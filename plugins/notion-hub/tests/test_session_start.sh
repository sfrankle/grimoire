#!/usr/bin/env bash
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=assert.sh
. "$here/assert.sh"

# setup_rules: the sandbox from assert.sh plus the example rules.
setup_rules() { setup; cp "$ROOT/examples/hubs/homelab/rules.md" "$NOTION_HUB_DIR/rules.md"; }

# run_hook <project dir>: prints the hook's stdout, stderr merged so noise is caught.
run_hook() { CLAUDE_PROJECT_DIR="$1" bash "$HOOK" 2>&1; }

line_count() { printf '%s\n' "$1" | wc -l | tr -d ' '; }
rows_of() { printf '%s\n' "$1" | grep -c '^- [a-z]*/[a-z]*/[a-z]* | '; }

# Number of characters before the first occurrence of $2 in $1, or -1.
pos() {
  case "$1" in
    *"$2"*) local before="${1%%"$2"*}"; printf '%s' "${#before}" ;;
    *) printf '%s' "-1" ;;
  esac
}

test_no_config() {
  setup_rules; rm "$NOTION_HUB_DIR/config.json"
  local out; out="$(run_hook "$HOME/code/app")"
  assert_eq "1" "$(line_count "$out")" "no config: one line"
  assert_contains "$out" "/notion-setup" "no config: mentions /notion-setup"
  assert_exit 0 "no config: exit 0" -- bash "$HOOK"
}

test_bad_config() {
  setup_rules; printf '{' > "$NOTION_HUB_DIR/config.json"
  local out; out="$(run_hook "$HOME/code/app")"
  assert_eq "1" "$(line_count "$out")" "bad config: one line"
  assert_contains "$out" "/notion-setup" "bad config: mentions /notion-setup"
  assert_exit 0 "bad config: exit 0" -- bash "$HOOK"
  printf '[1,2]' > "$NOTION_HUB_DIR/config.json"
  assert_eq "1" "$(line_count "$(run_hook "$HOME/code/app")")" "array config: one line"
}

test_no_jq() {
  setup_rules; build
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
  setup_rules
  local out; out="$(run_hook "$HOME/code/app")"
  assert_contains "$out" "Homelab Notes rules" "no index: rules printed"
  assert_contains "$out" "/notion-refresh" "no index: tells you to run /notion-refresh"
  assert_not_contains "$out" "Built " "no index: no index header"
}

test_shared_folder() {
  setup_rules; build
  printf 'PRIVATE-RULES-MARKER\n' > "$NOTION_HUB_DIR/rules.private.md"
  local out; out="$(run_hook "$HOME/code/app")"
  assert_contains "$out" "| NAS backup log |" "shared: NAS backup log shown"
  assert_contains "$out" "| Network layout |" "shared: Network layout shown"
  assert_contains "$out" "| Power bills |" "shared: Power bills shown"
  assert_contains "$out" "| dotfiles |" "shared: dotfiles shown"
  assert_not_contains "$out" "| Working style |" "shared: private always row hidden"
  assert_not_contains "$out" "| Medical notes |" "shared: private ask row hidden"
  assert_not_contains "$out" "PRIVATE-RULES-MARKER" "shared: rules.private.md not printed"
}

test_private_folder() {
  setup_rules; build
  printf 'PRIVATE-RULES-MARKER\n' > "$NOTION_HUB_DIR/rules.private.md"
  local out; out="$(run_hook "$HOME/notes/personal/sub")"
  assert_eq "6" "$(rows_of "$out")" "private: all six rows"
  assert_contains "$out" "PRIVATE-RULES-MARKER" "private: rules.private.md printed"
  out="$(run_hook "$HOME/notes/personal")"
  assert_contains "$out" "| Medical notes |" "private: exact private path is in scope"
}

test_prefix_not_match() {
  setup_rules; build
  printf 'PRIVATE-RULES-MARKER\n' > "$NOTION_HUB_DIR/rules.private.md"
  local out; out="$(run_hook "$HOME/notes/personal-old")"
  assert_not_contains "$out" "| Medical notes |" "prefix: personal-old does not unlock private rows"
  assert_not_contains "$out" "PRIVATE-RULES-MARKER" "prefix: personal-old does not print private rules"
}

