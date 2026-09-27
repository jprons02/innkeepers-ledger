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
| Coverage floors | `busted --coverage`, then `luacov`, then `sh scripts/check-coverage.sh` |
| Forbidden APIs | `sh scripts/check-apis.sh` |
| Vendored libraries | `sh scripts/check-libs.sh` |
| Doc links and context map | `sh scripts/check-links.sh` |

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

## Reporting bugs

Open an Issue with your game version, the AddOn version, what you did, and any Lua
error text (from `/console scriptErrors 1` or BugSack).
