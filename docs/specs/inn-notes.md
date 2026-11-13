# Spec: inn notes — noting innkeepers the AddOn doesn't know

> **Summary:** when a player talks to an innkeeper whose NPC ID isn't in `Data/Inns`, the
> AddOn quietly notes what the client reports (the NPC ID, the zone and continent map
> IDs, the server time, the innkeeper's faction when it reads as one) in a small
> per-character record, and the export string carries those notes as a new optional
> field, `notes`, added to v1. Recognition is the binder gossip option's icon; nothing is
> ever selected. A pure module, `InnNotes`, holds every rule; `Notes.lua` is thin glue.
> No book page in this slice.
> **Read when:** implementing or reviewing `InnNotes.lua`, `Notes.lua`, the `notes` export
> field or the notes record in SavedVariables; writing an export consumer that reads
> `notes`; adding an inn to `Data/Inns` from notes.

**Status:** approved (self-approved 2026-11-13, ticket #157). No maintainer decision
blocks the build. One player-facing line changes, the Share page's description of what
an export holds ([§3.8](#38-the-share-pages-description-draft)); it is a **DRAFT** and
ships as written until the maintainer decides (decisions.md → *Maintainer-gated content
ships as a DRAFT and doesn't block merge*). **When it merges is decided separately**
(decisions.md 2026-11-04: the feature ships in the first release after launch). Nothing
here assumes it ships in the first tag.
**Security-sensitive:** moderately. No peer data is read and nothing is synced, but the
slice reads new client values into SavedVariables, adds a field to the export (the
privacy boundary of [export.md §5](export.md#5-security-notes)) and narrows the
forbidden-API list. The reviewer applies security-level scrutiny to
[§5](#5-security-notes) and must try hostile client values and tampered SavedVariables
of its own.

Builds on (changes none of their behavior, except as listed in §4):
[sign.md §3.9](sign.md#39-signlua-the-glue) (client reads with hidden-value checks, the
`GOSSIP_SHOW` event, the guards); [sync-ledger.md §5.2](sync-ledger.md#52-hidden-secret-values-and-identity)
(the creature-GUID rule of `Ledger.innFromNpcGUID`); [collection-cosmetics.md §3.1](collection-cosmetics.md#31-places-inns-zones-continents)
(zone and continent keys are the client's map IDs, found by walking the map chain);
[export.md](export.md) (`build`'s rules, limits, the test-only decoder and `schemaOk`);
[book.md §4.1](book.md#41-savedvariables-the-books-record) (a separate, versioned
per-character record beside the ledger).

**Depends on client facts from the live walk (#12), now in
[platform-forever.md](../platform-forever.md) (their home, on `dev` since #161), and re-read
for this spec from the live probe's `npcs` table. As read when this spec was written:**
- 109 NPCs talked to in live; **exactly 7 had an option with icon `132052`**, and all 7
  are the innkeepers now in that branch's `Data/Inns` (NPCs `295`, `1464`, `6727`,
  `6734`, `6737`, `6740`, `8931`). No other NPC showed that icon. The beta's Coriella
  Calmbreeze (`254089`) had it too.
- **The binder option's `gossipOptionID` differs per innkeeper** (`95566`, `96506`,
  `96527`, `98485` in live; `137079` in the beta), and its position in the option list
  varies (first, second or third). So the option is recognized by its icon, never its ID
  or its place.
- **Every innkeeper's map chain read Zone → Continent → World 947**
  (`C_Map.GetBestMapForUnit("player")` was the Zone map itself for all 7; map types
  `3`, `2`, `1`). Inside The Deadmines `GetBestMapForUnit` returned `nil`.
- **`UnitFactionGroup("npc")` returned `"Alliance", "Alliance"` for all 7 innkeepers**
  (readable, not hidden), and nothing for neutral NPCs (the beta's Calmbreeze, neutral in
  `Data/Inns`, among them). A Horde innkeeper hasn't been read
  ([§8](#8-in-client-checks-for-the-maintainer) item 6).
- The probe stored option fields as strings, so **the raw Lua type of an option's `icon`
  is not yet seen**; retail documents it as a number (a file ID). This spec accepts only
  the number ([§3.3](#33-recognizing-an-innkeeper)); [§8](#8-in-client-checks-for-the-maintainer)
  item 1 confirms it.

---

## 1. Problem

`Data/Inns` is filled by hand from one player's walk (#12), so for a long time the AddOn
won't know every innkeeper: a whole faction's inns, Forever's new zones, a replaced NPC.
At an innkeeper it doesn't know, the AddOn does nothing: no button, no trace. Every
player who rests at such an inn is a witness that it exists, and the client already
tells the AddOn everything needed to add it (the NPC ID, the map IDs, the faction).
This slice lets the AddOn **note** those innkeepers silently, on the player's own
machine, and carry the notes in the export string the player chooses to copy. A note is
a claim, not proof, but many independent claims make inn data that can be checked and
added to `Data/Inns`.

## 2. Scope

**In:**
- `InnNotes.lua` (new, **pure**): recognizing an innkeeper from the gossip options, the
  zone and continent from a map chain, the note rule, the saved record (read, normalize,
  add, dedupe, cap, prune), the list the export carries ([§3.2](#32-innnotes-api)–[§3.6](#36-pruning-when-the-data-learns-an-innkeeper)).
- `Notes.lua` (new glue): one event frame on `GOSSIP_SHOW`, the client reads
  (hidden-value checked), writing the record, `Notes:Prune()` and `Notes:List()`
  ([§3.7](#37-noteslua-the-glue)).
- `Ledger.lua`: `Ledger.npcFromGUID(guid)`, the creature-GUID parse that
  `innFromNpcGUID` now calls (one copy of the GUID rule).
- `Export.lua`: the optional `notes` field ([§4.2](#42-export-the-notes-field-added-to-v1)).
- `Core.lua`: `Notes:Prune()` at login; `notes` in `Core:ExportString`.
- `BookView.lua`: the Share page's description line (DRAFT, [§3.8](#38-the-share-pages-description-draft)).
- `scripts/check-apis.sh`: `GetBindLocation` joins *gossip and innkeeper actions*.
- Wiring, tests and docs: TOC, `load.PURE` / `load` glue list, `.luacov`,
  `check-coverage.sh` (90%), `.luacheckrc` (`C_GossipInfo`, `C_Map`), the stub,
  [§6](#6-test-plan), [§4.5](#45-docs-the-implementer-updates).

**Out:**
- **Syncing notes** to anyone, in any form (decided in the ticket). No wire change.
- **A book page or any view of notes,** and any chat line when a note is made
  ([§3.10](#310-rejected-alternatives); [Open questions](#open-questions-maintainer) 1–2).
  The in-client check reads SavedVariables and the debug log instead.
- **Hearthstone bind data:** the bind location, binding, confirming a bind, or selecting
  any gossip option. Read only.
- **Any free text from the client:** the NPC's name, the gossip text, an option's text,
  the zone, subzone or minimap text. Notes hold integers and one two-value token.
- **The player's position** on the map (coordinates).
- **Camps** and any non-creature gossip (game objects): their GUIDs fail the creature
  pattern. Inns only (the scope guard).
- **Importing or decoding notes in the AddOn,** or turning notes into `Data/Inns`
  records: that is done by hand, outside the client, from many exports.
- Updating a stored note on a later visit (first note wins, [§3.5](#35-the-saved-record)).

## 3. Approach

### 3.1 Pieces and load order

| Piece | Kind | Holds |
|---|---|---|
| `InnNotes.lua` | **pure** (new) | every rule: recognition, place from a map chain, the note, the record, dedupe, cap, prune, the export list |
| `Notes.lua` | glue (new) | the `GOSSIP_SHOW` frame, client reads, record writes, `Prune`, `List`, debug lines |
| `Ledger.lua` | pure | new `Ledger.npcFromGUID` |
| `Export.lua` | pure | the `notes` field (validated with `InnNotes.validNote`) |
| `Core.lua` | glue | `Notes:Prune()` at login; `notes` into `ExportString` |

- **TOC:** `InnNotes.lua` goes **after `Cosmetics.lua` and before `SyncProtocol.lua`**,
  so `Export.lua` (later) can read its rule and limit. It asserts `ns.Ledger` and
  `ns.Collection` at load and reads `Ledger.LIMITS` (`innMax`, `tMin`, `tMax`) and
  `Collection.LIMITS.mapKeyMax`. `Notes.lua` goes **after `Sign.lua`** in the glue block.
  `load.PURE` gains `{ path = "InnNotes.lua", name = "InnNotes" }` in the same place;
  the glue list gains `{ path = "Notes.lua", name = "Notes" }` after `Sign`. `.luacov`
  includes `"InnNotes$"`; `scripts/check-coverage.sh` gets `InnNotes.lua 90`.
- **Why a pure module:** the `SignFlow` split again. Recognition, the map walk, the
  record's normalize pass and the cap are exactly what should run in the strict
  environment under a coverage floor; `Notes.lua` keeps only events and client reads.
- **Why a separate glue file, not `Sign.lua`:** its own event frame and its own guard,
  so a fault in noting can never touch the Sign or Read buttons, and `Sign.lua` stays
  unchanged. Two frames on `GOSSIP_SHOW` is ordinary.

### 3.2 `InnNotes` API

All functions are pure and **never throw** on any argument (each body in `pcall`, its
failure value returned). Arguments are read with `rawget` and raw `next`, never `pairs`,
`ipairs` or `#` on caller tables; no metamethod of an argument runs. "Integer" means
`type(x) == "number" and x == x and x % 1 == 0` plus the range.

| Name | Value / returns |
|---|---|
| `InnNotes.VERSION` | `1` (the saved record's `v`) |
| `InnNotes.BINDER_ICON` | `132052` |
| `InnNotes.MAP_TYPE` | `{ world = 1, continent = 2, zone = 3 }` (a copy; `Enum.UIMapType`'s values, seen in live) |
| `InnNotes.LIMITS` | `{ max = 200, readMax = 1000, optionsMax = 32, chainMax = 8 }` (a copy) |
| `InnNotes.isInnkeeper(icons)` | `true` if any of the first `optionsMax` items of the array `icons` is exactly the number `BINDER_ICON`; else `false` ([§3.3](#33-recognizing-an-innkeeper)) |
| `InnNotes.place(chain)` | `zone, continent` (two map IDs) or `nil` ([§3.4](#34-the-zone-and-continent)) |
| `InnNotes.validNote(n)` | boolean: the note rule of [§4.1](#41-savedvariables-the-notes-record) |
| `InnNotes.observe(s, inns)` | a new note, or `nil, reason` ([§3.5](#35-the-saved-record)) |
| `InnNotes.read(rec, inns)` | `{ items = <array>, writable = bool, dropped = n }` ([§3.5](#35-the-saved-record)) |
| `InnNotes.add(items, note)` | `result, items2`: `"added"` with a new array, or `"dup"` / `"full"` / `"invalid"` with `nil` |
| `InnNotes.record(items)` | a fresh `{ v = 1, items = { <copies> } }` |
| `InnNotes.list(rec, inns)` | `read(rec, inns).items` (fresh copies), or `{}` when the record isn't readable |

`inns` is the `Data/Inns` table (`ns.Data.Inns`); a non-table counts as empty (so every
NPC counts as unknown, which only notes more, never signs anything).

**Known vs unknown:** an NPC ID is **known** when `rawget(inns, id) ~= nil`: any record,
a primary or an alias, whether or not `Collection.bind` kept it. That is the test
`SyncProtocol` uses for an entry's `inn`. Only unknown innkeepers are noted.

### 3.3 Recognizing an innkeeper

An NPC is an innkeeper when **one of its gossip options carries the binder icon,
`132052`** (the option *Make this inn your home.*, whatever the client's language):
- read from `C_GossipInfo.GetOptions()` at `GOSSIP_SHOW`; the glue copies each option's
  `icon` (hidden-checked) into a plain array, at most `optionsMax` (32) of them, and
  `isInnkeeper` looks for the number `132052`;
- **never by `gossipOptionID`** (it differs per innkeeper, see the facts above), never by
  the option's text (localized), never by its position, never by the NPC's name;
- a string `"132052"`, `132052.0001`, `NaN` or a table is not the icon (exact number
  only; [§8](#8-in-client-checks-for-the-maintainer) item 1 confirms the client's type);
- **the NPC must be a creature:** `Ledger.npcFromGUID(UnitGUID("npc"))` gives an ID.
  A game object (a camp's fire, a mailbox) or a player has no creature GUID and is never
  noted.

Nothing is selected, confirmed or clicked. Reading the option list is all.

### 3.4 The zone and continent

The same rule #12's walk uses for `Data/Inns`'s keys
([collection-cosmetics.md §3.1](collection-cosmetics.md#31-places-inns-zones-continents)),
so a note's `zone` and `continent` are the same kind of key as `Data.Zones` and
`Data.Continents` (and as `collection.byZone` / `byContinent` in the export):

- **The chain** (glue): `id = C_Map.GetBestMapForUnit("player")`; then, at most
  `chainMax` (8) times, `info = C_Map.GetMapInfo(id)` → one item
  `{ id = info.mapID, type = info.mapType, parent = info.parentMapID }`, then
  `id = info.parentMapID`. It stops at a non-integer or `0` id, a missing `info`, a
  hidden value, or 8 items. The player stands within a few yards of the innkeeper, so
  the player's map is the innkeeper's.
- **`place(chain)`** (pure): walk the items in order, stopping at the first item that
  isn't a table with integer `id` (1..`mapKeyMax`) and integer `type`, or at an `id`
  already seen (a loop):
  - the **zone** is the first item with `type == 3` (Zone). Items below it (Dungeon 4,
    Micro 5, Orphan 6, a building's own map) are skipped. An item of type World (1),
    Continent (2) or Cosmic (0) **before** any zone → `nil` (no zone; no note);
  - the **continent** is the first item **after** the zone with `type == 2`
    (Continent), or, if an item with `type == 1` (World) comes first, that World map
    (Zephras Isle 2521 → Azeroth 947). Cosmic (0) or the end of the chain first →
    `nil`;
  - `zone == continent` → `nil` (one map, one role).
- **A capital city is its own zone** (it is a Zone-type map), as in the data.
- **No zone, no note.** In a dungeon (`GetBestMapForUnit` is `nil`) or wherever the
  chain doesn't read, nothing is recorded; the next talk tries again. So every stored
  note has both map IDs, and a consumer can always place it.

### 3.5 The saved record

**`observe(s, inns)`**, where the situation `s = { npc, now, icons, chain, faction }` is
what the glue read ([§3.7](#37-noteslua-the-glue)), checks in this order, stopping at
the first failure:

| # | Check | Reason |
|---|---|---|
| 1 | `id = Ledger.npcFromGUID(s.npc)` is not `nil` | `npc` |
| 2 | `rawget(inns, id) == nil` | `known` |
| 3 | `isInnkeeper(s.icons)` | `not_innkeeper` |
| 4 | `s.now` is an integer in `tMin`..`tMax` | `clock` |
| 5 | `zone, continent = place(s.chain)` is not `nil` | `place` |

On success: `{ npc = id, t = s.now, zone = zone, continent = continent, faction = f }`,
with `faction` present only when `s.faction` is exactly `"Alliance"` or `"Horde"`. The
result passes `validNote`.

**`read(rec, inns)`**, the book's `readPrefs` rules ([book.md §3.7](book.md#37-the-share-tab-and-the-saved-record)):
- `rec == nil` → `{ items = {}, writable = true, dropped = 0 }` (nothing saved yet).
- `rec` not a table → `writable = false`, no items (damaged; never overwritten).
- `rawget(rec, "v")` an integer above 1 → `writable = false`, no items (a newer AddOn
  wrote it; read nothing, write nothing, export nothing).
- `v == 1`: **normalize** `rawget(rec, "items")` (a non-table counts as empty): read
  items `1, 2, …` with `rawget` until the first `nil` or `readMax` (1 000) items; keep
  each that passes `validNote` **and** whose `npc` is unknown (§3.2); a later item with
  an `npc` already kept is dropped (first in index order wins); sort by `(t, npc)`
  ascending; keep the first `max` (200), so the oldest notes stay. Kept items are fresh
  copies with only the five keys. `dropped` counts every item read and not kept, plus 1
  if items remained unread past `readMax`. `writable = true`.
- any other `v` (missing, `0`, a string, `1.5`) → `writable = true`, no items, `dropped =
  1` (a broken record is replaced by the next write, as the book's is).

**`add(items, note)`** over a `read` result's `items`: `note` failing `validNote` →
`"invalid"`; an item with the same `npc` → `"dup"` (**first note wins**: a later visit
never changes it); `max` items already → `"full"` (**new notes are dropped at the cap;
nothing is evicted**); else `"added"` and a new array with copies of every item and the
note, sorted by `(t, npc)`. The caller's array is never modified.

**`record(items)`** → `{ v = 1, items = <copies of the valid items, in order> }`: the only
shape ever written.

**Why these numbers:** `max` 200 is about twice the number of innkeepers a classic-era
world plus Forever's new zones is likely to hold, and a note lasts only until the data
learns its innkeeper (§3.6), so an honest record stays far below it. 200 notes are about
17 KB serialized and a few KB in the export ([§4.3](#43-size)). `readMax` bounds the work a
tampered file can cause. `optionsMax` and `chainMax` bound the client reads (an
innkeeper shows 2–3 options; a chain is 3–5 maps deep).

### 3.6 Pruning when the data learns an innkeeper

A noted NPC is never also in `Data/Inns`: `observe` refuses known NPCs, and when a later
AddOn version adds that innkeeper to the data (`Data/Inns` only ever grows after the
first release), its note goes away **three ways**, so it can't leak:
1. **`read` drops it** (it is now known), so neither the export nor `add` ever sees it.
2. **At login** `Core:OpenLedger` calls `pcall(ns.Notes.Prune, ns.Notes)` after the
   unlock recording (for any opened ledger, read-only or not: the notes record has its
   own version). `Notes:Prune()` reads the owner's record; when it is `writable`, a
   table, and `dropped > 0`, it writes `record(read.items)` back. So the saved file
   sheds stale notes once per data update. An error is one debug line,
   `notes: error in prune`; opening the ledger and starting `Sync` never depend on it.
3. **`Export.build` keeps no key outside its table** and takes notes only from
   `Notes:List()`, which is `read` again.

### 3.7 `Notes.lua`: the glue

**Reads** (each in `pcall`, with the same local `hidden(v)` as `Sign.lua`: an
`issecretvalue` that raises counts as hidden), each checked **before** anything else
touches the value:
- `npc = UnitGUID("npc")`: hidden or not a string → `nil`.
- `icons`: `C_GossipInfo` a table and `GetOptions` a function, else `{}`. `opts =
  C_GossipInfo.GetOptions()`: hidden or not a table → `{}`. For `i = 1..optionsMax`:
  `o = opts[i]` (inside the `pcall`), stop at `nil`; `o` hidden or not a table → skip;
  `icon = o.icon`; hidden → skip; else `icons[#icons + 1] = icon` (any type: the pure
  side checks). Nothing else of an option is read (no `name`, no `gossipOptionID`).
- `chain` as in [§3.4](#34-the-zone-and-continent): `C_Map` a table with both
  functions, else `{}`; every returned value hidden-checked; `mapID`, `mapType` and
  `parentMapID` read from `info` only (no `name`).
- `faction = UnitFactionGroup("npc")` (first return): hidden or not a string → `nil`.
- `now = GetServerTime()`: hidden → `nil`.
- the owner: `ledger = ns.ledger` (read at use, never cached); `guid =
  ledger:ownerGUID()` must pass `Ledger.validGUID`, else stop.

**`GOSSIP_SHOW`** → guarded `Notes:Seen()`:
1. No ledger or no valid `guid` → stop.
2. `npc` read; `id = Ledger.npcFromGUID(npc)`; `nil`, or `rawget(ns.Data.Inns, id) ~=
   nil` → stop (every known innkeeper and most NPCs stop here, before any other read).
3. The record: `g = ns.Core.db.global` (a table, else stop); `all = g.notes`
   (`nil` or a table, else stop: a damaged `notes` table is never overwritten); `rec =
   all and all[guid]`; `r = InnNotes.read(rec, ns.Data.Inns)`; not `writable` → debug
   `notes: read-only`, stop.
4. Read `icons`, `chain`, `faction`, `now`; `note, why = InnNotes.observe(s, ns.Data.Inns)`.
   `nil` → debug `notes: <why>` only for `clock` and `place` (an ordinary NPC's
   `not_innkeeper` is silent), stop.
5. `res, items = InnNotes.add(r.items, note)`. `"added"` → `g.notes = all or {}`;
   `g.notes[guid] = InnNotes.record(items)`; debug `notes: noted <npc>`. `"full"` →
   debug `notes: full`. `"dup"` → nothing.

`GOSSIP_SHOW` repeats while the frame is open; the second time is a `"dup"`.

**`Notes:Prune()`** ([§3.6](#36-pruning-when-the-data-learns-an-innkeeper)) and
**`Notes:List()`**: `List` returns `InnNotes.list(rec, ns.Data.Inns)` for the owner's
record, or `{}` with no ledger, no valid GUID or no readable `global`/`notes`. Both are
guarded; `List` never writes.

**Output:** debug lines only, through `ns.Core:Debug` (our own codes and an integer NPC
ID; never a client string). **Nothing is printed to chat** with the debug log off.
**Guards:** every handler runs in `pcall`; an error is one debug line `notes: error in
<where>` (never the error's text); nothing reaches the player as a Lua error.
**Combat:** no combat data or state is read; the frame registers `GOSSIP_SHOW` only.
**No hooks, no gossip actions:** events only.

**For tests:** `Notes.frame` (the event frame) is a readable field.

### 3.8 The Share page's description (DRAFT)

The export now holds more than the Share page says it does, and a player should know
what they copy. `BookView.TEXT.shareInfoText` becomes (DRAFT, the maintainer's wording):

> Your signatures, the inns you've collected, the cosmetics you've earned and any
> innkeepers you've met that the ledger doesn't know yet. Other travelers' signatures
> are theirs: they're left out unless you tick the box.

Nothing else in the book changes. The layout checks (`spec/layout_spec.lua`) must still
pass with the longer text; if the right page's text block overflows, the implementer
reports the measured height rather than shrinking the font.

### 3.9 `Ledger.npcFromGUID`

`Ledger.npcFromGUID(guid)` → the NPC ID of a creature GUID, or `nil`; never throws. Its
body is today's `innFromNpcGUID` parse: inside `pcall`, `guid` a string matching
`^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-%x+$`, the ID 1..7 digits with no leading zero.
`innFromNpcGUID(guid, inns)` becomes `npcFromGUID(guid)` then the `inns` check, with
unchanged results. The API table of [sync-ledger.md §4.5](sync-ledger.md#45-ledger-api)
gains its row.

### 3.10 Rejected alternatives

- **Notes inside the ledger's saved table** (`ledgers[guid].notes`): a schema bump to 2
  and a migration of every player's ledger for data the ledger doesn't use, and a
  damaged note would make the whole ledger read-only. A separate versioned record, like
  the book's, costs nothing.
- **Recognizing by `gossipOptionID`:** it differs per innkeeper (five IDs seen).
  **By the option's text or the NPC's name:** localized. **By position in the list:** it
  varies.
- **Recording the NPC's name, the subzone or minimap text:** free client text in
  SavedVariables and the export (localized, unbounded, a text-safety surface), and the
  NPC ID already identifies the innkeeper; names come from the data.
- **Recording the player's coordinates:** not needed to add an inn, and more personal
  than a zone.
- **A note without a zone:** a consumer couldn't place it; waiting for the next talk is
  free.
- **Updating a note on later visits** (latest time, a better map read): more writes and
  rules for no consumer gain; the first observation is the claim.
- **Evicting the oldest note at the cap:** churn, and the first-seen claims are the
  useful ones. At the cap the data is badly out of date, and a data update prunes.
- **`notes` always present, even empty:** every existing export would change bytes (the
  golden `GOLDEN_F` would break) for no information the `addon` field doesn't give.
- **Opt-in per export, like travelers:** notes hold no other player's data; they're the
  player's own observations, like their entries ([Open questions](#open-questions-maintainer) 3).
- **Syncing notes:** decided against in the ticket.
- **A book page, or a chat line per note:** player-facing wording is the maintainer's,
  and nothing in this slice needs it; the debug log and SavedVariables serve the
  in-client check (Open questions 1–2).
- **The glue inside `Sign.lua`:** a fault in noting could then reach the Sign button's
  handler; a separate frame keeps them apart.
- **Excluding NPCs `Collection.bind` rejected from "known":** those are data bugs a CI
  test already keeps out; `rawget` matches `SyncProtocol`'s rule.
- **`UnitReaction("npc", "player")`** as faction: it is the player's standing, not the
  inn's side.

## 4. Data model changes

### 4.1 SavedVariables: the notes record

A new table in `InnkeepersLedgerDB.global`, **separate from the ledger** (whose schema
stays 1) and from the book's record:

```lua
InnkeepersLedgerDB.global.notes = {
  [<owner GUID>] = {          -- Ledger.validGUID; the GUID the ledger was opened for
    v = 1,                    -- this record's version
    items = {                 -- (t, npc) ascending, npc unique, at most 200
      { npc = 3934, t = 1793800000, zone = 1438, continent = 1414 },
      { npc = 2352, t = 1793801000, zone = 1424, continent = 1415, faction = "Horde" },
    },
  },
}
```

**The note rule** (`InnNotes.validNote(n)`): a table with exactly the keys `npc`, `t`,
`zone`, `continent` and optionally `faction` (checked with raw `next`); `npc` an
integer in 1..`innMax` (9 999 999); `t` an integer in `tMin`..`tMax`; `zone` and
`continent` integers in 1..`mapKeyMax` (999 999) with `zone ~= continent`; `faction`
absent or exactly `"Alliance"` or `"Horde"`.

- **Migration:** none. The table is new: a missing `notes` or a missing record reads as
  "nothing saved" and is created on the first note. A damaged `notes` table or record
  (not a table) is never overwritten; a newer record (`v > 1`) is neither read, written
  nor exported; a broken v1 record is replaced whole by the next write (§3.5). A future
  v2 adds migration steps with its own spec.
- **Bounds:** at most 200 items of five small fields (~20 KB at worst per character),
  written only for the logged-in owner's GUID, only from that client's own gossip reads.
  Nothing from another player reaches it.
- **Per character,** like the ledger: the export is a character's.

### 4.2 Export: the `notes` field (added to v1)

The format stays **v1** (`!IL1!`, `v = 1`): fields are only added, and a v1 decoder
ignores fields it doesn't know. One new row in [export-format.md → Data (v1)](../export-format.md#data-v1)
and in [export.md §4.1](export.md#41-the-v1-data-table):

| Field | Lua type | Range / form | Meaning | Source (glue) |
|---|---|---|---|---|
| `notes` | array, optional | **present only when at least one note exists**; 1..200 items; `(t, npc)` ascending; `npc` unique | innkeepers the player talked to whose NPC ID wasn't in the exporting AddOn's `Data/Inns` (added 2026-11, #157) | `Notes:List()` |
| `notes[i]` | table | `{ npc = 1..9 999 999, t = time, zone = 1..999 999, continent = 1..999 999, faction? }`; `zone ~= continent`; `faction` `"Alliance"` / `"Horde"`, optional | one note: the innkeeper's NPC ID, when it was first noted, the zone and continent map IDs where the player stood (the same rule and kind of key as `Data/Inns`'s `Zones` / `Continents` and `collection.byZone` / `byContinent`), and the faction the client reported for the innkeeper, absent when it reported none (a neutral NPC) or it couldn't be read | |

**`Export.build`** gains, after `travelers` in §3.5's order:
- `input.notes` **present and not a table → `nil, "notes"`** (the `travelers` rule).
- Items read with `rawget(t, i)` until the first `nil`; **more than `LIMITS.notesMax`
  (200) items read → `nil, "too_large"`** (read one past; never a partial export).
- An item failing `InnNotes.validNote` is left out; a later item with an `npc` already
  kept is left out; kept items are fresh copies, sorted `(t, npc)` ascending.
- **No kept item → no `notes` key.** `input.notes == nil` → no `notes` key.
- `Export.LIMITS` gains `notesMax = InnNotes.LIMITS.max` (`Export.lua` asserts
  `ns.InnNotes` at load).
- `build` does not check `npc` against `Data/Inns` (it takes no data tables);
  `Notes:List()` already left known NPCs out ([§3.6](#36-pruning-when-the-data-learns-an-innkeeper)).

**`Core:ExportString`** gains, after step 6: `notes` = `ns.Notes:List()` inside its own
`pcall`; an error or a non-table → `nil` (the export still succeeds, without notes).
Notes are **in every export, not opt-in** (they hold no other player's data); a
read-only ledger exports them too.

**For a consumer** (export-format.md gets these as a *Notes* paragraph and a line in
*Trust*):
- **A note is an unsigned claim** by whoever made the string, which can be edited or
  forged. It proves nothing on its own: count how many independent players report the
  same `npc` in the same `zone`, and check against the game before adding an inn.
- **A note never names an inn already in the data the exporting AddOn had.** A
  consumer whose data is newer will see notes for innkeepers it already knows; ignore
  those (match on `npc`).
- **An `npc` may be an alias** (a second innkeeper of a known inn) or a whole new inn;
  the note can't tell which.
- `faction` is the innkeeper's own faction as the client reported it, a hint about who
  can use the inn, not proof; absent means neutral **or** unreadable.
- A `t` after `exported` (beyond a few minutes' clock skew) means the string was edited.
- Notes carry no text, so nothing in them needs escaping to display; render only what
  your own data names.

### 4.3 Size

One note serializes to about 85 bytes (`^T^Snpc^N…^St^N…^Szone^N…^Scontinent^N…
^Sfaction^SAlliance^t` plus its array key), so 200 notes are about 17 KB serialized and
a few KB of the string. The implementer **measures** two new rows in
`spec/export_spec.lua` (as export.md §3.10 did) and records them in export.md §3.10 and
export-format.md → Size:

| Case | Hard ceiling |
|---|---|
| L + 200 notes (default, no travelers) | 32 KiB string |
| Every `build` limit at once, now with 200 notes, longest fields | `serializedMax` (4 MiB serialized); test ceiling stays 2 624 KiB unless the measurement needs more, which is then reported |

A measurement over a hard ceiling is a design problem: stop and report it.

### 4.4 Formats and other modules

- **Wire format:** unchanged (v1). Nothing new is sent; `Sync.lua` is untouched.
- **`Ledger` SavedVariables schema:** unchanged (1). `Ledger` only gains
  `npcFromGUID`.
- **`docs/data/forever.json`:** unchanged (notes are not data).

### 4.5 Docs the implementer updates

- [export-format.md](../export-format.md): the two rows of §4.2 in *Data (v1)*; the
  consumer points of §4.2 under *Notes* and one line in *Trust*; the limits sentence
  gains "200 notes"; *Size* gains the measured rows; *Privacy*: "By default the export
  contains only your own signatures, collection and notes on innkeepers you met."
- [export.md](export.md): §4.1's rows, §3.5's notes rules, §3.6's `notesMax`, §3.7's
  step, §3.10's rows; an *Amended 2026-11 (#157)* line under Status.
- [architecture.md](../architecture.md) → Modules: `InnNotes` (pure) and `Notes` (glue)
  rows linking this spec; → Export: "notes on unknown innkeepers are in every export".
- [sync-ledger.md §4.5](sync-ledger.md#45-ledger-api): the `npcFromGUID` row.
- [security-checklist.md](../security-checklist.md): *Gossip and innkeeper actions*
  names reading the bind location too; release item 10 becomes "the export string gained
  no data beyond the player's own ledger **and own notes**, and `travelers` appears only
  when the player opts in".
- [platform-forever.md](../platform-forever.md): the facts listed at the top of this
  spec (after #12's branch is on `dev`), and §8's checks on the checklist.
- [testing.md](../testing.md): the stub's `C_GossipInfo` and `C_Map`.
- [status.md](../status.md): notes built; §8 in the in-client batch; the Share line under
  Open questions.
- [decisions.md](../decisions.md): one entry, *Inn notes: the binder icon, a separate
  record, first note wins, 200 and no eviction, `notes` in every export* with §3.10's
  rejections, and a line on `GetBindLocation` joining the forbidden list (the script
  header asks for a decision entry on rule changes).
- `CHANGELOG.md`: one line under `## Unreleased` when it merges.
- `CLAUDE.md`'s context map: this spec's row (added with the spec).

## 5. Security notes

**Flag for the reviewer: security-level review of the client reads, the record's
normalize pass, `build`'s `notes` handling and the forbidden-API change.**

- **No peer data, no sync.** Notes come only from this client's own reads at
  `GOSSIP_SHOW`. `Notes.lua` names no addon-message or channel API; nothing in a note
  is ever sent. A test asserts `Sync`'s send spy sees nothing after noting.
- **Read only, nothing chosen.** No gossip option is selected, no bind is confirmed, the
  bind location is never read. **`check-apis.sh`:** `GetBindLocation` joins *gossip and
  innkeeper actions* (allowed nowhere). It narrows the list (no allow-list widens); the
  decision entry records it. Shipped comments must not name it (say "the bind
  location").
- **Hidden values** ([sync-ledger.md §5.2](sync-ledger.md#52-hidden-secret-values-and-identity)):
  every client value (the GUID, the options table, each option and its icon, each map
  value, the faction, the time) is hidden-checked **before** it is compared, indexed,
  concatenated or stored; a hidden value is a skip or a `nil`, never a guess.
  `npcFromGUID` runs its parse in `pcall`.
- **Only integers and one token are stored or exported.** The note rule admits five
  keys: four bounded integers and `faction` in a two-value set. No client string (name,
  text, zone name) is stored, exported or printed; debug lines carry our codes and an
  integer. So no `|` escape, URL or hidden character can enter through a note.
- **Bounded storage and work.** At most 200 notes per character, deduped by NPC ID,
  no eviction churn; `read` reads at most 1 000 items of a tampered file; the gossip
  read takes at most 32 options and 8 map steps; nothing recurses into caller tables.
- **Tampered SavedVariables.** A non-table `notes` or record is never overwritten; a
  newer record is untouched; a v1 record is normalized (invalid, duplicate, known and
  over-cap items dropped) before use, so a tampered file can at most lose its own
  notes. `build` re-checks every note anyway and fails closed (`too_large`, or the item
  left out).
- **Privacy boundary.** Notes are the player's own observations: which unknown
  innkeepers they met, where and when. That is the same kind of data their own entries
  already export (inn, time), so notes are in the default export, and the Share page
  says so (§3.8, DRAFT). No other player's GUID or name can be in a note (no string
  field exists for one). The export privacy walk (§6.4) runs with notes present.
- **Forgeable by design.** Notes are unsigned claims; export-format.md tells consumers
  so (§4.2).
- **Policy.** No new text names a site, product or consumer; `no-urls-in-game-code`
  stays green.
- **Quiet failure.** Every handler is guarded; nothing prints with the debug log off.

## 6. Test plan

busted; `InnNotes.lua` loaded with `Ledger.lua` and `Collection.lua` in the strict pure
environment; fixed times (`T = 1790000000`), never the clock. Coverage ≥ 90% for
`InnNotes.lua`; `Ledger.lua` stays ≥ 95%. Fixture inns: a `places.lua` table with NPCs
`5001` (primary) and `5003` (alias); `npcGUID(id)` as in sign.md §6.1. Hidden-value
stand-ins as in sync-ledger.md §5.2.

### 6.1 `spec/ledger_spec.lua` (additions)

- `npcFromGUID`: `Creature-0-4615-2991-62-254089-0000ABCDEF` → `254089`; `295`; a
  7-digit ID; an 8-digit ID, a leading zero, `Player-…`, `Pet-…`, `GameObject-…`,
  `Vehicle-…`, a missing spawn field, `""`, a number, a table, `nil`, both stand-ins →
  `nil`, no throw.
- `innFromNpcGUID`'s existing cases pass unchanged.

### 6.2 `spec/inn_notes_spec.lua` (pure)

- **Load:** raises without `ns.Ledger` or `ns.Collection`; loads in the strict
  environment; `LIMITS`, `MAP_TYPE` are copies (changing them changes nothing).
- **`isInnkeeper`:** `{132053, 132060, 132052}` and the icon first, middle, last →
  `true`; `{}`; `{132053}`; `"132052"`; `132052.5`; `NaN`; `{ {132052} }`; the icon at
  position 33 → `false`; a hole before the icon (reading stops) → `false`; a non-table,
  a table with raising metamethods, a stand-in → `false`, no throw.
- **`place`:** live's chain `{ {1437,3,1415}, {1415,2,947}, {947,1,0} }` → `1437, 1415`;
  Zephras Isle `{ {2521,3,947}, {947,1,0} }` → `2521, 947`; a Micro and a Dungeon map
  below the zone → skipped, same result; a Continent first (no zone) → `nil`; a World
  first → `nil`; zone then Cosmic (0) → `nil`; zone then end → `nil`; zone with no
  continent above but a second Zone then a Continent → the first zone and that
  continent; a loop (an `id` repeated) → stops, `nil` if no continent yet; `zone ==
  continent` → `nil`; ids `0`, `1000000`, `1.5`, `NaN`, a string, a missing `type` →
  stops there; more than 8 items: only the first 8 are used; `{}`, `nil`, stand-ins →
  `nil`.
- **`validNote`:** a full note and one without `faction` → `true`; each key out of range
  (`npc` 0, 10 000 000, `t` `tMin - 1`, `tMax + 1`, `zone` 0, 1 000 000, `zone ==
  continent`, `faction` `"Neutral"`, `"alliance"`, `""`), each wrong type, a missing key,
  an extra key, a non-table, a raising metatable → `false`.
- **`observe`, one case per row of §3.5 and the order:** a malformed or hidden GUID →
  `npc`; a known primary and a known alias → `known` (even with the binder icon); no
  binder icon → `not_innkeeper`; `now` `nil`, `NaN`, `1.5`, out of range → `clock`; an
  unreadable chain → `place`; all good → the note, `faction` kept for `"Horde"`, absent
  for `nil`, `""`, `"Neutral"`, a number; a non-table `inns` → every creature counts as
  unknown.
- **`read`:** `nil` → empty, writable; a string → not writable; `v = 2` with valid items
  → not writable, no items; `v` missing, `0`, `"1"`, `1.5` → empty, writable, `dropped =
  1`; `v = 1` with: invalid items (each kind) → dropped and counted; a duplicate `npc`
  with a different `t` → the first by index kept; a known `npc` (in fixture `inns`) →
  dropped (the prune); shuffled items → sorted `(t, npc)`; 250 valid items → the 200
  oldest; 1 001 items → `dropped` counts the unread rest as 1, no more than 1 000 read;
  a hole stops the read; `items` not a table → empty; returned items are copies (no
  table `rawequal` to an input table); the input is deep-equal before and after;
  metamethods on `rec` and items never fire.
- **`add`:** to an empty list → `"added"` and a one-item array; the same `npc` again
  with a later `t` → `"dup"`, nothing changed; 200 items then a new one → `"full"`; an
  invalid note → `"invalid"`; the result is sorted and the input array unchanged.
- **`record`:** `{ v = 1, items = copies }`, nothing else; invalid items in its input
  are left out.
- **`list`:** equals `read(rec, inns).items`; `{}` for a not-writable record.
- **Never throws:** every function with each argument replaced by `nil`, a number, `NaN`,
  a string, a raising table and both stand-ins.

### 6.3 `spec/notes_spec.lua` (the glue, whole AddOn under the stub)

Logged in as `spec/core_spec.lua` does. Stub additions: `C_GossipInfo.GetOptions`
(returns `wow.gossipOptions`, default `{}`), `C_Map.GetBestMapForUnit` and
`C_Map.GetMapInfo` over a `wow.maps` table (default: `1437 → 1415 → 947` types 3, 2, 1),
`UnitFactionGroup("npc")` overridable separately from `"player"`.
- **Unknown innkeeper:** NPC `3934`, options `{ {icon=132053}, {icon=132052} }`,
  `UnitFactionGroup("npc")` → `"Horde"` → after `GOSSIP_SHOW`,
  `db.global.notes[guid]` deep-equals `{ v = 1, items = { { npc = 3934, t = wow.now,
  zone = 1437, continent = 1415, faction = "Horde" } } }`; with debug on, one line
  `notes: noted 3934`. A second `GOSSIP_SHOW` → still one item, no line.
- **Known innkeeper** (`254089` from the real data, with the binder icon) → no `notes`
  table is created; `C_GossipInfo.GetOptions` is **not called** (spy: stop at step 2).
- **Not an innkeeper** (a vendor's GUID, options without the icon) → nothing written, no
  debug line.
- **Unreadable values:** hidden GUID, hidden options table, a hidden option, a hidden
  icon, raising `GetOptions`, `C_GossipInfo` missing, `GetBestMapForUnit` → `nil`
  (a dungeon), a hidden map value, `GetMapInfo` raising, hidden or raising
  `UnitFactionGroup("npc")` (the note is kept without `faction`), hidden clock → no
  note (or no faction), no error escapes, `wow.errors` empty.
- **The record:** a damaged `notes` (a string) or record (a number) → untouched (deep
  compare), debug `notes: read-only` where it applies; `v = 2` → untouched; a broken v1
  record (`v` missing) → replaced by a valid one on the next note; 200 stored notes → a
  new one gives `notes: full`, nothing written.
- **Never sends, never selects:** after noting, `Sync`'s send spy and every gossip
  action stub (`C_GossipInfo.SelectOption`) recorded no call.
- **Login prune:** a saved record with notes for `3934` and for `295` (in the real
  data) → after login the record holds only `3934`; a record with nothing to drop is not
  rewritten (the same table, `rawequal`); `Notes.Prune` raising → the ledger still opens
  and `Sync` still starts (a `notes: error in prune` debug line); a read-only ledger
  still prunes its notes record.
- **Errors:** `InnNotes.observe` stubbed to raise → `notes: error in gossip`, nothing
  written, Sign's buttons still show at a known innkeeper in the same run.
- `spec/addon_load_spec.lua`: `ns.InnNotes` and `ns.Notes` are tables; the TOC,
  `load.PURE`, the glue list and `.luacheckrc` checks pass.

### 6.4 `spec/export_spec.lua` and `spec/core_spec.lua` (additions)

- **`build`:** F plus `notes` of three valid notes, shuffled → the `notes` key holds them
  sorted `(t, npc)`; F with `notes = {}` or all-invalid notes → no `notes` key and
  output deep-equal EXPECTED_F; `notes = "x"`, `7`, `true` → `nil, "notes"`; a duplicate
  `npc` → the first kept; each invalid note kind left out, siblings kept; 201 items →
  `nil, "too_large"` (200 pass); metamethods on `notes` and its items never fire; output
  copies are fresh.
- **Round trip:** F + notes through `Export.string` and the test-only decoder →
  deep-equal; `schemaOk` accepts the `notes` key, rejects each malformed shape (unsorted,
  duplicate `npc`, an extra key, 201 items, `faction` `"Neutral"`, an empty `notes`
  array).
- **Goldens unchanged:** `Export.string(F)` still equals `GOLDEN_F` byte for byte (F has
  no notes).
- **Size rows** of §4.3, measured and asserted, the limits row tagged `#sim`.
- **Fuzz:** §6.6's seeded fuzz mutates F + T + notes too.
- **Privacy walk** (export.md §6.4) with notes present: still no traveler GUID or name in
  the default export.
- **Glue:** after noting `3934` and two own entries, `ns.Core:ExportString()` decodes to a
  table whose `notes` is the one note; a read-only ledger's export carries it too;
  `ns.Notes.List` raising → the export still succeeds without `notes`; no notes → no
  `notes` key.

### 6.5 Book

- `spec/book_view_spec.lua`: the Share page model's text equals the new
  `TEXT.shareInfoText`; no `|`, `%` or `http` in it.
- `spec/layout_spec.lua` passes with the longer text.

### 6.6 Lint and guards

`luacheck .` clean (`C_GossipInfo` and `C_Map` added to `.luacheckrc`'s `wow` list; no
other new global); `sh scripts/check-apis.sh` passes with `GetBindLocation` added, and
the PR shows it failing on a scratch shipped file that names it (then removed);
`check-libs.sh`, `check-links.sh`, `check-coverage.sh` (`InnNotes.lua` ≥ 90%,
`Ledger.lua` ≥ 95%) and the data JSON check pass.

## 7. Acceptance criteria

- [ ] `InnNotes.lua` implements §3.2–§3.6; pure, strict environment, in the TOC between
      `Cosmetics.lua` and `SyncProtocol.lua`, in `load.PURE`, `.luacov` and
      `check-coverage.sh` at 90%.
- [ ] `Notes.lua` implements §3.7: events only, every client value hidden-checked first,
      every handler guarded, no chat output with the debug log off, no client string
      stored or printed.
- [ ] `Ledger.npcFromGUID` exists and `innFromNpcGUID` uses it, results unchanged.
- [ ] Only unknown innkeepers are noted, recognized by the binder icon alone; a known one
      (primary or alias) and a non-innkeeper are never noted.
- [ ] The record is `db.global.notes[guid] = { v = 1, items }`, at most 200, `(t, npc)`
      ascending, `npc` unique, first note wins, no eviction; damaged and newer records
      are never written; stale notes are pruned at login.
- [ ] `notes` in the export per §4.2: absent when empty, validated, sorted, capped
      (`too_large` past 200); `GOLDEN_F` unchanged; measured sizes under their ceilings.
- [ ] `export-format.md` documents the field as an addition to v1, with the consumer
      rules of §4.2; the other docs of §4.5 are updated.
- [ ] The Share page's description is the DRAFT of §3.8, listed in status.md → Open
      questions; layout checks pass.
- [ ] `GetBindLocation` is on the forbidden list; nothing selects a gossip option or
      confirms a bind; `Sync` sends nothing new.
- [ ] Every test named in §6 exists and passes (`busted` output in the PR); `busted`,
      `luacheck .`, `check-apis.sh`, `check-libs.sh`, `check-links.sh`, coverage and the
      data JSON check are green locally and in CI.
- [ ] The reviewer did a security-level review of §5 item by item and tried hostile
      client values and a tampered record of its own.
- [ ] §8's checks are on the platform-forever.md checklist and in status.md's in-client
      batch.

## 8. In-client checks (for the maintainer)

With `/ledger debug` on, in the live client; read `InnkeepersLedger.lua` from disk after
a `/reload` (it names the character: an agent summarizes it, never commits it):
1. **An unknown innkeeper records one note:** talk to an innkeeper that isn't in the
   installed `Data/Inns` (any Horde innkeeper, a new Forever zone's, or one met before
   the data had it). One line `notes: noted <id>`; after `/reload`,
   `global.notes[<guid>].items` holds one note with that NPC ID, a `zone` and
   `continent` matching the probe's chain for that NPC, and `t` about the time you
   talked. If no line shows and the probe logged the binder icon for that NPC, the
   option's `icon` isn't the number `132052` (§3.3): tell an agent.
2. **Talking to the same innkeeper again** (or closing and reopening the gossip) adds
   nothing: no second line, still one note.
3. **A known innkeeper records none:** at Lion's Pride Inn (or any inn in the data), no
   `notes:` line and no new note.
4. **A vendor or quest giver records none,** and no `notes:` line.
5. **Nothing else changes at an unknown innkeeper:** no Sign or Read button (as today),
   no chat line, the hearthstone's bind location unchanged.
6. **The faction:** at an Alliance innkeeper the note has `faction = "Alliance"`; at a
   neutral one (a goblin town's, if met) no `faction`; at a Horde one (needs a Horde
   character) `"Horde"`.
7. **Export:** `/ledger share`, copy the string into a text file for an agent: decoded
   with the test-only decoder, it holds `notes` with the same items.
8. **After a data update that adds a noted innkeeper:** the next login's file no longer
   holds that note.

## Implementation notes (2026-11-13, #157)

Choices the spec left open, made in the build:
- **Failure values** (each API body runs in `pcall`): `isInnkeeper` and `validNote` →
  `false`; `place` → `nil`; `observe` → `nil, "error"`; `read` → `{ items = {}, writable
  = false, dropped = 0 }` (fail closed: nothing is written); `add` → `"invalid", nil`;
  `record` → `nil` (the glue writes only a table); `list` → `{}`.
- **`record` and `add` keep at most 200 valid items, first per `npc`,** so the written
  shape always holds the record's invariants whatever the caller passes; `add` copies
  only its input's valid items.
- **A damaged `notes` table** (not a table) also logs `notes: read-only` at an unknown
  NPC, like a damaged or newer record; it is never overwritten either way.
- **Measured** ([§4.3](#43-size)): L + 200 notes is 16 933 chars (57 158 B serialized,
  about 78 B a note); every `build` limit with 200 notes is 2 159 948 B serialized, under
  the 2 624 KiB test ceiling. The Share page's DRAFT text wraps to 5 lines (60 high at
  the layout checks' 0.6 em) inside the 500-high page; `spec/layout_spec.lua` passes.

## Assumptions (listed for the maintainer)

- **Notes are silent:** no chat line, no book page; only the debug log shows them.
- **Notes are in every export,** not opt-in: they hold no other player's data, and the
  Share page's description says they're there (DRAFT).
- **Per character,** like the ledger and the export.
- **First note wins;** later visits change nothing. **At 200 notes new ones are
  dropped;** a data update that learns those innkeepers frees the room.
- **No zone read, no note** (in a dungeon, or wherever the map chain doesn't read).
- **`faction` is the NPC's own faction as the client reports it,** recorded only as
  `"Alliance"` or `"Horde"`; verified readable on 7 Alliance innkeepers and a neutral
  one, not yet on a Horde one.
- **"Unknown" means not a key of `Data/Inns`** (any record, alias included), the same
  test sync uses.
- **The binder icon (`132052`) marks innkeepers and nothing else that has a creature
  GUID** (7 of 7 innkeepers and 0 of 102 other NPCs in live).

## Open questions (maintainer)

None blocks the build or the merge; the DRAFT ships until answered.

1. **Should the book show your notes** (for example, a line on the Inns tab: "3
   innkeepers noted that the ledger doesn't know yet")? Not in this slice; it would be a
   follow-up with your wording.
2. **Should noting say anything in chat** (DRAFT idea: "You noted an innkeeper the
   ledger doesn't know yet.")? This slice is silent.
3. **Notes in every export, or opt-in like travelers?** This slice includes them always
   (your own observations, no other player's data). Say if you want a tick box.
4. **The Share page's description** ([§3.8](#38-the-share-pages-description-draft)):
   the DRAFT adds "and any innkeepers you've met that the ledger doesn't know yet".
   Wording yours.
