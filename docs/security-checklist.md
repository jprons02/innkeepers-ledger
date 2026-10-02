# Security checklist

> **Summary:** the security checks that run on every PR, and the review every
> `dev → main` release PR gets before it merges.
> **Read when:** opening a release PR; changing CI, `scripts/check-*.sh` or an allow-list;
> adding a WoW API call to shipped code.

The threat model and the rules for peer data live in
[architecture.md → Security model](architecture.md#security-model--the-riskiest-part-of-the-addon).
This page checks that we followed them; it doesn't restate them.

## Automated, on every PR

All are required checks on `main` and `dev` (`CLAUDE.md` → Branch flow).

| Job | What it stops |
|---|---|
| `no-urls-in-game-code` | links or advertising in shipped code ([addon-policy.md](addon-policy.md)) |
| `libs-manifest` | vendored library files that differ from the reviewed ones ([libraries.md](libraries.md#vendoring-and-upgrades)) |
| `forbidden-apis` | forbidden APIs in shipped code (below) |
| `luacheck` | stray globals, including any global in pure modules |
| `busted` | regressions, including the hostile-peer-data specs |
| `coverage` | untested lines in pure modules: 95% floor for `Ledger`, `SyncProtocol` and `SyncSchedule`, 90% for the rest, no `luacov:` opt-outs (`scripts/check-coverage.sh`) |
| `docs-links` | broken relative links in the docs and docs missing from the context map (`scripts/check-links.sh`) |
| `package` | a package that isn't what the repo ships: the packager's dry run (`.github/workflows/release.yml`), then `scripts/check-package.sh` (exactly the shipped files, byte-for-byte, libraries matching the manifest, a filled-in, export-safe `## Version`) and `scripts/check-release.sh` (no `.env`, only plain tracked files, only the allowed `.pkgmeta` keys so no externals or license fetch, a manual changelog without links, each library a plain copy; for a tag, `vX.Y.Z` on a commit on `main`) |

GitHub settings that back these up: [Repository settings](#repository-settings).

### The forbidden-API check

`scripts/check-apis.sh` greps every `.lua`/`.xml` that git tracks (or would add), except
`Libs/`, `spec/` and `scripts/` (the packager drops the last two), plus
`Libs/embeds.xml`. It looks for these groups of names; the script holds the exact
lists.

- **Dynamic code:** `loadstring`, `load`, `setfenv`, `RunScript`, `ConsoleExec`, …
- **Global lookup by name:** `_G`, `getglobal`, `setglobal`. This closes the easy way
  around the grep (`_G["Run" .. "Script"]`).
- **Combat data:** combat log, health/power/aura/threat, `UnitAffectingCombat`
  ([addon-policy.md → Combat restrictions](addon-policy.md#combat-restrictions-midnight-2026-01-28)).
  Allowed nowhere.
- **Combat state:** `InCombatLockdown`, `PLAYER_REGEN_DISABLED`, `PLAYER_REGEN_ENABLED`.
  Allowed only in `Sync.lua`, which reads *whether* we're in combat to hold sends during
  fights and nothing more ([decisions.md](decisions.md), 2026-09-27 — Sync may read
  combat state, and players are told;
  [specs/sync-glue.md §5.2](specs/sync-glue.md#52-the-forbidden-apis-change)). Added in
  #47 as its own rule so the combat-data rule stays closed.
- **Chat and social sending:** say/whisper/Battle.net/community messages, mail, friends
  and ignore lists, `/who`.
- **Hooks:** `hooksecurefunc`, `HookScript`, chat message filters, …
- **Macros and bindings:** running or editing macros, secure action buttons, key
  bindings.
- **Gossip and innkeeper actions:** selecting gossip options, `ConfirmBinder`. `Sign`
  adds its own option but never picks one for the player, since that could reset their
  hearthstone.
- **Account and group actions:** invites, group and guild membership, CVars,
  reload/logout, store, items, trade, turning other AddOns on or off.
- **General-purpose decoders:** AceSerializer's `Deserialize` and LibDeflate's
  `Decompress…`, `DecodeFor…` and `CreateCodec` (its codec decodes) functions, and the
  client's own `C_EncodingUtil` namespace with its decoders (`DecompressString`,
  `DecodeBase64`, `DeserializeCBOR`, `DeserializeJSON`). Allowed
  nowhere: nothing we ship reads an
  export string or any other serialized or compressed data, so a crafted string can't
  reach an unbounded inflate or a float-yielding reader
  ([libraries.md → Findings](libraries.md#findings-that-shape-our-design) 2 and 3). The
  export's test-only decoder lives in `spec/`. Added in #64
  ([specs/export.md §5](specs/export.md#5-security-notes)).
- **Addon messages and channels:** sending, prefix registration, `CHAT_MSG_ADDON` and its
  variants, ChatThrottleLib, AceComm, joining or leaving chat channels. Allowed only in
  `Sync.lua`, plus `Libs/embeds.xml` so it can load ChatThrottleLib.

A name matches as a whole word, including after `.` or `:`. So a namespace cached in
a local (`local CI = C_ChatInfo; CI.SendAddonMessage(...)`) is caught too. Comments are
scanned, so reword a comment rather than naming a forbidden API. The check fails closed:
it fails if a file can't be read or git has to quote its name.
**Widening an allow-list or dropping a name needs a decision-log entry.** If one of our
own methods or locals collides with a listed name (`Book:SelectOption`, say), rename it.
Don't touch the list.

The check is a tripwire, not a proof. It can't see an API reached through a chain of
table lookups that never spells the name, and it can't see Blizzard functions being
overwritten. Release review item 1 covers those.

**Expected future exceptions (decide when the spec needs them):**
- **Hooks in `Sign.lua`:** injecting the gossip option will likely need
  `hooksecurefunc`/`HookScript` on the gossip frame. Add an allow-list entry with a
  decision entry. The alternative, overwriting the frame's methods, taints it.

## Repository settings

Set in GitHub, not in files; re-check them in each release review (item 12). Set on
2026-09-28 after the security audit ([decisions.md](decisions.md)).

- **Actions:** only GitHub-owned actions may run, and every action must be pinned to a
  full commit SHA (the repo's *Require actions to be pinned* setting). The default
  workflow token is read-only and can't approve PRs. First-time contributors' fork PRs
  need approval before CI runs.
- **Reporting:** private vulnerability reporting is on; [SECURITY.md](../SECURITY.md)
  points reporters there.
- **Secrets:** secret scanning and push protection are on. No repository secrets exist;
  the upload tokens live only in the `release` environment (below).
- **The packager** (set 2026-10-01, #81; [decisions.md](decisions.md)):
  - Allowed actions: GitHub-owned, plus exactly
    `BigWigsMods/packager@e50a250f8705041e40f2fa1ddcb280a686d65aa0` (v2.6.1).
  - Tag ruleset *Release tags: maintainer only*: creating, moving or deleting a `v*` tag
    is blocked for everyone but the repository admin (the maintainer's account).
  - Environment `release`: the maintainer is the required reviewer, and only `v*` tags
    may deploy to it. It holds `CF_API_TOKEN` and `WAGO_API_TOKEN`, entered by the
    maintainer. Its "Allow administrators to bypass configured protection rules" box
    is unchecked (the maintainer, 2026-10-01), so a publish always waits for an
    approval.
  - **What actually stops an agent.** Agents run as the maintainer's account, so the
    tag ruleset doesn't stop them, and the account that pushes a tag can also approve
    its deployment (the only reviewer is the maintainer, and a self-review block would
    lock him out). The stops are the agent's permission guard and the maintainer gates
    in `CLAUDE.md` (tagging and publishing are his). The environment makes a publish a
    deliberate, logged approval and keeps the tokens out of every other job; it is not
    a barrier against a session holding the maintainer's token.
  - `scripts/check-release.sh --tag` fails unless the tagged commit is on `origin/main`
    (so only code that passed a release PR's security review ships). It guards against
    a mistaken tag: the tagged commit carries its own copy of the script.

### Before the packager lands (first tag)

The packager publishes to every player, so a stolen token or account is the worst
supply-chain case. Before the first tag:
- [x] A second factor on every account that can publish. GitHub: 2FA, on since
  2026-09-28. CurseForge (project `1721704`) signs in with Google, so its second factor
  is that Google account's 2-Step Verification. Wago (project `n6VYeONd`) is reached
  through the GitHub sign-in it was set up with, which GitHub's 2FA covers; if it's
  another login, that login's 2-Step. The maintainer confirmed Google 2-Step
  (2026-10-01). The upload tokens are separate keys that bypass any login: they live only
  in the `release` environment's secrets, and are revoked and replaced if ever exposed.
- [x] The workflow runs only on `v*` tag pushes; a tag ruleset lets only the maintainer
  create or move `v*` tags (#81).
- [x] The CurseForge and Wago tokens live in a GitHub Environment with the maintainer as
  required reviewer, never as plain repository secrets. Only the publishing job gets
  `contents: write` (#81).
- [x] The packager action is pinned by SHA and added to the allowed-actions list by that
  exact pattern; a decision entry records it (it's a third-party action, item 12) (#81).

## Release review (every `dev → main` PR)

Before opening the release PR, the session reviews the whole release diff
(`git diff origin/main...origin/dev`) against this list. It can use the reviewer agent
with this page as its brief. The release PR gets a **Security review** section: each
item as pass, n/a or a finding.

**Findings get fixed on `dev` through a normal PR before the release merges.** Until
launch the session does this on its own. A finding that needs a maintainer decision
(scope, wording, anything in the gates) stops the release and goes to the maintainer.

1. **Dynamic behavior and taint:**
   - No code runs strings as code, reaches an API through lookups built from strings,
     or swaps function environments, however it's spelled.
   - No code overwrites Blizzard globals, frame methods or frame scripts. Hooks go only
     through `hooksecurefunc`/`HookScript`, and only where an allow-list permits them.
2. **Allow-lists:** every change since the last release to `scripts/check-apis.sh`,
   `scripts/check-libs.sh`, `.luacheckrc` globals or `Libs/embeds.xml` has a reason (a
   decision entry for allow-list widening).
3. **Peer data at the edge:** every path from `CHAT_MSG_ADDON` to `Ledger` goes through
   `SyncProtocol` validation, and each rule in the Security model has hostile-input
   specs (malformed, oversized, relayed, replayed, forged).
4. **Own-signature rule:** signer and name come only from the resolved sender, never
   from the payload; unresolved senders are dropped.
5. **Bounded storage:** nothing a peer sends can grow SavedVariables past the caps, and
   eviction is tested.
6. **Quiet failure:** bad input produces no chat output, pop-up or error, only the debug
   log. Parsing runs inside `pcall`.
7. **Sending:** the AddOn sends only its own entries, only through ChatThrottleLib in
   `Sync`, and only in response to the documented triggers. No new message types
   without a spec.
8. **Rendering:** peer-derived strings are shown as plain text; `|` escape sequences are
   rejected before display.
9. **Policy:** no new external references, links, paid or gated features; in-game
   wording follows [addon-policy.md](addon-policy.md).
10. **Export:** the export string gained no data beyond the player's own ledger, and
    `travelers` appears only when the player opts in;
    [export-format.md](export-format.md) matches the code.
11. **Public repo hygiene:** no secrets, personal information, private notes or other
    projects in the diff, including docs and tickets.
12. **Workflows:** read-only token, `persist-credentials: false`, actions pinned by SHA,
    no `pull_request_target`, no new third-party actions (the one allowed is the
    packager, pinned by SHA). Only `release.yml`'s `publish` job has `contents: write`
    or sees the tokens. The [repository settings](#repository-settings) still hold.
13. **Packaged version:** the version the packager writes into the TOC (`## Version`)
    matches `[A-Za-z0-9._+-]{1,32}`. Anything else (a space, a `/`, 33 bytes) makes every
    export refuse with `"addon"` ([specs/export.md §3.5](specs/export.md#35-build-rules)).
