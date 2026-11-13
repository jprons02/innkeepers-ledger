-- InnNotes (pure): recognizing an innkeeper, the zone and continent from a map chain, the
-- note rule, observe, the saved record's read / add / record / list, and never throwing
-- (docs/specs/inn-notes.md 6.2). Loaded with Ledger and Collection in the strict pure
-- environment. Fixed times, never the clock. The saved record comes from SavedVariables,
-- which a player can edit, so every argument here is hostile.
local load = require("helpers.load")
local fx = require("helpers.places")

local T = fx.T

local function modules()
  local ns = {}
  load.file("Ledger.lua", ns, load.pure_env())
  load.file("Collection.lua", ns, load.pure_env())
  load.file("InnNotes.lua", ns, load.pure_env())
  return ns
end

local NS = modules()
local InnNotes, Ledger = NS.InnNotes, NS.Ledger
local LIMITS = Ledger.LIMITS
local ICON = 132052

-- The fixture inns: 5001 (a primary) and 5003 (its alias), among others.
local INNS = (fx.placesF0())

local function npcGUID(id)
  return "Creature-0-4615-2991-62-" .. id .. "-0000ABCDEF"
end

local function deepcopy(v)
  if type(v) ~= "table" then
    return v
  end
  local out = {}
  for k, x in next, v do
    out[deepcopy(k)] = deepcopy(x)
  end
  return out
end

-- A metatable whose every event raises: set on an argument, it shows nothing ran.
local function hostileMT()
  local mt = {}
  for _, ev in ipairs(fx.HOSTILE_EVENTS) do
    mt[ev] = function() error("metamethod ran") end
  end
  return mt
end

-- Every table reachable from v.
local function tablesOf(v, out)
  out = out or {}
  if type(v) == "table" and not out[v] then
    out[v] = true
    for k, x in next, v do
      tablesOf(k, out)
      tablesOf(x, out)
    end
  end
  return out
end

-- Live's chain at Lion's Pride Inn: Elwynn Forest -> Eastern Kingdoms -> Azeroth.
local function chain()
  return { { id = 1437, type = 3, parent = 1415 }, { id = 1415, type = 2, parent = 947 },
    { id = 947, type = 1, parent = 0 } }
end

local function situation(changes)
  local s = { npc = npcGUID(3934), now = T, icons = { 132053, ICON }, chain = chain(),
    faction = "Horde" }
  for k, v in pairs(changes or {}) do
    s[k] = v
  end
  return s
end

local function note(npc, t, extra)
  local n = { npc = npc, t = t, zone = 1437, continent = 1415 }
  for k, v in pairs(extra or {}) do
    n[k] = v
  end
  return n
end

-- Values to put in place of any argument (nil is tried separately).
local function oddValues()
  return { 7, 0 / 0, "x", true, fx.hostileTable(), fx.hostileProxy(),
    setmetatable({ 1, 2 }, hostileMT()) }
end

