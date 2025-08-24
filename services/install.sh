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

# Проверяем установку Docker
echo "🐳 Проверка Docker..."
if ! command -v docker >/dev/null 2>&1; then
    echo "📦 Установка Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    usermod -aG docker $SUDO_USER 2>/dev/null || true
    echo "✅ Docker установлен"
else
    echo "✅ Docker уже установлен"
fi

# Проверяем установку Docker Compose
if ! command -v docker-compose >/dev/null 2>&1; then
    echo "📦 Установка Docker Compose..."
    apt update
    apt install -y docker-compose
    echo "✅ Docker Compose установлен"
else
    echo "✅ Docker Compose уже установлен"
fi

# Настройка ограничений Docker логирования
echo "📝 Настройка ограничений Docker логирования..."
DAEMON_JSON="/etc/docker/daemon.json"

# Создаем резервную копию
if [[ -f "$DAEMON_JSON" ]]; then
    cp "$DAEMON_JSON" "$DAEMON_JSON.backup.$(date +%Y%m%d_%H%M%S)"
    echo "💾 Резервная копия создана"
fi

# Создаем новую конфигурацию
cat > "$DAEMON_JSON" << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "7"
  }
}
EOF

echo "✅ Конфигурация Docker логирования установлена"
echo "   └─ Лимит: 10MB × 7 файлов = 70MB на контейнер"

# Создание Home Assistant директории и docker-compose
echo "🏠 Настройка Home Assistant..."
HA_DIR="/opt/homeassistant"
mkdir -p "$HA_DIR"

# Копируем docker-compose.yml если он есть в проекте
if [[ -f "docker-compose.yml" ]]; then
    cp docker-compose.yml "$HA_DIR/"
    echo "✅ docker-compose.yml скопирован в $HA_DIR"
else
    # Создаем базовый docker-compose.yml
    cat > "$HA_DIR/docker-compose.yml" << 'EOF'
services:
  homeassistant:
    container_name: homeassistant
    image: ghcr.io/home-assistant/home-assistant:stable
    volumes:
      - ./homeassistant:/config
      - /etc/localtime:/etc/localtime:ro
    restart: unless-stopped
    privileged: true
    network_mode: host
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "7"

  nodered:
    container_name: nodered
    image: nodered/node-red:latest
    ports:
      - "1880:1880"
    volumes:
      - ./nodered:/data
    restart: unless-stopped
    environment:
      - TZ=Europe/Moscow
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "7"
EOF
    echo "✅ Базовый docker-compose.yml создан"
fi

# Создаем необходимые директории
echo "📁 Создание директорий..."
mkdir -p /etc/ha-watchdog
mkdir -p /var/lib/ha-responder
mkdir -p /usr/local/bin
mkdir -p "$HA_DIR/homeassistant"
mkdir -p "$HA_DIR/nodered"

# Устанавливаем зависимости
echo "📦 Установка зависимостей..."
apt update
apt install -y bc curl jq wireless-tools dos2unix htop

# Копируем скрипты
echo "📋 Установка скриптов..."
cp monitoring/ha-watchdog/ha-watchdog.sh /usr/local/bin/ha-watchdog.sh
cp monitoring/ha-failure-notifier/ha-failure-notifier.sh /usr/local/bin/ha-failure-notifier.sh
cp system/nightly-reboot/nightly-reboot.sh /usr/local/bin/nightly-reboot.sh
cp system/update-checker/update-checker.sh /usr/local/bin/update-checker.sh
chmod +x /usr/local/bin/ha-watchdog.sh
chmod +x /usr/local/bin/ha-failure-notifier.sh
chmod +x /usr/local/bin/nightly-reboot.sh
chmod +x /usr/local/bin/update-checker.sh

# Копируем конфигурацию
if [[ ! -f /etc/ha-watchdog/config ]]; then
    cp monitoring/ha-watchdog/ha-watchdog.conf /etc/ha-watchdog/config
    echo "⚙️ Конфигурация скопирована в /etc/ha-watchdog/config"
    echo "📝 Не забудьте настроить Telegram токены!"
