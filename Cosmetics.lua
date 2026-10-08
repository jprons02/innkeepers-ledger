-- Cosmetics (pure): the catalog of seals and quills, which of them the player's own
-- signatures unlock and when, and SEALS, the seal table peers' entries are checked against.
-- No WoW API here. Client values come in as arguments (docs/architecture.md -> Modules).
-- Spec: docs/specs/collection-cosmetics.md (sections 3.5-3.9). SEALS is SyncProtocol's
-- `seals` (rule 16), so it decides which peer entries are stored: it holds every seal the
-- catalog knows and nothing else. Arguments are read with rawget only, with bounded work,
-- never written to, and nothing here throws on any argument. Only the load itself can raise
-- (the asserts).
local _, ns = ...

local Ledger = ns.Ledger
assert(type(Ledger) == "table", "Cosmetics needs ns.Ledger; Ledger.lua comes first in the TOC")
local Collection = ns.Collection
assert(type(Collection) == "table",
  "Cosmetics needs ns.Collection; Collection.lua comes first in the TOC")

local validName = Collection.validName
assert(type(validName) == "function", "Cosmetics needs Collection.validName")

local Cosmetics = {}
ns.Cosmetics = Cosmetics

local tsort = table.sort

-- Constants (spec 3.5, 3.8). The locals are what the code uses; RANGES is exported as a copy.
local RANGES = {
  seal = { 1, 99 },
  zoneSeal = { 101, 999 },
  quill = { 1000, 1099 },
}
-- 1100..1199 held inks until 2026-10-06 (none was released); it stays reserved.
local ID_MAX = Ledger.LIMITS.cosmeticIdMax -- read from Ledger, not second literals
local SEAL_MAX = Ledger.LIMITS.sealMax
local T_MIN, T_MAX = Ledger.LIMITS.tMin, Ledger.LIMITS.tMax
local INN_MAX = Ledger.LIMITS.innMax
local OWN_MAX = type(Collection.LIMITS) == "table" and Collection.LIMITS.ownMax or 0
local NAME_BYTES = 32
local ZONE_NAME_BYTES = type(Collection.LIMITS) == "table" and Collection.LIMITS.nameBytes or 0
local INNS_N_MAX, ZONES_N_MAX = 9999, 999

-- Every seal must fit the wire's seal token; every ID must fit the `earned` key space.
assert(RANGES.seal[2] <= SEAL_MAX and RANGES.zoneSeal[2] <= SEAL_MAX,
  "Cosmetics: a seal range is over Ledger.LIMITS.sealMax")
assert(RANGES.quill[2] <= ID_MAX, "Cosmetics: an ID range is over Ledger.LIMITS.cosmeticIdMax")

Cosmetics.RANGES = {
  seal = { RANGES.seal[1], RANGES.seal[2] },
  zoneSeal = { RANGES.zoneSeal[1], RANGES.zoneSeal[2] },
  quill = { RANGES.quill[1], RANGES.quill[2] },
}

-- An integer in lo..hi. NaN fails x == x; inf % 1 is NaN, so inf fails too.
local function isInt(x, lo, hi)
  return type(x) == "number" and x == x and x % 1 == 0 and x >= lo and x <= hi
end

-- ---------------------------------------------------------------------------
-- Record rules (spec 3.5). Names follow Collection's rule 5 (spec 3.2), at 32 bytes:
-- Collection.validName is the one copy of that rule.

local RECORD_FIELDS = { kind = true, name = true, rule = true }
-- Catalog kinds and their ID ranges. Zone seals never come from the catalog.
local KIND_RANGE = { seal = RANGES.seal, quill = RANGES.quill }
-- Each rule kind's fields besides `kind`, with the range of `n`.
local RULE_N = { inns = INNS_N_MAX, zones = ZONES_N_MAX, continent = false, all = false }

