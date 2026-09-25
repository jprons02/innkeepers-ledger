# Architecture

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
| `Data/Inns` | data | Innkeeper NPC ID → inn record (inn name, zone, continent). One table per game flavor. |
| `Data/Phrases` | data | Phrase templates + word lists, each with a stable numeric ID |
| `Sign` | glue | Detects an innkeeper interaction, offers "Sign the ledger", creates the entry |
| `Ledger` | pure | The entry store: add, dedupe, query by inn/signer, prune, storage caps |
| `Phrase` | pure | Builds, renders and validates phrase IDs → text |
| `Collection` | pure | Progress math: signed/total by continent and zone, unlock thresholds |
| `Cosmetics` | pure | Maps collection progress → unlocked quills/inks/seals |
| `SyncProtocol` | pure | Message encode/decode, digest comparison, **all validation** |
| `Sync` | glue | AceComm transport, group/guild triggers, throttling |
| `Export` | pure | Serialize + compress + encode the ledger per [export-format.md](export-format.md) |
| `UI/Book` | glue | The parchment book: pages per inn, collection view, cosmetics |

Pure modules receive anything they'd get from the client (time, GUIDs, inn data) as
arguments, so tests don't need a WoW stub.

## Signing flow

1. On `GOSSIP_SHOW`, read `UnitGUID("npc")` and parse the NPC ID from the creature
   GUID. NPC IDs don't depend on the client's language, whereas zone/subzone names
   differ in every locale, so **never match inns by name**.
2. If the NPC ID is in `Data/Inns` for the current flavor, add a "Sign the ledger"
   option to the gossip frame **(verify: how gossip options can be added or overlaid
   in the Forever client)**.
3. The player composes a phrase with the phrase builder (or picks a recent one) and
   confirms.
4. Conditions: `IsResting()` must be true. "Must be sitting" is desired for the
   ritual feel **(verify: there may be no API that reports sitting; drop the
   requirement if so)**.
5. Create the entry and store it in `Ledger`.

## Data model

```
Entry {
  v        : schema version (int)
  inn      : innkeeper NPC ID (int)         -- identifies the inn
  signer   : player GUID (string)           -- "Player-<realm>-<id>"
  name     : character name at signing (string, validated)
  t        : server time of signing, GetServerTime() (int)
  phrase   : array of phrase/word IDs (ints)
  seal     : cosmetic ID used when signing (int, optional)
}
```

- **Identity/dedupe key:** `(signer, inn, t)`.
- **Own vs others:** own entries are the ones where `signer == UnitGUID("player")`.
- **Storage caps:** caps on foreign entries in total, per signer, and per inn. When a cap
  is hit, evict the oldest entries first. Own entries are never evicted. Numbers are
  set in the first spec; SavedVariables bloat is a real risk.

## Sync protocol (SyncProtocol + Sync)

Transport: AceComm (handles chunking and throttling via ChatThrottleLib).
Prefix: `InnLedger` (≤16 chars). Channels: `PARTY`/`RAID` and `GUILD`; the global
opt-in channel is designed later.

Sketch (the first spec finalizes it):

1. **HELLO** — on group join/roster change, or periodically for guild: send a compact
   digest of *your own* entries (count + hash).
2. **WANT** — a peer whose digest for you differs asks for your entries (optionally
   "since t").
3. **ENTRIES** — reply with your own entries only, batched.

### Security model — the riskiest part of the AddOn

Every byte from another player is **untrusted**. They may be running a modified
AddOn. `SyncProtocol` validates everything before anything reaches `Ledger`:

- **Own-signature rule:** accept an entry only if `entry.signer` equals the
  **sender's GUID** as resolved by the client, never trusting a claim in the payload.
  Reject everything else. (Decision: [decisions.md](decisions.md).)
- **Schema:** exact types, known version, no extra fields, bounded array lengths.
- **Known IDs only:** `inn` must exist in `Data/Inns`, and every phrase/word ID must
  exist in `Data/Phrases`. Canned phrases make this a lookup table, not a text filter.
- **Name:** length-capped and matched against the character name pattern; it's rendered
  only as text, never interpreted.
- **Time sanity:** reject timestamps in the future (small tolerance) or before the
  game's launch.
- **Rate limits:** per-sender messages per minute and entries per batch. Drop anything
  over the limit silently.
- **Fail closed and quiet:** malformed input is dropped with no error pop-ups and no
  chat output. Only a debug log, when enabled.
- **Deserialization:** use AceSerializer/LibDeflate decoding inside `pcall`, with
  size caps before decompressing (to guard against decompression bombs).

## Export

See [export-format.md](export-format.md). `Export` is pure. The UI shows the string in
a copyable edit box. Exporting other travelers' entries is **opt-in** (they're other
people's names), and the default exports only your own signatures and collection.

## Game flavors

The target is WoW: Forever. The TOC may list several interface versions if the API
turns out to be shared with retail **(verify)**. `Data/Inns` is per flavor: Forever
revamps zones and adds new ones, so the inn list must come from Forever's own client
data, not from retail or Classic databases.

## Testing posture

Proportional, not ceremonial:

- **Test hard (busted, test-as-you-go):** `SyncProtocol` validation (every rule above
  with malicious-input cases), `Ledger` dedupe/caps/eviction, `Collection` math,
  `Phrase` validation, `Export` round-trip.
- **Test by hand in the client:** signing flow, gossip integration, UI, real
  AceComm between two accounts/characters.
- **CI:** a policy-guard workflow exists from day one. `luacheck` + `busted` get added
  to CI once the first Lua lands (kickoff step).
