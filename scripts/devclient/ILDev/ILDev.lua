-- ILDev: the dev harness (#139). Never packaged, never released (it lives under scripts/,
-- which the packager ignores). It runs a "tour" of the AddOn's UI that a deploy wrote into
-- Request.lua: open the book, click tabs and page buttons, take a screenshot and dump the
-- real layout at each step. Everything lands in ILDevDB (written on reload or logout) and
-- the client's Screenshots folder, where an agent reads it (scripts/devclient/read.lua).
--
-- Rules it keeps:
--   * A fixed step vocabulary over allow-listed targets: the /ledger command, and clicks
--     and hides under the book or the gossip window only. Request.lua is itself Lua (the
--     client runs every file in AddOns/), but the steps it lists are data: none is
--     evaluated, and a step outside the vocabulary or the allow-lists is refused.
--   * It drives the AddOn only from outside: its slash command, its named book frame and
--     plain button clicks. The AddOn has no dev hooks.
--   * It never clicks the composer's commit button, and in the gossip window it clicks
--     only the AddOn's own buttons (never a gossip option).
--   * Watch mode (reload on a timer to pick up new deploys) is switched on in game by the
--     player, and only reloads while the player is resting and away (AFK).
local ADDON = "ILDev"

local db -- ILDevDB once loaded
local run -- the run in progress (db.run)
local busy = false
local shotWaiter -- function waiting for SCREENSHOT_SUCCEEDED / _FAILED
local savedQuality -- the player's screenshotQuality while a tour runs
local watchChain = 0 -- the live watch timer chain; older chains stop

local LOGIN_DELAY = 4 -- seconds after login before a tour starts (the ledger opens at login)
local SHOT_TIMEOUT = 6
local SHOT_GAP = 1.2 -- screenshot files are named to the second
local SETTLE = 0.3 -- after a click, before the next step
local MAX_NODES = 1500 -- per dump
local MAX_DEPTH = 12
local WATCH_HOURS = 3
local WATCH_MIN = 30 -- seconds; a shorter interval would leave no time to type at login

-- The only slash command a tour runs, and the only frames it clicks in or hides.
local SLASH_OK = { ["/ledger"] = true }
local ROOT_OK = { InnkeepersLedgerBook = true, GossipFrame = true }
-- AddOns whose blocked actions are recorded: the harness drives the AddOn's handlers.
local WATCHED = { ILDev = true, InnkeepersLedger = true }

