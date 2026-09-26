# Status

> **Summary:** where the project stands right now, what's next, and what's waiting on the
> maintainer. A snapshot, rewritten each session; history lives in git and
> [decisions.md](decisions.md).
> **Read when:** every session, first thing after `CLAUDE.md`.

**Updated:** 2026-09-26

## Current state

- Docs (vision, decisions, architecture, platform, policy, prior art, export draft): ✅
- Context map + conventions (`CLAUDE.md`), branch flow (`dev` → `main`): ✅
- Agent team (`.claude/agents/`): ✅ planner, implementer, reviewer
- CI: ✅ policy guard (runs on every push and PR, including `dev`); ⬜ luacheck + busted
  (lands with the first Lua; [kickoff.md](kickoff.md) step 3)
- Kickoff step 1 (orient): ✅ reported. Steps 2+ (scaffold onward): ⬜
- AddOn code: ⬜ none yet
- Client verification ([platform-forever.md](platform-forever.md) checklist): ⬜ no
  Forever client yet
- Local toolchain (Lua 5.1, luarocks, busted, luacheck): ⬜ not installed on the dev
  machine

## Next step

Kickoff step 2: scaffold (TOC, embedded Ace3 + LibDeflate, `.luacheckrc`, `.busted`,
folder layout, a stubbed WoW API layer for tests), install the local toolchain, then
step 3 (luacheck + busted in CI). After that, slice #1 (`SyncProtocol` + `Ledger`)
through the build loop.

## Client access plan

- **Beta window:** 2026-09-17 → **2026-10-21**. Launch: **2026-11-04**.
- **Default route: the free beta opt-in** on the official Forever site. Invites go out in
  waves and aren't guaranteed.
- **Paid route (maintainer's call only):** the higher-tier pre-purchase editions include
  beta access. Buying one is never done on the project's behalf; it happens only if the
  maintainer names that purchase.
- **Retail as a stand-in:** Forever reportedly uses the retail-style API, so generic
  mechanics (gossip events, `UnitGUID("npc")` parsing, `IsResting()`, AceComm round-trips,
  instance messaging) can be prototyped on retail. Results are only indicative until
  confirmed on Forever. The innkeeper list and TOC interface number can't be substituted.

**Branches of the plan:**
- **Beta access by ~2026-10-03:** run Phase 2 during the beta and aim to release at launch.
- **No beta access:** finish Phase 1 plus retail prototyping before launch, run Phase 2 on
  launch day, and release **~1–2 weeks after launch**.

## Open questions (maintainer to decide)

- **Beta access:** opted in? Invited? Decides which plan branch applies (by ~2026-10-03).
- **Sender identity per channel.** Addon messages carry the sender's *name*, not GUID.
  Group members can be resolved name → GUID; guild members likely via the guild roster
  (verify); strangers on a future global channel can't. The slice-1 spec proposes how the
  own-signature rule binds on each channel; confirm the proposal. Ties into how names
  look on the mega-realm (platform checklist).

## Waiting on the maintainer in the client (batch)

These need someone at the keyboard in a Forever client. Everything else proceeds without
them. Full list: [platform-forever.md → Verification checklist](platform-forever.md#verification-checklist-needs-a-forever-client-beta-until-2026-10-21-or-launch-2026-11-04).

- TOC interface number; AddOn loads
- Innkeeper gossip: `GOSSIP_SHOW` + NPC ID from `UnitGUID("npc")`; option injection works
- `IsResting()` inside inns; sitting detection, if any
- AceComm PARTY / RAID / GUILD between two characters, including inside an instance
- Player GUID and name format on the mega-realm
- Walk every inn to collect innkeeper NPC IDs (`Data/Inns`)

## Follow-ups

- Move [kickoff.md](kickoff.md) to `docs/archive/` once v1 ships.
- Publish `Data/Inns` / `Data/Phrases` as a generated reference for export consumers
  ([export-format.md](export-format.md)), before export v1 is finalized.
