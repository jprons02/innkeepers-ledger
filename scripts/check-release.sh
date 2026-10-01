#!/bin/sh
# The checks before the packager runs (docs/security-checklist.md -> Before the packager
# lands; release.yml runs this first). Fails closed.
#   check-release.sh --tag <name>  a release: everything below, plus the tag is vX.Y.Z
#                                  and CHANGELOG.md has a "## <name>" section.
#   check-release.sh --dry-run     a dry run: everything below.
#   check-release.sh --self-test   checks the tag rule against known good and bad names.
# Always:
#   1. No .env file: the packager sources one as shell code.
#   2. .pkgmeta has no externals (decisions.md, 2026-09-26: what ships is Libs/).
#   3. .pkgmeta names CHANGELOG.md as the manual changelog and the file exists, so the
#      packager never builds one from commit messages (they hold links; addon policy).
# Runs from any directory.
set -u

cd "$(dirname "$0")/.." || exit 1

# A tag the packager may turn into "## Version": vX.Y.Z, at most 32 bytes in all, so it
# also passes export.md 3.5's [A-Za-z0-9._+-]{1,32}.
good_tag() {
  [ "${#1}" -le 32 ] || return 1
  printf '%s' "$1" | LC_ALL=C grep -qxE 'v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)' \
    || return 1
  # grep -x matches line by line; a name holding a newline must not pass.
  [ "$(printf '%s' "$1" | wc -l)" -eq 0 ]
}

if [ "${1-}" = "--self-test" ]; then
  status=0
  for t in v0.1.0 v1.0.0 v1.2.3 v10.20.30 v0.0.1 v1.0.999999999999999999999; do
    if ! good_tag "$t"; then
      echo "check-release: self-test FAIL: rejected good tag '$t'" >&2
      status=1
    fi
  done
  nl='
'
  for t in "" v 1.0.0 v1.0 v1.0.0.0 V1.0.0 v01.0.0 v1.0.0-beta v1.0.0+x "v1.0.0 " \
    " v1.0.0" "v1.0.0${nl}v1.0.1" "v1.0.0${nl}" v1.0.0/x 'v1.0.$x' v1.0.0x \
    v1.0.1234567890123456789012345678 refs/tags/v1.0.0 vI.0.0; do
    if good_tag "$t"; then
      echo "check-release: self-test FAIL: accepted bad tag '$t'" >&2
      status=1
    fi
  done
  [ "$status" -eq 0 ] && echo "check-release: self-test OK."
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

# 1. The packager runs ". .env" from the top directory or the working directory.
if [ -e .env ] || [ -L .env ]; then
  fail ".env exists; the packager would run it as shell code."
fi

# 2 and 3. .pkgmeta.
if [ ! -f .pkgmeta ]; then
  fail ".pkgmeta is missing."
else
  if grep -qE '^[[:space:]]*externals[[:space:]]*:' .pkgmeta; then
    fail ".pkgmeta has externals; ship only the reviewed Libs/."
  fi
  # Every library entry is a plain copy (no keyword replacement), the manifest isn't.
  for entry in $(cd Libs && LC_ALL=C ls -A); do
    [ "$entry" = MANIFEST.sha256 ] && continue
    if ! grep -qxF "  - Libs/$entry" .pkgmeta; then
      fail ".pkgmeta's plain-copy list is missing Libs/$entry."
    fi
  done
  if grep -qE '^[[:space:]]+-[[:space:]]+Libs/?[[:space:]]*$' .pkgmeta; then
    fail ".pkgmeta plain-copies all of Libs/, which ships Libs/MANIFEST.sha256."
  fi
  if ! grep -qxE 'manual-changelog:[[:space:]]*' .pkgmeta \
    || ! grep -qxE '[[:space:]]+filename:[[:space:]]*CHANGELOG\.md[[:space:]]*' .pkgmeta; then
    fail ".pkgmeta must name CHANGELOG.md as its manual-changelog filename."
  fi
fi
if [ ! -f CHANGELOG.md ]; then
  fail "CHANGELOG.md is missing; the packager would build one from commit messages."
elif LC_ALL=C grep -nIiE '(https?://|www\.|[a-z0-9-]+\.(com|net|org|io|gg|ai)\b)' CHANGELOG.md; then
  fail "CHANGELOG.md holds a link or a site name (addon policy: no external references)."
fi
if [ "$mode" = "--tag" ] && [ "$status" -eq 0 ] && ! grep -qxF "## $tag" CHANGELOG.md; then
  fail "CHANGELOG.md has no '## $tag' section; write the release notes first."
fi

if [ "$status" -eq 0 ]; then
  echo "check-release: OK${tag:+ for $tag}."
fi
exit "$status"
