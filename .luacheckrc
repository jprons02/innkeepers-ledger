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
  "GameFontHighlightSmall",
  "GameFontNormal",
  "GameFontNormalLarge",
  "GameFontNormalSmall",
  "GossipFrame",
  "InCombatLockdown",
  "IsInGroup",
  "IsInGuild",
  "IsInRaid",
  "IsResting",
  "LE_PARTY_CATEGORY_HOME",
  "LibStub",
  "QuestTitleFont",
  "UIParent",
  "UISpecialFrames",
  "UNKNOWNOBJECT",
  "UnitFactionGroup",
  "UnitFullName",
  "UnitGUID",
  "UnitName",
  "date",
  "issecretvalue",
  "time",
}

-- Keep in sync with GLUE in spec/helpers/load.lua (a spec checks it against the TOC).
for _, glue in ipairs({ "Core.lua", "Sign.lua", "Sync.lua", "UI/Book.lua" }) do
  files[glue] = { std = "lua51", read_globals = wow }
end

files["spec/"] = { std = "lua51+busted" }

-- The dev harness (#139): a separate AddOn that's never packaged (scripts/ is ignored),
-- plus the local scripts that read its results. It sets its own globals.
local devWow = {
  "C_Timer", "C_UI", "CreateFrame", "DEFAULT_CHAT_FRAME", "GetBuildInfo", "GetCVar",
  "GetPhysicalScreenSize", "GetTime", "InCombatLockdown", "IsResting", "ReloadUI",
  "Screenshot", "SetCVar", "UIParent", "UnitIsAFK", "date", "geterrorhandler",
  "seterrorhandler", "time",
}
files["scripts/devclient/ILDev/"] = {
  std = "lua51", read_globals = devWow,
  globals = { "ILDevDB", "ILDevRequest", "SLASH_ILDEV1", "SlashCmdList" },
}
files["scripts/devclient/read.lua"] = { std = "lua51" }
files["scripts/devclient/tours/"] = { std = "lua51" }
