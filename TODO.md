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
