# Decisions, 2026-09-25 (seed entries)

> **Summary:** the first product decisions, made at project setup: target, scope, phrases,
> sync scope, own-signatures-only, earned cosmetics, export, license. Still in force
> unless a newer entry in [decisions.md](../decisions.md) supersedes one.
> **Read when:** [decisions.md](../decisions.md)'s index points you here, or a product
> question may already be settled.

Moved here from `decisions.md` on 2026-09-26 to keep the log short. The text is unchanged
apart from link paths.

### 2026-09-25 — Target WoW: Forever first

Forever launches 2026-11-04 with no player housing, so the guestbook idea is completely
unclaimed there, and a launch-window release is the best discovery moment an AddOn
gets. Retail is a possible second target. If the API turns out to be shared (see
[platform-forever.md](../platform-forever.md)), a multi-interface TOC may cover both
cheaply, but retail is never allowed to delay Forever.

### 2026-09-25 — Inns only in v1

Inns are where hearthstones bind, and nobody has built for them. Retail housing
guestbooks already exist (see [prior-art.md](../prior-art.md)), so we don't compete there.
**Camps** (Forever's Camping system) are the first post-launch candidate once their API
behavior is known. Camps are ephemeral, which raises open questions about identifying
and naming them.

### 2026-09-25 — Canned phrases, not free text

The housing guestbooks allow free-text notes because a homeowner can delete them. An
inn has no moderator, and entries propagate peer-to-peer, so free text would carry
offensive content from book to book, and that responsibility lands on the AddOn author
(policy Rule 6, [addon-policy.md](../addon-policy.md)). A phrase builder (templates plus
word lists, in the spirit of Dark Souls messages) keeps expression without needing
moderation. A useful side effect: every entry is a small set of known IDs, which makes
validating synced data simple.

### 2026-09-25 — Sync scope: grouped-with + guild by default; global opt-in

"People you've grouped with" is the literal meaning of crossing paths and a natural
consent boundary. Guild sync is on by default. A wider "anyone" sync is an experimental
opt-in (the same pattern the housing guestbooks use). On Forever's shared worlds, a
global channel would be a firehose.
*Open check:* whether addon messages are restricted inside instances. If so, sync
when the group leaves the instance.

### 2026-09-25 — Accept only a sender's own signatures

Peers never relay third-party entries. When you sync with someone, you receive only
the entries they signed themselves. This makes forging someone else's signature
impossible (you can only claim your own), limits how far spam can spread, and matches
the fiction: you learn about a traveler by meeting that traveler.

### 2026-09-25 — Cosmetics are earned by play, never paid or gated

AddOn policy requires the AddOn to be free with no paid services, and it bars
advertising. Every quill, ink and seal unlocks through the collection. There is no
unlock code, no external check, and no feature that depends on anything outside the
game.

### 2026-09-25 — Generic, documented export string

A documented, versioned export (the SimulationCraft pattern) lets players take their
ledger anywhere. The format is public and neutral; the AddOn never names or links a
consumer. Spec: [export-format.md](../export-format.md).

### 2026-09-25 — Open source under MIT

Blizzard's policy already requires unobfuscated code; publishing it properly under MIT
makes that a strength.
