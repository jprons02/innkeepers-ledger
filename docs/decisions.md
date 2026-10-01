# Decisions

> **Summary:** the decision log. Settled decisions with the reason for each and the
> options rejected, dated, **newest first**.
> **Read when:** a question may already be settled; before proposing a change in
> direction or re-proposing a rejected option.

**Don't re-litigate these.** If new information changes one, add a new dated entry at the
top that supersedes it (and links it) rather than editing history.

---

### 2026-09-30 — A zone with no Continent above it is grouped under its World map

Settled in #76, which follows *Forever beta results* (below): Zephras Isle (map 2521,
type Zone) hangs directly off the Azeroth world map (947, type World). Spec:
[specs/collection-cosmetics.md §3.1, §3.2 rule 6](specs/collection-cosmetics.md#31-places-inns-zones-continents).
- **A zone's continent is the first Continent-type map above it, or the first
  World-type map if the chain reaches one first.** So `Continents[947] = { name =
  "Azeroth" }`, and Zephras Isle's inns count under it. "Continent" in the spec,
  `byContinent` and the export means this group.
- **A map ID keys a zone or a continent, never both:** a key in both tables excludes
  both records (and cascades), whatever either holds. This also catches a zone whose
  `continent` loops back to itself or to another zone.
- **Nothing else changes:** the record shape, the progress math, `Cosmetics` and the
  export (still v1) are as they were. The group's name is the map's own name from the
  client, so no new player-facing label is needed.
- The `continent` cosmetic rule counts a World-map group like any continent. Noted for
  the catalog retune (#63), not changed.

*Rejected:*
- **`continent = nil` and an "other lands" group:** a made-up key or a hole in
  `byContinent`, a broken export rule (every zone's `continent` is a `byContinent` key),
  and a new label for the maintainer to name.
- **Each such zone as its own group:** a key in both tables, and every lone island would
  earn the `continent` rule alone.
- **Renaming `continent` to `group`:** clearer, but it renames export fields for no change
  in meaning.

*Reflected in:* `Collection.lua`, `Data/Inns.lua`, `docs/specs/collection-cosmetics.md`
§3.1, §3.2, §3.5, §3.10, §6.1, §6.6, §8, open question 1; `docs/specs/export.md`
(implementation notes, §4.1); `docs/export-format.md`; `docs/platform-forever.md` →
Verification checklist.

### 2026-09-30 — Two-part names key as the bare sender form

Settled in #75, which follows *Forever beta results* (below). On a client whose names
are two-part, a character's one key form (group map, guild map, stored traveler name)
is the sender as the server sends it, `"First Surname"`. A realm client (retail) keeps
`"Name-Realm"`, unchanged. Spec: [specs/sync-glue.md §3.4](specs/sync-glue.md#34-sender-resolution).
- **The client tells which it is from its own player unit only:** the realm slot of
  `UnitFullName("player")` holds a one-word surname that differs from
  `GetNormalizedRealmName()` (`Sync.surname`). Never from a peer string. Decided once
  both are readable; until then the realm rules apply and two-part senders fail closed.
- **Units key as `name .. " " .. surname`,** taken from the observed `player` reading
  and assumed for party and raid units until #12 sees another character. A slot that's
  empty or holds our realm leaves a two-word name alone, so the likely alternatives (the
  whole name with `nil` or our realm) key the same way. A one-word name with such a slot
  is skipped: a first-name key could match another member's one-word sender and store
  their entries under the wrong GUID (found in #75's review). Anything else skips the
  unit too.
- **Deciding "two-part" empties the group and guild maps** built before it (in the
  realm form), so keys of the two forms never mix.
- **Our own realm's suffix is dropped** from a sender or roster name (`"First
  Surname-<our realm>"` → `"First Surname"`), since both name the same character. Any
  other suffix stays, so it never matches a bare key.
- **The owner's name is `"First Surname"`** on such a client (it was the first name
  only), the same form travelers are stored in. Retail's owner name stays the bare
  name.
- The security model is unchanged: resolution still compares server-set strings with
  names our own scans read, ambiguous keys are removed, and the own-signature rule
  stands.

*Rejected:*
- **Appending our realm on Forever too (`"First Surname-ClassicBetaPvP"`):** this would
  have needed the fewest code changes (the guild map already matched that way). But the
  suffix is made up, since Forever senders carry none and you only group or guild
  within one ruleset realm. It would also put the ruleset's name into every stored and
  exported traveler name.
- **Guessing two-part names from the shape of peer strings (a space in the sender):**
  a peer string must never decide how we read names.
- **Keying units by the first name alone:** two members sharing a first name would
  collide, and a near-miss sender could match.

*Reflected in:* `Sync.lua`, `Core.lua`, `docs/specs/sync-glue.md` §3.2, §3.4, §6, §8;
`docs/platform-forever.md` → Verification checklist; `docs/testing.md`.

### 2026-09-30 — Forever beta results: modern API, two-part names, zones without continents

The first in-client run (#12, beta build 1.60.1.70124) settled most platform questions;
the facts live in [platform-forever.md](platform-forever.md). What they decide:

- **Target the modern API; the TOC says `## Interface: 16001`.** The beta installs as a
  "classic" product but runs the retail/Midnight API (`WOW_PROJECT_ID` 1), so the
  retail-style design stands. The TOC placeholder is gone, and its test now checks the
  real number.
- **Two-part names break sender keys, so sync is fixed in #75.** The surname fills the
  realm slot of `UnitName`/`UnitFullName`, and addon-message senders arrive as
  `"First Surname"` with no realm. The group map keys units as `"First-Surname"`, so
  group senders never resolve (fail-closed, as designed, so it's not a security hole),
  and the ledger's owner name keeps only the first name. The security model doesn't
  change, only how names are keyed.
- **The collection must allow a zone with no Continent above it (#76).** Zephras Isle
  hangs directly off the Azeroth world map, which breaks `collection-cosmetics.md` §3.1's
  "first Continent-type ancestor" rule.
- **Inn data comes from play.** Forever's world is new (new zones, NPC IDs from 251 000
  up), so neither Classic nor retail inn lists carry over. The probe logs every NPC the
  maintainer talks to, and `Data/Inns` fills in from those logs during the beta.
- **Sync keeps its 255-byte cap and self-contained messages.** The client truncates
  longer messages silently and reports success, and a burst of whispers arrived out of
  order. `SyncProtocol` already caps at 255 and never relies on ordering or multi-part
  messages; this confirms the design.
- **Custom-channel addon messages work,** so a post-v1 "inn common room" stays possible.
  It's still out of v1 scope.

*Rejected:*
- **Building for the Classic API because of the product name:** the client reports
  mainline, and its API is retail's.
- **Keeping a realm suffix as the canonical sender form "because retail does":** Forever
  senders carry none. #75 picks one key form from the observed facts.

*Reflected in:* `docs/platform-forever.md`, `InnkeepersLedger.toc`, `docs/status.md`,
#75, #76.

### 2026-09-28 — Account email settings stay as they are

This supersedes one clause of *Security audit: repository hardening* below ("Account
settings stop new ones"). The audit suggested turning on GitHub's commit-email privacy
and push blocking, and changing the machine's global git email. The maintainer declined:
all three apply to the whole account or machine, not just this repo, and the current
setup works. This repo's own git config already commits with the noreply address. Only
merges made on GitHub record the account's commit email.

*Rejected:*
- **Turning on email privacy and push blocking:** they're account-wide, so they can
  reject pushes or change commit authors in repos outside this project.
- **Changing the global git email:** it would restamp commits in every other repo on the
  machine.

*Reflected in:* `docs/status.md` → Waiting on the maintainer's accounts.

### 2026-09-28 — Guild sync stays on by default; players are told what it shares

The security audit noted that sync sends your newest signatures (up to 40, each with its
inn and exact signing time) to your whole guild. So in a large guild, strangers who use
the AddOn can see where and when you rested. The maintainer kept the behavior and chose
disclosure: the README's principles say exactly what sync shares and with whom (the same
approach as the combat-state entry below). This refines, and doesn't change, the
2026-09-25 sync-scope decision
([archive](archive/decisions-2026-09.md#2026-09-25--sync-scope-grouped-with--guild-by-default-global-opt-in)).
Signatures are meant to be seen, and the guild roster already shows each online member's
zone.

*Rejected:*
- **A sync on/off toggle in v1:** more UI and states before launch, and the audit found
  no harm beyond what the guild roster already shows. Revisit if players ask for it.
- **Rounding `t` on the wire (e.g. to the hour):** `t` is part of the dedupe key and is
  shown in the book. Rounding breaks the dedupe key and makes the dates less accurate,
  and it buys little privacy.
- **Saying nothing:** a quiet broadcast of where you've been looks worse than it is.

*Reflected in:* `README.md` → Principles. The book's in-game help repeats it when
`UI/Book` is built (`docs/status.md` → Follow-ups).

### 2026-09-28 — Published exports show other travelers only as counts

An opted-in export carries other travelers' names, GUIDs and signing times. The exporter
opted in, but the travelers didn't. The format stays v1 (the player's own copy may keep
everything). Instead, [export-format.md → Privacy](export-format.md#privacy) asks every
consumer that *publishes* an export to show other travelers only as counts.

*Rejected:*
- **Dropping traveler times or names from the export (v2):** breaks the pinned v1 format
  for the player's own backups, and a consumer could publish counts anyway.
- **Showing names publicly:** it publishes the travelers' own location history without
  their consent.

*Reflected in:* `docs/export-format.md` → Privacy.

### 2026-09-28 — Security audit: repository hardening

A full audit of the maintainer side and the player side found no exploitable path from
peer data (details are in the audit PRs #71 and this one). It changed:
- **Decoder guard:** `C_EncodingUtil` and its decoders joined the *general-purpose
  decoders* rule in `scripts/check-apis.sh` (#71). This tightens the rule only.
- **GitHub settings:** Actions limited to GitHub-owned ones and SHA pinning required;
  private vulnerability reporting on, with `SECURITY.md` (left out of the package).
- **Packager prerequisites** (2FA, tag-only runs, tag ruleset, a protected Environment for
  the tokens, the packager pinned and allowed by exact pattern), recorded for when the
  packager lands.

*Rejected:*
- **Rewriting history to remove the maintainer's commit email** from web-merge commits:
  it needs a force-push on protected branches, and the email is already public. Account
  settings stop new ones.
- **A domain pattern in `no-urls-in-game-code`:** too noisy (`store.me` matches); links
  without a scheme are left to review item 9.

*Reflected in:* `docs/security-checklist.md` → Repository settings;
`scripts/check-apis.sh`; `SECURITY.md`.

### 2026-09-28 — Maintainer-gated content ships as a DRAFT and doesn't block merge

Slice 3 (#61) needed content that is the maintainer's call under `CLAUDE.md`'s gates:
phrase wording (#62) and the cosmetic catalog, names and thresholds (#63). Each ticket
shipped a complete, reviewed DRAFT (marked DRAFT in the data file and the spec's §9),
merged it once tests and review passed, and put the questions in `docs/status.md` →
Open questions. This works because IDs change freely until the first public release, so
a redirect costs a data edit, not a migration. It stops being safe at the first release:
from then on an ID's meaning is frozen ([specs/phrase.md §3.1](specs/phrase.md#31-data-shape-and-id-scheme)).
Content-safety rules are not gated this way: a draft that breaks
[addon-policy.md](addon-policy.md) is fixed before merge (as #62's review did with two
innkeeper templates).

*Rejected:*
- **Blocking the build on the maintainer's wording:** stalls every later slice (sync
  rejects every entry until phrases exist) for a choice that's cheap to change later.
- **Placeholder text ("phrase 1"):** nothing real to react to, and tests would pass on
  data that can't ship.

*Reflected in:* `docs/status.md` → Open questions; `docs/specs/phrase.md` §9;
`docs/specs/collection-cosmetics.md` §9.

### 2026-09-28 — Export v1: what the draft left open

Settled in #64, which built `Export` and `Core:ExportString` and pinned the export string
as **v1** ([export-format.md](export-format.md)). Spec: [specs/export.md](specs/export.md).
From here on export fields are only added; anything else bumps the major (`!IL2!`).
- **Changes from draft v0:** `travelers` is grouped per traveler (`{ guid, name, met,
  entries }`, mirroring the store) and traveler entries keep their `seal`; `me.name` is
  optional; `v` equals the envelope's major; every array order and uniqueness rule is
  pinned (entries `(t, inn)`, cosmetics `(t, id)`, travelers `met` descending then GUID
  bytes); optional means absent, never `nil`; integers only (no floats, booleans or
  `nil` in the serialized text); `addon` is 1..32 bytes of `A-Z a-z 0-9 . _ + -`;
  `flavor` is `"forever"` in v1; the limits and `too_large`.
- **No decoder or import ships.** The export is one-way (share, render, keep a copy).
  A new forbidden-API rule, *general-purpose decoders* (`Deserialize`, LibDeflate's
  `Decompress…` and `DecodeFor…`), is allowed in no shipped file; the reference decoder
  lives in `spec/` only. (`scripts/check-apis.sh` asks for a decision entry on rule
  changes: this is it.)
- **Limits, refused rather than truncated:** 10 000 own entries, 1 200 cosmetics, 1 000
  zones or continents, the ledger's foreign caps (3 000 travelers and traveler entries,
  40 per traveler), and a 4 MiB serialized backstop. No honest ledger reaches them.
  Measured: a 300-signature ledger exports to about 12 KB; opted in at the foreign cap,
  about 165 KB.
- **Travelers opt in per export, by `true` only:** `Core:ExportString(includeTravelers)`
  passes other travelers' records only when `includeTravelers` is exactly `true`
  (`rawequal`); nothing remembers the choice. Without it, no other player's GUID or name
  is anywhere in the string (a test walks every decoded key and value).
- **Where the spec was silent (fail closed):** a zone whose `continent` isn't a kept
  `byContinent` key is left out; `collection.done` with `signed ~= total` (or `total`
  0) refuses with `collection`, as does a `byContinent`/`byZone` that isn't a table;
  every required-field reason is checked before any item is read; a traveler record's
  entries are read (and counted) only once its GUID, name and `met` pass; a map item's
  `done` without `signed == total >= 1` leaves that item out (the review pinned the rule
  in export-format.md's map rows); a negative zero count is written as `0`.

*Rejected:*
- **Shipping a decoder or an import:** pasted strings would be untrusted input;
  LibDeflate has no output limit (722:1 shown) and AceSerializer yields `NaN`, `inf` and
  floats. v1 has no use for it.
- **The draft's flat `travelers` list:** repeats a GUID and a name per entry.
- **Truncating an export over the limits:** a string silently missing stamps is worse
  than a clear refusal.
- **Our own deterministic serializer (sorted keys) or JSON:** AceSerializer was chosen and
  reviewed for export, and byte equality isn't a consumer need.
- **`Export` calling `Collection`, `Cosmetics` or the ledger itself:** plain inputs keep
  it a small, fully testable shaper; the glue owns the calls.
- **LibDeflate `EncodeForPrint`, zlib framing:** already decided (standard base64, raw
  DEFLATE).
- **Line-wrapped base64:** edit boxes and pastes mangle newlines.
- **Comparing export strings for the "changed since you last shared" nudge:** bytes
  aren't stable across clients; the nudge compares data.
- **Remembering the travelers opt-in:** the format says per export.
- **A fixed compression level (9):** very slow in pure Lua for no format gain.

*Reflected in:* `docs/specs/export.md`; `Export.lua`; `Core.lua` (`ExportString`);
`scripts/check-apis.sh`; `.luacheckrc` (`UnitFactionGroup`); `docs/export-format.md`
(v1); `docs/architecture.md` → Modules, Export; `docs/libraries.md`;
`docs/security-checklist.md`; `docs/testing.md`; `docs/platform-forever.md` →
Verification checklist.

### 2026-09-27 — Collection: places, keys and faction totals

Settled in #63, which built `Collection` and gave `Data/Inns` its shape (still empty until
#12). Spec: [specs/collection-cosmetics.md §3.1–§3.4](specs/collection-cosmetics.md#31-places-inns-zones-continents).
- **Places are keyed by integers, never names:** inns by innkeeper NPC ID (what entries,
  `SyncProtocol` and `Ledger.innFromNpcGUID` already use); zones and continents by the
  client's own map IDs, read by #12's walk (project integers if map IDs turn out
  unreadable; the scheme doesn't change). A zone carries its continent, so an inn's
  continent can't disagree with its zone. Names are English data in v1, like phrases.
- **Inns, not innkeepers:** one record per inn is the primary; any other innkeeper of the
  same inn (a faction pair, a replaced NPC) is an `alias` of it, one hop only. An entry
  at an alias counts for the primary.
- **Totals are per faction:** an inn is open to a faction if it is neutral or that
  faction's; totals, zones, continents and `done` count open inns only. An unreadable
  faction counts every inn (harder, never easier). Another faction's inns never appear.
- **Own signatures only** count toward progress; other travelers' entries are the
  crossing-paths layer. A stamp is an inn you've signed (no ID; the export's entries
  carry them); weekly re-signs add to `count`, never a stamp.
- **Records are never removed or renumbered after the first release;** a retired inn
  keeps its record, and a zone keeps its seal.
- **Where the spec was silent (fail closed):** a seal clash counts every zone record
  whose `seal` is an in-range integer, kept or not, so an otherwise-bad record clashing
  with a good zone takes both out; a record with any `alias` key is read as an alias;
  `invalid` is sorted, so its order doesn't depend on `next`.

*Rejected:*
- **Zone keys as English names or slugs:** names differ per locale and slugs need a
  naming step, while map IDs come from the client.
- **Continent on each inn record:** can disagree with its zone.
- **Counting innkeepers:** a faction pair would count one inn twice.
- **Totals over both factions:** contested zones' seals and "every inn" could never be
  earned.
- **Counting other travelers' entries:** would make the passport tradeable.

*Reflected in:* `docs/specs/collection-cosmetics.md`; `Collection.lua`; `Data/Inns.lua`;
`docs/architecture.md` → Modules; `docs/platform-forever.md` → Verification checklist;
`docs/export-format.md` → Data (`collection`).

### 2026-09-27 — Cosmetics: IDs, derived unlocks that are never taken away, seals on signing

Settled in #63, which built `Cosmetics` and the DRAFT `Data/Cosmetics` catalog (the set,
names and thresholds are the maintainer's; open question in [status.md](status.md)).
Spec: [specs/collection-cosmetics.md §3.5–§3.7](specs/collection-cosmetics.md#35-cosmetic-ids).
- **One ID space, 1..9999:** milestone seals 1..99, zone seals 101..999 (each stored on
  its zone record, allocated in the order zones are added, never reused), quills
  1000..1099, inks 1100..1199, 100 and 1200..9999 reserved. Every seal is ≤ 999, the
  wire's limit; quills and inks never travel. No badge kind in v1.
- **Rules:** `inns n`, `zones n`, `continent`, `all`, and one generated `zone` rule per
  zone seal. Thresholds are counts, never percentages; after the first release an ID
  never changes meaning and a threshold never rises.
- **Unlocks are derived from your own entries on every call,** each dated by the `t` of
  the signature that completed the rule. **The ledger's `earned` map is only a floor**
  (`Sign` records unlocks with `markEarned`): a kept time is honored only for a catalog
  ID and only if it equals the time of an own entry the call read, and the earlier of
  derived and kept wins. So a data update that adds an inn never takes a seal away, and
  every exported time is still a real signature's.
- **`SEALS` holds every seal the catalog knows,** unlocked or not (a peer's unlocks
  can't be checked), and nothing but seals. `SyncProtocol` rule 16 is unchanged: an
  unknown seal skips that entry only.
- **Signing with a seal:** `canSeal` allows it only if the seal was unlocked by entries
  already in the ledger, no later than the new entry's time, so the signature that earns
  a seal can't carry it. It checks a private lookup, not the exported `SEALS`.
- **Where the spec was silent (fail closed):** `canSeal` returns `false` for a `t` that
  isn't an integer in `tMin`..`tMax` even when `seal` is `nil`; an atlas without
  `progress`, `zoneKeys` and `zone` functions, or whose zones misbehave (an error, a
  seal out of 101..999 or used twice, a bad name, more than 899 zones), binds as an
  empty atlas; an error inside `unlocked` (possible only with a foreign atlas) returns
  `{}`; the "read" entries a kept time must match use `progress`'s own filter and
  `ownMax` bound.

*Rejected:*
- **Stamps as cosmetics with IDs:** duplicates what entries already say.
- **Pure derivation with nothing stored:** a data update would take away a seal the
  player uses, and `Sign` would then refuse it.
- **Stored unlock state as the only truth:** drifts from the entries and can't be
  rebuilt for a ledger from before recording existed.
- **A kept time taken as is:** the own-entry-time check keeps export times tied to real
  signatures at no cost.
- **Zone seal ID = map ID** (over 999) **or = 100 + list position** (renumbers on
  insert).
- **The catalog as code in `Cosmetics.lua`:** it's content the maintainer edits.
- **A read-only proxy for `SEALS`:** `SyncProtocol` reads it with `rawget`.

*Reflected in:* `docs/specs/collection-cosmetics.md`; `Cosmetics.lua`;
`Data/Cosmetics.lua`; `InnkeepersLedger.toc` (`Data\Cosmetics.lua` after
`Data\Phrases.lua`); `docs/architecture.md` → Modules, Data model, Security model;
`docs/export-format.md` → Data (`cosmetics`).

### 2026-09-27 — Phrase grammar, ID scheme and rendering

Settled in #62, which built `Phrase` and the first draft `Data/Phrases`. Spec:
[specs/phrase.md §3](specs/phrase.md#3-approach). The wording of the draft set is still
the maintainer's (open question in [status.md](status.md)); nothing here waits on it.
- **One ID space, keyed directly by number:** templates 1..499, conjunctions 500..599,
  words 1000..9999, 600..999 reserved. Each value is a record (`kind`, `text`, and `cat`
  for a word). Words take blocks of 100 per category (category `k`: `900 + 100k` ..);
  the record's `cat` is what counts. `SyncProtocol`'s one-table lookup and `Sync`'s
  wiring stay unchanged.
- **Grammar:** a clause is a slotted template plus one word, or a slotless template; a
  phrase is one clause or two joined by a conjunction. Exactly six shapes (`t`, `TW`,
  `tCt`, `tCTW`, `TWCt`, `TWCTW`) fill the five wire slots. Any word fits any slot.
  After the first release the grammar may only grow, never shrink.
- **Rendering:** the slot `{w}` is replaced with plain `find` + `sub`, never `gsub`; no
  case changes and no added punctuation (conjunctions are sentence openers ending in
  `...`). Record limits bound any rendering at 156 bytes, under `renderBytes` 160. These
  rules and the IDs freeze at the first release.
- **Validation:** `Phrase.validIds` is the `phraseOk` hook: raw `next`/`rawget` only,
  stops counting past 5 keys, never writes, returns exactly `true`/`false`. `bind`
  excludes a bad record (named in `invalid`, a CI test keeps it empty) instead of
  raising, and missing data binds an empty set that rejects everything.
- **Where the spec was silent (fail closed):** at most 90 categories are read (one block
  of 100 IDs each; more is named in `invalid`); `compose` returns `nil` for any sixth
  non-`nil` argument; `invalid` prints only numeric keys and names any other key by its
  type, so no data string is echoed; the exported `SLOT`/`LIMITS`/`RANGES`/`SHAPES` are
  copies, so changing them can't loosen the grammar.

*Rejected:*
- **Separate tables per kind, each numbered from 1:** needs `Sync` and `sync-glue.md`
  changes, and IDs of different kinds could collide.
- **Kind from the ID range only, with bare-string values:** no home for a word's
  category or a later "retired" flag.
- **Typed slots:** more data to keep consistent and a weaker content argument; still
  possible for new templates later.
- **Lowercasing the second clause after a connector:** needs per-template case rules.
- **Storing or sending rendered text:** reopens free text and costs wire bytes.
- **Checking the grammar inside `SyncProtocol`,** or **raising in `bind` on a bad
  record** (a data typo would take the AddOn down in the client).

*Reflected in:* `docs/specs/phrase.md`; `Phrase.lua`; `Data/Phrases.lua`;
`InnkeepersLedger.toc` (`Phrase.lua` after `Ledger.lua`); `docs/export-format.md` →
phrase IDs; `docs/architecture.md` → Modules.

### 2026-09-27 — Phrase content rules

Settled in #62. Entries spread peer to peer with no moderator, and the draft allows
about 19 million two-clause phrases, so safety comes from rules on the parts that make
every combination inoffensive ([specs/phrase.md §3.6](specs/phrase.md#36-content-rules-why-no-combination-is-offensive);
[addon-policy.md](addon-policy.md) Rule 6).
- **Words:** no person or body (no body parts, even in idioms; nothing worn); no
  identity group (race, class, faction, gender, nationality, religion); nothing
  intimacy-adjacent (no bed or bath words, no food with a slang meaning); no violence,
  death, weapons or drugs; no proper nouns (Warcraft creature kinds as common nouns are
  allowed for now); each a lowercase noun phrase that reads as an object in every
  template.
- **Templates:** warm or neutral, never negative about the slot; no verbs of desire,
  touch or intimacy; the slot is an object, never a verb's subject; the only person
  named is the reader. The first draft's "Thank the innkeeper for {w}" and "Ask the
  innkeeper about {w}" were dropped in review: with "good company" in the slot they read
  as a tavern euphemism.
- **Conjunctions** carry no content.
- **Enforcement:** a reviewer reads the whole set against the rules, and a tripwire test
  fails CI if any template, conjunction or word contains a deny-listed word. A failing
  word is changed, or the list is amended with a reason in the PR.

*Rejected:*
- **Negative or warning templates** ("Be wary of {w}"): with any word in the slot they
  can be aimed at something, and the book is meant to be warm.
- **Free text, or free text through a filter:** settled against (*Canned phrases, not
  free text*, [archive](archive/decisions-2026-09.md)).
- **Reading every combination:** far too many; rules on the parts cover them all.

*Reflected in:* `docs/specs/phrase.md` §3.6, §9; `spec/phrase_spec.lua` (the tripwire);
`Data/Phrases.lua`.

### 2026-09-27 — Group map details: realm form, our own name, rescan on a miss

Settled in #54, which built the group map that *Group senders resolve through our own
unit scan* (below) called for. Spec: [specs/sync-glue.md §3.4](specs/sync-glue.md#34-sender-resolution).
- **Names come from `UnitFullName(unit)`,** falling back to `UnitName(unit)` only when
  `UnitFullName` isn't a function. The realm is normalized the way
  `GetNormalizedRealmName` does it (spaces and `-` removed); `nil` or empty means our
  realm, and the key is completed with our realm exactly as a bare sender is. Whether
  this matches the sender string is on the #12 checklist; if it doesn't, group senders
  are unresolved (fails closed), never misattributed.
- **Skipped units:** hidden or invalid GUID, hidden or non-string name, over 96 bytes,
  a name containing `-` (character names can't), the client's `UNKNOWNOBJECT`
  placeholder, and a realm that's hidden, not a string, or over 48 bytes once
  normalized. A key two units claim is removed, as in the guild map.
- **Our own name is in the map** (`player` in a party; our `raidN` in a raid), like our
  row in the guild map, so our echo is dropped by `receive` as `self` without a debug
  line. The member set still leaves us out.
- **A miss rescans the map once, then looks again,** at most once per 10 s (a clock that
  went back allows one; a hidden clock none). It covers a member whose name hadn't
  loaded at the roster event. The rescan replaces the map only, never the member set,
  so a peer's messages can't drive HELLO triggers. This resolves the current message
  with fresh data; it isn't a retry of a dropped one (*Sender identity is resolved per
  channel*).

*Rejected:*
- **Using the bare `UnitName` realm as is:** it keeps spaces (`Area 52`) that the sender
  string drops, so cross-realm members would never resolve.
- **Leaving our own name out, as the member set does:** every echo would count and log
  as `unresolved`.
- **No rescan on a miss:** a member whose name loaded after the roster event couldn't
  sync (not even answer our HELLO) until the next roster change.

*Reflected in:* `docs/specs/sync-glue.md` §3.4, §3.5.1, §3.9, §5.1, §6, §8;
`docs/architecture.md` → Security model; `docs/platform-forever.md` → Verification
checklist.

### 2026-09-27 — Sync send: timer, clock and hold choices where the spec was silent

Settled while building the `Sync` send path and combat hold (#47, PR #57). The
security-level review (162 seeds × 1 simulated hour of hostile input) found every
invariant held; its two robustness findings are fixed as described here.
- **Only the resume paths release the hold.** A pump that finds us in combat enters it;
  a pump never leaves it. Only the 3 s check after `PLAYER_REGEN_ENABLED` and the 30 s
  held re-check do. A pump that bumped the generation while already held would cancel a
  pending resume for nothing.
- **A timer counts as live only once `C_Timer.After` has returned**, for the pump timer
  and the held re-check alike. A pump or re-check timer due more than 5 s ago is treated
  as lost and replaced on the next request, and a held client's pump re-arms a lost
  re-check. A timer call that raises then can't leave sync stalled behind a timer that
  doesn't exist.
- **Bad clock.** At a roster update with new members, the GROUP channel is set but the
  member set is kept, so the next update still finds them new (spec §3.5.1 says the set
  is replaced; this departs from it only while the clock is unreadable). At guild join
  nothing happens until the next update. At start, the first pump with a good clock
  runs the group and guild triggers again (a 5 s retry until then).
- **Every handed-over message gets a debug line** (`sync: sent <kind> <CHANNEL>`), and a
  failed one `sync: send failed`, with the kind from our own first byte.
- **Long simulations are tagged `#sim`** (the 40-player raid, an hour in a guild, the
  10-minute flood). The `busted` job runs them; the `coverage` job skips them, since under
  luacov they take minutes and cover no pure-module line.

*Rejected:*
- **Releasing the hold from any pump that finds us out of combat:** it would skip the
  3 s settle that §3.6 and sync-ledger §8 ask for.
- **Running the simulations under coverage too:** the local coverage run went from about
  1.5 to over 5 minutes for no coverage gain.

*Reflected in:* `Sync.lua`; `.github/workflows/ci.yml`; `docs/testing.md`;
`CONTRIBUTING.md`.

---

### 2026-09-27 — Sync receive: fail-closed choices where the spec was silent

Settled while building the `Sync` receive path (#46, PR #55). The security-level review
checked each and found them sound.
- **An `issecretvalue` that raises counts as hidden**, as in `Core`. A hidden
  `IsInGuild` counts as not in a guild. A `GUILD_ROSTER_UPDATE` while the clock is
  unreadable is skipped (the next update or the trailing rebuild catches up).
- **Leaving the guild resets the roster-request gate**, so a quick rejoin asks for the
  roster at once. **An immediate map rebuild cancels a pending trailing one**
  (generation bump), so a lost timer can't block later trailing rebuilds.
- **`api.Enum` is an optional client input** (for the prefix-result enum), so the
  instance never reads `_G`; without it only `true` and `0` are accepted.
- **Accepted messages get a debug line too** (`sync: got <kind> <CHANNEL> <guid>`, plus
  the ENTRIES counts). Reason and kind codes that aren't plain lower-case words are
  written `unknown`, in stats and in debug lines.
- **Hidden values are checked before the prefix**, as spec §3.3.3 orders it. So another
  AddOn's hidden traffic counts under `dropped.hidden` and gets a debug line. Kept
  literal for now; see *Rejected*.

*Rejected:*
- **Checking the prefix before the other three arguments' hidden checks** (hidden
  prefix first, then compare it, then the rest): it keeps other AddOns' hidden traffic
  out of the counters and log, but it changes the spec's order and only matters if the
  client hides senders broadly, in which case sync can't work anyway (spec §8). Revisit
  if #12 shows hidden senders.

*Reflected in:* `docs/specs/sync-glue.md` §3.3.1 (`Enum`); `Sync.lua`; `docs/status.md`
→ Follow-ups.

### 2026-09-27 — Group senders resolve through our own unit scan, never `UnitGUID(sender)`

Found in #46's security review. The `Sync` glue spec resolved PARTY / RAID senders with
`UnitGUID(sender)`, passing a peer-chosen name to a function that also takes unit
tokens. If the client ever gives a bare sender name and a character can be named like a
token (`Target`, `Focus`, `Mouseover`, `Softfriend`, …), `UnitGUID` returns whoever *we*
are targeting, and that member's entries would be stored under another player's GUID
(shown in the harness with modelled tokens). Both facts are unverified, but the rule is
that a peer string never decides which GUID it gets. So group senders will resolve the
way guild senders already do: a name → GUID map built from our own `partyN` / `raidN`
scan (§3.5.1's scan), with hidden, invalid, own and ambiguous names left out. #54 updates
the spec and builds it; it must land before the first release. #46 shipped the spec as
written, since nothing is released and #47 builds the scan the fix needs.

*Rejected:*
- **A deny-list of unit-token names:** the token list grows with the client and has
  compound forms (`targettarget`, `focustarget`, …); missing one is a forgery.
- **Passing the `Name-Realm` form to `UnitGUID`:** it still hands a peer string to a
  token parser, and whether the full form resolves is itself unverified.

*Reflected in:* `docs/specs/sync-glue.md` §3.4 step 3 (a note until #54);
`docs/platform-forever.md` → Verification checklist; ticket #54.

### 2026-09-27 — SyncSchedule: failed sends keep their gates; forward clock jumps wait for #12

Settled while building `SyncSchedule` (#45, PR #52), where the `Sync` glue spec was
silent. The security-level review checked each rule against the spec and found none a
deviation.
- **A failed send keeps its gate stamps** (`lastHello`, `lastReply`, `lastLarge`). Its
  budget record and in-flight entry are removed and the item is dropped, as the spec
  says, but the gate stays closed, so a transport that keeps refusing can't be retried
  in a loop. A failed GUILD HELLO still schedules the next periodic one. Only `io.send`
  returning exactly `false` is a failure; anything else counts as handed over (errs
  toward the rate limits).
- **Leaving a channel keeps its gate stamps** (`setChannel(ch, nil)` drops only the
  pending items), so leaving and rejoining a group can't bypass a gate.
- **Server time jumping forward is not clamped in v1.** Backward jumps are (spec
  §3.5.2). A forward jump ages budget records early; fuzzing with forward jumps saw up
  to 48 messages in one real minute. Realm time jumping forward is unlikely, so this
  waits for #12 to show whether it happens.

*Rejected:*
- **Rolling back the gate stamps on a failed send:** a transport that fails every time
  would then be retried on every pump.
- **Capping how far a forward jump can age records now:** it adds state and tests for a
  case no one has seen in the client.

*Reflected in:* `docs/specs/sync-glue.md` §3.5.6 step 3; `docs/status.md` → Follow-ups.

### 2026-09-27 — Debug toggle wording: keep it as written

The maintainer kept the debug-log wording from the `Sync` glue spec: the command
`/ledger debug`, the lines `Debug log on.` / `Debug log off.`, and plain `sync: …` lines.
It's developer-facing and off by default, and changing it later is a one-line edit.
Closes the open question in the *Debug log* entry below.

*Rejected:* writing in-character ledger phrasing for it now (it's a troubleshooting
tool, not something players are meant to find).

*Reflected in:* `docs/specs/sync-glue.md` §3.8; ticket #44.

### 2026-09-27 — Sync glue: a pure send schedule, logical channels and a gated large reply

Settled in the `Sync` glue spec (#42). The send side's timing rules (send budget,
HELLO / WANT / reply gates, pending queues, the combat hold) live in a new **pure**
module, `SyncSchedule`, with a **95% coverage floor** like the rest of the sync boundary.
`Sync.lua` is the thin glue around it, built as an instance with injected client
functions so tests can run two or forty clients in one Lua state. Also:
- **Logical channels:** gates and pending items are per `GROUP` (PARTY or RAID on the
  wire) and `GUILD`, so a party that becomes a raid keeps its pending reply.
- **The send budget counts at hand-off to ChatThrottleLib, with at most 2 messages in
  flight** (released by the send callback, or after 30 s). On the wire that bounds any
  60 s to 32 messages and 70 entries, under the receiver's 40 and 80.
- **Any reply of more than one message (over 5 entries) is gated** to one per channel per
  5 minutes unless our window changed. This is stricter than slice 1 §8, which gated only
  `since = 0`: a hostile peer could have asked with `since = tMin` for a full reply every
  30 s. A gated ask is deferred, not dropped.
- **`decideWant` runs only when a WANT can actually go out**, so a peer's two asks per 10
  minutes are spent on real sends and suppression sees the latest state.
- **No HELLO from an empty share window.** A new own signature (`Sync:WindowChanged()`,
  called by `Sign`) sends a HELLO on each channel after 5–15 s.
- **`Core` opens the ledger at `PLAYER_LOGIN`**, retrying an unreadable GUID 5 times over
  10 s, and never uses a hidden GUID as a table key; the ledger lives at `ns.ledger`.
- **One live pump timer:** a generation-checked timer at most 5 s ahead, and send
  callbacks request a pump (never run one), so timers can't pile up and a queued send
  doesn't stall the in-flight cap. Found in the spec review.
- **The combat names get their own `forbidden-apis` rule** (`combat state`, allowed in
  `Sync.lua`) instead of widening the `combat data` rule, which stays closed everywhere.

*Rejected:*
- **The send logic inside `Sync.lua`:** no coverage floor, no strict environment, and the
  traffic model depends on exactly this logic.
- **Scheduling inside `SyncProtocol`:** it's the validation boundary; state machines
  there grow what the security review has to re-read.
- **One timer per pending item:** hundreds in a big guild, and ordering across timers is
  hard to test. One pump with a computed wake time instead.
- **Budget counted on send callbacks only:** a lost callback would freeze sending.
- **Deciding a WANT when its jitter timer fires:** the decision goes stale behind the
  budget or a fight, and spends an ask on a WANT that may never go out.
- **Widening the `combat data` allow-list for `Sync.lua`:** it would admit the combat log,
  health and auras too.

*Reflected in:* `docs/specs/sync-glue.md`; tickets under #41.

### 2026-09-27 — Guild HELLO interval

The first guild HELLO goes 60–120 s after login (or after joining a guild), then one every
**20–25 minutes** (1 200 s plus a random 0–300 s, so guildmates don't line up), on top of
the HELLO after each new own signature. Each is still subject to the 1-per-60-s gate and
the send budget, and nothing is sent from an empty window.

A guild's news travels through the signature-triggered HELLO within seconds; the periodic
one only serves guildmates who logged in since. At 1 000 online members that's about 45
HELLOs a minute at each receiver, far under the 1 200 global limit.

*Rejected:*
- **Every 5 minutes:** about 200 HELLOs a minute in a 1 000-member guild, for news that
  isn't urgent.
- **Only at login:** a guildmate who logs in later wouldn't hear from anyone until the
  next login or signature.
- **A HELLO whenever a guildmate comes online:** roster events fire constantly and would
  make every online member answer every login.

*Reflected in:* `docs/specs/sync-glue.md` §3.5.

### 2026-09-27 — Debug log: off by default, session only, no peer strings

`/ledger debug` turns a debug log on or off for the session; the setting is never saved.
Turning it on prints one report line (the ledger state and sync counters). While it's on,
lines go to the chat frame, at most 5 per 10 s, with a count of the lines skipped. A line
holds only our own words and reason codes, numbers, a channel name from our own set, and a
sender GUID after it passed validation: never a name, message text or error text. The
toggle wording is a placeholder until the maintainer gives a direction.

*Rejected:*
- **A saved setting:** it gets forgotten on, and prints for weeks.
- **An in-memory log buffer:** it would hold peer-derived data that nobody reads.
- **Printing every drop:** a raid would flood the chat frame.

*Reflected in:* `docs/specs/sync-glue.md` §3.8; `docs/status.md` → Open questions.

### 2026-09-27 — Ledger orders by bytes, keeps sorted indexes, and tightens two inputs

Built in #30 (PR #38). Three choices the spec left open or that came out of review:
- **Signer GUIDs compare byte by byte** in the eviction order `(t, signer, inn)` and in
  `travelers()`. Lua 5.1's string `<` uses `strcoll`, so its order follows the C
  locale. Some locales rank distinct strings equal, which would let a binary-search
  removal take the wrong entry and leave an index stale.
- **Foreign entries live in sorted indexes** (all foreign, and per inn, both in
  eviction order). Each add or eviction costs a binary search plus one array shift. A
  full 3 000-entry store takes a 10 000-entry flood in well under a second.
- **`addForeign` takes `now` only in `tMin..tMax`**, the range normalize accepts for
  `met`, so a bad clock can't plant a `met` that resets on every load. **Only an
  `"added"` entry renames a traveler**; a `"dropped"` one changes nothing.

*Rejected:*
- **String `<` for signers:** simpler, but its result depends on the client's collation.
- **Linear scans for the oldest entry:** about 20 M comparisons for the 10 000-entry
  flood.
- **Renaming on any accepted-looking add, including `"dropped"`:** it changes what's
  stored while reporting that nothing was.
- **Batching the load-time cap pass now:** a tampered file far over the caps (40 000
  entries) loads in about 4 s because each eviction shifts large arrays. Peers can't
  cause this and honest data stays under 3 000 entries, so it's a follow-up in
  `status.md`, not a v1 need.

*Reflected in:* `Ledger.lua`; `docs/specs/sync-ledger.md` §4.3–§4.5 (which also records
the smaller clarifications: `loadReport` fields, `canSign` and `markEarned` on bad input,
non-table own entries, the post-migration shape check).

### 2026-09-27 — Coverage floors on pure modules, a doc-link check, and local test runs

Two required CI jobs join the others. `coverage` runs `busted --coverage` and luacov
0.17.0, then `scripts/check-coverage.sh` enforces line-coverage floors: **95%** for
`Ledger` and `SyncProtocol` (the peer-data boundary) and **90%** for the other pure
modules. It fails closed: a missing report, a module missing from it, or a `luacov:`
opt-out comment fails the job. `docs-links` runs `scripts/check-links.sh`: every relative
link in the docs resolves, and every doc under `docs/` has a context-map row. The local
toolchain turned out to work once it's on `PATH`, so sessions run every check locally
before pushing, with CI as confirmation rather than the only test run. The maintainer
asked for this.

*Rejected:*
- **100% floors:** defensive branches that can't happen after validation would have to be
  deleted or contrived into tests; 95% leaves room without hiding whole paths.
- **Coverage of glue modules:** glue calls the client; it's checked in the client, and
  its stubbed parts would inflate the numbers.
- **Folding coverage into the `busted` job:** the required checks would be less specific
  (same reason as the separate CI jobs in the 2026-09-26 CI entry).
- **Allowing `luacov: disable` with review:** an opt-out in the security modules is
  exactly what the floor exists to stop.
- **Checking `#anchor` fragments in doc links:** GitHub's heading slugs are hard to
  reproduce exactly in `sh`; broken files are the common failure.

*Reflected in:* `.github/workflows/ci.yml`; `.luacov`; `scripts/check-coverage.sh`;
`scripts/check-links.sh`; `CONTRIBUTING.md` → Development setup;
`docs/security-checklist.md`; `CLAUDE.md` → Testing; branch protection.

### 2026-09-27 — Re-signing follows the game's weekly reset (supersedes the Friday 10:00 UTC entry below)

A character may still sign each inn once per week, but the signing week now turns over
at **the game's own weekly reset** for the player's region, not Friday 10:00 UTC. The
maintainer chose this. The glue reads the reset from the client
(`C_DateAndTime.GetSecondsUntilWeeklyReset`, with a per-region fallback table), and
`Ledger` takes it as an argument, so no region's time is hard-coded. The rule still
applies to incoming signatures. Details: `docs/specs/sync-ledger.md` §4.4, §8.

The region concern in the entry below doesn't hold: Forever is realmless per region,
and players from different regions never group or share a guild, so they never sync.
Everyone who syncs shares one reset.

*Rejected:*
- **Friday 10:00 UTC** (the entry below): a second weekly rhythm players would have to
  learn, next to the reset they already plan around.
- **Hard-coding each region's reset time:** Blizzard can move it, and Forever's times
  are unverified; the client already knows.

*Reflected in:* `docs/specs/sync-ledger.md`; `docs/platform-forever.md` → Verification
checklist; ticket #30.

### 2026-09-27 — Re-signing an inn: once per week, resetting Friday 10:00 UTC

A character may sign each inn once per signing week. Weeks start every **Friday at
10:00 UTC** (the maintainer chose weekly; the session picked the reset time within that).
The ledger enforces the rule for incoming signatures too: a traveler's second signature
at the same inn in the same week is rejected. Signing a different inn in the same week
is fine. Details: `docs/specs/sync-ledger.md` §3.1 (`weekAnchor`), §4.4.

*Rejected:*
- **Once per day** (the first proposal): repeat visits would fill a traveler's 40-entry
  share window with one inn, and own entries (never evicted) would grow fast.
- **WoW's own weekly reset:** it differs by region (Tuesday 15:00 UTC in the US,
  Wednesday 07:00 UTC in Europe), so two players could disagree about which week a
  signature is in. A fixed UTC time is the same for everyone and is plain arithmetic on
  server time.
- **A rolling 7 days since the last signature:** harder to explain in the UI than "the
  ledger turns a page every Friday".
- **Limiting only our own signing:** a modified client could still fill all 40 of its
  slots at one inn; checking incoming signatures too costs one lookup.

*Reflected in:* `docs/specs/sync-ledger.md`; tickets #30, #31.

### 2026-09-27 — Peer-data rate limits and time window

Received, per resolved sender GUID in fixed 60-second windows: 40 messages and 80
entries. Across all senders: 1 200 admitted messages. At most 1 000 senders are tracked;
when the table is full after pruning, new senders are dropped. Sent, by our own `Sync`:
at most 30 messages and 60 entries in any 60 s, 1 HELLO per channel per minute, 12
WANTs per minute, and one full reply per channel per 5 minutes (a later one is deferred,
not dropped). Timestamps must fall
between 2026-09-17 00:00 UTC (the Forever beta start) and now + 300 s. The numbers are
checked against a written traffic model (a 40-player raid syncing from scratch stays
under every limit). Details: `docs/specs/sync-ledger.md` §3.1, §5.3, §8.

*Rejected:*
- **The launch date (2026-11-04) as the earliest time:** entries signed during the beta
  would fail, so the AddOn couldn't be tested there. Backdating by seven weeks gains a
  forger nothing.
- **A token bucket:** smoother, but a fixed window is simpler to test exactly, and the
  double burst at a window edge is still small.
- **No global ceiling:** a crowd of modified clients could each stay under the
  per-sender limit.
- **The first draft's 30 / 600 limits:** they left WANT traffic out, so honest raid
  traffic would have been dropped (found in the spec review).

*Reflected in:* `docs/specs/sync-ledger.md`; `docs/architecture.md` → Security model.

### 2026-09-27 — Ledger storage: caps, eviction and SavedVariables shape

Foreign entries are capped at **40 per signer** (equal to the share window), **150 per
inn** and **3 000 in total** (about 400 KB of SavedVariables). Over a cap, the oldest
entry by `(t, signer, inn)` goes, so the store always holds the newest. Own entries are
never evicted. Ledgers live in `InnkeepersLedgerDB.global.ledgers[<character GUID>]`
with a ledger-level `schema` field (the per-entry `v` is gone), entries grouped per
traveler, and the time each cosmetic was earned. A ledger whose schema is newer than the
AddOn, or unreadable, opens read-only and is never rewritten. Details:
`docs/specs/sync-ledger.md` §4.

*Rejected:*
- **AceDB's per-character namespace:** it's keyed by name, and names can change; the
  GUID is the identity.
- **Evicting by receive time:** replaying old entries would keep them alive; signing
  time is what the book shows.
- **A flat list with signer and name on every entry:** repeats the GUID and name up to
  40 times per traveler.
- **Larger caps (10 000+):** multi-megabyte SavedVariables for a guild-heavy player,
  with little gain on the book's pages.
- **Wiping or rewriting unreadable saved data:** it would destroy a player's ledger after
  a downgrade.
- **Migrating in place:** a migration that fails halfway would leave half-migrated
  data; migrations run on a copy that is written back only on success.

*Reflected in:* `docs/specs/sync-ledger.md` §4; `docs/architecture.md` → Data model.

### 2026-09-27 — Sync wire format v1 and digest

Three ASCII messages, `H1:<count>:<digest>`, `W1:<target GUID>:<since>` and
`E1:<entry>;…` with up to 5 entries of `inn,t,p.p.p,seal`, in decimal with exactly one
spelling per number; every message fits in 255 bytes (worst case 242). ENTRIES are
broadcast so one reply serves every asker. The digest is a polynomial hash
`h = (h * 257 + byte) % 2147483647` over the canonical text of the sender's newest 40
own entries, which is exact in Lua 5.1 without a `bit` library. A peer is asked at most
twice per 10 minutes whatever its digest does, and a WANT seen on the same channel for the
same peer suppresses ours (the broadcast reply covers us). A syntax error drops the
whole message, while an unknown inn, phrase or seal skips only that entry. Messages
echoed back from ourselves are dropped. Details: `docs/specs/sync-ledger.md` §3, §5.1.

*Rejected:*
- **CRC32 / FNV:** need bitwise operations that busted's Lua 5.1 lacks, so the tests
  wouldn't run the shipped code.
- **Count + newest time as the digest:** misses a lost message in the middle.
- **Base36 or binary numbers:** one more entry per message, but a harder parser to audit.
- **A version on every entry:** the header already carries it.
- **Replying by whisper:** whispers aren't an accepted channel in v1.
- **Dropping a whole message for one unknown ID:** a peer with newer inn data would lose
  its valid entries too.
- **Capping WANTs per (peer, digest):** a peer churning its digest could make a whole
  raid broadcast WANTs nonstop (found in the spec review).

*Reflected in:* `docs/specs/sync-ledger.md`; `docs/architecture.md` → Sync protocol.

### 2026-09-27 — AddOn list blurb names both halves of the AddOn

The TOC `## Notes` line (the tooltip in the in-game AddOns list) reads "Sign the ledger
at every inn you rest in, and collect the signatures of travelers you meet along the
way." The maintainer took this recommendation.

*Rejected:*
- **Reusing the README's line** ("Talk to an innkeeper, sign the ledger, and fill a book
  of every inn you've rested at."): it describes only the inn collection and leaves out
  travelers crossing paths, which is what sets the AddOn apart.

*Reflected in:* `InnkeepersLedger.toc`.

### 2026-09-27 — Profile site trust: showcase only, no profile key in the v1 export

Exports can't be proven genuine: the code is public, there's no network, and the player
controls both the string and SavedVariables. So the site **shows collections off and
never ranks them**, which removes the reward for faking. Trust work lives on the site,
after launch:
- **Sanity checks:** only real inns; no times before launch or in the future;
  cosmetics earned after the entries behind them; no impossible travel; a re-upload
  keeps earlier stamps.
- **Ownership:** a login at first Publish, and "Log in with Battle.net" if Blizzard's
  API covers Forever characters (unchecked).
- **A report button.**
- **Later, "witnessed" stamps:** a future export carries fingerprints of entries
  received through sync (no names), so the site can mark a stamp that another
  uploader's ledger also holds.

The v1 export stays as specified. New fields can be added later without breaking old
strings.

*Rejected:*
- **Leaderboards:** they reward forging, and nothing can stop it.
- **A profile key in the v1 export:** the Share window would need a "keep this private"
  warning, anyone shown the string could take over the profile, and a site login gives
  the same protection with no AddOn change.

*Reflected in:* `docs/export-format.md` → Trust.

### 2026-09-27 — Profile website: after v1, a separate project, reached by one paste

A website with public player profiles (passport stamps, zone seals, earned badges) is a
post-v1 direction. The goal is that players go out of their way to share. The flow is
the export string: **Share** in the ledger shows the string preselected, the player
copies it, pastes it into the site, sees a preview and publishes. Pasting again later
updates the profile. WoW players already do this daily with WeakAuras and
SimulationCraft strings, so it isn't a scary step. v1 only needs the Share button and an
export that carries stamps, seals and badges with the time each was earned
([export-format.md](export-format.md)). The site itself is its own project, not part of
this repo.

The maintainer ruled that **neither the AddOn nor its download pages (CurseForge, Wago)
name or link the site**, so the policy rule in [addon-policy.md](addon-policy.md) stands
unchanged. Players find the site through the site itself and word of mouth. Profiles
show only the uploader's own signatures, never the travelers they met. How far the site
should trust uploads is still being discussed ([status.md](status.md)).

*Rejected:*
- **A companion desktop app that uploads automatically:** an install, Windows
  "unknown publisher" warnings unless a code-signing certificate is bought every year,
  and a second product to maintain.
- **Dragging the SavedVariables file onto the site:** players would have to find a
  folder buried in the WoW install.
- **An in-game prompt to upload:** it would name an outside site (Rule 4).
- **Mentioning the site on the download pages:** the maintainer said no.
- **Building the site before launch:** it would put the 2026-11-04 date at risk, and a
  versioned export means launch-day strings still work later.

*Reflected in:* `docs/vision.md` → Where it can grow; `docs/export-format.md`.

### 2026-09-27 — Keep the inn ledger after a pivot review

The maintainer considered changing the concept. Research on 2026-09-27 found every
alternative already taken on Forever or elsewhere, while nothing on Forever collects or
signs inns ([prior-art.md](prior-art.md) → The Forever landscape). The ledger stays;
v1 leans harder into the collection feeling like a passport (a stamp per inn, a seal per
zone).

*Rejected:*
- **Player memory ("familiar faces"):** Blizzard's Recent Allies ships in Forever, and
  iWillRemember already runs there.
- **An automatic character chronicle:** Forever Journal launched 2026-09-24, from an
  author shipping a Forever AddOn almost daily.
- **A Hardcore memorial wall:** Deathlog, Hardcore and a Forever-native memorial exist,
  and Forever has no Hardcore ruleset at launch.
- **Campfire stories:** 13 camping AddOns appeared in the first 10 days of the beta.
- **An "inn common room" with strangers over a hidden channel:** Blizzard blocked
  addon messages to custom channels in Classic in 2019. Whether Forever allows them is
  on the in-client checklist; if it does, this is a post-v1 candidate.

### 2026-09-27 — Sync may read combat state, and players are told

`Sync` may use `InCombatLockdown` and the `PLAYER_REGEN_*` events to hold sends until a
fight ends. That's a yes/no state flag; combat *data* (damage, targets, logs) stays
off-limits. Because "reads combat" sounds alarming, the README's principles say exactly
what is checked and why. The `forbidden-apis` allow-list for `Sync.lua` widens only
when the sync implementation lands, citing this entry.

*Rejected:*
- **Sending during fights:** extra traffic while players least want it, and Midnight-era
  rules may block addon messages in encounters anyway.
- **Not telling players:** the check is harmless, but a silent one looks like a hidden
  combat reader to anyone reading the code.

*Reflected in:* `README.md` → Principles; `docs/security-checklist.md` → Expected future
exceptions.

### 2026-09-26 — Security checks: forbidden-API guard on every PR, review before every release

A required CI job (`forbidden-apis`, `scripts/check-apis.sh`) greps shipped code for
forbidden APIs:
- dynamic code
- global lookup by name (`_G`)
- combat data
- chat and social sending
- hooks
- macros and key bindings
- selecting gossip options (picking one for the player could reset their hearthstone)
- account and group actions
- addon messaging and chat channels outside `Sync.lua`

A name matches after `.` or `:` too, so a cached namespace alias is caught. The check
fails closed on unreadable or oddly named files.

Widening an allow-list needs a decision entry. Every `dev → main` release PR also gets a
security review of the release diff against `docs/security-checklist.md`, with the
results in the PR. Until launch the session fixes findings and merges on its own, and a
finding that needs a maintainer decision stops the release (the maintainer chose this).
Workflows pin actions by commit SHA and use read-only, unpersisted tokens.

*Rejected:*
- **Only reviewing at release time:** problems would already be on `dev`, and a grep
  costs nothing per PR.
- **CodeQL or dependency scanners:** no Lua support; no package dependencies.
- **A third-party secret scanner:** GitHub secret scanning with push protection is
  already on.
- **A maintainer sign-off on every release:** not needed before there are players.
- **Inline exemptions in code:** they'd hide allow-list changes from review.

*Reflected in:* `docs/security-checklist.md`; `CLAUDE.md` → Branch flow; `.github/workflows/`;
`docs/architecture.md` → Security model (pointer).

### 2026-09-26 — CI: own toolchain install, and the library manifest pinned to the review doc

`ci.yml` runs `luacheck`, `busted` (Lua 5.1) and `libs-manifest` as separate jobs on
every push and PR. All three are required checks on `main` and `dev`, next to the
policy guard. The toolchain comes from apt and luarocks.org at the local versions. The
only action is `actions/checkout`. The token is read-only and isn't persisted, because
luarocks build scripts run as root. `scripts/check-libs.sh` now also requires the
manifest's library hashes (all but `Libs/embeds.xml`) to equal `docs/libraries.md` →
*Reviewed files*. Changing, adding or removing a library therefore means editing the
review record too.
*Rejected:*
- **Third-party Lua setup actions:** more outside code to trust in CI.
- **One combined job:** the required checks would be less specific.
- **The manifest alone as the source of truth:** a PR could edit a library and its
  manifest line together and pass, which the #9 review found.
- **Pinning each doc line to its `Libs/` path:** the upstream paths differ from the
  vendored ones, so the doc would need a third column. Comparing hashes already keeps
  unreviewed bytes out.
- **Covering `embeds.xml` in the check:** it's our file, so PR review covers it, like
  `Core.lua`.

*Reflected in:* `.github/workflows/ci.yml`; `docs/libraries.md` → Vendoring and upgrades;
`CLAUDE.md` → Testing; branch protection.

### 2026-09-26 — Scaffold conventions: embeds.xml in the manifest, pure modules enforced twice

`Libs/embeds.xml` (ours; sets the library load order) is listed in `Libs/MANIFEST.sha256`
like the vendored files. Pure and data modules are checked twice: a strict plain-Lua
environment in the specs (load time) and a `pure` luacheck std with only plain-Lua names
(function bodies too). Pure modules get libraries as arguments too, so `Export` takes
the serializer and compressor from its glue caller instead of calling `LibStub`.
*Rejected:* an allow-list of extra files in `check-libs.sh` (one more rule to keep
strict, and edits to the load order would go unnoticed); relying on the spec
environment alone (it misses globals used inside functions, which the review showed);
letting `Export` call `LibStub` (breaks the pure/glue line and needs the WoW stub in its
tests).
*Reflected in:* `docs/libraries.md` → Vendoring and upgrades; `docs/architecture.md` →
Modules, Testing posture; `.luacheckrc`.

### 2026-09-26 — Work is queued as GitHub issues written for a cold start

Tickets are GitHub issues with fixed sections (Goal, Read first, Already decided, Scope,
Done when, Start here, Gates and dependencies). They link doc sections instead of
copying them. A session stopping mid-ticket posts a handoff comment. Only the repo
owner's text in an issue counts as instructions. Merges into `dev` don't auto-close
issues, so tickets are closed by hand with evidence.
*Rejected:* to-do lists inside `status.md` (they mix a snapshot with a queue and lose
per-item history); tickets that paste context in full (the copies go stale when docs
change); a project board (overhead with no gain for a single maintainer; labels and a
milestone cover it); trusting all issue comments (the repo is public, so anyone could
plant instructions).
*Reflected in:* `CLAUDE.md` → Tickets; `.github/ISSUE_TEMPLATE/`.

### 2026-09-26 — Vendor a reviewed, minimal set of libraries

Libraries are committed under `Libs/` at exact reviewed versions (Ace3 Release-r1403
parts, ChatThrottleLib, LibDeflate 1.0.2), with a sha256 manifest checked in CI. Only the
parts we use are included.
*Rejected:* fetching the latest at package time through packager externals (what ships
would differ from what was reviewed); the whole Ace3 bundle (more code to trust than we
use); AceComm and AceGUI (see the sync transport entry; the UI is custom frames).
*Reflected in:* `docs/libraries.md`; `CLAUDE.md` → Stack.

### 2026-09-26 — Sync: own receive handler and codec, single messages, no compression

`Sync` receives addon messages itself with a byte cap and sends through ChatThrottleLib.
Every message fits in one addon message. `SyncProtocol` uses its own fixed text format.
Nothing received is compressed or run through a general-purpose deserializer. Signer
and name aren't sent; they come from the resolved sender. Numeric fields must be finite
integers in range. The review behind this is in `docs/libraries.md` → Findings.
*Rejected:* receiving through AceComm (it buffers multi-part messages without a size
limit before we can reject them); AceSerializer for peer data (it yields `NaN`, `inf`,
floats and extra values, and it's a shared library another AddOn can replace at
runtime); compressing sync payloads (a 722:1 decompression bomb was demonstrated, and
entries are too small to benefit); sending signer and name (they're redundant under the
own-signature rule and add a forgery surface).
*Reflected in:* `docs/architecture.md` → Sync protocol, Security model, Data model.
Supersedes the AceComm transport and "decode inside pcall with size caps" wording in
the architecture's original sketch.

### 2026-09-26 — Export uses standard base64

The export payload is AceSerializer → LibDeflate `CompressDeflate` → standard base64
(RFC 4648), with our own encoder.
*Rejected:* LibDeflate `EncodeForPrint` (a custom 6-bit alphabet that outside tools
can't decode with stock libraries, and its header credits GPLv2-licensed code).
*Reflected in:* `docs/export-format.md` → Envelope; `docs/architecture.md` → Export.

### 2026-09-26 — Sender identity is resolved per channel; unresolved senders are dropped

The own-signature rule needs the sender's GUID, but addon messages carry only a name.
`Sync` resolves it per channel: `UnitGUID(sender)` for PARTY/RAID and a roster-built
name → GUID map for GUILD. Other channels aren't accepted in v1. If the sender can't be
resolved, the message is dropped, and `entry.name` must match the resolved sender.
*Rejected:* trusting the payload's `signer` (forgeable by anyone); matching by name alone
(names change and can be reused, while GUIDs are stable); digital signatures on entries (no
way to bind a key to a character in-game, so they prove nothing the client can't already
tell us); retrying or queuing unresolved senders (complexity for little gain, since the
next HELLO resyncs).
*Reflected in:* `docs/architecture.md` → Security model; `docs/platform-forever.md` →
Verification checklist.

### 2026-09-26 — Branch protection on `main` and `dev` (supersedes part of the branch-flow entry below)

Both branches are protected with admins included: PRs only, the CI check required, no
force-pushes, no deletion, and no required approving review, since there's a single
maintainer. `dev` also requires linear history (squash merges). Release PRs into `main`
use a merge commit. `main` then sits a merge commit ahead of `dev` with identical
content, which is expected. This replaces the "Rejected: branch protection rules" line
in the branch-flow entry below.
*Rejected:* requiring an approving review (a single maintainer can't approve their own
PRs, so it would block everything); exempting admins (makes the rules optional);
squash-merging release PRs (`main` and `dev` histories would diverge); requiring
release branches to be up to date with `main` (`dev` could only catch up through a
merge commit, which its linear-history rule forbids).
*Reflected in:* `CLAUDE.md` → Branch flow; `CONTRIBUTING.md` → Branches and pull
requests.

### 2026-09-26 — Context docs as a map-driven tree

`CLAUDE.md` carries a Context map (doc / holds / read when) in place of a fixed reading
list. Running status moved out of `kickoff.md` into a new `docs/status.md` that every
session reads first and rewrites at the end. Every doc opens with a Summary / Read-when
header. This file stays the decision log, newest first. Each fact has one home; other
docs link to it.
*Rejected:* keeping status inside `kickoff.md` (a bootstrap-only runbook shouldn't hold
running state, and it gets archived after v1); a separate `decision-log.md` (this file
already is one, and renaming would break links); reading every doc each session (costly,
and it doesn't scale as specs accumulate).
*Reflected in:* `CLAUDE.md` → Context map; `docs/status.md`; `docs/kickoff.md`.

### 2026-09-26 — Autonomous build loop with maintainer gates

Specs are self-approved, and agents test, iterate until green, merge and report with
evidence. Work stops only for the maintainer gates: product decisions (scope, design,
naming), spending money, irreversible or public actions (publishing, tagging, posting,
deleting, force-pushing) and in-client verification. Those questions are batched in
`status.md` while other work continues. Kickoff step 1 becomes a report, not a wait.
*Rejected:* a human approval on every spec and a sign-off on every merge (it serializes
work on the maintainer ahead of a fixed launch window; the gates that matter are kept).
*Reflected in:* `CLAUDE.md` → Build loop; `docs/kickoff.md` → Sequence.

### 2026-09-26 — Test standard: busted + stubbed WoW API, hostile peer data

Pure logic runs under `busted` outside the game, with client calls behind a stubbed WoW
API layer. Tests treat all peer data as hostile (malformed, oversized, relayed, replayed,
forged signer, unknown IDs, compression bombs). `luacheck` must be clean. CI runs both
next to the policy guard. Anything that truly needs the client is listed for the
maintainer instead of blocking work.
*Rejected:* testing only in the client (slow, manual, and it can't cover malicious
input); browser/e2e tooling (doesn't apply to an in-game AddOn).
*Reflected in:* `CLAUDE.md` → Testing; `docs/architecture.md` → Testing posture.

### 2026-09-26 — Branch flow: feature branches → dev → main

`dev` is the integration branch. Work happens on `feat/`, `fix/`, `chore/` and `docs/`
branches from `dev`, squash-merged once green. `main` stays the default branch and
changes only through `dev → main` release PRs. Tags and published releases go out only
through the packager and are a maintainer gate. CI runs on `dev` as well as PRs.
*Rejected:* committing straight to `main` (no integration line ahead of releases);
branch protection rules (not configured; CI and discipline enforce the flow for now).
*Reflected in:* `CLAUDE.md` → Branch flow.

### 2026-09-26 — No spending without a named purchase; free beta route by default

Nothing that costs money is bought or enabled on the project's behalf unless the
maintainer names that purchase. Packaging, distribution and CI stay on free tiers. Beta
access defaults to the free opt-in; the paid pre-purchase route is the maintainer's call
alone.
*Rejected:* buying a higher-tier edition to guarantee beta access (a spending decision
only the maintainer can make; the no-beta plan still ships ~1–2 weeks after launch).
*Reflected in:* `CLAUDE.md` → Hard rules; `docs/status.md` → Client access plan.

---

### 2026-09-25 — Seed decisions (archived)

The first product decisions are in
[archive/decisions-2026-09.md](archive/decisions-2026-09.md), unchanged and still in
force. Titles, for references that cite them by name:

- Target WoW: Forever first
- Inns only in v1
- Canned phrases, not free text
- Sync scope: grouped-with + guild by default; global opt-in
- Accept only a sender's own signatures
- Cosmetics are earned by play, never paid or gated
- Generic, documented export string
- Open source under MIT
