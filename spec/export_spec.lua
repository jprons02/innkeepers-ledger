-- Export: base64, build, encode and round trips through the real vendored libraries, the
-- privacy boundary, the size budget and hostile input (docs/specs/export.md, section 6).
-- Own entries, `earned` and traveler records come from SavedVariables, which a player can
-- edit, so every input here is hostile. Fixed times, never the clock. schemaOk runs on every
-- build result and every decoded export (through build() and decode() below).
local load = require("helpers.load")
local fx = require("helpers.places")
local exportLibs = require("helpers.export_libs")
local dec = require("helpers.export_decode")

local T = fx.T

-- A fresh ns: Ledger, Collection, Cosmetics, Export, as in the TOC (no Data: the tests
-- bind the fixture places and catalog themselves).
local function modules()
  local ns = {}
  load.file("Ledger.lua", ns, load.pure_env())
  load.file("Collection.lua", ns, load.pure_env())
  load.file("Cosmetics.lua", ns, load.pure_env())
  load.file("Export.lua", ns, load.pure_env())
  return ns
end

local NS = modules()
local Export, Ledger = NS.Export, NS.Ledger
local LIMITS = Ledger.LIMITS
local LIBS = exportLibs.new()
local CODEC = LIBS.codec

-- A negative zero, made at run time (a `-0` literal may fold into the constant 0).
local ZERO = 0
local NEG_ZERO = -ZERO

local REASONS = {
  input = true, flavor = true, exported = true, addon = true, me = true, collection = true,
  entries = true, cosmetics = true, travelers = true, too_large = true,
}

-- ---------------------------------------------------------------------------
-- Helpers.

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

-- Export.build, with schemaOk on every result.
local function build(input)
  local data, reason = Export.build(input)
  if data ~= nil then
    local ok, where = dec.schemaOk(data)
    assert(ok, "schemaOk failed on a build result at " .. tostring(where))
    assert(reason == nil)
  else
    assert(REASONS[reason], "unknown reason " .. tostring(reason))
  end
  return data, reason
end

local function buildOk(input)
  local data, reason = build(input)
  assert(data, "build refused: " .. tostring(reason))
  return data
end

-- The test-only decoder with the real libraries, with schemaOk on every result.
local function decode(str, libs)
  local data, reason = dec.decode(str, libs or LIBS)
  if data ~= nil then
    local ok, where = dec.schemaOk(data)
    assert(ok, "schemaOk failed on a decoded export at " .. tostring(where))
  end
  return data, reason
end

local function exportOk(input, codec)
  local s, reason = Export.string(input, codec or CODEC)
  assert(s, "Export.string refused: " .. tostring(reason))
  return s
end

-- Every table reachable from v (keys and values), each once.
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

-- True if no table is reachable twice from v (by any path).
local function noSharedTables(v)
  local seen = {}
  local function walk(x)
    if type(x) ~= "table" then
      return true
    end
    if seen[x] then
      return false
    end
    seen[x] = true
    for k, y in next, x do
      if not walk(k) or not walk(y) then
        return false
      end
    end
    return true
  end
  return walk(v)
end

