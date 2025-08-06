#!/bin/bash

# HA Failure Notifier с Telegram-уведомлениями
LOG_FILE="/var/log/ha-failures.log"
ACTION_LOG="/var/log/ha-failure-notifier.log"
HASH_FILE="/var/lib/ha-failure-notifier/hashes.txt"
CONFIG_FILE="/etc/ha-watchdog/config"
THROTTLE_FILE="/var/lib/ha-failure-notifier/throttle.txt"

# Загрузка конфигурации
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# Значения по умолчанию если не заданы в конфиге
THROTTLE_MINUTES=${THROTTLE_MINUTES:-60}

# Telegram настройки (должны быть в config файле)
# TELEGRAM_BOT_TOKEN="your_bot_token_here"
# TELEGRAM_CHAT_ID="your_chat_id_here"

# Инициализация
[[ ! -f "$HASH_FILE" ]] && mkdir -p "$(dirname "$HASH_FILE")" && touch "$HASH_FILE"
[[ ! -f "$THROTTLE_FILE" ]] && mkdir -p "$(dirname "$THROTTLE_FILE")" && touch "$THROTTLE_FILE"

log_action() {
    echo "$(date '+%F %T') [FAILURE-NOTIFIER] $1" >> "$ACTION_LOG"
}

send_telegram() {
    local message="$1"
    local priority="${2:-normal}"
    
    if [[ -z "$TELEGRAM_BOT_TOKEN" ]] || [[ -z "$TELEGRAM_CHAT_ID" ]]; then
        log_action "TELEGRAM_NOT_CONFIGURED: $message"
        return 1
    fi
    
    # Добавляем эмодзи в зависимости от приоритета
    case "$priority" in
        "critical") message="🚨 КРИТИЧНО: $message" ;;
        "warning") message="⚠️ ВНИМАНИЕ: $message" ;;
        "info") message="ℹ️ ИНФО: $message" ;;
        *) message="📊 $message" ;;
    esac
    
    local hostname=$(hostname)
    local full_message="[$hostname] $message"
    
    if curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
        -d "chat_id=$TELEGRAM_CHAT_ID" \
        -d "text=$full_message" \
        -d "parse_mode=HTML" >/dev/null 2>&1; then
        log_action "TELEGRAM_SENT: $message"
        return 0
    else
        log_action "TELEGRAM_FAILED: $message"
        return 1
    fi
}

is_throttled() {
    local event_type="$1"
    local throttle_minutes="${2:-5}"
    local current_time=$(date +%s)
    
    # Читаем время последней отправки для этого типа события
    local last_sent=$(grep "^$event_type:" "$THROTTLE_FILE" 2>/dev/null | cut -d: -f2)
    
    if [[ -n "$last_sent" ]] && (( current_time - last_sent < throttle_minutes * 60 )); then
        return 0  # throttled
    else
        # Обновляем время последней отправки
        grep -v "^$event_type:" "$THROTTLE_FILE" > "$THROTTLE_FILE.tmp" 2>/dev/null || touch "$THROTTLE_FILE.tmp"
        echo "$event_type:$current_time" >> "$THROTTLE_FILE.tmp"
        mv "$THROTTLE_FILE.tmp" "$THROTTLE_FILE"
        return 1  # not throttled
    fi
}

restart_container() {
    local name="$1"
    if docker restart "$name" >/dev/null 2>&1; then
        log_action "RESTARTED: container $name"
        send_telegram "Контейнер $name был перезапущен" "warning"
        return 0
    else
        log_action "RESTART_FAILED: container $name"
        send_telegram "Не удалось перезапустить контейнер $name" "critical"
        return 1
    fi
}

restart_interface() {
    local iface="$1"
    local throttle_key="IFACE_RESTART_$iface"
    
    if is_throttled "$throttle_key" 5; then
        log_action "THROTTLED: $iface restart skipped (< 5 min)"
        return 1
    fi
    
    if ip link set "$iface" down && sleep 2 && ip link set "$iface" up; then
        log_action "RESTARTED: interface $iface"
        send_telegram "Сетевой интерфейс $iface был перезапущен" "warning"
        return 0
    else
        log_action "RESTART_FAILED: interface $iface"
        send_telegram "Не удалось перезапустить интерфейс $iface" "critical"
        return 1
    fi
}

