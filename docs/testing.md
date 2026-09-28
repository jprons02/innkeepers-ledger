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
- **Long simulations are tagged `#sim`** (the 40-player raid, an hour in a guild, the
  10-minute flood). `busted` runs them (about 10 s); the coverage run skips them with
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
- **CI:** every check runs on every push and PR, and each has a local command
  ([CONTRIBUTING.md → Development setup](../CONTRIBUTING.md#development-setup)). Pure
  modules have coverage floors (95% for `Ledger`, `SyncProtocol`, `SyncSchedule`; 90% the rest).
