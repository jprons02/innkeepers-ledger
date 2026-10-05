# Status

> **Summary:** where the project stands right now, what's next, and what's waiting on the
> maintainer. A snapshot, rewritten each session; history lives in git and
> [decisions.md](decisions.md).
> **Read when:** every session, first thing after `CLAUDE.md`.

**Updated:** 2026-10-05 (**first signature in the client**: `Sign` (#96) works at
Calmbreeze Inn; first innkeeper in `Data/Inns`; release to `main` on 2026-10-01)

## Current state

- **Phase 1 of [kickoff.md](kickoff.md) is done:** every pure module and the sync glue
  exist, tested (pure modules at 100% coverage) and security-reviewed. Specs:
  [sync-ledger](specs/sync-ledger.md), [sync-glue](specs/sync-glue.md),
  [phrase](specs/phrase.md), [collection-cosmetics](specs/collection-cosmetics.md),
  [export](specs/export.md) (export string **v1**).
- **Phase 2 has started (#12)** in the Forever beta. The probe's first run (2026-09-30)
  answered most client questions ([platform-forever.md](platform-forever.md)): modern
  API, TOC `16001`, NPC IDs from `UnitGUID("npc")`, a gossip-frame button works,
  custom-channel addon messages allowed, 255-byte message cap.
  - **Two-part names** (`"First Surname"`) are handled (#75), and `/ledger debug`'s report
    ends with `names two-part` / `realm` / `undecided`; Core and Sync read our own name
    through one helper (#80). Solo it reports `names two-part` (2026-10-05); still to
    confirm with a second character (#12).
  - **Zones with no continent** group under their World map (#76).
- **First innkeeper met (2026-10-05):** Coriella Calmbreeze (NPC `254089`), Calmbreeze
  Inn, Shen'dar Village, Zephras Isle; neutral; `IsResting()` true; the gossip button
  works there ([platform-forever.md](platform-forever.md)). She is `Data/Inns`' first
  record (zone 2521, seal 101, under Azeroth 947). Her *Make this inn your home.* option
  (icon 132052) is how the probe's log tells innkeepers apart.
- **`Sign` is built (#96, [specs/sign.md](specs/sign.md)):** a "Sign the guestbook" button
  under the gossip frame at every known innkeeper; a click either says why it can't sign
  (one chat line) or opens a plain DRAFT composer; signing stores an own entry, records
  earned cosmetics and tells `Sync`. The decisions live in a new pure module, `SignFlow`
  (90% floor); `Core` records unlocks at login. **Works in the client (2026-10-05):** the
  button shows only at Coriella, the composer renders, a signature was stored and
  survived a restart, and a second click names the reset (Tuesday 16:00 UTC). The
  probe no longer adds its own button (it stacked on ours).
- **Not built:** `UI/Book` (its ticket is next). Phrase and cosmetic sets, the composer's
  look and the signing messages are DRAFTs.
- **Releasing is wired up (#81, #86):** `release.yml` dry-runs the BigWigs packager on
  every PR (`package`, a required check) and publishes a `v*` tag only after the
  maintainer approves the `release` environment
  ([CONTRIBUTING.md → Releasing](../CONTRIBUTING.md#releasing)). The first manual dry
  run on `main` passed (2026-10-02, 36 files); #81 is closed. CurseForge `1721704`
  and Wago `n6VYeONd` exist, with pages written and both IDs in the TOC (#87, #88).
- **CI:** eight required checks on `main` and `dev`, all runnable locally but `package`.
- **Releases:** `main` holds everything through 2026-10-01 (the release PR of that
  date). No tags or published builds (maintainer gate).

## Next step

- **Agents:** write and build the `UI/Book` ticket.
- **In the client (maintainer, as you play):** keep ILProbe enabled, talk to every
  innkeeper you pass and `/reload` now and then; each one becomes a `Data/Inns` record.
  The installed AddOn is a copy of `dev` (agents refresh it after merges).

## Client access plan

- In the beta since 2026-09-30, until **2026-10-21**. Launch: **2026-11-04**. Phase 2
  during the beta, release at launch. Beta client: `World of Warcraft\_classic_beta_`,
  probe installed and enabled.

## Open questions (maintainer to decide)

None block work; drafts ship and get retuned ([decisions.md](decisions.md) →
*Maintainer-gated content ships as a DRAFT*).
- **Phrase wording (#62):** the DRAFT in [phrase.md §9](specs/phrase.md#9-draft-phrase-set-draft):
  ship or redirect? Alcohol words? "the murlocs"?
- **Cosmetic catalog (#63):** the DRAFT in
  [collection-cosmetics.md §9](specs/collection-cosmetics.md#9-draft-catalog-draft):
  set, names, thresholds; "every inn" = your faction's? Keep a zone seal when a patch
  adds an inn? World-map groups count toward the `continent` quill (#76).
- **Export (#64):** `me.region`? An import or backup restore
  ([export.md → Open questions](specs/export.md#open-questions-maintainer))?
- **Signing (#96):** the composer's look (a plain dark panel with arrow cyclers right of
  the gossip frame) and the chat lines, all in `SignFlow.TEXT`; announce earned
  cosmetics on signing, or leave it to the book? Recent phrases worth a follow-up?
  ([sign.md → Open questions](specs/sign.md#open-questions-maintainer)).

## Waiting on the maintainer

**In the client** (batched in #12; the unticked items in
[platform-forever.md → Verification checklist](platform-forever.md#verification-checklist-needs-a-forever-client-beta-until-2026-10-21-or-launch-2026-11-04)):
more innkeepers (each one a `Data/Inns` record); the rest of the signing checks
([sign.md §8](specs/sign.md#8-in-client-checks-for-12): the composer closing with the
gossip or the vendor option, cycling and the second line, a sealed signature after
Tuesday 2026-10-06 16:00 UTC); a second character in a party (round-trips,
`got hello PARTY` not `drop unresolved`, `UnitFullName("partyN")`, also in a cross-realm or group-finder group); a guild round-trip;
one dungeon run; copying out an export string (once the Share window exists).

**Accounts:** nothing waiting. Both upload tokens are in the `release` environment's
  secrets, and every publishing account has a second factor (2026-10-01;
  [security-checklist.md → Before the packager lands](security-checklist.md#before-the-packager-lands-first-tag)).

## Follow-ups

- **Before the first tag:** `CHANGELOG.md` gets its `## vX.Y.Z` notes (the release check
  requires them); answer #62 and #63 (IDs freeze at the first public release). Whether
  CurseForge and Wago map interface `16001` to Forever is unverified until the first
  upload; the packager's `-g` overrides it.
- **Release gate: `Data/Inns` must be complete for what it ships.** Earned cosmetics are
  never taken away, and the `zone`, `continent` and `all` rules count only the inns the
  data knows. In the beta the first signature at Calmbreeze (the only inn) earned 1101,
  101, 1003 *and* 2 at once (2026-10-05). Beta SavedVariables don't carry to live, but a
  release with a partial atlas would hand out "every inn" for good. Before the first
  tag: either every Forever inn is in the data, or the rules gain a guard (e.g. a
  per-zone "complete" mark, so a zone seal and the continent/all rules wait for it), a
  `collection-cosmetics.md` change.
- **Revisit once in groups (#12):** server-clock jumps in `SyncSchedule`; other AddOns'
  hidden traffic counted as `hidden`; group-map rescan budget; a dropped
  `C_Timer.After`; export build time and AceSerializer's ~5 MB after an opted-in export.
- **Weekly reset fallback:** the beta (region 90) resets Tuesday 16:00 UTC, an hour off
  the US row; fill the live regions' rows after launch.
- **`UI/Book`:** its in-game help says what sync shares, in the README's words.
- **Code tidy (low):** `isInt` / name allow-lists copied across `Collection`,
  `Cosmetics`, `Export`, `SignFlow` (and `Core`'s `hidden` in `Sign`); `Phrase` load-time
  asserts (#62 review nits).
- Publish `Data/*` as a generated reference for export consumers (needs the inn data).
- `GOLDEN_F` export string: regenerate if a library or interpreter change breaks it while
  its decode still matches, and say so in the PR.
- `Ledger`'s load-time cap pass is quadratic on a tampered file; batch evictions if needed.
- Harness: a ChatThrottleLib-callback option for `"defer"` mode.
- CI pins only top-level rocks; pin dependencies if an upstream release breaks CI.
- Delete GitHub's default labels (maintainer call: deletion).
- `decisions.md` is ~1 350 lines: move September entries to
  `docs/archive/decisions-2026-09.md` with an index line (early October).
- Move [kickoff.md](kickoff.md) to `docs/archive/` once v1 ships.
