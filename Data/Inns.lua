-- Places for WoW: Forever: inns, zones and continents, all keyed by integers so nothing is
-- ever matched by a (localized) name. Plain data, no WoW API. Shape, key schemes and record
-- rules: docs/specs/collection-cosmetics.md, sections 3.1 and 3.2.
-- Filled from the in-client walk of every inn (#12; the spec's section 8 lists what it
-- records). Partial until the walk is done.
--
--   Inns[<NPC ID>]     = { name = "...", zone = <zone key> }                     -- neutral
--   Inns[<NPC ID>]     = { name = "...", zone = <zone key>, faction = "Horde" }  -- one faction
--   Inns[<NPC ID>]     = { alias = <NPC ID of the inn's primary record> }        -- same inn
--   Zones[<map ID>]    = { name = "...", continent = <continent key>, seal = 101 }
--   Continents[<map ID>] = { name = "..." }
--
-- An inn's continent comes through its zone. Zone and continent keys are the client's own
-- map IDs. A zone's continent is the first Continent-type map above it, or, with none
-- there, the nearest World-type map (Zephras Isle 2521 sits right under Azeroth 947, so
-- Continents[947] = { name = "Azeroth" }). A map ID is never both a zone and a continent.
-- A zone's `seal` is its seal ID (101..999), allocated once in the order zones are added
-- and never reused. After the first release no record is ever removed or renumbered:
-- a retired inn keeps its record, a replacing innkeeper becomes an alias of it.
local _, ns = ...

ns.Data = ns.Data or {}
ns.Data.Inns = {
  [254089] = { name = "Calmbreeze Inn", zone = 2521 }, -- Coriella Calmbreeze, Shen'dar Village
}

ns.Data.Zones = {
  [2521] = { name = "Zephras Isle", continent = 947, seal = 101 },
}

ns.Data.Continents = {
  [947] = { name = "Azeroth" },
}
