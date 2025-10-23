#!/bin/bash

# 🔍 System Diagnostic Daily Report - Send daily diagnostic results to Telegram
# Runs daily at 5:30 AM to verify all systems are operational
# Author: Smart Home Monitoring System
# Version: 1.1 - Integrated with centralized logging

SCRIPT_NAME="system-diagnostic-startup"
LOGGING_SERVICE="/usr/local/bin/logging-service.sh"
DIAGNOSTIC_SCRIPT="/usr/local/bin/system-diagnostic.sh"

# Connect centralized logging service
if [[ -f "$LOGGING_SERVICE" ]] && [[ -r "$LOGGING_SERVICE" ]]; then
    source "$LOGGING_SERVICE" 2>/dev/null
    if ! command -v log_info >/dev/null 2>&1; then
        echo "ERROR: logging-service not available" >&2
        exit 1
    fi
else
    echo "ERROR: Centralized logging-service not found" >&2
    exit 1
fi

log_info "System diagnostic at startup - BEGIN"

# Run diagnostic
"$DIAGNOSTIC_SCRIPT"

log_info "System diagnostic at startup - COMPLETE"
        log_message "ERROR" "Failed to send diagnostic report to Telegram"
        exit 1
    fi
    
    log_message "INFO" "Daily system diagnostic report completed"
}

# Execute main function
main "$@"
