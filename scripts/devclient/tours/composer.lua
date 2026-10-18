-- The composer: needs the gossip window open at a known innkeeper, so it runs from
-- `/ildev run composer` after talking to one (a reload closes the gossip window, so an
-- automatic run skips it). Never clicks the commit button (ILDev refuses "Sign").
local G = "GossipFrame"

local steps = {
  { "dump", "gossip", G },
  { "shot", "gossip", G },
  { "click", G, "Sign the guestbook" },
  { "wait", 0.5 },
  { "dump", "composer-line1", G },
  { "shot", "composer-line1", G },
  { "click", G, ">", 1 },
  { "shot", "composer-line1-next", G },
  -- Adding the second line moves to it.
  { "click", G, "Add a second line" },
  { "dump", "composer-line2", G },
  { "shot", "composer-line2", G },
  -- Every conjunction label, for its width in the client (#148). Hearthside has more than
  -- its strip shows, so the strip pages: its ">" is the topmost one shown.
  { "click", G, ">", 1 },
  { "dump", "conj-hearthside-2", G },
}
-- The other voices' conjunctions fit on one page (Data/Phrases.lua).
for _, voice in ipairs({ "Bardic", "Grumbler", "Scholar", "Rowdy", "Mystic", "Sailor",
  "Noble" }) do
  steps[#steps + 1] = { "click", G, voice }
  steps[#steps + 1] = { "dump", "conj-" .. voice:lower(), G }
  if voice == "Rowdy" then -- the longest label
    steps[#steps + 1] = { "shot", "conj-rowdy", G }
  end
end
for _, s in ipairs({
  { "click", G, "Remove the second line" },
  { "click", G, "Cancel" },
  { "click", G, "Read the guestbook" },
  { "wait", 0.5 },
  { "dump", "read", "InnkeepersLedgerBook" },
  { "shot", "read", "InnkeepersLedgerBook" },
  { "hide", "InnkeepersLedgerBook" },
}) do
  steps[#steps + 1] = s
end

return { name = "composer", need = G, steps = steps }
