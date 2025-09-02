#!/bin/bash

# 📱 Общий скрипт для отправки Telegram сообщений с поддержкой топиков
# Используется всеми компонентами системы мониторинга
# Автор: Smart Home Monitoring System
# Версия: 1.0

CONFIG_FILE="/etc/telegram-sender/config"

# Загрузка конфигурации
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] Config file not found: $CONFIG_FILE" >> "${TELEGRAM_LOG_FILE:-/var/log/telegram-sender.log}"
    exit 1
fi

# Установка переменных из конфига или значений по умолчанию
LOG_FILE="${TELEGRAM_LOG_FILE:-/var/log/telegram-sender.log}"
TIMEOUT="${TELEGRAM_TIMEOUT:-10}"
RETRY_COUNT="${TELEGRAM_RETRY_COUNT:-3}"
RETRY_DELAY="${TELEGRAM_RETRY_DELAY:-2}"
MAX_MESSAGE_LENGTH="${TELEGRAM_MAX_MESSAGE_LENGTH:-4096}"
MAX_PREVIEW_LENGTH="${TELEGRAM_MAX_PREVIEW_LENGTH:-100}"
DEFAULT_PARSE_MODE="${TELEGRAM_PARSE_MODE_DEFAULT:-HTML}"
LOG_LEVEL="${TELEGRAM_LOG_LEVEL:-INFO}"

# Функция логирования с информацией о вызывающем процессе
log_message() {
    local level="$1"
    local message="$2"
    local caller_process="${3:-$(ps -o comm= -p $PPID 2>/dev/null || echo 'unknown')}"
    local caller_pid="${4:-$PPID}"
    
    # Проверка уровня логирования
    case "$LOG_LEVEL" in
        "ERROR") [[ "$level" == "ERROR" ]] || return 0 ;;
        "WARN") [[ "$level" =~ ^(ERROR|WARN)$ ]] || return 0 ;;
        "INFO") [[ "$level" =~ ^(ERROR|WARN|INFO|SUCCESS)$ ]] || return 0 ;;
        "DEBUG") ;; # Логировать все
    esac
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] [PID:$caller_pid] [$caller_process] $message" >> "$LOG_FILE"
}

# Функция получения имени топика по ID
get_topic_name() {
    local topic_id="$1"
    case "$topic_id" in
        "$TELEGRAM_TOPIC_SYSTEM") echo "system" ;;
        "$TELEGRAM_TOPIC_ERRORS") echo "errors" ;;
        "$TELEGRAM_TOPIC_UPDATES") echo "updates" ;;
        "$TELEGRAM_TOPIC_RESTART") echo "restart" ;;
        "") echo "root" ;;
        *) echo "topic_$topic_id" ;;
    esac
}

