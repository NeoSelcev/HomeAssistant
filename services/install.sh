#!/bin/bash

# Installation script for the enhanced HA monitoring system
# For Raspberry Pi 3B+ with Debian

set -e

echo "🚀 Installing enhanced Home Assistant monitoring system..."

# Check root privileges
if [[ $EUID -ne 0 ]]; then
    echo "❌ This script must be run as root"
   exit 1
fi

# Check Docker installation
echo "🐳 Checking Docker..."
if ! command -v docker >/dev/null 2>&1; then
    echo "📦 Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    usermod -aG docker $SUDO_USER 2>/dev/null || true
else
    echo "✅ Docker already installed"
fi

# Ensure diagnostic aliases (idempotent)
USER_HOME="/home/${SUDO_USER:-pi}"
if [[ -d "$USER_HOME" ]]; then
    if ! grep -q 'ha-system-health-check.sh' "$USER_HOME/.bashrc" 2>/dev/null; then
        echo "📋 Adding diagnostic aliases to user shell profile..."
        cat >> "$USER_HOME/.bashrc" << 'EOF'

# Diagnostic aliases for HA monitoring
alias health-check="ha-system-health-check.sh"
alias health-quick="ha-system-health-check.sh --quick"
alias health-monitor="ha-system-health-check.sh --monitor"
alias diagnostic="ha-monitoring-control diagnostic"
EOF
        chown ${SUDO_USER:-pi}:${SUDO_USER:-pi} "$USER_HOME/.bashrc"
        echo "✅ Diagnostic aliases added"
    fi
else
    echo "⚠️ User home directory not found, diagnostic aliases not added"
fi

# Check Docker Compose installation
if ! command -v docker-compose >/dev/null 2>&1; then
    echo "📦 Installing Docker Compose..."
    apt update
    apt install -y docker-compose
    echo "✅ Docker Compose installed"
else
    echo "✅ Docker Compose already installed"
fi

# Configure Docker logging limits
echo "📝 Configuring Docker logging limits..."
DAEMON_JSON="/etc/docker/daemon.json"

# Create backup of existing config
if [[ -f "$DAEMON_JSON" ]]; then
    cp "$DAEMON_JSON" "$DAEMON_JSON.backup.$(date +%Y%m%d_%H%M%S)"
    echo "💾 Backup created"
fi

# Create new configuration
cat > "$DAEMON_JSON" << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "7"
  }
}
EOF

echo "✅ Docker logging configuration applied"
echo "   └─ Limit: 10MB × 7 files = 70MB per container"

# Create Home Assistant directory and docker-compose
echo "🏠 Setting up Home Assistant..."
HA_DIR="/opt/homeassistant"
mkdir -p "$HA_DIR"

# Copy docker-compose.yml if present in project
if [[ -f "docker-compose.yml" ]]; then
    cp docker-compose.yml "$HA_DIR/"
    echo "✅ docker-compose.yml copied to $HA_DIR"
else
    # Create base docker-compose.yml
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
    echo "✅ Base docker-compose.yml created"
fi

# Create required directories
echo "📁 Creating directories..."
mkdir -p /etc/ha-watchdog
mkdir -p /var/lib/ha-responder
mkdir -p /usr/local/bin
mkdir -p "$HA_DIR/homeassistant"
mkdir -p "$HA_DIR/nodered"

# Install dependencies
echo "📦 Installing dependencies..."
apt update
apt install -y bc curl jq wireless-tools dos2unix htop

# Install security components
echo "🛡️ Installing security components..."
apt install -y ufw fail2ban stress-ng

echo "🔥 Configuring UFW Firewall..."
# UFW setup
ufw --force reset >/dev/null 2>&1 || true
ufw default deny incoming
ufw default allow outgoing

# Allow access only for local network and Tailscale
ufw allow from 192.168.1.0/24 to any port 22 comment 'SSH - Local Network'
ufw allow from 100.64.0.0/10 to any port 22 comment 'SSH - Tailscale VPN'
ufw allow from 192.168.1.0/24 to any port 8123 comment 'Home Assistant - Local Network'
ufw allow from 100.64.0.0/10 to any port 8123 comment 'Home Assistant - Tailscale VPN'
ufw allow from 192.168.1.0/24 to any port 1880 comment 'Node-RED - Local Network'
ufw allow from 100.64.0.0/10 to any port 1880 comment 'Node-RED - Tailscale VPN'

