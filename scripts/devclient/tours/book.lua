-- The book: every tab, each side's pages (up to 3), an inn's page, then closed. A chunk
-- that deploy.sh wraps into Request.lua; steps are listed in ILDev.lua.
local B = "InnkeepersLedgerBook"
-- The page button's ">" (BookView.TEXT.next); #1 is the left page's, #2 the right page's.
local NEXT = ">"
local LEFT, RIGHT = 1, 2

return {
  name = "book",
  steps = {
    { "hide", B }, -- /ledger toggles: start from a closed book
    { "slash", "/ledger", "" },
    { "wait", 0.5 },
    { "pages", B, NEXT, "inns-left-", B, 3, LEFT },
    { "pages", B, NEXT, "inns-right-", B, 3, RIGHT },
    -- An inn's page, through its row in the list (Data/Inns' first inn; the step fails
    -- when the list doesn't show it, and the tour carries on).
    { "click", B, "Calmbreeze Inn" },
    { "dump", "inn", B },
    { "shot", "inn", B },
    { "click", B, "Collection" },
    { "pages", B, NEXT, "collection-left-", B, 3, LEFT },
    { "pages", B, NEXT, "collection-right-", B, 3, RIGHT },
    { "click", B, "Cosmetics" },
    { "pages", B, NEXT, "cosmetics-left-", B, 3, LEFT },
    { "pages", B, NEXT, "cosmetics-right-", B, 3, RIGHT },
    { "click", B, "Share" },
    { "dump", "share", B },
    { "shot", "share", B },
    { "click", B, "Inns" },
    { "hide", B },
  },
}
