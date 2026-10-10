-- The composer: needs the gossip window open at a known innkeeper, so it runs from
-- `/ildev run composer` after talking to one (a reload closes the gossip window, so an
-- automatic run skips it). Never clicks the commit button (ILDev refuses "Sign").
return {
  name = "composer",
  need = "GossipFrame",
  steps = {
    { "dump", "gossip", "GossipFrame" },
    { "shot", "gossip", "GossipFrame" },
    { "click", "GossipFrame", "Sign the guestbook" },
    { "wait", 0.5 },
    { "dump", "composer-line1", "GossipFrame" },
    { "shot", "composer-line1", "GossipFrame" },
    { "click", "GossipFrame", ">", 1 },
    { "shot", "composer-line1-next", "GossipFrame" },
    { "click", "GossipFrame", "Add a second line" },
    { "click", "GossipFrame", "Second line" },
    { "dump", "composer-line2", "GossipFrame" },
    { "shot", "composer-line2", "GossipFrame" },
    { "click", "GossipFrame", "Remove the second line" },
    { "click", "GossipFrame", "Cancel" },
    { "click", "GossipFrame", "Read the guestbook" },
    { "wait", 0.5 },
    { "dump", "read", "InnkeepersLedgerBook" },
    { "shot", "read", "InnkeepersLedgerBook" },
    { "hide", "InnkeepersLedgerBook" },
  },
}
