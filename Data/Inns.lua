-- Innkeeper NPC ID -> inn record (inn name, zone, continent), for WoW: Forever.
-- Filled from the in-client walk of every inn (#12). Plain data, no WoW API.
local _, ns = ...

ns.Data = ns.Data or {}
ns.Data.Inns = {}
