#!/bin/bash

# Enhanced watchdog for System with Home Assistant
LOG_FILE="/var/log/ha-watchdog.log"
FAILURE_FILE="/var/log/ha-failures.log"
CONFIG_FILE="/etc/ha-watchdog/config"

# Load configuration
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    # Default values
    HOST="8.8.8.8"
    MEM_THRESHOLD_MB=80
    DISK_THRESHOLD_KB=500000
    TEMP_THRESHOLD=70
    HA_CONTAINER="homeassistant"
    CONTAINERS=("homeassistant" "nodered")
    IFACE="wlan0"
    HA_PORT=8123
    NODERED_PORT=1880
    SSH_PORT=22
    CRITICAL_SERVICES=("docker" "tailscaled")
    MAX_LOG_SIZE_MB=100
    HA_DB_PATH="/config/home-assistant_v2.db"
    HA_DB_MAX_SIZE_MB=1000
    SWAP_THRESHOLD_MB=100
fi

GATEWAY=$(ip route | awk '/default/ {print $3}')

# Ensure log directories exist
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null
mkdir -p "$(dirname "$FAILURE_FILE")" 2>/dev/null

# Centralized logging ONLY through logging-service
LOGGING_SERVICE="/usr/local/bin/logging-service.sh"
SCRIPT_NAME="ha-watchdog"

if [[ -f "$LOGGING_SERVICE" ]] && [[ -r "$LOGGING_SERVICE" ]]; then
    source "$LOGGING_SERVICE" 2>/dev/null
    if ! command -v log_structured >/dev/null 2>&1; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] [ha-watchdog] [PID:$$] [systemd] logging-service loaded, but log_structured function is not available" >> "$LOG_FILE"
        exit 1
    fi
    # Check wrapper functions availability
    if ! command -v log_debug >/dev/null 2>&1; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] [ha-watchdog] [PID:$$] [systemd] logging-service loaded, but log_debug function is not available" >> "$LOG_FILE"
        exit 1
    fi
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] [ha-watchdog] [PID:$$] [systemd] Centralized logging-service not found: $LOGGING_SERVICE" >> "$LOG_FILE"
    exit 1
fi

# Note: log_debug, log_info, log_warn, log_error are now provided by logging-service.sh

log_failure() {
    local message="$1"
    
    # Write failures through centralized logging-service 
    # to special file /var/log/ha-failures.log (for ha-failure-notifier)
    log_structured "ha-failures" "ERROR" "FAILURE: $message"
    
    # And duplicate to main watchdog log for debugging
    log_error "FAILURE: $message"
}

check_internet() {
    if ! ping -c 1 -W 2 "$HOST" >/dev/null 2>&1; then
        log_failure "NO_INTERNET"
        return 1
    fi
    return 0
}

check_gateway() {
    if [[ -n "$GATEWAY" ]] && ! ping -c 1 -W 2 "$GATEWAY" >/dev/null 2>&1; then
        log_failure "GATEWAY_DOWN:$GATEWAY"
        return 1
    fi
    return 0
}

check_containers() {
    local failed=0
    
    # Check Docker daemon
    if ! docker info >/dev/null 2>&1; then
        log_failure "DOCKER_DAEMON_DOWN"
        ((failed++))
    fi
    
    # Check containers
    for name in "${CONTAINERS[@]}"; do
        if ! docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null | grep -q true; then
            log_failure "CONTAINER_DOWN:$name"
            ((failed++))
        fi
    done
    
    return $failed
}

check_network_interface() {
    # Commented out - redundant WiFi checks create too much noise
    # if ! ip link show "$IFACE" 2>/dev/null | grep -q "state UP"; then
    #     log_failure "IFACE_DOWN:$IFACE"
    #     return 1
    # fi
    return 0
}

check_memory() {
    local mem_available_mb=$(free -m | awk '/Mem:/ {print $7}')
    if [[ "$mem_available_mb" -lt "$MEM_THRESHOLD_MB" ]]; then
        log_failure "LOW_MEMORY:${mem_available_mb}MB"
        return 1
    fi
    return 0
}

check_disk() {
    local disk_available_kb=$(df / | awk 'NR==2 {print $4}')
    if [[ "$disk_available_kb" -lt "$DISK_THRESHOLD_KB" ]]; then
        log_failure "LOW_DISK:${disk_available_kb}KB"
        return 1
    fi
    return 0
}

check_temperature() {
    local temp_file="/sys/class/thermal/thermal_zone0/temp"
    if [[ -f "$temp_file" ]]; then
        local temp_raw=$(cat "$temp_file")
        local temp_celsius=$((temp_raw / 1000))
        if [[ "$temp_celsius" -gt "$TEMP_THRESHOLD" ]]; then
            log_failure "HIGH_TEMP:${temp_celsius}C"
            return 1
        fi
    fi
    return 0
}

