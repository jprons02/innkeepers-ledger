# Status

> **Summary:** where the project stands right now, what's next, and what's waiting on the
> maintainer. A snapshot, rewritten each session; history lives in git and
> [decisions.md](decisions.md).
> **Read when:** every session, first thing after `CLAUDE.md`.

**Updated:** 2026-10-01 (#80 name form in `/ledger debug`; #81 packager, CurseForge and
Wago projects; release to `main`)

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
    through one helper (#80). Still to confirm with a second character (#12).
  - **Zones with no continent** group under their World map (#76).
- **Not built:** `Sign` and `UI/Book`. **No innkeeper has been seen yet**; file their
  tickets once one has (contracts in each spec's §8). `Data/Inns` is empty (it fills from
  the probe's logs). Phrase and cosmetic sets are DRAFTs.
- **Releasing is wired up (#81, #86):** `release.yml` dry-runs the BigWigs packager on
  every PR (`package`, a required check) and publishes a `v*` tag only after the
  maintainer approves the `release` environment
  ([CONTRIBUTING.md → Releasing](../CONTRIBUTING.md#releasing)). CurseForge `1721704`
  and Wago `n6VYeONd` exist, with pages written and both IDs in the TOC (#87, #88).
- **CI:** eight required checks on `main` and `dev`, all runnable locally but `package`.
- **Releases:** `main` holds everything through 2026-10-01 (the release PR of that
  date). No tags or published builds (maintainer gate).

## Next step

- **#81, the last bit (agent):** run *Actions → release → Run workflow* on `main` (the
  manual dry run) and attach it to #81; close #81 once the Wago token is in.
- **In the client (maintainer, as you play):** keep ILProbe enabled, talk to every
  innkeeper you pass and `/reload` now and then. Then the `Sign` and `UI/Book` tickets.

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
- **In-game blurb:** the TOC's `## Notes:` still reads "Sign the ledger at every inn you
  rest in…"; the download pages say "Sign a guestbook at every inn…". Match them?

## Waiting on the maintainer

**In the client** (batched in #12; the unticked items in
[platform-forever.md → Verification checklist](platform-forever.md#verification-checklist-needs-a-forever-client-beta-until-2026-10-21-or-launch-2026-11-04)):
any innkeeper (gossip, NPC ID, `IsResting()`, the button's look); solo after login,
`/ledger debug` ends `names two-part` (#80); a second character in a party (round-trips,
`got hello PARTY` not `drop unresolved`, `UnitFullName("partyN")`); a guild round-trip;
one dungeon run; copying out an export string (once the Share window exists).

**Accounts:**
- `WAGO_API_TOKEN` into the `release` environment's **secrets** (key from Wago's
  account API-keys page). `CF_API_TOKEN` is in.
- Confirm 2-Step Verification on the Google account CurseForge signs in with
  ([security-checklist.md → Before the packager lands](security-checklist.md#before-the-packager-lands-first-tag)).

## Follow-ups

- **Before the first tag:** `CHANGELOG.md` gets its `## vX.Y.Z` notes (the release check
  requires them); answer #62 and #63 (IDs freeze at the first public release). Whether
  CurseForge and Wago map interface `16001` to Forever is unverified until the first
  upload; the packager's `-g` overrides it.
- **Revisit once in groups (#12):** server-clock jumps in `SyncSchedule`; other AddOns'
  hidden traffic counted as `hidden`; group-map rescan budget; a dropped
  `C_Timer.After`; export build time and AceSerializer's ~5 MB after an opted-in export.
- **Weekly reset fallback:** the beta (region 90) resets Tuesday 16:00 UTC, an hour off
  the US row; fill the live regions' rows after launch.
- **`UI/Book`:** its in-game help says what sync shares, in the README's words.
- **Code tidy (low):** `isInt` / name allow-lists copied across `Collection`,
  `Cosmetics`, `Export`; `Phrase` load-time asserts (#62 review nits).
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
