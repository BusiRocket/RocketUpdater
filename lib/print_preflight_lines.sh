#!/bin/bash

# print_preflight_lines prints one greppable key=value line per preflight
# probe; scheduled runs, verbose runs and the tests read these.
print_preflight_lines() {
    print_message plain "preflight os=$1 build=$2 arch=$3 bash=$BASH_VERSION"
    print_message plain "preflight path=$PATH"
    print_message plain "preflight disk=${4}KiB_free"
    print_message plain "preflight backup=$5"
    print_message plain "preflight power=$6"
    print_message plain "preflight load=$7 cpus=$8 cpu_idle=$9"
    print_message plain "preflight FDA=${10}"
    print_message plain "preflight DNS=${11}"
    print_message plain "preflight sudo_mode=${12} sudo_list=${13}"
    print_message plain "preflight ssh_agent=${14}"
    print_message plain "preflight binaries=${15}"
}
