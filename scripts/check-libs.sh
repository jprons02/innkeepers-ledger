#!/bin/sh
# Verify that Libs/ holds exactly the reviewed library files (docs/libraries.md):
#   1. every file in Libs/MANIFEST.sha256 matches its hash, and
#   2. nothing else exists under Libs/ besides the manifest itself.
# Exits non-zero with a message on either failure. Runs from any directory.
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

# 2. Unlisted files. Anything that isn't a directory counts, symlinks included.
listed=$(sed -e 's/^[0-9a-f]\{64\}  //' "$manifest" | sort)
present=$(find Libs ! -type d ! -path "$manifest" | sort)
extra=$(printf '%s\n' "$present" | grep -vxF -e "$listed" || true)
if [ -n "$extra" ]; then
  echo "check-libs: FAIL: files under Libs/ that are not in $manifest:" >&2
  printf '%s\n' "$extra" | sed 's/^/  /' >&2
  status=1
fi

if [ "$status" -eq 0 ]; then
  echo "check-libs: OK: $(printf '%s\n' "$listed" | wc -l | tr -d ' ') files match $manifest, no unlisted files."
fi
exit "$status"