# Enable firewall
ufw --force enable
echo "✅ UFW Firewall configured and enabled"

echo "🚫 Configuring Fail2ban..."
# Fail2ban setup
cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true
filter = sshd
backend = systemd
maxretry = 3
bantime = 3600
EOF

systemctl enable fail2ban
systemctl restart fail2ban
echo "✅ Fail2ban configured and active"

# Audit/watch SSH
-w /var/log/auth.log -p wa -k auth
-w /etc/ssh/sshd_config -p wa -k ssh

# Audit/watch Home Assistant
-w /opt/homeassistant -p wa -k homeassistant
-w /etc/systemd/system/homeassistant.service -p wa -k homeassistant

# Audit/watch firewall
-w /etc/ufw -p wa -k firewall
EOF

echo "📋 Configuring Logrotate for security system..."
# Copy logrotate configs
cp "${SCRIPT_DIR}/logrotate/fail2ban" /etc/logrotate.d/
cp "${SCRIPT_DIR}/logrotate/ufw" /etc/logrotate.d/
echo "✅ Logrotate set for fail2ban and ufw"

# Copy scripts (updated architecture with centralized logging)
echo "📋 Installing scripts..."
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# Monitoring (with new logging architecture)
cp "${SCRIPT_DIR}/monitoring/ha-watchdog/ha-watchdog.sh" /usr/local/bin/ha-watchdog.sh
cp "${SCRIPT_DIR}/monitoring/ha-failure-notifier/ha-failure-notifier.sh" /usr/local/bin/ha-failure-notifier.sh

# System services (integrated with logging-service)
cp "${SCRIPT_DIR}/system/nightly-reboot/nightly-reboot.sh" /usr/local/bin/nightly-reboot.sh
cp "${SCRIPT_DIR}/system/update-checker/update-checker.sh" /usr/local/bin/update-checker.sh

# Communication (centralized Telegram)
cp "${SCRIPT_DIR}/communication/telegram-sender/telegram-sender.sh" /usr/local/bin/telegram-sender.sh

# CENTRAL LOGGING SERVICE (core of new architecture)
cp "${SCRIPT_DIR}/system/logging-service/logging-service.sh" /usr/local/bin/logging-service.sh

# Diagnostics
cp "${SCRIPT_DIR}/diagnostics/system-diagnostic.sh" /usr/local/bin/system-diagnostic.sh

# Set execute permissions
chmod +x /usr/local/bin/ha-watchdog.sh
chmod +x /usr/local/bin/ha-failure-notifier.sh
chmod +x /usr/local/bin/nightly-reboot.sh
chmod +x /usr/local/bin/update-checker.sh
chmod +x /usr/local/bin/telegram-sender.sh
chmod +x /usr/local/bin/logging-service.sh
chmod +x /usr/local/bin/system-diagnostic.sh

echo "✅ Scripts installed with new centralized logging architecture"

# Configure settings for new architecture
echo "📢 Configuring centralized services..."

# Telegram Sender Service
mkdir -p /etc/telegram-sender
if [[ ! -f /etc/telegram-sender/config ]]; then
    cp "${SCRIPT_DIR}/communication/telegram-sender/telegram-sender.conf" /etc/telegram-sender/config
    chmod 600 /etc/telegram-sender/config
    echo "⚙️ telegram-sender configuration copied to /etc/telegram-sender/config"
    echo "📝 IMPORTANT: Configure Telegram tokens in /etc/telegram-sender/config"
fi

# Centralized Logging Service
mkdir -p /etc/logging-service
if [[ ! -f /etc/logging-service/config ]]; then
    cp "${SCRIPT_DIR}/system/logging-service/logging-service.conf" /etc/logging-service/config
    chmod 644 /etc/logging-service/config
    echo "⚙️ logging-service configuration copied to /etc/logging-service/config"
fi

# Create log files for new architecture
echo "📁 Creating log structure..."
touch /var/log/telegram-sender.log
touch /var/log/logging-service.log
touch /var/log/ha-watchdog.log
touch /var/log/ha-failures.log
touch /var/log/ha-failure-notifier.log
touch /var/log/nightly-reboot.log
touch /var/log/update-checker.log

