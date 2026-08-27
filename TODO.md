# TODO — RocketUpdater

> Created 2026-08-22 from cross-project filings. States: `[ ]` pending, `[~]` partial,
> `[!]` blocked, `[x]` done, `[-]` obsolete.

- [ ] Commit or discard the untracked `.serena/` state in this checkout (also referenced from
      `~/p/osseus/TODO.md`; closing it here closes it there).
- [ ] Optional hygiene: 4 tracked shell scripts carry U+FE0F (emoji variation selector-16 in echo
      strings: `RocketUpdater.sh`, `lib/bash_colors.sh`, `scripts/format.sh`, `scripts/lint.sh`).
      Benign (verified 2026-08-22, rocket-agents hidden-unicode scan), but they will trip any
      future variation-selector CI scan; strip the VS16 or allowlist emoji if such a scan is
      added.

## Plugins

- [ ] Stop `plugins/homebrew.sh` retrying `brew upgrade --greedy` three times
  against the deterministic `gcloud-cli` failure. The cask's postflight deletes
  the optional virtualenv and rebuilds it with `pip install` from GitHub, and
  under the `brew` process that child consistently fails DNS resolution with
  `EAI_NONAME` while the identical command in a normal shell always succeeds —
  so every retry is a guaranteed loss of roughly a minute per run. Deliberately
  left alone when `heal_gcloud_cli()` landed (commit `e93ac91`, plugin v1.1.0):
  the heal covers the real breakage (relinking the five wrappers, rebuilding the
  virtualenv), and special-casing gcloud inside the generic retry looked
  fragile. Cheapest fix is probably skipping the retry for casks whose previous
  attempt failed in postflight, not naming gcloud.
