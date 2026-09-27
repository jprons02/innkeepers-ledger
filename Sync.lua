-- Sync (glue): addon-message transport, sender resolution, group and guild triggers.
local _, ns = ...

local Sync = {}
ns.Sync = Sync

-- Core calls this once the ledger is open (docs/specs/sync-glue.md 3.2). It does nothing
-- yet; the receive and send paths land with the Sync tickets under #41.
function Sync.Start()
end
