# Vision

> **Summary:** what we're building, why inns, the crossing-paths answer to the no-owner problem, the feel it must have, and post-v1 directions.
> **Read when:** making product or UX choices, writing in-game wording, or judging whether a feature belongs.

## The one-liner

Walk into an inn, talk to the innkeeper, sign the guestbook. Over time you fill a book of
everywhere you've stayed, and the entries of travelers you've crossed paths with fill
in alongside yours.

## Why inns

A hearthstone isn't a reward item. It's the *go home* button. Everyone has one, and
where you set it is a personal choice you carry for weeks or months. Inns are where
that choice happens, where rested XP builds up, and where "Rest well" is said. They're
the most "home" thing in Azeroth, and **no AddOn does anything with them.** There is
no built-in guestbook anywhere in the game. (See [prior-art.md](prior-art.md).)

## The design problem, and the answer

Guestbooks for player housing work because there's an **owner**, a guaranteed reader
for what you wrote. An inn has no owner. Signing one alone is just a stamp in a
collection, not a message to anyone. Without a fix, an inn guestbook is a strictly worse
guestbook.

**The answer: travelers crossing paths.** Your ledger fills with signatures from
players you actually meet: people you group with, and your guild. Nobody is guaranteed
to read your entry; instead you get **serendipity**. You finish a dungeon with a stranger
and afterward find they signed the same out-of-the-way inn you did. That's how it would
work in the fiction: travelers learn who else passed through by crossing paths.

**The collection underneath:** X of Y inns signed, by continent and zone. It carries the
AddOn through stretches when the social part isn't happening.

## The feel

- **A small deliberate moment.** Signing happens through the innkeeper's gossip
  menu, the same interaction as binding a hearthstone. It should feel like a ritual,
  not a notification.
- **A book, not a list.** Parchment, handwriting-style type, in-character wording,
  dates. The ledger should be something you *open*, not something you scan.
- **Warm, never noisy.** Sync is quiet. No chat spam, no pop-ups when strangers' entries
  arrive. You discover them when you open the book.
- **Earned, never bought.** Quills, inks and wax seals unlock through the collection
  (e.g. ten inns signed → a new quill; every inn in a zone → that zone's seal).

## Why WoW: Forever specifically

Forever (Blizzard's "Classic+", launching 2026-11-04) is the target. It has no player
housing, so the existing housing guestbook AddOns have nothing to attach to, and inns
are the only "home" there is. Forever's realmless design (one shared world per ruleset)
means you keep meeting the same travelers, which makes crossing paths stronger. See
[platform-forever.md](platform-forever.md).

## Where it can grow (after v1)

- **Camps.** Forever's Camping system lets players build shared campfires that grant
  rested status. A camp has a builder and contributors, so "sign the fire you shared"
  is a natural extension of the ledger.
- **Hardcore memorials.** On the Hardcore ruleset, a signature from a character who
  later died becomes a memorial. Worth designing for deliberately once we know what the
  client exposes.
- **Companions.** The crossing-paths sync is already a record of who you've played
  with. A "people I've traveled with" view (how often, where, when you last saw them)
  is the natural next layer.
- **Profile website.** Public player profiles showing passport stamps, zone seals and
  earned badges, so players have a place to show off their collection. The AddOn stays
  complete without it. The only bridge is one paste: **Share** in the ledger, copy,
  paste on the site, publish. Neither the AddOn nor its download pages name the site.
  Profiles show only the uploader's own signatures. It's a separate project, started
  after launch.
- **Inn common room.** Seeing every AddOn user who stayed at your inn, strangers
  included, over a hidden chat channel. Classic blocks addon messages on custom
  channels, but the Forever beta allows them (2026-09-30), so it's technically possible;
  see [platform-forever.md](platform-forever.md). It's what "which fellow travelers have
  stayed there before you" on the download pages could grow into, but it widens who
  sees your signatures from group and guild to strangers, so it needs its own decision.

None of these are in v1. See [decisions.md](decisions.md).
