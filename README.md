# 🏠 Smart Home Monitoring System

Comprehensive monitoring system for Home Assistant on Raspberry Pi 3B+ with automatic recovery, intelligent alerting, and remote management.

## ⚡ Recent Updates (September 2025)

### 📢 **telegram-sender v1.0 - Centralized Telegram Service**

**New Component:** Universal service for sending messages to Telegram with topic support and advanced logging.

**Key Features:**
- 🎯 **Topic-oriented sending** - automatic topic detection by ID
- 🔄 **Retry mechanism** - 3 sending attempts with 2-second delay
- 📝 **Detailed logging** - tracking senders, statuses, errors
- ⚙️ **Flexible configuration** - separate config file with full settings
- 🔒 **Security** - token validation and message verification
- 📊 **Metrics** - sending statistics and performance data

**Supported Topics:**
- 🏠 **SYSTEM (ID: 2)** - System messages and general information
- 🚨 **ERRORS (ID: 10)** - Critical errors and system failures  
- 📦 **UPDATES (ID: 9)** - Package and Docker image updates
- 🔄 **RESTART (ID: 4)** - Reboots and service restarts

**Service Files:**
```
/usr/local/bin/telegram-sender.sh     # Main script
/etc/telegram-sender/config           # Configuration
/var/log/telegram-sender.log          # Sending logs  
/etc/logrotate.d/telegram-sender      # Log rotation
```

**Usage:**
```bash
# Direct call with topic
telegram-sender.sh "Message" "10"  # To ERRORS topic

# From monitoring scripts
"$TELEGRAM_SENDER" "$message" "2"    # To SYSTEM topic
```

**Refactoring Results:**
- ✅ **Removed ~65 lines of duplicated code** from monitoring services
- ✅ **Replaced 14 curl calls** with single centralized service
- ✅ **Simplified send_telegram functions** in ha-failure-notifier, update-checker, nightly-reboot
- ✅ **Single configuration point** - no more token duplication needed
- ✅ **Centralized logging** - all sends logged in one place

### 🧠 **ha-system-health-check v1.0 - Comprehensive System Diagnostics**

**New Tool:** Complete system health monitoring and diagnostics toolkit.
- Protects SSH from brute-force attacks
- Ban time: 1 hour after 3 failed attempts

**📊 stress-ng**
- Performance testing utility for comprehensive system diagnostics
- Tests CPU, memory, disk I/O under loadsive Checks:**
- 🖥️ **System Resources** - Memory, disk, CPU load, temperature
- 🌐 **Network Connectivity** - Internet, gateway, DNS, interfaces
- 🐳 **Docker Services** - Daemon, containers, compose files
- 🏠 **HA Monitoring** - Watchdog, notifier, scripts, timers
- 📊 **Service Availability** - Port checks (8123, 1880, 9000, 8080) using bash `/dev/tcp`
- 📝 **Log Analysis** - File sizes, recent entries, state files
- 🔒 **Security Status** - SSH, firewall, updates
- ⚡ **Performance Tests** - Disk speed, memory stress tests

**Easy Remote Access:**
```bash
# Quick commands for Raspberry Pi
ssh rpi-vpn health-check         # Full diagnostics
ssh rpi-vpn health-quick         # Fast check
ssh rpi-vpn health-monitor       # Real-time monitoring
```

**Smart Reporting:**
- 🎨 Color-coded results (✓ PASS, ✗ FAIL, ⚠ WARN)
- 📊 Statistical summary with percentage scores
- 📋 Detailed reports saved to `/tmp/ha-health-report-*.txt`
- 🔄 Automatic system health assessment

### �🧠 **ha-failure-notifier v3.1 - Smart Throttling System**

**New Enhancement:** Added intelligent event-type based throttling system that replaces the generic "50 events max" limit with priority-based quotas.

