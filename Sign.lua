-- Sign (glue): the "Sign the guestbook" button under the gossip frame at a known
-- innkeeper, the composer, and the client reads behind them. Every decision lives in
-- SignFlow (pure); this file holds events, frames, client reads and chat output.
-- Spec: docs/specs/sign.md (sections 3.7 and 3.9). Events only: nothing here hooks the
-- gossip frame, picks a gossip option or touches the fight state. Every client value is
-- checked for hidden values first, and every handler and click is guarded.
local _, ns = ...

local Sign = {}
ns.Sign = Sign

local SignFlow = ns.SignFlow
local TEXT = SignFlow.TEXT

Sign.flow = SignFlow.new({
  inns = ns.Data.Inns,
  atlas = ns.Collection.atlas,
  phrase = ns.Phrase,
  cosmetics = ns.Cosmetics,
})
Sign.ui = {}
Sign.session = nil

-- ---------------------------------------------------------------------------
-- Client reads (spec 3.9).

-- The first return of a client function, or nil if it's missing or raises.
local function call(fn, ...)
  if type(fn) ~= "function" then
    return nil
  end
  local ok, value = pcall(fn, ...)
  if ok then
    return value
  end
  return nil
end

-- True for a hidden ("secret") value. Fails closed: an error while checking counts as
-- hidden. Touches nothing else about the value.
local function hidden(value)
  if type(issecretvalue) ~= "function" then
    return false
  end
  local ok, result = pcall(issecretvalue, value)
  return not ok or result ~= false and result ~= nil
end

local function readNpc()
  local npc = call(UnitGUID, "npc")
  if hidden(npc) or type(npc) ~= "string" then
    return nil
  end
  return npc
end

local function readFaction()
  local faction = call(UnitFactionGroup, "player")
  if hidden(faction) or type(faction) ~= "string" then
    return nil
  end
  return faction
end

-- The situation SignFlow decides on. The ledger is read at use, never cached.
local function read()
  local resting = call(IsResting)
  resting = not hidden(resting) and rawequal(resting, true)
  local now = call(GetServerTime)
  if hidden(now) then
    now = nil
  end
  return { ledger = ns.ledger, npc = readNpc(), resting = resting, now = now,
    faction = readFaction() }
end

-- ---------------------------------------------------------------------------
-- Output and guards. Debug lines carry only our own codes, never an error's text.

local function debug(line)
  pcall(function() ns.Core:Debug(line) end)
end

local function say(line)
  ns.Core:Print(line)
end

local function guard(where, fn, ...)
  local ok, result = pcall(fn, ...)
  if not ok then
    debug("sign: error in " .. where)
    return nil
  end
  return result
end

-- Calls a flow function; an error or a non-table answer gives `fallback`.
local function ask(fallback, fn, ...)
  local ok, res = pcall(fn, ...)
  if ok and type(res) == "table" then
    return res
  end
  return fallback
end

local function codeOf(res)
  local code = res.reason or res.result
  if type(code) ~= "string" then
    return "error"
  end
  return code
end

-- ---------------------------------------------------------------------------
-- Frames. The composer is a DRAFT (spec 3.7): its look, layout and labels are the
-- maintainer's to decide.

local COMPOSER_W, COMPOSER_H = 380, 530
local LABEL_W = 290
local ROWS = { -- field, offset from the top
  { "v1", -64 }, { "t1", -94 }, { "cat1", -124 }, { "w1", -154 },
  { "v2", -222 }, { "c", -252 }, { "t2", -282 }, { "cat2", -312 }, { "w2", -342 },
  { "seal", -382 },
}

local function gossipFrame()
  if type(GossipFrame) == "table" then
    return GossipFrame
  end
  return nil
end

local function newButton(parent, text, width, height)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, height)
  b:SetText(text)
  return b
end

local function newText(parent, width)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  fs:SetWidth(width)
  fs:SetJustifyH("CENTER")
  fs:SetWordWrap(true)
  return fs
