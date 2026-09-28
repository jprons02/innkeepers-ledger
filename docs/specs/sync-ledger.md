# Spec: slice 1 — Ledger + SyncProtocol

> **Summary:** the entry store (`Ledger`) and the sync codec and validation layer
> (`SyncProtocol`): wire grammar, digest, validation table, storage caps, rate limits,
> SavedVariables shape, and the hostile-input test plan. Also the contract the later
> `Sync` glue must honor.
> **Read when:** implementing or reviewing `Ledger.lua` or `SyncProtocol.lua`, writing the
> `Sync` slice, or changing anything about peer data, storage caps or the wire format.

**Status:** approved (self-approved 2026-09-27, ticket #11; no maintainer decision in it).
**Security-sensitive:** yes. The reviewer applies security-level scrutiny to everything
under [Security notes](#5-security-notes) and must try malicious input itself.

Architecture this builds on: [architecture.md](../architecture.md) → Data model, Sync
protocol, Security model, Testing posture. Decisions that bind it are listed in
[§3](#3-approach).

---

## 1. Problem

Players sign inn ledgers and, when they group or share a guild, their AddOns trade
signatures so each player's book fills with the travelers they crossed paths with. Every
byte a peer sends is hostile until proven otherwise, and every accepted byte ends up in
SavedVariables. This slice builds the two pure modules that make that safe: `Ledger`
stores entries with hard caps, and `SyncProtocol` turns addon-message strings into
validated entries (and our entries into strings). Nothing here touches the WoW API, so
all of it runs under `busted`.

## 2. Scope

**In:**
- `Ledger.lua` (pure): entry store, dedupe, queries, own vs foreign, storage caps and
  eviction, cosmetic earned times, SavedVariables schema and migration hook, the
  NPC-GUID → inn helper.
- `SyncProtocol.lua` (pure): message encoders, strict decoder, digest, every validation
  rule, rate limiter, the "should we ask?" decision.
- Their busted specs, including every hostile case in [§6](#6-test-plan).

**Out:**
- `Sync` glue (events, sending, sender resolution, combat hold, `issecretvalue` checks).
  [§8](#8-contract-for-the-sync-slice) fixes what it must do; its own ticket builds it.
- `Sign`, `Phrase`, `Collection`, `Cosmetics`, `Export`, UI, Core wiring of the
  SavedVariables table (lands with the first glue that needs it).
- Filling `Data/Inns` / `Data/Phrases` (tests use fixture tables).
- Camps, a global channel, whispers, deleting own entries: not in v1.

## 3. Approach

Binding decisions ([decisions.md](../decisions.md)): *Sync: own receive handler and
codec, single messages, no compression* · *Sender identity is resolved per channel* ·
*Accept only a sender's own signatures* · *Canned phrases, not free text* · *Sync may
read combat state* · and the three 2026-09-27 entries this spec adds (*Sync wire format
v1 and digest*, *Ledger storage caps and SavedVariables shape*, *Peer-data rate limits
and time window*).

### 3.1 Shared constants

Defined once, in `Ledger.LIMITS` (Ledger loads before SyncProtocol in the TOC) and read
by `SyncProtocol`:

| Name | Value | Why |
|---|---|---|
| `innMax` | 9 999 999 (≤ 7 digits) | retail NPC IDs are ≤ 6 digits; one digit of headroom for Forever's new NPCs |
| `phraseIdMax` | 9 999 (≤ 4 digits) | `Data/Phrases` IDs must stay in 1..9999 |
| `phraseIdsMax` | 5 | template + word + conjunction + template + word; `Phrase` may use fewer |
| `sealMax` | 999 (≤ 3 digits) | seal cosmetic IDs; 0 on the wire means "no seal" |
| `tMin` | 1 789 603 200 (2026-09-17 00:00 UTC, the beta start) | before this no Forever character existed; the same build works in beta and at launch |
| `tMax` | 9 999 999 999 (10 digits) | keeps every timestamp exactly 10 digits on the wire |
| `futureTolerance` | 300 s | both sides use `GetServerTime()`; 5 min covers skew |
| `nameMaxBytes` | 96 | display only; covers two-part names, UTF-8 and a realm suffix |
| `cosmeticIdMax` | 9 999 | for earned times |
| `weekLength` | 604 800 s | 7 days; signing weeks follow the game's weekly reset, whose time the glue passes in (4.4, 8) |

`Ledger.CAPS` and `SyncProtocol` rate limits are in [§4](#4-data-model) and
[§5.3](#53-rate-limits).

### 3.2 Wire format (protocol version 1)

Prefix `InnLedger`. The **message** (the text argument, prefix excluded) is ASCII,
at most **255 bytes** (retail value, **verify** on Forever, #12). Grammar (ABNF-style;
`DIGIT` = `0-9`, `NZ` = `1-9`):

```
message   = hello / want / entries
hello     = "H1:" count ":" digest
want      = "W1:" guid ":" since
entries   = "E1:" entry *4( ";" entry )           ; 1..5 entries
entry     = inn "," time "," phrase "," seal
phrase    = phraseid *4( "." phraseid )           ; 1..5 IDs, order kept
count     = "0" / NZ [DIGIT]                      ; 0..40 (<= SHARE_MAX)
digest    = "0" / NZ 0*9DIGIT                     ; 0..2147483646
since     = "0" / time
inn       = NZ 0*6DIGIT                           ; 1..9999999
time      = NZ 9DIGIT                             ; exactly 10 digits
phraseid  = NZ 0*3DIGIT                           ; 1..9999
seal      = "0" / NZ 0*2DIGIT                     ; 0 = none, else 1..999
guid      = "Player-" 1*DIGIT "-" 1*HEXDIG        ; <= 40 bytes total (verify, #12)
```

Rules that aren't visible in the grammar:
- **No leading zeros, signs, spaces, decimals, exponents or hex** in numbers. Every
  number has exactly one spelling, so the digest and dedupe see one form.
- **Signer and name are never on the wire.** The receiver fills them in from the
  resolved sender. The only GUID on the wire is WANT's *target*, which is compared for
  equality with our own GUID and never stored in the ledger.
- **ENTRIES are broadcast** on the channel the WANT came from. Everyone in the group or
  guild may store them (they are the sender's own), so one reply serves every asker.
  For the same reason a WANT addressed to someone else is useful: it tells us a reply is
  coming, so we don't ask too (3.3).
- **Seal `0` decodes to `nil`** (no seal), and a `nil` seal encodes as `0`.
- **Order:** a reply sends entries with `t > since`, oldest first, 5 per message. A cut-off
  reply can then resume with `since` = the newest entry received.
- **Unknown type letter or version** (`H2`, `X1`, …): dropped quietly (a newer peer).

**Worked byte counts** (all ≤ 255):

| Message | Example | Bytes |
|---|---|---|
| HELLO, worst case | `H1:40:2147483646` | 16 |
| WANT, typical | `W1:Player-1234-0ABCDEF0:1793800000` | 34 |
| WANT, worst case (40-byte GUID) | 3 + 40 + 1 + 10 | 54 |
| One entry, typical | `1234,1793800000,1.22.3,0` | 24 |
| One entry, worst case | `9999999,9999999999,9999.9999.9999.9999.9999,999` | 47 |
| ENTRIES, 5 worst-case entries | `E1:` + 5 × 47 + 4 `;` | **242** |
| ENTRIES, 6 worst-case entries | 242 + 1 + 47 | 290 ✗ → hence max 5 |

A full share window (40 entries) is 8 ENTRIES messages, ≤ 1 936 bytes.

### 3.3 Digest

HELLO carries `count` and `digest` of the sender's **share window**: its newest
`SHARE_MAX` (40) own entries, sorted ascending by `(t, inn)`.

```
canon(e)   = inn "," t "," phrase-ids-joined-by-"." "," (seal or 0)   -- same as the wire entry
text       = canon(e1) ";" canon(e2) ";" ...                        -- "" for no entries
digest     = h, where h = 0; for each byte b of text: h = (h * 257 + b) % 2147483647
```

- **Pure Lua 5.1 arithmetic, no `bit` library.** `h < 2^31`, so `h * 257 + 255 < 2^40`,
  far inside the 2^53 range doubles hold exactly. `%` on such values is exact (the
  quotient is < 2^9, so `floor(a / b)` can't round across an integer).
- **Test vectors** (computed in Lua 5.1 and cross-checked with arbitrary-precision
  arithmetic):

  | Window | `text` | digest |
  |---|---|---|
  | empty | `` | `0` |
  | A = `{inn=1234, t=1793800000, phrase={1,22,3}}` | `1234,1793800000,1.22.3,0` | `1244322287` |
  | A, B (B = `{inn=98765, t=1793900000, phrase={7}, seal=12}`) | `1234,1793800000,1.22.3,0;98765,1793900000,7,12` | `2020135697` |
  | B, A (wrong order, for the sort test) | `98765,1793900000,7,12;1234,1793800000,1.22.3,0` | `1242196279` |

- **Why collisions are acceptable:** the digest only decides whether to ask. A chance
  collision (about 1 in 2.1 × 10⁹ per change) leaves one peer's view stale until the
  sender's next signature changes its window. A forged digest gains nothing: a sender
  can only make others ask, or not ask, for *its own* entries, and asking is capped per
  peer (below), so churning digests can't trigger a WANT storm.
- **The receiver compares against what it holds for that sender**
  (`ledger:signerEntries(guid)`, same sort). Because `CAPS.perSigner == SHARE_MAX`, a
  receiver that holds everything holds exactly the sender's window.

**When to WANT** (`SyncProtocol.decideWant(memo, guid, channel, count, digest, held, now)`,
pure; `held` = `ledger:signerEntries(guid)`; returns a `since` to ask with, or `nil`).
`memo = { asked = {}, seen = {} }` is a per-session table owned by `Sync`.
1. `count == 0` → `nil`.
2. `#held == count` and `digest(held) == digest` → in sync, `nil`.
3. **Per-peer cap, whatever the digest.** `a = memo.asked[guid]`; treat it as absent if
   `now < a.start` or `now >= a.start + 600`. If `a.n >= 2` → `nil`. So each peer costs
   at most **2 WANTs per 10 minutes**, however often its digest changes.
4. `since` = `0` if `a` is present (the second ask fills a gap from a lost message or
   from our own eviction), else the newest held `t` (or `0` if nothing is held).
5. **Suppression.** `s = memo.seen[channel .. ":" .. guid]` (a WANT for this peer seen on **this** channel,
   from anyone). If `0 <= now − s.at <= 30` and `s.since <= since` → `nil`: a broadcast
   reply that covers us is already coming.
6. Record and ask: `memo.asked[guid]` = `{ start = now, n = 1 }` if `a` was absent, else
   `a.n = 2`; `memo.seen[channel .. ":" .. guid] = { at = now, since = since }`; return `since`.

`receive` fills `memo.seen` from WANTs addressed to others, keyed by the channel they came on (5.1 rule 13): a reply only reaches the channel the WANT was sent on, so a WANT on GUILD must not suppress an ask on PARTY. `asked` and
`seen` hold at most 1 000 keys each; on a new key with the table full, expired keys are
pruned first, and if it's still full the table is cleared (which at worst allows two
more WANTs per peer). `Sync` calls `decideWant` after a random 1–5 s delay, not on
receipt, so the first asker's WANT has time to suppress the others (8).

### 3.4 Rejected alternatives

- **Base36 or binary numbers on the wire:** saves ~7 bytes per entry (6 entries per
  message instead of 5) at the cost of a harder-to-audit parser.
- **Per-entry version on the wire:** the message header already versions the entry
  format; it would cost 2 bytes per entry.
- **Replies by whisper:** whispers aren't an accepted channel in v1, and a broadcast
  reply serves every asker at once.
- **CRC32 / FNV / djb2-xor digests:** they need bitwise operations. Emulating them in
  arithmetic is slow and easy to get wrong; the client's `bit` library isn't in busted's
  Lua, so tests wouldn't run the shipped code.
- **Count + newest `t` as the "digest":** misses a lost middle message when a later
  signature lands; the hash costs nothing extra.
- **Sending the full entry list instead of a digest:** 8 messages per peer per HELLO.
- **Dropping a whole ENTRIES message for one unknown inn/phrase:** a peer with a newer
  `Data/Inns` would lose up to 4 good entries per message. Syntax errors still drop the
  whole message ([§5.1](#51-validation-table)).

## 4. Data model

### 4.1 Entry (in memory and in storage)

```
Entry { inn = int, t = int, phrase = { int, ... }, seal = int or nil }
```

- **Changed from the architecture sketch:** the per-entry `v` field moves to the ledger
  (`schema`) and to the message header (`H1`/`W1`/`E1`); `signer` and `name` are held
  once per traveler rather than per entry. The dedupe key is unchanged:
  `(signer, inn, t)`.
- An entry is **structurally valid** (`Ledger.validEntry(e)`) when: `e` is a table;
  `inn` is an integer in 1..`innMax`; `t` an integer in `tMin`..`tMax`; `phrase` an
  array (no holes, no extra keys) of 1..`phraseIdsMax` integers in 1..`phraseIdMax`;
  `seal` is nil or an integer in 1..`sealMax`; no other keys. "Integer" means
  `type(x) == "number" and x == x and x % 1 == 0` plus the range check, so `NaN`, `inf`
  and fractions fail.

### 4.2 SavedVariables

AceDB-3.0, SavedVariable `InnkeepersLedgerDB`. Ledgers are per character, keyed by the
character's **GUID** (identity is the GUID; names are display only and may change):

```lua
InnkeepersLedgerDB.global.ledgers["Player-1234-0ABCDEF0"] = {
  schema = 1,
  me = { name = "Aldric Stonebrook" },           -- latest own name, display only
  own = {                                        -- own entries, sorted by (t, inn)
    { inn = 1234, t = 1793800000, phrase = { 1, 22, 3 } },
  },
  travelers = {                                  -- foreign entries, by signer GUID
    ["Player-1234-0BBBBBB0"] = {
      name = "Mira Ashvale",                     -- latest resolved name, display only
      met = 1793800100,                          -- server time of the first accepted entry
      entries = { { inn = 1234, t = 1793800050, phrase = { 4, 5 }, seal = 2 } },
    },
  },
  earned = { [12] = 1793800500 },                -- cosmetic ID -> time first earned
  quarantine = { },                              -- own entries that failed load checks
}
```

- `Core` hands `Ledger.new` the table `db.global.ledgers[guid]` (creating `{}` on first
  login). That wiring lands with the first glue module that needs it.
- **Export needs** (#11 comment, [export-format.md](../export-format.md)): `earned`
  carries the time each cosmetic was earned; `travelers` keeps every received entry with
  signer GUID, inn and time, which is what a later "witnessed stamps" fingerprint uses.

### 4.3 Load, versions and migration

`Ledger.new(data, owner, weekAnchor)` with `owner = { guid = <string>, name = <string> }`
and `weekAnchor` = the server time of any weekly reset, past or future (4.4). `Core`
creates `{}` only when the saved value is `nil`; it never replaces a non-table.
1. `owner.guid` fails `Ledger.validGUID`, or `weekAnchor` isn't an integer in
   0..`tMax` → error (a programming bug in the caller, not peer data).
2. `data` isn't a table → an empty **read-only** ledger.
3. `data` is empty → initialize it as schema 1 with all six fields: `schema`, `me`
   (`{ name = owner.name }` if that passes `validName`, else `{}`), `own`, `travelers`,
   `earned` and `quarantine` (empty tables). A missing field on a non-empty table counts
   as the wrong type in step 6.
4. `data.schema == Ledger.SCHEMA` → use it.
5. `data.schema` an integer in 1..`SCHEMA`−1 → **migrate**: deep-copy `data`, run
   `Ledger.MIGRATIONS[n](copy)` for n = schema .. SCHEMA−1 (each takes n to n+1 and sets
   `schema`) inside `pcall`. On success, write the copy back into `data` in place
   (clear its keys, copy the new ones in, so AceDB keeps the same table). On any error,
   or if the result's `schema` isn't `SCHEMA` or a top-level field has the wrong type
   (step 6), `data` stays untouched and the ledger opens read-only. v1 has no migrations; v2 adds
   `MIGRATIONS[1]` with a fixture test of the v1 shape.
6. **Read-only** in every other case: `schema` above `SCHEMA` (a downgraded AddOn),
   missing or not an integer on a non-empty table, or a top-level field of the wrong
   type (`own`, `travelers`, `earned`, `quarantine` not tables; `me` not a table).
   Player data is never destroyed by a version mismatch or damage.

**Read-only ledgers** set `ledger.readOnly = true`, never write to `data`, and answer
queries from in-memory copies built by the same normalize pass run on a deep copy (so
the player can still read a damaged ledger where parts are sound). Every write
(`addOwn`, `addForeign`) returns `"readonly"`; `markEarned` and `setOwnerName` return
`false`. `SyncProtocol.receive` drops everything for a read-only ledger (5.1 rule 2),
and `Sync` sends nothing from one.

**Normalize** (on `data` itself for a writable ledger, on a copy for a read-only one):
- drop foreign entries that fail `validEntry`;
- drop traveler records whose key fails `validGUID`, whose key is the owner's GUID, or
  whose `name` fails `validName`, or that have no valid entries left;
- a traveler's `met` that isn't an integer in `tMin`..`tMax` becomes its oldest entry's
  `t`;
- drop `earned` pairs whose key or time fails the `markEarned` checks;
- move invalid own entries to `quarantine` (at most 100 items in all, existing items
  first; beyond that they're dropped), and drop non-table `quarantine` items and
  non-table own "entries" (they carry nothing worth keeping);
- a `me.name` that fails `validName` becomes `owner.name` if that passes, else is
  removed;
- remove duplicate keys (first kept), sort, rebuild the indexes;
- for foreign entries, apply the weekly rule (4.4): per signer, keep the earliest entry
  of each `(inn, week)` and drop the rest. Own entries are never dropped for it (they're
  the player's own history);
- re-apply the caps (in case a later version lowers them): remove the oldest
  repeatedly until under every cap, in the order perSigner, perInn, foreignTotal.

`ledger.loadReport` counts what was dropped, quarantined or reset, for the debug log:
`foreignDropped`, `travelersDropped`, `metReset`, `earnedDropped`, `quarantined`,
`quarantineDropped`, `nameReset`, `duplicates`, `weekly`, `evicted`, plus `migrated`
(boolean) and, for a read-only ledger, `reason` (`"not_table"`, `"bad_field"`,
`"bad_schema"`, `"newer_schema"` or `"migration_failed"`).

Indexes (in memory, never saved): dedupe set keyed `signer .. "\0" .. inn .. "\0" .. t`,
foreign count per inn, total foreign count.

### 4.4 Caps and eviction

`Ledger.CAPS`:

| Cap | Value | Why |
|---|---|---|
| `perSigner` | 40 | equals `SHARE_MAX`: a traveler's newest 40 signatures, i.e. their whole share window |
| `perInn` | 150 | a busy inn's page shows the newest 150 travelers' signatures |
| `foreignTotal` | 3 000 | ≈ 400 KB of SavedVariables at ~130 bytes per stored entry |

Own entries are never evicted and have no cap.

**One signature per inn per week** (decisions.md → 2026-09-27 — Re-signing follows the
game's weekly reset). A signing week runs from one weekly reset up to the next.
`ledger:weekOf(t) = math.floor((t − weekAnchor) / weekLength)`, where `weekAnchor` is the
reset time passed to `Ledger.new` (week numbers may be negative; only equality matters).
The ledger stays region-agnostic: the glue supplies the reset time of the player's own
region (8). Players only ever sync with their own region (Forever is realmless per
region, and regions never group or share guilds), so both sides of a sync agree on the
weeks. A signer may hold at most one entry per `(inn, weekOf(t))`, and the ledger
enforces it for both sides:
- **Own:** `addOwn` returns `"too_soon"` when an own entry at that inn already falls in
  the same week. `ledger:canSign(inn, now)` answers the same question for the `Sign` UI,
  and `ledger:nextWeekStart(now)` gives the time of the next reset (for "sign again
  after …" text).
- **Foreign:** `addForeign` returns `"too_soon"` when that signer already has a stored
  entry at that inn in the same week; the first stored one wins. An honest client never
  sends two, so this only bites modified clients: one signer can claim at most one
  signature per inn per week, instead of filling all 40 of its slots at one inn.
- Own entries and foreign entries don't limit each other (the rule is per signer).

`addForeign` on a new, valid, non-duplicate entry:
1. Insert it (creating the traveler record with `met = now` if needed). If the entry
   is kept (the result is `"added"`), update the traveler's `name` to the given one.
2. If the signer now holds more than `perSigner`: remove the signer's oldest.
3. If the inn now holds more than `perInn` foreign entries: remove the inn's oldest.
4. If the total exceeds `foreignTotal`: remove the oldest foreign entry anywhere.
5. Drop a traveler record that has no entries left.

"Oldest" = smallest `(t, signer, inn)`, compared in that order (a total order, since
`(inn, t)` is unique per signer). Signer GUIDs compare **byte by byte**, never with Lua's
string `<`, which follows the C locale's collation (decisions.md → 2026-09-27 — Ledger
orders by bytes). On an add, each step removes at most one entry. If the
new entry is the one removed, the result is `"dropped"`: the store always holds the
newest entries under every cap.

### 4.5 Ledger API

All functions are pure. Returned arrays are new tables; the entry tables inside them are
shared and must not be modified by callers. `addOwn` and `addForeign` store a **copy**
of the entry they're given, so a caller changing its table later can't corrupt the store
or its indexes.

| Function | Returns |
|---|---|
| `Ledger.new(data, owner, weekAnchor)` | a ledger object (see 4.3); `ledger.readOnly`, `ledger.loadReport` |
| `Ledger.validEntry(e)` | boolean (4.1) |
| `Ledger.validGUID(s)` | boolean: a string of ≤ 40 bytes matching `^Player%-%d+%-%x+$` |
| `Ledger.validName(s)` | boolean: the name rule (5.2) |
| `Ledger.innFromNpcGUID(guid, inns)` | NPC ID if `guid` is a creature GUID whose NPC ID is a key of `inns`, else `nil`; never throws (5.2) |
| `ledger:weekOf(t)` / `ledger:nextWeekStart(now)` | the signing-week number of `t` / the time of the first weekly reset after `now` (4.4) |
| `ledger:canSign(inn, now)` | `false` if an own entry at `inn` falls in `weekOf(now)` (or the ledger is read-only, or `inn` / `now` isn't a valid integer), else `true` |
| `ledger:addOwn(e)` | `"added"`, `"dup"`, `"too_soon"`, `"invalid"`, `"readonly"` |
| `ledger:addForeign(signer, name, e, now)` | `"added"`, `"dup"`, `"too_soon"`, `"dropped"`, `"invalid"`, `"self"` (signer is the owner), `"readonly"` |
| `ledger:ownerGUID()` | the owner's GUID |
| `ledger:has(signer, inn, t)` | boolean |
| `ledger:own()` | own entries, `(t, inn)` ascending |
| `ledger:shareWindow(n)` | newest `n` own entries, `(t, inn)` ascending |
| `ledger:signerEntries(guid)` | that traveler's entries, `(t, inn)` ascending (empty for unknown) |
| `ledger:innEntries(inn)` | `{ own = { entry, ... }, foreign = { { signer = guid, name = s, entry = e }, ... } }`, `own` in `(t, inn)` order, `foreign` in `(t, signer)` order, both ascending |
| `ledger:travelers()` | `{ { guid = s, name = s, met = t, count = n }, ... }`, `met` descending, then `guid` (byte order) |
| `ledger:counts()` | `{ own = n, foreign = n, travelers = n }` |
| `ledger:setOwnerName(name)` | `true` if `name` passes `validName` and was stored in `me.name`, else `false` |
| `ledger:markEarned(id, t)` | `true` for a valid call (the cosmetic is recorded; an earlier stored time is kept); `false` if `id` isn't an integer in 1..`cosmeticIdMax`, `t` isn't an integer in `tMin`..`tMax`, or the ledger is read-only |
| `ledger:earnedAt(id)` / `ledger:earned()` | time or nil / a copy of the map |

`addForeign` checks its own inputs as a second line of defense (`validGUID(signer)`,
`validName(name)`, `validEntry(e)`, `now` an integer in `tMin`..`tMax`), but known-ID
and time-window checks live in `SyncProtocol`.

## 5. Security notes

**Flag for the reviewer: security-level review.** Everything below is attack surface.

### 5.1 Validation table

`SyncProtocol.receive` runs these in order and stops at the first failure. Nothing is
written to the ledger until every whole-message check has passed. Result is
`nil, reason` for a drop; reasons are for the debug log and the tests.

| # | Rule | Exact check | On failure | Test (in `spec/sync_protocol_spec.lua`) |
|---|---|---|---|---|
| 1 | Never throws | the whole body runs inside `pcall` | `nil, "error"` | `receive never throws on a hostile value in any argument` |
| 2 | Context sane | `ctx` is a table (its fields are read with `rawget`); `ctx.now` an integer in 0..`tMax`; `ctx.selfGUID` passes `Ledger.validGUID` and equals the ledger owner's GUID; `ctx.limiter` has `admit` and `admitEntries`; `ctx.wantMemo.seen`, `ctx.inns`, `ctx.phrases` and `ctx.seals` are tables; `ctx.phraseOk` is nil or a function; then `ctx.ledger` is not read-only (a read-only ledger gives `"readonly"`) | `"ctx"` / `"readonly"` | `drops everything when selfGUID is a hidden-value stand-in`; `… when the ledger is read-only` |
| 3 | Channel | `channel` is `"PARTY"`, `"RAID"` or `"GUILD"` | `"channel"` | `drops WHISPER, CHANNEL, SAY, INSTANCE_CHAT and nil` |
| 4 | Sender resolved | `sender` is a table; `Ledger.validGUID(sender.guid)`; `Ledger.validName(sender.name)` (5.2) | `"sender"` | `drops a nil, empty, non-string or malformed sender GUID`; `drops a sender name with a pipe or control byte` |
| 5 | Not our own echo | `sender.guid ~= ctx.selfGUID` | `"self"` | `drops our own messages echoed back by the channel` |
| 6 | Size first | `type(msg) == "string"` and `1 <= #msg <= 255` | `"size"` | `drops a 256-byte message unread`; `drops an empty message` |
| 7 | Rate (messages) | limiter admits the message (5.3); counted before parsing, so junk counts too | `"rate"` | `drops the 41st message from one sender within 60 s`; `admits again after the window` |
| 8 | Charset | no byte outside `0-9 A-Z a-z : ; , . -`, checked with explicit byte ranges (this also rejects AceComm's multi-part marker bytes `\001`–`\004`, `|`, spaces, NUL and UTF-8) | `"charset"` | `drops multi-part-marked messages`; `drops a message with a pipe escape`; `… with NUL`; `… with a space` |
| 9 | Header | matches `^[A-Z]%d+:`; type in `H`/`W`/`E`; version string exactly `"1"` | `"header"` / `"version"` | `drops an unknown type`; `drops version 2 and version 01` |
| 10 | Schema | exact grammar of 3.2 for the type: field count, separators, no empty fields, no trailing separator, 1..5 entries, 1..5 phrase IDs; WANT target passes `Ledger.validGUID` | `"schema"` | `drops an ENTRIES with 6 entries`; `… a phrase with 6 IDs`; `… an extra field`; `… a missing field`; `… ;; and a trailing ;`; `… a malformed WANT target` |
| 11 | Numbers | each token matches its digit pattern and max length **before** `tonumber`; then the range; so `NaN`, `inf`, `1e9`, `0x1F`, `-5`, `1.5`, `007` and overlong digit strings all fail (`+5` and `" 5"` already fail rule 8, and a 400-digit string rule 6; the tests use 200-digit tokens here) | `"number"` | `drops NaN, inf, exponent, hex, signed, decimal, leading-zero and overlong numbers` (one case each) |
| 12 | HELLO consistency | `count <= SHARE_MAX`; `count == 0` implies `digest == 0` | `"schema"` | `drops HELLO count 41`; `drops count 0 with a non-zero digest` |
| 13 | WANT `since` and target | `since == 0` or `tMin <= since <= now + futureTolerance`. A target other than `ctx.selfGUID` is not an error: it is recorded in `ctx.wantMemo.seen[channel .. ":" .. target]` (3.3) and returned as `want_seen`; it is never stored in the ledger | `"number"` | `records a WANT for someone else as seen`; `a WANT target is never stored in the ledger`; `since 0 passes` |
| 14 | Rate (entries) | limiter admits all parsed entries of the message for this sender, counted **before** the per-entry skips of rules 15–16 (5.3) | whole message `"rate"` | `drops ENTRIES past 80 entries per sender per minute` |
| 15 | Time window (per entry) | `tMin <= t <= now + futureTolerance` | entry skipped (`rejected`) | `skips an entry from before tMin`; `skips an entry 301 s in the future, keeps one 300 s ahead` |
| 16 | Known IDs (per entry) | `ctx.inns[inn] ~= nil`; **every** phrase ID has `ctx.phrases[id] ~= nil`, **and** `ctx.phraseOk(ids)` returns exactly `true` when that hook is given (additive: the hook can only reject more; it's called on a copy of the IDs, inside `pcall`, and an error rejects the entry); seal `nil` or `ctx.seals[seal] ~= nil` | entry skipped (`rejected`) | `skips an unknown inn but keeps its valid siblings`; `… unknown phrase ID`; `… unknown seal`; `a permissive phraseOk can't admit an unknown ID` |
| 17 | Own-signature | signer and name come only from `sender`; the entry is stored with `ledger:addForeign(sender.guid, sender.name, e, now)` | n/a (no other path exists) | `stores a relayed copy of B's entry under the relayer A, never under B`; `a GUID inside an entry is dropped and nothing is stored` (assert `nil` and no storage, not a specific reason) |
| 18 | Dedupe / replay / weekly | ledger dedupe on `(signer, inn, t)`; the first stored copy wins (a later copy with a different phrase is a dup); a second entry from the same signer at the same inn in the same week is `"too_soon"` (4.4) | counted as `dup`; `too_soon` counted as `rejected` | `replaying an ENTRIES 1 000 times leaves storage unchanged`; `a conflicting re-send doesn't overwrite`; `a second signature at one inn in one week is rejected, siblings kept` |
| 19 | Caps | ledger caps and eviction (4.4) | counted as `dropped` | see `spec/ledger_spec.lua` |

Successful results:
- HELLO → `{ kind = "hello", count = n, digest = n }`. `Sync` later calls `decideWant`
  (3.3, 8).
- WANT for us → `{ kind = "want", since = n }`.
- WANT for someone else → `{ kind = "want_seen", target = guid, since = n }`, after
  recording it in `ctx.wantMemo.seen[channel .. ":" .. target]` as `{ at = now, since }`
  (keeping the smaller `since` if one was seen in the last 30 s; `at` always becomes
  `now`).
- ENTRIES → `{ kind = "entries", added = n, dup = n, dropped = n, rejected = n }`, where
  `rejected` counts the rule 15–16 skips, `"too_soon"`, and any `addForeign` result of
  `"invalid"`, `"self"` or `"readonly"` (the last three shouldn't occur after
  validation; they're counted, not raised).

### 5.1a SyncProtocol API

| Name | Kind | Value / returns |
|---|---|---|
| `VERSION` | constant | `1` |
| `MAX_BYTES` | constant | `255` |
| `MAX_ENTRIES_PER_MSG` | constant | `5` |
| `SHARE_MAX` | constant | `Ledger.CAPS.perSigner` (40); read from `Ledger`, not a second literal |
| `CHANNELS` | constant | `{ PARTY = true, RAID = true, GUILD = true }` |
| `LIMITS` | constant | the 5.3 numbers: `{ window = 60, perSenderMessages = 40, perSenderEntries = 80, globalMessages = 1200, maxSenders = 1000 }` |
| `validName`, `validGUID` | alias | `Ledger.validName`, `Ledger.validGUID` |
| `canon(e)` | function | the canonical text of one entry (3.3) |
| `digest(entries)` | function | integer digest of an array of entries, used in the order given (callers pass `(t, inn)` ascending) |
| `encodeHello(window)` | function | one string `H1:<#window>:<digest(window)>` |
| `encodeWant(targetGUID, since)` | function | one string |
| `encodeEntries(window, since)` | function | an array of strings, each ≤ 255 bytes, entries with `t > since`, oldest first, 5 per message; `{}` if none |
| `receive(msg, channel, sender, ctx)` | function | a result table (5.1) or `nil, reason`; never throws. `sender = { guid, name }`; `ctx = { now, selfGUID, inns, phrases, phraseOk?, seals, ledger, limiter, wantMemo }` |
| `newLimiter()` | function | a limiter with `:admit(guid, now)` → boolean (one message) and `:admitEntries(guid, n, now)` → boolean |
| `newWantMemo()` | function | `{ asked = {}, seen = {} }` |
| `decideWant(memo, guid, channel, count, digest, held, now)` | function | `since` or `nil` (3.3) |

The encoders take our own entries, which `Ledger` has already validated; they still
raise (a caller bug, never peer data) on an entry that fails `Ledger.validEntry`, a HELLO
window over `SHARE_MAX`, a WANT target that fails `validGUID`, a WANT `since` that isn't `0`
or a valid time, an `encodeEntries` `since` that isn't an integer in 0..`tMax`, and any
message over `MAX_BYTES`. The limiter refuses (returns `false`)
a non-string GUID or a `now` that isn't an integer in 0..`tMax`; `admitEntries` also
refuses an `n` outside 0..`MAX_ENTRIES_PER_MSG` and a sender with no open window (it
follows an admitted message in the same window). `decideWant` returns `nil` on arguments
of the wrong type or range. All client values arrive as arguments; `SyncProtocol` reads
no globals, and it asserts `ns.Ledger` is present when it loads.

### 5.2 Hidden ("secret") values and identity

Forever may hand addons hidden values (unverified;
[platform-forever.md](../platform-forever.md) → AddOns and the API; checked in #12).
The design never depends on them arriving:
- **Unreadable innkeeper NPC ID → can't sign here.** `Ledger.innFromNpcGUID` returns
  `nil` for anything that isn't a readable string matching
  `^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-%x+$` with an NPC ID of 1..7 digits, no leading
  zero, that is a key of `inns`. It runs inside `pcall`, so a value that errors on any operation also gives
  `nil`. `Sign` shows no option on `nil`. The creature GUID format is **verify** (#12).
- **Unreadable sender → drop the message.** Rules 1, 2 and 4: a sender or self GUID or
  name that isn't a plain string, or that errors when touched, is a drop. (In Lua 5.1 a
  string compared with a table or userdata is simply unequal and `__eq` never runs, so
  equality checks alone would not catch a stand-in; the type and pattern checks do.) `Sync` also checks
  `issecretvalue` where it exists before calling (8).
- **Never a guess:** no fallback to a name lookup, no retry, no partial entry.
- **Test stand-ins:** busted can't make a real hidden string, so tests use a `newproxy`
  userdata and a table whose metatable raises on `__index`, `__len`, `__eq`, `__lt`,
  `__le`, `__concat`, `__tostring` and `__call`, passed as every argument in turn. A
  hidden value that reports `type() == "string"` can only be tested in the client; the
  `pcall` in rule 1 is the backstop and #12 checks the real behavior.
- **Identity is the GUID.** Names are display only. The **name rule**
  (`Ledger.validName`): a string of 2..96 bytes with no byte below 32, no 127 and
  no `|`; split at the first `-` into a name part and an optional realm part; the name
  part is one word or two words joined by one space, each word only `A-Za-z` and bytes
  128–255, the first 2..48 bytes and the second (the surname) 1..48 bytes; the realm part,
  if present, is 1..48 bytes of `A-Za-z0-9'-` and bytes 128–255 and doesn't end in
  `-`. Two-part (surname) names pass. The server issues these names, so this is
  defense in depth against UI escapes, not a filter on real names.
- **Patterns use explicit byte ranges** (`[A-Za-z]`, `[\128-\255]`), never `%a`, `%w`,
  `%l` or `%u`, whose meaning depends on the C locale. `%d` and `%x` are fine.

### 5.3 Rate limits

`SyncProtocol.newLimiter()` returns a limiter with fixed 60-second windows. A sender's
window starts at its first admitted message and resets when `now >= start + 60` **or**
`now < start` (server time jumped back). The global window works the same way, starting
at the first message any sender gets admitted.

| Limit | Value | Why |
|---|---|---|
| Messages per sender per window | 40 | the honest send budget (8) is 30 per any 60 s; 10 of headroom for delivery bunching |
| Entries per sender per window | 80 | the honest budget is 60 entries per any 60 s (one full window plus a partial reply) |
| Messages across all senders per window | 1 200 | ≥ 39 raid members × 30 (the most honest traffic one raid can produce); only messages the per-sender limit **admitted** count, so one flooding peer can't use it up alone |
| Tracked senders | 1 000 | on a new sender with the table full, expired windows are pruned first; if it is still full the message is dropped (fail closed) |

Over any limit: drop silently (rule 7 or 14). A dropped message or batch is charged to
**no** counter: `admit` checks the per-sender and global limits first and increments
both only when both admit. `now` is an argument (seconds). Limits are per resolved
sender GUID, so switching names doesn't reset them.

**Traffic model** (what the numbers are checked against; `Sync` enforces the send side,
see 8):
- **Honest sender, any 60 s, all channels together:** ≤ 30 messages and ≤ 60 entries;
  ≤ 1 HELLO per channel; ≤ 12 WANTs; ≤ 1 reply per channel per 30 s; ≤ 1 full
  (`since = 0`) reply per channel per 5 min unless its window changed.
- **40-player raid syncing from scratch, first minute, at one receiver:** 40 HELLOs;
  WANTs about 1–3 per member raid-wide after the 1–5 s jitter and suppression (≤ 120);
  one coalesced full reply per member (8 messages × 40 = 320). About 480 messages, under
  the 1 200 ceiling; the hard upper bound (39 × 30 = 1 170) is under it too. Members that
  hit the 12-WANT budget finish in the next minute. The `Sync` glue's model of its actual
  rules puts WANTs higher (about 8 per member) and still under every limit
  ([sync-glue.md §3.5.2](sync-glue.md#352-the-send-budget) → Traffic check).
- **A hostile peer churning its digest** gets at most 2 WANTs per honest peer per
  10 minutes, fewer after suppression. **A hostile peer spamming `W…:0`** gets at most
  one full reply per channel per 5 minutes. **A hostile flood** is cut at 40 messages
  and 80 entries a minute and at most 40 stored entries (per-signer cap).

### 5.4 Quiet failure

`SyncProtocol` and `Ledger` never print, raise UI or throw on peer data. They return a
reason; `Sync` may write it to a debug log that is off by default.

### 5.5 Forbidden-API guard

`Ledger.lua` and `SyncProtocol.lua` must pass `scripts/check-apis.sh` as they are:
**don't name any listed API even in a comment** (for example, write "the combat flag"
rather than the function's name). The `Sync.lua` allow-list for the combat-state names
widens only in the `Sync` slice (8).

## 6. Test plan

busted, pure modules loaded through `spec/helpers/load.lua` in the strict environment,
with fixture `inns` / `phrases` / `seals` tables. Use fixed `now` values, never the
clock.

### `spec/ledger_spec.lua`

- **validEntry:** accepts a minimal and a maximal entry; rejects each field missing,
  wrong type, out of range, `NaN`, `inf`, `-inf`, `1.5`, `0`; a phrase with 0 or 6 IDs, a
  hole or an extra key; an extra top-level key; `seal = 0`.
- **validGUID / validName:** accept `Player-1234-0ABCDEF0`, `Aldric`, `Aldric
  Stonebrook`, `Aldric-Azjol-Nerub`, a UTF-8 name; reject `player-1-AB`, `Player--AB`,
  `Player-1-`, `Player-1-AB-CD`, `Player-1-0x1F`, a 41-byte GUID, an embedded NUL, a
  pipe, a control byte, two spaces, three words, a trailing `-`, 1 and 97 bytes,
  non-strings.
- **Weeks** (fixture `weekAnchor` = 1 790 089 200, Tuesday 2026-09-22 15:00 UTC, the
  retail US reset): `weekOf` of the anchor is 0, of `anchor − 1` is −1; Tuesday
  14:59:59 and 15:00:00 UTC differ by one; `nextWeekStart` at, just before and just after
  a boundary; an anchor a few weeks in the future partitions time exactly like the past
  one; `Ledger.new` errors on a missing, fractional or `NaN` anchor.
- **Anchor change on load:** a ledger saved under one anchor and reopened under an anchor
  shifted by a day re-applies the weekly rule to foreign entries and keeps every own
  entry.
- **addOwn:** added; dup on the same `(inn, t)`; `"too_soon"` for the same inn later in
  the same week, `"added"` at the next reset (Tuesday 15:00:00 UTC in the fixture); a different inn in the same
  week is fine; `canSign` agrees with `addOwn` on each case; invalid; kept sorted by
  `(t, inn)` whatever the insert order; own entries survive any number of foreign adds
  (never evicted); changing the caller's table after `addOwn` changes nothing stored.
- **addForeign:** added with traveler record (`name`, `met = now`); dup; conflicting
  re-send doesn't overwrite; `"too_soon"` for a second entry from one signer at one inn
  in one week (the first is kept), while another signer at the same inn in that week is
  added; `"self"` for the owner's GUID; invalid signer, name or entry; name updates on a
  later accepted entry; `met` doesn't change. Cap and flood fixtures give each signer
  distinct `(inn, week)` pairs so the weekly rule doesn't mask the caps.
- **Caps, one test per cap:** the 41st entry of a signer evicts that signer's oldest; an
  older 41st entry is itself `"dropped"`; the 151st foreign entry at an inn evicts the
  inn's oldest foreign; the 3 001st foreign entry evicts the global oldest; ties broken
  by `(t, signer, inn)`; a traveler with no entries left disappears; counts and indexes
  stay consistent after each eviction (`has` false for evicted keys, re-adding an evicted
  key works under the cap rules).
- **Flood:** 10 000 distinct valid foreign entries from 500 signers leave
  `counts().foreign == 3000` and no signer above 40, no inn above 150.
- **Queries:** `shareWindow(40)` with 0, 39, 40 and 100 own entries; `signerEntries` of
  an unknown GUID is empty; `innEntries` splits own and foreign; `travelers` order.
- **Cosmetics:** `markEarned` records, keeps the earliest time, rejects bad IDs and times.
- **Load:** empty table → schema 1; round trip (build, then `Ledger.new` on the same
  table) gives identical queries; `Ledger.new` with an invalid owner GUID errors.
- **Read-only (each case deep-compares the saved table before and after):** a non-table
  `data` → empty read-only ledger; schema 2; a non-empty table without `schema`; schema 1
  with `own` a string (and each other top-level field of the wrong type); a read-only
  ledger still answers queries from its sound parts; `addOwn` / `addForeign` return
  `"readonly"`; `markEarned` / `setOwnerName` return `false`.
- **Normalize:** invalid foreign entries dropped; traveler records with a bad GUID, a bad
  name, the owner's own GUID, or no valid entries dropped; a bad `met` becomes the oldest
  entry's `t` (and `travelers()` doesn't throw on it); bad `earned` pairs dropped; invalid
  own entries quarantined (capped at 100); a bad `me.name` reset; duplicates removed;
  a signer's second foreign entry at one inn in one week dropped (the earliest kept),
  while two own entries in one week are both kept;
  unsorted input sorted; caps re-applied when they're lowered (a fixture with 60 entries
  from one signer, 200 at one inn and 3 500 in total ends at 40 / 150 / 3 000, oldest
  removed); `loadReport` counts.
- **Migration:** with a fake `MIGRATIONS[1]` and `SCHEMA = 2`, a v1 fixture migrates and
  the same table object is updated in place; a migration that throws halfway leaves the
  table byte-for-byte unchanged and the ledger read-only.
- **innFromNpcGUID:** valid creature GUID of a known inn → ID; unknown NPC ID → nil;
  `Player-…`, `Pet-…`, `Vehicle-…` → nil; malformed, an 8-digit ID, a leading-zero ID,
  empty, nil, number → nil; the two hidden-value stand-ins → nil without throwing.

### `spec/sync_protocol_spec.lua`

- **Encoders:** `encodeHello` of the 3.3 vectors; `encodeWant`; `encodeEntries(window,
  since)` → 5 per message, `t > since` only, oldest first, every message ≤ 255 bytes with
  worst-case entries; a seal of nil encodes as `0`.
- **Digest:** the four vectors in 3.3; order matters; a changed phrase ID, seal or time
  changes the digest.
- **Round trip:** every encoder's output is accepted by `receive` and stores exactly the
  input entries under the sender.
- **Every rule in 5.1**, with the named test for each row, and in particular the
  **hostile cases** from [testing.md → Testing
  posture](../testing.md#testing-posture):
  - malformed: truncated at every byte position of a valid ENTRIES (each is a drop or a
    valid shorter message, never an error); random bytes (a seeded loop of 1 000
    strings) never throw and never store;
  - oversized: 256 bytes; 10 KB; a valid prefix followed by junk;
  - multi-part: AceComm-style `\001`…`\004` prefixed strings;
  - relayed (third-party): A sends B's exact entry → stored under A only;
  - replayed: the same ENTRIES 1 000 times → no growth, limiter trips at 41;
  - forged signer: a GUID or name smuggled into an entry field → dropped, nothing
    stored; a WANT naming another player is recorded as seen and never stored in the ledger;
  - unknown inn / phrase / seal IDs: entry skipped, siblings kept;
  - `NaN` / `inf` / hex / decimal / exponent / signed / leading zero / overlong;
  - out-of-range timestamps: `tMin − 1`, `now + 301`, and `9999999999`;
  - floods: 41 messages, 81 entries, 1 201 admitted messages from many senders, 1 001
    senders; one sender sending 1 000 messages doesn't stop a second sender being
    admitted (rejected messages don't count globally); a window resets when `now` goes
    backwards.
- **decideWant:** in sync → nil; count 0 → nil; first mismatch → newest held `t`;
  nothing held → 0; second ask for the same peer within 10 min → 0, **even with a
  different digest**; third → nil for 10 min whatever the digest, then allowed again;
  suppressed when `seen` has a WANT for that peer on the same channel within 30 s with a
  smaller-or-equal `since`, not suppressed at 31 s, with a larger `since`, or when the
  seen WANT came on another channel (a WANT seen on GUILD doesn't suppress a PARTY ask); a suppressed call doesn't
  use up the peer's two asks; `asked` / `seen` pruned then cleared at 1 000 keys.
- **Context and read-only:** `ctx` missing, `ctx.now` not an integer, `ctx.selfGUID`
  malformed or not the ledger owner → `"ctx"`; a read-only ledger → `"readonly"` for
  every message type.
- **Hidden values:** the two stand-ins as `msg`, `channel`, `sender`, `sender.guid`,
  `sender.name`, `ctx` and `ctx.selfGUID` → drop, no throw, nothing stored.
- **Purity:** both modules load in the strict environment; `luacheck` clean;
  `sh scripts/check-apis.sh` passes.

## 7. Acceptance criteria

- [ ] `Ledger.lua` implements 4.1–4.5 with the constants in 3.1 and 4.4.
- [ ] `SyncProtocol.lua` implements 3.2, 3.3, 5.1, 5.1a and 5.2–5.4 with the constants in 3.1 and 5.3.
- [ ] Every test named in §6 exists and passes (`busted` output in the PR).
- [ ] `luacheck .` clean; `scripts/check-apis.sh` and `scripts/check-libs.sh` pass; CI
      green on the PR.
- [ ] No WoW global, `LibStub` or library call in either module.
- [ ] Digest vectors match 3.3 exactly.
- [ ] The reviewer did a security-level review of `SyncProtocol` and states that it tried
      malicious input of its own beyond the listed tests.

## 8. Contract for the Sync slice

Not built here; the `Sync` spec/ticket must honor it.

- **Receive:** register prefix `InnLedger`; handle `CHAT_MSG_ADDON` directly (never
  AceComm); ignore other prefixes; accept only PARTY / RAID / GUILD. Whether Forever
  uses `INSTANCE_CHAT` for some groups is a question for #12.
- **Hidden values:** if `issecretvalue` exists and is true for the message, channel or
  sender, drop before calling `SyncProtocol` (quietly).
- **Sender resolution:** per [architecture.md → Security
  model](../architecture.md#security-model--the-riskiest-part-of-the-addon); unresolved
  → drop. Pass `{ guid, name }` to `SyncProtocol.receive`.
- **Send:** only through ChatThrottleLib at `"BULK"` priority, only our own share window,
  only HELLO, WANT and replies to WANTs addressed to us, within the **send budget** of
  5.3's traffic model (≤ 30 messages and ≤ 60 entries in any 60 s across all channels,
  counted over a sliding window; anything over waits for the next slot):
  - **HELLO:** at most 1 per channel per 60 s. After joining a group or a roster
    change, wait a random 5–15 s (further changes in that time don't add HELLOs); for
    guild, a jittered interval the `Sync` spec sets.
  - **WANT:** on a HELLO, wait a random 1–5 s, then call `decideWant` with that HELLO's
    channel (so a WANT seen meanwhile on that channel suppresses ours) and send only if
    it returns a `since`. At most one pending timer per peer: a newer HELLO from the same
    peer replaces the pending one's `count`/`digest` rather than adding a timer. At most
    12 WANTs per 60 s; the rest wait.
  - **Replies:** coalesce WANTs for us that arrive within 5 s into one reply per channel,
    using the smallest `since`; at most one reply per channel per 30 s; at most one
    **full** (`since = 0`) reply per channel per 5 minutes unless our share window
    changed since the last one. A full reply asked for inside that 5 minutes is
    **deferred, not dropped**: at most one pending full reply per channel, sent when the
    gate opens (so a newcomer who joins just after a full reply still gets it, and a
    hostile asker can only delay it).
- **Combat hold** ([decisions.md](../decisions.md) → 2026-09-27 — Sync may read combat
  state): while `InCombatLockdown()` is true (or after `PLAYER_REGEN_DISABLED`), send
  nothing and queue instead. The queue is bounded by coalescing: at most one pending
  HELLO per channel, one pending reply per channel (smallest `since`), one pending WANT
  per target. **Resume** on `PLAYER_REGEN_ENABLED`: wait 3 s, check `InCombatLockdown()`
  again (if back in combat, keep waiting for the next `PLAYER_REGEN_ENABLED`), then
  flush HELLO, replies, WANTs in that order, still within the send budget. Receiving and
  validating continue during combat. The `forbidden-apis` allow-list for `Sync.lua`
  gains the three combat-state names (`InCombatLockdown`, `PLAYER_REGEN_DISABLED`,
  `PLAYER_REGEN_ENABLED`) in that PR, citing that decision entry.
- **Read-only ledger:** `Sync` neither sends nor receives.
- **State:** the rate limiter and the WANT memo live for the session only.

**Weekly reset source** (for `Core` when it calls `Ledger.new`; also binds `Sign`):
- `weekAnchor` = `GetServerTime() + C_DateAndTime.GetSecondsUntilWeeklyReset()`,
  rounded to the nearest 60 s (the two calls can straddle a second). The client knows its
  own region's reset, so nothing about regions is hard-coded.
- If that API is missing or returns a non-number or hidden value, fall back to a small
  table of known reset times keyed by `GetCurrentRegion()`, filled from #12. If the
  region is unknown too, use the US reset (Tuesday 15:00 UTC). A wrong anchor only
  shifts when the week turns over; it can't corrupt data.
- Recompute the anchor at each login. Blizzard can move the reset; normalize re-applies
  the weekly rule to foreign entries and never drops own ones.

## Assumptions (listed for the maintainer)

- The 255-byte message limit, the `Player-<digits>-<hex>` GUID form and the
  `Creature-…-<npcId>-<spawn>` form hold on Forever as on retail. If #12 finds
  otherwise, the constants and patterns change and the protocol version bumps if the wire
  changes.
- Phrases need at most 5 IDs, each ≤ 9999; seals ≤ 999. The `Phrase` slice must fit in
  these or bump the protocol version.
- Entries accepted from beta dates (from 2026-09-17) are harmless on live servers.
- ~400 KB of SavedVariables at the foreign cap is acceptable.
