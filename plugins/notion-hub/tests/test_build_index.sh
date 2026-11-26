#!/usr/bin/env bash
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=assert.sh
. "$here/assert.sh"

row() { grep -F "| $1 |" "$NOTION_HUB_DIR/index.md"; }

test_flags() {
  setup; build
  assert_contains "$(row 'Working style')" "- private/always/ro | Working style |" "flags: private always ro"
  assert_contains "$(row 'Power bills')" "- shared/auto/ro | Power bills |" "flags: mixed visibility is shared, no edit is ro"
  assert_contains "$(row 'Medical notes')" "- private/ask/ro | Medical notes |" "flags: private ask ro"
  assert_contains "$(row 'NAS backup log')" "- shared/auto/own | NAS backup log |" "flags: shared auto own"
  assert_contains "$(row 'Network layout')" "- shared/auto/edit | Network layout |" "flags: shared auto edit"
  assert_contains "$(row 'NAS backup log')" "| category: Log | keywords: backup, restic | https://www.notion.so/aaa1" "optional fields and url"
}

test_sort() {
  setup; build
  local order
  order="$(grep '^- ' "$NOTION_HUB_DIR/index.md" | awk -F' [|] ' '{print $2}' | paste -sd, -)"
  assert_eq "dotfiles,Medical notes,NAS backup log,Network layout,Power bills,Working style" "$order" "rows sorted by title, case-insensitive"
}

test_escaping() {
  setup; build
  local line seps
  line="$(grep -F 'dotfiles' "$NOTION_HUB_DIR/index.md")"
  assert_contains "$line" "zsh / tmux neovim" "pipe becomes slash, newline becomes space"
  seps="$(printf '%s' "$line" | grep -o ' | ' | wc -l | tr -d ' ')"
  assert_eq "3" "$seps" "dotfiles row keeps exactly 4 fields"
  assert_eq "1" "$(grep -c 'dotfiles' "$NOTION_HUB_DIR/index.md")" "dotfiles row is one line"
}

test_header() {
  setup; local out
  out="$(bash "$BUILD" "$ROWS")"
  assert_eq "Indexed 6 pages." "$out" "prints the row count"
  assert_contains "$(cat "$NOTION_HUB_DIR/index.md")" "# Notion hub index: Homelab Notes" "header title"
  if grep -Eq '^Built [0-9]{4}-[0-9]{2}-[0-9]{2} from .*/notion-refresh' "$NOTION_HUB_DIR/index.md"; then
    pass "built line with date and refresh hint"; else fail "built line with date and refresh hint"; fi
}

test_optional() {
  setup
  patch_config 'del(.fields.keywords)'
  bash "$BUILD" "$ROWS" >/dev/null
  assert_not_contains "$(cat "$NOTION_HUB_DIR/index.md")" "keywords:" "no keywords field when unmapped"
  assert_contains "$(cat "$NOTION_HUB_DIR/index.md")" "category: Log" "category still present"
}

test_empty_keeps_old() {
  setup; printf 'old index\n' > "$NOTION_HUB_DIR/index.md"
  printf '[]' > "$NOTION_HUB_DIR/empty.json"
  assert_exit 1 "empty rows exits 1" -- bash "$BUILD" "$NOTION_HUB_DIR/empty.json"
  assert_eq "old index" "$(cat "$NOTION_HUB_DIR/index.md")" "empty rows keeps index.md"
  assert_eq "" "$(find "$NOTION_HUB_DIR" -maxdepth 1 -name ".index*")" "no temp file left behind"
}

test_malformed_keeps_old() {
  setup; printf 'old index\n' > "$NOTION_HUB_DIR/index.md"
  printf 'not json' > "$NOTION_HUB_DIR/bad.json"
  assert_exit 1 "malformed rows exits 1" -- bash "$BUILD" "$NOTION_HUB_DIR/bad.json"
  assert_eq "old index" "$(cat "$NOTION_HUB_DIR/index.md")" "malformed rows keeps index.md"
}

