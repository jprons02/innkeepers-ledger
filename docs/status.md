# Status

> **Summary:** where the project stands right now, what's next, and what's waiting on the
> maintainer. A snapshot, rewritten each session; history lives in git and
> [decisions.md](decisions.md).
> **Read when:** every session, first thing after `CLAUDE.md`.

**Updated:** 2026-09-27 (after #11)

## Current state

- **Foundation done:** docs and context map, branch flow with protection on `main` and
  `dev`, the agent team, ticket forms and labels, kickoff steps 1–3
  ([kickoff.md](kickoff.md)).
- **AddOn scaffold (#8):** TOC (placeholder interface number), `Libs/embeds.xml`, every
  module as an empty stub on the shared `ns`, `Core` with AceDB + `/ledger`, and a WoW
  API stub so the whole AddOn loads under `busted`. Module logic: ⬜ none yet; the slice-1
  spec ([specs/sync-ledger.md](specs/sync-ledger.md)) is written (#11).
- **Libraries:** reviewed and vendored in `Libs/`, manifest pinned to
  [libraries.md](libraries.md).
- **CI:** five required checks on `main` and `dev`: `no-urls-in-game-code`, `luacheck`,
  `busted` (Lua 5.1), `libs-manifest`, `forbidden-apis`. Release PRs also get a security
  review ([security-checklist.md](security-checklist.md)).
- **Releases:** `main` = `dev` as of #24 (2026-09-26). Since then `dev` has docs-only
  changes (#25–#27). No tags yet (maintainer gate).
- **Direction re-confirmed (2026-09-27):** after a pivot review the inn ledger stays,
  with the collection leaning into a passport feel (stamp per inn, seal per zone). A
  public profile website is a post-v1, separate project that the AddOn never names
  ([vision.md](vision.md) → Where it can grow; [decisions.md](decisions.md)).
- **Client verification** ([platform-forever.md](platform-forever.md)): ⬜ no Forever
  client yet.
- **Local toolchain:** Lua 5.1 + busted + luacheck in a hererocks folder that isn't on
  the agent shell's `PATH` ([CONTRIBUTING.md](../CONTRIBUTING.md)), so CI is the
  authority for busted/luacheck. `scripts/check-*.sh` run locally with `sh`.

## Next step

**#30: build `Ledger`**, then **#31: build `SyncProtocol`** (blocked by #30). Both are
sub-issues of slice 1 (#10) and implement
[specs/sync-ledger.md](specs/sync-ledger.md), which settles the wire format, digest,
validation table, caps, rate limits and SavedVariables shape (#11). The spec's §8 is the
contract for the later `Sync` glue ticket (combat hold, hidden values, reply
coalescing); file that ticket when #31 is done.

In-client work is #12 (needs a Forever client and the maintainer).

## Client access plan

- **Beta window:** 2026-09-17 → **2026-10-21**. Launch: **2026-11-04**.
- **Default route: the free beta opt-in** on the official Forever site. Invites go out in
  waves and aren't guaranteed.
- **Paid route (maintainer's call only):** higher-tier pre-purchase editions include
  beta access. Never bought on the project's behalf.
- **Retail as a stand-in:** generic mechanics (gossip events, `UnitGUID("npc")`,
  `IsResting()`, addon-message round-trips) can be prototyped on retail. Results are only
  indicative; the innkeeper list and TOC interface number can't be substituted.

**Branches of the plan:**
- **Beta access by ~2026-10-03:** run Phase 2 during the beta and aim to release at launch.
- **No beta access:** finish Phase 1 plus retail prototyping before launch, run Phase 2 on
  launch day, and release **~1–2 weeks after launch**.

## Open questions (maintainer to decide)

- **Beta access (#1, #2):** not opted in as of 2026-09-27. The free opt-in costs nothing;
  opting in soon improves the odds. Decides the plan branch by ~2026-10-03.
- **Re-signing an inn (not blocking; needed by the `Sign` slice):** how often may a
  player sign the same inn again? Proposed: once per inn per day. It bounds how fast own
  entries grow (they're never evicted) and keeps the 40-entry share window varied.

## Waiting on the maintainer in the client (batch)

Tracked in #12; full list in [platform-forever.md → Verification checklist](platform-forever.md#verification-checklist-needs-a-forever-client-beta-until-2026-10-21-or-launch-2026-11-04).

- TOC interface number (placeholder `120000`); AddOn and libraries load
- Innkeeper gossip: `GOSSIP_SHOW` + NPC ID from `UnitGUID("npc")`; option injection
- `IsResting()` inside inns; sitting detection, if any
- Addon messages PARTY / RAID / GUILD, including inside an instance (and whether
  instance groups use `INSTANCE_CHAT`); size and rate limits
- Hidden values outside combat (innkeeper NPC ID, addon-message sender); addon messages
  to a custom channel allowed or blocked
- Player GUID and name format (two-part names?); sender name → GUID resolution
- Walk every inn to collect innkeeper NPC IDs (`Data/Inns`)

## Follow-ups

- Move [kickoff.md](kickoff.md) to `docs/archive/` once v1 ships.
- Delete GitHub's default labels (`bug`, `enhancement`, …), which overlap ours
  (maintainer call: deletion).
- Publish `Data/Inns` / `Data/Phrases` as a generated reference for export consumers
  before export v1 is finalized ([export-format.md](export-format.md)).
- CI pins only the top-level rocks; if an upstream release breaks CI, pin dependencies too.
- `decisions.md` is at 423 lines. At the start of October, move the September entries to
  `docs/archive/decisions-2026-09.md` and leave an index line. `architecture.md` is at
  197; split a section out before adding to it.
