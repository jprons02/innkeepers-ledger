-- Export (pure): builds the v1 export data table from plain values the glue gathers,
-- encodes it with an injected serializer and compressor, and writes our own standard
-- base64. The string format is docs/export-format.md; the spec is docs/specs/export.md.
-- No WoW API here. Client values come in as arguments (docs/architecture.md -> Modules),
-- and so do the libraries: this file never reaches for them itself.
-- Every argument is read with rawget / raw next only, with bounded work, never written to,
-- and nothing here throws on any argument. Only the load itself can raise (the asserts).
-- There is no decoder here or anywhere in shipped code; the test-only decoder lives in
-- spec/helpers/export_decode.lua.
local _, ns = ...

local Ledger = ns.Ledger
assert(type(Ledger) == "table", "Export needs ns.Ledger; Ledger.lua comes first in the TOC")
local Collection = ns.Collection
assert(type(Collection) == "table",
  "Export needs ns.Collection; Collection.lua comes first in the TOC")

local Export = {}
ns.Export = Export

local byte, floor = string.byte, math.floor
local tconcat, tsort = table.concat, table.sort

-- Constants (spec 3.6). The locals are what the code uses; the exported tables are copies.
local VERSION = 1
local PREFIX = "!IL" .. VERSION .. "!"
local FLAVORS = { forever = true }
local OWN_MAX = 10000
local COSMETICS_MAX = 1200
local MAP_ITEMS_MAX = 1000
local ADDON_BYTES = 32
local SERIALIZED_MAX = 4194304

-- Read from Ledger and Collection, not second literals.
local L = Ledger.LIMITS
local INN_MAX, T_MIN, T_MAX = L.innMax, L.tMin, L.tMax
local PHRASE_IDS_MAX = L.phraseIdsMax
local COSMETIC_ID_MAX = L.cosmeticIdMax
local FOREIGN_MAX, PER_SIGNER = Ledger.CAPS.foreignTotal, Ledger.CAPS.perSigner
local MAP_KEY_MAX = Collection.LIMITS.mapKeyMax
local FACTIONS = { Alliance = true, Horde = true }
local validGUID, validName, validEntry = Ledger.validGUID, Ledger.validName, Ledger.validEntry

Export.VERSION = VERSION
Export.PREFIX = PREFIX
Export.FLAVORS = { forever = true }
Export.LIMITS = {
  ownMax = OWN_MAX,
  cosmeticsMax = COSMETICS_MAX,
  mapItemsMax = MAP_ITEMS_MAX,
  addonBytes = ADDON_BYTES,
  serializedMax = SERIALIZED_MAX,
}

-- An integer in lo..hi. NaN fails x == x; inf % 1 is NaN, so inf fails too.
local function isInt(x, lo, hi)
  return type(x) == "number" and x == x and x % 1 == 0 and x >= lo and x <= hi
end

local function isTime(x)
  return isInt(x, T_MIN, T_MAX)
end

-- ---------------------------------------------------------------------------
-- Base64 (spec 3.3): RFC 4648 section 4, standard alphabet, "=" padding, no line breaks.

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local CHAR = {} -- 0..63 -> character
for i = 1, 64 do
  CHAR[i - 1] = ALPHABET:sub(i, i)
end

local function base64(s)
  if type(s) ~= "string" then
    return nil
  end
  local out, n = {}, 0
  local len = #s
  for i = 1, len - 2, 3 do
    local a, b, c = byte(s, i, i + 2)
    local v = a * 65536 + b * 256 + c
    out[n + 1] = CHAR[floor(v / 262144)]
    out[n + 2] = CHAR[floor(v / 4096) % 64]
    out[n + 3] = CHAR[floor(v / 64) % 64]
    out[n + 4] = CHAR[v % 64]
    n = n + 4
  end
  local rest = len % 3
  if rest == 1 then
    local v = byte(s, len) * 65536
    out[n + 1] = CHAR[floor(v / 262144)]
    out[n + 2] = CHAR[floor(v / 4096) % 64]
    out[n + 3] = "=="
  elseif rest == 2 then
    local a, b = byte(s, len - 1, len)
    local v = a * 65536 + b * 256
    out[n + 1] = CHAR[floor(v / 262144)]
    out[n + 2] = CHAR[floor(v / 4096) % 64]
    out[n + 3] = CHAR[floor(v / 64) % 64]
    out[n + 4] = "="
  end
  return tconcat(out)
end
Export.base64 = base64

-- ---------------------------------------------------------------------------
-- build (spec 3.5).

