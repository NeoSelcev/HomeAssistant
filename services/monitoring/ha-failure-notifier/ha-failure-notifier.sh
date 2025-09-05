#!/bin/bash

# HA Failure Notifier v3.1 with smart priority-based throttling
LOG_FILE="/var/log/ha-failures.log"
ACTION_LOG="/var/log/ha-failure-notifier.log"
HASH_FILE="/var/lib/ha-failure-notifier/hashes.txt"
POSITION_FILE="/var/lib/ha-failure-notifier/position.txt"
METADATA_FILE="/var/lib/ha-failure-notifier/metadata.txt"
TIMESTAMP_FILE="/var/lib/ha-failure-notifier/last_timestamp.txt"
CONFIG_FILE="/etc/ha-watchdog/config"
THROTTLE_FILE="/var/lib/ha-failure-notifier/throttle.txt"

# Load configuration
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# Default values if not set in config
THROTTLE_MINUTES=${THROTTLE_MINUTES:-60}

# Smart limits by event types (v3.1)
CRITICAL_EVENTS_LIMIT=20      # HA_SERVICE_DOWN, MEMORY_CRITICAL
HIGH_LOAD_EVENTS_LIMIT=10     # HIGH_LOAD
WARNING_EVENTS_LIMIT=5        # MEMORY_WARNING, DISK_WARNING
INFO_EVENTS_LIMIT=3           # Other events
THROTTLE_WINDOW_MINUTES=30    # Window for counting repetitions

# Telegram settings (should be in config file)
# TELEGRAM_BOT_TOKEN="your_bot_token_here"
# TELEGRAM_CHAT_ID="your_chat_id_here"

# Telegram sender service
TELEGRAM_SENDER="/usr/local/bin/telegram-sender.sh"
LOGGING_SERVICE="/usr/local/bin/logging-service.sh"

# Initialization
[[ ! -f "$HASH_FILE" ]] && mkdir -p "$(dirname "$HASH_FILE")" && touch "$HASH_FILE"
[[ ! -f "$POSITION_FILE" ]] && mkdir -p "$(dirname "$POSITION_FILE")" && echo "0" > "$POSITION_FILE"
[[ ! -f "$METADATA_FILE" ]] && mkdir -p "$(dirname "$METADATA_FILE")" && touch "$METADATA_FILE"
[[ ! -f "$TIMESTAMP_FILE" ]] && mkdir -p "$(dirname "$TIMESTAMP_FILE")" && echo "0" > "$TIMESTAMP_FILE"
[[ ! -f "$THROTTLE_FILE" ]] && mkdir -p "$(dirname "$THROTTLE_FILE")" && touch "$THROTTLE_FILE"

# Connect centralized logging service (REQUIRED)
if [[ -f "$LOGGING_SERVICE" ]] && [[ -r "$LOGGING_SERVICE" ]]; then
    source "$LOGGING_SERVICE" 2>/dev/null
    if ! command -v log_structured >/dev/null 2>&1; then
        echo "ERROR: logging-service loaded, but log_structured function is not available" >&2
        exit 1
    fi
else
    echo "ERROR: Centralized logging-service not found: $LOGGING_SERVICE" >&2
    exit 1
fi

log_action() {
    local message="$1"
    local level="${2:-INFO}"
    log_structured "ha-failure-notifier" "$level" "$message"
}

# Extract timestamp from log line (updated for logging-service format)
extract_timestamp() {
    local line="$1"
    # Support formats:
    # New logging-service: "YYYY-MM-DD HH:MM:SS [ERROR] [ha-watchdog] [PID:123] FAILURE: message"
    # Old format: "YYYY-MM-DD HH:MM:SS [WATCHDOG] message" 
    # Very old format: "YYYY-MM-DD HH:MM:SS message"
    if [[ "$line" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}) ]]; then
        local datetime="${BASH_REMATCH[1]}"
        # Convert to Unix timestamp
        date -d "$datetime" +%s 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Extract failure type from line (updated for new format)