test_order() {
  setup_rules; build
  local out; out="$(run_hook "$HOME/notes/personal")"
  local rules built always auto ask
  rules="$(pos "$out" "Homelab Notes rules")"
  built="$(pos "$out" "Built ")"
  always="$(pos "$out" "- private/always/ro | Working style")"
  auto="$(pos "$out" "- shared/auto/own | NAS backup")"
  ask="$(pos "$out" "- private/ask/ro | Medical notes")"
  if [ "$rules" -ge 0 ] && [ "$rules" -lt "$built" ] && [ "$built" -lt "$always" ]; then pass "order: rules, header, rows"; else fail "order: rules, header, rows"; fi
  if [ "$always" -lt "$auto" ] && [ "$auto" -lt "$ask" ]; then pass "order: always, auto, ask"; else fail "order: always, auto, ask"; fi
}

test_always_opt_in() {
  setup_rules; build
  patch_config '.scopes.always_shows_everywhere = true'
  local out; out="$(run_hook "$HOME/code/app")"
  assert_contains "$out" "- private/always/ro | Working style |" "opt-in: always row shown in shared folder"
  assert_not_contains "$out" "| Medical notes |" "opt-in: private ask row still hidden"
}

test_string_private_paths() {
  setup_rules; build
  patch_config '.scopes.private_paths = "~/notes/personal"'
  assert_contains "$(run_hook "$HOME/notes/personal")" "| Medical notes |" "string private_paths: private row shown in that folder"
  assert_not_contains "$(run_hook "$HOME/code/app")" "| Medical notes |" "string private_paths: private row hidden elsewhere"
}

test_bad_scopes() {
  setup_rules; build
  patch_config '.scopes = "Personal"'
  local out; out="$(run_hook "$HOME/code/app")"
  assert_eq "1" "$(line_count "$out")" "bad scopes: one line"
  assert_contains "$out" "/notion-setup" "bad scopes: mentions /notion-setup"
}

# Past the cap, ask rows go before auto rows, always rows stay, and one line says how many were left out.
test_cap() {
  setup_rules; build
  local full out; full="$(run_hook "$HOME/notes/personal")"
  assert_not_contains "$full" "did not fit" "cap: no note when everything fits"
  out="$(NOTION_HUB_MAX_CHARS=$(( ${#full} + 100 )) run_hook "$HOME/notes/personal")"
  assert_not_contains "$out" "| Medical notes |" "cap: slightly over cuts the ask row"
  assert_contains "$out" "| NAS backup log |" "cap: slightly over keeps auto rows"
  assert_contains "$out" "1 more rows did not fit" "cap: names the cut count"
  assert_contains "$out" "scoped-index.sh" "cap: points at scoped-index.sh"
  out="$(NOTION_HUB_MAX_CHARS=10 run_hook "$HOME/notes/personal")"
  assert_contains "$out" "| Working style |" "cap: always row never cut"
  assert_eq "1" "$(rows_of "$out")" "cap: only the always row left"
}

test_many_rows() {
  setup_rules
  jq -n '[range(0; 600) | {url: "https://www.notion.so/r\(.)", properties: {Name: "Page number \(.)", Summary: "A summary line long enough to matter for the cap", Load: (if . % 50 == 0 then "Always" elif . % 7 == 0 then "Only when asked" else null end), Area: "Homelab"}}]' > "$T/many.json"
  build "$T/many.json"
  local start=$SECONDS out
  out="$(run_hook "$HOME/code/app")"
  if [ $(( SECONDS - start )) -le 5 ]; then pass "many rows: 600 rows finish quickly"; else fail "many rows: 600 rows finish quickly"; fi
  if [ "${#out}" -le 9500 ]; then pass "many rows: output within the cap"; else fail "many rows: output within the cap (${#out})"; fi
  assert_contains "$out" "did not fit" "many rows: says rows were left out"
  assert_contains "$out" "Page number 0" "many rows: always row kept"
}

# setup_hubs: both example hubs with built indexes and the routing rules.
setup_hubs() { setup_multi; build_hub homelab; build_hub garden "$ROWS_GARDEN"; }

test_multi_routing_first() {
  setup_hubs
  local out routing homelab garden
  out="$(run_hook "$HOME/code/app")"
  routing="$(pos "$out" "# Notion hub routing")"
  homelab="$(pos "$out" "## Notion hub: Homelab Notes (homelab)")"
  garden="$(pos "$out" "Notion hub Garden Journal (garden): ")"
  if [ "$routing" -ge 0 ] && [ "$routing" -lt "$homelab" ] && [ "$routing" -lt "$garden" ]; then pass "multi: routing rules first"; else fail "multi: routing rules first"; fi
  if [ "$garden" -lt "$homelab" ]; then pass "multi: hubs in name order"; else fail "multi: hubs in name order"; fi
}

