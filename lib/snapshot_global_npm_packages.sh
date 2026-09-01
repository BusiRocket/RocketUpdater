#!/bin/bash

# snapshot_global_npm_packages prints one sorted TSV record per immediate
# global npm package: name, path, package.json SHA-256, declared name,
# declared version, and whether every declared bin/entrypoint exists.
# It never trusts `npm ls -g` (which reports a broken tree as healthy) and
# rejects a symlinked or non-user-owned global root.
snapshot_global_npm_packages() {
    local npm_root
    npm_root=$(npm root -g 2>/dev/null)

    if [ -z "$npm_root" ] || [ -L "$npm_root" ] || [ ! -d "$npm_root" ] ||
        [ ! -O "$npm_root" ]; then
        printf 'Global npm root is missing, symlinked, or not user-owned: %s\n' \
            "$npm_root" >&2
        return 1
    fi

    local package_dir
    for package_dir in "$npm_root"/* "$npm_root"/@*/*; do
        [ -d "$package_dir" ] || continue

        local package_name=${package_dir#"$npm_root"/}
        case $package_name in
        .* | '@'*/'') continue ;;
        '@'*) [ "${package_name#*/}" != "$package_name" ] || continue ;;
        esac

        local manifest="$package_dir/package.json"
        local manifest_sha=missing
        local declared_name=missing
        local declared_version=missing
        local bins_status=none

        if [ -f "$manifest" ]; then
            manifest_sha=$(shasum -a 256 "$manifest" 2>/dev/null | awk '{ print $1 }')
            [ -n "$manifest_sha" ] || manifest_sha=unreadable

            local flat_manifest
            flat_manifest=$(tr '\n' ' ' <"$manifest")
            declared_name=$(printf '%s' "$flat_manifest" |
                sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
            declared_version=$(printf '%s' "$flat_manifest" |
                sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
            [ -n "$declared_name" ] || declared_name=unparsed
            [ -n "$declared_version" ] || declared_version=unparsed

            local declared_targets
            declared_targets=$(printf '%s' "$flat_manifest" |
                sed -n 's/.*"bin"[[:space:]]*:[[:space:]]*{\([^}]*\)}.*/\1/p' |
                sed 's/,/\n/g' |
                sed -n 's/.*:[[:space:]]*"\([^"]*\)".*/\1/p')
            if [ -z "$declared_targets" ]; then
                declared_targets=$(printf '%s' "$flat_manifest" |
                    sed -n 's/.*"bin"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
            fi
            local main_target
            main_target=$(printf '%s' "$flat_manifest" |
                sed -n 's/.*"main"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
            if [ -n "$main_target" ]; then
                declared_targets=$(printf '%s\n%s' "$declared_targets" "$main_target")
            fi

            local declared_target
            while IFS= read -r declared_target; do
                [ -n "$declared_target" ] || continue
                bins_status=ok
                if [ ! -e "$package_dir/$declared_target" ]; then
                    bins_status=missing
                    break
                fi
            done <<<"$declared_targets"
        fi

        printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$package_name" "$package_dir" "$manifest_sha" \
            "$declared_name" "$declared_version" "$bins_status"
    done | LC_ALL=C sort
}
