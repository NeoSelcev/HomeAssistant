#!/bin/bash

# Скрипт установки улучшенной системы мониторинга HA
# Для Raspberry Pi 3B+ с Debian

set -e

echo "🚀 Установка улучшенной системы мониторинга Home Assistant..."

# Проверяем права root
if [[ $EUID -ne 0 ]]; then
   echo "❌ Этот скрипт должен запускаться с правами root"
   exit 1
fi

# Создаем необходимые директории
echo "📁 Создание директорий..."
mkdir -p /etc/ha-watchdog
mkdir -p /var/lib/ha-responder
mkdir -p /usr/local/bin

# Устанавливаем зависимости
echo "📦 Установка зависимостей..."
apt update
apt install -y bc curl jq

# Копируем скрипты
echo "📋 Установка скриптов..."
cp scripts/ha-watchdog.sh /usr/local/bin/ha-watchdog.sh
cp scripts/ha-failure-notifier.sh /usr/local/bin/ha-failure-notifier.sh
cp scripts/nightly-reboot.sh /usr/local/bin/nightly-reboot.sh
cp scripts/update-checker.sh /usr/local/bin/update-checker.sh
chmod +x /usr/local/bin/ha-watchdog.sh
chmod +x /usr/local/bin/ha-failure-notifier.sh
chmod +x /usr/local/bin/nightly-reboot.sh
chmod +x /usr/local/bin/update-checker.sh

# Копируем конфигурацию
if [[ ! -f /etc/ha-watchdog/config ]]; then
    cp config/ha-watchdog.conf /etc/ha-watchdog/config
    echo "⚙️ Конфигурация скопирована в /etc/ha-watchdog/config"
    echo "📝 Не забудьте настроить Telegram токены!"
fi

# Создаем systemd сервисы
echo "🔧 Создание systemd сервисов..."

# Копируем systemd файлы
cp systemd/ha-watchdog.service /etc/systemd/system/
cp systemd/ha-watchdog.timer /etc/systemd/system/
cp systemd/ha-failure-notifier.service /etc/systemd/system/
cp systemd/ha-failure-notifier.timer /etc/systemd/system/
cp systemd/nightly-reboot.service /etc/systemd/system/
cp systemd/nightly-reboot.timer /etc/systemd/system/

# Создаем скрипт для логротации
cat > /etc/logrotate.d/ha-monitoring << 'EOF'
/var/log/ha-*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
    maxsize 10M
}
EOF

# Перезагружаем systemd и включаем сервисы
echo "🔄 Настройка systemd..."
systemctl daemon-reload
systemctl enable ha-watchdog.timer
systemctl enable ha-failure-notifier.timer
systemctl enable nightly-reboot.timer

# Устанавливаем update-checker если нужен
read -p "Установить ежедневную проверку обновлений? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Создаем systemd файлы для update-checker
    cat > /etc/systemd/system/update-checker.service << 'EOF'
[Unit]
Description=System Update Checker
Documentation=man:systemd.service(5)
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/update-checker.sh
User=root
StandardOutput=journal
StandardError=journal
ConditionLoadAverage=<3.0

[Install]
WantedBy=multi-user.target
EOF

    cat > /etc/systemd/system/update-checker.timer << 'EOF'
[Unit]
Description=Schedule system update check during work hours on weekdays
Documentation=man:systemd.timer(5)
Requires=update-checker.service

[Timer]
OnCalendar=Mon,Tue,Wed,Thu,Fri *-*-* 09:00:00
Persistent=true
AccuracySec=1min
RandomizedDelaySec=30min

[Install]
WantedBy=timers.target
EOF

    systemctl enable update-checker.timer
    echo "✅ Update checker установлен"
fi

# Создаем скрипт для управления
cat > /usr/local/bin/ha-monitoring-control << 'EOF'
#!/bin/bash

case "$1" in
    start)
        systemctl start ha-watchdog.timer
        systemctl start ha-failure-notifier.timer
        systemctl start nightly-reboot.timer
        [[ -f /etc/systemd/system/update-checker.timer ]] && systemctl start update-checker.timer
        echo "✅ Мониторинг запущен"
        ;;
    stop)
        systemctl stop ha-watchdog.timer
        systemctl stop ha-failure-notifier.timer
        systemctl stop nightly-reboot.timer
        [[ -f /etc/systemd/system/update-checker.timer ]] && systemctl stop update-checker.timer
        echo "⏹️ Мониторинг остановлен"
        ;;
    restart)
        systemctl restart ha-watchdog.timer
        systemctl restart ha-failure-notifier.timer
        systemctl restart nightly-reboot.timer
        [[ -f /etc/systemd/system/update-checker.timer ]] && systemctl restart update-checker.timer
        echo "🔄 Мониторинг перезапущен"
        ;;
    status)
        echo "📊 Статус мониторинга:"
        systemctl status ha-watchdog.timer --no-pager -l
        systemctl status ha-failure-notifier.timer --no-pager -l
        systemctl status nightly-reboot.timer --no-pager -l
        [[ -f /etc/systemd/system/update-checker.timer ]] && systemctl status update-checker.timer --no-pager -l
        ;;
    logs)
        echo "📋 Логи watchdog:"
        tail -20 /var/log/ha-watchdog.log 2>/dev/null || echo "Лог файл не найден"
        echo ""
        echo "📋 Логи failure notifier:"
        tail -20 /var/log/ha-failure-notifier.log 2>/dev/null || echo "Лог файл не найден"
        echo ""
        echo "📋 Логи сбоев:"
        tail -20 /var/log/ha-failures.log 2>/dev/null || echo "Лог файл не найден"
        echo ""
        echo "📋 Логи reboot:"
        tail -10 /var/log/ha-reboot.log 2>/dev/null || echo "Лог файл не найден"
        ;;
    test-telegram)
        source /etc/ha-watchdog/config
        if [[ -n "$TELEGRAM_BOT_TOKEN" ]] && [[ -n "$TELEGRAM_CHAT_ID" ]]; then
            curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
                -d "chat_id=$TELEGRAM_CHAT_ID" \
                -d "text=🧪 Тест уведомлений от [$(hostname)] - Все системы работают!" && \
            echo "✅ Тестовое сообщение отправлено" || \
            echo "❌ Ошибка отправки сообщения"
        else
            echo "❌ Telegram не настроен в /etc/ha-watchdog/config"
        fi
        ;;
    *)
        echo "Использование: $0 {start|stop|restart|status|logs|test-telegram}"
        exit 1
        ;;
esac
EOF

chmod +x /usr/local/bin/ha-monitoring-control

echo ""
echo "✅ Установка завершена!"
echo ""
echo "📝 Следующие шаги:"
echo "1. Отредактируйте /etc/ha-watchdog/config"
echo "2. Добавьте токены Telegram бота"
echo "3. Запустите мониторинг: ha-monitoring-control start"
echo "4. Проверьте статус: ha-monitoring-control status"
echo "5. Протестируйте Telegram: ha-monitoring-control test-telegram"
echo ""
echo "🔧 Команды управления:"
echo "   ha-monitoring-control {start|stop|restart|status|logs|test-telegram}"
echo ""
echo "📍 Файлы логов:"
echo "   /var/log/ha-watchdog.log    - лог проверок"
echo "   /var/log/ha-responder.log   - лог действий"
echo "   /var/log/ha-failures.log    - лог сбоев"
echo ""