**Smart Throttling Features:**
- 🔴 **Critical Events** (HA_SERVICE_DOWN, MEMORY_CRITICAL): 20 events/30min
- 🟡 **High Priority** (HIGH_LOAD, CONNECTION_LOST): 10 events/30min  
- 🟠 **Warnings** (MEMORY_WARNING, DISK_WARNING): 5 events/30min
- 🔵 **Info Events** (other): 3 events/30min
- ⏰ **Rolling Window** - 30-minute sliding window with automatic cleanup
- 🔄 **Type Independence** - Different event types don't block each other
- 🛡️ **Dual Protection** - Smart + legacy throttling for compatibility

### 🔧 **ha-failure-notifier v3.0 - Timestamp-Based Event Processing**

**Problem Solved:** Version 2.0 caused cascades of identical Telegram notifications after log rotation because the notifier would reprocess all events from the beginning of the new log file, including old events that had already been processed.

**Solution:** Completely redesigned to use **timestamp-based tracking** instead of file position tracking.

**Key Features:**
- ✅ **Smart Throttling** - Priority-based event quotas (Critical:20, High:10, Warning:5, Info:3 per 30min)
- ✅ **Timestamp Tracking** - Stores Unix timestamp of last processed event instead of file position
- ✅ **Intelligent Event Classification** - Automatic priority detection (FATAL/ERROR/WARN/INFO)
- ✅ **Rotation Independence** - Works regardless of log file rotation, truncation, or recreation
- ✅ **Duplicate Prevention** - Processes only events newer than last processed timestamp
- ✅ **Perfect Accuracy** - Based on actual event time, not file structure
- ✅ **Dual Throttling System** - Smart priority-based + legacy time-based for compatibility
- ✅ **Rolling Window** - 30-minute sliding window with automatic cleanup
- ✅ **Backward Compatibility** - Maintains all existing functionality and state files
- ✅ **Smart File Rotation Detection** - Tracks metadata (size, creation time, first line hash)
- ✅ **Position-Based Processing** - Processes only NEW failure events (1-5 lines vs 1400+)
- ✅ **Anti-Spam Protection** - Limits to 50 events after rotation + smart priority limits
- ✅ **Performance Boost** - Reduced processing time from 60s timeout to <1s execution
- ✅ **State Persistence** - Maintains position across service restarts

**How It Works:**
```bash
# New state file: /var/lib/ha-failure-notifier/last_timestamp.txt
# Stores Unix timestamp: 1756276395 (last processed event time)

# Algorithm:
1. Read last_timestamp from file
2. For each line in log: extract event timestamp  
3. Process only if event_timestamp > last_timestamp
4. Save newest processed timestamp
```

**Files Added:**
```
/var/lib/ha-failure-notifier/
├── last_timestamp.txt  # NEW: Unix timestamp of last processed event
├── position.txt        # Kept for compatibility
├── metadata.txt        # Enhanced file rotation detection
└── throttle.txt        # Smart notification throttling
```

**Result:** Eliminates cascading duplicate notifications after log rotation. Events are processed exactly once based on their actual occurrence time, regardless of file changes.

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
    logging:
      max-size: "10m"
      max-file: "7"
    
  nodered:
    image: nodered/node-red:latest
    ports: 1880
    logging:
      max-size: "10m" 
      max-file: "7"
