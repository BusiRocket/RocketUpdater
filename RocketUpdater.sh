#!/bin/bash

set -e

# Get the directory of the script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/log_event.sh
source "$SCRIPT_DIR/lib/log_event.sh"
# shellcheck source=lib/print_message.sh
source "$SCRIPT_DIR/lib/print_message.sh"
# shellcheck source=lib/echo_info.sh
source "$SCRIPT_DIR/lib/echo_info.sh"
# shellcheck source=lib/echo_success.sh
source "$SCRIPT_DIR/lib/echo_success.sh"
# shellcheck source=lib/echo_warning.sh
source "$SCRIPT_DIR/lib/echo_warning.sh"
# shellcheck source=lib/echo_error.sh
source "$SCRIPT_DIR/lib/echo_error.sh"
# shellcheck source=lib/echo_skip.sh
source "$SCRIPT_DIR/lib/echo_skip.sh"

EVENT_DIRECTORY="$HOME/Library/Logs/RocketUpdater"
ROCKETUPDATER_EVENT_LOG="${ROCKETUPDATER_EVENT_LOG:-$EVENT_DIRECTORY/events.log}"
RUN_ID="${RUN_ID:-$(/bin/date -u '+%Y%m%dT%H%M%SZ').$$}"
export ROCKETUPDATER_EVENT_LOG RUN_ID

if ! mkdir -p "$EVENT_DIRECTORY" || ! chmod 700 "$EVENT_DIRECTORY"; then
    print_message plain "RocketUpdater could not secure its event log directory" >&2
    exit 78
fi

previous_umask=$(umask)
umask 077
if ! : >>"$ROCKETUPDATER_EVENT_LOG"; then
    umask "$previous_umask"
    print_message plain "RocketUpdater could not open its event log" >&2
    exit 78
fi
umask "$previous_umask"
if ! chmod 600 "$ROCKETUPDATER_EVENT_LOG"; then
    print_message plain "RocketUpdater could not secure its event log" >&2
    exit 78
fi

LOCK_DIRECTORY="$HOME/Library/Caches/RocketUpdater"

if ! mkdir -p "$LOCK_DIRECTORY"; then
    print_message plain "RocketUpdater could not create its lock directory" >&2
    exit 78
fi

if ! chmod 700 "$LOCK_DIRECTORY"; then
    print_message plain "RocketUpdater could not secure its lock directory" >&2
    exit 78
fi

if [ "$ROCKETUPDATER_LOCKED" != "1" ]; then
    export ROCKETUPDATER_LOCKED=1
    if /usr/bin/lockf -s -t 0 -k \
        "$LOCK_DIRECTORY/run.lock" \
        "$SCRIPT_DIR/RocketUpdater.sh" "$@"; then
        lock_status=0
    else
        lock_status=$?
    fi
    if [ "$lock_status" -eq 75 ]; then
        log_event warning lock_busy '' busy 0 "RocketUpdater is already running" || true
        print_message plain "RocketUpdater is already running" >&2
    fi
    exit "$lock_status"
fi

# shellcheck source=lib/command_exists.sh
source "$SCRIPT_DIR/lib/command_exists.sh"
# shellcheck source=lib/read_plugin_metadata.sh
source "$SCRIPT_DIR/lib/read_plugin_metadata.sh"
# shellcheck source=lib/run_preflight.sh
source "$SCRIPT_DIR/lib/run_preflight.sh"

ROCKETUPDATER_VERSION="1.0.0"
RUN_STARTED_AT=$(/bin/date '+%s')

log_runner_end() {
    local runner_status=$1
    local event_status=failed
    local finished_at
    local duration

    if [ "$runner_status" -eq 0 ]; then
        event_status=success
    fi
    finished_at=$(/bin/date '+%s')
    duration=$((finished_at - RUN_STARTED_AT))
    log_event info run_end '' "$event_status" "$duration" \
        "total=${TOTAL_PLUGINS:-0} successful=${SUCCESSFUL_PLUGINS:-0} failed=${FAILED_PLUGINS:-0} skipped=${SKIPPED_PLUGINS:-0}" || true
    if declare -F stop_sudo_keepalive >/dev/null 2>&1; then
        stop_sudo_keepalive
    fi
}

