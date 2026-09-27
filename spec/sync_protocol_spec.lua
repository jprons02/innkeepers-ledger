-- SyncProtocol: codec, digest, validation rules 1-19, rate limits and decideWant
-- (docs/specs/sync-ledger.md, sections 3, 5 and 6). Peer data is hostile here: every
-- rule gets malformed, oversized, multi-part, relayed, replayed, forged and flood cases.
-- Fixed times only, never the clock.
local load = require("helpers.load")

-- Ledger first, as in the TOC; `patch` may change Ledger before SyncProtocol reads it.
local function modules(patch)
  local ns = {}
  load.file("Ledger.lua", ns, load.pure_env())
  if patch then
    patch(ns.Ledger)
  end
  load.file("SyncProtocol.lua", ns, load.pure_env())
  return ns.Ledger, ns.SyncProtocol
end

local Ledger, SP = modules()
local LIMITS = Ledger.LIMITS

local ANCHOR = 1790089200 -- Tuesday 2026-09-22 15:00 UTC, the retail US reset
local NOW = 1794000000
local TMIN = LIMITS.tMin
local OWNER = "Player-1234-0ABCDEF0"
local MIRA = "Player-1234-0BBBBBB0"
local BRAM = "Player-1234-0CCCCCC0"
local NAME = "Mira Ashvale"
local SENDER = { guid = MIRA, name = NAME }

-- Fixture data tables. Unknown IDs used below: inn 5555, phrase 77, seal 50.
local INNS, PHRASES, SEALS = { [1234] = true, [98765] = true, [9999999] = true }, {}, {}
for i = 1, 300 do
  INNS[i] = true
end
for i = 1, 40 do
  PHRASES[i] = true
end
PHRASES[9999] = true
for i = 1, 20 do
  SEALS[i] = true
end
SEALS[999] = true

local function entry(inn, t, phrase, seal)
  return { inn = inn, t = t, phrase = phrase or { 1 }, seal = seal }
end

-- The digest vectors of spec 3.3.
local A = entry(1234, 1793800000, { 1, 22, 3 })
local B = entry(98765, 1793900000, { 7 }, 12)

local function guid(n)
  return ("Player-1-%08X"):format(n)
end

local function newLedger()
  return Ledger.new({}, { guid = OWNER, name = "Aldric Stonebrook" }, ANCHOR)
end

local function newCtx()
  return {
    now = NOW, selfGUID = OWNER, inns = INNS, phrases = PHRASES, seals = SEALS,
    ledger = newLedger(), limiter = SP.newLimiter(), wantMemo = SP.newWantMemo(),
  }
end

local function recv(ctx, msg, sender, channel)
  return SP.receive(msg, channel or "PARTY", sender or SENDER, ctx)
end

local function stored(ctx)
  return ctx.ledger:counts().foreign
end

-- A distinct valid entry per i (distinct inns, so the weekly rule never bites).
local function nth(i)
  return entry(i, NOW - 100000 + i, { 1 + i % 40 }, i % 3 == 0 and (i % 20 + 1) or nil)
end

local function wire(e)
  return e.inn .. "," .. e.t .. "," .. table.concat(e.phrase, ".") .. "," .. (e.seal or 0)
end

local function E(...)
  local parts = {}
  for i, e in ipairs({ ... }) do
    parts[i] = type(e) == "string" and e or wire(e)
  end
  return "E1:" .. table.concat(parts, ";")
end

local VALID = E(A) -- "E1:1234,1793800000,1.22.3,0"

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

local function hostiles()
  return {
    hostileTable(), hostileProxy(), 0 / 0, math.huge, -1, true, "", function() end, {},
    coroutine.create(function() end),
  }
end

-- Deterministic pseudo-random numbers (Park-Miller; exact in doubles).
local function rng(seed)
  return function(n)
    seed = seed * 16807 % 2147483647
    return seed % n
  end
end

describe("SyncProtocol module", function()
  it("has the spec 5.1a constants and aliases", function()
    assert.equal(1, SP.VERSION)
    assert.equal(255, SP.MAX_BYTES)
    assert.equal(5, SP.MAX_ENTRIES_PER_MSG)
    assert.equal(40, SP.SHARE_MAX)
    assert.same({ PARTY = true, RAID = true, GUILD = true }, SP.CHANNELS)
    assert.same({
      window = 60, perSenderMessages = 40, perSenderEntries = 80, globalMessages = 1200,
      maxSenders = 1000,
    }, SP.LIMITS)
    assert.equal(Ledger.validName, SP.validName)
    assert.equal(Ledger.validGUID, SP.validGUID)
    assert.same({ asked = {}, seen = {} }, SP.newWantMemo())
  end)

  it("reads SHARE_MAX from Ledger.CAPS, not a second literal", function()
    local _, sp = modules(function(L) L.CAPS.perSigner = 7 end)
    assert.equal(7, sp.SHARE_MAX)
  end)

  it("loads in the strict environment only after Ledger", function()
    assert.has_error(function()
      load.file("SyncProtocol.lua", {}, load.pure_env())
    end)
    local ns = {}
    load.file("Ledger.lua", ns, load.pure_env())
    load.file("SyncProtocol.lua", ns, load.pure_env())
    assert.is_table(ns.SyncProtocol)
  end)
end)

describe("SyncProtocol digest", function()
  it("matches the four vectors of spec 3.3", function()
    assert.equal("1234,1793800000,1.22.3,0", SP.canon(A))
    assert.equal("98765,1793900000,7,12", SP.canon(B))
    assert.equal(0, SP.digest({}))
    assert.equal(1244322287, SP.digest({ A }))
    assert.equal(2020135697, SP.digest({ A, B }))
    assert.equal(1242196279, SP.digest({ B, A }))
  end)

  it("depends on order, and on every phrase ID, the seal and the time", function()
    local base = SP.digest({ A, B })
    assert.not_equal(base, SP.digest({ B, A }))
    assert.not_equal(base, SP.digest({ entry(1234, 1793800000, { 1, 22, 4 }), B }))
    assert.not_equal(base, SP.digest({ A, entry(98765, 1793900000, { 7 }, 13) }))
    assert.not_equal(base, SP.digest({ A, entry(98765, 1793900000, { 7 }) }))
    assert.not_equal(base, SP.digest({ A, entry(98765, 1793900001, { 7 }, 12) }))
    assert.not_equal(base, SP.digest({ entry(1235, 1793800000, { 1, 22, 3 }), B }))
  end)

  it("stays an exact integer below 2^31 - 1 for a worst-case window", function()
    local window = {}
    for i = 1, 40 do
      window[i] = entry(9999999, 9999999960 + i - 1, { 9999, 9999, 9999, 9999, 9999 }, 999)
    end
    local d = SP.digest(window)
    assert.is_true(d >= 0 and d < 2147483647 and d % 1 == 0)
  end)
end)

