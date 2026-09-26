# Third-party libraries

> **Summary:** which embedded libraries we use and why, the exact reviewed versions and
> file hashes, licenses, the security review and its findings, and how to upgrade.
> **Read when:** vendoring or upgrading anything in `Libs/`, touching sync transport or
> serialization, or answering "is this library safe / allowed".

## What we use and why

| Library | Version | Used for | Source |
|---|---|---|---|
| LibStub | 2 | library versioning (required by the others) | Ace3 Release-r1403 |
| CallbackHandler-1.0 | 8 | event callbacks (required by AceEvent, AceDB) | Ace3 Release-r1403 |
| AceAddon-3.0 | 13 | addon object, load/enable lifecycle | Ace3 Release-r1403 |
| AceEvent-3.0 | 4 | game event registration | Ace3 Release-r1403 |
| AceDB-3.0 | 33 | SavedVariables with defaults and profiles | Ace3 Release-r1403 |
| AceConsole-3.0 | 7 | slash command | Ace3 Release-r1403 |
| AceSerializer-3.0 | 5 | **export only** (our own outgoing data) | Ace3 Release-r1403 |
| ChatThrottleLib | 32 | rate-limited **sending** of addon messages | Ace3 Release-r1403 (`AceComm-3.0/ChatThrottleLib.lua`) |
| LibDeflate | 1.0.2 | **export only**: `CompressDeflate` | luarocks.org `libdeflate-1.0.2-1.src.rock` |

