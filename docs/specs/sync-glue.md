# Spec: slice 2 — the `Sync` glue

> **Summary:** how the pure `Ledger` and `SyncProtocol` get wired into the client: `Core`
> opens the character's ledger, `Sync` receives and resolves senders, a new pure
> `SyncSchedule` decides what to send and when (send budget, HELLO/WANT/reply timing,
> combat hold), and ChatThrottleLib carries it. Includes the hostile-input test plan and
> the implementation ticket split.
> **Read when:** implementing or reviewing `Core`'s ledger wiring, `Sync.lua` or
> `SyncSchedule.lua`; changing any send trigger, timer, budget or the combat hold.

**Status:** approved (self-approved 2026-09-27, ticket #42). The one maintainer item, the
debug toggle wording, is settled: keep it as written (maintainer, 2026-09-27).
**Implemented** in #44–#47; #54 replaced §3.4 step 3 with the group map. Points the code settled
where this spec was silent, and one bad-clock departure from §3.5.1, are in
[decisions.md](../decisions.md) → *Sync receive: fail-closed choices* and *Sync send:
timer, clock and hold choices*.
**Security-sensitive:** yes. Sender resolution, hidden values and everything that reaches
`SyncProtocol.receive` are attack surface; the reviewer applies security-level scrutiny
to [§5](#5-security-notes) and must try hostile input of its own.

This spec expands [sync-ledger.md §8](sync-ledger.md#8-contract-for-the-sync-slice) and
honors every line of it. It changes **no** wire format, `SyncProtocol` rule or `Ledger`
behavior. Where it is stricter than §8 it says so ([§3.5.4](#354-replies)).

Binding decisions ([decisions.md](../decisions.md)): *Sync: own receive handler and
codec, single messages, no compression* · *Sender identity is resolved per channel;
unresolved senders are dropped* · *Sync may read combat state, and players are told* ·
*Sync wire format v1 and digest* · *Peer-data rate limits and time window* ·
*Re-signing follows the game's weekly reset* · *Vendor a reviewed, minimal set of
libraries* (no AceTimer, no AceComm) · *Sync scope: grouped-with + guild by default*
(archived seed decisions). This spec adds three 2026-09-27 entries: *Sync glue: a pure
send schedule, logical channels and a gated large reply*, *Guild HELLO interval*, *Debug
log*.

---

## 1. Problem

Slice 1 built the entry store and a codec that turns hostile strings into validated
entries, but nothing calls them: no ledger is opened, nothing is sent and nothing is
received. This slice makes two players' AddOns actually trade signatures when they group
or share a guild. It has to do that without trusting anything a peer sends, without
spamming the channel (a 40-player raid and a 1 000-member guild must both stay under the
rate limits of slice 1), and without sending during fights.

## 2. Scope

**In:**
- **`Core`**: open `db.global.ledgers[guid]` at login with the owner's GUID and name and
  the weekly-reset anchor ([§3.2](#32-core-opening-the-ledger)); keep the ledger at
  `ns.ledger`; start `Sync`; the debug-log sink and the `/ledger debug` toggle
  ([§3.8](#38-debug-log-and-stats)).
- **`SyncSchedule.lua`** (new, **pure**): the send budget, HELLO / WANT / reply timing and
  gates, the pending queues, the combat hold state, and the pump that decides the next
  message ([§3.5](#35-send-path-syncschedule)).
- **`Sync.lua`** (glue): prefix registration, the `CHAT_MSG_ADDON` handler, hidden-value
  checks, sender resolution for PARTY / RAID / GUILD, the guild-roster map, building
  `ctx`, dispatching results into the schedule, the triggers (group, guild, a new own
  signature), the combat events, and ChatThrottleLib sends.
- The `forbidden-apis` rule split for the combat-state names ([§5.2](#52-the-forbidden-apis-change)).
- busted specs for all three, a two-client harness, and the stub additions they need
  ([§6](#6-test-plan)).

**Out:**
- `Sign` (the signing flow). It will call `ns.Sync:WindowChanged()` after an own entry is
  added; this spec only defines that call.
- `Phrase`, `Collection`, `Cosmetics`, `Export`, UI. Until `Data/Phrases` has entries,
  every received entry is rejected as an unknown phrase; that is correct.
- Any player-facing text beyond the debug toggle lines (wording is a
  maintainer gate).
- `INSTANCE_CHAT`, whispers, custom channels: neither received nor sent in v1 (§8 of
  slice 1; #12 decides `INSTANCE_CHAT`).
- In-client verification (#12). Real two-character testing goes on that batch.
- Changing the wire format, `SyncProtocol` rules or `Ledger`. If an implementer finds the
  glue needs one, stop and flag it with a decision entry.

## 3. Approach

### 3.1 Pieces and load order

| Piece | Kind | Holds |
|---|---|---|
| `Core.lua` | glue | AceDB, opening the ledger, `ns.ledger`, `/ledger`, the debug sink |
| `SyncSchedule.lua` | **pure** (new) | every timing and budget rule of the send side, as state plus a `pump` |
| `Sync.lua` | glue | events, API calls, sender resolution, `ctx`, transport |

- **TOC:** `SyncSchedule.lua` goes right after `SyncProtocol.lua` (it reads
  `ns.SyncProtocol` and asserts it at load). `load.PURE` gains it; `.luacov` includes it;
  `scripts/check-coverage.sh` gets a **95%** floor for it (it's part of the sync
  boundary); `docs/architecture.md` → Modules gets one row.
- **Why a pure module:** the send side is where the traffic model is won or lost
  (budgets, gates, jitter, coalescing, combat hold). As pure code it runs under the strict
  environment with a coverage floor and exact-time tests; the glue left over is thin
  enough to test through the stub.
- **One clock:** everything uses `GetServerTime()` (integer seconds), the same `now`
  `SyncProtocol` takes. `SyncSchedule` never reads a clock; `now` is an argument.
- **`Sync` is an instance with injected client functions** (`Sync.new(deps)`, §3.3.1), so
  tests can run two or forty clients in one Lua state. `ns.Sync:Start()` builds the one
  real instance from the client's globals.

### 3.2 Core: opening the ledger

`Core:OnInitialize` keeps creating the AceDB object (no defaults). `Core:OnEnable` (fires
at `PLAYER_LOGIN`) calls `Core:OpenLedger()`:

1. **Owner GUID.** `guid = UnitGUID("player")`. If `issecretvalue` is a function and
   returns true for it, or `Ledger.validGUID(guid)` is false: retry after 2 s, at most 5
   attempts in all (10 s). After the last failure: no ledger for the session
   (`ns.ledger = nil`), `Sync` never starts, and the debug report says
   `ledger: no GUID`. **The GUID is checked before it is used as a table key**, so a
   hidden value never indexes SavedVariables.
2. **Owner name.** `name, second = UnitName("player")`, in `pcall`. A hidden or
   non-string `name` becomes `nil`; `Ledger.new` then leaves `me` empty (slice 1 §4.3).
   On a two-part client (Forever, #75) the name is `name .. " " .. surname`, where
   `surname = Sync.surname(second, GetNormalizedRealmName())` ([§3.4](#34-sender-resolution));
   a hidden `second` or realm, or no surname, leaves `name` alone (retail's `second` is
   `nil` for the player). A result that fails `validName` is dropped as before. The name
   is display only and never blocks opening.
3. **Weekly anchor** (slice 1 §8 → Weekly reset source):
   - `secs = C_DateAndTime.GetSecondsUntilWeeklyReset()`, called in `pcall`, only if
     `C_DateAndTime` is a table and that field a function.
   - Accept it only if it is a non-hidden number with `secs == secs` (not `NaN`) and
     `0 <= secs <= 604 860` (a week plus 60 s of tolerance), and `GetServerTime()` is an
     integer in 0..`tMax`. Then
     `anchor = floor((GetServerTime() + secs + 30) / 60) * 60` (nearest minute).
   - Otherwise the **fallback table** `Core.RESET_FALLBACK`, keyed by
     `GetCurrentRegion()`: it ships with one row, `[1] = 1790089200` (US, Tuesday
     2026-09-22 15:00 UTC). Rows for other regions come from #12. An unknown region, a
     hidden or non-number region, or a region with no row uses the US row. Because every
     player runs the same client build, everyone who syncs uses the same source.
4. **The saved table.** `local all = db.global.ledgers`; if `all == nil`, set
   `db.global.ledgers = {}`. If `all` is then not a table, `data = false` (a damaged file:
   never replaced). Else `data = all[guid]`; if that is `nil`, `all[guid] = {}` and use
   it. A non-table `data` is passed as it is.
5. **Open.** `ok, ledger = pcall(Ledger.new, data, { guid = guid, name = name }, anchor)`.
   An error (only a caller bug can cause one) → no ledger, debug report `ledger: open
   failed`. Otherwise `ns.ledger = ledger`. If it is writable and `name` passes
   `validName`, call `ledger:setOwnerName(name)` (a renamed character updates its
   display name at each login).
6. **Start sync:** `ns.Sync:Start()`. `Sync` decides for itself whether to run (§3.3.2).
   It is called after `open failed` too (Sync then turns itself off), never after
   `no GUID` (step 1).

`ns.ledger` is the only home of the ledger object. `Sign`, `Sync` and the UI read it at
use, never cache it at file load (it doesn't exist until `PLAYER_LOGIN`). The anchor is
recomputed at every login (slice 1 §8).

### 3.3 Receive path

#### 3.3.1 The `Sync` instance

`Sync.new(deps)` returns a client object. `deps` fields, all required unless marked:

| Field | Real value (from `ns.Sync:Start()`) |
|---|---|
| `ledger` | `ns.ledger` |
| `inns`, `phrases` | `ns.Data.Inns`, `ns.Data.Phrases` (a non-table becomes `{}`) |
| `seals` | `ns.Cosmetics.SEALS` if it is a table, else `{}` (the Cosmetics slice must provide exactly this name, or update this row) |
| `phraseOk` (optional) | `ns.Phrase.validIds` if it is a function, else `nil` (same rule for the Phrase slice) |
| `debug` | `function(line) ns.Core:Debug(line) end` |
| `onEntries` (optional) | `nil` in this slice; the UI slice may pass a function called after an ENTRIES result with `added > 0` (inside the handler's `pcall`) |
| `api` | a table of the client functions below |

`api` fields: `GetServerTime`, `UnitGUID`, `UnitFullName`, `UnitName`,
`UNKNOWNOBJECT` (the client's placeholder name, a string), `IsInGroup`, `IsInRaid`, `GetNumGroupMembers`,
`IsInGuild`, `GetNumGuildMembers`, `GetGuildRosterInfo`, `GuildRoster`
(`C_GuildInfo.GuildRoster`), `GetNormalizedRealmName`, `InCombatLockdown`,
`issecretvalue` (may be `nil`), `After` (`C_Timer.After`), `RegisterPrefix`
(`C_ChatInfo.RegisterAddonMessagePrefix`), `send` (`function(text, chattype, callback)`
→ `ChatThrottleLib:SendAddonMessage("BULK", "InnLedger", text, chattype, nil,
"InnLedger", callback)`), `random` (`math.random`), `Enum` (optional; the `Enum` global,
read for the prefix-result enum of §3.3.2). A missing optional client function or table
(`C_GuildInfo`, `issecretvalue`, `Enum`) is `nil`, and the code that needs it treats it as
"unavailable", never as an error.

The client holds: its `SyncSchedule`, one `SyncProtocol.newLimiter()`, one
`SyncProtocol.newWantMemo()` (shared by `receive` and the schedule), the group member
set, the guild map, `stats`, and one reused `ctx` table. All of it lives for the session
only.

#### 3.3.2 Start

`client:start()`:
1. `ledger` missing or `ledger.readOnly ~= false` → do nothing (no prefix, no events, no
   sends). Debug: `sync: off (read-only)` or `sync: off (no ledger)`.
2. `RegisterPrefix("InnLedger")` in `pcall`. Accept `true`, `0` or the value of
   `Enum.RegisterAddonMessagePrefixResult.Success` / `.DuplicatePrefix` when that enum
   exists (a duplicate means another AddOn also registered it; we still receive, and
   everything is validated anyway). Anything else → sync off for the session, debug
   `sync: off (prefix)`.
3. `held = combatNow()` (§3.6) → `schedule:setHeld(held)`.
4. Run the group and guild handlers once (§3.5.1) so a `/reload` inside a group or guild
   starts syncing without waiting for an event.
5. Only `ns.Sync:Start()` (the real path) creates the frame and registers the events:
   `CHAT_MSG_ADDON`, `GROUP_ROSTER_UPDATE`, `GUILD_ROSTER_UPDATE`, `PLAYER_GUILD_UPDATE`,
   `PLAYER_REGEN_DISABLED`, `PLAYER_REGEN_ENABLED`. Every handler calls
   `client:onEvent(event, ...)`. Tests call `onEvent` directly.

**Every handler body runs inside `pcall`.** An error is counted in `stats.errors`, gets
one debug line (`sync: error in <event>`, never the error text, which could echo peer
data), and is otherwise silent. The same wrapper covers `client:start()`,
`ns.Sync:Start()`, `WindowChanged`, the pump, every timer callback and the send callback
(§3.7).

#### 3.3.3 The `CHAT_MSG_ADDON` handler

Arguments `(prefix, text, channel, sender)`; the rest are ignored. In this order,
stopping at the first failure:

1. **Hidden values first.** If `api.issecretvalue` is a function and returns true for
   `prefix`, `text`, `channel` or `sender` (each checked, in that order) → drop
   `"hidden"`. Nothing else touches the arguments before this.
2. **Prefix.** `type(prefix) ~= "string"` or `prefix ~= "InnLedger"` → return. Other
   AddOns' traffic is not counted or logged (it would drown the log).
3. **Channel.** `type(channel) == "string"` first, then `SyncProtocol.CHANNELS[channel]`
   (PARTY / RAID / GUILD) must be true → else drop `"channel"`. WHISPER, `INSTANCE_CHAT`, CHANNEL, SAY and
   anything else are dropped here.
4. **Sender resolution** (§3.4) → `{ guid, name }`, or drop `"unresolved"`.
5. **`ctx`.** Refresh the reused table: `now = GetServerTime()`, `selfGUID =
   ledger:ownerGUID()`, and the fixed fields `ledger`, `limiter`, `wantMemo`, `inns`,
   `phrases`, `seals`, `phraseOk`.
6. **`SyncProtocol.receive(text, channel, sender, ctx)`.**
7. **Dispatch** on the result:

| Result | Action |
|---|---|
| `nil, reason` | `stats.dropped[reason] += 1`; a debug line, except for `"self"` (our own echo is normal) |
| `hello` | `schedule:onHello(sender.guid, channel, count, digest, now)` (`channel` is the wire channel it came on); request a pump |
| `want` | `schedule:onWant(channel, since, ledger:shareWindow(SHARE_MAX), now)` (wire channel); request a pump |
| `want_seen` | nothing more (`receive` already recorded it in the memo) |
| `entries` | add `added`, `dup`, `dropped`, `rejected` to `stats`; if `added > 0`, call `deps.onEntries` when it's a function (a hook for the future UI; `nil` in this slice) |

Receiving and validating continue during combat.

### 3.4 Sender resolution

The server sets `sender`, and the channel limits who can send there, so the name is
authentic. Resolution maps it to a GUID and fails closed.

1. **Shape.** `sender` must be a string of 1..96 bytes, else unresolved.
2. **Key.** `full = keyOf(sender)`, the one form per character, which keeps a
   traveler's stored name stable across channels. `realm = GetNormalizedRealmName()`,
   used only when it's a non-hidden string of 1..48 bytes (else `nil`). The form depends
   on the client (*two-part names*, below):
   - **A realm client** (retail): `fullName(sender)`. If it contains `-`, it's used as
     is; otherwise `sender .. "-" .. realm` (`sender` alone when `realm` is `nil`). The
     UI may hide our own realm suffix when it displays names; storage keeps the full
     form.
   - **A two-part client** (Forever): the sender as the server sends it,
     `"First Surname"`. A sender ending in `"-" .. realm` (our own realm, exactly) loses
     that suffix; any other `-` stays, so it can't match a bare key. Senders were seen
     with no realm (beta, 2026-09-30).

**Two-part names** (#75; decisions.md, 2026-09-30, *Two-part names key as the bare
sender form*). Forever's names are `"First Surname"`, and its `UnitName` /
`UnitFullName("player")` return `"First", "Surname"`: the surname sits where retail puts
the realm. The client tells the two apart **from its own player unit only**, never from
a peer string: `Sync.surname(second, realm)` is `second` (the 2nd return of
`UnitFullName("player")`, `UnitName` as the fallback) when it's a non-empty string of at
most 48 bytes with no whitespace or `-` that differs from `realm`, else `nil`. Retail's
slot holds our realm (or `nil`), so it's `nil` there. The answer is decided once, the
first time `realm` and a non-empty, non-hidden string `second` are both readable, and
kept for the session; until then the client follows the realm rules, under which a
two-part sender never matches (fails closed). Deciding "two-part" empties the group and
guild maps (built in the realm form until then) and clears the rescan gate, so the two
forms never mix: the next group miss rescans at once, and a guild miss requests the
roster.
3. **PARTY / RAID:** `guid = groupMap[full]`, the map below. If there's no entry,
   rescan the group's names now (the map only, at most once per 10 s; a clock that went
   back allows one at once) and look again; still no entry → unresolved. A sender who
   left the group, or whose name our scan can't read, is unresolved. **No peer string is
   ever passed to a client function:** `sender` is only compared with names our own
   scan read (decisions.md → *Group senders resolve through our own unit scan*).
4. **GUILD:** `guid = guildMap[full]`. If there's no entry: unresolved, and request a
   roster refresh (`api.GuildRoster()`, at most once per 60 s). The message is not kept
   or retried: the sender's next HELLO resyncs (decisions.md → *Sender identity is
   resolved per channel*).
5. **Result check.** A hidden `guid` (per `issecretvalue`), or one that fails
   `Ledger.validGUID` → unresolved. `SyncProtocol.receive` checks the GUID and name again
   (rules 4–5) and drops our own echo.
6. `sender = { guid = guid, name = full }`. The name is never looked up any other way.

**The group map** (full name → GUID, built from our own unit scan; decided in #54):
- Built by the unit scan of [§3.5.1](#351-logical-channels-and-triggers), so at start and
  on `GROUP_ROSTER_UPDATE`, and by the rescan in step 3. Not in a group → empty. The
  rescan replaces the map only: the member set and HELLO triggers change only on the
  roster event.
- Units: `raid1..raidN` in a raid; `player` and `party1..party(N-1)` in a party, with
  §3.5.1's `N` (at most 40 units, 41 with `player`).
- Per unit, each call in `pcall`: `guid = UnitGUID(unit)` and
  `name, realm = UnitFullName(unit)` (`UnitName(unit)` when `UnitFullName` isn't a
  function). Skip the unit if `guid`, `name` or `realm` is hidden, `guid` fails
  `validGUID`, `name` isn't a 1..96-byte string, `name` contains `-`, or `name` is the
  client's placeholder for a name not loaded yet (`UNKNOWNOBJECT` when it's a string,
  else `"Unknown"`).
- **Realm form.** A string `realm` has its spaces and `-` removed (the
  `GetNormalizedRealmName` form; `UnitName` gives `Area 52` where the sender says
  `Area52`). If the result is empty or `realm` is `nil`, the unit is on our realm:
  `key = fullName(name)`, the same completion step 2 gives a bare sender. Otherwise it
  must be 1..48 bytes and `key = name .. "-" .. realm`; any other `realm` skips the unit.
  **Verify** (#12) that this matches the sender string's form.
- **Two-part form** (a two-part client, instead of the realm form). The second return
  `realm` is `nil`, empty, or a string that equals our realm once its spaces and `-` are
  removed → `key = name` **if `name` contains a space**, else the unit is skipped (so
  `"First Surname", nil` and `"First Surname", "<our realm>"` key like the sender, and a
  unit read as `"First", "<our realm>"` never gives a first-name key another member's
  sender could match). Otherwise it's the surname:
  `name` must hold no whitespace and `realm` no whitespace or `-`, and
  `key = name .. " " .. realm`, at most 96 bytes; anything else skips the unit. Seen for
  `player` (beta); **assumed** for `partyN` / `raidN` until #12 sees another character.
- A key two units claim is **removed** until the next scan (ambiguous → unresolved).
- **Our own name is kept**, as the guild map keeps our roster row: our echo resolves to
  our GUID and `receive` drops it as `self`, quietly. The member set still skips us.
- Rebuilt on `GUILD_ROSTER_UPDATE`, at most once per 10 s (a later event inside the 10 s
  schedules one trailing rebuild), and at start. `api.GuildRoster()` is requested at start
  when in a guild.
- For `i = 1 .. min(GetNumGuildMembers(), 2000)` (a hidden value or a non-number counts
  as 0): `name` = the 1st return of
  `GetGuildRosterInfo(i)`, `guid` = the **17th** (retail order, **verify** #12). Skip the
  row if either is hidden, `name` isn't a 1..96-byte string, or `guid` fails `validGUID`.
  Key by `keyOf(name)`, as a sender (step 2): on a two-part client a roster name with or
  without our realm's suffix keys as `"First Surname"` (which one Forever gives is open,
  #12).
- A key that two rows claim is **removed** and stays removed until the next rebuild
  (ambiguous → unresolved). Rows past 2 000 are ignored (the server's guild cap is far
  lower; this only bounds the loop).
- Leaving the guild (`PLAYER_GUILD_UPDATE` with `IsInGuild()` false) clears the map.

### 3.5 Send path: `SyncSchedule`

#### 3.5.1 Logical channels and triggers

The schedule works on two **logical channels**: `GROUP` (the wire channel is `RAID` in
a raid, else `PARTY`) and `GUILD`. `SyncSchedule.WIRE_TO_LOGICAL = { PARTY = "GROUP",
RAID = "GROUP", GUILD = "GUILD" }`. Every gate is per logical channel. A party that
becomes a raid keeps its pending items; they go out on the new wire channel.

The glue tells the schedule which channels exist and when a HELLO is wanted:

| Trigger | Glue action |
|---|---|
| `GROUP_ROSTER_UPDATE`, and at start | not in a group → `setChannel("GROUP", nil)` and clear the member set. Else `setChannel("GROUP", inRaid and "RAID" or "PARTY")`; scan `raid1..raidN` (in a raid) or `party1..party(N-1)` with `UnitGUID`, skipping hidden, invalid and own GUIDs, where `N` = `GetNumGroupMembers()` as a number capped at 40 (hidden or not a number → 0). The same scan reads each unit's name and rebuilds the group map ([§3.4](#34-sender-resolution)). The member set is **replaced** by this scan; if the scan holds a GUID the previous set didn't, `requestHello("GROUP", now, 5, 15)`. So someone who leaves and rejoins counts as new, and the set never exceeds 40. "In a group" / "in a raid" / the member count use `IsInGroup` / `IsInRaid` / `GetNumGroupMembers` with `LE_PARTY_CATEGORY_HOME` when that constant exists (never send PARTY into an instance-only group), else with no argument. |
| `PLAYER_GUILD_UPDATE`, and at start | `IsInGuild()` true and the channel wasn't set → `setChannel("GUILD", "GUILD")`, `requestHello("GUILD", now, 60, 120)`, request the roster. False → `setChannel("GUILD", nil)`, clear the map. |
| `ns.Sync:WindowChanged()` (called by `Sign` after `addOwn` returns `"added"`) | `requestHello(ch, now, 5, 15)` for each available channel |
| A GUILD HELLO sent or skipped | the schedule itself sets the next one at `now + rand(1200, 1500)` ([§3.5.3](#353-hello)) |

A HELLO is for newcomers, so a roster change where only members *left* sends nothing.

#### 3.5.2 The send budget

`SyncSchedule.LIMITS`:

| Name | Value | Rule |
|---|---|---|
| `window` | 60 | length of the sliding window, s |
| `messages` | 30 | messages handed to ChatThrottleLib in any 60 s |
| `entries` | 60 | entries in those messages in any 60 s |
| `wants` | 12 | WANTs in any 60 s |
| `inFlightMax` | 2 | messages handed over whose send callback hasn't come back |
| `inFlightRelease` | 30 | an in-flight message with no callback after this many s is treated as sent |
| `helloGap` | 60 | HELLOs per logical channel: at most 1 per this many s |
| `helloDelay` | 5..15 | jitter after a group trigger or `WindowChanged` |
| `guildFirst` | 60..120 | first guild HELLO after login or joining a guild |
| `guildEvery` | 1200..1500 | periodic guild HELLO |
| `wantDelay` | 1..5 | jitter between a HELLO and our `decideWant` |
| `pendingWantsMax` | 200 | peers with a pending WANT decision |
| `coalesce` | 5 | WANTs for us are gathered this long before a reply |
| `replyGap` | 30 | replies per logical channel: at most 1 started per this many s |
| `largeGap` | 300 | large replies per logical channel: at most 1 per this many s unless our window changed |
| `smallMax` | 5 | a reply of at most this many entries (one message) is *small* |
| `resumeDelay` | 3 | seconds after `PLAYER_REGEN_ENABLED` before re-checking combat |

- The window is **sliding**: the schedule keeps one record `{ t, entries }` per message
  handed over (at most 30 live records) and one per WANT (at most 12). A record expires
  when `now >= t + 60`. A message may go out only if, after adding it, the live records
  hold ≤ 30 messages and ≤ 60 entries, and fewer than `inFlightMax` messages are in
  flight. A WANT also needs fewer than 12 live WANT records.
- **Counting at hand-off, with at most 2 in flight:** ChatThrottleLib may hold a `BULK`
  message behind other AddOns' traffic. The in-flight cap bounds how many of ours can
  bunch up behind that: on the wire, any 60 s carries at most 30 + 2 messages and
  60 + 10 entries, under the receiver's 40 and 80 (slice 1 §5.3), as long as callbacks
  come back within the 30 s release. The callback runs synchronously inside the send call
  when ChatThrottleLib has bandwidth and nothing queued; otherwise it comes a moment later
  from the library's queue, and the pump it requests (§3.7) carries on.
- **Traffic check** (the spec reviewer's model of these rules, 2026-09-27): a 40-player
  raid from scratch draws about 8 WANTs per member raid-wide (at most 16, about 310 in
  all; slice 1's "1–3" was optimistic, since one-second jitter gives only 5 buckets and
  suppression can't act inside the first), peaks at about 680 messages in any 60 s at one
  receiver, and no sender passes about 21 a minute. All under 40 per sender and 1 200 in
  all. In a 500-online guild, one new signature can draw about 200 WANTs within 1–2 s,
  also inside the limits. The 1 200 global cap is shared across channels: 39 raid members
  at 32 each (1 248) would pass it only if every one of them were at its budget at once.
- **Server time going backwards:** at the start of each call, **past stamps** later than
  `now` are set to `now`: budget records, in-flight hand-offs, `lastHello`, `lastReply`,
  `lastLarge.at`. The limits then hold again within one window instead of freezing sends.
  **Due times** keep their jitter and coalescing but are capped at `now` plus their
  kind's longest delay (a HELLO at `now + 1500`, a WANT at `now + 5`, `replyDue` at
  `now + 5`), so a jump back can't push them hours out.

#### 3.5.3 HELLO

- `requestHello(ch, now, lo, hi)`: ignored when `ch` is unavailable. Pending due becomes
  `min(existing due, now + rand(lo, hi))`, so repeated triggers keep one HELLO and never
  push it later (slice 1 §8: further changes in that time don't add HELLOs).
- Sent when `now >= due`, `now >= lastHello[ch] + helloGap`, and the budget admits one
  message. Text: `SyncProtocol.encodeHello(window)` with `window = io.window()`.
- **An empty share window sends no HELLO** (count 0 makes every receiver do nothing, so
  it's pure traffic). The pending HELLO is cleared as if sent, without stamping the gate.
- After a GUILD HELLO is sent or skipped, the next one is set to `now + rand(guildEvery)`
  while GUILD is available.

#### 3.5.4 Replies

WANTs for us feed per-channel **buckets**. `onWant(wire, since, window, now)`:
- `n` = the number of `window` entries with `t > since`. `n == 0` → ignored (nothing to
  send). `n <= smallMax` → the **small** bucket, else the **large** bucket; each keeps the
  smallest `since` it was given.
- The channel's `replyDue` is set to `now + coalesce` if unset (the first WANT of a batch
  starts the 5 s; later ones don't extend it).

At or after `replyDue`, and once `now >= lastReply[ch] + replyGap`, the pump starts one
reply for the channel:
1. **Large first**, if the large bucket is set and the **large gate** is open: no large
   reply yet on this channel, or `now >= lastLarge.at + largeGap`, or
   `SyncProtocol.digest(window) ~= lastLarge.digest` (our window changed). Send entries
   with `t > large.since`; stamp `lastLarge = { at = now, digest }`. Clear the large
   bucket, and the small one too if `small.since >= large.since` (it's covered).
2. Else **small**, if set: recompute `n` for `small.since`. `n == 0` → clear it. `n >
   smallMax` (our window grew meanwhile) → move it into the large bucket (smallest
   `since`) and go back to step 1 on the next pump. Else send it (one message) and clear
   the bucket.
3. Else (only a large ask, gate closed): wait. The ask is **deferred, not dropped**
   (slice 1 §8); the pump's wake time is the gate's opening.

Starting a reply stamps `lastReply[ch] = now`, clears `replyDue` if both buckets are now
empty (else `replyDue = now`), and puts the messages from
`SyncProtocol.encodeEntries(window, since)` into the channel's **in-progress** list
(≤ 8 strings), with each message's entry count (chunks of 5 of the entries with
`t > since`, oldest first, which is exactly how `encodeEntries` splits them). In-progress
messages go out one by one as the budget admits them, before any new reply starts on that
channel.

**Stricter than slice 1 §8, on purpose.** §8 gates only `since = 0` replies to one per
5 minutes. A hostile peer could get around that with `since = tMin` (a valid time before
all our entries), for a 40-entry reply every 30 s. Gating every reply of more than one
message closes that bypass: a hostile asker gets at most one 5-entry reply per channel
per 30 s plus one large reply per 5 minutes. Honest peers lose nothing but, at worst, a
delay of up to 5 minutes: a newcomer's `since = 0` is large and still gets its deferred
reply, a peer missing our new signatures gets them at once because our window changed,
a routine catch-up of a few entries is small, and only a peer missing 6 or more entries
of an unchanged window (lost messages) waits for the gate.

#### 3.5.5 WANT

- `onHello(guid, wire, count, digest, now)`: ignored when `count == 0`, the channel is
  unavailable, or any argument has the wrong type. A pending WANT exists for `guid` →
  replace its `count` and `digest`, keep its `due` (slice 1 §8: one pending timer per
  peer). Its channel **prefers GROUP**: a GROUP HELLO moves it to GROUP (with the new
  wire); a GUILD HELLO changes the channel only if the pending one is already GUILD or
  GROUP is unavailable. So a peer in both our group and our guild triggers a reply to
  the group, not to the whole guild. Else, if fewer than `pendingWantsMax` are pending, add `{ logical, wire,
  count, digest, due = now + rand(1, 5) }`; if the table is full, ignore the HELLO (the
  peer's next HELLO tries again).
- The pump takes due WANTs oldest `due` first (ties by GUID, byte order). For each, only
  when the budget admits one message and fewer than 12 WANTs are live: remove it and call
  `SyncProtocol.decideWant(memo, guid, currentWire, count, digest, io.held(guid), now)`.
  A `since` → send `SyncProtocol.encodeWant(guid, since)` on the channel's current wire;
  `nil` → nothing sent and no budget used. When the budget is full, the WANTs stay
  pending and are decided later with fresh state.
- `decideWant` runs only at the moment a WANT could go out, so a WANT seen meanwhile on
  that channel suppresses ours, and its per-peer count (2 per 10 minutes) only counts
  real sends.

#### 3.5.6 The pump

`schedule:pump(now, io)` with `io = { window = fn() → own share window,
held = fn(guid) → that signer's held entries, send = fn(wire, text, token) → boolean }`.
It returns the next time it wants to run, or `nil` when nothing is pending.

1. Clamp stored times to `now` (§3.5.2). Release in-flight messages older than
   `inFlightRelease`.
2. **Held (combat) → send nothing**; return `nil` (the resume path pumps again).
3. Loop, in this order, until nothing more can go out:
   a. **HELLO**: GROUP, then GUILD (§3.5.3).
   b. **Replies**: in-progress messages first, then starting a new reply (§3.5.4); GROUP,
      then GUILD.
   c. **WANTs** (§3.5.5).
   Each message gets a fresh integer token and is recorded in the budget and in flight
   before `io.send` is called. `io.send` returning false means nothing reached the
   transport: the record and the in-flight entry are removed, and the item is dropped
   (a failed HELLO clears its pending, a failed WANT is gone, a failed reply message drops
   the rest of that reply). `stats.sendFailed` counts it. The item's gate stamps
   (`lastHello`, `lastReply`, `lastLarge`) stay, so a failing transport can't be retried
   in a loop, and a failed GUILD HELLO still sets the next periodic one (#45). Only
   `false` is a failure; any other return counts as handed over.
4. Return the earliest of: each pending HELLO's `max(due, lastHello + helloGap)`; each
   channel's reply time (`max(replyDue, lastReply + replyGap)`, or the large gate's
   opening when only a gated large ask waits); the earliest pending WANT `due`; when
   something is blocked only by the budget, the earliest record expiry; when blocked by
   the in-flight cap, the earliest release time. Never earlier than `now + 1`.

`schedule:sendDone(token)` removes an in-flight entry; it may be called from inside
`io.send` (a synchronous callback) or later. An unknown token is ignored.

`schedule:setChannel(ch, wire)`: `wire = nil` drops everything pending on `ch` (HELLO,
buckets, in-progress messages, the WANTs whose logical channel is `ch`) and makes it
unavailable. A non-nil `wire` must be `PARTY` or `RAID` for GROUP and `GUILD` for GUILD
(else ignored).

**The glue's pump:** `client:pump()` reads `now`; if it isn't an integer in 0..`tMax`,
it skips this pump and retries with a plain `api.After(5, fire)` under a fresh
generation (setting `timerAt = nil`), so no arithmetic touches the bad `now`. It calls `schedule:setHeld(true)` if
`combatNow()` (§3.6), then `schedule:pump(now, io)`, then `requestPump(wake)`.

**Exactly one live timer.** Event handlers and send callbacks never send; they update
state and call `requestPump(now + 1)`. `requestPump(at)`:
- `at = nil` → nothing (idle).
- A live timer targets a time ≤ `at` → nothing.
- Else bump `timerGen`, set `timerAt = min(at, now + 5)`, and
  `api.After(timerAt - now, fire)`, where `fire` first checks that its captured
  generation is still `timerGen`. A **stale** timer returns at once, without pumping or
  scheduling anything. A current one clears `timerAt` and pumps.
- The 5 s horizon keeps stale timers short-lived: at most about 6 are outstanding at any
  time, whatever the traffic. A pump with nothing due is cheap and changes nothing, so a
  guild member pumps every 5 s while a HELLO is pending far ahead.

Every `SyncSchedule` method takes only plain values and never throws on bad input: a
wrong-type argument makes the call a no-op (`false` where the method returns a boolean).
`pump` reads `io`'s fields with `rawget` and returns `nil` unless all three are
functions; the `io` calls and the `SyncProtocol` encoders run inside the pump's own
`pcall`. An error there (say, `io.window()` returning something the encoders reject)
aborts this pump with nothing further sent and returns `now + 5`. Each item's stamps and
queue changes are written only after its encoder has returned, so an error leaves only
what the completed sends already did (no rollback needed).
`SyncSchedule.new(opts)` is the exception: a missing `opts.memo` table or `opts.rand`
function raises (a caller bug). `opts.rand(lo, hi)` must return an integer in `lo..hi`;
the glue passes `math.random`, tests pass a fixed sequence. `schedule:snapshot()` returns
counts (pending HELLOs, WANTs, reply buckets, in-progress messages, in-flight, live
budget records) for tests and the debug report.

### 3.6 Combat hold

- **`combatNow()`** (glue): a missing `api.InCombatLockdown` → not in combat. Else
  `ok, v = pcall(api.InCombatLockdown)`; only `ok` with a non-hidden `v == false` means
  not in combat. An error, a hidden value, `true`, `nil`, `1` or anything else → in
  combat (fail safe: hold).
- **Enter:** `PLAYER_REGEN_DISABLED`, `combatNow()` at start, or `combatNow()` at any
  pump → `schedule:setHeld(true)`. Bump a generation counter.
- **While held:** the pump sends nothing. Receiving, validating and storing continue, and
  `onHello` / `onWant` / `requestHello` keep updating the pending state, which is already
  bounded: one HELLO per channel, the two reply buckets and ≤ 8 in-progress messages per
  channel, ≤ 200 pending WANTs (one per peer). WANT decisions wait for the flush. An
  in-progress reply stops mid-way and continues after the fight.
- **Resume:** on `PLAYER_REGEN_ENABLED`, bump the generation and wait `resumeDelay` (3 s).
  Then, if the generation is unchanged and `combatNow()` is false,
  `schedule:setHeld(false)` and pump: HELLOs, replies, WANTs in that order, within the
  budget (§3.5.6). Still in combat → stay held until the next `PLAYER_REGEN_ENABLED`.
- **Held re-check:** while held, the glue runs the same resume check every 30 s (a
  timer of its own, one at a time, generation-checked like the pump's). A combat check
  that errored or returned a hidden value once can then clear without waiting for the
  next fight to end.
- **Already handed over:** at most `inFlightMax` (2) of our messages can sit in
  ChatThrottleLib's queue when a fight starts; those may still go out. Everything else
  waits.

### 3.7 Transport

- Every send is `ChatThrottleLib:SendAddonMessage("BULK", "InnLedger", text, wire, nil,
  "InnLedger", callback)`, through `api.send`. `callback(arg, didSend)` runs inside the
  same `pcall` wrapper as the handlers (ChatThrottleLib calls it through
  `securecallfunction`, so an escaping error would reach the player). It calls
  `schedule:sendDone(token)` and then `requestPump(now + 1)`, **never** a pump directly:
  it may run inside `io.send` or inside ChatThrottleLib's own despool loop. Without that
  request, a queued send (another AddOn's traffic queued, the library's start-up or
  zoning throttle, a server throttle) would leave the in-flight cap closed until the 30 s
  release. `didSend == false` is counted in `stats.sendFailed` and gets a debug line. The
  message isn't re-sent (the next HELLO cycle recovers).
- `ChatThrottleLib` is the global the library sets. A newer copy loaded by another AddOn
  upgrades the same table in place, so the reference stays valid.
- Sync never calls `C_ChatInfo.SendAddonMessage` itself.
- **Only these texts are ever sent:** `encodeHello` of our share window, `encodeWant` for
  a peer whose HELLO we got, and `encodeEntries` of our share window. Nothing else, no
  other channel, no target.

### 3.8 Debug log and stats

- **`stats`** (always kept, plain integers): `received[kind]`, `dropped[reason]` (the
  `SyncProtocol` reasons plus `hidden`, `channel`, `unresolved`), `added`, `dup`,
  `rejected`, `evicted` (the `dropped` count of ENTRIES results), `sent[hello|want|
  entries]`, `sendFailed`, `errors`.
- **Off by default, session only.** `/ledger debug` toggles it. The state isn't saved,
  so it can't be left on by accident across logins.
- **Turning it on** prints one report line: the ledger state (`read-only (<reason>)` or
  `open`, with the non-zero `loadReport` counts, or `no GUID`, `open failed`, `not open
  yet` while the GUID retry runs) and the `stats` totals. `Core` reads the real client's
  counters at `ns.Sync.stats` (the `Sync` receive ticket exposes them there) and sums each
  table of counters; with no `stats` it prints `sync: no stats`.
- **While on:** `Core:Debug(line)` prints through `Core:Print`. At most 5 lines per 10 s;
  lines over that are counted, and the next printed line starts with `(<n> skipped)`.
  Nothing is buffered.
- **No peer strings, ever.** A line holds only our own constant words and reason codes,
  numbers, a channel name taken from our own set (`PARTY`, `RAID`, `GUILD`; anything else
  is written `other`) and, for a resolved sender, the GUID **after** it passed
  `validGUID`. Never a name, never message text, never an error message. No link, site or
  service is named.
- **Wording:** `/ledger debug`, `Debug log on.` / `Debug log off.` and plain `sync: …`
  lines. It's developer-facing and kept as written (maintainer, 2026-09-27; decisions.md →
  *Debug toggle wording: keep it as written*).

### 3.9 Rejected alternatives

- **All the send logic inside `Sync.lua`:** glue has no coverage floor and can't load in
  the strict environment, and the traffic model lives in exactly this logic.
- **Putting scheduling into `SyncProtocol`:** it is the validation boundary; mixing in
  state machines would grow the module the security review has to re-read.
- **One `C_Timer` per pending item:** hundreds of timers in a big guild, and ordering
  across timers is hard to test. One pump with a computed wake time is simpler.
- **`GetTime()` for scheduling:** a second clock beside the `GetServerTime()` that
  `SyncProtocol` already uses; one-second resolution is enough for 1–5 s jitter.
- **Counting the budget when ChatThrottleLib actually sends (callbacks only):** a lost
  callback would freeze the budget. Hand-off counting plus the in-flight cap bounds
  bunching and can't freeze.
- **Gating only `since = 0` replies** (§8 as written): open to the `since = tMin` bypass
  (§3.5.4).
- **Deciding a WANT when the jitter timer fires, then queueing it:** the decision goes
  stale behind the budget or a fight, and it spends one of the peer's two asks on a WANT
  that may never go out.
- **Folding an interrupted reply into a new `since`:** re-encoding saves nothing; the
  remaining ≤ 8 strings are bounded and still valid.
- **Keying pending items by wire channel:** a party that turns into a raid would drop
  its pending reply, and nothing would ask again until the next HELLO.
- **`UnitGUID(sender)` for any channel:** it hands a peer-chosen name to a function that
  also parses unit tokens (`Target`, `Focus`, …), so a member named like a token would
  get our target's GUID. Replaced by the group map in #54 (decisions.md → *Group senders
  resolve through our own unit scan*, which also rejects a token deny-list).
- **A group-map miss that also rescans the member set:** a peer could then drive HELLO
  triggers by sending; the rescan touches the map only, and at most once per 10 s.
- **Retrying an unresolved message after a roster refresh:** settled against (decisions
  2026-09-26); only the map refreshes.
- **A saved debug setting or an in-memory log buffer:** a saved flag gets forgotten on;
  a buffer holds peer-derived data for no one.

## 4. Data model changes

- **SavedVariables:** none to the ledger schema (still 1). `Core` creates
  `InnkeepersLedgerDB.global.ledgers = {}` when it is `nil` and `ledgers[guid] = {}` for a
  new character (slice 1 §4.2). It never replaces a non-table value.
- **Wire format:** unchanged (v1).
- **Export:** unchanged.
- **Runtime only:** `ns.ledger`; the `Sync` client's limiter, WANT memo, schedule, member
  set, guild map and stats (all session-only).

## 5. Security notes

**Flag for the reviewer: security-level review.** Everything in this section is attack
surface or guards it.

### 5.1 What a peer controls, and what stops it

| A peer controls | Guard | Where |
|---|---|---|
| `text` of an addon message | hidden check, then everything in `SyncProtocol.receive` (rules 1–19) | §3.3.3, slice 1 §5.1 |
| its character name (as `sender`) | hidden check; 1..96-byte string; only ever compared with names our own group scan or the guild roster gave, never passed to a client function; `validGUID` on the result; `validName` in `receive` | §3.4 |
| its name as a group unit (server data, but player-chosen; possibly like a unit token) | read only from our own `partyN` / `raidN` / `player` units; hidden, invalid, dashed and not-yet-loaded names skipped; duplicate keys become unresolved; at most 41 units; a miss rescans the map at most once per 10 s | §3.4 |
| which channel it uses | only PARTY / RAID / GUILD; server-enforced membership | §3.3.3 |
| HELLO count / digest (churn, floods) | one pending WANT per peer; ≤ 200 pending; `decideWant`'s 2 per 10 minutes; 12 WANTs per 60 s | §3.5.5 |
| WANT `since` (spam, `0`, `tMin`) | 5 s coalescing; 1 reply per 30 s per channel; any reply over 5 entries gated to 1 per 5 minutes unless our window changed | §3.5.4 |
| WANTs addressed to others | recorded in the memo only (suppression), never stored | slice 1 rule 13 |
| message rate | `SyncProtocol` limiter (40 / 80 / 1 200 / 1 000) | slice 1 §5.3 |
| guild roster rows (server data, but names are player-chosen) | skip hidden or invalid rows; duplicate names become unresolved; loop bound 2 000 | §3.4 |
| anything that makes our code error | `pcall` around every handler, the pump and timers; the counter and debug line carry no peer text | §3.3.2 |

Also:
- **Own-signature rule:** `sender` is built only by §3.4 and only from the event's sender
  argument; `receive` stores under `sender.guid`. No other path to `ledger:addForeign`
  exists in `Sync`. The only GUID on the wire (WANT's target) never becomes a sender.
- **Stale guild map:** a name that moves to another character (a rename) inside the ≤ 10 s
  rebuild window would still resolve to the old GUID. The server controls renames, so a
  peer can't aim this, and the next rebuild fixes it.
- **Stale group map:** the map follows `GROUP_ROSTER_UPDATE`, and a hit never
  rescans, so between a change and its event a departed member's name still resolves.
  Each key's GUID was read from the same unit as its name, so it's still that
  character's own GUID; the server delivers PARTY / RAID messages only from members.
- **Read-only ledger:** `Sync` doesn't start (no prefix, no handler, no sends), and
  `receive` would drop anyway (rule 2).
- **Our sends are bounded whatever peers do:** the budget (30 / 60 / 12 per 60 s, in-flight
  cap) sits under every trigger, and the only texts are our own window's encodings.
- **Hidden values:** never used as a table key, concatenated, compared or printed before
  the `issecretvalue` check; `receive` repeats its own type checks, and `pcall` is the
  backstop for a hidden value that reports `type() == "string"` (only the client can
  test that; #12).
- **Quiet failure:** no chat output unless the player turned the debug log on; never a
  pop-up or a Lua error.

### 5.2 The forbidden-APIs change

The combat names (`InCombatLockdown`, `PLAYER_REGEN_DISABLED`, `PLAYER_REGEN_ENABLED`)
currently sit in the `combat data` rule of `scripts/check-apis.sh`, whose allow-list is
`-`. **Don't widen that rule**: that would let `Sync.lua` use the combat log, health and
auras too. Instead, in the PR that adds the combat hold:
- move the three names into a new rule `combat state|Sync.lua|InCombatLockdown
  PLAYER_REGEN_DISABLED PLAYER_REGEN_ENABLED`;
- leave `UnitAffectingCombat` and everything else in `combat data` with `-`;
- cite decisions.md → *2026-09-27 — Sync may read combat state, and players are told* in
  the PR and in a comment above the rule;
- update [security-checklist.md](../security-checklist.md) → the combat-state bullet under
  Expected future exceptions (it becomes a current exception).

`SyncSchedule.lua` and `Core.lua` must not name any addon-message or combat API, even in
comments ("the combat flag", "the transport"). The README principle about checking
*whether* you're in combat already matches this design.

## 6. Test plan

### 6.1 Harness and stub

- **`spec/helpers/wow_stub.lua` additions** (small, only what Core and the real-path
  tests need): a settable clock (`wow.now`, used by `GetServerTime`); `C_Timer.After`
  records its delay, and `wow.advance(seconds)` moves the clock forward one second at a
  time, running due timers, including ones they schedule (`wow.run_timers()` keeps its
  current meaning); a settable `GetTime` (ChatThrottleLib caches the function when it
  loads, so set the stub's value rather than replacing the function); `UnitName`, `GetCurrentRegion`, `GetNormalizedRealmName`,
  `C_DateAndTime.GetSecondsUntilWeeklyReset`, `IsInGroup`, `IsInRaid`,
  `GetNumGroupMembers`, `IsInGuild`, `GetNumGuildMembers`, `GetGuildRosterInfo`,
  `C_GuildInfo.GuildRoster`, `InCombatLockdown`, all with harmless defaults (solo, no
  guild, not in combat). *Built in #44.* Traps: AceDB calls `UnitName("player")` and
  `GetCurrentRegion()` itself when it initializes, so a test that makes either hidden,
  raising or odd sets it after `ADDON_LOADED` and before `PLAYER_LOGIN` (`login{atLogin}`
  in `spec/core_spec.lua`). AceDB creates `db.global` lazily, so read it with `rawget`.
  A hidden stand-in that isn't a string (like `newproxy`) is rejected by type checks
  anyway; to prove a hidden check runs *first*, flag a valid-looking string with
  `issecretvalue`.
- **`spec/helpers/sync_harness.lua`** (new): builds N `Sync` clients in one Lua state,
  each with its own `Ledger` (a fresh table), GUID, name and fake `api`, sharing:
  - a clock and a timer queue (`h:advance(seconds)`, one-second steps);
  - a **bus**: each client's `api.send` records the message and delivers it, at the next
    step, as `onEvent("CHAT_MSG_ADDON", "InnLedger", text, wire, senderName)` to every
    client on that channel, **including the sender** (addon messages echo on retail);
    delivery order per sender is kept; the send callback runs synchronously by default,
    and a per-client switch defers or fails it;
  - group and guild membership lists that drive each client's unit scan (`UnitGUID`,
    `UnitFullName` / `UnitName` on unit tokens), `IsInGroup` / `IsInRaid` and the guild
    roster; `c.tokens` models unit tokens like `target` (case-insensitive, as the
    client parses them), and `UnitGUID` of a name models the old lookup, for #54's
    forgery test;
  - fixture `inns` / `phrases` / `seals` tables (the real `Data` tables are empty);
  - per-client combat flags and the `PLAYER_REGEN_*` events.
  It loads the pure modules through `spec/helpers/load.lua` and `Sync.lua` as a file with
  a fresh `ns` for each client. *Built in #46,* except the combat flags and events and
  `LE_PARTY_CATEGORY_HOME` (the group functions ignore their argument), which #47 adds.
  A client function the harness should expose must also be listed in its `API_NAMES`.
- **Forever names (#75).** `harness.new({ forever = true })` models the beta: two-part
  names (`w:add("Ada Brook")`, `harness.twoPart(name, guid)` for a record), the realm
  `ClassicBetaPvP`, bare `"First Surname"` senders and roster names, and `"First",
  "Surname"` from `UnitFullName` / `UnitName` for every unit. `wow.foreverNames(first,
  surname)` gives the stub the same for `player` (overrides for `wow.install`).

### 6.2 `spec/sync_schedule_spec.lua` (pure, strict environment, fixed `now`, a scripted `rand`)

- **Budget:** 30 messages at `t = 0` → the 31st waits until `t = 60`, not `59`; 12
  five-entry messages at `t = 0` → a 13th waits, while a HELLO (0 entries) still goes; the 13th WANT in 60 s waits while a HELLO can still go; a third
  message waits while 2 are in flight, and goes after `sendDone` or after 30 s with no
  callback; `sendDone` from inside `io.send`; an unknown token is ignored; `io.send`
  returning false removes the record and drops the item; the clock going back 1 hour
  doesn't freeze sends past one window.
- **HELLO:** jitter from `rand(5, 15)`; repeated `requestHello` keeps one HELLO and never
  delays it; 1 per channel per 60 s even when requested every second; an empty window
  sends nothing and doesn't stamp the gate; GUILD reschedules after a send and after a
  skip; an unavailable channel ignores requests; GROUP and GUILD independent.
- **WANT:** one pending per peer, a newer HELLO replaces count / digest and keeps `due`,
  its channel per the GROUP-first rule; a GUILD HELLO doesn't move a pending GROUP WANT; `count = 0` ignored; the 201st peer ignored; order by `due` then GUID bytes;
  `decideWant` is called only when the budget admits a WANT (spy it: no call while
  blocked); a `nil` decision costs no budget; a HELLO churning its digest every second
  for 10 minutes gets ≤ 2 WANTs out; a WANT seen from someone else within 30 s on that
  channel suppresses ours (through the real memo).
- **Replies:** coalescing: WANTs at `t = 0, 2, 4` → one reply at `t = 5` with the
  smallest `since`, a WANT at `t = 6` isn't in it; 1 reply per channel per 30 s;
  small / large classification at 5 and 6 entries; a large reply stamps the gate, a
  second large ask inside 5 minutes is deferred and goes out when the gate opens (not
  dropped, exactly one); a changed window opens the gate early; **`since = tMin` is large
  and gated** (the bypass test); small replies continue at the 30 s gate while a large
  one is deferred; a large reply clears a covered small ask; a small ask that grows past
  5 entries becomes large; `n = 0` sends nothing and stamps nothing; a full reply is 8
  messages, sent as the budget admits, with the right entry count per message.
- **Channels:** `setChannel(ch, nil)` drops that channel's HELLO, buckets, in-progress
  messages and WANTs, and nothing on the other channel; PARTY → RAID keeps pending items
  and sends them on RAID; a bad wire value is ignored.
- **Combat hold:** held → nothing sent, `pump` returns `nil`; pending stays bounded under
  1 000 HELLOs from 300 peers and 1 000 WANTs while held; release → HELLO, replies, WANTs
  in that order within the budget; an in-progress reply resumes where it stopped.
- **Wake times:** each case above checks the returned wake time (due, gate, record
  expiry, in-flight release, never below `now + 1`, `nil` when idle).
- **Never throws:** every method with each argument replaced by `nil`, a string, `NaN`,
  `inf`, a table and the two hidden-value stand-ins (slice 1 §5.2) → no error;
  `SyncSchedule.new` without `memo` or `rand` errors.
- **Purity:** loads in the strict environment; `luacheck` clean; `check-apis.sh` passes;
  coverage ≥ 95%.

### 6.3 `spec/core_spec.lua` (whole AddOn under the stub)

- Login opens `db.global.ledgers[guid]` as schema 1 and sets `ns.ledger`; a second login
  reopens the same table (round trip).
- GUID `nil` at login, readable on the 3rd retry → opened then; unreadable for all 5
  attempts → no ledger, `Sync` not started, no key written to `ledgers`.
- A hidden GUID (`issecretvalue` true) → treated as unreadable, and **no table is indexed
  with it** (use a stand-in whose metamethods raise).
- Hidden or non-string name → opened with `me = {}`; a renamed character → `me.name`
  updated. Forever names → `me.name` is `"First Surname"`; our realm (spaced or not) in
  the slot, no readable realm, or a hidden slot or realm → the first name alone; a
  composed name failing the name rule → `me = {}`.
- Anchor: from the API (and rounded: `secs` ending in `:29` and `:31` seconds); API
  missing, erroring, returning `nil`, a string, `NaN`, `-1`, `604 861` or a hidden value →
  the fallback; region 1 and an unknown region → the US row.
- `ledgers` is a string → read-only empty ledger and the string is untouched;
  `ledgers[guid]` is a string → read-only, untouched; `Ledger.new` raising (a stubbed
  bad `GetServerTime`) → no ledger, no error escapes.
- `/ledger debug` toggles; on prints the report line; nothing prints while off; 20 lines
  in a second → 5 printed, the next allowed one starts with `(15 skipped)`; the
  existing `/ledger` version output still works.

### 6.4 `spec/sync_spec.lua` (the `Sync` glue, mostly through the harness)

Receive path, each hostile case by name:
- **unresolved sender:** PARTY sender not in the group → `unresolved`, `receive` not
  called (spy), nothing stored; GUILD sender not in the roster → `unresolved` and one
  roster request, a second one within 60 s requests nothing more.
- **sender that left the group:** entries arriving after the peer left → dropped; the
  peer's pending WANT is still bounded and harmless.
- **hidden-value stand-ins:** `issecretvalue` true for prefix, text, channel and sender
  in turn → `hidden`, `receive` not called; the two stand-in objects as each argument
  with `issecretvalue` false → no error escapes, nothing stored; the unit scan's
  `UnitGUID` or `UnitFullName` returning a stand-in or a hidden value → that unit is
  skipped, its sender `unresolved`; a hidden `GetNormalizedRealmName` → the sender is
  used as is.
- **group map (#54):** a member named `Target` / `focus` / `MOUSEOVER` while we target
  someone else → its entries go under its own GUID, never the target's, and a sender
  named like a token that no unit carries → `unresolved`; `UnitGUID` is only ever
  called with `player`, `partyN` or `raidN` (spy); two units with one key → both
  `unresolved`; `Mira` and `Mira-Stubrealm` → one GUID and one stored name; another
  realm, with a space or `-` in `UnitName`'s realm, still resolves; placeholder, dashed,
  hidden and over-long names skipped; a miss rescans the map at most once per 10 s and
  never sends a HELLO.
- **two-part names (#75, `spec/sync_names_spec.lua`):** `Sync.surname` cases; the
  two-part check waits while our realm or slot is unreadable, then holds; a party or
  raid member's bare sender resolves to their GUID and stores `"First Surname"`, a
  non-member doesn't; two Forever clients sync end to end; near misses (`"Mira Val"`),
  case changes, a first name alone, `"Mira-Vale"`, extra spaces and another realm's
  suffix → `unresolved`, our realm's suffix → the bare name; two members sharing a first
  name or a surname resolve apart; a name two units or rows claim → `unresolved`; every
  form a unit may give keys as the sender's, odd ones (a one-word name without a
  surname included) are skipped, so a one-word sender never borrows a member's GUID;
  maps built before the decision are emptied when it's made; `"Unknown"` until a
  rescan reads the name; the roster with or without our realm's suffix; the real client
  under the stub.
- **channels:** WHISPER, `INSTANCE_CHAT`, CHANNEL, SAY, `nil` → `channel`, nothing sent.
- **other prefixes:** ignored, no stats, no debug line.
- **our own echo:** counted as `self`, no debug line.
- **name normalization:** `Aldric` and `Aldric-Stubrealm` resolve to the same GUID and
  store the same name; a 97-byte sender → `unresolved`.
- **guild map:** duplicate names → both unresolved; rows with hidden or invalid GUIDs
  skipped; a roster of 2 500 rows reads 2 000; rebuilt at most once per 10 s with a
  trailing rebuild; cleared on leaving the guild.
- **read-only ledger:** no prefix registered, no frame events, `CHAT_MSG_ADDON` stores
  nothing, roster and guild events send nothing.
- **prefix registration failing** → sync off.
- **an error inside a handler** (a `receive` that raises, stubbed) → no error escapes,
  `stats.errors` counts it.

Send path and end to end:
- **Two clients, party:** A has 12 own entries, B none. They group → both HELLO within
  5–15 s (A only; B's window is empty) → B WANTs within 1–5 s → A replies after the 5 s
  coalescing, 3 messages, `BULK` → B holds exactly A's 12 entries under A's GUID and
  name, and nothing under anyone else.
- **`WindowChanged`:** A signs one more → one HELLO per available channel → B asks
  (`since` = the newest held) → a small reply → B holds 13.
- **a flood from one peer:** a hostile client sends 1 000 HELLOs with fresh digests and
  500 `W1:<A>:0` in 10 minutes → A sends ≤ 2 WANTs to it and ≤ 1 large reply per
  channel per 5 minutes (small ones only if asked with a recent `since`), never over the
  budget; the hostile client's messages past 40 a minute are `rate` drops.
- **WANT spam at `since = 0` and at `since = tMin`:** ≤ 1 large reply per channel per 5
  minutes each; an honest newcomer who asks inside the gate gets the deferred reply
  when it opens.
- **digest churn:** see the flood case; also no pending-WANT growth past one entry.
- **combat during a reply:** A starts an 8-message reply; after 3 messages
  `PLAYER_REGEN_DISABLED` → nothing more is sent; `PLAYER_REGEN_ENABLED` with combat back
  on at 3 s → still held; the next `PLAYER_REGEN_ENABLED` with combat off → after 3 s the
  pump order of §3.5.6 applies: a HELLO that came due during the fight first, then the
  reply's remaining 5 messages, then any new reply, then WANTs. Entries B sends during
  the fight are stored.
- **combat check that errors or never clears:** `InCombatLockdown` raising, or returning
  a hidden value, holds sync; once it returns `false`, the 30 s held re-check resumes it
  without a `PLAYER_REGEN_ENABLED`.
- **roster changes mid-sync:** party → raid while a reply is pending → it goes out on
  RAID; leaving the group mid-reply → the rest is dropped and nothing is sent on PARTY;
  only members leaving → no HELLO; a new member → one HELLO; a member who leaves and
  rejoins → one HELLO; `GetNumGroupMembers` returning 500 or a hidden value → the scan
  stays within 40 units or none.
- **group before guild:** a peer in both our party and our guild HELLOs on both → the
  WANT goes to PARTY; a WANT for us on PARTY never causes a GUILD reply.
- **deferred send callbacks:** with every callback arriving 1 s late (in the two-client
  and the raid runs), an 8-message reply finishes within about 10 s, not 30 s per 2
  messages.
- **one live timer:** after one simulated hour in a guild with a HELLO every 2 s (and
  a hostile one every second), no more than 6 timers are outstanding and only one
  pumps at a time.
- **bad clock in the glue pump:** `GetServerTime` returning `nil`, `NaN` or a string →
  the pump skips and retries; nothing is sent, nothing throws.
- **only our own texts:** in the flood and raid runs, every message a client hands over
  decodes as H, W or E, and every entry in its E messages is one of its own window's
  entries.
- **guild:** first HELLO 60–120 s after login, then every 1 200–1 500 s; no HELLO from an
  empty window.
- **real ChatThrottleLib:** one test through the real library (advance the stub's
  `GetTime` past its start-up throttle) shows our text reaching
  `C_ChatInfo.SendAddonMessage` with prefix `InnLedger`, the wire channel and no target.
- **a 40-player raid from scratch** (the traffic model check, slice 1 §5.3): 40 clients,
  each with 40 own entries, form a raid at once. Assert: after 10 simulated minutes every
  client holds every other client's 40 entries; **no client dropped an honest message as
  `rate`**; no client handed over more than 30 messages or 60 entries in any 60 s. If
  this fails, don't tune the limits: report it (the limits are a settled decision).
- **debug output:** with the log on, a hostile name, a pipe-escape message and a
  WHISPER channel called `|cffff0000x` produce lines that contain none of those strings.

### 6.5 Lint and guards

`luacheck .` clean (glue globals added to `.luacheckrc`'s `wow` list as they're used);
`sh scripts/check-apis.sh` passes, including a scratch check that `InCombatLockdown` in
`Core.lua` still fails and in `Sync.lua` passes; `check-libs.sh`, `check-links.sh`,
coverage floors all pass.

## 7. Acceptance criteria

Per implementation ticket (§9); the reviewer verifies each against this spec.

- [ ] `Core` implements §3.2 and §3.8 (the sink and toggle); §6.3 passes.
- [ ] `SyncSchedule.lua` implements §3.5 and the hold state of §3.6 with the constants in
      §3.5.2; §6.2 passes; coverage ≥ 95% with its floor in `check-coverage.sh`.
- [ ] `Sync.lua` implements §3.3, §3.4, §3.6 and §3.7; §6.4 passes, including the 40-raid
      traffic check.
- [ ] The `combat state` rule split of §5.2 is in `check-apis.sh`, citing the decision.
- [ ] `busted`, `luacheck`, `check-apis.sh`, `check-libs.sh`, `check-links.sh` and
      `check-coverage.sh` pass locally and in CI.
- [ ] No AceComm, AceTimer or direct `SendAddonMessage` call; every send goes through
      ChatThrottleLib at `BULK`.
- [ ] The reviewer did a security-level review of `Sync` and `SyncSchedule` (sender
      resolution, hidden values, what reaches `SyncProtocol.receive`, send bounds) and
      states that it tried hostile input of its own.

## 8. Unverified client facts this spec relies on

Designed within retail's behavior; each is on the #12 checklist in
[platform-forever.md](../platform-forever.md#verification-checklist-needs-a-forever-client-beta-until-2026-10-21-or-launch-2026-11-04).

| Fact | Design assumption | If it's different |
|---|---|---|
| Addon message size | 255 bytes | slice 1 constants change |
| Instance groups' chat type | PARTY / RAID | `INSTANCE_CHAT` needs a decision entry and a `SyncProtocol` channel change |
| Hidden senders outside combat | normal strings | the hidden check drops everything; sync can't work there |
| `CHAT_MSG_ADDON` sender format | ✅ seen (beta): `"First Surname"`, no realm; the key is the bare form on a two-part client (§3.4, #75) | `keyOf` changes |
| `GetNormalizedRealmName()` on a mega-realm | ✅ seen (beta): `ClassicBetaPvP` | `keyOf` uses the sender as is, and the client can't tell it has two-part names |
| `UnitFullName("player")` / `UnitName("player")` | ✅ seen (beta): `"First", "Surname"`, never a realm | the two-part check (§3.4) changes |
| `UnitFullName(partyN)` (#54, #75) | like `player` on Forever: `"First", "Surname"` (or the whole name with `nil` or our realm); retail: the name plus the realm in the sender's form once spaces and `-` are removed, `nil` or empty for our realm; `UNKNOWNOBJECT` until a name loads | the group map's key changes; until then group senders are unresolved (fails closed) |
| `GetGuildRosterInfo` name on Forever | `"First Surname"`, with or without our realm's suffix | the guild map's key changes; until then guild senders are unresolved |
| Home vs instance groups | `LE_PARTY_CATEGORY_HOME` exists; instance-only groups aren't sent to | the group check changes |
| `GetGuildRosterInfo` GUID | 17th return, a player GUID | the guild map changes |
| `GUILD_ROSTER_UPDATE` / `C_GuildInfo.GuildRoster()` | as retail | the refresh changes |
| `UnitGUID("player")` and the weekly-reset API at `PLAYER_LOGIN` | readable | the retry covers a short delay |
| Weekly reset per region | US row known; others from #12 | fill `Core.RESET_FALLBACK` |
| `RegisterAddonMessagePrefix` result | `true` or the result enum | accept list in §3.3.2 |
| `InCombatLockdown` and `PLAYER_REGEN_*` | as retail | the hold changes |
| ChatThrottleLib's send callback | runs with `didSend` | the in-flight release covers a silent one |

## 9. Implementation tickets

Filed under #41, in order:

1. **#44 `Core`: open the character's ledger at login** — §3.2, §3.8, stub additions of
   §6.1, §6.3. No blockers.
2. **#45 `SyncSchedule`: pure send schedule** — §3.5, §3.6 (hold state), §6.2, coverage
   floor, TOC / `load.PURE` / `.luacov`, the architecture row. No blockers (parallel to #44).
3. **#46 `Sync` receive path** — §3.3, §3.4, the harness of §6.1, the receive cases of §6.4.
   **Leaves out everything combat** (§3.3.2 step 3, the `PLAYER_REGEN_*` registrations,
   `combatNow`): until ticket 4 splits the rule (§5.2), those names fail
   `forbidden-apis` in `Sync.lua`. Blocked by #44 and #45.
4. **#47 `Sync` send path and combat hold** — §3.5.1 triggers, §3.5.6's glue pump, §3.6
   (including §3.3.2 step 3 and the `PLAYER_REGEN_*` events), §3.7, §5.2 in the same PR,
   and the send and end-to-end cases of §6.4 (incl. the 40-raid check). Blocked by #46.
5. **#54 group map** (filed after #46's review) — §3.4 step 3 and "The group map", the
   group-map cases of §6.4, §8's `UnitFullName` row. Built in PR #59; #41 closed.

## Assumptions (listed for the maintainer)

- The guild HELLO interval (first after 60–120 s, then every 20–25 minutes) is fine for a
  collection AddOn: a guildmate's new signature arrives within seconds through
  `WindowChanged`, and a newcomer gets everyone's windows within about 25 minutes.
- A big guild's newcomer may take several HELLO rounds to hear from everyone (200 pending
  WANTs, 12 WANTs a minute). That's acceptable for v1.
- Players who haven't signed anything send nothing at all.
- Storing names in full `Name-Realm` form is right on a realm client; the UI trims our
  own realm. On Forever the stored form is the bare `"First Surname"` (#75).

## Open questions (maintainer)

- None. The debug toggle wording was settled on 2026-09-27 (§3.8).
