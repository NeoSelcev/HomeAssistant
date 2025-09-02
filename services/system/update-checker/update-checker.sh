#!/bin/bash
# System Update Checker with Detailed Report
# Part of Smart Home Monitoring System

LOG_FILE="/var/log/ha-update-checker.log"
REPORT_FILE="/var/log/ha-update-report.log"
CONFIG_FILE="/etc/ha-watchdog/config"
TELEGRAM_SENDER="/usr/local/bin/telegram-sender.sh"

# Load configuration
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "$(date): Configuration file not found: $CONFIG_FILE" >> "$LOG_FILE"
    exit 1
fi

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" >> "$LOG_FILE"
}

# Function to send Telegram notification
send_telegram() {
    local message="$1"
    
    # Отправляем в топик UPDATES (ID: 9) - telegram-sender сам логирует результат
    "$TELEGRAM_SENDER" "$message" "9"
}

# Check if it's a working day (Monday-Friday)
WEEKDAY=$(date +%u)
if [ $WEEKDAY -gt 5 ]; then
    log_message "Skipping update check - weekend"
    exit 0
fi

log_message "Starting system update check"

# Create detailed report
cat > "$REPORT_FILE" << EOF
========================================
SYSTEM UPDATE REPORT
Generated: $(date '+%Y-%m-%d %H:%M:%S %Z')
Hostname: $(hostname)
========================================

EOF

# Check for package updates
echo "1. DEBIAN PACKAGE UPDATES" >> "$REPORT_FILE"
echo "=========================" >> "$REPORT_FILE"
apt update > /dev/null 2>&1
PACKAGE_UPDATES=$(apt list --upgradable 2>/dev/null | grep -v "Listing..." | wc -l)

if [ $PACKAGE_UPDATES -gt 0 ]; then
    echo "Available updates: $PACKAGE_UPDATES packages" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo "Package list:" >> "$REPORT_FILE"
    apt list --upgradable 2>/dev/null | grep -v "Listing..." | head -20 >> "$REPORT_FILE"
    if [ $PACKAGE_UPDATES -gt 20 ]; then
        echo "... and $((PACKAGE_UPDATES - 20)) more packages" >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
    echo "Commands to update packages:" >> "$REPORT_FILE"
    echo "  1. Create backup: sudo rsync -av /etc/ /backup/etc-\$(date +%Y%m%d)/" >> "$REPORT_FILE"
    echo "  2. Update package lists: sudo apt update" >> "$REPORT_FILE"
    echo "  3. Upgrade packages: sudo apt upgrade -y" >> "$REPORT_FILE"
    echo "  4. Clean up: sudo apt autoremove -y && sudo apt autoclean" >> "$REPORT_FILE"
    PACKAGES_NEED_UPDATE=true
else
    echo "No package updates available" >> "$REPORT_FILE"
    PACKAGES_NEED_UPDATE=false
fi

echo "" >> "$REPORT_FILE"

# Check for Docker image updates
echo "2. DOCKER IMAGE UPDATES" >> "$REPORT_FILE"
echo "======================" >> "$REPORT_FILE"

if command -v docker >/dev/null 2>&1; then
    cd /srv/home || { echo "Docker compose directory not found" >> "$REPORT_FILE"; exit 1; }
    
    # Check current images
    echo "Current running containers:" >> "$REPORT_FILE"
    docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # Pull latest images to check for updates
    DOCKER_OUTPUT=$(docker compose pull 2>&1)
    if echo "$DOCKER_OUTPUT" | grep -q "Downloaded newer image\|Pull complete"; then
        echo "Docker image updates available!" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        echo "Commands to update Docker stack:" >> "$REPORT_FILE"
        echo "  1. Create config backup: sudo cp -r /srv/home /backup/srv-home-\$(date +%Y%m%d)" >> "$REPORT_FILE"
        echo "  2. Create database backup: sudo docker exec homeassistant tar -czf /config/backup-\$(date +%Y%m%d).tar.gz /config" >> "$REPORT_FILE"
        echo "  3. Pull new images: cd /srv/home && sudo docker compose pull" >> "$REPORT_FILE"
        echo "  4. Recreate containers: sudo docker compose up -d --force-recreate" >> "$REPORT_FILE"
        echo "  5. Clean old images: sudo docker image prune -f" >> "$REPORT_FILE"
        echo "  6. Verify services: sudo docker ps && curl -f http://localhost:8123 && curl -f http://localhost:1880" >> "$REPORT_FILE"
        DOCKER_NEEDS_UPDATE=true
    else
        echo "No Docker image updates available" >> "$REPORT_FILE"
        DOCKER_NEEDS_UPDATE=false
    fi
else
    echo "Docker not available" >> "$REPORT_FILE"
    DOCKER_NEEDS_UPDATE=false
fi

echo "" >> "$REPORT_FILE"

# Check kernel updates
echo "3. KERNEL UPDATES" >> "$REPORT_FILE"
echo "================" >> "$REPORT_FILE"
CURRENT_KERNEL=$(uname -r)
AVAILABLE_KERNELS=$(apt list --upgradable 2>/dev/null | grep linux-image | wc -l)

