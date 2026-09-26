-- Ledger (pure): the entry store: add, dedupe, query, prune, storage caps.
-- No WoW API here. Client values come in as arguments (docs/architecture.md -> Modules).
local _, ns = ...

local Ledger = {}
ns.Ledger = Ledger
