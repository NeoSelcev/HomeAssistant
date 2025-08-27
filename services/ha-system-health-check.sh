#!/bin/bash

# HA System Health Check - Полная диагностика системы мониторинга
# Проверяет работоспособность всех компонентов Home Assistant мониторинга
# 🚀 СУПЕР КРУТАЯ ВЕРСИЯ с расширенной диагностикой!

VERSION="2.0"
SCRIPT_NAME="HA System Health Check СУПЕР ВЕРСИЯ"
LOG_FILE="/var/log/ha-health-check.log"
REPORT_FILE="/tmp/ha-health-report-$(date +%Y%m%d-%H%M%S).txt"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Счетчики для статистики
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNING_CHECKS=0

# Функции логирования
log() {
    echo "$(date '+%F %T') [HEALTH-CHECK] $1" | tee -a "$LOG_FILE"
}

print_header() {
    local title="$1"
    echo -e "\n${BLUE}================================================================${NC}"
    echo -e "${BLUE}  $title${NC}"
    echo -e "${BLUE}================================================================${NC}"
}

print_section() {
    local section="$1"
    echo -e "\n${CYAN}--- $section ---${NC}"
}

check_result() {
    local test_name="$1"
    local result="$2"
    local details="$3"
    
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    case "$result" in
        "PASS")
            echo -e "[${GREEN}✓ PASS${NC}] $test_name"
            [[ -n "$details" ]] && echo -e "         ${details}"
            PASSED_CHECKS=$((PASSED_CHECKS + 1))
            ;;
        "FAIL")
            echo -e "[${RED}✗ FAIL${NC}] $test_name"
            [[ -n "$details" ]] && echo -e "         ${RED}$details${NC}"
            FAILED_CHECKS=$((FAILED_CHECKS + 1))
            ;;
        "WARN")
            echo -e "[${YELLOW}⚠ WARN${NC}] $test_name"
            [[ -n "$details" ]] && echo -e "         ${YELLOW}$details${NC}"
            WARNING_CHECKS=$((WARNING_CHECKS + 1))
            ;;
    esac
    
    # Записываем в отчет
    echo "[$result] $test_name" >> "$REPORT_FILE"
    [[ -n "$details" ]] && echo "    $details" >> "$REPORT_FILE"
}

# Основные проверки системы
check_basic_system_info() {
    print_section "Базовая информация о системе"
    
    # Основная информация о системе
    check_result "Hostname" "PASS" "$(hostname)"
    check_result "Uptime" "PASS" "$(uptime -p)"
    check_result "Kernel" "PASS" "$(uname -r)"
    check_result "OS" "PASS" "$(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
    check_result "Architecture" "PASS" "$(uname -m)"
    
    # CPU Info
    local cpu_model=$(cat /proc/cpuinfo | grep "model name" | head -1 | cut -d':' -f2 | xargs)
    check_result "CPU Model" "PASS" "$cpu_model"
    
    # CPU Cores
    local cpu_cores=$(nproc)
    check_result "CPU Cores" "PASS" "$cpu_cores"
}

