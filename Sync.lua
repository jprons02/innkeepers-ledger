-- Sync (glue): addon-message transport, sender resolution, group and guild triggers.
-- Spec: docs/specs/sync-glue.md (sections 3.3, 3.4 and 3.8). Every message from another
-- player is hostile. The only way into the ledger is SyncProtocol.receive, with a sender
-- built by `resolve` below from the event's own sender argument (the own-signature rule).
--
-- A client is an instance with its client functions injected (`Sync.new(deps)`), so tests
-- can run several in one Lua state; `ns.Sync:Start()` builds the one real client. Nothing
-- here reads a global except `Sync:Start()`, which gathers them into `deps.api`.
local _, ns = ...

local Ledger = ns.Ledger
local SP = ns.SyncProtocol
local SyncSchedule = ns.SyncSchedule

local Sync = {}
ns.Sync = Sync

local find, min, select = string.find, math.min, select

local PREFIX = "InnLedger"
local CHANNELS = SP.CHANNELS      -- PARTY, RAID, GUILD
local SENDER_MAX = 96             -- bytes in a sender or roster name
local REALM_MAX = 48              -- bytes in a realm name
local ROSTER_ROWS = 2000          -- guild roster rows read, at most
local ROSTER_GAP = 60             -- at most one roster request per this many s
local REBUILD_GAP = 10            -- at most one guild map rebuild per this many s
local T_MAX = Ledger.LIMITS.tMax

-- The events the real client registers; onEvent ignores any other.
local EVENTS = { "CHAT_MSG_ADDON", "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE" }

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
  }, Client)
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

-- client:requestPump(at) asks the send side to run at `at`. The send path fills it in.
function Client.requestPump()
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
  if self:inGuild() then
    self:requestRoster(now)
  end
  if now ~= nil then
    self:rebuildGuild(now)
  end
  return true
end

-- Starts the client. A missing or read-only ledger, or a refused prefix, turns sync off
-- for the session: no events are handled. Returns true if running.
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
    -- The sender string exactly as the server gave it; it resolves for group members only.
    guid = call(self.api.UnitGUID, sender)
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
  if self:inGuild() then
    self:requestRoster(self:now())
  else
    -- Left the guild: clear the map, cancel a pending rebuild, and let a rejoin request
    -- the roster at once.
    self.guild = {}
    self.rebuildGen = self.rebuildGen + 1
    self.rebuildPending = false
    self.rosterAt = nil
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
      IsInGroup = IsInGroup,
      IsInRaid = IsInRaid,
      GetNumGroupMembers = GetNumGroupMembers,
      IsInGuild = IsInGuild,
      GetNumGuildMembers = GetNumGuildMembers,
      GetGuildRosterInfo = GetGuildRosterInfo,
      GuildRoster = field(C_GuildInfo, "GuildRoster"),
      GetNormalizedRealmName = GetNormalizedRealmName,
      issecretvalue = type(issecretvalue) == "function" and issecretvalue or nil,
      After = field(C_Timer, "After"),
      RegisterPrefix = field(C_ChatInfo, "RegisterAddonMessagePrefix"),
      Enum = type(Enum) == "table" and Enum or nil,
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
