# 🏠 Smart Home Monitoring System

Comprehensive monitoring system for Home Assistant on Raspberry Pi 3B+ with automatic recovery, intelligent alerting, and remote management featuring advanced system diagnostics, centralized Telegram notifications, and intelligent failure detection.

## 🎯 System Capabilities

### 🔍 **Comprehensive System Diagnostics**
Advanced system health monitoring with **79 comprehensive checks** accessible via unified aliases:

```bash
# System diagnostic aliases (all point to system-diagnostic.sh)
sysdiag    # Full system diagnostics (79 checks)
diag       # Same as sysdiag
diagnostic # Same as sysdiag
syscheck   # Quick essential checks (--quick)
fullcheck  # Full diagnostic with detailed output (--full)
```

**Remote SSH Usage:**
```bash
# Updated remote commands
ssh rpi-vpn sysdiag       # Full diagnostics (was health-check)
ssh rpi-vpn syscheck      # Quick check (was health-quick)  
ssh rpi-vpn fullcheck     # Full detailed check (new)
```

**Diagnostic Coverage:**
- 🖥️ **System Resources** - Memory, disk, CPU load, temperature
- 🌐 **Network Connectivity** - Internet, gateway, DNS, interfaces
- 🐳 **Docker Services** - Daemon, containers, compose files
- 🏠 **HA Monitoring** - Watchdog, notifier, scripts, timers
- 📊 **Service Availability** - Port checks (8123, 1880, 9000, 8080) using bash `/dev/tcp`
- 📝 **Log Analysis** - File sizes, recent entries, state files
- 🔒 **Security Status** - SSH, firewall, updates
- ⚡ **Performance Tests** - Disk speed, memory stress tests

**Detailed Diagnostic Coverage (79 checks total):**

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

**Latest Performance Results:**
- ✅ **66/79 checks passed (83%)**
- ⚠️ **12 warnings** (mostly security recommendations)
- ❌ **1 error** (minor issue)

**Smart Reporting:**
- 🎨 Color-coded results (✓ PASS, ✗ FAIL, ⚠ WARN)
- 📊 Statistical summary with percentage scores
- 📋 Detailed reports saved to `/tmp/system_diagnostic_YYYYMMDD_HHMMSS.txt`
- 🔄 Automatic system health assessment

### 🔧 **Intelligent Recovery & Monitoring**
- **20-Point Health Monitoring**: Network, resources, services, remote access, system health
- **Auto-restart**: Failed containers and network interfaces
- **Smart throttling**: Prevents notification spam with configurable intervals
- **Failure analysis**: Context-aware error categorization and response

### 📱 **Advanced Telegram Integration**
Centralized **telegram-sender v1.0** service with topic-based routing and intelligent throttling:

**Key Features:**
- 🎯 **Topic-oriented sending** - automatic topic detection by ID
- 🔄 **Retry mechanism** - 3 sending attempts with 2-second delay
- 📝 **Detailed logging** - tracking senders, statuses, errors
- ⚙️ **Flexible configuration** - separate config file with full settings
- 🔒 **Security** - token validation and message verification
- 📊 **Performance Metrics** - sender tracking and delivery statistics

**Supported Topics:**
- 🏠 **SYSTEM (ID: 2)** - System messages and general information
- 🚨 **ERRORS (ID: 10)** - Critical errors and system failures  
- 📦 **UPDATES (ID: 9)** - Package and Docker image updates
- 🔄 **RESTART (ID: 4)** - Reboots and service restarts
- 🔍 **SYSTEM_DIAGNOSTIC (ID: 123)** - System diagnostic reports and health checks
- 💾 **BACKUP (ID: 131)** - Backup reports and status updates

**Notification Priorities:**
- 🔴 **CRITICAL**: High temperature (>70°C), Home Assistant unreachable
- 🟠 **IMPORTANT**: Docker container failures, network issues
- 🟡 **WARNING**: High system load, slow network
- 🟢 **INFO**: Service recovery, successful restarts
- 🌙 **NIGHTLY REPORTS**: Daily system status and update summaries