describe("InnNotes module", function()
  it("loads in the strict environment with its constants", function()
    assert.equal(1, InnNotes.VERSION)
    assert.equal(132052, InnNotes.BINDER_ICON)
    assert.same({ world = 1, continent = 2, zone = 3 }, InnNotes.MAP_TYPE)
    assert.same({ max = 200, readMax = 1000, optionsMax = 32, chainMax = 8 }, InnNotes.LIMITS)
  end)

  it("raises at load without Ledger or Collection (packaging bugs)", function()
    assert.has_error(function()
      load.file("InnNotes.lua", {}, load.pure_env())
    end)
    assert.has_error(function()
      local ns = {}
      load.file("Ledger.lua", ns, load.pure_env())
      load.file("InnNotes.lua", ns, load.pure_env())
    end)
  end)

  it("changing the exported LIMITS and MAP_TYPE changes nothing inside", function()
    local ns = modules()
    ns.InnNotes.LIMITS.max = 1
    ns.InnNotes.LIMITS.optionsMax = 1
    ns.InnNotes.LIMITS.chainMax = 1
    ns.InnNotes.MAP_TYPE.zone = 99
    ns.InnNotes.BINDER_ICON = 1
    assert.is_true(ns.InnNotes.isInnkeeper({ 1, 2, ICON }))
    assert.same({ 1437, 1415 }, { ns.InnNotes.place(chain()) })
    local _, items = ns.InnNotes.add({ note(1, T) }, note(2, T + 1))
    assert.equal(2, #items)
  end)
end)

describe("InnNotes.isInnkeeper", function()
  it("is true when any of the first 32 icons is exactly 132052", function()
    assert.is_true(InnNotes.isInnkeeper({ 132053, 132060, ICON }))
    assert.is_true(InnNotes.isInnkeeper({ ICON, 132053, 132060 }))
    assert.is_true(InnNotes.isInnkeeper({ 132053, ICON, 132060 }))
    assert.is_true(InnNotes.isInnkeeper({ ICON }))
    local icons = {}
    for i = 1, 31 do
      icons[i] = 132053
    end
    icons[32] = ICON
    assert.is_true(InnNotes.isInnkeeper(icons))
  end)

  it("is false for anything else", function()
    local at33 = {}
    for i = 1, 32 do
      at33[i] = 132053
    end
    at33[33] = ICON
    for i, icons in ipairs({
      {}, { 132053 }, { "132052" }, { 132052.5 }, { 132052.0001 }, { 0 / 0 }, { { ICON } },
      at33, { 132053, nil, ICON }, { [2] = ICON }, { icon = ICON },
      { fx.hostileProxy(), fx.hostileTable() },
    }) do
      assert.is_false(InnNotes.isInnkeeper(icons), "case " .. i)
    end
  end)

  it("is false for a non-table, a raising table or a stand-in, without throwing", function()
    for _, v in ipairs({ ICON, "132052", true, fx.hostileTable(), fx.hostileProxy() }) do
      assert.is_false(InnNotes.isInnkeeper(v))
    end
    assert.is_false(InnNotes.isInnkeeper(nil))
    -- Metamethods never run: an __index that would answer the icon isn't asked.
    local mt = hostileMT()
    assert.is_false(InnNotes.isInnkeeper(setmetatable({}, mt)))
    assert.is_true(InnNotes.isInnkeeper(setmetatable({ 1, ICON }, mt)))
  end)
end)

describe("InnNotes.place", function()
  local function place(c)
    return { InnNotes.place(c) }
  end

  it("finds the zone and the continent above it", function()
    assert.same({ 1437, 1415 }, place(chain()))
    -- Zephras Isle: no Continent map above the zone, so the World map is its continent.
    assert.same({ 2521, 947 }, place({ { id = 2521, type = 3, parent = 947 },
      { id = 947, type = 1, parent = 0 } }))
    -- A capital city is its own zone.
    assert.same({ 1453, 1415 }, place({ { id = 1453, type = 3, parent = 1415 },
      { id = 1415, type = 2, parent = 947 } }))
  end)

  it("skips Dungeon, Micro, Orphan and other maps below the zone", function()
    local c = chain()
    table.insert(c, 1, { id = 500, type = 5, parent = 501 })
    table.insert(c, 2, { id = 501, type = 4, parent = 1437 })
    table.insert(c, 3, { id = 502, type = 6, parent = 1437 })
    table.insert(c, 4, { id = 503, type = 7, parent = 1437 })
    assert.same({ 1437, 1415 }, place(c))
  end)

  it("gives the first zone and the continent above a second zone", function()
    assert.same({ 1437, 1415 }, place({ { id = 1437, type = 3 }, { id = 1438, type = 3 },
      { id = 1415, type = 2 } }))
  end)

  it("is nil without a zone below the continent", function()
    assert.same({}, place({ { id = 1415, type = 2 }, { id = 947, type = 1 } }))
    assert.same({}, place({ { id = 947, type = 1 }, { id = 1437, type = 3 } }))
    assert.same({}, place({ { id = 946, type = 0 }, { id = 1437, type = 3 } }))
    assert.same({}, place({ { id = 500, type = 5 }, { id = 501, type = 4 } }))
  end)

  it("is nil without a continent above the zone", function()
    assert.same({}, place({ { id = 1437, type = 3 } }))
    assert.same({}, place({ { id = 1437, type = 3 }, { id = 946, type = 0 },
      { id = 1415, type = 2 } }))
    assert.same({}, place({ { id = 1437, type = 3 }, { id = 1438, type = 3 } }))
  end)

  it("stops at a repeated id (a loop)", function()
    assert.same({}, place({ { id = 1437, type = 3 }, { id = 1437, type = 3 },
      { id = 1415, type = 2 } }))
    assert.same({}, place({ { id = 1437, type = 3 }, { id = 500, type = 5 },
      { id = 500, type = 5 }, { id = 1415, type = 2 } }))
    -- A repeat after the continent is found doesn't matter: the walk is done.
    assert.same({ 1437, 1415 }, place({ { id = 1437, type = 3 }, { id = 1415, type = 2 },
      { id = 1415, type = 2 } }))
  end)

  it("never gives a zone that is its own continent", function()
    -- Only a repeated id could do it, and a repeat stops the walk.
    assert.same({}, place({ { id = 1437, type = 3 }, { id = 1437, type = 2 } }))
  end)

  it("stops at an item with a bad id or type", function()
    for i, bad in ipairs({
      { id = 0, type = 2 }, { id = 1000000, type = 2 }, { id = 1.5, type = 2 },
      { id = 0 / 0, type = 2 }, { id = "1415", type = 2 }, { id = 1415 },
      { id = 1415, type = "2" }, { id = 1415, type = 2.5 }, { id = 1415, type = 1 / 0 },
      "x", 7, fx.hostileProxy(), setmetatable({}, { __index = { id = 1415, type = 2 } }),
    }) do
      local c = { { id = 1437, type = 3 }, bad, { id = 1415, type = 2 } }
      assert.same({}, place(c), "case " .. i)
    end
  end)

  it("reads only the first 8 items", function()
    local c = { { id = 1437, type = 3 } }
    for i = 2, 8 do
      c[i] = { id = 500 + i, type = 5 }
    end
    c[9] = { id = 1415, type = 2 }
    assert.same({}, place(c))
    c[8] = { id = 1415, type = 2 }
    assert.same({ 1437, 1415 }, place(c))
  end)

  it("is nil for an empty chain, a non-table or a stand-in, without throwing", function()
    for _, v in ipairs(oddValues()) do
      assert.same({}, place(v))
    end
    assert.same({}, place({}))
    assert.same({}, place(nil))
    assert.same({ 1437, 1415 }, place(setmetatable(chain(), hostileMT())))
  end)
end)

describe("InnNotes.validNote", function()
  it("accepts a full note and one without faction", function()
    assert.is_true(InnNotes.validNote(note(3934, T, { faction = "Horde" })))
    assert.is_true(InnNotes.validNote(note(3934, T, { faction = "Alliance" })))
    assert.is_true(InnNotes.validNote(note(3934, T)))
    assert.is_true(InnNotes.validNote({ npc = 1, t = LIMITS.tMin, zone = 1, continent = 999999 }))
    assert.is_true(InnNotes.validNote({ npc = 9999999, t = LIMITS.tMax, zone = 999999,
      continent = 1 }))
  end)

  it("refuses each key out of range, each wrong type, a missing or extra key", function()
    local cases = {
      { npc = 0 }, { npc = 10000000 }, { npc = 1.5 }, { npc = 0 / 0 }, { npc = 1 / 0 },
      { npc = "3934" }, { npc = false },
      { t = LIMITS.tMin - 1 }, { t = LIMITS.tMax + 1 }, { t = T + 0.5 }, { t = "1" },
      { zone = 0 }, { zone = 1000000 }, { zone = 1415 }, { zone = "1437" }, { zone = -1 },
      { continent = 0 }, { continent = 1000000 }, { continent = {} },
      { faction = "Neutral" }, { faction = "alliance" }, { faction = "" }, { faction = 1 },
      { faction = {} }, { extra = 1 }, { name = "Innkeeper Farley" }, { [1] = 1 },
    }
    for i, changes in ipairs(cases) do
      assert.is_false(InnNotes.validNote(note(3934, T, changes)), "case " .. i)
    end
    for _, key in ipairs({ "npc", "t", "zone", "continent" }) do
      local n = note(3934, T)
      n[key] = nil
      assert.is_false(InnNotes.validNote(n), key)
    end
  end)

  it("refuses non-tables and raising tables; never runs a metamethod", function()
    for _, v in ipairs(oddValues()) do
      assert.is_false(InnNotes.validNote(v))
    end
    assert.is_false(InnNotes.validNote(nil))
    assert.is_false(InnNotes.validNote(setmetatable({ npc = 3934, t = T, zone = 1437 },
      { __index = { continent = 1415 } })))
    assert.is_true(InnNotes.validNote(setmetatable(note(3934, T), hostileMT())))
  end)
end)

describe("InnNotes.observe", function()
  it("notes an unknown innkeeper: the note, faction kept for Alliance or Horde", function()
    local n, why = InnNotes.observe(situation(), INNS)
    assert.is_nil(why)
    assert.same({ npc = 3934, t = T, zone = 1437, continent = 1415, faction = "Horde" }, n)
    assert.is_true(InnNotes.validNote(n))
    assert.equal("Alliance", InnNotes.observe(situation({ faction = "Alliance" }), INNS).faction)
  end)

  it("leaves faction out for nil, an empty string, Neutral, a number or a stand-in", function()
    for _, f in ipairs({ false, "", "Neutral", "horde", 7, fx.hostileProxy() }) do
      local s = situation()
      s.faction = f or nil
      local n = InnNotes.observe(s, INNS)
      assert.same({ npc = 3934, t = T, zone = 1437, continent = 1415 }, n)
    end
  end)

  it("gives npc for a malformed, missing or hidden GUID", function()
    for _, g in ipairs({ false, "Player-1-00000001", "GameObject-0-1-2-3-3934-00AB", "",
      7, fx.hostileProxy(), fx.hostileTable() }) do
      local s = situation()
      s.npc = g or nil
      assert.same({ nil, "npc" }, { InnNotes.observe(s, INNS) })
    end
  end)

  it("gives known for a primary and an alias in the data, even with the binder icon", function()
    assert.same({ nil, "known" }, { InnNotes.observe(situation({ npc = npcGUID(5001) }), INNS) })
    assert.same({ nil, "known" }, { InnNotes.observe(situation({ npc = npcGUID(5003) }), INNS) })
  end)

  it("gives not_innkeeper without the binder icon", function()
    for _, icons in ipairs({ {}, { 132053 }, { "132052" }, "x" }) do
      assert.same({ nil, "not_innkeeper" },
        { InnNotes.observe(situation({ icons = icons }), INNS) })
    end
    local s = situation()
    s.icons = nil
    assert.same({ nil, "not_innkeeper" }, { InnNotes.observe(s, INNS) })
  end)

  it("gives clock for a missing, NaN, fractional or out-of-range time", function()
    for _, now in ipairs({ false, 0 / 0, T + 0.5, LIMITS.tMin - 1, LIMITS.tMax + 1, "1",
      fx.hostileProxy() }) do
      local s = situation()
      s.now = now or nil
      assert.same({ nil, "clock" }, { InnNotes.observe(s, INNS) })
    end
  end)

  it("gives place when the chain doesn't read", function()
    for _, c in ipairs({ {}, "x", { { id = 1415, type = 2 } }, { { id = 1437, type = 3 } } }) do
      assert.same({ nil, "place" }, { InnNotes.observe(situation({ chain = c }), INNS) })
    end
  end)

  it("checks in the spec's order: npc, known, not_innkeeper, clock, place", function()
    local bad = { npc = "x", icons = {}, now = 1, chain = {} }
    assert.same({ nil, "npc" }, { InnNotes.observe(situation(bad), INNS) })
    bad.npc = npcGUID(5001)
    assert.same({ nil, "known" }, { InnNotes.observe(situation(bad), INNS) })
    bad.npc = npcGUID(3934)
    assert.same({ nil, "not_innkeeper" }, { InnNotes.observe(situation(bad), INNS) })
    bad.icons = { ICON }
    assert.same({ nil, "clock" }, { InnNotes.observe(situation(bad), INNS) })
    bad.now = T
    assert.same({ nil, "place" }, { InnNotes.observe(situation(bad), INNS) })
  end)

  it("counts every creature as unknown when inns isn't a table", function()
    for _, inns in ipairs({ "x", 7, fx.hostileProxy() }) do
      local n = InnNotes.observe(situation({ npc = npcGUID(5001) }), inns)
      assert.equal(5001, n.npc)
    end
    assert.equal(5001, InnNotes.observe(situation({ npc = npcGUID(5001) }), nil).npc)
    -- A raising table is read raw: 5001 isn't a raw key, so it's unknown.
    assert.equal(5001, InnNotes.observe(situation({ npc = npcGUID(5001) }),
      fx.hostileTable()).npc)
  end)

  it("never throws, whatever it's given, and never runs a metamethod", function()
    for _, v in ipairs(oddValues()) do
      local n, why = InnNotes.observe(v, INNS)
      assert.is_nil(n)
      assert.is_string(why)
    end
    local s = setmetatable(situation(), hostileMT())
    assert.equal(3934, InnNotes.observe(s, setmetatable({}, hostileMT())).npc)
  end)
end)

describe("InnNotes.read", function()
  local function rec(items, v)
    return { v = v == nil and 1 or v, items = items }
  end

  it("reads nothing saved yet as empty and writable", function()
    assert.same({ items = {}, writable = true, dropped = 0 }, InnNotes.read(nil, INNS))
  end)

  it("never writes a damaged record (not a table)", function()
    for _, v in ipairs({ "x", 7, true, fx.hostileProxy() }) do
      assert.same({ items = {}, writable = false, dropped = 0 }, InnNotes.read(v, INNS))
    end
  end)

  it("reads, writes and exports nothing of a newer record (v above 1)", function()
    for _, v in ipairs({ 2, 99, 2 ^ 40 }) do
      assert.same({ items = {}, writable = false, dropped = 0 },
        InnNotes.read(rec({ note(3934, T) }, v), INNS))
    end
  end)

  it("reads a broken record (v missing, 0, a string, 1.5) as empty, writable, dropped 1",
    function()
      for _, v in ipairs({ false, 0, "1", 1.5, -1, 0 / 0, {} }) do
        local r = rec({ note(3934, T) }, v)
        if v == false then
          r.v = nil
        end
        assert.same({ items = {}, writable = true, dropped = 1 }, InnNotes.read(r, INNS))
      end
    end)

  it("drops and counts invalid items, keeping the valid ones", function()
    local items = { note(3934, T), note(0, T), "x", note(2352, T + 1, { faction = "Neutral" }),
      note(2353, T + 2, { extra = 1 }), fx.hostileTable(), fx.hostileProxy(),
      note(6929, T + 3, { faction = "Alliance" }) }
    local r = InnNotes.read(rec(items), INNS)
    assert.is_true(r.writable)
    assert.equal(6, r.dropped)
    assert.same({ note(3934, T), note(6929, T + 3, { faction = "Alliance" }) }, r.items)
  end)

  it("keeps the first note of a repeated npc, by index", function()
    local r = InnNotes.read(rec({ note(3934, T + 50), note(3934, T), note(2352, T + 10) }),
      INNS)
    assert.same({ note(2352, T + 10), note(3934, T + 50) }, r.items)
    assert.equal(1, r.dropped)
  end)

  it("drops notes for NPCs the data now knows (primaries and aliases): the prune", function()
    local r = InnNotes.read(rec({ note(5001, T), note(3934, T + 1), note(5003, T + 2) }), INNS)
    assert.same({ note(3934, T + 1) }, r.items)
    assert.equal(2, r.dropped)
  end)

  it("sorts by (t, npc)", function()
    local items = { note(30, T + 2), note(20, T + 1), note(40, T + 1), note(10, T + 3) }
    for seed = 1, 4 do
      local r = InnNotes.read(rec(fx.shuffled(items, seed)), INNS)
      assert.same({ note(20, T + 1), note(40, T + 1), note(30, T + 2), note(10, T + 3) },
        r.items)
      assert.equal(0, r.dropped)
    end
  end)

  it("keeps the 200 oldest of 250 valid notes", function()
    local items = {}
    for i = 1, 250 do
      items[i] = note(1000 + i, T + 250 - i)
    end
    local r = InnNotes.read(rec(items), INNS)
    assert.equal(200, #r.items)
    assert.equal(50, r.dropped)
    assert.same(note(1250, T), r.items[1])
    assert.same(note(1051, T + 199), r.items[200])
  end)

  it("reads at most 1 000 items and counts the unread rest as 1", function()
    local items = {}
    for i = 1, 1001 do
      items[i] = "x"
    end
    items[1000] = note(3934, T)
    local r = InnNotes.read(rec(items), INNS)
    assert.same({ note(3934, T) }, r.items)
    assert.equal(999 + 1, r.dropped)
    -- Exactly 1 000 items: nothing unread.
    items[1001] = nil
    assert.equal(999, InnNotes.read(rec(items), INNS).dropped)
  end)

  it("stops at a hole", function()
    local r = InnNotes.read(rec({ note(3934, T), nil, note(2352, T) }), INNS)
    assert.same({ note(3934, T) }, r.items)
    assert.equal(0, r.dropped)
  end)

  it("reads items that aren't a table as empty", function()
    for _, items in ipairs({ false, "x", 7 }) do
      assert.same({ items = {}, writable = true, dropped = 0 },
        InnNotes.read(rec(items or nil), INNS))
    end
  end)

  it("returns fresh copies with only the five keys, and never writes its input", function()
    local input = rec({ note(3934, T, { faction = "Horde" }), note(2352, T + 1) })
    local before = deepcopy(input)
    local r = InnNotes.read(input, INNS)
    assert.same(before, input)
    local inputs = tablesOf(input)
    for t in pairs(tablesOf(r)) do
      assert.is_nil(inputs[t])
    end
  end)

  it("never runs a metamethod of the record or its items", function()
    local mt = hostileMT()
    local items = setmetatable({ setmetatable(note(3934, T), mt),
      setmetatable(note(2352, T + 1), mt) }, mt)
    local r = InnNotes.read(setmetatable({ v = 1, items = items }, mt),
      setmetatable({}, mt))
    assert.same({ note(3934, T), note(2352, T + 1) }, r.items)
    -- A v behind __index isn't read: the record is broken.
    assert.same({ items = {}, writable = true, dropped = 1 },
      InnNotes.read(setmetatable({ items = {} }, { __index = { v = 1 } }), INNS))
  end)

  it("counts every NPC as unknown when inns isn't a table", function()
    local r = InnNotes.read(rec({ note(5001, T) }), "x")
    assert.same({ note(5001, T) }, r.items)
  end)
end)

describe("InnNotes.add", function()
  it("adds to an empty list", function()
    local res, items = InnNotes.add({}, note(3934, T))
    assert.equal("added", res)
    assert.same({ note(3934, T) }, items)
  end)

  it("keeps the first note of an npc: a later visit is a dup and changes nothing", function()
    local list = { note(3934, T) }
    local before = deepcopy(list)
    assert.same({ "dup" }, { InnNotes.add(list, note(3934, T + 100, { faction = "Horde" })) })
    assert.same(before, list)
  end)

  it("drops a new note at 200 (nothing is evicted), but a dup is still a dup", function()
    local list = {}
    for i = 1, 200 do
      list[i] = note(1000 + i, T + i)
    end
    assert.same({ "full" }, { InnNotes.add(list, note(3934, T)) })
    assert.same({ "dup" }, { InnNotes.add(list, note(1001, T)) })
    list[200] = nil
    local res, items = InnNotes.add(list, note(3934, T))
    assert.equal("added", res)
    assert.equal(200, #items)
  end)

  it("refuses an invalid note", function()
    for _, n in ipairs({ note(0, T), note(3934, T, { extra = 1 }), "x", fx.hostileProxy() }) do
      assert.same({ "invalid" }, { InnNotes.add({}, n) })
    end
    assert.same({ "invalid" }, { InnNotes.add({}, nil) })
  end)

  it("returns a new sorted array of copies; the input array is unchanged", function()
    local list = { note(20, T + 1), note(40, T + 3) }
    local before = deepcopy(list)
    local n = note(30, T + 2)
    local res, items = InnNotes.add(list, n)
    assert.equal("added", res)
    assert.same({ note(20, T + 1), n, note(40, T + 3) }, items)
    assert.same(before, list)
    assert.is_false(rawequal(items, list))
    for _, item in ipairs(items) do
      assert.is_false(rawequal(item, list[1]) or rawequal(item, list[2]) or rawequal(item, n))
    end
  end)

  it("leaves invalid items of its input out and treats a non-table input as empty", function()
    local res, items = InnNotes.add({ note(20, T), "x", note(0, T) }, note(30, T))
    assert.equal("added", res)
    assert.same({ note(20, T), note(30, T) }, items)
    for _, v in ipairs({ "x", 7, fx.hostileProxy() }) do
      assert.same({ "added", { note(30, T) } }, { InnNotes.add(v, note(30, T)) })
    end
  end)
end)

describe("InnNotes.record", function()
  it("is { v = 1, items = copies } and nothing else", function()
    local items = { note(20, T, { faction = "Horde" }), note(30, T + 1) }
    local r = InnNotes.record(items)
    assert.same({ v = 1, items = deepcopy(items) }, r)
    assert.is_false(rawequal(r.items, items))
    assert.is_false(rawequal(r.items[1], items[1]))
  end)

  it("leaves invalid and repeated items out, and holds at most 200", function()
    assert.same({ v = 1, items = { note(20, T) } },
      InnNotes.record({ note(20, T), "x", note(0, T), note(20, T + 5) }))
    local many = {}
    for i = 1, 250 do
      many[i] = note(1000 + i, T + i)
    end
    assert.equal(200, #InnNotes.record(many).items)
  end)

  it("is an empty record for a non-table, and nil only if reading raises", function()
    for _, v in ipairs({ "x", 7 }) do
      assert.same({ v = 1, items = {} }, InnNotes.record(v))
    end
    assert.same({ v = 1, items = {} }, InnNotes.record(nil))
    assert.same({ v = 1, items = {} }, InnNotes.record(fx.hostileProxy()))
  end)
end)

describe("InnNotes.list", function()
  it("equals read(rec, inns).items", function()
    local r = { v = 1, items = { note(5001, T), note(3934, T + 1), note(2352, T) } }
    assert.same(InnNotes.read(r, INNS).items, InnNotes.list(r, INNS))
    assert.same({ note(2352, T), note(3934, T + 1) }, InnNotes.list(r, INNS))
  end)

  it("is {} for a record that isn't readable", function()
    assert.same({}, InnNotes.list("x", INNS))
    assert.same({}, InnNotes.list({ v = 2, items = { note(3934, T) } }, INNS))
    assert.same({}, InnNotes.list(nil, INNS))
  end)
end)

describe("InnNotes reads its arguments raw", function()
  it("runs no metamethod of any argument or item (a counting metatable)", function()
    local calls = 0
    local mt = {}
    for _, ev in ipairs(fx.HOSTILE_EVENTS) do
      mt[ev] = function() calls = calls + 1 end
    end
    local function spied(t)
      return setmetatable(t, mt)
    end
    local function rec()
      return spied({ v = 1, items = spied({ spied(note(3934, T)), spied(note(2352, T + 1)),
        spied({ npc = 1 }), spied(note(5001, T)) }) })
    end
    local inns = spied({ [5001] = true })
    assert.is_true(InnNotes.isInnkeeper(spied({ 132053, ICON })))
    assert.is_false(InnNotes.isInnkeeper(spied({ 132053 })))
    local c = spied({ spied({ id = 1437, type = 3 }), spied({ id = 1415, type = 2 }) })
    assert.same({ 1437, 1415 }, { InnNotes.place(c) })
    assert.same({}, { InnNotes.place(spied({ spied({ id = 1437, type = 3 }) })) })
    assert.is_true(InnNotes.validNote(spied(note(3934, T))))
    assert.is_false(InnNotes.validNote(spied({ npc = 3934 })))
    local s = spied({ npc = npcGUID(3934), now = T, icons = spied({ ICON }), chain = c })
    assert.equal(3934, InnNotes.observe(s, inns).npc)
    assert.same({ nil, "known" }, { InnNotes.observe(spied({ npc = npcGUID(5001) }), inns) })
    assert.equal(2, #InnNotes.read(rec(), inns).items)
    assert.equal(2, #InnNotes.list(rec(), inns))
    assert.equal("added", (InnNotes.add(rec().items, spied(note(6929, T)))))
    assert.equal(3, #InnNotes.record(rec().items).items)
    assert.equal(0, calls)
  end)
end)

describe("InnNotes never throws", function()
  it("for every function with each argument replaced by an odd value", function()
    local good = {
      isInnkeeper = { { ICON } },
      place = { chain() },
      validNote = { note(3934, T) },
      observe = { situation(), INNS },
      read = { { v = 1, items = { note(3934, T) } }, INNS },
      add = { { note(1, T) }, note(2, T) },
      record = { { note(1, T) } },
      list = { { v = 1, items = { note(3934, T) } }, INNS },
    }
    for name, args in pairs(good) do
      local fn = InnNotes[name]
      for i = 1, #args do
        for _, v in ipairs(oddValues()) do
          local call = { unpack(args) }
          call[i] = v
          local ok, err = pcall(fn, unpack(call, 1, #args))
          assert(ok, name .. " threw: " .. tostring(err))
        end
        local call = { unpack(args) }
        call[i] = nil
        assert(pcall(fn, unpack(call, 1, #args)), name .. " threw on nil")
      end
    end
  end)

  it("gives its failure value when the inside raises", function()
    -- Only a sort with a broken comparison could raise inside; force one through a
    -- module copy whose table.sort raises.
    local env = load.pure_env()
    local sorts = setmetatable({ sort = function() error("boom") end }, { __index = table })
    rawset(env, "table", sorts)
    local ns = {}
    load.file("Ledger.lua", ns, load.pure_env())
    load.file("Collection.lua", ns, load.pure_env())
    load.file("InnNotes.lua", ns, env)
    local N2 = ns.InnNotes
    assert.same({ items = {}, writable = false, dropped = 0 },
      N2.read({ v = 1, items = { note(1, T) } }, INNS))
    assert.same({}, N2.list({ v = 1, items = { note(1, T) } }, INNS))
    assert.same({ "invalid" }, { N2.add({}, note(1, T)) })
    -- observe, place, record, isInnkeeper and validNote don't sort; they still answer.
    assert.equal(3934, N2.observe(situation(), INNS).npc)
  end)
end)
