# Platform: WoW: Forever

> **Summary:** what's known about the WoW: Forever client, each fact marked confirmed / unverified / unknown, plus the in-client verification checklist.
> **Read when:** writing code that calls a WoW API, setting the TOC, planning in-client testing, or updating what's been verified.

What we know about the target client, **with confidence marked**. Researched
2026-09-25, before launch. Update this file as facts get verified in the client, and
don't write code that depends on a ⚠️ item until it's ✅.

Legend: ✅ confirmed by multiple credible sources or in-client · ⚠️ reported but
unverified · ❓ unknown

## The game

- ✅ **World of Warcraft: Forever** is Blizzard's "Classic+" flavor, announced at
  BlizzCon 2026, **launching 2026-11-04**. It's vanilla in look and feel, with a level-60
  cap, horizontal expansion (new raids, quests and zones, no new levels) and a separate
  story continuity. It runs on standard game time.
- ✅ **New and revamped zones:** Mount Hyjal, Riverglades, Shen'dralas, Zephras Isle,
  Dalaran in the Alterac Mountains, plus updates to original zones. **The inn list
  differs from Classic and retail.** `Data/Inns` must be built from Forever itself.
- ✅ **Realmless.** One mega-realm per ruleset per region (Normal / PvP / RP /
  Hardcore). Factions stay separate; you group only with the same faction and ruleset.
  ❓ How character names and GUIDs look on a mega-realm (whether names carry a realm
  suffix).
- ✅ **No player housing.** No houses, plots or decor. Hearthstones bind at innkeepers.
- ✅ **Camping.** Players build shared open-world campfires; others add
  profession-crafted objects (3 / 5 / 10 slots by campfire tier). Sitting by the fire for
  about a minute grants rested status, buffs, vendors and repairs. ❓ Whether you can
  bind a hearthstone at a camp (reported as not confirmed). ❓ How camps show up to the
  API (object GUIDs, events). Relevant for post-v1.
- ✅ **Hardcore ruleset announced, but not at launch** ("soon" after, no date).
  ❓ What the client exposes about other characters' deaths.
- ⚠️ **Names:** reported as two-part (a surname is mandatory) and unique across the
  region. Fan-site report of a developer Q&A; confirm in the client.
- ✅ **Recent Allies** (Blizzard's built-in list of players you grouped with) ships in
  Forever and colors their names.

## AddOns and the API

- ⚠️ **AddOns are supported, on the modern (retail-style) API with the Midnight-era
  combat restrictions**, rather than the old Classic API. Reported by Icy Veins as
  coming from Blizzard developers (that article couldn't be fetched to confirm the exact
  wording), and repeated by several lower-trust guide sites. If true, addon messages,
  SavedVariables, `IsResting()`, `UnitGUID("npc")` and gossip events should all behave
  as they do on retail.
- ⚠️ Forever reportedly ships built-in tools (damage meter, cooldown manager, swing
  timer). Irrelevant to us, but a sign that Blizzard expects non-combat AddOns to be
  where the AddOn scene is.
- ❓ **TOC interface number** for Forever. `InnkeepersLedger.toc` carries a marked
  placeholder (`120000`) until it's read in the client with
  `/dump select(4, GetBuildInfo())`.
- ❓ **Addon messages in instances.** Whether `SendAddonMessage` is restricted inside
  instances or during encounters (a Midnight-era question). Affects when party sync
  can run.
- ❓ **Gossip frame integration.** How to add a "Sign the ledger" option to (or next to)
  the innkeeper's gossip menu.
- ❓ **Sitting detection.** Whether any API reports that the player is sitting.
- ⚠️ **Hidden ("secret") values.** Fan sites report that Forever carries Midnight's
  secret values beyond combat: unit and creature names can arrive hidden, `CHAT_MSG_*`
  senders can arrive hidden under chat lockdown, and an addon message with a hidden
  argument is silently not sent. If true outside combat, it affects reading the
  innkeeper's NPC ID and resolving who sent a sync message. Unverified; top of the
  in-client list.
- ❓ **Addon messages on custom channels.** Retail allows `SendAddonMessage` to
  `"CHANNEL"`; Classic has blocked it since 1.13.3 (2019). Which one Forever follows
  decides whether an "inn common room" with strangers is possible (post-v1).

## Verification checklist (needs a Forever client: beta until 2026-10-21, or launch 2026-11-04)

- [ ] TOC interface number; AddOn loads
- [ ] `GOSSIP_SHOW` fires for innkeepers; `UnitGUID("npc")` yields a creature GUID with
      NPC ID
- [ ] Gossip option injection approach works
- [ ] `IsResting()` true inside inns
- [ ] Embedded libraries (see [libraries.md](libraries.md)) load without errors
- [ ] Addon message PARTY / RAID / GUILD round-trip between two characters
- [ ] Addon messages inside an instance / during an encounter, and which chat type
      instance groups use (`PARTY`/`RAID` or `INSTANCE_CHAT`)
- [ ] Addon message size limit (255 bytes on retail) and send rate limits (what
      ChatThrottleLib assumes)
- [ ] Hidden values outside combat: does `UnitGUID("npc")` at an innkeeper, and the
      sender of `CHAT_MSG_ADDON`, arrive as a normal value?
- [ ] Addon messages to a custom channel (`"CHANNEL"`): allowed or blocked?
- [ ] Player GUID and name format on the mega-realm (two-part names?)
- [ ] Weekly reset: `C_DateAndTime.GetSecondsUntilWeeklyReset()` works, and the reset
      day and time per region (for the fallback table)
- [ ] Addon-message sender name resolves to a GUID: `UnitGUID(sender)` for group
      members; guild roster exposes member GUIDs
- [ ] Collect innkeeper NPC IDs for every inn (the `Data/Inns` table)
- [ ] Sitting detection, if any

## Sources

- [Warcraft Wiki — World of Warcraft: Forever](https://warcraft.wiki.gg/wiki/World_of_Warcraft:_Forever)
- [Windows Central — Forever is Blizzard's take on Classic+](https://www.windowscentral.com/gaming/blizzard/world-of-warcraft-forever-is-blizzards-take-on-classic-revamping-vanilla-azeroth)
- [Blizzard Watch — Forever will be realmless](https://blizzardwatch.com/2026/09/13/world-warcraft-forever-will-realmless/)
- [Blizzard Watch — Forever's campfire system](https://blizzardwatch.com/2026/09/15/need-know-wow-forevers-campfire-system-works/)
- [Vice — Forever's camping system explained](https://www.vice.com/en/article/world-of-warcraft-forevers-camping-system-explained/)
- [Icy Veins — Addons in WoW Forever](https://www.icy-veins.com/wow-forever/news/addons-in-wow-forever-blizzard-devs-just-addressed-the-big-question/) (not fetched; headline only)
- [Blizzard forums — Housing in Forever?](https://us.forums.blizzard.com/en/wow/t/housing-in-forever/2347632)
