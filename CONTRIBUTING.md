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

Tests need Lua 5.1 with `busted` and `luacheck`. `hererocks` (a Python package) builds a
self-contained Lua 5.1 + LuaRocks in one folder:

- **Linux / macOS:** `pip install hererocks`, then
  `hererocks <dir> -l 5.1 -r latest`, then `<dir>/bin/luarocks install busted luacheck`.
- **Windows:** use MSYS2's UCRT64 environment
  (`pacman -S mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-make mingw-w64-ucrt-x86_64-hererocks`)
  and add `--target mingw` to the hererocks command. Before installing rocks, set
  `MSVCRT = 'ucrt'` in `<dir>/luarocks/config-5.1.lua`; otherwise C modules link against
  a runtime that isn't installed and fail with "The specified module could not be
  found". Run tools as `luarocks.bat`, `busted.bat` and `luacheck.bat`, with
  `<dir>/bin` and MSYS2's `ucrt64/bin` on `PATH`.

Run `busted` and `luacheck .` from the repo root before opening a PR. CI runs the same
checks.

## Branches and pull requests

- Branch from `dev`: `feat/<slug>`, `fix/<slug>`, `chore/<slug>` or `docs/<slug>`.
- Open the PR against `dev`. It's squash-merged once CI is green.
- `main` only receives `dev → main` release PRs.

## Reporting bugs

Open an Issue with your game version, the AddOn version, what you did, and any Lua
error text (from `/console scriptErrors 1` or BugSack).
