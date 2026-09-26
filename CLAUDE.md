# Innkeeper's Ledger — agent context

Standing context for AI agents (and humans) working in this repo. Lean on purpose: it
points at `docs/` rather than repeating it.

## What this is

A free, open-source World of Warcraft AddOn targeting **WoW: Forever** (launches
2026-11-04). Players sign a ledger by talking to innkeepers; the ledger becomes a
collection of inns plus the signatures of travelers they've crossed paths with,
synced peer-to-peer in-game. See [docs/vision.md](docs/vision.md).

## Context map

**Every session:** read [docs/status.md](docs/status.md) first. Then open only the docs the
task needs, using the "Read when" column. Don't read everything.

| Doc | Holds | Read when |
|---|---|---|
| [docs/status.md](docs/status.md) | current state, next step, open questions, what's waiting on the maintainer | always |
| [docs/decisions.md](docs/decisions.md) | the decision log: dated decisions, reasons, rejected options (newest first) | a question may already be settled; before proposing a change in direction |
| [docs/vision.md](docs/vision.md) | what we're building, the feel it must have, post-v1 directions | product or UX choices, wording, "should we build X" |
| [docs/architecture.md](docs/architecture.md) | modules, data model, signing flow, sync protocol, **security model**, testing posture | any code; sync, validation, storage caps, new modules |
| [docs/platform-forever.md](docs/platform-forever.md) | what's verified vs unverified about the Forever client; verification checklist | anything calling a WoW API; TOC; in-client testing |
| [docs/addon-policy.md](docs/addon-policy.md) | Blizzard AddOn policy rules that bind us | in-game text, links, anything paid or cosmetic, distribution pages |
| [docs/export-format.md](docs/export-format.md) | the export string spec (draft v0) | `Export` module; any change to exported data |
| [docs/prior-art.md](docs/prior-art.md) | existing guestbook AddOns and what we took from them | positioning, sync pattern precedent |
| [docs/kickoff.md](docs/kickoff.md) | phased build sequence to v1, cut order, completion criteria | picking the next step; timeline slips |
| [CONTRIBUTING.md](CONTRIBUTING.md) | local dev setup (Lua 5.1, busted, luacheck; Windows notes), PR conventions | setting up tooling; tests won't run locally |
| `docs/specs/<feature>.md` | one spec per feature (written by the planner) | working on that feature |

At the end of a session with real work or decisions: rewrite `docs/status.md`, add dated
entries to `docs/decisions.md` (newest first; supersede, never edit old entries), update
each fact's one home, and check that every doc under `docs/` has a map row and every
relative link resolves.

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
- **No spending.** Nothing that costs money is bought or enabled on the project's behalf
  unless the maintainer names that specific purchase; general approval ("go ahead")
  doesn't count. Packaging, distribution and CI stay on free tiers.

## Build loop

`planner → docs/specs/<feature>.md → implementer → reviewer → merge → report`

Agents drive work to done without checking in between steps:

- **Specs are self-approved** unless they contain a maintainer decision (below). List the
  assumptions made in the report.
- **Prove it works.** Write the tests, run them, fix, re-run until green. Report with
  evidence (test and lint output), never "should work". If the same problem survives
  ~3 genuinely different attempts, stop and report what was tried.
- **Merge** once tests, lint and CI are green and the reviewer passes.
- Agents live in `.claude/agents/`. They hand back to the orchestrating session, not to
  each other. The reviewer gives sync/validation code the scrutiny a security reviewer
  would.

**Maintainer gates — stop and ask only for these.** Batch the questions into one message
(tracked in `docs/status.md`) and keep working on everything they don't block:

1. Product decisions: scope, design, naming and in-game wording direction.
2. Spending money (see Hard rules).
3. Irreversible or public actions: publishing to CurseForge or Wago, tagging a release,
   posting publicly, deleting anything, force-pushing.
4. In-client verification that needs someone at the keyboard in a Forever client.

## Testing

`busted` specs with a stubbed WoW API layer, `luacheck` clean, both in CI next to the
policy guard. **Peer data is hostile in tests** (malformed, oversized, relayed, replayed,
forged). What truly needs the client goes on the in-client batch in `docs/status.md`.
Details: [docs/architecture.md → Testing posture](docs/architecture.md#testing-posture).

## Branch flow

- `main` is the default branch and the release line. `dev` is the integration branch.
- Work happens on `feat/<slug>` (or `fix/`, `chore/`, `docs/`) branches cut from `dev`.
  Open a PR into `dev` and **squash-merge** it once CI is green.
- `main` changes only through a `dev → main` release PR that summarizes what ships,
  merged with a **merge commit** (not squash) so `dev` and `main` don't diverge. `main`
  then sits a merge commit "ahead" of `dev` with identical content; that's expected, so
  don't sync it back.
- Before the first public release, `dev → main` merges freely. Tags and published
  releases go out only through the packager, and they are a maintainer gate.
- **Branch protection is on for `main` and `dev`** (admins included): changes land only
  through PRs, the CI check must pass, and force-pushes and deletion are blocked. No approving review is required. When
  a new CI job lands, add it to both branches' required checks.

## Stack

Lua 5.1 (WoW client). Ace3 (AceAddon, AceDB, AceComm, AceSerializer, AceGUI or custom
frames), LibDeflate for export encoding. Libraries are embedded per standard AddOn
practice. Tests: `busted`. Lint: `luacheck`. Packaging: BigWigs packager (CurseForge +
Wago), to be set up before release.
