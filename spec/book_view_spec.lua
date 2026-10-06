-- BookView: navigation, every page model, paging, ordering, text safety, dates, the quill
-- fallback and flourishes, the share snapshot and nudge, and the saved record
-- (docs/specs/book.md 6.2). Pure files in the strict environment, fixed times only.
-- Ledgers and travelers' data are hostile here too: malformed, oversized and stand-ins.
local load = require("helpers.load")
local fx = require("helpers.places")

local T = fx.T                       -- 1790000000, 21 September 2026 (UTC)
local DAY, WEEK = 86400, 604800
local ANCHOR = 1790089200            -- Tuesday 2026-09-22 15:00 UTC
local OWNER = "Player-1-0000AAAA"
local NOW = T + 2 * WEEK

-- A fresh ns in TOC order; `data` adds the shipped Data tables.
local function modules(data, env)
  local ns = {}
  load.file("Ledger.lua", ns, load.pure_env())
  if data then
    load.file("Data/Inns.lua", ns, load.pure_env())
    load.file("Data/Phrases.lua", ns, load.pure_env())
    load.file("Data/Cosmetics.lua", ns, load.pure_env())
  end
  for _, path in ipairs({ "Phrase.lua", "Collection.lua", "Cosmetics.lua", "SignFlow.lua" }) do
    load.file(path, ns, load.pure_env())
  end
  load.file("BookView.lua", ns, env or load.pure_env())
  return ns
end

local NS = modules(false)
local REAL = modules(true)
local BookView, Ledger = NS.BookView, NS.Ledger
local TEXT, LIMITS, FLOURISHES = BookView.TEXT, BookView.LIMITS, BookView.FLOURISHES

-- The phrase fixture of docs/specs/phrase.md 6: {2} renders "Rest well.", {1, 1000}
-- "Here's to the hearth!", and {1} (a slot without its word) doesn't render.
local function phraseData()
  return {
    [1] = { kind = "template", text = "Here's to {w}!" },
    [2] = { kind = "template", text = "Rest well." },
    [500] = { kind = "conj", text = "And then..." },
    [1000] = { kind = "word", cat = 1, text = "the hearth" },
    [1100] = { kind = "word", cat = 2, text = "hot stew" },
  }, { "Home", "Food" }
end

-- Catalog C plus two quills: 1004 (10 inns, locked over E) and 1005 (1 inn), five in all.
local function catalogPlus()
  local c = fx.catalog()
  c[1004] = { kind = "quill", name = "Grand quill", rule = { kind = "inns", n = 10 } }
  c[1005] = { kind = "quill", name = "Plain grey quill", rule = { kind = "inns", n = 1 } }
  return c
end

