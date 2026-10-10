-- The book: every tab, each side's pages (up to 3), then closed. A chunk that
-- deploy.sh wraps into Request.lua; steps are listed in ILDev.lua.
local B = "InnkeepersLedgerBook"
-- The page button's "›" (BookView.TEXT.next); #1 is the left page's, #2 the right page's.
local NEXT = "\226\128\186"
local LEFT, RIGHT = 1, 2

return {
  name = "book",
  steps = {
    { "slash", "/ledger", "" },
    { "wait", 0.5 },
    { "pages", B, NEXT, "inns-left-", B, 3, LEFT },
    { "pages", B, NEXT, "inns-right-", B, 3, RIGHT },
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
