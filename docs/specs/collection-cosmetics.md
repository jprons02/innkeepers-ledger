# Spec: `Collection` and `Cosmetics`

> **Summary:** the passport underneath the ledger. The `Data/Inns` record shape (inns,
> zones, continents, keyed by NPC ID and the client's map IDs; innkeeper aliases;
> factions), the progress math (signed/total overall, by continent, by zone, per inn),
> what a stamp is, the cosmetic ID scheme and catalog shape, unlock rules and how each
> earned time is derived from your own entries, `Cosmetics.SEALS` for peer validation and
> the seal check `Sign` uses, the shapes the export carries, the tests, and the **draft**
> catalog.
> **Read when:** implementing or reviewing `Collection.lua`, `Cosmetics.lua`,
> `Data/Inns.lua` or `Data/Cosmetics.lua`; filling `Data/Inns` (#12); adding a zone or a
> cosmetic; building `Sign`'s seal choice, the book's collection view or `Export`.

**Status:** approved (self-approved 2026-09-27, ticket #63), **except the catalog**: the
cosmetics, their names and their thresholds in [§9](#9-draft-catalog-draft) are a DRAFT
and the maintainer decides them (a `CLAUDE.md` gate). They ship as written until then;
the questions are tracked in [status.md](../status.md). Nothing else here waits on them.
Amended 2026-09-30 (#76): a zone with no Continent map above it is grouped under its
World map ([§3.1](#31-places-inns-zones-continents)), and a map ID can't key both a zone
and a continent ([§3.2](#32-record-rules) rule 6). Amended 2026-10-07 (#110,
self-approved; the maintainer chose the guard): place rules count only zones,
continents and an atlas the data marks complete
([§3.11](#311-completeness-marks-amended-2026-10-07-110)).
**Security-sensitive:** moderately. `Cosmetics.SEALS` is the `seals` table of
`SyncProtocol`'s rule 16, so it decides which peer entries are stored. The reviewer
applies security-level scrutiny to [§5](#5-security-notes) and must try hostile input of
its own.

Builds on: [sync-ledger.md](sync-ledger.md) → §3.1 (`sealMax` 999, `cosmeticIdMax`
9999), §4.2 (`earned` in SavedVariables), §4.5 (`ledger:own()`, `markEarned`,
`earned()`), §5.1 rule 16 (unknown seal skips the entry);
[sync-glue.md §3.3.1](sync-glue.md#331-the-sync-instance) (`seals` = `ns.Cosmetics.SEALS`);
[phrase.md §3.7](phrase.md#37-loading-and-binding) (the bind-at-load pattern this spec
copies). **Changes none of them**: no wire format, `SyncProtocol` rule, `Ledger` behavior
or `Sync` wiring changes here.

Binding decisions: [archive/decisions-2026-09.md](../archive/decisions-2026-09.md) →
*Cosmetics are earned by play, never paid or gated*, *Inns only in v1*;
[decisions.md](../decisions.md) → *Keep the inn ledger after a pivot review* (a stamp per
inn, a seal per zone), *Profile site trust* (cosmetic times let a consumer check an
unlock came after the entries that earn it), *Ledger storage* (`earned` holds the time
each cosmetic was earned). This spec adds two 2026-09-27 entries (the implementer writes
them when the PR lands): *Collection: places, keys and faction totals* ([§3.1](#31-places-inns-zones-continents),
[§3.3](#33-progress)) and *Cosmetics: IDs, derived unlocks that are never taken away,
seals on signing* ([§3.5](#35-cosmetic-ids)–[§3.7](#37-seals-for-peers-and-for-signing)).

---

## 1. Problem

The vision's collection underneath ("X of Y inns signed, by continent and zone") is what
carries the AddOn when nobody is around to cross paths with, and the 2026-09-27 pivot
review leaned into it as a passport: a stamp per inn, a seal per zone. Nothing computes
it yet. `Collection.lua` and `Cosmetics.lua` are stubs, and `Data/Inns` is an empty table
whose record shape nobody has pinned down, so #12's in-client walk doesn't know what to
record. `Cosmetics.SEALS` doesn't exist either, so `Sync` validates peers against an empty
seal table and rejects every sealed entry. This slice defines the place data, the pure
progress math over the player's **own** signatures, the cosmetic catalog and its unlock
rules (every earned time derived from entries), the seal table peers are checked
against, and the shapes the book and the export read. It ships a draft catalog.

## 2. Scope

**In:**
- `Data/Inns.lua`: the shape of [§3.1](#31-places-inns-zones-continents), still empty:
  `ns.Data.Inns = {}`, plus new empty `ns.Data.Zones` and `ns.Data.Continents`, with a
  header comment pointing at this spec.
- `Data/Cosmetics.lua` (new): the draft catalog of [§9](#9-draft-catalog-draft) in the
  shape of [§3.5](#35-cosmetic-ids), with a DRAFT comment.
- `Collection.lua` (pure): `bind` and the atlas functions of [§3.8](#38-api).
- `Cosmetics.lua` (pure): `bind`, `SEALS`, `unlocked`, `canSeal`, `info`, `catalog`.
- `spec/collection_spec.lua`, `spec/cosmetics_spec.lua`: every case in [§6](#6-test-plan),
  on fixture tables, including the `SyncProtocol` integration.
- Small wiring: `Data\Cosmetics.lua` in the TOC after `Data\Phrases.lua`; one row in
  `load.DATA`; one test in `spec/addon_load_spec.lua`; doc touches in
  [§4](#4-data-model-changes).

**Out:**
- Filling `Data/Inns`, `Zones`, `Continents` (#12; [§8](#8-contract-for-later-slices)
  says what the walk records).
- `Sign` attaching a seal and recording unlocks, the seal and quill pickers, the
  collection view (`UI/Book`), `Export` (#64). [§8](#8-contract-for-later-slices) fixes
  what each must do.
- Counting other travelers' entries toward anything. Progress and unlocks come from the
  player's own signatures only (the collection is where *you* have been; others' entries
  are the crossing-paths layer, and counting them would make the passport tradeable).
- Camps, continents' own seals, badges as a separate kind, "home inn" or repeat-visit
  rewards, percentage thresholds, localization of place names. Not in v1 (see
  [Open questions](#open-questions-maintainer) for the ones worth asking about).
- Any change to the wire format: quills are not on the wire (only `seal` is).

## 3. Approach

### 3.1 Places: inns, zones, continents

Three tables in `Data/Inns.lua`, all keyed by integers, so nothing is ever matched by a
name (names differ per locale):

```lua
ns.Data.Continents[<continent key>] = { name = "Eastern Kingdoms" }
ns.Data.Zones[<zone key>]           = { name = "Elwynn Forest", continent = <continent key>, seal = 101 }
ns.Data.Inns[<innkeeper NPC ID>]    = { name = "Lion's Pride Inn", zone = <zone key> }                  -- neutral
ns.Data.Inns[<innkeeper NPC ID>]    = { name = "...", zone = <zone key>, faction = "Alliance" }         -- one faction
ns.Data.Inns[<innkeeper NPC ID>]    = { alias = <NPC ID of the inn's primary record> }                  -- same inn
```

- **`Data.Inns` stays keyed by innkeeper NPC ID**, because entries carry the NPC ID
  (`inn` on the wire and in storage), `SyncProtocol` checks `rawget(inns, e.inn)` and
  `Ledger.innFromNpcGUID` looks NPC IDs up in it. Every record is non-`nil`, so both keep
  working unchanged, aliases included.
- **Zone and continent keys are the client's own map IDs** (`uiMapID`), read by #12's
  walk at each innkeeper: the zone is the first map of type *Zone* walking up from
  `C_Map.GetBestMapForUnit("player")` through `C_Map.GetMapInfo(id).parentMapID`, the
  continent the first of type *Continent* above it, **or, when the chain reaches a
  *World*-type map first, that World map** (#76). The Forever beta showed why: *Zephras
  Isle* (map 2521, type Zone) hangs directly off the *Azeroth* world map (947, type World),
  with no Continent between, so its record is `Zones[2521] = { name = "Zephras Isle",
  continent = 947, … }` and `Continents[947] = { name = "Azeroth" }`. "Continent" in this
  spec, in `byContinent` and in the export means this group: a Continent map, or the
  World map such a zone sits under. A map ID is one map, so it never keys both a zone and
  a continent (3.2 rule 6). Map IDs are
  locale-independent, stable across patches, come from the client rather than a naming
  choice, and let the book localize names later from `C_Map.GetMapInfo(id).name`. A
  capital city is its own zone (it has its own map). If #12 finds map IDs unreadable, the
  walk assigns project integers instead: the scheme (integer keys defined by the data)
  doesn't change, only where the numbers come from.
- **Continent is a property of the zone,** not of the inn, so the two can't disagree.
- **Display names are English data in v1,** like phrases: `name` fields, shown as plain
  text.
- **Progress counts inns, not innkeepers.** One inn can have several innkeeper NPCs (a
  faction pair behind one counter, or an NPC Blizzard replaced with a new ID). One record
  is the inn's **primary**; the others are **aliases** that point at it (one hop only)
  and carry nothing else. An entry at an alias counts for the primary. The **inn key** is
  the primary's NPC ID. An alias is only for *the same inn*; two inns in one town are two
  inns (two stamps).
- **Faction:** `faction` is `"Alliance"` or `"Horde"` (the client's English faction
  tokens, locale-independent) for an inn only that faction can use; absent for a neutral
  inn both can use. An inn is **open to** faction `F` if it is neutral or its faction is
  `F`. With `F` unknown (`nil`), every inn is open.
- **Records are never removed after the first release.** An inn whose NPC is gone from
  the game keeps its record (entries and peers still name it); a replacing NPC becomes an
  alias of it. A zone keeps its record (and so its seal ID) even if it loses every inn.
  Removing a zone would drop its seal from `SEALS` and make peers' sealed entries fail
  rule 16 ([§5](#5-security-notes)).

### 3.2 Record rules

`Collection.bind` keeps a record only if every rule holds; anything else is **excluded**
and named in `invalid` (never raised), as `Phrase.bind` does. A CI test keeps `invalid`
empty for the real data. Validation runs in this order, so an exclusion cascades (rule 5
applies within steps 1–3, rule 6 within steps 1–2):

1. **Continents:** key an integer in 1..`mapKeyMax`; value a table with exactly `name`.
2. **Zones:** key an integer in 1..`mapKeyMax`; exactly `name`, `continent`, `seal`;
   `continent` a kept continent key; `seal` an integer in the zone-seal range 101..999
   ([§3.5](#35-cosmetic-ids)). **A seal ID used by two or more zones excludes all of
   them** (fail closed; no "first one wins" that depends on `pairs` order). The count
   includes every zone record whose `seal` is an integer in 101..999, even one excluded
   for another reason (#63).
3. **Primary inns:** key an integer in 1..`Ledger.LIMITS.innMax`; exactly `name` and
   `zone`, plus optional `faction`; `zone` a kept zone key; `faction` absent or exactly
   `"Alliance"` or `"Horde"`.
4. **Aliases:** key as for inns; exactly `alias`; `alias` the key of a kept **primary**
   (not an alias, not itself, not excluded).
5. **Names** (continent, zone, inn): a string of 1..`nameBytes` (48) bytes, every byte in
   the allow-list `A-Z a-z 0-9`, space, `'`, `,`, `.`, `-`, first byte `A-Z`, no leading
   or trailing space, no two spaces in a row. So no `|`, `%`, `\`, control bytes or bytes
   ≥ 128. Explicit byte ranges, never `%a`/`%w` (locale-dependent; sync-ledger.md §5.2).
6. **One map, one role** (#76): a key present in both `Zones` and `Continents` excludes
   **both** records, whatever either holds (even a record excluded for another reason):
   we can't tell which is wrong, and no "first one wins" depends on `pairs` order. The
   continent's exclusion cascades to its zones and their inns, as rule 2 does. This also
   catches a zone whose chain loops back to itself (its `continent` is its own key) or
   two zones that are each other's continent. A zone whose `continent` is its own key
   with no such continent record is excluded by rule 2 already.

Any non-table argument counts as an empty table. `invalid` prints only numeric keys
(`"inn 5003"`, `"zone 10"`, `"continent 2"`) and names any other key by its type
(`"inn <string>"`), so no data string is echoed.

### 3.3 Progress

`atlas.progress(own, faction)` reads **own entries only** (`ledger:own()`), for the
player's faction, and returns a new table:

```lua
{
  faction = "Alliance",        -- the faction counted, or nil (every inn open)
  signed = 4, total = 4,       -- inns open to the faction: signed / all
  done = 1790000400,           -- when the last open inn was first signed; nil unless signed == total >= 1
  byContinent = { [<continent key>] = { signed = n, total = n, done = t or nil }, ... },
  byZone      = { [<zone key>] = { signed = n, total = n, continent = <key>, done = t or nil }, ... },
  inns        = { [<inn key>] = { zone = <key>, open = true, count = n, first = t or nil, last = t or nil }, ... },
  unknown = 1,                 -- own entries whose inn isn't a kept inn or alias
  truncated = false,           -- true if more than ownMax own entries were given
}
```

- **Counting.** An own entry is read if it is a table whose raw `inn` is an integer in
  1..`innMax` and raw `t` an integer in `tMin`..`tMax`; anything else is skipped silently
  (the `Ledger` quarantines bad own entries at load, so this is defense in depth). A read
  entry maps to its inn key through aliases. If there is none, it adds 1 to `unknown`.
- **Per inn** (`inns`): every kept primary inn appears, signed or not, with `open` for the
  faction. `count` is the number of own entries there (weekly re-signing makes this more
  than 1; entries at its aliases count too), `first`/`last` the smallest and largest `t`
  (by comparison, not by input order), both `nil` when `count == 0`.
- **Totals** count inns that are **open** to the faction. An inn signed while not open
  (a faction change, if Forever has one, or a tampered file) shows in `inns` with
  `open = false` and counts nowhere else.
- **`byZone`** holds the zones with at least one open inn; `byContinent` the continents
  with at least one open inn. A zone with none (another faction's zone, a zone whose inns
  were all retired) is left out, so the book and the export never show `0 / 0`.
- **`done`** for a zone, a continent or overall: when `total >= 1` and `signed == total`,
  the largest `first` among its open inns (the moment the last one was stamped); else
  `nil`.
- **Deterministic:** the result depends only on the bound data, the set of read entries
  and the faction, never on input order or `pairs` order.
- **Work is bounded:** at most `ownMax` (100 000) entries are read with `rawget(own, i)`
  for `i = 1, 2, …` until the first `nil`; past that, `truncated = true` and the rest are
  ignored. An honest ledger holds at most one entry per inn per week, far below that.

**Why totals are per faction:** Forever keeps factions apart, and an enemy innkeeper
can't be talked to, so "every inn" over both factions could never be finished, and a
contested zone's seal (a neutral inn plus the other faction's) could never be earned. The
faction comes from the client (`Sign`/UI/Export glue passes it). An unreadable faction
counts every inn: unlocks get harder, never easier.

### 3.4 Stamps

A **stamp** is an inn you have signed: an entry in `inns` with `count >= 1`, dated by
`first`. It is **not a cosmetic** and has no ID. The export already carries every stamp as
an entry ([export-format.md](../export-format.md): "Each stamp is an entry"). Repeat
signatures of one inn (weekly) add to `count` and move `last`; they never add a stamp.

### 3.5 Cosmetic IDs

One ID space of 1..`Ledger.LIMITS.cosmeticIdMax` (9 999), the key space of `earned`:

| Kind | Range | Where defined |
|---|---|---|
| seal (milestone) | 1..99 | `Data/Cosmetics` |
| (reserved) | 100 | never used |
| seal (zone) | 101..999 | the zone's `seal` field in `Data/Zones` |
| quill | 1000..1099 | `Data/Cosmetics` |
| (reserved) | 1100..1199 | held inks until 2026-10-06 (none released); never reused |
| (reserved) | 1200..9999 | later kinds (never reused for these) |

- **Every seal is ≤ 999** (`Ledger.LIMITS.sealMax`), because seals are the one cosmetic
  that travels on the wire. Quills never do, so they sit above it.
- **Zone seal IDs are stable because they are stored, not computed.** Each zone record
  carries its own `seal`, allocated once in the order zones are added (101, 102, …) and
  never reused. Adding a zone takes the next free number; no existing seal moves. The
  zone's map ID can't be the seal ID (Classic-era map IDs are in the 1400s, over 999), and
  a position in a list would renumber on insert.
- **`Data/Cosmetics`** is one table keyed by ID (seals 1..99, quills):

  ```lua
  ns.Data.Cosmetics[1001] = { kind = "quill", name = "Traveler's quill", rule = { kind = "inns", n = 10 } }
  ```

  Record rules (`Cosmetics.bind` excludes and names anything else, like 3.2): the key is
  an integer in its kind's range (a seal outside 1..99, e.g. 100 or 101, is excluded:
  zone seals come only from `Data/Zones`); exactly `kind`, `name`, `rule`; `kind` is
  `"seal"` or `"quill"`; `name` 1..32 bytes under 3.2 rule 5; `rule` a table
  that is exactly one of:

  | Rule | Fields | Met when |
  |---|---|---|
  | `inns` | `n` integer 1..9999 | `n` distinct open inns signed |
  | `zones` | `n` integer 1..999 | `n` zones done (every open inn signed) |
  | `continent` | none | any one continent done (a World-map group counts, 3.1) |
  | `all` | none | every inn open to you signed (`total >= 1`) |

- **Zone seals** are generated from the kept zones with rule `{ kind = "zone", zone =
  <zone key> }` (met when that zone is done) and `name` = the zone's name (the book
  composes the label; that wording is the UI slice's).
- **Stability:** before the first release the catalog changes freely. From then on an ID
  never changes meaning and is never reused, and a threshold never rises (it would take
  cosmetics away from players who haven't yet had them recorded, [§3.6](#36-unlocks-and-earned-times)).

### 3.6 Unlocks and earned times

`set.unlocked(own, faction, kept)` returns what is unlocked and when, as an array of
`{ id = n, t = n }` sorted by `(t, id)` ascending. It is computed from the entries every
time; **the stored `earned` map is only a floor that keeps what was once earned.**

**Derived time** (from `p = atlas.progress(own, faction)`):
- `inns n`: sort the `first` of every open, signed inn ascending; the `n`-th value.
- `zones n`: sort the `done` of every zone in `byZone` that has one; the `n`-th value.
- `continent`: the smallest `done` in `byContinent`.
- `all`: `p.done`.
- `zone z`: `p.byZone[z].done` (nil if the zone isn't there).
- Missing (fewer values than `n`, or `nil`) → not derived.

Every derived time is the `t` of one of the player's own entries: the signature that
completed the rule. So a consumer can check that each cosmetic came after the entries
behind it, as the profile-site trust entry wants.

**Kept unlocks (why some state is needed).** Pure derivation drifts the other way: when a
Forever patch adds an inn to a zone and #12's data follows, a player's zone seal (and
maybe `all` and a `continent` quill) would silently disappear, `Sign` would refuse the seal
they've been using, and the export would drop it. Earned things must not be taken away.
So `Sign` records each unlock with `ledger:markEarned(id, t)` (the ledger's existing
`earned` map, which already keeps the earliest time; sync-ledger.md §4.2, §4.5), and
`unlocked` merges the map back in as `kept`:
- For each catalog ID (never by iterating `kept`), `k = rawget(kept, id)` if `kept` is a
  table. `k` is **honored** only if it is an integer in `tMin`..`tMax` **and** equals the
  `t` of some own entry the call read (any inn, known or not: the inn may have been
  removed from the data). Everything else in `kept` is ignored.
- An ID is unlocked if it has a derived time or an honored kept time. Its `t` is the
  smaller of the two.
- So the result is still a pure function of its arguments; the only state is a floor
  whose every time is one of the player's own entry times.

A tampered `earned` can unlock a cosmetic early, but only for that player's own book,
their own sealed entries and their own export, and nothing here can stop a player editing
their own files (they could forge own entries too). It's not a security boundary
([§5](#5-security-notes)).

### 3.7 Seals for peers and for signing

- **`Cosmetics.SEALS`** is a table keyed by seal ID holding **every seal the catalog
  knows**, milestone and zone, unlocked or not: a peer's unlocks are theirs, and we hold
  at most 40 of their entries, so we can't check them. `SyncProtocol` rule 16 accepts a
  peer entry's seal if `rawget(SEALS, seal) ~= nil`. Values are copies of the info
  records ([§3.8](#38-api)); `SyncProtocol` reads only presence. Every key is an integer in
  1..999. A peer on a newer AddOn using a seal we don't know has that one entry skipped
  (rule 16); that is accepted behavior and is not loosened.
- **Signing with a seal** (`Sign`, a later slice): the seal must be unlocked by the
  signatures **already in the ledger**, no later than the new entry's time:
  `set.canSeal(unlocked, seal, t)` with `unlocked = set.unlocked(ledger:own(), faction,
  ledger:earned())` computed **before** `addOwn`, and `t` the new entry's time. It returns
  exactly `true` when `seal` is `nil`, or when `seal` is a key of `SEALS` and `unlocked`
  holds `{ id = seal, t = u }` with `u <= t`; else exactly `false`. So the signature that
  earns a seal can't carry it (the next one can), and every sealed own entry is one peers
  accept. A `t` that isn't an integer in `tMin`..`tMax` gives `false` even when `seal` is
  `nil` (fail closed; #63).
- `canSeal` checks against the set's private lookup, not the exported `SEALS` table, so
  code changing `SEALS` can't widen what `Sign` allows.

### 3.8 API

All functions are pure and **never throw** on any argument (they return `nil`, `false`,
`{}` or an empty result); only a file's own load can raise ([§3.9](#39-loading-and-binding)).
Returned tables are new each call; changing them changes nothing inside the module.

**`Collection`**

| Name | Value / returns |
|---|---|
| `Collection.LIMITS` | `{ nameBytes = 48, mapKeyMax = 999999, ownMax = 100000 }` (a copy; `innMax`, `tMin`, `tMax` are read from `Ledger.LIMITS`, not repeated) |
| `Collection.FACTIONS` | `{ Alliance = true, Horde = true }` (a copy) |
| `Collection.bind(inns, zones, continents)` | an **atlas**: the functions below as closures over a private copy of the kept records, plus `atlas.invalid` |
| `atlas.progress(own, faction)` | the table of 3.3. `faction` other than exactly `"Alliance"`/`"Horde"` (any other string, a non-string, a hidden-value stand-in) counts as `nil` |
| `atlas.innOf(npcId)` | the inn key for a kept primary or alias NPC ID, else `nil` |
| `atlas.inn(key)` | `{ name, zone, faction }` for a kept **primary** key, else `nil` |
| `atlas.zone(key)` | `{ name, continent, seal }` for a kept zone, else `nil` |
| `atlas.continent(key)` | `{ name }` for a kept continent, else `nil` |
| `atlas.zoneKeys()` | kept zone keys, ascending |
| `Collection.atlas` | the default atlas over the shipped data ([§3.9](#39-loading-and-binding)); its functions and `invalid` are also copied onto `Collection` (`Collection.progress`, …) |

**`Cosmetics`**

| Name | Value / returns |
|---|---|
| `Cosmetics.RANGES` | `{ seal = { 1, 99 }, zoneSeal = { 101, 999 }, quill = { 1000, 1099 } }` (a copy) |
| `Cosmetics.bind(atlas, catalog)` | a **set**: the fields below. An `atlas` without `progress`, `zoneKeys` and `zone` functions, or whose zones misbehave (an error, a seal outside 101..999 or used twice, a bad name), counts as an empty atlas (`Collection.bind()`); a non-table `catalog` as empty |
| `set.SEALS` | 3.7 |
| `set.invalid` | excluded catalog records (`"cosmetic 100"`), as 3.2 |
| `set.info(id)` | `{ id, kind, name, rule = { kind, n?, zone? } }` for a known cosmetic (zone seals included), else `nil` |
| `set.catalog()` | every `info` record, ascending by `id` |
| `set.unlocked(own, faction, kept)` | 3.6: `{ { id = n, t = n }, ... }`, `(t, id)` ascending |
| `set.canSeal(unlocked, seal, t)` | 3.7: exactly `true` / `false`. Reads `unlocked` with `rawget` only, at most one more item than the catalog holds; `t` must be an integer in `tMin`..`tMax` |
| `Cosmetics.SEALS`, `Cosmetics.unlocked`, … | the default set's fields over `Collection.atlas` and `Data.Cosmetics`, copied onto `Cosmetics` |

Neither module reads `ns` at call time, and neither iterates a caller's table with `pairs`
or `#`: arrays are read with `rawget(t, i)` up to their limit, maps with `rawget` by our
own keys, so no metamethod of an argument ever runs.

### 3.9 Loading and binding

Same pattern as `Phrase` ([phrase.md §3.7](phrase.md#37-loading-and-binding)):
- **TOC order** is already right: `Data\Inns.lua`, `Data\Phrases.lua`, then **new
  `Data\Cosmetics.lua`**, then `Ledger.lua`, `Phrase.lua`, `Collection.lua`,
  `Cosmetics.lua`. `load.DATA` gains `{ path = "Data/Cosmetics.lua", name = "Cosmetics" }`
  (the data table is `ns.Data.Cosmetics`; the module stays `ns.Cosmetics`).
- `Collection.lua` asserts `ns.Ledger`, then binds `Collection.atlas =
  Collection.bind(ns.Data.Inns, ns.Data.Zones, ns.Data.Continents)` (each read only if
  `ns.Data` is a table).
- `Cosmetics.lua` asserts `ns.Ledger` and `ns.Collection`, asserts
  `RANGES.zoneSeal[2] <= Ledger.LIMITS.sealMax` and `RANGES.quill[2] <=
  Ledger.LIMITS.cosmeticIdMax`, then binds the default set over `Collection.atlas` and
  `ns.Data.Cosmetics` and copies its fields, `SEALS` included, onto `Cosmetics`.
- **Missing data or a bad record never raises:** it binds an empty atlas or leaves the
  record out, named in `invalid`. `SEALS` over missing data holds only the catalog's
  milestone seals (or nothing), which fails closed for peers.
- `SyncProtocol` checks `rawget(ns.Data.Inns, inn)`. An inn record `bind` excluded is
  still "known" to sync and stored, but counts as `unknown` in progress; the real-data
  test keeps that from happening.
- Tests inject fixtures with `Collection.bind(...)` and `Cosmetics.bind(atlas, ...)`;
  nothing global is touched.

### 3.10 Rejected alternatives

- **Stamps as cosmetics with IDs:** an ID per inn duplicating what entries already say.
- **Pure derivation with nothing stored:** a data update adding an inn would take away a
  seal the player uses, and `Sign` would refuse it (3.6).
- **Stored unlock state as the only truth:** drifts from the entries, and a missing
  record (a ledger from before recording existed) could never be rebuilt.
- **A kept time taken as is:** the "equals an own entry's time" check keeps every export
  time tied to a real signature at no cost.
- **Zone keys as English names or slugs:** names differ by locale and Forever renames
  zones; slugs need a human naming step, while map IDs come from the client.
- **Zone seal ID = map ID:** map IDs go over 999, the wire's seal limit. **= 100 + list
  position:** inserting a zone renumbers every later seal.
- **Continent on each inn record:** can disagree with its zone.
- **For a zone with no Continent above it (#76):**
  - *`continent = nil`, reported under an "other lands" group:* `byContinent` would need
    a made-up key or a hole, the export's "every zone's `continent` is a `byContinent`
    key" rule would break, and the group would need a player-facing label nobody has
    chosen.
  - *Each such zone as its own group:* a zone key would also be a continent key (against
    rule 6), and every lone island would earn the `continent` rule alone.
  - *Renaming `continent` to `group`:* clearer, but it renames export fields and
    `byContinent` for no change in meaning. The World-map rule keeps the shape, the
    progress math and the export byte-for-byte as they were.
- **Counting innkeepers:** a faction pair or a replaced NPC would count one inn twice, and
  "every inn in a zone" would demand both factions' innkeepers.
- **Totals over both factions:** contested zones' seals and the `all` rule could never be
  earned (3.3).
- **Counting other travelers' entries:** the collection is where you've been (Scope).
- **Percentage thresholds:** they move whenever the data grows; "ten inns" is something a
  player can read and plan for.
- **The catalog as code in `Cosmetics.lua`:** it is content the maintainer edits, and it
  belongs in the published data reference, like `Data/Phrases`.
- **A read-only proxy for `SEALS`:** `SyncProtocol` reads it with `rawget`, which a proxy
  would defeat; `canSeal` uses a private copy instead (3.7).

### 3.11 Completeness marks (amended 2026-10-07, #110)

**The problem.** `zone`, `zones n`, `continent` and `all` count only the inns the data
knows. Until #12's walk has visited every inn, a zone holding one known inn is "done"
after one signature, and since earned cosmetics are never taken away (§3.6), a release
with a partial atlas would hand out "every inn" rewards for good. The beta showed it: the
first signature at Calmbreeze earned seal 101, quill 1003 and seal 2 at once.

**The marks.** The data says which places it knows in full:
- a zone record may carry **`complete = true`**: every inn in that zone is in `Data/Inns`;
- a continent record may carry **`complete = true`**: every zone of that continent that has
  an inn is in `Data/Zones`;
- **`ns.Data.AtlasComplete = true`** (in `Data/Inns.lua`): every continent with an inn is
  in `Data/Continents`. `Collection.bind(inns, zones, continents, atlasComplete)` takes it
  as a fourth argument; anything but exactly `true` counts as not complete.

The data author sets them from the walk (§8), never by guessing. An absent mark means
"not known to be complete", which is the safe default.

**Record rules.** `complete` is an optional field of zone and continent records (rules 1
and 2 gain it as optional). If present it must be exactly `true`; any other value
(`false`, `1`, `"yes"`) **excludes the record** like any bad field (fail closed; the
real-data test keeps `invalid` empty, so a typo fails CI rather than shipping).

**Effective completeness** (computed once in `bind`):
- a zone is complete if its record says so;
- a continent is complete if its record says so **and** every kept zone whose
  `continent` is it is complete (a marked continent over an unmarked zone is a data
  mistake; it counts as not complete);
- the atlas is complete if `atlasComplete == true` **and** every kept continent is
  complete.

**Fail closed on any exclusion (amended 2026-10-07, #118).** If `bind` excludes any
record (`invalid` is not empty, after the alias step), **no zone, no continent and not the
atlas is complete**, whatever the marks say. A marked zone that lost one of its inns to
validation would otherwise still count as complete and hand out its seal for good (§3.6).
An excluded record can't always be traced to a place (an inn whose bad field is `zone`,
a non-table record, a bad key), so the guard is global rather than per place. The shipped
data never trips it: the real-data test keeps `invalid` empty. Everything else about the
excluded record's neighbours is unchanged (`signed`, `total`, keys, `SEALS`).

**Progress** (§3.3 amended): `done` is set only for complete places. `byZone[z].done`
needs zone `z` complete; `byContinent[c].done` needs continent `c` complete; `p.done`
needs the atlas complete. `signed`, `total` and everything else are unchanged. Each
`byZone` and `byContinent` item and the result itself gain **`complete = true | false`**,
so the book can say "more to find" without its own logic. The export copies only its
named fields, so its format doesn't change: `done` is just absent more often, which v1
already allows.

**Cosmetics** read `done` (§3.6), so they need no guard of their own: `zone z`, `zones n`,
`continent` and `all` derive no time for an incomplete place. `inns n` counts signed inns
only, so a partial atlas can only undercount it; it stays unguarded. The `kept` floor is
unchanged: an `earned` time at an own entry's time is still honored, so an unlock
recorded under older data is kept (beta saves don't reach live realms).

**API** (§3.8 amended): `atlas.zone(key)` and `atlas.continent(key)` add `complete`
(the effective value); new `atlas.complete()` returns the atlas's. `Collection.bind`'s
fourth argument is new; `Collection.atlas` binds with `ns.Data.AtlasComplete` (read only
if `ns.Data` is a table). `Cosmetics.bind` reads zones as before (an extra field in
`atlas.zone` changes nothing there).

**The book** ([book.md](book.md) §3.5, §3.6, amended with this): wherever it prints
`signed .. TEXT.of .. total` for a place that isn't complete (the summary's inns line,
a continent bar, the Inns tab's continent and zone rows, the `continent`, `all` and
`zone z` rule progress), `total` is followed
by `TEXT.more` (DRAFT `"+"`, so "1 of 1+ inns signed"). The nearest-done continent for
the `continent` rule is chosen among complete continents only; none → `0 .. TEXT.of ..
1`, as today.

**Tests** (§6 amended): fixture F marks every zone and continent `complete = true` and
binds with `atlasComplete = true`, so every existing expectation holds. A new fixture
**F0** is F with no marks. On F0 with entries E: no `done` anywhere, every `complete` is
`false`, and `unlocked` holds only the `inns n` items (1 and 1001 at their F times; no 2,
1002, 1003 or zone seal). Then one mark at a time: Vale (10) marked → `byZone[10].done`
and seal 101 return; East (1) marked with Marsh (11) unmarked → East not complete, no
1003; both marked → 1003 at F's time; `atlasComplete` without every continent → no `all`.
`bind` with `complete` of `false`, `1`, `"true"`, a table, a stand-in on a zone and on a
continent → that record excluded and named (a continent's exclusion cascades);
`atlasComplete` of `1`, `"true"`, `{}` → not complete. The real-data test (§6.6) also
checks every `complete` in `Data/Inns.lua` is exactly `true`, and that `AtlasComplete` is
absent or a boolean; its "every rule is reachable" atlas is marked complete. The book
specs gain the `"+"` cases. A whole-AddOn test: one signature at Calmbreeze with the
shipped (unmarked) data records no place-based unlock.
**(#118)** On F (all marked) with one record excluded, each case binds with `invalid`
non-empty and every `complete` false (`atlas.zone`, `atlas.continent`,
`atlas.complete()`, each progress item and the result), no `done` anywhere, and only the
`inns n` items unlocked: an inn of a marked zone with a bad field; an inn whose `zone`
isn't a kept zone; an alias to a missing primary; a non-table inn record; a zone record
on another continent with a bad field (its own zone's seal gone, the other zones'
seals withheld too); a bad continent key. Existing tests that break a rule on F and then
read `done` or `complete` expect the guard's result.

**Rejected:** *only the maintainer visiting every inn before release* (the beta ends
2026-10-21; a missed inn would still leak); *a release-time switch that turns place
rules off* (zone seals known to be safe would wait too); *percent thresholds or rules
over known inns only* (they move as data grows, §3.10); *taking back unlocks when data
grows* (§3.6: earned things are never taken away); *marks on inns* (an inn can't know
it's the last one in its zone); *(#118) withholding completeness only from the place that
lost a record* (an excluded record can't always be traced to a place, and the shipped data
keeps `invalid` empty anyway, so precision buys nothing).

## 4. Data model changes

- **`Data/Inns.lua`:** shape of 3.1 (still empty until #12). Header comment updated
  (continent now comes through the zone). New empty `ns.Data.Zones` and
  `ns.Data.Continents` in the same file.
- **`Data/Cosmetics.lua`** (new): the §9 draft, shape of 3.5.
- **SavedVariables:** none. The ledger's existing `earned` map (schema 1,
  sync-ledger.md §4.2) is the kept floor of 3.6; no field, schema bump or migration. It
  has held nothing so far (nothing writes it until `Sign`), so no old data needs reading
  differently.
- **Wire format:** unchanged (v1). Every seal is 1..999, inside the `seal` token.
- **Export ([export-format.md](../export-format.md), still draft v0).** Update the Data
  section in this PR so #64 serializes these results directly:
  - `collection` = `{ faction, signed, total, done, byContinent, byZone }`, taken as is
    from `progress` (not `inns`, `unknown` or `truncated`: stamps are the entries). Changes
    from the draft: adds `faction`, `done`, `byContinent`, and `continent`/`done` on each
    zone; zone and continent keys are the client's map IDs (integers).
  - `cosmetics` = the `unlocked` array as is (`{ id, t }`, `(t, id)` ascending). Change the
    comment from "unlocked quills, inks, seals and badges" to "unlocked quills, inks and
    seals"; v1 has no badge kind (a consumer may present any of them as badges). IDs follow
    this spec's §3.5 ranges.
  - Add to the phrase-ID paragraph that inn, zone, continent and cosmetic IDs refer to
    `Data/Inns` (`Inns`, `Zones`, `Continents`) and `Data/Cosmetics`.
- **Docs in the same PR:** [architecture.md](../architecture.md) → Modules: `Data/Inns`
  row (NPC ID → inn record; zones and continents by map ID), a `Data/Cosmetics` row, the
  `Collection` row ("progress: signed/total by continent and zone, per inn") and the
  `Cosmetics` row (catalog, unlocks, `SEALS`) link this spec; Data model: `seal` is a seal
  ID from `Cosmetics.SEALS`. [platform-forever.md](../platform-forever.md) → Verification
  checklist: the `Data/Inns` item names the fields of §8 (#12), plus "map IDs readable at
  each inn (`C_Map.GetBestMapForUnit`, parent chain to Zone and Continent)" and "the
  player's faction token (`UnitFactionGroup("player")`) and each innkeeper's faction".
  [status.md](../status.md) → Open questions gets the catalog questions and the follow-up
  "publish `Data/Inns`/`Data/Phrases`" gains `Zones`, `Continents`, `Cosmetics`.
  [decisions.md](../decisions.md) gets the two entries named at the top.

## 5. Security notes

**Flag for the reviewer: security-level review of `SEALS`, `canSeal` and the argument
handling of `progress` / `unlocked`.**

- **Peer-facing surface: only `SEALS`.** It widens rule 16 from "no seal is known" to
  "every catalog seal is known". Check that every key is an integer in 1..999 (the wire
  can't carry more, and `SyncProtocol`'s grammar and `validEntry` check it again), that
  it holds seals only (no quill ID, so a peer's `seal` field can't name one), and
  that nothing in this slice changes `SyncProtocol`, the own-signature rule, the rate
  limits, size caps or storage caps. Rule 16 stays: an unknown seal skips that entry only.
- **Never remove a zone record** once released (3.1): its seal would leave `SEALS`, and
  our own older sealed entries would be rejected by peers on the newer data.
- **Own data is trusted-ish.** `ledger:own()` and `ledger:earned()` come from
  SavedVariables, which a player (or a broken file) can alter. Both functions fail closed
  and do bounded work: `rawget` only, no metamethods, `ownMax` entries at most, `kept`
  read only by catalog IDs (at most 99 + 899 + 200 lookups), every number checked with
  the integer-and-range test (`NaN`, `inf`, fractions fail). No input can make them throw,
  loop without bound, or write to an argument.
- **Faction** is a client value that may arrive hidden (platform-forever.md): it is only
  compared as `type(f) == "string"` and then by equality with two literals, so a
  stand-in counts as `nil`. The glue still checks `issecretvalue` before passing it (§8).
- **Text safety:** every name the modules return passed the 3.2 rule 5 allow-list (no
  `|` escapes, no `%`, no control bytes). The UI still shows names as plain text (§8).
- **Earned, never bought:** no rule depends on anything outside the game, there is no
  code or key that unlocks anything, and nothing is paid, gated or external
  (*Cosmetics are earned by play*). The reviewer checks the catalog against this.
- **Forbidden-API guard:** `Collection.lua`, `Cosmetics.lua`, `Data/Inns.lua` and
  `Data/Cosmetics.lua` name no WoW API even in comments (`scripts/check-apis.sh`); the
  map and faction calls live in #12's notes and the glue. All four load in the strict
  environment.

## 6. Test plan

busted, pure files loaded through `spec/helpers/load.lua` in the strict environment. Fixed
times, never the clock. Coverage floor 90% for both modules (already in
`scripts/check-coverage.sh`).

**Fixture places F** (the real `Data/Inns` is empty):
- continents `[1] = "East"`, `[2] = "West"`;
- zones `[10] = { "Vale", continent 1, seal 101 }`, `[11] = { "Marsh", 1, 102 }`,
  `[20] = { "Dunes", 2, 103 }`, `[21] = { "Ridge", 2, 104 }`;
- inns `[5001] = { "Vale Inn", zone 10 }` (neutral), `[5002] = { "Hill Inn", 10,
  Alliance }`, `[5003] = { alias = 5001 }`, `[5101] = { "Marsh Inn", 11, Alliance }`,
  `[5201] = { "Dune Inn", 20 }` (neutral), `[5202] = { "Oasis Inn", 20, Horde }`,
  `[5301] = { "Ridge Inn", 21, Horde }`.

**Fixture entries E** (`T = 1790000000`, each with `phrase = { 1 }`): e1 `5001 @ T`, e2
`5201 @ T+100`, e3 `5003 @ T+200` (the alias), e4 `5002 @ T+300`, e5 `5101 @ T+400`, e6
`9999 @ T+500` (not in data), e7 `5001 @ T+604800` (a week later).

**Fixture catalog C:** `[1]` seal `inns 2`, `[2]` seal `all`, `[1001]` quill `inns 3`,
`[1002]` quill `zones 2`, `[1003]` quill `continent`.

### 6.1 `Collection.bind` and record rules

- F binds with `invalid` empty; `innOf(5003) == 5001`, `innOf(5001) == 5001`,
  `innOf(9999) == nil`; `inn(5003) == nil` (alias), `inn(5002)` = `{ name = "Hill Inn",
  zone = 10, faction = "Alliance" }`; `zone(10)`, `continent(2)`; `zoneKeys()` =
  `{ 10, 11, 20, 21 }`.
- **Each rule of 3.2 broken once → excluded, named in `invalid`:** continent key `0`,
  `1.5`, `"1"`, `1000000`; a continent with an extra field; zone with a missing or
  unknown `continent`, `seal` 100, 1000, `0`, `1.5`, a missing seal; **two zones with seal
  101 → both excluded, and their inns too**; inn key `0`, `10000000`, `"5001"`, `-1`; inn
  with an unknown zone, `faction = "Neutral"`, `"alliance"`, `1`; an extra field; an alias
  to a missing key, to an alias, to itself, to an excluded inn; an alias with `name` too;
  names with `|`, `%`, `\`, `\0`, a UTF-8 byte, a leading, trailing or double space, a
  lowercase first byte, 49 bytes (48 passes), empty, non-string; a record that's a string
  or a number. An entry at an excluded inn counts as `unknown`.
- **A zone under a World map** (#76): F plus continent `[947] = "Azeroth"`, zone
  `[2521] = { "Zephras Isle", continent 947, seal 105 }`, inn `[251001]` in it: binds
  with `invalid` empty, and progress counts the inn under `byZone[2521]` (continent 947)
  and `byContinent[947]`; in `Cosmetics`, its zone seal and the `continent` rule are
  earned by signing it.
- **Rule 6, hostile:** a World key reused as a zone key (`Zones[947]` beside
  `Continents[947]`) → both excluded, and zone 2521 and its inn with them; a key in both
  tables where one record is junk (a string, a number) → both excluded; a zone whose
  `continent` is its own key, with and without a continent record of that key; two zones
  that are each other's continent → all excluded, F still binds.
- `bind()`, `bind("x", 7, true)`, `bind({}, {}, {})` → an empty atlas, no error.
- **Copies:** changing F after `bind`, or a table returned by `inn`/`zone`/`zoneKeys`/
  `progress`, changes no later result.

### 6.2 `progress`

- **Alliance, E:** `signed 4, total 4, done T+400, unknown 1, truncated false`;
  `inns[5001] = { zone 10, open, count 3, first T, last T+604800 }` (e1, e3 via the alias,
  e7); `inns[5202]`/`[5301]` `open = false, count 0`, no `first`/`last`;
  `byZone = { [10] = { 2, 2, continent 1, done T+300 }, [11] = { 1, 1, 1, T+400 },
  [20] = { 1, 1, 2, T+100 } }` (zone 21 absent);
  `byContinent = { [1] = { 3, 3, T+400 }, [2] = { 1, 1, T+100 } }`.
- **Horde, E:** `signed 2, total 4, done nil`; `byZone[10] = { 1, 1, done T }` (only the
  neutral inn is open), `[20] = { 1, 2 }`, `[21] = { 0, 1 }`, zone 11 absent;
  `inns[5002].open == false` with `count 1` (signed but not open: counts nowhere else).
- **Faction `nil`,** and each of `"Neutral"`, `"alliance"`, `""`, `1`, `{}`, the two
  stand-ins → all 6 inns open: `signed 4, total 6`, `byZone[20] = { 1, 2 }`, `faction`
  field `nil`.
- **Empty data** (`bind({}, {}, {})`): `signed 0, total 0, done nil`, empty maps,
  `unknown 7`.
- **An inn removed from the data after you signed it** (F without 5101): Alliance
  `total 3`, `unknown 2`, zone 11 absent, `done T+300`.
- **Repeat signatures:** 5001 signed three times counts once in `signed`, `count 3`.
- **An alias alone** (only e3): 5001 signed, `first = last = T+200`.
- **Order doesn't matter:** E reversed and shuffled (seeded) gives a deep-equal result.
- **Hostile `own`:** `nil`, `"x"`, `7`, the stand-ins → the empty-ledger result; an array
  with a non-table item, `inn` of `NaN`, `1/0`, `1.5`, `"5001"`, `0`, `10000000`, `t` of
  `tMin - 1`, `tMax + 1`, `NaN`, an entry with a raising metatable → each skipped, no
  throw, not counted in `unknown`; a hole (`{ e1, nil, e2 }`) stops the read at 1; a
  metatable `__index` on `own` is never called (spy); `own` is unchanged after the call.
- **Bound:** 100 001 valid entries → `truncated = true`, only the first 100 000 counted.
- `progress` never writes to its arguments (deep-compare before and after).

### 6.3 `Cosmetics.bind`, catalog and `SEALS`

- `bind(atlasF, C)`: `invalid` empty; `SEALS` keys exactly `{ 1, 2, 101, 102, 103, 104 }`;
  `info(103)` = `{ id = 103, kind = "seal", name = "Dunes", rule = { kind = "zone",
  zone = 20 } }`; `info(1001).rule` = `{ kind = "inns", n = 3 }`; `info(5)`/`info(nil)`
  → `nil`; `catalog()` ascending by `id`, 9 records.
- **Each record rule of 3.5 broken once → excluded and named:** a seal at 0, 100, 101,
  999, 1000; a quill at 999, 1100 and 1101 (reserved); an `ink` (no longer a kind); an unknown `kind`; an extra
  field; `name` failing 3.2 rule 5 or 33 bytes; `rule` missing, unknown `kind`, `inns`
  with `n` 0, 1.5, 10000 or missing, `zones` with `n` 1000, `continent` or `all` with an
  `n`, an extra rule field.
- `bind(nil, nil)` and `bind({}, "x")` → empty set: `SEALS = {}`, `unlocked` → `{}`,
  `canSeal(anything, 1, T)` false and `canSeal({}, nil, T)` true, no error.
- **`SEALS` is safe to hand out:** adding a key to `SEALS` doesn't change `canSeal`;
  a new `bind` gives a fresh table.

### 6.4 `unlocked` and earned times

- **Alliance, E, no kept:** exactly `{1, T+100}, {103, T+100}, {1003, T+100}, {101,
  T+300}, {1001, T+300}, {1002, T+300}, {2, T+400}, {102, T+400}` (the `(t, id)` order).
  Seal 104 (Horde's zone) is absent.
- **Horde, E:** exactly `{101, T}, {1003, T}, {1, T+100}`.
- **Every time is an own entry's `t`** (checked for both cases), and the same input twice
  and a shuffled input give deep-equal results.
- **Empty data:** `{}` for any entries (no rule can be met with `total 0`).
- **Kept floor, one case each:**
  - F plus a new neutral inn `[5004]` in zone 10, Alliance, no kept → 101, 2 gone, 1002
    moves to T+400; with `kept = { [101] = T+300, [2] = T+400, [1002] = T+300 }` → 101 at
    T+300, 2 at T+400, 1002 at T+300 (the smaller time).
  - F without 5101 (zone 11 loses its only inn), `kept = { [102] = T+400 }` → 102 still
    unlocked at T+400 (e5's time; e5 now counts as `unknown` and still anchors it).
  - `kept = { [1] = T }` → seal 1 at T (earlier than derived T+100, and e1's time).
  - Ignored: `[102] = T+401` (not an entry time), `[7] = T` (not in the catalog),
    `[1] = "x"`, `NaN`, `1.5`, `tMin - 1`; `kept` = `"junk"`, `7`, a stand-in, a table
    whose `__index` raises (never called).
- **No mutation** of `own` or `kept`.

### 6.5 `canSeal`

With `U` = Alliance's unlocked list: `canSeal(U, nil, T+500)` true; `(U, 1, T+100)` true;
`(U, 1, T+99)` false (earned after); `(U, 102, T+500)` true; `(U, 104, T+500)` false
(known, not unlocked); `(U, 1001, T+500)` false (a quill); `(U, 3, …)`, `(U, 0, …)`,
`(U, 0/0, …)`, `(U, "1", …)` false; `t` of `nil`, `NaN`, `1.5`, `tMax + 1` false; `U`
= `nil`, `"x"`, a stand-in, `{ { id = 1, t = "T" } }`, `{ { id = 1, t = 0/0 } }` false;
a 1 000 000-item array whose first item doesn't match stops after the catalog count + 1
items (review). The result is `rawequal` to `true` or `false`.

### 6.6 The real data

Loads `Data/Inns.lua`, `Data/Cosmetics.lua`, `Ledger.lua`, `Collection.lua`,
`Cosmetics.lua` into one fresh `ns`:
- `ns.Collection.invalid` and `ns.Cosmetics.invalid` are empty; every `Data.Inns` key is
  an integer in 1..`innMax`; every record is a primary or an alias of a primary.
- Every zone is used by at least one inn and every continent by one zone (a zone retired
  after release gets a named exception here); no map ID is both a zone and a continent;
  names unique per kind (case-insensitive);
  zone seals unique and in 101..999 (vacuous until #12, then it bites).
- Every key of `ns.Cosmetics.SEALS` is an integer in 1..`Ledger.LIMITS.sealMax`, and
  `SEALS` holds exactly the catalog's seals plus one per zone.
- The §9 catalog holds the IDs and rules listed there (update with the catalog; the
  numbers aren't a rule), and **every rule is reachable** on a generated atlas of 40
  neutral inns in 20 zones on 2 continents with one entry per inn (so a typo'd threshold
  like `n = 1000` fails CI).

### 6.7 With `SyncProtocol` (integration)

One fresh `ns` with `Ledger.lua`, `Data/Cosmetics.lua`, `Collection.lua`,
`Cosmetics.lua`, `SyncProtocol.lua`; `ctx` as in `spec/sync_protocol_spec.lua`'s `newCtx`
with fixture inns `1234..1238`, `phrases = { [1] = true }`, **`seals =
ns.Cosmetics.SEALS`** (the real one). One ENTRIES message from a resolved sender, five
entries at five inns: seal `0` (none), `1`, `2`, `3`, `101`. Result `{ kind = "entries",
added = 3, dup = 0, dropped = 0, rejected = 2 }`; stored exactly the first three, seals
`nil`, `1`, `2`. Then the same with `seals` from `Cosmetics.bind(Collection.bind(F),
ns.Data.Cosmetics).SEALS` on a fresh ledger: the `101` entry is stored too
(`added = 4, rejected = 1`).

### 6.8 Whole AddOn and guards

- `spec/addon_load_spec.lua`, "the whole AddOn under the WoW stub": `ns.Data.Cosmetics`,
  `ns.Data.Zones` and `ns.Data.Continents` are tables; `ns.Cosmetics.SEALS` is a table
  whose keys are all integers in 1..999 and which holds seal 1; and **`Sync` picks it
  up**: after `PLAYER_LOGIN`, `rawequal(ns.Sync.client.ctx.seals, ns.Cosmetics.SEALS)`
  (if the stub doesn't start a client, make it; this is the check that `realDeps` reads
  the right name).
- `Collection.lua` without `Ledger`, and `Cosmetics.lua` without `Collection`, raise (the
  asserts); with no `Data`, both load and bind empty.
- The TOC and list tests pass with `Data\Cosmetics.lua` added.
- `luacheck .` clean; `sh scripts/check-apis.sh`, `check-libs.sh`, `check-links.sh` and
  `check-coverage.sh` (`Collection.lua`, `Cosmetics.lua` ≥ 90%) pass.

## 7. Acceptance criteria

- [ ] `Data/Inns.lua` defines empty `Inns`, `Zones`, `Continents` with a header pointing
      at this spec; `Data/Cosmetics.lua` holds the §9 draft with a DRAFT comment; the TOC
      and `load.DATA` list the new file.
- [ ] `Collection.lua` implements 3.1–3.4, 3.8, 3.9; `Cosmetics.lua` implements 3.5–3.9,
      with limits read from `Ledger.LIMITS`, not repeated.
- [ ] Every test named in §6 exists and passes (`busted` output in the PR), including
      the fixture progress values, the kept-floor cases, the hostile arguments and the
      `SyncProtocol` integration with the real `SEALS`.
- [ ] Unlocks and times are derived from entries on every call; the only stored input is
      the `earned` floor, honored only for catalog IDs at own-entry times.
- [ ] `ns.Cosmetics.SEALS` holds only seals, every key an integer in 1..999, and `Sync`'s
      `ctx.seals` is that table.
- [ ] No WoW global, `LibStub` or library call in the four files; no `pairs`, `#` or
      `ipairs` on a caller's argument.
- [ ] `busted`, `luacheck .`, `check-apis.sh`, `check-libs.sh`, `check-links.sh`,
      coverage (`Collection.lua`, `Cosmetics.lua` ≥ 90%) green locally and in CI.
- [ ] The reviewer did a security-level review of §5 and states it tried hostile input of
      its own, and checked the catalog against *earned by play*.
- [ ] Docs of §4 updated (export-format.md Data section, architecture.md, platform-forever
      checklist, status.md open questions, the two decisions entries).
- [ ] (#110) §3.11: the marks, their record rules, effective completeness, `done` and
      `complete` in progress, the API additions, the book's `TEXT.more`, and its tests;
      `Data/Inns.lua`'s header documents the marks and ships none; a decision-log entry
      (2026-10-07, *Partial atlas: place rules count only places marked complete*);
      status.md's release-gate question answered.
- [ ] (#118) §3.11: any excluded record (`invalid` not empty, after the alias step) makes
      no zone, no continent and not the atlas complete; `signed`, `total`, keys and `SEALS`
      unchanged; the six fail-closed cases, plus a marked continent with no kept zone and
      an atlas with every zone excluded, each pin the guard; a decision-log entry
      (2026-10-07).

## 8. Contract for later slices

- **#12 (the in-client walk)** records, per innkeeper: the NPC ID; the inn's English
  name; the zone's map ID and English name (first *Zone*-type map up the parent chain);
  the continent's map ID and English name (the first *Continent*-type map above the zone,
  or the first *World*-type map if the chain reaches one first, 3.1); the innkeeper's
  faction (`"Alliance"`,
  `"Horde"`, or neutral if both can use it); and whether another innkeeper serves the same
  inn (an alias). Zone seals are numbered 101, 102, … in the order zones are added.
  The walk is bounded: it stops at a parent of `0` or `nil`, at an unreadable map, or
  after 12 steps (as the probe's walk does), and the step cap is what ends a looping
  chain. A chain with no *Zone* map, or
  with no Continent or World map above the zone, isn't entered: it goes on #12 as a
  question, and the rule is extended here first.
  **Completeness (#110, §3.11):** the walk also notes, per zone, whether every inn in it
  was visited (the maintainer's call, from the in-game map and their travels), and per
  continent whether every zone with an inn was. Only then does the data get
  `complete = true`; `ns.Data.AtlasComplete` waits until every continent is marked.
- **`Sign`:** gets the faction as the first return of `UnitFactionGroup("player")`
  (checked with `issecretvalue` and `type == "string"`, else `nil`; added to
  `.luacheckrc`'s glue list). Before `addOwn`, `unlocked = ns.Cosmetics.unlocked(own,
  faction, ledger:earned())`, and it attaches a seal only if `ns.Cosmetics.canSeal(
  unlocked, seal, t) == true`. After `addOwn` returns `"added"`, it recomputes `unlocked`
  and calls `ledger:markEarned(id, t)` for each item (idempotent; the ledger keeps the
  earliest). At login, `Core` does the same recording once for a writable ledger, so a
  data update never finds an unrecorded unlock. A read-only ledger records nothing.
- **UI / Book:** shows progress from `ns.Collection.progress(ledger:own(), faction)`, names
  from `inn`/`zone`/`continent` as plain text; lists cosmetics with `catalog()` and
  `unlocked`; offers only seals `canSeal` allows, and quills that are in
  `unlocked` (a chosen one that isn't falls back to the default look). What quills
  look like, and the labels ("Dunes seal"?), are the UI slice's design (a
  maintainer gate). Never hard-codes an ID.
- **Export (#64):** `collection` and `cosmetics` exactly as in §4, from the same calls.
- **After the first release:** new inns, zones, aliases and cosmetics get new keys and
  IDs; nothing is removed or renumbered; a threshold never rises. Older clients reject a
  peer entry sealed with a seal they don't know (rule 16), which is expected.

## 9. Draft catalog (DRAFT)

**The set, names and thresholds are the maintainer's decision** (open questions 1–3). Every
record passes 3.5 and is earned by play only. Thresholds are placeholders to retune after
#12 counts the inns: Classic had a few dozen inns open to each faction, and Forever adds
zones. **There are no inks** (maintainer, 2026-10-06): every signature is written in one
realistic ink, true to the game's times.

| ID | Kind | Name | Rule |
|---|---|---|---|
| 1 | seal | Wayfarer's seal | `inns 5` |
| 1001 | quill | Traveler's quill | `inns 10` (the vision's example) |
| 1002 | quill | Owl-feather quill | `inns 20` |
| 1003 | quill | Cartographer's quill | `continent`: every inn open to you on one continent |
| 2 | seal | Innkeeper's seal | `all`: every inn open to you |
| 101.. | seal | one per zone, named for it | `zone`: every inn open to you in that zone |

The feel: many zones have a single inn, so the
first zone seals come early; seals (the only cosmetic peers see) mark breadth; quills mark
depth. No name refers to a faction, race or class.

## Assumptions (listed for the maintainer)

- **Totals are per faction** (inns open to you: neutral plus your faction's). Another
  faction's inns never appear in your totals or zone seals.
- **Earned is never taken away:** once recorded, a cosmetic stays even if a patch adds an
  inn to a completed zone. The book can still show the zone as, say, 2 of 3.
- **Inns, not innkeepers:** a faction pair or a replacement NPC is one inn. Because the
  weekly re-sign rule is per NPC ID (`Ledger`), a player could sign both NPCs of one inn
  in one week; that only adds to `count`.
- **Map IDs** are readable at every inn in Forever and stable; if not, #12 assigns
  integers and nothing else changes.
- **Place names are English in v1,** like phrases; the map IDs leave room to use the
  client's localized names later.
- **Quills are local** (your own book's look); only seals travel. Putting quills
  on the wire would need protocol v2.
- **No badge kind in v1;** "badges" on the profile site can be any earned cosmetic.
- **The signature that completes a rule can't carry its seal;** the next one can.
- **`ownMax` 100 000** is far above any honest ledger (one entry per inn per week).

## Open questions (maintainer)

1. **The draft catalog** (§9): which cosmetics, their names, and the ladder (1 / 5 / 10 /
   20 inns; 3 / 10 zones; a continent; everything). Ship as is, or redirect? The numbers
   will be retuned once #12 knows how many inns there are. Doesn't block the build or the
   merge; IDs change freely until the first release. Note for the retune (#76): a zone
   with no Continent above it is grouped under its World map, which counts as a
   continent for the `continent` rule. If many Forever zones hang straight off Azeroth,
   that group nears "every inn"; a lone such zone makes the rule easy.
2. **Per-faction totals** (Assumptions): agree that "every inn" means every inn your
   faction can use?
3. **Never taken away** (Assumptions): agree that a seal stays when Forever adds an inn to
   a zone you'd completed? The alternative is losing it until you sign the new inn.
4. **Later, not v1:** worth a follow-up for continent seals, a "home inn" reward for
   re-signing the same inn over many weeks, or a distinct badge kind? None is in this
   slice.
