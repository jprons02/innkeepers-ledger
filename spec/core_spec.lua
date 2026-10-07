-- Core: opening the character's ledger at login, the weekly anchor, the debug log
-- (docs/specs/sync-glue.md 3.2, 3.8 and 6.3). The whole AddOn runs under the WoW stub.
local load = require("helpers.load")
local wow = require("helpers.wow_stub")

local GUID = "Player-1-00000001" -- the stub's UnitGUID("player")
local NOW = 1800000000           -- the stub's default server time
local US_RESET = 1790089200      -- Tuesday 2026-09-22 15:00 UTC
local T_MAX = 9999999999

-- A stand-in for a hidden ("secret") value: touching it in any way raises.
local function secret()
  local value = newproxy(true)
  local mt = getmetatable(value)
  local function touched() error("a hidden value was touched", 2) end
  for _, event in ipairs({ "__index", "__newindex", "__call", "__eq", "__lt", "__le",
    "__concat", "__len", "__tostring", "__unm", "__add", "__sub", "__mul", "__div",
    "__mod", "__pow" }) do
    mt[event] = touched
  end
  return value
end

-- A table that raises if it's ever indexed with `key`.
local function watched(key, contents)
  local function check(_, k)
    if rawequal(k, key) then
      error("a table was indexed with a hidden value", 2)
    end
  end
  return setmetatable(contents or {}, { __index = check, __newindex = function(t, k, v)
    check(t, k)
    rawset(t, k, v)
  end })
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

-- Loads the AddOn and logs in. opts: overrides (stub names), db (the SavedVariables as
-- saved), setup(ns) (runs after the files load, before ADDON_LOADED), atLogin (stub names
-- set after ADDON_LOADED, before PLAYER_LOGIN: AceDB reads UnitName itself when it
-- initializes).
local function login(opts)
  opts = opts or {}
  wow.install(opts.overrides)
  if opts.db ~= nil then
    _G.InnkeepersLedgerDB = opts.db
  end
  local ns = load.addon({})
  if opts.setup then
    opts.setup(ns)
  end
  wow.fire("ADDON_LOADED", load.ADDON_NAME)
  for name, value in pairs(opts.atLogin or {}) do
    _G[name] = value
  end
  wow.fire("PLAYER_LOGIN")
  return ns
end

-- Counts ns.Sync:Start() calls.
local function countStarts(ns, counter)
  ns.Sync.Start = function(self)
    assert.equal(ns.Sync, self)
    counter.n = counter.n + 1
  end
end

