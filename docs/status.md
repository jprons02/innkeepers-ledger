# Status

> **Summary:** where the project stands right now, what's next, and what's waiting on the
> maintainer. A snapshot, rewritten each session; history lives in git and
> [decisions.md](decisions.md).
> **Read when:** every session, first thing after `CLAUDE.md`.

**Updated:** 2026-09-28 (context save after slice 3; Phase 1 released to `main`)

## Current state

- **Phase 1 of [kickoff.md](kickoff.md) is done:** every pure module and the sync glue
  exist, are tested (pure modules at 100% coverage) and passed security-level reviews.
  - Slice 1 (#10): `Ledger`, `SyncProtocol`; spec [specs/sync-ledger.md](specs/sync-ledger.md).
  - Slice 2 (#41): `Core` opens the ledger, `SyncSchedule`, `Sync` send/receive, combat
    hold, group senders resolved through our own unit scan; spec
    [specs/sync-glue.md](specs/sync-glue.md). Two players' AddOns trade signatures; the
    40-player raid simulation stays under every rate limit.
  - Slice 3 (#61): `Phrase` + a DRAFT `Data/Phrases` ([specs/phrase.md](specs/phrase.md));
    `Collection` + `Cosmetics` + a DRAFT `Data/Cosmetics`, and the `Data/Inns` shape
    ([specs/collection-cosmetics.md](specs/collection-cosmetics.md)); `Export` +
    `Core:ExportString`, export string **v1** ([specs/export.md](specs/export.md),
    [export-format.md](export-format.md)).
- **Not built:** `Sign` and `UI/Book`. Both are glue that needs the client. Their
  contracts are in each spec's §8 (e.g. `Sign` calls `ns.Sync:WindowChanged()` after
  `addOwn` returns `"added"`, checks `ns.Cosmetics.canSeal`, records unlocks with
  `markEarned`).
- **Data:** `Data/Inns` is empty until #12. Phrase and cosmetic sets are DRAFTs whose IDs
  change freely until the first public release.
- **CI:** seven required checks on `main` and `dev`; every one also runs locally
  ([CONTRIBUTING.md](../CONTRIBUTING.md#development-setup)). Release PRs get a security
  review ([security-checklist.md](security-checklist.md)).
- **Releases:** `main` = `dev` as of the Phase 1 release PR (2026-09-28). No tags or
  published builds (maintainer gate).
- **Client verification** ([platform-forever.md](platform-forever.md)): ⬜ no Forever
  client yet.

## Next step

Everything left needs someone at a keyboard in a game client:
- **Phase 2, Forever client (#12):** the verification checklist, then `Data/Inns` per
  [collection-cosmetics.md §8](specs/collection-cosmetics.md#8-contract-for-later-slices),
  then `Sign` and `UI/Book` (Share window per
  [export.md §8](specs/export.md#8-contract-for-later-slices)). File their tickets once
  #12 answers the gossip and frame questions.
- **Phase 1.5 (optional), retail:** gossip/NPC-ID detection, `IsResting()`, addon-message
  round-trips, recorded as "retail-observed" in [platform-forever.md](platform-forever.md).

## Client access plan

- **Beta window:** 2026-09-17 → **2026-10-21**. Launch: **2026-11-04**.
- **Default route:** the free beta opt-in (invites in waves). The paid pre-purchase route
  is the maintainer's call only, never bought for the project.
- **Beta access by ~2026-10-03:** Phase 2 during the beta, release at launch. **No beta
  access:** retail prototyping now, Phase 2 on launch day, release ~1–2 weeks after.

## Open questions (maintainer to decide)

None block work; drafts ship and get retuned ([decisions.md](decisions.md) →
*Maintainer-gated content ships as a DRAFT*).
- **Beta access (#1, #2), time-sensitive:** not opted in as of 2026-09-28. Free; decides
  the plan branch by ~2026-10-03.
- **Phrase wording (#62):** the DRAFT in
  [phrase.md §9](specs/phrase.md#9-draft-phrase-set-draft): ship or redirect? Keep the
  alcohol words ("a mug of ale", "spiced cider")? Keep "the murlocs" or stay generic?
- **Cosmetic catalog (#63):** the DRAFT in
  [collection-cosmetics.md §9](specs/collection-cosmetics.md#9-draft-catalog-draft):
  set, names, thresholds (retuned after #12 counts inns). Also: "every inn" = every inn
  your faction can use? Keep a zone seal when a patch adds an inn to that zone? Later:
  continent seals, a "home inn" reward, a badge kind?
- **Export (#64):** add `me.region` (Forever names are unique only per region)? Ever
  want an import or backup restore ([export.md → Open questions](specs/export.md#open-questions-maintainer))?

## Waiting on the maintainer in the client

Batched in #12; the list is
[platform-forever.md → Verification checklist](platform-forever.md#verification-checklist-needs-a-forever-client-beta-until-2026-10-21-or-launch-2026-11-04).

## Follow-ups

- **Revisit if #12 shows it:** forward server-clock jumps in `SyncSchedule`; hidden
  addon traffic from other AddOns counted as `hidden` drops; group-map rescan budget
  (#54 review); a dropped `C_Timer.After`; export build time, edit-box capacity and the
  ~5 MB AceSerializer keeps after an opted-in export.
- **Code tidy (low):** `isInt` / name allow-lists are copied across `Collection`,
  `Cosmetics` and `Export` (share one if they start to drift); `Phrase` could assert
  `Ledger.LIMITS` numbers at load and require a space before `{w}` in templates (#62
  review nits).
- Publish `Data/Inns`, `Data/Phrases` and `Data/Cosmetics` as a generated reference for
  export consumers; needs #12's inn data.
- Export golden string (`GOLDEN_F`): regenerate if a library or interpreter change breaks
  it while its decode still matches, and say so in the PR.
- `Ledger`'s load-time cap pass is quadratic on a tampered file (40 000 entries ≈ 4 s);
  batch evictions if it ever matters.
- Harness: a ChatThrottleLib-callback option for `"defer"` mode would make the raid run
  more realistic.
- CI pins only top-level rocks; pin dependencies if an upstream release breaks CI.
- Delete GitHub's default labels (maintainer call: deletion).
- `decisions.md` is ~1 000 lines: early October, move September entries to
  `docs/archive/decisions-2026-09.md` with an index line.
- Move [kickoff.md](kickoff.md) to `docs/archive/` once v1 ships.
