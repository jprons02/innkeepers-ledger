-- Cosmetics earned by play: milestone seals, quills and inks, each with a stable numeric
-- ID and the rule that unlocks it. Plain data, no WoW API. Shape, ID ranges and rules:
-- docs/specs/collection-cosmetics.md, sections 3.5 and 9.
--
-- DRAFT: the set, the names and the thresholds are the maintainer's decision (the spec's
-- section 9 and its open questions). Before the first public release they can change
-- freely. From then on an ID is never reused and never changes meaning, and a threshold
-- never rises.
--
-- IDs: milestone seals 1..99, quills 1000..1099, inks 1100..1199. Zone seals (101..999)
-- are not here: each zone in Data/Inns.lua carries its own. Rules:
--   { kind = "inns", n = <1..9999> }   n distinct inns open to you signed
--   { kind = "zones", n = <1..999> }   n zones done (every inn open to you signed)
--   { kind = "continent" }             any one continent done
--   { kind = "all" }                   every inn open to you signed
local _, ns = ...

ns.Data = ns.Data or {}

ns.Data.Cosmetics = {
  -- Seals (the only cosmetic other travelers see, on your signatures).
  [1] = { kind = "seal", name = "Wayfarer's seal", rule = { kind = "inns", n = 5 } },
  [2] = { kind = "seal", name = "Innkeeper's seal", rule = { kind = "all" } },

  -- Quills.
  [1001] = { kind = "quill", name = "Traveler's quill", rule = { kind = "inns", n = 10 } },
  [1002] = { kind = "quill", name = "Owl-feather quill", rule = { kind = "inns", n = 20 } },
  [1003] = { kind = "quill", name = "Cartographer's quill", rule = { kind = "continent" } },

  -- Inks.
  [1101] = { kind = "ink", name = "Sepia ink", rule = { kind = "inns", n = 1 } },
  [1102] = { kind = "ink", name = "Forest-green ink", rule = { kind = "zones", n = 3 } },
  [1103] = { kind = "ink", name = "Midnight-blue ink", rule = { kind = "zones", n = 10 } },
}
