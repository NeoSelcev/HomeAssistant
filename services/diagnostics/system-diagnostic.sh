#!/bin/bash

# 🔍 Скрипт комплексной диагностики Raspberry Pi + Home Assistant
# Создает детальный отчет о состоянии системы

REPORT_FILE="/tmp/system_diagnostic_$(date +%Y%m%d_%H%M%S).txt"
COLORED_OUTPUT=true

# Цветной вывод
if [[ "$COLORED_OUTPUT" == true ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    NC=''
fi

log_section() {
    local title="$1"
    echo -e "${BLUE}=== $title ===${NC}" | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"
}

log_check() {
    local status="$1"
    local message="$2"
    local color=""
    
    case "$status" in
        "OK") color="$GREEN" ;;
        "WARNING") color="$YELLOW" ;;
        "ERROR") color="$RED" ;;
        "INFO") color="$CYAN" ;;
    esac
    
    echo -e "${color}[$status]${NC} $message" | tee -a "$REPORT_FILE"
}

check_basic_system() {
    log_section "🖥️  БАЗОВАЯ ИНФОРМАЦИЯ О СИСТЕМЕ"
    
    log_check "INFO" "Hostname: $(hostname)"
    log_check "INFO" "Uptime: $(uptime -p)"
    log_check "INFO" "Kernel: $(uname -r)"
    log_check "INFO" "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
    log_check "INFO" "Architecture: $(uname -m)"
    
    # CPU Info
    local cpu_model=$(cat /proc/cpuinfo | grep "model name" | head -1 | cut -d':' -f2 | xargs)
    log_check "INFO" "CPU: $cpu_model"
    
    # Temperature
    if [[ -f /sys/class/thermal/thermal_zone0/temp ]]; then
        local temp=$(cat /sys/class/thermal/thermal_zone0/temp | awk '{print $1/1000}')
        if (( $(echo "$temp > 70" | bc -l) )); then
            log_check "WARNING" "Temperature: ${temp}°C (высокая!)"
        elif (( $(echo "$temp > 60" | bc -l) )); then
            log_check "WARNING" "Temperature: ${temp}°C (повышенная)"
        else
            log_check "OK" "Temperature: ${temp}°C"
        fi
    fi
    
    echo "" | tee -a "$REPORT_FILE"
}

check_resources() {
    log_section "💾 РЕСУРСЫ СИСТЕМЫ"
    
    # Memory
    local mem_info=$(free -h | grep Mem:)
    local mem_total=$(echo $mem_info | awk '{print $2}')
    local mem_used=$(echo $mem_info | awk '{print $3}')
    local mem_available=$(echo $mem_info | awk '{print $7}')
    local mem_available_mb=$(free -m | awk '/Mem:/ {print $7}')
    
    log_check "INFO" "Memory Total: $mem_total"
    log_check "INFO" "Memory Used: $mem_used"
    
    if [[ $mem_available_mb -lt 100 ]]; then
        log_check "ERROR" "Memory Available: $mem_available (критически мало!)"
    elif [[ $mem_available_mb -lt 200 ]]; then
        log_check "WARNING" "Memory Available: $mem_available (мало)"
    else
        log_check "OK" "Memory Available: $mem_available"
    fi
    
    # Disk space
    local disk_info=$(df -h / | tail -1)
    local disk_size=$(echo $disk_info | awk '{print $2}')
    local disk_used=$(echo $disk_info | awk '{print $3}')
    local disk_available=$(echo $disk_info | awk '{print $4}')
    local disk_percent=$(echo $disk_info | awk '{print $5}' | sed 's/%//')
    
    log_check "INFO" "Disk Size: $disk_size"
    log_check "INFO" "Disk Used: $disk_used"
    
    if [[ $disk_percent -gt 90 ]]; then
        log_check "ERROR" "Disk Available: $disk_available ($disk_percent% used - критически мало!)"
    elif [[ $disk_percent -gt 80 ]]; then
        log_check "WARNING" "Disk Available: $disk_available ($disk_percent% used - мало)"
    else
        log_check "OK" "Disk Available: $disk_available ($disk_percent% used)"
    fi
    
    # Load average
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    if (( $(echo "$load_avg > 2.0" | bc -l) )); then
        log_check "WARNING" "Load Average: $load_avg (высокая нагрузка)"
    else
        log_check "OK" "Load Average: $load_avg"
    fi
    
    echo "" | tee -a "$REPORT_FILE"
}

check_network() {
    log_section "🌐 СЕТЕВОЕ ПОДКЛЮЧЕНИЕ"
    
    # Interfaces
    local interfaces=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo)
    log_check "INFO" "Network Interfaces: $interfaces"
    
    # Check specific interface status
    if ip link show wlan0 &>/dev/null; then
        if ip link show wlan0 | grep -q "state UP"; then
            log_check "OK" "WiFi (wlan0): UP"
        else
            log_check "ERROR" "WiFi (wlan0): DOWN"
        fi
    fi
    
    if ip link show eth0 &>/dev/null; then
        if ip link show eth0 | grep -q "state UP"; then
            log_check "OK" "Ethernet (eth0): UP"
        else
            log_check "WARNING" "Ethernet (eth0): DOWN"
        fi
    fi
    
    # IP addresses
    local ips=$(ip addr show | grep -E "inet.*global" | awk '{print $2, $NF}')
    if [[ -n "$ips" ]]; then
        log_check "INFO" "IP Addresses:"
        echo "$ips" | while read line; do
            echo "  $line" | tee -a "$REPORT_FILE"
        done
    fi
    
    # Gateway
    local gateway=$(ip route | awk '/default/ {print $3}')
    if [[ -n "$gateway" ]]; then
        if ping -c 1 -W 2 "$gateway" >/dev/null 2>&1; then
            log_check "OK" "Gateway ($gateway): Reachable"
        else
            log_check "ERROR" "Gateway ($gateway): Unreachable"
        fi
    else
        log_check "ERROR" "Gateway: Not found"
    fi
    
    # Internet connectivity
    if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
        log_check "OK" "Internet: Available"
    else
        log_check "ERROR" "Internet: Unavailable"
    fi
    
    # DNS
    if nslookup google.com >/dev/null 2>&1; then
        log_check "OK" "DNS: Working"
    else
        log_check "WARNING" "DNS: Issues detected"
    fi
    
    echo "" | tee -a "$REPORT_FILE"
}

