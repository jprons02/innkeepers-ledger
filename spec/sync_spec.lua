-- Sync, the receive path: prefix, hidden values, channels, sender resolution, the guild
-- map, ctx and dispatch (docs/specs/sync-glue.md 3.3, 3.4, 3.8 and the receive cases of
-- 6.4). Peer data is hostile here. Most cases run through spec/helpers/sync_harness.lua;
-- the last block runs the real client under the WoW stub.
local harness = require("helpers.sync_harness")
local load = require("helpers.load")
local wow = require("helpers.wow_stub")

local NOW = harness.NOW
local sign, entriesText, helloText, inject, held =
  harness.sign, harness.entriesText, harness.helloText, harness.inject, harness.held

-- The two hidden-value stand-ins (sync-ledger.md 5.2): touching them in any way raises.
local HOSTILE_EVENTS = {
  "__index", "__newindex", "__len", "__eq", "__lt", "__le", "__concat", "__tostring",
  "__call",
}

local function raise()
  error("hidden value touched")
end

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

-- Counts SyncProtocol.receive calls (installed before Sync.lua loads).
local function spyReceive(counter)
  return function(ns)
    local real = ns.SyncProtocol.receive
    ns.SyncProtocol.receive = function(...)
      counter.n = counter.n + 1
      return real(...)
    end
  end
end

-- A party of me (Aldric) and Mira; Mira has 3 own entries. `recv` counts me's receives.
local function party(raid)
  local w = harness.new()
  local recv = { n = 0 }
  local me = w:add("Aldric", { setup = spyReceive(recv) })
  local mira = w:add("Mira")
  w:setGroup({ me, mira }, raid)
  sign(mira, 3)
  return w, me, mira, recv
end

-- A guild of me (Aldric) and Mira, the map built at start; Mira has 3 own entries.
local function guild()
  local w = harness.new()
  local recv = { n = 0 }
  local me = w:add("Aldric", { setup = spyReceive(recv), start = false })
  local mira = w:add("Mira", { start = false })
  w:setGuild({ me, mira })
  assert.is_true(me.client:start())
  assert.is_true(mira.client:start())
  sign(mira, 3)
  return w, me, mira, recv
end

local function stats(c)
  return c.client.stats
end

-- Nothing counted at all.
local function assertQuiet(c)
  local s = stats(c)
  assert.same({}, s.received)
  assert.same({}, s.dropped)
  for _, name in ipairs({ "added", "dup", "rejected", "evicted", "sendFailed", "errors" }) do
    assert.equal(0, s[name], name)
  end
end

local function stored(c)
  return c.ledger:counts().foreign
end

local function hasLine(c, text)
  for _, line in ipairs(c.lines) do
    if line:find(text, 1, true) then
      return true
    end
  end
  return false
end

-- Letters-only names for big rosters (the name rule allows no digits).
local function letters(i)
  local s = ""
  repeat
    s = string.char(97 + i % 26) .. s
    i = math.floor(i / 26)
  until i == 0
  return "M" .. s
end

