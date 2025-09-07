#!/bin/bash

# 🔍 System Diagnostic Daily Report - Send daily diagnostic results to Telegram
# Runs daily at 5:30 AM to verify all systems are operational
# Author: Smart Home Monitoring System
# Version: 1.0

SCRIPT_NAME="system-diagnostic-startup"
LOG_FILE="/var/log/system-diagnostic-startup.log"
DIAGNOSTIC_SCRIPT="/usr/local/bin/system-diagnostic.sh"
TELEGRAM_SENDER="/usr/local/bin/telegram-sender.sh"
CONFIG_FILE="/etc/telegram-sender/config"

# Logging function
log_message() {
    local level="$1"
    local message="$2"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] [$SCRIPT_NAME] $message" | tee -a "$LOG_FILE"
}

# Parse diagnostic output and extract key information
parse_diagnostic_results() {
    local diagnostic_output="$1"
    
    # Extract test counts
    local successful_tests=$(echo "$diagnostic_output" | grep -o "✅ [0-9]* successful" | grep -o "[0-9]*" || echo "0")
    
    # Extract warnings
    local warnings=$(echo "$diagnostic_output" | grep "⚠️\|WARNING\|WARN" | head -10)
    
    # Extract errors
    local errors=$(echo "$diagnostic_output" | grep "❌\|ERROR\|CRITICAL\|FAILED" | head -10)
    
    # Extract conclusion (last few lines)
    local conclusion=$(echo "$diagnostic_output" | tail -20 | grep -E "(CONCLUSION|SUMMARY|Overall|Total|Status)" -A 5)
    
    # If no specific conclusion found, use last non-empty lines
    if [[ -z "$conclusion" ]]; then
        conclusion=$(echo "$diagnostic_output" | grep -v "^$" | tail -5)
    fi
    
    # Format message
    local message="🔍 <b>Daily System Diagnostic Report</b>\n"
    message+="📅 $(date '+%Y-%m-%d %H:%M:%S')\n\n"
    
    # Add successful tests count
    if [[ "$successful_tests" -gt 0 ]]; then
        message+="✅ <b>Successful Tests:</b> $successful_tests\n\n"
    fi
    
    # Add warnings if any
    if [[ -n "$warnings" ]]; then
        message+="⚠️ <b>Warnings:</b>\n"
        message+="<pre>$(echo "$warnings" | head -5)</pre>\n\n"
    fi
    
    # Add errors if any
    if [[ -n "$errors" ]]; then
        message+="❌ <b>Errors:</b>\n"
        message+="<pre>$(echo "$errors" | head -5)</pre>\n\n"
    fi
    
    # Add conclusion
    if [[ -n "$conclusion" ]]; then
        message+="📋 <b>Conclusion:</b>\n"
        message+="<pre>$(echo "$conclusion")</pre>"
    fi
    
    echo -e "$message"
}

# Main execution
main() {
    log_message "INFO" "Starting daily system diagnostic report"
    
    # Check dependencies
    if [[ ! -f "$DIAGNOSTIC_SCRIPT" ]]; then
        log_message "ERROR" "Diagnostic script not found: $DIAGNOSTIC_SCRIPT"
        exit 1
    fi
    
    if [[ ! -f "$TELEGRAM_SENDER" ]]; then
        log_message "ERROR" "Telegram sender script not found: $TELEGRAM_SENDER"
        exit 1
    fi
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_message "ERROR" "Telegram config not found: $CONFIG_FILE"
        exit 1
    fi
    
    # Load telegram config to get topic ID
    source "$CONFIG_FILE"
    
    if [[ -z "$TELEGRAM_TOPIC_SYSTEM_DIAGNOSTIC" ]]; then
        log_message "ERROR" "TELEGRAM_TOPIC_SYSTEM_DIAGNOSTIC not configured"
        exit 1
    fi
    
    # Run diagnostic
    log_message "INFO" "Running system diagnostic..."
    local diagnostic_output
    if diagnostic_output=$("$DIAGNOSTIC_SCRIPT" 2>&1); then
        log_message "INFO" "Diagnostic completed successfully"
    else
        log_message "WARN" "Diagnostic completed with issues (exit code: $?)"
    fi
    
    # Parse and format results
    local telegram_message
    telegram_message=$(parse_diagnostic_results "$diagnostic_output")
    
    # Send to telegram
    log_message "INFO" "Sending diagnostic report to Telegram (topic: $TELEGRAM_TOPIC_SYSTEM_DIAGNOSTIC)"
    if "$TELEGRAM_SENDER" "$telegram_message" "$TELEGRAM_TOPIC_SYSTEM_DIAGNOSTIC" "HTML"; then
        log_message "INFO" "Diagnostic report sent successfully"
    else
        log_message "ERROR" "Failed to send diagnostic report to Telegram"
        exit 1
    fi
    
    log_message "INFO" "Daily system diagnostic report completed"
}

# Execute main function
main "$@"
