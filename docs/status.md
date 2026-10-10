# Status

> **Summary:** where the project stands right now, what's next, and what's waiting on the
> maintainer. A snapshot, rewritten each session; history lives in git and
> [decisions.md](decisions.md).
> **Read when:** every session, first thing after `CLAUDE.md`.

**Updated:** 2026-10-09 (after the book's first in-client looks: #135 page file, #136
stamp bottom, #137 covers meet as the spine)

## Current state

- **Phase 1 of [kickoff.md](kickoff.md) is done:** every pure module and the sync glue,
  tested and security-reviewed. **Phase 2 (#12) is under way in the Forever beta**
  ([platform-forever.md](platform-forever.md)). `Data/Inns` holds one inn: Calmbreeze Inn
  (NPC `254089`), Zephras Isle (zone 2521, seal 101, Azeroth 947).
- **Signing works in the client** (#96, [sign.md](specs/sign.md)), with 8 phrase voices
  (#100). **The composer now shows lists** (#102): line tabs, a voice strip, a
  conjunction strip on line 2, template / category / word lists with page buttons and
  the mouse wheel. Lists are built, **still not seen in the client**; the look is DRAFT.
- **The book (`UI/Book`, #106, [book.md](specs/book.md)) was first seen in the client on
  2026-10-09.** Every tab draws, and the #110 "1 of 1+" wording shows. Three fixes came
  from the screenshots, all merged, installed and verified by tests:
  - #135: `Spellbook-Page-2` was a blur, so both pages use `Spellbook-Page-1`.
  - #136: a stamp's bottom side was drawn above the book.
  - #137: the maintainer wanted the crease in the middle, so both covers and ribbons now
    meet as the spine, with no black gap.
  The #137 look is not yet seen in the client. Results are logged in the
  [checklist](platform-forever.md#verification-checklist-needs-a-forever-client-beta-until-2026-10-21-or-launch-2026-11-04).
  The look is DRAFT.
- **No inks (#105):** one ink for every signature; IDs 1100..1199 reserved.
- **Place rules wait for completeness marks (#110,
  [collection-cosmetics.md §3.11](specs/collection-cosmetics.md#311-completeness-marks-amended-2026-10-07-110)):**
  a zone seal, `zones n`, `continent` and `all` count only places `Data/Inns` marks
  `complete`. Nothing is marked, so a signature earns only `inns n` items; the book shows
  "1 of 1+". This settles the partial-atlas release gate. **Fails closed (#118):** if
  any `Data/Inns` record is excluded, nothing counts as complete.
- **Names** reject malformed UTF-8 and hidden characters (#119,
  [sync-ledger.md §5.2a](specs/sync-ledger.md#52a-hidden-characters-in-names-amended-2026-10-07-119)).
- **Releasing:** last released to `main` on 2026-10-08 (#129). Since then, `dev` holds
  #133 (a refactor with no change in behavior: `Collection.validName` is now shared with
  `Cosmetics`) and the book's look fixes #135–#137. They go out with the next release PR.
  No tags yet (maintainer gate).
  **CI:** eight required checks on `ubuntu-24.04`, green.

## Next step

- **Agents:** no `ready` ticket. #12's in-client results drive what's next: fix what the
  screenshots show, add inns and mark zones complete from the walk. The low follow-ups
  below can fill gaps. Check each one against decisions.md before offering it: the redraw
  item looked open, but a timer was already ruled out.
- **Before trusting a screenshot, check the client's copy:** `cmp` each TOC file
  against `Interface/AddOns/InnkeepersLedger` ([testing.md](testing.md#testing-posture),
  the in-client probe). On 2026-10-09 the copy was 3 days stale, so the composer and
  #110 weren't in it. After a merge that touches game files, copy them over; `/reload`
  is enough unless a file is new.
- **In the client (maintainer), before the beta ends 2026-10-21** (`/reload` is enough
  now; the current `dev` is installed), on the
  [platform-forever.md checklist](platform-forever.md#verification-checklist-needs-a-forever-client-beta-until-2026-10-21-or-launch-2026-11-04):
  - the spine in the middle looks right (#137)
  - the Collection stamp has four sides and no red line shows above the book (#136)
  - the page label `1 / 1` shows (it didn't in the screenshots; the cause is unknown)
  - `‹ ›` are readable on the page buttons
  - **the composer**: a screenshot of line 1 and line 2 at Coriella, the mouse wheel
    scrolls the lists, long conjunctions fit
  - talk to every innkeeper you pass and **note per zone whether you've seen every inn
    in it** (that's what lets a zone be marked `complete`)

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
  - **The spine:** two ribbons (#137, as built) or one? For one, crop the right page's
    cover with `SetTexCoord(~0.123, 1, 0, 1)`; decisions.md 2026-10-09 (later).
  - **Inner padding:** are the right-hand numbers and the Use buttons too close to the
    page's border?
- **Phrase wording (#62)**, **cosmetic catalog (#63)**, **export (#64)**: as in each
  spec's Open questions.

## Waiting on the maintainer

**In the client** (#12, the unticked items of the platform-forever checklist): the book's
11 checks; the composer lists; more innkeepers and which zones are fully walked; the
rest of the signing checks; a second character in a party (round-trips,
`UnitFullName("partyN")`, cross-realm; it also confirms other players' names use a plain
space, which #119 requires, #128); a guild round-trip and one dungeon run.

## Follow-ups

- **Before the first tag:** `CHANGELOG.md` notes; answer #62 and #63 (IDs freeze);
  Interface `16001` → Forever on CurseForge and Wago is unverified until the first upload.
- **DRAFT wording:** the `continent` rule's "0 of 1" fallback has no "+". **Book redraws
  aren't coalesced** (2–6 ms per ENTRIES on a capped ledger); watch in #12. A timer is
  ruled out (decisions.md, the book entry); any fix waits for a client measurement.
- **CI runners:** pinned to `ubuntu-24.04` (#117); move on purpose before GitHub retires
  it. Job timeouts and the apt retry: decisions.md 2026-10-08. If coverage nears its
  30 min, raise it. If GraphQL fails, use `gh api` (REST)
  ([CONTRIBUTING.md](../CONTRIBUTING.md#branches-and-pull-requests)).
- **Revisit once in groups (#12):** server-clock jumps; other AddOns' traffic; group-map
  rescan budget; a dropped `C_Timer.After`; export build time. Weekly reset rows for live
  regions after launch.
- **Name hardening, if wanted (low, #119 review):** stacked combining marks, strong RTL
  letters and blank-rendering symbols (U+1D159) still pass (sync-ledger.md §5.2a, Out of
  scope).
- **The book's page label** (`1 / 1`, `UI/Book.lua` `buildPage`) has its text set
  (tests), but it didn't show in the client on 2026-10-09. If it's still missing after
  #137, look at its layer and frame level against the panels, and at the font.
- **Code tidy (low):** `Phrase`'s load-time asserts; `Ledger`'s quadratic load-time cap
  pass on a tampered file; `Sign.lua`'s `listField` builds a full `view()` per click.
  Publish `Data/*` for export consumers once inns exist.
- Delete GitHub's default labels (maintainer call). Archive [kickoff.md](kickoff.md) at v1.
