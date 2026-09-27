# Decisions

> **Summary:** the decision log. Settled decisions with the reason for each and the
> options rejected, dated, **newest first**.
> **Read when:** a question may already be settled; before proposing a change in
> direction or re-proposing a rejected option.

**Don't re-litigate these.** If new information changes one, add a new dated entry at the
top that supersedes it (and links it) rather than editing history.

---

### 2026-09-27 — Re-signing an inn: once per week, resetting Friday 10:00 UTC

A character may sign each inn once per signing week. Weeks start every **Friday at
10:00 UTC** (the maintainer chose weekly; the session picked the reset time within that).
The ledger enforces the rule for incoming signatures too: a traveler's second signature
at the same inn in the same week is rejected. Signing a different inn in the same week
is fine. Details: `docs/specs/sync-ledger.md` §3.1 (`weekAnchor`), §4.4.

*Rejected:*
- **Once per day** (the first proposal): repeat visits would fill a traveler's 40-entry
  share window with one inn, and own entries (never evicted) would grow fast.
- **WoW's own weekly reset:** it differs by region (Tuesday 15:00 UTC in the US,
  Wednesday 07:00 UTC in Europe), so two players could disagree about which week a
  signature is in. A fixed UTC time is the same for everyone and is plain arithmetic on
  server time.
- **A rolling 7 days since the last signature:** harder to explain in the UI than "the
  ledger turns a page every Friday".
- **Limiting only our own signing:** a modified client could still fill all 40 of its
  slots at one inn; checking incoming signatures too costs one lookup.

*Reflected in:* `docs/specs/sync-ledger.md`; tickets #30, #31.

### 2026-09-27 — Peer-data rate limits and time window

Received, per resolved sender GUID in fixed 60-second windows: 40 messages and 80
entries. Across all senders: 1 200 admitted messages. At most 1 000 senders are tracked;
when the table is full after pruning, new senders are dropped. Sent, by our own `Sync`:
at most 30 messages and 60 entries in any 60 s, 1 HELLO per channel per minute, 12
WANTs per minute, and one full reply per channel per 5 minutes (a later one is deferred,
not dropped). Timestamps must fall
between 2026-09-17 00:00 UTC (the Forever beta start) and now + 300 s. The numbers are
checked against a written traffic model (a 40-player raid syncing from scratch stays
under every limit). Details: `docs/specs/sync-ledger.md` §3.1, §5.3, §8.

*Rejected:*
- **The launch date (2026-11-04) as the earliest time:** entries signed during the beta
  would fail, so the AddOn couldn't be tested there. Backdating by seven weeks gains a
  forger nothing.
- **A token bucket:** smoother, but a fixed window is simpler to test exactly, and the
  double burst at a window edge is still small.
- **No global ceiling:** a crowd of modified clients could each stay under the
  per-sender limit.
- **The first draft's 30 / 600 limits:** they left WANT traffic out, so honest raid
  traffic would have been dropped (found in the spec review).

*Reflected in:* `docs/specs/sync-ledger.md`; `docs/architecture.md` → Security model.

### 2026-09-27 — Ledger storage: caps, eviction and SavedVariables shape

Foreign entries are capped at **40 per signer** (equal to the share window), **150 per
inn** and **3 000 in total** (about 400 KB of SavedVariables). Over a cap, the oldest
entry by `(t, signer, inn)` goes, so the store always holds the newest. Own entries are
never evicted. Ledgers live in `InnkeepersLedgerDB.global.ledgers[<character GUID>]`
with a ledger-level `schema` field (the per-entry `v` is gone), entries grouped per
traveler, and the time each cosmetic was earned. A ledger whose schema is newer than the
AddOn, or unreadable, opens read-only and is never rewritten. Details:
`docs/specs/sync-ledger.md` §4.

*Rejected:*
- **AceDB's per-character namespace:** it's keyed by name, and names can change; the
  GUID is the identity.
- **Evicting by receive time:** replaying old entries would keep them alive; signing
  time is what the book shows.
- **A flat list with signer and name on every entry:** repeats the GUID and name up to
  40 times per traveler.