Not used: AceComm-3.0 (see *Findings* 1), AceGUI/AceConfig (UI is custom frames),
AceTimer (the client's `C_Timer` suffices), AceHook, AceLocale, AceBucket, AceTab,
LibDeflate's print/chat encoders (see *Findings* 4).

**Where they come from.** Ace3 is exported from the official WowAce Subversion repository
(`repos.wowace.com/wow/ace3/tags/Release-r1403`, last changed 2026-08-12). LibDeflate
comes from the source rock on luarocks.org (sha256
`e977973d521bce4d0f854681bc55071e270dd63284ab921e5785fa261140f6bb`).

## Reviewed files (sha256)

Vendored copies must match these exactly. Paths are relative to the Ace3 tag root or the
LibDeflate rock's `LibDeflate/` folder.

```
26401bc42c26d1d1b6f7ad9410aa464edcbe4d32d74ebadeeecd8c0110236f7d  ace3:LibStub/LibStub.lua
e37ca6e5cd4e39c69d600468c8fe2a425b8a4d50023d9903fa3dc7aeeae1561f  ace3:CallbackHandler-1.0/CallbackHandler-1.0.lua
9310765c5310a395652e60a04f378e836785deb6f0b7181a448c74751d6f0185  ace3:CallbackHandler-1.0/CallbackHandler-1.0.xml
9aaec858b04820b597155b040dd76ef0d6e8e4f0707e54630001bcfe68497307  ace3:AceAddon-3.0/AceAddon-3.0.lua
b9820071648e42f9167882ef2a08602644a301cefd5d7e57c82aa36ca1439259  ace3:AceAddon-3.0/AceAddon-3.0.xml
928729c0edae955407778463d345baa0e59fc8f6f6ad53877b6243e0f225da4e  ace3:AceEvent-3.0/AceEvent-3.0.lua
9a9c0b14a8eda4509d45422cb1ac065ba9165879ef291816f1689bf6be3bcbc4  ace3:AceEvent-3.0/AceEvent-3.0.xml
9d6659c3de31c931a249c5ce35839939e43c07e5118c1660c30b4a5234e586ce  ace3:AceDB-3.0/AceDB-3.0.lua
5b3873c68d76a76fb52bbb9232d4d63b13f99cda5b3f95c86205d8022786d184  ace3:AceDB-3.0/AceDB-3.0.xml
3372abc50efcfa4f643bf7c2f3254de19327d28e2040997d672f94d1845a5499  ace3:AceConsole-3.0/AceConsole-3.0.lua
19b0494a1f16f9d7147cf0e0f601aa4e0fbaa61490037af0e8969fabcc2f185b  ace3:AceConsole-3.0/AceConsole-3.0.xml
874fabab25ee5c5c08599e37744abe9205659b6f33c59250bccbfbf4fe5d0a41  ace3:AceSerializer-3.0/AceSerializer-3.0.lua
7d578832f12c3f4eb1311e1dbebb2156950202d61aa6c299f3fd05a6ab69d496  ace3:AceSerializer-3.0/AceSerializer-3.0.xml
3491b6c98cae1634a9f0494b436e86df1632309fb68181c25240b53c4d86dde8  ace3:AceComm-3.0/ChatThrottleLib.lua
afe050a430bafdbca7da69d95897751239f4fab415784a419a3cdc2519eee9b2  ace3:LICENSE.txt
76f2114e527c2be1ac5cf768a68084946a3e19f63592834640020b7c9b5a450f  libdeflate-1.0.2:LibDeflate.lua
acbecf8578f4febb766a1dd0217336e2e7ec19e66d13c907e38b01b1b727d7df  libdeflate-1.0.2:LICENSE.txt
```

## Licenses

- **Ace3:** BSD-style. Embedding is allowed; keep the copyright notice and license text
  with the files. Redistributing Ace3 **as a stand-alone package** is prohibited without
  the Ace3 team's permission, so we ship it only embedded in the AddOn.
- **LibStub, ChatThrottleLib:** public domain.
- **LibDeflate:** zlib license. Its header credits two GPLv2 projects for its custom
  codec and 6-bit (print) encoding. We use only `CompressDeflate`, whose credited sources
  are zlib/puff (zlib license), and do our own export encoding.
- Our own code stays MIT. Each vendored library keeps its license file next to it.

## Review (2026-09-26)

Method: read the code paths we use; searched all files for dynamic code, outbound or
account-affecting APIs, combat APIs, hooks and URLs; ran hostile inputs on Lua 5.1.

- **Plain source.** Only Lua and XML, no compiled or obfuscated code.
- **No dynamic code on data.** No `loadstring`/`setfenv` in any file we ship. (The only
  `loadstring` in Ace3 is the stand-alone Ace3 console, which we don't include.)
- **Nothing sends on its own.** ChatThrottleLib sends only what an addon hands it. Its
  secure hooks on the send functions only measure traffic volume for throttling.
- **No combat data, purchases, mail, invites or settings changes.**
- **URLs** appear only in comments and XML schema namespaces (the policy guard excludes
  `Libs/`).
- **Hostile input (Lua 5.1):** AceSerializer rejected garbage, truncated data and 20,000
  levels of nesting without crashing and kept code-like strings as plain data. LibDeflate
  returned nil on garbage.

### Findings that shape our design

1. **AceComm reassembles multi-part messages with no size limit**, before the receiving
   addon sees them, and never expires stale partial data. Receiving through AceComm would
   let any sender make us buffer unbounded data. → Sync registers its own prefix and
   receives `CHAT_MSG_ADDON` directly with a byte cap; ChatThrottleLib is used only to
   send. ([architecture.md → Sync protocol](architecture.md))
2. **AceSerializer returns `inf`, `-inf`, `NaN`, hex numbers and floats**, plus duplicate
   keys (last wins) and extra top-level values. `NaN` fails every comparison, so a naive
   "not in the future" check passes it. → Sync uses its own fixed-format codec; any
   numeric field must be a finite integer in range.
3. **LibDeflate has no output limit.** A 27 KB payload inflated to 20 MB (722:1) in
   0.7 s. → Sync is never compressed, and nothing decompresses peer data in v1.
4. **Newest copy wins at runtime.** LibStub loads the highest version of each library
   across all installed AddOns, so another AddOn's newer copy may replace ours. →
   Security-relevant parsing lives in our own modules, never in a shared library.

## Vendoring and upgrades

- Libraries are committed under `Libs/` (not fetched at package time), so what ships is
  what was reviewed. `Libs/MANIFEST.sha256` lists every vendored file, and CI fails if
  any file differs from it.
- **Check:** `scripts/check-libs.sh` verifies every manifest hash and fails if any file
  under `Libs/` isn't in the manifest. `.gitattributes` marks `Libs/**` as `-text` so
  Git never changes line endings (and so hashes) on any platform.
- **`Libs/embeds.xml` is ours**, not upstream: it sets the library load order (see the
  table above). It's listed in the manifest like the vendored files, so any change to
  it is deliberate and the unlisted-file check stays strict. After editing it, regenerate
  its manifest line in the `<hash>  <path>` form (two spaces; `sha256sum` on Windows
  writes ` *<path>`, which the check rejects).
- **To upgrade:** fetch the new version from the sources above, diff it against the
  current copy, repeat the review (search + hostile-input run) on changed code paths,
  update the table, hashes and manifest here, and add a decision-log entry. One library
  per PR.
