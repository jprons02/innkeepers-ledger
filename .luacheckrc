-- Lint config. Pure modules and data get only the plain-Lua names in PURE (the same set
-- spec/helpers/load.lua allows), so any WoW global, _G, os or io in them is an error,
-- even inside a function. Glue gets Lua 5.1 plus the WoW API names it uses.
-- Nothing may set a new global.
max_line_length = 100

exclude_files = {
  "Libs/",
  ".luarocks/",
  "lua_modules/",
  ".release/",
}

stds.pure = {
  read_globals = {
    "assert", "error", "getmetatable", "ipairs", "next", "pairs", "pcall", "rawequal",
    "rawget", "rawset", "select", "setmetatable", "tonumber", "tostring", "type",
    "unpack", "xpcall", "math", "string", "table",
  },
}
std = "pure"

-- WoW API used by glue. Add names here as glue starts calling them.
local wow = {
  "C_AddOns",
  "C_ChatInfo",
  "C_DateAndTime",
  "C_GuildInfo",
  "C_Timer",
  "ChatThrottleLib",
  "CreateFrame",
  "Enum",
  "GetAddOnMetadata",
  "GetCurrentRegion",
  "GetGuildRosterInfo",
  "GetNormalizedRealmName",
  "GetNumGroupMembers",
  "GetNumGuildMembers",
  "GetServerTime",
  "InCombatLockdown",
  "IsInGroup",
  "IsInGuild",
  "IsInRaid",
  "IsResting",
  "LE_PARTY_CATEGORY_HOME",
  "LibStub",
  "UNKNOWNOBJECT",
  "UnitFactionGroup",
  "UnitFullName",
  "UnitGUID",
  "UnitName",
  "issecretvalue",
}

-- Keep in sync with GLUE in spec/helpers/load.lua (a spec checks it against the TOC).
for _, glue in ipairs({ "Core.lua", "Sign.lua", "Sync.lua", "UI/Book.lua" }) do
  files[glue] = { std = "lua51", read_globals = wow }
end

files["spec/"] = { std = "lua51+busted" }
