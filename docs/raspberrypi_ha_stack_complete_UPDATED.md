# 🏠 Smart Home Network Architecture

## Hardware & OS Configuration

### Raspberry Pi 3B+ Setup
- **OS**: Debian 12 (Bookworm), ARM64 architecture
- **Hostname**: rpi3-20250711  
- **SSH Access**: Port 22, key-based authentication
- **Installation**: Manual setup with full root access

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
    image: homeassistant/home-assistant:stable
    network_mode: host
    ports: 8123
    volumes: ./homeassistant:/config
    
  nodered:
    image: nodered/node-red:latest
    ports: 1880
    volumes: ./nodered:/data
```

### Tailscale VPN (Native Installation)
- **Service**: Native systemd services (not containerized)
- **Device**: rpi3-20250711
- **IP**: 100.103.54.125  
- **Public HTTPS**: https://rpi3-20250711.tail586076.ts.net/
- **Services**: tailscaled, tailscale-serve-ha, tailscale-funnel-ha

### Service Management
- **Working Directory**: `/srv/home`
- **Auto-start**: systemd service `home-stack.service`
- **Management**: `docker compose up/down`

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
*Updated: 2025-08-05 - Smart Home Network Documentation*
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

Создай файл `/etc/logrotate.d/ha-watchdog`:

```ini
/var/log/ha-*.log {
    rotate 5
    size 1M
    missingok
    notifempty
    compress
    delaycompress
    copytruncate
}
```

Добавь в `cron`:
```sh
echo '0 0 * * * root /usr/sbin/logrotate /etc/logrotate.conf' >> /etc/crontab
```

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

## 🔑 SSH ключи доступа

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