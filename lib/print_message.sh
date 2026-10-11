#!/bin/bash

print_message() {
    local level=$1
    local color=''
    local prefix=''
    local reset=''
    shift

    # The compact interface draws its own lines, so under it every leveled
    # message travels as one record (RS, level, tab, text) the renderer parses;
    # plain lines stay raw output like anything a tool prints.
    if [ "${ROCKETUPDATER_UI:-}" = compact ] && [ "$level" != plain ]; then
        printf '\036%s\t%s\n' "$level" "$*"
        return 0
    fi

    case $level in
    error)
        color='\033[0;31m'
        prefix='❌ '
        ;;
    info)
        color='\033[1;36m'
        prefix='ℹ️  '
        ;;
    skip)
        color='\033[0;90m'
        prefix='⏭️  '
        ;;
    success)
        color='\033[0;32m'
        prefix='✅ '
        ;;
    warning)
        color='\033[1;33m'
        prefix='⚠️  '
        ;;
    note)
        color='\033[0;90m'
        prefix='⊙  '
        ;;
    change)
        color='\033[0;32m'
        prefix='↑  '
        ;;
    esac

    if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ -n "$color" ]; then
        reset='\033[0m'
        printf '%b%s%s%b\n' "$color" "$prefix" "$*" "$reset"
    else
        printf '%s%s\n' "$prefix" "$*"
    fi
}
