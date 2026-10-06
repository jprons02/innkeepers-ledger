# Status

> **Summary:** where the project stands right now, what's next, and what's waiting on the
> maintainer. A snapshot, rewritten each session; history lives in git and
> [decisions.md](decisions.md).
> **Read when:** every session, first thing after `CLAUDE.md`.

**Updated:** 2026-10-06 (**phrase voices** merged (#100, #101): 8 voices, 156 templates,
an Oddities category, a voice per composer line; free text stays out. Released to `main`
the same day; the beta install holds it)

## Current state

- **Phase 1 of [kickoff.md](kickoff.md) is done:** every pure module and the sync glue,
  tested (pure modules at 100% coverage) and security-reviewed. Specs:
  [sync-ledger](specs/sync-ledger.md), [sync-glue](specs/sync-glue.md),
  [phrase](specs/phrase.md), [collection-cosmetics](specs/collection-cosmetics.md),
  [export](specs/export.md) (export string **v1**).
- **Phase 2 is under way (#12)** in the Forever beta, with the client facts in
  [platform-forever.md](platform-forever.md). Two-part names are handled (#75, #80), and
  solo `/ledger debug` ends `names two-part`. Zones with no continent group under their
  World map (#76).
- **First innkeeper (2026-10-05):** Coriella Calmbreeze (NPC `254089`), Calmbreeze Inn,
  Shen'dar Village, Zephras Isle, neutral. She is `Data/Inns`' only record so far (zone
  2521, seal 101, under Azeroth 947).
- **`Sign` is built and works in the client (#96, [specs/sign.md](specs/sign.md)):** a
  "Sign the guestbook" button at known innkeepers, a DRAFT composer, and a pure `SignFlow`
  module. In the beta, the button showed only at Coriella and a signature survived a
  restart. A second click named the Tuesday 16:00 UTC reset.
- **Phrase voices (#100, decision 2026-10-06):** the maintainer asked for free text up
  to ~200 characters, then chose to keep canned phrases with more personality instead.
  Templates and conjunctions now come in 8 voices (Hearthside, Bardic, Grumbler,
  Scholar, Rowdy, Mystic, Sailor, Noble), with 175 words including **Oddities**. The
  composer has a voice row per line, so one signature can mix two voices. Grammar, wire
  and export are unchanged. An independent review rewrote 24 lines that failed in some
  combination (the content rules gained "no payment or service frame"). The beta install
  was refreshed with it (the client was closed; it loads on the next start).
- **Wording:** players sign the inn's **guestbook**. The AddOn stays *Innkeeper's Ledger*
  (decision 2026-10-02).
- **Not built:** `UI/Book`; the list-style composer (#102, `ready`). Phrase and cosmetic
  sets, the composer's look and the signing messages are DRAFTs.
- **Releasing is wired up (#81, #86):** see
  [CONTRIBUTING.md → Releasing](../CONTRIBUTING.md#releasing). CurseForge `1721704` and
  Wago `n6VYeONd` are in the TOC.
- **CI:** eight required checks on `main` and `dev`, all runnable locally except
  `package`. **Releases:** `main` holds everything through 2026-10-06. No tags or
  published builds yet (maintainer gate).

## Next step

- **Agents:** write and build the `UI/Book` ticket (contracts in each spec's §8;
  [collection-cosmetics.md §8](specs/collection-cosmetics.md#8-contract-for-later-slices)).
  Then #102: browse phrases in lists instead of arrow cyclers (156 templates are a lot
  of clicking).
- **In the client (maintainer, as you play):** keep ILProbe enabled, talk to every
  innkeeper you pass and `/reload` now and then; each one becomes a `Data/Inns` record.
  After merges, agents refresh the installed copy
  ([testing.md](testing.md#testing-posture) → *Refreshing the AddOn*).

## Client access plan

- In the beta since 2026-09-30, until **2026-10-21**. Launch: **2026-11-04**. Phase 2
  runs during the beta, and the release is at launch. Beta client:
  `World of Warcraft\_classic_beta_`, with the probe and the `dev` AddOn installed.

## Open questions (maintainer to decide)

None of these block work. Drafts ship and get retuned
([decisions.md](decisions.md) → *Maintainer-gated content ships as a DRAFT*).
- **Phrase wording (#62):** the voices direction is chosen (2026-10-06); the lines in
  [phrase.md §9](specs/phrase.md#9-draft-phrase-set-draft) are still open to rewording as
  you play. Alcohol words? "the murlocs" and "the kobolds"?
- **Cosmetic catalog (#63):** the DRAFT in
  [collection-cosmetics.md §9](specs/collection-cosmetics.md#9-draft-catalog-draft): the
  set, names and thresholds. Does "every inn" mean your faction's inns? Should a zone
  seal stay when a patch adds an inn?
- **Export (#64):** include `me.region`? An import or backup restore
  ([export.md → Open questions](specs/export.md#open-questions-maintainer))?
- **Signing (#96):** the composer's look (the maintainer has a screenshot: a dark panel
  with arrow cyclers and a lot of empty space) and the chat lines, all in
  `SignFlow.TEXT`. Should signing announce earned cosmetics? Are recent phrases worth a
  follow-up? ([sign.md → Open questions](specs/sign.md#open-questions-maintainer)).

## Waiting on the maintainer

**In the client** (batched in #12; the unticked items in
[platform-forever.md → Verification checklist](platform-forever.md#verification-checklist-needs-a-forever-client-beta-until-2026-10-21-or-launch-2026-11-04)):
- More innkeepers.
- The rest of the signing checks: the composer closing with the gossip and with the
  vendor option, cycling and the second line, the new voice rows (a screenshot of the
  taller composer), and a sealed signature after 2026-10-06 16:00 UTC.
- A second character in a party: round-trips; `got hello PARTY`, not `drop unresolved`;
  `UnitFullName("partyN")`; and the same in a cross-realm or group-finder group.
- A guild round-trip, and one dungeon run.

**Accounts:** nothing waiting.

## Follow-ups

- **Before the first tag:** write the `CHANGELOG.md` `## vX.Y.Z` notes and answer #62 and
  #63 (IDs freeze at the first release). Interface `16001` → Forever on CurseForge and
  Wago is unverified until the first upload (the packager's `-g` overrides it).
- **Release gate: `Data/Inns` must be complete for what it ships.** Earned cosmetics are
  never taken away, and the `zone`, `continent` and `all` rules count only the inns the
  data knows. The beta's first signature, at the only known inn, earned 1101, 101, 1003
  *and* 2 at once (2026-10-05). Beta saves don't carry over to live, but a partial atlas
  in a release would hand out "every inn" for good. Before the first tag, either every
  Forever inn is in the data, or the rules gain a guard (e.g. a per-zone "complete" mark,
  a `collection-cosmetics.md` change).
- **CI runners:** `ubuntu-latest` moves to Ubuntu 26 from 2026-10-19; watch the first
  runs after that. A GitHub Actions incident on 2026-10-05 timed out jobs for hours
  ([CONTRIBUTING.md → Branches](../CONTRIBUTING.md#branches-and-pull-requests) says how
  to retry).
- **Revisit once in groups (#12):** server-clock jumps in `SyncSchedule`; other AddOns'
  hidden traffic counted as `hidden`; group-map rescan budget; a dropped
  `C_Timer.After`; export build time and AceSerializer's ~5 MB after an opted-in export.
- **Weekly reset fallback:** the beta (region 90) resets Tuesday 16:00 UTC, an hour off
  the US row. Fill in the live regions' rows after launch.
- **`UI/Book`:** its in-game help says what sync shares, in the README's words.
- **Code tidy (low):** `isInt` / name allow-lists copied across `Collection`,
  `Cosmetics`, `Export` and `SignFlow` (and `Core`'s `hidden` in `Sign`); `Phrase`'s
  load-time asserts.
- Publish `Data/*` as a generated reference for export consumers (needs the inn data).
- `GOLDEN_F` export string: regenerate it if a library or interpreter change breaks it
  while its decode still matches, and say so in the PR.
- `Ledger`'s load-time cap pass is quadratic on a tampered file; batch the evictions if
  needed.
- Harness: a ChatThrottleLib-callback option for `"defer"` mode. CI pins only top-level
  rocks; pin dependencies if an upstream release breaks CI.
- Delete GitHub's default labels (maintainer call: deletion).
- `decisions.md` is ~1 400 lines: move the September entries to
  `docs/archive/decisions-2026-09.md` with an index line.
- Move [kickoff.md](kickoff.md) to `docs/archive/` once v1 ships.