```

### **Log Management Configuration**

**Multi-level log management system:**

1. **Docker logs** (`/etc/docker/daemon.json`):
   - Global limits: 10MB per file, 7 archived files per container
   - Total Docker logs: ~140MB (HA + NodeRED)

2. **Application logs** (logrotate):
   - HA monitoring logs: 5-20MB rotation limits with 10-3 file retention
   - Home Assistant logs: 50MB rotation with 7 day retention
   - Automated rotation: daily at 00:00 UTC via systemd timer

3. **System logs** (systemd journal):
   - Limited to 500MB total (down from potential 1.5GB+)
   - 30-day retention with compression

**Log management commands:**

```bash
ha-monitoring-control log-sizes      # Check all log sizes
ha-monitoring-control rotate-logs    # Force log rotation  
ha-monitoring-control clean-journal  # Clean systemd journal
```

**Automatic rotation:** `logrotate.timer` runs daily at midnight (systemd, not cron)

## 🔧 Monitoring Services

### **Service Schedule & Performance**

| Service | Frequency | Boot Delay | Purpose |
|---------|-----------|------------|----------|
| **ha-watchdog** | 2 minutes | 30 seconds | 20-point system health monitoring |
| **ha-failure-notifier** | 5 minutes | 1 minute | Telegram alerts & auto-recovery (v2.0 enhanced) |
| **nightly-reboot** | Daily 03:30 | - | Maintenance reboot with health report |
| **update-checker** | Weekdays 09:00 ±30min | - | System/Docker update analysis |

### **Additional Components Deployed:**
- **Nightly Reboot Service**: ✅ Scheduled maintenance reboot at 3:30 AM
  - **Security Fix**: Removed `Persistent=true` to prevent reboot loops on missed schedules
  - **Enhanced Logging**: Detailed system metrics and Telegram notifications
- **Update Checker Service**: ✅ Weekday update analysis at 9:00 AM (±30min randomization)
  - **Added**: "No updates available" Telegram notifications for peace of mind
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

# Raspberry Pi via VPN (Tailscale)
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

## 🩺 System Health Diagnostics - SUPER VERSION

### **Quick Health Check Commands**

The system includes a **SUPER comprehensive diagnostic tool** with **79 checks** accessible via simple SSH commands:

```bash
# Full system diagnostics (79 checks) - SUPER VERSION
ssh rpi-vpn health-check

# Quick essential checks
ssh rpi-vpn health-quick

# Quiet mode (errors only)
ssh rpi-vpn health-check --quiet

# Verbose mode with debugging
ssh rpi-vpn health-check --verbose

# View available options
ssh rpi-vpn "health-check --help"
```

### **SUPER Diagnostic Coverage (79 checks total)**

**🖥️ Basic System Info (6 checks)**
- Hostname, Uptime, Kernel, OS, Architecture, CPU Model

**💾 System Resources (8 checks)**
- Memory usage (total/used/available), disk space, CPU load, temperature monitoring

**🌐 Extended Network Diagnostics (11 checks)**  
- Internet access, gateway, DNS, network interfaces, WiFi/Ethernet status, IP addresses

**🐳 Docker Services (12+ checks)**
- Docker daemon, version, info, containers, compose configuration

**🔗 Tailscale VPN Diagnostics (8+ checks)**
- Daemon status, connection, node info, peers, HA accessibility via VPN

**🔍 HA Monitoring Services (12+ checks)**
- Systemd services, timers, scripts, configuration validation

**📊 Log Analysis (6+ checks)**
- Log files, sizes, recent entries, state files

**🚪 Service Availability (4+ checks)**
- HA, Node-RED, Portainer, Zigbee2MQTT port checks

**📈 Recent Failures Analysis (4+ checks)**
- Failure logs, notification statistics, throttling status

**🔒 Enhanced Security (8+ checks)**
- SSH configuration, firewall, fail2ban, file permissions, security updates

**⚡ Performance Testing (2+ checks)**
- Disk write speed, memory stress test

### **Latest Performance Results**
- ✅ **66/79 checks passed (83%)**
- ⚠️ **12 warnings** (mostly security recommendations)
- ❌ **1 error** (minor issue)

---

## 🛡️ Security Components

### **Installed Security Tools**

The system includes comprehensive security protection:

**🔥 UFW Firewall**
- Blocks unauthorized access from internet
- Allows access only from local network (192.168.1.0/24) and Tailscale VPN (100.64.0.0/10)
- Protected ports: SSH (22), Home Assistant (8123), Node-RED (1880)

**🚫 Fail2ban**  
- Automatically blocks IPs after failed login attempts
- Protects SSH from brute-force attacks
- Ban time: 1 hour after 3 failed attempts

**📊 stress-ng**
- Performance testing utility for comprehensive system diagnostics
- Tests CPU, memory, disk I/O under load
- Integrated into health check for automated performance validation

**🌡️ Temperature Monitoring**
- Normal: < 70°C (Raspberry Pi optimized thresholds)
- High: 70-75°C (warning level)
- Critical: > 75°C (requires attention)

**📋 Logrotate Configuration**
- Fail2ban logs: Daily rotation, 52 weeks retention (`/var/log/fail2ban.log`)
- UFW logs: Daily rotation, 30 days retention (`/var/log/ufw.log`)
- SSH logs: Managed by systemd journald (automatic rotation)
- Automated cleanup prevents disk space issues

### **Security Configuration**

```bash
# View firewall status
ssh rpi-vpn "sudo ufw status"