test_no_config() {
  setup; rm "$NOTION_HUB_DIR/config.json"
  local err
  err="$(bash "$BUILD" "$ROWS" 2>&1 >/dev/null)"
  assert_exit 1 "no config exits 1" -- bash "$BUILD" "$ROWS"
  assert_contains "$err" "/notion-setup" "no config mentions /notion-setup"
}

test_missing_column() {
  setup; printf 'old index\n' > "$NOTION_HUB_DIR/index.md"
  patch_config '.fields.title = "Renamed column"'
  local err; err="$(bash "$BUILD" "$ROWS" 2>&1 >/dev/null)"
  assert_exit 1 "missing title column exits 1" -- bash "$BUILD" "$ROWS"
  assert_contains "$err" "title column" "missing title column says so"
  assert_eq "old index" "$(cat "$NOTION_HUB_DIR/index.md")" "missing title column keeps index.md"
}

test_no_visibility_is_shared() {
  setup
  jq 'map(.properties |= del(.Area))' "$ROWS" > "$T/rows.json"
  assert_eq "Indexed 6 pages." "$(bash "$BUILD" "$T/rows.json")" "no visibility column still indexes every row"
  assert_contains "$(row 'Working style')" "- shared/" "no visibility values means shared"
}

test_string_config_values() {
  setup
  patch_config '.values.load.always = "Always" | .scopes.private_values = "Personal"'
  bash "$BUILD" "$ROWS" >/dev/null
  assert_contains "$(row 'Working style')" "- private/always/ro |" "string always value matches exactly"
  setup
  patch_config '.values.load.always = "Always on" | .scopes.private_values = "Personal stuff"'
  bash "$BUILD" "$ROWS" >/dev/null
  assert_contains "$(row 'Working style')" "- shared/auto/ro |" "string values are not substring-matched"
}

test_multi_named() {
  setup_multi
  bash "$BUILD" "$ROWS_GARDEN" garden >/dev/null
  assert_contains "$(cat "$NOTION_HUB_DIR/garden/index.md")" "# Notion hub index: Garden Journal" "multi named: garden header"
  assert_eq "no" "$([ -e "$NOTION_HUB_DIR/homelab/index.md" ] && echo yes || echo no)" "multi named: other hub untouched"
}

test_multi_unnamed_fails() {
  setup_multi
  local err; err="$(bash "$BUILD" "$ROWS_GARDEN" 2>&1)"
  assert_exit 1 "multi unnamed: exits 1" -- bash "$BUILD" "$ROWS_GARDEN"
  assert_contains "$err" "build-index: more than one hub; name one of: garden, homelab" "multi unnamed: lists hubs"
  assert_eq "no" "$(ls "$NOTION_HUB_DIR"/*/index.md >/dev/null 2>&1 && echo yes || echo no)" "multi unnamed: no index written"
}

test_multi_unknown_fails() {
  setup_multi
  local id err
  for id in ../x nope; do
    assert_exit 1 "multi unknown $id: exits 1" -- bash "$BUILD" "$ROWS_GARDEN" "$id"
    err="$(bash "$BUILD" "$ROWS_GARDEN" "$id" 2>&1)"
    assert_contains "$err" "Hubs: garden, homelab" "multi unknown $id: lists hubs"
  done
}

test_legacy_with_id_fails() {
  setup
  assert_exit 1 "legacy with id: exits 1" -- bash "$BUILD" "$ROWS" homelab
  assert_eq "no" "$([ -e "$NOTION_HUB_DIR/index.md" ] && echo yes || echo no)" "legacy with id: no index written"
}

test_flags; test_sort; test_escaping; test_header; test_optional
test_empty_keeps_old; test_malformed_keeps_old; test_no_config
test_missing_column; test_no_visibility_is_shared; test_string_config_values
test_multi_named; test_multi_unnamed_fails; test_multi_unknown_fails; test_legacy_with_id_fails
finish
