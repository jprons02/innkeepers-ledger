-- Book (glue): the parchment book. Two pages in a dark frame, four tabs (Inns, Collection,
-- Cosmetics, Share), page turns, the Share page's edit box and checkbox, and the book's
-- own saved record (the chosen quill, the last share). Every decision lives in BookView
-- (pure); this file holds the frames, the client reads and the drawing of BookView's
-- models. Spec: docs/specs/book.md (section 3.11).
-- Core frame API only: no templates but UIPanelButtonTemplate, no menus, no scrolling, no
-- timer, no keyboard capture. Every client value is checked for hidden values first, and
-- every handler, click and refresh is guarded. Peer names reach a font string only as
-- BookView.plain returned them; nothing here formats text.
local _, ns = ...

local Book = {}
ns.Book = Book

local BookView = ns.BookView
local Ledger = ns.Ledger
local TEXT = BookView.TEXT
local LIMITS = BookView.LIMITS

-- The AddOn's one global name: the client's Escape list holds frames by name.
local FRAME_NAME = "InnkeepersLedgerBook"

-- ---------------------------------------------------------------------------
-- The look. DRAFT: the colors, the layout, the textures and the flourishes are the
-- maintainer's to decide (spec 3.10, 3.11.1). Every texture file is unverified on Forever;
-- each surface has a solid color under it, and the in-client check sets `file` to nil for
-- one that doesn't look right.

local INK = { 0.20, 0.13, 0.08 }   -- iron-gall ink: every line of writing
local FADED = 0.45                 -- unsigned inns, locked items
local STAMP = { 0.55, 0.16, 0.12 } -- stamp ink
local PARCHMENT = { 0.87, 0.80, 0.64 }

