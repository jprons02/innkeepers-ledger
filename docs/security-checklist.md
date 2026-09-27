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
| `coverage` | untested lines in pure modules: 95% floor for `Ledger` and `SyncProtocol`, 90% for the rest, no `luacov:` opt-outs (`scripts/check-coverage.sh`) |
| `docs-links` | broken relative links in the docs and docs missing from the context map (`scripts/check-links.sh`) |

GitHub secret scanning with push protection is on for the repo.

### The forbidden-API check

`scripts/check-apis.sh` greps every `.lua`/`.xml` that git tracks (or would add), except
`Libs/`, `spec/` and `scripts/` (the packager drops the last two), plus
`Libs/embeds.xml`. It looks for these groups of names; the script holds the exact
lists.

- **Dynamic code:** `loadstring`, `load`, `setfenv`, `RunScript`, `ConsoleExec`, …
- **Global lookup by name:** `_G`, `getglobal`, `setglobal`. This closes the easy way
  around the grep (`_G["Run" .. "Script"]`).
- **Combat data:** combat log, health/power/aura/threat and in-combat state
  ([addon-policy.md → Combat restrictions](addon-policy.md#combat-restrictions-midnight-2026-01-28)).
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
- **Combat state in `Sync.lua`:** holding sends during encounters might need
  `InCombatLockdown` or the `PLAYER_REGEN_*` events. That reads a combat *state* flag,
  not combat data. **Approved by the maintainer** ([decisions.md](decisions.md),
  2026-09-27): add the allow-list entry when the sync implementation lands, citing that
  decision. It goes in as a separate `combat state` rule allowed only in `Sync.lua`; the
  `combat data` rule stays closed everywhere
  ([specs/sync-glue.md §5.2](specs/sync-glue.md#52-the-forbidden-apis-change)).

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
    [export-format.md](export-format.md) matches the code.
11. **Public repo hygiene:** no secrets, personal information, private notes or other
    projects in the diff, including docs and tickets.
12. **Workflows:** read-only token, `persist-credentials: false`, actions pinned by SHA,
    no `pull_request_target`, no new third-party actions.