- **Larger caps (10 000+):** multi-megabyte SavedVariables for a guild-heavy player,
  with little gain on the book's pages.
- **Wiping or rewriting unreadable saved data:** it would destroy a player's ledger after
  a downgrade.
- **Migrating in place:** a migration that fails halfway would leave half-migrated
  data; migrations run on a copy that is written back only on success.

*Reflected in:* `docs/specs/sync-ledger.md` §4; `docs/architecture.md` → Data model.

### 2026-09-27 — Sync wire format v1 and digest

Three ASCII messages, `H1:<count>:<digest>`, `W1:<target GUID>:<since>` and
`E1:<entry>;…` with up to 5 entries of `inn,t,p.p.p,seal`, in decimal with exactly one
spelling per number; every message fits in 255 bytes (worst case 242). ENTRIES are
broadcast so one reply serves every asker. The digest is a polynomial hash
`h = (h * 257 + byte) % 2147483647` over the canonical text of the sender's newest 40
own entries, which is exact in Lua 5.1 without a `bit` library. A peer is asked at most
twice per 10 minutes whatever its digest does, and a WANT seen on the same channel for the
same peer suppresses ours (the broadcast reply covers us). A syntax error drops the
whole message, while an unknown inn, phrase or seal skips only that entry. Messages
echoed back from ourselves are dropped. Details: `docs/specs/sync-ledger.md` §3, §5.1.

*Rejected:*
- **CRC32 / FNV:** need bitwise operations that busted's Lua 5.1 lacks, so the tests
  wouldn't run the shipped code.
- **Count + newest time as the digest:** misses a lost message in the middle.
- **Base36 or binary numbers:** one more entry per message, but a harder parser to audit.
- **A version on every entry:** the header already carries it.
- **Replying by whisper:** whispers aren't an accepted channel in v1.
- **Dropping a whole message for one unknown ID:** a peer with newer inn data would lose
  its valid entries too.
- **Capping WANTs per (peer, digest):** a peer churning its digest could make a whole
  raid broadcast WANTs nonstop (found in the spec review).

*Reflected in:* `docs/specs/sync-ledger.md`; `docs/architecture.md` → Sync protocol.

### 2026-09-27 — AddOn list blurb names both halves of the AddOn

The TOC `## Notes` line (the tooltip in the in-game AddOns list) reads "Sign the ledger
at every inn you rest in, and collect the signatures of travelers you meet along the
way." The maintainer took this recommendation.

*Rejected:*
- **Reusing the README's line** ("Talk to an innkeeper, sign the ledger, and fill a book
  of every inn you've rested at."): it describes only the inn collection and leaves out
  travelers crossing paths, which is what sets the AddOn apart.

*Reflected in:* `InnkeepersLedger.toc`.

### 2026-09-27 — Profile site trust: showcase only, no profile key in the v1 export

Exports can't be proven genuine: the code is public, there's no network, and the player
controls both the string and SavedVariables. So the site **shows collections off and
never ranks them**, which removes the reward for faking. Trust work lives on the site,
after launch:
- **Sanity checks:** only real inns; no times before launch or in the future;
  cosmetics earned after the entries behind them; no impossible travel; a re-upload
  keeps earlier stamps.
- **Ownership:** a login at first Publish, and "Log in with Battle.net" if Blizzard's
  API covers Forever characters (unchecked).
- **A report button.**
- **Later, "witnessed" stamps:** a future export carries fingerprints of entries
  received through sync (no names), so the site can mark a stamp that another
  uploader's ledger also holds.

The v1 export stays as specified. New fields can be added later without breaking old
strings.

*Rejected:*
- **Leaderboards:** they reward forging, and nothing can stop it.
- **A profile key in the v1 export:** the Share window would need a "keep this private"
  warning, anyone shown the string could take over the profile, and a site login gives
  the same protection with no AddOn change.

*Reflected in:* `docs/export-format.md` → Trust.

### 2026-09-27 — Profile website: after v1, a separate project, reached by one paste

