-- Ledger: entry store, dedupe, weeks, caps, load and migration (docs/specs/sync-ledger.md,
-- sections 4 and 6). Fixed times only, never the clock.
local load = require("helpers.load")

local function fresh()
  return load.file("Ledger.lua", {}, load.pure_env()).Ledger
end

local Ledger = fresh()
local LIMITS, CAPS = Ledger.LIMITS, Ledger.CAPS

local ANCHOR = 1790089200 -- Tuesday 2026-09-22 15:00 UTC, the retail US reset
local WEEK = 604800
local DAY = 86400
local T0 = ANCHOR + 3600  -- inside week 0
local NOW = ANCHOR + 2 * DAY
local OWNER = "Player-1234-0ABCDEF0"
local OWNER_INFO = { guid = OWNER, name = "Aldric Stonebrook" }
local MIRA = "Player-1234-0BBBBBB0"
local NAME = "Mira Ashvale"

local function entry(inn, t, phrase, seal)
  return { inn = inn, t = t, phrase = phrase or { 1 }, seal = seal }
end

local function guid(n)
  return ("Player-1-%08X"):format(n)
end

local function newLedger(data, anchor, L)
  return (L or Ledger).new(data or {}, OWNER_INFO, anchor or ANCHOR)
end

local function deepcopy(v)
  if type(v) ~= "table" then
    return v
  end
  local out = {}
  for k, x in pairs(v) do
    out[deepcopy(k)] = deepcopy(x)
  end
  return out
end

local function raise()
  error("hidden value touched")
end

local HOSTILE_EVENTS = {
  "__index", "__len", "__eq", "__lt", "__le", "__concat", "__tostring", "__call",
}

-- The two hidden-value stand-ins (spec 5.2).
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