local LOOK = {
  frame = { file = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    color = { 0.10, 0.07, 0.05, 0.95 } },
  -- One page file for both (Spellbook-Page-2 stretched into a blur on Forever, #12). Its
  -- cover and ribbon edge go to the middle, where the two meet as the book's spine: the
  -- left page is mirrored, the right one isn't.
  left = { file = "Interface\\Spellbook\\Spellbook-Page-1", mirror = true,
    color = { PARCHMENT[1], PARCHMENT[2], PARCHMENT[3], 1 } },
  right = { file = "Interface\\Spellbook\\Spellbook-Page-1",
    color = { PARCHMENT[1], PARCHMENT[2], PARCHMENT[3], 1 } },
  barBack = { color = { INK[1], INK[2], INK[3], 0.15 } },
  ink = { color = { INK[1], INK[2], INK[3], 1 } },
  stamp = { color = { STAMP[1], STAMP[2], STAMP[3], 1 } },
  faint = { color = { INK[1], INK[2], INK[3], FADED } },
  highlight = { color = { INK[1], INK[2], INK[3], 0.12 } },
  selected = { color = { INK[1], INK[2], INK[3], 0.18 } },
  editBack = { color = { 0, 0, 0, 0.6 } },
  checkBack = { color = { 0.10, 0.07, 0.05, 0.9 } },
}

local PAGE_W, PAGE_H = 404, 500
-- One edge of the page file is a cover and a ribbon (about 12% of its width on Forever,
-- #12), the other an ornate border. Each page texture reaches COVER past the writing
-- area on the spine side and EDGE on the outer side, so no text sits on either; the two
-- textures meet in the middle with no gap.
local MARGIN, COVER, EDGE = 16, 56, 12
local TEX_W = PAGE_W + COVER + EDGE
local BOOK_W, BOOK_H = 2 * (MARGIN + TEX_W), 560
local PAGE_TOP = -44
local PAD = 24
local CONTENT_W = PAGE_W - 2 * PAD
local LIST_ROW_H = 27
local INN_ROW_H = 54
local STAMP_W, STAMP_H = 108, 88
local DASHES = 6

local LEFT_KINDS = { "title", "list", "summary", "quills", "share" }
local RIGHT_KINDS = { "help", "inn", "stamps", "seals", "shareInfo" }
local TAB_ORDER = { "inns", "collection", "cosmetics", "share" }
local TAB_TEXT = { inns = TEXT.tabInns, collection = TEXT.tabCollection,
  cosmetics = TEXT.tabCosmetics, share = TEXT.tabShare }
-- The nav field each paged kind turns.
local PAGE_FIELD = { title = "listPage", list = "listPage", summary = "barPage",
  quills = "quillPage", inn = "innPage", stamps = "stampPage", seals = "sealPage" }

Book.view = nil
Book.nav = { tab = "inns" }
Book.model = nil
Book.ui = nil

local shareText -- the string in the edit box while the Share page shows

-- ---------------------------------------------------------------------------
-- Output and guards. Debug lines carry only our own codes and numbers.

local function debug(line)
  pcall(function() ns.Core:Debug(line) end)
end

local function guard(where, fn, ...)
  local ok, result = pcall(fn, ...)
  if not ok then
    debug("book: error in " .. where)
    return nil
  end
  return result
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

-- ---------------------------------------------------------------------------
-- Client reads (spec 3.11.2).

local function readFaction()
  local faction = call(UnitFactionGroup, "player")
  if hidden(faction) or type(faction) ~= "string" then
    return nil
  end
  return faction
end

local function readName()
  local ok, name = pcall(function() return ns.Core:PlayerName() end)
  if ok and not hidden(name) and type(name) == "string" then
    return name
  end
  return nil
end

-- The client's UTC offset in seconds (local time = UTC + offset), 0 if it can't say.
local function readOffset()
  local ok, offset = pcall(function()
    local now = call(GetServerTime)
    if hidden(now) or type(now) ~= "number" or now ~= now then
      return 0
    end
    if type(date) ~= "function" or type(time) ~= "function" then
      return 0
    end
    local l, u = date("*t", now), date("!*t", now)
    if hidden(l) or hidden(u) or type(l) ~= "table" or type(u) ~= "table" then
      return 0
    end
    u.isdst = l.isdst
    local t = time(u)
    if hidden(t) or type(t) ~= "number" or t ~= t then
      return 0
    end
    return now - t
  end)
  if ok and type(offset) == "number" then
    return offset
  end
  return 0
end

-- The situation BookView builds from, and the record's whereabouts for writing it. The
-- ledger is read at use, never cached.
local function read()
  local s = { faction = readFaction(), name = readName(), offset = readOffset(),
    prefsWritable = false }
  local rec = { writable = false }
  local ledger = ns.ledger
  if type(ledger) ~= "table" then
    return s, rec
  end
  s.ledger = ledger
  pcall(function()
    local guid = ledger:ownerGUID()
    local db = ns.Core.db
    local g = type(db) == "table" and db.global or nil
    if type(g) ~= "table" then
      return
    end
    local all = g.book
    local saved = nil
    if type(all) == "table" and Ledger.validGUID(guid) then
      saved = all[guid]
    end
    local prefs = BookView.readPrefs(saved)
    s.quill, s.shared = prefs.quill, prefs.shared
    s.prefsWritable = prefs.writable == true and Ledger.validGUID(guid)
      and (all == nil or type(all) == "table")
    if s.prefsWritable then
      rec = { writable = true, g = g, guid = guid }
    end
  end)
  return s, rec
end

-- Writes the book's record for the owner: a fresh table of the known fields. Only for a
-- writable record; never touches the ledger or its saved table.
local function writeRecord(rec, quill, shared)
  if not rec.writable then
    return
  end
  local g = rec.g
  if g.book == nil then
    g.book = {}
  end
  if type(g.book) == "table" then
    g.book[rec.guid] = BookView.prefsRecord(quill, shared)
  end
end

-- The ledger's unlocks, as Cosmetics derives them (spec 3.6); {} on any error.
local function unlocksOf(s)
  local ok, u = pcall(function()
    local ledger = s.ledger
    return ns.Cosmetics.unlocked(ledger:own(), s.faction, ledger:earned())
  end)
  if ok and type(u) == "table" then
    return u
  end
  return {}
end

-- ---------------------------------------------------------------------------
-- Building blocks.

local function paint(tex, look)
  local c = look.color
  tex:SetColorTexture(c[1], c[2], c[3], c[4])
  if look.file and tex:SetTexture(look.file) == false then
    tex:SetColorTexture(c[1], c[2], c[3], c[4])
  end
end

local function fontOf(kind)
  if kind == "title" then
    if type(QuestTitleFont) == "table" then
      return QuestTitleFont
    end
    return GameFontNormalLarge
  elseif kind == "small" then
    return GameFontNormalSmall
  elseif kind == "edit" then
    return GameFontHighlightSmall
  end
  return GameFontNormal
end

local function color(fs, rgb, faded)
  fs:SetTextColor(rgb[1], rgb[2], rgb[3], faded and FADED or 1)
end

-- A font string at (x, y) from the parent's top left, in the ink, without the shadow.
local function newText(parent, kind, width, x, y, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  local obj = fontOf(kind)
  if type(obj) == "table" then
    fs:SetFontObject(obj)
  end
  fs:SetWidth(width)
  fs:SetJustifyH(justify or "LEFT")
  fs:SetJustifyV("TOP")
  fs:SetWordWrap(true)
  fs:SetShadowOffset(0, 0)
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  color(fs, INK, false)
  return fs
end

local function newTexture(parent, layer, look, w, h, x, y)
  local tex = parent:CreateTexture(nil, layer)
  paint(tex, look)
  if w then
    tex:SetSize(w, h)
    tex:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  else
    tex:SetAllPoints(parent)
  end
  return tex
end

local function newButton(parent, text, width, height)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, height)
  b:SetText(text)
  return b
end

local function shown(region, on)
  if on then
    region:Show()
  else
    region:Hide()
  end
end

local function setText(fs, text)
  fs:SetText(text or "")
  shown(fs, text ~= nil)
end

-- A stamp: four solid sides (signed) or four dashed ones (unsigned), a name and a date.
local function newStamp(parent, w, h, x, y)
  local st = { solid = {}, dashes = {} }
  local f = CreateFrame("Button", nil, parent)
  f:SetSize(w, h)
  f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  st.frame = f
  -- { x, down, width, height }: `down` is the distance below the stamp's top.
  local sides = { { 0, 0, w, 2 }, { 0, h - 2, w, 2 }, { 0, 0, 2, h }, { w - 2, 0, 2, h } }
  for i, side in ipairs(sides) do
    st.solid[i] = newTexture(f, "ARTWORK", LOOK.stamp, side[3], side[4], side[1], -side[2])
  end
  -- Each side: DASHES short dashes with gaps.
  local dx, dy = w / (2 * DASHES), h / (2 * DASHES)
  for i = 0, DASHES - 1 do
    local n = #st.dashes
    st.dashes[n + 1] = newTexture(f, "ARTWORK", LOOK.faint, dx, 2, (2 * i + 0.5) * dx, 0)
    st.dashes[n + 2] = newTexture(f, "ARTWORK", LOOK.faint, dx, 2, (2 * i + 0.5) * dx, -(h - 2))
    st.dashes[n + 3] = newTexture(f, "ARTWORK", LOOK.faint, 2, dy, 0, -(2 * i + 0.5) * dy)
    st.dashes[n + 4] = newTexture(f, "ARTWORK", LOOK.faint, 2, dy, w - 2, -(2 * i + 0.5) * dy)
  end
  st.name = newText(f, "small", w - 12, 6, -12, "CENTER")
  st.name:SetHeight(h - 36)
  st.date = newText(f, "small", w - 12, 6, -(h - 22), "CENTER")
  return st
end

local function drawStamp(st, signed, name, date)
  for _, tex in ipairs(st.solid) do
    shown(tex, signed)
  end
  for _, tex in ipairs(st.dashes) do
    shown(tex, not signed)
  end
  setText(st.name, name)
  color(st.name, signed and STAMP or INK, not signed)
  setText(st.date, signed and date or nil)
  color(st.date, STAMP, false)
end

-- ---------------------------------------------------------------------------
-- Frames (spec 3.11.1). Built once, on the first open.

local function newPanel(page)
  local p = CreateFrame("Frame", nil, page)
  p:SetAllPoints(page)
  p:Hide()
  return p
end

local function buildTitle(page)
  local p = newPanel(page)
  local ui = { panel = p, steps = {} }
  ui.title = newText(p, "title", CONTENT_W, PAD, -32, "CENTER")
  for i = 1, 3 do
    ui.steps[i] = newText(p, "body", CONTENT_W, PAD, -100 - (i - 1) * 64)
  end
  ui.hint = newText(p, "body", CONTENT_W, PAD, -320, "CENTER")
  return ui
end

local function buildHelp(page)
  local p = newPanel(page)
  local ui = { panel = p }
  ui.travelersTitle = newText(p, "title", CONTENT_W, PAD, -32)
  ui.travelersText = newText(p, "body", CONTENT_W, PAD, -64)
  ui.sharesTitle = newText(p, "title", CONTENT_W, PAD, -190)
  ui.sharesText = newText(p, "body", CONTENT_W, PAD, -222)
  return ui
end

local function buildList(page)
  local p = newPanel(page)
  local ui = { panel = p, rows = {} }
  for i = 1, LIMITS.listRows do
    local y = -24 - (i - 1) * LIST_ROW_H
    local b = CreateFrame("Button", nil, p)
    b:SetSize(CONTENT_W, LIST_ROW_H - 1)
    b:SetPoint("TOPLEFT", p, "TOPLEFT", PAD, y)
    local row = { button = b }
    row.highlight = newTexture(b, "HIGHLIGHT", LOOK.highlight)
    row.selected = newTexture(b, "BACKGROUND", LOOK.selected)
    row.mark = newTexture(b, "ARTWORK", LOOK.ink, 10, 10, 14, -8)
    row.text = newText(b, "body", 250, 0, -6)
    row.sub = newText(b, "small", 110, CONTENT_W - 110, -7, "RIGHT")
    b:SetScript("OnClick", function()
      if row.key ~= nil then
        Book:ShowInn(row.key)
      end
    end)
    ui.rows[i] = row
  end
  ui.empty = newText(p, "body", CONTENT_W, PAD, -32)
  return ui
end

local function buildInn(page)
  local p = newPanel(page)
  local ui = { panel = p, rows = {} }
  ui.title = newText(p, "title", CONTENT_W - STAMP_W - 8, PAD, -24)
  ui.place = newText(p, "small", CONTENT_W - STAMP_W - 8, PAD, -52)
  ui.count = newText(p, "body", CONTENT_W - STAMP_W - 8, PAD, -72)
  ui.last = newText(p, "small", CONTENT_W - STAMP_W - 8, PAD, -92)
  ui.stamp = newStamp(p, STAMP_W - 12, 64, PAD + CONTENT_W - STAMP_W + 12, -20)
  for i = 1, LIMITS.innRows do
    local y = -118 - (i - 1) * INN_ROW_H
    local f = CreateFrame("Frame", nil, p)
    f:SetSize(CONTENT_W, INN_ROW_H - 2)
    f:SetPoint("TOPLEFT", p, "TOPLEFT", PAD, y)
    local row = { frame = f }
    row.head = newText(f, "title", CONTENT_W, 0, -4)
    row.meta = newText(f, "small", CONTENT_W, 0, 0)
    row.text = newText(f, "body", CONTENT_W, 0, -14)
    row.text:SetHeight(28) -- two lines, word-wrapped
    row.flourish = newText(f, "small", CONTENT_W, 0, -42, "CENTER")
    ui.rows[i] = row
  end
  return ui
end

local function buildSummary(page)
  local p = newPanel(page)
  local ui = { panel = p, bars = {} }
  ui.signed = newText(p, "title", CONTENT_W, PAD, -28)
  ui.zones = newText(p, "body", CONTENT_W, PAD, -64)
  ui.signatures = newText(p, "body", CONTENT_W, PAD, -84)
  ui.travelers = newText(p, "body", CONTENT_W, PAD, -104)
  for i = 1, LIMITS.barRows do
    local y = -144 - (i - 1) * 48
    local bar = {}
    bar.name = newText(p, "body", CONTENT_W - 90, PAD, y)
    bar.text = newText(p, "small", 90, PAD + CONTENT_W - 90, y, "RIGHT")
    bar.back = newTexture(p, "ARTWORK", LOOK.barBack, CONTENT_W, 10, PAD, y - 20)
    bar.fill = newTexture(p, "OVERLAY", LOOK.ink, CONTENT_W, 10, PAD, y - 20)
    ui.bars[i] = bar
  end
  ui.empty = newText(p, "body", CONTENT_W, PAD, -144)
  return ui
end

local function buildStamps(page)
  local p = newPanel(page)
  local ui = { panel = p, cells = {} }
  ui.title = newText(p, "title", CONTENT_W, PAD, -24, "CENTER")
  local cols = 3
  for i = 1, LIMITS.stampCells do
    local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
    local x, y = PAD + col * (STAMP_W + 16), -64 - row * (STAMP_H + 14)
    local cell = newStamp(p, STAMP_W, STAMP_H, x, y)
    cell.frame:SetScript("OnClick", function()
      if cell.key ~= nil then
        Book:ShowStamp(cell.key)
      end
    end)
    ui.cells[i] = cell
  end
  ui.empty = newText(p, "body", CONTENT_W, PAD, -64)
  return ui
end

local function buildQuills(page)
  local p = newPanel(page)
  local ui = { panel = p, rows = {} }
  ui.title = newText(p, "title", CONTENT_W, PAD, -24)
  for i = 1, LIMITS.quillRows do
    local y = -64 - (i - 1) * 60
    local row = {}
    row.name = newText(p, "body", CONTENT_W - 80, PAD, y)
    row.status = newText(p, "small", CONTENT_W - 80, PAD, y - 20)
    row.use = newButton(p, TEXT.use, 64, 22)
    row.use:SetPoint("TOPRIGHT", p, "TOPRIGHT", -PAD, y)
    row.use:SetScript("OnClick", function()
      if row.id ~= nil then
        Book:SetQuill(row.id)
      end
    end)
    ui.rows[i] = row
  end
  return ui
end

local function buildSeals(page)
  local p = newPanel(page)
  local ui = { panel = p, rows = {} }
  ui.title = newText(p, "title", CONTENT_W, PAD, -24)
  ui.hint = newText(p, "small", CONTENT_W, PAD, -52)
  for i = 1, LIMITS.sealRows do
    local y = -84 - (i - 1) * 54
    local row = {}
    row.dot = newTexture(p, "ARTWORK", LOOK.stamp, 12, 12, PAD, y - 2)
    row.name = newText(p, "body", CONTENT_W - 20, PAD + 20, y)
    row.status = newText(p, "small", CONTENT_W - 20, PAD + 20, y - 20)
    ui.rows[i] = row
  end
  return ui
end

local function share(untick)
  local ui = Book.ui.share
  if untick then
    ui.check:SetChecked(false)
  end
  -- Only exactly true opts in: a client that answered 1 would never share travelers.
  local opted = rawequal(ui.check:GetChecked(), true)
  local ok, str, reason = pcall(function() return ns.Core:ExportString(opted) end)
  if not ok then
    str, reason = nil, "error"
  end
  if type(str) == "string" then
    shareText = str
    ui.fail:Hide()
    ui.edit:SetText(str)
    ui.edit:SetCursorPosition(0)
    ui.edit:SetFocus()
    ui.edit:HighlightText()
    debug("book: share " .. #str .. " bytes")
    -- The share mark: what the ledger held when this string was built and shown.
    local s, rec = read()
    if rec.writable then
      local own = s.ledger:own()
      writeRecord(rec, s.quill, BookView.snapshot(own, unlocksOf(s)))
    end
    return
  end
  shareText = ""
  ui.edit:SetText("")
  setText(ui.fail, TEXT.shareFail)
  if type(reason) ~= "string" or #reason > 32 or not reason:find("^[%a_]+$") then
    reason = "error"
  end
  debug("book: share " .. reason)
end

local function buildShare(page)
  local p = newPanel(page)
  local ui = { panel = p }
  ui.title = newText(p, "title", CONTENT_W, PAD, -24)
  ui.help = newText(p, "body", CONTENT_W, PAD, -60)

  local edit = CreateFrame("EditBox", nil, p)
  edit:SetSize(CONTENT_W, 24)
  edit:SetPoint("TOPLEFT", p, "TOPLEFT", PAD, -110)
  edit:SetMultiLine(false)
  edit:SetAutoFocus(false)
  edit:SetMaxLetters(0) -- no cap: the whole string fits
  if type(edit.SetMaxBytes) == "function" then
    edit:SetMaxBytes(0)
  end
  local font = fontOf("edit")
  if type(font) == "table" then
    edit:SetFontObject(font)
  end
  newTexture(edit, "BACKGROUND", LOOK.editBack)
  -- Read-only in effect: typing puts the built string back.
  edit:SetScript("OnTextChanged", function(self, userInput)
    if userInput then
      guard("edit", function()
        self:SetText(shareText or "")
        self:HighlightText()
      end)
    end
  end)
  edit:SetScript("OnEditFocusGained", function(self)
    guard("edit", function() self:HighlightText() end)
  end)
  edit:SetScript("OnEscapePressed", function(self)
    guard("edit", function() self:ClearFocus() end)
  end)
  ui.edit = edit

  local check = CreateFrame("CheckButton", nil, p)
  check:SetSize(20, 20)
  check:SetPoint("TOPLEFT", p, "TOPLEFT", PAD, -150)
  newTexture(check, "BACKGROUND", LOOK.checkBack)
  local mark = check:CreateTexture(nil, "ARTWORK")
  paint(mark, LOOK.ink)
  mark:SetPoint("TOPLEFT", check, "TOPLEFT", 4, -4)
  mark:SetSize(12, 12)
  check:SetCheckedTexture(mark)
  check:SetChecked(false)
  check:SetScript("OnClick", function()
    guard("check", share, false)
  end)
  ui.check = check
  ui.include = newText(p, "body", CONTENT_W - 30, PAD + 30, -152)
  ui.nudge = newText(p, "body", CONTENT_W, PAD, -190)
  ui.fail = newText(p, "body", CONTENT_W, PAD, -230)
  return ui
end

local function buildShareInfo(page)
  local p = newPanel(page)
  local ui = { panel = p }
  ui.title = newText(p, "title", CONTENT_W, PAD, -32)
  ui.text = newText(p, "body", CONTENT_W, PAD, -64)
  return ui
end

local draw -- defined below

local function turn(side, delta)
  local model = Book.model
  local page = type(model) == "table" and model[side] or nil
  local field = type(page) == "table" and PAGE_FIELD[page.kind] or nil
  if field == nil or type(page.page) ~= "number" then
    return
  end
  Book.nav[field] = page.page + delta
  draw(false)
end

local function buildPage(book, side, look, x)
  local f = CreateFrame("Frame", nil, book)
  f:SetSize(PAGE_W, PAGE_H)
  f:SetPoint("TOPLEFT", book, "TOPLEFT", x, PAGE_TOP)
  local tex = newTexture(f, "BACKGROUND", look, TEX_W, PAGE_H,
    side == "left" and -EDGE or -COVER, 0)
  if look.mirror then
    tex:SetTexCoord(1, 0, 0, 1)
  end
  local ui = { frame = f }
  ui.prev = newButton(f, TEXT.prev, 26, 22)
  ui.prev:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 10)
  ui.prev:SetScript("OnClick", function() guard("turn", turn, side, -1) end)
  ui.next = newButton(f, TEXT.next, 26, 22)
  ui.next:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 10)
  ui.next:SetScript("OnClick", function() guard("turn", turn, side, 1) end)
  ui.label = newText(f, "small", 120, PAGE_W / 2 - 60, -(PAGE_H - 30), "CENTER")
  ui.error = newText(f, "body", CONTENT_W, PAD, -PAGE_H / 2, "CENTER")
  ui.error:SetText(TEXT.pageError)
  ui.error:Hide()
  return ui
end

local function build()
  local book = CreateFrame("Frame", FRAME_NAME, UIParent)
  book:SetSize(BOOK_W, BOOK_H)
  book:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  book:SetFrameStrata("HIGH")
  book:SetClampedToScreen(true)
  book:EnableMouse(true)
  book:Hide()
  newTexture(book, "BACKGROUND", LOOK.frame)

  local ui = { frame = book, tabs = {} }
  ui.left = buildPage(book, "left", LOOK.left, MARGIN + EDGE)
  ui.right = buildPage(book, "right", LOOK.right, BOOK_W / 2 + COVER)

  ui.notice = newText(book, "small", 620, (BOOK_W - 620) / 2, -16, "CENTER")
  color(ui.notice, PARCHMENT, false) -- it sits on the dark frame, not on parchment
  ui.notice:Hide()

  ui.close = newButton(book, TEXT.close, 80, 22)
  ui.close:SetPoint("TOPRIGHT", book, "TOPRIGHT", -16, -12)
  ui.close:SetScript("OnClick", function() guard("close", function() book:Hide() end) end)

  for i, name in ipairs(TAB_ORDER) do
    local b = newButton(book, TAB_TEXT[name], 120, 24)
    b:SetPoint("TOPLEFT", book, "BOTTOMLEFT", 24 + (i - 1) * 124, -2)
    b:SetScript("OnClick", function() guard("tab", Book.ShowTab, Book, name) end)
    ui.tabs[name] = b
  end

  ui.title = buildTitle(ui.left.frame)
  ui.list = buildList(ui.left.frame)
  ui.summary = buildSummary(ui.left.frame)
  ui.quills = buildQuills(ui.left.frame)
  ui.share = buildShare(ui.left.frame)
  ui.help = buildHelp(ui.right.frame)
  ui.inn = buildInn(ui.right.frame)
  ui.stamps = buildStamps(ui.right.frame)
  ui.seals = buildSeals(ui.right.frame)
  ui.shareInfo = buildShareInfo(ui.right.frame)

  -- The string isn't kept once the book closes.
  book:SetScript("OnHide", function()
    guard("hide", function()
      shareText = nil
      ui.share.edit:ClearFocus()
      ui.share.edit:SetText("")
    end)
  end)

  -- Escape closes the book through the client's own list of plain frames.
  if type(UISpecialFrames) == "table" then
    table.insert(UISpecialFrames, FRAME_NAME)
  else
    debug("book: no special frames")
  end
  -- Only a finished book is kept: an error above leaves Book.ui nil, so the next open
  -- builds again (or reports) rather than showing half a book.
  Book.ui = ui
  return ui
end

-- ---------------------------------------------------------------------------
-- Drawing models (spec 3.11.4).

local fill = {}

function fill.title(ui, m)
  setText(ui.title, m.title)
  for i = 1, 3 do
    setText(ui.steps[i], m.steps and m.steps[i])
  end
  setText(ui.hint, m.hint)
end

function fill.help(ui, m)
  setText(ui.travelersTitle, m.travelersTitle)
  setText(ui.travelersText, m.travelersText)
  setText(ui.sharesTitle, m.sharesTitle)
  setText(ui.sharesText, m.sharesText)
end

local INDENT = { continent = 0, zone = 12, inn = 30 }

function fill.list(ui, m)
  local rows = m.rows or {}
  for i, w in ipairs(ui.rows) do
    local r = rows[i]
    shown(w.button, r ~= nil)
    w.key = nil
    if r ~= nil then
      w.key = r.kind == "inn" and r.key or nil
      w.text:ClearAllPoints()
      w.text:SetPoint("TOPLEFT", w.button, "TOPLEFT", INDENT[r.kind] or 0, -6)
      setText(w.text, r.text)
      color(w.text, INK, r.faded == true)
      setText(w.sub, r.sub)
      shown(w.mark, r.signed == true)
      shown(w.selected, r.selected == true)
    end
  end
  setText(ui.empty, m.empty)
end

function fill.inn(ui, m)
  setText(ui.title, m.title)
  setText(ui.place, m.place)
  setText(ui.count, m.countText)
  setText(ui.last, m.lastText)
  local stamp = m.stamp or {}
  drawStamp(ui.stamp, stamp.signed == true, m.title, stamp.date)
  local rows = m.rows or {}
  for i, w in ipairs(ui.rows) do
    local r = rows[i]
    shown(w.frame, r ~= nil)
    r = r or {}
    if r.kind == "heading" then
      setText(w.head, r.text)
      setText(w.meta, nil)
      setText(w.text, nil)
      setText(w.flourish, nil)
    elseif r.kind == "note" then
      setText(w.head, nil)
      setText(w.meta, nil)
      setText(w.text, r.text)
      color(w.text, INK, true)
      setText(w.flourish, nil)
    elseif r.kind == "own" or r.kind == "foreign" then
      local meta = r.date or ""
      if r.kind == "foreign" then
        meta = (r.name or TEXT.aTraveler) .. (r.date and TEXT.dot .. r.date or "")
      end
      if r.seal then
        meta = meta .. TEXT.dot .. r.seal
      end
      setText(w.head, nil)
      setText(w.meta, meta)
      setText(w.text, r.text)
      color(w.text, INK, false)
      setText(w.flourish, r.flourish)
    end
  end
end

function fill.summary(ui, m)
  setText(ui.signed, m.signedText)
  setText(ui.zones, m.zonesText)
  setText(ui.signatures, m.signaturesText)
  setText(ui.travelers, m.travelersText)
  local bars = m.bars or {}
  for i, w in ipairs(ui.bars) do
    local b = bars[i]
    shown(w.back, b ~= nil)
    setText(w.name, b and b.name)
    setText(w.text, b and b.text)
    local fraction = b and type(b.fraction) == "number" and b.fraction or 0
    if fraction > 1 then
      fraction = 1
    end
    shown(w.fill, fraction > 0)
    if fraction > 0 then
      w.fill:SetWidth(CONTENT_W * fraction)
    end
  end
  setText(ui.empty, m.empty)
end

function fill.stamps(ui, m)
  setText(ui.title, m.title)
  local cells = m.cells or {}
  for i, w in ipairs(ui.cells) do
    local c = cells[i]
    shown(w.frame, c ~= nil)
    w.key = c and c.key or nil
    if c ~= nil then
      drawStamp(w, c.signed == true, c.name, c.date)
    end
  end
  setText(ui.empty, m.empty)
end

function fill.quills(ui, m)
  setText(ui.title, m.title)
  local rows = m.rows or {}
  for i, w in ipairs(ui.rows) do
    local r = rows[i]
    w.id = r and r.id or nil
    setText(w.name, r and r.name)
    setText(w.status, r and r.status)
    shown(w.use, r ~= nil)
    if r ~= nil then
      color(w.name, INK, r.unlocked ~= true)
      color(w.status, INK, r.unlocked ~= true)
      if r.canUse == true then
        w.use:Enable()
      else
        w.use:Disable()
      end
    end
  end
end

function fill.seals(ui, m)
  setText(ui.title, m.title)
  setText(ui.hint, m.hint)
  local rows = m.rows or {}
  for i, w in ipairs(ui.rows) do
    local r = rows[i]
    shown(w.dot, r ~= nil)
    setText(w.name, r and r.name)
    setText(w.status, r and r.status)
    if r ~= nil then
      paint(w.dot, r.earned and LOOK.stamp or LOOK.faint)
      color(w.name, INK, r.earned ~= true)
      color(w.status, INK, r.earned ~= true)
    end
  end
end

function fill.share(ui, m)
  setText(ui.title, m.title)
  setText(ui.help, m.help)
  setText(ui.include, m.include)
  setText(ui.nudge, m.nudge)
  ui.fail:Hide()
end

function fill.shareInfo(ui, m)
  setText(ui.title, m.title)
  setText(ui.text, m.text)
end

-- Page turns from the model: the title page is the list's page 0.
local function pager(side, m)
  local first = (m.kind == "title" or m.kind == "list") and 0 or 1
  local paged = type(m.page) == "number" and type(m.pages) == "number"
  shown(side.prev, paged)
  shown(side.next, paged)
  if paged then
    if m.page > first then
      side.prev:Enable()
    else
      side.prev:Disable()
    end
    if m.page < m.pages then
      side.next:Enable()
    else
      side.next:Disable()
    end
  end
  setText(side.label, paged and m.page >= 1 and m.page .. " / " .. m.pages or nil)
end

local function drawSide(side, kinds, m)
  local kind = type(m) == "table" and m.kind or nil
  for _, k in ipairs(kinds) do
    local ui = Book.ui[k]
    if k == kind then
      fill[k](ui, m)
      ui.panel:Show()
    else
      ui.panel:Hide()
    end
  end
  side.error:Hide()
  if kind == nil then
    shown(side.prev, false)
    shown(side.next, false)
    setText(side.label, nil)
    return
  end
  pager(side, m)
end

-- Builds the model for `Book.nav` and draws it. `fresh` (a tab click or an open) rebuilds
-- the share string with the box unticked.
draw = function(fresh)
  local ui = Book.ui
  local s = read()
  -- view.build never raises and always returns a table; this guard is belt and braces
  -- for the glue's own contract (spec 3.11.4: a page that can't be built shows pageError).
  local ok, model = pcall(Book.view.build, s, Book.nav)
  if not ok or type(model) ~= "table" then
    model = { error = true }
  end
  Book.model = model
  if type(model.nav) == "table" then
    Book.nav = model.nav
  end
  local tab = Book.nav.tab
  if tab ~= "share" then
    ui.share.edit:ClearFocus() -- a hidden box must not keep the keyboard
  end
  for name, b in pairs(ui.tabs) do
    if name == tab then
      b:Disable()
    else
      b:Enable()
    end
  end
  setText(ui.notice, model.notice)

  if model.error then
    for _, side in ipairs({ { ui.left, LEFT_KINDS }, { ui.right, RIGHT_KINDS } }) do
      drawSide(side[1], side[2], nil)
      side[1].error:SetText(TEXT.pageError)
      side[1].error:Show()
    end
    return
  end
  drawSide(ui.left, LEFT_KINDS, model.left)
  drawSide(ui.right, RIGHT_KINDS, model.right)
  if tab == "share" and fresh then
    share(true)
  end
