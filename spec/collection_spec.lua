-- Collection: place record rules, progress by continent, zone and inn, and the hostile
-- own-entry cases (docs/specs/collection-cosmetics.md, sections 6.1, 6.2, 6.6 and 6.8).
-- Own entries come from SavedVariables, which a player can edit, so `own` is hostile here:
-- non-tables, metatables, holes, NaN and inf, huge arrays. Fixed times, never the clock.
local load = require("helpers.load")
local fx = require("helpers.places")

local T = fx.T

-- A fresh ns: Ledger, then (unless noData) Data/Inns, then Collection, as in the TOC.
-- `patch` may change Ledger before Collection reads it.
local function modules(opts)
  opts = opts or {}
  local ns = {}
  load.file("Ledger.lua", ns, load.pure_env())
  if opts.patch then
    opts.patch(ns.Ledger)
  end
  if not opts.noData then
    load.file("Data/Inns.lua", ns, load.pure_env())
  end
  load.file("Collection.lua", ns, load.pure_env())
  return ns
end

local NS = modules()
local Collection = NS.Collection
local LIMITS = NS.Ledger.LIMITS

local function atlasF()
  return Collection.bind(fx.places())
end

-- The spec 6.2 results for E (F is marked complete everywhere, spec 3.11).
local function allianceE()
  return {
    faction = "Alliance", signed = 4, total = 4, done = T + 400, unknown = 1, truncated = false,
    complete = true,
    byContinent = {
      [1] = { signed = 3, total = 3, done = T + 400, complete = true },
      [2] = { signed = 1, total = 1, done = T + 100, complete = true },
    },
    byZone = {
      [10] = { signed = 2, total = 2, continent = 1, done = T + 300, complete = true },
      [11] = { signed = 1, total = 1, continent = 1, done = T + 400, complete = true },
      [20] = { signed = 1, total = 1, continent = 2, done = T + 100, complete = true },
    },
    inns = {
      [5001] = { zone = 10, open = true, count = 3, first = T, last = T + 604800 },
      [5002] = { zone = 10, open = true, count = 1, first = T + 300, last = T + 300 },
      [5101] = { zone = 11, open = true, count = 1, first = T + 400, last = T + 400 },
      [5201] = { zone = 20, open = true, count = 1, first = T + 100, last = T + 100 },
      [5202] = { zone = 20, open = false, count = 0 },
      [5301] = { zone = 21, open = false, count = 0 },
    },
  }
end

local function hordeE()
  return {
    faction = "Horde", signed = 2, total = 4, unknown = 1, truncated = false, complete = true,
    byContinent = {
      [1] = { signed = 1, total = 1, done = T, complete = true },
      [2] = { signed = 1, total = 3, complete = true },
    },
    byZone = {
      [10] = { signed = 1, total = 1, continent = 1, done = T, complete = true },
      [20] = { signed = 1, total = 2, continent = 2, complete = true },
      [21] = { signed = 0, total = 1, continent = 2, complete = true },
    },
    inns = {
      [5001] = { zone = 10, open = true, count = 3, first = T, last = T + 604800 },
      [5002] = { zone = 10, open = false, count = 1, first = T + 300, last = T + 300 },
      [5101] = { zone = 11, open = false, count = 1, first = T + 400, last = T + 400 },
      [5201] = { zone = 20, open = true, count = 1, first = T + 100, last = T + 100 },
      [5202] = { zone = 20, open = true, count = 0 },
      [5301] = { zone = 21, open = true, count = 0 },
    },
  }
end

local function anyE()
  return {
    signed = 4, total = 6, unknown = 1, truncated = false, complete = true,
    byContinent = {
      [1] = { signed = 3, total = 3, done = T + 400, complete = true },
      [2] = { signed = 1, total = 3, complete = true },
    },
    byZone = {
      [10] = { signed = 2, total = 2, continent = 1, done = T + 300, complete = true },
      [11] = { signed = 1, total = 1, continent = 1, done = T + 400, complete = true },
      [20] = { signed = 1, total = 2, continent = 2, complete = true },
      [21] = { signed = 0, total = 1, continent = 2, complete = true },
    },
    inns = {
      [5001] = { zone = 10, open = true, count = 3, first = T, last = T + 604800 },
      [5002] = { zone = 10, open = true, count = 1, first = T + 300, last = T + 300 },
      [5101] = { zone = 11, open = true, count = 1, first = T + 400, last = T + 400 },
      [5201] = { zone = 20, open = true, count = 1, first = T + 100, last = T + 100 },
      [5202] = { zone = 20, open = true, count = 0 },
      [5301] = { zone = 21, open = true, count = 0 },
    },
  }
end

-- The result for no readable entries, Alliance, over F.
local function allianceEmpty()
  local r = allianceE()
  r.signed, r.done, r.unknown = 0, nil, 0
  r.byContinent[1] = { signed = 0, total = 3, complete = true }
  r.byContinent[2] = { signed = 0, total = 1, complete = true }
  r.byZone[10] = { signed = 0, total = 2, continent = 1, complete = true }
  r.byZone[11] = { signed = 0, total = 1, continent = 1, complete = true }
  r.byZone[20] = { signed = 0, total = 1, continent = 2, complete = true }
  for _, s in pairs(r.inns) do
    s.count, s.first, s.last = 0, nil, nil
  end
  return r
end

