-- Notes (glue): notes the innkeepers the data doesn't know. At GOSSIP_SHOW it reads what
-- the client reports about the NPC (its creature GUID, its gossip options' icons, the map
-- chain the player stands in, its faction, the server time) and saves a note in the
-- owner's record, db.global.notes[guid]. Every rule lives in InnNotes (pure); this file
-- holds the event, the client reads and the record writes. Spec: docs/specs/inn-notes.md
-- (sections 3.6 and 3.7).
-- Events only: nothing here hooks the gossip frame, picks a gossip option, binds or reads
-- the bind location, sends anything or touches the fight state. Every client value is
-- checked for hidden values first, every handler is guarded, and nothing is printed to
-- chat with the debug log off. No client string is stored or printed.
local _, ns = ...

local Notes = {}
ns.Notes = Notes

local InnNotes = ns.InnNotes
local Ledger = ns.Ledger
local OPTIONS_MAX = InnNotes.LIMITS.optionsMax
local CHAIN_MAX = InnNotes.LIMITS.chainMax

-- ---------------------------------------------------------------------------
-- Client reads (spec 3.7).

-- The first return of a client function, or nil if it's missing or raises.
local function call(fn, ...)
  if type(fn) ~= "function" then
    return nil
  end
  local ok, value = pcall(fn, ...)
  if ok then
    return value
  end
  return nil
end

-- True for a hidden ("secret") value. Fails closed: an error while checking counts as
-- hidden. Touches nothing else about the value.
local function hidden(value)
  if type(issecretvalue) ~= "function" then
    return false
  end
  local ok, result = pcall(issecretvalue, value)
  return not ok or result ~= false and result ~= nil
end

local function isInteger(x)
  return type(x) == "number" and x == x and x % 1 == 0
end

local function readNpc()
  local npc = call(UnitGUID, "npc")
  if hidden(npc) or type(npc) ~= "string" then
    return nil
  end
  return npc
end

