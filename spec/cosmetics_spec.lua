-- Cosmetics: catalog record rules, SEALS, unlocks and their earned times, the kept floor,
-- canSeal, the real draft catalog and SyncProtocol with the real SEALS
-- (docs/specs/collection-cosmetics.md, sections 6.3-6.8). SEALS decides which peer entries
-- are stored; own entries and `earned` come from SavedVariables, so `own`, `kept` and
-- `unlocked` are hostile here. Fixed times, never the clock.
local load = require("helpers.load")
local fx = require("helpers.places")

local T = fx.T

-- A fresh ns: Ledger, then (unless noData) the data, then Collection and Cosmetics, as in
-- the TOC. `patch` may change Ledger before the modules read it.
local function modules(opts)
  opts = opts or {}
  local ns = {}
  load.file("Ledger.lua", ns, load.pure_env())
  if opts.patch then
    opts.patch(ns.Ledger)
  end
  if not opts.noData then
    load.file("Data/Inns.lua", ns, load.pure_env())
    load.file("Data/Cosmetics.lua", ns, load.pure_env())
  end
  load.file("Collection.lua", ns, load.pure_env())
  load.file("Cosmetics.lua", ns, load.pure_env())
  return ns
end

local NS = modules()
local Collection, Cosmetics = NS.Collection, NS.Cosmetics
local LIMITS = NS.Ledger.LIMITS

local function atlasF()
  return Collection.bind(fx.places())
end

local function setF(catalog)
  return Cosmetics.bind(atlasF(), catalog or fx.catalog())
end