check_docker() {
    log_section "🐳 DOCKER"
    
    if ! command -v docker >/dev/null 2>&1; then
        log_check "ERROR" "Docker: Not installed"
        echo "" | tee -a "$REPORT_FILE"
        return
    fi
    
    log_check "INFO" "Docker Version: $(docker --version)"
    
    # Docker daemon status
    if systemctl is-active docker >/dev/null 2>&1; then
        log_check "OK" "Docker Daemon: Running"
    else
        log_check "ERROR" "Docker Daemon: Not running"
        echo "" | tee -a "$REPORT_FILE"
        return
    fi
    
    # Docker info
    if docker info >/dev/null 2>&1; then
        log_check "OK" "Docker Info: Accessible"
    else
        log_check "ERROR" "Docker Info: Cannot access daemon"
        echo "" | tee -a "$REPORT_FILE"
        return
    fi
    
    # Containers
    log_check "INFO" "Container Status:"
    local containers=("homeassistant" "nodered")
    for container in "${containers[@]}"; do
        if docker inspect "$container" >/dev/null 2>&1; then
            local status=$(docker inspect -f '{{.State.Status}}' "$container")
            local running=$(docker inspect -f '{{.State.Running}}' "$container")
            
            if [[ "$running" == "true" ]]; then
                log_check "OK" "  $container: Running"
            else
                log_check "ERROR" "  $container: $status"
            fi
        else
            log_check "WARNING" "  $container: Not found"
        fi
    done
    
    # Docker compose
    if [[ -f /srv/home/docker-compose.yml ]]; then
        log_check "OK" "Docker Compose: Configuration found"
        
        cd /srv/home 2>/dev/null
        if docker compose ps >/dev/null 2>&1; then
            log_check "OK" "Docker Compose: Working"
        else
            log_check "WARNING" "Docker Compose: Issues detected"
        fi
    else
        log_check "WARNING" "Docker Compose: Configuration not found"
    fi
    
    echo "" | tee -a "$REPORT_FILE"
}

check_services() {
    log_section "🚪 СЕРВИСЫ И ПОРТЫ"
    
    # Home Assistant
    if timeout 3 bash -c '</dev/tcp/localhost/8123' 2>/dev/null; then
        log_check "OK" "Home Assistant (8123): Accessible"
    else
        log_check "ERROR" "Home Assistant (8123): Not accessible"
    fi
    
    # Node-RED
    if timeout 3 bash -c '</dev/tcp/localhost/1880' 2>/dev/null; then
        log_check "OK" "Node-RED (1880): Accessible"
    else
        log_check "WARNING" "Node-RED (1880): Not accessible"
    fi
    
    # SSH
    if timeout 3 bash -c '</dev/tcp/localhost/22' 2>/dev/null; then
        log_check "OK" "SSH (22): Accessible"
    else
        log_check "WARNING" "SSH (22): Not accessible"
    fi
    
    echo "" | tee -a "$REPORT_FILE"
}

