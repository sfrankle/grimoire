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

test_shared_folder; test_private_folder; test_always_opt_in; test_missing; test_bad_scopes
finish
