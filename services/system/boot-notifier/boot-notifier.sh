#!/bin/bash
# Boot Notification Script
# Sends Telegram notification after system boot
# Detects if reboot was planned (nightly-reboot) or unplanned

SCRIPT_NAME="boot-notifier"
LOGGING_SERVICE="/usr/local/bin/logging-service.sh"
TELEGRAM_SENDER="/usr/local/bin/telegram-sender.sh"
REBOOT_LOG="/var/log/ha-reboot.log"
PLANNED_REBOOT_MARKER="/var/lib/nightly-reboot/planned-reboot.marker"

# Connect centralized logging service
if [[ -f "$LOGGING_SERVICE" ]] && [[ -r "$LOGGING_SERVICE" ]]; then
    source "$LOGGING_SERVICE" 2>/dev/null
    if ! command -v log_structured >/dev/null 2>&1; then
        echo "ERROR: logging-service not available" >&2
        exit 1
    fi
else
    echo "ERROR: Centralized logging-service not found: $LOGGING_SERVICE" >&2
    exit 1
fi

# Wait for system to stabilize
sleep 10

# Check if this was a planned reboot
PLANNED_REBOOT=false
if [[ -f "$PLANNED_REBOOT_MARKER" ]]; then
    # Check if marker is recent (less than 5 minutes old)
    MARKER_AGE=$(($(date +%s) - $(stat -c %Y "$PLANNED_REBOOT_MARKER" 2>/dev/null || echo 0)))
    if [[ $MARKER_AGE -lt 300 ]]; then
        PLANNED_REBOOT=true
        log_info "Detected planned reboot (marker age: ${MARKER_AGE}s)"
        # Remove marker after detection
        rm -f "$PLANNED_REBOOT_MARKER"
    else
        log_warn "Found old reboot marker (age: ${MARKER_AGE}s), considering reboot unplanned"
        rm -f "$PLANNED_REBOOT_MARKER"
    fi
fi

# If planned reboot, exit silently (pre-reboot notification already sent)
if [[ "$PLANNED_REBOOT" == "true" ]]; then
    log_info "Planned reboot detected, skipping boot notification (already notified before reboot)"
    exit 0
fi

# Unplanned reboot - send notification
log_warn "Unplanned reboot detected, sending boot notification"

# Gather system information
BOOT_TIME=$(who -b | awk '{print $3, $4}')
UPTIME=$(uptime -p)
LOAD=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
MEMORY_USAGE=$(free | awk 'NR==2{printf "%.1f%%", $3*100/$2}')
DISK_USAGE=$(df / | awk 'NR==2{print $5}')

# Check last shutdown reason from journalctl
SHUTDOWN_REASON=$(journalctl -b -1 -n 50 --no-pager 2>/dev/null | grep -i "shutdown\|reboot\|power" | tail -1 || echo "Unknown")

# Check for kernel panic or crash
KERNEL_ISSUE=""
if journalctl -b -1 --no-pager 2>/dev/null | grep -qi "panic\|oops\|segfault"; then
    KERNEL_ISSUE="⚠️ Kernel panic/crash detected in previous boot"
fi

# Check for power issues
POWER_ISSUE=""
if dmesg | grep -qi "under.*voltage\|power.*supply"; then
    POWER_ISSUE="⚠️ Power supply issues detected"
fi

# Create boot notification message
BOOT_MSG="🔄 <b>System Restarted (Unplanned)</b>
🕐 Boot Time: $BOOT_TIME
⏱️ Current Uptime: $UPTIME
📊 Load: $LOAD
💾 Memory: $MEMORY_USAGE
💿 Disk: $DISK_USAGE"

if [[ -n "$KERNEL_ISSUE" ]]; then
    BOOT_MSG="$BOOT_MSG

$KERNEL_ISSUE"
fi

if [[ -n "$POWER_ISSUE" ]]; then
    BOOT_MSG="$BOOT_MSG

$POWER_ISSUE"
fi

BOOT_MSG="$BOOT_MSG

📋 Last shutdown: ${SHUTDOWN_REASON:0:100}"

# Send notification to RESTART topic (ID: 4)
if "$TELEGRAM_SENDER" "$BOOT_MSG" "4"; then
    log_info "Unplanned boot notification sent successfully"
else
    log_error "Failed to send boot notification"
    exit 1
fi

log_info "Boot notification completed"
