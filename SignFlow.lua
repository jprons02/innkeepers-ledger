-- SignFlow (pure): every decision of signing the guestbook. When the button shows, the
-- checks and their reasons, the seals a signature may carry, the commit (one own entry
-- through addOwn, then the unlocks recorded), the composer's state (the draft) and the
-- chat lines. No WoW API here. Client values come in as arguments (docs/architecture.md
-- -> Modules); the glue is Sign.lua. Spec: docs/specs/sign.md (sections 3.2-3.6, 3.8).
-- Every entry this creates is broadcast to peers, so it only ever writes through
-- ledger:addOwn and ledger:markEarned. Every flow function runs in pcall and returns its
-- failure value on any argument; only SignFlow.new (a caller bug) and the load can raise.
local _, ns = ...

local Ledger = ns.Ledger
assert(type(Ledger) == "table", "SignFlow needs ns.Ledger; Ledger.lua comes first in the TOC")

local SignFlow = {}
ns.SignFlow = SignFlow

local floor, ceil = math.floor, math.ceil
local find, sub = string.find, string.sub
local tsort = table.sort

local LIMITS = Ledger.LIMITS -- read from Ledger, not second literals
local T_MIN, T_MAX = LIMITS.tMin, LIMITS.tMax
local INN_MAX = LIMITS.innMax
local IDS_MAX = LIMITS.phraseIdsMax
local SEAL_MAX = LIMITS.sealMax
local SLOT = "{w}"          -- a template's word slot (docs/specs/phrase.md 3.1)
local SLOT_SHOWN = "___"    -- how the composer shows the slot
local FACTIONS = { Alliance = true, Horde = true }

-- DRAFT: every player-facing line here is the maintainer's to decide (spec 3.7 and 3.8;
-- the button's label, "Sign the guestbook", is settled). Our own constants only: no `|`,
-- no `%`, no site, product or service. Lines are built by concatenation, never format.
local TEXT = {
  -- The composer (Sign.lua).
  button = "Sign the guestbook",
  title = "Sign the guestbook",
  addSecond = "Add a second line",
  removeSecond = "Remove the second line",
  sign = "Sign",
  cancel = "Cancel",
  noSeal = "No seal",
  voice = "Voice: ",
  -- The chat lines, one per result code.
  added = "You signed the guestbook of ",
  addedEnd = ".",
  theInn = "the inn",
  no_ledger = "Your ledger isn't open yet. Try again in a moment.",
  readonly = "Your ledger is read-only (saved by a newer version, or damaged), so nothing "
    .. "was signed.",
  not_inn = "Talk to the innkeeper again to sign the guestbook.",
  changed = "Talk to the innkeeper again to sign the guestbook.",
  clock = "The server time can't be read right now. Try again in a moment.",
  too_soon = "You've signed this guestbook this week. Sign again after the weekly reset (",
  too_soonEnd = ").",
  not_resting = "Rest at the inn to sign its guestbook.",
  phrase = "That phrase can't be signed. Choose another.",
  seal = "That seal can't be used yet. Choose another.",
  no_phrases = "There are no phrases to sign with.",
  dup = "Nothing was signed.",
  invalid = "Nothing was signed.",
  error = "Nothing was signed.",
  -- untilText.
  inPrefix = "in ",
  day = " day",
  days = " days",
  hour = " hour",
  hours = " hours",
  minute = " minute",
  minutes = " minutes",
  soon = "soon",
}

-- The result codes of a check or commit besides "added" (spec 3.3, 3.4, 3.8).
local REASONS = {
  no_ledger = true, readonly = true, not_inn = true, clock = true, too_soon = true,
  not_resting = true, changed = true, phrase = true, seal = true, no_phrases = true,
  dup = true, invalid = true, error = true,
}
-- What addOwn may answer besides "added"; anything else counts as "error".
local ADD_RESULTS = { dup = true, too_soon = true, invalid = true, readonly = true }

local function copySet(t)
  local out = {}
  for k, v in next, t do
    out[k] = v
  end
  return out
