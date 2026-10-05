-- ILProbe: throwaway platform probe for Innkeeper's Ledger issue #12.
-- Records client facts into ILProbeDB (written on /reload or logout) so they can be
-- read from WTF\Account\<account>\SavedVariables\!ILProbe.lua. Never released.
-- The "!" in the folder name makes it load before InnkeepersLedger, so the error hook
-- also sees that AddOn's load-time errors.

local PREFIX = "ILProbe"
local REAL_PREFIX = "InnLedger"
local MAX_LOG = 3000

local pending = {}   -- records made before ILProbeDB is loaded
local db

-- ---------------------------------------------------------------- safe reading

-- True when v can be read normally (not a hidden/"secret" value).
local function readable(v)
  local f = _G.issecretvalue
  if type(f) == "function" then
    local ok, r = pcall(f, v)
    if ok and r then return false end
  end
  return (pcall(function()
    local s = tostring(v)
    if s == "\0" then return 0 end
    return #s
  end))
end

-- A plain string for any value; never stores a hidden value.
local function str(v)
  if v == nil then return "nil" end
  if not readable(v) then return "<hidden>" end
  local ok, s = pcall(tostring, v)
  if not ok then return "<tostring error: " .. tostring(s) .. ">" end
  return s
end

-- Results of every secret-value checker the client has, for v.
local function secrecy(v)
  local out = {}
  for _, name in ipairs({ "issecretvalue", "issecrettable", "canaccessvalue",
                          "canaccesstable", "hasanysecretvalues" }) do
    local f = _G[name]
    if type(f) == "function" then
      local ok, r = pcall(f, v)
      out[name] = ok and str(r) or ("error: " .. str(r))
    end
  end
  out.readable = readable(v)
  return out
end

-- Resolves "C_ChatInfo.SendAddonMessage" against _G.
local function resolve(path)
  local v = _G
  for part in string.gmatch(path, "[^%.]+") do
    if type(v) ~= "table" then return nil end
    v = v[part]
  end
  return v
end

local function call(path, ...)
  local f = resolve(path)
  if type(f) ~= "function" then return { missing = true } end
  local r = { pcall(f, ...) }
  local out = { ok = r[1] }
  if not r[1] then
    out.err = str(r[2])
    return out
  end
  for i = 2, #r do out[i - 1] = str(r[i]) end
  out.n = #r - 1
  return out
end

local function enumDump(t)
  if type(t) ~= "table" then return str(t) end
  local out = {}
  for k, v in pairs(t) do out[str(k)] = str(v) end
  return out
end

-- ---------------------------------------------------------------- recording

