#!/bin/bash
# Nightly Reboot Script with Telegram Notification
# Part of Smart Home Monitoring System

LOG_FILE="/var/log/ha-reboot.log"
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
    echo "$(date '+%Y-%m-%d %H:%M:%S') [NIGHTLY-REBOOT] $1" >> "$LOG_FILE"
}

# Function to send Telegram notification
send_telegram() {
    local message="$1"
    
    # Отправляем в топик RESTART (ID: 4) - telegram-sender сам логирует результат
    "$TELEGRAM_SENDER" "$message" "4"
}

# Check if system has been running for at least 10 minutes to prevent boot loops
UPTIME_SECONDS=$(awk '{print int($1)}' /proc/uptime)
MIN_UPTIME=600  # 10 minutes

if [ $UPTIME_SECONDS -lt $MIN_UPTIME ]; then
    log_message "========== NIGHTLY REBOOT SCRIPT - INSUFFICIENT UPTIME =========="
    log_message "System uptime: ${UPTIME_SECONDS}s, Required: ${MIN_UPTIME}s"
    log_message "Script will not reboot system that just booted"
    
    UPTIME_MSG="⚠️ <b>Nightly Reboot - Boot Loop Protection</b>
🕐 Time: $(date '+%Y-%m-%d %H:%M:%S %Z')
⏱️ Uptime: $(uptime -p)
⚠️ System uptime too low (${UPTIME_SECONDS}s < ${MIN_UPTIME}s)
❌ Reboot cancelled - boot loop protection"
    
    send_telegram "$UPTIME_MSG"
    log_message "Boot loop protection notification sent. Exiting without reboot."
    exit 0
fi

# Check if we're running at the correct time (03:30 ± 5 minutes)
CURRENT_HOUR=$(date +%H)
CURRENT_MINUTE=$(date +%M)
CURRENT_TIME_MINUTES=$((CURRENT_HOUR * 60 + CURRENT_MINUTE))
TARGET_TIME_MINUTES=$((3 * 60 + 30))  # 03:30 = 210 minutes
TIME_DIFF=$((CURRENT_TIME_MINUTES - TARGET_TIME_MINUTES))

# Allow ±5 minutes window (205-215 minutes from midnight)
if [ $TIME_DIFF -lt -5 ] || [ $TIME_DIFF -gt 5 ]; then
    log_message "========== NIGHTLY REBOOT SCRIPT CALLED AT WRONG TIME =========="
    log_message "Current time: $(date '+%H:%M'), Expected: 03:30 (±5 min)"
    log_message "Script will not perform reboot outside scheduled window"
    
    WRONG_TIME_MSG="⚠️ <b>Nightly Reboot - Wrong Time</b>
🕐 Current: $(date '+%Y-%m-%d %H:%M:%S %Z')
⏰ Expected: 03:30 (±5 minutes)
❌ Reboot cancelled - not in scheduled window"
    
    send_telegram "$WRONG_TIME_MSG"
    log_message "Wrong time notification sent. Exiting without reboot."
    exit 0
fi

# Pre-reboot checks and notification
log_message "========== NIGHTLY REBOOT SEQUENCE STARTED =========="
log_message "System: $(hostname), Time: $(date)"
log_message "Starting nightly reboot sequence - time check passed"

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
log_message "System metrics - Memory: $MEMORY_USAGE, Disk: $DISK_USAGE"

# Wait 30 seconds for notification to be sent
sleep 30

# Perform reboot
log_message "Initiating system reboot - END OF LOG BEFORE RESTART"
log_message "========================================================="
/sbin/shutdown -r now