**Usage:**
```bash
# Direct call with topic
telegram-sender.sh "Message" "10"  # To ERRORS topic
telegram-sender.sh "System diagnostic completed" "123"  # To SYSTEM_DIAGNOSTIC topic
telegram-sender.sh "Backup completed successfully" "131"  # To BACKUP topic

# From monitoring scripts
"$TELEGRAM_SENDER" "$message" "2"    # To SYSTEM topic
"$TELEGRAM_SENDER" "$diagnostic_report" "123"  # To SYSTEM_DIAGNOSTIC topic
"$TELEGRAM_SENDER" "$backup_status" "131"      # To BACKUP topic
```

**Service Files:**
```
/usr/local/bin/telegram-sender.sh     # Main script
/etc/telegram-sender/config           # Configuration
/var/log/telegram-sender.log          # Sending logs  
/etc/logrotate.d/telegram-sender      # Log rotation
```

**Architecture Benefits:**
- 🎯 **Single Point of Configuration** - All Telegram settings in `/etc/telegram-sender/config`
- 📝 **Centralized Logging** - Unified logs in `/var/log/telegram-sender.log`
- 🔄 **Retry & Error Handling** - Built-in resilience with 3 attempts per message
- 🏗️ **Topic-Based Routing** - Automatic message categorization by service type
- 📊 **Performance Metrics** - Sender tracking and delivery statistics

**Refactoring Results:**
- ✅ **Eliminated 65+ lines of duplicate code** across monitoring services
- ✅ **Reduced 14 individual curl calls** to single service invocations
- ✅ **Simplified configuration management** - no more token duplication
- ✅ **Enhanced error handling** - centralized retry logic and logging

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

## 🔧 System Configuration

### **Swap Configuration**
Enhanced system performance with 2GB swap file:

```bash
# Create 2GB swap file for improved performance
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile

# Add to fstab for auto-mount
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# Verify result
free -h
swapon --show
```

### **Log Rotation Configuration**
Automated log management prevents disk space exhaustion:

**Logrotate Configurations:**
- `/etc/logrotate.d/ha-monitoring` - monitoring system logs
- `/etc/logrotate.d/homeassistant` - Home Assistant logs (50MB → rotate, 7 files)
- `/etc/logrotate.d/fail2ban` - Fail2ban logs (52 weeks retention)
- `/etc/logrotate.d/ufw` - UFW firewall logs (30 days retention)
- `/etc/systemd/journald.conf` - systemd journal limits (500MB max)

**High-frequency logs (every 2-5 minutes):**
```
/var/log/ha-watchdog.log, /var/log/ha-failure-notifier.log
├─ Size: 5MB → rotate
├─ Archive: 10 files (50MB total limit)
├─ Frequency: daily
└─ Compression: enabled
```

**Medium-frequency logs:**
```
/var/log/ha-failures.log, /var/log/ha-reboot.log
├─ Size: 10MB → rotate
├─ Archive: 5 files
└─ Frequency: weekly
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
| **ha-failure-notifier** | 5 minutes | 1 minute | Telegram alerts & auto-recovery with smart throttling |
| **nightly-reboot** | Daily 03:30 | - | Maintenance reboot with health report |
| **update-checker** | Weekdays 09:00 ±30min | - | System/Docker update analysis |

### **ha-failure-notifier - Advanced Features**

**Smart Throttling System:**
Intelligent event-type based throttling that replaces generic limits with priority-based quotas:

- 🔴 **Critical Events** (HA_SERVICE_DOWN, MEMORY_CRITICAL): 20 events/30min
- 🟡 **High Priority** (HIGH_LOAD, CONNECTION_LOST): 10 events/30min  
- 🟠 **Warnings** (MEMORY_WARNING, DISK_WARNING): 5 events/30min
- 🔵 **Info Events** (other): 3 events/30min
- ⏰ **Rolling Window** - 30-minute sliding window with automatic cleanup
- 🔄 **Type Independence** - Different event types don't block each other
- 🛡️ **Dual Protection** - Smart + legacy throttling for compatibility

**Timestamp-Based Processing:**
- ✅ **Rotation Independence** - Works regardless of log file rotation, truncation, or recreation
- ✅ **Duplicate Prevention** - Processes only events newer than last processed timestamp
- ✅ **Perfect Accuracy** - Based on actual event time, not file structure
- ✅ **Performance Boost** - Reduced processing time from 60s timeout to <1s execution

**State Files:**
```
/var/lib/ha-failure-notifier/
├── last_timestamp.txt        # Unix timestamp of last processed event
├── smart_throttle_history.txt # Smart throttling event history with priorities
├── position.txt              # Legacy: Last processed line number (kept for compatibility)
├── metadata.txt              # File metadata for rotation detection (size:ctime:mtime:hash)
├── throttle.txt              # Legacy: Timestamp tracking for notification throttling
└── hashes.txt                # Legacy hash storage (kept for compatibility)
```

### **Additional Components:**
- **Nightly Reboot Service**: Scheduled maintenance reboot at 3:30 AM with enhanced logging
- **Update Checker Service**: Weekday update analysis at 9:00 AM (±30min randomization)
- **Required System Packages**: bc, wireless-tools, dos2unix, curl, htop installed
- **Complete Service Suite**: 4 monitoring services with proper dependencies

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

## 🌐 Tailscale VPN Configuration

### **Current Setup**
- **Device**: rpi3-20250711 (only active device)
- **IP**: 100.103.54.125
- **Public URL**: https://rpi3-20250711.tail586076.ts.net/
- **Local HTTPS**: https://100.103.54.125:8443/

### **Native Installation**
- **Service**: Native systemd services (not containerized)
- **Services**: tailscaled, tailscale-serve-ha, tailscale-funnel-ha
- **Benefits**: Better performance, native OS integration

### **Tailscale systemd Services**

**tailscale-serve-ha.service:**
```ini
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

