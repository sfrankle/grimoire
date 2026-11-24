#!/usr/bin/env bash
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=assert.sh
. "$here/assert.sh"
setup

P="$THREADS_DIR"
bash "$NEW" project homelab "Rebuild" >/dev/null
bash "$NEW" unit homelab dns-cutover "Move DNS" >/dev/null
U="$P/homelab/units/dns-cutover"
export THREADS_TODAY=2026-11-24

# First call creates the log.
assert_exit 0 "first call exits 0" -- bash "$LOG" homelab dns-cutover abc-123 "drafted spec"
assert_eq "- 2026-11-24 | abc-123 | drafted spec" "$(cat "$U/log.md")" "first call creates log line"

# Same id replaces the line and its date.
THREADS_TODAY=2026-11-25 bash "$LOG" homelab dns-cutover abc-123 "wrote plan"
assert_eq "- 2026-11-25 | abc-123 | wrote plan" "$(cat "$U/log.md")" "same id replaces line and date"

# A new id appends.
bash "$LOG" homelab dns-cutover def-456 "reviewed"
assert_eq "- 2026-11-25 | abc-123 | wrote plan
- 2026-11-24 | def-456 | reviewed" "$(cat "$U/log.md")" "new id appends"

# Replacement keeps position.
bash "$LOG" homelab dns-cutover abc-123 "shipped"
assert_eq "- 2026-11-24 | abc-123 | shipped
- 2026-11-24 | def-456 | reviewed" "$(cat "$U/log.md")" "replace keeps position"

# Ids are compared literally, not as regexes.
bash "$LOG" homelab dns-cutover 'a.c-123' "dotted"
assert_eq "3" "$(wc -l < "$U/log.md" | tr -d ' ')" "regex-like id does not match abc-123"

# Dash id always appends.
bash "$LOG" homelab dns-cutover - "one"
bash "$LOG" homelab dns-cutover - "two"
assert_eq "2" "$(grep -c ' | - | ' "$U/log.md")" "dash ids append"

# One-line text.
bash "$NEW" unit homelab other "Other" >/dev/null
bash "$LOG" homelab other s1 $'a\nb | c'
assert_eq "- 2026-11-24 | s1 | a b / c" "$(cat "$P/homelab/units/other/log.md")" "newline and pipe become space and slash"

# No leftover temp files.
assert_eq "log.md
state.md" "$(ls -A "$U")" "no leftover temp file"

# Failures write nothing.
snap() { (cd "$THREADS_DIR" && find . -type f | sort); }
before="$(snap)"
assert_exit 3 "missing unit exits 3" -- bash "$LOG" homelab nope s1 "x"
assert_exit 3 "missing project exits 3" -- bash "$LOG" ghost nope s1 "x"
assert_exit 2 ".. as project exits 2" -- bash "$LOG" .. dns-cutover s1 "x"
assert_exit 2 ".. as unit exits 2" -- bash "$LOG" homelab .. s1 "x"
assert_exit 2 "missing text exits 2" -- bash "$LOG" homelab dns-cutover s1
assert_exit 2 "empty text exits 2" -- bash "$LOG" homelab dns-cutover s1 "  "
assert_exit 2 "no arguments exits 2" -- bash "$LOG"
assert_exit 2 "id with space exits 2" -- bash "$LOG" homelab dns-cutover "a b" "x"
assert_eq "$before" "$(snap)" "failed calls write nothing"
mkdir "$P/homelab/units/stateless"
assert_exit 3 "unit folder without state.md exits 3" -- bash "$LOG" homelab stateless s1 "x"
assert_eq "no" "$([ -e "$P/homelab/units/stateless/log.md" ] && echo yes || echo no)" "no log for stateless unit"

# Backslashes pass through awk literally, in text and in ids.
bash "$NEW" unit homelab lit "Literal" >/dev/null
L="$P/homelab/units/lit/log.md"
bash "$LOG" homelab lit s1 'dir C:\new\table'
assert_eq '- 2026-11-24 | s1 | dir C:\new\table' "$(cat "$L")" "backslashes in text stay literal on one line"
bash "$LOG" homelab lit 'x\y' "first"
bash "$LOG" homelab lit 'x\y' "second"
assert_eq '- 2026-11-24 | x\y | second' "$(tail -n +2 "$L")" "backslash id matches its earlier line"
assert_eq "2" "$(wc -l < "$L" | tr -d ' ')" "backslash id leaves one line per id"

# Numeric-looking ids compare as strings.
bash "$LOG" homelab lit 1 "one"
bash "$LOG" homelab lit 1.0 "one point zero"
assert_eq "2" "$(grep -c -e '| 1 |' -e '| 1.0 |' "$L")" "ids 1 and 1.0 stay separate lines"

# Date defaults to today.
unset THREADS_TODAY
bash "$LOG" homelab other today-id "x"
assert_contains "$(cat "$P/homelab/units/other/log.md")" "| today-id | x" "default date call writes"
assert_contains "$(cat "$P/homelab/units/other/log.md")" "- $(date +%F) | today-id" "default date is today"
finish
