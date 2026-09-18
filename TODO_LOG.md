# TODO Log

> Searchable record of closed project work. Active work lives in `TODO.md`.

## 2026

### 2026-09

- [x] 2026-09-19 — **Plugins:** Node formula upgrade tripped the global npm
  integrity guard.
  - Result: the full run of 2026-09-19 upgraded node 26.8.2 to 26.9.0 and
    the guard reported `integrity_violation package=npm kind=changed`, failing
    homebrew on both machines. The formula ships npm itself (`brew ls
    --verbose node` lists `libexec/lib/node_modules/npm/package.json`), so the
    rewrite is the upgrade working as designed. The plugin now reads the
    packages the formula owns and excludes them from both snapshots before the
    comparison; a foreign package changed by the same upgrade is still
    reported.
  - Evidence: `tests/plugins/homebrew-node-bundled-npm.sh` (RED against the
    old plugin, GREEN after; drives `scripts/run-plugin.sh` so the library
    wiring is covered); `./scripts/test-regressions.sh` all passed;
    `./scripts/lint.sh` 92 scripts clean.
  - Files: `lib/list_formula_npm_packages.sh`,
    `lib/exclude_npm_snapshot_packages.sh`, `plugins/homebrew.sh`,
    `scripts/run-plugin.sh`, `CHANGELOG.md`.

- [x] 2026-09-19 — **Plugins:** `osx` failed on the volume-owner password
  prompt for a macOS release.
  - Result: `sudo -n /usr/sbin/softwareupdate -d -r` stops at a volume-owner
    password prompt when it prepares a macOS release, which no run without a
    terminal can answer: `Failed to authenticate` after macOS 26.7 had
    downloaded on the MacBook (macOS 27 next in the list), and
    `com.apple.LocalAuthentication ... Password rejected (3)` while preparing
    macOS 26.7 itself on the Mac mini (Spanish locale, NOPASSWD sudo). The
    first fix assumed only major upgrades were affected; the mini run
    disproved it. The sudoers rule allows only that exact argv, so the
    download cannot be narrowed without a privileged change. Plugin v2.1.0
    detects a listed `macOS` release together with either wording, reports
    the release as a manual install from System Settings (noting that updates
    listed after it may not have downloaded) and succeeds. Other download
    failures still fail. Safari 27 is not mistaken for a macOS release, and
    the real label carries a non-breaking space (U+00A0) after `macOS`, which
    the first regex missed on the validation run; the test pins the
    byte-exact listing and both failure wordings.
    Assumption recorded: unattended preparation of a macOS release is never
    achievable without a terminal, so reporting it instead of failing changes
    nothing a user would miss.
  - Evidence: `tests/plugins/osx-os-update-auth.sh` (RED before, GREEN
    after), `tests/runner/sudo-mode.sh` still pins the single sudo argv;
    suite and shellcheck green; MacBook run 3 `run_end status=success
    total=27 successful=25 failed=0 skipped=2` (242s).
  - Files: `lib/list_macos_os_updates.sh`, `plugins/osx.sh`,
    `tests/plugins/osx.sh`, `scripts/run-plugin.sh`, `CHANGELOG.md`.

- [x] 2026-09-12 — **Plugins:** `plugins/bun.sh` fails whenever the run's cwd
  has no `package.json`.
  - Result: `bun pm cache` exits 1 with `error: No package.json was found for
    directory ...` (full run 2026-09-12, the only failed plugin of 27). The
    plugin now falls back to `${BUN_INSTALL:-$HOME/.bun}/install/cache` with a
    warning.
  - Evidence: commit 20a464f; verified from `$HOME` on the mini, where the
    scheduled run had failed.
  - Files: `plugins/bun.sh`.

- [x] 2026-09-08 — **Repository:** `.serena/` is local language-server state,
  not project content.
  - Result: added to `.gitignore`, so both checkouts stop reporting it as
    untracked. This also closes the copy in `~/p/osseus/TODO.md`.
  - Files: `.gitignore`.

