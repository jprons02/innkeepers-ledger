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

local function new_frame(name)
  local frame = { name = name, events = {}, scripts = {} }
  function frame:RegisterEvent(event) self.events[event] = true end
  function frame:UnregisterEvent(event) self.events[event] = nil end
  function frame:UnregisterAllEvents() self.events = {} end
  function frame:IsEventRegistered(event) return self.events[event] == true end
  function frame:SetScript(kind, fn) self.scripts[kind] = fn end
  function frame:GetScript(kind) return self.scripts[kind] end
  frame.Show = function() end
  frame.Hide = function() end
  frames[#frames + 1] = frame
  return frame
end

local function defaults()
  local api = {}

  api.GetServerTime = function() return 1800000000 end
  api.GetTime = function() return 0 end
  api.GetFramerate = function() return 60 end
  api.IsLoggedIn = function() return false end
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
  api.UnitClass = function() return "Warrior", "WARRIOR", 1 end
  api.UnitRace = function() return "Human", "Human", 1 end
  api.UnitFactionGroup = function() return "Alliance", "Alliance" end

  -- Timers queue until a test runs them with wow.run_timers().
  M.timers = {}
  api.C_Timer = {
    After = function(_, fn) M.timers[#M.timers + 1] = fn end,
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

  api.CreateFrame = function(_, name) return new_frame(name) end

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
  for _, frame in ipairs(frames) do
    local handler = frame.scripts.OnEvent
    if frame.events[event] and handler then
      handler(frame, event, ...)
    end
  end
end

-- Runs and clears queued C_Timer callbacks.
function M.run_timers()
  local pending = M.timers
  M.timers = {}
  for _, fn in ipairs(pending) do
    fn()
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
