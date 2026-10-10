#!/bin/sh
# Dev harness (#139): copies the working tree's AddOn and the ILDev harness into a WoW
# client, with a tour request, then checks the copy. The game reads the files on /reload
# (a new AddOn folder or a new TOC file needs a client restart).
# Usage: sh scripts/devclient/deploy.sh [-t tours] [-w seconds] [client folder]
#   -t  comma-separated tours from scripts/devclient/tours (default: book)
#   -w  watch mode's reload interval in seconds (default 60; watch is switched on in game)
#   client folder defaults to $ILDEV_CLIENT, then the default beta install.
set -eu
tours=book
watch=60
while getopts t:w: opt; do
  case $opt in
    t) tours=$OPTARG ;;
    w) watch=$OPTARG ;;
    *) exit 2 ;;
  esac
done
shift $((OPTIND - 1))
client=${1:-${ILDEV_CLIENT:-"C:/Program Files (x86)/World of Warcraft/_classic_beta_"}}
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
addons="$client/Interface/AddOns"
[ -d "$addons" ] || { echo "deploy: no AddOns folder at $addons" >&2; exit 1; }
case $watch in ''|*[!0-9]*) echo "deploy: -w takes whole seconds" >&2; exit 2 ;; esac

restart=
[ -d "$addons/ILDev" ] || restart="ILDev is a new AddOn folder"
dest="$addons/InnkeepersLedger"
files() { grep -v '^#' "$1" | tr -d '\r'; }
if [ -f "$dest/InnkeepersLedger.toc" ] &&
  [ "$(files "$dest/InnkeepersLedger.toc")" != "$(files "$repo/InnkeepersLedger.toc")" ]; then
  restart="the TOC's file list changed"
fi
[ -d "$dest" ] || restart="InnkeepersLedger is a new AddOn folder"

# The AddOn: what the packager ships (the TOC, Libs, Data, UI, the top-level Lua files).
rm -rf "$dest"
mkdir -p "$dest"
cp -r "$repo/Libs" "$repo/Data" "$repo/UI" "$dest/"
rm -f "$dest/Libs/MANIFEST.sha256"
cp "$repo"/*.lua "$repo/InnkeepersLedger.toc" "$dest/"

# The harness, with this deploy's request.
rm -rf "$addons/ILDev"
cp -r "$here/ILDev" "$addons/"
id=$(date +%Y%m%d-%H%M%S)
req="$addons/ILDev/Request.lua"
{
  echo "-- Written by scripts/devclient/deploy.sh."
  echo "ILDevRequest = {"
  echo "  id = \"$id\","
  echo "  watch = $watch,"
  echo "  tours = {"
  IFS=,
  for t in $tours; do
    f="$here/tours/$t.lua"
    [ -f "$f" ] || { echo "deploy: no tour $f" >&2; exit 1; }
    echo "    (function()"
    cat "$f"
    echo "    end)(),"
  done
  echo "  },"
  echo "}"
} > "$req"

# Check the copy.
bad=0
for f in "$repo"/*.lua "$repo/InnkeepersLedger.toc"; do
  cmp -s "$f" "$dest/$(basename "$f")" || { echo "deploy: differs: $f" >&2; bad=1; }
done
for d in Libs Data UI; do
  diff -rq -x MANIFEST.sha256 "$repo/$d" "$dest/$d" >/dev/null || { echo "deploy: differs: $d" >&2; bad=1; }
done
[ "$bad" = 0 ] || exit 1

echo "deployed request $id (tours: $tours) to $addons"
if [ -n "$restart" ]; then
  echo "RESTART the client: $restart (a /reload won't load it)."
else
  echo "In game: /reload (or wait for watch mode)."
fi
