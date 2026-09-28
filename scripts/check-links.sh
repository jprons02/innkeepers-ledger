#!/bin/sh
# Fail if the context docs are broken (CLAUDE.md -> Context map).
# 1. Every relative markdown link in CLAUDE.md, README.md, CONTRIBUTING.md and docs/
#    points at a file or folder that exists (the #anchor part isn't checked).
# 2. Every doc directly under docs/ has a row in CLAUDE.md's context map (specs and
#    archive are covered by their own rows).
# Fails closed: a doc that can't be read is a failure. Runs from any directory.
set -u
set -f

cd "$(dirname "$0")/.." || exit 1
status=0
nl='
'

docs=$(git -c core.quotePath=true ls-files -co --exclude-standard -- \
  CLAUDE.md README.md CONTRIBUTING.md 'docs/*.md' 'docs/**/*.md') || {
  echo "check-links: FAIL: git ls-files failed." >&2
  exit 1
}
docs=$(printf '%s\n' "$docs" | sort -u)

IFS=$nl
for f in $docs; do
  if [ ! -r "$f" ]; then
    echo "check-links: FAIL: cannot read $f" >&2
    status=1
    continue
  fi
  dir=$(dirname "$f")
  # Link targets: "](target)" or "](target#anchor)". Fenced code blocks and inline code
  # spans aren't links, so they're removed first. External links, mailto and same-page
  # anchors are skipped.
  targets=$(awk '/^[[:space:]]*```/ { fence = !fence; next } !fence' "$f" |
    sed 's/`[^`]*`//g' | grep -oE '\]\([^) ]+\)' |
    sed -e 's/^](//' -e 's/)$//' -e 's/#.*$//' | grep -vE '^(https?:|mailto:|$)' || true)
  for t in $targets; do
    if [ ! -e "$dir/$t" ]; then
      echo "check-links: FAIL: $f links to a missing file: $t" >&2
      status=1
    fi
  done
done

for f in $(printf '%s\n' "$docs" | grep -E '^docs/[^/]+\.md$'); do
  if ! grep -qF "($f)" CLAUDE.md; then
    echo "check-links: FAIL: $f has no row in CLAUDE.md's context map" >&2
    status=1
  fi
done

if [ "$status" -eq 0 ]; then
  echo "check-links: OK: $(printf '%s\n' "$docs" | grep -c .) docs, links resolve, map complete."
fi
exit "$status"