end

local function ensureButton()
  local ui = Sign.ui
  if ui.button then
    return ui.button
  end
  local parent = gossipFrame()
  if not parent then
    debug("sign: no gossip frame")
    return nil
  end
  local b = newButton(parent, TEXT.button, 180, 24)
  b:SetPoint("TOP", parent, "BOTTOM", 0, -4)
  b:SetScript("OnClick", function() Sign:Open() end)
  b:Hide()
  ui.button = b
  return b
end

local function ensureComposer()
  local ui = Sign.ui
  if ui.composer then
    return ui.composer
  end
  local parent = gossipFrame()
  if not parent then
    debug("sign: no gossip frame")
    return nil
  end
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(COMPOSER_W, COMPOSER_H)
  f:SetPoint("TOPLEFT", parent, "TOPRIGHT", 0, 0)
  f:EnableMouse(true)
  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0, 0, 0, 0.85)

  ui.title = newText(f, LABEL_W)
  ui.title:SetPoint("TOP", f, "TOP", 0, -14)
  ui.title:SetText(TEXT.title)
  ui.inn = newText(f, LABEL_W)
  ui.inn:SetPoint("TOP", f, "TOP", 0, -34)

  ui.rows = {}
  for _, spec in ipairs(ROWS) do
    local field, y = spec[1], spec[2]
    local prev = newButton(f, "<", 26, 22)
    prev:SetPoint("TOPLEFT", f, "TOPLEFT", 12, y)
    prev:SetScript("OnClick", function() Sign:Step(field, -1) end)
    local label = newText(f, LABEL_W)
    label:SetPoint("TOP", f, "TOP", 0, y - 4)
    local nxt = newButton(f, ">", 26, 22)
    nxt:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, y)
    nxt:SetScript("OnClick", function() Sign:Step(field, 1) end)
    ui.rows[field] = { prev = prev, label = label, next = nxt }
  end

  ui.toggle = newButton(f, TEXT.addSecond, 200, 22)
  ui.toggle:SetPoint("TOP", f, "TOP", 0, -188)
  ui.toggle:SetScript("OnClick", function() Sign:ToggleSecond() end)

  ui.preview = newText(f, COMPOSER_W - 40)
  ui.preview:SetPoint("TOP", f, "TOP", 0, -420)

  ui.sign = newButton(f, TEXT.sign, 120, 24)
  ui.sign:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 40, 16)
  ui.sign:SetScript("OnClick", function() Sign:Commit() end)
  ui.cancel = newButton(f, TEXT.cancel, 120, 24)
  ui.cancel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -40, 16)
  ui.cancel:SetScript("OnClick", function() Sign:Cancel() end)

  f:Hide()
  ui.composer = f
  return f
end

local function showRow(row, text, shown)
  row.label:SetText(text or "")
  for _, part in ipairs({ row.prev, row.label, row.next }) do
    if shown then
      part:Show()
    else
      part:Hide()
    end
  end
end

-- Copies the draft's view into the composer.
local function refresh()
  local session, ui = Sign.session, Sign.ui
  if not session or not ui.composer then
    return
  end
  local v = session.draft:view()
  if type(v) ~= "table" then
    return
  end
  ui.inn:SetText(session.name or "")
  local rows = ui.rows
  showRow(rows.v1, v.v1, v.voiceRow)
  showRow(rows.t1, v.t1, true)
  showRow(rows.cat1, v.cat1, v.word1)
  showRow(rows.w1, v.w1, v.word1)
  ui.toggle:SetText(v.second and TEXT.removeSecond or TEXT.addSecond)
  showRow(rows.v2, v.v2, v.second and v.voiceRow)
  showRow(rows.c, v.c, v.second)
  showRow(rows.t2, v.t2, v.second)
  showRow(rows.cat2, v.cat2, v.second and v.word2)
  showRow(rows.w2, v.w2, v.second and v.word2)
  showRow(rows.seal, v.seal, v.sealRow)
  ui.preview:SetText(v.preview or "")
