-- InnNotes (pure): the rules for noting innkeepers the data doesn't know. Recognizing an
-- innkeeper from its gossip options' icons, the zone and continent from a map chain, the
-- note rule, and the saved record (read, normalize, add, dedupe, cap, prune) plus the list
-- the export carries. Notes.lua is the glue that reads the client and writes the record.
-- No WoW API here. Client values come in as arguments (docs/architecture.md -> Modules).
-- Spec: docs/specs/inn-notes.md (sections 3.2-3.6 and 4.1). The saved record comes from
-- SavedVariables, which a player can edit: every argument is read with rawget / raw next
-- only, with bounded work, never written to, and nothing here throws on any argument
-- (each body runs in pcall). Only the load itself can raise (the asserts).
local _, ns = ...

local Ledger = ns.Ledger
assert(type(Ledger) == "table", "InnNotes needs ns.Ledger; Ledger.lua comes first in the TOC")
local Collection = ns.Collection
assert(type(Collection) == "table",
  "InnNotes needs ns.Collection; Collection.lua comes first in the TOC")

local InnNotes = {}
ns.InnNotes = InnNotes

local tsort = table.sort

-- Constants (spec 3.2). The locals are what the code uses; the exported tables are copies.
local VERSION = 1
local BINDER_ICON = 132052
local WORLD, CONTINENT, ZONE, COSMIC = 1, 2, 3, 0 -- Enum.UIMapType's values, seen in live
local MAX = 200
local READ_MAX = 1000
local OPTIONS_MAX = 32
local CHAIN_MAX = 8

-- Read from Ledger and Collection, not second literals.
local INN_MAX, T_MIN, T_MAX = Ledger.LIMITS.innMax, Ledger.LIMITS.tMin, Ledger.LIMITS.tMax
local MAP_KEY_MAX = Collection.LIMITS.mapKeyMax
local npcFromGUID = Ledger.npcFromGUID

InnNotes.VERSION = VERSION
InnNotes.BINDER_ICON = BINDER_ICON
InnNotes.MAP_TYPE = { world = WORLD, continent = CONTINENT, zone = ZONE }
InnNotes.LIMITS = {
  max = MAX, readMax = READ_MAX, optionsMax = OPTIONS_MAX, chainMax = CHAIN_MAX,
}

local FACTIONS = { Alliance = true, Horde = true }
local NOTE_KEYS = { npc = true, t = true, zone = true, continent = true, faction = true }

-- An integer. NaN fails x == x; inf % 1 is NaN, so inf fails too.
local function isInteger(x)
  return type(x) == "number" and x == x and x % 1 == 0
end

local function isInt(x, lo, hi)
  return isInteger(x) and x >= lo and x <= hi
end

-- True if `inns` (the Data/Inns table) has a record under `id`: a primary or an alias.
-- A non-table counts as empty, so every NPC counts as unknown.
local function known(inns, id)
  return type(inns) == "table" and rawget(inns, id) ~= nil
end

-- ---------------------------------------------------------------------------
-- Recognizing an innkeeper (spec 3.3).

local function isInnkeeper(icons)
  if type(icons) ~= "table" then
    return false
  end
  for i = 1, OPTIONS_MAX do
    local icon = rawget(icons, i)
    if icon == nil then
      return false
    end
    if type(icon) == "number" and icon == BINDER_ICON then
      return true
    end
  end
  return false
end

-- ---------------------------------------------------------------------------
-- The zone and continent from a map chain (spec 3.4).

