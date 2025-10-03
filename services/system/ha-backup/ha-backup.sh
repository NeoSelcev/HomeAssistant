#!/bin/bash

# 💾 Comprehensive System Backup Service
# Creates automated backups of critical Home Assistant system components
# Author: Smart Home Monitoring System
# Version: 1.0

SCRIPT_NAME="ha-backup"
LOG_FILE="/var/log/ha-backup.log"
BACKUP_BASE_DIR="/opt/backups"
BACKUP_DATE=$(date '+%Y%m%d_%H%M%S')
BACKUP_DIR="$BACKUP_BASE_DIR/$BACKUP_DATE"

# Retention settings
KEEP_DAILY_BACKUPS=7      # Keep 7 daily backups
KEEP_WEEKLY_BACKUPS=4     # Keep 4 weekly backups (1 month)
KEEP_MONTHLY_BACKUPS=3    # Keep 3 monthly backups

# Backup sources
HA_CONFIG_DIR="/opt/homeassistant/homeassistant"  # Docker bind mount location
HA_MONITORING_DIR="/opt/ha-monitoring"
SYSTEM_CONFIG_DIRS="/etc/systemd/system /etc/telegram-sender /etc/ha-watchdog /etc/logrotate.d"
DOCKER_DIR="/var/lib/docker/volumes"

# Telegram notification settings
TELEGRAM_SENDER="/usr/local/bin/telegram-sender.sh"
CONFIG_FILE="/etc/telegram-sender/config"

# Logging function
log_message() {
    local level="$1"
    local message="$2"
    
    # Special formatting for emoji levels - no timestamp or brackets
    if [[ "$level" =~ [^[:ascii:]] ]]; then
        echo "$level $message" | tee -a "$LOG_FILE"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] [$SCRIPT_NAME] $message" | tee -a "$LOG_FILE"
    fi
}

# Load telegram config
load_telegram_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    else
        log_message "WARN" "Telegram config not found: $CONFIG_FILE"
    fi
}

# Send telegram notification
send_telegram_notification() {
    local message="$1"
    local topic="${2:-$TELEGRAM_TOPIC_SYSTEM}"
    
    if [[ -f "$TELEGRAM_SENDER" && -n "$topic" ]]; then
        "$TELEGRAM_SENDER" "$message" "$topic" "HTML" 2>/dev/null || \
        log_message "WARN" "Failed to send Telegram notification"
    fi
}

# Check disk space
check_disk_space() {
    local required_space_mb=500  # Minimum 500MB required
    local available_space=$(df /opt | tail -1 | awk '{print $4}')
    local available_space_mb=$((available_space / 1024))
    
    if [[ $available_space_mb -lt $required_space_mb ]]; then
        log_message "⚠️" "Insufficient disk space: ${available_space_mb}MB available, ${required_space_mb}MB required"
        return 1
    fi
    
    log_message "✅" "Disk space check passed: ${available_space_mb}MB available"
    return 0
}

# Create backup directory
create_backup_dir() {
    if ! mkdir -p "$BACKUP_DIR"; then
        log_message "⚠️" "Failed to create backup directory: $BACKUP_DIR"
        return 1
    fi
    
    log_message "📁" "Created backup directory: $BACKUP_DIR"
    return 0
}

# Backup Home Assistant configuration
backup_homeassistant() {
    log_message "🏠" "Starting Home Assistant configuration backup..."
    
    if [[ ! -d "$HA_CONFIG_DIR" ]]; then
        log_message "WARN" "Home Assistant config directory not found: $HA_CONFIG_DIR"
        return 1
    fi
    
    local backup_file="$BACKUP_DIR/homeassistant_config.tar.gz"
    
    if tar -czf "$backup_file" -C "$(dirname "$HA_CONFIG_DIR")" "$(basename "$HA_CONFIG_DIR")" 2>/dev/null; then
        local size=$(du -h "$backup_file" | cut -f1)
        log_message "✅" "Home Assistant config backed up successfully ($size)"
        return 0
    else
        log_message "⚠️" "Failed to backup Home Assistant configuration"
        return 1
    fi
}

# Backup monitoring system
backup_monitoring_system() {
    log_message "📊" "Starting monitoring system backup..."
    
    local backup_file="$BACKUP_DIR/ha_monitoring.tar.gz"
    local temp_dir="/tmp/ha_monitoring_backup_$$"
    
    mkdir -p "$temp_dir"
    
    # Copy monitoring scripts and configs
    if [[ -d "$HA_MONITORING_DIR" ]]; then
        cp -r "$HA_MONITORING_DIR" "$temp_dir/" 2>/dev/null || true
    fi
    
    # Copy system configs
    for config_dir in $SYSTEM_CONFIG_DIRS; do
        if [[ -d "$config_dir" ]]; then
            local dirname=$(basename "$config_dir")
            mkdir -p "$temp_dir/system_configs"
            cp -r "$config_dir" "$temp_dir/system_configs/" 2>/dev/null || true
        fi
    done
    
    # Copy systemd services
    mkdir -p "$temp_dir/systemd_services"
    cp /etc/systemd/system/ha-*.service /etc/systemd/system/ha-*.timer 2>/dev/null || true
    cp /etc/systemd/system/system-diagnostic*.* /etc/systemd/system/nightly-*.* 2>/dev/null || true
    cp /etc/systemd/system/update-checker.* "$temp_dir/systemd_services/" 2>/dev/null || true
    
    # Copy our scripts from /usr/local/bin
    mkdir -p "$temp_dir/usr_local_bin"
    cp /usr/local/bin/ha-*.sh /usr/local/bin/system-diagnostic*.sh /usr/local/bin/telegram-sender.sh 2>/dev/null || true
    cp /usr/local/bin/health-check /usr/local/bin/system-diagnostic 2>/dev/null || true
    
    if tar -czf "$backup_file" -C "$temp_dir" . 2>/dev/null; then
        local size=$(du -h "$backup_file" | cut -f1)
        log_message "✅" "Monitoring system backed up successfully ($size)"
        rm -rf "$temp_dir"
        return 0
    else
        log_message "⚠️" "Failed to backup monitoring system"
        rm -rf "$temp_dir"
        return 1
    fi
}