-- The icons of the gossip options, in order, at most OPTIONS_MAX. Nothing else of an
-- option is read; the pure side checks each icon's type.
local function readIcons()
  local icons = {}
  local api = C_GossipInfo
  if type(api) ~= "table" or type(api.GetOptions) ~= "function" then
    return icons
  end
  local opts = call(api.GetOptions)
  if hidden(opts) or type(opts) ~= "table" then
    return icons
  end
  pcall(function()
    for i = 1, OPTIONS_MAX do
      local o = opts[i]
      if rawequal(o, nil) then
        break
      end
      if not hidden(o) and type(o) == "table" then
        local icon = o.icon
        if not hidden(icon) then
          icons[#icons + 1] = icon
        end
      end
    end
  end)
  return icons
end

-- The player's map, then its parents: { id, type, parent } items, at most CHAIN_MAX.
-- Stops at a non-integer or 0 id, a missing map, a hidden value or CHAIN_MAX items.
local function readChain()
  local chain = {}
  local api = C_Map
  if type(api) ~= "table" or type(api.GetBestMapForUnit) ~= "function"
    or type(api.GetMapInfo) ~= "function" then
    return chain
  end
  local id = call(api.GetBestMapForUnit, "player")
  for _ = 1, CHAIN_MAX do
    if hidden(id) or not isInteger(id) or id == 0 then
      break
    end
    local info = call(api.GetMapInfo, id)
    if hidden(info) or type(info) ~= "table" then
      break
    end
    local ok, mapID, mapType, parent = pcall(function()
      return info.mapID, info.mapType, info.parentMapID
    end)
    if not ok or hidden(mapID) or hidden(mapType) or hidden(parent) then
      break
    end
    chain[#chain + 1] = { id = mapID, type = mapType, parent = parent }
    id = parent
  end
  return chain
end

local function readFaction()
  local faction = call(UnitFactionGroup, "npc")
  if hidden(faction) or type(faction) ~= "string" then
    return nil
  end
  return faction
end

local function readNow()
  local now = call(GetServerTime)
  if hidden(now) then
    return nil
  end
  return now
end

-- The owner's GUID from the open ledger (read at use, never cached), or nil.
local function ownerGUID()
  local ledger = ns.ledger
  if not ledger then
    return nil
  end
  local ok, guid = pcall(function() return ledger:ownerGUID() end)
  if ok and Ledger.validGUID(guid) then
    return guid
  end
  return nil
end

local function inns()
  local data = ns.Data
  return type(data) == "table" and data.Inns or nil
end

-- db.global, or nil when it isn't a table.
local function global()
  local db = ns.Core and ns.Core.db
  local g = type(db) == "table" and db.global or nil
  if type(g) == "table" then
    return g
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- Output and guards. Debug lines carry only our own codes and an integer NPC ID.

local function debug(line)
  pcall(function() ns.Core:Debug(line) end)
end

local function guard(where, fn, ...)
  local ok, result = pcall(fn, ...)
  if not ok then
    debug("notes: error in " .. where)
    return nil
  end
  return result
end

-- ---------------------------------------------------------------------------
-- GOSSIP_SHOW (spec 3.7).

local function seen()
  local guid = ownerGUID()
  if not guid then
    return
  end
  local npc = readNpc()
  local id = Ledger.npcFromGUID(npc)
  local data = inns()
  if id == nil or (type(data) == "table" and rawget(data, id) ~= nil) then
    return -- not a creature, or an innkeeper the data knows
  end
  local g = global()
  if not g then
    return
  end
  local all = g.notes
  if all ~= nil and type(all) ~= "table" then
    debug("notes: read-only") -- a damaged notes table is never overwritten
    return
  end
  local r = InnNotes.read(all and all[guid], data)
  if r.writable ~= true then
    debug("notes: read-only")
    return
  end
  local note, why = InnNotes.observe({
    npc = npc, now = readNow(), icons = readIcons(), chain = readChain(),
    faction = readFaction(),
  }, data)
  if note == nil then
    if why == "clock" or why == "place" then
      debug("notes: " .. why)
    end
    return
  end
  local res, items = InnNotes.add(r.items, note)
  if res == "added" then
    local rec = InnNotes.record(items)
    if type(rec) == "table" then
      if all == nil then
        all = {}
        g.notes = all
      end
      all[guid] = rec
      debug("notes: noted " .. note.npc)
    end
  elseif res == "full" then
    debug("notes: full")
  end
end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event)
  if event == "GOSSIP_SHOW" then
    guard("gossip", seen)
  end
end)
frame:RegisterEvent("GOSSIP_SHOW")
Notes.frame = frame

-- ---------------------------------------------------------------------------
-- Login and export (spec 3.6).

-- The owner's record from the saved notes table, or nil with ok == false when there's
-- no owner or the table is unreadable.
local function ownRecord()
  local guid = ownerGUID()
  local g = guid and global()
  if not g then
    return false
  end
  local all = g.notes
  if type(all) ~= "table" then
    return false
  end
  return true, all, guid, all[guid]
end

local function prune()
  local ok, all, guid, rec = ownRecord()
  if not ok or type(rec) ~= "table" then
    return
  end
  local r = InnNotes.read(rec, inns())
  if r.writable == true and type(r.dropped) == "number" and r.dropped > 0 then
    local fresh = InnNotes.record(r.items)
    if type(fresh) == "table" then
      all[guid] = fresh
    end
  end
end

-- Core calls this at login for any opened ledger: drops the notes the data now knows,
-- and invalid or extra ones, from the owner's record. Writes only when something drops.
function Notes.Prune() -- called as Notes:Prune()
  guard("prune", prune)
end

-- The owner's notes for the export: fresh copies, or {} when there are none to read.
-- Never writes.
function Notes.List() -- called as Notes:List()
  local list = guard("list", function()
    local ok, _, _, rec = ownRecord()
    if not ok then
      return {}
    end
    return InnNotes.list(rec, inns())
  end)
  if type(list) == "table" then
    return list
  end
  return {}
end
