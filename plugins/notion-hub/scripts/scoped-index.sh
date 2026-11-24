#!/usr/bin/env bash
# Usage: scoped-index.sh
# Prints the index rows this folder is allowed to see, using the same scope rules as the session-start hook.
# Reads CLAUDE_PROJECT_DIR (falls back to PWD) and NOTION_HUB_DIR.
# Skills read the index through this script so private rows never reach a shared folder.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

fail() {
  printf 'scoped-index: %s\n' "$1" >&2
  exit 1
}

dir="$(hub_dir)"
need_jq || fail "jq is required but not installed."
[ -f "$dir/config.json" ] || fail "no config at $dir/config.json. Run /notion-setup first."
[ -f "$dir/index.md" ] || fail "no index at $dir/index.md. Run /notion-refresh first."
scope_setup "$dir/config.json" || fail "$dir/config.json is invalid. Run /notion-setup to fix it."
scoped_rows "$dir/index.md"
