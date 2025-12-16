#!/bin/bash

PLUGIN_NAME="OMZSH"
PLUGIN_VERSION="1.1.0"
DISABLE=${DISABLE:-false}

check_omzsh() {
    [ -d "${ZSH:-$HOME/.oh-my-zsh}" ]
}

update_omzsh() {
    local zsh_dir="${ZSH:-$HOME/.oh-my-zsh}"
    
    if ! check_omzsh; then
        echo_skip "Oh My Zsh is not installed. Skipping..."
        return 0
    fi

    echo_info "Oh My Zsh: Updating..."
    
    # Check if upgrade script exists
    if [ -f "$zsh_dir/tools/upgrade.sh" ]; then
        # Run the upgrade script
        env ZSH="$zsh_dir" sh "$zsh_dir/tools/upgrade.sh" 2>&1 || {
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
                plugin_name=$(basename "$plugin_dir")
                echo "  → Updating plugin: $plugin_name"
                (cd "$plugin_dir" && git pull 2>&1) || echo_warning "Failed to update $plugin_name"
            fi
        done
    fi

    # Update custom themes
    if [ -d "$zsh_dir/custom/themes" ]; then
        echo_info "Oh My Zsh: Updating custom themes..."
        
        for theme_dir in "$zsh_dir/custom/themes"/*; do
            if [ -d "$theme_dir/.git" ]; then
                local theme_name
                theme_name=$(basename "$theme_dir")
                echo "  → Updating theme: $theme_name"
                (cd "$theme_dir" && git pull 2>&1) || echo_warning "Failed to update $theme_name"
            fi
        done
    fi

    echo_success "Oh My Zsh update completed"
    return 0
}
