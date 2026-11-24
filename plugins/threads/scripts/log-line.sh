#!/usr/bin/env bash
# Write one line about this session to a unit's log.md.
# Usage: log-line.sh <project> <unit> <session-id|-> <what moved>
# The line is "- <date> | <session-id> | <text>", date from THREADS_TODAY or today.
# A rerun with the same session id replaces that line in place; the id "-" always appends.
# Exit codes: 0 written, 2 bad usage or invalid name, 3 unit missing.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

usage() {
  echo "usage: log-line.sh <project> <unit> <session-id|-> <what moved>" >&2
  exit 2
}

[ "$#" -ge 4 ] || usage
project="$1"
unit="$2"
id="$3"
shift 3
valid_name "$project" || { echo "invalid project name: $project" >&2; exit 2; }
valid_name "$unit" || { echo "invalid unit name: $unit" >&2; exit 2; }
case "$id" in
  "" | *[[:space:]]* | *'|'*) echo "invalid session id" >&2; exit 2 ;;
esac
text="$(one_line "$*")"
[ -n "$text" ] || usage

udir="$(threads_dir)/$project/units/$unit"
[ -f "$udir/state.md" ] || { echo "no such unit: $project/$unit" >&2; exit 3; }

log="$udir/log.md"
date_str="${THREADS_TODAY:-$(date +%F)}"
tmp="$(mktemp "$udir/.log.XXXXXX")" || exit 1
trap 'rm -f "$tmp"' EXIT

# Rewrite the log with this session's line in place of its old one, or at the end.
# The id is compared as a string against the second " | " field, never as a regex.
[ -f "$log" ] || : > "$log" || exit 1
awk -v id="$id" -v line="- $date_str | $id | $text" '
  BEGIN { done = 0 }
  {
    n = split($0, f, " \\| ")
    if (id != "-" && n >= 3 && substr($0, 1, 2) == "- " && f[2] == id) {
      if (!done) { print line; done = 1 }
      next
    }
    print
  }
  END { if (!done) print line }
' "$log" > "$tmp" || exit 1
mv "$tmp" "$log" || exit 1
trap - EXIT