echo "Current kernel: $CURRENT_KERNEL" >> "$REPORT_FILE"
if [ $AVAILABLE_KERNELS -gt 0 ]; then
    echo "Kernel updates available: $AVAILABLE_KERNELS" >> "$REPORT_FILE"
    apt list --upgradable 2>/dev/null | grep linux-image >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo "⚠️  KERNEL UPDATE REQUIRES REBOOT!" >> "$REPORT_FILE"
    echo "Commands for kernel update:" >> "$REPORT_FILE"
    echo "  1. Schedule maintenance window" >> "$REPORT_FILE"
    echo "  2. Create full system backup" >> "$REPORT_FILE"
    echo "  3. Update kernel: sudo apt upgrade linux-image-*" >> "$REPORT_FILE"
    echo "  4. Reboot system: sudo reboot" >> "$REPORT_FILE"
    echo "  5. Verify new kernel: uname -r" >> "$REPORT_FILE"
    KERNEL_NEEDS_UPDATE=true
else
    echo "No kernel updates available" >> "$REPORT_FILE"
    KERNEL_NEEDS_UPDATE=false
fi

echo "" >> "$REPORT_FILE"

# System status
echo "4. CURRENT SYSTEM STATUS" >> "$REPORT_FILE"
echo "========================" >> "$REPORT_FILE"
echo "Uptime: $(uptime -p)" >> "$REPORT_FILE"
echo "Load: $(uptime | awk -F'load average:' '{print $2}')" >> "$REPORT_FILE"
echo "Memory: $(free -h | awk 'NR==2{printf "%s/%s (%.1f%%)", $3,$2,$3*100/$2}')" >> "$REPORT_FILE"
echo "Disk: $(df -h / | awk 'NR==2{print $3"/"$2" ("$5")"}')" >> "$REPORT_FILE"
echo "Temperature: $(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | awk '{print $1/1000"°C"}' || echo 'N/A')" >> "$REPORT_FILE"

echo "" >> "$REPORT_FILE"
echo "========================================" >> "$REPORT_FILE"

# Determine if any updates are needed
if [ "$PACKAGES_NEED_UPDATE" = true ] || [ "$DOCKER_NEEDS_UPDATE" = true ] || [ "$KERNEL_NEEDS_UPDATE" = true ]; then
    UPDATE_SUMMARY="📦 Updates Available!"
    PRIORITY="HIGH"
    
    # Count total updates
    TOTAL_UPDATES=0
    [ "$PACKAGES_NEED_UPDATE" = true ] && TOTAL_UPDATES=$((TOTAL_UPDATES + PACKAGE_UPDATES))
    [ "$DOCKER_NEEDS_UPDATE" = true ] && TOTAL_UPDATES=$((TOTAL_UPDATES + 3))  # Assume 3 docker images
    [ "$KERNEL_NEEDS_UPDATE" = true ] && TOTAL_UPDATES=$((TOTAL_UPDATES + AVAILABLE_KERNELS))
    
    # Create Telegram message
    TELEGRAM_MSG="🔔 <b>System Updates Available</b>
🏠 Host: $(hostname)
📅 Date: $(date '+%Y-%m-%d %H:%M')

📊 <b>Update Summary:</b>"

    if [ "$PACKAGES_NEED_UPDATE" = true ]; then
        TELEGRAM_MSG="$TELEGRAM_MSG
📦 Packages: $PACKAGE_UPDATES updates"
    fi
    
    if [ "$DOCKER_NEEDS_UPDATE" = true ]; then
        TELEGRAM_MSG="$TELEGRAM_MSG
🐳 Docker: Image updates available"
    fi
    
    if [ "$KERNEL_NEEDS_UPDATE" = true ]; then
        TELEGRAM_MSG="$TELEGRAM_MSG
⚠️ Kernel: $AVAILABLE_KERNELS updates (reboot required)"
    fi
    
    TELEGRAM_MSG="$TELEGRAM_MSG

📋 Detailed report: /var/log/ha-update-report.log
🛠️ Check report for backup and update commands

⏰ Recommended maintenance window during low usage hours"

    # Send notification
    send_telegram "$TELEGRAM_MSG"
    log_message "Update check completed - Updates available: P:$PACKAGE_UPDATES D:$DOCKER_NEEDS_UPDATE K:$AVAILABLE_KERNELS"
    
else
    log_message "Update check completed - No updates available"
    echo "✅ SUMMARY: No updates available" >> "$REPORT_FILE"
    
    # Send "no updates" notification
    NO_UPDATES_MSG="✅ <b>System Status: Up to Date</b>
🏠 Host: $(hostname)
📅 Date: $(date '+%Y-%m-%d %H:%M')

📦 <b>All components current:</b>
✅ Packages: No updates available
✅ Docker: Images up to date
✅ Kernel: Current version

📊 <b>System Health:</b>
⏱️ Uptime: $(uptime -p)
💾 Memory: $(free -h | awk 'NR==2{printf "%s/%s", $3,$2}')
💿 Disk: $(df -h / | awk 'NR==2{print $3"/"$2}')

🛡️ System monitoring active and healthy"

    send_telegram "$NO_UPDATES_MSG"
fi

echo "Report saved to: $REPORT_FILE" >> "$REPORT_FILE"
log_message "Update check report generated: $REPORT_FILE"
