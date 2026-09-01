#!/bin/bash

PLUGIN_NAME="OMZSH"
PLUGIN_VERSION="1.2.0"
DISABLE=false
PLUGIN_PRIORITY=50
PLUGIN_TIMEOUT_SECONDS=1800
PLUGIN_SCHEDULE_ACTION=run

check_omzsh() {
    [ -d "${ZSH:-$HOME/.oh-my-zsh}" ]
}

# A dropped TLS handshake to github.com ("LibreSSL SSL_connect:
# SSL_ERROR_SYSCALL") is a transient network failure, not a broken repository:
# the identical pull succeeds seconds later. Retry a bounded number of times so
# one blip cannot fail the whole run, while a genuinely unreachable remote is
# still reported as a failure.
git_pull_with_retry() {
    local repo_dir=$1
    local attempt=1
    local max_attempts=3

    while [ "$attempt" -le "$max_attempts" ]; do
        if (cd "$repo_dir" && git pull 2>&1); then
            return 0
        fi

        if [ "$attempt" -lt "$max_attempts" ]; then
            echo_warning "git pull failed on attempt $attempt/$max_attempts; retrying in 5 seconds..."
            sleep "${OMZSH_RETRY_DELAY_SECONDS:-5}"
        fi

        attempt=$((attempt + 1))
    done

    return 1
}

update_omzsh() {
    local zsh_dir="${ZSH:-$HOME/.oh-my-zsh}"
    local has_failures=0

    if ! check_omzsh; then
        echo_skip "Oh My Zsh is not installed. Skipping..."
        return 20
    fi

    echo_info "Oh My Zsh: Updating..."

    # Check if upgrade script exists
    if [ -f "$zsh_dir/tools/upgrade.sh" ]; then
        # Run the upgrade script with zsh (Oh My Zsh requires zsh, not sh)
        env ZSH="$zsh_dir" zsh "$zsh_dir/tools/upgrade.sh" 2>&1 || {
            echo_warning "Oh My Zsh upgrade script failed, trying git pull..."
            (cd "$zsh_dir" && git pull origin master 2>&1) || true
        }
    else
        # Fallback to git pull
        echo_info "Using git pull to update Oh My Zsh..."
        (cd "$zsh_dir" && git pull origin master 2>&1) || echo_warning "Git pull failed"
    fi

    # Update custom plugins
    if [ -d "$zsh_dir/custom/plugins" ]; then
        echo_info "Oh My Zsh: Updating custom plugins..."

        for plugin_dir in "$zsh_dir/custom/plugins"/*; do
            if [ -d "$plugin_dir/.git" ]; then
                local plugin_name
                local plugin_stash_created
                local plugin_stash_output
                plugin_name=$(basename "$plugin_dir")
                plugin_stash_created=false
                echo "  → Updating plugin: $plugin_name"

                if ! (cd "$plugin_dir" && git diff --quiet --ignore-submodules HEAD -- 2>/dev/null) || [ -n "$(cd "$plugin_dir" && git ls-files --others --exclude-standard 2>/dev/null)" ]; then
                    echo_info "Stashing local changes for $plugin_name..."
                    if ! plugin_stash_output=$(cd "$plugin_dir" && git stash push --include-untracked -m "RocketUpdater auto-stash" 2>&1); then
                        has_failures=1
                        echo_warning "Failed to stash local changes for $plugin_name"
                        continue
                    fi

                    printf '%s\n' "$plugin_stash_output"

                    if ! echo "$plugin_stash_output" | grep -q "No local changes to save"; then
                        plugin_stash_created=true
                    fi
                fi

                if ! git_pull_with_retry "$plugin_dir"; then
                    has_failures=1
                    echo_warning "Failed to update $plugin_name"
                    continue
                fi

                if [ "$plugin_stash_created" = true ]; then
                    echo_info "Restoring local changes for $plugin_name..."
                    if ! (cd "$plugin_dir" && git stash pop 2>&1); then
                        has_failures=1
                        echo_warning "Updated $plugin_name but could not restore stashed changes automatically"
                    fi
                fi
            fi
        done
    fi

    # Update custom themes
    if [ -d "$zsh_dir/custom/themes" ]; then
        echo_info "Oh My Zsh: Updating custom themes..."

        for theme_dir in "$zsh_dir/custom/themes"/*; do
            if [ -d "$theme_dir/.git" ]; then
                local theme_name
                local theme_stash_created
                local theme_stash_output
                theme_name=$(basename "$theme_dir")
                theme_stash_created=false
                echo "  → Updating theme: $theme_name"

                if ! (cd "$theme_dir" && git diff --quiet --ignore-submodules HEAD -- 2>/dev/null) || [ -n "$(cd "$theme_dir" && git ls-files --others --exclude-standard 2>/dev/null)" ]; then
                    echo_info "Stashing local changes for $theme_name..."
                    if ! theme_stash_output=$(cd "$theme_dir" && git stash push --include-untracked -m "RocketUpdater auto-stash" 2>&1); then
                        has_failures=1
                        echo_warning "Failed to stash local changes for $theme_name"
                        continue
                    fi

                    printf '%s\n' "$theme_stash_output"

                    if ! echo "$theme_stash_output" | grep -q "No local changes to save"; then
                        theme_stash_created=true
                    fi
                fi

                if ! git_pull_with_retry "$theme_dir"; then
                    has_failures=1
                    echo_warning "Failed to update $theme_name"
                    continue
                fi

                if [ "$theme_stash_created" = true ]; then
                    echo_info "Restoring local changes for $theme_name..."
                    if ! (cd "$theme_dir" && git stash pop 2>&1); then
                        has_failures=1
                        echo_warning "Updated $theme_name but could not restore stashed changes automatically"
                    fi
                fi
            fi
        done
    fi

    if [ "$has_failures" -eq 1 ]; then
        echo_error "Oh My Zsh update completed with errors"
        return 1
    fi

    echo_success "Oh My Zsh update completed"
    return 0
}