end

SignFlow.TEXT = copySet(TEXT)
SignFlow.REASONS = copySet(REASONS)

-- An integer in lo..hi. NaN fails x == x; inf % 1 is NaN, so inf fails too.
local function isInt(x, lo, hi)
  return type(x) == "number" and x == x and x % 1 == 0 and x >= lo and x <= hi
end

local function factionOf(f)
  if type(f) == "string" and FACTIONS[f] == true then
    return f
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- Messages (spec 3.8).

local DAY, HOUR, MINUTE = 86400, 3600, 60

-- "in 3 days", "in 47 hours", "in 1 minute"; "soon" for anything not a whole n >= 0.
function SignFlow.untilText(n)
  if not isInt(n, 0, T_MAX) then
    return TEXT.soon
  end
  if n >= 2 * DAY then
    return TEXT.inPrefix .. floor(n / DAY) .. TEXT.days
  elseif n >= HOUR then
    local h = floor(n / HOUR)
    return TEXT.inPrefix .. h .. (h == 1 and TEXT.hour or TEXT.hours)
  end
  local m = ceil(n / MINUTE)
  if m < 1 then
    m = 1
  end
  return TEXT.inPrefix .. m .. (m == 1 and TEXT.minute or TEXT.minutes)
end

-- The inn's name for the `added` line: a string with no UI escape, else "the inn".
local function shownName(name)
  if type(name) == "string" and #name > 0 and not find(name, "|", 1, true) then
    return name
  end
  return TEXT.theInn
end

local function messageOf(res, name)
  local code
  if type(res) == "table" then
    code = rawget(res, "reason")
    if code == nil then
      code = rawget(res, "result")
    end
  end
  if code == "added" then
    return TEXT.added .. shownName(name) .. TEXT.addedEnd
  elseif type(code) ~= "string" or REASONS[code] ~= true then
    return TEXT.error
  elseif code == "too_soon" then
    return TEXT.too_soon .. SignFlow.untilText(rawget(res, "wait")) .. TEXT.too_soonEnd
  end
  return TEXT[code]
end

-- The one chat line for a check or commit result; an unknown code gets the error line.
function SignFlow.message(res, name)
  local ok, line = pcall(messageOf, res, name)
  if ok and type(line) == "string" then
    return line
  end
  return TEXT.error
end

-- ---------------------------------------------------------------------------
-- The flow (spec 3.2).

local function need(t, key, what)
  local f = rawget(t, key)
  if type(f) ~= "function" then
    error("SignFlow.new: deps." .. what .. "." .. key .. " must be a function", 3)
  end
  return f
end

local function depTable(deps, key)
  local t = rawget(deps, key)
  if type(t) ~= "table" then
    error("SignFlow.new: deps." .. key .. " must be a table", 3)
  end
  return t
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

local function none()
  return nil
end

local function emptyList()
  return {}
end

-- A raw copy of a caller's phrase IDs, or nil: a table with a metatable, or with more
-- keys than a phrase can hold, is refused. validIds then checks the copy's shape.
local function copyIds(ids)
  if type(ids) ~= "table" or getmetatable(ids) ~= nil then
    return nil
  end
  local out, n = {}, 0
  for k, v in next, ids do
    n = n + 1
    if n > IDS_MAX then
      return nil
    end
    out[k] = v
  end
  return out
end

local function copyEntry(e)
  local phrase = {}
  for i, id in ipairs(e.phrase) do
    phrase[i] = id
  end
  return { inn = e.inn, t = e.t, phrase = phrase, seal = e.seal }
end

