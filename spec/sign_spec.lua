-- Sign (glue): the gossip button, a click's reasons, the composer end to end, the double
-- click, the gossip closing or the NPC changing mid-compose, errors, and Core recording
-- unlocks at login (docs/specs/sign.md 6.3). The whole AddOn runs under the WoW stub.
local load = require("helpers.load")
local wow = require("helpers.wow_stub")

local GUID = "Player-1-00000001" -- the stub's UnitGUID("player")
local NOW = 1800000000           -- the stub's default server time
local RESET = NOW + 259200       -- the stub's reset is three days away
local CALM = 254089              -- Coriella Calmbreeze, Calmbreeze Inn (the real data)

local function npcGUID(id)
  return "Creature-0-4615-2991-62-" .. id .. "-0000ABCDEF"
end

local CALM_GUID = npcGUID(CALM)
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

-- Loads the AddOn and logs in: resting, talking to Coriella Calmbreeze. opts: overrides
-- (stub names), db (the SavedVariables as saved), setup(ns) (after the files load, before
-- ADDON_LOADED).
local function login(opts)
  opts = opts or {}
  state = { player = GUID, npc = CALM_GUID }
  local overrides = {
    IsResting = function() return true end,
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
  if opts.db ~= nil then
    _G.InnkeepersLedgerDB = opts.db
  end
  local ns = load.addon({})
  if opts.setup then
    opts.setup(ns)
  end
  wow.fire("ADDON_LOADED", load.ADDON_NAME)
  wow.fire("PLAYER_LOGIN")
  return ns
end

-- Counts ns.Sync:WindowChanged() calls.
local function spyWindow(ns)
  local calls = { n = 0 }
  ns.Sync.WindowChanged = function(self)
    assert.equal(ns.Sync, self)
    calls.n = calls.n + 1
  end
  return calls
end

local function saved()
  return _G.InnkeepersLedgerDB.global.ledgers[GUID]
end

local function chatSince(n)
  local out = {}
  for i = n + 1, #wow.chat do
    out[#out + 1] = wow.chat[i]
  end
  return out
end

local function has(line, text)
  return type(line) == "string" and line:find(text, 1, true) ~= nil
end

-- Buttons CreateFrame made under the gossip frame (the composer is a plain Frame).
local function gossipButtons()
  local n = 0
  for _, frame in ipairs(wow.children(_G.GossipFrame)) do
    if frame.template == "UIPanelButtonTemplate" then
      n = n + 1
    end
  end
  return n
end

local function composerShown(ns)
  local composer = ns.Sign.ui.composer
  return composer ~= nil and composer:IsShown()
end

local function click(ns)
  wow.fire("GOSSIP_SHOW")
  ns.Sign.ui.button:Click()
end

describe("Sign: the gossip button", function()
  after_each(function()
    assert.same({}, wow.errors)
    wow.uninstall()
  end)

  it("shows two buttons under the gossip frame at Coriella Calmbreeze", function()
    local ns = login()
    assert.is_nil(ns.Sign.ui.button)
    assert.is_nil(ns.Sign.ui.read)
    wow.fire("GOSSIP_SHOW")
    local b, r = ns.Sign.ui.button, ns.Sign.ui.read
    for _, button in ipairs({ b, r }) do
      assert.is_table(button)
      assert.equal(_G.GossipFrame, button.parent)
      assert.equal("Button", button.kind)
      assert.equal("UIPanelButtonTemplate", button.template)
      assert.is_true(button:IsShown())
      assert.same({ 160, 24 }, { button.width, button.height })
    end
    assert.equal("Sign the guestbook", b:GetText())
    assert.equal("Read the guestbook", r:GetText())
    assert.same({ "TOPRIGHT", _G.GossipFrame, "BOTTOM", -3, -4 }, b.points[1])
    assert.same({ "TOPLEFT", _G.GossipFrame, "BOTTOM", 3, -4 }, r.points[1])
    wow.fire("GOSSIP_SHOW")
    wow.fire("GOSSIP_SHOW")
    assert.equal(2, gossipButtons())
    assert.equal(b, ns.Sign.ui.button)
    assert.equal(r, ns.Sign.ui.read)
  end)

  it("shows and hides the Read button with the Sign button", function()
    local ns = login()
    wow.fire("GOSSIP_SHOW")
    local b, r = ns.Sign.ui.button, ns.Sign.ui.read
    assert.is_true(r:IsShown())
    state.npc = VENDOR_GUID
    wow.fire("GOSSIP_SHOW")
    assert.is_false(b:IsShown())
    assert.is_false(r:IsShown())
    state.npc = CALM_GUID
    wow.fire("GOSSIP_SHOW")
    assert.is_true(r:IsShown())
    wow.fire("GOSSIP_CLOSED")
    assert.is_false(b:IsShown())
    assert.is_false(r:IsShown())
  end)

  it("Read opens the book on the inn's page, and never signs", function()
    local ns = login()
    local opened = {}
    ns.Book.OpenInn = function(self, npc) opened[#opened + 1] = { self, npc } end
    wow.fire("GOSSIP_SHOW")
    ns.Sign.ui.read:Click()
    assert.same({ { ns.Book, CALM } }, opened)
    assert.same({}, saved().own)
    assert.is_nil(ns.Sign.session)
    -- Away from an inn (the NPC changed under an open gossip): the book opens on no inn.
    state.npc = VENDOR_GUID
    ns.Sign:Read()
    assert.same({ ns.Book, nil }, opened[2])
  end)

  it("keeps a broken book inside the Read click", function()
    local ns = login()
    ns.Core:ToggleDebug()
    wow.fire("GOSSIP_SHOW")
    ns.Book.OpenInn = function() error("raised on purpose") end
    local n = #wow.chat
    ns.Sign.ui.read:Click()
    local lines = chatSince(n)
    assert.equal(1, #lines)
    assert.is_true(has(lines[1], "sign: error in read"))
    ns.Book = nil
    ns.Sign.ui.read:Click()
  end)

  it("hides at a vendor, a malformed, missing, hidden or raising GUID", function()
    local ns = login()
    -- Shown at Calmbreeze first, then the GOSSIP_SHOW for `npc` (with `isSecret`).
    local function shownFor(npc, isSecret)
      state.npc = CALM_GUID
      _G.issecretvalue = function() return false end
      wow.fire("GOSSIP_SHOW")
      assert.is_true(ns.Sign.ui.button:IsShown())
      state.npc = npc
      if isSecret then
        _G.issecretvalue = isSecret
      end
      wow.fire("GOSSIP_SHOW")
      return ns.Sign.ui.button:IsShown()
    end
    for i, npc in ipairs({ VENDOR_GUID, "Creature-0-4615-2991-62-0254089-0000ABCDEF",
      "Player-1-00000002", "", secret(), 254089, {} }) do
      assert.is_false(shownFor(npc), "case " .. i)
    end
    assert.is_false(shownFor(nil))
    -- A valid-looking GUID the client flags: only the hidden check can stop it.
    assert.is_false(shownFor(CALM_GUID, function(v) return v == CALM_GUID end))
    assert.is_false(shownFor(CALM_GUID, function() error("raised on purpose") end))
    assert.equal(2, gossipButtons())
    assert.is_false(ns.Sign.ui.read:IsShown())
    -- UnitGUID itself raising.
    _G.UnitGUID = function(unit)
      if unit == "npc" then
        error("raised on purpose")
      end
    end
    wow.fire("GOSSIP_SHOW")
    assert.is_false(ns.Sign.ui.button:IsShown())
  end)

  it("hides when the NPC changes to a vendor and when the gossip closes", function()
    local ns = login()
    wow.fire("GOSSIP_SHOW")
    assert.is_true(ns.Sign.ui.button:IsShown())
    state.npc = VENDOR_GUID
    wow.fire("GOSSIP_SHOW")
    assert.is_false(ns.Sign.ui.button:IsShown())
    state.npc = CALM_GUID
    wow.fire("GOSSIP_SHOW")
    assert.is_true(ns.Sign.ui.button:IsShown())
    wow.fire("GOSSIP_CLOSED")
    assert.is_false(ns.Sign.ui.button:IsShown())
  end)

  it("makes no button without a gossip frame, with one debug line", function()
    local ns = login()
    ns.Core:ToggleDebug()
    _G.GossipFrame = nil
    local n = #wow.chat
    wow.fire("GOSSIP_SHOW")
    assert.is_nil(ns.Sign.ui.button)
    local lines = chatSince(n)
    assert.equal(1, #lines)
    assert.is_true(has(lines[1], "sign: no gossip frame"))
    wow.fire("GOSSIP_CLOSED")
    ns.Sign:Open() -- a check passes, but there's nowhere to put the composer
    assert.is_nil(ns.Sign.session)
  end)

  it("logs nothing for GOSSIP events when all is well", function()
    local ns = login()
    ns.Core:ToggleDebug()
    local n = #wow.chat
    wow.fire("GOSSIP_SHOW")
    wow.fire("GOSSIP_CLOSED")
    assert.same({}, chatSince(n))
  end)
end)

describe("Sign: a click that can't sign", function()
  after_each(function()
    assert.same({}, wow.errors)
    wow.uninstall()
  end)

  -- Clicks the button; exactly one chat line, holding `text`, and no composer.
  local function refused(ns, text)
    local n = #wow.chat
    click(ns)
    local lines = chatSince(n)
    assert.equal(1, #lines)
    assert.is_true(has(lines[1], text), lines[1])
    assert.is_false(composerShown(ns))
    assert.is_nil(ns.Sign.session)
  end

  it("not resting", function()
    local ns = login({ overrides = { IsResting = function() return false end } })
    refused(ns, "Rest at the inn to sign its guestbook.")
  end)

  it("IsResting raising, hidden or not exactly true", function()
    local ns = login()
    _G.IsResting = function() error("raised on purpose") end
    refused(ns, "Rest at the inn to sign its guestbook.")
    local hiddenTrue = true
    _G.IsResting = function() return hiddenTrue end
    _G.issecretvalue = function(v) return v == true end
    refused(ns, "Rest at the inn to sign its guestbook.")
    _G.issecretvalue = function(v)
      if v == true then
        error("raised on purpose")
      end
      return false
    end
    refused(ns, "Rest at the inn to sign its guestbook.")
    _G.issecretvalue = function() return false end
    _G.IsResting = function() return 1 end
    refused(ns, "Rest at the inn to sign its guestbook.")
  end)

  it("signed this week, with the time to the reset", function()
    local ns = login()
    assert.equal("added", ns.ledger:addOwn({ inn = CALM, t = NOW - 60, phrase = { 101 } }))
    refused(ns, "You've signed this guestbook this week. Sign again after the weekly reset "
      .. "(in 3 days).")
  end)

  it("a read-only ledger", function()
    local ns = login({ db = { global = { ledgers = { [GUID] = "damaged" } } } })
    assert.is_true(ns.ledger.readOnly)
    refused(ns, "Your ledger is read-only")
    assert.equal("damaged", saved())
  end)

  it("no ledger (the GUID was unreadable at login)", function()
    local ns = login({ setup = function() state.player = nil end })
    assert.is_nil(ns.ledger)
    refused(ns, "Your ledger isn't open yet. Try again in a moment.")
  end)

  it("the server time hidden", function()
    local ns = login()
    local hiddenNow = secret()
    _G.GetServerTime = function() return hiddenNow end
    _G.issecretvalue = function(v) return rawequal(v, hiddenNow) end
    refused(ns, "The server time can't be read right now. Try again in a moment.")
  end)

  it("logs the reason when the debug log is on", function()
    local ns = login({ overrides = { IsResting = function() return false end } })
    ns.Core:ToggleDebug()
    local n = #wow.chat
    click(ns)
    local lines = chatSince(n)
    assert.equal(2, #lines)
    assert.is_true(has(lines[2], "sign: not_resting"))
  end)
end)

describe("Sign: signing", function()
  after_each(function()
    assert.same({}, wow.errors)
    wow.uninstall()
  end)

  it("composes, signs, records the unlocks and tells Sync, end to end", function()
    local ns = login()
    local window = spyWindow(ns)
    click(ns)
    assert.is_true(composerShown(ns))
    local ui = ns.Sign.ui
    assert.equal(_G.GossipFrame, ui.composer.parent)
    assert.same({ "TOPLEFT", _G.GossipFrame, "TOPRIGHT", 0, 0 }, ui.composer.points[1])
    assert.same({ 0, 0, 0, 0.85 }, ui.composer.textures[1].color)
    assert.equal("Sign the guestbook", ui.title:GetText())
    assert.equal("Calmbreeze Inn", ui.inn:GetText())
    assert.equal("Rested here, dreaming of home.", ui.preview:GetText())
    local lists = ui.lists
    assert.equal("Rested here, dreaming of ___.", lists.template.rows[1].text:GetText())
    assert.is_true(lists.template.rows[1].mark:IsShown())
    assert.equal("Hearthside", lists.voice.rows[1].button:GetText())
    assert.is_false(lists.voice.rows[1].button:IsEnabled())
    assert.is_true(lists.voice.frame:IsShown())
    assert.is_true(lists.word.frame:IsShown())
    assert.is_true(lists.cat.frame:IsShown())
    assert.is_false(lists.conj.frame:IsShown())
    assert.is_false(ui.line2:IsShown())
    assert.is_false(ui.rows.seal.prev:IsShown())
    assert.equal("Add a second line", ui.toggle:GetText())

    lists.template.rows[2].button:Click()
    lists.word.rows[2].button:Click()
    assert.equal("Lingered a day longer for the hearth.", ui.preview:GetText())
    ui.toggle:Click()
    assert.equal("Remove the second line", ui.toggle:GetText())
    assert.is_true(ui.line2:IsShown())
    assert.equal("Second line", ui.line2:GetText())
    assert.is_false(ui.line2:IsEnabled()) -- editing line 2 now
    assert.is_true(ui.line1:IsEnabled())
    assert.is_true(lists.conj.frame:IsShown())
    assert.equal("And then...", lists.conj.rows[1].button:GetText())
    assert.is_false(lists.conj.rows[1].button:IsEnabled())
    assert.equal("Hearthside", lists.voice.rows[1].button:GetText())
    assert.is_false(lists.voice.rows[1].button:IsEnabled()) -- line 2's voice follows
    assert.is_true(lists.template.rows[1].mark:IsShown()) -- line 2's own template
    assert.is_false(lists.template.rows[2].mark:IsShown())
    assert.is_true(lists.word.frame:IsShown())
    assert.equal("Lingered a day longer for the hearth. And then... Rested here, dreaming of "
      .. "home.", ui.preview:GetText())
    for _ = 1, 5 do
      lists.template.next:Click()
    end
    assert.is_false(lists.template.next:IsEnabled())
    lists.template.rows[8].button:Click() -- the last template has no slot
    assert.is_false(lists.word.frame:IsShown())
    assert.is_false(lists.cat.frame:IsShown())
    assert.equal("Lingered a day longer for the hearth. And then... Thank you for everything.",
      ui.preview:GetText())

    local n = #wow.chat
    ui.sign:Click()
    assert.same({ { inn = CALM, t = NOW, phrase = { 2, 1002, 501, 111 } } }, saved().own)
    assert.same({}, saved().earned) -- the shipped data marks no place complete (#110)
    assert.equal(1, window.n)
    local lines = chatSince(n)
    assert.equal(1, #lines)
    assert.is_true(has(lines[1], "You signed the guestbook of Calmbreeze Inn."))
    assert.is_false(composerShown(ns))
    assert.is_nil(ns.Sign.session)
  end)

  it("writes each line in its own voice", function()
    local ns = login()
    click(ns)
    local ui = ns.Sign.ui
    local voices = ui.lists.voice.rows
    voices[2].button:Click()
    assert.equal("Bardic", voices[2].button:GetText())
    assert.is_false(voices[2].button:IsEnabled())
    assert.is_true(voices[1].button:IsEnabled())
    assert.equal("Let the ballads tell of home!", ui.preview:GetText())
    ui.toggle:Click()
    assert.is_false(voices[2].button:IsEnabled()) -- line 2 follows line 1
    voices[3].button:Click()
    assert.equal("Grumbler", voices[3].button:GetText())
    assert.is_false(voices[3].button:IsEnabled())
    assert.equal("Let the ballads tell of home! Mind you... Can't fault home.",
      ui.preview:GetText())
    ui.line1:Click()
    assert.is_false(voices[2].button:IsEnabled()) -- line 1 is still Bardic
    assert.is_true(voices[3].button:IsEnabled())
    ui.sign:Click()
    assert.same({ { inn = CALM, t = NOW, phrase = { 201, 1001, 521, 231, 1001 } } }, saved().own)
  end)

  it("signs with a seal the next week", function()
    local ns = login()
    click(ns)
    ns.Sign.ui.sign:Click()
    assert.is_false(ns.Sign.ui.rows.seal.label:IsShown())
    -- Seals 2 and 101 recorded under older data (the shipped data marks nothing, #110).
    assert.is_true(ns.ledger:markEarned(2, NOW) and ns.ledger:markEarned(101, NOW))
    wow.now = RESET + 1
    click(ns)
    local rows = ns.Sign.ui.rows
    assert.is_true(rows.seal.label:IsShown())
    assert.equal("No seal", rows.seal.label:GetText())
    rows.seal.next:Click()
    assert.equal("Innkeeper's seal", rows.seal.label:GetText())
    rows.seal.next:Click()
    assert.equal("Zephras Isle", rows.seal.label:GetText())
    ns.Sign.ui.sign:Click()
    local own = saved().own
    assert.equal(2, #own)
    assert.same({ inn = CALM, t = RESET + 1, phrase = { 1, 1001 }, seal = 101 }, own[2])
  end)

  it("keeps one composer and its draft on a double click, and signs once", function()
    local ns = login()
    local window = spyWindow(ns)
    click(ns)
    local composer, session = ns.Sign.ui.composer, ns.Sign.session
    ns.Sign.ui.lists.template.rows[2].button:Click()
    click(ns)
    assert.equal(composer, ns.Sign.ui.composer)
    assert.equal(session, ns.Sign.session)
    assert.equal(1, #wow.children(_G.GossipFrame) - gossipButtons())
    assert.equal("Lingered a day longer for home.", ns.Sign.ui.preview:GetText())
    local n = #wow.chat
    ns.Sign.ui.sign:Click()
    ns.Sign.ui.sign:Click()
    ns.Sign:Commit()
    assert.equal(1, #saved().own)
    assert.equal(1, window.n)
    assert.equal(1, #chatSince(n))
  end)

  it("Cancel closes the composer and signs nothing", function()
    local ns = login()
    click(ns)
    ns.Sign.ui.cancel:Click()
    assert.is_false(composerShown(ns))
    assert.is_nil(ns.Sign.session)
    ns.Sign:Commit()
    assert.same({}, saved().own)
  end)

  it("closes on GOSSIP_CLOSED; a commit after it does nothing, and changed if forced", function()
    local ns = login()
    local window = spyWindow(ns)
    click(ns)
    local session = ns.Sign.session
    wow.fire("GOSSIP_CLOSED")
    assert.is_false(composerShown(ns))
    assert.is_nil(ns.Sign.session)
    local n = #wow.chat
    ns.Sign:Commit()
    assert.same({}, chatSince(n))
    assert.same({}, saved().own)

    ns.Sign.session = session
    ns.Sign.ui.composer:Show()
    state.npc = nil
    ns.Sign:Commit()
    local lines = chatSince(n)
    assert.equal(1, #lines)
    assert.is_true(has(lines[1], "Talk to the innkeeper again to sign the guestbook."))
    assert.same({}, saved().own)
    assert.equal(0, window.n)
    assert.is_false(composerShown(ns))
    assert.is_nil(ns.Sign.session)
  end)

  it("closes when the NPC changes, keeps the draft for the same innkeeper", function()
    local ns = login()
    click(ns)
    state.npc = VENDOR_GUID
    wow.fire("GOSSIP_SHOW")
    assert.is_false(composerShown(ns))
    assert.is_nil(ns.Sign.session)

    state.npc = CALM_GUID
    click(ns)
    local session = ns.Sign.session
    ns.Sign.ui.lists.template.rows[2].button:Click()
    wow.fire("GOSSIP_SHOW")
    assert.equal(session, ns.Sign.session)
    assert.is_true(composerShown(ns))
    assert.equal("Lingered a day longer for home.", ns.Sign.ui.preview:GetText())
  end)

  it("leaves the composer open on a refusal it can fix", function()
    local ns = login()
    click(ns)
    _G.IsResting = function() return false end
    local n = #wow.chat
    ns.Sign.ui.sign:Click()
    assert.is_true(has(chatSince(n)[1], "Rest at the inn to sign its guestbook."))
    assert.is_true(composerShown(ns))
    _G.IsResting = function() return true end
    ns.Sign.ui.sign:Click()
    assert.equal(1, #saved().own)
  end)

  it("signs with the faction hidden or raising", function()
    local hiddenFaction = secret()
    local ns = login()
    _G.UnitFactionGroup = function() return hiddenFaction end
    _G.issecretvalue = function(v) return rawequal(v, hiddenFaction) end
    click(ns)
    ns.Sign.ui.sign:Click()
    assert.equal(1, #saved().own)

    wow.now = RESET + 1
    _G.UnitFactionGroup = function() error("raised on purpose") end
    click(ns)
    ns.Sign.ui.sign:Click()
    assert.equal(2, #saved().own)
  end)
end)

describe("Sign: the composer's lists (#102)", function()
  after_each(function()
    assert.same({}, wow.errors)
    wow.uninstall()
  end)

  -- A template's label as the composer shows it: the slot as ___.
  local function label(ns, id)
    local text = ns.Phrase.text(id)
    local a = text:find("{w}", 1, true)
    if a then
      return text:sub(1, a - 1) .. "___" .. text:sub(a + 3)
    end
    return text
  end

  -- The texts of a list's shown rows.
  local function texts(list)
    local out = {}
    for _, row in ipairs(list.rows) do
      if row.button:IsShown() then
        out[#out + 1] = row.text and row.text:GetText() or row.button:GetText()
      end
    end
    return out
  end

  local function marks(list)
    local n = 0
    for _, row in ipairs(list.rows) do
      if row.button:IsShown() and row.mark:IsShown() then
        n = n + 1
      end
    end
    return n
  end

  local function wheel(list, delta)
    list.frame.scripts.OnMouseWheel(list.frame, delta)
  end

  it("builds plain lists: text rows with a gold mark, a wheel, page buttons", function()
    local ns = login()
    click(ns)
    local lists = ns.Sign.ui.lists
    for _, key in ipairs({ "voice", "conj", "template", "cat", "word" }) do
      local list = lists[key]
      assert.equal(ns.Sign.ui.composer, list.frame.parent, key)
      assert.is_true(list.frame.mouseWheel, key)
      assert.is_function(list.frame.scripts.OnMouseWheel, key)
      assert.equal("UIPanelButtonTemplate", list.prev.template, key)
      assert.equal("UIPanelButtonTemplate", list.next.template, key)
    end
    for _, key in ipairs({ "template", "cat", "word" }) do
      for _, row in ipairs(lists[key].rows) do
        assert.equal("Button", row.button.kind)
        assert.is_nil(row.button.template)
        assert.equal("GameFontHighlightSmall", row.text.template)
        assert.same({ 1, 0.82, 0, 0.25 }, row.mark.color)
      end
    end
    assert.equal(8, #lists.template.rows)
    assert.equal(9, #lists.cat.rows)
    assert.equal(9, #lists.word.rows)
    for _, key in ipairs({ "voice", "conj" }) do
      assert.equal(8, #lists[key].rows)
      for _, row in ipairs(lists[key].rows) do
        assert.equal("UIPanelButtonTemplate", row.button.template)
      end
    end
  end)

  it("shows the voices as a strip, the chosen one disabled", function()
    local ns = login()
    click(ns)
    local ui = ns.Sign.ui
    local voice = ui.lists.voice
    assert.same({ "Hearthside", "Bardic", "Grumbler", "Scholar", "Rowdy", "Mystic", "Sailor",
      "Noble" }, texts(voice))
    for i, row in ipairs(voice.rows) do
      assert.equal(i ~= 1, row.button:IsEnabled())
    end
    assert.is_false(voice.prev:IsShown()) -- eight voices fit
    assert.is_false(voice.next:IsShown())
    assert.is_false(ui.line1:IsEnabled()) -- editing line 1
    assert.equal("First line", ui.line1:GetText())

    voice.rows[2].button:Click() -- Bardic
    local P = ns.Phrase
    assert.equal(label(ns, P.templates(2)[1]), ui.lists.template.rows[1].text:GetText())
    assert.equal(#P.templates(2) > 8, ui.lists.template.next:IsShown())
    ui.toggle:Click() -- line 2 follows: Bardic there too
    assert.is_false(voice.rows[2].button:IsEnabled())
    assert.equal(#P.conjunctions(2), #texts(ui.lists.conj))
    assert.equal(P.text(P.conjunctions(2)[1]), ui.lists.conj.rows[1].button:GetText())
    ui.lists.conj.rows[2].button:Click()
    assert.is_false(ui.lists.conj.rows[2].button:IsEnabled())
    assert.is_true(ui.lists.conj.rows[1].button:IsEnabled())
    ui.line1:Click()
    assert.is_false(ui.lists.conj.frame:IsShown()) -- line 1 has no conjunction
    assert.is_false(ui.line1:IsEnabled())
    assert.is_true(ui.line2:IsEnabled())
  end)

  it("pages and wheels the template list, stopping at both ends", function()
    local ns = login()
    click(ns)
    local P = ns.Phrase
    local ids = P.templates(1)
    assert.equal(36, #ids)
    local list = ns.Sign.ui.lists.template
    local function firstShown()
      return list.rows[1].text:GetText()
    end
    assert.equal(8, #texts(list))
    assert.is_true(list.prev:IsShown())
    assert.is_true(list.next:IsShown())
    assert.is_false(list.prev:IsEnabled())
    assert.is_true(list.next:IsEnabled())
    assert.equal(label(ns, ids[1]), firstShown())

    list.next:Click()
    local want = {}
    for i = 9, 16 do
      want[#want + 1] = label(ns, ids[i])
    end
    assert.same(want, texts(list))
    assert.is_true(list.prev:IsEnabled())
    wheel(list, -1) -- down one row
    assert.equal(label(ns, ids[10]), firstShown())
    wheel(list, 1)
    assert.equal(label(ns, ids[9]), firstShown())
    wheel(list, "junk")
    assert.equal(label(ns, ids[9]), firstShown())

    for _ = 1, 3 do
      list.prev:Click()
      ns.Sign:Scroll("template", -8) -- past the top, even with the button disabled
    end
    assert.equal(label(ns, ids[1]), firstShown())
    wheel(list, 1)
    assert.equal(label(ns, ids[1]), firstShown())
    assert.is_false(list.prev:IsEnabled())

    for _ = 1, 10 do
      ns.Sign:Scroll("template", 8)
    end
    assert.equal(label(ns, ids[29]), firstShown())
    assert.equal(label(ns, ids[36]), list.rows[8].text:GetText())
    assert.is_false(list.next:IsEnabled())
    wheel(list, -1)
    assert.equal(label(ns, ids[29]), firstShown())

    -- The chosen template (the first) is out of view: no row is marked.
    assert.equal(0, marks(list))
    list.rows[3].button:Click()
    assert.equal(1, marks(list))
    assert.is_true(list.rows[3].mark:IsShown())
    assert.equal(P.render({ ids[31], P.hasSlot(ids[31]) and 1001 or nil }),
      ns.Sign.ui.preview:GetText())
  end)

  it("hides page buttons when all fits, and the word lists for a slotless template", function()
    local ns = login()
    click(ns)
    local lists = ns.Sign.ui.lists
    assert.equal(9, #texts(lists.cat))
    assert.is_false(lists.cat.prev:IsShown())
    assert.is_false(lists.cat.next:IsShown())
    assert.is_true(lists.word.next:IsShown()) -- 20 words, 9 rows
    ns.Sign:Scroll("template", 100)
    lists.template.rows[8].button:Click() -- 111, no slot
    assert.is_false(lists.cat.frame:IsShown())
    assert.is_false(lists.word.frame:IsShown())
    assert.is_false(lists.word.next:IsShown())
    assert.is_false(lists.word.rows[1].button:IsShown())
    assert.equal("Thank you for everything.", ns.Sign.ui.preview:GetText())
  end)

  it("follows the category clicked, with one mark per list", function()
    local ns = login()
    click(ns)
    local P = ns.Phrase
    local lists = ns.Sign.ui.lists
    assert.equal(1, marks(lists.cat))
    assert.is_true(lists.cat.rows[1].mark:IsShown())
    assert.equal(1, marks(lists.word))
    lists.word.next:Click()
    lists.cat.rows[3].button:Click()
    assert.equal(1, marks(lists.cat))
    assert.is_true(lists.cat.rows[3].mark:IsShown())
    local want = {}
    for i = 1, 9 do
      want[i] = P.text(P.words(3)[i])
    end
    assert.same(want, texts(lists.word)) -- the new category's words, from the top
    assert.equal(1, marks(lists.word))
    assert.is_true(lists.word.rows[1].mark:IsShown())
    lists.word.rows[4].button:Click()
    assert.equal(1, marks(lists.word))
    assert.is_true(lists.word.rows[4].mark:IsShown())
    assert.equal(P.render({ 1, P.words(3)[4] }), ns.Sign.ui.preview:GetText())
  end)

  it("ignores a click on an empty row or an unknown list", function()
    local ns = login()
    click(ns)
    local before = ns.Sign.ui.preview:GetText()
    ns.Sign:Pick("template", nil)
    ns.Sign:Pick("nope", 2)
    ns.Sign:Scroll("nope", 8)
    ns.Sign:Pick({}, 2)
    assert.equal(before, ns.Sign.ui.preview:GetText())
    ns.Sign:Cancel()
    ns.Sign:Pick("template", 2) -- no session
    ns.Sign:Scroll("template", 8)
    ns.Sign:SetLine(2)
    assert.is_nil(ns.Sign.session)
  end)
end)

describe("Sign: errors stay inside", function()
  after_each(function()
    assert.same({}, wow.errors)
    wow.uninstall()
  end)

  it("tells the book once after a signature, and a raising book changes nothing", function()
    local ns = login()
    local calls = {}
    ns.Book.Changed = function(self) calls[#calls + 1] = self end
    click(ns)
    ns.Sign.ui.sign:Click()
    assert.same({ ns.Book }, calls)
    assert.equal(1, #saved().own)

    -- A refusal doesn't tell the book.
    click(ns)
    assert.equal(1, #calls)

    wow.now = RESET + 1
    ns.Core:ToggleDebug()
    ns.Book.Changed = function() error("raised on purpose") end
    click(ns)
    local n = #wow.chat
    ns.Sign.ui.sign:Click()
    assert.equal(2, #saved().own)
    local lines = chatSince(n)
    assert.equal(3, #lines)
    assert.is_true(has(lines[1], "sign: error in book"))
    assert.is_true(has(lines[2], "You signed the guestbook of Calmbreeze Inn."))
    assert.is_true(has(lines[3], "sign: added"))
    assert.is_false(composerShown(ns))
  end)

  it("keeps the entry and the line when Sync's WindowChanged raises", function()
    local ns = login()
    ns.Core:ToggleDebug()
    ns.Sync.WindowChanged = function() error("raised on purpose") end
    click(ns)
    local n = #wow.chat
    ns.Sign.ui.sign:Click()
    assert.equal(1, #saved().own)
    local lines = chatSince(n)
    assert.is_true(has(lines[1], "sign: error in sync"))
    assert.is_true(has(lines[2], "You signed the guestbook of Calmbreeze Inn."))
  end)

  it("says nothing was signed when the flow raises", function()
    local ns = login()
    click(ns)
    ns.Sign.flow.commit = function() error("raised on purpose") end
    local n = #wow.chat
    ns.Sign.ui.sign:Click()
    local lines = chatSince(n)
    assert.equal(1, #lines)
    assert.is_true(has(lines[1], "Nothing was signed."))
    assert.same({}, saved().own)

    ns.Sign.flow.check = function() error("raised on purpose") end
    ns.Sign:Cancel()
    n = #wow.chat
    click(ns)
    assert.is_true(has(chatSince(n)[1], "Nothing was signed."))
  end)

  it("logs an error in a handler or click and nothing else", function()
    local ns = login()
    ns.Core:ToggleDebug()
    click(ns)
    ns.Sign.session.draft = {} -- every draft method is gone now
    local n = #wow.chat
    ns.Sign.ui.lists.template.rows[2].button:Click()
    ns.Sign.ui.toggle:Click()
    ns.Sign.ui.sign:Click()
    ns.Sign.flow.innAt = function() error("raised on purpose") end
    wow.fire("GOSSIP_SHOW")
    ns.Sign.flow.recordUnlocks = function() error("raised on purpose") end
    assert.is_nil(ns.Sign:RecordUnlocks())
    _G.GossipFrame = nil
    ns.Sign.ui.button = nil
    wow.fire("GOSSIP_CLOSED")
    local want = { "sign: error in pick", "sign: error in toggle", "sign: error in commit",
      "sign: error in gossip show", "sign: error in login" }
    local lines = chatSince(n)
    assert.equal(#want, #lines)
    for i, text in ipairs(want) do
      assert.is_true(has(lines[i], text), lines[i])
    end
  end)

  it("logs an error in the seal row, a page button, the wheel or a line tab", function()
    local ns = login()
    ns.Core:ToggleDebug()
    click(ns)
    local list = ns.Sign.ui.lists.template
    ns.Sign.session.draft = {}
    local n = #wow.chat
    ns.Sign.ui.rows.seal.next:Click()
    list.next:Click()
    list.frame.scripts.OnMouseWheel(list.frame, -1)
    ns.Sign:SetLine(1)
    local want = { "sign: error in step", "sign: error in scroll", "sign: error in wheel",
      "sign: error in line" }
    local lines = chatSince(n)
    assert.equal(#want, #lines)
    for i, text in ipairs(want) do
      assert.is_true(has(lines[i], text), lines[i])
    end
  end)
end)

describe("Core recording unlocks at login", function()
  after_each(function()
    assert.same({}, wow.errors)
    wow.uninstall()
  end)

  local T = NOW - 3600

  local function db(data)
    return { global = { ledgers = { [GUID] = data } } }
  end

  local function ledgerData(schema)
    return { schema = schema, me = {}, own = { { inn = CALM, t = T, phrase = { 101 } } },
      travelers = {}, earned = {}, quarantine = {} }
  end

  it("fills earned for a saved signature", function()
    login({ db = db(ledgerData(1)) })
    assert.same({}, saved().earned) -- the shipped data marks no place complete (#110)
  end)

  it("writes nothing to a read-only ledger", function()
    local data = ledgerData(2)
    local before = deepcopy(data)
    local ns = login({ db = db(data) })
    assert.is_true(ns.ledger.readOnly)
    assert.same(before, saved())
  end)

  it("opens the ledger and starts Sync when recording raises", function()
    local ns = login({
      db = db(ledgerData(1)),
      setup = function(ns_) ns_.Sign.RecordUnlocks = function() error("raised on purpose") end end,
    })
    assert.is_table(ns.ledger)
    assert.is_false(ns.ledger.readOnly)
    assert.is_table(ns.Sync.client)
    assert.same({}, saved().earned)
  end)

  it("records nothing for a ledger whose entries unlock nothing", function()
    local ns = login()
    assert.same({}, ns.Sign:RecordUnlocks())
    assert.same({}, saved().earned)
  end)
end)
