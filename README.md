
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

Execute `./RocketUpdater.sh` to run every plugin in a supervised update pass, or
`./RocketUpdater.sh <plugin>` to run one plugin. Additional modes:

- `./RocketUpdater.sh --scheduled` — unattended mode for launchd: updates and
  reports only, never deletes, and never prompts for sudo.
- `./RocketUpdater.sh --preflight-only` (combinable with `--scheduled`) — runs
  and reports the fail-closed preflight without executing plugins.
- `./RocketUpdater.sh --clean <homebrew|npm|sparkle|all>` — supervised cleanup.
  It requires a real terminal, previews the exact candidates with their
  allocated KiB, and removes them only after you type the operation name.
  `all` still previews and confirms each operation separately.

Exit status 0 means no plugin failures; nonzero names every failure. A plugin
returning 20 means it skipped intentionally, 124 means it timed out, 75 means
another run holds the lock, and 78 means invalid configuration or preflight.

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

| Band  | Purpose                                                       | Plugins                                                                                                                       |
| ----- | ------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| 10-29 | Bootstrap: package managers the other plugins install through | `homebrew`, `brewhealth`                                                                                                       |
| 30-69 | Regular updaters and inventories (the default band)           | `composer`, `conda`, `gcloud`, `gopls`, `helm`, `npm`, `omzsh`, `pear`, `rust`, `yarn`, `msupdate`, `uvtools`, `sparkledrift`, `docker` |
| 70-99 | Reports, after everything has finished downloading            | `devcaches`, `sparklecache`, `cargosources`, `composerbackups`, `yarnmetadata`, `deno`, `platformio`, `bun`, `whispermodels`, `mole` |
| 100+  | System updates that may force a restart                       | `osx`                                                                                                                          |

Plugins sharing a priority run alphabetically, so the order is always
deterministic. The resolved order is printed at the start of a run.

Reports belong after the updaters: cache sizes measured first would be stale
the moment `brew`, `npm`, and `yarn` finish downloading. No plugin deletes
anything; the three guarded cleanup operations run only through `--clean`.

## Scheduling under launchd

The versioned sources live in [launchd/](launchd/) and are never installed
automatically:

| Source                                   | Installed as                              | Owner/mode        |
| ---------------------------------------- | ----------------------------------------- | ----------------- |
| `com.busirocket.rocketupdater.plist`     | `~/Library/LaunchAgents/<same name>`      | user, `0644`      |
| `rocketupdater.sudoers`                  | `/etc/sudoers.d/rocketupdater`            | `root:wheel 0440` |
| `rocketupdater.newsyslog.conf`           | `/etc/newsyslog.d/rocketupdater.conf`     | `root:wheel 0644` |

Validate the sources before installing anything:

```sh
plutil -lint launchd/com.busirocket.rocketupdater.plist
/usr/sbin/visudo -c -f launchd/rocketupdater.sudoers
./scripts/test-regressions.sh
```

Install the agent in preflight-only mode first, so the first scheduled wake
proves the environment without running a single update:

```sh
install -d -m 700 ~/Library/Logs/RocketUpdater ~/Library/Caches/RocketUpdater
install -m 644 launchd/com.busirocket.rocketupdater.plist \
    ~/Library/LaunchAgents/com.busirocket.rocketupdater.plist
/usr/libexec/PlistBuddy -c 'Add :ProgramArguments: string --preflight-only' \
    ~/Library/LaunchAgents/com.busirocket.rocketupdater.plist
launchctl bootstrap "gui/$UID" ~/Library/LaunchAgents/com.busirocket.rocketupdater.plist
launchctl kickstart -k "gui/$UID/com.busirocket.rocketupdater"
```

The gate passes when `launchctl print` reports `last exit code = 0`, the run's
only events are `run_start`, `preflight`, and `run_end` with `status=success`,
the logs are `0600`, and no ANSI escape reaches the captured output. Only then
remove `--preflight-only` and `bootout`/`bootstrap` again — `kickstart` does not
reload a changed plist.

The sudo allowlist is the sole unattended privilege. After installing it,
`sudo -n -l /usr/sbin/softwareupdate -d -r` must be allowed while
`sudo -n -l /usr/sbin/softwareupdate -i -a` must be denied. Until it is
installed, the `osx` plugin fails under `--scheduled` because it cannot obtain
the download grant.

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
