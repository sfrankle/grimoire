# shellcheck shell=bash
# Shared helpers for the notion-hub scripts.
# Source this file; it sets no options and prints nothing.

# The hub root: routing rules.md plus one folder per hub.
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

# Return 0 when <id> is a safe hub folder name: lowercase letters, digits and dashes.
valid_hub_id() {
  [[ "$1" =~ ^[a-z0-9][a-z0-9-]*$ ]]
}

# Print each direct subfolder of the root that has a config.json, one path per line, sorted.
hub_folders() {
  local c
  for c in "$(hub_dir)"/*/config.json; do
    [ -f "$c" ] && printf '%s\n' "${c%/config.json}"
  done | LC_ALL=C sort
  return 0
}

# Print one hub directory per line, sorted by name: each hub folder with a valid name.
hub_list() {
  local d
  hub_folders | while IFS= read -r d; do valid_hub_id "${d##*/}" && printf '%s\n' "$d"; done
  return 0
}

# Print the names of hub folders whose name is not a valid hub id.
hub_skipped() {
  local d
  hub_folders | while IFS= read -r d; do valid_hub_id "${d##*/}" || printf '%s\n' "${d##*/}"; done
  return 0
}

# Print a line about a top-level config.json, the single-hub layout from 0.1.0, or nothing.
old_layout_note() {
  local root
  root="$(hub_dir)"
  [ -f "$root/config.json" ] || return 0
  printf '%s\n' "$root/config.json is the old single-hub layout: move it, with rules.md, rules.private.md and index.md, into $root/<hub id>/."
}

# Print the hub id for a hub directory: its folder name.
# Usage: hub_id <dir>
hub_id() {
  printf '%s\n' "${1##*/}"
}

# Print a hub's display name on one line: hub.name, else its id.
# Usage: hub_name <dir>
hub_name() {
  local name
  name="$(jq -r '(.hub.name | strings) // empty' "$1/config.json" 2>/dev/null)"
  name="${name//$'\n'/ }"
  printf '%s\n' "${name:-$(hub_id "$1")}"
}

# Print the directory of the hub named <id>.
# Usage: hub_resolve [id]
# An empty id is accepted only when exactly one hub exists.
# Prints a message to stderr and returns 1 otherwise.
hub_resolve() {
  local id="${1:-}" root dirs names note
  root="$(hub_dir)"
  dirs="$(hub_list)"
  if [ -z "$dirs" ]; then
    note="$(old_layout_note)"
    echo "no hubs in $root. ${note:+$note }Run /notion-setup first." >&2
    return 1
  fi
  names="$(printf '%s\n' "$dirs" | sed 's|.*/||' | paste -sd, - | sed 's/,/, /g')"
  if [ -z "$id" ]; then
    case "$dirs" in
      *$'\n'*) echo "more than one hub; name one of: $names" >&2; return 1 ;;
    esac
    printf '%s\n' "$dirs"
    return 0
  fi
  if valid_hub_id "$id" && [ -f "$root/$id/config.json" ]; then
    printf '%s\n' "$root/$id"
    return 0
  fi
  echo "unknown hub '$id'. Hubs: $names" >&2
  return 1
}

# Return 0 when CLAUDE_PROJECT_DIR (or PWD) is at or under a path the jq filter yields.
# The filter may yield one string or an array of strings; ~ is expanded, a trailing slash is ignored.
# Usage: path_in_list <jq filter> <config.json>
path_in_list() {
  local paths line p project
  paths="$(jq -r "$1 // [] | if type == \"array\" then .[] else . end | strings" "$2" 2>/dev/null)" || return 1
  project="${CLAUDE_PROJECT_DIR:-$PWD}"
  project="${project%/}"
  while IFS= read -r line; do
    p="$(expand_tilde "$line")"
    p="${p%/}"
    [ -n "$p" ] || continue
    case "$project" in
      "$p" | "$p"/*) return 0 ;;
    esac
  done <<EOF_PATHS
$paths
EOF_PATHS
  return 1
}

# Return 0 when this hub shows in the current folder: show_in absent or null, or a match.
# Usage: shown_here <config.json>
shown_here() {
  [ "$(jq -r '(.hub.show_in // null) == null' "$1" 2>/dev/null)" = true ] && return 0
  path_in_list '.hub.show_in' "$1"
}

# Decide whether the current folder may see private rows.
# Usage: scope_setup <config.json>
# Sets SCOPE_IN=1 when CLAUDE_PROJECT_DIR (or PWD) is inside a scopes.private_paths folder.
# Sets SCOPE_EVERYWHERE=1 when scopes.always_shows_everywhere is true.
# Returns 1 when the config or its scopes is not a JSON object, so private rows never leak by default.
scope_setup() {
  local every
  SCOPE_IN=0
  SCOPE_EVERYWHERE=0
  every="$(jq -r '
    if type != "object" or ((.scopes | type) | IN("object", "null") | not) then error("bad config")
    else (.scopes.always_shows_everywhere == true) end' "$1" 2>/dev/null)" || return 1
  [ "$every" = true ] && SCOPE_EVERYWHERE=1
  path_in_list '.scopes.private_paths' "$1" && SCOPE_IN=1
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
