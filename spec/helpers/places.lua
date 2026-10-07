-- Fixtures for the Collection and Cosmetics specs (docs/specs/collection-cosmetics.md,
-- section 6): places F, own entries E, catalog C, the hidden-value stand-ins, a raw
-- snapshot to show nothing was written, and a seeded shuffle. Each call builds fresh tables.
local M = {}

M.T = 1790000000

-- Places F0: inns, zones, continents, with no completeness mark (spec 3.11).
function M.placesF0()
  return {
    [5001] = { name = "Vale Inn", zone = 10 },
    [5002] = { name = "Hill Inn", zone = 10, faction = "Alliance" },
    [5003] = { alias = 5001 },
    [5101] = { name = "Marsh Inn", zone = 11, faction = "Alliance" },
    [5201] = { name = "Dune Inn", zone = 20 },
    [5202] = { name = "Oasis Inn", zone = 20, faction = "Horde" },
    [5301] = { name = "Ridge Inn", zone = 21, faction = "Horde" },
  }, {
    [10] = { name = "Vale", continent = 1, seal = 101 },
    [11] = { name = "Marsh", continent = 1, seal = 102 },
    [20] = { name = "Dunes", continent = 2, seal = 103 },
    [21] = { name = "Ridge", continent = 2, seal = 104 },
  }, {
    [1] = { name = "East" },
    [2] = { name = "West" },
  }
end

-- Places F: F0 with every zone and continent marked complete, and a fourth value, true,
-- for Collection.bind's atlasComplete. So `Collection.bind(fx.places())` binds a complete
-- atlas; a caller that keeps the three tables passes `true` itself.
function M.places()
  local inns, zones, conts = M.placesF0()
  for _, z in pairs(zones) do
    z.complete = true
  end
  for _, c in pairs(conts) do
    c.complete = true
  end
  return inns, zones, conts, true
end

-- The fail-closed cases of spec 3.11 (#118): F (all marked, atlasComplete true) with one
-- record excluded. Each is { label, change(inns, zones, conts), invalid, alliance }, where
-- `alliance` is Alliance's unlocked list for E over catalog C as { id, t } pairs: only the
-- `inns n` items, at the times of the inns still known.
function M.excludedCases()
  local T = M.T
  return {
    { "an inn of a marked zone with a bad field (Hill Inn, faction \"Neutral\")",
      function(i) i[5002].faction = "Neutral" end, { "inn 5002" },
      { { 1, T + 100 }, { 1001, T + 400 } } },
    { "an inn whose zone isn't a kept zone", function(i)
      i[5401] = { name = "Glen Inn", zone = 99 }
    end, { "inn 5401" }, { { 1, T + 100 }, { 1001, T + 300 } } },
    { "an alias to a missing primary", function(i) i[5401] = { alias = 5999 } end,
      { "inn 5401" }, { { 1, T + 100 }, { 1001, T + 300 } } },
    { "a non-table inn record", function(i) i[5401] = "Glen Inn" end, { "inn 5401" },
      { { 1, T + 100 }, { 1001, T + 300 } } },
    { "a zone record on another continent with a bad field (Dunes, a lowercase name)",
      function(_, z) z[20].name = "dunes" end, { "inn 5201", "inn 5202", "zone 20" },
      { { 1, T + 300 }, { 1001, T + 400 } } },
    { "a bad continent key (\"3\")", function(_, _, c) c["3"] = { name = "North" } end,
      { "continent <string>" }, { { 1, T + 100 }, { 1001, T + 300 } } },
  }
end

-- Own entries E: e1..e7.
function M.entries()
  local T = M.T
  local function e(inn, t)
    return { inn = inn, t = t, phrase = { 1 } }
  end
  return {
    e(5001, T),          -- e1
    e(5201, T + 100),    -- e2
    e(5003, T + 200),    -- e3, the alias of 5001
    e(5002, T + 300),    -- e4
    e(5101, T + 400),    -- e5
    e(9999, T + 500),    -- e6, not in the data
    e(5001, T + 604800), -- e7, a week later
  }
end

-- Catalog C.
function M.catalog()
  return {
    [1] = { kind = "seal", name = "First seal", rule = { kind = "inns", n = 2 } },
    [2] = { kind = "seal", name = "Last seal", rule = { kind = "all" } },
    [1001] = { kind = "quill", name = "Long quill", rule = { kind = "inns", n = 3 } },
    [1002] = { kind = "quill", name = "Blue quill", rule = { kind = "zones", n = 2 } },
    [1003] = { kind = "quill", name = "Red quill", rule = { kind = "continent" } },
  }
end

local function raise()
  error("hidden value touched")
end

M.HOSTILE_EVENTS = {
  "__index", "__newindex", "__len", "__eq", "__lt", "__le", "__concat", "__tostring",
  "__call", "__unm", "__add",
}

-- The two hidden-value stand-ins (sync-ledger.md 5.2).
function M.hostileTable()
  local mt = {}
  for _, ev in ipairs(M.HOSTILE_EVENTS) do
    mt[ev] = raise
  end
  return setmetatable({}, mt)
end

function M.hostileProxy()
  local u = newproxy(true)
  local mt = getmetatable(u)
  for _, ev in ipairs(M.HOSTILE_EVENTS) do
    mt[ev] = raise
  end
  return u
end

-- A raw snapshot of t (NaN-aware, `depth` levels), to show nothing was written.
function M.snapshot(t, depth)
  depth = depth or 3
  if type(t) ~= "table" or depth == 0 then
    return { value = t }
  end
  local out = { ref = t, pairs = {} }
  for k, v in next, t do
    out.pairs[#out.pairs + 1] = { k = k, v = M.snapshot(v, depth - 1) }
  end
  return out
end

local function sameValue(a, b)
  return rawequal(a, b) or (a ~= a and b ~= b)
end

function M.sameSnapshot(a, b)
  if a.pairs == nil or b.pairs == nil then
    return a.pairs == b.pairs and sameValue(a.value, b.value)
  end
  if not rawequal(a.ref, b.ref) or #a.pairs ~= #b.pairs then
    return false
  end
  for i = 1, #a.pairs do
    local x, y = a.pairs[i], b.pairs[i]
    if not sameValue(x.k, y.k) or not M.sameSnapshot(x.v, y.v) then
      return false
    end
  end
  return true
end

-- A shuffled copy of an array, from a seed (Park-Miller; exact in doubles).
function M.shuffled(arr, seed)
  local out = {}
  for i = 1, #arr do
    out[i] = arr[i]
  end
  for i = #out, 2, -1 do
    seed = seed * 16807 % 2147483647
    local j = 1 + seed % i
    out[i], out[j] = out[j], out[i]
  end
  return out
end

function M.reversed(arr)
  local out = {}
  for i = #arr, 1, -1 do
    out[#out + 1] = arr[i]
  end
  return out
end

return M
