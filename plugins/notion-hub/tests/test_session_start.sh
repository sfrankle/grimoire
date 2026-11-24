#!/usr/bin/env bash
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname "$here")"
. "$here/assert.sh"

BUILD="$root/scripts/build-index.sh"
HOOK="$root/scripts/session-start.sh"
ROWS="$here/fixtures/rows.json"
TMPS=""

# Fresh sandbox: HOME, hub dir with the example config and rules; sets NOTION_HUB_DIR and HOME.
setup() {
  T="$(mktemp -d)"
  TMPS="$TMPS $T"
  export HOME="$T/home"
  mkdir -p "$HOME"
  NOTION_HUB_DIR="$T/hub"
  export NOTION_HUB_DIR
  mkdir -p "$NOTION_HUB_DIR"
  cp "$root/examples/config.json" "$NOTION_HUB_DIR/config.json"
  cp "$root/examples/rules.md" "$NOTION_HUB_DIR/rules.md"
  unset NOTION_HUB_MAX_CHARS
}
cleanup() { for d in $TMPS; do rm -rf "$d"; done; }
trap cleanup EXIT

build() { bash "$BUILD" "$ROWS" >/dev/null; }

# run_hook <project dir>: prints the hook's stdout, stderr merged so noise is caught.
run_hook() { CLAUDE_PROJECT_DIR="$1" bash "$HOOK" 2>&1; }

line_count() { printf '%s\n' "$1" | wc -l | tr -d ' '; }

# Number of characters before the first occurrence of $2 in $1, or -1.
pos() {
  case "$1" in
    *"$2"*) local before="${1%%"$2"*}"; printf '%s' "${#before}" ;;
    *) printf '%s' "-1" ;;
  esac
}

test_no_config() {
  setup; rm "$NOTION_HUB_DIR/config.json"
  local out; out="$(run_hook "$HOME/code/app")"
  assert_eq "1" "$(line_count "$out")" "no config: one line"
  assert_contains "$out" "/notion-setup" "no config: mentions /notion-setup"
  assert_exit 0 "no config: exit 0" -- bash "$HOOK"
}

test_bad_config() {
  setup; printf '{' > "$NOTION_HUB_DIR/config.json"
  local out; out="$(run_hook "$HOME/code/app")"
  assert_eq "1" "$(line_count "$out")" "bad config: one line"
  assert_contains "$out" "/notion-setup" "bad config: mentions /notion-setup"
  assert_exit 0 "bad config: exit 0" -- bash "$HOOK"
  printf '[1,2]' > "$NOTION_HUB_DIR/config.json"
  assert_eq "1" "$(line_count "$(run_hook "$HOME/code/app")")" "array config: one line"
}

test_no_jq() {
  setup; build
  local bin="$T/bin" tool
  mkdir -p "$bin"
  for tool in bash awk cat date dirname grep sed tr head wc; do
    ln -s "$(command -v "$tool")" "$bin/$tool"
  done
  local out; out="$(CLAUDE_PROJECT_DIR="$HOME/code/app" PATH="$bin" "$bin/bash" "$HOOK" 2>&1)"
  local code=$?
  assert_eq "1" "$(line_count "$out")" "no jq: one line"
  assert_contains "$out" "jq" "no jq: says jq is needed"
  assert_eq "0" "$code" "no jq: exit 0"
}

test_no_index() {
  setup
  local out; out="$(run_hook "$HOME/code/app")"
  assert_contains "$out" "Field Notes rules" "no index: rules printed"
  assert_contains "$out" "/notion-refresh" "no index: tells you to run /notion-refresh"
  assert_not_contains "$out" "Built " "no index: no index header"
}

test_shared_folder() {
  setup; build
  printf 'PRIVATE-RULES-MARKER\n' > "$NOTION_HUB_DIR/rules.private.md"
  local out; out="$(run_hook "$HOME/code/app")"
  assert_contains "$out" "| Kiln firing log |" "shared: Kiln shown"
  assert_contains "$out" "| Studio rates |" "shared: Studio rates shown"
  assert_contains "$out" "| Tax notes |" "shared: Tax notes shown"
  assert_contains "$out" "| glaze recipes |" "shared: glaze shown"
  assert_not_contains "$out" "| How I work |" "shared: private always row hidden"
  assert_not_contains "$out" "| Visa letters |" "shared: private ask row hidden"
  assert_not_contains "$out" "PRIVATE-RULES-MARKER" "shared: rules.private.md not printed"
  assert_not_contains "$out" "Fetch before your first answer" "shared: no always list when nothing is always"
}

test_private_folder() {
  setup; build
  printf 'PRIVATE-RULES-MARKER\n' > "$NOTION_HUB_DIR/rules.private.md"
  local out; out="$(run_hook "$HOME/notes/personal/sub")"
  local n; n="$(printf '%s\n' "$out" | grep -c '^- [a-z]*/[a-z]*/[a-z]* | ')"
  assert_eq "6" "$n" "private: all six rows"
  assert_contains "$out" "PRIVATE-RULES-MARKER" "private: rules.private.md printed"
  out="$(run_hook "$HOME/notes/personal")"
  assert_contains "$out" "| Visa letters |" "private: exact private path is in scope"
}