check_monitoring() {
    log_section "🔍 СИСТЕМА МОНИТОРИНГА"
    
    # Check if monitoring is installed
    if [[ -f /usr/local/bin/ha-watchdog.sh ]]; then
        log_check "OK" "HA Watchdog: Installed"
    else
        log_check "WARNING" "HA Watchdog: Not installed"
    fi
    
    if [[ -f /usr/local/bin/ha-responder.sh ]]; then
        log_check "OK" "HA Responder: Installed"
    else
        log_check "WARNING" "HA Responder: Not installed"
    fi
    
    # Systemd timers
    if systemctl is-active ha-watchdog.timer >/dev/null 2>&1; then
        log_check "OK" "Watchdog Timer: Active"
    else
        log_check "WARNING" "Watchdog Timer: Inactive"
    fi
    
    if systemctl is-active ha-responder.timer >/dev/null 2>&1; then
        log_check "OK" "Responder Timer: Active"
    else
        log_check "WARNING" "Responder Timer: Inactive"
    fi
    
    # Configuration
    if [[ -f /etc/ha-watchdog/config ]]; then
        log_check "OK" "Configuration: Found"
        
        source /etc/ha-watchdog/config 2>/dev/null
        
        if [[ -n "$TELEGRAM_BOT_TOKEN" ]] && [[ -n "$TELEGRAM_CHAT_ID" ]]; then
            log_check "OK" "Telegram: Configured"
        else
            log_check "WARNING" "Telegram: Not configured"
        fi
    else
        log_check "WARNING" "Configuration: Not found"
    fi
    
    # Log files
    if [[ -f /var/log/ha-watchdog.log ]]; then
        local last_entry=$(tail -1 /var/log/ha-watchdog.log 2>/dev/null)
        if [[ -n "$last_entry" ]]; then
            log_check "OK" "Watchdog Log: Active (last: $(echo $last_entry | awk '{print $1, $2}'))"
        else
            log_check "WARNING" "Watchdog Log: Empty"
        fi
    else
        log_check "WARNING" "Watchdog Log: Not found"
    fi
    
    if [[ -f /var/log/ha-failures.log ]]; then
        local failure_count=$(wc -l < /var/log/ha-failures.log 2>/dev/null)
        if [[ $failure_count -gt 0 ]]; then
            log_check "INFO" "Failures Log: $failure_count entries"
        else
            log_check "OK" "Failures Log: No failures recorded"
        fi
    else
        log_check "INFO" "Failures Log: Not found"
    fi

    # Telegram Sender Service (NEW - September 2025)
    log_check "INFO" "--- Telegram Sender Service ---"
    
    if [[ -f /usr/local/bin/telegram-sender.sh ]]; then
        log_check "OK" "Telegram Sender: Installed"
        
        # Test if executable
        if [[ -x /usr/local/bin/telegram-sender.sh ]]; then
            log_check "OK" "Telegram Sender: Executable"
        else
            log_check "WARNING" "Telegram Sender: Not executable"
        fi
    else
        log_check "WARNING" "Telegram Sender: Not installed"
    fi
    
    # Configuration check
    if [[ -f /etc/telegram-sender/config ]]; then
        log_check "OK" "Telegram Config: Found (/etc/telegram-sender/config)"
        
        # Check permissions
        local perms=$(stat -c%a /etc/telegram-sender/config 2>/dev/null)
        if [[ "$perms" == "600" ]]; then
            log_check "OK" "Telegram Config: Secure permissions (600)"
        else
            log_check "WARNING" "Telegram Config: Insecure permissions ($perms, should be 600)"
        fi
        
        # Check configuration content
        if grep -q "TELEGRAM_BOT_TOKEN=" /etc/telegram-sender/config 2>/dev/null; then
            if grep -q "your_bot_token_here" /etc/telegram-sender/config 2>/dev/null; then
                log_check "WARNING" "Telegram Config: Default token not changed"
            else
                log_check "OK" "Telegram Config: Bot token configured"
            fi
        else
            log_check "ERROR" "Telegram Config: Bot token missing"
        fi
        
        if grep -q "TELEGRAM_CHAT_ID=" /etc/telegram-sender/config 2>/dev/null; then
            if grep -q "your_group_chat_id" /etc/telegram-sender/config 2>/dev/null; then
                log_check "WARNING" "Telegram Config: Default chat ID not changed"
            else
                log_check "OK" "Telegram Config: Chat ID configured"
            fi
        else
            log_check "ERROR" "Telegram Config: Chat ID missing"
        fi
        
        # Check topic configuration
        local topics_found=0
        for topic in "TELEGRAM_TOPIC_SYSTEM" "TELEGRAM_TOPIC_ERRORS" "TELEGRAM_TOPIC_UPDATES" "TELEGRAM_TOPIC_RESTART"; do
            if grep -q "$topic=" /etc/telegram-sender/config 2>/dev/null; then
                ((topics_found++))
            fi
        done
        log_check "INFO" "Telegram Topics: $topics_found/4 configured"
        
    else
        log_check "ERROR" "Telegram Config: Not found (/etc/telegram-sender/config)"
    fi
    
    # Log file check
    if [[ -f /var/log/telegram-sender.log ]]; then
        local log_size=$(du -h /var/log/telegram-sender.log 2>/dev/null | cut -f1)
        local log_lines=$(wc -l < /var/log/telegram-sender.log 2>/dev/null)
        log_check "OK" "Telegram Log: Found ($log_size, $log_lines entries)"
        
        # Check recent activity
        if [[ -s /var/log/telegram-sender.log ]]; then
            local last_entry=$(tail -1 /var/log/telegram-sender.log 2>/dev/null)
            if [[ -n "$last_entry" ]]; then
                local last_time=$(echo "$last_entry" | awk '{print $1, $2}')
                log_check "INFO" "Last Activity: $last_time"
                
                # Check for recent successful sends
                local recent_success=$(grep -c "SUCCESS" /var/log/telegram-sender.log 2>/dev/null)
                local recent_errors=$(grep -c "ERROR" /var/log/telegram-sender.log 2>/dev/null)
                log_check "INFO" "Statistics: $recent_success successful, $recent_errors errors"
            fi
        fi
    else
        log_check "WARNING" "Telegram Log: Not found (/var/log/telegram-sender.log)"
    fi
    
    # Logrotate configuration
    if [[ -f /etc/logrotate.d/telegram-sender ]]; then
        log_check "OK" "Logrotate: Configured for telegram-sender"
    else
        log_check "WARNING" "Logrotate: Not configured for telegram-sender"
    fi
    
    # Integration check with monitoring services
    log_check "INFO" "--- Service Integration ---"
    
    # Check if monitoring services use telegram-sender
    if [[ -f /opt/ha-monitoring/scripts/ha-failure-notifier.sh ]]; then
        if grep -q "TELEGRAM_SENDER.*telegram-sender.sh" /opt/ha-monitoring/scripts/ha-failure-notifier.sh 2>/dev/null; then
            log_check "OK" "ha-failure-notifier: Uses telegram-sender"
        else
            log_check "WARNING" "ha-failure-notifier: Uses legacy Telegram method"
        fi
    fi
    
    if [[ -f /opt/ha-monitoring/scripts/update-checker.sh ]]; then
        if grep -q "TELEGRAM_SENDER.*telegram-sender.sh" /opt/ha-monitoring/scripts/update-checker.sh 2>/dev/null; then
            log_check "OK" "update-checker: Uses telegram-sender"
        else
            log_check "WARNING" "update-checker: Uses legacy Telegram method"
        fi
    fi
    
    if [[ -f /opt/ha-monitoring/scripts/nightly-reboot.sh ]]; then
        if grep -q "TELEGRAM_SENDER.*telegram-sender.sh" /opt/ha-monitoring/scripts/nightly-reboot.sh 2>/dev/null; then
            log_check "OK" "nightly-reboot: Uses telegram-sender"
        else
            log_check "WARNING" "nightly-reboot: Uses legacy Telegram method"
        fi
    fi
    
    # Additional checks from ha-system-health-check.sh
    log_check "INFO" "--- State Files ---"
    
    # Monitoring state files
    local monitoring_files=(
        "/var/lib/ha-failure-notifier/last_timestamp.txt"
        "/var/lib/ha-failure-notifier/throttle.txt"
        "/var/lib/ha-failure-notifier/metadata.txt"
    )
    
    for file in "${monitoring_files[@]}"; do
        if [[ -f "$file" ]]; then
            local content=$(head -1 "$file" 2>/dev/null)
            log_check "OK" "State file $(basename $file): Found"
        else
            log_check "INFO" "State file $(basename $file): Not found (created on first run)"
        fi
    done
    
    echo "" | tee -a "$REPORT_FILE"
}

