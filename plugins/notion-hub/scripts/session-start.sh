#!/usr/bin/env bash
# SessionStart hook: prints the user's rules and the index rows that are in scope for this folder.
# Takes no arguments. Reads CLAUDE_PROJECT_DIR (falls back to PWD), NOTION_HUB_DIR and NOTION_HUB_MAX_CHARS.
# Always exits 0 and prints nothing to stderr.
#
# A hub whose hub.show_in does not match this folder prints one pointer line and its in-scope always rows.
# Every other hub prints its heading, rules, index header and rows.
#
# Output cap: Claude Code caps a hook's plain stdout at 10,000 characters.
# Over the cap the output is replaced by a file path and a 2,000 character preview.
# Source: https://code.claude.com/docs/en/hooks (checked 2026-11-24).
# The default below leaves 500 characters of headroom; every hub shares it.
DEFAULT_MAX_CHARS=9500

exec 2>/dev/null

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

# The hub parts below write tagged records, one per output line: <block>\t<kind>\t<text>.
# <block> groups lines that print together (0 is the top of the output, then one per hub).
# <kind> is F for fixed text, 0 for an always row, 1 for an auto row and 2 for an ask row.

# fixed <block> <text>: one F record per line of text.
fixed() {
  local line
  while IFS= read -r line; do printf '%s\tF\t%s\n' "$1" "$line"; done <<<"$2"
}

# fixed_file <block> <file>: one F record per line of the file, then a blank one.
fixed_file() {
  awk -v b="$1" '{ print b "\tF\t" $0 } END { print b "\tF\t" }' "$2"
}

# rows <block> loaded|pointer <index.md>: the in-scope rows as records (call scope_setup first).
# Pointer mode keeps only the always rows.
rows() {
  scoped_rows "$3" | awk -v b="$1" -v mode="$2" '
    {
      split($2, f, "/")
      k = (f[2] == "always") ? "0" : (f[2] == "ask") ? "2" : "1"
      if (mode == "pointer" && k != "0") next
      print b "\t" k "\t" $0
    }'
}

# A hub shown in this folder: heading, rules, private rules, index header, rows.
# Usage: loaded_hub <block> <dir> <id> <name>
loaded_hub() {
  local b="$1" d="$2" id="$3" name="$4"
  fixed "$b" "## Notion hub: $name ($id)"
  fixed "$b" ""
  [ -f "$d/rules.md" ] && fixed_file "$b" "$d/rules.md"
  [ "$SCOPE_IN" = 1 ] && [ -f "$d/rules.private.md" ] && fixed_file "$b" "$d/rules.private.md"
  if [ ! -f "$d/index.md" ]; then
    fixed "$b" "No index yet for $id. Run /notion-refresh $id."
    return 0
  fi
  # The index header is everything above the first row.
  fixed "$b" "$(awk '/^- /{exit} {print}' "$d/index.md")"
  fixed "$b" ""
  rows "$b" loaded "$d/index.md"
}

# A hub not shown in this folder: one pointer line, then its in-scope always rows.
# Usage: pointer_hub <block> <dir> <id> <name>
pointer_hub() {
  local b="$1" d="$2" id="$3" name="$4" pointer
  pointer="$(jq -r '(.hub.pointer | strings) // empty' "$d/config.json")"
  pointer="${pointer//$'\n'/ }"
  [ -n "$pointer" ] || pointer="$name"
  case "$pointer" in *[.!?]) ;; *) pointer="$pointer." ;; esac
  fixed "$b" "Notion hub $name ($id): $pointer Not loaded in this folder; run $here/scoped-index.sh $id to list it."
  [ -f "$d/index.md" ] && rows "$b" pointer "$d/index.md"
  return 0
}

# Usage: hub <block> <dir>   (call scope_setup on its config first)
hub() {
  local id name
  id="$(hub_id "$2")"
  name="$(hub_name "$2")"
  if shown_here "$2/config.json"; then
    loaded_hub "$1" "$2" "$id" "$name"
  else
    pointer_hub "$1" "$2" "$id" "$name"
  fi
}

# Every hub: the old-layout note, routing rules, ignored folders, then each hub in name order.
all_hubs() {
  local root d note b=0
  root="$(hub_dir)"
  note="$(old_layout_note)"
  [ -n "$note" ] && fixed 0 "Notion hub: $note"
  [ -f "$root/rules.md" ] && fixed_file 0 "$root/rules.md"
  while IFS= read -r d; do
    [ -n "$d" ] && fixed 0 "Notion hub folder '$d' ignored: hub ids are lowercase letters, digits and dashes."
  done <<EOF_SKIPPED
$(hub_skipped)
EOF_SKIPPED
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    b=$((b + 1))
    if scope_setup "$d/config.json"; then
      hub "$b" "$d"
    else
      fixed "$b" "Notion hub $(hub_id "$d"): config is invalid. Run /notion-setup to fix it."
    fi
  done <<EOF_HUBS
$(hub_list)
EOF_HUBS
}

# Print the records within <max> characters.
# Fixed text always prints. Rows are admitted from one shared pool, in this order:
# always rows (never cut), auto rows, ask rows.
# A row that would pass the cap is left out and counted; kept rows print under their own block.
# Usage: ... | fit <max>
fit() {
  awk -v max="$1" -v more="$here/scoped-index.sh" '
    BEGIN {
      note = "\n%d more rows did not fit. Run %s to list every row in scope.\n"
      # Room for the closing line, with up to five digits of count.
      reserve = length(sprintf(note, 99999, more))
    }
    {
      # Split on the first two tabs only: text from rules files may hold tabs of its own.
      t = index($0, "\t"); b = substr($0, 1, t - 1); rest = substr($0, t + 1)
      t = index(rest, "\t"); k = substr(rest, 1, t - 1); text = substr(rest, t + 1)
      if (!(b in seen)) {
        seen[b] = 1; order[++blocks] = b
        if (blocks > 1) used++  # the blank line that may separate blocks
      }
      if (k == "F") { fix[b, ++nfix[b]] = text; used += length(text) + 1 }
      else { n++; kind[n] = k; block[n] = b; row[n] = text }
    }
    END {
      split("0 1 2", pri, " ")
      for (p = 1; p <= 3; p++) for (i = 1; i <= n; i++) {
        if (kind[i] != pri[p]) continue
        if (pri[p] != "0" && used + length(row[i]) + 1 > max - reserve) { cut++; continue }
        used += length(row[i]) + 1
        keep[i] = 1
      }
      for (j = 1; j <= blocks; j++) {
        b = order[j]
        if (printed && last != "") print ""
        for (i = 1; i <= nfix[b]; i++) { print fix[b, i]; last = fix[b, i]; printed = 1 }
        for (p = 1; p <= 3; p++) for (i = 1; i <= n; i++)
          if (keep[i] && block[i] == b && kind[i] == pri[p]) { print row[i]; last = row[i]; printed = 1 }
      }
      if (cut) printf note, cut, more
    }'
}

main() {
  local max note
  if [ -z "$(hub_folders)" ]; then
    note="$(old_layout_note)"
    echo "${note:+Notion hub: $note}${note:-Notion hub is not set up. Run /notion-setup to connect your database.}"
    return 0
  fi
  if ! need_jq; then
    echo "Notion hub needs jq to read its config. Install jq and start a new session."
    return 0
  fi

  max="${NOTION_HUB_MAX_CHARS:-$DEFAULT_MAX_CHARS}"
  case "$max" in '' | *[!0-9]*) max="$DEFAULT_MAX_CHARS" ;; esac
  all_hubs | fit "$max"
}

main || true
exit 0
