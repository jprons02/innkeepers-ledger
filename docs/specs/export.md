# Spec: `Export` and export format v1

> **Summary:** how a player takes their ledger out of the game. The v1 data table (every
> field's Lua type, range, meaning and source), the encoding pipeline (AceSerializer →
> raw DEFLATE → standard base64 → `!IL1!`), the pure `Export` API with injected
> serializer and compressor, the `Core:ExportString` glue the Share window will call,
> the privacy boundary (`travelers` only when opted in), the limits and size budget, a
> test-only decoder, a guard that keeps decoders out of shipped code, and the tests.
> **Read when:** implementing or reviewing `Export.lua` or `Core:ExportString`; changing
> anything that ends up in an export; building the Share window or `/ledger share`;
> writing an export consumer.

**Status:** approved (self-approved 2026-09-28, ticket #64). No maintainer decision blocks
it; two non-blocking questions are under [Open questions](#open-questions-maintainer).
**Security-sensitive:** moderately. No peer bytes are parsed here and nothing is imported,
but this slice draws the **privacy boundary** (other players' GUIDs and names leave the
game only when the player opts in), makes the serializer and compressor reachable from
glue, and adds a forbidden-API rule that keeps every general-purpose decoder out of
shipped code. The reviewer applies security-level scrutiny to [§5](#5-security-notes)
and must try hostile input of its own.

Builds on: [export-format.md](../export-format.md) (draft v0, finalized here);
[collection-cosmetics.md §3.3, §3.6, §4, §8](collection-cosmetics.md#8-contract-for-later-slices)
(`collection` = `Collection.progress` minus `inns`, `unknown`, `truncated`; `cosmetics` =
`Cosmetics.unlocked`); [sync-ledger.md §3.1, §4.4, §4.5](sync-ledger.md#45-ledger-api)
(`Ledger.LIMITS`, `Ledger.CAPS`, `ledger:own()`, `travelers()`, `signerEntries()`,
`earned()`, `ownerGUID()`); [sync-glue.md §3.2](sync-glue.md) (`Core` opens the ledger,
`version()`, `ownerName()`, the hidden-value checks). **Changes none of them:** no wire
format, `Ledger`, `Collection`, `Cosmetics` or `Sync` behavior changes here.

Binding decisions: [archive/decisions-2026-09.md](../archive/decisions-2026-09.md) →
*Generic, documented export string*; [decisions.md](../decisions.md) → *Export uses
standard base64*, *Profile site trust: showcase only, no profile key in the v1 export*,
*Profile website: after v1, a separate project, reached by one paste*, *Vendor a
reviewed, minimal set of libraries*, *Sync: own receive handler and codec, single
messages, no compression* (nothing decompresses or deserializes peer data). This spec
adds one 2026-09-28 entry (the implementer writes it when the PR lands): *Export v1:
what the draft left open* ([§3.9](#39-rejected-alternatives) lists the rejected options).

---

## 1. Problem

The post-v1 profile site, and any player who wants to render, share or back up their
ledger, needs a stable way to get it out of the game. The only bridge the AddOn may
offer is a neutral, documented string the player copies from an edit box
(*Generic, documented export string*). `Export.lua` is a stub and
[export-format.md](../export-format.md) is a draft: field types, ranges, orders, the
traveler shape and the size of a big ledger's string are not pinned, and once a string is
out in the world its meaning can't change. This slice pins the v1 format, builds the pure
encoder over the player's own ledger, collection and cosmetics (plus other travelers'
signatures only when the player opts in), proves round-trips through the real vendored
libraries, and gives the future Share window one glue call.

## 2. Scope

**In:**
- `Export.lua` (pure): `build`, `encode`, `string`, `base64` and the constants of
  [§3.6](#36-api).
- `Core.lua` (glue): `Core:ExportString(includeTravelers)` ([§3.7](#37-glue-coreexportstring)).
  No slash command, no frame.
- `spec/export_spec.lua` and two helpers: `spec/helpers/export_libs.lua` (loads the real
  vendored LibStub, AceSerializer-3.0 and LibDeflate into a private environment) and
  `spec/helpers/export_decode.lua` (the test-only reference decoder and a v1 schema
  checker). New cases in `spec/core_spec.lua` for the glue.
- `scripts/check-apis.sh`: a new rule, *general-purpose decoders*, allowed nowhere in
  shipped code ([§5](#5-security-notes)).
- `.luacheckrc`: `UnitFactionGroup` joins the glue list (Core reads it first; the
  collection spec had assigned that to `Sign`).
- Docs in [§4.4](#44-docs-the-implementer-updates), with `export-format.md` marked **v1**.

**Out:**
- The Share window, `/ledger share`, the travelers opt-in control and the "changed
  since you last shared" nudge (`UI/Book`, Phase 2). [§8](#8-contract-for-later-slices)
  fixes what they must do.
- **Any import or decoder in shipped code** (restoring a backup, reading someone else's
  string). It would be untrusted input with a decompression-bomb risk
  ([libraries.md → Findings](../libraries.md#findings-that-shape-our-design) 2 and 3) and
  v1 has no use for it. A future import is a new feature with its own spec and the
  maintainer's scope call.
- Publishing `Data/Inns`, `Data/Phrases`, `Data/Cosmetics` as a generated reference
  (a follow-up in [status.md](../status.md); needs #12's inn data).
- "Witnessed" stamp fingerprints (*Profile site trust*): a later additive field.
- Anything on the consumer side. The AddOn and this repo's shipped code never name a
  consumer.
- Recording unlocks with `markEarned` (the `Sign` / `Core`-at-login work of
  [collection-cosmetics.md §8](collection-cosmetics.md#8-contract-for-later-slices)).

## 3. Approach

### 3.1 Pipeline

```
input (plain Lua values from glue)
  → Export.build(input)                 -- validated, fresh data table (§4.1), or nil, reason
  → codec.serialize(data)               -- AceSerializer-3.0 Serialize: "^1" … "^^"
  → codec.compress(serialized)          -- LibDeflate CompressDeflate: raw DEFLATE (RFC 1951)
  → Export.base64(compressed)           -- ours: RFC 4648 §4, A–Z a–z 0–9 + /, "=" padding
  → "!IL1!" .. payload
```

- **`Export` never calls `LibStub`** (it loads in the strict pure environment). The glue
  passes `codec = { serialize = fn, compress = fn }` ([§3.7](#37-glue-coreexportstring)).
- **No line breaks** anywhere in the string. The full string matches
  `^!IL1![A-Za-z0-9+/]*=?=?$` and the payload length is a multiple of 4. No `|`, so an
  edit box shows it as is.
- **Compression settings:** LibDeflate's defaults (`configs = nil`), which pick the level
  from the input length (7 under 2 KB, 5 up to 64 KB, 3 above). Consumers inflate raw
  DEFLATE at any level; the level is not part of the format.

### 3.2 What AceSerializer does with our data (read from the vendored r1403 copy)

- **Output:** `"^1"`, one serialized value, `"^^"`. Tables are `^T` key value key value …
  `^t`; strings `^S` + text with escapes; numbers `^N` + `tostring(n)`.
- **Numbers are integers only in v1.** Lua 5.1's `tostring` uses `%.14g`, so every
  integer below 10^14 prints as plain decimal digits and `tonumber` reads it back
  exactly; our largest value is `tMax` = 9 999 999 999. So a v1 export never contains
  `^F…^f` (floats), `^B`/`^b` (booleans) or `^Z` (nil). A test checks the serialized text
  for them ([§6.3](#63-encode-and-round-trip-real-libraries)).
- **String escapes** (for consumers): a byte `n` ≤ 32 other than 30 → `~` then
  `char(n + 64)` (so a space is `` ~` ``); 30 → `~z`; `^` → `~}`; `~` → `~|`; 127 → `~{`.
  Bytes 128–255 (UTF-8 names) pass through unchanged. `Deserialize` first strips every
  control byte and space from its input, which is why these are escaped.
- **Keys come from `pairs`.** Every key is written explicitly (arrays as `^N1`, `^N2`, …),
  in `pairs` order: not specified, even for arrays. Consumers index by key and never
  depend on order in the serialized text; the orders §4.1 pins are the **array indexes**.
- **Nil can't be a table value**, so an optional field is **absent**, never `nil`-valued.
- **Shared tables are written twice and cycles recurse forever**, so `build` returns a
  fresh tree with no table appearing twice ([§3.5](#35-build-rules)).
- **Determinism.** On one interpreter (PUC Lua 5.1, used by busted locally and in CI)
  the same input gives the same bytes: string and number hashing are unseeded and
  `build` constructs tables in a fixed order. WoW's client Lua may order keys
  differently, so **byte equality is not part of the format**. Two exports of the same
  ledger may differ byte-wise and still decode to equal tables. The golden tests
  ([§6.3](#63-encode-and-round-trip-real-libraries)) pin the decoded table as the
  contract and the bytes only as a change detector.
- **Shared-library replacement** ([libraries.md](../libraries.md) Finding 4): at runtime
  a newer AceSerializer-3.0 or LibDeflate from another AddOn may be the one the glue
  gets. Serializer revision `^1` and raw DEFLATE are stable across those versions;
  `encode` still checks every return value and catches errors ([§3.6](#36-api)).

### 3.3 Base64 (ours)

RFC 4648 §4, standard alphabet `A–Z a–z 0–9 + /`, `=` padding to a multiple of 4
characters, no line breaks, pure Lua 5.1 arithmetic (no `bit` library): each 3-byte
group `n = a*65536 + b*256 + c` gives the characters `floor(n/262144)`,
`floor(n/4096) % 64`, `floor(n/64) % 64`, `n % 64`; a final 1- or 2-byte group is padded
with zero bits and `==` or `=`. Output is built in a table and joined once with
`table.concat` (no repeated string concatenation). `Export.base64("")` is `""`.

**No decoder ships.** The base64 decoder, inflate and deserialize steps live in
`spec/helpers/export_decode.lua` ([§3.8](#38-the-test-only-decoder)).

### 3.4 Travelers are opt-in, and grouped

- **Opt-in means an argument.** `build` includes `travelers` only when `input.travelers`
  is a table; the glue passes one only when `includeTravelers` is **exactly `true`**
  (`rawequal`), so `"yes"`, `1` or a table don't opt in. Nothing is remembered between
  exports ("opt-in per export", [export-format.md → Privacy](../export-format.md#privacy)).
- **Grouped per traveler, like the store**, not the draft's flat list:
  `{ guid, name, met, entries = { entry, … } }`. The flat shape repeated a GUID and a name
  on up to 40 entries per traveler; the grouped one mirrors `ledger:travelers()` +
  `ledger:signerEntries()` and gives consumers one entry parser for own and traveler
  entries.
- **Traveler entries carry `seal`** when they have one: it is part of that traveler's
  signature (peers validate it against `Cosmetics.SEALS` before it's stored).
- **`met`** (the server time we first accepted one of their entries) is included: it is
  the crossing-paths moment the book shows. `name` is the latest resolved name.
- Opted in with no travelers gives `travelers = {}` (present and empty), so a consumer can
  tell "opted in, met nobody" from "not opted in" (absent).

### 3.5 `build` rules

`Export.build(input)` returns a **new** data table in the §4.1 shape, or `nil, reason`.
It never throws on any argument, never writes to an argument, runs no metamethod of an
argument (arrays read with `rawget(t, i)` for `i = 1, 2, …` until the first `nil`; maps
with raw `next`; never `pairs`, `ipairs` or `#` on caller tables), never recurses into a
caller table beyond the fixed depth of §4.1, and copies only the listed keys, so nothing
else (`inns`, `unknown`, `truncated`, an extra field) can leak into the output.

One uniform rule:
- **A required top-level value that fails its check → `nil, reason`** (a caller bug; the
  glue passes values that always pass): `input` not a table → `"input"`; `flavor` not a
  key of `FLAVORS` → `"flavor"`; `exported` not an integer in `tMin`..`tMax` →
  `"exported"`; `addon` not 1..32 bytes of `A-Z a-z 0-9 . _ + -` (explicit byte ranges,
  never `%w`) → `"addon"`; `me` not a table or `me.guid` failing `Ledger.validGUID` →
  `"me"`; `progress` not a table, or its `signed`/`total` not integers in
  0..`innMax` with `signed <= total`, or `faction`/`done` present and invalid →
  `"collection"`; `own` not a table → `"entries"`; `unlocked` not a table →
  `"cosmetics"`; `travelers` present and not a table → `"travelers"`.
- **An array item or map item that fails its check is left out**, and the rest is kept.
  "Integer" everywhere means `type(x) == "number" and x == x and x % 1 == 0` plus the
  range, so `NaN`, `±inf` and fractions fail. Items:
  - `me.name`: kept if it passes `Ledger.validName`, else absent.
  - own entry: kept if it passes `Ledger.validEntry` (copied as a new table, `seal` only
    if non-`nil`); a later item with the same `(inn, t)` as a kept one is left out.
  - cosmetic: kept if `id` is an integer in 1..`cosmeticIdMax` and `t` in
    `tMin`..`tMax`; for a repeated `id` only the smallest `(t, id)` is kept.
  - `byContinent[k]` / `byZone[k]`: kept if `k` is an integer in 1..`mapKeyMax`, the
    value is a table with `signed`/`total` integers in 0..`innMax`, `signed <= total`,
    `done` absent or a time, and (zones only) `continent` an integer in 1..`mapKeyMax`.
  - traveler: kept if `guid` passes `validGUID` and isn't `me.guid`, `name` passes
    `validName`, `met` is a time, and at least one entry is kept (entries as for own
    entries, per traveler); a later traveler with a GUID already kept is left out.
- **Limits → `nil, "too_large"`** (read one item past the limit to detect it; never a
  partial export): more than `LIMITS.ownMax` own items; more than `LIMITS.cosmeticsMax`
  cosmetic items; more than `LIMITS.mapItemsMax` items in `byContinent` or in `byZone`;
  more than `Ledger.CAPS.foreignTotal` traveler records or traveler entries in all; more
  than `Ledger.CAPS.perSigner` entries in one traveler record. Counts are of items read,
  valid or not, so the work is bounded whatever the items hold.
- **Orders are `build`'s, not the caller's:** own and traveler entries `(t, inn)`
  ascending; cosmetics `(t, id)` ascending; travelers `met` descending, then `guid` in
  **byte order** (compared byte by byte, as `Ledger` does, never with Lua's string `<`).
  Deduplication keeps the first occurrence in input order, then the sort runs. So a
  shuffled input gives a deep-equal output.

### 3.6 API

All functions are pure and **never throw** on any argument. `Export.lua` asserts
`ns.Ledger` and `ns.Collection` when it loads (both precede it in the TOC) and reads
their limits instead of repeating literals.

| Name | Value / returns |
|---|---|
| `Export.VERSION` | `1` (the format major: the envelope digit and `data.v`) |
| `Export.PREFIX` | `"!IL1!"` (built from `VERSION`) |
| `Export.FLAVORS` | `{ forever = true }` (a copy; v1's only flavor) |
| `Export.LIMITS` | `{ ownMax = 10000, cosmeticsMax = 1200, mapItemsMax = 1000, addonBytes = 32, serializedMax = 4194304 }` (a copy). Traveler limits are `Ledger.CAPS.foreignTotal` (3 000) and `Ledger.CAPS.perSigner` (40); map keys use `Collection.LIMITS.mapKeyMax`; IDs and times use `Ledger.LIMITS` |
| `Export.build(input)` | data table (§4.1) or `nil, reason` (§3.5) |
| `Export.encode(data, codec)` | the export string, or `nil, reason`: `"data"` (not a table), `"codec"` (not a table, or `serialize`/`compress` not functions), `"serialize"` (the call raised, or returned anything but a non-empty string), `"too_large"` (the serialized string is over `serializedMax`; `compress` is then never called), `"compress"` (raised, or not a non-empty string). Each codec call runs in `pcall`; only its first return is used |
| `Export.string(input, codec)` | `encode(build(input), codec)`; `build`'s `nil, reason` passes through and the codec is never called |
| `Export.base64(s)` | standard base64 of a string (§3.3); `nil` for a non-string |

**`input`**, all plain values the glue gathers:

```lua
{
  flavor    = "forever",
  exported  = <server time>,
  addon     = "<version>",
  me        = { guid = <string>, name = <string or nil> },
  own       = <array of entries>,          -- ledger:own()
  progress  = <Collection.progress result>,
  unlocked  = <Cosmetics.unlocked result>,
  travelers = nil | <array of { guid, name, met, entries = <array of entries> }>,
}
```

**Why these limits.** `ownMax` 10 000: an honest ledger holds at most one entry per inn
per week, and 10 000 means signing about 14 inns every day for two years. `cosmeticsMax`
1 200 covers every ID `Cosmetics` can produce (99 milestone seals + 899 zone seals + 200
quills and inks). `mapItemsMax` 1 000 is above the 899 zones that can carry a seal.
`serializedMax` 4 MiB is a backstop above the largest string `build` can produce
(≈ 2.2 MB, [§3.10](#310-size-budget)), so it never refuses a `build` result; it stops a
caller that hands `encode` some other huge table, and it is the bound consumers may
enforce on inflate ([§4.2](#42-export-formatmd-becomes-v1)).

### 3.7 Glue: `Core:ExportString`

`Core:ExportString(includeTravelers)` → the export string, or `nil, reason`. The Share
window and `/ledger share` (later) call only this. It runs its body in `pcall` (→ `nil,
"error"`), prints nothing, sends nothing, and writes nothing:

1. `ledger = ns.ledger`; none → `nil, "no_ledger"`. A **read-only** ledger exports too
   (a damaged or newer-schema ledger is exactly when a backup copy helps).
2. `AceSerializer = LibStub("AceSerializer-3.0", true)`, `LibDeflate =
   LibStub("LibDeflate", true)`; either missing → `nil, "libs"`. `codec = { serialize =
   function(v) return AceSerializer:Serialize(v) end, compress = function(s) return
   (LibDeflate:CompressDeflate(s)) end }`.
3. `faction` = the first return of `UnitFactionGroup("player")` through Core's `call`,
   then `hidden()` → `nil`, and anything but a string → `nil` (the collection spec's
   rule; `Collection` narrows it to `"Alliance"`/`"Horde"`).
4. `now` = `call(GetServerTime)`; a hidden value → `nil` (then `build` returns
   `"exported"`).
5. `own = ledger:own()`; `progress = ns.Collection.progress(own, faction)`;
   `unlocked = ns.Cosmetics.unlocked(own, faction, ledger:earned())`.
6. `travelers`: only if `rawequal(includeTravelers, true)`: for each `t` of
   `ledger:travelers()`, `{ guid = t.guid, name = t.name, met = t.met, entries =
   ledger:signerEntries(t.guid) }`.
7. `return ns.Export.string({ flavor = "forever", exported = now, addon = version(), me
   = { guid = ledger:ownerGUID(), name = ownerName() }, own = own, progress = progress,
   unlocked = unlocked, travelers = travelers }, codec)`.

`flavor` is a literal in `Core` because the TOC targets only Forever in v1; if a build
ever targets several flavors, #12's notes say how to detect it and the literal becomes a
lookup. `me.name` is the client's current name (Core's `ownerName()`, hidden-checked);
`me.guid` is the GUID the ledger was opened for.

### 3.8 The test-only decoder

`spec/helpers/export_decode.lua` (never shipped; the packager drops `spec/`):
- `unbase64(s)`: strict RFC 4648: length a multiple of 4; only the alphabet, then at
  most two `=` at the end; zero pad bits (so `Zh==` is rejected, `Zg==` isn't); else
  `nil`. Written independently of `Export.base64` (its own table and arithmetic).
- `decode(str, libs)`: `#str` over 6 000 000 → `nil, "too_large"`; `^!IL(%d+)!` →
  major; not `1` → `nil, "version"`; `unbase64` fails → `nil, "base64"`;
  `libs.deflate:DecompressDeflate` → `nil` or trailing bytes → `nil, "inflate"`;
  inflated over `serializedMax` → `nil, "too_large"`; `libs.serializer:Deserialize` must
  return `true` and exactly one table → else `nil, "deserialize"`; `data.v ~= 1` →
  `nil, "version"`. Returns the data table.
- `schemaOk(data)`: `true` exactly when `data` matches §4.1 (every required field, every
  type and range, orders, uniqueness, no key outside §4.1). Every test runs it on every
  `build` result and every decoded export.

`spec/helpers/export_libs.lua` loads `Libs/LibStub/LibStub.lua`,
`Libs/AceSerializer-3.0/AceSerializer-3.0.lua` and `Libs/LibDeflate/LibDeflate.lua` with
`load.file` into a **private environment** (`env._G = env`, `__index` to the real
globals for the standard libraries), so no `LibStub` global leaks (`spec/smoke_spec.lua`
asserts there is none). It returns `{ serializer, deflate, codec }`, where `codec` is
built exactly as in §3.7 step 2.

### 3.9 Rejected alternatives

- **Shipping a decoder or an import:** peer or pasted strings would be untrusted input;
  LibDeflate has no output limit (722:1 shown) and AceSerializer yields `NaN`, `inf` and
  floats. v1 needs no import, and the new guard keeps it that way.
- **The draft's flat `travelers` list:** repeats GUID and name per entry; the grouped
  shape mirrors the store (3.4).
- **Truncating an export over the limits:** a string silently missing stamps is worse
  than a clear refusal at limits no honest ledger reaches.
- **Our own deterministic serializer (sorted keys) or JSON:** AceSerializer was chosen
  and reviewed for export, and byte equality isn't a consumer need.
- **`Export` calling `Collection`/`Cosmetics`/the ledger itself:** plain inputs keep it a
  small, fully testable shaper; the glue owns the calls.
- **LibDeflate `EncodeForPrint`, zlib wrapper:** already decided (standard base64, raw
  DEFLATE).
- **Line-wrapped base64 (MIME, 76 columns):** newlines get mangled by edit boxes and
  pastes.
- **Comparing export strings for the "changed since you last shared" nudge:** bytes
  aren't stable across clients (3.2); the nudge compares data ([§8](#8-contract-for-later-slices)).
- **Remembering the travelers opt-in:** the format says per export.
- **A fixed compression level (9):** very slow in pure Lua for no format gain.

### 3.10 Size budget

Estimates from the serialized form (bytes per item from §3.2's encoding; DEFLATE on this
text, whose structure repeats but whose times, GUIDs, names and IDs don't, at roughly 3–5×;
base64 adds a third). The implementer **measures** each row in `spec/export_spec.lua`,
fills the *Measured* column here and in export-format.md, and sets each test ceiling at
the measured string length × 1.25 rounded up to a multiple of 16 KiB, **never above the
hard ceiling**. A measurement above a hard ceiling is a design problem: stop and report
it rather than raising the ceiling.

Fixture **L** ([§6](#6-test-plan)): 300 own entries (5 phrase IDs each, every other one
sealed), `progress` with 150 zones on 5 continents, 160 cosmetics.

| Case | Serialized (est.) | String (est.) | Hard ceiling | Measured |
|---|---|---|---|---|
| Empty ledger (no entries, empty data) | ~200 B | ~200 chars | none | 217 chars (211 B serialized), < 0.01 s; test ceiling 16 KiB |
| L, default | ~50 KB | 12–20 KB | 32 KiB | 11 773 chars (41 448 B), 0.02 s; test ceiling 16 KiB |
| L + travelers, 75 × 40 entries (the caps) | ~450 KB | 100–170 KB | 512 KiB | 84 893 chars (272 420 B), 0.14 s; test ceiling 112 KiB |
| L + travelers, 3 000 × 1 entry (worst at the caps) | ~600 KB | 150–250 KB | 512 KiB | 164 749 chars (517 391 B), 0.22 s; test ceiling 208 KiB |
| Every `build` limit at once, longest fields | ≤ 2.2 MB | not encoded | `serializedMax` | 2 142 045 B serialized, 0.19 s build + serialize; test ceiling 2 624 KiB |

Measured 2026-09-28 (#64) under busted, PUC Lua 5.1, with the vendored libraries; times
are `os.clock` around `Export.string` on the implementer's machine, a first signal only.

- **Default exports are small** (a few KB for most players, ~15 KB for a heavy one).
  Opted-in exports near the foreign cap are the large case.
- **Client cost is unverified:** pure-Lua DEFLATE on ~600 KB may take a second or more
  in the client and freeze a frame, and a ~250 KB edit box text may be slow to set. Both
  go on #12's list ([§4.4](#44-docs-the-implementer-updates)); the Share window's design
  can react (a short "preparing" state, or computing on click only). The implementer
  records the busted encode time of each row in the PR as a first signal.

## 4. Data model changes

- **SavedVariables:** none. Nothing is stored; no schema bump, no migration.
- **Wire format:** unchanged.
- **`Ledger`, `Collection`, `Cosmetics`:** unchanged.

### 4.1 The v1 data table

"time" = integer Unix seconds (UTC, the server clock) in `tMin`..`tMax`
(1 789 603 200..9 999 999 999). "Optional" = the key may be absent; no key is ever
present with a `nil` value. No key outside this table appears in v1.

| Field | Lua type | Range / form | Meaning | Source (glue) |
|---|---|---|---|---|
| `v` | integer | `1` | format major; always equals the envelope's digit | `Export.VERSION` |
| `flavor` | string | `"forever"` (v1's only value) | the game flavor the ledger came from | literal in `Core` |
| `exported` | integer | time | when the string was made | `GetServerTime()` |
| `addon` | string | 1..32 bytes of `A-Z a-z 0-9 . _ + -`; `"dev"` unpackaged | the AddOn version that wrote it | Core's `version()` |
| `me` | table | `{ guid, name? }` | the character | |
| `me.guid` | string | `Player-<digits>-<hex>`, ≤ 40 bytes | identity | `ledger:ownerGUID()` |
| `me.name` | string, optional | `Ledger.validName` (2..96 bytes, letters, UTF-8, one space, optional `-Realm`) | display name at export | Core's `ownerName()` |
| `collection` | table | `{ faction?, signed, total, done?, byContinent, byZone }` | progress over **your own** signatures, inns open to your faction | `Collection.progress(own, faction)` minus `inns`, `unknown`, `truncated` |
| `collection.faction` | string, optional | `"Alliance"` / `"Horde"` | faction counted; absent: unreadable, every inn counted | `UnitFactionGroup("player")` |
| `collection.signed`, `.total` | integer | 0..9 999 999, `signed <= total` | open inns signed / all open inns | progress |
| `collection.done` | time, optional | present only when `signed == total >= 1` | when the last open inn was first signed | progress |
| `collection.byContinent` | table (map) | integer key 1..999 999 (the client's continent map ID: a Continent map, or the World map above a zone with no Continent, e.g. 947 Azeroth) → `{ signed, total, done? }`; `signed`/`total` ranges as `collection.signed`/`.total`; `done` a time, present only when `signed == total >= 1` | continents with at least one open inn | progress |
| `collection.byZone` | table (map) | integer key 1..999 999 (zone map ID) → `{ signed, total, continent, done? }`; `signed`/`total` ranges as `collection.signed`/`.total`; `done` a time, present only when `signed == total >= 1` | zones with at least one open inn; `continent` is a `byContinent` key | progress |
| `cosmetics` | array | `{ id = 1..9 999, t = time }`, `(t, id)` ascending, `id` unique | unlocked quills, inks and seals and when each was earned | `Cosmetics.unlocked(own, faction, ledger:earned())` |
| `entries` | array | entry (below), `(t, inn)` ascending, `(inn, t)` unique | your own signatures; each inn's first is its stamp | `ledger:own()` |
| `travelers` | array, optional | present only when opted in (may be empty); `met` descending, then `guid` byte order; `guid` unique, never `me.guid` | travelers whose signatures you hold | `ledger:travelers()` |
| `travelers[i]` | table | `{ guid, name, met = time, entries }`; `guid`/`name` as `me.guid`/`me.name` (`name` required); `entries` 1..40 entries, `(t, inn)` ascending, `(inn, t)` unique | one traveler and **their own** signatures | `ledger:signerEntries(guid)` |
| entry | table | `{ inn = 1..9 999 999, t = time, phrase = { 1..5 IDs, each 1..9 999 }, seal = 1..999 (optional) }` | one signature | |

- An entry's `inn` is an innkeeper NPC ID from `Data/Inns`, possibly an **alias** of the
  inn's primary record ([collection-cosmetics.md §3.1](collection-cosmetics.md#31-places-inns-zones-continents)).
  `phrase` IDs render with [phrase.md §3.4](phrase.md#34-rendering). `seal` and cosmetic
  IDs follow [collection-cosmetics.md §3.5](collection-cosmetics.md#35-cosmetic-ids).
- Every cosmetic time equals the `t` of one of your own entries (collection-cosmetics
  §3.6), so a consumer can check it.
- **Maps have integer keys** in the serialized form; a consumer converting to JSON turns
  them into strings.
- `collection`, `cosmetics` and `entries` are always present (possibly empty).

**Changes from draft v0** (each goes into the decision entry): `travelers` grouped per
traveler with `met` and entries that keep `seal`; `me.name` optional; `v` equals the
envelope major; every array order and uniqueness rule pinned; optional means absent;
integers only; `addon` charset; `flavor` values; the limits and `too_large`.

### 4.2 `export-format.md` becomes v1

Exactly these edits (the implementer makes them; keep the rest):
- **Header:** summary "the export string spec (envelope, payload, data fields, privacy
  and trust rules). **v1**, pinned 2026-09-28 (#64)." Replace the status paragraph with:
  "**Status: v1** (2026-09-28). From here on, fields are only added. A decoder ignores
  fields it doesn't know and rejects any other major version. A change that would alter
  a field's meaning or type bumps the major (`!IL2!`, `v = 2`)."
- **Envelope:** add: no line breaks; the full-string pattern and length rule of §3.1;
  raw DEFLATE, **not** zlib or gzip framing; the compression level is not part of the
  format; `v` inside must equal the envelope digit.
- **New subsection "Serialized form"**: §3.2's consumer-facing points (the `^1 … ^^`
  frame, `^T`/`^t`, `^S` with the escape table, `^N` decimal integers only, no `^F`,
  `^B`, `^b`, `^Z` in v1, keys in any order, arrays as explicit integer keys, whitespace
  and control bytes ignored by the reader).
- **"Data (draft)" → "Data (v1)"**: the §4.1 table and notes replace the draft block.
  (`status.md` links `export-format.md#data-draft`; update that link to the new heading.)
- **New subsection "Decoding"**: the steps of §3.8 as prose (prefix and major, base64,
  raw inflate, AceSerializer, `v`, then validate against Data), and the caps: "The AddOn
  never writes a serialized payload over 4 194 304 bytes, so a consumer may cap inflate
  output there and reject strings over 6 000 000 characters." Keep the Trust section
  pointing here.
- **New subsection "Size"**: the §3.10 table with the measured column.
- **Privacy:** add "Opting in is per export; nothing remembers it. Without it, no other
  player's GUID or name appears anywhere in the string."
- **Sharing in-game:** unchanged.

### 4.3 CLAUDE.md map

Add this spec's row after `collection-cosmetics.md` (done with this spec). The
implementer changes the `export-format.md` row's "(draft v0)" to "(v1)".

### 4.4 Docs the implementer updates

- [export-format.md](../export-format.md): §4.2.
- [architecture.md](../architecture.md) → Modules: the `Export` row links this spec;
  → Export: the pipeline in one line, `Core:ExportString(includeTravelers)` as the one
  glue entry, "no decoder or import ships; the forbidden-API check enforces it".
- [libraries.md](../libraries.md): AceSerializer and LibDeflate rows say `Serialize` and
  `CompressDeflate` are the only calls in shipped code; `Deserialize` and
  `DecompressDeflate` run only in tests. Link the new check rule under Findings 2 and 3.
- [security-checklist.md](../security-checklist.md) → The forbidden-API check: a bullet
  for *General-purpose decoders* (allowed nowhere); release item 10 adds "and `travelers`
  appears only when the player opts in".
- [testing.md](../testing.md) → Testing posture: the two helpers (real libraries in a
  private environment; the test-only decoder and `schemaOk`), and that the large size
  cases are tagged `#sim`.
- [platform-forever.md](../platform-forever.md) → Verification checklist (#12): "an edit
  box holds, shows and copies a ~250 KB string (and how long `SetText` takes)" and "how
  long an opted-in export of a ledger at the foreign cap takes to build".
- [decisions.md](../decisions.md): the 2026-09-28 entry *Export v1: what the draft left
  open* (the §4.1 change list, no shipped decoder plus its guard, the limits, per-export
  opt-in by `true` only) with the §3.9 rejections; and a line in it on the new
  forbidden-API rule (the script header asks for a decision entry on rule changes).
- [status.md](../status.md): rewrite (Export done; its size measurements; the anchor fix).
- `.luacheckrc`: `UnitFactionGroup` in the glue list.

## 5. Security notes

**Flag for the reviewer: security-level review of the privacy boundary, `build`'s
argument handling and the new forbidden-API rule.**

- **No peer bytes, no import.** Nothing here parses data from another player or from a
  paste. The only decoders (`Deserialize`, `DecompressDeflate`, base64 decode) run in
  `spec/`. **New rule in `scripts/check-apis.sh`:** `general purpose decoders|-|Deserialize
  DecompressDeflate DecompressDeflateWithDict DecompressZlib DecompressZlibWithDict
  DecodeForPrint DecodeForWoWAddonChannel DecodeForWoWChatChannel`, allowed in no shipped
  file (`Libs/` and `spec/` are outside the scan, as now). Today no shipped file names
  them. Shipped comments must not either: say "the test-only decoder".
- **Privacy boundary.** The default export holds no other player's GUID or name
  anywhere: `travelers` is the only field that can hold them, and it appears only when
  `input.travelers` is a table, which the glue passes only for `includeTravelers ==
  true` (`rawequal`). Every other string in the output is `me.guid`, `me.name`, `flavor`
  or `addon`. A test walks every key and value of the decoded default export for any
  traveler GUID or name ([§6.4](#64-privacy)).
- **Own-signature rule holds on the way out.** Traveler entries are exported under the
  GUID they are stored under (the resolved sender, sync-ledger §5.1 rule 17), never
  re-attributed, and the owner's GUID can't appear as a traveler (§3.5).
- **Tampered SavedVariables.** `Ledger` normalizes on load, and `build` re-checks every
  value against §4.1 anyway: no metamethods, bounded reads (limits of §3.6, read one past
  to detect), fixed depth, no recursion into caller tables, fresh output with no shared
  or cyclic tables, never throws, never writes an argument. A tampered file can at most
  make the player's own export refuse (`too_large`) or leave out bad items.
- **Output text is inert.** Every string in the output passed `validGUID`, `validName`,
  the `addon` charset or the `FLAVORS` set, so no `|` escape can reach an edit box and
  no URL (`:` and `/` are outside every allowed set). The base64 payload has no `|`.
- **Libraries.** Only `Serialize` and `CompressDeflate` run in the client, on our own
  data. A replaced shared copy is another installed AddOn (trusted under the threat
  model); `encode` still catches errors and checks types, and a codec failure is a quiet
  `nil, reason`.
- **Forgeable by design.** The player controls the string; nothing in the AddOn reads or
  trusts an export, and export-format.md → Trust tells consumers the same.
- **Policy.** No consumer, site or URL is named in `Export.lua`, `Core.lua` or the
  output (`no-urls-in-game-code`); nothing is paid or gated.
- **Forbidden-API guard.** `Export.lua` names no WoW API even in comments;
  `UnitFactionGroup` is not a forbidden name.

## 6. Test plan

busted; `Export.lua` loaded with `Ledger.lua` and `Collection.lua` into one fresh `ns` in
the strict pure environment; the real vendored libraries through
`spec/helpers/export_libs.lua`. Fixed times (`T = 1790000000`), never the clock. Coverage
floor 90% for `Export.lua` (already in `scripts/check-coverage.sh`). **`schemaOk` runs on
every non-`nil` `build` result and every decoded export in every test.**

**Fixture F** (default): `flavor "forever"`, `exported T+1000`, `addon "1.0.0"`, `me = {
guid = "Player-1234-0ABCDEF0", name = "Aldric" }`; `own` = e1 `{ inn 5001, t T, phrase
{101} }`, e2 `{ 5201, T+100, {3, 1201}, seal 1 }`, e3 `{ 5003, T+200, {101, 1201, 501,
3, 1202} }`; `progress = { faction "Alliance", signed 2, total 3, byContinent { [1] = { 2,
3 } }, byZone { [10] = { 1, 2, continent 1 }, [20] = { 1, 1, continent 1, done T+100 } },
inns = {…}, unknown 0, truncated false }`; `unlocked = { { 1101, T }, { 103, T+100 } }`.
**F+T** adds `travelers = { { guid "Player-1234-0BBBBBB0", name "Mira Ashvale", met
T+50, entries { { 5001, T+40, {4, 5}, seal 2 } } }, { guid "Player-1234-0CCCCCC0", name
"Zoë-Azjol-Nerub", met T+60, entries { { 5201, T+45, {7} } } } }`. **EXPECTED_F** and
**EXPECTED_F_T** are written out literally in the spec file (the §4.1 shape: no `inns`,
`unknown` or `truncated`; `seal` absent on e1 and e3; travelers ordered Zoë then Mira).

### 6.1 Base64

- RFC 4648 §10 vectors: `""`→`""`, `f`→`Zg==`, `fo`→`Zm8=`, `foo`→`Zm9v`, `foob`→`Zm9vYg==`,
  `fooba`→`Zm9vYmE=`, `foobar`→`Zm9vYmFy`.
- Alphabet edges: `"\0\0\0"`→`AAAA`, `"\255\255\255"`→`////`, `"\251\255"`→`+/8=`.
- All 256 byte values in one string, and seeded random strings of length 0..64, round-trip
  through the helper's `unbase64`; output length is `4 * ceil(n / 3)`; only the alphabet
  plus at most two trailing `=`.
- The helper's `unbase64` rejects: length not a multiple of 4; `-`, `_`, space, `\n`;
  `=` in the middle; three `=`; non-zero pad bits (`Zh==`, `Zm9=`).
- `Export.base64(nil)`, `(7)`, `({})`, a stand-in → `nil`, no throw.
- A 300 KB input round-trips (the join-once rule; also a speed signal).

### 6.2 `build`

- **F → EXPECTED_F exactly; F+T → EXPECTED_F_T exactly.** No `travelers` key in
  EXPECTED_F; `collection` has no `inns`, `unknown`, `truncated`.
- **Opt-in:** `travelers = nil` → absent; `{}` → present and empty; `"yes"`, `1`, `true`
  → `nil, "travelers"`.
- **Orders:** F+T with `own`, `unlocked`, `travelers` and each traveler's entries
  reversed and seeded-shuffled → deep-equal output. Travelers with equal `met` order by
  GUID bytes (`Player-1-0A` before `Player-1-0a`: `A` is byte 65).
- **Dedupe:** own `(inn, t)` repeated with a different phrase → first kept; cosmetic `id`
  repeated → the one with the smaller `t` kept; a traveler GUID repeated → first kept;
  a traveler's entries deduped the same way.
- **Required fields, one case each →** the named reason: `input` of `nil`, `"x"`, a
  stand-in; `flavor` `"Forever"`, `"retail"`, `nil`; `exported` `tMin - 1`, `tMax + 1`,
  `NaN`, `1.5`, `"1790000000"`; `addon` `""`, 33 bytes, `"1.0 beta"`, `"v1|r"`,
  `"a/b"`, `"x:y"`, a UTF-8 byte; `me` `nil`, `{}`, `guid` `"player-1-AB"`, a 41-byte
  GUID; `progress` `nil`, `signed` over `total`, `total` `NaN`, `faction` `"Neutral"`,
  `done` `1.5`; `own` `nil`, `7`; `unlocked` `nil`, `"x"`.
- **Items left out, one case each:** `me.name` with `|` or 97 bytes → no `name` key; own
  entries failing `validEntry` (each: `inn` 0, `t` `NaN`, `phrase` with 6 IDs or a hole,
  `seal` 0 or 1000, an extra key, a non-table); cosmetics with `id` 0, 10000, `1.5`, `t`
  `tMin - 1`, a non-table; map items with key `0`, `1000000`, `"10"`, `1.5`, with
  `signed` over `total`, a zone without `continent`, a non-table; travelers with a bad
  GUID, `me.guid` as GUID, a bad name, `met` `NaN`, no valid entries. Their siblings are
  kept.
- **Limits → `nil, "too_large"`:** 10 001 own items (10 000 pass); 1 201 cosmetics;
  1 001 zones; 1 001 continents; 3 001 traveler records; 3 001 traveler entries in all
  (e.g. 76 × 40 + 1); 41 entries in one record. Items past a hole don't count (a hole
  stops the read).
- **Purity and safety:** inputs deep-compare equal before and after; no table in the
  output is `rawequal` to an input table; no table appears twice in the output;
  `__index`, `__newindex`, `__len` and `__call` metamethods on every input table raise
  and never fire; the two hidden-value stand-ins in every field position → a reason or a
  left-out item, never a throw; a cycle (`progress.byZone[10] = progress`) → that item
  left out, no recursion.

### 6.3 Encode and round trip (real libraries)

- **F and F+T** → `Export.string` → matches `^!IL1![A-Za-z0-9+/]*=?=?$`, payload length a
  multiple of 4, no `\r`, `\n`, space or `|` → the helper's `decode` → deep-equal
  EXPECTED_F / EXPECTED_F_T, `v == 1`.
- **Names survive:** a space (`Mira Ashvale`, escaped `` ~` ``), UTF-8 (`Zoë`), a realm
  suffix and `'` in a realm round-trip byte for byte.
- **Integers only:** the serialized text of F+T (captured through a spy serializer that
  calls the real one) contains no `^F`, `^B`, `^b`, `^Z`.
- **Golden:** a checked-in string `GOLDEN_F`, generated once by the implementer from F
  under Lua 5.1 with the vendored libraries: (1) `decode(GOLDEN_F)` deep-equals
  EXPECTED_F (the contract; it must hold for all of v1); (2) `Export.string(F)` equals
  `GOLDEN_F` byte for byte (a change detector; if it breaks after a library or
  interpreter change while (1) holds, regenerate it and say so in the PR); (3) encoding F
  twice in one run gives equal strings.
- **Empty ledger:** no own entries, empty progress maps, no cosmetics → a valid string
  that decodes to empty arrays and maps.
- **Codec failures →** `nil, reason`: `codec` `nil`, `{}`, `serialize` not a function →
  `"codec"`; `serialize` raises, returns `nil`, `7`, `""` → `"serialize"`; returns
  `serializedMax + 1` bytes → `"too_large"` and `compress` never called (spy); `compress`
  raises, returns `nil`, `""`, `{}` → `"compress"`; `Export.string` with a failing
  `build` never calls the codec; `encode("x", codec)` → `"data"`.

### 6.4 Privacy

- **Default export of a ledger that holds travelers:** build a `Ledger.new` fixture with
  own entries and two travelers (`addForeign`), run the §3.7 steps in the test
  (`includeTravelers` nil) through `Export.string` with the real libraries, decode, and
  walk **every key and value** recursively: no string equals either traveler's GUID or
  name, the only string matching `^Player%-` is `me.guid`, and there is no `travelers`
  key. The same with `includeTravelers = true` finds both.
- No string anywhere in any decoded fixture contains `://` or `www.`.

### 6.5 Size budget

- Fixture **L** and the §3.10 rows, each asserting the string length ≤ its ceiling and
  printing the measured length and encode time (for the PR). The traveler rows and the
  limits row are tagged `#sim` (run by `busted`, skipped by the coverage run).
- **Limits row:** `build` at every limit at once (10 000 own entries with 5 phrase IDs
  and seals, 3 000 travelers × 1 entry with 40-byte GUIDs and 96-byte names, 1 000 zones,
  1 000 continents, 1 200 cosmetics) succeeds, and its **serialized** length (real
  AceSerializer, no compression) is ≤ `serializedMax`.

### 6.6 Hostile and tampered input

- **Seeded fuzz, 1 000 iterations** (`#sim` if slow): mutate F+T by replacing one random
  field at any depth with one of `nil`, `NaN`, `1/0`, `-1/0`, `1.5`, `0`, `-1`, `2^53`,
  `""`, a 200-byte string, `"|cff"`, `{}`, a stand-in, a table with raising
  metamethods, a 50-deep nested table. Each result is a known reason or passes
  `schemaOk`; nothing throws; the input is unchanged.
- **Tampered SavedVariables end to end:** `Ledger.new` over a saved table with invalid
  own entries (quarantined), bad traveler records, junk `earned` and a bad `me.name`;
  the §3.7 steps → a valid string; quarantined entries don't appear.
- **With the real `Collection` and `Cosmetics`** (fixture places and catalog from
  `spec/helpers/places.lua`): `collection` deep-equals `progress` minus `inns`,
  `unknown`, `truncated`, and `cosmetics` deep-equals `unlocked`, for Alliance, Horde and
  `nil` faction.

### 6.7 Glue (`spec/core_spec.lua`, whole AddOn under the stub)

- After login, with two own entries (`addOwn`) and one traveler (`addForeign`):
  `ns.Core:ExportString()` → a string; decoded with the libraries **from the loaded
  AddOn's `LibStub`** → `me.guid == "Player-1-00000001"`, `me.name == "Traveler"`,
  `flavor == "forever"`, `addon == "dev"` (and `"1.2.3"` with `wow.metadata.Version`),
  `exported == wow.now`, `entries` = `ledger:own()`, `collection.faction == "Alliance"`,
  no `travelers`.
- `ExportString(true)` includes the traveler; `ExportString("yes")`, `(1)`, `({})` don't.
- `UnitFactionGroup` raising, returning a hidden stand-in (`issecretvalue` → true), or a
  number → no `faction`; a hidden clock → `nil, "exported"`.
- A read-only ledger (newer schema) still exports its entries.
- No ledger (GUID never readable) → `nil, "no_ledger"`; AceSerializer or LibDeflate
  removed from `LibStub.libs` → `nil, "libs"`; `ns.Collection.progress` replaced by a
  function that raises → `nil, "error"`.
- Nothing printed (`wow.chat` unchanged), nothing sent, no error caught by the libraries,
  the saved ledger deep-equal before and after.

### 6.8 Guards

- `sh scripts/check-apis.sh` passes; the PR shows it failing on a scratch shipped file
  that calls `Deserialize` (then removed).
- `spec/smoke_spec.lua` still finds no `LibStub` global after `spec/export_spec.lua` runs.
- `luacheck .` clean; `check-libs.sh`, `check-links.sh`, `check-coverage.sh`
  (`Export.lua` ≥ 90%) pass.

## 7. Acceptance criteria

- [ ] `Export.lua` implements §3.1–§3.6 with the constants of §3.6, limits read from
      `Ledger` and `Collection`, no `LibStub`, WoW global or library call.
- [ ] `Core:ExportString(includeTravelers)` implements §3.7; only `true` opts in.
- [ ] Every test named in §6 exists and passes (`busted` output in the PR), including the
      RFC vectors, both goldens, the privacy walk, the limits, the fuzz and the glue
      cases; `schemaOk` runs on every result.
- [ ] Measured sizes and encode times are in the PR and in §3.10 and export-format.md;
      every measurement is under its hard ceiling.
- [ ] The default export contains no other player's GUID or name anywhere.
- [ ] No decoder in shipped code; the new `check-apis.sh` rule is in place and green.
- [ ] No URL or consumer name in `Export.lua`, `Core.lua` or the output
      (`no-urls-in-game-code` green).
- [ ] `busted`, `luacheck .`, `check-apis.sh`, `check-libs.sh`, `check-links.sh`,
      coverage (`Export.lua` ≥ 90%) green locally and in CI.
- [ ] export-format.md says **v1** with §4.2's edits; the docs of §4.4 are updated; the
      decision entry is in decisions.md.
- [ ] The reviewer did a security-level review of §5 and states it tried hostile input
      of its own.

## 8. Contract for later slices

- **Share window / `/ledger share` (UI slice):** call `ns.Core:ExportString(opted)`,
  where `opted` is a control that **starts unticked every time** the window opens and is
  passed as exactly `true` when ticked. Show the string preselected in an edit box that
  accepts its full length (no letter or byte cap; verify limits in #12), with no line
  wrapping inserted. On `nil, reason`, show a neutral message (wording is a maintainer
  gate) and never the reason code's text to the player unless the debug log is on. Name
  no site or consumer anywhere. Build the string when the window opens or on a click,
  never on a timer.
- **"Changed since you last shared" nudge:** compare **data**, never strings (bytes
  aren't stable, §3.2): e.g. store at share time the own-entry count, the newest own
  `t`, and the unlocked count, and compare those. Storing them is a SavedVariables
  change for that slice's spec.
- **Export consumers (outside this repo):** follow export-format.md → Decoding: cap
  sizes before inflating, validate every field, ignore unknown fields, reject other
  majors, never trust the string.
- **After v1:** add fields only (for example `me.region`, or "witnessed" fingerprints
  under a new key); `v` and the envelope stay `1`. Anything else bumps to `!IL2!`.
  `build`'s "no key outside §4.1" and `schemaOk` change together with the doc.

## Assumptions (listed for the maintainer)

- **No decoder or import ships in v1.** The export is a one-way street (share, render,
  keep a copy); restoring a ledger from a string would be a separate feature.
- **Travelers are all or nothing per export,** not picked one by one, and the choice is
  never remembered.
- **Travelers carry `met` and their seals,** grouped per traveler instead of the draft's
  flat list.
- **`me.name` is the name at export** (from the client), not the one stored at login;
  no realm or region is exported in v1 ([Open questions](#open-questions-maintainer) 1).
- **A read-only (damaged or newer) ledger still exports.**
- **Export refuses rather than truncates** past limits (10 000 own entries, the foreign
  caps) that no honest ledger reaches.
- **Default exports are small** (estimated 12–20 KB for 300 signatures); opted-in exports
  near the foreign cap may reach ~250 KB and take a noticeable moment to build in the
  client. Both are checked in #12.
- **The flavor is `"forever"`** by a literal, since v1 targets only Forever.

## Implementation notes (2026-09-28, #64)

Where this spec was silent, the build took the fail-closed reading. Each is also in
[decisions.md](../decisions.md) → *Export v1: what the draft left open*.

- **A zone whose `continent` isn't a kept `byContinent` key is left out** (§4.1 says
  `continent` is a `byContinent` key; §3.5's item rule didn't list the check). So a bad
  continent item takes its zones with it.
- **`collection.done` present with `signed ~= total` or `total < 1` → `"collection"`**
  (§4.1's "present only when"; §3.5 said only "present and invalid").
- **`byContinent` or `byZone` not a table → `"collection"`** (both are required in §4.1).
- **Map items follow the top level's rule** (review of #64): a `byContinent` or `byZone`
  item whose `done` comes without `signed == total >= 1` is left out, and the two map
  rows of §4.1 now pin it (as `Collection.progress` already guarantees:
  [collection-cosmetics.md §3.3](collection-cosmetics.md#33-progress)).
- **A negative zero count is written as 0:** `build` adds `0` to `signed` and `total`,
  since AceSerializer would write `-0` as `^N-0`, which isn't plain decimal digits.
  `schemaOk` refuses a negative zero.
- **Reason order:** every required top-level check runs first, in §3.5's order; only then
  are items read, so `"too_large"` never hides a required-field reason.
- **Traveler entries are read (and count toward the 3 000) only for a record whose
  GUID, name and `met` pass** and whose GUID isn't already kept. A left-out record's
  entries are never read, so the work stays bounded either way.
- **The fuzz (§6.6) isn't tagged `#sim`:** the whole spec file runs in about 1.5 s, so the
  coverage run keeps it. The traveler and limits size rows are tagged `#sim`.
- `Core.ExportString(_, includeTravelers)` is defined with a dot so luacheck doesn't flag
  the unused `self`; callers still write `ns.Core:ExportString(opted)`.
- **Checked for #76 (2026-09-30):** a zone with no Continent map above it is grouped
  under its World map ([collection-cosmetics.md §3.1](collection-cosmetics.md#31-places-inns-zones-continents)),
  so a `byContinent` key can be a World map ID (947, Azeroth). Nothing here assumed a
  Continent-type map: the key is an integer in 1..`mapKeyMax` like any other, and every
  zone still names a `byContinent` key. The format stays v1 and `build` is unchanged;
  only the key's description in §4.1 and export-format.md widened.

## Open questions (maintainer)

1. **Region or realm in the export?** Forever is realmless (one mega-realm per ruleset
   per region), so a character's public name is only unique with its region, which a
   profile site may want. v1 omits it; adding `me.region` later is additive, and
   launch-day strings would just lack it until re-shared. Worth adding now? Doesn't block
   the build.
2. **Is an import or backup restore ever wanted?** Not v1. Answering "yes, later" would
   put a spec on the post-v1 list; the untrusted-input rules would then apply to pasted
   strings. Doesn't block anything.