test_prefix_not_match() {
  setup; build
  printf 'PRIVATE-RULES-MARKER\n' > "$NOTION_HUB_DIR/rules.private.md"
  local out; out="$(run_hook "$HOME/notes/personal-old")"
  assert_not_contains "$out" "| Visa letters |" "prefix: personal-old does not unlock private rows"
  assert_not_contains "$out" "PRIVATE-RULES-MARKER" "prefix: personal-old does not print private rules"
}

test_order() {
  setup; build
  local out; out="$(run_hook "$HOME/notes/personal")"
  local rules built row fetch
  rules="$(pos "$out" "Field Notes rules")"
  built="$(pos "$out" "Built ")"
  row="$(pos "$out" "- shared/auto/own | Kiln")"
  fetch="$(pos "$out" "Fetch before your first answer")"
  [ "$rules" -ge 0 ] && [ "$rules" -lt "$built" ] && pass "order: rules before Built" || fail "order: rules before Built"
  [ "$built" -lt "$row" ] && pass "order: Built before rows" || fail "order: Built before rows"
  [ "$row" -lt "$fetch" ] && [ "$fetch" -ge 0 ] && pass "order: rows before always list" || fail "order: rows before always list"
}

test_always_list() {
  setup; build
  local out; out="$(run_hook "$HOME/notes/personal")"
  local tail="${out#*Fetch before your first answer}"
  assert_contains "$tail" "How I work" "always list: names How I work"
  assert_contains "$tail" "https://www.notion.so/aaa2" "always list: gives its URL"
  assert_not_contains "$tail" "Kiln firing log" "always list: only always rows"
}

test_always_opt_in() {
  setup; build
  jq '.scopes.always_shows_everywhere = true' "$NOTION_HUB_DIR/config.json" > "$T/c" && mv "$T/c" "$NOTION_HUB_DIR/config.json"
  local out; out="$(run_hook "$HOME/code/app")"
  assert_contains "$out" "- private/always/ro | How I work |" "opt-in: always row shown in shared folder"
  assert_contains "${out#*Fetch before your first answer}" "https://www.notion.so/aaa2" "opt-in: always list entry shown"
  assert_not_contains "$out" "| Visa letters |" "opt-in: private ask row still hidden"
}

# Rewrite the epoch in index.md to N days ago.
age_index() {
  local epoch=$(( $(date +%s) - $1 * 86400 - 300 ))
  sed "s/(epoch [0-9]*)/(epoch $epoch)/" "$NOTION_HUB_DIR/index.md" > "$T/i" && mv "$T/i" "$NOTION_HUB_DIR/index.md"
}

test_age_nudge() {
  setup; build; age_index 9
  local out; out="$(run_hook "$HOME/code/app")"
  assert_contains "$out" "9 days old" "age: 9 days named"
  assert_contains "$out" "/notion-refresh" "age: old index nudges /notion-refresh"
  build; age_index 2
  out="$(run_hook "$HOME/code/app")"
  assert_not_contains "$out" "/notion-refresh" "age: 2 day old index has no nudge"
}

test_cap() {
  setup; build
  printf 'Rules.\n' > "$NOTION_HUB_DIR/rules.md"
  local max="${CAP_TEST_MAX:-800}"
  local out; out="$(NOTION_HUB_MAX_CHARS=$max run_hook "$HOME/notes/personal")"
  [ "${#out}" -le "$max" ] && pass "cap: output within $max chars (${#out})" || fail "cap: output within $max chars (${#out})"
  assert_contains "$out" "rows cut" "cap: warns about cut rows"
  assert_contains "$out" "| How I work |" "cap: always row kept"
  case "$out" in
    *"| Visa letters |"*) fail "cap: ask row cut first" ;;
    *) pass "cap: ask row cut first" ;;
  esac
  # With a limit that fits the ask row but not everything, autos go only after asks.
  local full; full="$(run_hook "$HOME/notes/personal")"
  assert_not_contains "$full" "rows cut" "cap: no warning when everything fits"
  local m2=$(( ${#full} - 5 ))
  out="$(NOTION_HUB_MAX_CHARS=$m2 run_hook "$HOME/notes/personal")"
  assert_not_contains "$out" "| Visa letters |" "cap: slightly over cuts the ask row"
  assert_contains "$out" "| Kiln firing log |" "cap: slightly over keeps auto rows"
  assert_contains "$out" "| Studio rates |" "cap: slightly over keeps all auto rows"
}

test_no_config; test_bad_config; test_no_jq; test_no_index
test_shared_folder; test_private_folder; test_prefix_not_match
test_order; test_always_list; test_always_opt_in; test_age_nudge; test_cap
finish