fi

# Перезапуск Docker для применения настроек логирования
echo "🔄 Перезапуск Docker для применения настроек..."
systemctl restart docker
sleep 5

# Запуск Home Assistant контейнеров
echo "🏠 Запуск Home Assistant контейнеров..."
cd "$HA_DIR"
docker-compose up -d
echo "✅ Home Assistant контейнеры запущены"

# Создаем systemd сервисы
echo "🔧 Создание systemd сервисов..."

# Копируем systemd файлы мониторинга
cp monitoring/ha-watchdog/ha-watchdog.service /etc/systemd/system/
cp monitoring/ha-watchdog/ha-watchdog.timer /etc/systemd/system/
cp monitoring/ha-failure-notifier/ha-failure-notifier.service /etc/systemd/system/
cp monitoring/ha-failure-notifier/ha-failure-notifier.timer /etc/systemd/system/

# Копируем systemd файлы системных сервисов
cp system/nightly-reboot/nightly-reboot.service /etc/systemd/system/
cp system/nightly-reboot/nightly-reboot.timer /etc/systemd/system/
cp system/update-checker/update-checker.service /etc/systemd/system/
cp system/update-checker/update-checker.timer /etc/systemd/system/

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
    # Создаем systemd файлы для update-checker (если они не скопированы из папки)
    if [[ ! -f /etc/systemd/system/update-checker.service ]]; then
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
    fi

    if [[ ! -f /etc/systemd/system/update-checker.timer ]]; then
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
    fi

    systemctl daemon-reload
    systemctl enable update-checker.timer
    echo "✅ Update checker установлен"
fi

# Устанавливаем Tailscale если нужен
read -p "Установить и настроить Tailscale VPN? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🔧 Установка Tailscale..."
    
    # Установка Tailscale
    if ! command -v tailscale >/dev/null 2>&1; then
        curl -fsSL https://tailscale.com/install.sh | sh
    fi
    
    # Остановка сервисов
    systemctl stop tailscaled tailscale-serve-ha tailscale-funnel-ha 2>/dev/null || true
    
    # Копирование конфигурации и сервисов
    cp tailscale/tailscaled/tailscaled.service /etc/systemd/system/
    cp tailscale/tailscale-serve-ha/tailscale-serve-ha.service /etc/systemd/system/
    cp tailscale/tailscale-funnel-ha/tailscale-funnel-ha.service /etc/systemd/system/
    
    if [[ -f tailscale/tailscaled/tailscaled.default ]]; then
        cp tailscale/tailscaled/tailscaled.default /etc/default/tailscaled
    fi
    
    # Активация сервисов
    systemctl daemon-reload
    systemctl enable --now tailscaled tailscale-serve-ha tailscale-funnel-ha
    
    echo "✅ Tailscale установлен"
    echo "🔑 Для авторизации выполните: tailscale up --hostname=rpi3-$(date +%Y%m%d)"
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
        [[ -f /etc/systemd/system/tailscaled.service ]] && systemctl start tailscaled
        [[ -f /etc/systemd/system/tailscale-serve-ha.service ]] && systemctl start tailscale-serve-ha
        [[ -f /etc/systemd/system/tailscale-funnel-ha.service ]] && systemctl start tailscale-funnel-ha
        echo "✅ Все сервисы запущены"
        ;;
    stop)
        systemctl stop ha-watchdog.timer
        systemctl stop ha-failure-notifier.timer
        systemctl stop nightly-reboot.timer
        [[ -f /etc/systemd/system/update-checker.timer ]] && systemctl stop update-checker.timer
        [[ -f /etc/systemd/system/tailscaled.service ]] && systemctl stop tailscaled
        [[ -f /etc/systemd/system/tailscale-serve-ha.service ]] && systemctl stop tailscale-serve-ha
        [[ -f /etc/systemd/system/tailscale-funnel-ha.service ]] && systemctl stop tailscale-funnel-ha
        echo "⏹️ Все сервисы остановлены"
        ;;
    restart)
        systemctl restart ha-watchdog.timer
        systemctl restart ha-failure-notifier.timer
        systemctl restart nightly-reboot.timer
        [[ -f /etc/systemd/system/update-checker.timer ]] && systemctl restart update-checker.timer
        [[ -f /etc/systemd/system/tailscaled.service ]] && systemctl restart tailscaled
        [[ -f /etc/systemd/system/tailscale-serve-ha.service ]] && systemctl restart tailscale-serve-ha
        [[ -f /etc/systemd/system/tailscale-funnel-ha.service ]] && systemctl restart tailscale-funnel-ha
        echo "🔄 Все сервисы перезапущены"
        ;;
    status)
        echo "📊 Статус сервисов:"
        echo "--- Мониторинг ---"
        systemctl status ha-watchdog.timer --no-pager -l
        systemctl status ha-failure-notifier.timer --no-pager -l
        echo "--- Система ---"
        systemctl status nightly-reboot.timer --no-pager -l
        [[ -f /etc/systemd/system/update-checker.timer ]] && systemctl status update-checker.timer --no-pager -l
        echo "--- Tailscale ---"
        [[ -f /etc/systemd/system/tailscaled.service ]] && systemctl status tailscaled --no-pager -l
        [[ -f /etc/systemd/system/tailscale-serve-ha.service ]] && systemctl status tailscale-serve-ha --no-pager -l
        [[ -f /etc/systemd/system/tailscale-funnel-ha.service ]] && systemctl status tailscale-funnel-ha --no-pager -l
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
    tailscale-status)
        if command -v tailscale >/dev/null 2>&1; then
            echo "🔗 Статус Tailscale:"
            tailscale status
        else
            echo "❌ Tailscale не установлен"
        fi
        ;;
    diagnostic)
        if [[ -f /usr/local/bin/system-diagnostic.sh ]]; then
            /usr/local/bin/system-diagnostic.sh
        else
            echo "❌ Скрипт диагностики не найден"
        fi
        ;;
    *)
        echo "Использование: $0 {start|stop|restart|status|logs|test-telegram|tailscale-status|diagnostic}"
        exit 1
        ;;
