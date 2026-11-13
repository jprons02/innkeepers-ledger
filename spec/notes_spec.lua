-- Notes (glue): noting an unknown innkeeper at GOSSIP_SHOW, known innkeepers and other NPCs
-- left alone, unreadable client values, the saved record (damaged, newer, broken, full),
-- never sending or picking an option, the login prune and errors kept away from Sign
-- (docs/specs/inn-notes.md 6.3). The whole AddOn runs under the WoW stub.
local load = require("helpers.load")
local wow = require("helpers.wow_stub")

local GUID = "Player-1-00000001" -- the stub's UnitGUID("player")
local NOW = 1800000000           -- the stub's default server time
local ICON = 132052              -- the binder option's icon
local UNKNOWN = 3934             -- an innkeeper the shipped data doesn't know
local CALM = 254089              -- Coriella Calmbreeze, Calmbreeze Inn (the real data)
local FARLEY = 295               -- Innkeeper Farley, Lion's Pride Inn (the real data)

local function npcGUID(id)
  return "Creature-0-4615-2991-62-" .. id .. "-0000ABCDEF"
end

local VENDOR_GUID = npcGUID(251361)

-- A stand-in for a hidden ("secret") value: touching it in any way raises.
local function secret()
  local value = newproxy(true)
  local mt = getmetatable(value)
  local function touched() error("a hidden value was touched", 2) end
  for _, event in ipairs({ "__index", "__newindex", "__call", "__eq", "__lt", "__le",
    "__concat", "__len", "__tostring", "__unm", "__add" }) do
    mt[event] = touched
  end
  return value
end

-- issecretvalue that flags exactly these values.
local function flags(...)
  local hiddenValues = { ... }
  return function(v)
    for _, h in ipairs(hiddenValues) do
      if rawequal(v, h) then
        return true
      end
    end
    return false
  end
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

-- What UnitGUID answers this case: state.player for "player", state.npc for "npc".
local state

-- The innkeeper's options: a Trade option, then the binder option.
local function innOptions()
  return { { icon = 132060, name = "Let me browse your goods.", gossipOptionID = 1 },
    { icon = ICON, name = "Make this inn your home.", gossipOptionID = 96506 } }
end

-- Loads the AddOn and logs in, talking to an innkeeper the data doesn't know (Horde).
-- opts: overrides (stub names), db (the SavedVariables as saved), setup(ns) (after the
-- files load, before ADDON_LOADED), debug (the debug log on from the start).
local function login(opts)
  opts = opts or {}
  state = { player = GUID, npc = npcGUID(UNKNOWN) }
  local overrides = {
    UnitGUID = function(unit)
      if unit == "player" then
        return state.player
      elseif unit == "npc" then
        return state.npc
      end
    end,
  }
  for k, v in pairs(opts.overrides or {}) do
    overrides[k] = v
  end
  wow.install(overrides)
  wow.gossipOptions = innOptions()
  wow.npcFaction = "Horde"
  if opts.db ~= nil then
    _G.InnkeepersLedgerDB = opts.db
  end
  local ns = load.addon({})
  if opts.setup then
    opts.setup(ns)
  end
  wow.fire("ADDON_LOADED", load.ADDON_NAME)
  if opts.debug then
    ns.Core.debugOn, ns.Core.debugPrinted, ns.Core.debugSkipped = true, {}, 0
  end
  wow.fire("PLAYER_LOGIN")
  return ns
end

-- Turns the debug log on and clears the chat (its report lines included).
local function debugOn()
  wow.slash("/ledger debug")
  wow.chat = {}
end

local function lines(text)
  local n = 0
  for _, line in ipairs(wow.chat) do
    if line:find(text, 1, true) then
      n = n + 1
    end
  end
  return n
end

local function notesTable()
  local g = rawget(_G.InnkeepersLedgerDB, "global")
  return g and rawget(g, "notes")
end

local function record()
  local all = notesTable()
  return type(all) == "table" and all[GUID] or nil
end

local function theNote(extra)
  local n = { npc = UNKNOWN, t = NOW, zone = 1437, continent = 1415 }
  for k, v in pairs(extra or {}) do
    n[k] = v
  end
  return n
end

