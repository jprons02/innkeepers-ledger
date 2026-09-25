# Kickoff runbook · START HERE

> **Bootstrap-only.** This tells the first build sessions what to do and in what order.
> Once v1 ships, move it to `docs/archive/`. Standing context lives in `CLAUDE.md`, the
> "why" in `docs/vision.md` + `docs/decisions.md`, the "how" in `docs/architecture.md`.

## Where things stand

- Vision, decisions, architecture, platform facts, policy, prior art: ✅ written
- Agent team (`.claude/agents/`): ✅ planner, implementer, reviewer
- CI: ✅ policy guard only; ⬜ luacheck + busted (step 3)
- AddOn code: ⬜ none yet
- Client verification ([platform-forever.md](platform-forever.md) checklist): ⬜ needs
  a Forever client (beta, or launch day 2026-11-04)

## Client access plan

The in-client work needs a WoW: Forever client. As of 2026-09-25 we don't have one yet.

- **Beta window:** 2026-09-17 → **2026-10-21**. Launch: **2026-11-04**.
- **Free route:** beta opt-in on the official Forever site. Invites go out in waves and
  aren't guaranteed.
- **Guaranteed route:** the higher-tier Forever pre-purchase editions include beta
  access; the cheapest edition does not. (Check the current edition details before
  buying.)
- **Retail as a stand-in:** Forever reportedly uses the retail-style API. Generic
  mechanics (gossip events, `UnitGUID("npc")` parsing, `IsResting()`, AceComm
  round-trips, instance messaging) can be prototyped on retail. The results are only
  indicative until confirmed on Forever. Forever-specific data (the innkeeper list, the
  TOC interface number) can't be substituted.

**Branches:**
- **Beta access by ~2026-10-03:** follow Phase 2 during the beta and aim to release at
  launch.
- **No beta access:** finish Phase 1 plus retail prototyping before launch, then run
  Phase 2 on launch day and release **~1–2 weeks after launch**. Still early enough to
  be discovered; the collection and innkeeper IDs are the long pole.

## Read first, in order

1. `CLAUDE.md`
2. `docs/vision.md`
3. `docs/decisions.md` (settled; don't redo)
4. `docs/architecture.md`
5. `docs/platform-forever.md` (know what's unverified)

## Sequence

The deadline that matters is **the Forever launch window (2026-11-04)**. Build the pure
logic first, since it doesn't need a game client, and do client verification as soon as a
Forever client is available.

**Phase 1 — foundation (no client needed)**
1. **Orient.** Read the docs; summarize scope, the hard rules and the riskiest part
   (sync validation) back to the human in a few lines. **No code yet.** *(human
   confirms)*
2. Scaffold: TOC (interface number TBD, see platform doc), embedded Ace3 + LibDeflate,
   `.luacheckrc`, `.busted`, folder layout per the architecture module table.
3. Add `luacheck` + `busted` to CI (extend `.github/workflows/`).
4. Build loop on slice #1 = **`SyncProtocol` + `Ledger`**: entry schema, validation
   (every rule in the security model, with malicious-input tests), dedupe, caps and
   eviction. This is the riskiest foundation, so it's tested first and hardest.
5. `Phrase` + `Data/Phrases` (a first phrase set), then `Collection` + `Cosmetics`, then
   `Export` (finalize [export-format.md](export-format.md) to v1).

**Phase 1.5 — retail prototype (optional, while waiting for Forever access)**
- Throwaway harness on retail: gossip/NPC-ID detection, `IsResting()`, AceComm
  PARTY/GUILD/instance round-trips. Record findings in `platform-forever.md` as
  "retail-observed", not confirmed.

**Phase 2 — in the client (needs Forever)**
6. Work through the platform verification checklist; update `platform-forever.md`.
7. Collect innkeeper NPC IDs → `Data/Inns` for Forever.
8. `Sign` flow (gossip integration, `IsResting()`), then `Sync` transport, tested
   between two characters, including inside an instance.
9. `UI/Book`: parchment book, collection view, cosmetics, export box.

**Phase 3 — release**
10. BigWigs packager, CurseForge + Wago projects, screenshots, description (free,
    no outside links, "not affiliated with Blizzard").
11. Release in the launch window; post in r/wowaddons and the Forever community.

If the timeline slips, cut scope in this order: cosmetics → export → guild sync (keep
party sync). The signing ritual and the collection are the core.

## Build-loop protocol

`planner → docs/specs/<feature>.md → human approves spec → implementer → reviewer → human sign-off → merge`

- Agents hand back to the orchestrating session, not to each other.
- Specs and review reports live in the repo.
- Anything touching sync or deserialization gets the reviewer's security-level
  scrutiny.

## Kickoff complete when

- [ ] Pure modules built and tested; CI runs luacheck + busted green
- [ ] Platform checklist verified in a Forever client
- [ ] Signing, collection, party/guild sync and the book work in-game
- [ ] Published on CurseForge + Wago
