#!/bin/sh
# CI only: install apt packages without hanging on a stalled mirror (#126). On
# 2026-10-07 `apt-get update` stalled mid-fetch until GitHub's 6-hour default killed
# the job. apt gets its own network timeouts and retries, `timeout` caps each command,
# and the update plus install is tried three times before the job fails.
# Usage: sh scripts/ci-apt-install.sh <package>...
set -eu

[ "$#" -gt 0 ] || { echo "usage: $0 <package>..." >&2; exit 2; }

opts="-q -o Acquire::Retries=3 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30"
attempt=1
while :; do
  # $opts is split on purpose.
  # shellcheck disable=SC2086
  if sudo timeout 240 apt-get $opts update &&
     sudo timeout 300 apt-get $opts install -y "$@"; then
    exit 0
  fi
  if [ "$attempt" -ge 3 ]; then
    echo "::error::apt failed after $attempt attempts"
    exit 1
  fi
  echo "::warning::apt attempt $attempt failed; retrying"
  attempt=$((attempt + 1))
  sleep 15
done
