-- Layout (#140): the stub's anchor resolver (wow.rect), then the real book (UI/Book.lua) and
-- composer (Sign.lua) frames checked with it: every shown region resolves, stays inside its
-- parent (intentional exceptions listed, each with its reason), overlaps nothing it
-- shouldn't, and its estimated text fits. Each check is also shown to fail on a broken
-- layout. The whole AddOn runs under the WoW stub, logged in at Coriella Calmbreeze.
local load = require("helpers.load")
local wow = require("helpers.wow_stub")
local layout = require("helpers.layout")

local GUID = "Player-1-00000001" -- the stub's UnitGUID("player")
local NOW = 1800000000           -- the stub's default server time, 15 January 2027
local SEPT = 1789700000          -- 18 September 2026 (a ledger's earliest time is the 17th)
local WEEK = 604800
local CALM = 254089              -- Coriella Calmbreeze, Calmbreeze Inn (the real data)
local CALM_GUID = "Creature-0-4615-2991-62-" .. CALM .. "-0000ABCDEF"

-- Days since 1970-01-01 for a civil date.
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

-- `date` and `time` for a client on UTC, whatever this machine's time zone is.
local UTC = {
  date = function(fmt, t)
    if fmt == "*t" then
      local r = os.date("!*t", t)
      r.isdst = false
      return r
    end
    return os.date(fmt, t)
  end,
  time = function(tt)
    return daysFromCivil(tt.year, tt.month, tt.day) * 86400 + tt.hour * 3600 + tt.min * 60
      + tt.sec
  end,
}

-- ---------------------------------------------------------------------------
-- A full atlas: places and quills added to the shipped data before Collection loads. The
-- first continent has 14 inns (more than a page of stamps); the others 4 each. Seven
-- continents plus Azeroth are more than a page of bars. Names are as long as most real
-- ones (an inn 20 characters, a zone 16, a continent 18); `long` makes an inn 24 and a
-- zone 20.
local function addPlaces(ns, long)
  local D = ns.Data
  local npc, seal = 300000, 101
  local innName = long and "The Wandering Wyvern %03d" or "Wandering Wyvern %03d"
  local zoneName = long and "Thistlewood Hills %d%d" or "Thistle Hills %d%d"
  for c = 1, 7 do
    local cont = 4000 + c
    D.Continents[cont] = { name = string.format("Eastern Kingdom %02d", c), complete = true }
    for z = 1, 2 do
      local zone = 3000 + c * 10 + z
      seal = seal + 1
      D.Zones[zone] = { name = string.format(zoneName, c, z), continent = cont, seal = seal,
        complete = true }
      for _ = 1, c == 1 and 7 or 2 do
        npc = npc + 1
        D.Inns[npc] = { name = string.format(innName, npc % 1000), zone = zone }
      end
    end
  end
  -- More quills than a page holds (6 rows), with names as long as they get (32 bytes).
  for id = 1004, 1010 do
    D.Cosmetics[id] = { kind = "quill", name = "Gilded phoenix-feather quill " .. id - 900,
      rule = { kind = "inns", n = id - 1000 } }
  end
end

-- What UnitGUID("npc") answers.
local npc

-- Loads the AddOn and logs in: resting, at Coriella Calmbreeze, the clock in UTC, the
-- gossip frame where the client puts it (a UIPanel on the left: 384 x 512, its top left 16
-- in and 104 down; the classic client's). opts: full (the full atlas), long (its long
-- names), db (SavedVariables).
local function login(opts)
  opts = opts or {}
  npc = CALM_GUID
  wow.install({
    IsResting = function() return true end,
    UnitGUID = function(unit)
      if unit == "player" then
        return GUID
      elseif unit == "npc" then
        return npc
      end
    end,
    date = UTC.date,
    time = UTC.time,
  })
  _G.GossipFrame:SetSize(384, 512)
  _G.GossipFrame:SetPoint("TOPLEFT", _G.UIParent, "TOPLEFT", 16, -104)
  if opts.db ~= nil then
    _G.InnkeepersLedgerDB = opts.db
  end
  local ns = {}
  for _, path in ipairs(load.toc_files()) do
    if path == "Collection.lua" and opts.full then
      addPlaces(ns, opts.long)
    end
    load.file(path, ns)
  end
  wow.fire("ADDON_LOADED", load.ADDON_NAME)
  wow.fire("PLAYER_LOGIN")
  return ns
end

-- The longest valid phrase (two lines, each word slot with the longest word), by bytes.
local function longestPhrase(P)
  local longestWord
  for c = 1, #P.categories() do
    for _, w in ipairs(P.words(c)) do
      if longestWord == nil or #P.text(w) > #P.text(longestWord) then
        longestWord = w
      end
    end
  end
  local function line(t)
    if P.hasSlot(t) then
      return { t, longestWord }
    end
    return { t }
  end
  local best, bestLen = nil, -1
  local function try(ids)
    if P.validIds(ids) then
      local text = P.render(ids)
      if type(text) == "string" and #text > bestLen then
        best, bestLen = ids, #text
      end
    end
  end
  local templates = P.templates()
  local first = nil
  for _, t in ipairs(templates) do
    local ids = line(t)
    if P.validIds(ids) and (first == nil or #P.render(ids) > #P.render(first)) then
      first = ids
    end
  end
  for _, c in ipairs(P.conjunctions()) do
    for _, t in ipairs(templates) do
      local ids = { unpack(first) }
      ids[#ids + 1] = c
      for _, id in ipairs(line(t)) do
        ids[#ids + 1] = id
      end
      try(ids)
    end
  end
  return best, bestLen
end

-- A two-line phrase of typical length (59 characters, from spec/sign_spec.lua).
local TYPICAL = { 201, 1001, 521, 231, 1001 }

-- The full ledger's saved book record: the Cartographer's quill chosen (its flourish shows)
-- and a share mark from before every signature (the nudge shows).
local function fullDb()
  return { global = { book = { [GUID] = { v = 1, quill = 1003,
    shared = { own = 1, newest = SEPT, unlocked = 0 } } } } }
end

-- The full ledger: every inn signed (Calmbreeze ten times, with seals), every cosmetic
-- recorded as earned and 40 travelers at Calmbreeze with two-part names. Needs
-- login({ full = true, db = fullDb() }). opts: phrase (Calmbreeze's signatures; TYPICAL by
-- default), name(i) (traveler i's name; "MiraA Thornwood" and so on by default),
-- travelerSeal (a seal on the travelers' signatures; none by default).
local function fill(ns, opts)
  opts = opts or {}
  local ledger = ns.ledger
  local ids = { 1, 2, 1001, 1002, 1003 }
  for id = 102, 115 do
    ids[#ids + 1] = id
  end
  for id = 1004, 1010 do
    ids[#ids + 1] = id
  end
  for _, id in ipairs(ids) do
    assert.is_true(ledger:markEarned(id, SEPT), id)
  end
  local phrase = opts.phrase or TYPICAL
  for i = 1, 10 do
    assert.equal("added", ledger:addOwn({ inn = CALM, t = SEPT + i * WEEK, phrase = phrase,
      seal = i % 2 == 0 and 2 or 102 }))
  end
  local n = 0
  for id in pairs(ns.Data.Inns) do
    if id ~= CALM then
      n = n + 1
      assert.equal("added", ledger:addOwn({ inn = id, t = SEPT + n * 60, phrase = { 101 } }))
    end
  end
  for i = 1, 40 do
    local name = opts.name and opts.name(i)
      or string.format("Mira%s Thornwood", string.char(65 + i % 26))
    assert.equal("added", ledger:addForeign(string.format("Player-1-%08X", 4096 + i), name,
      { inn = CALM, t = SEPT + i * 3600, phrase = phrase, seal = opts.travelerSeal }, NOW))
  end
end

-- ---------------------------------------------------------------------------
-- The checks over the book and the gossip frame.

local function concat(out, list, label)
  for _, p in ipairs(list) do
    out[#out + 1] = label .. " | " .. p
  end
end

-- Every problem the book shows now, prefixed with `label`.
local function bookProblems(ns, label, out)
  out = out or {}
  local ui = ns.Book.ui
  local items = layout.collect(ui.frame, ui, "book")
  local instead = {
    -- The page textures reach past their page, 56 into the cover on the spine side and
    -- 12 into the border on the outer side (book.md 3.11.1): they stay inside the book.
    [ui.left.frame.textures[1]] = ui.frame,
    [ui.right.frame.textures[1]] = ui.frame,
  }
  -- The tabs hang under the book by design (book.md 3.11.1): they stay on the screen.
  for _, tab in pairs(ui.tabs) do
    instead[tab] = _G.UIParent
  end
  -- A bar's fill is drawn over its back by design (book.md 3.11.1).
  local over = {}
  for _, bar in ipairs(ui.summary.bars) do
    over[bar.fill] = { [bar.back] = true }
  end
  -- A stamp's sides meet at its corners, solid or dashed.
  local stamps = { ui.inn.stamp }
  for _, cell in ipairs(ui.stamps.cells) do
    stamps[#stamps + 1] = cell
  end
  for _, st in ipairs(stamps) do
    for _, set in ipairs({ st.solid, st.dashes }) do
      local sides = {}
      for _, tex in ipairs(set) do
        sides[tex] = true
        over[tex] = sides
      end
    end
  end
  local function allowed(a, b)
    return over[a] ~= nil and over[a][b] == true
  end
  concat(out, layout.unresolved(items), label)
  concat(out, layout.outside(items, instead), label)
  concat(out, layout.overlaps(items, allowed), label)
  concat(out, layout.overflows(items), label)
  concat(out, layout.offScreen(ui.frame, "book"), label)
  for name, tab in pairs(ui.tabs) do
    concat(out, layout.offScreen(tab, "tabs." .. name), label)
  end
  return out
end

-- Every problem under the gossip frame now: the Sign and Read buttons and the composer.
local function gossipProblems(ns, label, out)
  out = out or {}
  local ui = ns.Sign.ui
  local items = layout.collect(_G.GossipFrame, ui, "gossip")
  -- The Sign and Read buttons hang under the gossip frame, and the composer stands to its
  -- right, by design (sign.md 3.7): they stay on the screen.
  local instead = {}
  for _, k in ipairs({ "button", "read", "composer" }) do
    if ui[k] then
      instead[ui[k]] = _G.UIParent
    end
  end
  -- A list's < > buttons sit right of the list by design (sign.md 3.7): they stay inside
  -- the composer.
  for _, list in pairs(ui.lists or {}) do
    instead[list.prev] = ui.composer
    instead[list.next] = ui.composer
  end
  concat(out, layout.unresolved(items), label)
  concat(out, layout.outside(items, instead), label)
  concat(out, layout.overlaps(items), label)
  concat(out, layout.overflows(items), label)
  return out
end

-- Problems listed once each, in the order found.
local function unique(list)
  local seen, out = {}, {}
  for _, p in ipairs(list) do
    local key = p:gsub("^.- | ", "")
    if not seen[key] then
      seen[key] = true
      out[#out + 1] = p
    end
  end
  return out
end

-- Known problems (#140): what these checks found in the current UI, left for the
-- maintainer, since the look is a DRAFT. Each is reproduced by a pending case in "Layout:
-- known problems" below. The other cases drop only these, so every other check stays live;
-- drop a pattern once its problem is fixed.
local KNOWN = {
  -- The conjunction strip's labels, at 12 pt in 92-wide buttons (sign.md 3.7).
  "^lists%.conj%.rows%[%d%]%.button: label ",
}

-- Problems listed once each, without the known ones.
local function report(list)
  local out = {}
  for _, p in ipairs(unique(list)) do
    local bare = p:gsub("^.- | ", "")
    local isKnown = false
    for _, pattern in ipairs(KNOWN) do
      isKnown = isKnown or bare:find(pattern) ~= nil
    end
    if not isKnown then
      out[#out + 1] = p
    end
  end
  return out
end

-- True if one problem holds every fragment.
local function has(list, ...)
  local fragments = { ... }
  for _, p in ipairs(list) do
    local all = true
    for _, text in ipairs(fragments) do
      all = all and p:find(text, 1, true) ~= nil
    end
    if all then
      return true
    end
  end
  return false
end

local function state(ns)
  local m = ns.Book.model or {}
  local l, r = m.left or {}, m.right or {}
  return string.format("%s: %s %s / %s %s", ns.Book.nav.tab, tostring(l.kind),
    tostring(l.page), tostring(r.kind), tostring(r.page))
end

-- Turns `side`'s pages to the end, checking each.
local function turnAll(ns, side, out)
  local guard = 0
  while side.next:IsShown() and side.next:IsEnabled() and guard < 50 do
    side.next:Click()
    bookProblems(ns, state(ns), out)
    guard = guard + 1
  end
end

-- Every page of one tab: both sides turned to the end, and on the Inns tab every inn's
-- page from every list page.
local function visitTab(ns, tab, out)
  local ui = ns.Book.ui
  ns.Book:ShowTab(tab)
  bookProblems(ns, state(ns), out)
  if tab ~= "inns" then
    turnAll(ns, ui.left, out)
    turnAll(ns, ui.right, out)
    return out
  end
  local guard = 0
  repeat
    for _, row in ipairs(ui.list.rows) do
      if row.button:IsShown() and row.key ~= nil then
        row.button:Click()
        bookProblems(ns, state(ns), out)
        turnAll(ns, ui.right, out)
      end
    end
    local more = ui.left.next:IsShown() and ui.left.next:IsEnabled()
    if more then
      ui.left.next:Click()
      bookProblems(ns, state(ns), out)
    end
    guard = guard + 1
  until not more or guard > 20
  return out
end

-- ---------------------------------------------------------------------------

describe("wow.rect: the stub resolves anchors", function()
  before_each(function() wow.install() end)
  after_each(wow.uninstall)

  local function frame(parent, w, h)
    local f = _G.CreateFrame("Frame", nil, parent or _G.UIParent)
    if w then
      f:SetSize(w, h)
    end
    return f
  end

  it("makes UIParent the screen, 1024 x 768", function()
    assert.same({ 0, 0, 1024, 768 }, { wow.rect(_G.UIParent) })
  end)

  it("places a sized frame by each of the nine points, with offsets", function()
    local f = frame(nil, 100, 50)
    local cases = {
      { "TOPLEFT", 10, 718 - 50 }, { "TOP", 512 - 50 + 10, 718 - 50 },
      { "TOPRIGHT", 1024 - 100 + 10, 718 - 50 }, { "LEFT", 10, 384 - 25 - 50 },
      { "CENTER", 512 - 50 + 10, 384 - 25 - 50 }, { "RIGHT", 1024 - 100 + 10, 384 - 25 - 50 },
      { "BOTTOMLEFT", 10, -50 }, { "BOTTOM", 512 - 50 + 10, -50 },
      { "BOTTOMRIGHT", 1024 - 100 + 10, -50 },
    }
    for _, c in ipairs(cases) do
      f:ClearAllPoints()
      f:SetPoint(c[1], _G.UIParent, c[1], 10, -50)
      assert.same({ c[2], c[3], 100, 50 }, { wow.rect(f) }, c[1])
    end
  end)

  it("anchors to another region's point, and to the parent by default", function()
    local a = frame(nil, 200, 100)
    a:SetPoint("BOTTOMLEFT", _G.UIParent, "BOTTOMLEFT", 100, 100)
    local b = frame(a, 20, 10)
    b:SetPoint("TOPLEFT", a, "BOTTOMRIGHT", 5, -5)
    assert.same({ 305, 85, 20, 10 }, { wow.rect(b) })
    local c = frame(a, 20, 10)
    c:SetPoint("TOPLEFT") -- the parent's own TOPLEFT
    assert.same({ 100, 190, 20, 10 }, { wow.rect(c) })
    c:SetPoint("TOPLEFT", 4, -6) -- replaces the TOPLEFT point, offsets only
    assert.same({ 104, 184, 20, 10 }, { wow.rect(c) })
    assert.equal(1, #c.points)
    c:SetPoint("TOPLEFT", a) -- a region, its same point
    assert.same({ 100, 190, 20, 10 }, { wow.rect(c) })
    c:SetPoint("TOPLEFT", a, 2, -2) -- a region and offsets
    assert.same({ 102, 188, 20, 10 }, { wow.rect(c) })
    c:SetPoint("TOPLEFT", nil, "CENTER", 0, 0) -- nil: the parent
    assert.same({ 200, 140, 20, 10 }, { wow.rect(c) })
    local named = _G.CreateFrame("Frame", "LayoutNamed", _G.UIParent)
    named:SetSize(10, 10)
    named:SetPoint("BOTTOMLEFT", _G.UIParent, "BOTTOMLEFT", 1, 2)
    c:SetPoint("TOPLEFT", "LayoutNamed", "TOPRIGHT", 0, 0) -- a global name
    assert.same({ 11, 2, 20, 10 }, { wow.rect(c) })
  end)

  it("stretches between two points, and SetAllPoints covers the region", function()
    local a = frame(nil, 200, 100)
    a:SetPoint("CENTER")
    local b = frame(a)
    b:SetPoint("TOPLEFT", a, "TOPLEFT", 10, -10)
    b:SetPoint("BOTTOMRIGHT", a, "BOTTOMRIGHT", -10, 10)
    assert.same({ 422, 344, 180, 80 }, { wow.rect(b) })
    b:SetSize(5, 5) -- two points on an axis win over the size, as in the client
    assert.same({ 422, 344, 180, 80 }, { wow.rect(b) })
    local c = frame(a)
    c:SetHeight(30)
    c:SetPoint("LEFT", a, "LEFT")
    c:SetPoint("RIGHT", a, "CENTER") -- half the width
    assert.same({ 412, 369, 100, 30 }, { wow.rect(c) })
    local d = frame(a)
    d:SetAllPoints()
    assert.same({ 412, 334, 200, 100 }, { wow.rect(d) })
    d:SetAllPoints(b)
    assert.same({ 422, 344, 180, 80 }, { wow.rect(d) })
    local tex = a:CreateTexture(nil, "BACKGROUND")
    assert.equal(a, tex.parent)
    tex:SetAllPoints()
    assert.same({ 412, 334, 200, 100 }, { wow.rect(tex) })
  end)

  it("is nil without points, without a size, with a bad point or in a cycle", function()
    local a = frame(nil, 10, 10)
    assert.is_nil(wow.rect(a))
    local b = frame(nil)
    b:SetPoint("TOPLEFT")
    assert.is_nil(wow.rect(b)) -- no size
    b:SetWidth(10)
    assert.is_nil(wow.rect(b)) -- no height
    b:SetHeight(10)
    assert.same({ 0, 758, 10, 10 }, { wow.rect(b) })
    b:SetPoint("MIDDLE")
    assert.is_nil(wow.rect(b))
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", a, "TOPLEFT") -- a doesn't resolve
    assert.is_nil(wow.rect(b))
    a:SetPoint("TOPLEFT", b, "BOTTOMLEFT")
    assert.is_nil(wow.rect(a)) -- a cycle
    assert.is_nil(wow.rect(b))
    local c = frame(nil)
    c:SetPoint("TOPLEFT", _G.UIParent, "TOPLEFT", 10, -10)
    c:SetPoint("BOTTOMRIGHT", _G.UIParent, "TOPLEFT", 0, 0) -- inverted: a negative size
    assert.is_nil(wow.rect(c))
    assert.is_nil(wow.rect(nil))
  end)

  it("sizes a font string from its text: wide as the text, high as its lines", function()
    local f = frame(nil, 300, 300)
    f:SetPoint("BOTTOMLEFT")
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    assert.equal(f, fs.parent)
    fs:SetPoint("TOPLEFT")
    fs:SetText("Calmbreeze")
    -- 10 characters x 12 x 0.6
    assert.same({ 0, 288, 72, 12 }, { wow.rect(fs) })
    fs:SetFontObject(_G.GameFontNormalSmall)
    assert.same({ 0, 290, 60, 10 }, { wow.rect(fs) })
    fs:SetText("")
    assert.same({ 0, 300, 0, 0 }, { wow.rect(fs) })
    -- A set width wraps by words: 6 per word plus a space, 6 per character at 10.
    fs:SetText("aaaa bbbb cccc dddd")
    fs:SetWidth(60)
    assert.same({ 0, 280, 60, 20 }, { wow.rect(fs) })
    assert.same({ 2, 54, 24 }, { wow.textLines(fs, 60) })
    fs:SetWordWrap(false)
    assert.same({ 0, 290, 60, 10 }, { wow.rect(fs) })
    assert.same({ 1, 114, 24 }, { wow.textLines(fs, 60) })
    fs:SetWordWrap(true)
    fs:SetHeight(15) -- a set height wins
    assert.same({ 0, 285, 60, 15 }, { wow.rect(fs) })
    fs:SetText("one\ntwo") -- a line break starts a line
    fs:SetHeight(0)
    assert.same({ 0, 280, 60, 20 }, { wow.rect(fs) })
    -- Characters, not bytes: a middle dot is one.
    assert.near(3 * 7.2, wow.textWidth({}, "a\194\183b"), 1e-9)
    assert.equal(12, wow.fontSize({ template = "UIPanelButtonTemplate" }))
    assert.equal(18, wow.fontSize({ fontObject = _G.QuestTitleFont }))
  end)
end)

describe("Layout: the book", function()
  after_each(function()
    assert.same({}, wow.errors)
    wow.uninstall()
  end)

  for _, tab in ipairs({ "inns", "collection", "cosmetics", "share" }) do
    it("keeps every page of the " .. tab .. " tab in order, empty ledger", function()
      local ns = login()
      wow.slash("/ledger")
      local out = bookProblems(ns, "open")
      visitTab(ns, tab, out)
      if tab == "inns" then
        ns.Sign:Read() -- the inn's page, not signed yet
        bookProblems(ns, state(ns), out)
      end
      assert.same({}, report(out))
    end)

    it("keeps every page of the " .. tab .. " tab in order, full ledger", function()
      local ns = login({ full = true, db = fullDb() })
      fill(ns)
      wow.slash("/ledger")
      local out = visitTab(ns, tab, {})
      assert.same({}, report(out))
    end)
  end

  it("fills every kind of page to its last row with the full ledger", function()
    local ns = login({ full = true, db = fullDb() })
    fill(ns)
    wow.slash("/ledger")
    local ui = ns.Book.ui
    assert.is_true(ui.list.rows[16].button:IsShown())
    assert.is_true(ui.left.next:IsEnabled()) -- more than a page of inns
    ns.Book:OpenInn(CALM)
    assert.is_true(ui.inn.rows[6].frame:IsShown())
    assert.is_true(ui.inn.rows[2].flourish:IsShown()) -- the chosen quill's flourish
    ns.Book:ShowTab("collection")
    assert.is_true(ui.summary.bars[6].name:IsShown())
    assert.is_true(ui.left.next:IsEnabled() and ui.right.next:IsEnabled())
    local full = false -- a continent's page of stamps with all 12 cells
    for _ = 1, 10 do
      full = full or ui.stamps.cells[12].frame:IsShown()
      ui.right.next:Click()
    end
    assert.is_true(full)
    ns.Book:ShowTab("cosmetics")
    assert.is_true(ui.quills.rows[6].use:IsShown())
    assert.is_true(ui.seals.rows[7].name:IsShown())
    assert.is_true(ui.left.next:IsEnabled() and ui.right.next:IsEnabled())
    ns.Book:ShowTab("share")
    assert.is_true(ui.share.nudge:IsShown())
  end)

  it("keeps the error lines, the notice and a failed share in order", function()
    local ns = login({ full = true, db = fullDb() })
    fill(ns)
    ns.ledger.readOnly = true -- the read-only notice
    wow.slash("/ledger")
    assert.is_true(ns.Book.ui.notice:IsShown())
    local out = bookProblems(ns, "read-only")
    ns.Core.ExportString = function() return nil, "too_big" end
    ns.Book:ShowTab("share")
    assert.is_true(ns.Book.ui.share.fail:IsShown())
    bookProblems(ns, "share failed", out)
    ns.Book.view.build = function() error("raised on purpose") end
    ns.Book:ShowTab("inns")
    assert.is_true(ns.Book.ui.left.error:IsShown())
    bookProblems(ns, "page error", out)
    assert.same({}, report(out))
  end)
end)

describe("Layout: the composer", function()
  after_each(function()
    assert.same({}, wow.errors)
    wow.uninstall()
  end)

  local function open(ns)
    wow.fire("GOSSIP_SHOW")
    ns.Sign.ui.button:Click()
    assert.is_true(ns.Sign.ui.composer:IsShown())
  end

  -- Every page of a list, checked (the page buttons, as a player would).
  local function pageThrough(ns, list, label, out)
    gossipProblems(ns, label, out)
    local guard = 0
    while list.next:IsShown() and list.next:IsEnabled() and guard < 50 do
      list.next:Click()
      gossipProblems(ns, label, out)
      guard = guard + 1
    end
  end

  it("keeps the buttons and the composer in order: one line, two, the seal row", function()
    local ns = login()
    wow.fire("GOSSIP_SHOW")
    local out = gossipProblems(ns, "buttons")
    open(ns)
    gossipProblems(ns, "line 1", out)
    ns.Sign.ui.toggle:Click()
    assert.is_true(ns.Sign.ui.lists.conj.frame:IsShown())
    gossipProblems(ns, "line 2", out)
    ns.Sign.ui.cancel:Click()
    -- The seal row: a signature and seals earned, a week on (as in spec/sign_spec.lua).
    assert.equal("added", ns.ledger:addOwn({ inn = CALM, t = NOW, phrase = { 101 } }))
    assert.is_true(ns.ledger:markEarned(2, NOW) and ns.ledger:markEarned(101, NOW))
    wow.now = NOW + 259200 + 1 -- past the stub's weekly reset
    open(ns)
    assert.is_true(ns.Sign.ui.rows.seal.label:IsShown())
    for _ = 1, 3 do
      ns.Sign.ui.rows.seal.next:Click()
      gossipProblems(ns, "seal", out)
    end
    assert.same({}, report(out))
  end)

  it("fits every voice's templates, every category and every word in their rows", function()
    local ns = login()
    open(ns)
    local ui = ns.Sign.ui
    local out = {}
    for v = 1, #ns.Phrase.voices() do
      ns.Sign:Pick("voice", v)
      pageThrough(ns, ui.lists.template, "voice " .. v, out)
    end
    ns.Sign:Scroll("template", -100)
    ui.lists.template.rows[1].button:Click() -- a template with a slot
    assert.is_true(ui.lists.cat.frame:IsShown())
    for c = 1, #ns.Phrase.categories() do
      ns.Sign:Pick("cat", c)
      pageThrough(ns, ui.lists.word, "category " .. c, out)
    end
    assert.same({}, report(out))
  end)

  it("fits the preview at its 160-byte cap above the Sign button", function()
    local ns = login()
    open(ns)
    local text = ns.Phrase.render(longestPhrase(ns.Phrase))
    assert.is_true(#text <= 160)
    ns.Sign.ui.preview:SetText(text)
    local out = gossipProblems(ns, "longest phrase")
    -- And any 160 bytes of words.
    ns.Sign.ui.preview:SetText(string.rep("Wwwwwww ", 20))
    gossipProblems(ns, "160 bytes", out)
    assert.same({}, report(out))
  end)
end)

describe("Layout: each check fails on a broken layout", function()
  after_each(function()
    assert.same({}, wow.errors)
    wow.uninstall()
  end)

  local function full()
    local ns = login({ full = true, db = fullDb() })
    fill(ns)
    wow.slash("/ledger")
    return ns
  end

  it("a region without points doesn't resolve", function()
    local ns = full()
    local ui = ns.Book.ui
    ui.left.next:Click() -- the list page
    assert.same({}, bookProblems(ns, "before"))
    ui.list.rows[2].button:ClearAllPoints()
    local out = bookProblems(ns, "broken")
    assert.is_true(has(out, "list.rows[2].button doesn't resolve"), table.concat(out, "\n"))
    assert.is_true(has(out, "list.rows[2].text doesn't resolve"))
  end)

  it("an anchor cycle doesn't resolve", function()
    local ns = login()
    wow.fire("GOSSIP_SHOW")
    ns.Sign.ui.button:Click()
    local ui = ns.Sign.ui
    ui.line1:SetPoint("TOPLEFT", ui.toggle, "TOPRIGHT", 4, 0)
    ui.toggle:ClearAllPoints()
    ui.toggle:SetPoint("TOPLEFT", ui.line1, "TOPRIGHT", 4, 0)
    local out = gossipProblems(ns, "broken")
    assert.is_true(has(out, "line1 doesn't resolve"), table.concat(out, "\n"))
    assert.is_true(has(out, "toggle doesn't resolve"))
  end)

  it("a moved anchor leaves the page", function()
    local ns = full()
    ns.Book:ShowTab("cosmetics")
    assert.same({}, bookProblems(ns, "before"))
    local row = ns.Book.ui.quills.rows[1]
    row.use:SetPoint("TOPRIGHT", ns.Book.ui.quills.panel, "TOPRIGHT", 40, -64)
    local out = bookProblems(ns, "broken")
    -- 40 past the page's right edge (the page: 52..456 across, 120..620 up).
    assert.is_true(has(out, "quills.rows[1].use (432.0, 534.0, 64.0 x 22.0) leaves "
      .. "(52.0, 120.0, 404.0 x 500.0)"), table.concat(out, "\n"))
  end)

  it("an oversized row overlaps the next", function()
    local ns = full()
    ns.Book.ui.left.next:Click()
    local rows = ns.Book.ui.list.rows
    rows[3].button:SetHeight(40)
    local out = bookProblems(ns, "broken")
    assert.is_true(has(out, "list.rows[3].button", "overlaps list.rows[4].button"),
      table.concat(out, "\n"))
    -- In the composer too: a template row as high as two.
    out = {}
    wow.fire("GOSSIP_SHOW")
    ns.Sign.ui.button:Click()
    assert.same({}, gossipProblems(ns, "before"))
    ns.Sign.ui.lists.template.rows[5].button:SetHeight(34)
    gossipProblems(ns, "broken", out)
    assert.is_true(has(out, "lists.template.rows[5].button",
      "overlaps lists.template.rows[6].button"), table.concat(out, "\n"))
  end)

  it("a page button off its page, or over the rows, is caught", function()
    local ns = full()
    local ui = ns.Book.ui
    ui.left.next:Click()
    assert.is_true(ui.list.rows[16].button:IsShown())
    ui.left.next:SetPoint("BOTTOMRIGHT", ui.left.frame, "BOTTOMRIGHT", 20, 10)
    local out = bookProblems(ns, "broken")
    assert.is_true(has(out, "left.next (450.0, 130.0, 26.0 x 22.0) leaves "
      .. "(52.0, 120.0, 404.0 x 500.0)"), table.concat(out, "\n"))
    ui.left.next:SetPoint("BOTTOMRIGHT", ui.left.frame, "BOTTOMRIGHT", -12, 50)
    out = bookProblems(ns, "broken")
    assert.is_true(has(out, "left.next", "overlaps list.rows[16].button"),
      table.concat(out, "\n"))
  end)

  it("text wider than its box, or with more lines than fit, is caught", function()
    local ns = full()
    local ui = ns.Book.ui
    ui.tabs.share:SetText("Share your ledger with the world")
    local out = bookProblems(ns, "broken")
    assert.is_true(has(out, "tabs.share: label"), table.concat(out, "\n"))
    ns.Book:OpenInn(CALM)
    local row = ui.inn.rows[2]
    assert.is_true(row.text:IsShown())
    row.text:SetText(string.rep("Rested here, dreaming of home. ", 4))
    out = bookProblems(ns, "broken")
    assert.is_true(has(out, "inn.rows[2].text: \"Rested", "is 3 lines (36.0 high) in 28.0"),
      table.concat(out, "\n"))
    row.text:SetText(string.rep("W", 60)) -- one word wider than the box
    out = bookProblems(ns, "broken")
    assert.is_true(has(out, "inn.rows[2].text: a word of"), table.concat(out, "\n"))

    wow.fire("GOSSIP_SHOW")
    ns.Sign.ui.button:Click()
    ns.Sign.ui.lists.cat.rows[1].text:SetText(string.rep("Long ", 10))
    out = gossipProblems(ns, "broken")
    assert.is_true(has(out, "lists.cat.rows[1].text: \"Long"), table.concat(out, "\n"))
  end)

  it("a book moved off the screen is caught", function()
    local ns = full()
    ns.Book.ui.frame:SetPoint("CENTER", _G.UIParent, "CENTER", 100, 0)
    local out = bookProblems(ns, "broken")
    assert.is_true(has(out, "book (124.0, 104.0, 976.0 x 560.0) leaves the screen"),
      table.concat(out, "\n"))
  end)
end)

-- Problems these checks found in the current UI (#140). The book's and the composer's look
-- is a DRAFT the maintainer decides, so they're reported, not fixed here. Each case
-- reproduces one; turn it into `it` once it's fixed. Widths are the stub's conservative
-- estimate (0.6 em a character); the numbers at 0.5 em, about the game font's average,
-- are in each comment.
describe("Layout: known problems", function()
  after_each(function()
    wow.uninstall()
  end)

  -- The longest phrase the composer can make, "Weighed anchor, still thinking of a good
  -- night's sleep. Then, LOUDER... Weighed anchor, still thinking of a good night's
  -- sleep." (127 characters), is 914 px of text (762 at 0.5 em) in an inn row's 356-wide
  -- box: 3 lines in a box 28 high (2 lines), so the client cuts it short.
  pending("an inn row holds the longest phrase (it needs 3 lines of the 2 it has)", function()
    local ns = login({ full = true, db = fullDb() })
    fill(ns, { phrase = longestPhrase(ns.Phrase) })
    ns.Book:OpenInn(CALM)
    assert.same({}, report(bookProblems(ns, "longest phrase")))
  end)

  -- A traveler row's meta line (name, date, seal) has 14 px, one line, above the phrase,
  -- and wraps. "MiraB Thornwood · 18 September 2026 · Sealed with Thistle Hills 11 seal"
  -- is 71 characters: 426 px in 356 (355 at 0.5 em, 1 px to spare), so its second line
  -- covers the phrase by 6 px. The longest name a ledger keeps (64 bytes shown, then
  -- "...") makes it 3 lines, 16 px over the phrase, at any font width.
  pending("a traveler row's name, date and seal stay on their one line", function()
    local ns = login({ full = true, db = fullDb() })
    fill(ns, { travelerSeal = 102, name = function(i)
      if i <= 2 then
        return string.rep("W", 48) .. " " .. string.rep("w", 47)
      end
      return string.format("Mira%s Thornwood", string.char(65 + i % 26))
    end })
    ns.Book:OpenInn(CALM)
    local out = bookProblems(ns, state(ns))
    turnAll(ns, ns.Book.ui.right, out)
    assert.same({}, report(out))
  end)

  -- An inn's title on its page is QuestTitleFont (18 pt) in 240 px: "The Wandering Wyvern
  -- 001" (24 characters) is 259 px (216 at 0.5 em), so it wraps onto the place line below.
  -- Only the estimate flags it; the in-client check decides.
  pending("a 24-character inn name stays on the inn page's title line", function()
    local ns = login({ full = true, long = true, db = fullDb() })
    fill(ns)
    wow.slash("/ledger")
    assert.same({}, report(visitTab(ns, "inns", {})))
  end)

  -- The conjunction strip's buttons are 92 wide, 84 inside the border: "Then, LOUDER...",
  -- "By the tides..." and "One must add..." (15 characters) are 108 px (90 at 0.5 em). 12
  -- of the 30 labels are over 84 by the estimate, those 3 at 0.5 em.
  pending("the conjunction strip's labels fit their buttons", function()
    local ns = login()
    wow.fire("GOSSIP_SHOW")
    ns.Sign.ui.button:Click()
    ns.Sign.ui.toggle:Click()
    local out = {}
    for v = 1, #ns.Phrase.voices() do
      ns.Sign:Pick("voice", v)
      gossipProblems(ns, "voice " .. v, out)
    end
    assert.same({}, unique(out))
  end)
end)