-- Texts never clicked: the composer's commit button.
local NEVER = { ["Sign"] = true }
-- In the gossip window, only these (the AddOn's own buttons) may be clicked.
local GOSSIP_OK = {
  ["Sign the guestbook"] = true, ["Read the guestbook"] = true,
  ["First line"] = true, ["Second line"] = true,
  ["Add a second line"] = true, ["Remove the second line"] = true,
  ["Cancel"] = true, ["<"] = true, [">"] = true,
}

local function now()
  return GetTime()
end

local function note(op, ok, text)
  if run then
    run.steps[#run.steps + 1] = { t = math.floor((now() - run.t0) * 10) / 10,
      op = op, ok = ok and true or false, note = text }
  end
end

local function say(text)
  DEFAULT_CHAT_FRAME:AddMessage("|cff88ccffILDev|r " .. text)
end

local abort -- defined with the runs, below

local function after(sec, fn)
  C_Timer.After(sec, function()
    local ok, err = pcall(fn)
    if not ok then
      abort(err)
    end
  end)
end

-- ---------------------------------------------------------------------------
-- Frames and geometry. Rects are in UIParent units: left, bottom, width, height.

local function root(name)
  local f = type(name) == "string" and _G[name] or nil
  if type(f) == "table" and type(f.GetObjectType) == "function" then
    return f
  end
  return nil
end

local function round(x)
  if type(x) ~= "number" then
    return nil
  end
  return math.floor(x * 10 + 0.5) / 10
end

local function rectOf(r)
  local ok, l, b, w, h = pcall(r.GetRect, r)
  if not ok or type(l) ~= "number" then
    return nil
  end
  -- A region without its own scale draws at its parent's.
  local scaled = r.GetEffectiveScale and r or r:GetParent()
  local es = scaled and scaled.GetEffectiveScale and scaled:GetEffectiveScale()
    or UIParent:GetEffectiveScale()
  local k = es / UIParent:GetEffectiveScale()
  return { round(l * k), round(b * k), round(w * k), round(h * k) }
end

local function children(f)
  local out = {}
  if f.GetChildren then
    for _, c in ipairs({ f:GetChildren() }) do
      out[#out + 1] = c
    end
  end
  return out
end

local function regions(f)
  local out = {}
  if f.GetRegions then
    for _, r in ipairs({ f:GetRegions() }) do
      out[#out + 1] = r
    end
  end
  return out
end

-- Union of the shown frames and regions under `f` (itself included), for cropping.
local function bounds(f)
  local l, b, r, t
  local function add(x)
    local ok, vis = pcall(x.IsVisible, x)
    if not ok or not vis then
      return
    end
    local rc = rectOf(x)
    if not rc or rc[3] <= 0 or rc[4] <= 0 then
      return
    end
    l = l and math.min(l, rc[1]) or rc[1]
    b = b and math.min(b, rc[2]) or rc[2]
    r = r and math.max(r, rc[1] + rc[3]) or rc[1] + rc[3]
    t = t and math.max(t, rc[2] + rc[4]) or rc[2] + rc[4]
  end
  local function walk(x, depth)
    add(x)
    if depth >= MAX_DEPTH then
      return
    end
    for _, rg in ipairs(regions(x)) do
      add(rg)
    end
    for _, c in ipairs(children(x)) do
      walk(c, depth + 1)
    end
  end
  walk(f, 0)
  if not l then
    return nil
  end
  return { l, b, r - l, t - b }
end

local function textOf(x)
  if x.GetText then
    local ok, s = pcall(x.GetText, x)
    if ok and type(s) == "string" then
      return s
    end
  end
  return nil
end

-- Shown buttons under `f` whose text is `text`, top to bottom, then left to right.
local function buttons(f, text)
  local found = {}
  local function walk(x, depth)
    local kind = x.GetObjectType and x:GetObjectType()
    if (kind == "Button" or kind == "CheckButton") and x:IsVisible() and textOf(x) == text then
      found[#found + 1] = x
    end
    if depth < MAX_DEPTH then
      for _, c in ipairs(children(x)) do
        walk(c, depth + 1)
      end
    end
  end
  walk(f, 0)
  table.sort(found, function(a, b)
    local ta, tb = a:GetTop() or 0, b:GetTop() or 0
    if math.abs(ta - tb) > 1 then
      return ta > tb
    end
    return (a:GetLeft() or 0) < (b:GetLeft() or 0)
  end)
  return found
end

-- ---------------------------------------------------------------------------
-- The layout dump: one node per frame and region, with what decides how it draws.

local function points(x)
  local out = {}
  local ok, n = pcall(x.GetNumPoints, x)
  if not ok or type(n) ~= "number" then
    return out
  end
  for i = 1, n do
    local p, rel, rp, px, py = x:GetPoint(i)
    local relName
    if rel == nil then
      relName = "nil"
    elseif rel == x:GetParent() then
      relName = "parent"
    else
      relName = (rel.GetName and rel:GetName()) or tostring(rel.GetObjectType and
        rel:GetObjectType() or "?")
    end
    out[#out + 1] = { p, relName, rp, round(px), round(py) }
  end
  return out
end

local function dumpNode(x, depth, count)
  count.n = count.n + 1
  if count.n > MAX_NODES then
    return nil
  end
  local node = {
    k = x:GetObjectType(),
    name = x.GetName and x:GetName() or nil,
    shown = x.IsShown and x:IsShown() or nil,
    vis = x.IsVisible and x:IsVisible() or nil,
    r = rectOf(x),
    a = x.GetAlpha and round(x:GetAlpha()) or nil,
    pts = points(x),
  }
  if x.GetFrameStrata then
    node.strata = x:GetFrameStrata()
    node.level = x:GetFrameLevel()
  end
  if x.GetDrawLayer then
    local layer, sub = x:GetDrawLayer()
    node.layer = layer
    node.sub = sub
  end
  local text = textOf(x)
  if text and text ~= "" then
    node.text = text
  end
  if x:GetObjectType() == "FontString" then
    node.sw = round(x:GetStringWidth())
    node.sh = round(x:GetStringHeight())
    node.trunc = x.IsTruncated and x:IsTruncated() or nil
    local file, size = x:GetFont()
    node.font = file and (tostring(file) .. " " .. tostring(round(size))) or nil
    node.color = { x:GetTextColor() }
    for i, c in ipairs(node.color) do
      node.color[i] = round(c)
    end
  elseif x:GetObjectType() == "Texture" then
    local ok, tex = pcall(x.GetTexture, x)
    node.tex = ok and tex ~= nil and tostring(tex) or nil
    local ok2, a, b, c, d, e, f, g, h = pcall(x.GetTexCoord, x)
    if ok2 and a then
      node.tc = { round(a), round(b), round(c), round(d), round(e), round(f), round(g),
        round(h) }
    end
    node.color = { x:GetVertexColor() }
    for i, v in ipairs(node.color) do
      node.color[i] = round(v)
    end
  end
  if x.IsEnabled then
    node.enabled = x:IsEnabled() and true or false
  end
  if depth < MAX_DEPTH then
    local kids = {}
    for _, rg in ipairs(regions(x)) do
      kids[#kids + 1] = dumpNode(rg, depth + 1, count)
    end
    for _, c in ipairs(children(x)) do
      kids[#kids + 1] = dumpNode(c, depth + 1, count)
    end
    if #kids > 0 then
      node.kids = kids
    end
  end
  return node
end

-- ---------------------------------------------------------------------------
-- Steps. Each takes the step table and `next`, and calls `next()` when done.

local function slashCommand(cmd)
  cmd = cmd:lower()
  for key, fn in pairs(SlashCmdList) do
    for i = 1, 9 do
      local alias = _G["SLASH_" .. key .. i]
      if alias == nil then
        break
      end
      if type(alias) == "string" and alias:lower() == cmd then
        return fn
      end
    end
  end
  return nil
end

local steps = {}

function steps.slash(s, nextStep)
  local cmd = type(s[2]) == "string" and s[2]:lower() or nil
  local fn = cmd and SLASH_OK[cmd] and slashCommand(cmd) or nil
  if not (cmd and SLASH_OK[cmd]) then
    note("slash " .. tostring(s[2]), false, "refused: not an allowed command")
  elseif not fn then
    note("slash " .. tostring(s[2]), false, "no such command")
  else
    local ok, err = pcall(fn, s[3] or "")
    note("slash " .. s[2] .. " " .. (s[3] or ""), ok, not ok and tostring(err) or nil)
  end
  after(SETTLE, nextStep)
end

function steps.wait(s, nextStep)
  after(tonumber(s[2]) or 1, nextStep)
end

function steps.hide(s, nextStep)
  local f = ROOT_OK[s[2]] and root(s[2]) or nil
  if f then
    f:Hide()
  end
  note("hide " .. tostring(s[2]), f ~= nil)
  after(SETTLE, nextStep)
end

local function click(rootName, text, n)
  if not ROOT_OK[rootName] then
    return false, "refused: not an allowed frame"
  end
  if type(text) ~= "string" or text == "" then
    return false, "refused: no button text"
  end
  local f = root(rootName)
  if not f then
    return false, "no frame " .. tostring(rootName)
  end
  if NEVER[text] then
    return false, "refused: never clicks " .. text
  end
  if rootName == "GossipFrame" and not GOSSIP_OK[text] then
    return false, "refused: not one of the AddOn's buttons"
  end
  local list = buttons(f, text)
  local b = list[n or 1]
  if not b then
    return false, ("no shown button %q (#%d of %d)"):format(text, n or 1, #list)
  end
  if not b:IsEnabled() then
    return false, "disabled"
  end
  b:Click()
  return true
end

function steps.click(s, nextStep)
  local ok, why = click(s[2], s[3], s[4])
  note(("click %s %q %s"):format(tostring(s[2]), tostring(s[3]), tostring(s[4] or 1)), ok, why)
  after(SETTLE, nextStep)
end

-- The screenshot's crop box in pixels of the physical screen, for crop.ps1.
local function cropBox(name)
  local f = root(name)
  local rc = f and bounds(f)
  if not rc then
    return nil
  end
  local pw, ph = GetPhysicalScreenSize()
  local k = pw / UIParent:GetWidth()
  local pad = 8
  local x = math.max(0, math.floor(rc[1] * k) - pad)
  local y = math.max(0, math.floor(ph - (rc[2] + rc[4]) * k) - pad)
  return { x = x, y = y, w = math.min(pw - x, math.ceil(rc[3] * k) + 2 * pad),
    h = math.min(ph - y, math.ceil(rc[4] * k) + 2 * pad), screenW = pw, screenH = ph }
end

local function shoot(label, cropName, nextStep)
  local shot = { label = label, crop = cropName and cropBox(cropName) or nil }
  run.shots[#run.shots + 1] = shot
  local done = false
  local function finish(ok, why)
    if done then
      return
    end
    done = true
    shotWaiter = nil
    shot.ok = ok
    shot.stamp = date("%m%d%y_%H%M%S")
    note("shot " .. label, ok, why)
    after(SHOT_GAP, nextStep)
  end
  shotWaiter = finish
  local ok, err = pcall(Screenshot)
  if not ok then
    finish(false, "Screenshot() raised: " .. tostring(err))
    return
  end
  after(SHOT_TIMEOUT, function() finish(false, "timed out") end)
end

function steps.shot(s, nextStep)
  shoot(s[2] or ("shot" .. (#run.shots + 1)), s[3], nextStep)
end

function steps.dump(s, nextStep)
  local f = root(s[3])
  if not f then
    note("dump " .. tostring(s[2]), false, "no frame " .. tostring(s[3]))
  else
    local count = { n = 0 }
    run.dumps[s[2]] = dumpNode(f, 0, count)
    note("dump " .. s[2], count.n <= MAX_NODES, count.n .. " nodes")
  end
  after(0, nextStep)
end

-- { "pages", root, buttonText, label, crop, max, n }: screenshot and dump, then click the
-- button while it's enabled (up to max times).
function steps.pages(s, nextStep)
  local i = 0
  local max = tonumber(s[6]) or 5
  local function one()
    i = i + 1
    local label = s[4] .. i
    local count = { n = 0 }
    run.dumps[label] = dumpNode(root(s[2]) or UIParent, 0, count)
    shoot(label, s[5], function()
      if i >= max then
        nextStep()
        return
      end
      local ok, why = click(s[2], s[3], s[7])
      if not ok then
        note("pages " .. s[4] .. " stop", true, why)
        nextStep()
        return
      end
      after(SETTLE, one)
    end)
  end
  one()
end

-- ---------------------------------------------------------------------------
-- Runs.

local function restoreQuality()
  if savedQuality ~= nil then
    SetCVar("screenshotQuality", savedQuality)
    savedQuality = nil
  end
end

local function finishRun()
  if run.finished then
    return
  end
  restoreQuality()
  run.finished = time()
  busy = false
  say(("tour done: %d steps, %d shots, %d errors."):format(#run.steps, #run.shots,
    #run.errors))
  db.autoReload = { tried = time() }
  say("saving: reloading the UI.")
  C_Timer.After(1, function()
    local reload = (C_UI and C_UI.Reload) or ReloadUI
    pcall(reload)
  end)
  -- If the reload is blocked, say so; a typed /reload saves the results.
  C_Timer.After(4, function()
    db.autoReload = nil
    say("the automatic reload didn't happen; type /reload to save the results.")
  end)
end

-- A step raised from a timer: the run ends there, with what it has.
abort = function(err)
  note("error", false, tostring(err))
  if run and not run.finished then
    finishRun()
  end
  busy = false
end

-- The tours' steps in order, with a "mark" before each tour. Raises on a malformed tour.
local function queueOf(req, only)
  local queue = {}
  for _, tour in ipairs(req.tours) do
    if only == nil or tour.name == only then
      local need = tour.need and root(tour.need)
      if tour.need and not (need and need:IsVisible()) then
        queue[#queue + 1] = { "skip", tour.name, tour.need }
      else
        queue[#queue + 1] = { "mark", tour.name }
        for _, s in ipairs(tour.steps or {}) do
          queue[#queue + 1] = s
        end
      end
    end
  end
  return queue
end

local function runTours(only)
  local req = ILDevRequest
  if type(req) ~= "table" or type(req.tours) ~= "table" then
    say("no request (deploy one with scripts/devclient/deploy.sh).")
    return
  end
  if busy then
    say("a tour is already running.")
    return
  end
  local okQueue, queue = pcall(queueOf, req, only)
  if not okQueue then
    say("the request is malformed: " .. tostring(queue))
    return
  end
  busy = true
  run = { id = req.id, started = time(), t0 = now(), steps = {}, shots = {}, dumps = {},
    errors = {}, only = only }
  db.run = run
  db.lastId = req.id
  local pw, ph = GetPhysicalScreenSize()
  run.client = { build = select(1, GetBuildInfo()), interface = select(4, GetBuildInfo()),
    screen = { pw, ph }, ui = { round(UIParent:GetWidth()), round(UIParent:GetHeight()) },
    uiScale = round(UIParent:GetEffectiveScale()) }
  savedQuality = GetCVar("screenshotQuality")
  SetCVar("screenshotQuality", "10")
  local i = 0
  local nextStep
  nextStep = function()
    i = i + 1
    local s = queue[i]
    if s == nil then
      finishRun()
      return
    end
    if type(s) ~= "table" then
      note("step " .. i, false, "not a table")
      nextStep()
      return
    end
    if s[1] == "mark" or s[1] == "skip" then
      note("tour " .. tostring(s[2]), s[1] == "mark",
        s[1] == "skip" and ("skipped: " .. tostring(s[3]) .. " not shown") or nil)
      nextStep()
      return
    end
    local fn = steps[s[1]]
    if not fn then
      note("unknown step " .. tostring(s[1]), false)
      nextStep()
      return
    end
    -- Each step moves the run on once, even if it raises after scheduling its next.
    local moved = false
    local function go()
      if not moved then
        moved = true
        nextStep()
      end
    end
    local ok, err = pcall(fn, s, go)
    if not ok then
      note("step " .. tostring(s[1]) .. " raised", false, tostring(err))
      after(0, go)
    end
  end
  say("tour " .. tostring(req.id) .. " starting.")
  nextStep()
end

-- ---------------------------------------------------------------------------
-- Watch mode: reload every `watch` seconds while resting and AFK, so a new deploy is
-- picked up without anyone at the keyboard.

local function watchOk()
  return db.watchUntil and time() < db.watchUntil and IsResting() and UnitIsAFK("player")
    and not InCombatLockdown()
end

local function scheduleWatch(chain)
  if chain == nil then
    watchChain = watchChain + 1
    chain = watchChain
  end
  local req = ILDevRequest
  local every = math.max(WATCH_MIN, type(req) == "table" and tonumber(req.watch) or 60)
  C_Timer.After(every, function()
    if chain ~= watchChain or not db.watchUntil then
      return
    end
    if busy then
      scheduleWatch(chain)
      return
    end
    if watchOk() then
      db.autoReload = { tried = time() }
      local reload = (C_UI and C_UI.Reload) or ReloadUI
      reload()
    elseif time() >= db.watchUntil then
      db.watchUntil = nil
      say("watch mode ended (time limit).")
    else
      scheduleWatch(chain)
    end
  end)
end

-- ---------------------------------------------------------------------------
-- Events and the slash command.

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("SCREENSHOT_SUCCEEDED")
events:RegisterEvent("SCREENSHOT_FAILED")
events:RegisterEvent("ADDON_ACTION_BLOCKED")
events:RegisterEvent("ADDON_ACTION_FORBIDDEN")
events:SetScript("OnEvent", function(_, event, a1, a2)
  if event == "ADDON_LOADED" and a1 == ADDON then
    ILDevDB = type(ILDevDB) == "table" and ILDevDB or {}
    db = ILDevDB
    -- Did the last automatic reload happen? A load within 20 s of trying says yes.
    if type(db.autoReload) == "table" then
      db.reloadWorked = (time() - (db.autoReload.tried or 0)) < 20
      db.autoReload = nil
    end
    local handler = geterrorhandler()
    seterrorhandler(function(msg, ...)
      if run and #run.errors < 50 then
        run.errors[#run.errors + 1] = tostring(msg):sub(1, 400)
      end
      return handler(msg, ...)
    end)
  elseif event == "PLAYER_LOGIN" then
    local req = ILDevRequest
    if type(req) == "table" and req.id and req.id ~= db.lastId then
      C_Timer.After(LOGIN_DELAY, function() runTours() end)
    end
    if db.watchUntil then
      scheduleWatch()
    end
  elseif event == "SCREENSHOT_SUCCEEDED" or event == "SCREENSHOT_FAILED" then
    if shotWaiter then
      local ok, err = pcall(shotWaiter, event == "SCREENSHOT_SUCCEEDED",
        event ~= "SCREENSHOT_SUCCEEDED" and event or nil)
      if not ok then
        abort(err)
      end
    end
  elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
    if WATCHED[a1] then
      db.blocked = db.blocked or {}
      db.blocked[#db.blocked + 1] = event .. " " .. tostring(a1) .. " " .. tostring(a2)
    end
  end
end)

SLASH_ILDEV1 = "/ildev"
SlashCmdList.ILDEV = function(input)
  local cmd, arg = (input or ""):match("^%s*(%S*)%s*(%S*)")
  cmd = cmd:lower()
  if cmd == "run" then
    runTours(arg ~= "" and arg or nil)
  elseif cmd == "watch" then
    if arg == "off" then
      db.watchUntil = nil
      watchChain = watchChain + 1
      say("watch mode off.")
    else
      db.watchUntil = time() + WATCH_HOURS * 3600
      say(("watch mode on for %d hours: reloads while you're resting and AFK."):format(
        WATCH_HOURS))
      scheduleWatch()
    end
  else
    local req = ILDevRequest
    say(("request %s, last run %s, watch %s, auto reload worked: %s."):format(
      type(req) == "table" and tostring(req.id) or "none", tostring(db.lastId),
      db.watchUntil and "on" or "off", tostring(db.reloadWorked)))
    say("/ildev run [tour] | /ildev watch [off]")
  end
end
