#!/usr/bin/env bash
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=assert.sh
. "$here/assert.sh"
# shellcheck source=../scripts/lib.sh
. "$ROOT/scripts/lib.sh"

names() { while IFS= read -r d; do [ -n "$d" ] && basename "$d"; done | paste -sd, -; }


test_list_sorted() {
  setup_multi
  assert_eq "garden,homelab" "$(hub_list | names)" "list: sorted by name"
}

test_list_skips_bad_names() {
  setup_multi
  add_bad_hub
  assert_eq "garden,homelab" "$(hub_list | names)" "bad name: absent from list"
  assert_eq "Bad Name" "$(hub_skipped)" "bad name: reported as skipped"
}


test_resolve() {
  local out rc
  setup; rm "$HUB/config.json"
  out="$(hub_resolve "" 2>&1)"; rc=$?
  assert_eq "1" "$rc" "resolve none: fails"
  assert_contains "$out" "no hubs in $NOTION_HUB_DIR. Run /notion-setup first." "resolve none: message"
  setup_multi
  assert_eq "$NOTION_HUB_DIR/garden" "$(hub_resolve garden)" "resolve multi: garden"
  assert_eq "garden" "$(hub_id "$NOTION_HUB_DIR/garden")" "resolve multi: id is folder name"
  out="$(hub_resolve "" 2>&1)"; rc=$?
  assert_eq "1" "$rc" "resolve multi: empty id fails"
  assert_contains "$out" "more than one hub; name one of: garden, homelab" "resolve multi: empty id message"
  out="$(hub_resolve nope 2>&1)"; rc=$?
  assert_eq "1" "$rc" "resolve multi: unknown id fails"
  assert_contains "$out" "unknown hub 'nope'. Hubs: garden, homelab" "resolve multi: unknown id message"
  assert_exit 1 "resolve multi: path-like id fails" -- hub_resolve ../x
  rm -rf "$NOTION_HUB_DIR/garden"
  assert_eq "$NOTION_HUB_DIR/homelab" "$(hub_resolve "")" "resolve multi: empty id ok with one hub"
  setup; mv "$HUB/config.json" "$NOTION_HUB_DIR/config.json"
  out="$(hub_resolve "" 2>&1)"; rc=$?
  assert_eq "1" "$rc" "resolve old layout: fails"
  assert_contains "$out" "$NOTION_HUB_DIR/config.json is the old single-hub layout" "resolve old layout: says how to move it"
}

test_resolve_no_valid_hubs() {
  local out rc
  setup_multi
  rm -rf "$NOTION_HUB_DIR/garden" "$NOTION_HUB_DIR/homelab"
  add_bad_hub
  out="$(hub_resolve "" 2>&1)"; rc=$?
  assert_eq "1" "$rc" "resolve no valid hubs: fails"
  assert_contains "$out" "no hubs in $NOTION_HUB_DIR." "resolve no valid hubs: message"
  assert_not_contains "$out" "more than one hub" "resolve no valid hubs: not the many-hubs message"
}

test_valid_id() {
  assert_exit 0 "valid id: plain" -- valid_hub_id home-lab2
  assert_exit 1 "valid id: uppercase" -- valid_hub_id Home
  assert_exit 1 "valid id: leading dash" -- valid_hub_id -x
  assert_exit 1 "valid id: empty" -- valid_hub_id ""
}

test_shown_here() {
  setup_multi
  local g="$NOTION_HUB_DIR/garden/config.json" h="$NOTION_HUB_DIR/homelab/config.json"
  CLAUDE_PROJECT_DIR="$HOME/garden/beds" shown_here "$g"; assert_eq "0" "$?" "shown: garden under ~/garden/beds"
  CLAUDE_PROJECT_DIR="$HOME/garden" shown_here "$g"; assert_eq "0" "$?" "shown: garden at ~/garden"
  CLAUDE_PROJECT_DIR="$HOME/gardening" shown_here "$g"; assert_eq "1" "$?" "shown: garden not in ~/gardening"
  CLAUDE_PROJECT_DIR="$HOME/code" shown_here "$h"; assert_eq "0" "$?" "shown: homelab anywhere"
}

test_path_string() {
  setup_multi
  local g="$NOTION_HUB_DIR/garden/config.json"
  patch_hub garden '.hub.show_in = "~/garden/"'
  CLAUDE_PROJECT_DIR="$HOME/garden/beds" shown_here "$g"; assert_eq "0" "$?" "string show_in: matches under it"
  CLAUDE_PROJECT_DIR="$HOME/other" shown_here "$g"; assert_eq "1" "$?" "string show_in: other folder hidden"
}

test_list_sorted; test_list_skips_bad_names; test_resolve; test_resolve_no_valid_hubs; test_valid_id; test_shown_here; test_path_string
finish
