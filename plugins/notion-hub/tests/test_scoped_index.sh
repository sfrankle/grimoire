#!/usr/bin/env bash
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname "$here")"
# shellcheck source=assert.sh
. "$here/assert.sh"

BUILD="$root/scripts/build-index.sh"
SCOPED="$root/scripts/scoped-index.sh"
ROWS="$here/fixtures/rows.json"
TMPS=""

setup() {
  T="$(mktemp -d)"
  TMPS="$TMPS $T"
  export HOME="$T/home"
  mkdir -p "$HOME"
  NOTION_HUB_DIR="$T/hub"
  export NOTION_HUB_DIR
  mkdir -p "$NOTION_HUB_DIR"
  cp "$root/examples/config.json" "$NOTION_HUB_DIR/config.json"
  bash "$BUILD" "$ROWS" >/dev/null
}
# Called from the EXIT trap below.
# shellcheck disable=SC2329
cleanup() { for d in $TMPS; do rm -rf "$d"; done; }
trap cleanup EXIT

scoped() { CLAUDE_PROJECT_DIR="$1" bash "$SCOPED" 2>&1; }

test_shared_folder() {
  setup
  local out; out="$(scoped "$HOME/code/app")"
  assert_contains "$out" "| NAS backup log |" "shared folder: shared row listed"
  assert_not_contains "$out" "Medical notes" "shared folder: private ask row hidden"
  assert_not_contains "$out" "Working style" "shared folder: private always row hidden"
  assert_not_contains "$out" "Built " "shared folder: rows only, no header"
}

test_private_folder() {
  setup
  local out; out="$(scoped "$HOME/notes/personal/sub")"
  assert_eq "6" "$(printf '%s\n' "$out" | grep -c '^- ')" "private folder: all six rows"
}

test_always_opt_in() {
  setup
  jq '.scopes.always_shows_everywhere = true' "$NOTION_HUB_DIR/config.json" > "$T/c" && mv "$T/c" "$NOTION_HUB_DIR/config.json"
  local out; out="$(scoped "$HOME/code/app")"
  assert_contains "$out" "| Working style |" "opt-in: private always row listed"
  assert_not_contains "$out" "Medical notes" "opt-in: private ask row still hidden"
}

test_missing() {
  setup; rm "$NOTION_HUB_DIR/index.md"
  assert_exit 1 "no index: exits 1" -- env CLAUDE_PROJECT_DIR="$HOME" bash "$SCOPED"
  setup; rm "$NOTION_HUB_DIR/config.json"
  assert_exit 1 "no config: exits 1" -- env CLAUDE_PROJECT_DIR="$HOME" bash "$SCOPED"
}

test_bad_scopes() {
  setup
  jq '.scopes = "Personal"' "$NOTION_HUB_DIR/config.json" > "$T/c" && mv "$T/c" "$NOTION_HUB_DIR/config.json"
  local err; err="$(scoped "$HOME/code/app")"
  assert_exit 1 "string scopes: exits 1" -- env CLAUDE_PROJECT_DIR="$HOME" bash "$SCOPED"
  assert_contains "$err" "must be an object" "string scopes: names the shape, not JSON syntax"
}

test_shared_folder; test_private_folder; test_always_opt_in; test_missing; test_bad_scopes
finish
