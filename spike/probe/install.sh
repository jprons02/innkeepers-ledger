#!/bin/sh
# Throwaway (#12): copies the probe and the working-tree AddOn into a WoW client's
# AddOns folder. The installed copy's TOC gets INTERFACE instead of the placeholder.
# Usage: sh spike/probe/install.sh "<client folder>" [interface]
set -eu
client=${1:?client folder, e.g. "C:/Program Files (x86)/World of Warcraft/_classic_beta_"}
interface=${2:-16001}
repo=$(cd "$(dirname "$0")/../.." && pwd)
addons="$client/Interface/AddOns"
mkdir -p "$addons"

rm -rf "$addons/!ILProbe"
cp -r "$repo/spike/probe/!ILProbe" "$addons/"
sed -i "s/^## Interface: .*/## Interface: $interface/" "$addons/!ILProbe/!ILProbe.toc"

dest="$addons/InnkeepersLedger"
rm -rf "$dest"
mkdir -p "$dest"
cp -r "$repo/Libs" "$repo/Data" "$repo/UI" "$dest/"
cp "$repo"/*.lua "$dest/"
sed "s/^## Interface: .*/## Interface: $interface/" "$repo/InnkeepersLedger.toc" > "$dest/InnkeepersLedger.toc"
echo "installed into $addons (interface $interface)"
