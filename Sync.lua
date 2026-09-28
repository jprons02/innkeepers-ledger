-- Sync (glue): addon-message transport, sender resolution, group and guild triggers, the
-- combat hold and the pump that drives SyncSchedule.
-- Spec: docs/specs/sync-glue.md (sections 3.3 to 3.8). Every message from another player
-- is hostile. The only way into the ledger is SyncProtocol.receive, with a sender built by
-- `resolve` below from the event's own sender argument (the own-signature rule). The only
-- texts sent are SyncSchedule's encodings of our own share window.
--
-- A client is an instance with its client functions injected (`Sync.new(deps)`), so tests
-- can run several in one Lua state; `ns.Sync:Start()` builds the one real client. Nothing
-- here reads a global except `Sync:Start()`, which gathers them into `deps.api`.
--
-- Event handlers and send callbacks never send: they update state and request a pump.
-- Exactly one pump timer is live at a time (spec 3.5.6).
--
-- Combat state: reading whether we're in combat is allowed here and only here
-- (docs/decisions.md, 2026-09-27: "Sync may read combat state, and players are told").
local _, ns = ...

local Ledger = ns.Ledger
local SP = ns.SyncProtocol
local SyncSchedule = ns.SyncSchedule

local Sync = {}
ns.Sync = Sync

local find, floor, min, select = string.find, math.floor, math.min, select
local gsub, sub = string.gsub, string.sub

local PREFIX = "InnLedger"
local CHANNELS = SP.CHANNELS      -- PARTY, RAID, GUILD
local SENDER_MAX = 96             -- bytes in a sender or roster name
local REALM_MAX = 48              -- bytes in a realm name
local ROSTER_ROWS = 2000          -- guild roster rows read, at most
local ROSTER_GAP = 60             -- at most one roster request per this many s
local REBUILD_GAP = 10            -- at most one guild map rebuild per this many s
local GROUP_MAX = 40              -- group units scanned, at most (plus "player" in a party)
local RESCAN_GAP = 10             -- a group map miss rescans at most once per this many s
local PLACEHOLDER = "Unknown"     -- a name not loaded yet, when UNKNOWNOBJECT isn't readable
local PUMP_HORIZON = 5            -- the pump timer never targets more than this many s out
local BAD_CLOCK_RETRY = 5         -- a pump that read a bad clock retries after this many s
local HELD_RECHECK = 30           -- while held, re-check combat this often, s
local LIMITS = SyncSchedule.LIMITS
local T_MAX = Ledger.LIMITS.tMax

-- What a sent text is, by its first byte (our own encoders only).
local KINDS = { H = "hello", W = "want", E = "entries" }

-- The events the real client registers; onEvent ignores any other.
local EVENTS = {
  "CHAT_MSG_ADDON", "GROUP_ROSTER_UPDATE", "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE",
  "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
}

local function isInt(x, lo, hi)
  return type(x) == "number" and x == x and x % 1 == 0 and x >= lo and x <= hi
end

-- The first return of a client function, or nil if it's missing or raises.
local function call(fn, ...)
  if type(fn) ~= "function" then
    return nil
  end
  local ok, value = pcall(fn, ...)
  if ok then
    return value
  end
  return nil
end

local function tableOr(v)
  return type(v) == "table" and v or {}
end

-- A reason or kind code for stats and debug lines: our own lower-case words only.
local function code(s)
  if type(s) == "string" and #s <= 16 and find(s, "^[a-z_]+$") then
    return s
  end
  return "unknown"
end

-- A channel name for a debug line: one of ours, else "other". Never the peer's string.
local function channelName(channel)
  if type(channel) == "string" and CHANNELS[channel] then
    return channel
  end
  return "other"
end

-- One form per character: "Name-Realm". A name that has a realm is used as is; without a
-- readable realm, the name stays as it is.
local function fullName(name, realm)
  if realm == nil or find(name, "-", 1, true) then
    return name
  end
  return name .. "-" .. realm
end

-- The 1st and 17th returns of a pcall'd GetGuildRosterInfo (the GUID is the 17th).
local function rosterRow(ok, name, ...)
  if not ok then
    return nil, nil
  end
  return name, (select(16, ...))
end

