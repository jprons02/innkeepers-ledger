-- Core (glue): AceAddon setup, AceDB SavedVariables, opening the character's ledger at
-- login, the /ledger command, the debug log and the export string's glue.
-- Specs: docs/specs/sync-glue.md (sections 3.2 and 3.8), docs/specs/export.md (3.7).
local ADDON_NAME, ns = ...

local Core = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "AceConsole-3.0", "AceEvent-3.0")
ns.Core = Core

local Ledger = ns.Ledger
local floor = math.floor

local GetAddOnMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata

-- Known weekly-reset times by GetCurrentRegion(), for when the client can't say (spec 3.2).
-- Other regions' rows come from the in-client checks (#12); a missing row uses the US one.
local US = 1
Core.RESET_FALLBACK = {
  [US] = 1790089200, -- Tuesday 2026-09-22 15:00 UTC
}

local GUID_ATTEMPTS = 5
local GUID_RETRY_SECONDS = 2
local RESET_MAX_SECONDS = 604860 -- a week plus 60 s of tolerance
local DEBUG_LINES = 5
local DEBUG_WINDOW = 10

-- The order the debug report lists the sync counters in (spec 3.8).
local STAT_NAMES = {
  "received", "dropped", "added", "dup", "rejected", "evicted", "sent", "sendFailed",
  "errors",
}

-- The packager replaces @project-version@; an unpackaged checkout reports "dev".
local function version()
  local v = GetAddOnMetadata(ADDON_NAME, "Version")
  if not v or v:find("@", 1, true) then
    return "dev"
  end
  return v
end

local function isInt(x, lo, hi)
  return type(x) == "number" and x == x and x % 1 == 0 and x >= lo and x <= hi
end

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

-- The owner's GUID if it's readable and valid, else nil. Nothing indexes a table with a
-- hidden value: it's checked before anything else touches it.
local function ownerGUID()
  local guid = call(UnitGUID, "player")
  if hidden(guid) or not Ledger.validGUID(guid) then
    return nil
  end
  return guid
end

-- The owner's name for display, or nil if it's hidden or not a string. Forever's
-- two-part names come back as "First", "Surname" (the surname in the realm slot), and
-- the name is then "First Surname", the form its senders arrive in (sync-glue.md 3.4).
-- Retail's slot holds our realm, so its name is unchanged. The same read and rule as
-- Sync's name form (Sync.readOwnName), so the two agree whenever both read the same values.
local function ownerName()
  local api = {
    UnitFullName = UnitFullName,
    UnitName = UnitName,
    GetNormalizedRealmName = GetNormalizedRealmName,
  }
  return (ns.Sync.readOwnName(api, hidden))
end

-- The server time of a weekly reset (sync-ledger.md 8 -> Weekly reset source).
local function weekAnchor()
  local now = call(GetServerTime)
  if type(C_DateAndTime) == "table" and not hidden(now)
    and isInt(now, 0, Ledger.LIMITS.tMax) then
    local secs = call(C_DateAndTime.GetSecondsUntilWeeklyReset)
    if not hidden(secs) and type(secs) == "number" and secs == secs
      and secs >= 0 and secs <= RESET_MAX_SECONDS then
      return floor((now + secs + 30) / 60) * 60
    end
  end
  local region = call(GetCurrentRegion)
  if hidden(region) or type(region) ~= "number" or region ~= region then
    region = US
  end
  return Core.RESET_FALLBACK[region] or Core.RESET_FALLBACK[US]
end

-- The saved table for `guid`: created on first login, never replaced (spec 3.2 step 4).
-- `false` when the saved ledgers table (or the `global` holding it) is damaged.
local function savedLedger(db, guid)
  if type(db.global) ~= "table" then
    return false
  end
  if db.global.ledgers == nil then
    db.global.ledgers = {}
  end
  local all = db.global.ledgers
  if type(all) ~= "table" then
    return false
  end
  if all[guid] == nil then
    all[guid] = {}
  end
  return all[guid]
end

function Core:OnInitialize()
  self.db = LibStub("AceDB-3.0"):New("InnkeepersLedgerDB", {}, true)
  self:RegisterChatCommand("ledger", "SlashCommand")
end

-- Runs at PLAYER_LOGIN.
function Core:OnEnable()
  self:OpenLedger()
end

-- Opens db.global.ledgers[guid] as ns.ledger, then starts Sync (spec 3.2). An unreadable
-- GUID is retried every 2 s, 5 attempts in all; after that there's no ledger this session.
function Core:OpenLedger(attempt)
  attempt = attempt or 1
  ns.ledger = nil
  local guid = ownerGUID()
  if not guid then
    if attempt < GUID_ATTEMPTS then
      self.ledgerState = "not open yet"
      C_Timer.After(GUID_RETRY_SECONDS, function() self:OpenLedger(attempt + 1) end)
    else
      self.ledgerState = "no GUID"
    end
    return
  end

  local name = ownerName()
  local data = savedLedger(self.db, guid)
  local ok, ledger = pcall(function()
    return Ledger.new(data, { guid = guid, name = name }, weekAnchor())
  end)
  if ok then
    ns.ledger = ledger
    self.ledgerState = "open"
    if not ledger.readOnly and Ledger.validName(name) then
      ledger:setOwnerName(name)
    end
  else
    self.ledgerState = "open failed"
  end
  ns.Sync:Start()
end

