-- A strict, test-only reader of exactly the JSON scripts/data-json.lua promises
-- (docs/specs/data-json.md, sections 3.3 and 6): objects, strings, integers and booleans;
-- escapes \", \\ and \u00xx for the bytes 0x00-0x1F and 0x7F; space and LF between
-- tokens. Anything else is refused: arrays, null, floats, exponents, leading zeros, -0,
-- other escapes, raw control bytes, malformed UTF-8, duplicate keys, trailing commas and
-- trailing bytes. Returns the value (objects as tables with string keys) or raises
-- "json_read: <reason> at byte <n>". The AddOn never reads JSON; this lives in spec/ only.
local M = {}

local byte, sub, find = string.byte, string.sub, string.find

local function err(reason, i)
  error("json_read: " .. reason .. " at byte " .. i, 0)
end

local function skip(s, i)
  while true do
    local b = byte(s, i)
    if b ~= 32 and b ~= 10 then
      return i
    end
    i = i + 1
  end
end

-- One UTF-8 sequence starting at i: returns the index after it, or nil. Decodes the code
-- point and checks its range, so it's independent of the encoder's byte-range table.
local function utf8At(s, i)
  local b = byte(s, i)
  local n, cp, min
  if b < 0x80 then
    return i + 1
  elseif b >= 0xC0 and b < 0xE0 then
    n, cp, min = 1, b - 0xC0, 0x80
  elseif b >= 0xE0 and b < 0xF0 then
    n, cp, min = 2, b - 0xE0, 0x800
  elseif b >= 0xF0 and b < 0xF8 then
    n, cp, min = 3, b - 0xF0, 0x10000
  else
    return nil
  end
  for k = 1, n do
    local c = byte(s, i + k)
    if c == nil or c < 0x80 or c > 0xBF then
      return nil
    end
    cp = cp * 64 + (c - 0x80)
  end
  if cp < min or cp > 0x10FFFF or (cp >= 0xD800 and cp <= 0xDFFF) then
    return nil
  end
  return i + n + 1
end

local HEX = "0123456789abcdef"

local function readString(s, i)
  -- s[i] is the opening quote.
  local out, j = {}, i + 1
  while true do
    local b = byte(s, j)
    if b == nil then
      err("unterminated string", i)
    elseif b == 34 then
      return table.concat(out), j + 1
    elseif b == 92 then
      local e = sub(s, j + 1, j + 1)
      if e == "\"" or e == "\\" then
        out[#out + 1] = e
        j = j + 2
      elseif e == "u" and sub(s, j + 2, j + 3) == "00" then
        local hi, lo = find(HEX, sub(s, j + 4, j + 4), 1, true),
          find(HEX, sub(s, j + 5, j + 5), 1, true)
        local code = hi and lo and (hi - 1) * 16 + (lo - 1)
        if not code or not (code <= 31 or code == 127) or #sub(s, j + 4, j + 5) ~= 2 then
          err("bad \\u escape", j)
        end
        out[#out + 1] = string.char(code)
        j = j + 6
      else
        err("bad escape", j)
      end
    elseif b < 32 or b == 127 then
      err("raw control byte in a string", j)
    else
      local after = utf8At(s, j)
      if not after then
        err("malformed UTF-8", j)
      end
      out[#out + 1] = sub(s, j, after - 1)
      j = after
    end
  end
end

local readValue

local function readObject(s, i)
  local obj = {}
  i = skip(s, i + 1)
  if byte(s, i) == 125 then
    return obj, i + 1
  end
  while true do
    if byte(s, i) ~= 34 then
      err("expected a string key", i)
    end
    local key
    key, i = readString(s, i)
    if obj[key] ~= nil then
      err("duplicate key", i)
    end
    i = skip(s, i)
    if byte(s, i) ~= 58 then
      err("expected ':'", i)
    end
    obj[key], i = readValue(s, skip(s, i + 1))
    i = skip(s, i)
    local b = byte(s, i)
    if b == 125 then
      return obj, i + 1
    elseif b ~= 44 then
      err("expected ',' or '}'", i)
    end
    i = skip(s, i + 1)
  end
end

function readValue(s, i)
  local b = byte(s, i)
  if b == 123 then
    return readObject(s, i)
  elseif b == 34 then
    return readString(s, i)
  elseif sub(s, i, i + 3) == "true" then
    return true, i + 4
  elseif sub(s, i, i + 4) == "false" then
    return false, i + 5
  end
  -- An integer: -?(0|[1-9][0-9]*), not -0, nothing after the digits but a delimiter.
  local num = s:match("^%-?%d+", i)
  if not num then
    err("unexpected token", i)
  end
  local digits = num:gsub("^%-", "")
  if (#digits > 1 and sub(digits, 1, 1) == "0") or num == "-0" then
    err("leading zero or -0", i)
  end
  local nxt = sub(s, i + #num, i + #num)
  if nxt == "." or nxt == "e" or nxt == "E" then
    err("not an integer", i)
  end
  local n = tonumber(num)
  if #digits > 16 or n > 2 ^ 53 - 1 or n < -(2 ^ 53 - 1) then
    err("integer out of range", i)
  end
  return n, i + #num
end

function M.read(s)
  assert(type(s) == "string", "json_read: needs a string")
  local v, i = readValue(s, skip(s, 1))
  i = skip(s, i)
  if i <= #s then
    err("trailing bytes", i)
  end
  return v
end

return M
