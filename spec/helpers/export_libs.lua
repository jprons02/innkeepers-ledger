-- The real vendored LibStub, AceSerializer-3.0 and LibDeflate, loaded into a private
-- environment (docs/specs/export.md 3.8), so no LibStub global leaks into the test run.
-- Reads of any name outside the standard library fail loudly, so a library that starts
-- touching a WoW global shows up here. Each call loads fresh copies.
local load = require("helpers.load")

local M = {}

-- The standard names the libraries may read. LibStub reads as nil until LibStub.lua sets
-- it (each library checks for it first); io, os and debug read as nil, which keeps
-- LibDeflate's command-line block (it checks for all three) from running.
local STANDARD = {
  "assert", "error", "getmetatable", "ipairs", "next", "pairs", "pcall", "rawequal",
  "rawget", "rawset", "select", "setmetatable", "tonumber", "tostring", "type",
  "unpack", "xpcall", "math", "string", "table",
}
local ABSENT = { io = true, os = true, debug = true, LibStub = true }

function M.env()
  local env = {}
  for _, name in ipairs(STANDARD) do
    env[name] = _G[name]
  end
  env._G = env
  return setmetatable(env, {
    __index = function(_, key)
      if ABSENT[key] then
        return nil
      end
      error("a vendored library read global '" .. tostring(key) .. "'", 2)
    end,
  })
end

-- { serializer, deflate, codec, LibStub }. `codec` is built exactly as Core builds it
-- (spec 3.7 step 2).
function M.new()
  local env = M.env()
  load.file("Libs/LibStub/LibStub.lua", {}, env)
  load.file("Libs/AceSerializer-3.0/AceSerializer-3.0.lua", {}, env)
  load.file("Libs/LibDeflate/LibDeflate.lua", {}, env)
  local LibStub = rawget(env, "LibStub")
  local serializer = LibStub("AceSerializer-3.0")
  local deflate = LibStub("LibDeflate")
  return {
    serializer = serializer,
    deflate = deflate,
    LibStub = LibStub,
    codec = {
      serialize = function(v) return serializer:Serialize(v) end,
      compress = function(s) return (deflate:CompressDeflate(s)) end,
    },
  }
end

return M
