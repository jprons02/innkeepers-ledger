# Contributing

Thanks for stopping by the inn.

## Before you open a PR

- Read [docs/vision.md](docs/vision.md) and [docs/decisions.md](docs/decisions.md).
  Decisions there are settled; if you want to reopen one, open an Issue first
  and explain what changed.
- Keep it in scope. This AddOn signs inns and collects travelers. Features that
  read combat data, automate gameplay, or talk to anything outside the game won't be
  accepted.
- **No advertising, links, or references to outside products, sites, or services** in
  any in-game text, and no paid or gated features. This is Blizzard AddOn policy, not
  preference ([docs/addon-policy.md](docs/addon-policy.md)).

## Code

- Lua 5.1 (the WoW client's dialect). Match the surrounding style.
- Keep game-independent logic (sync merge, validation, collection math, the phrase
  builder, export encoding) in pure modules with no WoW API calls, so it's unit-testable
  with `busted` outside the client. See [docs/architecture.md](docs/architecture.md).
- Anything that parses data from another player is **untrusted input**. Follow the
  validation rules in the architecture doc.

## Development setup

Tests need Lua 5.1 with `busted`, `luacheck` and `luacov`. `hererocks` (a Python
package) builds a self-contained Lua 5.1 + LuaRocks in one folder:

- **Linux / macOS:** `pip install hererocks`, then
  `hererocks <dir> -l 5.1 -r latest`, then
  `<dir>/bin/luarocks install busted`, `… luacheck` and `… luacov`.
- **Windows:** use MSYS2's UCRT64 environment
  (`pacman -S mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-make mingw-w64-ucrt-x86_64-hererocks`)
  and add `--target mingw` to the hererocks command. Before installing rocks, set
  `MSVCRT = 'ucrt'` in `<dir>/luarocks/config-5.1.lua`; otherwise C modules link against
  a runtime that isn't installed and fail with "The specified module could not be
  found". Run tools as `luarocks.bat`, `busted.bat`, `luacheck.bat` and `luacov.bat`,
  with `<dir>/bin` and MSYS2's `ucrt64/bin` on `PATH`. The tools aren't on `PATH` by
  default, so put them there for the session first; in PowerShell:
  `$env:PATH = "C:\msys64\ucrt64\bin;<dir>\bin;$env:PATH"`. The `sh scripts/…` checks
  run from Git Bash (PowerShell has no `sh`).

Before opening a PR, run these from the repo root. CI runs the same checks, and all of
them are required:

| Check | Command |
|---|---|
| Tests | `busted` |
| Lint | `luacheck .` |
| Coverage floors | `busted --coverage --exclude-tags=sim`, then `luacov`, then `sh scripts/check-coverage.sh` |
| Forbidden APIs | `sh scripts/check-apis.sh` |
| Vendored libraries | `sh scripts/check-libs.sh` |
| Doc links and context map | `sh scripts/check-links.sh` |
| Release checks (self-tests) | `sh scripts/check-release.sh --self-test`, `sh scripts/check-package.sh --self-test` (seconds on Linux, a few minutes in Git Bash) |

The packager's dry run itself (`package` in `.github/workflows/release.yml`) runs only in
CI; see [Releasing](#releasing).

[docs/security-checklist.md](docs/security-checklist.md) explains the API and library
checks.

**Coverage floors.** Every pure module must keep line coverage at or above its floor:
95% for `Ledger`, `SyncProtocol` and `SyncSchedule` (the sync boundary), 90% for the other pure
modules. Glue isn't measured; it's checked in the client. Code can't opt out with a
`luacov:` comment, and changing a floor needs a decision-log entry. Coverage says which
lines ran, not that they're right: the hostile-input tests in the specs still decide
whether a module is done.

## Branches and pull requests

- Branch from `dev`: `feat/<slug>`, `fix/<slug>`, `chore/<slug>` or `docs/<slug>`.
- Open the PR against `dev`. It's squash-merged once CI is green.
- `main` only receives `dev → main` release PRs.
- **A check that failed for GitHub's reasons** (the job log says "not acquired by Runner
  … even after multiple attempts", a 15-minute timeout, a job cancelled at its own
  `timeout-minutes` during the install step, or `apt failed after 3 attempts` from
  `scripts/ci-apt-install.sh`) isn't a code failure. Re-run it
  from the Actions page; the agents' token can't (`gh run rerun` gets "Resource not
  accessible by personal access token"), so agents push an empty commit to the branch
  instead, which starts fresh runs. Check [githubstatus.com](https://www.githubstatus.com/)
  first: during an Actions incident, retries keep timing out until it's mitigated.
- **When `gh pr create` or `gh pr merge` fails with "GraphQL: Something went wrong"**, the
  REST API usually still works: `gh api repos/<owner>/<repo>/pulls -f base=dev -f head=<branch>
  -f title=... -F body=@<file>` opens the PR, and `gh api -X PUT
  repos/<owner>/<repo>/pulls/<n>/merge -f merge_method=squash` merges it (seen 2026-10-06).

## Releasing

Releases are built by the BigWigs packager in `.github/workflows/release.yml`. Tagging
and publishing are the maintainer's; everything before them is checked in CI.

- **Every PR** runs `package`: the packager with `-d -u` (no upload, Unix line endings),
  then `scripts/check-package.sh` on the zip. A manual run (*Actions → release → Run
  workflow*) does the same for any branch. Only the maintainer can start one: the
  agents' token gets a 403 on that.
- **Release notes** go in `CHANGELOG.md` under `## vX.Y.Z` before tagging. It ships in
  the AddOn and is the text on the download pages, so it's plain: no links, no site or
  product names. The packager never builds notes from commit messages.
- **To release** (maintainer): merge the `dev → main` release PR, then on `main`
  `git tag vX.Y.Z && git push origin vX.Y.Z`. The tag must be `vX.Y.Z` (numbers, no
  leading zeros) on a commit that's on `main` (the check fails otherwise); it becomes
  the TOC's `## Version`. `package` runs again for the tag; then `publish` waits for
  approval in the `release` environment. Approving builds and checks the package once
  more and uploads it to CurseForge, Wago and a GitHub release (the file label reads
  `vX.Y.Z-forever`, the packager's game suffix), then checks the uploaded build again.
- **Download pages** (CurseForge `1721704`, Wago `n6VYeONd`): the text and rules are in
  [docs/decisions.md](docs/decisions.md) (2026-10-01, *Distribution pages*): no outbound
  links. The logo's source is `media/logo.svg` (render `media/logo.png` at 500×500;
  `media/` never ships).
- **Before the first release:** the CurseForge and Wago projects exist, their IDs are
  in the TOC (`## X-Curse-Project-ID`, `## X-Wago-ID`), and the maintainer has put
  `CF_API_TOKEN` and `WAGO_API_TOKEN` into the `release` environment. Never paste a
  token anywhere else. Without an ID or token, the packager skips that site.

## Reporting bugs

Open an Issue with your game version, the AddOn version, what you did, and any Lua
error text (from `/console scriptErrors 1` or BugSack).
