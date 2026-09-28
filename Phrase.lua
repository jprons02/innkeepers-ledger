-- Phrase (pure): builds, renders and validates phrase IDs.
-- No WoW API here. Client values come in as arguments (docs/architecture.md -> Modules).
-- Spec: docs/specs/phrase.md. validIds is SyncProtocol's rule 16 hook, so it runs on
-- every received entry: its argument is hostile. It reads with raw next/rawget only,
-- does bounded work, never writes to its argument and returns exactly true or false.
-- Nothing here throws on any argument; only the load itself can raise (the assert).
local _, ns = ...

local Ledger = ns.Ledger
assert(type(Ledger) == "table", "Phrase needs ns.Ledger; Ledger.lua comes first in the TOC")

local Phrase = {}
ns.Phrase = Phrase

local find, sub, byte = string.find, string.sub, string.byte
local tsort = table.sort

-- Constants (spec 3.5). The locals below are what the code uses; the exported tables
-- are copies for callers and tests, so changing them changes nothing here.
local SLOT = "{w}"
local IDS_MAX = Ledger.LIMITS.phraseIdsMax -- read from Ledger, not a second literal
local ID_MAX = Ledger.LIMITS.phraseIdMax
local TEMPLATE_BYTES = 48
local CONJ_BYTES = 16
local WORD_BYTES = 24
local CATEGORY_BYTES = 40
local RENDER_BYTES = 160
local RANGES = {
  template = { 1, 499 },
  conj = { 500, 599 },
  word = { 1000, 9999 },
}
local BLOCK = 100
-- Category k allocates word IDs 900 + 100k .. 999 + 100k, so there is room for 90.
local CATEGORIES_MAX = (RANGES.word[2] - RANGES.word[1] + 1) / BLOCK
local SHAPES = { t = true, TW = true, tCt = true, tCTW = true, TWCt = true, TWCTW = true }
-- The fields each kind's record has, exactly (spec 3.2 rule 2).
local FIELDS = {
  template = { kind = true, text = true },
  conj = { kind = true, text = true },
  word = { kind = true, cat = true, text = true },
}

Phrase.SLOT = SLOT
Phrase.LIMITS = {
  idsMax = IDS_MAX, idMax = ID_MAX, templateBytes = TEMPLATE_BYTES, conjBytes = CONJ_BYTES,
  wordBytes = WORD_BYTES, categoryBytes = CATEGORY_BYTES, renderBytes = RENDER_BYTES,
}
Phrase.RANGES = {
  template = { RANGES.template[1], RANGES.template[2] },
  conj = { RANGES.conj[1], RANGES.conj[2] },
  word = { RANGES.word[1], RANGES.word[2] },
  block = BLOCK,
}
Phrase.SHAPES = { t = true, TW = true, tCt = true, tCTW = true, TWCt = true, TWCTW = true }

-- An integer in lo..hi. NaN fails x == x; inf % 1 is NaN, so inf fails too.
local function isInt(x, lo, hi)
  return type(x) == "number" and x == x and x % 1 == 0 and x >= lo and x <= hi
end

-- ---------------------------------------------------------------------------
-- Record rules (spec 3.2). Explicit byte values only: %a and friends follow the C locale.

local B_SPACE = 32
local ALLOWED = {} -- byte -> true: A-Z a-z 0-9, space and ' , . ! ? -
for b = 65, 90 do
  ALLOWED[b] = true
end
for b = 97, 122 do
  ALLOWED[b] = true
end
for b = 48, 57 do
  ALLOWED[b] = true
end
for _, b in ipairs({ 32, 39, 44, 46, 33, 63, 45 }) do
  ALLOWED[b] = true
end
local ENDS = { [46] = true, [33] = true, [63] = true } -- . ! ?

local function isUpper(b)
  return b ~= nil and b >= 65 and b <= 90
end

local function isLower(b)
  return b ~= nil and b >= 97 and b <= 122
end

-- Every byte of s[first..last] is in the allow-list.
local function allowed(s, first, last)
  for i = first, last do
    if not ALLOWED[byte(s, i)] then
      return false
    end
  end
  return true
