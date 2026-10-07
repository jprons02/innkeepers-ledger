-- Book (glue): /ledger opening and closing the book, the first open, an inn's page, page
-- turns, the Read button, the quiet refresh, the Share page and its nudge, the quill, a
-- damaged record, the fallbacks and errors (docs/specs/book.md 6.3). The whole AddOn runs
-- under the WoW stub, logged in as the stub's player, Alliance, with the real data.
local load = require("helpers.load")
local wow = require("helpers.wow_stub")

local GUID = "Player-1-00000001" -- the stub's UnitGUID("player")
local NOW = 1800000000           -- the stub's default server time, 15 January 2027 08:00 UTC
local WEEK = 604800
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

-- Days since 1970-01-01 for a civil date (the inverse of BookView's).
local function daysFromCivil(y, m, d)
  if m <= 2 then
    y = y - 1
  end
  local era = math.floor(y / 400)
  local yoe = y - era * 400
  local mp = (m + 9) % 12
  local doy = math.floor((153 * mp + 2) / 5) + d - 1
  local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
  return era * 146097 + doe - 719468
end

-- `date` and `time` for a client whose local time is UTC + offset, whatever this machine's
-- time zone is.
local function clock(offset)
  return {
    date = function(fmt, t)
      if fmt == "*t" then
        local r = os.date("!*t", t + offset)
        r.isdst = false
        return r
      elseif fmt == "!*t" then
        return os.date("!*t", t)
      end
      return os.date(fmt, t)
    end,
    time = function(tt)
      return daysFromCivil(tt.year, tt.month, tt.day) * 86400 + tt.hour * 3600 + tt.min * 60
        + tt.sec - offset
    end,
  }
end

-- What UnitGUID answers this case: state.player for "player", state.npc for "npc".
local state

-- Loads the AddOn and logs in: resting, at Coriella Calmbreeze, the clock in UTC. opts:
-- overrides (stub names), db (the SavedVariables as saved), beforeBook(ns) (runs just
-- before UI/Book.lua), setup(ns) (after the files, before ADDON_LOADED).
local function login(opts)
  opts = opts or {}
  state = { player = GUID, npc = CALM_GUID }
  local utc = clock(0)
  local overrides = {
    IsResting = function() return true end,
    UnitGUID = function(unit)
      if unit == "player" then
        return state.player
      elseif unit == "npc" then
        return state.npc
      end
    end,
    date = utc.date,
    time = utc.time,
  }
  for k, v in pairs(opts.overrides or {}) do
    overrides[k] = v
  end
  wow.install(overrides)
  if opts.db ~= nil then
    _G.InnkeepersLedgerDB = opts.db
  end
  local ns = {}
  for _, path in ipairs(load.toc_files()) do
    if path == "UI/Book.lua" and opts.beforeBook then
      opts.beforeBook(ns)
    end
    load.file(path, ns)
  end
  if opts.setup then
    opts.setup(ns)
  end
  wow.fire("ADDON_LOADED", load.ADDON_NAME)
  wow.fire("PLAYER_LOGIN")
  return ns
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

local function shown(region)
  return region ~= nil and region:IsShown() == true
end

-- Every text under a frame: font strings, button labels, edit boxes.
local function frameStrings(frame, out)
  out = out or {}
  for _, fs in ipairs(frame.fontStrings or {}) do
    if fs.text then
      out[#out + 1] = fs.text
    end
  end
  if frame.text then
    out[#out + 1] = frame.text
  end
  for _, child in ipairs(wow.children(frame)) do
    frameStrings(child, out)
  end
  return out
end

local function anyString(ns, text)
  for _, s in ipairs(frameStrings(ns.Book.ui.frame)) do
    if s:find(text, 1, true) then
      return true
    end
  end
  return false
end

local function sign(ns, t, phrase)
  assert.equal("added", ns.ledger:addOwn({ inn = CALM, t = t or NOW - 3600,
    phrase = phrase or { 101 } }))
end

-- Records the unlocks one signature at Calmbreeze earned before #110 (seal 101, the
-- Cartographer's quill 1003, seal 2). The shipped data marks no place complete, so they
-- now come only from a recorded `earned` floor at that signature's time, as for a character
-- that recorded them under older data (collection-cosmetics.md 3.11).
local function recordPlaceUnlocks(ns, t)
  for _, id in ipairs({ 101, 1003, 2 }) do
    assert.is_true(ns.ledger:markEarned(id, t or NOW - 3600))
  end
end

local function traveler(n)
  return string.format("Player-1-%08X", 4096 + n) -- never the player's own GUID
end

local function addTraveler(ns, n, t, name)
  assert.equal("added", ns.ledger:addForeign(traveler(n), name or ("Mira" .. string.char(64 + n)),
    { inn = CALM, t = t, phrase = { 102 } }, NOW))
end

local function record()
  local book = rawget(_G.InnkeepersLedgerDB.global, "book")
  return type(book) == "table" and book[GUID] or nil
end

local function date(ns, t)
  return ns.BookView.dateText(t, 0)
end

local function innRowTexts(ns)
  local out = {}
  for _, row in ipairs(ns.Book.ui.inn.rows) do
    if shown(row.frame) then
      local parts = {}
      for _, k in ipairs({ "head", "meta", "text", "flourish" }) do
        if shown(row[k]) then
          parts[#parts + 1] = row[k]:GetText()
        end
      end
      out[#out + 1] = table.concat(parts, " / ")
    end
  end
  return out
end

describe("Book: opening and closing", function()
  after_each(function()
    assert.same({}, wow.errors)
    wow.uninstall()
  end)

  it("/ledger shows the book, and again hides it; any other word toggles", function()
    local ns = login()
    assert.is_nil(_G.InnkeepersLedgerBook)
    wow.slash("/ledger")
    local frame = _G.InnkeepersLedgerBook
    assert.is_table(frame)
    assert.equal(ns.Book.ui.frame, frame)
    assert.equal("InnkeepersLedgerBook", frame.name)
    assert.is_true(rawequal(_G.UIParent, frame.parent))
    assert.is_true(frame:IsShown())
    assert.same({ 860, 560 }, { frame.width, frame.height })
    assert.same({ "CENTER", _G.UIParent, "CENTER", 0, 0 }, frame.points[1])
    assert.equal("HIGH", frame.strata)
    assert.is_true(frame.clamped)
    assert.is_true(frame.mouse)
    assert.same({}, wow.chat)
    wow.slash("/ledger")
    assert.is_false(frame:IsShown())
    wow.slash("/ledger foo")
    assert.is_true(frame:IsShown())
    -- Built once.
    wow.slash("/ledger")
    wow.slash("/ledger")
    assert.equal(frame, ns.Book.ui.frame)
    assert.equal(1, #wow.children(_G.UIParent))
  end)

  it("puts its one name in the client's Escape list", function()
    login()
    wow.slash("/ledger")
    assert.same({ "InnkeepersLedgerBook" }, _G.UISpecialFrames)
    wow.slash("/ledger")
    wow.slash("/ledger")
    assert.same({ "InnkeepersLedgerBook" }, _G.UISpecialFrames)
  end)

  it("still opens without the Escape list, with one debug line", function()
    local ns = login({ overrides = { UISpecialFrames = false } })
    _G.UISpecialFrames = nil
    ns.Core:ToggleDebug()
    local n = #wow.chat
    wow.slash("/ledger")
    assert.is_true(ns.Book.ui.frame:IsShown())
    local lines = chatSince(n)
    assert.equal(1, #lines)
    assert.is_true(has(lines[1], "book: no special frames"))
  end)

  it("closes with its Close button", function()
    local ns = login()
    wow.slash("/ledger")
    assert.equal("Close", ns.Book.ui.close:GetText())
    ns.Book.ui.close:Click()
    assert.is_false(ns.Book.ui.frame:IsShown())
  end)

  it("keeps /ledger version and /ledger debug", function()
    local ns = login()
    wow.slash("/ledger version")
    assert.equal(1, #wow.chat)
    assert.is_true(has(wow.chat[1], "version dev"))
    assert.is_nil(ns.Book.ui)
    wow.slash("/ledger debug")
    assert.is_true(has(wow.chat[2], "Debug log on."))
    assert.is_nil(ns.Book.ui)
  end)

  it("draws the frame, the pages and the tabs in the DRAFT look", function()
    local ns = login()
    wow.slash("/ledger")
    local ui = ns.Book.ui
    assert.same({ 0.10, 0.07, 0.05, 0.95 }, ui.frame.textures[1].color)
    assert.equal("Interface\\DialogFrame\\UI-DialogBox-Background-Dark", ui.frame.textures[1].file)
    assert.equal("Interface\\Spellbook\\Spellbook-Page-1", ui.left.frame.textures[1].file)
    assert.equal("Interface\\Spellbook\\Spellbook-Page-2", ui.right.frame.textures[1].file)
    local names = {}
    for name, b in pairs(ui.tabs) do
      assert.equal("UIPanelButtonTemplate", b.template)
      names[name] = b:GetText()
    end
    assert.same({ inns = "Inns", collection = "Collection", cosmetics = "Cosmetics",
      share = "Share" }, names)
    assert.is_false(ui.tabs.inns:IsEnabled())
    assert.is_true(ui.tabs.share:IsEnabled())
    assert.same({ "TOPLEFT", ui.frame, "BOTTOMLEFT", 24, -2 }, ui.tabs.inns.points[1])
    -- Ink on parchment, without the font shadow.
    local fs = ui.title.title
    assert.same({ 0.20, 0.13, 0.08, 1 }, fs.textColor)
    assert.same({ 0, 0 }, fs.shadowOffset)
    assert.equal(_G.QuestTitleFont, fs.fontObject)
    assert.equal(_G.GameFontNormal, ui.title.steps[1].fontObject)
    assert.equal(_G.GameFontHighlightSmall, ui.share.edit.fontObject)
  end)

  it("keeps the color under a texture the client can't find", function()
    local ns = login()
    wow.textureResult = false
    wow.slash("/ledger")
    assert.same({ 0.87, 0.80, 0.64, 1 }, ns.Book.ui.left.frame.textures[1].color)
  end)
end)

describe("Book: the Inns tab", function()
  after_each(function()
    assert.same({}, wow.errors)
    wow.uninstall()
  end)

  it("opens an empty ledger on its title page and the help page", function()
    local ns = login()
    wow.slash("/ledger")
    local ui = ns.Book.ui
    assert.is_true(shown(ui.title.panel))
    assert.is_false(shown(ui.list.panel))
    assert.equal("The ledger of Traveler", ui.title.title:GetText())
    assert.equal(ns.BookView.TEXT.step1, ui.title.steps[1]:GetText())
    assert.equal(ns.BookView.TEXT.step3, ui.title.steps[3]:GetText())
    assert.equal("Open this book any time with /ledger.", ui.title.hint:GetText())
    assert.is_true(shown(ui.help.panel))
    assert.equal("What your ledger shares", ui.help.sharesTitle:GetText())
    assert.equal(ns.BookView.TEXT.sharesText, ui.help.sharesText:GetText())
    assert.is_true(has(ui.help.sharesText:GetText(), "up to 40"))
    assert.is_false(ui.left.prev:IsEnabled())
    assert.is_true(ui.left.next:IsEnabled())
    assert.is_false(shown(ui.left.label))
    assert.is_false(shown(ui.right.prev))
    assert.is_false(shown(ui.notice))

    ui.left.next:Click()
    assert.is_true(shown(ui.list.panel))
    assert.is_false(shown(ui.title.panel))
    local rows = ui.list.rows
    assert.equal("Azeroth", rows[1].text:GetText())
    -- The shipped data marks no place complete yet: each total says there may be more.
    assert.equal("0 of 1+", rows[1].sub:GetText())
    assert.equal("Zephras Isle", rows[2].text:GetText())
    assert.equal("signed 0 of 1+", rows[2].sub:GetText())
    assert.equal("Calmbreeze Inn", rows[3].text:GetText())
    assert.same({ 0.20, 0.13, 0.08, 0.45 }, rows[3].text.textColor)
    assert.is_false(shown(rows[3].mark))
    assert.is_false(shown(rows[4].button))
    assert.equal("1 / 1", ui.left.label:GetText())
    assert.is_true(ui.left.prev:IsEnabled())
    assert.is_false(ui.left.next:IsEnabled())
    ui.left.prev:Click()
    assert.is_true(shown(ui.title.panel))
  end)

  it("lists a signed inn and opens its page from the list", function()
    local ns = login()
    sign(ns)
    wow.slash("/ledger")
    local ui = ns.Book.ui
    assert.is_true(shown(ui.list.panel))
    local rows = ui.list.rows
    assert.equal("signed 1 of 1+", rows[2].sub:GetText())
    assert.is_true(shown(rows[3].mark))
    assert.same({ 0.20, 0.13, 0.08, 1 }, rows[3].text.textColor)
    assert.is_false(shown(ui.inn.panel))
    rows[3].button:Click()
    assert.is_true(shown(ui.inn.panel))
    assert.is_false(shown(ui.help.panel))
    assert.is_true(shown(rows[3].selected))
    assert.equal("Calmbreeze Inn", ui.inn.title:GetText())
    assert.equal("Zephras Isle, Azeroth", ui.inn.place:GetText())
    assert.equal("Signed once", ui.inn.count:GetText())
    assert.is_false(shown(ui.inn.last))
    assert.equal(date(ns, NOW - 3600), ui.inn.stamp.date:GetText())
    assert.is_true(shown(ui.inn.stamp.solid[1]))
    assert.is_false(shown(ui.inn.stamp.dashes[1]))
    assert.same({
      "Your signatures",
      date(ns, NOW - 3600) .. " / " .. ns.Phrase.render({ 101 }),
      "Travelers' signatures",
      "No traveler you've met has signed here yet.",
    }, innRowTexts(ns))
    -- Clicking a header row does nothing.
    rows[1].button:Click()
    assert.equal("Calmbreeze Inn", ui.inn.title:GetText())
  end)

  it("turns the inn's pages", function()
    local ns = login()
    for i = 1, 8 do
      addTraveler(ns, i, NOW - i * WEEK)
    end
    ns.Sign:Read() -- the book on Calmbreeze Inn's page
    local ui = ns.Book.ui
    assert.is_true(shown(ui.inn.panel))
    assert.equal("1 / 2", ui.right.label:GetText())
    assert.is_false(ui.right.prev:IsEnabled())
    assert.is_true(ui.right.next:IsEnabled())
    assert.same({
      "Your signatures",
      "You haven't signed this guestbook yet.",
      "Travelers' signatures",
      "MiraA / " .. date(ns, NOW - WEEK) .. " / " .. ns.Phrase.render({ 102 }),
      "MiraB / " .. date(ns, NOW - 2 * WEEK) .. " / " .. ns.Phrase.render({ 102 }),
      "MiraC / " .. date(ns, NOW - 3 * WEEK) .. " / " .. ns.Phrase.render({ 102 }),
    }, (function()
      local out = innRowTexts(ns)
      for i = 4, 6 do
        out[i] = out[i]:gsub(" \194\183 ", " / ")
      end
      return out
    end)())
    ui.right.next:Click()
    assert.equal("2 / 2", ui.right.label:GetText())
    assert.is_true(ui.right.prev:IsEnabled())
    assert.is_false(ui.right.next:IsEnabled())
    local texts = innRowTexts(ns)
    assert.equal(6, #texts)
    assert.equal("Travelers' signatures", texts[1])
    assert.is_true(has(texts[2], "MiraD"))
    assert.is_true(has(texts[6], "MiraH"))
    assert.equal(2, ns.Book.nav.innPage)
  end)

  it("shows a stamp in faded dashes before the first signature", function()
    local ns = login()
    ns.Sign:Read()
    local stamp = ns.Book.ui.inn.stamp
    assert.is_false(shown(stamp.solid[1]))
    assert.is_true(shown(stamp.dashes[1]))
    assert.equal(24, #stamp.dashes)
    assert.is_false(shown(stamp.date))
    assert.equal("Not signed yet", ns.Book.ui.inn.count:GetText())
  end)
end)

describe("Book: the Read button", function()
  after_each(function()
    assert.same({}, wow.errors)
    wow.uninstall()
  end)

  it("opens the book on Calmbreeze Inn's page from the gossip", function()
    local ns = login()
    wow.fire("GOSSIP_SHOW")
    assert.equal("Sign the guestbook", ns.Sign.ui.button:GetText())
    assert.equal("Read the guestbook", ns.Sign.ui.read:GetText())
    assert.is_true(shown(ns.Sign.ui.read))
    ns.Sign.ui.read:Click()
    local ui = ns.Book.ui
    assert.is_true(ui.frame:IsShown())
    assert.equal("inns", ns.Book.nav.tab)
    assert.is_false(ui.tabs.inns:IsEnabled())
    assert.is_true(shown(ui.inn.panel))
    assert.equal("Calmbreeze Inn", ui.inn.title:GetText())
    -- The list turned to the page holding the inn.
    assert.is_true(shown(ui.list.panel))
    assert.is_true(shown(ui.list.rows[3].selected))
    wow.fire("GOSSIP_CLOSED")
    assert.is_false(shown(ns.Sign.ui.read))
    assert.is_false(shown(ns.Sign.ui.button))
    assert.is_true(ui.frame:IsShown())
    assert.is_nil(ns.Sign.session)
    assert.same({}, ns.ledger:own())
  end)

  it("hides both buttons at a vendor", function()
    local ns = login()
    state.npc = VENDOR_GUID
    wow.fire("GOSSIP_SHOW")
    assert.is_false(shown(ns.Sign.ui.read))
    assert.is_false(shown(ns.Sign.ui.button))
  end)

  it("keeps a broken book inside the click", function()
    local ns = login()
    wow.fire("GOSSIP_SHOW")
    ns.Book.view.innKey = function() error("raised on purpose") end
    ns.Sign.ui.read:Click()
    ns.Book = nil
    ns.Sign.ui.read:Click()
  end)
end)

describe("Book: the quiet refresh", function()
  after_each(function()
    assert.same({}, wow.errors)
    wow.uninstall()
  end)

  it("draws a traveler's new signature into the open page, quietly", function()
    local ns = login()
    for i = 1, 8 do
      addTraveler(ns, i, NOW - i * WEEK)
    end
    ns.Sign:Read()
    ns.Book.ui.right.next:Click()
    assert.equal("2 / 2", ns.Book.ui.right.label:GetText())
    local n = #wow.chat
    -- Between MiraD and MiraE, so it lands on the open page and pushes MiraH to a third.
    addTraveler(ns, 9, NOW - 4 * WEEK - 86400, "Quill")
    ns.Sync.client.deps.onEntries()
    assert.same({}, chatSince(n))
    assert.is_true(ns.Book.ui.frame:IsShown())
    assert.equal(2, ns.Book.nav.innPage)
    assert.equal("2 / 3", ns.Book.ui.right.label:GetText())
    local texts = innRowTexts(ns)
    assert.is_true(has(texts[2], "MiraD"), texts[2])
    assert.is_true(has(texts[3], "Quill"), texts[3])
    assert.is_true(has(texts[6], "MiraG"), texts[6])
  end)

  it("does nothing while the book is hidden or on the Share page", function()
    local ns = login()
    local builds = 0
    local real = ns.Book.view.build
    ns.Book.view.build = function(...)
      builds = builds + 1
      return real(...)
    end
    ns.Sync.client.deps.onEntries()
    ns.Book:Changed()
    assert.equal(0, builds)
    assert.is_nil(ns.Book.ui)
    wow.slash("/ledger")
    assert.equal(1, builds)
    wow.slash("/ledger")
    ns.Sync.client.deps.onEntries()
    assert.equal(1, builds)
    assert.is_false(ns.Book.ui.frame:IsShown())
    wow.slash("/ledger share")
    local text = ns.Book.ui.share.edit:GetText()
    local exports = 0
    local realExport = ns.Core.ExportString
    ns.Core.ExportString = function(...)
      exports = exports + 1
      return realExport(...)
    end
    builds = 0
    ns.Sync.client.deps.onEntries()
    assert.same({ 0, 0 }, { builds, exports })
    assert.equal(text, ns.Book.ui.share.edit:GetText())
  end)

  it("keeps a failing book out of Sync's errors", function()
    local ns = login()
    ns.Core:ToggleDebug()
    wow.slash("/ledger")
    local errors = ns.Sync.stats.errors
    local n = #wow.chat
    ns.Book.view.build = function() error("raised on purpose") end
    ns.Sync.client.deps.onEntries()
    assert.equal("This page can't be read right now.", ns.Book.ui.left.error:GetText())
    ns.Book.ui = { frame = "broken" }
    ns.Sync.client.deps.onEntries()
    assert.is_true(has(chatSince(n)[1], "book: error in refresh"))
    ns.Book.Changed = function() error("raised on purpose") end
    ns.Sync.client.deps.onEntries()
    ns.Book = nil
    ns.Sync.client.deps.onEntries()
    assert.equal(errors, ns.Sync.stats.errors)
  end)

  it("shows a signature made through Sign while the book is open", function()
    local ns = login()
    wow.fire("GOSSIP_SHOW")
    ns.Sign.ui.read:Click()
    assert.equal("You haven't signed this guestbook yet.", innRowTexts(ns)[2])
    ns.Sign.ui.button:Click()
    ns.Sign.ui.sign:Click()
    assert.equal(1, #ns.ledger:own())
    assert.equal("Signed once", ns.Book.ui.inn.count:GetText())
    assert.is_true(has(innRowTexts(ns)[2], date(ns, NOW)))
    assert.is_true(ns.Book.ui.frame:IsShown())
  end)
end)

describe("Book: the Share page", function()
  after_each(function()
    assert.same({}, wow.errors)
    wow.uninstall()
  end)

  it("shows the export string preselected, unticked, in a box that takes all of it", function()
    local ns = login()
    sign(ns)
    addTraveler(ns, 1, NOW - WEEK)
    wow.slash("/ledger share")
    local ui = ns.Book.ui
    local share = ui.share
    assert.equal("share", ns.Book.nav.tab)
    assert.is_false(ui.tabs.share:IsEnabled())
    assert.is_true(shown(share.panel))
    assert.is_true(shown(ui.shareInfo.panel))
    assert.equal("What the text holds", ui.shareInfo.title:GetText())
    assert.equal("Include travelers' signatures", share.include:GetText())
    assert.is_false(share.check:GetChecked())
    local plain = ns.Core:ExportString()
    assert.is_string(plain)
    assert.equal(plain, share.edit:GetText())
    assert.is_true(share.edit:HasFocus())
    assert.is_true(share.edit.highlighted)
    assert.equal(0, share.edit.cursor)
    assert.equal(0, share.edit:GetMaxLetters())
    assert.equal(0, share.edit.maxBytes)
    assert.is_false(share.edit.multiLine)
    assert.is_false(share.edit.autoFocus)
    assert.is_false(shown(share.fail))
    assert.is_false(shown(ui.left.prev))

    share.check:Click()
    assert.is_true(share.check:GetChecked())
    local opted = ns.Core:ExportString(true)
    assert.equal(opted, share.edit:GetText())
    assert.is_true(#opted > #plain)

    ui.tabs.inns:Click()
    assert.is_false(share.edit:HasFocus())
    assert.is_false(shown(share.panel))
    ui.tabs.share:Click()
    assert.is_false(share.check:GetChecked())
    assert.equal(plain, share.edit:GetText())
    assert.is_true(share.edit:HasFocus())
    share.check:Click()
    wow.slash("/ledger")
    wow.slash("/ledger")
    assert.is_false(share.check:GetChecked())
    assert.equal(plain, share.edit:GetText())
  end)

  it("opts in only for exactly true from the checkbox", function()
    local ns = login()
    wow.slash("/ledger share")
    local check = ns.Book.ui.share.check
    local seen = {}
    ns.Core.ExportString = function(_, opted)
      seen[#seen + 1] = opted
      return "x"
    end
    for _, answer in ipairs({ 1, "true", "1", {}, false }) do
      check.GetChecked = function() return answer end
      check:Click()
    end
    check.GetChecked = function() return nil end
    check:Click()
    check.GetChecked = function() return true end
    check:Click()
    assert.equal(7, #seen)
    for i = 1, 6 do
      assert.is_true(rawequal(seen[i], false), i)
    end
    assert.is_true(rawequal(seen[7], true))
  end)

  it("puts the built string back when anything is typed", function()
    local ns = login()
    wow.slash("/ledger share")
    local edit = ns.Book.ui.share.edit
    local text = edit:GetText()
    edit.highlighted = false
    wow.type(edit, "something else")
    assert.equal(text, edit:GetText())
    assert.is_true(edit.highlighted)
    edit.scripts.OnTextChanged(edit, false)
    assert.equal(text, edit:GetText())
    edit.scripts.OnEscapePressed(edit)
    assert.is_false(edit:HasFocus())
    edit.highlighted = false
    edit.scripts.OnEditFocusGained(edit)
    assert.is_true(edit.highlighted)
  end)

  it("forgets the string when the book closes", function()
    local ns = login()
    wow.slash("/ledger share")
    local edit = ns.Book.ui.share.edit
    assert.is_true(#edit:GetText() > 0)
    wow.slash("/ledger")
    assert.equal("", edit:GetText())
    assert.is_false(edit:HasFocus())
  end)

  it("says it can't share, neutrally, when the export fails", function()
    local ns = login()
    ns.Core:ToggleDebug()
    ns.Core.ExportString = function() return nil, "libs" end
    local n = #wow.chat
    wow.slash("/ledger share")
    local share = ns.Book.ui.share
    assert.equal("", share.edit:GetText())
    assert.is_true(shown(share.fail))
    assert.equal("Your ledger can't be shared right now.", share.fail:GetText())
    assert.is_false(anyString(ns, "libs"))
    local lines = chatSince(n)
    assert.equal(1, #lines)
    assert.is_true(has(lines[1], "book: share libs"))
    -- A reason that isn't one of our codes is logged as error; a raising export too.
    ns.Core.ExportString = function() return nil, "x|y" end
    share.check:Click()
    ns.Core.ExportString = function() error("raised on purpose") end
    share.check:Click()
    lines = chatSince(n)
    assert.is_true(has(lines[2], "book: share error"))
    assert.is_true(has(lines[3], "book: share error"))
    assert.is_nil(record())
    -- Without the debug log, nothing is printed at all.
    ns.Core:ToggleDebug()
    n = #wow.chat
    ns.Book.ui.tabs.inns:Click()
    ns.Book.ui.tabs.share:Click()
    assert.same({}, chatSince(n))
  end)

  it("logs the string's size only", function()
    local ns = login()
    ns.Core:ToggleDebug()
    local n = #wow.chat
    wow.slash("/ledger share")
    local lines = chatSince(n)
    assert.equal(1, #lines)
    assert.is_true(has(lines[1], "book: share " .. #ns.Core:ExportString() .. " bytes"))
  end)

  it("records the share and nudges with what changed since", function()
    local ns = login()
    sign(ns, NOW - 2 * WEEK)
    wow.slash("/ledger share")
    local share = ns.Book.ui.share
    assert.is_false(shown(share.nudge))
    local rec = record()
    assert.same({ v = 1, shared = { own = 1, newest = NOW - 2 * WEEK,
      unlocked = #ns.Cosmetics.unlocked(ns.ledger:own(), "Alliance", ns.ledger:earned()) } },
      rec)
    wow.slash("/ledger")
    wow.slash("/ledger share")
    assert.equal("Nothing new since you last shared.", share.nudge:GetText())
    sign(ns, NOW - WEEK)
    wow.slash("/ledger")
    wow.slash("/ledger share")
    assert.is_true(shown(share.nudge))
    assert.equal("1 new signature since you last shared.", share.nudge:GetText())
    assert.equal(1, record().v)
    assert.equal(2, record().shared.own)
    -- The checkbox rebuilds the string and keeps the nudge as shown.
    share.check:Click()
    assert.equal("1 new signature since you last shared.", share.nudge:GetText())
  end)

  it("writes no mark without a ledger", function()
    local ns = login()
    ns.ledger = nil
    wow.slash("/ledger share")
    assert.equal("Your ledger can't be shared right now.", ns.Book.ui.share.fail:GetText())
    assert.equal("Your ledger isn't open yet. Try again in a moment.",
      ns.Book.ui.notice:GetText())
    assert.is_nil(rawget(_G.InnkeepersLedgerDB.global, "book"))
  end)
end)

describe("Book: quills", function()
  after_each(function()
    assert.same({}, wow.errors)
    wow.uninstall()
  end)

  -- The quill rows by name: { status, Use enabled }.
  local function quillRows(ns)
    local out = {}
    for _, row in ipairs(ns.Book.ui.quills.rows) do
      if shown(row.name) then
        out[row.name:GetText()] = { row.status:GetText(), row.use:IsEnabled() }
      end
    end
    return out
  end

  it("uses an unlocked quill and draws its flourish under own signatures", function()
    local ns = login()
    sign(ns)
    -- Nothing place-based unlocks from the shipped (unmarked) data: no quill but the plain.
    wow.slash("/ledger")
    ns.Book.ui.tabs.cosmetics:Click()
    assert.same({ "Sign every inn on one continent \194\183 0 of 1", false },
      quillRows(ns)["Cartographer's quill"])
    -- With the Cartographer's quill (1003) recorded, as under older data, it can be used.
    recordPlaceUnlocks(ns)
    ns.Book:Changed()
    local rows = quillRows(ns)
    assert.same({ "In use", false }, rows["Plain quill"])
    assert.equal(true, rows["Cartographer's quill"][2])
    assert.same({ "Sign 10 inns \194\183 1 of 10", false }, rows["Traveler's quill"])
    local use
    for _, row in ipairs(ns.Book.ui.quills.rows) do
      if row.id == 1003 then
        use = row.use
      end
    end
    use:Click()
    assert.same({ v = 1, quill = 1003 }, record())
    rows = quillRows(ns)
    assert.same({ "In use", false }, rows["Cartographer's quill"])
    assert.same({ "Always yours", true }, rows["Plain quill"])
    -- Seals: earned, with their dates.
    local seals = {}
    for _, row in ipairs(ns.Book.ui.seals.rows) do
      if shown(row.name) then
        seals[#seals + 1] = row.name:GetText()
      end
    end
    assert.same({ "Wayfarer's seal", "Innkeeper's seal", "Zephras Isle seal" }, seals)
    assert.equal("Choose a seal when you sign a guestbook.", ns.Book.ui.seals.hint:GetText())

    ns.Book:OpenInn(CALM)
    assert.equal(ns.BookView.FLOURISHES[3], ns.Book.ui.inn.rows[2].flourish:GetText())
    assert.is_true(shown(ns.Book.ui.inn.rows[2].flourish))

    -- Back to the plain quill.
    ns.Book.ui.tabs.cosmetics:Click()
    for _, row in ipairs(ns.Book.ui.quills.rows) do
      if row.id == 0 then
        row.use:Click()
      end
    end
    assert.same({ v = 1 }, record())
    ns.Book:OpenInn(CALM)
    assert.is_false(shown(ns.Book.ui.inn.rows[2].flourish))
  end)

  it("draws with the plain quill for a saved quill not unlocked, and leaves it saved", function()
    local ns = login({ db = { global = { book = { [GUID] = { v = 1, quill = 1001 } } } } })
    sign(ns)
    wow.slash("/ledger")
    ns.Book.ui.tabs.cosmetics:Click()
    assert.same({ "In use", false }, quillRows(ns)["Plain quill"])
    ns.Book:SetQuill(1001) -- not unlocked: refused
    ns.Book:SetQuill(2)    -- a seal: refused
    assert.same({ v = 1, quill = 1001 }, record())
    ns.Book:OpenInn(CALM)
    assert.is_false(shown(ns.Book.ui.inn.rows[2].flourish))
  end)

  it("never writes a damaged or newer record", function()
    local cases = {
      { book = "x" },
      { book = { [GUID] = { v = 2, quill = 1003 } } },
      { book = { [GUID] = "junk" } },
    }
    for i, global in ipairs(cases) do
      local before = deepcopy(global)
      local ns = login({ db = { global = global } })
      sign(ns)
      recordPlaceUnlocks(ns)
      wow.slash("/ledger")
      ns.Book.ui.tabs.cosmetics:Click()
      for _, row in ipairs(ns.Book.ui.quills.rows) do
        if shown(row.use) then
          assert.is_false(row.use:IsEnabled(), i)
        end
      end
      ns.Book:SetQuill(1003)
      wow.slash("/ledger share")
      assert.is_true(#ns.Book.ui.share.edit:GetText() > 0)
      assert.same(before.book, _G.InnkeepersLedgerDB.global.book, i)
      assert.same({}, wow.errors)
      wow.uninstall()
    end
  end)

  it("works with no saved global table", function()
    local ns = login()
    sign(ns)
    recordPlaceUnlocks(ns)
    ns.Core.db.global = 5
    wow.slash("/ledger")
    ns.Book.ui.tabs.cosmetics:Click()
    for _, row in ipairs(ns.Book.ui.quills.rows) do
      if shown(row.use) then
        assert.is_false(row.use:IsEnabled())
      end
    end
    ns.Book:SetQuill(1003)
    wow.slash("/ledger share")
    assert.equal(5, ns.Core.db.global)
  end)

  it("leaves other characters' records alone when it writes its own", function()
    local OTHER = "Player-1-0000BEEF"
    local other = { v = 1, quill = 1001, shared = { own = 3, newest = NOW - WEEK,
      unlocked = 2 } }
    local ns = login({ db = { global = { book = { [OTHER] = deepcopy(other),
      ["Player-1-0000F00D"] = "damaged" } } } })
    sign(ns)
    recordPlaceUnlocks(ns)
    wow.slash("/ledger share")
    assert.is_table(record().shared)
    ns.Book:SetQuill(1003)
    assert.equal(1003, record().quill)
    assert.is_table(record().shared)
    local book = _G.InnkeepersLedgerDB.global.book
    assert.same(other, book[OTHER])
    assert.equal("damaged", book["Player-1-0000F00D"])
  end)

  it("replaces a broken v1 record whole on the next write", function()
    local ns = login({ db = { global = { book = { [GUID] = { quill = "x", other = 1 } } } } })
    sign(ns)
    recordPlaceUnlocks(ns)
    wow.slash("/ledger")
    ns.Book:SetQuill(1003)
    assert.same({ v = 1, quill = 1003 }, record())
  end)
end)

describe("Book: the Collection tab", function()
  after_each(function()
    assert.same({}, wow.errors)
    wow.uninstall()
  end)

  it("shows the passport and opens an inn from its stamp", function()
    local ns = login()
    sign(ns)
    addTraveler(ns, 1, NOW - WEEK)
    wow.slash("/ledger")
    ns.Book.ui.tabs.collection:Click()
    local ui = ns.Book.ui
    -- The shipped data marks no place complete: a + after each total, no zone completed.
    assert.equal("1 of 1+ inns signed", ui.summary.signed:GetText())
    assert.equal("Zones completed: 0 of 1", ui.summary.zones:GetText())
    assert.equal("1 of 1+", ui.summary.bars[1].text:GetText())
    assert.equal("Signatures: 1", ui.summary.signatures:GetText())
    assert.equal("Travelers met: 1", ui.summary.travelers:GetText())
    assert.equal("Azeroth", ui.summary.bars[1].name:GetText())
    assert.equal(356, ui.summary.bars[1].fill.width)
    assert.is_false(shown(ui.summary.bars[2].name))
    assert.equal("Azeroth", ui.stamps.title:GetText())
    local cell = ui.stamps.cells[1]
    assert.equal("Calmbreeze Inn", cell.name:GetText())
    assert.equal(date(ns, NOW - 3600), cell.date:GetText())
    assert.is_false(shown(ui.stamps.cells[2].frame))
    cell.frame:Click()
    assert.equal("inns", ns.Book.nav.tab)
    assert.is_true(shown(ui.inn.panel))
    assert.equal("Calmbreeze Inn", ui.inn.title:GetText())
  end)
end)

describe("Book: fallbacks", function()
  after_each(function()
    assert.same({}, wow.errors)
    wow.uninstall()
  end)

  it("uses the large game font for titles without the quest title font", function()
    local ns = login()
    _G.QuestTitleFont = nil
    wow.slash("/ledger")
    assert.equal(_G.GameFontNormalLarge, ns.Book.ui.title.title.fontObject)
    wow.uninstall()
    ns = login()
    _G.QuestTitleFont, _G.GameFontNormalLarge, _G.GameFontNormal = nil, nil, nil
    wow.slash("/ledger")
    assert.is_nil(ns.Book.ui.title.title.fontObject)
    assert.equal("The ledger of Traveler", ns.Book.ui.title.title:GetText())
  end)

  it("writes dates in the client's time zone, and in UTC when it can't say", function()
    -- 02:00 UTC on 15 January is still the evening of the 14th at UTC-5.
    local t = NOW - 6 * 3600
    local west = clock(-5 * 3600)
    local ns = login({ overrides = { date = west.date, time = west.time } })
    sign(ns, t)
    ns.Sign:Read()
    assert.equal("14 January 2027", ns.Book.ui.inn.stamp.date:GetText())
    _G.date = nil
    ns.Book:Changed()
    assert.equal("15 January 2027", ns.Book.ui.inn.stamp.date:GetText())
    _G.date = west.date
    _G.time = function() error("raised on purpose") end
    ns.Book:Changed()
    assert.equal("15 January 2027", ns.Book.ui.inn.stamp.date:GetText())
    _G.time = west.time
    _G.GetServerTime = function() return secret() end
    _G.issecretvalue = function(v) return type(v) == "userdata" end
    ns.Book:Changed()
    assert.equal("15 January 2027", ns.Book.ui.inn.stamp.date:GetText())
  end)

  it("counts every inn when the faction is hidden or raising", function()
    local ns = login()
    local hiddenFaction = secret()
    _G.UnitFactionGroup = function() return hiddenFaction end
    _G.issecretvalue = function(v) return rawequal(v, hiddenFaction) end
    sign(ns)
    wow.slash("/ledger")
    assert.equal("signed 1 of 1+", ns.Book.ui.list.rows[2].sub:GetText())
    _G.UnitFactionGroup = function() error("raised on purpose") end
    ns.Book:Changed()
    assert.equal("signed 1 of 1+", ns.Book.ui.list.rows[2].sub:GetText())
  end)

  it("titles the book without a name it can read", function()
    local ns = login()
    ns.Core.PlayerName = function() error("raised on purpose") end
    wow.slash("/ledger")
    assert.equal("Your ledger", ns.Book.ui.title.title:GetText())
  end)

  it("says the ledger isn't open, and shows the places unsigned", function()
    local ns = login()
    ns.ledger = nil
    wow.slash("/ledger")
    local ui = ns.Book.ui
    assert.is_true(shown(ui.notice))
    assert.equal("Your ledger isn't open yet. Try again in a moment.", ui.notice:GetText())
    assert.same({ 0.87, 0.80, 0.64, 1 }, ui.notice.textColor)
    assert.is_true(shown(ui.title.panel))
    ui.left.next:Click()
    assert.equal("signed 0 of 1+", ui.list.rows[2].sub:GetText())
    ui.tabs.cosmetics:Click()
    for _, row in ipairs(ui.quills.rows) do
      if shown(row.use) then
        assert.is_false(row.use:IsEnabled())
      end
    end
  end)

  it("shows a read-only ledger with its notice", function()
    local ns = login({ db = { global = { ledgers = { [GUID] = { schema = 99, me = {},
      own = { { inn = CALM, t = NOW - 3600, phrase = { 101 } } }, travelers = {}, earned = {},
      quarantine = {} } } } } })
    assert.is_true(ns.ledger.readOnly)
    ns.Sign:Read()
    assert.equal(ns.BookView.TEXT.readOnly, ns.Book.ui.notice:GetText())
    assert.equal("Signed once", ns.Book.ui.inn.count:GetText())
  end)
end)

describe("Book: errors stay inside", function()
  after_each(function()
    assert.same({}, wow.errors)
    wow.uninstall()
  end)

  it("shows a neutral line on both pages when a page can't be built", function()
    local ns = login()
    ns.Core:ToggleDebug()
    ns.Book.view.build = function() error("raised on purpose") end
    local n = #wow.chat
    wow.slash("/ledger")
    local ui = ns.Book.ui
    assert.is_true(ui.frame:IsShown())
    for _, side in ipairs({ ui.left, ui.right }) do
      assert.is_true(shown(side.error))
      assert.equal("This page can't be read right now.", side.error:GetText())
      assert.is_false(shown(side.prev))
    end
    for _, kind in ipairs({ "title", "list", "help", "inn" }) do
      assert.is_false(shown(ui[kind].panel))
    end
    assert.same({}, chatSince(n))
    ns.Book.view.build = function() return "x" end
    ns.Book:Changed()
    assert.is_true(shown(ui.left.error))
  end)

  it("says the ledger can't be opened when the view failed to build", function()
    local ns = login({ beforeBook = function(ns_) ns_.Collection.atlas = nil end })
    assert.is_nil(ns.Book.view)
    local n = #wow.chat
    wow.slash("/ledger")
    local lines = chatSince(n)
    assert.equal(1, #lines)
    assert.is_true(has(lines[1], "The ledger can't be opened right now."))
    assert.is_nil(ns.Book.ui)
    n = #wow.chat
    wow.slash("/ledger share")
    ns.Book:OpenInn(CALM)
    assert.equal(2, #chatSince(n))
    ns.Book:Changed()
    ns.Book:ShowTab("inns")
    ns.Book:ShowInn(CALM)
    ns.Book:ShowStamp(CALM)
    ns.Book:SetQuill(1003)
    assert.equal(2, #chatSince(n))
  end)

  it("keeps no half-built book when building raises, and builds again next time", function()
    local ns = login()
    ns.Core:ToggleDebug()
    local real = _G.CreateFrame
    _G.CreateFrame = function(kind, ...)
      if kind == "EditBox" then
        error("raised on purpose")
      end
      return real(kind, ...)
    end
    local n = #wow.chat
    wow.slash("/ledger")
    assert.is_nil(ns.Book.ui)
    assert.same({}, _G.UISpecialFrames)
    assert.is_false(_G.InnkeepersLedgerBook:IsShown())
    local lines = chatSince(n)
    assert.equal(1, #lines)
    assert.is_true(has(lines[1], "book: error in toggle"))
    ns.Book:Changed()
    ns.Book:ShowTab("share")
    ns.Book:SetQuill(1003)
    assert.is_nil(ns.Book.ui)

    _G.CreateFrame = real
    wow.slash("/ledger")
    assert.is_table(ns.Book.ui)
    assert.is_true(ns.Book.ui.frame:IsShown())
    assert.equal(_G.InnkeepersLedgerBook, ns.Book.ui.frame)
    assert.same({ "InnkeepersLedgerBook" }, _G.UISpecialFrames)
  end)

  it("logs an error in a click and nothing else", function()
    local ns = login()
    ns.Core:ToggleDebug()
    wow.slash("/ledger")
    local n = #wow.chat
    ns.Book.view.innKey = function() error("raised on purpose") end
    ns.Book:OpenInn(CALM)
    ns.Book.nav = "broken"
    ns.Book.ui.tabs.share:Click()
    ns.Book:ShowInn(CALM)
    local lines = chatSince(n)
    assert.equal(3, #lines)
    assert.is_true(has(lines[1], "book: error in open"))
    assert.is_true(has(lines[2], "book: error in tab"))
    assert.is_true(has(lines[3], "book: error in inn"))
  end)
end)
