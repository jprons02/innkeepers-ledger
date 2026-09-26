# Kickoff runbook

> **Summary:** the ordered phases and steps from an empty repo to the v1 release, what to
> cut if the timeline slips, and when kickoff counts as complete. Bootstrap-only: move it
> to `docs/archive/` once v1 ships.
> **Read when:** picking the next build step, sequencing work against the launch window,
> or deciding what to cut.

## Status and client access

Running status, the client access plan (beta vs launch day) and what's waiting on the
maintainer live in [status.md](status.md), not here.

## Read first

`CLAUDE.md` (and its Context map), then [status.md](status.md). Open other docs through
the map as each step needs them.

## Sequence

The deadline that matters is **the Forever launch window (2026-11-04)**. Build the pure
logic first, since it doesn't need a game client, and do client verification as soon as a
Forever client is available.

**Phase 1 — foundation (no client needed)**
1. **Orient.** Read the docs; report scope, the hard rules and the riskiest part (sync
   validation) to the maintainer in a few lines. A report, not a wait.
2. Scaffold: TOC (interface number TBD, see platform doc), embedded Ace3 + LibDeflate,
   `.luacheckrc`, `.busted`, a stubbed WoW API layer for tests, and the folder layout
   from the architecture module table.
3. Add `luacheck` + `busted` to CI next to the policy guard (extend
   `.github/workflows/`).
4. Build loop on slice #1 = **`SyncProtocol` + `Ledger`**: entry schema, validation
   (every rule in the security model, with malicious-input tests), dedupe, caps and
   eviction. This is the riskiest foundation, so it's tested first and hardest.
5. `Phrase` + `Data/Phrases` (a first phrase set), then `Collection` + `Cosmetics`, then
   `Export` (finalize [export-format.md](export-format.md) to v1).

**Phase 1.5 — retail prototype (optional, while waiting for Forever access)**
- Throwaway harness on retail: gossip/NPC-ID detection, `IsResting()`, AceComm
  PARTY/GUILD/instance round-trips. Record findings in `platform-forever.md` as
  "retail-observed", not confirmed.

**Phase 2 — in the client (needs Forever and the maintainer at the keyboard)**
6. Work through the platform verification checklist; update `platform-forever.md`.
7. Collect innkeeper NPC IDs → `Data/Inns` for Forever.
8. `Sign` flow (gossip integration, `IsResting()`), then `Sync` transport, tested
   between two characters, including inside an instance.
9. `UI/Book`: parchment book, collection view, cosmetics, export box.

**Phase 3 — release**
10. BigWigs packager, CurseForge + Wago projects (free tiers only), screenshots,
    description (free, no outside links, "not affiliated with Blizzard").
11. Release in the launch window; post in r/wowaddons and the Forever community.
    **Maintainer gate:** tagging, publishing and posting.

If the timeline slips, cut scope in this order: cosmetics → export → guild sync (keep
party sync). The signing ritual and the collection are the core.

## Build loop

See `CLAUDE.md` → Build loop and Branch flow. Specs and review reports live in the repo.

## Kickoff complete when

- [ ] Pure modules built and tested; CI runs luacheck + busted green
- [ ] Platform checklist verified in a Forever client
- [ ] Signing, collection, party/guild sync and the book work in-game
- [ ] Published on CurseForge + Wago
