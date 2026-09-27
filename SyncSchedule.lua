-- SyncSchedule (pure): what Sync sends and when. The send budget, HELLO / WANT / reply
-- timing and gates, the pending queues, the hold state and the pump that picks the next
-- message. No WoW API and no clock here: `now` is always an argument, and the transport
-- is reached only through the `io.send` function the glue passes to `pump`.
-- Spec: docs/specs/sync-glue.md (sections 3.5 and 3.6). Every method takes plain values
-- and never throws on bad input; only `SyncSchedule.new` raises, on a caller bug.
local _, ns = ...

local SP = ns.SyncProtocol
assert(type(SP) == "table", "SyncSchedule needs ns.SyncProtocol; SyncProtocol.lua comes first")

local SyncSchedule = {}
ns.SyncSchedule = SyncSchedule

local huge, max, min = math.huge, math.max, math.min
local byte, tremove, tsort = string.byte, table.remove, table.sort

-- Constants (spec 3.5.2). The locals below are what the code uses; the exported table is
-- for callers and tests. Ranges are { lo, hi } in seconds.
local WINDOW = 60             -- sliding budget window, s
local MESSAGES = 30           -- messages handed over in any WINDOW
local ENTRIES = 60            -- entries in those messages in any WINDOW
local WANTS = 12              -- WANTs in any WINDOW
local IN_FLIGHT_MAX = 2       -- handed over, send callback not back yet
local IN_FLIGHT_RELEASE = 30  -- no callback after this long: treated as sent
local HELLO_GAP = 60          -- per logical channel
local HELLO_DELAY = { 5, 15 }
local GUILD_FIRST = { 60, 120 }
local GUILD_EVERY = { 1200, 1500 }
local WANT_DELAY = { 1, 5 }
local PENDING_WANTS_MAX = 200
local COALESCE = 5
local REPLY_GAP = 30
local LARGE_GAP = 300
local SMALL_MAX = SP.MAX_ENTRIES_PER_MSG -- a reply that fits one message is small
local PER_MSG = SP.MAX_ENTRIES_PER_MSG   -- how encodeEntries splits a reply
local RESUME_DELAY = 3
local SHARE_MAX = SP.SHARE_MAX
local T_MAX = ns.Ledger.LIMITS.tMax

SyncSchedule.LIMITS = {
  window = WINDOW,
  messages = MESSAGES,
  entries = ENTRIES,
  wants = WANTS,
  inFlightMax = IN_FLIGHT_MAX,
  inFlightRelease = IN_FLIGHT_RELEASE,
  helloGap = HELLO_GAP,
  helloDelay = { HELLO_DELAY[1], HELLO_DELAY[2] },
  guildFirst = { GUILD_FIRST[1], GUILD_FIRST[2] },
  guildEvery = { GUILD_EVERY[1], GUILD_EVERY[2] },
  wantDelay = { WANT_DELAY[1], WANT_DELAY[2] },
  pendingWantsMax = PENDING_WANTS_MAX,
  coalesce = COALESCE,
  replyGap = REPLY_GAP,
  largeGap = LARGE_GAP,
  smallMax = SMALL_MAX,
  resumeDelay = RESUME_DELAY,
}

-- Logical channels (spec 3.5.1). Gates and pending items are kept per logical channel,
-- so a party that turns into a raid keeps them.
local ORDER = { "GROUP", "GUILD" }
local WIRE_TO_LOGICAL = { PARTY = "GROUP", RAID = "GROUP", GUILD = "GUILD" }
SyncSchedule.WIRE_TO_LOGICAL = { PARTY = "GROUP", RAID = "GROUP", GUILD = "GUILD" }

-- An integer in lo..hi. NaN fails x == x; inf % 1 is NaN, so inf fails too.
local function isInt(x, lo, hi)
  return type(x) == "number" and x == x and x % 1 == 0 and x >= lo and x <= hi
end

local function isTime(x)
  return isInt(x, 0, T_MAX)
end