local function newStats()
  return {
    received = {}, dropped = {}, added = 0, dup = 0, rejected = 0, evicted = 0,
    sent = {}, sendFailed = 0, errors = 0,
  }
end

local Client = {}
Client.__index = Client

-- Sync.new(deps): a client (spec 3.3.1). deps = { ledger, inns, phrases, seals, phraseOk?,
-- debug, onEntries?, api }. Raises only on a caller bug (no deps or api table, no
-- api.random for the schedule).
function Sync.new(deps)
  if type(deps) ~= "table" or type(deps.api) ~= "table" then
    error("Sync.new: deps and deps.api must be tables", 2)
  end
  local api = deps.api
  local memo = SP.newWantMemo()
  local limiter = SP.newLimiter()
  local self = setmetatable({
    deps = deps,
    api = api,
    ledger = deps.ledger,
    limiter = limiter,
    memo = memo,
    schedule = SyncSchedule.new({ memo = memo, rand = api.random }),
    stats = newStats(),
    running = false,
    guild = {},            -- full name -> GUID, from the server's roster
    rebuildAt = nil,       -- when the guild map was last rebuilt
    rebuildGen = 0,        -- bumped to cancel a pending trailing rebuild
    rebuildPending = false,
    rosterAt = nil,        -- when the roster was last requested
    members = {},          -- GUIDs of the other group members, from our unit scan
    group = {},            -- full name -> GUID, from the same scan (us included)
    rescanAt = nil,        -- when a group map miss last rescanned
    guildOn = false,       -- the GUILD channel is available
    timerGen = 0,          -- the live pump timer's generation; older timers are stale
    timerLive = false,     -- a pump timer is armed and hasn't fired
    timerAt = nil,         -- when it fires (nil if armed while the clock was bad)
    held = false,          -- combat hold
    combatGen = 0,         -- bumped on entering combat and on PLAYER_REGEN_ENABLED
    recheckGen = 0,        -- the held re-check timer's generation, the same way
    recheckLive = false,
    recheckAt = nil,
    triggersPending = false, -- the clock was bad at start; the pump runs the triggers
  }, Client)
  -- What the schedule may do: read our share window and a signer's held entries, and send.
  self.io = {
    window = function() return self.ledger:shareWindow(SP.SHARE_MAX) end,
    held = function(guid) return self.ledger:signerEntries(guid) end,
    send = function(wire, text, token) return self:send(wire, text, token) end,
  }
  -- One reused ctx for SyncProtocol.receive; `now` and `selfGUID` are set per message.
  self.ctx = {
    ledger = deps.ledger,
    limiter = limiter,
    wantMemo = memo,
    inns = tableOr(deps.inns),
    phrases = tableOr(deps.phrases),
    seals = tableOr(deps.seals),
    phraseOk = type(deps.phraseOk) == "function" and deps.phraseOk or nil,
  }
  return self
end

-- True for a hidden ("secret") value. Fails closed: an error while checking counts as
-- hidden. Missing issecretvalue means nothing is hidden. Touches nothing else.
function Client:hidden(value)
  local isSecret = self.api.issecretvalue
  if type(isSecret) ~= "function" then
    return false
  end
  local ok, result = pcall(isSecret, value)
  return not ok or (result ~= false and result ~= nil)
end

-- The server time if it's a readable integer in range, else nil.
function Client:now()
  local now = call(self.api.GetServerTime)
  if self:hidden(now) or not isInt(now, 0, T_MAX) then
    return nil
  end
  return now
end

-- One debug line. Callers pass only our own words, codes, numbers, channel names from
-- our set and GUIDs that passed validGUID (spec 3.8).
function Client:debug(line)
  local fn = self.deps.debug
  if type(fn) == "function" then
    pcall(fn, line)
  end
end

-- Runs fn(self, ...) in pcall. An error is counted and logged by `label` (our own event or
-- step name), never with its text, which could echo peer data.
function Client:guard(label, fn, ...)
  local ok, result = pcall(fn, self, ...)
  if not ok then
    self.stats.errors = self.stats.errors + 1
    self:debug("sync: error in " .. label)
    return nil
  end
  return result
end

