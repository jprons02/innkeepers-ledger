-- Collection (pure): the passport math. Validates the place data (inns, zones,
-- continents; a zone's "continent" is a World map when no Continent map is above it) once,
-- then counts the player's own signatures: signed / total overall, by
-- continent, by zone, and per inn. A zone, a continent or the whole atlas is "done" only if
-- the data marks it complete (every inn there is known) and no record was excluded, so a
-- partial atlas can't hand out "every inn" rewards.
-- No WoW API here. Client values come in as arguments (docs/architecture.md -> Modules).
-- Spec: docs/specs/collection-cosmetics.md (sections 3.1-3.4, 3.8, 3.9, 3.11). Own entries come
-- from SavedVariables, which a player can edit: every argument is read with rawget only,
-- with bounded work, never written to, and nothing here throws on any argument. Only the
-- load itself can raise (the assert).
local _, ns = ...

local Ledger = ns.Ledger
assert(type(Ledger) == "table",
  "Collection needs ns.Ledger; Ledger.lua comes first in the TOC")

local Collection = {}
ns.Collection = Collection

local byte, find = string.byte, string.find
local tsort = table.sort

-- Constants (spec 3.8). The locals are what the code uses; the exported tables are copies.
local NAME_BYTES = 48
local MAP_KEY_MAX = 999999
local OWN_MAX = 100000
local INN_MAX = Ledger.LIMITS.innMax -- read from Ledger, not second literals
local T_MIN, T_MAX = Ledger.LIMITS.tMin, Ledger.LIMITS.tMax
-- Zone seal IDs (spec 3.5). Cosmetics.RANGES.zoneSeal holds the same range and Cosmetics
-- checks every zone seal against it again.
local ZONE_SEAL_MIN, ZONE_SEAL_MAX = 101, 999
local FACTIONS = { Alliance = true, Horde = true }

Collection.LIMITS = { nameBytes = NAME_BYTES, mapKeyMax = MAP_KEY_MAX, ownMax = OWN_MAX }
Collection.FACTIONS = { Alliance = true, Horde = true }

-- An integer in lo..hi. NaN fails x == x; inf % 1 is NaN, so inf fails too.
local function isInt(x, lo, hi)
  return type(x) == "number" and x == x and x % 1 == 0 and x >= lo and x <= hi
end

-- ---------------------------------------------------------------------------
-- Record rules (spec 3.2). Explicit byte values only: %a and friends follow the C locale.

local B_SPACE = 32
local ALLOWED = {} -- byte -> true: A-Z a-z 0-9, space and ' , . -
for b = 65, 90 do
  ALLOWED[b] = true
end
for b = 97, 122 do
  ALLOWED[b] = true
end
for b = 48, 57 do
  ALLOWED[b] = true
end
for _, b in ipairs({ 32, 39, 44, 46, 45 }) do
  ALLOWED[b] = true
end

-- Rule 5: 1..maxBytes allowed bytes, first A-Z, no trailing or double space. maxBytes is
-- NAME_BYTES when nil, and otherwise must be an integer in 1..NAME_BYTES (else false).
-- Exported for Cosmetics' catalog names (spec 3.5); never throws.
local function validName(s, maxBytes)
  if maxBytes == nil then
    maxBytes = NAME_BYTES
  elseif not isInt(maxBytes, 1, NAME_BYTES) then
    return false
  end
  if type(s) ~= "string" or #s < 1 or #s > maxBytes then
    return false
  end
  local first = byte(s, 1)
  if first < 65 or first > 90 or byte(s, -1) == B_SPACE or find(s, "  ", 1, true) then
    return false
  end
  for i = 1, #s do
    if not ALLOWED[byte(s, i)] then
      return false
    end
  end
  return true
end

Collection.validName = validName

-- The keys of v (raw) are exactly the keys of `fields`, where `fields[k] == true` means
-- required and `false` optional.
local function exactFields(v, fields)
  for k in next, v do
    if fields[k] == nil then
      return false
    end
  end
  for k, required in next, fields do
    if required and rawget(v, k) == nil then
      return false
    end
  end
  return true
end

-- `complete` is optional on zones and continents (spec 3.11); if present it must be true.
local CONTINENT_FIELDS = { name = true, complete = false }
local ZONE_FIELDS = { name = true, continent = true, seal = true, complete = false }
local INN_FIELDS = { name = true, zone = true, faction = false }
local ALIAS_FIELDS = { alias = true }

-- A short name for an excluded key. Only numbers are printed; any other key is named by
-- its type, so no data string is echoed.
local function label(prefix, k)
  if type(k) == "number" then
    return prefix .. " " .. tostring(k)
  end
  return prefix .. " <" .. type(k) .. ">"
end

-- A completeness mark (spec 3.11): absent, or exactly true. Anything else fails the record.
local function validMark(v)
  return v == nil or rawequal(v, true)
end

-- ---------------------------------------------------------------------------
-- bind (spec 3.8): validate and index once, return closures over the private copy.

function Collection.bind(inns, zones, continents, atlasComplete)
  if type(inns) ~= "table" then
    inns = {}
  end
  if type(zones) ~= "table" then
    zones = {}
  end
  if type(continents) ~= "table" then
    continents = {}
  end
  local invalid = {}

  -- 1. Continents (a zone's group: a Continent map, or a World map with no Continent
  -- between). A map ID is one map, so a key in both tables excludes both records, whatever
  -- they hold: we can't tell which one is wrong (rule 6).
  local conts = {} -- key -> { name, marked }
  for k, v in next, continents do
    if isInt(k, 1, MAP_KEY_MAX) and rawget(zones, k) == nil and type(v) == "table"
      and exactFields(v, CONTINENT_FIELDS) and validName(rawget(v, "name"))
      and validMark(rawget(v, "complete")) then
      conts[k] = { name = rawget(v, "name"), marked = rawget(v, "complete") == true }
    else
      invalid[#invalid + 1] = label("continent", k)
    end
  end

  -- 2. Zones. A seal used by two or more zone records (any record with a seal in range,
  -- kept or not) excludes all of them, whatever order `next` visits them in.
  local sealUses = {}
  for _, v in next, zones do
    local seal = type(v) == "table" and rawget(v, "seal") or nil
    if isInt(seal, ZONE_SEAL_MIN, ZONE_SEAL_MAX) then
      sealUses[seal] = (sealUses[seal] or 0) + 1
    end
  end
  local zoneRecs, zoneKeys = {}, {} -- key -> { name, continent, seal, complete }; sorted keys
  for k, v in next, zones do
    local ok = isInt(k, 1, MAP_KEY_MAX) and rawget(continents, k) == nil and type(v) == "table"
      and exactFields(v, ZONE_FIELDS)
    local name, continent, seal, mark
    if ok then
      name, continent, seal = rawget(v, "name"), rawget(v, "continent"), rawget(v, "seal")
      mark = rawget(v, "complete")
      ok = validName(name) and isInt(continent, 1, MAP_KEY_MAX) and conts[continent] ~= nil
        and isInt(seal, ZONE_SEAL_MIN, ZONE_SEAL_MAX) and sealUses[seal] == 1
        and validMark(mark)
    end
    if ok then
      zoneRecs[k] = { name = name, continent = continent, seal = seal, complete = mark == true }
      zoneKeys[#zoneKeys + 1] = k
    else
      invalid[#invalid + 1] = label("zone", k)
    end
  end
  tsort(zoneKeys)

  -- 3. Primary inns; aliases wait for step 4.
  local primaries, primaryKeys, innOf = {}, {}, {} -- key -> record; sorted keys; NPC -> key
  local aliases = {}
  for k, v in next, inns do
    local ok = isInt(k, 1, INN_MAX) and type(v) == "table"
    if ok and rawget(v, "alias") ~= nil then
      if exactFields(v, ALIAS_FIELDS) then
        aliases[#aliases + 1] = k
      else
        ok = false
      end
    elseif ok then
      local name, zone, faction = rawget(v, "name"), rawget(v, "zone"), rawget(v, "faction")
      ok = exactFields(v, INN_FIELDS) and validName(name) and isInt(zone, 1, MAP_KEY_MAX)
        and zoneRecs[zone] ~= nil
        and (faction == nil or (type(faction) == "string" and FACTIONS[faction] == true))
      if ok then
        primaries[k] = { name = name, zone = zone, faction = faction }
        primaryKeys[#primaryKeys + 1] = k
        innOf[k] = k
      end
    end
    if not ok then
      invalid[#invalid + 1] = label("inn", k)
    end
  end
  tsort(primaryKeys)

  -- 4. Aliases: one hop to a kept primary (not an alias, not itself, not excluded).
  for _, k in ipairs(aliases) do
    local target = rawget(rawget(inns, k), "alias")
    if isInt(target, 1, INN_MAX) and target ~= k and primaries[target] ~= nil then
      innOf[k] = target
    else
      invalid[#invalid + 1] = label("inn", k)
    end
  end
  tsort(invalid)

  -- Effective completeness (spec 3.11): a zone as marked; a continent if marked and every
  -- kept zone on it is complete; the atlas if marked and every kept continent is complete.
  -- Fail closed (#118): once any record of any kind is excluded, nothing is complete. An
  -- excluded record can't always be traced to a place, and a marked zone that lost an inn
  -- would otherwise still hand out its seal for good (spec 3.6).
  local clean = #invalid == 0
  for _, rec in next, zoneRecs do
    rec.complete = clean and rec.complete
  end
  for _, rec in next, conts do
    rec.complete = clean and rec.marked
  end
  for _, rec in next, zoneRecs do
    if not rec.complete then
      conts[rec.continent].complete = false
    end
  end
  local atlasDone = clean and rawequal(atlasComplete, true)
  for _, rec in next, conts do
    if not rec.complete then
      atlasDone = false
    end
  end

  local atlas = { invalid = invalid }

  -- Spec 3.3. Own entries only, read raw, at most OWN_MAX of them.
  function atlas.progress(own, faction)
    local f = (type(faction) == "string" and FACTIONS[faction] == true) and faction or nil
    local count, first, last = {}, {}, {}
    local unknown, truncated = 0, false
    if type(own) == "table" then
      for i = 1, OWN_MAX + 1 do
        local e = rawget(own, i)
        if e == nil then
          break
        elseif i > OWN_MAX then
          truncated = true
          break
        end
        if type(e) == "table" then
          local inn, t = rawget(e, "inn"), rawget(e, "t")
          if isInt(inn, 1, INN_MAX) and isInt(t, T_MIN, T_MAX) then
            local key = innOf[inn]
            if key == nil then
              unknown = unknown + 1
            else
              count[key] = (count[key] or 0) + 1
              if first[key] == nil or t < first[key] then
                first[key] = t
              end
              if last[key] == nil or t > last[key] then
                last[key] = t
              end
            end
          end
        end
      end
    end

    local res = {
      faction = f, signed = 0, total = 0, byContinent = {}, byZone = {}, inns = {},
      unknown = unknown, truncated = truncated, complete = atlasDone,
    }
    -- The largest `first` among signed open inns, per zone, per continent and overall.
    local zoneMax, contMax, allMax = {}, {}, nil
    for _, key in ipairs(primaryKeys) do
      local rec = primaries[key]
      local open = f == nil or rec.faction == nil or rec.faction == f
      local c = count[key] or 0
      res.inns[key] = {
        zone = rec.zone, open = open, count = c, first = first[key], last = last[key],
      }
      if open then
        local zkey = rec.zone
        local ckey = zoneRecs[zkey].continent
        local z = res.byZone[zkey]
        if z == nil then
          z = { signed = 0, total = 0, continent = ckey, complete = zoneRecs[zkey].complete }
          res.byZone[zkey] = z
        end
        local cont = res.byContinent[ckey]
        if cont == nil then
          cont = { signed = 0, total = 0, complete = conts[ckey].complete }
          res.byContinent[ckey] = cont
        end
        z.total, cont.total, res.total = z.total + 1, cont.total + 1, res.total + 1
        if c > 0 then
          local t = first[key]
          z.signed, cont.signed, res.signed = z.signed + 1, cont.signed + 1, res.signed + 1
          if zoneMax[zkey] == nil or t > zoneMax[zkey] then
            zoneMax[zkey] = t
          end
          if contMax[ckey] == nil or t > contMax[ckey] then
            contMax[ckey] = t
          end
          if allMax == nil or t > allMax then
            allMax = t
          end
        end
      end
    end
    -- `done` only for a place the data knows in full (spec 3.11).
    for zkey, z in next, res.byZone do
      if z.complete and z.signed == z.total then
        z.done = zoneMax[zkey]
      end
    end
    for ckey, cont in next, res.byContinent do
      if cont.complete and cont.signed == cont.total then
        cont.done = contMax[ckey]
      end
    end
    if atlasDone and res.total >= 1 and res.signed == res.total then
      res.done = allMax
    end
    return res
  end

  function atlas.innOf(npcId)
    if not isInt(npcId, 1, INN_MAX) then
      return nil
    end
    return innOf[npcId]
  end

  function atlas.inn(key)
    local rec = isInt(key, 1, INN_MAX) and primaries[key] or nil
    if rec == nil then
      return nil
    end
    return { name = rec.name, zone = rec.zone, faction = rec.faction }
  end

  function atlas.zone(key)
    local rec = isInt(key, 1, MAP_KEY_MAX) and zoneRecs[key] or nil
    if rec == nil then
      return nil
    end
    return { name = rec.name, continent = rec.continent, seal = rec.seal, complete = rec.complete }
  end

  function atlas.continent(key)
    local rec = isInt(key, 1, MAP_KEY_MAX) and conts[key] or nil
    if rec == nil then
      return nil
    end
    return { name = rec.name, complete = rec.complete }
  end

  -- Spec 3.11: true if the data marks every continent with an inn, and each is complete.
  function atlas.complete()
    return atlasDone
  end

  function atlas.zoneKeys()
    local out = {}
    for i, k in ipairs(zoneKeys) do
      out[i] = k
    end
    return out
  end

  return atlas
end

-- ---------------------------------------------------------------------------
-- The default atlas, over the shipped data (spec 3.9). Missing data binds an empty atlas;
-- a bad record is left out and named in `invalid`, never raised.

local inns, zones, continents, atlasComplete
if type(ns.Data) == "table" then
  inns, zones, continents = ns.Data.Inns, ns.Data.Zones, ns.Data.Continents
  atlasComplete = ns.Data.AtlasComplete
end
Collection.atlas = Collection.bind(inns, zones, continents, atlasComplete)
for _, name in ipairs({ "progress", "innOf", "inn", "zone", "continent", "zoneKeys",
  "complete" }) do
  Collection[name] = Collection.atlas[name]
end
Collection.invalid = Collection.atlas.invalid
