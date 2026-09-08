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

## Findings while closing the backlog (2026-09-08)

- [x] The saturation gate never fired on either machine. `sysctl` prints the
  load in the user's locale — "19,70", not "19.70" — and `awk -v` only treats a
  value as numeric when it looks numeric, so the comparison was done on strings:
  `"19,70" > "8"` is false because `"1" < "8"`. The mini, at load 136 on 8 CPUs
  with 0.0% idle, was reported healthy. Fixed by normalising the separator and
  forcing numeric context; `tests/runner/preflight-load-gate.sh` pins the
  discriminating case. Verified on the mini: it now reports
  `load=136.31 cpus=8 cpu_idle=0.0` and degrades.
- [x] `tests/runner/plugin-timeout.sh` failed for machine load rather than for
  its contract: it waited five seconds for the fixture plugin to start, and
  preflight now takes a two-sample `top` before any plugin runs. The waits are
  60s, which also covers the runner's own `--kill-after=30s`.

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

## Archived to the Mac mini instead of deleted (2026-09-08)

The owner's decision: with no Time Machine destination on the MacBook and
terabytes free on the mini, the heavy items move to
`/Volumes/Datos18TB/Archivo/macbook-2026-09-08` as archive and can be processed
there later. 62 GiB now sit on the mini; the MacBook went from 153 GiB free to
206 GiB.

Each item was streamed as a tar over ssh, with the sha256 of the same byte
stream computed on both ends and the archive listed on the mini before anything
local was removed. Hashes and a restore table are in `LEEME.md` beside the
archives.

- [x] `~/Backups/nova-account-closures-2026-08` (6.81 GB) and
  `~/Backups/webcafeina-orphan-docroots-2026-08-24` (4.42 GB) — the two archives
  Codex correctly refused to see deleted: sole copies of closed hosting accounts.
- [x] The local iOS backup of 2026-07-04 (9.46 GB), `~/.cache/whisper` (6.72 GB),
  the `midia-test` AVD (3.43 GB), Cursor's `state.vscdb.backup` of 15 May
  (6.43 GB) and the July plugin rollback (440 MB).
- [x] `~/.ollama/models` (28.78 GB) archived whole, then only `qwen3.5:35b-mlx`
  removed locally (21 GB). `qwen3.5-opencode` stays installed: it is a local
  derivative in no registry, and the archive is its only other copy.
- [x] Ollama removed entirely on 2026-09-08: the owner uses none of it. Both
  remaining models went (`qwen3.5-opencode` 6.6 GB, `nomic-embed-text` 274 MB)
  and `brew services stop ollama` ended the idle daemon. `~/.ollama` is 40 KB.
  Note for whoever meets this next: `~/.config/opencode/opencode.json` still
  names `ollama/qwen3.5-opencode:latest` as its `model` and `small_model`, so
  opencode's default provider is now dangling — point it elsewhere or restore
  that model from `ollama-models.tar` before using opencode locally.
- [-] Parallels Windows 11 stays: it is the owner's only Windows. Compaction is
  not worth running either — `prl_disk_tool compact --info` reports 54,623
  allocated blocks against 54,610 used at 1 MiB per block, so about **13 MiB**
  to recover. The 256 GiB virtual disk holds ~53 GiB of real Windows. The only
  meaningful saving is the 3.2 GiB `.mem` suspended state, released by resuming
  the VM and shutting Windows down properly instead of leaving it suspended —
  the owner's call, since it discards the saved session.
### Safe reclamation done on 2026-09-08

The MacBook went from 153 GiB free at the start of the session to 218 GiB, with
nothing lost that cannot be rebuilt or restored from the mini's archive.

- [x] Ollama removed entirely — see the entry above; 6.9 GB and one idle daemon.
- [x] OrbStack build cache pruned with `docker builder prune -f`: 22.82 GB, the
  figure Docker itself reported as reclaimable, with zero active cache. Images,
  containers and volumes were left alone, and every named data volume was
  checked present afterwards (`enlima-mariadb`, `osseus_dbdata`, `n8n_local_data`,
  `supabase_db_midia-local-e2e`, `ddev-global-cache`).

  Worth knowing for next time: starting OrbStack made kubelet garbage-collect
  75 old `k8s_POD_*` sandbox containers and three anonymous volumes from earlier
  runs. That is kubelet's own startup GC, visible in `docker events` as
  `container destroy k8s_POD_...`, not something the prune did — but the counts
  move at the same moment and read as if it had.