# Check fail2ban status  
ssh rpi-vpn "sudo fail2ban-client status"

# Run performance stress test
ssh rpi-vpn "stress-ng --cpu 1 --vm 1 --vm-bytes 100M -t 30s"
```

### **Access Control**
- **Local Network:** Full access (192.168.1.0/24)
- **Tailscale VPN:** Full access (100.64.0.0/10)  
- **Internet:** Blocked by UFW firewall
- **SSH:** Key-based authentication only, passwords disabled
- Docker daemon, container status, compose file validation, specific containers

**HA Monitoring Services (6+ checks)**
- Watchdog service, failure notifier, timers, script validation

**Service Availability (4 checks)**
- Port checks for HA (8123), Node-RED (1880), Portainer (9000), Zigbee2MQTT (8080)

**Log Analysis (6+ checks)**
- Log file sizes, recent entries, state files, throttling statistics

**Security & Updates (4+ checks)**
- SSH status, firewall, fail2ban, security updates

**Performance Tests (2 checks)**
- Disk write speed, memory stress testing

### **Diagnostic Output Example**
```
================================================================
  HA System Health Check v1.0
================================================================
[✓ PASS] Memory usage (67.2%)
[✓ PASS] Home Assistant (port 8123) - Service responding  
[⚠ WARN] Portainer (port 9000) - Service unavailable
[✗ FAIL] DNS resolution - DNS not working

Total checks: 37 | Passed: 24 (64%) | Warnings: 8 | Errors: 5
🚨 SYSTEM REQUIRES IMMEDIATE ATTENTION
```

### **Automated Setup on Raspberry Pi**

The health check system is automatically configured during installation:
- **Main script**: `/usr/local/bin/ha-health-check`
- **Quick access**: `health-check`, `health-quick`, `health-monitor` commands  
- **Reports**: Saved to `/tmp/ha-health-report-YYYYMMDD-HHMMSS.txt`
- **Logs**: Diagnostic logs in `/var/log/ha-health-check.log`

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

**New centralized configuration** (via telegram-sender service):

1. Create a bot via @BotFather in Telegram
2. Obtain the bot token and group ID with discussion topics
3. Create the telegram-sender configuration:

```bash
sudo mkdir -p /etc/telegram-sender
sudo tee /etc/telegram-sender/config << 'EOF'
# Core bot settings
TELEGRAM_BOT_TOKEN="your_bot_token_here"
TELEGRAM_CHAT_ID="your_group_chat_id"

# Group topics (message_thread_id)
TELEGRAM_TOPIC_SYSTEM=2     # System messages
TELEGRAM_TOPIC_ERRORS=10    # Errors and failures
TELEGRAM_TOPIC_UPDATES=9    # Updates
TELEGRAM_TOPIC_RESTART=4    # Restarts