describe("SyncProtocol encoders", function()
  it("encodeHello gives count and digest of the 3.3 vectors", function()
    assert.equal("H1:0:0", SP.encodeHello({}))
    assert.equal("H1:1:1244322287", SP.encodeHello({ A }))
    assert.equal("H1:2:2020135697", SP.encodeHello({ A, B }))
  end)

  it("encodeHello refuses more than SHARE_MAX entries and invalid entries", function()
    local window = {}
    for i = 1, 41 do
      window[i] = nth(i)
    end
    assert.has_error(function() SP.encodeHello(window) end)
    assert.has_error(function() SP.encodeHello({ entry(1, NOW, { 1 }, 0) }) end)
    assert.has_error(function() SP.encodeHello("x") end)
  end)

  it("encodeWant", function()
    assert.equal("W1:Player-1234-0ABCDEF0:1793800000", SP.encodeWant(OWNER, 1793800000))
    assert.equal("W1:Player-1234-0ABCDEF0:0", SP.encodeWant(OWNER, 0))
    assert.has_error(function() SP.encodeWant("player-1-AB", 0) end)
    assert.has_error(function() SP.encodeWant(OWNER, 5) end)
    assert.has_error(function() SP.encodeWant(OWNER, 1793800000.5) end)
    assert.has_error(function() SP.encodeWant(OWNER, nil) end)
  end)

  it("encodeEntries sends t > since, oldest first, 5 per message", function()
    local window = {}
    for i = 12, 1, -1 do -- unsorted on purpose
      window[#window + 1] = nth(i)
    end
    local msgs = SP.encodeEntries(window, 0)
    assert.same({
      E(nth(1), nth(2), nth(3), nth(4), nth(5)),
      E(nth(6), nth(7), nth(8), nth(9), nth(10)),
      E(nth(11), nth(12)),
    }, msgs)
    assert.same({ E(nth(11), nth(12)) }, SP.encodeEntries(window, nth(10).t))
    assert.same({}, SP.encodeEntries(window, nth(12).t))
    assert.same({}, SP.encodeEntries({}, 0))
  end)

  it("encodeEntries orders equal times by inn", function()
    local t = NOW - 10
    assert.same({ E(entry(3, t), entry(9, t)) },
      SP.encodeEntries({ entry(9, t), entry(3, t) }, 0))
  end)

  it("encodes a nil seal as 0", function()
    assert.same({ "E1:1234,1793800000,1.22.3,0" }, SP.encodeEntries({ A }, 0))
  end)

  it("keeps every message within 255 bytes with worst-case entries", function()
    local window = {}
    for i = 1, 10 do
      window[i] = entry(9999999, 9999999989 + i, { 9999, 9999, 9999, 9999, 9999 }, 999)
    end
    local msgs = SP.encodeEntries(window, 0)
    assert.equal(2, #msgs)
    for _, m in ipairs(msgs) do
      assert.equal(242, #m)
    end
    assert.equal(54, #SP.encodeWant("Player-1234-" .. ("A"):rep(28), 9999999999))
  end)

  it("encodeEntries refuses invalid entries or since", function()
    assert.has_error(function() SP.encodeEntries({ entry(0, NOW) }, 0) end)
    assert.has_error(function() SP.encodeEntries({ A }, -1) end)
    assert.has_error(function() SP.encodeEntries({ A }, 0 / 0) end)
    assert.has_error(function() SP.encodeEntries(nil, 0) end)
  end)

  it("raises rather than emit a message over 255 bytes", function()
    -- Only reachable if Ledger's entry rule ever loosened; the size check still holds.
    local _, sp = modules(function(L) L.validEntry = function() return true end end)
    local big = {}
    for i = 1, 5 do
      local phrase = {}
      for j = 1, 30 do
        phrase[j] = j
      end
      big[i] = entry(1, NOW + i, phrase)
    end
    assert.has_error(function() sp.encodeEntries(big, 0) end)
    -- The boundary: "E1:1,1794000001,<phrase>,0" is 255 bytes with 119 IDs of "1" and
    -- 256 bytes when one of them is "10".
    local ones = {}
    for j = 1, 119 do
      ones[j] = 1
    end
    assert.equal(255, #sp.encodeEntries({ entry(1, NOW + 1, ones) }, 0)[1])
    ones[119] = 10
    assert.has_error(function() sp.encodeEntries({ entry(1, NOW + 1, ones) }, 0) end)
  end)
end)

describe("SyncProtocol round trip", function()
  it("every encoder's output is accepted by receive", function()
    local ctx = newCtx()
    local window = {}
    for i = 1, 12 do
      window[i] = nth(i)
    end
    local res = recv(ctx, SP.encodeHello(window))
    assert.same({ kind = "hello", count = 12, digest = SP.digest(window) }, res)

    res = recv(ctx, SP.encodeWant(OWNER, window[4].t))
    assert.same({ kind = "want", since = window[4].t }, res)
    res = recv(ctx, SP.encodeWant(BRAM, 0))
    assert.same({ kind = "want_seen", target = BRAM, since = 0 }, res)

    for _, msg in ipairs(SP.encodeEntries(window, 0)) do
      res = recv(ctx, msg)
      assert.equal("entries", res.kind)
    end
    assert.same(window, ctx.ledger:signerEntries(MIRA))
    assert.equal(12, stored(ctx))
    -- Now in sync: no WANT for this peer.
    assert.is_nil(SP.decideWant(SP.newWantMemo(), MIRA, "PARTY", 12, SP.digest(window),
      ctx.ledger:signerEntries(MIRA), NOW))
  end)

  it("stores exactly the input entries, seals and phrase order included", function()
    local ctx = newCtx()
    local window = { A, B, entry(9999999, NOW + 300, { 9999, 3, 9999, 1, 2 }, 999) }
    for _, msg in ipairs(SP.encodeEntries(window, 0)) do
      assert.same({ kind = "entries", added = 3, dup = 0, dropped = 0, rejected = 0 },
        recv(ctx, msg))
    end
    assert.same(window, ctx.ledger:signerEntries(MIRA))
  end)
end)

describe("SyncProtocol.receive rule 1 (never throws)", function()
  it("receive never throws on a hostile value in any argument", function()
    for pos = 1, 4 do
      for _, v in ipairs(hostiles()) do
        local ctx = newCtx()
        local args = { VALID, "PARTY", SENDER, ctx }
        args[pos] = v
        local ok, res = pcall(SP.receive, args[1], args[2], args[3], args[4])
        assert.is_true(ok)
        assert.is_nil(res)
        assert.equal(0, stored(ctx))
      end
    end
  end)

  it("never throws on a hostile value in any ctx or sender field", function()
    local fields = {
      "now", "selfGUID", "ledger", "limiter", "wantMemo", "inns", "phrases", "seals",
      "phraseOk",
    }
    local sealed = E(entry(1234, A.t, { 1, 22, 3 }, 12)) -- so the seals table is read too
    for _, f in ipairs(fields) do
      for _, v in ipairs(hostiles()) do
        local ctx = newCtx()
        local ledger = ctx.ledger
        ctx[f] = v
        local ok = pcall(SP.receive, sealed, "PARTY", SENDER, ctx)
        assert.is_true(ok)
        assert.equal(0, ledger:counts().foreign)
      end
    end
    for _, f in ipairs({ "guid", "name" }) do
      for _, v in ipairs(hostiles()) do
        local ctx = newCtx()
        local sender = { guid = MIRA, name = NAME }
        sender[f] = v
        local ok, res, reason = pcall(SP.receive, VALID, "PARTY", sender, ctx)
        assert.is_true(ok)
        assert.is_nil(res)
        assert.equal("sender", reason)
        assert.equal(0, stored(ctx))
      end
    end
  end)

  it("turns an error inside into a quiet 'error' drop", function()
    local ctx = newCtx()
    ctx.ledger = hostileTable()
    assert.same({ nil, "error" }, { recv(ctx, VALID) })
    ctx = newCtx()
    ctx.limiter = { admit = raise, admitEntries = raise }
    assert.same({ nil, "error" }, { recv(ctx, VALID) })
  end)
end)

describe("SyncProtocol.receive rule 2 (context)", function()
  it("drops everything when selfGUID is a hidden-value stand-in", function()
    for _, v in ipairs({ hostileTable(), hostileProxy() }) do
      for _, msg in ipairs({ VALID, "H1:0:0", "W1:" .. OWNER .. ":0" }) do
        local ctx = newCtx()
        ctx.selfGUID = v
        assert.same({ nil, "ctx" }, { recv(ctx, msg) })
        assert.equal(0, stored(ctx))
      end
    end
  end)

  it("drops everything when the ledger is read-only", function()
    local ctx = newCtx()
    ctx.ledger = Ledger.new("damaged", { guid = OWNER, name = "Aldric" }, ANCHOR)
    assert.is_true(ctx.ledger.readOnly)
    for _, msg in ipairs({ VALID, "H1:0:0", "W1:" .. OWNER .. ":0", "W1:" .. BRAM .. ":0",
      "X9:junk" }) do
      assert.same({ nil, "readonly" }, { recv(ctx, msg) })
    end
    assert.same({}, ctx.wantMemo.seen)
    assert.is_true(ctx.limiter:admit(MIRA, NOW)) -- nothing was charged either
  end)

  it("drops on a missing or broken ctx", function()
    assert.same({ nil, "ctx" }, { SP.receive(VALID, "PARTY", SENDER, nil) })
    local cases = {
      { "now", 1.5 }, { "now", 0 / 0 }, { "now", math.huge }, { "now", "1794000000" },
      { "now", nil }, { "now", -1 }, { "now", LIMITS.tMax + 1 },
      { "selfGUID", "player-1234-0ABCDEF0" }, { "selfGUID", nil }, { "selfGUID", BRAM },
      { "ledger", nil }, { "ledger", {} }, { "limiter", nil }, { "limiter", {} },
      { "limiter", { admit = function() return true end } },
      { "wantMemo", nil }, { "wantMemo", {} }, { "inns", nil }, { "phrases", false },
      { "seals", "x" }, { "phraseOk", true },
    }
    for i, c in ipairs(cases) do
      local ctx = newCtx()
      ctx[c[1]] = c[2]
      local res, reason = recv(ctx, VALID)
      assert.is_nil(res, "case " .. i)
      assert.equal("ctx", reason, "case " .. i)
    end
  end)

  it("drops when selfGUID isn't the ledger owner", function()
    local ctx = newCtx()
    ctx.selfGUID = MIRA
    assert.same({ nil, "ctx" }, { recv(ctx, VALID, { guid = BRAM, name = "Bram" }) })
  end)
end)

describe("SyncProtocol.receive rules 3-5 (channel, sender, echo)", function()
  it("drops WHISPER, CHANNEL, SAY, INSTANCE_CHAT and nil", function()
    local ctx = newCtx()
    for _, ch in ipairs({ "WHISPER", "CHANNEL", "SAY", "INSTANCE_CHAT", "party", "" }) do
      assert.same({ nil, "channel" }, { recv(ctx, VALID, SENDER, ch) })
    end
    assert.same({ nil, "channel" }, { SP.receive(VALID, nil, SENDER, ctx) })
    assert.equal(0, stored(ctx))
    for _, ch in ipairs({ "PARTY", "RAID", "GUILD" }) do
      assert.equal("hello", recv(ctx, "H1:0:0", SENDER, ch).kind)
    end
  end)

  it("drops a nil, empty, non-string or malformed sender GUID", function()
    local ctx = newCtx()
    assert.same({ nil, "sender" }, { SP.receive(VALID, "PARTY", nil, ctx) })
    assert.same({ nil, "sender" }, { SP.receive(VALID, "PARTY", "Mira", ctx) })
    for _, g in ipairs({ false, "", 42, "player-1234-0BBBBBB0", "Player--AB", "Player-1-",
      "Player-1-0x1F", "Player-1-AB-CD", "Player-1-" .. ("A"):rep(32), "Creature-0-1-2-3-4-5",
      "Player-1-AB\0" }) do
      assert.same({ nil, "sender" }, { recv(ctx, VALID, { guid = g, name = NAME }) })
    end
    assert.equal(0, stored(ctx))
  end)

  it("reads the sender's fields raw and never runs its metamethods", function()
    local ctx = newCtx()
    local viaIndex = setmetatable({}, { __index = { guid = MIRA, name = NAME } })
    assert.same({ nil, "sender" }, { recv(ctx, VALID, viaIndex) })
    local calls = 0
    local function trap()
      calls = calls + 1
      error("touched")
    end
    local trapped = setmetatable({ guid = MIRA, name = NAME },
      { __index = trap, __newindex = trap, __len = trap, __eq = trap, __tostring = trap })
    assert.equal("entries", recv(ctx, VALID, trapped).kind)
    assert.equal(0, calls)
    assert.same({ A }, ctx.ledger:signerEntries(MIRA))
  end)

  it("drops a sender name with a pipe or control byte", function()
    local ctx = newCtx()
    for _, n in ipairs({ "Mira|cffff0000", "Mira\1", "Mira\n", "Mira\0", "Mira\127", "M",
      ("M"):rep(97), "Mira  Ashvale", "Mira-", 5 }) do
      assert.same({ nil, "sender" }, { recv(ctx, VALID, { guid = MIRA, name = n }) })
    end
    assert.same({ nil, "sender" }, { recv(ctx, VALID, { guid = MIRA }) })
    assert.equal(0, stored(ctx))
  end)

  it("drops our own messages echoed back by the channel", function()
    local ctx = newCtx()
    assert.same({ nil, "self" }, { recv(ctx, VALID, { guid = OWNER, name = "Aldric" }) })
    assert.same({ nil, "self" }, { recv(ctx, "H1:0:0", { guid = OWNER, name = "Aldric" }) })
    assert.equal(0, stored(ctx))
  end)
end)

describe("SyncProtocol.receive rule 6 (size first)", function()
  it("drops a 256-byte message unread", function()
    local ctx = newCtx()
    local msg = VALID .. (";" .. wire(A)):rep(20)
    msg = msg:sub(1, 256)
    assert.equal(256, #msg)
    for _ = 1, 50 do
      assert.same({ nil, "size" }, { recv(ctx, msg) })
    end
    -- Unread means uncharged: the limiter still admits a full window.
    for _ = 1, 40 do
      assert.is_table(recv(ctx, "H1:0:0"))
    end
  end)

  it("drops an empty message", function()
    assert.same({ nil, "size" }, { recv(newCtx(), "") })
  end)

  it("drops oversized messages of 10 KB and a valid prefix followed by junk", function()
    local ctx = newCtx()
    assert.same({ nil, "size" }, { recv(ctx, ("1"):rep(10240)) })
    assert.same({ nil, "size" }, { recv(ctx, VALID .. ("X"):rep(300)) })
    assert.same({ nil, "number" }, { recv(ctx, VALID .. "junk") })
    assert.same({ nil, "schema" }, { recv(ctx, VALID .. ",junk") })
    assert.same({ nil, "schema" }, { recv(ctx, "H1:0:0:junk") })
    assert.equal(0, stored(ctx))
  end)

  it("reads a message of exactly 255 bytes", function()
    -- 255 bytes pass the size rule and are judged by the later rules.
    local exact = "H1:0:" .. ("1"):rep(250)
    assert.equal(255, #exact)
    assert.same({ nil, "number" }, { recv(newCtx(), exact) })
  end)
end)

describe("SyncProtocol.receive rule 7 (message rate)", function()
  it("drops the 41st message from one sender within 60 s", function()
    local ctx = newCtx()
    for _ = 1, 40 do
      assert.is_table(recv(ctx, "H1:0:0"))
    end
    assert.same({ nil, "rate" }, { recv(ctx, "H1:0:0") })
    ctx.now = NOW + 59
    assert.same({ nil, "rate" }, { recv(ctx, "H1:0:0") })
    -- Another sender is unaffected.
    assert.is_table(recv(ctx, "H1:0:0", { guid = BRAM, name = "Bram" }))
  end)

  it("admits again after the window", function()
    local ctx = newCtx()
    for _ = 1, 41 do
      recv(ctx, "H1:0:0")
    end
    ctx.now = NOW + 60
    assert.is_table(recv(ctx, "H1:0:0"))
  end)

  it("counts junk too, since the rate check comes before parsing", function()
    local ctx = newCtx()
    for _ = 1, 40 do
      assert.same({ nil, "charset" }, { recv(ctx, "junk junk") })
    end
    assert.same({ nil, "rate" }, { recv(ctx, "H1:0:0") })
  end)
end)

describe("SyncProtocol.receive rule 8 (charset)", function()
  it("drops multi-part-marked messages", function()
    local ctx = newCtx()
    for b = 1, 4 do
      assert.same({ nil, "charset" }, { recv(ctx, string.char(b) .. VALID) })
      assert.same({ nil, "charset" }, { recv(ctx, VALID .. string.char(b)) })
    end
    -- A multi-part series is never reassembled.
    recv(ctx, "\001E1:1234,17938")
    recv(ctx, "\00300000,1.22.3,0")
    assert.equal(0, stored(ctx))
  end)

  it("drops a message with a pipe escape", function()
    assert.same({ nil, "charset" }, { recv(newCtx(), "H1:0:0|r") })
    assert.same({ nil, "charset" }, { recv(newCtx(), "|cffff0000H1:0:0") })
  end)

  it("drops a message with NUL", function()
    assert.same({ nil, "charset" }, { recv(newCtx(), "H1:0\0:0") })
    assert.same({ nil, "charset" }, { recv(newCtx(), VALID .. "\0") })
  end)

  it("drops a message with a space", function()
    assert.same({ nil, "charset" }, { recv(newCtx(), "H1: 0:0") })
    assert.same({ nil, "charset" }, { recv(newCtx(), "E1:1234, 1793800000,1,0") })
  end)

  it("drops UTF-8, tabs, newlines and other punctuation", function()
    for _, m in ipairs({ "H1:0:0\195\169", "H1:0:0\t", "H1:0:0\n", "H1:+5:0", "H1:0:0_",
      "H1:0:0/", "H1:0:0'", "H1:0:0\255" }) do
      assert.same({ nil, "charset" }, { recv(newCtx(), m) })
    end
  end)
end)

describe("SyncProtocol.receive rule 9 (header)", function()
  it("drops an unknown type", function()
    for _, m in ipairs({ "X1:0:0", "h1:0:0", "A1:0:0", "Z1:x", "H:0:0", "H1", "H1-0:0",
      "1:0:0", ":H1:0:0", "HH1:0:0" }) do
      assert.same({ nil, "header" }, { recv(newCtx(), m) }, m)
    end
  end)

  it("drops version 2 and version 01", function()
    for _, m in ipairs({ "H2:0:0", "H01:0:0", "W2:x", "E0:1", "E11:" .. wire(A),
      "H10:0:0" }) do
      assert.same({ nil, "version" }, { recv(newCtx(), m) }, m)
    end
  end)
end)

describe("SyncProtocol.receive rule 10 (schema)", function()
  local function schema(m)
    local ctx = newCtx()
    assert.same({ nil, "schema" }, { recv(ctx, m) }, m)
    assert.equal(0, stored(ctx))
  end

  it("drops an ENTRIES with 6 entries", function()
    schema(E(nth(1), nth(2), nth(3), nth(4), nth(5), nth(6)))
    local ctx = newCtx()
    assert.equal(5, recv(ctx, E(nth(1), nth(2), nth(3), nth(4), nth(5))).added)
  end)

  it("drops a phrase with 6 IDs", function()
    schema("E1:1234,1793800000,1.2.3.4.5.6,0")
    assert.equal(1, recv(newCtx(), "E1:1234,1793800000,1.2.3.4.5,0").added)
  end)

  it("drops an extra field", function()
    schema("E1:1234,1793800000,1,0,0")
    schema("H1:1:5:5")
    schema("W1:" .. OWNER .. ":0:0")
  end)

  it("drops a missing field", function()
    schema("E1:1234,1793800000,1")
    schema("E1:1234")
    schema("H1:0")
    schema("W1:" .. OWNER)
    schema("W1:0")
    schema("H1:")
    schema("E1:")
    schema("W1:")
  end)

  it("drops ;; and a trailing ;", function()
    schema(VALID .. ";;" .. wire(B))
    schema(VALID .. ";")
    schema("E1:;" .. wire(A))
    schema("E1:1234,,1793800000,1,0")
    schema("E1:1234,1793800000,1..2,0")
    schema("E1:1234,1793800000,.1,0")
    schema("E1:1234,1793800000,1.,0")
    schema("E1:1234,1793800000,1,0,")
    schema("H1::0")
    schema("H1:0:")
    schema("W1::0")
  end)

  it("drops a malformed WANT target", function()
    for _, g in ipairs({ "player-1234-0ABCDEF0", "Player--AB", "Player-1-", "Player-1-XYZ",
      "Player-1-AB-CD", "Player-1-" .. ("A"):rep(32), "Creature-0-1-2-3-1234-AB", "Mira" }) do
      schema("W1:" .. g .. ":0")
    end
  end)

  it("drops a GUID or name smuggled into an entry", function()
    schema("E1:" .. BRAM .. ",1234,1793800000,1,0")
    schema(VALID .. ";" .. BRAM)
  end)
end)

describe("SyncProtocol.receive rule 11 (numbers)", function()
  local function number(m)
    local ctx = newCtx()
    assert.same({ nil, "number" }, { recv(ctx, m) }, m)
    assert.equal(0, stored(ctx))
  end

  -- Each field of each message type in turn.
  local function inEachField(tok)
    number("E1:" .. tok .. ",1793800000,1,0")
    number("E1:1234," .. tok .. ",1,0")
    number("E1:1234,1793800000," .. tok .. ",0")
    number("E1:1234,1793800000,1." .. tok .. ",0")
    number("E1:1234,1793800000,1," .. tok)
    number(VALID .. ";" .. tok .. ",1793800000,1,0")
    number("H1:" .. tok .. ":0")
    number("H1:1:" .. tok)
    number("W1:" .. OWNER .. ":" .. tok)
  end

  it("drops NaN", function() inEachField("nan") inEachField("NaN") end)
  it("drops inf", function() inEachField("inf") inEachField("INF") end)
  it("drops an exponent", function() inEachField("1e9") inEachField("1E3") end)
  it("drops hex", function() inEachField("0x1F") inEachField("0X1") end)
  it("drops a signed number", function()
    inEachField("-5")
    -- '+' isn't in the charset at all, so a plus sign fails one rule earlier.
    assert.same({ nil, "charset" }, { recv(newCtx(), "H1:+5:0") })
  end)
  it("drops a decimal", function()
    number("E1:1.5,1793800000,1,0")
    number("E1:1234,1793800000.5,1,0")
    number("E1:1234,1793800000,1,1.5")
    number("H1:1.5:0")
    number("H1:1:1.5")
    number("W1:" .. OWNER .. ":1793800000.5")
  end)
  it("drops a leading zero", function()
    inEachField("007")
    inEachField("00")
    number("E1:1234,0793800000,1,0")
  end)
  it("drops overlong numbers", function()
    inEachField(("9"):rep(200))
    number("E1:12345678,1793800000,1,0")       -- inn: 8 digits
    number("E1:1234,17938000000,1,0")          -- time: 11 digits
    number("E1:1234,179380000,1,0")            -- time: 9 digits
    number("E1:1234,1793800000,10000,0")       -- phrase ID: 5 digits
    number("E1:1234,1793800000,1,1000")        -- seal: 4 digits
    number("H1:100:5")                         -- count: 3 digits
    number("H1:1:12345678901")                 -- digest: 11 digits
    number("H1:1:2147483647")                  -- digest: out of range
    number("W1:" .. OWNER .. ":179380000")      -- since: 9 digits
  end)
  it("drops a zero where the grammar has none", function()
    number("E1:0,1793800000,1,0")
    number("E1:1234,0,1,0")
    number("E1:1234,1793800000,0,0")
    number("E1:1234,1793800000,1.0,0")
  end)
  it("accepts the largest values of each field", function()
    local ctx = newCtx()
    ctx.now = LIMITS.tMax - 300
    assert.equal(1, recv(ctx, "E1:9999999,9999999999,9999.9999.9999.9999.9999,999").added)
    assert.same({ kind = "hello", count = 40, digest = 2147483646 },
      recv(newCtx(), "H1:40:2147483646"))
  end)
end)

describe("SyncProtocol.receive rule 12 (HELLO consistency)", function()
  it("drops HELLO count 41", function()
    assert.same({ nil, "schema" }, { recv(newCtx(), "H1:41:5") })
    assert.same({ nil, "schema" }, { recv(newCtx(), "H1:99:5") })
    assert.same({ kind = "hello", count = 40, digest = 5 }, recv(newCtx(), "H1:40:5"))
  end)

  it("drops count 0 with a non-zero digest", function()
    assert.same({ nil, "schema" }, { recv(newCtx(), "H1:0:5") })
    assert.same({ kind = "hello", count = 0, digest = 0 }, recv(newCtx(), "H1:0:0"))
    assert.same({ kind = "hello", count = 3, digest = 0 }, recv(newCtx(), "H1:3:0"))
  end)
end)

describe("SyncProtocol.receive rule 13 (WANT)", function()
  it("returns a WANT for us", function()
    assert.same({ kind = "want", since = 1793800000 },
      recv(newCtx(), "W1:" .. OWNER .. ":1793800000"))
  end)

  it("records a WANT for someone else as seen", function()
    local ctx = newCtx()
    assert.same({ kind = "want_seen", target = BRAM, since = 1793800000 },
      recv(ctx, "W1:" .. BRAM .. ":1793800000", SENDER, "GUILD"))
    assert.same({ ["GUILD:" .. BRAM] = { at = NOW, since = 1793800000 } }, ctx.wantMemo.seen)
    -- Within 30 s the smaller since is kept; the time moves on.
    ctx.now = NOW + 10
    recv(ctx, "W1:" .. BRAM .. ":1793900000", SENDER, "GUILD")
    assert.same({ at = NOW + 10, since = 1793800000 }, ctx.wantMemo.seen["GUILD:" .. BRAM])
    ctx.now = NOW + 20
    recv(ctx, "W1:" .. BRAM .. ":0", SENDER, "GUILD")
    assert.same({ at = NOW + 20, since = 0 }, ctx.wantMemo.seen["GUILD:" .. BRAM])
    -- After 30 s the old record no longer counts.
    ctx.now = NOW + 51
    recv(ctx, "W1:" .. BRAM .. ":1793900000", SENDER, "GUILD")
    assert.same({ at = NOW + 51, since = 1793900000 }, ctx.wantMemo.seen["GUILD:" .. BRAM])
    -- Keyed by channel: the same target on PARTY is a separate record.
    recv(ctx, "W1:" .. BRAM .. ":0", SENDER, "PARTY")
    assert.same({ at = NOW + 51, since = 0 }, ctx.wantMemo.seen["PARTY:" .. BRAM])
    assert.same({ at = NOW + 51, since = 1793900000 }, ctx.wantMemo.seen["GUILD:" .. BRAM])
  end)

  it("a WANT target is never stored in the ledger", function()
    local ctx = newCtx()
    recv(ctx, "W1:" .. BRAM .. ":0")
    recv(ctx, "W1:" .. OWNER .. ":0")
    assert.same({ own = 0, foreign = 0, travelers = 0 }, ctx.ledger:counts())
    assert.same({}, ctx.ledger:travelers())
  end)

  it("since 0 passes", function()
    assert.same({ kind = "want", since = 0 }, recv(newCtx(), "W1:" .. OWNER .. ":0"))
  end)

  it("drops a since before tMin or more than 300 s ahead", function()
    assert.same({ nil, "number" }, { recv(newCtx(), "W1:" .. OWNER .. ":" .. (TMIN - 1)) })
    assert.same({ nil, "number" }, { recv(newCtx(), "W1:" .. OWNER .. ":" .. (NOW + 301)) })
    assert.same({ nil, "number" }, { recv(newCtx(), "W1:" .. OWNER .. ":9999999999") })
    assert.same({ kind = "want", since = NOW + 300 },
      recv(newCtx(), "W1:" .. OWNER .. ":" .. (NOW + 300)))
    assert.same({ kind = "want", since = TMIN }, recv(newCtx(), "W1:" .. OWNER .. ":" .. TMIN))
  end)

  it("holds the seen memo to 1 000 keys", function()
    local ctx = newCtx()
    local seen = ctx.wantMemo.seen
    for i = 1, 1000 do
      seen["PARTY:" .. guid(i)] = { at = i <= 400 and NOW - 31 or NOW, since = 0 }
    end
    recv(ctx, "W1:" .. BRAM .. ":0")
    local n = 0
    for _ in pairs(seen) do
      n = n + 1
    end
    assert.equal(601, n) -- the 400 expired records were pruned
    assert.is_nil(seen["PARTY:" .. guid(1)])
    assert.is_table(seen["PARTY:" .. BRAM])
  end)
end)

describe("SyncProtocol.receive rule 14 (entry rate)", function()
  it("drops ENTRIES past 80 entries per sender per minute", function()
    local ctx = newCtx()
    local five = E(nth(1), nth(2), nth(3), nth(4), nth(5))
    for _ = 1, 15 do
      assert.is_table(recv(ctx, five))
    end
    assert.is_table(recv(ctx, E(nth(6))))               -- 76
    assert.same({ nil, "rate" }, { recv(ctx, five) })    -- 81: refused, not charged
    assert.is_table(recv(ctx, E(nth(7), nth(8), nth(9), nth(10)))) -- 80
    assert.same({ nil, "rate" }, { recv(ctx, E(nth(11))) })         -- 81
    assert.is_nil(ctx.ledger:signerEntries(MIRA)[11])
    ctx.now = NOW + 60
    assert.equal(1, recv(ctx, E(nth(11))).added)
  end)

  it("counts entries before the per-entry skips", function()
    local ctx = newCtx()
    local unknown = E(entry(5555, NOW - 10), entry(5556, NOW - 10), entry(5557, NOW - 10),
      entry(5558, NOW - 10), entry(5559, NOW - 10))
    for _ = 1, 16 do
      assert.equal(5, recv(ctx, unknown).rejected)
    end
    assert.same({ nil, "rate" }, { recv(ctx, E(nth(1))) })
  end)
end)

describe("SyncProtocol.receive rules 15-16 (per-entry skips)", function()
  it("skips an entry from before tMin", function()
    local ctx = newCtx()
    -- The hook runs only for entries that passed the time window, so it shows rule 15
    -- itself did the skipping (the ledger would refuse the entry too).
    local seen = {}
    ctx.phraseOk = function(ids)
      seen[#seen + 1] = ids[1]
      return true
    end
    local res = recv(ctx, E(entry(1, TMIN - 1, { 5 }), entry(2, TMIN, { 6 })))
    assert.same({ kind = "entries", added = 1, dup = 0, dropped = 0, rejected = 1 }, res)
    assert.same({ entry(2, TMIN, { 6 }) }, ctx.ledger:signerEntries(MIRA))
    assert.same({ 6 }, seen)
  end)

  it("skips an entry 301 s in the future, keeps one 300 s ahead", function()
    local ctx = newCtx()
    local res = recv(ctx, E(entry(1, NOW + 301), entry(2, NOW + 300), entry(3, 9999999999)))
    assert.same({ kind = "entries", added = 1, dup = 0, dropped = 0, rejected = 2 }, res)
    assert.same({ entry(2, NOW + 300) }, ctx.ledger:signerEntries(MIRA))
  end)

  it("skips an unknown inn but keeps its valid siblings", function()
    local ctx = newCtx()
    local res = recv(ctx, E(A, entry(5555, NOW), B))
    assert.same({ kind = "entries", added = 2, dup = 0, dropped = 0, rejected = 1 }, res)
    assert.same({ A, B }, ctx.ledger:signerEntries(MIRA))
  end)

  it("skips an unknown phrase ID", function()
    local ctx = newCtx()
    local res = recv(ctx, E(A, entry(5, NOW, { 1, 77, 2 }), entry(6, NOW, { 77 })))
    assert.same({ kind = "entries", added = 1, dup = 0, dropped = 0, rejected = 2 }, res)
    assert.same({ A }, ctx.ledger:signerEntries(MIRA))
  end)

  it("skips an unknown seal", function()
    local ctx = newCtx()
    local res = recv(ctx, E(A, entry(5, NOW, { 1 }, 50), entry(6, NOW, { 1 }, 20)))
    assert.same({ kind = "entries", added = 2, dup = 0, dropped = 0, rejected = 1 }, res)
    assert.same({ A, entry(6, NOW, { 1 }, 20) }, ctx.ledger:signerEntries(MIRA))
  end)

  it("a permissive phraseOk can't admit an unknown ID", function()
    local ctx = newCtx()
    ctx.phraseOk = function() return true end
    local res = recv(ctx, E(entry(5, NOW, { 77 }), entry(5555, NOW), entry(6, NOW, { 1 }, 50), A))
    assert.equal(3, res.rejected)
    assert.same({ A }, ctx.ledger:signerEntries(MIRA))
  end)

  it("a phraseOk can reject more, gets a copy, and only a plain true admits", function()
    local ctx = newCtx()
    local calls = {}
    ctx.phraseOk = function(ids)
      calls[#calls + 1] = { unpack(ids) }
      local first = ids[1]
      ids[1] = 3 -- tampering with the argument changes nothing stored
      if first == 2 then
        return 1 -- truthy but not true
      end
      return first ~= 4
    end
    local res = recv(ctx, E(entry(5, NOW, { 1, 22 }), entry(6, NOW, { 4 }),
      entry(7, NOW, { 2 })))
    assert.same({ kind = "entries", added = 1, dup = 0, dropped = 0, rejected = 2 }, res)
    assert.same({ { 1, 22 }, { 4 }, { 2 } }, calls)
    assert.same({ entry(5, NOW, { 1, 22 }) }, ctx.ledger:signerEntries(MIRA))
  end)

  it("a phraseOk that throws rejects the entry quietly", function()
    local ctx = newCtx()
    ctx.phraseOk = raise
    assert.same({ kind = "entries", added = 0, dup = 0, dropped = 0, rejected = 1 },
      recv(ctx, VALID))
    assert.equal(0, stored(ctx))
  end)

  it("counts an addForeign refusal as rejected", function()
    -- A clock before tMin passes the ctx check, but the ledger refuses the write.
    local ctx = newCtx()
    ctx.now = TMIN - 1
    assert.same({ kind = "entries", added = 0, dup = 0, dropped = 0, rejected = 1 },
      recv(ctx, E(entry(1, TMIN + 10))))
  end)
end)

describe("SyncProtocol.receive rules 17-19 (own signature, dedupe, caps)", function()
  it("stores a relayed copy of B's entry under the relayer A, never under B", function()
    local ctx = newCtx()
    -- Bram signed A; Mira relays it word for word.
    assert.equal(1, recv(ctx, VALID, { guid = BRAM, name = "Bram" }).added)
    assert.equal(1, recv(ctx, VALID, SENDER).added)
    assert.same({ A }, ctx.ledger:signerEntries(MIRA))
    assert.same({ A }, ctx.ledger:signerEntries(BRAM))
    -- A relay of an entry Bram never sent us lands only under Mira.
    local ctx2 = newCtx()
    recv(ctx2, VALID, SENDER)
    assert.is_true(ctx2.ledger:has(MIRA, A.inn, A.t))
    assert.is_false(ctx2.ledger:has(BRAM, A.inn, A.t))
    assert.same({}, ctx2.ledger:signerEntries(BRAM))
    assert.equal(NAME, ctx2.ledger:travelers()[1].name)
  end)

  it("a GUID inside an entry is dropped and nothing is stored", function()
    for _, m in ipairs({
      "E1:" .. BRAM .. ",1234,1793800000,1,0",
      "E1:1234,1793800000,1," .. BRAM,
      "E1:1234,1793800000," .. BRAM .. ",0",
      "E1:1234,1793800000,1,0," .. BRAM,
      "E1:1234,1793800000,1,0,Bram",
      "E1:1234,1793800000,Bram,0",
      VALID .. ";" .. BRAM .. ",1234,1793800000,1,0",
    }) do
      local ctx = newCtx()
      local res = recv(ctx, m)
      assert.is_nil(res, m)
      assert.same({ own = 0, foreign = 0, travelers = 0 }, ctx.ledger:counts())
    end
  end)

  it("replaying an ENTRIES 1 000 times leaves storage unchanged", function()
    local ctx = newCtx()
    local msg = E(A, B)
    assert.equal(2, recv(ctx, msg).added)
    local before = ctx.ledger:signerEntries(MIRA)
    local dups, rated = 0, 0
    for i = 1, 1000 do
      ctx.now = NOW + math.floor(i / 40) * 60 -- fresh windows, so replays reach the ledger
      local res, reason = recv(ctx, msg)
      if res then
        dups = dups + res.dup
        assert.equal(0, res.added)
      else
        assert.equal("rate", reason)
        rated = rated + 1
      end
    end
    assert.equal(2000, dups)
    assert.equal(0, rated)
    assert.same(before, ctx.ledger:signerEntries(MIRA))
    assert.equal(2, stored(ctx))
  end)

  it("replayed at one time, the limiter trips at the 41st", function()
    local ctx = newCtx()
    for i = 1, 1000 do
      local res, reason = recv(ctx, VALID)
      if i <= 40 then
        assert.is_table(res)
      else
        assert.equal("rate", reason)
      end
    end
    assert.equal(1, stored(ctx))
  end)

  it("a conflicting re-send doesn't overwrite", function()
    local ctx = newCtx()
    recv(ctx, VALID)
    assert.same({ kind = "entries", added = 0, dup = 1, dropped = 0, rejected = 0 },
      recv(ctx, "E1:1234,1793800000,4.5,9"))
    assert.same({ A }, ctx.ledger:signerEntries(MIRA))
  end)

  it("a second signature at one inn in one week is rejected, siblings kept", function()
    local ctx = newCtx()
    recv(ctx, VALID)
    local res = recv(ctx, E(entry(1234, A.t + 100, { 2 }), entry(98765, A.t + 100, { 3 })))
    assert.same({ kind = "entries", added = 1, dup = 0, dropped = 0, rejected = 1 }, res)
    assert.same({ A, entry(98765, A.t + 100, { 3 }) }, ctx.ledger:signerEntries(MIRA))
  end)

  it("counts an entry the caps evict at once as dropped", function()
    local ctx = newCtx()
    for i = 1, 40 do
      assert.equal("added", ctx.ledger:addForeign(MIRA, NAME, nth(i), NOW))
    end
    local res = recv(ctx, E(entry(41, NOW - 200000)))
    assert.same({ kind = "entries", added = 0, dup = 0, dropped = 1, rejected = 0 }, res)
    assert.equal(40, stored(ctx))
  end)
end)

describe("SyncProtocol hostile input", function()
  it("a valid ENTRIES truncated at every byte is a drop or a valid shorter message", function()
    local full = E(A, B, entry(5, 1793950000, { 2, 3 }, 1))
    for i = 0, #full do
      local ctx = newCtx()
      local res, reason = recv(ctx, full:sub(1, i))
      assert.not_equal("error", reason)
      if res then
        assert.equal("entries", res.kind)
        assert.equal(res.added, stored(ctx))
      else
        assert.is_string(reason)
        assert.equal(0, stored(ctx))
      end
    end
  end)

  it("1 000 seeded random strings never throw and never store", function()
    local rand = rng(20260927)
    local alphabet = "0123456789HWEPlayer:;,.-"
    local heads = { "", "E1:", "H1:", "W1:", "E1:1234,", "\001", "|c" }
    local ctx = newCtx()
    for n = 1, 1000 do
      local len = rand(300)
      local bytes = {}
      for i = 1, len do
        if n % 2 == 0 then
          bytes[i] = string.char(rand(256))
        else
          local k = rand(#alphabet) + 1
          bytes[i] = alphabet:sub(k, k)
        end
      end
      local msg = heads[rand(#heads) + 1] .. table.concat(bytes)
      ctx.limiter = SP.newLimiter()
      local ok, res, reason = pcall(SP.receive, msg, "PARTY", SENDER, ctx)
      assert.is_true(ok)
      assert.not_equal("error", reason)
      if res and res.kind == "entries" then
        assert.equal(0, res.added + res.dropped)
      end
    end
    assert.same({ own = 0, foreign = 0, travelers = 0 }, ctx.ledger:counts())
  end)

  it("hidden-value stand-ins in any position drop, don't throw, store nothing", function()
    for _, v in ipairs({ hostileTable(), hostileProxy() }) do
      local positions = {
        function(ctx) return v, "PARTY", SENDER, ctx end,
        function(ctx) return VALID, v, SENDER, ctx end,
        function(ctx) return VALID, "PARTY", v, ctx end,
        function(ctx) return VALID, "PARTY", { guid = v, name = NAME }, ctx end,
        function(ctx) return VALID, "PARTY", { guid = MIRA, name = v }, ctx end,
        function(ctx) return VALID, "PARTY", SENDER, v, ctx end,
        function(ctx)
          ctx.selfGUID = v
          return VALID, "PARTY", SENDER, ctx
        end,
      }
      for i, args in ipairs(positions) do
        local ctx = newCtx()
        local m, ch, s, c = args(ctx)
        local ok, res = pcall(SP.receive, m, ch, s, c)
        assert.is_true(ok, "position " .. i)
        assert.is_nil(res, "position " .. i)
        assert.equal(0, stored(ctx))
      end
    end
  end)
end)

describe("SyncProtocol limiter", function()
  it("admits 40 messages per sender per window, then resets after 60 s", function()
    local l = SP.newLimiter()
    for _ = 1, 40 do
      assert.is_true(l:admit(MIRA, NOW))
    end
    assert.is_false(l:admit(MIRA, NOW + 59))
    assert.is_true(l:admit(MIRA, NOW + 60))
  end)

  it("resets a window when now goes backwards", function()
    local l = SP.newLimiter()
    for _ = 1, 40 do
      assert.is_true(l:admit(MIRA, NOW))
    end
    assert.is_false(l:admit(MIRA, NOW))
    assert.is_true(l:admit(MIRA, NOW - 1))
    local ctx = newCtx()
    for _ = 1, 41 do
      recv(ctx, "H1:0:0")
    end
    ctx.now = NOW - 5
    assert.is_table(recv(ctx, "H1:0:0"))
  end)

  it("caps admitted messages across all senders at 1 200 a window", function()
    local ctx = newCtx()
    for s = 1, 30 do
      for _ = 1, 40 do
        assert.is_table(recv(ctx, "H1:0:0", { guid = guid(s), name = NAME }))
      end
    end
    -- The 1 201st admitted message would come from a fresh sender.
    assert.same({ nil, "rate" }, { recv(ctx, "H1:0:0", { guid = guid(31), name = NAME }) })
    ctx.now = NOW + 60
    assert.is_table(recv(ctx, "H1:0:0", { guid = guid(31), name = NAME }))
  end)

  it("one sender's 1 000 messages don't stop a second sender (refusals aren't counted)",
    function()
      local ctx = newCtx()
      local refused = 0
      for _ = 1, 1000 do
        if not recv(ctx, "H1:0:0") then
          refused = refused + 1
        end
      end
      assert.equal(960, refused)
      assert.is_table(recv(ctx, "H1:0:0", { guid = BRAM, name = "Bram" }))
      -- Exactly 41 admitted so far: 1 159 more fit in the global window, and no more.
      local admitted = 41
      for s = 1, 29 do
        for _ = 1, 40 do
          if recv(ctx, "H1:0:0", { guid = guid(s), name = NAME }) then
            admitted = admitted + 1
          end
        end
      end
      assert.equal(1200, admitted)
      assert.same({ nil, "rate" }, { recv(ctx, "H1:0:0", { guid = BRAM, name = "Bram" }) })
    end)

  it("tracks at most 1 000 senders: prunes expired windows, else fails closed", function()
    local l = SP.newLimiter()
    for s = 1, 1000 do
      assert.is_true(l:admit(guid(s), s <= 400 and NOW or NOW + 30))
    end
    assert.is_false(l:admit(guid(1001), NOW + 30))  -- full, nothing expired
    assert.is_true(l:admit(guid(1), NOW + 30))       -- known senders still go on
    assert.is_true(l:admit(guid(1001), NOW + 60))    -- 400 expired windows pruned
    assert.equal(601, l.count)
    local n = 0
    for _ in pairs(l.senders) do
      n = n + 1
    end
    assert.equal(601, n)
  end)

  it("drops the 1 001st sender through receive", function()
    local ctx = newCtx()
    for s = 1, 1000 do
      assert.is_table(recv(ctx, "H1:0:0", { guid = guid(s), name = NAME }))
    end
    assert.same({ nil, "rate" }, { recv(ctx, "H1:0:0", { guid = guid(1001), name = NAME }) })
  end)

  it("admits 80 entries per sender per window, charging no refused batch", function()
    local l = SP.newLimiter()
    assert.is_false(l:admitEntries(MIRA, 1, NOW)) -- no admitted message yet
    assert.is_true(l:admit(MIRA, NOW))
    for _ = 1, 16 do
      assert.is_true(l:admitEntries(MIRA, 5, NOW))
    end
    assert.is_false(l:admitEntries(MIRA, 1, NOW))
    assert.is_true(l:admitEntries(MIRA, 0, NOW))
    assert.is_false(l:admitEntries(MIRA, 1, NOW + 60)) -- the window closed
    assert.is_true(l:admit(MIRA, NOW + 60))
    assert.is_true(l:admitEntries(MIRA, 5, NOW + 60))
  end)

  it("refuses bad arguments", function()
    local l = SP.newLimiter()
    for _, v in ipairs(hostiles()) do
      if type(v) ~= "string" then -- any string is a key; receive checks GUIDs first
        assert.is_false(l:admit(v, NOW))
      end
      assert.is_false(l:admit(MIRA, v))
    end
    assert.is_false(l:admit(MIRA, NOW + 0.5))
    assert.is_true(l:admit(MIRA, NOW))
    assert.is_false(l:admitEntries(MIRA, 6, NOW))
    assert.is_false(l:admitEntries(MIRA, -1, NOW))
    assert.is_false(l:admitEntries(MIRA, 0 / 0, NOW))
    assert.is_false(l:admitEntries(MIRA, 1, 0 / 0))
    assert.is_false(l:admitEntries(hostileTable(), 1, NOW))
  end)
end)

describe("SyncProtocol.decideWant", function()
  local HELD = { A, B }
  local DIG = SP.digest(HELD)

  local function ask(memo, count, dig, held, now, channel, peer)
    return SP.decideWant(memo, peer or MIRA, channel or "PARTY", count, dig, held or HELD,
      now or NOW)
  end

  it("in sync -> nil", function()
    local memo = SP.newWantMemo()
    assert.is_nil(ask(memo, 2, DIG))
    assert.same({ asked = {}, seen = {} }, memo)
  end)

  it("count 0 -> nil", function()
    assert.is_nil(ask(SP.newWantMemo(), 0, 0))
    assert.is_nil(ask(SP.newWantMemo(), 0, 0, {}))
  end)

  it("first mismatch -> newest held t", function()
    local memo = SP.newWantMemo()
    assert.equal(B.t, ask(memo, 3, 5))
    assert.same({ start = NOW, n = 1 }, memo.asked[MIRA])
    assert.same({ at = NOW, since = B.t }, memo.seen["PARTY:" .. MIRA])
    -- Same count, different digest: also a mismatch.
    assert.equal(B.t, ask(SP.newWantMemo(), 2, DIG + 1))
  end)

  it("nothing held -> 0", function()
    assert.equal(0, ask(SP.newWantMemo(), 4, 5, {}))
  end)

  it("second ask within 10 min -> 0, even with a different digest", function()
    local memo = SP.newWantMemo()
    assert.equal(B.t, ask(memo, 3, 5))
    assert.equal(0, ask(memo, 4, 6, nil, NOW + 100))
    assert.same({ start = NOW, n = 2 }, memo.asked[MIRA])
  end)

  it("third -> nil for 10 min whatever the digest, then allowed again", function()
    local memo = SP.newWantMemo()
    ask(memo, 3, 5)
    ask(memo, 3, 5, nil, NOW + 100)
    for d = 1, 20 do
      assert.is_nil(ask(memo, 3, d, nil, NOW + 100 + d * 20))
    end
    assert.is_nil(ask(memo, 3, 5, nil, NOW + 599))
    assert.equal(B.t, ask(memo, 3, 5, nil, NOW + 600))
    assert.same({ start = NOW + 600, n = 1 }, memo.asked[MIRA])
  end)

  it("a record from the future (the clock went back) doesn't count", function()
    local memo = SP.newWantMemo()
    memo.asked[MIRA] = { start = NOW + 50, n = 2 }
    assert.equal(B.t, ask(memo, 3, 5))
  end)

  it("suppressed by a WANT seen on the same channel within 30 s with a smaller since", function()
    for _, s in ipairs({ { NOW - 30, 0 }, { NOW, B.t }, { NOW - 1, B.t - 1 } }) do
      local memo = SP.newWantMemo()
      memo.seen["PARTY:" .. MIRA] = { at = s[1], since = s[2] }
      assert.is_nil(ask(memo, 3, 5))
      assert.same({}, memo.asked) -- a suppressed call doesn't use up an ask
    end
  end)

  it("not suppressed at 31 s, with a larger since, from the future or another channel",
    function()
      for _, s in ipairs({
        { "PARTY", NOW - 31, 0 }, { "PARTY", NOW, B.t + 1 }, { "PARTY", NOW + 1, 0 },
        { "GUILD", NOW, 0 }, { "RAID", NOW, 0 },
      }) do
        local memo = SP.newWantMemo()
        memo.seen[s[1] .. ":" .. MIRA] = { at = s[2], since = s[3] }
        assert.equal(B.t, ask(memo, 3, 5))
      end
    end)

  it("a WANT seen on GUILD suppresses a GUILD ask, not a PARTY ask", function()
    local ctx = newCtx()
    recv(ctx, "W1:" .. MIRA .. ":0", { guid = BRAM, name = "Bram" }, "GUILD")
    assert.is_nil(ask(ctx.wantMemo, 3, 5, nil, NOW + 3, "GUILD"))
    assert.equal(B.t, ask(ctx.wantMemo, 3, 5, nil, NOW + 3, "PARTY"))
  end)

  it("a suppressed call doesn't use up the peer's two asks", function()
    local memo = SP.newWantMemo()
    memo.seen["PARTY:" .. MIRA] = { at = NOW, since = 0 }
    assert.is_nil(ask(memo, 3, 5))
    assert.is_nil(ask(memo, 3, 5, nil, NOW + 10))
    assert.equal(B.t, ask(memo, 3, 5, nil, NOW + 31))
    assert.equal(0, ask(memo, 3, 5, nil, NOW + 40))
    assert.is_nil(ask(memo, 3, 5, nil, NOW + 50))
  end)

  it("prunes asked at 1 000 keys, then clears it", function()
    local memo = SP.newWantMemo()
    for i = 1, 1000 do
      memo.asked[guid(i)] = { start = i <= 300 and NOW - 600 or NOW, n = 1 }
    end
    assert.equal(B.t, ask(memo, 3, 5))
    local n = 0
    for _ in pairs(memo.asked) do
      n = n + 1
    end
    assert.equal(701, n)
    assert.is_nil(memo.asked[guid(1)])
    assert.is_table(memo.asked[guid(301)])

    memo = SP.newWantMemo()
    for i = 1, 1000 do
      memo.asked[guid(i)] = { start = NOW, n = 1 }
    end
    assert.equal(B.t, ask(memo, 3, 5))
    assert.same({ [MIRA] = { start = NOW, n = 1 } }, memo.asked)
  end)

  it("prunes seen at 1 000 keys, then clears it", function()
    local memo = SP.newWantMemo()
    for i = 1, 1000 do
      memo.seen["RAID:" .. guid(i)] = { at = i <= 300 and NOW - 31 or NOW, since = 0 }
    end
    assert.equal(B.t, ask(memo, 3, 5))
    local n = 0
    for _ in pairs(memo.seen) do
      n = n + 1
    end
    assert.equal(701, n)

    memo = SP.newWantMemo()
    for i = 1, 1000 do
      memo.seen["RAID:" .. guid(i)] = { at = NOW, since = 0 }
    end
    assert.equal(B.t, ask(memo, 3, 5))
    assert.same({ ["PARTY:" .. MIRA] = { at = NOW, since = B.t } }, memo.seen)
  end)

  it("returns nil on bad arguments", function()
    local memo = SP.newWantMemo()
    assert.is_nil(SP.decideWant(nil, MIRA, "PARTY", 3, 5, HELD, NOW))
    assert.is_nil(SP.decideWant({}, MIRA, "PARTY", 3, 5, HELD, NOW))
    assert.is_nil(SP.decideWant(memo, nil, "PARTY", 3, 5, HELD, NOW))
    assert.is_nil(SP.decideWant(memo, MIRA, nil, 3, 5, HELD, NOW))
    assert.is_nil(SP.decideWant(memo, MIRA, "PARTY", 41, 5, HELD, NOW))
    assert.is_nil(SP.decideWant(memo, MIRA, "PARTY", 3, 0 / 0, HELD, NOW))
    assert.is_nil(SP.decideWant(memo, MIRA, "PARTY", 3, 5, nil, NOW))
    assert.is_nil(SP.decideWant(memo, MIRA, "PARTY", 3, 5, HELD, 1.5))
    assert.same({ asked = {}, seen = {} }, memo)
  end)
end)
