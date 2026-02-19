#!/bin/bash

PLUGIN_NAME="Rust"
PLUGIN_VERSION="1.0.2"
DISABLE=${DISABLE:-false}

check_rustup() {
    command_exists rustup
}

check_cargo_install_update() {
    # Provided by the "cargo-update" crate (installed via `cargo install cargo-update`)
    command_exists cargo-install-update
}

is_real_cargo_install_update() {
    # Some setups may have a shim/symlink that actually invokes plain `cargo`,
    # which would fail with "USAGE: cargo <SUBCOMMAND>" when we pass flags.
    local help_out
    help_out=$(cargo-install-update --help 2>&1 || true)

    # Match the actual help format which spans multiple lines:
    # USAGE:
    #     cargo <SUBCOMMAND>
    if echo "$help_out" | grep -q "cargo <SUBCOMMAND>"; then
        return 1
    fi

    return 0
}

check_cargo_install_update_subcommand() {
    command_exists cargo && cargo install-update --help >/dev/null 2>&1
}

update_rust() {
    if ! check_rustup; then
        echo_skip "Rustup is not installed. Skipping..."
        echo_info "  → Install with: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
        return 0
    fi

    # Keep rustup itself up to date (no-op if already current)
    echo_info "Rust: Updating rustup..."
    rustup self update 2>&1 || echo_warning "rustup self update failed"

    # Update all installed toolchains and their installed components (e.g., rustfmt/clippy if present)
    echo_info "Rust: Updating toolchains..."
    rustup update 2>&1 || {
        echo_error "Rust: rustup update failed"
        return 1
    }

    # Optionally update cargo-installed binaries if the helper is available
    echo_info "Rust: Updating cargo-installed binaries..."
    if check_cargo_install_update && is_real_cargo_install_update; then
        cargo-install-update --all 2>&1 || echo_warning "cargo-install-update failed"
    elif check_cargo_install_update_subcommand; then
        cargo install-update --all 2>&1 || echo_warning "cargo install-update failed"
    else
        echo_skip "Cargo binaries update skipped (cargo-update not installed)"
        echo_info "  → Install with: cargo install cargo-update"
    fi

    echo_success "Rust update completed"
    return 0
}
