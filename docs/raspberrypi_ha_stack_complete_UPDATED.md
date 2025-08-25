# 🏠 Smart Home Network Architecture

## Hardware & OS Configuration

### Raspberry Pi 3B+ Setup
- **OS**: Debian 12 (Bookworm), ARM64 architecture
- **Hostname**: rpi3-20250711  
- **SSH Access**: Port 22, key-based authentication
- **Installation**: Manual setup with full root access
- **Memory**: 1GB RAM + 2GB Swap file (/swapfile)
- **Storage**: MicroSD card with regular health monitoring

### Network Configuration
- **Local Network**: 192.168.1.0/24
- **PI Address**: 192.168.1.21
- **Router**: 192.168.1.1
- **DNS**: 8.8.8.8, 1.1.1.1

## Docker Infrastructure

### Core Services Stack
```yaml
services:
  homeassistant:
    image: ghcr.io/home-assistant/home-assistant:stable
    network_mode: host
    ports: 8123
    volumes: ./homeassistant:/config
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "7"
    
  nodered:
    image: nodered/node-red:latest
    ports: 1880
    volumes: ./nodered:/data
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "7"
```

### Docker Logging Configuration
**Global Settings** (`/etc/docker/daemon.json`):
```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "7"
  }
}
```

**Log Management Strategy:**
- **Per Container Limit**: 70MB maximum (10MB × 7 files)
- **Total Docker Logs**: ~140MB maximum (HA + NodeRED)  
- **Automatic Rotation**: When log file reaches 10MB
- **Archive Policy**: Keep 7 historical log files
- **Benefits**: Prevents disk space exhaustion, maintains debugging capability

### Tailscale VPN (Native Installation)
- **Service**: Native systemd services (not containerized)
- **Device**: rpi3-20250711
- **IP**: 100.103.54.125  
- **Public HTTPS**: https://rpi3-20250711.tail586076.ts.net/
- **Services**: tailscaled, tailscale-serve-ha, tailscale-funnel-ha

## Monitoring & Management Services

### Health Monitoring Stack (Systemd Timers)
```bash
# Active monitoring services with scheduled execution
ha-watchdog.timer         # Every 2 minutes - 20-point system health
ha-failure-notifier.timer # Every 5 minutes - Telegram alerts & recovery  
nightly-reboot.timer      # Daily 03:30 - Maintenance reboot with health report
update-checker.timer      # Weekdays 09:00 ±30min - Update analysis
```

**⚠️ Important Timer Configuration:**
- `nightly-reboot.timer` **does NOT** use `Persistent=true` to prevent reboot loops
- `WakeSystem=false` prevents timer from waking sleeping system
- **Triple Protection System:**
  1. **Timer Level**: No persistent catch-up runs after system downtime
  2. **Time Validation**: Script only runs between 03:25-03:35 (±5 min window)
  3. **Boot Loop Protection**: Minimum 10 minutes system uptime required
- If system misses 03:30 reboot (maintenance/downtime), it will skip until next day
- All protection violations send Telegram notifications for monitoring

### Service Logging Configuration
```
/var/log/ha-watchdog.log         # System health checks (every 2min)
/var/log/ha-failure-notifier.log # Alert processing & recovery actions
/var/log/ha-failures.log        # Failure events log (processed by notifier)
/var/log/ha-reboot.log   # Nightly maintenance reports
/var/log/ha-update-checker.log   # System update analysis
/var/log/ha-services-control.log # Service management operations
/var/log/ha-debug.log           # Debug information
```

### Telegram Integration
**Notification Categories:**
- 🔴 Critical: System failures, high temperature (>70°C)
- 🟠 Important: Container failures, network issues  
- 🟡 Warning: High system load, slow network
- 🟢 Info: Service recovery, successful restarts
- 🌙 Nightly: Daily system health reports with update status

**Features:**
- Smart throttling prevents notification spam
- Rich HTML formatting with system metrics
- Automatic update checking and reporting
- Pre-reboot health summaries

## Network Topology

### WiFi Infrastructure
- **Main Router**: 192.168.1.1 (Gateway)
- **DHCP Range**: 192.168.1.100-200
- **Smart Devices**: IoT VLAN isolated
- **VPN Access**: Tailscale overlay network

### Port Mapping
- **8123**: Home Assistant Web UI
- **1880**: Node-RED Flow Editor  
- **22**: SSH Management Port
- **443/80**: HTTPS/HTTP (if exposed)

## Security Configuration

### SSH Hardening
- Key-based authentication only
- Custom port (22)
- Root login via keys
- Fail2ban protection

