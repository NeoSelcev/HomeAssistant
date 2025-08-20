# 🏠 Smart Home Monitoring System

Comprehensive monitoring system for Home Assistant on Raspberry Pi 3B+ with automatic recovery, intelligent alerting, and remote management.

## 🎯 System Capabilities

### � **20-Point Health Monitoring**
- **Network**: Internet connectivity, gateway, interface status, WiFi signal strength
- **Resources**: Memory, disk space, CPU temperature, system load, swap usage
- **Services**: Docker containers, HA/Node-RED ports, critical systemd services
- **Remote Access**: SSH, Tailscale VPN, public HTTPS (Funnel)
- **System Health**: SD card errors, power supply, NTP sync, log sizes, HA database

### 🔧 **Intelligent Recovery**
- **Auto-restart**: Failed containers and network interfaces
- **Smart throttling**: Prevents notification spam with configurable intervals
- **Failure analysis**: Context-aware error categorization and response

### 📱 **Telegram Integration**
- **Priority alerts**: 🚨 Critical, ⚠️ Warning, ℹ️ Info, 📊 Status notifications
- **Rich messaging**: Hostname tagging, detailed failure context
- **Throttled delivery**: Configurable quiet periods for recurring issues

## 📋 System Specifications

### **Hardware & OS**
- **Device**: Raspberry Pi 3 Model B Plus Rev 1.3
- **OS**: Debian GNU/Linux 12 (bookworm), Kernel 6.1.0-37-arm64
- **Storage**: 15GB total, 5.3GB used (40%), 8.2GB available
- **Memory**: 902MB total, typically ~800MB used
- **Network**: 192.168.1.21 (local), 100.103.54.125 (VPN Tailscale)

### **Active Services Stack**
- **Home Assistant**: Port 8123 (ghcr.io/home-assistant/home-assistant:stable)
- **Node-RED**: Port 1880 (nodered/node-red:latest)
- **Tailscale VPN**: 100.103.54.125 with public HTTPS access
- **Docker**: v20.10.24 (container orchestration)
- **SSH**: Port 22 (ed25519 key authentication)

### **Docker Stack**
```yaml
services:
  homeassistant:
    image: homeassistant/home-assistant:stable
    network_mode: host
    ports: 8123
    
  nodered:
    image: nodered/node-red:latest
    ports: 1880
```

## 🔧 Monitoring Services

### **Service Schedule & Performance**

| Service | Frequency | Boot Delay | Purpose |
|---------|-----------|------------|----------|
| **ha-watchdog** | 2 minutes | 30 seconds | 20-point system health monitoring |
| **ha-failure-notifier** | 5 minutes | 1 minute | Telegram alerts & auto-recovery |
| **nightly-reboot** | Daily 03:30 | - | Maintenance reboot with health report |
| **update-checker** | Weekdays 09:00 ±30min | - | System/Docker update analysis |

### **Additional Components Deployed:**
- **Nightly Reboot Service**: ✅ Scheduled maintenance reboot at 3:30 AM
- **Update Checker Service**: ✅ Weekday update analysis at 9:00 AM (±30min randomization)
- **Required System Packages**: ✅ bc, wireless-tools, dos2unix, curl installed
- **Complete Service Suite**: ✅ 4 monitoring services with proper dependencies

### **Monitoring Coverage (20 Checks)**

#### **Network & Connectivity (4)**
- Internet connectivity, gateway reachability, network interface status, WiFi signal strength

#### **System Resources (4)** 
- Memory availability, disk space, CPU temperature, system load average

#### **Services & Containers (3)**
- Docker containers health, HA/Node-RED port availability, critical systemd services

#### **Remote Access (3)**
- SSH accessibility, Tailscale VPN status, public HTTPS access (Funnel)

#### **System Health (6)**
- SD card errors, power supply/throttling, NTP sync, log sizes, HA database integrity, swap usage

### **Intelligent Features**

- **Smart throttling**: Prevents notification spam with configurable intervals (5min-4hrs)
- **Auto-recovery**: Restarts failed containers and network interfaces
- **Context-aware alerts**: Different priorities and throttle times per issue type
- **Log rotation**: Automatic cleanup prevents disk space issues
- **Hash-based resumption**: Efficiently processes only new failures

## 🔐 SSH Configuration

### **Quick Connection Setup**

Add to your `~/.ssh/config`:
```
# Raspberry Pi Home Assistant (Local Network)
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

### **Setup SSH Key**
First, create the SSH key from project documentation:
```bash
# Create the private key
cat > ~/.ssh/raspberry_pi_key << 'EOF'
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACBzSjnVXBPRIV7IxophtNDfOs6PqHGiMwsftPyhUzImVAAAAKjNropLza6K
SwAAAAtzc2gtZWQyNTUxOQAAACBzSjnVXBPRIV7IxophtNDfOs6PqHGiMwsftPyhUzImVA
AAAEBwxp6MW7O9+NzY2hv/rg6blSU5BRwUkJPIXLrmr4Jwn3NKOdVcE9EhXsjGimG00N86
zo+ocaIzCx+0/KFTMiZUAAAAHm5lb3NlbGNldkBMZW5vdm9QMTRzZ2VuMi1TbGF2YQECAw
QFBgc=
-----END OPENSSH PRIVATE KEY-----
EOF

