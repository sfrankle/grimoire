#!/usr/bin/env bash
# Usage: scoped-index.sh [hub]
# With a hub id (or a single hub) it prints that hub's rows only.
# With several hubs and no id it prints each hub's rows under a "## <name> (<id>)" heading.
# A hub with a bad config or no index gets a one-line "## <id>: <reason>" and the run still exits 0.
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

need_jq || fail "jq is required but not installed."

if [ "$(hub_mode)" = multi ] && [ -z "${1:-}" ]; then
  first=1
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    id="$(hub_id "$d")"
    if [ ! -f "$d/index.md" ]; then
      reason="no index yet. Run /notion-refresh $id."
    elif ! scope_setup "$d/config.json"; then
      reason="config is invalid. Run /notion-setup to fix it."
    else
      reason=""
    fi
    [ "$first" = 1 ] || echo
    first=0
    if [ -n "$reason" ]; then
      printf '## %s: %s\n' "$id" "$reason"
    else
      printf '## %s (%s)\n' "$(jq -r '.hub.name // "Notion hub"' "$d/config.json")" "$id"
      scoped_rows "$d/index.md"
    fi
  done <<EOF_HUBS
$(hub_list)
EOF_HUBS
  exit 0
fi

dir="$(hub_resolve "${1:-}" 2>&1)" || fail "$dir"
[ -f "$dir/index.md" ] || fail "no index at $dir/index.md. Run /notion-refresh first."
scope_setup "$dir/config.json" || fail "$dir/config.json is invalid. Run /notion-setup to fix it."
scoped_rows "$dir/index.md"
