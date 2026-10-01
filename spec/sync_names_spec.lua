-- Sync with Forever's two-part names (#75; docs/specs/sync-glue.md 3.4). In the beta the
-- surname fills the realm slot of UnitName / UnitFullName and senders arrive as a bare
-- "First Surname". These cases run the harness in its Forever mode, then the real client
-- under the WoW stub. Peer data is hostile: near-misses, case changes, realm suffixes and
-- placeholders must never resolve to someone else's GUID.
local harness = require("helpers.sync_harness")
local load = require("helpers.load")
local wow = require("helpers.wow_stub")

local REALM = harness.FOREVER_REALM
local sign, entriesText, helloText, inject, held =
  harness.sign, harness.entriesText, harness.helloText, harness.inject, harness.held

local function raise()
  error("hidden value touched")
end

local function hostileProxy()
  local u = newproxy(true)
  local mt = getmetatable(u)
  for _, ev in ipairs({ "__index", "__newindex", "__len", "__eq", "__lt", "__le",
    "__concat", "__tostring", "__call" }) do
    mt[ev] = raise
  end
  return u
end

local function stats(c)
  return c.client.stats
end

local function stored(c)
  return c.ledger:counts().foreign
end

-- Me (Ada Brook) grouped with `others` (names of new clients, or records), all started
-- after the group is set. Returns the world, me and the members (me first).
local function forever(others, raid)
  local w = harness.new({ forever = true })
  local me = w:add("Ada Brook", { start = false })
  local members = { me }
  for _, m in ipairs(others or { "Mira Vale" }) do
    members[#members + 1] = type(m) == "string" and w:add(m, { start = false }) or m
  end
  w:setGroup(members, raid)
  for _, m in ipairs(members) do
    if m.client then
      assert.is_true(m.client:start())
    end
  end
  return w, me, members
end

-- Whether a HELLO from `sender` on `channel` resolves for `me`.
local function resolves(me, sender, channel)
  local before = stats(me).dropped.unresolved or 0
  inject(me, "InnLedger", "H1:0:0", channel or "PARTY", sender)
  return (stats(me).dropped.unresolved or 0) == before
end

local function keys(map)
  local out = {}
  for key in pairs(map) do
    out[#out + 1] = key
  end
  table.sort(out)
  return out
end

-- Replaces UnitFullName for one unit; every other unit answers as before.
local function unitAnswers(c, unit, ...)
  local real, n, answer = c.impl.UnitFullName, select("#", ...), { ... }
  c.impl.UnitFullName = function(u)
    if u == unit then
      return unpack(answer, 1, n)
    end
    return real(u)
  end
end

describe("Sync.surname", function()
  local Sync

  before_each(function()
    local w = harness.new()
    Sync = w:add("Aldric", { start = false }).ns.Sync
  end)

  it("is the realm slot when it holds a one-word name that isn't our realm", function()
    assert.equal("Brook", Sync.surname("Brook", REALM))
    assert.equal(("S"):rep(48), Sync.surname(("S"):rep(48), REALM))
    assert.equal("Ünder", Sync.surname("Ünder", REALM))
  end)

  it("is nil for our realm, nothing, a realm-shaped or odd slot, or no realm to compare",
    function()
      for _, case in ipairs({
        { REALM, REALM }, { nil, REALM }, { "", REALM }, { "Area 52", "Area52" },
        { "Azjol-Nerub", "AzjolNerub" }, { "Two Words", REALM }, { "Tab\tbed", REALM },
        { ("S"):rep(49), REALM }, { 42, REALM }, { {}, REALM }, { true, REALM },
        { "Brook", nil }, { "Brook", "" }, { "Brook", 42 },
      }) do
        assert.is_nil(Sync.surname(case[1], case[2]), tostring(case[1]))
      end
    end)
end)

describe("Sync.ownName", function()
  local Sync

  before_each(function()
    local w = harness.new()
    Sync = w:add("Aldric", { start = false }).ns.Sync
  end)

  -- { name, second, realm } -> display name, form
  it("gives the display name and the name form from one reading", function()
    for label, case in pairs({
      forever = { { "Ada", "Brook", REALM }, "Ada Brook", true },
      retail = { { "Aldric", "Stubrealm", "Stubrealm" }, "Aldric", false },
      ["our realm in the slot"] = { { "Ada", REALM, REALM }, "Ada", false },
      ["a spaced realm in the slot"] = { { "Ada", "Classic Beta PvP", REALM }, "Ada", false },
      ["no slot"] = { { "Ada", nil, REALM }, "Ada", nil },
      ["an empty slot"] = { { "Ada", "", REALM }, "Ada", nil },
      ["a slot that isn't a string"] = { { "Ada", 42, REALM }, "Ada", nil },
      ["no realm"] = { { "Ada", "Brook", nil }, "Ada", nil },
      ["an empty realm"] = { { "Ada", "Brook", "" }, "Ada", nil },
      ["a realm that isn't a string"] = { { "Ada", "Brook", 42 }, "Ada", nil },
      ["a realm too long"] = { { "Ada", "Brook", ("R"):rep(49) }, "Ada", nil },
      ["no name, two-part"] = { { nil, "Brook", REALM }, nil, true },
      ["a name that isn't a string"] = { { 42, "Stubrealm", "Stubrealm" }, nil, false },
    }) do
      local name, form = Sync.ownName(case[1][1], case[1][2], case[1][3])
      assert.equal(case[2], name, label)
      assert.equal(case[3], form, label)
    end
  end)
end)

describe("Sync with two-part names: telling the client apart", function()
  it("logs the decision once, in our own words", function()
    for _, mode in ipairs({ { forever = true, word = "two-part", name = "Ada Brook" },
      { forever = false, word = "realm", name = "Aldric" } }) do
      local w = harness.new({ forever = mode.forever })
      local me = w:add(mode.name, { start = false })
      me.impl.GetNormalizedRealmName = function() return nil end
      assert.is_true(me.client:start())
      assert.same({ "sync: on" }, me.lines) -- undecided: no line
      me.impl.GetNormalizedRealmName = function() return w.realm end
      for _ = 1, 3 do
        me.client:twoPart()
        me.client:onEvent("GROUP_ROSTER_UPDATE")
      end
      assert.same({ "sync: on", "sync: names " .. mode.word }, me.lines)
    end
  end)

  it("decides at start, solo, when our unit can be read", function()
    local w = harness.new({ forever = true })
    local me = w:add("Ada Brook")
    assert.is_true(me.client.surnames)
    assert.same({ "sync: on", "sync: names two-part" }, me.lines)
  end)

  it("is two-part on Forever and not on retail, from our own player unit", function()
    local _, me = forever()
    assert.is_true(me.client:twoPart())
    assert.is_true(me.client.surnames)
    local w = harness.new()
    local aldric = w:add("Aldric")
    w:setGroup({ aldric, w:add("Mira") })
    aldric.client:onEvent("GROUP_ROSTER_UPDATE")
    assert.is_false(aldric.client:twoPart())
    assert.same({ "Aldric-Stubrealm", "Mira-Stubrealm" }, keys(aldric.client.group))
  end)

  it("waits to decide while our realm or our own realm slot can't be read", function()
    local w = harness.new({ forever = true })
    local me = w:add("Ada Brook", { start = false })
    local hiddenSlot = "Brook"
    local cases = {
      function() me.impl.GetNormalizedRealmName = function() return nil end end,
      function() me.impl.GetNormalizedRealmName = function() error("boom") end end,
      function() me.secret = function(v) return v == hiddenSlot end end,
      function() unitAnswers(me, "player", "Ada", nil) end,
      function() unitAnswers(me, "player", "Ada", "") end,
      function() unitAnswers(me, "player", "Ada", 42) end,
      function() unitAnswers(me, "player", "Ada", hostileProxy()) end,
      function() me.impl.UnitFullName = function() error("boom") end end,
    }
    local realImpl = {}
    for k, v in pairs(me.impl) do
      realImpl[k] = v
    end
    for i, setup in ipairs(cases) do
      setup()
      assert.is_false(me.client:twoPart(), i)
      assert.is_nil(me.client.surnames, i)
      for k, v in pairs(realImpl) do
        me.impl[k] = v
      end
      me.secret = nil
    end
    -- Readable again: decided, and kept.
    assert.is_true(me.client:twoPart())
    me.impl.GetNormalizedRealmName = function() return nil end
    assert.is_true(me.client:twoPart())
  end)

  it("stays a realm client when our realm slot holds our realm, spaced or not", function()
    for _, slot in ipairs({ "Stubrealm", "Stub realm", "Stub-realm" }) do
      local w = harness.new()
      local me = w:add("Aldric", { start = false })
      unitAnswers(me, "player", "Aldric", slot)
      assert.is_false(me.client:twoPart(), slot)
      assert.is_false(me.client.surnames, slot)
    end
  end)
end)

describe("Sync with two-part names: the group", function()
  it("resolves a party member's message to their GUID and stores the bare name", function()
    for _, raid in ipairs({ false, true }) do
      local w, me, members = forever({ "Mira Vale" }, raid)
      local mira = members[2]
      assert.same({ "Ada Brook", "Mira Vale" }, keys(me.client.group))
      sign(mira, 3)
      for _, text in ipairs(entriesText(mira)) do
        w:post(mira, raid and "RAID" or "PARTY", text)
      end
      w:deliver()
      local n, name = held(me, mira.guid)
      assert.equal(3, n)
      assert.equal("Mira Vale", name)
      assert.is_nil(stats(me).dropped.unresolved)
      assert.equal(1, stats(mira).dropped.self) -- her echo resolved to her own GUID
    end
  end)

  it("drops a sender who isn't in the group", function()
    local w, me, members = forever({ "Mira Vale" })
    local stranger = w:add("Bram Stone")
    sign(stranger, 3)
    for _, text in ipairs(entriesText(stranger)) do
      inject(me, "InnLedger", text, "PARTY", stranger.full)
    end
    assert.equal(1, stats(me).dropped.unresolved)
    assert.equal(0, stored(me))
    assert.is_true(resolves(me, members[2].full))
  end)

  it("syncs two Forever clients end to end, both ways", function()
    local w, me, members = forever({ "Mira Vale" })
    local mira = members[2]
    sign(me, 4)
    sign(mira, 5, 20)
    me.client:windowChanged()
    mira.client:windowChanged()
    w:advance(120)
    assert.same({ 5, "Mira Vale" }, { held(me, mira.guid) })
    assert.same({ 4, "Ada Brook" }, { held(mira, me.guid) })
    assert.is_nil(stats(me).dropped.unresolved)
    assert.is_nil(stats(mira).dropped.unresolved)
  end)

  it("never resolves a near miss, a case change, a first name alone or a dashed form",
    function()
      local _, me = forever({ "Mira Vale" })
      for _, sender in ipairs({ "Mira Val", "Mira Vales", "Mira", "Vale", "mira vale",
        "MIRA VALE", "Mira vale", "Mira-Vale", "Mira  Vale", "Mira Vale ", " Mira Vale",
        "Mira\tVale", "Mira Vale-Farshore", "Mira Vale-" .. REALM .. "-" .. REALM,
        "Mira Vale-classicbetapvp", "-" .. REALM, "Unknown" }) do
        assert.is_false(resolves(me, sender), sender)
      end
      assert.equal(0, stats(me).errors)
    end)

  it("tells apart two members with the same first name, or the same surname", function()
    local _, me, members = forever({ "Mira Vale", "Mira Stone", "Bram Vale" })
    assert.same({ "Ada Brook", "Bram Vale", "Mira Stone", "Mira Vale" },
      keys(me.client.group))
    for i = 2, 4 do
      sign(members[i], i)
      inject(me, "InnLedger", entriesText(members[i])[1], "PARTY", members[i].full)
      assert.same({ i, members[i].full }, { held(me, members[i].guid) })
    end
    assert.is_false(resolves(me, "Mira"))
  end)

  it("treats our own realm's suffix on a sender as the bare name", function()
    local _, me, members = forever({ "Mira Vale" })
    local mira = members[2]
    sign(mira, 2)
    inject(me, "InnLedger", entriesText(mira)[1], "PARTY", "Mira Vale-" .. REALM)
    assert.same({ 2, "Mira Vale" }, { held(me, mira.guid) })
  end)

  it("leaves out a name two units claim, until a scan finds it once", function()
    local w, me = forever({
      harness.twoPart("Mira Vale", "Player-1-0000B001"),
      harness.twoPart("Mira Vale", "Player-1-0000B002"),
    })
    assert.same({ "Ada Brook" }, keys(me.client.group))
    assert.is_false(resolves(me, "Mira Vale"))
    table.remove(w.group.members, 2)
    me.client:onEvent("GROUP_ROSTER_UPDATE")
    assert.equal("Player-1-0000B002", me.client.group["Mira Vale"])
  end)

  it("keys each form a unit's name may take as the sender form, and skips the rest",
    function()
      local _, me = forever({ "Mira Vale" })
      local cases = {
        { { "Mira", "Vale" }, "Mira Vale" },          -- as the player unit reads (beta)
        { { "Mira Vale", nil }, "Mira Vale" },        -- the whole name, no realm
        { { "Mira Vale", "" }, "Mira Vale" },
        { { "Mira Vale", REALM }, "Mira Vale" },      -- the whole name and our realm
        { { "Mira Vale", "Classic Beta PvP" }, "Mira Vale" },
        { { ("M"):rep(47), ("V"):rep(48) }, ("M"):rep(47) .. " " .. ("V"):rep(48) },
      }
      for _, case in ipairs(cases) do
        unitAnswers(me, "party1", case[1][1], case[1][2])
        me.client:onEvent("GROUP_ROSTER_UPDATE")
        assert.equal("Player-1-00000002", me.client.group[case[2]], case[2])
        assert.equal(2, #keys(me.client.group), case[2])
      end
      local hiddenSlot = "Veiled"
      me.secret = function(v) return v == hiddenSlot end
      for i, bad in ipairs({
        { "Mira Vale", "Farshore" },        -- two-part plus a slot that isn't our realm
        { "Mira", REALM }, { "Mira", nil }, { "Mira", "" }, -- one word, no surname
        { "Mira", "Va le" }, { "Mira", "Va-le" }, { "Mira", "Vale\t" },
        { "Mira", 42 }, { "Mira", {} }, { "Mira", hiddenSlot },
        { "Mira", hostileProxy() },
        { ("M"):rep(48), ("V"):rep(48) },   -- 97 bytes together
        { "Mira-Vale", nil }, { "Unknown", "Vale" }, { "Unknown", nil }, { "", "Vale" },
        { 42, "Vale" },
      }) do
        if type(bad[2]) == "userdata" then
          me.secret = function(v) return v == hiddenSlot or type(v) == "userdata" end
        end
        unitAnswers(me, "party1", bad[1], bad[2])
        me.client:onEvent("GROUP_ROSTER_UPDATE")
        assert.same({ "Ada Brook" }, keys(me.client.group), i)
      end
      assert.equal(0, stats(me).errors)
    end)

  it("never lets a one-word sender borrow a member whose unit drops the surname", function()
    -- If units ever read "Mira", <our realm> for Mira Vale, a member whose sender is
    -- "Mira" (unit not loaded yet) must not resolve to Mira Vale's GUID.
    local _, me, members = forever({ "Mira Vale",
      harness.twoPart("Mira", "Player-1-0000C001") })
    unitAnswers(me, "party1", "Mira", REALM)
    unitAnswers(me, "party2", "Unknown", nil)
    me.client:onEvent("GROUP_ROSTER_UPDATE")
    assert.same({ "Ada Brook" }, keys(me.client.group))
    assert.is_nil(me.client:resolve("PARTY", "Mira", harness.NOW))
    assert.is_false(resolves(me, "Mira"))
    assert.equal(0, (held(me, members[2].guid)))
  end)

  it("empties maps built before the client knew its names were two-part", function()
    local w = harness.new({ forever = true })
    local me = w:add("Ada Brook", { start = false })
    local mira = w:add("Mira Vale", { start = false })
    w:setGroup({ me, mira })
    w:setGuild({ me, mira })
    local readable = false
    me.impl.GetNormalizedRealmName = function() return readable and REALM or nil end
    assert.is_true(me.client:start())
    -- Undecided at start: the maps were built in the realm form.
    assert.is_nil(me.client.surnames)
    assert.same({ "Ada-Brook", "Mira-Vale" }, keys(me.client.group))
    assert.same({ "Ada Brook", "Mira Vale" }, keys(me.client.guild))
    readable = true
    assert.is_false(resolves(me, "Mira-Vale"))  -- decided now: the old keys are gone
    assert.is_true(me.client.surnames)
    assert.is_true(resolves(me, "Mira Vale"))   -- the miss rescanned in the new form
    assert.same({ "Ada Brook", "Mira Vale" }, keys(me.client.group))
    assert.same({}, keys(me.client.guild))      -- refilled at the next roster update
    local requests = me.calls.GuildRoster or 0
    assert.is_false(resolves(me, "Mira Vale", "GUILD")) -- a miss asks for the roster
    assert.equal(requests + 1, me.calls.GuildRoster)  -- at once: the gate was cleared
    me.client:onEvent("GUILD_ROSTER_UPDATE")
    w:advance(10) -- the trailing rebuild (one per 10 s; the last ran at start)
    assert.same({ "Ada Brook", "Mira Vale" }, keys(me.client.guild))
    assert.is_true(resolves(me, "Mira Vale", "GUILD"))
  end)

  it("resolves a member whose name hadn't loaded, once a rescan reads it", function()
    local w, me, members = forever({ "Mira Vale" })
    local mira = members[2]
    sign(mira, 3)
    unitAnswers(me, "party1", "Unknown", nil)
    me.client:onEvent("GROUP_ROSTER_UPDATE")
    assert.same({ "Ada Brook" }, keys(me.client.group))
    assert.is_false(resolves(me, "Unknown"))
    assert.is_false(resolves(me, "Mira Vale"))
    unitAnswers(me, "party1", "Mira", "Vale")
    w:advance(10)
    inject(me, "InnLedger", entriesText(mira)[1], "PARTY", "Mira Vale")
    assert.same({ 3, "Mira Vale" }, { held(me, mira.guid) })
  end)

  it("drops our own echo as self, quietly", function()
    local w, me = forever()
    sign(me, 1)
    me.lines = {}
    w:post(me, "PARTY", helloText(me))
    w:deliver()
    assert.equal(1, stats(me).dropped.self)
    assert.is_nil(stats(me).dropped.unresolved)
    assert.same({}, me.lines)
  end)

  it("never passes a peer string to a unit function", function()
    local w, me, members = forever({ "Mira Vale", "Target Dummy" })
    local asked = {}
    for _, fname in ipairs({ "UnitGUID", "UnitFullName", "UnitName" }) do
      local real = me.impl[fname]
      me.impl[fname] = function(unit, ...)
        asked[#asked + 1] = unit
        return real(unit, ...)
      end
    end
    sign(members[2], 2)
    for _, sender in ipairs({ "Mira Vale", "Target Dummy", "target", "Mira", "player",
      "party1", "Mira Vale-" .. REALM, "Stranger Danger" }) do
      inject(me, "InnLedger", entriesText(members[2])[1], "PARTY", sender)
      w:advance(11)
    end
    assert.is_true(#asked > 0)
    for _, unit in ipairs(asked) do
      assert.truthy(unit == "player" or unit:match("^party%d+$"), unit)
    end
    assert.equal(2, (held(me, members[2].guid)))
  end)
end)

describe("Sync with two-part names: the guild", function()
  -- A guild of me (Ada Brook) and `others`, its roster rows given as `names` (default:
  -- each member's bare name), the map built at start.
  local function guildOf(others, names)
    local w = harness.new({ forever = true })
    local me = w:add("Ada Brook", { start = false })
    local members = { me }
    for _, m in ipairs(others) do
      members[#members + 1] = type(m) == "string" and w:add(m, { start = false }) or m
    end
    w:setGuild(members)
    for i, name in pairs(names or {}) do
      w.guild.rows[i].name = name
    end
    assert.is_true(me.client:start())
    return w, me, members
  end

  it("resolves a roster name with or without our realm's suffix to the bare form", function()
    local _, me, members = guildOf({ "Mira Vale", "Bram Stone" },
      { [3] = "Bram Stone-" .. REALM })
    assert.same({ "Ada Brook", "Bram Stone", "Mira Vale" }, keys(me.client.guild))
    for i = 2, 3 do
      sign(members[i], i)
      inject(me, "InnLedger", entriesText(members[i])[1], "GUILD", members[i].full)
      assert.same({ i, members[i].full }, { held(me, members[i].guid) })
    end
  end)

  it("keeps another realm's suffix, so the bare sender doesn't match it", function()
    local _, me = guildOf({ "Mira Vale" }, { [2] = "Mira Vale-Farshore" })
    assert.same({ "Ada Brook", "Mira Vale-Farshore" }, keys(me.client.guild))
    assert.is_false(resolves(me, "Mira Vale", "GUILD"))
    assert.is_true(resolves(me, "Mira Vale-Farshore", "GUILD"))
  end)

  it("leaves out a name two rows claim, in either form", function()
    local _, me = guildOf({ harness.twoPart("Mira Vale", "Player-1-0000B001"),
      harness.twoPart("Mira Vale", "Player-1-0000B002") }, { [3] = "Mira Vale-" .. REALM })
    assert.same({ "Ada Brook" }, keys(me.client.guild))
    assert.is_false(resolves(me, "Mira Vale", "GUILD"))
  end)

  it("never resolves a near miss or a case change", function()
    local _, me = guildOf({ "Mira Vale" })
    for _, sender in ipairs({ "Mira Val", "mira vale", "Mira", "Mira-Vale", "Unknown" }) do
      assert.is_false(resolves(me, sender, "GUILD"), sender)
    end
  end)
end)

describe("ns.Sync:Start with two-part names (the real client)", function()
  local GUID = "Player-1-00000001" -- the stub's own GUID
  local MIRA = "Player-1-00000002"

  -- The stub in Forever mode, in a party with Mira Vale.
  local function login(partyName)
    local overrides = wow.foreverNames("Traveler", "Wayfarer")
    local names = overrides.UnitFullName
    overrides.IsInGroup = function() return true end
    overrides.GetNumGroupMembers = function() return 2 end
    overrides.UnitGUID = function(unit)
      if unit == "player" then return GUID end
      if unit == "party1" then return MIRA end
    end
    overrides.UnitFullName = function(unit)
      if unit == "party1" then return partyName[1], partyName[2] end
      return names(unit)
    end
    wow.install(overrides)
    local ns = load.addon({})
    wow.fire("ADDON_LOADED", load.ADDON_NAME)
    wow.fire("PLAYER_LOGIN")
    return ns
  end

  after_each(wow.uninstall)

  it("prints the decision line only while debug is on, and never a peer string", function()
    -- Our realm can't be read at login: undecided, so nothing to print yet.
    local realm = nil
    local overrides = wow.foreverNames("Traveler", "Wayfarer")
    overrides.GetNormalizedRealmName = function() return realm end
    overrides.IsInGroup = function() return true end
    overrides.GetNumGroupMembers = function() return 2 end
    overrides.UnitGUID = function(unit)
      if unit == "player" then return GUID end
      if unit == "party1" then return MIRA end
    end
    local names = overrides.UnitFullName
    overrides.UnitFullName = function(unit)
      if unit == "party1" then return "Mira", "Vale" end
      return names(unit)
    end
    wow.install(overrides)
    local ns = load.addon({})
    wow.fire("ADDON_LOADED", load.ADDON_NAME)
    wow.fire("PLAYER_LOGIN")
    assert.equal("undecided", ns.Sync:NameForm())
    wow.slash("/ledger debug")
    wow.chat = {}
    realm = "ClassicBetaPvP"
    wow.fire("GROUP_ROSTER_UPDATE")
    wow.fire("GROUP_ROSTER_UPDATE")
    assert.same({}, wow.errors)
    assert.equal("two-part", ns.Sync:NameForm())
    local found = 0
    for _, line in ipairs(wow.chat) do
      assert.is_nil(line:find("Mira", 1, true), line)
      assert.is_nil(line:find("Vale", 1, true), line)
      if line:find("sync: names", 1, true) then
        found = found + 1
        assert.equal("sync: names two-part", line:sub(-#"sync: names two-part"), line)
      end
    end
    assert.equal(1, found)

    -- Decided at login with debug off: nothing printed then, and the report says it.
    wow.uninstall()
    login({ "Mira", "Vale" })
    wow.slash("/ledger debug")
    for _, line in ipairs(wow.chat) do
      assert.is_nil(line:find("sync: names", 1, true), line)
    end
    assert.equal("; names two-part", wow.chat[#wow.chat]:sub(-#"; names two-part"))
  end)

  it("resolves a party member's bare two-part sender", function()
    local ns = login({ "Mira", "Vale" })
    assert.same({}, wow.errors)
    assert.equal("Traveler Wayfarer", ns.ledger.data.me.name)
    wow.fire("CHAT_MSG_ADDON", "InnLedger", "H1:0:0", "PARTY", "Mira Vale", "", 0, 0, "", 0)
    assert.equal(1, ns.Sync.stats.received.hello)
    assert.is_nil(ns.Sync.stats.dropped.unresolved)
    wow.fire("CHAT_MSG_ADDON", "InnLedger", "H1:0:0", "PARTY", "Mira", "", 0, 0, "", 0)
    wow.fire("CHAT_MSG_ADDON", "InnLedger", "H1:0:0", "PARTY", "Mira-Vale", "", 0, 0, "", 0)
    assert.equal(2, ns.Sync.stats.dropped.unresolved)
  end)
end)

-- Core's owner name and Sync's name form come from one read of our player unit
-- (Sync.readOwnName), so they can't disagree: "First Surname" exactly when two-part.
describe("Our own name: one read for Core and Sync", function()
  local hiddenSlot = newproxy(false)
  local function fixed(...)
    local n, answer = select("#", ...), { ... }
    return function(unit)
      if unit == "player" then return unpack(answer, 1, n) end
    end
  end
  local foreverNames = wow.foreverNames("Traveler", "Wayfarer")
  local CASES = {
    { "Forever", foreverNames, {}, "Traveler Wayfarer", "two-part" },
    { "retail", nil, {}, "Traveler", "realm" },
    { "a hidden slot", foreverNames, {
      UnitFullName = fixed("Traveler", hiddenSlot),
      issecretvalue = function(v) return rawequal(v, hiddenSlot) end,
    }, "Traveler", "undecided" },
    { "an unreadable realm", foreverNames, {
      GetNormalizedRealmName = function() error("boom") end,
    }, "Traveler", "undecided" },
    { "a hidden realm", foreverNames, {
      issecretvalue = function(v) return v == "ClassicBetaPvP" end,
    }, "Traveler", "undecided" },
    { "UnitFullName missing (Forever)", foreverNames, { UnitFullName = false },
      "Traveler Wayfarer", "two-part" },
    { "UnitFullName missing (retail)", nil, { UnitFullName = false },
      "Traveler", "undecided" },
    { "our realm in the slot", foreverNames, {
      UnitFullName = fixed("Traveler", "ClassicBetaPvP"),
    }, "Traveler", "realm" },
    { "UnitFullName and UnitName disagree", foreverNames, {
      UnitName = fixed("Traveler", "ClassicBetaPvP"),
    }, "Traveler Wayfarer", "two-part" },
  }

  after_each(wow.uninstall)

  it("gives the same answer for the owner name and the name form", function()
    for _, case in ipairs(CASES) do
      local label = case[1]
      wow.install(case[2])
      local ns = load.addon({})
      wow.fire("ADDON_LOADED", load.ADDON_NAME)
      for k, v in pairs(case[3]) do
        _G[k] = v
      end
      wow.fire("PLAYER_LOGIN")
      assert.same({}, wow.errors, label)
      local name, form = ns.ledger.data.me.name, ns.Sync:NameForm()
      assert.equal(case[4], name, label)
      assert.equal(case[5], form, label)
      assert.equal(form == "two-part", name:find(" ", 1, true) ~= nil, label)
      wow.uninstall()
    end
  end)
end)