function Client:drop(reason, channel, guid)
  reason = code(reason)
  local dropped = self.stats.dropped
  dropped[reason] = (dropped[reason] or 0) + 1
  if reason == "self" then
    return -- our own echo is normal
  end
  local line = "sync: drop " .. reason
  if channel ~= nil then
    line = line .. " " .. channelName(channel)
  end
  if guid ~= nil then
    line = line .. " " .. guid
  end
  self:debug(line)
end

-- True unless the value is missing, false or hidden (a hidden answer counts as "no").
function Client:yes(v)
  return not self:hidden(v) and v ~= nil and v ~= false
end

-- ---------------------------------------------------------------------------
-- The pump and its one live timer (spec 3.5.6).

local fire

-- Schedules the pump timer for `now + delay` under a fresh generation, which makes every
-- older timer stale. It counts as live only once `After` has returned, so a call that
-- raises leaves no phantom timer and the next request arms a fresh one.
function Client:arm(now, delay)
  local after = self.api.After
  if type(after) ~= "function" then
    return
  end
  self.timerGen = self.timerGen + 1
  local gen = self.timerGen
  self.timerLive, self.timerAt = false, nil
  after(delay, function()
    self:guard("pump", fire, gen)
  end)
  self.timerLive = true
  self.timerAt = now ~= nil and now + delay or nil
end

-- Asks for a pump at `at` (nil = idle). A live timer due no later than `at` already
-- covers it; else the timer is re-armed for min(at, now + 5). A live timer due more than
-- 5 s in the past was lost and doesn't count. With a bad clock, any live timer covers it.
function Client:requestPump(at)
  if at == nil then
    return
  end
  local now = self:now()
  if now == nil then
    if not self.timerLive then
      self:arm(nil, BAD_CLOCK_RETRY)
    end
    return
  end
  local live = self.timerAt
  if self.timerLive and live ~= nil and live <= at and live >= now - PUMP_HORIZON then
    return
  end
  local target = min(at, now + PUMP_HORIZON)
  if target < now + 1 then
    target = now + 1
  end
  self:arm(now, target - now)
end

-- Asks for a pump in one second (event handlers and send callbacks).
function Client:poke()
  local now = self:now()
  self:requestPump(now ~= nil and now + 1 or 0)
end

local function pump(self)
  if not self.running then
    return
  end
  local now = self:now()
  if now == nil then
    -- A bad clock: no arithmetic on it; try again later under a fresh generation.
    self:arm(nil, BAD_CLOCK_RETRY)
    return
  end
  if self.triggersPending then
    -- The clock was bad at start: run the start-time triggers now.
    self.triggersPending = false
    self:onGroup(now)
    self:onGuild(now)
    self:rebuildGuild(now)
  end
  if not self.held and self:combatNow() then
    self:hold()
  elseif self.held then
    self:armRecheck() -- re-arms a re-check that was lost
  end
  self:requestPump(self.schedule:pump(now, self.io))
end

-- A timer's callback: a stale generation returns at once; the current one pumps.
function fire(self, gen)
  if gen ~= self.timerGen then
    return
  end
  self.timerLive, self.timerAt = false, nil
  pump(self)
end

function Client:pump()
  self:guard("pump", pump)
end

-- ---------------------------------------------------------------------------
-- Transport (spec 3.7).

local function sendDone(self, token, didSend)
  self.schedule:sendDone(token)
  if didSend == false then
    self.stats.sendFailed = self.stats.sendFailed + 1
    self:debug("sync: send failed")
  end
  self:poke() -- never a pump here: this may run inside api.send or the library's queue
end

-- io.send for the schedule: hands `text` to the transport on `wire`. False only if
-- nothing reached it (no send function, or it raised or returned false).
function Client:send(wire, text, token)
  local send = self.api.send
  local ok, result = false, nil
  if type(send) == "function" then
    ok, result = pcall(send, text, wire, function(_, didSend)
      self:guard("send", sendDone, token, didSend)
    end)
  end
  if not ok or result == false then
    self.stats.sendFailed = self.stats.sendFailed + 1
    self:debug("sync: send failed " .. channelName(wire))
    return false
  end
  local kind = KINDS[sub(text, 1, 1)] or "unknown"
  local sent = self.stats.sent
  sent[kind] = (sent[kind] or 0) + 1
  self:debug("sync: sent " .. kind .. " " .. channelName(wire))
  return true
