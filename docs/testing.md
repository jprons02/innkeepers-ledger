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
  **Frames** (for `Sign`, [specs/sign.md §6.1](specs/sign.md#61-stub-and-helpers)):
  `CreateFrame(kind, name, parent, template)` records `kind`, `parent` and `template`
  (a hidden parent doesn't hide its children); frames have a real `Show` / `Hide` /
  `IsShown`, recorded `SetPoint` (`frame.points`), sizes and text, `Enable` / `Disable`,
  `Click()` (runs `OnClick` when enabled), `CreateFontString` and `CreateTexture`
  (`SetColorTexture` lands in `.color`). `GossipFrame` is a stub frame; set it to `nil`
  for a client without one. `wow.children(parent)` lists the frames made under a parent.
  `UnitGUID("npc")` is `nil` unless a case overrides `UnitGUID`.
- **Sign** (`spec/sign_flow_spec.lua`, pure; `spec/sign_spec.lua`, the glue): the pure
  cases build flows over the place fixtures, the phrase fixture of
  [specs/phrase.md §6](specs/phrase.md#6-test-plan) and a real `Ledger`, plus the real
  data for the draft; NPC GUIDs are `"Creature-0-4615-2991-62-<id>-0000ABCDEF"`. The glue
  cases log in at Coriella Calmbreeze (`254089`), resting, and drive the button and the
  composer through `Sign.ui` (`button`, `composer`, `lists.<voice|conj|template|cat|word>`
  with `frame`, `rows[i].button/text/mark`, `prev`, `next`; `line1`, `line2`,
  `rows.seal.prev/label/next`, `toggle`, `sign`, `cancel`, `preview`, `title`, `inn`) and
  `Sign.session`. The mouse wheel is driven by calling a list frame's
  `scripts.OnMouseWheel(frame, delta)`; the stub records `EnableMouseWheel` as
  `frame.mouseWheel`.
- **The book** (`spec/book_view_spec.lua`, pure; `spec/book_spec.lua`, the glue;
  [specs/book.md §6](specs/book.md#6-test-plan)): the pure cases build views over the
  place fixtures, the phrase fixture and catalog C (plus quills where a case needs five),
  real `Ledger`s and fake ledgers that return hostile or oversized answers; `sizes` shrinks
  the page sizes to exercise paging. A spy on the strict environment's `rawget` counts the
  read caps. The glue cases log in at Coriella Calmbreeze with `date` and `time` stubbed to
  a fixed UTC offset (so dates don't follow the machine's time zone), and drive the book
  through `Book.ui` (`frame`, `tabs`, `close`, `left` / `right` = `{ prev, next, label,
  error }`, `title`, `help`, `list.rows`, `inn`, `summary`, `stamps.cells`, `quills.rows`,
  `seals.rows`, `share = { edit, check, nudge, fail }`, `notice`), `Book.nav`,
  `Book.model` and `Book.view`. **Stub additions for it:** a named `CreateFrame` also sets
  the global; `EditBox` (text, focus, `HighlightText` recorded, max letters and bytes) and
  `CheckButton` (`GetChecked` a boolean, `Click()` toggles then runs `OnClick`);
  `wow.type(edit, text)` runs `OnTextChanged(self, true)`; `Hide` runs `OnHide`; font
  strings record `SetFontObject`, `SetTextColor`, `SetShadowOffset`; textures record
  `SetTexture` (set `wow.textureResult = false` for a file the client can't find);
  `ClearAllPoints`; and the globals `UIParent`, `UISpecialFrames`, the `GameFont*` and
  `QuestTitleFont` objects, `date` and `time`, each settable to `nil` per case.
- **Layout (#140):** `wow.rect(region)` resolves anchors the way the client does and
  returns left, bottom, width, height, or `nil` when it can't (no points, no size, a bad
  point, an anchor cycle). `UIParent` is the screen, 1024 × 768. It handles `SetPoint`
  with any of the nine points, offsets, a region, a global name or the parent (the
  default), `SetAllPoints`, `SetSize` / `SetWidth` / `SetHeight`, and two points on an axis
  (a stretch sets the size). `SetPoint` replaces a point of the same name, as the client
  does. Font strings and textures know their `parent`. A font string with no set width
  is as wide as its text, and with no set height as high as its lines. Text width is an
  estimate: characters × font size × 0.6 (`wow.FONT_SIZES`, `wow.TEXT_EM`). The game fonts
  average about 0.5 em, so the estimate is conservative: text that passes fits, and text
  it flags may still just fit in the client. Not modeled: scale, clamping to the screen
  and real font metrics. `spec/helpers/layout.lua` holds the checks, each returning a
  list of problems with the numbers: every shown region (shown with all its parents)
  resolves, stays inside its parent, overlaps nothing but its own parents and backdrops,
  and its text fits. `spec/layout_spec.lua` runs them over
  every page of every tab of the book (an empty ledger and a full one, with an atlas of
  38 extra inns) and the composer (every voice's templates, every category's words, the
  seal row, the preview at its cap). Each exception is listed in the spec with its
  reason, and each check has a case showing it fails on a broken layout. Problems found
  in the current UI are `pending` cases under "Layout: known problems" (the look is a
  DRAFT); the other cases skip only those.
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
  stub overrides. The cases live in `spec/sync_names_spec.lua`. Our own name is read
  through `UnitFullName("player")` first (`Sync.readOwnName`, `UnitName` only when it's
  missing), so a test that changes the player's name stubs both, or it tests nothing.
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
  10-minute flood, the large export size rows, the `cleanText` sweep over every code point
  of planes 0 and 1). `busted` runs them (about 10 s); the coverage run skips them with
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
- **Test by hand in the client:** signing flow (the checks of
  [specs/sign.md §8](specs/sign.md#8-in-client-checks-for-12)), gossip integration, UI, real
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
  the character's name). Since 2026-10-05 the probe adds no gossip button of its own (it
  stacked on the real "Sign the guestbook" button); it still logs every NPC, and an
  innkeeper is the one whose options include *Make this inn your home.* (icon 132052).
  **The client's copy goes stale:** before reading a screenshot, compare each file the
  TOC loads, plus `Libs/`, against the client's copy (`cmp`). Re-copy after each merge.
  On 2026-10-09 the copy was 3 days old, so screenshots showed code from before #102 and
  #110.
- **Refreshing the AddOn in the client after a merge:** the installed
  `Interface/AddOns/InnkeepersLedger` is a plain copy, not a link. Copy `Libs`, `Data`,
  `UI`, every top-level `*.lua` and the TOC from `dev` over it (what `install.sh` does,
  without touching the probe), then `diff -rq` it against the repo. Changed files load
  on `/reload`; a new file in the TOC needs a full client restart. The game never reads
  GitHub, so `dev` code is testable in the beta without a release.
- **CI:** every check runs on every push and PR, and each has a local command
  ([CONTRIBUTING.md → Development setup](../CONTRIBUTING.md#development-setup)). Pure
  modules have coverage floors (95% for `Ledger`, `SyncProtocol`, `SyncSchedule`; 90% the
  rest, `SignFlow` and `BookView` included).
