#!/bin/bash

PLUGIN_NAME="Conda"
PLUGIN_VERSION="1.1.0"
DISABLE=${DISABLE:-false}

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
        echo "3.13"
    else
        # Extract major.minor version
        echo "$version" | cut -d. -f1,2
    fi
}

update_conda_environment() {
    local env_name=$1
    local is_base=$2
    
    echo_info "Processing environment: $env_name"
    
    # Update all packages in the environment
    echo "  → Updating packages..."
    if ! conda update -n "$env_name" --all -y 2>&1; then
        echo_warning "Some packages in $env_name could not be updated"
    fi
    
    # Update Python (don't force specific version, let conda resolve)
    echo "  → Updating Python..."
    if ! conda update -n "$env_name" python -y 2>&1; then
        echo_skip "Python update skipped for $env_name (dependency conflicts)"
    fi
    
    # Update pip
    echo "  → Updating pip..."
    conda install -n "$env_name" pip -y 2>/dev/null || true
    conda run -n "$env_name" pip install --upgrade pip 2>/dev/null || true
    
    # Update pip packages using pip-review if available
    echo "  → Updating pip packages..."
    if conda run -n "$env_name" pip show pip-review >/dev/null 2>&1; then
        conda run -n "$env_name" pip-review --auto 2>/dev/null || true
    else
        # Install pip-review and run it
        if conda run -n "$env_name" pip install pip-review 2>/dev/null; then
            conda run -n "$env_name" pip-review --auto 2>/dev/null || true
        fi
    fi
    
    echo_success "Environment $env_name updated"
}

update_conda() {
    if ! check_conda; then
        echo_skip "Conda is not installed. Skipping..."
        return 0
    fi

    # Clean conda cache
    echo_info "Conda: Cleaning cache..."
    conda clean --all -y 2>&1 || true

    # Update conda itself
    echo_info "Conda: Updating Conda..."
    conda update -n base conda -y 2>&1 || echo_warning "Conda self-update failed"

    # Update base environment packages
    echo_info "Conda: Updating base environment packages..."
    conda update -n base --all -y 2>&1 || echo_warning "Some base packages could not be updated"

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

    echo_success "Conda update completed"
    return 0
}
