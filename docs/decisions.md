# Decisions

> **Summary:** the decision log. Settled decisions with the reason for each and the
> options rejected, dated, **newest first**.
> **Read when:** a question may already be settled; before proposing a change in
> direction or re-proposing a rejected option.

**Don't re-litigate these.** If new information changes one, add a new dated entry at the
top that supersedes it (and links it) rather than editing history.

---

### 2026-09-26 — Security checks: forbidden-API guard on every PR, review before every release

A required CI job (`forbidden-apis`, `scripts/check-apis.sh`) greps shipped code for
forbidden APIs:
- dynamic code
- global lookup by name (`_G`)
- combat data
- chat and social sending
- hooks
- account and group actions
- addon messaging outside `Sync.lua`

Widening an allow-list needs a decision entry. Every `dev → main` release PR also gets a
security review of the release diff against `docs/security-checklist.md`, with the
results in the PR. Until launch the session fixes findings and merges on its own, and a
finding that needs a maintainer decision stops the release (the maintainer chose this).
Workflows pin actions by commit SHA and use read-only, unpersisted tokens.

*Rejected:*
- **Only reviewing at release time:** problems would already be on `dev`, and a grep
  costs nothing per PR.
- **CodeQL or dependency scanners:** no Lua support; no package dependencies.
- **A third-party secret scanner:** GitHub secret scanning with push protection is
  already on.
- **A maintainer sign-off on every release:** not needed before there are players.
- **Inline exemptions in code:** they'd hide allow-list changes from review.

*Reflected in:* `docs/security-checklist.md`; `CLAUDE.md` → Branch flow; `.github/workflows/`;
`docs/architecture.md` → Security model (pointer).

### 2026-09-26 — CI: own toolchain install, and the library manifest pinned to the review doc

`ci.yml` runs `luacheck`, `busted` (Lua 5.1) and `libs-manifest` as separate jobs on
every push and PR. All three are required checks on `main` and `dev`, next to the
policy guard. The toolchain comes from apt and luarocks.org at the local versions. The
only action is `actions/checkout`. The token is read-only and isn't persisted, because
luarocks build scripts run as root. `scripts/check-libs.sh` now also requires the
manifest's library hashes (all but `Libs/embeds.xml`) to equal `docs/libraries.md` →
*Reviewed files*. Changing, adding or removing a library therefore means editing the
review record too.
*Rejected:*
- **Third-party Lua setup actions:** more outside code to trust in CI.
- **One combined job:** the required checks would be less specific.
- **The manifest alone as the source of truth:** a PR could edit a library and its
  manifest line together and pass, which the #9 review found.
- **Pinning each doc line to its `Libs/` path:** the upstream paths differ from the
  vendored ones, so the doc would need a third column. Comparing hashes already keeps
  unreviewed bytes out.
- **Covering `embeds.xml` in the check:** it's our file, so PR review covers it, like
  `Core.lua`.

*Reflected in:* `.github/workflows/ci.yml`; `docs/libraries.md` → Vendoring and upgrades;
`CLAUDE.md` → Testing; branch protection.

### 2026-09-26 — Scaffold conventions: embeds.xml in the manifest, pure modules enforced twice

`Libs/embeds.xml` (ours; sets the library load order) is listed in `Libs/MANIFEST.sha256`
like the vendored files. Pure and data modules are checked twice: a strict plain-Lua
environment in the specs (load time) and a `pure` luacheck std with only plain-Lua names
(function bodies too). Pure modules get libraries as arguments too, so `Export` takes
the serializer and compressor from its glue caller instead of calling `LibStub`.
*Rejected:* an allow-list of extra files in `check-libs.sh` (one more rule to keep
strict, and edits to the load order would go unnoticed); relying on the spec
environment alone (it misses globals used inside functions, which the review showed);
letting `Export` call `LibStub` (breaks the pure/glue line and needs the WoW stub in its
tests).
*Reflected in:* `docs/libraries.md` → Vendoring and upgrades; `docs/architecture.md` →
Modules, Testing posture; `.luacheckrc`.

### 2026-09-26 — Work is queued as GitHub issues written for a cold start

Tickets are GitHub issues with fixed sections (Goal, Read first, Already decided, Scope,
Done when, Start here, Gates and dependencies). They link doc sections instead of
copying them. A session stopping mid-ticket posts a handoff comment. Only the repo
owner's text in an issue counts as instructions. Merges into `dev` don't auto-close
issues, so tickets are closed by hand with evidence.
*Rejected:* to-do lists inside `status.md` (they mix a snapshot with a queue and lose
per-item history); tickets that paste context in full (the copies go stale when docs
change); a project board (overhead with no gain for a single maintainer; labels and a
milestone cover it); trusting all issue comments (the repo is public, so anyone could
plant instructions).
*Reflected in:* `CLAUDE.md` → Tickets; `.github/ISSUE_TEMPLATE/`.

### 2026-09-26 — Vendor a reviewed, minimal set of libraries

Libraries are committed under `Libs/` at exact reviewed versions (Ace3 Release-r1403
parts, ChatThrottleLib, LibDeflate 1.0.2), with a sha256 manifest checked in CI. Only the
parts we use are included.
*Rejected:* fetching the latest at package time through packager externals (what ships
would differ from what was reviewed); the whole Ace3 bundle (more code to trust than we
use); AceComm and AceGUI (see the sync transport entry; the UI is custom frames).
*Reflected in:* `docs/libraries.md`; `CLAUDE.md` → Stack.

### 2026-09-26 — Sync: own receive handler and codec, single messages, no compression

`Sync` receives addon messages itself with a byte cap and sends through ChatThrottleLib.
Every message fits in one addon message. `SyncProtocol` uses its own fixed text format.
Nothing received is compressed or run through a general-purpose deserializer. Signer
and name aren't sent; they come from the resolved sender. Numeric fields must be finite
integers in range. The review behind this is in `docs/libraries.md` → Findings.
*Rejected:* receiving through AceComm (it buffers multi-part messages without a size
limit before we can reject them); AceSerializer for peer data (it yields `NaN`, `inf`,
floats and extra values, and it's a shared library another AddOn can replace at
runtime); compressing sync payloads (a 722:1 decompression bomb was demonstrated, and
entries are too small to benefit); sending signer and name (they're redundant under the
own-signature rule and add a forgery surface).
*Reflected in:* `docs/architecture.md` → Sync protocol, Security model, Data model.
Supersedes the AceComm transport and "decode inside pcall with size caps" wording in
the architecture's original sketch.

### 2026-09-26 — Export uses standard base64

The export payload is AceSerializer → LibDeflate `CompressDeflate` → standard base64
(RFC 4648), with our own encoder.
*Rejected:* LibDeflate `EncodeForPrint` (a custom 6-bit alphabet that outside tools
can't decode with stock libraries, and its header credits GPLv2-licensed code).
*Reflected in:* `docs/export-format.md` → Envelope; `docs/architecture.md` → Export.

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

### 2026-09-25 — Seed decisions (archived)

The first product decisions are in
[archive/decisions-2026-09.md](archive/decisions-2026-09.md), unchanged and still in
force. Titles, for references that cite them by name:

- Target WoW: Forever first
- Inns only in v1
- Canned phrases, not free text
- Sync scope: grouped-with + guild by default; global opt-in
- Accept only a sender's own signatures
- Cosmetics are earned by play, never paid or gated
- Generic, documented export string
- Open source under MIT
