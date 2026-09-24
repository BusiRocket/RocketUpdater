#!/bin/bash

# npm_script_allowed PACKAGE succeeds when a global update of PACKAGE must run
# the package's own install scripts. npm 12 blocks lifecycle scripts unless
# --allow-scripts names the package, and for these packages the script is what
# makes the installed binary runnable, so skipping it breaks them silently.
#
# pnpm 12: its preinstall swaps a shebang-less placeholder for the native
# binary. Left in place, a shell still runs it, but Node's spawnSync('pnpm')
# fails with ENOEXEC on macOS (2026-09-24, jscpd in pre-push hooks).
npm_script_allowed() {
    case $1 in
    pnpm) return 0 ;;
    *) return 1 ;;
    esac
}