-- Every string key and value reachable from v.
local function stringsOf(v, out)
  out = out or {}
  if type(v) == "string" then
    out[#out + 1] = v
  elseif type(v) == "table" then
    for k, x in next, v do
      stringsOf(k, out)
      stringsOf(x, out)
    end
  end
  return out
end

-- A codec whose serialize records what the real one wrote.
local function spyCodec()
  local spy = { serialized = nil, compressCalls = 0 }
  spy.codec = {
    serialize = function(v)
      spy.serialized = LIBS.serializer:Serialize(v)
      return spy.serialized
    end,
    compress = function(s)
      spy.compressCalls = spy.compressCalls + 1
      return (LIBS.deflate:CompressDeflate(s))
    end,
  }
  return spy
end

-- ---------------------------------------------------------------------------
-- Fixtures F and F+T (spec 6).

local ME = "Player-1234-0ABCDEF0"
local MIRA = "Player-1234-0BBBBBB0"
local ZOE = "Player-1234-0CCCCCC0"
local ZOE_NAME = "Zo\195\171-Azjol-Nerub" -- UTF-8 "Zoë"

local function F()
  return {
    flavor = "forever",
    exported = T + 1000,
    addon = "1.0.0",
    me = { guid = ME, name = "Aldric" },
    own = {
      { inn = 5001, t = T, phrase = { 101 } },
      { inn = 5201, t = T + 100, phrase = { 3, 1201 }, seal = 1 },
      { inn = 5003, t = T + 200, phrase = { 101, 1201, 501, 3, 1202 } },
    },
    progress = {
      faction = "Alliance", signed = 2, total = 3,
      byContinent = { [1] = { signed = 2, total = 3 } },
      byZone = {
        [10] = { signed = 1, total = 2, continent = 1 },
        [20] = { signed = 1, total = 1, continent = 1, done = T + 100 },
      },
      inns = {
        [5001] = { zone = 10, open = true, count = 2, first = T, last = T + 200 },
        [5201] = { zone = 20, open = true, count = 1, first = T + 100, last = T + 100 },
      },
      unknown = 0,
      truncated = false,
    },
    unlocked = { { id = 1101, t = T }, { id = 103, t = T + 100 } },
  }
end

local function FT()
  local input = F()
  input.travelers = {
    { guid = MIRA, name = "Mira Ashvale", met = T + 50,
      entries = { { inn = 5001, t = T + 40, phrase = { 4, 5 }, seal = 2 } } },
    { guid = ZOE, name = ZOE_NAME, met = T + 60,
      entries = { { inn = 5201, t = T + 45, phrase = { 7 } } } },
  }
  return input
end

local function EXPECTED_F()
  return {
    v = 1,
    flavor = "forever",
    exported = T + 1000,
    addon = "1.0.0",
    me = { guid = ME, name = "Aldric" },
    collection = {
      faction = "Alliance", signed = 2, total = 3,
      byContinent = { [1] = { signed = 2, total = 3 } },
      byZone = {
        [10] = { signed = 1, total = 2, continent = 1 },
        [20] = { signed = 1, total = 1, continent = 1, done = T + 100 },
      },
    },
    cosmetics = { { id = 1101, t = T }, { id = 103, t = T + 100 } },
    entries = {
      { inn = 5001, t = T, phrase = { 101 } },
      { inn = 5201, t = T + 100, phrase = { 3, 1201 }, seal = 1 },
      { inn = 5003, t = T + 200, phrase = { 101, 1201, 501, 3, 1202 } },
    },
  }
end

local function EXPECTED_F_T()
  local expected = EXPECTED_F()
  expected.travelers = {
    { guid = ZOE, name = ZOE_NAME, met = T + 60,
      entries = { { inn = 5201, t = T + 45, phrase = { 7 } } } },
    { guid = MIRA, name = "Mira Ashvale", met = T + 50,
      entries = { { inn = 5001, t = T + 40, phrase = { 4, 5 }, seal = 2 } } },
  }
  return expected
end

-- Export.string(F()) under Lua 5.1 with the vendored libraries (spec 6.3 golden). If this
-- breaks after a library or interpreter change while decode(GOLDEN_F) still deep-equals
-- EXPECTED_F, regenerate it and say so in the PR.
local GOLDEN_F = "!IL1!dZHRTvMwDIWfaFOSbUJcjvFzGSGFKy4shdYbkbJkSk3F3h47YaVj/L1o0tjnO84paHgB"
  .. "d0R5J8+r28a+hA7c4SP04J6jP2NZaLNaL9T2Yff470kBgfN9nxM4vVRLBW4Eq8F1eTgihW5gmK1cJlitFdeIN3f3"
  .. "qj0MsGaqq9W8rGuZhBYjdhTYhjvfzq85YQUr+R7CIWFfbSmTjwJkSaKQMAmtevynlXe90Oaev8U0dfN4e98G4XBi"
  .. "8KnDH6qR2XaT9nLzWXnCUMPi5ykXqhNVey2JOBaXgLPoUgK7UbfZudN78UOLQtJow37nWUXmWqRvRCtpt9pUrRuw"
  .. "ZUJSmDlf/Rbzp/OEEeRG1nXb1mNzufE++jEXXnPBEQsfwdc="

-- ---------------------------------------------------------------------------

describe("Export module", function()
  it("has the spec 3.6 constants", function()
    assert.equal(1, Export.VERSION)
    assert.equal("!IL1!", Export.PREFIX)
    assert.same({ forever = true }, Export.FLAVORS)
    assert.same({ ownMax = 10000, cosmeticsMax = 1200, mapItemsMax = 1000, addonBytes = 32,
      serializedMax = 4194304 }, Export.LIMITS)
  end)

  it("changing the exported FLAVORS and LIMITS changes nothing inside", function()
    local ns = modules()
    ns.Export.FLAVORS.retail = true
    ns.Export.LIMITS.ownMax = 1
    ns.Export.LIMITS.addonBytes = 1
    local input = F()
    assert.same(EXPECTED_F(), ns.Export.build(input))
    input.flavor = "retail"
    assert.same({ nil, "flavor" }, { ns.Export.build(input) })
  end)

  it("raises at load without Ledger or Collection (packaging bugs)", function()
    assert.has_error(function()
      load.file("Export.lua", {}, load.pure_env())
    end)
    assert.has_error(function()
      local ns = {}
      load.file("Ledger.lua", ns, load.pure_env())
      load.file("Export.lua", ns, load.pure_env())
    end)
  end)

  it("leaves no LibStub global behind (the libraries load in a private environment)", function()
    exportLibs.new()
    assert.is_nil(rawget(_G, "LibStub"))
    assert.is_nil(rawget(_G, "LibDeflate"))
  end)
end)

-- ---------------------------------------------------------------------------
-- 6.1 Base64

describe("Export.base64 (6.1)", function()
  -- Park-Miller, exact in doubles.
  local function rng(seed)
    return function(n)
      seed = seed * 16807 % 2147483647
      return seed % n
    end
  end

  it("matches the RFC 4648 section 10 vectors", function()
    local vectors = {
      { "", "" }, { "f", "Zg==" }, { "fo", "Zm8=" }, { "foo", "Zm9v" },
      { "foob", "Zm9vYg==" }, { "fooba", "Zm9vYmE=" }, { "foobar", "Zm9vYmFy" },
    }
    for _, v in ipairs(vectors) do
      assert.equal(v[2], Export.base64(v[1]))
    end
  end)

  it("uses the alphabet's edges", function()
    assert.equal("AAAA", Export.base64("\0\0\0"))
    assert.equal("////", Export.base64("\255\255\255"))
    assert.equal("+/8=", Export.base64("\251\255"))
  end)

  it("round-trips all 256 byte values and seeded random strings of length 0..64", function()
    local all = {}
    for b = 0, 255 do
      all[#all + 1] = string.char(b)
    end
    local cases = { table.concat(all) }
    local r = rng(20260928)
    for n = 0, 64 do
      local bytes = {}
      for i = 1, n do
        bytes[i] = string.char(r(256))
      end
      cases[#cases + 1] = table.concat(bytes)
    end
    for _, s in ipairs(cases) do
      local out = Export.base64(s)
      assert.equal(4 * math.ceil(#s / 3), #out)
      assert.truthy(out:match("^[A-Za-z0-9+/]*=?=?$"))
      assert.equal(s, dec.unbase64(out))
    end
  end)

  it("has a test-only decoder that is strict (unbase64)", function()
    assert.equal("f", dec.unbase64("Zg=="))
    assert.equal("", dec.unbase64(""))
    for _, bad in ipairs({ "Zg=", "Zm9", "Zm9vY", "Zm-v", "Zm_v", "Zm v", "Zm\nv",
      "Zg==Zm9v", "Z=9v", "Z===", "====", "Zh==", "Zm9=", 7 }) do
      assert.is_nil(dec.unbase64(bad), tostring(bad))
    end
  end)

  it("returns nil for anything but a string, without throwing", function()
    for _, v in ipairs({ 7, {}, fx.hostileTable(), fx.hostileProxy(), true }) do
      assert.is_nil(Export.base64(v))
    end
    assert.is_nil(Export.base64(nil))
  end)

  it("round-trips a 300 KB input (joined once)", function()
    local r = rng(7)
    local bytes = {}
    for i = 1, 300 * 1024 do
      bytes[i] = string.char(r(256))
    end
    local s = table.concat(bytes)
    local started = os.clock()
    local out = Export.base64(s)
    local took = os.clock() - started
    assert.equal(409600, #out)
    assert.equal(s, dec.unbase64(out))
    print(string.format("\nexport: base64 of 300 KB took %.3f s", took))
  end)
end)

-- ---------------------------------------------------------------------------
-- 6.2 build

describe("Export.build (6.2)", function()
  it("builds F into EXPECTED_F exactly: no travelers, no inns/unknown/truncated", function()
    local data = buildOk(F())
    assert.same(EXPECTED_F(), data)
    assert.is_nil(rawget(data, "travelers"))
    for _, key in ipairs({ "inns", "unknown", "truncated" }) do
      assert.is_nil(rawget(data.collection, key))
    end
    assert.is_nil(rawget(data.entries[1], "seal"))
    assert.is_nil(rawget(data.entries[3], "seal"))
  end)

  it("builds F+T into EXPECTED_F_T exactly (Zoë, then Mira)", function()
    assert.same(EXPECTED_F_T(), buildOk(FT()))
  end)

  describe("opt-in", function()
    it("has no travelers key when travelers is nil", function()
      local input = FT()
      input.travelers = nil
      assert.is_nil(rawget(buildOk(input), "travelers"))
    end)

    it("has an empty travelers array when it's an empty table", function()
      local input = F()
      input.travelers = {}
      assert.same({}, buildOk(input).travelers)
    end)

    it("refuses travelers that aren't a table", function()
      for _, v in ipairs({ "yes", 1, true }) do
        local input = F()
        input.travelers = v
        assert.same({ nil, "travelers" }, { build(input) })
      end
    end)
  end)

  describe("orders", function()
    it("gives a deep-equal result for reversed and seeded-shuffled inputs", function()
      local expected = EXPECTED_F_T()
      for seed = 1, 20 do
        local input = FT()
        local reorder = seed == 1 and fx.reversed or function(arr)
          return fx.shuffled(arr, seed)
        end
        input.own = reorder(input.own)
        input.unlocked = reorder(input.unlocked)
        input.travelers = reorder(input.travelers)
        for _, tr in ipairs(input.travelers) do
          tr.entries[2] = { inn = 5301, t = T + 30, phrase = { 9 } }
          tr.entries = reorder(tr.entries)
        end
        local want = deepcopy(expected)
        for _, tr in ipairs(want.travelers) do
          table.insert(tr.entries, 1, { inn = 5301, t = T + 30, phrase = { 9 } })
        end
        assert.same(want, buildOk(input))
      end
    end)

    it("orders travelers with equal met by GUID bytes (A before a)", function()
      local input = F()
      local e = { { inn = 5001, t = T, phrase = { 1 } } }
      input.travelers = {
        { guid = "Player-1-0a", name = "Lower", met = T, entries = deepcopy(e) },
        { guid = "Player-1-0A", name = "Upper", met = T, entries = deepcopy(e) },
        { guid = "Player-1-0B", name = "Later", met = T + 1, entries = deepcopy(e) },
        { guid = "Player-1-0AB", name = "Longer", met = T, entries = deepcopy(e) },
      }
      local out = buildOk(input).travelers
      -- A GUID that is a prefix of another comes first.
      assert.same({ "Player-1-0B", "Player-1-0A", "Player-1-0AB", "Player-1-0a" },
        { out[1].guid, out[2].guid, out[3].guid, out[4].guid })
    end)

    it("orders own entries with equal t by inn", function()
      local input = F()
      input.own = {
        { inn = 7, t = T, phrase = { 1 } }, { inn = 3, t = T, phrase = { 1 } },
      }
      local out = buildOk(input).entries
      assert.same({ 3, 7 }, { out[1].inn, out[2].inn })
    end)
  end)

  describe("dedupe", function()
    it("keeps the first own entry of a repeated (inn, t)", function()
      local input = F()
      input.own[4] = { inn = 5001, t = T, phrase = { 999 } }
      assert.same(EXPECTED_F().entries, buildOk(input).entries)
    end)

    it("keeps the smaller t of a repeated cosmetic id, in either order", function()
      local input = F()
      input.unlocked[3] = { id = 1101, t = T + 100 } -- later: ignored
      input.unlocked[4] = { id = 103, t = T + 50 }   -- earlier: replaces T + 100
      assert.same({ { id = 1101, t = T }, { id = 103, t = T + 50 } },
        buildOk(input).cosmetics)
    end)

    it("keeps the first traveler of a repeated GUID", function()
      local input = FT()
      input.travelers[3] = { guid = MIRA, name = "Other", met = T + 90,
        entries = { { inn = 1, t = T, phrase = { 1 } } } }
      assert.same(EXPECTED_F_T().travelers, buildOk(input).travelers)
    end)

    it("dedupes a traveler's entries by (inn, t)", function()
      local input = FT()
      local entries = input.travelers[1].entries
      entries[2] = { inn = 5001, t = T + 40, phrase = { 1 } }
      assert.same(EXPECTED_F_T().travelers, buildOk(input).travelers)
    end)
  end)

  describe("required fields", function()
    local function refuses(reason, mutate)
      local input = FT()
      local replaced = mutate(input)
      if replaced ~= nil then
        input = replaced
      end
      local data, got = build(input)
      assert.is_nil(data)
      assert.equal(reason, got)
    end

    it("input", function()
      for _, v in ipairs({ "x", fx.hostileProxy(), 7 }) do
        refuses("input", function() return v end)
      end
      assert.same({ nil, "input" }, { build(nil) })
    end)

    it("flavor", function()
      for _, v in ipairs({ "Forever", "retail", fx.hostileTable() }) do
        refuses("flavor", function(i) i.flavor = v end)
      end
      refuses("flavor", function(i) i.flavor = nil end)
    end)

    it("exported", function()
      for _, v in ipairs({ LIMITS.tMin - 1, LIMITS.tMax + 1, 0 / 0, 1 / 0, T + 0.5,
        "1790000000" }) do
        refuses("exported", function(i) i.exported = v end)
      end
    end)

    it("addon", function()
      for _, v in ipairs({ "", ("1"):rep(33), "1.0 beta", "v1|r", "a/b", "x:y", "1.0\195\169",
        "a\0", 1 }) do
        refuses("addon", function(i) i.addon = v end)
      end
      local input = F()
      input.addon = ("1"):rep(32)
      assert.equal(("1"):rep(32), buildOk(input).addon)
      input.addon = "Az09._+-"
      assert.equal("Az09._+-", buildOk(input).addon)
    end)

    it("me", function()
      refuses("me", function(i) i.me = nil end)
      refuses("me", function(i) i.me = {} end)
      refuses("me", function(i) i.me = "x" end)
      refuses("me", function(i) i.me.guid = "player-1-AB" end)
      refuses("me", function(i) i.me.guid = "Player-1-" .. ("A"):rep(32) end) -- 41 bytes
    end)

    it("collection", function()
      refuses("collection", function(i) i.progress = nil end)
      refuses("collection", function(i) i.progress.signed = 4 end)
      refuses("collection", function(i) i.progress.total = 0 / 0 end)
      refuses("collection", function(i) i.progress.signed = -1 end)
      refuses("collection", function(i) i.progress.total = LIMITS.innMax + 1 end)
      refuses("collection", function(i) i.progress.faction = "Neutral" end)
      refuses("collection", function(i) i.progress.faction = 1 end)
      refuses("collection", function(i)
        i.progress.signed = 3
        i.progress.done = T + 0.5
      end)
      -- done only when signed == total >= 1 (spec 4.1).
      refuses("collection", function(i) i.progress.done = T end)
      refuses("collection", function(i)
        i.progress.signed, i.progress.total, i.progress.done = 0, 0, T
      end)
      refuses("collection", function(i) i.progress.byContinent = nil end)
      refuses("collection", function(i) i.progress.byZone = "x" end)
    end)

    it("entries", function()
      refuses("entries", function(i) i.own = nil end)
      refuses("entries", function(i) i.own = 7 end)
    end)

    it("cosmetics", function()
      refuses("cosmetics", function(i) i.unlocked = nil end)
      refuses("cosmetics", function(i) i.unlocked = "x" end)
    end)

    it("reports the first failing field in the spec's order", function()
      refuses("flavor", function(i)
        i.flavor, i.exported, i.own = nil, nil, nil
      end)
      refuses("collection", function(i)
        i.progress.signed, i.own, i.travelers = 9, nil, 1
      end)
    end)

    it("accepts a missing faction and a valid done", function()
      local input = F()
      input.progress.faction = nil
      input.progress.signed = 3
      input.progress.done = T + 200
      local c = buildOk(input).collection
      assert.is_nil(rawget(c, "faction"))
      assert.equal(T + 200, c.done)
    end)
  end)

  describe("items left out", function()
    it("me.name with | or over 96 bytes, or not a string", function()
      for _, v in ipairs({ "Al|dric", ("A"):rep(97), 7, fx.hostileProxy() }) do
        local input = F()
        input.me.name = v
        local me = buildOk(input).me
        assert.is_nil(rawget(me, "name"))
        assert.equal(ME, me.guid)
      end
    end)

    it("own entries that fail validEntry; siblings kept", function()
      local bad = {
        { inn = 0, t = T, phrase = { 1 } },
        { inn = 1, t = 0 / 0, phrase = { 1 } },
        { inn = 1, t = T, phrase = { 1, 2, 3, 4, 5, 6 } },
        { inn = 1, t = T, phrase = { [1] = 1, [3] = 3 } },
        { inn = 1, t = T, phrase = { 1 }, seal = 0 },
        { inn = 1, t = T, phrase = { 1 }, seal = 1000 },
        { inn = 1, t = T, phrase = { 1 }, extra = true },
        "x",
        7,
        fx.hostileProxy(),
      }
      for _, e in ipairs(bad) do
        local input = F()
        table.insert(input.own, 2, e)
        assert.same(EXPECTED_F().entries, buildOk(input).entries)
      end
    end)

    it("cosmetics with a bad id or t; siblings kept", function()
      local bad = {
        { id = 0, t = T }, { id = 10000, t = T }, { id = 1.5, t = T },
        { id = 5, t = LIMITS.tMin - 1 }, { id = 5, t = 0 / 0 }, "x", fx.hostileProxy(),
      }
      for _, c in ipairs(bad) do
        local input = F()
        table.insert(input.unlocked, 2, c)
        assert.same(EXPECTED_F().cosmetics, buildOk(input).cosmetics)
      end
    end)

    it("zones with a bad key or value; siblings kept", function()
      local cases = {
        { key = 0 }, { key = 1000000 }, { key = "10" }, { key = 1.5 }, { key = -1 },
        { key = 30, value = { signed = 2, total = 1, continent = 1 } },
        { key = 30, value = { signed = 1, total = 1 } },
        { key = 30, value = { signed = 1, total = 1, continent = 0 } },
        { key = 30, value = { signed = 1, total = 1, continent = 1.5 } },
        { key = 30, value = { signed = 1, total = 1, continent = 1, done = T + 0.5 } },
        { key = 30, value = { signed = 0 / 0, total = 1, continent = 1 } },
        -- done only when signed == total >= 1 (spec 4.1).
        { key = 30, value = { signed = 1, total = 2, continent = 1, done = T } },
        { key = 30, value = { signed = 0, total = 0, continent = 1, done = T } },
        -- A continent that isn't a kept byContinent key (spec 4.1).
        { key = 30, value = { signed = 1, total = 1, continent = 2 } },
        { key = 30, value = "x" },
        { key = 30, value = fx.hostileProxy() },
      }
      for _, case in ipairs(cases) do
        local input = F()
        input.progress.byZone[case.key] = case.value or { signed = 1, total = 1, continent = 1 }
        assert.same(EXPECTED_F().collection, buildOk(input).collection)
      end
    end)

    it("continents with a bad key or value; siblings kept", function()
      local cases = {
        { key = 0 }, { key = 1000000 }, { key = "1" }, { key = 1.5 },
        { key = 3, value = { signed = 2, total = 1 } },
        { key = 3, value = { signed = 1, total = 1, done = T + 0.5 } },
        { key = 3, value = { signed = 1 } },
        { key = 3, value = { signed = 1, total = 2, done = T } },
        { key = 3, value = { signed = 0, total = 0, done = T } },
        { key = 3, value = "x" },
        { key = 3, value = fx.hostileProxy() },
      }
      for _, case in ipairs(cases) do
        local input = F()
        input.progress.byContinent[case.key] = case.value or { signed = 1, total = 1 }
        assert.same(EXPECTED_F().collection, buildOk(input).collection)
      end
    end)

    it("keeps a map item whose done comes with signed == total >= 1", function()
      local input = F()
      input.progress.byZone[30] = { signed = 2, total = 2, continent = 1, done = T }
      input.progress.byContinent[3] = { signed = 1, total = 1, done = T + 5 }
      local c = buildOk(input).collection
      assert.same({ signed = 2, total = 2, continent = 1, done = T }, c.byZone[30])
      assert.same({ signed = 1, total = 1, done = T + 5 }, c.byContinent[3])
    end)

    it("zones of a continent that was left out go with it", function()
      local input = F()
      input.progress.byContinent[1] = { signed = 9, total = 1 }
      local c = buildOk(input).collection
      assert.same({}, c.byContinent)
      assert.same({}, c.byZone)
    end)

    it("travelers that fail a check; siblings kept", function()
      local e = function() return { { inn = 1, t = T, phrase = { 1 } } } end
      local bad = {
        { guid = "player-1-AB", name = "Bad", met = T, entries = e() },
        { guid = ME, name = "Me", met = T, entries = e() },
        { guid = "Player-1-0D", name = "x|y", met = T, entries = e() },
        { guid = "Player-1-0D", name = "Nan", met = 0 / 0, entries = e() },
        { guid = "Player-1-0D", name = "Nobody", met = T, entries = { { inn = 0 } } },
        { guid = "Player-1-0D", name = "Nobody", met = T, entries = {} },
        { guid = "Player-1-0D", name = "Nobody", met = T, entries = "x" },
        { guid = "Player-1-0D", name = "Nobody", met = T },
        "x",
        fx.hostileProxy(),
      }
      for _, tr in ipairs(bad) do
        local input = FT()
        table.insert(input.travelers, 2, tr)
        assert.same(EXPECTED_F_T().travelers, buildOk(input).travelers)
      end
    end)
  end)

  describe("limits", function()
    local function ownN(n)
      local own = {}
      for i = 1, n do
        own[i] = { inn = 1 + i % 100, t = T + i, phrase = { 1 } }
      end
      return own
    end

    local function traveler(i, n)
      local entries = {}
      for j = 1, n do
        entries[j] = { inn = j, t = T + j, phrase = { 1 } }
      end
      return { guid = string.format("Player-1-%08X", i), name = "Traveler", met = T,
        entries = entries }
    end

    it("10 000 own items pass; 10 001 is too_large", function()
      local input = F()
      input.own = ownN(10000)
      assert.equal(10000, #buildOk(input).entries)
      input.own[10001] = { inn = 1, t = T, phrase = { 1 } }
      assert.same({ nil, "too_large" }, { build(input) })
    end)

    it("counts invalid items too", function()
      local input = F()
      input.own = ownN(10000)
      input.own[10001] = "junk"
      assert.same({ nil, "too_large" }, { build(input) })
    end)

    it("1 200 cosmetics pass; 1 201 is too_large", function()
      local input = F()
      input.unlocked = {}
      for i = 1, 1200 do
        input.unlocked[i] = { id = i, t = T }
      end
      assert.equal(1200, #buildOk(input).cosmetics)
      input.unlocked[1201] = { id = 1201, t = T }
      assert.same({ nil, "too_large" }, { build(input) })
    end)

    it("1 000 zones or continents pass; 1 001 is too_large", function()
      for _, map in ipairs({ "byZone", "byContinent" }) do
        local input = F()
        local m = {}
        for k = 1, 1000 do
          m[k] = { signed = 0, total = 1, continent = 1 }
          if map == "byContinent" then
            m[k].continent = nil
          end
        end
        input.progress[map] = m
        buildOk(input)
        m[1001] = "junk"
        assert.same({ nil, "too_large" }, { build(input) }, map)
      end
    end)

    it("3 000 traveler records pass; 3 001 is too_large", function()
      local input = F()
      input.travelers = {}
      for i = 1, 3000 do
        input.travelers[i] = traveler(i, 1)
      end
      assert.equal(3000, #buildOk(input).travelers)
      input.travelers[3001] = "junk"
      assert.same({ nil, "too_large" }, { build(input) })
    end)

    it("3 000 traveler entries in all pass; 3 001 is too_large", function()
      local input = F()
      input.travelers = {}
      for i = 1, 75 do
        input.travelers[i] = traveler(i, 40)
      end
      assert.equal(75, #buildOk(input).travelers)
      input.travelers[76] = traveler(76, 1)
      assert.same({ nil, "too_large" }, { build(input) })
    end)

    it("40 entries in one record pass; 41 is too_large", function()
      local input = F()
      input.travelers = { traveler(1, 40) }
      assert.equal(40, #buildOk(input).travelers[1].entries)
      input.travelers = { traveler(1, 41) }
      assert.same({ nil, "too_large" }, { build(input) })
    end)

    it("stops reading at a hole: items past it don't count", function()
      local input = F()
      input.own = ownN(10)
      for i = 12, 10020 do
        input.own[i] = { inn = 1, t = T + i, phrase = { 1 } }
      end
      assert.equal(10, #buildOk(input).entries)
    end)
  end)

  it("writes a negative zero count as 0 (never -0)", function()
    assert.equal(-math.huge, 1 / NEG_ZERO)
    local input = F()
    input.progress.signed, input.progress.total = NEG_ZERO, 3
    input.progress.byZone[10].signed = NEG_ZERO
    input.progress.byContinent[5] = { signed = NEG_ZERO, total = NEG_ZERO }
    input.progress.byZone[50] = { signed = NEG_ZERO, total = 1, continent = 5 }
    local c = buildOk(input).collection
    for _, v in ipairs({ c.signed, c.byZone[10].signed, c.byContinent[5].signed,
      c.byContinent[5].total, c.byZone[50].signed }) do
      assert.equal(math.huge, 1 / v)
    end
    local spy = spyCodec()
    exportOk(input, spy.codec)
    assert.is_nil(spy.serialized:find("^N-", 1, true))
  end)

  describe("purity and safety", function()
    it("never writes an input; no output table is an input table or appears twice", function()
      local input = FT()
      local before = fx.snapshot(input, 8)
      local data = buildOk(input)
      assert.is_true(fx.sameSnapshot(before, fx.snapshot(input, 8)))
      local inputs, outputs = tablesOf(input), tablesOf(data)
      for t in pairs(outputs) do
        assert.is_nil(inputs[t])
      end
      assert.is_true(noSharedTables(data))
      -- Two builds share nothing either.
      for t in pairs(tablesOf(buildOk(input))) do
        assert.is_nil(outputs[t])
      end
    end)

    it("never runs a metamethod of an input table", function()
      local input = FT()
      local fired = {}
      local function hostile(event)
        return function()
          fired[#fired + 1] = event
          error("metamethod " .. event .. " fired")
        end
      end
      for t in pairs(tablesOf(input)) do
        setmetatable(t, {
          __index = hostile("__index"), __newindex = hostile("__newindex"),
          __len = hostile("__len"), __call = hostile("__call"),
          __eq = hostile("__eq"), __lt = hostile("__lt"), __le = hostile("__le"),
        })
      end
      assert.same(EXPECTED_F_T(), buildOk(input))
      assert.same({}, fired)
    end)

    it("gives a reason or leaves an item out for a hidden-value stand-in anywhere", function()
      local paths = {}
      local function collect(t, path)
        for k, v in next, t do
          local p = { unpack(path) }
          p[#p + 1] = k
          paths[#paths + 1] = p
          if type(v) == "table" then
            collect(v, p)
          end
        end
      end
      collect(FT(), {})
      assert.is_true(#paths > 60)
      for _, path in ipairs(paths) do
        for _, standIn in ipairs({ fx.hostileTable(), fx.hostileProxy() }) do
          local input = FT()
          local parent = input
          for i = 1, #path - 1 do
            parent = parent[path[i]]
          end
          parent[path[#path]] = standIn
          local ok, data, reason = pcall(build, input)
          assert(ok, "threw at " .. table.concat(path, ".") .. ": " .. tostring(data))
          assert(data ~= nil or REASONS[reason])
        end
      end
    end)

    it("leaves out an item that points back at the input (a cycle), without recursing", function()
      local input = F()
      input.progress.byZone[10] = input.progress
      local data = buildOk(input)
      assert.same({ [20] = EXPECTED_F().collection.byZone[20] }, data.collection.byZone)
      input = F()
      input.own[2].phrase = input.own
      input.own[4] = input
      assert.equal(2, #buildOk(input).entries)
    end)
  end)
end)

-- ---------------------------------------------------------------------------
-- The test-only schema check itself (spec 3.8): it must refuse what build must never write.

describe("schemaOk", function()
  local function breaks(mutate)
    local data = EXPECTED_F_T()
    mutate(data)
    return not dec.schemaOk(data)
  end

  it("passes EXPECTED_F and EXPECTED_F_T", function()
    assert.is_true(dec.schemaOk(EXPECTED_F()))
    assert.is_true(dec.schemaOk(EXPECTED_F_T()))
  end)

  it("refuses done without signed == total >= 1, at the top and in each map", function()
    assert.is_true(breaks(function(d) d.collection.done = T end))
    assert.is_true(breaks(function(d) d.collection.byZone[10].done = T end))
    assert.is_true(breaks(function(d) d.collection.byContinent[1].done = T end))
    assert.is_true(breaks(function(d)
      d.collection.byContinent[2] = { signed = 0, total = 0, done = T }
    end))
    assert.is_false(breaks(function(d)
      d.collection.byContinent[2] = { signed = 4, total = 4, done = T }
    end))
  end)

  it("refuses a negative zero count", function()
    assert.is_true(breaks(function(d) d.collection.signed = NEG_ZERO end))
    assert.is_true(breaks(function(d) d.collection.byZone[20].total = NEG_ZERO end))
  end)

  it("refuses an extra key, a bad order and a traveler that is the owner", function()
    assert.is_true(breaks(function(d) d.extra = 1 end))
    assert.is_true(breaks(function(d)
      d.entries[1], d.entries[2] = d.entries[2], d.entries[1]
    end))
    assert.is_true(breaks(function(d) d.travelers[1].guid = ME end))
  end)
end)

-- ---------------------------------------------------------------------------
-- 6.3 Encode and round trip

describe("Export.encode and Export.string (6.3)", function()
  local PATTERN = "^!IL1![A-Za-z0-9+/]*=?=?$"

  local function wellFormed(s)
    assert.truthy(s:match(PATTERN), s)
    assert.equal(0, (#s - #"!IL1!") % 4)
    assert.is_nil(s:find("[\r\n |]"))
  end

  it("round-trips F and F+T through the real libraries", function()
    for _, case in ipairs({ { F, EXPECTED_F }, { FT, EXPECTED_F_T } }) do
      local s = exportOk(case[1]())
      wellFormed(s)
      local data = decode(s)
      assert.same(case[2](), data)
      assert.equal(1, data.v)
    end
  end)

  it("keeps names byte for byte: a space, UTF-8, a realm suffix and ' in a realm", function()
    local input = FT()
    input.me.name = "Aldric-Quel'Thalas"
    local spy = spyCodec()
    local data = decode(exportOk(input, spy.codec))
    assert.equal("Aldric-Quel'Thalas", data.me.name)
    assert.equal(ZOE_NAME, data.travelers[1].name)
    assert.equal("Mira Ashvale", data.travelers[2].name)
    assert.truthy(spy.serialized:find("^SMira~`Ashvale", 1, true))
    assert.truthy(spy.serialized:find("^S" .. ZOE_NAME, 1, true))
  end)

  it("writes integers only: no floats, booleans or nils in the serialized text", function()
    local spy = spyCodec()
    exportOk(FT(), spy.codec)
    local s = spy.serialized
    assert.equal("^1", s:sub(1, 2))
    assert.equal("^^", s:sub(-2))
    for _, code in ipairs({ "^F", "^f", "^B", "^b", "^Z" }) do
      assert.is_nil(s:find(code, 1, true), code)
    end
    local numbers = 0
    for n in s:gmatch("%^N([^%^]*)") do
      assert.truthy(n:match("^%d+$"), n)
      numbers = numbers + 1
    end
    assert.is_true(numbers > 40)
  end)

  describe("golden", function()
    it("decodes GOLDEN_F to EXPECTED_F (the v1 contract)", function()
      assert.same(EXPECTED_F(), decode(GOLDEN_F))
    end)

    it("encodes F to GOLDEN_F byte for byte (a change detector)", function()
      assert.equal(GOLDEN_F, exportOk(F()))
    end)

    it("encodes F twice in one run to equal strings", function()
      assert.equal(exportOk(F()), exportOk(F()))
    end)
  end)

  it("encodes an empty ledger to empty arrays and maps", function()
    local input = F()
    input.own = {}
    input.unlocked = {}
    input.progress = { signed = 0, total = 0, byContinent = {}, byZone = {} }
    local s = exportOk(input)
    wellFormed(s)
    local data = decode(s)
    assert.same({}, data.entries)
    assert.same({}, data.cosmetics)
    assert.same({ signed = 0, total = 0, byContinent = {}, byZone = {} }, data.collection)
  end)

  describe("codec failures", function()
    local function codec(serialize, compress)
      return { serialize = serialize or CODEC.serialize, compress = compress or CODEC.compress }
    end

    local function fails(reason, c, input)
      assert.same({ nil, reason }, { Export.string(input or F(), c) })
    end

    it("codec", function()
      fails("codec", nil)
      fails("codec", {})
      fails("codec", "x")
      fails("codec", { serialize = "x", compress = CODEC.compress })
      fails("codec", { serialize = CODEC.serialize, compress = 7 })
      fails("codec", fx.hostileTable())
      fails("codec", fx.hostileProxy())
    end)

    it("serialize", function()
      fails("serialize", codec(function() error("boom") end))
      for _, v in ipairs({ false, 7, "", {} }) do
        fails("serialize", codec(function() return v end))
      end
      fails("serialize", codec(function() return nil end))
    end)

    it("too_large: over serializedMax, and compress is never called", function()
      local calls = 0
      local big = ("x"):rep(Export.LIMITS.serializedMax + 1)
      fails("too_large", codec(function() return big end, function()
        calls = calls + 1
        return "x"
      end))
      assert.equal(0, calls)
      local fits = ("x"):rep(Export.LIMITS.serializedMax)
      local s = Export.string(F(), codec(function() return fits end, function()
        calls = calls + 1
        return "abc"
      end))
      assert.equal("!IL1!YWJj", s)
      assert.equal(1, calls)
    end)

    it("compress", function()
      fails("compress", codec(nil, function() error("boom") end))
      for _, v in ipairs({ "", {}, 7 }) do
        fails("compress", codec(nil, function() return v end))
      end
      fails("compress", codec(nil, function() return nil end))
    end)

    it("uses only the first return of each codec call", function()
      local s = Export.string(F(), codec(function() return "^1^^", "extra" end,
        function() return "abc", "extra" end))
      assert.equal("!IL1!YWJj", s)
    end)

    it("never calls the codec when build fails", function()
      local calls = 0
      local spy = codec(function()
        calls = calls + 1
        return "x"
      end, function()
        calls = calls + 1
        return "x"
      end)
      local input = F()
      input.flavor = "retail"
      fails("flavor", spy, input)
      assert.equal(0, calls)
    end)

    it("data", function()
      assert.same({ nil, "data" }, { Export.encode("x", CODEC) })
      assert.same({ nil, "data" }, { Export.encode(nil, CODEC) })
    end)
  end)
end)

-- ---------------------------------------------------------------------------
-- The glue steps of spec 3.7, run on a pure ledger (6.4, 6.6).

local function bindF()
  local atlas = NS.Collection.bind(fx.places())
  return atlas, NS.Cosmetics.bind(atlas, fx.catalog())
end

local function glueInput(ledger, includeTravelers, faction)
  local atlas, set = bindF()
  local own = ledger:own()
  local travelers
  if rawequal(includeTravelers, true) then
    travelers = {}
    for _, t in ipairs(ledger:travelers()) do
      travelers[#travelers + 1] = { guid = t.guid, name = t.name, met = t.met,
        entries = ledger:signerEntries(t.guid) }
    end
  end
  return {
    flavor = "forever", exported = T + 5000, addon = "dev",
    me = { guid = ledger:ownerGUID(), name = "Aldric" },
    own = own,
    progress = atlas.progress(own, faction),
    unlocked = set.unlocked(own, faction, ledger:earned()),
    travelers = travelers,
  }
end

local ANCHOR = T - 3600

describe("privacy (6.4)", function()
  local function ledgerWithTravelers()
    local ledger = Ledger.new({}, { guid = ME, name = "Aldric" }, ANCHOR)
    for _, e in ipairs(fx.entries()) do
      assert.equal("added", ledger:addOwn(e))
    end
    assert.equal("added", ledger:addForeign(MIRA, "Mira Ashvale",
      { inn = 5001, t = T + 40, phrase = { 4, 5 } }, T + 50))
    assert.equal("added", ledger:addForeign(ZOE, ZOE_NAME,
      { inn = 5201, t = T + 45, phrase = { 7 } }, T + 60))
    return ledger
  end

  it("the default export holds no other player's GUID or name anywhere", function()
    local ledger = ledgerWithTravelers()
    local data = decode(exportOk(glueInput(ledger, nil, "Alliance")))
    assert.is_nil(rawget(data, "travelers"))
    local players = 0
    for _, s in ipairs(stringsOf(data)) do
      for _, other in ipairs({ MIRA, ZOE, "Mira Ashvale", ZOE_NAME }) do
        assert.is_nil(s:find(other, 1, true), s)
      end
      if s:match("^Player%-") then
        assert.equal(ME, s)
        players = players + 1
      end
    end
    assert.equal(1, players)
  end)

  it("only exactly true opts in", function()
    local ledger = ledgerWithTravelers()
    for _, v in ipairs({ "yes", 1, {}, false }) do
      assert.is_nil(rawget(decode(exportOk(glueInput(ledger, v, "Alliance"))), "travelers"))
    end
  end)

  it("an opted-in export holds both travelers", function()
    local ledger = ledgerWithTravelers()
    local data = decode(exportOk(glueInput(ledger, true, "Alliance")))
    local found = {}
    for _, s in ipairs(stringsOf(data)) do
      found[s] = true
    end
    for _, other in ipairs({ MIRA, ZOE, "Mira Ashvale", ZOE_NAME }) do
      assert.is_true(found[other], other)
    end
    assert.equal(2, #data.travelers)
  end)

  it("no string in any decoded fixture holds :// or www.", function()
    for _, input in ipairs({ F(), FT(), glueInput(ledgerWithTravelers(), true, nil) }) do
      for _, s in ipairs(stringsOf(decode(exportOk(input)))) do
        assert.is_nil(s:find("://", 1, true))
        assert.is_nil(s:lower():find("www.", 1, true))
      end
    end
  end)
end)

-- ---------------------------------------------------------------------------
-- 6.5 Size budget

-- Fixture L: 300 own entries (5 phrase IDs each, every other one sealed), progress with
-- 150 zones on 5 continents, 160 cosmetics.
local function fixtureL()
  local own = {}
  for i = 1, 300 do
    own[i] = {
      inn = 100000 + (i * 7919) % 90000,
      t = T + i * 86400 + (i * 37) % 3600,
      phrase = { 1 + i % 24, 1000 + (i * 13) % 120, 500 + i % 4, 1 + (i * 7) % 24,
        1000 + (i * 29) % 120 },
      seal = i % 2 == 0 and 1 + i % 99 or nil,
    }
  end
  local byContinent, byZone = {}, {}
  for c = 1, 5 do
    byContinent[1400 + c * 13] = { signed = 20 + c, total = 40 + c }
  end
  for z = 1, 150 do
    local total = 1 + z % 6
    local signed = z % 3 == 0 and total or z % total
    byZone[2000 + z * 17] = { signed = signed, total = total,
      continent = 1400 + (1 + z % 5) * 13, done = signed == total and T + z * 86400 or nil }
  end
  local unlocked = {}
  for i = 1, 160 do
    unlocked[i] = { id = i < 60 and i or 100 + i, t = own[i].t }
  end
  local input = F()
  input.own = own
  input.progress = { faction = "Horde", signed = 150, total = 400, byContinent = byContinent,
    byZone = byZone }
  input.unlocked = unlocked
  return input
end

local NAME_LETTERS = "abcdefghijklmnopqrstuvwxyz"

-- A traveler i with n entries: a realistic GUID and a 5..12-letter name.
local function sizeTraveler(i, n, guid, name)
  local len = 5 + i % 8
  local letters = { string.char(65 + i % 26) }
  for j = 2, len do
    local k = 1 + (i * 31 + j * 17) % 26
    letters[j] = NAME_LETTERS:sub(k, k)
  end
  local entries = {}
  for j = 1, n do
    local ids = {}
    for m = 1, 1 + (i + j) % 5 do
      ids[m] = 1 + (i * 3 + j * 5 + m * 11) % 1200
    end
    entries[j] = { inn = 100000 + (i * 97 + j * 7919) % 90000,
      t = T + j * 86400 + i % 86400, phrase = ids,
      seal = (i + j) % 3 == 0 and 1 + (i + j) % 99 or nil }
  end
  -- Under 2^31: Lua 5.1's %X goes through a C long, 32 bits on Windows.
  local hex = string.format("%08X", i * 48271 % 2147483647)
  return { guid = guid or string.format("Player-%d-%s", 1000 + i % 9000, hex),
    name = name or table.concat(letters), met = T + 400 * 86400 - i * 600, entries = entries }
end

-- measured string length x 1.25, rounded up to a multiple of 16 KiB, never above `hard`.
local KIB16 = 16384

local function measure(label, input, ceiling)
  local spy = spyCodec()
  local started = os.clock()
  local s = exportOk(input, spy.codec)
  local took = os.clock() - started
  print(string.format("\nexport size: %s: %d chars, serialized %d B, %.2f s", label, #s,
    #spy.serialized, took))
  assert.is_true(#s <= ceiling, label .. ": " .. #s .. " > " .. ceiling)
  return s
end

describe("size budget (6.5)", function()
  it("empty ledger", function()
    local input = F()
    input.own, input.unlocked = {}, {}
    input.progress = { signed = 0, total = 0, byContinent = {}, byZone = {} }
    measure("empty", input, 1 * KIB16)
  end)

  it("L, default", function()
    local s = measure("L default", fixtureL(), 1 * KIB16)
    assert.equal(300, #decode(s).entries)
  end)

  it("L + travelers, 75 x 40 entries #sim", function()
    local input = fixtureL()
    input.travelers = {}
    for i = 1, 75 do
      input.travelers[i] = sizeTraveler(i, 40)
    end
    local s = measure("L + 75 x 40", input, 7 * KIB16)
    assert.equal(75, #decode(s).travelers)
  end)

  it("L + travelers, 3 000 x 1 entry #sim", function()
    local input = fixtureL()
    input.travelers = {}
    for i = 1, 3000 do
      input.travelers[i] = sizeTraveler(i, 1)
    end
    local s = measure("L + 3000 x 1", input, 13 * KIB16)
    assert.equal(3000, #decode(s).travelers)
  end)

  it("every build limit at once, longest fields: serialized under serializedMax #sim", function()
    local input = F()
    input.own = {}
    for i = 1, 10000 do
      input.own[i] = { inn = 9000000 + i, t = LIMITS.tMax - i,
        phrase = { 9990 + i % 10, 9000 + i % 999, 8000 + i % 999, 7000 + i % 999,
          6000 + i % 999 }, seal = 900 + i % 99 }
    end
    input.unlocked = {}
    for i = 1, 1200 do
      input.unlocked[i] = { id = 8799 + i, t = LIMITS.tMax - i }
    end
    local byContinent, byZone = {}, {}
    for k = 1, 1000 do
      byContinent[999000 + k - 1] = { signed = 9999999, total = 9999999, done = LIMITS.tMax }
      byZone[998000 + k - 1] = { signed = 9999999, total = 9999999, continent = 999000,
        done = LIMITS.tMax }
    end
    input.progress = { faction = "Alliance", signed = 9999999, total = 9999999,
      done = LIMITS.tMax, byContinent = byContinent, byZone = byZone }
    input.me.name = ("A"):rep(47) .. "-" .. ("B"):rep(48)
    input.travelers = {}
    local name = ("C"):rep(47) .. "-" .. ("D"):rep(48)
    for i = 1, 3000 do
      local guid = string.format("Player-9999-%028X", i)
      assert.equal(40, #guid)
      local tr = sizeTraveler(i, 1, guid, name)
      tr.entries[1] = deepcopy(input.own[i])
      input.travelers[i] = tr
    end
    local started = os.clock()
    local data = buildOk(input)
    local serialized = LIBS.serializer:Serialize(data)
    print(string.format("\nexport size: every limit: serialized %d B, build + serialize %.2f s",
      #serialized, os.clock() - started))
    assert.is_true(#serialized <= Export.LIMITS.serializedMax)
    assert.is_true(#serialized <= 164 * KIB16)
  end)
end)

-- ---------------------------------------------------------------------------
-- 6.6 Hostile and tampered input

describe("hostile and tampered input (6.6)", function()
  it("survives 1 000 seeded mutations of F+T: a known reason or a valid table", function()
    local seed = 64
    local function rand(n)
      seed = seed * 16807 % 2147483647
      return 1 + seed % n
    end
    local function deep(n)
      local t = {}
      local cur = t
      for _ = 1, n do
        cur.x = {}
        cur = cur.x
      end
      return t
    end
    local values = {
      function() return nil end, function() return 0 / 0 end, function() return 1 / 0 end,
      function() return -1 / 0 end, function() return 1.5 end, function() return 0 end,
      function() return -1 end, function() return 2 ^ 53 end, function() return "" end,
      function() return ("x"):rep(200) end, function() return "|cff" end,
      function() return {} end, fx.hostileProxy, fx.hostileTable,
      function() return deep(50) end,
    }
    local refused, built = 0, 0
    for iteration = 1, 1000 do
      local input = FT()
      local slots = {}
      local function collect(t)
        for k, v in next, t do
          slots[#slots + 1] = { t, k }
          if type(v) == "table" then
            collect(v)
          end
        end
      end
      collect(input)
      local slot = slots[rand(#slots)]
      slot[1][slot[2]] = values[rand(#values)]()
      local before = fx.snapshot(input, 8)
      local ok, data, reason = pcall(build, input)
      assert(ok, "iteration " .. iteration .. " threw: " .. tostring(data))
      assert.is_true(fx.sameSnapshot(before, fx.snapshot(input, 8)))
      if data then
        built = built + 1
        if iteration % 50 == 0 then
          assert.same(data, decode(exportOk(input)))
        end
      else
        assert.truthy(REASONS[reason])
        refused = refused + 1
      end
    end
    assert.is_true(built > 300 and refused > 50, built .. " built, " .. refused .. " refused")
  end)

  it("exports a tampered SavedVariables ledger without its quarantined entries", function()
    local good1 = { inn = 5001, t = T, phrase = { 1 } }
    local good2 = { inn = 5201, t = T + 100, phrase = { 2 }, seal = 1 }
    local saved = {
      schema = 1,
      me = { name = "x|cff" },
      own = { good1, { inn = "x" }, { inn = 5002, t = 1, phrase = { 1 } },
        { inn = 5101, t = T + 50, phrase = { 1 }, seal = 5000 }, good2 },
      travelers = {
        [MIRA] = { name = "Mira Ashvale", met = T + 50,
          entries = { { inn = 5001, t = T + 40, phrase = { 4 } }, { inn = 0 } } },
        ["not-a-guid"] = { name = "Bad", met = T, entries = { good1 } },
        [ZOE] = "junk",
        [ME] = { name = "Me", met = T, entries = { good1 } },
      },
      earned = { [0] = 1, [1101] = "x", [1] = T, [2] = T + 1 },
      quarantine = {},
    }
    local ledger = Ledger.new(saved, { guid = ME, name = "Aldric" }, ANCHOR)
    assert.equal(3, ledger.loadReport.quarantined)
    local data = decode(exportOk(glueInput(ledger, true, "Alliance")))
    assert.same({ good1, good2 }, data.entries)
    assert.equal(1, #data.travelers)
    assert.equal(MIRA, data.travelers[1].guid)
    assert.same({ { inn = 5001, t = T + 40, phrase = { 4 } } }, data.travelers[1].entries)
    for _, c in ipairs(data.cosmetics) do
      assert.is_true(c.t == T or c.t == T + 100)
    end
  end)

  it("matches the real Collection and Cosmetics for Alliance, Horde and no faction", function()
    local atlas, set = bindF()
    for _, faction in ipairs({ "Alliance", "Horde", false }) do
      local f = faction or nil
      local own = fx.entries()
      local progress = atlas.progress(own, f)
      local unlocked = set.unlocked(own, f, { [1] = T })
      local input = F()
      input.own, input.progress, input.unlocked = own, progress, unlocked
      local data = buildOk(input)
      -- The export copies only its named fields: not `inns`, `unknown`, `truncated`, nor the
      -- `complete` flags of collection-cosmetics.md 3.11 (the format is unchanged).
      local want = deepcopy(progress)
      want.inns, want.unknown, want.truncated, want.complete = nil, nil, nil, nil
      for _, map in ipairs({ want.byContinent, want.byZone }) do
        for _, item in pairs(map) do
          item.complete = nil
        end
      end
      assert.same(want, data.collection)
      assert.same(unlocked, data.cosmetics)
      assert.same(want, decode(exportOk(input)).collection)
    end
  end)

  it("carries no done for a place not marked complete (F0), in the same format", function()
    local atlas = NS.Collection.bind(fx.placesF0())
    local set = NS.Cosmetics.bind(atlas, fx.catalog())
    local own = fx.entries()
    local input = F()
    input.own, input.progress = own, atlas.progress(own, "Alliance")
    input.unlocked = set.unlocked(own, "Alliance")
    local coll = decode(exportOk(input)).collection
    assert.same({ "byContinent", "byZone", "faction", "signed", "total" }, (function()
      local keys = {}
      for k in pairs(coll) do
        keys[#keys + 1] = k
      end
      table.sort(keys)
      return keys
    end)())
    assert.equal(4, coll.signed)
    assert.equal(4, coll.total)
    for _, map in ipairs({ coll.byContinent, coll.byZone }) do
      for _, item in pairs(map) do
        assert.is_nil(item.done)
        assert.is_nil(item.complete)
        assert.equal(item.total, item.signed)
      end
    end
  end)
end)
