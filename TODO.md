# TODO — RocketUpdater

> Created 2026-08-22 from cross-project filings. States: `[ ]` pending, `[~]` partial,
> `[!]` blocked, `[x]` done, `[-]` obsolete.

- [x] `.serena/` is local language-server state, not project content: added to
      `.gitignore` on 2026-09-08, so both checkouts stop reporting it as
      untracked (this also closes the copy in `~/p/osseus/TODO.md`).
- [-] U+FE0F hygiene — do not strip it. As of 2026-09-08 the selector survives in
      exactly one file, `lib/print_message.sh`, on three characters: `ℹ️` (U+2139),
      `⏭️` (U+23ED) and `⚠️` (U+26A0). Those three have a text presentation by
      default, so removing VS16 turns the run's prefixes into monochrome glyphs —
      it degrades the output rather than cleaning it. If a variation-selector CI
      scan is ever added, allowlist these three; that is the correct fix here.

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
- [x] `report_docker` no longer waits about 86 seconds on a dead daemon: the
      `docker info` gate is bounded with the coreutils timeout preflight already
      requires (10s, `--kill-after=5s`). Covered by `tests/plugins/docker.sh`,
      whose hung-daemon case takes 10s with the bound and 121s without it.
- [x] Task 3.5 supervised canary — closed 2026-09-08. The full updater path
      under launchd is now proven, not just the deferral gate: run
      `20260908T004750Z.95225` reported `preflight ready`, exactly one
      `plugin_end` for each of the 27 plugins, zero error events, and
      `run_end status=success total=27 successful=25 failed=0 skipped=2` after
      2054 seconds. Logs stayed 0600 in a 0700 directory, stderr held only
      gcloud's progress text, and no child survived the run.

      It also settled the risk this item was watching. The first canary deferred
      everything because the 1-minute load was above the CPU count while
      Backblaze was uploading, and a night like that produces `run_end success`
      having done nothing. The gate now confirms load with measured CPU idle
      (`preflight ... cpu_idle=`), and this run — load in the 15-22 range on 16
      CPUs with 58-75% idle — came back `ready` and did the real work. The
      threshold was not tuned on speculation: `tests/runner/preflight-load-gate.sh`
      pins both sides, an I/O-bound machine (75% idle, not degraded) and a
      saturated one (0% idle, degraded, status 20), and the 2026-09-01 canary is
      the measured example of the second.

      Slowest steps under launchd, for future comparison: homebrew 315s,
      brewhealth 488s, mole 123s, osx 43s.

## Findings from the first Mac mini run (2026-09-08)

`main` is now the only branch here and on GitHub; the Mac mini
(`Mac-mini-de-Cristian.local`, 192.168.1.65) was synced to it and ran the full
27 plugins over ssh. First result: 22 successful, 2 failed, 3 skipped. After the
fixes below the same run is 24 successful, 0 failed, 3 skipped (docker daemon
down, bun and platformio not installed), 733 lines, no noise of any kind.

- [x] `pear` failed on the mini only: 141 files under `/opt/homebrew/share/pear`
  were root-owned, left by earlier `sudo pear` runs, so every package ended in
  `permission denied (delete)` / `ERROR: commit failed`. The laptop had 0 such
  files, which is why it never showed. Fixed on the host with
  `sudo chown -R cristiandeluxe:admin /opt/homebrew/share/pear`.
- [x] The deeper cause was in the runner: a manual run over ssh has no terminal,
  and it skipped sudo entirely. But `sudo -n` never prompts, it fails, and the
  mini has `NOPASSWD: ALL`, so the grant was there to be used. The no-terminal
  path now probes with `sudo -n true` and keeps the privileged steps when it
  succeeds. Scheduled mode is untouched. Covered by
  `tests/runner/sudo-nopasswd.sh`.
- [x] With the keepalive now running in non-interactive runs, stopping it made
  bash print `Terminated: 15  sleep 60` into the log, which reads like a failed
  step. The keepalive is disowned and its stderr discarded.
- [x] `brewhealth` failed on the mini: `brew missing` reported `memo: fzf`, a
  real missing dependency of the installed `antoniorodr/memo` formula. Installed
  `fzf`; `brew missing` is now empty there.
- [x] Mini-only `brew doctor` advisories cleared on 2026-09-08. Four casks had a
  `.metadata` directory but no version directory, so Homebrew could not upgrade
  them: `google-chrome` (now 152.0.7977.83), `gcloud-cli` (583.0.0, its `latest`
  symlink had been dangling at 579.0.0), `orbstack` (2.2.3; no containers
  existed, and it was running again straight after) and `responsively` (1.18.0).
  The `yarn` 1.22.22 formula was uninstalled: nothing depended on it, it was
  unlinked, and `/opt/homebrew/bin/yarn` is corepack's shim serving 4.14.1,
  which still works and still upgrades through the yarn plugin.
- [-] Unbrewed dylibs in `/usr/local/lib` on the mini: keep them. `pkgutil`
  names the owners — `libEioPal`, `libTCMsgSrv2` and `libTCMsgSvr2` belong to
  `com.tcelectronic.pkg.TCAudioInterfaceSoftware` (the audio interface driver),
  `libcpsrt` to `com.wibu.cmdriver` (CodeMeter licensing), and `libext2fs` to an
  ext2/3/4 filesystem installer. Homebrew only warns because it did not put them
  there; deleting them breaks audio hardware and licence dongles.

