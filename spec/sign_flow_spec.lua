-- SignFlow: when the button shows, the checks and their order, the seals offered, the
-- commit, unlock recording, the draft model and the chat lines (docs/specs/sign.md 6.2).
-- Pure files in the strict environment, fixed times only. Client values arrive here as
-- arguments, so every one of them gets malformed and hidden-value stand-ins too.
local load = require("helpers.load")
local fx = require("helpers.places")

local WEEK = 604800
local ANCHOR = 1790089200            -- Tuesday 2026-09-22 15:00 UTC
local NOW = ANCHOR + 10 * WEEK + 1000
local RESET = ANCHOR + 11 * WEEK     -- the weekly reset after NOW
local OWNER = "Player-1-0000AAAA"
local OWNER_NAME = "Aldric Stonebrook"
local PEER = "Player-1-0000BBBB"

-- A fresh ns in TOC order; `data` adds the shipped Data tables.
local function modules(data)
  local ns = {}
  load.file("Ledger.lua", ns, load.pure_env())
  if data then
    load.file("Data/Inns.lua", ns, load.pure_env())
    load.file("Data/Phrases.lua", ns, load.pure_env())
    load.file("Data/Cosmetics.lua", ns, load.pure_env())
  end
  for _, path in ipairs({ "Phrase.lua", "Collection.lua", "Cosmetics.lua", "SyncProtocol.lua",
    "SignFlow.lua" }) do
    load.file(path, ns, load.pure_env())
  end
  return ns
end

local NS = modules(false)
local REAL = modules(true)
local SignFlow, Ledger, SP = NS.SignFlow, NS.Ledger, NS.SyncProtocol
local LIMITS = Ledger.LIMITS

-- The phrase fixture of docs/specs/phrase.md 6.
local function phraseData()
  return {
    [1] = { kind = "template", text = "Here's to {w}!" },
    [2] = { kind = "template", text = "Rest well." },
    [500] = { kind = "conj", text = "And then..." },
    [1000] = { kind = "word", cat = 1, text = "the hearth" },
    [1100] = { kind = "word", cat = 2, text = "hot stew" },
  }, { "Home", "Food" }
end

