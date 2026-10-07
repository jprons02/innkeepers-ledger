-- BookView (pure): every decision of the parchment book. Navigation and its clamps, the
-- model of each page (the inn list, an inn's page, the collection, the stamps, quills and
-- seals, the Share page), paging, ordering, text safety, dates, the quill fallback and its
-- flourish, the share nudge and the book's saved record. No WoW API here: client values
-- arrive in the situation `s`, the ledger is passed in, and Collection, Phrase and
-- Cosmetics come through `deps` (docs/architecture.md -> Modules). The glue is
-- UI/Book.lua. Spec: docs/specs/book.md (sections 3.2-3.10).
-- Travelers' names come from other players: they reach a model only through `plain`.
-- Every view and module function runs in pcall and returns its failure value on any
-- argument; only BookView.new (a caller bug) and the file itself can raise.
local _, ns = ...

local Ledger = ns.Ledger
assert(type(Ledger) == "table", "BookView needs ns.Ledger; Ledger.lua comes first in the TOC")

local BookView = {}
ns.BookView = BookView

local floor = math.floor
local byte, sub = string.byte, string.sub
local tsort = table.sort

-- Read from Ledger and Collection, not second literals.
local T_MIN, T_MAX = Ledger.LIMITS.tMin, Ledger.LIMITS.tMax
local INN_MAX = Ledger.LIMITS.innMax
local ID_MAX = Ledger.LIMITS.cosmeticIdMax
local validEntry = Ledger.validEntry
local Collection = ns.Collection
local OWN_MAX = type(Collection) == "table" and type(Collection.LIMITS) == "table"
  and Collection.LIMITS.ownMax or 0

-- Constants (spec 3.9). The locals are what the code uses; the exported tables are copies.
local LIMITS = {
  listRows = 16, innRows = 6, barRows = 6, stampCells = 12, quillRows = 6, sealRows = 7,
  ownReadMax = 1000, foreignReadMax = 600, aliasesMax = 8, innsReadMax = 20000,
  nameBytes = 64,
  tMin = T_MIN, tMax = T_MAX, cosmeticIdMax = ID_MAX, ownMax = OWN_MAX,
}
local SIZE_KEYS = { "listRows", "innRows", "barRows", "stampCells", "quillRows", "sealRows" }
local SIZE_MIN, SIZE_MAX = 3, 50
local COUNT_MAX = 10000000 -- a ledger count shown; anything else shows 0
local PAGE_MAX = 1000000   -- a page index kept in `nav` for a tab not built this time
local OFFSET_MAX = 50400   -- UTC-14 h .. UTC+14 h
local DAY = 86400

-- DRAFT: every player-facing line is the maintainer's to decide (spec 3.10). The tab names
-- are settled. Our own constants only: no `|`, no `%`, no site, product, service or URL.
-- Lines are joined by concatenation, never format. Three glyphs aren't ASCII: the page
-- turns (U+2039, U+203A) and the middle dot (U+00B7), written as UTF-8 bytes.
local TEXT = {
  tabInns = "Inns",
  tabCollection = "Collection",
  tabCosmetics = "Cosmetics",
  tabShare = "Share",
  prev = "\226\128\185",
  next = "\226\128\186",
  close = "Close",
  titleOf = "The ledger of ",
  titleNoName = "Your ledger",
  step1 = "1. Find an innkeeper, the one who keeps your hearthstone, and talk to them.",
  step2 = "2. Rest at the inn and choose Sign the guestbook.",
  step3 = "3. Choose your words and sign. Each guestbook takes your signature once a week.",
  hint = "Open this book any time with /ledger.",
  travelersTitle = "Travelers",
  travelersText = "When you group with other travelers who keep a ledger, or share a guild "
    .. "with them, your books quietly trade signatures. Theirs appear on each inn's page, "
    .. "under your own.",
  sharesTitle = "What your ledger shares",
  -- README.md -> Principles -> What sync shares, word for word (a test compares them).
  sharesText = "Your own newest signatures (up to 40), each with its inn, the date and time "
    .. "you signed, your phrase and your seal. It goes to your group and your guild, so "
    .. "guildmates who use the AddOn can see where and when you signed. Nothing else about "
    .. "you is sent: no location, chat, gear or play time beyond those signatures.",
  of = " of ",
  more = "+", -- after a total the data doesn't know in full yet: "1 of 1+ inns signed"
  signedPrefix = "signed ",
  innsSigned = " inns signed",
  notSigned = "Not signed yet",
  signedOnce = "Signed once",
  signedTimes1 = "Signed ",
  signedTimes2 = " times",
  lastSigned = "Last signed ",
  yours = "Your signatures",
  travelers = "Travelers' signatures",
  noOwn = "You haven't signed this guestbook yet.",
  noForeign = "No traveler you've met has signed here yet.",
  faded = "The ink here has faded.",
  aTraveler = "A traveler",
  aSeal = "a seal",
  sealedWith = "Sealed with ",
  zoneSealSuffix = " seal",
  zonesDone = "Zones completed: ",
  signatures = "Signatures: ",
  travelersMet = "Travelers met: ",
  noInns = "No inns are known yet.",
  quillsTitle = "Quills",
  sealsTitle = "Seals",
  plainQuill = "Plain quill",
  inUse = "In use",
  alwaysYours = "Always yours",
  use = "Use",
  earnedOn = "Earned ",
  dot = " \194\183 ",
  sealHint = "Choose a seal when you sign a guestbook.",
  ruleInns1 = "Sign ",
  ruleInns2 = " inns",
  ruleZones1 = "Complete ",
  ruleZones2 = " zones",
  ruleContinent = "Sign every inn on one continent",
  ruleAll = "Sign every inn open to you",
  ruleZone = "Sign every inn in ",
  shareTitle = "Share your ledger",
  shareHelp = "Copy this text to keep a copy of your ledger or to share it.",
  include = "Include travelers' signatures",
  shareFail = "Your ledger can't be shared right now.",
  nothingNew = "Nothing new since you last shared.",
  newOne = "1 new signature since you last shared.",
  newMany = " new signatures since you last shared.",
  changed = "Your ledger has changed since you last shared.",
  shareInfoTitle = "What the text holds",
  shareInfoText = "Your signatures, the inns you've collected and the cosmetics you've "
    .. "earned. Other travelers' signatures are theirs: they're left out unless you tick "
    .. "the box.",
  noLedger = "Your ledger isn't open yet. Try again in a moment.",
  readOnly = "This ledger is read-only (saved by a newer version, or damaged). You can read "
    .. "it, but nothing new is written.",
  pageError = "This page can't be read right now.",
  cantOpen = "The ledger can't be opened right now.",
  months = {
    "January", "February", "March", "April", "May", "June", "July", "August", "September",
    "October", "November", "December",
  },
}