check_logging_service() {
    log_section "📝 ЦЕНТРАЛИЗОВАННОЕ ЛОГИРОВАНИЕ"
    
    # Core logging service checks
    log_check "INFO" "--- Core Logging Service ---"
    
    if [[ -f /usr/local/bin/logging-service.sh ]]; then
        log_check "OK" "Logging Service: Installed"
        
        # Check if executable
        if [[ -x /usr/local/bin/logging-service.sh ]]; then
            log_check "OK" "Logging Service: Executable"
        else
            log_check "ERROR" "Logging Service: Not executable"
        fi
    else
        log_check "ERROR" "Logging Service: Not installed (/usr/local/bin/logging-service.sh)"
        echo "" | tee -a "$REPORT_FILE"
        return
    fi
    
    # Configuration check
    if [[ -f /etc/logging-service/config ]]; then
        log_check "OK" "Logging Config: Found (/etc/logging-service/config)"
        
        # Check permissions
        local perms=$(stat -c%a /etc/logging-service/config 2>/dev/null)
        if [[ "$perms" == "644" ]] || [[ "$perms" == "640" ]]; then
            log_check "OK" "Logging Config: Secure permissions ($perms)"
        else
            log_check "WARNING" "Logging Config: Unusual permissions ($perms)"
        fi
        
        # Check configuration content
        source /etc/logging-service/config 2>/dev/null
        
        if [[ -n "$LOG_FORMAT" ]]; then
            log_check "OK" "Log Format: $LOG_FORMAT"
        else
            log_check "WARNING" "Log Format: Not configured (using default: plain)"
        fi
        
        if [[ -n "$MAX_MESSAGE_LENGTH" ]]; then
            log_check "OK" "Max Message Length: $MAX_MESSAGE_LENGTH chars"
        else
            log_check "INFO" "Max Message Length: Using default (2048 chars)"
        fi
        
        if [[ "$ENABLE_REMOTE_LOGGING" == "true" ]]; then
            if [[ -n "$REMOTE_LOG_ENDPOINT" ]]; then
                log_check "OK" "Remote Logging: Enabled ($REMOTE_LOG_ENDPOINT)"
            else
                log_check "WARNING" "Remote Logging: Enabled but no endpoint configured"
            fi
        else
            log_check "INFO" "Remote Logging: Disabled"
        fi
        
    else
        log_check "ERROR" "Logging Config: Not found (/etc/logging-service/config)"
    fi
    
    # Test logging service functionality
    log_check "INFO" "--- Functionality Tests ---"
    
    # Test if logging service can be sourced
    if source /usr/local/bin/logging-service.sh 2>/dev/null; then
        log_check "OK" "Service Loading: Can be sourced"
        
        # Test if main function exists
        if command -v log_structured >/dev/null 2>&1; then
            log_check "OK" "Core Function: log_structured available"
            
            # Test actual logging functionality
            local test_message="DIAGNOSTIC_TEST_$(date +%s)"
            if log_structured "system-diagnostic" "INFO" "$test_message" 2>/dev/null; then
                log_check "OK" "Logging Test: Functional"
                
                # Verify log was written
                local diagnostic_log="/var/log/ha-system-diagnostic.log"
                if [[ -f "$diagnostic_log" ]] && grep -q "$test_message" "$diagnostic_log" 2>/dev/null; then
                    log_check "OK" "Log Write: Verified (message written to log)"
                else
                    log_check "WARNING" "Log Write: Cannot verify message in log file"
                fi
            else
                log_check "ERROR" "Logging Test: Failed to execute log_structured"
            fi
        else
            log_check "ERROR" "Core Function: log_structured not available"
        fi
        
        # Test helper functions
        if command -v get_log_file >/dev/null 2>&1; then
            log_check "OK" "Helper Function: get_log_file available"
            
            # Test service mapping
            local test_services=("ha-watchdog" "ha-failure-notifier" "telegram-sender" "ha-failures")
            local mapping_errors=0
            for service in "${test_services[@]}"; do
                local log_file=$(get_log_file "$service" 2>/dev/null)
                if [[ -n "$log_file" ]] && [[ "$log_file" =~ ^/var/log/ ]]; then
                    # Service mapping working
                    continue
                else
                    ((mapping_errors++))
                fi
            done
            
            if [[ $mapping_errors -eq 0 ]]; then
                log_check "OK" "Service Mapping: All core services mapped correctly"
            else
                log_check "WARNING" "Service Mapping: $mapping_errors services have mapping issues"
            fi
        else
            log_check "WARNING" "Helper Function: get_log_file not available"
        fi
        
    else
        log_check "ERROR" "Service Loading: Cannot source logging-service.sh"
    fi
    
    # Check logging service's own log
    log_check "INFO" "--- Service Monitoring ---"
    
    local service_log="/var/log/logging-service.log"
    if [[ -f "$service_log" ]]; then
        local log_size=$(du -h "$service_log" 2>/dev/null | cut -f1)
        local log_lines=$(wc -l < "$service_log" 2>/dev/null)
        log_check "OK" "Service Log: Found ($log_size, $log_lines entries)"
        
        # Check for recent activity
        if [[ -s "$service_log" ]]; then
            local last_entry=$(tail -1 "$service_log" 2>/dev/null)
            if [[ -n "$last_entry" ]]; then
                local last_time=$(echo "$last_entry" | awk '{print $1, $2}')
                log_check "INFO" "Last Activity: $last_time"
                
                # Check for errors in logging service
                local recent_errors=$(grep -c "ERROR\|CRITICAL" "$service_log" 2>/dev/null)
                if [[ $recent_errors -eq 0 ]]; then
                    log_check "OK" "Service Health: No errors in service log"
                else
                    log_check "WARNING" "Service Health: $recent_errors errors found in service log"
                fi
            fi
        fi
    else
        log_check "INFO" "Service Log: Not found (created on first use)"
    fi
    
    # Check integration with dependent services
    log_check "INFO" "--- Service Dependencies ---"
    
    local dependent_services=(
        "/usr/local/bin/ha-watchdog.sh"
        "/usr/local/bin/ha-failure-notifier.sh"
        "/usr/local/bin/update-checker.sh"
        "/usr/local/bin/nightly-reboot.sh"
    )
    
    local integration_count=0
    for service_file in "${dependent_services[@]}"; do
        if [[ -f "$service_file" ]]; then
            if grep -q "logging-service\.sh" "$service_file" 2>/dev/null; then
                ((integration_count++))
            fi
        fi
    done
    
    log_check "INFO" "Service Integration: $integration_count/4 services use logging-service"
    
    if [[ $integration_count -eq 4 ]]; then
        log_check "OK" "Architecture: Full centralized logging adoption"
    elif [[ $integration_count -gt 2 ]]; then
        log_check "WARNING" "Architecture: Partial centralized logging adoption"
    else
        log_check "ERROR" "Architecture: Minimal centralized logging adoption"
    fi
    
    # Check log files managed by logging service
    log_check "INFO" "--- Managed Log Files ---"
    
    local managed_logs=(
        "/var/log/ha-watchdog.log"
        "/var/log/ha-failure-notifier.log"
        "/var/log/ha-failures.log"
        "/var/log/telegram-sender.log"
        "/var/log/ha-update-checker.log"
    )
    
    local healthy_logs=0
    for log_file in "${managed_logs[@]}"; do
        if [[ -f "$log_file" ]]; then
            local size=$(du -h "$log_file" 2>/dev/null | cut -f1)
            local lines=$(wc -l < "$log_file" 2>/dev/null)
            
            # Check if log is not too large (>100MB = problem)
            local size_mb=$(du -m "$log_file" 2>/dev/null | cut -f1)
            if [[ $size_mb -gt 100 ]]; then
                log_check "WARNING" "Log File $(basename $log_file): Large size ($size, $lines lines)"
            else
                log_check "OK" "Log File $(basename $log_file): Healthy ($size, $lines lines)"
                ((healthy_logs++))
            fi
        else
            log_check "INFO" "Log File $(basename $log_file): Not found (created on first use)"
        fi
    done
    
    if [[ $healthy_logs -eq ${#managed_logs[@]} ]]; then
        log_check "OK" "Log Management: All managed logs are healthy"
    elif [[ $healthy_logs -gt 3 ]]; then
        log_check "WARNING" "Log Management: Most logs healthy ($healthy_logs/${#managed_logs[@]})"
    else
        log_check "WARNING" "Log Management: Few logs healthy ($healthy_logs/${#managed_logs[@]})"
    fi
    
    # Logrotate integration
    if [[ -f /etc/logrotate.d/logging-service ]]; then
        log_check "OK" "Logrotate: Configured for logging-service"
    else
        log_check "WARNING" "Logrotate: Not configured for logging-service"
    fi
    
    if [[ -f /etc/logrotate.d/ha-general-logs ]]; then
        log_check "OK" "Logrotate: Configured for HA logs"
    else
        log_check "WARNING" "Logrotate: Not configured for HA logs"
    fi
    
    echo "" | tee -a "$REPORT_FILE"
}

check_tailscale() {
    log_section "🔗 TAILSCALE VPN"
    
    if ! command -v tailscale >/dev/null 2>&1; then
        log_check "INFO" "Tailscale: Not installed"
        echo "" | tee -a "$REPORT_FILE"
        return
    fi
    
    log_check "INFO" "Tailscale Version: $(tailscale version | head -1)"
    
    # Tailscale daemon status
    if systemctl is-active tailscaled >/dev/null 2>&1; then
        log_check "OK" "Tailscaled Daemon: Running"
    else
        log_check "ERROR" "Tailscaled Daemon: Not running"
        echo "" | tee -a "$REPORT_FILE"
        return
    fi
    
    # Tailscale status
    local ts_status=$(tailscale status --json 2>/dev/null)
    if [[ $? -eq 0 ]]; then
        local backend_state=$(echo "$ts_status" | jq -r '.BackendState' 2>/dev/null)
        case "$backend_state" in
            "Running")
                log_check "OK" "Tailscale Status: Connected"
                ;;
            "NeedsLogin")
                log_check "WARNING" "Tailscale Status: Needs authentication"
                ;;
            "NoState"|"Stopped")
                log_check "ERROR" "Tailscale Status: Not connected"
                ;;
            *)
                log_check "WARNING" "Tailscale Status: $backend_state"
                ;;
        esac
        
        # Get current node info
        local self_info=$(echo "$ts_status" | jq -r '.Self // empty' 2>/dev/null)
        if [[ -n "$self_info" ]] && [[ "$self_info" != "null" ]]; then
            local hostname=$(echo "$self_info" | jq -r '.HostName // "unknown"' 2>/dev/null)
            local tailscale_ip=$(echo "$self_info" | jq -r '.TailscaleIPs[0] // "unknown"' 2>/dev/null)
            local online=$(echo "$self_info" | jq -r '.Online // false' 2>/dev/null)
            
            log_check "INFO" "Hostname: $hostname"
            log_check "INFO" "Tailscale IP: $tailscale_ip"
            
            if [[ "$online" == "true" ]]; then
                log_check "OK" "Node Status: Online"
            else
                log_check "WARNING" "Node Status: Offline"
            fi
        fi
        
        # Count peers
        local peer_count=$(echo "$ts_status" | jq '.Peer | length' 2>/dev/null)
        if [[ -n "$peer_count" ]] && [[ "$peer_count" != "null" ]]; then
            log_check "INFO" "Connected Peers: $peer_count"
        fi
    else
        log_check "WARNING" "Tailscale Status: Cannot retrieve status"
    fi
    
    # Check Tailscale services
    if systemctl is-active tailscale-serve-ha >/dev/null 2>&1; then
        log_check "OK" "Tailscale Serve HA: Active"
    else
        log_check "INFO" "Tailscale Serve HA: Inactive"
    fi
    
    if systemctl is-active tailscale-funnel-ha >/dev/null 2>&1; then
        log_check "OK" "Tailscale Funnel HA: Active"
    else
        log_check "INFO" "Tailscale Funnel HA: Inactive"
    fi
    
    # Check if Home Assistant is accessible via Tailscale
    if [[ -n "$tailscale_ip" ]] && [[ "$tailscale_ip" != "unknown" ]]; then
        if timeout 3 bash -c "</dev/tcp/$tailscale_ip/8123" 2>/dev/null; then
            log_check "OK" "HA via Tailscale ($tailscale_ip:8123): Accessible"
        else
            log_check "WARNING" "HA via Tailscale ($tailscale_ip:8123): Not accessible"
        fi
    fi
    
    echo "" | tee -a "$REPORT_FILE"
}