function SignFlow.new(deps)
  if type(deps) ~= "table" then
    error("SignFlow.new: deps must be a table", 2)
  end
  local inns = depTable(deps, "inns")
  local atlas = depTable(deps, "atlas")
  local phrase = depTable(deps, "phrase")
  local cosmetics = depTable(deps, "cosmetics")
  local innOf, innRec = need(atlas, "innOf", "atlas"), need(atlas, "inn", "atlas")
  local validIds = need(phrase, "validIds", "phrase")
  local render = need(phrase, "render", "phrase")
  local compose = need(phrase, "compose", "phrase")
  local phraseText = need(phrase, "text", "phrase")
  local hasSlot = need(phrase, "hasSlot", "phrase")
  local templatesOf = need(phrase, "templates", "phrase")
  local conjunctionsOf = need(phrase, "conjunctions", "phrase")
  local categoriesOf = need(phrase, "categories", "phrase")
  local wordsOf = need(phrase, "words", "phrase")
  -- Optional: a phrase set without voices offers every template as one group.
  local voicesOf = rawget(phrase, "voices")
  if type(voicesOf) ~= "function" then
    voicesOf = emptyList
  end
  local unlocked = need(cosmetics, "unlocked", "cosmetics")
  local canSeal = need(cosmetics, "canSeal", "cosmetics")
  local info = need(cosmetics, "info", "cosmetics")
  local SEALS = rawget(cosmetics, "SEALS")
  if type(SEALS) ~= "table" then
    error("SignFlow.new: deps.cosmetics.SEALS must be a table", 2)
  end

  local flow = {}

  -- The NPC ID behind a creature GUID if it's an inn the atlas kept, else nil.
  local function innAt(npc)
    local id = Ledger.innFromNpcGUID(npc, inns)
    if id == nil or innOf(id) == nil then
      return nil
    end
    return id
  end

  -- The inn's name (an alias shows its primary's), or nil.
  local function innName(id)
    local key = innOf(id)
    local rec = key ~= nil and innRec(key) or nil
    local name = type(rec) == "table" and rawget(rec, "name") or nil
    if type(name) == "string" then
      return name
    end
    return nil
  end

  -- The unlocks of the ledger's own entries (Cosmetics.unlocked; kept floors included).
  local function unlocksOf(ledger, faction)
    return unlocked(ledger:own(), factionOf(faction), ledger:earned())
  end

  local function tooSoon(key, ledger, now)
    local res = { reason = "too_soon" }
    if key == "result" then
      res = { result = "too_soon" }
    end
    local wait = ledger:nextWeekStart(now) - now
    if isInt(wait, 0, T_MAX) then
      res.wait = wait
    end
    return res
  end

  -- Spec 3.3, in order.
  local function check(s)
    local ledger = type(s) == "table" and rawget(s, "ledger") or nil
    if type(ledger) ~= "table" then
      return { ok = false, reason = "no_ledger" }
    end
    if rawget(ledger, "readOnly") ~= false then
      return { ok = false, reason = "readonly" }
    end
    local inn = innAt(rawget(s, "npc"))
    if inn == nil then
      return { ok = false, reason = "not_inn" }
    end
    local now = rawget(s, "now")
    if not isInt(now, T_MIN, T_MAX) then
      return { ok = false, reason = "clock" }
    end
    if ledger:canSign(inn, now) ~= true then
      local res = tooSoon("reason", ledger, now)
      res.ok = false
      return res
    end
    if not rawequal(rawget(s, "resting"), true) then
      return { ok = false, reason = "not_resting" }
    end
    return { ok = true, inn = inn, name = innName(inn) }
  end

  -- The seals of `u` usable at `now`, ascending, no duplicates.
  local function usable(u, now)
    local out, seen = {}, {}
    for i = 1, #u do
      local id = u[i].id
      if isInt(id, 1, SEAL_MAX) and not seen[id] and rawget(SEALS, id) ~= nil
        and canSeal(u, id, now) == true then
        seen[id] = true
        out[#out + 1] = id
      end
    end
    tsort(out)
    return out
  end

  local function seals(s)
    if check(s).ok ~= true then
      return {}
    end
    local ledger = rawget(s, "ledger")
    return usable(unlocksOf(ledger, rawget(s, "faction")), rawget(s, "now"))
  end

  -- Spec 3.5. Records every unlock not yet in `earned`; returns those IDs, ascending.
  local function recordUnlocks(ledger, faction)
    if type(ledger) ~= "table" or rawget(ledger, "readOnly") ~= false then
      return {}
    end
    local u = unlocksOf(ledger, faction)
    local out = {}
    for i = 1, #u do
      local id, t = u[i].id, u[i].t
      local before = ledger:earnedAt(id)
      if ledger:markEarned(id, t) == true and before == nil then
        out[#out + 1] = id
      end
    end
    tsort(out)
    return out
  end
  local safeRecord = safe(recordUnlocks, emptyList)

  -- Spec 3.4, in order.
  local function commit(s, inn, ids, seal)
    local ledger = type(s) == "table" and rawget(s, "ledger") or nil
    if type(ledger) ~= "table" then
      return { result = "no_ledger" }
    end
    if rawget(ledger, "readOnly") ~= false then
      return { result = "readonly" }
    end
    if not isInt(inn, 1, INN_MAX) or innAt(rawget(s, "npc")) ~= inn then
      return { result = "changed" }
    end
    local now = rawget(s, "now")
    if not isInt(now, T_MIN, T_MAX) then
      return { result = "clock" }
    end
    if ledger:canSign(inn, now) ~= true then
      return tooSoon("result", ledger, now)
    end
    if not rawequal(rawget(s, "resting"), true) then
      return { result = "not_resting" }
    end
    local phraseIds = copyIds(ids)
    if phraseIds == nil or validIds(phraseIds) ~= true then
      return { result = "phrase" }
    end
    local faction = rawget(s, "faction")
    if canSeal(unlocksOf(ledger, faction), seal, now) ~= true then
      return { result = "seal" }
    end
    local e = { inn = inn, t = now, phrase = phraseIds, seal = seal }
    local r = ledger:addOwn(e)
    if r ~= "added" then
      if type(r) ~= "string" or ADD_RESULTS[r] ~= true then
        return { result = "error" }
      elseif r == "too_soon" then
        return tooSoon("result", ledger, now)
      end
      return { result = r }
    end
    return { result = "added", entry = copyEntry(e), earned = safeRecord(ledger, faction) }
  end

  -- ---------------------------------------------------------------------------
  -- The draft (spec 3.6).

  local function templateLabel(id)
    local text = phraseText(id)
    if type(text) ~= "string" then
      return nil
    end
    local a = find(text, SLOT, 1, true)
    if a then
      return sub(text, 1, a - 1) .. SLOT_SHOWN .. sub(text, a + #SLOT)
    end
    return text
  end

  -- The voices the composer offers, each with its templates and conjunctions (a voice
  -- with no conjunction of its own offers them all). A voice with no template is skipped;
  -- with none left, one unnamed group holds everything (spec 3.6).
  local function voiceGroups()
    local groups, all = {}, conjunctionsOf()
    local names = voicesOf()
    for v = 1, type(names) == "table" and #names or 0 do
      local t, c = templatesOf(v), conjunctionsOf(v)
      if type(names[v]) == "string" and #t > 0 then
        groups[#groups + 1] = { name = names[v], templates = t, conjs = #c > 0 and c or all }
      end
    end
    if #groups == 0 then
      groups[1] = { templates = templatesOf(), conjs = all }
    end
    return groups
  end

  local function newDraft(sealIds)
    if #templatesOf() == 0 then
      return nil
    end
    local groups, cats = voiceGroups(), categoriesOf()
    local words = {}
    for i = 1, #cats do
      words[i] = wordsOf(i)
    end
    local sealList = {}
    if type(sealIds) == "table" and getmetatable(sealIds) == nil then
      for i = 1, SEAL_MAX do
        local id = rawget(sealIds, i)
        if id == nil then
          break
        elseif isInt(id, 1, SEAL_MAX) then
          sealList[#sealList + 1] = id
        end
      end
    end

    local st = {
      v1 = 1, t1 = 1, cat1 = 1, w1 = 1, v2 = 1, c = 1, t2 = 1, cat2 = 1, w2 = 1, seal = 0,
    }
    local second = false
    local v2Chosen = false -- until the player picks line 2's voice, it follows line 1's

    -- The list a field steps over, or nil for an unknown field.
    local function listOf(field)
      if field == "v1" or field == "v2" then
        return groups
      elseif field == "t1" then
        return groups[st.v1].templates
      elseif field == "t2" then
        return groups[st.v2].templates
      elseif field == "c" then
        return groups[st.v2].conjs
      elseif field == "cat1" or field == "cat2" then
        return cats
      elseif field == "w1" then
        return words[st.cat1] or {}
      elseif field == "w2" then
        return words[st.cat2] or {}
      end
      return nil
    end

    local function word(k)
      local list = words[st["cat" .. k]]
      return list and list[st["w" .. k]] or nil
    end

    local function idsNow()
      local g1, g2 = groups[st.v1], groups[st.v2]
      local t1 = g1.templates[st.t1]
      local w1 = hasSlot(t1) and word(1) or nil
      local c, t2, w2
      if second then
        c, t2 = g2.conjs[st.c], g2.templates[st.t2]
        w2 = hasSlot(t2) and word(2) or nil
      end
      return compose(t1, w1, c, t2, w2)
    end

    local draft = {}

    draft.step = safe(function(_, field, delta)
      if type(field) ~= "string" or type(delta) ~= "number" or (delta ~= 1 and delta ~= -1) then
        return
      end
      if field == "seal" then
        local n = #sealList
        if n > 0 then
          st.seal = (st.seal + delta) % (n + 1)
        end
        return
      end
      local list = listOf(field)
      if list == nil or #list == 0 then
        return
      end
      st[field] = (st[field] - 1 + delta) % #list + 1
      if field == "cat1" then
        st.w1 = 1
      elseif field == "cat2" then
        st.w2 = 1
      elseif field == "v1" then
        st.t1 = 1
        if not v2Chosen then
          st.v2, st.c, st.t2 = st.v1, 1, 1
        end
      elseif field == "v2" then
        v2Chosen = true
        st.c, st.t2 = 1, 1
      end
    end, none)

    draft.setSecond = safe(function(_, on)
      second = rawequal(on, true)
    end, none)

    draft.ids = safe(function()
      return idsNow()
    end, none)

    draft.seal = safe(function()
      if st.seal == 0 then
        return nil
      end
      return sealList[st.seal]
    end, none)

    draft.view = safe(function()
      local g1, g2 = groups[st.v1], groups[st.v2]
      local t1, t2 = g1.templates[st.t1], g2.templates[st.t2]
      local c = g2.conjs[st.c]
      local w1, w2 = word(1), word(2)
      local sealLabel = TEXT.noSeal
      if st.seal ~= 0 then
        local rec = info(sealList[st.seal])
        local name = type(rec) == "table" and rawget(rec, "name") or nil
        sealLabel = type(name) == "string" and name or tostring(sealList[st.seal])
      end
      local preview = render(idsNow())
      return {
        v1 = g1.name and TEXT.voice .. g1.name or nil,
        t1 = templateLabel(t1),
        cat1 = cats[st.cat1],
        w1 = w1 and phraseText(w1) or nil,
        v2 = g2.name and TEXT.voice .. g2.name or nil,
        c = c and phraseText(c) or nil,
        t2 = templateLabel(t2),
        cat2 = cats[st.cat2],
        w2 = w2 and phraseText(w2) or nil,
        seal = sealLabel,
        preview = type(preview) == "string" and preview or nil,
        word1 = hasSlot(t1) == true,
        word2 = second and hasSlot(t2) == true,
        second = second,
        sealRow = #sealList > 0,
        voiceRow = g1.name ~= nil,
      }
    end, none)

    return draft
  end

  flow.innAt = safe(innAt, none)
  flow.innName = safe(innName, none)
  flow.check = safe(check, function() return { ok = false, reason = "error" } end)
  flow.seals = safe(seals, emptyList)
  flow.commit = safe(commit, function() return { result = "error" } end)
  flow.recordUnlocks = safeRecord
  flow.newDraft = safe(newDraft, none)
  return flow
end
