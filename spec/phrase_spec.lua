-- Phrase: record rules, grammar, rendering, builder helpers, the real draft table and the
-- SyncProtocol hook (docs/specs/phrase.md, section 6). validIds is SyncProtocol's rule 16
-- hook, so its argument is hostile here: non-tables, metatables, holes, huge tables,
-- NaN and inf, and every wrong kind in every position.
local load = require("helpers.load")

-- A fresh ns: Ledger, then (unless noData) the data, then Phrase, as in the TOC.
-- `patch` may change Ledger before Phrase reads it.
local function modules(opts)
  opts = opts or {}
  local ns = {}
  load.file("Ledger.lua", ns, load.pure_env())
  if opts.patch then
    opts.patch(ns.Ledger)
  end
  if not opts.noData then
    load.file("Data/Phrases.lua", ns, load.pure_env())
  end
  load.file("Phrase.lua", ns, load.pure_env())
  return ns
end

local NS = modules()
local Phrase = NS.Phrase
local DATA, CATEGORIES, VOICES = NS.Data.Phrases, NS.Data.PhraseCategories, NS.Data.PhraseVoices

-- The spec 6 fixture.
local function fixture()
  return {
    [1] = { kind = "template", text = "Here's to {w}!" },
    [2] = { kind = "template", text = "Rest well." },
    [500] = { kind = "conj", text = "And then..." },
    [1000] = { kind = "word", cat = 1, text = "the hearth" },
    [1100] = { kind = "word", cat = 2, text = "hot stew" },
  }, { "Home", "Food" }
end

local function fixtureSet()
  return Phrase.bind(fixture())
end

local function contains(list, value)
  for _, v in ipairs(list) do
    if v == value then
      return true
    end
  end
  return false
end

local function raise()
  error("hidden value touched")
end

local HOSTILE_EVENTS = {
  "__index", "__newindex", "__len", "__eq", "__lt", "__le", "__concat", "__tostring",
  "__call", "__unm", "__add",
}

-- The two hidden-value stand-ins (sync-ledger.md 5.2).
local function hostileTable()
  local mt = {}
  for _, ev in ipairs(HOSTILE_EVENTS) do
    mt[ev] = raise
  end
  return setmetatable({}, mt)
end

local function hostileProxy()
  local u = newproxy(true)
  local mt = getmetatable(u)
  for _, ev in ipairs(HOSTILE_EVENTS) do
    mt[ev] = raise
  end
  return u
end

-- Values that are not a valid ID, in any position (spec 6.2).
local function badIds()
  return {
    1.5, "1", true, {}, 0 / 0, 1 / 0, -1 / 0, -1, 0, 10000, 2 ^ 53, 1e300,
    hostileTable(), hostileProxy(), function() end,
  }
end