local function place(chain)
  if type(chain) ~= "table" then
    return nil
  end
  local seen = {}
  local zone, continent
  for i = 1, CHAIN_MAX do
    local item = rawget(chain, i)
    if type(item) ~= "table" then
      break
    end
    local id, kind = rawget(item, "id"), rawget(item, "type")
    if not isInt(id, 1, MAP_KEY_MAX) or not isInteger(kind) or seen[id] then
      break
    end
    seen[id] = true
    if zone == nil then
      if kind == ZONE then
        zone = id
      elseif kind == WORLD or kind == CONTINENT or kind == COSMIC then
        return nil -- no zone below the continent
      end
      -- Below the zone (a dungeon, a micro map, a building's own map): skipped.
    elseif kind == CONTINENT or kind == WORLD then
      continent = id
      break
    elseif kind == COSMIC then
      return nil
    end
  end
  if zone == nil or continent == nil or zone == continent then
    return nil
  end
  return zone, continent
end

-- ---------------------------------------------------------------------------
-- The note rule (spec 4.1).

local function validNote(n)
  if type(n) ~= "table" then
    return false
  end
  for k in next, n do
    if NOTE_KEYS[k] ~= true then
      return false
    end
  end
  local zone, continent = rawget(n, "zone"), rawget(n, "continent")
  local faction = rawget(n, "faction")
  return isInt(rawget(n, "npc"), 1, INN_MAX)
    and isInt(rawget(n, "t"), T_MIN, T_MAX)
    and isInt(zone, 1, MAP_KEY_MAX) and isInt(continent, 1, MAP_KEY_MAX)
    and zone ~= continent
    and (faction == nil or (type(faction) == "string" and FACTIONS[faction] == true))
end

-- A fresh copy of a note that passed validNote, with only its five keys.
local function copyNote(n)
  return {
    npc = rawget(n, "npc"), t = rawget(n, "t"), zone = rawget(n, "zone"),
    continent = rawget(n, "continent"), faction = rawget(n, "faction"),
  }
end

local function noteLess(a, b)
  if a.t ~= b.t then
    return a.t < b.t
  end
  return a.npc < b.npc
end

-- ---------------------------------------------------------------------------
-- A note from what the glue read (spec 3.5).

local function observe(s, inns)
  if type(s) ~= "table" then
    return nil, "npc"
  end
  local id = npcFromGUID(rawget(s, "npc"))
  if id == nil then
    return nil, "npc"
  elseif known(inns, id) then
    return nil, "known"
  elseif not isInnkeeper(rawget(s, "icons")) then
    return nil, "not_innkeeper"
  end
  local now = rawget(s, "now")
  if not isInt(now, T_MIN, T_MAX) then
    return nil, "clock"
  end
  local zone, continent = place(rawget(s, "chain"))
  if zone == nil then
    return nil, "place"
  end
  local faction = rawget(s, "faction")
  local note = { npc = id, t = now, zone = zone, continent = continent }
  if type(faction) == "string" and FACTIONS[faction] == true then
    note.faction = faction
  end
  return note
end

-- ---------------------------------------------------------------------------
-- The saved record (spec 3.5).

local function readOnly()
  return { items = {}, writable = false, dropped = 0 }
end

-- The kept items of a v1 record's `items`: valid, unknown, first per NPC in index order,
-- sorted by (t, npc), the oldest MAX. Returns them and how many were read and not kept.
local function normalize(items, inns)
  local out, kept, dropped = {}, {}, 0
  if type(items) ~= "table" then
    return out, 0
  end
  for i = 1, READ_MAX do
    local it = rawget(items, i)
    if it == nil then
      break
    end
    local npc = validNote(it) and rawget(it, "npc")
    if npc and not known(inns, npc) and not kept[npc] then
      kept[npc] = true
      out[#out + 1] = copyNote(it)
    else
      dropped = dropped + 1
    end
  end
  if rawget(items, READ_MAX + 1) ~= nil then
    dropped = dropped + 1 -- items left unread past readMax
  end
  tsort(out, noteLess)
  for i = #out, MAX + 1, -1 do
    out[i] = nil
    dropped = dropped + 1
  end
  return out, dropped
end

local function read(rec, inns)
  if rec == nil then
    return { items = {}, writable = true, dropped = 0 }
  elseif type(rec) ~= "table" then
    return readOnly() -- damaged: never overwritten
  end
  local v = rawget(rec, "v")
  if isInteger(v) and v > VERSION then
    return readOnly() -- a newer AddOn wrote it
  elseif v ~= VERSION then
    return { items = {}, writable = true, dropped = 1 } -- broken: the next write replaces it
  end
  local items, dropped = normalize(rawget(rec, "items"), inns)
  return { items = items, writable = true, dropped = dropped }
end

-- The valid items of an array (at most MAX, first per NPC), as fresh copies in order.
local function validItems(items)
  local out, kept = {}, {}
  if type(items) ~= "table" then
    return out
  end
  for i = 1, READ_MAX do
    local it = rawget(items, i)
    if it == nil or #out >= MAX then
      break
    end
    if validNote(it) then
      local npc = rawget(it, "npc")
      if not kept[npc] then
        kept[npc] = true
        out[#out + 1] = copyNote(it)
      end
    end
  end
  return out
end

local function add(items, note)
  if not validNote(note) then
    return "invalid", nil
  end
  local list = validItems(items)
  local npc = rawget(note, "npc")
  for i = 1, #list do
    if list[i].npc == npc then
      return "dup", nil -- first note wins
    end
  end
  if #list >= MAX then
    return "full", nil -- nothing is evicted
  end
  list[#list + 1] = copyNote(note)
  tsort(list, noteLess)
  return "added", list
end

local function record(items)
  return { v = VERSION, items = validItems(items) }
end

-- ---------------------------------------------------------------------------
-- The API: every body in pcall, its failure value returned.

function InnNotes.isInnkeeper(icons)
  local ok, result = pcall(isInnkeeper, icons)
  return ok and result == true
end

function InnNotes.place(chain)
  local ok, zone, continent = pcall(place, chain)
  if ok and zone ~= nil then
    return zone, continent
  end
  return nil
end

function InnNotes.validNote(n)
  local ok, result = pcall(validNote, n)
  return ok and result == true
end

function InnNotes.observe(s, inns)
  local ok, note, reason = pcall(observe, s, inns)
  if ok then
    return note, reason
  end
  return nil, "error"
end

function InnNotes.read(rec, inns)
  local ok, result = pcall(read, rec, inns)
  if ok then
    return result
  end
  return readOnly()
end

function InnNotes.add(items, note)
  local ok, result, list = pcall(add, items, note)
  if ok then
    return result, list
  end
  return "invalid", nil
end

function InnNotes.record(items)
  local ok, result = pcall(record, items)
  if ok then
    return result
  end
  return nil
end

function InnNotes.list(rec, inns)
  local ok, result = pcall(read, rec, inns)
  if ok then
    return result.items
  end
  return {}
end