end

-- ---------------------------------------------------------------------------
-- Combat hold (spec 3.6).

-- True unless the client says plainly that we're not in combat. A missing function means
-- not in combat; an error, a hidden value or anything but false means hold (fail safe).
function Client:combatNow()
  local check = self.api.InCombatLockdown
  if type(check) ~= "function" then
    return false
  end
  local ok, v = pcall(check)
  return not (ok and not self:hidden(v) and v == false)
end

local recheck

-- Starts the held re-check timer unless one is live. A live one due more than 5 s ago
-- was lost, and one due further out than 30 s (the clock went back) is replaced.
function Client:armRecheck()
  local after = self.api.After
  if type(after) ~= "function" then
    return
  end
  local now, live = self:now(), self.recheckAt
  if self.recheckLive and (live == nil or now == nil
    or (live >= now - PUMP_HORIZON and live <= now + HELD_RECHECK)) then
    return
  end
  self.recheckGen = self.recheckGen + 1
  local gen = self.recheckGen
  self.recheckLive, self.recheckAt = false, nil
  after(HELD_RECHECK, function()
    self:guard("recheck", recheck, gen)
  end)
  self.recheckLive = true
  self.recheckAt = now ~= nil and now + HELD_RECHECK or nil
end

-- Enters the hold: the schedule sends nothing until a resume check finds us out of combat.
function Client:hold()
  self.combatGen = self.combatGen + 1
  if not self.held then
    self.held = true
    self.schedule:setHeld(true)
    self:debug("sync: held")
  end
  self:armRecheck()
end

-- The resume check: out of combat, release and pump; else stay held.
function Client:tryResume()
  if not self.held or self:combatNow() then
    return
  end
  self.held = false
  self.schedule:setHeld(false)
  self:debug("sync: resumed")
  pump(self)
end

function recheck(self, gen)
  if gen ~= self.recheckGen then
    return
  end
  self.recheckLive, self.recheckAt = false, nil
  if not self.held then
    return
  end
  self:tryResume()
  if self.held then
    self:armRecheck()
  end
end

local function resume(self, gen)
  if gen == self.combatGen then
    self:tryResume()
  end
end

-- ---------------------------------------------------------------------------
-- Triggers (spec 3.5.1).

-- The group functions' argument: LE_PARTY_CATEGORY_HOME when it exists, so PARTY is
-- never sent into an instance-only group.
function Client:groupCall(fn)
  local category = self.api.LE_PARTY_CATEGORY_HOME
  if type(category) == "number" and not self:hidden(category) then
    return call(fn, category)
  end
  return call(fn)
end

-- The client's placeholder for a name that hasn't loaded yet.
function Client:placeholder()
  local name = self.api.UNKNOWNOBJECT
  if type(name) == "string" and not self:hidden(name) then
    return name
  end
  return PLACEHOLDER
end

-- The name and realm of one of our own units: UnitFullName, or UnitName where it's
-- missing. Only ever called with "player", "partyN" or "raidN".
local function unitName(api, unit)
  local fn = api.UnitFullName
  if type(fn) ~= "function" then
    fn = api.UnitName
  end
  if type(fn) ~= "function" then
    return nil, nil
  end
  local ok, name, realm = pcall(fn, unit)
  if not ok then
    return nil, nil
  end
  return name, realm
end

-- The group map key for a unit's name and realm, or nil to skip the unit (spec 3.4). The
-- realm loses its spaces and dashes (the GetNormalizedRealmName form); none means ours.
function Client:unitKey(name, realm, ourRealm, placeholder)
  if self:hidden(name) or self:hidden(realm) or type(name) ~= "string" or #name < 1
    or #name > SENDER_MAX or find(name, "-", 1, true) or name == placeholder then
    return nil
  end
  if realm ~= nil then
    if type(realm) ~= "string" then
      return nil
    end
    realm = gsub(realm, "[%s%-]", "")
    if #realm > REALM_MAX then
      return nil
    end
    if realm ~= "" then
      return name .. "-" .. realm
    end
  end
  return fullName(name, ourRealm)
end