# Set correct permissions
chmod 600 ~/.ssh/raspberry_pi_key
```

### **Connection Commands**
```bash
# Local network
ssh rpi

# VPN connection  
ssh rpi-vpn

# File transfer
scp file.txt rpi:/srv/home/
scp -r ./monitoring/ rpi:/tmp/

# Remote commands
ssh rpi "docker ps"
ssh rpi "vcgencmd measure_temp && free -h"
```

### **Key Setup (if needed)**
```bash
# Generate key
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519

# Copy to Pi
ssh-copy-id -i ~/.ssh/id_ed25519.pub root@192.168.1.21
```

## 🚀 Installation & Setup

### **Prerequisites**
The monitoring system requires these additional packages on Raspberry Pi:
```bash
# Essential packages for monitoring functionality
sudo apt update
sudo apt install -y bc wireless-tools dos2unix curl htop
```

### **1. Deploy to Raspberry Pi**
```bash
cd monitoring
sudo ./install.sh
```

### **Package Dependencies:**
- **bc**: Calculator for mathematical operations in monitoring scripts
- **wireless-tools**: WiFi signal strength monitoring (iwconfig command)  
- **dos2unix**: Convert Windows line endings in configuration files
- **curl**: HTTP requests for Telegram notifications and API calls
- **htop**: Enhanced system process monitor for diagnostics and troubleshooting

### **2. Configure Telegram Bot**
1. Create bot via @BotFather in Telegram
2. Get bot token and your chat ID
3. Edit `/etc/ha-watchdog/config`:
```bash
TELEGRAM_BOT_TOKEN="your_bot_token"
TELEGRAM_CHAT_ID="your_chat_id"
```

### **3. Management Commands**
```bash
# Start monitoring
sudo ha-monitoring-control start

# Check status
sudo ha-monitoring-control status

# View logs
sudo ha-monitoring-control logs

# Test Telegram
sudo ha-monitoring-control test-telegram

# Stop monitoring
sudo ha-monitoring-control stop
```

### **4. PowerShell Remote Management (Windows)**
```powershell
# Deploy system
.\manage.ps1 -Action deploy -RpiIP 192.168.1.21

# Check status
.\manage.ps1 -Action status -RpiIP 192.168.1.21

# View logs
.\manage.ps1 -Action logs -RpiIP 192.168.1.21
```

## 📊 Monitoring Dashboard

### **Service Status Check**
```bash
# Quick system overview
ssh rpi "vcgencmd measure_temp && free -h && docker ps"

# Monitoring service status
ssh rpi "systemctl status ha-watchdog.timer ha-failure-notifier.timer"

# Recent failures
ssh rpi "tail -20 /var/log/ha-failures.log"
```

### **Log Files Location**
- **Watchdog**: `/var/log/ha-watchdog.log`
- **Failure Notifier**: `/var/log/ha-failure-notifier.log`
- **Failures**: `/var/log/ha-failures.log`
- **Reboot**: `/var/log/ha-reboot.log`
- **Updates**: `/var/log/ha-update-checker.log`

## 🔧 System Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   ha-watchdog   │───▶│  /var/log/       │───▶│ ha-failure-     │
│   (2 minutes)   │    │  ha-failures.log │    │ notifier        │
│                 │    │                  │    │ (5 minutes)     │
│ • 20 health     │    │ • Failure events │    │                 │
│   checks        │    │ • Timestamps     │    │ • Telegram      │
│ • Auto recovery │    │ • Error details  │    │   alerts        │
│ • Logging       │    │                  │    │ • Throttling    │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                                         │
                                                         ▼
                                               ┌─────────────────┐
                                               │   Telegram      │
                                               │   Bot           │
                                               │                 │
                                               │ 🚨 Critical     │
                                               │ ⚠️  Warning     │
                                               │ ℹ️  Info        │
                                               │ 📊 Status       │
                                               └─────────────────┘
```

## 🔧 Troubleshooting & System Health

### **SSH Key Setup (if needed)**

```bash
# Generate new SSH key
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519

# Copy key to Raspberry Pi
ssh-copy-id -i ~/.ssh/id_ed25519.pub root@192.168.1.21

# Test connection
ssh -i ~/.ssh/id_ed25519 root@192.168.1.21
```

### **Common Diagnostics**

```bash
# System health overview
ssh rpi "vcgencmd measure_temp && free -h && df -h"

# Enhanced system monitoring with htop
ssh rpi "htop -d 10 -n 1"

# Service status check
ssh rpi "systemctl status ha-watchdog.timer ha-failure-notifier.timer"

# Docker container health
ssh rpi "docker ps && docker stats --no-stream"

# Recent failure events
ssh rpi "tail -20 /var/log/ha-failures.log"

# Network connectivity test
ssh rpi "ping -c 3 8.8.8.8 && curl -s https://www.google.com"

# System resource monitoring
ssh rpi "htop -d 5 -n 3"
```

### **Performance Optimizations Made**

