# Decisions

> **Summary:** the decision log. Settled decisions with the reason for each and the
> options rejected, dated, **newest first**.
> **Read when:** a question may already be settled; before proposing a change in
> direction or re-proposing a rejected option.

**Don't re-litigate these.** If new information changes one, add a new dated entry at the
top that supersedes it (and links it) rather than editing history.

---

### 2026-10-08 — One copy of the place-name rule; `isInt` stays per module

`Cosmetics` had its own copy of `Collection`'s rule 5 (the byte allow-list, a capital
first letter, no trailing or double space). `Collection.validName(s, maxBytes)` is now
exported, and `Cosmetics` uses it for catalog names (32 bytes) and zone-seal names (48)
(#132; [specs/collection-cosmetics.md §3.8](specs/collection-cosmetics.md#38-api)).
Behavior is unchanged. A bad limit gives `false`, never an error. **`isInt` stays a local
in each module:** it's one line, and sharing it would make every module (`Ledger`
included) load after a helper. That adds a load-order dependency to validation code and
changes nothing it does. **Rejected:** *a shared `Util.lua`* (the load-order cost); *merging `Phrase`'s
allow-list* (a different rule: it allows `!` and `?`).

### 2026-10-08 — CI jobs have timeouts, and apt retries a stalled mirror