-- The unit scan: in a group, returns whether it's a raid, the set of the other members'
-- GUIDs (hidden, invalid and own GUIDs skipped; at most 40 units) and the group map, full
-- name -> GUID, us included (a unit whose name can't be read is left out, and so is a
-- name two units claim). Not in a group: nil. The one place group units are read; no
-- string from a peer ever reaches a client function here.
function Client:scanGroup()
  local api = self.api
  if not self:yes(self:groupCall(api.IsInGroup)) then
    return nil
  end
  local raid = self:yes(self:groupCall(api.IsInRaid))
  local n = self:groupCall(api.GetNumGroupMembers)
  if self:hidden(n) or type(n) ~= "number" or n ~= n then
    n = 0
  end
  n = floor(min(n, GROUP_MAX))
  local unit, last = "party", n - 1
  if raid then
    unit, last = "raid", n
  end
  local own = self.ledger:ownerGUID()
  local ourRealm, placeholder = self:realm(), self:placeholder()
  local set, map, claimed = {}, {}, {}
  local function add(u, guid)
    local name, realm = unitName(api, u)
    local key = self:unitKey(name, realm, ourRealm, placeholder)
    if key == nil then
      return
    end
    if claimed[key] then
      map[key] = nil
    else
      claimed[key] = true
      map[key] = guid
    end
  end
  if not raid and Ledger.validGUID(own) then
    add("player", own) -- a raid lists us among raid1..raidN
  end
  for i = 1, last do
    local u = unit .. i
    local guid = call(api.UnitGUID, u)
    if not self:hidden(guid) and Ledger.validGUID(guid) then
      if guid ~= own then
        set[guid] = true
      end
      add(u, guid)
    end
  end
  return raid, set, map
end

-- GROUP_ROSTER_UPDATE and start: set the GROUP channel and ask for a HELLO when the scan
-- holds someone the last one didn't. Members only leaving sends nothing.
function Client:onGroup(now)
  local raid, set, map = self:scanGroup()
  if set == nil then
    self.schedule:setChannel("GROUP", nil)
    self.members, self.group = {}, {}
    return
  end
  self.group = map
  self.schedule:setChannel("GROUP", raid and "RAID" or "PARTY")
  local new = false
  for guid in next, set do
    if not self.members[guid] then
      new = true
      break
    end
  end
  if new then
    if now == nil then
      return -- keep the old set, so the next update still finds them new
    end
    self.schedule:requestHello("GROUP", now, LIMITS.helloDelay[1], LIMITS.helloDelay[2])
    self:requestPump(now + 1)
  end
  self.members = set
end

-- PLAYER_GUILD_UPDATE and start: joining makes GUILD available and asks for the first
-- guild HELLO; leaving drops the channel and the guild map.
function Client:onGuild(now)
  if self:inGuild() then
    self:requestRoster(now)
    if not self.guildOn and now ~= nil then
      self.guildOn = true
      self.schedule:setChannel("GUILD", "GUILD")
      self.schedule:requestHello("GUILD", now, LIMITS.guildFirst[1], LIMITS.guildFirst[2])
      self:requestPump(now + 1)
    end
    return
  end
  self.guildOn = false
  self.schedule:setChannel("GUILD", nil)
  -- Clear the map, cancel a pending rebuild, and let a rejoin request the roster at once.
  self.guild = {}
  self.rebuildGen = self.rebuildGen + 1
  self.rebuildPending = false
  self.rosterAt = nil
end

local function windowChanged(self)
  local now = self:now()
  if now == nil then
    return
  end
  for _, ch in ipairs({ "GROUP", "GUILD" }) do
    self.schedule:requestHello(ch, now, LIMITS.helloDelay[1], LIMITS.helloDelay[2])
  end
  self:requestPump(now + 1)
end

-- Our share window changed (Sign calls this after addOwn returns "added"): a HELLO on
-- each available channel.
function Client:windowChanged()
  if self.running then
    self:guard("WindowChanged", windowChanged)
  end
end

-- ---------------------------------------------------------------------------
-- Start (spec 3.3.2).