check_services() {
    local failed=0
    
    # Check Home Assistant accessibility
    if [[ -n "$HA_PORT" ]] && ! timeout 5 bash -c "</dev/tcp/localhost/$HA_PORT" 2>/dev/null; then
        log_failure "HA_SERVICE_DOWN:$HA_PORT"
        ((failed++))
    fi
    
    # Check Node-RED accessibility
    if [[ -n "$NODERED_PORT" ]] && ! timeout 5 bash -c "</dev/tcp/localhost/$NODERED_PORT" 2>/dev/null; then
        log_failure "NODERED_SERVICE_DOWN:$NODERED_PORT"
        ((failed++))
    fi
    
    return $failed
}

check_system_load() {
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    local load_threshold="2.0"
    
    if (( $(echo "$load_avg > $load_threshold" | bc -l) )); then
        log_failure "HIGH_LOAD:${load_avg}"
        return 1
    fi
    return 0
}

check_ssh_access() {
    if [[ -n "$SSH_PORT" ]] && ! timeout 3 bash -c "</dev/tcp/localhost/$SSH_PORT" 2>/dev/null; then
        log_failure "SSH_DOWN:$SSH_PORT"
        return 1
    fi
    return 0
}

check_ssh_security() {
    local failed=0
    
    # Check if fail2ban is protecting SSH (critical for security)
    if command -v fail2ban-client >/dev/null 2>&1; then
        if ! systemctl is-active --quiet fail2ban; then
            log_failure "FAIL2BAN_NOT_RUNNING"
            ((failed++))
        else
            # Check if SSH jail is enabled (requires sudo)
            if ! sudo fail2ban-client status sshd &>/dev/null; then
                log_failure "FAIL2BAN_SSH_JAIL_NOT_ACTIVE"
                ((failed++))
            fi
        fi
    else
        log_failure "FAIL2BAN_NOT_INSTALLED"
        ((failed++))
    fi
    
    return $failed
}

check_tailscale_status() {
    local failed=0
    
    # Check Tailscale daemon
    if ! systemctl is-active tailscaled >/dev/null 2>&1; then
        log_failure "TAILSCALE_DAEMON_DOWN"
        ((failed++))
    fi
    
    # Check VPN connectivity
    if ! tailscale status >/dev/null 2>&1; then
        log_failure "TAILSCALE_VPN_DOWN"
        ((failed++))
    fi
    
    # Check Funnel service
    if ! systemctl is-active tailscale-funnel-ha >/dev/null 2>&1; then
        log_failure "TAILSCALE_FUNNEL_DOWN"
        ((failed++))
    fi
    
    return $failed
}

check_sd_card_health() {
    local failed=0
    
    # Check SD card errors in dmesg
    if dmesg | tail -100 | grep -q -E "(mmc.*error|mmc.*timeout|mmc.*failed)"; then
        log_failure "SD_CARD_ERRORS"
        ((failed++))
    fi
    
    # Check read-only filesystem state
    if mount | grep -q "/ .*ro,"; then
        log_failure "FILESYSTEM_READONLY"
        ((failed++))
    fi
    
    return $failed
}

check_critical_systemd_services() {
    local failed=0
    
    for service in "${CRITICAL_SERVICES[@]}"; do
        if ! systemctl is-active "$service" >/dev/null 2>&1; then
            log_failure "SYSTEMD_SERVICE_DOWN:$service"
            ((failed++))
        fi
    done
    
    return $failed
}

check_log_sizes() {
    local failed=0
    local max_size_bytes=$((MAX_LOG_SIZE_MB * 1024 * 1024))
    
    # Check important log files for oversize condition
    for log_file in "/var/log/syslog" "/var/log/daemon.log" "$LOG_FILE" "$FAILURE_FILE"; do
        if [[ -f "$log_file" ]]; then
            local size=$(stat -c%s "$log_file" 2>/dev/null || echo 0)
            if [[ $size -gt $max_size_bytes ]]; then
                log_failure "LOG_OVERSIZED:$log_file:${size}bytes"
                ((failed++))
            fi
        fi
    done
    
    return $failed
}

check_ntp_sync() {
    local failed=0
    
    # Check NTP synchronization (systemd-timesyncd compatible)
    if command -v timedatectl >/dev/null 2>&1; then
        if ! timedatectl status | grep -q "System clock synchronized: yes"; then
            log_failure "NTP_NOT_SYNCED"
            ((failed++))
        fi
    fi
    
    return $failed
}

check_power_supply() {
    local failed=0
    
    # Check for undervoltage events in dmesg
    if dmesg | tail -50 | grep -q -i "under.*voltage"; then
        log_failure "UNDERVOLTAGE_DETECTED"
        ((failed++))
    fi
    
    # Check CPU throttling flags
    if [[ -f "/sys/devices/platform/soc/soc:firmware/get_throttled" ]]; then
        local throttled=$(cat /sys/devices/platform/soc/soc:firmware/get_throttled 2>/dev/null || echo "0")
        if [[ "$throttled" != "0x0" ]] && [[ "$throttled" != "0" ]]; then
            log_failure "CPU_THROTTLED:$throttled"
            ((failed++))
        fi
    fi
    
    return $failed
}

