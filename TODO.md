# TODO — RocketUpdater

> Consolidated from cross-project filings and the run findings recorded since
> 2026-08-22. Last reviewed: 2026-09-19. History coverage: Complete.
>
> States: `[ ]` pending · `[~]` partial or unverified · `[!]` blocked · `[x]`
> verified complete · `[-]` obsolete or superseded. Closed work moves to
> `TODO_LOG.md`.

## Plugins

- [!] `xdevplatform/homebrew-tap` Casks/xurl.rb:37 calls the deprecated
  `postflight`; every brew invocation prints the warning on stderr, where it is
  now harmless to the run. No PR is possible: that file starts with "generated
  by GoReleaser. DO NOT EDIT", and it comes from `homebrew_casks.hooks.post.install`
  in `xdevplatform/xurl`'s `.goreleaser.yaml`, which GoReleaser always renders
  as a legacy `postflight do ... end`. GoReleaser has no `postflight_steps`
  support yet — tracked upstream in goreleaser/goreleaser#6870, still open on
  2026-09-19. Blocked on that issue; a patch to either repo would be
  overwritten by the next release.

## Waiting on the owner, not on work

Parked deliberately: the owner will decide them later, and nothing else should
touch them in the meantime. Everything else from the 2026-08-31 disk audit was
archived to the mini, pruned, or rejected on 2026-09-08 (see `TODO_LOG.md`).

- [ ] Steam — 66 GiB under `steamapps/common` on 2026-09-19, six titles,
  re-downloadable, so a UI uninstall of whichever titles the owner picks rather
  than an archive. The two Witcher installs alone are 32.6 GiB. Preserve
  Steam.AppBundle, account state, and the remaining library.
- [ ] The Parallels `.mem` suspended state — 3.2 GiB, released by resuming the
  VM and shutting Windows down properly. It discards the session saved on
  21 June, which is why it is the owner's call and not a maintenance step. The
  VM is still `suspended` on 2026-09-19; a full copy sits on the mini.
- [ ] Ollama — back in use after the 2026-09-08 removal: `ollama list` shows
  `qwen3.6:35b` (22 GB) and `qwen3.6:35b-mlx` (23 GB) pulled on 2026-09-17,
  `~/.ollama/models` is 43 GB, the brew service is stopped. Both are registry
  models and re-pullable; only the owner knows whether both variants are
  needed.
- [ ] Claude and Claude-favish application bundles — 14 GiB and 12 GiB under
  `~/Library/Application Support` on 2026-09-19. Decision: confirm both
  applications and local agents are stopped and accept the reprovisioning cost
  before removing any bundle.