trap 'log_runner_end $?' EXIT
log_event info run_start '' started 0 "RocketUpdater v$ROCKETUPDATER_VERSION"

ROCKETUPDATER_MODE=manual
ROCKETUPDATER_PREFLIGHT_ONLY=false
SELECTED_PLUGIN=""
CLEANUP_OPERATION=""

parse_cli_arguments() {
    local saw_scheduled=false
    local saw_clean=false
    local saw_preflight=false

    while [ "$#" -gt 0 ]; do
        case $1 in
        --scheduled)
            if [ "$saw_scheduled" = true ]; then
                print_message plain "Duplicate mode: --scheduled" >&2
                return 78
            fi
            saw_scheduled=true
            shift
            ;;
        --preflight-only)
            if [ "$saw_preflight" = true ]; then
                print_message plain "Duplicate mode: --preflight-only" >&2
                return 78
            fi
            saw_preflight=true
            shift
            ;;
        --clean)
            if [ "$saw_clean" = true ] || [ "$#" -lt 2 ]; then
                print_message plain "Usage: $0 --clean <homebrew|npm|sparkle|all>" >&2
                return 78
            fi
            case $2 in
            homebrew | npm | sparkle | all) CLEANUP_OPERATION=$2 ;;
            *)
                print_message plain "Unknown cleanup operation: $2" >&2
                return 78
                ;;
            esac
            saw_clean=true
            shift 2
            ;;
        --*)
            print_message plain "Unknown option: $1" >&2
            return 78
            ;;
        *)
            if [ -n "$SELECTED_PLUGIN" ]; then
                print_message plain "Only one plugin may be selected" >&2
                return 78
            fi
            SELECTED_PLUGIN=$1
            shift
            ;;
        esac
    done

    if [ "$saw_clean" = true ]; then
        if [ "$saw_scheduled" = true ] || [ "$saw_preflight" = true ] || [ -n "$SELECTED_PLUGIN" ]; then
            print_message plain "--clean cannot be combined with another mode or a plugin" >&2
            return 78
        fi
        ROCKETUPDATER_MODE=clean
    elif [ "$saw_scheduled" = true ]; then
        ROCKETUPDATER_MODE=scheduled
    fi

    ROCKETUPDATER_PREFLIGHT_ONLY=$saw_preflight
    export ROCKETUPDATER_MODE ROCKETUPDATER_PREFLIGHT_ONLY
}

if ! parse_cli_arguments "$@"; then
    exit 78
fi

if [ "$ROCKETUPDATER_MODE" = clean ]; then
    if [ "${NONINTERACTIVE:-0}" = 1 ] || [ "${ROCKETUPDATER_LAUNCHD:-0}" = 1 ] ||
        [ ! -t 0 ] || [ ! -t 1 ]; then
        print_message plain "Cleanup requires an interactive terminal" >&2
        exit 78
    fi
    /bin/bash "$SCRIPT_DIR/scripts/run-cleanup.sh" "$CLEANUP_OPERATION"
    exit $?
fi

set +e
run_preflight "$ROCKETUPDATER_MODE"
PREFLIGHT_STATUS=$?
set -e

if [ "$PREFLIGHT_STATUS" -eq 78 ]; then
    echo_error "Preflight failed: invalid configuration."
    exit 78
fi

# Degradation defers heavy scheduled work; a degraded preflight is not a
# failure, so preflight-only reporting still exits 0.
ROCKETUPDATER_DEFER_RUN_ACTIONS=false
if [ "$PREFLIGHT_STATUS" -eq 20 ]; then
    echo_warning "Preflight is degraded; heavy scheduled work is deferred."
    if [ "$ROCKETUPDATER_MODE" = scheduled ] && [ -z "$SELECTED_PLUGIN" ]; then
        ROCKETUPDATER_DEFER_RUN_ACTIONS=true
    fi
fi

if [ "$ROCKETUPDATER_PREFLIGHT_ONLY" = true ]; then
    exit 0
fi

# Track plugin results for summary (bash 3.2 compatible)
TOTAL_PLUGINS=0
SUCCESSFUL_PLUGINS=0
FAILED_PLUGINS=0
SKIPPED_PLUGINS=0
FAILED_PLUGIN_LIST=""

