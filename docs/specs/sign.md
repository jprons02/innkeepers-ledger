# Spec: `Sign` — signing the guestbook

> **Summary:** the signing flow. A "Sign the guestbook" button under the gossip frame at
> any innkeeper in `Data/Inns`; a click checks why signing may not be possible (no ledger,
> read-only, not resting, already signed this week) or opens a plain DRAFT phrase
> composer; signing adds an own entry, records earned cosmetics and tells `Sync`. The
> decisions live in a new pure module, `SignFlow`; `Sign.lua` is thin glue. Also `Core`
> recording unlocks at login, the tests, and the in-client checks.
> **Read when:** implementing or reviewing `SignFlow.lua`, `Sign.lua` or `Core`'s unlock
> recording; changing when the button shows, what a click does, the composer or the
> signing messages.

**Status:** approved (self-approved 2026-10-05, ticket #96), **except the composer's look
and every player-facing line** in [§3.7](#37-the-composer-draft) and
[§3.8](#38-messages-draft): those are a DRAFT and the maintainer decides them (a
`CLAUDE.md` gate). They ship as written until then ([decisions.md](../decisions.md) →
*Maintainer-gated content ships as a DRAFT and doesn't block merge*). The button's label,
"Sign the guestbook", is settled (2026-10-02).
**Security-sensitive:** moderately. `Sign` reads no peer data and changes no sync or export
format, but every entry it creates is broadcast to peers, and it reads client values that
may be hidden. The reviewer checks [§5](#5-security-notes) item by item.

Builds on (changes none of them): [sync-ledger.md](sync-ledger.md) §4.4–4.5 (`addOwn`,
`canSign`, `nextWeekStart`, read-only ledgers), §5.2 (`innFromNpcGUID`, hidden values);
[sync-glue.md](sync-glue.md) §3.2 (`ns.ledger` is read at use, never cached), §3.5.1
(`ns.Sync:WindowChanged()` after `"added"`); [phrase.md §8](phrase.md#8-contract-for-later-slices)
(build with `compose`, list parts with the builder helpers, plain-text rendering);
[collection-cosmetics.md §8](collection-cosmetics.md#8-contract-for-later-slices) (faction
from `UnitFactionGroup("player")`, `canSeal` before `addOwn`, `markEarned` after, `Core`
records at login). Client facts: [platform-forever.md](../platform-forever.md) → *Gossip*,
*At an innkeeper (2026-10-05)*, *Sitting detection*.

---

## 1. Problem

Everything under the guestbook exists (the ledger, phrases, places, cosmetics, sync), but
nobody can sign it: `Sign.lua` is a stub, so a player's book stays empty and sync has
nothing of theirs to share. The beta has a real innkeeper to test at (Coriella
Calmbreeze, NPC `254089`) and closes on 2026-10-21. This slice gives a player standing at
an innkeeper in `Data/Inns` a "Sign the guestbook" button on the gossip frame, a way to
compose a canned phrase, and one click that stores an own entry every peer will accept,
records what it earned, and lets `Sync` announce it. Anything that stops a signature gets
one plain reason, so the player is never left guessing.

## 2. Scope

**In:**
- `SignFlow.lua` (new, **pure**): button visibility, the checks and their reasons, the
  seal choices, the commit (entry, `addOwn`, unlock recording), the composer's state model
  (the "draft"), and the message text ([§3.2](#32-signflow-api)–[§3.6](#36-the-draft-model)).
- `Sign.lua` (glue): the `GOSSIP_SHOW` / `GOSSIP_CLOSED` handlers, the gossip button, the
  DRAFT composer frame, the client reads with hidden-value checks, the calls to
  `ns.Core:Print`, `ns.Core:Debug` and `ns.Sync:WindowChanged()` ([§3.7](#37-the-composer-draft),
  [§3.9](#39-signlua-the-glue)).
- `Core.lua`: record unlocks once at login for a writable ledger
  ([§3.5](#35-recording-unlocks)).
- Wiring: TOC, `load.PURE`, `.luacov`, `check-coverage.sh` (90%), `.luacheckrc`
  (`GossipFrame`), stub additions, specs ([§6](#6-test-plan)), docs ([§4](#4-data-model-changes)).

**Out:**
- `UI/Book`, the Share window, `/ledger share`, any view of entries or cosmetics.
- Any change to the wire format, `SyncProtocol`, `Ledger`, `Phrase`, `Collection`,
  `Cosmetics`, the export format or the SavedVariables schema.
- **Recent phrases**, remembering the last phrase or seal, a "random phrase" button.
- **Announcing earned cosmetics** in chat or on screen (the book shows them; the wording
  and the moment are a design question, [Open questions](#open-questions-maintainer)).
- **Sitting** as a condition: the client has no query for it
  ([platform-forever.md](../platform-forever.md) → *Sitting detection*), so the
  architecture's "drop it if so" applies.
- Quills on the composer (they're the book's look, not part of an entry).
- Camps, non-innkeeper NPCs, signing from anywhere but the gossip frame.
- Localization: the DRAFT text is English, like phrases and place names.

## 3. Approach

### 3.1 Pieces and load order

| Piece | Kind | Holds |
|---|---|---|
| `SignFlow.lua` | **pure** (new) | every decision: when the button shows, the checks, the commit, unlock recording, the draft model, message text |
| `Sign.lua` | glue | events, the button and composer frames, the client reads, chat output, `WindowChanged` |
| `Core.lua` | glue | one extra call at login: `ns.Sign:RecordUnlocks()` |

- **TOC:** `SignFlow.lua` goes after `Export.lua`, at the end of the pure block (it reads
  `ns.Ledger` at load and asserts it; everything else comes in through `SignFlow.new`'s
  `deps`). `load.PURE` gains `{ path = "SignFlow.lua", name = "SignFlow" }`; `.luacov`
  includes `"SignFlow$"`; `scripts/check-coverage.sh` gets `SignFlow.lua 90`.
- **Why a pure module:** this is the `SyncSchedule` split again. The logic the ticket
  cares about (visibility, the reasons, what a click commits, which seals are offered) runs
  in the strict environment with a coverage floor and exact tests; what's left in
  `Sign.lua` is frames and client reads, tested through the stub.
- `SignFlow` never reads `ns` after load and never calls a WoW function: client values
  arrive as arguments, the ledger is passed in, and `Phrase`, `Collection` and `Cosmetics`
  come through `deps`.

### 3.2 `SignFlow` API

`SignFlow.new(deps)` returns a **flow**. `deps = { inns, atlas, phrase, cosmetics }`:
- `inns`: the `Data/Inns` table (`ns.Data.Inns`), for `Ledger.innFromNpcGUID`;
- `atlas`: a `Collection` atlas (needs `innOf`, `inn`);
- `phrase`: a `Phrase` set (needs `validIds`, `render`, `compose`, `text`, `hasSlot`,
  `templates`, `conjunctions`, `categories`, `words`);
- `cosmetics`: a `Cosmetics` set (needs `unlocked`, `canSeal`, `info`, `SEALS`).

A missing table or function raises (a caller bug, like `SyncSchedule.new`). The real flow
is `SignFlow.new({ inns = ns.Data.Inns, atlas = ns.Collection.atlas, phrase = ns.Phrase,
cosmetics = ns.Cosmetics })`, built by `Sign.lua` at load. Tests build flows over fixtures
(`Collection.bind`, `Cosmetics.bind`, `Phrase.bind`).

**The situation** `s` is what the glue read from the client, already checked for hidden
values ([§3.9](#39-signlua-the-glue)): `{ ledger, npc, resting, now, faction }`, where
`ledger` is `ns.ledger` (or `nil`), `npc` is `UnitGUID("npc")` (or `nil`), `resting` is
`true` only if `IsResting()` read exactly `true`, `now` is `GetServerTime()` (or `nil`)
and `faction` is `"Alliance"`, `"Horde"` or `nil`.

| Function | Returns |
|---|---|
| `flow.innAt(npc)` | the NPC ID if `Ledger.innFromNpcGUID(npc, inns)` gives one **and** `atlas.innOf(id) ~= nil` (a record `Collection.bind` excluded shows no button: fail closed); else `nil` |
| `flow.innName(id)` | `atlas.inn(atlas.innOf(id)).name` (the primary's name, so an alias shows its inn), or `nil` |
| `flow.check(s)` | `{ ok = true, inn = id, name = s }` or `{ ok = false, reason = r, wait = n? }` ([§3.3](#33-checks-and-reasons)) |
| `flow.seals(s)` | the seal IDs the player may sign with now, ascending ([§3.4](#34-commit)); `{}` when none or on any bad input |
| `flow.commit(s, inn, ids, seal)` | `{ result = "added", entry = e, earned = { id, ... } }` or `{ result = r, wait = n? }` ([§3.4](#34-commit)) |
| `flow.recordUnlocks(ledger, faction)` | the IDs newly recorded, ascending; `{}` for a missing or read-only ledger ([§3.5](#35-recording-unlocks)) |
| `flow.newDraft(seals)` | a draft ([§3.6](#36-the-draft-model)), or `nil` if the phrase set has no template |
| `SignFlow.message(res, name)` | the one chat line for a check or commit result ([§3.8](#38-messages-draft)) |
| `SignFlow.untilText(seconds)` | `"in 3 days"`, `"in 47 hours"`, `"in 12 minutes"` ([§3.8](#38-messages-draft)) |
| `SignFlow.REASONS` | the reason codes of §3.3–3.4, as a set (a copy) |

Every flow function **never throws** on any argument: each runs its body in `pcall` and
returns its failure value (`nil`, `{}`, or `{ ok = false, reason = "error" }` /
`{ result = "error" }`). Arguments are read with type checks first; numbers pass the
integer-and-range test (`NaN`, `inf` and fractions fail).

### 3.3 Checks and reasons

`flow.check(s)`, in this order, stopping at the first failure:

| # | Check | Reason |
|---|---|---|
| 1 | `s` is a table and `s.ledger` is a table | `no_ledger` |
| 2 | `s.ledger.readOnly == false` | `readonly` |
| 3 | `inn = flow.innAt(s.npc)` is not `nil` | `not_inn` |
| 4 | `s.now` is an integer in `tMin`..`tMax` | `clock` |
| 5 | `s.ledger:canSign(inn, s.now)` is `true` | `too_soon`, with `wait = ledger:nextWeekStart(now) - now` |
| 6 | `s.resting == true` | `not_resting` |

On success: `{ ok = true, inn = inn, name = flow.innName(inn) }`.

- **`too_soon` comes before `not_resting`,** so a player who already signed isn't told to
  rest first and then told it was pointless.
- **The button doesn't depend on these checks:** it shows whenever `innAt` finds an inn
  ([§3.9](#39-signlua-the-glue)), and a click explains a failure in one chat line. A
  silently missing button at an innkeeper would look like a bug.
- **Faction isn't checked.** The client already keeps players from talking to the other
  faction's innkeepers; an entry at an inn not open to your faction is stored and counts
  nowhere in progress (collection-cosmetics.md §3.3), which is harmless.

### 3.4 Commit

`flow.seals(s)`: if `check(s)` fails, `{}`. Else `u = cosmetics.unlocked(ledger:own(),
s.faction, ledger:earned())`, and the result is every `id` in `u` with
`rawget(cosmetics.SEALS, id) ~= nil` and `cosmetics.canSeal(u, id, s.now) == true`,
ascending, no duplicates. So the signature that earns a seal can't carry it; the next one
can.

`flow.commit(s, inn, ids, seal)`, stopping at the first failure:
1. Checks 1–2 of §3.3 (`no_ledger`, `readonly`).
2. **Same inn:** `inn` is an integer and `flow.innAt(s.npc) == inn`, else `changed` (the
   gossip closed, or the player is now talking to someone else). The NPC is read again at
   commit, so nothing a composer remembers can sign at an inn the player has left.
3. Checks 4–6 of §3.3 (`clock`, `too_soon` with `wait`, `not_resting`).
4. **Phrase:** `phrase.validIds(copy of ids) == true`, else `phrase`. (`ids` from
   `draft:ids()` may be `nil`.)
5. **Seal:** `u` as in `seals` above (computed **before** `addOwn`), then
   `cosmetics.canSeal(u, seal, s.now) == true` (exactly `true` for `seal == nil`), else
   `seal`. A seal that stopped being allowed is refused, never silently dropped.
6. `e = { inn = inn, t = s.now, phrase = <copy of ids>, seal = seal }`;
   `r = ledger:addOwn(e)`. Anything but `"added"` (`dup`, `too_soon`, `invalid`,
   `readonly`) is returned as the result.
7. On `"added"`: `earned = flow.recordUnlocks(ledger, s.faction)`; return
   `{ result = "added", entry = <a copy of e>, earned = earned }`.

`commit` never calls `addForeign`, never writes anything but `addOwn` and `markEarned`, and
never calls `Sync`: the glue does that on `"added"`.

### 3.5 Recording unlocks

`flow.recordUnlocks(ledger, faction)`: a missing or read-only ledger → `{}`. Else
`u = cosmetics.unlocked(ledger:own(), faction, ledger:earned())`; for each item, note
whether `ledger:earnedAt(id)` was `nil`, then `ledger:markEarned(id, t)` (idempotent; the
ledger keeps the earliest time). Returns the IDs that were `nil` before and recorded now.

- **After a signature** (§3.4 step 7).
- **At login** (collection-cosmetics.md §8: a data update never finds an unrecorded
  unlock): in `Core:OpenLedger`, after `ns.ledger` is set and the owner name is stored,
  and before `ns.Sync:Start()`, a writable ledger gets
  `pcall(ns.Sign.RecordUnlocks, ns.Sign)`. `Sign:RecordUnlocks()` reads the faction
  ([§3.9](#39-signlua-the-glue)) and calls `flow.recordUnlocks(ns.ledger, faction)`. An
  error is swallowed with one debug line (`sign: error in login`); opening the ledger and
  starting sync never depend on it.
- An unreadable faction counts every inn (unlocks get harder, never easier), so recording
  with `nil` can only record less. The next signature records again.

### 3.6 The draft model

The composer's state, pure, so the glue only copies strings into frames. `flow.newDraft(seals)`
returns `nil` when `phrase.templates()` is empty; else a draft with indexes `v1`, `t1`,
`cat1`, `w1`, `v2`, `c`, `t2`, `cat2`, `w2` (all start at 1), `second = false`, and
`seal = 0` (none), over a private copy of `seals`.

**Voices** (amended 2026-10-06, #100): the draft builds its voice groups once, from
`phrase.voices()` (optional in `deps.phrase`): one group per voice that has at least one
template, holding `templates(v)` and `conjunctions(v)` (all conjunctions when the voice
has none of its own). With no group left (no voices bound, or `voices` missing or junk),
one unnamed group holds `templates()` and `conjunctions()`, and the voice rows hide.
Line 1 uses group `v1` for `t1`; line 2 uses group `v2` for `c` and `t2`. Changing `v1`
resets `t1`; changing `v2` resets `c` and `t2`. **Line 2 follows line 1's voice** (moving
`v1` also sets `v2` and resets `c`, `t2`) until the player steps `v2` once; from then on
the two are independent. A step that wraps a one-item list back to itself changes
nothing and resets nothing. When any voice group exists, a template or conjunction with
no `voice` isn't offered; the shipped data gives every one a voice (a test checks it).

| Method | Does |
|---|---|
| `draft:step(field, delta)` | `field` in `v1 t1 cat1 w1 v2 c t2 cat2 w2 seal`, `delta` `1` or `-1`; moves the index with wrap-around over its list (the voice groups, the group's templates, `categories()`, `words(cat)`, the group's conjunctions; `seal` over `0..#seals`). Changing a category resets its word to 1. A field whose list is empty, or any other argument, is a no-op |
| `draft:setSecond(on)` | `on == true` adds the second part; anything else removes it |
| `draft:ids()` | `phrase.compose(T1, W1, C, T2, W2)` where `W1` is the word only if `hasSlot(T1)`, and `C, T2, W2` only if `second` (W2 only if `hasSlot(T2)`); so `nil` only for a set with an empty category or no conjunction |
| `draft:seal()` | the chosen seal ID, or `nil` for none |
| `draft:view()` | the strings to show: `{ v1, t1, cat1, w1, v2, c, t2, cat2, w2, seal, preview, word1 = bool, word2 = bool, second = bool, sealRow = bool, voiceRow = bool }` |

- **`view` strings:** template text with its slot shown as `___` (plain `find` + `sub`,
  never `gsub` with data), `v1` / `v2` as the DRAFT "Voice: " plus the voice name (`nil`
  for the unnamed group), category names, word and conjunction texts, the seal's
  `cosmetics.info(id).name` or the DRAFT "No seal" line, and `preview =
  phrase.render(ids)` (or `nil`). `word1` / `word2` say whether the word rows apply;
  `sealRow` is `#seals > 0`. All of it is our own allow-listed data (no `|`, no `%`).
- The initial draft is a valid phrase with the real data (`{1, 1001}`, "Rested here,
  dreaming of home."), so the preview is never empty and Sign is never a dead button.

### 3.7 The composer (DRAFT)

**Its look, layout and every label are the maintainer's to decide; this is a plain,
functional draft.** It uses only pieces the beta has shown or that are core frame API:
- **Frame:** `CreateFrame("Frame", nil, GossipFrame)`, about 380×530, anchored with its
  `TOPLEFT` at `GossipFrame`'s `TOPRIGHT`, mouse enabled, a background texture
  `SetColorTexture(0, 0, 0, 0.85)` (no backdrop template, nothing unverified). Parented to
  `GossipFrame`, so it hides when the gossip does; the `GOSSIP_CLOSED` handler hides it
  too ([§3.9](#39-signlua-the-glue)).
- **Rows**, fixed positions (a hidden row leaves a gap, no relayout), each a
  `UIPanelButtonTemplate` `<` button, a font string (`GameFontHighlight`, word-wrapped)
  and a `>` button wired to `draft:step(field, ∓1)`:
  1. title "Sign the guestbook" and the inn's name (`flow.innName`);
  2. `v1` (shown when `voiceRow`), `t1` (the first line's template); `cat1`, `w1` (shown
     when `word1`);
  3. a toggle button, "Add a second line" / "Remove the second line" → `setSecond`;
  4. when `second`: `v2` (when `voiceRow`), `c`, `t2`, and `cat2`, `w2` (when `word2`);
  5. `seal` (shown when `sealRow`);
  6. the preview, word-wrapped, up to 160 bytes;
  7. **Sign** and **Cancel** buttons.
- Every change re-reads `draft:view()` and refreshes every string and row.
- No dropdowns (the modern menu API is unverified on Forever), no scroll lists, no
  `UISpecialFrames` (it needs a named global frame); Escape closes the gossip frame, and
  the composer with it.

### 3.8 Messages (DRAFT)

One chat line per outcome, through `ns.Core:Print` (the AddOn's prefix, our own chat
frame; nothing is sent to anyone). The wording is DRAFT; all of it lives in one table,
`SignFlow.TEXT`, so it's retuned in one place. `SignFlow.message(res, name)` picks the
line by `res.reason` or `res.result`; an unknown code gets the `error` line.

| Code | Line (DRAFT) |
|---|---|
| `added` | `You signed the guestbook of <inn name>.` (`name` from `flow.innName`; "the inn" if `nil`) |
| `no_ledger` | `Your ledger isn't open yet. Try again in a moment.` |
| `readonly` | `Your ledger is read-only (saved by a newer version, or damaged), so nothing was signed.` |
| `not_inn`, `changed` | `Talk to the innkeeper again to sign the guestbook.` |
| `clock` | `The server time can't be read right now. Try again in a moment.` |
| `too_soon` | `You've signed this guestbook this week. Sign again after the weekly reset (` .. `untilText(wait)` .. `).` |
| `not_resting` | `Rest at the inn to sign its guestbook.` |
| `phrase` | `That phrase can't be signed. Choose another.` |
| `seal` | `That seal can't be used yet. Choose another.` |
| `no_phrases` | `There are no phrases to sign with.` |
| `dup`, `invalid`, `error` | `Nothing was signed.` |

`SignFlow.untilText(n)`: `n >= 172800` → `"in <floor(n / 86400)> days"`; `n >= 3600` →
`"in <floor(n / 3600)> hours"` (`"1 hour"` singular); else `"in <max(1, ceil(n / 60))>
minutes"` (`"1 minute"`). A non-integer or negative `n` → `"soon"`. Lines are built by
concatenation, never `string.format` or `gsub` with data, and hold only our constants, our
allow-listed inn names and numbers. No line names a site, product or service.

### 3.9 `Sign.lua`: the glue

**Client reads** (`read()` builds `s`), each call in `pcall` with a local `hidden(v)` like
`Core`'s (an `issecretvalue` that raises counts as hidden), checked **before** anything
else touches the value:
- `npc = UnitGUID("npc")`: hidden or not a string → `nil`.
- `resting = IsResting()`: only a non-hidden exact `true` is `true`; anything else
  (hidden, `nil`, an error, `1`) → `false`.
- `now = GetServerTime()`: hidden → `nil` (the flow checks the range).
- `faction = UnitFactionGroup("player")` (first return): hidden or not a string → `nil`.
- `ledger = ns.ledger`, read at use (never cached at load).

**Events.** At load, `Sign.lua` builds the flow and one event frame
(`CreateFrame("Frame")`) registered for `GOSSIP_SHOW` and `GOSSIP_CLOSED`. Every handler,
click and `RecordUnlocks` runs inside a guard: `pcall`, and on error one debug line
`sign: error in <where>` (never the error text). Nothing reaches the player as a Lua error.
- **`GOSSIP_SHOW`:** `inn = flow.innAt(read().npc)`. On first need, create the button:
  `CreateFrame("Button", nil, GossipFrame, "UIPanelButtonTemplate")`, about 180×24, its
  `TOP` at `GossipFrame`'s `BOTTOM`, text **"Sign the guestbook"**, `OnClick` →
  `Sign:Open()`. If `GossipFrame` isn't a table, no button and one debug line
  (`sign: no gossip frame`). Show the button when `inn` isn't `nil`, else hide it. If a
  session is open for another inn (or `inn` is `nil`), close it (the NPC changed while the
  composer was open). A session for the same inn is left alone (`GOSSIP_SHOW` can repeat
  while the frame is open).
- **`GOSSIP_CLOSED`:** hide the button, close the composer, end the session.

**`Sign:Open()`** (the gossip button):
1. `res = flow.check(read())`. Not `ok` → print `message(res)`, debug `sign: <reason>`, stop.
2. A session already open for `res.inn` → stop (a double click keeps the draft).
3. `draft = flow.newDraft(flow.seals(s))`; `nil` → print the `no_phrases` line, stop.
4. `session = { inn = res.inn, name = res.name, draft = draft, done = false }`; show and
   refresh the composer.

**`Sign:Commit()`** (the composer's Sign button):
1. No session, or `session.done` → do nothing (a second click after success is silent).
2. `res = flow.commit(read(), session.inn, draft:ids(), draft:seal())`.
3. `"added"` → `session.done = true`; close the composer and end the session; then
   `pcall` `ns.Sync:WindowChanged()` (an error there gets its debug line and changes
   nothing); print the `added` line; debug `sign: added`.
4. Anything else → print its line, debug `sign: <code>`. `changed` closes the composer;
   every other failure leaves it open so the player can fix it or cancel.

**`Sign:Cancel()`** closes the composer and ends the session. **`Sign:RecordUnlocks()`**
is §3.5.

**For tests,** `Sign.ui = { button, composer, rows = { t1 = { prev, label, next }, … },
toggle, sign, cancel, preview, title }` and `Sign.session` are readable fields.

**Combat:** `Sign` reads neither combat data nor combat state. The button and composer are
plain, unprotected frames, which combat lockdown doesn't restrict, and signing sends
nothing itself: `WindowChanged` only requests a HELLO, and `Sync`'s combat hold already
keeps it until the fight ends. `Sign.lua` stays out of the `combat state` rule of
`check-apis.sh` (only `Sync.lua` may read it), so no allow-list widens.

**No hooks, no gossip actions:** `Sign` listens to events only (no `hooksecurefunc` or
`HookScript` on the gossip frame; both are forbidden), never selects a gossip option, and
never binds a hearthstone. The NPC's name and gossip text are never read or shown.

### 3.10 Rejected alternatives

- **All the logic in `Sign.lua` with injected client functions (`Sync.new` style):** glue
  has no coverage floor and can't load in the strict environment; the checks and the draft
  model are exactly what should be held to one.
- **Hiding or disabling the button when signing isn't possible:** a missing button at an
  innkeeper reads as a bug, and a disabled one needs a tooltip (`GameTooltip`, unverified)
  to say why. One line on click explains every case with verified pieces.
- **The reason shown inside the gossip frame or composer:** more layout for a DRAFT;
  revisit with the maintainer's design.
- **A gossip option injected into the option list:** the beta verified a button under the
  frame; injecting into `GossipFrame.GreetingPanel.ScrollBox` means hooking Blizzard's
  data provider (hooks are forbidden).
- **Dropdowns for templates and words:** `UIDropDownMenu` is deprecated on the modern API
  and the newer menu API is unverified on Forever; arrow cyclers use only the verified
  button template.
- **Reading combat state to keep the composer closed in combat:** nothing in signing is
  protected, and it would widen the `combat state` allow-list for no gain.
- **Dropping a seal that stopped being allowed at commit:** it would sign something the
  player didn't choose; refusing with `seal` is honest and can't normally happen.
- **Checking faction before signing:** the client already prevents it, and progress
  ignores an inn not open to you.
- **Checking `canSign` and the rest only when the composer opens:** the player can walk
  out, wait past the reset or switch NPCs while composing; commit re-checks everything.
- **Requiring sitting:** no client query exists (platform-forever.md).

## 4. Data model changes

- **SavedVariables:** none. `Sign` writes `own` (through `addOwn`) and `earned` (through
  `markEarned`) of the existing schema 1 ([sync-ledger.md §4.2](sync-ledger.md#42-savedvariables));
  no new field, no schema bump, no migration. `earned` has held nothing until now, so the
  login recording of §3.5 simply fills it.
- **Wire format:** unchanged (v1). New own entries use only known inns, valid phrases and
  allowed seals, so they fit sync-ledger.md §3.2 as they are.
- **Export:** unchanged (v1). It already carries own entries and the `unlocked` list.
- **Runtime only:** `Sign.session` and the frames (session only).
- **Docs in the same PR:**
  - [architecture.md](../architecture.md) → Modules: a `SignFlow` row (pure: when to
    offer signing, the checks, the commit, the composer's state; links this spec), and the
    `Sign` row links it too. Signing flow: step 2 says the button sits under the gossip
    frame (verified), step 3 the composer (no recent phrases in v1), step 4 drops the
    sitting requirement (no query API), and the button shows at any known innkeeper with
    reasons given on click.
  - [testing.md](../testing.md) → the module pattern and stub notes for the richer frames
    and `GossipFrame` (§6.1).
  - [platform-forever.md](../platform-forever.md) → Verification checklist: the in-client
    checks of [§8](#8-in-client-checks-for-12).
  - [status.md](../status.md): `Sign` built; the composer and messages as a DRAFT under
    Open questions; the in-client batch.
  - [decisions.md](../decisions.md): one entry, *Sign: a pure SignFlow, the button at
    every known innkeeper, reasons on click, no sitting or combat check* (what §3.3,
    §3.9 and §3.10 settle), plus the new 90% coverage floor for `SignFlow.lua`.

## 5. Security notes

**For the reviewer:** `Sign` touches no peer input and no sync or export format. Review it
for these, and say so in the review:

- **What we broadcast is valid for every peer.** An own entry goes out in our HELLO
  window and ENTRIES replies, so it must pass peers' `SyncProtocol` rules (sync-ledger.md
  §5.1): `inn` comes only from `innFromNpcGUID` over `Data/Inns` (rule 16's lookup) and
  is kept by `Collection`; `t` is the server time, checked in `tMin`..`tMax`; the phrase
  passes `validIds` (the peers' `phraseOk` hook); a seal is a key of `SEALS` and passed
  `canSeal`; `addOwn` re-checks `Ledger.validEntry` and the weekly rule. A test round-trips
  a signed entry through `SyncProtocol.encodeEntries` and a peer's `receive` (§6.2).
- **Own-signature rule:** `Sign` writes only through `addOwn`; nothing in it can reach
  `addForeign` or put another player's GUID or name anywhere.
- **Hidden values** (sync-ledger.md §5.2): every client value is checked with
  `issecretvalue` before it is compared, concatenated, pattern-matched or used as a table
  key; `innFromNpcGUID` repeats the type check inside `pcall`. A hidden NPC GUID, rest
  state, time or faction makes signing impossible or counts as `nil`, never a guess.
- **Rate and size:** one own entry per inn per week (the ledger's weekly rule); a player
  signing many inns quickly only requests HELLOs, which `SyncSchedule` gates (one per
  channel per 60 s, inside the send budget). Own entries are uncapped by design, bounded by
  inns × weeks. No new storage cap is needed.
- **Text safety:** only our own allow-listed strings reach a font string or chat line
  (template, word and conjunction texts, inn and seal names, our constants). The NPC's
  name and gossip text are never read. No `string.format` or `gsub` with data.
- **Forbidden-API guard:** `SignFlow.lua` names no WoW API (pure, strict environment).
  `Sign.lua` uses no hook, gossip action, combat data or combat state, chat send or addon
  message API, even in comments ("the combat flag"); it prints only to our own chat frame
  through `Core:Print`. `sh scripts/check-apis.sh` passes unchanged: no rule or allow-list
  changes in this PR.
- **Quiet failure:** every handler and click is guarded; debug lines carry only our codes.

## 6. Test plan

### 6.1 Stub and helpers

- **`spec/helpers/wow_stub.lua`**, only what the Sign tests need: `CreateFrame(kind, name,
  parent, template)` records `parent` and `template`; frames gain `SetPoint`, `SetSize`,
  `SetWidth`, `SetHeight`, `EnableMouse`, `SetText` / `GetText`, `Enable` / `Disable`, a
  real `Show` / `Hide` / `IsShown`, `Click()` (runs `OnClick`), `CreateFontString` (a
  font string with `SetText`, `GetText`, `SetPoint`, `SetWidth`, `SetJustifyH`,
  `SetWordWrap`, `Show`, `Hide`, `IsShown`) and `CreateTexture` (`SetAllPoints`,
  `SetColorTexture`). A `GossipFrame` global (a stub frame). `UnitGUID("npc")` stays `nil`
  by default; tests override it. Keep the existing behavior for every current test.
- **Fixtures:** the pure tests reuse `spec/helpers/places.lua` (places F, entries,
  catalog C, the two hidden-value stand-ins) and the phrase fixture of
  [phrase.md §6](phrase.md#6-test-plan), and build a real `Ledger` with a fixed anchor.
  An NPC GUID helper: `npcGUID(id) = "Creature-0-4615-2991-62-" .. id .. "-0000ABCDEF"`.

### 6.2 `spec/sign_flow_spec.lua` (pure, strict environment, fixed times)

- **`new`:** raises without `inns`, `atlas`, `phrase` or `cosmetics`, or with one of
  their functions missing; loads in the strict environment; raises without `ns.Ledger`.
- **`innAt` / `innName`:** a known primary → its ID; an alias (`5003`) → `5003`, its name
  the primary's; an unknown NPC; a record present in `inns` but excluded by
  `Collection.bind` → `nil`. **Malformed GUIDs:** `Player-1-00000001`, `Pet-…`,
  `Vehicle-…`, a leading-zero ID, an 8-digit ID, a missing spawn field, `""`, a number, a
  table, `nil`, each hidden-value stand-in → `nil`, no throw.
- **`check`, one case per row of §3.3, and the order:** no `s`, no ledger, a ledger that
  isn't a table → `no_ledger`; a read-only ledger (non-table data, newer schema) →
  `readonly` even when also not resting; unknown NPC → `not_inn`; `now` `nil`, `NaN`,
  `1.5`, `tMin - 1`, `tMax + 1`, a string → `clock`; signed this week → `too_soon` with
  `wait` equal to `nextWeekStart(now) - now` (also one second before the reset, `wait =
  1`, and at the reset: ok); **signed this week and not resting → `too_soon`**; `resting`
  `false`, `nil`, `1`, `"true"` → `not_resting`; all good → `ok` with the inn and name;
  another inn signed this week doesn't block this one.
- **`seals`:** none unlocked → `{}`; a seal earned by the latest entry is offered only
  when `now` ≥ its time (canSeal), so the signature that earns it can't use it; a quill ID
  in `unlocked` is never offered; a kept `earned` floor (a zone seal kept after its
  zone gained an inn) is offered; `check` failing → `{}`; hostile `faction` → counted as
  `nil`.
- **`commit`:**
  - success: the stored entry deep-equals `{ inn, t = now, phrase = ids, seal }`; the
    returned `entry` and stored copy are independent of the caller's `ids` table (change
    it after: storage unchanged); `earned` lists exactly the new unlocks.
  - **each `addOwn` result**, through a fake ledger whose `addOwn` returns `"dup"`,
    `"too_soon"`, `"invalid"`, `"readonly"` (and raises → `error`): returned as the
    result, `recordUnlocks` not called, nothing else written.
  - `changed`: `s.npc` `nil` (gossip closed), another known inn, an unknown NPC, a
    hidden stand-in; `inn` argument `nil`, `NaN`, a string.
  - the checks again at commit time: blocked when the draft opened, then the weekly reset
    passed → `added`; signed meanwhile → `too_soon`; walked out → `not_resting`.
  - **`phrase`:** `ids` `nil` (compose returned nil), `{}`, `{3}` (slotted template
    alone), six IDs, an unknown ID, a table with a raising metatable; `addOwn` never
    called (spy).
  - **`seal`:** an unknown seal, a known seal not unlocked, a seal unlocked by an entry
    after `now`, a quill ID, `0`, `NaN`; `nil` seal passes.
  - **double commit:** two commits with the same `s` → the first `added`, the second
    `too_soon`; one own entry.
  - **round trip to a peer:** a committed entry encoded with
    `SyncProtocol.encodeEntries(ledger:shareWindow(40), 0)` and received by a second
    ledger through `SyncProtocol.receive` (ctx as in `spec/sync_protocol_spec.lua`'s
    `newCtx`, with the same fixture `inns`, `phrases`, `phraseOk` and the fixture set's
    `SEALS`) is stored under the sender, with and without a seal.
- **`recordUnlocks`:** fixture entries → `earned` holds every unlocked ID at its derived
  time and the return lists them; a second call returns `{}` and changes nothing; an
  `earned` time earlier than derived is kept; a read-only ledger, `nil`, a string → `{}`,
  nothing written (deep compare).
- **Draft:**
  - `newDraft` over an empty phrase set → `nil`; the real data's first view previews
    `Rested here, dreaming of home.`, `word1 = true`, `second = false`, `sealRow = false`.
  - `step` wraps both ways for every field; a category change resets its word; a slotless
    template → `word1 = false` and `ids()` has no word; `setSecond(true)` → a two-clause
    `ids()` that passes `validIds` and renders; `setSecond("yes")` removes it.
  - **every combination reachable from the initial draft by `step` and `setSecond` gives
    `ids()` that passes `validIds`** (walk every template × every word of one category,
    every conjunction, both clauses) with the real data.
  - a fixture with an empty category → `ids()` `nil`, `preview` `nil`, no throw.
  - `seal` over `{}` is a no-op; over `{2, 101}` cycles none → 2 → 101 → none forwards
    and the reverse backwards, `draft:seal()` matches, the label is the seal's name; the
    caller changing its `seals` table afterwards changes nothing.
  - `step` with a bad field, delta `0`, `2`, `NaN`, a stand-in → no-op, no throw.
  - view strings: the slot shows as `___`; no `|` in any string over the real data.
- **Messages:** every reason in `SignFlow.REASONS` and `added` has a line; an unknown
  code → the `error` line; `too_soon` includes `untilText(wait)`; `added` with a `nil`
  name uses "the inn"; no line contains `|`, `%` or `http`. `untilText`: `0` → `in 1
  minute`, `59`, `60` → `in 1 minute`, `61` → `in 2 minutes`, `3599` → `in 60 minutes`,
  `3600` → `in 1 hour`, `172799` → `in 47 hours`, `172800` → `in 2 days`, `604800` →
  `in 7 days`, `-1`, `NaN`, `1.5`, a string → `soon`.
- **Never throws:** every flow function with each argument replaced by `nil`, a number,
  `NaN`, a string, a table with raising metamethods and the two stand-ins.
- Coverage ≥ 90%; `luacheck` clean.

### 6.3 `spec/sign_spec.lua` (the glue, whole AddOn under the stub)

Logged in as `spec/core_spec.lua` does; `IsResting` → `true` and `UnitGUID("npc")` →
Calmbreeze's GUID (`254089`, the real data) unless a case says otherwise.
- **Button:** `GOSSIP_SHOW` at Calmbreeze → one button, parented to `GossipFrame`, text
  `Sign the guestbook`, shown; at a vendor's GUID, a malformed GUID, `nil`, a GUID that
  `issecretvalue` flags (a valid-looking string, so the hidden check must come first) and
  a raising stand-in → hidden, no error; innkeeper then vendor → hidden; `GOSSIP_CLOSED`
  → hidden; repeated `GOSSIP_SHOW` creates no second button; no `GossipFrame` → no
  button, no error, one debug line when debug is on.
- **Click reasons (one chat line each, composer not shown):** not resting; `IsResting`
  raising or hidden; signed this week (the line says `in 3 days` with the stub's reset);
  read-only ledger (`ledgers[guid]` a string); no ledger (GUID unreadable at login);
  `GetServerTime` hidden.
- **Sign end to end:** click → composer shown with the preview `Rested here, dreaming of
  home.`; step `t1` and `w1` through the row buttons and toggle the second line → the
  preview follows; Sign → one own entry in `db.global.ledgers[guid].own` with the
  composed IDs and no seal; `earned` holds 1101, 1003, 2 and 101 at the entry's time;
  `ns.Sync.WindowChanged` called once (spy); one `added` chat line naming *Calmbreeze
  Inn*; composer hidden.
- **Next week with a seal:** advance `wow.now` past the reset; click → the seal row shows;
  choose seal 101 → the new entry has `seal = 101`.
- **Double click:** the gossip button twice → one composer, the draft kept; the composer's
  Sign twice → one entry, one `WindowChanged`, one chat line.
- **Gossip closed mid-compose:** `GOSSIP_CLOSED` → composer hidden, session ended; calling
  `Sign:Commit()` afterwards does nothing; and with the session forced back, a commit with
  `UnitGUID("npc")` returning `nil` gives the `changed` line and no entry.
- **NPC changes while the composer is open:** `GOSSIP_SHOW` for a vendor → composer
  closed; for the same innkeeper again → draft kept.
- **Faction hidden or raising** → signing still works (counted as `nil`).
- **Errors:** `ns.Sync.WindowChanged` raising → the entry is kept, the `added` line still
  prints, no error escapes; `flow.commit` stubbed to raise → `Nothing was signed.`, no
  error escapes; `wow.errors` stays empty in every case.
- **Core at login:** a saved ledger with one own entry at `254089` and an empty `earned`
  → after login `earned` = `{ [2] = t, [101] = t, [1003] = t, [1101] = t }`; a read-only
  ledger → the saved table is unchanged (deep compare); `Sign.RecordUnlocks` raising →
  the ledger still opens and `Sync` still starts.
- `spec/addon_load_spec.lua`: `ns.SignFlow` is a table; the TOC, `load.PURE` and
  `.luacheckrc` checks pass with `SignFlow.lua` added.

### 6.4 Lint and guards

`luacheck .` clean (`GossipFrame` added to `.luacheckrc`'s `wow` list; no other new
global); `sh scripts/check-apis.sh` passes with no rule changed; `check-libs.sh`,
`check-links.sh`, `check-coverage.sh` (`SignFlow.lua` ≥ 90%) pass.

## 7. Acceptance criteria

- [ ] `SignFlow.lua` implements §3.2–3.6 and §3.8 (the `TEXT` table marked DRAFT); pure,
      loads in the strict environment, listed in the TOC after `Export.lua`, `load.PURE`,
      `.luacov` and `check-coverage.sh` at 90%.
- [ ] `Sign.lua` implements §3.7 (marked DRAFT in a comment) and §3.9: events only (no
      hooks), the button under `GossipFrame` labeled "Sign the guestbook", every client
      value hidden-checked first, every handler guarded.
- [ ] `Core:OpenLedger` records unlocks for a writable ledger before starting `Sync`
      (§3.5), and a failure there changes nothing else.
- [ ] Every own entry is created by `flow.commit` after the checks of §3.4, and
      `ns.Sync:WindowChanged()` is called exactly once per `"added"`.
- [ ] Every test named in §6 exists and passes (`busted` output in the PR), including the
      peer round trip, the double click, gossip closed mid-compose and the NPC change.
- [ ] `busted`, `luacheck .`, `check-apis.sh` (no rule changed), `check-libs.sh`,
      `check-links.sh`, `check-coverage.sh` green locally and in CI.
- [ ] No SavedVariables, wire or export change; no combat read; no new library.
- [ ] The reviewer checked §5 item by item and tried hostile client values of its own
      (hidden and malformed GUIDs, a bad clock, a tampered `earned`).
- [ ] Docs of §4 updated; the composer and messages are under status.md → Open questions;
      §8's checks are on the platform-forever.md checklist (#12).

## 8. In-client checks (for #12)

At Coriella Calmbreeze (`254089`), with `/ledger debug` on; read the SavedVariables file
from disk after a `/reload`:
1. "Sign the guestbook" shows under her gossip frame, and **not** under a non-innkeeper's
   (a vendor, a quest giver); it hides when the gossip closes.
2. A click opens the composer to the right of the gossip frame: the background, the font
   strings and the `<` `>` buttons render (`CreateFontString`, `SetColorTexture` are
   unverified on Forever); cycling and the second line work; the preview follows.
   **A screenshot for the maintainer** (the DRAFT look).
   The voice rows (#100): "Voice: Hearthside" over line 1; stepping it changes line 1's
   template set; the second line's voice follows until stepped; nothing overlaps in the
   530-pixel frame.
3. Sign → the `added` line; after `/reload`, `InnkeepersLedger.lua` holds one own entry
   at `254089` and `earned` holds 1101, 1003, 2, 101.
4. A second click the same week → the `too_soon` line, and the reset it names matches the
   beta's Tuesday 16:00 UTC.
5. Closing the gossip mid-compose hides the composer; talking to another NPC with it open
   closes it. Choosing *I would like to buy from you.* closes it too (`GOSSIP_CLOSED`).
6. After the next weekly reset (the beta has Tuesdays 2026-10-13 and 10-20 left): the seal
   row offers Zephras Isle's seal and the Innkeeper's seal; a sealed signature is stored
   with `seal = 101`.
7. With a second character in a party: the signature reaches them (part of the existing
   round-trip item).
8. Any innkeeper met whose rest area doesn't cover where you talk to them: the
   `not_resting` line shows.

## Assumptions (listed for the maintainer)

- **The button shows at every known innkeeper,** and a click that can't sign says why in
  one chat line, rather than the button hiding.
- **Every innkeeper shows a gossip frame** (they all offer the binder option, so the client
  never skips straight to the merchant window).
- **No sitting requirement** (no client query exists) and **no faction check** (the client
  already prevents talking to the other faction's innkeepers).
- **Signing records unlocks silently;** nothing announces a new seal or quill until
  the book shows it.
- **Default seal is none** each time; the composer doesn't remember the last phrase or
  seal.
- **The entry's `inn` is the NPC ID talked to** (an alias's own ID, as the architecture's
  data model says), so the weekly rule is per innkeeper NPC (collection-cosmetics.md's
  assumption).
- **Chat lines go to the player's own chat frame** through the AddOn's prefix; nothing is
  ever sent to a channel.

## Open questions (maintainer)

None blocks the build or the merge; the DRAFT ships until answered.

1. **The composer's look and wording** (§3.7): a plain dark panel with arrow cyclers to
   the right of the gossip frame. Keep it for launch, or describe the look you want (a
   parchment page, handwriting font, where it sits)?
2. **The messages** (§3.8): wording and tone, and whether reasons belong in chat at all
   or on the frame.
3. **Announcing earned cosmetics:** should signing say when it earns a seal or quill
   (for example "Zephras Isle's seal is yours"), or leave that to the book?
4. **Recent phrases:** worth a follow-up (the last few phrases offered first), or is the
   cycler enough?