-- A private copy of a valid rule, or nil.
local function checkRule(rule)
  if type(rule) ~= "table" then
    return nil
  end
  local kind = rawget(rule, "kind")
  local nMax -- the largest n, false for a rule without one, nil for an unknown kind
  if type(kind) == "string" then
    nMax = RULE_N[kind]
  end
  if nMax == nil then
    return nil
  end
  for k in next, rule do
    if k ~= "kind" and not (k == "n" and nMax) then
      return nil
    end
  end
  if not nMax then
    return { kind = kind }
  end
  local n = rawget(rule, "n")
  if not isInt(n, 1, nMax) then
    return nil
  end
  return { kind = kind, n = n }
end

-- The private record for (id, v), or nil if any rule fails.
local function checkRecord(id, v)
  if not isInt(id, 1, ID_MAX) or type(v) ~= "table" then
    return nil
  end
  local kind = rawget(v, "kind")
  local range = type(kind) == "string" and KIND_RANGE[kind] or nil
  if range == nil or id < range[1] or id > range[2] then
    return nil
  end
  for k in next, v do
    if not RECORD_FIELDS[k] then
      return nil
    end
  end
  local name = rawget(v, "name")
  local rule = checkRule(rawget(v, "rule"))
  if not validName(name, NAME_BYTES) or rule == nil then
    return nil
  end
  return { id = id, kind = kind, name = name, rule = rule }
end

local function label(k)
  if type(k) == "number" then
    return "cosmetic " .. tostring(k)
  end
  return "cosmetic <" .. type(k) .. ">"
end

local function copyInfo(rec)
  local rule = { kind = rec.rule.kind, n = rec.rule.n, zone = rec.rule.zone }
  return { id = rec.id, kind = rec.kind, name = rec.name, rule = rule }
end

local ZONES_MAX = RANGES.zoneSeal[2] - RANGES.zoneSeal[1] + 1 -- one seal each

-- The zone seal records of an atlas: { [seal] = record }, or nil if anything about its
-- zones is off (a real atlas has already checked them; this is the second line).
local function zoneSeals(atlas)
  local out = {}
  local keys = atlas.zoneKeys()
  if type(keys) ~= "table" then
    return nil
  end
  for i = 1, ZONES_MAX + 1 do
    local key = rawget(keys, i)
    if key == nil then
      return out
    elseif i > ZONES_MAX or type(key) ~= "number" then
      return nil
    end
    local z = atlas.zone(key)
    local seal = type(z) == "table" and rawget(z, "seal") or nil
    local name = type(z) == "table" and rawget(z, "name") or nil
    if not isInt(seal, RANGES.zoneSeal[1], RANGES.zoneSeal[2]) or out[seal] ~= nil
      or not validName(name, ZONE_NAME_BYTES) then
      return nil
    end
    out[seal] = { id = seal, kind = "seal", name = name, rule = { kind = "zone", zone = key } }
  end
  -- Not reached: the loop returns at the first missing key or past ZONES_MAX.
end

-- The times of every own entry progress would read (spec 3.6: a kept time must be one).
local function entryTimes(own)
  local times = {}
  if type(own) ~= "table" then
    return times
  end
  for i = 1, OWN_MAX do
    local e = rawget(own, i)
    if e == nil then
      break
    end
    if type(e) == "table" then
      local t = rawget(e, "t")
      if isInt(rawget(e, "inn"), 1, INN_MAX) and isInt(t, T_MIN, T_MAX) then
        times[t] = true
      end
    end
  end
  return times
end

local function unlockLess(a, b)
  if a.t ~= b.t then
    return a.t < b.t
  end
  return a.id < b.id
end

-- ---------------------------------------------------------------------------
-- bind (spec 3.8).