-- True if the client accepted our prefix: true, 0, or the result enum's Success or
-- DuplicatePrefix when that enum exists.
function Client:registerPrefix()
  local register = self.api.RegisterPrefix
  if type(register) ~= "function" then
    return false
  end
  local ok, result = pcall(register, PREFIX)
  if not ok or self:hidden(result) or result == nil then
    return false
  end
  if result == true or result == 0 then
    return true
  end
  local enum = self.api.Enum
  local results = type(enum) == "table" and enum.RegisterAddonMessagePrefixResult or nil
  if type(results) ~= "table" then
    return false
  end
  return result == results.Success or result == results.DuplicatePrefix
end

local function start(self)
  if self.running then
    return true
  end
  local ledger = self.ledger
  if type(ledger) ~= "table" then
    self:debug("sync: off (no ledger)")
    return false
  end
  if ledger.readOnly ~= false then
    self:debug("sync: off (read-only)")
    return false
  end
  if not self:registerPrefix() then
    self:debug("sync: off (prefix)")
    return false
  end
  self.running = true
  self:debug("sync: on")
  local now = self:now()
  if self:combatNow() then
    self:hold()
  else
    self.schedule:setHeld(false)
  end
  -- A /reload inside a group or guild syncs without waiting for an event.
  self:onGroup(now)
  self:onGuild(now)
  if now ~= nil then
    self:rebuildGuild(now)
  else
    -- A bad clock at start: the first pump with a good one runs the triggers again.
    self.triggersPending = true
    self:requestPump(0)
  end
  return true
end

-- Starts the client. A missing or read-only ledger, or a refused prefix, turns sync off
-- for the session: no events are handled and nothing is sent. Returns true if running.
function Client:start()
  return self:guard("start", start) == true
end

-- ---------------------------------------------------------------------------
-- Guild map (spec 3.4).

function Client:inGuild()
  local v = call(self.api.IsInGuild)
  return not self:hidden(v) and v ~= nil and v ~= false
end

-- Requests a roster refresh, at most once per ROSTER_GAP (a clock that went back allows
-- one at once).
function Client:requestRoster(now)
  local last = self.rosterAt
  if now == nil or (last ~= nil and now >= last and now < last + ROSTER_GAP) then
    return
  end
  self.rosterAt = now
  call(self.api.GuildRoster)
end

-- The realm to complete a bare name with, or nil if it isn't readable.
function Client:realm()
  local realm = call(self.api.GetNormalizedRealmName)
  if self:hidden(realm) or type(realm) ~= "string" or #realm < 1 or #realm > REALM_MAX then
    return nil
  end
  return realm
end

-- Rebuilds name -> GUID from the server's roster. Hidden or invalid rows are skipped, and
-- a name two rows claim is left out (ambiguous means unresolved).
function Client:rebuildGuild(now)
  self.rebuildAt = now
  local map, claimed = {}, {}
  local rosterInfo = self.api.GetGuildRosterInfo
  if self:inGuild() and type(rosterInfo) == "function" then
    local n = call(self.api.GetNumGuildMembers)
    if self:hidden(n) or type(n) ~= "number" or n ~= n then
      n = 0
    end
    local realm = self:realm()
    for i = 1, min(n, ROSTER_ROWS) do
      local name, guid = rosterRow(pcall(rosterInfo, i))
      if not self:hidden(name) and not self:hidden(guid)
        and type(name) == "string" and #name >= 1 and #name <= SENDER_MAX
        and Ledger.validGUID(guid) then
        local key = fullName(name, realm)
        if claimed[key] then
          map[key] = nil
        else
          claimed[key] = true
          map[key] = guid
        end
      end
    end
  end
  self.guild = map
end

local function trailingRebuild(self, gen)
  if gen ~= self.rebuildGen then
    return -- cancelled (left the guild) or replaced
  end
  self.rebuildPending = false
  local now = self:now()
  if now ~= nil then
    self:rebuildGuild(now)
  end
end

-- ---------------------------------------------------------------------------
-- Receive (spec 3.3.3 and 3.4).

-- Whether a group map miss may rescan now: at most once per RESCAN_GAP (a clock that
-- went back allows one at once). The rescan replaces the map only, never the member set.
function Client:rescanDue(now)
  local last = self.rescanAt
  if now == nil or (last ~= nil and now >= last and now < last + RESCAN_GAP) then
    return false
  end
  self.rescanAt = now
  return true
