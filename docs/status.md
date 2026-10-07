# Status

> **Summary:** where the project stands right now, what's next, and what's waiting on the
> maintainer. A snapshot, rewritten each session; history lives in git and
> [decisions.md](decisions.md).
> **Read when:** every session, first thing after `CLAUDE.md`.

**Updated:** 2026-10-07 (**released to `main` (#114):** the book, no inks, the list
composer (#102) and completeness marks (#110); release security review passed)

## Current state

- **Phase 1 of [kickoff.md](kickoff.md) is done:** every pure module and the sync glue,
  tested and security-reviewed (specs: [sync-ledger](specs/sync-ledger.md),
  [sync-glue](specs/sync-glue.md), [phrase](specs/phrase.md),
  [collection-cosmetics](specs/collection-cosmetics.md), [export](specs/export.md)).
- **Phase 2 (#12) is under way in the Forever beta**, client facts in
  [platform-forever.md](platform-forever.md). `Data/Inns` holds one record: Coriella
  Calmbreeze (NPC `254089`), Calmbreeze Inn, Zephras Isle (zone 2521, seal 101, Azeroth 947).
- **`Sign` works in the client (#96, [sign.md](specs/sign.md))**, with phrase **voices**
  (#100: 8 voices, 156 templates, 175 words; canned phrases, no free text).
- **`UI/Book` is built (#106, [book.md](specs/book.md)), not yet seen in the client.**
  The maintainer chose it from mockups: a parchment spread with four tabs (Inns,
  Collection, Cosmetics, Share), inn pages with your signatures then travelers', a stamp
  grid, quills as a flourish under your own signatures, and the Share page with a "since
  you last shared" line. `/ledger` toggles it (`share`, `version`, `debug` are
  subcommands), and a "Read the guestbook" button sits beside "Sign the guestbook". A pure
  `BookView` (98% coverage) builds every page; a security-level review passed (hostile
  names, tampered records, ledgers at every cap). Wording, look and textures are DRAFT.
- **No inks (#105, decision 2026-10-06):** every signature is in one realistic ink;
  1100..1199 is reserved. Quills and seals remain.
- **The composer shows lists (#102, #111):** line tabs, a voice strip, a conjunction
  strip on line 2, and template, category and word lists with page buttons and the mouse
  wheel; the seal keeps its `<` `>`. Built, not yet seen in the client; the look is DRAFT.
- **Place rules wait for completeness marks (#110, decision 2026-10-07):** a zone seal,
  `zones n`, `continent` and `all` count only zones, continents and an atlas that
  `Data/Inns` marks `complete` ([collection-cosmetics.md §3.11](specs/collection-cosmetics.md#311-completeness-marks-amended-2026-10-07-110)).
  The shipped data marks nothing, so a signature now earns only `inns n` items; the book
  shows "1 of 1+". This answers the release gate on a partial atlas.
- **Releasing is wired up** ([CONTRIBUTING.md → Releasing](../CONTRIBUTING.md#releasing)).
  `main` and `dev` hold the same content (release #114, 2026-10-07). No tags yet
  (maintainer gate). **CI:** eight required checks, all green on `dev`.

## Next step

- **Agents:** no `ready` ticket is queued; #12's in-client results drive what's next
  (retune the DRAFT look from screenshots, mark zones complete from the walk). Small
  follow-ups below can fill gaps.
- **In the client (maintainer):** restart the client (a new file, `BookView.lua`, needs a
  full restart, not `/reload`), then run the book's and the composer's checks on the
  [platform-forever.md checklist](platform-forever.md#verification-checklist-needs-a-forever-client-beta-until-2026-10-21-or-launch-2026-11-04).
  Two matter most: do the parchment textures load, and do `‹ › ·` render. A screenshot of
  each tab and of each composer line helps retune the DRAFT look. Keep talking to every
  innkeeper you pass, and **note per zone whether you've seen every inn in it**: that is
  what lets a zone be marked `complete` (#110).

## Client access

In the beta until **2026-10-21**; launch **2026-11-04**. Beta client
`World of Warcraft\_classic_beta_`, with the probe and the `dev` AddOn installed.

## Open questions (maintainer to decide)

None block work; DRAFTs ship until answered.
- **Which places to mark complete:** your call from the walk (#12), zone by zone. Until
  a zone is marked, its seal can't be earned; zones you never finish just keep their
  seals locked. The book's `"+"` ("1 of 1+") is DRAFT wording.
- **The book ([book.md → Open questions](specs/book.md#open-questions-maintainer)):** the
  wording and look (flourishes, ink, textures, layout); entries newest or oldest first;
  whether a share counts when shown or only when copied; a movable book.
- **Traveler names:** `BookView.plain` blocks every UI escape and control byte, but (like
  `Ledger.validName`) it lets through invisible format characters (right-to-left
  override, zero-width joiner) and some non-canonical UTF-8. The worst case is an odd
  glyph or reordered text. Tighten both, or leave them?
- **Phrase wording (#62)**, **cosmetic catalog (#63)** (now without inks, the first
  signature earns nothing by itself), **export (#64)**, **signing (#96)**: as in each
  spec's Open questions.

## Waiting on the maintainer

**In the client** (#12, the unticked items in
[platform-forever.md → Verification checklist](platform-forever.md#verification-checklist-needs-a-forever-client-beta-until-2026-10-21-or-launch-2026-11-04)):
the book's 11 checks; the list composer
(rendering, the mouse wheel, conjunctions fitting their buttons); more innkeepers, with
which zones you've fully walked; the rest of the signing checks; a second character
in a party (round-trips, `got hello PARTY`, `UnitFullName("partyN")`, cross-realm); a guild
round-trip and one dungeon run. **Accounts:** nothing waiting.

## Follow-ups

- **Before the first tag:** `CHANGELOG.md` notes; answer #62 and #63 (IDs freeze);
  Interface `16001` → Forever on CurseForge and Wago is unverified until the first upload.
- **Completeness over excluded records (low, #110 review):** a marked continent whose
  zones were all excluded, or a marked zone that lost an inn to a bad record, still counts
  as complete. Only the real-data `invalid == {}` test catches it today; failing closed
  in `Collection.bind` would be cheap.
- **Book redraws aren't coalesced:** each ENTRIES message with new entries redraws an open
  book (2–6 ms on a capped ledger in desktop Lua). Watch it in the party test (#12).
- **CI runners:** `ubuntu-latest` moves to Ubuntu 26 from 2026-10-19; watch the first
  runs. GitHub's GraphQL API failed on 2026-10-06; `gh api` (REST) still opened and merged
  PRs ([CONTRIBUTING.md → Branches](../CONTRIBUTING.md#branches-and-pull-requests)).
- **Revisit once in groups (#12):** server-clock jumps in `SyncSchedule`; other AddOns'
  hidden traffic; group-map rescan budget; a dropped `C_Timer.After`; export build time.
- **Weekly reset:** fill in the live regions' rows after launch (beta: Tuesday 16:00 UTC).
- **Code tidy (low):** `isInt` / name allow-lists copied across modules; `Phrase`'s
  load-time asserts. Publish `Data/*` as a reference for export consumers (needs inn
  data). `GOLDEN_F`: regenerate only if a library change breaks it, and say so in the PR.
  `Ledger`'s load-time cap pass is quadratic on a tampered file.
- Delete GitHub's default labels (maintainer call). Move September decisions to
  `docs/archive/decisions-2026-09.md` (`decisions.md` is ~1 550 lines). Archive
  [kickoff.md](kickoff.md) once v1 ships.
