# Status

> **Summary:** where the project stands right now, what's next, and what's waiting on the
> maintainer. A snapshot, rewritten each session; history lives in git and
> [decisions.md](decisions.md).
> **Read when:** every session, first thing after `CLAUDE.md`.

**Updated:** 2026-10-01 (packager workflow, #81 in #86; name form in `/ledger debug`, #80 in #85)

## Current state

- **Phase 1 of [kickoff.md](kickoff.md) is done:** every pure module and the sync glue
  exist, are tested (pure modules at 100% coverage) and passed security-level reviews.
  - Slice 1 (#10): `Ledger`, `SyncProtocol`; spec [specs/sync-ledger.md](specs/sync-ledger.md).
  - Slice 2 (#41): `Core`, `SyncSchedule`, `Sync`; spec [specs/sync-glue.md](specs/sync-glue.md).
  - Slice 3 (#61): `Phrase`, `Collection`, `Cosmetics`, `Export` (export string **v1**);
    specs [phrase.md](specs/phrase.md), [collection-cosmetics.md](specs/collection-cosmetics.md),
    [export.md](specs/export.md).
- **Phase 2 has started (#12).** The maintainer is in the Forever beta (#1, #2 closed:
  beta route). The first in-client run (2026-09-30) used the throwaway probe AddOn
  ([testing.md → The in-client probe](testing.md#testing-posture)). Results:
  [platform-forever.md](platform-forever.md).
  - ✅ Modern retail/Midnight API; TOC `16001`; the AddOn and libraries load; no hidden
    values outside combat; NPC IDs readable from `UnitGUID("npc")`; a button on the
    gossip frame works; custom-channel addon messages allowed; 255-byte cap (longer
    messages truncated silently); edit box holds 256 KB; no sitting API.
  - ✅ **Two-part names** (`"First Surname"`, surname in the realm slot): fixed in #75.
    Senders, group and guild keys and stored names use the bare `"First Surname"`;
    the owner's name is `"First Surname"` ([decisions.md](decisions.md), 2026-09-30).
    Still to confirm with a second character (#12). `/ledger debug`'s report ends with
    `names two-part`, `names realm` or `names undecided`, and Core and Sync read our
    own name through one helper (#80).
  - ✅ **Zones can sit under the world map with no continent:** fixed in #76 (#83). Such a
    zone is grouped under its World map (Zephras Isle → Azeroth 947); a map ID never
    keys both a zone and a continent ([decisions.md](decisions.md), 2026-09-30). The
    other zones' chains come in as the collection fills (#12).
- **Not built:** `Sign` and `UI/Book`. The gossip and NPC-ID questions are answered for
  ordinary NPCs, but **no innkeeper has been seen yet**. File their tickets once one has
  (contracts in each spec's §8).
- **Data:** `Data/Inns` empty. Forever's world is new, so it fills in from the probe's
  logs as the maintainer plays. Phrase and cosmetic sets are DRAFTs.
- **CI:** eight required checks on `main` and `dev`, all runnable locally but the
  packager's dry run (`package`, CI only)
  ([CONTRIBUTING.md](../CONTRIBUTING.md#development-setup)).
- **Releases:** the Phase 1 release PR (2026-09-28) shipped to `main`; later changes are
  on `dev` only. No tags or published builds (maintainer gate).

## Next step

- **#81** (the packager): built and merged in #86. `release.yml` dry-runs the packager
  on every PR (`package`, a required check) and publishes a `v*` tag only after the
  maintainer approves the `release` environment. Packager v2.6.1 pinned by SHA; tag
  ruleset and environment set. Left open for the maintainer's part (below) and the
  first manual dry run once `release.yml` reaches `main`.
- **In the client (maintainer, as you play):** keep ILProbe enabled. Talk to every
  innkeeper you pass (the probe logs NPC ID, map chain, faction and gossip options) and
  `/reload` now and then so the log is written. Then `Sign` and `UI/Book` tickets.

## Client access plan

- **In the beta** (2026-09-30), which runs until **2026-10-21**. Launch: **2026-11-04**.
  Plan: Phase 2 during the beta, release at launch.
- The beta client is installed at `World of Warcraft\_classic_beta_`. The probe is
  installed there and enabled.

## Open questions (maintainer to decide)

None block work; drafts ship and get retuned ([decisions.md](decisions.md) →
*Maintainer-gated content ships as a DRAFT*).
- **Phrase wording (#62):** the DRAFT in
  [phrase.md §9](specs/phrase.md#9-draft-phrase-set-draft): ship or redirect? Keep the
  alcohol words ("a mug of ale", "spiced cider")? Keep "the murlocs" or stay generic?
- **Cosmetic catalog (#63):** the DRAFT in
  [collection-cosmetics.md §9](specs/collection-cosmetics.md#9-draft-catalog-draft):
  set, names, thresholds (retuned once the inns are counted). Also: "every inn" = every
  inn your faction can use? Keep a zone seal when a patch adds an inn to that zone?
  Later: continent seals, a "home inn" reward, a badge kind? For the retune: a zone with
  no Continent above it is grouped under its World map, which counts toward the
  `continent` quill (#76).
- **Export (#64):** add `me.region` (Forever names are unique only per region)? Ever
  want an import or backup restore ([export.md → Open questions](specs/export.md#open-questions-maintainer))?

## Waiting on the maintainer in the client

Batched in #12; the open items are the unticked ones in
[platform-forever.md → Verification checklist](platform-forever.md#verification-checklist-needs-a-forever-client-beta-until-2026-10-21-or-launch-2026-11-04).
In short:
- **Any innkeeper:** talk to them (gossip, NPC ID, `IsResting()` inside the inn, the
  button's look on their dialog).
- **Solo, after login:** `/ledger debug`'s report ends `names two-part` (#80).
- **A second character in a party** (a second account or a friend with both AddOns):
  party and raid round-trips; with `/ledger debug` on, their HELLO shows as
  `got hello PARTY`, not `drop unresolved` (#75's follow-up); what
  `UnitFullName("partyN")` returns.
- **A guild:** guild round-trip and roster names/GUIDs.
- **One dungeon run in a group:** addon messages in instances and encounters.
- **Copy out** an export string (once the Share window exists).

## Waiting on the maintainer's accounts

- GitHub 2FA: ✅ on. Account email settings stay as they are
  ([decisions.md](decisions.md), 2026-09-28).
- **Now (one checkbox):** Settings → Environments → `release` → uncheck *Allow
  administrators to bypass configured protection rules*, so each publish needs an
  approval even from the maintainer's account (#81; an agent's attempt was refused by
  its permission guard).
- **At release time, not before:** the maintainer creates the CurseForge and Wago
  accounts with 2FA from the start, then the project pages (send the project IDs for
  the TOC) and upload tokens, entered only into the `release` environment as
  `CF_API_TOKEN` and `WAGO_API_TOKEN`
  ([security-checklist.md → Before the packager lands](security-checklist.md#before-the-packager-lands-first-tag),
  [CONTRIBUTING.md → Releasing](../CONTRIBUTING.md#releasing)).

## Follow-ups

- **Revisit once in groups (#12):** forward server-clock jumps in `SyncSchedule`; hidden
  addon traffic from other AddOns counted as `hidden` drops; group-map rescan budget
  (#54 review); a dropped `C_Timer.After`; export build time and the ~5 MB AceSerializer
  keeps after an opted-in export.
- **Weekly reset fallback:** the beta (region 90) resets Tuesday 16:00 UTC, an hour off
  the US row that `Core.RESET_FALLBACK` falls back to. It's only used if the API fails;
  fill the live regions' rows after launch.
- **Code tidy (low):** `isInt` / name allow-lists are copied across `Collection`,
  `Cosmetics` and `Export`; `Phrase` could assert `Ledger.LIMITS` numbers at load and
  require a space before `{w}` in templates (#62 review nits).
- Publish `Data/Inns`, `Data/Phrases` and `Data/Cosmetics` as a generated reference for
  export consumers; needs the inn data.
- **Before the first tag:** write `CHANGELOG.md`'s `## vX.Y.Z` notes (the release check
  requires them), add the TOC IDs (#81), and answer the phrase and catalog questions:
  IDs freeze at the first public release. Whether CurseForge and Wago map interface
  `16001` to a Forever game version is unverified until the first upload; the
  packager's `-g` overrides it if not.
- **`UI/Book`:** the book's in-game help says what sync shares, in the README's words
  (decisions.md, 2026-09-28, guild sync disclosure).
- Export golden string (`GOLDEN_F`): regenerate if a library or interpreter change breaks
  it while its decode still matches, and say so in the PR.
- `Ledger`'s load-time cap pass is quadratic on a tampered file (40 000 entries ≈ 4 s);
  batch evictions if it ever matters.
- Harness: a ChatThrottleLib-callback option for `"defer"` mode would make the raid run
  more realistic.
- CI pins only top-level rocks; pin dependencies if an upstream release breaks CI.
- Delete GitHub's default labels (maintainer call: deletion).
- `decisions.md` is ~1 100 lines: early October, move September entries to
  `docs/archive/decisions-2026-09.md` with an index line.
- Move [kickoff.md](kickoff.md) to `docs/archive/` once v1 ships.