echo_info "RocketUpdater v$ROCKETUPDATER_VERSION - starting system update"

# Ask for root once, here, while stdin is still the terminal. Plugins run with
# no stdin on purpose, so they cannot prompt themselves without stalling the
# whole run; they read SUDO_AVAILABLE and use the credentials cached by this
# step. Declining is a supported answer; each privileged plugin handles the
# missing grant explicitly.
export SUDO_AVAILABLE=false
SUDO_KEEPALIVE_PID=""

request_sudo_access() {
    if [ "$ROCKETUPDATER_MODE" != manual ]; then
        return 0
    fi

    if ! command_exists sudo; then
        return 0
    fi

    # A manual run without a terminal cannot *prompt*, but it can still use a
    # grant that needs no prompt: `sudo -n` never asks, it fails. A host with a
    # NOPASSWD rule (the Mac mini) therefore keeps the privileged paths over
    # ssh, where the old early return made PEAR fail on root-owned files.
    if [ ! -t 0 ]; then
        if sudo -n true 2>/dev/null; then
            SUDO_AVAILABLE=true
            start_sudo_keepalive
            echo_info "Root access is available without a prompt; privileged steps stay enabled."
            return 0
        fi

        echo_warning "No terminal available for a sudo prompt; continuing without root."
        return 0
    fi

    if sudo -n true 2>/dev/null; then
        SUDO_AVAILABLE=true
        start_sudo_keepalive
        return 0
    fi

    echo_warning "Some steps do more as root (PEAR/PECL upgrades, macOS update downloads)."
    echo_warning "Enter your password to allow them, or press Ctrl-D to continue without."

    if sudo -v; then
        SUDO_AVAILABLE=true
        start_sudo_keepalive
        echo_success "Root access granted for this run."
    else
        echo_skip "Continuing without root. Privileged steps will be attempted unprivileged."
    fi
}

# A full run outlasts sudo's timestamp (five minutes by default), so refresh it
# until the script exits. Without this, the steps that need root run last and
# find the grant already expired, reporting "sudo: a password is required".
#
# Refresh with `sudo -n -v`, which sudo(8) documents as extending the timeout
# without running a command. An earlier version ran `sudo -n true` instead and
# the ticket still expired mid-run.
start_sudo_keepalive() {
    while true; do
        sleep 60
        kill -0 "$$" 2>/dev/null || exit 0
        sudo -n -v 2>/dev/null || exit 0
    done &
    SUDO_KEEPALIVE_PID=$!
    # Detach it from job control. Otherwise killing it at the end of a
    # non-interactive run makes bash print "Terminated: 15  sleep 60" into the
    # log, which reads like a failure and is only the keepalive shutting down.
    disown "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
}

stop_sudo_keepalive() {
    [ -n "$SUDO_KEEPALIVE_PID" ] || return 0
    # Kill the sleep it is parked in as well; killing the subshell alone leaves
    # that child orphaned for up to a minute after the run ends.
    pkill -P "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    SUDO_KEEPALIVE_PID=""
}

