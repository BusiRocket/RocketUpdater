
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