**tailscale-funnel-ha.service:**
```ini
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

### **Restore Tailscale (if needed)**
```bash
cd tailscale_native/
sudo ./restore-tailscale.sh
```

## 🐳 Docker Infrastructure

### **Core Services Stack**

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

### **Docker Logging Configuration**

Global settings (`/etc/docker/daemon.json`):

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

## 🏠 Home Assistant Configuration

### **Core Configuration (configuration.yaml)**

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

### **Text-to-Speech (TTS)**
Google Translate is used for TTS functionality:

```yaml
tts:
  - platform: google_translate
    service_name: google_say
```

### **Installed Integrations**
- ✅ **HACS** (Home Assistant Community Store) - installed manually
- ✅ **Sonoff (eWeLink)** - 48 devices via LAN/Cloud connectivity
- ✅ **Broadlink** - functional IR/RF transmitter
- ✅ **Roomba** - auto-discovered vacuum robot
- ✅ **Weather, Sun, TTS, Backup** - built-in integrations
- ⏳ **HomeBridge** - planned for Siri integration

## 🌀 Node-RED Integration

### **Connection**
- Connected to Home Assistant via WebSocket with long-lived token
- UI accessible at: http://192.168.1.21:1880/ (local) or via Tailscale VPN

### **Installed Palettes**
- `node-red` (core)
- `node-red-contrib-home-assistant-websocket` - HA integration
- `node-red-contrib-influxdb` - time series database
- `node-red-contrib-moment` - date/time handling
- `node-red-contrib-time-range-switch` - time-based switching
- `node-red-dashboard` - web dashboard
- `node-red-node-email` - email notifications
- `node-red-node-telegrambot` - Telegram integration
- `node-red-node-ui-table` - table UI components

### **Example Automation Flow**

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

### **Usage Examples**
```bash
# Local network connection
ssh rpi

# VPN connection (global access)
ssh rpi-vpn

# File copy operations
scp ./services/install.sh rpi:/tmp/
scp -r ./services/ rpi:/srv/home/