-- Records the weekAnchor that Ledger.new is given.
local function recordAnchors(ns, anchors)
  local real = ns.Ledger.new
  ns.Ledger.new = function(data, owner, anchor)
    anchors[#anchors + 1] = anchor
    return real(data, owner, anchor)
  end
end

-- Stub overrides for a GetSecondsUntilWeeklyReset that returns `value`.
local function resetIn(value)
  return { C_DateAndTime = { GetSecondsUntilWeeklyReset = function() return value end } }
end

-- The saved ledgers table, or nil if nothing has created it (AceDB adds `global` lazily).
local function savedLedgers()
  return (rawget(_G.InnkeepersLedgerDB, "global") or {}).ledgers
end

local function saved()
  return _G.InnkeepersLedgerDB.global.ledgers
end

local function chatHas(text)
  for _, line in ipairs(wow.chat) do
    if line:find(text, 1, true) then
      return true
    end
  end
  return false
end

describe("Core opening the ledger at login", function()
  after_each(wow.uninstall)

  it("opens db.global.ledgers[guid] as schema 1, sets ns.ledger and starts Sync", function()
    local starts = { n = 0 }
    local ns = login({ setup = function(ns) countStarts(ns, starts) end })
    assert.same({}, wow.errors)
    assert.is_table(ns.ledger)
    assert.is_false(ns.ledger.readOnly)
    assert.equal(GUID, ns.ledger:ownerGUID())
    local data = saved()[GUID]
    assert.equal(1, data.schema)
    assert.equal(data, ns.ledger.data)
    assert.same({ name = "Traveler" }, data.me)
    assert.equal(1, starts.n)
  end)

  it("reopens the same saved table at the next login (round trip)", function()
    local ns = login()
    local e = { inn = 1234, t = NOW - 60, phrase = { 1, 2 } }
    assert.equal("added", ns.ledger:addOwn(e))
    local db = deepcopy(_G.InnkeepersLedgerDB)
    wow.uninstall()

    ns = login({ db = db })
    assert.same({}, wow.errors)
    assert.is_false(ns.ledger.readOnly)
    assert.same({ e }, ns.ledger:own())
    assert.equal(saved()[GUID], ns.ledger.data)
    assert.equal(1, #saved()[GUID].own)
  end)

  describe("owner GUID", function()
    local function guidAfter(readable, calls)
      return function(unit)
        if unit ~= "player" then return nil end
        calls.n = calls.n + 1
        if calls.n >= readable then
          return GUID
        end
      end
    end

    it("retries a nil GUID every 2 s and opens once it's readable (3rd retry)", function()
      local calls, starts = { n = 0 }, { n = 0 }
      local ns = login({
        overrides = { UnitGUID = guidAfter(4, calls) },
        setup = function(ns) countStarts(ns, starts) end,
      })
      assert.equal(1, calls.n)
      assert.is_nil(ns.ledger)
      assert.is_nil(savedLedgers())
      wow.advance(1)
      assert.equal(1, calls.n)
      wow.advance(1)
      assert.equal(2, calls.n)
      wow.advance(4)
      assert.equal(4, calls.n)
      assert.is_table(ns.ledger)
      assert.equal(GUID, ns.ledger:ownerGUID())
      assert.equal(1, starts.n)
      wow.advance(30)
      assert.equal(4, calls.n)
      assert.equal(1, starts.n)
      assert.same({}, wow.errors)
    end)

    it("opens on the 5th and last attempt", function()
      local calls = { n = 0 }
      local ns = login({ overrides = { UnitGUID = guidAfter(5, calls) } })
      wow.advance(8)
      assert.equal(5, calls.n)
      assert.is_table(ns.ledger)
    end)

    it("gives up after 5 attempts: no ledger, no Sync, nothing written", function()
      local calls, starts = { n = 0 }, { n = 0 }
      local ns = login({
        overrides = { UnitGUID = guidAfter(math.huge, calls) },
        setup = function(ns) countStarts(ns, starts) end,
      })
      wow.advance(60)
      assert.equal(5, calls.n)
      assert.is_nil(ns.ledger)
      assert.equal(0, starts.n)
      assert.is_nil(savedLedgers())
      assert.same({}, wow.timers)
      assert.same({}, wow.errors)
      wow.slash("/ledger debug")
      assert.is_true(chatHas("ledger: no GUID"))
    end)

    it("treats a GUID that isn't a player GUID as unreadable", function()
      for _, bad in ipairs({ "Creature-0-1-2-3-4-5", "", 42, "Player-1-00000001 ",
        ("Player-1-" .. ("A"):rep(40)) }) do
        local calls = { n = 0 }
        local ns = login({ overrides = { UnitGUID = function(unit)
          if unit == "player" then
            calls.n = calls.n + 1
            return bad
          end
        end } })
        wow.advance(10)
        assert.equal(5, calls.n)
        assert.is_nil(ns.ledger)
        assert.is_nil(savedLedgers())
        wow.uninstall()
      end
    end)

    it("treats a raising UnitGUID as unreadable", function()
      local ns = login({ overrides = { UnitGUID = function() error("boom") end } })
      wow.advance(10)
      assert.is_nil(ns.ledger)
      assert.same({}, wow.errors)
    end)

    it("treats a hidden GUID as unreadable and never indexes a table with it", function()
      local hiddenGUID = secret()
      local calls, starts = { n = 0 }, { n = 0 }
      local ledgers = watched(hiddenGUID)
      local ns = login({
        overrides = {
          UnitGUID = function(unit)
            if unit == "player" then
              calls.n = calls.n + 1
              return hiddenGUID
            end
          end,
          issecretvalue = function(v) return rawequal(v, hiddenGUID) end,
        },
        db = { global = watched(hiddenGUID, { ledgers = ledgers }) },
        setup = function(ns) countStarts(ns, starts) end,
      })
      wow.advance(10)
      assert.equal(5, calls.n)
      assert.is_nil(ns.ledger)
      assert.equal(0, starts.n)
      assert.is_nil(next(ledgers))
      assert.same({}, wow.errors)
    end)

    it("never touches a hidden GUID even when issecretvalue is missing", function()
      local hiddenGUID = secret()
      local ns = login({
        overrides = { UnitGUID = function() return hiddenGUID end },
        setup = function() _G.issecretvalue = nil end,
      })
      wow.advance(10)
      assert.is_nil(ns.ledger)
      assert.same({}, wow.errors)
    end)

    it("counts an issecretvalue that raises as hidden", function()
      local ns = login({ overrides = { issecretvalue = function() error("boom") end } })
      wow.advance(10)
      assert.is_nil(ns.ledger)
      assert.same({}, wow.errors)
    end)

    -- In the client a hidden GUID is still a string, so only issecretvalue can tell.
    it("treats a valid-looking GUID that issecretvalue flags as unreadable", function()
      local starts = { n = 0 }
      local ledgers = watched(GUID)
      local ns = login({
        overrides = { issecretvalue = function(v) return v == GUID end },
        db = { global = watched(GUID, { ledgers = ledgers }) },
        setup = function(ns) countStarts(ns, starts) end,
      })
      wow.advance(10)
      assert.is_nil(ns.ledger)
      assert.equal(0, starts.n)
      assert.is_nil(next(ledgers))
      assert.same({}, wow.errors)
    end)

    it("checks a GUID for hidden before anything else touches it", function()
      local ns = login({
        overrides = { issecretvalue = function(v) return v == GUID end },
        setup = function(ns)
          local validGUID = ns.Ledger.validGUID
          ns.Ledger.validGUID = function(s)
            assert(s ~= GUID, "validGUID was given a hidden GUID")
            return validGUID(s)
          end
        end,
      })
      wow.advance(10)
      assert.same({}, wow.errors)
      assert.is_nil(ns.ledger)
    end)
  end)

  describe("owner name", function()
    -- Both name functions answer `fn`: Core reads UnitFullName and falls back to UnitName,
    -- so a case that stubbed only one would still read the stub's own name.
    local function names(fn, extra)
      local t = { UnitFullName = fn, UnitName = fn }
      for k, v in pairs(extra or {}) do
        t[k] = v
      end
      return t
    end

    it("opens with me = {} for a valid-looking name that issecretvalue flags", function()
      local ns = login({ overrides = { issecretvalue = function(v) return v == "Traveler" end } })
      assert.is_false(ns.ledger.readOnly)
      assert.same({}, saved()[GUID].me)
    end)

    it("opens with me = {} for a hidden name", function()
      local hiddenName = secret()
      local ns = login({ atLogin = names(function() return hiddenName end, {
        issecretvalue = function(v) return rawequal(v, hiddenName) end,
      }) })
      assert.same({}, wow.errors)
      assert.is_false(ns.ledger.readOnly)
      assert.same({}, saved()[GUID].me)
    end)

    it("opens with me = {} for a name that isn't a string", function()
      for _, bad in ipairs({ 42, true, {} }) do
        local ns = login({ atLogin = names(function() return bad end) })
        assert.is_false(ns.ledger.readOnly)
        assert.same({}, saved()[GUID].me)
        wow.uninstall()
      end
    end)

    it("opens with me = {} when the name functions raise or aren't functions", function()
      for _, bad in ipairs({ function() error("boom") end, 42 }) do
        local ns = login({ atLogin = names(bad) })
        assert.is_table(ns.ledger)
        assert.same({}, saved()[GUID].me)
        wow.uninstall()
      end
    end)

    it("reads UnitFullName first, and UnitName only when UnitFullName is missing", function()
      local ns = login({ atLogin = {
        UnitFullName = function() return "Wayfarer", "Stubrealm" end,
        UnitName = function() return "Other" end,
      } })
      assert.equal("Wayfarer", ns.ledger.data.me.name)
      wow.uninstall()

      ns = login({ atLogin = {
        UnitFullName = false,
        UnitName = function() return "Other" end,
      } })
      assert.equal("Other", ns.ledger.data.me.name)
    end)

    it("updates me.name for a renamed character", function()
      login()
      assert.equal("Traveler", saved()[GUID].me.name)
      local db = deepcopy(_G.InnkeepersLedgerDB)
      wow.uninstall()

      local ns = login({ db = db, atLogin = names(function() return "Wayfarer" end) })
      assert.equal("Wayfarer", saved()[GUID].me.name)
      assert.equal(ns.ledger.data, saved()[GUID])
    end)

    it("stores First Surname on a two-part (Forever) client", function()
      local ns = login({ overrides = wow.foreverNames("Traveler", "Wayfarer") })
      assert.same({}, wow.errors)
      assert.equal("Traveler Wayfarer", saved()[GUID].me.name)
      assert.equal("Traveler Wayfarer", ns.ledger.data.me.name)
    end)

    it("keeps the first name alone when the surname can't be told from a realm", function()
      local hiddenSlot = secret()
      local cases = {
        ["our realm in the slot"] = { atLogin = names(
          function() return "Traveler", "ClassicBetaPvP" end) },
        ["a spaced realm in the slot"] = { atLogin = names(
          function() return "Traveler", "Classic Beta PvP" end) },
        ["no realm"] = { atLogin = { GetNormalizedRealmName = function() return nil end } },
        ["a raising realm"] = { atLogin = {
          GetNormalizedRealmName = function() error("boom") end } },
        ["a hidden realm"] = { atLogin = {
          issecretvalue = function(v) return v == "ClassicBetaPvP" end } },
        ["a hidden slot"] = { atLogin = names(function() return "Traveler", hiddenSlot end, {
          issecretvalue = function(v) return rawequal(v, hiddenSlot) end }) },
      }
      for label, case in pairs(cases) do
        login({ overrides = wow.foreverNames("Traveler", "Wayfarer"), atLogin = case.atLogin })
        assert.same({}, wow.errors, label)
        assert.equal("Traveler", saved()[GUID].me.name, label)
        wow.uninstall()
      end
    end)

    it("leaves me empty when First Surname fails the name rule", function()
      login({ overrides = wow.foreverNames("Traveler", "Way|farer") })
      assert.same({}, saved()[GUID].me)
    end)

    it("keeps the stored name when the new one fails the name rule", function()
      login()
      local db = deepcopy(_G.InnkeepersLedgerDB)
      wow.uninstall()

      local ns = login({ db = db, atLogin = names(function() return "x|cffff" end) })
      assert.is_table(ns.ledger)
      assert.equal("Traveler", saved()[GUID].me.name)
    end)
  end)

  describe("weekly anchor", function()
    local function anchorWith(overrides, setup, atLogin)
      local anchors = {}
      login({ overrides = overrides, atLogin = atLogin, setup = function(ns)
        recordAnchors(ns, anchors)
        if setup then setup(ns) end
      end })
      assert.same({}, wow.errors)
      assert.equal(1, #anchors)
      return anchors[1]
    end

    it("comes from the API, rounded to the nearest minute", function()
      assert.equal(NOW + 259200, anchorWith())
      assert.equal(NOW + 3600, anchorWith(resetIn(3629)))
      assert.equal(NOW + 3660, anchorWith(resetIn(3631)))
      assert.equal(NOW, anchorWith(resetIn(0)))
      assert.equal(NOW + 604860, anchorWith(resetIn(604860)))
    end)

    it("falls back to the region table for any bad API result", function()
      local hiddenSecs = secret()
      local cases = {
        missing = { setup = function() _G.C_DateAndTime = nil end },
        ["not a table"] = { overrides = { C_DateAndTime = "junk" } },
        ["no function"] = { overrides = { C_DateAndTime = {} } },
        erroring = { overrides = { C_DateAndTime = {
          GetSecondsUntilWeeklyReset = function() error("boom") end } } },
        ["nil"] = { overrides = resetIn(nil) },
        string = { overrides = resetIn("3600") },
        NaN = { overrides = resetIn(0 / 0) },
        ["-1"] = { overrides = resetIn(-1) },
        ["604861"] = { overrides = resetIn(604861) },
        infinite = { overrides = resetIn(math.huge) },
        hidden = { overrides = {
          C_DateAndTime = { GetSecondsUntilWeeklyReset = function() return hiddenSecs end },
          issecretvalue = function(v) return rawequal(v, hiddenSecs) end,
        } },
        ["hidden, valid-looking"] = { overrides = {
          C_DateAndTime = { GetSecondsUntilWeeklyReset = function() return 3600 end },
          issecretvalue = function(v) return v == 3600 end,
        } },
      }
      for name, case in pairs(cases) do
        assert.equal(US_RESET, anchorWith(case.overrides, case.setup), name)
        wow.uninstall()
      end
    end)

    it("falls back when the server time isn't an integer in range", function()
      for _, now in ipairs({ NOW + 0.5, -1, T_MAX + 1 }) do
        assert.equal(US_RESET, anchorWith(nil, function() wow.now = now end))
        wow.uninstall()
      end
      assert.equal(US_RESET, anchorWith({ GetServerTime = function() error("boom") end }))
      wow.uninstall()
      assert.equal(US_RESET, anchorWith({ issecretvalue = function(v) return v == NOW end }))
    end)

    it("uses the region's row, and the US row for region 1 or an unknown region", function()
      local third = US_RESET + 3600
      local function withRow(ns) ns.Core.RESET_FALLBACK[3] = third end
      local noApi = function(ns)
        _G.C_DateAndTime = nil
        withRow(ns)
      end
      -- AceDB reads the region when it initializes, so the region is set at login.
      local function inRegion(fn, more)
        local atLogin = { GetCurrentRegion = fn }
        for name, value in pairs(more or {}) do
          atLogin[name] = value
        end
        local anchor = anchorWith(nil, noApi, atLogin)
        wow.uninstall()
        return anchor
      end
      assert.equal(US_RESET, inRegion(function() return 1 end))
      assert.equal(third, inRegion(function() return 3 end))
      for _, region in ipairs({ 2, 99, 0 / 0, "3", false }) do
        assert.equal(US_RESET, inRegion(function() return region end))
      end
      local hiddenRegion = secret()
      assert.equal(US_RESET, inRegion(function() return hiddenRegion end,
        { issecretvalue = function(v) return rawequal(v, hiddenRegion) end }))
      assert.equal(US_RESET, inRegion(function() return 3 end,
        { issecretvalue = function(v) return v == 3 end }))
      assert.equal(US_RESET, inRegion(function() error("boom") end))
    end)
  end)

  describe("damaged saved data", function()
    it("opens a read-only empty ledger when ledgers is a string, leaving it untouched", function()
      local starts = { n = 0 }
      local ns = login({ db = { global = { ledgers = "junk" } },
        setup = function(ns) countStarts(ns, starts) end })
      assert.same({}, wow.errors)
      assert.is_true(ns.ledger.readOnly)
      assert.equal("not_table", ns.ledger.loadReport.reason)
      assert.equal("junk", saved())
      assert.same({ own = 0, foreign = 0, travelers = 0 }, ns.ledger:counts())
      assert.equal(1, starts.n)
    end)

    it("opens read-only when ledgers[guid] is a string, leaving it untouched", function()
      local ns = login({ db = { global = { ledgers = { [GUID] = "junk" } } } })
      assert.is_true(ns.ledger.readOnly)
      assert.equal("junk", saved()[GUID])
    end)

    it("leaves other characters' ledgers alone", function()
      local other = { schema = 1, me = {}, own = {}, travelers = {}, earned = {},
        quarantine = {} }
      local ns = login({ db = { global = { ledgers = { ["Player-1-00000002"] = other } } } })
      assert.is_false(ns.ledger.readOnly)
      assert.equal(other, saved()["Player-1-00000002"])
      assert.is_table(saved()[GUID])
    end)

    it("catches Ledger.new raising (a bad server time): no ledger, no error", function()
      local starts = { n = 0 }
      local ns = login({
        overrides = resetIn(604800),
        setup = function(ns)
          countStarts(ns, starts)
          wow.now = T_MAX -- the anchor lands a week past tMax
        end,
      })
      assert.same({}, wow.errors)
      assert.is_nil(ns.ledger)
      assert.equal("open failed", ns.Core.ledgerState)
      assert.equal(1, starts.n)
      wow.slash("/ledger debug")
      assert.is_true(chatHas("ledger: open failed"))
    end)

    it("opens a read-only empty ledger when global isn't a table, leaving it untouched", function()
      for _, bad in ipairs({ "junk", 7 }) do
        local ns = login({ db = { global = bad } })
        assert.same({}, wow.errors)
        assert.is_true(ns.ledger.readOnly)
        assert.equal(bad, _G.InnkeepersLedgerDB.global)
        wow.uninstall()
      end
    end)

    it("catches an error while working out the anchor", function()
      local ns = login({ setup = function(ns)
        ns.Core.RESET_FALLBACK = setmetatable({}, { __index = function() error("boom") end })
        _G.C_DateAndTime = nil
      end })
      assert.same({}, wow.errors)
      assert.is_nil(ns.ledger)
      assert.equal("open failed", ns.Core.ledgerState)
    end)

    it("catches any error from Ledger.new", function()
      local ns = login({ setup = function(ns)
        ns.Ledger.new = function() error("boom") end
      end })
      assert.same({}, wow.errors)
      assert.is_nil(ns.ledger)
    end)
  end)
end)

describe("the debug log", function()
  local ns

  before_each(function()
    ns = login()
    wow.chat = {}
  end)

  after_each(wow.uninstall)

  it("is off by default and prints nothing while off", function()
    ns.Core:Debug("sync: test")
    assert.same({}, wow.chat)
  end)

  it("toggles with /ledger debug, printing the report line when it turns on", function()
    wow.slash("/ledger debug")
    assert.equal(2, #wow.chat)
    assert.truthy(wow.chat[1]:find("Debug log on.", 1, true))
    assert.truthy(wow.chat[2]:find("ledger: open; sync: received 0, dropped 0, added 0, dup 0, "
      .. "rejected 0, evicted 0, sent 0, sendFailed 0, errors 0", 1, true), wow.chat[2])
    ns.Core:Debug("sync: test")
    assert.equal(3, #wow.chat)
    assert.truthy(wow.chat[3]:find("sync: test", 1, true))

    wow.slash("/ledger  DEBUG ")
    assert.equal(4, #wow.chat)
    assert.truthy(wow.chat[4]:find("Debug log off.", 1, true))
    ns.Core:Debug("sync: test")
    assert.equal(4, #wow.chat)
  end)

  it("reports the non-zero load counts and the sync totals", function()
    wow.uninstall()
    ns = login({ db = { global = { ledgers = { [GUID] = {
      schema = 1, me = {}, own = { { inn = "x" }, { inn = 1, t = 1 } }, travelers = {},
      earned = { [0] = 1 }, quarantine = {},
    } } } } })
    ns.Sync.stats = {
      received = { hello = 2, want = 1, entries = 4 },
      dropped = { self = 1, bad_prefix = 2 },
      added = 3,
      dup = 0,
      sent = { hello = 1 },
      errors = 0,
      bogus = 7,
    }
    wow.chat = {}
    wow.slash("/ledger debug")
    assert.truthy(wow.chat[2]:find(
      "ledger: open, earnedDropped 1, quarantined 2; sync: received 7, dropped 3, added 3, "
        .. "dup 0, sent 1, errors 0", 1, true), wow.chat[2])
  end)

  it("says so when Sync has no stats", function()
    ns.Sync.stats = nil
    wow.slash("/ledger debug")
    assert.truthy(wow.chat[2]:find("ledger: open; sync: no stats; names realm", 1, true),
      wow.chat[2])
  end)

  it("ends the report with the client's name form", function()
    local hiddenSlot = secret()
    local cases = {
      { "realm", {} },
      { "two-part", { overrides = wow.foreverNames("Traveler", "Wayfarer") } },
      { "undecided", { overrides = wow.foreverNames("Traveler", "Wayfarer"), atLogin = {
        GetNormalizedRealmName = function() return nil end } } },
      { "undecided", { overrides = wow.foreverNames("Traveler", "Wayfarer"), atLogin = {
        UnitFullName = function() return "Traveler", hiddenSlot end,
        issecretvalue = function(v) return rawequal(v, hiddenSlot) end } } },
      -- Read-only: Sync never starts, so nothing decided it.
      { "undecided", { db = { global = { ledgers = { [GUID] = { schema = 99 } } } } } },
    }
    for i, case in ipairs(cases) do
      wow.uninstall()
      ns = login(case[2])
      wow.chat = {}
      wow.slash("/ledger debug")
      assert.same({}, wow.errors, i)
      local suffix = "; names " .. case[1]
      assert.equal(suffix, wow.chat[2]:sub(-#suffix), i .. ": " .. wow.chat[2])
    end
  end)

  it("says names undecided when Sync has no client or NameForm fails", function()
    ns.Sync.client = nil
    wow.slash("/ledger debug")
    assert.truthy(wow.chat[2]:find("; names undecided$"), wow.chat[2])
    wow.slash("/ledger debug")
    ns.Sync.NameForm = function() error("boom") end
    wow.chat = {}
    wow.slash("/ledger debug")
    assert.truthy(wow.chat[2]:find("; names undecided$"), wow.chat[2])
  end)

  it("reports a read-only ledger with its reason", function()
    wow.uninstall()
    ns = login({ db = { global = { ledgers = { [GUID] = { schema = 99 } } } } })
    wow.chat = {}
    wow.slash("/ledger debug")
    assert.truthy(wow.chat[2]:find("ledger: read-only (newer_schema)", 1, true), wow.chat[2])
  end)

  it("reports a ledger that isn't open yet", function()
    wow.uninstall()
    ns = login({ overrides = { UnitGUID = function() return nil end } })
    wow.chat = {}
    wow.slash("/ledger debug")
    assert.truthy(wow.chat[2]:find("ledger: not open yet", 1, true), wow.chat[2])
  end)

  it("prints at most 5 lines per 10 s and counts the rest", function()
    wow.slash("/ledger debug")
    wow.chat = {}
    for i = 1, 20 do
      ns.Core:Debug("sync: line " .. i)
    end
    assert.equal(5, #wow.chat)
    assert.truthy(wow.chat[5]:find("sync: line 5", 1, true))
    wow.advance(9)
    ns.Core:Debug("sync: still limited")
    assert.equal(5, #wow.chat)
    wow.advance(1)
    ns.Core:Debug("sync: next")
    assert.equal(6, #wow.chat)
    assert.truthy(wow.chat[6]:find("(16 skipped) sync: next", 1, true), wow.chat[6])
    ns.Core:Debug("sync: after")
    assert.truthy(wow.chat[7]:find(": sync: after", 1, true), wow.chat[7])
  end)

  it("says (15 skipped) on the next line after 20 lines in one second", function()
    wow.slash("/ledger debug")
    wow.chat = {}
    for i = 1, 20 do
      ns.Core:Debug("sync: line " .. i)
    end
    wow.advance(10)
    ns.Core:Debug("sync: next")
    assert.equal(6, #wow.chat)
    assert.truthy(wow.chat[6]:find("(15 skipped) sync: next", 1, true), wow.chat[6])
  end)

  it("starts a fresh count each time it's turned on", function()
    wow.slash("/ledger debug")
    for _ = 1, 8 do
      ns.Core:Debug("sync: x")
    end
    wow.slash("/ledger debug")
    wow.slash("/ledger debug")
    wow.chat = {}
    ns.Core:Debug("sync: fresh")
    assert.equal(1, #wow.chat)
    assert.falsy(wow.chat[1]:find("skipped", 1, true))
  end)

  it("keeps printing when the clock steps back", function()
    wow.slash("/ledger debug")
    for _ = 1, 5 do
      ns.Core:Debug("sync: x")
    end
    wow.now = NOW - 3600
    wow.chat = {}
    ns.Core:Debug("sync: after the jump")
    assert.equal(1, #wow.chat)
  end)

  it("still limits lines when the clock isn't a number", function()
    for _, clock in ipairs({ 0 / 0, "x" }) do
      wow.uninstall()
      ns = login({ atLogin = { GetServerTime = function() return clock end } })
      wow.slash("/ledger debug")
      wow.chat = {}
      for _ = 1, 20 do
        ns.Core:Debug("sync: x")
      end
      assert.equal(5, #wow.chat)
    end
  end)

  it("ignores a line that isn't a string", function()
    wow.slash("/ledger debug")
    wow.chat = {}
    ns.Core:Debug(nil)
    ns.Core:Debug(42)
    assert.same({}, wow.chat)
  end)

  it("answers /ledger version with the version; /ledger opens the book instead", function()
    wow.slash("/ledger version")
    assert.equal(1, #wow.chat)
    assert.truthy(wow.chat[1]:find("version dev", 1, true))
    wow.slash("/ledger")
    wow.slash("/ledger something")
    assert.equal(1, #wow.chat)
    assert.is_table(ns.Book.ui)
  end)

  it("routes /ledger, /ledger share and any other word to the book", function()
    local calls = {}
    ns.Book.Toggle = function(self) calls[#calls + 1] = { "Toggle", self } end
    ns.Book.Open = function(self, tab) calls[#calls + 1] = { "Open", self, tab } end
    wow.slash("/ledger")
    wow.slash("/ledger  SHARE ")
    wow.slash("/ledger foo bar")
    assert.same({ { "Toggle", ns.Book }, { "Open", ns.Book, "share" }, { "Toggle", ns.Book } },
      calls)
    assert.same({}, wow.chat)
  end)

  it("logs one line when the book raises, and nothing escapes", function()
    ns.Book.Toggle = function() error("raised on purpose") end
    ns.Book.Open = function() error("raised on purpose") end
    wow.slash("/ledger debug")
    wow.chat = {}
    wow.slash("/ledger")
    wow.slash("/ledger share")
    assert.equal(2, #wow.chat)
    assert.truthy(wow.chat[1]:find("book: error in slash", 1, true))
    assert.truthy(wow.chat[2]:find("book: error in slash", 1, true))
    ns.Book = nil
    wow.slash("/ledger")
    assert.same({}, wow.errors)
  end)
end)

describe("Core:PlayerName", function()
  after_each(wow.uninstall)

  it("is the owner's display name", function()
    local ns = login()
    assert.equal("Traveler", ns.Core:PlayerName())
  end)

  it("is the two-part name on Forever", function()
    local ns = login({ overrides = wow.foreverNames("Mira", "Ashvale") })
    assert.equal("Mira Ashvale", ns.Core:PlayerName())
  end)

  it("is nil when the name is hidden, missing, invalid or the read raises", function()
    local ns = login()
    local hiddenName = secret()
    _G.UnitFullName = function() return hiddenName end
    _G.UnitName = function() return hiddenName end
    _G.issecretvalue = function(v) return rawequal(v, hiddenName) end
    assert.is_nil(ns.Core:PlayerName())
    _G.issecretvalue = function() return false end
    _G.UnitFullName = function() return nil end
    _G.UnitName = function() return nil end
    assert.is_nil(ns.Core:PlayerName())
    _G.UnitFullName = function() return "x|cff" end
    assert.is_nil(ns.Core:PlayerName())
    ns.Sync.readOwnName = function() error("raised on purpose") end
    assert.is_nil(ns.Core:PlayerName())
  end)
end)

-- docs/specs/export.md 3.7 and 6.7: Core:ExportString, decoded with the libraries the loaded
-- AddOn registered, through the test-only decoder.
describe("Core:ExportString", function()
  local dec = require("helpers.export_decode")
  local TRAVELER = "Player-1-00000002"
  local OWN = {
    { inn = 1234, t = NOW - 600, phrase = { 1, 2 } },
    { inn = 5678, t = NOW - 60, phrase = { 3 }, seal = 1 },
  }

  -- Logs in with two own entries and one traveler; returns ns.
  local function withLedger(opts)
    local ns = login(opts)
    for _, e in ipairs(OWN) do
      assert.equal("added", ns.ledger:addOwn(e))
    end
    assert.equal("added", ns.ledger:addForeign(TRAVELER, "Mira",
      { inn = 1234, t = NOW - 300, phrase = { 4 } }, NOW - 200))
    return ns
  end

  local function decode(s)
    local LibStub = _G.LibStub
    local data, reason = dec.decode(s, {
      serializer = LibStub("AceSerializer-3.0"), deflate = LibStub("LibDeflate"),
    })
    assert(data, "decode failed: " .. tostring(reason))
    assert(dec.schemaOk(data))
    return data
  end

  after_each(wow.uninstall)

  it("exports the ledger: own entries, the owner, no travelers", function()
    local ns = withLedger()
    local s, reason = ns.Core:ExportString()
    assert.is_string(s, reason)
    local data = decode(s)
    assert.equal(GUID, data.me.guid)
    assert.equal("Traveler", data.me.name)
    assert.equal("forever", data.flavor)
    assert.equal("dev", data.addon)
    assert.equal(wow.now, data.exported)
    assert.same(ns.ledger:own(), data.entries)
    assert.same(OWN, data.entries)
    assert.equal("Alliance", data.collection.faction)
    assert.is_nil(data.travelers)
  end)

  it("reports the packaged version", function()
    local ns = withLedger()
    wow.metadata.Version = "1.2.3"
    assert.equal("1.2.3", decode(ns.Core:ExportString()).addon)
  end)

  it("includes travelers only for exactly true", function()
    local ns = withLedger()
    local data = decode(ns.Core:ExportString(true))
    assert.equal(1, #data.travelers)
    assert.equal(TRAVELER, data.travelers[1].guid)
    assert.equal("Mira", data.travelers[1].name)
    assert.equal(NOW - 200, data.travelers[1].met)
    assert.same({ { inn = 1234, t = NOW - 300, phrase = { 4 } } }, data.travelers[1].entries)
    for _, v in ipairs({ "yes", 1, {}, false }) do
      assert.is_nil(decode(ns.Core:ExportString(v)).travelers)
    end
  end)

  it("leaves faction out when UnitFactionGroup raises, is hidden or isn't a string", function()
    local hiddenFaction = secret()
    local cases = {
      { UnitFactionGroup = function() error("boom") end },
      { UnitFactionGroup = function() return hiddenFaction end,
        issecretvalue = function(v) return rawequal(v, hiddenFaction) end },
      { issecretvalue = function(v) return v == "Alliance" end },
      { UnitFactionGroup = function() return 7 end },
      { UnitFactionGroup = "junk" },
    }
    for _, case in ipairs(cases) do
      local ns = withLedger()
      for name, value in pairs(case) do
        _G[name] = value
      end
      local data = decode(ns.Core:ExportString())
      assert.is_nil(data.collection.faction)
      assert.same(OWN, data.entries)
      wow.uninstall()
    end
  end)

  it("refuses with exported when the clock is hidden or unreadable", function()
    local hiddenNow = secret()
    local cases = {
      { issecretvalue = function(v) return v == NOW end },
      { GetServerTime = function() return hiddenNow end,
        issecretvalue = function(v) return rawequal(v, hiddenNow) end },
      { GetServerTime = function() error("boom") end },
      { GetServerTime = function() return NOW + 0.5 end },
    }
    for _, case in ipairs(cases) do
      local ns = withLedger()
      for name, value in pairs(case) do
        _G[name] = value
      end
      assert.same({ nil, "exported" }, { ns.Core:ExportString() })
      wow.uninstall()
    end
  end)

  it("keeps a planted traveler out of its own default export (walks every string)", function()
    local PLANTED, NAME = "Player-1-00000009", "Planted"
    local ns = login({ db = { global = { ledgers = { [GUID] = {
      schema = 1,
      me = { name = "Traveler" },
      own = { deepcopy(OWN[1]),
        { inn = 1, t = NOW - 30, phrase = { 1 }, signer = PLANTED, name = NAME } },
      travelers = { [PLANTED] = { name = NAME, met = NOW - 100,
        entries = { { inn = 1234, t = NOW - 300, phrase = { 4 } } } } },
      earned = { [PLANTED] = NOW, [1] = NOW - 600 },
      quarantine = { { signer = PLANTED, name = NAME } },
    } } } } })
    local function strings(v, out)
      if type(v) == "string" then
        out[#out + 1] = v
      elseif type(v) == "table" then
        for k, x in pairs(v) do
          strings(k, out)
          strings(x, out)
        end
      end
      return out
    end
    for _, str in ipairs({ ns.Core:ExportString(false), ns.Core:ExportString() }) do
      local data = decode(str)
      assert.is_nil(data.travelers)
      for _, s in ipairs(strings(data, {})) do
        assert.is_nil(s:find(PLANTED, 1, true), s)
        assert.is_nil(s:find(NAME, 1, true), s)
      end
    end
    -- The plant is real: opting in exports it.
    local found = {}
    for _, s in ipairs(strings(decode(ns.Core:ExportString(true)), {})) do
      found[s] = true
    end
    assert.is_true(found[PLANTED] and found[NAME])
  end)

  it("exports a read-only ledger (a newer schema) with its entries", function()
    local ns = login({ db = { global = { ledgers = { [GUID] = {
      schema = 99, me = {}, own = deepcopy(OWN), travelers = {}, earned = {}, quarantine = {},
    } } } } })
    assert.is_true(ns.ledger.readOnly)
    assert.same(OWN, decode(ns.Core:ExportString()).entries)
  end)

  it("gives no_ledger when the GUID was never readable", function()
    local ns = login({ overrides = { UnitGUID = function() return nil end } })
    wow.advance(10)
    assert.is_nil(ns.ledger)
    assert.same({ nil, "no_ledger" }, { ns.Core:ExportString() })
  end)

  it("gives libs when AceSerializer or LibDeflate is missing", function()
    for _, name in ipairs({ "AceSerializer-3.0", "LibDeflate" }) do
      local ns = withLedger()
      _G.LibStub.libs[name] = nil
      assert.same({ nil, "libs" }, { ns.Core:ExportString() })
      wow.uninstall()
    end
  end)

  it("gives error when something inside raises", function()
    local ns = withLedger()
    ns.Collection.progress = function() error("boom") end
    assert.same({ nil, "error" }, { ns.Core:ExportString() })
  end)

  it("prints, sends and writes nothing", function()
    local ns = withLedger()
    wow.advance(30)
    local chat, sent = #wow.chat, #wow.sent
    local before = deepcopy(_G.InnkeepersLedgerDB)
    assert.is_string(ns.Core:ExportString(true))
    assert.is_string(ns.Core:ExportString())
    assert.is_string(ns.Core:ExportString("yes"))
    assert.equal(chat, #wow.chat)
    assert.equal(sent, #wow.sent)
    assert.same({}, wow.errors)
    assert.same(before, _G.InnkeepersLedgerDB)
  end)
end)