# Backup Docker data (selective)
backup_docker_data() {
    log_message "🐳" "Starting Docker data backup..."
    
    # Only backup specific volumes, not all docker data
    local backup_file="$BACKUP_DIR/docker_volumes.tar.gz"
    local temp_dir="/tmp/docker_backup_$$"
    
    mkdir -p "$temp_dir"
    
    # Backup Home Assistant docker volume if exists
    if docker volume ls | grep -q homeassistant; then
        docker run --rm -v homeassistant:/data -v "$temp_dir":/backup alpine tar -czf /backup/homeassistant_volume.tar.gz -C /data . 2>/dev/null || true
    fi
    
    # Backup Node-RED volume if exists
    if docker volume ls | grep -q nodered; then
        docker run --rm -v nodered:/data -v "$temp_dir":/backup alpine tar -czf /backup/nodered_volume.tar.gz -C /data . 2>/dev/null || true
    fi
    
    if [[ -n "$(ls -A "$temp_dir" 2>/dev/null)" ]]; then
        tar -czf "$backup_file" -C "$temp_dir" . 2>/dev/null
        local size=$(du -h "$backup_file" | cut -f1)
        log_message "✅" "Docker volumes backed up successfully ($size)"
        rm -rf "$temp_dir"
        return 0
    else
        log_message "WARN" "No Docker volumes found to backup"
        rm -rf "$temp_dir"
        return 1
    fi
}

# Create backup manifest
create_backup_manifest() {
    local manifest_file="$BACKUP_DIR/backup_manifest.txt"
    
    cat > "$manifest_file" << EOF
Backup Created: $(date)
Backup Directory: $BACKUP_DIR
System: $(hostname)
Uptime: $(uptime)

Backup Contents:
$(ls -lh "$BACKUP_DIR")

System Info:
- Home Assistant Version: $(docker exec homeassistant python --version 2>/dev/null || echo "Unknown")
- System Load: $(cat /proc/loadavg)
- Memory Usage: $(free -h | grep Mem)
- Disk Usage: $(df -h /)

Services Status:
$(systemctl is-active ha-watchdog.timer ha-failure-notifier.timer system-diagnostic-startup.timer)
EOF
    
    log_message "📋" "Backup manifest created"
}

# Cleanup old backups
cleanup_old_backups() {
    log_message "🧹" "Starting cleanup of old backups..."
    
    cd "$BACKUP_BASE_DIR" || return 1
    
    # Remove backups older than retention periods
    # Daily backups (keep last 7 days)
    find . -maxdepth 1 -type d -name "20*" -mtime +$KEEP_DAILY_BACKUPS | head -10 | while read -r dir; do
        if [[ -d "$dir" ]]; then
            log_message "🗑️" "Removing old daily backup: $dir"
            rm -rf "$dir"
        fi
    done
    
    log_message "✅" "Cleanup completed"
}

# Calculate backup statistics
calculate_backup_stats() {
    local total_size=$(du -sh "$BACKUP_DIR" | cut -f1)
    local file_count=$(find "$BACKUP_DIR" -type f | wc -l)
    local duration=$(($(date +%s) - START_TIME))
    
    # Build message with printf to avoid encoding issues
    printf "💾 <b>System Backup Completed</b>\n📅 %s\n\n📊 <b>Statistics:</b>\n• Size: %s\n• Files: %s\n• Duration: %ss\n\n💾 <b>Backup Location:</b>\n<code>%s</code>" \
        "$(date '+%Y-%m-%d %H:%M:%S')" "$total_size" "$file_count" "$duration" "$BACKUP_DIR"
}

# Main backup function
main() {
    START_TIME=$(date +%s)
    log_message "🚀" "Starting comprehensive system backup"
    
    # Load configuration
    load_telegram_config
    
    # Pre-flight checks
    if ! check_disk_space; then
        send_telegram_notification "❌ <b>Backup Failed</b>
Insufficient disk space" "$TELEGRAM_TOPIC_BACKUP"
        exit 1
    fi
    
    if ! create_backup_dir; then
        send_telegram_notification "❌ <b>Backup Failed</b>
Cannot create backup directory" "$TELEGRAM_TOPIC_BACKUP"
        exit 1
    fi
    
    # Perform backups
    local backup_errors=0
    
    backup_homeassistant || ((backup_errors++))
    backup_monitoring_system || ((backup_errors++))
    backup_docker_data || true  # Don't count as error if no docker volumes
    
    # Create manifest
    create_backup_manifest
    
    # Cleanup old backups
    cleanup_old_backups
    
    # Calculate and report results
    local backup_summary=$(calculate_backup_stats)
    
    if [[ $backup_errors -eq 0 ]]; then
        log_message "✅" "All backup operations completed successfully"
        send_telegram_notification "$backup_summary" "$TELEGRAM_TOPIC_BACKUP"
    else
        log_message "⚠️" "Backup completed with $backup_errors errors"
        local error_message="⚠️ <b>Backup Completed with Errors</b>

$backup_summary

❌ <b>Errors:</b> $backup_errors"
        send_telegram_notification "$error_message" "$TELEGRAM_TOPIC_BACKUP"
    fi
    
    log_message "🏁" "Backup process finished"
}

# Execute main function
main "$@"