- [-] 2026-09-08 — **Repository:** U+FE0F hygiene — do not strip it.
  - Resolution: the selector survives in exactly one file, `lib/print_message.sh`,
    on three characters: `ℹ️` (U+2139), `⏭️` (U+23ED) and `⚠️` (U+26A0). Those
    three have a text presentation by default, so removing VS16 turns the run's
    prefixes into monochrome glyphs — it degrades the output rather than
    cleaning it. If a variation-selector CI scan is ever added, allowlist these
    three; that is the correct fix here.

- [x] 2026-09-08 — **Plugins:** Helm checksum verification automated, replacing
  the by-hand procedure below.
  - Result: `plugins/helm.sh` v1.1.0 verifies every installed plugin binary on
    each run through four libraries: `helm_plugin_release_source` names the
    release assets for a plugin and platform, `helm_reference_digest` fetches
    the published checksums, confirms the archive against them and streams the
    archived binary into `shasum`, `find_helm_plugin_directory` maps a declared
    plugin name to its installation directory (they differ — `dashboard`
    installs into `helm-dashboard.git`), and `classify_helm_plugin_binary`
    compares the two digests. Three outcomes, deliberately distinct: `verified`
    is a byte-identical match; `mismatch` fails the plugin and prints both
    digests so the finding can be reproduced by hand; `unverifiable` only
    warns — an unreachable or corrupt download says nothing about the installed
    file, and failing the run on it is how a verification step becomes noise
    people learn to ignore. Nothing is ever extracted to disk: the archive
    member is streamed into `shasum`, so an archive that fails its checksum
    never becomes a file, and no recursive delete is needed — which is what
    `tests/runner/cleanup-safety.sh` demands. The reference digest is cached
    per plugin and version, because the archives are 78 MiB and 71 MiB and the
    answer cannot change for a released version; a warm run is one local hash.
  - Lesson: the libraries were sourced in `RocketUpdater.sh`, but plugins
    execute in `scripts/run-plugin.sh`, which loads its own list. Every helper
    worked, the runner loaded none of them, and the plugin reported "no plugins
    to verify" and exited 0 — a pass meaning the opposite of what it said. The
    tests had hand-sourced the libraries and so could not see it.
    `tests/plugins/helm-checksum-verified.sh` now drives `scripts/run-plugin.sh`
    instead, and fails if the runner stops loading them.
  - Evidence: `./scripts/test-regressions.sh` green (29 contracts); the real
    run reproduces the hand-verified digests exactly: `diff` →
    `0fff52a0...6e6a9cd`, `dashboard` → `01faebb0...d737630`. Commit d9a3494.
  - Files: `plugins/helm.sh`, `lib/helm_plugin_release_source.sh`,
    `lib/helm_reference_digest.sh`, `lib/find_helm_plugin_directory.sh`,
    `lib/classify_helm_plugin_binary.sh`, `scripts/run-plugin.sh`,
    `tests/plugins/helm-checksum-*.sh`.

- [x] 2026-09-08 — **Host maintenance:** Helm plugins updated on the owner's
  approval — `diff` 3.14.1 to 3.15.12 and `dashboard` 2.0.3 to 2.1.3 — with the
  verification their own installers skip done by hand.
  - Result: both plugin directories were copied to the session scratchpad first
    (rollback is a `cp -R` away). The upstream release tarball was downloaded
    separately and checked against the checksum file the project publishes:
    `helm-diff-macos-arm64.tgz` → `cb9e5b6c...632b580`,
    `helm-dashboard_2.1.3_Darwin_arm64.tar.gz` → `0d6cb213...dedff85`, both
    matched. The verified tarball was extracted and its binary hashed, the
    plugin updated through helm, then the installed binary hashed and compared:
    `diff` → `0fff52a0...6e6a9cd`, `helm-dashboard` → `01faebb0...d737630`,
    both identical to the verified reference. `helm diff version` answers
    3.15.12, `helm dashboard --version` answers 2.1.3, helm v4.2.4 still lists
    both plugins.
  - Finding that made this a decision: `helm-diff`'s `install-binary.sh` does
    not verify anything — its `installFile` comment says "verifies the SHA256
    for the file" and the function only untars and copies, a leftover comment
    from the template it was copied from. `helm plugin update diff` therefore
    installs an unverified download. Now automated by the entry above.

