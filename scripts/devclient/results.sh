#!/bin/sh
# Dev harness (#139): reports the last tour and crops its screenshots into an out folder
# (outside the repo: the results name the character).
# Usage: sh scripts/devclient/results.sh <out folder> [client folder]
# Needs lua (5.1) on PATH; crops with Windows PowerShell.
set -eu
out=${1:?out folder, e.g. a scratch directory}
client=${2:-${ILDEV_CLIENT:-"C:/Program Files (x86)/World of Warcraft/_classic_beta_"}}
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$out"
sv=
for f in "$client"/WTF/Account/*/SavedVariables/ILDev.lua; do
  [ -f "$f" ] || continue
  if [ -z "$sv" ] || [ "$f" -nt "$sv" ]; then sv=$f; fi
done
[ -n "$sv" ] || { echo "results: no ILDev saved variables under $client/WTF (reload once)" >&2; exit 1; }
lua "$here/read.lua" "$sv" "$client/Screenshots" "$out"
if [ -s "$out/crops.txt" ]; then
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$here/crop.ps1" 2>/dev/null || echo "$here/crop.ps1")" \
    -List "$(cygpath -w "$out/crops.txt" 2>/dev/null || echo "$out/crops.txt")"
fi