### Container Security  
- Host network mode for HA discovery
- Volume mounts with restricted permissions
- Regular image updates via watchtower

### Network Security
- Firewall rules (ufw)
- VPN-only external access
- Regular security updates

---
*Updated: 2025-08-21 - Smart Home Network Documentation*

## Monitoring System

### System Health Monitoring
- **Scripts Location**: `/opt/ha-monitoring/scripts/`
- **Config**: `/etc/ha-watchdog/config`
- **Logs**: `/var/log/ha-*.log`

#### ha-watchdog.sh
- **Purpose**: Comprehensive system health checks
- **Service**: `ha-watchdog.service` (timer-based)
- **Interval**: Every 2 minutes
- **Checks**: 20 different system components
  - Memory usage (threshold: 80MB free)
  - Docker containers (homeassistant, nodered)  
  - Tailscale services (tailscaled, funnel, serve)
  - Network connectivity and WiFi signal
  - CPU temperature and load
  - Disk space and SD card health
  - SSH access and systemd services

#### ha-failure-notifier.sh  
- **Purpose**: Process failures and send Telegram notifications
- **Service**: `ha-failure-notifier.service` (timer-based)
- **Interval**: Every 1 minute
- **Features**: Smart throttling, automatic container restart
- **Notifications**: Critical/Warning/Info with emojis

#### System Management
- **Control Script**: `/usr/local/bin/ha-monitoring-services-control.sh`
- **Usage**: `ha-monitoring-services-control.sh {permissions|restart|status|full}`
- **Functions**: Set permissions, restart services, check status

### Memory Management
- **Swap File**: `/swapfile` (2GB)
- **Configuration**: Auto-enabled at boot via `/etc/fstab`
- **Monitoring**: Included in watchdog checks
    image: nodered/node-red
    network_mode: host
    volumes:
      - ./node-red:/data
    restart: unless-stopped

  tailscale:
    image: tailscale/tailscale
    network_mode: host
    volumes:
      - ./tailscale:/var/lib/tailscale
    cap_add:
      - NET_ADMIN
      - NET_RAW
    environment:
      - TS_AUTHKEY=tskey-...
    command: tailscaled
    restart: unless-stopped
```

## 3. systemd службы

## 3. Tailscale Native Configuration

### Installation & Restore
```bash
# Restore from backup
cd /path/to/project/tailscale_native/
sudo ./restore-tailscale.sh
```

### systemd Services

#### tailscale-serve-ha.service
```ini
# Цель: HTTPS прокси для HA через порт 8443
[Unit]
Description=Tailscale Serve HTTPS for Home Assistant (port 8443)
After=network.target docker.service tailscaled.service
Requires=tailscaled.service

[Service]
Type=simple
ExecStartPre=/bin/sleep 30
ExecStart=/usr/bin/tailscale serve --bg --https=8443 http://localhost:8123
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

#### tailscale-funnel-ha.service
```ini
# Цель: Публичный HTTPS доступ из интернета
[Unit]
Description=Tailscale Funnel for Home Assistant (public HTTPS)
After=network.target docker.service tailscaled.service
Requires=tailscaled.service

[Service]
ExecStart=/usr/bin/tailscale funnel 8443
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

## 4. Конфигурация Home Assistant

### configuration.yaml (основа)

```yaml
default_config:

http:
  use_x_forwarded_for: true
  server_host: 0.0.0.0
  trusted_proxies:
    - 127.0.0.1
    - 100.64.0.0/10

frontend:
  themes: !include_dir_merge_named themes

automation: !include automations.yaml
script: !include scripts.yaml
scene: !include scenes.yaml
```

### Расширения конфигурации:

- Telegram настроен через Node-RED с API токеном
- В будущем можно подключить `telegram:` напрямую через UI-интеграции
- Для TTS используется Google Translate:

```yaml
tts:
  - platform: google_translate
    service_name: google_say
