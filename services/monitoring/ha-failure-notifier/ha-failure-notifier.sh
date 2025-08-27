#!/bin/bash

# HA Failure Notifier v3.0 с timestamp-based tracking
LOG_FILE="/var/log/ha-failures.log"
ACTION_LOG="/var/log/ha-failure-notifier.log"
HASH_FILE="/var/lib/ha-failure-notifier/hashes.txt"
POSITION_FILE="/var/lib/ha-failure-notifier/position.txt"
METADATA_FILE="/var/lib/ha-failure-notifier/metadata.txt"
TIMESTAMP_FILE="/var/lib/ha-failure-notifier/last_timestamp.txt"
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
[[ ! -f "$POSITION_FILE" ]] && mkdir -p "$(dirname "$POSITION_FILE")" && echo "0" > "$POSITION_FILE"
[[ ! -f "$METADATA_FILE" ]] && mkdir -p "$(dirname "$METADATA_FILE")" && touch "$METADATA_FILE"
[[ ! -f "$TIMESTAMP_FILE" ]] && mkdir -p "$(dirname "$TIMESTAMP_FILE")" && echo "0" > "$TIMESTAMP_FILE"
[[ ! -f "$THROTTLE_FILE" ]] && mkdir -p "$(dirname "$THROTTLE_FILE")" && touch "$THROTTLE_FILE"

log_action() {
    echo "$(date '+%F %T') [FAILURE-NOTIFIER] $1" >> "$ACTION_LOG"
}

# Извлечь timestamp из строки лога
extract_timestamp() {
    local line="$1"
    # Ожидаем формат: YYYY-MM-DD HH:MM:SS
    if [[ "$line" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}) ]]; then
        local datetime="${BASH_REMATCH[1]}"
        # Конвертируем в Unix timestamp
        date -d "$datetime" +%s 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Проверить, новее ли событие чем последний обработанный timestamp
is_event_newer() {
    local event_timestamp="$1"
    local last_timestamp="$2"
    
    # Если timestamps некорректны, считаем событие новым
    [[ "$event_timestamp" == "0" ]] && return 0
    [[ "$last_timestamp" == "0" ]] && return 0
    
    # Событие новое если его timestamp больше последнего обработанного
    (( event_timestamp > last_timestamp ))
}

# Получить метаданные файла
get_file_metadata() {
    local file="$1"
    if [[ -f "$file" ]]; then
        # Возвращаем: размер:время_создания:время_модификации:хеш_первой_строки
        local size=$(stat -c%s "$file" 2>/dev/null || echo "0")
        local ctime=$(stat -c%Z "$file" 2>/dev/null || echo "0")  # время изменения inode (создания/ротации)
        local mtime=$(stat -c%Y "$file" 2>/dev/null || echo "0")  # время модификации содержимого
        local first_line_hash=""
        
        if [[ -s "$file" ]]; then
            first_line_hash=$(head -n1 "$file" 2>/dev/null | sha256sum | cut -d' ' -f1)
        fi
        
        echo "${size}:${ctime}:${mtime}:${first_line_hash}"
    else
        echo "0:0:0:"
    fi
}

# Проверить, был ли файл ротирован
is_file_rotated() {
    local current_metadata="$1"
    local saved_metadata="$2"
    
    # Парсим метаданные: размер:время_создания:время_модификации:хеш_первой_строки
    IFS=':' read -r curr_size curr_ctime curr_mtime curr_hash <<< "$current_metadata"
    IFS=':' read -r saved_size saved_ctime saved_mtime saved_hash <<< "$saved_metadata"
    
    # Файл ротирован если:
    # 1. Хеш первой строки изменился (файл заменен)
    # 2. Размер файла стал меньше предыдущего (файл усечен/пересоздан)
    # 3. Время создания файла изменилось (файл пересоздан при ротации)
    # 4. Время создания новее времени модификации (новый файл)
    
    if [[ -n "$saved_hash" && -n "$curr_hash" && "$curr_hash" != "$saved_hash" ]]; then
        log_action "ROTATION DETECTED: First line hash changed ($saved_hash -> $curr_hash)"
        return 0
    fi
    
    if [[ "$curr_size" -lt "$saved_size" ]]; then
        log_action "ROTATION DETECTED: File size decreased ($saved_size -> $curr_size)"
        return 0
    fi
    
    # Проверяем время создания файла (inode change time)
    if [[ -n "$saved_ctime" && -n "$curr_ctime" && "$curr_ctime" != "$saved_ctime" ]]; then
        # Если время создания изменилось И новое время создания больше старого времени модификации
        # это значит файл был пересоздан
        if [[ "$curr_ctime" -gt "$saved_mtime" ]]; then
            log_action "ROTATION DETECTED: File creation time changed ($saved_ctime -> $curr_ctime)"
            return 0
        fi
    fi
    
    # Дополнительная проверка: если время создания больше времени модификации
    # это может означать новый файл
    if [[ -n "$curr_ctime" && -n "$curr_mtime" && "$curr_ctime" -gt "$curr_mtime" ]]; then
        local time_diff=$((curr_ctime - curr_mtime))
        # Если разница больше 60 секунд, вероятно файл был создан заново
        if [[ "$time_diff" -gt 60 ]]; then
            log_action "ROTATION DETECTED: Creation time > modification time (diff: ${time_diff}s)"
            return 0
        fi
    fi
    
    return 1
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
    local event_timestamp="$2"
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
            # Не перезапускаем интерфейс автоматически - создает много шума
            if [[ "$iface" == "wlan0" ]]; then
                log_action "IGNORED: $iface down (auto-restart disabled)"
                return
            else
                restart_interface "$iface"
                return
            fi
            ;;
        *"LOW_MEMORY:"*)
            local mem=$(echo "$line" | sed 's/.*LOW_MEMORY://' | cut -d' ' -f1)
            event_type="LOW_MEMORY"
            message="Мало свободной памяти: $mem"
            priority="critical"
            should_throttle=true
            throttle_minutes=60
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
        *"TAILSCALE_DAEMON_DOWN"*)
            event_type="TAILSCALE_DAEMON"
            message="Tailscale демон не работает"
            priority="critical"
            should_throttle=true
            throttle_minutes=15
            ;;
        *"TAILSCALE_VPN_DOWN"*)
            event_type="TAILSCALE_VPN"
            message="Tailscale VPN подключение недоступно"
            priority="critical"
            should_throttle=true
            throttle_minutes=15
            ;;
        *"TAILSCALE_FUNNEL_DOWN"*)
            event_type="TAILSCALE_FUNNEL"
            message="Tailscale Funnel сервис не работает"
            priority="warning"
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
        *"SD_CARD_ERRORS"*)
            event_type="SD_CARD_ERRORS"
            message="Ошибки SD карты обнаружены"
            priority="critical"
            should_throttle=true
            throttle_minutes=60
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
    
    # Сохраняем timestamp последнего обработанного события
    if [[ "$event_timestamp" != "0" ]]; then
        echo "$event_timestamp" > "$TIMESTAMP_FILE"
        log_action "TIMESTAMP_UPDATED: $event_timestamp"
    fi
}

