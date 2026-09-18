#!/bin/bash

# list_formula_npm_packages FORMULA prints, one per line, the global npm
# package names a Homebrew formula installs itself: every
# lib/node_modules/<name>/package.json (scoped names included) the formula's
# keg contains. The node formula ships npm this way, so an upgrade rewrites
# that package by design; nothing installed with `npm install -g` is listed.
list_formula_npm_packages() {
    local formula=$1

    brew ls --verbose --formula "$formula" 2>/dev/null | awk -F/ '
        $NF != "package.json" { next }
        NF >= 4 && $(NF-2) == "node_modules" && $(NF-3) == "lib" && $(NF-1) !~ /^@/ {
            print $(NF-1)
            next
        }
        NF >= 5 && $(NF-3) == "node_modules" && $(NF-4) == "lib" && $(NF-2) ~ /^@/ {
            print $(NF-2) "/" $(NF-1)
        }
    ' | LC_ALL=C sort -u
}