local function record(kind, data)
  local entry = { t = date("%Y-%m-%d %H:%M:%S"), k = kind, d = data }
  if not db then
    pending[#pending + 1] = entry
    return
  end
  local log = db.log
  log[#log + 1] = entry
  if #log > MAX_LOG then table.remove(log, 1) end
end

local function say(msg)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00ILProbe:|r " .. msg)
  end
end

-- Lua errors from any AddOn, with a stack.
do
  local original = geterrorhandler()
  seterrorhandler(function(msg, ...)
    pcall(function()
      local stack = type(debugstack) == "function" and debugstack(3, 12, 0) or ""
      local e = { t = date("%Y-%m-%d %H:%M:%S"), msg = str(msg), stack = str(stack) }
      if db then
        db.errors[#db.errors + 1] = e
      else
        pending[#pending + 1] = { t = e.t, k = "error", d = e }
      end
    end)
    return original(msg, ...)
  end)
end

-- ---------------------------------------------------------------- facts

local function mapChain()
  local chain = {}
  local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
  if not ok then return { err = str(id) } end
  local best = id
  while id and id ~= 0 and #chain < 12 do
    local okInfo, info = pcall(C_Map.GetMapInfo, id)
    if not okInfo or type(info) ~= "table" then break end
    chain[#chain + 1] = { id = str(info.mapID), name = str(info.name),
                          mapType = str(info.mapType), parent = str(info.parentMapID) }
    id = info.parentMapID
  end
  local pos = {}
  if best then
    local okPos, p = pcall(C_Map.GetPlayerMapPosition, best, "player")
    if okPos and p and p.GetXY then
      local x, y = p:GetXY()
      pos = { x = str(x), y = str(y) }
    end
  end
  return { best = str(best), chain = chain, pos = pos,
           zone = str(GetZoneText and GetZoneText()),
           realZone = str(GetRealZoneText and GetRealZoneText()),
           subzone = str(GetSubZoneText and GetSubZoneText()),
           minimap = str(GetMinimapZoneText and GetMinimapZoneText()) }
end

local function selfFullName()
  local ok, name, realm = pcall(UnitFullName, "player")
  if not ok or not name then return nil end
  if not realm or realm == "" then
    local okR, r = pcall(GetNormalizedRealmName)
    realm = okR and r or ""
  end
  return name .. "-" .. realm
end

local API_NAMES = {
  "C_ChatInfo.SendAddonMessage", "C_ChatInfo.SendAddonMessageLogged",
  "C_ChatInfo.RegisterAddonMessagePrefix", "C_ChatInfo.IsAddonMessagePrefixRegistered",
  "C_ChatInfo.InChatMessagingLockdown", "SendAddonMessage",
  "C_GossipInfo.GetOptions", "C_GossipInfo.GetText", "C_GossipInfo.SelectOption",
  "C_GossipInfo.GetAvailableQuests", "GossipFrame", "GossipFrame.GreetingPanel",
  "GossipFrame.GreetingPanel.ScrollBox", "GossipTitleButton1", "GossipFrameGreetingPanel",
  "C_Map.GetBestMapForUnit", "C_Map.GetMapInfo", "C_Map.GetPlayerMapPosition",
  "IsResting", "InCombatLockdown", "UnitGUID", "UnitFullName", "GetNormalizedRealmName",
  "C_DateAndTime.GetSecondsUntilWeeklyReset", "C_DateAndTime.GetSecondsUntilDailyReset",
  "GetServerTime", "GetCurrentRegion", "GetCurrentRegionName",
  "C_GuildInfo.GuildRoster", "GuildRoster", "GetGuildRosterInfo", "GetNumGuildMembers",
  "C_EncodingUtil", "C_AddOns.GetAddOnInfo", "C_AddOns.IsAddOnLoaded",
  "C_AddOns.GetAddOnMetadata", "GetAddOnMetadata",
  "issecretvalue", "issecrettable", "canaccessvalue", "canaccesstable", "hasanysecretvalues",
  "C_Secrets", "C_RestrictedActions", "C_Timer.After", "C_Timer.NewTicker",
  "GetTimePreciseSec", "debugprofilestop", "JoinTemporaryChannel", "JoinChannelByName",
  "LeaveChannelByName", "GetChannelName", "UnitFactionGroup", "UnitReaction",
  "C_PlayerInfo.GUIDIsPlayer", "C_Housing", "C_DamageMeter", "C_EditMode",
  "ChatThrottleLib", "LE_PARTY_CATEGORY_HOME", "LE_PARTY_CATEGORY_INSTANCE",
  "UNKNOWNOBJECT", "WOW_PROJECT_ID", "WOW_PROJECT_MAINLINE", "WOW_PROJECT_CLASSIC",
}

local function snapshot(reason)
  local s = { reason = reason }
  s.build = call("GetBuildInfo")
  s.projectId = str(_G.WOW_PROJECT_ID)
  s.player = {
    guid = call("UnitGUID", "player"), guidSecrecy = secrecy(UnitGUID("player")),
    name = call("UnitName", "player"), fullName = call("UnitFullName", "player"),
    selfFull = str(selfFullName()),
    realm = call("GetRealmName"), normalizedRealm = call("GetNormalizedRealmName"),
    faction = call("UnitFactionGroup", "player"),
    factionSecrecy = secrecy(UnitFactionGroup("player")),
    race = call("UnitRace", "player"), class = call("UnitClass", "player"),
    level = call("UnitLevel", "player"),
  }
  s.state = {
    resting = call("IsResting"), combat = call("InCombatLockdown"),
    instance = call("IsInInstance"), inGuild = call("IsInGuild"),
    inGroup = call("IsInGroup"), inRaid = call("IsInRaid"),
    inGroupHome = call("IsInGroup", _G.LE_PARTY_CATEGORY_HOME),
    inGroupInstance = call("IsInGroup", _G.LE_PARTY_CATEGORY_INSTANCE),
    members = call("GetNumGroupMembers"),
    chatLockdown = call("C_ChatInfo.InChatMessagingLockdown"),
  }
  s.time = {
    weeklyReset = call("C_DateAndTime.GetSecondsUntilWeeklyReset"),
    dailyReset = call("C_DateAndTime.GetSecondsUntilDailyReset"),
    server = call("GetServerTime"), clientTime = str(time()),
    date = date("!%Y-%m-%d %H:%M:%S UTC"),
    region = call("GetCurrentRegion"), regionName = call("GetCurrentRegionName"),
  }
  s.map = mapChain()
  s.api = {}
  for _, name in ipairs(API_NAMES) do
    local v = resolve(name)
    s.api[name] = (type(v) == "table" or type(v) == "function") and type(v) or str(v)
  end
  s.consts = {
    UNKNOWNOBJECT = str(_G.UNKNOWNOBJECT),
    LE_PARTY_CATEGORY_HOME = str(_G.LE_PARTY_CATEGORY_HOME),
    LE_PARTY_CATEGORY_INSTANCE = str(_G.LE_PARTY_CATEGORY_INSTANCE),
  }
  local E = _G.Enum or {}
  s.enums = {
    SendAddonMessageResult = enumDump(E.SendAddonMessageResult),
    RegisterAddonMessagePrefixResult = enumDump(E.RegisterAddonMessagePrefixResult),
    UIMapType = enumDump(E.UIMapType),
  }
  s.realAddon = {
    info = call("C_AddOns.GetAddOnInfo", "InnkeepersLedger"),
    loaded = call("C_AddOns.IsAddOnLoaded", "InnkeepersLedger"),
    version = call("C_AddOns.GetAddOnMetadata", "InnkeepersLedger", "Version"),
    prefixRegistered = call("C_ChatInfo.IsAddonMessagePrefixRegistered", REAL_PREFIX),
  }
  s.memoryKB = str(collectgarbage("count"))
  db.snaps[#db.snaps + 1] = s
  record("snapshot", { reason = reason, n = #db.snaps })
  say("snapshot " .. #db.snaps .. " saved (" .. reason .. ")")
end

-- Every C_ namespace's function names, plus globals matching interesting patterns.
local function apiInventory()
  local build = str(select(2, GetBuildInfo()))
  if db.api[build] then return end
  local inv = { namespaces = {}, matches = {}, globalFunctions = 0 }
  local patterns = { "[Ss]ecret", "Sit", "Stand", "Restrict", "Lockdown", "Gossip",
                     "AddonMessage", "Resting", "Encoding" }
  for k, v in pairs(_G) do
    if type(k) == "string" then
      if type(v) == "function" then inv.globalFunctions = inv.globalFunctions + 1 end
      if k:match("^C_") and type(v) == "table" then
        local fns = {}
        for fk, fv in pairs(v) do
          if type(fk) == "string" and type(fv) == "function" then fns[#fns + 1] = fk end
        end
        table.sort(fns)
        inv.namespaces[k] = table.concat(fns, " ")
      else
        for _, p in ipairs(patterns) do
          if k:match(p) and #inv.matches < 400 then
            inv.matches[#inv.matches + 1] = k .. " (" .. type(v) .. ")"
            break
          end
        end
      end
    end
  end
  table.sort(inv.matches)
  db.api[build] = inv
  record("api", { build = build, globalFunctions = inv.globalFunctions })
end

-- ---------------------------------------------------------------- gossip

local probeButton
local lastNpc

local function frameShape()
  local g = _G.GossipFrame
  if type(g) ~= "table" then return { gossipFrame = str(g) } end
  local keys = {}
  for k, v in pairs(g) do
    if type(k) == "string" and #keys < 60 then keys[#keys + 1] = k .. ":" .. type(v) end
  end
  table.sort(keys)
  local shape = { keys = table.concat(keys, " ") }
  if g.GetNumChildren then shape.children = str(g:GetNumChildren()) end
  if g.GetName then shape.name = str(g:GetName()) end
  if g.GetWidth then shape.size = str(g:GetWidth()) .. "x" .. str(g:GetHeight()) end
  return shape
end

local function ensureButton()
  if probeButton then return end
  local parent = type(_G.GossipFrame) == "table" and _G.GossipFrame or UIParent
  local ok, b = pcall(CreateFrame, "Button", "ILProbeSignButton", parent, "UIPanelButtonTemplate")
  if not ok then
    record("inject", { created = false, err = str(b) })
    return
  end
  b:SetSize(180, 24)
  b:SetText("Probe: sign the ledger")
  b:SetPoint("TOP", parent, "BOTTOM", 0, -4)
  b:SetScript("OnClick", function()
    record("inject", { clicked = true, npc = lastNpc, resting = call("IsResting") })
    say("button click recorded for NPC " .. str(lastNpc))
  end)
  probeButton = b
  record("inject", { created = true, parent = parent == UIParent and "UIParent" or "GossipFrame" })
end

local function onGossipShow()
  local guid = UnitGUID("npc")
  local npcId
  if readable(guid) and type(guid) == "string" then
    local unitType, _, _, _, _, id = strsplit("-", guid)
    npcId = id
    if unitType ~= "Creature" then npcId = (unitType or "?") .. ":" .. (id or "?") end
  end
  lastNpc = npcId or "<unknown>"
  local e = {
    guid = str(guid), guidSecrecy = secrecy(guid), npcId = str(npcId),
    name = str(UnitName("npc")), nameSecrecy = secrecy(UnitName("npc")),
    npcFaction = call("UnitFactionGroup", "npc"), reaction = call("UnitReaction", "npc", "player"),
    resting = call("IsResting"), map = mapChain(), frame = frameShape(),
    text = call("C_GossipInfo.GetText"), options = {},
  }
  local okO, options = pcall(C_GossipInfo.GetOptions)
  if okO and type(options) == "table" then
    for i, o in ipairs(options) do
      e.options[i] = { name = str(o.name), icon = str(o.icon), id = str(o.gossipOptionID),
                       flags = str(o.flags), status = str(o.status) }
    end
  else
    e.optionsErr = str(options)
  end
  db.npcs[str(lastNpc)] = e
  record("gossip", { npcId = str(lastNpc), name = e.name })
  -- The button test is done (2026-10-05); the real AddOn's "Sign the guestbook" button
  -- now sits in this spot, so the probe no longer adds its own.
  say("gossip recorded: " .. e.name .. " (NPC " .. str(lastNpc) .. ")")
end

-- ---------------------------------------------------------------- addon messages

local sendSeq = 0

local function send(chatType, target, text)
  sendSeq = sendSeq + 1
  text = text or ("ping " .. sendSeq .. " " .. chatType)
  local f = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or _G.SendAddonMessage
  local ok, r1, r2 = pcall(f, PREFIX, text, chatType, target)
  local e = { chatType = chatType, target = str(target), len = #text, ok = ok,
              result = str(r1), result2 = str(r2), seq = sendSeq,
              at = str(GetTimePreciseSec and GetTimePreciseSec()) }
  record("send", e)
  return ok, r1
end

-- Finds a group unit and guild roster row whose name matches the sender string.
local function resolveSender(sender)
  local out = {}
  if not readable(sender) then return { hidden = true } end
  local units = { "player" }
  if IsInRaid() then
    for i = 1, 40 do units[#units + 1] = "raid" .. i end
  else
    for i = 1, 4 do units[#units + 1] = "party" .. i end
  end
  for _, unit in ipairs(units) do
    local ok, name, realm = pcall(UnitFullName, unit)
    if ok and name then
      local full = name .. "-" .. ((realm and realm ~= "") and realm or (GetNormalizedRealmName() or ""))
      if full == sender or name == sender then
        out.unit = unit
        out.unitFull = full
        out.unitGuid = str(UnitGUID(unit))
      end
    end
  end
  if IsInGuild() then
    local okN, n = pcall(GetNumGuildMembers)
    for i = 1, (okN and n or 0) do
      local r = { pcall(GetGuildRosterInfo, i) }
      if r[1] and r[2] == sender then
        out.guildIndex = i
        out.guildGuid17 = str(r[18])
        out.guildReturns = #r - 1
        break
      end
    end
  end
  return out
end

local function onAddonMessage(event, prefix, text, channel, sender, target, zoneChannelID,
                              localID, name, instanceID)
  if prefix ~= PREFIX and prefix ~= REAL_PREFIX then return end
  local e = {
    event = event, prefix = str(prefix), len = readable(text) and #text or "<hidden>",
    text = prefix == PREFIX and str(text) or nil, channel = str(channel),
    sender = str(sender), senderSecrecy = secrecy(sender), target = str(target),
    zoneChannelID = str(zoneChannelID), localID = str(localID), name = str(name),
    instanceID = str(instanceID), resolved = resolveSender(sender),
    at = str(GetTimePreciseSec and GetTimePreciseSec()),
  }
  local key = str(prefix) .. " " .. str(channel)
  db.recvCounts[key] = (db.recvCounts[key] or 0) + 1
  -- Keep every probe message but only the first 50 of the real AddOn's traffic.
  if prefix == PREFIX or db.recvCounts[key] <= 50 then record("recv", e) end
end

-- ---------------------------------------------------------------- tests

local function after(sec, fn) C_Timer.After(sec, function() pcall(fn) end) end

local function testPing()
  local me = selfFullName()
  send("WHISPER", me)
  if IsInGuild() then send("GUILD") end
  if IsInRaid() then send("RAID") elseif IsInGroup(LE_PARTY_CATEGORY_HOME) then send("PARTY") end
  if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then send("INSTANCE_CHAT") end
  say("pings sent (whisper-to-self" .. (IsInGuild() and ", guild" or "") .. ")")
end

local function testSize()
  local me = selfFullName()
  for _, n in ipairs({ 250, 255, 256, 300 }) do
    local body = "size" .. n .. " " .. string.rep("x", n)
    send("WHISPER", me, body:sub(1, n))
    if IsInGuild() then send("GUILD", nil, body:sub(1, n)) end
  end
  say("size test sent (250/255/256/300 bytes)")
end

local function testBurst()
  local me = selfFullName()
  for i = 1, 30 do send("WHISPER", me, "burst " .. i) end
  if IsInGuild() then
    for i = 1, 30 do send("GUILD", nil, "gburst " .. i) end
  end
  say("burst sent (30 whisper-to-self" .. (IsInGuild() and ", 30 guild" or "") .. ")")
end

local CHANNEL = "ilprobe" .. tostring(math.random(10000, 99999))

local function testChannel()
  local okJ, r = pcall(JoinTemporaryChannel or JoinChannelByName, CHANNEL)
  record("channel", { joined = okJ, result = str(r), channel = CHANNEL })
  after(3, function()
    local id = GetChannelName(CHANNEL)
    record("channel", { id = str(id) })
    if id and id > 0 then
      send("CHANNEL", id, "chan ping")
      after(5, function() pcall(LeaveChannelByName, CHANNEL) end)
    end
  end)
  say("custom channel test started")
end

local function testEditBox()
  local eb = CreateFrame("EditBox", nil, UIParent)
  eb:SetMultiLine(true)
  eb:SetAutoFocus(false)
  eb:SetFontObject(ChatFontNormal)
  eb:SetSize(300, 100)
  eb:Hide()
  local s = string.rep("ABCDEFGHIJ", 25600) -- 256 000 bytes
  local r = { size = #s, defaultMax = str(eb:GetMaxLetters()), memBeforeKB = str(collectgarbage("count")) }
  local t0 = debugprofilestop()
  eb:SetText(s)
  r.setTextMs = str(debugprofilestop() - t0)
  r.gotDefault = #(eb:GetText() or "")
  eb:SetMaxLetters(0)
  t0 = debugprofilestop()
  eb:SetText(s)
  r.setTextMs2 = str(debugprofilestop() - t0)
  r.gotUnlimited = #(eb:GetText() or "")
  eb:SetText("")
  r.memAfterKB = str(collectgarbage("count"))
  record("editbox", r)
  say("edit box: got " .. r.gotUnlimited .. " of " .. r.size .. " bytes in " .. r.setTextMs2 .. " ms")
end

local function testRoster()
  if not IsInGuild() then
    record("roster", { inGuild = false })
    return
  end
  if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
  after(3, function()
    local rows = {}
    local okN, n = pcall(GetNumGuildMembers)
    for i = 1, math.min(okN and n or 0, 5) do
      local r = { pcall(GetGuildRosterInfo, i) }
      rows[i] = { name = str(r[2]), returns = #r - 1, guid17 = str(r[18]),
                  guidSecrecy = secrecy(r[18]) }
    end
    record("roster", { members = str(n), rows = rows })
  end)
end

local function testGroup()
  local rows = {}
  local units = IsInRaid() and 40 or 4
  for i = 1, units do
    local unit = (IsInRaid() and "raid" or "party") .. i
    if UnitExists(unit) then
      rows[unit] = { fullName = call("UnitFullName", unit), name = call("UnitName", unit),
                     guid = call("UnitGUID", unit) }
    end
  end
  record("group", { rows = rows, self = call("UnitFullName", "player") })
end

-- Runs the real AddOn's /ledger command so its output is captured.
local function realStatus()
  for key, fn in pairs(SlashCmdList) do
    if _G["SLASH_" .. key .. "1"] == "/ledger" then
      pcall(fn, "")
      return
    end
  end
  record("ledger", { slash = "missing" })
end

local function runAll()
  say("running all tests; stay put for about 25 seconds")
  snapshot("all")
  apiInventory()
  realStatus()
  after(1, testPing)
  after(3, testSize)
  after(5, testChannel)
  after(12, testEditBox)
  after(13, testRoster)
  after(14, testGroup)
  after(16, testBurst)
  after(25, function()
    snapshot("all-end")
    say("done. Talk to an innkeeper next, click the probe button, then /reload.")
  end)
end

-- ---------------------------------------------------------------- wiring

local frame = CreateFrame("Frame")
local EVENTS = {
  "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "GOSSIP_SHOW", "GOSSIP_CLOSED",
  "CHAT_MSG_ADDON", "CHAT_MSG_ADDON_LOGGED", "PLAYER_UPDATE_RESTING",
  "ZONE_CHANGED_NEW_AREA", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
  "ENCOUNTER_START", "ENCOUNTER_END", "GROUP_ROSTER_UPDATE", "GUILD_ROSTER_UPDATE",
}
for _, ev in ipairs(EVENTS) do
  local ok, err = pcall(frame.RegisterEvent, frame, ev)
  if not ok then record("event", { event = ev, registered = false, err = str(err) }) end
end

frame:SetScript("OnEvent", function(_, event, ...)
  local ok, err = pcall(function(...)
    if event == "ADDON_LOADED" then
      local name = ...
      if name == "!ILProbe" then
        ILProbeDB = type(ILProbeDB) == "table" and ILProbeDB or {}
        db = ILProbeDB
        for _, k in ipairs({ "log", "snaps", "npcs", "errors", "api", "recvCounts" }) do
          db[k] = type(db[k]) == "table" and db[k] or {}
        end
        db.session = (db.session or 0) + 1
        for _, e in ipairs(pending) do
          if e.k == "error" then db.errors[#db.errors + 1] = e.d else db.log[#db.log + 1] = e end
        end
        pending = {}
        record("session", { n = db.session })
        local okR, r = pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
        record("prefix", { ok = okR, result = str(r) })
      else
        record("addon_loaded", { name = str(name) })
      end
    elseif event == "PLAYER_LOGIN" then
      after(3, function() snapshot("login"); apiInventory() end)
      if DEFAULT_CHAT_FRAME then
        hooksecurefunc(DEFAULT_CHAT_FRAME, "AddMessage", function(_, msg)
          if readable(msg) and type(msg) == "string" and msg:lower():find("ledger")
             and not msg:find("ILProbe") then
            record("chat", { msg = msg })
          end
        end)
      end
    elseif event == "GOSSIP_SHOW" then
      onGossipShow()
    elseif event == "GOSSIP_CLOSED" then
      if probeButton then probeButton:Hide() end
    elseif event == "CHAT_MSG_ADDON" or event == "CHAT_MSG_ADDON_LOGGED" then
      onAddonMessage(event, ...)
    elseif event == "PLAYER_UPDATE_RESTING" or event == "ZONE_CHANGED_NEW_AREA" then
      record(event, { resting = call("IsResting"), map = mapChain() })
    elseif event == "PLAYER_REGEN_DISABLED" then
      record(event, { lockdown = call("InCombatLockdown") })
      send("WHISPER", selfFullName(), "combat ping")
    elseif event == "ENCOUNTER_START" or event == "ENCOUNTER_END" then
      record(event, { args = { str((...)) }, instance = call("IsInInstance") })
      if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then send("INSTANCE_CHAT", nil, "encounter ping") end
      if IsInGroup(LE_PARTY_CATEGORY_HOME) then send(IsInRaid() and "RAID" or "PARTY", nil, "encounter ping") end
    elseif event == "PLAYER_ENTERING_WORLD" then
      record(event, { instance = call("IsInInstance"), map = mapChain() })
    else
      record(event, {})
    end
  end, ...)
  if not ok then record("handler_error", { event = event, err = str(err) }) end
end)

SLASH_ILPROBE1 = "/ilp"
SlashCmdList.ILPROBE = function(input)
  local cmd = (input or ""):match("^%s*(%S*)"):lower()
  local ok, err = pcall(function()
    if cmd == "" or cmd == "all" then runAll()
    elseif cmd == "snap" then snapshot("manual")
    elseif cmd == "ping" then testPing()
    elseif cmd == "size" then testSize()
    elseif cmd == "burst" then testBurst()
    elseif cmd == "chan" then testChannel()
    elseif cmd == "edit" then testEditBox()
    elseif cmd == "roster" then testRoster()
    elseif cmd == "group" then testGroup(); send(IsInRaid() and "RAID" or "PARTY", nil, "group ping")
    else say("/ilp [all|snap|ping|size|burst|chan|edit|roster|group]") end
  end)
  if not ok then say("error: " .. str(err)); record("slash_error", { cmd = cmd, err = str(err) }) end
end
