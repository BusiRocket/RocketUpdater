# TODO — RocketUpdater

> Created 2026-08-22 from cross-project filings. States: `[ ]` pending, `[~]` partial,
> `[!]` blocked, `[x]` done, `[-]` obsolete.

- [ ] Commit or discard the untracked `.serena/` state in this checkout (also referenced from
      `~/p/osseus/TODO.md`; closing it here closes it there).
- [ ] Optional hygiene: tracked shell scripts carry U+FE0F (emoji variation selector-16 in echo
      strings; originally `RocketUpdater.sh`, `lib/bash_colors.sh` (since retired),
      `scripts/format.sh`, `scripts/lint.sh`; `lib/print_message.sh` inherited the emoji).
      Benign (verified 2026-08-22, rocket-agents hidden-unicode scan), but they will trip any
      future variation-selector CI scan; strip the VS16 or allowlist emoji if such a scan is
      added.

## Plugins

- [x] Stop `plugins/homebrew.sh` retrying `brew upgrade --greedy` three times
  against the deterministic `gcloud-cli` failure. Resolved 2026-09-01 by plugin
  v2.0.0: the blanket `--greedy` retry loop is gone; each outdated formula and
  cask is upgraded once with no retry (only `brew update` keeps its three
  attempts), and greedy behavior is limited to
  `HOMEBREW_UPGRADE_GREEDY_CASKS="codexbar goplaces"`. Evidence:
  `tests/plugins/homebrew.sh` proves a failed cask is attempted once, the
  remaining casks still run, and the plugin returns 1.

## Scheduling activation (blocked on privileged writes)

- [x] Install `/etc/sudoers.d/rocketupdater` as `root:wheel 0440`. Done
      2026-09-01 through the macOS authorization dialog, so no credential passed
      through a shell or a transcript. `visudo -c` validates the whole config.
      Boundary proven by execution, not by `sudo -l` (macOS ships
      `%admin ALL=(ALL) ALL`, so `sudo -l` reports every command as permitted
      and cannot discriminate): `sudo -n /usr/sbin/softwareupdate -d -r` exits 0
      with no prompt, while `sudo -n /usr/bin/true` and
      `sudo -n /usr/sbin/softwareupdate --version` both exit 1 with
      "a password is required". The install path was never executed.
- [x] Install `/etc/newsyslog.d/rocketupdater.conf` as `root:wheel 0644`. Done
      2026-09-01 in the same authorization. Fields verified tab-separated with
      `cat -et`.
- [x] LaunchAgent installed, gated in preflight-only mode, then reloaded in full
      scheduled mode on 2026-09-01. The Task 3.4 gate passed: exit 0; the run's
      only events were run_start, preflight ready, run_end success; logs 0600;
      directory 0700; empty stderr; no ANSI escape; no surviving child.
- [ ] `report_docker` spends about 86 seconds reaching a dead daemon before
      skipping. Observed in the 2026-09-01 canary (`plugin_end docker skipped`
      with duration 86) while OrbStack was not running: the Docker CLI has no
      connect timeout on this path, so every scheduled run pays that minute and
      a half for nothing. It is correct, just slow. Cheapest fix is bounding the
      existing `docker info` gate with the coreutils timeout already required by
      preflight, rather than reimplementing the gate.
- [~] Task 3.5 supervised canary — first execution was **not representative**,
      and the deferral that made it so was correct rather than a false positive.
      The machine was genuinely saturated: 1-minute load 56-62 against 16
      logical CPUs, and `top -l 2` measured **0.0% idle** (75.73% user, 24.26%
      sys) with node at 344% CPU, Backblaze `bztransmit` at 92%, Chrome, Orca
      and codex all live. Preflight reported `degraded` and deferred every
      `run`-action plugin, leaving only the reports. So the degradation gate is
      proven in production, but the full updater path under launchd is still
      unproven.

      **Risk to watch:** if the machine is also loaded at 03:15, the scheduled
      run defers everything and still emits `run_end status=success` with zero
      failures - a no-op that reads as healthy. Whether that happens cannot be
      determined from a daytime sample, so do not retune the threshold on
      speculation; observe the first real calendar run instead. Smallest next
      step: after a 03:15 run, check
      `tail -40 "$HOME/Library/Logs/RocketUpdater/events.log"` for `preflight`
      with `ready` rather than `degraded`, exactly one `plugin_end` per plugin,
      and `run_end` with `status=success`. If it shows `degraded` with
      `reasons: load_above_cpu_count`, the gate needs a metric that separates
      genuine CPU saturation from an I/O-bound backup daemon (measured CPU idle,
      not load average), because deferring every night makes the schedule inert.

      What the run did prove: every one of the 27 plugins emitted exactly one
      `plugin_end`; the deferral gate fired for all `run` actions; no deletion,
      prune, purge, or cleanup command appeared anywhere in the output; no child
      survived `run_end`; and the summary was truthful
      (`total=27 successful=1 failed=1 skipped=25`). The single failure was
      Mole, diagnosed and fixed in commit `ad705d8`: Mole abandoned its own dry
      run when a per-item size check blew its 30-second budget on the 71 GB
      OrbStack blob. With the budget raised the real dry run now completes
      (`Dry run complete`, 12.57 GB across 556 items in 6 categories, versus
      10.14 GB / 423 / 4 when it was cancelled, confirming the cancelled run
      under-reported) and the plugin exits 0.

