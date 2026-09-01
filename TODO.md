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