-- Byte order. String `<` follows the C locale's collation (as in Ledger).
local function strLess(a, b)
  for i = 1, math.min(#a, #b) do
    local x, y = byte(a, i), byte(b, i)
    if x ~= y then
      return x < y
    end
  end
  return #a < #b
end

local function entryLess(a, b)
  if a.t ~= b.t then
    return a.t < b.t
  end
  return a.inn < b.inn
end

local function cosmeticLess(a, b)
  if a.t ~= b.t then
    return a.t < b.t
  end
  return a.id < b.id
end

local function travelerLess(a, b)
  if a.met ~= b.met then
    return a.met > b.met
  end
  return strLess(a.guid, b.guid)
end

-- `addon`: 1..ADDON_BYTES bytes of A-Z a-z 0-9 . _ + - (explicit byte ranges).
local function validAddon(s)
  if type(s) ~= "string" or #s < 1 or #s > ADDON_BYTES then
    return false
  end
  for i = 1, #s do
    local b = byte(s, i)
    if not ((b >= 65 and b <= 90) or (b >= 97 and b <= 122) or (b >= 48 and b <= 57)
      or b == 46 or b == 95 or b == 43 or b == 45) then
      return false
    end
  end
  return true
end

-- A fresh copy of an entry that passed Ledger.validEntry (read raw).
local function copyEntry(e)
  local phrase, p = {}, rawget(e, "phrase")
  for i = 1, PHRASE_IDS_MAX do
    local id = rawget(p, i)
    if id == nil then
      break
    end
    phrase[i] = id
  end
  local out = { inn = rawget(e, "inn"), t = rawget(e, "t"), phrase = phrase }
  local seal = rawget(e, "seal")
  if seal ~= nil then
    out.seal = seal
  end
  return out
end

-- The kept entries of an array, sorted, or nil if it holds more than `max` items.
-- `budget` (optional) is { left = n }: every item read spends one, and running out is
-- too many as well. A non-table gives no entries.
local function entries(arr, max, budget)
  local out, seen = {}, {}
  if type(arr) ~= "table" then
    return out
  end
  for i = 1, max + 1 do
    local e = rawget(arr, i)
    if e == nil then
      break
    elseif i > max then
      return nil
    end
    if budget then
      budget.left = budget.left - 1
      if budget.left < 0 then
        return nil
      end
    end
    if validEntry(e) then
      local inn, t = rawget(e, "inn"), rawget(e, "t")
      local byInn = seen[inn]
      if byInn == nil then
        byInn = {}
        seen[inn] = byInn
      end
      if not byInn[t] then
        byInn[t] = true
        out[#out + 1] = copyEntry(e)
      end
    end
  end
  tsort(out, entryLess)
  return out
end

-- { signed, total } read raw from a progress-shaped table, or nil if they fail.
local function counts(v)
  local signed, total = rawget(v, "signed"), rawget(v, "total")
  if isInt(signed, 0, INN_MAX) and isInt(total, 0, INN_MAX) and signed <= total then
    return signed, total
  end
  return nil
end

-- A map of { signed, total, done? [, continent] } items, or nil if it holds too many.
-- `continents` (for zones) is the kept continent map: a zone's continent must be a key.
local function progressMap(map, continents)
  local out, n = {}, 0
  for k, v in next, map do
    n = n + 1
    if n > MAP_ITEMS_MAX then
      return nil
    end
    if isInt(k, 1, MAP_KEY_MAX) and type(v) == "table" then
      local signed, total = counts(v)
      local done = rawget(v, "done")
      local ok = signed ~= nil and (done == nil or isTime(done))
      local continent
      if ok and continents then
        continent = rawget(v, "continent")
        ok = isInt(continent, 1, MAP_KEY_MAX) and continents[continent] ~= nil
      end
      if ok then
        out[k] = { signed = signed, total = total, continent = continent, done = done }
      end
    end
  end
  return out
end

-- True if a progress result's own fields pass (spec 3.5): counts, faction, done, and the
-- two maps are tables. `done` is present only when signed == total >= 1 (spec 4.1).
local function collectionOk(p)
  if type(p) ~= "table" then
    return false
  end
  local signed, total = counts(p)
  local faction, done = rawget(p, "faction"), rawget(p, "done")
  return signed ~= nil
    and (faction == nil or (type(faction) == "string" and FACTIONS[faction] == true))
    and (done == nil or (isTime(done) and signed == total and total >= 1))
    and type(rawget(p, "byContinent")) == "table" and type(rawget(p, "byZone")) == "table"
end

-- The collection table of a progress result that passed collectionOk, or nil if a map
-- holds too many items.
local function collection(p)
  local conts = progressMap(rawget(p, "byContinent"), nil)
  local zones = conts and progressMap(rawget(p, "byZone"), conts)
  if not zones then
    return nil
  end
  local signed, total = counts(p)
  return {
    faction = rawget(p, "faction"), signed = signed, total = total, done = rawget(p, "done"),
    byContinent = conts, byZone = zones,
  }
end

-- The kept cosmetics, sorted, or nil if there are too many.
local function cosmetics(list)
  local out, at = {}, {} -- kept items; id -> its item in out
  for i = 1, COSMETICS_MAX + 1 do
    local c = rawget(list, i)
    if c == nil then
      break
    elseif i > COSMETICS_MAX then
      return nil
    end
    if type(c) == "table" then
      local id, t = rawget(c, "id"), rawget(c, "t")
      if isInt(id, 1, COSMETIC_ID_MAX) and isTime(t) then
        local prev = at[id]
        if prev == nil then
          local item = { id = id, t = t }
          at[id] = item
          out[#out + 1] = item
        elseif t < prev.t then
          prev.t = t
        end
      end
    end
  end
  tsort(out, cosmeticLess)
  return out
end

-- The kept travelers, sorted, or nil if a limit is passed.
local function travelers(list, ownerGUID)
  local out, kept = {}, {}
  local budget = { left = FOREIGN_MAX }
  for i = 1, FOREIGN_MAX + 1 do
    local rec = rawget(list, i)
    if rec == nil then
      break
    elseif i > FOREIGN_MAX then
      return nil
    end
    if type(rec) == "table" then
      local guid, name, met = rawget(rec, "guid"), rawget(rec, "name"), rawget(rec, "met")
      if validGUID(guid) and guid ~= ownerGUID and not kept[guid] and validName(name)
        and isTime(met) then
        local list2 = entries(rawget(rec, "entries"), PER_SIGNER, budget)
        if list2 == nil then
          return nil
        end
        if #list2 > 0 then
          kept[guid] = true
          out[#out + 1] = { guid = guid, name = name, met = met, entries = list2 }
        end
      end
    end
  end
  tsort(out, travelerLess)
  return out
end

-- Export.build(input) -> the v1 data table (spec 4.1), or nil, reason.
function Export.build(input)
  if type(input) ~= "table" then
    return nil, "input"
  end
  local flavor, exported = rawget(input, "flavor"), rawget(input, "exported")
  local addon, me = rawget(input, "addon"), rawget(input, "me")
  local progress, own = rawget(input, "progress"), rawget(input, "own")
  local unlocked, travelerList = rawget(input, "unlocked"), rawget(input, "travelers")

  -- Required top-level values, in a fixed order.
  if not (type(flavor) == "string" and FLAVORS[flavor] == true) then
    return nil, "flavor"
  elseif not isTime(exported) then
    return nil, "exported"
  elseif not validAddon(addon) then
    return nil, "addon"
  elseif type(me) ~= "table" or not validGUID(rawget(me, "guid")) then
    return nil, "me"
  elseif not collectionOk(progress) then
    return nil, "collection"
  elseif type(own) ~= "table" then
    return nil, "entries"
  elseif type(unlocked) ~= "table" then
    return nil, "cosmetics"
  elseif travelerList ~= nil and type(travelerList) ~= "table" then
    return nil, "travelers"
  end

  -- Items: bad ones are left out; past a limit the whole export is refused.
  local guid, name = rawget(me, "guid"), rawget(me, "name")
  local coll = collection(progress)
  local ownOut = coll and entries(own, OWN_MAX)
  local cosOut = ownOut and cosmetics(unlocked)
  local travOut
  if cosOut and travelerList ~= nil then
    travOut = travelers(travelerList, guid)
  end
  if cosOut == nil or (travelerList ~= nil and travOut == nil) then
    return nil, "too_large"
  end

  return {
    v = VERSION,
    flavor = flavor,
    exported = exported,
    addon = addon,
    me = { guid = guid, name = validName(name) and name or nil },
    collection = coll,
    cosmetics = cosOut,
    entries = ownOut,
    travelers = travOut,
  }
end

-- ---------------------------------------------------------------------------
-- encode and string (spec 3.6).

-- The first return of fn(arg) if it's a non-empty string, else nil. Never raises.
local function callString(fn, arg)
  local ok, s = pcall(fn, arg)
  if ok and type(s) == "string" and s ~= "" then
    return s
  end
  return nil
end

function Export.encode(data, codec)
  if type(data) ~= "table" then
    return nil, "data"
  end
  if type(codec) ~= "table" then
    return nil, "codec"
  end
  local serialize, compress = rawget(codec, "serialize"), rawget(codec, "compress")
  if type(serialize) ~= "function" or type(compress) ~= "function" then
    return nil, "codec"
  end
  local serialized = callString(serialize, data)
  if serialized == nil then
    return nil, "serialize"
  end
  if #serialized > SERIALIZED_MAX then
    return nil, "too_large"
  end
  local compressed = callString(compress, serialized)
  if compressed == nil then
    return nil, "compress"
  end
  return PREFIX .. base64(compressed)
end

function Export.string(input, codec)
  local data, reason = Export.build(input)
  if data == nil then
    return nil, reason
  end
  return Export.encode(data, codec)
end
