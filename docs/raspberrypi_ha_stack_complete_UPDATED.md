# 🏠 Smart Home Network Architecture

## Recent Updates (September 2025)

### 📢 **telegram-sender v1.0 - Centralized Telegram Service**

**Major Infrastructure Update**: Replaced individual Telegram implementations with unified service across all monitoring components.

**Architecture Benefits:**
- 🎯 **Single Point of Configuration** - All Telegram settings in `/etc/telegram-sender/config`
- 📝 **Centralized Logging** - Unified logs in `/var/log/telegram-sender.log`
- 🔄 **Retry & Error Handling** - Built-in resilience with 3 attempts per message
- 🏗️ **Topic-Based Routing** - Automatic message categorization by service type
- 📊 **Performance Metrics** - Sender tracking and delivery statistics

**Service Integration:**
```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│ ha-watchdog     │───▶│ telegram-sender │───▶│ Telegram Bot    │
│ (monitoring)    │    │ (centralized)   │    │ Topic: ERRORS   │
└─────────────────┘    └─────────────────┘    └─────────────────┘

┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│ update-checker  │───▶│ telegram-sender │───▶│ Telegram Bot    │
│ (updates)       │    │ (centralized)   │    │ Topic: UPDATES  │
└─────────────────┘    └─────────────────┘    └─────────────────┘

┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│ nightly-reboot  │───▶│ telegram-sender │───▶│ Telegram Bot    │
│ (maintenance)   │    │ (centralized)   │    │ Topic: RESTART  │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

**Refactoring Results:**
- ✅ **Eliminated 65+ lines of duplicate code** across monitoring services
- ✅ **Reduced 14 individual curl calls** to single service invocations
- ✅ **Simplified configuration management** - no more token duplication
- ✅ **Enhanced error handling** - centralized retry logic and logging

## Hardware & OS Configuration

### Raspberry Pi 3B+ Setup
- **OS**: Debian 12 (Bookworm), ARM64 architecture
- **Hostname**: rpi3-20250711  
- **SSH Access**: Port 22, key-based authentication
- **Installation**: Manual setup with full root access
- **Memory**: 1GB RAM + 2GB Swap file (/swapfile)
- **Storage**: MicroSD card with regular health monitoring**Key Improvements v3.0:**

#### 🕒 **Timestamp-Based Processing**
```bash
# New state file stores Unix timestamp of last processed event
/var/lib/ha-failure-notifier/last_timestamp.txt
# Example content: 1756276395 (last processed event timestamp)
```

#### 🔄 **Algorithm Change**
- **Before v3.0**: Track file position, reprocess after rotation
- **After v3.0**: Track event timestamp, process only newer events
- **Result**: Eliminates duplicate notifications regardless of file changes

#### 🛡️ **Duplicate Prevention**
- Reads entire log file but processes only events with timestamp > last_processed
- Works with any log rotation, truncation, or file recreation
- Maintains perfect accuracy based on actual event occurrence time

**Preserved v2.0 Features:**
- ✅ **Smart File Rotation Detection** - Tracks metadata (size, creation time, first line hash)
- ✅ **Position-Based Processing** - Processes only NEW failure events (1-5 lines vs 1400+)
- ✅ **Anti-Spam Protection** - Limits to 50 events after rotation
- ✅ **Performance Boost** - Reduced processing time from 60s timeout to <1s execution
- ✅ **State Persistence** - Maintains position across service restartsiguration
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
ha-failure-notifier.timer # Every 5 minutes - Telegram alerts & recovery (improved v2.0)
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
/var/log/ha-reboot.log          # Nightly maintenance reports
/var/log/ha-update-checker.log  # System update analysis
/var/log/ha-services-control.log # Service management operations
/var/log/ha-debug.log           # Debug information
```

### Failure Notifier State Files
```
/var/lib/ha-failure-notifier/
├── last_timestamp.txt        # Unix timestamp of last processed event (v3.0)
├── smart_throttle_history.txt # Smart throttling event history with priorities (v3.1)
├── position.txt              # Legacy: Last processed line number (kept for compatibility)
├── metadata.txt              # File metadata for rotation detection (size:ctime:mtime:hash)
├── throttle.txt              # Legacy: Timestamp tracking for notification throttling
└── hashes.txt                # Legacy hash storage (kept for compatibility)
```

