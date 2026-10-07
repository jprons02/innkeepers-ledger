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

-- What frames, font strings and textures share: a shown flag, points, a size and text.
local function region(kind)
  local r = { kind = kind, shown = true, points = {}, text = nil }
  function r:Show() self.shown = true end
  function r:Hide() self.shown = false end
  function r:IsShown() return self.shown end
  function r:SetPoint(...) self.points[#self.points + 1] = { ... } end
  function r:ClearAllPoints() self.points = {} end
  function r:SetAllPoints(...) self.allPoints = { ... } end
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
  function frame:CreateFontString(_, layer, fsTemplate)
    local fs = new_font_string(layer, fsTemplate)
    self.fontStrings[#self.fontStrings + 1] = fs
    return fs
  end
  function frame:CreateTexture(_, layer)
    local tex = new_texture(layer)
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
  api.UIParent = new_frame("UIParent")
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

return M
