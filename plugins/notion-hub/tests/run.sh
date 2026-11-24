#!/usr/bin/env bash
# Runs every tests/test_*.sh and exits non-zero if any fails.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
status=0
for t in "$here"/test_*.sh; do
  [ -e "$t" ] || continue
  printf '== %s\n' "$(basename "$t")"
  bash "$t" || status=1
done
exit $status