check_system_resources() {
    print_section "Системные ресурсы"
    
    # Проверка использования памяти
    local mem_usage=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')
    local mem_info=$(free -h | grep Mem:)
    local mem_total=$(echo $mem_info | awk '{print $2}')
    local mem_used=$(echo $mem_info | awk '{print $3}')
    local mem_available=$(echo $mem_info | awk '{print $7}')
    local mem_available_mb=$(free -m | awk '/Mem:/ {print $7}')
    
    check_result "Memory Total" "PASS" "$mem_total"
    check_result "Memory Used" "PASS" "$mem_used"
    
    if [[ $mem_available_mb -lt 100 ]]; then
        check_result "Memory Available" "FAIL" "$mem_available (критически мало!)"
    elif [[ $mem_available_mb -lt 200 ]]; then
        check_result "Memory Available" "WARN" "$mem_available (мало)"
    else
        check_result "Memory Available" "PASS" "$mem_available"
    fi
    
    if (( $(echo "$mem_usage > 85" | bc -l) )); then
        check_result "Использование памяти" "WARN" "Использовано ${mem_usage}% (>85%)"
    elif (( $(echo "$mem_usage > 95" | bc -l) )); then
        check_result "Использование памяти" "FAIL" "Критично высокое использование: ${mem_usage}%"
    else
        check_result "Использование памяти" "PASS" "Использовано ${mem_usage}%"
    fi
    
    # Проверка использования диска
    local disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    local disk_info=$(df -h / | tail -1)
    local disk_size=$(echo $disk_info | awk '{print $2}')
    local disk_used=$(echo $disk_info | awk '{print $3}')
    local disk_available=$(echo $disk_info | awk '{print $4}')
    
    check_result "Disk Size" "PASS" "$disk_size"
    check_result "Disk Used" "PASS" "$disk_used"
    
    if [[ "$disk_usage" -gt 90 ]]; then
        check_result "Disk Available" "FAIL" "$disk_available (${disk_usage}% used - критически мало!)"
    elif [[ "$disk_usage" -gt 80 ]]; then
        check_result "Disk Available" "WARN" "$disk_available (${disk_usage}% used - мало)"
    else
        check_result "Disk Available" "PASS" "$disk_available (${disk_usage}% used)"
    fi
    
    if [[ "$disk_usage" -gt 85 ]]; then
        check_result "Использование диска /" "WARN" "Использовано ${disk_usage}% (>85%)"
    elif [[ "$disk_usage" -gt 95 ]]; then
        check_result "Использование диска /" "FAIL" "Критично высокое использование: ${disk_usage}%"
    else
        check_result "Использование диска /" "PASS" "Использовано ${disk_usage}%"
    fi
    
    # Проверка загрузки CPU
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    local cpu_cores=$(nproc)
    local load_ratio=$(echo "scale=2; $load_avg / $cpu_cores" | bc)
    
    if (( $(echo "$load_avg > 2.0" | bc -l) )); then
        check_result "Load Average" "WARN" "$load_avg (высокая нагрузка)"
    else
        check_result "Load Average" "PASS" "$load_avg"
    fi
    
    if (( $(echo "$load_ratio > 1.5" | bc -l) )); then
        check_result "Загрузка системы" "WARN" "Load Average: $load_avg (${load_ratio}x от количества ядер)"
    elif (( $(echo "$load_ratio > 2.0" | bc -l) )); then
        check_result "Загрузка системы" "FAIL" "Критично высокая загрузка: $load_avg"
    else
        check_result "Загрузка системы" "PASS" "Load Average: $load_avg"
    fi
    
    # Проверка температуры (для Raspberry Pi)
    if [[ -f /sys/class/thermal/thermal_zone0/temp ]]; then
        local temp=$(cat /sys/class/thermal/thermal_zone0/temp | awk '{print $1/1000}')
        if (( $(echo "$temp > 70" | bc -l) )); then
            check_result "Temperature" "WARN" "${temp}°C (высокая!)"
        elif (( $(echo "$temp > 60" | bc -l) )); then
            check_result "Temperature" "WARN" "${temp}°C (повышенная)"
        else
            check_result "Temperature" "PASS" "${temp}°C"
        fi
    elif command -v vcgencmd >/dev/null 2>&1; then
        local temp=$(vcgencmd measure_temp | cut -d= -f2 | cut -d"'" -f1)
        if (( $(echo "$temp > 70" | bc -l) )); then
            check_result "Температура CPU" "WARN" "Температура: ${temp}°C (>70°C)"
        elif (( $(echo "$temp > 80" | bc -l) )); then
            check_result "Температура CPU" "FAIL" "Критично высокая температура: ${temp}°C"
        else
            check_result "Температура CPU" "PASS" "Температура: ${temp}°C"
        fi
    fi
    
    # Проверка аптайма
    local uptime_seconds=$(awk '{print int($1)}' /proc/uptime)
    local uptime_days=$((uptime_seconds / 86400))
    local uptime_hours=$(((uptime_seconds % 86400) / 3600))
    check_result "Время работы системы" "PASS" "${uptime_days} дней, ${uptime_hours} часов"
}

