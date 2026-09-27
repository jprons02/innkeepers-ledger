# Status

> **Summary:** where the project stands right now, what's next, and what's waiting on the
> maintainer. A snapshot, rewritten each session; history lives in git and
> [decisions.md](decisions.md).
> **Read when:** every session, first thing after `CLAUDE.md`.

**Updated:** 2026-09-27 (after #46)

## Current state

- **Foundation:** docs and context map, branch flow with protection on `main` and `dev`,
  the agent team, ticket forms and labels, kickoff steps 1–3 ([kickoff.md](kickoff.md)).
  Libraries reviewed and vendored in `Libs/` ([libraries.md](libraries.md)). The
  scaffold (#8) loads the whole AddOn under `busted` through a WoW API stub.
- **CI:** seven required checks on `main` and `dev`: `no-urls-in-game-code`, `luacheck`,
  `busted` (Lua 5.1), `coverage` (floors on pure modules), `docs-links`,
  `libs-manifest`, `forbidden-apis`. Release PRs also get a security review
  ([security-checklist.md](security-checklist.md)). Every check also runs locally
  ([CONTRIBUTING.md](../CONTRIBUTING.md#development-setup)); run them before pushing.
- **Slice 1 done (#10):** spec [specs/sync-ledger.md](specs/sync-ledger.md) (wire format,
  digest, validation, caps, rate limits, SavedVariables). `Ledger` (#30) and
  `SyncProtocol` (#31) built, both at 100% line coverage; `SyncProtocol` passed a
  security-level review (2.2 M differential-fuzz messages, every security mutant
  killed). Re-signing an inn: once per week, at the game's weekly reset.
- **Slice 2 in progress (#41),** spec [specs/sync-glue.md](specs/sync-glue.md):
  - **#44 `Core` done:** opens the character's ledger at login as `ns.ledger` (GUID
    retry, weekly anchor with region fallback, damaged-data handling, `/ledger debug`).
  - **#45 `SyncSchedule` done** (PR #52): the pure send schedule, 100% coverage under a
    95% floor. Its security-level review fuzzed hours of simulated time; every bound
    held, and one late-wake bug was found and fixed. Failed sends keep their gates
    (decisions.md → *SyncSchedule: failed sends keep their gates*).
  - **#46 `Sync` receive path done** (PR #55): hidden-value checks, sender resolution
    (group via `UnitGUID`, guild via the roster map), `SyncProtocol.receive`, dispatch
    into `SyncSchedule`, `stats` at `ns.Sync.stats` (shown by `/ledger debug`), and a
    multi-client harness (`spec/helpers/sync_harness.lua`). Nothing is sent yet;
    `onHello` / `onWant` are ignored until #47 makes the channels available. Its
    security review found no code defect but one design hole in the spec (#54).
  - Other module logic (`Phrase`, `Collection`, `Cosmetics`, `Export`, UI): ⬜ none yet.
- **Releases:** `main` = `dev` as of #24 (2026-09-26). Since then `dev` has docs and CI
  changes (#25–#39) and module logic (`Ledger` #38, `SyncProtocol` #40, `Core` #50,
  `SyncSchedule` #52, `Sync` receive #55). No tags yet (maintainer gate).
- **Direction (2026-09-27):** the inn ledger stays, leaning into a passport feel (stamp
  per inn, seal per zone). A public profile website is a post-v1, separate project the
  AddOn never names ([vision.md](vision.md) → Where it can grow).
- **Client verification** ([platform-forever.md](platform-forever.md)): ⬜ no Forever
  client yet.

## Next step

1. **#47** `Sync` send path, combat hold and the `combat state` guard rule (`ready`).
   Its 40-player-raid simulation checks the traffic model.
   - From #46: `Sync.lua` needs `requestPump` filled (a no-op now), `send` and the
     combat function added to `realDeps().api`, and more `EVENTS`. `stats.sent` and
     `sendFailed` exist but nothing counts them yet. The harness's send switches
     (`c.sendMode` = `"sync"` / `"defer"` / `"fail"`, `c.sendDelay`) and
     `w:setGroup(members, raid)` are ready; what it lacks is in
     [specs/sync-glue.md §6.1](specs/sync-glue.md#61-harness-and-stub).
   - From #45: the glue passes `ledger:shareWindow(SHARE_MAX)` as `io.window` and to
     `onWant`; the schedule counts its own failed sends in `snapshot().sendFailed`; its
     gates never reach the 30-message cap on their own (at most 29 at once), so the cap
     is a backstop.
   - Keep the `partyN` / `raidN` scan in one function; #54 extends it.
2. **#54** Group senders resolve through our own unit scan, never `UnitGUID(sender)`
   (blocked by #47; must land before the first release). A character named like a unit
   token (`Target`, `Focus`) could otherwise get entries stored under another player's
   GUID (decisions.md → *Group senders resolve through our own unit scan*).

Then, unfiled, from [kickoff.md](kickoff.md) Phase 1 step 5: `Phrase` + `Data/Phrases`,
`Collection` + `Cosmetics`, `Export`. Until `Data/Phrases` has entries, every received
entry is rejected as an unknown phrase. In-client work is #12.

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
the sync specs lean on its GUID-format, message-size, `INSTANCE_CHAT` and weekly-reset
items.

## Follow-ups

- Move [kickoff.md](kickoff.md) to `docs/archive/` once v1 ships.
- Server time jumping *forward* isn't clamped in `SyncSchedule` (decisions.md →
  *SyncSchedule: failed sends keep their gates*); revisit if #12 shows it happens.
- Delete GitHub's default labels (`bug`, `enhancement`, …), which overlap ours
  (maintainer call: deletion).
- Publish `Data/Inns` / `Data/Phrases` as a generated reference for export consumers
  before export v1 is finalized ([export-format.md](export-format.md)).
- CI pins only the top-level rocks; if an upstream release breaks CI, pin dependencies too.
- `Ledger`'s cap pass at load time is quadratic: a tampered SavedVariables file far over
  the caps (40 000 entries) loads in about 4 s. Peers can't reach this; batch the
  evictions if it ever matters (decisions.md → 2026-09-27 — Ledger orders by bytes).
- Another AddOn's hidden addon traffic is counted and logged as a `hidden` drop, since
  the hidden check comes before the prefix (decisions.md → *Sync receive: fail-closed
  choices*); revisit if #12 shows hidden senders.
- `decisions.md` is at about 690 lines. At the start of October, move the September entries to
  `docs/archive/decisions-2026-09.md` and leave an index line.