check_security() {
    log_section "🔒 БЕЗОПАСНОСТЬ"
    
    # SSH configuration
    if [[ -f /etc/ssh/sshd_config ]]; then
        local ssh_port=$(grep "^Port" /etc/ssh/sshd_config | awk '{print $2}')
        if [[ "$ssh_port" != "22" ]]; then
            log_check "OK" "SSH Port: Changed ($ssh_port)"
        else
            log_check "WARNING" "SSH Port: Default (22)"
        fi
        
        if grep -q "PasswordAuthentication no" /etc/ssh/sshd_config; then
            log_check "OK" "SSH Password Auth: Disabled"
        else
            log_check "WARNING" "SSH Password Auth: Enabled"
        fi
        
        if grep -q "PermitRootLogin" /etc/ssh/sshd_config; then
            local root_login=$(grep "PermitRootLogin" /etc/ssh/sshd_config | awk '{print $2}')
            if [[ "$root_login" == "yes" ]]; then
                log_check "WARNING" "SSH Root Login: Enabled"
            else
                log_check "OK" "SSH Root Login: $root_login"
            fi
        fi
    fi
    
    # Firewall
    if command -v ufw >/dev/null 2>&1; then
        local ufw_status=$(ufw status | head -1)
        if echo "$ufw_status" | grep -q "active"; then
            log_check "OK" "Firewall (UFW): Active"
        else
            log_check "WARNING" "Firewall (UFW): Inactive"
        fi
    else
        log_check "INFO" "Firewall (UFW): Not installed"
    fi
    
    # Fail2ban
    if command -v fail2ban-client >/dev/null 2>&1; then
        if systemctl is-active fail2ban >/dev/null 2>&1; then
            log_check "OK" "Fail2ban: Service active"
            
            # Check jail status
            local jail_count=$(fail2ban-client status 2>/dev/null | grep -c "Jail list:" || echo "0")
            if [[ "$jail_count" -gt 0 ]]; then
                local jails=$(fail2ban-client status 2>/dev/null | grep "Jail list:" | cut -d: -f2 | tr -d ' ' | tr ',' ' ')
                log_check "INFO" "Fail2ban Jails: $jails"
                
                # Check banned IPs
                local total_banned=0
                for jail in $jails; do
                    local banned=$(fail2ban-client status "$jail" 2>/dev/null | grep "Currently banned:" | awk '{print $NF}' || echo "0")
                    total_banned=$((total_banned + banned))
                done
                log_check "INFO" "Currently Banned IPs: $total_banned"
            fi
        else
            log_check "WARNING" "Fail2ban: Service inactive"
        fi
    else
        log_check "INFO" "Fail2ban: Not installed"
    fi
    
    # Security updates check
    if command -v apt >/dev/null 2>&1; then
        log_check "INFO" "--- Security Updates ---"
        # Update package list if older than 1 day
        local apt_update_time=$(stat -c %Y /var/lib/apt/lists/ 2>/dev/null || echo "0")
        local current_time=$(date +%s)
        local time_diff=$((current_time - apt_update_time))
        
        if [[ $time_diff -gt 86400 ]]; then
            log_check "INFO" "Package list is outdated (>24h), checking anyway..."
        fi
        
        local security_updates=$(apt list --upgradable 2>/dev/null | grep -c security || echo "0")
        local total_updates=$(apt list --upgradable 2>/dev/null | wc -l)
        
        if [[ "$security_updates" -eq 0 ]]; then
            log_check "OK" "Security Updates: None pending"
        else
            log_check "WARNING" "Security Updates: $security_updates security updates pending"
        fi
        
        if [[ "$total_updates" -gt 0 ]]; then
            log_check "INFO" "Total Updates Available: $total_updates"
        fi
    fi
    
    # File permissions
    if [[ -f /etc/ha-watchdog/config ]]; then
        local perms=$(stat -c %a /etc/ha-watchdog/config)
        if [[ "$perms" == "600" ]] || [[ "$perms" == "640" ]]; then
            log_check "OK" "Config File Permissions: Secure ($perms)"
        else
            log_check "WARNING" "Config File Permissions: Insecure ($perms)"
        fi
    fi
    
    echo "" | tee -a "$REPORT_FILE"
}

