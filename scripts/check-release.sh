#!/bin/sh
# The checks before the packager runs (docs/security-checklist.md -> Before the packager
# lands; release.yml runs this first). Fails closed.
#   check-release.sh --tag <name>  a release: everything below, plus the tag is vX.Y.Z,
#                                  the tagged commit is on origin/main, and CHANGELOG.md
#                                  has a "## <name>" section.
#   check-release.sh --dry-run     a dry run: everything below.
#   check-release.sh --self-test   runs every rule against known good and bad inputs.
# Always:
#   1. No .env file: the packager sources one as shell code.
#   2. Every tracked file is a plain file (mode 100644 or 100755): a symlink would ship
#      whatever it points at.
#   3. .pkgmeta uses only package-as, manual-changelog, plain-copy and ignore, each once;
#      no externals (decisions.md, 2026-09-26: what ships is Libs/), no license fetch.
#   4. The manual changelog is CHANGELOG.md and exists, so the packager never builds one
#      from commit messages (they hold links; addon policy). It holds no link.
#   5. Every entry under Libs/ but the manifest is its own plain-copy line, and Libs/
#      as a whole isn't one (it would ship the manifest).
# Runs from any directory.
set -u
set -f

cd "$(dirname "$0")/.." || exit 1
repo=$(pwd)
nl='
'

# Links, mail addresses and site names (addon policy: no external references).
LINK_RE='(://|mailto:|www\.|[a-z0-9-]+\.(com|net|org|io|gg|ai|dev|app|co|me|tv|ly|us|uk|de|fr|eu|info|xyz|link|site|online|store|shop|gl|to|be|cc|ws|gift|blog)([^a-z0-9]|$))'

# A tag the packager may turn into "## Version": vX.Y.Z, at most 32 bytes in all, so it
# also passes export.md 3.5's [A-Za-z0-9._+-]{1,32}.
good_tag() {
  [ "${#1}" -le 32 ] || return 1
  printf '%s' "$1" | LC_ALL=C grep -qxE 'v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)' \
    || return 1
  # grep -x matches line by line; a name holding a newline must not pass.
  [ "$(printf '%s' "$1" | wc -l)" -eq 0 ]
}

# $1: `git ls-files -s` output. Prints the entries that aren't plain files.
odd_modes() {
  printf '%s\n' "$1" | LC_ALL=C awk 'NF && $1 != "100644" && $1 != "100755"'
}

# Checks the release tree in the current directory (rules 1, 3, 4, 5). Prints failures;
# returns non-zero on any.
check_tree() {
  st=0
  bad() {
    echo "check-release: FAIL: $1" >&2
    st=1
  }

  # 1. The packager runs ". .env" from the top directory or the working directory.
  if [ -e .env ] || [ -L .env ]; then
    bad ".env exists; the packager would run it as shell code."
  fi

  # 3. .pkgmeta's top-level keys.
  if [ ! -f .pkgmeta ]; then
    bad ".pkgmeta is missing."
    return 1
  fi
  keys=$(LC_ALL=C grep -vE '^([[:space:]]|#|$)' .pkgmeta | tr -d '\r')
  for key in $(printf '%s\n' "$keys" | sed 's/[[:space:]]*:.*$//' | LC_ALL=C sort | uniq -d); do
    bad ".pkgmeta has '$key' more than once."
  done
  odd=$(printf '%s\n' "$keys" |
    LC_ALL=C grep -vxE '(package-as:[[:space:]]*InnkeepersLedger|manual-changelog:|plain-copy:|ignore:)[[:space:]]*')
  [ $? -gt 1 ] && bad "the .pkgmeta key scan failed."
  if [ -n "$odd" ]; then
    bad ".pkgmeta may only hold package-as: InnkeepersLedger, manual-changelog:, plain-copy: and ignore: at the top level (no externals, license-output, move-folders, ...):$nl$odd"
  fi

  # 4. The changelog: the block under manual-changelog is exactly these two lines.
  block=$(awk '
    /^manual-changelog:/ { on = 1; next }
    on && /^[^[:space:]#]/ { on = 0 }
    on && /^[[:space:]]+[^[:space:]#]/ { gsub(/\r/, ""); print }
  ' .pkgmeta)
  if [ "$block" != "  filename: CHANGELOG.md${nl}  markup-type: markdown" ]; then
    bad ".pkgmeta's manual-changelog must be exactly 'filename: CHANGELOG.md' and 'markup-type: markdown'."
  fi
  if [ ! -f CHANGELOG.md ]; then
    bad "CHANGELOG.md is missing; the packager would build one from commit messages."
  else
    LC_ALL=C grep -nIiE "$LINK_RE" CHANGELOG.md >&2
    case $? in
      0) bad "CHANGELOG.md holds a link or a site name (addon policy: no external references)." ;;
      1) ;;
      *) bad "the link scan of CHANGELOG.md failed." ;;
    esac
  fi

  # 5. Libraries are plain copies, one line each.
  if [ ! -d Libs ]; then
    bad "Libs/ is missing."
  else
    for entry in $(LC_ALL=C ls -A Libs); do
      [ "$entry" = MANIFEST.sha256 ] && continue
      if ! grep -qxF "  - Libs/$entry" .pkgmeta; then
        bad ".pkgmeta's plain-copy list is missing Libs/$entry."
      fi
    done
  fi
  if section plain-copy | grep -qE '^[[:space:]]+-[[:space:]]+(Libs/?|Libs/MANIFEST\.sha256)[[:space:]]*$'; then
    bad ".pkgmeta plain-copies Libs/ or its manifest, which would ship Libs/MANIFEST.sha256."
  fi
  if ! section ignore | grep -qxE '[[:space:]]+-[[:space:]]+Libs/MANIFEST\.sha256[[:space:]]*'; then
    bad ".pkgmeta's ignore list must hold Libs/MANIFEST.sha256."
  fi
  return "$st"
}

