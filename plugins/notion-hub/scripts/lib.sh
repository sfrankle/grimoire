# shellcheck shell=bash
# Shared helpers for the notion-hub scripts.
# Source this file; it sets no options and prints nothing.

# The directory holding config.json, rules.md and index.md.
hub_dir() {
  printf '%s\n' "${NOTION_HUB_DIR:-$HOME/.claude/notion-hub}"
}

# Replace a leading ~ or ~/ with $HOME.
expand_tilde() {
  # The quoted ~ is a literal match on purpose: config paths arrive unexpanded.
  # shellcheck disable=SC2088
  case "$1" in
    "~") printf '%s\n' "$HOME" ;;
    "~/"*) printf '%s\n' "$HOME/${1#"~/"}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

# Return 1 when jq is not installed.
need_jq() {
  command -v jq >/dev/null 2>&1
}

# Decide whether the current folder may see private rows.
# Usage: scope_setup <config.json>
# Sets SCOPE_IN=1 when CLAUDE_PROJECT_DIR (or PWD) is inside a scopes.private_paths folder.
# Sets SCOPE_EVERYWHERE=1 when scopes.always_shows_everywhere is true.
# Returns 1 when the config is not a JSON object, 2 when scopes is set but is not an object.
# A bad scopes shape is an error rather than "no scopes", so private rows never leak by default.
scope_setup() {
  local settings first=1 line p project
  SCOPE_IN=0
  SCOPE_EVERYWHERE=0
  # First line: the always-shows-everywhere flag (or bad_scopes), then one private path per line.
  # private_paths may be one string or a list.
  settings="$(jq -r '
    if type != "object" then error("not an object")
    elif .scopes != null and (.scopes | type) != "object" then "bad_scopes"
    else
      ((.scopes.always_shows_everywhere == true) | tostring),
      ((.scopes.private_paths // []) | if type == "array" then .[] else . end | strings)
    end' "$1" 2>/dev/null)" || return 1
  [ "$settings" = "bad_scopes" ] && return 2
  project="${CLAUDE_PROJECT_DIR:-$PWD}"
  project="${project%/}"
  while IFS= read -r line; do
    if [ "$first" = 1 ]; then
      first=0
      [ "$line" = "true" ] && SCOPE_EVERYWHERE=1
      continue
    fi
    p="$(expand_tilde "$line")"
    p="${p%/}"
    [ -n "$p" ] || continue
    case "$project" in
      "$p" | "$p"/*) SCOPE_IN=1 ;;
    esac
  done <<EOF_SETTINGS
$settings
EOF_SETTINGS
  return 0
}

# Print the index rows this folder may see: shared rows, private rows in a private folder,
# and private always rows when always_shows_everywhere is on.
# Usage: scoped_rows <index.md>   (call scope_setup first)
scoped_rows() {
  awk -v scope="$SCOPE_IN" -v every="$SCOPE_EVERYWHERE" '
    /^- / {
      split($2, f, "/")
      if (f[1] != "private" || scope == 1 || (every == 1 && f[2] == "always")) print
    }' "$1"
}