- [x] 2026-09-08 — **Host maintenance:** Helm plugin directory cleaned.
  - Result: `~/Library/helm/plugins` held eight dangling symlinks from April —
    six `skaffold-render*` and two `tmp.*` pointing into `/var/folders/.../T/`
    paths macOS has long since cleared. Only the links were removed.
  - Evidence: `helm plugin list` still reports both real plugins.

- [x] 2026-09-08 — **Host maintenance:** pip user packages audited, and they
  stay.
  - Result: `lxml` 6.1.1 and `pandas` 3.0.3 in
    `~/Library/Python/3.14/lib/python/site-packages` are live dependencies:
    `brain/tools/caixabank/convertCardXls.py` and
    `brain/tools/forense/{analyze,classify}.py` import pandas (analyze also
    numpy), and the docx/xlsx skill validators under `rocket-agents-library`
    import lxml. No old-pandas API use turned up — the `.append(` hits are
    reportlab story lists, not DataFrames. Never upgrade these unbounded: the
    consumers are financial and forensic scripts whose output nobody re-checks
    by hand.

- [x] 2026-09-08 — **Host maintenance:** Shadow zsh formulae removed (about
  5 MiB; the point was the shadowing, not the space).
  - Result: `.zshrc` sets `ZSH_THEME="powerlevel10k/powerlevel10k"` and lists
    `zsh-syntax-highlighting` and `zsh-autosuggestions` in `plugins=(...)`, all
    resolved from `~/.oh-my-zsh/custom`; nothing sourced
    `/opt/homebrew/share/zsh-*` and no formula depended on the three. After
    `brew uninstall --formula powerlevel10k zsh-autosuggestions zsh-syntax-highlighting`
    a real interactive shell still reports `theme=powerlevel10k/powerlevel10k`,
    both plugins loaded and the `p10k` function present.
  - Note for future shell checks: `.zshrc` takes an early agent path when
    `CLAUDECODE`, `CODEX_AGENT` and similar are set, so a shell started from an
    agent session loads none of this. Verify with those variables unset, under
    a pty, or the result is a false negative.

- [x] 2026-09-08 — **Host maintenance:** OpenClaw gateway decommission verified
  gone.
  - Result: no `~/Library/LaunchAgents/ai.openclaw.gateway.plist`, `launchctl
    print gui/501/ai.openclaw.gateway` reports the service is not in the
    domain, no gateway process is running and no `~/Library/Logs/openclaw*`
    remains. Only the retained plist under `LaunchAgents/disabled/` is left, as
    intended (SHA-256
    `3c50e470ae6e9a2e8e8a6c0e98644f5b3a6afa9b164a0537448d2cf2190d2501`).
  - Original finding: a launchd job repeatedly executed Node against absent
    `/opt/homebrew/lib/node_modules/openclaw/dist/index.js`, producing
    `MODULE_NOT_FOUND`: `spawn scheduled`, 128,122 runs, last exit 1, and a
    3,328,859,672-byte error log growing 3,068 bytes per four seconds. Do not
    create a RocketUpdater OpenClaw plugin or newsyslog rule. If any part of
    the live job or log reappears, use the idempotent supervised sequence:
    `launchctl bootout gui/$(id -u)/ai.openclaw.gateway`, move the active
    plist to `~/Library/LaunchAgents/disabled/` (refuse if a retained copy
    already exists), `plutil -lint` it, gzip the error log with a sha256
    comparison of the decompressed stream before removing the original, then
    after 5 seconds prove no service, no `pgrep -f '.../openclaw/dist/index.js
    gateway'` and no error log. Log removal is reversible with `gzip -cd`; the
    plist move with `mv` back, but do not bootstrap it unless the owner
    recommissions OpenClaw and the declared entrypoint exists.