plugin_record() {
    local plugin_file=$1
    local plugin_metadata
    local plugin_name
    local plugin_version
    local plugin_disabled
    local plugin_priority_value
    local plugin_timeout_seconds
    local plugin_scheduled_action
    local plugin_filename=${plugin_file##*/}
    local plugin_basename=${plugin_filename%.sh}

    plugin_metadata=$(read_plugin_metadata "$plugin_file") || return 78
    IFS=$'\t' read -r plugin_name plugin_version plugin_disabled plugin_priority_value \
        plugin_timeout_seconds plugin_scheduled_action <<<"$plugin_metadata"

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$plugin_priority_value" "$plugin_basename" "$plugin_name" "$plugin_version" \
        "$plugin_disabled" "$plugin_timeout_seconds" "$plugin_scheduled_action"
}

selected_plugin_records() {
    local selected_plugin=${1:-}
    local plugin_file
    local record
    local unsorted_records=""

    if [ -n "$selected_plugin" ]; then
        case $selected_plugin in
        *[!a-zA-Z0-9_]* | '')
            echo_error "Invalid plugin name: $selected_plugin"
            return 78
            ;;
        esac
        plugin_record "$SCRIPT_DIR/plugins/$selected_plugin.sh" || return 78
        return 0
    fi

    if [ ! -d "$SCRIPT_DIR/plugins" ]; then
        echo_error 'No plugins found. Please ensure the plugins directory exists and contains plugins.'
        return 78
    fi

    for plugin_file in "$SCRIPT_DIR"/plugins/*.sh; do
        if [ ! -f "$plugin_file" ]; then
            echo_error 'No plugins found. Please ensure the plugins directory exists and contains plugins.'
            return 78
        fi
        record=$(plugin_record "$plugin_file") || return 78
        if [ -z "$unsorted_records" ]; then
            unsorted_records=$record
        else
            unsorted_records="$unsorted_records
$record"
        fi
    done

    printf '%s\n' "$unsorted_records" | LC_ALL=C sort -t $'\t' -k1,1n -k2,2
}

load_plugin_records() {
    local selected_plugin=${1:-}
    local metadata_status

    set +e
    PLUGIN_RECORDS=$(selected_plugin_records "$selected_plugin")
    metadata_status=$?
    set -e

    if [ "$metadata_status" -ne 0 ] || [ -z "$PLUGIN_RECORDS" ]; then
        return 78
    fi
}

append_failed_plugin() {
    local plugin=$1

    if [ -z "$FAILED_PLUGIN_LIST" ]; then
        FAILED_PLUGIN_LIST=$plugin
    else
        FAILED_PLUGIN_LIST="$FAILED_PLUGIN_LIST $plugin"
    fi
}

run_plugin_record() {
    local record=$1
    local _plugin_priority
    local plugin
    local plugin_name
    local _plugin_version
    local plugin_disabled
    local plugin_timeout_seconds
    local plugin_scheduled_action
    local plugin_file
    local plugin_function
    local plugin_status
    local plugin_started_at
    local plugin_finished_at
    local plugin_duration

    IFS=$'\t' read -r _plugin_priority plugin plugin_name _plugin_version plugin_disabled \
        plugin_timeout_seconds plugin_scheduled_action <<<"$record"
    plugin_file="$SCRIPT_DIR/plugins/$plugin.sh"

    TOTAL_PLUGINS=$((TOTAL_PLUGINS + 1))
    plugin_started_at=$(/bin/date '+%s')
    log_event info plugin_start "$plugin" started 0 "$plugin_name"

    if [ "$plugin_disabled" = true ]; then
        echo_skip "Plugin $plugin is disabled."
        SKIPPED_PLUGINS=$((SKIPPED_PLUGINS + 1))
        plugin_finished_at=$(/bin/date '+%s')
        plugin_duration=$((plugin_finished_at - plugin_started_at))
        log_event info plugin_end "$plugin" skipped "$plugin_duration" "Plugin is disabled"
        return 0
    fi

    if [ "$ROCKETUPDATER_MODE" = scheduled ]; then
        case $plugin_scheduled_action in
        skip)
            echo_skip "Plugin $plugin is configured to skip."
            SKIPPED_PLUGINS=$((SKIPPED_PLUGINS + 1))
            plugin_finished_at=$(/bin/date '+%s')
            plugin_duration=$((plugin_finished_at - plugin_started_at))
            log_event info plugin_end "$plugin" skipped "$plugin_duration" "Scheduled action is skip"
            return 0
            ;;
        report) plugin_function="report_$plugin" ;;
        run)
            if [ "$ROCKETUPDATER_DEFER_RUN_ACTIONS" = true ]; then
                echo_skip "Plugin $plugin is deferred by the degraded preflight."
                SKIPPED_PLUGINS=$((SKIPPED_PLUGINS + 1))
                plugin_finished_at=$(/bin/date '+%s')
                plugin_duration=$((plugin_finished_at - plugin_started_at))
                log_event info plugin_end "$plugin" skipped "$plugin_duration" \
                    "Deferred by the degraded preflight"
                return 0
            fi
            plugin_function="update_$plugin"
            ;;
        esac
    else
        plugin_function="update_$plugin"
    fi

    echo_info "Updating $plugin_name..."

    set +e
    /opt/homebrew/bin/timeout --kill-after=30s "$plugin_timeout_seconds" \
        /bin/bash "$SCRIPT_DIR/scripts/run-plugin.sh" "$plugin_file" "$plugin_function" </dev/null
    plugin_status=$?
    set -e
    plugin_finished_at=$(/bin/date '+%s')
    plugin_duration=$((plugin_finished_at - plugin_started_at))

    case $plugin_status in
    0)
        SUCCESSFUL_PLUGINS=$((SUCCESSFUL_PLUGINS + 1))
        log_event info plugin_end "$plugin" success "$plugin_duration" "$plugin_function completed"
        ;;
    20)
        SKIPPED_PLUGINS=$((SKIPPED_PLUGINS + 1))
        echo_skip "Plugin $plugin skipped (status 20)."
        log_event info plugin_end "$plugin" skipped "$plugin_duration" "$plugin_function returned status 20"
        ;;
    124 | 137)
        FAILED_PLUGINS=$((FAILED_PLUGINS + 1))
        append_failed_plugin "$plugin"
        echo_error "Plugin $plugin timed out (status $plugin_status)."
        log_event error plugin_end "$plugin" failed "$plugin_duration" \
            "$plugin_function timed out with status $plugin_status"
        ;;
    *)
        FAILED_PLUGINS=$((FAILED_PLUGINS + 1))
        append_failed_plugin "$plugin"
        echo_error "Command failed: $plugin_function (status $plugin_status)"
        log_event error plugin_end "$plugin" failed "$plugin_duration" \
            "$plugin_function returned status $plugin_status"
        ;;
    esac
}

# Function to load and update all plugins
load_and_update_plugins() {
    local record
    local _plugin_priority
    local plugin
    local plugin_order=""

    echo_info 'Loading plugins...'

    while IFS= read -r record <&3; do
        [ -n "$record" ] || continue
        IFS=$'\t' read -r _plugin_priority plugin _ <<<"$record"
        if [ -z "$plugin_order" ]; then
            plugin_order=$plugin
        else
            plugin_order="$plugin_order $plugin"
        fi
    done 3<<<"$PLUGIN_RECORDS"

    echo_info "Order: $plugin_order"

    # The record list has its own descriptor so child commands cannot consume
    # it, and the loop remains in the parent so only the parent updates counts.
    while IFS= read -r record <&3; do
        [ -n "$record" ] || continue
        run_plugin_record "$record"
    done 3<<<"$PLUGIN_RECORDS"
}

# Function to display summary
display_summary() {
    print_message plain "UPDATE SUMMARY"
    print_message plain "Total: $TOTAL_PLUGINS"
    echo_success "Successful: $SUCCESSFUL_PLUGINS"

    if [ "$FAILED_PLUGINS" -gt 0 ]; then
        echo_error "Failed: $FAILED_PLUGINS"
    else
        print_message plain "Failed: 0"
    fi

    echo_skip "Skipped: $SKIPPED_PLUGINS"

    # Show failed plugins if any
    if [ "$FAILED_PLUGINS" -gt 0 ]; then
        echo_error "Failed plugins:"
        for plugin in $FAILED_PLUGIN_LIST; do
            print_message plain "  - $plugin"
        done
    fi

    if [ "$FAILED_PLUGINS" -eq 0 ]; then
        echo_success "No plugin failures."
    else
        echo_warning "Some updates failed. Check the logs above."
    fi
}

# Validate all selected plugin metadata before sudo or any plugin execution.
if ! load_plugin_records "$SELECTED_PLUGIN"; then
    exit 78
fi

# Check if we are inside a conda environment
if [ -n "$CONDA_DEFAULT_ENV" ] && [ "$CONDA_DEFAULT_ENV" != "base" ]; then
    echo_warning "Deactivating the current conda environment ($CONDA_DEFAULT_ENV)."
    conda deactivate
fi

if [ "$ROCKETUPDATER_MODE" = manual ]; then
    request_sudo_access
fi

if [ -n "$SELECTED_PLUGIN" ]; then
    run_plugin_record "$PLUGIN_RECORDS"
    if [ "$FAILED_PLUGINS" -gt 0 ]; then
        exit 1
    fi
    exit 0
fi

echo_info 'Updating plugins...'
load_and_update_plugins

# Display summary
display_summary

if [ "$FAILED_PLUGINS" -gt 0 ]; then
    exit 1
fi