```

## 5. Интеграции и устройства

- ✅ HACS (установлен вручную)
- ✅ Sonoff (eWeLink) — 48 устройств через LAN/Cloud
- ✅ Broadlink — работает (IR/RF передатчик)
- ✅ Roomba — auto discovered
- ✅ Weather, Sun, TTS, Backup
- ⏳ HomeBridge — планируется подключение для интеграции с Siri

## 6. Node-RED

- Подключение к HA через WebSocket с токеном
- Установленные паллеты:
 - `node-red`
 - `node-red-contrib-home-assistant-websocket`
 - `node-red-contrib-influxdb`
 - `node-red-contrib-moment`
 - `node-red-contrib-time-range-switch`
 - `node-red-dashboard`
 - `node-red-node-email`
 - `node-red-node-telegrambot`
 - `node-red-node-ui-table`

### Пример потока:

```json
[
  {
    "id": "sensor1",
    "type": "server-state-changed",
    "name": "Sonoff Light",
    "entityidfilter": "switch.sonoff_1000cbf589",
    "outputinitially": false,
    "x": 150,
    "y": 100,
    "wires": [["telegram"]]
  },
  {
    "id": "telegram",
    "type": "telegram sender",
    "name": "Notify",
    "bot": "mybot",
    "chatId": "538317310",
    "x": 350,
    "y": 100,
    "wires": []
  }
]
```

## 7. Сеть и доступ

- Основная сеть: `192.168.1.0/24`
- IoT подсети: `192.168.2.x`, `192.168.3.x`, `192.168.4.x`
- Доступ к ним:
  - Проброс портов на роутерах
  - Node-RED как прокси
  - План: static routes

## 8. Отладка и мониторинг

- Проверка Tailscale IP:
  ```bash
  tailscale ip -4
  ```
- Статус HA:
  ```bash
  docker logs -f homeassistant
  ```
- Проверка доступности HA:
  ```bash
  curl -v http://localhost:8123
  ```

## 9. Известные проблемы

- ⚠️ YAML-конфигурация Telegram устарела
- ⚠️ SSL-ошибка при доступе через Funnel без сертификата
- ⚠️ HA Mobile может терять соединение через VPN

## 10. Рекомендации и ToDo

- 🔐 Включить авторизацию и роли в HA
- 🧩 Настроить HomeBridge и интеграцию с Siri
- 📡 Расширить Telegram-уведомления (движение, температура, события)
- 🌍 Использовать Tailscale DNS или домен через CNAME
- 🧪 Добавить интеграции: Zigbee2MQTT (через USB), ESPHome, MQTT-брокер
- 🔄 Настроить snapshot-резервирование
- 📲 Автоматизировать backup на внешний диск или Google Drive
- 🧠 Создать структуру автоматизаций в Node-RED: уведомления, ночной режим, отпугивание и т.д.

---

## 📦 Watchdog и система оповещений

### `ha-watchdog.sh`

Скрипт мониторит:

- доступность Home Assistant (`http://localhost:8123`)
- работоспособность всех Docker-контейнеров
- системную нагрузку (`uptime`)
- соединение с интернетом (`ping 8.8.8.8`)

Логи:
- `/var/log/ha-watchdog.log` — история запусков и нагрузка
- `/var/log/ha-failures.log` — список обнаруженных проблем

Контроль одиночного запуска реализован через `/tmp/ha-watchdog-state.txt`.

### `ha-watchdog.service`

Юнит systemd для запуска watchdog-а при загрузке и с перезапуском:

```ini
[Unit]
Description=HA Watchdog Monitor Service
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
ExecStart=/usr/local/bin/ha-watchdog.sh
Restart=always

[Install]
WantedBy=multi-user.target
```

---

### 🧹 Logrotate для логов

**Автоматическая настройка:** Logrotate конфигурируется автоматически при установке через `install.sh`

**Конфигурации установлены:**

- `/etc/logrotate.d/ha-monitoring` - для логов системы мониторинга
- `/etc/logrotate.d/homeassistant` - для логов Home Assistant  
- `/etc/systemd/journald.conf` - ограничения systemd journal (500MB)

**Параметры ротации:**

```bash
# Высокочастотные логи (каждые 2-5 минут)
/var/log/ha-watchdog.log, /var/log/ha-failure-notifier.log
├─ Размер: 5MB → ротация  
├─ Архив: 10 файлов (50MB общий лимит)
├─ Частота: ежедневно
└─ Сжатие: да

# Средние логи  
/var/log/ha-failures.log, /var/log/ha-reboot.log
├─ Размер: 10MB → ротация
├─ Архив: 5 файлов  
└─ Частота: еженедельно

# Home Assistant
/srv/homeassistant/home-assistant.log
├─ Размер: 50MB → ротация
├─ Архив: 7 файлов
├─ Метод: copytruncate (безопасно для HA)
└─ Частота: ежедневно
```

**Управление через ha-monitoring-control:**

```bash
ha-monitoring-control log-sizes      # размеры всех логов
ha-monitoring-control rotate-logs    # принудительная ротация  
ha-monitoring-control clean-journal  # очистка systemd journal
```