chmod 644 /var/log/telegram-sender.log
chmod 644 /var/log/logging-service.log
chmod 644 /var/log/ha-watchdog.log
chmod 644 /var/log/ha-failures.log
chmod 644 /var/log/ha-failure-notifier.log
chmod 644 /var/log/nightly-reboot.log
chmod 644 /var/log/update-checker.log

# Logrotate for new services
echo "🔄 Configuring logrotate for centralized architecture..."
cp "${SCRIPT_DIR}/communication/telegram-sender/telegram-sender.logrotate" /etc/logrotate.d/telegram-sender
cp "${SCRIPT_DIR}/system/logging-service/logging-service.logrotate" /etc/logrotate.d/logging-service
cp "${SCRIPT_DIR}/system/ha-general-logs.logrotate" /etc/logrotate.d/ha-general-logs

echo "✅ Centralized services configured"

# Copy ha-watchdog configuration (legacy, without Telegram tokens)
# Now ha-watchdog uses only logging-service for all logs
if [[ ! -f /etc/ha-watchdog/config ]]; then
    cp "${SCRIPT_DIR}/monitoring/ha-watchdog/ha-watchdog.conf" /etc/ha-watchdog/config
    echo "⚙️ ha-watchdog configuration copied (without Telegram tokens)"
    echo "📝 Telegram settings now in /etc/telegram-sender/config"
    echo "📝 All logs now via /usr/local/bin/logging-service.sh"
fi

# Restart Docker to apply logging settings
echo "🔄 Restarting Docker to apply settings..."
systemctl restart docker
sleep 5

# Start Home Assistant containers
echo "🏠 Starting Home Assistant containers..."
cd "$HA_DIR"
docker-compose up -d
echo "✅ Home Assistant containers started"

# Create systemd services
echo "🔧 Creating systemd services..."

# Copy systemd files for monitoring services
cp monitoring/ha-watchdog/ha-watchdog.service /etc/systemd/system/
cp monitoring/ha-watchdog/ha-watchdog.timer /etc/systemd/system/
cp monitoring/ha-failure-notifier/ha-failure-notifier.service /etc/systemd/system/
cp monitoring/ha-failure-notifier/ha-failure-notifier.timer /etc/systemd/system/

# Copy systemd files for system services
cp "${SCRIPT_DIR}/system/nightly-reboot/nightly-reboot.service" /etc/systemd/system/
cp "${SCRIPT_DIR}/system/nightly-reboot/nightly-reboot.timer" /etc/systemd/system/
cp "${SCRIPT_DIR}/system/update-checker/update-checker.service" /etc/systemd/system/
cp "${SCRIPT_DIR}/system/update-checker/update-checker.timer" /etc/systemd/system/

# Extended logrotate setup
echo "📝 Setting up extended logrotate..."