## Findings from the run of 2026-09-07

- [x] Homebrew: `brew outdated` was captured with `2>&1`, so deprecation and tap
  warnings entered the outdated list and were passed to `brew upgrade`, failing
  the whole plugin while the real packages upgraded fine. Fixed by keeping
  stderr apart and filtering the names; covered by
  `tests/plugins/homebrew-warning-noise.sh`.
- [x] Homebrew upgraded exactly one formula and one cask per run and reported
  success for the rest. `brew upgrade` reads stdin, and the loop fed the
  outdated list on stdin, so the first upgrade drained the remaining names. The
  list now arrives on fd 3; covered by `tests/plugins/homebrew-stdin-drain.sh`,
  which fails against the old form. This is why 32 formulae stayed outdated
  across runs that all reported success.
- [x] `HOMEBREW_NO_REQUIRE_TAP_TRUST` dropped: the 20 installed third-party taps
  are now trusted explicitly in `~/.homebrew/trust.json` via `brew trust --tap`
  (3 were missing: ddev/ddev, gbevin/tools, stripe/stripe-cli). A tap installed
  later is reported by brew instead of being trusted silently, which the blanket
  variable never allowed.
- [x] PEAR probes the grant once with `sudo -n true` and reports the reason once,
  instead of one `sudo: a password is required` per package; an expiry mid-loop
  also disables root for the remaining packages. Covered by
  `tests/plugins/pear-sudo-probe.sh`.
- [x] Docker/OrbStack report: `du` stderr no longer floods the run. Vanished
  paths (live container overlays) are counted and reported as one line saying
  the size is a lower bound.
- [x] `brew doctor` advisories resolved on 2026-09-07:
  - `goplaces`: the 0.4.3 formula keg was dead weight (no formula, no dependents,
    nothing linked into it; `/opt/homebrew/bin/goplaces` belongs to the 0.4.9
    cask). Uninstalled. Homebrew autoremoved an orphaned `unbound` 1.26.0 in the
    same command; nothing depends on it and `brew missing` is clean, so it was
    an unused leftover. `brew install unbound` restores it if that is wrong.
  - `terraform`: 1.5.7 was an orphaned keg of a formula Homebrew removed (BUSL).
    There is no `.tf` file anywhere under `~/p` and no state file, so nothing
    could be broken by a version change: uninstalled and replaced with
    `hashicorp/tap/terraform` 1.16.1, which is maintained and upgradeable.
  - `pillow` and `pydantic`: left unlinked deliberately. They are dependency
    kegs of `img2pdf` and `ocrmypdf`, which run from their own virtualenvs and
    work today. `brew link --dry-run` shows linking would write PIL and pydantic
    into the global `/opt/homebrew/lib/python3.13/site-packages`, so the warning
    is the correct state, not a defect. Re-check only if a dependent breaks.
- [x] `plugins/uvtools.sh` now feeds its tool list on fd 3 as well, so a future
  `uv` that reads stdin cannot silently reduce the run to one tool. Covered by
  `tests/plugins/uvtools.sh`, which fails against the old form.
- [!] `xdevplatform/homebrew-tap` Casks/xurl.rb:37 calls the deprecated
  `postflight`; every brew invocation prints the warning on stderr, where it is
  now harmless to the run. No PR is possible: that file starts with "generated
  by GoReleaser. DO NOT EDIT", and it comes from `homebrew_casks.hooks.post.install`
  in `xdevplatform/xurl`'s `.goreleaser.yaml`, which GoReleaser always renders
  as a legacy `postflight do ... end`. GoReleaser has no `postflight_steps`
  support yet — tracked upstream in goreleaser/goreleaser#6870, open. Blocked on
  that issue; a patch to either repo would be overwritten by the next release.

## Manual disk-reclamation decisions

- [x] Shadow zsh formulae removed 2026-09-08 (about 5 MiB, the point was the
  shadowing, not the space). Confirmed first: `.zshrc` sets
  `ZSH_THEME="powerlevel10k/powerlevel10k"` and lists `zsh-syntax-highlighting`
  and `zsh-autosuggestions` in `plugins=(...)`, all resolved from
  `~/.oh-my-zsh/custom`; nothing sourced `/opt/homebrew/share/zsh-*` and no
  formula depended on the three. After
  `brew uninstall --formula powerlevel10k zsh-autosuggestions zsh-syntax-highlighting`
  a real interactive shell still reports `theme=powerlevel10k/powerlevel10k`,
  both plugins loaded and the `p10k` function present.

  Note for future shell checks: `.zshrc` takes an early agent path when
  `CLAUDECODE`, `CODEX_AGENT` and similar are set, so a shell started from an
  agent session loads none of this. Verify with those variables unset, under a
  pty, or the result is a false negative.
- [x] OpenClaw gateway decommission — verified gone on 2026-09-08: no
  `~/Library/LaunchAgents/ai.openclaw.gateway.plist`, `launchctl print
  gui/501/ai.openclaw.gateway` reports the service is not in the domain, no
  gateway process is running and no `~/Library/Logs/openclaw*` remains. Only the
  retained plist under `LaunchAgents/disabled/` is left, as intended. The
  recovery sequence below stays for the case where any part of it reappears.

  Original finding — the owner confirmed it is not in use.
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
