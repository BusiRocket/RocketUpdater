#!/bin/bash

read_plugin_metadata() {
    local plugin_file=$1
    local plugin_filename
    local plugin_basename
    local line
    local line_number=0
    local in_function=false
    local saw_function=false
    local function_name
    local has_update=false
    local has_report=false
    local name=""
    local version=""
    local disabled=""
    local priority=""
    local timeout_seconds=""
    local scheduled_action=""
    local name_count=0
    local version_count=0
    local disabled_count=0
    local priority_count=0
    local timeout_count=0
    local action_count=0

    if [ ! -f "$plugin_file" ]; then
        printf 'Invalid plugin metadata: file not found: %s\n' "$plugin_file" >&2
        return 78
    fi

    plugin_filename=${plugin_file##*/}
    case $plugin_filename in
    *.sh) plugin_basename=${plugin_filename%.sh} ;;
    *)
        printf 'Invalid plugin metadata: plugin filename must end in .sh: %s\n' "$plugin_file" >&2
        return 78
        ;;
    esac

    case $plugin_basename in
    '' | *[!a-zA-Z0-9_]*)
        printf 'Invalid plugin metadata: unsafe plugin basename: %s\n' "$plugin_basename" >&2
        return 78
        ;;
    esac

    while IFS= read -r line || [ -n "$line" ]; do
        line_number=$((line_number + 1))

        if [ "$line_number" -gt 10000 ] || [ "${#line}" -gt 4096 ]; then
            printf 'Invalid plugin metadata: parser bound exceeded at %s:%s\n' "$plugin_file" "$line_number" >&2
            return 78
        fi

        case $line in
        *"$(printf '\r')"*)
            printf 'Invalid plugin metadata: carriage return at %s:%s\n' "$plugin_file" "$line_number" >&2
            return 78
            ;;
        esac

        if [ "$in_function" = true ]; then
            if [[ $line =~ ^\}[[:space:]]*$ ]] || [[ $line =~ ^\}[[:space:]]+\#.*$ ]]; then
                in_function=false
                continue
            fi
            case $line in
            '}'*)
                printf 'Invalid plugin metadata: unsupported function closure at %s:%s\n' "$plugin_file" "$line_number" >&2
                return 78
                ;;
            esac
            continue
        fi

        if [[ $line =~ ^([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*\(\)[[:space:]]*\{[[:space:]]*$ ]]; then
            function_name=${BASH_REMATCH[1]}
            saw_function=true
            case $function_name in
            "update_$plugin_basename") has_update=true ;;
            "report_$plugin_basename") has_report=true ;;
            esac
            in_function=true
            continue
        fi

        case $line in
        '' | '#!'* | '#'*) continue ;;
        PLUGIN_NAME=*)
            if [ "$saw_function" = true ]; then
                printf 'Invalid plugin metadata: declaration after first function at %s:%s\n' "$plugin_file" "$line_number" >&2
                return 78
            fi
            name_count=$((name_count + 1))
            case $line in
            PLUGIN_NAME=\"*\")
                name=${line#PLUGIN_NAME=\"}
                name=${name%\"}
                ;;
            *)
                printf 'Invalid plugin metadata: PLUGIN_NAME must be a literal quoted string at %s:%s\n' "$plugin_file" "$line_number" >&2
                return 78
                ;;
            esac
            ;;
        PLUGIN_VERSION=*)
            if [ "$saw_function" = true ]; then
                printf 'Invalid plugin metadata: declaration after first function at %s:%s\n' "$plugin_file" "$line_number" >&2
                return 78
            fi
            version_count=$((version_count + 1))
            case $line in
            PLUGIN_VERSION=\"*\")
                version=${line#PLUGIN_VERSION=\"}
                version=${version%\"}
                ;;
            *)
                printf 'Invalid plugin metadata: PLUGIN_VERSION must be a literal quoted string at %s:%s\n' "$plugin_file" "$line_number" >&2
                return 78
                ;;
            esac
            ;;
        DISABLE=*)
            if [ "$saw_function" = true ]; then
                printf 'Invalid plugin metadata: declaration after first function at %s:%s\n' "$plugin_file" "$line_number" >&2
                return 78
            fi
            disabled_count=$((disabled_count + 1))
            case $line in
            DISABLE=true) disabled=true ;;
            DISABLE=false) disabled=false ;;
            *)
                printf 'Invalid plugin metadata: DISABLE must be true or false at %s:%s\n' "$plugin_file" "$line_number" >&2
                return 78
                ;;
            esac
            ;;
        PLUGIN_PRIORITY=*)
            if [ "$saw_function" = true ]; then
                printf 'Invalid plugin metadata: declaration after first function at %s:%s\n' "$plugin_file" "$line_number" >&2
                return 78
            fi
            priority_count=$((priority_count + 1))
            priority=${line#PLUGIN_PRIORITY=}
            case $priority in
            '' | *[!0-9]*)
                printf 'Invalid plugin metadata: PLUGIN_PRIORITY must be an integer at %s:%s\n' "$plugin_file" "$line_number" >&2
                return 78
                ;;
            esac
            ;;
        PLUGIN_TIMEOUT_SECONDS=*)
            if [ "$saw_function" = true ]; then
                printf 'Invalid plugin metadata: declaration after first function at %s:%s\n' "$plugin_file" "$line_number" >&2
                return 78
            fi
            timeout_count=$((timeout_count + 1))
            timeout_seconds=${line#PLUGIN_TIMEOUT_SECONDS=}
            case $timeout_seconds in
            '' | *[!0-9]*)
                printf 'Invalid plugin metadata: PLUGIN_TIMEOUT_SECONDS must be a positive integer at %s:%s\n' "$plugin_file" "$line_number" >&2
                return 78
                ;;
            esac
            case $timeout_seconds in
            *[1-9]*) ;;
            *)
                printf 'Invalid plugin metadata: PLUGIN_TIMEOUT_SECONDS must be a positive integer at %s:%s\n' "$plugin_file" "$line_number" >&2
                return 78
                ;;
            esac
            ;;
        PLUGIN_SCHEDULE_ACTION=*)
            if [ "$saw_function" = true ]; then
                printf 'Invalid plugin metadata: declaration after first function at %s:%s\n' "$plugin_file" "$line_number" >&2
                return 78
            fi
            action_count=$((action_count + 1))
            scheduled_action=${line#PLUGIN_SCHEDULE_ACTION=}
            case $scheduled_action in
            run | report | skip) ;;
            *)
                printf 'Invalid plugin metadata: PLUGIN_SCHEDULE_ACTION must be run, report, or skip at %s:%s\n' "$plugin_file" "$line_number" >&2
                return 78
                ;;
            esac
            ;;
        *)
            printf 'Invalid plugin metadata: executable top-level statement at %s:%s\n' "$plugin_file" "$line_number" >&2
            return 78
            ;;
        esac
    done <"$plugin_file"

    if [ "$in_function" = true ]; then
        printf 'Invalid plugin metadata: unterminated function body: %s\n' "$plugin_file" >&2
        return 78
    fi

    if [ "$name_count" -ne 1 ] || [ "$version_count" -ne 1 ] || [ "$disabled_count" -ne 1 ] ||
        [ "$priority_count" -ne 1 ] || [ "$timeout_count" -ne 1 ] || [ "$action_count" -ne 1 ]; then
        printf 'Invalid plugin metadata: exactly one of each required field is required: %s\n' "$plugin_file" >&2
        return 78
    fi

    case $name in
    '' | *"$(printf '\t')"* | *'"'* | *\\* | *'$'* | *'`'* | *';'* | *'|'* | *'&'* | *'<'* | *'>'*)
        printf 'Invalid plugin metadata: PLUGIN_NAME contains non-literal content: %s\n' "$plugin_file" >&2
        return 78
        ;;
    esac
    case $version in
    '' | *"$(printf '\t')"* | *'"'* | *\\* | *'$'* | *'`'* | *';'* | *'|'* | *'&'* | *'<'* | *'>'* | *[!a-zA-Z0-9._+-]*)
        printf 'Invalid plugin metadata: PLUGIN_VERSION contains non-literal content: %s\n' "$plugin_file" >&2
        return 78
        ;;
    esac

    if [ "$has_update" != true ]; then
        printf 'Invalid plugin metadata: missing update_%s: %s\n' "$plugin_basename" "$plugin_file" >&2
        return 78
    fi
    if [ "$scheduled_action" = report ] && [ "$has_report" != true ]; then
        printf 'Invalid plugin metadata: missing report_%s: %s\n' "$plugin_basename" "$plugin_file" >&2
        return 78
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$name" "$version" "$disabled" "$priority" "$timeout_seconds" "$scheduled_action"
}