-- Fixture deps: places F, the phrase fixture, catalog C. `over` replaces any of them.
local function deps(over)
  local inns, zones, conts = fx.places()
  local atlas = NS.Collection.bind(inns, zones, conts)
  assert(#atlas.invalid == 0)
  local d = {
    inns = inns,
    atlas = atlas,
    phrase = NS.Phrase.bind(phraseData()),
    cosmetics = NS.Cosmetics.bind(atlas, fx.catalog()),
  }
  for k, v in pairs(over or {}) do
    d[k] = v
  end
  return d
end

local function newFlow(over)
  return SignFlow.new(deps(over))
end

local function realFlow()
  return REAL.SignFlow.new({
    inns = REAL.Data.Inns, atlas = REAL.Collection.atlas, phrase = REAL.Phrase,
    cosmetics = REAL.Cosmetics,
  })
end

local function npcGUID(id)
  return "Creature-0-4615-2991-62-" .. id .. "-0000ABCDEF"
end

local function newLedger(data, guid)
  return Ledger.new(data or {}, { guid = guid or OWNER, name = OWNER_NAME }, ANCHOR)
end

-- A saved ledger table with these own entries and `earned`.
local function savedData(own, earned)
  return { schema = 1, me = {}, own = own or {}, travelers = {}, earned = earned or {},
    quarantine = {} }
end

local function entry(inn, t, phrase, seal)
  return { inn = inn, t = t, phrase = phrase or { 2 }, seal = seal }
end

-- A situation where signing at Vale Inn (5001) works.
local function sit(over)
  local s = { ledger = newLedger(), npc = npcGUID(5001), resting = true, now = NOW,
    faction = "Alliance" }
  for k, v in pairs(over or {}) do
    s[k] = v
  end
  return s
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

-- A ledger stand-in that answers like `real` but returns `addResult` from addOwn
-- ("raise" raises) and counts every call.
local function fakeLedger(addResult)
  local real = newLedger()
  local calls = {}
  local fake = { readOnly = false }
  for _, m in ipairs({ "canSign", "nextWeekStart", "own", "earned", "earnedAt" }) do
    fake[m] = function(_, ...)
      calls[m] = (calls[m] or 0) + 1
      return real[m](real, ...)
    end
  end
  fake.addOwn = function()
    calls.addOwn = (calls.addOwn or 0) + 1
    if addResult == "raise" then
      error("addOwn raised")
    end
    return addResult
  end
  fake.markEarned = function()
    calls.markEarned = (calls.markEarned or 0) + 1
    return true
  end
  return fake, real, calls
end

local function raise()
  error("raised on purpose")
end

-- Values that are no valid argument anywhere, the two hidden-value stand-ins included.
local function badValues()
  return { false, 1, 0 / 0, 1 / 0, "x", {}, fx.hostileTable(), fx.hostileProxy(),
    function() end }
end

local function hasPipe(v)
  return type(v) == "string" and v:find("|", 1, true) ~= nil
end

-- ---------------------------------------------------------------------------

describe("SignFlow.new", function()
  it("loads in the strict environment and builds a flow over fixtures and the real data", function()
    assert.is_table(SignFlow)
    assert.is_table(newFlow())
    assert.is_table(realFlow())
  end)

  it("raises without ns.Ledger", function()
    assert.has_error(function()
      load.file("SignFlow.lua", {}, load.pure_env())
    end)
  end)

  it("raises without deps or any of its tables", function()
    assert.has_error(function() SignFlow.new(nil) end)
    for _, bad in ipairs({ 1, "x" }) do
      assert.has_error(function() SignFlow.new(bad) end)
    end
    for _, key in ipairs({ "inns", "atlas", "phrase", "cosmetics" }) do
      local d = deps()
      d[key] = nil
      assert.has_error(function() SignFlow.new(d) end, nil, key)
      d[key] = "x"
      assert.has_error(function() SignFlow.new(d) end, nil, key)
    end
  end)

  it("raises when any function it needs is missing", function()
    local needs = {
      atlas = { "innOf", "inn" },
      phrase = { "validIds", "render", "compose", "text", "hasSlot", "templates",
        "conjunctions", "categories", "words" },
      cosmetics = { "unlocked", "canSeal", "info", "SEALS" },
    }
    for key, names in pairs(needs) do
      for _, name in ipairs(names) do
        local d = deps()
        local copy = {}
        for k, v in pairs(d[key]) do
          copy[k] = v
        end
        copy[name] = nil
        d[key] = copy
        assert.has_error(function() SignFlow.new(d) end, nil, key .. "." .. name)
      end
    end
  end)
end)

describe("flow.innAt and flow.innName", function()
  local flow = newFlow()

  it("finds a known primary and an alias, which shows its primary's name", function()
    assert.equal(5001, flow.innAt(npcGUID(5001)))
    assert.equal("Vale Inn", flow.innName(5001))
    assert.equal(5003, flow.innAt(npcGUID(5003)))
    assert.equal("Vale Inn", flow.innName(5003))
    assert.equal("Ridge Inn", flow.innName(5301))
  end)

  it("gives nil for an unknown NPC, and for a record Collection.bind excluded", function()
    assert.is_nil(flow.innAt(npcGUID(7777)))
    assert.is_nil(flow.innName(7777))
    local inns, zones, conts = fx.places()
    inns[5999] = { name = "Bad|Inn", zone = 10 }
    local atlas = NS.Collection.bind(inns, zones, conts)
    assert.same({ "inn 5999" }, atlas.invalid)
    local f = newFlow({ inns = inns, atlas = atlas })
    assert.equal(5999, Ledger.innFromNpcGUID(npcGUID(5999), inns))
    assert.is_nil(f.innAt(npcGUID(5999)))
    assert.is_nil(f.innName(5999))
  end)

  it("gives nil for every malformed GUID, with no throw", function()
    local bad = {
      "Player-1-00000001",
      "Pet-0-4615-2991-62-5001-0000ABCDEF",
      "Vehicle-0-4615-2991-62-5001-0000ABCDEF",
      "Creature-0-4615-2991-62-05001-0000ABCDEF",
      "Creature-0-4615-2991-62-12345678-0000ABCDEF",
      "Creature-0-4615-2991-62-5001",
      "Creature-0-4615-2991-62-5001-0000ABCDEF ",
      "", 5001, {}, nil, fx.hostileTable(), fx.hostileProxy(),
    }
    for i = 1, 13 do
      assert.is_nil(flow.innAt(bad[i]), tostring(i))
    end
    for _, v in ipairs(badValues()) do
      assert.is_nil(flow.innName(v))
    end
  end)
end)

describe("flow.check", function()
  local flow = newFlow()

  it("passes a good situation with the inn and its name", function()
    assert.same({ ok = true, inn = 5001, name = "Vale Inn" }, flow.check(sit()))
    assert.same({ ok = true, inn = 5003, name = "Vale Inn" },
      flow.check(sit({ npc = npcGUID(5003) })))
  end)

  it("no_ledger: no situation, no ledger, a ledger that isn't a table", function()
    assert.same({ ok = false, reason = "no_ledger" }, flow.check(nil))
    local s = sit()
    s.ledger = nil
    assert.same({ ok = false, reason = "no_ledger" }, flow.check(s))
    assert.same({ ok = false, reason = "no_ledger" }, flow.check(sit({ ledger = "x" })))
  end)

  it("readonly: a damaged or newer ledger, even when also not resting", function()
    local damaged = newLedger("x")
    local newer = newLedger({ schema = 99, own = {} })
    assert.is_true(damaged.readOnly)
    assert.is_true(newer.readOnly)
    for _, ledger in ipairs({ damaged, newer }) do
      assert.same({ ok = false, reason = "readonly" }, flow.check(sit({ ledger = ledger })))
      assert.same({ ok = false, reason = "readonly" },
        flow.check(sit({ ledger = ledger, resting = false, now = "x" })))
    end
  end)

  it("not_inn: an unknown NPC or no NPC", function()
    assert.same({ ok = false, reason = "not_inn" }, flow.check(sit({ npc = npcGUID(7777) })))
    local s = sit()
    s.npc = nil
    assert.same({ ok = false, reason = "not_inn" }, flow.check(s))
  end)

  it("clock: a missing, fractional or out-of-range time", function()
    for _, now in ipairs({ 0 / 0, 1.5, LIMITS.tMin - 1, LIMITS.tMax + 1, "1800000000",
      1 / 0 }) do
      assert.same({ ok = false, reason = "clock" }, flow.check(sit({ now = now })))
    end
    local s = sit()
    s.now = nil
    assert.same({ ok = false, reason = "clock" }, flow.check(s))
  end)

  it("too_soon with the wait to the reset; a second before it; ok at it", function()
    local ledger = newLedger()
    assert.equal("added", ledger:addOwn(entry(5001, NOW - 10)))
    local res = flow.check(sit({ ledger = ledger }))
    assert.same({ ok = false, reason = "too_soon", wait = RESET - NOW }, res)
    assert.equal(ledger:nextWeekStart(NOW) - NOW, res.wait)
    assert.same({ ok = false, reason = "too_soon", wait = 1 },
      flow.check(sit({ ledger = ledger, now = RESET - 1 })))
    assert.is_true(flow.check(sit({ ledger = ledger, now = RESET })).ok)
  end)

  it("too_soon comes before not_resting", function()
    local ledger = newLedger()
    ledger:addOwn(entry(5001, NOW - 10))
    assert.equal("too_soon", flow.check(sit({ ledger = ledger, resting = false })).reason)
  end)

  it("not_resting: anything but exactly true", function()
    for _, r in ipairs({ false, 1, "true", fx.hostileTable(), fx.hostileProxy() }) do
      assert.same({ ok = false, reason = "not_resting" }, flow.check(sit({ resting = r })))
    end
    local s = sit()
    s.resting = nil
    assert.same({ ok = false, reason = "not_resting" }, flow.check(s))
  end)

  it("another inn signed this week doesn't block this one", function()
    local ledger = newLedger()
    ledger:addOwn(entry(5201, NOW - 10))
    assert.is_true(flow.check(sit({ ledger = ledger })).ok)
  end)

  it("a ledger whose methods raise gives error", function()
    local ledger = { readOnly = false, canSign = raise }
    assert.same({ ok = false, reason = "error" }, flow.check(sit({ ledger = ledger })))
  end)
end)

describe("flow.seals", function()
  local flow = newFlow()

  it("is empty with nothing unlocked", function()
    assert.same({}, flow.seals(sit()))
  end)

  it("offers a seal only from its unlock time, so the signature earning it can't use it", function()
    local s = sit({ npc = npcGUID(5002) })
    assert.equal("added", flow.commit(sit({ ledger = s.ledger }), 5001, { 2 }, nil).result)
    -- Seal 1 (2 inns) and zone seal 101 (5001 + 5002) come with this signature, not before.
    assert.same({}, flow.seals(s))
    assert.same({ result = "seal" }, flow.commit(s, 5002, { 2 }, 1))
    local res = flow.commit(s, 5002, { 2 }, nil)
    assert.equal("added", res.result)
    assert.same({ 1, 101 }, res.earned)
    assert.same({ 1, 101 }, flow.seals(sit({ ledger = s.ledger, npc = npcGUID(5101) })))
    assert.same({}, flow.seals(sit({ ledger = s.ledger, npc = npcGUID(5101), now = NOW - 1 })))
  end)

  it("never offers a quill or an ink", function()
    local ledger = newLedger(savedData({ entry(5001, NOW - 300), entry(5002, NOW - 200),
      entry(5101, NOW - 100) }))
    local u = NS.Cosmetics.bind(deps().atlas, fx.catalog()).unlocked(ledger:own(), "Alliance")
    local ids = {}
    for _, item in ipairs(u) do
      ids[#ids + 1] = item.id
    end
    table.sort(ids)
    assert.same({ 1, 101, 102, 1001, 1101, 1102 }, ids)
    assert.same({ 1, 101, 102 }, flow.seals(sit({ ledger = ledger, npc = npcGUID(5201) })))
  end)

  it("offers a kept earned floor", function()
    local t1 = NOW - 100
    local kept = newLedger(savedData({ entry(5001, t1) }, { [101] = t1 }))
    assert.same({ 101 }, flow.seals(sit({ ledger = kept, npc = npcGUID(5101) })))
    local plain = newLedger(savedData({ entry(5001, t1) }))
    assert.same({}, flow.seals(sit({ ledger = plain, npc = npcGUID(5101) })))
  end)

  it("is empty when check fails", function()
    local ledger = newLedger(savedData({ entry(5101, NOW - 100) }))
    assert.same({ 102 }, flow.seals(sit({ ledger = ledger })))
    assert.same({}, flow.seals(sit({ ledger = ledger, resting = false })))
    assert.same({}, flow.seals(sit({ ledger = ledger, npc = npcGUID(5101) }))) -- too_soon
  end)

  it("counts a hostile faction as none", function()
    local ledger = newLedger(savedData({ entry(5201, NOW - 100) }))
    -- Dune Inn is all of the Dunes for Alliance; with no faction, Oasis Inn counts too.
    assert.same({ 103 }, flow.seals(sit({ ledger = ledger })))
    for _, f in ipairs({ "Horde ", fx.hostileTable(), fx.hostileProxy(), 1 }) do
      assert.same({}, flow.seals(sit({ ledger = ledger, faction = f })))
    end
    local s = sit({ ledger = ledger })
    s.faction = nil
    assert.same({}, flow.seals(s))
  end)
end)

describe("flow.commit", function()
  local flow = newFlow()

  it("adds the entry, independent of the caller's table, and lists the new unlocks", function()
    local s = sit({ npc = npcGUID(5101) })
    local ids = { 1, 1000 }
    local res = flow.commit(s, 5101, ids, nil)
    assert.equal("added", res.result)
    local want = { inn = 5101, t = NOW, phrase = { 1, 1000 } }
    assert.same(want, res.entry)
    assert.same({ want }, s.ledger:own())
    assert.same({ 102 }, res.earned)
    ids[1], ids[3] = 2, 500
    res.entry.phrase[1] = 2
    assert.same({ want }, s.ledger:own())

    s.npc = npcGUID(5001)
    assert.same({ 1 }, flow.commit(s, 5001, { 2 }, 102).earned)
    s.npc = npcGUID(5002)
    res = flow.commit(s, 5002, { 2 }, 1)
    assert.equal(1, res.entry.seal)
    assert.same({ 101, 1001, 1101, 1102 }, res.earned)
    assert.same({ [1] = NOW, [101] = NOW, [102] = NOW, [1001] = NOW, [1101] = NOW,
      [1102] = NOW }, s.ledger:earned())
    -- Own entries sort by time, then inn: 5001, 5002, 5101.
    assert.same({ inn = 5001, t = NOW, phrase = { 2 }, seal = 102 }, s.ledger:own()[1])
  end)

  it("returns each addOwn refusal as the result and records nothing", function()
    for _, r in ipairs({ "dup", "too_soon", "invalid", "readonly", "raise", "odd", 7 }) do
      local fake, real, calls = fakeLedger(r)
      local res = flow.commit(sit({ ledger = fake }), 5001, { 2 }, nil)
      local want = r
      if r == "raise" or r == "odd" or r == 7 then
        want = "error"
      end
      assert.equal(want, res.result, tostring(r))
      if r == "too_soon" then
        assert.equal(RESET - NOW, res.wait)
      end
      assert.equal(1, calls.addOwn)
      assert.is_nil(calls.markEarned)
      assert.is_nil(calls.earnedAt)
      assert.same({ own = 0, foreign = 0, travelers = 0 }, real:counts())
      assert.same({}, real:earned())
    end
  end)

  it("changed: the gossip closed, another NPC, a hidden GUID, a bad inn argument", function()
    local s = sit()
    for _, npc in ipairs({ npcGUID(5201), npcGUID(5003), npcGUID(7777), fx.hostileTable(),
      fx.hostileProxy() }) do
      s.npc = npc
      assert.same({ result = "changed" }, flow.commit(s, 5001, { 2 }, nil))
    end
    s.npc = nil
    assert.same({ result = "changed" }, flow.commit(s, 5001, { 2 }, nil))
    s.npc = npcGUID(5001)
    for _, inn in ipairs({ 0 / 0, "5001", 5001.5, fx.hostileTable() }) do
      assert.same({ result = "changed" }, flow.commit(s, inn, { 2 }, nil))
    end
    assert.same({ result = "changed" }, flow.commit(s, nil, { 2 }, nil))
    assert.same({}, s.ledger:own())
  end)

  it("no_ledger, readonly and clock at commit", function()
    assert.same({ result = "no_ledger" }, flow.commit(nil, 5001, { 2 }))
    assert.same({ result = "no_ledger" }, flow.commit(sit({ ledger = 1 }), 5001, { 2 }))
    assert.same({ result = "readonly" },
      flow.commit(sit({ ledger = newLedger("x") }), 5001, { 2 }))
    assert.same({ result = "clock" }, flow.commit(sit({ now = 1.5 }), 5001, { 2 }))
  end)

  it("checks again at commit: the reset passed, signed meanwhile, walked out", function()
    local ledger = newLedger()
    ledger:addOwn(entry(5001, NOW - 10))
    local s = sit({ ledger = ledger })
    assert.equal("too_soon", flow.check(s).reason)
    s.now = RESET
    assert.equal("added", flow.commit(s, 5001, { 2 }, nil).result)

    s = sit()
    assert.is_true(flow.check(s).ok)
    s.ledger:addOwn(entry(5001, NOW - 5))
    assert.same({ result = "too_soon", wait = RESET - NOW }, flow.commit(s, 5001, { 2 }, nil))

    s = sit()
    assert.is_true(flow.check(s).ok)
    s.resting = false
    assert.same({ result = "not_resting" }, flow.commit(s, 5001, { 2 }, nil))
    assert.same({}, s.ledger:own())
  end)

  it("phrase: refuses any ids validIds refuses, before addOwn", function()
    local mt = setmetatable({ 1, 1000 }, {})
    local cases = { false, {}, { 1 }, { 1, 1000, 500, 1, 1000, 2 }, { 3 }, { 1, 1000, x = 1 },
      fx.hostileTable(), fx.hostileProxy(), mt, "1.1000", { [2] = 1000 } }
    for i = 0, #cases do
      local fake, _, calls = fakeLedger("added")
      local ids = cases[i] -- cases[0] is nil: compose found nothing
      assert.same({ result = "phrase" }, flow.commit(sit({ ledger = fake }), 5001, ids, nil),
        tostring(i))
      assert.is_nil(calls.addOwn)
    end
  end)

  it("seal: refuses a seal it can't use; a nil seal passes", function()
    -- Seal 1 and zone seal 101 unlock at NOW + 200, after the commit's time.
    local ledger = newLedger(savedData({ entry(5001, NOW + 100), entry(5002, NOW + 200) }))
    local s = sit({ ledger = ledger, npc = npcGUID(5101) })
    for i, seal in ipairs({ 50, 2, 1, 101, 1001, 0, 0 / 0, -1, "1", fx.hostileTable() }) do
      assert.same({ result = "seal" }, flow.commit(s, 5101, { 2 }, seal), "seal case " .. i)
    end
    assert.equal(2, #ledger:own())
    s.now = NOW + 200
    assert.equal("added", flow.commit(s, 5101, { 2 }, 101).result)
    assert.equal(101, ledger:own()[3].seal)
    s.npc = npcGUID(5201)
    assert.equal("added", flow.commit(s, 5201, { 2 }, nil).result)
  end)

  it("a double commit adds one entry", function()
    local s = sit()
    assert.equal("added", flow.commit(s, 5001, { 2 }, nil).result)
    assert.equal("too_soon", flow.commit(s, 5001, { 2 }, nil).result)
    assert.equal(1, #s.ledger:own())
  end)

  it("makes entries a peer stores under the sender, with and without a seal", function()
    local inns = fx.places()
    local data, cats = phraseData()
    local phrase = NS.Phrase.bind(data, cats)
    local d = deps({ inns = inns, phrase = phrase })
    local f = SignFlow.new(d)
    local s = sit({ npc = npcGUID(5101) })
    assert.equal("added", f.commit(s, 5101, { 1, 1000 }, nil).result)
    s.npc = npcGUID(5001)
    assert.equal("added", f.commit(s, 5001, { 2, 500, 1, 1100 }, 102).result)

    local peer = newLedger({}, PEER)
    local ctx = {
      now = NOW, selfGUID = PEER, inns = inns, phrases = data, seals = d.cosmetics.SEALS,
      phraseOk = phrase.validIds, ledger = peer, limiter = SP.newLimiter(),
      wantMemo = SP.newWantMemo(),
    }
    local msgs = SP.encodeEntries(s.ledger:shareWindow(40), 0)
    assert.equal(1, #msgs)
    local res = SP.receive(msgs[1], "PARTY", { guid = OWNER, name = OWNER_NAME }, ctx)
    assert.equal("entries", res.kind)
    assert.equal(2, res.added)
    assert.equal(0, res.rejected)
    assert.same(s.ledger:own(), peer:signerEntries(OWNER))
    assert.equal(102, peer:signerEntries(OWNER)[1].seal)
  end)
end)

describe("flow.recordUnlocks", function()
  local flow = newFlow()

  local function fixtureLedger(earned)
    return newLedger(savedData(fx.entries(), earned))
  end

  it("records every unlock at its derived time, then nothing more", function()
    local ledger = fixtureLedger()
    local u = deps().cosmetics.unlocked(ledger:own(), "Alliance", {})
    assert.is_true(#u > 0)
    local want, ids = {}, {}
    for _, item in ipairs(u) do
      want[item.id] = item.t
      ids[#ids + 1] = item.id
    end
    table.sort(ids)
    assert.same(ids, flow.recordUnlocks(ledger, "Alliance"))
    assert.same(want, ledger:earned())
    local before = deepcopy(ledger.data)
    assert.same({}, flow.recordUnlocks(ledger, "Alliance"))
    assert.same(before, ledger.data)
  end)

  it("keeps an earned time earlier than the derived one", function()
    local ledger = fixtureLedger({ [101] = fx.T })
    local u = deps().cosmetics.unlocked(ledger:own(), "Alliance", {})
    local derived
    for _, item in ipairs(u) do
      if item.id == 101 then
        derived = item.t
      end
    end
    assert.is_true(derived > fx.T)
    local recorded = flow.recordUnlocks(ledger, "Alliance")
    assert.equal(fx.T, ledger:earnedAt(101))
    for _, id in ipairs(recorded) do
      assert.not_equal(101, id)
    end
  end)

  it("writes nothing for a read-only or missing ledger", function()
    local data = savedData(fx.entries())
    data.schema = 2
    local ledger = newLedger(data)
    assert.is_true(ledger.readOnly)
    local before = deepcopy(data)
    local snap = fx.snapshot(data, 4)
    assert.same({}, flow.recordUnlocks(ledger, "Alliance"))
    assert.same(before, data)
    assert.is_true(fx.sameSnapshot(snap, fx.snapshot(data, 4)))
    assert.same({}, ledger:earned())
    for _, v in ipairs({ nil, "x", 1, fx.hostileTable(), fx.hostileProxy() }) do
      assert.same({}, flow.recordUnlocks(v, "Alliance"))
    end
  end)
end)

describe("the draft", function()
  local real = realFlow()

  it("is nil over a phrase set with no template", function()
    assert.is_nil(newFlow({ phrase = NS.Phrase.bind() }).newDraft({}))
  end)

  it("starts as a valid phrase with the real data", function()
    local d = real.newDraft({})
    local v = d:view()
    assert.equal("Rested here, dreaming of home.", v.preview)
    assert.equal("Rested here, dreaming of ___.", v.t1)
    assert.equal("Hearth and home", v.cat1)
    assert.equal("home", v.w1)
    assert.is_true(v.word1)
    assert.is_false(v.second)
    assert.is_false(v.word2)
    assert.is_false(v.sealRow)
    assert.equal("No seal", v.seal)
    assert.same({ 1, 1001 }, d:ids())
    assert.is_nil(d:seal())
  end)

  it("steps every field both ways with wrap-around", function()
    local P = REAL.Phrase
    local sizes = { v1 = #P.voices(), t1 = #P.templates(1), cat1 = #P.categories(),
      w1 = #P.words(1), v2 = #P.voices(), c = #P.conjunctions(1), t2 = #P.templates(1),
      cat2 = #P.categories(), w2 = #P.words(1) }
    for field, n in pairs(sizes) do
      assert.is_true(n > 1, field)
      local d = real.newDraft({})
      d:setSecond(true)
      local first = d:view()[field]
      d:step(field, -1)
      local last = d:view()[field]
      assert.not_equal(first, last, field)
      d:step(field, 1)
      assert.equal(first, d:view()[field], field)
      for _ = 1, n - 1 do
        d:step(field, 1)
      end
      assert.equal(last, d:view()[field], field)
      d:step(field, 1)
      assert.equal(first, d:view()[field], field)
    end
  end)

  it("resets a category's word when the category changes", function()
    local d = real.newDraft({})
    d:step("w1", 1)
    d:step("w1", 1)
    assert.equal("a warm fire", d:view().w1)
    d:step("cat1", 1)
    assert.equal(REAL.Phrase.text(REAL.Phrase.words(2)[1]), d:view().w1)
    d:step("cat1", -1)
    assert.equal("home", d:view().w1)
    d:setSecond(true)
    d:step("w2", 1)
    d:step("cat2", -1)
    local last = #REAL.Phrase.categories()
    assert.equal(REAL.Phrase.text(REAL.Phrase.words(last)[1]), d:view().w2)
  end)

  it("leaves the word out of a slotless template", function()
    local d = real.newDraft({})
    d:step("t1", -1) -- Hearthside's last template, 111, has no slot
    local v = d:view()
    assert.is_false(v.word1)
    assert.equal("Thank you for everything.", v.t1)
    assert.same({ 111 }, d:ids())
    d:setSecond(true)
    d:step("t2", -1)
    assert.is_false(d:view().word2)
    assert.same({ 111, 501, 111 }, d:ids())
  end)

  it("adds and removes the second line", function()
    local d = real.newDraft({})
    d:setSecond(true)
    local ids = d:ids()
    assert.same({ 1, 1001, 501, 1, 1001 }, ids)
    assert.is_true(REAL.Phrase.validIds(ids))
    local v = d:view()
    assert.is_true(v.second)
    assert.is_true(v.word2)
    assert.equal("Rested here, dreaming of home. And then... Rested here, dreaming of home.",
      v.preview)
    d:setSecond("yes")
    assert.same({ 1, 1001 }, d:ids())
    assert.is_false(d:view().second)
  end)

  it("every reachable combination composes a valid phrase", function()
    local P = REAL.Phrase
    local nT, nC, nCat = #P.templates(), #P.conjunctions(), #P.categories()
    local checked = 0
    local function valid(d)
      local ids = d:ids()
      assert.is_true(P.validIds(ids))
      assert.is_string(d:view().preview)
      checked = checked + 1
    end
    -- First clause: every template x every word of each category.
    local d = real.newDraft({})
    for _ = 1, nCat do
      for _ = 1, nT do
        for _ = 1, #P.words(1) + 3 do
          valid(d)
          d:step("w1", 1)
        end
        d:step("t1", 1)
      end
      d:step("cat1", 1)
    end
    -- Both clauses: every conjunction x every second template x every word of one category.
    d = real.newDraft({})
    d:setSecond(true)
    for _ = 1, nC do
      for _ = 1, nT do
        for _ = 1, #P.words(1) do
          valid(d)
          d:step("w2", 1)
        end
        d:step("t2", 1)
      end
      d:step("c", 1)
      d:step("t1", 1)
    end
    assert.is_true(checked > 1000)
  end)

  it("gives no ids and no preview for a set with an empty category, without throwing", function()
    local data = phraseData()
    data[1000] = nil -- category 1 is empty now
    local f = newFlow({ phrase = NS.Phrase.bind(data, { "Home", "Food" }) })
    local d = f.newDraft({})
    assert.is_nil(d:ids())
    local v = d:view()
    assert.is_nil(v.preview)
    assert.is_nil(v.w1)
    assert.is_true(v.word1)
    d:step("w1", 1)
    assert.is_nil(d:ids())
    d:step("cat1", 1)
    assert.same({ 1, 1100 }, d:ids())
    -- No conjunction: no second line.
    data = phraseData()
    data[500] = nil
    d = newFlow({ phrase = NS.Phrase.bind(data, { "Home", "Food" }) }).newDraft({})
    d:setSecond(true)
    d:step("c", 1)
    assert.is_nil(d:ids())
    assert.is_nil(d:view().c)
  end)

  it("starts in the first voice, and line 2 follows line 1's voice until it's chosen", function()
    local d = real.newDraft({})
    local v = d:view()
    assert.is_true(v.voiceRow)
    assert.equal("Voice: Hearthside", v.v1)
    assert.equal("Voice: Hearthside", v.v2)
    d:step("v1", 1)
    v = d:view()
    assert.equal("Voice: Bardic", v.v1)
    assert.equal("Let the ballads tell of ___!", v.t1)
    assert.same({ 201, 1001 }, d:ids())
    d:setSecond(true)
    assert.equal("Voice: Bardic", d:view().v2)
    assert.same({ 201, 1001, 511, 201, 1001 }, d:ids())
    d:step("v1", -1) -- line 2 still follows
    assert.same({ 1, 1001, 501, 1, 1001 }, d:ids())
    d:step("v2", -1) -- now chosen: Noble, the last voice
    assert.equal("Voice: Noble", d:view().v2)
    assert.same({ 1, 1001, 571, 381, 1001 }, d:ids())
    d:step("t2", 1)
    d:step("v1", 1) -- line 2 keeps its own voice and template
    assert.equal("Voice: Bardic", d:view().v1)
    assert.equal("Voice: Noble", d:view().v2)
    assert.same({ 201, 1001, 571, 382, 1001 }, d:ids())
    assert.is_true(REAL.Phrase.validIds(d:ids()))
  end)

  it("resets the template on a voice change, and the conjunction on line 2's", function()
    local d = real.newDraft({})
    d:step("t1", 1)
    d:step("v1", 1)
    d:step("v1", -1)
    assert.same({ 1, 1001 }, d:ids())
    d:setSecond(true)
    d:step("c", 1)
    d:step("t2", 1)
    d:step("v2", 1)
    d:step("v2", -1)
    assert.same({ 1, 1001, 501, 1, 1001 }, d:ids())
  end)

  it("pairs every voice with every voice in a valid two-line phrase", function()
    local P = REAL.Phrase
    local n = #P.voices()
    for a = 1, n do
      for b = 1, n do
        local d = real.newDraft({})
        d:setSecond(true)
        d:step("v2", 1) -- choose line 2's voice first, so line 1's steps leave it alone
        d:step("v2", -1)
        for _ = 2, b do
          d:step("v2", 1)
        end
        for _ = 2, a do
          d:step("v1", 1)
        end
        local ids = d:ids()
        assert.is_true(P.validIds(ids), a .. "/" .. b)
        assert.equal(a, P.voice(ids[1]))
        assert.equal(b, P.voice(ids[3]))
        assert.equal(b, P.voice(ids[4]))
      end
    end
  end)

  it("offers one unnamed group when the set has no voices", function()
    local d = newFlow().newDraft({})
    local v = d:view()
    assert.is_false(v.voiceRow)
    assert.is_nil(v.v1)
    assert.is_nil(v.v2)
    d:step("t1", 1)
    d:step("v1", 1) -- one group: wraps to itself, so line 1 keeps its template
    assert.same({ 2 }, d:ids())
  end)

  it("skips a voice with no template, and lends every conjunction to a voice with none", function()
    local data, cats = phraseData()
    data[1].voice = 1
    data[2].voice = 3
    data[500].voice = 1
    local phrase = NS.Phrase.bind(data, cats, { "Warm", "Empty", "Gruff" })
    assert.same({}, phrase.invalid)
    local d = newFlow({ phrase = phrase }).newDraft({})
    d:step("v1", 1)
    assert.equal("Voice: Gruff", d:view().v1) -- Empty was skipped
    assert.same({ 2 }, d:ids())
    d:setSecond(true)
    assert.equal("And then...", d:view().c) -- Gruff has no conjunction of its own
    assert.same({ 2, 500, 2 }, d:ids())
  end)

  it("treats junk from voices as no voices, and a voices that throws as no draft", function()
    local base = NS.Phrase.bind(phraseData())
    local function with(voices)
      local phrase = {}
      for k, fn in pairs(base) do
        phrase[k] = fn
      end
      phrase.voices = voices
      return newFlow({ phrase = phrase })
    end
    for _, voices in ipairs({
      function() return "x" end,
      function() return { 5, true } end,
      "not a function",
    }) do
      local d = with(voices).newDraft({})
      assert.is_false(d:view().voiceRow)
      assert.same({ 1, 1000 }, d:ids())
    end
    assert.is_nil(with(function() error("boom") end).newDraft({}))
  end)

  it("cycles the seals: none, then each in turn, both ways", function()
    local seals = { 2, 101 }
    local d = real.newDraft(seals)
    seals[1], seals[3] = 50, 60
    assert.is_true(d:view().sealRow)
    local order = { { 2, "Innkeeper's seal" }, { 101, "Zephras Isle" }, { nil, "No seal" } }
    for _, want in ipairs(order) do
      d:step("seal", 1)
      assert.equal(want[1], d:seal())
      assert.equal(want[2], d:view().seal)
    end
    for i = #order - 1, 1, -1 do
      d:step("seal", -1)
      assert.equal(order[i][1], d:seal())
    end
    d:step("seal", -1)
    assert.is_nil(d:seal())

    local none = real.newDraft({})
    none:step("seal", 1)
    assert.is_nil(none:seal())
    assert.equal("No seal", none:view().seal)
    -- Only whole seal IDs are kept; a hostile list gives none.
    assert.is_false(real.newDraft({ "2", 0 / 0 }):view().sealRow)
    assert.is_false(real.newDraft(fx.hostileTable()):view().sealRow)
    assert.is_false(real.newDraft(nil):view().sealRow)
  end)

  it("labels an unnamed seal by its number", function()
    local cosmetics = deps().cosmetics
    local stub = {}
    for k, v in pairs(cosmetics) do
      stub[k] = v
    end
    stub.info = function() return nil end
    local d = newFlow({ cosmetics = stub }).newDraft({ 7 })
    d:step("seal", 1)
    assert.equal("7", d:view().seal)
  end)

  it("ignores a bad field or delta", function()
    local d = real.newDraft({ 2 })
    d:setSecond(true)
    local before = d:view()
    for _, field in ipairs({ "x", "second", "preview", 1, fx.hostileTable(), fx.hostileProxy() }) do
      d:step(field, 1)
    end
    for _, delta in ipairs({ 0, 2, -2, 0.5, 0 / 0, "1", fx.hostileTable(), fx.hostileProxy() }) do
      d:step("t1", delta)
      d:step("seal", delta)
    end
    d:step("t1")
    assert.same(before, d:view())
  end)

  it("shows the slot as ___ and no | in any string over the real data", function()
    local d = real.newDraft({ 2, 101 })
    d:setSecond(true)
    d:step("seal", 1)
    local seen = {}
    for _ = 1, #REAL.Phrase.templates() do
      for _ = 1, #REAL.Phrase.categories() do
        local v = d:view()
        for k, s in pairs(v) do
          assert.is_false(hasPipe(s), k)
          assert.is_nil(type(s) == "string" and s:find("%", 1, true) or nil, k)
        end
        seen[v.t1] = true
        d:step("cat1", 1)
        d:step("w2", 1)
      end
      d:step("t1", 1)
      d:step("t2", -1)
    end
    assert.is_true(seen["Here's to ___!"])
    assert.is_true(seen["Rest well, traveler."])
  end)
end)

describe("SignFlow.message and SignFlow.untilText", function()
  local message, untilText = SignFlow.message, SignFlow.untilText

  it("has a line for every reason and for added", function()
    for code in pairs(SignFlow.REASONS) do
      local line = message({ reason = code, wait = 60 })
      assert.is_string(line)
      assert.is_true(#line > 0, code)
      assert.equal(line, message({ result = code, wait = 60 }))
    end
    assert.equal("You signed the guestbook of Calmbreeze Inn.",
      message({ result = "added" }, "Calmbreeze Inn"))
    assert.equal("You signed the guestbook of the inn.", message({ result = "added" }))
    assert.equal("You signed the guestbook of the inn.", message({ result = "added" }, "A|cff"))
    assert.equal("Rest at the inn to sign its guestbook.", message({ reason = "not_resting" }))
    assert.equal("Talk to the innkeeper again to sign the guestbook.",
      message({ result = "changed" }))
  end)

  it("gives the error line for an unknown or malformed result", function()
    for _, res in ipairs({ { reason = "nope" }, { result = "sign" }, { result = "button" }, {},
      nil, "too_soon", { reason = fx.hostileTable() }, fx.hostileTable(), fx.hostileProxy() }) do
      assert.equal("Nothing was signed.", message(res))
    end
  end)

  it("says when the next reset is", function()
    assert.equal("You've signed this guestbook this week. Sign again after the weekly reset "
      .. "(in 3 days).", message({ reason = "too_soon", wait = 259200 }))
    assert.equal("You've signed this guestbook this week. Sign again after the weekly reset "
      .. "(soon).", message({ result = "too_soon" }))
  end)

  it("holds no |, % or link in any text", function()
    local lines = {}
    for _, v in pairs(SignFlow.TEXT) do
      lines[#lines + 1] = v
    end
    for code in pairs(SignFlow.REASONS) do
      lines[#lines + 1] = message({ reason = code, wait = 1 })
    end
    lines[#lines + 1] = message({ result = "added" }, "Vale Inn")
    for _, line in ipairs(lines) do
      assert.is_nil(line:find("|", 1, true), line)
      assert.is_nil(line:find("%", 1, true), line)
      assert.is_nil(line:lower():find("http", 1, true), line)
      assert.is_nil(line:lower():find("www", 1, true), line)
    end
  end)

  it("hands out copies of TEXT and REASONS", function()
    SignFlow.TEXT.error = "changed"
    SignFlow.REASONS.nope = true
    assert.equal("Nothing was signed.", message({ reason = "error" }))
    assert.equal("Nothing was signed.", message({ reason = "nope" }))
    SignFlow.TEXT.error = "Nothing was signed."
    SignFlow.REASONS.nope = nil
  end)

  it("untilText rounds to days, hours or minutes", function()
    local cases = {
      { 0, "in 1 minute" }, { 59, "in 1 minute" }, { 60, "in 1 minute" },
      { 61, "in 2 minutes" }, { 3599, "in 60 minutes" }, { 3600, "in 1 hour" },
      { 7200, "in 2 hours" }, { 172799, "in 47 hours" }, { 172800, "in 2 days" },
      { 604800, "in 7 days" },
    }
    for _, c in ipairs(cases) do
      assert.equal(c[2], untilText(c[1]), tostring(c[1]))
    end
    for _, n in ipairs({ -1, 0 / 0, 1 / 0, 1.5, "60", fx.hostileTable() }) do
      assert.equal("soon", untilText(n))
    end
    assert.equal("soon", untilText(nil))
  end)
end)

describe("never throws", function()
  local flow = newFlow()

  it("on any argument, in every flow function", function()
    local good = { sit(), 5001, { 2 }, nil }
    local function try(name, fn, ...)
      local ok, err = pcall(fn, ...)
      assert.is_true(ok, name .. ": " .. tostring(err))
    end
    for _, bad in ipairs(badValues()) do
      try("innAt", flow.innAt, bad)
      try("innName", flow.innName, bad)
      try("check", flow.check, bad)
      assert.is_false(flow.check(bad).ok)
      assert.same({}, flow.seals(bad))
      try("recordUnlocks", flow.recordUnlocks, bad, bad)
      try("newDraft", flow.newDraft, bad)
      try("message", SignFlow.message, bad, bad)
      try("untilText", SignFlow.untilText, bad)
      for i = 1, 4 do
        local args = { good[1], good[2], good[3], good[4] }
        args[i] = bad
        local res = flow.commit(args[1], args[2], args[3], args[4])
        assert.is_string(res.result)
      end
      for _, key in ipairs({ "ledger", "npc", "resting", "now", "faction" }) do
        local sitBad = sit()
        sitBad[key] = bad
        try("check " .. key, flow.check, sitBad)
        try("seals " .. key, flow.seals, sitBad)
        try("commit " .. key, flow.commit, sitBad, 5001, { 2 }, nil)
      end
      local d = flow.newDraft({ 1 })
      try("step", d.step, d, bad, bad)
      try("setSecond", d.setSecond, d, bad)
      try("ids", d.ids, bad)
      try("seal", d.seal, bad)
      try("view", d.view, bad)
    end
  end)

  it("returns the failure value when a dependency raises", function()
    local d = deps()
    local function raising(t)
      local out = {}
      for k, v in pairs(t) do
        out[k] = type(v) == "function" and raise or v
      end
      return out
    end
    local f = SignFlow.new({ inns = d.inns, atlas = raising(d.atlas),
      phrase = raising(d.phrase), cosmetics = raising(d.cosmetics) })
    assert.is_nil(f.innAt(npcGUID(5001)))
    assert.is_nil(f.innName(5001))
    assert.same({ ok = false, reason = "error" }, f.check(sit()))
    assert.same({}, f.seals(sit()))
    assert.same({ result = "error" }, f.commit(sit(), 5001, { 2 }, nil))
    assert.same({}, f.recordUnlocks(newLedger(), "Alliance"))
    assert.is_nil(f.newDraft({}))

    -- A draft whose phrase set starts raising after it was made.
    local phrase, broken = {}, false
    for k, v in pairs(d.phrase) do
      phrase[k] = v
      if type(v) == "function" then
        phrase[k] = function(...)
          if broken then
            error("raised on purpose")
          end
          return v(...)
        end
      end
    end
    local draft = newFlow({ phrase = phrase }).newDraft({ 1 })
    assert.same({ 1, 1000 }, draft:ids())
    broken = true
    assert.is_nil(draft:ids())
    assert.is_nil(draft:view())
    draft:step("t1", 1)

    -- Unlocks that raise only once the entry is in: the entry stays, earned is empty.
    local cosmetics, n = {}, 0
    for k, v in pairs(d.cosmetics) do
      cosmetics[k] = v
    end
    cosmetics.unlocked = function(...)
      n = n + 1
      if n > 1 then
        error("raised on purpose")
      end
      return d.cosmetics.unlocked(...)
    end
    local s = sit()
    local res = newFlow({ cosmetics = cosmetics }).commit(s, 5001, { 2 }, nil)
    assert.equal("added", res.result)
    assert.same({}, res.earned)
    assert.equal(1, #s.ledger:own())
  end)
end)
