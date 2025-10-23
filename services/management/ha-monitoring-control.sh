#!/bin/bash

# HomeAssistant Monitoring Control Script
# Management of all HomeAssistant monitoring services

set -e

LOG_FILE="/var/log/ha-monitoring-control.log"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

SERVICES=(
    "ha-watchdog.timer"
    "ha-failure-notifier.timer"
    "update-checker.timer"
    "system-diagnostic-startup.timer"
    "nightly-reboot.timer"
    "ha-backup.timer"
    "boot-notifier.timer"
)

check_service_status() {
    if systemctl is-active --quiet "$1"; then
        echo "✓ $1 - active"
        return 0
    else
        echo "✗ $1 - inactive"
        return 1
    fi
}

start_services() {
    echo "=== Starting monitoring services ==="
    for service in "${SERVICES[@]}"; do
        echo "Starting $service..."
        systemctl start "$service"
        systemctl enable "$service"
        check_service_status "$service"
    done
    echo "=== All services started ==="
}

stop_services() {
    echo "=== Stopping monitoring services ==="
    for service in "${SERVICES[@]}"; do
        echo "Stopping $service..."
        systemctl stop "$service"
        check_service_status "$service"
    done
    echo "=== All services stopped ==="
}

restart_services() {
    echo "=== Restarting monitoring services ==="
    stop_services
    sleep 2
    start_services
}

show_status() {
    echo "=== Monitoring services status ==="
    local all_ok=true
    for service in "${SERVICES[@]}"; do
        if ! check_service_status "$service"; then
            all_ok=false
        fi
    done
    
    echo
    if $all_ok; then
        echo "All services are working correctly"
    else
        echo "Some services are inactive"
    fi
}

show_logs() {
    echo "=== Monitoring Service Logs ==="
    echo ""
    echo "--- ha-watchdog ---"
    tail -20 /var/log/ha-watchdog.log 2>/dev/null || echo "No logs"
    echo ""
    echo "--- ha-failure-notifier ---"
    tail -20 /var/log/ha-failure-notifier.log 2>/dev/null || echo "No logs"
    echo ""
    echo "--- update-checker ---"
    tail -20 /var/log/ha-update-checker.log 2>/dev/null || echo "No logs"
    echo ""
    echo "--- system-diagnostic-startup ---"
    tail -20 /var/log/system-diagnostic-startup.log 2>/dev/null || echo "No logs"
    echo ""
    echo "--- nightly-reboot ---"
    tail -20 /var/log/ha-reboot.log 2>/dev/null || echo "No logs"
    echo ""
    echo "--- ha-backup ---"
    tail -20 /var/log/ha-backup.log 2>/dev/null || echo "No logs"
    echo ""
    echo "--- boot-notifier ---"
    tail -20 /var/log/boot-notifier.log 2>/dev/null || echo "No logs"
}

test_telegram() {
    echo "=== Testing Telegram notifications ==="
    if [ -f "/usr/local/bin/telegram-sender.sh" ]; then
        /usr/local/bin/telegram-sender.sh "🧪 HomeAssistant monitoring test: $(date)" "0"
        echo "Test message sent"
    else
        echo "telegram-sender script not found"
    fi
}

run_diagnostic() {
    echo "=== Running system diagnostics ==="
    if [ -f "/usr/local/bin/system-diagnostic.sh" ]; then
        /usr/local/bin/system-diagnostic.sh
    else
        echo "system-diagnostic script not found"
    fi
}

show_help() {
    echo "Usage: ha-monitoring-control {start|stop|restart|status|logs|test-telegram|diagnostic}"
    echo
    echo "Commands:"
    echo "  start         - Start all monitoring services"
    echo "  stop          - Stop all monitoring services"
    echo "  restart       - Restart all monitoring services"
    echo "  status        - Show status of all services"
    echo "  logs          - Show recent logs"
    echo "  test-telegram - Send test Telegram message"
    echo "  diagnostic    - Run full system diagnostics"
}

log_message "ha-monitoring-control started with parameter: $1"

case "$1" in
    start)
        start_services
        ;;
    stop)
        stop_services
        ;;
    restart)
        restart_services
        ;;
    status)
        show_status
        ;;
    logs)
        show_logs
        ;;
    test-telegram)
        test_telegram
        ;;
    diagnostic)
        run_diagnostic
        ;;
    *)
        show_help
        exit 1
        ;;
esac
