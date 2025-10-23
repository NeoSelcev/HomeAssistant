#!/bin/bash

# 📱 Universal script for sending Telegram messages with topic support
# Used by all monitoring system components
# Author: Smart Home Monitoring System
# Version: 2.0 - Integrated with centralized logging

SCRIPT_NAME="telegram-sender"
LOGGING_SERVICE="/usr/local/bin/logging-service.sh"
CONFIG_FILE="/etc/telegram-sender/config"

# Connect centralized logging service FIRST
if [[ -f "$LOGGING_SERVICE" ]] && [[ -r "$LOGGING_SERVICE" ]]; then
    source "$LOGGING_SERVICE" 2>/dev/null
    if ! command -v log_info >/dev/null 2>&1; then
        echo "ERROR: logging-service wrapper functions not available" >&2
        exit 1
    fi
else
    echo "ERROR: Centralized logging-service not found: $LOGGING_SERVICE" >&2
    exit 1
fi

# Load configuration
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    log_error "Config file not found: $CONFIG_FILE"
    exit 1
fi

# Set variables from config or default values
TIMEOUT="${TELEGRAM_TIMEOUT:-10}"
RETRY_COUNT="${TELEGRAM_RETRY_COUNT:-3}"
RETRY_DELAY="${TELEGRAM_RETRY_DELAY:-2}"
MAX_MESSAGE_LENGTH="${TELEGRAM_MAX_MESSAGE_LENGTH:-4096}"
MAX_PREVIEW_LENGTH="${TELEGRAM_MAX_PREVIEW_LENGTH:-100}"
DEFAULT_PARSE_MODE="${TELEGRAM_PARSE_MODE_DEFAULT:-HTML}"

# Function to get topic name by ID
get_topic_name() {
    local topic_id="$1"
    case "$topic_id" in
        "$TELEGRAM_TOPIC_SYSTEM") echo "system" ;;
        "$TELEGRAM_TOPIC_ERRORS") echo "errors" ;;
        "$TELEGRAM_TOPIC_UPDATES") echo "updates" ;;
        "$TELEGRAM_TOPIC_RESTART") echo "restart" ;;
        "$TELEGRAM_TOPIC_SYSTEM_DIAGNOSTIC") echo "system_diagnostic" ;;
        "$TELEGRAM_TOPIC_BACKUP") echo "backup" ;;
        "$TELEGRAM_TOPIC_SECURITY") echo "security" ;;
        "") echo "root" ;;
        *) echo "topic_$topic_id" ;;
    esac
}

# Main message sending function
send_telegram_message() {
    local message="$1"
    local topic_id="$2"  # Optional parameter
    local parse_mode="${3:-$DEFAULT_PARSE_MODE}"
    
    # Check required parameters
    if [[ -z "$message" ]]; then
        log_error "Message is empty"
        echo "ERROR: Message cannot be empty"
        return 1
    fi
    
    if [[ -z "$TELEGRAM_BOT_TOKEN" ]] || [[ -z "$TELEGRAM_CHAT_ID" ]]; then
        log_error "Telegram credentials not configured"
        echo "ERROR: Telegram credentials not configured"
        return 1
    fi
    
    # Get hostname for message formatting
    local hostname=$(hostname)
    
    # Format message with hostname prefix
    message="[$hostname] $message"
    
    # Truncate message if too long
    if [[ ${#message} -gt $MAX_MESSAGE_LENGTH ]]; then
    local truncated_message="${message:0:$((MAX_MESSAGE_LENGTH-50))}...\n\n[Message truncated: original length ${#message} chars]"
        log_warn "Message truncated from ${#message} to ${#truncated_message} characters"
        message="$truncated_message"
    fi
    
    # Prepare data for sending
    local curl_data="chat_id=$TELEGRAM_CHAT_ID"
    curl_data="$curl_data&text=$(echo "$message" | sed 's/&/%26/g; s/</%3C/g; s/>/%3E/g')"
    curl_data="$curl_data&parse_mode=$parse_mode"
    
    # Add extra parameters
    if [[ "$TELEGRAM_DISABLE_NOTIFICATION" == "true" ]]; then
        curl_data="$curl_data&disable_notification=true"
    fi
    if [[ "$TELEGRAM_DISABLE_WEB_PAGE_PREVIEW" == "true" ]]; then
        curl_data="$curl_data&disable_web_page_preview=true"
    fi
    
    # Add topic if provided
    local topic_name="root"
    if [[ -n "$topic_id" ]]; then
        curl_data="$curl_data&message_thread_id=$topic_id"
        topic_name=$(get_topic_name "$topic_id")
    fi
    
    log_info "Attempting to send message to topic '$topic_name' (ID: ${topic_id:-'none'})"
    log_debug "Message preview: $(echo "$message" | head -c $MAX_PREVIEW_LENGTH)..."
    
    # Send message with retries
    local attempt=1
    while [[ $attempt -le $RETRY_COUNT ]]; do
        log_debug "Attempt $attempt/$RETRY_COUNT"
        
        local response=$(curl -s -w "HTTP_CODE:%{http_code}" --max-time "$TIMEOUT" \
            -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
            -d "$curl_data" 2>&1)
        
        local http_code=$(echo "$response" | grep -o 'HTTP_CODE:[0-9]*' | cut -d: -f2)
        local json_response=$(echo "$response" | sed 's/HTTP_CODE:[0-9]*$//')
        
    # Process result
        if [[ "$http_code" == "200" ]] && echo "$json_response" | grep -q '"ok":true'; then
            local message_id=$(echo "$json_response" | grep -o '"message_id":[0-9]*' | cut -d: -f2)
            log_info "Message sent successfully to topic '$topic_name' (message_id: $message_id, attempt: $attempt)"
            return 0
        else
            local error_description=$(echo "$json_response" | grep -o '"description":"[^"]*"' | cut -d'"' -f4)
            log_warn "Attempt $attempt failed. HTTP: $http_code, Error: ${error_description:-'Unknown error'}"
            
            if [[ $attempt -lt $RETRY_COUNT ]]; then
                log_info "Retrying in $RETRY_DELAY seconds..."
                sleep "$RETRY_DELAY"
            fi
        fi
        
        ((attempt++))
    done
    
    # All attempts failed
    log_error "Failed to send message to topic '$topic_name' after $RETRY_COUNT attempts"
    log_debug "Final response: $json_response"
    return 1
}

# Main logic (when script is executed directly)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Create log file if it does not exist
    if [[ ! -f "$LOG_FILE" ]]; then
        touch "$LOG_FILE"
        chmod 644 "$LOG_FILE"
    fi
    
    case "${1:-}" in
        "")
            echo "ERROR: Message is required"
            echo "Usage: $0 <message> [topic_id] [parse_mode]"
            exit 1
            ;;
        *)
            send_telegram_message "$1" "$2" "$3"
            exit $?
            ;;
    esac
fi
