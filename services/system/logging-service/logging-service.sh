#!/bin/bash

# 📝 Централизованный сервис структурированного логирования
# Используется для единообразного форматирования и ротации логов
# Автор: Smart Home Monitoring System
# Версия: 1.0

CONFIG_FILE="/etc/logging-service/config"

# Загрузка конфигурации
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] Config file not found: $CONFIG_FILE" >&2
    exit 1
fi

# Значения по умолчанию
LOG_FORMAT="${LOG_FORMAT:-plain}"  # plain, json, syslog
MAX_MESSAGE_LENGTH="${MAX_MESSAGE_LENGTH:-2048}"
ENABLE_REMOTE_LOGGING="${ENABLE_REMOTE_LOGGING:-false}"

# Специальный лог для самого logging-service (избегаем рекурсии)
LOGGING_SERVICE_LOG="${LOGGING_SERVICE_LOG:-/var/log/logging-service.log}"
ENABLE_SELF_LOGGING="${ENABLE_SELF_LOGGING:-true}"
SELF_LOG_LEVEL="${SELF_LOG_LEVEL:-INFO}"

# Функция прямого логирования для logging-service (без рекурсии)
log_self() {
    local level="$1"
    local message="$2"
    
    # Проверяем, включено ли самологирование и соответствует ли уровень
    if [[ "$ENABLE_SELF_LOGGING" != "true" ]]; then
        return 0
    fi
    
    # Фильтрация по уровню самологирования
    case "$SELF_LOG_LEVEL" in
        "ERROR") [[ "$level" == "ERROR" ]] || return 0 ;;
        "WARN") [[ "$level" =~ ^(ERROR|WARN)$ ]] || return 0 ;;
        "INFO") [[ "$level" =~ ^(ERROR|WARN|INFO)$ ]] || return 0 ;;
        "DEBUG") ;; # Логировать всё
    esac
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local hostname=$(hostname)
    local pid=$$
    
    # Простой формат для самологирования
    echo "$timestamp [$level] [logging-service] [PID:$pid] $message" >> "$LOGGING_SERVICE_LOG"
}

# Функция структурированного логирования
log_structured() {
    local service="$1"
    local level="$2"     # DEBUG, INFO, WARN, ERROR, CRITICAL
    local message="$3"
    local extra_data="$4"  # JSON string для дополнительных данных
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local hostname=$(hostname)
    local pid=$$
    local caller_pid="$PPID"
    local caller_process="$(ps -o comm= -p $PPID 2>/dev/null || echo 'unknown')"
    
    # Обрезка сообщения если слишком длинное
    if [[ ${#message} -gt $MAX_MESSAGE_LENGTH ]]; then
        message="${message:0:$((MAX_MESSAGE_LENGTH-20))}...[TRUNCATED]"
    fi
    
    case "$LOG_FORMAT" in
        "json")
            local log_entry=$(cat <<EOF
{
  "timestamp": "$timestamp",
  "hostname": "$hostname",
  "service": "$service",
  "level": "$level",
  "message": "$message",
  "pid": $pid,
  "caller_pid": $caller_pid,
  "caller_process": "$caller_process"$([ -n "$extra_data" ] && echo ",\"extra\": $extra_data" || echo "")
}
EOF
            )
            ;;
        "syslog")
            # RFC 3164 format
            local facility="16"  # local0
            local severity=$(get_syslog_severity "$level")
            local priority=$((facility * 8 + severity))
            log_entry="<$priority>$timestamp $hostname $service[$pid]: [$level] $message"
            ;;
        *)
            # Plain format (default)
            log_entry="$timestamp [$level] [$service] [PID:$pid] [$caller_process] $message"
            ;;
    esac
    
    # Определение лог-файла для сервиса
    local log_file=$(get_log_file "$service")
    
    # Самологирование важных событий (без рекурсии)
    if [[ "$level" == "ERROR" ]] || [[ "$level" == "CRITICAL" ]]; then
        log_self "INFO" "Processing $level event from $service: $message"
    fi
    
    # Запись в файл
    echo "$log_entry" >> "$log_file"
    
    # Проверка успешности записи
    if [[ $? -ne 0 ]]; then
        log_self "ERROR" "Failed to write to log file: $log_file"
        return 1
    fi
    
    # Удаленное логирование (если включено)
    if [[ "$ENABLE_REMOTE_LOGGING" == "true" ]] && [[ -n "$REMOTE_LOG_ENDPOINT" ]]; then
        log_self "DEBUG" "Sending log to remote endpoint: $REMOTE_LOG_ENDPOINT"
        send_remote_log "$log_entry" "$service" "$level" &
    fi
    
    # Уведомления для критических событий
    if [[ "$level" == "CRITICAL" ]] && [[ -n "$CRITICAL_NOTIFICATION_COMMAND" ]]; then
        log_self "INFO" "Sending critical notification for: $service"
        $CRITICAL_NOTIFICATION_COMMAND "$service" "$message" &
    fi
}

