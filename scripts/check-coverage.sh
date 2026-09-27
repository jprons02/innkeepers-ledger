#!/bin/sh
# Fail if a pure module's line coverage is under its floor (CONTRIBUTING.md -> Tests).
# Reads the luacov report that `busted --coverage && luacov` writes (config: .luacov).
# Every file in the floor list must appear in the report; a missing file, a missing
# report or a coverage-disabling comment in a pure module is a failure (fails closed).
# Changing a floor needs a decision-log entry (docs/decisions.md). Runs from any directory.
set -u

cd "$(dirname "$0")/.." || exit 1
report=luacov.report.out
status=0

# file floor(%). The security boundary gets the higher floor.
floors='Ledger.lua 95
SyncProtocol.lua 95
Phrase.lua 90
Collection.lua 90
Cosmetics.lua 90
Export.lua 90'

if [ ! -r "$report" ]; then
  echo "check-coverage: FAIL: $report not found; run busted --coverage, then luacov." >&2
  exit 1
fi

# Excluding lines from coverage would hide untested paths in the modules that matter most.
for f in $(printf '%s\n' "$floors" | cut -d' ' -f1); do
  if [ ! -r "$f" ]; then
    echo "check-coverage: FAIL: cannot read $f" >&2
    status=1
  elif grep -n 'luacov:' "$f" >/dev/null; then
    echo "check-coverage: FAIL: $f turns coverage off with a luacov comment:" >&2
    grep -n 'luacov:' "$f" | sed 's/^/  /' >&2
    status=1
  fi
done

# The summary rows look like: "Ledger.lua   123  4  96.85%".
summary=$(awk '/^Summary$/ { s = 1 } s && NF == 4 && $4 ~ /%$/ { print $1, $4 }' "$report")

printf '%s\n' "$floors" | {
  inner=0
  while read -r file floor; do
    pct=$(printf '%s\n' "$summary" | awk -v f="$file" '$1 == f { sub(/%$/, "", $2); print $2 }')
    if [ -z "$pct" ]; then
      echo "check-coverage: FAIL: $file is not in the coverage report (not loaded by any spec?)" >&2
      inner=1
    elif awk -v p="$pct" -v m="$floor" 'BEGIN { exit !(p + 0 < m + 0) }'; then
      echo "check-coverage: FAIL: $file at $pct%, floor $floor%" >&2
      inner=1
    else
      echo "check-coverage: $file $pct% (floor $floor%)"
    fi
  done
  exit "$inner"
} || status=1

if [ "$status" -eq 0 ]; then
  echo "check-coverage: OK: every pure module is at or above its floor."
fi
exit "$status"