- [x] 2026-09-08 — **Disk reclamation:** Heavy items archived to the Mac mini
  instead of deleted.
  - Result: the owner's decision — with no Time Machine destination on the
    MacBook and terabytes free on the mini, the heavy items moved to
    `/Volumes/Datos18TB/Archivo/macbook-2026-09-08`. Each item was streamed as
    a tar over ssh, with the sha256 of the same byte stream computed on both
    ends and the archive listed on the mini before anything local was removed.
    Hashes and a restore table are in `LEEME.md` beside the archives. 62 GiB
    now sit on the mini; the MacBook went from 153 GiB free to 206 GiB.
    Archived: `~/Backups/nova-account-closures-2026-08` (6.81 GB) and
    `~/Backups/webcafeina-orphan-docroots-2026-08-24` (4.42 GB), the sole
    copies of closed hosting accounts; the local iOS backup of 2026-07-04
    (9.46 GB); `~/.cache/whisper` (6.72 GB); the `midia-test` AVD (3.43 GB);
    Cursor's `state.vscdb.backup` of 15 May (6.43 GB); the July plugin rollback
    (440 MB); `~/.ollama/models` (28.78 GB) whole.
  - Closes the parked decisions for the iOS device backup, Cursor
    `state.vscdb.backup`, server pre-cutover snapshots, Android `midia-test`
    AVD, OpenAI Whisper checkpoints and the Claude-favish plugin rollback
    snapshots: each is now a restore from the mini, not a deletion.

- [x] 2026-09-08 — **Disk reclamation:** Ollama removed entirely.
  - Result: the owner used none of it at the time. `qwen3.5:35b-mlx` (21 GB),
    `qwen3.5-opencode` (6.6 GB, a local derivative in no registry — the mini
    archive is its only other copy) and `nomic-embed-text` (274 MB) went, and
    `brew services stop ollama` ended the idle daemon. `~/.ollama` was 40 KB.
    `~/.config/opencode/opencode.json` still named
    `ollama/qwen3.5-opencode:latest` as `model` and `small_model`, leaving
    opencode's default provider dangling.
  - Amendment 2026-09-19: Ollama is back in use. `ollama list` shows
    `qwen3.6:35b` (22 GB) and `qwen3.6:35b-mlx` (23 GB) pulled two days earlier
    and `~/.ollama/models` is 43 GB again. Tracked as an open owner decision in
    `TODO.md`.

- [x] 2026-09-08 — **Disk reclamation:** Safe reclamation on the MacBook.
  - Result: OrbStack build cache pruned with `docker builder prune -f`
    (22.82 GB, the figure Docker reported as reclaimable, zero active cache;
    images, containers and volumes untouched, every named data volume checked
    present afterwards: `enlima-mariadb`, `osseus_dbdata`, `n8n_local_data`,
    `supabase_db_midia-local-e2e`, `ddev-global-cache`). PlatformIO cache-only
    prune, 426 MB (`packages` and `tools` untouched). Composer rollback phars:
    kept `latest.phar` and 2.9.5, removed the eight older ones (`~/.composer`
    31 MB to 6.4 MB, `composer --version` still 2.10.3). `pnpm store prune` on
    the active v11 store: 732 packages, about 2 GB; the v10 and v3 stores stay
    because projects under `~/p` still pin pnpm 10.x and 9.15.x. The MacBook
    ended the session at 218 GiB free, later 231 GiB.
  - Note: starting OrbStack made kubelet garbage-collect 75 old `k8s_POD_*`
    sandbox containers and three anonymous volumes — kubelet's own startup GC,
    visible in `docker events` as `container destroy k8s_POD_...`, not the
    prune.
  - Closes the parked decisions for the OrbStack sparse image (`~/OrbStack` is
    2.8 GiB on 2026-09-19), PlatformIO cache, Composer old phars and pnpm
    legacy stores.

