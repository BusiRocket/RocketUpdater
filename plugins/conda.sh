#!/bin/bash

PLUGIN_NAME="Conda"
PLUGIN_VERSION="1.0.0"
DISABLE=${DISABLE:-false} # To disable, set DISABLE=true

check_conda() {
    command -v conda >/dev/null 2>&1
}

update_conda() {
    if check_conda; then
        echo_yellow "Conda: Cleaning"
        conda clean --all -y

        echo_yellow "Conda: Updating Conda itself..."
        conda update --force-reinstall conda -y
        conda update -n base --force-reinstall conda -y

        echo_yellow "Conda: Updating all packages in the base environment..."
        conda update --force-reinstall -y --all

        LATEST_PYTHON_VERSION=$(curl -s --compressed https://www.python.org | LC_ALL=C sed -n 's/.*Latest: <a href="\/downloads\/release\/python-[0-9]*\/">Python \([0-9.]*\)<\/a>.*/\1/p')

        echo_yellow "Conda: Updating all packages and Python version in all environments..."

        while read -r line ; do
            if [[ $line != "#"* ]] && [[ ! -z "$line" ]] ; then
                regex_env="^([a-zA-Z0-9_-]+)"

                if [[ $line =~ $regex_env ]]; then
                    env_name=${BASH_REMATCH[1]}

                    echo_yellow "Processing environment: $env_name"

                    # echo_yellow "Updating Conda in environment $env_name..."
                    # conda update -n "$env_name" --force-reinstall conda -y

                    echo_yellow "Updating all packages in environment $env_name..."
                    conda update -n "$env_name" --force-reinstall --all -y

                    echo_yellow "Updating Python to the latest version in environment $env_name..."
                    conda install -n "$env_name" -c conda-forge python="$LATEST_PYTHON_VERSION" -y || conda install -n "$env_name" -c conda-forge python -y

                    echo_yellow "Updating pip in environment $env_name..."
                    conda install -n "$env_name" pip -y
                    conda run -n "$env_name" pip install --upgrade pip

                    echo_yellow "Installing pip-review in environment $env_name..."
                    conda run -n "$env_name" pip install pip-review

                    echo_yellow "Running pip-review to update all pip packages in environment $env_name..."
                    conda run -n "$env_name" pip-review --auto
                fi
            fi
        done < <(conda env list | tail -n +4 | awk '{print $1}')
    fi
}

update_conda