On 2026-10-07 `apt-get update` stalled mid-fetch on three CI runs and sat until GitHub's
6-hour default cancelled them (#126). Every job in `ci`, `policy-guard` and `release` now
sets `timeout-minutes` well above its usual run time (coverage 30, luacheck and busted 15,
`package` 10, `publish` 20, script-only jobs 5), and the toolchain jobs install through
`scripts/ci-apt-install.sh`: apt's network timeouts and retries, `timeout` on each
command, three attempts. The toolchain sources and versions are unchanged. **Rejected:**
*caching the toolchain* (`actions/cache` is one more action and a cache to trust, for
about a minute saved per job); *a Lua setup action from the marketplace* (a new
third-party action, which checklist item 12 rules out).

### 2026-10-07 — Names with hidden characters or malformed UTF-8 are rejected

The maintainer chose to tighten (#119, [specs/sync-ledger.md
§5.2a](specs/sync-ledger.md#52a-hidden-characters-in-names-amended-2026-10-07-119)).
`Ledger.cleanText` decodes strictly per RFC 3629 (no overlongs, surrogates or code points
above U+10FFFF) and rejects any code point in one sorted 48-row table: controls, every
space but U+0020, line and paragraph separators, format and bidi controls (a
right-to-left override, zero-width joiners), invisible fillers, variation selectors,
private use and noncharacters. `validName` requires it, so sync receive, the ledger load,
`addForeign`, the export and our own name all drop such names; the book's `plain` shows
the fallback. No real character name in any supported locale contains one, so no player
is lost; a stored traveler with such a name is dropped at load like any invalid record.
No wire, export or SavedVariables version change: the export only narrows what it
writes. **Rejected:** *stripping the characters* (it changes the sender's name, so a
forgery could look exactly like someone else); *allow-listing scripts* (too many locales);
*a Unicode database at runtime* (size, and no need); *checking only at display* (the
ledger and export would still carry them). Combining-mark stacks and strong RTL letters
stay out of scope.

### 2026-10-07 — Completeness fails closed on any excluded record

If `Collection.bind` excludes any record of the atlas, no zone, continent or the atlas
counts as complete, whatever the marks say (#118, [specs/collection-cosmetics.md
§3.11](specs/collection-cosmetics.md#311-completeness-marks-amended-2026-10-07-110)).
Until now a zone marked `complete` that lost one of its inns to validation still counted
as complete, so a data mistake that slipped past CI could hand out its seal for good
(earned things are never taken away). The shipped data never trips the guard: the
real-data test keeps `invalid` empty. **Rejected:** *withholding completeness only from
the place that lost a record* (an excluded record can't always be traced to a place: a bad
`zone` field, a non-table record, a bad key; and precision buys nothing while `invalid`
stays empty).

### 2026-10-07 — A month's decisions move to the archive once the month is over

`decisions.md` had grown to ~1 590 lines, most of it September's build-out, and every
session that checks a settled question paid for all of it (#120). The 2026-09-26..30
entries moved verbatim (link paths aside) to
[archive/decisions-2026-09.md](archive/decisions-2026-09.md), next to the seed entries;
`decisions.md` keeps a dated title index so references by name still resolve. From now on,
when a closed month's entries outgrow a quick read, they move to
`archive/decisions-YYYY-MM.md` the same way, with a map row. **Rejected:** *one archive
file for everything* (it grows the same way); *summaries instead of the text* (the reasons
and rejected options are the point of the log).

### 2026-10-07 — CI runners pinned to `ubuntu-24.04`

Every workflow job runs on `ubuntu-24.04` instead of `ubuntu-latest` (#117). GitHub moves
`ubuntu-latest` to Ubuntu 26 from 2026-10-19, between the beta and launch; a new image can
change apt's `lua5.1` or luarocks under us and turn required checks red in launch week.
Moving to a newer image is a deliberate PR, before GitHub retires 24.04. Job names are
unchanged, so branch protection's required checks still match. **Rejected:** *staying on
`-latest` and fixing breakage when it comes* (the timing is the worst possible).

### 2026-10-07 — Composer: lists, one line at a time, core frame API only

The signing composer (#102, [specs/sign.md](specs/sign.md) §3.6, §3.7) shows a line's
choices as lists instead of `<` `>` cyclers: line tabs, a voice strip, a conjunction
strip on line 2, and template, category and word lists with page buttons and the mouse
wheel. The seal keeps its cycler (few items). The windows live in the pure draft
(`pick`, `setLine`, `list`, `scroll`, one setter shared with `step`), so they're tested
with a coverage floor. **Rejected:** arrow cyclers for 156 templates and 175 words (no
one browses that); both lines' lists at once (twice a gossip frame's height); dropdowns
(`UIDropDownMenu` deprecated, the menu API unverified on Forever); `ScrollBox` /
`FauxScrollFrame` (unverified, more than a few rows need). The look stays a DRAFT.

### 2026-10-07 — Partial atlas: place rules count only places marked complete

**Settles** what the "every inn" rules (a zone's seal, `zones n`, `continent`, `all`) mean
while `Data/Inns` is still partial (#110, [specs/collection-cosmetics.md
§3.11](specs/collection-cosmetics.md#311-completeness-marks-amended-2026-10-07-110)).
The data marks what it knows in full: `complete = true` on a zone (every inn in it is
known) or a continent (every zone of it with an inn is known), and `ns.Data.AtlasComplete
= true` (every continent with an inn is known). Any other value excludes the record.
A continent counts as complete only if its zones all are, and the atlas only if its
continents all are. `Collection.progress` sets `done` only for complete places and adds
`complete` flags, so the cosmetics need no guard of their own; `inns n` stays unguarded
(a partial atlas can only undercount it). The book follows an incomplete place's total
with a DRAFT `"+"` ("1 of 1+ inns signed"). Marks are set from the in-client walk, never
by guessing; the shipped data has none yet. No wire, export-format or SavedVariables
change: the export's `done` is just absent more often.

**Why:** the progress math counts only the inns the data knows, and earned cosmetics are
never taken away, so a release with a partial atlas would hand out "every inn" rewards for
good. The beta showed it: the first signature at Calmbreeze earned seal 101, the
Cartographer's quill and the Innkeeper's seal at once. An unlock a character already
recorded is still kept through the `earned` floor (beta saves don't reach live realms).
**The maintainer chose this guard** over visiting every inn before the beta ends.

**Rejected:** only the maintainer visiting every inn before release (the beta ends
2026-10-21, and a missed inn would still leak); a release-time switch that turns place
rules off (zone seals known to be safe would wait too); percent thresholds or rules over
known inns only (they move as the data grows); taking unlocks back when the data grows
(earned things are never taken away); marks on inns (an inn can't know it's the last one
in its zone).

### 2026-10-06 — Book: a pure BookView, one named frame for ESC, a GUID-keyed record, the share mark at build, refresh through `onEntries`

The `UI/Book` slice (#106, [specs/book.md](specs/book.md) §3.11–§3.13) settles how the book
is built:

- **Every decision lives in a new pure module, `BookView`,** with a **90% coverage floor**
  (`scripts/check-coverage.sh`, like the other non-boundary pure modules): navigation and
  its clamps, every page model, paging, ordering, text safety, dates, the quill fallback
  and flourishes, the share nudge, and the saved record's read and write shapes.
  `UI/Book.lua` is glue: frames, client reads (hidden-value checked), drawing models. The
  `SignFlow` split again.
- **One global name, `InnkeepersLedgerBook`:** the client's `UISpecialFrames` list needs a
  frame name for Escape to close a plain frame. It is the AddOn's only global; nothing
  else is named, hooked or captured (no keyboard capture, no bindings).
- **The book's own record, `db.global.book[guid]`** (`v = 1`, an optional `quill`, an
  optional `shared` snapshot), keyed by the ledger's owner GUID, separate from the ledger
  (its schema stays 1). A damaged record is never overwritten; a newer one (`v > 1`) is
  neither read nor written.
- **The share mark is recorded when the string is built and shown,** not on copy (that
  would mean reading keys in the edit box). The nudge compares snapshots (own count,
  newest own `t`, unlocked count), never strings.
- **Refresh through `Sync`'s `onEntries` hook and after a signature:** `Book:Changed()`,
  in `pcall`, redraws only while the book shows and not on the Share page; no timer,
  and `SyncProtocol`'s rate limits bound the redraws.
- **Peer names reach a font string only through `BookView.plain`:** a name with `|`, a
  control byte or broken UTF-8 is replaced by "A traveler", never escaped. Nothing is
  formatted with data.
- **An inn page reads the newest entries only:** at most 1 000 own and 600 foreign per
  NPC ID of the group (8 IDs at most), newest first; the merged list is then trimmed to
  the same caps (the group's newest 1 000 own and 600 foreign), so a build reads at most
  8 × the caps. It renders only the 6 rows it shows.

*Rejected:* all the logic in `Book.lua` (no coverage floor, no strict environment);
scrolling frames and the tab, check box and input templates (unverified on Forever);
AceDB's `db.char` for the record (two "Mira"s on one realm would share it); the record
inside the ledger's table (a schema change; a read-only ledger couldn't store it);
comparing export strings; a timer to coalesce refreshes; escaping `|` as `||`.

*Reflected in:* `BookView.lua`, `UI/Book.lua`, `Core.lua`, `Sign.lua`, `SignFlow.lua`,
`Sync.lua`, the TOC, `.luacheckrc`, `.luacov`, `scripts/check-coverage.sh`,
`docs/architecture.md`, `docs/specs/sign.md`, `docs/specs/sync-glue.md`,
`docs/specs/export.md`, `docs/testing.md`, `docs/security-checklist.md`,
`docs/platform-forever.md`.

### 2026-10-06 — UI/Book: the parchment ledger

The maintainer chose the book's design from mockups (#106,
[specs/book.md](specs/book.md)):

1. **A two-page parchment spread in a dark frame**, four tabs at the bottom: **Inns**,
   **Collection**, **Cosmetics**, **Share**. Custom frames, core frame API only; no new
   library, no `UIDropDownMenu` / `MenuUtil` / `ScrollBox`. Escape closes it.
2. **Inns:** the left page lists inns open to your faction by continent → zone, "signed
   n of m" per zone, a filled mark for signed inns, unsigned inns listed by name, faded.
   Selecting one shows its page on the right: name, "Zone, Continent", a stamp dated by
   the first signature, count and last date, your signatures (date, phrase, seal), then
   travelers' (name, date, phrase, seal). Page turns, **no scrolling**; the list pages
   too.
3. **Collection:** "N of M inns signed", a bar per continent, zones completed, total
   signatures (weekly returns counted), travelers met (a count); the right page is a
   passport **stamp grid** per continent (paged): signed inns inked and dated, unsigned
   ones as dashed outlines with their name.
4. **Cosmetics:** quills (choose among unlocked; a default plain quill always available)
   and seals (earned ones, and locked ones with their rule and progress). **No inks**
   (above). A quill is a **flourish** under your own signatures in your book, local
   only. Every signature is written in one realistic, period-plausible ink. The chosen
   quill is a per-character saved setting; one that isn't unlocked falls back to the
   plain quill. Seals are chosen at signing, not in the book.
5. **Share:** `Core:ExportString(opted)`; the travelers box starts unticked every open;
   the string preselected in an edit box that takes its full length; no site named;
   built on open or click, never on a timer; a neutral message on failure. Keep the
   **"N new signatures since you last shared"** line, comparing data stored at share
   time. `/ledger share` opens it.
6. **First open / empty ledger:** a title page ("The ledger of <name>"), three steps for
   signing, "Open this book any time with /ledger"; on the right a "Travelers"
   explanation and **"What your ledger shares"** in the README's exact words.
7. **Opening:** `/ledger` toggles the book (the version moves to `/ledger version`;
   `/ledger debug` stays), and a **"Read the guestbook"** button at known innkeepers next
   to "Sign the guestbook" opens the book on that inn's page. No minimap button in v1.
8. **Travelers only on inn pages,** plus the count. No Travelers tab or per-traveler page
   (post-v1 *Companions*).
9. **Fonts:** the client's own (titles in a Morpheus-style font object, text in the
   standard game font). No shipped font files.
10. **Quiet updates:** built when opened; if entries arrive while it's open, the visible
    page refreshes quietly. Never on a timer.
11. All player-facing strings in one `TEXT` table; the wording, the look and the
    textures are a **DRAFT** (they ship as written until the maintainer retunes them).
    A phrase that won't render shows a neutral fallback line.

The labels "Sign the guestbook" and "Read the guestbook" and the four tab names are
settled.

*Rejected:* a Travelers tab or per-traveler pages (post-v1); a minimap button; scrolling
lists; inks.

### 2026-10-06 — No inks: one realistic ink for every signature

From the book mockups, the maintainer dropped ink color choices: "we want it to look
real or somewhat real and to role play with the technology of the times of the game".
Every signature, the player's and travelers', is written in one period-plausible ink
(#105).

- **The catalog loses inks:** 1101 Sepia, 1102 Forest-green and 1103 Midnight-blue are
  gone, and so is the `ink` kind. 1100..1199 stays reserved and is never reused. None
  had been released, so nothing is taken from anyone.
- **Quills stay,** earned as before; in the book a quill is a flourish under your own
  signatures (decided with the rest of the book, #106).
- **The first signature no longer earns anything of its own:** Sepia ink (`inns 1`) was
  the only rule meant to fire on it. The cosmetic ladder is still a DRAFT (#63).
- *Rejected:* colored inks, as anachronistic for the setting.
- Supersedes the ink parts of
  [2026-09-27 — Cosmetics: IDs, derived unlocks…](#2026-09-27--cosmetics-ids-derived-unlocks-that-are-never-taken-away-seals-on-signing)
  and the ink mention in *Cosmetics are earned by play, never paid or gated*
  ([archive](archive/decisions-2026-09.md)).

### 2026-10-06 — Phrase voices; free text stays out

The maintainer found the first composer too narrow ("a few preselected options") and
asked about free text up to ~200 characters. Free text was weighed again, including a
**private note** kept only in the player's own ledger, and the maintainer chose to stay
with canned phrases (*Canned phrases, not free text*,
[archive](archive/decisions-2026-09.md), stands). Instead the set grows **voices** (#100):

- **A voice is a temperament with its own sentence frames and connectors:** Hearthside
  (the first draft's warm tone), Bardic, Grumbler, Scholar, Rowdy, Mystic, Sailor, Noble.
  The terse and wide-eyed voices that were floated are folded into Grumbler and
  Hearthside. Voices are temperaments, never races or classes (content rule 2), and no
  voice imitates a real-world accent.
- **A voice is a UI grouping only.** Templates and conjunctions carry an optional
  `voice`; `ns.Data.PhraseVoices` names them. The grammar, `validIds`, the wire and the
  export are unchanged, and any template still takes any word, so a signature may **mix
  voices**: the composer picks a voice per line, and line 2 follows line 1's voice until
  the player picks one for it.
- **IDs:** voice 1 keeps the first draft's IDs (the beta's signatures still render);
  voice `v ≥ 2` takes a block of 30 template IDs from `201 + 30(v − 2)` (slotless from
  +20) and conjunctions `501 + 10(v − 1)`.
- **Words:** five more per category and a ninth category, **Oddities** (gentle humor such
  as "a suspicious stew"), under the same content rules.
- **Content rules gain one line:** no template pays for, buys, orders or summons its slot.
  With the Company words in the slot, a payment frame ("Paid good coin. Got {w}.") reads
  as a provider-and-service euphemism. The tripwire adds `pay paid coin coins buy bought
  chest meat mount goblin goblins worgen stool trade`. The review replaced 24 lines that
  failed in some combination (e.g. "Rhymes with {w}" invited unstated crude rhymes;
  "What is {w}" broke agreement with plural words).

*Rejected:* free text, synced or private (above); typed slots per voice (the "any word
fits" rule keeps the content argument simple); a voice stored in the entry (peers don't
need it, and it would change the wire); one voice per signature (the maintainer asked to
combine voices).

*Reflected in:* `Data/Phrases.lua`, `Phrase.lua`, `SignFlow.lua`, `Sign.lua`,
`docs/specs/phrase.md` (§3.1, §3.2, §3.5, §3.6, §9), `docs/specs/sign.md` (§3.6, §3.7,
§8), `docs/architecture.md`.

### 2026-10-05 — Sign: a pure SignFlow, the button at every known innkeeper, reasons on click, no sitting or combat check

The `Sign` slice (#96, [specs/sign.md](specs/sign.md)) settles how signing works:

- **The decisions live in a new pure module, `SignFlow`,** with a **90% coverage floor**
  (`scripts/check-coverage.sh`, like the other non-boundary pure modules): when the button
  shows, the checks and their order, the seals offered, the commit, unlock recording, the
  composer's state and the chat lines. `Sign.lua` is thin glue: events, frames, client
  reads (each hidden-value checked first) and chat output. The `SyncSchedule` split again.
- **The button shows at every innkeeper in `Data/Inns`** (that `Collection` kept), whether
  or not signing is possible right now. A click that can't sign prints one chat line with
  the reason (no ledger, read-only, signed this week with the time to the reset, not
  resting); `too_soon` is reported before `not_resting`.
- **Every check runs again at commit,** including the NPC (`changed` if the player is
  talking to someone else); a seal that stopped being allowed is refused, never dropped.
- **No sitting requirement** (the client has no query for it) and **no faction check**
  (the client already keeps players from the other faction's innkeepers).
- **No combat check:** the button and composer are unprotected frames, and signing sends
  nothing itself (`Sync`'s combat hold already covers the HELLO). `Sign.lua` stays out of
  the `combat state` allow-list of `check-apis.sh`.
- **`Core` records unlocks once at login** for a writable ledger, before `Sync` starts; an
  error there is logged and changes nothing else.
- The composer's look and every player-facing line are a **DRAFT** (all in
  `SignFlow.TEXT`); the maintainer decides them (status.md → Open questions).

*Rejected:* all the logic in `Sign.lua` with injected client functions (no coverage
floor, no strict environment); hiding or disabling the button when signing isn't possible
(a missing button reads as a bug; a disabled one needs an unverified tooltip); injecting a
gossip option into the option list (needs a hook, which is forbidden); dropdowns (the
modern menu API is unverified on Forever); checking only when the composer opens.

*Reflected in:* `SignFlow.lua`, `Sign.lua`, `Core.lua`, `scripts/check-coverage.sh`,
`.luacov`, `docs/architecture.md` (Modules, Signing flow), `docs/testing.md`,
`docs/platform-forever.md` (checklist).

### 2026-10-02 — Players sign the inn's guestbook; the AddOn keeps the name "ledger"

The maintainer saw the probe's "sign the ledger" button in the beta and asked for "sign
the guestbook". Player-facing text now uses **guestbook** for the thing you sign at an
inn: the `Sign` button reads "Sign the guestbook", the TOC `## Notes` line reads "Sign
the guestbook at every inn you rest in, and collect the signatures of travelers you meet
along the way." (this matches the download pages, which already said "guestbook"), and so
do the README tagline and the changelog. This supersedes the wording (not the two-halves
shape) of *AddOn list blurb names both halves of the AddOn* (2026-09-27).

The AddOn's name, *Innkeeper's Ledger*, stays: the ledger is the player's own book of
inns and signatures. `/ledger`, the `Ledger` module and the SavedVariables names are
unchanged.

*Rejected:* renaming the AddOn to match. The CurseForge and Wago projects already exist
under this name, and "guestbook" alone would read as a housing guestbook AddOn
([prior-art.md](prior-art.md)).

*Reflected in:* `InnkeepersLedger.toc`, `README.md`, `CHANGELOG.md`, `CLAUDE.md`,
`docs/vision.md`, `docs/architecture.md` (the `Sign` flow).

### 2026-10-01 — On a two-part client, guild keys must be two words too

From the `dev → main` release review. This extends *Two-part names key as the bare
sender form* (2026-09-30) to the guild map. That entry already skips a one-word unit name
in the group map; the guild map keyed whatever the roster gave. Now a two-part client
also skips a roster key with no space (`"First"`, `"First-<our realm>"` reduced to
`"First"`, or `"First-<other realm>"`). Both maps fail closed the same way, so a one-word
sender can't resolve to a member whose roster row lost its surname. Spec:
[specs/sync-glue.md §3.4](specs/sync-glue.md#34-sender-resolution).

The same review noted that the group map reads any one-word slot as a surname, which is
only safe while groups stay within one ruleset realm. That's now an item on #12's list
(a cross-realm or group-finder member's `UnitFullName`).

*Rejected:* holding the release for it. Both findings were low, and the guild fix is
small enough to land first.

*Reflected in:* `Sync.lua` (`rebuildGuild`), `spec/sync_names_spec.lua`,
`docs/specs/sync-glue.md` §3.4, `docs/platform-forever.md` → Verification checklist,
`docs/status.md`.

### 2026-10-01 — Distribution pages: CurseForge and Wago, no outbound links

The maintainer created both projects (#81): CurseForge `1721704` and Wago `n6VYeONd`,
both now in the TOC (`## X-Curse-Project-ID`, `## X-Wago-ID`).
- **Page text** (chosen by the maintainer): name *Innkeeper's Ledger*; summary *"Sign a
  guestbook at every inn and discover which fellow travelers have stayed there before
  you."*; the description follows the README (what it does, exactly what sync shares,
  principles), with a Blizzard trademark line. Logo: an original drawing (a timber inn
  at night, its sign an open ledger and quill), no game art. License: MIT. Third-party
  distribution allowed on CurseForge.
- **No outbound links** on either page (website, wiki, source, support and Discord left
  empty), per [addon-policy.md](addon-policy.md) rule 4, which covers distribution
  pages. **One exception:** Wago's license field requires a URL, so it points at the
  neutral MIT text (`opensource.org/license/mit`), not at the repo.
- **The Wago project is a custom addon, not linked to the GitHub repo:** uploads come
  from `release.yml` with `WAGO_API_TOKEN`, so Wago needs no access to the repo.
- **Account security:** CurseForge signs in with Google, so its second factor is the
  Google account's 2-Step Verification
  ([security-checklist.md → Before the packager lands](security-checklist.md#before-the-packager-lands-first-tag)).
  Tokens go only into the `release` environment's **secrets** (never variables); the
  first CurseForge token, entered as a plain variable in a second, unprotected
  environment, was revoked and replaced, and that environment deleted.

*Rejected:*
- **Linking the source repo from the pages:** harmless in spirit, but still a link out;
  revisit only as a deliberate exception.
- **Wago's "GitHub Addon Creation":** ties the project to the repo and may ask for
  GitHub permissions, for nothing the workflow needs.
- **Renaming the environment to `production`:** it would mean redoing the reviewer,
  tag policy and docs for no gain.

*Reflected in:* `InnkeepersLedger.toc`; `docs/security-checklist.md` → Repository
settings, Before the packager lands; `docs/status.md`.

### 2026-10-01 — The BigWigs packager, pinned; releases built and checked in CI

Settled in #81 (PR #86), carrying out *Security audit: repository hardening* (archived) for
the packager. The maintainer approved one lookup of the packager's repository for this.
- **Third-party action (checklist item 12):** `BigWigsMods/packager` **v2.6.1**, commit
  `e50a250f8705041e40f2fa1ddcb280a686d65aa0` (released 2026-09-18). It's allowed by
  that exact `owner/repo@sha` pattern; any other version needs a new entry. Reviewed at
  that commit: `action.yml` runs `setup-packager.sh` (installs pandoc only with a
  WoWInterface token, subversion only for svn externals; we have neither) and
  `release.sh`. Things that shaped the workflow: `release.sh` **sources a `.env` file**
  from the checkout (so the release check refuses one); it **builds `CHANGELOG.md` from
  commit messages** unless a manual changelog is set (ours hold links, so `.pkgmeta`
  names a hand-written `CHANGELOG.md`); it writes CRLF unless given `-u`; it replaces
  `@…@` keywords in `.lua`/`.xml`/`.toc`/`.md`/`.txt` files (LibDeflate's header has
  some), unless a path is a `plain-copy`; and `plain-copy` overrides `ignore`. It maps
  interface `16xxx` to Forever.
- **Two jobs** (`release.yml`): `package` (every PR, manual runs, `v*` tags) is a dry
  run with no secrets and a required check; `publish` (`v*` tags only) runs in the
  `release` environment (maintainer approval, tokens there only, the only job with
  `contents: write`), builds and checks once more, then uploads to CurseForge, Wago and
  a GitHub release for the tag.
- **What ships is checked byte-for-byte:** `scripts/check-package.sh` requires exactly
  the tracked files minus dotfiles and the `.pkgmeta` ignore list, every one identical
  to the checkout but the TOC, the libraries matching `Libs/MANIFEST.sha256`, and a
  `## Version` of 1..32 bytes of `[A-Za-z0-9._+-]` equal to the tag (export.md §3.5).
  Every library entry is a `plain-copy`; our own files keep their LF bytes (`-u`).
- **Tags are `vX.Y.Z`** (numbers, no leading zeros) **on a commit already on `main`**,
  and the tag is the version. `CHANGELOG.md` needs a `## vX.Y.Z` section before a tag
  passes.
- **The release check locks down the inputs** the packager trusts: `.pkgmeta` may hold
  only `package-as`, `manual-changelog` (exactly `CHANGELOG.md`, markdown), `plain-copy`
  and `ignore`, each once (no externals, no `license-output` fetch from the web, no
  second changelog); every tracked file is a plain file (a symlink would ship whatever it
  points at); no `.env`. Shipped text (README, LICENSE, CHANGELOG) carries no link or
  site name.
- **The environment approval isn't a barrier against an agent.** Agents run as the
  maintainer's account, which can push the tag and approve its own deployment. The
  stops are the agent permission guard and the `CLAUDE.md` gates; the environment makes
  each publish a deliberate, logged approval and keeps the tokens in one job. Admin
  bypass of the environment is to be turned off by the maintainer.

*Rejected:*
- **Floating `@v2`:** a moved tag upstream would change what publishes; SHA only.
- **Letting the packager write the changelog:** it would ship `Claude-Session` links and
  co-author lines in the AddOn and on the download pages (addon policy).
- **Building once and uploading that zip:** the packager can't upload a prebuilt zip.
  The publish job builds twice from the same commit and checks the first build.
- **`plain-copy: Libs`:** it ships `Libs/MANIFEST.sha256` (plain-copy beats ignore).
- **A pre-release suffix on tags (`-beta1`):** not needed for v1; one line in
  `scripts/check-release.sh` if it ever is.

*Reflected in:* `.github/workflows/release.yml`, `.pkgmeta`, `CHANGELOG.md`,
`scripts/check-release.sh`, `scripts/check-package.sh`, `Core.lua` (a comment);
`docs/security-checklist.md` → Automated, Repository settings, Before the packager lands,
item 12; `docs/libraries.md` → Vendoring and upgrades; `CONTRIBUTING.md` → Releasing;
`docs/status.md`.

---

### September 2026 (archived)

Every entry dated 2026-09-25 to 2026-09-30 is in
[archive/decisions-2026-09.md](archive/decisions-2026-09.md), unchanged apart from link
paths and still in force unless an entry above supersedes it. Titles, newest first, for
references that cite them by name:

- 2026-09-30 — One read of our own name; the name form shows in `/ledger debug`
- 2026-09-30 — A zone with no Continent above it is grouped under its World map
- 2026-09-30 — Two-part names key as the bare sender form
- 2026-09-30 — Forever beta results: modern API, two-part names, zones without continents
- 2026-09-28 — Account email settings stay as they are
- 2026-09-28 — Guild sync stays on by default; players are told what it shares
- 2026-09-28 — Published exports show other travelers only as counts
- 2026-09-28 — Security audit: repository hardening
- 2026-09-28 — Maintainer-gated content ships as a DRAFT and doesn't block merge
- 2026-09-28 — Export v1: what the draft left open
- 2026-09-27 — Collection: places, keys and faction totals
- 2026-09-27 — Cosmetics: IDs, derived unlocks that are never taken away, seals on signing
- 2026-09-27 — Phrase grammar, ID scheme and rendering
- 2026-09-27 — Phrase content rules
- 2026-09-27 — Group map details: realm form, our own name, rescan on a miss
- 2026-09-27 — Sync send: timer, clock and hold choices where the spec was silent
- 2026-09-27 — Sync receive: fail-closed choices where the spec was silent
- 2026-09-27 — Group senders resolve through our own unit scan, never `UnitGUID(sender)`
- 2026-09-27 — SyncSchedule: failed sends keep their gates; forward clock jumps wait for #12
- 2026-09-27 — Debug toggle wording: keep it as written
- 2026-09-27 — Sync glue: a pure send schedule, logical channels and a gated large reply
- 2026-09-27 — Guild HELLO interval
- 2026-09-27 — Debug log: off by default, session only, no peer strings
- 2026-09-27 — Ledger orders by bytes, keeps sorted indexes, and tightens two inputs
- 2026-09-27 — Coverage floors on pure modules, a doc-link check, and local test runs
- 2026-09-27 — Re-signing follows the game's weekly reset (supersedes the Friday 10:00 UTC entry below)
- 2026-09-27 — Re-signing an inn: once per week, resetting Friday 10:00 UTC
- 2026-09-27 — Peer-data rate limits and time window
- 2026-09-27 — Ledger storage: caps, eviction and SavedVariables shape
- 2026-09-27 — Sync wire format v1 and digest
- 2026-09-27 — AddOn list blurb names both halves of the AddOn
- 2026-09-27 — Profile site trust: showcase only, no profile key in the v1 export
- 2026-09-27 — Profile website: after v1, a separate project, reached by one paste
- 2026-09-27 — Keep the inn ledger after a pivot review
- 2026-09-27 — Sync may read combat state, and players are told
- 2026-09-26 — Security checks: forbidden-API guard on every PR, review before every release
- 2026-09-26 — CI: own toolchain install, and the library manifest pinned to the review doc
- 2026-09-26 — Scaffold conventions: embeds.xml in the manifest, pure modules enforced twice
- 2026-09-26 — Work is queued as GitHub issues written for a cold start
- 2026-09-26 — Vendor a reviewed, minimal set of libraries
- 2026-09-26 — Sync: own receive handler and codec, single messages, no compression
- 2026-09-26 — Export uses standard base64
- 2026-09-26 — Sender identity is resolved per channel; unresolved senders are dropped
- 2026-09-26 — Branch protection on `main` and `dev` (supersedes part of the branch-flow entry below)
- 2026-09-26 — Context docs as a map-driven tree
- 2026-09-26 — Autonomous build loop with maintainer gates
- 2026-09-26 — Test standard: busted + stubbed WoW API, hostile peer data
- 2026-09-26 — Branch flow: feature branches → dev → main
- 2026-09-26 — No spending without a named purchase; free beta route by default
- 2026-09-25 — Target WoW: Forever first
- 2026-09-25 — Inns only in v1
- 2026-09-25 — Canned phrases, not free text
- 2026-09-25 — Sync scope: grouped-with + guild by default; global opt-in
- 2026-09-25 — Accept only a sender's own signatures
- 2026-09-25 — Cosmetics are earned by play, never paid or gated
- 2026-09-25 — Generic, documented export string
- 2026-09-25 — Open source under MIT