# Основная функция отправки сообщения
send_telegram_message() {
    local message="$1"
    local topic_id="$2"  # Необязательный параметр
    local parse_mode="${3:-$DEFAULT_PARSE_MODE}"
    local caller_process="$(ps -o comm= -p $PPID 2>/dev/null || echo 'unknown')"
    local caller_pid="$PPID"
    
    # Проверка обязательных параметров
    if [[ -z "$message" ]]; then
        log_message "ERROR" "Message is empty" "$caller_process" "$caller_pid"
        echo "ERROR: Message cannot be empty"
        return 1
    fi
    
    if [[ -z "$TELEGRAM_BOT_TOKEN" ]] || [[ -z "$TELEGRAM_CHAT_ID" ]]; then
        log_message "ERROR" "Telegram credentials not configured" "$caller_process" "$caller_pid"
        echo "ERROR: Telegram credentials not configured"
        return 1
    fi
    
    # Обрезка сообщения если слишком длинное
    if [[ ${#message} -gt $MAX_MESSAGE_LENGTH ]]; then
        local truncated_message="${message:0:$((MAX_MESSAGE_LENGTH-50))}...\n\n[Сообщение обрезано: ${#message} символов]"
        log_message "WARN" "Message truncated from ${#message} to ${#truncated_message} characters" "$caller_process" "$caller_pid"
        message="$truncated_message"
    fi
    
    # Подготовка данных для отправки
    local curl_data="chat_id=$TELEGRAM_CHAT_ID"
    curl_data="$curl_data&text=$(echo "$message" | sed 's/&/%26/g; s/</%3C/g; s/>/%3E/g')"
    curl_data="$curl_data&parse_mode=$parse_mode"
    
    # Добавление дополнительных параметров
    if [[ "$TELEGRAM_DISABLE_NOTIFICATION" == "true" ]]; then
        curl_data="$curl_data&disable_notification=true"
    fi
    if [[ "$TELEGRAM_DISABLE_WEB_PAGE_PREVIEW" == "true" ]]; then
        curl_data="$curl_data&disable_web_page_preview=true"
    fi
    
    # Добавление топика если указан
    local topic_name="root"
    if [[ -n "$topic_id" ]]; then
        curl_data="$curl_data&message_thread_id=$topic_id"
        topic_name=$(get_topic_name "$topic_id")
    fi
    
    log_message "INFO" "Attempting to send message to topic '$topic_name' (ID: ${topic_id:-'none'})" "$caller_process" "$caller_pid"
    log_message "DEBUG" "Message preview: $(echo "$message" | head -c $MAX_PREVIEW_LENGTH)..." "$caller_process" "$caller_pid"
    
    # Отправка сообщения с повторными попытками
    local attempt=1
    while [[ $attempt -le $RETRY_COUNT ]]; do
        log_message "DEBUG" "Attempt $attempt/$RETRY_COUNT" "$caller_process" "$caller_pid"
        
        local response=$(curl -s -w "HTTP_CODE:%{http_code}" --max-time "$TIMEOUT" \
            -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
            -d "$curl_data" 2>&1)
        
        local http_code=$(echo "$response" | grep -o 'HTTP_CODE:[0-9]*' | cut -d: -f2)
        local json_response=$(echo "$response" | sed 's/HTTP_CODE:[0-9]*$//')
        
        # Обработка результата
        if [[ "$http_code" == "200" ]] && echo "$json_response" | grep -q '"ok":true'; then
            local message_id=$(echo "$json_response" | grep -o '"message_id":[0-9]*' | cut -d: -f2)
            log_message "SUCCESS" "Message sent successfully to topic '$topic_name' (message_id: $message_id, attempt: $attempt)" "$caller_process" "$caller_pid"
            return 0
        else
            local error_description=$(echo "$json_response" | grep -o '"description":"[^"]*"' | cut -d'"' -f4)
            log_message "WARN" "Attempt $attempt failed. HTTP: $http_code, Error: ${error_description:-'Unknown error'}" "$caller_process" "$caller_pid"
            
            if [[ $attempt -lt $RETRY_COUNT ]]; then
                log_message "INFO" "Retrying in $RETRY_DELAY seconds..." "$caller_process" "$caller_pid"
                sleep "$RETRY_DELAY"
            fi
        fi
        
        ((attempt++))
    done
    
    # Все попытки неудачны
    log_message "ERROR" "Failed to send message to topic '$topic_name' after $RETRY_COUNT attempts" "$caller_process" "$caller_pid"
    log_message "DEBUG" "Final response: $json_response" "$caller_process" "$caller_pid"
    return 1
}

# Основная логика (если скрипт запущен напрямую)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Создание лог-файла если не существует
    if [[ ! -f "$LOG_FILE" ]]; then
        touch "$LOG_FILE"
        chmod 644 "$LOG_FILE"
    fi
    
    case "${1:-}" in
        "")
            echo "ERROR: Message is required"
            echo "Usage: $0 <message> [topic_id] [parse_mode]"
            exit 1
            ;;
        *)
            send_telegram_message "$1" "$2" "$3"
            exit $?
            ;;
    esac
fi
