-- Export (pure): encodes the ledger per docs/export-format.md.
-- No WoW API here. Client values come in as arguments (docs/architecture.md -> Modules).
local _, ns = ...

local Export = {}
ns.Export = Export