process_failure() {
    local line="$1"
    local event_type
    local message
    local priority="warning"
    local should_throttle=false
    local throttle_minutes=5
    
    case "$line" in
        *"NO_INTERNET"*)
            event_type="NO_INTERNET"
            message="Интернет недоступен"
            should_throttle=true
            throttle_minutes=10
            ;;
        *"GATEWAY_DOWN"*)
            event_type="GATEWAY_DOWN"
            message="Шлюз не отвечает"
            should_throttle=true
            throttle_minutes=10
            ;;
        *"DOCKER_DAEMON_DOWN"*)
            event_type="DOCKER_DAEMON_DOWN"
            message="Docker daemon не работает"
            priority="critical"
            should_throttle=true
            throttle_minutes=15
            ;;
        *"HA_DOWN"*)
            event_type="HA_DOWN"
            message="Home Assistant недоступен"
            priority="critical"
            ;;
        *"CONTAINER_DOWN:"*)
            local name=$(echo "$line" | sed 's/.*CONTAINER_DOWN://' | cut -d' ' -f1)
            event_type="CONTAINER_DOWN_$name"
            restart_container "$name"
            return
            ;;
        *"IFACE_DOWN:"*)
            local iface=$(echo "$line" | sed 's/.*IFACE_DOWN://' | cut -d' ' -f1)
            event_type="IFACE_DOWN_$iface"
            restart_interface "$iface"
            return
            ;;
        *"LOW_MEMORY:"*)
            local mem=$(echo "$line" | sed 's/.*LOW_MEMORY://' | cut -d' ' -f1)
            event_type="LOW_MEMORY"
            message="Мало свободной памяти: $mem"
            priority="critical"
            should_throttle=true
            throttle_minutes=30
            ;;
        *"LOW_DISK:"*)
            local disk=$(echo "$line" | sed 's/.*LOW_DISK://' | cut -d' ' -f1)
            event_type="LOW_DISK"
            message="Мало места на диске: $disk"
            priority="critical"
            should_throttle=true
            throttle_minutes=60
            ;;
        *"HIGH_TEMP:"*)
            local temp=$(echo "$line" | sed 's/.*HIGH_TEMP://' | cut -d' ' -f1)
            event_type="HIGH_TEMP"
            message="Высокая температура CPU: $temp"
            priority="critical"
            should_throttle=true
            throttle_minutes=15
            ;;
        *"HA_SERVICE_DOWN"*)
            event_type="HA_SERVICE_DOWN"
            message="Сервис Home Assistant не отвечает на порту 8123"
            priority="critical"
            ;;
        *"NODERED_SERVICE_DOWN"*)
            event_type="NODERED_SERVICE_DOWN"
            message="Сервис Node-RED не отвечает на порту 1880"
            ;;
        *"HIGH_LOAD:"*)
            local load=$(echo "$line" | sed 's/.*HIGH_LOAD://' | cut -d' ' -f1)
            event_type="HIGH_LOAD"
            message="Высокая нагрузка на систему: $load"
            should_throttle=true
            throttle_minutes=10
            ;;
        *"SSH_DOWN:"*)
            event_type="SSH_DOWN"
            message="SSH сервис недоступен"
            priority="critical"
            should_throttle=true
            throttle_minutes=15
            ;;
        *"TAILSCALE_"*)
            event_type="TAILSCALE_ISSUE"
            message="Проблема с Tailscale VPN"
            priority="critical"
            should_throttle=true
            throttle_minutes=20
            ;;
        *"HA_DATABASE_"*)
            event_type="HA_DATABASE"
            message="Проблема с базой данных Home Assistant"
            priority="critical"
            should_throttle=true
            throttle_minutes=60
            ;;
        *"HIGH_SWAP_USAGE:"*)
            local swap=$(echo "$line" | sed 's/.*HIGH_SWAP_USAGE://' | cut -d' ' -f1)
            event_type="HIGH_SWAP"
            message="Высокое использование swap: $swap"
            priority="warning"
            should_throttle=true
            throttle_minutes=30
            ;;
        *"WEAK_WIFI_SIGNAL:"*)
            local signal=$(echo "$line" | sed 's/.*WEAK_WIFI_SIGNAL://' | cut -d' ' -f1)
            event_type="WEAK_WIFI"
            message="Слабый WiFi сигнал: $signal"
            should_throttle=true
            throttle_minutes=60
            ;;
        *"UNDERVOLTAGE_DETECTED"*)
            event_type="UNDERVOLTAGE"
            message="Обнаружено пониженное напряжение питания"
            priority="critical"
            should_throttle=true
            throttle_minutes=30
            ;;
        *"CPU_THROTTLED"*)
            event_type="CPU_THROTTLED"
            message="CPU регулируется из-за температуры/питания"
            priority="critical"
            should_throttle=true
            throttle_minutes=20
            ;;
        *"NTP_NOT_SYNCED"*)
            event_type="NTP_SYNC"
            message="Время не синхронизировано через NTP"
            should_throttle=true
            throttle_minutes=120
            ;;
        *"LOG_OVERSIZED:"*)
            event_type="LOG_OVERSIZED"
            message="Лог файл превысил допустимый размер"
            should_throttle=true
            throttle_minutes=240
            ;;
        *)
            event_type="UNKNOWN"
            message="Неизвестная проблема: $line"
            ;;
    esac
    
    # Проверяем throttling
    if [[ "$should_throttle" == true ]] && is_throttled "$event_type" "$throttle_minutes"; then
        log_action "THROTTLED: $event_type (< $throttle_minutes min)"
        return
    fi
    
    # Отправляем уведомление
    send_telegram "$message" "$priority"
    log_action "PROCESSED: $event_type - $message"
}