# Backup existing logrotate configurations
mkdir -p /backup/logrotate-$(date +%Y%m%d)
cp -r /etc/logrotate.d/* /backup/logrotate-$(date +%Y%m%d)/ 2>/dev/null || true

# Install configuration for HA monitoring logs
cp logrotate/ha-monitoring /etc/logrotate.d/
chmod 644 /etc/logrotate.d/ha-monitoring

# Install configuration for Home Assistant logs
cp logrotate/homeassistant /etc/logrotate.d/
chmod 644 /etc/logrotate.d/homeassistant

# Configure systemd journal limits (current size may be >1GB)
echo "📊 Configuring systemd journal limits..."
cp /etc/systemd/journald.conf /etc/systemd/journald.conf.backup-$(date +%Y%m%d)
cp logrotate/journald.conf /etc/systemd/journald.conf

# Restart journald to apply settings
systemctl restart systemd-journald

# Clean large journals
echo "🧹 Cleaning systemd journals..."
JOURNAL_SIZE_BEFORE=$(du -sh /var/log/journal 2>/dev/null | cut -f1 || echo "0")
echo "   Size before cleanup: $JOURNAL_SIZE_BEFORE"
journalctl --vacuum-size=500M
JOURNAL_SIZE_AFTER=$(du -sh /var/log/journal 2>/dev/null | cut -f1 || echo "0")
echo "   Size after cleanup: $JOURNAL_SIZE_AFTER"

# Force rotate large log files
echo "🔄 Forcing rotation of large logs..."
if [ -f /var/log/ha-failure-notifier.log ]; then
    NOTIFIER_SIZE=$(stat -c%s /var/log/ha-failure-notifier.log 2>/dev/null || echo "0")
    if [ "$NOTIFIER_SIZE" -gt 5242880 ]; then  # 5MB
    echo "   Rotating ha-failure-notifier.log ($(($NOTIFIER_SIZE / 1024 / 1024))MB)"
        logrotate -f /etc/logrotate.d/ha-monitoring
    fi
fi

# Test logrotate configuration
echo "✅ Testing logrotate configuration..."
logrotate -d /etc/logrotate.d/ha-monitoring >/dev/null 2>&1 && echo "   ✅ HA monitoring: OK" || echo "   ❌ HA monitoring: ERROR"
logrotate -d /etc/logrotate.d/homeassistant >/dev/null 2>&1 && echo "   ✅ Home Assistant: OK" || echo "   ❌ Home Assistant: ERROR"

# Install daily cron for logrotate (if not present)
if ! crontab -l 2>/dev/null | grep -q logrotate; then
    echo "⏰ Adding logrotate to cron..."
    (crontab -l 2>/dev/null; echo "0 2 * * * /usr/sbin/logrotate /etc/logrotate.conf") | crontab -
    echo "   ✅ Logrotate will run daily at 02:00"
fi

# Reload systemd and enable services
echo "🔄 Configuring systemd..."
systemctl daemon-reload
systemctl enable ha-watchdog.timer
systemctl enable ha-failure-notifier.timer
systemctl enable nightly-reboot.timer

read -p "Install daily update check? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Create systemd files for update-checker if not already copied
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
    echo "✅ Update checker installed"
fi

read -p "Install and configure Tailscale VPN? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🔧 Installing Tailscale..."
    
    # Install Tailscale
    if ! command -v tailscale >/dev/null 2>&1; then
        curl -fsSL https://tailscale.com/install.sh | sh
    fi
    
    # Stop services
    systemctl stop tailscaled tailscale-serve-ha tailscale-funnel-ha 2>/dev/null || true
    
    # Copy configuration and services
    cp tailscale/tailscaled/tailscaled.service /etc/systemd/system/
    cp tailscale/tailscale-serve-ha/tailscale-serve-ha.service /etc/systemd/system/
    cp tailscale/tailscale-funnel-ha/tailscale-funnel-ha.service /etc/systemd/system/
    
    if [[ -f tailscale/tailscaled/tailscaled.default ]]; then
        cp tailscale/tailscaled/tailscaled.default /etc/default/tailscaled
    fi
    
    # Activate services
    systemctl daemon-reload
    systemctl enable --now tailscaled tailscale-serve-ha tailscale-funnel-ha
    
    echo "✅ Tailscale installed"
    echo "🔑 For authorization run: tailscale up --hostname=rpi3-$(date +%Y%m%d)"
fi

# Create management control script
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
    echo "✅ All services started"
        ;;
    stop)
        systemctl stop ha-watchdog.timer
        systemctl stop ha-failure-notifier.timer
        systemctl stop nightly-reboot.timer
        [[ -f /etc/systemd/system/update-checker.timer ]] && systemctl stop update-checker.timer
        [[ -f /etc/systemd/system/tailscaled.service ]] && systemctl stop tailscaled
        [[ -f /etc/systemd/system/tailscale-serve-ha.service ]] && systemctl stop tailscale-serve-ha
        [[ -f /etc/systemd/system/tailscale-funnel-ha.service ]] && systemctl stop tailscale-funnel-ha
    echo "⏹️ All services stopped"
        ;;
    restart)
        systemctl restart ha-watchdog.timer
        systemctl restart ha-failure-notifier.timer
        systemctl restart nightly-reboot.timer
        [[ -f /etc/systemd/system/update-checker.timer ]] && systemctl restart update-checker.timer
        [[ -f /etc/systemd/system/tailscaled.service ]] && systemctl restart tailscaled
        [[ -f /etc/systemd/system/tailscale-serve-ha.service ]] && systemctl restart tailscale-serve-ha
        [[ -f /etc/systemd/system/tailscale-funnel-ha.service ]] && systemctl restart tailscale-funnel-ha
    echo "🔄 All services restarted"
        ;;
    status)
    echo "📊 Services status:"
    echo "--- Monitoring ---"
        systemctl status ha-watchdog.timer --no-pager -l
        systemctl status ha-failure-notifier.timer --no-pager -l
    echo "--- System ---"
        systemctl status nightly-reboot.timer --no-pager -l
        [[ -f /etc/systemd/system/update-checker.timer ]] && systemctl status update-checker.timer --no-pager -l
    echo "--- Tailscale ---"
        [[ -f /etc/systemd/system/tailscaled.service ]] && systemctl status tailscaled --no-pager -l
        [[ -f /etc/systemd/system/tailscale-serve-ha.service ]] && systemctl status tailscale-serve-ha --no-pager -l
        [[ -f /etc/systemd/system/tailscale-funnel-ha.service ]] && systemctl status tailscale-funnel-ha --no-pager -l
        ;;
    logs)
    echo "📋 Watchdog logs:"
    tail -20 /var/log/ha-watchdog.log 2>/dev/null || echo "Log file not found"
        echo ""
    echo "📋 Failure notifier logs:"
    tail -20 /var/log/ha-failure-notifier.log 2>/dev/null || echo "Log file not found"
        echo ""
    echo "📋 Failure events logs:"
    tail -20 /var/log/ha-failures.log 2>/dev/null || echo "Log file not found"
        echo ""
    echo "📋 Reboot logs:"
    tail -10 /var/log/ha-reboot.log 2>/dev/null || echo "Log file not found"
        ;;
    log-sizes)
    echo "📊 Log sizes:"
    echo "--- HA monitoring logs ---"
    du -sh /var/log/ha-*.log 2>/dev/null | sort -hr || echo "Logs not found"
    echo "--- Home Assistant logs ---"
    du -sh /srv/homeassistant/*.log 2>/dev/null || echo "Logs not found"
    echo "--- Systemd journal ---"
    journalctl --disk-usage 2>/dev/null || echo "Journal unavailable"
        ;;
    rotate-logs)
    echo "🔄 Forcing log rotation..."
        logrotate -f /etc/logrotate.d/ha-monitoring
        logrotate -f /etc/logrotate.d/homeassistant
    echo "✅ Rotation completed"
        ;;
    clean-journal)
    echo "🧹 Cleaning systemd journal..."
    BEFORE=$(journalctl --disk-usage 2>/dev/null | grep -o '[0-9.]*[KMGT]' || echo "unknown")
        journalctl --vacuum-size=500M
    AFTER=$(journalctl --disk-usage 2>/dev/null | grep -o '[0-9.]*[KMGT]' || echo "unknown")
    echo "Size before: $BEFORE, after: $AFTER"
        ;;
    test-telegram)
    echo "🧪 Testing Telegram via centralized service..."
        
    # Verify new centralized telegram-sender
        if [[ -x "/usr/local/bin/telegram-sender.sh" ]] && [[ -f "/etc/telegram-sender/config" ]]; then
            echo "📢 Using new telegram-sender service..."
            
            # Test sending to different topics
            echo "📝 Sending test messages to topics..."
            
            /usr/local/bin/telegram-sender.sh "🧪 TEST: System message from [$(hostname)]" "2" && \
                echo "  ✅ SYSTEM topic (ID: 2) - sent" || \
                echo "  ❌ SYSTEM topic (ID: 2) - error"
                
            sleep 1
            
            /usr/local/bin/telegram-sender.sh "🚨 TEST: Error message from [$(hostname)]" "10" && \
                echo "  ✅ ERRORS topic (ID: 10) - sent" || \
                echo "  ❌ ERRORS topic (ID: 10) - error"
                
            echo "📊 Check logs: tail -10 /var/log/telegram-sender.log"
            
    # Fallback to legacy method from ha-watchdog config
        elif [[ -f "/etc/ha-watchdog/config" ]]; then
            echo "⚠️ Using legacy method from ha-watchdog config..."
            source /etc/ha-watchdog/config
            if [[ -n "$TELEGRAM_BOT_TOKEN" ]] && [[ -n "$TELEGRAM_CHAT_ID" ]]; then
                curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
                    -d "chat_id=$TELEGRAM_CHAT_ID" \
                    -d "text=🧪 Legacy test from [$(hostname)] - ha-watchdog config" && \
                echo "✅ Legacy test: message sent" || \
                echo "❌ Legacy test: send error"
            else
                echo "❌ Telegram tokens not configured in /etc/ha-watchdog/config"
            fi
        else
            echo "❌ Telegram configuration not found!"
            echo "📝 Configure /etc/telegram-sender/config or /etc/ha-watchdog/config"
        fi
        ;;
    tailscale-status)
        if command -v tailscale >/dev/null 2>&1; then
            echo "🔗 Tailscale status:"
            tailscale status
        else
            echo "❌ Tailscale not installed"
        fi
        ;;
    diagnostic)
        if [[ -f /usr/local/bin/system-diagnostic.sh ]]; then
            /usr/local/bin/system-diagnostic.sh
        else
            echo "❌ Diagnostic script not found"
        fi
        ;;
    *)
    echo "Usage: $0 {start|stop|restart|status|logs|log-sizes|rotate-logs|clean-journal|test-telegram|tailscale-status|diagnostic}"
        echo ""
    echo "Log management commands:"
    echo "  log-sizes     - show sizes of all logs"
    echo "  rotate-logs   - force log rotation"
    echo "  clean-journal - vacuum systemd journal to 500MB"
        exit 1
        ;;
esac
EOF

chmod +x /usr/local/bin/ha-monitoring-control

# Install diagnostic script
echo "🔍 Installing diagnostic script..."
cp system-diagnostic.sh /usr/local/bin/system-diagnostic.sh
chmod +x /usr/local/bin/system-diagnostic.sh

echo ""
echo "✅ Installation completed!"
echo ""
echo "🐳 Docker state:"
echo "   ├─ Docker Engine: Configured with log limits (10MB×7)"
echo "   ├─ Home Assistant: Running on port 8123"
echo "   └─ Node-RED: Running on port 1880"
echo ""
echo "📝 Next steps:"
echo "1. Edit /etc/ha-watchdog/config"
echo "2. Add Telegram bot tokens"
echo "3. Start monitoring: ha-monitoring-control start"
echo "4. Check status: ha-monitoring-control status"
echo "5. Test Telegram: ha-monitoring-control test-telegram"
echo ""
echo "🔧 Management commands:"
echo "   ha-monitoring-control {start|stop|restart|status|logs|test-telegram|tailscale-status|diagnostic}"
echo "   ha-monitoring-control {log-sizes|rotate-logs|clean-journal} - log management"
echo ""
echo "🐳 Docker commands:"
echo "   cd /opt/homeassistant && docker-compose ps     - containers status"
echo "   cd /opt/homeassistant && docker-compose logs   - containers logs"
echo "   cd /opt/homeassistant && docker-compose restart - restart containers"
echo ""
echo "🔍 System diagnostics:"
echo "   system-diagnostic.sh        - full system diagnostics"
echo "   health-check                 - alias for system-diagnostic.sh"
echo ""

# Add diagnostic aliases for the user
echo "🔧 Setting diagnostic aliases..."
USER_HOME="/home/${SUDO_USER:-pi}"
if [[ -d "$USER_HOME" ]]; then
    cat >> "$USER_HOME/.bashrc" << 'EOF'

# Diagnostic aliases for HA monitoring
alias diag-full="system-diagnostic.sh"
alias diag-telegram="system-diagnostic.sh 2>/dev/null | grep -A 25 \"Telegram Sender Service\""
alias diag-monitoring="system-diagnostic.sh 2>/dev/null | grep -A 50 \"MONITORING SYSTEM\""
alias diag-summary="system-diagnostic.sh 2>/dev/null | grep -E \"(OK|WARNING|ERROR)\" | tail -20"
EOF
    chown ${SUDO_USER:-pi}:${SUDO_USER:-pi} "$USER_HOME/.bashrc"
    echo "✅ Diagnostic aliases added"
else
    echo "⚠️  User home directory not found, aliases not added"
fi

echo ""
echo "💡 Quick diagnostic commands:"
echo "   health-check     - full system diagnostics (79 checks)"
echo "   health-quick     - quick core components check"  
echo "   health-monitor   - real-time monitoring"
echo "   diagnostic       - alternative diagnostics via ha-monitoring-control"
echo ""
echo "📍 Log files:"
echo "   /var/log/ha-watchdog.log     - checks log"
echo "   /var/log/ha-responder.log    - actions log" 
echo "   /var/log/ha-failures.log     - failures log"
echo "   /var/log/telegram-sender.log - Telegram send log"
echo ""
