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
STALE_DAYS=7

exec 2>/dev/null

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/lib.sh"

main() {
  local dir config rules priv_rules index
  dir="$(hub_dir)"
  config="$dir/config.json"
  rules="$dir/rules.md"
  priv_rules="$dir/rules.private.md"
  index="$dir/index.md"

  if [ ! -f "$config" ]; then
    echo "Notion hub is not set up. Run /notion-setup to connect your database."
    return 0
  fi
  if ! need_jq; then
    echo "Notion hub needs jq to read its config. Install jq and start a new session."
    return 0
  fi

  # One jq call: first line is the always-shows-everywhere flag, then one private path per line.
  local settings
  settings="$(jq -r '
    if type == "object" then
      ((.scopes.always_shows_everywhere == true) | tostring),
      ((.scopes.private_paths // []) | if type == "array" then .[] | strings else empty end)
    else error("not an object") end' "$config")" || {
    echo "Notion hub config is not valid JSON. Run /notion-setup to fix it."
    return 0
  }

  local everywhere=0 first=1 p project in_scope=0 line
  project="${CLAUDE_PROJECT_DIR:-$PWD}"
  project="${project%/}"
  while IFS= read -r line; do
    if [ "$first" = 1 ]; then
      first=0
      [ "$line" = "true" ] && everywhere=1
      continue
    fi
    p="$(expand_tilde "$line")"
    p="${p%/}"
    [ -n "$p" ] || continue
    case "$project" in
      "$p" | "$p"/*) in_scope=1 ;;
    esac
  done <<EOF_SETTINGS
$settings
EOF_SETTINGS

  local out=""
  if [ -f "$rules" ]; then out="$(cat "$rules")"$'\n\n'; fi
  if [ "$in_scope" = 1 ] && [ -f "$priv_rules" ]; then out="$out$(cat "$priv_rules")"$'\n\n'; fi

  if [ ! -f "$index" ]; then
    printf '%s%s\n' "$out" "No index yet. Run /notion-refresh to build it."
    return 0
  fi

  # Index header (everything above the first row) and the age line.
  local header epoch now age age_note=""
  header="$(awk '/^- /{exit} {print}' "$index")"
  epoch="$(printf '%s\n' "$header" | sed -n 's/^Built .*(epoch \([0-9][0-9]*\)).*/\1/p' | head -n 1)"
  if [ -n "$epoch" ]; then
    now="$(date +%s)"
    age=$(( (now - epoch) / 86400 ))
    if [ "$age" -ge "$STALE_DAYS" ]; then
      age_note="Index is $age days old. Run /notion-refresh to update it."
    fi
  fi
  out="$out$header"$'\n'
  [ -n "$age_note" ] && out="$out$age_note"$'\n'
  out="$out"$'\n'

  # Keep rows in scope: shared rows, private rows in a private folder, and always rows if opted in.
  local rows
  rows="$(awk -v scope="$in_scope" -v every="$everywhere" '
    /^- / {
      split($2, f, "/")
      if (f[1] != "private" || scope == 1 || (every == 1 && f[2] == "always")) print
    }' "$index")"

  local max="${NOTION_HUB_MAX_CHARS:-$DEFAULT_MAX_CHARS}"
  case "$max" in '' | *[!0-9]*) max="$DEFAULT_MAX_CHARS" ;; esac

  # Rows as arrays: text, load flag, kept marker.
  local -a r_text=() r_load=() r_keep=()
  local n=0 flags rest
  if [ -n "$rows" ]; then
    while IFS= read -r line; do
      flags="${line#- }"
      flags="${flags%% *}"
      rest="${flags#*/}"
      r_text[n]="$line"
      r_load[n]="${rest%%/*}"
      r_keep[n]=1
      n=$((n + 1))
    done <<EOF_ROWS
$rows
EOF_ROWS
  fi

  # The always-fetch list covers rows that are never cut, so it is fixed up front.
  local always="" title url i
  for ((i = 0; i < n; i++)); do
    if [ "${r_load[i]}" = "always" ]; then
      rest="${r_text[i]#*" | "}"
      title="${rest%%" | "*}"
      url="${r_text[i]##*" | "}"
      always="$always- $title: $url"$'\n'
    fi
  done
  [ -n "$always" ] && always="Fetch before your first answer:"$'\n'"$always"

  # Assemble; cut ask rows then auto rows, each from the end, until the output fits.
  local cut=0 body warn total
  local -a order=()
  for ((i = n - 1; i >= 0; i--)); do [ "${r_load[i]}" = "ask" ] && order[${#order[@]}]=$i; done
  for ((i = n - 1; i >= 0; i--)); do [ "${r_load[i]}" = "auto" ] && order[${#order[@]}]=$i; done
  local next=0
  while :; do
    body=""
    for ((i = 0; i < n; i++)); do
      [ "${r_keep[i]}" = 1 ] && body="$body${r_text[i]}"$'\n'
    done
    warn=""
    [ "$cut" -gt 0 ] && warn="Warning: $cut index rows cut to fit session start. Run /notion-refresh or trim the hub."$'\n'
    total="$out$body$warn"
    [ -n "$always" ] && total="$total"$'\n'"$always"
    if [ "${#total}" -le "$max" ] || [ "$next" -ge "${#order[@]}" ]; then break; fi
    r_keep[${order[next]}]=0
    next=$((next + 1))
    cut=$((cut + 1))
  done
  printf '%s' "$total"
}

main || true
exit 0
