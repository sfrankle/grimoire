#!/usr/bin/env bash
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname "$here")"
# shellcheck source=assert.sh
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
# Called from the EXIT trap below.
# shellcheck disable=SC2329
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
  assert_contains "$out" "Homelab Notes rules" "no index: rules printed"
  assert_contains "$out" "/notion-refresh" "no index: tells you to run /notion-refresh"
  assert_not_contains "$out" "Built " "no index: no index header"
}

test_shared_folder() {
  setup; build
  printf 'PRIVATE-RULES-MARKER\n' > "$NOTION_HUB_DIR/rules.private.md"
  local out; out="$(run_hook "$HOME/code/app")"
  assert_contains "$out" "| NAS backup log |" "shared: NAS backup log shown"
  assert_contains "$out" "| Network layout |" "shared: Network layout shown"
  assert_contains "$out" "| Power bills |" "shared: Power bills shown"
  assert_contains "$out" "| dotfiles |" "shared: dotfiles shown"
  assert_not_contains "$out" "| Working style |" "shared: private always row hidden"
  assert_not_contains "$out" "| Medical notes |" "shared: private ask row hidden"
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
  assert_contains "$out" "| Medical notes |" "private: exact private path is in scope"
}

test_prefix_not_match() {
  setup; build
  printf 'PRIVATE-RULES-MARKER\n' > "$NOTION_HUB_DIR/rules.private.md"
  local out; out="$(run_hook "$HOME/notes/personal-old")"
  assert_not_contains "$out" "| Medical notes |" "prefix: personal-old does not unlock private rows"
  assert_not_contains "$out" "PRIVATE-RULES-MARKER" "prefix: personal-old does not print private rules"
}

test_order() {
  setup; build
  local out; out="$(run_hook "$HOME/notes/personal")"
  local rules built row fetch
  rules="$(pos "$out" "Homelab Notes rules")"
  built="$(pos "$out" "Built ")"
  row="$(pos "$out" "- shared/auto/own | NAS backup")"
  fetch="$(pos "$out" "Fetch before your first answer")"
  if [ "$rules" -ge 0 ] && [ "$rules" -lt "$built" ]; then pass "order: rules before Built"; else fail "order: rules before Built"; fi
  if [ "$built" -lt "$row" ]; then pass "order: Built before rows"; else fail "order: Built before rows"; fi
  if [ "$row" -lt "$fetch" ] && [ "$fetch" -ge 0 ]; then pass "order: rows before always list"; else fail "order: rows before always list"; fi
}

test_always_list() {
  setup; build
  local out; out="$(run_hook "$HOME/notes/personal")"
  local tail="${out#*Fetch before your first answer}"
  assert_contains "$tail" "Working style" "always list: names Working style"
  assert_contains "$tail" "https://www.notion.so/aaa2" "always list: gives its URL"
  assert_not_contains "$tail" "NAS backup log" "always list: only always rows"
}

test_always_opt_in() {
  setup; build
  jq '.scopes.always_shows_everywhere = true' "$NOTION_HUB_DIR/config.json" > "$T/c" && mv "$T/c" "$NOTION_HUB_DIR/config.json"
  local out; out="$(run_hook "$HOME/code/app")"
  assert_contains "$out" "- private/always/ro | Working style |" "opt-in: always row shown in shared folder"
  assert_contains "${out#*Fetch before your first answer}" "https://www.notion.so/aaa2" "opt-in: always list entry shown"
  assert_not_contains "$out" "| Medical notes |" "opt-in: private ask row still hidden"
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
  assert_contains "$out" "/notion-refresh" "age: 9 day old index nudges /notion-refresh"
  build; age_index 7
  out="$(run_hook "$HOME/code/app")"
  assert_contains "$out" "7 days old" "age: 7 days named"
  assert_not_contains "$out" "/notion-refresh" "age: exactly 7 days has no nudge"
  build; age_index 2
  out="$(run_hook "$HOME/code/app")"
  assert_contains "$out" "2 days old" "age: 2 days named"
  assert_not_contains "$out" "/notion-refresh" "age: 2 day old index has no nudge"
}