-- "ledger: open, migrated, quarantined 2" or "ledger: read-only (bad_field)".
local function ledgerReport()
  local ledger = ns.ledger
  if not ledger then
    return "ledger: " .. (Core.ledgerState or "not open yet")
  end
  local report = ledger.loadReport or {}
  local parts = { ledger.readOnly and "ledger: read-only (" .. tostring(report.reason) .. ")"
    or "ledger: open" }
  if report.migrated == true then
    parts[#parts + 1] = "migrated"
  end
  local keys = {}
  for key, value in pairs(report) do
    if type(key) == "string" and type(value) == "number" and value ~= 0 then
      keys[#keys + 1] = key
    end
  end
  table.sort(keys)
  for _, key in ipairs(keys) do
    parts[#parts + 1] = key .. " " .. report[key]
  end
  return table.concat(parts, ", ")
end

-- Sync's name form: "names two-part", "names realm" or "names undecided".
local function namesReport()
  local ok, form = pcall(function() return ns.Sync:NameForm() end)
  if not ok or (form ~= "two-part" and form ~= "realm") then
    form = "undecided"
  end
  return "names " .. form
end

-- The totals of Sync's counters that exist; a table of counters is summed.
local function syncReport()
  local stats = ns.Sync and ns.Sync.stats
  if type(stats) ~= "table" then
    return "sync: no stats"
  end
  local parts = {}
  for _, name in ipairs(STAT_NAMES) do
    local value = stats[name]
    if type(value) == "table" then
      local sum = 0
      for _, n in pairs(value) do
        if type(n) == "number" then
          sum = sum + n
        end
      end
      value = sum
    end
    if type(value) == "number" then
      parts[#parts + 1] = name .. " " .. value
    end
  end
  return "sync: " .. table.concat(parts, ", ")
end

function Core:ToggleDebug()
  self.debugOn = not self.debugOn
  if self.debugOn then
    self.debugPrinted, self.debugSkipped = {}, 0
    self:Print("Debug log on.")
    self:Print(ledgerReport() .. "; " .. syncReport() .. "; " .. namesReport())
  else
    self:Print("Debug log off.")
  end
end

-- Prints a debug line while the log is on: at most 5 per 10 s, the rest counted and
-- reported on the next line printed. Callers pass only our own words, reason codes,
-- numbers and validated GUIDs, never peer text (spec 3.8).
function Core:Debug(line)
  if not self.debugOn or type(line) ~= "string" then
    return
  end
  local now = call(GetServerTime)
  if hidden(now) or type(now) ~= "number" or now ~= now then
    now = 0
  end
  local printed = self.debugPrinted
  local age = #printed > 0 and now - printed[1] or DEBUG_WINDOW
  if #printed >= DEBUG_LINES and age >= 0 and age < DEBUG_WINDOW then
    self.debugSkipped = self.debugSkipped + 1
    return
  end
  if #printed >= DEBUG_LINES then
    table.remove(printed, 1)
  end
  printed[#printed + 1] = now
  if self.debugSkipped > 0 then
    line = "(" .. self.debugSkipped .. " skipped) " .. line
    self.debugSkipped = 0
  end
  self:Print(line)
end

-- The body of ExportString (docs/specs/export.md 3.7). May raise; the caller catches it.
local function exportString(includeTravelers)
  local ledger = ns.ledger
  if not ledger then
    return nil, "no_ledger"
  end
  local serializer = LibStub("AceSerializer-3.0", true)
  local deflate = LibStub("LibDeflate", true)
  if not serializer or not deflate then
    return nil, "libs"
  end
  local codec = {
    serialize = function(v) return serializer:Serialize(v) end,
    compress = function(s) return (deflate:CompressDeflate(s)) end,
  }

  local faction = call(UnitFactionGroup, "player")
  if hidden(faction) or type(faction) ~= "string" then
    faction = nil
  end
  local now = call(GetServerTime)
  if hidden(now) then
    now = nil
  end

  local own = ledger:own()
  local progress = ns.Collection.progress(own, faction)
  local unlocked = ns.Cosmetics.unlocked(own, faction, ledger:earned())

  -- Other travelers' names and GUIDs leave the game only when the player opts in, and
  -- only exactly `true` opts in.
  local travelers
  if rawequal(includeTravelers, true) then
    travelers = {}
    for _, t in ipairs(ledger:travelers()) do
      travelers[#travelers + 1] = {
        guid = t.guid, name = t.name, met = t.met, entries = ledger:signerEntries(t.guid),
      }
    end
  end

  return ns.Export.string({
    flavor = "forever", -- v1's TOC targets only Forever
    exported = now,
    addon = version(),
    me = { guid = ledger:ownerGUID(), name = ownerName() },
    own = own,
    progress = progress,
    unlocked = unlocked,
    travelers = travelers,
  }, codec)
end

-- The export string for the Share window and /ledger share, or nil, reason. Only
-- `includeTravelers == true` adds other travelers' signatures. Prints, sends and writes
-- nothing; an error inside gives nil, "error".
function Core.ExportString(_, includeTravelers) -- called as Core:ExportString(opted)
  local ok, result, reason = pcall(exportString, includeTravelers)
  if not ok then
    return nil, "error"
  end
  return result, reason
end

function Core:SlashCommand(input)
  local command = type(input) == "string" and input:match("^%s*(%S*)"):lower() or ""
  if command == "debug" then
    self:ToggleDebug()
  else
    self:Print("version " .. version())
  end
end
