# Status

> **Summary:** where the project stands right now, what's next, and what's waiting on the
> maintainer. A snapshot, rewritten each session; history lives in git and
> [decisions.md](decisions.md).
> **Read when:** every session, first thing after `CLAUDE.md`.

**Updated:** 2026-09-27 (#63 Collection + Cosmetics)

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
- **Slice 1 done (#10),** spec [specs/sync-ledger.md](specs/sync-ledger.md): `Ledger`
  (#30) and `SyncProtocol` (#31), both at 100% coverage; `SyncProtocol` passed a
  security-level review. Re-signing an inn: once per week, at the game's weekly reset.
- **Slice 2 (#41) done,** spec [specs/sync-glue.md](specs/sync-glue.md):
  `Core` opens the ledger at login as `ns.ledger` (#44); `SyncSchedule`, the pure send
  schedule (#45); `Sync` receives and resolves senders (#46), and sends, with the combat
  hold and the `combat state` guard rule (#47, PR #57). Group senders resolve through a
  name → GUID map from our own unit scan, so no peer string reaches a client function
  (#54). **Two players' AddOns now trade signatures**; the 40-player raid simulation
  stays under every rate limit. Each piece passed a security-level review. Choices the
  specs left open are in decisions.md (*Sync receive: fail-closed choices*, *Sync send:
  timer, clock and hold choices*, *Group map details*).
  `Sign` must call `ns.Sync:WindowChanged()` after `addOwn` returns `"added"`, check
  `ns.Cosmetics.canSeal` before attaching a seal, and record unlocks with `markEarned`
  (spec [collection-cosmetics.md §8](specs/collection-cosmetics.md#8-contract-for-later-slices)).
- **Slice 3 (#61), in progress:** `Phrase` + a DRAFT `Data/Phrases` set (#62), spec
  [specs/phrase.md](specs/phrase.md): 24 templates, 4 conjunctions, 120 words; synced
  entries with real phrase IDs are now stored. `Phrase.lua` at 100% coverage; passed a
  security-level review. `Collection` + `Cosmetics` + a DRAFT `Data/Cosmetics` catalog
  (#63), spec [specs/collection-cosmetics.md](specs/collection-cosmetics.md): the
  `Data/Inns` shape (inns by NPC ID with aliases and factions, zones and continents by
  map ID, a seal per zone; still empty until #12), per-faction progress over your own
  signatures, unlocks derived from entries with the `earned` map as a floor, and
  `Cosmetics.SEALS`, which `Sync` now validates peers' seals against. Both modules at
  100% coverage. Next: `Export` (#64).
- **Other module logic** (`Sign`, UI): ⬜ none yet.
- **Releases:** `main` = `dev` as of #24 (2026-09-26). Since then `dev` has docs and CI
  changes (#25–#39) and module logic (`Ledger` #38, `SyncProtocol` #40, `Core` #50,
  `SyncSchedule` #52, `Sync` receive #55, `Sync` send #57, group map #59, `Phrase` #62,
  `Collection` + `Cosmetics` #63). No tags yet
  (maintainer gate).
- **Direction (2026-09-27):** the inn ledger stays, leaning into a passport feel (stamp
  per inn, seal per zone). A public profile website is a post-v1, separate project the
  AddOn never names ([vision.md](vision.md) → Where it can grow).
- **Client verification** ([platform-forever.md](platform-forever.md)): ⬜ no Forever
  client yet.

## Next step

Slice 3 (#61), [kickoff.md](kickoff.md) Phase 1 step 5: #64 `Export` (its blocker #63 is
done): serialize `Collection.progress` and `Cosmetics.unlocked` as
[export-format.md → Data](export-format.md#data-draft) now describes. In-client work is
#12, which also fills `Data/Inns` in the shape of
[specs/collection-cosmetics.md §8](specs/collection-cosmetics.md#8-contract-for-later-slices).

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
- **Phrase wording (#62):** the DRAFT set in
  [specs/phrase.md §9](specs/phrase.md#9-draft-phrase-set-draft) is on `dev`: warm
  inn-and-road lines with a little Dark Souls whimsy. Ship as is, or redirect? IDs change
  freely until the first release. Also: keep the alcohol words ("a mug of ale", "spiced
  cider")? Keep Warcraft creature words ("the murlocs") or stay generic fantasy?
- **Cosmetic catalog (#63):** the DRAFT in
  [specs/collection-cosmetics.md §9](specs/collection-cosmetics.md#9-draft-catalog-draft)
  is on `dev`: Sepia ink (first signature), Wayfarer's seal (5 inns), Traveler's
  quill (10), Owl-feather quill (20), Forest-green ink (3 zones), Midnight-blue ink (10
  zones), Cartographer's quill (a continent), Innkeeper's seal (every inn), plus a seal
  per zone. Ship as is, or redirect the set, names or ladder? Thresholds get retuned
  once #12 counts the inns; IDs change freely until the first release. Doesn't block
  anything.
- **Per-faction totals (#63):** agree that "every inn" means every inn your faction can
  use (neutral plus your faction's)?
- **Never taken away (#63):** agree that a seal stays when Forever adds an inn to a zone
  you'd completed? The alternative is losing it until you sign the new inn.
- **Later, not v1 (#63):** worth a follow-up for continent seals, a "home inn" reward for
  re-signing one inn over many weeks, or a separate badge kind?

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
- Publish `Data/Inns` (`Inns`, `Zones`, `Continents`), `Data/Phrases` and
  `Data/Cosmetics` as a generated reference for export consumers before export v1 is
  finalized ([export-format.md](export-format.md)).
- CI pins only the top-level rocks; if an upstream release breaks CI, pin dependencies too.
- `Ledger`'s cap pass at load time is quadratic: a tampered SavedVariables file far over
  the caps (40 000 entries) loads in about 4 s. Peers can't reach this; batch the
  evictions if it ever matters (decisions.md → 2026-09-27 — Ledger orders by bytes).
- Another AddOn's hidden addon traffic is counted and logged as a `hidden` drop, since
  the hidden check comes before the prefix (decisions.md → *Sync receive: fail-closed
  choices*); revisit if #12 shows hidden senders.
- Harness: `"defer"` mode puts a message on the bus at hand-off; ChatThrottleLib puts a
  queued one on the wire at its callback. #47's review checked that model separately (it
  held); a harness option for it would make the deferred raid run more realistic.
- Group map rescan (#54 review, low): a server clock swinging back and forth allows a
  rescan per miss (41 units each), as `requestRoster` does; and if our own name can't be
  read, our echoes spend the 10 s rescan budget, delaying a late-loading newcomer. Both
  fail closed; revisit if #12 shows either.
- A timer `C_Timer.After` silently drops is replaced only on the next request (any
  incoming message or event). The real client doesn't drop timers; revisit if #12 does.
- `decisions.md` is at about 730 lines. At the start of October, move the September
  entries to `docs/archive/decisions-2026-09.md` and leave an index line.
