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
  ✅ In the beta (2026-09-30): the player GUID is the retail form
  `Player-<serverID>-<8 hex>`; `GetRealmName()` is the ruleset realm (`Classic Beta PvP`,
  normalized `ClassicBetaPvP`). How names look is under **Names** below.
- ✅ **No player housing.** No houses, plots or decor. Hearthstones bind at innkeepers.
- ✅ **Camping.** Players build shared open-world campfires; others add
  profession-crafted objects (3 / 5 / 10 slots by campfire tier). Sitting by the fire for
  about a minute grants rested status, buffs, vendors and repairs. ❓ Whether you can
  bind a hearthstone at a camp (reported as not confirmed). ❓ How camps show up to the
  API (object GUIDs, events). Relevant for post-v1.
- ✅ **Hardcore ruleset announced, but not at launch** ("soon" after, no date).
  ❓ What the client exposes about other characters' deaths.
- ✅ **Names are two-part** (first name and surname; beta, 2026-09-30). The surname
  takes the realm's place in the unit APIs: `UnitName("player")` and
  `UnitFullName("player")` both return `"First", "Surname"`, never a realm. The
  `CHAT_MSG_ADDON` sender (and `target`) is `"First Surname"`: one space, **no realm
  suffix, no dash**. A whisper addressed `"First-Surname"` still arrived. ⚠️ Region-wide
  uniqueness is still only reported. ❓ What `UnitFullName("partyN")` and
  `GetGuildRosterInfo` return for *other* characters (needs a second character or a
  guild). What this breaks in our code: [decisions.md](decisions.md), 2026-09-30.
- ✅ **A new world at the start:** the first zone seen, *Zephras Isle* (map 2521, type
  Zone), sits **directly under the Azeroth world map** (947, type World), with no
  Continent-type map between them. New races (e.g. *Skyborne*) map onto Alliance and
  Horde through `UnitFactionGroup`.
