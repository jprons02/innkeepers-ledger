#!/bin/sh
# Dev harness (#139): reports the last tour and crops its screenshots into an out folder
# (outside the repo: the results name the character). If the same deploy ran a tour before
# that one (the book tour at login, then `/ildev run composer`), it's reported first, into
# <out folder>/earlier.
# Usage: sh scripts/devclient/results.sh <out folder> [client folder]
# Needs lua (5.1) on PATH; crops with Windows PowerShell.
set -eu
out=${1:?out folder, e.g. a scratch directory}
client=${2:-${ILDEV_CLIENT:-"C:/Program Files (x86)/World of Warcraft/_classic_beta_"}}
here=$(cd "$(dirname "$0")" && pwd)
# A reused out folder keeps nothing of an older report's earlier run.
rm -rf "$out/earlier"
mkdir -p "$out/earlier"
rm -f "$out/crops.txt"
sv=
for f in "$client"/WTF/Account/*/SavedVariables/ILDev.lua; do
  [ -f "$f" ] || continue
  if [ -z "$sv" ] || [ "$f" -nt "$sv" ]; then sv=$f; fi
done
[ -n "$sv" ] || { echo "results: no ILDev saved variables under $client/WTF (reload once)" >&2; exit 1; }
crop() {
  if [ -s "$1/crops.txt" ]; then
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$here/crop.ps1" 2>/dev/null || echo "$here/crop.ps1")" \
      -List "$(cygpath -w "$1/crops.txt" 2>/dev/null || echo "$1/crops.txt")"
  fi
}
lua "$here/read.lua" "$sv" "$client/Screenshots" "$out/earlier" earlier
crop "$out/earlier"
rmdir "$out/earlier" 2>/dev/null || true # empty: no earlier run
lua "$here/read.lua" "$sv" "$client/Screenshots" "$out"
crop "$out"
