# Export format

**Status: DRAFT v0.** The first build session finalizes this and marks it v1. After v1,
changes are additive or bump the version. Never silently change the meaning of a field.

The export string lets a player take their ledger out of the game (to render it, share
it, or back it up) by copying a string from an in-game edit box. It follows the
SimulationCraft pattern. The format is public and neutral: **the AddOn never names,
links or recommends any consumer of it.**

## Envelope

```
!IL1!<payload>
```

- `!IL` marks an Innkeeper's Ledger export; `1` is the **format major version**.
- `<payload>` = the data table → serialized (AceSerializer-3.0) → compressed
  (LibDeflate `CompressDeflate`) → printable-encoded (LibDeflate `EncodeForPrint`).
- Decoders should reject unknown major versions and ignore unknown fields.

## Data (draft)

```
{
  v       = 1,                 -- schema version
  flavor  = "forever",         -- game flavor the ledger came from
  exported= <server time>,
  addon   = "<addon version>",
  me = {
    guid  = "<player GUID>",
    name  = "<character name>",
  },
  collection = {
    signed = <int>, total = <int>,
    byZone = { [<zone key>] = { signed = <int>, total = <int> }, ... },
  },
  cosmetics = { <unlocked cosmetic IDs> },
  entries = {                  -- your own signatures (always)
    { inn = <npcId>, t = <time>, phrase = { <ids> }, seal = <id> }, ...
  },
  travelers = {                -- OPTIONAL: others' signatures, only if the player opts in
    { signer = "<guid>", name = "<name>", inn = <npcId>, t = <time>, phrase = { <ids> } }, ...
  },
}
```

Phrase and inn IDs refer to the tables shipped in the AddOn (`Data/Phrases`,
`Data/Inns`). A future version of this doc should publish those tables (or a generated
JSON of them) so consumers can render text without reading Lua.

## Privacy

- By default the export contains only **your own** signatures and collection.
- `travelers` includes other players' character names and is **opt-in** per export.
- There's nothing secret in an export, but treat it as personal data.

## Trust

An export is produced by open-source code on the player's machine, so **it can be
edited or forged.** Consumers must treat it as user-supplied input: validate it, cap
sizes before decompressing, and never assume it proves anything.
