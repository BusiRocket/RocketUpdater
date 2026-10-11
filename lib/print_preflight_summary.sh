#!/bin/bash

# print_preflight_summary OS ARCH DISK_KIB POWER BACKUP DNS LOAD CPUS REASONS
# condenses the preflight probes into the two lines the compact interface
# shows; the greppable key=value lines remain the verbose and scheduled output.
print_preflight_summary() {
    local os_version=$1
    local machine_arch=$2
    local disk_free_kib=$3
    local power_state=$4
    local backup_state=$5
    local dns_state=$6
    local load_one=$7
    local cpu_count=$8
    local degraded_reasons=$9
    local disk_text=unknown
    local reason

    case $disk_free_kib in
    '' | *[!0-9]*) ;;
    *) disk_text=$(LC_ALL=C /usr/bin/awk -v kib="$disk_free_kib" 'BEGIN { printf "%.1f GiB free", kib / 1048576 }') ;;
    esac

    printf '  \033[90mmacOS %s · %s · %s · power %s · backup %s · DNS %s · load %s/%s\033[0m\n' \
        "$os_version" "$machine_arch" "$disk_text" "$power_state" "$backup_state" \
        "$dns_state" "$load_one" "$cpu_count"

    for reason in $degraded_reasons; do
        case $reason in
        load_above_cpu_count) reason="machine is busy (load $load_one on $cpu_count CPUs); steps will be slower" ;;
        battery_below_50) reason="on battery below 50%" ;;
        dns_unavailable) reason="DNS is unavailable; network steps will fail" ;;
        esac
        printf '  \033[1;33m!\033[0m %s\n' "$reason"
    done
}
