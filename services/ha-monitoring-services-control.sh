#!/bin/bash

# Скрипт управления HA сервисами
LOG_FILE="/var/log/ha-services-control.log"

log() {
    echo "$(date '+%F %T') [CONTROL] $1" | tee -a "$LOG_FILE"
}

# Устанавливаем права на выполнение
set_permissions() {
    log "Установка прав на выполнение..."
    chmod +x /opt/ha-monitoring/scripts/*.sh
    chmod +x /usr/local/bin/ha-*.sh
    log "Права установлены"
}

# Перезапуск всех HA сервисов
restart_services() {
    log "Перезапуск всех HA сервисов..."
    
    systemctl daemon-reload
    
    # Основные сервисы мониторинга
    systemctl restart ha-watchdog.service
    systemctl restart ha-failure-notifier.service
    
    # Docker контейнеры
    cd /srv/home && docker-compose restart
    
    log "Сервисы перезапущены"
}

# Проверка статуса сервисов
check_status() {
    log "Проверка статуса сервисов..."
    
    echo "=== Systemd сервисы ==="
    systemctl status ha-watchdog.service --no-pager -l
    systemctl status ha-failure-notifier.service --no-pager -l
    
    echo "=== Docker контейнеры ==="
    docker ps
    
    echo "=== Использование памяти ==="
    free -h
}

case "$1" in
    "permissions"|"perms")
        set_permissions
        ;;
    "restart")
        set_permissions
        restart_services
        ;;
    "status")
        check_status
        ;;
    "full")
        set_permissions
        restart_services
        check_status
        ;;
    *)
        echo "Использование: $0 {permissions|restart|status|full}"
        echo "  permissions - установить права на выполнение"
        echo "  restart     - перезапустить все сервисы"
        echo "  status      - проверить статус сервисов"
        echo "  full        - выполнить все действия"
        exit 1
        ;;
esac
