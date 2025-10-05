#!/bin/bash

# Fail2Ban Telegram Notification Script
# This script sends security alerts to Telegram when fail2ban bans/unbans IPs

ACTION="$1"
IP="$2"
JAIL="$3"
TIME="$4"

TELEGRAM_SCRIPT="/usr/local/bin/telegram-sender.sh"
LOG_FILE="/var/log/fail2ban-telegram-notify.log"
SECURITY_TOPIC="471"  # Security topic ID

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$ACTION] $1" >> "$LOG_FILE"
}

# Function to get IP geolocation
get_ip_location() {
    local ip="$1"
    
    # Check if IP is private/VPN range
    if [[ "$ip" =~ ^100\. ]] || [[ "$ip" =~ ^192\.168\. ]] || [[ "$ip" =~ ^10\. ]] || [[ "$ip" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]]; then
        echo "VPN/Private Network"
        return
    fi
    
    # Try to get location info, with timeout and fallback
    local location
    location=$(timeout 5 curl -s "http://ip-api.com/json/$ip" 2>/dev/null | jq -r '.country + ", " + .city' 2>/dev/null)
    
    if [[ "$location" == "null, null" ]] || [[ -z "$location" ]] || [[ "$location" == ", " ]]; then
        echo "Unknown Location"
    else
        echo "$location"
    fi
}

# Function to get additional IP info
get_ip_info() {
    local ip="$1"
    
    # Check if IP is private/VPN range
    if [[ "$ip" =~ ^100\. ]] || [[ "$ip" =~ ^192\.168\. ]] || [[ "$ip" =~ ^10\. ]] || [[ "$ip" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]]; then
        echo "VPN/Private Network"
        return
    fi
    
    local org
    org=$(timeout 3 curl -s "http://ip-api.com/json/$ip" 2>/dev/null | jq -r '.org // "Unknown ISP"' 2>/dev/null)
    echo "$org"
}

# Function to get ban duration from jail configuration
get_ban_duration() {
    local jail="$1"
    local bantime
    
    # Try to get bantime from jail-specific configuration first
    bantime=$(grep -A 20 "^\[$jail\]" /etc/fail2ban/jail.local 2>/dev/null | grep "^bantime" | head -1 | cut -d'=' -f2 | tr -d ' ')
    
    # If not found, get from DEFAULT section
    if [[ -z "$bantime" ]]; then
        bantime=$(grep "^bantime" /etc/fail2ban/jail.local 2>/dev/null | head -1 | cut -d'=' -f2 | tr -d ' ')
    fi
    
    # Convert time to human readable format
    case "$bantime" in
        *h) echo "$bantime" ;;
        *m) echo "$bantime" ;;
        *s) echo "$bantime" ;;
        [0-9]*) 
            if [[ $bantime -ge 3600 ]]; then
                echo "$((bantime / 3600)) hour(s)"
            elif [[ $bantime -ge 60 ]]; then
                echo "$((bantime / 60)) minute(s)"
            else
                echo "$bantime second(s)"
            fi
            ;;
        *) echo "1 hour" ;; # fallback
    esac
}

case "$ACTION" in
    "start")
        MESSAGE="🛡️ FAIL2BAN STARTED

⏰ Time: $(date '+%Y-%m-%d %H:%M:%S')
🔄 Status: Protection System Online

Ready to defend against attacks!"
        
        "$TELEGRAM_SCRIPT" "$MESSAGE" "$SECURITY_TOPIC"
        log_message "Fail2ban started - notification sent"
        ;;
        
    "stop")
        MESSAGE="⚠️ FAIL2BAN STOPPED

⏰ Time: $(date '+%Y-%m-%d %H:%M:%S')
🔄 Status: Protection System Offline

Security monitoring disabled!"
        
        "$TELEGRAM_SCRIPT" "$MESSAGE" "$SECURITY_TOPIC"
        log_message "Fail2ban stopped - notification sent"
        ;;
        
    "ban")
        if [[ -z "$IP" ]] || [[ -z "$JAIL" ]]; then
            log_message "ERROR: Missing IP or JAIL parameter for ban action"
            exit 1
        fi
        
        # Get IP location and ISP info
        LOCATION=$(get_ip_location "$IP")
        ISP=$(get_ip_info "$IP")
        BAN_DURATION=$(get_ban_duration "$JAIL")
        
        # Clean jail name from angle brackets that break HTML parsing
        JAIL_CLEAN=$(echo "$JAIL" | sed 's/[<>]//g')
        
        MESSAGE="🚨 SECURITY BREACH DETECTED 🚨

🔒 IP BANNED: $IP
🏛️ Service: $JAIL_CLEAN
📍 Location: $LOCATION
🌐 ISP: $ISP
⏰ Time: $(date '+%Y-%m-%d %H:%M:%S')

🛡️ Automatic protection activated!
⏱️ Ban duration: $BAN_DURATION"
        
        "$TELEGRAM_SCRIPT" "$MESSAGE" "471"
        log_message "IP $IP banned in jail $JAIL - notification sent (Location: $LOCATION)"
        ;;
        
    "unban")
        if [[ -z "$IP" ]] || [[ -z "$JAIL" ]]; then
            log_message "ERROR: Missing IP or JAIL parameter for unban action"
            exit 1
        fi
        
        # Clean jail name from angle brackets that break HTML parsing
        JAIL_CLEAN=$(echo "$JAIL" | sed 's/[<>]//g')
        
        MESSAGE="✅ IP ADDRESS UNBANNED

🔓 IP Released: $IP
🏛️ Service: $JAIL_CLEAN
⏰ Time: $(date '+%Y-%m-%d %H:%M:%S')

Ban period expired - monitoring continues."
        
        "$TELEGRAM_SCRIPT" "$MESSAGE" "471"
        log_message "IP $IP unbanned from jail $JAIL - notification sent"
        ;;
        
    *)
        log_message "ERROR: Unknown action '$ACTION'"
        exit 1
        ;;
esac

exit 0