- ✅ **Recent Allies** (Blizzard's built-in list of players you grouped with) ships in
  Forever and colors their names.

## AddOns and the API

In-client results below come from a throwaway probe AddOn (branch `spike/12-probe`, never
merged) run in the Forever beta, build **1.60.1.70124** (2026-09-29), on 2026-09-30.

- ✅ **The modern (retail/Midnight) API, not the Classic one.** The install folder and
  product are `_classic_beta_` / `wow_classic_beta`, but `WOW_PROJECT_ID` is `1`
  (`WOW_PROJECT_MAINLINE`), with 5 988 global functions and 271 `C_` namespaces,
  Midnight-era ones included (`C_Secrets`, `C_RestrictedActions`, `C_EncodingUtil`,
  `C_DamageMeter`, `C_SwingTimer`, `C_Housing`). `SendAddonMessage` exists only as
  `C_ChatInfo.SendAddonMessage` (returns `Enum.SendAddonMessageResult`, `0` = Success);
  `GetAddOnMetadata` only as `C_AddOns.GetAddOnMetadata`; `GuildRoster` only as
  `C_GuildInfo.GuildRoster`. The Midnight secret-value functions are there
  (`issecretvalue`, `canaccessvalue`, `issecrettable`, `hasanysecretvalues`,
  `scrubsecretvalues`, `secretwrap`, `canaccesssecrets`, `dropsecretaccess`).
- ✅ **TOC interface number: `16001`** (`select(4, GetBuildInfo())`). The TOC carries it.
- ✅ **AddOn and embedded libraries load** with no Lua error; the ledger opens (GUID
  readable at `PLAYER_LOGIN`), and `RegisterAddonMessagePrefix` returns `0` (Success).
- ✅ **Hidden values outside combat: none seen.** `UnitGUID("player")`,
  `UnitGUID("npc")`, `UnitName("npc")`, `UnitFactionGroup("player")` and the
  `CHAT_MSG_ADDON` sender all read normally (`issecretvalue` false, `canaccessvalue`
  true). ❓ Inside combat, instances and encounters: not tested yet.
  `C_ChatInfo.AreOutgoingAddonChatMessagesRestricted` and
  `C_ChatInfo.InChatMessagingLockdown` (false out of combat) exist to ask.
- ✅ **NPC GUIDs are the retail form** `Creature-0-<server>-<instance>-<zoneUID>-<npcID>-<spawn>`;
  field 6 is the NPC ID (e.g. `251361`). Forever NPC IDs seen so far are 251 000–264 000.
- ✅ **Gossip:** `GOSSIP_SHOW` fires; `C_GossipInfo.GetOptions()` / `GetText()` work;
  `GossipFrame` is the retail frame (`GossipFrame.GreetingPanel.ScrollBox`, 338×496).
  A `UIPanelButtonTemplate` button parented to `GossipFrame` and anchored under it shows
  and takes clicks. ❓ Not yet seen at an innkeeper (none met so far).
- ✅ **Sitting detection: no query API.** Only actions exist (`ToggleSit`,
  `SitStandOrDescendStart`); nothing reports the stand state.
- ✅ **Addon messages on custom channels are allowed** (retail behavior): `"CHANNEL"` to a
  joined temporary channel returned Success and arrived (`localID` and channel name
  filled in).
- ✅ **Size:** a message over 255 bytes is **silently truncated to 255** and still returns
  Success (256 and 300 arrived as 255). 255 arrives whole. `SyncProtocol` already caps
  at 255.
- ✅ **Order is not guaranteed:** 30 whispers-to-self sent in one frame all arrived, out
  of order. ❓ Group and guild channels not tested.
- ✅ **Weekly reset:** `C_DateAndTime.GetSecondsUntilWeeklyReset()` works at login; in
  the beta (`GetCurrentRegion()` = 90, name empty) it lands on **Tuesday 16:00 UTC**.
- ✅ **Export edit box:** a 256 000-byte string fits (default `GetMaxLetters()` is 0, no
  cap), `SetText` takes 2.3 ms the first time, with no measurable memory held.
- ❓ **Addon messages in instances and encounters,** and which chat type instance groups
  use. Needs a dungeon run.
- ❓ **Party, raid and guild round-trips** between two characters. Needs a second
  character (or a guild).

## Verification checklist (needs a Forever client: beta until 2026-10-21, or launch 2026-11-04)

Ticked items were checked in the beta on 2026-09-30 (build 1.60.1.70124); the results are
in the sections above. **Partly** means the rest of the item is still open.

- [x] TOC interface number (`16001`); AddOn loads ✅
- [ ] `GOSSIP_SHOW` fires for innkeepers; `UnitGUID("npc")` yields a creature GUID with
      NPC ID. **Partly** ✅: both hold for every NPC tried, but no innkeeper yet
- [x] Gossip option injection approach works ✅ (a button parented to `GossipFrame`,
      anchored under it). Re-check the look at an innkeeper
- [ ] `IsResting()` true inside inns (it's `false` outside, and readable)
- [x] Embedded libraries (see [libraries.md](libraries.md)) load without errors ✅
- [ ] Addon message PARTY / RAID / GUILD round-trip between two characters
- [ ] Addon messages inside an instance / during an encounter, and which chat type
      instance groups use (`PARTY`/`RAID` or `INSTANCE_CHAT`)
- [ ] Addon message size limit and send rate limits (what ChatThrottleLib assumes).
      **Partly** ✅: 255 bytes, longer messages truncated silently; 30 whispers in one
      frame all arrived. Group and guild throttles untested
- [x] Hidden values outside combat: `UnitGUID("npc")`, NPC names and the
      `CHAT_MSG_ADDON` sender all arrive as normal values ✅ (at an innkeeper: re-check
      with the first one)
- [x] Addon messages to a custom channel (`"CHANNEL"`): **allowed** ✅
- [x] Player GUID and name format on the mega-realm ✅: retail GUID, **two-part names**
      whose surname fills the realm slot of `UnitName`/`UnitFullName`
- [x] Weekly reset ✅: `C_DateAndTime.GetSecondsUntilWeeklyReset()` works at login; the
      beta resets Tuesday 16:00 UTC (region 90). Live regions: check after launch
- [ ] Addon-message sender name resolves to a GUID: through our own unit scan for group
      members (see the #54 item); guild roster exposes member GUIDs. **Known broken**
      for two-part names; see [decisions.md](decisions.md), 2026-09-30
- [ ] Sync glue ([specs/sync-glue.md §8](specs/sync-glue.md#8-unverified-client-facts-this-spec-relies-on)).
      **Partly** ✅: the `CHAT_MSG_ADDON` sender is `"First Surname"` (a space, no realm
      suffix); `GetNormalizedRealmName()` is `ClassicBetaPvP`; `UnitGUID("player")` and
      the weekly-reset API are readable at `PLAYER_LOGIN`; `RegisterAddonMessagePrefix`
      returns `0`; `LE_PARTY_CATEGORY_HOME` = 1 and `_INSTANCE` = 2 exist. Still open:
      `GetGuildRosterInfo`'s 17th return, `GUILD_ROSTER_UPDATE` /
      `C_GuildInfo.GuildRoster()`, `InCombatLockdown` and `PLAYER_REGEN_*`,
      ChatThrottleLib's `didSend`, home-versus-instance group separation
- [ ] Group sender names (#54). **Partly** ✅: the sender is a bare `"First Surname"`
      with no `-Realm`; `UnitFullName("player")` returns the surname, not our realm;
      `UNKNOWNOBJECT` is `"Unknown"` (AceDB's profile key read it at load). Still open:
      what `UnitFullName("partyN")` returns and whether it can match the sender; unit-token
      names; `GROUP_ROSTER_UPDATE` after a name loads
- [ ] Collect every inn for the `Data/Inns` table (#12), per innkeeper: the NPC ID; the
      inn's English name; the zone's map ID and English name; the continent's map ID
      and English name; the innkeeper's faction (`"Alliance"`, `"Horde"`, or neutral if
      both can use it); whether another innkeeper serves the same inn (an alias). Zone
      seals are numbered 101, 102, … in the order zones are added
      ([specs/collection-cosmetics.md §8](specs/collection-cosmetics.md#8-contract-for-later-slices)).
      The probe logs every NPC talked to, so this fills in during normal play
- [ ] Map IDs readable at each inn (`C_Map.GetBestMapForUnit("player")`, then the
      `C_Map.GetMapInfo(id).parentMapID` chain up to the first *Zone*- and
      *Continent*-type maps); a capital city is its own zone. **Partly** ✅: the chain
      reads, but Zephras Isle has **no Continent ancestor** (Zone → World)
- [x] The player's faction token ✅: `UnitFactionGroup("player")` returns `"Alliance"`
      (readable, English); `UnitFactionGroup("npc")` gives an NPC's faction (`"Horde"`,
      `"Alliance"`, or nothing for neutral ones), `UnitReaction` its standing
- [ ] Export ([specs/export.md §3.10](specs/export.md#310-size-budget)). **Partly** ✅: an
      edit box holds a 256 000-byte string (`SetText` 2.3 ms). Still open: copying it
      out; build time and memory of an opted-in export at the foreign cap
- [x] Sitting detection ✅: none (no query API)

## Sources

- [Warcraft Wiki — World of Warcraft: Forever](https://warcraft.wiki.gg/wiki/World_of_Warcraft:_Forever)
- [Windows Central — Forever is Blizzard's take on Classic+](https://www.windowscentral.com/gaming/blizzard/world-of-warcraft-forever-is-blizzards-take-on-classic-revamping-vanilla-azeroth)
- [Blizzard Watch — Forever will be realmless](https://blizzardwatch.com/2026/09/13/world-warcraft-forever-will-realmless/)
- [Blizzard Watch — Forever's campfire system](https://blizzardwatch.com/2026/09/15/need-know-wow-forevers-campfire-system-works/)
- [Vice — Forever's camping system explained](https://www.vice.com/en/article/world-of-warcraft-forevers-camping-system-explained/)
- [Icy Veins — Addons in WoW Forever](https://www.icy-veins.com/wow-forever/news/addons-in-wow-forever-blizzard-devs-just-addressed-the-big-question/) (not fetched; headline only)
- [Blizzard forums — Housing in Forever?](https://us.forums.blizzard.com/en/wow/t/housing-in-forever/2347632)
