#!/bin/sh
# Dev harness (#139): copies the working tree's AddOn and the ILDev harness into a WoW
# client, with a tour request, then checks the copy. The game reads the files on /reload
# (a new AddOn folder or a changed TOC needs a client restart).
# Usage: sh scripts/devclient/deploy.sh [-t tours] [-w seconds] [client folder]
#   -t  comma-separated tours from scripts/devclient/tours (default: book)
#   -w  watch mode's reload interval, 30 s or more (default 60; watch is switched on in game)
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
here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo=$(CDPATH='' cd -- "$here/../.." && pwd)
addons="$client/Interface/AddOns"

# Everything is checked before anything in the client changes.
[ -d "$addons" ] || { echo "deploy: no AddOns folder at $addons" >&2; exit 1; }
case $watch in ''|*[!0-9]*) echo "deploy: -w takes whole seconds" >&2; exit 2 ;; esac
[ "$watch" -ge 30 ] || { echo "deploy: -w must be 30 or more" >&2; exit 2; }
list=$(printf '%s' "$tours" | tr ',' ' ')
[ -n "$list" ] || { echo "deploy: no tours" >&2; exit 2; }
for t in $list; do
  case $t in *[!A-Za-z0-9_-]*) echo "deploy: bad tour name $t" >&2; exit 2 ;; esac
  [ -f "$here/tours/$t.lua" ] || { echo "deploy: no tour $here/tours/$t.lua" >&2; exit 2; }
done

# A restart is needed for a new AddOn folder or any change to a TOC.
restart=
dest="$addons/InnkeepersLedger"
same() { [ -f "$2" ] && [ "$(tr -d '\r' < "$1")" = "$(tr -d '\r' < "$2")" ]; }
same "$repo/InnkeepersLedger.toc" "$dest/InnkeepersLedger.toc" || restart="the AddOn's TOC changed"
[ -d "$dest" ] || restart="InnkeepersLedger is a new AddOn folder"
same "$here/ILDev/ILDev.toc" "$addons/ILDev/ILDev.toc" || restart="ILDev's TOC changed"
[ -d "$addons/ILDev" ] || restart="ILDev is a new AddOn folder"

# The request, built and checked before it's installed.
id="$(date +%Y%m%d-%H%M%S)-$$"
tmp="$addons/.ILDev-Request.lua.tmp"
{
  echo "-- Written by scripts/devclient/deploy.sh."
  echo "ILDevRequest = {"
  echo "  id = \"$id\","
  echo "  watch = $watch,"
  echo "  tours = {"
  for t in $list; do
    echo "    (function()"
    cat "$here/tours/$t.lua"
    echo "    end)(),"
  done
  echo "  },"
  echo "}"
} > "$tmp"

# The AddOn: what the packager ships (the TOC, Libs, Data, UI, the top-level Lua files).
rm -rf "$dest"
mkdir -p "$dest"
cp -r "$repo/Libs" "$repo/Data" "$repo/UI" "$dest/"
rm -f "$dest/Libs/MANIFEST.sha256"
cp "$repo"/*.lua "$repo/InnkeepersLedger.toc" "$dest/"

# The harness, with this deploy's request.
rm -rf "$addons/ILDev"
cp -r "$here/ILDev" "$addons/"
mv "$tmp" "$addons/ILDev/Request.lua"

# Check the copy.
bad=0
for f in "$repo"/*.lua "$repo/InnkeepersLedger.toc"; do
  cmp -s "$f" "$dest/$(basename "$f")" || { echo "deploy: differs: $f" >&2; bad=1; }
done
for d in Libs Data UI; do
  diff -rq -x MANIFEST.sha256 "$repo/$d" "$dest/$d" >/dev/null ||
    { echo "deploy: differs: $d" >&2; bad=1; }
done
cmp -s "$here/ILDev/ILDev.lua" "$addons/ILDev/ILDev.lua" ||
  { echo "deploy: differs: ILDev.lua" >&2; bad=1; }
[ "$bad" = 0 ] || exit 1

echo "deployed request $id (tours: $tours) to $addons"
if [ -n "$restart" ]; then
  echo "RESTART the client: $restart (a /reload won't load it)."
else
  echo "In game: /reload (or wait for watch mode)."
fi
