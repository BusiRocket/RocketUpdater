#!/bin/bash

# run_preflight MODE probes the machine, prints one greppable key=value line
# per probe, records one structured preflight event, and returns 0 (ready),
# 20 (degraded: defer heavy work), or 78 (invalid configuration).
run_preflight() {
    local mode=$1
    local failure_reasons=""
    local degraded_reasons=""

    local binaries_status=ok
    local required_binary
    for required_binary in /bin/bash /usr/bin/lockf /opt/homebrew/bin/timeout \
        /usr/bin/caffeinate /usr/sbin/softwareupdate; do
        if [ ! -x "$required_binary" ]; then
            binaries_status=missing
            failure_reasons="$failure_reasons missing_binary:$required_binary"
        fi
    done

    local os_version
    local os_build
    local machine_arch
    os_version=$(/usr/bin/sw_vers -productVersion 2>/dev/null) || os_version=unknown
    os_build=$(/usr/bin/sw_vers -buildVersion 2>/dev/null) || os_build=unknown
    machine_arch=$(/usr/bin/uname -m 2>/dev/null) || machine_arch=unknown

    # Preflight is fail-closed: an unreadable free-space figure blocks the run
    # just like a full disk would.
    local disk_free_kib
    disk_free_kib=$(/bin/df -k /System/Volumes/Data 2>/dev/null |
        /usr/bin/awk 'NR == 2 { print $4 }')
    case $disk_free_kib in
    '' | *[!0-9]*)
        disk_free_kib=unknown
        failure_reasons="$failure_reasons disk_free_unreadable"
        ;;
    *)
        if [ "$disk_free_kib" -lt 20971520 ]; then
            failure_reasons="$failure_reasons disk_free_below_20GiB"
        fi
        ;;
    esac

    local backup_state=none
    local tmutil_output
    tmutil_output=$(/usr/bin/tmutil destinationinfo 2>&1) || true
    case $tmutil_output in
    *'No destinations'* | '') backup_state=none ;;
    *) backup_state=configured ;;
    esac

    local power_state=ac
    local battery_percent=100
    local pmset_output
    pmset_output=$(/usr/bin/pmset -g batt 2>/dev/null) || pmset_output=""
    if printf '%s' "$pmset_output" | /usr/bin/grep -q "Battery Power"; then
        battery_percent=$(printf '%s\n' "$pmset_output" |
            /usr/bin/sed -n 's/.*[[:space:]]\([0-9][0-9]*\)%.*/\1/p' | /usr/bin/head -1)
        case $battery_percent in
        '' | *[!0-9]*) battery_percent=0 ;;
        esac
        power_state="battery:${battery_percent}%"
        if [ "$battery_percent" -lt 50 ]; then
            degraded_reasons="$degraded_reasons battery_below_50"
        fi
    fi

    local load_one
    local cpu_count
    load_one=$(/usr/sbin/sysctl -n vm.loadavg 2>/dev/null |
        /usr/bin/awk '{ print $2 }')
    cpu_count=$(/usr/sbin/sysctl -n hw.logicalcpu 2>/dev/null)
    case $cpu_count in
    '' | *[!0-9]*) cpu_count=1 ;;
    esac
    # Load average alone is not saturation: it counts processes blocked on I/O,
    # so a backup daemon or a big download pushes it over the CPU count while
    # the machine is mostly idle. Measured on 2026-09-08: load 22 on 16 CPUs
    # with 58% idle, which would defer every plugin for nothing. Confirm with
    # measured idle before degrading — 2026-09-01 was the genuine case, load
    # 56-62 with 0.0% idle. When idle cannot be measured, the load alone
    # decides, which is the old behaviour.
    local cpu_idle=unknown
    case $load_one in
    '') load_one=unknown ;;
    *)
        if /usr/bin/awk -v load="$load_one" -v cpus="$cpu_count" \
            'BEGIN { exit !(load > cpus) }'; then
            cpu_idle=$(/opt/homebrew/bin/timeout --kill-after=5s 20s \
                /usr/bin/top -l 2 -n 0 2>/dev/null |
                /usr/bin/awk '/CPU usage/ { gsub("%", "", $7); idle = $7 } END { print idle }' |
                /usr/bin/tr ',' '.')
            case $cpu_idle in
            '' | *[!0-9.]*) cpu_idle=unknown ;;
            esac

            if [ "$cpu_idle" = unknown ] ||
                /usr/bin/awk -v idle="$cpu_idle" 'BEGIN { exit !(idle < 15) }'; then
                degraded_reasons="$degraded_reasons load_above_cpu_count"
            fi
        fi
        ;;
    esac

    # Full Disk Access probe: the user TCC database is readable only with FDA.
    # FDA=no skips the affected reports later; it never blocks the run.
    local fda_state=no
    if [ -r "$HOME/Library/Application Support/com.apple.TCC/TCC.db" ]; then
        fda_state=yes
    fi

    local dns_state=unavailable
    local dns_attempts=1
    local dns_attempt=1
    if [ "$mode" = scheduled ]; then
        dns_attempts=30
    fi
    while [ "$dns_attempt" -le "$dns_attempts" ]; do
        if /usr/bin/dscacheutil -q host -a name apple.com 2>/dev/null |
            /usr/bin/grep -q ip_address; then
            dns_state=ok
            break
        fi
        dns_attempt=$((dns_attempt + 1))
        if [ "$dns_attempt" -le "$dns_attempts" ]; then
            /bin/sleep 10
        fi
    done
    if [ "$dns_state" != ok ]; then
        degraded_reasons="$degraded_reasons dns_unavailable"
    fi

    # Record sudo-list availability as metadata only; scheduled mode never
    # probes sudo, and no credential or rule text is captured.
    local sudo_list=not_probed
    if [ "$mode" = manual ] && command_exists sudo; then
        if sudo -n -l >/dev/null 2>&1; then
            sudo_list=cached
        else
            sudo_list=none
        fi
    fi

    local ssh_agent=absent
    if [ -n "${SSH_AUTH_SOCK:-}" ]; then
        ssh_agent=present
    fi

    print_message plain "preflight os=$os_version build=$os_build arch=$machine_arch bash=$BASH_VERSION"
    print_message plain "preflight path=$PATH"
    print_message plain "preflight disk=${disk_free_kib}KiB_free"
    print_message plain "preflight backup=$backup_state"
    print_message plain "preflight power=$power_state"
    print_message plain "preflight load=$load_one cpus=$cpu_count cpu_idle=$cpu_idle"
    print_message plain "preflight FDA=$fda_state"
    print_message plain "preflight DNS=$dns_state"
    print_message plain "preflight sudo_mode=$mode sudo_list=$sudo_list"
    print_message plain "preflight ssh_agent=$ssh_agent"
    print_message plain "preflight binaries=$binaries_status"

    if [ "$backup_state" = none ]; then
        echo_warning "No Time Machine destination is configured; destructive work stays manual."
    fi

    if [ -n "$failure_reasons" ]; then
        log_event error preflight '' failed 0 "reasons:$failure_reasons"
        return 78
    fi
    if [ -n "$degraded_reasons" ]; then
        log_event warning preflight '' degraded 0 "reasons:$degraded_reasons"
        return 20
    fi
    log_event info preflight '' ready 0 \
        "disk=${disk_free_kib}KiB backup=$backup_state power=$power_state dns=$dns_state fda=$fda_state"
    return 0
}
