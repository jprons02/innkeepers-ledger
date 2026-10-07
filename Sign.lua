-- Sign (glue): the "Sign the guestbook" and "Read the guestbook" buttons under the gossip
-- frame at a known innkeeper, the composer, and the client reads behind them. Every
-- decision lives in SignFlow (pure); this file holds events, frames, client reads and chat
-- output. Specs: docs/specs/sign.md (sections 3.7 and 3.9), docs/specs/book.md (3.12).
-- Events only: nothing here hooks the
-- gossip frame, picks a gossip option or touches the fight state. Every client value is
-- checked for hidden values first, and every handler and click is guarded.
local _, ns = ...

local Sign = {}
ns.Sign = Sign

local SignFlow = ns.SignFlow
local TEXT = SignFlow.TEXT
local floor = math.floor

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
-- maintainer's to decide. It edits one line at a time through lists (line tabs, a voice
-- strip, a conjunction strip on line 2, templates, categories and words); only the seal
-- keeps its < > cycler. Core frame API only: buttons, font strings, textures and the
-- mouse wheel, no dropdowns or scroll templates.

local COMPOSER_W, COMPOSER_H = 420, 600
local LABEL_W = 320
local ROW_H = 17                -- a list row
local STRIP_W, STRIP_H = 92, 20 -- a voice or conjunction button, 4 per row
local PAGE_W, PAGE_H = 24, 20   -- a list's < and > buttons
local SELECTED = { 1, 0.82, 0, 0.25 } -- the faint gold behind a list's chosen row

-- The lists (spec 3.7), at fixed positions: a hidden one leaves a gap. `strip` lists are
-- rows of buttons (the chosen one disabled); the others are rows of text with a mark.
-- x, y: the list's top left in the composer; w: its width; n: how many items it shows.
local LISTS = {
  voice = { strip = true, x = 12, y = -76, n = 8 },
  conj = { strip = true, x = 12, y = -124, n = 8 },
  template = { x = 12, y = -174, w = 364, n = 8 },
  cat = { x = 12, y = -318, w = 140, n = 9 },
  word = { x = 182, y = -318, w = 194, n = 9 },
}
local LIST_ORDER = { "voice", "conj", "template", "cat", "word" }

-- The draft field a list edits on line `k`.
local function fieldOf(key, k)
  if key == "voice" then
    return "v" .. k
  elseif key == "conj" then
    return "c"
  elseif key == "template" then
    return "t" .. k
  elseif key == "cat" then
    return "cat" .. k
  end
  return "w" .. k
end

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

local function shown(region, on)
  if on then
    region:Show()
  else
    region:Hide()
  end
end

-- The two buttons under the gossip frame, side by side: Sign (left) and Read (right).
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
  local b = newButton(parent, TEXT.button, 160, 24)
  b:SetPoint("TOPRIGHT", parent, "BOTTOM", -3, -4)
  b:SetScript("OnClick", function() Sign:Open() end)
  b:Hide()
  local r = newButton(parent, TEXT.read, 160, 24)
  r:SetPoint("TOPLEFT", parent, "BOTTOM", 3, -4)
  r:SetScript("OnClick", function() Sign:Read() end)
  r:Hide()
  ui.button, ui.read = b, r
  return b
end

-- Shows or hides both buttons together.
local function showButtons(on)
  for _, b in ipairs({ Sign.ui.button, Sign.ui.read }) do
    if on then
      b:Show()
    else
      b:Hide()
    end
  end
end

