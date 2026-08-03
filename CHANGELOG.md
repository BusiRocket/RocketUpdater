# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Root access is requested once at the start of a run, while stdin is still the
  terminal, and the grant is refreshed until the run finishes so it does not
  expire before the steps that need it. Declining continues the run.

### Changed

- Privileged steps in the `pear` plugin fall back to an unprivileged attempt
  instead of being skipped: without a grant, and also when the privileged
  command itself fails for any reason.

## [1.0.0] - 2026-08-03

First tagged release. The tool has been in daily use for some time; this entry
covers what it contains, with the changes since the previous cleanup called out
individually.

### Added

- Plugin architecture: each updater is a self-contained script under `plugins/`
  exposing an `update_<name>` function, sourced and dispatched by
  `RocketUpdater.sh`. Fourteen ship with it: `homebrew`, `composer`, `conda`,
  `gcloud`, `npm`, `npx`, `omzsh`, `pear`, `rust`, `yarn`, `docker`,
  `devcaches`, `mole`, `osx`.
- Priority-based execution order. Plugins declare `PLUGIN_PRIORITY` in the style
  of SysV init sequence numbers, so updaters run before cleanup and system
  updates run last. Only the plugins whose position matters declare one; the
  rest default to 50 and tie-break alphabetically. The resolved order is printed
  at the start of a run.
- Run a single plugin with `./RocketUpdater.sh <plugin>`.
- Summary report counting successful, failed and skipped plugins, naming the
  ones that failed, and exiting non-zero when any did.
- `DISABLE=true` to turn off an individual plugin.
- `scripts/format.sh` (shfmt), `scripts/lint.sh` (shellcheck) and
  `scripts/test-regressions.sh`.

### Fixed

- A plugin reading stdin no longer truncates the run. The plugin list is read on
  fd 3, and plugins are given no stdin at all, so a tool that prompts gets EOF
  and fails on the record instead of stalling the run on a question written to a
  discarded stderr.
- The `yarn` plugin no longer blocks forever when `yarn` is a Corepack shim. The
  shim enables Corepack's download prompt, which asks on stdin before fetching
  the pinned release; the plugin now disables it, keeping the download.
- The `pear` plugin degrades instead of failing when sudo has no cached
  credentials: it checks once, then skips the privileged steps with a message
  naming the fix.
- A single broken cask or formula no longer aborts the Homebrew step or skips
  its cleanup.
- Homebrew tap-trust prompts no longer cause formulae to be silently skipped.
- Oh My Zsh custom plugins and themes with local changes are stashed and
  restored around the update instead of blocking it.
- Cargo-installed binaries update through `cargo install-update`.
- Conda skips the base environment when updating Python and avoids dependency
  conflicts during package updates.

### Changed

- The whole tree is shfmt-formatted and passes shellcheck at its strictest
  severity. Project-wide policy lives in `.shellcheckrc`.

[1.0.0]: https://github.com/BusiRocket/RocketUpdater/releases/tag/v1.0.0
