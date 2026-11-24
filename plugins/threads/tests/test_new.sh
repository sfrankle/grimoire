#!/usr/bin/env bash
# Literal ~ in fixtures is intentional: paths are stored unexpanded.
# shellcheck disable=SC2088
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=assert.sh
. "$here/assert.sh"
# shellcheck source=../scripts/lib.sh
. "$ROOT/scripts/lib.sh"
setup

P="$THREADS_DIR"

# Project create.
out="$(bash "$NEW" project homelab $'Rebuild the | home\nserver' '~/code/homelab' '~/notes/homelab')"
assert_eq "$P/homelab/state.md" "$out" "project create prints state.md path"
assert_eq "homelab" "$(front "$P/homelab/state.md" name)" "project name"
assert_eq "Rebuild the / home server" "$(front "$P/homelab/state.md" summary)" "project summary goes through one_line"
assert_eq "active" "$(front "$P/homelab/state.md" status)" "project status active"
assert_eq "$(printf '~/code/homelab\n~/notes/homelab')" "$(front_list "$P/homelab/state.md" paths)" "project paths stored unexpanded"
assert_eq "yes" "$([ -d "$P/homelab/units" ] && echo yes)" "project has units folder"

# Project with no paths still parses.
bash "$NEW" project calculus "Study" >/dev/null
assert_eq "" "$(front_list "$P/calculus/state.md" paths)" "project without paths has empty list"
assert_eq "active" "$(front "$P/calculus/state.md" status)" "project without paths is active"

# Unit create.
out="$(bash "$NEW" unit homelab dns-cutover "Move DNS | to new box")"
assert_eq "$P/homelab/units/dns-cutover/state.md" "$out" "unit create prints state.md path"
u="$P/homelab/units/dns-cutover/state.md"
assert_eq "dns-cutover" "$(front "$u" name)" "unit name"
assert_eq "Move DNS / to new box" "$(front "$u" summary)" "unit summary through one_line"
assert_eq "active" "$(front "$u" status)" "unit status active"
assert_contains "$(cat "$u")" "## Where to continue" "unit has continue heading"

# Missing project.
assert_exit 3 "unit in missing project exits 3" -- bash "$NEW" unit missing x s
assert_eq "no" "$([ -e "$P/missing" ] && echo yes || echo no)" "missing project not created"

# Duplicates leave the first file unchanged.
before="$(cat "$P/homelab/state.md")"
assert_exit 4 "duplicate project exits 4" -- bash "$NEW" project homelab "Other"
assert_eq "$before" "$(cat "$P/homelab/state.md")" "duplicate project leaves file unchanged"
before="$(cat "$u")"
assert_exit 4 "duplicate unit exits 4" -- bash "$NEW" unit homelab dns-cutover "Other"
assert_eq "$before" "$(cat "$u")" "duplicate unit leaves file unchanged"

# Invalid names and usage write nothing.
snap() { (cd "$THREADS_DIR" && find . | sort); }
before="$(snap)"
assert_exit 2 "project ../evil exits 2" -- bash "$NEW" project ../evil s
assert_exit 2 "unit uppercase name exits 2" -- bash "$NEW" unit homelab A s
assert_exit 2 "unit a/b exits 2" -- bash "$NEW" unit homelab 'a/b' s
assert_exit 2 "unit invalid project exits 2" -- bash "$NEW" unit ../x a s
assert_exit 2 "project missing summary exits 2" -- bash "$NEW" project fresh
assert_exit 2 "project empty summary exits 2" -- bash "$NEW" project fresh "  "
assert_exit 2 "unit missing summary exits 2" -- bash "$NEW" unit homelab fresh
assert_exit 2 "unknown subcommand exits 2" -- bash "$NEW" thing a b
assert_exit 2 "no arguments exits 2" -- bash "$NEW"
assert_exit 2 "newline path exits 2" -- bash "$NEW" project fresh s $'x\nstatus: archived'
assert_exit 2 "whitespace-only path exits 2" -- bash "$NEW" project fresh s "   "
assert_exit 2 "second path with newline exits 2" -- bash "$NEW" project fresh s '~/ok' $'a\rb'
assert_eq "$before" "$(snap)" "non-zero exits write nothing"
assert_eq "no" "$([ -e "$THREADS_DIR/evil" ] && echo yes || echo no)" "no escape via .."

# Surrounding whitespace in a path is trimmed.
bash "$NEW" project trimmed s "  ~/code/trimmed  " >/dev/null
assert_eq "~/code/trimmed" "$(front_list "$P/trimmed/state.md" paths)" "path whitespace trimmed"

# A fresh root is created on first project.
rm -rf "$THREADS_DIR"
bash "$NEW" project first "First" >/dev/null
assert_eq "first" "$(front "$THREADS_DIR/first/state.md" name)" "first project creates the root"
finish
