#!/usr/bin/env bash
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=assert.sh
. "$here/assert.sh"

scoped() { CLAUDE_PROJECT_DIR="$1" bash "$SCOPED" 2>&1; }

test_shared_folder() {
  setup; build
  local out; out="$(scoped "$HOME/code/app")"
  assert_contains "$out" "| NAS backup log |" "shared folder: shared row listed"
  assert_not_contains "$out" "Medical notes" "shared folder: private ask row hidden"
  assert_not_contains "$out" "Working style" "shared folder: private always row hidden"
  assert_not_contains "$out" "Built " "shared folder: rows only, no header"
}

test_private_folder() {
  setup; build
  local out; out="$(scoped "$HOME/notes/personal/sub")"
  assert_eq "6" "$(printf '%s\n' "$out" | grep -c '^- ')" "private folder: all six rows"
}

test_always_opt_in() {
  setup; build
  patch_config '.scopes.always_shows_everywhere = true'
  local out; out="$(scoped "$HOME/code/app")"
  assert_contains "$out" "| Working style |" "opt-in: private always row listed"
  assert_not_contains "$out" "Medical notes" "opt-in: private ask row still hidden"
}

test_missing() {
  setup
  assert_exit 1 "no index: exits 1" -- env CLAUDE_PROJECT_DIR="$HOME" bash "$SCOPED"
  build; rm "$NOTION_HUB_DIR/config.json"
  assert_exit 1 "no config: exits 1" -- env CLAUDE_PROJECT_DIR="$HOME" bash "$SCOPED"
}

test_bad_scopes() {
  setup; build
  patch_config '.scopes = "Personal"'
  assert_exit 1 "string scopes: exits 1" -- env CLAUDE_PROJECT_DIR="$HOME" bash "$SCOPED"
  assert_not_contains "$(scoped "$HOME/code/app")" "Medical notes" "string scopes: no rows leak"
}

scoped_hub() { local d="$1"; shift; CLAUDE_PROJECT_DIR="$d" bash "$SCOPED" "$@" 2>&1; }

test_multi_one() {
  setup_multi; build_hub garden "$ROWS_GARDEN"
  local out; out="$(scoped_hub "$HOME/code/app" garden)"
  assert_contains "$out" "| Planting calendar |" "multi one: shared row listed"
  assert_contains "$out" "| Seed inventory |" "multi one: second shared row listed"
  assert_not_contains "$out" "Allotment lease" "multi one: private row hidden"
  assert_not_contains "$out" "## " "multi one: no heading"
}

test_multi_private() {
  setup_multi; build_hub garden "$ROWS_GARDEN"
  local out; out="$(scoped_hub "$HOME/notes/personal" garden)"
  assert_eq "3" "$(printf '%s\n' "$out" | grep -c '^- ')" "multi private: all three rows"
}

test_multi_all() {
  setup_multi; build_hub garden "$ROWS_GARDEN"; build_hub homelab
  local out; out="$(scoped_hub "$HOME/code/app")"
  assert_contains "$out" "## Garden Journal (garden)" "multi all: garden heading"
  assert_contains "$out" "## Homelab Notes (homelab)" "multi all: homelab heading"
  local g h
  g="$(printf '%s\n' "$out" | grep -n '^## Garden' | cut -d: -f1)"
  h="$(printf '%s\n' "$out" | grep -n '^## Homelab' | cut -d: -f1)"
  assert_eq "yes" "$([ "$g" -lt "$h" ] && echo yes || echo no)" "multi all: garden block first"
  assert_contains "$out" "| NAS backup log |" "multi all: homelab rows listed"
  assert_contains "$out" "| Planting calendar |" "multi all: garden rows listed"
  assert_contains "$out" "
## Homelab" "multi all: blank line between blocks"
}

test_multi_unknown() {
  setup_multi; build_hub garden "$ROWS_GARDEN"
  assert_exit 1 "multi unknown: exits 1" -- env CLAUDE_PROJECT_DIR="$HOME" bash "$SCOPED" nope
}

test_multi_bad_hub() {
  setup_multi; build_hub garden "$ROWS_GARDEN"; build_hub homelab
  printf '{' > "$NOTION_HUB_DIR/garden/config.json"
  assert_exit 0 "multi bad hub: exits 0" -- env CLAUDE_PROJECT_DIR="$HOME/code/app" bash "$SCOPED"
  local out; out="$(scoped_hub "$HOME/code/app")"
  assert_contains "$out" "| NAS backup log |" "multi bad hub: homelab rows still listed"
  assert_contains "$out" "## garden: config is invalid" "multi bad hub: garden named"
}

test_multi_no_index() {
  setup_multi; build_hub homelab
  local out; out="$(scoped_hub "$HOME/code/app")"
  assert_contains "$out" "## garden: no index yet. Run /notion-refresh garden." "multi no index: reason"
  assert_contains "$out" "| NAS backup log |" "multi no index: other hub listed"
}

test_legacy_with_id() {
  setup; build
  assert_exit 1 "legacy with id: exits 1" -- env CLAUDE_PROJECT_DIR="$HOME" bash "$SCOPED" homelab
}

test_shared_folder; test_private_folder; test_always_opt_in; test_missing; test_bad_scopes
test_multi_one; test_multi_private; test_multi_all; test_multi_unknown; test_multi_bad_hub; test_multi_no_index; test_legacy_with_id
finish
