# AddOn policy constraints

Blizzard publishes a
[UI Add-On Development Policy](https://us.forums.blizzard.com/en/wow/t/ui-add-on-development-policy/24534).
Breaking it can get an AddOn disabled or pulled from distribution sites. These are the
rules that shape this project. Quotes are from the official post; re-check it before a
release in case it changes.

## The rules that bind us

- **Free of charge.** *"All add-ons must be distributed free of charge"* and may not
  *"otherwise require some form of monetary compensation."* That means no paid tiers,
  no paid unlocks, and no feature gated behind anything bought. **This is why every
  cosmetic is earned through play.**
- **No hidden code.** *"The programming code of an add-on must in no way be hidden or
  obfuscated."* We publish the source under MIT anyway. (Encoding the *export string*
  is fine; it's data, not code.)
- **No advertising (Rule 4).** *"Add-ons may not be used to advertise any goods or
  services."* **The AddOn never references, links to, or promotes any external product,
  site, or service.** That includes in-game text, tooltips, the export UI, and the
  distribution pages.
- **No offensive material (Rule 6).** An AddOn that spreads offensive content is the
  author's problem. **This is why entries use canned phrases instead of free text**:
  entries propagate between players and there's no moderator.
- **Donations:** not solicited in-game. (Allowed on distribution sites, but not
  planned.)
- **Blizzard can disable anything (Rule 8).** Blizzard reserves the right to break any
  AddOn functionality at will, and has done so for whole categories (see below).

## No network access

The Lua sandbox has **no HTTP and no sockets**. An AddOn can't reach a website or an
API. Design around it; don't plan for it to change. The legitimate bridges out of the
game:

1. **Export strings** — the AddOn shows a string that the user copies (the
   SimulationCraft pattern). This is our only outbound bridge.
2. Companion apps reading SavedVariables off disk between sessions (not planned).
3. **Addon messages** between players in-game (party, raid, guild). This is our sync.

What gets AddOns and accounts in trouble is interacting with the *running* game from
outside: input automation, memory reading, botting. We do none of it.

## Combat restrictions (Midnight, 2026-01-28)

The Midnight pre-patch made combat data a black box to AddOns ("Secret Values"). In
[Blizzard's words](https://news.blizzard.com/en-us/article/24246290/combat-philosophy-and-addon-disarmament-in-midnight),
AddOns "can change the size or shape of the box, and they can paint it a different
color, but what they can't do is look inside." Several major combat AddOns were
discontinued. **The scope is combat state only.** Social, cosmetic and collection
AddOns are unaffected, and WoW: Forever reportedly applies the same rules (see
[platform-forever.md](platform-forever.md)). **This AddOn reads no combat data.**