check_network_connectivity() {
    print_section "Сетевое подключение"
    
    # Проверка сетевых интерфейсов
    local interfaces=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo)
    check_result "Network Interfaces" "PASS" "$interfaces"
    
    # Check specific interface status
    if ip link show wlan0 &>/dev/null; then
        if ip link show wlan0 | grep -q "state UP"; then
            check_result "WiFi (wlan0)" "PASS" "UP"
        else
            check_result "WiFi (wlan0)" "FAIL" "DOWN"
        fi
    fi
    
    if ip link show eth0 &>/dev/null; then
        if ip link show eth0 | grep -q "state UP"; then
            check_result "Ethernet (eth0)" "PASS" "UP"
        else
            check_result "Ethernet (eth0)" "WARN" "DOWN"
        fi
    fi
    
    # IP addresses
    local ips=$(ip addr show | grep -E "inet.*global" | awk '{print $2, $NF}')
    if [[ -n "$ips" ]]; then
        check_result "IP Addresses" "PASS" "Найдены активные IP"
        echo "$ips" | while read line; do
            echo -e "         $line"
        done
    fi
    
    # Проверка активных интерфейсов
    local active_interfaces=$(ip link show | grep "state UP" | awk -F: '{print $2}' | tr -d ' ')
    if [[ -n "$active_interfaces" ]]; then
        check_result "Сетевые интерфейсы" "PASS" "Активные: $(echo $active_interfaces | tr '\n' ' ')"
    else
        check_result "Сетевые интерфейсы" "FAIL" "Нет активных интерфейсов"
    fi
    
    # Проверка локального шлюза
    local gateway=$(ip route | grep default | awk '{print $3}' | head -1)
    if [[ -n "$gateway" ]] && ping -c 1 -W 3 "$gateway" >/dev/null 2>&1; then
        check_result "Локальный шлюз" "PASS" "Пинг до $gateway успешен"
        check_result "Gateway" "PASS" "$gateway - Reachable"
    else
        check_result "Локальный шлюз" "FAIL" "Нет доступа к шлюзу $gateway"
        check_result "Gateway" "FAIL" "$gateway - Unreachable"
    fi
    
    # Проверка интернет-соединения
    if ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        check_result "Интернет соединение" "PASS" "Пинг до 8.8.8.8 успешен"
        check_result "Internet" "PASS" "Available"
    else
        check_result "Интернет соединение" "FAIL" "Нет доступа в интернет"
        check_result "Internet" "FAIL" "Unavailable"
    fi
    
    # Проверка DNS
    if nslookup google.com >/dev/null 2>&1; then
        check_result "DNS разрешение" "PASS" "DNS работает"
        check_result "DNS" "PASS" "Working"
    else
        check_result "DNS разрешение" "FAIL" "DNS не работает"
        check_result "DNS" "FAIL" "Issues detected"
    fi
}

check_docker_services() {
    print_section "Docker и контейнеры"
    
    # Проверка Docker daemon
    if ! command -v docker >/dev/null 2>&1; then
        check_result "Docker" "FAIL" "Not installed"
        return
    fi
    
    check_result "Docker Version" "PASS" "$(docker --version)"
    
    if systemctl is-active docker >/dev/null 2>&1; then
        check_result "Docker daemon" "PASS" "Служба активна"
        check_result "Docker Daemon" "PASS" "Running"
    else
        check_result "Docker daemon" "FAIL" "Служба не активна"
        check_result "Docker Daemon" "FAIL" "Not running"
        return
    fi
    
    # Docker info
    if docker info >/dev/null 2>&1; then
        check_result "Docker Info" "PASS" "Accessible"
    else
        check_result "Docker Info" "FAIL" "Cannot access daemon"
        return
    fi
    
    # Проверка docker-compose файла
    if [[ -f "/srv/home/docker-compose.yml" ]]; then
        check_result "Docker Compose файл" "PASS" "Файл найден: /srv/home/docker-compose.yml"
        check_result "Docker Compose Configuration" "PASS" "Found"
        
        # Проверка docker compose команд
        cd /srv/home 2>/dev/null
        if docker compose ps >/dev/null 2>&1; then
            check_result "Docker Compose" "PASS" "Working"
        else
            check_result "Docker Compose" "WARN" "Issues detected"
        fi
    else
        check_result "Docker Compose файл" "FAIL" "Файл не найден: /srv/home/docker-compose.yml"
        check_result "Docker Compose Configuration" "FAIL" "Not found"
    fi
    
    # Проверка контейнеров
    local containers=$(docker ps --format "table {{.Names}}\t{{.Status}}" 2>/dev/null)
    if [[ $? -eq 0 ]]; then
        local running_containers=$(docker ps -q | wc -l)
        if [[ "$running_containers" -gt 0 ]]; then
            check_result "Docker контейнеры" "PASS" "$running_containers контейнеров запущено"
            echo -e "         ${containers}"
        else
            check_result "Docker контейнеры" "WARN" "Нет запущенных контейнеров"
        fi
    else
        check_result "Docker контейнеры" "FAIL" "Ошибка при получении списка контейнеров"
    fi
    
    # Проверка конкретных сервисов
    local services=("homeassistant" "nodered" "portainer" "zigbee2mqtt")
    for service in "${services[@]}"; do
        if docker ps --format "{{.Names}}" | grep -q "^${service}$"; then
            local status=$(docker ps --format "{{.Names}}\t{{.Status}}" | grep "^${service}" | cut -f2)
            check_result "Контейнер $service" "PASS" "$status"
        else
            # Проверяем docker inspect для более детальной информации
            if docker inspect "$service" >/dev/null 2>&1; then
                local container_status=$(docker inspect -f '{{.State.Status}}' "$service")
                local running=$(docker inspect -f '{{.State.Running}}' "$service")
                
                if [[ "$running" == "true" ]]; then
                    check_result "Контейнер $service" "PASS" "Running"
                else
                    check_result "Контейнер $service" "FAIL" "$container_status"
                fi
            else
                check_result "Контейнер $service" "WARN" "Контейнер не запущен"
            fi
        fi
    done
}

