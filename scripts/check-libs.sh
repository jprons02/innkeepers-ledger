#!/bin/sh
# Verify that Libs/ holds exactly the reviewed library files (docs/libraries.md):
#   1. every file in Libs/MANIFEST.sha256 matches its hash, and
#   2. every name under Libs/ is plain (A-Z a-z 0-9 . _ -), and
#   3. nothing else exists under Libs/ besides the manifest itself, and
#   4. the manifest's library hashes equal docs/libraries.md -> Reviewed files.
# Exits non-zero with a message on any failure. Runs from any directory.
set -u

cd "$(dirname "$0")/.." || exit 1
manifest=Libs/MANIFEST.sha256
status=0

if [ ! -f "$manifest" ]; then
  echo "check-libs: FAIL: $manifest is missing." >&2
  exit 1
fi

# 1. Hashes. --strict also fails on malformed manifest lines.
if ! sha256sum --strict -c "$manifest"; then
  echo "check-libs: FAIL: a vendored file differs from $manifest (or is missing)." >&2
  status=1
fi
# Every line must be "<hash>  Libs/<path>": no comments, blanks or paths elsewhere.
badlines=$(grep -vxE '[0-9a-f]{64}  Libs/[A-Za-z0-9._/-]+' "$manifest" || true)
if [ -n "$badlines" ]; then
  echo "check-libs: FAIL: $manifest lines must be '<sha256>  Libs/<path>':" >&2
  printf '%s\n' "$badlines" | sed 's/^/  /' >&2
  status=1
fi

# 2. Unsafe names. The unlisted-file check below compares paths line by line, so a
# name holding a newline could split into two listed paths. Allow only plain names.
odd=$(LC_ALL=C find Libs -name '*[!A-Za-z0-9._-]*')
if [ -n "$odd" ]; then
  echo "check-libs: FAIL: names under Libs/ may only use A-Z a-z 0-9 . _ - :" >&2
  printf '%s\n' "$odd" | sed 's/^/  /' >&2
  status=1
fi

# 3. Unlisted files. Anything that isn't a directory counts, symlinks included.
listed=$(sed -e 's/^[0-9a-f]\{64\}  //' "$manifest" | sort)
present=$(find Libs ! -type d ! -path "$manifest" | sort)
extra=$(printf '%s\n' "$present" | grep -vxF -e "$listed" || true)
if [ -n "$extra" ]; then
  echo "check-libs: FAIL: files under Libs/ that are not in $manifest:" >&2
  printf '%s\n' "$extra" | sed 's/^/  /' >&2
  status=1
fi

# 4. Review doc. The manifest's hashes (except Libs/embeds.xml, which is ours) must be
# exactly the "Reviewed files" hashes in the review doc, so changing, adding or removing
# a library also means editing the review record, not just the manifest. Only lines in
# the doc's "## Reviewed files" section count, in the form "<sha256>  <source>:<path>".
review=docs/libraries.md
if [ ! -f "$review" ]; then
  echo "check-libs: FAIL: $review is missing." >&2
  status=1
else
  reviewed=$(sed -n '/^## Reviewed files/,/^## /p' "$review" |
    grep -E '^[0-9a-f]{64}  [a-z0-9.-]+:' | cut -c1-64 | sort)
  vendored=$(grep -vxE '[0-9a-f]{64}  Libs/embeds\.xml' "$manifest" | cut -c1-64 | sort)
  if [ -z "$reviewed" ]; then
    echo "check-libs: FAIL: no hashes found in $review -> Reviewed files." >&2
    status=1
  elif [ "$reviewed" != "$vendored" ]; then
    echo "check-libs: FAIL: $manifest hashes differ from $review -> Reviewed files." >&2
    echo "  in the manifest only:" >&2
    printf '%s\n' "$vendored" | grep -vxF -e "$reviewed" | sed 's/^/    /' >&2
    echo "  in the review doc only:" >&2
    printf '%s\n' "$reviewed" | grep -vxF -e "$vendored" | sed 's/^/    /' >&2
    echo "  (counts: manifest $(printf '%s\n' "$vendored" | grep -c .)," \
      "review doc $(printf '%s\n' "$reviewed" | grep -c .))" >&2
    status=1
  fi
fi

if [ "$status" -eq 0 ]; then
  echo "check-libs: OK: $(grep -c '^[0-9a-f]\{64\}  ' "$manifest") files match $manifest and $review, no unlisted files."
fi
exit "$status"
