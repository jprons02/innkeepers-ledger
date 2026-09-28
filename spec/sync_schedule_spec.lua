-- SyncSchedule: the send budget, HELLO / WANT / reply gates, pending queues, the hold
-- state and the pump (docs/specs/sync-glue.md, sections 3.5, 3.6 and 6.2). Pure, run in
-- the strict environment with a fixed `now` and a scripted `rand`. Every case checks the
-- wake time the pump returns.
local load = require("helpers.load")

local function modules()
  local ns = {}
  load.file("Ledger.lua", ns, load.pure_env())
  load.file("SyncProtocol.lua", ns, load.pure_env())
  load.file("SyncSchedule.lua", ns, load.pure_env())
  return ns.Ledger, ns.SyncProtocol, ns.SyncSchedule
end

local Ledger, SP, SS = modules()
local TMIN = Ledger.LIMITS.tMin

local T0 = 1794000000
local ANCHOR = 1790089200
local OWN = "Player-1234-0ABCDEF0"
local PEER = "Player-1234-0BBBBBB0"
local OTHER = "Player-1234-0CCCCCC0"
local BASE = 1793000000 -- own entries are signed from here, one a minute

local function guid(n)
  return ("Player-1-%08X"):format(n)
end

-- Own entries 1..n (distinct inns), `(t, inn)` ascending, as ledger:shareWindow gives them.
local function ownEntry(i)
  return { inn = 100 + i, t = BASE + i * 60, phrase = { 1 + i % 40 } }
end

local function win(n)
  local w = {}
  for i = 1, n do
    w[i] = ownEntry(i)
  end
  return w
end

-- The `since` that leaves exactly k entries of win(n) to send.
local function sinceFor(n, k)
  return BASE + (n - k) * 60
end

local function entriesIn(text)
  return select(2, text:gsub(";", "")) + 1
end

-- rand that always gives the lowest value, and a scripted one that records its calls.
local function lowest(lo)
  return lo
end

