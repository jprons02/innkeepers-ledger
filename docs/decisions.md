# Decisions

> **Summary:** the decision log. Settled decisions with the reason for each and the
> options rejected, dated, **newest first**.
> **Read when:** a question may already be settled; before proposing a change in
> direction or re-proposing a rejected option.

**Don't re-litigate these.** If new information changes one, add a new dated entry at the
top that supersedes it (and links it) rather than editing history.

---

### 2026-11-04 (later) — The walk moves to the live client; the offline renderer is dropped

The beta closed on 2026-10-21 before the innkeeper walk (#12): the probe's log was last
written 2026-10-12, and `Data/Inns` still holds one inn. The maintainer chose to run the
probe in the **live client** instead: it was installed in `_forever_` on 2026-11-04
(from `spike/12-probe`, with `dev`'s AddOn), so his play logs every innkeeper he talks
to, and an agent fills `Data/Inns` from the log
([platform-forever.md](platform-forever.md), [testing.md](testing.md#testing-posture)).
The beta's NPC and map IDs count as unverified in live until the probe logs them there.

**The offline renderer** (the stub's frames drawn in a browser, for the gap between the
beta and launch; 2026-10-10) **is dropped:** the gap is over and the live client serves
the harness. **Rejected:** *#157's notes as the walk's tool* (they wait for the release
after launch, and the probe already logs innkeepers); *hand-collected IDs* (slower, and
error-prone).

---

### 2026-11-04 — Data tables published as generated JSON; noting unknown innkeepers waits

The maintainer's call today, on launch day: **publish `Data/*` as a generated JSON file
before the first tag** (#156), so an export consumer can render inn, zone, seal,
cosmetic and phrase text without reading Lua (the promise in
[export-format.md → Notes](export-format.md#notes)). **Noting innkeepers the AddOn
doesn't know, and carrying the notes in the export (#157), ships in the first release
after launch**, not before the first tag: a launch-week scope guard.

How the JSON is built ([specs/data-json.md](specs/data-json.md)):
- **One file, `docs/data/forever.json`,** written by `scripts/data-json.lua` and
  committed; CI's `busted` job runs `--check` and fails when it differs from the Lua. It
  sits under `docs`, which never ships, and names no consumer (like the export string).
- **Only the records the AddOn keeps,** read through `Collection`, `Cosmetics` and
  `Phrase` after they bind the data: effective `complete` marks, zone seals listed in
  `cosmetics`. A rejected record fails the build rather than dropping out quietly.
- **Versioned by `schema` alone** (1). Fields are only added; a change of meaning or type
  bumps it. No AddOn version, date or hash in the file, so the same data gives the same
  bytes.
- **Integer keys become decimal-string keys, no arrays;** keys sorted (numbers
  numerically, strings by byte); one record per line; `\"`, `\\` and `\u00xx` the only
  escapes; malformed UTF-8 fails the build.

**Rejected:** *a top-level `data/` folder* (on Windows and macOS it's the shipped
`Data/`); *`Data/forever.json` with its own ignore line* (one forgotten line ships it);
*the raw `ns.Data` tables* (records the AddOn rejects, raw marks, no zone seals);
*skipping rejected records*; *JSON arrays for categories and voices* (0- against 1-based);
*`null` or `"neutral"` for absent fields*; *a version or date in the file* (the check
would always fail); *a JSON library* (a new dependency for about 100 lines); *a new CI
job* (a new required check for one step); *`git diff --exit-code` after regenerating*
(mutates the checkout).

---

### October 2026 (archived)

Every entry dated 2026-10-01 to 2026-10-12 is in
[archive/decisions-2026-10.md](archive/decisions-2026-10.md), unchanged apart from link
paths and still in force unless an entry above supersedes it. Titles, newest first, for
references that cite them by name:

- 2026-10-12 — The conjunction buttons stay 124 wide: measured
- 2026-10-11 (later) — What the harness's first runs settled
- 2026-10-11 — The inn page sizes to its text; the conjunction strip gets wider buttons
- 2026-10-10 — Agents see the UI through a dev harness in the client
- 2026-10-09 (later) — The pages' covers meet in the middle as the spine
- 2026-10-09 — Both book pages use `Spellbook-Page-1`, clear of its cover
- 2026-10-08 — One copy of the place-name rule; `isInt` stays per module
- 2026-10-08 — CI jobs have timeouts, and apt retries a stalled mirror
- 2026-10-07 — Names with hidden characters or malformed UTF-8 are rejected
- 2026-10-07 — Completeness fails closed on any excluded record
- 2026-10-07 — A month's decisions move to the archive once the month is over
- 2026-10-07 — CI runners pinned to `ubuntu-24.04`
- 2026-10-07 — Composer: lists, one line at a time, core frame API only
- 2026-10-07 — Partial atlas: place rules count only places marked complete
- 2026-10-06 — Book: a pure BookView, one named frame for ESC, a GUID-keyed record, the share mark at build, refresh through `onEntries`
- 2026-10-06 — UI/Book: the parchment ledger
- 2026-10-06 — No inks: one realistic ink for every signature
- 2026-10-06 — Phrase voices; free text stays out
- 2026-10-05 — Sign: a pure SignFlow, the button at every known innkeeper, reasons on click, no sitting or combat check
- 2026-10-02 — Players sign the inn's guestbook; the AddOn keeps the name "ledger"
- 2026-10-01 — On a two-part client, guild keys must be two words too
- 2026-10-01 — Distribution pages: CurseForge and Wago, no outbound links
- 2026-10-01 — The BigWigs packager, pinned; releases built and checked in CI

---

### September 2026 (archived)

Every entry dated 2026-09-25 to 2026-09-30 is in
[archive/decisions-2026-09.md](archive/decisions-2026-09.md), unchanged apart from link
paths and still in force unless an entry above supersedes it. Titles, newest first, for
references that cite them by name:

- 2026-09-30 — One read of our own name; the name form shows in `/ledger debug`
- 2026-09-30 — A zone with no Continent above it is grouped under its World map
- 2026-09-30 — Two-part names key as the bare sender form
- 2026-09-30 — Forever beta results: modern API, two-part names, zones without continents
- 2026-09-28 — Account email settings stay as they are
- 2026-09-28 — Guild sync stays on by default; players are told what it shares
- 2026-09-28 — Published exports show other travelers only as counts
- 2026-09-28 — Security audit: repository hardening
- 2026-09-28 — Maintainer-gated content ships as a DRAFT and doesn't block merge
- 2026-09-28 — Export v1: what the draft left open
- 2026-09-27 — Collection: places, keys and faction totals
- 2026-09-27 — Cosmetics: IDs, derived unlocks that are never taken away, seals on signing
- 2026-09-27 — Phrase grammar, ID scheme and rendering
- 2026-09-27 — Phrase content rules
- 2026-09-27 — Group map details: realm form, our own name, rescan on a miss
- 2026-09-27 — Sync send: timer, clock and hold choices where the spec was silent
- 2026-09-27 — Sync receive: fail-closed choices where the spec was silent
- 2026-09-27 — Group senders resolve through our own unit scan, never `UnitGUID(sender)`
- 2026-09-27 — SyncSchedule: failed sends keep their gates; forward clock jumps wait for #12
- 2026-09-27 — Debug toggle wording: keep it as written
- 2026-09-27 — Sync glue: a pure send schedule, logical channels and a gated large reply
- 2026-09-27 — Guild HELLO interval
- 2026-09-27 — Debug log: off by default, session only, no peer strings
- 2026-09-27 — Ledger orders by bytes, keeps sorted indexes, and tightens two inputs
- 2026-09-27 — Coverage floors on pure modules, a doc-link check, and local test runs
- 2026-09-27 — Re-signing follows the game's weekly reset (supersedes the Friday 10:00 UTC entry below)
- 2026-09-27 — Re-signing an inn: once per week, resetting Friday 10:00 UTC
- 2026-09-27 — Peer-data rate limits and time window
- 2026-09-27 — Ledger storage: caps, eviction and SavedVariables shape
- 2026-09-27 — Sync wire format v1 and digest
- 2026-09-27 — AddOn list blurb names both halves of the AddOn
- 2026-09-27 — Profile site trust: showcase only, no profile key in the v1 export
- 2026-09-27 — Profile website: after v1, a separate project, reached by one paste
- 2026-09-27 — Keep the inn ledger after a pivot review
- 2026-09-27 — Sync may read combat state, and players are told
- 2026-09-26 — Security checks: forbidden-API guard on every PR, review before every release
- 2026-09-26 — CI: own toolchain install, and the library manifest pinned to the review doc
- 2026-09-26 — Scaffold conventions: embeds.xml in the manifest, pure modules enforced twice
- 2026-09-26 — Work is queued as GitHub issues written for a cold start
- 2026-09-26 — Vendor a reviewed, minimal set of libraries
- 2026-09-26 — Sync: own receive handler and codec, single messages, no compression
- 2026-09-26 — Export uses standard base64
- 2026-09-26 — Sender identity is resolved per channel; unresolved senders are dropped
- 2026-09-26 — Branch protection on `main` and `dev` (supersedes part of the branch-flow entry below)
- 2026-09-26 — Context docs as a map-driven tree
- 2026-09-26 — Autonomous build loop with maintainer gates
- 2026-09-26 — Test standard: busted + stubbed WoW API, hostile peer data
- 2026-09-26 — Branch flow: feature branches → dev → main
- 2026-09-26 — No spending without a named purchase; free beta route by default
- 2026-09-25 — Target WoW: Forever first
- 2026-09-25 — Inns only in v1
- 2026-09-25 — Canned phrases, not free text
- 2026-09-25 — Sync scope: grouped-with + guild by default; global opt-in
- 2026-09-25 — Accept only a sender's own signatures
- 2026-09-25 — Cosmetics are earned by play, never paid or gated
- 2026-09-25 — Generic, documented export string
- 2026-09-25 — Open source under MIT
