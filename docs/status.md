# Status

> **Summary:** where the project stands right now, what's next, and what's waiting on the
> maintainer. A snapshot, rewritten each session; history lives in git and
> [decisions.md](decisions.md).
> **Read when:** every session, first thing after `CLAUDE.md`.

**Updated:** 2026-11-13 (the live probe's second read: five more inns, eight in all; a
dungeon run's addon-message facts; the live client's AddOn updated so signing works)

## Current state

- **The code is ready for v1.** Phase 1 of [kickoff.md](kickoff.md) is done (every pure
  module and the sync glue, tested and security-reviewed); signing (#96), 8 phrase voices
  (#100), the book (#106) and the composer work in the client, the last two as DRAFT
  looks. Seen in the client on 2026-10-11 and 10-12: every tab, the inn page, the
  composer on both lines, every voice's conjunction strip (decisions.md 2026-10-11,
  2026-10-12, now in the October archive).
- **`Data/Inns` holds eight inns** (zone seals 101..108): Calmbreeze Inn (Zephras Isle,
  from the beta) and seven Alliance-only inns from the live probe (read 2026-11-06 and
  2026-11-13): Lion's Pride Inn (Elwynn), The Gilded Rose (Stormwind), Sentinel Hill Inn
  (Westfall), Lakeshire Inn (Redridge), Stoutlager Inn (Loch Modan), Deepwater Tavern
  (Wetlands) on Eastern Kingdoms (1415), and Auberdine Inn (Darkshore) on Kalimdor
  (1414). IDs, map chains and how each name was got:
  [platform-forever.md](platform-forever.md) (the Collect item). **Sentinel Hill Inn and
  Auberdine Inn are DRAFT names** (`<town> Inn`, decisions.md 2026-11-13). **The walk
  (#12) continues.** Nothing is marked `complete`, so place rules stay locked and the
  book shows "1 of 8+" (fails closed, #110/#118). The Inns tab's list now runs to two
  pages (16 rows each), and the seals list to two (7 each).
- **The live ledger was empty until 2026-11-13:** the client's AddOn was installed on
  2026-11-04 with only Calmbreeze in `Data/Inns`, so no innkeeper met in live showed
  *Sign the guestbook*. Its `Data/Inns.lua` (the only shipped file that differed) was
  replaced with this one on 2026-11-13; signing works at the seven live inns from the next
  login.
- **`Data/*` is published as JSON (#156, on `dev`):** `docs/data/forever.json`, written
  by `scripts/data-json.lua`; CI fails when it's stale
  ([specs/data-json.md](specs/data-json.md)). **Regenerate and commit it with every
  `Data/*` change.**
- **Inn notes (#157) are built on `feat/157-inn-notes`**, not merged
  ([specs/inn-notes.md](specs/inn-notes.md)): at an innkeeper `Data/Inns` doesn't know
  (recognized by the binder option's icon, 132052), `Notes.lua` quietly saves the NPC ID,
  zone, continent, time and faction in `db.global.notes[guid]` (200 at most, first note
  wins, pruned at login once the data knows the NPC), and every export carries them as
  the optional `notes` field (v1). `GetBindLocation` joined the forbidden-API list. **When
  it merges is decided separately** (decisions.md 2026-11-04: the first release after
  launch); its in-client checks are under Waiting on the maintainer.
- **The dev harness** (#139, [testing.md](testing.md#testing-posture)) screenshots and
  measures the UI in the client; each round needs the maintainer's `/reload`s. Its last
  round (2026-10-12) ran clean. Layout checks in busted (#140) use a measured 0.6 em
  text width.
- **Releasing:** last released to `main` on 2026-10-18 (#153). **`dev` is ahead by #156,
  #160 and this session's inns:** `Data/Inns.lua` ships, so the first tag's notes
  should mention the inns. `CHANGELOG.md` holds the first
  release's notes under `## Unreleased` (#152). No tags yet (maintainer gate). **CI:**
  eight required checks on `ubuntu-24.04`, green.

## Path to launch

The code is ready; what's left is in-client data and checks, the maintainer's answers,
and the tag. The CurseForge and Wago projects, page text and `release` tokens are done.
1. **The walk (maintainer, live client):** talk to every innkeeper you pass (the probe
   logs each), and note per zone whether you've seen every inn in it. Visit Calmbreeze
   Inn early: it shows whether live kept the beta's IDs. One session with a second
   character in a party: sync between two players is untested.
2. **Answers (maintainer):** #62 and #63 before the first tag (their IDs freeze), and
   which zones to mark complete. The other open questions can ship as DRAFTs.
3. **Agent, as inns arrive:** read the probe's `npcs` table from disk, fill `Data/Inns`,
   regenerate the JSON, mark the chosen zones, check names against the inn page's limits
   ([book.md §3.11.1](specs/book.md#3111-frames-and-the-look-draft)); then a release PR
   with its security review, and rename `CHANGELOG.md`'s `## Unreleased` to the tag's
   `## vX.Y.Z` (the notes don't need #156: nothing in it ships).
4. **Tag and publish (maintainer):** see
   [CONTRIBUTING.md → Releasing](../CONTRIBUTING.md#releasing). Interface `16001` →
   Forever on CurseForge and Wago is unverified until that first upload.

## Next step

- **No agent ticket is ready.** #12 waits on the walk; **#157** (noting unknown
  innkeepers in the export) is built on its branch (review pending), and merges after
  the first tag (decisions.md 2026-11-04).
  Otherwise pick from Follow-ups, checking decisions.md first.
- **When the maintainer reports a walk:** read the `npcs` table (not the `log`, which
  rolls over at 3 000 entries) of `WTF/Account/<account>/SavedVariables/!ILProbe.lua`
  under the live client folder; an innkeeper is the NPC whose gossip options include
  *Make this inn your home.* (icon 132052). Then Path to launch step 3, and copy the new
  `Data/Inns.lua` into the live client's `Interface/AddOns/InnkeepersLedger/Data/` so he
  can sign there (WoW closed, or a `/reload`). Also read `InnkeepersLedger.lua` beside
  the log: its `own` list shows what he signed. Both name the character: summarize into
  the docs, never commit them.
- **The harness in live:** `deploy.sh` and `results.sh` default to the beta folder; pass
  the live client's folder (or set `ILDEV_CLIENT`). ILDev isn't installed there yet;
  `deploy.sh` installs it. The maintainer's steps per round: `/reload` (the book tour,
  ~15 s); at an innkeeper with gossip open, `/ildev run composer` (~20 s); `/reload`
  again. Don't deploy mid-round; a request runs once (testing.md, the two traps).

## Client access

**Live since 2026-11-04.** Client `World of Warcraft\_forever_` (build 1.60.1.70755),
with the probe and `dev`'s AddOn installed on 2026-11-04; its `Data/Inns.lua` replaced on
2026-11-13 (eight inns), so it matches `dev`'s shipped files
([platform-forever.md](platform-forever.md)). The beta client
(`_classic_beta_`) is closed.

## Open questions (maintainer to decide)

None block work; DRAFTs ship until answered.
- **Which zones to mark complete:** your call from the walk. The `"+"` wording is DRAFT.
- **The book** ([book.md → Open questions](specs/book.md#open-questions-maintainer)) and
  **the composer** ([sign.md → Open questions](specs/sign.md#open-questions-maintainer)):
  - **Tabs:** under the book (the player frame and the Issue Reporter covered them in the
    beta) or inside it, e.g. along the top beside Close?
  - **Spine:** two ribbons (as built) or one (`SetTexCoord(~0.123, 1, 0, 1)` on the right
    cover)?
  - **Inner padding:** right-hand numbers and Use buttons too close to the border?
  - **Small screens:** the book is 976 wide (a 5:4 screen at scale 1 gives 960). Shrink,
    scale or accept?
  - **Conjunction strip:** 6 buttons, 3 a row, Hearthside's 7 page; or three rows of
    three (22 taller)? 4 a row is out (labels measured).
  - **Inn page rows:** headings 30 high, others 64. Fine, or tighter?
- **Inn names (DRAFT):** *Sentinel Hill Inn* and *Auberdine Inn* are `<town> Inn`
  because the client gives only the town (decisions.md 2026-11-13). Keep, or rename?
- **Inn notes (#157, DRAFT):** the Share page now says the text holds "any innkeepers
  you've met that the ledger doesn't know yet" (wording yours). Also: should the book
  show your notes, should noting say anything in chat (it's silent), and should notes be
  opt-in like travelers (they're in every export)?
  ([inn-notes.md → Open questions](specs/inn-notes.md#open-questions-maintainer)).
- **Phrase wording (#62)**, **cosmetic catalog (#63)**, **export (#64)**: as in each
  spec's Open questions.

## Waiting on the maintainer

**In the client** (#12): the walk, now signing at each inn (sign at Lion's Pride Inn or
any of the seven live inns first, then `/reload` and tell an agent: the first live signature); the unticked
[platform-forever.md checklist](platform-forever.md#verification-checklist-needs-a-forever-client-beta-until-2026-10-21-or-launch-2026-11-04)
items (the mouse wheel on the composer lists; the rest of the signing checks; a second
character in a party for round-trips, `UnitFullName("partyN")` and cross-realm names,
#119/#128; a guild round-trip and one dungeon run). **Once #157 is installed:** its
in-client checks ([inn-notes.md §8](specs/inn-notes.md#8-in-client-checks-for-the-maintainer)):
with `/ledger debug` on, an unknown innkeeper (any Horde one, or a new Forever zone's)
gives one `notes: noted <id>` line and one saved note; again gives nothing; a known
innkeeper or a vendor gives nothing; no button, chat line or bind change; the note's
faction; the note in `/ledger share`'s string; the note gone after a data update learns
the innkeeper.

## Follow-ups

- **Encounter lockdown (low):** mid-encounter, addon messages fail (`WHISPER` returns
  `11`, `PARTY` returns `0` and is dropped; platform-forever.md, the instance item).
  `Sync` holds sends in combat, which covered all 7 encounters seen; a player out of
  combat mid-encounter (dead) would lose sends. If wanted: hold on `ENCOUNTER_START`
  until `ENCOUNTER_END` too (a new event pair for the API allow-list).
- **Book redraws aren't coalesced** (2–6 ms per ENTRIES on a capped ledger); a timer is
  ruled out, so any fix waits for a client measurement. DRAFT wording: the `continent`
  rule's "0 of 1" fallback has no "+".
- **CI runners:** pinned to `ubuntu-24.04` (#117); move on purpose before GitHub retires
  it. If coverage nears its 30 min timeout, raise it. If GraphQL fails, use `gh api`
  ([CONTRIBUTING.md](../CONTRIBUTING.md#branches-and-pull-requests)).
- **Revisit once in groups:** server-clock jumps; other AddOns' traffic; group-map rescan
  budget; a dropped `C_Timer.After`; export build time; weekly reset rows for live regions.
- **Name hardening, if wanted (low, #119 review):** stacked combining marks, strong RTL
  letters and blank-rendering symbols (U+1D159) still pass (sync-ledger.md §5.2a).
- **Code tidy (low):** `Phrase`'s load-time asserts; `Ledger`'s quadratic load-time cap
  pass on a tampered file; `Sign.lua`'s `listField` builds a full `view()` per click;
  `scripts/data-json.lua`'s "not in the TOC" error has no test (#156 review).
- Delete GitHub's default labels (maintainer call). Archive [kickoff.md](kickoff.md) at v1.
