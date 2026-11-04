# Spec: the data tables as JSON (`docs/data/forever.json`)

> **Summary:** the AddOn's data tables (`Data/Inns`, `Data/Cosmetics`, `Data/Phrases`)
> published as one generated, committed JSON file, so an export consumer can render inn,
> zone, seal, cosmetic and phrase text without reading Lua. The file path, the versioned
> schema and an example, what's included (only what the AddOn's `bind` functions keep),
> the exact JSON encoding (key conversion, ordering, layout, escaping, numbers), the
> generator script and its `--check` mode, the CI step, why nothing of it is packaged,
> and the tests.
> **Read when:** changing `Data/*.lua` (regenerate the file); changing
> `scripts/data-json.lua` or `docs/data/forever.json`; adding a field a consumer needs;
> writing an export consumer.

**Status:** approved (self-approved 2026-11-04, ticket #156). The maintainer decided on
2026-11-04 to build it before the first tag, that the file is neutral (it names no
consumer, like the export string), and that fields are only ever added (a change of
meaning or type bumps the schema's major). No maintainer decision is left open here.
**Security-sensitive:** no. Nothing here reads data from other players, and no sync,
`SyncProtocol` or export-decoding code changes. The JSON is written from our own
data and never read by the AddOn. The reviewer's usual checks apply, plus the packaging
check in [§5](#5-security-notes): nothing of this may ship.

Builds on: [collection-cosmetics.md §3.1–3.5, §3.11](collection-cosmetics.md#31-places-inns-zones-continents)
(place and cosmetic shapes, record rules, completeness marks; `Collection.bind`,
`Cosmetics.bind`); [phrase.md §3.1–3.4](phrase.md#31-data-shape-and-id-scheme) (phrase
shape, ID ranges, rendering; `Phrase.bind`); [export-format.md → Notes](../export-format.md#notes)
(the IDs an export carries refer to these tables). **Changes none of them:** no `Data/*`
content, module behavior, export field or shipped file changes here.

---

## 1. Problem

An export string carries only IDs: an inn's innkeeper NPC ID, zone and continent map IDs,
cosmetic IDs, phrase ID arrays. To show "Calmbreeze Inn, Zephras Isle" or render a
signature, a consumer has to read `Data/*.lua`, which means evaluating or parsing Lua
and re-implementing each `bind` function's record rules to know which records the
AddOn actually accepts. [export-format.md](../export-format.md#notes) has promised a
published form of these tables since v1. This slice generates one JSON file from the
data the AddOn binds, commits it, and has CI fail whenever the JSON and the Lua differ.

## 2. Scope

**In:**
- `scripts/data-json.lua`: the generator (Lua 5.1, no new dependencies),
  [§3.5](#35-the-generator).
- `docs/data/forever.json`: the committed output.
- `spec/data_json_spec.lua` and a test-only strict JSON reader
  `spec/helpers/json_read.lua` ([§6](#6-test-plan)).
- One step in `ci.yml`'s `busted` job ([§3.6](#36-ci)).
- `.gitattributes`: `docs/data/*.json text eol=lf`. `.luacheckrc`:
  `files["scripts/data-json.lua"] = { std = "lua51" }`.
- Docs: [export-format.md](../export-format.md) Notes point at the file and this spec;
  a context-map row in `CLAUDE.md`; a Development setup row in `CONTRIBUTING.md`; a
  decision entry; the status.md follow-up ("Publish `Data/*`…") removed.

**Out:**
- Any change to `Data/*.lua` contents (comments included), the export string or format,
  `Collection`, `Cosmetics`, `Phrase`, or anything else that ships in the game.
- A JSON reader in shipped code (the AddOn never reads this file).
- Rendering helpers, a JSON Schema document, localized names, other flavors' files.
- A coverage floor for the generator (it's a dev tool, not a pure module; the tests in
  §6 are its bar).
- A `CHANGELOG.md` entry (nothing player-facing changes).

## 3. Approach

### 3.1 File and invocation

- **Path: `docs/data/forever.json`.** `docs` is already in `.pkgmeta`'s `ignore`, so
  nothing in packaging changes, and the file sits beside
  [export-format.md](../export-format.md), which links it. `forever` is the export's
  `flavor` value; another flavor, if there ever is one, gets its own file.
- **Generator: `scripts/data-json.lua`**, run from the repo root:
  - `lua scripts/data-json.lua` builds the JSON and writes the file (binary mode, LF
    only). It prints `data-json: wrote docs/data/forever.json (<n> bytes).`
  - `lua scripts/data-json.lua --check` builds it in memory and compares it byte for byte
    with the file (read in binary mode). Equal: `data-json: OK.`, exit 0. Different or
    missing: `data-json: FAIL: docs/data/forever.json is out of date; run lua
    scripts/data-json.lua and commit it.`, exit 1. Writes nothing.
  - Any build error (below) prints `data-json: FAIL: <reason>` and exits 1 without
    writing. Not run from the root (no readable `InnkeepersLedger.toc`) or an unknown
    argument: a usage line, exit 2.
  - CI's binary is `lua5.1`; locally it's `lua` (hererocks).

### 3.2 Schema (v1)

The root is one object. Every Lua table keyed by integers becomes a JSON object whose
keys are those integers as decimal strings (`"254089"`); there are **no JSON arrays**.
Values that *refer* to a key (an inn's `zone`, a zone's `continent` and `seal`, an alias,
a rule's `zone`, a word's `cat`, a phrase's `voice`) stay JSON numbers. Every number is
an integer. An optional field is **absent**, never `null`; the file has no `null`.

| Field | JSON type | Content | Source |
|---|---|---|---|
| `schema` | number | `1`, the schema's major | literal in the generator |
| `flavor` | string | `"forever"` | literal (the export's `flavor`) |
| `atlasComplete` | boolean | the atlas's effective completeness | `Collection.complete()` |
| `continents` | object | continent map ID → `{ name, complete }` | `Collection.continent(k)` |
| `zones` | object | zone map ID → `{ name, continent, seal, complete }` | `Collection.zone(k)` |
| `inns` | object | innkeeper NPC ID → a primary `{ name, zone, faction? }` or an alias `{ alias }` | `Collection.inn(k)`, `Collection.innOf(k)` |
| `cosmetics` | object | cosmetic ID → `{ kind, name, rule }`, zone seals included; `rule` is `{ kind, n?, zone? }` | `Cosmetics.catalog()` minus `id` |
| `phraseCategories` | object | category number → name | `Phrase.categories()` |
| `phraseVoices` | object | voice number → name | `Phrase.voices()` |
| `phrases` | object | phrase ID → template or conj `{ kind, text, voice? }`, or word `{ kind, cat, text }` | `Phrase.kind/text/voice`, `Phrase.words(cat)` |

Field meanings are the Lua ones, defined once in their specs:
- **Places** ([collection-cosmetics.md §3.1](collection-cosmetics.md#31-places-inns-zones-continents)):
  `faction` is `"Alliance"` or `"Horde"`, absent for a neutral inn. An alias's `alias` is
  a key of a primary in `inns`; an export entry's `inn` may be an alias, so follow it one
  hop. **`complete` is always present and is the effective value** (§3.11): a continent
  marked complete over an unmarked zone reads `false`, as the AddOn treats it.
- **Cosmetics** ([§3.5](collection-cosmetics.md#35-cosmetic-ids)): `kind` `"seal"` or
  `"quill"`; `rule.kind` `"inns"` / `"zones"` (with `n`), `"continent"`, `"all"`, or
  `"zone"` (with `zone`, a key of `zones`) for the zone seals the AddOn generates from
  `zones`. So each zone's seal appears twice (`zones[z].seal` and `cosmetics[seal]`); a
  consumer resolves an export's cosmetic IDs and seals from `cosmetics` alone.
- **Phrases** ([phrase.md §3.1](phrase.md#31-data-shape-and-id-scheme)): `kind`
  `"template"`, `"conj"` or `"word"`; a template's `text` keeps its `{w}` slot. Render an
  export's phrase arrays with [phrase.md §3.4](phrase.md#34-rendering).

**Versioning.** Fields are only added. A field changing meaning or type bumps `schema`
(and the file stays at this path). A consumer rejects a `schema` it doesn't know and
ignores fields it doesn't know. **No AddOn version or build date is in the file**: either
would change it on every build and break reproducibility (§3.3). Records follow the data
specs' stability rules (from the first release, an ID is never removed, reused or
re-meant), so the newest file renders any export; an ID missing from it means an AddOn
newer than the file wrote the export.

**Example** (the start of the file for today's data; `…` marks elided lines):

```json
{
  "atlasComplete": false,
  "continents": {
    "947": {"complete": false, "name": "Azeroth"}
  },
  "cosmetics": {
    "1": {"kind": "seal", "name": "Wayfarer's seal", "rule": {"kind": "inns", "n": 5}},
    "2": {"kind": "seal", "name": "Innkeeper's seal", "rule": {"kind": "all"}},
    "101": {"kind": "seal", "name": "Zephras Isle", "rule": {"kind": "zone", "zone": 2521}},
    "1001": {"kind": "quill", "name": "Traveler's quill", "rule": {"kind": "inns", "n": 10}},
    "1002": {"kind": "quill", "name": "Owl-feather quill", "rule": {"kind": "inns", "n": 20}},
    "1003": {"kind": "quill", "name": "Cartographer's quill", "rule": {"kind": "continent"}}
  },
  "flavor": "forever",
  "inns": {
    "254089": {"name": "Calmbreeze Inn", "zone": 2521}
  },
  "phraseCategories": {
    "1": "Hearth and home",
    …
    "9": "Oddities"
  },
  "phraseVoices": {
    "1": "Hearthside",
    …
    "8": "Noble"
  },
  "phrases": {
    "1": {"kind": "template", "text": "Rested here, dreaming of {w}.", "voice": 1},
    …
    "501": {"kind": "conj", "text": "And then...", "voice": 1},
    …
    "1001": {"cat": 1, "kind": "word", "text": "home"},
    …
  },
  "schema": 1,
  "zones": {
    "2521": {"complete": false, "continent": 947, "name": "Zephras Isle", "seal": 101}
  }
}
```

### 3.3 Encoding (byte-for-byte reproducible)

The same data always gives the same bytes, on any OS and in any `pairs` order.

- **Key order:** an object built from integer keys lists them **numerically ascending**
  (`"9"`, `"10"`, `"101"`); an object of string keys lists them in **byte order**
  (`"phraseCategories"` < `"phraseVoices"` < `"phrases"`). One rule everywhere, so no
  per-record order table. A table mixing key types, or with a key that isn't a string or
  an integer, is a build error. An empty table is `{}`.
- **Layout:** the root and each of its object values (the sections) are written one
  member per line, indented 2 spaces per level, `,` at the end of every member line but
  the last; an empty section is `{}` on its key's line. **Every deeper object is
  written on one line**, `{"k": v, "k2": v2}`: one record per line, so a data change is a
  one-line diff. Separators are exactly `": "` and `", "`; no trailing spaces; no tabs.
  The file ends with exactly one `\n`, has no `\r` and no BOM.
- **Numbers:** integers only, in −(2^53 − 1)..2^53 − 1, written with
  `string.format("%.0f", n)` (exact for those, and not limited to a C `long`, which is 32
  bits on Windows); `0` and `-0` both write `0`. A non-integer, NaN, ±inf or anything
  out of that range is a build error.
- **Strings:** `"` → `\"`, `\` → `\\`, every byte 0x00–0x1F and 0x7F → `\u00xx`
  (4 lowercase hex digits; no short forms like `\n`). Every other byte is written as is,
  `/` included. The whole string must be **well-formed UTF-8** (RFC 3629: no stray
  continuation byte, no truncated sequence, no overlong form, no surrogate U+D800–DFFF,
  nothing above U+10FFFF); otherwise it's a build error, since a JSON text must be UTF-8.
  (Today's data is ASCII by its allow-lists, so this only matters for the encoder's own
  tests and later data.)
- **Booleans** `true`/`false`. Any other Lua type (function, userdata, thread) is a build
  error; `nil` never appears because absent fields aren't in the table.

### 3.4 What's included: only what the AddOn keeps

The generator loads the data **and** the modules that bind it, then reads every record
through the bound accessors, so a consumer never sees a record the AddOn rejects and
every value is the AddOn's normalized copy (effective `complete`, generated zone seals).
It also **fails closed**:
1. A non-empty `ns.Collection.invalid`, `ns.Cosmetics.invalid` or `ns.Phrase.invalid` is
   a build error naming the entries (`invalid: inn 5003, zone 10`). The real-data specs
   already keep them empty, so this only ever fires on a broken edit, and it fires in
   `--check` too.
2. `Cosmetics.bind` falls back to an empty atlas without adding to `invalid` if the
   atlas's zones misbehave (its second line of defense; the real atlas has already
   checked them, so no data edit triggers it today). So the generator also checks that
   `cosmetics` holds exactly one `rule.kind == "zone"` seal per entry in `zones`, at that
   zone's `seal`; else a build error.
3. Keys the accessors can't list (inns, continents) come from the raw `ns.Data` tables
   with `pairs`, sorted; each must give a record (`Collection.inn(k)`, or an alias via
   `Collection.innOf(k) ~= k`; `Collection.continent(k)`), else a build error. Zones come
   from `Collection.zoneKeys()`, cosmetics from `Cosmetics.catalog()`, phrases from
   `Phrase.templates()`, `Phrase.conjunctions()` and `Phrase.words(c)` for each category
   `c`; each raw `Data.Phrases` key must be among them, else a build error.

So, with `invalid` empty, the file holds every record of the data, and the checks make a
silent drop impossible.

### 3.5 The generator

One file, `scripts/data-json.lua`, that is also loadable as a module for the tests:
- `local load = dofile("spec/helpers/load.lua")` (the same loader the specs use). In
  `load.toc_files()` order, it runs every path in `load.DATA` plus `Ledger.lua`,
  `Phrase.lua`, `Collection.lua` and `Cosmetics.lua` into one fresh `ns`, each with
  `load.file(path, ns, load.pure_env())`: each chunk gets `(addonName, ns)` as `...`,
  in the strict environment, exactly as the specs and the client do. It's a build error
  if any of those seven paths isn't in the TOC.
- **Module table `M`:**
  - `M.encode(value)` → the JSON text of §3.3 (with the final `\n`); raises on any
    build error, with a message naming the path to the bad value (`phrases.12.text`).
  - `M.build(ns)` → the Lua table of §3.2 (integer-keyed maps, string-keyed records),
    after the checks of §3.4; raises on a failed check. It reads only `ns.Data`,
    `ns.Collection`, `ns.Cosmetics` and `ns.Phrase`, so a test can hand it any `ns`.
  - `M.loadAddon()` → the `ns` above.
  - `M.main(args, path)` → an exit code (0, 1, 2) for `args` (`{}` or `{ "--check" }`)
    and the output `path` (default `docs/data/forever.json`); prints the messages of
    §3.1; never raises (it `pcall`s the build).
- **Entry:** the chunk's arguments are the command-line arguments (`...` in Lua 5.1). If
  the first is `"--lib"` it returns `M` (the tests:
  `loadfile("scripts/data-json.lua")("--lib")`); otherwise it calls
  `os.exit(M.main({ ... }))`.
- No new global (luacheck), no library outside Lua 5.1, no `require`.

### 3.6 CI

A new step in the **`busted`** job of `.github/workflows/ci.yml`, after the existing
`busted` step, so no new job and no change to the required checks:

```yaml
      - name: Data JSON is current
        run: lua5.1 scripts/data-json.lua --check
```

The `busted` job already installs `lua5.1`. Also, `spec/data_json_spec.lua` compares the
generated text with the committed file ([§6.4](#64-the-real-data)), so a local `busted`
run catches a stale file before CI does.

### 3.7 Packaging

Nothing changes, and nothing of this ships:
- `docs/data/forever.json` is under `docs` (in `.pkgmeta` `ignore`);
  `scripts/data-json.lua` under `scripts`; `spec/data_json_spec.lua` and
  `spec/helpers/json_read.lua` under `spec`.
- `scripts/check-package.sh`'s expected file list is tracked files minus `.pkgmeta`'s
  `ignore` list, and it fails any package holding `docs/`, `spec/` or `scripts/`. Its
  `--self-test` builds a good package from that list, so a passing self-test shows the
  new files aren't in it. No new case is needed.
- `scripts/check-apis.sh` skips `spec/` and `scripts/` (the generator's `dofile`,
  `loadfile` and the spec's JSON reader are fine there).

### 3.8 Rejected alternatives

- **A top-level `data/` folder:** on Windows and macOS (case-insensitive) it is the same
  folder as `Data/`, which ships, so the JSON would land in the package.
- **`Data/forever.json`** with its own `ignore` line: next to shipped files; one
  forgotten line ships it.
- **Exporting the raw `ns.Data` tables:** a consumer could see records the AddOn
  rejects, raw `complete` marks instead of effective ones, and no zone seals in
  `cosmetics`.
- **Skipping rejected records silently:** a consumer would never see them either, but a
  broken edit would quietly vanish from the file; failing the build surfaces it.
- **JSON arrays for categories and voices:** 0-based indexes against 1-based numbers
  invite an off-by-one; one rule (integer keys → string keys) covers every table.
- **`null` for absent fields, or `"neutral"` for a missing faction:** the Lua and the
  export say "absent"; inventing a value adds a meaning.
- **An AddOn version, build date or git hash in the file:** changes every build, so the
  check would always fail. `schema` is the only version.
- **Pretty-printing every object across lines:** about 2 000 extra lines and noisy diffs;
  **one line for the whole file:** unreadable diffs.
- **A per-record field order table:** more code to keep in step; byte order is one rule.
- **`git diff --exit-code` after regenerating in CI:** mutates the checkout and needs git
  to judge; `--check` is the same command locally and in CI.
- **A new CI job:** a new required check on both branches for a one-line step.
- **A JSON library (dkjson, lua-cjson):** a new dependency for about 100 lines of
  encoder; cjson's float and escape handling isn't ours to pin.
- **Short escapes (`\n`, `\t`) or escaping non-ASCII as `\uXXXX`:** two rules where one
  does; UTF-8 is valid JSON as is.

## 4. Data model changes

- **SavedVariables:** none. **Sync message format:** none. **Export format:** none (v1
  unchanged; only its Notes gain a pointer).
- **New published format:** `docs/data/forever.json`, schema 1 (§3.2), versioned by its
  own `schema` field and the additive-only rule.
- **Docs in the same PR:**
  - [export-format.md](../export-format.md) → Notes: replace "A future version of this
    doc should publish those tables (or a generated JSON of them)…" with a pointer to
    `docs/data/forever.json` (a relative link, `data/forever.json`) and this spec's §3.2,
    saying keys are strings there and IDs follow the data specs.
  - `CLAUDE.md` context map: a row for `docs/specs/data-json.md` ("the data tables as
    JSON: `docs/data/forever.json`, schema, encoding, generator, `--check`" / "changing
    `Data/*.lua`; the generator or the JSON; writing an export consumer").
  - `CONTRIBUTING.md` → Development setup table: a row "Data JSON (after editing
    `Data/*`) | `lua scripts/data-json.lua`, check with `--check`".
  - [decisions.md](../decisions.md): a 2026-11-04 entry, *Data tables published as
    generated JSON* (the maintainer's call; path, accepted-records-only, no version in
    the file; the rejected options of §3.8, briefly).
  - [status.md](../status.md): drop "Publish `Data/*` for export consumers once inns
    exist." from Follow-ups.

## 5. Security notes

Not a sync or deserialization change: no peer data is read, and nothing touches
`SyncProtocol`, `Sync`, the own-signature rule, rate limits, size or storage caps, or
export decoding. What the reviewer checks:
- **Nothing ships** (§3.7): `check-package.sh --self-test` passes, and no `.pkgmeta`
  change was needed or made.
- **No decoder in shipped code:** the JSON reader lives in `spec/helpers/`; the AddOn
  never reads the file; `check-apis.sh`'s decoder rule is untouched.
- **Valid, unambiguous output:** a consumer parses the file with a stock JSON parser, so
  the encoder's escaping (§3.3) must make every string round-trip exactly; the hostile
  string tests of §6.1 pin it.
- **Policy:** the file is data only. It names no site, product or consumer (CLAUDE.md
  hard rules); the data's allow-lists already keep `:` and `/` out of every name and
  phrase, so no URL can appear.
- **Public repo:** the file holds only what `Data/*.lua` already publishes; source
  comments (an NPC's name, a village) aren't copied.
- The generator runs only repo files at fixed paths from the TOC, in the strict
  environment; it's a dev tool and never runs in CI with secrets.

## 6. Test plan

busted, `spec/data_json_spec.lua`, loading the module with
`loadfile("scripts/data-json.lua")("--lib")`. `spec/helpers/json_read.lua` is a small
**strict** reader of exactly the JSON §3.3 promises (objects, strings, integers,
booleans; escapes `\"`, `\\`, `\u00xx`); it rejects anything else (arrays, `null`,
floats, exponents, leading zeros, short escapes, raw control bytes, duplicate keys,
trailing commas, trailing bytes), so a pass also proves the output stays inside that
grammar. A few cases show the reader rejects each of those.

### 6.1 `encode`, hostile values

- **Escapes:** a string holding every byte 0x00–0x1F and 0x7F encodes to the
  `\u0000`…`\u001f`, `\u007f` sequence exactly; `"` → `\"`, `\` → `\\`, `/` and space
  unchanged; `"a\"b\\c"` round-trips through `json_read`; a string of all 128 ASCII
  bytes round-trips.
- **UTF-8 passes through:** `é` (2 bytes), `€` (3), U+1F600 (4), U+2028, U+FFFF,
  U+10FFFF are written byte for byte and round-trip.
- **Malformed UTF-8 raises,** one case each: a lone 0x80; 0xC3 at the end; 0xE2 0x82
  (truncated); overlong 0xC0 0xAF and 0xE0 0x80 0xAF; a surrogate 0xED 0xA0 0x80; 0xF4
  0x90 0x80 0x80 (above U+10FFFF); a 0xF5..0xFF byte. The error names the value's path.
- **Numbers:** `0`, `-0` (→ `0`), `1`, `-5`, `9999999`, `2^53 - 1` exact; `1.5`, `0/0`,
  `1/0`, `-1/0`, `2^53` raise.
- **Keys and tables:** `{[10]=…, [9]=…, [100]=…}` → keys `"9"`, `"10"`, `"100"` in that
  order; string keys in byte order (`"B"` before `"a"`); `{}` → `{}`; mixed integer and
  string keys, a float key, a boolean key, a table key raise; a function or `newproxy`
  value raises.
- **Layout:** a small fixture (root with a scalar, an empty section, a section of two
  records, one holding a nested object) encodes to an exact expected string: two-space
  indents, inline records, `": "`/`", "`, one final `\n`, no `\r`, no trailing space.
- **Determinism:** the same value built by inserting keys in ascending and in descending
  order encodes to identical bytes.

### 6.2 `build` on fixtures

Fixture data loaded through the real modules (set `ns.Data` before loading `Ledger.lua`,
`Phrase.lua`, `Collection.lua`, `Cosmetics.lua`): a neutral inn, a Horde inn, an alias,
two zones on one continent (one marked `complete`), the continent marked `complete`,
`AtlasComplete = true`, a two-record catalog, and phrases including a template without a
`voice`.
- The alias is `{ alias = <primary> }`; the Horde inn has `faction`, the neutral one
  none; the marked zone `complete = true`; the unmarked zone, the continent (marked, but
  over an unmarked zone) and `atlasComplete` all `false` (effective values).
- `cosmetics` holds the catalog's records plus one `zone` seal per zone, without `id`.
- The template without a voice has no `voice` field; words carry `cat`.
- `schema == 1`, `flavor == "forever"`.
- **Fails closed,** each raises, and `main` returns 1 without writing (temp path): a bad
  inn record (non-empty `Collection.invalid`); a bad cosmetic; a bad phrase; an `ns`
  whose `Cosmetics` is replaced by `Cosmetics.bind(nil, ns.Data.Cosmetics)` (an empty
  atlas, so no zone seals, with `invalid` empty: §3.4 check 2); a key added to
  `ns.Data.Continents` after binding (no bound record: §3.4 check 3).

### 6.3 `main`

- Write mode to a temp path writes the encoded text and returns 0; `--check` against it
  returns 0; after appending a byte to the file, or changing one record in the loaded
  `ns` (an inn's name) before building, `--check` returns 1 and leaves the file as it
  was; a missing file returns 1; an unknown argument returns 2.

### 6.4 The real data

- **The committed file is current:** `M.encode(M.build(M.loadAddon()))` equals
  `docs/data/forever.json`'s bytes.
- **It parses back to the Lua tables:** `json_read` of the file, with string keys turned
  back into integers, equals the raw `ns.Data` tables record for record: every key of
  `Data.Inns`, `Data.Zones`, `Data.Continents`, `Data.Phrases`, `Data.Cosmetics` and
  both name lists is present with the same field values, and nothing else is (`complete`
  aside, which equals `Collection.zone(k).complete` / `Collection.continent(k).complete`);
  every zone's seal is in `cosmetics` with `rule = { kind = "zone", zone = k }`;
  `atlasComplete == Collection.complete()`.
- Every number in the parsed file is an integer; the file ends in one `\n` and holds no
  `\r` and no byte ≥ 0x80 (today's data is ASCII).
- `.luacheckrc` gives `scripts/data-json.lua` no WoW globals (the existing
  `addon_load_spec` check still passes: the entry has no `read_globals`).

### 6.5 Guards and commands (run locally and in CI)

`busted`, `luacheck .`, coverage (`busted --coverage --exclude-tags=sim`, `luacov`,
`sh scripts/check-coverage.sh`: floors unchanged), `sh scripts/check-apis.sh`,
`check-libs.sh`, `check-links.sh` (the new spec's row and the export-format link),
`sh scripts/check-package.sh --self-test`, `sh scripts/check-release.sh --self-test`,
`lua scripts/data-json.lua --check`. **In the PR, show the stale case:** change one
`Data` value in a scratch commit, show `--check` exit 1 (and the `busted` failure), then
drop the commit.

## 7. Acceptance criteria

- [ ] `scripts/data-json.lua` implements §3.1 and §3.3–§3.5; `lua scripts/data-json.lua`
      writes and `--check` verifies; no new dependency or global.
- [ ] `docs/data/forever.json` is committed, matches §3.2's schema and layout (the
      example's lines appear in it as shown), and is LF-only via `.gitattributes`.
- [ ] The file holds only records the `bind` functions keep; the generator fails on a
      non-empty `invalid`, a missing zone seal, or a raw key with no bound record.
- [ ] `--check` passes on Windows (local) and Linux (CI): the bytes don't depend on the
      OS or `pairs` order.
- [ ] Every test in §6 exists and passes (`busted` output in the PR), including the
      hostile strings, malformed UTF-8, the number edges and the parse-back of the real
      file.
- [ ] `ci.yml`'s `busted` job runs `lua5.1 scripts/data-json.lua --check`; no job added or
      renamed; CI green.
- [ ] The PR shows a `Data` change without regeneration failing `--check`.
- [ ] Nothing of this ships: `.pkgmeta` unchanged, `check-package.sh --self-test` passes.
- [ ] Docs of §4 updated; `check-links.sh` passes.

## Assumptions (listed for the maintainer)

- **Path `docs/data/forever.json`**, generator `scripts/data-json.lua` (not `data/`: on
  Windows and macOS that's the shipped `Data/` folder).
- **Accepted records only,** read through the bound modules, and the generator refuses
  to write while any `invalid` list is non-empty, rather than quietly leaving records out.
- **`complete` is the effective value** and always present; `atlasComplete` likewise.
- **Zone seals are listed in `cosmetics`** (as the AddOn's catalog has them) as well as
  on each zone.
- **Field names mirror `ns.Data`** in lower camel case (`inns`, `zones`, `continents`,
  `atlasComplete`, `cosmetics`, `phrases`, `phraseCategories`, `phraseVoices`), plus
  `schema: 1` and `flavor: "forever"`; record fields keep their Lua names (`conj`, `cat`).
- **No AddOn version in the file;** `schema` is its only version.
- **Integer keys become decimal-string keys everywhere,** with no JSON arrays; reference
  values stay numbers.
- **Key order is numeric for integer keys and byte order for strings,** so `schema` is
  not the first line (JSON order carries no meaning).
- **Escapes are `\"`, `\\` and `\u00xx` for 0x00–0x1F and 0x7F; valid UTF-8 passes
  through, invalid UTF-8 fails the build.**
- **The CI step goes in the `busted` job,** and a spec makes a local `busted` catch a
  stale file too.

## Open questions (maintainer)

None. The build, the neutrality rule and the additive-only rule were decided on
2026-11-04; everything else here is technical.