check_ha_monitoring_services() {
    print_section "HA мониторинг сервисы"
    
    # Проверка systemd сервисов
    local services=("ha-watchdog" "ha-failure-notifier")
    
    for service in "${services[@]}"; do
        if systemctl is-active "${service}.service" >/dev/null 2>&1; then
            local status=$(systemctl show "${service}.service" --property=SubState --value)
            check_result "Сервис $service" "PASS" "Статус: $status"
        else
            check_result "Сервис $service" "FAIL" "Сервис не активен"
        fi
        
        # Проверка timer'ов
        if systemctl is-active "${service}.timer" >/dev/null 2>&1; then
            local next_run=$(systemctl show "${service}.timer" --property=NextElapseUSecRealtime --value)
            if [[ "$next_run" != "0" ]]; then
                check_result "Timer $service" "PASS" "Timer активен"
            else
                check_result "Timer $service" "WARN" "Timer неактивен"
            fi
        else
            check_result "Timer $service" "FAIL" "Timer не найден"
        fi
    done
    
    # Проверка скриптов мониторинга
    local scripts=("/opt/ha-monitoring/scripts/ha-watchdog.sh" "/opt/ha-monitoring/scripts/ha-failure-notifier.sh")
    
    for script in "${scripts[@]}"; do
        if [[ -f "$script" ]]; then
            if [[ -x "$script" ]]; then
                # Проверка синтаксиса
                if bash -n "$script" 2>/dev/null; then
                    check_result "Скрипт $(basename $script)" "PASS" "Файл найден и синтаксис корректен"
                else
                    check_result "Скрипт $(basename $script)" "FAIL" "Ошибка синтаксиса"
                fi
            else
                check_result "Скрипт $(basename $script)" "WARN" "Файл найден, но не исполняемый"
            fi
        else
            check_result "Скрипт $(basename $script)" "FAIL" "Файл не найден"
        fi
    done
}

