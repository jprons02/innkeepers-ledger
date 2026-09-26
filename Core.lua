-- Core (glue): AceAddon setup, AceDB SavedVariables, the /ledger command.
local ADDON_NAME, ns = ...

local Core = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "AceConsole-3.0", "AceEvent-3.0")
ns.Core = Core

local GetAddOnMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata

-- The packager replaces @project-version@; an unpackaged checkout reports "dev".
local function version()
  local v = GetAddOnMetadata(ADDON_NAME, "Version")
  if not v or v:find("@", 1, true) then
    return "dev"
  end
  return v
end

function Core:OnInitialize()
  self.db = LibStub("AceDB-3.0"):New("InnkeepersLedgerDB", {}, true)
  self:RegisterChatCommand("ledger", "SlashCommand")
end

function Core:SlashCommand()
  self:Print("version " .. version())
end