# Основная функция с timestamp-based алгоритмом
main() {
    log_action "Starting failure processing (v3.0 timestamp-based)..."
    
    if [[ ! -f "$LOG_FILE" ]]; then
        log_action "Failure log file not found: $LOG_FILE"
        return 1
    fi
    
    local total_lines=$(wc -l < "$LOG_FILE")
    local last_timestamp=$(cat "$TIMESTAMP_FILE" 2>/dev/null || echo "0")
    local current_metadata=$(get_file_metadata "$LOG_FILE")
    local saved_metadata=$(cat "$METADATA_FILE" 2>/dev/null || echo "")
    local processed_events=0
    local newest_timestamp="$last_timestamp"
    
    log_action "Log file has $total_lines lines, last processed timestamp: $last_timestamp"
    log_action "Current metadata: $current_metadata"
    log_action "Saved metadata: $saved_metadata"
    
    # Проверяем, был ли файл ротирован (для информации)
    local file_rotated=false
    if [[ -n "$saved_metadata" ]] && is_file_rotated "$current_metadata" "$saved_metadata"; then
        file_rotated=true
        log_action "File rotation detected, but processing by timestamp"
    fi
    
    # Обрабатываем ВСЕ строки в файле, но отправляем только новые по timestamp
    if (( total_lines > 0 )); then
        log_action "Processing all $total_lines lines, filtering by timestamp > $last_timestamp"
        
        while IFS= read -r line; do
            # Пропускаем пустые строки и строки без временной метки
            [[ -z "$line" || "$line" != *" "* ]] && continue
            
            # Извлекаем timestamp из строки
            local event_timestamp=$(extract_timestamp "$line")
            
            # Обрабатываем только события новее последнего обработанного
            if is_event_newer "$event_timestamp" "$last_timestamp"; then
                process_failure "$line" "$event_timestamp"
                ((processed_events++))
                
                # Обновляем самый новый timestamp
                if (( event_timestamp > newest_timestamp )); then
                    newest_timestamp="$event_timestamp"
                fi
            else
                # Логируем пропущенные старые события (для отладки)
                if [[ "$event_timestamp" != "0" ]]; then
                    log_action "SKIPPED_OLD: timestamp $event_timestamp <= $last_timestamp"
                fi
            fi
        done < "$LOG_FILE"
        
        # Сохраняем метаданные и самый новый timestamp
        echo "$current_metadata" > "$METADATA_FILE"
        if [[ "$newest_timestamp" != "$last_timestamp" ]]; then
            echo "$newest_timestamp" > "$TIMESTAMP_FILE"
            log_action "Updated newest timestamp to $newest_timestamp, processed $processed_events new event(s)"
        else
            log_action "No new events found (all timestamps <= $last_timestamp)"
        fi
        
        # Если файл был ротирован, отправляем уведомление
        if [[ "$file_rotated" == true ]]; then
            send_telegram "Лог файл был ротирован, обработаны события по timestamp" "info"
        fi
    else
        log_action "Log file is empty"
        # Обновляем метаданные даже если файл пуст
        echo "$current_metadata" > "$METADATA_FILE"
    fi
}

main "$@"
