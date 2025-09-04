#!/bin/bash

# Пример модификации ha-watchdog.sh для использования logging-service
# Показывает как интегрировать стандартизированное логирование

LOG_FILE="/var/log/ha-watchdog.log"
FAILURE_FILE="/var/log/ha-failures.log"
CONFIG_FILE="/etc/ha-watchdog/config"

# Подключение centralized logging service (опционально)
LOGGING_SERVICE="/usr/local/bin/logging-service.sh"
if [[ -f "$LOGGING_SERVICE" ]]; then
    # Проверяем, что файл исполняемый и можем его источником
    if [[ -r "$LOGGING_SERVICE" ]]; then
        source "$LOGGING_SERVICE"
        USE_STRUCTURED_LOGGING=true
        echo "✅ Centralized logging service loaded"
    else
        echo "⚠️ Logging service found but not readable: $LOGGING_SERVICE"
        USE_STRUCTURED_LOGGING=false
    fi
else
    echo "ℹ️ Centralized logging service not found, using fallback logging"
    USE_STRUCTURED_LOGGING=false
fi

# Функция логирования с автоматическим выбором метода
log() {
    local message="$1"
    local level="${2:-INFO}"
    
    if [[ "$USE_STRUCTURED_LOGGING" == "true" ]]; then
        # Используем централизованный logging-service
        log_structured "ha-watchdog" "$level" "$message"
    else
        # Fallback на старый метод
        echo "$(date '+%F %T') [WATCHDOG] $message" >> "$LOG_FILE"
    fi
}

log_failure() {
    local message="$1"
    
    # Записываем в файл сбоев (как было)
    echo "$(date '+%F %T') $message" >> "$FAILURE_FILE"
    
    # И логируем через стандартный механизм
    log "FAILURE: $message" "ERROR"
}

# Пример использования:
check_internet() {
    local start_time=$(date +%s%3N)
    
    if ! ping -c 1 -W 2 "8.8.8.8" >/dev/null 2>&1; then
        log_failure "NO_INTERNET"
        return 1
    fi
    
    local end_time=$(date +%s%3N)
    local duration=$((end_time - start_time))
    
    # Логируем с метриками если доступно
    if [[ "$USE_STRUCTURED_LOGGING" == "true" ]]; then
        log_with_metrics "ha-watchdog" "INFO" "Internet check successful" "$duration"
    else
        log "Internet check successful (${duration}ms)" "INFO"
    fi
    
    return 0
}

check_memory() {
    local mem_available_mb=$(free -m | awk '/Mem:/ {print $7}')
    local mem_total_mb=$(free -m | awk '/Mem:/ {print $2}')
    local mem_usage_percent=$(( (mem_total_mb - mem_available_mb) * 100 / mem_total_mb ))
    
    if [[ "$mem_available_mb" -lt 80 ]]; then
        # Структурированное логирование с дополнительными данными
        if [[ "$USE_STRUCTURED_LOGGING" == "true" ]]; then
            local extra_data='{"mem_available_mb": '$mem_available_mb', "mem_usage_percent": '$mem_usage_percent'}'
            log_structured "ha-watchdog" "ERROR" "Low memory: ${mem_available_mb}MB available" "$extra_data"
        else
            log "Low memory: ${mem_available_mb}MB available (${mem_usage_percent}% used)" "ERROR"
        fi
        log_failure "LOW_MEMORY:${mem_available_mb}MB"
        return 1
    fi
    
    log "Memory OK: ${mem_available_mb}MB available (${mem_usage_percent}% used)" "INFO"
    return 0
}

# Основная логика
main() {
    log "Starting system health check" "INFO"
    
    local checks_passed=0
    local checks_total=0
    
    # Internet check
    ((checks_total++))
    if check_internet; then
        ((checks_passed++))
    fi
    
    # Memory check  
    ((checks_total++))
    if check_memory; then
        ((checks_passed++))
    fi
    
    # Итоговый отчет
    local success_rate=$(( checks_passed * 100 / checks_total ))
    
    if [[ "$USE_STRUCTURED_LOGGING" == "true" ]]; then
        local extra_data='{"checks_passed": '$checks_passed', "checks_total": '$checks_total', "success_rate": '$success_rate'}'
        log_structured "ha-watchdog" "INFO" "Health check completed" "$extra_data"
    else
        log "Health check completed: $checks_passed/$checks_total ($success_rate%)" "INFO"
    fi
}

main "$@"
