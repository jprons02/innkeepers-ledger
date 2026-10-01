#!/bin/sh
# Checks what the packager built before anything is uploaded (release.yml; the release
# review's items 12 and 13 in docs/security-checklist.md). Fails closed.
#   check-package.sh --tag <name> <zip>  a release build: also, ## Version is <name>.
#   check-package.sh --dry-run <zip>     a dry-run build.
#   check-package.sh --self-test         builds packages from this checkout and checks
#                                        that good ones pass and broken ones fail.
# The package must be:
#   1. one folder, InnkeepersLedger/, with plain file names (no "..", no absolute paths);
#   2. exactly the files the repo ships: the tracked files minus dotfiles and the
#      .pkgmeta ignore list (so no docs/, spec/, scripts/, .claude/, .github/ or
#      Libs/MANIFEST.sha256), nothing missing and nothing added;
#   3. every file byte-for-byte the checkout's, the TOC aside, and every library file
#      matching Libs/MANIFEST.sha256 (what ships is what was reviewed);
#   4. the TOC unchanged but for "## Version:", which is filled in and matches
#      [A-Za-z0-9._+-]{1,32} (docs/specs/export.md 3.5);
#   5. every file the TOC lists present; no URL in shipped .lua/.toc/.xml and no link or
#      site name in shipped text (README, LICENSE, CHANGELOG.md), outside Libs/ (policy).
# Runs from any directory; needs git, unzip, sha256sum and cmp.
set -u
set -f

cd "$(dirname "$0")/.." || exit 1
repo=$(pwd)
NAME=InnkeepersLedger
TOC=$NAME.toc
nl='
'
# Links, mail addresses and site names; scripts/check-release.sh uses the same pattern.
LINK_RE='(://|mailto:|www\.|[a-z0-9-]+\.(com|net|org|io|gg|ai|dev|app|co|me|tv|ly|us|uk|de|fr|eu|info|xyz|link|site|online|store|shop|gl|to|be|cc|ws|gift|blog)([^a-z0-9]|$))'

# Zip entry names that would extract outside the folder: absolute, "..", backslashes.
# Fails closed: if grep itself errors, every name is reported.
unsafe_names() {
  out=$(printf '%s\n' "$1" | LC_ALL=C grep -E '(^/|(^|/)\.\.(/|$)|\\)')
  case $? in
    0) printf '%s\n' "$out" ;;
    1) ;;
    *) printf '%s\n' "$1" ;;
  esac
}

