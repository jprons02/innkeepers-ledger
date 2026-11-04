-- Writes the AddOn's data tables (Data/Inns, Data/Cosmetics, Data/Phrases) as one JSON
-- file, docs/data/forever.json, for export consumers. Spec: docs/specs/data-json.md.
-- A dev tool: never packaged (scripts/ is in .pkgmeta's ignore), never read by the AddOn.
--
-- From the repo root:
--   lua scripts/data-json.lua           build the JSON and write the file
--   lua scripts/data-json.lua --check   compare it with the file; exit 1 if they differ
-- Exit codes: 0 done, 1 out of date or a build error, 2 usage.
--
-- Only what the AddOn keeps is written: the data is loaded with the modules that bind it
-- and read back through their accessors, and any record they reject fails the build
-- (spec 3.4). The bytes depend on nothing but the data (spec 3.3): no version, no date,
-- no `pairs` order. The specs load this file as a module: loadfile(path)("--lib").
local M = {}

local OUT = "docs/data/forever.json"
local TOC = "InnkeepersLedger.toc"
local LOADER = "spec/helpers/load.lua"
local SCHEMA = 1
local FLAVOR = "forever"
local INT_MAX = 2 ^ 53 - 1
-- The modules that bind the data, after the files of load.DATA (all in TOC order).
local MODULES = { "Ledger.lua", "Phrase.lua", "Collection.lua", "Cosmetics.lua" }

local byte, char, format = string.byte, string.char, string.format
local concat, sort = table.concat, table.sort

local function fail(msg)
  error(msg, 0)
end

-- ---------------------------------------------------------------------------
-- Encoding (spec 3.3).

local function isInt(x)
  return type(x) == "number" and x == x and x % 1 == 0 and x >= -INT_MAX and x <= INT_MAX
end

-- Byte order, whatever the C locale says (Lua's string < uses strcoll).
local function byteLess(a, b)
  local n = math.min(#a, #b)
  for i = 1, n do
    local x, y = byte(a, i), byte(b, i)
    if x ~= y then
      return x < y
    end
  end
  return #a < #b
end

local function number(n, path)
  if not isInt(n) then
    fail(path .. ": not an integer in -(2^53 - 1)..2^53 - 1")
  end
  if n == 0 then
    return "0" -- %.0f writes -0 as "-0"
  end
  return format("%.0f", n)
end

-- The byte after position i is a continuation byte in lo..hi (default 0x80..0xBF).
local function cont(s, i, lo, hi)
  local b = byte(s, i)
  return b ~= nil and b >= (lo or 0x80) and b <= (hi or 0xBF)
end

-- Well-formed UTF-8 (RFC 3629): no stray continuation, truncation, overlong form,
-- surrogate or code point above U+10FFFF.
local function validUtf8(s)
  local i, n = 1, #s
  while i <= n do
    local b = byte(s, i)
    local len
    if b < 0x80 then
      len = 1
    elseif b >= 0xC2 and b <= 0xDF then
      len = cont(s, i + 1) and 2
    elseif b == 0xE0 then
      len = cont(s, i + 1, 0xA0, 0xBF) and cont(s, i + 2) and 3
    elseif b == 0xED then
      len = cont(s, i + 1, 0x80, 0x9F) and cont(s, i + 2) and 3
    elseif b >= 0xE1 and b <= 0xEF then
      len = cont(s, i + 1) and cont(s, i + 2) and 3
    elseif b == 0xF0 then
      len = cont(s, i + 1, 0x90, 0xBF) and cont(s, i + 2) and cont(s, i + 3) and 4
    elseif b >= 0xF1 and b <= 0xF3 then
      len = cont(s, i + 1) and cont(s, i + 2) and cont(s, i + 3) and 4
    elseif b == 0xF4 then
      len = cont(s, i + 1, 0x80, 0x8F) and cont(s, i + 2) and cont(s, i + 3) and 4
    end
    if not len then
      return false
    end
    i = i + len
  end
  return true
end

-- `"` and `\` escaped, every byte 0x00-0x1F and 0x7F as \u00xx; nothing else.
local ESCAPE = { [char(34)] = "\\\"", [char(92)] = "\\\\", [char(127)] = "\\u007f" }
for b = 0, 31 do
  ESCAPE[char(b)] = format("\\u%04x", b)
end

local function str(s, path)
  if not validUtf8(s) then
    fail(path .. ": not well-formed UTF-8")
  end
  return "\"" .. s:gsub("[%z\1-\31\34\92\127]", ESCAPE) .. "\""
end

-- The keys of t, sorted: integers numerically, strings in byte order. Mixed or other
-- keys fail. Returns the sorted keys and their JSON (quoted) forms.
local function sortedKeys(t, path)
  local ints, strs = {}, {}
  for k in pairs(t) do
    if type(k) == "string" then
      strs[#strs + 1] = k
    elseif isInt(k) then
      ints[#ints + 1] = k
    else
      fail(path .. ": a " .. type(k) .. " key that isn't a string or an integer")
    end
  end
  if #ints > 0 and #strs > 0 then
    fail(path .. ": mixes integer and string keys")
  end
  local keys, names = {}, {}
  if #ints > 0 then
    sort(ints)
    for i, k in ipairs(ints) do
      keys[i], names[i] = k, "\"" .. number(k, path) .. "\""
    end
  else
    sort(strs, byteLess)
    for i, k in ipairs(strs) do
      keys[i], names[i] = k, str(k, path .. " (key)")
    end
  end
  return keys, names
end

local function join(path, key)
  if path == "" then
    return tostring(key)
  end
  return path .. "." .. tostring(key)
end

-- `depth` 0 is the root and 1 its sections, written one member per line; any deeper
-- object is written on one line.
local function value(v, depth, path)
  local t = type(v)
  if t == "string" then
    return str(v, path == "" and "(root)" or path)
  elseif t == "number" then
    return number(v, path == "" and "(root)" or path)
  elseif t == "boolean" then
    return v and "true" or "false"
  elseif t ~= "table" then
    fail((path == "" and "(root)" or path) .. ": a " .. t .. " value")
  end
  local keys, names = sortedKeys(v, path == "" and "(root)" or path)
  if #keys == 0 then
    return "{}"
  end
  local parts = {}
  for i, k in ipairs(keys) do
    parts[i] = names[i] .. ": " .. value(v[k], depth + 1, join(path, k))
  end
  if depth >= 2 then
    return "{" .. concat(parts, ", ") .. "}"
  end
  local inner = string.rep("  ", depth + 1)
  return "{\n" .. inner .. concat(parts, ",\n" .. inner) .. "\n" .. string.rep("  ", depth) .. "}"
end

function M.encode(v)
  return value(v, 0, "") .. "\n"
end

-- ---------------------------------------------------------------------------
-- Build (spec 3.2, 3.4): the bound records, checked so nothing can drop silently.

-- The keys of a raw data table, sorted; any non-integer key fails (it can't be bound).
local function rawKeys(t, what)
  local keys = {}
  if type(t) ~= "table" then
    return keys
  end
  for k in pairs(t) do
    if not isInt(k) then
      fail(what .. ": a " .. type(k) .. " key has no bound record")
    end
    keys[#keys + 1] = k
  end
  sort(keys)
  return keys
end

local function places(Data, C)
  local continents, zones, inns = {}, {}, {}
  for _, k in ipairs(rawKeys(Data.Continents, "continents")) do
    local rec = C.continent(k)
    if rec == nil then
      fail("continents: continent " .. number(k, "continents") .. " has no bound record")
    end
    continents[k] = { name = rec.name, complete = rec.complete }
  end
  for _, k in ipairs(C.zoneKeys()) do
    local rec = C.zone(k)
    zones[k] = { name = rec.name, continent = rec.continent, seal = rec.seal,
      complete = rec.complete }
  end
  for _, k in ipairs(rawKeys(Data.Zones, "zones")) do
    if zones[k] == nil then
      fail("zones: zone " .. number(k, "zones") .. " has no bound record")
    end
  end
  for _, k in ipairs(rawKeys(Data.Inns, "inns")) do
    local rec, target = C.inn(k), C.innOf(k)
    if rec ~= nil then
      inns[k] = { name = rec.name, zone = rec.zone, faction = rec.faction }
    elseif target ~= nil and target ~= k then
      inns[k] = { alias = target }
    else
      fail("inns: inn " .. number(k, "inns") .. " has no bound record")
    end
  end
  return continents, zones, inns
end

local function cosmetics(Data, Cos, zones)
  local out, zoneSeals = {}, 0
  for _, rec in ipairs(Cos.catalog()) do
    local r = rec.rule
    out[rec.id] = { kind = rec.kind, name = rec.name,
      rule = { kind = r.kind, n = r.n, zone = r.zone } }
    if r.kind == "zone" then
      zoneSeals = zoneSeals + 1
    end
  end
  -- Check 2: exactly one zone seal per zone, at its seal.
  local nZones = 0
  for _, k in ipairs(rawKeys(zones, "zones")) do
    local z = zones[k]
    nZones = nZones + 1
    local rec = out[z.seal]
    if rec == nil or rec.rule.kind ~= "zone" or rec.rule.zone ~= k then
      fail("cosmetics: zone " .. number(k, "zones") .. " has no zone seal "
        .. tostring(z.seal))
    end
  end
  if zoneSeals ~= nZones then
    fail("cosmetics: " .. zoneSeals .. " zone seals for " .. nZones .. " zones")
  end
  for _, k in ipairs(rawKeys(Data.Cosmetics, "cosmetics")) do
    if out[k] == nil then
      fail("cosmetics: cosmetic " .. number(k, "cosmetics") .. " has no bound record")
    end
  end
  return out
end

local function phrases(Data, P)
  local cats, voices, out = {}, {}, {}
  for i, name in ipairs(P.categories()) do
    cats[i] = name
  end
  for i, name in ipairs(P.voices()) do
    voices[i] = name
  end
  for _, list in ipairs({ P.templates(), P.conjunctions() }) do
    for _, id in ipairs(list) do
      out[id] = { kind = P.kind(id), text = P.text(id), voice = P.voice(id) }
    end
  end
  for c = 1, #cats do
    for _, id in ipairs(P.words(c)) do
      out[id] = { kind = "word", cat = c, text = P.text(id) }
    end
  end
  for _, k in ipairs(rawKeys(Data.Phrases, "phrases")) do
    if out[k] == nil then
      fail("phrases: phrase " .. number(k, "phrases") .. " has no bound record")
    end
  end
  return cats, voices, out
end

function M.build(ns)
  local Data, C, Cos, P = ns.Data or {}, ns.Collection, ns.Cosmetics, ns.Phrase
  -- Check 1: every bound module kept every record.
  local bad = {}
  for _, list in ipairs({ C.invalid, Cos.invalid, P.invalid }) do
    for _, label in ipairs(list) do
      bad[#bad + 1] = tostring(label)
    end
  end
  if #bad > 0 then
    fail("invalid: " .. concat(bad, ", "))
  end
  local continents, zones, inns = places(Data, C)
  local cats, voices, phraseRecs = phrases(Data, P)
  return {
    schema = SCHEMA,
    flavor = FLAVOR,
    atlasComplete = C.complete() == true,
    continents = continents,
    zones = zones,
    inns = inns,
    cosmetics = cosmetics(Data, Cos, zones),
    phraseCategories = cats,
    phraseVoices = voices,
    phrases = phraseRecs,
  }
end

-- ---------------------------------------------------------------------------
-- Loading and the command line (spec 3.1, 3.5).

-- The data files and their modules, in TOC order, into one fresh ns, each run as the
-- client and the specs run it: (addonName, ns) as `...`, in the strict environment.
function M.loadAddon()
  local load = dofile(LOADER)
  local wanted, left = {}, 0
  for _, d in ipairs(load.DATA) do
    wanted[d.path], left = true, left + 1
  end
  for _, path in ipairs(MODULES) do
    wanted[path], left = true, left + 1
  end
  local ns = {}
  for _, path in ipairs(load.toc_files()) do
    if wanted[path] then
      load.file(path, ns, load.pure_env())
      wanted[path], left = nil, left - 1
    end
  end
  if left > 0 then
    local missing = {}
    for path in pairs(wanted) do
      missing[#missing + 1] = path
    end
    sort(missing)
    fail("not in the TOC: " .. concat(missing, ", "))
  end
  return ns
end

local function readFile(path)
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local text = f:read("*a")
  f:close()
  return text
end

local USAGE = "usage: lua scripts/data-json.lua [--check]  (from the repo root)"

function M.main(args, path)
  args, path = args or {}, path or OUT
  local check = #args == 1 and args[1] == "--check"
  if (#args ~= 0 and not check) or readFile(TOC) == nil then
    print(USAGE)
    return 2
  end
  local ok, text = pcall(function()
    return M.encode(M.build(M.loadAddon()))
  end)
  if not ok then
    print("data-json: FAIL: " .. tostring(text))
    return 1
  end
  if check then
    if readFile(path) == text then
      print("data-json: OK.")
      return 0
    end
    print("data-json: FAIL: " .. path
      .. " is out of date; run lua scripts/data-json.lua and commit it.")
    return 1
  end
  local f = io.open(path, "wb")
  local written = f and f:write(text)
  if f then
    f:close()
  end
  if not written then
    print("data-json: FAIL: can't write " .. path)
    return 1
  end
  print(format("data-json: wrote %s (%d bytes).", path, #text))
  return 0
end

local args = { ... }
if args[1] == "--lib" then
  return M
end
os.exit(M.main(args))
