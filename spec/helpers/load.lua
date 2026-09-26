-- Loads AddOn files the way the client does: each chunk gets (addonName, ns) as `...`.
-- Specs load modules into a fresh `ns` so they stay isolated from each other.
local M = {}

M.ADDON_NAME = "InnkeepersLedger"
M.TOC = "InnkeepersLedger.toc"

-- Every file of ours in the TOC, by kind (docs/architecture.md -> Modules). A spec
-- checks the TOC against these lists; GLUE must match the list in .luacheckrc.
M.PURE = {
  { path = "Phrase.lua", name = "Phrase" },
  { path = "Ledger.lua", name = "Ledger" },
  { path = "Collection.lua", name = "Collection" },
  { path = "Cosmetics.lua", name = "Cosmetics" },
  { path = "SyncProtocol.lua", name = "SyncProtocol" },
  { path = "Export.lua", name = "Export" },
}
M.DATA = {
  { path = "Data/Inns.lua", name = "Inns" },
  { path = "Data/Phrases.lua", name = "Phrases" },
}
M.GLUE = {
  { path = "Core.lua", name = "Core" },
  { path = "Sign.lua", name = "Sign" },
  { path = "Sync.lua", name = "Sync" },
  { path = "UI/Book.lua", name = "Book" },
}

-- The Lua 5.1 names a pure module may use. No io/os/debug, no code loading.
local PURE_NAMES = {
  "assert", "error", "getmetatable", "ipairs", "next", "pairs", "pcall", "rawequal",
  "rawget", "rawset", "select", "setmetatable", "tonumber", "tostring", "type",
  "unpack", "xpcall", "math", "string", "table",
}

-- A strict plain-Lua environment: reading or writing any other global is an error,
-- so a pure module that touches a WoW global fails to load.
function M.pure_env()
  local env = {}
  for _, name in ipairs(PURE_NAMES) do
    env[name] = _G[name]
  end
  env._G = env
  return setmetatable(env, {
    __index = function(_, key)
      error("pure module read global '" .. tostring(key) .. "'", 2)
    end,
    __newindex = function(_, key)
      error("pure module set global '" .. tostring(key) .. "'", 2)
    end,
  })
end

-- Runs one file with (addonName, ns). `env`, if given, replaces its globals.
function M.file(path, ns, env)
  ns = ns or {}
  local chunk = assert(loadfile(path))
  if env then
    setfenv(chunk, env)
  end
  chunk(M.ADDON_NAME, ns)
  return ns
end

local function dir_of(path)
  return path:match("^(.*)/[^/]*$") or "."
end

local function join(dir, file)
  file = file:gsub("\\", "/")
  if dir == "." then
    return file
  end
  return dir .. "/" .. file
end

local function read(path)
  local f = assert(io.open(path, "rb"))
  local text = f:read("*a")
  f:close()
  return text
end

-- Lua files an XML file loads, in order, following <Script> and <Include>.
local function xml_files(path, out)
  local dir = dir_of(path)
  for tag, file in read(path):gmatch("<(%a+)%s+file=\"([^\"]+)\"") do
    local full = join(dir, file)
    if tag == "Script" then
      out[#out + 1] = full
    elseif tag == "Include" then
      xml_files(full, out)
    end
  end
  return out
end

-- The file entries of a TOC, as written (slashes normalized), in order.
function M.toc_entries(toc)
  local entries = {}
  for line in read(toc or M.TOC):gmatch("[^\r\n]+") do
    line = line:match("^%s*(.-)%s*$")
    if line ~= "" and line:sub(1, 1) ~= "#" then
      entries[#entries + 1] = line:gsub("\\", "/")
    end
  end
  return entries
end

-- Every Lua file the client would run for the TOC, in load order.
function M.toc_files(toc)
  local files = {}
  for _, entry in ipairs(M.toc_entries(toc)) do
    if entry:match("%.xml$") then
      xml_files(entry, files)
    else
      files[#files + 1] = entry
    end
  end
  return files
end

-- Loads the whole AddOn (libraries included) into a fresh ns, in TOC order.
-- Glue and libraries need the WoW stub installed first.
function M.addon(ns)
  ns = ns or {}
  for _, path in ipairs(M.toc_files()) do
    M.file(path, ns)
  end
  return ns
end

return M