- [x] PlatformIO cache-only prune: 426 MB. `packages` (3.2 GB of toolchains) and
  `tools` (1.2 GB) untouched, since those are re-downloaded SDKs, not cache.
- [x] Composer rollback phars: kept `latest.phar` and 2.9.5, removed the eight
  older ones. `~/.composer` went from 31 MB to 6.4 MB and `composer --version`
  still answers 2.10.3.
- [x] `pnpm store prune` on the active v11 store: 732 packages, about 2 GB. The
  v10 and v3 stores stay: projects under `~/p` still pin pnpm 10.x and 9.15.x.
- [-] Yarn Berry metadata (1.1 GB) left alone: it is the offline resolution
  index, and losing it is a real capability loss rather than a cache eviction.
  The same goes for the Deno (138 MB) and Bun (172 MB) caches, which are not
  worth the review.

### End-of-session verification (2026-09-08)

Full manual run after every change of the day: 27 plugins, 25 successful,
0 failed, 2 skipped, exit 0, 602 lines of log. None of the noise this session
started with appears in it — no `No such file or directory`, no `Stale NFS`, no
`a password is required`, no `Terminated: 15`, no tap-trust deprecation, no
`No available formula with the name "warning: ..."`.

Two of the day's fixes can be read directly in that log. Preflight recorded
`load=263.59 cpus=16 cpu_idle=0.0` — genuine saturation, correctly identified by
the measured-idle gate rather than by the load alone, and reported as degraded
while manual mode still ran the work. PEAR printed `its install directory is
writable by this user; upgrading without root`, so it no longer creates the
root-owned files that broke the Mac mini.

Suite and shellcheck green on both machines at `0f97f1b`. The MacBook ended the
session at 231 GiB free, from 153 GiB.

### Waiting on the owner, not on work

Three items are parked deliberately: the owner will decide them later, and
nothing else should touch them in the meantime.

- [ ] Steam — 61 GiB across six titles, re-downloadable, so a UI uninstall of
  whichever titles the owner picks rather than an archive. The two Witcher
  installs alone are 32.6 GiB.
- [ ] The Parallels `.mem` suspended state — 3.2 GiB, released by resuming the
  VM and shutting Windows down properly. It discards the session saved on
  21 June, which is why it is the owner's call and not a maintenance step.
- [x] The Parallels VM now has a copy on the mini, taken 2026-09-08 with the VM
  suspended and nothing but the Parallels service running:
  `parallels-windows-11-pvm.tar`, 60,705,433,600 bytes, sha256
  `b191286692...4d672c7`, 30 entries including the 53 GiB `.hds`, the `.mem`
  suspended state and `config.pvs`. **The local VM was not touched** — it is
  still `suspended` and still 57 GiB, which is the point: this is the copy that
  did not exist, not a move. Restoring it is `tar -C ~/Parallels -xf` followed
  by `prlctl register`.

Atrium stays untouched by the owner's decision, index growth included.

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
- [x] pip user packages — audited 2026-09-08, and they stay. `lxml` 6.1.1 and
  `pandas` 3.0.3 in `~/Library/Python/3.14/lib/python/site-packages` are live
  dependencies, not leftovers: `brain/tools/caixabank/convertCardXls.py` and
  `brain/tools/forense/{analyze,classify}.py` import pandas (analyze also
  numpy), and the docx/xlsx skill validators under `rocket-agents-library`
  import lxml. No old-pandas API use turned up in those scripts — the `.append(`
  hits are reportlab story lists, not DataFrames. The item's real point stands:
  never upgrade these unbounded, because the consumers are financial and
  forensic scripts whose output nobody re-checks by hand.
- [x] Helm plugin directory cleaned 2026-09-08: `~/Library/helm/plugins` held
  eight **dangling symlinks** from April — six `skaffold-render*` and two `tmp.*`
  pointing into `/var/folders/.../T/` paths macOS has long since cleared. Only
  the links were removed; `helm plugin list` still reports both real plugins.
