#!/bin/bash

# 🔄 System Backup Restore Utility
# Restore system backups created by ha-backup service
# Author: Smart Home Monitoring System
# Version: 1.0

SCRIPT_NAME="ha-restore"
LOG_FILE="/var/log/ha-restore.log"
BACKUP_BASE_DIR="/opt/backups"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log_message() {
    local level="$1"
    local message="$2"
    local color=""
    
    case "$level" in
        "INFO") color="$BLUE" ;;
        "SUCCESS") color="$GREEN" ;;
        "WARN") color="$YELLOW" ;;
        "ERROR") color="$RED" ;;
    esac
    
    echo -e "${color}[$level]${NC} $message" | tee -a "$LOG_FILE"
}

# List available backups
list_backups() {
    log_message "INFO" "Available backups in $BACKUP_BASE_DIR:"
    echo
    
    if [[ ! -d "$BACKUP_BASE_DIR" ]]; then
        log_message "ERROR" "Backup directory not found: $BACKUP_BASE_DIR"
        return 1
    fi
    
    local backups=($(find "$BACKUP_BASE_DIR" -maxdepth 1 -type d -name "20*" | sort -r))
    
    if [[ ${#backups[@]} -eq 0 ]]; then
        log_message "WARN" "No backups found"
        return 1
    fi
    
    local i=1
    for backup in "${backups[@]}"; do
        local backup_name=$(basename "$backup")
        local backup_size=$(du -sh "$backup" 2>/dev/null | cut -f1)
        local backup_date=$(echo "$backup_name" | sed 's/_/ /' | sed 's/\(.\{4\}\)\(.\{2\}\)\(.\{2\}\) \(.\{2\}\)\(.\{2\}\)\(.\{2\}\)/\1-\2-\3 \4:\5:\6/')
        
        printf "%2d) %s (%s) - %s\n" "$i" "$backup_name" "$backup_size" "$backup_date"
        
        # Show manifest if exists
        if [[ -f "$backup/backup_manifest.txt" ]]; then
            echo "     $(head -1 "$backup/backup_manifest.txt" | grep "Backup Created:")"
        fi
        echo
        
        ((i++))
    done
}

# Show backup details
show_backup_details() {
    local backup_dir="$1"
    
    if [[ ! -d "$backup_dir" ]]; then
        log_message "ERROR" "Backup directory not found: $backup_dir"
        return 1
    fi
    
    log_message "INFO" "Backup details for: $(basename "$backup_dir")"
    echo
    
    # Show manifest
    if [[ -f "$backup_dir/backup_manifest.txt" ]]; then
        cat "$backup_dir/backup_manifest.txt"
        echo
    fi
    
    # Show contents
    log_message "INFO" "Backup contents:"
    ls -lh "$backup_dir"
}

# Restore Home Assistant configuration
restore_homeassistant() {
    local backup_dir="$1"
    local ha_backup="$backup_dir/homeassistant_config.tar.gz"
    
    if [[ ! -f "$ha_backup" ]]; then
        log_message "ERROR" "Home Assistant backup not found: $ha_backup"
        return 1
    fi
    
    log_message "WARN" "This will overwrite current Home Assistant configuration!"
    read -p "Are you sure? (yes/no): " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        log_message "INFO" "Restore cancelled"
        return 0
    fi
    
    # Stop Home Assistant
    log_message "INFO" "Stopping Home Assistant..."
    docker stop homeassistant 2>/dev/null || true
    
    # Backup current config
    local current_backup="/tmp/ha_config_backup_$(date +%s).tar.gz"
    if [[ -d "/var/lib/homeassistant" ]]; then
        tar -czf "$current_backup" -C /var/lib homeassistant 2>/dev/null
        log_message "INFO" "Current config backed up to: $current_backup"
    fi
    
    # Restore from backup
    log_message "INFO" "Restoring Home Assistant configuration..."
    if tar -xzf "$ha_backup" -C /var/lib/ 2>/dev/null; then
        log_message "SUCCESS" "Home Assistant configuration restored"
        
        # Start Home Assistant
        log_message "INFO" "Starting Home Assistant..."
        docker start homeassistant 2>/dev/null || true
        
        return 0
    else
        log_message "ERROR" "Failed to restore Home Assistant configuration"
        return 1
    fi
}

# Restore monitoring system
restore_monitoring() {
    local backup_dir="$1"
    local monitoring_backup="$backup_dir/ha_monitoring.tar.gz"
    
    if [[ ! -f "$monitoring_backup" ]]; then
        log_message "ERROR" "Monitoring system backup not found: $monitoring_backup"
        return 1
    fi
    
    log_message "WARN" "This will overwrite current monitoring system configuration!"
    read -p "Are you sure? (yes/no): " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        log_message "INFO" "Restore cancelled"
        return 0
    fi
    
    # Extract to temporary directory
    local temp_dir="/tmp/monitoring_restore_$$"
    mkdir -p "$temp_dir"
    
    if tar -xzf "$monitoring_backup" -C "$temp_dir" 2>/dev/null; then
        log_message "INFO" "Restoring monitoring system..."
        
        # Restore monitoring scripts
        if [[ -d "$temp_dir/ha-monitoring" ]]; then
            cp -r "$temp_dir/ha-monitoring"/* /opt/ha-monitoring/ 2>/dev/null || true
        fi
        
        # Restore system configs
        if [[ -d "$temp_dir/system_configs" ]]; then
            cp -r "$temp_dir/system_configs"/* /etc/ 2>/dev/null || true
        fi
        
        # Restore systemd services
        if [[ -d "$temp_dir/systemd_services" ]]; then
            cp "$temp_dir/systemd_services"/* /etc/systemd/system/ 2>/dev/null || true
            systemctl daemon-reload
        fi
        
        log_message "SUCCESS" "Monitoring system restored"
        rm -rf "$temp_dir"
        return 0
    else
        log_message "ERROR" "Failed to restore monitoring system"
        rm -rf "$temp_dir"
        return 1
    fi
}

# Interactive restore menu
interactive_restore() {
    while true; do
        echo
        log_message "INFO" "Backup Restore Menu"
        echo "1) List available backups"
        echo "2) Show backup details"
        echo "3) Restore Home Assistant configuration"
        echo "4) Restore monitoring system"
        echo "5) Full system restore (ALL components)"
        echo "0) Exit"
        echo
        
        read -p "Select option (0-5): " choice
        
        case "$choice" in
            1)
                list_backups
                ;;
            2)
                list_backups
                echo
                read -p "Enter backup number to view details: " backup_num
                local backups=($(find "$BACKUP_BASE_DIR" -maxdepth 1 -type d -name "20*" | sort -r))
                if [[ $backup_num -ge 1 && $backup_num -le ${#backups[@]} ]]; then
                    show_backup_details "${backups[$((backup_num-1))]}"
                else
                    log_message "ERROR" "Invalid backup number"
                fi
                ;;
            3)
                list_backups
                echo
                read -p "Enter backup number to restore from: " backup_num
                local backups=($(find "$BACKUP_BASE_DIR" -maxdepth 1 -type d -name "20*" | sort -r))
                if [[ $backup_num -ge 1 && $backup_num -le ${#backups[@]} ]]; then
                    restore_homeassistant "${backups[$((backup_num-1))]}"
                else
                    log_message "ERROR" "Invalid backup number"
                fi
                ;;
            4)
                list_backups
                echo
                read -p "Enter backup number to restore from: " backup_num
                local backups=($(find "$BACKUP_BASE_DIR" -maxdepth 1 -type d -name "20*" | sort -r))
                if [[ $backup_num -ge 1 && $backup_num -le ${#backups[@]} ]]; then
                    restore_monitoring "${backups[$((backup_num-1))]}"
                else
                    log_message "ERROR" "Invalid backup number"
                fi
                ;;
            5)
                list_backups
                echo
                read -p "Enter backup number for FULL restore: " backup_num
                local backups=($(find "$BACKUP_BASE_DIR" -maxdepth 1 -type d -name "20*" | sort -r))
                if [[ $backup_num -ge 1 && $backup_num -le ${#backups[@]} ]]; then
                    log_message "WARN" "FULL SYSTEM RESTORE - This will overwrite ALL configurations!"
                    read -p "Type 'RESTORE' to confirm: " confirm
                    if [[ "$confirm" == "RESTORE" ]]; then
                        restore_homeassistant "${backups[$((backup_num-1))]}"
                        restore_monitoring "${backups[$((backup_num-1))]}"
                        log_message "SUCCESS" "Full system restore completed"
                    else
                        log_message "INFO" "Full restore cancelled"
                    fi
                else
                    log_message "ERROR" "Invalid backup number"
                fi
                ;;
            0)
                log_message "INFO" "Exiting restore utility"
                break
                ;;
            *)
                log_message "ERROR" "Invalid option"
                ;;
        esac
    done
}

# Main function
main() {
    log_message "INFO" "Starting backup restore utility"
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_message "ERROR" "This script must be run as root"
        exit 1
    fi
    
    # Check if backup directory exists
    if [[ ! -d "$BACKUP_BASE_DIR" ]]; then
        log_message "ERROR" "Backup directory not found: $BACKUP_BASE_DIR"
        exit 1
    fi
    
    # Start interactive menu
    interactive_restore
}

# Execute main function
main "$@"