end

-- { guid, name } for the sender of a message on `channel`, or nil (unresolved).
function Client:resolve(channel, sender, now)
  if type(sender) ~= "string" or #sender < 1 or #sender > SENDER_MAX then
    return nil
  end
  local full = fullName(sender, self:realm())
  local guid
  if channel == "GUILD" then
    guid = self.guild[full]
    if guid == nil then
      self:requestRoster(now)
      return nil
    end
  else
    -- Only compared with names our own unit scan read; never handed to a client function.
    guid = self.group[full]
    if guid == nil and self:rescanDue(now) then
      local _, _, map = self:scanGroup()
      self.group = map or {}
      guid = self.group[full]
    end
    if guid == nil then
      return nil
    end
  end
  if self:hidden(guid) or not Ledger.validGUID(guid) then
    return nil
  end
  return { guid = guid, name = full }
end

function Client:dispatch(result, channel, who, now)
  local stats = self.stats
  local kind = code(result.kind)
  stats.received[kind] = (stats.received[kind] or 0) + 1
  local line = "sync: got " .. kind .. " " .. channelName(channel) .. " " .. who.guid
  if kind == "hello" then
    self.schedule:onHello(who.guid, channel, result.count, result.digest, now)
    self:requestPump(now + 1)
  elseif kind == "want" then
    self.schedule:onWant(channel, result.since, self.ledger:shareWindow(SP.SHARE_MAX), now)
    self:requestPump(now + 1)
  elseif kind == "entries" then
    local added, dup, dropped, rejected = result.added, result.dup, result.dropped,
      result.rejected
    stats.added = stats.added + added
    stats.dup = stats.dup + dup
    stats.evicted = stats.evicted + dropped
    stats.rejected = stats.rejected + rejected
    line = line .. " added " .. added .. " dup " .. dup .. " evicted " .. dropped
      .. " rejected " .. rejected
    if added > 0 and type(self.deps.onEntries) == "function" then
      self.deps.onEntries()
    end
  end
  self:debug(line)
end

local handlers = {}

function handlers.CHAT_MSG_ADDON(self, prefix, text, channel, sender)
  -- 1. Hidden values first: nothing else touches the arguments before this.
  if self:hidden(prefix) or self:hidden(text) or self:hidden(channel) or self:hidden(sender) then
    return self:drop("hidden")
  end
  -- 2. Other AddOns' traffic: not counted, not logged.
  if type(prefix) ~= "string" or prefix ~= PREFIX then
    return
  end
  -- 3. PARTY, RAID and GUILD only.
  if type(channel) ~= "string" or not CHANNELS[channel] then
    return self:drop("channel", channel)
  end
  -- 4. Sender resolution.
  local now = self:now()
  local who = self:resolve(channel, sender, now)
  if who == nil then
    return self:drop("unresolved", channel)
  end
  -- 5-6. Everything else is SyncProtocol's.
  local ctx = self.ctx
  ctx.now = now
  ctx.selfGUID = self.ledger:ownerGUID()
  local result, reason = SP.receive(text, channel, who, ctx)
  if result == nil then
    return self:drop(reason, channel, who.guid)
  end
  -- 7. Dispatch.
  self:dispatch(result, channel, who, now)
end

function handlers.GUILD_ROSTER_UPDATE(self)
  local now = self:now()
  if now == nil then
    return
  end
  local last = self.rebuildAt
  if last == nil or now < last or now >= last + REBUILD_GAP then
    -- Any trailing rebuild still pending (or lost) is superseded by this one.
    self.rebuildGen = self.rebuildGen + 1
    self.rebuildPending = false
    self:rebuildGuild(now)
  elseif not self.rebuildPending then
    local after = self.api.After
    if type(after) ~= "function" then
      return
    end
    self.rebuildGen = self.rebuildGen + 1
    local gen = self.rebuildGen
    after(last + REBUILD_GAP - now, function()
      self:guard("rebuild", trailingRebuild, gen)
    end)
    self.rebuildPending = true
  end
end

function handlers.PLAYER_GUILD_UPDATE(self)
  self:onGuild(self:now())
end

