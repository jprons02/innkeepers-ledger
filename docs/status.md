# Status

> **Summary:** where the project stands right now, what's next, and what's waiting on the
> maintainer. A snapshot, rewritten each session; history lives in git and
> [decisions.md](decisions.md).
> **Read when:** every session, first thing after `CLAUDE.md`.

**Updated:** 2026-09-27 (after #42)

## Current state

- **Foundation done:** docs and context map, branch flow with protection on `main` and
  `dev`, the agent team, ticket forms and labels, kickoff steps 1–3
  ([kickoff.md](kickoff.md)).
- **AddOn scaffold (#8):** TOC (placeholder interface number), `Libs/embeds.xml`, every
  module as an empty stub on the shared `ns`, `Core` with AceDB + `/ledger`, and a WoW
  API stub so the whole AddOn loads under `busted`.
- **Slice 1 done (#10 closed):**
  - **`Ledger`** (#30, PR #38): the entry store, weekly rule, caps and eviction,
    queries, earned times, and load, migration and read-only behavior.
  - **`SyncProtocol`** (#31, PR #40): encoders, strict decoder (rules 1–19), digest,
    limiter, WANT memo and `decideWant`.
  - Both have 100% line coverage. The security-level review of `SyncProtocol` passed:
    2.2 M differential-fuzz messages with 0 mismatches, and every security mutant is
    killed. Other module logic: ⬜ none yet.
- **Slice-1 spec done (#11, #32):** [specs/sync-ledger.md](specs/sync-ledger.md) settles
  the wire format, digest, validation table, storage caps, rate limits (with a traffic
  model) and SavedVariables shape. It passed two security-level reviewer passes; the
  first caught a WANT fan-out that would have broken the rate limits in raids.
  Re-signing an inn: once per week, turning over at the game's weekly reset (maintainer,
  2026-09-27), enforced for own and incoming signatures.
- **Libraries:** reviewed and vendored in `Libs/`, manifest pinned to
  [libraries.md](libraries.md).
- **CI:** seven required checks on `main` and `dev`: `no-urls-in-game-code`, `luacheck`,
  `busted` (Lua 5.1), `coverage` (floors on pure modules), `docs-links`,
  `libs-manifest`, `forbidden-apis`. Release PRs also get a security review
  ([security-checklist.md](security-checklist.md)).
- **Releases:** `main` = `dev` as of #24 (2026-09-26). Since then `dev` has docs and CI
  changes (#25–#39; #36 added the `coverage` and `docs-links` checks) and the first
  module logic (`Ledger` #38, `SyncProtocol` #40). No tags yet (maintainer gate).
- **Direction (2026-09-27):** the inn ledger stays, leaning into a passport feel (stamp
  per inn, seal per zone). A public profile website is a post-v1, separate project the
  AddOn never names ([vision.md](vision.md) → Where it can grow).
- **Client verification** ([platform-forever.md](platform-forever.md)): ⬜ no Forever
  client yet.
- **Local toolchain works:** Lua 5.1, busted, luacheck and luacov run locally once
  their folder and MSYS2's `ucrt64/bin` are put on `PATH` for the session (PowerShell
  line in [CONTRIBUTING.md](../CONTRIBUTING.md#development-setup)). Run every check
  locally before pushing; CI confirms.

## Next step

**Slice 2 (#41, the `Sync` glue) is specced** in [specs/sync-glue.md](specs/sync-glue.md)
(#42). The spec passed a security-level review; the first pass caught a timer pile-up
and a send stall on late callbacks, both fixed. Build it in order:
1. **#44** `Core` opens the character's ledger at login (`ready`) and **#45**
   `SyncSchedule`, the pure send schedule (`ready`). These two can run in parallel.
2. **#46** `Sync` receive path and sender resolution (blocked by #44, #45).
3. **#47** `Sync` send path, combat hold and the `combat state` guard rule (blocked by
   #46). Its 40-player-raid simulation checks the traffic model.

Also unfiled from [kickoff.md](kickoff.md) Phase 1 step 5: `Phrase` + `Data/Phrases`,
then `Collection` + `Cosmetics`, then `Export`. Until `Data/Phrases` has entries, every
received entry is rejected as an unknown phrase.

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
- **Debug toggle wording (non-blocking):** `/ledger debug` and its `Debug log on.` /
  `Debug log off.` lines are developer-facing placeholders
  ([specs/sync-glue.md §3.8](specs/sync-glue.md#38-debug-log-and-stats)). Keep them, or
  give a direction. #44 builds with the placeholders.

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
- `Ledger`'s cap pass at load time is quadratic: a tampered SavedVariables file far over
  the caps (40 000 entries) loads in about 4 s. Peers can't reach this, so it's not
  needed for v1; batch the evictions if it ever matters (decisions.md → 2026-09-27 —
  Ledger orders by bytes).
- `decisions.md` is at 604 lines. At the start of October, move the September entries to
  `docs/archive/decisions-2026-09.md` and leave an index line. `architecture.md` is at
  198; split a section out before adding to it.
