# Status

> **Summary:** where the project stands right now, what's next, and what's waiting on the
> maintainer. A snapshot, rewritten each session; history lives in git and
> [decisions.md](decisions.md).
> **Read when:** every session, first thing after `CLAUDE.md`.

**Updated:** 2026-09-27 (after #11 / #32)

## Current state

- **Foundation done:** docs and context map, branch flow with protection on `main` and
  `dev`, the agent team, ticket forms and labels, kickoff steps 1–3
  ([kickoff.md](kickoff.md)).
- **AddOn scaffold (#8):** TOC (placeholder interface number), `Libs/embeds.xml`, every
  module as an empty stub on the shared `ns`, `Core` with AceDB + `/ledger`, and a WoW
  API stub so the whole AddOn loads under `busted`. Module logic: ⬜ none yet.
- **Slice-1 spec done (#11, #32):** [specs/sync-ledger.md](specs/sync-ledger.md) settles
  the wire format, digest, validation table, storage caps, rate limits (with a traffic
  model) and SavedVariables shape. It passed two security-level reviewer passes; the
  first caught a WANT fan-out that would have broken the rate limits in raids.
  Re-signing an inn: once per week, turning over at the game's weekly reset (maintainer,
  2026-09-27), enforced for own and incoming signatures.
- **Libraries:** reviewed and vendored in `Libs/`, manifest pinned to
  [libraries.md](libraries.md).
- **CI:** five required checks on `main` and `dev`: `no-urls-in-game-code`, `luacheck`,
  `busted` (Lua 5.1), `libs-manifest`, `forbidden-apis`. Release PRs also get a security
  review ([security-checklist.md](security-checklist.md)).
- **Releases:** `main` = `dev` as of #24 (2026-09-26). Since then `dev` has docs-only
  changes (#25–#32). No tags yet (maintainer gate).
- **Direction (2026-09-27):** the inn ledger stays, leaning into a passport feel (stamp
  per inn, seal per zone). A public profile website is a post-v1, separate project the
  AddOn never names ([vision.md](vision.md) → Where it can grow).
- **Client verification** ([platform-forever.md](platform-forever.md)): ⬜ no Forever
  client yet.
- **Local toolchain:** Lua 5.1 + busted + luacheck live in a hererocks folder that isn't
  on the agent shell's `PATH` ([CONTRIBUTING.md](../CONTRIBUTING.md)), so CI is the
  authority for busted/luacheck. The folder's `bin/lua.exe` runs by full path for quick
  Lua 5.1 checks (the spec's digest vectors were computed that way).
  `scripts/check-*.sh` run locally with `sh`.

## Next step

**#30: build `Ledger`** (`ready`), then **#31: build `SyncProtocol`** (blocked by #30).
Both are sub-issues of slice 1 (#10) and implement the spec above. When #31 is done,
file the `Sync` glue ticket from the spec's §8 (send budget, HELLO debounce, WANT
jitter, deferred full replies, combat hold with its `forbidden-apis` allow-list change).

In-client work is #12 (needs a Forever client and the maintainer).

## Client access plan

- **Beta window:** 2026-09-17 → **2026-10-21**. Launch: **2026-11-04**.
- **Default route:** the free beta opt-in (invites in waves, not guaranteed). The paid
  pre-purchase route is the maintainer's call only, never bought for the project.
- **Retail as a stand-in:** generic mechanics (gossip events, `UnitGUID("npc")`,
  `IsResting()`, addon-message round-trips) can be prototyped there; results are only
  indicative, and the innkeeper list and TOC number can't be substituted.
- **Beta access by ~2026-10-03:** run Phase 2 during the beta, aim to release at launch.
  **No beta access:** finish Phase 1 plus retail prototyping, run Phase 2 on launch day,
  release ~1–2 weeks after launch.

## Open questions (maintainer to decide)

- **Beta access (#1, #2):** not opted in as of 2026-09-27. The free opt-in costs nothing;
  opting in soon improves the odds. Decides the plan branch by ~2026-10-03.

## Waiting on the maintainer in the client

Batched in #12. The list lives in
[platform-forever.md → Verification checklist](platform-forever.md#verification-checklist-needs-a-forever-client-beta-until-2026-10-21-or-launch-2026-11-04);
the slice-1 spec leans on its GUID-format, message-size, `INSTANCE_CHAT` and weekly-reset
items.

## Follow-ups

- Move [kickoff.md](kickoff.md) to `docs/archive/` once v1 ships.
- Delete GitHub's default labels (`bug`, `enhancement`, …), which overlap ours
  (maintainer call: deletion).
- Publish `Data/Inns` / `Data/Phrases` as a generated reference for export consumers
  before export v1 is finalized ([export-format.md](export-format.md)).
- CI pins only the top-level rocks; if an upstream release breaks CI, pin dependencies too.
- `decisions.md` is at 467 lines. At the start of October, move the September entries to
  `docs/archive/decisions-2026-09.md` and leave an index line. `architecture.md` is at
  197; split a section out before adding to it.
