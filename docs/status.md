# Status

> **Summary:** where the project stands right now, what's next, and what's waiting on the
> maintainer. A snapshot, rewritten each session; history lives in git and
> [decisions.md](decisions.md).
> **Read when:** every session, first thing after `CLAUDE.md`.

**Updated:** 2026-09-26

## Current state

- Docs (vision, decisions, architecture, platform, policy, prior art, export draft): ✅
- Context map + conventions (`CLAUDE.md`), branch flow (`dev` → `main`), branch
  protection on both branches: ✅
- Agent team (`.claude/agents/`): ✅ planner, implementer, reviewer
- CI: ✅ policy guard (runs on every push and PR, including `dev`); ⬜ luacheck + busted
  (lands with the first Lua; [kickoff.md](kickoff.md) step 3)
- Kickoff step 1 (orient): ✅ reported. Step 2 (scaffold): ✅ (#8). Steps 3+: ⬜
- AddOn scaffold: ✅ TOC (placeholder interface number), `Libs/embeds.xml`, every module
  as an empty stub on the shared `ns`, `Core` with AceDB + `/ledger` (prints the
  version), WoW API stub + loader helpers, `.busted`, `.luacheckrc`, `.pkgmeta`. The
  whole AddOn loads under the stub in `busted`. Module logic: ⬜ none yet
- Client verification ([platform-forever.md](platform-forever.md) checklist): ⬜ no
  Forever client yet
- Libraries: ✅ reviewed and vendored into `Libs/` with a checksum manifest and
  `scripts/check-libs.sh` ([libraries.md](libraries.md)); ⬜ check runs in CI (#9)
- Tickets: ✅ issue forms, labels, `v1 launch` milestone; queue below
- Local toolchain: ✅ Lua 5.1 + busted 2.3.0 + luacheck 1.2.0 (setup in
  [CONTRIBUTING.md](../CONTRIBUTING.md))

## Next step

Work the ticket queue in order (each ticket says what to read):

1. ~~#7 Vendor the reviewed libraries~~ ✅ done (#15)
2. ~~#8 Scaffold the AddOn~~ ✅ done
3. #9 luacheck + busted + manifest checks in CI (unblocked; next)
4. #10 Slice 1 parent → #11 write the spec and file the implementation tickets
   (can run in parallel with #7–#9; it's docs only)

In-client work is #12 (needs a Forever client and the maintainer).

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

- **Beta access:** not opted in as of 2026-09-26. The free opt-in costs nothing and
  invites go out in waves, so opting in soon improves the odds. Decides which plan
  branch applies (by ~2026-10-03); without access, plan for the no-beta branch.
- **AddOn list blurb (low priority):** the TOC `## Notes` line reuses the README's
  wording ("Talk to an innkeeper, sign the ledger, and fill a book of every inn you've
  rested at."). Keep it or give a replacement.

Settled 2026-09-26: sender identity per channel (see
[decisions.md](decisions.md) and [architecture.md → Security model](architecture.md)).

## Waiting on the maintainer in the client (batch)

Tracked in #12. These need someone at the keyboard in a Forever client. Everything else
proceeds without them. Full list: [platform-forever.md → Verification checklist](platform-forever.md#verification-checklist-needs-a-forever-client-beta-until-2026-10-21-or-launch-2026-11-04).

- TOC interface number (the TOC holds a marked placeholder, `120000`); AddOn loads,
  including `Libs/embeds.xml` (a bare `<Ui>` with no namespace)
- Innkeeper gossip: `GOSSIP_SHOW` + NPC ID from `UnitGUID("npc")`; option injection works
- `IsResting()` inside inns; sitting detection, if any
- Addon messages PARTY / RAID / GUILD between two characters, including inside an
  instance; message size and rate limits; embedded libraries load
- Player GUID and name format on the mega-realm; sender name → GUID resolution (group
  via `UnitGUID`, guild roster exposes GUIDs)
- Walk every inn to collect innkeeper NPC IDs (`Data/Inns`)

## Follow-ups

- Move [kickoff.md](kickoff.md) to `docs/archive/` once v1 ships.
- [decisions.md](decisions.md) is past ~200 lines. When it next grows, move the
  2026-09-25 seed entries to `docs/archive/decisions-2026-09.md` and link them.
- Delete GitHub's default labels (`bug`, `enhancement`, …), which overlap ours
  (maintainer call: deletion).
- Publish `Data/Inns` / `Data/Phrases` as a generated reference for export consumers
  ([export-format.md](export-format.md)), before export v1 is finalized.