test_pointer_outside() {
  setup_hubs
  local out; out="$(run_hook "$HOME/code/app")"
  assert_contains "$out" "Notion hub Garden Journal (garden): Sowing dates, plant care and harvest notes. Not loaded in this folder; run $SCOPED garden to list it." "pointer: garden pointer line"
  assert_contains "$out" "- shared/always/edit | Planting calendar |" "pointer: shared always row shown"
  assert_not_contains "$out" "| Seed inventory |" "pointer: auto row hidden"
  assert_not_contains "$out" "Garden Journal rules" "pointer: hub rules hidden"
  assert_not_contains "$out" "## Notion hub: Garden Journal" "pointer: no garden heading"
  assert_eq "1" "$(printf '%s\n' "$out" | grep -c '^Built ')" "pointer: only the loaded hub's index header"
  assert_contains "$out" "Homelab Notes rules" "pointer: homelab rules loaded"
  assert_contains "$out" "| NAS backup log |" "pointer: homelab auto rows loaded"
}

test_pointer_no_private_leak() {
  setup_hubs
  printf 'GARDEN-PRIVATE-MARKER\n' > "$NOTION_HUB_DIR/garden/rules.private.md"
  local out; out="$(run_hook "$HOME/code/app")"
  assert_not_contains "$out" "| Allotment lease |" "pointer private: private always row hidden in a shared folder"
  assert_not_contains "$out" "GARDEN-PRIVATE-MARKER" "pointer private: rules.private.md hidden"
  out="$(run_hook "$HOME/notes/personal")"
  assert_contains "$out" "| Allotment lease |" "pointer private: private always row shown in a private folder"
  assert_not_contains "$out" "GARDEN-PRIVATE-MARKER" "pointer private: rules.private.md hidden outside show_in"
}

test_inside_show_in() {
  setup_hubs
  local out; out="$(run_hook "$HOME/garden/beds")"
  assert_contains "$out" "## Notion hub: Garden Journal (garden)" "show_in: garden heading"
  assert_contains "$out" "Garden Journal rules" "show_in: garden rules"
  assert_contains "$out" "| Seed inventory |" "show_in: garden auto row"
  assert_contains "$out" "| NAS backup log |" "show_in: homelab still loaded"
  assert_not_contains "$out" "Not loaded in this folder" "show_in: no pointer lines"
}

