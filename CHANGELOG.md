# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Launchd-safe runner: native `lockf` single-instance locking, static plugin
  metadata validation without executing plugin code, per-plugin child
  processes with bounded timeouts, structured 0600 event logging, and a
  fail-closed preflight (`--preflight-only`) that records disk, power, load,
  backup, FDA, DNS, and required binaries.
- Mode-aware CLI: `--scheduled` updates and reports with zero reachable
  deletion and no sudo probing; a TTY-only `--clean <homebrew|npm|sparkle|all>`
  dispatches guarded, typed-confirmation cleanup operations.
- Global npm package-tree integrity snapshots around `npm install -g` and the
  Homebrew `node` formula upgrade; damage to any non-target package stops
  further global updates and is logged as a structured integrity event.
- New verified plugins: `brewhealth`, `gopls`, `helm` (inventory), `msupdate`
  (inventory), `uvtools`, `sparkledrift` (feed evidence), `sparklecache`
  (staged-installation report), `cargosources`, `composerbackups`,
  `yarnmetadata`, `deno`, `platformio`, `bun`, and `whispermodels` — every one
  update- or report-only, with bounded timeouts and truthful exit statuses.
- Guarded `--clean sparkle` operation that removes only verified obsolete
  stopped-app ChatGPT Sparkle staged installations after a typed confirmation
  and a byte-identical re-enumeration; `PersistentDownloads` stays report-only.

### Changed

- Homebrew 2.0.0: per-item formula and cask upgrades (greedy only for
  `codexbar` and `goplaces`), no blanket `--greedy` retries, and
  `brew cleanup` moved behind the manual `--clean homebrew` guard.
- Docker 2.0.0 and Mole 2.0.0 are report-only (`docker system df`,
  `mo clean --dry-run`); all pruning is a recorded human decision.
- OSX 2.0.0 downloads updates with `softwareupdate -d -r` only, reports
  restart-required as a terminal state, and reports Chrome caches instead of
  deleting them; `sudo purge` is gone.
- Composer, Conda, DevCaches, NPM, and Yarn 2.0.0 no longer delete any cache;
  npm cache removal lives only behind the manual `--clean npm` guard, and the
  NPX plugin is retired with its `_npx` size folded into the npm report.
- A missing tool now skips a plugin with status 20, and core update failures
  return nonzero instead of hiding behind warnings.
- The `omzsh` plugin retries a failed `git pull` up to three times. A dropped
  TLS handshake to github.com (`LibreSSL SSL_connect: SSL_ERROR_SYSCALL`) is a
  transient network failure that succeeds on the next attempt, and one blip
  should not fail an entire unattended run; a remote that stays unreachable is
  still reported as a failure. A missing Oh My Zsh now skips with status 20
  instead of reporting success.
- The `pear` plugin resolves PEAR's real package tree instead of trusting
  php.ini's `include_path`. Homebrew's php formula points the path at a
  skeleton inside the Cellar while the packages live under the prefix, which
  made every `pear`/`pecl` command die with
  `Failed opening required 'Console/Getopt.php'`. It also leaves the `PEAR`
  package itself to `brew upgrade php` under a Homebrew-managed PHP, because
  upgrading it tries to replace read-only Cellar binaries and can only end in
  `ERROR: commit failed`; the remaining packages are upgraded individually.
- `brewhealth` splits severity: a formula whose dependency is missing fails the
  run, while `brew doctor` and the autoremove preview are reported without
  failing. `brew doctor` is advisory by Homebrew's own definition and always
  has something to say on a lived-in machine, so failing on it made every run
  permanently red and taught the reader to ignore failures.
- The `pear` plugin no longer parses a PHP stack trace as the PECL package
  list. A broken PEAR install makes `pecl list` die with a fatal error, and the
  old code turned its stack-trace lines into package names, attempting eight
  bogus upgrades of `Warning:`, `Fatal`, `Stack`, `#0`-`#3` and `thrown`. The
  listing must now succeed, and only names matching a package-name pattern are
  upgraded.
- `report_mole` raises Mole's own `MOLE_TIMEOUT_DISK_VERIFY_SEC` size-check
  budget to 120 seconds and treats a dry run that Mole itself abandons as an
  incomplete measurement (status 20) rather than a failure, so an informational
  report cannot mark a whole scheduled run failed. Any other nonzero exit, or
  unrecognized output, still fails loudly. It also reports the binary's SHA-256
  as its identity because this Mole build exposes no version string.

- Root access is requested once at the start of a run, while stdin is still the
  terminal, and the grant is refreshed until the run finishes so it does not
  expire before the steps that need it. Declining continues the run.

### Changed

- Privileged steps in the `pear` plugin fall back to an unprivileged attempt
  instead of being skipped: without a grant, and also when the privileged
  command itself fails for any reason.

### Fixed

- A failed `pear`/`pecl` upgrade is reported as a failure. The plugin returned
  success unconditionally, so the summary could claim every plugin succeeded
  with `ERROR: commit failed` on screen.
- When a privileged attempt fails, the reason is printed. It was discarded, so
  "retrying without sudo" read the same whether sudo was refused, the ticket had
  expired, or the command itself errored.
- The `gcloud` plugin repairs the `gcloud-cli` cask after Homebrew reverts its
  upgrade. The cask's postflight builds a Python virtualenv by pip-installing
  wheels from github.com; under the `brew` process that pip fails DNS resolution
  and the upgrade rolls back, leaving the SDK files at the new version but the
  `bin` wrappers unlinked so `gcloud` disappears from `PATH`. The plugin now
  runs after Homebrew and, idempotently, relinks the wrappers and rebuilds the
  optional virtualenv, both of which succeed outside the `brew` environment.

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