-- Every query agrees with every other and with the caps.
local function assertConsistent(ledger)
  local counts = ledger:counts()
  local travelers = ledger:travelers()
  assert.equal(#travelers, counts.travelers)
  local total, perInn = 0, {}
  for _, tr in ipairs(travelers) do
    local entries = ledger:signerEntries(tr.guid)
    assert.equal(tr.count, #entries)
    assert.is_true(#entries >= 1 and #entries <= CAPS.perSigner)
    for _, e in ipairs(entries) do
      assert.is_true(ledger:has(tr.guid, e.inn, e.t))
      perInn[e.inn] = (perInn[e.inn] or 0) + 1
    end
    total = total + #entries
  end
  assert.equal(total, counts.foreign)
  assert.is_true(total <= CAPS.foreignTotal)
  for inn, n in pairs(perInn) do
    assert.is_true(n <= CAPS.perInn)
    assert.equal(n, #ledger:innEntries(inn).foreign)
  end
  assert.equal(#ledger:own(), counts.own)
end

describe("Ledger constants", function()
  it("match spec 3.1 and 4.4", function()
    assert.same({
      innMax = 9999999, phraseIdMax = 9999, phraseIdsMax = 5, sealMax = 999,
      tMin = 1789603200, tMax = 9999999999, futureTolerance = 300, nameMaxBytes = 96,
      cosmeticIdMax = 9999, weekLength = 604800,
    }, LIMITS)
    assert.same({ perSigner = 40, perInn = 150, foreignTotal = 3000 }, CAPS)
    assert.equal(1, Ledger.SCHEMA)
    assert.same({}, Ledger.MIGRATIONS)
  end)
end)

describe("Ledger.validEntry", function()
  local nan, inf = 0 / 0, math.huge

  it("accepts a minimal and a maximal entry", function()
    assert.is_true(Ledger.validEntry({ inn = 1, t = LIMITS.tMin, phrase = { 1 } }))
    assert.is_true(Ledger.validEntry({
      inn = LIMITS.innMax, t = LIMITS.tMax, phrase = { 9999, 9999, 9999, 9999, 9999 },
      seal = LIMITS.sealMax,
    }))
  end)

  it("rejects each field missing", function()
    assert.is_false(Ledger.validEntry({ t = T0, phrase = { 1 } }))
    assert.is_false(Ledger.validEntry({ inn = 1, phrase = { 1 } }))
    assert.is_false(Ledger.validEntry({ inn = 1, t = T0 }))
  end)

  it("rejects wrong types, out-of-range values, NaN, inf, -inf, 1.5 and 0", function()
    local bad = {
      inn = { "1", true, {}, 0, LIMITS.innMax + 1, nan, inf, -inf, 1.5, -1 },
      t = { "1793800000", LIMITS.tMin - 1, LIMITS.tMax + 1, nan, inf, -inf, T0 + 0.5, 0 },
      seal = { "1", 0, LIMITS.sealMax + 1, nan, inf, -inf, 1.5, -1 },
    }
    for field, values in pairs(bad) do
      for _, v in ipairs(values) do
        local e = entry(1234, T0, { 1 }, 3)
        e[field] = v
        assert.is_false(Ledger.validEntry(e), field .. " = " .. tostring(v))
      end
    end
    for _, v in ipairs({ "1", 0, LIMITS.phraseIdMax + 1, nan, inf, -inf, 1.5, -1 }) do
      assert.is_false(Ledger.validEntry(entry(1234, T0, { 1, v })), "phrase id " .. tostring(v))
    end
  end)

  it("rejects a phrase with 0 or 6 IDs, a hole or an extra key, or not a table", function()
    assert.is_false(Ledger.validEntry(entry(1, T0, {})))
    assert.is_false(Ledger.validEntry(entry(1, T0, { 1, 2, 3, 4, 5, 6 })))
    assert.is_false(Ledger.validEntry(entry(1, T0, { [1] = 1, [3] = 3 })))
    assert.is_false(Ledger.validEntry(entry(1, T0, { [2] = 1 })))
    assert.is_false(Ledger.validEntry(entry(1, T0, { 1, x = 2 })))
    assert.is_false(Ledger.validEntry(entry(1, T0, { [1.5] = 1 })))
    local e = entry(1, T0)
    e.phrase = "1.2"
    assert.is_false(Ledger.validEntry(e))
  end)

  it("rejects an extra top-level key, seal = 0 and non-tables", function()
    local e = entry(1, T0)
    e.signer = MIRA
    assert.is_false(Ledger.validEntry(e))
    assert.is_false(Ledger.validEntry(entry(1, T0, { 1 }, 0)))
    for _, v in ipairs({ "x", 5, true }) do
      assert.is_false(Ledger.validEntry(v))
    end
    assert.is_false(Ledger.validEntry(nil))
  end)

  it("never runs a metatable and never throws", function()
    local e = setmetatable({ inn = 1, t = T0, phrase = { 1 } }, getmetatable(hostileTable()))
    assert.is_true(Ledger.validEntry(e))
    assert.is_false(Ledger.validEntry(hostileTable()))
    assert.is_false(Ledger.validEntry(hostileProxy()))
    assert.is_false(Ledger.validEntry(entry(1, T0, hostileTable())))
  end)
end)

describe("Ledger.validGUID and Ledger.validName", function()
  it("accept the documented forms", function()
    assert.is_true(Ledger.validGUID("Player-1234-0ABCDEF0"))
    assert.is_true(Ledger.validGUID("Player-1-" .. ("A"):rep(31))) -- 40 bytes
    for _, name in ipairs({
      "Aldric", "Aldric Stonebrook", "Aldric-Azjol-Nerub", "\195\134lfric", "Al",
      "Aldric Stonebrook-Azjol-Nerub", "Aldric-Kel'Thuzad", "Ab C", ("a"):rep(48),
    }) do
      assert.is_true(Ledger.validName(name), name)
    end
  end)

  it("reject malformed GUIDs", function()
    for _, g in ipairs({
      "player-1-AB", "Player--AB", "Player-1-", "Player-1-AB-CD", "Player-1-0x1F",
      "Player-1-" .. ("A"):rep(32), "Player-1-AB\0CD", "Player-1-AB|r", "Creature-1-AB",
      " Player-1-AB", "Player-1-AB ", "",
    }) do
      assert.is_false(Ledger.validGUID(g), g)
    end
    for _, v in ipairs({ 5, true, {} }) do
      assert.is_false(Ledger.validGUID(v))
    end
    assert.is_false(Ledger.validGUID(nil))
  end)

  it("reject malformed names", function()
    for _, name in ipairs({
      "Ald\0ric", "Ald|ric", "|cffff0000Aldric", "Ald\1ric", "Ald\127ric", "Ald\31ric",
      "Aldric  Stonebrook", "Aldric Stone Brook", "Aldric-", "Aldric-Realm-", "-Realm",
      "A", ("a"):rep(97), "A Stonebrook", " Aldric", "Aldric ", "Ald3ric", "Aldric-Re alm",
      ("a"):rep(49), "Aldric " .. ("b"):rep(49), "Aldric-" .. ("r"):rep(49), "",
    }) do
      assert.is_false(Ledger.validName(name), name)
    end
    for _, v in ipairs({ 5, true, {} }) do
      assert.is_false(Ledger.validName(v))
    end
    assert.is_false(Ledger.validName(nil))
  end)

  it("never throw on the hidden-value stand-ins", function()
    for _, v in ipairs({ hostileTable(), hostileProxy() }) do
      assert.is_false(Ledger.validGUID(v))
      assert.is_false(Ledger.validName(v))
    end
  end)
end)

describe("Ledger weeks", function()
  local ledger
  before_each(function()
    ledger = newLedger()
  end)

  it("numbers weeks from the anchor", function()
    assert.equal(0, ledger:weekOf(ANCHOR))
    assert.equal(-1, ledger:weekOf(ANCHOR - 1))
    -- Tuesday 14:59:59 and 15:00:00 UTC a week later.
    assert.equal(0, ledger:weekOf(ANCHOR + WEEK - 1))
    assert.equal(1, ledger:weekOf(ANCHOR + WEEK))
  end)

  it("gives the next reset at, just before and just after a boundary", function()
    local b = ANCHOR + WEEK
    assert.equal(b + WEEK, ledger:nextWeekStart(b))
    assert.equal(b, ledger:nextWeekStart(b - 1))
    assert.equal(b + WEEK, ledger:nextWeekStart(b + 1))
    assert.equal(ANCHOR, ledger:nextWeekStart(ANCHOR - 1))
  end)

  it("partitions time the same with an anchor a few weeks in the future", function()
    local future = newLedger({}, ANCHOR + 3 * WEEK)
    for _, t in ipairs({
      ANCHOR - 5, ANCHOR, ANCHOR + 1, ANCHOR + WEEK - 1, ANCHOR + WEEK, T0 + 17 * DAY,
      LIMITS.tMin, ANCHOR + 10 * WEEK + 12345,
    }) do
      assert.equal(ledger:weekOf(t) - 3, future:weekOf(t))
      assert.equal(ledger:nextWeekStart(t), future:nextWeekStart(t))
    end
  end)

  it("Ledger.new errors on a missing, fractional, NaN or out-of-range anchor", function()
    for _, anchor in ipairs({ ANCHOR + 0.5, 0 / 0, math.huge, -1, LIMITS.tMax + 1, "1" }) do
      assert.has_error(function() Ledger.new({}, OWNER_INFO, anchor) end)
    end
    assert.has_error(function() Ledger.new({}, OWNER_INFO, nil) end)
    assert.has_no.errors(function() Ledger.new({}, OWNER_INFO, 0) end)
  end)

  it("re-applies the weekly rule to foreign entries when the anchor moves a day", function()
    local data = {}
    local a = newLedger(data)
    local t1, t2 = ANCHOR + 6 * DAY + DAY / 2, ANCHOR + 7 * DAY + DAY / 5
    assert.equal("added", a:addOwn(entry(1, t1)))
    assert.equal("added", a:addOwn(entry(1, t2)))
    assert.equal("added", a:addForeign(MIRA, NAME, entry(5, t1), NOW))
    assert.equal("added", a:addForeign(MIRA, NAME, entry(5, t2), NOW))

    local b = newLedger(data, ANCHOR + DAY)
    assert.equal(b:weekOf(t1), b:weekOf(t2))
    assert.equal(2, #b:own())
    local kept = b:signerEntries(MIRA)
    assert.equal(1, #kept)
    assert.equal(t1, kept[1].t)
    assert.equal(1, b.loadReport.weekly)
    assert.equal(1, #data.travelers[MIRA].entries)
  end)
end)

describe("Ledger:addOwn", function()
  local ledger
  before_each(function()
    ledger = newLedger()
  end)

  it("adds, then reports dup and too_soon, and adds again at the next reset", function()
    assert.is_true(ledger:canSign(1234, T0))
    assert.equal("added", ledger:addOwn(entry(1234, T0, { 1, 22, 3 })))
    assert.is_true(ledger:has(OWNER, 1234, T0))
    assert.equal("dup", ledger:addOwn(entry(1234, T0, { 9 })))
    assert.same({ 1, 22, 3 }, ledger:own()[1].phrase)

    local later = ANCHOR + WEEK - 1
    assert.is_false(ledger:canSign(1234, later))
    assert.equal("too_soon", ledger:addOwn(entry(1234, later)))

    assert.is_true(ledger:canSign(1234, ANCHOR + WEEK))
    assert.equal("added", ledger:addOwn(entry(1234, ANCHOR + WEEK)))
    assert.is_false(ledger:canSign(1234, ANCHOR + WEEK + 5))
  end)

  it("allows a different inn in the same week", function()
    assert.equal("added", ledger:addOwn(entry(1234, T0)))
    assert.is_true(ledger:canSign(98765, T0 + 60))
    assert.equal("added", ledger:addOwn(entry(98765, T0 + 60)))
    assert.equal(2, ledger:counts().own)
  end)

  it("rejects invalid entries, and canSign is false for invalid arguments", function()
    assert.equal("invalid", ledger:addOwn(entry(0, T0)))
    assert.equal("invalid", ledger:addOwn(nil))
    assert.equal("invalid", ledger:addOwn(hostileTable()))
    assert.equal(0, ledger:counts().own)
    assert.is_false(ledger:canSign(0, T0))
    assert.is_false(ledger:canSign(1234, 0 / 0))
    assert.is_false(ledger:canSign("1234", T0))
    assert.is_false(ledger:canSign(1234, nil))
  end)

  it("keeps own entries sorted by (t, inn) whatever the insert order", function()
    local adds = {
      entry(30, T0 + 5), entry(10, T0 + 1), entry(20, T0 + 5), entry(40, T0 - 100),
      entry(5, T0 + 5), entry(10, T0 + WEEK),
    }
    for _, e in ipairs(adds) do
      assert.equal("added", ledger:addOwn(e))
    end
    local got = {}
    for _, e in ipairs(ledger:own()) do
      got[#got + 1] = { e.t, e.inn }
    end
    assert.same({
      { T0 - 100, 40 }, { T0 + 1, 10 }, { T0 + 5, 5 }, { T0 + 5, 20 }, { T0 + 5, 30 },
      { T0 + WEEK, 10 },
    }, got)
  end)

  it("never evicts own entries, whatever the foreign adds", function()
    for i = 1, 5 do
      assert.equal("added", ledger:addOwn(entry(7, ANCHOR + i * WEEK)))
    end
    for i = 1, 200 do
      ledger:addForeign(guid(i), NAME, entry(7, T0 + i), NOW)
    end
    assert.equal(5, ledger:counts().own)
    assert.equal(5, #ledger:innEntries(7).own)
    assert.equal(CAPS.perInn, #ledger:innEntries(7).foreign)
  end)

  it("stores a copy of the caller's entry", function()
    local e = entry(1234, T0, { 1, 22, 3 }, 4)
    assert.equal("added", ledger:addOwn(e))
    e.inn, e.t, e.seal = 99, T0 + 1, 5
    e.phrase[1], e.phrase[4] = 55, 6
    assert.same({ entry(1234, T0, { 1, 22, 3 }, 4) }, ledger:own())
    assert.is_true(ledger:has(OWNER, 1234, T0))
    assert.is_false(ledger:has(OWNER, 99, T0 + 1))
  end)
end)

describe("Ledger:addForeign", function()
  local ledger
  before_each(function()
    ledger = newLedger()
  end)

  it("adds with a traveler record carrying the name and met = now", function()
    assert.equal("added", ledger:addForeign(MIRA, NAME, entry(1234, T0, { 4, 5 }, 2), NOW))
    assert.same({ { guid = MIRA, name = NAME, met = NOW, count = 1 } }, ledger:travelers())
    assert.same({ entry(1234, T0, { 4, 5 }, 2) }, ledger:signerEntries(MIRA))
    assert.is_true(ledger:has(MIRA, 1234, T0))
    assert.is_false(ledger:has(OWNER, 1234, T0))
  end)

  it("reports dup, and a conflicting re-send doesn't overwrite", function()
    assert.equal("added", ledger:addForeign(MIRA, NAME, entry(1234, T0, { 4 }), NOW))
    assert.equal("dup", ledger:addForeign(MIRA, NAME, entry(1234, T0, { 4 }), NOW))
    assert.equal("dup", ledger:addForeign(MIRA, "Mira Other", entry(1234, T0, { 9 }, 3), NOW))
    assert.same({ entry(1234, T0, { 4 }) }, ledger:signerEntries(MIRA))
    assert.equal(NAME, ledger:travelers()[1].name)
  end)

  it("reports too_soon for a signer's second entry at one inn in one week", function()
    assert.equal("added", ledger:addForeign(MIRA, NAME, entry(1234, T0), NOW))
    assert.equal("too_soon", ledger:addForeign(MIRA, NAME, entry(1234, T0 + DAY), NOW))
    assert.equal("added", ledger:addForeign(guid(1), NAME, entry(1234, T0 + DAY), NOW))
    assert.equal("added", ledger:addForeign(MIRA, NAME, entry(1234, ANCHOR + WEEK), NOW))
    assert.same({ entry(1234, T0), entry(1234, ANCHOR + WEEK) }, ledger:signerEntries(MIRA))
  end)

  it("own and foreign entries don't limit each other", function()
    assert.equal("added", ledger:addOwn(entry(1234, T0)))
    assert.equal("added", ledger:addForeign(MIRA, NAME, entry(1234, T0), NOW))
    assert.equal("added", ledger:addForeign(guid(2), NAME, entry(1234, T0 + 1), NOW))
    assert.is_false(ledger:canSign(1234, T0 + 2))
  end)

  it("refuses the owner's own GUID", function()
    assert.equal("self", ledger:addForeign(OWNER, NAME, entry(1234, T0), NOW))
    assert.equal(0, ledger:counts().foreign)
    assert.same({}, ledger:travelers())
  end)

  it("rejects an invalid signer, name, entry or now", function()
    local good = entry(1234, T0)
    local cases = {
      { "player-1-AB", NAME, good, NOW },
      { nil, NAME, good, NOW },
      { hostileTable(), NAME, good, NOW },
      { MIRA, "Mira|r", good, NOW },
      { MIRA, nil, good, NOW },
      { MIRA, hostileProxy(), good, NOW },
      { MIRA, NAME, entry(1234, T0, { 1 }, 0), NOW },
      { MIRA, NAME, hostileTable(), NOW },
      { MIRA, NAME, good, NOW + 0.5 },
      { MIRA, NAME, good, nil },
      { MIRA, NAME, good, 0 / 0 },
    }
    for i, c in ipairs(cases) do
      assert.equal("invalid", ledger:addForeign(c[1], c[2], c[3], c[4]), "case " .. i)
    end
    assert.same({ own = 0, foreign = 0, travelers = 0 }, ledger:counts())
  end)

  it("updates the name on a later accepted entry and keeps met", function()
    assert.equal("added", ledger:addForeign(MIRA, NAME, entry(1, T0), NOW))
    assert.equal("dup", ledger:addForeign(MIRA, "Mira Dup", entry(1, T0), NOW + 50))
    assert.equal("Mira Ashvale", ledger:travelers()[1].name)
    assert.equal("added", ledger:addForeign(MIRA, "Mira Stormwind", entry(2, T0), NOW + 100))
    assert.same({ { guid = MIRA, name = "Mira Stormwind", met = NOW, count = 2 } },
      ledger:travelers())
  end)

  it("stores a copy of the caller's entry", function()
    local e = entry(1234, T0, { 4, 5 })
    assert.equal("added", ledger:addForeign(MIRA, NAME, e, NOW))
    e.t, e.phrase[1] = T0 + 9, 77
    assert.same({ entry(1234, T0, { 4, 5 }) }, ledger:signerEntries(MIRA))
  end)
end)

describe("Ledger caps", function()
  local ledger
  before_each(function()
    ledger = newLedger()
  end)

  it("the 41st entry of a signer evicts that signer's oldest", function()
    for i = 1, 40 do
      assert.equal("added", ledger:addForeign(MIRA, NAME, entry(i, T0 + i), NOW))
    end
    assert.equal("added", ledger:addForeign(MIRA, NAME, entry(41, T0 + 41), NOW))
    local entries = ledger:signerEntries(MIRA)
    assert.equal(40, #entries)
    assert.equal(2, entries[1].inn)
    assert.is_false(ledger:has(MIRA, 1, T0 + 1))
    assertConsistent(ledger)

    -- The evicted key's dedupe and week slots are free again: the same inn, same week,
    -- newer time goes in (evicting the next oldest).
    assert.equal("added", ledger:addForeign(MIRA, NAME, entry(1, T0 + 100), NOW))
    assert.is_false(ledger:has(MIRA, 2, T0 + 2))
    -- Re-adding the evicted key itself is judged by the caps, not refused as a dup.
    assert.equal("dropped", ledger:addForeign(MIRA, NAME, entry(2, T0 + 2), NOW))
    assertConsistent(ledger)
  end)

  it("an older 41st entry of a signer is itself dropped", function()
    for i = 1, 40 do
      ledger:addForeign(MIRA, NAME, entry(i, T0 + i), NOW)
    end
    assert.equal("dropped", ledger:addForeign(MIRA, NAME, entry(41, T0), NOW))
    assert.is_false(ledger:has(MIRA, 41, T0))
    assert.equal(40, #ledger:signerEntries(MIRA))
    assert.equal(1, ledger:signerEntries(MIRA)[1].inn)
    assertConsistent(ledger)
  end)

  it("the 151st foreign entry at an inn evicts the inn's oldest", function()
    for i = 1, 150 do
      assert.equal("added", ledger:addForeign(guid(i), NAME, entry(9, T0 + i), NOW))
    end
    assert.equal("added", ledger:addForeign(guid(151), NAME, entry(9, T0 + 151), NOW))
    local foreign = ledger:innEntries(9).foreign
    assert.equal(150, #foreign)
    assert.equal(guid(2), foreign[1].signer)
    assert.is_false(ledger:has(guid(1), 9, T0 + 1))
    -- A traveler with no entries left disappears.
    assert.same({}, ledger:signerEntries(guid(1)))
    assert.equal(150, ledger:counts().travelers)
    assertConsistent(ledger)
    assert.equal("dropped", ledger:addForeign(guid(1), NAME, entry(9, T0 + 1), NOW))
    assert.equal(150, ledger:counts().travelers)
    assertConsistent(ledger)
  end)

  -- 3000 entries: 100 signers x 30, each at its own inn, t = T0 + k (k = 1..3000).
  local function fillTotal(l, oldest)
    local k = 0
    for s = 1, 100 do
      for j = 1, 30 do
        k = k + 1
        assert.equal("added", l:addForeign(guid(s), NAME, entry(s * 100 + j, T0 + 10 + k), NOW))
      end
    end
    for _, o in ipairs(oldest or {}) do
      assert.equal("added", l:addForeign(o[1], NAME, entry(o[2], T0), NOW))
    end
  end

  it("the 3 001st foreign entry evicts the global oldest", function()
    fillTotal(ledger)
    assert.equal(3000, ledger:counts().foreign)
    assert.equal("added", ledger:addForeign(MIRA, NAME, entry(1, T0 + 5000), NOW))
    assert.equal(3000, ledger:counts().foreign)
    assert.is_false(ledger:has(guid(1), 101, T0 + 11))
    assert.is_true(ledger:has(guid(1), 102, T0 + 12))
    assert.equal("dropped", ledger:addForeign(guid(1), NAME, entry(101, T0 + 11), NOW))
    assertConsistent(ledger)
  end)

  it("breaks ties by (t, signer, inn)", function()
    local a, b = "Player-1-A0", "Player-1-B0"
    local l = newLedger()
    -- Three entries share the oldest t; fill to 3 000 without the last three fillers.
    local k = 0
    for s = 1, 100 do
      for j = 1, 30 do
        k = k + 1
        if k <= 2997 then
          l:addForeign(guid(s), NAME, entry(s * 100 + j, T0 + 10 + k), NOW)
        end
      end
    end
    assert.equal("added", l:addForeign(b, NAME, entry(1, T0), NOW))
    assert.equal("added", l:addForeign(a, NAME, entry(2, T0), NOW))
    assert.equal("added", l:addForeign(a, NAME, entry(1, T0), NOW))
    assert.equal(3000, l:counts().foreign)

    local order = { { a, 1 }, { a, 2 }, { b, 1 } }
    for n, victim in ipairs(order) do
      assert.equal("added", l:addForeign(MIRA, NAME, entry(n, T0 + 9000 + n), NOW))
      assert.is_false(l:has(victim[1], victim[2], T0), "eviction " .. n)
      for m = n + 1, #order do
        assert.is_true(l:has(order[m][1], order[m][2], T0))
      end
    end
    assertConsistent(l)

    -- The same order within one inn: (t, signer).
    local inn = newLedger()
    for i = 1, 148 do
      inn:addForeign(guid(i), NAME, entry(9, T0 + i), NOW)
    end
    inn:addForeign(b, NAME, entry(9, T0), NOW)
    inn:addForeign(a, NAME, entry(9, T0), NOW)
    assert.equal(a, inn:innEntries(9).foreign[1].signer)
    inn:addForeign(MIRA, NAME, entry(9, T0 + 500), NOW)
    assert.is_false(inn:has(a, 9, T0))
    assert.is_true(inn:has(b, 9, T0))
  end)

  it("a flood of 10 000 entries from 500 signers ends at the caps", function()
    local results = {}
    for j = 1, 20 do
      for s = 1, 500 do
        -- 20 distinct inns per signer (distinct (inn, week) pairs), 60 inns overall.
        local inn = (s * 7 + j) % 60 + 1
        local r = ledger:addForeign(guid(s), NAME, entry(inn, T0 + j * 500 + s), NOW)
        results[r] = (results[r] or 0) + 1
      end
    end
    assert.equal(10000, (results.added or 0) + (results.dropped or 0))
    local counts = ledger:counts()
    assert.equal(3000, counts.foreign)
    for _, tr in ipairs(ledger:travelers()) do
      assert.is_true(tr.count <= CAPS.perSigner)
    end
    for inn = 1, 60 do
      assert.is_true(#ledger:innEntries(inn).foreign <= CAPS.perInn)
    end
    assertConsistent(ledger)
  end)
end)

describe("Ledger queries", function()
  local ledger
  before_each(function()
    ledger = newLedger()
  end)

  it("shareWindow(40) with 0, 39, 40 and 100 own entries", function()
    assert.same({}, ledger:shareWindow(40))
    for i = 1, 100 do
      ledger:addOwn(entry(i, T0 + i))
      if i == 39 or i == 40 then
        assert.equal(i, #ledger:shareWindow(40))
      end
    end
    local window = ledger:shareWindow(40)
    assert.equal(40, #window)
    assert.equal(61, window[1].inn)
    assert.equal(100, window[40].inn)
    assert.same({}, ledger:shareWindow(0))
    assert.same({}, ledger:shareWindow(0 / 0))
    assert.same({}, ledger:shareWindow(nil))
    assert.equal(100, #ledger:shareWindow(math.huge))
  end)

  it("signerEntries of an unknown GUID is empty", function()
    assert.same({}, ledger:signerEntries(MIRA))
    assert.same({}, ledger:signerEntries(nil))
    assert.same({}, ledger:signerEntries(hostileTable()))
  end)

  it("innEntries splits own and foreign, each in order", function()
    ledger:addOwn(entry(7, T0 + 50))
    ledger:addOwn(entry(7, ANCHOR + WEEK))
    ledger:addOwn(entry(8, T0))
    ledger:addForeign("Player-1-B0", "Bran", entry(7, T0), NOW)
    ledger:addForeign("Player-1-A0", "Anna", entry(7, T0), NOW)
    ledger:addForeign(MIRA, NAME, entry(7, T0 - 10), NOW)
    ledger:addForeign(MIRA, NAME, entry(8, T0 - 10), NOW)
    local got = ledger:innEntries(7)
    assert.same({ entry(7, T0 + 50), entry(7, ANCHOR + WEEK) }, got.own)
    assert.same({
      { signer = MIRA, name = NAME, entry = entry(7, T0 - 10) },
      { signer = "Player-1-A0", name = "Anna", entry = entry(7, T0) },
      { signer = "Player-1-B0", name = "Bran", entry = entry(7, T0) },
    }, got.foreign)
    assert.same({ own = {}, foreign = {} }, ledger:innEntries(1))
    assert.same({ own = {}, foreign = {} }, ledger:innEntries(0 / 0))
  end)

  it("travelers are ordered by met descending, then GUID", function()
    ledger:addForeign("Player-1-C0", "Cara", entry(1, T0), NOW)
    ledger:addForeign("Player-1-B0", "Bran", entry(1, T0 + 1), NOW + 10)
    ledger:addForeign("Player-1-A0", "Anna", entry(1, T0 + 2), NOW)
    local order = {}
    for _, tr in ipairs(ledger:travelers()) do
      order[#order + 1] = tr.guid
    end
    assert.same({ "Player-1-B0", "Player-1-A0", "Player-1-C0" }, order)
    assert.same({ own = 0, foreign = 3, travelers = 3 }, ledger:counts())
    assert.equal(OWNER, ledger:ownerGUID())
  end)

  it("returns new arrays", function()
    ledger:addOwn(entry(1, T0))
    local own = ledger:own()
    own[1] = nil
    assert.equal(1, #ledger:own())
  end)

  it("has() is false for bad arguments", function()
    ledger:addOwn(entry(1, T0))
    assert.is_false(ledger:has(nil, 1, T0))
    assert.is_false(ledger:has(OWNER, "1", T0))
    assert.is_false(ledger:has(OWNER, 1, 0 / 0))
    assert.is_false(ledger:has(hostileTable(), 1, T0))
  end)
end)

describe("Ledger cosmetics", function()
  local ledger
  before_each(function()
    ledger = newLedger()
  end)

  it("markEarned records and keeps the earliest time", function()
    assert.is_true(ledger:markEarned(12, T0 + 100))
    assert.equal(T0 + 100, ledger:earnedAt(12))
    assert.is_true(ledger:markEarned(12, T0 + 500))
    assert.equal(T0 + 100, ledger:earnedAt(12))
    assert.is_true(ledger:markEarned(12, T0))
    assert.equal(T0, ledger:earnedAt(12))
    assert.is_nil(ledger:earnedAt(13))
    assert.is_nil(ledger:earnedAt(0 / 0))
    local earned = ledger:earned()
    assert.same({ [12] = T0 }, earned)
    earned[12] = 1
    assert.equal(T0, ledger:earnedAt(12))
  end)

  it("markEarned rejects bad IDs and times", function()
    for _, id in ipairs({ 0, LIMITS.cosmeticIdMax + 1, 1.5, 0 / 0, math.huge, "12" }) do
      assert.is_false(ledger:markEarned(id, T0))
    end
    for _, t in ipairs({ LIMITS.tMin - 1, LIMITS.tMax + 1, 0 / 0, T0 + 0.5, "1" }) do
      assert.is_false(ledger:markEarned(12, t))
    end
    assert.is_false(ledger:markEarned(nil, T0))
    assert.same({}, ledger:earned())
  end)

  it("setOwnerName stores a valid name only", function()
    local data = {}
    local l = newLedger(data)
    assert.is_true(l:setOwnerName("Aldric Newname"))
    assert.equal("Aldric Newname", data.me.name)
    assert.is_false(l:setOwnerName("Bad|Name"))
    assert.equal("Aldric Newname", data.me.name)
  end)
end)

describe("Ledger load", function()
  it("initializes an empty table as schema 1 with all six fields", function()
    local data = {}
    local ledger = newLedger(data)
    assert.is_false(ledger.readOnly)
    assert.same({
      schema = 1, me = { name = "Aldric Stonebrook" }, own = {}, travelers = {}, earned = {},
      quarantine = {},
    }, data)

    local unnamed = {}
    Ledger.new(unnamed, { guid = OWNER, name = "Bad|Name" }, ANCHOR)
    assert.same({}, unnamed.me)
  end)

  it("round trip: reopening the same table gives identical queries", function()
    local data = {}
    local a = newLedger(data)
    a:addOwn(entry(1234, T0, { 1, 22, 3 }))
    a:addOwn(entry(98765, T0 + 100, { 7 }, 12))
    a:addForeign(MIRA, NAME, entry(1234, T0 + 50, { 4, 5 }, 2), NOW)
    a:addForeign(guid(1), "Bran", entry(98765, T0 + 60), NOW + 5)
    a:markEarned(12, T0 + 500)

    local b = newLedger(data)
    assert.is_false(b.readOnly)
    for _, q in ipairs({ "own", "travelers", "counts", "earned" }) do
      assert.same(a[q](a), b[q](b), q)
    end
    assert.same(a:shareWindow(40), b:shareWindow(40))
    assert.same(a:signerEntries(MIRA), b:signerEntries(MIRA))
    assert.same(a:innEntries(1234), b:innEntries(1234))
    assert.is_true(b:has(MIRA, 1234, T0 + 50))
    assert.is_false(b:canSign(1234, T0 + 1))
    assert.same({
      migrated = false, foreignDropped = 0, travelersDropped = 0, metReset = 0,
      earnedDropped = 0, quarantined = 0, quarantineDropped = 0, nameReset = 0,
      duplicates = 0, weekly = 0, evicted = 0,
    }, b.loadReport)
  end)

  it("errors on an invalid owner", function()
    for _, owner in ipairs({ { guid = "player-1-AB", name = NAME }, { name = NAME }, "x" }) do
      assert.has_error(function() Ledger.new({}, owner, ANCHOR) end)
    end
    assert.has_error(function() Ledger.new({}, nil, ANCHOR) end)
  end)
end)

describe("Ledger read-only", function()
  local function validV1()
    return {
      schema = 1,
      me = { name = "Aldric Stonebrook" },
      own = { entry(1234, T0, { 1, 22, 3 }) },
      travelers = {
        [MIRA] = { name = NAME, met = NOW, entries = { entry(1234, T0 + 50, { 4, 5 }, 2) } },
      },
      earned = { [12] = T0 + 500 },
      quarantine = {},
    }
  end

  -- Opens `data` read-only, tries every write, and checks `data` never changed.
  local function openReadOnly(data)
    local before = deepcopy(data)
    local ledger = newLedger(data)
    assert.is_true(ledger.readOnly)
    assert.equal("readonly", ledger:addOwn(entry(4321, T0 + WEEK)))
    assert.equal("readonly", ledger:addForeign(guid(9), NAME, entry(4321, T0), NOW))
    assert.is_false(ledger:markEarned(13, T0))
    assert.is_false(ledger:setOwnerName("Aldric Other"))
    assert.is_false(ledger:canSign(4321, T0 + 2 * WEEK))
    assert.same(before, data)
    return ledger
  end

  it("a non-table saved value gives an empty read-only ledger", function()
    for _, v in ipairs({ "x", 5, true }) do
      local ledger = openReadOnly(v)
      assert.same({ own = 0, foreign = 0, travelers = 0 }, ledger:counts())
      assert.equal("not_table", ledger.loadReport.reason)
    end
    assert.is_true(Ledger.new(false, OWNER_INFO, ANCHOR).readOnly)
  end)

  it("schema 2 (a newer AddOn's data) opens read-only and still answers", function()
    local data = validV1()
    data.schema = 2
    local ledger = openReadOnly(data)
    assert.equal("newer_schema", ledger.loadReport.reason)
    assert.same({ entry(1234, T0, { 1, 22, 3 }) }, ledger:own())
    assert.equal(1, #ledger:signerEntries(MIRA))
  end)

  it("a non-empty table with a missing or non-integer schema opens read-only", function()
    for _, schema in ipairs({ "1", 1.5, 0, -1, {} }) do
      local data = validV1()
      data.schema = schema
      assert.equal("bad_schema", openReadOnly(data).loadReport.reason)
    end
    local data = validV1()
    data.schema = nil
    assert.equal("bad_schema", openReadOnly(data).loadReport.reason)
    assert.equal("bad_schema", openReadOnly({ junk = true }).loadReport.reason)

    -- NaN never deep-compares equal, so check that case by hand.
    data = validV1()
    data.schema = 0 / 0
    local ownBefore = data.own
    local ledger = newLedger(data)
    assert.is_true(ledger.readOnly)
    assert.equal("readonly", ledger:addOwn(entry(4321, T0)))
    assert.is_true(data.schema ~= data.schema)
    assert.equal(ownBefore, data.own)
    assert.equal(1, #data.own)
  end)

  it("schema 1 with a top-level field of the wrong type opens read-only", function()
    for _, field in ipairs({ "own", "travelers", "earned", "quarantine", "me" }) do
      for _, bad in ipairs({ "a string", false }) do
        local data = validV1()
        data[field] = bad
        assert.equal("bad_field", openReadOnly(data).loadReport.reason, field)
      end
    end
  end)

  it("answers queries from the sound parts of a damaged ledger", function()
    local data = validV1()
    data.earned = "junk"
    data.travelers[MIRA].entries[2] = { inn = "bad" }
    data.own[2] = entry(99, T0 + WEEK)
    data.own[3] = "junk"
    data.own.stray = entry(55, T0 + 2 * WEEK) -- a non-array key still holds an entry
    local ledger = openReadOnly(data)
    assert.equal(3, #ledger:own())
    assert.equal(55, ledger:own()[3].inn)
    assert.same({ entry(1234, T0 + 50, { 4, 5 }, 2) }, ledger:signerEntries(MIRA))
    assert.same({}, ledger:earned())
    assert.equal(1, ledger.loadReport.foreignDropped)
    assert.equal(1, ledger.loadReport.quarantineDropped)
  end)

  it("copies cyclic saved tables without looping or touching them", function()
    local data = validV1()
    data.schema = 2
    local loop = { note = "cyclic" }
    loop.self = loop
    data.quarantine = { loop, loop }
    local ledger = newLedger(data)
    assert.is_true(ledger.readOnly)
    assert.equal(loop, data.quarantine[1])
    assert.equal(loop, loop.self)
    assert.is_nil(next(loop, next(loop, next(loop))))
    assert.equal(1, #ledger:own())
  end)
end)

describe("Ledger normalize", function()
  local function base()
    return { schema = 1, me = { name = "Aldric" }, own = {}, travelers = {}, earned = {},
      quarantine = {} }
  end

  it("drops invalid foreign entries and bad traveler records", function()
    local data = base()
    data.travelers = {
      [MIRA] = { name = NAME, met = NOW, entries = {
        entry(1, T0), { inn = 0, t = T0, phrase = { 1 } }, "junk", entry(2, T0, { 1 }, 0),
      } },
      ["player-1-AB"] = { name = NAME, met = NOW, entries = { entry(1, T0) } },
      [OWNER] = { name = NAME, met = NOW, entries = { entry(1, T0) } },
      ["Player-1-C0"] = { name = "Bad|Name", met = NOW, entries = { entry(1, T0) } },
      ["Player-1-D0"] = { name = NAME, met = NOW, entries = { { inn = 1 } } },
      ["Player-1-E0"] = { name = NAME, met = NOW, entries = "junk" },
      ["Player-1-F0"] = "junk",
      [5] = { name = NAME, met = NOW, entries = { entry(1, T0) } },
    }
    local ledger = newLedger(data)
    assert.is_false(ledger.readOnly)
    assert.same({ [MIRA] = { name = NAME, met = NOW, entries = { entry(1, T0) } } },
      data.travelers)
    assert.equal(4, ledger.loadReport.foreignDropped)
    assert.equal(7, ledger.loadReport.travelersDropped)
    assertConsistent(ledger)
  end)

  it("a bad met becomes the oldest entry's time", function()
    local bad = { "x", LIMITS.tMin - 1, 0 / 0, NOW + 0.5, false }
    for i = 1, #bad do
      local met = bad[i] or nil -- `false` stands in for a missing met
      local data = base()
      data.travelers[MIRA] = { name = NAME, met = met,
        entries = { entry(2, T0 + 9), entry(1, T0 + 3) } }
      local ledger = newLedger(data)
      assert.equal(T0 + 3, data.travelers[MIRA].met)
      assert.equal(T0 + 3, ledger:travelers()[1].met)
      assert.equal(1, ledger.loadReport.metReset)
    end
  end)

  it("drops bad earned pairs", function()
    local data = base()
    data.earned = { [12] = T0, [0] = T0, [13] = LIMITS.tMin - 1, x = T0, [1.5] = T0,
      [14] = "t", [LIMITS.cosmeticIdMax] = LIMITS.tMax }
    local ledger = newLedger(data)
    assert.same({ [12] = T0, [LIMITS.cosmeticIdMax] = LIMITS.tMax }, ledger:earned())
    assert.same({ [12] = T0, [LIMITS.cosmeticIdMax] = LIMITS.tMax }, data.earned)
    assert.equal(5, ledger.loadReport.earnedDropped)
  end)

  it("quarantines invalid own entries, at most 100", function()
    local data = base()
    data.quarantine = { { inn = "old" }, "not a table" }
    data.own = { entry(1, T0) }
    for i = 1, 105 do
      data.own[#data.own + 1] = { inn = i }
    end
    data.own[#data.own + 1] = "junk"
    local ledger = newLedger(data)
    assert.equal(1, ledger:counts().own)
    assert.equal(100, #data.quarantine)
    assert.same({ inn = "old" }, data.quarantine[1])
    assert.same({ inn = 1 }, data.quarantine[2])
    assert.equal(99, ledger.loadReport.quarantined)
    assert.equal(1 + 6 + 1, ledger.loadReport.quarantineDropped)
  end)

  it("resets a bad me.name to the owner's name, or removes it", function()
    local data = base()
    data.me.name = "Bad|Name"
    local ledger = newLedger(data)
    assert.equal("Aldric Stonebrook", data.me.name)
    assert.equal(1, ledger.loadReport.nameReset)

    data = base()
    data.me.name = 5
    Ledger.new(data, { guid = OWNER, name = "Bad|Name" }, ANCHOR)
    assert.is_nil(data.me.name)
  end)

  it("removes duplicates (first kept) and sorts", function()
    local data = base()
    data.own = { entry(3, T0 + 9), entry(1, T0, { 5 }), entry(2, T0 + 1), entry(1, T0, { 6 }) }
    data.travelers[MIRA] = { name = NAME, met = NOW, entries = {
      entry(8, T0 + 7), entry(7, T0 + 2, { 5 }), entry(7, T0 + 2, { 6 }),
    } }
    local ledger = newLedger(data)
    assert.same({ entry(1, T0, { 5 }), entry(2, T0 + 1), entry(3, T0 + 9) }, data.own)
    assert.same({ entry(7, T0 + 2, { 5 }), entry(8, T0 + 7) }, data.travelers[MIRA].entries)
    assert.equal(2, ledger.loadReport.duplicates)
    assert.is_true(ledger:has(OWNER, 3, T0 + 9))
  end)

  it("drops a signer's second foreign entry at one inn in one week, keeps own ones", function()
    local data = base()
    data.own = { entry(7, T0 + DAY), entry(7, T0) }
    data.travelers[MIRA] = { name = NAME, met = NOW, entries = {
      entry(7, T0 + DAY), entry(7, T0), entry(7, T0 + WEEK),
    } }
    data.travelers[guid(1)] = { name = NAME, met = NOW, entries = { entry(7, T0 + DAY) } }
    local ledger = newLedger(data)
    assert.equal(2, #ledger:own())
    assert.same({ entry(7, T0), entry(7, T0 + WEEK) }, ledger:signerEntries(MIRA))
    assert.equal(1, #ledger:signerEntries(guid(1)))
    assert.equal(1, ledger.loadReport.weekly)
    assert.is_false(ledger:canSign(7, T0))
  end)

  it("re-applies the caps: 60 / 200 / 3 500 end at 40 / 150 / 3 000, oldest removed", function()
    local data = base()
    local s1 = "Player-1-51"
    local e1 = {}
    for i = 1, 60 do
      e1[i] = entry(1000 + i, T0 + 100000 + i)
    end
    data.travelers[s1] = { name = NAME, met = NOW, entries = e1 }
    for k = 1, 200 do
      data.travelers[guid(k)] = { name = NAME, met = NOW,
        entries = { entry(7, T0 + 200000 + k) } }
    end
    for m = 1, 81 do
      local es = {}
      for j = 1, 40 do
        es[j] = entry(10000 + m * 100 + j, T0 + m * 100 + j)
      end
      data.travelers[guid(1000 + m)] = { name = NAME, met = NOW, entries = es }
    end

    local ledger = newLedger(data)
    assert.equal(3000, ledger:counts().foreign)
    local s1Entries = ledger:signerEntries(s1)
    assert.equal(40, #s1Entries)
    assert.equal(1021, s1Entries[1].inn)
    local inn7 = ledger:innEntries(7).foreign
    assert.equal(150, #inn7)
    assert.equal(guid(51), inn7[1].signer)
    for m = 1, 10 do
      assert.same({}, ledger:signerEntries(guid(1000 + m)))
    end
    assert.equal(10, #ledger:signerEntries(guid(1011)))
    assert.equal(40, #ledger:signerEntries(guid(1012)))
    assert.equal(500, ledger.loadReport.evicted)
    assert.equal(1 + 150 + 71, ledger:counts().travelers)
    assertConsistent(ledger)
    -- The saved table matches what the ledger holds.
    assert.is_nil(data.travelers[guid(1)])
    assert.equal(40, #data.travelers[s1].entries)
  end)
end)

describe("Ledger migration", function()
  local function v1()
    return {
      schema = 1,
      me = { name = "Aldric" },
      own = { entry(1234, T0) },
      travelers = { [MIRA] = { name = NAME, met = NOW, entries = { entry(1234, T0 + 1) } } },
      earned = { [12] = T0 },
      quarantine = {},
    }
  end

  it("migrates a v1 table in place with a fake MIGRATIONS[1]", function()
    local L = fresh()
    L.SCHEMA = 2
    L.MIGRATIONS[1] = function(d)
      d.schema = 2
      d.me.migrated = true
    end
    local data = v1()
    local me = data.me
    local ledger = newLedger(data, nil, L)
    assert.is_false(ledger.readOnly)
    assert.is_true(ledger.loadReport.migrated)
    assert.equal(2, data.schema)
    assert.is_true(data.me.migrated)
    assert.are_not.equal(me, data.me) -- the copy's tables, written into the same object
    assert.equal(1, ledger:counts().own)
    assert.equal("added", ledger:addOwn(entry(4321, T0)))
    assert.equal(2, #data.own)

    local empty = {}
    newLedger(empty, nil, L)
    assert.equal(2, empty.schema)
  end)

  it("chains migrations from 1 to SCHEMA", function()
    local L = fresh()
    L.SCHEMA = 3
    local ran = {}
    L.MIGRATIONS[1] = function(d) ran[#ran + 1] = 1; d.schema = 2 end
    L.MIGRATIONS[2] = function(d) ran[#ran + 1] = 2; d.schema = 3 end
    local data = v1()
    assert.is_false(newLedger(data, nil, L).readOnly)
    assert.same({ 1, 2 }, ran)
    assert.equal(3, data.schema)
  end)

  it("a migration that throws halfway leaves the table unchanged and read-only", function()
    local L = fresh()
    L.SCHEMA = 2
    L.MIGRATIONS[1] = function(d)
      d.own = nil
      d.me.name = "Changed"
      error("boom")
    end
    local data = v1()
    local before = deepcopy(data)
    local me = data.me
    local ledger = newLedger(data, nil, L)
    assert.is_true(ledger.readOnly)
    assert.equal("migration_failed", ledger.loadReport.reason)
    assert.same(before, data)
    assert.equal(me, data.me)
    assert.equal(1, #ledger:own())
  end)

  it("a migration that leaves the wrong schema or shape doesn't count", function()
    for _, bad in ipairs({
      function() end,
      function(d) d.schema = 2; d.own = "x" end,
    }) do
      local L = fresh()
      L.SCHEMA = 2
      L.MIGRATIONS[1] = bad
      local data = v1()
      local before = deepcopy(data)
      assert.is_true(newLedger(data, nil, L).readOnly)
      assert.same(before, data)
    end
    local L = fresh()
    L.SCHEMA = 2
    local data = v1()
    assert.is_true(newLedger(data, nil, L).readOnly) -- MIGRATIONS[1] missing
  end)
end)

describe("Ledger.innFromNpcGUID", function()
  local inns = { [1234] = true, [9999999] = true, [12345678] = true }

  it("returns the NPC ID of a known inn's creature GUID", function()
    assert.equal(1234, Ledger.innFromNpcGUID("Creature-0-3767-0-1-1234-0000ABCDEF", inns))
    assert.equal(9999999, Ledger.innFromNpcGUID("Creature-0-1-2-3-9999999-00AB", inns))
  end)

  it("returns nil for anything else", function()
    for _, g in ipairs({
      "Creature-0-3767-0-1-4321-0000ABCDEF",   -- unknown NPC ID
      "Player-0-3767-0-1-1234-0000ABCDEF",
      "Pet-0-3767-0-1-1234-0000ABCDEF",
      "Vehicle-0-3767-0-1-1234-0000ABCDEF",
      "Creature-0-3767-0-1-1234",              -- no spawn part
      "Creature-0-3767-0-1234-0000ABCDEF",     -- a field short
      "Creature-0-3767-0-1-1234-0000ABCDEF-1",
      "Creature-0-3767-0-1-12345678-0000AB",   -- 8 digits, even though it's a key
      "Creature-0-3767-0-1-01234-0000AB",      -- leading zero
      "Creature-0-3767-0-1-0-0000AB",
      "",
    }) do
      assert.is_nil(Ledger.innFromNpcGUID(g, inns), g)
    end
    assert.is_nil(Ledger.innFromNpcGUID(nil, inns))
    assert.is_nil(Ledger.innFromNpcGUID(1234, inns))
    assert.is_nil(Ledger.innFromNpcGUID("Creature-0-3767-0-1-1234-0000ABCDEF", nil))
  end)

  it("returns nil for the hidden-value stand-ins without throwing", function()
    assert.is_nil(Ledger.innFromNpcGUID(hostileTable(), inns))
    assert.is_nil(Ledger.innFromNpcGUID(hostileProxy(), inns))
    assert.is_nil(Ledger.innFromNpcGUID("Creature-0-3767-0-1-1234-0000ABCDEF", hostileTable()))
  end)
end)