- **Reduced I/O**: Watchdog runs every 2min instead of 15s (8x less frequent)
- **Smart dependencies**: Services start only when prerequisites are ready  
- **Efficient logging**: Proper log rotation prevents disk space issues
- **Load balancing**: Randomized delays prevent system load spikes
- **Enhanced monitoring**: Expanded from 17 to 20 comprehensive health checks
- **Intelligent throttling**: 60-minute notification throttling prevents spam

### **🎉 Deployment Status: FULLY OPERATIONAL**

✅ **All 4 monitoring services active and scheduled:**
- ha-watchdog.timer (every 2 minutes)
- ha-failure-notifier.timer (every 5 minutes)  
- nightly-reboot.timer (daily at 3:30 AM)
- update-checker.timer (weekdays at 9:00 AM ±30min)

✅ **System packages installed:** bc, wireless-tools, dos2unix, curl  
✅ **Telegram integration:** Active and sending notifications  
✅ **Auto-recovery:** Container and network interface restart capabilities  
✅ **Boot persistence:** All services enabled for automatic startup

---

*Smart Home Monitoring System - Comprehensive health monitoring with intelligent alerting for Raspberry Pi Home Assistant installations.*
.\manage.ps1 -Action check -RpiIP 192.168.1.21
```

## 📁 Структура проекта

```
project/
├── 📋 README.md                           # Эта документация
├── 🔧 manage.ps1                          # Управление с Windows (9 команд)
├── 🐳 docker-compose.yml                  # Docker стек (HA + Node-RED)
├── 📁 monitoring/                         # Система мониторинга
│   ├── scripts/
│   │   ├── ha-watchdog.sh                 # Мониторинг каждые 2 минуты
│   │   ├── ha-failure-notifier.sh         # Обработка сбоев + Telegram
│   │   ├── nightly-reboot.sh              # Ночная перезагрузка
│   │   └── update-checker.sh              # Проверка обновлений
│   ├── systemd/                           # Автозапуск сервисов
│   │   ├── ha-watchdog.service/timer      # SystemD конфигурация
│   │   ├── ha-failure-notifier.service/timer     
│   │   ├── nightly-reboot.service/timer
│   │   └── update-checker.service/timer
│   ├── config/
│   │   └── ha-watchdog.conf               # Пороги мониторинга
│   └── install.sh                         # Автоматическая установка
├── 📁 tailscale_native/                   # Нативная конфигурация Tailscale
│   ├── systemd/                           # Сервисы: tailscaled, serve, funnel
│   ├── config/tailscaled.default          # Переменные окружения
│   └── restore-tailscale.sh               # Скрипт восстановления
├── 📁 management/                         
│   └── system-diagnostic.sh               # Комплексная диагностика
└── 📁 docs/                               # Сетевая архитектура
    ├── network-infrastructure.md          # Топология домашней сети
    ├── raspberrypi_ha_stack_complete_UPDATED.md  # Полная архитектура Pi
    └── images/                            # Схемы и диаграммы
```

## 🌐 Tailscale VPN Configuration

### **Current Setup**
- **Device**: rpi3-20250711 (единственное активное)
- **IP**: 100.103.54.125
- **Public URL**: https://rpi3-20250711.tail586076.ts.net/
- **Local HTTPS**: https://100.103.54.125:8443/

### **Restore Tailscale (if needed)**
```bash
cd tailscale_native/
sudo ./restore-tailscale.sh
```

## 🔔 Telegram уведомления

Система отправляет уведомления с эмодзи приоритетами:
- � **КРИТИЧНО**: Высокая температура (>70°C), недоступность Home Assistant
- 🟠 **ВАЖНО**: Упавшие Docker контейнеры, проблемы сети
- 🟡 **ПРЕДУПРЕЖДЕНИЕ**: Высокая загрузка системы, медленная сеть
- 🟢 **ИНФОРМАЦИЯ**: Восстановление сервисов, успешные перезапуски

## 🌐 Сетевая инфраструктура

### Основные устройства
- **Главный роутер**: Technicolor FGA2233PTN (оптоволокно)
- **Mesh система**: TP-Link Deco HC220-G1-IL (расширение покрытия)
- **IoT роутеры**: Изолированные сети для умных устройств
- **WiFi расширитель**: TP-Link RE305

### Конфигурация
- **Сеть**: 192.168.1.0/24
- **Pi адрес**: 192.168.1.21 (статический)
- **DNS**: 8.8.8.8, 1.1.1.1
- **VPN**: Tailscale для удаленного доступа

## 📊 Мониторинг и диагностика

### Ключевые метрики
- Температура CPU (норма <65°C, критично >70°C)
- Загрузка системы (CPU, RAM, диск)
- Доступность сервисов (ping, port check)
- Состояние Docker контейнеров

### Автоматическое восстановление
- Перезапуск упавших контейнеров
- Восстановление WiFi интерфейса
- Очистка логов при переполнении диска
- Уведомления о всех действиях

---
*Smart Home Monitoring System v2.0 - Raspberry Pi 3B+ + Home Assistant*  
*Создано для автоматического мониторинга и поддержания работоспособности умного дома*
