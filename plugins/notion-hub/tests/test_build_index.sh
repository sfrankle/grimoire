#!/usr/bin/env bash
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname "$here")"
. "$here/assert.sh"

BUILD="$root/scripts/build-index.sh"
ROWS="$here/fixtures/rows.json"
DIRS=""

# Fresh hub dir with the example config; sets NOTION_HUB_DIR.
setup() {
  NOTION_HUB_DIR="$(mktemp -d)"
  export NOTION_HUB_DIR
  DIRS="$DIRS $NOTION_HUB_DIR"
  cp "$root/examples/config.json" "$NOTION_HUB_DIR/config.json"
}
cleanup() { for d in $DIRS; do rm -rf "$d"; done; }
trap cleanup EXIT

row() { grep -F "| $1 |" "$NOTION_HUB_DIR/index.md"; }

test_flags() {
  setup; bash "$BUILD" "$ROWS" >/dev/null
  assert_contains "$(row 'Working style')" "- private/always/ro | Working style |" "flags: private always ro"
  assert_contains "$(row 'Tax notes')" "- shared/auto/ro | Tax notes |" "flags: mixed visibility is shared, no edit is ro"
  assert_contains "$(row 'Medical notes')" "- private/ask/ro | Medical notes |" "flags: private ask ro"
  assert_contains "$(row 'Kiln firing log')" "- shared/auto/own | Kiln firing log |" "flags: shared auto own"
  assert_contains "$(row 'Studio rates')" "- shared/auto/edit | Studio rates |" "flags: shared auto edit"
  assert_contains "$(row 'Kiln firing log')" "| category: Log | keywords: kiln, glaze | https://www.notion.so/aaa1" "optional fields and url"
}

test_sort() {
  setup; bash "$BUILD" "$ROWS" >/dev/null
  local order
  order="$(grep '^- ' "$NOTION_HUB_DIR/index.md" | awk -F' [|] ' '{print $2}' | paste -sd, -)"
  assert_eq "glaze recipes,Kiln firing log,Medical notes,Studio rates,Tax notes,Working style" "$order" "rows sorted by title, case-insensitive"
}

test_escaping() {
  setup; bash "$BUILD" "$ROWS" >/dev/null
  local line seps
  line="$(grep -F 'glaze recipes' "$NOTION_HUB_DIR/index.md")"
  assert_contains "$line" "Cone 6 / satin matte" "pipe becomes slash, newline becomes space"
  seps="$(printf '%s' "$line" | grep -o ' | ' | wc -l | tr -d ' ')"
  assert_eq "3" "$seps" "glaze row keeps exactly 4 fields"
  assert_eq "1" "$(grep -c 'glaze recipes' "$NOTION_HUB_DIR/index.md")" "glaze row is one line"
}

test_header() {
  setup; local out
  out="$(bash "$BUILD" "$ROWS")"
  assert_eq "Indexed 6 pages." "$out" "prints the row count"
  assert_contains "$(cat "$NOTION_HUB_DIR/index.md")" "# Notion hub index: Field Notes" "header title"
  if grep -Eq '^Built [0-9]{4}-[0-9]{2}-[0-9]{2} \(epoch [0-9]+\)' "$NOTION_HUB_DIR/index.md"; then
    pass "built line with date and epoch"; else fail "built line with date and epoch"; fi
}

test_optional() {
  setup
  jq 'del(.fields.keywords)' "$NOTION_HUB_DIR/config.json" > "$NOTION_HUB_DIR/c.tmp" && mv "$NOTION_HUB_DIR/c.tmp" "$NOTION_HUB_DIR/config.json"
  bash "$BUILD" "$ROWS" >/dev/null
  assert_not_contains "$(cat "$NOTION_HUB_DIR/index.md")" "keywords:" "no keywords field when unmapped"
  assert_contains "$(cat "$NOTION_HUB_DIR/index.md")" "category: Log" "category still present"
}

test_empty_keeps_old() {
  setup; printf 'old index\n' > "$NOTION_HUB_DIR/index.md"
  printf '[]' > "$NOTION_HUB_DIR/empty.json"
  assert_exit 1 "empty rows exits 1" -- bash "$BUILD" "$NOTION_HUB_DIR/empty.json"
  assert_eq "old index" "$(cat "$NOTION_HUB_DIR/index.md")" "empty rows keeps index.md"
  assert_eq "" "$(ls -A "$NOTION_HUB_DIR" | grep '^\.index' )" "no temp file left behind"
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
  local k
  for k in title summary visibility; do
    setup; printf 'old index\n' > "$NOTION_HUB_DIR/index.md"
    jq --arg k "$k" '.fields[$k] = "Renamed column"' "$NOTION_HUB_DIR/config.json" > "$NOTION_HUB_DIR/c.tmp" && mv "$NOTION_HUB_DIR/c.tmp" "$NOTION_HUB_DIR/config.json"
    local err; err="$(bash "$BUILD" "$ROWS" 2>&1 >/dev/null)"
    assert_exit 1 "missing $k column exits 1" -- bash "$BUILD" "$ROWS"
    assert_contains "$err" "Renamed column" "missing $k column names the property"
    assert_eq "old index" "$(cat "$NOTION_HUB_DIR/index.md")" "missing $k column keeps index.md"
  done
}

test_string_config_values() {
  setup
  jq '.values.load.always = "Always" | .scopes.private_values = "Personal"' "$NOTION_HUB_DIR/config.json" > "$NOTION_HUB_DIR/c.tmp" && mv "$NOTION_HUB_DIR/c.tmp" "$NOTION_HUB_DIR/config.json"
  bash "$BUILD" "$ROWS" >/dev/null
  assert_contains "$(row 'Working style')" "- private/always/ro |" "string always value matches exactly"
  setup
  jq '.values.load.always = "Always on" | .scopes.private_values = "Personal stuff"' "$NOTION_HUB_DIR/config.json" > "$NOTION_HUB_DIR/c.tmp" && mv "$NOTION_HUB_DIR/c.tmp" "$NOTION_HUB_DIR/config.json"
  bash "$BUILD" "$ROWS" >/dev/null
  assert_contains "$(row 'Working style')" "- shared/auto/ro |" "string values are not substring-matched"
}

test_flags; test_sort; test_escaping; test_header; test_optional
test_empty_keeps_old; test_malformed_keeps_old; test_no_config
test_missing_column; test_string_config_values
finish