# Remote command execution
ssh rpi "docker ps"
ssh rpi-vpn "sysdiag --quick"
ssh rpi-vpn systemctl status ha-watchdog
```

## 🛡️ Security Components

### **Installed Security Tools**

The system includes comprehensive security protection:

**🔥 UFW Firewall**
- **Status**: Active and enabled on system startup
- **Default Policy**: Deny incoming, allow outgoing
- **Allowed Access**:
  - SSH (22): Local network (192.168.1.0/24) + Tailscale VPN (100.64.0.0/10)
  - Home Assistant (8123): Local network + Tailscale VPN only
  - Node-RED (1880): Local network + Tailscale VPN only
- **Blocked**: All internet access to services
- **Configuration**: `/etc/ufw/user.rules`

**🚫 Fail2ban**
- **Service**: `fail2ban.service` - active protection
- **SSH Protection**: Monitors `/var/log/auth.log`
- **Policy**: 3 failed attempts = 1 hour IP ban
- **Configuration**: `/etc/fail2ban/jail.local`
- **Status Check**: `fail2ban-client status sshd`
- **Log Rotation**: Daily rotation, 52 weeks retention (`/etc/logrotate.d/fail2ban`)

**📊 stress-ng**
- Performance testing utility for comprehensive system diagnostics
- Tests CPU, memory, disk I/O under load
- Integrated into health check for automated performance validation

**🌡️ Temperature Monitoring**
- Normal: < 70°C (Raspberry Pi optimized thresholds)
- High: 70-75°C (warning level)
- Critical: > 75°C (requires attention)

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

### **Automated Setup on Raspberry Pi**

The health check system is automatically configured during installation:
- **Main script**: `/usr/local/bin/system-diagnostic.sh`
- **Quick access**: `sysdiag`, `diag`, `diagnostic`, `syscheck`, `fullcheck` commands  
- **Reports**: Saved to `/tmp/system_diagnostic_YYYYMMDD_HHMMSS.txt`
- **Logs**: Diagnostic logs created automatically during execution

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

### **Package Dependencies:**
- **bc**: Calculator for mathematical operations in monitoring scripts
- **wireless-tools**: WiFi signal strength monitoring (iwconfig command)  
- **dos2unix**: Convert Windows line endings in configuration files
- **curl**: HTTP requests for Telegram notifications and API calls
- **htop**: Enhanced system process monitor for diagnostics and troubleshooting

### **1. Install Docker and Core Services**

**Install Docker on Raspberry Pi:**
```bash
# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Add current user to docker group
sudo usermod -aG docker $USER

# Install Docker Compose
sudo apt update
sudo apt install docker-compose-plugin

# Start and enable Docker service
sudo systemctl start docker
sudo systemctl enable docker

# Verify installation
docker --version
docker compose version
```

**Deploy Home Assistant and Node-RED containers:**
```bash
# Create project directory
mkdir -p ~/homeassistant
cd ~/homeassistant

# Create docker-compose.yml file
cat > docker-compose.yml << 'EOF'
services:
  homeassistant:
    image: ghcr.io/home-assistant/home-assistant:stable
    container_name: homeassistant
    privileged: true
    restart: unless-stopped
    environment:
      - TZ=Europe/London
    volumes:
      - ./homeassistant:/config
      - /run/dbus:/run/dbus:ro
    network_mode: host
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "7"
    
  nodered:
    image: nodered/node-red:latest
    container_name: nodered
    restart: unless-stopped
    environment:
      - TZ=Europe/London
    ports:
      - "1880:1880"
    volumes:
      - ./nodered:/data
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "7"
EOF

# Configure Docker daemon with global logging limits
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "7"
  }
}
EOF

# Restart Docker to apply configuration
sudo systemctl restart docker

# Start the containers
docker compose up -d

# Verify containers are running
docker ps
```

**Access services:**
- **Home Assistant**: http://192.168.1.21:8123
- **Node-RED**: http://192.168.1.21:1880

### **2. Deploy Monitoring System**

The `install.sh` script automatically installs and configures all monitoring services, systemd units, and configurations:

```bash
# Clone or copy the PRI-HA project to Raspberry Pi
git clone https://github.com/NeoSelcev/PRI-HA.git
cd PRI-HA/services