- [-] 2026-09-08 — **Disk reclamation:** Yarn Berry metadata, Deno and Bun
  caches left alone.
  - Resolution: the 1.1 GB Yarn metadata is the offline resolution index, and
    losing it is a real capability loss rather than a cache eviction. The Deno
    (138 MB) and Bun (172 MB) caches are not worth the review.

- [-] 2026-09-08 — **Disk reclamation:** Parallels Windows 11 VM stays.
  - Resolution: it is the owner's only Windows. Compaction is not worth running
    — `prl_disk_tool compact --info` reports 54,623 allocated blocks against
    54,610 used at 1 MiB per block, about 13 MiB to recover. The 256 GiB
    virtual disk holds ~53 GiB of real Windows. The only meaningful saving is
    the 3.2 GiB `.mem` suspended state, which stays an owner decision in
    `TODO.md`.

- [x] 2026-09-08 — **Disk reclamation:** Parallels VM copied to the mini.
  - Result: taken with the VM suspended and nothing but the Parallels service
    running: `parallels-windows-11-pvm.tar`, 60,705,433,600 bytes, sha256
    `b191286692...4d672c7`, 30 entries including the 53 GiB `.hds`, the `.mem`
    suspended state and `config.pvs`. The local VM was not touched — still
    `suspended`, still 57 GiB. Restoring is `tar -C ~/Parallels -xf` followed
    by `prlctl register`.

- [-] 2026-09-08 — **Disk reclamation:** Atrium index deletion.
  - Resolution: Atrium stays untouched by the owner's decision, index growth
    included.

- [-] 2026-09-08 — **Disk reclamation:** Cargo registry/src wholesale deletion
  rejected.
  - Resolution: there are 491 extracted package trees with no matching local
    crate archive. A future selective tool may consider only exact
    source/archive matches while Rust processes are stopped.

- [x] 2026-09-08 — **Runner:** Task 3.5 supervised canary closed; the full
  updater path under launchd is proven.
  - Result: run `20260908T004750Z.95225` reported `preflight ready`, exactly
    one `plugin_end` for each of the 27 plugins, zero error events, and
    `run_end status=success total=27 successful=25 failed=0 skipped=2` after
    2054 seconds. Logs stayed 0600 in a 0700 directory, stderr held only
    gcloud's progress text, and no child survived the run. The first canary
    had deferred everything because the 1-minute load was above the CPU count
    while Backblaze was uploading; the gate now confirms load with measured CPU
    idle (`preflight ... cpu_idle=`), and this run — load 15-22 on 16 CPUs with
    58-75% idle — came back `ready` and did the real work. Slowest steps under
    launchd: homebrew 315s, brewhealth 488s, mole 123s, osx 43s.
  - Evidence: `tests/runner/preflight-load-gate.sh` pins both sides, an
    I/O-bound machine (75% idle, not degraded) and a saturated one (0% idle,
    degraded, status 20).

- [x] 2026-09-08 — **Runner:** The saturation gate never fired on either
  machine.
  - Result: `sysctl` prints the load in the user's locale — "19,70", not
    "19.70" — and `awk -v` only treats a value as numeric when it looks
    numeric, so the comparison was done on strings: `"19,70" > "8"` is false
    because `"1" < "8"`. The mini, at load 136 on 8 CPUs with 0.0% idle, was
    reported healthy. Fixed by normalising the separator and forcing numeric
    context.
  - Evidence: `tests/runner/preflight-load-gate.sh` pins the discriminating
    case; the mini now reports `load=136.31 cpus=8 cpu_idle=0.0` and degrades.

- [x] 2026-09-08 — **Tests:** `tests/runner/plugin-timeout.sh` failed for
  machine load rather than for its contract.
  - Result: it waited five seconds for the fixture plugin to start, and
    preflight now takes a two-sample `top` before any plugin runs. The waits
    are 60s, which also covers the runner's own `--kill-after=30s`.

- [x] 2026-09-08 — **Plugins:** `report_docker` no longer waits about 86
  seconds on a dead daemon.
  - Result: the `docker info` gate is bounded with the coreutils timeout
    preflight already requires (10s, `--kill-after=5s`).
  - Evidence: `tests/plugins/docker.sh`, whose hung-daemon case takes 10s with
    the bound and 121s without it.

