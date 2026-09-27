-- SyncProtocol (pure): message codec, digest comparison and all validation of peer data.
-- No WoW API here. Client values come in as arguments (docs/architecture.md -> Modules).
-- Spec: docs/specs/sync-ledger.md (sections 3 and 5). Every byte a peer sends is hostile:
-- nothing reaches the ledger until the whole message has passed, and the only write is
-- ledger:addForeign under the resolved sender (the own-signature rule).
local _, ns = ...

local Ledger = ns.Ledger
assert(type(Ledger) == "table", "SyncProtocol needs ns.Ledger; Ledger.lua comes first in the TOC")

local SyncProtocol = {}
ns.SyncProtocol = SyncProtocol

local find, sub, match, byte = string.find, string.sub, string.match, string.byte
local concat, tsort = table.concat, table.sort

local LIMITS = Ledger.LIMITS
local validGUID, validName, validEntry = Ledger.validGUID, Ledger.validName, Ledger.validEntry

-- Constants (spec 5.1a). The locals below are what the code uses; the exported tables
-- are for callers and tests.
local VERSION = 1
local MAX_BYTES = 255
local MAX_ENTRIES = 5
local SHARE_MAX = Ledger.CAPS.perSigner
local CHANNELS = { PARTY = true, RAID = true, GUILD = true }

local WINDOW = 60              -- rate-limit window, seconds (spec 5.3)
local SENDER_MESSAGES = 40
local SENDER_ENTRIES = 80
local GLOBAL_MESSAGES = 1200
local MAX_SENDERS = 1000

local DIGEST_MOD = 2147483647  -- digest values are 0..DIGEST_MOD - 1 (spec 3.3)
local ASK_WINDOW = 600         -- at most ASK_MAX WANTs per peer per ASK_WINDOW (spec 3.3)
local ASK_MAX = 2
local SEEN_WINDOW = 30         -- a WANT seen this recently suppresses ours
local MEMO_MAX = 1000          -- keys in each of the WANT memo's tables

SyncProtocol.VERSION = VERSION
SyncProtocol.MAX_BYTES = MAX_BYTES
SyncProtocol.MAX_ENTRIES_PER_MSG = MAX_ENTRIES
SyncProtocol.SHARE_MAX = SHARE_MAX
SyncProtocol.CHANNELS = { PARTY = true, RAID = true, GUILD = true }
SyncProtocol.LIMITS = {
  window = WINDOW,
  perSenderMessages = SENDER_MESSAGES,
  perSenderEntries = SENDER_ENTRIES,
  globalMessages = GLOBAL_MESSAGES,
  maxSenders = MAX_SENDERS,
}
SyncProtocol.validName = validName
SyncProtocol.validGUID = validGUID

-- An integer in lo..hi. NaN fails x == x; inf % 1 is NaN, so inf fails too.
local function isInt(x, lo, hi)
  return type(x) == "number" and x == x and x % 1 == 0 and x >= lo and x <= hi
end

-- ---------------------------------------------------------------------------
-- Digest and encoders. These take our own entries, which Ledger has validated.

-- The canonical text of one entry, the same as its wire form (spec 3.3). Integers below
-- 10^14 print without an exponent, so every field prints as plain digits.
local function canon(e)
  return e.inn .. "," .. e.t .. "," .. concat(e.phrase, ".") .. "," .. (e.seal or 0)
end
SyncProtocol.canon = canon

-- h = (h * 257 + b) % DIGEST_MOD over the bytes of the joined canon texts. h < 2^31, so
-- every intermediate is below 2^40 and exact in a double; no bit library needed.
local function digest(entries)
  local parts = {}
  for i = 1, #entries do
    parts[i] = canon(entries[i])
  end
  local text = concat(parts, ";")
  local h = 0
  for i = 1, #text do
    h = (h * 257 + byte(text, i)) % DIGEST_MOD
  end
  return h
end
SyncProtocol.digest = digest

-- Encoders raise on a caller bug (they only ever see our own data), never on peer data.
local function checked(msg)
  if #msg > MAX_BYTES then
    error("SyncProtocol: message over " .. MAX_BYTES .. " bytes", 3)
  end
  return msg
