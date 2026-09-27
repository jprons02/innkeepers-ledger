# Status

> **Summary:** where the project stands right now, what's next, and what's waiting on the
> maintainer. A snapshot, rewritten each session; history lives in git and
> [decisions.md](decisions.md).
> **Read when:** every session, first thing after `CLAUDE.md`.

**Updated:** 2026-09-27

## Current state

- **Foundation done:**
  - docs, the context map and branch flow, with protection on `main` and `dev`
  - the agent team (planner, implementer, reviewer)
  - ticket forms, labels and the `v1 launch` milestone
  - kickoff steps 1–3 ([kickoff.md](kickoff.md))
- **AddOn scaffold (#8):**
  - TOC (placeholder interface number), `Libs/embeds.xml`
  - every module as an empty stub on the shared `ns`
  - `Core` with AceDB + `/ledger`
  - WoW API stub and loader helpers; the whole AddOn loads under `busted`

  Module logic: ⬜ none yet.
- **Libraries:** reviewed and vendored in `Libs/`. The manifest is pinned to the review
  doc's hash list ([libraries.md](libraries.md)).
- **CI:** five required checks on `main` and `dev`:
  - `no-urls-in-game-code`
  - `luacheck`
  - `busted` (Lua 5.1)
  - `libs-manifest`
  - `forbidden-apis`

  Every release PR also gets a security review
  ([security-checklist.md](security-checklist.md)).
- **Releases:** `main` = `dev` in content as of #24 (2026-09-26), the first release with
  a *Security review* section. No tags yet (maintainer gate).
- **Client verification** ([platform-forever.md](platform-forever.md) checklist): ⬜ no
  Forever client yet.
- **Local toolchain:** Lua 5.1 + busted 2.3.0 + luacheck 1.2.0 in a hererocks folder
  ([CONTRIBUTING.md](../CONTRIBUTING.md)). That folder isn't on the agent shell's
  `PATH`, so CI is the authority for busted/luacheck. `scripts/check-*.sh` run locally
  with `sh`.

## Next step

**#10 Slice 1 parent → #11: write the spec and file the implementation tickets.** Done
so far: #7, #8, #9, #22. In-client work is #12 (needs a Forever client and the
maintainer).

## Client access plan

- **Beta window:** 2026-09-17 → **2026-10-21**. Launch: **2026-11-04**.
- **Default route: the free beta opt-in** on the official Forever site. Invites go out in
  waves and aren't guaranteed.
- **Paid route (maintainer's call only):** the higher-tier pre-purchase editions include
  beta access. Buying one is never done on the project's behalf; it happens only if the
  maintainer names that purchase.
- **Retail as a stand-in:** Forever reportedly uses the retail-style API, so generic
  mechanics (gossip events, `UnitGUID("npc")` parsing, `IsResting()`, addon-message round-trips,
  instance messaging) can be prototyped on retail. Results are only indicative until
  confirmed on Forever. The innkeeper list and TOC interface number can't be substituted.

**Branches of the plan:**
- **Beta access by ~2026-10-03:** run Phase 2 during the beta and aim to release at launch.
- **No beta access:** finish Phase 1 plus retail prototyping before launch, run Phase 2 on
  launch day, and release **~1–2 weeks after launch**.

## Open questions (maintainer to decide)

- **Beta access:** not opted in as of 2026-09-27. The free opt-in costs nothing and
  invites go out in waves, so opting in soon improves the odds. Decides which plan
  branch applies (by ~2026-10-03); without access, plan for the no-beta branch.
- **AddOn list blurb (low priority):** the TOC `## Notes` line reuses the README's
  wording ("Talk to an innkeeper, sign the ledger, and fill a book of every inn you've
  rested at."). Keep it or give a replacement.

- **Trusting uploads to the profile site (post-v1, in discussion):** exports can be
  edited, so the site can't treat stamps as proof. How much checking the site does, and
  whether the export should carry anything extra for it, is still being worked out.

Settled: sender identity per channel (2026-09-26); `Sync` may read combat *state*,
explained to players in the README; keep the inn ledger after a pivot review; the
profile website is post-v1 and never named by the AddOn or its download pages (all
2026-09-27). See [decisions.md](decisions.md).

## Waiting on the maintainer in the client (batch)

Tracked in #12. These need someone at the keyboard in a Forever client. Everything else
proceeds without them. Full list: [platform-forever.md → Verification checklist](platform-forever.md#verification-checklist-needs-a-forever-client-beta-until-2026-10-21-or-launch-2026-11-04).

- TOC interface number (the TOC holds a marked placeholder, `120000`); AddOn loads
- Innkeeper gossip: `GOSSIP_SHOW` + NPC ID from `UnitGUID("npc")`; option injection works
- `IsResting()` inside inns; sitting detection, if any
- Addon messages PARTY / RAID / GUILD between two characters, including inside an
  instance; message size and rate limits; embedded libraries load
- Player GUID and name format on the mega-realm; sender name → GUID resolution (group
  via `UnitGUID`, guild roster exposes GUIDs)
- Walk every inn to collect innkeeper NPC IDs (`Data/Inns`)
- Hidden ("secret") values outside combat: innkeeper NPC ID and addon-message sender
  arrive readable; addon messages to a custom channel allowed or blocked

## Follow-ups

- Move [kickoff.md](kickoff.md) to `docs/archive/` once v1 ships.
- Delete GitHub's default labels (`bug`, `enhancement`, …), which overlap ours
  (maintainer call: deletion).
- Publish `Data/Inns` / `Data/Phrases` as a generated reference for export consumers
  ([export-format.md](export-format.md)), before export v1 is finalized.
- CI pins only the top-level rocks (busted, luacheck); their dependencies float. If an
  upstream release breaks CI, pin those as well.
- `decisions.md` is past the ~200-line split point (304). At the start of October, move
  the September entries to `docs/archive/decisions-2026-09.md` and leave an index line.
  `architecture.md` is at 199; split a section out before adding to it.
