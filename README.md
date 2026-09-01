
# RocketUpdater

**RocketUpdater** is a comprehensive and powerful tool designed to automate the update process of various system utilities and development tools. With RocketUpdater, you can ensure that all your essential tools are always up-to-date, providing you with the latest features and security improvements without the hassle of manual updates.

## Features

- **Homebrew Integration**: Automatically update, upgrade, and clean Homebrew packages.
- **NPM and Yarn Support**: Update global NPM packages and the Yarn version effortlessly.
- **Composer Maintenance**: Clear cache, self-update Composer, and update global Composer packages.
- **Rust Toolchain Updates**: Update Rust toolchains via rustup (and optionally cargo-installed binaries).
- **Conda Environment Management**: Deactivate current Conda environments, update Conda itself, and ensure all environments have the latest Python version and packages.
- **Docker Cleanup**: Remove exited containers and unused images to free up space.
- **Mole Integration**: Run [Mole](https://mole.fit) (`mo clean`) as a plugin for a deep, whitelist-aware macOS cache cleanup.
- **Dev Cache Cleanup**: Prune uv, pnpm store, and pip caches not covered by other plugins.
- **macOS Updates**: Keep your macOS up-to-date with the latest software updates.
- **PEAR and PECL Updates**: Clear cache and upgrade PEAR and PECL packages.
- **Additional Utilities**: Update Browsers List with npx.

## Installation

1. Clone the repository:
   ```sh
   git clone https://github.com/BusiRocket/RocketUpdater.git
   ```

2. Navigate to the project directory:
   ```sh
   cd RocketUpdater
   ```

3. Make the script executable:
   ```sh
   chmod +x RocketUpdater.sh
   ```

4. Run the script:
   ```sh
   ./RocketUpdater.sh
   ```

## Usage

Simply execute the `RocketUpdater.sh` script to begin the update process. The script will guide you through updating and cleaning various tools and environments.

## Root access

Some steps do more as root: PEAR and PECL write into system directories, and the
macOS plugin downloads recommended system updates. RocketUpdater asks for your
password once, at the start of the run, and keeps the grant alive until it
finishes.

Declining is a supported answer. Press Ctrl-D and the run continues; the steps
that wanted root are attempted unprivileged instead of being skipped. The same
fallback applies when a privileged command fails for any other reason, so a
`sudo` that is granted but cannot run the command still ends with an attempt
rather than an error.

Plugins never prompt on their own. They run with no stdin, so a tool that asks a
question gets EOF and fails on the record instead of stalling the run on a
prompt that may not even be visible. When there is no terminal at all (cron, CI)
the password step is skipped with a note.

## Plugin order

Plugins run in priority order, in the style of SysV init sequence numbers:
lower runs first, and the gaps leave room to insert a plugin without
renumbering the rest. A plugin declares its position with `PLUGIN_PRIORITY`:

```sh
PLUGIN_PRIORITY=10
```

| Band     | Purpose                                                        | Plugins                    |
| -------- | -------------------------------------------------------------- | -------------------------- |
| 10-29    | Bootstrap: package managers the other plugins install through   | `homebrew`                 |
| 30-69    | Regular updaters (the default band)                             | everything else            |
| 70-99    | Cleanup, after everything has finished downloading              | `docker`, `devcaches`, `mole` |
| 100+     | System updates that may force a restart                         | `osx`                      |

A plugin that does not care about its position omits `PLUGIN_PRIORITY` and gets
the default of `50`. Plugins sharing a priority run alphabetically, so the order
is always deterministic. The resolved order is printed at the start of a run.

Cleanup belongs after the updaters: pruning caches first only frees space that
`brew`, `npm`, and `yarn` refill minutes later.

## Shell plugin sources

The Oh My Zsh custom repositories under `~/.oh-my-zsh/custom` are the canonical
sourced copies of `powerlevel10k`, `zsh-autosuggestions`, and
`zsh-syntax-highlighting`. The Homebrew formulae with the same names are shadow
installs that `.zshrc` does not source. No plugin or scheduled command
uninstalls them; the one-off decision to remove the three shadow formulae is
recorded in [TODO.md](TODO.md) and requires human approval.

## Formatting and linting

Shell scripts are formatted with [shfmt](https://github.com/patrickvane/shfmt) and linted with [shellcheck](https://www.shellcheck.net/). Install them (`brew install shfmt shellcheck`), then:

- **Format all scripts:** `./scripts/format.sh`
- **Check formatting only (CI):** `./scripts/format.sh --check`
- **Lint all scripts:** `./scripts/lint.sh` (defaults to the strictest `style` severity; pass `warning` or `error` to relax it)
- **Regression tests:** `./scripts/test-regressions.sh`

Indent and style are defined in [.editorconfig](.editorconfig); project-wide shellcheck exclusions in [.shellcheckrc](.shellcheckrc).

## Contributing

We welcome contributions from the community! If you have suggestions for new features or improvements, feel free to open an issue or submit a pull request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
