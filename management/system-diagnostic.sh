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

generate_summary() {
    log_section "📊 ИТОГОВЫЙ ОТЧЕТ"
    
    local total_checks=$(grep -c "\[.*\]" "$REPORT_FILE")
    local ok_checks=$(grep -c "\[OK\]" "$REPORT_FILE")
    local warning_checks=$(grep -c "\[WARNING\]" "$REPORT_FILE")
    local error_checks=$(grep -c "\[ERROR\]" "$REPORT_FILE")
    
    log_check "INFO" "Всего проверок: $total_checks"
    log_check "INFO" "Успешных: $ok_checks"
    log_check "INFO" "Предупреждений: $warning_checks"
    log_check "INFO" "Ошибок: $error_checks"
    
    echo "" | tee -a "$REPORT_FILE"
    
    if [[ $error_checks -gt 0 ]]; then
        log_check "ERROR" "СИСТЕМА ТРЕБУЕТ ВНИМАНИЯ! Найдены критические проблемы."
    elif [[ $warning_checks -gt 0 ]]; then
        log_check "WARNING" "Система работает, но есть предупреждения."
    else
        log_check "OK" "Система работает нормально!"
    fi
    
    echo "" | tee -a "$REPORT_FILE"
    log_check "INFO" "Полный отчет сохранен в: $REPORT_FILE"
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
    check_security
    generate_summary
    
    echo ""
    echo -e "${GREEN}✅ Диагностика завершена!${NC}"
    echo -e "${CYAN}📄 Отчет доступен в: $REPORT_FILE${NC}"
}

# Проверка зависимостей
if ! command -v bc >/dev/null 2>&1; then
    echo "⚠️  Внимание: утилита 'bc' не найдена. Некоторые проверки могут работать некорректно."
fi

main "$@"
