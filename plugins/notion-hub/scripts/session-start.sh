#!/usr/bin/env bash
# SessionStart hook: prints the user's rules and the index rows that are in scope for this folder.
# Takes no arguments. Reads CLAUDE_PROJECT_DIR (falls back to PWD), NOTION_HUB_DIR and NOTION_HUB_MAX_CHARS.
# Always exits 0 and prints nothing to stderr.
#
# Output cap: Claude Code caps a hook's plain stdout at 10,000 characters.
# Over the cap the output is replaced by a file path and a 2,000 character preview.
# Source: https://code.claude.com/docs/en/hooks (checked 2026-11-24).
# The default below leaves 500 characters of headroom.
DEFAULT_MAX_CHARS=9500

exec 2>/dev/null

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

main() {
  local dir out max
  dir="$(hub_dir)"

  if [ ! -f "$dir/config.json" ]; then
    echo "Notion hub is not set up. Run /notion-setup to connect your database."
    return 0
  fi
  if ! need_jq; then
    echo "Notion hub needs jq to read its config. Install jq and start a new session."
    return 0
  fi
  if ! scope_setup "$dir/config.json"; then
    echo "Notion hub config is invalid. Run /notion-setup to fix it."
    return 0
  fi

  out=""
  [ -f "$dir/rules.md" ] && out="$(cat "$dir/rules.md")"$'\n\n'
  [ "$SCOPE_IN" = 1 ] && [ -f "$dir/rules.private.md" ] && out="$out$(cat "$dir/rules.private.md")"$'\n\n'

  if [ ! -f "$dir/index.md" ]; then
    printf '%sNo index yet. Run /notion-refresh to build it.\n' "$out"
    return 0
  fi

  # The index header is everything above the first row.
  out="$out$(awk '/^- /{exit} {print}' "$dir/index.md")"$'\n\n'
  printf '%s' "$out"

  max="${NOTION_HUB_MAX_CHARS:-$DEFAULT_MAX_CHARS}"
  case "$max" in '' | *[!0-9]*) max="$DEFAULT_MAX_CHARS" ;; esac

  # Rows go out always first, then auto, then ask.
  # Always rows are never cut; an auto or ask row that would pass the cap is left out and counted.
  scoped_rows "$dir/index.md" | awk -v budget=$((max - ${#out} - 150)) -v more="$here/scoped-index.sh" '
    { split($2, f, "/"); r = (f[2] == "always") ? 0 : (f[2] == "ask") ? 2 : 1; row[r, ++n[r]] = $0 }
    END {
      for (r = 0; r < 3; r++) for (i = 1; i <= n[r]; i++) {
        if (r > 0 && used + length(row[r, i]) + 1 > budget) { cut++; continue }
        used += length(row[r, i]) + 1
        print row[r, i]
      }
      if (cut) printf "\n%d more rows did not fit. Run %s to list every row in scope.\n", cut, more
    }'
}

main || true
exit 0
