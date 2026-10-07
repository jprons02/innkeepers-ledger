# Status

> **Summary:** where the project stands right now, what's next, and what's waiting on the
> maintainer. A snapshot, rewritten each session; history lives in git and
> [decisions.md](decisions.md).
> **Read when:** every session, first thing after `CLAUDE.md`.

**Updated:** 2026-10-07 (**released to `main` (#114):** the book, no inks, the list
composer (#102) and completeness marks (#110); release security review passed)

## Current state

- **Phase 1 of [kickoff.md](kickoff.md) is done:** every pure module and the sync glue,
  tested and security-reviewed. **Phase 2 (#12) is under way in the Forever beta**
  ([platform-forever.md](platform-forever.md)). `Data/Inns` holds one inn: Calmbreeze Inn
  (NPC `254089`), Zephras Isle (zone 2521, seal 101, Azeroth 947).
- **Signing works in the client** (#96, [sign.md](specs/sign.md)), with 8 phrase voices
  (#100). **The composer now shows lists** (#102): line tabs, a voice strip, a
  conjunction strip on line 2, template / category / word lists with page buttons and
  the mouse wheel. Lists are built, not yet seen in the client; the look is DRAFT.
- **The book (`UI/Book`, #106, [book.md](specs/book.md))** is built, not yet seen in the
  client: a parchment spread with Inns, Collection, Cosmetics and Share tabs; `/ledger`
  toggles it; "Read the guestbook" sits beside "Sign the guestbook". Look is DRAFT.
- **No inks (#105):** one ink for every signature; IDs 1100..1199 reserved.
- **Place rules wait for completeness marks (#110,
  [collection-cosmetics.md §3.11](specs/collection-cosmetics.md#311-completeness-marks-amended-2026-10-07-110)):**
  a zone seal, `zones n`, `continent` and `all` count only places `Data/Inns` marks
  `complete`. Nothing is marked, so a signature earns only `inns n` items; the book shows
  "1 of 1+". This settles the partial-atlas release gate.
- **Releasing:** `main` and `dev` hold the same content (#114). No tags yet (maintainer
  gate). **CI:** eight required checks, green.

## Next step

- **Agents:** no `ready` ticket. #12's in-client results drive what's next: retune the
  DRAFT look from screenshots, add inns and mark zones complete from the walk. Small
  follow-ups below can fill gaps.
- **In the client (maintainer):** restart fully (new file `BookView.lua`; `/reload` isn't
  enough), then run the book's and the composer's checks on the
  [platform-forever.md checklist](platform-forever.md#verification-checklist-needs-a-forever-client-beta-until-2026-10-21-or-launch-2026-11-04).
  Most important: parchment textures load, `‹ › ·` render, the mouse wheel scrolls the
  lists, long conjunctions fit their buttons. A screenshot of each book tab and each
  composer line. Talk to every innkeeper you pass and **note per zone whether you've seen
  every inn in it** (that's what lets a zone be marked `complete`).

## Client access

In the beta until **2026-10-21**; launch **2026-11-04**. Beta client
`World of Warcraft\_classic_beta_`, with the probe and the `dev` AddOn installed.

## Open questions (maintainer to decide)

None block work; DRAFTs ship until answered.
- **Which zones to mark complete:** your call from the walk (#12). An unmarked zone's
  seal stays locked. The `"+"` wording is DRAFT.
- **The book** ([book.md → Open questions](specs/book.md#open-questions-maintainer)) and
  **the composer** ([sign.md → Open questions](specs/sign.md#open-questions-maintainer)):
  wording and look.
- **Traveler names:** `BookView.plain` (like `Ledger.validName`) lets invisible format
  characters (right-to-left override, zero-width joiner) through. Worst case: odd glyphs
  or reordered text. Tighten, or leave?
- **Phrase wording (#62)**, **cosmetic catalog (#63)**, **export (#64)**: as in each
  spec's Open questions.

## Waiting on the maintainer

**In the client** (#12, the unticked items of the platform-forever checklist): the book's
11 checks; the composer lists; more innkeepers and which zones are fully walked; the
rest of the signing checks; a second character in a party (round-trips,
`UnitFullName("partyN")`, cross-realm); a guild round-trip and one dungeon run.

## Follow-ups

- **Before the first tag:** `CHANGELOG.md` notes; answer #62 and #63 (IDs freeze);
  Interface `16001` → Forever on CurseForge and Wago is unverified until the first upload.
- **Fail closed on completeness (low, #110 review):** a marked place that lost a record to
  validation still counts as complete; only the real-data `invalid == {}` test catches it.
  The `continent` rule's "0 of 1" fallback has no "+" (DRAFT wording pass).
- **Book redraws aren't coalesced** (2–6 ms per ENTRIES on a capped ledger). Watch in #12.
- **CI runners:** pinned to `ubuntu-24.04` (#117); move on purpose before GitHub retires it. If GitHub's GraphQL
  API fails, `gh api` (REST) still works ([CONTRIBUTING.md](../CONTRIBUTING.md#branches-and-pull-requests)).
- **Revisit once in groups (#12):** server-clock jumps; other AddOns' traffic; group-map
  rescan budget; a dropped `C_Timer.After`; export build time. Weekly reset rows for live
  regions after launch.
- **Code tidy (low):** `isInt` / name allow-lists copied across modules; `Phrase`'s
  load-time asserts; `Ledger`'s quadratic load-time cap pass on a tampered file;
  `Sign.lua`'s `listField` builds a full `view()` per click. Publish `Data/*` for export
  consumers once inns exist.
- Delete GitHub's default labels (maintainer call). Archive [kickoff.md](kickoff.md) at v1.
