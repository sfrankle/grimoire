#!/usr/bin/env bash
# Write one line about this session to a unit's log.md.
# Usage: log-line.sh <project> <unit> <session-id|-> <what moved>
# The line is "- <date> | <session-id> | <text>", date from THREADS_TODAY or today.
# A rerun with the same session id replaces that line in place; the id "-" always appends.
# Sessions writing the same log take turns through a lock folder, so no line is lost.
# THREADS_LOCK_TRIES sets how many times to try the lock, 0.1 seconds apart (default 100, about 10 seconds).
# Exit codes: 0 written, 2 bad usage or invalid name, 3 unit missing, 5 log still locked after the last try.
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
lock="$udir/.log.lock"

# mkdir is atomic on both macOS and Linux, so only one session holds the lock at a time.
max_tries="${THREADS_LOCK_TRIES:-100}"
case "$max_tries" in '' | *[!0-9]* | 0) max_tries=100 ;; esac
tries=0
until mkdir "$lock" 2>/dev/null; do
  tries=$((tries + 1))
  if [ "$tries" -ge "$max_tries" ]; then
    echo "log is locked: $lock (remove it if no other session is writing)" >&2
    exit 5
  fi
  sleep 0.1
done
tmp=""
trap 'rm -f "$tmp"; rmdir "$lock"' EXIT
tmp="$(mktemp "$udir/.log.XXXXXX")" || exit 1
# mktemp makes the file 0600; give it the umask's mode, the same as the unit's other files.
chmod "$(printf '%o' $((0666 & ~$(umask))))" "$tmp" || exit 1

# Rewrite the log with this session's line in place of its old one, or at the end.
# Values go in through the environment, since awk -v would interpret backslash escapes.
# The id is compared as a string against the second " | " field, never as a regex or a number.
[ -f "$log" ] || : > "$log" || exit 1
ID="$id" LINE="- $date_str | $id | $text" awk '
  BEGIN { done = 0; id = ENVIRON["ID"]; line = ENVIRON["LINE"] }
  {
    n = split($0, f, " \\| ")
    if (id != "-" && n >= 3 && substr($0, 1, 2) == "- " && (f[2] "") == (id "")) {
      if (!done) { print line; done = 1 }
      next
    }
    print
  }
  END { if (!done) print line }
' "$log" > "$tmp" || exit 1
mv "$tmp" "$log" || exit 1
tmp=""
