# Prior art

> **Summary:** existing guestbook AddOns (retail housing), what we took from them, why this AddOn isn't a copy, and the Forever AddOn landscape near launch.
> **Read when:** positioning or describing the AddOn, looking for precedent on the sync pattern, or weighing a new feature against what already exists.

Guestbooks researched 2026-09-21; the Forever landscape on 2026-09-27.

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

## The Forever landscape (researched 2026-09-27)

Ten days into the beta, Forever AddOns arrive daily, mostly small ones with a few
hundred downloads each. Being first matters less than being polished. Download counts
are CurseForge's on 2026-09-27.

- **Inns and guestbooks:** searching "innkeeper" and "guestbook" under CurseForge's
  Forever filter finds nothing relevant. No AddOn in any flavor collects inns.
- **Exploration:** map-pin and waypoint tools (HandyNotes, ALL THE THINGS) and flat
  achievement lists ([Hardcore Achievements](https://www.curseforge.com/wow/addons/hardcore-achievements),
  about 155k downloads, supports Forever). Nothing collectible like passport stamps or
  zone seals.
- **Journals:** [Forever Journal](https://www.curseforge.com/wow/addons/forever-journal)
  (parchment-book journal, released 2026-09-24) and
  [Companion Chronicle](https://www.curseforge.com/wow/addons/companion-chronicle) (a
  manual journal about players you meet). Older journal and timeline AddOns in other
  flavors never took off.
- **Remembering players:** Blizzard's **Recent Allies** ships in Forever and colors the
  names of players you grouped with.
  [iWillRemember](https://www.curseforge.com/wow/addons/iwillremember) already supports
  Forever (auto-logs group members, notes in tooltips).
  [I Remember You](https://www.curseforge.com/wow/addons/i-remember-you) has about 369k
  downloads in other flavors.
- **Hardcore deaths:** [Deathlog](https://www.curseforge.com/wow/addons/deathlog)
  dominates Classic Hardcore and shares deaths with strangers over a hidden channel.
  [HARDCORE FOREVER](https://www.curseforge.com/wow/addons/hardcore-forever) is already
  out for Forever, which has no Hardcore ruleset at launch.
- **Camping:** 13 camping AddOns were published in the first 10 days of the beta,
  including two campfire storytellers.

What this means for us is recorded in [decisions.md](decisions.md) (2026-09-27, keep
the inn ledger).