extract_failure_type() {
    local line="$1"
    # New format: "YYYY-MM-DD HH:MM:SS [ERROR] [ha-watchdog] [PID:123] FAILURE: SOME_FAILURE_TYPE"
    if [[ "$line" =~ FAILURE:\ ([A-Z_][A-Z0-9_:]*) ]]; then
        echo "${BASH_REMATCH[1]}"
    # Old format: "YYYY-MM-DD HH:MM:SS [WATCHDOG] SOME_FAILURE_TYPE"  
    elif [[ "$line" =~ \[WATCHDOG\]\ ([A-Z_][A-Z0-9_:]*) ]]; then
        echo "${BASH_REMATCH[1]}"
    # Very old format: "YYYY-MM-DD HH:MM:SS SOME_FAILURE_TYPE"
    elif [[ "$line" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}\ ([A-Z_][A-Z0-9_:]*) ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo "UNKNOWN_FAILURE"
    fi
}

# Determine if event is newer than last processed timestamp
is_event_newer() {
    local event_timestamp="$1"
    local last_timestamp="$2"
    
    # If timestamps are invalid treat event as new
    [[ "$event_timestamp" == "0" ]] && return 0
    [[ "$last_timestamp" == "0" ]] && return 0
    
    # Event is new if its timestamp is greater than last processed
    (( event_timestamp > last_timestamp ))
}

# Determine event priority for smart throttling (v3.1)
get_event_priority() {
    local event_type="$1"
    
    case "$event_type" in
        *"HA_SERVICE_DOWN"* | *"MEMORY_CRITICAL"* | *"DISK_CRITICAL"*)
            echo "critical" ;;
        *"HIGH_LOAD"* | *"CONNECTION_LOST"*)
            echo "high" ;;
        *"MEMORY_WARNING"* | *"DISK_WARNING"*)
            echo "warning" ;;
        *)
            echo "info" ;;
    esac
}

# Check whether to throttle event using smart algorithm (v3.1)
should_throttle_smart() {
    local event_type="$1"
    local event_timestamp="$2"
    local priority=$(get_event_priority "$event_type")
    
    # Count events of this type within last throttling window
    local window_start=$((event_timestamp - THROTTLE_WINDOW_MINUTES * 60))
    local count=0
    
    if [[ -f "$THROTTLE_FILE" ]]; then
        count=$(awk -F: -v window="$window_start" -v type="$event_type" \
                   '$1 >= window && $0 ~ type' "$THROTTLE_FILE" 2>/dev/null | wc -l)
    fi
    
    # Enforce per-priority limits
    case "$priority" in
        "critical") [[ "$count" -ge "$CRITICAL_EVENTS_LIMIT" ]] ;;
        "high")     [[ "$count" -ge "$HIGH_LOAD_EVENTS_LIMIT" ]] ;;
        "warning")  [[ "$count" -ge "$WARNING_EVENTS_LIMIT" ]] ;;
        "info")     [[ "$count" -ge "$INFO_EVENTS_LIMIT" ]] ;;
    esac
}

# Cleanup old entries from smart throttling history (v3.1)
cleanup_smart_throttle() {
    local cutoff_time="$(($(date +%s) - THROTTLE_WINDOW_MINUTES * 60))"
    
    if [[ -f "$THROTTLE_FILE" ]]; then
    # If file contains new format (timestamp:type:message), we clean it
        if head -1 "$THROTTLE_FILE" 2>/dev/null | grep -q ':'; then
            awk -F: -v cutoff="$cutoff_time" \
                '$1 >= cutoff' \
                "$THROTTLE_FILE" > "$THROTTLE_FILE.tmp" && \
            mv "$THROTTLE_FILE.tmp" "$THROTTLE_FILE"
        fi
    fi
}

# Get file metadata
get_file_metadata() {
    local file="$1"
    if [[ -f "$file" ]]; then
    # Return: size:inode_ctime:mtime:first_line_hash
        local size=$(stat -c%s "$file" 2>/dev/null || echo "0")
    local ctime=$(stat -c%Z "$file" 2>/dev/null || echo "0")  # inode change time (creation/rotation)
    local mtime=$(stat -c%Y "$file" 2>/dev/null || echo "0")  # content modification time
        local first_line_hash=""
        
        if [[ -s "$file" ]]; then
            first_line_hash=$(head -n1 "$file" 2>/dev/null | sha256sum | cut -d' ' -f1)
        fi
        
        echo "${size}:${ctime}:${mtime}:${first_line_hash}"
    else
        echo "0:0:0:"
    fi
}