# Run the automated installation script
sudo ./install.sh
```

**What install.sh does:**

**🔧 System Preparation:**
- Checks for root privileges
- Verifies Docker installation (installs if missing)
- Installs required packages: `bc`, `wireless-tools`, `dos2unix`, `curl`, `htop`
- Adds diagnostic aliases to user shell profile

**📋 Service Installation:**
- **System Diagnostic**: `/usr/local/bin/system-diagnostic.sh` with aliases (`sysdiag`, `diag`, `diagnostic`, `syscheck`, `fullcheck`)
- **Telegram Sender**: `/usr/local/bin/telegram-sender.sh` with config template in `/etc/telegram-sender/`
- **HA Watchdog**: Service + timer for 20-point health monitoring every 2 minutes
- **HA Failure Notifier**: Service + timer for smart alerts and recovery every 5 minutes  
- **Nightly Reboot**: Service + timer for daily maintenance reboot at 03:30
- **Update Checker**: Service + timer for weekday update analysis at 09:00
- **Backup System**: Service + timer for automated Home Assistant backups
- **Logging Service**: Centralized log management and cleanup
- **System Diagnostic Startup**: Boot-time diagnostics

**🗂️ File Locations After Installation:**

**Scripts & Binaries:**
```
/usr/local/bin/
├── system-diagnostic.sh          # 79-check comprehensive diagnostics
├── telegram-sender.sh            # Centralized Telegram service
└── ha-monitoring-control         # Management utility
```

**Systemd Services & Timers:**
```
/etc/systemd/system/
├── ha-watchdog.service           # Health monitoring service
├── ha-watchdog.timer             # Every 2 minutes
├── ha-failure-notifier.service   # Alert & recovery service  
├── ha-failure-notifier.timer     # Every 5 minutes
├── nightly-reboot.service        # Maintenance reboot
├── nightly-reboot.timer          # Daily at 03:30
├── update-checker.service        # Update analysis
├── update-checker.timer          # Weekdays 09:00
├── ha-backup.service             # Backup system
├── ha-backup.timer               # Configurable schedule
├── logging-service.service       # Log management
├── system-diagnostic-startup.service # Boot diagnostics
└── system-diagnostic-startup.timer   # At boot + 2 minutes
```

**Configuration Files:**
```
/etc/
├── telegram-sender/
│   └── config                    # Telegram bot configuration
├── ha-watchdog/
│   └── config                    # Watchdog configuration
└── logging-service/
    └── config                    # Log management configuration
```

**Log Rotation Configs:**
```
/etc/logrotate.d/
├── ha-monitoring                 # All monitoring services
├── telegram-sender               # Telegram service logs
├── homeassistant                 # Home Assistant logs
├── fail2ban                      # Security logs
└── ufw                          # Firewall logs
```

**State & Log Files:**
```
/var/log/
├── ha-watchdog.log              # Health monitoring logs
├── ha-failure-notifier.log      # Alert service logs  
├── ha-failures.log              # Detected failures
├── ha-reboot.log                # Reboot service logs
├── ha-update-checker.log        # Update analysis logs
├── ha-backup.log                # Backup operation logs
└── telegram-sender.log          # Telegram sending logs

/var/lib/ha-failure-notifier/    # State files for smart processing
├── last_timestamp.txt           # Last processed event timestamp
├── smart_throttle_history.txt   # Throttling history
└── metadata.txt                 # File rotation detection
```

**🚀 Service Startup:**
After installation, all services are automatically:
- **Enabled**: Start automatically on boot
- **Started**: Begin monitoring immediately  
- **Configured**: Ready with default settings
- **Logged**: All activities are logged with rotation

**⚙️ Management Commands:**
```bash
# Check installation status
sudo ha-monitoring-control status

# Start all monitoring services
sudo ha-monitoring-control start

# View recent logs
sudo ha-monitoring-control logs

# Test Telegram integration
sudo ha-monitoring-control test-telegram
```

### **3. Configure Telegram Bot**

**Check telegram updates on https://api.telegram.org/bot8185210583:AAG8wijjUfAFHTyP-rzI1WpVyxcJEJQAIXQ/getUpdates**

Create centralized telegram-sender configuration:

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
TELEGRAM_TOPIC_SYSTEM=2             # System messages
TELEGRAM_TOPIC_ERRORS=10            # Errors and failures
TELEGRAM_TOPIC_UPDATES=9            # Updates
TELEGRAM_TOPIC_RESTART=4            # Restarts
TELEGRAM_TOPIC_SYSTEM_DIAGNOSTIC=123  # System diagnostic reports
TELEGRAM_TOPIC_BACKUP=131           # Backup reports

# Performance settings
TELEGRAM_TIMEOUT=10
TELEGRAM_RETRY_COUNT=3
TELEGRAM_RETRY_DELAY=2
EOF
```

### **4. Management Commands**
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
- **Telegram Sender**: `/var/log/telegram-sender.log`

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

### **Common Diagnostics**