A website with public player profiles (passport stamps, zone seals, earned badges) is a
post-v1 direction. The goal is that players go out of their way to share. The flow is
the export string: **Share** in the ledger shows the string preselected, the player
copies it, pastes it into the site, sees a preview and publishes. Pasting again later
updates the profile. WoW players already do this daily with WeakAuras and
SimulationCraft strings, so it isn't a scary step. v1 only needs the Share button and an
export that carries stamps, seals and badges with the time each was earned
([export-format.md](export-format.md)). The site itself is its own project, not part of
this repo.

The maintainer ruled that **neither the AddOn nor its download pages (CurseForge, Wago)
name or link the site**, so the policy rule in [addon-policy.md](addon-policy.md) stands
unchanged. Players find the site through the site itself and word of mouth. Profiles
show only the uploader's own signatures, never the travelers they met. How far the site
should trust uploads is still being discussed ([status.md](status.md)).

*Rejected:*
- **A companion desktop app that uploads automatically:** an install, Windows
  "unknown publisher" warnings unless a code-signing certificate is bought every year,
  and a second product to maintain.
- **Dragging the SavedVariables file onto the site:** players would have to find a
  folder buried in the WoW install.
- **An in-game prompt to upload:** it would name an outside site (Rule 4).
- **Mentioning the site on the download pages:** the maintainer said no.
- **Building the site before launch:** it would put the 2026-11-04 date at risk, and a
  versioned export means launch-day strings still work later.

*Reflected in:* `docs/vision.md` → Where it can grow; `docs/export-format.md`.

### 2026-09-27 — Keep the inn ledger after a pivot review

The maintainer considered changing the concept. Research on 2026-09-27 found every
alternative already taken on Forever or elsewhere, while nothing on Forever collects or
signs inns ([prior-art.md](prior-art.md) → The Forever landscape). The ledger stays;
v1 leans harder into the collection feeling like a passport (a stamp per inn, a seal per
zone).

*Rejected:*
- **Player memory ("familiar faces"):** Blizzard's Recent Allies ships in Forever, and
  iWillRemember already runs there.
- **An automatic character chronicle:** Forever Journal launched 2026-09-24, from an
  author shipping a Forever AddOn almost daily.
- **A Hardcore memorial wall:** Deathlog, Hardcore and a Forever-native memorial exist,
  and Forever has no Hardcore ruleset at launch.
- **Campfire stories:** 13 camping AddOns appeared in the first 10 days of the beta.
- **An "inn common room" with strangers over a hidden channel:** Blizzard blocked
  addon messages to custom channels in Classic in 2019. Whether Forever allows them is
  on the in-client checklist; if it does, this is a post-v1 candidate.

### 2026-09-27 — Sync may read combat state, and players are told

`Sync` may use `InCombatLockdown` and the `PLAYER_REGEN_*` events to hold sends until a
fight ends. That's a yes/no state flag; combat *data* (damage, targets, logs) stays
off-limits. Because "reads combat" sounds alarming, the README's principles say exactly
what is checked and why. The `forbidden-apis` allow-list for `Sync.lua` widens only
when the sync implementation lands, citing this entry.

*Rejected:*
- **Sending during fights:** extra traffic while players least want it, and Midnight-era
  rules may block addon messages in encounters anyway.
- **Not telling players:** the check is harmless, but a silent one looks like a hidden
  combat reader to anyone reading the code.

*Reflected in:* `README.md` → Principles; `docs/security-checklist.md` → Expected future
exceptions.

### 2026-09-26 — Security checks: forbidden-API guard on every PR, review before every release

A required CI job (`forbidden-apis`, `scripts/check-apis.sh`) greps shipped code for
forbidden APIs:
- dynamic code
- global lookup by name (`_G`)
- combat data
- chat and social sending
- hooks
- macros and key bindings
- selecting gossip options (picking one for the player could reset their hearthstone)
- account and group actions
- addon messaging and chat channels outside `Sync.lua`

A name matches after `.` or `:` too, so a cached namespace alias is caught. The check
fails closed on unreadable or oddly named files.

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
