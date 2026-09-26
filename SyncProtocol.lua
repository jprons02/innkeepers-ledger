-- SyncProtocol (pure): message codec, digest comparison and all validation of peer data.
-- No WoW API here. Client values come in as arguments (docs/architecture.md -> Modules).
local _, ns = ...

local SyncProtocol = {}
ns.SyncProtocol = SyncProtocol
