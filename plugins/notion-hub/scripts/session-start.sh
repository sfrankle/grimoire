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
# shellcheck source=lib.sh
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

  scope_setup "$config" || {
    echo "Notion hub config is not valid JSON. Run /notion-setup to fix it."
    return 0
  }
  local in_scope="$SCOPE_IN" line

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
    if [ "$age" = 1 ]; then age_note="Index is 1 day old."; else age_note="Index is $age days old."; fi
    if [ "$age" -gt "$STALE_DAYS" ]; then
      age_note="$age_note Run /notion-refresh to update it."
    fi
  fi
  out="$out$header"$'\n'
  [ -n "$age_note" ] && out="$out$age_note"$'\n'
  out="$out"$'\n'

  local rows
  rows="$(scoped_rows "$index")"

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

  # Cut ask rows then auto rows, each from the end, until the output fits.
  # Row lengths are summed once, so the cost is linear in the number of rows.
  local cut=0 warn="" sum=0 fixed next=0 body=""
  local -a len=() order=()
  for ((i = 0; i < n; i++)); do
    len[i]=$(( ${#r_text[i]} + 1 ))
    sum=$((sum + len[i]))
  done
  for ((i = n - 1; i >= 0; i--)); do [ "${r_load[i]}" = "ask" ] && order[${#order[@]}]=$i; done
  for ((i = n - 1; i >= 0; i--)); do [ "${r_load[i]}" = "auto" ] && order[${#order[@]}]=$i; done
  fixed=${#out}
  [ -n "$always" ] && fixed=$((fixed + 1 + ${#always}))
  while [ $((fixed + sum + ${#warn})) -gt "$max" ] && [ "$next" -lt "${#order[@]}" ]; do
    i=${order[next]}
    r_keep[i]=0
    sum=$((sum - len[i]))
    next=$((next + 1))
    cut=$((cut + 1))
    warn="Warning: $cut index rows cut to fit session start. Shorten summaries or move pages to the ask load value."$'\n'
  done
  if [ "$cut" = 0 ] && [ $((fixed + sum)) -gt "$max" ]; then
    warn="Warning: rules and always rows alone are over the $max character session start cap. Shorten them."$'\n'
  fi
  for ((i = 0; i < n; i++)); do
    [ "${r_keep[i]}" = 1 ] && body="$body${r_text[i]}"$'\n'
  done
  out="$out$body$warn"
  [ -n "$always" ] && out="$out"$'\n'"$always"
  printf '%s' "$out"
}

main || true
exit 0