check_recent_failures() {
    log_section "📈 АНАЛИЗ ПОСЛЕДНИХ СБОЕВ"
    
    local failure_log="/var/log/ha-failures.log"
    if [[ -f "$failure_log" ]]; then
        local today=$(date +%Y-%m-%d)
        local failures_today=$(grep "$today" "$failure_log" 2>/dev/null | wc -l)
        
        if [[ "$failures_today" -eq 0 ]]; then
            log_check "OK" "Failures Today: No failures detected"
        elif [[ "$failures_today" -lt 10 ]]; then
            log_check "WARNING" "Failures Today: $failures_today failures detected"
        else
            log_check "ERROR" "Failures Today: Many failures - $failures_today"
        fi
        
        # Show last 5 failures
        local recent_failures=$(tail -n 5 "$failure_log" 2>/dev/null)
        if [[ -n "$recent_failures" ]]; then
            log_check "INFO" "Last 5 failure entries:"
            echo "$recent_failures" | while read line; do
                echo "  $line" | tee -a "$REPORT_FILE"
            done
        fi
        
        # Weekly failure statistics
        local week_ago=$(date -d '7 days ago' +%Y-%m-%d)
        local failures_week=$(awk -v start="$week_ago" -v end="$today" '$1 >= start && $1 <= end' "$failure_log" 2>/dev/null | wc -l)
        log_check "INFO" "Failures This Week: $failures_week total"
        
    else
        log_check "WARNING" "Failures Log: Not found"
    fi
    
    # Notification statistics
    local notifier_log="/var/log/ha-failure-notifier.log"
    if [[ -f "$notifier_log" ]]; then
        local today=$(date +%Y-%m-%d)
        local recent_notifications=$(grep "$today" "$notifier_log" 2>/dev/null | grep -c "SUCCESS\|SENT" || echo "0")
        local recent_throttled=$(grep "$today" "$notifier_log" 2>/dev/null | grep -c "THROTTLED" || echo "0")
        local recent_errors=$(grep "$today" "$notifier_log" 2>/dev/null | grep -c "ERROR\|FAILED" || echo "0")
        
        log_check "INFO" "Notifications Today: $recent_notifications sent"
        if [[ "$recent_throttled" -gt 0 ]]; then
            log_check "INFO" "Throttled Events: $recent_throttled (spam protection)"
        fi
        if [[ "$recent_errors" -gt 0 ]]; then
            log_check "WARNING" "Notification Errors: $recent_errors failed sends"
        else
            log_check "OK" "Notification Errors: None"
        fi
    fi
    
    echo "" | tee -a "$REPORT_FILE"
}

