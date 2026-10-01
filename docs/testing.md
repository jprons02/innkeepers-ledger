# Testing

> **Summary:** how the AddOn is tested: what gets tested hard, the module pattern and
> strict environment, the WoW stub, hostile-peer-data tests, coverage floors, and what
> waits for the client.
> **Read when:** writing or reviewing tests; changing `spec/helpers/`, `.luacheckrc`, CI or
> a coverage floor; a test won't run.

Moved out of [architecture.md](architecture.md) on 2026-09-27 when that file hit 200
lines. Local commands: [CONTRIBUTING.md → Development setup](../CONTRIBUTING.md#development-setup).

## Testing posture

Proportional, not ceremonial:

- **Test hard (busted, test-as-you-go):** `SyncProtocol` validation (every rule in
  [architecture.md → Security model](architecture.md#security-model--the-riskiest-part-of-the-addon)
  with malicious-input cases), `SyncSchedule` send bounds and wake times, `Ledger`
  dedupe/caps/eviction, `Collection` math, `Phrase` validation, `Export` encode/decode
  round-trip.
- **Stubbed WoW API.** Pure modules take client values as arguments; any glue exercised
  in tests goes through a small stub layer of the WoW API, so `busted` runs outside the
  game.
- **Module pattern.** Every file starts `local _, ns = ...` and assigns `ns.<Module>`
  (data goes under `ns.Data`). `spec/helpers/load.lua` runs a file with a fresh `ns`, as
  the client does. Pure modules load in a strict plain-Lua environment that errors on
  any other global, which catches access at load time; `.luacheckrc` gives pure and
  data files only those same plain-Lua names, which catches it inside functions too
  (`_G`, `os`, `io` and every WoW global included). The helper also holds the module
  lists (`PURE`, `DATA`, `GLUE`; specs check them against the TOC and `.luacheckrc`)
  and can load the whole AddOn in TOC order (libraries included).
- **The stub** (`spec/helpers/wow_stub.lua`): `install(overrides)` / `uninstall()`
  (restores `_G`), `fire(event, ...)`, `slash("/cmd")`, a settable clock (`wow.now`,
  `wow.advance(s)` runs timers as they fall due), plus recorded chat output, sent addon
  messages, queued timers and errors the libraries catch. It supplies the client's
  `xpcall`, which passes extra arguments to the function; stock Lua 5.1's drops them,
  and Ace3 then calls `OnInitialize` without `self` and swallows the error.
- **The sync harness** (`spec/helpers/sync_harness.lua`): N `Sync` clients in one Lua
  state, each with its own `ns`, ledger, GUID and fake `api` (no stub, no `_G`), sharing
  a clock, a timer queue, an addon-message bus that echoes to the sender, and the group
  and guild lists behind the unit functions (`UnitGUID`, `UnitFullName`, `UnitName`),
  the group calls and the roster. `c.tokens` makes `UnitGUID` answer unit tokens like
  `target` in any case, as the client does, so a test can play a member named like one. `c.impl.X` replaces
  one client function, `c.calls.X` counts its calls, `c.secret(v)` is the client's
  `issecretvalue`. Fixture inns, phrases and seals stand in for the empty `Data` tables.
  For the send side: `c.sendMode` (`"sync"`, `"defer"` by `c.sendDelay` s, `"fail"`),
  `w.sent` (every message handed over), `c.inCombat` and `harness.combat(c, on)`,
  `c.groupArgs` (the group calls' argument) and `w:timersOf(c)`. The send cases and the
  end-to-end runs live in `spec/sync_send_spec.lua`; the receive cases in
  `spec/sync_spec.lua`.
- **Forever names** (two-part `"First Surname"` names, the surname in the realm slot;
  [platform-forever.md](platform-forever.md)): `harness.new({ forever = true })` and
  `harness.twoPart(name, guid)` in the harness, `wow.foreverNames(first, surname)` as
  stub overrides. The cases live in `spec/sync_names_spec.lua`.
- **Place fixtures** (`spec/helpers/places.lua`): the fixture places, own entries and
  catalog of [specs/collection-cosmetics.md §6](specs/collection-cosmetics.md#6-test-plan),
  the two hidden-value stand-ins, a raw snapshot (nothing written) and a seeded shuffle,
  shared by `spec/collection_spec.lua` and `spec/cosmetics_spec.lua`. A hand-built place
  table keeps zone keys apart from continent keys (zones 10, 11, … or 1001.., continents
  1, 2): a key in both is excluded with everything under it
  ([§3.2 rule 6](specs/collection-cosmetics.md#32-record-rules)), so a test that doesn't
  assert `invalid` empty can pass on an empty atlas (#76 caught two).
- **Export helpers** ([specs/export.md §3.8](specs/export.md#38-the-test-only-decoder)):
  `spec/helpers/export_libs.lua` loads the real vendored LibStub, AceSerializer-3.0 and
  LibDeflate into a private environment (standard library names only; no `LibStub`
  global leaks), with a codec built as `Core` builds it. `spec/helpers/export_decode.lua`
  is the test-only decoder (strict base64, raw inflate, deserialize, size caps) and
  `schemaOk`, the v1 schema check that every export test runs on every build result and
  every decoded string. No decoder ships; `scripts/check-apis.sh` keeps it that way.
- **Long simulations are tagged `#sim`** (the 40-player raid, an hour in a guild, the
  10-minute flood, the large export size rows). `busted` runs them (about 10 s); the coverage run skips them with
  `--exclude-tags=sim`, since under luacov they take minutes and cover no pure-module
  line the module specs don't.
- **Peer data is hostile in tests.** For every rule in the security model, cover
  malformed, oversized and multi-part messages (dropped unread), relayed (third-party),
  replayed and forged-signer input, unknown inn/phrase IDs, `NaN`/`inf`/hex/decimal
  numbers, out-of-range timestamps, and floods over the rate limit.
- **Beyond the spec's cases, for security-level reviews:** seeded random fuzz over hours
  of simulated time, checking invariants every step (nothing throws, the budgets hold
  in any 60 s, pending state stays bounded, only our own texts go out), and mutants of
  the key rules. For anything that returns a wake time, a **differential**: one driver
  pumps every second, another only at the returned wake (or `now + 1` after an input);
  their send logs must match. That is how #45's review found a wake time that was too
  late, which every named test had missed.
- **Lint:** `luacheck` clean.
- **Test by hand in the client:** signing flow, gossip integration, UI, real
  addon messages between two accounts/characters. These go on the in-client batch in
  [status.md](status.md) rather than blocking other work.
- **The in-client probe (#12):** a throwaway AddOn, `!ILProbe`, on branch
  `spike/12-probe`, never merged. `sh spike/probe/install.sh "<client folder>"` copies
  it, plus the working-tree AddOn with the TOC's interface number, into the client's
  `Interface/AddOns`. A new AddOn folder needs a full client restart. In game, `/ilp`
  runs every automatic check; talking to any NPC records its GUID, gossip and map chain;
  every addon message, rest-state change and Lua error is logged too. `/reload` or
  logging out writes the log to
  `WTF/Account/<account>/SavedVariables/!ILProbe.lua`, which a session reads straight
  from disk. Extend the probe on that branch when a new client question comes up; the
  results go into [platform-forever.md](platform-forever.md), never the raw log (it holds
  the character's name).
- **CI:** every check runs on every push and PR, and each has a local command
  ([CONTRIBUTING.md → Development setup](../CONTRIBUTING.md#development-setup)). Pure
  modules have coverage floors (95% for `Ledger`, `SyncProtocol`, `SyncSchedule`; 90% the rest).