function Cosmetics.bind(atlas, catalog)
  if type(catalog) ~= "table" then
    catalog = {}
  end
  local zones
  if type(atlas) == "table" and type(rawget(atlas, "progress")) == "function"
    and type(rawget(atlas, "zoneKeys")) == "function" and type(rawget(atlas, "zone")) == "function"
  then
    local ok, res = pcall(zoneSeals, atlas)
    zones = ok and res or nil
  end
  if zones == nil then
    -- No usable atlas: an empty one (fail closed: no zone seals, nothing unlocked by it).
    atlas = Collection.bind()
    zones = {}
  end
  local progress = atlas.progress

  local invalid = {}
  local records, ids = {}, {} -- id -> private record; sorted IDs
  for id, v in next, catalog do
    local rec = checkRecord(id, v)
    if rec == nil then
      invalid[#invalid + 1] = label(id)
    else
      records[id] = rec
      ids[#ids + 1] = id
    end
  end
  for seal, rec in next, zones do
    records[seal] = rec
    ids[#ids + 1] = seal
  end
  tsort(ids)
  tsort(invalid)

  -- Seals: a private lookup for canSeal, and SEALS, the copy handed out.
  local sealKnown, SEALS = {}, {}
  for _, id in ipairs(ids) do
    if records[id].kind == "seal" then
      sealKnown[id] = true
      SEALS[id] = copyInfo(records[id])
    end
  end
  local nIds = #ids

  local set = { SEALS = SEALS, invalid = invalid }

  function set.info(id)
    local rec = isInt(id, 1, ID_MAX) and records[id] or nil
    if rec == nil then
      return nil
    end
    return copyInfo(rec)
  end

  function set.catalog()
    local out = {}
    for i, id in ipairs(ids) do
      out[i] = copyInfo(records[id])
    end
    return out
  end

  -- Spec 3.6: derived from the entries on every call; `kept` is only a floor.
  local function unlocked(own, faction, kept)
    local p = progress(own, faction)

    -- Derived-time inputs, each sorted or reduced, so `next` order never matters.
    local firsts, zoneDones, contDone = {}, {}, nil
    for _, s in next, p.inns do
      if s.open and s.first ~= nil then
        firsts[#firsts + 1] = s.first
      end
    end
    tsort(firsts)
    for _, z in next, p.byZone do
      if z.done ~= nil then
        zoneDones[#zoneDones + 1] = z.done
      end
    end
    tsort(zoneDones)
    for _, c in next, p.byContinent do
      if c.done ~= nil and (contDone == nil or c.done < contDone) then
        contDone = c.done
      end
    end

    local function derived(rule)
      local kind = rule.kind
      if kind == "inns" then
        return firsts[rule.n]
      elseif kind == "zones" then
        return zoneDones[rule.n]
      elseif kind == "continent" then
        return contDone
      elseif kind == "all" then
        return p.done
      end
      local z = p.byZone[rule.zone]
      return z and z.done
    end

    local times = type(kept) == "table" and entryTimes(own) or nil
    local out = {}
    for _, id in ipairs(ids) do
      local t = derived(records[id].rule)
      if times ~= nil then
        local k = rawget(kept, id)
        if isInt(k, T_MIN, T_MAX) and times[k] and (t == nil or k < t) then
          t = k
        end
      end
      if t ~= nil then
        out[#out + 1] = { id = id, t = t }
      end
    end
    tsort(out, unlockLess)
    return out
  end

  function set.unlocked(own, faction, kept)
    local ok, res = pcall(unlocked, own, faction, kept)
    if ok then
      return res
    end
    return {}
  end

  -- Spec 3.7: exactly true or false. At most nIds + 1 items of `unlocked` are read.
  function set.canSeal(list, seal, t)
    if not isInt(t, T_MIN, T_MAX) then
      return false
    end
    if seal == nil then
      return true
    end
    if not isInt(seal, 1, SEAL_MAX) or sealKnown[seal] ~= true or type(list) ~= "table" then
      return false
    end
    for i = 1, nIds + 1 do
      local item = rawget(list, i)
      if item == nil then
        return false
      end
      if type(item) == "table" and rawequal(rawget(item, "id"), seal) then
        local u = rawget(item, "t")
        if isInt(u, T_MIN, T_MAX) and u <= t then
          return true
        end
      end
    end
    return false
  end

  return set
end

-- ---------------------------------------------------------------------------
-- The default set, over the shipped data (spec 3.9). Missing data binds an empty set, whose
-- SEALS is empty (fail closed for peers); a bad record is left out, never raised.

local catalog
if type(ns.Data) == "table" then
  catalog = ns.Data.Cosmetics
end
local default = Cosmetics.bind(Collection.atlas, catalog)
for _, name in ipairs({ "SEALS", "invalid", "info", "catalog", "unlocked", "canSeal" }) do
  Cosmetics[name] = default[name]
end