check_performance() {
    log_section "⚡ ПРОИЗВОДИТЕЛЬНОСТЬ"
    
    # CPU performance test
    log_check "INFO" "--- CPU Performance ---"
    local cpu_cores=$(nproc)
    log_check "INFO" "CPU Cores Available: $cpu_cores"
    
    # Simple CPU test - time a calculation
    local start_time=$(date +%s.%N)
    for i in {1..1000}; do
        echo "scale=10; sqrt($i)" | bc -l >/dev/null 2>&1
    done
    local end_time=$(date +%s.%N)
    local cpu_test_time=$(echo "$end_time - $start_time" | bc | cut -d. -f1)
    
    if [[ "$cpu_test_time" -lt 2 ]]; then
        log_check "OK" "CPU Performance: Good (${cpu_test_time}s for 1000 calculations)"
    elif [[ "$cpu_test_time" -lt 5 ]]; then
        log_check "WARNING" "CPU Performance: Moderate (${cpu_test_time}s for 1000 calculations)"
    else
        log_check "WARNING" "CPU Performance: Slow (${cpu_test_time}s for 1000 calculations)"
    fi
    
    # Disk I/O test
    log_check "INFO" "--- Disk Performance ---"
    if command -v dd >/dev/null 2>&1; then
        local write_test=$(dd if=/dev/zero of=/tmp/test_write bs=1M count=10 oflag=sync 2>&1 | grep -o '[0-9.]\+ [MG]B/s' | head -1)
        rm -f /tmp/test_write
        if [[ -n "$write_test" ]]; then
            log_check "OK" "Disk Write Speed: $write_test"
        else
            log_check "WARNING" "Disk Write Speed: Could not measure"
        fi
        
        local read_test=$(dd if=/dev/zero of=/tmp/test_read bs=1M count=10 iflag=direct 2>&1 | grep -o '[0-9.]\+ [MG]B/s' | head -1)
        rm -f /tmp/test_read
        if [[ -n "$read_test" ]]; then
            log_check "OK" "Disk Read Speed: $read_test"
        else
            log_check "WARNING" "Disk Read Speed: Could not measure"
        fi
    else
        log_check "WARNING" "Disk Performance: dd command not available"
    fi
    
    # Memory test
    log_check "INFO" "--- Memory Performance ---"
    if command -v stress-ng >/dev/null 2>&1; then
        local mem_test=$(timeout 3 stress-ng --vm 1 --vm-bytes 64M --timeout 2s --quiet 2>/dev/null && echo "PASS" || echo "FAIL")
        if [[ "$mem_test" == "PASS" ]]; then
            log_check "OK" "Memory Stress Test: Passed"
        else
            log_check "WARNING" "Memory Stress Test: Failed"
        fi
    else
        log_check "INFO" "Memory Stress Test: stress-ng not available"
    fi
    
    echo "" | tee -a "$REPORT_FILE"
}