check_log_files() {
    print_section "Лог файлы и их состояние"
    
    local log_files=(
        "/var/log/ha-failures.log"
        "/var/log/ha-failure-notifier.log" 
        "/var/log/ha-watchdog.log"
    )
    
    for log_file in "${log_files[@]}"; do
        if [[ -f "$log_file" ]]; then
            local size=$(stat -c%s "$log_file" 2>/dev/null || echo "0")
            local size_mb=$((size / 1024 / 1024))
            local age=$(find "$log_file" -mtime +1 2>/dev/null)
            
            if [[ "$size_mb" -gt 100 ]]; then
                check_result "Лог $(basename $log_file)" "WARN" "Размер: ${size_mb}MB (>100MB)"
            elif [[ "$size_mb" -gt 500 ]]; then
                check_result "Лог $(basename $log_file)" "FAIL" "Критично большой размер: ${size_mb}MB"
            else
                check_result "Лог $(basename $log_file)" "PASS" "Размер: ${size_mb}MB"
            fi
            
            # Проверка последних записей
            local recent_entries=$(tail -n 50 "$log_file" 2>/dev/null | grep "$(date +%Y-%m-%d)" | wc -l)
            if [[ "$recent_entries" -gt 0 ]]; then
                echo -e "         Записей сегодня: $recent_entries"
            else
                echo -e "         ${YELLOW}Нет записей за сегодня${NC}"
            fi
        else
            check_result "Лог $(basename $log_file)" "FAIL" "Файл не найден"
        fi
    done
    
    # Проверка состояния файлов мониторинга
    local monitoring_files=(
        "/var/lib/ha-failure-notifier/last_timestamp.txt"
        "/var/lib/ha-failure-notifier/throttle.txt"
        "/var/lib/ha-failure-notifier/metadata.txt"
    )
    
    print_section "Файлы состояния мониторинга"
    for file in "${monitoring_files[@]}"; do
        if [[ -f "$file" ]]; then
            local content=$(head -1 "$file" 2>/dev/null)
            check_result "Файл $(basename $file)" "PASS" "Содержимое: $content"
        else
            check_result "Файл $(basename $file)" "WARN" "Файл не найден (будет создан при первом запуске)"
        fi
    done
}

check_tailscale_vpn() {
    print_section "Tailscale VPN"
    
    if ! command -v tailscale >/dev/null 2>&1; then
        check_result "Tailscale" "WARN" "Not installed"
        return
    fi
    
    check_result "Tailscale Version" "PASS" "$(tailscale version | head -1)"
    
    # Tailscale daemon status
    if systemctl is-active tailscaled >/dev/null 2>&1; then
        check_result "Tailscaled Daemon" "PASS" "Running"
    else
        check_result "Tailscaled Daemon" "FAIL" "Not running"
        return
    fi
    
    # Tailscale status
    local ts_status=$(tailscale status --json 2>/dev/null)
    if [[ $? -eq 0 ]]; then
        local backend_state=$(echo "$ts_status" | jq -r '.BackendState' 2>/dev/null)
        case "$backend_state" in
            "Running")
                check_result "Tailscale Status" "PASS" "Connected"
                ;;
            "NeedsLogin")
                check_result "Tailscale Status" "WARN" "Needs authentication"
                ;;
            "NoState"|"Stopped")
                check_result "Tailscale Status" "FAIL" "Not connected"
                ;;
            *)
                check_result "Tailscale Status" "WARN" "$backend_state"
                ;;
        esac
        
        # Get current node info
        local self_info=$(echo "$ts_status" | jq -r '.Self // empty' 2>/dev/null)
        if [[ -n "$self_info" ]] && [[ "$self_info" != "null" ]]; then
            local hostname=$(echo "$self_info" | jq -r '.HostName // "unknown"' 2>/dev/null)
            local tailscale_ip=$(echo "$self_info" | jq -r '.TailscaleIPs[0] // "unknown"' 2>/dev/null)
            local online=$(echo "$self_info" | jq -r '.Online // false' 2>/dev/null)
            
            check_result "Tailscale Hostname" "PASS" "$hostname"
            check_result "Tailscale IP" "PASS" "$tailscale_ip"
            
            if [[ "$online" == "true" ]]; then
                check_result "Node Status" "PASS" "Online"
            else
                check_result "Node Status" "WARN" "Offline"
            fi
            
            # Check if Home Assistant is accessible via Tailscale
            if [[ -n "$tailscale_ip" ]] && [[ "$tailscale_ip" != "unknown" ]]; then
                if timeout 3 bash -c "</dev/tcp/$tailscale_ip/8123" 2>/dev/null; then
                    check_result "HA via Tailscale" "PASS" "$tailscale_ip:8123 - Accessible"
                else
                    check_result "HA via Tailscale" "WARN" "$tailscale_ip:8123 - Not accessible"
                fi
            fi
        fi
        
        # Count peers
        local peer_count=$(echo "$ts_status" | jq '.Peer | length' 2>/dev/null)
        if [[ -n "$peer_count" ]] && [[ "$peer_count" != "null" ]]; then
            check_result "Connected Peers" "PASS" "$peer_count"
        fi
    else
        check_result "Tailscale Status" "WARN" "Cannot retrieve status"
    fi
    
    # Check Tailscale services
    if systemctl is-active tailscale-serve-ha >/dev/null 2>&1; then
        check_result "Tailscale Serve HA" "PASS" "Active"
    else
        check_result "Tailscale Serve HA" "WARN" "Inactive"
    fi
    
    if systemctl is-active tailscale-funnel-ha >/dev/null 2>&1; then
        check_result "Tailscale Funnel HA" "PASS" "Active"
    else
        check_result "Tailscale Funnel HA" "WARN" "Inactive"
    fi
}

