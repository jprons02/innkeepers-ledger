# Status

> **Summary:** where the project stands right now, what's next, and what's waiting on the
> maintainer. A snapshot, rewritten each session; history lives in git and
> [decisions.md](decisions.md).
> **Read when:** every session, first thing after `CLAUDE.md`.

**Updated:** 2026-10-06 (**`UI/Book` merged** (#106, #108) and **inks dropped** (#105,
#107), both into `dev`; the beta install holds them. Not yet released to `main`)

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
- **Not built:** the list-style composer (#102, `ready`).
- **Releasing is wired up** ([CONTRIBUTING.md → Releasing](../CONTRIBUTING.md#releasing)).
  `main` holds everything through #104; #107 and #108 are on `dev` only. No tags yet
  (maintainer gate). **CI:** eight required checks, all green on `dev`.

## Next step

- **Agents:** #102 (browse phrases in lists instead of arrow cyclers). Then a `dev → main`
  release PR with its security review.
- **In the client (maintainer):** restart the client (a new file, `BookView.lua`, needs a
  full restart, not `/reload`), then run the book's checks on the
  [platform-forever.md checklist](platform-forever.md#verification-checklist-needs-a-forever-client-beta-until-2026-10-21-or-launch-2026-11-04).
  Two matter most: do the parchment textures load, and do `‹ › ·` render. A screenshot of
  each tab helps retune the DRAFT look. Keep talking to every innkeeper you pass.

## Client access

In the beta until **2026-10-21**; launch **2026-11-04**. Beta client
`World of Warcraft\_classic_beta_`, with the probe and the `dev` AddOn installed.

## Open questions (maintainer to decide)

None block work; DRAFTs ship until answered.
- **Release gate, decide before 2026-10-21: `Data/Inns`.** The `zone`, `continent` and
  `all` rules count only the inns the data knows, and earned cosmetics are never taken
  away, so a partial atlas in a release hands out "every inn" for good (the beta's first
  signature earned 101, 1003 and 2 at once). Either you visit every Forever inn during the
  beta, or the rules gain a guard (e.g. a per-zone "complete" mark,
  [collection-cosmetics.md](specs/collection-cosmetics.md) change).
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
the book's 11 checks; more innkeepers; the rest of the signing checks; a second character
in a party (round-trips, `got hello PARTY`, `UnitFullName("partyN")`, cross-realm); a guild
round-trip and one dungeon run. **Accounts:** nothing waiting.

## Follow-ups

- **Before the first tag:** `CHANGELOG.md` notes; answer #62 and #63 (IDs freeze);
  Interface `16001` → Forever on CurseForge and Wago is unverified until the first upload.
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
