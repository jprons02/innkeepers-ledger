# Decisions

> **Summary:** the decision log. Settled decisions with the reason for each and the
> options rejected, dated, **newest first**.
> **Read when:** a question may already be settled; before proposing a change in
> direction or re-proposing a rejected option.

**Don't re-litigate these.** If new information changes one, add a new dated entry at the
top that supersedes it (and links it) rather than editing history.

---

### 2026-09-26 — Sender identity is resolved per channel; unresolved senders are dropped

The own-signature rule needs the sender's GUID, but addon messages carry only a name.
`Sync` resolves it per channel: `UnitGUID(sender)` for PARTY/RAID and a roster-built
name → GUID map for GUILD. Other channels aren't accepted in v1. If the sender can't be
resolved, the message is dropped, and `entry.name` must match the resolved sender.
*Rejected:* trusting the payload's `signer` (forgeable by anyone); matching by name alone
(names change and can be reused, while GUIDs are stable); digital signatures on entries (no
way to bind a key to a character in-game, so they prove nothing the client can't already
tell us); retrying or queuing unresolved senders (complexity for little gain, since the
next HELLO resyncs).
*Reflected in:* `docs/architecture.md` → Security model; `docs/platform-forever.md` →
Verification checklist.

### 2026-09-26 — Branch protection on `main` and `dev` (supersedes part of the branch-flow entry below)

Both branches are protected with admins included: PRs only, the CI check required, no
force-pushes, no deletion, and no required approving review, since there's a single
maintainer. `dev` also requires linear history (squash merges). Release PRs into `main`
use a merge commit. `main` then sits a merge commit ahead of `dev` with identical
content, which is expected. This replaces the "Rejected: branch protection rules" line
in the branch-flow entry below.
*Rejected:* requiring an approving review (a single maintainer can't approve their own
PRs, so it would block everything); exempting admins (makes the rules optional);
squash-merging release PRs (`main` and `dev` histories would diverge); requiring
release branches to be up to date with `main` (`dev` could only catch up through a
merge commit, which its linear-history rule forbids).
*Reflected in:* `CLAUDE.md` → Branch flow; `CONTRIBUTING.md` → Branches and pull
requests.

### 2026-09-26 — Context docs as a map-driven tree

`CLAUDE.md` carries a Context map (doc / holds / read when) in place of a fixed reading
list. Running status moved out of `kickoff.md` into a new `docs/status.md` that every
session reads first and rewrites at the end. Every doc opens with a Summary / Read-when
header. This file stays the decision log, newest first. Each fact has one home; other
docs link to it.
*Rejected:* keeping status inside `kickoff.md` (a bootstrap-only runbook shouldn't hold
running state, and it gets archived after v1); a separate `decision-log.md` (this file
already is one, and renaming would break links); reading every doc each session (costly,
and it doesn't scale as specs accumulate).
*Reflected in:* `CLAUDE.md` → Context map; `docs/status.md`; `docs/kickoff.md`.

### 2026-09-26 — Autonomous build loop with maintainer gates

Specs are self-approved, and agents test, iterate until green, merge and report with
evidence. Work stops only for the maintainer gates: product decisions (scope, design,
naming), spending money, irreversible or public actions (publishing, tagging, posting,
deleting, force-pushing) and in-client verification. Those questions are batched in
`status.md` while other work continues. Kickoff step 1 becomes a report, not a wait.
*Rejected:* a human approval on every spec and a sign-off on every merge (it serializes
work on the maintainer ahead of a fixed launch window; the gates that matter are kept).
*Reflected in:* `CLAUDE.md` → Build loop; `docs/kickoff.md` → Sequence.

### 2026-09-26 — Test standard: busted + stubbed WoW API, hostile peer data

Pure logic runs under `busted` outside the game, with client calls behind a stubbed WoW
API layer. Tests treat all peer data as hostile (malformed, oversized, relayed, replayed,
forged signer, unknown IDs, compression bombs). `luacheck` must be clean. CI runs both
next to the policy guard. Anything that truly needs the client is listed for the
maintainer instead of blocking work.
*Rejected:* testing only in the client (slow, manual, and it can't cover malicious
input); browser/e2e tooling (doesn't apply to an in-game AddOn).
*Reflected in:* `CLAUDE.md` → Testing; `docs/architecture.md` → Testing posture.

### 2026-09-26 — Branch flow: feature branches → dev → main

`dev` is the integration branch. Work happens on `feat/`, `fix/`, `chore/` and `docs/`
branches from `dev`, squash-merged once green. `main` stays the default branch and
changes only through `dev → main` release PRs. Tags and published releases go out only
through the packager and are a maintainer gate. CI runs on `dev` as well as PRs.
*Rejected:* committing straight to `main` (no integration line ahead of releases);
branch protection rules (not configured; CI and discipline enforce the flow for now).
*Reflected in:* `CLAUDE.md` → Branch flow.

### 2026-09-26 — No spending without a named purchase; free beta route by default

Nothing that costs money is bought or enabled on the project's behalf unless the
maintainer names that purchase. Packaging, distribution and CI stay on free tiers. Beta
access defaults to the free opt-in; the paid pre-purchase route is the maintainer's call
alone.
*Rejected:* buying a higher-tier edition to guarantee beta access (a spending decision
only the maintainer can make; the no-beta plan still ships ~1–2 weeks after launch).
*Reflected in:* `CLAUDE.md` → Hard rules; `docs/status.md` → Client access plan.

---

### 2026-09-25 — Target WoW: Forever first

Forever launches 2026-11-04 with no player housing, so the guestbook idea is completely
unclaimed there, and a launch-window release is the best discovery moment an AddOn
gets. Retail is a possible second target. If the API turns out to be shared (see
[platform-forever.md](platform-forever.md)), a multi-interface TOC may cover both
cheaply, but retail is never allowed to delay Forever.

### 2026-09-25 — Inns only in v1

Inns are where hearthstones bind, and nobody has built for them. Retail housing
guestbooks already exist (see [prior-art.md](prior-art.md)), so we don't compete there.
**Camps** (Forever's Camping system) are the first post-launch candidate once their API
behavior is known. Camps are ephemeral, which raises open questions about identifying
and naming them.

### 2026-09-25 — Canned phrases, not free text

The housing guestbooks allow free-text notes because a homeowner can delete them. An
inn has no moderator, and entries propagate peer-to-peer, so free text would carry
offensive content from book to book, and that responsibility lands on the AddOn author
(policy Rule 6, [addon-policy.md](addon-policy.md)). A phrase builder (templates plus
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
consumer. Spec: [export-format.md](export-format.md).

### 2026-09-25 — Open source under MIT

Blizzard's policy already requires unobfuscated code; publishing it properly under MIT
makes that a strength.