# Определение лог-файла по сервису
# ✅ ВАЖНО: Каждый сервис = отдельный лог-файл (НЕ централизация!)
# Это сделано для сохранения индивидуальности и удобства анализа
get_log_file() {
    local service="$1"
    case "$service" in
        "ha-watchdog") echo "/var/log/ha-watchdog.log" ;;              # ✅ Индивидуальный лог для мониторинга
        "ha-failure-notifier") echo "/var/log/ha-failure-notifier.log" ;; # ✅ Индивидуальный лог для сбоев
        "telegram-sender") echo "/var/log/telegram-sender.log" ;;      # ✅ Индивидуальный лог для Telegram
        "update-checker") echo "/var/log/ha-update-checker.log" ;;     # ✅ Индивидуальный лог для обновлений
        "nightly-reboot") echo "/var/log/ha-reboot.log" ;;             # ✅ Индивидуальный лог для перезагрузок
        *) echo "/var/log/ha-${service}.log" ;;                        # ✅ Паттерн для новых сервисов
    esac
}

# Преобразование уровня в syslog severity
get_syslog_severity() {
    case "$1" in
        "DEBUG") echo "7" ;;
        "INFO") echo "6" ;;
        "WARN") echo "4" ;;
        "ERROR") echo "3" ;;
        "CRITICAL") echo "2" ;;
        *) echo "6" ;;
    esac
}

# Отправка на удаленный лог-сервер
send_remote_log() {
    local log_entry="$1"
    local service="$2"
    local level="$3"
    
    if [[ -n "$REMOTE_LOG_ENDPOINT" ]]; then
        local response=$(curl -s --max-time 5 \
             -H "Content-Type: application/json" \
             -d "$log_entry" \
             -w "HTTP_CODE:%{http_code}" \
             "$REMOTE_LOG_ENDPOINT" 2>&1)
             
        local http_code=$(echo "$response" | grep -o 'HTTP_CODE:[0-9]*' | cut -d: -f2)
        
        if [[ "$http_code" == "200" ]] || [[ "$http_code" == "201" ]]; then
            log_self "DEBUG" "Remote log sent successfully for $service (HTTP: $http_code)"
        else
            log_self "WARN" "Remote log failed for $service (HTTP: $http_code)"
        fi
    fi
}

# Функция для простого логирования (обратная совместимость)
log_simple() {
    local service="$1"
    local message="$2"
    local level="${3:-INFO}"
    
    log_structured "$service" "$level" "$message"
}

# Функция для логирования с метриками
log_with_metrics() {
    local service="$1"
    local level="$2"
    local message="$3"
    local duration="$4"
    local status_code="$5"
    
    local extra_data=""
    if [[ -n "$duration" ]] || [[ -n "$status_code" ]]; then
        extra_data="{"
        [[ -n "$duration" ]] && extra_data+='"duration_ms": '$duration
        [[ -n "$duration" && -n "$status_code" ]] && extra_data+=', '
        [[ -n "$status_code" ]] && extra_data+='"status_code": '$status_code
        extra_data+="}"
    fi
    
    log_structured "$service" "$level" "$message" "$extra_data"
}

# Основная логика (если скрипт запущен напрямую)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Создание лог-файла для самого logging-service если не существует
    if [[ ! -f "$LOGGING_SERVICE_LOG" ]]; then
        mkdir -p "$(dirname "$LOGGING_SERVICE_LOG")" 2>/dev/null
        touch "$LOGGING_SERVICE_LOG"
        chmod 644 "$LOGGING_SERVICE_LOG"
        log_self "INFO" "Logging service initialized, log file created: $LOGGING_SERVICE_LOG"
    fi
    
    case "${1:-}" in
        "")
            echo "ERROR: Parameters required"
            echo "Usage: $0 <service> <level> <message> [extra_json]"
            echo "   or: $0 simple <service> <message> [level]"
            echo "   or: $0 metrics <service> <level> <message> <duration_ms> [status_code]"
            log_self "WARN" "Called without parameters"
            exit 1
            ;;
        "simple")
            log_self "DEBUG" "Processing simple log call for service: $2"
            log_simple "$2" "$3" "$4"
            ;;
        "metrics")
            log_self "DEBUG" "Processing metrics log call for service: $2"
            log_with_metrics "$2" "$3" "$4" "$5" "$6"
            ;;
        *)
            log_self "DEBUG" "Processing structured log call for service: $1"
            log_structured "$1" "$2" "$3" "$4"
            ;;
    esac
    
    log_self "DEBUG" "Log processing completed successfully"
fi