# Check whether the file was rotated
is_file_rotated() {
    local current_metadata="$1"
    local saved_metadata="$2"
    
    # Parse metadata: size:inode_ctime:mtime:first_line_hash
    IFS=':' read -r curr_size curr_ctime curr_mtime curr_hash <<< "$current_metadata"
    IFS=':' read -r saved_size saved_ctime saved_mtime saved_hash <<< "$saved_metadata"
    
    # File considered rotated if:
    # 1. First line hash changed (file replaced)
    # 2. File size is smaller than previous (file truncated/recreated)
    # 3. File creation (inode change) time changed (file recreated during rotation)
    # 4. Creation time newer than modification time (new file scenario)
    
    if [[ -n "$saved_hash" && -n "$curr_hash" && "$curr_hash" != "$saved_hash" ]]; then
        log_debug "ROTATION DETECTED: First line hash changed ($saved_hash -> $curr_hash)"
        return 0
    fi
    
    if [[ "$curr_size" -lt "$saved_size" ]]; then
        log_debug "ROTATION DETECTED: File size decreased ($saved_size -> $curr_size)"
        return 0
    fi
    
    # Check file creation (inode change) time
    if [[ -n "$saved_ctime" && -n "$curr_ctime" && "$curr_ctime" != "$saved_ctime" ]]; then
    # If creation time changed AND new creation time is greater than old modification time
    # this means file was recreated
        if [[ "$curr_ctime" -gt "$saved_mtime" ]]; then
            log_debug "ROTATION DETECTED: File creation time changed ($saved_ctime -> $curr_ctime)"
            return 0
        fi
    fi
    
    # Additional check: if creation time is greater than modification time
    # this may indicate a newly created file
    if [[ -n "$curr_ctime" && -n "$curr_mtime" && "$curr_ctime" -gt "$curr_mtime" ]]; then
        local time_diff=$((curr_ctime - curr_mtime))
    # If difference > 60 seconds the file was likely recreated
        if [[ "$time_diff" -gt 60 ]]; then
            log_debug "ROTATION DETECTED: Creation time > modification time (diff: ${time_diff}s)"
            return 0
        fi
    fi
    
    return 1
}

send_telegram() {
    local message="$1"
    local priority="${2:-normal}"
    
    # Add emoji based on priority
    case "$priority" in
    "critical") message="🚨 CRITICAL: $message" ;;
    "warning") message="⚠️ WARNING: $message" ;;
    "info") message="ℹ️ INFO: $message" ;;
        *) message="📊 $message" ;;
    esac
    
    local hostname=$(hostname)
    local full_message="[$hostname] $message"
    
    # Send to the ERRORS topic (ID:10) - telegram-sender logs result itself
    "$TELEGRAM_SENDER" "$full_message" "10"
}

is_throttled() {
    local event_type="$1"
    local throttle_minutes="${2:-5}"
    local current_time=$(date +%s)
    
    # Read last sent time for this event type
    local last_sent=$(grep "^$event_type:" "$THROTTLE_FILE" 2>/dev/null | cut -d: -f2)
    
    if [[ -n "$last_sent" ]] && (( current_time - last_sent < throttle_minutes * 60 )); then
        return 0  # throttled
    else
    # Update last sent time
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
    send_telegram "Container $name was restarted" "warning"
        return 0
    else
        log_action "RESTART_FAILED: container $name"
    send_telegram "Failed to restart container $name" "critical"
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
    send_telegram "Network interface $iface was restarted" "warning"
        return 0
    else
        log_action "RESTART_FAILED: interface $iface"
    send_telegram "Failed to restart interface $iface" "critical"
        return 1
    fi
}