# The lines of .pkgmeta's top-level section $1, without the key line.
section() {
  awk -v key="$1:" '
    { sub(/\r$/, "") }
    $0 ~ "^" key { on = 1; next }
    on && /^[^[:space:]#]/ { on = 0 }
    on' .pkgmeta
}

# True if HEAD is origin/main or an ancestor of it; false if origin/main isn't there.
on_main() {
  git rev-parse -q --verify refs/remotes/origin/main > /dev/null \
    && git merge-base --is-ancestor HEAD refs/remotes/origin/main
}

if [ "${1-}" = "--self-test" ]; then
  status=0
  sfail() {
    echo "check-release: self-test FAIL: $1" >&2
    status=1
  }

  # Tag names.
  for t in v0.1.0 v1.0.0 v1.2.3 v10.20.30 v0.0.1 v1.0.999999999999999999999; do
    good_tag "$t" || sfail "rejected good tag '$t'"
  done
  for t in "" v 1.0.0 v1.0 v1.0.0.0 V1.0.0 v01.0.0 v1.0.0-beta v1.0.0+x "v1.0.0 " \
    " v1.0.0" "v1.0.0${nl}v1.0.1" "v1.0.0${nl}" "v1.0.0$(printf '\r')" v1.0.0/x \
    'v1.0.$x' v1.0.0x v1.0.1234567890123456789012345678 refs/tags/v1.0.0 vI.0.0; do
    good_tag "$t" && sfail "accepted bad tag '$t'"
  done

  # File modes.
  [ -z "$(odd_modes "100644 abc 0	a.lua${nl}100755 abc 0	x.sh")" ] || sfail "flagged plain files"
  [ -n "$(odd_modes "100644 abc 0	a.lua${nl}120000 abc 0	Data/x.txt")" ] || sfail "missed a symlink"
  [ -n "$(odd_modes "160000 abc 0	sub")" ] || sfail "missed a submodule"

  # The tree rules, on copies of this checkout's .pkgmeta, CHANGELOG.md and Libs/ list.
  work=$(mktemp -d) || exit 1
  trap 'rm -rf "$work"' EXIT
  n=0
  # tcase <label> <expect: pass|fail> <mutation, run inside the copy>
  tcase() {
    n=$((n + 1))
    d=$work/t$n
    mkdir -p "$d/Libs"
    cp "$repo/.pkgmeta" "$repo/CHANGELOG.md" "$d/"
    for e in $(LC_ALL=C ls -A "$repo/Libs"); do : > "$d/Libs/$e"; done
    (cd "$d" && eval "$3") || { sfail "setup: $1"; return; }
    if (cd "$d" && check_tree) > /dev/null 2>&1; then got=pass; else got=fail; fi
    [ "$got" = "$2" ] || sfail "$1: expected $2, got $got"
  }
  tcase "this checkout" pass ":"
  tcase "a .env file" fail "echo 'x=1' > .env"
  tcase "no .pkgmeta" fail "rm .pkgmeta"
  tcase "externals" fail "printf 'externals:\n  Libs/X: x\n' >> .pkgmeta"
  tcase "quoted externals" fail "printf '\"externals\":\n  Libs/X: x\n' >> .pkgmeta"
  tcase "license-output" fail "echo 'license-output: LICENSE.txt' >> .pkgmeta"
  tcase "move-folders" fail "printf 'move-folders:\n  a: b\n' >> .pkgmeta"
  tcase "nolib creation" fail "echo 'enable-nolib-creation: yes' >> .pkgmeta"
  tcase "another package name" fail "sed -i 's/^package-as: .*/package-as: Other/' .pkgmeta"
  tcase "a second manual-changelog" fail \
    "printf 'manual-changelog:\n  filename: NOTES.md\n' >> .pkgmeta"
  tcase "a second ignore list" fail "printf 'ignore:\n  - x\n' >> .pkgmeta"
  tcase "another changelog file" fail \
    "sed -i 's/filename: CHANGELOG.md/filename: NOTES.md/' .pkgmeta"
  tcase "a changelog filename moved away" fail \
    "sed -i '/filename: CHANGELOG.md/d' .pkgmeta && printf 'x:\n  filename: CHANGELOG.md\n' >> .pkgmeta"
  tcase "no manual changelog" fail "sed -i '/^manual-changelog:/,/markup-type/d' .pkgmeta"
  tcase "no CHANGELOG.md" fail "rm CHANGELOG.md"
  for link in "https://x" "see example.com" "www.x" "bit.ly/x" "mailto:a@b" "a.dev site" \
    "x.gg/y"; do
    tcase "a changelog link: $link" fail "echo '- $link' >> CHANGELOG.md"
  done
  tcase "file names in the changelog" pass "echo '- Core.lua and embeds.xml changed' >> CHANGELOG.md"
  tcase "a library not plain-copied" fail "sed -i '/  - Libs\/LibStub$/d' .pkgmeta"
  tcase "a new library not plain-copied" fail ": > Libs/NewLib"
  tcase "all of Libs plain-copied" fail \
    "sed -i 's|^plain-copy:$|plain-copy:\n  - Libs|' .pkgmeta"
  tcase "the manifest plain-copied" fail \
    "sed -i 's|^plain-copy:$|plain-copy:\n  - Libs/MANIFEST.sha256|' .pkgmeta"
  tcase "the manifest not ignored" fail "sed -i '/  - Libs\/MANIFEST.sha256/d' .pkgmeta"

  # On main: a throwaway repo where origin/main holds A, and B is a branch commit.
  g=$work/git
  if mkdir "$g" && cd "$g" && git init -q . && git -c user.name=t -c user.email=t@t \
    commit -q --allow-empty -m A && git update-ref refs/remotes/origin/main HEAD \
    && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m B; then
    on_main && sfail "a commit not on origin/main passed"
    git checkout -q HEAD~1
    on_main || sfail "a commit on origin/main failed"
    git update-ref -d refs/remotes/origin/main
    on_main && sfail "passed with no origin/main"
    cd "$repo" || exit 1
  else
    sfail "setup: the throwaway repo"
  fi

  [ "$status" -eq 0 ] && echo "check-release: self-test OK ($n tree cases)."
  exit "$status"
fi

mode=${1-}
tag=${2-}
case "$mode" in
  --tag) ;;
  --dry-run) tag= ;;
  *)
    echo "usage: check-release.sh --tag <name> | --dry-run | --self-test" >&2
    exit 2
    ;;