## Findings from the run of 2026-09-07

- [x] Homebrew: `brew outdated` was captured with `2>&1`, so deprecation and tap
  warnings entered the outdated list and were passed to `brew upgrade`, failing
  the whole plugin while the real packages upgraded fine. Fixed by keeping
  stderr apart and filtering the names; covered by
  `tests/plugins/homebrew-warning-noise.sh`.
- [ ] `HOMEBREW_NO_REQUIRE_TAP_TRUST` is deprecated ("Use `brew trust` for each
  non-official tap"). Every brew call prints the warning. Next step: decide
  whether to run `brew trust` once per third-party tap (openclaw, xdevplatform,
  steipete, oven-sh, anomalyco, stripe) and drop the variable.
- [ ] PEAR: every per-package `upgrade` still prints `sudo: a password is
  required` before falling back. The fallback works; the noisy privileged
  attempt should be skipped when sudo is known to be unavailable.
- [ ] Docker/OrbStack report: `du` walks container overlay paths and emits
  hundreds of `No such file or directory` / `Stale NFS file handle` lines. Next
  step: send `du` stderr to /dev/null in the docker plugin's size report.
- [ ] `brew doctor` reports unlinked kegs (`goplaces`, `pillow`, `pydantic`) and
  keg-only leftovers (`terraform`, `goplaces`). Advisory only; decide manually.

## Findings from the first full run (2026-09-01, 27 plugins, 5 minutes)

First result: 23 successful, 2 failed, 2 skipped, runner exit 1. Preflight was
`ready`, so the earlier `degraded` canary was caused by this session's own test
load, not a permanent condition. Zero integrity events: the global npm tree
survived upgrades of npm, jscpd, pnpm and `@playwright/mcp`.

**After the fixes below, re-run clean:** `run_end status=success`,
`total=27 successful=25 failed=0 skipped=2`, 215 seconds, with `brewhealth`
(16s), `pear` (14s) and `mole` (84s) all succeeding and the summary reading
"No plugin failures." The two skips are `conda` (not installed) and `docker`
(daemon down), both status 20 as designed. Still zero integrity events across
every run so far.

**Third run caught a further defect, fourth confirmed the fix.** Run 3 exited 1
on `omzsh`: `git pull` of `zsh-autosuggestions` died with
`LibreSSL SSL_connect: SSL_ERROR_SYSCALL in connection to github.com:443`.
Retrying the identical pull by hand succeeded immediately, so it was a
transient TLS drop. Unlike the Mole and `brew doctor` cases, the update here
genuinely did not happen, so failing was correct - what was wrong was giving up
after one attempt when `brew update` already had three. Fixed by adding a
bounded three-attempt retry to the plugin's git pulls, and `omzsh` now skips
with 20 instead of 0 when Oh My Zsh is absent. Run 4: exit 0,
`total=27 successful=25 failed=0 skipped=2`, 216 seconds, exactly one
`plugin_end` per plugin with no duplicates.

Note for the 03:15 verification: runs 2 and 4 had a `degraded` preflight
because this session was loading the machine. Manual mode ignores the deferral,
so all 27 plugins still ran, but no `--scheduled` run has yet been observed on
an unloaded machine.

- [x] PEAR was broken on this machine, independently of RocketUpdater: every
      `pear`/`pecl` command died with
      `Failed opening required 'Console/Getopt.php'`. Root cause was not a
      missing package but a wrong `include_path`: Homebrew's php formula ships a
      PEAR skeleton in `Cellar/php/8.5.10/share/php/pear` and php.ini points
      there, while the real tree with `Console`, `Archive`, `Structures` and
      `XML` lives in `/opt/homebrew/share/pear`. Fixed 2026-09-01 in plugin
      v2.0.0 by resolving the real tree and exporting `PHP_PEAR_INSTALL_DIR`,
      rather than editing the user's php.ini. A second failure surfaced behind
      it: upgrading the `PEAR` package itself tries to replace the read-only
      Cellar binaries `pear`, `peardev` and `pecl`, which can only end in
      `permission denied (delete)` / `ERROR: commit failed`. Under a
      Homebrew-managed PHP the plugin now leaves that package to
      `brew upgrade php` and upgrades the rest individually. Verified: the real
      plugin run now exits 0 after upgrading Archive_Tar, Console_Getopt,
      Structures_Graph and XML_Util.
- [x] `brewhealth` no longer fails on advisory output. Fixed 2026-09-01 in
      plugin v2.0.0 with a severity split: `brew missing` (a formula whose
      dependency is absent) fails the run, while `brew doctor` and the
      autoremove preview are reported without failing, because `brew doctor` is
      advisory by Homebrew's own definition and always has something to say on a
      lived-in machine. The one real finding it had, `memo: fzf`, was repaired
      by installing `fzf`; `brew missing` is now clean and the plugin exits 0.
- [x] Decided 2026-09-01: leave Homebrew's post-install cleanup enabled.
      `brew upgrade` removes the superseded Cellar version of a package it
      replaces (`Removing: .../camsnap/0.4.1`), which is intrinsic to upgrading
      rather than a decision about user data.
      `HOMEBREW_NO_INSTALL_CLEANUP=1` would satisfy a literal reading of "zero
      scheduled deletion" while growing the Cellar without bound, and no guard
      here reclaims old kegs. README now states the nuance instead of leaving
      the phrase to be misread.
- [ ] Remaining `brew doctor` advisories, left deliberately because each is a
      judgment call with real consequences: formulae `terraform` and `goplaces`
      are deprecated, and kegs `goplaces`, `pillow`, `pydantic` are unlinked.
      Do **not** blanket-`brew link` those: `pillow` and `pydantic` are commonly
      left unlinked so they cannot shadow pip-installed versions, and linking
      them can break a working Python environment. Smallest next step: decide
      per keg whether anything needs it on `PATH`, and choose a replacement for
      `terraform` (licence change) separately.

## Manual disk-reclamation decisions

- [ ] Shadow zsh formulae — decision: confirm .zshrc sources the Oh My Zsh
  powerlevel10k, zsh-autosuggestions, and zsh-syntax-highlighting repositories
  under `~/.oh-my-zsh/custom`, which are the canonical sourced copies. If
  confirmed, approve one-time `brew uninstall` of only the three shadow
  formulae, then verify .zshrc still resolves the Oh My Zsh copies. No plugin
  or scheduled command may run this uninstall.
- [ ] OpenClaw gateway decommission — the owner confirmed it is not in use.
  Root cause is a launchd job repeatedly executing Node against absent
  `/opt/homebrew/lib/node_modules/openclaw/dist/index.js`, producing
  `MODULE_NOT_FOUND`. The last live observation showed `spawn scheduled`,
  128,122 runs, last exit 1, and a 3,328,859,672-byte error log growing by
  3,068 bytes in four seconds. The machine then changed outside this audit:
  the service and error log are now absent, no gateway process remains, and a
  valid retained plist exists at
  `~/Library/LaunchAgents/disabled/ai.openclaw.gateway.plist` with SHA-256
  `3c50e470ae6e9a2e8e8a6c0e98644f5b3a6afa9b164a0537448d2cf2190d2501`.
  Do not create a RocketUpdater OpenClaw plugin or newsyslog rule. Use this
  idempotent supervised sequence if any part of the live job/log reappears:

  ```sh
  set -eu
  label="ai.openclaw.gateway"
  domain="gui/$(id -u)"
  active_plist="$HOME/Library/LaunchAgents/$label.plist"
  disabled_dir="$HOME/Library/LaunchAgents/disabled"
  retained_plist="$disabled_dir/$label.plist"
  err_log="$HOME/.openclaw/logs/gateway.err.log"
  stamp=$(date -u +%Y%m%dT%H%M%SZ)
  archive="$HOME/.openclaw/logs/gateway.err.$stamp.log.gz"

  launchctl print "$domain/$label" 2>&1 || true
  stat -f 'inode=%i bytes=%z mtime=%Sm' "$err_log" 2>/dev/null || true
  launchctl bootout "$domain/$label" 2>/dev/null || true
  ! launchctl print "$domain/$label" >/dev/null 2>&1
  ! pgrep -f '/opt/homebrew/lib/node_modules/openclaw/dist/index.js gateway' >/dev/null

  if [ -e "$active_plist" ]; then
      [ ! -e "$retained_plist" ] || {
          echo "Retained plist already exists; compare before moving" >&2
          exit 1
      }
      install -d -m 700 "$disabled_dir"
      mv "$active_plist" "$retained_plist"
  fi
  plutil -lint "$retained_plist"

  if [ -f "$err_log" ]; then
      umask 077
      gzip -c "$err_log" >"$archive.tmp"
      gzip -t "$archive.tmp"
      before_hash=$(shasum -a 256 "$err_log" | awk '{print $1}')
      archived_hash=$(gzip -cd "$archive.tmp" | shasum -a 256 | awk '{print $1}')
      [ "$before_hash" = "$archived_hash" ]
      mv "$archive.tmp" "$archive"
      rm -f -- "$err_log"
  fi

  sleep 5
  ! launchctl print "$domain/$label" >/dev/null 2>&1
  ! pgrep -f '/opt/homebrew/lib/node_modules/openclaw/dist/index.js gateway' >/dev/null
  [ ! -e "$err_log" ]
  ```

  The final three commands are the proof that respawning stopped. The log
  removal is reversible with `gzip -cd "$archive" >"$err_log"`. The plist move
  is reversible with `mv "$retained_plist" "$active_plist"`, but do not
  bootstrap it unless the owner recommissions OpenClaw and the declared
  entrypoint exists.
- [ ] OrbStack sparse image — potential 66 GiB. Decision: confirm all stopped
  containers, images, volumes, and build cache are disposable. If approved,
  start OrbStack, inspect docker system df, approve each prune target, then run
  compaction. Never run from launchd.
- [ ] Steam library — potential 63 GiB. Decision: choose titles to uninstall in
  the Steam UI. Preserve Steam.AppBundle, account state, and the remaining
  library.
- [ ] Parallels Windows 11 VM — potential 57 GiB. Decision: inspect and remove
  snapshots inside Parallels only after confirming the VM opens and required
  rollback points. Never delete the PVM.
- [ ] Ollama models — potential 27 GiB. Decision: identify re-pullable registry
  models. Preserve qwen3.5-opencode because it is a local derivative and active
  configuration dependency.
- [ ] Claude and Claude-favish VM bundles — potential 18.2 GiB. Decision:
  confirm both applications and local agents are stopped and accept
  reprovisioning cost before removing any bundle.
- [ ] pnpm legacy stores — potential 7.2 GiB. Decision: map projects to pnpm
  store versions and preserve any store still referenced. Do not infer safety
  from the active pnpm version alone.
- [ ] Atrium index — potential 9.5 GiB. Decision: confirm the archive and Brain
  are healthy, take the atrium lock, remove only the derived index, and verify
  the scheduled rebuild completes. Never delete and rebuild inline.
- [ ] iOS device backup — potential 8.9 GiB. Decision: confirm a current,
  restorable iCloud or alternate backup in Finder before deleting an old local
  backup.
- [ ] Cursor state.vscdb.backup — potential 6.4 GiB. Decision: quit Cursor,
  verify staleness and current database health, preserve a recoverable copy,
  then approve one-time removal.
- [ ] Server pre-cutover snapshots — potential 10.4 GiB. Decision: owner confirms
  nova-account-closures-2026-08 and webcafeina-orphan-docroots are no longer
  rollback dependencies.
- [ ] Android midia-test AVD — potential 3.2 GiB. Decision: confirm installed APK
  state, databases, and snapshots are disposable; system images do not back up
  user data.
- [ ] OpenAI Whisper checkpoints — current 6.3 GiB across large-v3,
  large-v3-turbo, medium, and small. Decision: retain or remove the set/model
  names explicitly. Homebrew openai-whisper loads these `.pt` files; uv-managed
  mlx-whisper uses a separate Hugging Face cache. Turbo does not supersede every
  workflow, and APFS access time is not usage evidence here.
- [ ] Claude-favish plugin rollback snapshots — potential 993 MiB. Decision:
  select specific dated backups after verifying the live plugins symlink and a
  newer rollback remain intact.
- [ ] Yarn Berry metadata — current 1.1 GiB. Decision: inspect the report and
  explicitly accept loss of Yarn 4.12 offline package resolution before any
  deletion. The 2.1 GiB zip cache does not replace this metadata index.
- [ ] Composer old phars — current nine files, about 28 MiB. Decision: retain at
  least one known-good rollback before selecting older backups.
- [ ] PlatformIO cache — current 435 MiB. Decision: review pio system prune
  --dry-run --cache output, then approve the exact cache-only prune manually.
- [ ] Deno cache — current about 138 MiB. Decision: preserve originStorage and
  webCacheStorage; review deno clean --dry-run before any manual clean.
- [ ] Bun cache — current 21 MiB. Decision: no action unless growth makes
  re-download cost worthwhile.
- [ ] pip user packages — decision: verify which scripts import user-site lxml
  and pandas before any unbounded upgrade.
- [ ] Helm plugins — decision: review the diff and dashboard update scripts,
  source URLs, and checksums before running plugin hooks manually.
- [-] Cargo registry/src wholesale deletion — rejected. There are 491 extracted
  package trees with no matching local crate archive. A future selective tool
  may consider only exact source/archive matches while Rust processes are
  stopped.