test_cap() {
  setup; build
  printf 'Rules.\n' > "$NOTION_HUB_DIR/rules.md"
  local max="${CAP_TEST_MAX:-800}"
  local out; out="$(NOTION_HUB_MAX_CHARS=$max run_hook "$HOME/notes/personal")"
  if [ "${#out}" -le "$max" ]; then pass "cap: output within $max chars (${#out})"; else fail "cap: output within $max chars (${#out})"; fi
  assert_contains "$out" "rows cut" "cap: warns about cut rows"
  assert_contains "$out" "| Working style |" "cap: always row kept"
  case "$out" in
    *"| Medical notes |"*) fail "cap: ask row cut first" ;;
    *) pass "cap: ask row cut first" ;;
  esac
  # With a limit that fits the ask row but not everything, autos go only after asks.
  local full; full="$(run_hook "$HOME/notes/personal")"
  assert_not_contains "$full" "rows cut" "cap: no warning when everything fits"
  local m2=$(( ${#full} - 5 ))
  out="$(NOTION_HUB_MAX_CHARS=$m2 run_hook "$HOME/notes/personal")"
  assert_not_contains "$out" "| Medical notes |" "cap: slightly over cuts the ask row"
  assert_contains "$out" "| NAS backup log |" "cap: slightly over keeps auto rows"
  assert_contains "$out" "| Network layout |" "cap: slightly over keeps all auto rows"
}

test_one_day_old() {
  setup; build; age_index 1
  local out; out="$(run_hook "$HOME/code/app")"
  assert_contains "$out" "Index is 1 day old." "age: 1 day is singular"
  assert_not_contains "$out" "1 days" "age: no '1 days'"
}

test_string_private_paths() {
  setup; build
  jq '.scopes.private_paths = "~/notes/personal"' "$NOTION_HUB_DIR/config.json" > "$T/c" && mv "$T/c" "$NOTION_HUB_DIR/config.json"
  local out; out="$(run_hook "$HOME/notes/personal")"
  assert_contains "$out" "| Medical notes |" "string private_paths: private row shown in that folder"
  out="$(run_hook "$HOME/code/app")"
  assert_not_contains "$out" "| Medical notes |" "string private_paths: private row hidden elsewhere"
}

test_cap_cut_order() {
  setup; build
  printf 'Rules.\n' > "$NOTION_HUB_DIR/rules.md"
  # The warning costs more than one row saves, so one character over cuts two rows.
  local full out; full="$(run_hook "$HOME/notes/personal")"
  out="$(NOTION_HUB_MAX_CHARS=$(( ${#full} - 1 )) run_hook "$HOME/notes/personal")"
  assert_not_contains "$out" "| Medical notes |" "cut order: ask row goes first"
  assert_not_contains "$out" "| Power bills |" "cut order: last auto row goes after the ask rows"
  assert_contains "$out" "| Network layout |" "cut order: earlier autos stay"
  assert_contains "$out" "| NAS backup log |" "cut order: middle auto stays"
  assert_contains "$out" "| dotfiles |" "cut order: first auto stays"
  assert_contains "$out" "| Working style |" "cut order: always row stays"
  assert_contains "$out" "2 index rows cut" "cut order: warning counts both cuts"
}

test_cap_warning_text() {
  setup; build
  local out; out="$(NOTION_HUB_MAX_CHARS=800 run_hook "$HOME/notes/personal")"
  assert_contains "$out" "Shorten summaries" "cap warning: says to shorten summaries"
  assert_not_contains "$out" "trim the hub" "cap warning: no old advice"
}

test_cap_never_cut_over() {
  setup
  printf '[{"url":"https://www.notion.so/zzz1","properties":{"Name":"Only always","Summary":"Always loaded","Load":"Always","Area":"Homelab"}}]' > "$T/one.json"
  bash "$BUILD" "$T/one.json" >/dev/null
  local out; out="$(NOTION_HUB_MAX_CHARS=10 run_hook "$HOME/code/app")"
  assert_contains "$out" "Warning" "never-cut over cap: still warns"
  assert_contains "$out" "| Only always |" "never-cut over cap: always row kept"
}

test_many_rows() {
  setup
  jq -n '[range(0; 600) | {url: "https://www.notion.so/r\(.)", properties: {Name: "Page number \(.)", Summary: "A summary line long enough to matter for the cap", Load: (if . % 50 == 0 then "Always" elif . % 7 == 0 then "Only when asked" else null end), Area: "Homelab"}}]' > "$T/many.json"
  bash "$BUILD" "$T/many.json" >/dev/null
  local start=$SECONDS out
  out="$(run_hook "$HOME/code/app")"
  if [ $(( SECONDS - start )) -le 5 ]; then pass "many rows: 600 rows finish quickly"; else fail "many rows: 600 rows finish quickly"; fi
  if [ "${#out}" -le 9500 ]; then pass "many rows: output within the cap"; else fail "many rows: output within the cap (${#out})"; fi
  assert_contains "$out" "rows cut" "many rows: warns about cut rows"
  assert_contains "$out" "Page number 0" "many rows: always row kept"
}

test_no_config; test_bad_config; test_no_jq; test_no_index
test_shared_folder; test_private_folder; test_prefix_not_match
test_order; test_always_list; test_always_opt_in; test_age_nudge; test_cap
test_one_day_old; test_string_private_paths; test_cap_cut_order
test_cap_warning_text; test_cap_never_cut_over; test_many_rows
finish
