-- The test-only reference decoder for export strings and a v1 schema checker
-- (docs/specs/export.md 3.8). Never shipped: the packager drops spec/, and
-- scripts/check-apis.sh keeps every general-purpose decoder out of shipped code.
-- Written independently of Export.lua (own alphabet table, own arithmetic, own rules), so
-- a bug in one doesn't hide in the other. Uses Ledger's name and GUID rules only, since
-- the format defines those fields by them.
local load = require("helpers.load")

local M = {}

M.MAX_STRING = 6000000
M.SERIALIZED_MAX = 4194304

local Ledger = load.file("Ledger.lua", {}, load.pure_env()).Ledger

local T_MIN, T_MAX = 1789603200, 9999999999

-- ---------------------------------------------------------------------------
-- Strict RFC 4648 base64.

local VALUE = {}
do
  local alphabet = {}
  for c = ("A"):byte(), ("Z"):byte() do alphabet[#alphabet + 1] = string.char(c) end
  for c = ("a"):byte(), ("z"):byte() do alphabet[#alphabet + 1] = string.char(c) end
  for c = ("0"):byte(), ("9"):byte() do alphabet[#alphabet + 1] = string.char(c) end
  alphabet[#alphabet + 1] = "+"
  alphabet[#alphabet + 1] = "/"
  for i, ch in ipairs(alphabet) do
    VALUE[ch:byte()] = i - 1
  end
end

-- The bytes of a strict base64 string, or nil.
function M.unbase64(s)
  if type(s) ~= "string" or #s % 4 ~= 0 then
    return nil
  end
  local pad = 0
  if s:sub(-2) == "==" then
    pad = 2
  elseif s:sub(-1) == "=" then
    pad = 1
  end
  local body = #s - pad
  for i = 1, body do
    if VALUE[s:byte(i)] == nil then
      return nil
    end
  end
  local out = {}
  for i = 1, #s, 4 do
    local a, b = VALUE[s:byte(i)], VALUE[s:byte(i + 1)]
    local c = VALUE[s:byte(i + 2)] or 0
    local d = VALUE[s:byte(i + 3)] or 0
    local last = i + 3 == #s
    local n = ((a * 64 + b) * 64 + c) * 64 + d
    local b1 = math.floor(n / 65536)
    local b2 = math.floor(n / 256) % 256
    local b3 = n % 256
    if last and pad == 2 then
      if b2 ~= 0 or b3 ~= 0 then
        return nil -- non-zero pad bits
      end
      out[#out + 1] = string.char(b1)
    elseif last and pad == 1 then
      if b3 ~= 0 then
        return nil
      end
      out[#out + 1] = string.char(b1, b2)
    else
      out[#out + 1] = string.char(b1, b2, b3)
    end
  end
  return table.concat(out)
end

-- ---------------------------------------------------------------------------
-- decode(str, libs) -> data, or nil, reason. `libs` = { serializer, deflate }.

function M.decode(str, libs)
  if type(str) ~= "string" then
    return nil, "input"
  end
  if #str > M.MAX_STRING then
    return nil, "too_large"
  end
  local major = str:match("^!IL(%d+)!")
  if major ~= "1" then
    return nil, "version"
  end
  local bytes = M.unbase64(str:sub(#"!IL1!" + 1))
  if bytes == nil then
    return nil, "base64"
  end
  local ok, inflated, extra = pcall(libs.deflate.DecompressDeflate, libs.deflate, bytes)
  if not ok or type(inflated) ~= "string" or extra ~= 0 then
    return nil, "inflate"
  end
  if #inflated > M.SERIALIZED_MAX then
    return nil, "too_large"
  end
  local function pack(...)
    return { n = select("#", ...), ... }
  end
  local results = pack(pcall(libs.serializer.Deserialize, libs.serializer, inflated))
  -- pcall's true, Deserialize's true, then exactly one table.
  if results[1] ~= true or results[2] ~= true or results.n ~= 3
    or type(results[3]) ~= "table" then
    return nil, "deserialize"
  end
  local data = results[3]
  if data.v ~= 1 then
    return nil, "version"
  end
  return data
end

-- ---------------------------------------------------------------------------
-- schemaOk(data) -> true, or false and where it failed (spec 4.1).

local function isInt(x, lo, hi)
  return type(x) == "number" and x == x and x % 1 == 0 and x >= lo and x <= hi
end

local function isTime(x)
  return isInt(x, T_MIN, T_MAX)
end

-- Keys of t are a subset of `fields`; every `true` field is present.
local function fieldsOk(t, fields)
  if type(t) ~= "table" or getmetatable(t) ~= nil then
    return false
  end
  for k in next, t do
    if fields[k] == nil then
      return false
    end
  end
  for k, required in next, fields do
    if required and rawget(t, k) == nil then
      return false
    end
  end
  return true
end

-- An array: keys exactly 1..n. Returns n or nil.
local function arrayLen(t)
  if type(t) ~= "table" or getmetatable(t) ~= nil then
    return nil
  end
  local n = 0
  for _ in next, t do
    n = n + 1
  end
  for i = 1, n do
    if rawget(t, i) == nil then
      return nil
    end
  end
  return n
end

local function bytesLess(a, b)
  for i = 1, math.min(#a, #b) do
    if a:byte(i) ~= b:byte(i) then
      return a:byte(i) < b:byte(i)
    end
  end
  return #a < #b
end

local function addonOk(s)
  return type(s) == "string" and #s >= 1 and #s <= 32 and s:match("^[A-Za-z0-9._+%-]+$") ~= nil
end

local ENTRY = { inn = true, t = true, phrase = true, seal = false }

local function entryOk(e)
  if not fieldsOk(e, ENTRY) or not isInt(e.inn, 1, 9999999) or not isTime(e.t) then
    return false
  end
  if e.seal ~= nil and not isInt(e.seal, 1, 999) then
    return false
  end
  local n = arrayLen(e.phrase)
  if n == nil or n < 1 or n > 5 then
    return false
  end
  for i = 1, n do
    if not isInt(e.phrase[i], 1, 9999) then
      return false
    end
  end
  return true
end

-- An entry array: (t, inn) strictly ascending, so (inn, t) is unique too.
local function entriesOk(list, min, max)
  local n = arrayLen(list)
  if n == nil or n < min or n > max then
    return false
  end
  for i = 1, n do
    local e = list[i]
    if not entryOk(e) then
      return false
    end
    local prev = list[i - 1]
    if prev and not (prev.t < e.t or (prev.t == e.t and prev.inn < e.inn)) then
      return false
    end
  end
  return true
end

local COUNT_FIELDS = { signed = true, total = true, done = false }
local ZONE_FIELDS = { signed = true, total = true, continent = true, done = false }

-- Counts are plain non-negative integers (a negative zero would read "-0"), and `done`
-- is present only when signed == total >= 1.
local function countsOk(v)
  return isInt(v.signed, 0, 9999999) and isInt(v.total, 0, 9999999) and v.signed <= v.total
    and 1 / v.signed > 0 and 1 / v.total > 0
    and (v.done == nil or (isTime(v.done) and v.signed == v.total and v.total >= 1))
end

local COLLECTION = {
  faction = false, signed = true, total = true, done = false, byContinent = true,
  byZone = true,
}

local function collectionOk(c)
  if not fieldsOk(c, COLLECTION) or not countsOk(c) then
    return false
  end
  if c.faction ~= nil and c.faction ~= "Alliance" and c.faction ~= "Horde" then
    return false
  end
  if type(c.byContinent) ~= "table" or getmetatable(c.byContinent) ~= nil
    or type(c.byZone) ~= "table" or getmetatable(c.byZone) ~= nil then
    return false
  end
  for k, v in next, c.byContinent do
    if not isInt(k, 1, 999999) or not fieldsOk(v, COUNT_FIELDS) or not countsOk(v) then
      return false
    end
  end
  for k, v in next, c.byZone do
    if not isInt(k, 1, 999999) or not fieldsOk(v, ZONE_FIELDS) or not countsOk(v)
      or not isInt(v.continent, 1, 999999) or c.byContinent[v.continent] == nil then
      return false
    end
  end
  return true
end

local COSMETIC = { id = true, t = true }

local function cosmeticsOk(list)
  local n = arrayLen(list)
  if n == nil then
    return false
  end
  local ids = {}
  for i = 1, n do
    local c = list[i]
    if not fieldsOk(c, COSMETIC) or not isInt(c.id, 1, 9999) or not isTime(c.t)
      or ids[c.id] then
      return false
    end
    ids[c.id] = true
    local prev = list[i - 1]
    if prev and not (prev.t < c.t or (prev.t == c.t and prev.id < c.id)) then
      return false
    end
  end
  return true
end

local TRAVELER = { guid = true, name = true, met = true, entries = true }

local function travelersOk(list, ownerGUID)
  local n = arrayLen(list)
  if n == nil then
    return false
  end
  local guids = {}
  for i = 1, n do
    local tr = list[i]
    if not fieldsOk(tr, TRAVELER) or not Ledger.validGUID(tr.guid) or tr.guid == ownerGUID
      or guids[tr.guid] or not Ledger.validName(tr.name) or not isTime(tr.met)
      or not entriesOk(tr.entries, 1, 40) then
      return false
    end
    guids[tr.guid] = true
    local prev = list[i - 1]
    if prev and not (prev.met > tr.met or (prev.met == tr.met and bytesLess(prev.guid, tr.guid)))
    then
      return false
    end
  end
  return true
end

local TOP = {
  v = true, flavor = true, exported = true, addon = true, me = true, collection = true,
  cosmetics = true, entries = true, travelers = false,
}
local ME = { guid = true, name = false }

function M.schemaOk(data)
  if not fieldsOk(data, TOP) then
    return false, "top-level keys"
  elseif data.v ~= 1 then
    return false, "v"
  elseif data.flavor ~= "forever" then
    return false, "flavor"
  elseif not isTime(data.exported) then
    return false, "exported"
  elseif not addonOk(data.addon) then
    return false, "addon"
  elseif not fieldsOk(data.me, ME) or not Ledger.validGUID(data.me.guid)
    or (data.me.name ~= nil and not Ledger.validName(data.me.name)) then
    return false, "me"
  elseif not collectionOk(data.collection) then
    return false, "collection"
  elseif not cosmeticsOk(data.cosmetics) then
    return false, "cosmetics"
  elseif not entriesOk(data.entries, 0, math.huge) then
    return false, "entries"
  elseif data.travelers ~= nil and not travelersOk(data.travelers, data.me.guid) then
    return false, "travelers"
  end
  return true
end

return M