- [x] 2026-09-08 — **Mac mini:** First full run over ssh, findings fixed.
  - Result: `main` is the only branch here and on GitHub; the mini
    (`Mac-mini-de-Cristian.local`, 192.168.1.65) was synced to it and ran the
    full 27 plugins. First result 22 successful, 2 failed, 3 skipped; after the
    fixes 24 successful, 0 failed, 3 skipped (docker daemon down, bun and
    platformio not installed), 733 lines, no noise.
    `pear` failed on the mini only: 141 files under `/opt/homebrew/share/pear`
    were root-owned from earlier `sudo pear` runs; fixed on the host with
    `sudo chown -R cristiandeluxe:admin /opt/homebrew/share/pear`. The deeper
    cause was in the runner: a manual run over ssh has no terminal and skipped
    sudo entirely, but `sudo -n` never prompts and the mini has `NOPASSWD:
    ALL`; the no-terminal path now probes with `sudo -n true` and keeps the
    privileged steps when it succeeds (scheduled mode untouched). With the
    keepalive now running in non-interactive runs, stopping it printed
    `Terminated: 15  sleep 60` into the log; the keepalive is disowned and its
    stderr discarded. `brewhealth` failed: `brew missing` reported `memo: fzf`,
    a real missing dependency of `antoniorodr/memo`; installed `fzf`.
    Mini-only `brew doctor` advisories cleared: four casks had a `.metadata`
    directory but no version directory (`google-chrome` now 152.0.7977.83,
    `gcloud-cli` 583.0.0 with its dangling `latest` symlink fixed, `orbstack`
    2.2.3, `responsively` 1.18.0); the `yarn` 1.22.22 formula was uninstalled
    because `/opt/homebrew/bin/yarn` is corepack's shim serving 4.14.1.
  - Evidence: `tests/runner/sudo-nopasswd.sh`; `brew missing` empty on the
    mini.

- [-] 2026-09-08 — **Mac mini:** Unbrewed dylibs in `/usr/local/lib` stay.
  - Resolution: `pkgutil` names the owners — `libEioPal`, `libTCMsgSrv2` and
    `libTCMsgSvr2` belong to `com.tcelectronic.pkg.TCAudioInterfaceSoftware`
    (the audio interface driver), `libcpsrt` to `com.wibu.cmdriver` (CodeMeter
    licensing), and `libext2fs` to an ext2/3/4 filesystem installer. Homebrew
    only warns because it did not put them there; deleting them breaks audio
    hardware and licence dongles.

- [x] 2026-09-08 — **Verification:** End-of-session full manual run.
  - Result: 27 plugins, 25 successful, 0 failed, 2 skipped, exit 0, 602 lines
    of log, none of the noise the session started with (`No such file or
    directory`, `Stale NFS`, `a password is required`, `Terminated: 15`,
    tap-trust deprecation, `No available formula with the name "warning:
    ..."`). Preflight recorded `load=263.59 cpus=16 cpu_idle=0.0` — genuine
    saturation, correctly identified by the measured-idle gate, reported as
    degraded while manual mode still ran the work. PEAR printed `its install
    directory is writable by this user; upgrading without root`.
  - Evidence: suite and shellcheck green on both machines at `0f97f1b`.

- [x] 2026-09-07 — **Plugins:** Homebrew findings from the run of 2026-09-07.
  - Result: `brew outdated` was captured with `2>&1`, so deprecation and tap
    warnings entered the outdated list and were passed to `brew upgrade`;
    stderr is now kept apart and the names filtered. Homebrew upgraded exactly
    one formula and one cask per run and reported success for the rest,
    because `brew upgrade` reads stdin and the loop fed the outdated list on
    stdin; the list now arrives on fd 3 — this is why 32 formulae stayed
    outdated across runs that all reported success.
    `HOMEBREW_NO_REQUIRE_TAP_TRUST` dropped: the 20 installed third-party taps
    are trusted explicitly in `~/.homebrew/trust.json` via `brew trust --tap`
    (3 were missing: ddev/ddev, gbevin/tools, stripe/stripe-cli).
  - Evidence: `tests/plugins/homebrew-warning-noise.sh`,
    `tests/plugins/homebrew-stdin-drain.sh` (fails against the old form).

