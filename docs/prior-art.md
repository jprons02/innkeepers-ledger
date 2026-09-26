# Prior art

> **Summary:** existing guestbook AddOns (retail housing), what we took from them, and why this AddOn isn't a copy.
> **Read when:** positioning or describing the AddOn, or looking for precedent on the sync pattern.

Researched 2026-09-21.

## No built-in guestbook exists

Nowhere in WoW (not inns, not player housing) is there a built-in guestbook, and players
have [asked for one](https://us.forums.blizzard.com/en/wow/t/housing-guest-book/2200945).
There's no official API that records who visited a place, so **every implementation
requires the visitor to actively sign.**

## Guestbooks exist for retail player housing

Player housing shipped with Midnight (retail), and the guestbook idea was built quickly:

- **[Guestbook](https://www.curseforge.com/wow/addons/guestbook)** — about 50k
  downloads. Sign or leave a custom note with an icon; homeowners can delete entries.
- **[HomeWatch](https://www.curseforge.com/wow/addons/homewatch)** — logs visits,
  greets visitors, and prompts you to sign if the home has Guestbook installed.
- **[MidnightGuestbook](https://www.curseforge.com/wow/addons/midnightguestbook)** —
  adds ratings.

**What we take from them:**
- **The demand is proven.** About 50k downloads for a guestbook.
- **The sync pattern is solved:** quiet peer-to-peer, where clients compare books when
  users meet and exchange only the missing entries, with guild scope by default and
  wider scopes as experimental opt-ins. We follow the same pattern (see
  [architecture.md](architecture.md)), adding the rule that peers accept only a sender's
  own signatures.
- **Free text works for them because an owner can moderate.** We have no owner, so we
  use canned phrases.

## Why this isn't a copy

- **Different place, different action.** In retail you **cannot bind a hearthstone to a
  house**, not even your own. Hearthstones bind only at innkeepers; housing uses a
  separate "Teleport Home." Inns remain their own thing.
- **Different social loop.** Housing guestbooks are host-and-guest. Inns have no host,
  so ours is travelers crossing paths (see [vision.md](vision.md)).
- **Different game.** WoW: Forever has no player housing at all, so none of these AddOns
  apply there.

**Nobody has built a guestbook for inns.**
