#!/bin/bash

log_event() {
    local level=$1
    local event=$2
    local plugin=$3
    local status=$4
    local duration=$5
    local message=$6
    local sanitized_run_id=$RUN_ID
    local timestamp

    timestamp=$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ') || return 1

    level=${level//$'\t'/ }
    level=${level//$'\n'/ }
    level=${level//$'\r'/ }
    event=${event//$'\t'/ }
    event=${event//$'\n'/ }
    event=${event//$'\r'/ }
    plugin=${plugin//$'\t'/ }
    plugin=${plugin//$'\n'/ }
    plugin=${plugin//$'\r'/ }
    status=${status//$'\t'/ }
    status=${status//$'\n'/ }
    status=${status//$'\r'/ }
    duration=${duration//$'\t'/ }
    duration=${duration//$'\n'/ }
    duration=${duration//$'\r'/ }
    message=${message//$'\t'/ }
    message=${message//$'\n'/ }
    message=${message//$'\r'/ }
    sanitized_run_id=${sanitized_run_id//$'\t'/ }
    sanitized_run_id=${sanitized_run_id//$'\n'/ }
    sanitized_run_id=${sanitized_run_id//$'\r'/ }
    timestamp=${timestamp//$'\t'/ }
    timestamp=${timestamp//$'\n'/ }
    timestamp=${timestamp//$'\r'/ }

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$sanitized_run_id" "$timestamp" "$level" "$event" "$plugin" "$status" "$duration" "$message" \
        >>"$ROCKETUPDATER_EVENT_LOG"
}
