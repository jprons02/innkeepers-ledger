# Innkeeper's Ledger

> *"Sign the guestbook, traveler?"*

A free World of Warcraft AddOn for **WoW: Forever**. Talk to an innkeeper, sign the inn's
guestbook, and slowly fill a book of every inn you've rested at. Travelers you group with
leave their marks in your book too, so years later you might find that the stranger
from last night's dungeon slept in the same tiny Hillsbrad inn you did.

**Status:** pre-release, in design. Target: WoW: Forever launch (2026-11-04).

## What it does (v1 plan)

- **Sign at the innkeeper.** It's the same NPC you bind your hearthstone with. Signing
  is a small, deliberate moment, not an automatic log.
- **A collection of inns.** See how many of the world's inns you've signed, by continent
  and zone.
- **Travelers crossing paths.** When you group with (or share a guild with) other
  players who use the AddOn, your books quietly swap entries, but only each player's own
  signatures.
- **A book, not a spreadsheet.** Entries are rendered on parchment, in character,
  with dates.
- **Earned cosmetics.** Quills and wax seals unlock as your collection grows.
  Nothing is paid, and nothing is gated.
- **Export.** Copy a documented export string of your ledger for use anywhere
  (see [docs/export-format.md](docs/export-format.md)).

Entries use a phrase builder rather than free text, so the ledger stays friendly
without needing a moderator.

## Principles

- Free, forever. No paid features, no ads, no links to outside products. This follows
  [Blizzard's AddOn policy](docs/addon-policy.md).
- No combat data. This is a social AddOn. The only combat-related thing it checks is
  *whether* you're in combat, so it can hold ledger sharing until the fight ends. It
  never reads what happens in a fight: no damage, no targets, no logs.
- Your data stays in your game's SavedVariables. The AddOn has no network access; sync
  happens only in-game, between players who are online together.
- What sync shares: your own newest signatures (up to 40), each with its inn, the date
  and time you signed, your phrase and your seal. It goes to your group and your guild,
  so guildmates who use the AddOn can see where and when you signed. Nothing else about
  you is sent: no location, chat, gear or play time beyond those signatures.

## Docs

| | |
|---|---|
| [docs/status.md](docs/status.md) | Where the project stands and what's next |
| [docs/vision.md](docs/vision.md) | The idea and the design intent |
| [docs/decisions.md](docs/decisions.md) | Settled decisions and why |
| [docs/architecture.md](docs/architecture.md) | How it's built |
| [docs/platform-forever.md](docs/platform-forever.md) | What we know (and don't) about WoW: Forever |
| [docs/addon-policy.md](docs/addon-policy.md) | The Blizzard policy constraints this AddOn lives under |
| [docs/prior-art.md](docs/prior-art.md) | Existing guestbook AddOns and what we learned |
| [docs/export-format.md](docs/export-format.md) | The export string spec |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Bug reports and ideas go in GitHub Issues.
Security problems go through private reporting instead: see [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE). World of Warcraft is a trademark of Blizzard Entertainment. This
project is not affiliated with or endorsed by Blizzard.