-- A list: a frame of `spec.n` rows, its < > page buttons, and the mouse wheel. A row
-- click picks the row's item; which field that is depends on the line being edited.
local function newList(parent, key, spec)
  local list = { rows = {} }
  local n = spec.n
  local strip = spec.strip
  local width = strip and 4 * (STRIP_W + 2) - 2 or spec.w
  local height = strip and 2 * (STRIP_H + 2) - 2 or n * ROW_H
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(width, height)
  f:SetPoint("TOPLEFT", parent, "TOPLEFT", spec.x, spec.y)
  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function(_, delta) Sign:Wheel(key, delta) end)
  list.frame = f
  for i = 1, n do
    local row = {}
    local b
    if strip then
      local col, r = (i - 1) % 4, floor((i - 1) / 4)
      b = newButton(f, "", STRIP_W, STRIP_H)
      b:SetPoint("TOPLEFT", f, "TOPLEFT", col * (STRIP_W + 2), -r * (STRIP_H + 2))
    else
      b = CreateFrame("Button", nil, f)
      b:SetSize(width, ROW_H)
      b:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -(i - 1) * ROW_H)
      row.mark = b:CreateTexture(nil, "BACKGROUND")
      row.mark:SetAllPoints()
      row.mark:SetColorTexture(SELECTED[1], SELECTED[2], SELECTED[3], SELECTED[4])
      row.mark:Hide()
      row.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      row.text:SetPoint("LEFT", b, "LEFT", 4, 0)
      row.text:SetWidth(width - 8)
      row.text:SetJustifyH("LEFT")
      row.text:SetWordWrap(false)
    end
    row.button = b
    b:SetScript("OnClick", function() Sign:Pick(key, row.index) end)
    list.rows[i] = row
  end
  -- Page buttons: right of the list (a strip's stacked at its right end).
  list.prev = newButton(f, "<", PAGE_W, PAGE_H)
  list.prev:SetPoint("TOPLEFT", f, "TOPRIGHT", 4, 0)
  list.prev:SetScript("OnClick", function() Sign:Scroll(key, -n) end)
  list.next = newButton(f, ">", PAGE_W, PAGE_H)
  list.next:SetPoint("BOTTOMLEFT", f, "BOTTOMRIGHT", 4, 0)
  list.next:SetScript("OnClick", function() Sign:Scroll(key, n) end)
  list.count = n
  return list
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
  ui.title:SetPoint("TOP", f, "TOP", 0, -10)
  ui.title:SetText(TEXT.title)
  ui.inn = newText(f, LABEL_W)
  ui.inn:SetPoint("TOP", f, "TOP", 0, -28)

  -- The line tabs and the second line's toggle.
  ui.line1 = newButton(f, TEXT.firstLine, 100, 22)
  ui.line1:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -48)
  ui.line1:SetScript("OnClick", function() Sign:SetLine(1) end)
  ui.line2 = newButton(f, TEXT.secondLine, 100, 22)
  ui.line2:SetPoint("TOPLEFT", f, "TOPLEFT", 116, -48)
  ui.line2:SetScript("OnClick", function() Sign:SetLine(2) end)
  ui.toggle = newButton(f, TEXT.addSecond, 180, 22)
  ui.toggle:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -48)
  ui.toggle:SetScript("OnClick", function() Sign:ToggleSecond() end)

  ui.lists = {}
  for _, key in ipairs(LIST_ORDER) do
    ui.lists[key] = newList(f, key, LISTS[key])
  end

  -- The seal row keeps its cycler.
  local prev = newButton(f, "<", 26, 22)
  prev:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -478)
  prev:SetScript("OnClick", function() Sign:Step("seal", -1) end)
  local label = newText(f, LABEL_W)
  label:SetPoint("TOP", f, "TOP", 0, -482)
  local nxt = newButton(f, ">", 26, 22)
  nxt:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -478)
  nxt:SetScript("OnClick", function() Sign:Step("seal", 1) end)
  ui.rows = { seal = { prev = prev, label = label, next = nxt } }

  ui.preview = newText(f, COMPOSER_W - 30)
  ui.preview:SetPoint("TOP", f, "TOP", 0, -508)

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

-- Copies one window of the draft's list into a list's rows; hides the list when `on` is
-- false or the draft has no window for it.
local function drawList(list, draft, field, on)
  local w = on and draft:list(field, list.count) or nil
  if type(w) ~= "table" then
    list.frame:Hide()
    for _, row in ipairs(list.rows) do
      row.index = nil
      row.button:Hide()
    end
    list.prev:Hide()
    list.next:Hide()
    return
  end
  list.frame:Show()
  for i, row in ipairs(list.rows) do
    local item = w.items[i]
    row.index = item and item.index or nil
    shown(row.button, item ~= nil)
    if item then
      local text = type(item.text) == "string" and item.text or ""
      if row.text then
        row.text:SetText(text)
        shown(row.mark, item.selected == true)
      else
        row.button:SetText(text)
        if item.selected == true then
          row.button:Disable()
        else
          row.button:Enable()
        end
      end
    end
  end
  local paged = w.total > list.count
  shown(list.prev, paged)
  shown(list.next, paged)
  if w.first > 1 then
    list.prev:Enable()
  else
    list.prev:Disable()
  end
  if w.first + list.count - 1 < w.total then
    list.next:Enable()
  else
    list.next:Disable()
  end
