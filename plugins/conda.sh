#!/bin/bash

PLUGIN_NAME="Conda"
PLUGIN_VERSION="2.0.0"
DISABLE=false
PLUGIN_PRIORITY=50
PLUGIN_TIMEOUT_SECONDS=1800
PLUGIN_SCHEDULE_ACTION=run

check_conda() {
    command -v conda >/dev/null 2>&1
}

get_latest_stable_python() {
    # Get latest stable Python version from conda-forge
    # This is more reliable than scraping python.org
    local version
    version=$(conda search python -c conda-forge 2>/dev/null | grep -E "^python\s+" | tail -1 | awk '{print $2}')

    if [ -z "$version" ]; then
        # Fallback to a known stable version
        echo "3.14"
    else
        # Extract major.minor version
        echo "$version" | cut -d. -f1,2
    fi
}

# list_pypi_packages prints the packages conda attributes to the pypi channel,
# which are the only ones pip installed and may upgrade.
list_pypi_packages() {
    conda list -n "$1" 2>/dev/null | awk '!/^#/ && $NF == "pypi" { print $1 }'
}

update_conda_environment() {
    local env_name=$1
    local is_base=$2

    echo_info "Processing environment: $env_name"

    # Update all packages (skip --all for base to avoid removing conda deps like ruamel.yaml)
    if [ "$is_base" != "true" ]; then
        echo "  → Updating packages..."
        if ! conda update -n "$env_name" --all -y 2>&1; then
            echo_warning "Some packages in $env_name could not be updated"
        fi
    fi

    # Update Python: skip base (conda's own deps block python upgrade); other envs → latest (e.g. 3.14)
    if [ "$is_base" != "true" ]; then
        local latest_python
        latest_python=$(get_latest_stable_python)
        echo "  → Updating Python to $latest_python..."
        if ! conda install -n "$env_name" "python=$latest_python" -y 2>&1; then
            echo_skip "Python update to $latest_python skipped for $env_name (dependency conflicts)"
        fi
    fi

    # pip only for what pip installed: conda lists those from the `pypi`
    # channel. pip-review upgraded everything, conda's own packages included,
    # and on 2026-08-24 left base with a pydantic-core that pydantic refused,
    # which crashed every conda command. Base is conda itself, so pip stays out.
    if [ "$is_base" != "true" ]; then
        local pypi_packages
        pypi_packages=$(list_pypi_packages "$env_name")
        if [ -n "$pypi_packages" ]; then
            echo "  → Updating pip-installed packages..."
            local package
            for package in $pypi_packages; do
                conda run -n "$env_name" pip install --upgrade "$package" 2>&1 ||
                    echo_warning "pip could not upgrade $package in $env_name"
            done
        fi
    fi

    echo_success "Environment $env_name updated"
}

update_conda() {
    if ! check_conda; then
        echo_skip "Conda is not installed. Skipping..."
        return 20
    fi

    # Update conda itself: use only conda-forge so the latest conda (e.g. 26.1.1) is installed
    echo_info "Conda: Updating Conda..."
    local has_failures=0
    if ! conda update -n base -c conda-forge --override-channels conda -y 2>&1; then
        echo_error "Conda self-update failed; see the output above"
        has_failures=1
    fi

    # Skip "conda update -n base --all" to avoid RemoveError (ruamel.yaml etc.); base is updated per-env below

    # Get list of environments
    echo_info "Conda: Updating all environments..."

    local envs
    envs=$(conda env list | grep -v "^#" | grep -v "^$" | awk '{print $1}')

    for env_name in $envs; do
        if [ -n "$env_name" ] && [ "$env_name" != "#" ]; then
            if [ "$env_name" = "base" ]; then
                update_conda_environment "$env_name" true
            else
                update_conda_environment "$env_name" false
            fi
        fi
    done

    if [ "$has_failures" -ne 0 ]; then
        echo_error "Conda update completed with errors"
        return 1
    fi

    echo_success "Conda update completed"
    return 0
}