```bash
# System health overview
ssh rpi "vcgencmd measure_temp && free -h && df -h"

# Enhanced system monitoring with htop
ssh rpi "htop -d 10 -n 1"

# Full system diagnostics (79 checks)
ssh rpi "sysdiag"

# Quick system check
ssh rpi "syscheck"

# Service status check
ssh rpi "systemctl status ha-watchdog.timer ha-failure-notifier.timer"

# Docker container health
ssh rpi "docker ps && docker stats --no-stream"

# Recent failure events
ssh rpi "tail -20 /var/log/ha-failures.log"

# Network connectivity test
ssh rpi "ping -c 3 8.8.8.8 && curl -s https://www.google.com"
```

### **Debugging Commands**

**Check Tailscale status:**
```bash
tailscale ip -4
tailscale status
```

**Home Assistant status:**
```bash
docker logs -f homeassistant
curl -v http://localhost:8123
```

**Network diagnostics:**
```bash
# Check network connectivity
ping 8.8.8.8
systemctl status networking

# WiFi signal strength  
iwconfig wlan0

# Port availability
ss -tulpn | grep :8123
```

**System performance:**
```bash
# System resources
htop
free -h
df -h

# Temperature monitoring
vcgencmd measure_temp
```

# Temperature monitoring
vcgencmd measure_temp
```

### **Performance Optimizations**

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

## � Monitoring and Diagnostics

### **Key Metrics**
- **CPU temperature** (normal <65°C, critical >70°C)
- **System load** (CPU, RAM, disk)
- **Service availability** (ping, port check)
- **Docker container status**

### **Automatic Recovery**
- **Restart failed containers**
- **Restore WiFi interface**
- **Clean logs when disk fills**
- **Notify about all actions**

## �🖥️ Hardware & OS Configuration

### **Primary Node Configuration**
- **Device**: Raspberry Pi 3B+
- **OS**: Debian 12 (Bookworm) ARM64
- **RAM**: 1GB LPDDR2 SDRAM  
- **IP Address**: 192.168.1.21 (static)
- **Hostname**: rpi3-20250711
- **Storage**: 32GB MicroSD Card (SanDisk Ultra)

### **Network Configuration**
- **Main network**: 192.168.1.0/24
- **IoT subnets**: 192.168.2.x, 192.168.3.x, 192.168.4.x
- **DNS**: 8.8.8.8, 1.1.1.1
- **Ports**:
  - **8123**: Home Assistant Web UI
  - **1880**: Node-RED Flow Editor
  - **22**: SSH Management Port
  - **443/80**: HTTPS/HTTP (Tailscale Funnel)

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

## 📁 Project Structure

```
PRI-HA/
├── 📋 README.md                           # This comprehensive documentation
├── 🐳 docker/                            # Docker infrastructure
│   ├── docker-compose.yml                # Docker stack (HA + Node-RED)
│   └── daemon.json                       # Docker daemon configuration
├── 📁 services/                          # Complete monitoring system
│   ├── install.sh                        # Automated installation script
│   ├── communication/                    # Communication services
│   │   └── telegram-sender/              # Centralized Telegram service v1.0
│   │       ├── telegram-sender.sh        # Main script
│   │       ├── telegram-sender.conf      # Configuration
│   │       └── telegram-sender.logrotate # Log rotation
│   ├── diagnostics/                      # System diagnostics
│   │   ├── system-diagnostic.sh          # 79-check comprehensive diagnostics
│   │   └── system-diagnostic.logrotate   # Log rotation config
│   ├── monitoring/                       # Health monitoring services
│   │   ├── ha-watchdog/                  # 20-point system monitoring (every 2min)
│   │   │   ├── ha-watchdog.sh            # Main monitoring script
│   │   │   ├── ha-watchdog.conf          # Configuration
│   │   │   ├── ha-watchdog.service       # Systemd service
│   │   │   ├── ha-watchdog.timer         # Systemd timer
│   │   │   └── ha-watchdog.logrotate     # Log rotation
│   │   └── ha-failure-notifier/          # Smart alerts & recovery (every 5min)
│   │       ├── ha-failure-notifier.sh    # Notification script
│   │       ├── ha-failure-notifier.service # Systemd service
│   │       ├── ha-failure-notifier.timer # Systemd timer
│   │       └── ha-failure-notifier.logrotate # Log rotation
│   ├── system/                           # System maintenance services
│   │   ├── nightly-reboot/               # Daily maintenance reboot (03:30)
│   │   │   ├── nightly-reboot.sh         # Reboot script
│   │   │   ├── nightly-reboot.service    # Systemd service
│   │   │   ├── nightly-reboot.timer      # Systemd timer
│   │   │   └── nightly-reboot.logrotate  # Log rotation
│   │   ├── update-checker/               # Update analysis (weekdays 09:00)
│   │   │   ├── update-checker.sh         # Update checking script
│   │   │   ├── update-checker.service    # Systemd service
│   │   │   ├── update-checker.timer      # Systemd timer
│   │   │   └── update-checker.logrotate  # Log rotation
│   │   ├── ha-backup/                    # Backup system
│   │   │   ├── ha-backup.sh              # Backup script
│   │   │   ├── ha-restore.sh             # Restore script
│   │   │   ├── ha-backup.service         # Systemd service
│   │   │   ├── ha-backup.timer           # Systemd timer
│   │   │   └── ha-backup.logrotate       # Log rotation
│   │   ├── logging-service/              # Centralized log management
│   │   │   ├── logging-service.sh        # Log management script
│   │   │   ├── logging-service.conf      # Configuration
│   │   │   ├── logging-service.service   # Systemd service
│   │   │   └── logging-service.logrotate # Log rotation
│   │   ├── system-diagnostic-startup/    # Startup diagnostics
│   │   │   ├── system-diagnostic-startup.sh # Startup script
│   │   │   ├── system-diagnostic-startup.service # Systemd service
│   │   │   ├── system-diagnostic-startup.timer # Systemd timer
│   │   │   └── system-diagnostic-startup.logrotate # Log rotation
│   │   └── ha-general-logs.logrotate     # General log rotation config
│   ├── logrotate/                        # System log rotation configs
│   │   ├── homeassistant                 # HA log rotation
│   │   ├── fail2ban                      # Security log rotation  
│   │   ├── ufw                           # Firewall log rotation
│   │   └── journald.conf                 # Systemd journal limits
│   └── tailscale/                        # Tailscale VPN services
│       ├── scripts/                      # Utility scripts
│       │   └── remote-delete-machines    # Machine cleanup script
│       ├── tailscaled/                   # Native daemon service
│       │   ├── tailscaled.service        # Systemd service
│       │   └── tailscaled.default        # Environment config
│       ├── tailscale-serve-ha/           # HTTPS proxy service
│       │   └── tailscale-serve-ha.service # Systemd service
│       └── tailscale-funnel-ha/          # Public HTTPS access
│           └── tailscale-funnel-ha.service # Systemd service
└── 📁 docs/                              # Documentation & architecture
    ├── network-infrastructure.md         # Network topology
    └── images/                           # Network diagrams & photos
        ├── Home plan.jpg                 # House layout
        ├── Home plan - routers.jpg       # Router placement
        └── Home plan - smart devices.JPEG # Device locations