local function scripted(values)
  local calls, i = {}, 0
  return function(lo, hi)
    calls[#calls + 1] = { lo, hi }
    i = i + 1
    local v = values[i]
    if v == nil then
      return lo
    end
    return v
  end, calls
end

-- A schedule with a recording transport. o.group = "PARTY" / "RAID", o.guild = true,
-- o.window (default win(10)), o.rand, o.memo, o.async (callbacks don't come back by
-- themselves). h.onSend(wire, text, token) may return false to fail a send.
local function harness(o)
  o = o or {}
  local h = {
    sent = {}, heldBy = {}, window = o.window or win(10), async = o.async or false,
    memo = o.memo or SP.newWantMemo(),
  }
  h.s = SS.new({ memo = h.memo, rand = o.rand or lowest })
  if o.group then
    assert(h.s:setChannel("GROUP", o.group))
  end
  if o.guild then
    assert(h.s:setChannel("GUILD", "GUILD"))
  end
  h.io = {
    window = function() return h.window end,
    held = function(g) return h.heldBy[g] or {} end,
    send = function(wire, text, token)
      if h.onSend and h.onSend(wire, text, token) == false then
        return false
      end
      h.sent[#h.sent + 1] = { wire = wire, text = text, token = token, t = h.now }
      if not h.async then
        h.s:sendDone(token) -- the synchronous callback, from inside io.send
      end
      return true
    end,
  }
  function h:pump(now)
    self.now = now
    return self.s:pump(now, self.io)
  end
  -- The messages sent since the last take, and their kinds as a string ("HEEW").
  function h:take()
    local out, kinds = self.sent, {}
    self.sent = {}
    for i, m in ipairs(out) do
      kinds[i] = m.text:sub(1, 1)
    end
    return out, table.concat(kinds)
  end
  return h
end

local function count(list, kind, wire)
  local n = 0
  for _, m in ipairs(list) do
    if m.text:sub(1, 1) == kind and (wire == nil or m.wire == wire) then
      n = n + 1
    end
  end
  return n
end

local function raise()
  error("hidden value touched")
end

local HOSTILE_EVENTS = {
  "__index", "__newindex", "__len", "__eq", "__lt", "__le", "__concat", "__tostring",
  "__call", "__unm", "__add",
}

-- The two hidden-value stand-ins (sync-ledger.md 5.2).
local function hostileTable()
  local mt = {}
  for _, ev in ipairs(HOSTILE_EVENTS) do
    mt[ev] = raise
  end
  return setmetatable({}, mt)
end

local function hostileProxy()
  local u = newproxy(true)
  local mt = getmetatable(u)
  for _, ev in ipairs(HOSTILE_EVENTS) do
    mt[ev] = raise
  end
  return u
end

local function badValues()
  return { { nil }, { "x" }, { 0 / 0 }, { math.huge }, { {} }, { hostileTable() },
    { hostileProxy() } }
end

-- Wraps SP.decideWant for one test; the schedule looks it up at call time.
local function spyDecide()
  local real = SP.decideWant
  local calls = {}
  SP.decideWant = function(...)
    calls[#calls + 1] = { ... }
    return real(...)
  end
  return calls, function() SP.decideWant = real end
end

describe("SyncSchedule module", function()
  it("loads in the strict environment only after SyncProtocol", function()
    assert.has_error(function()
      local ns = {}
      load.file("Ledger.lua", ns, load.pure_env())
      load.file("SyncSchedule.lua", ns, load.pure_env())
    end)
    local _, _, ss = modules()
    assert.is_table(ss)
  end)

  it("has the spec 3.5.2 constants and the logical channel map", function()
    assert.same({
      window = 60, messages = 30, entries = 60, wants = 12, inFlightMax = 2,
      inFlightRelease = 30, helloGap = 60, helloDelay = { 5, 15 }, guildFirst = { 60, 120 },
      guildEvery = { 1200, 1500 }, wantDelay = { 1, 5 }, pendingWantsMax = 200,
      coalesce = 5, replyGap = 30, largeGap = 300, smallMax = 5, resumeDelay = 3,
    }, SS.LIMITS)
    assert.same({ PARTY = "GROUP", RAID = "GROUP", GUILD = "GUILD" }, SS.WIRE_TO_LOGICAL)
  end)

  it("SyncSchedule.new without memo or rand errors", function()
    local f = function() return 1 end
    assert.has_error(function() SS.new() end)
    assert.has_error(function() SS.new({}) end)
    assert.has_error(function() SS.new({ memo = {} }) end)
    assert.has_error(function() SS.new({ rand = f }) end)
    assert.has_error(function() SS.new({ memo = "memo", rand = f }) end)
    assert.has_error(function() SS.new({ memo = {}, rand = {} }) end)
    assert.has_error(function() SS.new(hostileTable()) end)
    assert.is_table(SS.new({ memo = {}, rand = f }))
  end)

  it("is idle when new: nothing pending, pump returns nil", function()
    local h = harness({ group = "PARTY", guild = true })
    assert.is_nil(h:pump(T0))
    assert.same({
      hellos = 0, wants = 0, buckets = 0, progress = 0, inFlight = 0, records = 0,
      wantRecords = 0, held = false, sendFailed = 0,
    }, h.s:snapshot())
  end)
end)

describe("SyncSchedule budget", function()
  it("30 messages at t = 0: the 31st waits until t = 60, not 59", function()
    -- The schedule's own gates can't hand over 30 messages at one instant: 2 HELLOs,
    -- 12 WANTs and at most 15 reply messages sharing the 60 entries make at most 29. So
    -- the 30 budget records are seeded directly; the cap is a backstop.
    local h = harness({ group = "PARTY" })
    for _ = 1, 30 do
      h.s.msgs[#h.s.msgs + 1] = { t = T0, n = 0 }
    end
    assert.is_true(h.s:requestHello("GROUP", T0, 0, 0))
    assert.equal(T0 + 60, h:pump(T0))
    assert.equal(T0 + 60, h:pump(T0 + 59))
    assert.equal(0, #h.sent)
    assert.equal(30, h.s:snapshot().records)
    assert.is_nil(h:pump(T0 + 60))
    assert.equal("H", select(2, h:take()))
    assert.equal(1, h.s:snapshot().records) -- the 30 expired at exactly t + 60
  end)

  it("12 five-entry messages at t = 0: a 13th waits, while a HELLO (0 entries) still goes",
    function()
    local h = harness({ group = "PARTY", guild = true, window = win(40) })
    h.s:onWant("PARTY", 0, h.window, T0 - 5)
    h.s:onWant("GUILD", 0, h.window, T0 - 5)
    assert.equal(T0 + 60, h:pump(T0))
    local sent = h:take()
    assert.equal(12, #sent)
    assert.equal(8, count(sent, "E", "PARTY"))
    assert.equal(4, count(sent, "E", "GUILD"))
    for _, m in ipairs(sent) do
      assert.equal(5, entriesIn(m.text))
    end
    assert.is_true(h.s:requestHello("GROUP", T0 + 1, 0, 0))
    assert.equal(T0 + 60, h:pump(T0 + 1))
    assert.equal("H", select(2, h:take()))
    assert.equal(T0 + 60, h:pump(T0 + 59))
    assert.equal(0, #h.sent)
    assert.is_nil(h:pump(T0 + 60))
    assert.equal(4, count(h:take(), "E", "GUILD"))
  end)

  it("the 13th WANT in 60 s waits while a HELLO can still go", function()
    local h = harness({ group = "PARTY" })
    for i = 1, 13 do
      h.s:onHello(guid(i), "PARTY", 3, 1000 + i, T0 - 1) -- due T0
    end
    assert.equal(T0 + 60, h:pump(T0))
    local sent = h:take()
    assert.equal(12, count(sent, "W", "PARTY"))
    assert.equal(1, h.s:snapshot().wants)
    assert.is_true(h.s:requestHello("GROUP", T0 + 1, 0, 0))
    assert.equal(T0 + 60, h:pump(T0 + 1))
    assert.equal("H", select(2, h:take()))
    assert.equal(T0 + 60, h:pump(T0 + 59))
    assert.equal(0, #h.sent)
    assert.is_nil(h:pump(T0 + 60))
    local last = h:take()
    assert.equal(1, count(last, "W"))
    assert.equal(SP.encodeWant(guid(13), 0), last[1].text)
  end)

  it("a third message waits while 2 are in flight and goes after sendDone", function()
    local h = harness({ group = "PARTY", window = win(15), async = true })
    h.s:onWant("PARTY", 0, h.window, T0 - 5)
    assert.equal(T0 + 30, h:pump(T0)) -- the in-flight release
    local sent = h:take()
    assert.equal(2, #sent)
    assert.equal(2, h.s:snapshot().inFlight)
    assert.is_true(h.s:sendDone(sent[1].token))
    assert.is_false(h.s:sendDone(sent[1].token)) -- once only
    assert.is_nil(h:pump(T0 + 1))
    assert.equal(1, #h:take())
  end)

  it("a third message goes after 30 s with no callback", function()
    local h = harness({ group = "PARTY", window = win(15), async = true })
    h.s:onWant("PARTY", 0, h.window, T0 - 5)
    assert.equal(T0 + 30, h:pump(T0))
    assert.equal(2, #h:take())
    assert.equal(T0 + 30, h:pump(T0 + 29))
    assert.equal(0, #h.sent)
    assert.is_nil(h:pump(T0 + 30))
    assert.equal(1, #h:take())
    assert.equal(1, h.s:snapshot().inFlight) -- the third's own callback is still out
  end)

  it("sendDone from inside io.send frees the slot at once", function()
    local h = harness({ group = "PARTY", window = win(40) })
    h.s:onWant("PARTY", 0, h.window, T0 - 5)
    assert.is_nil(h:pump(T0))
    local sent = h:take()
    assert.equal(8, #sent)
    for i, m in ipairs(sent) do
      assert.equal(i, m.token) -- a fresh integer token each
    end
    assert.equal(0, h.s:snapshot().inFlight)
    assert.equal(8, h.s:snapshot().records)
  end)

  it("ignores an unknown token", function()
    local h = harness({ group = "PARTY", window = win(15), async = true })
    h.s:onWant("PARTY", 0, h.window, T0 - 5)
    h:pump(T0)
    for _, tok in ipairs({ 0, 3, 99, -1, 1.5, "1", 0 / 0 }) do
      assert.is_false(h.s:sendDone(tok))
    end
    assert.equal(2, h.s:snapshot().inFlight)
  end)

  it("io.send returning false removes the record and drops the item", function()
    -- A failed HELLO clears its pending.
    local h = harness({ group = "PARTY" })
    h.onSend = function() return false end
    h.s:requestHello("GROUP", T0, 0, 0)
    assert.is_nil(h:pump(T0))
    local snap = h.s:snapshot()
    assert.equal(0, snap.records)
    assert.equal(0, snap.inFlight)
    assert.equal(0, snap.hellos)
    assert.equal(1, snap.sendFailed)
    -- A failed WANT is gone.
    h.s:onHello(PEER, "PARTY", 3, 77, T0)
    assert.is_nil(h:pump(T0 + 1))
    snap = h.s:snapshot()
    assert.equal(0, snap.wants)
    assert.equal(0, snap.wantRecords)
    assert.equal(2, snap.sendFailed)
    -- A failed reply message drops the rest of that reply.
    local n = 0
    h.onSend = function()
      n = n + 1
      return n ~= 2
    end
    h.s:onWant("PARTY", 0, h.window, T0 + 1)
    h.window = win(15)
    h.s:onWant("PARTY", 0, h.window, T0 + 1)
    assert.is_nil(h:pump(T0 + 6))
    assert.equal(1, #h:take())
    snap = h.s:snapshot()
    assert.equal(1, snap.records)
    assert.equal(0, snap.progress)
    assert.equal(0, snap.buckets)
    assert.equal(3, snap.sendFailed)
  end)

  it("a failure after a synchronous callback leaves the in-flight count right", function()
    local h = harness({ group = "PARTY" })
    h.onSend = function(_, _, token)
      h.s:sendDone(token)
      return false
    end
    h.s:requestHello("GROUP", T0, 0, 0)
    h:pump(T0)
    assert.equal(0, h.s:snapshot().inFlight)
    assert.equal(0, h.s:snapshot().records)
  end)

  it("the clock going back 1 hour doesn't freeze sends past one window", function()
    local h = harness({ group = "PARTY", guild = true, window = win(40) })
    h.s:requestHello("GROUP", T0 - 5, 0, 0)
    h.s:onWant("PARTY", 0, h.window, T0 - 5)
    h.s:onWant("GUILD", 0, h.window, T0 - 5)
    h:pump(T0)
    assert.equal(13, #h:take()) -- a HELLO and 12 five-entry messages
    local back = T0 - 3600
    assert.equal(back + 60, h:pump(back))
    assert.equal(0, #h.sent)
    h.s:requestHello("GROUP", back + 1, 0, 0)
    assert.equal(back + 60, h:pump(back + 59))
    assert.equal(0, #h.sent)
    assert.is_nil(h:pump(back + 60))
    local sent = h:take()
    assert.equal(1, count(sent, "H"))
    assert.equal(4, count(sent, "E", "GUILD"))
  end)

  it("releases in-flight hand-offs one release time after the clock goes back", function()
    local h = harness({ group = "PARTY", window = win(15), async = true })
    h.s:onWant("PARTY", 0, h.window, T0)
    assert.equal(T0 + 35, h:pump(T0 + 5))
    assert.equal(2, #h:take())
    local back = T0 - 3600
    assert.equal(back + 30, h:pump(back)) -- not T0 + 35, an hour out
    assert.is_nil(h:pump(back + 30))
    assert.equal(1, #h:take())
  end)

  it("caps due times after a jump back at their kind's longest delay", function()
    local h = harness({ group = "PARTY", guild = true })
    h.s:requestHello("GUILD", T0, 1500, 1500)
    h.s:onHello(PEER, "PARTY", 3, 5, T0 + 3600) -- due T0 + 3601
    h.s:onWant("PARTY", 0, h.window, T0 + 3600) -- due T0 + 3605
    -- Back to T0: the WANT and the reply are due within 5 s, not an hour out.
    assert.equal(T0 + 5, h:pump(T0))
    assert.equal(T0 + 1500, h:pump(T0 + 5)) -- then only the GUILD HELLO is left
    local _, kinds = h:take()
    assert.equal("EEW", kinds)
    -- A HELLO due far ahead is capped at now + 1500.
    local g = harness({ group = "PARTY" })
    g.s:requestHello("GROUP", T0 + 90000, 1500, 1500)
    assert.equal(T0 + 1500, g:pump(T0))
  end)
end)

describe("SyncSchedule HELLO", function()
  it("jitters from rand(5, 15)", function()
    local rand, calls = scripted({ 9 })
    local h = harness({ group = "PARTY", rand = rand })
    assert.is_true(h.s:requestHello("GROUP", T0, 5, 15))
    assert.same({ { 5, 15 } }, calls)
    assert.equal(T0 + 9, h:pump(T0))
    assert.equal(T0 + 9, h:pump(T0 + 8))
    assert.equal(0, #h.sent)
    assert.is_nil(h:pump(T0 + 9))
    local sent = h:take()
    assert.equal(1, #sent)
    assert.equal("PARTY", sent[1].wire)
    assert.equal(SP.encodeHello(h.window), sent[1].text)
  end)

  it("repeated requestHello keeps one HELLO and never delays it", function()
    local rand = scripted({ 12, 15, 6 })
    local h = harness({ group = "PARTY", rand = rand })
    h.s:requestHello("GROUP", T0, 5, 15)     -- due T0 + 12
    h.s:requestHello("GROUP", T0 + 1, 5, 15) -- T0 + 16: later, ignored
    assert.equal(1, h.s:snapshot().hellos)
    assert.equal(T0 + 12, h:pump(T0 + 1))
    h.s:requestHello("GROUP", T0 + 2, 5, 15) -- T0 + 8: earlier, taken
    assert.equal(T0 + 8, h:pump(T0 + 2))
    assert.is_nil(h:pump(T0 + 8))
    assert.equal(1, #h:take())
    assert.is_nil(h:pump(T0 + 12))
    assert.equal(0, #h.sent)
  end)

  it("sends 1 per channel per 60 s even when requested every second", function()
    local h = harness({ group = "PARTY" })
    local wake
    for t = T0, T0 + 179 do
      h.s:requestHello("GROUP", t, 5, 15)
      wake = h:pump(t)
      assert.is_true(wake == nil or wake >= t + 1) -- nil right after a send
    end
    local sent = h:take()
    assert.equal(3, #sent)
    assert.same({ T0 + 5, T0 + 65, T0 + 125 }, { sent[1].t, sent[2].t, sent[3].t })
    assert.equal(T0 + 185, wake) -- the gate, not the 5 s due
  end)

  it("an empty window sends nothing and doesn't stamp the gate", function()
    local h = harness({ group = "PARTY", window = {} })
    h.s:requestHello("GROUP", T0, 5, 15)
    assert.equal(T0 + 5, h:pump(T0))
    assert.is_nil(h:pump(T0 + 5))
    assert.equal(0, #h.sent)
    assert.equal(0, h.s:snapshot().hellos)
    h.window = win(1)
    h.s:requestHello("GROUP", T0 + 6, 0, 0)
    assert.is_nil(h:pump(T0 + 6)) -- not held back by a gate
    assert.equal("H1:1:" .. SP.digest(h.window), h:take()[1].text)
  end)

  it("GUILD reschedules after a send and after a skip", function()
    local rand, calls = scripted({ 60, 1300, 1450 })
    local h = harness({ guild = true, rand = rand })
    h.s:requestHello("GUILD", T0, 60, 120)
    assert.equal(T0 + 60, h:pump(T0))
    assert.equal(T0 + 60 + 1300, h:pump(T0 + 60)) -- sent, next one set
    assert.equal(1, count(h:take(), "H", "GUILD"))
    assert.same({ 1200, 1500 }, calls[2])
    assert.equal(1, h.s:snapshot().hellos)
    h.window = {}
    assert.equal(T0 + 1360 + 1450, h:pump(T0 + 1360)) -- skipped, next one set
    assert.equal(0, #h.sent)
    assert.same({ 1200, 1500 }, calls[3])
  end)

  it("an unavailable channel ignores requests", function()
    local h = harness({ group = "PARTY" })
    assert.is_false(h.s:requestHello("GUILD", T0, 5, 15))
    assert.is_false(h.s:requestHello("RAID", T0, 5, 15))
    assert.equal(0, h.s:snapshot().hellos)
    assert.is_nil(h:pump(T0 + 100))
    assert.equal(0, #h.sent)
  end)

  it("keeps GROUP and GUILD independent", function()
    local h = harness({ group = "RAID", guild = true })
    h.s:requestHello("GROUP", T0, 0, 0)
    assert.is_nil(h:pump(T0))
    assert.equal("RAID", h:take()[1].wire)
    h.s:requestHello("GUILD", T0 + 1, 0, 0)
    h.s:requestHello("GROUP", T0 + 1, 0, 0)
    assert.equal(T0 + 60, h:pump(T0 + 1)) -- GUILD goes, GROUP waits for its own gate
    local sent = h:take()
    assert.equal(1, #sent)
    assert.equal("GUILD", sent[1].wire)
    assert.equal(T0 + 1201, h:pump(T0 + 60)) -- next: the periodic GUILD HELLO
    assert.equal("RAID", h:take()[1].wire)
  end)
end)

describe("SyncSchedule WANT", function()
  it("keeps one pending per peer; a newer HELLO replaces count and digest and keeps due", function()
    local calls, restore = spyDecide()
    finally(restore)
    local h = harness({ group = "PARTY", rand = scripted({ 4, 1 }) })
    assert.is_true(h.s:onHello(PEER, "PARTY", 3, 111, T0))
    assert.is_true(h.s:onHello(PEER, "PARTY", 5, 222, T0 + 2))
    assert.equal(1, h.s:snapshot().wants)
    assert.equal(T0 + 4, h:pump(T0 + 3))
    assert.equal(0, #calls)
    assert.is_nil(h:pump(T0 + 4))
    assert.equal(1, #calls)
    local c = calls[1]
    assert.equal(PEER, c[2])
    assert.equal("PARTY", c[3])
    assert.equal(5, c[4])
    assert.equal(222, c[5])
    assert.equal(T0 + 4, c[7])
    assert.equal(SP.encodeWant(PEER, 0), h:take()[1].text)
  end)

  it("takes the GROUP-first channel: a GROUP HELLO moves a pending GUILD WANT", function()
    local h = harness({ group = "PARTY", guild = true })
    h.s:onHello(PEER, "GUILD", 3, 111, T0)
    h.s:onHello(PEER, "PARTY", 3, 111, T0)
    assert.is_nil(h:pump(T0 + 1))
    local sent = h:take()
    assert.equal(1, #sent)
    assert.equal("PARTY", sent[1].wire)
  end)

  it("a GUILD HELLO doesn't move a pending GROUP WANT", function()
    local h = harness({ group = "PARTY", guild = true })
    h.s:onHello(PEER, "PARTY", 3, 111, T0)
    h.s:onHello(PEER, "GUILD", 4, 112, T0)
    h.s:onHello(OTHER, "GUILD", 3, 111, T0)
    h.s:onHello(OTHER, "GUILD", 3, 113, T0) -- GUILD to GUILD stays GUILD
    assert.is_nil(h:pump(T0 + 1))
    local sent = h:take()
    assert.equal(2, #sent)
    assert.equal("PARTY", sent[1].wire)
    assert.equal(SP.encodeWant(PEER, 0), sent[1].text)
    assert.equal("GUILD", sent[2].wire)
  end)

  it("ignores count = 0, bad arguments and an unavailable channel", function()
    local h = harness({ group = "PARTY" })
    assert.is_false(h.s:onHello(PEER, "PARTY", 0, 0, T0))
    assert.is_false(h.s:onHello(PEER, "PARTY", 41, 5, T0))
    assert.is_false(h.s:onHello(PEER, "PARTY", 3, -1, T0))
    assert.is_false(h.s:onHello("Mira", "PARTY", 3, 5, T0))
    assert.is_false(h.s:onHello(PEER, "GUILD", 3, 5, T0))
    assert.is_false(h.s:onHello(PEER, "WHISPER", 3, 5, T0))
    assert.equal(0, h.s:snapshot().wants)
    assert.is_nil(h:pump(T0 + 10))
  end)

  it("ignores the 201st peer", function()
    local h = harness({ group = "PARTY" })
    for i = 1, 200 do
      assert.is_true(h.s:onHello(guid(i), "PARTY", 3, i, T0))
    end
    assert.is_false(h.s:onHello(guid(201), "PARTY", 3, 201, T0))
    assert.is_true(h.s:onHello(guid(200), "PARTY", 4, 999, T0)) -- a pending peer updates
    assert.equal(200, h.s:snapshot().wants)
  end)

  it("orders by due, then GUID bytes", function()
    -- "B" (66) sorts before "a" (97) by bytes; many locales' collation says otherwise.
    local lower, upper, early = "Player-1-0000000a", "Player-1-0000000B", guid(99)
    local h = harness({ group = "PARTY", rand = scripted({ 2, 2, 1 }) })
    h.s:onHello(lower, "PARTY", 3, 1, T0)
    h.s:onHello(upper, "PARTY", 3, 1, T0)
    h.s:onHello(early, "PARTY", 3, 1, T0)
    assert.equal(T0 + 1, h:pump(T0))
    assert.is_nil(h:pump(T0 + 2))
    local sent = h:take()
    assert.equal(3, #sent)
    assert.equal(SP.encodeWant(early, 0), sent[1].text)
    assert.equal(SP.encodeWant(upper, 0), sent[2].text)
    assert.equal(SP.encodeWant(lower, 0), sent[3].text)
  end)

  it("calls decideWant only when the budget admits a WANT", function()
    local h = harness({ group = "PARTY" })
    for i = 1, 12 do
      h.s:onHello(guid(i), "PARTY", 3, i, T0 - 1)
    end
    h:pump(T0)
    assert.equal(12, #h:take())
    local calls, restore = spyDecide()
    finally(restore)
    h.s:onHello(PEER, "PARTY", 3, 5, T0)
    for t = T0 + 1, T0 + 59 do
      assert.equal(T0 + 60, h:pump(t))
    end
    assert.equal(0, #calls)
    assert.is_nil(h:pump(T0 + 60))
    assert.equal(1, #calls)
    assert.equal(1, #h:take())
  end)

  it("a nil decision costs no budget", function()
    local h = harness({ group = "PARTY" })
    local theirs = { ownEntry(1), ownEntry(2) }
    h.heldBy[PEER] = theirs
    h.s:onHello(PEER, "PARTY", 2, SP.digest(theirs), T0) -- we're in sync
    assert.is_nil(h:pump(T0 + 1))
    local snap = h.s:snapshot()
    assert.equal(0, #h.sent)
    assert.equal(0, snap.wants)
    assert.equal(0, snap.records)
    assert.equal(0, snap.wantRecords)
  end)

  it("a HELLO churning its digest every second for 10 minutes gets <= 2 WANTs out", function()
    local h = harness({ group = "PARTY" })
    for t = 0, 599 do
      h.s:onHello(PEER, "PARTY", 5, 1000 + t, T0 + t)
      local wake = h:pump(T0 + t)
      assert.is_true(wake == nil or wake >= T0 + t + 1)
      assert.is_true(h.s:snapshot().wants <= 1)
    end
    local wants = count(h:take(), "W")
    assert.is_true(wants >= 1 and wants <= 2)
  end)

  it("a WANT seen from someone else within 30 s on that channel suppresses ours", function()
    -- Through the real memo: SyncProtocol.receive records the other asker's WANT.
    local function run(channel)
      local h = harness({ group = "PARTY", guild = true })
      local ctx = {
        now = T0, selfGUID = OWN, inns = {}, phrases = {}, seals = {},
        ledger = Ledger.new({}, { guid = OWN, name = "Aldric" }, ANCHOR),
        limiter = SP.newLimiter(), wantMemo = h.memo,
      }
      local r = SP.receive("W1:" .. PEER .. ":0", channel, { guid = OTHER, name = "Bram" }, ctx)
      assert.equal("want_seen", r.kind)
      h.s:onHello(PEER, "PARTY", 3, 42, T0 + 10)
      assert.is_nil(h:pump(T0 + 11))
      return count(h:take(), "W")
    end
    assert.equal(0, run("PARTY"))
    assert.equal(1, run("GUILD")) -- a WANT on another channel doesn't cover ours
  end)
end)

describe("SyncSchedule replies", function()
  it("coalesces WANTs at t = 0, 2, 4 into one reply at t = 5 with the smallest since", function()
    local h = harness({ group = "PARTY", window = win(10) })
    assert.is_true(h.s:onWant("PARTY", sinceFor(10, 3), h.window, T0))
    assert.equal(T0 + 5, h:pump(T0))
    assert.is_true(h.s:onWant("PARTY", sinceFor(10, 4), h.window, T0 + 2))
    assert.is_true(h.s:onWant("PARTY", sinceFor(10, 2), h.window, T0 + 4))
    assert.equal(T0 + 5, h:pump(T0 + 4)) -- later WANTs don't extend the 5 s
    assert.equal(0, #h.sent)
    assert.is_nil(h:pump(T0 + 5))
    local sent = h:take()
    assert.equal(1, #sent)
    assert.equal(SP.encodeEntries(h.window, sinceFor(10, 4))[1], sent[1].text)
    -- A WANT at t = 6 isn't in it; it waits for the 30 s gate.
    h.s:onWant("PARTY", sinceFor(10, 5), h.window, T0 + 6)
    assert.equal(T0 + 35, h:pump(T0 + 6))
    assert.equal(T0 + 35, h:pump(T0 + 34))
    assert.equal(0, #h.sent)
    assert.is_nil(h:pump(T0 + 35))
    assert.equal(5, entriesIn(h:take()[1].text))
  end)

  it("starts 1 reply per channel per 30 s", function()
    local h = harness({ group = "PARTY", guild = true, window = win(10) })
    h.s:onWant("PARTY", sinceFor(10, 1), h.window, T0)
    h.s:onWant("GUILD", sinceFor(10, 1), h.window, T0)
    assert.is_nil(h:pump(T0 + 5))
    assert.equal(2, #h:take()) -- one per channel
    for i = 1, 20 do
      h.s:onWant("PARTY", sinceFor(10, 2), h.window, T0 + 5 + i)
      assert.equal(T0 + 35, h:pump(T0 + 5 + i))
    end
    assert.equal(0, #h.sent)
    assert.is_nil(h:pump(T0 + 35))
    assert.equal(1, #h:take())
  end)

  it("classifies 5 entries as small and 6 as large", function()
    local h = harness({ group = "PARTY", window = win(20) })
    h.s:onWant("PARTY", sinceFor(20, 6), h.window, T0) -- large: 2 messages, stamps the gate
    assert.is_nil(h:pump(T0 + 5))
    local sent = h:take()
    assert.equal(2, #sent)
    assert.same({ 5, 1 }, { entriesIn(sent[1].text), entriesIn(sent[2].text) })
    h.s:onWant("PARTY", sinceFor(20, 5), h.window, T0 + 40) -- small: not gated
    assert.is_nil(h:pump(T0 + 45))
    sent = h:take()
    assert.equal(1, #sent)
    assert.equal(5, entriesIn(sent[1].text))
    h.s:onWant("PARTY", sinceFor(20, 6), h.window, T0 + 80) -- large again: gated
    assert.equal(T0 + 305, h:pump(T0 + 85))
    assert.equal(0, #h.sent)
    assert.is_nil(h:pump(T0 + 305))
    assert.equal(2, #h:take())
  end)

  it("a large reply stamps the gate; a 2nd large ask in 5 minutes is deferred, then sent once",
    function()
    local h = harness({ group = "PARTY", window = win(40) })
    h.s:onWant("PARTY", 0, h.window, T0)
    assert.is_nil(h:pump(T0 + 5))
    assert.equal(8, #h:take())
    h.s:onWant("PARTY", 0, h.window, T0 + 60)
    assert.equal(T0 + 305, h:pump(T0 + 65))
    local sends = {}
    for t = T0 + 66, T0 + 700 do
      h:pump(t)
      for _, m in ipairs(h:take()) do
        sends[#sends + 1] = m.t
      end
    end
    assert.equal(8, #sends) -- exactly one more full reply
    assert.equal(T0 + 305, sends[1])
    assert.equal(0, h.s:snapshot().buckets)
  end)

  it("a changed window opens the gate early", function()
    local h = harness({ group = "PARTY", window = win(39) })
    h.s:onWant("PARTY", 0, h.window, T0)
    assert.is_nil(h:pump(T0 + 5))
    assert.equal(8, #h:take())
    h.window = win(40) -- we signed again
    h.s:onWant("PARTY", 0, h.window, T0 + 60)
    assert.is_nil(h:pump(T0 + 65))
    assert.equal(8, #h:take())
    -- And the new stamp gates the next large ask on the new window.
    h.s:onWant("PARTY", 0, h.window, T0 + 100)
    assert.equal(T0 + 365, h:pump(T0 + 105))
  end)

  it("since = tMin is large and gated (the bypass test)", function()
    local h = harness({ group = "PARTY", window = win(40) })
    local replies = 0
    for t = T0, T0 + 599 do
      if (t - T0) % 30 == 0 then
        h.s:onWant("PARTY", TMIN, h.window, t)
      end
      h:pump(t)
      local sent = h:take()
      for _, m in ipairs(sent) do
        assert.equal(5, entriesIn(m.text))
      end
      replies = replies + (#sent > 0 and 1 or 0)
    end
    assert.equal(2, replies) -- at T0 + 5 and T0 + 305, no others
  end)

  it("small replies continue at the 30 s gate while a large one is deferred", function()
    local h = harness({ group = "PARTY", window = win(40) })
    h.s:onWant("PARTY", 0, h.window, T0)
    h:pump(T0 + 5)
    assert.equal(8, #h:take())
    h.s:onWant("PARTY", 0, h.window, T0 + 40)
    h.s:onWant("PARTY", sinceFor(40, 2), h.window, T0 + 40)
    assert.equal(T0 + 305, h:pump(T0 + 45))
    local sent = h:take()
    assert.equal(1, #sent)
    assert.equal(2, entriesIn(sent[1].text))
    h.s:onWant("PARTY", sinceFor(40, 3), h.window, T0 + 60)
    assert.equal(T0 + 75, h:pump(T0 + 65))
    assert.equal(T0 + 305, h:pump(T0 + 75)) -- the small one went, the large one waits
    assert.equal(3, entriesIn(h:take()[1].text))
    assert.is_nil(h:pump(T0 + 305))
    assert.equal(8, #h:take())
  end)

  it("a large reply clears a covered small ask", function()
    local h = harness({ group = "PARTY", window = win(40) })
    h.s:onWant("PARTY", sinceFor(40, 2), h.window, T0)
    h.s:onWant("PARTY", 0, h.window, T0 + 1)
    assert.equal(2, h.s:snapshot().buckets)
    assert.is_nil(h:pump(T0 + 5))
    assert.equal(8, #h:take())
    assert.equal(0, h.s:snapshot().buckets)
    assert.is_nil(h:pump(T0 + 35))
    assert.equal(0, #h.sent)
  end)

  it("keeps a small ask the large reply doesn't cover", function()
    -- Only a window that shrank between the asks can do this; the small ask survives.
    local h = harness({ group = "PARTY", window = win(20) })
    h.s:onWant("PARTY", sinceFor(20, 10), h.window, T0) -- large, since = entry 10
    local short = win(12)
    h.s:onWant("PARTY", sinceFor(12, 3), short, T0)     -- small, since = entry 9
    assert.equal(T0 + 35, h:pump(T0 + 5))
    assert.equal(2, #h:take())
    assert.equal(1, h.s:snapshot().buckets)
    -- On our window it's 11 entries now: large, and the gate is closed.
    assert.equal(T0 + 305, h:pump(T0 + 35))
    assert.equal(0, #h.sent)
    assert.is_nil(h:pump(T0 + 305))
    assert.equal(3, #h:take())
  end)

  it("a small ask that grows past 5 entries becomes large", function()
    local h = harness({ group = "PARTY", window = win(38) })
    h.s:onWant("PARTY", 0, h.window, T0)
    h:pump(T0 + 5)
    assert.equal(8, #h:take())
    h.s:onWant("PARTY", sinceFor(38, 4), h.window, T0 + 40) -- small: 4 entries
    h.window = win(40)                                       -- now 6 are newer
    assert.is_nil(h:pump(T0 + 45))
    local sent = h:take()
    assert.equal(2, #sent) -- sent as large (the window changed, so the gate is open)
    -- It stamped the large gate: another large ask on this window waits.
    h.s:onWant("PARTY", 0, h.window, T0 + 80)
    assert.equal(T0 + 345, h:pump(T0 + 85))
  end)

  it("a grown small ask behind a closed gate waits for the gate", function()
    local h = harness({ group = "PARTY", window = win(40) })
    h.s:onWant("PARTY", 0, h.window, T0)
    h:pump(T0 + 5)
    assert.equal(8, #h:take()) -- the gate is stamped with this window's digest
    -- Classified against an older window (4 newer entries); on ours it's 6.
    h.s:onWant("PARTY", sinceFor(40, 6), win(38), T0 + 40)
    assert.equal(T0 + 305, h:pump(T0 + 45))
    assert.equal(0, #h.sent)
    assert.is_nil(h:pump(T0 + 305))
    assert.equal(2, #h:take())
  end)

  it("n = 0 sends nothing and stamps nothing", function()
    local h = harness({ group = "PARTY", window = win(10) })
    assert.is_false(h.s:onWant("PARTY", sinceFor(10, 0), h.window, T0))
    assert.equal(0, h.s:snapshot().buckets)
    assert.is_nil(h:pump(T0 + 5))
    -- An ask whose entries are gone by reply time (a window that shrank) clears quietly.
    h.s:onWant("PARTY", sinceFor(10, 3), h.window, T0 + 6)
    h.s:onWant("PARTY", 0, win(20), T0 + 6) -- large, then the window shrinks under it
    h.window = {}
    assert.is_nil(h:pump(T0 + 11))
    assert.equal(0, #h.sent)
    assert.equal(0, h.s:snapshot().buckets)
    -- Nothing was stamped: the next ask is answered after 5 s, not 30.
    h.window = win(10)
    h.s:onWant("PARTY", sinceFor(10, 2), h.window, T0 + 12)
    assert.is_nil(h:pump(T0 + 17))
    assert.equal(1, #h:take())
  end)

  it("a full reply is 8 messages, sent as the budget admits, with the right entry count each",
    function()
    local h = harness({ group = "PARTY", guild = true, window = win(38) })
    h.s:onWant("GUILD", 0, h.window, T0) -- takes 38 of the 60 entries first
    h:pump(T0 + 5)
    assert.equal(8, #h:take())
    h.s:onWant("PARTY", 0, h.window, T0 + 10)
    assert.equal(T0 + 65, h:pump(T0 + 15))
    local first = h:take()
    assert.equal(4, #first) -- 20 more entries fit, then the budget waits
    assert.is_nil(h:pump(T0 + 65))
    local rest = h:take()
    assert.equal(4, #rest)
    local expect = SP.encodeEntries(h.window, 0)
    local counts = {}
    for i, m in ipairs({ first[1], first[2], first[3], first[4], rest[1], rest[2], rest[3],
      rest[4] }) do
      assert.equal(expect[i], m.text)
      assert.equal("PARTY", m.wire)
      counts[i] = entriesIn(m.text)
    end
    assert.same({ 5, 5, 5, 5, 5, 5, 5, 3 }, counts)
  end)

  it("ignores a WANT with nothing to send, a bad since or an unavailable channel", function()
    local h = harness({ group = "PARTY" })
    assert.is_false(h.s:onWant("GUILD", 0, h.window, T0))
    assert.is_false(h.s:onWant("WHISPER", 0, h.window, T0))
    assert.is_false(h.s:onWant("PARTY", -1, h.window, T0))
    assert.is_false(h.s:onWant("PARTY", 0, {}, T0))
    assert.is_false(h.s:onWant("PARTY", 0, { "junk", { t = "x" } }, T0))
    assert.is_nil(h:pump(T0 + 10))
  end)
end)

describe("SyncSchedule channels", function()
  local function loaded()
    local h = harness({ group = "PARTY", guild = true, window = win(40), async = true })
    h.s:requestHello("GROUP", T0, 60, 60)
    h.s:requestHello("GUILD", T0, 60, 60)
    h.s:onWant("PARTY", 0, h.window, T0)
    h.s:onWant("GUILD", 0, h.window, T0)
    h:pump(T0 + 5) -- starts both replies; 2 messages in flight, 14 in progress
    assert.equal(2, #h:take())
    h.s:onHello(PEER, "PARTY", 3, 1, T0 + 6)
    h.s:onHello(OTHER, "GUILD", 3, 1, T0 + 6)
    h.s:onWant("PARTY", sinceFor(40, 1), h.window, T0 + 6)
    h.s:onWant("GUILD", sinceFor(40, 1), h.window, T0 + 6)
    return h
  end

  it("setChannel(ch, nil) drops that channel's HELLO, buckets, in-progress messages and WANTs only",
    function()
    local h = loaded()
    local snap = h.s:snapshot()
    assert.same({ 2, 2, 2, 14 }, { snap.hellos, snap.wants, snap.buckets, snap.progress })
    assert.is_true(h.s:setChannel("GROUP", nil))
    snap = h.s:snapshot()
    assert.equal(1, snap.hellos)
    assert.equal(1, snap.wants)
    assert.equal(1, snap.buckets)
    assert.equal(8, snap.progress)
    h.async = false
    h.s:sendDone(1)
    h.s:sendDone(2)
    for t = T0 + 6, T0 + 200 do
      h:pump(t)
    end
    local sent = h:take()
    assert.is_true(#sent > 0)
    for _, m in ipairs(sent) do
      assert.equal("GUILD", m.wire)
    end
    assert.is_false(h.s:requestHello("GROUP", T0 + 200, 0, 0))
  end)

  it("PARTY to RAID keeps pending items and sends them on RAID", function()
    local h = loaded()
    assert.is_true(h.s:setChannel("GROUP", "RAID"))
    assert.equal(14, h.s:snapshot().progress)
    h.async = false
    h.s:sendDone(1)
    h.s:sendDone(2)
    for t = T0 + 6, T0 + 200 do
      h:pump(t)
    end
    local sent = h:take()
    local party = count(sent, "H", "PARTY") + count(sent, "E", "PARTY") + count(sent, "W", "PARTY")
    assert.equal(0, party)
    assert.equal(1, count(sent, "H", "RAID"))
    assert.equal(1, count(sent, "W", "RAID"))
    assert.is_true(count(sent, "E", "RAID") >= 7)
  end)

  it("ignores a bad wire value", function()
    local h = harness({ group = "PARTY" })
    assert.is_false(h.s:setChannel("GROUP", "GUILD"))
    assert.is_false(h.s:setChannel("GUILD", "PARTY"))
    assert.is_false(h.s:setChannel("GUILD", "RAID"))
    assert.is_false(h.s:setChannel("GROUP", "WHISPER"))
    assert.is_false(h.s:setChannel("GROUP", "INSTANCE_CHAT"))
    assert.is_false(h.s:setChannel("PARTY", "PARTY"))
    assert.is_false(h.s:setChannel("GROUP", 1))
    h.s:requestHello("GROUP", T0, 0, 0)
    assert.is_nil(h:pump(T0))
    assert.equal("PARTY", h:take()[1].wire)
    assert.is_false(h.s:requestHello("GUILD", T0, 0, 0))
  end)
end)

describe("SyncSchedule combat hold", function()
  it("held: nothing sent, pump returns nil", function()
    local h = harness({ group = "PARTY" })
    h.s:requestHello("GROUP", T0, 0, 0)
    assert.is_true(h.s:setHeld(true))
    assert.is_nil(h:pump(T0))
    assert.is_nil(h:pump(T0 + 1000))
    assert.equal(0, #h.sent)
    assert.is_true(h.s:snapshot().held)
    assert.is_true(h.s:setHeld(false))
    assert.is_nil(h:pump(T0 + 1001))
    assert.equal(1, #h:take())
  end)

  it("keeps pending bounded under 1 000 HELLOs from 300 peers and 1 000 WANTs while held",
    function()
    local h = harness({ group = "PARTY", guild = true, window = win(40) })
    h.s:setHeld(true)
    for i = 1, 1000 do
      local t = T0 + i
      h.s:onHello(guid(i % 300), i % 2 == 0 and "PARTY" or "GUILD", 1 + i % 40, i, t)
      h.s:onWant(i % 3 == 0 and "GUILD" or "RAID", (i % 7 == 0) and 0 or sinceFor(40, i % 9),
        h.window, t)
      h.s:requestHello(i % 2 == 0 and "GROUP" or "GUILD", t, 5, 15)
      assert.is_nil(h:pump(t))
    end
    local snap = h.s:snapshot()
    assert.equal(200, snap.wants)
    assert.is_true(snap.buckets <= 4)
    assert.equal(2, snap.hellos)
    assert.equal(0, snap.progress)
    assert.equal(0, snap.records)
    assert.equal(0, #h.sent)
  end)

  it("release sends HELLO, replies, WANTs in that order within the budget", function()
    local h = harness({ group = "PARTY", guild = true, window = win(10) })
    h.s:setHeld(true)
    h.s:onHello(PEER, "PARTY", 3, 1, T0)
    h.s:onHello(OTHER, "GUILD", 3, 1, T0)
    h.s:onWant("PARTY", 0, h.window, T0)
    h.s:onWant("GUILD", 0, h.window, T0)
    h.s:requestHello("GROUP", T0, 5, 15)
    h.s:requestHello("GUILD", T0, 5, 15)
    assert.is_nil(h:pump(T0 + 20))
    h.s:setHeld(false)
    assert.equal(T0 + 1220, h:pump(T0 + 20)) -- next: the periodic GUILD HELLO
    local sent, kinds = h:take()
    assert.equal("HHEEEEWW", kinds)
    assert.same({ "PARTY", "GUILD", "PARTY", "PARTY", "GUILD", "GUILD", "PARTY", "GUILD" }, {
      sent[1].wire, sent[2].wire, sent[3].wire, sent[4].wire, sent[5].wire, sent[6].wire,
      sent[7].wire, sent[8].wire,
    })
  end)

  it("an in-progress reply resumes where it stopped", function()
    local h = harness({ group = "PARTY", window = win(40), async = true })
    h.s:onWant("PARTY", 0, h.window, T0)
    h:pump(T0 + 5)
    local first = h:take()
    assert.equal(2, #first)
    h.s:setHeld(true)
    h.s:sendDone(first[1].token)
    h.s:sendDone(first[2].token)
    assert.is_nil(h:pump(T0 + 6))
    assert.equal(6, h.s:snapshot().progress)
    h.s:setHeld(false)
    h.async = false
    assert.is_nil(h:pump(T0 + 100))
    local rest = h:take()
    local expect = SP.encodeEntries(h.window, 0)
    assert.equal(6, #rest)
    for i, m in ipairs(rest) do
      assert.equal(expect[i + 2], m.text)
    end
  end)

  it("setHeld ignores anything but a boolean", function()
    local s = SS.new({ memo = {}, rand = lowest })
    for _, v in ipairs({ 1, "true", {}, 0 / 0 }) do
      assert.is_false(s:setHeld(v))
    end
    assert.is_false(s:setHeld(nil))
    assert.is_false(s:snapshot().held)
  end)
end)

describe("SyncSchedule wake times", function()
  it("is nil when idle", function()
    local h = harness({ group = "PARTY", guild = true })
    assert.is_nil(h:pump(T0))
    h.s:requestHello("GROUP", T0, 0, 0)
    assert.is_nil(h:pump(T0)) -- sent; nothing left
    assert.equal(1, #h:take())
  end)

  it("is the earliest of HELLO, reply, gate and WANT times", function()
    local h = harness({ group = "PARTY", guild = true, rand = scripted({ 40, 3 }) })
    h.s:requestHello("GUILD", T0, 5, 50) -- T0 + 40
    assert.equal(T0 + 40, h:pump(T0))
    h.s:onWant("PARTY", sinceFor(10, 2), h.window, T0 + 1) -- reply at T0 + 6
    assert.equal(T0 + 6, h:pump(T0 + 1))
    h.s:onHello(PEER, "PARTY", 3, 1, T0 + 2) -- WANT due T0 + 5
    assert.equal(T0 + 5, h:pump(T0 + 2))
  end)

  it("is the record expiry when blocked only by the budget", function()
    local h = harness({ group = "PARTY" })
    for i = 1, 12 do
      h.s:onHello(guid(i), "PARTY", 3, i, T0 - 1)
    end
    h:pump(T0)
    h:take()
    h.s:onHello(PEER, "PARTY", 3, 1, T0 + 20)
    assert.equal(T0 + 60, h:pump(T0 + 21))
  end)

  it("is the reply time, not the record expiry, when a reply is due and the budget full", function()
    -- Starting a reply isn't budget-gated; only its messages wait for the budget.
    local h = harness({ group = "PARTY" })
    for _ = 1, 30 do
      h.s.msgs[#h.s.msgs + 1] = { t = T0, n = 0 }
    end
    h.s:onWant("PARTY", h.window[8].t, h.window, T0)
    assert.equal(T0 + 5, h:pump(T0))
    assert.equal(T0 + 60, h:pump(T0 + 5)) -- started: now its message waits for the budget
    assert.equal(1, h.s:snapshot().progress)
    assert.equal(0, #h.sent)
    assert.is_nil(h:pump(T0 + 60))
    assert.equal("E", h:take()[1].text:sub(1, 1))
  end)

  it("is an empty window's HELLO due time even while the HELLO gate is closed", function()
    local h = harness({ group = "PARTY" })
    h.s:requestHello("GROUP", T0, 0, 0)
    h:pump(T0)
    assert.equal(1, count(h:take(), "H", "PARTY"))
    h.window = {}
    h.s:requestHello("GROUP", T0 + 10, 5, 5)
    assert.equal(T0 + 15, h:pump(T0 + 10)) -- its due time, not the gate at T0 + 60
    assert.is_nil(h:pump(T0 + 15))
    assert.equal(0, h.s:snapshot().hellos)
    assert.equal(0, #h.sent)
  end)

  it("is the in-flight release when blocked by the in-flight cap", function()
    local h = harness({ group = "PARTY", window = win(40), async = true })
    h.s:onWant("PARTY", 0, h.window, T0)
    assert.equal(T0 + 35, h:pump(T0 + 5))
    assert.equal(T0 + 35, h:pump(T0 + 20))
  end)

  it("is the large gate's opening when only a gated large ask waits", function()
    local h = harness({ group = "PARTY", window = win(40) })
    h.s:onWant("PARTY", 0, h.window, T0)
    h:pump(T0 + 5)
    h:take()
    h.s:onWant("PARTY", 0, h.window, T0 + 10)
    assert.equal(T0 + 305, h:pump(T0 + 15))
  end)

  it("is the reply gap when the large gate opens before it", function()
    local h = harness({ group = "PARTY", window = win(40) })
    h.s:onWant("PARTY", 0, h.window, T0)
    h:pump(T0 + 5) -- large: the gate opens at T0 + 305
    h.s:onWant("PARTY", sinceFor(40, 1), h.window, T0 + 280)
    h:pump(T0 + 285) -- small: the next reply can start at T0 + 315
    assert.equal(9, #h:take())
    h.s:onWant("PARTY", sinceFor(40, 2), h.window, T0 + 290)
    h.s:onWant("PARTY", 0, h.window, T0 + 290)
    assert.equal(T0 + 315, h:pump(T0 + 295))
    assert.equal(0, #h.sent)
    assert.is_nil(h:pump(T0 + 315)) -- the large one, covering the small one
    assert.equal(8, #h:take())
  end)

  it("is never below now + 1", function()
    local h = harness({ group = "PARTY", guild = true, window = win(40), async = true })
    local seed = 7
    local function roll(n)
      seed = seed * 16807 % 2147483647
      return seed % n
    end
    for t = T0, T0 + 900 do
      local r = roll(10)
      if r == 0 then
        h.s:requestHello(roll(2) == 0 and "GROUP" or "GUILD", t, 0, roll(20))
      elseif r == 1 then
        local wire = roll(2) == 0 and "PARTY" or "GUILD"
        h.s:onHello(guid(roll(50)), wire, 1 + roll(40), roll(1000), t)
      elseif r == 2 then
        h.s:onWant(roll(2) == 0 and "PARTY" or "GUILD", sinceFor(40, roll(41)), h.window, t)
      elseif r == 3 and #h.sent > 0 then
        h.s:sendDone(h.sent[1 + roll(#h.sent)].token)
      end
      local wake = h:pump(t)
      assert.is_true(wake == nil or (wake >= t + 1 and wake % 1 == 0))
    end
    local sent = h:take()
    assert.is_true(#sent > 0)
    -- Never over the budget: at most 30 messages and 60 entries in any 60 s.
    for i = 1, #sent do
      local msgs, entries = 0, 0
      for j = i, #sent do
        if sent[j].t >= sent[i].t + 60 then
          break
        end
        msgs = msgs + 1
        entries = entries + (sent[j].text:sub(1, 1) == "E" and entriesIn(sent[j].text) or 0)
      end
      assert.is_true(msgs <= 30 and entries <= 60)
    end
  end)
end)

describe("SyncSchedule never throws", function()
  local function io()
    return {
      window = function() return win(10) end,
      held = function() return {} end,
      send = function() return true end,
    }
  end

  local CALLS = {
    { "setChannel", { "GROUP", "PARTY" }, 2 },
    { "setHeld", { true }, 1 },
    { "requestHello", { "GROUP", T0, 5, 15 }, 4 },
    { "onHello", { PEER, "PARTY", 3, 12345, T0 }, 5 },
    { "onWant", { "PARTY", 0, win(10), T0 }, 4 },
    { "pump", { T0 + 10, io() }, 2 },
    { "sendDone", { 1 }, 1 },
    { "snapshot", {}, 0 },
  }

  it("every method, each argument nil, a string, NaN, inf, a table or a hidden-value stand-in",
    function()
    for _, call in ipairs(CALLS) do
      local name, args, n = call[1], call[2], call[3]
      for pos = 0, n do
        for _, bad in ipairs(badValues()) do
          local s = SS.new({ memo = SP.newWantMemo(), rand = lowest })
          s:setChannel("GROUP", "PARTY")
          s:onWant("PARTY", 0, win(10), T0)
          local self, a = s, {}
          for i = 1, n do
            a[i] = args[i]
          end
          if pos == 0 then
            self = bad[1]
          else
            a[pos] = bad[1]
          end
          local ok, err = pcall(s[name], self, unpack(a, 1, n))
          assert.is_true(ok, name .. " arg " .. pos .. ": " .. tostring(err))
        end
      end
    end
  end)

  it("returns false (or nil) for a wrong-type argument and leaves the state alone", function()
    local s = SS.new({ memo = SP.newWantMemo(), rand = lowest })
    assert.is_false(s:setChannel(hostileTable(), "PARTY"))
    assert.is_false(s:requestHello("GROUP", 0 / 0, 5, 15))
    assert.is_false(s:onHello(hostileProxy(), "PARTY", 3, 1, T0))
    assert.is_false(s:onWant("PARTY", math.huge, win(10), T0))
    assert.is_false(s:onWant("PARTY", 0, hostileProxy(), T0))
    assert.is_nil(s:pump(T0, hostileProxy()))
    assert.is_nil(s:pump(T0, { window = 1, held = 2, send = 3 }))
    assert.is_nil(s:pump(-1, io()))
    assert.is_nil(s.snapshot(hostileTable()))
    assert.same({
      hellos = 0, wants = 0, buckets = 0, progress = 0, inFlight = 0, records = 0,
      wantRecords = 0, held = false, sendFailed = 0,
    }, s:snapshot())
  end)

  it("a bad io.window, io.held or io.send aborts the pump quietly with now + 5", function()
    local windows = {
      function() return nil end,
      function() return hostileProxy() end,
      function() return { hostileTable() } end,
      function() return { { inn = "x", t = 1, phrase = {} } } end,
      function() return win(41) end,
      function() error("boom") end,
    }
    for _, w in ipairs(windows) do
      local s = SS.new({ memo = SP.newWantMemo(), rand = lowest })
      s:setChannel("GROUP", "PARTY")
      s:requestHello("GROUP", T0, 0, 0)
      s:onWant("PARTY", 0, win(10), T0)
      local sent = 0
      local wake = s:pump(T0 + 5, {
        window = w, held = function() return {} end,
        send = function() sent = sent + 1 return true end,
      })
      assert.equal(T0 + 10, wake)
      assert.equal(0, sent)
    end
    -- A table stand-in reads (by rawget and primitive length) as an empty window.
    local s0 = SS.new({ memo = SP.newWantMemo(), rand = lowest })
    s0:setChannel("GROUP", "PARTY")
    s0:requestHello("GROUP", T0, 0, 0)
    s0:onWant("PARTY", 0, win(10), T0)
    assert.is_nil(s0:pump(T0 + 5, {
      window = function() return hostileTable() end, held = function() return {} end,
      send = function() error("nothing may be sent") end,
    }))
    -- io.held returning junk, and io.send raising.
    for _, held in ipairs({ function() return hostileTable() end, function() error("x") end,
      function() return { hostileTable() } end }) do
      local s = SS.new({ memo = SP.newWantMemo(), rand = lowest })
      s:setChannel("GROUP", "PARTY")
      s:onHello(PEER, "PARTY", 3, 1, T0)
      local wake = s:pump(T0 + 1, {
        window = function() return win(10) end, held = held, send = function() return true end,
      })
      assert.is_true(wake == nil or wake == T0 + 6)
    end
    local s = SS.new({ memo = SP.newWantMemo(), rand = lowest })
    s:setChannel("GROUP", "PARTY")
    s:requestHello("GROUP", T0, 0, 0)
    assert.equal(T0 + 5, s:pump(T0, {
      window = function() return win(10) end, held = function() return {} end,
      send = function() error("transport") end,
    }))
    assert.equal(1, s:snapshot().records) -- handed over before the error: still counted
  end)

  it("survives a rand that raises or returns junk (it falls back to the latest time)", function()
    for _, rand in ipairs({
      function() error("rand") end,
      function() return 0 / 0 end,
      function() return 99999 end,
      function() return hostileTable() end,
    }) do
      local h = harness({ group = "PARTY", rand = rand })
      assert.is_true(h.s:requestHello("GROUP", T0, 5, 15))
      assert.equal(T0 + 15, h:pump(T0))
    end
  end)
end)
