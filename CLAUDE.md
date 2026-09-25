# Innkeeper's Ledger — agent context

Standing context for AI agents (and humans) working in this repo. Lean on purpose: it
points at `docs/` rather than repeating it.

## What this is

A free, open-source World of Warcraft AddOn targeting **WoW: Forever** (launches
2026-11-04). Players sign a ledger by talking to innkeepers; the ledger becomes a
collection of inns plus the signatures of travelers they've crossed paths with,
synced peer-to-peer in-game. See [docs/vision.md](docs/vision.md).

## Status

**Pre-build.** Docs are seeded; no AddOn code exists yet. The first session follows
[docs/kickoff.md](docs/kickoff.md).

## Read before doing anything

1. [docs/vision.md](docs/vision.md): what we're building and the feel it must have
2. [docs/decisions.md](docs/decisions.md): settled decisions (**do not re-litigate**;
   raise a new question instead)
3. [docs/architecture.md](docs/architecture.md): modules, data model, sync protocol,
   security model, testing posture
4. [docs/platform-forever.md](docs/platform-forever.md): what's verified vs unverified
   about the target client. **Unverified claims must be verified in-client before code
   depends on them.**
5. [docs/addon-policy.md](docs/addon-policy.md): the rules that can get an AddOn pulled

## Hard rules

- **This repository is public.** Never commit secrets, personal information, private
  notes, or content about other projects. If something feels like it belongs in a
  private note, it does not belong here.
- **The AddOn never references, links to, or promotes any external product, site, or
  service, and has no paid or gated features.** AddOn policy: free of charge, no
  advertising. Every cosmetic is earned through play. The only outbound bridge is the
  neutral, documented [export string](docs/export-format.md); it never names a
  consumer.
- **Never read combat data.** Midnight-era restrictions make it a black box, and this
  AddOn has no reason to touch it.
- **No network access exists; don't design for it.** Sync is in-game addon messages only.
- **Data from other players is untrusted input.** Follow the validation rules in the
  architecture doc exactly. Accept only a sender's *own* signatures, never relayed
  third-party entries.
- **Scope guard:** inns only in v1. Camps and the "Companions" expansion are planned
  later (see decisions). Say no to scope creep before the launch window.

## Build loop

`planner → docs/specs/<feature>.md → human approves spec → implementer → reviewer → human sign-off → merge`

Agents live in `.claude/agents/`. They hand back to the orchestrating session, not to
each other. The reviewer gives the sync/validation code the scrutiny a security
reviewer would.

## Stack

Lua 5.1 (WoW client). Ace3 (AceAddon, AceDB, AceComm, AceSerializer, AceGUI or custom
frames), LibDeflate for export encoding. Libraries are embedded per standard AddOn
practice. Tests: `busted`. Lint: `luacheck`. Packaging: BigWigs packager (CurseForge +
Wago), to be set up before release.