end

-- Ends the session and hides the composer.
local function close()
  Sign.session = nil
  if Sign.ui.composer then
    Sign.ui.composer:Hide()
  end
end

-- ---------------------------------------------------------------------------
-- Events (spec 3.9).

local function onGossipShow()
  local inn = Sign.flow.innAt(readNpc())
  local button = ensureButton()
  if button then
    if inn ~= nil then
      button:Show()
    else
      button:Hide()
    end
  end
  -- The NPC changed while the composer was open: close it. The same inn keeps its draft.
  local session = Sign.session
  if session and (inn == nil or session.inn ~= inn) then
    close()
  end
end

local function onGossipClosed()
  if Sign.ui.button then
    Sign.ui.button:Hide()
  end
  close()
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
  if event == "GOSSIP_SHOW" then
    guard("gossip show", onGossipShow)
  elseif event == "GOSSIP_CLOSED" then
    guard("gossip closed", onGossipClosed)
  end
end)
events:RegisterEvent("GOSSIP_SHOW")
events:RegisterEvent("GOSSIP_CLOSED")
Sign.events = events

-- ---------------------------------------------------------------------------
-- Clicks.

local function open()
  local flow = Sign.flow
  local s = read()
  local res = ask({ ok = false, reason = "error" }, flow.check, s)
  if res.ok ~= true then
    say(SignFlow.message(res))
    debug("sign: " .. codeOf(res))
    return
  end
  local session = Sign.session
  if session and session.inn == res.inn and not session.done then
    return -- a double click keeps the draft
  end
  close()
  local draft = flow.newDraft(flow.seals(s))
  if type(draft) ~= "table" then
    say(SignFlow.message({ reason = "no_phrases" }))
    debug("sign: no_phrases")
    return
  end
  if not ensureComposer() then
    return
  end
  Sign.session = { inn = res.inn, name = res.name, draft = draft, done = false }
  Sign.ui.composer:Show()
  refresh()
end

local function commit()
  local session = Sign.session
  if not session or session.done then
    return
  end
  local draft = session.draft
  local res = ask({ result = "error" }, Sign.flow.commit, read(), session.inn, draft:ids(),
    draft:seal())
  local code = codeOf(res)
  if code == "added" then
    session.done = true
    close()
    if not pcall(function() ns.Sync:WindowChanged() end) then
      debug("sign: error in sync")
    end
    say(SignFlow.message(res, session.name))
    debug("sign: added")
    return
  end
  say(SignFlow.message(res, session.name))
  debug("sign: " .. code)
  if code == "changed" then
    close()
  end
end

local function step(field, delta)
  local session = Sign.session
  if session and not session.done then
    session.draft:step(field, delta)
    refresh()
  end
end

local function toggleSecond()
  local session = Sign.session
  if session and not session.done then
    local v = session.draft:view()
    session.draft:setSecond(not (type(v) == "table" and v.second))
    refresh()
  end
end

-- The gossip button: checks, then opens the composer (or says why it can't).
function Sign.Open() -- called as Sign:Open()
  guard("open", open)
end

-- The composer's Sign button: one own entry, then Sync announces it.
function Sign.Commit() -- called as Sign:Commit()
  guard("commit", commit)
end

function Sign.Cancel() -- called as Sign:Cancel()
  guard("cancel", close)
end

function Sign.Step(_, field, delta) -- called as Sign:Step(field, delta)
  guard("step", step, field, delta)
end

function Sign.ToggleSecond() -- called as Sign:ToggleSecond()
  guard("toggle", toggleSecond)
end

-- Core calls this at login for a writable ledger (spec 3.5). Returns the IDs recorded.
function Sign.RecordUnlocks() -- called as Sign:RecordUnlocks()
  return guard("login", function()
    return Sign.flow.recordUnlocks(ns.ledger, readFaction())
  end)
end