-- Byte order for GUID tie-breaks: string `<` follows the C locale's collation.
local function strLess(a, b)
  for i = 1, min(#a, #b) do
    local x, y = byte(a, i), byte(b, i)
    if x ~= y then
      return x < y
    end
  end
  return #a < #b
end

-- Entries of `window` with t > since: the same filter encodeEntries uses. Reads with
-- rawget and type checks, so a malformed window counts short instead of throwing.
local function countSince(window, since)
  local n = 0
  for i = 1, #window do
    local e = rawget(window, i)
    local t = type(e) == "table" and rawget(e, "t") or nil
    if type(t) == "number" and t > since then
      n = n + 1
    end
  end
  return n
end

local Schedule = {}
Schedule.__index = Schedule

local function isSchedule(self)
  return type(self) == "table" and rawequal(getmetatable(self), Schedule)
end

local function newChannel()
  return {
    wire = nil,        -- current wire channel; nil = unavailable
    helloDue = nil,    -- pending HELLO
    lastHello = nil,
    small = nil,       -- smallest `since` of the small bucket
    large = nil,       -- smallest `since` of the large bucket
    replyDue = nil,
    lastReply = nil,
    lastLarge = nil,   -- { at, digest } of the last large reply
    progress = {},     -- in-progress reply: { text, n } per message, in send order
  }
end

-- SyncSchedule.new{ memo = <SyncProtocol WANT memo>, rand = fn(lo, hi) -> integer }.
function SyncSchedule.new(opts)
  local memo = type(opts) == "table" and rawget(opts, "memo") or nil
  local rand = type(opts) == "table" and rawget(opts, "rand") or nil
  if type(memo) ~= "table" then
    error("SyncSchedule.new: opts.memo must be the WANT memo table", 2)
  end
  if type(rand) ~= "function" then
    error("SyncSchedule.new: opts.rand must be a function", 2)
  end
  return setmetatable({
    memo = memo,
    rand = rand,
    held = false,
    token = 0,
    msgs = {},       -- budget records { t, n }, oldest first
    wantRecs = {},   -- the WANT records among them, oldest first
    inFlight = {},   -- token -> hand-off time
    nInFlight = 0,
    wants = {},      -- guid -> { logical, wire, count, digest, due }
    nWants = 0,
    sendFailed = 0,
    ch = { GROUP = newChannel(), GUILD = newChannel() },
  }, Schedule)
end

-- rand(lo, hi), trusted to be a caller's function but not to behave: an error or a value
-- outside lo..hi becomes hi (the latest, so a bad rand can only slow sending down).
function Schedule:_rand(lo, hi)
  local ok, v = pcall(self.rand, lo, hi)
  if ok and isInt(v, lo, hi) then
    return v
  end
  return hi
end

-- ---------------------------------------------------------------------------
-- Time keeping (spec 3.5.2 -> Server time going backwards).

local function clampList(list, now)
  for i = 1, #list do
    if list[i].t > now then
      list[i].t = now
    end
  end
end

-- Past stamps later than `now` become `now`; due times are capped at `now` plus their
-- kind's longest delay.
function Schedule:_clamp(now)
  clampList(self.msgs, now)
  clampList(self.wantRecs, now)
  for token, t in next, self.inFlight do
    if t > now then
      self.inFlight[token] = now -- assigning an existing field during traversal is allowed
    end
  end
  for _, c in next, self.ch do
    if c.lastHello ~= nil and c.lastHello > now then
      c.lastHello = now
    end
    if c.lastReply ~= nil and c.lastReply > now then
      c.lastReply = now
    end
    if c.lastLarge ~= nil and c.lastLarge.at > now then
      c.lastLarge.at = now
    end
    if c.helloDue ~= nil and c.helloDue > now + GUILD_EVERY[2] then
      c.helloDue = now + GUILD_EVERY[2]
    end
    if c.replyDue ~= nil and c.replyDue > now + COALESCE then
      c.replyDue = now + COALESCE
    end
  end
  for _, w in next, self.wants do
    if w.due > now + WANT_DELAY[2] then
      w.due = now + WANT_DELAY[2]
    end
  end
end

-- Drops expired budget records (a prefix: records are kept in time order) and releases
-- in-flight messages whose callback is overdue.
function Schedule:_expire(now)
  for _, list in ipairs({ self.msgs, self.wantRecs }) do
    local k = 0
    while list[k + 1] ~= nil and now >= list[k + 1].t + WINDOW do
      k = k + 1
    end
    for _ = 1, k do
      tremove(list, 1)
    end
  end
  for token, t in next, self.inFlight do
    if now >= t + IN_FLIGHT_RELEASE then
      self.inFlight[token] = nil -- clearing fields during traversal is allowed
      self.nInFlight = self.nInFlight - 1
    end
  end
end

-- ---------------------------------------------------------------------------
-- The send budget (spec 3.5.2).

-- The earliest time a message of `n` entries (a WANT if `isWant`) fits the budget: `now`
-- if it fits now. Exact for the sliding window; for the in-flight cap it's the earliest
-- release (a send callback can free a slot sooner, and it requests a pump when it does).
function Schedule:_admitAt(now, n, isWant)
  local at = now
  if self.nInFlight >= IN_FLIGHT_MAX then
    local first = huge
    for _, t in next, self.inFlight do
      first = min(first, t)
    end
    at = max(at, first + IN_FLIGHT_RELEASE)
  end
  local msgs = self.msgs
  if #msgs + 1 > MESSAGES then
    at = max(at, msgs[#msgs + 1 - MESSAGES].t + WINDOW)
  end
  local total = n
  for i = 1, #msgs do
    total = total + msgs[i].n
  end
  local i = 0
  while total > ENTRIES and i < #msgs do
    i = i + 1
    total = total - msgs[i].n
  end
  if i > 0 then
    at = max(at, msgs[i].t + WINDOW)
  end
  local wants = self.wantRecs
  if isWant and #wants >= WANTS then
    at = max(at, wants[#wants + 1 - WANTS].t + WINDOW)
  end
  return at
end

local function removeRec(list, rec)
  for i = #list, 1, -1 do
    if list[i] == rec then
      tremove(list, i)
      return
    end
  end
end

-- Records one message in the budget and in flight, then hands it to io.send. Returns
-- false if io.send returned false (nothing reached the transport): the record and the
-- in-flight entry are removed again.
function Schedule:_handOver(now, send, wire, text, n, isWant)
  self.token = self.token + 1
  local token = self.token
  local rec = { t = now, n = n }
  self.msgs[#self.msgs + 1] = rec
  if isWant then
    self.wantRecs[#self.wantRecs + 1] = rec
  end
  self.inFlight[token] = now
  self.nInFlight = self.nInFlight + 1
  if send(wire, text, token) == false then
    removeRec(self.msgs, rec)
    if isWant then
      removeRec(self.wantRecs, rec)
    end
    if self.inFlight[token] ~= nil then
      self.inFlight[token] = nil
      self.nInFlight = self.nInFlight - 1
    end
    self.sendFailed = self.sendFailed + 1
    return false
  end
  return true
end

-- A send callback came back for `token`. Unknown tokens are ignored.
function Schedule:sendDone(token)
  if not isSchedule(self) or not isInt(token, 1, self.token) or self.inFlight[token] == nil then
    return false
  end
  self.inFlight[token] = nil
  self.nInFlight = self.nInFlight - 1
  return true
end

-- ---------------------------------------------------------------------------
-- Inputs from the glue.

-- Makes a logical channel available on `wire`, or unavailable (`wire == nil`), which
-- drops everything pending on it. Gate stamps are kept.
function Schedule:setChannel(ch, wire)
  if not isSchedule(self) or (ch ~= "GROUP" and ch ~= "GUILD") then
    return false
  end
  local c = self.ch[ch]
  if wire == nil then
    c.wire, c.helloDue, c.small, c.large, c.replyDue = nil, nil, nil, nil, nil
    c.progress = {}
    for guid, w in next, self.wants do
      if w.logical == ch then
        self.wants[guid] = nil -- clearing fields during traversal is allowed
        self.nWants = self.nWants - 1
      end
    end
    return true
  end
  if type(wire) ~= "string" or WIRE_TO_LOGICAL[wire] ~= ch then
    return false
  end
  c.wire = wire
  return true
end

-- The combat flag, as the glue reads it (spec 3.6). While held, `pump` sends nothing.
function Schedule:setHeld(held)
  if not isSchedule(self) or type(held) ~= "boolean" then
    return false
  end
  self.held = held
  return true
end

-- A HELLO is wanted on `ch` in lo..hi seconds. Never pushes a pending one later.
function Schedule:requestHello(ch, now, lo, hi)
  if not isSchedule(self) or (ch ~= "GROUP" and ch ~= "GUILD") or not isTime(now)
    or not isInt(lo, 0, GUILD_EVERY[2]) or not isInt(hi, lo, GUILD_EVERY[2]) then
    return false
  end
  self:_clamp(now)
  local c = self.ch[ch]
  if c.wire == nil then
    return false
  end
  local due = now + self:_rand(lo, hi)
  if c.helloDue == nil or due < c.helloDue then
    c.helloDue = due
  end
  return true
end

-- A peer's HELLO came in on `wire` (spec 3.5.5). One pending WANT decision per peer.
function Schedule:onHello(guid, wire, count, digest, now)
  if not isSchedule(self) or not SP.validGUID(guid) or type(wire) ~= "string"
    or not isInt(count, 1, SHARE_MAX) or not isInt(digest, 0, huge) or not isTime(now) then
    return false
  end
  local logical = WIRE_TO_LOGICAL[wire]
  if logical == nil or self.ch[logical].wire == nil then
    return false
  end
  self:_clamp(now)
  local w = self.wants[guid]
  if w ~= nil then
    w.count, w.digest = count, digest
    -- GROUP first: a peer in both our group and our guild is answered in the group.
    if logical == "GROUP" or w.logical == "GUILD" or self.ch.GROUP.wire == nil then
      w.logical, w.wire = logical, wire
    end
    return true
  end
  if self.nWants >= PENDING_WANTS_MAX then
    return false
  end
  self.wants[guid] = {
    logical = logical, wire = wire, count = count, digest = digest,
    due = now + self:_rand(WANT_DELAY[1], WANT_DELAY[2]),
  }
  self.nWants = self.nWants + 1
  return true
end

-- A WANT for us came in on `wire` (spec 3.5.4). `window` is our share window now.
function Schedule:onWant(wire, since, window, now)
  if not isSchedule(self) or type(wire) ~= "string" or not isInt(since, 0, T_MAX)
    or type(window) ~= "table" or not isTime(now) then
    return false
  end
  local logical = WIRE_TO_LOGICAL[wire]
  if logical == nil or self.ch[logical].wire == nil then
    return false
  end
  self:_clamp(now)
  local n = countSince(window, since)
  if n == 0 then
    return false
  end
  local c = self.ch[logical]
  if n <= SMALL_MAX then
    c.small = min(c.small or since, since)
  else
    c.large = min(c.large or since, since)
  end
  if c.replyDue == nil then
    c.replyDue = now + COALESCE
  end
  return true
end

-- ---------------------------------------------------------------------------
-- The pump (spec 3.5.6).

-- Our share window, read once per pump. A caller bug (not a table, over SHARE_MAX) is an
-- error, which the pump's pcall turns into "abort this pump".
local function readWindow(run)
  if run.window == nil then
    local w = run.io.window()
    if type(w) ~= "table" or #w > SHARE_MAX then
      error("SyncSchedule: io.window() is not a share window")
    end
    run.window = w
  end
  return run.window
end

local function largeGateOpen(c, now, dig)
  local last = c.lastLarge
  return last == nil or now >= last.at + LARGE_GAP or dig ~= last.digest
end

function Schedule:_nextGuildHello(ch, now)
  if ch == "GUILD" then
    self.ch.GUILD.helloDue = now + self:_rand(GUILD_EVERY[1], GUILD_EVERY[2])
  end
end

-- One HELLO on `ch` if it's due, its gate is open and the budget admits it.
function Schedule:_helloStep(run, ch)
  local c, now = self.ch[ch], run.now
  if c.wire == nil or c.helloDue == nil or now < c.helloDue then
    return false
  end
  local window = readWindow(run)
  if #window == 0 then
    -- Count 0 makes every receiver do nothing: skip it, and don't stamp the gate.
    c.helloDue = nil
    self:_nextGuildHello(ch, now)
    return true
  end
  if (c.lastHello ~= nil and now < c.lastHello + HELLO_GAP) or self:_admitAt(now, 0) > now then
    return false
  end
  local text = SP.encodeHello(window)
  c.helloDue, c.lastHello = nil, now
  self:_nextGuildHello(ch, now)
  self:_handOver(now, run.io.send, c.wire, text, 0, false)
  return true
end

-- Starts one reply on `ch` (spec 3.5.4 steps 1-3), or clears / moves a bucket that has
-- nothing (more) to send as it is. Returns true if anything changed.
function Schedule:_startReply(run, ch)
  local c, now = self.ch[ch], run.now
  local window = readWindow(run)
  local since, dig
  local changed = false
  if c.large ~= nil then
    if countSince(window, c.large) == 0 then
      c.large, changed = nil, true -- nothing to send: no reply, no stamp
    else
      dig = SP.digest(window)
      if largeGateOpen(c, now, dig) then
        since = c.large
      end
    end
  end
  if since == nil and c.small ~= nil then
    local n = countSince(window, c.small)
    if n == 0 then
      c.small, changed = nil, true
    elseif n > SMALL_MAX then
      -- Our window grew since the ask: it's a large reply now, gate and all.
      c.large, c.small, changed = min(c.large or c.small, c.small), nil, true
    else
      since, dig = c.small, nil
    end
  end
  if since == nil then
    if c.small == nil and c.large == nil then
      c.replyDue, changed = nil, true
    end
    return changed
  end
  local texts = SP.encodeEntries(window, since)
  local n = countSince(window, since)
  -- Stamps and queue changes only after the encoder returned.
  if dig ~= nil then
    c.lastLarge = { at = now, digest = dig }
    c.large = nil
    if c.small ~= nil and c.small >= since then
      c.small = nil
    end
  else
    c.small = nil
  end
  c.lastReply = now
  c.replyDue = (c.small ~= nil or c.large ~= nil) and now or nil
  local progress = {}
  for i = 1, #texts do
    progress[i] = { text = texts[i], n = min(PER_MSG, n - PER_MSG * (i - 1)) }
  end
  c.progress = progress
  return true
end

-- The next message of the reply in progress on `ch`, else a new reply if one is due.
function Schedule:_replyStep(run, ch)
  local c, now = self.ch[ch], run.now
  if c.wire == nil then
    return false
  end
  local m = c.progress[1]
  if m ~= nil then
    if self:_admitAt(now, m.n) > now then
      return false
    end
    tremove(c.progress, 1)
    if not self:_handOver(now, run.io.send, c.wire, m.text, m.n, false) then
      c.progress = {} -- a failed message drops the rest of its reply
    end
    return true
  end
  if c.replyDue == nil or now < c.replyDue
    or (c.lastReply ~= nil and now < c.lastReply + REPLY_GAP) then
    return false
  end
  return self:_startReply(run, ch)
end

-- Due WANT decisions, oldest `due` first (ties by GUID bytes), while the budget admits a
-- WANT. decideWant runs only then, so its per-peer count only counts real sends.
function Schedule:_wantStep(run)
  local now = run.now
  local due = {}
  for guid, w in next, self.wants do
    if w.due <= now then
      due[#due + 1] = { guid = guid, w = w }
    end
  end
  tsort(due, function(a, b)
    if a.w.due ~= b.w.due then
      return a.w.due < b.w.due
    end
    return strLess(a.guid, b.guid)
  end)
  local changed = false
  for i = 1, #due do
    if self:_admitAt(now, 0, true) > now then
      break
    end
    local guid, w = due[i].guid, due[i].w
    local wire = self.ch[w.logical].wire
    local since = SP.decideWant(self.memo, guid, wire, w.count, w.digest, run.io.held(guid), now)
    local text = since ~= nil and SP.encodeWant(guid, since) or nil
    self.wants[guid] = nil
    self.nWants = self.nWants - 1
    changed = true
    if text ~= nil then
      self:_handOver(now, run.io.send, wire, text, 0, true)
    end
  end
  return changed
end

-- The earliest time anything pending could go out (spec 3.5.6 step 4), or nil.
function Schedule:_wake(run)
  local now = run.now
  local wake
  local function earliest(t)
    if wake == nil or t < wake then
      wake = t
    end
  end
  local function consider(ready, n, isWant)
    earliest(max(ready, self:_admitAt(now, n, isWant)))
  end
  for _, ch in ipairs(ORDER) do
    local c = self.ch[ch]
    if c.wire ~= nil then
      if c.helloDue ~= nil then
        if #readWindow(run) == 0 then
          -- An empty window's HELLO is skipped at its due time, whatever the gate or budget.
          earliest(c.helloDue)
        else
          consider(max(c.helloDue, c.lastHello ~= nil and c.lastHello + HELLO_GAP or 0), 0)
        end
      end
      if c.progress[1] ~= nil then
        consider(now, c.progress[1].n)
      elseif c.replyDue ~= nil then
        -- Starting a reply isn't budget-gated (its messages are, once in progress), so
        -- only the reply gap and, for a lone large ask, the large gate count here.
        local ready = max(c.replyDue, c.lastReply ~= nil and c.lastReply + REPLY_GAP or 0)
        if c.small == nil and c.large ~= nil
          and not largeGateOpen(c, now, SP.digest(readWindow(run))) then
          ready = max(ready, c.lastLarge.at + LARGE_GAP)
        end
        earliest(ready)
      end
    end
  end
  for _, w in next, self.wants do
    consider(w.due, 0, true)
  end
  if wake == nil then
    return nil
  end
  return max(wake, now + 1)
end

local function run(self, r)
  local progressed = true
  while progressed do
    progressed = self:_helloStep(r, "GROUP") or self:_helloStep(r, "GUILD")
      or self:_replyStep(r, "GROUP") or self:_replyStep(r, "GUILD")
      or self:_wantStep(r)
  end
  return self:_wake(r)
end

-- pump(now, io): sends what can go now and returns the next time it wants to run, or nil
-- when nothing is pending (or while held). io = { window = fn() -> our share window,
-- held = fn(guid) -> that signer's held entries, send = fn(wire, text, token) -> boolean }.
function Schedule:pump(now, io)
  if not isSchedule(self) or not isTime(now) or type(io) ~= "table" then
    return nil
  end
  local window, held, send = rawget(io, "window"), rawget(io, "held"), rawget(io, "send")
  if type(window) ~= "function" or type(held) ~= "function" or type(send) ~= "function" then
    return nil
  end
  self:_clamp(now)
  self:_expire(now)
  if self.held then
    return nil
  end
  local ok, wake = pcall(run, self, {
    now = now, io = { window = window, held = held, send = send },
  })
  if not ok then
    return now + 5 -- an encoder or io error: nothing more this pump, try again soon
  end
  return wake
end

-- Counts for tests and the debug report.
function Schedule:snapshot()
  if not isSchedule(self) then
    return nil
  end
  local s = {
    hellos = 0, wants = self.nWants, buckets = 0, progress = 0, inFlight = self.nInFlight,
    records = #self.msgs, wantRecords = #self.wantRecs, held = self.held,
    sendFailed = self.sendFailed,
  }
  for _, c in next, self.ch do
    s.hellos = s.hellos + (c.helloDue ~= nil and 1 or 0)
    s.buckets = s.buckets + (c.small ~= nil and 1 or 0) + (c.large ~= nil and 1 or 0)
    s.progress = s.progress + #c.progress
  end
  return s
end