-- A raw snapshot of t (NaN-aware, two levels), to show nothing was written.
local function snapshot(t, depth)
  depth = depth or 2
  if type(t) ~= "table" or depth == 0 then
    return { value = t }
  end
  local out = { ref = t, pairs = {} }
  for k, v in next, t do
    out.pairs[#out.pairs + 1] = { k = k, v = snapshot(v, depth - 1) }
  end
  return out
end

local function sameValue(a, b)
  return rawequal(a, b) or (a ~= a and b ~= b)
end

local function sameSnapshot(a, b)
  if a.pairs == nil or b.pairs == nil then
    return a.pairs == b.pairs and sameValue(a.value, b.value)
  end
  if not rawequal(a.ref, b.ref) or #a.pairs ~= #b.pairs then
    return false
  end
  for i = 1, #a.pairs do
    local x, y = a.pairs[i], b.pairs[i]
    if not sameValue(x.k, y.k) or not sameSnapshot(x.v, y.v) then
      return false
    end
  end
  return true
end

-- Deterministic pseudo-random numbers (Park-Miller; exact in doubles).
local function rng(seed)
  return function(n)
    seed = seed * 16807 % 2147483647
    return seed % n
  end
end

-- ---------------------------------------------------------------------------

describe("Phrase module", function()
  it("has the spec 3.5 constants", function()
    assert.equal("{w}", Phrase.SLOT)
    assert.same({
      idsMax = 5, idMax = 9999, templateBytes = 48, conjBytes = 16, wordBytes = 24,
      categoryBytes = 40, renderBytes = 160, voicesMax = 50,
    }, Phrase.LIMITS)
    assert.same({ template = { 1, 499 }, conj = { 500, 599 }, word = { 1000, 9999 }, block = 100 },
      Phrase.RANGES)
    assert.same({ t = true, TW = true, tCt = true, tCTW = true, TWCt = true, TWCTW = true },
      Phrase.SHAPES)
  end)

  it("reads idsMax and idMax from Ledger.LIMITS, not second literals", function()
    local ns = modules({ patch = function(L)
      L.LIMITS.phraseIdsMax = 3
      L.LIMITS.phraseIdMax = 1500
    end })
    assert.equal(3, ns.Phrase.LIMITS.idsMax)
    assert.equal(1500, ns.Phrase.LIMITS.idMax)
    assert.is_true(ns.Phrase.validIds({ 101, 503, 106 }))
    assert.is_false(ns.Phrase.validIds({ 102, 504, 4, 1101 })) -- 4 IDs, over idsMax
    assert.is_false(ns.Phrase.validIds({ 3, 1601 })) -- over idMax
  end)

  it("changing the exported constants changes nothing inside", function()
    local ns = modules()
    ns.Phrase.SHAPES.TT = true
    ns.Phrase.SHAPES.t = nil
    ns.Phrase.LIMITS.idsMax = 1
    ns.Phrase.SLOT = "x"
    assert.is_true(ns.Phrase.validIds({ 101 }))
    assert.is_false(ns.Phrase.validIds({ 3, 3 }))
    assert.is_true(ns.Phrase.validIds({ 3, 1201, 501, 11, 1002 }))
    assert.equal("Here's to old friends!", ns.Phrase.render({ 3, 1201 }))
  end)

  it("exposes the default set's twelve functions and invalid", function()
    for _, name in ipairs({ "validIds", "render", "compose", "kind", "text", "hasSlot",
      "templates", "conjunctions", "categories", "words", "voices", "voice" }) do
      assert.is_function(Phrase[name], name)
    end
    assert.same({}, Phrase.invalid)
  end)

  it("loads with no Data and rejects everything (fail closed)", function()
    local ns = modules({ noData = true })
    assert.is_false(ns.Phrase.validIds({ 101 }))
    assert.is_nil(ns.Phrase.render({ 101 }))
    assert.same({}, ns.Phrase.templates())
    assert.same({}, ns.Phrase.invalid)
  end)

  it("loads with a non-table ns.Data and rejects everything", function()
    local ns = {}
    load.file("Ledger.lua", ns, load.pure_env())
    ns.Data = "junk"
    load.file("Phrase.lua", ns, load.pure_env())
    assert.is_false(ns.Phrase.validIds({ 101 }))
  end)

  it("raises at load without Ledger (a packaging bug)", function()
    assert.has_error(function()
      load.file("Phrase.lua", {}, load.pure_env())
    end)
  end)
end)

-- ---------------------------------------------------------------------------
-- 6.1 bind and the record rules.

describe("Phrase.bind", function()
  it("binds the fixture with nothing invalid and lists its parts", function()
    local set = fixtureSet()
    assert.same({}, set.invalid)
    assert.same({ 1, 2 }, set.templates())
    assert.same({ 500 }, set.conjunctions())
    assert.same({ "Home", "Food" }, set.categories())
    assert.same({ 1000 }, set.words(1))
    assert.same({ 1100 }, set.words(2))
    assert.same({}, set.words(3))
    assert.same({}, set.words("1"))
    assert.same({}, set.words(nil))
    assert.same({}, set.words(0 / 0))
    assert.same({}, set.words(1.5))
    assert.same({}, set.words(hostileTable()))
  end)

  it("kind, text and hasSlot", function()
    local set = fixtureSet()
    assert.equal("template", set.kind(1))
    assert.equal("template", set.kind(2))
    assert.equal("conj", set.kind(500))
    assert.equal("word", set.kind(1000))
    assert.equal("Here's to {w}!", set.text(1)) -- a template keeps its slot
    assert.equal("Rest well.", set.text(2))
    assert.equal("And then...", set.text(500))
    assert.equal("hot stew", set.text(1100))
    assert.is_true(set.hasSlot(1))
    for _, id in ipairs({ 2, 500, 1000, 1100, 3, 999, 9999 }) do
      assert.is_false(set.hasSlot(id), tostring(id))
      if id ~= 2 and id ~= 500 and id ~= 1000 and id ~= 1100 then
        assert.is_nil(set.kind(id))
        assert.is_nil(set.text(id))
      end
    end
    for _, v in ipairs(badIds()) do
      assert.is_false(set.hasSlot(v))
      assert.is_nil(set.kind(v))
      assert.is_nil(set.text(v))
    end
    assert.is_false(set.hasSlot(nil))
    assert.is_nil(set.kind(nil))
    assert.is_nil(set.text(nil))
  end)

  -- A sequence that uses `id` and would be valid if its record were valid.
  local function useOf(id, v)
    local kind = type(v) == "table" and rawget(v, "kind") or nil
    if kind == "word" then
      return { 1, id }
    elseif kind == "conj" then
      return { 2, id, 2 }
    elseif kind == "template" and type(rawget(v, "text")) == "string"
      and rawget(v, "text"):find("{w}", 1, true) then
      return { id, 1000 }
    end
    return { id }
  end

  local T = function(text) return { kind = "template", text = text } end
  local C = function(text) return { kind = "conj", text = text } end
  local W = function(text, cat) return { kind = "word", cat = cat or 1, text = text } end

  -- Each spec 3.2 rule broken once: { label, key, value, invalid name }.
  local BROKEN = {
    { "key 0", 0, T("Rest easy."), "id 0" },
    { "key -1", -1, T("Rest easy."), "id -1" },
    { "key 2.5", 2.5, T("Rest easy."), "id 2.5" },
    { "key 10000", 10000, W("the fire"), "id 10000" },
    { "key inf", math.huge, W("the fire"), "id " .. tostring(math.huge) },
    { "key \"3\"", "3", T("Rest easy."), "id (string)" },
    { "key true", true, T("Rest easy."), "id (boolean)" },
    { "template at 600", 600, T("Rest easy."), "id 600" },
    { "template at 1001", 1001, T("Rest easy."), "id 1001" },
    { "conj at 50", 50, C("Even so..."), "id 50" },
    { "word at 499", 499, W("the fire"), "id 499" },
    { "word at 700", 700, W("the fire"), "id 700" },
    { "missing kind", 3, { text = "Rest easy." }, "id 3" },
    { "unknown kind", 3, { kind = "noun", text = "Rest easy." }, "id 3" },
    { "non-string kind", 3, { kind = 1, text = "Rest easy." }, "id 3" },
    { "missing text", 3, { kind = "template" }, "id 3" },
    { "non-string text", 3, { kind = "template", text = 5 }, "id 3" },
    { "an extra field", 3, { kind = "template", text = "Rest easy.", note = "x" }, "id 3" },
    { "cat on a template", 3, { kind = "template", text = "Rest easy.", cat = 1 }, "id 3" },
    { "word without cat", 1001, { kind = "word", text = "the fire" }, "id 1001" },
    { "cat = 0", 1001, W("the fire", 0), "id 1001" },
    { "cat = 3", 1001, W("the fire", 3), "id 1001" },
    { "cat = 1.5", 1001, W("the fire", 1.5), "id 1001" },
    { "cat = \"1\"", 1001, W("the fire", "1"), "id 1001" },
    { "text with |", 3, T("Rest |cffff0000well."), "id 3" },
    { "text with %", 3, T("Rest %s well."), "id 3" },
    { "text with \\", 3, T("Rest \\n well."), "id 3" },
    { "text with \\0", 3, T("Rest\0 well."), "id 3" },
    { "text with \\t", 3, T("Rest\twell."), "id 3" },
    { "text with a UTF-8 byte", 3, T("Rest w\195\169ll."), "id 3" },
    { "text with {", 3, T("Rest { well."), "id 3" },
    { "text with }", 3, T("Rest } well."), "id 3" },
    { "text with {W}", 3, T("Here's to {W}!"), "id 3" },
    { "text with {x}", 3, T("Here's to {x}!"), "id 3" },
    { "text with two {w}", 3, T("Here's to {w} and {w}!"), "id 3" },
    { "a word with {w}", 1001, W("the {w} fire"), "id 1001" },
    { "a conj with {w}", 501, C("And {w}..."), "id 501" },
    { "a word with |", 1001, W("the |fire"), "id 1001" },
    { "a conj with %", 501, C("And %d..."), "id 501" },
    { "a leading space", 3, T(" Rest easy."), "id 3" },
    { "a trailing space", 3, T("Rest easy. "), "id 3" },
    { "two spaces", 3, T("Rest  easy."), "id 3" },
    { "two spaces in a word", 1001, W("the  fire"), "id 1001" },
    { "an empty template", 3, T(""), "id 3" },
    { "an empty word", 1001, W(""), "id 1001" },
    { "an empty conj", 501, C(""), "id 501" },
    { "a template of 49 bytes", 3, T("A" .. ("a"):rep(47) .. "."), "id 3" },
    { "a template of 3 bytes", 3, T("Hi."), "id 3" },
    { "a word of 25 bytes", 1001, W(("a"):rep(25)), "id 1001" },
    { "a conj of 17 bytes", 501, C("A" .. ("a"):rep(13) .. "..."), "id 501" },
    { "a conj of 3 bytes", 501, C("..."), "id 501" },
    { "a template starting lowercase", 3, T("rest easy."), "id 3" },
    { "a template starting with {w}", 3, T("{w} was lovely."), "id 3" },
    { "a template starting with a digit", 3, T("3 cheers."), "id 3" },
    { "a template not ending in . ! ?", 3, T("Rest easy"), "id 3" },
    { "a template ending in ,", 3, T("Rest easy,"), "id 3" },
    { "a word starting uppercase", 1001, W("The fire"), "id 1001" },
    { "a word ending uppercase", 1001, W("the firE"), "id 1001" },
    { "a word starting with a digit", 1001, W("3 fires"), "id 1001" },
    { "a word ending with a digit", 1001, W("fire 3"), "id 1001" },
    { "a word ending in .", 1001, W("the fire."), "id 1001" },
    { "a conj starting lowercase", 501, C("and so..."), "id 501" },
    { "a conj not ending in ...", 501, C("And then."), "id 501" },
    { "a conj ending in ..", 501, C("And then.."), "id 501" },
    { "a value that's a string", 3, "Rest easy.", "id 3" },
    { "a value that's a number", 3, 5, "id 3" },
    { "a value that's a hostile table", 3, hostileTable(), "id 3" },
  }

  for _, case in ipairs(BROKEN) do
    local name, key, value, label = case[1], case[2], case[3], case[4]
    it("excludes " .. name, function()
      local data, cats = fixture()
      data[key] = value
      local set = Phrase.bind(data, cats)
      assert.same({ label }, set.invalid)
      assert.is_nil(set.kind(key))
      assert.is_nil(set.text(key))
      assert.is_false(set.hasSlot(key))
      local seq = useOf(key, value)
      assert.is_false(set.validIds(seq))
      assert.is_nil(set.render(seq))
      -- The rest of the fixture still binds.
      assert.is_true(set.validIds({ 1, 1000, 500, 2 }))
    end)
  end

  it("passes the boundary lengths and a minimal record of each kind", function()
    local data, cats = fixture()
    data[3] = { kind = "template", text = "A" .. ("a"):rep(46) .. "." } -- 48 bytes
    data[4] = { kind = "template", text = "Hey." } -- 4 bytes
    data[5] = { kind = "template", text = "Here's to " .. ("a"):rep(34) .. "{w}!" } -- 48
    data[501] = { kind = "conj", text = "A" .. ("a"):rep(12) .. "..." } -- 16 bytes
    data[502] = { kind = "conj", text = "A..." } -- 4 bytes
    data[1001] = { kind = "word", cat = 1, text = ("a"):rep(24) } -- 24 bytes
    data[1002] = { kind = "word", cat = 2, text = "a" } -- 1 byte
    data[1003] = { kind = "word", cat = 1, text = "a well-worn map, it's old! or? no" }
    local set = Phrase.bind(data, cats)
    assert.same({ "id 1003" }, set.invalid) -- 33 bytes: only the length fails
    data[1003] = { kind = "word", cat = 1, text = "a map, it's old! or? no" }
    set = Phrase.bind(data, cats)
    assert.same({}, set.invalid)
    assert.equal(48, #set.text(3))
    assert.equal(48, #set.text(5))
    assert.equal(16, #set.text(501))
    assert.equal(24, #set.text(1001))
    assert.is_true(set.validIds({ 3, 501, 5, 1001 }))
    assert.is_true(set.validIds({ 4, 502, 5, 1002 }))
    assert.same({ 1000, 1001, 1003 }, set.words(1))
  end)

  describe("categories", function()
    local function bindCats(cats)
      local data = fixture()
      return Phrase.bind(data, cats)
    end

    it("a hole at 2 keeps only category 1 and excludes the cat-2 word", function()
      local set = bindCats({ [1] = "Home", [3] = "Extra" })
      assert.same({ "Home" }, set.categories())
      assert.is_nil(set.kind(1100))
      assert.is_true(contains(set.invalid, "id 1100"))
      assert.is_true(contains(set.invalid, "category 3"))
      assert.equal(2, #set.invalid)
      assert.is_false(set.validIds({ 1, 1100 }))
      assert.is_true(set.validIds({ 1, 1000 }))
    end)

    for _, case in ipairs({
      { "a non-string name", 5 },
      { "an empty name", "" },
      { "a 41-byte name", "F" .. ("o"):rep(40) },
      { "a name with |", "Fo|od" },
      { "a name starting lowercase", "food" },
      { "a name with {w}", "Food {w}" },
      { "a name with a trailing space", "Food " },
      { "a hostile table name", hostileTable() },
    }) do
      it(case[1] .. " excludes that category, later ones and their words", function()
        local set = bindCats({ "Home", case[2], "Third" })
        assert.same({ "Home" }, set.categories())
        assert.is_nil(set.kind(1100))
        table.sort(set.invalid)
        assert.same({ "category 2", "category 3", "id 1100" }, set.invalid)
      end)
    end

    it("a 40-byte name passes", function()
      local name = "F" .. ("o"):rep(39)
      local set = bindCats({ "Home", name })
      assert.same({ "Home", name }, set.categories())
      assert.same({}, set.invalid)
    end)

    it("names a non-number category key by its type", function()
      local set = bindCats({ "Home", "Food", x = "Extra" })
      assert.same({ "category (string)" }, set.invalid)
      assert.same({ "Home", "Food" }, set.categories())
    end)

    it("reads at most 90 categories (one block of 100 IDs each)", function()
      local cats = {}
      for i = 1, 91 do
        cats[i] = "Category"
      end
      local set = bindCats(cats)
      assert.equal(90, #set.categories())
      assert.same({ "category 91" }, set.invalid)
    end)

    for _, bad in ipairs({ "nil", "a string", "a number" }) do
      it("categories that are " .. bad .. " give no category and exclude every word", function()
        local values = { ["nil"] = nil, ["a string"] = "Home", ["a number"] = 1 }
        local set = bindCats(values[bad])
        assert.same({}, set.categories())
        assert.same({}, set.words(1))
        table.sort(set.invalid)
        assert.same({ "id 1000", "id 1100" }, set.invalid)
        assert.is_true(set.validIds({ 2, 500, 2 }))
        assert.is_false(set.validIds({ 1, 1000 }))
      end)
    end
  end)

  for _, case in ipairs({ { "nil", nil }, { "\"x\"", "x" }, { "{}", {} }, { "5", 5 } }) do
    it("bind(" .. case[1] .. ") gives an empty set", function()
      local set = Phrase.bind(case[2])
      assert.same({}, set.invalid)
      assert.same({}, set.templates())
      assert.same({}, set.conjunctions())
      assert.same({}, set.categories())
      assert.same({}, set.words(1))
      for _, ids in ipairs({ { 1 }, { 2 }, { 1, 1000 }, { 101 }, { 3, 1201 } }) do
        assert.is_false(set.validIds(ids))
        assert.is_nil(set.render(ids))
      end
      assert.is_nil(set.compose(2))
      assert.is_nil(set.kind(1))
    end)
  end

  describe("voices", function()
    -- The fixture with voices: template 1 and conj 500 in voice 1, template 2 in voice 2,
    -- and template 3 with no voice.
    local function voiced(extra)
      local data, cats = fixture()
      data[1].voice = 1
      data[2].voice = 2
      data[500].voice = 1
      data[3] = { kind = "template", text = "Hello." }
      for k, v in pairs(extra or {}) do
        data[k] = v
      end
      return data, cats
    end

    it("binds the voices and lists templates and conjunctions per voice", function()
      local data, cats = voiced()
      local set = Phrase.bind(data, cats, { "Warm", "Gruff" })
      assert.same({}, set.invalid)
      assert.same({ "Warm", "Gruff" }, set.voices())
      assert.same({ 1, 2, 3 }, set.templates())
      assert.same({ 1, 2, 3 }, set.templates(nil))
      assert.same({ 1 }, set.templates(1))
      assert.same({ 2 }, set.templates(2))
      assert.same({ 500 }, set.conjunctions())
      assert.same({ 500 }, set.conjunctions(1))
      assert.same({}, set.conjunctions(2))
      assert.equal(1, set.voice(1))
      assert.equal(2, set.voice(2))
      assert.equal(1, set.voice(500))
      assert.is_nil(set.voice(3)) -- no voice
      assert.is_nil(set.voice(1000)) -- a word
      assert.is_nil(set.voice(4)) -- unknown
      -- A voice never changes what is valid.
      assert.is_true(set.validIds({ 3, 500, 1, 1000 }))
    end)

    it("returns {} for a voice that isn't bound, and nil for hostile IDs", function()
      local data, cats = voiced()
      local set = Phrase.bind(data, cats, { "Warm", "Gruff" })
      for _, v in ipairs({ 0, 3, -1, 1.5, "1", true, {}, 0 / 0, 1 / 0, hostileTable(),
        hostileProxy(), function() end }) do
        assert.same({}, set.templates(v))
        assert.same({}, set.conjunctions(v))
        assert.is_nil(set.voice(v))
      end
    end)

    for _, case in ipairs({
      { "voice 0", 0 }, { "voice 3 (beyond the list)", 3 }, { "voice 1.5", 1.5 },
      { "voice \"1\"", "1" }, { "voice NaN", 0 / 0 }, { "voice true", true },
    }) do
      it("excludes a template with " .. case[1], function()
        local data, cats = voiced({ [4] = { kind = "template", voice = case[2], text = "Bye." } })
        local set = Phrase.bind(data, cats, { "Warm", "Gruff" })
        assert.is_nil(set.kind(4))
        assert.same({ "id 4" }, set.invalid)
        assert.is_false(set.validIds({ 4 }))
      end)
    end

    it("excludes a word with a voice (not one of its fields)", function()
      local data, cats = voiced({ [1001] = { kind = "word", cat = 1, voice = 1, text = "tea" } })
      local set = Phrase.bind(data, cats, { "Warm", "Gruff" })
      assert.is_nil(set.kind(1001))
      assert.same({ "id 1001" }, set.invalid)
    end)

    it("a hole at 2 keeps only voice 1 and excludes the voice-2 template", function()
      local data, cats = voiced()
      local set = Phrase.bind(data, cats, { [1] = "Warm", [3] = "Extra" })
      assert.same({ "Warm" }, set.voices())
      assert.is_nil(set.kind(2))
      assert.is_true(contains(set.invalid, "id 2"))
      assert.is_true(contains(set.invalid, "voice 3"))
      assert.equal(2, #set.invalid)
    end)

    for _, case in ipairs({
      { "a non-string name", 5 }, { "an empty name", "" },
      { "a 41-byte name", "G" .. ("r"):rep(40) },
      { "a name with |", "Gr|uff" }, { "a name starting lowercase", "gruff" },
    }) do
      it("a bad voice name (" .. case[1] .. ") ends the list there", function()
        local data, cats = voiced()
        local set = Phrase.bind(data, cats, { "Warm", case[2] })
        assert.same({ "Warm" }, set.voices())
        assert.is_nil(set.kind(2))
        assert.is_true(contains(set.invalid, "id 2"))
        assert.is_true(contains(set.invalid, "voice 2"))
      end)
    end

    it("binds no voice when voices isn't a table, so voiced records are excluded", function()
      local cases = { n = 4, nil, "x", 7, true }
      for i = 1, cases.n do
        local data, cats = voiced()
        local set = Phrase.bind(data, cats, cases[i])
        assert.same({}, set.voices())
        assert.same({ 3 }, set.templates())
        assert.is_nil(set.kind(500))
      end
    end)

    it("stops reading names after voicesMax", function()
      local names = {}
      for i = 1, Phrase.LIMITS.voicesMax + 5 do
        names[i] = "Voice"
      end
      local data, cats = voiced()
      local set = Phrase.bind(data, cats, names)
      assert.equal(Phrase.LIMITS.voicesMax, #set.voices())
      assert.equal(5, #set.invalid)
    end)

    it("copies: changing a returned list or the names after bind changes nothing", function()
      local data, cats = voiced()
      local names = { "Warm", "Gruff" }
      local set = Phrase.bind(data, cats, names)
      names[1] = "Cold"
      set.voices()[2] = "x"
      set.templates(1)[1] = 99
      assert.same({ "Warm", "Gruff" }, set.voices())
      assert.same({ 1 }, set.templates(1))
    end)
  end)

  it("a data table with a metatable is read raw", function()
    local data, cats = fixture()
    setmetatable(data, { __index = function()
      return { kind = "template", text = "Hi there." }
    end })
    local set = Phrase.bind(data, cats)
    assert.same({}, set.invalid)
    assert.is_nil(set.kind(3))
    local hostile = hostileTable()
    local set2 = Phrase.bind(hostile, hostileTable())
    assert.same({}, set2.templates())
  end)

  it("copies: changing the data after bind changes no result", function()
    local data, cats = fixture()
    local set = Phrase.bind(data, cats)
    data[1].text = "Beware of {w}!"
    data[2] = nil
    data[3] = { kind = "template", text = "Rest easy." }
    data[1000].cat = 2
    cats[1] = "Changed"
    cats[3] = "Third"
    assert.equal("Here's to {w}!", set.text(1))
    assert.equal("Here's to the hearth!", set.render({ 1, 1000 }))
    assert.is_true(set.validIds({ 2 }))
    assert.is_nil(set.kind(3))
    assert.same({ 1000 }, set.words(1))
    assert.same({ "Home", "Food" }, set.categories())
  end)

  it("copies: changing a returned array changes the next call's result not at all", function()
    local set = fixtureSet()
    for _, get in ipairs({
      function() return set.templates() end,
      function() return set.conjunctions() end,
      function() return set.categories() end,
      function() return set.words(1) end,
    }) do
      local a = get()
      local before = { unpack(a) }
      a[1] = 42
      a[#a + 1] = 43
      local b = get()
      assert.are_not.equal(a, b)
      assert.same(before, b)
    end
    local tpl = set.templates()
    tpl[1] = 1000
    assert.is_true(set.validIds({ 1, 1000 }))
  end)
end)

-- ---------------------------------------------------------------------------
-- 6.2 validIds, render, compose.

describe("Phrase.validIds", function()
  local set = fixtureSet()

  local ACCEPTED = {
    { "t", { 2 } },
    { "TW", { 1, 1000 } },
    { "tCt", { 2, 500, 2 } },
    { "tCTW", { 2, 500, 1, 1100 } },
    { "TWCt", { 1, 1000, 500, 2 } },
    { "TWCTW", { 1, 1000, 500, 1, 1100 } },
  }

  for _, case in ipairs(ACCEPTED) do
    it("accepts the shape " .. case[1], function()
      local ids = case[2]
      local before = snapshot(ids)
      assert.is_true(rawequal(true, set.validIds(ids)))
      assert.is_true(sameSnapshot(before, snapshot(ids)))
    end)
  end

  -- { label, value } rejected cases; each value is built fresh by the function.
  local REJECTED = {
    { "nil", function() return nil end },
    { "a number", function() return 3 end },
    { "a string", function() return "1.1000" end },
    { "true", function() return true end },
    { "a function", function() return function() end end },
    { "a newproxy userdata", hostileProxy },
    { "the hostile table stand-in", hostileTable },
    { "a coroutine", function() return coroutine.create(function() end) end },
    { "{}", function() return {} end },
    { "6 IDs", function() return { 1, 1000, 500, 1, 1100, 2 } end },
    { "{[1] = 1, [3] = 1000}", function() return { [1] = 1, [3] = 1000 } end },
    { "{1, 1000, x = 1}", function() return { 1, 1000, x = 1 } end },
    { "{[0] = 2, 2}", function() return { [0] = 2, 2 } end },
    { "{2, [2.5] = 1}", function() return { 2, [2.5] = 1 } end },
    { "{[2] = 2}", function() return { [2] = 2 } end },
    { "{2, [-1] = 2}", function() return { 2, [-1] = 2 } end },
    { "{2, [true] = 2}", function() return { 2, [true] = 2 } end },
    { "unknown {3}", function() return { 3 } end },
    { "unknown {1, 1001}", function() return { 1, 1001 } end },
    { "unknown {9999}", function() return { 9999 } end },
    { "unknown {1, 999}", function() return { 1, 999 } end },
    { "a word first {1000}", function() return { 1000 } end },
    { "a word first {1000, 1}", function() return { 1000, 1 } end },
    { "a conj first", function() return { 500, 2 } end },
    { "a conj last", function() return { 2, 500 } end },
    { "a conj alone", function() return { 500 } end },
    { "two conjs", function() return { 2, 500, 500, 2 } end },
    { "a conj in the word slot", function() return { 1, 500 } end },
    { "a template in the word slot", function() return { 1, 2 } end },
    { "a slotted template in the word slot", function() return { 1, 1 } end },
    { "a word after a slotless template", function() return { 2, 1000 } end },
    { "two words", function() return { 1, 1000, 1100 } end },
    { "a slotted template alone", function() return { 1 } end },
    { "a missing word before a conj", function() return { 1, 500, 2 } end },
    { "a missing word at the end", function() return { 2, 500, 1 } end },
    { "three clauses", function() return { 2, 500, 2, 500, 2 } end },
    { "two clauses, no conj {2, 2}", function() return { 2, 2 } end },
    { "two clauses, no conj {1, 1000, 2}", function() return { 1, 1000, 2 } end },
    { "{1, 1000, 500}", function() return { 1, 1000, 500 } end },
  }

  for _, case in ipairs(REJECTED) do
    it("rejects " .. case[1], function()
      local ids = case[2]()
      local before = snapshot(ids)
      local ok, res = pcall(set.validIds, ids)
      assert.is_true(ok)
      assert.is_true(rawequal(false, res))
      assert.is_true(sameSnapshot(before, snapshot(ids)))
      ok, res = pcall(set.render, ids)
      assert.is_true(ok)
      assert.is_nil(res)
    end)
  end

  it("rejects a 1 000 000-element array", function()
    local ids = {}
    for i = 1, 1000000 do
      ids[i] = 2
    end
    assert.is_false(set.validIds(ids))
    assert.is_nil(set.render(ids))
  end)

  it("rejects a table with 100 000 string keys", function()
    local ids = {}
    for i = 1, 100000 do
      ids["k" .. i] = 2
    end
    assert.is_false(set.validIds(ids))
    assert.is_nil(set.render(ids))
  end)

  it("uses raw access: an __index function is never called", function()
    local called = 0
    local ids = setmetatable({ 1 }, { __index = function()
      called = called + 1
      return 1000
    end })
    assert.is_false(set.validIds(ids))
    assert.is_nil(set.render(ids))
    assert.is_nil(set.compose(ids))
    assert.equal(0, called)
  end)

  it("ignores a hostile metatable on an otherwise valid sequence", function()
    local ids = { 1, 1000 }
    local mt = {}
    for _, ev in ipairs(HOSTILE_EVENTS) do
      mt[ev] = raise
    end
    setmetatable(ids, mt)
    assert.is_true(set.validIds(ids))
    assert.equal("Here's to the hearth!", set.render(ids))
  end)

  for _, pos in ipairs({ 1, 2 }) do
    it("rejects every non-integer or out-of-range value at " .. pos .. " of a TW", function()
      for _, v in ipairs(badIds()) do
        local ids = { 1, 1000 }
        ids[pos] = v
        local before = snapshot(ids)
        local ok, res = pcall(set.validIds, ids)
        assert.is_true(ok)
        assert.is_true(rawequal(false, res), type(v))
        assert.is_true(sameSnapshot(before, snapshot(ids)))
        ok, res = pcall(set.render, ids)
        assert.is_true(ok)
        assert.is_nil(res)
      end
    end)
  end

  it("agrees with an independent oracle on 20 000 random sequences (real data)", function()
    -- Kind letters straight from Data/Phrases, and the six shapes written out again.
    local function oracleLetter(id)
      local rec = type(id) == "number" and DATA[id] or nil
      if rec == nil then
        return "x"
      elseif rec.kind == "template" then
        return rec.text:find("{w}", 1, true) and "T" or "t"
      elseif rec.kind == "conj" then
        return "C"
      end
      return "W"
    end
    local SHAPES = { "t", "TW", "tCt", "tCTW", "TWCt", "TWCTW" }
    local function oracle(ids)
      local shape = ""
      for i = 1, #ids do
        shape = shape .. oracleLetter(ids[i])
      end
      for _, s in ipairs(SHAPES) do
        if s == shape then
          return true
        end
      end
      return false
    end
    -- Pools by letter; "x" draws from the extras (unknown, reserved, edge and non-integer).
    local pools = { T = {}, t = {}, C = {}, W = {},
      x = { 0, 3, 499, 600, 1099, 9999, 10000, 1.5 } }
    for id in pairs(DATA) do
      local l = oracleLetter(id)
      pools[l][#pools[l] + 1] = id
    end
    for _, p in pairs(pools) do
      table.sort(p)
    end
    local letters = { "T", "t", "C", "W", "x" }
    local rand = rng(20260927)
    local accepted, rejected = 0, 0
    for _ = 1, 20000 do
      local ids = {}
      for i = 1, 1 + rand(6) do
        local pool = pools[letters[1 + rand(#letters)]]
        ids[i] = pool[1 + rand(#pool)]
      end
      local want = oracle(ids)
      local got = Phrase.validIds(ids)
      if got ~= want then
        error("mismatch for {" .. table.concat(ids, ", ") .. "}: got " .. tostring(got))
      end
      if want then
        accepted = accepted + 1
      else
        rejected = rejected + 1
      end
    end
    -- Both sides exercised.
    assert.is_true(accepted > 300, "accepted " .. accepted)
    assert.is_true(rejected > 10000, "rejected " .. rejected)
  end)

  it("accepts every part of the real set in a sequence", function()
    for _, id in ipairs(Phrase.templates()) do
      local ids = Phrase.hasSlot(id) and { id, 1001 } or { id }
      assert.is_true(Phrase.validIds(ids), tostring(id))
    end
    for cat = 1, #Phrase.categories() do
      for _, id in ipairs(Phrase.words(cat)) do
        assert.is_true(Phrase.validIds({ 1, id }), tostring(id))
      end
    end
    for _, id in ipairs(Phrase.conjunctions()) do
      assert.is_true(Phrase.validIds({ 101, id, 101 }), tostring(id))
    end
  end)
end)

describe("Phrase.render", function()
  it("renders the spec's exact strings (real data)", function()
    assert.equal("Rest well, traveler.", Phrase.render({ 101 }))
    assert.equal("Here's to old friends!", Phrase.render({ 3, 1201 }))
    assert.equal("Here's to old friends! And then... Will miss the hearth.",
      Phrase.render({ 3, 1201, 501, 11, 1002 }))
    assert.equal("Tomorrow, the long road. But... Will miss the hearth.",
      Phrase.render({ 10, 1301, 502, 11, 1002 }))
    assert.equal("Slept like a stone. Best of all... Grateful for fresh bread.",
      Phrase.render({ 102, 504, 4, 1101 }))
    assert.equal("Here's to old friends! And then... Slept like a stone.",
      Phrase.render({ 3, 1201, 501, 102 }))
    assert.equal("Rest well, traveler. Even so... The fire was warm.",
      Phrase.render({ 101, 503, 106 }))
  end)

  it("puts the word where the slot is (fixture)", function()
    local data, cats = fixture()
    data[3] = { kind = "template", text = "Found {w} here." }
    data[4] = { kind = "template", text = "Dreaming of {w}." }
    local set = Phrase.bind(data, cats)
    assert.equal("Here's to the hearth!", set.render({ 1, 1000 }))
    assert.equal("Found hot stew here.", set.render({ 3, 1100 }))
    assert.equal("Dreaming of the hearth.", set.render({ 4, 1000 }))
    assert.equal("Found the hearth here. And then... Dreaming of hot stew.",
      set.render({ 3, 1000, 500, 4, 1100 }))
  end)

  it("treats % and other pattern bytes in data as plain (they can't pass bind anyway)", function()
    local data, cats = fixture()
    data[1000].text = "the %1 hearth"
    local set = Phrase.bind(data, cats)
    assert.same({ "id 1000" }, set.invalid)
    assert.is_nil(set.render({ 1, 1000 }))
  end)
end)

describe("Phrase.compose", function()
  it("builds the sequences of spec 3.5 as new arrays", function()
    assert.same({ 101 }, Phrase.compose(101))
    assert.same({ 3, 1201 }, Phrase.compose(3, 1201))
    assert.same({ 101, 503, 3, 1201 }, Phrase.compose(101, nil, 503, 3, 1201))
    assert.same({ 3, 1201, 501, 11, 1002 }, Phrase.compose(3, 1201, 501, 11, 1002))
    assert.same({ 3, 1201, 501, 102 }, Phrase.compose(3, 1201, 501, 102))
    assert.same({ 101, 503, 106 }, Phrase.compose(101, nil, 503, 106))
    local a, b = Phrase.compose(101), Phrase.compose(101)
    assert.are_not.equal(a, b)
    a[1] = 3
    assert.same({ 101 }, Phrase.compose(101))
  end)

  it("returns nil for sequences the grammar refuses", function()
    assert.is_nil(Phrase.compose(3, nil, 501, 101)) -- the slot needs a word
    assert.is_nil(Phrase.compose(3, 1201, 501))
    assert.is_nil(Phrase.compose())
    assert.is_nil(Phrase.compose(nil, nil, nil, nil, nil))
    assert.is_nil(Phrase.compose(1201))
    assert.is_nil(Phrase.compose(101, 1201))
  end)

  it("returns nil for a sixth part, even a valid-looking one", function()
    assert.is_nil(Phrase.compose(3, 1201, 501, 11, 1002, 1002))
    assert.is_nil(Phrase.compose(101, nil, nil, nil, nil, 501))
    -- Trailing nils are not parts.
    assert.same({ 101 }, Phrase.compose(101, nil, nil, nil, nil, nil, nil))
  end)

  it("returns nil for hostile arguments, never throwing", function()
    for _, v in ipairs(badIds()) do
      for pos = 1, 5 do
        local args = { 3, 1201, 501, 11, 1002 }
        args[pos] = v
        local ok, res = pcall(Phrase.compose, unpack(args, 1, 5))
        assert.is_true(ok)
        assert.is_nil(res)
      end
      local ok, res = pcall(Phrase.compose, v)
      assert.is_true(ok)
      assert.is_nil(res)
    end
  end)
end)

-- ---------------------------------------------------------------------------
-- 6.3 The real data table.

describe("Data/Phrases (the draft set)", function()
  local RANGE = { template = { 1, 499 }, conj = { 500, 599 }, word = { 1000, 9999 } }

  local function byKind(kind)
    local out = {}
    for id, rec in pairs(DATA) do
      if rec.kind == kind then
        out[#out + 1] = id
      end
    end
    table.sort(out)
    return out
  end

  local function allowedBytes(s)
    return s:find("[^A-Za-z0-9 ',.!?%-]") == nil
  end

  it("binds with nothing invalid", function()
    assert.same({}, Phrase.invalid)
  end)

  it("keys every record by an integer ID in 1..9999 and in its kind's range", function()
    for id, rec in pairs(DATA) do
      assert.equal("number", type(id), tostring(id))
      assert.is_true(id % 1 == 0 and id >= 1 and id <= NS.Ledger.LIMITS.phraseIdMax, tostring(id))
      assert.is_true(id < 600 or id > 999, "reserved ID " .. id)
      local r = RANGE[rec.kind]
      assert.is_table(r, tostring(id))
      assert.is_true(id >= r[1] and id <= r[2], tostring(id))
    end
  end)

  it("files every word in its category's block, and every category has a word", function()
    for id, rec in pairs(DATA) do
      if rec.kind == "word" then
        assert.equal(math.floor((id - 900) / 100), rec.cat, tostring(id))
      end
    end
    assert.equal(#CATEGORIES, #Phrase.categories())
    for cat = 1, #CATEGORIES do
      assert.is_true(#Phrase.words(cat) > 0, CATEGORIES[cat])
    end
  end)

  it("category names pass rule 6 and don't repeat", function()
    local seen = {}
    for i, name in ipairs(CATEGORIES) do
      assert.is_true(#name >= 1 and #name <= 40 and allowedBytes(name), name)
      assert.truthy(name:find("^[A-Z]"), name)
      assert.is_nil(name:find("^ ") or name:find(" $") or name:find("  ", 1, true))
      assert.is_nil(seen[name:lower()], name)
      seen[name:lower()] = i
    end
  end)

  it("no two records of the same kind share a text (case-insensitive)", function()
    local seen = { template = {}, conj = {}, word = {} }
    for id, rec in pairs(DATA) do
      local key = rec.text:lower()
      assert.is_nil(seen[rec.kind][key], rec.text .. " at " .. id)
      seen[rec.kind][key] = id
    end
  end)

  it("keeps the worst-case rendering within renderBytes and on the spec 3.4 formula", function()
    local L = Phrase.LIMITS
    assert.is_true(2 * (L.templateBytes - 3 + L.wordBytes) + 2 + L.conjBytes <= L.renderBytes)
    local function longest(ids, keep)
      local best
      for _, id in ipairs(ids) do
        if (keep == nil or keep(id)) and (best == nil or #DATA[id].text > #DATA[best].text) then
          best = id
        end
      end
      return best
    end
    local T = longest(byKind("template"), Phrase.hasSlot)
    local W = longest(byKind("word"))
    local C = longest(byKind("conj"))
    local text = Phrase.render({ T, W, C, T, W })
    assert.is_string(text)
    local lenT, lenW, lenC = #DATA[T].text, #DATA[W].text, #DATA[C].text
    assert.equal(2 * (lenT - 3 + lenW) + 2 + lenC, #text)
    assert.is_true(#text <= L.renderBytes)
    -- No slotless template or two-clause slotless form is longer than that.
    local t = longest(byKind("template"))
    assert.is_true(#DATA[t].text <= lenT - 3 + lenW)
  end)

  it("every one-clause rendering is within renderBytes and passes the byte allow-list", function()
    local n = 0
    for _, t in ipairs(Phrase.templates()) do
      local list = {}
      if Phrase.hasSlot(t) then
        for cat = 1, #Phrase.categories() do
          for _, w in ipairs(Phrase.words(cat)) do
            list[#list + 1] = { t, w }
          end
        end
      else
        list[1] = { t }
      end
      for _, ids in ipairs(list) do
        local text = Phrase.render(ids)
        assert.is_string(text)
        assert.is_true(#text <= Phrase.LIMITS.renderBytes)
        assert.is_true(allowedBytes(text), text)
        assert.is_nil(text:find("{w}", 1, true))
        n = n + 1
      end
    end
    assert.equal(109 * 175 + 47, n)
  end)

  it("trips on no deny-listed word (spec 3.6 tripwire)", function()
    local DENY = {}
    for w in ([[
      bed bath naked kiss lick touch ride came come love butt buns nuts cherry cherries
      melon melons sausage peach peaches breast thigh hole tongue rear hand head heart belly
      blood kill die dead death horde alliance human dwarf dwarves elf elves gnome gnomes
      orc orcs troll trolls tauren undead forsaken warrior mage priest rogue hunter warlock
      paladin druid shaman man woman men women boy girl innkeeper stayed milk staff
      goblin goblins worgen chest meat mount pay paid coin coins buy bought stool trade
    ]]):gmatch("%S+") do
      DENY[w] = true
    end
    for id, rec in pairs(DATA) do
      for run in rec.text:lower():gmatch("[a-z]+") do
        assert.is_nil(DENY[run], ("%q in %d: %q"):format(run, id, rec.text))
      end
    end
    -- The tripwire itself works.
    local hits = 0
    for run in ("A warm bed, the Heart."):lower():gmatch("[a-z]+") do
      if DENY[run] then
        hits = hits + 1
      end
    end
    assert.equal(2, hits)
  end)

  it("has the counts of spec 9 (update with the wording)", function()
    assert.equal(156, #byKind("template"))
    local slotted = 0
    for _, id in ipairs(byKind("template")) do
      if Phrase.hasSlot(id) then
        slotted = slotted + 1
      end
    end
    assert.equal(109, slotted)
    assert.equal(30, #byKind("conj"))
    assert.equal(175, #byKind("word"))
    assert.equal(9, #CATEGORIES)
    for cat = 1, 8 do
      assert.equal(20, #Phrase.words(cat))
    end
    assert.equal(15, #Phrase.words(9))
    assert.equal(8, #VOICES)
    local perVoice = { { 36, 7 }, { 20, 4 }, { 19, 3 }, { 17, 4 }, { 16, 3 }, { 17, 3 },
      { 16, 3 }, { 15, 3 } }
    for v, counts in ipairs(perVoice) do
      assert.equal(counts[1], #Phrase.templates(v), VOICES[v])
      assert.equal(counts[2], #Phrase.conjunctions(v), VOICES[v])
    end
    local n = 0
    for _ in pairs(DATA) do
      n = n + 1
    end
    assert.equal(361, n)
  end)

  it("the lists match the data", function()
    assert.same(byKind("template"), Phrase.templates())
    assert.same(byKind("conj"), Phrase.conjunctions())
    assert.same(CATEGORIES, Phrase.categories())
    assert.are_not.equal(CATEGORIES, Phrase.categories())
    assert.same(VOICES, Phrase.voices())
    assert.are_not.equal(VOICES, Phrase.voices())
  end)

  it("gives every template and conjunction a voice, inside its voice's ID block", function()
    -- The allocation convention of Data/Phrases.lua's header (spec 3.1).
    local function templateVoice(id)
      if id <= 200 then
        return 1
      end
      return math.floor((id - 201) / 30) + 2
    end
    for id, rec in pairs(DATA) do
      if rec.kind == "template" then
        assert.equal(templateVoice(id), rec.voice, rec.text)
        assert.equal(rec.voice, Phrase.voice(id))
        local slotless = id > 200 and (id - 201) % 30 >= 20 or id > 100 and id <= 200
        assert.equal(not slotless, Phrase.hasSlot(id), rec.text)
      elseif rec.kind == "conj" then
        assert.equal(math.floor((id - 501) / 10) + 1, rec.voice, rec.text)
        assert.equal(rec.voice, Phrase.voice(id))
      else
        assert.is_nil(Phrase.voice(id))
      end
    end
    local all = {}
    for v = 1, #VOICES do
      for _, id in ipairs(Phrase.templates(v)) do
        all[#all + 1] = id
      end
    end
    table.sort(all)
    assert.same(Phrase.templates(), all)
  end)

  it("voice names pass rule 6 and don't repeat", function()
    local seen = {}
    for i, name in ipairs(VOICES) do
      assert.is_true(#name >= 1 and #name <= 40 and allowedBytes(name), name)
      assert.truthy(name:find("^[A-Z]"), name)
      assert.is_nil(seen[name:lower()], name)
      seen[name:lower()] = i
    end
  end)
end)

-- ---------------------------------------------------------------------------
-- 6.4 With SyncProtocol.

describe("Phrase as SyncProtocol's phraseOk hook (real data)", function()
  local OWNER = "Player-1234-0ABCDEF0"
  local MIRA = "Player-1234-0BBBBBB0"
  local SENDER = { guid = MIRA, name = "Mira Ashvale" }
  local ANCHOR = 1790089200 -- Tuesday 2026-09-22 15:00 UTC
  local NOW = 1794000000

  local function loadAll()
    local ns = {}
    load.file("Ledger.lua", ns, load.pure_env())
    load.file("Data/Phrases.lua", ns, load.pure_env())
    load.file("Phrase.lua", ns, load.pure_env())
    load.file("SyncProtocol.lua", ns, load.pure_env())
    return ns
  end

  local function newCtx(ns, hook)
    return {
      now = NOW, selfGUID = OWNER,
      inns = { [1234] = true, [1235] = true, [1236] = true, [1237] = true, [1238] = true,
        [1239] = true },
      seals = {},
      phrases = ns.Data.Phrases,
      phraseOk = hook and ns.Phrase.validIds or nil,
      ledger = ns.Ledger.new({}, { guid = OWNER, name = "Aldric Stonebrook" }, ANCHOR),
      limiter = ns.SyncProtocol.newLimiter(),
      wantMemo = ns.SyncProtocol.newWantMemo(),
    }
  end

  local A = { inn = 1234, t = NOW - 500, phrase = { 3, 1201, 501, 11, 1002 } }
  local B = { inn = 1235, t = NOW - 400, phrase = { 101 } }
  local MSG = "E1:1234," .. (NOW - 500) .. ",3.1201.501.11.1002,0"
    .. ";1235," .. (NOW - 400) .. ",101,0"
    .. ";1236," .. (NOW - 300) .. ",1201.3,0"
    .. ";1237," .. (NOW - 200) .. ",3,0"
    .. ";1238," .. (NOW - 100) .. ",101.501.101.501.101,0"
  local UNKNOWN = "E1:1239," .. (NOW - 50) .. ",3.1099,0"

  it("stores the grammatical entries and rejects the rest", function()
    local ns = loadAll()
    local ctx = newCtx(ns, true)
    assert.equal("function", type(ctx.phraseOk))
    local res, reason = ns.SyncProtocol.receive(MSG, "PARTY", SENDER, ctx)
    assert.is_nil(reason)
    assert.same({ kind = "entries", added = 2, dup = 0, dropped = 0, rejected = 3 }, res)
    local held = ctx.ledger:signerEntries(MIRA)
    assert.same({ A, B }, held)
    assert.equal("Here's to old friends! And then... Will miss the hearth.",
      ns.Phrase.render(held[1].phrase))
    assert.equal("Rest well, traveler.", ns.Phrase.render(held[2].phrase))
    -- An unknown ID is rejected by the lookup before the hook.
    assert.same({ kind = "entries", added = 0, dup = 0, dropped = 0, rejected = 1 },
      ns.SyncProtocol.receive(UNKNOWN, "PARTY", SENDER, ctx))
    assert.equal(2, #ctx.ledger:signerEntries(MIRA))
  end)

  it("without the hook the lookup alone stores all five, still rejects an unknown ID", function()
    local ns = loadAll()
    local ctx = newCtx(ns, false)
    assert.is_nil(ctx.phraseOk)
    assert.same({ kind = "entries", added = 5, dup = 0, dropped = 0, rejected = 0 },
      ns.SyncProtocol.receive(MSG, "PARTY", SENDER, ctx))
    assert.same({ kind = "entries", added = 0, dup = 0, dropped = 0, rejected = 1 },
      ns.SyncProtocol.receive(UNKNOWN, "PARTY", SENDER, ctx))
    assert.equal(5, #ctx.ledger:signerEntries(MIRA))
  end)
end)
