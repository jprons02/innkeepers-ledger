# Spec: `Phrase` and the first `Data/Phrases` set

> **Summary:** what a signature says. The phrase data shape and ID ranges, the grammar
> that says which ID sequences are valid, how IDs render to English text, the content
> rules that keep every combination inoffensive, the `Phrase` API (validation, rendering,
> builder helpers), the hostile-input test plan, and the **draft** phrase set.
> **Read when:** implementing or reviewing `Phrase.lua` or `Data/Phrases.lua`; adding or
> rewording phrases; rendering entries in the UI or an export consumer; building the
> phrase builder or `Sign`.

**Status:** approved (self-approved 2026-09-27, ticket #62), **except the wording**: the
phrase set in [§9](#9-draft-phrase-set-draft) is a DRAFT and the maintainer decides it
(a `CLAUDE.md` gate). It ships as written until then, and the question is tracked in
[status.md](../status.md). Nothing else in this spec waits on that answer.
**Security-sensitive:** yes, moderately. `Phrase.validIds` runs on every received entry
(it's `SyncProtocol`'s rule 16 hook), and `render` turns peer-chosen ID sequences into
text the UI shows. The reviewer applies security-level scrutiny to [§5](#5-security-notes)
and must try hostile input of its own.

Builds on: [sync-ledger.md](sync-ledger.md) → §3.1 (`phraseIdMax`, `phraseIdsMax`), §3.2
(`phrase` grammar on the wire), §5.1 rule 16 (known IDs and the `phraseOk` hook);
[sync-glue.md §3.3.1](sync-glue.md#331-the-sync-instance) (`phrases` = `ns.Data.Phrases`,
`phraseOk` = `ns.Phrase.validIds`). **Changes neither**: no wire format, `SyncProtocol`
rule, `Ledger` behavior or `Sync` wiring changes here.

Binding decisions: [archive/decisions-2026-09.md](../archive/decisions-2026-09.md) →
*Canned phrases, not free text*; [decisions.md](../decisions.md) → *Sync wire format v1
and digest* (1..5 phrase IDs per entry, each 1..9999, order kept). This spec adds two
2026-09-27 entries (the implementer writes them when the PR lands): *Phrase grammar, ID
scheme and rendering* ([§3](#3-approach)) and *Phrase content rules*
([§3.6](#36-content-rules-why-no-combination-is-offensive)).

---

## 1. Problem

A signature needs something to say, and the thing it says travels peer to peer with no
moderator. The 2026-09-25 decision settled that entries use canned phrases (templates
plus word lists, in the spirit of Dark Souls messages), so every entry is a short list of
known IDs. Nothing defines those IDs yet: `Data/Phrases` is empty, so today every
received entry is rejected as an unknown phrase, and `Sign` has nothing to offer. This
slice defines the phrase data, the one grammar every client agrees on, and the pure
`Phrase` module that validates a sequence (for sync and for signing), renders it to text
(for the book and export consumers) and lists the parts (for the future builder UI). It
ships a first draft set in the inn/passport tone.

## 2. Scope

**In:**
- `Data/Phrases.lua`: the draft set of [§9](#9-draft-phrase-set-draft), in the shape of
  [§3.1](#31-data-shape-and-id-scheme), plus `ns.Data.PhraseCategories`.
- `Phrase.lua` (pure): `bind`, `validIds`, `render`, `compose` and the builder helpers
  of [§3.5](#35-api).
- `spec/phrase_spec.lua`: every case in [§6](#6-test-plan), including the hostile
  sequences and the `SyncProtocol` integration test.
- Small wiring: move `Phrase.lua` after `Ledger.lua` in the TOC ([§3.7](#37-loading-and-binding));
  one line in `spec/addon_load_spec.lua`; doc touches in [§4](#4-data-model-changes).

**Out:**
- The phrase builder UI, "recent phrases", and the fallback text for an entry that won't
  render (`UI/Book`, `Sign`). [§8](#8-contract-for-later-slices) fixes what they must do.
- Localization. v1 phrases are English only ([Assumptions](#assumptions-listed-for-the-maintainer)).
- Typed slots (a template that accepts only one category), more than two clauses, free
  text of any kind, player or place names in phrases.
- Publishing a generated phrase reference for export consumers (already a follow-up in
  [status.md](../status.md)).

## 3. Approach

### 3.1 Data shape and ID scheme

`ns.Data.Phrases` is **one table keyed directly by numeric ID**, templates,
conjunctions and words in one ID space, because `SyncProtocol` checks
`rawget(phrases, id) ~= nil` for every ID. It holds nothing else (no string keys). Each
value is a record:

| Kind | Record | ID range |
|---|---|---|
| template | `{ kind = "template", text = <string> }` | 1..499 |
| conjunction | `{ kind = "conj", text = <string> }` | 500..599 |
| word | `{ kind = "word", cat = <int>, text = <string> }` | 1000..9999 |

- IDs 600..999 are **reserved** (unused; room for a fourth kind later).
- **Words are grouped in blocks of 100 per category:** category `k` (1..90) allocates
  from `900 + 100k` .. `999 + 100k`, so category 1 is 1000..1099 and category 8 is
  1700..1799. The draft starts each block at `+1` (1001, 1101, …) and leaves the rest of
  every block free. The block is an allocation convention; the record's `cat` is what
  counts (a later re-categorization for display may break the convention with a
  decision entry; the ID keeps its meaning).
- A **template has a slot** if its text contains `{w}` (the only placeholder, exactly
  once); otherwise it is **slotless**. There's no separate flag.
- `ns.Data.PhraseCategories` is an array of category names, index = category number
  (`{ "Hearth and home", "Food and drink", … }`). Names are UI labels only; they never
  appear in an entry or its rendering.
- **Stability:** before the first public release the draft can change freely. From the
  first release on, an ID is never reused and its meaning never changes (stored entries
  and other players' books depend on it); new phrases get new IDs. See
  [Assumptions](#assumptions-listed-for-the-maintainer) for typo fixes.

Why records rather than bare strings: a word needs its category, and a later
"retired: still renders, not offered in the builder" flag needs somewhere to live. That
flag is **not** in v1.

### 3.2 Record rules

`Phrase.bind` accepts a record only if every rule holds; anything else is excluded
([§3.7](#37-loading-and-binding)). `LIMITS` are in [§3.5](#35-api).

1. The key is an integer (`type == "number"`, `x == x`, `x % 1 == 0`) in its kind's range
   (3.1), and in 1..`phraseIdMax`.
2. The value is a table with exactly the fields of its kind (3.1) and no others.
3. `text` is a string whose every byte is in the **allow-list** `A-Z a-z 0-9`, space,
   `'`, `,`, `.`, `!`, `?`, `-`, plus, in a template only, the three bytes of one `{w}`.
   So no `|` (UI escape codes), no `%` (pattern and format magic), no `\`, no control
   bytes, no bytes ≥ 128, no other `{` or `}`. Checked with explicit byte ranges, never
   `%a`/`%w`/`%l`/`%u` (locale-dependent; sync-ledger.md §5.2).
4. No leading or trailing space, and no two spaces in a row.
5. Per kind:
   - **template:** 4..`templateBytes` bytes (counting `{w}` as its 3 bytes); first byte
     `A-Z`; last byte `.`, `!` or `?`; `{w}` at most once. (So no template starts with
     its slot, and no rendering ever needs to change case.)
   - **conj:** 4..`conjBytes` bytes; first byte `A-Z`; ends with `...`.
   - **word:** 1..`wordBytes` bytes; first and last byte `a-z`; `cat` an integer in
     1..`#categories` (the bound category list).
6. A category name is a string of 1..`categoryBytes` (40) bytes under rules 3–4 (no
   `{w}`) with first byte `A-Z`. The category list is read as `1..n` up to the first
   missing or invalid name; later names, and words pointing at them, are excluded.

### 3.3 Grammar

A **clause** is a slotted template followed by exactly one word, or a slotless template
alone. A **phrase** is one clause, or two clauses joined by one conjunction. Writing
`T` for a slotted template, `t` for a slotless one, `W` for a word and `C` for a
conjunction, the valid sequences are exactly these six shapes:

| Shape | IDs | Example (draft IDs) |
|---|---|---|
| `t` | 1 | `{101}` |
| `TW` | 2 | `{3, 1201}` |
| `tCt` | 3 | `{101, 503, 106}` |
| `tCTW` | 4 | `{102, 504, 4, 1101}` |
| `TWCt` | 4 | `{3, 1201, 501, 102}` |
| `TWCTW` | 5 | `{10, 1301, 502, 11, 1002}` |

- **Any word fits any slot.** There are no typed slots; templates are written so every
  word reads as their object ([§3.6](#36-content-rules-why-no-combination-is-offensive)).
  This is what the five wire slots of sync-ledger.md §3.1 (template + word + conjunction
  + template + word) were sized for.
- Repeats are allowed (the same template or word in both clauses).
- **After the first release the grammar may only grow** (a new shape or kind that older
  clients reject, fail closed). It never shrinks: a stricter grammar would reject
  signatures that older clients made and still share. Adding typed slots later is
  possible only for *new* templates.

### 3.4 Rendering

`render(ids)` returns the English text of a valid sequence, or `nil`.
1. If `validIds(ids)` isn't `true` → `nil`.
2. **Clause text:** a slotless template's `text` as is. A slotted template's `text` with
   its `{w}` replaced by the word's `text`: find `{w}` with `string.find(text, "{w}", 1,
   true)` (plain) and join `sub(1, a - 1) .. word .. sub(b + 1)`. **Never `gsub`** with a
   data string as the replacement (`%` is magic there; rule 3 bans it anyway).
3. **One clause:** the clause text. **Two clauses:** `clause1 .. " " .. conj .. " " ..
   clause2`.
4. **No case changes, no added punctuation.** Templates start with a capital and end with
   their own `.`, `!` or `?`; words start lowercase and sit mid-sentence; a conjunction
   is a sentence opener ending in `...`, after which the second clause's capital reads
   naturally. Example: `{3, 1201, 501, 11, 1002}` → `Here's to old friends! And then...
   Will miss the hearth.`
5. **Length bound:** by the record limits, a rendering is at most
   `2 × (templateBytes − 3 + wordBytes) + 2 + conjBytes` = 2 × 69 + 18 = **156 bytes**,
   under `LIMITS.renderBytes` = **160**. The draft's worst case is far shorter (114
   bytes). A test checks both ([§6.3](#63-the-real-data-table)).

These rules, with the published IDs, are all an export consumer needs to render an
entry. They are frozen with the IDs at the first release.

### 3.5 API

All functions are pure and **never throw** on any argument (they return `false`, `nil`
or `{}`); only `Phrase.lua`'s own load can raise ([§3.7](#37-loading-and-binding)).
Returned arrays are new tables each call; changing them changes nothing inside `Phrase`.

**Constants**

| Name | Value |
|---|---|
| `Phrase.SLOT` | `"{w}"` |
| `Phrase.LIMITS` | `{ idsMax = Ledger.LIMITS.phraseIdsMax (5), idMax = Ledger.LIMITS.phraseIdMax (9999), templateBytes = 48, conjBytes = 16, wordBytes = 24, categoryBytes = 40, renderBytes = 160 }` — the two sync numbers are **read from `Ledger.LIMITS`**, not second literals |
| `Phrase.RANGES` | `{ template = { 1, 499 }, conj = { 500, 599 }, word = { 1000, 9999 }, block = 100 }` |
| `Phrase.SHAPES` | `{ t = true, TW = true, tCt = true, tCTW = true, TWCt = true, TWCTW = true }` |

**`Phrase.bind(data, categories)`** → a **set**: a table holding the functions below as
closures over a private copy of the valid records, plus `set.invalid`. Validation and
indexing happen once, here. A non-table `data` or `categories` counts as empty.
`set.invalid` is an array of short strings naming what was excluded (`"id 12"`,
`"category 4"`), for tests and the debug report; order unspecified. `bind` copies every
text it keeps, so changing `data` afterwards changes nothing.

**Set functions** (each also exposed on `Phrase` for the default set, [§3.7](#37-loading-and-binding)):

| Function | Returns |
|---|---|
| `validIds(ids)` | exactly `true` if `ids` is a valid sequence (below), else exactly `false` |
| `render(ids)` | the text (3.4), or `nil` if `validIds(ids)` isn't `true` |
| `compose(t1, w1, c, t2, w2)` | a new array of the non-`nil` arguments, in that order, if it passes `validIds`; else `nil`. The builder's one call: `compose(101)`, `compose(3, 1201)`, `compose(101, nil, 503, 3, 1201)` |
| `kind(id)` | `"template"`, `"conj"`, `"word"` or `nil` |
| `text(id)` | the record's text (templates keep `{w}`, so the builder can show a blank), or `nil` |
| `hasSlot(id)` | `true` only for a slotted template, else `false` |
| `templates()` | template IDs, ascending |
| `conjunctions()` | conjunction IDs, ascending |
| `categories()` | category names, index = category number |
| `words(cat)` | the word IDs of category `cat`, ascending; `{}` for anything else |

**`validIds(ids)`, exactly:**
1. `type(ids) ~= "table"` → `false`.
2. Count the keys with raw `next`, stopping as soon as the count passes `idsMax`
   (→ `false`). A count of 0 → `false`. Work is bounded by 6 steps whatever the table
   holds.
3. For `i = 1..n`: `id = rawget(ids, i)` must be an integer in 1..`idMax` and a valid
   record of the set; else `false`. (n keys that include every `1..n` means no holes and
   no extra keys.)
4. Build the shape string from the kinds (`T`, `t`, `W`, `C`) and return
   `SHAPES[shape] == true`.

It uses only `type`, `next`, `rawget` and arithmetic on numbers it has checked, so no
metamethod of the argument ever runs; it never writes to `ids`; and it allocates nothing
proportional to the input.

### 3.6 Content rules: why no combination is offensive

Entries propagate with no moderator, and an AddOn that spreads offensive content is the
author's problem ([addon-policy.md](../addon-policy.md), Rule 6). The draft allows about
2 200 one-clause and 19 million two-clause phrases, far too many to read, so safety comes
from rules on the parts that make every combination safe:

**Words** (every one must satisfy all of these):
1. **Not a person or a body.** No individual person (no "the innkeeper", "a stranger",
   "the bard" as words), no body part (even idioms like "a helping hand" or "a clear
   head"), no bodily function, no clothing or anything worn.
2. **No identity groups.** No race, class, faction, gender, nationality, religion or
   real-world group. Company words are collective and platonic only ("old friends", "the
   guild", "fellow travelers").
3. **Nothing intimacy-adjacent.** No bed, bath, sheets, pillow or undress words, and no
   food with a well-known slang meaning (no buns, nuts, cherries, melons, peaches,
   sausages).
4. **No violence, death, weapons or drugs.** Ordinary inn fare only; "a mug of ale" and
   "spiced cider" are the only drinks with alcohol (open question 2).
5. **No proper nouns.** No player, real-world, product, site, zone, city, NPC or faction
   name (also sidesteps faction baiting and Forever's renamed zones). Warcraft creature
   kinds written as common nouns ("the murlocs") are allowed (open question 3).
6. **Reads as an object in every template:** a lowercase noun phrase carrying its own
   article or determiner ("the hearth", "a warm fire", "hope").

**Templates:**
1. **Warm or neutral, never negative about the slot.** No warnings, complaints or
   insults ("Beware of", "Avoid", "Worst", "Never again"), so no word can be aimed at
   anything.
2. **No verbs of desire, touch or intimacy** (want, hold, kiss, touch, taste, ride,
   come/came, love, bed), and nothing about spending the night with or for something.
3. **The slot is an object or complement,** never a verb's subject, so no verb has to
   agree with a word ("Here's to {w}!", not "{w} was lovely").
4. The only person a template names is the reader ("traveler", "friend"). No template
   names the innkeeper or makes anyone the source of the slot: "Ask the innkeeper about
   good company" reads as a tavern euphemism (#62 review).

**Conjunctions** are neutral connectors with no content of their own.

**Why that covers every combination:** a clause is a warm or neutral statement about an
inoffensive thing, because no word refers to a person, body or identity and no template
is negative or intimate. A second clause adds a second such statement; a conjunction
adds no content; five IDs are too few to spell anything with initials. The Company
words do name people, but only collectively and as the reader's own circle ("old
friends", "my companions", "the guild"), and no template offers, arranges or spends the
night with the slot, so they read as fellowship. Innuendo needs a body, an intimate
object, or a provider-and-service frame ("ask X about Y"), and the rules remove all
three. Dark Souls' famous crude messages came from its body-part words; this set has
none. Words with a crude slang or phallic reading ("warm milk", "a walking staff") were
replaced in review, and the tripwire now lists them.

**Enforcement:** a reviewer reads the whole set against these rules (the lists are short),
and a **tripwire test** ([§6.3](#63-the-real-data-table)) fails if any template, word or
conjunction contains a word from a small deny-list, so a later addition that breaks a
rule is caught in CI.

### 3.7 Loading and binding

- **TOC order:** `Data\Phrases.lua` (already early), then `Ledger.lua`, then
  **`Phrase.lua` moved to just after `Ledger.lua`** (it reads `Ledger.LIMITS`, as
  `SyncProtocol` does). `load.PURE` membership doesn't change; its order may follow the
  TOC.
- At load, `Phrase.lua`:
  1. `assert(ns.Ledger, …)` (a packaging bug, like `SyncProtocol`'s assert).
  2. `local data = type(ns.Data) == "table" and ns.Data.Phrases or nil`, same for
     `PhraseCategories`.
  3. `local default = Phrase.bind(data, categories)` and copies its ten functions and
     `invalid` onto `Phrase` (`Phrase.validIds = default.validIds`, …).
- So `Phrase.validIds` takes the **single `ids` argument** `Sync` passes
  (`realDeps` reads `ns.Phrase.validIds` at `Start`, after every file has loaded), and
  the logic itself reads no `ns` state at call time: everything goes through `bind`'s
  arguments.
- **No `Data`, or a bad record, never raises.** Missing data binds an empty set
  (`validIds` is always `false`: fail closed, matching `Sync`'s `{}` fallback for
  `phrases`). A bad record is excluded and named in `invalid`; the data test keeps
  `invalid` empty. A raise at load would take the whole AddOn down in the client for a
  data typo.
- `SyncProtocol` still checks `rawget(ns.Data.Phrases, id)`. A record `bind` excluded is
  "known" to that check but fails `validIds`, and the hook can only reject more, so the
  two never disagree in the unsafe direction.
- **How tests inject fixtures:** `Phrase.bind(fixtureData, fixtureCategories)` returns an
  independent set; nothing global is touched. The real-data and integration tests load
  `Ledger.lua`, `Data/Phrases.lua` and `Phrase.lua` (and `SyncProtocol.lua`) into one
  fresh `ns` with `spec/helpers/load.lua`, pure files in the strict environment.

### 3.8 Rejected alternatives

- **Free text, or free text through a filter:** settled against (*Canned phrases, not
  free text*).
- **Separate tables per kind, each numbered from 1:** `SyncProtocol`'s one-table lookup
  would need a change to `sync-glue.md` §3.3.1 and `Sync.lua`, and a template ID could
  collide with a word ID. One ID space costs nothing.
- **Kind derived from the ID range only, with bare-string values:** smaller file, but no
  home for a word's category or a later "retired" flag. Ranges stay as a check.
- **Typed slots (a template accepts only some categories):** better grammar in places,
  but more data to keep consistent, a builder that has to filter, and the "any word fits"
  rule is what keeps the content argument of §3.6 simple. It stays possible for new
  templates later.
- **Lowercasing the second clause after a lowercase connector (`…, and then rested …`):**
  needs per-template knowledge of whether the first word is `I` or a proper noun, and
  terminal punctuation handling for `!`/`?`. Sentence-opener conjunctions ending in `...`
  need no case rule at all.
- **`gsub` for the slot:** `%` in a replacement string is magic; plain `find` + `sub`
  can't misread data.
- **Storing or sending rendered text:** reopens the free-text problem, costs wire bytes
  and breaks localization later.
- **Checking the grammar inside `SyncProtocol`:** the `phraseOk` hook already exists for
  this; `SyncProtocol` stays unchanged and re-reviewed code stays small.
- **Raising in `bind` on a bad record:** a data typo would break the AddOn in the client;
  excluding it plus a CI test is safer.
- **Negative or warning templates ("Be wary of {w}"):** the Dark Souls staple, but with
  any word in the slot they can be aimed, and the book is meant to be warm.
- **Three or more clauses:** doesn't fit the five wire slots.

## 4. Data model changes

- **SavedVariables:** none. Entries already store `phrase` as an array of 1..5 integer
  IDs (sync-ledger.md §4.1); the ledger schema stays 1. Stored entries aren't re-checked
  against the grammar at load: `render` returns `nil` for one that fails, and the UI shows
  its fallback (§8). Before this slice no entry could be stored with a phrase (every ID was
  unknown and `Sign` doesn't exist), so no migration is needed.
- **Wire format:** unchanged (v1). Every draft ID is ≤ 4 digits and every sequence ≤ 5
  IDs, inside sync-ledger.md's worst-case byte counts.
- **Export:** unchanged (v0 already carries phrase ID arrays). Consumers render with the
  published `Data/Phrases` and the rules of §3.4; add one line to
  [export-format.md](../export-format.md) under the phrase-ID paragraph pointing at this
  spec's §3.4.
- **Runtime only:** the bound set inside `Phrase` (session only).
- **Docs in the same PR:** [architecture.md](../architecture.md) → Modules, the `Phrase`
  row links this spec; export-format.md as above; [status.md](../status.md) → Open
  questions gets the wording question; [decisions.md](../decisions.md) gets the two
  entries named at the top.

## 5. Security notes

**Flag for the reviewer: security-level review of `validIds` and `render`.**

- **What a peer controls:** only the sequence of 1..5 IDs in an entry, already
  syntax-checked by `SyncProtocol` rules 10–11 (integers 1..9999, 1..5 of them) and
  looked up in `ns.Data.Phrases` (rule 16). `validIds` adds the grammar. The peer never
  supplies text: everything `render` returns comes from our own table.
- **`validIds` is defense in depth, not trust in the caller.** `SyncProtocol` passes a
  plain copy inside `pcall` and accepts only `== true`. `validIds` still treats its
  argument as hostile, because `Sign` and the UI call it directly: no metamethods (raw
  `next`/`rawget`, no `#`, no `ipairs`), bounded work (stops counting past 5 keys), no
  writes to the argument, exactly `true`/`false`, and it never throws on `nil`, numbers,
  strings, booleans, functions, userdata, `NaN`/`inf` values, huge tables, or the two
  hidden-value stand-ins of sync-ledger.md §5.2.
- **Own-signature rule, rate limits, size and storage caps:** untouched; they live in
  `SyncProtocol` and `Ledger` and this slice doesn't change them. The grammar can only
  reject more entries.
- **Text safety:** the byte allow-list (3.2 rule 3) keeps `|` escape codes, `%`, control
  bytes and non-ASCII out of every string `Phrase` can return, and `render` output is
  bounded (160 bytes). A test walks the whole table (§6.3). The UI must still display the
  text as plain text (§8).
- **Content safety (policy Rule 6):** §3.6, enforced by review and the tripwire test.
- **Forbidden-API guard:** `Phrase.lua` and `Data/Phrases.lua` name no WoW API
  (`scripts/check-apis.sh`); both load in the strict environment.

## 6. Test plan

busted, `spec/phrase_spec.lua`, pure files loaded through `spec/helpers/load.lua` in the
strict environment. Fixture sets come from `Phrase.bind`; real-data cases load
`Ledger.lua`, `Data/Phrases.lua` and `Phrase.lua` into one fresh `ns`. Coverage floor 90%
(already in `scripts/check-coverage.sh`).

A small **fixture** used below: templates `1 = "Here's to {w}!"`, `2 = "Rest well."`;
conj `500 = "And then..."`; words `1000 = "the hearth"` (cat 1), `1100 = "hot stew"`
(cat 2); categories `{ "Home", "Food" }`.

### 6.1 `bind` and record rules (fixture-based)

- The fixture binds with `invalid` empty; `templates()` = `{1, 2}`, `conjunctions()` =
  `{500}`, `categories()` = `{"Home", "Food"}`, `words(1)` = `{1000}`, `words(2)` =
  `{1100}`, `words(3)` / `words("1")` / `words(nil)` = `{}`.
- `kind`, `text` (template keeps `{w}`), `hasSlot` (true for 1, false for 2, 500, 1000,
  unknown IDs and hostile values).
- **Each rule of 3.2 broken once → that ID is excluded, named in `invalid`, `kind` is
  `nil`, and a sequence using it fails `validIds`:** key `0`, `-1`, `2.5`, `10000`, `"3"`,
  `true`; template at 600 and at 1000; conj at 50; word at 499 and at 700; missing `kind`,
  unknown `kind`, missing `text`, non-string `text`, an extra field, a word without
  `cat`, `cat = 0`, `cat = 3` (beyond the list), `cat = 1.5`; text with `|`, `%`, `\`,
  `\0`, `\t`, a UTF-8 byte, `{`, `}`, `{W}`, `{x}`, two `{w}`; a leading space, trailing
  space, two spaces; an empty text; a template of 49 bytes (48 passes); a word of 25 bytes
  (24 passes); a conj of 17 bytes (16 passes); a template starting lowercase or with
  `{w}`; a template not ending in `.`/`!`/`?`; a word starting or ending uppercase or
  with a digit; a conj not ending in `...`; a value that's a string or a number.
- **Categories:** a list with a hole at 2 → only category 1 exists and the cat-2 word is
  excluded; a non-string name, an empty name, a 41-byte name, a name with `|` → same
  (that category and later ones excluded); `categories` not a table → no category, every
  word excluded.
- `bind(nil)`, `bind("x")`, `bind({})` → an empty set: `validIds` is `false` for
  everything, lists empty, no error.
- **Copies:** changing the fixture table (a text, a new key) after `bind` changes no
  result; changing an array returned by `templates()` / `words(1)` / `categories()`
  changes the next call's result not at all.

### 6.2 `validIds`, `render`, `compose` (fixture-based unless noted)

**Accepts** each of the six shapes (fixture): `{2}`, `{1, 1000}`, `{2, 500, 2}`,
`{2, 500, 1, 1100}`, `{1, 1000, 500, 2}`, `{1, 1000, 500, 1, 1100}`; the return value is
`rawequal(true)`.

**Rejects (returns exactly `false`, never throws), one case each:**
- *not a table:* `nil`, `3`, `"1.1000"`, `true`, a function, a `newproxy` userdata, the
  table stand-in whose metatable raises on every metamethod (sync-ledger.md §5.2).
- *size:* `{}`; 6 IDs (`{1, 1000, 500, 1, 1100, 2}`); a 1 000 000-element array; a table
  with 100 000 string keys. (That the count stops after 6 keys is checked by review, not
  by timing.)
- *holes and extra keys:* `{[1] = 1, [3] = 1000}`; `{1, 1000, x = 1}`; `{[0] = 2, 2}`;
  `{2, [2.5] = 1}`; `{[2] = 2}`.
- *metamethods don't count:* `setmetatable({1}, { __index = function() return 1000 end })`
  → `false` (raw access), and the `__index` function is never called (spy).
- *non-integers and ranges:* each of `1.5`, `"1"`, `true`, `{}`, `0/0` (NaN), `1/0`,
  `-1/0`, `-1`, `0`, `10000`, `2^53`, `1e300` in position 1 and in position 2 of an
  otherwise valid `TW`.
- *unknown IDs in range:* `{3}`, `{1, 1001}`, `{9999}`.
- *wrong kind in a position:* a word where a template belongs (`{1000}`, `{1000, 1}`);
  a conj first (`{500, 2}`) or last (`{2, 500}`); two conjs (`{2, 500, 500, 2}`); a conj
  in the word slot (`{1, 500}`); a template in the word slot (`{1, 2}`); a word after a
  slotless template (`{2, 1000}`); two words (`{1, 1000, 1100}`).
- *missing word:* a slotted template alone (`{1}`); before a conj (`{1, 500, 2}`); at the
  end (`{2, 500, 1}`).
- *too many clauses:* `{2, 500, 2, 500, 2}`; two clauses with no conj (`{2, 2}`,
  `{1, 1000, 2}`).
- **No mutation:** each accepted and rejected table deep-compares equal before and after.

**Oracle differential (real data):** a seeded loop of 20 000 random sequences of 1..6
IDs, drawn from the real IDs plus `{0, 3, 499, 600, 1099, 9999, 10000, 1.5}`, gives the
same answer from `validIds` as an independent oracle in the test (map each ID to its kind
letter from `Data/Phrases` directly, then match the six shapes).

**Coverage of the real set:** every template appears in an accepted sequence (slotted
ones with word 1001, slotless alone), every word in `{1, word}`, every conjunction in
`{101, c, 101}`.

**`render`:**
- Exact strings (real data): `{101}` → `Rest well, traveler.`; `{3, 1201}` → `Here's to
  old friends!`; `{3, 1201, 501, 11, 1002}` → `Here's to old friends! And then... Will
  miss the hearth.`; `{10, 1301, 502, 11, 1002}` → `Tomorrow, the long road. But... Will
  miss the hearth.`; `{102, 504, 4, 1101}` → `Slept like a stone. Best of all... Grateful
  for fresh bread.`
- Fixture: `{1, 1000}` → `Here's to the hearth!` (the slot mid-text), and a fixture
  template with the slot last before the punctuation and one with text after the slot
  render correctly.
- Every rejected case above → `nil`, no error.

**`compose`:** `compose(101)` → `{101}`; `compose(3, 1201)` → `{3, 1201}`;
`compose(101, nil, 503, 3, 1201)` → `{101, 503, 3, 1201}`; `compose(3, nil, 501, 101)`
→ `nil` (slot needs a word); `compose(3, 1201, 501)` → `nil`; `compose()` → `nil`;
hostile arguments (NaN, tables, stand-ins) → `nil`; the returned array is a new table.

### 6.3 The real data table

Loads `Data/Phrases.lua` (strict environment) and `Phrase.lua`:
- `ns.Phrase.invalid` is empty (**every record passes 3.2**); every key of
  `ns.Data.Phrases` is an integer in 1..9999 (`Ledger.LIMITS.phraseIdMax`) and in its
  kind's range; no key in 600..999; no string key.
- Every word's `cat` matches its ID block (draft convention); every category has at
  least one word; category names pass 3.2 rule 6.
- No two records of the same kind share a text (case-insensitive), and no category name
  repeats.
- **Render bound:** compute the longest template, word and conjunction; the worst-case
  rendering (the longest slotted template with the longest word, twice, joined by the
  longest conjunction) is rendered through `render` and is ≤ `LIMITS.renderBytes` (160),
  and equals the formula of 3.4 step 5 for those lengths. Every one-clause rendering of
  the real set (templates × words, about 2 200) is ≤ 160 bytes and passes the byte
  allow-list.
- **Tripwire deny-list** (3.6): split every template, conjunction and word text into
  lowercase letter runs; none is in a list the test keeps, at least: `bed bath naked
  kiss lick touch ride came come love butt buns nuts cherry cherries melon melons
  sausage peach peaches breast thigh hole tongue rear hand head heart belly blood kill
  die dead death horde alliance human dwarf dwarves elf elves gnome gnomes orc orcs troll
  trolls tauren undead forsaken warrior mage priest rogue hunter warlock paladin druid
  shaman man woman men women boy girl`. Category names are not checked (they never enter
  an entry). A failing word is changed or the list is amended with a reason in the PR.
- The counts match §9 (24 templates, 4 conjunctions, 120 words, 8 categories), so a
  wording change that drops a record is visible in review. (Update the numbers with the
  wording; they aren't a rule.)

### 6.4 With `SyncProtocol` (integration)

One fresh `ns` with `Ledger.lua`, `Data/Phrases.lua`, `Phrase.lua`, `SyncProtocol.lua`.
`ctx` as in `spec/sync_protocol_spec.lua`'s `newCtx` (a fresh ledger, limiter and memo, a
fixed `now`), with `inns = { [1234] = true, [1235] = true, [1236] = true, [1237] = true,
[1238] = true, [1239] = true }`, `seals = {}`, **`phrases = ns.Data.Phrases`** and
**`phraseOk = ns.Phrase.validIds`**. One ENTRIES message from a resolved sender, five
entries at five inns (so the weekly rule doesn't bite), times inside the window:
- A: `3.1201.501.11.1002` (`TWCTW`) → stored;
- B: `101` (`t`) → stored;
- C: `1201.3` (known IDs, word first) → rejected;
- D: `3` (slotted template alone) → rejected;
- E: `101.501.101.501.101` (three clauses) → rejected.

Assert the result `{ kind = "entries", added = 2, dup = 0, dropped = 0, rejected = 3 }`,
`signerEntries(sender)` holds exactly A and B, and `ns.Phrase.render` of A's stored
`phrase` is `Here's to old friends! And then... Will miss the hearth.` The same message
with `phraseOk = nil` (fresh `ctx`) stores all five (the hook, not the lookup, did the
rejecting). A second message with one entry at inn 1239 using an unknown ID
(`3.1099`) is rejected with the hook and without it.

### 6.5 Whole AddOn and guards

- `spec/addon_load_spec.lua`, "the whole AddOn under the WoW stub": `ns.Phrase.validIds`
  is a function, `ns.Phrase.invalid` is empty, and `ns.Phrase.validIds({101})` is
  `true` (so `Sync`'s `realDeps` gets a working hook). The existing TOC and list tests
  pass with `Phrase.lua` moved.
- `Phrase.lua` loaded into an `ns` with no `Data` → loads, `validIds({101})` is `false`;
  into an `ns` without `Ledger` → raises (the assert).
- `luacheck .` clean; `sh scripts/check-apis.sh`, `check-libs.sh`, `check-links.sh` and
  `check-coverage.sh` (Phrase ≥ 90%) pass.

## 7. Acceptance criteria

- [ ] `Data/Phrases.lua` holds the §9 set in the §3.1 shape, plus `PhraseCategories`,
      with a DRAFT comment pointing at this spec.
- [ ] `Phrase.lua` implements §3.2–3.5 and §3.7 with the constants of §3.5 (sync limits
      read from `Ledger.LIMITS`), and `Phrase.lua` sits after `Ledger.lua` in the TOC.
- [ ] Every test named in §6 exists and passes (`busted` output in the PR), including the
      hostile sequences, the oracle differential, the table walk with the render bound,
      the tripwire, and the `SyncProtocol` integration case.
- [ ] `validIds` returns exactly `true`/`false`, uses no metamethod of its argument, stops
      after 6 keys, never writes to its argument; `render` never uses `gsub` with data as
      the replacement.
- [ ] No WoW global, `LibStub` or library call in `Phrase.lua` or `Data/Phrases.lua`.
- [ ] `busted`, `luacheck .`, `check-apis.sh`, `check-libs.sh`, `check-links.sh`,
      coverage (`Phrase.lua` ≥ 90%) green locally and in CI.
- [ ] The reviewer read the whole draft set against §3.6, did a security-level review of
      `validIds` / `render`, and states it tried hostile input of its own.
- [ ] Docs of §4 updated; the wording question is in `status.md` → Open questions; the
      two decision entries are in `decisions.md`.

## 8. Contract for later slices

- **`Sign`:** builds the sequence with `ns.Phrase.compose(...)` (or checks
  `ns.Phrase.validIds(ids) == true`) and never calls `ledger:addOwn` with a sequence that
  fails, so every own entry is one peers will accept. `compose` keeps the non-`nil`
  arguments in order and ignores their positions (`compose(nil, nil, 101)` is `{101}`),
  so the builder passes the parts in the order it wants them, not by slot.
- **UI / phrase builder:** lists parts with `templates()`, `conjunctions()`,
  `categories()`, `words(cat)` and `text(id)` (showing `Phrase.SLOT` as a blank);
  never hard-codes an ID. Shows `render` output as plain text (never as a format string
  or a `gsub` replacement). When `render` returns `nil` (an entry stored under an older
  draft, or damaged), it shows a neutral fallback; that wording is the UI slice's
  (a maintainer gate).
- **Export consumers:** render with §3.4 and the published tables; an ID they don't know
  means a newer AddOn wrote it.
- **Adding phrases after v1:** new IDs only, inside their kind's range and category
  block, passing §3.2 and §3.6 and the tests; a new category takes the next block. Older
  clients reject entries using IDs they don't have (sync-ledger.md §3.4: only that entry
  is skipped), which is expected.

## 9. Draft phrase set (DRAFT)

**Wording is the maintainer's decision** (open question 1). Everything below passes
§3.2 and was checked against §3.6. Counts: **24 templates** (18 slotted, 6 slotless),
**4 conjunctions**, **120 words** in **8 categories** of 15.

### Templates (1..499)

| ID | Text | | ID | Text |
|---|---|---|---|---|
| 1 | `Rested here, dreaming of {w}.` | | 10 | `Tomorrow, {w}.` |
| 2 | `Lingered a day longer for {w}.` | | 11 | `Will miss {w}.` |
| 3 | `Here's to {w}!` | | 12 | `Raised a cup to {w}.` |
| 4 | `Grateful for {w}.` | | 13 | `The road led me to {w}.` |
| 5 | `Found {w} here.` | | 14 | `Stopped to rest, thought of {w}.` |
| 6 | `Warmed by {w}.` | | 15 | `Heard songs of {w}.` |
| 7 | `Remember {w}.` | | 16 | `Traded tales of {w}.` |
| 8 | `Seek {w}, traveler.` | | 17 | `Write home about {w}.` |
| 9 | `Never forget {w}.` | | 18 | `May you find {w}.` |

Slotless:

| ID | Text |
|---|---|
| 101 | `Rest well, traveler.` |
| 102 | `Slept like a stone.` |
| 103 | `Safe travels, friend.` |
| 104 | `Passed through here.` |
| 105 | `I will be back.` |
| 106 | `The fire was warm.` |

### Conjunctions (500..599)

| ID | Text |
|---|---|
| 501 | `And then...` |
| 502 | `But...` |
| 503 | `Even so...` |
| 504 | `Best of all...` |

### Words (1000..9999, one block of 100 per category)

| # | Category (block) | Words, IDs from block + 1 in this order |
|---|---|---|
| 1 | Hearth and home (1000..1099) | home, the hearth, a warm fire, a cozy corner, the common room, a good night's sleep, a warm blanket, a lantern's glow, a rocking chair, a window seat, the creaky stairs, a roof overhead, the inn's cat, the stables, a quiet room |
| 2 | Food and drink (1100..1199) | fresh bread, hot stew, a bowl of soup, sweet rolls, honey cakes, apple pie, a wheel of cheese, roast boar, fresh berries, a hearty breakfast, a second helping, hot tea, warm porridge, spiced cider, a mug of ale |
| 3 | Company (1200..1299) | old friends, new friends, good company, fellow travelers, my companions, the guild, the whole party, a warm welcome, a kind word, a good deed, a shared meal, a good laugh, tall tales, a song by the fire, a game of cards |
| 4 | The road (1300..1399) | the long road, the open road, a winding path, the next town, the mountain pass, a river crossing, the ferry, a shortcut, a well-worn map, a trusty compass, a signpost, a quiet trail, the crossroads, the way home, faraway lands |
| 5 | Places (1400..1499) | the sea, the mountains, the deep forest, a quiet village, the big city, the harbor, rolling hills, a still lake, a waterfall, the meadow, the old bridge, the countryside, a hidden valley, the coast, the snowy peaks |
| 6 | Sky and seasons (1500..1599) | the morning sun, a starry night, the full moon, soft rain, fresh snow, a summer breeze, autumn leaves, the first frost, a thunderstorm, morning mist, a rainbow, the sunset, the dawn, the harvest, spring flowers |
| 7 | Adventure (1600..1699) | adventure, treasure, a new quest, an old legend, a lucky find, a hidden cave, ancient ruins, a secret door, a sunken ship, a glinting gem, a dragon, the wolves, the murlocs, a long climb, the unknown |
| 8 | Of the heart (1700..1799) | rest, peace and quiet, a fresh start, good fortune, hope, courage, sweet dreams, a clear mind, wonder, patience, a second chance, simple joys, a long nap, old memories, the little things |

So `1001` = "home", `1002` = "the hearth", …, `1015` = "a quiet room"; `1101` = "fresh
bread"; `1715` = "the little things".

Longest parts: template 14 (32 bytes), word 1006 "a good night's sleep" (20 bytes),
conjunction 504 (14 bytes); the worst-case rendering is 114 bytes.

## Assumptions (listed for the maintainer)

- **English only in v1.** Players on other client languages see English phrases. The ID
  design keeps localization additive later (a locale supplies texts for the same IDs;
  the grammar is language-independent), though languages with gender or case agreement
  may need per-template word forms, and non-ASCII text would need its own allow-list.
- **Any word fits any slot**, with no typed slots, and this is permanent for these 18
  templates once released (§3.3).
- **No negative templates:** the Dark Souls warning style ("Be wary of…") is left out on
  purpose (§3.6).
- **Joining style:** two clauses read `Clause one. And then... Clause two.` (sentence
  openers ending in `...`), which gives a diary feel and needs no case rules.
- **After the first release,** an ID's text may still get a typo or punctuation fix that
  keeps its meaning; anything more gets a new ID.
- **Beta-era entries** (the time window accepts dates from 2026-09-17) made under an
  earlier draft may render differently or not at all if the draft changes before release.
  That is acceptable before release.
- **160 bytes** is enough room for the book's layout (about three lines per entry).
- **Moving `Phrase.lua` after `Ledger.lua` in the TOC** is harmless: nothing reads
  `ns.Phrase` at load.

## Open questions (maintainer)

1. **The wording of the draft set** (§9: templates, conjunctions, words, category names)
   and its tone: warm inn-and-road lines with a little Dark Souls whimsy ("Lingered a day
   longer for the murlocs"). Ship as is, or redirect? Doesn't block the build or merge;
   the IDs can change freely until the first release.
2. **Alcohol words:** keep "a mug of ale" and "spiced cider" (inns sell both in the game),
   or keep the set alcohol-free?
3. **Game creature words:** keep Warcraft flavor like "the murlocs", or keep every word
   generic fantasy?
