#!/bin/bash

PLUGIN_NAME="Rust"
PLUGIN_VERSION="1.0.4"
DISABLE=${DISABLE:-false}

check_rustup() {
    command_exists rustup
}

check_cargo_install_update_subcommand() {
    # Provided by the "cargo-update" crate (installed via `cargo install cargo-update`).
    # Invoke it the canonical way — as a cargo subcommand — so cargo dispatches to the
    # real `cargo-install-update` binary. That binary still expects `install-update` as
    # its first argument even when called directly, so `cargo-install-update --all` fails
    # with "Usage: cargo <COMMAND>"; the `cargo install-update` dispatch is the only
    # reliable form.
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
    if check_cargo_install_update_subcommand; then
        cargo install-update --all 2>&1 || echo_warning "cargo install-update failed"
    else
        echo_skip "Cargo binaries update skipped (cargo-update not installed)"
        echo_info "  → Install with: cargo install cargo-update"
    fi

    echo_success "Rust update completed"
    return 0
}