- [x] Helm plugins updated 2026-09-08 on the owner's approval — `diff` 3.14.1 to
  3.15.12 and `dashboard` 2.0.3 to 2.1.3 — with the verification their own
  installers skip done by hand instead:

  1. Both plugin directories were copied to the session scratchpad first, so a
     rollback is a `cp -R` away.
  2. The upstream release tarball was downloaded separately and checked against
     the checksum file the project publishes:
     `helm-diff-macos-arm64.tgz` → `cb9e5b6c...632b580`, and
     `helm-dashboard_2.1.3_Darwin_arm64.tar.gz` → `0d6cb213...dedff85`. Both
     matched.
  3. That verified tarball was extracted and its binary hashed, then the plugin
     was updated through helm, then the *installed* binary was hashed and
     compared: `diff` → `0fff52a0...6e6a9cd`, `helm-dashboard` →
     `01faebb0...d737630`. Both identical to the verified reference, which is
     what proves the unverified download actually delivered the genuine release.
  4. `helm diff version` answers 3.15.12, `helm dashboard --version` answers
     2.1.3, and helm itself (v4.2.4) still lists both plugins.

  The defect in `helm-diff`'s installer is still there and still worth knowing —
  its `installFile` claims to verify a SHA256 and does not. That manual check is
  now automated, so it no longer depends on anyone remembering it.

  Original review — the finding that made this a decision:
  Sources are the legitimate upstreams (`databus23/helm-diff`,
  `komodorio/helm-dashboard`) over HTTPS, and both are behind: diff 3.14.1
  against 3.15.12, dashboard 2.0.3 against 2.1.3. But `helm-diff`'s
  `install-binary.sh` **does not verify anything**: its `installFile` comment
  says "verifies the SHA256 for the file" and the function only untars and
  copies, with no checksum fetched or compared — a leftover comment from the
  template it was copied from. So `helm plugin update diff` runs a script that
  downloads a release tarball and installs it unverified. That is not a
  maintenance step to take unattended; it is a decision about trusting a
  download.
- [x] Helm checksum verification automated 2026-09-08, replacing the by-hand
  procedure recorded above. `plugins/helm.sh` v1.1.0 now verifies every
  installed plugin binary on each run through four libraries:
  `helm_plugin_release_source` names the release assets for a plugin and
  platform, `helm_reference_digest` fetches the published checksums, confirms
  the archive against them and streams the archived binary into `shasum`,
  `find_helm_plugin_directory` maps a declared plugin name to its installation
  directory (they differ — `dashboard` installs into `helm-dashboard.git`), and
  `classify_helm_plugin_binary` compares the two digests.

  Three outcomes, deliberately distinct. `verified` is a byte-identical match.
  `mismatch` fails the plugin and prints both digests so the finding can be
  reproduced by hand. `unverifiable` only warns — an unreachable or corrupt
  download says nothing about the installed file, and failing the run on it is
  how a verification step becomes noise people learn to ignore.

  Two properties are worth keeping in mind. Nothing is ever extracted to disk:
  the archive member is streamed into `shasum`, so an archive that fails its
  checksum never becomes a file, and no recursive delete is needed — which is
  what `tests/runner/cleanup-safety.sh` demands. And the reference digest is
  cached per plugin and version, because the archives are 78 MiB and 71 MiB and
  the answer cannot change for a released version; a warm run is one local hash.

  Evidence — `./scripts/test-regressions.sh` is green (29 contracts), and the
  real run reproduces the hand-verified digests recorded above exactly:
  `diff` → `0fff52a0...6e6a9cd`, `dashboard` → `01faebb0...d737630`.

  The wiring mistake this cost is the part worth remembering: the libraries were
  sourced in `RocketUpdater.sh`, but plugins execute in
  `scripts/run-plugin.sh`, which loads its own list. Every helper worked, the
  runner loaded none of them, and the plugin reported "no plugins to verify" and
  exited 0 — a pass meaning the opposite of what it said. The tests had
  hand-sourced the libraries and so could not see it.
  `tests/plugins/helm-checksum-verified.sh` now drives `scripts/run-plugin.sh`
  instead, and fails if the runner stops loading them.
- [-] Cargo registry/src wholesale deletion — rejected. There are 491 extracted
  package trees with no matching local crate archive. A future selective tool
  may consider only exact source/archive matches while Rust processes are
  stopped.
