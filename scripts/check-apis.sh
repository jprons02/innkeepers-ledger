#!/bin/sh
# Fail if our shipped code uses an API it must not (docs/security-checklist.md).
# Scans every tracked .lua and .xml outside Libs/, spec/ and scripts/ (the packager drops
# spec/ and scripts/), plus Libs/embeds.xml (ours; a <Script> in it could run code).
# Comments are scanned too, so don't name a forbidden API even in a comment; reword it.
# Each rule lists the only files allowed to use its names ("-" means none). Widening an
# allow-list needs a decision-log entry (docs/decisions.md). Fails closed: a file that
# can't be read is a failure. Runs from any directory.
set -u
set -f

cd "$(dirname "$0")/.." || exit 1
status=0
nl='
'

# Tracked and untracked-but-not-ignored files; a force-added ignored file is tracked, so
# it's scanned too. Git quotes names with unusual characters (non-ASCII, quotes,
# backslashes, control characters); those would slip past the extension filter, so any
# quoted name is a failure.
listing=$(git -c core.quotePath=true ls-files -co --exclude-standard) || {
  echo "check-apis: FAIL: git ls-files failed." >&2
  exit 1
}
quoted=$(printf '%s\n' "$listing" | grep '^"' || true)
if [ -n "$quoted" ]; then
  echo "check-apis: FAIL: file names may only use plain ASCII characters:" >&2
  printf '%s\n' "$quoted" | sed 's/^/  /' >&2
  status=1
fi
files=$(printf '%s\n' "$listing" | grep -iE '\.(lua|xml)$' |
  grep -vE '^(Libs|spec|scripts)/' | sort)
files="$files${files:+$nl}Libs/embeds.xml"

# label | allowed files | names
# A name matches as a whole word, also after "." or ":" (so aliases like CI.SendChatMessage
# match). Dots in a name are literal. "re:<ERE>" is used as is.
# "combat state" is only whether we're in combat, never combat data, and only in Sync.lua
# (docs/decisions.md, 2026-09-27: "Sync may read combat state, and players are told").
# The "combat data" rule stays closed everywhere.
# "general purpose decoders" keeps every deserializer, inflater and decoder of the vendored
# libraries out of shipped code: nothing we ship reads an export string or any other
# serialized or compressed data (docs/decisions.md, 2026-09-28: "Export v1: what the draft
# left open"). The test-only decoder lives in spec/. CreateCodec is listed because the codec
# it returns has a Decode method. The client's own C_EncodingUtil namespace (inflate, base64,
# CBOR and JSON readers) is listed too, with its decoders by name so a cached alias is
# caught. Like every rule here it's a guard against honest
# mistakes: a computed lookup (lib["Decompress" .. "Deflate"]) isn't caught; review is.
rules='dynamic code|-|loadstring loadfile dofile setfenv getfenv RunScript ConsoleExec re:(^|[^A-Za-z0-9_.:])load([[:space:]]*[(,);}"[-]|[[:space:]]*$)
global lookup by name|-|_G getglobal setglobal
combat data|-|CombatLogGetCurrentEventInfo COMBAT_LOG_EVENT COMBAT_LOG_EVENT_UNFILTERED C_CombatLog C_DamageMeter UnitHealth UnitHealthMax UnitPower UnitPowerMax UnitAura C_UnitAuras UnitDetailedThreatSituation UnitThreatSituation UnitAffectingCombat UNIT_COMBAT
combat state|Sync.lua|InCombatLockdown PLAYER_REGEN_DISABLED PLAYER_REGEN_ENABLED
chat and social sending|-|SendChatMessage ChatEdit_SendText BNSendWhisper BNSendGameData BNSendFriendInvite C_BattleNet C_Club SendMail C_Mail C_FriendList AddFriend AddIgnore SendWho
hooks|-|hooksecurefunc HookScript securecall issecurevariable ChatFrame_AddMessageEventFilter
macros and bindings|-|RunMacro RunMacroText CreateMacro EditMacro DeleteMacro C_Macro SecureActionButtonTemplate macrotext SetBinding SetBindingClick SetBindingMacro SetBindingSpell SetBindingItem SetOverrideBinding SetOverrideBindingClick SaveBindings
gossip and innkeeper actions|-|SelectGossipOption SelectOption SelectOptionByIndex ConfirmBinder
account and group actions|-|InviteUnit UninviteUnit LeaveParty PromoteToLeader GuildInvite GuildUninvite GuildLeave GuildDisband GuildSetLeader GuildPromote GuildDemote GuildRosterSetPublicNote GuildRosterSetOfficerNote C_GuildInfo.Invite Uninvite RemoveFromGuild SetCVar SetCVarBitfield ReloadUI Logout Quit ForceQuit C_StorePublic C_WowTokenPublic DeleteCursorItem UseContainerItem BuyMerchantItem InitiateTrade AcceptTrade DisableAddOn EnableAddOn DisableAllAddOns EnableAllAddOns
general purpose decoders|-|Deserialize DecompressDeflate DecompressDeflateWithDict DecompressZlib DecompressZlibWithDict DecodeForPrint DecodeForWoWAddonChannel DecodeForWoWChatChannel CreateCodec C_EncodingUtil DecompressString DecodeBase64 DeserializeCBOR DeserializeJSON
addon messages and channels|Sync.lua Libs/embeds.xml|SendAddonMessage SendAddonMessageLogged RegisterAddonMessagePrefix CHAT_MSG_ADDON CHAT_MSG_ADDON_LOGGED BN_CHAT_MSG_ADDON ChatThrottleLib AceComm SendCommMessage RegisterComm JoinChannelByName JoinPermanentChannel JoinTemporaryChannel LeaveChannelByName'

while IFS='|' read -r label allow names; do
  alt=
  IFS=' '
  for n in $names; do
    case $n in
      re:*) p=${n#re:} ;;
      *) p="(^|[^A-Za-z0-9_])$(printf '%s' "$n" | sed 's/\./\\./g')([^A-Za-z0-9_]|$)" ;;
    esac
    alt="$alt${alt:+|}$p"
  done
  IFS=$nl
  for f in $files; do
    case " $allow " in *" $f "*) continue ;; esac
    hits=$(grep -nE "$alt" "$f")
    rc=$?
    if [ "$rc" -gt 1 ]; then
      echo "check-apis: FAIL: cannot read $f" >&2
      status=1
    elif [ -n "$hits" ]; then
      echo "check-apis: FAIL: $label in $f (allowed only in: $allow):" >&2
      printf '%s\n' "$hits" | sed 's/^/  /' >&2
      status=1
    fi
  done
done <<EOF
$rules
EOF

if [ "$status" -eq 0 ]; then
  echo "check-apis: OK: $(printf '%s\n' "$files" | grep -c .) files, no forbidden APIs."
fi
exit "$status"
