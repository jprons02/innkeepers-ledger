#!/bin/sh
# Fail if our shipped code uses an API it must not (docs/security-checklist.md).
# Scans every .lua and .xml outside Libs/, spec/ and scripts/, plus Libs/embeds.xml
# (ours; a <Script> in it could run code). Comments are scanned too, so don't name a
# forbidden API even in a comment; reword it.
# Each rule lists the only files allowed to use its names ("-" means none). Widening an
# allow-list needs a decision-log entry (docs/decisions.md). Runs from any directory.
set -u

cd "$(dirname "$0")/.." || exit 1
status=0

files=$(find . \( -path ./Libs -o -path ./spec -o -path ./scripts -o -path ./.git \
  -o -path ./.luarocks -o -path ./lua_modules -o -path ./.release \) -prune \
  -o -type f \( -name '*.lua' -o -name '*.xml' \) -print | sed 's#^\./##' | sort)
files="$files
Libs/embeds.xml"

# label | allowed files | names (a name matches as a whole word; dots are literal)
rules='dynamic code|-|loadstring loadfile dofile load( setfenv getfenv RunScript
global lookup by name|-|_G getglobal setglobal
combat data|-|CombatLogGetCurrentEventInfo COMBAT_LOG_EVENT COMBAT_LOG_EVENT_UNFILTERED C_CombatLog C_DamageMeter UnitHealth UnitHealthMax UnitPower UnitPowerMax UnitAura C_UnitAuras UnitDetailedThreatSituation UnitThreatSituation UnitAffectingCombat InCombatLockdown PLAYER_REGEN_DISABLED PLAYER_REGEN_ENABLED UNIT_COMBAT
chat and social sending|-|SendChatMessage C_ChatInfo.SendChatMessage BNSendWhisper BNSendGameData C_BattleNet C_Club.SendMessage SendMail C_Mail
hooks|-|hooksecurefunc HookScript securecall issecurevariable
account and group actions|-|InviteUnit C_PartyInfo.InviteUnit C_PartyInfo.LeaveParty LeaveParty GuildInvite GuildUninvite C_GuildInfo.Invite C_GuildInfo.Uninvite C_GuildInfo.RemoveFromGuild SetCVar C_CVar.SetCVar ReloadUI Logout Quit ForceQuit C_StorePublic C_WowTokenPublic DeleteCursorItem UseContainerItem C_Container.UseContainerItem BuyMerchantItem InitiateTrade AcceptTrade
addon messages|Sync.lua Libs/embeds.xml|SendAddonMessage C_ChatInfo.SendAddonMessage SendAddonMessageLogged C_ChatInfo.SendAddonMessageLogged RegisterAddonMessagePrefix C_ChatInfo.RegisterAddonMessagePrefix CHAT_MSG_ADDON ChatThrottleLib'

while IFS='|' read -r label allow names; do
  # A name ending in "(" matches only as a call ("load(" but not "load order").
  alt=$(printf '%s\n' $names | sed -e 's/\./\\./g' \
    -e 's/($/[[:space:]]*\\(/;t' -e 's/$/([^A-Za-z0-9_]|$)/' | paste -sd '|' -)
  pattern="(^|[^A-Za-z0-9_.])($alt)"
  for f in $files; do
    case " $allow " in *" $f "*) continue ;; esac
    hits=$(grep -nE "$pattern" "$f" || true)
    if [ -n "$hits" ]; then
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