test_two_hubs_loaded_cap() {
  setup_hubs
  patch_hub homelab '.hub.show_in = ["~/garden"] | .scopes.private_paths = ["~/garden"]'
  local full out cap; full="$(run_hook "$HOME/garden")"
  assert_contains "$full" "## Notion hub: Homelab Notes (homelab)" "two loaded: homelab heading"
  assert_contains "$full" "## Notion hub: Garden Journal (garden)" "two loaded: garden heading"
  assert_contains "$full" "| Medical notes |" "two loaded: ask row in scope"
  cap=$(( ${#full} - 1 ))
  out="$(NOTION_HUB_MAX_CHARS=$cap run_hook "$HOME/garden")"
  assert_not_contains "$out" "| Medical notes |" "two loaded cap: ask row cut"
  assert_contains "$out" "| Working style |" "two loaded cap: homelab always row kept"
  assert_contains "$out" "| Planting calendar |" "two loaded cap: garden always row kept"
  assert_eq "1" "$(printf '%s\n' "$out" | grep -c 'did not fit')" "two loaded cap: one closing line"
  if [ "${#out}" -le "$cap" ]; then pass "two loaded cap: within the cap"; else fail "two loaded cap: within the cap (${#out} > $cap)"; fi
}

test_one_bad_hub() {
  setup_hubs; printf '{' > "$NOTION_HUB_DIR/garden/config.json"
  local out err code
  out="$(CLAUDE_PROJECT_DIR="$HOME/code/app" bash "$HOOK" 2>"$T/err")"; code=$?
  err="$(cat "$T/err")"
  assert_contains "$out" "Notion hub garden: config is invalid. Run /notion-setup to fix it." "bad hub: one line for garden"
  assert_eq "1" "$(printf '%s\n' "$out" | grep -c 'Notion hub garden')" "bad hub: only one garden line"
  assert_not_contains "$out" "| Planting calendar |" "bad hub: no garden rows"
  assert_contains "$out" "| NAS backup log |" "bad hub: homelab rows still load"
  assert_eq "0" "$code" "bad hub: exit 0"
  assert_eq "" "$err" "bad hub: empty stderr"
}

test_no_index_one_hub() {
  setup_hubs; rm "$NOTION_HUB_DIR/garden/index.md"
  local out; out="$(run_hook "$HOME/garden")"
  assert_contains "$out" "No index yet for garden. Run /notion-refresh garden." "no index one hub: names the hub"
  assert_contains "$out" "| NAS backup log |" "no index one hub: homelab rows still load"
  out="$(run_hook "$HOME/code/app")"
  assert_contains "$out" "Notion hub Garden Journal (garden): " "no index one hub: pointer line still printed"
}

test_legacy_show_in() {
  setup_rules; build
  patch_config '.hub.show_in = "~/code/homelab"'
  local out; out="$(run_hook "$HOME/code/app")"
  assert_contains "$out" "Notion hub Homelab Notes: Backups, network layout, hardware and how each service is deployed. Not loaded in this folder; run $SCOPED to list it." "legacy show_in: pointer line without an id"
  assert_not_contains "$out" "(homelab)" "legacy show_in: no hub id in the label"
  assert_not_contains "$out" "scoped-index.sh homelab" "legacy show_in: no hub id after scoped-index.sh"
  assert_not_contains "$out" "| Working style |" "legacy show_in: private always row hidden"
  assert_not_contains "$out" "| NAS backup log |" "legacy show_in: no auto rows"
  assert_not_contains "$out" "Homelab Notes rules" "legacy show_in: rules hidden"
  out="$(run_hook "$HOME/code/homelab")"
  assert_contains "$out" "| NAS backup log |" "legacy show_in: loaded inside show_in"
  assert_not_contains "$out" "Not loaded in this folder" "legacy show_in: no pointer inside show_in"
}

test_cap_cuts_pointer_always() {
  setup_hubs
  patch_hub homelab '.scopes.always_shows_everywhere = true'
  local full out; full="$(run_hook "$HOME/code/app")"
  assert_contains "$full" "| Planting calendar |" "pointer cap: pointer always row shown uncapped"
  out="$(NOTION_HUB_MAX_CHARS=10 run_hook "$HOME/code/app")"
  assert_not_contains "$out" "| Planting calendar |" "pointer cap: pointer always row cut"
  assert_contains "$out" "| Working style |" "pointer cap: loaded always row kept"
  assert_contains "$out" "5 more rows did not fit" "pointer cap: cut rows counted across hubs"
  out="$(NOTION_HUB_MAX_CHARS=$(( ${#full} - 1 )) run_hook "$HOME/code/app")"
  assert_contains "$out" "| Planting calendar |" "pointer cap: pointer always row outranks auto rows"
  assert_contains "$out" "did not fit" "pointer cap: auto rows cut first"
}

test_skipped_folder() {
  setup_hubs
  mkdir -p "$NOTION_HUB_DIR/Bad Name"; cp "$NOTION_HUB_DIR/garden/config.json" "$NOTION_HUB_DIR/Bad Name/"
  local out; out="$(run_hook "$HOME/code/app")"
  assert_contains "$out" "Notion hub folder 'Bad Name' ignored: hub ids are lowercase letters, digits and dashes." "skipped: ignored line"
  assert_eq "1" "$(printf '%s\n' "$out" | grep -c 'ignored: hub ids')" "skipped: one ignored line"
  assert_contains "$out" "## Notion hub: Homelab Notes (homelab)" "skipped: homelab loads"
  assert_contains "$out" "Notion hub Garden Journal (garden): " "skipped: garden pointer"
}

test_rules_tab() {
  setup_hubs
  printf 'Tab\tinside\tthe rules\n' >> "$NOTION_HUB_DIR/rules.md"
  assert_contains "$(run_hook "$HOME/code/app")" "$(printf 'Tab\tinside\tthe rules')" "rules tab: tabs survive"
}

test_no_config; test_bad_config; test_no_jq; test_no_index
test_shared_folder; test_private_folder; test_prefix_not_match
test_order; test_always_opt_in; test_string_private_paths; test_bad_scopes
test_cap; test_many_rows
test_multi_routing_first; test_pointer_outside; test_pointer_no_private_leak; test_inside_show_in
test_two_hubs_loaded_cap; test_one_bad_hub; test_no_index_one_hub; test_legacy_show_in
test_cap_cuts_pointer_always; test_skipped_folder; test_rules_tab
finish