# The tracked files the package should hold, one per line, sorted.
expected_files() {
  ignore=$(awk '
    /^ignore:[[:space:]]*$/ { on = 1; next }
    on && /^[^[:space:]#]/ { on = 0 }
    on && /^[[:space:]]+-[[:space:]]+/ { sub(/^[[:space:]]+-[[:space:]]+/, ""); sub(/[[:space:]]+$/, ""); print }
  ' .pkgmeta)
  git -c core.quotePath=true ls-files | LC_ALL=C grep -vE '(^|/)\.' |
    IGNORE=$ignore awk '
      BEGIN { n = split(ENVIRON["IGNORE"], ig, "\n") }
      {
        for (i = 1; i <= n; i++) {
          if (ig[i] != "" && ($0 == ig[i] || index($0, ig[i] "/") == 1)) { next }
        }
        print
      }' | LC_ALL=C sort
}

# Checks the package folder under $1 ($1/InnkeepersLedger). $2: the tag, or empty.
check_tree() {
  root=$1
  tag=$2
  st=0
  bad() {
    echo "check-package: FAIL: $1" >&2
    st=1
  }

  top=$(cd "$root" && LC_ALL=C ls -A)
  if [ "$top" != "$NAME" ]; then
    bad "the package must hold one folder, $NAME/ (found: $(printf '%s' "$top" | tr '\n' ' '))."
    return 1
  fi
  pkg=$root/$NAME

  odd=$(cd "$pkg" && LC_ALL=C find . -name '*[!A-Za-z0-9._-]*')
  if [ -n "$odd" ]; then
    bad "names in the package may only use A-Z a-z 0-9 . _ - :$nl$odd"
    return 1
  fi
  # Nothing but plain files and folders.
  others=$(cd "$pkg" && find . ! -type f ! -type d)
  if [ -n "$others" ]; then
    bad "the package holds links or special files:$nl$others"
    return 1
  fi

  actual=$(cd "$pkg" && find . -type f | sed 's|^\./||' | LC_ALL=C sort)
  want=$(cd "$repo" && expected_files)
  for path in docs spec scripts .claude .github Libs/MANIFEST.sha256 CLAUDE.md; do
    if [ -e "$pkg/$path" ]; then
      bad "$path is in the package."
    fi
  done
  extra=$(printf '%s\n' "$actual" | LC_ALL=C comm -23 - "$(tmpfile want "$want")")
  missing=$(printf '%s\n' "$want" | LC_ALL=C comm -23 - "$(tmpfile actual "$actual")")
  [ -n "$extra" ] && bad "files the repo doesn't ship:$nl$extra"
  [ -n "$missing" ] && bad "files missing from the package:$nl$missing"

  # 3. Bytes. Every shipped file but the TOC equals the checkout's.
  for f in $(printf '%s\n' "$actual" | LC_ALL=C comm -12 - "$(tmpfile want "$want")"); do
    [ "$f" = "$TOC" ] && continue
    cmp -s "$pkg/$f" "$repo/$f" || bad "$f differs from the checkout."
  done
  libs=0
  while read -r hash path; do
    case "$path" in Libs/*) ;; *) continue ;; esac
    libs=$((libs + 1))
    if [ ! -f "$pkg/$path" ]; then
      bad "$path (in Libs/MANIFEST.sha256) is missing."
    elif [ "$(sha256sum "$pkg/$path" | cut -d' ' -f1)" != "$hash" ]; then
      bad "$path doesn't match Libs/MANIFEST.sha256."
    fi
  done < "$repo/Libs/MANIFEST.sha256"
  [ "$libs" -gt 0 ] || bad "no '<hash>  Libs/<path>' lines read from Libs/MANIFEST.sha256."

  # 4. The TOC.
  if [ ! -f "$pkg/$TOC" ]; then
    bad "$TOC is missing."
    return 1
  fi
  if ! cmp -s "$(tmpfile toc-built "$(grep -v '^## Version:' "$pkg/$TOC" | tr -d '\r')")" \
    "$(tmpfile toc-repo "$(grep -v '^## Version:' "$repo/$TOC" | tr -d '\r')")"; then
    bad "$TOC changed beyond its ## Version line."
  fi
  versions=$(grep -c '^## Version:' "$pkg/$TOC")
  version=$(sed -n 's/^## Version: \(.*\)$/\1/p' "$pkg/$TOC" | tr -d '\r')
  if [ "$versions" -ne 1 ]; then
    bad "$TOC must have one ## Version line (found $versions)."
  elif [ "${#version}" -gt 32 ] || [ "${#version}" -lt 1 ] \
    || ! printf '%s' "$version" | LC_ALL=C grep -qxE '[A-Za-z0-9._+-]+'; then
    bad "## Version '$version' isn't 1..32 bytes of A-Z a-z 0-9 . _ + - (exports would refuse)."
  elif [ -n "$tag" ] && [ "$version" != "$tag" ]; then
    bad "## Version '$version' isn't the tag '$tag'."
  fi

  # 5. Files the TOC loads, and links.
  for f in $(grep -v '^#' "$pkg/$TOC" | tr -d '\r' | tr '\\' '/'); do
    [ -f "$pkg/$f" ] || bad "$TOC lists $f, which isn't in the package."
  done
  # Code: URLs. Text (README, LICENSE, CHANGELOG, any .md or .txt): site names too.
  # grep exits 1 for no match; anything above that is a failed scan, which fails.
  links=$(cd "$pkg" && LC_ALL=C grep -rnIiE '(://|www\.|mailto:)' \
    --include='*.lua' --include='*.toc' --include='*.xml' --exclude-dir=Libs .)
  [ $? -gt 1 ] && bad "the link scan of shipped code failed."
  [ -n "$links" ] && bad "links in shipped files:$nl$links"
  links=$(cd "$pkg" && LC_ALL=C grep -rnIiE "$LINK_RE" --exclude-dir=Libs \
    --exclude='*.lua' --exclude='*.toc' --exclude='*.xml' .)
  [ $? -gt 1 ] && bad "the link scan of shipped text failed."
  [ -n "$links" ] && bad "links or site names in shipped text:$nl$links"
  [ -f "$pkg/CHANGELOG.md" ] || bad "CHANGELOG.md is missing."
  return "$st"
}

work=$(mktemp -d) || exit 1
trap 'rm -rf "$work"' EXIT
# Writes $2 (plus a newline) to the temp file named $1 and prints its path. Called in
# $(...), a subshell, so each caller names its own file.
tmpfile() {
  printf '%s\n' "$2" > "$work/$1.txt"
  printf '%s' "$work/$1.txt"
}

# Copies the files this checkout ships into $1/InnkeepersLedger, the TOC's version set
# to $2: what a correct packager run gives.
build_good() {
  mkdir -p "$1/$NAME"
  for f in $(expected_files); do
    mkdir -p "$1/$NAME/$(dirname "$f")"
    cp "$f" "$1/$NAME/$f"
  done
  sed "s/^## Version: .*/## Version: $2/" "$TOC" > "$1/$NAME/$TOC"
}

if [ "${1-}" = "--self-test" ]; then
  status=0
  n=0
  # case <label> <expect: pass|fail> <tag> <mutation, run inside the package folder>
  case_() {
    n=$((n + 1))
    dir=$work/case$n
    cp -R "$work/good" "$dir"
    (cd "$dir/$NAME" && eval "$4") || { echo "self-test: setup failed: $1" >&2; status=1; return; }
    if check_tree "$dir" "$3" > /dev/null 2>&1; then got=pass; else got=fail; fi
    if [ "$got" != "$2" ]; then
      echo "check-package: self-test FAIL: $1: expected $2, got $got" >&2
      status=1
    fi
  }
  build_good "$work/good" "v1.2.3"
  lib=$(grep -m1 '  Libs/' Libs/MANIFEST.sha256 | cut -d' ' -f3)
  case_ "a good release build" pass v1.2.3 ":"
  case_ "a good dry run" pass "" ":"
  case_ "a dry-run version" pass "" "sed -i 's/^## Version: .*/## Version: v1.2.3-4-gabcdef1/' $TOC"
  case_ "docs/ shipped" fail "" "mkdir docs && echo x > docs/status.md"
  case_ "spec/ shipped" fail "" "mkdir spec && echo x > spec/a_spec.lua"
  case_ "scripts/ shipped" fail "" "mkdir scripts && echo x > scripts/x.sh"
  case_ "the manifest shipped" fail "" "echo x > Libs/MANIFEST.sha256"
  case_ "an extra file" fail "" "echo x > Extra.lua"
  case_ "a missing library" fail "" "rm $lib"
  case_ "a changed library" fail "" "echo '-- x' >> $lib"
  case_ "a changed Lua file" fail "" "echo '-- x' >> Core.lua"
  case_ "a missing TOC file" fail "" "rm Sync.lua"
  case_ "a second folder" fail "" "mkdir ../Other && echo x > ../Other/a.lua"
  case_ "a version left as the keyword" fail "" \
    "sed -i 's/^## Version: .*/## Version: @project-version@/' $TOC"
  case_ "a version with a space" fail "" "sed -i 's/^## Version: .*/## Version: 1 2/' $TOC"
  case_ "a version with a slash" fail "" "sed -i 's|^## Version: .*|## Version: v1/2|' $TOC"
  case_ "a 33-byte version" fail "" \
    "sed -i 's/^## Version: .*/## Version: v123456789012345678901234567890.0/' $TOC"
  case_ "an empty version" fail "" "sed -i 's/^## Version: .*/## Version: /' $TOC"
  case_ "no version line" fail "" "sed -i '/^## Version:/d' $TOC"
  case_ "two version lines" fail "" "echo '## Version: v1.2.3' >> $TOC"
  case_ "a version that isn't the tag" fail v1.2.4 ":"
  case_ "a TOC line changed" fail "" "sed -i 's/^## Interface: .*/## Interface: 110000/' $TOC"
  case_ "a link in the changelog" fail "" "echo 'see example.com' >> CHANGELOG.md"
  case_ "a short link in the changelog" fail "" "echo 'bit.ly/x' >> CHANGELOG.md"
  case_ "a mail address in the README" fail "" "echo 'mailto:a@b' >> README.md"
  case_ "a site in the LICENSE" fail "" "echo 'x.dev' >> LICENSE"
  case_ "a link in a new text file" fail "" "echo 'https://x' > Libs/../notes.txt"
  case_ "no changelog" fail "" "rm CHANGELOG.md"
  for name in "/etc/x" "../x" "a/../../x" "a/.." 'a\b' ".."; do
    [ -n "$(unsafe_names "$name")" ] || {
      echo "check-package: self-test FAIL: zip name '$name' passed" >&2; status=1; }
  done
  for name in "InnkeepersLedger/" "InnkeepersLedger/a..b.lua" "InnkeepersLedger/..a"; do
    [ -z "$(unsafe_names "$name")" ] || {
      echo "check-package: self-test FAIL: zip name '$name' failed" >&2; status=1; }
  done
  case_ "a URL in Lua" fail "" "echo '-- https://x' >> Data/Inns.lua"
  case_ "an odd name" fail "" "echo x > 'a b.lua'"
  [ "$status" -eq 0 ] && echo "check-package: self-test OK ($n cases)."
  exit "$status"
fi

mode=${1-}
case "$mode" in
  --tag) tag=${2-}; zip=${3-} ;;
  --dry-run) tag=; zip=${2-} ;;
  *) zip= ;;
esac
if [ -z "$zip" ] || { [ "$mode" = "--tag" ] && [ -z "$tag" ]; }; then
  echo "usage: check-package.sh --tag <name> <zip> | --dry-run <zip> | --self-test" >&2
  exit 2
fi
case "$zip" in /*) ;; *) zip=$OLDPWD/$zip ;; esac
if [ ! -f "$zip" ]; then
  echo "check-package: FAIL: no zip at $zip" >&2
  exit 1
fi

# Entry names before extracting: relative, no "..", no backslashes.
entries=$(unzip -Z1 "$zip") || { echo "check-package: FAIL: unreadable zip." >&2; exit 1; }
badnames=$(unsafe_names "$entries")
if [ -n "$badnames" ]; then
  echo "check-package: FAIL: unsafe entry names:$nl$badnames" >&2
  exit 1
fi
mkdir "$work/pkg" && unzip -q "$zip" -d "$work/pkg" || {
  echo "check-package: FAIL: couldn't extract the zip." >&2
  exit 1
}
if check_tree "$work/pkg" "$tag"; then
  echo "check-package: OK: $(printf '%s\n' "$entries" | grep -vc '/$') files${tag:+, version $tag}."
  exit 0
fi
exit 1
