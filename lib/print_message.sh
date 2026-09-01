#!/bin/bash

print_message() {
    local level=$1
    local color=''
    local prefix=''
    local reset=''
    shift

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
    esac

    if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ -n "$color" ]; then
        reset='\033[0m'
        printf '%b%s%s%b\n' "$color" "$prefix" "$*" "$reset"
    else
        printf '%s%s\n' "$prefix" "$*"
    fi
}