end

-- Rules 3-4 for `s`. With `slotOk`, one {w} may appear; returns true plus its position
-- (or false when there is none). Anything else returns nil.
local function cleanText(s, slotOk)
  if type(s) ~= "string" or #s == 0 then
    return nil
  end
  if byte(s, 1) == B_SPACE or byte(s, -1) == B_SPACE or find(s, "  ", 1, true) then
    return nil
  end
  local a = slotOk and find(s, SLOT, 1, true) or nil
  if a then
    -- Any second {w} fails here: `{` isn't in the allow-list.
    if not allowed(s, 1, a - 1) or not allowed(s, a + #SLOT, #s) then
      return nil
    end
    return true, a
  end
  if not allowed(s, 1, #s) then
    return nil
  end
  return true, false
end

local function validCategoryName(s)
  return cleanText(s, false) ~= nil and #s <= CATEGORY_BYTES and isUpper(byte(s, 1))
end

-- The private record for (id, v), or nil if any rule fails. `ncat` = bound categories.
local function checkRecord(id, v, ncat)
  if not isInt(id, 1, ID_MAX) or type(v) ~= "table" then
    return nil
  end
  local kind = rawget(v, "kind")
  local fields = type(kind) == "string" and FIELDS[kind] or nil
  if fields == nil then
    return nil
  end
  local range = RANGES[kind]
  if id < range[1] or id > range[2] then
    return nil
  end
  for k in next, v do
    if not fields[k] then
      return nil
    end
  end
  local text, cat = rawget(v, "text"), rawget(v, "cat")
  local ok, slot = cleanText(text, kind == "template")
  if not ok then
    return nil
  end
  local n, first, last = #text, byte(text, 1), byte(text, -1)
  if kind == "template" then
    if n < 4 or n > TEMPLATE_BYTES or not isUpper(first) or not ENDS[last] then
      return nil
    end
    return { kind = kind, text = text, slot = slot }
  elseif kind == "conj" then
    if n < 4 or n > CONJ_BYTES or not isUpper(first) or sub(text, -3) ~= "..." then
      return nil
    end
    return { kind = kind, text = text }
  end
  if n > WORD_BYTES or not isLower(first) or not isLower(last) or not isInt(cat, 1, ncat) then
    return nil
  end
  return { kind = kind, text = text, cat = cat }
end

-- A short name for an excluded key, for tests and the debug report. Only numbers are
-- printed; any other key is named by its type, so no data string is echoed.
local function label(prefix, k)
  if type(k) == "number" then
    return prefix .. " " .. tostring(k)
  end
  return prefix .. " (" .. type(k) .. ")"
end

local function copyArray(arr)
  local out = {}
  for i = 1, #arr do
    out[i] = arr[i]
  end
  return out
end

-- ---------------------------------------------------------------------------
-- bind (spec 3.5): validate and index once, return closures over the private copy.

function Phrase.bind(data, categories)
  if type(data) ~= "table" then
    data = {}
  end
  if type(categories) ~= "table" then
    categories = {}
  end
  local invalid = {}

  -- Categories: 1..n up to the first missing or invalid name (rule 6).
  local cats = {}
  for i = 1, CATEGORIES_MAX do
    local name = rawget(categories, i)
    if not validCategoryName(name) then
      break
    end
    cats[i] = name
  end
  local ncat = #cats
  for k in next, categories do
    if not isInt(k, 1, ncat) then
      invalid[#invalid + 1] = label("category", k)
    end
  end

  -- Records.
  local records = {} -- id -> private record; a plain table nobody else sees
  local templates, conjs, words = {}, {}, {}
  for i = 1, ncat do
    words[i] = {}
  end
  for id, v in next, data do
    local rec = checkRecord(id, v, ncat)
    if rec == nil then
      invalid[#invalid + 1] = label("id", id)
    else
      records[id] = rec
      if rec.kind == "template" then
        templates[#templates + 1] = id
      elseif rec.kind == "conj" then
        conjs[#conjs + 1] = id
      else
        local list = words[rec.cat]
        list[#list + 1] = id
      end
    end
  end
  tsort(templates)
  tsort(conjs)
  for i = 1, ncat do
    tsort(words[i])
  end

  -- The kind letter of one ID: T slotted template, t slotless, C conjunction, W word.
  local function letter(id)
    if not isInt(id, 1, ID_MAX) then
      return nil
    end
    local rec = records[id]
    if rec == nil then
      return nil
    elseif rec.kind == "template" then
      return rec.slot and "T" or "t"
    elseif rec.kind == "conj" then
      return "C"
    end
    return "W"
  end

  local set = { invalid = invalid }

  -- Spec 3.5 validIds, exactly. Raw next/rawget only; at most IDS_MAX + 1 keys counted.
  function set.validIds(ids)
    if type(ids) ~= "table" then
      return false
    end
    local n = 0
    local k = next(ids)
    while k ~= nil do
      n = n + 1
      if n > IDS_MAX then
        return false
      end
      k = next(ids, k)
    end
    if n == 0 then
      return false
    end
    -- n keys that include every 1..n: no holes and no extra keys.
    local shape = ""
    for i = 1, n do
      local l = letter(rawget(ids, i))
      if l == nil then
        return false
      end
      shape = shape .. l
    end
    return SHAPES[shape] == true
  end
  local validIds = set.validIds

  -- One clause from position i: its text and the next position.
  local function clause(ids, i)
    local rec = records[rawget(ids, i)]
    if not rec.slot then
      return rec.text, i + 1
    end
    local word = records[rawget(ids, i + 1)].text
    -- Plain find + sub; never gsub with data as the replacement (spec 3.4).
    return sub(rec.text, 1, rec.slot - 1) .. word .. sub(rec.text, rec.slot + #SLOT), i + 2
  end

  function set.render(ids)
    if validIds(ids) ~= true then
      return nil
    end
    local first, i = clause(ids, 1)
    local conj = rawget(ids, i)
    if conj == nil then
      return first
    end
    local second = clause(ids, i + 1)
    return first .. " " .. records[conj].text .. " " .. second
  end

  -- The builder's one call. Only five parts exist; any more non-nil argument fails.
  function set.compose(t1, w1, c, t2, w2, ...)
    for i = 1, select("#", ...) do
      if select(i, ...) ~= nil then
        return nil
      end
    end
    local parts, out, n = { t1, w1, c, t2, w2 }, {}, 0
    for i = 1, 5 do
      local v = rawget(parts, i)
      if v ~= nil then
        n = n + 1
        out[n] = v
      end
    end
    if validIds(out) ~= true then
      return nil
    end
    return out
  end

  function set.kind(id)
    local rec = isInt(id, 1, ID_MAX) and records[id] or nil
    return rec and rec.kind or nil
  end

  function set.text(id)
    local rec = isInt(id, 1, ID_MAX) and records[id] or nil
    return rec and rec.text or nil
  end

  function set.hasSlot(id)
    return letter(id) == "T"
  end

  function set.templates()
    return copyArray(templates)
  end

  function set.conjunctions()
    return copyArray(conjs)
  end

  function set.categories()
    return copyArray(cats)
  end

  function set.words(cat)
    if not isInt(cat, 1, ncat) then
      return {}
    end
    return copyArray(words[cat])
  end

  return set
end

-- ---------------------------------------------------------------------------
-- The default set, over the shipped data (spec 3.7). Missing data binds an empty set,
-- which rejects everything (fail closed); a bad record is excluded, never raised.

local data, categories
if type(ns.Data) == "table" then
  data, categories = ns.Data.Phrases, ns.Data.PhraseCategories
end
local default = Phrase.bind(data, categories)
for _, name in ipairs({
  "validIds", "render", "compose", "kind", "text", "hasSlot", "templates", "conjunctions",
  "categories", "words",
}) do
  Phrase[name] = default[name]
end
Phrase.invalid = default.invalid