end

local function setTab(tab, on, selected)
  shown(tab, on)
  if selected then
    tab:Disable()
  else
    tab:Enable()
  end
end

-- Copies the draft's view and the edited line's lists into the composer.
local function refresh()
  local session, ui = Sign.session, Sign.ui
  if not session or not ui.composer then
    return
  end
  local draft = session.draft
  local v = draft:view()
  if type(v) ~= "table" then
    return
  end
  ui.inn:SetText(session.name or "")
  local k = v.line == 2 and v.second and 2 or 1
  setTab(ui.line1, true, k == 1)
  setTab(ui.line2, v.second, k == 2)
  ui.toggle:SetText(v.second and TEXT.removeSecond or TEXT.addSecond)
  local lists = ui.lists
  local word = k == 1 and v.word1 or k == 2 and v.word2
  drawList(lists.voice, draft, fieldOf("voice", k), v.voiceRow)
  drawList(lists.conj, draft, fieldOf("conj", k), k == 2)
  drawList(lists.template, draft, fieldOf("template", k), true)
  drawList(lists.cat, draft, fieldOf("cat", k), word)
  drawList(lists.word, draft, fieldOf("word", k), word)
  local seal = ui.rows.seal
  seal.label:SetText(v.seal or "")
  for _, part in ipairs({ seal.prev, seal.label, seal.next }) do
    shown(part, v.sealRow)
  end
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
  if ensureButton() then
    showButtons(inn ~= nil)
  end
  -- The NPC changed while the composer was open: close it. The same inn keeps its draft.
  local session = Sign.session
  if session and (inn == nil or session.inn ~= inn) then
    close()
  end
end

local function onGossipClosed()
  if Sign.ui.button then
    showButtons(false)
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
    if not pcall(function() ns.Book:Changed() end) then
      debug("sign: error in book")
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

-- The field a list edits now, from the line the draft says is being edited.
local function listField(draft, key)
  local v = draft:view()
  local k = type(v) == "table" and v.line == 2 and 2 or 1
  return fieldOf(key, k)
end

local function pick(key, index)
  local session = Sign.session
  if session and not session.done and LISTS[key] and index ~= nil then
    session.draft:pick(listField(session.draft, key), index)
    refresh()
  end
end

local function scroll(key, delta)
  local session = Sign.session
  if session and not session.done and LISTS[key] then
    session.draft:scroll(listField(session.draft, key), delta, LISTS[key].n)
    refresh()
  end
end

local function setLine(k)
  local session = Sign.session
  if session and not session.done then
    session.draft:setLine(k)
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

-- The Read button: opens the book on this innkeeper's inn. It never signs, checks resting
-- or picks a gossip option.
function Sign.Read() -- called as Sign:Read()
  guard("read", function()
    ns.Book:OpenInn(Sign.flow.innAt(readNpc()))
  end)
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

-- A list row: picks the item at `index` in the list `key` ("voice", "conj", "template",
-- "cat", "word") of the line being edited.
function Sign.Pick(_, key, index) -- called as Sign:Pick(key, index)
  guard("pick", pick, key, index)
end

-- A list's page buttons: moves its window by `delta` rows.
function Sign.Scroll(_, key, delta) -- called as Sign:Scroll(key, delta)
  guard("scroll", scroll, key, delta)
end

-- The mouse wheel over a list: a delta of 1 (up) moves the window one row up.
function Sign.Wheel(_, key, delta) -- called as Sign:Wheel(key, delta)
  guard("wheel", function()
    if type(delta) == "number" then
      scroll(key, -delta)
    end
  end)
end

function Sign.SetLine(_, k) -- called as Sign:SetLine(k)
  guard("line", setLine, k)
end

-- Core calls this at login for a writable ledger (spec 3.5). Returns the IDs recorded.
function Sign.RecordUnlocks() -- called as Sign:RecordUnlocks()
  return guard("login", function()
    return Sign.flow.recordUnlocks(ns.ledger, readFaction())
  end)
end
