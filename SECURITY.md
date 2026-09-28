# Security

Innkeeper's Ledger trades data with other players' AddOns in-game, so a bug in how it
reads that data could affect everyone who runs it. If you find one, please report it
privately first.

## Reporting a vulnerability

Use GitHub's private reporting: open this repository's **Security** tab and choose
**Report a vulnerability**. Only the maintainer sees the report. Please don't open a
public issue for it.

Helpful to include: what a hostile player (or a crafted file or string) can make the
AddOn do, the steps or message text that trigger it, and the AddOn version.

## What counts

- Anything another player can send that gets past validation: a forged signature, an
  entry stored outside the caps, an error or chat output, UI escape codes, runaway CPU or
  memory, or making your client send far more than it should.
- Anything that makes the AddOn read combat data, act for the player (chat, trade, mail,
  invites, gossip choices) or run code built from a string.
- A way into the published package that bypasses this repository's checks.

How the AddOn treats other players' data:
[docs/architecture.md → Security model](docs/architecture.md#security-model--the-riskiest-part-of-the-addon).

## Supported versions

Only the latest release gets fixes.