# Performance settings
TELEGRAM_TIMEOUT=10
TELEGRAM_RETRY_COUNT=3
TELEGRAM_RETRY_DELAY=2
EOF
```

**Deprecated configuration** (no longer used):
- ~~`/etc/ha-watchdog/config`~~ - Telegram tokens moved to telegram-sender
- All monitoring services now use centralized telegram-sender.sh

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
- **Telegram Sender**: `/var/log/telegram-sender.log` (new centralized log)

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

## 📁 Project Structure

```
project/
├── 📋 README.md                           # This documentation
├── 🔧 manage.ps1                          # Management from Windows (9 commands)
├── 🐳 docker-compose.yml                  # Docker stack (HA + Node-RED)
├── 📁 monitoring/                         # Monitoring system
│   ├── scripts/
│   │   ├── ha-watchdog.sh                 # Monitoring every 2 minutes
│   │   ├── ha-failure-notifier.sh         # Failure processing + Telegram
│   │   ├── nightly-reboot.sh              # Nightly reboot
│   │   └── update-checker.sh              # Update checking
│   ├── systemd/                           # Service autostart (systemd units)
│   │   ├── ha-watchdog.service/timer      # SystemD configuration
│   │   ├── ha-failure-notifier.service/timer     
│   │   ├── nightly-reboot.service/timer
│   │   └── update-checker.service/timer
│   ├── config/
│   │   └── ha-watchdog.conf               # Monitoring thresholds
│   └── install.sh                         # Automatic installation
├── 📁 tailscale_native/                   # Native Tailscale configuration
│   ├── systemd/                           # Services: tailscaled, serve, funnel
│   ├── config/tailscaled.default          # Environment variables
│   └── restore-tailscale.sh               # Restore script
├── 📁 management/                         
│   └── system-diagnostic.sh               # Comprehensive diagnostics
└── 📁 docs/                               # Network architecture
  ├── network-infrastructure.md          # Home network topology
  ├── raspberrypi_ha_stack_complete_UPDATED.md  # Full Pi architecture
  └── images/                            # Schemes and diagrams
```

## 🌐 Tailscale VPN Configuration

### **Current Setup**
- **Device**: rpi3-20250711 (only active device)
- **IP**: 100.103.54.125
- **Public URL**: https://rpi3-20250711.tail586076.ts.net/
- **Local HTTPS**: https://100.103.54.125:8443/

### **Restore Tailscale (if needed)**
```bash
cd tailscale_native/
sudo ./restore-tailscale.sh
```

## 🔔 Telegram Notifications

The system sends notifications with emoji priorities:
- 🔴 **CRITICAL**: High temperature (>70°C), Home Assistant unreachable
- 🟠 **IMPORTANT**: Docker container failures, network issues
- 🟡 **WARNING**: High system load, slow network
- 🟢 **INFO**: Service recovery, successful restarts
- 🌙 **NIGHTLY REPORTS**: Daily system status and update summaries

## 🌐 Network Infrastructure

### Core Devices
- **Main router**: Technicolor FGA2233PTN (fiber)
- **Mesh system**: TP-Link Deco HC220-G1-IL (coverage extension)
- **IoT routers**: Isolated networks for smart devices
- **WiFi extender**: TP-Link RE305

### Configuration
- **Network**: 192.168.1.0/24
- **Pi address**: 192.168.1.21 (static)
- **DNS**: 8.8.8.8, 1.1.1.1
- **VPN**: Tailscale for remote access

## 📊 Monitoring and Diagnostics

### Key Metrics
- CPU temperature (normal <65°C, critical >70°C)
- System load (CPU, RAM, disk)
- Service availability (ping, port check)
- Docker container status

### Automatic Recovery
- Restart failed containers
- Restore WiFi interface
- Clean logs when disk fills
- Notify about all actions

---
*Smart Home Monitoring System v2.0 - Raspberry Pi 3B+ + Home Assistant*  
*Created for automated monitoring and maintaining smart home reliability*

**Latest Update (August 2025):** Enhanced failure notification system with intelligent file rotation detection and anti-spam protection. Now processes only NEW events, eliminating duplicate alerts.