esac

status=0
fail() {
  echo "check-release: FAIL: $1" >&2
  status=1
}

if [ "$mode" = "--tag" ] && ! good_tag "$tag"; then
  fail "the tag must be vX.Y.Z (numbers without leading zeros), at most 32 bytes."
fi
check_tree || status=1

# 2. Modes.
files=$(git ls-files -s) || fail "git ls-files failed."
[ -n "$files" ] || fail "git ls-files listed nothing."
odd=$(odd_modes "$files")
if [ -n "$odd" ]; then
  fail "tracked entries that aren't plain files (symlinks, submodules):$nl$odd"
fi

if [ "$mode" = "--tag" ]; then
  # Only reviewed code ships: the tag must point at a commit already on main (the
  # dev -> main release PR and its security review). Guards against a mistaken tag; the
  # tagged commit carries its own copy of this script, so it isn't a hard stop.
  if ! on_main; then
    fail "the tagged commit isn't on origin/main; tag main after the release PR merges."
  fi
  if [ -f CHANGELOG.md ] && ! grep -qxF "## $tag" CHANGELOG.md; then
    fail "CHANGELOG.md has no '## $tag' section; write the release notes first."
  fi
fi

if [ "$status" -eq 0 ]; then
  echo "check-release: OK${tag:+ for $tag}."
fi
exit "$status"