local function keys(t)
  local out = {}
  for k in pairs(t) do
    out[#out + 1] = k
  end
  table.sort(out)
  return out
end

local function U(pairsList)
  local out = {}
  for i, p in ipairs(pairsList) do
    out[i] = { id = p[1], t = p[2] }
  end
  return out
end

-- The spec 6.4 results for E.
local ALLIANCE = U({ { 1, T + 100 }, { 103, T + 100 }, { 1003, T + 100 }, { 101, T + 300 },
  { 1001, T + 300 }, { 1002, T + 300 }, { 2, T + 400 }, { 102, T + 400 } })
local HORDE = U({ { 101, T }, { 1003, T }, { 1, T + 100 } })

-- Every own-entry time in E.
local function entryTimes()
  local times = {}
  for _, e in ipairs(fx.entries()) do
    times[e.t] = true
  end
  return times
end

-- ---------------------------------------------------------------------------

describe("Cosmetics module", function()
  it("has the spec 3.8 RANGES", function()
    assert.same({ seal = { 1, 99 }, zoneSeal = { 101, 999 }, quill = { 1000, 1099 } },
      Cosmetics.RANGES)
  end)

  it("changing the exported RANGES changes nothing inside", function()
    local ns = modules()
    ns.Cosmetics.RANGES.seal[2] = 5000
    ns.Cosmetics.RANGES.quill[1] = 1
    local set = ns.Cosmetics.bind(ns.Collection.bind(fx.places()), fx.catalog())
    assert.same({}, set.invalid)
    local cat = fx.catalog()
    cat[3000] = { kind = "seal", name = "Big seal", rule = { kind = "all" } }
    cat[50] = { kind = "quill", name = "Low quill", rule = { kind = "all" } }
    assert.same({ "cosmetic 3000", "cosmetic 50" },
      ns.Cosmetics.bind(ns.Collection.bind(fx.places()), cat).invalid)
  end)

  it("exposes the default set's fields", function()
    for _, name in ipairs({ "info", "catalog", "unlocked", "canSeal" }) do
      assert.is_function(Cosmetics[name], name)
    end
    assert.is_table(Cosmetics.SEALS)
    assert.same({}, Cosmetics.invalid)
  end)

  it("raises at load without Ledger or Collection (packaging bugs)", function()
    assert.has_error(function()
      load.file("Cosmetics.lua", {}, load.pure_env())
    end)
    assert.has_error(function()
      local ns = {}
      load.file("Ledger.lua", ns, load.pure_env())
      load.file("Cosmetics.lua", ns, load.pure_env())
    end)
  end)

  it("raises at load if a range is over Ledger.LIMITS (sealMax, cosmeticIdMax)", function()
    assert.has_error(function()
      modules({ patch = function(L) L.LIMITS.sealMax = 500 end })
    end)
    assert.has_error(function()
      modules({ patch = function(L) L.LIMITS.cosmeticIdMax = 1050 end })
    end)
  end)

  it("reads tMin and tMax from Ledger.LIMITS, not second literals", function()
    local ns = modules({ patch = function(L)
      L.LIMITS.tMax = T + 350
    end })
    local set = ns.Cosmetics.bind(ns.Collection.bind(fx.places()), fx.catalog())
    -- e5 (T + 400) and e7 are past tMax now: not read, so zone 11 has nothing signed.
    local got = set.unlocked(fx.entries(), "Alliance")
    assert.same(U({ { 1, T + 100 }, { 103, T + 100 }, { 1003, T + 100 }, { 101, T + 300 },
      { 1001, T + 300 }, { 1002, T + 300 } }), got)
    assert.is_false(set.canSeal(got, 1, T + 351))
    assert.is_true(set.canSeal(got, 1, T + 350))
    -- A kept time past tMax is ignored.
    assert.same(got, set.unlocked(fx.entries(), "Alliance", { [102] = T + 400 }))
  end)

  it("loads with no Data: SEALS empty, nothing unlocked", function()
    local ns = modules({ noData = true })
    assert.same({}, ns.Cosmetics.SEALS)
    assert.same({}, ns.Cosmetics.invalid)
    assert.same({}, ns.Cosmetics.catalog())
    assert.same({}, ns.Cosmetics.unlocked(fx.entries(), "Alliance"))
    assert.is_false(ns.Cosmetics.canSeal({ { id = 1, t = T } }, 1, T))
  end)

  it("loads with a non-table ns.Data: SEALS empty", function()
    local ns = {}
    load.file("Ledger.lua", ns, load.pure_env())
    ns.Data = 7
    load.file("Collection.lua", ns, load.pure_env())
    load.file("Cosmetics.lua", ns, load.pure_env())
    assert.same({}, ns.Cosmetics.SEALS)
  end)
end)

-- ---------------------------------------------------------------------------
-- 6.3 bind, catalog and SEALS.

describe("Cosmetics.bind", function()
  it("binds atlas F and catalog C: SEALS, info and catalog", function()
    local set = setF()
    assert.same({}, set.invalid)
    assert.same({ 1, 2, 101, 102, 103, 104 }, keys(set.SEALS))
    assert.same({ id = 103, kind = "seal", name = "Dunes", rule = { kind = "zone", zone = 20 } },
      set.info(103))
    assert.same({ kind = "inns", n = 3 }, set.info(1001).rule)
    assert.same({ id = 2, kind = "seal", name = "Last seal", rule = { kind = "all" } },
      set.info(2))
    assert.same({ id = 1002, kind = "quill", name = "Blue quill",
      rule = { kind = "zones", n = 2 } }, set.info(1002))
    assert.is_nil(set.info(5))
    assert.is_nil(set.info(nil))
    for _, v in ipairs({ "1", 0 / 0, 1 / 0, 1.5, 0, 10000, {}, fx.hostileTable(),
      fx.hostileProxy() }) do
      assert.is_nil(set.info(v))
    end
    local cat = set.catalog()
    assert.equal(9, #cat)
    local ids = {}
    for i, rec in ipairs(cat) do
      ids[i] = rec.id
      assert.same(set.info(rec.id), rec)
    end
    assert.same({ 1, 2, 101, 102, 103, 104, 1001, 1002, 1003 }, ids)
  end)

  it("SEALS values are info records, and it holds seals only", function()
    local set = setF()
    for id, rec in pairs(set.SEALS) do
      assert.same(set.info(id), rec)
      assert.equal("seal", rec.kind)
      assert.is_true(id % 1 == 0 and id >= 1 and id <= LIMITS.sealMax)
    end
    assert.is_nil(set.SEALS[1001])
    assert.is_nil(set.SEALS[1002])
  end)

  local function rec(kind, name, rule)
    return { kind = kind, name = name, rule = rule }
  end
  local ALL = { kind = "all" }

  -- Each record rule of spec 3.5 broken once, added to C: { label, id, record }.
  local BROKEN = {
    { "a seal at 0", 0, rec("seal", "Seal", ALL) },
    { "a seal at 100", 100, rec("seal", "Seal", ALL) },
    { "a seal at 101 (zone seals come only from Data/Zones)", 101, rec("seal", "Seal", ALL) },
    { "a seal at 999", 999, rec("seal", "Seal", ALL) },
    { "a seal at 1000", 1000, rec("seal", "Seal", ALL) },
    { "a quill at 999", 999, rec("quill", "Quill", ALL) },
    { "a quill at 1100", 1100, rec("quill", "Quill", ALL) },
    { "an ink (no longer a kind) in the quill range", 1050, rec("ink", "Ink", ALL) },
    { "a quill at 1101 (reserved; inks held it)", 1101, rec("quill", "Quill", ALL) },
    { "a quill at 10000", 10000, rec("quill", "Quill", ALL) },
    { "a seal at 1.5", 1.5, rec("seal", "Seal", ALL) },
    { "a seal at -1", -1, rec("seal", "Seal", ALL) },
    { "a key \"3\"", "3", rec("seal", "Seal", ALL) },
    { "an unknown kind", 3, rec("badge", "Badge", ALL) },
    { "kind \"Seal\"", 3, rec("Seal", "Seal", ALL) },
    { "kind \"zoneSeal\"", 3, rec("zoneSeal", "Seal", ALL) },
    { "a missing kind", 3, { name = "Seal", rule = ALL } },
    { "an extra field", 3, { kind = "seal", name = "Seal", rule = ALL, price = 0 } },
    { "a name with |", 3, rec("seal", "Se|al", ALL) },
    { "a name with %", 3, rec("seal", "Se%al", ALL) },
    { "a name with \\0", 3, rec("seal", "Se\0al", ALL) },
    { "a name with a UTF-8 byte", 3, rec("seal", "S\195\169al", ALL) },
    { "a name with !", 3, rec("seal", "Seal!", ALL) },
    { "a name starting lowercase", 3, rec("seal", "seal", ALL) },
    { "a name with a trailing space", 3, rec("seal", "Seal ", ALL) },
    { "a name with a double space", 3, rec("seal", "Big  seal", ALL) },
    { "an empty name", 3, rec("seal", "", ALL) },
    { "a 33-byte name", 3, rec("seal", "S" .. ("e"):rep(32), ALL) },
    { "a non-string name", 3, rec("seal", 3, ALL) },
    { "a missing name", 3, { kind = "seal", rule = ALL } },
    { "a missing rule", 3, { kind = "seal", name = "Seal" } },
    { "a rule that's a string", 3, rec("seal", "Seal", "all") },
    { "a rule of unknown kind", 3, rec("seal", "Seal", { kind = "badges" }) },
    { "a rule of kind zone (only generated)", 3,
      rec("seal", "Seal", { kind = "zone", zone = 10 }) },
    { "a rule without a kind", 3, rec("seal", "Seal", { n = 2 }) },
    { "inns with n 0", 3, rec("seal", "Seal", { kind = "inns", n = 0 }) },
    { "inns with n 1.5", 3, rec("seal", "Seal", { kind = "inns", n = 1.5 }) },
    { "inns with n 10000", 3, rec("seal", "Seal", { kind = "inns", n = 10000 }) },
    { "inns with n NaN", 3, rec("seal", "Seal", { kind = "inns", n = 0 / 0 }) },
    { "inns with n \"2\"", 3, rec("seal", "Seal", { kind = "inns", n = "2" }) },
    { "inns with n missing", 3, rec("seal", "Seal", { kind = "inns" }) },
    { "zones with n 1000", 3, rec("seal", "Seal", { kind = "zones", n = 1000 }) },
    { "zones with n missing", 3, rec("seal", "Seal", { kind = "zones" }) },
    { "continent with an n", 3, rec("seal", "Seal", { kind = "continent", n = 1 }) },
    { "all with an n", 3, rec("seal", "Seal", { kind = "all", n = 1 }) },
    { "an extra rule field", 3, rec("seal", "Seal", { kind = "inns", n = 2, zone = 10 }) },
    { "a record that's a string", 3, "Seal" },
    { "a record that's a hostile table", 3, fx.hostileTable() },
  }

  for _, case in ipairs(BROKEN) do
    local name, id, value = case[1], case[2], case[3]
    it("excludes " .. name, function()
      local cat = fx.catalog()
      cat[id] = value
      local set = setF(cat)
      local label = type(id) == "number" and "cosmetic " .. tostring(id)
        or "cosmetic <" .. type(id) .. ">"
      assert.same({ label }, set.invalid)
      assert.equal(9, #set.catalog())
      if id ~= 101 then
        assert.is_nil(set.info(id))
        assert.is_nil(set.SEALS[id])
      else
        assert.equal("Vale", set.info(101).name) -- the zone's seal, not the catalog's
      end
      assert.same(ALLIANCE, set.unlocked(fx.entries(), "Alliance"))
    end)
  end

  it("passes the boundary IDs, a 32-byte name and n at its maximum", function()
    local cat = fx.catalog()
    cat[99] = rec("seal", "S" .. ("e"):rep(31), { kind = "inns", n = 9999 })
    cat[1000] = rec("quill", "Az09 ',.-", { kind = "zones", n = 999 })
    cat[1099] = rec("quill", "Q", ALL)
    local set = setF(cat)
    assert.same({}, set.invalid)
    assert.equal(12, #set.catalog())
    assert.is_table(set.SEALS[99])
  end)

  for _, case in ipairs({
    { "bind(nil, nil)", {} },
    { "bind({}, \"x\")", { {}, "x" } },
    { "bind(a proxy, a hostile table)", { fx.hostileProxy(), fx.hostileTable() } },
  }) do
    it(case[1] .. " gives an empty set", function()
      local set = Cosmetics.bind(unpack(case[2], 1, 2))
      assert.same({}, set.SEALS)
      assert.same({}, set.invalid)
      assert.same({}, set.catalog())
      assert.same({}, set.unlocked(fx.entries(), "Alliance", { [1] = T }))
      for _, anything in ipairs({ {}, { { id = 1, t = T } }, ALLIANCE }) do
        assert.is_false(set.canSeal(anything, 1, T + 500))
      end
      assert.is_true(set.canSeal({}, nil, T))
    end)
  end

  it("an atlas without progress counts as empty; C still binds", function()
    local a = atlasF()
    local set = Cosmetics.bind({ zoneKeys = a.zoneKeys, zone = a.zone }, fx.catalog())
    assert.same({ 1, 2 }, keys(set.SEALS))
    assert.same({}, set.unlocked(fx.entries(), "Alliance"))
  end)

  it("an atlas whose zone functions misbehave counts as empty (fail closed)", function()
    local good = atlasF()
    local function atlasWith(zoneKeys, zone)
      return { progress = good.progress, zoneKeys = zoneKeys, zone = zone }
    end
    for _, a in ipairs({
      atlasWith(function() error("boom") end, good.zone),
      atlasWith(good.zoneKeys, function() error("boom") end),
      atlasWith(good.zoneKeys, function() return nil end),
      atlasWith(good.zoneKeys, function(k)
        local z = good.zone(k)
        z.seal = 1000
        return z
      end),
      atlasWith(good.zoneKeys, function(k)
        local z = good.zone(k)
        z.seal = 101 -- every zone the same seal
        return z
      end),
      atlasWith(good.zoneKeys, function(k)
        local z = good.zone(k)
        z.name = "Bad|name"
        return z
      end),
      atlasWith(function()
        local out = {}
        for i = 1, 900 do
          out[i] = i
        end
        return out
      end, function(k) return { name = "Zone", continent = 1, seal = 100 + k } end),
    }) do
      local set = Cosmetics.bind(a, fx.catalog())
      assert.same({ 1, 2 }, keys(set.SEALS))
      assert.same({}, set.unlocked(fx.entries(), "Alliance"))
    end
    -- A non-table zoneKeys result, or a non-number key mid-list, empties the atlas too
    -- (spec 3.8: zones that misbehave), rather than keeping a partial zone list.
    for _, zk in ipairs({
      function() return "x" end,
      function() return { 10, false, 11 } end,
      function() return { 10, "11" } end,
    }) do
      local set = Cosmetics.bind(atlasWith(zk, good.zone), fx.catalog())
      assert.same({ 1, 2 }, keys(set.SEALS))
      assert.same({}, set.unlocked(fx.entries(), "Alliance"))
    end
  end)

  it("an atlas whose progress raises unlocks nothing, never throwing", function()
    local good = atlasF()
    local set = Cosmetics.bind({ progress = function() error("boom") end,
      zoneKeys = good.zoneKeys, zone = good.zone }, fx.catalog())
    local ok, res = pcall(set.unlocked, fx.entries(), "Alliance", { [1] = T })
    assert.is_true(ok)
    assert.same({}, res)
  end)

  it("SEALS is safe to hand out: changing it doesn't change canSeal", function()
    local set = setF()
    local list = U({ { 3, T }, { 1, T + 100 }, { 1001, T } })
    set.SEALS[3] = { id = 3, kind = "seal", name = "Forged", rule = { kind = "all" } }
    set.SEALS[1001] = true
    set.SEALS[1] = nil
    assert.is_false(set.canSeal(list, 3, T + 500))
    assert.is_false(set.canSeal(list, 1001, T + 500))
    assert.is_true(set.canSeal(list, 1, T + 500))
    set.SEALS[103].name = "Changed"
    assert.equal("Dunes", set.info(103).name)
  end)

  it("a new bind gives a fresh SEALS table", function()
    local a, b = setF(), setF()
    assert.are_not.equal(a.SEALS, b.SEALS)
    assert.same(a.SEALS, b.SEALS)
  end)

  it("copies: changing C after bind, or a returned record, changes no later result", function()
    local cat = fx.catalog()
    local set = setF(cat)
    cat[1].rule.n = 1
    cat[1].name = "Changed"
    cat[3] = rec("seal", "Late seal", ALL)
    local info = set.info(1)
    info.rule.n, info.name = 1, "X"
    set.catalog()[1].rule.n = 1
    assert.same({ id = 1, kind = "seal", name = "First seal", rule = { kind = "inns", n = 2 } },
      set.info(1))
    assert.is_nil(set.info(3))
    assert.same(ALLIANCE, set.unlocked(fx.entries(), "Alliance"))
  end)

  it("a catalog table with a metatable is read raw", function()
    local calls = 0
    local cat = setmetatable(fx.catalog(), { __index = function()
      calls = calls + 1
      return rec("seal", "Ghost", ALL)
    end })
    setmetatable(cat[1], { __index = function() calls = calls + 1 end })
    local set = setF(cat)
    assert.same({}, set.invalid)
    assert.is_nil(set.info(3))
    assert.equal(0, calls)
  end)
end)

-- ---------------------------------------------------------------------------
-- 6.4 unlocked and earned times.

describe("Cosmetics unlocked", function()
  local set = setF()

  it("Alliance, E, no kept: the spec 6.4 list in (t, id) order; Horde's zone seal absent",
    function()
      local got = set.unlocked(fx.entries(), "Alliance")
      assert.same(ALLIANCE, got)
      for _, u in ipairs(got) do
        assert.are_not.equal(104, u.id)
      end
    end)

  it("Horde, E", function()
    assert.same(HORDE, set.unlocked(fx.entries(), "Horde"))
  end)

  it("every time is an own entry's t, and results are deterministic", function()
    local times = entryTimes()
    for _, faction in ipairs({ "Alliance", "Horde" }) do
      local want = set.unlocked(fx.entries(), faction)
      for _, u in ipairs(want) do
        assert.is_true(times[u.t] == true, u.id .. " at " .. u.t)
      end
      assert.same(want, set.unlocked(fx.entries(), faction))
      assert.same(want, set.unlocked(fx.reversed(fx.entries()), faction))
      for seed = 1, 20 do
        assert.same(want, set.unlocked(fx.shuffled(fx.entries(), seed * 104729), faction))
      end
    end
  end)

  it("faction nil counts every inn: no all, no Horde zone done yet", function()
    assert.same(U({ { 1, T + 100 }, { 101, T + 300 }, { 1001, T + 300 }, { 102, T + 400 },
      { 1002, T + 400 }, { 1003, T + 400 } }), set.unlocked(fx.entries(), nil))
  end)

  it("empty data: nothing for any entries", function()
    local empty = Cosmetics.bind(Collection.bind({}, {}, {}), fx.catalog())
    assert.same({}, empty.unlocked(fx.entries(), "Alliance"))
    assert.same({}, empty.unlocked(fx.entries(), nil))
    assert.same({}, empty.unlocked({}, "Horde"))
  end)

  it("no entries: nothing unlocked", function()
    assert.same({}, set.unlocked({}, "Alliance"))
    assert.same({}, set.unlocked(nil, "Alliance"))
  end)

  it("a zone under a World map earns its seal, and its group counts as a continent (#76)",
    function()
      local world = Cosmetics.bind(Collection.bind(
        { [251001] = { name = "Zephras Inn", zone = 2521 } },
        { [2521] = { name = "Zephras Isle", continent = 947, seal = 101, complete = true } },
        { [947] = { name = "Azeroth", complete = true } }, true), fx.catalog())
      assert.same({}, world.invalid)
      assert.same({ 1, 2, 101 }, keys(world.SEALS))
      assert.same(U({ { 2, T }, { 101, T }, { 1003, T } }),
        world.unlocked({ { inn = 251001, t = T, phrase = { 1 } } }, "Alliance"))
    end)

  describe("completeness marks (spec 3.11)", function()
    -- F0 plus the marks named: { zones = { keys }, conts = { keys } }, and atlasComplete.
    local function setMarked(zoneKeys, contKeys, atlasComplete)
      local inns, zones, conts = fx.placesF0()
      for _, k in ipairs(zoneKeys) do
        zones[k].complete = true
      end
      for _, k in ipairs(contKeys) do
        conts[k].complete = true
      end
      return Cosmetics.bind(Collection.bind(inns, zones, conts, atlasComplete), fx.catalog())
    end

    it("F0, E: only the inns n items (1 and 1001 at their F times)", function()
      local s = Cosmetics.bind(Collection.bind(fx.placesF0()), fx.catalog())
      assert.same({}, s.invalid)
      assert.same({ 1, 2, 101, 102, 103, 104 }, keys(s.SEALS)) -- SEALS doesn't change
      assert.same(U({ { 1, T + 100 }, { 1001, T + 300 } }), s.unlocked(fx.entries(), "Alliance"))
      assert.same(U({ { 1, T + 100 } }), s.unlocked(fx.entries(), "Horde"))
      assert.same(U({ { 1, T + 100 }, { 1001, T + 300 } }), s.unlocked(fx.entries(), nil))
      -- Even with atlasComplete, unmarked places complete nothing.
      assert.same(U({ { 1, T + 100 }, { 1001, T + 300 } }),
        setMarked({}, {}, true).unlocked(fx.entries(), "Alliance"))
    end)

    it("Vale marked: seal 101 returns at F's time, nothing else", function()
      assert.same(U({ { 1, T + 100 }, { 101, T + 300 }, { 1001, T + 300 } }),
        setMarked({ 10 }, {}).unlocked(fx.entries(), "Alliance"))
    end)

    it("East marked with Marsh unmarked: East isn't complete, no 1003", function()
      assert.same(U({ { 1, T + 100 }, { 101, T + 300 }, { 1001, T + 300 } }),
        setMarked({ 10 }, { 1 }).unlocked(fx.entries(), "Alliance"))
    end)

    it("East with both its zones marked: 1003 at East's done, and 1002", function()
      assert.same(U({ { 1, T + 100 }, { 101, T + 300 }, { 1001, T + 300 }, { 102, T + 400 },
        { 1002, T + 400 }, { 1003, T + 400 } }),
        setMarked({ 10, 11 }, { 1 }).unlocked(fx.entries(), "Alliance"))
    end)

    it("every place marked, no atlasComplete: F's list without 2", function()
      local want = {}
      for _, u in ipairs(ALLIANCE) do
        if u.id ~= 2 then
          want[#want + 1] = u
        end
      end
      assert.same(want, setMarked({ 10, 11, 20, 21 }, { 1, 2 }).unlocked(fx.entries(), "Alliance"))
    end)

    it("atlasComplete without every continent complete: no all (seal 2)", function()
      local got = setMarked({ 10, 11, 20 }, { 1, 2 }, true).unlocked(fx.entries(), "Alliance")
      for _, u in ipairs(got) do
        assert.are_not.equal(2, u.id)
      end
      -- West isn't complete (Ridge unmarked): 1003 comes from East at T + 400, not T + 100.
      assert.same(U({ { 1, T + 100 }, { 103, T + 100 }, { 101, T + 300 }, { 1001, T + 300 },
        { 1002, T + 300 }, { 102, T + 400 }, { 1003, T + 400 } }), got)
    end)

    it("every mark and atlasComplete: the F list", function()
      assert.same(ALLIANCE,
        setMarked({ 10, 11, 20, 21 }, { 1, 2 }, true).unlocked(fx.entries(), "Alliance"))
    end)

    it("the kept floor still honors an unlock recorded under older data", function()
      local kept = { [101] = T, [2] = T + 400, [1003] = T + 100 }
      assert.same(U({ { 101, T }, { 1, T + 100 }, { 1003, T + 100 }, { 1001, T + 300 },
        { 2, T + 400 } }), setMarked({}, {}).unlocked(fx.entries(), "Alliance", kept))
    end)
  end)

  describe("the kept floor", function()
    local function withNewInn()
      local inns, zones, conts = fx.places()
      inns[5004] = { name = "Brook Inn", zone = 10 }
      return Cosmetics.bind(Collection.bind(inns, zones, conts, true), fx.catalog())
    end

    it("a new inn in a done zone: 101 and 2 gone, 1002 moves to T+400 without kept", function()
      local s = withNewInn()
      assert.same(U({ { 1, T + 100 }, { 103, T + 100 }, { 1003, T + 100 }, { 1001, T + 300 },
        { 102, T + 400 }, { 1002, T + 400 } }), s.unlocked(fx.entries(), "Alliance"))
    end)

    it("a new inn in a done zone: kept keeps 101, 2 and the earlier 1002", function()
      local s = withNewInn()
      local kept = { [101] = T + 300, [2] = T + 400, [1002] = T + 300 }
      local before = fx.snapshot(kept)
      assert.same(ALLIANCE, s.unlocked(fx.entries(), "Alliance", kept))
      assert.is_true(fx.sameSnapshot(before, fx.snapshot(kept)))
    end)

    it("a zone that loses its only inn keeps its seal at e5's time", function()
      local inns, zones, conts = fx.places()
      inns[5101] = nil
      local s = Cosmetics.bind(Collection.bind(inns, zones, conts, true), fx.catalog())
      local got = s.unlocked(fx.entries(), "Alliance", { [102] = T + 400 })
      local found
      for _, u in ipairs(got) do
        if u.id == 102 then
          found = u.t
        end
      end
      assert.equal(T + 400, found)
      -- Without kept it's gone (zone 11 has no open inn).
      for _, u in ipairs(s.unlocked(fx.entries(), "Alliance")) do
        assert.are_not.equal(102, u.id)
      end
    end)

    it("a kept time earlier than derived wins: seal 1 at T", function()
      local got = set.unlocked(fx.entries(), "Alliance", { [1] = T })
      assert.same({ id = 1, t = T }, got[1])
      assert.equal(#ALLIANCE, #got)
    end)

    it("a kept time is honored at any own entry, even at an unknown inn (e6)", function()
      local got = set.unlocked(fx.entries(), "Horde", { [2] = T + 500 })
      assert.same(U({ { 101, T }, { 1003, T }, { 1, T + 100 }, { 2, T + 500 } }), got)
    end)

    -- Kept values that are ignored: Horde has neither 2 nor 102 derived, so any honored
    -- value would show.
    for _, case in ipairs({
      { "[102] = T+401 (not an entry time)", function() return { [102] = T + 401 } end },
      { "[2] = T+1 (not an entry time)", function() return { [2] = T + 1 } end },
      { "[7] = T (not in the catalog)", function() return { [7] = T } end },
      { "[1105] = T (not in the catalog)", function() return { [1105] = T } end },
      { "[2] = \"x\"", function() return { [2] = "x" } end },
      { "[2] = NaN", function() return { [2] = 0 / 0 } end },
      { "[2] = inf", function() return { [2] = 1 / 0 } end },
      { "[2] = 1.5", function() return { [2] = 1.5 } end },
      { "[2] = T + 0.5", function() return { [2] = T + 0.5 } end },
      { "[2] = tMin - 1", function() return { [2] = LIMITS.tMin - 1 } end },
      { "[2] = tostring(T)", function() return { [2] = tostring(T) } end },
      { "[\"2\"] = T", function() return { ["2"] = T } end },
      { "kept = \"junk\"", function() return "junk" end },
      { "kept = 7", function() return 7 end },
      { "kept = the newproxy stand-in", fx.hostileProxy },
      { "kept = a table whose __index raises", fx.hostileTable },
      { "kept = a table whose __index answers T", function()
        return setmetatable({}, { __index = function() return T end })
      end },
    }) do
      it("ignores kept " .. case[1], function()
        local kept = case[2]()
        local ok, got = pcall(set.unlocked, fx.entries(), "Horde", kept)
        assert.is_true(ok)
        assert.same(HORDE, got)
      end)
    end

    it("a kept time at an entry progress didn't read is ignored", function()
      local E = fx.entries()
      assert.same(HORDE, set.unlocked({ E[1], E[2], { inn = 0, t = T + 7 } }, "Horde",
        { [2] = T + 7 }))
      -- Past a hole isn't read either.
      assert.same(HORDE, set.unlocked({ E[1], E[2], nil, E[4] }, "Horde", { [2] = T + 300 }))
      assert.same(U({ { 101, T }, { 1003, T }, { 1, T + 100 }, { 2, T + 300 } }),
        set.unlocked({ E[1], E[2], E[4] }, "Horde", { [2] = T + 300 }))
    end)

    it("the controls: an honored value would show", function()
      assert.same(U({ { 2, T }, { 101, T }, { 1003, T }, { 1, T + 100 } }),
        set.unlocked(fx.entries(), "Horde", { [2] = T }))
      assert.same(U({ { 101, T }, { 1003, T }, { 1, T + 100 }, { 102, T + 400 } }),
        set.unlocked(fx.entries(), "Horde", { [102] = T + 400 }))
    end)
  end)

  it("never writes to own or kept, and never calls their metamethods", function()
    local calls = 0
    local function spy()
      calls = calls + 1
    end
    local own = setmetatable(fx.entries(), { __index = spy, __newindex = spy, __len = spy })
    local kept = setmetatable({ [1] = T, [9] = T }, { __index = spy, __newindex = spy })
    local before, beforeK = fx.snapshot(own), fx.snapshot(kept)
    set.unlocked(own, "Alliance", kept)
    set.unlocked(own, "Horde", kept)
    assert.equal(0, calls)
    assert.is_true(fx.sameSnapshot(before, fx.snapshot(own)))
    assert.is_true(fx.sameSnapshot(beforeK, fx.snapshot(kept)))
  end)

  it("hostile own never throws", function()
    local owns = { "x", 7, fx.hostileTable(), fx.hostileProxy(),
      { fx.hostileTable(), fx.hostileProxy(), "x", { inn = 0 / 0, t = 0 / 0 } } }
    for i = 0, #owns do -- owns[0] is nil
      local ok, got = pcall(set.unlocked, owns[i], "Alliance", { [1] = T })
      assert.is_true(ok)
      assert.same({}, got)
    end
  end)

  it("returns a new table each call", function()
    local a, b = set.unlocked(fx.entries(), "Alliance"), set.unlocked(fx.entries(), "Alliance")
    assert.are_not.equal(a, b)
    a[1].t = 0
    assert.same(ALLIANCE, set.unlocked(fx.entries(), "Alliance"))
  end)
end)

-- ---------------------------------------------------------------------------
-- 6.5 canSeal.

describe("Cosmetics canSeal", function()
  local set = setF()
  local list = set.unlocked(fx.entries(), "Alliance")

  local function is(want, ...)
    local got = set.canSeal(...)
    assert.is_true(rawequal(want, got))
  end

  it("no seal is always allowed (with a valid time)", function()
    is(true, list, nil, T + 500)
    is(true, {}, nil, T)
    is(true, nil, nil, T)
  end)

  it("a seal unlocked no later than t", function()
    is(true, list, 1, T + 100)
    is(true, list, 1, T + 500)
    is(false, list, 1, T + 99) -- earned after
    is(true, list, 102, T + 500)
    is(true, list, 102, T + 400)
    is(false, list, 102, T + 399)
    is(true, list, 2, T + 400)
  end)

  it("a known seal that isn't unlocked", function()
    is(false, list, 104, T + 500)
  end)

  it("a quill is never a seal", function()
    is(false, list, 1001, T + 500)
    is(false, list, 1002, T + 500)
    is(false, list, 1003, T + 500)
  end)

  it("unknown or malformed seals", function()
    for _, seal in ipairs({ 3, 0, 0 / 0, 1 / 0, "1", 1.5, -1, 100, 999, 1000, true, {},
      fx.hostileTable(), fx.hostileProxy() }) do
      is(false, U({ { 3, T }, { 0, T }, { 100, T }, { 999, T }, { 1000, T } }), seal, T + 500)
      is(false, list, seal, T + 500)
    end
  end)

  it("t must be an integer in tMin..tMax", function()
    local times = { 0 / 0, 1 / 0, T + 0.5, LIMITS.tMax + 1, LIMITS.tMin - 1, "T",
      tostring(T + 500), fx.hostileProxy() }
    for i = 0, #times do -- times[0] is nil
      is(false, list, 1, times[i])
      is(false, list, nil, times[i]) -- fail closed even with no seal
    end
  end)

  it("hostile unlocked lists", function()
    is(false, nil, 1, T + 500)
    for _, u in ipairs({ "x", 7, fx.hostileTable(), fx.hostileProxy(),
      { { id = 1, t = tostring(T) } }, { { id = 1, t = 0 / 0 } }, { { id = 1, t = 1 / 0 } },
      { { id = 1, t = T + 0.5 } }, { { id = 1, t = LIMITS.tMin - 1 } }, { { id = "1", t = T } },
      { { id = 1.5, t = T } }, { "1" }, { 1 }, { fx.hostileTable() }, { fx.hostileProxy() },
      { nil, { id = 1, t = T } },
      setmetatable({}, { __index = function() return { id = 1, t = T } end }),
      { setmetatable({}, { __index = function(_, k) return k == "id" and 1 or T end }) },
    }) do
      local ok, got = pcall(set.canSeal, u, 1, T + 500)
      assert.is_true(ok)
      assert.is_true(rawequal(false, got))
    end
  end)

  it("a match further on in the list counts, up to the catalog count + 1 items", function()
    local miss = { id = 5, t = T }
    local big = {}
    for i = 1, 1000000 do
      big[i] = miss
    end
    is(false, big, 1, T + 500)
    big[11] = { id = 1, t = T } -- 9 records + 2: not read
    is(false, big, 1, T + 500)
    big[10] = { id = 1, t = T } -- 9 records + 1: read
    is(true, big, 1, T + 500)
    -- A later-dated duplicate before the good one doesn't stop the search.
    is(true, U({ { 1, T + 600 }, { 1, T + 100 } }), 1, T + 500)
  end)
end)

-- ---------------------------------------------------------------------------
-- 6.6 The real draft catalog.

describe("Data/Cosmetics (the draft catalog)", function()
  local DATA = NS.Data.Cosmetics

  it("binds with nothing invalid", function()
    assert.same({}, Cosmetics.invalid)
  end)

  it("holds the IDs and rules of spec 9 (update with the catalog)", function()
    local want = {
      [1] = { "seal", "Wayfarer's seal", { kind = "inns", n = 5 } },
      [2] = { "seal", "Innkeeper's seal", { kind = "all" } },
      [1001] = { "quill", "Traveler's quill", { kind = "inns", n = 10 } },
      [1002] = { "quill", "Owl-feather quill", { kind = "inns", n = 20 } },
      [1003] = { "quill", "Cartographer's quill", { kind = "continent" } },
    }
    assert.same(keys(want), keys(DATA))
    for id, w in pairs(want) do
      assert.same({ id = id, kind = w[1], name = w[2], rule = w[3] }, Cosmetics.info(id))
    end
  end)

  it("names are unique (case-insensitive)", function()
    local seen = {}
    for id, rec in pairs(DATA) do
      assert.is_nil(seen[rec.name:lower()], rec.name .. " at " .. id)
      seen[rec.name:lower()] = id
    end
  end)

  it("SEALS keys are integers in 1..sealMax: the catalog's seals plus one per zone", function()
    local want = {}
    for id, rec in pairs(DATA) do
      if rec.kind == "seal" then
        want[#want + 1] = id
      end
    end
    for _, z in pairs(NS.Data.Zones) do
      want[#want + 1] = z.seal
    end
    table.sort(want)
    assert.same(want, keys(Cosmetics.SEALS))
    for id in pairs(Cosmetics.SEALS) do
      assert.is_true(type(id) == "number" and id % 1 == 0 and id >= 1 and id <= LIMITS.sealMax)
    end
  end)

  it("with the shipped (unmarked) data, one signature at Calmbreeze unlocks no place rule",
    function()
      -- The beta's first signature earned 101, 1003 and 2 at once (#110). Not any more.
      local own = { { inn = 254089, t = T, phrase = { 1 } } }
      for _, faction in ipairs({ "Alliance", "Horde", false }) do
        assert.same({}, Cosmetics.unlocked(own, faction or nil))
      end
      -- An unlock already recorded at that signature's time is kept (the floor, spec 3.6).
      assert.same(U({ { 2, T }, { 101, T }, { 1003, T } }),
        Cosmetics.unlocked(own, "Alliance", { [101] = T, [1003] = T, [2] = T }))
    end)

  it("every rule is reachable: 40 neutral inns in 20 zones on 2 continents", function()
    -- Zone keys 1001..1020, apart from the continent keys: a map ID is one or the other.
    -- Every place marked complete (spec 3.11), or no place rule could be met.
    local inns, zones = {}, {}
    local conts = { [1] = { name = "East", complete = true },
      [2] = { name = "West", complete = true } }
    for z = 1, 20 do
      zones[1000 + z] = { name = "Zone " .. z, continent = z <= 10 and 1 or 2, seal = 100 + z,
        complete = true }
    end
    local own = {}
    for i = 1, 40 do
      inns[i] = { name = "Inn " .. i, zone = 1000 + math.ceil(i / 2) }
      own[i] = { inn = i, t = T + i }
    end
    local atlas = Collection.bind(inns, zones, conts, true)
    assert.same({}, atlas.invalid)
    assert.is_true(atlas.complete())
    local set = Cosmetics.bind(atlas, DATA)
    local got = {}
    for _, u in ipairs(set.unlocked(own, "Alliance")) do
      got[u.id] = true
    end
    for id in pairs(DATA) do
      assert.is_true(got[id] == true, "cosmetic " .. id .. " is out of reach")
    end
    for z = 1, 20 do
      assert.is_true(got[100 + z] == true, "zone seal " .. (100 + z))
    end
  end)
end)

-- ---------------------------------------------------------------------------
-- 6.7 With SyncProtocol and the real SEALS.

describe("Cosmetics.SEALS as SyncProtocol's seals", function()
  local OWNER = "Player-1234-0ABCDEF0"
  local MIRA = "Player-1234-0BBBBBB0"
  local SENDER = { guid = MIRA, name = "Mira Ashvale" }
  local ANCHOR = 1790089200 -- Tuesday 2026-09-22 15:00 UTC
  local NOW = 1794000000

  local function loadAll()
    local ns = {}
    load.file("Ledger.lua", ns, load.pure_env())
    load.file("Data/Cosmetics.lua", ns, load.pure_env())
    load.file("Collection.lua", ns, load.pure_env())
    load.file("Cosmetics.lua", ns, load.pure_env())
    load.file("SyncProtocol.lua", ns, load.pure_env())
    return ns
  end

  local function newCtx(ns, seals)
    return {
      now = NOW, selfGUID = OWNER,
      inns = { [1234] = true, [1235] = true, [1236] = true, [1237] = true, [1238] = true },
      phrases = { [1] = true },
      seals = seals,
      ledger = ns.Ledger.new({}, { guid = OWNER, name = "Aldric Stonebrook" }, ANCHOR),
      limiter = ns.SyncProtocol.newLimiter(),
      wantMemo = ns.SyncProtocol.newWantMemo(),
    }
  end

  -- Five entries at five inns, sealed 0 (none), 1, 2, 3 and 101.
  local MSG = "E1:1234," .. (NOW - 500) .. ",1,0"
    .. ";1235," .. (NOW - 400) .. ",1,1"
    .. ";1236," .. (NOW - 300) .. ",1,2"
    .. ";1237," .. (NOW - 200) .. ",1,3"
    .. ";1238," .. (NOW - 100) .. ",1,101"

  it("stores entries with a known seal and rejects an unknown one", function()
    local ns = loadAll()
    local ctx = newCtx(ns, ns.Cosmetics.SEALS)
    assert.is_true(rawequal(ctx.seals, ns.Cosmetics.SEALS))
    local res, reason = ns.SyncProtocol.receive(MSG, "PARTY", SENDER, ctx)
    assert.is_nil(reason)
    assert.same({ kind = "entries", added = 3, dup = 0, dropped = 0, rejected = 2 }, res)
    assert.same({
      { inn = 1234, t = NOW - 500, phrase = { 1 } },
      { inn = 1235, t = NOW - 400, phrase = { 1 }, seal = 1 },
      { inn = 1236, t = NOW - 300, phrase = { 1 }, seal = 2 },
    }, ctx.ledger:signerEntries(MIRA))
  end)

  it("with zone seals bound from F, the 101 entry is stored too", function()
    local ns = loadAll()
    local seals = ns.Cosmetics.bind(ns.Collection.bind(fx.places()), ns.Data.Cosmetics).SEALS
    local ctx = newCtx(ns, seals)
    assert.same({ kind = "entries", added = 4, dup = 0, dropped = 0, rejected = 1 },
      ns.SyncProtocol.receive(MSG, "PARTY", SENDER, ctx))
    local held = ctx.ledger:signerEntries(MIRA)
    assert.equal(4, #held)
    assert.equal(101, held[4].seal)
  end)
end)