**Smart Throttling (v3.1) State Format:**
```
# smart_throttle_history.txt entries:
timestamp:priority:message_type
1756276395:critical:FATAL_ERROR
1756276401:warning:WARN_PERFORMANCE
1756276405:high:ERROR_CONNECTION
```

### Telegram Integration
**Notification Categories:**
- 🔴 Critical: System failures, high temperature (>75°C)
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
- Custom port (22) - standard port with firewall protection
- Root login via keys
- Password authentication disabled
- Fail2ban protection enabled

### Firewall Protection (UFW)
- **Status**: Active and enabled on system startup
- **Default Policy**: Deny incoming, allow outgoing
- **Allowed Access**:
  - SSH (22): Local network (192.168.1.0/24) + Tailscale VPN (100.64.0.0/10)
  - Home Assistant (8123): Local network + Tailscale VPN only
  - Node-RED (1880): Local network + Tailscale VPN only
- **Blocked**: All internet access to services
- **Configuration**: `/etc/ufw/user.rules`

### Intrusion Detection (Fail2ban)
- **Service**: `fail2ban.service` - active protection
- **SSH Protection**: Monitors `/var/log/auth.log`
- **Policy**: 3 failed attempts = 1 hour IP ban
- **Configuration**: `/etc/fail2ban/jail.local`
- **Status Check**: `fail2ban-client status sshd`
- **Log Rotation**: Daily rotation, 52 weeks retention (`/etc/logrotate.d/fail2ban`)

### UFW Firewall Logs
- **UFW Logs**: `/var/log/ufw.log`
- **Log Rotation**: Daily rotation, 30 days retention (`/etc/logrotate.d/ufw`)

### Container Security  
- Host network mode for HA discovery
- Volume mounts with restricted permissions
- Regular image updates via watchtower
- UFW firewall controls container port access

### Network Security
- UFW firewall rules (active)
- Tailscale VPN-only external access
- Regular security updates monitoring
- Performance testing with stress-ng

### Security Monitoring
- **File Permissions**: Configuration files secured (600)
- **Security Updates**: Monitored via `apt list --upgradable`
- **SSH Attempts**: Tracked by fail2ban and health diagnostics
- **Firewall Status**: Monitored in system health checks

---
*Updated: 2025-08-21 - Smart Home Network Documentation*

## Monitoring System

### System Health Monitoring
- **Scripts Location**: `/opt/ha-monitoring/scripts/`
- **Config**: `/etc/ha-watchdog/config` (legacy), `/etc/telegram-sender/config` (new)
- **Logs**: `/var/log/ha-*.log`, `/var/log/telegram-sender.log`

#### telegram-sender.sh v1.0 (NEW - September 2025)
- **Purpose**: Centralized Telegram notification service with topic support
- **Location**: `/usr/local/bin/telegram-sender.sh`
- **Config**: `/etc/telegram-sender/config`
- **Features**:
  - **Topic-based routing** - automatic message categorization (SYSTEM:2, ERRORS:10, UPDATES:9, RESTART:4)
  - **Retry mechanism** - 3 attempts with 2-second delays
  - **Comprehensive logging** - sender tracking, delivery status, error diagnostics
  - **Performance metrics** - message statistics and delivery confirmation
  - **Security validation** - token verification and message sanitization
  - **Flexible configuration** - timeout, retry count, parse mode customization
- **Usage**: `telegram-sender.sh "message" "topic_id"` or `telegram-sender.sh "message"` (default topic)
- **Integration**: Used by all monitoring services (ha-watchdog, failure-notifier, update-checker, nightly-reboot)

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
- **Purpose**: Process failures and send Telegram notifications with timestamp-based event tracking
- **Service**: `ha-failure-notifier.service` (timer-based)
- **Interval**: Every 5 minutes
- **Version**: 3.1 - Smart Priority-Based Throttling (August 2025)
- **Features**: 
  - **Smart throttling** - priority-based event quotas (Critical:20, High:10, Warning:5, Info:3 per 30min)
  - **Timestamp tracking** - processes only events newer than last processed timestamp
  - **Event classification** - automatic priority detection (FATAL/ERROR/WARN/INFO)
  - **Rotation independence** - works regardless of log file changes/rotation
  - **Duplicate prevention** - eliminates cascading notifications after log rotation
  - **Rolling window** - 30-minute sliding window with automatic cleanup
  - **Dual throttling system** - smart priority-based + legacy time-based for compatibility
  - **Automatic container restart** for failed services
  - **State persistence** - maintains timestamp and throttling state across restarts
