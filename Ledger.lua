-- Ledger (pure): the entry store: add, dedupe, query, prune, storage caps.
-- No WoW API here. Client values come in as arguments (docs/architecture.md -> Modules).
-- Spec: docs/specs/sync-ledger.md (sections 3.1 and 4).
local _, ns = ...

local Ledger = {}
ns.Ledger = Ledger

local floor = math.floor
local tinsert, tremove, tsort = table.insert, table.remove, table.sort

-- Shared limits (spec 3.1). SyncProtocol reads these; don't repeat the literals there.
Ledger.LIMITS = {
  innMax = 9999999,
  phraseIdMax = 9999,
  phraseIdsMax = 5,
  sealMax = 999,
  tMin = 1789603200, -- 2026-09-17 00:00 UTC, the beta start
  tMax = 9999999999,
  futureTolerance = 300,
  nameMaxBytes = 96,
  cosmeticIdMax = 9999,
  weekLength = 604800,
}

-- Storage caps (spec 4.4). Own entries have no cap and are never evicted.
Ledger.CAPS = {
  perSigner = 40,
  perInn = 150,
  foreignTotal = 3000,
}

Ledger.SCHEMA = 1
-- MIGRATIONS[n](copy) takes a schema-n table to n + 1 and sets `schema` (spec 4.3).
Ledger.MIGRATIONS = {}

local LIMITS, CAPS = Ledger.LIMITS, Ledger.CAPS
local QUARANTINE_MAX = 100
local FIELDS = { "own", "travelers", "earned", "quarantine" }

-- ---------------------------------------------------------------------------
-- Validation. None of these throw, whatever they're given.

-- An integer in lo..hi. NaN fails x == x; inf % 1 is NaN, so inf fails too.
local function isInt(x, lo, hi)
  return type(x) == "number" and x == x and x % 1 == 0 and x >= lo and x <= hi
end

local ENTRY_KEYS = { inn = true, t = true, phrase = true, seal = true }

local function validPhrase(p)
  if type(p) ~= "table" then
    return false
  end
  local n = 0
  for k, v in next, p do
    if not isInt(k, 1, LIMITS.phraseIdsMax) or not isInt(v, 1, LIMITS.phraseIdMax) then
      return false
    end
    n = n + 1
  end
  if n < 1 then
    return false
  end
  -- n distinct keys in 1..phraseIdsMax: an array exactly when 1..n are all present.
  for i = 1, n do
    if rawget(p, i) == nil then
      return false
    end
  end
  return true
end

-- Structurally valid entry (spec 4.1). Reads with rawget/next, so metatables never run.
function Ledger.validEntry(e)
  if type(e) ~= "table" then
    return false
  end
  for k in next, e do
    if not ENTRY_KEYS[k] then
      return false
    end
  end
  local seal = rawget(e, "seal")
  return isInt(rawget(e, "inn"), 1, LIMITS.innMax)
    and isInt(rawget(e, "t"), LIMITS.tMin, LIMITS.tMax)
    and validPhrase(rawget(e, "phrase"))
    and (seal == nil or isInt(seal, 1, LIMITS.sealMax))
end

function Ledger.validGUID(s)
  return type(s) == "string" and #s <= 40 and s:match("^Player%-%d+%-%x+$") ~= nil
end

-- The name rule (spec 5.2). Explicit byte ranges only: %a and friends follow the C locale.
local WORD = "[A-Za-z\128-\255]"
local ONE_WORD = "^(" .. WORD .. "+)$"
local TWO_WORDS = "^(" .. WORD .. "+) (" .. WORD .. "+)$"
local REALM = "^[A-Za-z0-9'%-\128-\255]+$"

