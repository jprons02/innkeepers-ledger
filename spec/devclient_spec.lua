-- The dev harness (#139): ILDev runs a tour over a small fake frame tree, and read.lua
-- reports a saved run. Neither ships; these cases keep the harness honest between client
-- sessions (the real check is a tour in the client).
local HERE = "scripts/devclient/"

-- A tour file as deploy.sh wraps it into Request.lua.
local function tour(name)
  return assert(loadfile(HERE .. "tours/" .. name .. ".lua"))()
end

local function region(kind, parent, rect, text)
  local r = { kind = kind, parent = parent, rect = rect, text = text, shown = true,
    kids = {}, regs = {}, enabled = true, clicks = 0 }
  function r.GetObjectType(self) return self.kind end
  function r.GetName(self) return self.name end
  function r.IsShown(self) return self.shown end
  function r.IsVisible(self)
    local p = self
    while p do
      if not p.shown then
        return false
      end
      p = p.parent
    end
    return true
  end
  function r.GetRect(self)
    if self.rect then
      return unpack(self.rect)
    end
  end
  function r.GetEffectiveScale() return 1 end
  function r.GetAlpha() return 1 end
  function r.GetNumPoints() return 1 end
  function r.GetPoint(self) return "TOPLEFT", self.parent, "TOPLEFT", 0, 0 end
  function r.GetParent(self) return self.parent end
  function r.GetText(self) return self.text end
  function r.GetTop(self) return self.rect[2] + self.rect[4] end
  function r.GetLeft(self) return self.rect[1] end
  function r.IsEnabled(self) return self.enabled end
  function r.Click(self)
    self.clicks = self.clicks + 1
    if self.onClick then
      self.onClick(self)
    end
  end
  function r.Hide(self) self.shown = false end
  function r.Show(self) self.shown = true end
  if kind == "FontString" or kind == "Texture" then
    function r.GetDrawLayer() return "OVERLAY", 0 end
    if parent then
      table.insert(parent.regs, r)
    end
  else
    function r.GetChildren(self) return unpack(self.kids) end
    function r.GetRegions(self) return unpack(self.regs) end
    function r.GetFrameStrata() return "HIGH" end
    function r.GetFrameLevel() return 2 end
    if parent then
      table.insert(parent.kids, r)
    end
  end
  if kind == "FontString" then
    function r.GetStringWidth() return 50 end
    function r.GetStringHeight() return 12 end
    function r.IsTruncated(self) return self.truncated end
    function r.GetFont() return "Fonts\\FRIZQT__.TTF", 12 end
    function r.GetTextColor() return 0.2, 0.1, 0.1, 1 end
  elseif kind == "Texture" then
    function r.GetTexture() return "Interface\\Spellbook\\Spellbook-Page-1" end
    function r.GetTexCoord() return 1, 0, 1, 1, 0, 0, 0, 1 end
    function r.GetVertexColor() return 1, 1, 1, 1 end
  end
  return r
end

local NAMES = { "CreateFrame", "C_Timer", "C_UI", "GetTime", "time", "date", "Screenshot",
  "GetCVar", "SetCVar", "GetPhysicalScreenSize", "UIParent", "DEFAULT_CHAT_FRAME",
  "GetBuildInfo", "geterrorhandler", "seterrorhandler", "SlashCmdList", "IsResting",
  "UnitIsAFK", "InCombatLockdown", "ReloadUI", "ILDevDB", "ILDevRequest", "SLASH_ILDEV1",
  "InnkeepersLedgerBook", "GossipFrame", "SLASH_ACECONSOLE_LEDGER1" }

-- Installs a fake client in _G; `w.pump()` runs timers in due order.
local function install(request, db)
  local w = { saved = {}, timers = {}, now = 0, reloads = 0, shots = 0, chat = {},
    cvars = { screenshotQuality = "3" }, resting = true, afk = true }
  for _, n in ipairs(NAMES) do
    w.saved[n] = rawget(_G, n)
  end
  local ui = region("Frame", nil, { 0, 0, 1024, 768 })
  function ui.GetWidth() return 1024 end
  function ui.GetHeight() return 768 end
  _G.UIParent = ui
  local book = region("Frame", ui, { 100, 100, 800, 500 })
  book.name = "InnkeepersLedgerBook"
  book.shown = false
  _G.InnkeepersLedgerBook = book
  local function tab(text, x)
    local b = region("Button", book, { x, 70, 120, 24 }, text)
    b.onClick = function() w.tab = text end
    return b
  end
  w.tabs = { tab("Inns", 124), tab("Collection", 248), tab("Cosmetics", 372), tab("Share", 496) }
  local left = region("Frame", book, { 116, 110, 404, 480 })
  w.leftNext = region("Button", left, { 480, 120, 26, 22 }, "\226\128\186")
  w.leftNext.onClick = function(b) b.enabled = false end -- two pages
  w.rightNext = region("Button", region("Frame", book, { 480, 110, 404, 480 }),
    { 850, 120, 26, 22 }, "\226\128\186")
  w.rightNext.enabled = false
  w.label = region("FontString", left, { 260, 120, 120, 12 }, "1 / 2")
  w.label.truncated = true
  region("Texture", left, { 104, 110, 472, 480 })

  local gossip = region("Frame", ui, { 20, 200, 340, 420 })
  gossip.shown = false
  _G.GossipFrame = gossip
  w.signButton = region("Button", gossip, { 30, 180, 160, 24 }, "Sign the guestbook")
  w.home = region("Button", gossip, { 30, 400, 300, 20 }, "Make this inn your home.")
  w.commit = region("Button", gossip, { 30, 220, 120, 24 }, "Sign")
  w.book, w.gossip = book, gossip

  _G.SlashCmdList = { ACECONSOLE_LEDGER = function() book:Show() end }
  _G.SLASH_ACECONSOLE_LEDGER1 = "/ledger"
  _G.CreateFrame = function()
    local f = {}
    function f.RegisterEvent() end
    function f.SetScript(_, _, fn) w.onEvent = fn end
    return f
  end
  _G.C_Timer = { After = function(sec, fn)
    table.insert(w.timers, { at = w.now + sec, fn = fn, seq = #w.timers })
  end }
  _G.C_UI = { Reload = function() w.reloads = w.reloads + 1 end }
  _G.ReloadUI = _G.C_UI.Reload
  _G.GetTime = function() return w.now end
  _G.time = function() return 1791633600 + math.floor(w.now) end
  _G.date = function() return "101026_120000" end
  _G.Screenshot = function()
    w.shots = w.shots + 1
    _G.C_Timer.After(0.1, function() w.onEvent(nil, "SCREENSHOT_SUCCEEDED") end)
  end
  _G.GetCVar = function(k) return w.cvars[k] end
  _G.SetCVar = function(k, v) w.cvars[k] = v end
  _G.GetPhysicalScreenSize = function() return 2048, 1536 end
  _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) table.insert(w.chat, m) end }
  _G.GetBuildInfo = function() return "1.60.1", "70124", "Sep 29 2026", 16001 end
  local handler = function() end
  _G.geterrorhandler = function() return handler end
  _G.seterrorhandler = function(fn) handler = fn end
  _G.IsResting = function() return w.resting end
  _G.UnitIsAFK = function() return w.afk end
  _G.InCombatLockdown = function() return false end
  _G.ILDevDB = db
  _G.ILDevRequest = request

  function w.pump(limit)
    for _ = 1, limit or 500 do
      if #w.timers == 0 then
        return
      end
      table.sort(w.timers, function(a, b)
        if a.at ~= b.at then
          return a.at < b.at
        end
        return a.seq < b.seq
      end)
      local t = table.remove(w.timers, 1)
      w.now = math.max(w.now, t.at)
      t.fn()
    end
  end
  function w.fire(...)
    w.onEvent(nil, ...)
  end
  function w.uninstall()
    for _, n in ipairs(NAMES) do
      rawset(_G, n, w.saved[n])
    end
  end
  assert(loadfile(HERE .. "ILDev/ILDev.lua"))()
  w.fire("ADDON_LOADED", "ILDev")
  return w
end

local function stepsOf(db)
  local out = {}
  for _, s in ipairs(db.run.steps) do
    out[#out + 1] = (s.ok and "ok " or "FAIL ") .. s.op
      .. (s.note and (" (" .. s.note .. ")") or "")
  end
  return out
end

local function has(list, pattern)
  for _, v in ipairs(list) do
    if v:find(pattern) then
      return true
    end
  end
  return false
end

describe("ILDev", function()
  local w
  after_each(function()
    if w then
      w.uninstall()
      w = nil
    end
  end)

  it("tours the book at login, once per request, then reloads to save", function()
    w = install({ id = "r1", tours = { tour("book"), tour("composer") } })
    w.fire("PLAYER_LOGIN")
    w.pump()
    local db = _G.ILDevDB
    assert.equal("r1", db.lastId)
    local steps = stepsOf(db)
    -- The book: the left page turns once (then its button is disabled), the right one
    -- never; every tab is clicked; the composer is skipped (no gossip window).
    assert.is_true(has(steps, "^ok shot inns%-left%-1$"))
    assert.is_true(has(steps, "^ok shot inns%-left%-2$"))
    assert.is_false(has(steps, "inns%-left%-3"))
    assert.is_true(has(steps, "^ok pages inns%-right%- stop %(disabled%)"))
    assert.is_true(has(steps, "^ok click InnkeepersLedgerBook \"Share\""))
    assert.is_true(has(steps, "^ok shot share$"))
    assert.is_true(has(steps, "^FAIL tour composer %(skipped: GossipFrame not shown%)"))
    assert.is_table(db.run.dumps.share)
    assert.equal("InnkeepersLedgerBook", db.run.dumps.share.name)
    assert.equal("Inns", w.tab)
    assert.is_false(w.book.shown)
    assert.equal(#db.run.shots, w.shots)
    assert.equal("3", w.cvars.screenshotQuality)
    assert.equal(1, w.reloads)
    assert.is_number(db.run.finished)

    -- The same request after the reload doesn't run again.
    w.uninstall()
    w = install({ id = "r1", tours = { tour("book") } }, db)
    w.fire("PLAYER_LOGIN")
    w.pump()
    assert.equal(0, w.shots)
  end)

  it("tells whether its last automatic reload happened", function()
    w = install({ id = "r0", tours = {} }, { autoReload = { tried = 1791633600 - 5 } })
    assert.is_true(_G.ILDevDB.reloadWorked)
    w.uninstall()
    w = install({ id = "r0", tours = {} }, { autoReload = { tried = 1791633600 - 100 } })
    assert.is_false(_G.ILDevDB.reloadWorked)
  end)

  it("crops to the frame and everything shown under it, in physical pixels", function()
    w = install({ id = "r2", tours = { { name = "t", steps = {
      { "slash", "/ledger", "" }, { "shot", "book", "InnkeepersLedgerBook" } } } } })
    w.fire("PLAYER_LOGIN")
    w.pump()
    local crop = _G.ILDevDB.run.shots[1].crop
    -- The book is 100,100 800x500; its tabs hang 30 below it. Twice the UI's size, 8 px pad.
    assert.same({ x = 192, y = 1536 - 1200 - 8, w = 1616, h = 1076, screenW = 2048,
      screenH = 1536 }, crop)
  end)

  it("never clicks the commit button, nor anything in the gossip window but its own", function()
    w = install({ id = "r3", tours = { { name = "g", need = "GossipFrame", steps = {
      { "click", "GossipFrame", "Sign" },
      { "click", "GossipFrame", "Make this inn your home." },
      { "click", "InnkeepersLedgerBook", "Sign" },
      { "click", "GossipFrame", "Sign the guestbook" } } } } })
    w.gossip:Show()
    w.fire("PLAYER_LOGIN")
    w.pump()
    local steps = stepsOf(_G.ILDevDB)
    assert.is_true(has(steps, "FAIL click GossipFrame \"Sign\" 1 %(refused"))
    assert.is_true(has(steps, "FAIL click GossipFrame \"Make this inn your home.\" 1 %(refused"))
    assert.is_true(has(steps, "FAIL click InnkeepersLedgerBook \"Sign\" 1 %(refused"))
    assert.equal(0, w.commit.clicks)
    assert.equal(0, w.home.clicks)
    assert.equal(1, w.signButton.clicks)
  end)

  it("guards the composer's commit button by its current label", function()
    -- ILDev refuses the text "Sign"; if SignFlow relabels the button, this must follow.
    local src = assert(io.open("SignFlow.lua", "rb")):read("*a")
    assert.equal("Sign", src:match('\n  sign = "([^"]*)"'))
    local ildev = assert(io.open(HERE .. "ILDev/ILDev.lua", "rb")):read("*a")
    assert.truthy(ildev:find('local NEVER = { ["Sign"] = true }', 1, true))
  end)

  it("runs only /ledger, and clicks and hides only in the book and the gossip window", function()
    w = install({ id = "r6", tours = { { name = "t", steps = {
      { "slash", "/run", "x" },
      { "slash", "/LEDGER", "" },
      { "click", "GameMenuFrame", "Logout" },
      { "click", "InnkeepersLedgerBook" },
      { "click", "InnkeepersLedgerBook", "" },
      { "hide", "UIParent" } } } } })
    _G.SlashCmdList.SCRIPT = function() w.ran = true end
    _G.SLASH_SCRIPT1 = "/run"
    w.fire("PLAYER_LOGIN")
    w.pump()
    _G.SlashCmdList.SCRIPT, _G.SLASH_SCRIPT1 = nil, nil
    local steps = stepsOf(_G.ILDevDB)
    assert.is_nil(w.ran)
    assert.is_true(has(steps, "FAIL slash /run %(refused"))
    assert.is_true(has(steps, "^ok slash /LEDGER"))
    assert.is_true(w.book.shown)
    assert.is_true(has(steps, "FAIL click GameMenuFrame \"Logout\" 1 %(refused"))
    local refused = "1 %(refused: no button text"
    assert.is_true(has(steps, "FAIL click InnkeepersLedgerBook \"nil\" " .. refused))
    assert.is_true(has(steps, "FAIL click InnkeepersLedgerBook \"\" " .. refused))
    assert.is_true(has(steps, "FAIL hide UIParent"))
    assert.is_true(_G.UIParent.shown)
  end)

  it("watch mode reloads only while resting and away, and is switched on in game", function()
    w = install({ id = "r4", watch = 30, tours = {} })
    _G.ILDevDB.lastId = "r4"
    w.fire("PLAYER_LOGIN")
    w.pump()
    assert.equal(0, w.reloads) -- not switched on
    _G.SlashCmdList.ILDEV("watch")
    w.afk = false
    w.pump(3)
    assert.equal(0, w.reloads) -- at the keyboard
    w.afk = true
    w.pump(1)
    assert.equal(1, w.reloads)
    _G.SlashCmdList.ILDEV("watch off")
    w.pump()
    assert.is_nil(_G.ILDevDB.watchUntil)
    assert.equal(1, w.reloads)
  end)

  it("keeps one watch chain and never reloads faster than every 30 s", function()
    w = install({ id = "r7", watch = 0, tours = {} })
    _G.ILDevDB.lastId = "r7"
    w.fire("PLAYER_LOGIN")
    _G.SlashCmdList.ILDEV("watch")
    _G.SlashCmdList.ILDEV("watch")
    _G.SlashCmdList.ILDEV("watch")
    assert.equal(3, #w.timers)
    w.pump(3)
    assert.equal(1, w.reloads) -- the two older chains stopped
    assert.equal(30, w.now)
  end)

  it("carries on past bad steps, and a raising step still ends the run", function()
    w = install({ id = "r5", tours = { { name = "t", steps = {
      { "nosuch" }, "junk", { "click", "NoSuchFrame", "x" },
      { "dump", nil, "InnkeepersLedgerBook" }, -- raises: a nil key
      { "dump", "d", "InnkeepersLedgerBook" } } } } })
    w.fire("PLAYER_LOGIN")
    w.pump()
    local db = _G.ILDevDB
    local steps = stepsOf(db)
    assert.is_true(has(steps, "FAIL unknown step nosuch"))
    assert.is_true(has(steps, "FAIL step 3 %(not a table%)"))
    assert.is_true(has(steps, "FAIL click NoSuchFrame \"x\" 1 %(refused: not an allowed frame%)"))
    assert.is_true(has(steps, "FAIL step dump raised"))
    assert.is_true(has(steps, "^ok dump d"))
    assert.is_number(db.run.finished)
    assert.equal("3", w.cvars.screenshotQuality)
    assert.equal(1, w.reloads)
  end)

  it("ends the run when a step raises from a timer, and isn't stuck afterwards", function()
    w = install({ id = "r8", tours = { { name = "t", steps = {
      { "slash", "/ledger", "" }, { "shot", "a", "InnkeepersLedgerBook" } } } } })
    local real = _G.date
    _G.date = function() error("clock") end -- raises inside the screenshot's callback
    w.fire("PLAYER_LOGIN")
    w.pump()
    _G.date = real
    local db = _G.ILDevDB
    assert.is_number(db.run.finished)
    assert.equal("3", w.cvars.screenshotQuality)
    assert.equal(1, w.reloads)
    _G.SlashCmdList.ILDEV("run")
    w.pump()
    assert.equal(2, w.shots) -- a second run started: not stuck "already running"
  end)

  it("refuses a malformed request without getting stuck", function()
    w = install({ id = "r9", tours = { { name = "t", steps = 5 } } })
    w.fire("PLAYER_LOGIN")
    w.pump()
    assert.is_nil(_G.ILDevDB.run)
    assert.is_true(has(w.chat, "malformed"))
  end)
end)

describe("read.lua", function()
  it("reports a run: failed steps, the crop list, truncated and stray text", function()
    local dir = (os.getenv("TEMP") or os.getenv("TMPDIR") or "/tmp"):gsub("\\", "/")
    local sv = dir .. "/ildev_spec_sv.lua"
    local shot = dir .. "/WoWScrnShot_101026_120001.jpg"
    local f = assert(io.open(sv, "wb"))
    f:write([[
ILDevDB = { lastId = "r9", reloadWorked = false, run = {
  id = "r9", started = 1791633600, finished = 1791633630,
  client = { build = "1.60.1", interface = 16001, screen = { 2048, 1536 }, ui = { 1024, 768 } },
  steps = { { t = 0.5, op = "shot inns", ok = true }, { t = 1, op = "click x", ok = false,
    note = "no frame" } },
  errors = { "Book.lua:1: boom" },
  shots = { { label = "inns", ok = true, stamp = "101026_120000",
    crop = { x = 192, y = 328, w = 1616, h = 1076, screenW = 2048, screenH = 1536 } } },
  dumps = { inns = { k = "Frame", name = "InnkeepersLedgerBook", vis = true,
    r = { 100, 100, 800, 500 }, kids = {
      { k = "FontString", vis = true, r = { 260, 120, 120, 12 }, text = "1 / 2", trunc = true },
      { k = "FontString", vis = true, r = { 950, 120, 120, 12 }, text = "stray" },
      { k = "FontString", vis = false, r = { 950, 120, 120, 12 }, text = "hidden" } } } },
} }
]])
    f:close()
    -- One second off the recorded stamp, as a slow write can be.
    assert(io.open(shot, "wb")):close()
    local printed = {}
    local env = setmetatable({ arg = { sv, dir, dir },
      print = function(s) printed[#printed + 1] = s end }, { __index = _G })
    local chunk = assert(loadfile(HERE .. "read.lua"))
    setfenv(chunk, env)
    chunk()
    local text = table.concat(printed, "\n")
    os.remove(sv)
    os.remove(shot)
    local crops = assert(io.open(dir .. "/crops.txt", "rb")):read("*a")
    os.remove(dir .. "/crops.txt")
    os.remove(dir .. "/inns.txt")
    assert.truthy(text:find("FAIL click x  (no frame)", 1, true))
    assert.truthy(text:find("Book.lua:1: boom", 1, true))
    assert.truthy(text:find("text truncated \"1 / 2\"", 1, true))
    assert.truthy(text:find("outside InnkeepersLedgerBook: 950,120 120x12", 1, true))
    assert.is_nil(text:find("hidden", 1, true))
    assert.equal(shot .. "|" .. dir .. "/01-inns.png|192|328|1616|1076|2048|1536\n", crops)
  end)
end)