**Автоматическая ротация - systemd timer:**

```bash
# Проверка статуса logrotate
systemctl status logrotate.timer
● logrotate.timer - Daily rotation of log files
  Active: active (waiting)
  Trigger: ежедневно в 00:00 UTC (полночь)
  
# Следующий запуск
systemctl list-timers logrotate.timer
```

- **Расписание**: Ежедневно в 00:00 (полночь) через systemd timer
- **Метод**: `logrotate.timer` → `logrotate.service` (современная замена cron)
- **Настройки**: `/lib/systemd/system/logrotate.timer` (OnCalendar=daily)
- **Автозапуск**: включен при загрузке системы

---

### 🔔 `ha-alert.sh`

Этот скрипт запускается отдельно и сканирует `ha-failures.log`, чтобы:

- определить новые проблемы
- отправить сообщение в Telegram (или другую систему)
- вести журнал отправленных алертов (`/var/log/ha-alerted-ids.txt`)

Пример:

```bash
#!/bin/bash
FAILURE_LOG="/var/log/ha-failures.log"
ALERTED_IDS="/var/log/ha-alerted-ids.txt"

mkdir -p /var/log
[[ -f $ALERTED_IDS ]] || touch $ALERTED_IDS

while read -r line; do
  hash=$(echo "$line" | md5sum | cut -d' ' -f1)
  if ! grep -q "$hash" "$ALERTED_IDS"; then
    # send_to_telegram "$line"
    echo "$hash" >> "$ALERTED_IDS"
  fi
done < "$FAILURE_LOG"
```

Создай systemd таймер или cron-задачу для регулярного запуска.

---

## � System Configuration

### Swap Configuration
```bash
# Создание 2GB swap файла для улучшения производительности
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile

# Добавление в fstab для автозагрузки
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# Проверка результата
free -h
swapon --show
```

### Service Management
```bash
# Установка и управление сервисами мониторинга
cd /path/to/project
cp services/ha-monitoring-services-control.sh /usr/local/bin/
chmod +x /usr/local/bin/ha-monitoring-services-control.sh

# Использование
ha-monitoring-services-control.sh full    # Полная настройка
ha-monitoring-services-control.sh restart # Перезапуск сервисов
ha-monitoring-services-control.sh status  # Проверка статуса
```

## �🔑 SSH ключи доступа

Публичный ключ:
```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHNKOdVcE9EhXsjGimG00N86zo+ocaIzCx+0/KFTMiZU neoselcev@LenovoP14sgen2-Slava
```
Приватный ключ:
```
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACBzSjnVXBPRIV7IxophtNDfOs6PqHGiMwsftPyhUzImVAAAAKjNropLza6K
SwAAAAtzc2gtZWQyNTUxOQAAACBzSjnVXBPRIV7IxophtNDfOs6PqHGiMwsftPyhUzImVA
AAAEBwxp6MW7O9+NzY2hv/rg6blSU5BRwUkJPIXLrmr4Jwn3NKOdVcE9EhXsjGimG00N86
zo+ocaIzCx+0/KFTMiZUAAAAHm5lb3NlbGNldkBMZW5vdm9QMTRzZ2VuMi1TbGF2YQECAw
QFBgc=
-----END OPENSSH PRIVATE KEY-----
```
---

## 🔗 Быстрые SSH подключения

### Настройка ~/.ssh/config

Для удобного подключения добавьте в файл `~/.ssh/config`:

```bash
# Raspberry Pi Home Assistant (Локальная сеть)
Host rpi
    HostName 192.168.1.21
    Port 22
    User root
    IdentityFile ~/.ssh/raspberry_pi_key
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    ServerAliveInterval 60
    ServerAliveCountMax 3

# Raspberry Pi через VPN (Tailscale)
Host rpi-vpn
    HostName 100.103.54.125
    Port 22
    User root
    IdentityFile ~/.ssh/raspberry_pi_key
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
```

### Создание SSH ключа

```bash
# Создаем приватный ключ (уже есть выше в документе)
# Устанавливаем правильные права доступа
chmod 600 ~/.ssh/raspberry_pi_key
```

### Использование

```bash
# Подключение по локальной сети
ssh rpi

# Подключение через VPN (из любой точки мира)
ssh rpi-vpn

# Копирование файлов
scp ./monitoring/install.sh rpi:/tmp/
scp -r ./monitoring/ rpi:/srv/home/

# Выполнение команд
ssh rpi "docker ps"
ssh rpi-vpn "systemctl status ha-watchdog"
```

---