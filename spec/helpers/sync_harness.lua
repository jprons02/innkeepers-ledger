-- A world of Sync clients in one Lua state (docs/specs/sync-glue.md 6.1). Each client has
-- its own ns (the pure modules and Sync.lua loaded fresh), Ledger, GUID, name and fake
-- `api`; they share one clock, one timer queue, one addon-message bus and the group and
-- guild membership that drive UnitGUID, IsInGroup / IsInRaid / GetNumGroupMembers and
-- the guild roster. No WoW stub or _G state is involved.
--
--   local harness = require("helpers.sync_harness")
--   local w = harness.new()
--   local me, mira = w:add("Aldric"), w:add("Mira")
--   w:setGroup({ me, mira })
--   w:post(mira, "PARTY", text)   -- delivered at the next step (or w:deliver())
--   w:advance(5)                  -- one-second steps: deliver, then run due timers
--
-- Client functions are counted in `c.calls[name]` and implemented by `c.impl[name]`; a
-- test replaces `c.impl.X` to change one, or sets `c.api.X = nil` to make it missing.
-- `c.secret(v)` is the client's issecretvalue predicate. Sends (the send path) go on the
-- bus; `c.sendMode` = "sync" (callback at once, the default), "defer" (after
-- `c.sendDelay` s) or "fail" (callback with didSend false). `c.inCombat` drives
-- InCombatLockdown, and `H.combat(c, on)` sets it and fires the PLAYER_REGEN_* event.
-- The group functions record their argument in `c.groupArgs` (LE_PARTY_CATEGORY_HOME is
-- `H.HOME` in every client's api) and otherwise ignore it. Timers remember their client
-- (`timer.owner`). `UnitFullName` / `UnitName` answer "player", "partyN" and "raidN";
-- `c.tokens` makes UnitGUID answer unit tokens like "target" (any case), and UnitGUID of
-- a member's name still answers, so a test can show what the old name lookup did.
--
-- Forever names: `harness.new({ forever = true })` models the beta (2026-09-30). Names
-- are two-part ("Ada Brook"), the realm is `H.FOREVER_REALM`, senders and roster names
-- are the bare "First Surname", and UnitFullName / UnitName give "First", "Surname" for
-- every unit (seen for "player"; assumed for the others until #12 sees them).
local load = require("helpers.load")

local H = {}

H.PREFIX = "InnLedger"
H.NOW = 1794000000
H.ANCHOR = 1790089200 -- Tuesday 2026-09-22 15:00 UTC, the retail US reset
H.REALM = "Stubrealm"
H.FOREVER_REALM = "ClassicBetaPvP" -- the beta's GetNormalizedRealmName
H.HOME = 1 -- LE_PARTY_CATEGORY_HOME

-- Fixture data (the real Data tables are empty): inns 1..300, phrases 1..40, seals 1..20.
H.INNS, H.PHRASES, H.SEALS = {}, {}, {}
for i = 1, 300 do
  H.INNS[i] = true
end
for i = 1, 40 do
  H.PHRASES[i] = true
end
for i = 1, 20 do
  H.SEALS[i] = true
end

-- A distinct valid entry per i (distinct inns, so the weekly rule never bites).
function H.entry(i, now)
  return { inn = i, t = (now or H.NOW) - 100000 + i, phrase = { 1 + i % 40 },
    seal = i % 3 == 0 and (i % 20 + 1) or nil }
end

local API_NAMES = {
  "GetServerTime", "UnitGUID", "UnitFullName", "UnitName", "IsInGroup", "IsInRaid",
  "GetNumGroupMembers", "IsInGuild",
  "GetNumGuildMembers", "GetGuildRosterInfo", "GuildRoster", "GetNormalizedRealmName",
  "InCombatLockdown", "issecretvalue", "After", "RegisterPrefix", "send", "random",
}

local World = {}
World.__index = World

-- opts.seed: the seed of the shared random numbers (Park-Miller, exact in doubles).
-- opts.forever: Forever's two-part names (see the top of this file).
function H.new(opts)
  opts = opts or {}
  return setmetatable({
    now = H.NOW,
    forever = opts.forever == true,
    realm = opts.forever and H.FOREVER_REALM or H.REALM,
    seed = opts.seed or 12345,
    timers = {},
    timerSeq = 0,
    clients = {},
    queue = {},     -- messages waiting for the next step
    sent = {},      -- every message a client handed to `send`
    group = { members = {}, raid = false },
    guild = { members = {}, rows = {} },
  }, World)
end

local function contains(list, x)
  for _, v in ipairs(list) do
    if v == x then
      return true
    end
  end
  return false
end

function World:rand(lo, hi)
  self.seed = self.seed * 16807 % 2147483647
  return lo + self.seed % (hi - lo + 1)
end

-- Queues fn to run `delay` seconds from now (`owner`: the client that asked, if any).
function World:after(delay, fn, owner)
  self.timerSeq = self.timerSeq + 1
  self.timers[#self.timers + 1] = { due = self.now + delay, seq = self.timerSeq, fn = fn,
    owner = owner }
end

-- How many queued timers belong to `c`.
function World:timersOf(c)
  local n = 0
  for _, timer in ipairs(self.timers) do
    if timer.owner == c then
      n = n + 1
    end
  end
  return n
end

-- Runs the earliest-scheduled due timer. False if none is due.
function World:runDue()
  for i, timer in ipairs(self.timers) do
    if timer.due <= self.now then
      table.remove(self.timers, i)
      timer.fn()
      return true
    end
  end
  return false
end

-- Moves the clock forward one second at a time: deliver what was sent, then run the
-- timers that fell due (including ones they schedule).
function World:advance(seconds)
  for _ = 1, seconds do
    self.now = self.now + 1
    self:deliver()
    while self:runDue() do end
  end
end

-- The clients that hear `wire`: the group for PARTY / RAID, the guild for GUILD.
function World:listeners(wire)
  local members = (wire == "GUILD") and self.guild.members or self.group.members
  local out = {}
  for _, m in ipairs(members) do
    if m.client ~= nil then
      out[#out + 1] = m
    end
  end
  return out
end

-- Queues `text` from `from` on `wire`, delivered to every listener (the sender included:
-- addon messages echo) at the next step. `sender` defaults to from's full name.
function World:post(from, wire, text, sender)
  self.queue[#self.queue + 1] = { from = from, wire = wire, text = text,
    sender = sender or from.full }
end

-- Delivers every queued message now, in order.
function World:deliver()
  local queue = self.queue
  self.queue = {}
  for _, m in ipairs(queue) do
    for _, c in ipairs(self:listeners(m.wire)) do
      c.client:onEvent("CHAT_MSG_ADDON", H.PREFIX, m.text, m.wire, m.sender)
    end
  end
end

-- Group members: clients or plain { name, full, guid } records. `raid` makes it a raid.
function World:setGroup(members, raid)
  self.group = { members = members, raid = raid == true }
end

-- Guild members: clients or plain records. The roster rows are rebuilt from them in
-- order ({ name = full name, guid }); tests may edit `w.guild.rows` afterwards.
function World:setGuild(members)
  local rows = {}
  for i, m in ipairs(members) do
    rows[i] = { name = m.full, guid = m.guid }
  end
  self.guild = { members = members, rows = rows }
end

-- A plain member record for someone with no client (a name the server knows).
function H.member(name, guid, realm)
  return { name = name, full = name .. "-" .. (realm or H.REALM), guid = guid }
end

-- A member record for a Forever world: `name` is "First Surname", the sender form.
function H.twoPart(name, guid)
  local first, surname = name:match("^(%S+) (%S+)$")
  return { name = name, first = first or name, surname = surname, full = name, guid = guid }
end

-- The default client functions for `c`.
local function defaults(w, c)
  local impl = {}
  local function inGroup()
    return contains(w.group.members, c)
  end
  local function inGuild()
    return contains(w.guild.members, c)
  end
  impl.GetServerTime = function() return w.now end
  -- The member behind "player", "raidN" or "partyN", or nil.
  local function unitMember(unit)
    if unit == "player" then
      return c
    end
    if type(unit) ~= "string" or not inGroup() then
      return nil
    end
    local members = w.group.members
    local n = tonumber(unit:match("^raid(%d+)$") or "")
    if n then
      return w.group.raid and members[n] or nil
    end
    n = tonumber(unit:match("^party(%d+)$") or "")
    if n then
      local others = {}
      for _, m in ipairs(members) do
        if m ~= c then
          others[#others + 1] = m
        end
      end
      return others[n]
    end
    return nil
  end
  impl.UnitGUID = function(unit)
    local member = unitMember(unit)
    if member then
      return member.guid
    end
    -- Unit tokens, case-insensitive as the client parses them (c.tokens: "target" -> GUID).
    local token = type(unit) == "string" and c.tokens[unit:lower()]
    if token then
      return token
    end
    if not inGroup() then
      return nil
    end
    -- A group member's name: the lookup #54 removed from Sync (kept to test against it).
    for _, m in ipairs(w.group.members) do
      if unit == m.name or unit == m.full then
        return m.guid
      end
    end
    return nil
  end
  -- Forever: the first name and the surname, for every unit.
  local function twoPartName(unit)
    local m = unitMember(unit)
    if not m then
      return nil
    end
    return m.first, m.surname
  end
  -- Name and realm, the realm nil for our own realm except for "player" (retail).
  impl.UnitFullName = function(unit)
    if w.forever then
      return twoPartName(unit)
    end
    local m = unitMember(unit)
    if not m then
      return nil
    end
    local realm = m.full:match("%-(.+)$")
    if unit ~= "player" and realm == w.realm then
      realm = nil
    end
    return m.name, realm
  end
  -- Name and realm, the realm nil for our own realm.
  impl.UnitName = function(unit)
    if w.forever then
      return twoPartName(unit)
    end
    local m = unitMember(unit)
    if not m then
      return nil
    end
    local realm = m.full:match("%-(.+)$")
    return m.name, realm ~= w.realm and realm or nil
  end
  local function record(name, ...)
    c.groupArgs[name] = { n = select("#", ...), ... }
  end
  impl.IsInGroup = function(...) record("IsInGroup", ...) return inGroup() end
  impl.IsInRaid = function(...) record("IsInRaid", ...) return inGroup() and w.group.raid end
  impl.GetNumGroupMembers = function(...)
    record("GetNumGroupMembers", ...)
    return inGroup() and #w.group.members or 0
  end
  impl.InCombatLockdown = function() return c.inCombat end
  impl.IsInGuild = function() return inGuild() end
  impl.GetNumGuildMembers = function()
    local n = inGuild() and #w.guild.rows or 0
    return n, n, n
  end
  -- Retail order: the name is the 1st return, the GUID the 17th.
  impl.GetGuildRosterInfo = function(i)
    local row = inGuild() and w.guild.rows[i]
    if not row then
      return nil
    end
    return row.name, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
      nil, row.guid
  end
  impl.GuildRoster = function() end
  impl.GetNormalizedRealmName = function() return w.realm end
  impl.issecretvalue = function(v) return c.secret ~= nil and c.secret(v) == true end
  impl.After = function(delay, fn) w:after(delay, fn, c) end
  impl.RegisterPrefix = function() return true end
  impl.random = function(lo, hi) return w:rand(lo, hi) end
  -- The send path: record, queue for the next step, and run the callback per sendMode.
  impl.send = function(text, wire, callback)
    w.sent[#w.sent + 1] = { from = c, text = text, wire = wire, at = w.now }
    w:post(c, wire, text)
    if c.sendMode == "defer" then
      w:after(c.sendDelay, function() callback(nil, true) end)
    elseif c.sendMode == "fail" then
      callback(nil, false)
    else
      callback(nil, true)
    end
  end
  return impl
end

-- Adds a client named `name` (full name "<name>-<realm>"; in a Forever world `name` is
-- "First Surname" and is the full name too). opts:
--   guid     its GUID (default Player-1-<index as 8 hex digits>)
--   ledger   a ledger object to use instead of a fresh one
--   data     the saved table the fresh ledger opens (e.g. "junk" for a read-only one)
--   setup    fn(ns, c) run after the pure modules load, before Sync.lua (for spies)
--   deps     extra Sync.new deps (merged over the defaults)
--   start    false to skip client:start()
function World:add(name, opts)
  opts = opts or {}
  local index = #self.clients + 1
  local c = {
    world = self,
    name = name,
    full = self.forever and name or name .. "-" .. self.realm,
    guid = opts.guid or ("Player-1-%08X"):format(index),
    lines = {},     -- debug lines
    calls = {},     -- client function name -> call count
    secret = nil,   -- issecretvalue predicate
    sendMode = "sync",
    sendDelay = 1,
    inCombat = false,
    groupArgs = {}, -- group function name -> { n = argument count, ... }
    tokens = {},    -- unit tokens UnitGUID answers: lower-case token -> GUID
  }
  if self.forever then
    c.first, c.surname = name:match("^(%S+) (%S+)$")
    c.first = c.first or name
  end
  local ns = {}
  load.file("Ledger.lua", ns, load.pure_env())
  load.file("SyncProtocol.lua", ns, load.pure_env())
  load.file("SyncSchedule.lua", ns, load.pure_env())
  if opts.setup then
    opts.setup(ns, c)
  end
  load.file("Sync.lua", ns)
  c.ns = ns
  c.ledger = opts.ledger
  if c.ledger == nil then
    local data = opts.data
    if data == nil then
      data = {}
    end
    c.ledger = ns.Ledger.new(data, { guid = c.guid, name = name }, H.ANCHOR)
  end

  c.impl = defaults(self, c)
  c.api = {}
  for _, fname in ipairs(API_NAMES) do
    c.api[fname] = function(...)
      c.calls[fname] = (c.calls[fname] or 0) + 1
      return c.impl[fname](...)
    end
  end
  c.api.LE_PARTY_CATEGORY_HOME = H.HOME
  c.api.UNKNOWNOBJECT = "Unknown"

  local deps = {
    ledger = c.ledger, inns = H.INNS, phrases = H.PHRASES, seals = H.SEALS,
    debug = function(line) c.lines[#c.lines + 1] = line end,
    api = c.api,
  }
  for k, v in pairs(opts.deps or {}) do
    deps[k] = v
  end
  c.client = ns.Sync.new(deps)
  self.clients[index] = c
  if opts.start ~= false then
    c.started = c.client:start()
  end
  return c
end

-- Gives `c` n own entries (entry(1) .. entry(n)).
function H.sign(c, n, first)
  first = first or 1
  for i = first, first + n - 1 do
    assert(c.ledger:addOwn(H.entry(i)) == "added")
  end
end

-- The ENTRIES messages of c's share window with t > since.
function H.entriesText(c, since)
  return c.ns.SyncProtocol.encodeEntries(c.ledger:shareWindow(c.ns.SyncProtocol.SHARE_MAX),
    since or 0)
end

function H.helloText(c)
  return c.ns.SyncProtocol.encodeHello(c.ledger:shareWindow(c.ns.SyncProtocol.SHARE_MAX))
end

-- Puts `c` in or out of combat and fires the matching event.
function H.combat(c, on)
  c.inCombat = on
  c.client:onEvent(on and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
end

-- Delivers CHAT_MSG_ADDON to `c` directly, with any arguments.
function H.inject(c, ...)
  c.client:onEvent("CHAT_MSG_ADDON", ...)
end

-- Entries c's ledger holds under `guid`, and the traveler's stored name.
function H.held(c, guid)
  local name
  for _, t in ipairs(c.ledger:travelers()) do
    if t.guid == guid then
      name = t.name
    end
  end
  return #c.ledger:signerEntries(guid), name
end

return H
