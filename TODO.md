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
