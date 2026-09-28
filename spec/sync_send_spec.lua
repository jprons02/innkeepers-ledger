-- Sync, the send path: triggers, the glue's pump and its one live timer, the combat hold,
-- the transport and the end-to-end runs (docs/specs/sync-glue.md 3.5.1, 3.5.6, 3.6, 3.7
-- and the send cases of 6.4), including the 40-player raid that checks the traffic model.
-- Peers are hostile here too. Most cases run through spec/helpers/sync_harness.lua; the
-- last block sends through the real ChatThrottleLib under the WoW stub.
local harness = require("helpers.sync_harness")
local load = require("helpers.load")
local wow = require("helpers.wow_stub")

local sign, entriesText, held = harness.sign, harness.entriesText, harness.held
local LIMITS = { messages = 30, entries = 60, window = 60 }

local HIDDEN = "hidden-value" -- flagged by the client's issecretvalue in the cases that use it

local function stats(c)
  return c.client.stats
end

local function kind(text)
  return text:sub(1, 1)
end

-- The messages `c` handed over, optionally only one kind ("H", "W", "E") and wire.
local function sentBy(w, c, k, wire)
  local out = {}
  for _, m in ipairs(w.sent) do
    if m.from == c and (k == nil or kind(m.text) == k) and (wire == nil or m.wire == wire) then
      out[#out + 1] = m
    end
  end
  return out
end

local function entryCount(text)
  if kind(text) ~= "E" then
    return 0
  end
  local _, semis = text:gsub(";", "")
  return semis + 1
end

local function wantOf(text)
  local target, since = text:match("^W1:([^:]+):(%d+)$")
  return target, tonumber(since)
end

-- Joining a guild: PLAYER_GUILD_UPDATE, then the roster update that builds the map.
local function joinGuild(...)
  for _, c in ipairs({ ... }) do
    c.client:onEvent("PLAYER_GUILD_UPDATE")
    c.client:onEvent("GUILD_ROSTER_UPDATE")
  end
end

-- GROUP_ROSTER_UPDATE on each client.
local function roster(...)
  for _, c in ipairs({ ... }) do
    c.client:onEvent("GROUP_ROSTER_UPDATE")
  end
end

-- Advances until pred() holds, one second at a time; fails after `limit` seconds.
local function advanceUntil(w, pred, limit)
  for _ = 1, limit do
    if pred() then
      return
    end
    w:advance(1)
  end
  assert(pred(), "condition not reached in " .. limit .. " s")
end

-- No client handed over more than 30 messages or 60 entries in any 60 s.
local function assertBudget(w)
  local by = {}
  for _, m in ipairs(w.sent) do
    by[m.from] = by[m.from] or {}
    local list = by[m.from]
    list[#list + 1] = m
  end
  for c, list in pairs(by) do
    local j, msgs, entries = 1, 0, 0
    for i = 1, #list do
      -- The window [list[i].at, list[i].at + 60).
      while j <= #list and list[j].at < list[i].at + LIMITS.window do
        msgs, entries = msgs + 1, entries + entryCount(list[j].text)
        j = j + 1
      end
      assert(msgs <= LIMITS.messages,
        c.name .. ": " .. msgs .. " messages in 60 s from " .. list[i].at)
      assert(entries <= LIMITS.entries,
        c.name .. ": " .. entries .. " entries in 60 s from " .. list[i].at)
      msgs, entries = msgs - 1, entries - entryCount(list[i].text)
    end
  end
end

-- Every message a client handed over is H, W or E; every E entry is one of its own
-- window's (by its canonical text); a WANT targets someone else.
local function assertOwnTexts(w)
  local own = {}
  for _, m in ipairs(w.sent) do
    local c = m.from
    local k = kind(m.text)
    if k == "H" then
      assert.truthy(m.text:find("^H1:%d+:%d+$"), m.text)
    elseif k == "W" then
      local target, since = wantOf(m.text)
      assert.truthy(target and since, m.text)
      assert.are_not.equal(c.guid, target)
    else
      assert.equal("E", k, m.text)
      if own[c] == nil then
        own[c] = {}
        for _, text in ipairs(entriesText(c, 0)) do
          for part in text:sub(4):gmatch("[^;]+") do
            own[c][part] = true
          end
        end
      end
      assert.equal("E1:", m.text:sub(1, 3))
      for part in m.text:sub(4):gmatch("[^;]+") do
        assert.is_true(own[c][part] == true, c.name .. " sent a foreign entry " .. part)
      end
    end
  end
end

-- Letters-only names for big groups (the name rule allows no digits).
local function letters(i)
  local s = ""
  repeat
    s = string.char(97 + i % 26) .. s
    i = math.floor(i / 26)
  until i == 0
  return "M" .. s
end

-- When `c`'s large replies on `wire` started, for a run where it sends only full
-- 40-entry replies (8 messages each; the budget may spread one over two minutes).
local function largeStarts(w, c, wire)
  local list = sentBy(w, c, "E", wire)
  assert(#list % 8 == 0, wire .. ": " .. #list .. " ENTRIES messages")
  local starts = {}
  for i = 1, #list, 8 do
    starts[#starts + 1] = list[i].at
  end
  return starts
end

local function assertGaps(list, gap)
  for i = 2, #list do
    assert(list[i] - list[i - 1] >= gap, "only " .. (list[i] - list[i - 1]) .. " s apart")
  end
end

-- A world with Aldric (a, `n` own entries) and Mira (b, none) in a party.
local function pair(n)
  local w = harness.new()
  local a, b = w:add("Aldric"), w:add("Mira")
  sign(a, n)
  w:setGroup({ a, b })
  return w, a, b
end

describe("Sync send: two clients", function()
  it("trade A's 12 entries in a party: HELLO, WANT, one coalesced 3-message reply", function()
    local w, a, b = pair(12)
    local t0 = w.now
    roster(a, b)
    assert.same({}, w.sent) -- handlers never send; they request a pump
    advanceUntil(w, function() return #sentBy(w, a, "H") > 0 end, 20)
    local hello = sentBy(w, a, "H")[1]
    assert.is_true(hello.at >= t0 + 5 and hello.at <= t0 + 15, "HELLO at +" .. (hello.at - t0))
    assert.equal("PARTY", hello.wire)
    assert.equal(harness.helloText(a), hello.text)

    w:advance(40)
    assert.same({}, sentBy(w, b, "H")) -- B's window is empty: no HELLO
    local wants = sentBy(w, b, "W")
    assert.equal(1, #wants)
    local target, since = wantOf(wants[1].text)
    assert.equal(a.guid, target)
    assert.equal(0, since)
    local delay = wants[1].at - (hello.at + 1) -- the HELLO arrives a step after it's sent
    assert.is_true(delay >= 1 and delay <= 5, "WANT " .. delay .. " s after the HELLO")

    local replies = sentBy(w, a, "E")
    assert.equal(3, #replies)
    for _, m in ipairs(replies) do
      assert.equal("PARTY", m.wire)
      assert.equal(wants[1].at + 1 + 5, m.at) -- after the 5 s coalescing
    end
    assert.same({ 5, 5, 2 }, { entryCount(replies[1].text), entryCount(replies[2].text),
      entryCount(replies[3].text) })
    local count, name = held(b, a.guid)
    assert.equal(12, count)
    assert.equal(a.full, name)
    assert.equal(12, b.ledger:counts().foreign)
    assert.equal(1, #b.ledger:travelers())
    assert.equal(0, a.ledger:counts().foreign)
    assert.equal(1, stats(a).sent.hello)
    assert.equal(3, stats(a).sent.entries)
    assert.equal(1, stats(b).sent.want)
    assert.equal(0, stats(a).errors + stats(b).errors)
    assertBudget(w)
    assertOwnTexts(w)
  end)

  it("WindowChanged: one HELLO per available channel, then a small reply", function()
    local w, a, b = pair(12)
    w:setGuild({ a, b })
    joinGuild(a, b)
    roster(a, b)
    -- Past SyncProtocol's 10-minute ask window, so B's next ask is its first again
    -- (a second ask inside it starts from 0: sync-ledger.md 3.3).
    w:advance(700)
    assert.equal(12, (held(b, a.guid)))
    local before = #w.sent
    local t1 = w.now

    assert.equal("added", a.ledger:addOwn(harness.entry(13)))
    a.ns.Sync.client = a.client -- the real entry point, bound to this client
    a.ns.Sync:WindowChanged()
    w:advance(40)
    local hellos = { PARTY = 0, GUILD = 0 }
    local want, reply
    for i = before + 1, #w.sent do
      local m = w.sent[i]
      if m.from == a and kind(m.text) == "H" then
        hellos[m.wire] = hellos[m.wire] + 1
        assert.is_true(m.at >= t1 + 5 and m.at <= t1 + 15)
      elseif m.from == b and kind(m.text) == "W" then
        assert.is_nil(want)
        want = m
      elseif m.from == a and kind(m.text) == "E" then
        assert.is_nil(reply)
        reply = m
      end
    end
    assert.same({ PARTY = 1, GUILD = 1 }, hellos)
    local target, since = wantOf(want.text)
    assert.equal(a.guid, target)
    assert.equal(harness.entry(12).t, since) -- the newest B held
    assert.equal(1, entryCount(reply.text))
    assert.equal(13, (held(b, a.guid)))
    assertBudget(w)
  end)

  it("WindowChanged does nothing while sync is off or before it started", function()
    local w = harness.new()
    local a = w:add("Aldric", { start = false })
    assert.has_no.errors(function() a.client:windowChanged() end)
    a.ns.Sync:WindowChanged() -- no real client
    assert.same({}, w.timers)
    assert.same({}, w.sent)
  end)
end)

describe("Sync send: a flood from one peer", function()
  it("gets at most 2 WANTs and one large reply per channel per 5 min #sim", function()
    local w = harness.new()
    local a = w:add("Aldric")
    sign(a, 40)
    local evil = harness.member("Evil", "Player-1-0000E001")
    w:setGroup({ a, evil })
    w:setGuild({ a, evil })
    roster(a)
    joinGuild(a)
    local SP = a.ns.SyncProtocol
    local want = SP.encodeWant(a.guid, 0)
    local t0, hellos, wants, maxPending = w.now, 0, 0, 0
    for s = 1, 600 do
      -- 1 000 HELLOs with fresh digests and 500 W:<A>:0 in 10 minutes, on both channels.
      for k = 1, (s % 3 == 0) and 1 or 2 do
        hellos = hellos + 1
        w:post(evil, (hellos % 2 == 0) and "GUILD" or "PARTY",
          "H1:40:" .. (hellos * 7919 % 1000003), evil.full)
        if k == 1 and s % 6 ~= 0 then
          wants = wants + 1
          w:post(evil, (wants % 2 == 0) and "GUILD" or "PARTY", want, evil.full)
        end
      end
      w:advance(1)
      maxPending = math.max(maxPending, a.client.schedule:snapshot().wants)
    end
    assert.equal(1000, hellos)
    assert.equal(500, wants)
    assert.equal(1, maxPending) -- digest churn: never more than its one pending WANT

    local toEvil = 0
    for _, m in ipairs(sentBy(w, a, "W")) do
      if wantOf(m.text) == evil.guid then
        toEvil = toEvil + 1
      end
    end
    assert.is_true(toEvil <= 2, toEvil .. " WANTs to the flooder")
    for _, wire in ipairs({ "PARTY", "GUILD" }) do
      local starts = largeStarts(w, a, wire)
      assert.is_true(#starts >= 1 and #starts <= 2, wire .. ": " .. #starts .. " replies")
      assertGaps(starts, 300)
    end
    assert.is_true((stats(a).dropped.rate or 0) > 0) -- past 40 a minute
    assert.is_true(w.now - t0 == 600)
    assertBudget(w)
    assertOwnTexts(w)
    for _, line in ipairs(a.lines) do
      assert.falsy(line:find("Evil", 1, true), line)
      assert.falsy(line:find("|", 1, true), line)
    end
  end)
end)

describe("Sync send: WANT spam", function()
  for _, case in ipairs({ { "0", 0 }, { "tMin", 1789603200 } }) do
    it("at since = " .. case[1] .. ": one large reply per 5 min; a newcomer's ask is deferred",
      function()
        local w = harness.new()
        local a = w:add("Aldric")
        local b = w:add("Mira")
        sign(a, 40)
        local evil = harness.member("Evil", "Player-1-0000E001")
        w:setGroup({ a, evil })
        roster(a)
        local want = a.ns.SyncProtocol.encodeWant(a.guid, case[2])
        local t0 = w.now
        for s = 1, 600 do
          if s % 3 == 0 then
            w:post(evil, "PARTY", want, evil.full)
          end
          if s == 60 then
            -- An honest newcomer joins just after the first large reply.
            w:setGroup({ a, evil, b })
            roster(a, b)
          end
          if s == 290 then
            assert.equal(0, (held(b, a.guid))) -- still inside the gate
          end
          w:advance(1)
        end
        local starts = largeStarts(w, a, "PARTY")
        assert.is_true(#starts >= 2 and #starts <= 3, #starts .. " replies")
        assertGaps(starts, 300)
        assert.is_true(starts[1] <= t0 + 12)
        assert.equal(40, (held(b, a.guid))) -- the deferred reply went out when the gate opened
        assert.equal(0, stats(a).errors)
        assertBudget(w)
      end)
  end
end)

describe("Sync send: combat", function()
  it("holds a reply mid-way, stays held while combat is back on, then flushes in order",
    function()
      local w, a, b = pair(40)
      a.sendMode, a.sendDelay = "defer", 1
      roster(a, b)
      advanceUntil(w, function() return #sentBy(w, a, "E") >= 3 end, 60)
      harness.combat(a, true)
      local k = #sentBy(w, a, "E")
      assert.is_true(k >= 3 and k < 8, k .. " sent before the fight")
      a.sendMode = "sync"
      local mark = #sentBy(w, a)
      local tFight = w.now

      -- During the fight: B's entries arrive and are stored; B's HELLO leaves A a WANT to
      -- decide; our own window changes (a HELLO comes due); and B asks for a small reply.
      sign(b, 3, 101)
      w:post(b, "PARTY", entriesText(b)[1])
      w:advance(1)
      assert.equal(3, (held(a, b.guid)))
      sign(b, 2, 104)
      b.client:windowChanged()
      a.client:windowChanged()
      w:advance(20)
      assert.equal(1, a.client.schedule:snapshot().wants)
      w:post(b, "PARTY", a.ns.SyncProtocol.encodeWant(a.guid, harness.entry(38).t))
      w:advance(60)
      assert.equal(mark, #sentBy(w, a)) -- nothing sent during the fight

      -- PLAYER_REGEN_ENABLED while combat is back on: still held after 3 s.
      a.client:onEvent("PLAYER_REGEN_ENABLED")
      w:advance(10)
      assert.is_true(a.client.held)
      assert.equal(mark, #sentBy(w, a))

      -- Leave room before the next held re-check, so the resume is the 3 s one.
      advanceUntil(w, function() return a.client.recheckAt > w.now + 5 end, 40)
      harness.combat(a, false)
      local tEnd = w.now
      w:advance(2)
      assert.equal(mark, #sentBy(w, a))
      w:advance(1)
      local after = {}
      for i, m in ipairs(sentBy(w, a)) do
        if i > mark then
          after[#after + 1] = m
          assert.equal(tEnd + 3, m.at)
        end
      end
      local kinds = {}
      for _, m in ipairs(after) do
        kinds[#kinds + 1] = kind(m.text) .. entryCount(m.text)
      end
      local expected = { "H0" }
      for _ = k + 1, 8 do
        expected[#expected + 1] = "E5" -- the rest of the reply, where it stopped
      end
      expected[#expected + 1] = "E2" -- the new small reply
      expected[#expected + 1] = "W0" -- then the WANT for B's new entries
      assert.same(expected, kinds)
      assert.is_true(tEnd - tFight > 60)
      w:advance(60)
      assert.equal(40, (held(b, a.guid)))
      assert.equal(5, (held(a, b.guid)))
      assert.equal(0, stats(a).errors)
    end)

  for _, mode in ipairs({ "raises", "hidden" }) do
    it("holds while the combat check " .. mode .. "; the 30 s re-check resumes", function()
      local w, a, b = pair(12)
      a.secret = function(v) return v == HIDDEN end
      a.impl.InCombatLockdown = function()
        if mode == "raises" then
          error("boom")
        end
        return HIDDEN
      end
      roster(a, b)
      w:advance(40)
      assert.same({}, sentBy(w, a))
      assert.is_true(a.client.held)
      a.impl.InCombatLockdown = function() return false end
      w:advance(31) -- no PLAYER_REGEN_ENABLED at all
      assert.equal(1, #sentBy(w, a, "H"))
      assert.is_false(a.client.held)
      assert.equal(0, stats(a).errors)
    end)
  end

  it("starts held when in combat at start, and resumes 3 s after the fight ends", function()
    local w, a, b = pair(12)
    a.inCombat = true
    local a2 = w:add("Bram", { start = false })
    a2.inCombat = true
    sign(a2, 3)
    w:setGroup({ a, b, a2 })
    assert.is_true(a2.client:start())
    assert.is_true(a2.client.held)
    w:advance(40)
    assert.same({}, sentBy(w, a2))
    harness.combat(a2, false)
    w:advance(2)
    assert.same({}, sentBy(w, a2))
    w:advance(1)
    assert.equal(1, #sentBy(w, a2, "H"))
  end)

  it("a later PLAYER_REGEN_DISABLED cancels a pending resume", function()
    local w, a, b = pair(12)
    roster(a, b)
    harness.combat(a, true)
    w:advance(30)
    harness.combat(a, false)
    w:advance(1)
    harness.combat(a, true)
    w:advance(2)
    a.inCombat = false -- combat state cleared without an event; the old resume is stale
    w:advance(1)
    assert.is_true(a.client.held)
    assert.same({}, sentBy(w, a))
    w:advance(30) -- the held re-check picks it up
    assert.is_false(a.client.held)
    assert.equal(1, #sentBy(w, a, "H"))
  end)

  it("keeps one held re-check timer, and re-arms a lost one", function()
    local w, a = pair(12)
    harness.combat(a, true)
    for _ = 1, 5 do
      harness.combat(a, true)
    end
    assert.equal(1, w:timersOf(a) - (a.client.timerLive and 1 or 0))
    a.impl.After = function() end -- timers are lost from now on
    w:advance(70) -- the re-check fires at +30 and re-arms into the void; +60 is lost
    local gen = a.client.recheckGen
    a.impl.After = function(delay, fn) w:after(delay, fn, a) end
    harness.combat(a, true) -- the lost one is over 5 s overdue: a fresh one is armed
    assert.equal(gen + 1, a.client.recheckGen)
  end)

  it("works without InCombatLockdown or a timer function", function()
    local w, a, b = pair(12)
    a.api.InCombatLockdown = nil
    roster(a, b)
    w:advance(20)
    assert.equal(1, #sentBy(w, a, "H"))
    a.api.After = nil
    assert.has_no.errors(function()
      harness.combat(a, true)
      harness.combat(a, false)
      roster(a)
    end)
    assert.equal(0, stats(a).errors)
  end)
end)

describe("Sync send: roster changes mid-sync", function()
  it("sends a pending reply on RAID after the party becomes a raid", function()
    local w, a, b = pair(12)
    roster(a, b)
    advanceUntil(w, function() return #sentBy(w, b, "W") > 0 end, 30)
    w:setGroup({ a, b }, true)
    roster(a, b)
    w:advance(20)
    assert.equal(3, #sentBy(w, a, "E", "RAID"))
    assert.equal(0, #sentBy(w, a, "E", "PARTY"))
    assert.equal(12, (held(b, a.guid)))
  end)

  it("drops the rest of a reply when we leave the group, sending nothing on PARTY", function()
    local w, a, b = pair(40)
    a.sendMode, a.sendDelay = "defer", 1
    roster(a, b)
    advanceUntil(w, function() return #sentBy(w, a, "E") > 0 end, 60)
    local n = #sentBy(w, a)
    w:setGroup({})
    roster(a, b)
    w:advance(60)
    assert.equal(n, #sentBy(w, a))
    assert.equal(0, a.client.schedule:snapshot().progress)
  end)

  it("HELLOs for newcomers only: not when members leave; once for a leave and rejoin",
    function()
      local w = harness.new()
      local a, b, c, d = w:add("Aldric"), w:add("Mira"), w:add("Bram"), w:add("Vesna")
      sign(a, 12)
      w:setGroup({ a, b, c })
      roster(a, b, c)
      w:advance(100)
      assert.equal(1, #sentBy(w, a, "H"))

      w:setGroup({ a, b }) -- Bram leaves
      roster(a)
      w:advance(100)
      assert.equal(1, #sentBy(w, a, "H"))

      w:setGroup({ a, b, d }) -- Vesna joins; repeated updates keep one HELLO
      roster(a)
      roster(a)
      w:advance(1)
      roster(a)
      w:advance(100)
      assert.equal(2, #sentBy(w, a, "H"))

      w:setGroup({ a, d }) -- Mira leaves and rejoins
      roster(a)
      w:setGroup({ a, d, b })
      roster(a)
      w:advance(100)
      assert.equal(3, #sentBy(w, a, "H"))
    end)

  it("scans at most 40 units, none for a hidden or odd count, with the home category",
    function()
      local w, a, b = pair(12)
      w:setGroup({ a, b }, true)
      local tokens = {}
      a.impl.UnitGUID = function(unit)
        tokens[#tokens + 1] = unit
        return nil
      end
      a.secret = function(v) return v == HIDDEN end
      for _, n in ipairs({ 500, 40.5, math.huge }) do
        a.impl.GetNumGroupMembers = function() return n end
        tokens = {}
        roster(a)
        assert.equal(40, #tokens)
        assert.equal("raid40", tokens[40])
      end
      for _, n in ipairs({ HIDDEN, 0 / 0, "12", -3 }) do
        a.impl.GetNumGroupMembers = function() return n end
        tokens = {}
        roster(a)
        assert.same({}, tokens)
      end
      a.impl.GetNumGroupMembers = function() error("boom") end
      roster(a)
      assert.equal(0, stats(a).errors)
      assert.same({ n = 1, harness.HOME }, a.groupArgs.IsInGroup)
      assert.same({ n = 1, harness.HOME }, a.groupArgs.IsInRaid)
      a.api.LE_PARTY_CATEGORY_HOME = nil
      roster(a)
      assert.same({ n = 0 }, a.groupArgs.IsInGroup)
      a.api.LE_PARTY_CATEGORY_HOME = HIDDEN
      a.groupArgs = {}
      roster(a)
      assert.same({ n = 0 }, a.groupArgs.IsInRaid)
    end)

  it("scans party1..party(N-1) in a party, skipping hidden, invalid and own GUIDs", function()
    local w, a, b = pair(12)
    local tokens = {}
    a.secret = function(v) return v == HIDDEN end
    local answers = { party1 = HIDDEN, party2 = "Creature-0-1", party3 = a.guid,
      party4 = b.guid }
    a.impl.GetNumGroupMembers = function() return 5 end
    a.impl.UnitGUID = function(unit)
      tokens[#tokens + 1] = unit
      return answers[unit]
    end
    roster(a)
    assert.same({ "party1", "party2", "party3", "party4" }, tokens)
    assert.same({ [b.guid] = true }, a.client.members)
    w:advance(20)
    assert.equal(1, #sentBy(w, a, "H"))
  end)

  it("treats a hidden IsInGroup as no group, and a hidden IsInRaid as a party", function()
    local w, a, b = pair(12)
    a.secret = function(v) return v == HIDDEN end
    a.impl.IsInRaid = function() return HIDDEN end
    roster(a, b)
    w:advance(20)
    assert.equal(1, #sentBy(w, a, "H", "PARTY"))
    a.impl.IsInGroup = function() return HIDDEN end
    roster(a)
    assert.same({}, a.client.members)
  end)

  it("keeps newcomers new when the clock is bad at the roster update", function()
    local w, a = pair(12)
    a.impl.GetServerTime = function() return nil end
    roster(a)
    assert.same({}, a.client.members)
    a.impl.GetServerTime = function() return w.now end
    roster(a)
    w:advance(20)
    assert.equal(1, #sentBy(w, a, "H"))
  end)
end)

describe("Sync send: group before guild", function()
  it("answers a peer in both our party and our guild on PARTY, never GUILD", function()
    local w, a, b = pair(12)
    w:setGuild({ a, b })
    joinGuild(a, b)
    -- A's HELLO reaches B on GUILD first, then on PARTY a second later.
    w:post(a, "GUILD", harness.helloText(a))
    w:advance(1)
    roster(a, b)
    w:post(a, "PARTY", harness.helloText(a))
    w:advance(200)
    local wants = sentBy(w, b, "W")
    assert.is_true(#wants >= 1)
    for _, m in ipairs(wants) do
      assert.equal("PARTY", m.wire)
    end
    assert.is_true(#sentBy(w, a, "E", "PARTY") > 0)
    assert.equal(0, #sentBy(w, a, "E", "GUILD"))
    assert.equal(12, (held(b, a.guid)))
  end)
end)

describe("Sync send: deferred send callbacks", function()
  it("finish an 8-message reply within about 10 s when every callback is 1 s late", function()
    local w, a, b = pair(40)
    a.sendMode, b.sendMode = "defer", "defer"
    roster(a, b)
    w:advance(60)
    local replies = sentBy(w, a, "E")
    assert.equal(8, #replies)
    assert.is_true(replies[8].at - replies[1].at <= 10,
      "took " .. (replies[8].at - replies[1].at) .. " s")
    assert.equal(40, (held(b, a.guid)))
    assert.equal(0, a.client.schedule:snapshot().inFlight)
  end)

  it("counts a failed send and a didSend false, and never retries in a loop", function()
    local w, a, b = pair(12)
    a.sendMode = "fail" -- every callback says didSend false
    roster(a, b)
    w:advance(60)
    -- The harness still delivered them, so B asked and A replied; each was counted once.
    assert.equal(1, #sentBy(w, a, "H"))
    assert.equal(3, #sentBy(w, a, "E"))
    assert.equal(4, stats(a).sendFailed)
    assert.equal(0, a.client.schedule:snapshot().sendFailed) -- all were handed over
    assert.equal(0, a.client.schedule:snapshot().inFlight)
    local failed = 0
    for _, line in ipairs(a.lines) do
      failed = failed + (line == "sync: send failed" and 1 or 0)
    end
    assert.equal(4, failed)

    local w2, c, d = pair(12)
    c.impl.send = function() error("too long") end
    roster(c, d)
    w2:advance(40)
    assert.equal(1, stats(c).sendFailed)
    assert.equal(1, c.client.schedule:snapshot().sendFailed)
    assert.equal(0, stats(c).errors)
    c.impl.send = function() return false end
    c.client:windowChanged()
    w2:advance(100)
    assert.equal(2, stats(c).sendFailed)
    assert.same({}, sentBy(w2, d))
  end)

  it("catches an error inside the send callback", function()
    local w, a, b = pair(12)
    a.client.schedule.sendDone = function() error("boom") end
    roster(a, b)
    assert.has_no.errors(function() w:advance(60) end)
    local n = #sentBy(w, a)
    assert.is_true(n >= 1)
    assert.equal(n, stats(a).errors) -- one per callback
    local found = false
    for _, line in ipairs(a.lines) do
      found = found or line == "sync: error in send"
    end
    assert.is_true(found)
  end)
end)

describe("Sync send: one live timer", function()
  it("keeps at most 6 timers and pumps at most once a second, over an hour in a guild #sim",
    function()
      local w = harness.new()
      local a = w:add("Aldric")
      sign(a, 12)
      local peers = {}
      for i = 1, 30 do
        peers[i] = harness.member(letters(i), ("Player-1-%08X"):format(0x1000 + i))
      end
      local evil = harness.member("Evil", "Player-1-0000E001")
      local members = { a, evil }
      for _, p in ipairs(peers) do
        members[#members + 1] = p
      end
      w:setGuild(members)
      joinGuild(a)
      local schedule = a.client.schedule
      local realPump = schedule.pump
      local pumpsAt = {}
      schedule.pump = function(...)
        pumpsAt[w.now] = (pumpsAt[w.now] or 0) + 1
        return realPump(...)
      end
      local maxTimers = 0
      for s = 1, 3600 do
        if s % 2 == 0 then
          local p = peers[1 + (s / 2) % #peers]
          w:post(p, "GUILD", "H1:3:" .. (s * 31 % 100003), p.full)
        end
        w:post(evil, "GUILD", "H1:40:" .. s, evil.full)
        w:advance(1)
        maxTimers = math.max(maxTimers, w:timersOf(a))
      end
      assert.is_true(maxTimers <= 6, maxTimers .. " timers")
      for t, n in pairs(pumpsAt) do
        assert(n <= 1, n .. " pumps at " .. t)
      end
      assert.is_true(#sentBy(w, a, "H") >= 2) -- the periodic guild HELLO went out
      assert.equal(0, stats(a).errors)
      assertBudget(w)
    end)

  it("treats a pump timer overdue by more than 5 s as lost", function()
    local w, a, b = pair(12)
    a.impl.After = function() end -- this timer never fires
    roster(a, b)
    a.impl.After = function(delay, fn) w:after(delay, fn, a) end
    w:advance(10)
    roster(a) -- nothing new: no request, the lost timer still counts
    w:advance(10)
    assert.same({}, sentBy(w, a))
    a.client:poke() -- the lost timer is over 5 s overdue now: a fresh one
    w:advance(20)
    assert.equal(1, #sentBy(w, a, "H"))
  end)
end)

describe("Sync send: bad clock in the glue pump", function()
  for _, bad in ipairs({ "nil", "NaN", "string", "hidden" }) do
    it("skips and retries when GetServerTime returns " .. bad, function()
      local w, a, b = pair(12)
      roster(a, b)
      w:advance(1)
      local value = ({ NaN = 0 / 0, string = "1794000000", hidden = HIDDEN })[bad]
      a.secret = function(v) return v == HIDDEN end
      a.impl.GetServerTime = function() return value end
      assert.has_no.errors(function() w:advance(60) end)
      assert.same({}, sentBy(w, a))
      assert.is_true(w:timersOf(a) <= 2)
      a.client:poke()
      a.client:pump()
      assert.is_true(w:timersOf(a) <= 2)
      a.impl.GetServerTime = function() return w.now end
      w:advance(10)
      assert.equal(1, #sentBy(w, a, "H"))
      assert.equal(0, stats(a).errors)
    end)
  end
end)

describe("Sync send: guild", function()
  it("first HELLO 60-120 s after login, then every 1 200-1 500 s; none from an empty window",
    function()
      local w = harness.new()
      local a = w:add("Aldric", { start = false })
      local b = w:add("Mira", { start = false })
      sign(a, 12)
      w:setGuild({ a, b })
      local t0 = w.now
      assert.is_true(a.client:start())
      assert.is_true(b.client:start())
      w:advance(5000)
      local hellos = sentBy(w, a, "H", "GUILD")
      assert.is_true(#hellos >= 3)
      assert.is_true(hellos[1].at >= t0 + 60 and hellos[1].at <= t0 + 120)
      for i = 2, #hellos do
        local gap = hellos[i].at - hellos[i - 1].at
        assert.is_true(gap >= 1200 and gap <= 1500, "gap " .. gap)
      end
      assert.same({}, sentBy(w, b, "H"))
      assert.equal(12, (held(b, a.guid)))
      assertBudget(w)
    end)

  it("drops the GUILD channel on leaving and asks for a first HELLO again on rejoining",
    function()
      local w = harness.new()
      local a, b = w:add("Aldric", { start = false }), w:add("Mira")
      sign(a, 12)
      w:setGuild({ a, b })
      assert.is_true(a.client:start())
      w:advance(10)
      w:setGuild({ b })
      a.client:onEvent("PLAYER_GUILD_UPDATE")
      w:advance(200)
      assert.same({}, sentBy(w, a))
      w:setGuild({ a, b })
      local t1 = w.now
      a.client:onEvent("PLAYER_GUILD_UPDATE")
      a.client:onEvent("PLAYER_GUILD_UPDATE") -- already on: no second request
      w:advance(130)
      local hellos = sentBy(w, a, "H", "GUILD")
      assert.equal(1, #hellos)
      assert.is_true(hellos[1].at >= t1 + 60 and hellos[1].at <= t1 + 120)
    end)
end)

describe("Sync send: a 40-player raid from scratch", function()
  for _, mode in ipairs({ "sync", "defer" }) do
    it("syncs everyone within 10 minutes, under every limit (callbacks " .. mode .. ") #sim",
      function()
        local w = harness.new({ seed = 4047 })
        local cs = {}
        for i = 1, 40 do
          cs[i] = w:add(letters(i))
          cs[i].sendMode = mode
          sign(cs[i], 40)
        end
        w:setGroup(cs, true)
        roster(unpack(cs))
        w:advance(600)
        for _, c in ipairs(cs) do
          for _, other in ipairs(cs) do
            if other ~= c then
              assert.equal(40, (held(c, other.guid)), c.name .. " misses " .. other.name)
            end
          end
          assert.is_nil(stats(c).dropped.rate, c.name .. " dropped an honest message as rate")
          assert.equal(0, stats(c).errors)
          assert.equal(0, stats(c).sendFailed)
        end
        assertBudget(w)
        assertOwnTexts(w)
      end)
  end
end)

-- ---------------------------------------------------------------------------
-- The real client under the WoW stub: our text reaches the client's send function
-- through the real ChatThrottleLib.

describe("ns.Sync send through the real ChatThrottleLib", function()
  local MIRA = "Player-1-00000002"

  after_each(wow.uninstall)

  local function login(overrides)
    wow.install(overrides)
    local ns = load.addon({})
    wow.fire("ADDON_LOADED", load.ADDON_NAME)
    wow.fire("PLAYER_LOGIN")
    return ns
  end

  local function grouped()
    return {
      IsInGroup = function() return true end,
      GetNumGroupMembers = function() return 2 end,
      UnitGUID = function(unit)
        if unit == "player" then return "Player-1-00000001" end
        if unit == "party1" then return MIRA end
      end,
    }
  end

  it("hands a HELLO to C_ChatInfo.SendAddonMessage: prefix InnLedger, PARTY, no target",
    function()
      local ns = login(grouped())
      assert.equal("added", ns.ledger:addOwn({ inn = 1, t = wow.now - 1000, phrase = { 1 } }))
      ns.Sync:WindowChanged()
      assert.same({}, wow.sent) -- nothing sent from an event or a call
      wow.advance(20) -- also moves GetTime past the library's start-up throttle
      assert.same({}, wow.errors)
      assert.equal(1, #wow.sent)
      local m = wow.sent[1]
      assert.equal("InnLedger", m.prefix)
      assert.equal("PARTY", m.channel)
      assert.is_nil(m.target)
      assert.truthy(m.text:find("^H1:1:%d+$"), m.text)
      assert.equal(1, ns.Sync.stats.sent.hello)
      assert.equal(0, ns.Sync.stats.sendFailed)
      assert.is_true(_G.ChatThrottleLib.Prio.BULK.nTotalSent > 0)
      assert.equal(0, _G.ChatThrottleLib.Prio.NORMAL.nTotalSent)
    end)

  it("holds on PLAYER_REGEN_DISABLED and resumes on PLAYER_REGEN_ENABLED", function()
    local inCombat = false
    local overrides = grouped()
    overrides.InCombatLockdown = function() return inCombat end
    local ns = login(overrides)
    ns.ledger:addOwn({ inn = 1, t = wow.now - 1000, phrase = { 1 } })
    inCombat = true
    wow.fire("PLAYER_REGEN_DISABLED")
    wow.advance(25)
    assert.same({}, wow.sent)
    inCombat = false
    wow.fire("PLAYER_REGEN_ENABLED")
    wow.advance(3)
    assert.equal(1, #wow.sent)
    assert.same({}, wow.errors)
  end)
end)