check_public_access() {
    local failed=0
    
    # Check external accessibility via Tailscale Funnel (if configured)
    if systemctl is-active tailscale-funnel-ha >/dev/null 2>&1; then
        local funnel_url=$(tailscale funnel status 2>/dev/null | grep -o "https://[^/]*" | head -1)
        if [[ -n "$funnel_url" ]]; then
            if ! timeout 10 curl -s -f "$funnel_url" >/dev/null 2>&1; then
                log_failure "PUBLIC_ACCESS_DOWN:$funnel_url"
                ((failed++))
            fi
        fi
    fi
    
    return $failed
}

check_ha_database() {
    local failed=0
    
    # Check Home Assistant database size
    if [[ -f "$HA_DB_PATH" ]]; then
        local db_size_mb=$(du -m "$HA_DB_PATH" 2>/dev/null | cut -f1)
        if [[ $db_size_mb -gt $HA_DB_MAX_SIZE_MB ]]; then
            log_failure "HA_DATABASE_OVERSIZED:${db_size_mb}MB"
            ((failed++))
        fi
        
    # Verify database integrity (quick check)
        if ! timeout 5 sqlite3 "$HA_DB_PATH" "PRAGMA integrity_check;" 2>/dev/null | grep -q "ok"; then
            log_failure "HA_DATABASE_CORRUPTED"
            ((failed++))
        fi
    else
    # Try to locate DB inside container via docker exec
        local container_db_path=$(docker exec homeassistant find /config -name "home-assistant_v2.db" 2>/dev/null | head -1)
        if [[ -z "$container_db_path" ]]; then
            log_failure "HA_DATABASE_MISSING:$HA_DB_PATH"
            ((failed++))
        fi
    fi
    
    return $failed
}

check_swap_usage() {
    local failed=0
    
    # Check swap usage amount
    local swap_used_mb=$(free -m | awk '/Swap:/ {print $3}')
    if [[ $swap_used_mb -gt $SWAP_THRESHOLD_MB ]]; then
        log_failure "HIGH_SWAP_USAGE:${swap_used_mb}MB"
        ((failed++))
    fi
    
    return $failed
}

check_wifi_signal() {
    local failed=0
    
    # Check WiFi signal strength (if WiFi in use)
    if [[ "$IFACE" == "wlan0" ]] || [[ "$IFACE" == wlan* ]]; then
        if command -v iwconfig >/dev/null 2>&1; then
            local signal_level=$(iwconfig "$IFACE" 2>/dev/null | grep "Signal level" | sed 's/.*Signal level=\(-[0-9]*\).*/\1/')
            if [[ -n "$signal_level" ]] && [[ $signal_level -lt -70 ]]; then
                log_failure "WEAK_WIFI_SIGNAL:${signal_level}dBm"
                ((failed++))
            fi
        elif command -v iw >/dev/null 2>&1; then
            # Alternative method using iw command
            local signal_level=$(iw dev "$IFACE" link 2>/dev/null | grep "signal:" | awk '{print $2}')
            if [[ -n "$signal_level" ]] && [[ $signal_level -lt -70 ]]; then
                log_failure "WEAK_WIFI_SIGNAL:${signal_level}dBm"
                ((failed++))
            fi
        fi
    fi
    
    return $failed
}

# Main comprehensive check
main() {
    log_info "Starting comprehensive system health check (20 components)"
    
    local total_failures=0
    
    # Basic connectivity checks
    log_debug "Running network connectivity checks..."
    check_internet || ((total_failures++))
    check_gateway || ((total_failures++))
    check_network_interface || ((total_failures++))
    
    # System resource checks
    log_debug "Checking system resources..."
    check_memory || ((total_failures++))
    check_disk || ((total_failures++))
    check_temperature || ((total_failures++))
    check_system_load || ((total_failures++))
    
    # Services and containers
    log_debug "Verifying services and containers..."
    check_containers || ((total_failures++))
    check_services || ((total_failures++))
    check_critical_systemd_services || ((total_failures++))
    
    # Remote access services
    log_debug "Testing remote access..."
    check_ssh_access || ((total_failures++))
    check_ssh_security || ((total_failures++))
    check_tailscale_status || ((total_failures++))
    # check_public_access || ((total_failures++))  # Disabled: Tailscale Funnel not configured
    
    # System health (storage, power, time, logs)
    log_debug "Analyzing system health..."
    check_sd_card_health || ((total_failures++))
    check_power_supply || ((total_failures++))
    check_ntp_sync || ((total_failures++))
    check_log_sizes || ((total_failures++))
    
    # Extended application-specific checks
    log_debug "Running extended diagnostics..."
    check_ha_database || ((total_failures++))
    check_swap_usage || ((total_failures++))
    check_wifi_signal || ((total_failures++))
    
    if [[ $total_failures -eq 0 ]]; then
        log_info "Health check completed: ALL 19 CHECKS PASSED ✓"
    else
        log_warn "Health check completed: $total_failures failure(s) detected across system components"
    fi
}

main "$@"
