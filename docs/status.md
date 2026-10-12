# Status

> **Summary:** where the project stands right now, what's next, and what's waiting on the
> maintainer. A snapshot, rewritten each session; history lives in git and
> [decisions.md](decisions.md).
> **Read when:** every session, first thing after `CLAUDE.md`.

**Updated:** 2026-10-12 (#148's round ran clean in the client and the ticket is closed;
the conjunction labels are measured, so the strip's buttons stay 124 wide)

## Current state

- **Phase 1 of [kickoff.md](kickoff.md) is done:** every pure module and the sync glue,
  tested and security-reviewed. **Phase 2 (#12) is under way in the Forever beta**
  ([platform-forever.md](platform-forever.md)). `Data/Inns` holds one inn: Calmbreeze Inn
  (NPC `254089`), Zephras Isle (zone 2521, seal 101, Azeroth 947).
- **Agents see the UI through the dev harness, and it works in the client** (#139,
  [testing.md](testing.md#testing-posture); first runs 2026-10-11): `deploy.sh` installs
  the working tree's AddOn and a tour, the client screenshots each step and dumps the
  real layout, `results.sh <out>` reports the run and crops the images. **A reload from a
  timer is blocked on Forever,** so each run needs the maintainer to type `/reload`
  (once to load a deploy, once more to save the results), and watch mode can't work.
  Nothing types into the game for him (decisions.md 2026-10-10).
  **A clean run reports clean (#148, done):** the round of 2026-10-12 ran both tours
  with no failed step, no Lua errors, 0 layout warnings and the 7 expected frames
  hanging outside their root; one round keeps both tours' results.
- **Layout checks in busted (#140)** resolve anchors in the stub and check the book and
  the composer. Their text width (0.6 em) is now measured against the client: 0.43 to
  0.60 em over 40 strings, so it stays as the upper bound.
- **Seen in the client on 2026-10-11:**
  - the spine (#137): the covers meet in the middle;
  - #143's fixes (#145, decisions.md 2026-10-11,
    [book.md §3.11.1](specs/book.md#3111-frames-and-the-look-draft)): the inn page's rows
    and header sit exactly where the layout checks put them, and the conjunction strip
    has 6 wider buttons, 3 a row;
  - the composer's lists (#102), both lines;
  - the page label and the `<` `>` page buttons (#146): the label was ink on the page
    file's dark bottom edge and the old arrows were 4 px wide; both read now.
  The long cases (a three-line phrase, a wrapped traveler line, a two-line inn name)
  exist only in the layout checks: the maintainer's ledger has one short signature.
- **Seen in the client on 2026-10-12 (#148's round):** every tab of the book and
  Calmbreeze Inn's page (opened through its row, and through Read at the innkeeper); the
  composer on both lines; every voice's conjunction strip. **The conjunction labels are
  30 to 95.8 wide** (0.42 to 0.55 em), so the 124-wide buttons stay: three labels are
  too wide for the old 92 (decisions.md 2026-10-12).
- **Signing works in the client** (#96, [sign.md](specs/sign.md)), with 8 phrase voices
  (#100). The book (`UI/Book`, #106, [book.md](specs/book.md)) and the composer are
  DRAFT looks.
- **No inks (#105):** one ink for every signature; IDs 1100..1199 reserved.
- **Place rules wait for completeness marks (#110,
  [collection-cosmetics.md §3.11](specs/collection-cosmetics.md#311-completeness-marks-amended-2026-10-07-110)):**
  only places `Data/Inns` marks `complete` count toward zone, continent and `all` rules.
  Nothing is marked, so the book shows "1 of 1+". **Fails closed (#118).**
- **Names** reject malformed UTF-8 and hidden characters (#119,
  [sync-ledger.md §5.2a](specs/sync-ledger.md#52a-hidden-characters-in-names-amended-2026-10-07-119)).
- **Releasing:** last released to `main` on 2026-10-08 (#129). Since then, `dev` holds
  #133, the book fixes #135–#137, the dev tooling #139/#140, and #145 and #146 (both
  change what ships: `UI/Book.lua`, `Sign.lua`, `BookView.lua`). They go out with the
  next release PR. No tags yet (maintainer gate). **CI:** eight required checks on
  `ubuntu-24.04`, green.

## Next step

- **No ticket is open for agents.** #12 is the maintainer's walk; pick from Follow-ups
  (check each against decisions.md first), or take the next answer the maintainer gives
  to an open question. `dev` is ahead of `main` (Releasing, above): a release PR can go
  at any time.
- **The harness loop** (agent): `sh scripts/devclient/deploy.sh -t book,composer`, ask
  the maintainer for the steps below, then `sh scripts/devclient/results.sh <scratch dir>`
  (Lua on PATH) and read the cropped PNGs, the trees, the warnings and the list of
  hanging frames. Results name the character: keep them out of the repo. The book
  tour's results are in `<scratch dir>/earlier`. **Don't deploy while a round is under
  way:** a new request runs the book tour at the next `/reload` and replaces the
  results. The raw screenshots (`Screenshots/` in the client folder) are readable
  before the saving reload, and show whether a round has started. **A request runs once:**
  after a round that went wrong, deploy again before the next `/reload`
  ([testing.md](testing.md#testing-posture), the two traps).
- **A harness round (maintainer), when an agent asks for one:**
  1. `/reload`. The book tour runs about 4 s later and closes the book when done
     (about 15 s; leave the book alone until then).
  2. Talk to an innkeeper, leave the gossip window open, `/ildev run composer` (about
     20 s: it steps through every voice on line 2; it never clicks Sign; it ends on the
     inn's page).
  3. `/reload` again, then tell the agent.
- **In the client (maintainer), before the beta ends 2026-10-21.** Still by eye, on the
  [platform-forever.md checklist](platform-forever.md#verification-checklist-needs-a-forever-client-beta-until-2026-10-21-or-launch-2026-11-04):
  the mouse wheel on the composer lists; talk to every innkeeper you pass and **note per
  zone whether you've seen every inn in it**.

## Client access

In the beta until **2026-10-21**; launch **2026-11-04**. Beta client
`World of Warcraft\_classic_beta_`, with the probe, ILDev as of #148 and `dev`'s AddOn as
of #146 installed (deployed 2026-10-12; that request has run, so nothing runs at the
next `/reload`).

## Open questions (maintainer to decide)

None block work; DRAFTs ship until answered.
- **Which zones to mark complete:** your call from the walk (#12). An unmarked zone's
  seal stays locked. The `"+"` wording is DRAFT.
- **The book** ([book.md → Open questions](specs/book.md#open-questions-maintainer)) and
  **the composer** ([sign.md → Open questions](specs/sign.md#open-questions-maintainer)):
  wording and look.
  - **Where the tabs go (new, 2026-10-11):** they hang under the book, and in the client
    the player frame (moved to the bottom center) and the beta's Issue Reporter button
    drew over them: "Inns" half covered, "Share" almost hidden. Keep them there, or put
    them inside the book (for example along its top, beside Close)?
  - **The spine:** two ribbons (#137, as built and now seen) or one? For one, crop the
    right page's cover with `SetTexCoord(~0.123, 1, 0, 1)`; decisions.md 2026-10-09
    (later).
  - **Inner padding:** are the right-hand numbers and the Use buttons too close to the
    page's border?
  - **Small screens:** the book is 976 wide; at UI scale 1 a 5:4 screen gives 960, so
    it would be clamped against the edges. Shrink it, scale it, or accept it?
  - **The conjunction strip (#143):** 6 buttons, 3 a row, so Hearthside's 7 conjunctions
    page. Keep it, or three rows of three (no paging; the composer grows 22 taller)?
    Back to 4 a row is out: the labels are measured (decisions.md 2026-10-12).
  - **The inn page (#143):** a heading row is now 30 high and the others 64 (they were
    all 54). Fine, or tighter?
- **An offline renderer** (the stub's frames drawn in a browser with the client's
  textures, for the gap from 2026-10-21 to launch): decide once the gap is near
  (decisions.md 2026-10-10).
- **Phrase wording (#62)**, **cosmetic catalog (#63)**, **export (#64)**: as in each
  spec's Open questions.

## Waiting on the maintainer

**In the client** (#12): the unticked items of the platform-forever checklist (more
innkeepers and which zones are fully walked; the rest of the signing checks; a second
character in a party for round-trips, `UnitFullName("partyN")` and cross-realm names,
#119/#128; a guild round-trip and one dungeon run).

**On the dev machine:** a leftover agent worktree folder, `.claude/worktrees/agent-…`
(untracked, clean, at a commit already on `main`), makes `busted` fail one case
(`addon_load_spec`: its Lua files aren't in the TOC) and `luacheck .` report its files.
CI doesn't see it. Deleting it is the maintainer's call; until then run
`luacheck . --exclude-files ".claude/**"` and expect that one failure.

## Follow-ups

- **Before the first tag:** `CHANGELOG.md` notes; answer #62 and #63 (IDs freeze);
  Interface `16001` → Forever on CurseForge and Wago is unverified until the first upload.
- **When `Data/Inns` fills (#12):** check the names against the inn page's limits
  ([book.md §3.11.1](specs/book.md#3111-frames-and-the-look-draft), "What the room
  rests on").
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
