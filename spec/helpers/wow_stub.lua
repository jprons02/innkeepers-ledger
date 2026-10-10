-- A minimal stand-in for the WoW API so glue (and the embedded libraries) can run under
-- busted. Tests override single functions per case:
--
--   local wow = require("helpers.wow_stub")
--   before_each(function() wow.install({ IsResting = function() return true end }) end)
--   after_each(wow.uninstall)
--
-- Keep it small: add a name when a test needs it, not before.
local M = {}

local lua_xpcall = xpcall

local saved      -- globals as they were before install (name -> value)
local frames     -- every frame CreateFrame has made since install

M.SCREEN_W, M.SCREEN_H = 1024, 768

-- What frames, font strings and textures share: a shown flag, points, a size and text.
-- SetPoint replaces a point already set with the same name, as the client does;
-- SetAllPoints(rel) sets TOPLEFT and BOTTOMRIGHT to `rel` (nil: the parent).
local function region(kind)
  local r = { kind = kind, shown = true, points = {}, text = nil }
  function r:Show() self.shown = true end
  function r:Hide() self.shown = false end
  function r:IsShown() return self.shown end
  function r:SetPoint(point, ...)
    for i, p in ipairs(self.points) do
      if p[1] == point then
        self.points[i] = { point, ... }
        return
      end
    end
    self.points[#self.points + 1] = { point, ... }
  end
  function r:ClearAllPoints() self.points = {} end
  function r:SetAllPoints(rel)
    self.points = { { "TOPLEFT", rel, "TOPLEFT", 0, 0 },
      { "BOTTOMRIGHT", rel, "BOTTOMRIGHT", 0, 0 } }
  end
  function r:SetSize(w, h) self.width, self.height = w, h end
  function r:SetWidth(w) self.width = w end
  function r:SetHeight(h) self.height = h end
  function r:SetText(text) self.text = text end
  function r:GetText() return self.text end
  function r:SetAlpha(a) self.alpha = a end
  return r
end

local function new_font_string(layer, template)
  local fs = region("FontString")
  fs.layer, fs.template = layer, template
  function fs:SetJustifyH(j) self.justifyH = j end
  function fs:SetJustifyV(j) self.justifyV = j end
  function fs:SetWordWrap(on) self.wordWrap = on end
  function fs:SetFontObject(obj) self.fontObject = obj end
  function fs:SetTextColor(...) self.textColor = { ... } end
  function fs:SetShadowOffset(x, y) self.shadowOffset = { x, y } end
  return fs
end

-- SetTexture(file) records the file and returns true, as the client does for a file it
-- finds; set wow.textureResult = false per case for one it doesn't.
local function new_texture(layer)
  local tex = region("Texture")
  tex.layer = layer
  function tex:SetColorTexture(...) self.color = { ... } end
  function tex:SetTexture(file)
    self.file = file
    if M.textureResult == false then
      return false
    end
    return true
  end
  function tex:SetTexCoord(...) self.texCoord = { ... } end
  function tex:SetVertexColor(...) self.vertexColor = { ... } end
  return tex
end

-- EditBox methods (book.md 6.1). SetText doesn't run OnTextChanged here; wow.type does,
-- with userInput = true, as typing does in the client.
local function edit_box(frame)
  frame.focus, frame.highlights, frame.maxLetters, frame.cursor = false, 0, 0, 0
  function frame:SetText(text) self.text = text; self.highlighted = false end
  function frame:SetCursorPosition(n) self.cursor = n end
  function frame:SetFocus()
    local was = self.focus
    self.focus = true
    if not was and self.scripts.OnEditFocusGained then
      self.scripts.OnEditFocusGained(self)
    end
  end
  function frame:ClearFocus() self.focus = false end
  function frame:HasFocus() return self.focus end
  function frame:HighlightText()
    self.highlighted = true
    self.highlights = self.highlights + 1
  end
  function frame:SetAutoFocus(on) self.autoFocus = on end
  function frame:SetMultiLine(on) self.multiLine = on end
  function frame:SetMaxLetters(n) self.maxLetters = n end
  function frame:GetMaxLetters() return self.maxLetters end
  function frame:SetMaxBytes(n) self.maxBytes = n end
  function frame:SetFontObject(obj) self.fontObject = obj end
end

-- CheckButton methods: GetChecked returns a boolean; Click() toggles, then runs OnClick.
local function check_button(frame)
  frame.checked = false
  function frame:SetChecked(on) self.checked = on and true or false end
  function frame:GetChecked() return self.checked end
  function frame:SetCheckedTexture(tex) self.checkedTexture = tex end
  function frame:Click(...)
    if not self.enabled then
      return
    end
    self.checked = not self.checked
    local handler = self.scripts.OnClick
    if handler then
      handler(self, ...)
    end
  end
end

-- CreateFrame(kind, name, parent, template): `parent` and `template` are recorded, not
-- modeled (a hidden parent doesn't hide its children here). Click() runs OnClick, as the
-- client does for an enabled button.
local function new_frame(name, kind, parent, template)
  local frame = region(kind or "Frame")
  frame.name, frame.parent, frame.template = name, parent, template
  frame.events, frame.scripts, frame.enabled = {}, {}, true
  frame.fontStrings, frame.textures = {}, {}
  function frame:RegisterEvent(event) self.events[event] = true end
  function frame:UnregisterEvent(event) self.events[event] = nil end
  function frame:UnregisterAllEvents() self.events = {} end
  function frame:IsEventRegistered(event) return self.events[event] == true end
  function frame:SetScript(kind_, fn) self.scripts[kind_] = fn end
  function frame:GetScript(kind_) return self.scripts[kind_] end
  function frame:EnableMouse(on) self.mouse = on end
  function frame:EnableMouseWheel(on) self.mouseWheel = on end
  function frame:Enable() self.enabled = true end
  function frame:Disable() self.enabled = false end
  function frame:IsEnabled() return self.enabled end
  function frame:Click(...)
    local handler = self.scripts.OnClick
    if self.enabled and handler then
      handler(self, ...)
    end
  end
  -- A font string's or texture's parent is the frame that made it.
  function frame:CreateFontString(_, layer, fsTemplate)
    local fs = new_font_string(layer, fsTemplate)
    fs.parent = self
    self.fontStrings[#self.fontStrings + 1] = fs
    return fs
  end
  function frame:CreateTexture(_, layer)
    local tex = new_texture(layer)
    tex.parent = self
    self.textures[#self.textures + 1] = tex
    return tex
  end
  function frame:SetFrameStrata(strata) self.strata = strata end
  function frame:SetClampedToScreen(on) self.clamped = on end
  -- Hide runs OnHide when the frame was shown, as the client does.
  function frame:Hide()
    local was = self.shown
    self.shown = false
    if was and self.scripts.OnHide then
      self.scripts.OnHide(self)
    end
  end
  if kind == "EditBox" then
    edit_box(frame)
  elseif kind == "CheckButton" then
    check_button(frame)
  end
  frames[#frames + 1] = frame
  return frame
end

-- Every frame CreateFrame made since install whose parent is `parent`.
function M.children(parent)
  local out = {}
  for _, frame in ipairs(frames or {}) do
    if rawequal(frame.parent, parent) then
      out[#out + 1] = frame
    end
  end
  return out
end

local function defaults()
  local api = {}

  -- The clocks: set wow.now (server time, integer seconds) and wow.time (GetTime) per case,
  -- or move both with wow.advance. Libraries may cache the functions, so set the values.
  M.now = 1800000000
  M.time = 0
  api.GetServerTime = function() return M.now end
  api.GetTime = function() return M.time end
  api.GetFramerate = function() return 60 end
  -- As in the client, true from PLAYER_LOGIN on (AceAddon enables addons only then).
  M.loggedIn = false
  api.IsLoggedIn = function() return M.loggedIn end
  api.IsResting = function() return false end
  api.GetLocale = function() return "enUS" end
  api.GetRealmName = function() return "Stubrealm" end
  api.GetCurrentRegion = function() return 1 end
  api.GetCurrentRegionName = function() return "US" end
  api.UnitGUID = function(unit)
    if unit == "player" then return "Player-1-00000001" end
  end
  api.UnitName = function(unit)
    if unit == "player" then return "Traveler" end
  end
  api.UnitFullName = function(unit)
    if unit == "player" then return "Traveler", "Stubrealm" end
  end
  api.UNKNOWNOBJECT = "Unknown"
  api.UnitClass = function() return "Warrior", "WARRIOR", 1 end
  api.UnitRace = function() return "Human", "Human", 1 end
  api.UnitFactionGroup = function() return "Alliance", "Alliance" end
  api.GetNormalizedRealmName = function() return "Stubrealm" end
  -- Three days to the weekly reset.
  api.C_DateAndTime = {
    GetSecondsUntilWeeklyReset = function() return 259200 end,
  }

  -- Solo, no guild, not in combat.
  api.IsInGroup = function() return false end
  api.IsInRaid = function() return false end
  api.GetNumGroupMembers = function() return 0 end
  api.IsInGuild = function() return false end
  api.GetNumGuildMembers = function() return 0, 0, 0 end
  api.GetGuildRosterInfo = function() return nil end
  api.C_GuildInfo = { GuildRoster = function() end }
  api.InCombatLockdown = function() return false end

  -- Timers queue with their due time. wow.advance runs them as the clock reaches them;
  -- wow.run_timers() runs everything queued, whatever its delay.
  M.timers = {}
  api.C_Timer = {
    After = function(delay, fn)
      M.timers[#M.timers + 1] = { delay = delay, due = M.now + delay, fn = fn }
    end,
  }

  -- Addon metadata comes from this table; the TOC's version is a packager token.
  M.metadata = { Version = "@project-version@" }
  api.C_AddOns = {
    GetAddOnMetadata = function(_, field) return M.metadata[field] end,
  }

  -- Sent addon messages are recorded, never delivered.
  M.sent = {}
  api.C_ChatInfo = {
    RegisterAddonMessagePrefix = function() return true end,
    SendAddonMessage = function(prefix, text, channel, target)
      M.sent[#M.sent + 1] = { prefix = prefix, text = text, channel = channel, target = target }
      return true
    end,
  }
  api.C_ChatInfo.SendAddonMessageLogged = api.C_ChatInfo.SendAddonMessage
  api.SendChatMessage = function() end
  api.Enum = {}

  -- A named frame is also a global, as in the client (uninstall removes it).
  api.CreateFrame = function(kind, name, parent, template)
    local frame = new_frame(name, kind, parent, template)
    if type(name) == "string" then
      _G[name] = frame
    end
    return frame
  end
  -- The gossip frame Sign anchors to. UnitGUID("npc") stays nil unless a case sets it.
  api.GossipFrame = new_frame("GossipFrame")
  -- The book's parent, the Escape list and the client's font objects (book.md 6.1). Set
  -- any to nil per case to test the fallbacks.
  -- UIParent is the screen for wow.rect: 1024 x 768, the size of UIParent on a 4:3
  -- screen at UI scale 1. It isn't the smallest: a 5:4 screen gives 960 x 768.
  api.UIParent = new_frame("UIParent")
  api.UIParent.screen = true
  api.UIParent:SetSize(M.SCREEN_W, M.SCREEN_H)
  M.screen = api.UIParent
  api.UISpecialFrames = {}
  api.GameFontNormal = { name = "GameFontNormal" }
  api.GameFontNormalSmall = { name = "GameFontNormalSmall" }
  api.GameFontNormalLarge = { name = "GameFontNormalLarge" }
  api.GameFontHighlightSmall = { name = "GameFontHighlightSmall" }
  api.QuestTitleFont = { name = "QuestTitleFont" }
  api.date = os.date
  api.time = os.time
  M.textureResult = true

  -- Chat output lands in wow.chat.
  M.chat = {}
  api.DEFAULT_CHAT_FRAME = {
    AddMessage = function(_, text) M.chat[#M.chat + 1] = text end,
  }
  api.SlashCmdList = {}
  api.hash_SlashCmdList = {}

  api.hooksecurefunc = function(target, name, hook)
    if type(target) == "string" then
      target, name, hook = _G, target, name
    end
    local original = target[name]
    target[name] = function(...)
      local results = { original(...) }
      hook(...)
      return unpack(results)
    end
  end
  api.securecallfunction = function(fn, ...) return fn(...) end

  -- The client's xpcall passes extra arguments to fn; stock Lua 5.1's drops them,
  -- which makes Ace3's safecall run OnInitialize without `self`.
  api.xpcall = function(fn, handler, ...)
    local n, args = select("#", ...), { ... }
    return lua_xpcall(function() return fn(unpack(args, 1, n)) end, handler)
  end

  -- Errors the libraries catch (e.g. in OnInitialize) land in wow.errors.
  M.errors = {}
  api.geterrorhandler = function()
    return function(err) M.errors[#M.errors + 1] = err end
  end
  api.issecretvalue = function() return false end
  api.wipe = function(t)
    for k in pairs(t) do t[k] = nil end
    return t
  end
  api.format = string.format

  return api
end

-- Overrides for Forever's two-part names, as the beta gave them (2026-09-30): the surname
-- in the realm slot of UnitName / UnitFullName("player"), and the ruleset realm.
function M.foreverNames(first, surname)
  first, surname = first or "Traveler", surname or "Wayfarer"
  local function names(unit)
    if unit == "player" then return first, surname end
  end
  return {
    UnitName = names,
    UnitFullName = names,
    GetRealmName = function() return "Classic Beta PvP" end,
    GetNormalizedRealmName = function() return "ClassicBetaPvP" end,
  }
end

-- Installs the stub into _G. `overrides` replaces or adds names for this case.
function M.install(overrides)
  M.uninstall()
  saved, frames = {}, {}
  -- Remember every global present now; uninstall removes anything added later
  -- (the stub, library globals, SavedVariables, slash command names).
  for name, value in pairs(_G) do
    saved[name] = value
  end
  local api = defaults()
  for name, value in pairs(overrides or {}) do
    api[name] = value
  end
  for name, value in pairs(api) do
    _G[name] = value
  end
  return api
end

-- Restores _G to what it was before install.
function M.uninstall()
  if not saved then return end
  local names = {}
  for name in pairs(_G) do
    names[#names + 1] = name
  end
  for _, name in ipairs(names) do
    if saved[name] == nil then
      _G[name] = nil
    end
  end
  for name, value in pairs(saved) do
    _G[name] = value
  end
  saved, frames = nil, nil
end

-- Delivers an event to every frame registered for it, as the client does.
function M.fire(event, ...)
  if event == "PLAYER_LOGIN" then
    M.loggedIn = true
  end
  for _, frame in ipairs(frames) do
    local handler = frame.scripts.OnEvent
    if frame.events[event] and handler then
      handler(frame, event, ...)
    end
  end
end

-- Runs and clears queued C_Timer callbacks, whatever their delay. Timers they schedule
-- stay queued.
function M.run_timers()
  local pending = M.timers
  M.timers = {}
  for _, timer in ipairs(pending) do
    timer.fn()
  end
end

-- Runs the first due timer, in the order they were scheduled. Returns false if none is due.
local function run_due()
  for i, timer in ipairs(M.timers) do
    if timer.due <= M.now then
      table.remove(M.timers, i)
      timer.fn()
      return true
    end
  end
  return false
end

-- Moves both clocks forward one second at a time, running each timer once the clock
-- reaches it, including timers those schedule.
function M.advance(seconds)
  for _ = 1, seconds do
    M.now = M.now + 1
    M.time = M.time + 1
    while run_due() do end
  end
end

-- Types `text` into an edit box: sets it and runs OnTextChanged(self, true).
function M.type(edit, text)
  edit.text = text
  local handler = edit.scripts.OnTextChanged
  if handler then
    handler(edit, true)
  end
end

-- Runs a slash command the way the chat box would, e.g. wow.slash("/ledger").
function M.slash(line)
  local command, input = line:match("^(/%S+)%s*(.*)$")
  for key, fn in pairs(_G.SlashCmdList) do
    for i = 1, 10 do
      local alias = _G["SLASH_" .. key .. i]
      if alias and alias:lower() == command:lower() then
        return fn(input)
      end
    end
  end
  error("no slash command " .. tostring(command))
end

-- ---------------------------------------------------------------------------
-- Layout (#140): anchors to rectangles, and a text size estimate, so specs can check
-- geometry without a client. Pure: reads what the regions recorded, changes nothing.

-- The font size of each font object (and font string template) the AddOn uses, from the
-- client's FrameXML. Text width is estimated as characters x size x TEXT_EM. 0.6 em is a
-- guess, not a measurement: it's meant to be wider than most text, but capitals, wide
-- letters and Morpheus (QuestTitleFont) may run wider. Calibrate it from the string widths
-- the #139 dev harness dumps (`sw`). A line is `size` high, also a guess.
M.FONT_SIZES = {
  GameFontNormal = 12,
  GameFontNormalSmall = 10,
  GameFontNormalLarge = 16,
  GameFontHighlight = 12,
  GameFontHighlightSmall = 10,
  QuestTitleFont = 18,
  UIPanelButtonTemplate = 12, -- a button's label is GameFontNormal
}
M.TEXT_EM = 0.6

-- Each anchor point as { horizontal, vertical } fractions of a rectangle from its bottom left.
local POINTS = {
  TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 },
  LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 },
  BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 }, BOTTOMRIGHT = { 1, 0 },
}

-- The font size a region's text is drawn in: its font object, else its template (a font
-- string's, or a button's), else GameFontNormal.
function M.fontSize(r)
  local obj = r.fontObject
  local size = type(obj) == "table" and M.FONT_SIZES[obj.name]
    or M.FONT_SIZES[r.template]
  return size or M.FONT_SIZES.GameFontNormal
end

-- Characters (not bytes) in a UTF-8 string.
local function chars(s)
  return #s:gsub("[\128-\191]", "")
end

-- The estimated width of `text` (one line) in `region`'s font.
function M.textWidth(r, text)
  return chars(text) * M.fontSize(r) * M.TEXT_EM
end

-- How `region`'s text lays out in `width` (nil: no width, so no wrapping): the number of
-- lines, the widest line and the widest word, all estimated. Word wrap is on unless the
-- region turned it off, as in the client. Empty text is 0 lines.
function M.textLines(r, width)
  local text = type(r.text) == "string" and r.text or ""
  if text == "" then
    return 0, 0, 0
  end
  local em = M.fontSize(r) * M.TEXT_EM
  local wrap = r.wordWrap ~= false and type(width) == "number"
  local lines, widest, widestWord = 0, 0, 0
  for para in (text .. "\n"):gmatch("([^\n]*)\n") do
    local n = 0 -- characters on the current line
    lines = lines + 1
    for word in para:gmatch("%S+") do
      local w = chars(word)
      widestWord = math.max(widestWord, w * em)
      if wrap and n > 0 and (n + 1 + w) * em > width then
        widest = math.max(widest, n * em)
        lines, n = lines + 1, w
      else
        n = n + (n > 0 and 1 or 0) + w
      end
    end
    if not wrap then
      n = chars(para)
    end
    widest = math.max(widest, n * em)
  end
  return lines, widest, widestWord
end

-- A point as SetPoint recorded it: point [, relativeTo [, relativePoint]] [, x, y].
-- relativeTo may be a region, a global frame name or nil (the parent, or the screen for a
-- region without one).
local function anchorOf(p, r)
  local point = p[1]
  local rel, relPoint, x, y
  if type(p[2]) == "number" then
    x, y = p[2], p[3]
  else
    rel = p[2]
    if type(p[3]) == "string" then
      relPoint, x, y = p[3], p[4], p[5]
    elseif type(p[3]) == "number" then
      x, y = p[3], p[4]
    else
      x, y = p[4], p[5]
    end
  end
  if type(rel) == "string" then
    rel = rawget(_G, rel)
  end
  if rel == nil then
    rel = r.parent or M.screen
  end
  return point, rel, relPoint or point, x or 0, y or 0
end

-- One axis from its constraints (fraction -> coordinate): two different fractions give
-- the start and the length (a stretch); one needs `size`.
local function span(cons, size)
  local lo, hi
  for f in pairs(cons) do
    if lo == nil or f < lo then lo = f end
    if hi == nil or f > hi then hi = f end
  end
  if lo == nil then
    return nil
  end
  if lo ~= hi then
    local len = (cons[hi] - cons[lo]) / (hi - lo)
    return cons[lo] - lo * len, len
  end
  if type(size) ~= "number" then
    return nil
  end
  return cons[lo] - lo * size, size
end

local function set(n)
  return type(n) == "number" and n > 0 and n or nil
end

local resolve

-- Where each of `region`'s points lands, as horizontal and vertical constraints; nil if
-- a point is malformed or its relative region doesn't resolve.
local function constraints(r, visiting)
  local xs, ys = {}, {}
  for _, p in ipairs(r.points) do
    local point, rel, relPoint, x, y = anchorOf(p, r)
    local a, b = POINTS[point], POINTS[relPoint]
    if not a or not b or type(x) ~= "number" or type(y) ~= "number" then
      return nil
    end
    local l, bottom, w, h = resolve(rel, visiting)
    if l == nil then
      return nil
    end
    xs[a[1]] = l + b[1] * w + x
    ys[a[2]] = bottom + b[2] * h + y
  end
  return xs, ys
end

resolve = function(r, visiting)
  if type(r) ~= "table" then
    return nil
  end
  if r.screen then
    return 0, 0, r.width, r.height
  end
  if visiting[r] or type(r.points) ~= "table" or #r.points == 0 then
    return nil -- an anchor cycle, or no anchors
  end
  visiting[r] = true
  local xs, ys = constraints(r, visiting)
  visiting[r] = nil
  if xs == nil then
    return nil
  end
  local text = r.kind == "FontString"
  -- A font string without a set width is as wide as its text; without a set height, as
  -- high as its lines.
  local width = set(r.width)
  if width == nil and text then
    local _, widest = M.textLines(r, nil)
    width = widest
  end
  local left, w = span(xs, width)
  if left == nil then
    return nil
  end
  local height = set(r.height)
  if height == nil and text then
    height = M.textLines(r, w) * M.fontSize(r)
  end
  local bottom, h = span(ys, height)
  if bottom == nil or w < 0 or h < 0 then
    return nil
  end
  return left, bottom, w, h
end

-- The rectangle a region resolves to in screen units, from its points, its size and its
-- parents' rectangles, as the client lays it out: left, bottom, width, height; nil when it
-- can't be resolved (no points, a missing size, a malformed point, an anchor cycle, or a
-- relative region that doesn't resolve). UIParent is the screen, 1024 x 768.
function M.rect(r)
  return resolve(r, {})
end

return M
