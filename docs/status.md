# Status

> **Summary:** where the project stands right now, what's next, and what's waiting on the
> maintainer. A snapshot, rewritten each session; history lives in git and
> [decisions.md](decisions.md).
> **Read when:** every session, first thing after `CLAUDE.md`.

**Updated:** 2026-10-10 (agents can now see the UI: the dev harness #139 and layout
checks #140; four layout problems ticketed as #143)

## Current state

- **Phase 1 of [kickoff.md](kickoff.md) is done:** every pure module and the sync glue,
  tested and security-reviewed. **Phase 2 (#12) is under way in the Forever beta**
  ([platform-forever.md](platform-forever.md)). `Data/Inns` holds one inn: Calmbreeze Inn
  (NPC `254089`), Zephras Isle (zone 2521, seal 101, Azeroth 947).
- **Agents can see the UI without the maintainer's screenshots** (decisions.md
  2026-10-10, [testing.md](testing.md#testing-posture)):
  - **The dev harness (#139):** `scripts/devclient/`. `deploy.sh` installs the working
    tree's AddOn and `ILDev` (never packaged) with a tour; on the next login or `/reload`
    the client screenshots each step and dumps the real layout; `results.sh <out>` reports
    the run and crops the images. **Not yet run in the client**: whether `Screenshot()`
    and a timed reload work in Forever is on the platform-forever checklist.
  - **Layout checks in busted (#140):** the stub resolves anchors (`wow.rect`);
    `spec/layout_spec.lua` checks the book (every tab and page, three ledgers, the longest
    inputs) and the composer for regions off their page, overlaps and text that doesn't
    fit. Text widths are an uncalibrated 0.6 em guess.
  - **They found four layout problems** (live "known problem" cases): the longest phrase
    and a long traveler meta line overflow an inn row, a 24-character inn name wraps the
    inn title, and 12 conjunction labels are too wide for their buttons. Fixing them is
    **#143** (`ready`).
- **Signing works in the client** (#96, [sign.md](specs/sign.md)), with 8 phrase voices
  (#100). **The composer shows lists** (#102), built but **not yet seen in the client**;
  the look is DRAFT.
- **The book (`UI/Book`, #106, [book.md](specs/book.md)) was first seen in the client on
  2026-10-09.** Three fixes came from those screenshots (#135 one page file, #136 the
  stamp's bottom side, #137 the covers meet as the spine). #137 is not yet seen in the
  client. The look is DRAFT.
- **No inks (#105):** one ink for every signature; IDs 1100..1199 reserved.
- **Place rules wait for completeness marks (#110,
  [collection-cosmetics.md §3.11](specs/collection-cosmetics.md#311-completeness-marks-amended-2026-10-07-110)):**
  only places `Data/Inns` marks `complete` count toward zone, continent and `all` rules.
  Nothing is marked, so the book shows "1 of 1+". **Fails closed (#118).**
- **Names** reject malformed UTF-8 and hidden characters (#119,
  [sync-ledger.md §5.2a](specs/sync-ledger.md#52a-hidden-characters-in-names-amended-2026-10-07-119)).
- **Releasing:** last released to `main` on 2026-10-08 (#129). Since then, `dev` holds
  #133, the book fixes #135–#137 and the dev tooling #139/#140 (spec and `scripts/` only;
  nothing that ships changed). They go out with the next release PR. No tags yet
  (maintainer gate). **CI:** eight required checks on `ubuntu-24.04`, green.

## Next step

- **Agents:** **#143** (fix the four layout problems; the layout checks prove the fix).
  Then use the harness on #12's open looks. The low follow-ups below can fill gaps; check
  each one against decisions.md before offering it.
- **The harness loop** (agent): `sh scripts/devclient/deploy.sh -t book` (add `composer`
  when the maintainer will talk to an innkeeper), ask for a `/reload` (or rely on watch
  mode), then `sh scripts/devclient/results.sh <scratch dir>` and read the cropped PNGs
  and the layout warnings. Results name the character: keep them out of the repo.
  `deploy.sh` also replaces the manual "copy the AddOn over and `cmp` it" step.
- **In the client (maintainer), before the beta ends 2026-10-21:**
  - **First, start the client** (ILDev is a new AddOn folder; a `/reload` won't load it).
    A book tour runs about 4 s after login and then reloads the UI by itself. If it
    says the automatic reload didn't happen, type `/reload`. Then tell the agent.
  - To let agents iterate while you're away: in an inn, `/ildev watch`, then go AFK
    (it reloads every 60 s only while resting and AFK; `/ildev watch off` ends it).
  - At Coriella, with the gossip window open: `/ildev run composer` (screenshots both
    composer lines; it never clicks Sign).
  - Still by eye, on the
    [platform-forever.md checklist](platform-forever.md#verification-checklist-needs-a-forever-client-beta-until-2026-10-21-or-launch-2026-11-04):
    the mouse wheel on the composer lists; talk to every innkeeper you pass and **note
    per zone whether you've seen every inn in it**.

## Client access

In the beta until **2026-10-21**; launch **2026-11-04**. Beta client
`World of Warcraft\_classic_beta_`, with the probe, ILDev and the current `dev` AddOn
installed (deployed 2026-10-10; the client was closed).

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
  - **Small screens:** the book is 976 wide; at UI scale 1 a 5:4 screen gives 960, so
    it would be clamped against the edges. Shrink it, scale it, or accept it?
  - **Conjunction labels (#143):** if wider strip buttons don't fit, shorter labels are
    a wording call ("Then, LOUDER...", "By the tides...", "One must add...").
- **An offline renderer** (the stub's frames drawn in a browser with the client's
  textures, for the gap from 2026-10-21 to launch): decide once the gap is near
  (decisions.md 2026-10-10).
- **Phrase wording (#62)**, **cosmetic catalog (#63)**, **export (#64)**: as in each
  spec's Open questions.

## Waiting on the maintainer

**In the client** (#12): the first harness run (above); the unticked items of the
platform-forever checklist (more innkeepers and which zones are fully walked; the rest
of the signing checks; a second character in a party for round-trips,
`UnitFullName("partyN")` and cross-realm names, #119/#128; a guild round-trip and one
dungeon run). The book's and composer's look checks move to the harness once it runs.

## Follow-ups

- **Calibrate the layout checks' text width** (`wow.TEXT_EM`, 0.6 em) from the harness's
  dumped string widths (`sw`) once a run exists; then re-check #143's numbers.
- **The book's page label** (`1 / 1`) didn't show in the client on 2026-10-09. The
  harness's dump shows its rect, layer, level and alpha: read it from the first run.
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
- **Code tidy (low):** `Phrase`'s load-time asserts; `Ledger`'s quadratic load-time cap
  pass on a tampered file; `Sign.lua`'s `listField` builds a full `view()` per click.
  Publish `Data/*` for export consumers once inns exist.
- Delete GitHub's default labels (maintainer call). Archive [kickoff.md](kickoff.md) at v1.
