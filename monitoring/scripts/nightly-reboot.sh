#!/bin/bash
# Nightly Reboot Script with Telegram Notification
# Part of Smart Home Monitoring System

LOG_FILE="/var/log/ha-reboot.log"
CONFIG_FILE="/etc/ha-watchdog/config"

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
    if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
        curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
             -d "chat_id=$TELEGRAM_CHAT_ID" \
             -d "text=$message" \
             -d "parse_mode=HTML" > /dev/null 2>&1
    fi
}

# Pre-reboot checks and notification
log_message "Starting nightly reboot sequence"

# Check system health before reboot
UPTIME=$(uptime -p)
LOAD=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
MEMORY_USAGE=$(free | awk 'NR==2{printf "%.1f%%", $3*100/$2}')
DISK_USAGE=$(df / | awk 'NR==2{print $5}')

# Create reboot message
REBOOT_MSG="🔄 <b>Scheduled Reboot</b>
🕐 Time: $(date '+%Y-%m-%d %H:%M:%S %Z')
⏱️ Uptime: $UPTIME
📊 Load: $LOAD
💾 Memory: $MEMORY_USAGE
💿 Disk: $DISK_USAGE
🔁 System will restart in 30 seconds..."

# Send notification
send_telegram "$REBOOT_MSG"
log_message "Reboot notification sent. Uptime: $UPTIME, Load: $LOAD"

# Wait 30 seconds for notification to be sent
sleep 30

# Perform reboot
log_message "Initiating system reboot"
/sbin/shutdown -r now
