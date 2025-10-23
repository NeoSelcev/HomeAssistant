#!/bin/bash

# 📝 Centralized structured logging service
# Used for unified formatting and log rotation
# Author: Smart Home Monitoring System
# Version: 1.1 - Fixed CONFIG_FILE name collision

LOGGING_CONFIG_FILE="/etc/logging-service/config"

# Load configuration (optional - use defaults if not found)
if [[ -f "$LOGGING_CONFIG_FILE" ]]; then
    source "$LOGGING_CONFIG_FILE"
fi

# Default values (if not set in config)
LOG_FORMAT="${LOG_FORMAT:-plain}"  # plain, json, syslog
MAX_MESSAGE_LENGTH="${MAX_MESSAGE_LENGTH:-2048}"
ENABLE_REMOTE_LOGGING="${ENABLE_REMOTE_LOGGING:-false}"

# Special log for logging-service itself (avoid recursion)
LOGGING_SERVICE_LOG="${LOGGING_SERVICE_LOG:-/var/log/logging-service.log}"
ENABLE_SELF_LOGGING="${ENABLE_SELF_LOGGING:-true}"
SELF_LOG_LEVEL="${SELF_LOG_LEVEL:-INFO}"

# Direct logging function for logging-service (no recursion)
log_self() {
    local level="$1"
    local message="$2"
    
    # Check if self-logging is enabled and level matches
    if [[ "$ENABLE_SELF_LOGGING" != "true" ]]; then
        return 0
    fi
    
    # Filter by self-logging level
    case "$SELF_LOG_LEVEL" in
        "ERROR") [[ "$level" == "ERROR" ]] || return 0 ;;
        "WARN") [[ "$level" =~ ^(ERROR|WARN)$ ]] || return 0 ;;
        "INFO") [[ "$level" =~ ^(ERROR|WARN|INFO)$ ]] || return 0 ;;
    "DEBUG") ;; # Log everything
    esac
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local hostname=$(hostname)
    local pid=$$
    
    # Simple format for self-logging
    echo "$timestamp [$level] [logging-service] [PID:$pid] $message" >> "$LOGGING_SERVICE_LOG"
}

# Structured logging function
log_structured() {
    local service="$1"
    local level="$2"     # DEBUG, INFO, WARN, ERROR, CRITICAL
    local message="$3"
    local extra_data="$4"  # JSON string for extra fields
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local hostname=$(hostname)
    local pid=$$
    local caller_pid="$PPID"
    local caller_process="$(ps -o comm= -p $PPID 2>/dev/null || echo 'unknown')"
    
    # Truncate message if too long
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
    
    # Determine log file for service
    local log_file=$(get_log_file "$service")
    
    # Self-log important events (no recursion)
    if [[ "$level" == "ERROR" ]] || [[ "$level" == "CRITICAL" ]]; then
        log_self "INFO" "Processing $level event from $service: $message"
    fi
    
    # Write to file
    echo "$log_entry" >> "$log_file"
    
    # Verify write success
    if [[ $? -ne 0 ]]; then
        log_self "ERROR" "Failed to write to log file: $log_file"
        return 1
    fi
    
    # Remote logging (if enabled)
    if [[ "$ENABLE_REMOTE_LOGGING" == "true" ]] && [[ -n "$REMOTE_LOG_ENDPOINT" ]]; then
        log_self "DEBUG" "Sending log to remote endpoint: $REMOTE_LOG_ENDPOINT"
        send_remote_log "$log_entry" "$service" "$level" &
    fi
    
    # Notifications for critical events
    if [[ "$level" == "CRITICAL" ]] && [[ -n "$CRITICAL_NOTIFICATION_COMMAND" ]]; then
        log_self "INFO" "Sending critical notification for: $service"
        $CRITICAL_NOTIFICATION_COMMAND "$service" "$message" &
    fi
}

# Define log file by service
# ✅ IMPORTANT: Each service = separate log file (NOT centralization!)
# This is done to preserve individuality and convenience of analysis
get_log_file() {
    local service="$1"
    case "$service" in
        "ha-watchdog") echo "/var/log/ha-watchdog.log" ;;              # ✅ Individual log for monitoring
        "ha-failure-notifier") echo "/var/log/ha-failure-notifier.log" ;; # ✅ Individual log for failures
        "ha-failures") echo "/var/log/ha-failures.log" ;;              # ✅ Special file for failure events
        "telegram-sender") echo "/var/log/telegram-sender.log" ;;      # ✅ Individual log for Telegram
        "update-checker") echo "/var/log/ha-update-checker.log" ;;     # ✅ Individual log for updates
        "nightly-reboot") echo "/var/log/ha-reboot.log" ;;             # ✅ Individual log for reboots
        "system-diagnostic-startup") echo "/var/log/system-diagnostic-startup.log" ;; # 🆕 NEW mapping
        "ha-backup") echo "/var/log/ha-backup.log" ;;                  # 🆕 NEW mapping
        "boot-notifier") echo "/var/log/boot-notifier.log" ;;          # 🆕 NEW mapping
        *) echo "/var/log/ha-${service}.log" ;;                        # ✅ Pattern for new services
    esac
}

# Convert level to syslog severity
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

# Send to remote log server
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

# Simple logging function (backward compatibility)
log_simple() {
    local service="$1"
    local message="$2"
    local level="${3:-INFO}"
    
    log_structured "$service" "$level" "$message"
}

# Logging function with metrics
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

# Main logic (if script is run directly)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Create log file for logging-service itself if it does not exist
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
}

# ========================================
# Convenience wrapper functions for common use
# ========================================

# These functions should be used when sourced by other scripts
# They don't require passing service name repeatedly

log_debug() {
    local message="$1"
    local service="${SCRIPT_NAME:-unknown}"
    log_structured "$service" "DEBUG" "$message"
}

log_info() {
    local message="$1"
    local service="${SCRIPT_NAME:-unknown}"
    log_structured "$service" "INFO" "$message"
}

log_warn() {
    local message="$1"
    local service="${SCRIPT_NAME:-unknown}"
    log_structured "$service" "WARN" "$message"
}

log_error() {
    local message="$1"
    local service="${SCRIPT_NAME:-unknown}"
    log_structured "$service" "ERROR" "$message"
}

log_critical() {
    local message="$1"
    local service="${SCRIPT_NAME:-unknown}"
    log_structured "$service" "CRITICAL" "$message"
}
            ;;
        *)
            log_self "DEBUG" "Processing structured log call for service: $1"
            log_structured "$1" "$2" "$3" "$4"
            ;;
    esac
    
    log_self "DEBUG" "Log processing completed successfully"
fi