```

## ⚠️ Known Issues

- **Telegram YAML configuration is deprecated** - migrate to UI integration for better reliability
- **SSL error when using Funnel without certificate** - certificate auto-renewal may fail
- **HA Mobile may occasionally lose VPN connectivity** - restart Tailscale service on mobile device
- **Large log files** - ensure logrotate is running properly via `systemctl status logrotate.timer`
- **Memory pressure on Pi 3B+** - monitor swap usage and consider log cleanup if system becomes slow

## 💡 Recommendations and ToDo

### **Security Enhancements**
- 🔐 Enable authentication and role management in Home Assistant
- 🔑 Implement regular SSH key rotation
- 🛡️ Consider enabling two-factor authentication for critical services

### **Integration Expansion**
- 🧩 Configure HomeBridge for Siri integration
- 🌍 Use Tailscale DNS or custom domain via CNAME
- 🧪 Add integrations: Zigbee2MQTT (USB), ESPHome, MQTT broker
- 📡 Expand Telegram notifications (motion, temperature, events)

### **Backup & Maintenance**
- 🔄 Implement automated snapshot scheduling
- 📲 Automate backups to external disk or Google Drive
- 📊 Set up InfluxDB for historical data retention
- 🧹 Configure automated disk cleanup routines

### **Smart Home Automation**
- 🧠 Build structured Node-RED automations:
  - Motion-based lighting control
  - Night mode activation
  - Security deterrence systems
  - Environmental monitoring alerts

---
*Smart Home Monitoring System - Comprehensive health monitoring with intelligent alerting for Raspberry Pi Home Assistant installations.*
