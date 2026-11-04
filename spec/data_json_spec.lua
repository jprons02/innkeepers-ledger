-- The data tables as JSON (docs/specs/data-json.md, section 6): the encoder against
-- hostile values, build over fixture data loaded through the real modules (and its
-- fail-closed checks), main's write and --check modes, and the committed file against the
-- real data. The generator is a dev tool, loaded here as a module.
local load = require("helpers.load")
local json = require("helpers.json_read")

local OUT = "docs/data/forever.json"

local function lib()
  return assert(loadfile("scripts/data-json.lua"))("--lib")
end

local M = lib()

local function readFile(path)
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local text = f:read("*a")
  f:close()
  return text
end

local function writeFile(path, text)
  local f = assert(io.open(path, "wb"))
  f:write(text)
  f:close()
end

local TMP = (os.getenv("TEMP") or os.getenv("TMPDIR") or "/tmp"):gsub("\\", "/")
  .. "/il_data_json_spec.json"

-- Runs fn with print captured; returns fn's result and the printed lines.
local function quiet(fn)
  local lines, saved = {}, _G.print
  _G.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do
      parts[i] = tostring(select(i, ...))
    end
    lines[#lines + 1] = table.concat(parts, "\t")
  end
  local ok, res = pcall(fn)
  _G.print = saved
  assert(ok, res)
  return res, lines
end

-- A fresh ns over `data` (a function returning the ns.Data table), loaded through the
-- real modules in TOC order.
local function bound(data)
  local ns = { Data = data() }
  for _, path in ipairs({ "Ledger.lua", "Phrase.lua", "Collection.lua", "Cosmetics.lua" }) do
    load.file(path, ns, load.pure_env())
  end
  return ns
end

-- The real data into a fresh ns, with `patch(Data)` run before the modules bind it.
local function realNs(patch)
  local ns = {}
  for _, d in ipairs(load.DATA) do
    load.file(d.path, ns, load.pure_env())
  end
  if patch then
    patch(ns.Data)
  end
  for _, path in ipairs({ "Ledger.lua", "Phrase.lua", "Collection.lua", "Cosmetics.lua" }) do
    load.file(path, ns, load.pure_env())
  end
  return ns
end

local function bytes(lo, hi, extra)
  local t = {}
  for b = lo, hi do
    t[#t + 1] = string.char(b)
  end
  return table.concat(t) .. (extra or "")
end

-- encode of one string value, without the quotes' line: the root must be a table, so a
-- string is wrapped as { s = v } and unwrapped from `{\n  "s": <here>\n}\n`.
local function encStr(v)
  local text = M.encode({ s = v })
  return assert(text:match('^{\n  "s": (.*)\n}\n$'))
end

local function roundTrip(v)
  return json.read(M.encode({ s = v })).s
end

describe("json_read (test helper)", function()
  it("reads objects, strings, integers and booleans", function()
    assert.same({ a = { b = 1, c = -25 }, d = "x\"\\\1\127", e = true, f = false, g = {} },
      json.read('{"a": {"b": 1, "c": -25}, "d": "x\\"\\\\\\u0001\\u007f", "e": true, '
        .. '"f": false, "g": {}}\n'))
  end)

  it("refuses everything outside the promised grammar", function()
    for _, bad in ipairs({
      "[1]", '{"a": [1]}', '{"a": null}', '{"a": 1.5}', '{"a": 1e5}', '{"a": 1E5}',
      '{"a": 01}', '{"a": -0}', '{"a": "\\n"}', '{"a": "\\t"}', '{"a": "\\/"}',
      '{"a": "\\u0041"}', '{"a": "\\u001F"}', '{"a": "\1"}', '{"a": "\127"}',
      '{"a": "\128"}', '{"a": "\237\160\128"}', '{"a": 1, "a": 2}', '{"a": 1,}',
      '{"a": 1} x', '{"a": 1}{}', '{"a":\t1}', '{"a": 1}\r\n', '{"a": 9007199254740992}',
      '{"a": "x}', '{a: 1}', '{"a" 1}', "",
    }) do
      assert.has_error(function()
        json.read(bad)
      end)
    end
  end)
end)

describe("data-json encode", function()
  it("escapes \", \\ and every control byte as \\u00xx, and nothing else", function()
    local controls = bytes(0, 31, "\127")
    local want = {}
    for b = 0, 31 do
      want[#want + 1] = string.format("\\u%04x", b)
    end
    want[#want + 1] = "\\u007f"
    assert.equal('"' .. table.concat(want) .. '"', encStr(controls))
    assert.equal('"\\"\\\\/ "', encStr('"\\/ '))
    assert.equal("a\"b\\c", roundTrip("a\"b\\c"))
    local ascii = bytes(0, 127)
    assert.equal(ascii, roundTrip(ascii))
  end)

  it("passes well-formed UTF-8 through byte for byte", function()
    for _, s in ipairs({
      "\195\169", -- é
      "\226\130\172", -- €
      "\240\159\152\128", -- U+1F600
      "\226\128\168", -- U+2028
      "\239\191\191", -- U+FFFF
      "\244\143\191\191", -- U+10FFFF
    }) do
      assert.equal('"' .. s .. '"', encStr(s))
      assert.equal(s, roundTrip(s))
    end
  end)

  it("refuses malformed UTF-8, naming the value's path", function()
    for _, s in ipairs({
      "\128", -- a lone continuation byte
      "ok\195", -- 0xC3 at the end
      "\226\130", -- truncated
      "\192\175", -- overlong
      "\224\128\175", -- overlong
      "\237\160\128", -- a surrogate
      "\244\144\128\128", -- above U+10FFFF
      "\245", "\255", "a\248b",
    }) do
      local ok, e = pcall(M.encode, { phrases = { [12] = { text = s } } })
      assert.is_false(ok)
      assert.matches("phrases.12.text", e, 1, true)
      assert.matches("UTF-8", e, 1, true)
    end
    local ok, e = pcall(M.encode, { ["\128"] = 1 })
    assert.is_false(ok)
    assert.matches("UTF-8", e, 1, true)
  end)

  it("writes integers exactly and refuses every other number", function()
    for n, s in pairs({ [0] = "0", [1] = "1", [-5] = "-5", [9999999] = "9999999",
      [2 ^ 53 - 1] = "9007199254740991", [-(2 ^ 53 - 1)] = "-9007199254740991" }) do
      assert.equal(s, encStr(n))
    end
    assert.equal("0", encStr(-0))
    assert.equal("0", encStr(-1 * 0))
    for _, n in ipairs({ 1.5, 0 / 0, 1 / 0, -1 / 0, 2 ^ 53, -(2 ^ 53), 1e300 }) do
      local ok, e = pcall(M.encode, { a = { b = n } })
      assert.is_false(ok)
      assert.matches("a.b", e, 1, true)
    end
  end)

  it("orders keys numerically or by byte, and refuses mixed or odd keys", function()
    assert.equal('{\n  "t": {\n    "9": 1,\n    "10": 2,\n    "100": 3\n  }\n}\n',
      M.encode({ t = { [10] = 2, [9] = 1, [100] = 3 } }))
    assert.equal('{\n  "B": 1,\n  "a": 2,\n  "aa": 3\n}\n',
      M.encode({ aa = 3, a = 2, B = 1 }))
    assert.equal("{}\n", M.encode({}))
    for _, bad in ipairs({
      { [1] = 1, a = 2 }, { [1.5] = 1 }, { [true] = 1 }, { [{}] = 1 },
      { [2 ^ 53] = 1 }, { a = print }, { a = coroutine.create(function() end) },
      { a = newproxy() }, { a = { b = { c = { [1] = 1, x = 2 } } } },
    }) do
      assert.has_error(function()
        M.encode(bad)
      end)
    end
    assert.has_error(function()
      M.encode(print)
    end)
  end)

  it("lays out the root and sections one member a line, deeper objects inline", function()
    local text = M.encode({
      n = 1,
      empty = {},
      recs = {
        [2] = { name = "B", rule = { kind = "zone", zone = 7 } },
        [1] = { name = "A", flag = true },
      },
    })
    assert.equal(table.concat({
      "{",
      '  "empty": {},',
      '  "n": 1,',
      '  "recs": {',
      '    "1": {"flag": true, "name": "A"},',
      '    "2": {"name": "B", "rule": {"kind": "zone", "zone": 7}}',
      "  }",
      "}",
      "",
    }, "\n"), text)
    assert.is_nil(text:find("\r", 1, true))
    assert.is_nil(text:find(" \n", 1, true))
    assert.is_nil(text:find("\t", 1, true))
  end)

  it("gives the same bytes whatever order the keys went in", function()
    local up, down = { recs = {} }, { recs = {} }
    for i = 1, 300 do
      up.recs[i] = { name = "N" .. i, ["k" .. i] = i }
    end
    for i = 300, 1, -1 do
      down.recs[i] = { ["k" .. i] = i, name = "N" .. i }
    end
    assert.equal(M.encode(up), M.encode(down))
  end)
end)

-- Fixture data (spec 6.2): a neutral inn, a Horde inn, an alias, two zones on one
-- continent (one marked), the continent marked, the atlas marked, a two-record catalog,
-- and phrases with a voiceless template.
local function fixture()
  return {
    Inns = {
      [5001] = { name = "Vale Inn", zone = 10 },
      [5002] = { name = "Ridge Inn", zone = 11, faction = "Horde" },
      [5003] = { alias = 5001 },
    },
    Zones = {
      [10] = { name = "Vale", continent = 1, seal = 101, complete = true },
      [11] = { name = "Ridge", continent = 1, seal = 102 },
    },
    Continents = { [1] = { name = "East", complete = true } },
    AtlasComplete = true,
    Cosmetics = {
      [1] = { kind = "seal", name = "Wayfarer's seal", rule = { kind = "inns", n = 5 } },
      [1001] = { kind = "quill", name = "Map quill", rule = { kind = "continent" } },
    },
    PhraseCategories = { "Hearth" },
    PhraseVoices = { "Warm" },
    Phrases = {
      [1] = { kind = "template", voice = 1, text = "Dreaming of {w}." },
      [101] = { kind = "template", text = "Rested well." },
      [501] = { kind = "conj", voice = 1, text = "And then..." },
      [1001] = { kind = "word", cat = 1, text = "home" },
    },
  }
end

describe("data-json build", function()
  it("reads every record through the bound modules", function()
    assert.same({
      schema = 1,
      flavor = "forever",
      atlasComplete = false,
      continents = { [1] = { name = "East", complete = false } },
      zones = {
        [10] = { name = "Vale", continent = 1, seal = 101, complete = true },
        [11] = { name = "Ridge", continent = 1, seal = 102, complete = false },
      },
      inns = {
        [5001] = { name = "Vale Inn", zone = 10 },
        [5002] = { name = "Ridge Inn", zone = 11, faction = "Horde" },
        [5003] = { alias = 5001 },
      },
      cosmetics = {
        [1] = { kind = "seal", name = "Wayfarer's seal", rule = { kind = "inns", n = 5 } },
        [101] = { kind = "seal", name = "Vale", rule = { kind = "zone", zone = 10 } },
        [102] = { kind = "seal", name = "Ridge", rule = { kind = "zone", zone = 11 } },
        [1001] = { kind = "quill", name = "Map quill", rule = { kind = "continent" } },
      },
      phraseCategories = { "Hearth" },
      phraseVoices = { "Warm" },
      phrases = {
        [1] = { kind = "template", text = "Dreaming of {w}.", voice = 1 },
        [101] = { kind = "template", text = "Rested well." },
        [501] = { kind = "conj", text = "And then...", voice = 1 },
        [1001] = { kind = "word", cat = 1, text = "home" },
      },
    }, M.build(bound(fixture)))
  end)

  it("keeps an atlas complete when every mark holds", function()
    local out = M.build(bound(function()
      local d = fixture()
      d.Zones[11].complete = true
      return d
    end))
    assert.is_true(out.atlasComplete)
    assert.is_true(out.continents[1].complete)
    assert.is_true(out.zones[11].complete)
  end)

  -- Each case: a broken ns, and the text its error must hold.
  local broken = {
    { "a bad inn", "invalid: inn 5009", function()
      return bound(function()
        local d = fixture()
        d.Inns[5009] = { name = "lowercase inn", zone = 10 }
        return d
      end)
    end },
    { "a bad cosmetic", "invalid: cosmetic 50", function()
      return bound(function()
        local d = fixture()
        d.Cosmetics[50] = { kind = "quill", name = "Wrong range", rule = { kind = "all" } }
        return d
      end)
    end },
    { "a bad phrase", "invalid: id 2", function()
      return bound(function()
        local d = fixture()
        d.Phrases[2] = { kind = "template", text = "no capital." }
        return d
      end)
    end },
    { "no zone seals (an empty atlas)", "zone seal", function()
      local ns = bound(fixture)
      ns.Cosmetics = ns.Cosmetics.bind(nil, ns.Data.Cosmetics)
      assert.same({}, ns.Cosmetics.invalid)
      return ns
    end },
    { "a continent with no bound record", "continent 3 has no bound record", function()
      local ns = bound(fixture)
      ns.Data.Continents[3] = { name = "North" }
      return ns
    end },
    { "an inn with no bound record", "inn 5004 has no bound record", function()
      local ns = bound(fixture)
      ns.Data.Inns[5004] = { name = "Late Inn", zone = 10 }
      return ns
    end },
    { "a zone with no bound record", "zone 12 has no bound record", function()
      local ns = bound(fixture)
      ns.Data.Zones[12] = { name = "Late", continent = 1, seal = 103 }
      return ns
    end },
    { "a cosmetic with no bound record", "cosmetic 3 has no bound record", function()
      local ns = bound(fixture)
      ns.Data.Cosmetics[3] = { kind = "seal", name = "Late seal", rule = { kind = "all" } }
      return ns
    end },
    { "a phrase with no bound record", "phrase 2 has no bound record", function()
      local ns = bound(fixture)
      ns.Data.Phrases[2] = { kind = "template", text = "Late." }
      return ns
    end },
    { "a raw key that isn't an integer", "key has no bound record", function()
      local ns = bound(fixture)
      ns.Data.Inns.x = { name = "Odd Inn", zone = 10 }
      return ns
    end },
  }

  for _, case in ipairs(broken) do
    it("fails closed on " .. case[1] .. ", and main writes nothing", function()
      local ok, e = pcall(M.build, case[3]())
      assert.is_false(ok)
      assert.matches(case[2], e, 1, true)

      local m = lib()
      m.loadAddon = case[3]
      os.remove(TMP)
      for _, args in ipairs({ {}, { "--check" } }) do
        local code, lines = quiet(function()
          return m.main(args, TMP)
        end)
        assert.equal(1, code)
        assert.matches("^data%-json: FAIL: ", lines[1])
        assert.matches(case[2], lines[1], 1, true)
        assert.is_nil(readFile(TMP))
      end
    end)
  end
end)

describe("data-json main", function()
  after_each(function()
    os.remove(TMP)
  end)

  it("writes, checks, and fails a stale or missing file", function()
    local m = lib()
    local code, lines = quiet(function()
      return m.main({}, TMP)
    end)
    local want = M.encode(M.build(M.loadAddon()))
    assert.equal(0, code)
    assert.equal(want, readFile(TMP))
    assert.same({ "data-json: wrote " .. TMP .. " (" .. #want .. " bytes)." }, lines)

    code, lines = quiet(function()
      return m.main({ "--check" }, TMP)
    end)
    assert.equal(0, code)
    assert.same({ "data-json: OK." }, lines)

    -- A byte appended to the file.
    writeFile(TMP, want .. "\n")
    code, lines = quiet(function()
      return m.main({ "--check" }, TMP)
    end)
    assert.equal(1, code)
    assert.same({ "data-json: FAIL: " .. TMP
      .. " is out of date; run lua scripts/data-json.lua and commit it." }, lines)
    assert.equal(want .. "\n", readFile(TMP))

    -- One record changed in the data before it's bound.
    writeFile(TMP, want)
    m.loadAddon = function()
      return realNs(function(Data)
        Data.Inns[254089].name = "Brightwater Inn"
      end)
    end
    code = quiet(function()
      return m.main({ "--check" }, TMP)
    end)
    assert.equal(1, code)
    assert.equal(want, readFile(TMP))

    -- A missing file.
    os.remove(TMP)
    m = lib()
    code = quiet(function()
      return m.main({ "--check" }, TMP)
    end)
    assert.equal(1, code)
    assert.is_nil(readFile(TMP))
  end)

  it("answers an unknown argument with usage and exit 2", function()
    for _, args in ipairs({ { "--write" }, { "--check", "x" }, { "-c" } }) do
      local code, lines = quiet(function()
        return M.main(args, TMP)
      end)
      assert.equal(2, code)
      assert.matches("^usage: ", lines[1])
    end
    assert.is_nil(readFile(TMP))
  end)
end)

-- Integer keys back from their decimal strings, one level down (the sections).
local function intKeys(t)
  local out = {}
  for k, v in pairs(t) do
    local n = tonumber(k)
    assert(n and string.format("%d", n) == k, "a section key isn't a decimal integer: " .. k)
    out[n] = v
  end
  return out
end

local function without(t, field)
  local out = {}
  for k, v in pairs(t) do
    if k ~= field then
      out[k] = v
    end
  end
  return out
end

describe("data-json and the real data", function()
  local ns = M.loadAddon()
  local text = readFile(OUT)

  it("has a committed file that is current", function()
    assert.is_string(text, OUT .. " is missing; run lua scripts/data-json.lua")
    assert.equal(M.encode(M.build(ns)), text,
      OUT .. " is out of date; run lua scripts/data-json.lua and commit it")
  end)

  it("parses back to the data tables, record for record", function()
    local Data, C = ns.Data, ns.Collection
    local doc = json.read(text)
    assert.same({
      atlasComplete = true, continents = true, cosmetics = true, flavor = true, inns = true,
      phraseCategories = true, phraseVoices = true, phrases = true, schema = true,
      zones = true,
    }, (function()
      local keys = {}
      for k in pairs(doc) do
        keys[k] = true
      end
      return keys
    end)())
    assert.equal(1, doc.schema)
    assert.equal("forever", doc.flavor)
    assert.equal(C.complete(), doc.atlasComplete)

    assert.same(Data.Inns, intKeys(doc.inns))
    assert.same(Data.Phrases, intKeys(doc.phrases))
    assert.same(Data.PhraseCategories, intKeys(doc.phraseCategories))
    assert.same(Data.PhraseVoices, intKeys(doc.phraseVoices))

    local zones, conts = intKeys(doc.zones), intKeys(doc.continents)
    assert.same(Data.Zones, (function()
      local out = {}
      for k, z in pairs(zones) do
        assert.equal(C.zone(k).complete, z.complete)
        out[k] = without(z, "complete")
        if Data.Zones[k] and Data.Zones[k].complete ~= nil then
          out[k].complete = Data.Zones[k].complete
        end
      end
      return out
    end)())
    assert.same(Data.Continents, (function()
      local out = {}
      for k, c in pairs(conts) do
        assert.equal(C.continent(k).complete, c.complete)
        out[k] = without(c, "complete")
        if Data.Continents[k] and Data.Continents[k].complete ~= nil then
          out[k].complete = Data.Continents[k].complete
        end
      end
      return out
    end)())

    local cosmetics = intKeys(doc.cosmetics)
    for k, z in pairs(Data.Zones) do
      assert.same({ kind = "seal", name = z.name, rule = { kind = "zone", zone = k } },
        cosmetics[z.seal])
      cosmetics[z.seal] = nil
    end
    assert.same(Data.Cosmetics, cosmetics)
  end)

  it("holds only integers, ASCII, LF and one final newline", function()
    local function walk(v)
      if type(v) == "table" then
        for _, x in pairs(v) do
          walk(x)
        end
      elseif type(v) == "number" then
        assert.equal(0, v % 1)
      end
    end
    walk(json.read(text))
    assert.equal("\n", text:sub(-1))
    assert.not_equal("\n", text:sub(-2, -2))
    assert.is_nil(text:find("\r", 1, true))
    assert.is_nil(text:find("[\128-\255]"))
    assert.is_nil(text:find("\t", 1, true))
    assert.is_nil(text:find(" \n", 1, true))
    assert.not_equal("\239\187\191", text:sub(1, 3))
  end)

  it("holds the spec's example lines as shown", function()
    for _, line in ipairs({
      '  "atlasComplete": false,',
      '    "947": {"complete": false, "name": "Azeroth"}',
      '    "101": {"kind": "seal", "name": "Zephras Isle", "rule": {"kind": "zone", '
        .. '"zone": 2521}},',
      '    "254089": {"name": "Calmbreeze Inn", "zone": 2521}',
      '    "1": {"kind": "template", "text": "Rested here, dreaming of {w}.", "voice": 1},',
      '    "501": {"kind": "conj", "text": "And then...", "voice": 1},',
      '    "1001": {"cat": 1, "kind": "word", "text": "home"},',
      '  "schema": 1,',
      '    "2521": {"complete": false, "continent": 947, "name": "Zephras Isle", "seal": 101}',
    }) do
      assert.is_truthy(text:find("\n" .. line .. "\n", 1, true), line)
    end
  end)

  it("gives the generator plain Lua 5.1 in .luacheckrc, no WoW globals", function()
    local env = { stds = {}, files = {}, ipairs = ipairs }
    local config = assert(loadfile(".luacheckrc"))
    setfenv(config, env)()
    assert.same({ std = "lua51" }, env.files["scripts/data-json.lua"])
  end)
end)