end

-- ---------------------------------------------------------------------------
-- Opening, closing and the refresh (spec 3.11.4, 3.11.5).

local function noView()
  pcall(function() ns.Core:Print(TEXT.cantOpen) end)
  debug("book: no view")
end

local function show()
  if Book.ui == nil then
    build()
  end
  Book.ui.frame:Show()
  draw(true)
end

local function open(tab)
  if Book.view == nil then
    return noView()
  end
  if type(tab) == "string" then
    Book.nav.tab = tab
  end
  show()
end

local function toggle()
  if Book.view == nil then
    return noView()
  end
  if Book.ui ~= nil and Book.ui.frame:IsShown() then
    Book.ui.frame:Hide()
    return
  end
  show()
end

-- /ledger: shows the book, or hides it.
function Book.Toggle() -- called as Book:Toggle()
  guard("toggle", toggle)
end

-- Opens the book, on `tab` if given ("inns", "collection", "cosmetics", "share").
function Book.Open(_, tab) -- called as Book:Open(tab)
  guard("open", open, tab)
end

-- The Read button: the book on the inn's page (`npc` is an innkeeper's NPC ID).
function Book.OpenInn(_, npc) -- called as Book:OpenInn(npc)
  guard("open", function()
    if Book.view == nil then
      return noView()
    end
    Book.nav = { tab = "inns", inn = Book.view.innKey(npc) }
    show()
  end)