end

local function checkEntries(window)
  if type(window) ~= "table" then
    error("SyncProtocol: window is not a table", 3)
  end
  for i = 1, #window do
    if not validEntry(window[i]) then
      error("SyncProtocol: window entry " .. i .. " is not a valid entry", 3)
    end
  end
end

function SyncProtocol.encodeHello(window)
  checkEntries(window)
  if #window > SHARE_MAX then
    error("SyncProtocol: HELLO window over " .. SHARE_MAX .. " entries", 2)
  end
  return checked("H" .. VERSION .. ":" .. #window .. ":" .. digest(window))
end

function SyncProtocol.encodeWant(targetGUID, since)
  if not validGUID(targetGUID) then
    error("SyncProtocol: WANT target is not a player GUID", 2)
  end
  if since ~= 0 and not isInt(since, LIMITS.tMin, LIMITS.tMax) then
    error("SyncProtocol: WANT since is not 0 or a valid time", 2)
  end
  return checked("W" .. VERSION .. ":" .. targetGUID .. ":" .. since)
end

-- Entries with t > since, oldest first by (t, inn), MAX_ENTRIES per message.
function SyncProtocol.encodeEntries(window, since)
  checkEntries(window)
  if not isInt(since, 0, LIMITS.tMax) then
    error("SyncProtocol: since is not a valid time", 2)
  end
  local list = {}
  for i = 1, #window do
    if window[i].t > since then
      list[#list + 1] = window[i]
    end
  end
  tsort(list, function(a, b)
    if a.t ~= b.t then
      return a.t < b.t
    end
    return a.inn < b.inn
  end)
  local out = {}
  for first = 1, #list, MAX_ENTRIES do
    local parts = {}
    for i = first, math.min(first + MAX_ENTRIES - 1, #list) do
      parts[#parts + 1] = canon(list[i])
    end
    out[#out + 1] = checked("E" .. VERSION .. ":" .. concat(parts, ";"))
  end
  return out
end

-- ---------------------------------------------------------------------------
-- WANT memo helpers (spec 3.3).

local function askExpired(a, now)
  return now < a.start or now >= a.start + ASK_WINDOW
end

local function seenExpired(s, now)
  return now < s.at or now > s.at + SEEN_WINDOW
end

-- Sets t[key] = value, holding t to MEMO_MAX keys: on a new key with t full, expired
-- keys go first, and if it's still full the whole table is cleared.
local function cappedSet(t, key, value, expired, now)
  if t[key] == nil then
    local n = 0
    for _ in next, t do
      n = n + 1
    end
    if n >= MEMO_MAX then
      n = 0
      for k, v in next, t do
        if expired(v, now) then
          t[k] = nil -- clearing fields during traversal is allowed
        else
          n = n + 1
        end
      end
      if n >= MEMO_MAX then
        for k in next, t do
          t[k] = nil
        end
      end
    end
  end
  t[key] = value
end

function SyncProtocol.newWantMemo()
  return { asked = {}, seen = {} }
end

-- The `since` to ask `guid` for after its HELLO on `channel`, or nil (spec 3.3).
-- `held` = ledger:signerEntries(guid).
function SyncProtocol.decideWant(memo, guid, channel, count, dig, held, now)
  if type(memo) ~= "table" or type(memo.asked) ~= "table" or type(memo.seen) ~= "table"
    or type(guid) ~= "string" or type(channel) ~= "string" or type(held) ~= "table"
    or not isInt(count, 0, SHARE_MAX) or not isInt(dig, 0, DIGEST_MOD - 1)
    or not isInt(now, 0, LIMITS.tMax) then
    return nil
  end
  -- 1-2. Nothing to fetch, or already in sync.
  if count == 0 or (#held == count and digest(held) == dig) then
    return nil
  end
  -- 3. Per-peer cap, whatever the digest.
  local a = memo.asked[guid]
  if a ~= nil and askExpired(a, now) then
    a = nil
  end
  if a ~= nil and a.n >= ASK_MAX then
    return nil
  end
  -- 4. A second ask starts from 0 to fill any gap.
  local since = 0
  if a == nil then
    for i = 1, #held do
      if held[i].t > since then
        since = held[i].t
      end
    end
  end
  -- 5. A broadcast reply that covers us is already coming on this channel.
  local key = channel .. ":" .. guid
  local s = memo.seen[key]
  if s ~= nil and not seenExpired(s, now) and s.since <= since then
    return nil
  end
  -- 6. Record and ask.
  if a ~= nil then
    a.n = a.n + 1
  else
    cappedSet(memo.asked, guid, { start = now, n = 1 }, askExpired, now)
  end
  cappedSet(memo.seen, key, { at = now, since = since }, seenExpired, now)
  return since
end

-- ---------------------------------------------------------------------------
-- Rate limiter (spec 5.3). Fixed windows per sender and globally. A message or batch
-- that is refused is charged to no counter.

local Limiter = {}
Limiter.__index = Limiter

function SyncProtocol.newLimiter()
  return setmetatable({ senders = {}, count = 0, global = nil }, Limiter)
end

local function windowExpired(w, now)
  return now < w.start or now >= w.start + WINDOW
end

-- Removes expired sender windows; they'd reset on their next message anyway.
function Limiter:_prune(now)
  for guid, w in next, self.senders do
    if windowExpired(w, now) then
      self.senders[guid] = nil
      self.count = self.count - 1
    end
  end
end

-- One message from `guid` at `now`: true if admitted (and counted), else false.
function Limiter:admit(guid, now)
  if type(guid) ~= "string" or not isInt(now, 0, LIMITS.tMax) then
    return false
  end
  local w = self.senders[guid]
  if w == nil and self.count >= MAX_SENDERS then
    self:_prune(now)
    if self.count >= MAX_SENDERS then
      return false -- fail closed
    end
  end
  local fresh = w == nil or windowExpired(w, now)
  local g = self.global
  local gfresh = g == nil or windowExpired(g, now)
  -- Both limits must admit before either counter moves.
  if (not fresh and w.messages >= SENDER_MESSAGES)
    or (not gfresh and g.messages >= GLOBAL_MESSAGES) then
    return false
  end
  if fresh then
    if w == nil then
      self.count = self.count + 1
    end
    w = { start = now, messages = 0, entries = 0 }
    self.senders[guid] = w
  end
  if gfresh then
    g = { start = now, messages = 0 }
    self.global = g
  end
  w.messages = w.messages + 1
  g.messages = g.messages + 1
  return true
end

-- `n` entries from `guid` at `now`, after `admit` admitted their message in this window.
-- A sender with no open window is refused (fail closed).
function Limiter:admitEntries(guid, n, now)
  if type(guid) ~= "string" or not isInt(n, 0, MAX_ENTRIES) or not isInt(now, 0, LIMITS.tMax) then
    return false
  end
  local w = self.senders[guid]
  if w == nil or windowExpired(w, now) or w.entries + n > SENDER_ENTRIES then
    return false
  end
  w.entries = w.entries + n
  return true
end

-- ---------------------------------------------------------------------------
-- Decoding (spec 3.2). Lua 5.1 patterns have no optional groups, so messages are split
-- on their separators and every piece is matched on its own.

-- The pieces of `s` between each `sep`, or nil unless there are minN..maxN of them and
-- none is empty. Stops early once there are too many.
local function pieces(s, sep, minN, maxN)
  local out, pos = {}, 1
  while true do
    local i = find(s, sep, pos, true)
    local piece = sub(s, pos, i and i - 1 or #s)
    if piece == "" then
      return nil
    end
    out[#out + 1] = piece
    if not i then
      break
    end
    if #out >= maxN then
      return nil
    end
    pos = i + 1
  end
  if #out < minN then
    return nil
  end
  return out
end

-- A number token: "0" (only if zeroOk) or a non-zero digit then digits, at most maxLen
-- bytes. Length and digits are checked before tonumber, which would accept hex,
-- exponents, signs, spaces, "nan" and "inf".
local function number(tok, maxLen, zeroOk)
  if tok == "0" then
    return zeroOk and 0 or nil
  end
  if #tok > maxLen or not find(tok, "^[1-9]%d*$") then
    return nil
  end
  return tonumber(tok)
end

-- A time token: exactly 10 digits, no leading zero.
local function time(tok)
  return #tok == 10 and number(tok, 10, false) or nil
end

-- HELLO body "count:digest" (rules 10-12).
local function parseHello(body)
  local f = pieces(body, ":", 2, 2)
  if not f then
    return nil, "schema"
  end
  local count, dig = number(f[1], 2, true), number(f[2], 10, true)
  if not count or not dig or dig >= DIGEST_MOD then
    return nil, "number"
  end
  if count > SHARE_MAX or (count == 0 and dig ~= 0) then
    return nil, "schema"
  end
  return { kind = "hello", count = count, digest = dig }
end

-- WANT body "target:since" (rules 10, 11 and 13's range; the target is handled later).
local function parseWant(body, now)
  local f = pieces(body, ":", 2, 2)
  if not f or not validGUID(f[1]) then
    return nil, "schema"
  end
  local since = f[2] == "0" and 0 or time(f[2])
  if not since then
    return nil, "number"
  end
  if since ~= 0 and (since < LIMITS.tMin or since > now + LIMITS.futureTolerance) then
    return nil, "number"
  end
  return f[1], since
end

-- ENTRIES body: 1..5 entries "inn,t,phrase,seal" joined by ";" (rules 10-11). All of
-- the structure is checked before any number, so rule 10 always wins over rule 11.
local function parseEntries(body)
  local list = pieces(body, ";", 1, MAX_ENTRIES)
  if not list then
    return nil, "schema"
  end
  local raw = {}
  for i = 1, #list do
    local f = pieces(list[i], ",", 4, 4)
    local ids = f and pieces(f[3], ".", 1, LIMITS.phraseIdsMax)
    if not ids then
      return nil, "schema"
    end
    raw[i] = { inn = f[1], t = f[2], ids = ids, seal = f[4] }
  end
  local entries = {}
  for i = 1, #raw do
    local r = raw[i]
    local inn, t, seal = number(r.inn, 7, false), time(r.t), number(r.seal, 3, true)
    if not inn or not t or not seal then
      return nil, "number"
    end
    local phrase = {}
    for j = 1, #r.ids do
      phrase[j] = number(r.ids[j], 4, false)
      if not phrase[j] then
        return nil, "number"
      end
    end
    entries[i] = { inn = inn, t = t, phrase = phrase, seal = seal ~= 0 and seal or nil }
  end
  return entries
end

-- Rule 16: every ID known; the optional phraseOk hook can only reject more. The hook
-- gets a copy of the IDs, and anything but a plain `true` (or an error) is a reject.
local function knownIDs(e, inns, phrases, seals, phraseOk)
  if rawget(inns, e.inn) == nil then
    return false
  end
  local ids = {}
  for i = 1, #e.phrase do
    if rawget(phrases, e.phrase[i]) == nil then
      return false
    end
    ids[i] = e.phrase[i]
  end
  if e.seal ~= nil and rawget(seals, e.seal) == nil then
    return false
  end
  if phraseOk ~= nil then
    local ok, res = pcall(phraseOk, ids)
    return ok and res == true
  end
  return true
end

-- The body of receive, rules 2-19 in order (rule 1 is the pcall around it). Context
-- and sender fields are read with rawget, so no metamethod of theirs ever runs.
local function receive(msg, channel, sender, ctx)
  -- 2. Context sane.
  if type(ctx) ~= "table" then
    return nil, "ctx"
  end
  local now, selfGUID, ledger = rawget(ctx, "now"), rawget(ctx, "selfGUID"), rawget(ctx, "ledger")
  local limiter, memo = rawget(ctx, "limiter"), rawget(ctx, "wantMemo")
  local inns, phrases, seals = rawget(ctx, "inns"), rawget(ctx, "phrases"), rawget(ctx, "seals")
  local phraseOk = rawget(ctx, "phraseOk")
  if not isInt(now, 0, LIMITS.tMax) or not validGUID(selfGUID)
    or type(ledger) ~= "table" or type(ledger.ownerGUID) ~= "function"
    or ledger:ownerGUID() ~= selfGUID
    or type(limiter) ~= "table" or type(limiter.admit) ~= "function"
    or type(limiter.admitEntries) ~= "function"
    or type(memo) ~= "table" or type(rawget(memo, "seen")) ~= "table"
    or type(inns) ~= "table" or type(phrases) ~= "table" or type(seals) ~= "table"
    or (phraseOk ~= nil and type(phraseOk) ~= "function") then
    return nil, "ctx"
  end
  if ledger.readOnly ~= false then
    return nil, "readonly"
  end

  -- 3. Channel.
  if type(channel) ~= "string" or not CHANNELS[channel] then
    return nil, "channel"
  end

  -- 4. Sender resolved by the glue; 5. not our own echo.
  if type(sender) ~= "table" then
    return nil, "sender"
  end
  local guid, name = rawget(sender, "guid"), rawget(sender, "name")
  if not validGUID(guid) or not validName(name) then
    return nil, "sender"
  end
  if guid == selfGUID then
    return nil, "self"
  end

  -- 6. Size before anything reads the message; 7. then the rate, so junk counts too.
  if type(msg) ~= "string" or #msg < 1 or #msg > MAX_BYTES then
    return nil, "size"
  end
  if not limiter:admit(guid, now) then
    return nil, "rate"
  end

  -- 8. Charset, explicit byte ranges only. Rejects multi-part markers (bytes 1-4),
  -- pipes, spaces, NUL and UTF-8.
  if find(msg, "[^0-9A-Za-z:;,.%-]") then
    return nil, "charset"
  end

  -- 9. Header.
  local kind, version = match(msg, "^([A-Z])(%d+):")
  if kind ~= "H" and kind ~= "W" and kind ~= "E" then
    return nil, "header"
  end
  if version ~= "1" then
    return nil, "version"
  end
  local body = sub(msg, 4)

  -- 10-12.
  if kind == "H" then
    return parseHello(body)
  end

  -- 10, 11, 13.
  if kind == "W" then
    local target, since = parseWant(body, now)
    if not target then
      return nil, since
    end
    if target == selfGUID then
      return { kind = "want", since = since }
    end
    -- A reply is coming on this channel; remember it so we don't ask too. The target
    -- never goes near the ledger.
    local seen = rawget(memo, "seen")
    local key = channel .. ":" .. target
    local s = seen[key]
    local keep = since
    if s ~= nil and not seenExpired(s, now) and s.since < keep then
      keep = s.since
    end
    cappedSet(seen, key, { at = now, since = keep }, seenExpired, now)
    return { kind = "want_seen", target = target, since = since }
  end

  -- 10-11.
  local entries, reason = parseEntries(body)
  if not entries then
    return nil, reason
  end
  -- 14. Every parsed entry counts, before the per-entry skips.
  if not limiter:admitEntries(guid, #entries, now) then
    return nil, "rate"
  end
  -- 15-16 for every entry first, then 17-19 through the ledger.
  local result = { kind = "entries", added = 0, dup = 0, dropped = 0, rejected = 0 }
  local accepted = {}
  for i = 1, #entries do
    local e = entries[i]
    if e.t < LIMITS.tMin or e.t > now + LIMITS.futureTolerance
      or not knownIDs(e, inns, phrases, seals, phraseOk) then
      result.rejected = result.rejected + 1
    else
      accepted[#accepted + 1] = e
    end
  end
  for i = 1, #accepted do
    -- 17. Signer and name come only from the resolved sender.
    local r = ledger:addForeign(guid, name, accepted[i], now)
    if r == "added" or r == "dup" or r == "dropped" then
      result[r] = result[r] + 1
    else
      result.rejected = result.rejected + 1 -- too_soon, or invalid/self/readonly
    end
  end
  return result
end

-- receive(msg, channel, sender, ctx): a result table or nil, reason (spec 5.1). Never
-- throws: anything that errors inside is a quiet "error" drop.
function SyncProtocol.receive(msg, channel, sender, ctx)
  local ok, result, reason = pcall(receive, msg, channel, sender, ctx)
  if not ok then
    return nil, "error"
  end
  return result, reason
end