process_failure() {
    local line="$1"
    local event_timestamp="$2"
    
    # Extract event type from log line (supports new format)
    local event_type=$(extract_failure_type "$line")
    local message
    local priority="warning"
    local should_throttle=false
    local throttle_minutes=5
    
    log_action "Processing failure event: $event_type" "DEBUG"
    
    case "$event_type" in
        *"NO_INTERNET"*)
            message="Internet unavailable"
            should_throttle=true
            throttle_minutes=10
            ;;
        *"GATEWAY_DOWN"*)
            message="Gateway not responding"
            should_throttle=true
            throttle_minutes=10
            ;;
        *"DOCKER_DAEMON_DOWN"*)
            message="Docker daemon is not running"
            priority="critical"
            should_throttle=true
            throttle_minutes=15
            ;;
        *"HA_DOWN"*|*"HA_SERVICE_DOWN"*)
            message="Home Assistant is unavailable"
            priority="critical"
            ;;
        *"CONTAINER_DOWN:"*)
            local name=$(echo "$event_type" | sed 's/.*CONTAINER_DOWN://' | cut -d: -f1)
            restart_container "$name"
            return
            ;;
        *"IFACE_DOWN:"*)
            local iface=$(echo "$event_type" | sed 's/.*IFACE_DOWN://' | cut -d: -f1)
            # Do not auto-restart interface - too noisy
            if [[ "$iface" == "wlan0" ]]; then
                log_action "IGNORED: $iface down (auto-restart disabled)" "DEBUG"
                return
            else
                restart_interface "$iface"
                return
            fi
            ;;
        *"LOW_MEMORY:"*)
            local mem=$(echo "$line" | sed 's/.*LOW_MEMORY://' | cut -d' ' -f1)
            event_type="LOW_MEMORY"
            message="Low free memory: $mem"
            priority="critical"
            should_throttle=true
            throttle_minutes=60
            ;;
        *"LOW_DISK:"*)
            local disk=$(echo "$line" | sed 's/.*LOW_DISK://' | cut -d' ' -f1)
            event_type="LOW_DISK"
            message="Low disk space: $disk"
            priority="critical"
            should_throttle=true
            throttle_minutes=60
            ;;
        *"HIGH_TEMP:"*)
            local temp=$(echo "$line" | sed 's/.*HIGH_TEMP://' | cut -d' ' -f1)
            event_type="HIGH_TEMP"
            message="High CPU temperature: $temp"
            priority="critical"
            should_throttle=true
            throttle_minutes=15
            ;;
        *"HA_SERVICE_DOWN"*)
            event_type="HA_SERVICE_DOWN"
            message="Home Assistant service not responding on port 8123"
            priority="critical"
            ;;
        *"NODERED_SERVICE_DOWN"*)
            event_type="NODERED_SERVICE_DOWN"
            message="Node-RED service not responding on port 1880"
            ;;
        *"HIGH_LOAD:"*)
            local load=$(echo "$line" | sed 's/.*HIGH_LOAD://' | cut -d' ' -f1)
            event_type="HIGH_LOAD"
            message="High system load: $load"
            should_throttle=true
            throttle_minutes=10
            ;;
        *"SSH_DOWN:"*)
            event_type="SSH_DOWN"
            message="SSH service unavailable"
            priority="critical"
            should_throttle=true
            throttle_minutes=15
            ;;
        *"TAILSCALE_DAEMON_DOWN"*)
            event_type="TAILSCALE_DAEMON"
            message="Tailscale daemon not running"
            priority="critical"
            should_throttle=true
            throttle_minutes=15
            ;;
        *"TAILSCALE_VPN_DOWN"*)
            event_type="TAILSCALE_VPN"
            message="Tailscale VPN connection unavailable"
            priority="critical"
            should_throttle=true
            throttle_minutes=15
            ;;
        *"TAILSCALE_FUNNEL_DOWN"*)
            event_type="TAILSCALE_FUNNEL"
            message="Tailscale Funnel service not running"
            priority="warning"
            should_throttle=true
            throttle_minutes=20
            ;;
        *"HA_DATABASE_"*)
            event_type="HA_DATABASE"
            message="Home Assistant database problem detected"
            priority="critical"
            should_throttle=true
            throttle_minutes=60
            ;;
        *"HIGH_SWAP_USAGE:"*)
            local swap=$(echo "$line" | sed 's/.*HIGH_SWAP_USAGE://' | cut -d' ' -f1)
            event_type="HIGH_SWAP"
            message="High swap usage: $swap"
            priority="warning"
            should_throttle=true
            throttle_minutes=30
            ;;
        *"WEAK_WIFI_SIGNAL:"*)
            local signal=$(echo "$line" | sed 's/.*WEAK_WIFI_SIGNAL://' | cut -d' ' -f1)
            event_type="WEAK_WIFI"
            message="Weak WiFi signal: $signal"
            should_throttle=true
            throttle_minutes=60
            ;;
        *"UNDERVOLTAGE_DETECTED"*)
            event_type="UNDERVOLTAGE"
            message="Undervoltage detected"
            priority="critical"
            should_throttle=true
            throttle_minutes=30
            ;;
        *"CPU_THROTTLED"*)
            event_type="CPU_THROTTLED"
            message="CPU throttled due to temperature/power"
            priority="critical"
            should_throttle=true
            throttle_minutes=20
            ;;
        *"NTP_NOT_SYNCED"*)
            event_type="NTP_SYNC"
            message="System time not synchronized via NTP"
            should_throttle=true
            throttle_minutes=120
            ;;
        *"LOG_OVERSIZED:"*)
            event_type="LOG_OVERSIZED"
            message="Log file exceeded allowed size"
            should_throttle=true
            throttle_minutes=240
            ;;
        *"SD_CARD_ERRORS"*)
            event_type="SD_CARD_ERRORS"
            message="SD card errors detected"
            priority="critical"
            should_throttle=true
            throttle_minutes=60
            ;;
        *)
            event_type="UNKNOWN"
            message="Unknown issue: $line"
            ;;
    esac
    
    # Apply smart throttling (v3.1) - takes precedence over legacy logic
    if should_throttle_smart "$event_type" "$event_timestamp"; then
        local priority_level=$(get_event_priority "$event_type")
    log_action "SMART_THROTTLED: [$priority_level] $event_type (limit reached)"
    # Record throttled events in history as well
        echo "${event_timestamp}:${event_type}:${line}" >> "$THROTTLE_FILE"
        return
    fi
    
    # Apply legacy throttling (compatibility)
    if [[ "$should_throttle" == true ]] && is_throttled "$event_type" "$throttle_minutes"; then
        log_action "LEGACY_THROTTLED: $event_type (< $throttle_minutes min)"
        return
    fi
    
    # Append event to smart throttling history
    echo "${event_timestamp}:${event_type}:${line}" >> "$THROTTLE_FILE"
    
    # Send notification
    send_telegram "$message" "$priority"
    log_action "PROCESSED: $event_type - $message"
    
    # Save timestamp of last processed event
    if [[ "$event_timestamp" != "0" ]]; then
        echo "$event_timestamp" > "$TIMESTAMP_FILE"
        log_action "TIMESTAMP_UPDATED: $event_timestamp"
    fi
}

