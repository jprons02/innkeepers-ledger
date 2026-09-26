-- Lint config. Pure modules get plain Lua 5.1 only, so any WoW global in them is an
-- error; glue files get the WoW API names they use. Nothing may set a new global.
std = "lua51"
max_line_length = 100

exclude_files = {
  "Libs/",
  ".luarocks/",
  "lua_modules/",
  ".release/",
}

-- WoW API used by glue. Add names here as glue starts calling them.
local wow = {
  "C_AddOns",
  "C_ChatInfo",
  "C_Timer",
  "CreateFrame",
  "GetAddOnMetadata",
  "GetServerTime",
  "IsResting",
  "LibStub",
  "UnitGUID",
}

for _, glue in ipairs({ "Core.lua", "Sign.lua", "Sync.lua", "UI/Book.lua" }) do
  files[glue] = { read_globals = wow }
end

files["spec/"] = { std = "+busted" }