end

function Book.ShowTab(_, name) -- called as Book:ShowTab(name)
  guard("tab", function()
    if Book.view == nil or Book.ui == nil then
      return
    end
    Book.nav.tab = name
    draw(true)
  end)
end

-- An inn row's click: that inn's page, first page.
function Book.ShowInn(_, key) -- called as Book:ShowInn(key)
  guard("inn", function()
    if Book.view == nil or Book.ui == nil then
      return
    end
    Book.nav.inn = key
    Book.nav.innPage = 1
    draw(false)
  end)
end

-- A stamp's click: that inn's page on the Inns tab, its list page by default.
function Book.ShowStamp(_, key) -- called as Book:ShowStamp(key)
  guard("stamp", function()
    if Book.view == nil or Book.ui == nil then
      return
    end
    Book.nav = { tab = "inns", inn = key }
    draw(false)
  end)
end

-- A quill's Use button: saves the choice when the record is writable and the quill is
-- unlocked (0, the plain quill, clears it).
function Book.SetQuill(_, id) -- called as Book:SetQuill(id)
  guard("quill", function()
    if Book.view == nil or Book.ui == nil then
      return
    end
    local s, rec = read()
    if not rec.writable then
      return
    end
    if id ~= 0 and Book.view.effectiveQuill(id, unlocksOf(s)) ~= id then
      return
    end
    writeRecord(rec, id ~= 0 and id or nil, s.shared)
    draw(false)
  end)
end

-- The one refresh hook: Sync after it stored travelers' entries, Sign after a signature.
-- Redraws only while the book shows and not on the Share page; never shows the book,
-- prints or plays anything.
function Book.Changed() -- called as Book:Changed()
  local ok = pcall(function()
    local ui = Book.ui
    if Book.view == nil or ui == nil or not ui.frame:IsShown() or Book.nav.tab == "share" then
      return
    end
    draw(false)
  end)
  if not ok then
    debug("book: error in refresh")
  end
end

-- ---------------------------------------------------------------------------
-- The view, built once over the shipped data; a failure leaves the book closed.

do
  local ok, view = pcall(function()
    return BookView.new({
      inns = ns.Data.Inns,
      atlas = ns.Collection.atlas,
      phrase = ns.Phrase,
      cosmetics = ns.Cosmetics,
    })
  end)
  if ok then
    Book.view = view
  end
end