describe("Sync receive, end to end", function()
  it("stores a valid ENTRIES from a resolved party peer under its GUID and full name", function()
    local w, me, mira, recv = party()
    for _, text in ipairs(entriesText(mira)) do
      w:post(mira, "PARTY", text)
    end
    w:deliver()
    local n, name = held(me, mira.guid)
    assert.equal(3, n)
    assert.equal("Mira-Stubrealm", name)
    assert.equal(3, stored(me))
    assert.equal(1, recv.n)
    assert.equal(1, stats(me).received.entries)
    assert.equal(3, stats(me).added)
    assert.equal(0, stats(me).errors)
    assert.is_true(hasLine(me, "sync: got entries PARTY " .. mira.guid .. " added 3"))
    -- Mira heard her own echo.
    assert.equal(1, stats(mira).dropped.self)
    assert.equal(0, stored(mira))
  end)

  it("resolves RAID senders the same way", function()
    local w, me, mira = party(true)
    w:post(mira, "RAID", entriesText(mira)[1])
    w:advance(1)
    assert.equal(3, (held(me, mira.guid)))
  end)

  it("resolves GUILD senders from the roster", function()
    local w, me, mira = guild()
    w:post(mira, "GUILD", entriesText(mira)[1])
    w:deliver()
    local n, name = held(me, mira.guid)
    assert.equal(3, n)
    assert.equal("Mira-Stubrealm", name)
  end)

  it("hands HELLO to schedule:onHello and WANT to schedule:onWant with the wire channel", function()
    local w, me, mira = party(true)
    sign(me, 7)
    local hellos, wants = {}, {}
    local schedule = me.client.schedule
    schedule.onHello = function(self, ...)
      assert.equal(schedule, self)
      hellos[#hellos + 1] = { ... }
    end
    schedule.onWant = function(self, ...)
      assert.equal(schedule, self)
      wants[#wants + 1] = { ... }
    end
    local SP = me.ns.SyncProtocol
    local window = mira.ledger:shareWindow(40)
    w:post(mira, "RAID", helloText(mira))
    w:post(mira, "RAID", SP.encodeWant(me.guid, 0))
    w:post(mira, "RAID", SP.encodeWant("Player-1-0000BEEF", 0))
    w:deliver()
    assert.same({ { mira.guid, "RAID", 3, SP.digest(window), NOW } }, hellos)
    assert.equal(1, #wants)
    assert.equal("RAID", wants[1][1])
    assert.equal(0, wants[1][2])
    assert.same(me.ledger:shareWindow(40), wants[1][3])
    assert.equal(7, #wants[1][3])
    assert.equal(NOW, wants[1][4])
    assert.same({ hello = 1, want = 1, want_seen = 1 }, stats(me).received)
    -- The WANT for someone else is only remembered, never stored.
    assert.is_table(me.client.memo.seen["RAID:Player-1-0000BEEF"])
    assert.equal(0, stored(me))
  end)

  it("hands a guild HELLO to the schedule with GUILD as the wire", function()
    local w, me, mira = guild()
    local hellos = {}
    me.client.schedule.onHello = function(_, guid, wire) hellos[#hellos + 1] = { guid, wire } end
    w:post(mira, "GUILD", helloText(mira))
    w:deliver()
    assert.same({ { mira.guid, "GUILD" } }, hellos)
  end)

  it("calls onEntries only when something was added", function()
    local w = harness.new()
    local calls = 0
    local me = w:add("Aldric", { deps = { onEntries = function() calls = calls + 1 end } })
    local mira = w:add("Mira")
    w:setGroup({ me, mira })
    sign(mira, 2)
    local text = entriesText(mira)[1]
    inject(me, "InnLedger", text, "PARTY", mira.full)
    assert.equal(1, calls)
    inject(me, "InnLedger", text, "PARTY", mira.full) -- all duplicates
    assert.equal(1, calls)
    assert.equal(2, stats(me).dup)
  end)

  it("counts an entry the ledger evicts at once as evicted", function()
    local _, me, mira = party()
    sign(mira, 38, 4) -- 41 entries; the share window is the newest 40
    for _, text in ipairs(entriesText(mira)) do
      inject(me, "InnLedger", text, "PARTY", mira.full)
    end
    assert.equal(40, stats(me).added)
    assert.equal(0, stats(me).evicted)
    -- The oldest one is past the per-signer cap of 40, so it's dropped on arrival.
    local SP = me.ns.SyncProtocol
    inject(me, "InnLedger", "E1:" .. SP.canon(mira.ledger:own()[1]), "PARTY", mira.full)
    assert.equal(1, stats(me).evicted)
    assert.equal(40, stats(me).added)
    assert.equal(40, (held(me, mira.guid)))
    assert.is_true(hasLine(me, "evicted 1"))
  end)

  it("counts entries it can't use: unknown IDs are rejected", function()
    local w, me, mira = party()
    inject(me, "InnLedger", "E1:5555," .. (NOW - 50) .. ",1,0", "PARTY", mira.full)
    assert.equal(1, stats(me).rejected)
    assert.equal(0, stored(me))
    assert.is_nil(w.sent[1])
  end)
end)

describe("Sync receive: unresolved sender", function()
  it("drops a PARTY sender who isn't in our group, without calling receive", function()
    local w, me, mira, recv = party()
    w:setGroup({})
    inject(me, "InnLedger", entriesText(mira)[1], "PARTY", mira.full)
    assert.equal(1, stats(me).dropped.unresolved)
    assert.equal(0, recv.n)
    assert.equal(0, stored(me))
    assert.is_true(hasLine(me, "sync: drop unresolved PARTY"))
  end)

  it("drops a PARTY sender our group doesn't hold, while we're grouped with others", function()
    local w, me, mira, recv = party()
    w:setGroup({ me, harness.member("Bram", "Player-1-0000B4A3") })
    inject(me, "InnLedger", entriesText(mira)[1], "RAID", mira.full)
    assert.equal(1, stats(me).dropped.unresolved)
    assert.equal(0, recv.n)
    assert.equal(0, stored(me))
  end)

  it("drops a GUILD sender not in the roster, requesting the roster once per 60 s", function()
    local w, me, _, recv = guild()
    local stranger = w:add("Vesna", { start = false })
    sign(stranger, 1)
    w:advance(60) -- past the request made at start
    local before = me.calls.GuildRoster
    inject(me, "InnLedger", entriesText(stranger)[1], "GUILD", stranger.full)
    assert.equal(1, stats(me).dropped.unresolved)
    assert.equal(0, recv.n)
    assert.equal(0, stored(me))
    assert.equal(before + 1, me.calls.GuildRoster)
    w:advance(59)
    inject(me, "InnLedger", entriesText(stranger)[1], "GUILD", stranger.full)
    assert.equal(2, stats(me).dropped.unresolved)
    assert.equal(before + 1, me.calls.GuildRoster)
    w:advance(1)
    inject(me, "InnLedger", entriesText(stranger)[1], "GUILD", stranger.full)
    assert.equal(before + 2, me.calls.GuildRoster)
  end)

  it("never resolves a GUILD sender through UnitGUID, even a group member", function()
    local w = harness.new()
    local recv = { n = 0 }
    local me = w:add("Aldric", { setup = spyReceive(recv), start = false })
    local bram = w:add("Bram", { start = false })
    w:setGroup({ me, bram })
    w:setGuild({ me }) -- Bram is in our group but not on the roster
    assert.is_true(me.client:start())
    sign(bram, 1)
    local asked = {}
    local unitGUID = me.impl.UnitGUID
    me.impl.UnitGUID = function(unit)
      asked[#asked + 1] = unit
      return unitGUID(unit)
    end
    local text = entriesText(bram)[1]
    inject(me, "InnLedger", text, "GUILD", bram.full)
    inject(me, "InnLedger", text, "GUILD", "Bram")
    assert.equal(2, stats(me).dropped.unresolved)
    assert.same({}, asked)
    assert.equal(0, recv.n)
    assert.equal(0, stored(me))
    -- The same sender on PARTY resolves through the group map built at start.
    inject(me, "InnLedger", text, "PARTY", bram.full)
    assert.same({}, asked)
    assert.equal(1, stored(me))
  end)

  it("requests the roster again at once when the clock went back", function()
    local w, me = guild()
    local before = me.calls.GuildRoster
    w.now = NOW - 3600
    inject(me, "InnLedger", "H1:0:0", "GUILD", "Vesna-Stubrealm")
    assert.equal(before + 1, me.calls.GuildRoster)
  end)

  it("requests nothing when the roster call is missing, and still drops", function()
    local w, me = guild()
    w:advance(60)
    me.api.GuildRoster = nil
    inject(me, "InnLedger", "H1:0:0", "GUILD", "Vesna-Stubrealm")
    assert.equal(1, stats(me).dropped.unresolved)
    assert.equal(0, stats(me).errors)
  end)
end)

describe("Sync receive: sender that left the group", function()
  it("drops entries that arrive after the peer left; its pending WANT stays bounded", function()
    local w, me, mira, recv = party()
    me.client:onEvent("GROUP_ROSTER_UPDATE")
    harness.combat(me, true) -- held, so the pending WANT stays pending
    for i = 1, 50 do
      sign(mira, 1, 3 + i)
      w:post(mira, "PARTY", helloText(mira))
      w:advance(1)
    end
    assert.equal(1, me.client.schedule:snapshot().wants)
    local before = recv.n
    w:setGroup({ me })
    me.client:onEvent("GROUP_ROSTER_UPDATE") -- the group map follows the roster
    inject(me, "InnLedger", entriesText(mira)[1], "PARTY", mira.full)
    inject(me, "InnLedger", helloText(mira), "PARTY", mira.full)
    assert.equal(before, recv.n)
    assert.equal(2, stats(me).dropped.unresolved)
    assert.equal(0, stored(me))
    assert.equal(1, me.client.schedule:snapshot().wants)
    -- The group is gone: the roster update drops it with the GROUP channel. Nothing was sent.
    w:setGroup({})
    me.client:onEvent("GROUP_ROSTER_UPDATE")
    assert.equal(0, me.client.schedule:snapshot().wants)
    for _, m in ipairs(w.sent) do
      assert.are_not.equal(me, m.from)
    end
  end)
end)

describe("Sync receive: hidden values", function()
  local ARGS = { "prefix", "text", "channel", "sender" }

  for i, arg in ipairs(ARGS) do
    it("drops a message whose " .. arg .. " is hidden, before anything else touches it", function()
      local _, me, mira, recv = party()
      local args = { "InnLedger", entriesText(mira)[1], "PARTY", mira.full }
      local flagged = args[i]
      me.secret = function(v) return v == flagged end
      local clockReads = me.calls.GetServerTime
      inject(me, unpack(args, 1, 4))
      assert.equal(1, stats(me).dropped.hidden)
      assert.equal(0, recv.n)
      assert.is_nil(me.calls.UnitGUID)
      assert.equal(clockReads, me.calls.GetServerTime)
      assert.equal(0, stored(me))
    end)
  end

  it("checks prefix, text, channel and sender in that order, first of all", function()
    local _, me, mira = party()
    local seen, lookups = {}, {}
    local clockReads = me.calls.GetServerTime
    me.secret = function(v)
      seen[#seen + 1] = v
      lookups[#lookups + 1] = (me.calls.UnitGUID or 0) + me.calls.GetServerTime - clockReads
      return false
    end
    local text = entriesText(mira)[1]
    inject(me, "InnLedger", text, "PARTY", mira.full)
    assert.same({ "InnLedger", text, "PARTY", mira.full }, { unpack(seen, 1, 4) })
    assert.same({ 0, 0, 0, 0 }, { unpack(lookups, 1, 4) })
    assert.equal(3, stored(me))
  end)

  it("counts a hidden value from another AddOn's prefix as hidden too", function()
    local _, me = party()
    me.secret = function(v) return v == "OtherAddon" end
    inject(me, "OtherAddon", "hello", "PARTY", "Mira-Stubrealm")
    assert.equal(1, stats(me).dropped.hidden)
  end)

  it("treats an issecretvalue that raises as hidden (fails closed)", function()
    local _, me, mira, recv = party()
    me.impl.issecretvalue = function() error("boom") end
    inject(me, "InnLedger", entriesText(mira)[1], "PARTY", mira.full)
    assert.equal(1, stats(me).dropped.hidden)
    assert.equal(0, recv.n)
    assert.equal(0, stats(me).errors)
  end)

  it("works without issecretvalue", function()
    local _, me, mira = party()
    me.api.issecretvalue = nil
    inject(me, "InnLedger", entriesText(mira)[1], "PARTY", mira.full)
    assert.equal(3, stored(me))
  end)

  it("drops the two stand-ins in any argument quietly when issecretvalue says false", function()
    for _, make in ipairs({ hostileTable, hostileProxy }) do
      for i = 1, 4 do
        local _, me, mira = party()
        local args = { "InnLedger", entriesText(mira)[1], "PARTY", mira.full }
        args[i] = make()
        assert.has_no.errors(function() inject(me, unpack(args, 1, 4)) end)
        assert.equal(0, stats(me).errors)
        assert.equal(0, stored(me))
        -- And as the event name.
        assert.has_no.errors(function() me.client:onEvent(make(), unpack(args, 1, 4)) end)
      end
    end
  end)

  it("stores nothing while the clock is hidden, and doesn't throw", function()
    local w, me, mira, recv = party()
    me.client:onEvent("GROUP_ROSTER_UPDATE") -- a hidden clock allows no rescan on a miss
    me.secret = function(v) return v == w.now end
    assert.has_no.errors(function()
      inject(me, "InnLedger", entriesText(mira)[1], "PARTY", mira.full)
    end)
    assert.equal(1, recv.n)
    assert.equal(1, stats(me).dropped.ctx) -- receive saw no time
    assert.equal(0, stored(me))
    assert.equal(0, stats(me).errors)
    me.secret = nil
    inject(me, "InnLedger", entriesText(mira)[1], "PARTY", mira.full)
    assert.equal(3, stored(me))
  end)

  it("drops a sender whose unit's UnitGUID is a stand-in or a hidden value", function()
    for _, make in ipairs({ hostileTable, hostileProxy }) do
      local _, me, mira, recv = party()
      local bad = make()
      me.impl.UnitGUID = function() return bad end
      inject(me, "InnLedger", entriesText(mira)[1], "PARTY", mira.full)
      assert.equal(1, stats(me).dropped.unresolved)
      assert.equal(0, recv.n)
      assert.equal(0, stats(me).errors)
    end
    local _, me, mira, recv = party()
    me.secret = function(v) return v == mira.guid end
    inject(me, "InnLedger", entriesText(mira)[1], "PARTY", mira.full)
    assert.equal(1, stats(me).dropped.unresolved)
    assert.equal(0, recv.n)
  end)

  it("drops a sender whose unit's UnitGUID raises or isn't a player GUID", function()
    for _, bad in ipairs({ "Creature-0-1-2-3-4-5", "", 42, "Player-1-0000BEEF " }) do
      local _, me, mira, recv = party()
      me.impl.UnitGUID = function() return bad end
      inject(me, "InnLedger", entriesText(mira)[1], "PARTY", mira.full)
      assert.equal(1, stats(me).dropped.unresolved)
      assert.equal(0, recv.n)
    end
    local _, me, mira = party()
    me.impl.UnitGUID = function() error("boom") end
    inject(me, "InnLedger", entriesText(mira)[1], "PARTY", mira.full)
    assert.equal(1, stats(me).dropped.unresolved)
    assert.equal(0, stats(me).errors)
  end)

  it("uses a bare sender as is when the realm is hidden, missing or odd", function()
    local cases = {
      hidden = function(me) me.secret = function(v) return v == "Stubrealm" end end,
      ["a stand-in"] = function(me)
        local bad = hostileProxy()
        me.impl.GetNormalizedRealmName = function() return bad end
      end,
      missing = function(me) me.api.GetNormalizedRealmName = nil end,
      raising = function(me) me.impl.GetNormalizedRealmName = function() error("boom") end end,
      empty = function(me) me.impl.GetNormalizedRealmName = function() return "" end end,
      ["49 bytes"] = function(me)
        me.impl.GetNormalizedRealmName = function() return ("R"):rep(49) end
      end,
    }
    for name, setup in pairs(cases) do
      local _, me, mira = party()
      setup(me)
      inject(me, "InnLedger", entriesText(mira)[1], "PARTY", "Mira")
      local n, stored_name = held(me, mira.guid)
      assert.equal(3, n, name)
      assert.equal("Mira", stored_name, name)
      assert.equal(0, stats(me).errors, name)
    end
  end)
end)

describe("Sync receive: channels", function()
  it("drops WHISPER, INSTANCE_CHAT, CHANNEL, SAY, nil and look-alikes", function()
    for _, channel in ipairs({ "WHISPER", "INSTANCE_CHAT", "CHANNEL", "SAY", "party", "",
      "GUILD ", 1 }) do
      local w, me, mira, recv = party()
      inject(me, "InnLedger", entriesText(mira)[1], channel, mira.full)
      assert.equal(1, stats(me).dropped.channel, tostring(channel))
      assert.equal(0, recv.n)
      assert.equal(0, stored(me))
      assert.is_nil(me.calls.UnitGUID)
      assert.is_nil(w.sent[1])
    end
    local _, me, mira, recv = party()
    inject(me, "InnLedger", entriesText(mira)[1], nil, mira.full)
    assert.equal(1, stats(me).dropped.channel)
    assert.equal(0, recv.n)
  end)
end)

describe("Sync receive: other prefixes", function()
  it("ignores them: no stats, no debug line, receive not called", function()
    local _, me, mira, recv = party()
    local text = entriesText(mira)[1]
    for _, prefix in ipairs({ "OtherAddon", "innledger", "InnLedger2", "InnLedger ", "", 42 }) do
      inject(me, prefix, text, "PARTY", mira.full)
    end
    inject(me, nil, text, "PARTY", mira.full)
    assertQuiet(me)
    assert.equal(0, recv.n)
    assert.same({ "sync: on", "sync: names realm" }, me.lines)
  end)
end)

describe("Sync receive: our own echo", function()
  it("counts it as self, with no debug line", function()
    local w, me = party()
    sign(me, 2)
    me.lines = {}
    w:post(me, "PARTY", helloText(me))
    w:post(me, "PARTY", entriesText(me)[1])
    w:deliver()
    assert.equal(2, stats(me).dropped.self)
    assert.same({}, me.lines)
    assert.equal(0, stored(me))
  end)
end)

describe("Sync receive: name normalization", function()
  it("resolves Mira and Mira-Stubrealm to one GUID and one stored name (PARTY)", function()
    local _, me, mira = party()
    sign(mira, 2, 10)
    local texts = entriesText(mira) -- 5 entries: 1, 2, 3, 10, 11
    local SP = me.ns.SyncProtocol
    local window = mira.ledger:shareWindow(40)
    inject(me, "InnLedger", "E1:" .. SP.canon(window[1]), "PARTY", "Mira")
    -- The bare name is stored in full at once (a later message would rename it anyway).
    assert.same({ 1, "Mira-Stubrealm" }, { held(me, mira.guid) })
    inject(me, "InnLedger", "E1:" .. SP.canon(window[2]), "PARTY", "Mira-Stubrealm")
    assert.equal(1, #texts)
    local n, name = held(me, mira.guid)
    assert.equal(2, n)
    assert.equal("Mira-Stubrealm", name)
    assert.equal(1, me.ledger:counts().travelers)
  end)

  it("resolves Mira and Mira-Stubrealm to one GUID and one stored name (GUILD)", function()
    local _, me, mira = guild()
    local SP = me.ns.SyncProtocol
    local window = mira.ledger:shareWindow(40)
    inject(me, "InnLedger", "E1:" .. SP.canon(window[1]), "GUILD", "Mira")
    assert.same({ 1, "Mira-Stubrealm" }, { held(me, mira.guid) })
    inject(me, "InnLedger", "E1:" .. SP.canon(window[2]), "GUILD", "Mira-Stubrealm")
    local n, name = held(me, mira.guid)
    assert.equal(2, n)
    assert.equal("Mira-Stubrealm", name)
  end)

  it("keeps another realm's name as the server gave it", function()
    local w, me, mira = party()
    w:setGroup({ me, harness.member("Mira", mira.guid, "Farshore") })
    inject(me, "InnLedger", entriesText(mira)[1], "PARTY", "Mira-Farshore")
    local _, name = held(me, mira.guid)
    assert.equal("Mira-Farshore", name)
  end)

  it("drops a 97-byte or empty sender unresolved, before any lookup", function()
    for _, sender in ipairs({ ("A"):rep(97), ("A"):rep(40) .. "-" .. ("B"):rep(56), "" }) do
      local _, me, mira, recv = party()
      me.impl.UnitGUID = function() return mira.guid end
      inject(me, "InnLedger", entriesText(mira)[1], "PARTY", sender)
      assert.equal(1, stats(me).dropped.unresolved)
      assert.is_nil(me.calls.UnitGUID)
      assert.equal(0, recv.n)
    end
    -- 96 bytes passes the shape check and reaches receive (whose name rule drops it).
    local w, me, mira, recv = party()
    w:setGroup({ me, harness.member(("A"):rep(96), mira.guid) })
    inject(me, "InnLedger", entriesText(mira)[1], "PARTY", ("A"):rep(96))
    assert.equal(1, recv.n)
    assert.equal(1, stats(me).dropped.sender)
    assert.equal(0, stored(me))
  end)
end)

describe("Sync receive: group map (#54)", function()
  -- Me (Aldric) grouped with `others` (clients or records), started after the group is set.
  local function groupOf(others, raid)
    local w = harness.new()
    local recv = { n = 0 }
    local me = w:add("Aldric", { setup = spyReceive(recv), start = false })
    local members = { me }
    for _, m in ipairs(others) do
      members[#members + 1] = type(m) == "string" and w:add(m) or m
    end
    w:setGroup(members, raid)
    for i = 2, #members do
      if members[i].client then
        members[i].client:onEvent("GROUP_ROSTER_UPDATE")
      end
    end
    assert.is_true(me.client:start())
    return w, me, members, recv
  end

  local function resolves(me, sender, channel)
    local before = stats(me).dropped.unresolved or 0
    inject(me, "InnLedger", "H1:0:0", channel or "PARTY", sender)
    return (stats(me).dropped.unresolved or 0) == before
  end

  local function keys(me)
    local out = {}
    for key in pairs(me.client.group) do
      out[#out + 1] = key
    end
    table.sort(out)
    return out
  end

  -- Records every argument the unit functions get.
  local function spyUnits(c)
    local asked = {}
    for _, fname in ipairs({ "UnitGUID", "UnitFullName", "UnitName" }) do
      local real = c.impl[fname]
      c.impl[fname] = function(unit, ...)
        asked[#asked + 1] = unit
        return real(unit, ...)
      end
    end
    return asked
  end

  local TOKENS = { "Target", "focus", "MOUSEOVER", "Targettarget", "Softfriend" }

  it("stores a member named like a unit token under its own GUID, never our target's",
    function()
      for _, token in ipairs(TOKENS) do
        local _, me, members = groupOf({ "Bram", token })
        local bram, peer = members[2], members[3]
        me.tokens[token:lower()] = bram.guid -- we target (focus, mouse over, ...) Bram
        sign(peer, 3)
        -- A bare sender, as the client might give it.
        for _, text in ipairs(entriesText(peer)) do
          inject(me, "InnLedger", text, "PARTY", token)
        end
        assert.equal(0, (held(me, bram.guid)), token)
        local n, name = held(me, peer.guid)
        assert.equal(3, n, token)
        assert.equal(token .. "-Stubrealm", name, token)
        assert.equal(3, stored(me), token)
      end
    end)

  it("drops a sender named like a token that no unit carries, in any case", function()
    local _, me, members, recv = groupOf({ "Bram", "Target" })
    local bram, peer = members[2], members[3]
    sign(peer, 3)
    for _, token in ipairs({ "target", "TARGET", "tArGeT", "focus", "Mouseover", "player",
      "party1", "raid1", "Target-Stubrealm-Stubrealm" }) do
      me.tokens[token:lower()] = bram.guid
      inject(me, "InnLedger", entriesText(peer)[1], "PARTY", token)
    end
    assert.equal(9, stats(me).dropped.unresolved)
    assert.equal(0, recv.n)
    assert.equal(0, stored(me))
  end)

  it("never passes a peer string to a unit function (party, raid, guild, hostile names)",
    function()
      for _, raid in ipairs({ false, true }) do
        local w, me, members = groupOf({ "Mira", "Target", "Bram" }, raid)
        local asked = spyUnits(me)
        sign(members[2], 12)
        w:setGuild(members)
        me.client:onEvent("PLAYER_GUILD_UPDATE")
        me.client:onEvent("GUILD_ROSTER_UPDATE")
        for _, sender in ipairs({ "Target", "target", "focus", "Mira", "Mira-Stubrealm",
          "player", "party1", "raid1", "Stranger", "Stranger-Farshore" }) do
          inject(me, "InnLedger", entriesText(members[2])[1], raid and "RAID" or "PARTY",
            sender)
          inject(me, "InnLedger", "H1:0:0", "GUILD", sender)
          w:advance(11) -- lets each miss rescan
        end
        me.client:onEvent("GROUP_ROSTER_UPDATE")
        w:advance(120) -- a whole sync round, both ways
        assert.is_true(#asked > 0)
        for _, unit in ipairs(asked) do
          assert.truthy(unit == "player" or unit:match("^party%d+$")
            or unit:match("^raid%d+$"), unit)
        end
        assert.equal(12, (held(me, members[2].guid)))
      end
    end)

  it("models the client: a bare token answers our target, a full name the member", function()
    -- Documents the harness model this ticket's forgery test relies on.
    local _, me, members = groupOf({ "Bram", "Target" })
    me.tokens.target = members[2].guid
    assert.equal(members[2].guid, me.api.UnitGUID("Target"))
    assert.equal(members[3].guid, me.api.UnitGUID("Target-Stubrealm"))
  end)

  it("leaves out a key that two units claim, until a scan finds it once", function()
    local w, me = groupOf({
      harness.member("Bram", "Player-1-0000B001"),
      harness.member("Bram", "Player-1-0000B002"),
      harness.member("Cora", "Player-1-0000C001"),
      harness.member("Cora", "Player-1-0000C002", "Farshore"),
    })
    assert.same({ "Aldric-Stubrealm", "Cora-Farshore", "Cora-Stubrealm" }, keys(me))
    assert.is_false(resolves(me, "Bram"))
    assert.is_false(resolves(me, "Bram-Stubrealm"))
    assert.is_true(resolves(me, "Cora"))
    assert.is_true(resolves(me, "Cora-Farshore"))
    assert.equal("Player-1-0000C001", me.client.group["Cora-Stubrealm"])
    assert.equal("Player-1-0000C002", me.client.group["Cora-Farshore"])
    -- A unit whose realm reads as ours in full collides with one whose realm reads nil.
    local fullName = me.impl.UnitFullName
    me.impl.UnitFullName = function(unit)
      if unit == "party4" then
        return "Cora", "Stubrealm"
      end
      return fullName(unit)
    end
    me.client:onEvent("GROUP_ROSTER_UPDATE")
    assert.is_nil(me.client.group["Cora-Stubrealm"])
    -- One Bram leaves: the next scan resolves the other.
    table.remove(w.group.members, 2)
    me.client:onEvent("GROUP_ROSTER_UPDATE")
    assert.equal("Player-1-0000B002", me.client.group["Bram-Stubrealm"])
  end)

  it("keys our own name, so our echo counts as self, but never adds us to the members",
    function()
      for _, raid in ipairs({ false, true }) do
        local w, me, members = groupOf({ "Mira" }, raid)
        assert.same({ "Aldric-Stubrealm", "Mira-Stubrealm" }, keys(me))
        assert.same({ [members[2].guid] = true }, me.client.members)
        sign(me, 1)
        w:post(me, raid and "RAID" or "PARTY", helloText(me))
        w:deliver()
        assert.equal(1, stats(me).dropped.self)
        assert.is_nil(stats(me).dropped.unresolved)
      end
    end)

  it("puts a unit's realm in the sender's form: no spaces or dashes, none means ours",
    function()
      local _, me = groupOf({ "Mira" })
      local realms = {
        { "Area 52", "Mira-Area52" },
        { "Azjol-Nerub", "Mira-AzjolNerub" },
        { "Farshore", "Mira-Farshore" },
        { "", "Mira-Stubrealm" },
        { " - ", "Mira-Stubrealm" },
        { ("R"):rep(48), "Mira-" .. ("R"):rep(48) },
      }
      for _, case in ipairs(realms) do
        me.impl.UnitFullName = function(unit)
          if unit == "party1" then
            return "Mira", case[1]
          end
        end
        me.client:onEvent("GROUP_ROSTER_UPDATE")
        assert.same({ case[2] }, keys(me), case[1])
      end
      -- Skipped: a realm too long once normalized, not a string, or hidden.
      local hiddenRealm = "Veiled"
      me.secret = function(v) return v == hiddenRealm end
      for i, bad in ipairs({ ("R"):rep(49), 42, {}, hiddenRealm, hostileProxy() }) do
        me.impl.UnitFullName = function(unit)
          if unit == "party1" then
            return "Mira", bad
          end
        end
        me.client:onEvent("GROUP_ROSTER_UPDATE")
        assert.same({}, keys(me), i)
      end
      assert.equal(0, stats(me).errors)
    end)

  it("falls back to UnitName, whose realm keeps its spaces", function()
    local _, me = groupOf({ harness.member("Mira", "Player-1-0000A001", "Area 52"), "Bram" })
    me.api.UnitFullName = nil
    me.client:onEvent("GROUP_ROSTER_UPDATE")
    assert.same({ "Aldric-Stubrealm", "Bram-Stubrealm", "Mira-Area52" }, keys(me))
    assert.is_true(resolves(me, "Mira-Area52"))
    assert.is_true(resolves(me, "Bram"))
    -- Neither: an empty map, every group sender unresolved.
    me.api.UnitName = nil
    me.client:onEvent("GROUP_ROSTER_UPDATE")
    assert.same({}, keys(me))
    assert.is_false(resolves(me, "Bram"))
    assert.equal(0, stats(me).errors)
  end)

  it("skips placeholder, dashed, hidden, odd and unreadable names, and keeps reading",
    function()
      local names = {
        "Unknown", "Inconnu", "Mi-ra", "Veiled", ("L"):rep(97), "", 42, false,
        hostileTable(), hostileProxy(), "RAISE", "Good",
      }
      local others = {}
      for i = 1, #names do
        others[i] = harness.member("Slot", ("Player-1-%08X"):format(0xA000 + i))
      end
      local _, me = groupOf(others)
      me.api.UNKNOWNOBJECT = "Inconnu"
      me.secret = function(v) return v == "Veiled" end
      me.impl.UnitFullName = function(unit)
        if unit == "player" then
          return "Aldric", "Stubrealm"
        end
        local name = names[tonumber(unit:match("%d+"))]
        if name == "RAISE" then
          error("boom")
        end
        return name, nil
      end
      me.client:onEvent("GROUP_ROSTER_UPDATE")
      -- "Unknown" is a real name here, since the client's placeholder is "Inconnu".
      assert.same({ "Aldric-Stubrealm", "Good-Stubrealm", "Unknown-Stubrealm" }, keys(me))
      me.api.UNKNOWNOBJECT = nil -- unreadable: the placeholder is "Unknown"
      me.client:onEvent("GROUP_ROSTER_UPDATE")
      assert.same({ "Aldric-Stubrealm", "Good-Stubrealm", "Inconnu-Stubrealm" }, keys(me))
      assert.equal(0, stats(me).errors)
    end)

  it("rescans the map on a miss at most once per 10 s, never touching the members",
    function()
      local w, me, members = groupOf({ "Mira" })
      local mira = members[2]
      sign(mira, 3)
      local loaded = false
      local fullName = me.impl.UnitFullName
      me.impl.UnitFullName = function(unit)
        if unit == "party1" and not loaded then
          return "Unknown", nil
        end
        return fullName(unit)
      end
      me.client:onEvent("GROUP_ROSTER_UPDATE")
      assert.same({ [mira.guid] = true }, me.client.members)
      local scans = function() return me.calls.UnitFullName or 0 end
      local before = scans()
      assert.is_false(resolves(me, "Mira")) -- a miss: one rescan, still not loaded
      assert.equal(before + 2, scans())      -- player and party1
      loaded = true
      for _ = 1, 100 do
        assert.is_false(resolves(me, "Mira"))
      end
      w:advance(9)
      assert.is_false(resolves(me, "Mira"))
      assert.equal(before + 2, scans())
      w:advance(1)
      inject(me, "InnLedger", entriesText(mira)[1], "PARTY", "Mira")
      assert.equal(3, stored(me))
      assert.equal(before + 4, scans())
      -- A newcomer with no roster event yet resolves through a rescan, but joins neither
      -- the member set nor a HELLO.
      local bram = w:add("Bram")
      sign(bram, 2, 50)
      w.group.members[#w.group.members + 1] = bram
      local hellos = 0
      local schedule = me.client.schedule
      local requestHello = schedule.requestHello
      schedule.requestHello = function(...)
        hellos = hellos + 1
        return requestHello(...)
      end
      w:advance(10)
      inject(me, "InnLedger", entriesText(bram)[1], "PARTY", bram.full)
      assert.equal(2, (held(me, bram.guid)))
      assert.same({ [mira.guid] = true }, me.client.members)
      assert.equal(0, hellos)
      schedule.requestHello = requestHello
      -- A clock that went back allows a rescan at once; a hidden one allows none.
      loaded = false
      me.client:onEvent("GROUP_ROSTER_UPDATE")
      loaded = true
      w.now = w.now - 3600
      assert.is_true(resolves(me, "Mira"))
      loaded = false
      me.client:onEvent("GROUP_ROSTER_UPDATE")
      loaded = true
      w:advance(20)
      me.secret = function(v) return v == w.now end
      assert.is_false(resolves(me, "Mira"))
    end)

  it("empties the map when we leave the group", function()
    local w, me = groupOf({ "Mira" })
    assert.is_true(resolves(me, "Mira"))
    w:setGroup({})
    me.client:onEvent("GROUP_ROSTER_UPDATE")
    assert.same({}, keys(me))
    w:advance(10)
    assert.is_false(resolves(me, "Mira"))
  end)
end)

describe("Sync receive: guild map", function()
  -- A guild of me and Mira plus extra roster rows, the map built at start.
  local function guildWith(rows, setup)
    local w = harness.new()
    local recv = { n = 0 }
    local me = w:add("Aldric", { setup = spyReceive(recv), start = false })
    local mira = w:add("Mira", { start = false })
    w:setGuild({ me, mira })
    for _, row in ipairs(rows) do
      w.guild.rows[#w.guild.rows + 1] = row
    end
    if setup then
      setup(me, w)
    end
    -- These cases count timers and roster reads; the send side's pump timer is switched off.
    me.client.requestPump = function() end
    assert.is_true(me.client:start())
    sign(mira, 3)
    return w, me, mira, recv
  end

  local function resolves(me, sender)
    local before = stats(me).dropped.unresolved or 0
    inject(me, "InnLedger", "H1:0:0", "GUILD", sender)
    return (stats(me).dropped.unresolved or 0) == before
  end

  it("leaves out a name that two or more rows claim", function()
    local _, me = guildWith({
      { name = "Bram-Stubrealm", guid = "Player-1-0000B001" },
      { name = "Bram-Stubrealm", guid = "Player-1-0000B002" },
      { name = "Cora", guid = "Player-1-0000C001" },              -- normalizes to Cora-Stubrealm
      { name = "Cora-Stubrealm", guid = "Player-1-0000C002" },
      { name = "Dain-Stubrealm", guid = "Player-1-0000D001" },
      { name = "Dain-Stubrealm", guid = "Player-1-0000D002" },
      { name = "Dain-Stubrealm", guid = "Player-1-0000D003" },
    })
    for _, sender in ipairs({ "Bram-Stubrealm", "Bram", "Cora", "Cora-Stubrealm", "Dain" }) do
      assert.is_false(resolves(me, sender), sender)
    end
    assert.is_true(resolves(me, "Mira-Stubrealm"))
  end)

  it("resolves a name again once a rebuild finds it only once", function()
    local w, me = guildWith({
      { name = "Bram-Stubrealm", guid = "Player-1-0000B001" },
      { name = "Bram-Stubrealm", guid = "Player-1-0000B002" },
    })
    assert.is_false(resolves(me, "Bram"))
    table.remove(w.guild.rows)
    w:advance(10)
    me.client:onEvent("GUILD_ROSTER_UPDATE")
    assert.is_true(resolves(me, "Bram"))
  end)

  it("skips rows with hidden or invalid names or GUIDs, and keeps reading", function()
    local veiledGUID, veiledName = "Player-1-0000AAAA", "Veiled-Stubrealm"
    local _, me, mira, recv = guildWith({
      { name = "Hidden-Stubrealm", guid = veiledGUID },
      { name = "Proxy-Stubrealm", guid = hostileProxy() },
      { name = "Table-Stubrealm", guid = hostileTable() },
      { name = "Creature-Stubrealm", guid = "Creature-0-1-2-3-4-5" },
      { name = "Number-Stubrealm", guid = 42 },
      { name = veiledName, guid = "Player-1-0000AAAB" },
      { name = hostileTable(), guid = "Player-1-0000AAAC" },
      { name = hostileProxy(), guid = "Player-1-0000AAAD" },
      { name = ("L"):rep(97), guid = "Player-1-0000AAAE" },
      { name = "", guid = "Player-1-0000AAAF" },
      { name = 42, guid = "Player-1-0000AAB0" },
    }, function(me)
      me.secret = function(v) return v == veiledGUID or v == veiledName end
    end)
    assert.equal(0, stats(me).errors)
    -- Skipped when the map is built, not only when a sender is resolved.
    local keys = {}
    for key in pairs(me.client.guild) do
      keys[#keys + 1] = key
    end
    table.sort(keys)
    assert.same({ "Aldric-Stubrealm", "Mira-Stubrealm" }, keys)
    assert.is_nil(me.client.guild["Hidden-Stubrealm"])
    assert.is_nil(me.client.guild[veiledName])
    for _, sender in ipairs({ "Hidden", "Proxy", "Table", "Creature", "Number", "Veiled" }) do
      assert.is_false(resolves(me, sender), sender)
    end
    inject(me, "InnLedger", entriesText(mira)[1], "GUILD", "Mira")
    assert.equal(3, stored(me))
    assert.equal(1, recv.n)
  end)

  it("skips a row whose GetGuildRosterInfo raises", function()
    local _, me = guildWith({ { name = "Bram-Stubrealm", guid = "Player-1-0000B001" } },
      function(me, w)
        me.impl.GetGuildRosterInfo = function(i)
          if i == 1 then
            error("boom")
          end
          local row = w.guild.rows[i]
          return row.name, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
            nil, nil, row.guid
        end
      end)
    assert.is_false(resolves(me, "Aldric"))
    assert.is_true(resolves(me, "Mira"))
    assert.is_true(resolves(me, "Bram"))
    assert.equal(0, stats(me).errors)
  end)

  it("reads at most 2 000 rows of a 2 500-row roster", function()
    local rows = {}
    for i = 1, 2498 do
      rows[i] = { name = letters(i) .. "-Stubrealm", guid = ("Player-1-%08X"):format(4096 + i) }
    end
    local _, me = guildWith(rows)
    assert.equal(2000, me.calls.GetGuildRosterInfo)
    -- Rows 1-2 are me and Mira, so rows[1998] is roster row 2000.
    assert.is_true(resolves(me, letters(1998)))
    assert.is_false(resolves(me, letters(1999)))
    assert.is_false(resolves(me, letters(2498)))
  end)

  it("reads no rows when the member count is hidden, not a number or raises", function()
    local hiddenCount = 7
    local cases = {
      NaN = function() return 0 / 0 end,
      string = function() return "2" end,
      ["nil"] = function() return nil end,
      negative = function() return -1 end,
      proxy = function() return hostileProxy() end,
      raising = function() error("boom") end,
      hidden = function() return hiddenCount end,
    }
    for name, count in pairs(cases) do
      local _, me = guildWith({}, function(me)
        me.impl.GetNumGuildMembers = count
        me.secret = function(v) return v == hiddenCount end
      end)
      assert.is_nil(me.calls.GetGuildRosterInfo, name)
      assert.is_false(resolves(me, "Mira"), name)
      assert.equal(0, stats(me).errors, name)
    end
    local _, me = guildWith({}, function(me)
      me.impl.GetNumGuildMembers = function() return math.huge end
    end)
    assert.equal(2000, me.calls.GetGuildRosterInfo)
    assert.is_true(resolves(me, "Mira"))
  end)

  it("is rebuilt at most once per 10 s, with one trailing rebuild", function()
    local w, me = guildWith({})
    assert.equal(1, me.calls.GetNumGuildMembers) -- at start
    w:advance(1)
    w.guild.rows[#w.guild.rows + 1] = { name = "Bram-Stubrealm", guid = "Player-1-0000B001" }
    for _ = 1, 9 do
      me.client:onEvent("GUILD_ROSTER_UPDATE")
      assert.equal(1, me.calls.GetNumGuildMembers)
      assert.equal(1, #w.timers)
      assert.is_false(resolves(me, "Bram"))
      w:advance(1)
    end
    -- t = 10: the one trailing rebuild ran.
    assert.same({}, w.timers)
    assert.equal(2, me.calls.GetNumGuildMembers)
    assert.is_true(resolves(me, "Bram"))
    w:advance(1)
    me.client:onEvent("GUILD_ROSTER_UPDATE")
    me.client:onEvent("GUILD_ROSTER_UPDATE")
    assert.equal(2, me.calls.GetNumGuildMembers)
    w:advance(8)
    assert.equal(2, me.calls.GetNumGuildMembers)
    w:advance(1)
    assert.equal(3, me.calls.GetNumGuildMembers)
    w:advance(30)
    me.client:onEvent("GUILD_ROSTER_UPDATE") -- past the gap: at once
    assert.equal(4, me.calls.GetNumGuildMembers)
    assert.same({}, w.timers)
  end)

  it("rebuilds at once when the clock went back", function()
    local w, me = guildWith({})
    w.now = NOW - 3600
    me.client:onEvent("GUILD_ROSTER_UPDATE")
    assert.equal(2, me.calls.GetNumGuildMembers)
  end)

  it("skips a roster update while the clock is unreadable", function()
    local w, me = guildWith({})
    w.now = 0 / 0
    me.client:onEvent("GUILD_ROSTER_UPDATE")
    assert.equal(1, me.calls.GetNumGuildMembers)
    assert.same({}, w.timers)
  end)

  it("is cleared on leaving the guild, and a pending trailing rebuild is cancelled", function()
    local w, me, mira = guildWith({})
    assert.is_true(resolves(me, "Mira"))
    w:advance(1)
    me.client:onEvent("GUILD_ROSTER_UPDATE") -- schedules the trailing rebuild
    w:setGuild({ mira })
    me.client:onEvent("PLAYER_GUILD_UPDATE", "player")
    assert.is_false(resolves(me, "Mira"))
    local builds = me.calls.GetNumGuildMembers
    w:advance(20)
    assert.equal(builds, me.calls.GetNumGuildMembers)
    assert.is_false(resolves(me, "Mira"))
    -- Rejoining: the roster is requested, and the next roster update rebuilds the map.
    w:advance(60)
    local requests = me.calls.GuildRoster
    w:setGuild({ me, mira })
    me.client:onEvent("PLAYER_GUILD_UPDATE", "player")
    assert.equal(requests + 1, me.calls.GuildRoster)
    me.client:onEvent("GUILD_ROSTER_UPDATE")
    assert.is_true(resolves(me, "Mira"))
  end)

  it("doesn't run a trailing rebuild cancelled by leaving, even after rejoining", function()
    local w, me, mira = guildWith({})
    w:advance(1)
    me.client:onEvent("GUILD_ROSTER_UPDATE") -- trailing rebuild due at t = 10
    w:setGuild({ mira })
    me.client:onEvent("PLAYER_GUILD_UPDATE")
    w:advance(1)
    w:setGuild({ me, mira })
    me.client:onEvent("PLAYER_GUILD_UPDATE")
    local builds = me.calls.GetNumGuildMembers
    w:advance(20)
    assert.equal(builds, me.calls.GetNumGuildMembers)
    assert.is_false(resolves(me, "Mira"))
    -- A new roster update schedules afresh.
    me.client:onEvent("GUILD_ROSTER_UPDATE")
    assert.equal(builds + 1, me.calls.GetNumGuildMembers)
    assert.is_true(resolves(me, "Mira"))
  end)

  it("lets an immediate rebuild supersede a pending trailing one", function()
    local w, me = guildWith({})
    w:advance(1)
    me.client:onEvent("GUILD_ROSTER_UPDATE") -- trailing rebuild due at t = 10
    assert.equal(1, #w.timers)
    w.now = NOW - 100
    me.client:onEvent("GUILD_ROSTER_UPDATE") -- the clock went back: rebuilt at once
    assert.equal(2, me.calls.GetNumGuildMembers)
    w.now = NOW + 9
    w:advance(1) -- the stale timer fires and does nothing
    assert.same({}, w.timers)
    assert.equal(2, me.calls.GetNumGuildMembers)
  end)

  it("doesn't let a lost timer block later trailing rebuilds", function()
    local w, me = guildWith({})
    me.impl.After = function() end -- the timer never fires
    w:advance(1)
    me.client:onEvent("GUILD_ROSTER_UPDATE")
    w:advance(20)
    me.client:onEvent("GUILD_ROSTER_UPDATE") -- past the gap: at once
    assert.equal(2, me.calls.GetNumGuildMembers)
    me.impl.After = function(delay, fn) w:after(delay, fn) end
    w:advance(1)
    me.client:onEvent("GUILD_ROSTER_UPDATE") -- inside the gap: a fresh trailing rebuild
    assert.equal(1, #w.timers)
    w:advance(9)
    assert.equal(3, me.calls.GetNumGuildMembers)
  end)

  it("requests the roster at once when rejoining soon after leaving", function()
    local w, me, mira = guildWith({})
    assert.equal(1, me.calls.GuildRoster) -- at start
    w:advance(5)
    w:setGuild({ mira })
    me.client:onEvent("PLAYER_GUILD_UPDATE")
    w:advance(1)
    w:setGuild({ me, mira })
    me.client:onEvent("PLAYER_GUILD_UPDATE")
    assert.equal(2, me.calls.GuildRoster)
    me.client:onEvent("PLAYER_GUILD_UPDATE") -- still inside the 60 s limit
    assert.equal(2, me.calls.GuildRoster)
  end)

  it("treats a hidden IsInGuild as not in a guild", function()
    local _, me = guildWith({}, function(me)
      me.impl.IsInGuild = function() return "in a guild" end
      me.secret = function(v) return v == "in a guild" end
    end)
    assert.is_nil(me.calls.GuildRoster)
    assert.is_nil(me.calls.GetNumGuildMembers)
    assert.is_false(resolves(me, "Mira"))
    -- The same value, readable, counts as in a guild.
    local _, other = guildWith({}, function(c)
      c.impl.IsInGuild = function() return "in a guild" end
    end)
    assert.equal(1, other.calls.GuildRoster)
    assert.is_true(resolves(other, "Mira"))
  end)

  it("keeps a roster update from filling the map while we're not in a guild", function()
    local w, me, mira = guildWith({})
    w:setGuild({ mira })
    me.client:onEvent("PLAYER_GUILD_UPDATE")
    w:advance(10)
    me.client:onEvent("GUILD_ROSTER_UPDATE")
    assert.is_false(resolves(me, "Mira"))
  end)

  it("requests the roster at start only when in a guild", function()
    local _, me = guildWith({})
    assert.equal(1, me.calls.GuildRoster)
    local w = harness.new()
    local solo = w:add("Aldric")
    assert.is_nil(solo.calls.GuildRoster)
    assert.is_true(solo.started)
  end)
end)

describe("Sync receive: read-only ledger", function()
  it("registers no prefix, handles no event and stores nothing", function()
    local w = harness.new()
    local recv = { n = 0 }
    local me = w:add("Aldric", { data = "junk", setup = spyReceive(recv), start = false })
    local mira = w:add("Mira")
    w:setGroup({ me, mira })
    w:setGuild({ me, mira })
    sign(mira, 3)
    assert.is_true(me.ledger.readOnly)
    assert.is_false(me.client:start())
    assert.is_nil(me.calls.RegisterPrefix)
    assert.same({ "sync: off (read-only)" }, me.lines)
    me.lines = {}
    inject(me, "InnLedger", entriesText(mira)[1], "PARTY", mira.full)
    me.client:onEvent("GUILD_ROSTER_UPDATE")
    me.client:onEvent("PLAYER_GUILD_UPDATE")
    assert.equal(0, recv.n)
    assert.equal(0, stored(me))
    assertQuiet(me)
    assert.same({}, me.lines)
    assert.is_nil(me.calls.GetNumGuildMembers)
    assert.is_nil(me.calls.GuildRoster)
    assert.is_nil(w.sent[1])
    assert.same({}, w.timers)
  end)

  it("stays off without a ledger", function()
    local w = harness.new()
    local me = w:add("Aldric", { start = false })
    me.client = me.ns.Sync.new({
      api = me.api, debug = function(line) me.lines[#me.lines + 1] = line end,
    })
    assert.is_false(me.client:start())
    assert.same({ "sync: off (no ledger)" }, me.lines)
    inject(me, "InnLedger", "H1:0:0", "PARTY", "Mira-Stubrealm")
    assertQuiet(me)
  end)
end)

describe("Sync receive: prefix registration", function()
  local ENUM = { RegisterAddonMessagePrefixResult = {
    Success = 0, DuplicatePrefix = 1, InvalidPrefix = 2, TooManyPrefixes = 3,
  } }

  local function startWith(result, enum)
    local w = harness.new()
    local me = w:add("Aldric", { start = false })
    local mira = w:add("Mira")
    w:setGroup({ me, mira })
    sign(mira, 3)
    me.impl.RegisterPrefix = result
    me.api.Enum = enum
    local on = me.client:start()
    inject(me, "InnLedger", entriesText(mira)[1], "PARTY", mira.full)
    return on, me
  end

  it("turns sync off for any other result", function()
    local hiddenResult = hostileProxy()
    local cases = {
      ["false"] = { function() return false end },
      ["nil"] = { function() return nil end },
      ["2"] = { function() return 2 end },
      ["1 without the enum"] = { function() return 1 end },
      ["1 with an enum lacking the table"] = { function() return 1 end, {} },
      ["InvalidPrefix"] = { function() return 2 end, ENUM },
      ["TooManyPrefixes"] = { function() return 3 end, ENUM },
      string = { function() return "InnLedger" end, ENUM },
      table = { function() return {} end, ENUM },
      raising = { function() error("boom") end, ENUM },
      ["a stand-in"] = { function() return hiddenResult end, ENUM },
    }
    for name, case in pairs(cases) do
      local on, me = startWith(case[1], case[2])
      assert.is_false(on, name)
      assert.same({ "sync: off (prefix)" }, me.lines, name)
      assert.equal(0, stored(me), name)
      assertQuiet(me)
    end
  end)

  it("turns sync off for a hidden result or a missing function", function()
    assert.is_true((startWith(function() return true end)))
    local w = harness.new()
    local me = w:add("Aldric", { start = false })
    me.secret = function(v) return v == true end
    assert.is_false(me.client:start())
    me = w:add("Bram", { start = false })
    me.api.RegisterPrefix = nil
    assert.is_false(me.client:start())
    assert.same({ "sync: off (prefix)" }, me.lines)
  end)

  it("accepts true, 0, and the enum's Success and DuplicatePrefix", function()
    local cases = {
      { function() return true end },
      { function() return 0 end },
      { function() return 0 end, ENUM },
      { function() return 1 end, ENUM },
    }
    for i, case in ipairs(cases) do
      local on, me = startWith(case[1], case[2])
      assert.is_true(on, i)
      assert.equal(3, stored(me), i)
    end
  end)

  it("registers the prefix InnLedger once, even if started twice", function()
    local w = harness.new()
    local me = w:add("Aldric", { start = false })
    local asked = {}
    me.impl.RegisterPrefix = function(prefix)
      asked[#asked + 1] = prefix
      return true
    end
    assert.is_true(me.client:start())
    assert.is_true(me.client:start())
    assert.same({ "InnLedger" }, asked)
  end)
end)

describe("Sync receive: errors inside a handler", function()
  it("catches a receive that raises, counts it and logs no error text", function()
    local w = harness.new()
    local me = w:add("Aldric", { setup = function(ns)
      ns.SyncProtocol.receive = function() error("peer text Mira |cffff0000") end
    end })
    local mira = w:add("Mira")
    w:setGroup({ me, mira })
    sign(mira, 1)
    assert.has_no.errors(function()
      inject(me, "InnLedger", entriesText(mira)[1], "PARTY", mira.full)
    end)
    assert.equal(1, stats(me).errors)
    assert.equal("sync: error in CHAT_MSG_ADDON", me.lines[#me.lines])
    for _, line in ipairs(me.lines) do
      assert.falsy(line:find("peer", 1, true))
      assert.falsy(line:find("Mira", 1, true))
      assert.falsy(line:find("|", 1, true))
    end
  end)

  it("catches a schedule that raises", function()
    local w, me, mira = party()
    me.client.schedule.onHello = function() error("boom") end
    w:post(mira, "PARTY", helloText(mira))
    assert.has_no.errors(function() w:deliver() end)
    assert.equal(1, stats(me).errors)
  end)

  it("catches a debug sink that raises", function()
    local w = harness.new()
    local me = w:add("Aldric", { deps = { debug = function() error("boom") end } })
    assert.is_true(me.started)
    assert.has_no.errors(function() inject(me, "InnLedger", "H1:0:0", "WHISPER", "Mira") end)
    assert.equal(1, stats(me).dropped.channel)
  end)

  it("catches a timer call that raises, and a trailing rebuild that raises", function()
    local w, me = guild()
    me.client.requestPump = function() end -- only the rebuild timer here
    me.impl.After = function() error("boom") end
    w:advance(1)
    assert.has_no.errors(function() me.client:onEvent("GUILD_ROSTER_UPDATE") end)
    assert.equal(1, stats(me).errors)
    assert.equal("sync: error in GUILD_ROSTER_UPDATE", me.lines[#me.lines])

    local w2, me2 = guild()
    w2:advance(1)
    me2.client:onEvent("GUILD_ROSTER_UPDATE")
    me2.ns.Ledger.validGUID = function() error("boom") end
    assert.has_no.errors(function() w2:advance(10) end)
    assert.equal(1, stats(me2).errors)
    assert.equal("sync: error in rebuild", me2.lines[#me2.lines])
  end)

  it("catches an error while starting", function()
    local w = harness.new()
    local me = w:add("Aldric", { start = false })
    local ledger = setmetatable({}, { __index = function() error("boom") end })
    me.client = me.ns.Sync.new({
      ledger = ledger, api = me.api,
      debug = function(line) me.lines[#me.lines + 1] = line end,
    })
    assert.has_no.errors(function() assert.is_false(me.client:start()) end)
    assert.equal(1, me.client.stats.errors)
    assert.same({ "sync: error in start" }, me.lines)
  end)

  it("ignores events it doesn't handle", function()
    local _, me = party()
    me.client:onEvent("CHAT_MSG_ADDON_LOGGED")
    me.client:onEvent("SOMETHING_ELSE", 1, 2)
    me.client:onEvent(nil)
    assertQuiet(me)
  end)

  it("raises from Sync.new only on a caller bug", function()
    local w = harness.new()
    local me = w:add("Aldric", { start = false })
    assert.has_error(function() me.ns.Sync.new() end)
    assert.has_error(function() me.ns.Sync.new({}) end)
    assert.has_error(function() me.ns.Sync.new({ api = {} }) end) -- no random
    local c = me.ns.Sync.new({ api = me.api, inns = "junk", phrases = 7, phraseOk = "x" })
    assert.same({}, c.ctx.inns)
    assert.same({}, c.ctx.phrases)
    assert.same({}, c.ctx.seals)
    assert.is_nil(c.ctx.phraseOk)
  end)
end)

describe("Sync receive: debug output", function()
  local EVIL = "Evil|cffff0000Name"
  local PIPE = "|cffff0000x"

  local function assertClean(lines)
    assert.is_true(#lines > 0)
    for _, line in ipairs(lines) do
      for _, bad in ipairs({ "|", "Evil", "cffff", "Hitem", "Mira", "WHISPER", "boom" }) do
        assert.falsy(line:find(bad, 1, true), line)
      end
    end
  end

  it("never writes a peer's name, text or channel", function()
    local w, me, mira = party()
    local evilGUID = "Player-1-0000E111"
    w:setGroup({ me, mira, { name = EVIL, full = EVIL .. "-Stubrealm", guid = evilGUID } })
    me.lines = {}
    -- A hostile name that resolves (receive's name rule drops it) and one that doesn't.
    inject(me, "InnLedger", "H1:0:0", "PARTY", EVIL)
    inject(me, "InnLedger", "H1:0:0", "RAID", "Evil|Hitem:1|hOther")
    -- Pipe escapes in the message text from a resolved peer.
    inject(me, "InnLedger", PIPE, "PARTY", mira.full)
    inject(me, "InnLedger", "E1:|Hitem:1|h[x]|h", "PARTY", mira.full)
    -- A whisper from someone called |cffff0000x, and a channel called that.
    inject(me, "InnLedger", "H1:0:0", "WHISPER", PIPE)
    inject(me, "InnLedger", "H1:0:0", PIPE, mira.full)
    -- An error whose text echoes peer data.
    me.client.schedule.onHello = function() error("boom Mira |cffff0000") end
    inject(me, "InnLedger", helloText(mira), "PARTY", mira.full)
    assertClean(me.lines)
    assert.is_true(hasLine(me, "sync: drop sender PARTY " .. evilGUID))
    assert.is_true(hasLine(me, "sync: drop unresolved RAID"))
    assert.is_true(hasLine(me, "sync: drop charset PARTY " .. mira.guid))
    assert.is_true(hasLine(me, "sync: drop channel other"))
    assert.is_true(hasLine(me, "sync: error in CHAT_MSG_ADDON"))
  end)
end)

describe("Sync receive: seeded fuzz", function()
  it("never throws, and stores only under a resolved member's GUID and name", function()
    local seed = 20260927
    local function pick(list)
      seed = seed * 16807 % 2147483647
      return list[1 + seed % #list]
    end
    local w = harness.new()
    local me = w:add("Aldric", { start = false })
    local mira = w:add("Mira", { start = false })
    local bram = w:add("Bram", { start = false }) -- never a member
    w:setGroup({ me, mira })
    w:setGuild({ me, mira })
    assert.is_true(me.client:start())
    sign(mira, 12)
    sign(bram, 12, 100)
    local SP = me.ns.SyncProtocol
    local texts = { "H1:0:0", helloText(mira), helloText(bram), SP.encodeWant(me.guid, 0),
      SP.encodeWant(bram.guid, 0), "|cffff0000x", ("E"):rep(300), "", "E1:", "W1:x:0",
      hostileTable(), hostileProxy(), 42 }
    for _, list in ipairs({ entriesText(mira), entriesText(bram), entriesText(mira, NOW) }) do
      for _, t in ipairs(list) do
        texts[#texts + 1] = t
      end
    end
    local prefixes = { "InnLedger", "InnLedger", "InnLedger", "Other", "", hostileTable(), 7 }
    local channels = { "PARTY", "RAID", "GUILD", "GUILD", "WHISPER", "INSTANCE_CHAT", "SAY",
      "|cffff0000x", hostileProxy() }
    local senders = { mira.full, "Mira", bram.full, "Bram", me.full, "Evil|cffff0000Name",
      ("A"):rep(97), "", hostileTable(), hostileProxy() }
    local flags = { false, false, false, "Stubrealm", mira.guid, mira.full, "PARTY",
      "InnLedger", "raise" }
    for step = 1, 3000 do
      local flag = pick(flags)
      if flag == "raise" then
        me.impl.issecretvalue = function() error("boom") end
      else
        me.impl.issecretvalue = function(v) return flag ~= false and v == flag end
      end
      local roll = step % 50
      assert.has_no.errors(function()
        if roll == 0 then
          me.client:onEvent("GUILD_ROSTER_UPDATE")
        elseif roll == 25 then
          me.client:onEvent("PLAYER_GUILD_UPDATE")
        else
          inject(me, pick(prefixes), pick(texts), pick(channels), pick(senders))
        end
      end)
      if step % 10 == 0 then
        w:advance(1)
      end
    end
    assert.equal(0, stats(me).errors)
    assert.is_true(stats(me).added > 0)
    -- A bare "Mira" is stored as is while the realm is hidden (spec 3.4).
    for _, t in ipairs(me.ledger:travelers()) do
      assert.equal(mira.guid, t.guid)
      assert.is_true(t.name == "Mira-Stubrealm" or t.name == "Mira", t.name)
    end
    for _, line in ipairs(me.lines) do
      assert.falsy(line:find("|", 1, true), line)
      assert.falsy(line:find("Mira", 1, true), line)
      assert.falsy(line:find("Bram", 1, true), line)
    end
  end)
end)

describe("the harness", function()
  it("delivers a send to everyone on the channel, the sender included, at the next step", function()
    local w = harness.new()
    local me, mira = w:add("Aldric"), w:add("Mira")
    local outsider = w:add("Vesna")
    w:setGroup({ me, mira })
    sign(me, 1)
    local done = {}
    me.api.send(helloText(me), "PARTY", function(_, didSend) done[#done + 1] = didSend end)
    assert.same({ true }, done)
    assert.equal(1, #w.sent)
    assert.equal(0, (stats(mira).received.hello or 0))
    w:advance(1)
    assert.equal(1, stats(mira).received.hello)
    assert.equal(1, stats(me).dropped.self)
    assertQuiet(outsider)

    me.sendMode = "defer"
    me.api.send("H1:0:0", "PARTY", function(_, didSend) done[#done + 1] = didSend end)
    assert.equal(1, #done)
    w:advance(1)
    assert.same({ true, true }, done)
    me.sendMode = "fail"
    me.api.send("H1:0:0", "PARTY", function(_, didSend) done[#done + 1] = didSend end)
    assert.same({ true, true, false }, done)
  end)

  it("answers unit tokens for the group and a raid", function()
    local w = harness.new()
    local me, mira, bram = w:add("Aldric"), w:add("Mira"), w:add("Bram")
    w:setGroup({ me, mira, bram })
    assert.equal(mira.guid, me.api.UnitGUID("party1"))
    assert.equal(bram.guid, me.api.UnitGUID("party2"))
    assert.is_nil(me.api.UnitGUID("party3"))
    assert.is_nil(me.api.UnitGUID("raid1"))
    w:setGroup({ me, mira, bram }, true)
    assert.equal(me.guid, me.api.UnitGUID("raid1"))
    assert.is_true(me.api.IsInRaid())
    assert.equal(3, me.api.GetNumGroupMembers())
    local r = me.api.random(5, 15)
    assert.is_true(r >= 5 and r <= 15 and r % 1 == 0)
  end)
end)

-- ---------------------------------------------------------------------------
-- The real client: ns.Sync:Start() under the WoW stub, through Core's login.

describe("ns.Sync:Start (the real client)", function()
  local GUID = "Player-1-00000001" -- the stub's own GUID
  local MIRA = "Player-1-00000002"
  local STUB_NOW = 1800000000

  -- Logs in; frames Sync makes after the files load are collected in `frames`.
  local function login(opts)
    opts = opts or {}
    wow.install(opts.overrides)
    if opts.db ~= nil then
      _G.InnkeepersLedgerDB = opts.db
    end
    local ns = load.addon({})
    local frames = {}
    local create = _G.CreateFrame
    _G.CreateFrame = function(...)
      local frame = create(...)
      frames[#frames + 1] = frame
      return frame
    end
    if opts.setup then
      opts.setup(ns)
    end
    wow.fire("ADDON_LOADED", load.ADDON_NAME)
    wow.fire("PLAYER_LOGIN")
    return ns, frames
  end

  local function registered(frames)
    local events = {}
    for _, frame in ipairs(frames) do
      for event in pairs(frame.events) do
        events[event] = true
      end
    end
    return events
  end

  local function prefixes(list)
    return { C_ChatInfo = {
      RegisterAddonMessagePrefix = function(prefix)
        list[#list + 1] = prefix
        return list.result == nil and true or list.result
      end,
    } }
  end

  -- A party of the stub's player and Mira: the unit scan finds her as party1.
  local function inParty()
    return {
      IsInGroup = function() return true end,
      GetNumGroupMembers = function() return 2 end,
      UnitGUID = function(unit)
        if unit == "player" then return GUID end
        if unit == "party1" then return MIRA end
      end,
      UnitFullName = function(unit)
        if unit == "player" then return "Traveler", "Stubrealm" end
        if unit == "party1" then return "Mira", nil end
      end,
    }
  end

  after_each(wow.uninstall)

  it("registers the prefix and its six events, and exposes stats", function()
    local asked = {}
    local ns, frames = login({ overrides = prefixes(asked) })
    assert.same({}, wow.errors)
    assert.same({ "InnLedger" }, asked)
    assert.same({ CHAT_MSG_ADDON = true, GROUP_ROSTER_UPDATE = true, GUILD_ROSTER_UPDATE = true,
      PLAYER_GUILD_UPDATE = true, PLAYER_REGEN_DISABLED = true, PLAYER_REGEN_ENABLED = true },
      registered(frames))
    assert.is_table(ns.Sync.stats)
    assert.equal(ns.Sync.client.stats, ns.Sync.stats)
    wow.chat = {}
    wow.slash("/ledger debug")
    assert.truthy(wow.chat[2]:find("ledger: open; sync: received 0, dropped 0, added 0, dup 0, "
      .. "rejected 0, evicted 0, sent 0, sendFailed 0, errors 0; names realm", 1, true),
      wow.chat[2])
  end)

  it("receives CHAT_MSG_ADDON; with the real, empty data every entry is rejected", function()
    local ns = login({ overrides = inParty() })
    wow.fire("CHAT_MSG_ADDON", "InnLedger", "E1:1," .. (STUB_NOW - 50) .. ",1,0", "PARTY",
      "Mira-Stubrealm", "", 0, 0, "", 0)
    assert.same({}, wow.errors)
    assert.equal(1, ns.Sync.stats.received.entries)
    assert.equal(1, ns.Sync.stats.rejected)
    assert.equal(0, ns.ledger:counts().foreign)
    wow.fire("CHAT_MSG_ADDON", "InnLedger", "H1:0:0", "WHISPER", "Mira-Stubrealm")
    assert.equal(1, ns.Sync.stats.dropped.channel)
  end)

  it("builds the guild map from the stub's roster at start", function()
    local requests = 0
    local ns = login({ overrides = {
      IsInGuild = function() return true end,
      GetNumGuildMembers = function() return 1, 1, 1 end,
      GetGuildRosterInfo = function(i)
        if i == 1 then
          return "Mira-Stubrealm", nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
            nil, nil, nil, MIRA
        end
      end,
      C_GuildInfo = { GuildRoster = function() requests = requests + 1 end },
    } })
    assert.equal(1, requests)
    wow.fire("CHAT_MSG_ADDON", "InnLedger", "H1:1:5", "GUILD", "Mira")
    assert.equal(1, ns.Sync.stats.received.hello)
    wow.fire("GUILD_ROSTER_UPDATE")
    wow.advance(10)
    assert.same({}, wow.errors)
    assert.equal(0, ns.Sync.stats.errors)
  end)

  it("stays off for a read-only ledger: no prefix, no frame events", function()
    local asked = {}
    local ns, frames = login({ overrides = prefixes(asked),
      db = { global = { ledgers = "junk" } } })
    assert.is_true(ns.ledger.readOnly)
    assert.same({}, asked)
    assert.same({}, registered(frames))
    assert.is_table(ns.Sync.stats)
    wow.fire("CHAT_MSG_ADDON", "InnLedger", "H1:0:0", "PARTY", "Mira-Stubrealm")
    assert.same({}, ns.Sync.stats.received)
  end)

  it("stays off when the ledger failed to open", function()
    local asked = {}
    local ns, frames = login({ overrides = prefixes(asked), setup = function(ns)
      ns.Ledger.new = function() error("boom") end
    end })
    assert.is_nil(ns.ledger)
    assert.same({}, asked)
    assert.same({}, registered(frames))
  end)

  it("stays off when the prefix is refused, and accepts DuplicatePrefix", function()
    local asked = { result = 2 }
    local _, frames = login({ overrides = prefixes(asked) })
    assert.same({}, registered(frames))
    wow.uninstall()

    asked = { result = 1 }
    local overrides = prefixes(asked)
    overrides.Enum = { RegisterAddonMessagePrefixResult = { Success = 0, DuplicatePrefix = 1 } }
    _, frames = login({ overrides = overrides })
    assert.is_true(registered(frames).CHAT_MSG_ADDON)
  end)

  it("runs once when called again", function()
    local ns, frames = login()
    local client = ns.Sync.client
    ns.Sync:Start()
    assert.equal(client, ns.Sync.client)
    local n = 0
    for _, frame in ipairs(frames) do
      if frame.events.CHAT_MSG_ADDON then
        n = n + 1
      end
    end
    assert.equal(1, n)
  end)

  it("counts an error while starting and never raises it", function()
    local ns = login({ setup = function()
      _G.CreateFrame = function() error("boom") end
    end })
    assert.same({}, wow.errors)
    assert.equal(1, ns.Sync.stats.errors)

    wow.uninstall()
    ns = login({ setup = function(addon)
      addon.Sync.new = function() error("boom") end
    end })
    assert.same({}, wow.errors)
    assert.equal(1, ns.Sync.stats.errors)
  end)

  it("writes debug lines to chat without peer strings", function()
    local ns = login({ overrides = inParty() })
    wow.slash("/ledger debug")
    wow.chat = {}
    wow.fire("CHAT_MSG_ADDON", "InnLedger", "H1:0:0", "PARTY", "Evil|cffff0000Name")
    wow.fire("CHAT_MSG_ADDON", "InnLedger", "|cffff0000x", "PARTY", "Mira-Stubrealm")
    wow.fire("CHAT_MSG_ADDON", "InnLedger", "H1:0:0", "WHISPER", "|cffff0000x")
    wow.fire("CHAT_MSG_ADDON", "InnLedger", "H1:0:0", "|cffff0000x", "Mira-Stubrealm")
    assert.equal(4, #wow.chat)
    for _, line in ipairs(wow.chat) do
      for _, bad in ipairs({ "Evil", "cffff", "Mira", "WHISPER" }) do
        assert.falsy(line:find(bad, 1, true), line)
      end
    end
    assert.equal(1, ns.Sync.stats.dropped.charset)
  end)
end)
