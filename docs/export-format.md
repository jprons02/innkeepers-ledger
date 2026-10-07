# Export format

> **Summary:** the export string spec (envelope, payload, data fields, privacy and trust rules). **v1**, pinned 2026-09-28 (#64).
> **Read when:** working on the Export module or changing any data that ends up in an export.

**Status: v1** (2026-09-28). From here on, fields are only added. A decoder ignores
fields it doesn't know and rejects any other major version. A change that would alter
a field's meaning or type bumps the major (`!IL2!`, `v = 2`).

The export string lets a player take their ledger out of the game (to render it, share
it, or back it up) by copying a string from an in-game edit box. It follows the
SimulationCraft pattern. The format is public and neutral: **the AddOn never names,
links or recommends any consumer of it.** How the AddOn builds it:
[specs/export.md](specs/export.md).

## Envelope

```
!IL1!<payload>
```

- `!IL` marks an Innkeeper's Ledger export; `1` is the **format major version**.
- `<payload>` = the data table → serialized (AceSerializer-3.0) → compressed
  (LibDeflate `CompressDeflate`, raw DEFLATE per RFC 1951) → printable-encoded with
  **standard base64** (RFC 4648, `A–Z a–z 0–9 + /`, `=` padding). Both steps are standard,
  so any language can decode an export with stock libraries (plus an AceSerializer reader).
- **Raw DEFLATE, not zlib or gzip framing:** no header, no checksum. The compression
  level is not part of the format; inflate works for any level.
- **No line breaks** anywhere in the string. The full string matches
  `^!IL1![A-Za-z0-9+/]*=?=?$`, and the payload's length is a multiple of 4. It holds no
  `|`, so an edit box shows it as is.
- `v` inside the data must equal the envelope's digit.
- Decoders should reject unknown major versions and ignore unknown fields.

## Serialized form

The inflated payload is AceSerializer-3.0 text (serializer revision 1):

- **Frame:** `^1`, exactly one serialized value (the data table), then `^^`.
- **Tables:** `^T`, then key, value, key, value, …, then `^t`. Arrays are written with
  explicit integer keys (`^N1`, `^N2`, …). **Keys appear in any order**, arrays
  included; index by key and never depend on the order in the text.
- **Strings:** `^S` then the text, with these escapes: a byte `n` ≤ 32 other than 30
  → `~` then the byte `n + 64` (so a space is `` ~` ``); byte 30 → `~z`; `^` → `~}`;
  `~` → `~|`; byte 127 → `~{`. Bytes 128–255 (UTF-8 names) pass through unchanged.
- **Numbers:** `^N` then plain decimal digits. **v1 writes integers only**, all below
  10^14, so a v1 export never contains `^F…^f` (floats), `^B`/`^b` (booleans) or `^Z`
  (nil). An optional field is absent, never `nil`-valued.
- The reader ignores every control byte and space in the text (the stock reader strips
  them before parsing), which is why strings escape them.

## Data (v1)

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
| `me.guid` | string | a GUID ([Names and GUIDs](#names-and-guids)) | identity | `ledger:ownerGUID()` |
| `me.name` | string, optional | a name ([Names and GUIDs](#names-and-guids)) | display name at export | Core's `ownerName()` |
| `collection` | table | `{ faction?, signed, total, done?, byContinent, byZone }` | progress over **your own** signatures, inns open to your faction | `Collection.progress(own, faction)` minus `inns`, `unknown`, `truncated` |
| `collection.faction` | string, optional | `"Alliance"` / `"Horde"` | faction counted; absent: unreadable, every inn counted | `UnitFactionGroup("player")` |
| `collection.signed`, `.total` | integer | 0..9 999 999, `signed <= total` | open inns signed / all open inns | progress |
| `collection.done` | time, optional | present only when `signed == total >= 1` | when the last open inn was first signed. Absent, even with `signed == total`, while the AddOn's data doesn't yet know every inn there; the same holds for each `byContinent` and `byZone` item's `done` | progress |
| `collection.byContinent` | table (map) | integer key 1..999 999 (the client's continent map ID: a Continent map, or the World map above a zone with no Continent, e.g. 947 Azeroth) → `{ signed, total, done? }`; `signed`/`total` ranges as `collection.signed`/`.total`; `done` a time, present only when `signed == total >= 1` | continents with at least one open inn | progress |
| `collection.byZone` | table (map) | integer key 1..999 999 (zone map ID) → `{ signed, total, continent, done? }`; `signed`/`total` ranges as `collection.signed`/`.total`; `done` a time, present only when `signed == total >= 1` | zones with at least one open inn; `continent` is a `byContinent` key | progress |
| `cosmetics` | array | `{ id = 1..9 999, t = time }`, `(t, id)` ascending, `id` unique | unlocked quills and seals and when each was earned | `Cosmetics.unlocked(own, faction, ledger:earned())` |
| `entries` | array | entry (below), `(t, inn)` ascending, `(inn, t)` unique | your own signatures; each inn's first is its stamp | `ledger:own()` |
| `travelers` | array, optional | present only when opted in (may be empty); `met` descending, then `guid` byte order; `guid` unique, never `me.guid` | travelers whose signatures you hold | `ledger:travelers()` |
| `travelers[i]` | table | `{ guid, name, met = time, entries }`; `guid`/`name` as `me.guid`/`me.name` (`name` required); `entries` 1..40 entries, `(t, inn)` ascending, `(inn, t)` unique | one traveler and **their own** signatures | `ledger:signerEntries(guid)` |
| entry | table | `{ inn = 1..9 999 999, t = time, phrase = { 1..5 IDs, each 1..9 999 }, seal = 1..999 (optional) }` | one signature | |

### Names and GUIDs

These are the AddOn's own rules (`Ledger.validGUID`, `Ledger.validName`), spelled out so a
consumer can check them without reading Lua. Traveler GUIDs and names follow the same
rules. "Letter" means a byte `A-Z`, `a-z` or 128–255 (UTF-8), and every byte count is in
bytes, not characters.

- **GUID:** `Player-`, one or more digits `0-9`, `-`, one or more hex digits
  (`0-9 A-F a-f`); at most 40 bytes in all.
- **Name:** 2..96 bytes in all, with no control byte (0–31, 127) and no `|`. It splits
  at its **first** `-` into a character name and an optional realm:
  - **Character name:** one word of 2..48 letters, or two words joined by one space, the
    first 2..48 letters and the second 1..48 letters. No `-`, digits or other bytes.
  - **Realm** (only after a `-`): 1..48 bytes of letters, digits `0-9`, `'` and `-`,
    not ending in `-` (so `Zoë-Azjol-Nerub` is the name `Zoë` on the realm
    `Azjol-Nerub`).

### Notes

- An entry's `inn` is an innkeeper NPC ID from `Data/Inns`, possibly an **alias** of the
  inn's primary record ([specs/collection-cosmetics.md §3.1](specs/collection-cosmetics.md#31-places-inns-zones-continents)).
  `phrase` IDs render with [specs/phrase.md §3.4](specs/phrase.md#34-rendering). `seal`
  and cosmetic IDs follow [specs/collection-cosmetics.md §3.5](specs/collection-cosmetics.md#35-cosmetic-ids).
- Every cosmetic time equals the `t` of one of your own entries (collection-cosmetics
  §3.6), so a consumer can check it.
- **Maps have integer keys** in the serialized form; a consumer converting to JSON turns
  them into strings.
- `collection`, `cosmetics` and `entries` are always present (possibly empty).
- The AddOn refuses to export (rather than truncate) a ledger past these limits: more
  than 10 000 own entries, 1 200 cosmetics, 1 000 zones or continents, 3 000 travelers,
  3 000 traveler entries in all, or 40 entries for one traveler.

Phrase and inn IDs refer to the tables shipped in the AddOn (`Data/Phrases`,
`Data/Inns`); zone and continent keys (the client's map IDs) to `Data/Inns`'s `Zones` and
`Continents`, and cosmetic IDs to `Data/Cosmetics` plus each zone's `seal`. `collection`
is the result of `Collection.progress` minus `inns`, `unknown` and `truncated`;
`cosmetics` is `Cosmetics.unlocked` as is (shapes, ID ranges and how each time is
derived: [specs/collection-cosmetics.md](specs/collection-cosmetics.md) §3.3–§3.6 and
§4). v1 has no separate badge kind; a consumer may present any earned cosmetic as a
badge. A future version of this doc should publish those tables (or a generated
JSON of them) so consumers can render text without reading Lua. To turn a phrase ID
array into text, follow the rendering rules in
[specs/phrase.md §3.4](specs/phrase.md#34-rendering); an ID a consumer doesn't know
means a newer AddOn wrote it.

Times on cosmetics let a consumer check that an unlock came after the entries that earn
it. Each stamp is an entry, and a zone's seal appears in `cosmetics`.

## Decoding

1. Check the size first: reject a string over 6 000 000 characters.
2. Read the prefix `!IL<digits>!`. Reject any major version other than `1`.
3. Base64-decode the rest strictly (standard alphabet, `=` padding only at the end, zero
   pad bits). Reject anything else.
4. Inflate it as **raw** DEFLATE. Reject a failed inflate or trailing bytes after the
   final block. **Cap the inflated output:** the AddOn never writes a serialized payload
   over 4 194 304 bytes, so a consumer may cap inflate output there and reject strings
   over 6 000 000 characters.
5. Read it with an AceSerializer-3.0 reader. Expect exactly one value, a table.
6. Check `v == 1`, then validate every field against [Data (v1)](#data-v1): types,
   ranges, orders, uniqueness. Ignore fields you don't know. Treat the result as
   untrusted ([Trust](#trust)).

The AddOn itself ships no decoder; this repo's reference decoder lives in its tests.

## Size

Measured 2026-09-28 under busted (PUC Lua 5.1) with the vendored libraries. Fixture
**L**: 300 own entries (5 phrase IDs each, every other one sealed), 150 zones on 5
continents, 160 cosmetics. The tests hold each row under its ceiling.

| Case | Serialized | String | Encode time (busted) | Test ceiling | Hard ceiling |
|---|---|---|---|---|---|
| Empty ledger | 211 B | 217 chars | < 0.01 s | 16 KiB | none |
| L, default | 41 448 B | 11 773 chars | 0.02 s | 16 KiB | 32 KiB |
| L + travelers, 75 × 40 entries (the caps) | 272 420 B | 84 893 chars | 0.14 s | 112 KiB | 512 KiB |
| L + travelers, 3 000 × 1 entry (worst at the caps) | 517 391 B | 164 749 chars | 0.22 s | 208 KiB | 512 KiB |
| Every limit at once, longest fields | 2 142 045 B | not encoded | 0.19 s (build + serialize) | 2 624 KiB serialized | 4 MiB serialized |

Default exports are small; opted-in exports near the foreign cap are the large case.
Build time and edit-box limits in the client are unverified
([platform-forever.md](platform-forever.md) checklist).

## Sharing in-game

- The ledger has a **Share** button (and `/ledger share`). It opens a small window with
  the export string already selected and the hint "Press Ctrl+C to copy". The window
  never names or links any site or consumer.
- When the ledger has changed since the last share, the button can say so ("Your
  ledger has changed since you last shared it"). This is a nudge, not a prompt, and it
  names no destination either.

## Privacy

- By default the export contains only **your own** signatures and collection.
- `travelers` includes other players' character names and is **opt-in** per export.
- Opting in is per export; nothing remembers it. Without it, no other player's GUID or
  name appears anywhere in the string.
- There's nothing secret in an export, but treat it as personal data.
- **Consumers that publish an export** (a public page, a shared list) show other
  travelers only as counts: how many travelers, how many of their signatures, per inn or
  in total. Never their names, GUIDs, signing times or phrases. The exporter opted in;
  the travelers named in the string didn't.

## Trust

An export is produced by open-source code on the player's machine, so **it can be
edited or forged.** Consumers must treat it as user-supplied input: validate it, cap
sizes before decompressing ([Decoding](#decoding)), and never assume it proves anything.
The format carries no key or signature on purpose; see [decisions.md](decisions.md)
(2026-09-27, profile site trust).
