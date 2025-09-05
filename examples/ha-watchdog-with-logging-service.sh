#!/bin/bash

# Example modification of ha-watchdog.sh to use logging-service
# Demonstrates how to integrate standardized logging

LOG_FILE="/var/log/ha-watchdog.log"
FAILURE_FILE="/var/log/ha-failures.log"
CONFIG_FILE="/etc/ha-watchdog/config"

# Attach centralized logging service (optional)
LOGGING_SERVICE="/usr/local/bin/logging-service.sh"
if [[ -f "$LOGGING_SERVICE" ]]; then
    # Ensure the file is executable and can be sourced
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

# Logging function with automatic method selection
log() {
    local message="$1"
    local level="${2:-INFO}"
    
    if [[ "$USE_STRUCTURED_LOGGING" == "true" ]]; then
    # Use centralized logging-service
        log_structured "ha-watchdog" "$level" "$message"
    else
    # Fallback to legacy method
        echo "$(date '+%F %T') [WATCHDOG] $message" >> "$LOG_FILE"
    fi
}

log_failure() {
    local message="$1"
    
    # Write to failures file (previous behavior)
    echo "$(date '+%F %T') $message" >> "$FAILURE_FILE"
    
    # And log through the standardized mechanism
    log "FAILURE: $message" "ERROR"
}

# Example usage:
check_internet() {
    local start_time=$(date +%s%3N)
    
    if ! ping -c 1 -W 2 "8.8.8.8" >/dev/null 2>&1; then
        log_failure "NO_INTERNET"
        return 1
    fi
    
    local end_time=$(date +%s%3N)
    local duration=$((end_time - start_time))
    
    # Log with metrics if available
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
    # Structured logging with extra data
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

# Main logic
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
    
    # Final summary report
    local success_rate=$(( checks_passed * 100 / checks_total ))
    
    if [[ "$USE_STRUCTURED_LOGGING" == "true" ]]; then
        local extra_data='{"checks_passed": '$checks_passed', "checks_total": '$checks_total', "success_rate": '$success_rate'}'
        log_structured "ha-watchdog" "INFO" "Health check completed" "$extra_data"
    else
        log "Health check completed: $checks_passed/$checks_total ($success_rate%)" "INFO"
    fi
}

main "$@"