check_ha_services_availability() {
    print_section "Доступность HA сервисов"
    
    # Функция проверки порта через /dev/tcp (как в watchdog)
    check_tcp_port() {
        local host="$1"
        local port="$2"
        timeout 5 bash -c "</dev/tcp/$host/$port" 2>/dev/null
    }
    
    # Проверка Home Assistant
    local ha_ports=("8123")
    for port in "${ha_ports[@]}"; do
        if check_tcp_port "localhost" "$port"; then
            check_result "Home Assistant (порт $port)" "PASS" "Сервис отвечает"
        else
            check_result "Home Assistant (порт $port)" "FAIL" "Сервис недоступен"
        fi
    done
    
    # Проверка Node-RED
    if check_tcp_port "localhost" "1880"; then
        check_result "Node-RED (порт 1880)" "PASS" "Сервис отвечает"
    else
        check_result "Node-RED (порт 1880)" "WARN" "Сервис недоступен"
    fi
    
    # Проверка Portainer
    if check_tcp_port "localhost" "9000"; then
        check_result "Portainer (порт 9000)" "PASS" "Сервис отвечает"
    else
        check_result "Portainer (порт 9000)" "WARN" "Сервис недоступен"
    fi
    
    # Проверка Zigbee2MQTT
    if check_tcp_port "localhost" "8080"; then
        check_result "Zigbee2MQTT (порт 8080)" "PASS" "Сервис отвечает"
    else
        check_result "Zigbee2MQTT (порт 8080)" "WARN" "Сервис недоступен"
    fi
}

check_recent_failures() {
    print_section "Анализ последних сбоев"
    
    local failure_log="/var/log/ha-failures.log"
    if [[ -f "$failure_log" ]]; then
        local today=$(date +%Y-%m-%d)
        local failures_today=$(grep "$today" "$failure_log" 2>/dev/null | wc -l)
        
        if [[ "$failures_today" -eq 0 ]]; then
            check_result "Сбои за сегодня" "PASS" "Сбоев не обнаружено"
        elif [[ "$failures_today" -lt 10 ]]; then
            check_result "Сбои за сегодня" "WARN" "$failures_today сбоев обнаружено"
        else
            check_result "Сбои за сегодня" "FAIL" "Много сбоев: $failures_today"
        fi
        
        # Показываем последние 5 сбоев
        local recent_failures=$(tail -n 5 "$failure_log" 2>/dev/null)
        if [[ -n "$recent_failures" ]]; then
            echo -e "         ${CYAN}Последние 5 записей:${NC}"
            echo "$recent_failures" | while read line; do
                echo -e "         $line"
            done
        fi
    else
        check_result "Лог сбоев" "WARN" "Файл лога не найден"
    fi
    
    # Проверка работы уведомлений
    local notifier_log="/var/log/ha-failure-notifier.log"
    if [[ -f "$notifier_log" ]]; then
        local recent_notifications=$(grep "$(date +%Y-%m-%d)" "$notifier_log" 2>/dev/null | grep "TELEGRAM_SENT" | wc -l)
        local recent_throttled=$(grep "$(date +%Y-%m-%d)" "$notifier_log" 2>/dev/null | grep "THROTTLED" | wc -l)
        
        echo -e "         Уведомлений отправлено сегодня: $recent_notifications"
        echo -e "         Событий заблокировано троттлингом: $recent_throttled"
    fi
}

