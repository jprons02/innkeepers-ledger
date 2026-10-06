# Architecture

> **Summary:** how the AddOn is built: modules (pure vs glue), signing flow, data model,
> sync protocol, the security model for peer data, export, game flavors. Testing lives in
> [testing.md](testing.md).
> **Read when:** writing or reviewing any code, especially sync, validation, storage caps
> or a new module.

How Innkeeper's Ledger is built. Decisions referenced here live in
[decisions.md](decisions.md). Anything marked **(verify)** depends on client behavior
that hasn't been confirmed in WoW: Forever yet (see
[platform-forever.md](platform-forever.md)).

## Shape

A pure client-side Lua AddOn. No server, no database, no network. State lives in
SavedVariables. Players' AddOns exchange data only through in-game addon messages
while they're online together.

## Modules

Split along one line: **pure logic** (no WoW API calls, unit-testable with `busted`)
vs **client glue** (events, frames, API calls).

| Module | Kind | Responsibility |
|---|---|---|
| `Core` | glue | AceAddon setup, AceDB SavedVariables, slash command, wiring |
| `Data/Inns` | data | Innkeeper NPC ID → inn record (name, zone, faction) or alias of one; zones and continents keyed by the client's map IDs, each zone with its seal ID ([spec](specs/collection-cosmetics.md#31-places-inns-zones-continents)). One table per game flavor. |
| `Data/Phrases` | data | Phrase templates + word lists, each with a stable numeric ID; templates and conjunctions grouped into voices (UI only) |
| `Data/Cosmetics` | data | The cosmetic catalog: milestone seals and quills, each with a stable numeric ID and its unlock rule ([spec](specs/collection-cosmetics.md#35-cosmetic-ids)) |
| `Sign` | glue | The "Sign the guestbook" button under the gossip frame, the phrase composer, the client reads (hidden-value checked), chat lines, `Sync:WindowChanged()` after a signature ([spec](specs/sign.md)) |
| `SignFlow` | pure | Every signing decision: when to offer signing, the checks and their reasons, the seals a signature may carry, the commit (`addOwn`, then unlocks recorded), the composer's state ([spec](specs/sign.md)) |
| `Ledger` | pure | The entry store: add, dedupe, query by inn/signer, prune, storage caps |
| `Phrase` | pure | Builds, renders and validates phrase IDs → text ([spec](specs/phrase.md)) |
| `Collection` | pure | Progress over your own signatures: signed/total by continent and zone, per inn ([spec](specs/collection-cosmetics.md)) |
| `Cosmetics` | pure | The catalog, unlocked quills and seals and when each was earned, `SEALS` for peer validation, the seal check on signing ([spec](specs/collection-cosmetics.md)) |
| `SyncProtocol` | pure | Own fixed-format message codec, digest comparison, **all validation** |
| `SyncSchedule` | pure | What `Sync` sends and when: send budget, HELLO / WANT / reply gates, pending queues, combat hold state, the pump ([spec](specs/sync-glue.md#35-send-path-syncschedule)) |
| `Sync` | glue | Addon-message transport (own receive handler, ChatThrottleLib to send), sender → GUID resolution, group/guild triggers, the pump that drives `SyncSchedule`, the combat hold ([spec](specs/sync-glue.md)) |
| `Export` | pure | Builds the v1 export table, then serialize + compress + base64 per [export-format.md](export-format.md) ([spec](specs/export.md)) |
| `UI/Book` | glue | The parchment book: pages per inn, collection view, cosmetics |

Pure modules receive anything they'd get from the client (time, GUIDs, inn data) as
arguments, so tests don't need a WoW stub. That includes libraries: `Export` can't call
`LibStub`, so its caller (glue) passes in the serializer and compressor.

## Signing flow

1. On `GOSSIP_SHOW`, read `UnitGUID("npc")` and parse the NPC ID from the creature
   GUID. NPC IDs don't depend on the client's language, whereas zone/subzone names
   differ in every locale, so **never match inns by name**.
2. If the NPC ID is in `Data/Inns` for the current flavor (and `Collection` kept the
   record), a "Sign the guestbook" button shows under the gossip frame (verified in the
   beta: a `UIPanelButtonTemplate` button parented to `GossipFrame`). It shows at every
   known innkeeper; a click that can't sign says why in one chat line (no ledger,
   read-only, signed this week, not resting).
3. The player composes a phrase in the composer (arrow cyclers over a voice per line,
   templates, categories, words and conjunctions, an optional second line and an optional
   seal) and confirms. No recent phrases in v1.
4. Conditions: `IsResting()` must be exactly `true`, and the ledger's weekly rule must
   allow the inn. There is no sitting requirement: the client has no query for it
   ([platform-forever.md](platform-forever.md) → *Sitting detection*).
5. Every check runs again at confirm, then the entry is stored through `Ledger:addOwn`,
   new unlocks are recorded in `earned`, and `Sync:WindowChanged()` announces it.
   `Core` also records unlocks once at login. Details: [specs/sign.md](specs/sign.md).

## Data model

```
Entry {
  inn      : innkeeper NPC ID (int)         -- identifies the inn
  t        : server time of signing, GetServerTime() (int)
  phrase   : array of phrase/word IDs (ints)
  seal     : seal ID from Cosmetics.SEALS used when signing (int 1..999, optional)
}
-- held per signer: signer = player GUID (identity), name = display only
```

- **Stored vs sent:** entries are stored per signer GUID (the traveler record holds the
  name), and the schema version lives on the ledger, not on each entry. On the wire,
  `signer` and `name` are never sent; the receiver fills them in from the resolved sender.
- **Identity/dedupe key:** `(signer, inn, t)`. Own entries are the ledger owner's.
- **Storage caps:** foreign entries capped in total, per signer and per inn, oldest
  evicted first; own entries never evicted. Numbers, SavedVariables shape and migration:
  [specs/sync-ledger.md](specs/sync-ledger.md) §4.

## Sync protocol (SyncProtocol + Sync)

Transport: addon messages, prefix `InnLedger` (≤16 chars). Channels: `PARTY`/`RAID` and
`GUILD`; the global opt-in channel is designed later.

- **Sending:** through ChatThrottleLib at `BULK`, which keeps us under the server's rate
  limits, within `SyncSchedule`'s send budget (30 messages / 60 entries in any 60 s).
  Nothing is sent during combat: `Sync` is the one file allowed to read *whether* we're in
  combat, never combat data ([specs/sync-glue.md](specs/sync-glue.md) §3.5–3.7).
- **Receiving:** `Sync` registers the prefix itself and handles `CHAT_MSG_ADDON`
  directly. It does **not** receive through AceComm, which reassembles multi-part
  messages with no size limit before we could reject them
  ([libraries.md → Findings](libraries.md#findings-that-shape-our-design)).
- **One message per payload:** every message fits in a single addon message (255 bytes,
  **verify** on Forever). Anything longer, or anything multi-part, is dropped unread.
  Batches are several single messages, never one long one.
- **Own codec, no compression:** `SyncProtocol` encodes and decodes a small fixed text
  format of its own, parsed with strict patterns. No AceSerializer and no LibDeflate on
  anything received, so there is no general-purpose deserializer and no decompression of
  peer data. Entries are tiny, so compression buys nothing.
- **Signer and name aren't sent.** Under the own-signature rule they are always the
  sender, so the receiver fills them in from the resolved sender (below). The wire entry
  carries only `inn`, `t`, `phrase` and `seal`; the message header carries the version.

Three messages (grammar, digest, byte counts and rate limits:
[specs/sync-ledger.md](specs/sync-ledger.md) §3 and §5):

1. **HELLO** — on group join/roster change, or periodically for guild: count + digest
   of *your own* newest entries.
2. **WANT** — a peer whose digest for you differs asks for your entries since a time.
3. **ENTRIES** — broadcast reply with your own entries only, up to 5 per message, each
   message complete on its own.

### Security model — the riskiest part of the AddOn

Every byte from another player is **untrusted**. They may be running a modified
AddOn. `SyncProtocol` validates everything before anything reaches `Ledger`:

- **Own-signature rule:** an entry's `signer` is always the **sender's GUID** as resolved
  by the client, never a claim in the payload (the payload doesn't carry one).
  (Decision: [decisions.md](decisions.md).) Addon messages carry only the sender's
  *name*, so `Sync` resolves name → GUID per channel and passes the result to
  `SyncProtocol` as an argument:
  - **PARTY / RAID:** a name → GUID map built from our own `player` / `partyN` /
    `raidN` scan, so a peer string never reaches a client function (a character named
    like a unit token can't borrow our target's GUID). Only current group members
    resolve; a miss rescans the map at most once per 10 s (decisions: *Group senders
    resolve through our own unit scan*, *Group map details*; spec
    [sync-glue.md §3.4](specs/sync-glue.md#34-sender-resolution)).
  - **GUILD:** a name → GUID map built from the guild roster and refreshed on roster
    updates **(verify: the roster exposes member GUIDs in Forever)**.
  - **Any other channel (whisper, a future global channel):** not accepted in v1.
  - **Unresolved sender** (left the group, not in the roster yet, lookup returns nil):
    drop the message. No retry and no fallback.
  - The entry's `name` is the resolved sender's name in one form per character:
    `"Name-Realm"` on retail, the bare `"First Surname"` on Forever. Which form applies
    is read from our own player unit, never from a peer (decisions: *Two-part names key
    as the bare sender form*).
- **Size first:** drop any message over the byte cap or with a multi-part marker before
  parsing it.
- **Schema:** exact field count and order, known version, bounded array lengths,
  nothing extra.
- **Numbers:** every numeric field must be a **finite integer within its range** (reject
  `NaN`, `inf`, hex, decimals, signs where not allowed). `NaN` fails every comparison, so
  range checks alone don't catch it.
- **Known IDs only:** `inn` must exist in `Data/Inns`, every phrase/word ID must
  exist in `Data/Phrases`, and a `seal` must be a key of `Cosmetics.SEALS` (every seal
  the catalog knows, unlocked or not). Canned phrases make this a lookup table, not a
  text filter.
- **Name:** length-capped and matched against the character name pattern (no `|`, so no
  UI escape codes); it's rendered only as text, never interpreted.
- **Time sanity:** reject timestamps in the future (small tolerance) or before the
  Forever beta began.
- **Rate limits:** per-sender messages and entries per minute, plus a global ceiling.
  Drop anything over the limit silently. (All numbers: the slice-1 spec.)
- **Fail closed and quiet:** malformed input is dropped with no error pop-ups and no
  chat output. Only a debug log, when enabled. Parsing runs inside `pcall`.
- **Threat model:** other players are untrusted. The player's own installed AddOns are
  trusted (they can already do anything in-game), but a shared library may be replaced
  at runtime by another AddOn's newer copy, so security-relevant parsing lives in our
  own modules only.

How these rules are checked (CI and the release review):
[security-checklist.md](security-checklist.md).

## Export

See [export-format.md](export-format.md) (v1) and [specs/export.md](specs/export.md).
Pipeline: `Export.build` (validated, fresh data table) → AceSerializer `Serialize` →
LibDeflate `CompressDeflate` (raw DEFLATE) → our own standard base64 → `!IL1!…`, all on
our own outgoing data. `Export` is pure: the glue passes the serializer and compressor
in. **`Core:ExportString(includeTravelers)` is the one glue entry** the Share window and
`/ledger share` will call (both arrive with the UI slice; `/ledger` handles only `debug`
today); it prints, sends and writes nothing. The UI shows the string in a
copyable edit box. Exporting other travelers' entries is **opt-in** per export (only
`includeTravelers == true`; they're other people's names), and the default exports only
your own signatures and collection. **No decoder or import ships;** the forbidden-API
check enforces it ([security-checklist.md](security-checklist.md#the-forbidden-api-check)).

## Game flavors

The target is WoW: Forever. The TOC may list several interface versions if the API
turns out to be shared with retail **(verify)**. `Data/Inns` is per flavor: Forever
revamps zones and adds new ones, so the inn list must come from Forever's own client
data, not from retail or Classic databases.

## Testing posture

Moved to [testing.md](testing.md): what gets tested hard, the module pattern and strict
environment, the WoW stub, hostile-peer-data tests, fuzzing, coverage floors and the
in-client batch.