-- A result as it is when nothing is complete (no marks, or the #118 guard): every count
-- the same, no done anywhere, every complete false.
local function uncompleted(r)
  r.done, r.complete = nil, false
  for _, map in ipairs({ r.byZone, r.byContinent }) do
    for _, item in pairs(map) do
      item.done, item.complete = nil, false
    end
  end
  return r
end

-- ---------------------------------------------------------------------------

describe("Collection module", function()
  it("has the spec 3.8 constants", function()
    assert.same({ nameBytes = 48, mapKeyMax = 999999, ownMax = 100000 }, Collection.LIMITS)
    assert.same({ Alliance = true, Horde = true }, Collection.FACTIONS)
  end)

  it("changing the exported constants changes nothing inside", function()
    local ns = modules()
    ns.Collection.LIMITS.nameBytes = 1
    ns.Collection.LIMITS.ownMax = 1
    ns.Collection.FACTIONS.Neutral = true
    ns.Collection.FACTIONS.Alliance = nil
    local atlas = ns.Collection.bind(fx.places())
    assert.same({}, atlas.invalid)
    assert.same(allianceE(), atlas.progress(fx.entries(), "Alliance"))
    assert.same(anyE(), atlas.progress(fx.entries(), "Neutral"))
  end)

  it("reads innMax, tMin and tMax from Ledger.LIMITS, not second literals", function()
    local ns = modules({ patch = function(L)
      L.LIMITS.innMax = 5200
      L.LIMITS.tMin = T + 1
      L.LIMITS.tMax = T + 1000
    end })
    local atlas = ns.Collection.bind(fx.places())
    assert.same({ "inn 5201", "inn 5202", "inn 5301" }, atlas.invalid)
    local p = atlas.progress(fx.entries(), nil)
    -- e1 (T) and e7 (T + 604800) are outside the patched window; e6 is over innMax.
    assert.equal(0, p.unknown)
    assert.equal(1, p.inns[5001].count)
    assert.equal(T + 200, p.inns[5001].first)
    assert.equal(3, p.signed)
  end)

  it("exposes the default atlas's functions and invalid", function()
    assert.is_table(Collection.atlas)
    for _, name in ipairs({ "progress", "innOf", "inn", "zone", "continent", "zoneKeys",
      "complete" }) do
      assert.is_function(Collection[name], name)
      assert.equal(Collection.atlas[name], Collection[name])
    end
    assert.same({}, Collection.invalid)
    local zones = {}
    for key in pairs(NS.Data.Zones) do
      zones[#zones + 1] = key
    end
    table.sort(zones)
    assert.same(zones, Collection.zoneKeys())
  end)

  it("loads with no Data and binds an empty atlas", function()
    local ns = modules({ noData = true })
    assert.same({}, ns.Collection.invalid)
    assert.same({}, ns.Collection.zoneKeys())
    local p = ns.Collection.progress(fx.entries(), "Alliance")
    assert.equal(0, p.total)
    assert.equal(7, p.unknown)
  end)

  it("binds the default atlas with ns.Data.AtlasComplete (spec 3.11)", function()
    for _, case in ipairs({ { true, true }, { false, false }, { nil, false }, { 1, false } }) do
      local ns = {}
      load.file("Ledger.lua", ns, load.pure_env())
      local inns, zones, conts = fx.places()
      ns.Data = { Inns = inns, Zones = zones, Continents = conts, AtlasComplete = case[1] }
      load.file("Collection.lua", ns, load.pure_env())
      assert.equal(case[2], ns.Collection.complete())
      assert.equal(case[2], ns.Collection.progress(fx.entries(), "Alliance").done == T + 400)
    end
  end)

  it("loads with a non-table ns.Data and binds an empty atlas", function()
    local ns = {}
    load.file("Ledger.lua", ns, load.pure_env())
    ns.Data = "junk"
    load.file("Collection.lua", ns, load.pure_env())
    assert.same({}, ns.Collection.zoneKeys())
    assert.equal(0, ns.Collection.progress({}, nil).total)
  end)

  it("raises at load without Ledger (a packaging bug)", function()
    assert.has_error(function()
      load.file("Collection.lua", {}, load.pure_env())
    end)
  end)
end)

-- ---------------------------------------------------------------------------
-- 6.1 bind and the record rules.

describe("Collection.bind", function()
  it("binds F with nothing invalid and answers the lookups", function()
    local atlas = atlasF()
    assert.same({}, atlas.invalid)
    assert.equal(5001, atlas.innOf(5003))
    assert.equal(5001, atlas.innOf(5001))
    assert.equal(5301, atlas.innOf(5301))
    assert.is_nil(atlas.innOf(9999))
    assert.is_nil(atlas.inn(5003)) -- an alias
    assert.same({ name = "Hill Inn", zone = 10, faction = "Alliance" }, atlas.inn(5002))
    assert.same({ name = "Vale Inn", zone = 10 }, atlas.inn(5001))
    assert.same({ name = "Vale", continent = 1, seal = 101, complete = true }, atlas.zone(10))
    assert.same({ name = "Ridge", continent = 2, seal = 104, complete = true }, atlas.zone(21))
    assert.same({ name = "West", complete = true }, atlas.continent(2))
    assert.same({ 10, 11, 20, 21 }, atlas.zoneKeys())
    assert.is_true(atlas.complete())
    assert.is_nil(atlas.zone(12))
    assert.is_nil(atlas.continent(3))
  end)

  it("lookups return nil for any other argument, never throwing", function()
    local atlas = atlasF()
    for _, v in ipairs({ "5001", "10", 0 / 0, 1 / 0, -1, 0, 5001.5, 10.5, true, {},
      fx.hostileTable(), fx.hostileProxy(), function() end }) do
      for _, get in ipairs({ atlas.innOf, atlas.inn, atlas.zone, atlas.continent }) do
        local ok, res = pcall(get, v)
        assert.is_true(ok)
        assert.is_nil(res)
      end
    end
    assert.is_nil(atlas.innOf(nil))
    assert.is_nil(atlas.inn(nil))
  end)

  local INF = tostring(1 / 0)
  local function cont(name)
    return { name = name }
  end
  local function zone(name, continent, seal)
    return { name = name, continent = continent, seal = seal }
  end
  local function inn(name, z, faction)
    return { name = name, zone = z, faction = faction }
  end

  -- Each spec 3.2 rule broken once, on a record added to F: { label, change, invalid }.
  local BROKEN = {
    { "continent key 0", function(_, _, c) c[0] = cont("North") end, "continent 0" },
    { "continent key 1.5", function(_, _, c) c[1.5] = cont("North") end, "continent 1.5" },
    { "continent key \"1\"", function(_, _, c) c["1"] = cont("North") end, "continent <string>" },
    { "continent key 1000000", function(_, _, c) c[1000000] = cont("North") end,
      "continent 1000000" },
    { "continent key inf", function(_, _, c) c[1 / 0] = cont("North") end, "continent " .. INF },
    { "continent key true", function(_, _, c) c[true] = cont("North") end, "continent <boolean>" },
    { "a continent with an extra field", function(_, _, c)
      c[3] = { name = "North", seal = 105 }
    end, "continent 3" },
    { "a continent without a name", function(_, _, c) c[3] = {} end, "continent 3" },
    { "a continent that's a string", function(_, _, c) c[3] = "North" end, "continent 3" },
    { "a continent that's a number", function(_, _, c) c[3] = 7 end, "continent 3" },
    { "a zone with a missing continent", function(_, z) z[30] = zone("Glen", nil, 105) end,
      "zone 30" },
    { "a zone with an unknown continent", function(_, z) z[30] = zone("Glen", 3, 105) end,
      "zone 30" },
    { "a zone with continent \"1\"", function(_, z) z[30] = zone("Glen", "1", 105) end,
      "zone 30" },
    { "a zone with seal 100", function(_, z) z[30] = zone("Glen", 1, 100) end, "zone 30" },
    { "a zone with seal 1000", function(_, z) z[30] = zone("Glen", 1, 1000) end, "zone 30" },
    { "a zone with seal 0", function(_, z) z[30] = zone("Glen", 1, 0) end, "zone 30" },
    { "a zone with seal 1.5", function(_, z) z[30] = zone("Glen", 1, 1.5) end, "zone 30" },
    { "a zone with seal NaN", function(_, z) z[30] = zone("Glen", 1, 0 / 0) end, "zone 30" },
    { "a zone with seal \"105\"", function(_, z) z[30] = zone("Glen", 1, "105") end, "zone 30" },
    { "a zone with a missing seal", function(_, z) z[30] = zone("Glen", 1, nil) end, "zone 30" },
    { "a zone with an extra field", function(_, z)
      z[30] = { name = "Glen", continent = 1, seal = 105, faction = "Horde" }
    end, "zone 30" },
    { "zone key 0", function(_, z) z[0] = zone("Glen", 1, 105) end, "zone 0" },
    { "zone key 1000000", function(_, z) z[1000000] = zone("Glen", 1, 105) end, "zone 1000000" },
    { "zone key \"30\"", function(_, z) z["30"] = zone("Glen", 1, 105) end, "zone <string>" },
    { "a zone that's a string", function(_, z) z[30] = "Glen" end, "zone 30" },
    { "a zone that's a number", function(_, z) z[30] = 105 end, "zone 30" },
    { "inn key 0", function(i) i[0] = inn("Glen Inn", 10) end, "inn 0" },
    { "inn key 10000000", function(i) i[10000000] = inn("Glen Inn", 10) end, "inn 10000000" },
    { "inn key \"5001\"", function(i) i["5001"] = inn("Glen Inn", 10) end, "inn <string>" },
    { "inn key -1", function(i) i[-1] = inn("Glen Inn", 10) end, "inn -1" },
    { "inn key 5401.5", function(i) i[5401.5] = inn("Glen Inn", 10) end, "inn 5401.5" },
    { "an inn with an unknown zone", function(i) i[5401] = inn("Glen Inn", 99) end, "inn 5401" },
    { "an inn with a missing zone", function(i) i[5401] = inn("Glen Inn", nil) end, "inn 5401" },
    { "an inn with zone \"10\"", function(i) i[5401] = inn("Glen Inn", "10") end, "inn 5401" },
    { "an inn with faction \"Neutral\"", function(i)
      i[5401] = inn("Glen Inn", 10, "Neutral")
    end, "inn 5401" },
    { "an inn with faction \"alliance\"", function(i)
      i[5401] = inn("Glen Inn", 10, "alliance")
    end, "inn 5401" },
    { "an inn with faction 1", function(i) i[5401] = inn("Glen Inn", 10, 1) end, "inn 5401" },
    { "an inn with faction true", function(i) i[5401] = inn("Glen Inn", 10, true) end,
      "inn 5401" },
    { "an inn with an extra field", function(i)
      i[5401] = { name = "Glen Inn", zone = 10, continent = 1 }
    end, "inn 5401" },
    { "an inn that's a string", function(i) i[5401] = "Glen Inn" end, "inn 5401" },
    { "an inn that's a number", function(i) i[5401] = 10 end, "inn 5401" },
    { "an alias to a missing key", function(i) i[5401] = { alias = 5999 } end, "inn 5401" },
    { "an alias to an alias", function(i) i[5401] = { alias = 5003 } end, "inn 5401" },
    { "an alias to itself", function(i) i[5401] = { alias = 5401 } end, "inn 5401" },
    { "an alias to \"5001\"", function(i) i[5401] = { alias = "5001" } end, "inn 5401" },
    { "an alias to 5001.5", function(i) i[5401] = { alias = 5001.5 } end, "inn 5401" },
    { "an alias that's false", function(i) i[5401] = { alias = false } end, "inn 5401" },
    { "an alias with a name too", function(i)
      i[5401] = { alias = 5001, name = "Vale Inn" }
    end, "inn 5401" },
    { "an alias with a zone too", function(i) i[5401] = { alias = 5001, zone = 10 } end,
      "inn 5401" },
    { "an alias record that's a hostile table", function(i)
      i[5401] = fx.hostileTable()
    end, "inn 5401" },
  }

  for _, case in ipairs(BROKEN) do
    local name, change, label = case[1], case[2], case[3]
    it("excludes " .. name, function()
      local inns, zones, conts = fx.places()
      change(inns, zones, conts)
      local atlas = Collection.bind(inns, zones, conts, true)
      assert.same({ label }, atlas.invalid)
      -- The rest of F still binds, but nothing is complete (spec 3.11, #118).
      assert.same(uncompleted(allianceE()), atlas.progress(fx.entries(), "Alliance"))
      assert.is_false(atlas.complete())
      assert.same({ 10, 11, 20, 21 }, atlas.zoneKeys())
      assert.is_nil(atlas.inn(5401))
      assert.is_nil(atlas.innOf(5401))
      assert.is_nil(atlas.zone(30))
      assert.is_nil(atlas.continent(3))
    end)
  end

  -- Rule 5 on each kind of name: { label, name }.
  local BAD_NAMES = {
    { "|", "Glen|cff Inn" }, { "%", "Glen %s Inn" }, { "\\", "Glen \\n Inn" },
    { "\\0", "Glen\0Inn" }, { "a tab", "Glen\tInn" }, { "a newline", "Glen\nInn" },
    { "a UTF-8 byte", "Gl\195\169n Inn" }, { "byte 127", "Glen\127Inn" },
    { "! (not in the place allow-list)", "Glen Inn!" }, { "{", "Glen {w}" },
    { "a leading space", " Glen" }, { "a trailing space", "Glen " },
    { "a double space", "Glen  Inn" }, { "a lowercase first byte", "glen" },
    { "a digit first", "3 Glens" }, { "an apostrophe first", "'Glen" },
    { "49 bytes", "G" .. ("l"):rep(48) }, { "empty", "" }, { "a number", 5 },
    { "a table", {} }, { "true", true },
  }

  for _, case in ipairs(BAD_NAMES) do
    it("excludes a continent, a zone and an inn whose name has " .. case[1], function()
      for _, kind in ipairs({ "continent", "zone", "inn" }) do
        local inns, zones, conts = fx.places()
        if kind == "continent" then
          conts[3] = cont(case[2])
        elseif kind == "zone" then
          zones[30] = zone(case[2], 1, 105)
        else
          inns[5401] = inn(case[2], 10)
        end
        local atlas = Collection.bind(inns, zones, conts, true)
        local key = ({ continent = 3, zone = 30, inn = 5401 })[kind]
        assert.same({ kind .. " " .. key }, atlas.invalid)
      end
    end)
  end

  it("passes a 48-byte name, a 1-byte name and every allowed byte", function()
    local inns, zones, conts = fx.places()
    local n48 = "G" .. ("l"):rep(47)
    conts[3] = cont(n48)
    zones[30] = zone("A", 3, 105)
    inns[5401] = inn("Az09 ',.-azAZ Inn", 30, "Horde")
    inns[5402] = { alias = 5401 }
    local atlas = Collection.bind(inns, zones, conts, true)
    assert.same({}, atlas.invalid)
    assert.same({ name = n48, complete = false }, atlas.continent(3)) -- unmarked
    assert.same({ name = "A", continent = 3, seal = 105, complete = false }, atlas.zone(30))
    assert.same({ name = "Az09 ',.-azAZ Inn", zone = 30, faction = "Horde" }, atlas.inn(5401))
    assert.equal(5401, atlas.innOf(5402))
  end)

  it("two zones with seal 101 are both excluded, and their inns too", function()
    local inns, zones, conts = fx.places()
    zones[12] = zone("Glen", 1, 101)
    inns[5401] = inn("Glen Inn", 12)
    local atlas = Collection.bind(inns, zones, conts, true)
    assert.same({ "inn 5001", "inn 5002", "inn 5003", "inn 5401", "zone 10", "zone 12" },
      atlas.invalid)
    assert.same({ 11, 20, 21 }, atlas.zoneKeys())
    assert.is_nil(atlas.innOf(5003))
  end)

  it("a seal clash with an excluded zone record still excludes both (fail closed)", function()
    local inns, zones, conts = fx.places()
    zones[12] = zone("glen", 1, 104) -- a bad name, but its seal is 104 (Ridge's)
    local atlas = Collection.bind(inns, zones, conts, true)
    assert.same({ "inn 5301", "zone 12", "zone 21" }, atlas.invalid)
  end)

  it("an excluded continent cascades to its zones, their inns and aliases", function()
    local inns, zones, conts = fx.places()
    conts[1] = { name = "East", extra = true }
    local atlas = Collection.bind(inns, zones, conts, true)
    assert.same({ "continent 1", "inn 5001", "inn 5002", "inn 5003", "inn 5101", "zone 10",
      "zone 11" }, atlas.invalid)
    assert.same({ 20, 21 }, atlas.zoneKeys())
  end)

  -- #76: Zephras Isle (zone 2521) sits right under the Azeroth world map (947), with no
  -- Continent map between, so its group is the World map.
  local function withWorld()
    local inns, zones, conts = fx.places()
    conts[947] = { name = "Azeroth", complete = true }
    zones[2521] = { name = "Zephras Isle", continent = 947, seal = 105, complete = true }
    inns[251001] = inn("Zephras Inn", 2521)
    return inns, zones, conts, true
  end

  it("accepts a zone under a World map and counts its inns there (#76)", function()
    local atlas = Collection.bind(withWorld())
    assert.same({}, atlas.invalid)
    assert.same({ name = "Azeroth", complete = true }, atlas.continent(947))
    assert.same({ name = "Zephras Isle", continent = 947, seal = 105, complete = true },
      atlas.zone(2521))
    assert.equal(251001, atlas.innOf(251001))
    assert.same({ 10, 11, 20, 21, 2521 }, atlas.zoneKeys())

    local own = fx.entries()
    own[#own + 1] = { inn = 251001, t = T + 600, phrase = { 1 } }
    local p = atlas.progress(own, "Alliance")
    local want = allianceE()
    want.signed, want.total, want.done = 5, 5, T + 600
    want.byContinent[947] = { signed = 1, total = 1, done = T + 600, complete = true }
    want.byZone[2521] = { signed = 1, total = 1, continent = 947, done = T + 600, complete = true }
    want.inns[251001] = { zone = 2521, open = true, count = 1, first = T + 600, last = T + 600 }
    assert.same(want, p)

    -- Unsigned, it is one more open inn on its own group.
    p = atlas.progress(fx.entries(), "Horde")
    assert.same({ signed = 0, total = 1, complete = true }, p.byContinent[947])
    assert.same({ signed = 0, total = 1, continent = 947, complete = true }, p.byZone[2521])
    assert.equal(5, p.total)
  end)

  it("a World key reused as a zone key excludes both, and what hangs off them (#76)",
    function()
      local inns, zones, conts = withWorld()
      zones[947] = zone("Azeroth", 1, 106)
      local atlas = Collection.bind(inns, zones, conts, true)
      assert.same({ "continent 947", "inn 251001", "zone 2521", "zone 947" }, atlas.invalid)
      assert.is_nil(atlas.continent(947))
      assert.is_nil(atlas.zone(947))
      assert.same({ 10, 11, 20, 21 }, atlas.zoneKeys())
      assert.same(uncompleted(allianceE()), atlas.progress(fx.entries(), "Alliance"))
    end)

  it("a key in both tables excludes both even when one record is junk (fail closed)",
    function()
      local inns, zones, conts = fx.places()
      conts[10] = "junk" -- zone 10's key; zone 10 itself is good
      local atlas = Collection.bind(inns, zones, conts, true)
      assert.same({ "continent 10", "inn 5001", "inn 5002", "inn 5003", "zone 10" },
        atlas.invalid)
      inns, zones, conts = fx.places()
      zones[1] = 7 -- continent 1's key
      atlas = Collection.bind(inns, zones, conts, true)
      assert.same({ "continent 1", "inn 5001", "inn 5002", "inn 5003", "inn 5101", "zone 1",
        "zone 10", "zone 11" }, atlas.invalid)
    end)

  it("a zone whose chain loops back to itself is excluded (#76)", function()
    -- Its own continent, with no continent record: an unknown continent.
    local inns, zones, conts = fx.places()
    zones[30] = zone("Glen", 30, 105)
    inns[5401] = inn("Glen Inn", 30)
    local atlas = Collection.bind(inns, zones, conts, true)
    assert.same({ "inn 5401", "zone 30" }, atlas.invalid)
    -- Its own continent, with a continent record of that key: the key is in both tables.
    conts[30] = cont("Glen Lands")
    atlas = Collection.bind(inns, zones, conts, true)
    assert.same({ "continent 30", "inn 5401", "zone 30" }, atlas.invalid)
    -- Two zones that are each other's continent.
    inns, zones, conts = fx.places()
    zones[30], zones[31] = zone("Glen", 31, 105), zone("Fen", 30, 106)
    conts[30], conts[31] = cont("Glen Lands"), cont("Fen Lands")
    inns[5401] = inn("Glen Inn", 30)
    atlas = Collection.bind(inns, zones, conts, true)
    assert.same({ "continent 30", "continent 31", "inn 5401", "zone 30", "zone 31" },
      atlas.invalid)
    assert.same(uncompleted(allianceE()), atlas.progress(fx.entries(), "Alliance"))
  end)

  it("an alias to an excluded inn is excluded too", function()
    local inns, zones, conts = fx.places()
    inns[5401] = inn("Glen Inn", 99)
    inns[5402] = { alias = 5401 }
    local atlas = Collection.bind(inns, zones, conts, true)
    assert.same({ "inn 5401", "inn 5402" }, atlas.invalid)
  end)

  it("an entry at an excluded inn counts as unknown", function()
    local inns, zones, conts = fx.places()
    inns[5101].faction = "Neutral"
    local atlas = Collection.bind(inns, zones, conts, true)
    assert.same({ "inn 5101" }, atlas.invalid)
    local p = atlas.progress(fx.entries(), "Alliance")
    assert.is_nil(p.byZone[11]) -- the zone is kept but has no inn left
    assert.equal(2, p.unknown)
    assert.is_nil(p.inns[5101])
    assert.equal(3, p.total)
  end)

  for _, case in ipairs({
    { "bind()", {} },
    { "bind(\"x\", 7, true)", { "x", 7, true } },
    { "bind({}, {}, {})", { {}, {}, {} } },
    { "bind of three hostile tables", { fx.hostileTable(), fx.hostileTable(),
      fx.hostileTable() } },
    { "bind of three proxies", { fx.hostileProxy(), fx.hostileProxy(), fx.hostileProxy() } },
  }) do
    it(case[1] .. " gives an empty atlas, no error", function()
      local atlas = Collection.bind(unpack(case[2], 1, 3))
      assert.same({}, atlas.invalid)
      assert.same({}, atlas.zoneKeys())
      assert.is_nil(atlas.innOf(5001))
      assert.is_nil(atlas.inn(5001))
      assert.is_nil(atlas.zone(10))
      assert.is_nil(atlas.continent(1))
      assert.same({ faction = "Alliance", signed = 0, total = 0, byContinent = {}, byZone = {},
        inns = {}, unknown = 7, truncated = false, complete = false },
        atlas.progress(fx.entries(), "Alliance"))
      assert.is_false(atlas.complete())
    end)
  end

  it("data tables with metatables are read raw", function()
    local inns, zones, conts = fx.places()
    local calls = 0
    local function spy()
      calls = calls + 1
      return { name = "Ghost", zone = 10 }
    end
    setmetatable(inns, { __index = spy })
    setmetatable(zones, { __index = spy })
    setmetatable(conts, { __index = spy })
    setmetatable(inns[5001], { __index = function() calls = calls + 1 return "Horde" end })
    local atlas = Collection.bind(inns, zones, conts, true)
    assert.same({}, atlas.invalid)
    assert.is_nil(atlas.inn(5999))
    assert.same({ name = "Vale Inn", zone = 10 }, atlas.inn(5001))
    assert.equal(0, calls)
  end)

  it("copies: changing F after bind changes no later result", function()
    local inns, zones, conts = fx.places()
    local atlas = Collection.bind(inns, zones, conts, true)
    inns[5001].name = "Changed"
    inns[5001].faction = "Horde"
    inns[5003].alias = 5002
    inns[5999] = inn("New Inn", 10)
    zones[10].seal = 199
    zones[30] = zone("Glen", 1, 105)
    zones[11].complete = nil
    conts[1].name = "Changed"
    conts[2].complete = false
    inns[5101] = nil
    assert.same({ name = "Vale Inn", zone = 10 }, atlas.inn(5001))
    assert.equal(5001, atlas.innOf(5003))
    assert.is_nil(atlas.innOf(5999))
    assert.same({ name = "Vale", continent = 1, seal = 101, complete = true }, atlas.zone(10))
    assert.same({ name = "East", complete = true }, atlas.continent(1))
    assert.is_true(atlas.complete())
    assert.same({ 10, 11, 20, 21 }, atlas.zoneKeys())
    assert.same(allianceE(), atlas.progress(fx.entries(), "Alliance"))
  end)

  it("copies: changing a returned table changes no later result", function()
    local atlas = atlasF()
    local i, z, c, keys = atlas.inn(5002), atlas.zone(10), atlas.continent(1), atlas.zoneKeys()
    i.faction, i.zone = "Horde", 11
    z.seal, z.continent, z.complete = 1, 2, false
    c.name, c.complete = "X", false
    keys[1], keys[5] = 99, 100
    local p = atlas.progress(fx.entries(), "Alliance")
    p.signed, p.inns[5001].count, p.byZone[10].total, p.byContinent[1] = 0, 0, 9, nil
    p.byZone[11].complete, p.complete = false, false
    assert.same({ name = "Hill Inn", zone = 10, faction = "Alliance" }, atlas.inn(5002))
    assert.same({ name = "Vale", continent = 1, seal = 101, complete = true }, atlas.zone(10))
    assert.same({ name = "East", complete = true }, atlas.continent(1))
    assert.same({ 10, 11, 20, 21 }, atlas.zoneKeys())
    assert.same(allianceE(), atlas.progress(fx.entries(), "Alliance"))
  end)
end)

-- ---------------------------------------------------------------------------
-- 6.2 progress.

describe("Collection progress", function()
  local atlas = atlasF()

  it("Alliance, E: the spec 6.2 values", function()
    assert.same(allianceE(), atlas.progress(fx.entries(), "Alliance"))
  end)

  it("Horde, E: only the neutral inns and Horde's count; a signed closed inn counts nowhere",
    function()
      local p = atlas.progress(fx.entries(), "Horde")
      assert.same(hordeE(), p)
      assert.is_false(p.inns[5002].open)
      assert.equal(1, p.inns[5002].count)
      assert.is_nil(p.byZone[11])
    end)

  for _, case in ipairs({
    { "nil", function() return nil end },
    { "\"Neutral\"", function() return "Neutral" end },
    { "\"alliance\"", function() return "alliance" end },
    { "\"\"", function() return "" end },
    { "1", function() return 1 end },
    { "{}", function() return {} end },
    { "a table with Alliance's __eq", function()
      return setmetatable({}, { __eq = function() return true end })
    end },
    { "the hostile table stand-in", fx.hostileTable },
    { "the newproxy stand-in", fx.hostileProxy },
  }) do
    it("faction " .. case[1] .. " counts every inn open", function()
      local p = atlas.progress(fx.entries(), case[2]())
      assert.same(anyE(), p)
      assert.is_nil(p.faction)
      assert.same({ signed = 1, total = 2, continent = 2, complete = true }, p.byZone[20])
    end)
  end

  it("empty data: nothing to count, every entry unknown", function()
    local p = Collection.bind({}, {}, {}).progress(fx.entries(), "Alliance")
    assert.same({ faction = "Alliance", signed = 0, total = 0, byContinent = {}, byZone = {},
      inns = {}, unknown = 7, truncated = false, complete = false }, p)
    assert.is_nil(p.done)
    -- Marked complete, an empty atlas still has no done: nothing to sign (total 0).
    p = Collection.bind({}, {}, {}, true).progress(fx.entries(), "Alliance")
    assert.is_true(p.complete)
    assert.is_nil(p.done)
  end)

  it("an inn removed from the data after you signed it counts as unknown", function()
    local inns, zones, conts = fx.places()
    inns[5101] = nil
    local p = Collection.bind(inns, zones, conts, true).progress(fx.entries(), "Alliance")
    assert.equal(3, p.total)
    assert.equal(3, p.signed)
    assert.equal(2, p.unknown)
    assert.is_nil(p.byZone[11])
    assert.is_nil(p.inns[5101])
    assert.equal(T + 300, p.done)
    assert.same({ signed = 2, total = 2, done = T + 300, complete = true }, p.byContinent[1])
  end)

  it("repeat signatures of one inn count once in signed, three times in count", function()
    local p = atlas.progress(fx.entries(), "Alliance")
    assert.equal(3, p.inns[5001].count)
    assert.equal(4, p.signed)
    assert.equal(T, p.inns[5001].first)
    assert.equal(T + 604800, p.inns[5001].last)
    -- Three signatures of 5001 alone: one stamp.
    local E = fx.entries()
    p = atlas.progress({ E[1], E[3], E[7] }, "Alliance")
    assert.equal(1, p.signed)
    assert.equal(3, p.inns[5001].count)
  end)

  it("an alias alone signs its primary", function()
    local p = atlas.progress({ fx.entries()[3] }, "Alliance")
    assert.same({ zone = 10, open = true, count = 1, first = T + 200, last = T + 200 },
      p.inns[5001])
    assert.equal(1, p.signed)
    assert.is_nil(p.inns[5003])
  end)

  it("order doesn't matter: E reversed and shuffled give deep-equal results", function()
    for _, faction in ipairs({ "Alliance", "Horde", false }) do
      local f = faction or nil
      local want = atlas.progress(fx.entries(), f)
      assert.same(want, atlas.progress(fx.reversed(fx.entries()), f))
      for seed = 1, 20 do
        assert.same(want, atlas.progress(fx.shuffled(fx.entries(), seed * 7919), f))
      end
    end
  end)

  it("first and last are by comparison, not input order", function()
    local E = fx.entries()
    local p = atlas.progress({ E[7], E[3], E[1] }, "Alliance")
    assert.equal(T, p.inns[5001].first)
    assert.equal(T + 604800, p.inns[5001].last)
  end)

  describe("hostile own", function()
    for _, case in ipairs({
      { "nil", function() return nil end },
      { "\"x\"", function() return "x" end },
      { "7", function() return 7 end },
      { "true", function() return true end },
      { "a function", function() return function() end end },
      { "the hostile table stand-in", fx.hostileTable },
      { "the newproxy stand-in", fx.hostileProxy },
      { "{}", function() return {} end },
    }) do
      it(case[1] .. " gives the empty-ledger result", function()
        local ok, p = pcall(atlas.progress, case[2](), "Alliance")
        assert.is_true(ok)
        assert.same(allianceEmpty(), p)
      end)
    end

    local E1 = fx.entries()[1]
    local BAD = {
      { "a string item", "5001" },
      { "a number item", 5001 },
      { "true", true },
      { "inn NaN", { inn = 0 / 0, t = T + 1, phrase = { 1 } } },
      { "inn inf", { inn = 1 / 0, t = T + 1, phrase = { 1 } } },
      { "inn 1.5", { inn = 1.5, t = T + 1, phrase = { 1 } } },
      { "inn 5001.5", { inn = 5001.5, t = T + 1, phrase = { 1 } } },
      { "inn \"5001\"", { inn = "5001", t = T + 1, phrase = { 1 } } },
      { "inn 0", { inn = 0, t = T + 1, phrase = { 1 } } },
      { "inn 10000000", { inn = 10000000, t = T + 1, phrase = { 1 } } },
      { "inn missing", { t = T + 1, phrase = { 1 } } },
      { "t tMin - 1", { inn = 5002, t = LIMITS.tMin - 1, phrase = { 1 } } },
      { "t tMax + 1", { inn = 5002, t = LIMITS.tMax + 1, phrase = { 1 } } },
      { "t NaN", { inn = 5002, t = 0 / 0, phrase = { 1 } } },
      { "t 1.5 past T", { inn = 5002, t = T + 1.5, phrase = { 1 } } },
      { "t \"T\"", { inn = 5002, t = tostring(T), phrase = { 1 } } },
      { "t missing", { inn = 5002, phrase = { 1 } } },
      { "an entry with a raising metatable", fx.hostileTable() },
      { "an entry whose __index answers", setmetatable({}, { __index = function(_, k)
        return k == "inn" and 5002 or T + 1
      end }) },
      { "a newproxy entry", fx.hostileProxy() },
    }

    for _, case in ipairs(BAD) do
      it("skips " .. case[1] .. " without counting it unknown", function()
        local own = { case[2], E1 }
        local before = fx.snapshot(own)
        local ok, p = pcall(atlas.progress, own, "Alliance")
        assert.is_true(ok)
        assert.same(atlas.progress({ E1 }, "Alliance"), p)
        assert.equal(0, p.unknown)
        assert.is_true(fx.sameSnapshot(before, fx.snapshot(own)))
      end)
    end

    it("a hole stops the read", function()
      local E = fx.entries()
      local p = atlas.progress({ E[1], nil, E[2] }, "Alliance")
      assert.same(atlas.progress({ E[1] }, "Alliance"), p)
      assert.equal(1, p.signed)
    end)

    it("never calls a metamethod of own (spy)", function()
      local calls = 0
      local function spy()
        calls = calls + 1
        return fx.entries()[2]
      end
      local own = setmetatable(fx.entries(), { __index = spy, __len = spy, __newindex = spy })
      local p = atlas.progress(own, "Alliance")
      assert.same(allianceE(), p)
      assert.equal(0, calls)
    end)

    it("own is unchanged after the call", function()
      local own = fx.entries()
      own[4].extra = "x"
      setmetatable(own[5], { __newindex = function() error("written") end })
      local before = fx.snapshot(own, 4)
      atlas.progress(own, "Alliance")
      atlas.progress(own, nil)
      assert.is_true(fx.sameSnapshot(before, fx.snapshot(own, 4)))
    end)
  end)

  it("reads at most 100 000 entries: 100 001 gives truncated and counts the first 100 000",
    function()
      local own = {}
      for i = 1, 100001 do
        own[i] = { inn = 5001, t = T + i }
      end
      local p = atlas.progress(own, "Alliance")
      assert.is_true(p.truncated)
      assert.equal(100000, p.inns[5001].count)
      assert.equal(T + 100000, p.inns[5001].last)
      own[100001] = nil
      p = atlas.progress(own, "Alliance")
      assert.is_false(p.truncated)
      assert.equal(100000, p.inns[5001].count)
    end)

  it("never writes to its arguments", function()
    local own = fx.entries()
    local faction = { "Alliance" }
    local before, beforeF = fx.snapshot(own), fx.snapshot(faction)
    atlas.progress(own, faction)
    atlas.progress(own, "Horde")
    assert.is_true(fx.sameSnapshot(before, fx.snapshot(own)))
    assert.is_true(fx.sameSnapshot(beforeF, fx.snapshot(faction)))
  end)

  it("returns a new table each call", function()
    local a = atlas.progress(fx.entries(), "Alliance")
    local b = atlas.progress(fx.entries(), "Alliance")
    assert.are_not.equal(a, b)
    assert.are_not.equal(a.inns, b.inns)
    assert.are_not.equal(a.byZone[10], b.byZone[10])
  end)
end)

-- ---------------------------------------------------------------------------
-- 3.11 Completeness marks: `done` only for places the data marks complete.

describe("Collection completeness marks", function()
  -- allianceE() as F0 gives it: every count the same, no done, every complete false.
  local function allianceF0()
    return uncompleted(allianceE())
  end

  it("F0 (no marks): no done anywhere, every complete false", function()
    local atlas = Collection.bind(fx.placesF0())
    assert.same({}, atlas.invalid)
    assert.same(allianceF0(), atlas.progress(fx.entries(), "Alliance"))
    for _, faction in ipairs({ "Horde", false }) do
      local p = atlas.progress(fx.entries(), faction or nil)
      assert.is_nil(p.done)
      assert.is_false(p.complete)
      for _, map in ipairs({ p.byZone, p.byContinent }) do
        for _, item in pairs(map) do
          assert.is_nil(item.done)
          assert.is_false(item.complete)
        end
      end
    end
    assert.same({ name = "Vale", continent = 1, seal = 101, complete = false }, atlas.zone(10))
    assert.same({ name = "East", complete = false }, atlas.continent(1))
    assert.is_false(atlas.complete())
  end)

  it("F0 with atlasComplete true but no continent marked: not complete", function()
    local inns, zones, conts = fx.placesF0()
    local atlas = Collection.bind(inns, zones, conts, true)
    assert.is_false(atlas.complete())
    assert.same(allianceF0(), atlas.progress(fx.entries(), "Alliance"))
  end)

  it("one zone marked (Vale): its done returns, nothing else", function()
    local inns, zones, conts = fx.placesF0()
    zones[10].complete = true
    local atlas = Collection.bind(inns, zones, conts)
    local want = allianceF0()
    want.byZone[10].done, want.byZone[10].complete = T + 300, true
    assert.same(want, atlas.progress(fx.entries(), "Alliance"))
    assert.is_true(atlas.zone(10).complete)
    assert.is_false(atlas.continent(1).complete)
  end)

  it("a marked continent over an unmarked zone is not complete", function()
    local inns, zones, conts = fx.placesF0()
    conts[1].complete = true
    zones[10].complete = true -- Marsh (11) stays unmarked
    local atlas = Collection.bind(inns, zones, conts)
    assert.same({}, atlas.invalid)
    assert.same({ name = "East", complete = false }, atlas.continent(1))
    local p = atlas.progress(fx.entries(), "Alliance")
    assert.same({ signed = 3, total = 3, complete = false }, p.byContinent[1])
    assert.is_nil(p.byZone[11].done)
  end)

  it("a continent and all its zones marked: complete, with its done", function()
    local inns, zones, conts = fx.placesF0()
    conts[1].complete, zones[10].complete, zones[11].complete = true, true, true
    local atlas = Collection.bind(inns, zones, conts)
    assert.is_true(atlas.continent(1).complete)
    local p = atlas.progress(fx.entries(), "Alliance")
    assert.same({ signed = 3, total = 3, done = T + 400, complete = true }, p.byContinent[1])
    assert.same({ signed = 1, total = 1, complete = false }, p.byContinent[2])
    assert.is_false(p.complete)
    assert.is_nil(p.done)
  end)

  it("atlasComplete without every continent complete: no overall done", function()
    local inns, zones, conts = fx.places()
    zones[21].complete = nil -- West has an unmarked zone (Horde's)
    local atlas = Collection.bind(inns, zones, conts, true)
    assert.is_false(atlas.complete())
    assert.is_false(atlas.continent(2).complete)
    local p = atlas.progress(fx.entries(), "Alliance")
    assert.is_false(p.complete)
    assert.is_nil(p.done) -- Alliance signed every inn open to it
    assert.equal(p.total, p.signed)
    assert.is_nil(p.byContinent[2].done)
    assert.equal(T + 100, p.byZone[20].done)
  end)

  it("every mark and atlasComplete true: the F result", function()
    assert.is_true(atlasF().complete())
    assert.same(allianceE(), atlasF().progress(fx.entries(), "Alliance"))
    -- Without the fourth argument, every place is complete but the atlas isn't.
    local inns, zones, conts = fx.places()
    local p = Collection.bind(inns, zones, conts).progress(fx.entries(), "Alliance")
    local want = allianceE()
    want.done, want.complete = nil, false
    assert.same(want, p)
  end)

  -- Any complete value but true excludes the record (fail closed).
  local BAD_MARKS = {
    { "false", function() return false end },
    { "1", function() return 1 end },
    { "\"true\"", function() return "true" end },
    { "\"yes\"", function() return "yes" end },
    { "a table", function() return {} end },
    { "a table whose __eq says true", function()
      return setmetatable({}, { __eq = function() return true end })
    end },
    { "the hostile table stand-in", fx.hostileTable },
    { "the newproxy stand-in", fx.hostileProxy },
  }

  for _, case in ipairs(BAD_MARKS) do
    it("a zone with complete = " .. case[1] .. " is excluded and named", function()
      local inns, zones, conts = fx.places()
      zones[11].complete = case[2]()
      local atlas
      assert.has_no.errors(function()
        atlas = Collection.bind(inns, zones, conts, true)
      end)
      assert.same({ "inn 5101", "zone 11" }, atlas.invalid)
      assert.is_nil(atlas.zone(11))
      -- An exclusion makes nothing complete (#118), though East's other zone is marked.
      assert.is_false(atlas.zone(10).complete)
      assert.is_false(atlas.continent(1).complete)
      assert.is_false(atlas.complete())
    end)

    it("a continent with complete = " .. case[1] .. " is excluded, and it cascades",
      function()
        local inns, zones, conts = fx.places()
        conts[2].complete = case[2]()
        local atlas = Collection.bind(inns, zones, conts, true)
        assert.same({ "continent 2", "inn 5201", "inn 5202", "inn 5301", "zone 20", "zone 21" },
          atlas.invalid)
        assert.is_nil(atlas.continent(2))
        assert.same({ 10, 11 }, atlas.zoneKeys())
        -- An exclusion makes nothing complete (#118), though East is marked in full.
        assert.is_false(atlas.continent(1).complete)
        assert.is_false(atlas.complete())
      end)
  end

  -- #118: on F (all marked), one excluded record of any kind makes nothing complete.
  for _, case in ipairs(fx.excludedCases()) do
    it("fails closed on " .. case.label .. ": nothing complete, no done (#118)", function()
      local inns, zones, conts = fx.places()
      case.change(inns, zones, conts)
      local atlas
      assert.has_no.errors(function()
        atlas = Collection.bind(inns, zones, conts, true)
      end)
      assert.same(case.invalid, atlas.invalid)
      assert.is_false(atlas.complete())
      local zoneKeys = atlas.zoneKeys()
      assert.is_true(#zoneKeys >= 3)
      for _, k in ipairs(zoneKeys) do
        local z = atlas.zone(k)
        assert.is_false(z.complete, "zone " .. k)
        assert.is_false(atlas.continent(z.continent).complete, "continent " .. z.continent)
      end
      for _, faction in ipairs({ "Alliance", "Horde", false }) do
        local p = atlas.progress(fx.entries(), faction or nil)
        assert.is_true(p.total >= 1)
        assert.is_false(p.complete)
        assert.is_nil(p.done)
        for _, map in ipairs({ p.byZone, p.byContinent }) do
          assert.is_not_nil(next(map))
          for key, item in pairs(map) do
            assert.is_false(item.complete, tostring(key))
            assert.is_nil(item.done, tostring(key))
          end
        end
      end
    end)
  end

  -- The guard on each level on its own. In the cases above every continent has a kept
  -- zone, so the zones' guard alone would make it incomplete; these cases have none.
  it("a marked continent with no kept zone isn't complete after an exclusion (#118)",
    function()
      local inns, zones, conts = fx.places()
      conts[3] = { name = "North", complete = true }
      -- The control: with nothing excluded, North (no zone) and the atlas are complete.
      local atlas = Collection.bind(inns, zones, conts, true)
      assert.same({}, atlas.invalid)
      assert.is_true(atlas.continent(3).complete)
      assert.is_true(atlas.complete())
      inns[5401] = "Glen Inn"
      atlas = Collection.bind(inns, zones, conts, true)
      assert.same({ "inn 5401" }, atlas.invalid)
      assert.same({ name = "North", complete = false }, atlas.continent(3))
      assert.is_false(atlas.complete())
    end)

  it("every zone excluded: the marked continents and the atlas aren't complete (#118)",
    function()
      local inns, zones, conts = fx.places()
      for _, z in pairs(zones) do
        z.name = z.name:lower()
      end
      local atlas = Collection.bind(inns, zones, conts, true)
      assert.same({ "inn 5001", "inn 5002", "inn 5003", "inn 5101", "inn 5201", "inn 5202",
        "inn 5301", "zone 10", "zone 11", "zone 20", "zone 21" }, atlas.invalid)
      assert.same({}, atlas.zoneKeys())
      assert.same({ name = "East", complete = false }, atlas.continent(1))
      assert.same({ name = "West", complete = false }, atlas.continent(2))
      assert.is_false(atlas.complete())
      local p = atlas.progress(fx.entries(), "Alliance")
      assert.is_false(p.complete)
      assert.is_nil(p.done)
    end)

  it("every continent excluded: atlasComplete true is still not complete (#118)", function()
    -- The control: no records at all, nothing excluded, atlasComplete true → complete.
    assert.is_true(Collection.bind({}, {}, {}, true).complete())
    local inns, zones, conts = fx.places()
    for _, c in pairs(conts) do
      c.name = c.name:lower()
    end
    local atlas = Collection.bind(inns, zones, conts, true)
    assert.same({ "continent 1", "continent 2", "inn 5001", "inn 5002", "inn 5003", "inn 5101",
      "inn 5201", "inn 5202", "inn 5301", "zone 10", "zone 11", "zone 20", "zone 21" },
      atlas.invalid)
    assert.is_false(atlas.complete())
    assert.is_false(atlas.progress(fx.entries(), "Alliance").complete)
  end)

  it("the #118 guard changes only complete and done: signed, total and keys as before",
    function()
      -- An extra inn at an unknown zone (5401) leaves every count of F as it was.
      local inns, zones, conts = fx.places()
      inns[5401] = { name = "Glen Inn", zone = 99 }
      local atlas = Collection.bind(inns, zones, conts, true)
      assert.same({ "inn 5401" }, atlas.invalid)
      assert.same(uncompleted(allianceE()), atlas.progress(fx.entries(), "Alliance"))
      assert.same(uncompleted(hordeE()), atlas.progress(fx.entries(), "Horde"))
      assert.same(uncompleted(anyE()), atlas.progress(fx.entries(), nil))
      assert.same({ 10, 11, 20, 21 }, atlas.zoneKeys())
      assert.same({ name = "Vale", continent = 1, seal = 101, complete = false }, atlas.zone(10))
      assert.same({ name = "East", complete = false }, atlas.continent(1))
      -- Hill Inn excluded from Vale (marked): Vale's counts drop, and it isn't done.
      inns, zones, conts = fx.places()
      inns[5002].faction = "Neutral"
      local p = Collection.bind(inns, zones, conts, true).progress(fx.entries(), "Alliance")
      assert.same({ signed = 1, total = 1, continent = 1, complete = false }, p.byZone[10])
      assert.equal(3, p.signed)
      assert.equal(3, p.total)
      assert.equal(2, p.unknown) -- e4 (Hill Inn) and e6
    end)

  for _, case in ipairs({
    { "nil", function() return nil end },
    { "false", function() return false end },
    { "1", function() return 1 end },
    { "\"true\"", function() return "true" end },
    { "{}", function() return {} end },
    { "a table whose __eq says true", function()
      return setmetatable({}, { __eq = function() return true end })
    end },
    { "the hostile table stand-in", fx.hostileTable },
    { "the newproxy stand-in", fx.hostileProxy },
  }) do
    it("atlasComplete " .. case[1] .. " counts as not complete", function()
      local inns, zones, conts = fx.places()
      local atlas
      assert.has_no.errors(function()
        atlas = Collection.bind(inns, zones, conts, case[2]())
      end)
      assert.same({}, atlas.invalid)
      assert.is_false(atlas.complete())
      local p = atlas.progress(fx.entries(), "Alliance")
      assert.is_false(p.complete)
      assert.is_nil(p.done)
      assert.equal(T + 400, p.byContinent[1].done) -- places keep their own marks
    end)
  end

  it("complete() always answers exactly true or false", function()
    for _, atlas in ipairs({ atlasF(), Collection.bind(fx.placesF0()), Collection.bind() }) do
      local c = atlas.complete()
      assert.is_true(rawequal(c, true) or rawequal(c, false))
    end
  end)
end)

-- ---------------------------------------------------------------------------
-- 6.6 The real data (Data/Inns.lua fills in during #12's walk).

describe("Data/Inns (the shipped places)", function()
  local DATA = NS.Data

  it("binds with nothing invalid", function()
    assert.same({}, Collection.invalid)
  end)

  it("defines Inns, Zones and Continents as tables", function()
    assert.is_table(DATA.Inns)
    assert.is_table(DATA.Zones)
    assert.is_table(DATA.Continents)
  end)

  it("keys every inn by an integer NPC ID; every record is a primary or an alias of one",
    function()
      for id, rec in pairs(DATA.Inns) do
        assert.is_true(type(id) == "number" and id % 1 == 0 and id >= 1
          and id <= LIMITS.innMax, tostring(id))
        if rec.alias ~= nil then
          assert.is_nil(DATA.Inns[rec.alias].alias, tostring(id))
          assert.equal(rec.alias, Collection.innOf(id))
        else
          assert.equal(id, Collection.innOf(id))
        end
      end
    end)

  it("every zone is used by an inn and every continent by a zone", function()
    -- A zone retired after release gets a named exception here.
    local usedZones, usedConts = {}, {}
    for _, rec in pairs(DATA.Inns) do
      if rec.zone then
        usedZones[rec.zone] = true
      end
    end
    for key, z in pairs(DATA.Zones) do
      assert.is_true(usedZones[key] == true, "zone " .. key .. " has no inn")
      usedConts[z.continent] = true
    end
    for key in pairs(DATA.Continents) do
      assert.is_true(usedConts[key] == true, "continent " .. key .. " has no zone")
    end
  end)

  it("no map ID is both a zone and a continent", function()
    for key in pairs(DATA.Zones) do
      assert.is_nil(DATA.Continents[key], "map " .. key)
    end
  end)

  it("names are unique per kind (case-insensitive)", function()
    for _, kind in ipairs({ "Inns", "Zones", "Continents" }) do
      local seen = {}
      for key, rec in pairs(DATA[kind]) do
        if rec.name then
          local n = rec.name:lower()
          assert.is_nil(seen[n], kind .. ": " .. rec.name .. " at " .. key)
          seen[n] = key
        end
      end
    end
  end)

  it("resolves the first innkeeper seen in the beta from its real GUID", function()
    -- Coriella Calmbreeze, Calmbreeze Inn (Zephras Isle), as UnitGUID("npc") gave it.
    local guid = "Creature-0-4615-2991-62-254089-0000407142"
    assert.equal(254089, NS.Ledger.innFromNpcGUID(guid, DATA.Inns))
    assert.equal(254089, Collection.innOf(254089))
  end)

  it("every completeness mark is exactly true; AtlasComplete is absent or a boolean",
    function()
      for _, kind in ipairs({ "Zones", "Continents" }) do
        for key, rec in pairs(DATA[kind]) do
          assert.is_true(rec.complete == nil or rawequal(rec.complete, true), kind .. " " .. key)
        end
      end
      local ac = DATA.AtlasComplete
      assert.is_true(ac == nil or type(ac) == "boolean")
      if ac ~= true then
        assert.is_false(Collection.complete())
      end
    end)

  it("ships no marks yet: a signature at Calmbreeze completes nothing (#110)", function()
    -- Until the walk knows Zephras Isle and Azeroth in full, they stay unmarked.
    assert.is_false(Collection.complete())
    assert.is_false(Collection.zone(2521).complete)
    assert.is_false(Collection.continent(947).complete)
    local p = Collection.progress({ { inn = 254089, t = T, phrase = { 1 } } }, "Alliance")
    assert.equal(1, p.signed)
    assert.equal(1, p.total)
    assert.is_nil(p.done)
    assert.is_nil(p.byZone[2521].done)
    assert.is_nil(p.byContinent[947].done)
  end)

  it("zone seals are unique and in 101..999", function()
    local seen = {}
    for key, z in pairs(DATA.Zones) do
      assert.is_true(z.seal >= 101 and z.seal <= 999 and z.seal % 1 == 0, tostring(key))
      assert.is_nil(seen[z.seal], "seal " .. z.seal)
      seen[z.seal] = key
    end
  end)
end)