check_system_security() {
    print_section "Безопасность системы"
    
    # Проверка SSH
    if systemctl is-active ssh >/dev/null 2>&1; then
        check_result "SSH сервис" "PASS" "Сервис активен"
    else
        check_result "SSH сервис" "WARN" "SSH сервис неактивен"
    fi
    
    # SSH configuration
    if [[ -f /etc/ssh/sshd_config ]]; then
        local ssh_port=$(grep "^Port" /etc/ssh/sshd_config | awk '{print $2}')
        if [[ -n "$ssh_port" && "$ssh_port" != "22" ]]; then
            check_result "SSH Port" "PASS" "Changed ($ssh_port)"
        else
            check_result "SSH Port" "WARN" "Default (22)"
        fi
        
        if grep -q "PasswordAuthentication no" /etc/ssh/sshd_config; then
            check_result "SSH Password Auth" "PASS" "Disabled"
        else
            check_result "SSH Password Auth" "WARN" "Enabled"
        fi
        
        if grep -q "PermitRootLogin" /etc/ssh/sshd_config; then
            local root_login=$(grep "PermitRootLogin" /etc/ssh/sshd_config | awk '{print $2}')
            if [[ "$root_login" == "yes" ]]; then
                check_result "SSH Root Login" "WARN" "Enabled"
            else
                check_result "SSH Root Login" "PASS" "$root_login"
            fi
        fi
    fi
    
    # Проверка firewall
    if command -v ufw >/dev/null 2>&1; then
        local ufw_status=$(ufw status | head -1)
        if echo "$ufw_status" | grep -q "active"; then
            check_result "Firewall (UFW)" "PASS" "Активен"
        else
            check_result "Firewall (UFW)" "WARN" "Неактивен"
        fi
    else
        check_result "Firewall (UFW)" "WARN" "Not installed"
    fi
    
    # Проверка fail2ban
    if systemctl is-active fail2ban >/dev/null 2>&1; then
        check_result "Fail2ban" "PASS" "Сервис активен"
    else
        check_result "Fail2ban" "WARN" "Сервис неактивен"
    fi
    
    # File permissions for monitoring configs
    if [[ -f /etc/ha-watchdog/config ]]; then
        local perms=$(stat -c %a /etc/ha-watchdog/config)
        if [[ "$perms" == "600" ]] || [[ "$perms" == "640" ]]; then
            check_result "Config File Permissions" "PASS" "Secure ($perms)"
        else
            check_result "Config File Permissions" "WARN" "Insecure ($perms)"
        fi
    fi
    
    # Проверка обновлений безопасности
    if command -v apt >/dev/null 2>&1; then
        local security_updates=$(apt list --upgradable 2>/dev/null | grep -c security || echo "0")
        if [[ "$security_updates" -eq 0 ]]; then
            check_result "Обновления безопасности" "PASS" "Нет ожидающих обновлений"
        else
            check_result "Обновления безопасности" "WARN" "$security_updates обновлений ожидает"
        fi
    fi
}

generate_summary() {
    print_header "СВОДКА РЕЗУЛЬТАТОВ"
    
    local pass_percent=0
    if [[ "$TOTAL_CHECKS" -gt 0 ]]; then
        pass_percent=$(( (PASSED_CHECKS * 100) / TOTAL_CHECKS ))
    fi
    
    echo -e "Всего проверок выполнено: ${BLUE}$TOTAL_CHECKS${NC}"
    echo -e "Успешно пройдено: ${GREEN}$PASSED_CHECKS${NC} (${pass_percent}%)"
    echo -e "Предупреждения: ${YELLOW}$WARNING_CHECKS${NC}"
    echo -e "Ошибки: ${RED}$FAILED_CHECKS${NC}"
    
    # Общая оценка состояния системы
    if [[ "$FAILED_CHECKS" -eq 0 && "$WARNING_CHECKS" -eq 0 ]]; then
        echo -e "\n${GREEN}🎉 СИСТЕМА В ОТЛИЧНОМ СОСТОЯНИИ${NC}"
    elif [[ "$FAILED_CHECKS" -eq 0 && "$WARNING_CHECKS" -lt 5 ]]; then
        echo -e "\n${YELLOW}⚠️  СИСТЕМА В ХОРОШЕМ СОСТОЯНИИ (есть предупреждения)${NC}"
    elif [[ "$FAILED_CHECKS" -lt 3 ]]; then
        echo -e "\n${YELLOW}⚠️  СИСТЕМА ТРЕБУЕТ ВНИМАНИЯ${NC}"
    else
        echo -e "\n${RED}🚨 СИСТЕМА ТРЕБУЕТ НЕМЕДЛЕННОГО ВМЕШАТЕЛЬСТВА${NC}"
    fi
    
    echo -e "\nПодробный отчет сохранен в: ${CYAN}$REPORT_FILE${NC}"
    echo -e "Лог выполнения: ${CYAN}$LOG_FILE${NC}"
}

