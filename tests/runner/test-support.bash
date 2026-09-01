#!/bin/bash

runner_fixture_create() {
    local root_dir=$1
    local fixture_name=$2
    local fixture_dir

    fixture_dir=$(mktemp -d "$root_dir/.runner-fixture-${fixture_name}.XXXXXX")
    mkdir -p "$fixture_dir/bin" "$fixture_dir/home" "$fixture_dir/plugins"
    cp "$root_dir/RocketUpdater.sh" "$fixture_dir/RocketUpdater.sh"
    cp -R "$root_dir/lib" "$fixture_dir/lib"
    cp -R "$root_dir/scripts" "$fixture_dir/scripts"
    if [ -d "$root_dir/cleanup" ]; then
        cp -R "$root_dir/cleanup" "$fixture_dir/cleanup"
    fi
    cat >"$fixture_dir/bin/sudo" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$RUNNER_TEST_STATE/sudo.log"
exit 1
EOF
    chmod +x "$fixture_dir/bin/sudo"
    printf '%s\n' "$fixture_dir"
}

runner_fixture_cleanup() {
    /bin/rm -rf -- "$1"
}