describe("Notes: an innkeeper the data doesn't know", function()
  after_each(function()
    assert.same({}, wow.errors)
    wow.uninstall()
  end)

  it("records one note at GOSSIP_SHOW, with one debug line", function()
    local ns = login()
    assert.is_table(ns.Notes.frame)
    assert.is_true(ns.Notes.frame:IsEventRegistered("GOSSIP_SHOW"))
    assert.is_nil(notesTable())
    debugOn()
    wow.fire("GOSSIP_SHOW")
    assert.same({ v = 1, items = { theNote({ faction = "Horde" }) } }, record())
    assert.equal(1, #wow.chat)
    assert.equal(1, lines("notes: noted 3934"))
    -- The same innkeeper again: still one note, no line.
    wow.advance(60)
    wow.fire("GOSSIP_SHOW")
    assert.same({ v = 1, items = { theNote({ faction = "Horde" }) } }, record())
    assert.equal(1, #wow.chat)
  end)

  it("prints nothing with the debug log off", function()
    login()
    wow.fire("GOSSIP_SHOW")
    assert.same({ v = 1, items = { theNote({ faction = "Horde" }) } }, record())
    assert.same({}, wow.chat)
  end)

  it("keeps notes of other characters and adds in (t, npc) order", function()
    local OTHER = "Player-1-00000002"
    local theirs = { v = 1, items = { theNote({ t = NOW - 5 }) } }
    login({ db = { global = { notes = { [OTHER] = deepcopy(theirs),
      [GUID] = { v = 1, items = { { npc = 4000, t = NOW + 5, zone = 1, continent = 2 } } } } } } })
    wow.fire("GOSSIP_SHOW")
    assert.same(theirs, notesTable()[OTHER])
    assert.same({ v = 1, items = { theNote({ faction = "Horde" }),
      { npc = 4000, t = NOW + 5, zone = 1, continent = 2 } } }, record())
  end)

  it("keeps no faction for a neutral innkeeper", function()
    login()
    wow.npcFaction = nil
    wow.fire("GOSSIP_SHOW")
    assert.same({ v = 1, items = { theNote() } }, record())
  end)

  it("finds the binder option wherever it is in the list", function()
    login()
    wow.gossipOptions = { { icon = ICON }, { icon = 132053 }, { icon = 132060 } }
    wow.fire("GOSSIP_SHOW")
    assert.equal(1, #record().items)
  end)
end)

describe("Notes: NPCs it leaves alone", function()
  after_each(function()
    assert.same({}, wow.errors)
    wow.uninstall()
  end)

  it("notes no known innkeeper (primary data) and never asks for its options", function()
    for _, id in ipairs({ CALM, FARLEY }) do
      local calls = 0
      local ns = login({ overrides = { C_GossipInfo = {
        GetOptions = function() calls = calls + 1 return innOptions() end,
      } } })
      state.npc = npcGUID(id)
      debugOn()
      wow.fire("GOSSIP_SHOW")
      assert.is_nil(notesTable())
      assert.equal(0, calls)
      assert.equal(0, lines("notes:"))
      -- Sign's buttons show there as before.
      assert.is_true(ns.Sign.ui.button:IsShown())
      wow.uninstall()
    end
  end)

  it("notes no vendor or quest giver, and says nothing", function()
    login()
    state.npc = VENDOR_GUID
    wow.gossipOptions = { { icon = 132060 }, { icon = 132049 } }
    debugOn()
    wow.fire("GOSSIP_SHOW")
    assert.is_nil(notesTable())
    assert.same({}, wow.chat)
  end)

  it("notes no player, game object or pet", function()
    login()
    debugOn()
    for _, g in ipairs({ "Player-1-00000002", "GameObject-0-4615-2991-62-3934-0000ABCDEF",
      "Pet-0-4615-2991-62-3934-0000ABCDEF" }) do
      state.npc = g
      wow.fire("GOSSIP_SHOW")
    end
    assert.is_nil(notesTable())
    assert.same({}, wow.chat)
  end)

  it("does nothing without an open ledger", function()
    local ns = login({ overrides = { UnitGUID = function() return nil end } })
    assert.is_nil(ns.ledger)
    wow.fire("GOSSIP_SHOW")
    assert.is_nil(notesTable())
  end)
end)

describe("Notes: unreadable client values", function()
  after_each(wow.uninstall)

  -- Each case: setup() after login, then GOSSIP_SHOW; want: the record (nil: none), and
  -- the one debug line it gives, if any.
  local function run(setup, want, line)
    local ns = login()
    debugOn()
    setup(ns)
    wow.fire("GOSSIP_SHOW")
    assert.same(want, record())
    assert.same({}, wow.errors)
    assert.equal(0, lines("notes: error"))
    if line then
      assert.equal(1, lines(line))
    end
    wow.uninstall()
  end

  local NO_FACTION = { v = 1, items = { theNote() } }

  it("notes nothing for a hidden NPC GUID", function()
    local s = secret()
    run(function()
      state.npc = s
      _G.issecretvalue = flags(s)
    end, nil)
    -- A valid-looking GUID that issecretvalue flags is hidden too.
    run(function() _G.issecretvalue = flags(npcGUID(UNKNOWN)) end, nil)
  end)

  it("notes nothing for a hidden, raising or missing option list", function()
    local s = secret()
    run(function()
      wow.gossipOptions = s
      _G.issecretvalue = flags(s)
    end, nil)
    run(function() _G.C_GossipInfo.GetOptions = function() error("boom") end end, nil)
    run(function() _G.C_GossipInfo = nil end, nil)
    run(function() _G.C_GossipInfo = { GetOptions = "x" } end, nil)
    run(function() wow.gossipOptions = "x" end, nil)
  end)

  it("skips a hidden option or icon, reading the rest", function()
    local s, i = secret(), secret()
    run(function()
      wow.gossipOptions = { s, { icon = ICON } }
      _G.issecretvalue = flags(s)
    end, { v = 1, items = { theNote({ faction = "Horde" }) } })
    run(function()
      wow.gossipOptions = { { icon = 132060 }, s }
      _G.issecretvalue = flags(s)
    end, nil)
    run(function()
      wow.gossipOptions = { { icon = i } }
      _G.issecretvalue = flags(i)
    end, nil)
    -- A hidden icon that is the binder icon's number is still hidden.
    run(function() _G.issecretvalue = flags(ICON) end, nil)
    -- An option that raises when read is skipped with the rest of the list.
    run(function()
      wow.gossipOptions = setmetatable({}, { __index = function() error("boom") end })
    end, nil)
    -- An icon of another type is not the binder icon.
    run(function() wow.gossipOptions = { { icon = "132052" } } end, nil)
  end)

  it("notes nothing where the map doesn't read: a dungeon, a hidden or raising map", function()
    run(function() wow.bestMap = nil end, nil, "notes: place")
    local s = secret()
    run(function()
      wow.bestMap = s
      _G.issecretvalue = flags(s)
    end, nil, "notes: place")
    run(function()
      wow.maps[1415].mapType = s
      _G.issecretvalue = flags(s)
    end, nil, "notes: place")
    run(function()
      wow.maps[1437] = s
      _G.issecretvalue = flags(s)
    end, nil, "notes: place")
    run(function() _G.C_Map.GetMapInfo = function() error("boom") end end, nil, "notes: place")
    run(function()
      wow.maps[1437] = setmetatable({}, { __index = function() error("boom") end })
    end, nil, "notes: place")
    run(function() _G.C_Map = nil end, nil, "notes: place")
    run(function() wow.maps[1415] = nil end, nil, "notes: place")
  end)

  it("keeps the note without faction when the NPC's faction is hidden or raises", function()
    local s = secret()
    run(function()
      wow.npcFaction = s
      _G.issecretvalue = flags(s)
    end, NO_FACTION)
    run(function() _G.UnitFactionGroup = function() error("boom") end end, NO_FACTION)
    run(function() wow.npcFaction = 7 end, NO_FACTION)
    run(function() wow.npcFaction = "Neutral" end, NO_FACTION)
  end)

  it("notes nothing for a hidden or unreadable clock", function()
    local s = secret()
    run(function()
      wow.now = s
      _G.issecretvalue = flags(s)
    end, nil, "notes: clock")
    run(function() _G.GetServerTime = function() error("boom") end end, nil, "notes: clock")
  end)
end)

describe("Notes: the saved record", function()
  after_each(function()
    assert.same({}, wow.errors)
    wow.uninstall()
  end)

  it("never overwrites a damaged notes table or record", function()
    for _, global in ipairs({ { notes = "x" }, { notes = { [GUID] = 7 } } }) do
      local before = deepcopy(global)
      login({ db = { global = global } })
      debugOn()
      wow.fire("GOSSIP_SHOW")
      assert.same(before.notes, notesTable())
      assert.equal(1, lines("notes: read-only"))
      wow.uninstall()
    end
  end)

  it("logs nothing about a read-only record at an NPC that isn't an innkeeper", function()
    for _, global in ipairs({ { notes = "x" }, { notes = { [GUID] = { v = 2, items = {} } } } }) do
      login({ db = { global = global } })
      state.npc = VENDOR_GUID
      wow.gossipOptions = {
        { icon = 132060, name = "Let me browse your goods.", gossipOptionID = 1 },
      }
      debugOn()
      wow.fire("GOSSIP_SHOW")
      assert.equal(0, lines("notes:"))
      wow.uninstall()
    end
  end)

  it("never touches a newer record (v = 2)", function()
    local newer = { v = 2, items = { theNote({ t = NOW - 5 }) }, extra = { 1 } }
    login({ db = { global = { notes = { [GUID] = deepcopy(newer) } } } })
    debugOn()
    wow.fire("GOSSIP_SHOW")
    assert.same(newer, record())
    assert.equal(1, lines("notes: read-only"))
  end)

  it("replaces a broken v1 record (v missing) with a valid one", function()
    login({ db = { global = { notes = { [GUID] = { items = { theNote({ npc = 4000 }) } } } } } })
    wow.fire("GOSSIP_SHOW")
    assert.same({ v = 1, items = { theNote({ faction = "Horde" }) } }, record())
  end)

  it("drops a new note at 200: notes: full, nothing written", function()
    local items = {}
    for i = 1, 200 do
      items[i] = { npc = 100000 + i, t = NOW - 1000 + i, zone = 1, continent = 2 }
    end
    local full = { v = 1, items = items }
    login({ db = { global = { notes = { [GUID] = deepcopy(full) } } } })
    local saved = record()
    debugOn()
    wow.fire("GOSSIP_SHOW")
    assert.is_true(rawequal(saved, record()))
    assert.same(full, record())
    assert.equal(1, lines("notes: full"))
  end)

  it("writes nothing when global isn't a table", function()
    login({ db = { global = "x" } })
    wow.fire("GOSSIP_SHOW")
    assert.equal("x", _G.InnkeepersLedgerDB.global)
  end)
end)

describe("Notes: never sends, never picks", function()
  after_each(function()
    assert.same({}, wow.errors)
    wow.uninstall()
  end)

  it("sends no addon message and calls no gossip action when noting", function()
    login()
    wow.advance(120)
    local sent = #wow.sent
    wow.fire("GOSSIP_SHOW")
    wow.fire("GOSSIP_SHOW")
    assert.equal(1, #record().items)
    assert.equal(sent, #wow.sent)
    assert.same({}, wow.gossipSelected)
  end)
end)

describe("Notes: the login prune", function()
  after_each(wow.uninstall)

  local function saved(items, v)
    return { global = { notes = { [GUID] = { v = v or 1, items = items } } } }
  end

  it("drops notes for innkeepers the data now knows", function()
    login({ db = saved({ theNote(), theNote({ npc = FARLEY, t = NOW + 1 }),
      theNote({ npc = CALM, t = NOW + 2 }) }) })
    assert.same({ v = 1, items = { theNote() } }, record())
    assert.same({}, wow.errors)
  end)

  it("doesn't rewrite a record with nothing to drop", function()
    local db = saved({ theNote() })
    local rec = db.global.notes[GUID]
    login({ db = db })
    assert.is_true(rawequal(rec, record()))
    assert.same({ v = 1, items = { theNote() } }, record())
  end)

  it("leaves a damaged or newer record alone", function()
    for _, rec in ipairs({ "x", { v = 2, items = { theNote({ npc = FARLEY }) } } }) do
      local before = deepcopy(rec)
      login({ db = { global = { notes = { [GUID] = rec } } } })
      assert.same(before, record())
      wow.uninstall()
    end
  end)

  it("prunes a read-only ledger's notes record too", function()
    local db = saved({ theNote(), theNote({ npc = FARLEY, t = NOW + 1 }) })
    db.global.ledgers = { [GUID] = { schema = 99, me = {}, own = {}, travelers = {},
      earned = {}, quarantine = {} } }
    local ns = login({ db = db })
    assert.is_true(ns.ledger.readOnly)
    assert.same({ v = 1, items = { theNote() } }, record())
  end)

  it("still opens the ledger and starts Sync when Prune raises", function()
    local starts = 0
    local ns = login({ debug = true, setup = function(ns)
      ns.Notes.Prune = function() error("raised on purpose") end
      local start = ns.Sync.Start
      ns.Sync.Start = function(self)
        starts = starts + 1
        return start(self)
      end
    end })
    assert.is_table(ns.ledger)
    assert.equal(1, starts)
    assert.equal(1, lines("notes: error in prune"))
    assert.same({}, wow.errors)
  end)

  it("catches an error inside the prune with its own debug line", function()
    local ns = login({ debug = true, db = saved({ theNote() }), setup = function(ns)
      ns.InnNotes.read = function() error("raised on purpose") end
    end })
    assert.is_table(ns.ledger)
    assert.equal(1, lines("notes: error in prune"))
    assert.same({}, wow.errors)
  end)
end)

describe("Notes: errors stay in Notes", function()
  after_each(function()
    assert.same({}, wow.errors)
    wow.uninstall()
  end)

  it("logs notes: error in gossip when observe raises; Sign still works", function()
    local ns = login()
    ns.InnNotes.observe = function() error("raised on purpose") end
    debugOn()
    wow.fire("GOSSIP_SHOW")
    assert.is_nil(notesTable())
    assert.equal(1, lines("notes: error in gossip"))
    -- Next, at a known innkeeper, in the same run: Sign's buttons show.
    state.npc = npcGUID(CALM)
    wow.fire("GOSSIP_SHOW")
    assert.is_true(ns.Sign.ui.button:IsShown())
    assert.is_true(ns.Sign.ui.read:IsShown())
  end)

  it("keeps Sign's buttons when Notes fails in the same GOSSIP_SHOW", function()
    local ns = login()
    state.npc = npcGUID(CALM)
    ns.Ledger.npcFromGUID = function() error("raised on purpose") end
    debugOn()
    wow.fire("GOSSIP_SHOW")
    assert.equal(1, lines("notes: error in gossip"))
    assert.is_true(ns.Sign.ui.button:IsShown())
  end)

  it("never prints the error's text", function()
    local ns = login()
    ns.InnNotes.observe = function() error("SECRET TEXT") end
    debugOn()
    wow.fire("GOSSIP_SHOW")
    assert.equal(0, lines("SECRET TEXT"))
  end)
end)

describe("Notes:List", function()
  after_each(function()
    assert.same({}, wow.errors)
    wow.uninstall()
  end)

  it("lists the owner's notes as copies and never writes", function()
    local ns = login({ db = { global = { notes = { [GUID] = { v = 1,
      items = { theNote({ t = NOW + 1 }), { npc = 4000, t = NOW, zone = 1, continent = 2 } } },
      ["Player-1-00000002"] = { v = 1, items = { theNote({ npc = 5000 }) } } } } } })
    local before = deepcopy(_G.InnkeepersLedgerDB)
    local list = ns.Notes:List()
    assert.same({ { npc = 4000, t = NOW, zone = 1, continent = 2 }, theNote({ t = NOW + 1 }) },
      list)
    assert.is_false(rawequal(list[1], record().items[2]))
    assert.same(before, _G.InnkeepersLedgerDB)
  end)

  it("is {} with no ledger, no notes, a damaged or newer record", function()
    local ns = login({ overrides = { UnitGUID = function() return nil end } })
    assert.same({}, ns.Notes:List())
    wow.uninstall()
    for _, global in ipairs({ {}, { notes = "x" }, { notes = { [GUID] = 7 } },
      { notes = { [GUID] = { v = 2, items = { theNote() } } } } }) do
      ns = login({ db = { global = global } })
      assert.same({}, ns.Notes:List())
      wow.uninstall()
    end
  end)

  it("is {} when reading raises", function()
    local ns = login({ db = { global = {
      notes = { [GUID] = { v = 1, items = { theNote() } } } } } })
    ns.InnNotes.list = function() error("raised on purpose") end
    assert.same({}, ns.Notes:List())
  end)
end)