run_performance_test() {
    print_section "Тест производительности"
    
    # Тест скорости чтения диска
    local read_speed=$(dd if=/dev/zero of=/tmp/test_write bs=1M count=10 2>&1 | grep -o '[0-9.]\+ MB/s' | head -1)
    rm -f /tmp/test_write
    if [[ -n "$read_speed" ]]; then
        check_result "Скорость записи диска" "PASS" "$read_speed"
    else
        check_result "Скорость записи диска" "WARN" "Не удалось измерить"
    fi
    
    # Тест памяти
    local mem_test=$(timeout 5 stress-ng --vm 1 --vm-bytes 100M -t 3s 2>/dev/null && echo "OK" || echo "FAIL")
    if [[ "$mem_test" == "OK" ]]; then
        check_result "Тест памяти" "PASS" "Стресс-тест пройден"
    else
        check_result "Тест памяти" "WARN" "Утилита stress-ng недоступна"
    fi
}

# Основная функция
main() {
    clear
    print_header "$SCRIPT_NAME v$VERSION"
    echo -e "Время запуска: ${CYAN}$(date)${NC}"
    echo -e "Хост: ${CYAN}$(hostname)${NC}"
    echo -e "Пользователь: ${CYAN}$(whoami)${NC}"
    
    log "Начало проверки системы"
    
    # Создаем заголовок отчета
    {
        echo "HA System Health Check Report"
        echo "Время: $(date)"
        echo "Хост: $(hostname)"
        echo "=================================="
        echo ""
    } > "$REPORT_FILE"
    
    # Выполняем все проверки
    check_basic_system_info
    check_system_resources
    check_network_connectivity
    check_docker_services
    check_tailscale_vpn
    check_ha_monitoring_services
    check_log_files
    check_ha_services_availability
    check_recent_failures
    check_system_security
    
    # Дополнительные тесты (если доступны инструменты)
    if command -v stress-ng >/dev/null 2>&1 || command -v dd >/dev/null 2>&1; then
        run_performance_test
    fi
    
    # Генерируем сводку
    generate_summary
    
    log "Проверка системы завершена. Отчет: $REPORT_FILE"
}

# Проверка зависимостей
check_dependencies() {
    local missing_tools=()
    
    # Проверяем наличие необходимых утилит
    local required_tools=("bc" "docker" "systemctl")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    # Предупреждение о необязательных утилитах
    if ! command -v jq >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️  Внимание: утилита 'jq' не найдена. Проверка Tailscale будет ограничена.${NC}"
    fi
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        echo -e "${RED}Предупреждение: Следующие утилиты не найдены:${NC}"
        printf '  %s\n' "${missing_tools[@]}"
        echo -e "${YELLOW}Некоторые проверки могут быть пропущены${NC}"
        echo ""
    fi
}

# Вывод справки
show_help() {
    echo "HA System Health Check v$VERSION"
    echo ""
    echo "Использование: $0 [ОПЦИИ]"
    echo ""
    echo "Опции:"
    echo "  -h, --help     Показать эту справку"
    echo "  -q, --quiet    Тихий режим (только ошибки)"
    echo "  -v, --verbose  Подробный вывод"
    echo "  --quick        Быстрая проверка (основные компоненты)"
    echo "  --full         Полная проверка (по умолчанию)"
    echo ""
    echo "Примеры:"
    echo "  $0              # Полная проверка"
    echo "  $0 --quick      # Быстрая проверка"
    echo "  $0 --quiet      # Тихий режим"
}

# Обработка аргументов командной строки
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    -q|--quiet)
        exec > /dev/null
        ;;
    --quick)
        # Для быстрой проверки ограничиваем список функций
        QUICK_MODE=true
        ;;
    -v|--verbose)
        set -x
        ;;
esac

# Запуск
check_dependencies
main

exit 0