- **Notifications**: Critical/Warning/Info with emojis and hostname
- **File Tracking**: Uses `/var/lib/ha-failure-notifier/` for last_timestamp.txt, smart_throttle_history.txt, position.txt, metadata.txt, throttle.txt

#### ha-system-health-check.sh v1.0
- **Purpose**: Comprehensive system diagnostics and health reporting
- **Location**: `/usr/local/bin/ha-system-health-check.sh`
- **Quick Commands**: `health-check`, `health-quick`, `health-monitor`
- **Features**:
  - **79 comprehensive checks** (upgraded from 37) across all system components
  - **Color-coded output** - ✓ PASS (green), ✗ FAIL (red), ⚠ WARN (yellow)
  - **Statistical reporting** - percentage scores and health assessment
  - **Port checking** - uses bash `/dev/tcp` (no external dependencies)
  - **Performance testing** - stress-ng integration for CPU/memory tests
  - **Detailed reports** saved to `/tmp/ha-health-report-YYYYMMDD-HHMMSS.txt`
- **Enhanced Check Categories**:
  - **Basic System Info** (6 checks): Hostname, uptime, kernel, OS, architecture, CPU model
  - **System Resources** (8 checks): Memory (detailed), disk space, CPU load, temperature (75°C threshold)
  - **Extended Network** (11 checks): Internet, gateway, DNS, interfaces, WiFi/Ethernet status, IP addresses
  - **Docker Services** (12+ checks): Daemon, version, info, containers, compose configuration
  - **Tailscale VPN** (8+ checks): Daemon status, connection, node info, peers, HA accessibility (via `tailscale serve status`)
  - **HA Monitoring** (12+ checks): Systemd timers (not services!), scripts, configuration validation
  - **Log Analysis** (6+ checks): File sizes, recent entries, state files, rotation status
  - **Service Availability** (4+ checks): Port checks for HA, Node-RED, Portainer, Zigbee2MQTT
  - **Recent Failures** (4+ checks): Failure logs, notification stats, throttling status
  - **Enhanced Security** (8+ checks): SSH config, UFW firewall, fail2ban, file permissions, security updates
  - **Performance Testing** (2+ checks): Stress-ng memory test, disk write speed validation
  - **Performance Testing** (2+ checks): Disk write speed, memory stress test (stress-ng)
- **Latest Performance**: 66/79 checks passed (83%), 12 warnings, 1 error
- **Check Categories**:
  - System Resources: memory, disk, CPU load, temperature
  - Network: internet, gateway, DNS, interface status  
  - Docker: daemon, containers, compose files
  - HA Services: watchdog, notifier, timers, scripts
  - Service Ports: HA (8123), Node-RED (1880), Portainer (9000), Zigbee2MQTT (8080)
  - Log Analysis: file sizes, recent entries, state files
  - Security: SSH, firewall, updates, fail2ban
  - Performance: disk speed, memory stress tests
- **Remote Access Examples**:
  ```bash
  ssh rpi-vpn health-check         # Full diagnostics
  ssh rpi-vpn health-quick         # Essential checks only
  ssh rpi-vpn health-monitor       # Continuous monitoring
  ssh rpi-vpn "health-check --help" # Command options
  ```
- **Smart Health Assessment**: Automatically categorizes system status from "excellent" to "requires intervention"

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

## 3. systemd services

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
# Goal: HTTPS proxy for HA via port 8443
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
# Goal: Public HTTPS access from the Internet
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

## 4. Home Assistant Configuration

### configuration.yaml (core)

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

### Configuration extensions:

- Telegram is configured via Node-RED with an API token
- In the future you can connect `telegram:` directly via UI integrations
- Google Translate is used for TTS:

```yaml
tts:
  - platform: google_translate
    service_name: google_say
```

## 5. Integrations and Devices

- ✅ HACS (installed manually)
- ✅ Sonoff (eWeLink) — 48 devices via LAN/Cloud
- ✅ Broadlink — functional (IR/RF transmitter)
- ✅ Roomba — auto discovered
- ✅ Weather, Sun, TTS, Backup
- ⏳ HomeBridge — planned for Siri integration

## 6. Node-RED

