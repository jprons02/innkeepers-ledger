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

-- The spec 6.2 results for E.
local function allianceE()
  return {
    faction = "Alliance", signed = 4, total = 4, done = T + 400, unknown = 1, truncated = false,
    byContinent = {
      [1] = { signed = 3, total = 3, done = T + 400 },
      [2] = { signed = 1, total = 1, done = T + 100 },
    },
    byZone = {
      [10] = { signed = 2, total = 2, continent = 1, done = T + 300 },
      [11] = { signed = 1, total = 1, continent = 1, done = T + 400 },
      [20] = { signed = 1, total = 1, continent = 2, done = T + 100 },
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
    faction = "Horde", signed = 2, total = 4, unknown = 1, truncated = false,
    byContinent = {
      [1] = { signed = 1, total = 1, done = T },
      [2] = { signed = 1, total = 3 },
    },
    byZone = {
      [10] = { signed = 1, total = 1, continent = 1, done = T },
      [20] = { signed = 1, total = 2, continent = 2 },
      [21] = { signed = 0, total = 1, continent = 2 },
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
    signed = 4, total = 6, unknown = 1, truncated = false,
    byContinent = {
      [1] = { signed = 3, total = 3, done = T + 400 },
      [2] = { signed = 1, total = 3 },
    },
    byZone = {
      [10] = { signed = 2, total = 2, continent = 1, done = T + 300 },
      [11] = { signed = 1, total = 1, continent = 1, done = T + 400 },
      [20] = { signed = 1, total = 2, continent = 2 },
      [21] = { signed = 0, total = 1, continent = 2 },
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
  r.byContinent[1] = { signed = 0, total = 3 }
  r.byContinent[2] = { signed = 0, total = 1 }
  r.byZone[10] = { signed = 0, total = 2, continent = 1 }
  r.byZone[11] = { signed = 0, total = 1, continent = 1 }
  r.byZone[20] = { signed = 0, total = 1, continent = 2 }
  for _, s in pairs(r.inns) do
    s.count, s.first, s.last = 0, nil, nil
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
    for _, name in ipairs({ "progress", "innOf", "inn", "zone", "continent", "zoneKeys" }) do
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
    assert.same({ name = "Vale", continent = 1, seal = 101 }, atlas.zone(10))
    assert.same({ name = "Ridge", continent = 2, seal = 104 }, atlas.zone(21))
    assert.same({ name = "West" }, atlas.continent(2))
    assert.same({ 10, 11, 20, 21 }, atlas.zoneKeys())
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
      local atlas = Collection.bind(inns, zones, conts)
      assert.same({ label }, atlas.invalid)
      -- The rest of F still binds.
      assert.same(allianceE(), atlas.progress(fx.entries(), "Alliance"))
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
        local atlas = Collection.bind(inns, zones, conts)
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
    local atlas = Collection.bind(inns, zones, conts)
    assert.same({}, atlas.invalid)
    assert.same({ name = n48 }, atlas.continent(3))
    assert.same({ name = "A", continent = 3, seal = 105 }, atlas.zone(30))
    assert.same({ name = "Az09 ',.-azAZ Inn", zone = 30, faction = "Horde" }, atlas.inn(5401))
    assert.equal(5401, atlas.innOf(5402))
  end)

  it("two zones with seal 101 are both excluded, and their inns too", function()
    local inns, zones, conts = fx.places()
    zones[12] = zone("Glen", 1, 101)
    inns[5401] = inn("Glen Inn", 12)
    local atlas = Collection.bind(inns, zones, conts)
    assert.same({ "inn 5001", "inn 5002", "inn 5003", "inn 5401", "zone 10", "zone 12" },
      atlas.invalid)
    assert.same({ 11, 20, 21 }, atlas.zoneKeys())
    assert.is_nil(atlas.innOf(5003))
  end)

  it("a seal clash with an excluded zone record still excludes both (fail closed)", function()
    local inns, zones, conts = fx.places()
    zones[12] = zone("glen", 1, 104) -- a bad name, but its seal is 104 (Ridge's)
    local atlas = Collection.bind(inns, zones, conts)
    assert.same({ "inn 5301", "zone 12", "zone 21" }, atlas.invalid)
  end)

  it("an excluded continent cascades to its zones, their inns and aliases", function()
    local inns, zones, conts = fx.places()
    conts[1] = { name = "East", extra = true }
    local atlas = Collection.bind(inns, zones, conts)
    assert.same({ "continent 1", "inn 5001", "inn 5002", "inn 5003", "inn 5101", "zone 10",
      "zone 11" }, atlas.invalid)
    assert.same({ 20, 21 }, atlas.zoneKeys())
  end)

  -- #76: Zephras Isle (zone 2521) sits right under the Azeroth world map (947), with no
  -- Continent map between, so its group is the World map.
  local function withWorld()
    local inns, zones, conts = fx.places()
    conts[947] = cont("Azeroth")
    zones[2521] = zone("Zephras Isle", 947, 105)
    inns[251001] = inn("Zephras Inn", 2521)
    return inns, zones, conts
  end

  it("accepts a zone under a World map and counts its inns there (#76)", function()
    local atlas = Collection.bind(withWorld())
    assert.same({}, atlas.invalid)
    assert.same({ name = "Azeroth" }, atlas.continent(947))
    assert.same({ name = "Zephras Isle", continent = 947, seal = 105 }, atlas.zone(2521))
    assert.equal(251001, atlas.innOf(251001))
    assert.same({ 10, 11, 20, 21, 2521 }, atlas.zoneKeys())

    local own = fx.entries()
    own[#own + 1] = { inn = 251001, t = T + 600, phrase = { 1 } }
    local p = atlas.progress(own, "Alliance")
    local want = allianceE()
    want.signed, want.total, want.done = 5, 5, T + 600
    want.byContinent[947] = { signed = 1, total = 1, done = T + 600 }
    want.byZone[2521] = { signed = 1, total = 1, continent = 947, done = T + 600 }
    want.inns[251001] = { zone = 2521, open = true, count = 1, first = T + 600, last = T + 600 }
    assert.same(want, p)

    -- Unsigned, it is one more open inn on its own group.
    p = atlas.progress(fx.entries(), "Horde")
    assert.same({ signed = 0, total = 1 }, p.byContinent[947])
    assert.same({ signed = 0, total = 1, continent = 947 }, p.byZone[2521])
    assert.equal(5, p.total)
  end)

  it("a World key reused as a zone key excludes both, and what hangs off them (#76)",
    function()
      local inns, zones, conts = withWorld()
      zones[947] = zone("Azeroth", 1, 106)
      local atlas = Collection.bind(inns, zones, conts)
      assert.same({ "continent 947", "inn 251001", "zone 2521", "zone 947" }, atlas.invalid)
      assert.is_nil(atlas.continent(947))
      assert.is_nil(atlas.zone(947))
      assert.same({ 10, 11, 20, 21 }, atlas.zoneKeys())
      assert.same(allianceE(), atlas.progress(fx.entries(), "Alliance"))
    end)

  it("a key in both tables excludes both even when one record is junk (fail closed)",
    function()
      local inns, zones, conts = fx.places()
      conts[10] = "junk" -- zone 10's key; zone 10 itself is good
      local atlas = Collection.bind(inns, zones, conts)
      assert.same({ "continent 10", "inn 5001", "inn 5002", "inn 5003", "zone 10" },
        atlas.invalid)
      inns, zones, conts = fx.places()
      zones[1] = 7 -- continent 1's key
      atlas = Collection.bind(inns, zones, conts)
      assert.same({ "continent 1", "inn 5001", "inn 5002", "inn 5003", "inn 5101", "zone 1",
        "zone 10", "zone 11" }, atlas.invalid)
    end)

  it("a zone whose chain loops back to itself is excluded (#76)", function()
    -- Its own continent, with no continent record: an unknown continent.
    local inns, zones, conts = fx.places()
    zones[30] = zone("Glen", 30, 105)
    inns[5401] = inn("Glen Inn", 30)
    local atlas = Collection.bind(inns, zones, conts)
    assert.same({ "inn 5401", "zone 30" }, atlas.invalid)
    -- Its own continent, with a continent record of that key: the key is in both tables.
    conts[30] = cont("Glen Lands")
    atlas = Collection.bind(inns, zones, conts)
    assert.same({ "continent 30", "inn 5401", "zone 30" }, atlas.invalid)
    -- Two zones that are each other's continent.
    inns, zones, conts = fx.places()
    zones[30], zones[31] = zone("Glen", 31, 105), zone("Fen", 30, 106)
    conts[30], conts[31] = cont("Glen Lands"), cont("Fen Lands")
    inns[5401] = inn("Glen Inn", 30)
    atlas = Collection.bind(inns, zones, conts)
    assert.same({ "continent 30", "continent 31", "inn 5401", "zone 30", "zone 31" },
      atlas.invalid)
    assert.same(allianceE(), atlas.progress(fx.entries(), "Alliance"))
  end)

  it("an alias to an excluded inn is excluded too", function()
    local inns, zones, conts = fx.places()
    inns[5401] = inn("Glen Inn", 99)
    inns[5402] = { alias = 5401 }
    local atlas = Collection.bind(inns, zones, conts)
    assert.same({ "inn 5401", "inn 5402" }, atlas.invalid)
  end)

  it("an entry at an excluded inn counts as unknown", function()
    local inns, zones, conts = fx.places()
    inns[5101].faction = "Neutral"
    local atlas = Collection.bind(inns, zones, conts)
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
        inns = {}, unknown = 7, truncated = false }, atlas.progress(fx.entries(), "Alliance"))
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
    local atlas = Collection.bind(inns, zones, conts)
    assert.same({}, atlas.invalid)
    assert.is_nil(atlas.inn(5999))
    assert.same({ name = "Vale Inn", zone = 10 }, atlas.inn(5001))
    assert.equal(0, calls)
  end)

  it("copies: changing F after bind changes no later result", function()
    local inns, zones, conts = fx.places()
    local atlas = Collection.bind(inns, zones, conts)
    inns[5001].name = "Changed"
    inns[5001].faction = "Horde"
    inns[5003].alias = 5002
    inns[5999] = inn("New Inn", 10)
    zones[10].seal = 199
    zones[30] = zone("Glen", 1, 105)
    conts[1].name = "Changed"
    inns[5101] = nil
    assert.same({ name = "Vale Inn", zone = 10 }, atlas.inn(5001))
    assert.equal(5001, atlas.innOf(5003))
    assert.is_nil(atlas.innOf(5999))
    assert.same({ name = "Vale", continent = 1, seal = 101 }, atlas.zone(10))
    assert.same({ name = "East" }, atlas.continent(1))
    assert.same({ 10, 11, 20, 21 }, atlas.zoneKeys())
    assert.same(allianceE(), atlas.progress(fx.entries(), "Alliance"))
  end)

  it("copies: changing a returned table changes no later result", function()
    local atlas = atlasF()
    local i, z, c, keys = atlas.inn(5002), atlas.zone(10), atlas.continent(1), atlas.zoneKeys()
    i.faction, i.zone = "Horde", 11
    z.seal, z.continent = 1, 2
    c.name = "X"
    keys[1], keys[5] = 99, 100
    local p = atlas.progress(fx.entries(), "Alliance")
    p.signed, p.inns[5001].count, p.byZone[10].total, p.byContinent[1] = 0, 0, 9, nil
    assert.same({ name = "Hill Inn", zone = 10, faction = "Alliance" }, atlas.inn(5002))
    assert.same({ name = "Vale", continent = 1, seal = 101 }, atlas.zone(10))
    assert.same({ name = "East" }, atlas.continent(1))
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
      assert.same({ signed = 1, total = 2, continent = 2 }, p.byZone[20])
    end)
  end

  it("empty data: nothing to count, every entry unknown", function()
    local p = Collection.bind({}, {}, {}).progress(fx.entries(), "Alliance")
    assert.same({ faction = "Alliance", signed = 0, total = 0, byContinent = {}, byZone = {},
      inns = {}, unknown = 7, truncated = false }, p)
    assert.is_nil(p.done)
  end)

  it("an inn removed from the data after you signed it counts as unknown", function()
    local inns, zones, conts = fx.places()
    inns[5101] = nil
    local p = Collection.bind(inns, zones, conts).progress(fx.entries(), "Alliance")
    assert.equal(3, p.total)
    assert.equal(3, p.signed)
    assert.equal(2, p.unknown)
    assert.is_nil(p.byZone[11])
    assert.is_nil(p.inns[5101])
    assert.equal(T + 300, p.done)
    assert.same({ signed = 2, total = 2, done = T + 300 }, p.byContinent[1])
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

  it("zone seals are unique and in 101..999", function()
    local seen = {}
    for key, z in pairs(DATA.Zones) do
      assert.is_true(z.seal >= 101 and z.seal <= 999 and z.seal % 1 == 0, tostring(key))
      assert.is_nil(seen[z.seal], "seal " .. z.seal)
      seen[z.seal] = key
    end
  end)
end)
