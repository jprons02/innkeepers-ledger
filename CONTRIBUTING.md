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

## Reporting bugs

Open an Issue with your game version, the AddOn version, what you did, and any Lua
error text (from `/console scriptErrors 1` or BugSack).