-- DRAFT look (spec 3.6): drawn under your own signatures for the quill in use. ASCII only.
local FLOURISHES = { "~ ~ ~", "-~-~-~-", "~*~*~", "=~=~=" }

local function copy(t)
  local out = {}
  for k, v in next, t do
    out[k] = type(v) == "table" and copy(v) or v
  end
  return out
end

BookView.TEXT = copy(TEXT)
BookView.LIMITS = copy(LIMITS)
BookView.FLOURISHES = copy(FLOURISHES)

-- An integer in lo..hi. NaN fails x == x; inf % 1 is NaN, so inf fails too.
local function isInt(x, lo, hi)
  return type(x) == "number" and x == x and x % 1 == 0 and x >= lo and x <= hi
end

-- Byte order. String `<` follows the C locale's collation; the book's order must not.
local function strLess(a, b)
  for i = 1, math.min(#a, #b) do
    local x, y = byte(a, i), byte(b, i)
    if x ~= y then
      return x < y
    end
  end
  return #a < #b
end

-- Runs fn(...) in pcall; on an error, the failure value `fail()`.
local function safe(fn, fail)
  return function(...)
    local ok, res = pcall(fn, ...)
    if ok then
      return res
    end
    return fail()
  end
end

-- ---------------------------------------------------------------------------
-- Text safety and dates (spec 3.8).

local B_PIPE, B_DEL = 124, 127

local function plain(s, maxBytes, fallback)
  if type(s) ~= "string" or #s == 0 then
    return fallback
  end
  if not isInt(maxBytes, 1, PAGE_MAX) then
    maxBytes = LIMITS.nameBytes
  end
  local n, i, cut = #s, 1, 0
  while i <= n do
    local b = byte(s, i)
    local len
    if b < 32 or b == B_DEL or b == B_PIPE then
      return fallback
    elseif b < 128 then
      len = 1
    elseif b >= 194 and b <= 223 then
      len = 2
    elseif b >= 224 and b <= 239 then
      len = 3
    elseif b >= 240 and b <= 244 then
      len = 4
    else
      return fallback -- a lone continuation byte, C0, C1 or F5..FF
    end
    local last = i + len - 1
    if last > n then
      return fallback -- a truncated sequence
    end
    for j = i + 1, last do
      local c = byte(s, j)
      if c < 128 or c > 191 then
        return fallback
      end
    end
    if last <= maxBytes then
      cut = last
    end
    i = last + 1
  end
  if n > maxBytes then
    return sub(s, 1, cut) .. "..."
  end
  return s
end

-- "5 October 2026" for a time `t` at the client's UTC offset; nil for anything not a time.
-- Days to a civil date with integer arithmetic only (the proleptic Gregorian calendar).
local function dateText(t, offset)
  if not isInt(t, T_MIN, T_MAX) then
    return nil
  end
  if not isInt(offset, -OFFSET_MAX, OFFSET_MAX) then
    offset = 0
  end
  local z = floor((t + offset) / DAY) + 719468
  local era = floor(z / 146097)
  local doe = z - era * 146097
  local yoe = floor((doe - floor(doe / 1460) + floor(doe / 36524) - floor(doe / 146096)) / 365)
  local doy = doe - (365 * yoe + floor(yoe / 4) - floor(yoe / 100))
  local mp = floor((5 * doy + 2) / 153)
  local d = doy - floor((153 * mp + 2) / 5) + 1
  local m = mp < 10 and mp + 3 or mp - 9
  local y = yoe + era * 400
  if m <= 2 then
    y = y + 1
  end
  return d .. " " .. TEXT.months[m] .. " " .. y
end

-- plain in pcall: an error gives the fallback.
local function plainOr(s, maxBytes, fallback)
  local ok, res = pcall(plain, s, maxBytes, fallback)
  if ok then
    return res
  end
  return fallback
end

BookView.plain = plainOr
BookView.dateText = safe(dateText, function() return nil end)

-- ---------------------------------------------------------------------------
-- The share snapshot, the nudge and the saved record (spec 3.7, 4.1).

-- The number of items of `list` up to the first nil, at most `max`.
local function countItems(list, max)
  if type(list) ~= "table" then
    return 0
  end
  local n = 0
  for i = 1, max do
    if rawget(list, i) == nil then
      break
    end
    n = i
  end
  return n
end

local function snapshot(own, unlocked)
  local count, newest = 0, nil
  if type(own) == "table" then
    for i = 1, OWN_MAX do
      local e = rawget(own, i)
      if e == nil then
        break
      end
      count = i
      local t = type(e) == "table" and rawget(e, "t") or nil
      if isInt(t, T_MIN, T_MAX) and (newest == nil or t > newest) then
        newest = t
      end
    end
  end
  return { own = count, newest = newest, unlocked = countItems(unlocked, ID_MAX) }
end

-- A fresh copy of a valid snapshot, or nil.
local function validSnapshot(t)
  if type(t) ~= "table" then
    return nil
  end
  local own, newest, unlocked = rawget(t, "own"), rawget(t, "newest"), rawget(t, "unlocked")
  if not isInt(own, 0, OWN_MAX) or not isInt(unlocked, 0, ID_MAX) then
    return nil
  end
  if newest ~= nil and not isInt(newest, T_MIN, T_MAX) then
    return nil
  end
  if (newest == nil) ~= (own == 0) then
    return nil
  end
  return { own = own, newest = newest, unlocked = unlocked }
end

local function nudge(stored, current)
  local old, now = validSnapshot(stored), validSnapshot(current)
  if old == nil or now == nil then
    return nil
  end
  if old.own == now.own and old.newest == now.newest and old.unlocked == now.unlocked then
    return TEXT.nothingNew
  end
  if now.own > old.own then
    local n = now.own - old.own
    if n == 1 then
      return TEXT.newOne
    end
    return n .. TEXT.newMany
  end
  return TEXT.changed
end

local function readPrefs(rec)
  if rec == nil then
    return { writable = true }
  end
  if type(rec) ~= "table" then
    return { writable = false } -- damaged: never overwritten
  end
  local v = rawget(rec, "v")
  if isInt(v, 2, math.huge) then
    return { writable = false } -- a newer AddOn wrote it
  end
  if v ~= 1 then
    return { writable = true } -- a broken v1 record: the next write replaces it
  end
  local quill = rawget(rec, "quill")
  return {
    quill = isInt(quill, 1, ID_MAX) and quill or nil,
    shared = validSnapshot(rawget(rec, "shared")),
    writable = true,
  }
end

local function prefsRecord(quill, shared)
  return {
    v = 1,
    quill = isInt(quill, 1, ID_MAX) and quill or nil,
    shared = validSnapshot(shared),
  }
end

BookView.snapshot = safe(snapshot, function() return { own = 0, unlocked = 0 } end)
BookView.nudge = safe(nudge, function() return nil end)
BookView.readPrefs = safe(readPrefs, function() return { writable = false } end)
BookView.prefsRecord = safe(prefsRecord, function() return { v = 1 } end)

-- ---------------------------------------------------------------------------
-- The view (spec 3.2-3.7).

local TABS = { inns = true, collection = true, cosmetics = true, share = true }
local FACTIONS = { Alliance = true, Horde = true }
local SHOWN_KINDS = { quill = true, seal = true }

local function need(t, key, what)
  local f = rawget(t, key)
  if type(f) ~= "function" then
    error("BookView.new: deps." .. what .. "." .. key .. " must be a function", 3)
  end
  return f
end

local function depTable(deps, key)
  local t = rawget(deps, key)
  if type(t) ~= "table" then
    error("BookView.new: deps." .. key .. " must be a table", 3)
  end
  return t
end

-- A record's name if it's a string, else "".
local function nameOf(rec)
  local name = type(rec) == "table" and rawget(rec, "name") or nil
  if type(name) == "string" then
    return name
  end
  return ""
end

-- "signed of total" for a progress item, with TEXT.more after the total unless the item is
-- marked complete (collection-cosmetics.md 3.11): there may be inns the data doesn't know.
local function ofTotal(item)
  local text = item.signed .. TEXT.of .. item.total
  if rawequal(rawget(item, "complete"), true) then
    return text
  end
  return text .. TEXT.more
end

-- Orders tree nodes by name in byte order, ties by key.
local function nodeLess(a, b)
  if a.name ~= b.name then
    return strLess(a.name, b.name)
  end
  return a.key < b.key
end

-- Calls ledger:method(arg) in pcall; nil on an error or without a ledger.
local function ask(ledger, method, arg)
  if ledger == nil then
    return nil
  end
  local ok, res = pcall(function() return ledger[method](ledger, arg) end)
  if ok then
    return res
  end
  return nil
end

local function clamp(v, lo, hi)
  if v == nil or v < lo then
    return lo
  elseif v > hi then
    return hi
  end
  return v
end

-- Splits rows into pages of at most `per`. A row starting a page brings its `heads`
-- (the headers it sits under) first, repeated with cont = true and counted toward `per`.
-- `repeatHead(h)` makes the repeated copy. Always at least one (maybe empty) page.
local function paginate(rows, per, repeatHead)
  local pages, page = {}, nil
  for _, r in ipairs(rows) do
    if page == nil or #page >= per then
      page = {}
      pages[#pages + 1] = page
      for _, h in ipairs(r.heads) do
        page[#page + 1] = repeatHead(h)
      end
    end
    page[#page + 1] = r
  end
  if #pages == 0 then
    pages[1] = {}
  end
  return pages
end

local function ceilDiv(n, per)
  local pages = floor((n + per - 1) / per)
  if pages < 1 then
    return 1
  end
  return pages
end

function BookView.new(deps)
  if type(deps) ~= "table" then
    error("BookView.new: deps must be a table", 2)
  end
  local inns = depTable(deps, "inns")
  local atlas = depTable(deps, "atlas")
  local phrase = depTable(deps, "phrase")
  local cosmetics = depTable(deps, "cosmetics")
  local progressOf = need(atlas, "progress", "atlas")
  local innOf = need(atlas, "innOf", "atlas")
  local innRec = need(atlas, "inn", "atlas")
  local zoneRec = need(atlas, "zone", "atlas")
  local contRec = need(atlas, "continent", "atlas")
  local render = need(phrase, "render", "phrase")
  local catalogOf = need(cosmetics, "catalog", "cosmetics")
  local unlockedOf = need(cosmetics, "unlocked", "cosmetics")
  local info = need(cosmetics, "info", "cosmetics")

  local size = {}
  local sizes = rawget(deps, "sizes")
  for _, k in ipairs(SIZE_KEYS) do
    local v = type(sizes) == "table" and rawget(sizes, k) or nil
    size[k] = isInt(v, SIZE_MIN, SIZE_MAX) and v or LIMITS[k]
  end

  -- The inn index (spec 3.2): each kept primary with the NPC IDs that lead to it.
  local groups, primaries = {}, {}
  local read = 0
  for k in next, inns do
    read = read + 1
    if read > LIMITS.innsReadMax then
      break
    end
    local p = innOf(k)
    if p ~= nil then
      local g = groups[p]
      if g == nil then
        g = { p }
        groups[p] = g
        primaries[#primaries + 1] = p
      end
      if k ~= p then
        g[#g + 1] = k
      end
    end
  end
  for _, p in ipairs(primaries) do
    local g = groups[p]
    tsort(g)
    if #g > LIMITS.aliasesMax then
      local kept = { p }
      for _, id in ipairs(g) do
        if #kept >= LIMITS.aliasesMax then
          break
        end
        if id ~= p then
          kept[#kept + 1] = id
        end
      end
      tsort(kept)
      groups[p] = kept
    end
  end

  -- The place tree: continents -> zones -> inns, each by name in byte order, ties by key.
  local tree, contNodes, zoneNodes = {}, {}, {}
  local innName, zoneName, contName = {}, {}, {}
  tsort(primaries)
  for _, p in ipairs(primaries) do
    local irec = innRec(p)
    local z = type(irec) == "table" and rawget(irec, "zone") or nil
    local zrec = z ~= nil and zoneRec(z) or nil
    local c = type(zrec) == "table" and rawget(zrec, "continent") or nil
    local crec = c ~= nil and contRec(c) or nil
    if type(crec) == "table" then
      innName[p], zoneName[z], contName[c] = nameOf(irec), nameOf(zrec), nameOf(crec)
      local cnode = contNodes[c]
      if cnode == nil then
        cnode = { key = c, name = contName[c], zones = {} }
        contNodes[c] = cnode
        tree[#tree + 1] = cnode
      end
      local znode = zoneNodes[z]
      if znode == nil then
        znode = { key = z, name = zoneName[z], inns = {} }
        zoneNodes[z] = znode
        cnode.zones[#cnode.zones + 1] = znode
      end
      znode.inns[#znode.inns + 1] = { key = p, name = innName[p] }
    end
  end
  tsort(tree, nodeLess)
  for _, cnode in ipairs(tree) do
    tsort(cnode.zones, nodeLess)
    for _, znode in ipairs(cnode.zones) do
      tsort(znode.inns, nodeLess)
    end
  end

  -- The catalog, read once per call: quills and seals only, by ID.
  local function catalogItems()
    local cat = catalogOf()
    local out = {}
    if type(cat) ~= "table" then
      return out
    end
    for i = 1, ID_MAX + 1 do
      local rec = rawget(cat, i)
      if rec == nil then
        break
      end
      local id = type(rec) == "table" and rawget(rec, "id") or nil
      local kind = type(rec) == "table" and rawget(rec, "kind") or nil
      if isInt(id, 1, ID_MAX) and type(kind) == "string" and SHOWN_KINDS[kind] then
        out[#out + 1] = rec
      end
    end
    tsort(out, function(a, b) return a.id < b.id end)
    return out
  end

  -- id -> t for the unlocked list, read raw, at most `max` items.
  local function unlockedMap(list, max)
    local out = {}
    if type(list) ~= "table" then
      return out
    end
    for i = 1, max do
      local item = rawget(list, i)
      if item == nil then
        break
      end
      if type(item) == "table" then
        local id, t = rawget(item, "id"), rawget(item, "t")
        if isInt(id, 1, ID_MAX) and isInt(t, T_MIN, T_MAX) and out[id] == nil then
          out[id] = t
        end
      end
    end
    return out
  end

  -- The quill to draw with: `quill` if it's an unlocked quill, else 0 (the plain quill).
  local function effectiveQuill(quill, unlocked)
    if not isInt(quill, 1, ID_MAX) then
      return 0
    end
    local rec = info(quill)
    if type(rec) ~= "table" or rawget(rec, "kind") ~= "quill" then
      return 0
    end
    if unlockedMap(unlocked, #catalogOf() + 1)[quill] ~= nil then
      return quill
    end
    return 0
  end

  -- The flourish of each catalog quill, by its rank among the quills by ID.
  local function flourishes(cat)
    local out, rank = {}, 0
    for _, rec in ipairs(cat) do
      if rec.kind == "quill" then
        rank = rank + 1
        out[rec.id] = FLOURISHES[((rank - 1) % #FLOURISHES) + 1]
      end
    end
    return out
  end

  local function emptyProgress()
    return { signed = 0, total = 0, byContinent = {}, byZone = {}, inns = {} }
  end

  -- Everything one build reads, gathered once and only as far as the tab needs it.
  local function context(s)
    local ledger = rawget(s, "ledger")
    if type(ledger) ~= "table" then
      ledger = nil
    end
    local faction = rawget(s, "faction")
    if type(faction) ~= "string" or FACTIONS[faction] ~= true then
      faction = nil
    end
    local own = ask(ledger, "own")
    if type(own) ~= "table" then
      own = {}
    end
    local ctx = { ledger = ledger, faction = faction, own = own, offset = rawget(s, "offset") }
    function ctx.progress()
      if ctx.p == nil then
        local p = progressOf(own, faction)
        if type(p) ~= "table" or type(p.inns) ~= "table" or type(p.byZone) ~= "table"
          or type(p.byContinent) ~= "table" then
          p = emptyProgress()
        end
        ctx.p = p
      end
      return ctx.p
    end
    function ctx.catalog()
      if ctx.cat == nil then
        ctx.cat = catalogItems()
      end
      return ctx.cat
    end
    function ctx.unlocked()
      if ctx.u == nil then
        local earned = ask(ledger, "earned")
        if type(earned) ~= "table" then
          earned = nil
        end
        local list = unlockedOf(own, faction, earned)
        local u = {}
        if type(list) == "table" then
          for i = 1, #ctx.catalog() + 1 do
            local item = rawget(list, i)
            if item == nil then
              break
            end
            if type(item) == "table" then
              local id, t = rawget(item, "id"), rawget(item, "t")
              if isInt(id, 1, ID_MAX) and isInt(t, T_MIN, T_MAX) then
                u[#u + 1] = { id = id, t = t }
              end
            end
          end
        end
        ctx.u = u
      end
      return ctx.u
    end
    return ctx
  end

  -- Navigation (spec 3.3): the tab, the inn, and every page kept or reset.
  local function normalize(nav)
    local tab = rawget(nav, "tab")
    if type(tab) ~= "string" or TABS[tab] ~= true then
      tab = "inns"
    end
    local inn = rawget(nav, "inn")
    if not isInt(inn, 1, INN_MAX) or innOf(inn) ~= inn or innRec(inn) == nil then
      inn = nil
    end
    local out = { tab = tab, inn = inn }
    local listPage = rawget(nav, "listPage")
    out.listPage = isInt(listPage, 0, PAGE_MAX) and listPage or nil
    for _, k in ipairs({ "innPage", "barPage", "stampPage", "quillPage", "sealPage" }) do
      local v = rawget(nav, k)
      out[k] = isInt(v, 1, PAGE_MAX) and v or 1
    end
    return out
  end

  local function defaultNav()
    return { tab = "inns", innPage = 1, barPage = 1, stampPage = 1, quillPage = 1,
      sealPage = 1 }
  end

  -- -------------------------------------------------------------------------
  -- The Inns tab (spec 3.4).

  local function listRows(p, selected)
    local rows = {}
    for _, cnode in ipairs(tree) do
      local c = p.byContinent[cnode.key]
      if c ~= nil then
        local crow = { kind = "continent", text = cnode.name, sub = ofTotal(c), heads = {} }
        rows[#rows + 1] = crow
        for _, znode in ipairs(cnode.zones) do
          local z = p.byZone[znode.key]
          if z ~= nil then
            local zrow = { kind = "zone", text = znode.name,
              sub = TEXT.signedPrefix .. ofTotal(z), heads = { crow } }
            rows[#rows + 1] = zrow
            for _, inode in ipairs(znode.inns) do
              local st = p.inns[inode.key]
              if type(st) == "table" and st.open then
                local count = st.count or 0
                rows[#rows + 1] = { kind = "inn", key = inode.key, text = inode.name,
                  signed = count >= 1, faded = count == 0, selected = inode.key == selected,
                  heads = { crow, zrow } }
              end
            end
          end
        end
      end
    end
    return rows
  end

  -- A model row: the fields without the paging bookkeeping.
  local function listRow(r, cont)
    local out = { kind = r.kind, text = r.text, sub = r.sub }
    if r.kind == "inn" then
      out.key, out.signed, out.faded, out.selected = r.key, r.signed, r.faded, r.selected
    end
    if cont then
      out.cont = true
    end
    return out
  end

  local function repeatList(h)
    return { repeated = h }
  end

  local function titlePage(s, pages)
    local name = plainOr(rawget(s, "name"), LIMITS.nameBytes, nil)
    return {
      kind = "title",
      title = name ~= nil and TEXT.titleOf .. name or TEXT.titleNoName,
      steps = { TEXT.step1, TEXT.step2, TEXT.step3 },
      hint = TEXT.hint,
      page = 0,
      pages = pages,
    }
  end

  local function helpPage()
    return {
      kind = "help",
      travelersTitle = TEXT.travelersTitle,
      travelersText = TEXT.travelersText,
      sharesTitle = TEXT.sharesTitle,
      sharesText = TEXT.sharesText,
    }
  end

  local function sealLabel(id)
    local rec = info(id)
    if type(rec) ~= "table" or rawget(rec, "kind") ~= "seal" then
      return TEXT.aSeal
    end
    local name = nameOf(rec)
    if name == "" then
      return TEXT.aSeal
    end
    local rule = rawget(rec, "rule")
    if type(rule) == "table" and rawget(rule, "kind") == "zone" then
      return name .. TEXT.zoneSealSuffix
    end
    return name
  end

  -- Reads the newest `cap` items of a list the ledger returned (it returns oldest first),
  -- raw, into `out`. Only valid items: an entry (own) or { signer, name, entry } (foreign).
  local function readNewest(list, cap, out, foreign)
    if type(list) ~= "table" then
      return
    end
    local n = #list -- a table's length never runs a metamethod in Lua 5.1
    local first = n - cap + 1
    if first < 1 then
      first = 1
    end
    for i = n, first, -1 do
      local item = rawget(list, i)
      if foreign then
        if type(item) == "table" then
          local e, signer = rawget(item, "entry"), rawget(item, "signer")
          if type(signer) == "string" and validEntry(e) then
            out[#out + 1] = { e = e, signer = signer, name = rawget(item, "name") }
          end
        end
      elseif validEntry(item) then
        out[#out + 1] = { e = item }
      end
    end
  end

  local function ownLess(a, b)
    local x, y = rawget(a.e, "t"), rawget(b.e, "t")
    if x ~= y then
      return x > y
    end
    return rawget(a.e, "inn") < rawget(b.e, "inn")
  end

  local function foreignLess(a, b)
    local x, y = rawget(a.e, "t"), rawget(b.e, "t")
    if x ~= y then
      return x > y
    end
    if a.signer ~= b.signer then
      return strLess(a.signer, b.signer)
    end
    return rawget(a.e, "inn") < rawget(b.e, "inn")
  end

  local function trim(list, cap)
    for i = #list, cap + 1, -1 do
      list[i] = nil
    end
  end

  local function repeatHeading(h)
    return { kind = "heading", text = h.text, cont = true }
  end

  local function innPage(ctx, s, key, nav)
    local p = ctx.progress()
    local st = p.inns[key]
    if type(st) ~= "table" then
      st = { count = 0 }
    end
    local count = isInt(st.count, 0, math.huge) and st.count or 0
    local offset = ctx.offset

    -- 1. The entries of every NPC ID of the group, newest first, capped.
    local own, foreign = {}, {}
    for _, id in ipairs(groups[key] or { key }) do
      local res = ask(ctx.ledger, "innEntries", id)
      if type(res) == "table" then
        readNewest(rawget(res, "own"), LIMITS.ownReadMax, own, false)
        readNewest(rawget(res, "foreign"), LIMITS.foreignReadMax, foreign, true)
      end
    end
    tsort(own, ownLess)
    tsort(foreign, foreignLess)
    trim(own, LIMITS.ownReadMax)
    trim(foreign, LIMITS.foreignReadMax)

    -- 2. The row sequence, unrendered: the page count comes from it alone.
    local rows = {}
    local hYours = { kind = "heading", text = TEXT.yours, heads = {} }
    rows[1] = hYours
    for _, item in ipairs(own) do
      rows[#rows + 1] = { kind = "own", item = item, heads = { hYours } }
    end
    if #own == 0 then
      rows[#rows + 1] = { kind = "note", text = TEXT.noOwn, heads = { hYours } }
    end
    local hTravelers = { kind = "heading", text = TEXT.travelers, heads = {} }
    rows[#rows + 1] = hTravelers
    for _, item in ipairs(foreign) do
      rows[#rows + 1] = { kind = "foreign", item = item, heads = { hTravelers } }
    end
    if #foreign == 0 then
      rows[#rows + 1] = { kind = "note", text = TEXT.noForeign, heads = { hTravelers } }
    end
    local pages = paginate(rows, size.innRows, repeatHeading)
    nav.innPage = clamp(nav.innPage, 1, #pages)

    -- 3. Only the requested page is rendered.
    local flourish
    if rawget(s, "quill") ~= nil then
      flourish = flourishes(ctx.catalog())[effectiveQuill(rawget(s, "quill"), ctx.unlocked())]
    end
    local out = {}
    for _, r in ipairs(pages[nav.innPage]) do
      if r.cont then
        out[#out + 1] = r
      elseif r.kind == "heading" or r.kind == "note" then
        out[#out + 1] = { kind = r.kind, text = r.text }
      else
        local e = r.item.e
        local text = render(rawget(e, "phrase"))
        if type(text) ~= "string" then
          text = TEXT.faded
        end
        local row = { kind = r.kind, date = dateText(rawget(e, "t"), offset), text = text }
        local seal = rawget(e, "seal")
        if seal ~= nil then
          row.seal = TEXT.sealedWith .. sealLabel(seal)
        end
        if r.kind == "own" then
          row.flourish = flourish
        else
          row.name = plainOr(r.item.name, LIMITS.nameBytes, TEXT.aTraveler)
        end
        out[#out + 1] = row
      end
    end

    local countText
    if count == 0 then
      countText = TEXT.notSigned
    elseif count == 1 then
      countText = TEXT.signedOnce
    else
      countText = TEXT.signedTimes1 .. count .. TEXT.signedTimes2
    end
    local irec = innRec(key)
    local z = type(irec) == "table" and rawget(irec, "zone") or nil
    local zrec = z ~= nil and zoneRec(z) or nil
    local c = type(zrec) == "table" and rawget(zrec, "continent") or nil
    local crec = c ~= nil and contRec(c) or nil
    return {
      kind = "inn",
      key = key,
      title = nameOf(irec),
      place = nameOf(zrec) .. ", " .. nameOf(crec),
      stamp = { signed = count >= 1, date = count >= 1 and dateText(st.first, offset) or nil },
      countText = countText,
      lastText = count >= 2 and TEXT.lastSigned .. (dateText(st.last, offset) or "") or nil,
      rows = out,
      page = nav.innPage,
      pages = #pages,
    }
  end

  local function innsTab(ctx, s, nav, model)
    local p = ctx.progress()
    local rows = listRows(p, nav.inn)
    local pages = paginate(rows, size.listRows, repeatList)
    local n = #pages

    if nav.listPage == nil then
      local holding
      if nav.inn ~= nil then
        for i, page in ipairs(pages) do
          for _, r in ipairs(page) do
            if r.kind == "inn" and r.key == nav.inn then
              holding = i
            end
          end
        end
      end
      if holding ~= nil then
        nav.listPage = holding
      elseif rawget(ctx.own, 1) == nil then
        nav.listPage = 0
      else
        nav.listPage = 1
      end
    end
    nav.listPage = clamp(nav.listPage, 0, n)

    if nav.listPage == 0 then
      model.left = titlePage(s, n)
    else
      local out = {}
      for _, r in ipairs(pages[nav.listPage]) do
        if r.repeated then
          out[#out + 1] = listRow(r.repeated, true)
        else
          out[#out + 1] = listRow(r, false)
        end
      end
      model.left = { kind = "list", rows = out, page = nav.listPage, pages = n }
      if #rows == 0 then
        model.left.empty = TEXT.noInns
      end
    end

    if nav.inn ~= nil then
      model.right = innPage(ctx, s, nav.inn, nav)
    else
      model.right = helpPage()
    end
  end

  -- -------------------------------------------------------------------------
  -- The Collection tab (spec 3.5).

  local function zonesDone(p)
    local done, total = 0, 0
    for _, z in next, p.byZone do
      total = total + 1
      if z.done ~= nil then
        done = done + 1
      end
    end
    return done, total
  end

  local function collectionTab(ctx, nav, model)
    local p = ctx.progress()
    local counts = ask(ctx.ledger, "counts")
    local ownCount, travelers = 0, 0
    if type(counts) == "table" then
      local o, t = rawget(counts, "own"), rawget(counts, "travelers")
      ownCount = isInt(o, 0, COUNT_MAX) and o or 0
      travelers = isInt(t, 0, COUNT_MAX) and t or 0
    end
    local done, zones = zonesDone(p)

    local bars = {}
    for _, cnode in ipairs(tree) do
      local c = p.byContinent[cnode.key]
      if c ~= nil and c.total >= 1 then
        bars[#bars + 1] = { name = cnode.name, signed = c.signed, total = c.total,
          fraction = c.signed / c.total, text = ofTotal(c) }
      end
    end
    local barPages = ceilDiv(#bars, size.barRows)
    nav.barPage = clamp(nav.barPage, 1, barPages)
    local shown = {}
    for i = (nav.barPage - 1) * size.barRows + 1, math.min(#bars, nav.barPage * size.barRows) do
      shown[#shown + 1] = bars[i]
    end
    model.left = {
      kind = "summary",
      signedText = ofTotal(p) .. TEXT.innsSigned,
      zonesText = TEXT.zonesDone .. done .. TEXT.of .. zones,
      signaturesText = TEXT.signatures .. ownCount,
      travelersText = TEXT.travelersMet .. travelers,
      bars = shown,
      page = nav.barPage,
      pages = barPages,
    }
    if p.total == 0 then
      model.left.empty = TEXT.noInns
    end

    -- Stamps: each continent starts a new page.
    local pages = {}
    for _, cnode in ipairs(tree) do
      if p.byContinent[cnode.key] ~= nil then
        local page
        for _, znode in ipairs(cnode.zones) do
          for _, inode in ipairs(znode.inns) do
            local st = p.inns[inode.key]
            if type(st) == "table" and st.open then
              if page == nil or #page.cells >= size.stampCells then
                page = { title = cnode.name, cells = {} }
                pages[#pages + 1] = page
              end
              local signed = (st.count or 0) >= 1
              page.cells[#page.cells + 1] = { key = inode.key, name = inode.name, signed = signed,
                date = signed and dateText(st.first, ctx.offset) or nil }
            end
          end
        end
      end
    end
    if #pages == 0 then
      nav.stampPage = 1
      model.right = { kind = "stamps", cells = {}, empty = TEXT.noInns, page = 1, pages = 1 }
      return
    end
    nav.stampPage = clamp(nav.stampPage, 1, #pages)
    local page = pages[nav.stampPage]
    model.right = { kind = "stamps", title = page.title, cells = page.cells,
      page = nav.stampPage, pages = #pages }
  end

  -- -------------------------------------------------------------------------
  -- The Cosmetics tab (spec 3.6).

  -- The continent nearest done: largest signed / total, then more signed, then smaller key.
  -- Only a complete continent can earn the rule (collection-cosmetics.md 3.11), so only
  -- those are candidates.
  local function nearestContinent(p)
    local best, bestKey
    for key, c in next, p.byContinent do
      if rawequal(rawget(c, "complete"), true) then
        local better = best == nil
        if not better then
          local a, b = c.signed * best.total, best.signed * c.total
          if a ~= b then
            better = a > b
          elseif c.signed ~= best.signed then
            better = c.signed > best.signed
          else
            better = key < bestKey
          end
        end
        if better then
          best, bestKey = c, key
        end
      end
    end
    return best
  end

  local function minOf(a, b)
    if a < b then
      return a
    end
    return b
  end

  -- "<rule text> . <progress>" for a locked item.
  local function ruleStatus(rule, p)
    local kind = type(rule) == "table" and rawget(rule, "kind") or nil
    local n = type(rule) == "table" and rawget(rule, "n") or nil
    local text, progress
    if kind == "inns" and isInt(n, 1, math.huge) then
      text = TEXT.ruleInns1 .. n .. TEXT.ruleInns2
      progress = minOf(p.signed, n) .. TEXT.of .. n
    elseif kind == "zones" and isInt(n, 1, math.huge) then
      text = TEXT.ruleZones1 .. n .. TEXT.ruleZones2
      progress = minOf((zonesDone(p)), n) .. TEXT.of .. n
    elseif kind == "continent" then
      text = TEXT.ruleContinent
      local c = nearestContinent(p)
      progress = c and ofTotal(c) or (0 .. TEXT.of .. 1)
    elseif kind == "all" then
      text = TEXT.ruleAll
      progress = ofTotal(p)
    elseif kind == "zone" then
      local z = rawget(rule, "zone")
      text = TEXT.ruleZone .. nameOf(z ~= nil and zoneRec(z) or nil)
      local zp = z ~= nil and p.byZone[z] or nil
      progress = zp and ofTotal(zp) or (0 .. TEXT.of .. 0)
    else
      return ""
    end
    return text .. TEXT.dot .. progress
  end

  local function pageOf(rows, per, pageNo)
    local pages = ceilDiv(#rows, per)
    pageNo = clamp(pageNo, 1, pages)
    local out = {}
    for i = (pageNo - 1) * per + 1, math.min(#rows, pageNo * per) do
      out[#out + 1] = rows[i]
    end
    return out, pageNo, pages
  end

  local function cosmeticsTab(ctx, s, nav, model)
    local p = ctx.progress()
    local cat = ctx.catalog()
    local u = ctx.unlocked()
    local uMap = unlockedMap(u, #u)
    local quill = effectiveQuill(rawget(s, "quill"), u)
    local writable = rawequal(rawget(s, "prefsWritable"), true)

    local quills = { { id = 0, name = TEXT.plainQuill, unlocked = true } }
    for _, rec in ipairs(cat) do
      if rec.kind == "quill" then
        quills[#quills + 1] = { id = rec.id, name = nameOf(rec), unlocked = uMap[rec.id] ~= nil,
          rule = rec.rule }
      end
    end
    local rows = {}
    for i, q in ipairs(quills) do
      local chosen = q.id == quill
      local status
      if chosen then
        status = TEXT.inUse
      elseif q.id == 0 then
        status = TEXT.alwaysYours
      elseif q.unlocked then
        status = TEXT.earnedOn .. (dateText(uMap[q.id], ctx.offset) or "")
      else
        status = ruleStatus(q.rule, p)
      end
      rows[i] = { id = q.id, name = q.name, unlocked = q.unlocked, chosen = chosen,
        canUse = q.unlocked and not chosen and writable, status = status }
    end
    local shown, page, pages = pageOf(rows, size.quillRows, nav.quillPage)
    nav.quillPage = page
    model.left = { kind = "quills", title = TEXT.quillsTitle, rows = shown, page = page,
      pages = pages }

    local seals = {}
    for _, rec in ipairs(cat) do
      if rec.kind == "seal" then
        local rule = rec.rule
        local zone = type(rule) == "table" and rawget(rule, "kind") == "zone"
          and rawget(rule, "zone") or nil
        local earned = uMap[rec.id] ~= nil
        if earned or zone == nil or p.byZone[zone] ~= nil then
          seals[#seals + 1] = {
            id = rec.id,
            name = sealLabel(rec.id),
            earned = earned,
            status = earned and TEXT.earnedOn .. (dateText(uMap[rec.id], ctx.offset) or "")
              or ruleStatus(rule, p),
          }
        end
      end
    end
    shown, page, pages = pageOf(seals, size.sealRows, nav.sealPage)
    nav.sealPage = page
    model.right = { kind = "seals", title = TEXT.sealsTitle, hint = TEXT.sealHint, rows = shown,
      page = page, pages = pages }
  end

  -- -------------------------------------------------------------------------
  -- The Share tab (spec 3.7).

  local function shareTab(ctx, s, model)
    local current = snapshot(ctx.own, ctx.unlocked())
    model.left = {
      kind = "share",
      title = TEXT.shareTitle,
      help = TEXT.shareHelp,
      include = TEXT.include,
      nudge = nudge(rawget(s, "shared"), current),
    }
    model.right = { kind = "shareInfo", title = TEXT.shareInfoTitle, text = TEXT.shareInfoText }
  end

  -- -------------------------------------------------------------------------

  local function build(s, nav)
    if type(s) ~= "table" then
      s = {}
    end
    if type(nav) ~= "table" then
      nav = {}
    end
    local n = normalize(nav)
    local ctx = context(s)
    local model = { tab = n.tab, nav = n }
    if ctx.ledger == nil then
      model.notice = TEXT.noLedger
    elseif rawget(ctx.ledger, "readOnly") ~= false then
      model.notice = TEXT.readOnly
    end
    if n.tab == "inns" then
      innsTab(ctx, s, n, model)
    elseif n.tab == "collection" then
      collectionTab(ctx, n, model)
    elseif n.tab == "cosmetics" then
      cosmeticsTab(ctx, s, n, model)
    else
      shareTab(ctx, s, model)
    end
    return model
  end

  local view = {}
  view.build = safe(build, function()
    return { tab = "inns", nav = defaultNav(), error = true }
  end)
  view.innKey = safe(function(npc)
    local key = innOf(npc)
    if isInt(key, 1, INN_MAX) then
      return key
    end
    return nil
  end, function() return nil end)
  view.effectiveQuill = safe(effectiveQuill, function() return 0 end)
  return view
end