function handlers.GROUP_ROSTER_UPDATE(self)
  self:onGroup(self:now())
end

function handlers.PLAYER_REGEN_DISABLED(self)
  self:hold()
end

-- Wait 3 s, then resume if no newer combat event came and we're out of combat.
function handlers.PLAYER_REGEN_ENABLED(self)
  self.combatGen = self.combatGen + 1
  local gen = self.combatGen
  local after = self.api.After
  if type(after) == "function" then
    after(LIMITS.resumeDelay, function()
      self:guard("resume", resume, gen)
    end)
  end
end

-- Handles one client event. Does nothing unless the client is running; every handler
-- runs in pcall.
function Client:onEvent(event, ...)
  if not self.running or type(event) ~= "string" then
    return
  end
  local handler = handlers[event]
  if handler ~= nil then
    self:guard(event, handler, ...)
  end
end

-- ---------------------------------------------------------------------------
-- The real client.

local function field(t, key)
  if type(t) == "table" and type(t[key]) == "function" then
    return t[key]
  end
  return nil
end

local function realDeps()
  local data = tableOr(ns.Data)
  local cosmetics, phrase = tableOr(ns.Cosmetics), tableOr(ns.Phrase)
  return {
    ledger = ns.ledger,
    inns = tableOr(data.Inns),
    phrases = tableOr(data.Phrases),
    seals = tableOr(cosmetics.SEALS),
    phraseOk = type(phrase.validIds) == "function" and phrase.validIds or nil,
    debug = function(line) ns.Core:Debug(line) end,
    api = {
      GetServerTime = GetServerTime,
      UnitGUID = UnitGUID,
      UnitFullName = UnitFullName,
      UnitName = UnitName,
      UNKNOWNOBJECT = UNKNOWNOBJECT,
      IsInGroup = IsInGroup,
      IsInRaid = IsInRaid,
      GetNumGroupMembers = GetNumGroupMembers,
      IsInGuild = IsInGuild,
      GetNumGuildMembers = GetNumGuildMembers,
      GetGuildRosterInfo = GetGuildRosterInfo,
      GuildRoster = field(C_GuildInfo, "GuildRoster"),
      GetNormalizedRealmName = GetNormalizedRealmName,
      InCombatLockdown = InCombatLockdown,
      issecretvalue = type(issecretvalue) == "function" and issecretvalue or nil,
      After = field(C_Timer, "After"),
      RegisterPrefix = field(C_ChatInfo, "RegisterAddonMessagePrefix"),
      -- Every send goes through ChatThrottleLib at BULK, never to a target. The global is
      -- read at each send: a newer copy another AddOn loads upgrades the same table.
      send = function(text, chattype, callback)
        return ChatThrottleLib:SendAddonMessage("BULK", PREFIX, text, chattype, nil, PREFIX,
          callback)
      end,
      Enum = type(Enum) == "table" and Enum or nil,
      LE_PARTY_CATEGORY_HOME = LE_PARTY_CATEGORY_HOME,
      random = math.random,
    },
  }
end

local function startReal(self)
  local client = Sync.new(realDeps())
  self.client, self.stats = client, client.stats
  if client:start() then
    local frame = CreateFrame("Frame")
    frame:SetScript("OnEvent", function(_, event, ...)
      client:onEvent(event, ...)
    end)
    for _, event in ipairs(EVENTS) do
      frame:RegisterEvent(event)
    end
    self.frame = frame
  end
end

-- Core calls this once the ledger is open (spec 3.2). Builds the one real client from
-- the client's globals, exposes its counters at ns.Sync.stats and registers the events.
-- Runs once; an error is counted and logged like a handler's.
function Sync:Start()
  if self.client ~= nil then
    return
  end
  local ok = pcall(startReal, self)
  if not ok then
    if type(self.stats) ~= "table" then
      self.stats = newStats()
    end
    self.stats.errors = self.stats.errors + 1
    pcall(function() ns.Core:Debug("sync: error in start") end)
  end
end

-- Sign calls this after ledger:addOwn returns "added" (spec 3.5.1): a HELLO goes out on
-- each available channel. Does nothing while sync is off.
function Sync:WindowChanged()
  local client = self.client
  if type(client) == "table" then
    client:windowChanged()
  end
end
