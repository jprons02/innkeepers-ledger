# Spec: `UI/Book` — the parchment ledger

> **Summary:** the book the player opens. A two-page parchment spread in a dark frame
> with four tabs (Inns, Collection, Cosmetics, Share): the inn list and each inn's page
> (your signatures, then travelers'), the collection numbers and a passport stamp grid,
> quills (a local flourish under your own signatures) and seals, and the Share page around
> `Core:ExportString`. Every decision lives in a new pure module, `BookView`, which builds
> plain page models; `UI/Book.lua` only draws them. Also: `/ledger` opens the book, a
> "Read the guestbook" button at innkeepers, quiet refresh when entries arrive, a small
> per-character SavedVariables record (chosen quill, last share), the tests and the
> in-client checks.
> **Read when:** implementing or reviewing `BookView.lua`, `UI/Book.lua`, `/ledger`'s
> commands, the Read button, the Share page or the book's SavedVariables record; changing
> what the book shows, its wording or its look.

**Status:** approved (self-approved 2026-10-06, ticket #106). The structure, tabs and
behavior follow the maintainer's decisions of 2026-10-06 (below). **Every player-facing
line ([§3.10](#310-text-draft)), the look, the layout and the textures
([§3.11](#311-uibooklua-the-glue)) are a DRAFT** the maintainer decides (a `CLAUDE.md`
gate); they ship as written until then ([decisions.md](../decisions.md) → *Maintainer-gated
content ships as a DRAFT and doesn't block merge*). The labels "Sign the guestbook" and
"Read the guestbook" and the four tab names are settled.
Amended 2026-10-07 (#110): a place the data doesn't mark complete has `TEXT.more` (DRAFT
`"+"`) after its total, and the `continent` rule's progress picks among complete
continents only ([§3.5](#35-the-collection-tab), [§3.6](#36-the-cosmetics-tab);
[collection-cosmetics.md §3.11](collection-cosmetics.md#311-completeness-marks-amended-2026-10-07-110)).
Amended 2026-10-07 (#119, self-approved; the maintainer chose to tighten): `plain` falls
back on any name that fails `Ledger.cleanText` (strictly malformed UTF-8, or a hidden
character such as a right-to-left override or a zero-width joiner)
([§3.8](#38-text-safety-and-dates);
[sync-ledger.md §5.2a](sync-ledger.md#52a-hidden-characters-in-names-amended-2026-10-07-119)).
**Security-sensitive:** yes, moderately. The book **displays other players' names and
signatures** (peer-derived data) and this slice **wires a hook into `Sync`'s receive
path** (`onEntries`) and **calls the export** with an opt-in. No wire, export or ledger
format changes. The reviewer applies security-level scrutiny to [§5](#5-security-notes)
item by item and tries hostile display data of its own.

Builds on (changes only what [§3.12](#312-changes-outside-the-book) lists):
[sync-ledger.md](sync-ledger.md) §4.4–4.5 (`own`, `innEntries`, `travelers`, `counts`,
`earned`, read-only ledgers), §5.2 (names: `Ledger.validName`, hidden values);
[sync-glue.md §3.3.1](sync-glue.md#331-the-sync-instance) (the `onEntries` hook, `nil`
until now); [phrase.md §8](phrase.md#8-contract-for-later-slices) (`render`, plain-text
display, a fallback for `nil`); [collection-cosmetics.md §8](collection-cosmetics.md#8-contract-for-later-slices)
(progress, names as plain text, cosmetics from `catalog()` / `unlocked`, a chosen quill
that isn't unlocked falls back, never hard-code an ID);
[export.md §8](export.md#8-contract-for-later-slices) (the Share window and the nudge);
[sign.md](sign.md) §3.2, §3.9 (the flow's `innAt`, the gossip button, the faction read).
Client facts: [platform-forever.md](../platform-forever.md) → *Gossip*, *Export edit box*.

**Already decided (maintainer, 2026-10-06, from mockups; settled, not reopened here).**
The orchestrator writes them into [decisions.md](../decisions.md) as one entry,
*UI/Book: the parchment ledger*:
1. A two-page parchment spread in a dark frame, four tabs at the bottom: **Inns**,
   **Collection**, **Cosmetics**, **Share**. Custom frames, core frame API only; no new
   library, no `UIDropDownMenu` / `MenuUtil` / `ScrollBox`. ESC closes it.
2. **Inns:** the left page lists inns open to your faction by continent → zone, "signed
   n of m" per zone, a filled mark for signed inns, unsigned inns listed by name, faded.
   Selecting one shows its page on the right: name, "Zone, Continent", a stamp dated by
   the first signature, count and last date, your signatures (date, phrase, seal), then
   travelers' (name, date, phrase, seal). Page turns (‹ ›), **no scrolling**; the list
   pages too.
3. **Collection:** "N of M inns signed", a bar per continent, zones completed, total
   signatures (weekly returns counted), travelers met (a count); the right page is a
   passport **stamp grid** per continent (paged): signed inns inked and dated, unsigned
   as dashed outlines with their name.
4. **Cosmetics:** quills (choose among unlocked; a default plain quill always available)
   and seals (earned ones, and locked ones with their rule and progress). **No inks**
   (#105 removes the kind). A quill is a **flourish** drawn under your own signatures in
   your book, local only. Every signature is written in **one realistic,
   period-plausible ink**. The chosen quill is a per-character saved setting; one that
   isn't unlocked falls back to the plain quill. Seals are chosen at signing, not here.
5. **Share:** `Core:ExportString(opted)` per export.md §8; the travelers box starts
   unticked every open; the string preselected in an edit box that takes its full
   length; no site named; built on open or click, never on a timer; a neutral message on
   `nil`. Keep the **"N new signatures since you last shared"** line, comparing data
   (own count, newest own `t`, unlocked count) stored at share time. `/ledger share`
   opens it.
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
11. All player-facing strings in one `TEXT` table; wording, look and textures are DRAFT.
    A phrase that won't render shows a neutral fallback line.

---

## 1. Problem

Everything under the guestbook now works in the client: players sign at an innkeeper,
the ledger keeps their entries and the ones travelers share, `Collection` and
`Cosmetics` compute the passport, and `Export` builds the share string. But nothing shows
any of it. `UI/Book.lua` is a 5-line stub, `/ledger` only prints a version, and a player
who signs sees one chat line and then nothing: no list of inns, no page where a
stranger's signature turns up, no stamps, no seals, no way to copy the export. The
vision's feel ("a book, not a list... something you *open*") lives or dies here. This
slice builds the book the maintainer chose from mockups: four tabs on a parchment spread,
inn pages that carry the crossing-paths moment, the collection as a passport, quills as a
flourish of your own hand, and the Share page, all from data the other modules already
compute, with every peer-derived string shown as plain, bounded text.

## 2. Scope

**In:**
- `BookView.lua` (new, **pure**): navigation, every page model, text safety, dates, the
  quill fallback and flourish, the share snapshot and nudge, the saved record's read and
  write shapes, and the `TEXT` table ([§3.2](#32-bookview-api)–[§3.10](#310-text-draft)).
- `UI/Book.lua` (glue): the frame, pages, tabs and widgets; client reads with hidden-value
  checks; drawing models; ESC; the Share page's edit box and checkbox; the saved record;
  `Book:Changed()` ([§3.11](#311-uibooklua-the-glue)).
- Small changes elsewhere ([§3.12](#312-changes-outside-the-book)): `Core` (`/ledger`
  commands, `Core:PlayerName()`), `Sign.lua` (the Read button, `Book:Changed()` after a
  signature), `Sync.lua` (`onEntries` → `Book:Changed()`), `SignFlow.TEXT` (the Read
  label).
- Wiring: TOC, `load.PURE`, `.luacov`, `check-coverage.sh` (90%), `.luacheckrc` globals,
  stub additions, specs ([§6](#6-test-plan)), docs ([§4.3](#43-docs-the-implementer-updates)).

**Out:**
- A Travelers tab, a per-traveler page, "people I've traveled with" (post-v1
  *Companions*; scope guard). Travelers appear only on inn pages and as a count.
- Inks of any kind (#105), choosing a seal in the book (seals are chosen in `Sign`'s
  composer), announcing earned cosmetics.
- A minimap button, a key binding (forbidden API), a movable or resizable book, saved
  window position, scrolling lists, search or filters, sorting options.
- Any change to the wire format, `SyncProtocol`, `Ledger`, `Phrase`, `Collection`,
  `Cosmetics`, `Export`, the export format, or the ledger's SavedVariables schema.
- Import or any decoder (export.md: none ships).
- Localization (English DRAFT text, like phrases and places), camps, a "home inn".
- Inns not open to your faction in the list (an inn page still opens for one through the
  Read button, [§3.4](#34-the-inns-tab)).
- The composer's look and the list-style composer (#102).

## 3. Approach

### 3.1 Pieces and load order

| Piece | Kind | Holds |
|---|---|---|
| `BookView.lua` | **pure** (new) | every decision: what each page shows, paging, ordering, text safety, dates, flourishes, the quill fallback, the share nudge, the saved record's shapes, `TEXT` |
| `UI/Book.lua` | glue | the frames, the client reads, drawing models, ESC, the edit box and checkbox, writing the saved record, `Book:Changed()` |
| `Core.lua` | glue | `/ledger` commands; `Core:PlayerName()` |
| `Sign.lua` | glue | the "Read the guestbook" button; `Book:Changed()` after `"added"` |
| `Sync.lua` | glue | `onEntries` in `realDeps` calls `Book:Changed()` |

- **TOC:** `BookView.lua` goes after `SignFlow.lua`, at the end of the pure block (it
  asserts `ns.Ledger` at load; everything else comes through `BookView.new`'s `deps`).
  `UI\Book.lua` stays last. `load.PURE` gains `{ path = "BookView.lua", name =
  "BookView" }`; `.luacov` includes `"BookView$"`; `scripts/check-coverage.sh` gets
  `BookView.lua 90`.
- **Why a pure module:** the `SignFlow` split again (sign.md §3.1). Ordering, paging,
  bounds, text safety and the fallbacks are exactly what needs exact tests and a coverage
  floor; `Book.lua` is left with frames and client reads, tested through the stub.
- `BookView` never reads `ns` after load and never calls a WoW function: client values
  arrive in the situation `s`, the ledger is passed in, and `Collection`, `Phrase` and
  `Cosmetics` come through `deps`.

### 3.2 `BookView` API

`BookView.new(deps)` returns a **view**. `deps = { inns, atlas, phrase, cosmetics, sizes? }`:
- `inns`: the `Data/Inns` table (`ns.Data.Inns`), read once to index each inn's NPC IDs;
- `atlas`: a `Collection` atlas (needs `progress`, `innOf`, `inn`, `zone`, `continent`);
- `phrase`: a `Phrase` set (needs `render`);
- `cosmetics`: a `Cosmetics` set (needs `catalog`, `unlocked`, `info`);
- `sizes` (optional, for tests): any of `listRows`, `innRows`, `barRows`, `stampCells`,
  `quillRows`, `sealRows`, each an integer in 3..50; anything else keeps the default of
  [§3.9](#39-bounds-and-readiness).

A missing table or function raises (a caller bug, like `SignFlow.new`). The real view is
`BookView.new({ inns = ns.Data.Inns, atlas = ns.Collection.atlas, phrase = ns.Phrase,
cosmetics = ns.Cosmetics })`, built by `Book.lua` at load inside `pcall`.

**The inn index (built once in `new`):** for every key `k` of `inns` (raw `next`, at most
`innsReadMax` keys, our own shipped data) with `atlas.innOf(k) ~= nil`, `k` joins the
group of `p = atlas.innOf(k)`. Each group is sorted ascending and holds at most
`aliasesMax` NPC IDs (the primary is always kept, since `innOf(p) == p`; extra aliases
past the cap are dropped). The **place tree** is built at the same time: the kept
primary inns grouped by zone (`atlas.inn(p).zone`) and zones by continent
(`atlas.zone(z).continent`); continents, zones and inns each ordered by **name in byte
order** (compared byte by byte, never Lua's string `<`), ties by key.

**The situation** `s` is what the glue read, already hidden-checked
([§3.11.2](#3112-client-reads)):
`{ ledger, faction, name, offset, quill, shared, prefsWritable }`, where `ledger` is
`ns.ledger` or `nil`; `faction` is `"Alliance"`, `"Horde"` or `nil`; `name` the
player's display name or `nil`; `offset` the client's UTC offset in seconds (`0` if
unknown); `quill` and `shared` the saved record's fields ([§3.7](#37-the-share-tab-and-the-saved-record));
`prefsWritable` whether the record can be written.

| Function | Returns |
|---|---|
| `view.build(s, nav)` | the **model** of both pages for the navigation `nav` ([§3.3](#33-navigation-and-the-model)) |
| `view.innKey(npc)` | the primary inn key for an NPC ID (`atlas.innOf`), or `nil` |
| `view.effectiveQuill(quill, unlocked)` | the quill to draw with: `quill` if it is a quill in the `unlocked` list, else `0` (the plain quill) ([§3.6](#36-the-cosmetics-tab)) |
| `BookView.snapshot(own, unlocked)` | `{ own = n, newest = t?, unlocked = n }` ([§3.7](#37-the-share-tab-and-the-saved-record)) |
| `BookView.nudge(stored, current)` | the nudge line or `nil` ([§3.7](#37-the-share-tab-and-the-saved-record)) |
| `BookView.readPrefs(rec)` | `{ quill, shared, writable }` ([§3.7](#37-the-share-tab-and-the-saved-record)) |
| `BookView.prefsRecord(quill, shared)` | a fresh v1 record ([§4.1](#41-savedvariables-the-books-record)) |
| `BookView.plain(s, maxBytes, fallback)` | safe display text ([§3.8](#38-text-safety-and-dates)) |
| `BookView.dateText(t, offset)` | `"5 October 2026"`, or `nil` ([§3.8](#38-text-safety-and-dates)) |
| `BookView.TEXT`, `BookView.LIMITS`, `BookView.FLOURISHES` | copies of the constants ([§3.9](#39-bounds-and-readiness), [§3.10](#310-text-draft), [§3.6](#36-the-cosmetics-tab)) |

Every view and module function **never throws** on any argument: each runs its body in
`pcall` and returns its failure value (`build` → `{ tab = "inns", nav = <the default
nav>, error = true }`; others `nil`, `0`, `{}` or the fallback). Arguments are read with
type checks first; numbers pass the integer-and-range test (`NaN`, `inf` and fractions
fail). Caller tables (`s`, `nav`, everything the ledger returns) are read with `rawget`
and bounded loops; nothing is written to them.

### 3.3 Navigation and the model

**`nav`** is the glue's state: `{ tab, listPage, inn, innPage, barPage, stampPage,
quillPage, sealPage }`. `build` normalizes it and returns the result as `model.nav`
(the glue stores that, so a clamped page stays clamped):
- `tab` is one of `"inns"`, `"collection"`, `"cosmetics"`, `"share"`; anything else →
  `"inns"`.
- `inn` must be a primary key with `atlas.inn(inn) ~= nil`; anything else → `nil`.
- `listPage` is an integer in `0..pages` (page 0 is the title page). `nil` (or a bad
  value) means **default**: the list page holding `inn` if `inn` is set and listed; else
  `0` if the ledger has no own entries (or there is no ledger); else `1`.
- Every other page is an integer in `1..pages`; a bad value → `1`; past the end → the
  last page.

**The model:** `{ tab, nav, notice?, left = <page>, right = <page> }`. `notice` is
`TEXT.noLedger` when `s.ledger` isn't a table, `TEXT.readOnly` when the ledger is
read-only, else absent. Each page is a table with a `kind` and, when it pages,
`page` and `pages` (the glue enables ‹ when `page` is above the first page and › when
it is below `pages`). Every string in a model is our own constant, our allow-listed data,
a number, a date from `dateText`, or a peer name that passed `plain`.

| Tab | `left.kind` | `right.kind` |
|---|---|---|
| `inns` | `"title"` (list page 0) or `"list"` | `"inn"` if `nav.inn` is set, else `"help"` |
| `collection` | `"summary"` | `"stamps"` |
| `cosmetics` | `"quills"` | `"seals"` |
| `share` | `"share"` | `"shareInfo"` |

**No ledger or a read-only one:** with no ledger, everything that reads it acts on an
empty ledger (no own or foreign entries, counts 0, nothing unlocked) and the notice
says why; the list, places and stamps still show (all unsigned). A read-only ledger is
shown in full (its queries answer from the normalized copy, sync-ledger.md §4.3); only
the notice differs.

### 3.4 The Inns tab

**Progress** for this tab and the next: `p = atlas.progress(own, s.faction)` with
`own = ledger:own()` (or `{}`).

**`title`** (list page 0): `{ kind = "title", title, steps = { s1, s2, s3 }, hint, page =
0, pages = <list pages> }`. `title` = `TEXT.titleOf .. name` when `plain(s.name, 64)`
gives a name, else `TEXT.titleNoName`. The title page is always the list's first page,
so › turns to the list and ‹ on list page 1 turns back to it; it opens by default only
when there are no own entries.

**`help`** (right, no inn selected): `{ kind = "help", travelersTitle, travelersText,
sharesTitle, sharesText }`, all from `TEXT`. `TEXT.sharesText` is the README's sentence
([README.md](../../README.md) → Principles → *What sync shares*) **word for word** after
"What sync shares: ", with only its first letter capitalized; a test compares the two
([§6.2](#62-specbook_view_speclua-pure-strict-environment)), so they can't drift.

**`list`** (pages 1..n): rows, in place-tree order, of only what is open to the faction:
- for each continent in `p.byContinent`: `{ kind = "continent", text = <name>, sub =
  signed .. TEXT.of .. total }`;
- for each of its zones in `p.byZone`: `{ kind = "zone", text = <name>, sub =
  TEXT.signedPrefix .. signed .. TEXT.of .. total }` ("signed 1 of 2");
- for each of the zone's inns with `p.inns[key].open`: `{ kind = "inn", key, text =
  <name>, signed = count >= 1, faded = count == 0, selected = key == nav.inn }`.

A continent or zone row whose progress item isn't `complete` gets `TEXT.more` after its
total, as in [§3.5](#35-the-collection-tab) (#110).

Paging: at most `listRows` rows per page. **A page never starts mid-group without its
headers:** when a page's first row would be a zone or inn row, the page begins with its
continent's header (and, before an inn row, its zone's header) repeated with `cont =
true`; repeated headers count toward `listRows`. Pages are filled greedily in order, so
the result depends only on the data. With no open inn at all, one list page holds no
rows and `empty = TEXT.noInns`.

**`inn`** (right): for `key = nav.inn`:
```lua
{ kind = "inn", key = key,
  title = <inn name>, place = <zone name> .. ", " .. <continent name>,
  stamp = { signed = bool, date = dateText(first) or nil },
  countText = <"Signed 3 times" | "Signed once" | TEXT.notSigned>,
  lastText = TEXT.lastSigned .. dateText(last)  -- only when count >= 2
  rows = { ... }, page = n, pages = m }
```
`count`, `first`, `last` are `p.inns[key]`'s (entries at aliases included). The row
sequence is:
1. `{ kind = "heading", text = TEXT.yours }`;
2. the own entries at every NPC ID in the inn's group, **newest first** (`t` descending,
   then NPC ID ascending): `{ kind = "own", date, text, seal?, flourish? }`; or, when
   there are none, `{ kind = "note", text = TEXT.noOwn }`;
3. `{ kind = "heading", text = TEXT.travelers }`;
4. the foreign entries at every NPC ID of the group, newest first (`t` descending, then
   signer GUID in byte order, then NPC ID): `{ kind = "foreign", name, date, text, seal?
   }`; or `{ kind = "note", text = TEXT.noForeign }`.

Paging: at most `innRows` rows per page; a page whose first row would be an entry row
begins with its section's heading repeated (`cont = true`, counted). **Only the rows of
the requested page are rendered:** `render`, `dateText`, `plain` and the seal lookup run
for at most `innRows` rows per build; the page count comes from the row count alone.

Per row:
- `date = dateText(e.t, s.offset)`; `text = phrase.render(e.phrase)`, or
  `TEXT.faded` when it returns anything but a string (a phrase ID set that no longer
  renders after a data change).
- `seal`: if `e.seal` is set, `info = cosmetics.info(e.seal)`; a `"zone"` rule gives
  `info.name .. TEXT.zoneSealSuffix` ("Zephras Isle seal"), any other seal `info.name`
  ("Wayfarer's seal"), and an unknown ID `TEXT.aSeal`. The line reads `TEXT.sealedWith ..
  <label>`.
- `name` (foreign): `plain(rec.name, LIMITS.nameBytes, TEXT.aTraveler)`.
- `flourish` (own): `FLOURISHES` entry for the effective quill ([§3.6](#36-the-cosmetics-tab)),
  absent for the plain quill.

**Reading the ledger for a page** (bounded, [§3.9](#39-bounds-and-readiness)): for each
NPC ID of the group, `ledger:innEntries(id)` inside `pcall`; from its result, `own` and
`foreign` are read **newest first**: the ledger returns both oldest first, so each list is
read with `rawget(t, i)` from its raw length `#t` down, at most `ownReadMax` own and
`foreignReadMax` foreign items **per NPC ID** (a table's `#` runs no metamethod in Lua
5.1). An item is used only if it is a table whose entry passes `Ledger.validEntry`
(foreign: `rawget(item, "entry")`) and, for a foreign item, whose `signer` is a string;
others are skipped. The items of the whole group are then merged, sorted newest first
and **trimmed to the same caps**, so the oldest are dropped and the page holds the newest
`ownReadMax` own and `foreignReadMax` foreign entries of the group. A build reads at most
`aliasesMax` (8) × the caps.

**Selecting:** an inn row's click sets `nav.inn = key, innPage = 1`. A key whose inn the
atlas doesn't keep normalizes to `nil`, and the right page shows `help`.

### 3.5 The Collection tab

**`summary`** (left):
```lua
{ kind = "summary",
  signedText = p.signed .. TEXT.of .. p.total .. TEXT.innsSigned,  -- "4 of 4 inns signed"
  zonesText = TEXT.zonesDone .. <zones with done> .. TEXT.of .. <zones in byZone>,
  signaturesText = TEXT.signatures .. counts.own,  -- every own entry, weekly returns counted
  travelersText = TEXT.travelersMet .. counts.travelers,
  bars = { { name, signed, total, fraction, text = signed .. TEXT.of .. total }, ... },
  page = n, pages = m }
```
`counts = ledger:counts()` (zeros without a ledger or on a bad answer; each count an
integer in `0..10^7`, else 0). `bars` holds one item per continent in `p.byContinent`,
in place-tree order, `fraction = signed / total` (always `total >= 1` there), at most
`barRows` per page. With `p.total == 0`: no bars and `empty = TEXT.noInns`.

**Places not known in full (#110, [collection-cosmetics.md
§3.11](collection-cosmetics.md#311-completeness-marks-amended-2026-10-07-110)):** wherever
the book prints `signed .. TEXT.of .. total` for a place whose progress item (or `p`
itself, for the inns line) isn't `complete`, the total is followed by `TEXT.more` (DRAFT
`"+"`): "1 of 1+ inns signed", a bar's "3 of 3+", a list row's "signed 1 of 1+", and the
rule progress of §3.6. `zonesText` counts zones with `done`, so an unmarked zone never
counts as completed.

**`stamps`** (right): the open inns in place-tree order, **each continent starting a new
page**, at most `stampCells` cells per page:
`{ kind = "stamps", title = <continent name>, cells = { { key, name, signed, date? } },
page, pages }`; `date = dateText(first)` for a signed inn. No open inn → one page with
`empty = TEXT.noInns`. A cell's click opens that inn's page on the Inns tab
(`nav = { tab = "inns", inn = key }`, list page by default).

### 3.6 The Cosmetics tab

`u = cosmetics.unlocked(own, s.faction, ledger:earned())` (or `{}`), read with `rawget`
up to `catalog()`'s length + 1; `cat = cosmetics.catalog()`. Only the kinds `"quill"`
and `"seal"` are shown; a record of any other kind is ignored (defense: #105 removes
inks, and a later kind needs its own spec).

**The effective quill** (`view.effectiveQuill(quill, u)`): `quill` if it is an integer,
`cosmetics.info(quill).kind == "quill"`, and an item of `u` has `id == quill`; otherwise
`0`, the plain quill. So a saved ID that is unknown, not unlocked yet, a seal, `NaN` or
junk draws with the plain quill, and the saved value is left as is (it becomes valid
once earned). The book never hard-codes a quill ID.

**Flourishes (DRAFT look):** `FLOURISHES` is an array of short ASCII strings (§3.10). A
quill's flourish is `FLOURISHES[((r - 1) % #FLOURISHES) + 1]`, where `r` is its rank
among the catalog's quills by ID ascending; the plain quill has none. Every own row is
drawn with the effective quill's flourish under its text, past signatures included (it
is your book's look, never stored on an entry, never sent).

**`quills`** (left): rows, the plain quill first (`id = 0`), then every catalog quill
by ID: `{ id, name, unlocked, chosen, canUse, status }`, at most `quillRows` per page.
- `chosen`: `id == effective quill`. `canUse`: `unlocked and not chosen and
  s.prefsWritable`.
- `status`: chosen → `TEXT.inUse`; the plain quill otherwise → `TEXT.alwaysYours`;
  unlocked → `TEXT.earnedOn .. dateText(t)`; locked → `<rule text> .. TEXT.dot ..
  <progress>`.

**`seals`** (right): `{ kind = "seals", hint = TEXT.sealHint, rows, page, pages }`; rows
for every catalog seal by ID (milestone seals, then zone seals), **except a zone seal
that is neither unlocked nor for a zone in `p.byZone`** (another faction's zone: it
can't be earned, so it isn't dangled): `{ id, name = <label as in §3.4>, earned, status
}`, `status` = `TEXT.earnedOn .. date` or `<rule text> .. TEXT.dot .. <progress>`, at
most `sealRows` per page.

**Rule text and progress** (locked items), capped so progress never reads past its
goal:

| Rule | Text | Progress |
|---|---|---|
| `inns n` | `TEXT.ruleInns1 .. n .. TEXT.ruleInns2` ("Sign 10 inns") | `min(p.signed, n) .. TEXT.of .. n` |
| `zones n` | `TEXT.ruleZones1 .. n .. TEXT.ruleZones2` | `min(<zones done>, n) .. TEXT.of .. n` |
| `continent` | `TEXT.ruleContinent` | the continent nearest done (largest `signed / total`, then more `signed`, then smaller key): `signed .. TEXT.of .. total`; none → `0 .. TEXT.of .. 1` |
| `all` | `TEXT.ruleAll` | `p.signed .. TEXT.of .. p.total` |
| `zone z` | `TEXT.ruleZone .. <zone name>` | `p.byZone[z].signed .. TEXT.of .. total` |

So the maintainer's example reads "Sign 10 inns · 4 of 10".

**Amended 2026-10-07 (#110):** the `continent`, `all` and `zone z` progress follow the
total with `TEXT.more` when the place (or `p`) isn't `complete` ("Sign every inn in
Vale · 2 of 2+"). The `continent` rule's nearest-done continent is chosen **among
complete continents only** (only those can earn it); none → `0 .. TEXT.of .. 1`, as
before. `inns n` and `zones n` are unchanged.

### 3.7 The Share tab and the saved record

**`share`** (left): `{ kind = "share", title = TEXT.shareTitle, help = TEXT.shareHelp,
include = TEXT.include, nudge = BookView.nudge(s.shared, current) }` with `current =
BookView.snapshot(own, u)`. **`shareInfo`** (right): `{ kind = "shareInfo", title =
TEXT.shareInfoTitle, text = TEXT.shareInfoText }`. The string itself is the glue's
([§3.11.6](#3116-the-share-page)): the model never holds it.

**`BookView.snapshot(own, unlocked)`**: `own` = the number of own entries (read with
`rawget` up to `Collection.LIMITS.ownMax`), `newest` = the largest valid `t` among them
(absent when there are none), `unlocked` = the number of items in `unlocked` (bounded
the same way). Non-tables count as empty.

**`BookView.nudge(stored, current)`**, `stored` and `current` snapshots (or anything):
- `stored` not a valid snapshot (missing, junk, a field out of range) → `nil`: never
  shared, so no line.
- equal (`own`, `newest`, `unlocked` all equal) → `TEXT.nothingNew`;
- `current.own > stored.own` → `n = current.own - stored.own`: `TEXT.newOne` for 1, else
  `n .. TEXT.newMany` ("3 new signatures since you last shared.");
- anything else that differs (an unlock alone; fewer own entries after a quarantine) →
  `TEXT.changed`.

Data is compared, never strings (export.md §3.2: bytes aren't stable).

**The saved record** (shape and migration: [§4.1](#41-savedvariables-the-books-record)):
`BookView.readPrefs(rec)` → `{ quill, shared, writable }`:
- `rec == nil` → `{ writable = true }` (nothing saved yet).
- `rec` not a table → `{ writable = false }` (damaged; never overwritten, so nothing is
  deleted).
- `rawget(rec, "v")` an integer above 1 → `{ writable = false }` (a newer AddOn wrote
  it; read nothing, write nothing).
- `v == 1`: `quill` kept if an integer in `1..cosmeticIdMax`; `shared` kept if a table
  with `own` an integer in `0..ownMax`, `unlocked` in `0..cosmeticIdMax`, and `newest`
  absent or a time (`tMin..tMax`), and `newest` absent exactly when `own == 0`; each
  field that fails is `nil`. `writable = true`.
- any other `v` (missing, `0`, a string) → `{ writable = true }` with no fields (a
  broken v1 record is replaced by the next write).

`BookView.prefsRecord(quill, shared)` → `{ v = 1, quill = <if an integer 1..cosmeticIdMax>,
shared = <a fresh copy of a valid snapshot> }`, nothing else.

### 3.8 Text safety and dates

**`BookView.plain(s, maxBytes, fallback)`** is the one gate for peer-derived display text
(travelers' names) and the player's own name.

**Amended 2026-10-07 (#119):** step 2 runs `Ledger.cleanText` on the whole input, so
`plain` refuses everything the name rule refuses: strictly malformed UTF-8 (RFC 3629;
the old structural check let overlongs, surrogates, code points above U+10FFFF and the
C1 controls `C2 80..9F` through) and every hidden code point (non-ASCII spaces, format
and bidi controls such as a right-to-left override, zero-width characters, invisible
fillers, variation selectors, private use, noncharacters). The one table of banned code
points lives in
[sync-ledger.md §5.2a](sync-ledger.md#52a-hidden-characters-in-names-amended-2026-10-07-119).

1. `s` not a string, or empty → `fallback`.
2. `Ledger.cleanText(s)` isn't `true` → `fallback`. Checked on the **full** input,
   before any cut, so a hidden character past `maxBytes` still replaces the whole name
   rather than leaving a clean-looking prefix. This covers every byte `< 32` and `127`,
   malformed UTF-8 (a lone or missing continuation byte, `C0`, `C1`, `F5..FF`, a
   truncated sequence, an overlong, a surrogate, anything above U+10FFFF) and the hidden
   code points. `BookView` reads `Ledger.cleanText` once at load, like `validEntry`, and
   asserts it is a function.
3. Any `|` (124) → `fallback`. **Never escaped** (no `||`): a name that holds a UI
   escape is replaced, not repaired.
4. Longer than `maxBytes` → cut at `maxBytes`, back off to the start of the last
   complete character, append `"..."`. Step 2 has already proved the structure, so the
   byte loop needs only each lead byte's length (`< 0x80` 1, `< 0xE0` 2, `< 0xF0` 3,
   else 4) and step 3's `|` test; drop the failure branches step 2 makes unreachable
   rather than leave them uncovered.
5. Else `s` unchanged.

Checks use `string.byte` and plain comparisons only (no patterns over the data, never
`%a`/`%w`), and `fallback` itself is our constant.

**Is extra escaping needed?** No. Every traveler name in the ledger already passed
`Ledger.validName` on the way in (`addForeign`) and again at load (`normalize`), and that
rule rejects `|`, control bytes and `\127` (`[%z\1-\31\127|]`), malformed UTF-8 and
hidden characters (`Ledger.cleanText`, #119), caps names at 96 bytes,
and allows only letters, UTF-8 bytes, one space and a realm suffix. Inn, zone, continent
and cosmetic names pass `Collection`'s allow-list (no `|`, no `%`), phrase text passes
`Phrase`'s, dates and numbers are ours. `plain` is defense in depth (a tampered
SavedVariables file, a future code path) and the byte cap bounds layout. **Nothing is
ever passed through `string.format`, `SetFormattedText` or a `gsub` replacement**; lines
are built by concatenation with our constants.

**`BookView.dateText(t, offset)`**: `t` must be an integer in `tMin..tMax`, else `nil`.
`offset` an integer in `-50400..50400` (UTC−14 h..+14 h), else `0`. The local day is
`floor((t + offset) / 86400)`, turned into a civil date with integer arithmetic only
(the days-to-civil algorithm: `z = days + 719468`, era of 146097 days, year of era,
day of year, month from `(5 * doy + 2) / 153`), and written `day .. " " ..
TEXT.months[m] .. " " .. year` ("5 October 2026"). No time of day is shown (DRAFT). The
glue measures `offset` ([§3.11.2](#3112-client-reads)); the module never reads a clock.

### 3.9 Bounds and readiness

`BookView.LIMITS` (a copy; `tMin`, `tMax`, `cosmeticIdMax` are read from
`Ledger.LIMITS`, `ownMax` from `Collection.LIMITS`, not repeated):

| Limit | Value | Bounds |
|---|---|---|
| `listRows` | 16 | rows per list page |
| `innRows` | 6 | rows per inn page (so ≤ 6 renders per build) |
| `barRows` | 6 | continent bars per summary page |
| `stampCells` | 12 | stamps per page (3 × 4) |
| `quillRows` | 6 | quill rows per page |
| `sealRows` | 7 | seal rows per page |
| `ownReadMax` | 1 000 | own entries read per NPC ID of an inn's group (newest first), and kept for the page after the merge |
| `foreignReadMax` | 600 | foreign entries read per NPC ID of an inn's group (newest first), and kept for the page after the merge (4 × the ledger's per-inn cap of 150) |
| `aliasesMax` | 8 | NPC IDs per inn group |
| `innsReadMax` | 20 000 | `Data/Inns` keys read at `new` |
| `nameBytes` | 64 | display bytes of a name |

- **Work per build** is bounded by these and by what `Collection` and `Cosmetics`
  already bound (`progress` reads at most `ownMax` entries; `unlocked` at most the
  catalog). A build computes only the current tab: the Inns tab reads `own()`,
  `progress` and one inn group's `innEntries`; Collection reads `own()`, `progress`,
  `counts()`; Cosmetics reads `own()`, `unlocked`, `catalog()`; Share reads `own()` and
  `unlocked`.
- **The atlas isn't ready** (no inn data, or `bind` excluded everything): the list,
  bars and stamps are empty with `TEXT.noInns`; the inn index is empty, so the Read
  button's inn (if any) normalizes to `nil` and the help page shows. Nothing raises.
- **The ledger isn't ready** (the GUID retry at login, or none this session): the
  notice of [§3.3](#33-navigation-and-the-model); the Share page gets `nil, "no_ledger"`
  from `ExportString` and shows the neutral line; quill choice is off
  (`prefsWritable = false`, since the record is keyed by the ledger's GUID).
- **Read-only ledger:** displayed in full with the notice; the record (separate from the
  ledger) stays writable; the export works (export.md §3.7).

### 3.10 `TEXT` (DRAFT)

**Every line is the maintainer's to decide.** One table, `BookView.TEXT`, our constants
only: no `|`, no `%`, no site, product, service or URL. Lines are joined by
concatenation. Three glyphs are outside ASCII and need the in-client check
([§8](#8-in-client-checks-for-12) item 3): `‹` `›` (U+2039, U+203A) and `·` (U+00B7),
written as UTF-8 byte escapes in the source.

| Key | Text (DRAFT) |
|---|---|
| `tabInns`, `tabCollection`, `tabCosmetics`, `tabShare` | `Inns`, `Collection`, `Cosmetics`, `Share` (settled) |
| `prev`, `next`, `close` | `‹`, `›`, `Close` |
| `titleOf`, `titleNoName` | `The ledger of `, `Your ledger` |
| `step1` | `1. Find an innkeeper, the one who keeps your hearthstone, and talk to them.` |
| `step2` | `2. Rest at the inn and choose Sign the guestbook.` |
| `step3` | `3. Choose your words and sign. Each guestbook takes your signature once a week.` |
| `hint` | `Open this book any time with /ledger.` |
| `travelersTitle` | `Travelers` |
| `travelersText` | `When you group with other travelers who keep a ledger, or share a guild with them, your books quietly trade signatures. Theirs appear on each inn's page, under your own.` |
| `sharesTitle` | `What your ledger shares` |
| `sharesText` | `Your own newest signatures (up to 40), each with its inn, the date and time you signed, your phrase and your seal. It goes to your group and your guild, so guildmates who use the AddOn can see where and when you signed. Nothing else about you is sent: no location, chat, gear or play time beyond those signatures.` (the README's words; tested) |
| `of`, `signedPrefix`, `innsSigned` | ` of `, `signed `, ` inns signed` |
| `more` | `+` (after the total of a place the data doesn't know in full; #110) |
| `notSigned`, `signedOnce`, `signedTimes1`, `signedTimes2`, `lastSigned` | `Not signed yet`, `Signed once`, `Signed `, ` times`, `Last signed ` |
| `yours`, `travelers` | `Your signatures`, `Travelers' signatures` |
| `noOwn`, `noForeign` | `You haven't signed this guestbook yet.`, `No traveler you've met has signed here yet.` |
| `faded` | `The ink here has faded.` (a phrase that won't render) |
| `aTraveler`, `aSeal`, `sealedWith`, `zoneSealSuffix` | `A traveler`, `a seal`, `Sealed with `, ` seal` |
| `zonesDone`, `signatures`, `travelersMet` | `Zones completed: `, `Signatures: `, `Travelers met: ` |
| `noInns` | `No inns are known yet.` |
| `quillsTitle`, `sealsTitle`, `plainQuill` | `Quills`, `Seals`, `Plain quill` |
| `inUse`, `alwaysYours`, `use`, `earnedOn`, `dot` | `In use`, `Always yours`, `Use`, `Earned `, ` · ` |
| `sealHint` | `Choose a seal when you sign a guestbook.` |
| `ruleInns1`, `ruleInns2`, `ruleZones1`, `ruleZones2` | `Sign `, ` inns`, `Complete `, ` zones` |
| `ruleContinent`, `ruleAll`, `ruleZone` | `Sign every inn on one continent`, `Sign every inn open to you`, `Sign every inn in ` |
| `shareTitle` | `Share your ledger` |
| `shareHelp` | `Copy this text to keep a copy of your ledger or to share it.` |
| `include` | `Include travelers' signatures` |
| `shareFail` | `Your ledger can't be shared right now.` |
| `nothingNew`, `newOne`, `newMany`, `changed` | `Nothing new since you last shared.`, `1 new signature since you last shared.`, ` new signatures since you last shared.`, `Your ledger has changed since you last shared.` |
| `shareInfoTitle` | `What the text holds` |
| `shareInfoText` | `Your signatures, the inns you've collected and the cosmetics you've earned. Other travelers' signatures are theirs: they're left out unless you tick the box.` |
| `noLedger` | `Your ledger isn't open yet. Try again in a moment.` |
| `readOnly` | `This ledger is read-only (saved by a newer version, or damaged). You can read it, but nothing new is written.` |
| `pageError` | `This page can't be read right now.` |
| `cantOpen` | `The ledger can't be opened right now.` |
| `months` | `January` … `December` (an array) |

**`FLOURISHES` (DRAFT look):** `{ "~ ~ ~", "-~-~-~-", "~*~*~", "=~=~=" }`, all ASCII, no
`|` or `%`.

**The ink:** one color for every signature and line of handwriting-style text, yours and
travelers' alike, **iron-gall ink**, `INK = { 0.20, 0.13, 0.08 }` (a dark brown-black);
faded text (unsigned inns, locked items) is `INK` at alpha `0.45`; stamps use **stamp
ink**, `STAMP = { 0.55, 0.16, 0.12 }` (a muted red-brown). Both are glue constants
(DRAFT look), never stored or sent.

### 3.11 `UI/Book.lua`: the glue

#### 3.11.1 Frames and the look (DRAFT)

Core frame API only: `CreateFrame` (`Frame`, `Button`, `CheckButton`, `EditBox`),
`CreateFontString`, `CreateTexture`, `UIPanelButtonTemplate` (verified in the beta). No
backdrop template, no tab or check box templates, no dropdowns, menus, scroll frames or
`ScrollBox`. Everything is built once, on the first open, and hidden or filled after
that.

- **The book:** `CreateFrame("Frame", "InnkeepersLedgerBook", UIParent)`, about 860 × 560,
  `CENTER` of `UIParent`, strata `HIGH`, mouse enabled, clamped to the screen, not
  movable. **Its global name is the AddOn's only global** (UISpecialFrames needs a name,
  §3.11.4). Hidden by default.
- **Layers:** the dark frame (a texture over the whole book); two pages inset 16 px,
  each about 404 × 500, with a parchment texture; a narrow spine shadow between them;
  four border lines of `STAMP`-tinted color texture around each page are optional
  (DRAFT).
- **Tabs:** four `UIPanelButtonTemplate` buttons, about 120 × 24, in a row under the
  book (`TOPLEFT` at the book's `BOTTOMLEFT` + 24, −2); the current tab's button is
  `Disable()`d to mark it (no tab template).
- **Close:** a small `UIPanelButtonTemplate` button labeled `TEXT.close` at the book's
  top right.
- **Page turns:** each page has a ‹ and a › `UIPanelButtonTemplate` button (26 × 22) at
  its bottom corners and a centered page label (`n / m`, numbers only), each enabled
  from the model ([§3.3](#33-navigation-and-the-model)).
- **Rows:** each page kind owns a fixed set of widgets at fixed positions (a hidden row
  leaves a gap; no relayout): the list's `listRows` rows (a plain `Button`, a font
  string, a 10 × 10 mark texture filled with `INK` for signed inns, and a `HIGHLIGHT`
  layer texture at low alpha); the inn page's header strings, a stamp box and `innRows`
  row boxes (meta line: name or date and seal; phrase text, word-wrapped to 2 lines;
  flourish line); the summary's lines and `barRows` bars (a background texture and a
  fill texture whose width is `fraction` × the bar width); a 3 × 4 grid of stamp cells
  (a `Button` each); quill and seal rows (a quill row's **Use** button enabled from
  `canUse`).
- **Stamps:** a signed stamp is a box whose four sides are solid `STAMP` lines with the
  inn's name and date inside in `STAMP`; an unsigned one has **dashed** sides (each side
  six short color-texture dashes with gaps) and its name in faded `INK`.
- **Fonts** (§3.11.3) and **text colors:** every string is `INK`, faded where the model
  says, with `SetShadowOffset(0, 0)` (the game fonts' shadow smudges parchment).

**Textures, every one unverified on Forever** (each has a solid-color fallback; the
in-client check decides which stay, [§8](#8-in-client-checks-for-12) item 2). A table
`LOOK` in `Book.lua` holds, per surface, `{ file = <path or nil>, color = { r, g, b, a } }`.
The glue always calls `SetColorTexture(color)` first; if `file` is set it then calls
`SetTexture(file)`, and if that returns exactly `false` it re-applies the color. A file
that loads as a blank or green square without returning `false` is caught by the
in-client check and its `file` set to `nil` (a one-line change).

| Surface | Candidate files (try in order, keep the first that looks right) | Fallback color |
|---|---|---|
| dark frame | `Interface\DialogFrame\UI-DialogBox-Background-Dark`; `Interface\Tooltips\UI-Tooltip-Background` tinted dark | `0.10, 0.07, 0.05, 0.95` (dark leather) |
| left page | `Interface\Spellbook\Spellbook-Page-1` (the old spellbook's left page); `Interface\QuestFrame\QuestBG` (quest-log parchment); `Interface\Stationery\StationeryTest1` (mail stationery) | `0.87, 0.80, 0.64, 1` (parchment) |
| right page | `Interface\Spellbook\Spellbook-Page-2`; the left page's choice | `0.87, 0.80, 0.64, 1` |
| spine shadow | none | `0, 0, 0, 0.25` |
| bars, marks, stamp lines, seal dots | none (color only) | `INK`, `STAMP` |

Texture coordinates for the page files (`SetTexCoord`) are tuned in the client; until
then the files are stretched.

#### 3.11.2 Client reads

`read()` builds `s` ([§3.2](#32-bookview-api)); each call runs in `pcall` and every value
is checked for hidden values (`issecretvalue`, failing closed, like `Sign`'s `hidden`)
**before** anything else touches it:
- `ledger = ns.ledger`, read at use, never cached.
- `faction` = the first return of `UnitFactionGroup("player")`: hidden or not a string →
  `nil` (as `Sign`).
- `name = ns.Core:PlayerName()` ([§3.12](#312-changes-outside-the-book)); an error →
  `nil`.
- `offset`: `now = GetServerTime()`; `l = date("*t", now)`, `u = date("!*t", now)`, both
  tables; `u.isdst = l.isdst`; `offset = now - time(u)`. Any step missing, raising,
  hidden or not a number → `0`. `BookView.dateText` clamps the rest.
- the record: `guid = ledger and ledger:ownerGUID()`; `g = ns.Core.db.global` (a table,
  else no record); `all = g.book`; `rec = type(all) == "table" and all[guid] or nil`;
  `prefs = BookView.readPrefs(rec)`. `prefsWritable = prefs.writable and guid passes
  Ledger.validGUID and (all == nil or type(all) == "table")`. `quill`, `shared` from
  `prefs`.

**Writing the record** (`Book:SetQuill(id)`, and the share mark §3.11.6): only when
`prefsWritable`; creates `g.book = {}` if it is `nil`; then `g.book[guid] =
BookView.prefsRecord(quill, shared)`, a fresh table (the old record's other fields go;
there are none in v1). Never writes `ns.ledger` or its saved table.

#### 3.11.3 Fonts

The client's own font objects, never a font file (decision 9). Titles (the book title,
inn names, tab-page titles): `QuestTitleFont` (the client's Morpheus-face quest title
font, **unverified on Forever**) if it is a table, else `GameFontNormalLarge`. Body text:
`GameFontNormal`; small lines (dates, statuses, stamp names): `GameFontNormalSmall`; the
edit box: `GameFontHighlightSmall`. Each is applied with `fs:SetFontObject(obj)` only
when `type(obj) == "table"`; a missing object leaves the font string's creation
template (`GameFontNormal`) in place. Text color always from §3.10.

#### 3.11.4 Opening, closing and ESC

- **`Book:Toggle()`**: hidden → `Book:Open()`; shown → hide.
- **`Book:Open(tab)`**: `tab` (optional) sets `nav.tab`; shows the frame, then
  `draw()`. Navigation is kept for the session (a bookmark): reopening shows the tab and
  inn last seen, except that `Open("share")` and the Share tab always start unticked.
- **`Book:OpenInn(npc)`** (the Read button): `key = view.innKey(npc)`; `nav = { tab =
  "inns", inn = key }` (list page by default, so the list turns to the page holding the
  inn), then show and draw.
- **`draw()`**: `model = view.build(read(), nav)`; `nav = model.nav`; fill the widgets of
  `model.left.kind` and `model.right.kind`, hide every other kind's; the notice line
  (if any) shows above the pages. `model.error` → both pages show `TEXT.pageError`.
  Clicks (tab, ‹ ›, inn row, stamp, Use) change `nav` and call `draw()`.
- **ESC:** at creation, if `UISpecialFrames` is a table, `table.insert(UISpecialFrames,
  "InnkeepersLedgerBook")`, so the client's own Escape handling hides the book (the
  standard way for plain frames; the frame isn't protected, so it works in combat). If
  `UISpecialFrames` is missing, nothing is inserted and the Close button still works
  (one debug line, `book: no special frames`). The book never captures the keyboard
  itself (no keyboard propagation calls, no bindings).
- **`OnHide`**: clears the edit box's focus and text (the string isn't kept in memory).
- **Combat:** the book reads neither combat data nor combat state; its frames are plain
  and unprotected, so opening, turning pages and ESC work in combat.

#### 3.11.5 Quiet refresh

**`Book:Changed()`** is the one refresh hook. If the book isn't shown, it does nothing
(the next open builds afresh). If it is shown and the tab isn't Share, it calls
`draw()` with the current `nav` (pages clamp if they shrank). The Share tab isn't
redrawn (a new string would be a new share; the nudge stays as shown). It never shows
the frame, prints, plays a sound or touches chat. It runs in `pcall`; an error gives
one debug line (`book: error in refresh`).

Callers: `Sync`'s `onEntries` (foreign entries were added) and `Sign` after `"added"`
([§3.12](#312-changes-outside-the-book)). **No timer** anywhere in the book. A burst of
ENTRIES messages redraws once per message with `added > 0`; `SyncProtocol`'s rate
limits (40 messages per sender, 1 200 in all per minute) bound that, and each draw is
bounded by §3.9.

#### 3.11.6 The Share page

On every draw of the Share tab **from a tab click, `Open("share")` or `/ledger share`**
(not from `Changed`), and on every click of the checkbox:
1. `opted = rawequal(check:GetChecked(), true)` (a client that answered `1` would
   never opt in: fail closed). On a tab click or open, the box is first unticked
   (`SetChecked(false)`).
2. `str, reason = ns.Core:ExportString(opted)` (inside `pcall`; an error is `nil`).
3. A string → `edit:SetText(str)`, `edit:SetCursorPosition(0)`, `edit:SetFocus()`,
   `edit:HighlightText()`; debug `book: share <#str> bytes`. Then, if `prefsWritable`,
   the share mark is written: `shared = BookView.snapshot(ledger:own(), unlocked)`
   (`unlocked` as in §3.6), with the current quill kept.
4. `nil` → `edit:SetText("")`, the line `TEXT.shareFail` shows; debug `book: share
   <reason>` (the code goes only to the debug log, never to the page).

The **nudge** shown is the model's, computed from the record **before** this write, so
it tells the player what changed since the previous share; it isn't recomputed on a
checkbox click.

The **edit box:** `CreateFrame("EditBox", nil, page)`, about 360 × 24, single line
(`SetMultiLine(false)`), `SetAutoFocus(false)`, `SetMaxLetters(0)` (no cap; the beta
showed `0` is the default and a 256 000-byte string fits), and `SetMaxBytes(0)` when that
method exists; a background color texture; font §3.11.3. Read-only in effect:
`OnTextChanged(self, userInput)` puts the built string back and re-highlights it when
`userInput` is true; `OnEditFocusGained` highlights all; `OnEscapePressed` clears focus
(the next Escape closes the book). **The checkbox:** a plain `CheckButton` (about 20 × 20)
with a dark box texture, a checked texture (an `INK` square, inset 4 px) set with
`SetCheckedTexture`, and a label font string with `TEXT.include`; no check box template.

#### 3.11.7 Guards and test handles

Every handler, click and refresh runs inside `guard(where, fn)`: `pcall`, and on error
one debug line `book: error in <where>` (never the error text). `BookView.new` runs in
`pcall` at load; on failure `Book.view = nil`, and `Toggle` / `Open` / `OpenInn` print
`TEXT.cantOpen` once per call (a player-initiated command, so one chat line is right)
plus `book: no view`.

For tests: `Book.view`, `Book.nav`, `Book.model` and `Book.ui = { frame, tabs = { inns,
collection, cosmetics, share }, close, left = { prev, next, label, … }, right = { … },
list = { rows }, inn = { title, place, stamp, count, last, rows }, summary = { … },
stamps = { cells }, quills = { rows }, seals = { rows }, share = { edit, check, nudge,
fail }, notice }` are readable fields.

### 3.12 Changes outside the book

- **`Core.lua`:**
  - `SlashCommand`: the first word, lowercased: `""` → `ns.Book:Toggle()`; `"share"` →
    `ns.Book:Open("share")`; `"version"` → the existing `version <v>` line; `"debug"` →
    unchanged; anything else → `ns.Book:Toggle()`. Each Book call in `pcall` (an error:
    debug `book: error in slash`).
  - `Core.PlayerName(_)` (called `Core:PlayerName()`): `ownerName()` if it passes
    `Ledger.validName`, else `nil`. Reads only; Core's existing hidden checks apply.
- **`Sign.lua` and `SignFlow.TEXT`:**
  - `SignFlow.TEXT.read = "Read the guestbook"` (settled label).
  - The **Read button**: created with the Sign button in `ensureButton`, both
    `UIPanelButtonTemplate`, about 160 × 24: Sign's `TOPRIGHT` at `GossipFrame`'s `BOTTOM`
    (−3, −4), Read's `TOPLEFT` at `GossipFrame`'s `BOTTOM` (3, −4). Shown and hidden
    with the Sign button (`GOSSIP_SHOW` at a known inn; `GOSSIP_CLOSED`). `OnClick` →
    `guard("read", …)`: `ns.Book:OpenInn(Sign.flow.innAt(readNpc()))`. It never
    signs, checks resting or selects a gossip option. `Sign.ui.read` is readable.
  - After `"added"` in `commit`: `pcall` `ns.Book:Changed()` (after `WindowChanged`; an
    error gets `sign: error in book` and changes nothing).
- **`Sync.lua`:** `realDeps` gains `onEntries = function() local book = ns.Book; if
  type(book) == "table" and type(book.Changed) == "function" then pcall(book.Changed,
  book) end end`. The `pcall` keeps a Book failure from counting as a sync error. Nothing
  else in `Sync` changes; the hook passes no peer data (it takes no arguments).

### 3.13 Rejected alternatives

- **All the logic in `Book.lua`:** glue has no coverage floor and can't load in the
  strict environment; paging, ordering, text safety and the fallbacks are what need one.
- **One model function per page:** `build(s, nav)` lets one normalization own every
  clamp and default, and tests compare whole models.
- **Escaping `|` as `||` in names:** a stored name with `|` already means a tampered file
  or a bug; replacing it with "A traveler" shows nothing a peer chose, and `validName`
  makes it unreachable today.
- **Stripping hidden characters in `plain` instead of falling back** (#119): the shown
  name would no longer be the stored one, and a stripped forgery could look exactly like
  another traveler's name; "A traveler" shows nothing a peer chose.
- **Scrolling lists (`ScrollFrame`, `ScrollBox`):** the maintainer chose page turns
  (decision 2), and they need no unverified template.
- **Tab and check box templates (`PanelTabButtonTemplate`, `UICheckButtonTemplate`,
  `InputBoxTemplate`, `BackdropTemplate`):** unverified on Forever, and an unknown
  template is a load-time error; plain frames and color textures do the job.
- **Keyboard capture for ESC (`EnableKeyboard` plus propagation):** swallows movement
  keys and the propagation call is restricted in combat; `UISpecialFrames` is the
  standard path for a plain frame and costs one global name.
- **AceDB's per-character profile (`db.char`) for the record:** its key is the first
  return of `UnitName` plus the realm, and on Forever that's the first name only, so two
  characters named "Mira" on one ruleset realm would share a quill. The ledger's own GUID
  key can't collide.
- **The quill and share mark inside the ledger's saved table:** a `Ledger` schema
  change (sync-ledger.md §4.2) for display preferences, and a read-only ledger couldn't
  store them.
- **Recording the share mark only when the player copies:** detecting Ctrl+C means
  reading keys in the edit box, more client surface for a nudge; the mark is recorded
  when the string is built and shown ([Open questions](#open-questions-maintainer) 3).
- **Comparing export strings for the nudge:** bytes aren't stable (export.md §3.2).
- **A timer to coalesce refreshes, or a periodic rebuild:** the maintainer ruled out
  timers; sync's own rate limits bound the redraws.
- **Hard-coded flourish per quill ID:** collection-cosmetics.md §8 forbids hard-coding
  IDs; rank order keeps the look stable as the catalog changes.
- **Rendering every entry of an inn up front:** 600 renders for a page that shows 6.
- **Oldest-first entries:** a guestbook reads that way on paper, but the latest crossing
  is what a player opens the page for ([Assumptions](#assumptions-listed-for-the-maintainer)).
- **The Read button in `Book.lua` with its own `GOSSIP_SHOW` handler:** two handlers
  reading the same NPC and two buttons positioned by different files; `Sign` already owns
  the gossip frame.
- **Listing inns of the other faction (faded):** never finishable, and the totals
  exclude them (collection-cosmetics.md §3.3).

## 4. Data model changes

### 4.1 SavedVariables: the book's record

A new table in the AddOn's existing SavedVariables (`InnkeepersLedgerDB`, AceDB's
`global` section), **separate from the ledger** (whose schema stays 1):

```lua
InnkeepersLedgerDB.global.book = {
  [<owner GUID>] = {          -- Ledger.validGUID; the GUID the ledger was opened for
    v = 1,                    -- this record's version
    quill = 1001,             -- optional: the chosen quill's cosmetic ID; absent = the plain quill
    shared = {                -- optional: the snapshot at the last share
      own = 7,                -- own entries then (integer 0..ownMax)
      newest = 1790000400,    -- the newest own entry's t (a time); absent when own == 0
      unlocked = 4,           -- unlocked cosmetics then (integer 0..cosmeticIdMax)
    },
  },
}
```

- **Migration:** none needed. The table is new: a missing `book`, or a missing record,
  reads as "nothing saved" and is created on the first write
  ([§3.11.2](#3112-client-reads)). Reading follows `readPrefs`
  ([§3.7](#37-the-share-tab-and-the-saved-record)): a damaged `book` or record (not a
  table) is never overwritten; a record from a **newer** version (`v > 1`) is neither
  read nor written; a broken v1 record is replaced whole by the next write. A future v2
  adds `MIGRATIONS`-style steps here with its own spec.
- **Bounds:** one record per character that has opened its ledger and chosen a quill or
  shared; written only for the logged-in owner's GUID; three small fields. Nothing a peer
  sends reaches it.
- **Not stored:** navigation, the export string, the checkbox (decision 5: unticked every
  open), window position.

### 4.2 Formats

- **Wire format:** unchanged (v1). Quills and flourishes are local; nothing new is sent.
- **Export:** unchanged (v1). The book only calls `Core:ExportString`.
- **Ledger:** unchanged; the book only reads it (`own`, `innEntries`, `counts`, `earned`,
  `ownerGUID`, `readOnly`).

### 4.3 Docs the implementer updates

In the same PR:
- [architecture.md](../architecture.md) → Modules: the `UI/Book` row ("the parchment
  book: four tabs, inn pages with travelers' signatures, the stamp grid, quills as a local
  flourish, the Share page; draws `BookView` models; its own record in
  `db.global.book[guid]`", linking this spec) and a new **`BookView`** row (pure: page
  models, paging, ordering, text safety, dates, the quill fallback, the share nudge).
  Signing flow step 2: the "Read the guestbook" button beside "Sign the guestbook". Sync
  protocol → Receiving: one line that `onEntries` only tells the book to redraw. Export:
  the Share page and `/ledger share` exist now (drop "will call" / "today").
- [sync-glue.md §3.3.1](sync-glue.md#331-the-sync-instance) and the dispatch table:
  `onEntries` is now `Book:Changed()` (in `pcall`).
- [sign.md](sign.md): §3.9 and §6.3 for the second button and its placement; §3.9 step 3
  of `Commit` gains the `Book:Changed()` call; Scope's "Out" list drops "`UI/Book`, the
  Share window, `/ledger share`".
- [export.md §8](export.md#8-contract-for-later-slices): the Share window and the nudge
  are built (link this spec's §3.7 and §3.11.6; the mark is recorded when the string is
  built and shown).
- [testing.md](../testing.md): the stub additions of [§6.1](#61-stub-and-helpers), the
  Book tests, and `BookView` in the coverage-floor sentence (90%).
- [platform-forever.md](../platform-forever.md) → Verification checklist: the checks of
  [§8](#8-in-client-checks-for-12).
- [security-checklist.md](../security-checklist.md) → release review item 8 (Rendering):
  "peer names pass `BookView.plain` (no `|`, control bytes or broken UTF-8 reach a font
  string)".
- `CLAUDE.md` → Context map: a row for this spec, after `sign.md`'s: *the `UI/Book` spec:
  tabs, page models (`BookView`), inn pages, stamps, quills as flourishes, the Share page
  and nudge, the book's SavedVariables record, `/ledger` commands, the Read button* —
  read when *`BookView.lua`, `UI/Book.lua`, `/ledger` commands, the Read button, the
  Share page, anything the book shows*.
- [README.md](../../README.md): no change is required (it doesn't document `/ledger`). If
  the orchestrator wants one, a line under *What it does*: "Open your ledger with
  `/ledger`; `/ledger share` copies your export string." (The README's "Quills, inks"
  wording is #105's.)
- [status.md](../status.md): the book built; its wording and look under Open questions;
  the in-client batch.
- [decisions.md](../decisions.md): the maintainer entry of *Already decided* above, and
  one implementation entry, *Book: a pure BookView, one named frame for ESC, a GUID-keyed
  record, the share mark at build, refresh through `onEntries`* (what §3.11–§3.13
  settle), including the new 90% floor and the one global name.
- `.luacheckrc` (`wow` list): `UIParent`, `UISpecialFrames`, `GameFontNormal`,
  `GameFontNormalSmall`, `GameFontNormalLarge`, `GameFontHighlightSmall`,
  `QuestTitleFont`, `date`, `time`. No other new global.
- TOC: `BookView.lua` after `SignFlow.lua`.

## 5. Security notes

**For the reviewer: security-level review of the display of peer data, the `onEntries`
hook, the export opt-in, and the saved record's reader.** Say in the review which items
were checked and what hostile input was tried.

- **Peer data at display.** Travelers' names and entries come only from the ledger, which
  stored them through `SyncProtocol` (every rule of architecture.md → Security model) and
  `addForeign`. The book adds a second gate: names through `plain` (no `|`, control bytes,
  `\127`, malformed UTF-8 or hidden character such as a bidi override or a zero-width
  joiner reaches a font string, #119; byte-capped), entries through
  `Ledger.validEntry`, phrases rendered from our own allow-listed table (a `nil` render
  shows `TEXT.faded`), seals named from our catalog. No peer string is ever passed to
  `string.format`, `SetFormattedText`, a pattern or a `gsub` replacement, used as a table
  key in the glue, or concatenated into anything but a font string's text.
- **Bounded work on peer-sized data.** An inn page reads at most `foreignReadMax` (600)
  foreign and `ownReadMax` (1 000) own entries **per NPC ID**, newest first, over at most
  `aliasesMax` (8) NPC IDs (so at most 8 × the caps per build), trims the merged list to
  the same caps, and renders at most `innRows` (6). The list, stamps and cosmetics are sized by our own data.
  A ledger at every storage cap (3 000 foreign entries) can't make a build loop without
  bound or throw.
- **The `onEntries` hook** (the one change in `Sync.lua`): it carries no arguments and no
  peer data; it runs only after `SyncProtocol` accepted and stored entries; it is wrapped
  in `pcall` so a book error can't break or count against the receive path; the book only
  redraws (no write to the ledger, no send, no output); redraws are bounded by
  `SyncProtocol`'s rate limits. Own-signature rule, rate limits, size and storage caps:
  untouched.
- **Export opt-in:** travelers are included only when the checkbox's `GetChecked()` is
  exactly `true` and passed as exactly `true` (export.md §3.4); the box is unticked at
  every open and on every tab click; nothing remembers it. The string is built only on
  open or click. No decoder or import is added; the `general purpose decoders` rule stays
  closed.
- **The saved record** is our own, keyed by the owner's validated GUID, read through
  `readPrefs` (integer-and-range tests; junk or newer records never written), written as
  a fresh table of three known fields. A tampered record can at most pick a quill (only
  if unlocked) or change the nudge line for that player.
- **Globals and taint:** one named frame, `InnkeepersLedgerBook`, and one insertion into
  `UISpecialFrames` (the standard pattern for plain frames). No Blizzard function, frame
  method or script is overwritten or hooked; the frames are unprotected; the Read button
  is a plain button parented to `GossipFrame`, like Sign's (verified). Release review
  item 1 checks it.
- **Forbidden-API guard:** `BookView.lua` names no WoW API (pure, strict environment).
  `Book.lua` uses no hook, binding, gossip action, combat data or state, chat send or
  addon message API, `_G`, or code loading. `sh scripts/check-apis.sh` passes with **no
  rule or allow-list change**. Watch two traps: never name a method after a listed API
  (no `Book:SelectOption`; inn rows call `Book:ShowInn`), and the dynamic-code rule
  matches the word "load" at the end of a comment line or before `(`, so reword such
  comments.
- **Policy:** no site, product, service or URL in any `TEXT` line or in the Share page
  (a test checks); nothing paid or gated; cosmetics are only displayed and chosen.
- **Quiet failure:** every handler is guarded; debug lines carry only our codes and
  numbers (`book: share 11773 bytes`), never a name, a phrase or an error's text.

## 6. Test plan

### 6.1 Stub and helpers

**`spec/helpers/wow_stub.lua`**, only what the Book tests need, keeping every current
test's behavior:
- `CreateFrame(kind, name, parent, template)`: a non-`nil` `name` also sets the global
  (as the client does; `uninstall` removes it). New kinds: `EditBox` (`SetText` /
  `GetText`, `SetCursorPosition`, `SetFocus` / `ClearFocus` / `HasFocus`,
  `HighlightText` (records it), `SetAutoFocus`, `SetMultiLine`, `SetMaxLetters` /
  `GetMaxLetters`, `SetMaxBytes`, `SetFontObject`, scripts `OnTextChanged`,
  `OnEscapePressed`, `OnEditFocusGained`, and a `wow.type(edit, text)` helper that runs
  `OnTextChanged(self, true)`), `CheckButton` (`SetChecked` / `GetChecked` returning a
  boolean, `SetCheckedTexture`; `Click()` toggles, then runs `OnClick`).
- Frames gain `SetFrameStrata`, `SetClampedToScreen`, `SetScript("OnHide")` (run by
  `Hide` when shown). Font strings gain `SetFontObject`, `SetTextColor` (recorded),
  `SetShadowOffset`, `SetAlpha`, `SetJustifyV`. Textures gain `SetTexture(file)`
  (recorded; returns `true`), `SetTexCoord`, `SetVertexColor`, `SetWidth`.
- Globals: `UIParent` (a stub frame), `UISpecialFrames = {}`, `GameFontNormal`,
  `GameFontNormalSmall`, `GameFontNormalLarge`, `GameFontHighlightSmall`,
  `QuestTitleFont` (empty tables), `date = os.date`, `time = os.time`. Each overridable
  (set to `nil`) to test the fallbacks.

**Fixtures:** the pure tests reuse `spec/helpers/places.lua` (places F, entries E, catalog
C, the two hidden-value stand-ins, the seeded shuffle) and the phrase fixture of
[phrase.md §6](phrase.md#6-test-plan); a real `Ledger` with a fixed anchor, own entries
through `addOwn`, travelers through `addForeign` (valid GUIDs
`"Player-1-0000000A"`…); `T = 1790000000`. Since #105, catalog C's two
former inks are quills 1002 and 1003; one case adds a record of a stray kind to prove the
book ignores any kind but quill and seal.

### 6.2 `spec/book_view_spec.lua` (pure, strict environment)

- **`new`:** raises without `inns`, `atlas`, `phrase`, `cosmetics` or one of their needed
  functions; loads in the strict environment; raises without `ns.Ledger`. `sizes` out of
  range (`2`, `51`, `1.5`, `"6"`) keep the defaults.
- **Inn index:** F's alias 5003 joins 5001's group (`{ 5001, 5003 }`); a key `bind`
  excluded is left out; a group of 10 aliases keeps 8 including the primary;
  `innKey(5003) == 5001`, `innKey(9999)`, `innKey("5001")`, `innKey(0/0)` → `nil`.
- **`plain`:** `"Mira Ashvale"` unchanged; `"Zoë"` unchanged; `"a|cffff0000b"`,
  `"a||b"`, `"a\nb"`, `"a\0b"`, `"a\127b"` → fallback; malformed UTF-8: `"\128"`,
  `"Zo\195"`, `"\192\128"`, `"\193\191"`, `"\245\128\128\128"`, `"\226\130"` →
  fallback; `nil`, `7`, `""`, `{}`, both stand-ins → fallback, no throw; a 70-byte
  ASCII name at 64 → its first 64 bytes + `"..."`; a name whose 64th–65th bytes are one
  two-byte character → its first 63 bytes + `"..."` (the cut backs off); never returns
  `|`.
- **`plain`, hidden characters (amended 2026-10-07, #119):** → fallback for an RLO
  (`E2 80 AE`), a ZWJ (`E2 80 8D`), an NBSP (`C2 A0`), an ideographic space (`E3 80 80`)
  and a Hangul filler (`E3 85 A4`), each at the start, the middle and the end of
  `"Mira Ashvale"`; a C1 control (`"Mi\194\133ra"`); an overlong 3-byte
  (`"\224\128\128"`) and 4-byte (`"\240\128\128\128"`) sequence; a surrogate
  (`"\237\160\128"`); a code point above U+10FFFF (`"\244\144\128\128"`); a 70-byte
  ASCII name with an RLO at bytes 66–68 → fallback, **not** a clean 64-byte prefix (the
  check runs before the cut). Still unchanged: `"Ýrsa"`, `"Weiß"`, `"Алдрик"`,
  `"알드릭"`, `"艾德里克"`. Cuts still land on a boundary: 23 Hangul syllables (69 bytes)
  at 64 → the first 63 bytes + `"..."`; 62 ASCII bytes, then U+10000 (`F0 90 80 80`),
  then 4 ASCII bytes at 64 → the first 62 bytes + `"..."`. **Agreement:** over the
  seeded fuzz strings of [sync-ledger.md §6](sync-ledger.md#specledger_speclua)
  (`cleanText`), `plain(x, 64, F)` is `F` whenever `cleanText(x)` is `false`, and no
  result holds `|`.
- **`dateText`:** `(1789603200, 0)` → `"17 September 2026"`; `(1789603200, -3600)` →
  `"16 September 2026"`; `(1835395200, 0)` → `"29 February 2028"`; `(1798758000, 0)` →
  `"31 December 2026"` and `(1798758000, 3600)` → `"1 January 2027"`; `offset` of `NaN`,
  `1.5`, `50401`, `"0"` → as `0`; `t` of `tMin - 1`, `tMax + 1`, `NaN`, `"1789603200"` →
  `nil`.
- **Navigation:** every `nav` field replaced by `nil`, `NaN`, `1.5`, `-1`, `"2"`, a
  stand-in, a table with raising metamethods → the defaults, no throw; pages past the
  end clamp to the last; `tab = "Inns"` → `"inns"`; `inn` an alias (5003), an unknown
  key, a non-integer → `nil`; default `listPage`: `0` with no own entries, `1` with one,
  the page holding `inn` when set (with `listRows = 5` so it isn't page 1), `0` / `1` when
  `inn` isn't listed (another faction's).
- **Title and help:** `The ledger of Aldric` for a valid name; `Your ledger` for `nil`,
  a name with `|`, malformed UTF-8, and a name with an RLO (#119); `TEXT.sharesText`
  equals the README's sentence:
  the spec reads `README.md`, takes the text after `What sync shares: ` up to the
  paragraph end, joins lines with single spaces, capitalizes its first letter, and
  compares exactly.
- **List** (F, E): Alliance rows exactly (continents East, West by name; zones in each by
  name with `signed n of m`; inns signed or faded; zone 21 absent); Horde (5002 and 5101
  absent, 5202 and 5301 listed); faction `nil` (every inn); `selected` on `nav.inn`;
  **paging with `listRows = 5`**: exact rows of every page, repeated headers with `cont =
  true` where a page starts mid-zone, every inn on exactly one page, the page count; the
  empty atlas → one page, no rows, `empty = TEXT.noInns`.
- **Inn page** (ledger over E plus travelers):
  - 5001's page merges entries at 5001 and 5003; own rows newest first; `count`, `first`
    and `last` from progress (`Signed 3 times`, `Last signed …`); the stamp dated by
    `first`; title and `place = "Vale, East"`.
  - travelers: three entries with equal `t` order by signer GUID bytes
    (`Player-1-0000000A` before `Player-1-0000000a`), then NPC ID.
  - notes: no own entries → `noOwn`; no travelers → `noForeign`; both headings present.
  - **paging with `innRows = 4`**: exact rows per page with repeated headings (`cont =
    true`); the page count from the row count.
  - **renders only the page:** with 300 foreign entries, a spy on `phrase.render` counts
    at most `innRows` calls per build, and a spy on the ledger's `innEntries` counts one
    call per NPC ID of the group.
  - **read caps:** a fake ledger whose `innEntries` returns 5 000 foreign and 5 000 own
    items → at most 600 and 1 000 read (`rawget` spy), the newest kept, no throw.
  - row content: a phrase that won't render → `TEXT.faded`; seals: a milestone seal's
    name, a zone seal's `"<zone> seal"`, an unknown seal ID → `a seal`; a foreign name
    with `|` (forced into a fake ledger) → `A traveler`, and the same for a foreign name
    with a ZWJ (#119); own rows carry the effective
    quill's flourish and none with the plain quill.
  - hostile ledger: `innEntries` raising, returning `nil`, a string, items that aren't
    tables, entries failing `validEntry`, a `signer` that's a number → those rows
    skipped, notes where nothing is left, no throw.
- **No ledger / read-only:** `s.ledger = nil` → `notice = noLedger`, list all unsigned,
  title page by default; a read-only ledger (newer schema) → `notice = readOnly` and its
  entries shown.
- **Collection:** Alliance over E: `4 of 4 inns signed`, `Zones completed: 3 of 3`,
  `Signatures: 7` (every own entry, the unknown inn's and the weekly return included),
  `Travelers met: 2` (with two travelers added); bars by continent name with exact
  `fraction`s; Horde's numbers; `barRows = 3` paging; `counts()` raising or returning
  junk → zeros; the empty atlas → `empty`.
- **Stamps:** cells in place-tree order, each continent on its own page; signed cells
  dated by `first`; `stampCells = 3` → a continent with 4 open inns spans two pages and
  the next continent starts a new one; empty atlas → `empty`.
- **Cosmetics:**
  - `effectiveQuill`: `nil`, `0`, a locked quill, a seal ID, an unknown ID, `NaN`,
    `1.5`, a string, a stand-in → `0`; an unlocked quill → itself; an unlocked list with
    a raising metatable → `0`.
  - quills: the plain quill first; `chosen`, `canUse` (false when `prefsWritable` is
    false), statuses for chosen, plain, unlocked (`Earned <date>`) and locked
    (`Sign 10 inns · 4 of 10` with real-shaped data); paging with `quillRows = 3`;
    flourish ranks: the first catalog quill → `FLOURISHES[1]`, the fifth → wraps to
    `FLOURISHES[1]`.
  - seals: earned with dates; locked with each rule kind's text and progress (`inns`,
    `zones`, `continent` picks the nearest-done continent, `all`, `zone`); progress
    capped at the goal; a Horde-only zone's seal absent for Alliance unless unlocked
    (with a kept `earned` floor → present and earned); a record of another kind
    (`"ink"`, `"badge"`) ignored.
- **Share:** `snapshot` over E (`own = 7`, `newest = T+604800`, `unlocked = n`), over
  `{}` (`own = 0`, no `newest`), over junk; `nudge`: `nil` stored → `nil`; equal →
  `nothingNew`; `+1` → `newOne`; `+3` → `3 new signatures…`; unlocked only → `changed`;
  fewer own → `changed`; stored with `newest` but `own = 0`, `own = NaN`, `own = -1`,
  `unlocked = 10000` → `nil`.
- **Saved record:** `readPrefs` for `nil`, `"x"`, `{ v = 2, quill = 1001 }` (not
  writable, nothing read), `{ v = 1, quill = 1001, shared = {…} }`, `{ v = 1, quill =
  "1001" }`, `{ v = 1, shared = { own = 1 } }` (no `newest` → `nil`), `{}` (writable, no
  fields), a stand-in; `prefsRecord` gives exactly `{ v, quill?, shared? }` and copies
  `shared`.
- **Safety walks:** every string in every model built over the real data and over F
  (all tabs, all pages) has no `|` and no `%`; every `TEXT` value and `FLOURISHES` entry
  has no `|`, `%`, `http`, `www` or `://`; `build` with each `s` field and `nav` replaced
  by hostile values never throws and never writes to `s`, `nav` or the ledger (deep
  compare of the saved table).
- Coverage ≥ 90%; `luacheck` clean.

### 6.3 `spec/book_spec.lua` (the glue, whole AddOn under the stub)

Logged in as `spec/core_spec.lua` does, the faction `"Alliance"`, the real data
(Calmbreeze Inn, `254089`, Zephras Isle under Azeroth 947).
- **Open and close:** `/ledger` shows `InnkeepersLedgerBook` (the global exists, is the
  frame); `/ledger` again hides it; `/ledger foo` toggles; the frame's name is in
  `UISpecialFrames`; with `UISpecialFrames = nil` the book still opens, no error.
  `/ledger version` prints `version dev`; `/ledger debug` still toggles the log.
- **First open, empty ledger:** the title page (`The ledger of Traveler`, the three
  steps, the hint) and the help page with the README's words; › turns to list page 1
  listing Zephras Isle, `signed 0 of 1`, Calmbreeze Inn faded.
- **After a signature** (`addOwn` at `254089`): the list's default page is 1;
  `signed 1 of 1`, the inn's mark shown; clicking its row → the right page reads
  `Calmbreeze Inn`, `Zephras Isle, Azeroth`, the stamp dated, `Signed once`, the own row
  with the rendered phrase.
- **Page turns:** 8 travelers' entries at `254089` (`addForeign`, spread over weeks) →
  two inn pages (heading, note, heading and 3 entries, then the repeated heading and 5;
  a ninth entry would open a third page); ‹ disabled on page 1, › enabled; › → page 2 shows the rest with the
  repeated heading, › disabled; the page label reads `2 / 2`.
- **Read button:** `GOSSIP_SHOW` at Calmbreeze → two buttons under `GossipFrame` labeled
  `Sign the guestbook` and `Read the guestbook`; at a vendor → both hidden; Read → the
  book shown on the Inns tab with Calmbreeze's page; `GOSSIP_CLOSED` → both buttons
  hidden, the book still shown; Read with `ns.Book` broken → no error escapes.
- **Quiet refresh:** with the inn page open, `addForeign` one more entry and call
  `ns.Sync.client.deps.onEntries()` → the new traveler row is drawn, `wow.chat`
  unchanged, the frame still shown, the page index kept; with the book hidden →
  `Book.view.build` not called (spy); `Book:Changed` raising inside → no error escapes
  and the sync counters' `errors` is unchanged. Signing through `Sign` while the book
  shows → the own row appears.
- **Share:** `/ledger share` → the Share tab, the box unticked, the edit box's text equals
  `ns.Core:ExportString()`'s string, focused and highlighted, `GetMaxLetters() == 0`;
  ticking → equals `ExportString(true)`'s; switching tabs and back → unticked again;
  `ExportString` stubbed to return `nil, "libs"` → `Your ledger can't be shared right
  now.`, the edit box empty, the word `libs` nowhere in the frame's strings, one debug
  line only with debug on; typing into the box (`wow.type`) → the string restored.
  **Nudge and mark:** first share → no nudge, then `db.global.book[guid].shared` holds
  the snapshot; sign once more and reopen Share → `1 new signature since you last
  shared.`; the record's `v == 1`.
- **Quill:** the Cosmetics tab with an unlocked quill (with the real data, one signature
  at Calmbreeze unlocks the Cartographer's quill, 1003) → Use enabled; Use →
  `book[guid].quill == 1003`, the row says `In use`, own rows on an inn page show its
  flourish; a saved quill that isn't unlocked (1001) → the plain quill is `In use` and
  the saved value unchanged.
- **Damaged record:** `db.global.book = "x"` → the book works, Use disabled, nothing
  written (deep compare); `book[guid] = { v = 2 }` → the same; `db.global` not a table →
  the same.
- **Fallbacks:** `QuestTitleFont = nil` → titles use `GameFontNormalLarge`, no error;
  `date = nil` → dates in UTC, no error; `UnitFactionGroup` hidden or raising → every
  inn counted; `ns.ledger = nil` → the `noLedger` notice; a read-only ledger → the
  `readOnly` notice and its entries.
- **Errors:** `Book.view.build` stubbed to raise → `This page can't be read right now.`,
  no error escapes; `BookView.new` failing at load (stubbed `ns.Collection.atlas = nil`
  before `Book.lua`) → `/ledger` prints `The ledger can't be opened right now.` once;
  `wow.errors` stays empty in every case.

### 6.4 Changes to existing specs

- `spec/sign_spec.lua`: "one button" becomes two (Sign and Read, both parented to
  `GossipFrame`, shown and hidden together); after `"added"`, `ns.Book.Changed` is called
  once (spy) and its raising changes nothing.
- `spec/core_spec.lua`: `/ledger` no longer prints the version (it toggles the book);
  `/ledger version` does; `Core:PlayerName()` → `"Traveler"`, `nil` when hidden.
- `spec/sync_spec.lua` / the harness: unchanged (the harness passes its own `deps`);
  `spec/addon_load_spec.lua`: `realDeps().onEntries` is a function, `ns.BookView` is a
  table, and the TOC / `load.PURE` / `.luacheckrc` checks pass with `BookView.lua`.

### 6.5 Lint and guards

`luacheck .` clean (the nine globals of [§4.3](#43-docs-the-implementer-updates) in
`.luacheckrc`, nothing else); `sh scripts/check-apis.sh` passes with no rule or
allow-list changed; `check-libs.sh`, `check-links.sh`, `check-coverage.sh`
(`BookView.lua` ≥ 90%) pass; `no-urls-in-game-code` passes.

## 7. Acceptance criteria

- [ ] `BookView.lua` implements §3.2–§3.10 (`TEXT` and `FLOURISHES` marked DRAFT); pure,
      loads in the strict environment, listed in the TOC after `SignFlow.lua`,
      `load.PURE`, `.luacov` and `check-coverage.sh` at 90%.
- [ ] `UI/Book.lua` implements §3.11 (the look marked DRAFT in a comment): core frame API
      only, every client value hidden-checked first, every handler guarded, one named
      frame inserted into `UISpecialFrames`, no timer, no keyboard capture.
- [ ] The four tabs show what decisions 2–6 say; travelers appear only on inn pages and
      as a count; page turns everywhere a list can overflow, no scrolling.
- [ ] Peer names reach font strings only through `BookView.plain`; nothing is formatted
      or `gsub`bed with data.
- [ ] `plain` calls `Ledger.cleanText` on the full input before the cut (#119), and no
      branch of its byte loop is left unreachable.
- [ ] `/ledger` toggles, `/ledger share` opens Share, `/ledger version` prints the
      version, `/ledger debug` unchanged; the Read button opens the inn's page.
- [ ] `Sync`'s `onEntries` and `Sign`'s `"added"` call `Book:Changed()` in `pcall`; the
      book redraws only while shown and never outputs anything.
- [ ] The Share page follows export.md §8 (unticked every open, `true` only, full-length
      box, preselected, neutral failure line, no site) and the nudge compares snapshots.
- [ ] `db.global.book[guid]` follows §4.1; damaged and newer records are never written.
- [ ] Every test named in §6 exists and passes (`busted` output in the PR), including the
      README sentence check, render-only-the-page, the read caps and the refresh cases.
- [ ] `busted`, `luacheck .`, `check-apis.sh` (no rule changed), `check-libs.sh`,
      `check-links.sh`, `check-coverage.sh` green locally and in CI.
- [ ] No wire, export or ledger-schema change; no combat read; no new library.
- [ ] The reviewer checked §5 item by item and tried hostile display data of its own
      (names with `|`, broken UTF-8, hidden characters such as an RLO or a ZWJ, a ledger
      at the caps, a tampered record).
- [ ] Docs of §4.3 updated; the wording and look are under status.md → Open questions;
      §8's checks are on the platform-forever.md checklist (#12).

## 8. In-client checks (for #12)

With `/ledger debug` on; screenshots go to the maintainer (the DRAFT look):
1. **Opening:** `/ledger` opens the book in the middle of the screen and closes it;
   `/ledger version` prints the version; no Lua error (with script errors shown).
2. **The look:** the dark frame, two parchment pages and the spine render; for each
   texture candidate of §3.11.1, whether it loads (not blank, not green) and looks right;
   the chosen files' coordinates. A screenshot of each tab.
3. **Fonts and glyphs:** titles in the Morpheus face (`QuestTitleFont` exists), body text
   in the game font, ink colors readable on the parchment; the `‹` `›` and `·` glyphs
   render (else `TEXT.prev` / `TEXT.next` become `<` / `>` and `TEXT.dot` ` - `).
4. **ESC:** Escape closes the book; with the Share box focused, the first Escape clears
   focus and the second closes; Escape in combat closes it too, with no "blocked" or
   taint message.
5. **Page turns:** ‹ and › enabled and disabled correctly on the list and on Calmbreeze's
   page; with more travelers or inns later, a second page turns and shows the repeated
   heading.
6. **The Read button:** at Coriella Calmbreeze, "Read the guestbook" sits beside "Sign the
   guestbook" without overlapping; it opens the book on Calmbreeze Inn's page; both
   buttons hide when the gossip closes and the book stays open.
7. **Share:** `/ledger share` shows the string preselected and the box unticked;
   Ctrl+C then a paste outside the game gives the whole string (its length equals the
   debug line's `book: share <n> bytes`); ticking rebuilds it longer when travelers
   exist; `GetChecked()` returns `true` (a boolean) when ticked; reopening starts
   unticked. After one more signature, reopening shows `1 new signature since you last
   shared.`
8. **Refresh while open:** with a second character in the party, open your inn page,
   let them sync (`got entries … added n` in the debug log): their signature appears
   without anything popping up or printing.
9. **Dates:** an entry's date matches the local calendar (check one made late in the
   evening, local time, where UTC is already the next day).
10. **Quill:** once a quill is earned (the beta's ten-inn threshold may not be reached;
    else check with the plain quill only): Use it, `/reload`, the choice holds and own
    signatures show its flourish; `InnkeepersLedger.lua` holds `book[<guid>] = { v = 1,
    quill = … }`.
11. **First open on a fresh character:** the title page with the character's two-part
    name and the help page; nothing else is written to SavedVariables until a share or a
    quill choice.

## Assumptions (listed for the maintainer)

- **Newest first:** your signatures and travelers' are listed newest first on an inn's
  page, so the latest crossing is on the first page.
- **The title page is the book's first page** and opens by default only while you have no
  signatures; › turns to the inn list, ‹ from list page 1 turns back to it.
- **The book keeps your place** (tab, inn, pages) for the session; it isn't saved.
- **"Since you last shared" means since the share string was last built and shown** (the
  AddOn can't tell whether it was copied without reading keys).
- **Dates are local calendar dates** (the client's time zone), with no time of day; UTC
  if the client can't say.
- **A quill's flourish applies to all your signatures,** past ones included; it is your
  book's look, never stored on an entry or sent.
- **Inns of the other faction aren't listed;** the Read button still opens such an inn's
  page.
- **A zone seal you can't earn (another faction's zone) isn't shown,** unless you
  already have it.
- **Stamps are clickable** and open that inn's page.
- **`/ledger` with an unknown word opens the book** rather than printing help.
- **The book doesn't move** and sits in the middle of the screen, above the gossip frame.
- **One ink** (iron-gall brown-black) for all handwriting; stamps in a red-brown stamp
  ink.

## Open questions (maintainer)

None blocks the build or the merge; the DRAFT ships until answered.

1. **Wording and look** (§3.10, §3.11.1): every line, the flourish designs, the ink
   colors, the textures, the layout. The in-client screenshots (§8 items 2–3) are the
   basis for this.
2. **Entry order** (Assumptions): newest first, or oldest first like a paper guestbook?
3. **The share nudge's moment:** count a share when the string is shown (as built), or
   only when it's copied (needs key reading in the edit box)?
4. **A movable book** (or a remembered position): worth it once you've used it next to the
   gossip frame?