function Ledger.validName(s)
  if type(s) ~= "string" or #s < 2 or #s > LIMITS.nameMaxBytes then
    return false
  end
  -- Redundant with the patterns below, kept as the explicit UI-escape guard.
  if s:find("[%z\1-\31\127|]") then
    return false
  end
  local name, realm = s:match("^([^%-]*)%-(.*)$")
  if not name then
    name = s
  end
  if realm and (#realm < 1 or #realm > 48 or not realm:match(REALM) or realm:sub(-1) == "-") then
    return false
  end
  local first, second = name:match(TWO_WORDS)
  if first then
    return #first >= 2 and #first <= 48 and #second <= 48
  end
  first = name:match(ONE_WORD)
  return first ~= nil and #first >= 2 and #first <= 48
end

-- The NPC ID of an innkeeper's creature GUID if it's a key of `inns`, else nil (spec 5.2).
-- Runs in pcall, so a hidden value that errors when touched gives nil too.
function Ledger.innFromNpcGUID(guid, inns)
  local ok, id = pcall(function()
    if type(guid) ~= "string" or type(inns) ~= "table" then
      return nil
    end
    local digits = guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-%x+$")
    if not digits or #digits > 7 or digits:sub(1, 1) == "0" then
      return nil
    end
    local n = tonumber(digits)
    if inns[n] == nil then
      return nil
    end
    return n
  end)
  if ok then
    return id
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- Helpers.

-- Only for entries that passed validEntry; rawget keeps metatables out.
local function copyEntry(e)
  local phrase = {}
  for i, id in ipairs(rawget(e, "phrase")) do
    phrase[i] = id
  end
  return { inn = rawget(e, "inn"), t = rawget(e, "t"), phrase = phrase, seal = rawget(e, "seal") }
end

-- Copies keys and values; shared or cyclic tables stay shared or cyclic in the copy.
local function deepCopy(v, seen)
  if type(v) ~= "table" then
    return v
  end
  if seen[v] then
    return seen[v]
  end
  local out = {}
  seen[v] = out
  for k, x in next, v do
    out[deepCopy(k, seen)] = deepCopy(x, seen)
  end
  return out
end

-- Values of a table: positive-integer keys ascending, then the rest in `next` order.
local function values(t)
  local ints, other = {}, {}
  for k, v in next, t do
    if isInt(k, 1, math.huge) then
      ints[#ints + 1] = k
    else
      other[#other + 1] = v
    end
  end
  tsort(ints)
  local out = {}
  for i, k in ipairs(ints) do
    out[i] = t[k]
  end
  for _, v in ipairs(other) do
    out[#out + 1] = v
  end
  return out
end

-- Orders. Entries of one signer: (t, inn). Foreign refs { signer, e }: (t, signer, inn)
-- across the store, (t, signer) within an inn. Each is a total order on stored entries.
local function entryLess(a, b)
  if a.t ~= b.t then
    return a.t < b.t
  end
  return a.inn < b.inn
end

-- Byte order. String `<` follows the C locale's collation, which may differ between
-- clients or even rank two distinct strings equal; the store's order must not.
local function strLess(a, b)
  for i = 1, math.min(#a, #b) do
    local x, y = a:byte(i), b:byte(i)
    if x ~= y then
      return x < y
    end
  end
  return #a < #b
end

local function refLess(a, b)
  if a.e.t ~= b.e.t then
    return a.e.t < b.e.t
  end
  if a.signer ~= b.signer then
    return strLess(a.signer, b.signer)
  end
  return a.e.inn < b.e.inn
end

local function insertSorted(arr, x, less)
  local lo, hi = 1, #arr
  while lo <= hi do
    local mid = floor((lo + hi) / 2)
    if less(x, arr[mid]) then
      hi = mid - 1
    else
      lo = mid + 1
    end
  end
  tinsert(arr, lo, x)
end

local function removeSorted(arr, x, less)
  local lo, hi = 1, #arr
  while lo <= hi do
    local mid = floor((lo + hi) / 2)
    local m = arr[mid]
    if less(x, m) then
      hi = mid - 1
    elseif less(m, x) then
      lo = mid + 1
    else
      tremove(arr, mid)
      return
    end
  end
end

local function entryKey(signer, inn, t)
  return signer .. "\0" .. inn .. "\0" .. t
end

local function weekKey(signer, inn, week)
  return signer .. "\0" .. inn .. "\0w" .. week
end

local function weekOf(anchor, t)
  return floor((t - anchor) / LIMITS.weekLength)
end

-- ---------------------------------------------------------------------------
-- Load: shape checks, migration, normalize (spec 4.3).

local function newReport()
  return {
    migrated = false,
    foreignDropped = 0,  -- foreign entries that failed validEntry
    travelersDropped = 0,
    metReset = 0,
    earnedDropped = 0,
    quarantined = 0,     -- invalid own entries moved to quarantine
    quarantineDropped = 0,
    nameReset = 0,
    duplicates = 0,
    weekly = 0,          -- foreign entries dropped by the weekly rule
    evicted = 0,         -- foreign entries removed by the caps
  }
end

local function shapeOk(t)
  if type(t.me) ~= "table" then
    return false
  end
  for _, f in ipairs(FIELDS) do
    if type(t[f]) ~= "table" then
      return false
    end
  end
  return true
end

local function migrate(data)
  local copy = deepCopy(data, {})
  local ok = pcall(function()
    for n = data.schema, Ledger.SCHEMA - 1 do
      Ledger.MIGRATIONS[n](copy)
    end
  end)
  if not ok or copy.schema ~= Ledger.SCHEMA or not shapeOk(copy) then
    return false
  end
  -- Write back in place so AceDB keeps the same table.
  for k in pairs(data) do
    data[k] = nil
  end
  for k, v in pairs(copy) do
    data[k] = v
  end
  return true
end

-- Rewrites own, travelers, earned, quarantine and me.name in `store`. Caps come later,
-- once the indexes exist.
local function normalize(store, owner, anchor, report)
  local ownerGUID = owner.guid
  for _, f in ipairs(FIELDS) do
    if type(store[f]) ~= "table" then
      store[f] = {}
    end
  end
  if type(store.me) ~= "table" then
    store.me = {}
  end

  -- Quarantine keeps its table items, then takes invalid own entries, up to the cap.
  local quarantine = {}
  local function toQuarantine(item, moved)
    if type(item) == "table" and #quarantine < QUARANTINE_MAX then
      quarantine[#quarantine + 1] = item
      if moved then
        report.quarantined = report.quarantined + 1
      end
    else
      report.quarantineDropped = report.quarantineDropped + 1
    end
  end
  for _, item in ipairs(values(store.quarantine)) do
    toQuarantine(item, false)
  end

  local own, seen = {}, {}
  for _, e in ipairs(values(store.own)) do
    if not Ledger.validEntry(e) then
      toQuarantine(e, true)
    else
      local key = e.inn .. "\0" .. e.t
      if seen[key] then
        report.duplicates = report.duplicates + 1
      else
        seen[key] = true
        own[#own + 1] = copyEntry(e)
      end
    end
  end
  tsort(own, entryLess)
  store.own = own
  store.quarantine = quarantine

  local travelers = {}
  for guid, rec in next, store.travelers do
    local entries = {}
    if Ledger.validGUID(guid) and guid ~= ownerGUID and type(rec) == "table"
      and Ledger.validName(rec.name) and type(rec.entries) == "table" then
      seen = {}
      for _, e in ipairs(values(rec.entries)) do
        if not Ledger.validEntry(e) then
          report.foreignDropped = report.foreignDropped + 1
        else
          local key = e.inn .. "\0" .. e.t
          if seen[key] then
            report.duplicates = report.duplicates + 1
          else
            seen[key] = true
            entries[#entries + 1] = copyEntry(e)
          end
        end
      end
      tsort(entries, entryLess)
      -- The weekly rule: the earliest entry of each (inn, week) stays.
      local kept, weeks = {}, {}
      for _, e in ipairs(entries) do
        local key = e.inn .. "\0" .. weekOf(anchor, e.t)
        if weeks[key] then
          report.weekly = report.weekly + 1
        else
          weeks[key] = true
          kept[#kept + 1] = e
        end
      end
      entries = kept
    end
    if #entries == 0 then
      report.travelersDropped = report.travelersDropped + 1
    else
      local met = rec.met
      if not isInt(met, LIMITS.tMin, LIMITS.tMax) then
        met = entries[1].t
        report.metReset = report.metReset + 1
      end
      travelers[guid] = { name = rec.name, met = met, entries = entries }
    end
  end
  store.travelers = travelers

  local earned = {}
  for id, t in next, store.earned do
    if isInt(id, 1, LIMITS.cosmeticIdMax) and isInt(t, LIMITS.tMin, LIMITS.tMax) then
      earned[id] = t
    else
      report.earnedDropped = report.earnedDropped + 1
    end
  end
  store.earned = earned

  if store.me.name ~= nil and not Ledger.validName(store.me.name) then
    report.nameReset = report.nameReset + 1
    store.me.name = Ledger.validName(owner.name) and owner.name or nil
  end
end

-- ---------------------------------------------------------------------------
-- The ledger object.

local LedgerObject = {}
LedgerObject.__index = LedgerObject

local function emptyStore(ownerName)
  return {
    schema = Ledger.SCHEMA,
    me = Ledger.validName(ownerName) and { name = ownerName } or {},
    own = {},
    travelers = {},
    earned = {},
    quarantine = {},
  }
end

-- Removes one stored foreign entry from the store and every index.
function LedgerObject:_removeForeign(signer, e)
  local rec = self.data.travelers[signer]
  removeSorted(rec.entries, e, entryLess)
  local ref = { signer = signer, e = e }
  removeSorted(self._all, ref, refLess)
  removeSorted(self._inns[e.inn], ref, refLess)
  if #self._inns[e.inn] == 0 then
    self._inns[e.inn] = nil
  end
  self._keys[entryKey(signer, e.inn, e.t)] = nil
  self._weeks[weekKey(signer, e.inn, self:weekOf(e.t))] = nil
  if #rec.entries == 0 then
    self.data.travelers[signer] = nil
    self._travelerCount = self._travelerCount - 1
  end
end

-- Builds the in-memory indexes from the normalized store.
function LedgerObject:_index()
  local guid = self._guid
  self._keys, self._weeks, self._all, self._inns = {}, {}, {}, {}
  self._travelerCount = 0
  for _, e in ipairs(self.data.own) do
    self._keys[entryKey(guid, e.inn, e.t)] = true
    self._weeks[weekKey(guid, e.inn, self:weekOf(e.t))] = true
  end
  for signer, rec in pairs(self.data.travelers) do
    self._travelerCount = self._travelerCount + 1
    for _, e in ipairs(rec.entries) do
      local ref = { signer = signer, e = e }
      self._all[#self._all + 1] = ref
      local list = self._inns[e.inn]
      if not list then
        list = {}
        self._inns[e.inn] = list
      end
      list[#list + 1] = ref
      self._keys[entryKey(signer, e.inn, e.t)] = true
      self._weeks[weekKey(signer, e.inn, self:weekOf(e.t))] = true
    end
  end
  tsort(self._all, refLess)
  for _, list in pairs(self._inns) do
    tsort(list, refLess)
  end
end

-- Re-applies the caps when a ledger opens, oldest first: perSigner, perInn, foreignTotal.
function LedgerObject:_applyCaps(report)
  local signers = {}
  for signer in pairs(self.data.travelers) do
    signers[#signers + 1] = signer
  end
  for _, signer in ipairs(signers) do
    local rec = self.data.travelers[signer]
    while #rec.entries > CAPS.perSigner do
      self:_removeForeign(signer, rec.entries[1])
      report.evicted = report.evicted + 1
    end
  end
  local inns = {}
  for inn in pairs(self._inns) do
    inns[#inns + 1] = inn
  end
  for _, inn in ipairs(inns) do
    while self._inns[inn] and #self._inns[inn] > CAPS.perInn do
      local ref = self._inns[inn][1]
      self:_removeForeign(ref.signer, ref.e)
      report.evicted = report.evicted + 1
    end
  end
  while #self._all > CAPS.foreignTotal do
    local ref = self._all[1]
    self:_removeForeign(ref.signer, ref.e)
    report.evicted = report.evicted + 1
  end
end

-- Ledger.new(data, owner, weekAnchor): see spec 4.3. `owner` = { guid, name };
-- `weekAnchor` = the server time of any weekly reset. Errors only on caller bugs.
function Ledger.new(data, owner, weekAnchor)
  if type(owner) ~= "table" or not Ledger.validGUID(owner.guid) then
    error("Ledger.new: owner.guid is not a player GUID", 2)
  end
  if not isInt(weekAnchor, 0, LIMITS.tMax) then
    error("Ledger.new: weekAnchor is not an integer time", 2)
  end
  local self = setmetatable({
    _guid = owner.guid,
    _anchor = weekAnchor,
    readOnly = false,
    loadReport = newReport(),
  }, LedgerObject)
  local report = self.loadReport

  if type(data) ~= "table" then
    report.reason = "not_table"
  elseif next(data) == nil then
    for k, v in pairs(emptyStore(owner.name)) do
      data[k] = v
    end
  elseif data.schema == Ledger.SCHEMA then
    if not shapeOk(data) then
      report.reason = "bad_field"
    end
  elseif isInt(data.schema, 1, Ledger.SCHEMA - 1) then
    if migrate(data) then
      report.migrated = true
    else
      report.reason = "migration_failed"
    end
  elseif isInt(data.schema, Ledger.SCHEMA + 1, math.huge) then
    report.reason = "newer_schema"
  else
    report.reason = "bad_schema"
  end

  local store = data
  if report.reason then
    -- Read-only: never write to `data`; answer queries from a normalized copy.
    self.readOnly = true
    store = type(data) == "table" and deepCopy(data, {}) or emptyStore(nil)
  end
  self.data = store
  normalize(store, owner, weekAnchor, report)
  self:_index()
  self:_applyCaps(report)
  return self
end

-- ---------------------------------------------------------------------------
-- Weeks (spec 4.4).

function LedgerObject:weekOf(t)
  return weekOf(self._anchor, t)
end

function LedgerObject:nextWeekStart(now)
  return self._anchor + (self:weekOf(now) + 1) * LIMITS.weekLength
end

-- False for a read-only ledger, invalid arguments, or an own entry at `inn` this week.
function LedgerObject:canSign(inn, now)
  if self.readOnly or not isInt(inn, 1, LIMITS.innMax) or not isInt(now, 0, LIMITS.tMax) then
    return false
  end
  return not self._weeks[weekKey(self._guid, inn, self:weekOf(now))]
end

-- ---------------------------------------------------------------------------
-- Writes.

function LedgerObject:addOwn(e)
  if self.readOnly then
    return "readonly"
  end
  if not Ledger.validEntry(e) then
    return "invalid"
  end
  local guid = self._guid
  local key = entryKey(guid, e.inn, e.t)
  if self._keys[key] then
    return "dup"
  end
  local wkey = weekKey(guid, e.inn, self:weekOf(e.t))
  if self._weeks[wkey] then
    return "too_soon"
  end
  insertSorted(self.data.own, copyEntry(e), entryLess)
  self._keys[key] = true
  self._weeks[wkey] = true
  return "added"
end

-- Stores a foreign entry under `signer` (spec 4.4). Known-ID and time-window checks
-- belong to SyncProtocol; these checks are the second line of defense.
function LedgerObject:addForeign(signer, name, e, now)
  if self.readOnly then
    return "readonly"
  end
  if not Ledger.validGUID(signer) or not Ledger.validName(name) or not Ledger.validEntry(e)
    or not isInt(now, LIMITS.tMin, LIMITS.tMax) then
    return "invalid"
  end
  if signer == self._guid then
    return "self"
  end
  local key = entryKey(signer, e.inn, e.t)
  if self._keys[key] then
    return "dup"
  end
  local wkey = weekKey(signer, e.inn, self:weekOf(e.t))
  if self._weeks[wkey] then
    return "too_soon"
  end

  -- 1. Insert.
  local travelers = self.data.travelers
  local rec = travelers[signer]
  if not rec then
    rec = { name = name, met = now, entries = {} }
    travelers[signer] = rec
    self._travelerCount = self._travelerCount + 1
  end
  local entry = copyEntry(e)
  insertSorted(rec.entries, entry, entryLess)
  local ref = { signer = signer, e = entry }
  insertSorted(self._all, ref, refLess)
  local list = self._inns[entry.inn]
  if not list then
    list = {}
    self._inns[entry.inn] = list
  end
  insertSorted(list, ref, refLess)
  self._keys[key] = true
  self._weeks[wkey] = true

  -- 2-4. At most one eviction per cap; 5 happens inside _removeForeign.
  local dropped = false
  local function evict(victim)
    if victim.e == entry then
      dropped = true
    end
    self:_removeForeign(victim.signer, victim.e)
  end
  if #rec.entries > CAPS.perSigner then
    evict({ signer = signer, e = rec.entries[1] })
  end
  if not dropped and #list > CAPS.perInn then
    evict(list[1])
  end
  if not dropped and #self._all > CAPS.foreignTotal then
    evict(self._all[1])
  end
  if dropped then
    return "dropped"
  end
  rec.name = name -- only an accepted entry renames the traveler
  return "added"
end

function LedgerObject:setOwnerName(name)
  if self.readOnly or not Ledger.validName(name) then
    return false
  end
  self.data.me.name = name
  return true
end

-- Records when a cosmetic was first earned; an earlier time already stored is kept.
function LedgerObject:markEarned(id, t)
  if self.readOnly or not isInt(id, 1, LIMITS.cosmeticIdMax)
    or not isInt(t, LIMITS.tMin, LIMITS.tMax) then
    return false
  end
  local earned = self.data.earned
  if earned[id] == nil or t < earned[id] then
    earned[id] = t
  end
  return true
end

-- ---------------------------------------------------------------------------
-- Queries. Arrays are new tables; the entry tables in them are shared, read-only.

local function copyArray(arr, first, last)
  local out = {}
  for i = first or 1, last or #arr do
    out[#out + 1] = arr[i]
  end
  return out
end

function LedgerObject:ownerGUID()
  return self._guid
end

function LedgerObject:has(signer, inn, t)
  if type(signer) ~= "string" or not isInt(inn, 1, LIMITS.innMax)
    or not isInt(t, LIMITS.tMin, LIMITS.tMax) then
    return false
  end
  return self._keys[entryKey(signer, inn, t)] == true
end

function LedgerObject:own()
  return copyArray(self.data.own)
end

function LedgerObject:shareWindow(n)
  local own = self.data.own
  if type(n) ~= "number" or n ~= n or n < 1 then
    return {}
  end
  n = math.min(floor(n), #own)
  return copyArray(own, #own - n + 1, #own)
end

function LedgerObject:signerEntries(guid)
  local rec = type(guid) == "string" and self.data.travelers[guid]
  if not rec then
    return {}
  end
  return copyArray(rec.entries)
end

function LedgerObject:innEntries(inn)
  local own, foreign = {}, {}
  for _, e in ipairs(self.data.own) do
    if e.inn == inn then
      own[#own + 1] = e
    end
  end
  local list = type(inn) == "number" and inn == inn and self._inns[inn]
  for _, ref in ipairs(list or {}) do
    foreign[#foreign + 1] = {
      signer = ref.signer,
      name = self.data.travelers[ref.signer].name,
      entry = ref.e,
    }
  end
  return { own = own, foreign = foreign }
end

function LedgerObject:travelers()
  local out = {}
  for guid, rec in pairs(self.data.travelers) do
    out[#out + 1] = { guid = guid, name = rec.name, met = rec.met, count = #rec.entries }
  end
  tsort(out, function(a, b)
    if a.met ~= b.met then
      return a.met > b.met
    end
    return strLess(a.guid, b.guid)
  end)
  return out
end

function LedgerObject:counts()
  return { own = #self.data.own, foreign = #self._all, travelers = self._travelerCount }
end

function LedgerObject:earnedAt(id)
  if type(id) ~= "number" or id ~= id then
    return nil
  end
  return self.data.earned[id]
end

function LedgerObject:earned()
  local out = {}
  for id, t in pairs(self.data.earned) do
    out[id] = t
  end
  return out
end