- Connected to HA via WebSocket with long-lived token
- Installed palettes:
 - `node-red`
 - `node-red-contrib-home-assistant-websocket`
 - `node-red-contrib-influxdb`
 - `node-red-contrib-moment`
 - `node-red-contrib-time-range-switch`
 - `node-red-dashboard`
 - `node-red-node-email`
 - `node-red-node-telegrambot`
 - `node-red-node-ui-table`

### Example Flow:

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

## 7. Network and Access

- Main network: `192.168.1.0/24`
- IoT subnets: `192.168.2.x`, `192.168.3.x`, `192.168.4.x`
- Access methods:
  - Port forwarding on routers
  - Node-RED as proxy
  - Plan: static routes

## 8. Debugging and Monitoring

- Check Tailscale IP:
  ```bash
  tailscale ip -4
  ```
- Home Assistant status:
  ```bash
  docker logs -f homeassistant
  ```
- Check HA availability:
  ```bash
  curl -v http://localhost:8123
  ```

## 9. Known Issues

- ⚠️ Telegram YAML configuration is deprecated (migrate to UI integration)
- ⚠️ SSL error when using Funnel without certificate
- ⚠️ HA Mobile may occasionally lose VPN connectivity

## Recent Updates (August 2025)

### ha-failure-notifier.sh v3.1 - Smart Priority-Based Throttling

**New Enhancement:** Added intelligent event throttling system with priority-based quotas to prevent notification overload while ensuring critical alerts always get through.

**Smart Throttling Features:**

#### 🎯 **Priority-Based Event Quotas**
```bash
# Event type priority mapping and limits per 30-minute window:
CRITICAL (FATAL/ERROR):  20 events max  # Most important alerts
HIGH (ERROR patterns):   10 events max  # Important failures  
WARNING (WARN):          5 events max   # Moderate issues
INFO (INFO/DEBUG):       3 events max   # Low priority status
```

#### 🧠 **Automatic Event Classification**
- **CRITICAL**: FATAL, ERROR, connection failures, service crashes
- **HIGH**: Authentication errors, database issues, critical timeouts
- **WARNING**: WARN level events, performance degradation
- **INFO**: INFO, DEBUG, routine status messages

#### ⏰ **Rolling Window System**
- **30-minute sliding window** with automatic cleanup
- **Dual throttling**: Smart priority-based + legacy time-based
- **State persistence**: Survives service restarts and system reboots

#### 📁 **New State Files**
```bash
/var/lib/ha-failure-notifier/smart_throttle_history.txt
# Format: timestamp:priority:count
# Example: 1756276395:critical:3
```

### ha-failure-notifier.sh v3.0 - Timestamp-Based Event Processing

**Problem Solved:** Version 2.0 caused cascades of identical Telegram notifications after log rotation because the notifier would reprocess all events from the beginning of the new log file.

**Solution:** Redesigned to use **timestamp-based tracking** instead of file position tracking.

**Key Improvements:**

#### � **Timestamp-Based Processing**
```bash
# New state file stores Unix timestamp of last processed event
/var/lib/ha-failure-notifier/last_timestamp.txt
# Example content: 1756276395 (last processed event timestamp)
```

#### � **Algorithm Change**
- **Before v3.0**: Track file position, reprocess after rotation
- **After v3.0**: Track event timestamp, process only newer events
- **Result**: Eliminates duplicate notifications regardless of file changes

#### �️ **Duplicate Prevention**
- Reads entire log file but processes only events with timestamp > last_processed
- Works with any log rotation, truncation, or file recreation
- Maintains perfect accuracy based on actual event occurrence time

**Files Updated:**
- `last_timestamp.txt` - NEW: Unix timestamp tracking
- `position.txt` - Kept for backward compatibility  
- `metadata.txt` - Enhanced rotation detection
- `throttle.txt` - Smart notification throttling

## 10. Recommendations and ToDo

- 🔐 Enable authentication and role management in HA
- 🧩 Configure HomeBridge for Siri integration
- 📡 Expand Telegram notifications (motion, temperature, events)
- 🌍 Use Tailscale DNS or domain via CNAME
- 🧪 Add integrations: Zigbee2MQTT (USB), ESPHome, MQTT broker
- 🔄 Implement snapshot scheduling
- 📲 Automate backups to external disk or Google Drive
- 🧠 Build structured Node-RED automations: notifications, night mode, deterrence, etc.

---

## 📦 Watchdog and Notification System

### `ha-watchdog.sh`

The script monitors:

- Home Assistant availability (`http://localhost:8123`)
- Docker container health
- System load (`uptime`)
- Internet connectivity (`ping 8.8.8.8`)

Logs:
- `/var/log/ha-watchdog.log` — run history and load metrics
- `/var/log/ha-failures.log` — detected issues list

Single-run control handled via `/tmp/ha-watchdog-state.txt`.

### `ha-watchdog.service`

Systemd unit to launch the watchdog on boot with restart:

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

### 🧹 Logrotate for Logs

**Automatic setup:** Logrotate is configured automatically via `install.sh`

**Installed configurations:**

- `/etc/logrotate.d/ha-monitoring` - monitoring system logs
- `/etc/logrotate.d/homeassistant` - Home Assistant logs
- `/etc/logrotate.d/fail2ban` - Fail2ban logs (52 weeks retention)  
- `/etc/logrotate.d/ufw` - UFW Firewall logs (30 days retention)
- `/etc/systemd/journald.conf` - systemd journal limits (500MB)

**SSH Logs Note:** SSH uses systemd journald so no separate logrotate config is needed.

**Rotation parameters:**

```bash
# High-frequency logs (every 2-5 minutes)
/var/log/ha-watchdog.log, /var/log/ha-failure-notifier.log
├─ Size: 5MB → rotate  
├─ Archive: 10 files (50MB total limit)
├─ Frequency: daily
└─ Compression: enabled

# Medium-frequency logs  
/var/log/ha-failures.log, /var/log/ha-reboot.log
├─ Size: 10MB → rotate
├─ Archive: 5 files  
└─ Frequency: weekly

# Home Assistant
/srv/homeassistant/home-assistant.log
├─ Size: 50MB → rotate
├─ Archive: 7 files
├─ Method: copytruncate (safe for HA)
└─ Frequency: daily
```

**Management via ha-monitoring-control:**

```bash
ha-monitoring-control log-sizes      # show sizes of all logs
ha-monitoring-control rotate-logs    # force rotation  
ha-monitoring-control clean-journal  # clean systemd journal
```

**Automatic rotation - systemd timer:**

```bash
# Check logrotate status
systemctl status logrotate.timer
● logrotate.timer - Daily rotation of log files
  Active: active (waiting)
  Trigger: daily at 00:00 UTC (midnight)
  
# Next run
systemctl list-timers logrotate.timer
```

- **Schedule**: Daily at 00:00 via systemd timer
- **Method**: `logrotate.timer` → `logrotate.service` (modern cron alternative)
- **Settings**: `/lib/systemd/system/logrotate.timer` (OnCalendar=daily)
- **Autostart**: enabled at system boot

---

### 🔔 `ha-alert.sh`

This script runs separately and scans `ha-failures.log` to:

- identify new issues
- send a message to Telegram (or other system)
- maintain a record of sent alerts (`/var/log/ha-alerted-ids.txt`)

Example:

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

Create a systemd timer or cron job for periodic execution.

---

## 🛠️ System Configuration

### Swap Configuration
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

### Service Management
```bash
# Install and manage monitoring services
cd /path/to/project
cp services/ha-monitoring-services-control.sh /usr/local/bin/
chmod +x /usr/local/bin/ha-monitoring-services-control.sh

# Usage
ha-monitoring-services-control.sh full    # Full setup
ha-monitoring-services-control.sh restart # Restart services
ha-monitoring-services-control.sh status  # Check status
```

## 🔑 SSH Access Keys

Public key (example placeholder - replace with your own):
```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHNKOdVcE9EhXsjGimG00N86zo+ocaIzCx+0/KFTMiZU neoselcev@LenovoP14sgen2-Slava
```
Private key:
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

## 🔗 Quick SSH Connections

### ~/.ssh/config Setup

For convenience add to `~/.ssh/config`:

```bash
# Raspberry Pi Home Assistant (Local network)
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

### Create SSH Key

```bash
# Generate private key (already shown above)
# Set correct permissions
chmod 600 ~/.ssh/raspberry_pi_key
```

### Usage

```bash
# Local network
ssh rpi

# VPN connection (global access)
ssh rpi-vpn

# File copy
scp ./monitoring/install.sh rpi:/tmp/
scp -r ./monitoring/ rpi:/srv/home/

# Execute commands
ssh rpi "docker ps"
ssh rpi-vpn "systemctl status ha-watchdog"
```

---