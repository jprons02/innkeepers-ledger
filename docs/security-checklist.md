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

GitHub secret scanning with push protection is on for the repo.

### The forbidden-API check

`scripts/check-apis.sh` greps every shipped `.lua`/`.xml` (outside `Libs/`, `spec/` and
`scripts/`, plus `Libs/embeds.xml`) for these groups of names. The script holds the exact
lists.

- **Dynamic code:** `loadstring`, `load(`, `setfenv`, `RunScript`, …
- **Global lookup by name:** `_G`, `getglobal`, `setglobal`. This closes the easy way
  around the grep (`_G["Run" .. "Script"]`).
- **Combat data:** combat log, health/power/aura/threat and in-combat state
  ([addon-policy.md → Combat restrictions](addon-policy.md#combat-restrictions-midnight-2026-01-28)).
- **Chat and social sending:** say/whisper/Battle.net/community messages, mail.
- **Hooks:** `hooksecurefunc`, `HookScript`, …
- **Account and group actions:** invites, guild membership, CVars, reload/logout, store,
  items, trade.
- **Addon messages:** sending, prefix registration, `CHAT_MSG_ADDON` and
  ChatThrottleLib. Allowed only in `Sync.lua` (and in `Libs/embeds.xml`, which loads
  ChatThrottleLib).

Comments are scanned too, so reword a comment rather than naming a forbidden API.
**Widening an allow-list or dropping a name needs a decision-log entry.** The check is
a tripwire, not a proof: it can't see a name built through something other than `_G`.
Release review item 1 covers that.

## Release review (every `dev → main` PR)

Before opening the release PR, the session reviews the whole release diff
(`git diff origin/main...origin/dev`) against this list. It can use the reviewer agent
with this page as its brief. The release PR gets a **Security review** section: each
item as pass, n/a or a finding.

**Findings get fixed on `dev` through a normal PR before the release merges.** Until
launch the session does this on its own. A finding that needs a maintainer decision
(scope, wording, anything in the gates) stops the release and goes to the maintainer.

1. **Dynamic behavior:** no code runs strings as code, looks up globals by constructed
   names, or swaps function environments, however it's spelled.
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
    [export-format.md](export-format.md) matches the code.
11. **Public repo hygiene:** no secrets, personal information, private notes or other
    projects in the diff, including docs and tickets.
12. **Workflows:** read-only token, `persist-credentials: false`, actions pinned by SHA,
    no `pull_request_target`, no new third-party actions.