- [x] 2026-09-07 — **Plugins:** PEAR probes the grant once.
  - Result: `sudo -n true` once and one reported reason, instead of one `sudo:
    a password is required` per package; an expiry mid-loop also disables root
    for the remaining packages.
  - Evidence: `tests/plugins/pear-sudo-probe.sh`.

- [x] 2026-09-07 — **Plugins:** Docker/OrbStack report `du` stderr no longer
  floods the run.
  - Result: vanished paths (live container overlays) are counted and reported
    as one line saying the size is a lower bound.

- [x] 2026-09-07 — **Plugins:** `plugins/uvtools.sh` feeds its tool list on
  fd 3.
  - Result: a future `uv` that reads stdin cannot silently reduce the run to
    one tool.
  - Evidence: `tests/plugins/uvtools.sh`, which fails against the old form.

- [x] 2026-09-07 — **Host maintenance:** `brew doctor` advisories resolved.
  - Result: `goplaces` 0.4.3 formula keg was dead weight (the binary belongs to
    the 0.4.9 cask), uninstalled; Homebrew autoremoved an orphaned `unbound`
    1.26.0 in the same command (`brew install unbound` restores it).
    `terraform` 1.5.7 was an orphaned keg of a formula Homebrew removed (BUSL);
    no `.tf` file under `~/p` and no state file, so it was replaced with
    `hashicorp/tap/terraform` 1.16.1. `pillow` and `pydantic` are left unlinked
    deliberately: dependency kegs of `img2pdf` and `ocrmypdf`, which run from
    their own virtualenvs; `brew link --dry-run` shows linking would write PIL
    and pydantic into the global `/opt/homebrew/lib/python3.13/site-packages`.
    Re-check only if a dependent breaks.

- [x] 2026-09-01 — **Plugins:** Stop `plugins/homebrew.sh` retrying `brew
  upgrade --greedy` three times against the deterministic `gcloud-cli` failure.
  - Result: plugin v2.0.0 dropped the blanket `--greedy` retry loop; each
    outdated formula and cask is upgraded once with no retry (only `brew
    update` keeps its three attempts), and greedy behavior is limited to
    `HOMEBREW_UPGRADE_GREEDY_CASKS="codexbar goplaces"`.
  - Evidence: `tests/plugins/homebrew.sh` proves a failed cask is attempted
    once, the remaining casks still run, and the plugin returns 1.

- [x] 2026-09-01 — **Scheduling activation:** Privileged files installed and
  the LaunchAgent enabled.
  - Result: `/etc/sudoers.d/rocketupdater` installed as `root:wheel 0440`
    through the macOS authorization dialog, so no credential passed through a
    shell or a transcript; `visudo -c` validates the whole config. The boundary
    is proven by execution, not by `sudo -l` (macOS ships `%admin ALL=(ALL)
    ALL`, so `sudo -l` reports every command as permitted): `sudo -n
    /usr/sbin/softwareupdate -d -r` exits 0 with no prompt, while `sudo -n
    /usr/bin/true` and `sudo -n /usr/sbin/softwareupdate --version` both exit 1
    with "a password is required". `/etc/newsyslog.d/rocketupdater.conf`
    installed as `root:wheel 0644` in the same authorization, fields verified
    tab-separated with `cat -et`. The LaunchAgent was installed gated in
    preflight-only mode, then reloaded in full scheduled mode: the Task 3.4
    gate passed with exit 0, the run's only events run_start, preflight ready,
    run_end success; logs 0600; directory 0700; empty stderr; no ANSI escape;
    no surviving child.
  - Files: `launchd/`.