-- Fixture deps: places F (or `over.places`), the phrase fixture, catalog C (or
-- `over.catalog`). `over` replaces any field.
local function deps(over)
  over = over or {}
  local inns, zones, conts
  if over.places then
    inns, zones, conts = over.places()
  else
    inns, zones, conts = fx.places()
  end
  local atlas = NS.Collection.bind(inns, zones, conts)
  assert(#atlas.invalid == 0 or over.allowInvalid)
  local d = {
    inns = inns,
    atlas = atlas,
    phrase = NS.Phrase.bind(phraseData()),
    cosmetics = NS.Cosmetics.bind(atlas, over.catalog or fx.catalog()),
  }
  for k, v in pairs(over) do
    if k ~= "places" and k ~= "catalog" and k ~= "allowInvalid" then
      d[k] = v
    end
  end
  return d
end

local function newView(over)
  return BookView.new(deps(over))
end

local function newLedger(data)
  return Ledger.new(data or {}, { guid = OWNER, name = "Aldric" }, ANCHOR)
end

-- A ledger holding entries E (each with the phrase {2}); returns the ledger and its table.
local function ledgerE()
  local data = {}
  local ledger = newLedger(data)
  for _, e in ipairs(fx.entries()) do
    e.phrase = { 2 }
    assert.equal("added", ledger:addOwn(e))
  end
  return ledger, data
end

local function traveler(n)
  return string.format("Player-1-%08X", n)
end

local function addTraveler(ledger, guid, name, inn, t, seal, phrase)
  assert.equal("added", ledger:addForeign(guid, name,
    { inn = inn, t = t, phrase = phrase or { 2 }, seal = seal }, NOW))
end

-- A situation: Alliance, named Aldric, UTC, the record writable. `over` replaces fields.
local function sit(ledger, over)
  local s = { ledger = ledger, faction = "Alliance", name = "Aldric", offset = 0,
    prefsWritable = true }
  for k, v in pairs(over or {}) do
    s[k] = v
  end
  return s
end

local function date(t)
  return BookView.dateText(t, 0)
end

-- The rows of a list page as compact strings: "c East 3 of 3", "z Vale signed 2 of 2",
-- "i 5001 Vale Inn +" (signed) or "-" (faded); a trailing "*" marks a repeated header.
local function listLines(page)
  local out = {}
  for _, r in ipairs(page.rows) do
    local line
    if r.kind == "inn" then
      line = "i " .. r.key .. " " .. r.text .. (r.signed and " +" or " -")
      assert.equal(not r.signed, r.faded)
    else
      line = r.kind:sub(1, 1) .. " " .. r.text .. " " .. r.sub
    end
    out[#out + 1] = line .. (r.cont and " *" or "")
  end
  return out
end

-- Every string anywhere in a model.
local function strings(v, out, seen)
  out, seen = out or {}, seen or {}
  if type(v) == "string" then
    out[#out + 1] = v
  elseif type(v) == "table" and not seen[v] then
    seen[v] = true
    for k, x in pairs(v) do
      strings(k, out, seen)
      strings(x, out, seen)
    end
  end
  return out
end

local function hostileValues()
  return { 0 / 0, 1 / 0, 1.5, -1, "2", true, {}, fx.hostileTable(), fx.hostileProxy(),
    function() end }
end

-- ---------------------------------------------------------------------------

describe("BookView.new", function()
  it("loads in the strict environment and exports copies of its constants", function()
    local ns = modules(false)
    local B = ns.BookView
    assert.is_function(B.new)
    B.TEXT.yours = "changed"
    B.TEXT.months[1] = "changed"
    B.LIMITS.innRows = 1
    B.FLOURISHES[1] = "x"
    local inns, zones, conts = fx.places()
    local atlas = ns.Collection.bind(inns, zones, conts)
    local view = B.new({ inns = inns, atlas = atlas, phrase = ns.Phrase.bind(phraseData()),
      cosmetics = ns.Cosmetics.bind(atlas, fx.catalog()) })
    local m = view.build({}, { inn = 5001 })
    assert.equal("Your signatures", m.right.rows[1].text)
    assert.equal(4, #m.right.rows)
    assert.equal("21 January 2027", B.dateText(1800500000, 0))
  end)

  it("reads its limits from Ledger and Collection", function()
    assert.equal(Ledger.LIMITS.tMin, LIMITS.tMin)
    assert.equal(Ledger.LIMITS.tMax, LIMITS.tMax)
    assert.equal(Ledger.LIMITS.cosmeticIdMax, LIMITS.cosmeticIdMax)
    assert.equal(NS.Collection.LIMITS.ownMax, LIMITS.ownMax)
    assert.same({ 16, 6, 6, 12, 6, 7, 1000, 600, 8, 20000, 64 }, {
      LIMITS.listRows, LIMITS.innRows, LIMITS.barRows, LIMITS.stampCells, LIMITS.quillRows,
      LIMITS.sealRows, LIMITS.ownReadMax, LIMITS.foreignReadMax, LIMITS.aliasesMax,
      LIMITS.innsReadMax, LIMITS.nameBytes })
  end)

  it("raises without ns.Ledger", function()
    assert.has_error(function()
      load.file("BookView.lua", {}, load.pure_env())
    end)
  end)

  it("raises without deps, a dep table or a needed function", function()
    assert.has_error(function() BookView.new() end)
    assert.has_error(function() BookView.new("x") end)
    for _, key in ipairs({ "inns", "atlas", "phrase", "cosmetics" }) do
      local d = deps()
      d[key] = nil
      assert.has_error(function() BookView.new(d) end, nil, key)
    end
    local needed = {
      atlas = { "progress", "innOf", "inn", "zone", "continent" },
      phrase = { "render" },
      cosmetics = { "catalog", "unlocked", "info" },
    }
    for dep, names in pairs(needed) do
      for _, name in ipairs(names) do
        local d = deps()
        local copy = {}
        for k, v in pairs(d[dep]) do
          copy[k] = v
        end
        copy[name] = nil
        d[dep] = copy
        assert.has_error(function() BookView.new(d) end, nil, dep .. "." .. name)
      end
    end
  end)

  it("keeps the default sizes for any size out of range", function()
    local ledger = ledgerE()
    for _, bad in ipairs({ 2, 51, 1.5, "6", 0 / 0 }) do
      local view = newView({ sizes = { listRows = bad, innRows = bad, barRows = bad,
        stampCells = bad, quillRows = bad, sealRows = bad } })
      local m = view.build(sit(ledger, { faction = false }), { listPage = 1 })
      assert.equal(1, m.left.pages, tostring(bad))
      assert.equal(12, #m.left.rows)
    end
    local m = newView({ sizes = "x" }).build(sit(ledger, { faction = false }), { listPage = 1 })
    assert.equal(12, #m.left.rows)
    m = newView({ sizes = { listRows = 3 } }).build(sit(ledger), { listPage = 1 })
    assert.equal(3, #m.left.rows)
  end)
end)

describe("BookView: the inn index", function()
  it("groups an alias with its primary", function()
    local view = newView()
    assert.equal(5001, view.innKey(5001))
    assert.equal(5001, view.innKey(5003))
    assert.equal(5101, view.innKey(5101))
    assert.is_nil(view.innKey(nil))
    for i, bad in ipairs({ 9999, "5001", 0 / 0, 1.5, fx.hostileTable(), fx.hostileProxy() }) do
      assert.is_nil(view.innKey(bad), i)
    end
  end)

  it("reads every NPC ID of the group, once each", function()
    local view = newView()
    local calls = {}
    local ledger = { readOnly = false, own = function() return {} end,
      innEntries = function(_, id)
        calls[#calls + 1] = id
        return { own = {}, foreign = {} }
      end }
    view.build(sit(ledger), { inn = 5001 })
    table.sort(calls)
    assert.same({ 5001, 5003 }, calls)
  end)

  it("leaves out a key bind excluded", function()
    local view = newView({ allowInvalid = true, places = function()
      local inns, zones, conts = fx.places()
      inns[5004] = { alias = 7777 } -- no such primary
      inns[5005] = { name = "bad|name", zone = 10 }
      return inns, zones, conts
    end })
    assert.is_nil(view.innKey(5004))
    assert.is_nil(view.innKey(5005))
    local m = view.build(sit(nil, { faction = false }), { listPage = 1, inn = 5005 })
    assert.is_nil(m.nav.inn)
    for _, r in ipairs(m.left.rows) do
      assert.is_true(r.key ~= 5005)
    end
  end)

  it("keeps at most 8 NPC IDs in a group, the primary always", function()
    local view = newView({ places = function()
      local inns, zones, conts = fx.places()
      for i = 1, 10 do
        inns[6000 + i] = { alias = 5101 }
      end
      return inns, zones, conts
    end })
    local calls = {}
    local ledger = { readOnly = false, own = function() return {} end,
      innEntries = function(_, id)
        calls[#calls + 1] = id
        return {}
      end }
    view.build(sit(ledger), { inn = 5101 })
    table.sort(calls)
    assert.same({ 5101, 6001, 6002, 6003, 6004, 6005, 6006, 6007 }, calls)
    -- A dropped alias still finds its inn through the atlas.
    assert.equal(5101, view.innKey(6010))
  end)
end)

describe("BookView.plain", function()
  local plain = BookView.plain

  it("passes a clean name unchanged", function()
    assert.equal("Mira Ashvale", plain("Mira Ashvale", 64, "F"))
    assert.equal("Zo\195\171", plain("Zo\195\171", 64, "F"))
    assert.equal("Aldric-Stubrealm", plain("Aldric-Stubrealm", 64, "F"))
    assert.equal("\226\130\172\240\159\141\186", plain("\226\130\172\240\159\141\186", 64, "F"))
  end)

  it("replaces a name with a UI escape or a control byte, never escaping it", function()
    for _, s in ipairs({ "a|cffff0000b", "a||b", "a\nb", "a\0b", "a\127b", "|", "a\tb" }) do
      assert.equal("F", plain(s, 64, "F"), s)
    end
  end)

  it("replaces malformed UTF-8", function()
    for _, s in ipairs({ "\128", "Zo\195", "\192\128", "\193\191", "\245\128\128\128",
      "\226\130", "\195\40", "\240\159\141", "\255", "a\191b" }) do
      assert.equal("F", plain(s, 64, "F"), s)
    end
  end)

  it("gives the fallback for anything not a non-empty string, without raising", function()
    assert.equal("F", plain(nil, 64, "F"))
    for _, v in ipairs({ 7, "", {}, true, fx.hostileTable(), fx.hostileProxy() }) do
      assert.equal("F", plain(v, 64, "F"))
    end
    assert.is_nil(plain(nil, 64))
    assert.is_nil(plain("a|b", 64))
  end)

  it("cuts a long name at a character boundary and marks the cut", function()
    local name = string.rep("a", 70)
    assert.equal(string.rep("a", 64) .. "...", plain(name, 64, "F"))
    -- Bytes 64-65 are one two-byte character: the cut backs off to byte 63.
    local s = string.rep("a", 63) .. "\195\169" .. "bc"
    assert.equal(string.rep("a", 63) .. "...", plain(s, 64, "F"))
    assert.equal(string.rep("a", 64), plain(string.rep("a", 64), 64, "F"))
    -- A bad maxBytes uses the name cap.
    assert.equal(string.rep("a", 64) .. "...", plain(name, "x", "F"))
    assert.equal(string.rep("a", 64) .. "...", plain(name, 0 / 0, "F"))
  end)

  it("never returns a pipe", function()
    for b = 0, 255 do
      local out = plain("ab" .. string.char(b) .. "cd", 64, "F")
      assert.is_nil(out:find("|", 1, true), b)
    end
  end)
end)

describe("BookView.dateText", function()
  local dateText = BookView.dateText

  it("writes the local calendar date", function()
    assert.equal("17 September 2026", dateText(1789603200, 0))
    assert.equal("16 September 2026", dateText(1789603200, -3600))
    assert.equal("29 February 2028", dateText(1835395200, 0))
    assert.equal("31 December 2026", dateText(1798758000, 0))
    assert.equal("1 January 2027", dateText(1798758000, 3600))
    assert.equal("1 March 2100", dateText(4107542400, 0)) -- 2100 isn't a leap year
    assert.equal("21 September 2026", dateText(T, 0))
  end)

  it("agrees with the C library's UTC calendar over a spread of days", function()
    local months = TEXT.months
    local seed = 12345
    for _ = 1, 2000 do
      seed = seed * 16807 % 2147483647
      local t = LIMITS.tMin + seed % (60 * 365 * DAY)
      local c = os.date("!*t", t)
      assert.equal(c.day .. " " .. months[c.month] .. " " .. c.year, dateText(t, 0), t)
    end
  end)

  it("treats a bad offset as UTC", function()
    assert.equal("31 December 2026", dateText(1798758000, nil))
    for i, offset in ipairs({ 0 / 0, 1.5, 50401, -50401, "0", fx.hostileProxy() }) do
      assert.equal("31 December 2026", dateText(1798758000, offset), i)
    end
    assert.equal("1 January 2027", dateText(1798758000, 50400))
  end)

  it("is nil for anything not a time", function()
    assert.is_nil(dateText(nil, 0))
    for i, t in ipairs({ LIMITS.tMin - 1, LIMITS.tMax + 1, 0 / 0, "1789603200", 1789603200.5,
      fx.hostileTable() }) do
      assert.is_nil(dateText(t, 0), i)
    end
    assert.equal("20 November 2286", dateText(LIMITS.tMax, 0))
  end)
end)

describe("BookView: navigation", function()
  it("normalizes every field to its default, never raising", function()
    local view = newView()
    local ledger = ledgerE()
    local fields = { "tab", "listPage", "inn", "innPage", "barPage", "stampPage", "quillPage",
      "sealPage" }
    for _, field in ipairs(fields) do
      for _, bad in ipairs(hostileValues()) do
        local nav = { tab = "inns", inn = 5001 }
        nav[field] = bad
        local m = view.build(sit(ledger), nav)
        assert.is_nil(m.error, field)
        assert.is_true(m.nav.tab == "inns", field)
        for _, p in ipairs({ "innPage", "barPage", "stampPage", "quillPage", "sealPage" }) do
          assert.is_true(m.nav[p] >= 1)
        end
      end
    end
    for _, nav in ipairs(hostileValues()) do
      local m = view.build(sit(ledger), nav)
      assert.is_nil(m.error)
      assert.equal("inns", m.nav.tab)
      assert.equal(1, m.nav.listPage)
      assert.is_nil(m.nav.inn)
    end
  end)

  it("takes only the four tab names", function()
    local view = newView()
    for _, tab in ipairs({ "inns", "collection", "cosmetics", "share" }) do
      assert.equal(tab, view.build(sit(nil), { tab = tab }).tab)
    end
    assert.equal("inns", view.build(sit(nil), { tab = "Inns" }).tab)
    assert.equal("inns", view.build(sit(nil), { tab = "travelers" }).tab)
  end)

  it("keeps only a primary inn the atlas knows", function()
    local view = newView()
    assert.equal(5001, view.build(sit(nil), { inn = 5001 }).nav.inn)
    -- Another faction's inn still opens (the Read button).
    assert.equal(5202, view.build(sit(nil), { inn = 5202 }).nav.inn)
    for _, inn in ipairs({ 5003, 9999, 5001.5, "5001", 0 }) do
      local m = view.build(sit(nil), { inn = inn })
      assert.is_nil(m.nav.inn, tostring(inn))
      assert.equal("help", m.right.kind)
    end
  end)

  it("clamps pages past the end to the last", function()
    local view = newView({ sizes = { listRows = 5 } })
    local ledger = ledgerE()
    local m = view.build(sit(ledger), { listPage = 99, inn = 5001, innPage = 99 })
    assert.equal(3, m.nav.listPage)
    assert.equal(1, m.nav.innPage)
    m = view.build(sit(ledger), { tab = "collection", barPage = 7, stampPage = 9 })
    assert.same({ 1, 2 }, { m.nav.barPage, m.nav.stampPage })
    m = view.build(sit(ledger), { tab = "cosmetics", quillPage = 7, sealPage = 9 })
    assert.same({ 1, 1 }, { m.nav.quillPage, m.nav.sealPage })
    -- A page of a tab not built this time is kept for later.
    m = view.build(sit(ledger), { tab = "share", barPage = 7, listPage = 5 })
    assert.same({ 7, 5 }, { m.nav.barPage, m.nav.listPage })
  end)

  it("defaults the list page: the title without own entries, else the list", function()
    local view = newView({ sizes = { listRows = 5 } })
    assert.equal(0, view.build(sit(newLedger()), {}).nav.listPage)
    assert.equal(0, view.build(sit(nil), {}).nav.listPage)
    local one = newLedger()
    assert.equal("added", one:addOwn({ inn = 5001, t = T, phrase = { 2 } }))
    assert.equal(1, view.build(sit(one), {}).nav.listPage)
    -- The page holding the inn (page 2 with five rows a page).
    assert.equal(2, view.build(sit(one), { inn = 5001 }).nav.listPage)
    assert.equal(3, view.build(sit(one), { inn = 5201 }).nav.listPage)
    -- An inn the list doesn't show (another faction's): the usual default.
    assert.equal(1, view.build(sit(one), { inn = 5202 }).nav.listPage)
    assert.equal(0, view.build(sit(newLedger()), { inn = 5202 }).nav.listPage)
    -- An explicit page stays.
    assert.equal(0, view.build(sit(one), { inn = 5001, listPage = 0 }).nav.listPage)
  end)
end)

describe("BookView: the title and help pages", function()
  it("names the ledger after a valid name", function()
    local view = newView()
    local m = view.build(sit(nil, { name = "Aldric" }), {})
    assert.same({ kind = "title", title = "The ledger of Aldric",
      steps = { TEXT.step1, TEXT.step2, TEXT.step3 }, hint = TEXT.hint, page = 0, pages = 1 },
      m.left)
    for _, name in ipairs({ false, "Ald|cric", "Zo\195", "", 7 }) do
      local s = sit(nil)
      s.name = name or nil
      assert.equal("Your ledger", view.build(s, {}).left.title)
    end
    assert.same({ kind = "help", travelersTitle = "Travelers", travelersText = TEXT.travelersText,
      sharesTitle = "What your ledger shares", sharesText = TEXT.sharesText }, m.right)
  end)

  it("says what sync shares in the README's exact words", function()
    local f = assert(io.open("README.md", "rb"))
    local readme = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    local start = readme:find("What sync shares: ", 1, true)
    assert.is_number(start)
    local rest = readme:sub(start + #"What sync shares: ")
    local para = rest:match("^(.-)\n%s*\n") or rest
    local words = {}
    for line in para:gmatch("[^\n]+") do
      words[#words + 1] = line:match("^%s*(.-)%s*$")
    end
    local sentence = table.concat(words, " ")
    sentence = sentence:sub(1, 1):upper() .. sentence:sub(2)
    assert.equal(sentence, TEXT.sharesText)
  end)
end)

describe("BookView: the inn list", function()
  it("lists the Alliance's inns by continent, zone and name", function()
    local m = newView().build(sit(ledgerE()), { listPage = 1 })
    assert.equal("list", m.left.kind)
    assert.same({
      "c East 3 of 3",
      "z Marsh signed 1 of 1",
      "i 5101 Marsh Inn +",
      "z Vale signed 2 of 2",
      "i 5002 Hill Inn +",
      "i 5001 Vale Inn +",
      "c West 1 of 1",
      "z Dunes signed 1 of 1",
      "i 5201 Dune Inn +",
    }, listLines(m.left))
    assert.same({ 1, 1 }, { m.left.page, m.left.pages })
    assert.is_nil(m.left.empty)
  end)

  it("lists the Horde's inns, unsigned ones faded", function()
    local m = newView().build(sit(ledgerE(), { faction = "Horde" }), { listPage = 1 })
    assert.same({
      "c East 1 of 1",
      "z Vale signed 1 of 1",
      "i 5001 Vale Inn +",
      "c West 1 of 3",
      "z Dunes signed 1 of 2",
      "i 5201 Dune Inn +",
      "i 5202 Oasis Inn -",
      "z Ridge signed 0 of 1",
      "i 5301 Ridge Inn -",
    }, listLines(m.left))
  end)

  it("lists every inn with no faction", function()
    local s = sit(ledgerE())
    s.faction = nil
    local m = newView().build(s, { listPage = 1 })
    assert.equal(12, #m.left.rows)
    local keys = {}
    for _, r in ipairs(m.left.rows) do
      if r.kind == "inn" then
        keys[#keys + 1] = r.key
      end
    end
    assert.same({ 5101, 5002, 5001, 5201, 5202, 5301 }, keys)
  end)

  it("marks the selected inn", function()
    local m = newView().build(sit(ledgerE()), { listPage = 1, inn = 5002 })
    for _, r in ipairs(m.left.rows) do
      if r.kind == "inn" then
        assert.equal(r.key == 5002, r.selected)
      else
        assert.is_nil(r.selected)
      end
    end
  end)

  it("pages five rows at a time, repeating headers a page starts under", function()
    local view = newView({ sizes = { listRows = 5 } })
    local s = sit(ledgerE())
    local pages = {}
    for i = 1, 3 do
      local m = view.build(s, { listPage = i })
      assert.same({ i, 3 }, { m.left.page, m.left.pages })
      pages[i] = listLines(m.left)
    end
    assert.same({
      { "c East 3 of 3", "z Marsh signed 1 of 1", "i 5101 Marsh Inn +", "z Vale signed 2 of 2",
        "i 5002 Hill Inn +" },
      { "c East 3 of 3 *", "z Vale signed 2 of 2 *", "i 5001 Vale Inn +", "c West 1 of 1",
        "z Dunes signed 1 of 1" },
      { "c West 1 of 1 *", "z Dunes signed 1 of 1 *", "i 5201 Dune Inn +" },
    }, pages)
    -- Every inn on exactly one page.
    local seen = {}
    for _, page in ipairs(pages) do
      for _, line in ipairs(page) do
        local key = line:match("^i (%d+)")
        if key then
          assert.is_nil(seen[key])
          seen[key] = true
        end
      end
    end
    assert.same({ ["5101"] = true, ["5002"] = true, ["5001"] = true, ["5201"] = true }, seen)
    -- The title page counts the list's pages.
    assert.same({ 0, 3 }, { view.build(s, { listPage = 0 }).left.page,
      view.build(s, { listPage = 0 }).left.pages })
  end)

  it("shows one empty page when no inn is known", function()
    local view = newView({ places = function() return {}, {}, {} end })
    local m = view.build(sit(ledgerE()), { listPage = 1 })
    assert.same({ kind = "list", rows = {}, page = 1, pages = 1, empty = TEXT.noInns }, m.left)
    m = view.build(sit(ledgerE()), { inn = 5001 })
    assert.is_nil(m.nav.inn)
    assert.equal("help", m.right.kind)
  end)
end)

describe("BookView: an inn's page", function()
  local function withTravelers()
    local ledger, data = ledgerE()
    addTraveler(ledger, traveler(10), "Mira", 5001, T + 50, 1)
    addTraveler(ledger, traveler(11), "Bram", 5003, T + 60, 101)
    return ledger, data
  end

  it("merges the group's entries, newest first, with the inn's numbers", function()
    local m = newView().build(sit(withTravelers()), { inn = 5001 })
    assert.same({
      kind = "inn", key = 5001, title = "Vale Inn", place = "Vale, East",
      stamp = { signed = true, date = date(T) },
      countText = "Signed 3 times",
      lastText = "Last signed " .. date(T + WEEK),
      rows = {
        { kind = "heading", text = "Your signatures" },
        { kind = "own", date = "28 September 2026", text = "Rest well." },
        { kind = "own", date = "21 September 2026", text = "Rest well." },
        { kind = "own", date = "21 September 2026", text = "Rest well." },
        { kind = "heading", text = "Travelers' signatures" },
        { kind = "foreign", name = "Bram", date = "21 September 2026", text = "Rest well.",
          seal = "Sealed with Vale seal" },
      },
      page = 1, pages = 2,
    }, m.right)
    local m2 = newView().build(sit(withTravelers()), { inn = 5001, innPage = 2 })
    assert.same({
      { kind = "heading", text = "Travelers' signatures", cont = true },
      { kind = "foreign", name = "Mira", date = "21 September 2026", text = "Rest well.",
        seal = "Sealed with First seal" },
    }, m2.right.rows)
  end)

  it("reads once and has no last line for one signature", function()
    local ledger = newLedger()
    assert.equal("added", ledger:addOwn({ inn = 5101, t = T, phrase = { 1, 1000 } }))
    local m = newView().build(sit(ledger), { inn = 5101 })
    assert.equal("Signed once", m.right.countText)
    assert.is_nil(m.right.lastText)
    assert.equal("Here's to the hearth!", m.right.rows[2].text)
    m = newView().build(sit(ledger), { inn = 5002 })
    assert.equal("Not signed yet", m.right.countText)
    assert.same({ signed = false }, m.right.stamp)
    assert.equal("Hill Inn", m.right.title)
  end)

  it("orders travelers' entries at one time by signer bytes, then NPC ID", function()
    local ledger = newLedger()
    local A, a = "Player-1-0000000A", "Player-1-0000000a"
    addTraveler(ledger, a, "Lower", 5001, T)
    addTraveler(ledger, A, "Upper", 5003, T)
    addTraveler(ledger, A, "Upper", 5001, T)
    local m = newView().build(sit(ledger), { inn = 5001 })
    local names = {}
    for _, r in ipairs(m.right.rows) do
      if r.kind == "foreign" then
        names[#names + 1] = r.name
      end
    end
    assert.same({ "Upper", "Upper", "Lower" }, names)
    -- And the two Upper rows: 5001 before 5003. The fake below tells them apart by phrase.
    local fake = { readOnly = false, own = function() return {} end,
      innEntries = function(_, id)
        local text = id == 5001 and { 2 } or { 1, 1000 }
        return { own = {}, foreign = { { signer = A, name = "Upper",
          entry = { inn = id, t = T, phrase = text } } } }
      end }
    m = newView().build(sit(fake), { inn = 5001 })
    assert.equal("Rest well.", m.right.rows[4].text)
    assert.equal("Here's to the hearth!", m.right.rows[5].text)
  end)

  it("orders own entries at one time by NPC ID, the inn before its alias", function()
    local function texts(ledger)
      local out = {}
      for _, r in ipairs(newView().build(sit(ledger), { inn = 5001 }).right.rows) do
        if r.kind == "own" then
          out[#out + 1] = r.text
        end
      end
      return out
    end
    local ledger = newLedger()
    assert.equal("added", ledger:addOwn({ inn = 5003, t = T, phrase = { 1, 1000 } }))
    assert.equal("added", ledger:addOwn({ inn = 5001, t = T, phrase = { 2 } }))
    assert.same({ "Rest well.", "Here's to the hearth!" }, texts(ledger))
    -- Read in the other order (each ID answers with the other's entry): the same result.
    local fake = { readOnly = false, own = function() return {} end,
      innEntries = function(_, id)
        local e = id == 5001 and { inn = 5003, t = T, phrase = { 1, 1000 } }
          or { inn = 5001, t = T, phrase = { 2 } }
        return { own = { e }, foreign = {} }
      end }
    assert.same({ "Rest well.", "Here's to the hearth!" }, texts(fake))
  end)

  it("says so when nobody signed: both headings, both notes", function()
    local m = newView().build(sit(newLedger()), { inn = 5001 })
    assert.same({
      { kind = "heading", text = "Your signatures" },
      { kind = "note", text = "You haven't signed this guestbook yet." },
      { kind = "heading", text = "Travelers' signatures" },
      { kind = "note", text = "No traveler you've met has signed here yet." },
    }, m.right.rows)
    assert.same({ 1, 1 }, { m.right.page, m.right.pages })
    assert.equal("Not signed yet", m.right.countText)
  end)

  it("pages four rows at a time with repeated headings", function()
    local ledger = ledgerE()
    for i = 1, 5 do
      addTraveler(ledger, traveler(i), "Traveler", 5001, T + i * DAY)
    end
    local view = newView({ sizes = { innRows = 4 } })
    local kinds = {}
    for page = 1, 3 do
      local m = view.build(sit(ledger), { inn = 5001, innPage = page })
      assert.same({ page, 3 }, { m.right.page, m.right.pages })
      local line = {}
      for _, r in ipairs(m.right.rows) do
        line[#line + 1] = r.kind .. (r.cont and "*" or "")
      end
      kinds[page] = table.concat(line, " ")
    end
    assert.same({
      "heading own own own",
      "heading foreign foreign foreign",
      "heading* foreign foreign",
    }, kinds)
    -- A page starting with own entries repeats its heading too.
    view = newView({ sizes = { innRows = 3 } })
    local m = view.build(sit(ledger), { inn = 5001, innPage = 2 })
    assert.same({ kind = "heading", text = "Your signatures", cont = true }, m.right.rows[1])
    assert.equal("own", m.right.rows[2].kind)
  end)

  it("renders only the page it shows", function()
    local d = deps()
    local real = d.phrase.render
    local renders = 0
    d.phrase = { render = function(ids)
      renders = renders + 1
      return real(ids)
    end }
    local foreign = {}
    for i = 1, 300 do
      foreign[i] = { signer = traveler(i), name = "Mira",
        entry = { inn = 5001, t = T + i * 60, phrase = { 2 } } }
    end
    local calls = {}
    local fake = { readOnly = false, own = function() return {} end,
      innEntries = function(_, id)
        calls[id] = (calls[id] or 0) + 1
        if id == 5001 then
          return { own = {}, foreign = foreign }
        end
        return { own = {}, foreign = {} }
      end }
    local view = BookView.new(d)
    for _, page in ipairs({ 1, 30, 61, 99 }) do
      renders, calls = 0, {}
      local m = view.build(sit(fake), { inn = 5001, innPage = page })
      assert.is_true(renders <= LIMITS.innRows, renders)
      assert.same({ [5001] = 1, [5003] = 1 }, calls)
      assert.equal(61, m.right.pages)
    end
  end)

  it("reads at most 1 000 own and 600 foreign items, keeping the newest", function()
    local bigOwn, bigForeign = {}, {}
    for i = 1, 5000 do
      bigOwn[i] = { inn = 5101, t = T + i * DAY, phrase = { 2 } }
      bigForeign[i] = { signer = traveler(i), name = "Mira",
        entry = { inn = 5101, t = T + i * DAY, phrase = { 2 } } }
    end
    local counts = { [bigOwn] = 0, [bigForeign] = 0 }
    local env = load.pure_env()
    rawset(env, "rawget", function(t, k)
      if counts[t] then
        counts[t] = counts[t] + 1
      end
      return rawget(t, k)
    end)
    local ns = modules(false, env)
    local inns, zones, conts = fx.places()
    local atlas = ns.Collection.bind(inns, zones, conts)
    local view = ns.BookView.new({ inns = inns, atlas = atlas,
      phrase = ns.Phrase.bind(phraseData()), cosmetics = ns.Cosmetics.bind(atlas, fx.catalog()) })
    local fake = { readOnly = false, own = function() return {} end,
      innEntries = function() return { own = bigOwn, foreign = bigForeign } end }
    local m = view.build(sit(fake), { inn = 5101 })
    assert.is_nil(m.error)
    assert.is_true(counts[bigOwn] <= 1000, counts[bigOwn])
    assert.is_true(counts[bigForeign] <= 600, counts[bigForeign])
    -- 1 + 1000 own rows (5 a page after the first) and 1 + 600 foreign rows.
    assert.equal(320, m.right.pages)
    assert.equal(ns.BookView.dateText(T + 5000 * DAY, 0), m.right.rows[2].date)
    m = view.build(sit(fake), { inn = 5101, innPage = 200 })
    assert.equal(ns.BookView.dateText(T + 4001 * DAY, 0), m.right.rows[6].date)
    m = view.build(sit(fake), { inn = 5101, innPage = 201 })
    assert.equal("heading", m.right.rows[1].kind)
    assert.equal(ns.BookView.dateText(T + 5000 * DAY, 0), m.right.rows[2].date)
    m = view.build(sit(fake), { inn = 5101, innPage = 320 })
    assert.equal(ns.BookView.dateText(T + 4401 * DAY, 0), m.right.rows[#m.right.rows].date)
  end)

  it("keeps the newest 600 travelers' entries over the whole group", function()
    -- 5001 answers the even days, its alias 5003 the odd ones: 1 200 in all.
    local lists = { [5001] = {}, [5003] = {} }
    for i = 1, 1200 do
      local id = i % 2 == 0 and 5001 or 5003
      local list = lists[id]
      list[#list + 1] = { signer = traveler(i), name = "Mira",
        entry = { inn = id, t = T + i * DAY, phrase = { 2 } } }
    end
    local fake = { readOnly = false, own = function() return {} end,
      innEntries = function(_, id) return { own = {}, foreign = lists[id] } end }
    local view = newView()
    local m = view.build(sit(fake), { inn = 5001, innPage = 2 })
    -- Hy, note, Ht and 600 rows: 3 + 3 on page 1, then 5 a page after the repeated heading.
    assert.equal(121, m.right.pages)
    assert.equal(date(T + 1197 * DAY), m.right.rows[2].date)
    m = view.build(sit(fake), { inn = 5001, innPage = 121 })
    assert.equal(date(T + 601 * DAY), m.right.rows[#m.right.rows].date)
  end)

  it("shows a faded line for a phrase that won't render, and every kind of seal", function()
    local ledger = newLedger()
    assert.equal("added", ledger:addOwn({ inn = 5001, t = T, phrase = { 1 }, seal = 2 }))
    assert.equal("added", ledger:addOwn({ inn = 5001, t = T + WEEK, phrase = { 2 }, seal = 99 }))
    addTraveler(ledger, traveler(1), "Mira", 5001, T, 104, { 3 })
    local m = newView().build(sit(ledger), { inn = 5001 })
    assert.same({ kind = "own", date = date(T + WEEK), text = "Rest well.",
      seal = "Sealed with a seal" }, m.right.rows[2])
    assert.same({ kind = "own", date = date(T), text = "The ink here has faded.",
      seal = "Sealed with Last seal" }, m.right.rows[3])
    assert.same({ kind = "foreign", name = "Mira", date = date(T),
      text = "The ink here has faded.", seal = "Sealed with Ridge seal" }, m.right.rows[5])
  end)

  it("shows a traveler whose name isn't plain text as a traveler", function()
    local fake = { readOnly = false, own = function() return {} end,
      innEntries = function()
        return { own = {}, foreign = {
          { signer = traveler(1), name = "Mi|cffff0000ra", entry = { inn = 5001, t = T,
            phrase = { 2 } } },
          { signer = traveler(2), name = "Zo\195", entry = { inn = 5001, t = T + 1,
            phrase = { 2 } } },
          { signer = traveler(3), name = nil, entry = { inn = 5001, t = T + 2, phrase = { 2 } } },
          { signer = traveler(4), name = string.rep("x", 80), entry = { inn = 5001, t = T + 3,
            phrase = { 2 } } },
        } }
      end }
    local m = newView({ sizes = { innRows = 10 } }).build(sit(fake), { inn = 5101 })
    local names = {}
    for _, r in ipairs(m.right.rows) do
      if r.kind == "foreign" then
        names[#names + 1] = r.name
      end
    end
    assert.same({ string.rep("x", 64) .. "...", "A traveler", "A traveler", "A traveler" },
      names)
  end)

  it("draws the quill's flourish under own rows only, none for the plain quill", function()
    local ledger = ledgerE()
    addTraveler(ledger, traveler(1), "Mira", 5001, T)
    local view = newView({ catalog = catalogPlus() })
    local function rowsWith(quill)
      return view.build(sit(ledger, { quill = quill }), { inn = 5001 }).right.rows
    end
    for _, r in ipairs(rowsWith(1001)) do
      assert.equal(r.kind == "own" and FLOURISHES[1] or nil, r.flourish)
    end
    assert.equal(FLOURISHES[2], rowsWith(1002)[2].flourish)
    assert.equal(FLOURISHES[3], rowsWith(1003)[2].flourish)
    assert.equal(FLOURISHES[1], rowsWith(1005)[2].flourish) -- the fifth quill wraps
    for _, quill in ipairs({ 0, 1004, 1, 9999, 0 / 0, "1001" }) do
      assert.is_nil(rowsWith(quill)[2].flourish, tostring(quill))
    end
  end)

  it("skips anything a hostile ledger hands back", function()
    local cases = {
      function() error("raised on purpose") end,
      function() return nil end,
      function() return "x" end,
      function() return { own = "x", foreign = 7 } end,
      function() return { own = { 1, "x", true }, foreign = { 1, "x", {} } } end,
      function()
        return { own = { { inn = 5001, t = 5, phrase = { 2 } }, { inn = 5001 } },
          foreign = { { signer = traveler(1), entry = { inn = 5001, t = T, phrase = { 2 },
            extra = 1 } }, { signer = 7, entry = { inn = 5001, t = T, phrase = { 2 } } },
            { signer = traveler(2), entry = "x" } } }
      end,
      function() return fx.hostileTable() end,
      function() return { own = fx.hostileTable(), foreign = fx.hostileTable() } end,
    }
    for i, innEntries in ipairs(cases) do
      local fake = { readOnly = false, own = function() return {} end, innEntries = innEntries }
      local m = newView().build(sit(fake), { inn = 5001 })
      assert.is_nil(m.error, i)
      assert.same({
        { kind = "heading", text = "Your signatures" },
        { kind = "note", text = "You haven't signed this guestbook yet." },
        { kind = "heading", text = "Travelers' signatures" },
        { kind = "note", text = "No traveler you've met has signed here yet." },
      }, m.right.rows, i)
    end
  end)
end)

describe("BookView: no ledger and a read-only ledger", function()
  it("shows the list unsigned, the title page by default, and the notice", function()
    local m = newView().build(sit(nil), {})
    assert.equal(TEXT.noLedger, m.notice)
    assert.equal("title", m.left.kind)
    m = newView().build(sit(nil), { listPage = 1, inn = 5001 })
    for _, r in ipairs(m.left.rows) do
      if r.kind == "inn" then
        assert.is_true(r.faded)
      end
    end
    assert.equal("Not signed yet", m.right.countText)
    for _, tab in ipairs({ "collection", "cosmetics", "share" }) do
      local t = newView().build(sit(nil), { tab = tab })
      assert.is_nil(t.error)
      assert.equal(TEXT.noLedger, t.notice)
    end
    local c = newView().build(sit(nil), { tab = "collection" })
    assert.equal("0 of 4 inns signed", c.left.signedText)
    assert.equal("Signatures: 0", c.left.signaturesText)
  end)

  it("shows a read-only ledger in full, with the notice", function()
    local data = { schema = 99, me = {}, own = { { inn = 5001, t = T, phrase = { 2 } } },
      travelers = {}, earned = {}, quarantine = {} }
    local ledger = newLedger(data)
    assert.is_true(ledger.readOnly)
    local m = newView().build(sit(ledger), { inn = 5001 })
    assert.equal(TEXT.readOnly, m.notice)
    assert.equal("Signed once", m.right.countText)
    assert.equal("own", m.right.rows[2].kind)
    assert.is_nil(newView().build(sit(newLedger()), {}).notice)
  end)
end)

describe("BookView: the Collection tab", function()
  it("sums up the Alliance's passport", function()
    local ledger = ledgerE()
    addTraveler(ledger, traveler(1), "Mira", 5001, T)
    addTraveler(ledger, traveler(2), "Bram", 5201, T)
    local m = newView().build(sit(ledger), { tab = "collection" })
    assert.same({
      kind = "summary",
      signedText = "4 of 4 inns signed",
      zonesText = "Zones completed: 3 of 3",
      signaturesText = "Signatures: 7",
      travelersText = "Travelers met: 2",
      bars = {
        { name = "East", signed = 3, total = 3, fraction = 1, text = "3 of 3" },
        { name = "West", signed = 1, total = 1, fraction = 1, text = "1 of 1" },
      },
      page = 1, pages = 1,
    }, m.left)
  end)

  it("sums up the Horde's", function()
    local m = newView().build(sit(ledgerE(), { faction = "Horde" }), { tab = "collection" })
    assert.equal("2 of 4 inns signed", m.left.signedText)
    assert.equal("Zones completed: 1 of 3", m.left.zonesText)
    assert.same({
      { name = "East", signed = 1, total = 1, fraction = 1, text = "1 of 1" },
      { name = "West", signed = 1, total = 3, fraction = 1 / 3, text = "1 of 3" },
    }, m.left.bars)
  end)

  local function fourContinents()
    local inns, zones, conts = {}, {}, {}
    for i = 1, 4 do
      conts[i] = { name = "Land " .. string.char(68 - i) } -- Land C, B, A, @
      zones[10 + i] = { name = "Zone " .. i, continent = i, seal = 100 + i }
      inns[5000 + i] = { name = "Inn " .. i, zone = 10 + i }
    end
    conts[4].name = "Land D"
    return inns, zones, conts
  end

  it("pages the continent bars", function()
    local view = newView({ places = fourContinents, sizes = { barRows = 3 } })
    local m = view.build(sit(newLedger()), { tab = "collection" })
    local names = {}
    for _, b in ipairs(m.left.bars) do
      names[#names + 1] = b.name
    end
    assert.same({ "Land A", "Land B", "Land C" }, names)
    assert.same({ 1, 2 }, { m.left.page, m.left.pages })
    m = view.build(sit(newLedger()), { tab = "collection", barPage = 2 })
    assert.same({ { name = "Land D", signed = 0, total = 1, fraction = 0, text = "0 of 1" } },
      m.left.bars)
  end)

  it("shows zeros when counts raises or answers junk", function()
    for _, counts in ipairs({
      function() error("raised on purpose") end,
      function() return "x" end,
      function() return { own = -1, travelers = 0 / 0 } end,
      function() return { own = 1e8, travelers = "2" } end,
      function() return fx.hostileTable() end,
    }) do
      local real = ledgerE()
      local fake = { readOnly = false, own = function() return real:own() end, counts = counts }
      local m = newView().build(sit(fake), { tab = "collection" })
      assert.equal("Signatures: 0", m.left.signaturesText)
      assert.equal("Travelers met: 0", m.left.travelersText)
      assert.equal("4 of 4 inns signed", m.left.signedText)
    end
  end)

  it("is empty without inns", function()
    local view = newView({ places = function() return {}, {}, {} end })
    local m = view.build(sit(ledgerE()), { tab = "collection" })
    assert.same({}, m.left.bars)
    assert.equal(TEXT.noInns, m.left.empty)
    assert.equal("0 of 0 inns signed", m.left.signedText)
    assert.same({ kind = "stamps", cells = {}, empty = TEXT.noInns, page = 1, pages = 1 }, m.right)
  end)

  it("stamps the open inns, each continent on its own page", function()
    local m = newView().build(sit(ledgerE()), { tab = "collection" })
    assert.same({ kind = "stamps", title = "East", cells = {
      { key = 5101, name = "Marsh Inn", signed = true, date = date(T + 400) },
      { key = 5002, name = "Hill Inn", signed = true, date = date(T + 300) },
      { key = 5001, name = "Vale Inn", signed = true, date = date(T) },
    }, page = 1, pages = 2 }, m.right)
    m = newView().build(sit(ledgerE(), { faction = "Horde" }), { tab = "collection",
      stampPage = 2 })
    assert.same({ kind = "stamps", title = "West", cells = {
      { key = 5201, name = "Dune Inn", signed = true, date = date(T + 100) },
      { key = 5202, name = "Oasis Inn", signed = false },
      { key = 5301, name = "Ridge Inn", signed = false },
    }, page = 2, pages = 2 }, m.right)
  end)

  it("splits a continent past the cells, and starts the next one on a new page", function()
    local function places()
      return {
        [5001] = { name = "Inn A", zone = 10 }, [5002] = { name = "Inn B", zone = 10 },
        [5003] = { name = "Inn C", zone = 10 }, [5004] = { name = "Inn D", zone = 11 },
        [5101] = { name = "Inn E", zone = 20 },
      }, {
        [10] = { name = "Vale", continent = 1, seal = 101 },
        [11] = { name = "Wold", continent = 1, seal = 102 },
        [20] = { name = "Dunes", continent = 2, seal = 103 },
      }, { [1] = { name = "East" }, [2] = { name = "West" } }
    end
    local view = newView({ places = places, sizes = { stampCells = 3 } })
    local function cells(page)
      local m = view.build(sit(newLedger()), { tab = "collection", stampPage = page })
      local out = { m.right.title }
      for _, c in ipairs(m.right.cells) do
        out[#out + 1] = c.name
      end
      assert.equal(3, m.right.pages)
      return out
    end
    assert.same({ "East", "Inn A", "Inn B", "Inn C" }, cells(1))
    assert.same({ "East", "Inn D" }, cells(2))
    assert.same({ "West", "Inn E" }, cells(3))
  end)
end)

describe("BookView: the Cosmetics tab", function()
  it("falls back to the plain quill for anything not an unlocked quill", function()
    local view = newView({ catalog = catalogPlus() })
    local ledger = ledgerE()
    local u = NS.Cosmetics.bind(NS.Collection.bind(fx.places()), catalogPlus())
      .unlocked(ledger:own(), "Alliance", nil)
    assert.equal(1001, view.effectiveQuill(1001, u))
    assert.equal(1005, view.effectiveQuill(1005, u))
    assert.equal(0, view.effectiveQuill(nil, u))
    for i, quill in ipairs({ 0, 1004, 1, 101, 9999, 0 / 0, 1.5, "1001", fx.hostileProxy(),
      fx.hostileTable() }) do
      assert.equal(0, view.effectiveQuill(quill, u), i)
    end
    assert.equal(0, view.effectiveQuill(1001, nil))
    for _, list in ipairs({ "x", {}, fx.hostileTable(), { { id = "1001", t = T } } }) do
      assert.equal(0, view.effectiveQuill(1001, list))
    end
  end)

  local function quills(m)
    local out = {}
    for _, r in ipairs(m.left.rows) do
      out[#out + 1] = r
    end
    return out
  end

  it("lists the plain quill first, then each quill with its status", function()
    local view = newView({ catalog = catalogPlus() })
    local m = view.build(sit(ledgerE(), { quill = 1002 }), { tab = "cosmetics" })
    assert.equal("quills", m.left.kind)
    assert.equal(TEXT.quillsTitle, m.left.title)
    assert.same({
      { id = 0, name = "Plain quill", unlocked = true, chosen = false, canUse = true,
        status = "Always yours" },
      { id = 1001, name = "Long quill", unlocked = true, chosen = false, canUse = true,
        status = "Earned " .. date(T + 300) },
      { id = 1002, name = "Blue quill", unlocked = true, chosen = true, canUse = false,
        status = "In use" },
      { id = 1003, name = "Red quill", unlocked = true, chosen = false, canUse = true,
        status = "Earned " .. date(T + 400) },
      { id = 1004, name = "Grand quill", unlocked = false, chosen = false, canUse = false,
        status = "Sign 10 inns \194\183 4 of 10" },
      { id = 1005, name = "Plain grey quill", unlocked = true, chosen = false, canUse = true,
        status = "Earned " .. date(T) },
    }, quills(m))
  end)

  it("draws with the plain quill for a saved locked quill; Use off when read-only", function()
    local view = newView({ catalog = catalogPlus() })
    local m = view.build(sit(ledgerE(), { quill = 1004, prefsWritable = false }),
      { tab = "cosmetics" })
    local rows = quills(m)
    assert.is_true(rows[1].chosen)
    assert.equal("In use", rows[1].status)
    for _, r in ipairs(rows) do
      assert.is_false(r.canUse)
    end
    for _, w in ipairs({ false, 1, "true", fx.hostileProxy() }) do
      local s = sit(ledgerE())
      s.prefsWritable = w
      assert.is_false(quills(view.build(s, { tab = "cosmetics" }))[2].canUse)
      s.prefsWritable = nil
      assert.is_false(quills(view.build(s, { tab = "cosmetics" }))[2].canUse)
    end
  end)

  it("pages the quills", function()
    local view = newView({ catalog = catalogPlus(), sizes = { quillRows = 3 } })
    local m = view.build(sit(ledgerE()), { tab = "cosmetics", quillPage = 2 })
    local ids = {}
    for _, r in ipairs(m.left.rows) do
      ids[#ids + 1] = r.id
    end
    assert.same({ 1003, 1004, 1005 }, ids)
    assert.same({ 2, 2 }, { m.left.page, m.left.pages })
  end)

  local function sealCatalog()
    local c = fx.catalog()
    c[3] = { kind = "seal", name = "Zones seal", rule = { kind = "zones", n = 5 } }
    c[4] = { kind = "seal", name = "Land seal", rule = { kind = "continent" } }
    return c
  end

  local function seals(m)
    local out = {}
    for _, r in ipairs(m.right.rows) do
      out[#out + 1] = r.id .. " " .. r.name .. " | " .. r.status
        .. (r.earned and " +" or "")
    end
    return out
  end

  it("lists earned seals with dates and locked ones with each rule's progress", function()
    local ledger = newLedger()
    assert.equal("added", ledger:addOwn({ inn = 5001, t = T, phrase = { 2 } }))
    local m = newView({ catalog = sealCatalog(), sizes = { sealRows = 10 } })
      .build(sit(ledger), { tab = "cosmetics" })
    assert.equal(TEXT.sealHint, m.right.hint)
    local d = " \194\183 "
    assert.same({
      "1 First seal | Sign 2 inns" .. d .. "1 of 2",
      "2 Last seal | Sign every inn open to you" .. d .. "1 of 4",
      "3 Zones seal | Complete 5 zones" .. d .. "0 of 5",
      "4 Land seal | Sign every inn on one continent" .. d .. "1 of 3",
      "101 Vale seal | Sign every inn in Vale" .. d .. "1 of 2",
      "102 Marsh seal | Sign every inn in Marsh" .. d .. "0 of 1",
      "103 Dunes seal | Sign every inn in Dunes" .. d .. "0 of 1",
    }, seals(m))
    -- With more signed, the earned ones show their date.
    m = newView({ catalog = sealCatalog(), sizes = { sealRows = 10 } })
      .build(sit(ledgerE()), { tab = "cosmetics" })
    assert.same({
      "1 First seal | Earned " .. date(T + 100) .. " +",
      "2 Last seal | Earned " .. date(T + 400) .. " +",
      "3 Zones seal | Complete 5 zones" .. d .. "3 of 5",
      "4 Land seal | Earned " .. date(T + 400) .. " +",
      "101 Vale seal | Earned " .. date(T + 300) .. " +",
      "102 Marsh seal | Earned " .. date(T + 400) .. " +",
      "103 Dunes seal | Earned " .. date(T + 100) .. " +",
    }, seals(m))
  end)

  it("caps progress at the goal and picks the continent nearest done", function()
    local d = deps({ catalog = sealCatalog(), sizes = { sealRows = 10 } })
    local real = d.cosmetics
    d.cosmetics = { catalog = real.catalog, info = real.info,
      unlocked = function() return {} end }
    local m = BookView.new(d).build(sit(ledgerE()), { tab = "cosmetics" })
    local dot = " \194\183 "
    local lines = seals(m)
    assert.equal("1 First seal | Sign 2 inns" .. dot .. "2 of 2", lines[1])
    assert.equal("2 Last seal | Sign every inn open to you" .. dot .. "4 of 4", lines[2])
    assert.equal("4 Land seal | Sign every inn on one continent" .. dot .. "3 of 3", lines[4])
    -- West done (1 of 1) beats East half done.
    local ledger = newLedger()
    assert.equal("added", ledger:addOwn({ inn = 5001, t = T, phrase = { 2 } }))
    assert.equal("added", ledger:addOwn({ inn = 5201, t = T, phrase = { 2 } }))
    lines = seals(BookView.new(d).build(sit(ledger), { tab = "cosmetics" }))
    assert.equal("4 Land seal | Sign every inn on one continent" .. dot .. "1 of 1", lines[4])
    -- Nothing signed: the tie goes to the smaller continent key (East, 0 of 1).
    lines = seals(BookView.new(d).build(sit(newLedger(), { faction = "Horde" }),
      { tab = "cosmetics" }))
    assert.equal("4 Land seal | Sign every inn on one continent" .. dot .. "0 of 1", lines[4])
    -- No inn known: no continent at all.
    local empty = deps({ places = function() return {}, {}, {} end, catalog = sealCatalog() })
    empty.cosmetics = { catalog = empty.cosmetics.catalog, info = empty.cosmetics.info,
      unlocked = function() return {} end }
    lines = seals(BookView.new(empty).build(sit(newLedger()), { tab = "cosmetics" }))
    assert.equal("4 Land seal | Sign every inn on one continent" .. dot .. "0 of 1", lines[4])
    assert.equal("2 Last seal | Sign every inn open to you" .. dot .. "0 of 0", lines[2])
  end)

  it("leaves out another faction's zone seal unless it's earned", function()
    local view = newView({ sizes = { sealRows = 10 } })
    local function ids(ledger)
      local out = {}
      for _, r in ipairs(view.build(sit(ledger), { tab = "cosmetics" }).right.rows) do
        out[#out + 1] = r.id
      end
      return out
    end
    assert.same({ 1, 2, 101, 102, 103 }, ids(newLedger()))
    local ledger = newLedger()
    assert.equal("added", ledger:addOwn({ inn = 5001, t = T, phrase = { 2 } }))
    assert.is_true(ledger:markEarned(104, T))
    assert.same({ 1, 2, 101, 102, 103, 104 }, ids(ledger))
    local row = view.build(sit(ledger), { tab = "cosmetics" }).right.rows[6]
    assert.same({ id = 104, name = "Ridge seal", earned = true, status = "Earned " .. date(T) },
      row)
  end)

  it("pages the seals", function()
    local view = newView({ sizes = { sealRows = 3 } })
    local m = view.build(sit(newLedger()), { tab = "cosmetics", sealPage = 2 })
    assert.same({ 2, 2 }, { m.right.page, m.right.pages })
    assert.equal(2, #m.right.rows)
  end)

  it("ignores any kind but quill and seal", function()
    local d = deps()
    local real = d.cosmetics
    d.cosmetics = { info = real.info, unlocked = real.unlocked, catalog = function()
      local c = real.catalog()
      c[#c + 1] = { id = 1101, kind = "ink", name = "Blue ink", rule = { kind = "inns", n = 1 } }
      c[#c + 1] = { id = 1201, kind = "badge", name = "Badge", rule = { kind = "inns", n = 1 } }
      c[#c + 1] = "junk"
      c[#c + 1] = { id = "x", kind = "quill" }
      return c
    end }
    local m = BookView.new(d).build(sit(ledgerE()), { tab = "cosmetics" })
    for _, r in ipairs(m.left.rows) do
      assert.is_true(r.id == 0 or (r.id >= 1001 and r.id <= 1003), r.id)
    end
    for _, r in ipairs(m.right.rows) do
      assert.is_true(r.id < 1000)
    end
    assert.equal(4, #m.left.rows)
  end)
end)

describe("BookView: the Share tab", function()
  it("builds the Share page and its nudge", function()
    local ledger = ledgerE()
    local view = newView()
    local m = view.build(sit(ledger), { tab = "share" })
    assert.same({ kind = "share", title = TEXT.shareTitle, help = TEXT.shareHelp,
      include = TEXT.include }, m.left)
    assert.same({ kind = "shareInfo", title = TEXT.shareInfoTitle, text = TEXT.shareInfoText },
      m.right)
    local u = NS.Cosmetics.bind(NS.Collection.bind(fx.places()), fx.catalog())
      .unlocked(ledger:own(), "Alliance", ledger:earned())
    local shared = BookView.snapshot(ledger:own(), u)
    m = view.build(sit(ledger, { shared = shared }), { tab = "share" })
    assert.equal(TEXT.nothingNew, m.left.nudge)
    shared.own = 6
    m = view.build(sit(ledger, { shared = shared }), { tab = "share" })
    assert.equal(TEXT.newOne, m.left.nudge)
  end)

  it("snapshots the own entries and the unlocks", function()
    local ledger = ledgerE()
    local u = { { id = 1, t = T }, { id = 2, t = T } }
    assert.same({ own = 7, newest = T + WEEK, unlocked = 2 }, BookView.snapshot(ledger:own(), u))
    assert.same({ own = 0, unlocked = 0 }, BookView.snapshot({}, {}))
    assert.same({ own = 0, unlocked = 0 }, BookView.snapshot("x", 7))
    assert.same({ own = 2, newest = T, unlocked = 0 },
      BookView.snapshot({ { t = T }, "junk", nil, { t = T + 5 } }, fx.hostileTable()))
    assert.same({ own = 0, unlocked = 0 }, BookView.snapshot(fx.hostileProxy(), nil))
  end)

  it("compares snapshots for the nudge", function()
    local nudge = BookView.nudge
    local now = { own = 7, newest = T + WEEK, unlocked = 4 }
    assert.is_nil(nudge(nil, now))
    assert.equal(TEXT.nothingNew, nudge({ own = 7, newest = T + WEEK, unlocked = 4 }, now))
    assert.equal(TEXT.newOne, nudge({ own = 6, newest = T, unlocked = 4 }, now))
    assert.equal("3 new signatures since you last shared.",
      nudge({ own = 4, newest = T, unlocked = 2 }, now))
    assert.equal(TEXT.changed, nudge({ own = 7, newest = T + WEEK, unlocked = 3 }, now))
    assert.equal(TEXT.changed, nudge({ own = 8, newest = T + WEEK, unlocked = 4 }, now))
    assert.equal(TEXT.changed, nudge({ own = 7, newest = T, unlocked = 4 }, now))
    for _, bad in ipairs({
      { own = 0, newest = T, unlocked = 0 },
      { own = 0 / 0, unlocked = 0 },
      { own = -1, unlocked = 0 },
      { own = 1, newest = T, unlocked = 10000 },
      { own = 1, unlocked = 0 },
      { own = 1, newest = 5, unlocked = 0 },
      "x", fx.hostileTable(), fx.hostileProxy(),
    }) do
      assert.is_nil(nudge(bad, now))
    end
    assert.is_nil(nudge(now, "x"))
  end)
end)

describe("BookView: the saved record", function()
  local readPrefs = BookView.readPrefs
  local shared = { own = 7, newest = T, unlocked = 4 }

  it("reads what a v1 record holds and nothing else", function()
    assert.same({ writable = true }, readPrefs(nil))
    assert.same({ writable = false }, readPrefs("x"))
    assert.same({ writable = false }, readPrefs(7))
    assert.same({ writable = false }, readPrefs({ v = 2, quill = 1001 }))
    assert.same({ writable = false }, readPrefs({ v = 1e300, quill = 1001 }))
    assert.same({ quill = 1001, shared = shared, writable = true },
      readPrefs({ v = 1, quill = 1001, shared = { own = 7, newest = T, unlocked = 4, x = 1 } }))
    assert.same({ writable = true }, readPrefs({ v = 1, quill = "1001" }))
    assert.same({ writable = true }, readPrefs({ v = 1, quill = 0 }))
    assert.same({ writable = true }, readPrefs({ v = 1, shared = { own = 1 } }))
    assert.same({ writable = true }, readPrefs({ v = 1, shared = { own = 0, unlocked = 0,
      newest = T } }))
    assert.same({ shared = { own = 0, unlocked = 0 }, writable = true },
      readPrefs({ v = 1, shared = { own = 0, unlocked = 0 } }))
    assert.same({ writable = true }, readPrefs({}))
    assert.same({ writable = true }, readPrefs({ v = "1", quill = 1001 }))
    assert.same({ writable = true }, readPrefs({ v = 0 }))
    assert.same({ writable = true }, readPrefs({ v = 1.5 }))
    assert.same({ writable = false }, readPrefs(fx.hostileProxy()))
    assert.same({ writable = true }, readPrefs(fx.hostileTable()))
  end)

  it("writes a fresh v1 record of the known fields", function()
    local s = { own = 7, newest = T, unlocked = 4 }
    local rec = BookView.prefsRecord(1001, s)
    assert.same({ v = 1, quill = 1001, shared = s }, rec)
    assert.is_false(rawequal(rec.shared, s))
    assert.same({ v = 1 }, BookView.prefsRecord(nil, nil))
    assert.same({ v = 1 }, BookView.prefsRecord(0, { own = 1 }))
    assert.same({ v = 1 }, BookView.prefsRecord("1001", "x"))
    assert.same({ v = 1, shared = { own = 0, unlocked = 0 } },
      BookView.prefsRecord(0 / 0, { own = 0, unlocked = 0, extra = true }))
  end)
end)

describe("BookView: safety walks", function()
  -- Every page of every tab, for a view and a situation.
  local function everyModel(view, s, inn, fn)
    for _, tab in ipairs({ "inns", "collection", "cosmetics", "share" }) do
      local nav = { tab = tab, inn = inn, listPage = 0, innPage = 1, barPage = 1,
        stampPage = 1, quillPage = 1, sealPage = 1 }
      for _ = 1, 50 do
        local m = view.build(s, nav)
        assert.is_nil(m.error)
        fn(m)
        local moved = false
        for _, side in ipairs({ "left", "right" }) do
          local page = m[side]
          local field = ({ title = "listPage", list = "listPage", summary = "barPage",
            quills = "quillPage", inn = "innPage", stamps = "stampPage",
            seals = "sealPage" })[page.kind]
          if field and page.page < page.pages then
            nav = m.nav
            nav[field] = page.page + 1
            moved = true
          end
        end
        if not moved then
          break
        end
      end
    end
  end

  local function clean(m)
    for _, str in ipairs(strings(m)) do
      assert.is_nil(str:find("|", 1, true), str)
      assert.is_nil(str:find("%", 1, true), str)
    end
  end

  it("puts no pipe and no percent sign in any model over F or the real data", function()
    local ledger = ledgerE()
    addTraveler(ledger, traveler(1), "Mi\195\177a", 5001, T, 101)
    for _, quill in ipairs({ 1001, 0 }) do
      local view = newView({ sizes = { listRows = 3, innRows = 3, barRows = 3, stampCells = 3,
        quillRows = 3, sealRows = 3 } })
      everyModel(view, sit(ledger, { quill = quill }), 5001, clean)
    end
    local real = REAL.BookView.new({ inns = REAL.Data.Inns, atlas = REAL.Collection.atlas,
      phrase = REAL.Phrase, cosmetics = REAL.Cosmetics })
    local rl = REAL.Ledger.new({}, { guid = OWNER, name = "Aldric" }, ANCHOR)
    assert.equal("added", rl:addOwn({ inn = 254089, t = T, phrase = { 101 }, seal = nil }))
    everyModel(real, sit(rl), 254089, clean)
    everyModel(real, sit(nil), nil, clean)
  end)

  it("keeps every constant line free of escapes, format codes and addresses", function()
    local lines = strings(TEXT)
    for _, f in ipairs(FLOURISHES) do
      lines[#lines + 1] = f
      for i = 1, #f do
        assert.is_true(f:byte(i) < 128)
      end
    end
    assert.equal(12, #TEXT.months)
    for _, line in ipairs(lines) do
      for _, bad in ipairs({ "|", "%", "http", "www", "://" }) do
        assert.is_nil(line:lower():find(bad, 1, true), line)
      end
    end
  end)

  it("never raises or writes for hostile situation fields", function()
    local view = newView()
    local fields = { "ledger", "faction", "name", "offset", "quill", "shared", "prefsWritable" }
    for _, field in ipairs(fields) do
      for _, bad in ipairs(hostileValues()) do
        local ledger, data = ledgerE()
        local s = sit(ledger, { shared = { own = 1, newest = T, unlocked = 0 } })
        s[field] = bad
        local nav = { tab = "inns", inn = 5001, listPage = 1 }
        local before = { s = fx.snapshot(s), nav = fx.snapshot(nav), data = fx.snapshot(data, 6) }
        for _, tab in ipairs({ "inns", "collection", "cosmetics", "share" }) do
          nav.tab = tab
          before.nav = fx.snapshot(nav)
          local m = view.build(s, nav)
          assert.is_nil(m.error, field .. " " .. tab)
          assert.is_true(fx.sameSnapshot(before.s, fx.snapshot(s)), field)
          assert.is_true(fx.sameSnapshot(before.nav, fx.snapshot(nav)), field)
          assert.is_true(fx.sameSnapshot(before.data, fx.snapshot(data, 6)), field)
        end
      end
    end
    for _, s in ipairs(hostileValues()) do
      for _, tab in ipairs({ "inns", "collection", "cosmetics", "share" }) do
        local m = view.build(s, { tab = tab, inn = 5001 })
        assert.is_nil(m.error, tab)
      end
    end
  end)

  it("gives the error model when a dependency raises", function()
    local d = deps()
    d.atlas = { progress = function() error("raised on purpose") end, innOf = d.atlas.innOf,
      inn = d.atlas.inn, zone = d.atlas.zone, continent = d.atlas.continent }
    local m = BookView.new(d).build(sit(ledgerE()), { tab = "collection", barPage = 3 })
    assert.same({ tab = "inns", nav = { tab = "inns", innPage = 1, barPage = 1, stampPage = 1,
      quillPage = 1, sealPage = 1 }, error = true }, m)
    d = deps()
    d.cosmetics = { catalog = function() error("raised on purpose") end,
      unlocked = d.cosmetics.unlocked, info = d.cosmetics.info }
    local view = BookView.new(d)
    assert.equal(0, view.effectiveQuill(1001, {}))
    assert.is_true(view.build(sit(ledgerE()), { tab = "cosmetics" }).error)
  end)
end)