# Основная функция
main() {
    log_action "Starting failure processing..."
    
    if [[ ! -f "$LOG_FILE" ]]; then
        log_action "Failure log file not found: $LOG_FILE"
        return 1
    fi
    
    local last_hash=$(cat "$HASH_FILE" 2>/dev/null)
    local start_processing=0
    local processed_lines=0
    local hash_found=0
    local current_hash=""
    
    # Определяем режим работы
    if [[ -z "$last_hash" ]]; then
        log_action "First run - no previous hash found, processing all existing failures"
        start_processing=1
    else
        log_action "Resuming from last hash: ${last_hash:0:8}..."
    fi
    
    while IFS= read -r line; do
        # Пропускаем пустые строки и строки без временной метки
        [[ -z "$line" || "$line" != *" "* ]] && continue
        
        current_hash=$(echo -n "$line" | sha256sum | cut -d ' ' -f1)
        
        # Если есть last_hash, ищем его в файле
        if [[ -n "$last_hash" ]] && [[ "$start_processing" -eq 0 ]]; then
            if [[ "$current_hash" == "$last_hash" ]]; then
                hash_found=1
                start_processing=1
                log_action "Found last processed hash, resuming from next line"
                continue  # Пропускаем уже обработанную строку
            fi
            continue
        fi
        
        # Обрабатываем новые строки
        if [[ "$start_processing" -eq 1 ]]; then
            process_failure "$line"
            ((processed_lines++))
        fi
        
    done < "$LOG_FILE"
    
    # Если искали hash но не нашли, это новый лог файл
    if [[ -n "$last_hash" ]] && [[ "$hash_found" -eq 0 ]]; then
        log_action "Previous hash not found - log file was rotated/recreated, processing all failures"
        processed_lines=0
        while IFS= read -r line; do
            [[ -z "$line" || "$line" != *" "* ]] && continue
            current_hash=$(echo -n "$line" | sha256sum | cut -d ' ' -f1)
            process_failure "$line"
            ((processed_lines++))
        done < "$LOG_FILE"
    fi
    
    # Сохраняем только последний hash
    if [[ -n "$current_hash" ]]; then
        echo "$current_hash" > "$HASH_FILE"
        log_action "Saved last hash: ${current_hash:0:8}..."
    fi
    
    log_action "Processed $processed_lines new failure(s)"
}

main "$@"