generate_summary() {
    log_section "📊 ИТОГОВЫЙ ОТЧЕТ"
    
    local total_checks=$(grep -c "\[.*\]" "$REPORT_FILE")
    local ok_checks=$(grep -c "\[OK\]" "$REPORT_FILE")
    local warning_checks=$(grep -c "\[WARNING\]" "$REPORT_FILE")
    local error_checks=$(grep -c "\[ERROR\]" "$REPORT_FILE")
    local info_checks=$(grep -c "\[INFO\]" "$REPORT_FILE")
    
    log_check "INFO" "Total Checks: $total_checks"
    log_check "INFO" "Successful: $ok_checks"
    log_check "INFO" "Warnings: $warning_checks"
    log_check "INFO" "Errors: $error_checks"
    log_check "INFO" "Info: $info_checks"
    
    # Calculate percentage
    local pass_percent=0
    if [[ "$total_checks" -gt 0 ]]; then
        pass_percent=$(( (ok_checks * 100) / total_checks ))
    fi
    log_check "INFO" "Success Rate: ${pass_percent}%"
    
    echo "" | tee -a "$REPORT_FILE"
    
    # Overall system health assessment
    if [[ $error_checks -eq 0 && $warning_checks -eq 0 ]]; then
        log_check "OK" "СИСТЕМА В ОТЛИЧНОМ СОСТОЯНИИ! 🎉"
    elif [[ $error_checks -eq 0 && $warning_checks -lt 5 ]]; then
        log_check "WARNING" "Система в хорошем состоянии (есть предупреждения) ⚠️"
    elif [[ $error_checks -lt 3 ]]; then
        log_check "WARNING" "СИСТЕМА ТРЕБУЕТ ВНИМАНИЯ ⚠️"
    else
        log_check "ERROR" "СИСТЕМА ТРЕБУЕТ НЕМЕДЛЕННОГО ВМЕШАТЕЛЬСТВА! 🚨"
    fi
    
    echo "" | tee -a "$REPORT_FILE"
    log_check "INFO" "Full report saved to: $REPORT_FILE"
}

# Главная функция
main() {
    echo -e "${CYAN}🔍 Запуск диагностики системы...${NC}"
    echo "Отчет: $REPORT_FILE"
    echo ""
    
    echo "=== ДИАГНОСТИКА RASPBERRY PI + HOME ASSISTANT ===" > "$REPORT_FILE"
    echo "Дата: $(date)" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    check_basic_system
    check_resources
    check_network
    check_docker
    check_services
    check_monitoring
    check_logging_service
    check_tailscale
    check_security
    check_recent_failures
    check_performance
    generate_summary
    
    echo ""
    echo -e "${GREEN}✅ Диагностика завершена!${NC}"
    echo -e "${CYAN}📄 Отчет доступен в: $REPORT_FILE${NC}"
}

# Проверка зависимостей
if ! command -v bc >/dev/null 2>&1; then
    echo "⚠️  Внимание: утилита 'bc' не найдена. Некоторые проверки могут работать некорректно."
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "⚠️  Внимание: утилита 'jq' не найдена. Проверка Tailscale будет ограничена."
fi

main "$@"