esac
EOF

chmod +x /usr/local/bin/ha-monitoring-control

# Устанавливаем скрипт диагностики
echo "🔍 Установка скрипта диагностики..."
cp system-diagnostic.sh /usr/local/bin/system-diagnostic.sh
chmod +x /usr/local/bin/system-diagnostic.sh

echo ""
echo "✅ Установка завершена!"
echo ""
echo "� Docker состояние:"
echo "   ├─ Docker Engine: Настроен с ограничениями логов (10MB×7)"
echo "   ├─ Home Assistant: Запущен на порту 8123"
echo "   └─ Node-RED: Запущен на порту 1880"
echo ""
echo "�📝 Следующие шаги:"
echo "1. Отредактируйте /etc/ha-watchdog/config"
echo "2. Добавьте токены Telegram бота"
echo "3. Запустите мониторинг: ha-monitoring-control start"
echo "4. Проверьте статус: ha-monitoring-control status"
echo "5. Протестируйте Telegram: ha-monitoring-control test-telegram"
echo ""
echo "🔧 Команды управления:"
echo "   ha-monitoring-control {start|stop|restart|status|logs|test-telegram|tailscale-status|diagnostic}"
echo ""
echo "🐳 Docker команды:"
echo "   cd /opt/homeassistant && docker-compose ps     - статус контейнеров"
echo "   cd /opt/homeassistant && docker-compose logs   - логи контейнеров"
echo "   cd /opt/homeassistant && docker-compose restart - перезапуск контейнеров"
echo ""
echo "🔍 Диагностика системы:"
echo "   system-diagnostic.sh    - полная диагностика системы"
echo ""
echo "📍 Файлы логов:"
echo "   /var/log/ha-watchdog.log    - лог проверок"
echo "   /var/log/ha-responder.log   - лог действий"
echo "   /var/log/ha-failures.log    - лог сбоев"
echo ""