# Main function using timestamp-based algorithm
main() {
    log_action "Starting failure processing (v3.1 smart priority-based throttling)" "INFO"
    log_action "Enhanced for new logging-service format from ha-watchdog.sh" "DEBUG"
    
    if [[ ! -f "$LOG_FILE" ]]; then
        log_action "Failure log file not found: $LOG_FILE" "ERROR"
        return 1
    fi
    
    # Purge old records from smart throttling history
    cleanup_smart_throttle
    
    local total_lines=$(wc -l < "$LOG_FILE")
    local last_timestamp=$(cat "$TIMESTAMP_FILE" 2>/dev/null || echo "0")
    local current_metadata=$(get_file_metadata "$LOG_FILE")
    local saved_metadata=$(cat "$METADATA_FILE" 2>/dev/null || echo "")
    local processed_events=0
    local newest_timestamp="$last_timestamp"
    
    log_action "Log file has $total_lines lines, last processed timestamp: $last_timestamp"
    log_action "Current metadata: $current_metadata" "DEBUG"
    log_action "Saved metadata: $saved_metadata" "DEBUG"
    
    # Check if file was rotated (informational)
    local file_rotated=false
    if [[ -n "$saved_metadata" ]] && is_file_rotated "$current_metadata" "$saved_metadata"; then
        file_rotated=true
        log_action "File rotation detected, but processing by timestamp" "DEBUG"
    fi
    
    # Iterate all lines but only process those newer than last timestamp
    if (( total_lines > 0 )); then
        log_action "Processing all $total_lines lines, filtering by timestamp > $last_timestamp"
        
        while IFS= read -r line; do
            # Skip empty lines or lines without timestamp
            [[ -z "$line" || "$line" != *" "* ]] && continue
            
            # Extract timestamp from line
            local event_timestamp=$(extract_timestamp "$line")
            
            # Process only events newer than last processed
            if is_event_newer "$event_timestamp" "$last_timestamp"; then
                process_failure "$line" "$event_timestamp"
                ((processed_events++))
                
                # Track newest timestamp
                if (( event_timestamp > newest_timestamp )); then
                    newest_timestamp="$event_timestamp"
                fi
            else
                # Log skipped old events (debug)
                if [[ "$event_timestamp" != "0" ]]; then
                    log_action "SKIPPED_OLD: timestamp $event_timestamp <= $last_timestamp"
                fi
            fi
        done < "$LOG_FILE"
        
    # Save metadata and newest timestamp
        echo "$current_metadata" > "$METADATA_FILE"
        if [[ "$newest_timestamp" != "$last_timestamp" ]]; then
            echo "$newest_timestamp" > "$TIMESTAMP_FILE"
            log_action "Updated newest timestamp to $newest_timestamp, processed $processed_events new event(s)" "INFO"
        else
            log_action "No new events found (all timestamps <= $last_timestamp)" "DEBUG"
        fi
        
    # Rotation notifications removed - they created noise
        # if [[ "$file_rotated" == true ]]; then
    #     send_telegram "Log file was rotated, events processed by timestamp" "info"
        # fi
    else
        log_action "Log file is empty" "WARN"
    # Save metadata even if file is empty
        echo "$current_metadata" > "$METADATA_FILE"
    fi
    
    log_action "Failure processing completed" "INFO"
}

main "$@"
