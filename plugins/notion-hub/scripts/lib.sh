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

# Return 0 when <id> is a safe hub folder name: lowercase letters, digits and dashes.
valid_hub_id() {
  [[ "$1" =~ ^[a-z0-9][a-z0-9-]*$ ]]
}

# Print the hub layout: legacy (top-level config.json), multi (hub subfolders) or none.
hub_mode() {
  local root c
  root="$(hub_dir)"
  if [ -f "$root/config.json" ]; then
    echo legacy
    return 0
  fi
  for c in "$root"/*/config.json; do
    if [ -f "$c" ]; then
      echo multi
      return 0
    fi
  done
  echo none
}

# Print one hub directory per line, sorted by name: the root in legacy mode,
# else each direct subfolder that has a config.json and a valid name.
hub_list() {
  local root c name
  root="$(hub_dir)"
  case "$(hub_mode)" in
    legacy) printf '%s\n' "$root" ;;
    multi)
      for c in "$root"/*/config.json; do
        [ -f "$c" ] || continue
        name="$(basename "$(dirname "$c")")"
        valid_hub_id "$name" && printf '%s\n' "$root/$name"
      done | LC_ALL=C sort
      ;;
  esac
  return 0
}

# Print the names of subfolders with a config.json but an invalid hub name (multi mode only).
hub_skipped() {
  local root c name
  [ "$(hub_mode)" = multi ] || return 0
  root="$(hub_dir)"
  for c in "$root"/*/config.json; do
    [ -f "$c" ] || continue
    name="$(basename "$(dirname "$c")")"
    valid_hub_id "$name" || printf '%s\n' "$name"
  done | LC_ALL=C sort
  return 0
}

# Print the hub id for a hub directory: the folder name, or nothing for the legacy root.
# Usage: hub_id <dir>
hub_id() {
  [ "$1" = "$(hub_dir)" ] || basename "$1"
}

# Print the directory of the hub named <id>.
# Usage: hub_resolve [id]
# Legacy mode accepts only an empty id. Multi mode accepts an empty id only when one hub exists.
# Prints a message to stderr and returns 1 otherwise.
hub_resolve() {
  local id="${1:-}" root dirs names count
  root="$(hub_dir)"
  case "$(hub_mode)" in
    none)
      echo "no config at $root/config.json. Run /notion-setup first." >&2
      return 1
      ;;
    legacy)
      if [ -n "$id" ]; then
        echo "unknown hub '$id'. This setup has a single hub; run without a hub name." >&2
        return 1
      fi
      printf '%s\n' "$root"
      return 0
      ;;
  esac
  dirs="$(hub_list)"
  names="$(printf '%s\n' "$dirs" | while IFS= read -r d; do [ -n "$d" ] && basename "$d"; done | paste -sd, - | sed 's/,/, /g')"
  if [ -z "$id" ]; then
    count="$(printf '%s\n' "$dirs" | grep -c .)"
    if [ "$count" = 1 ]; then
      printf '%s\n' "$dirs"
      return 0
    fi
    echo "more than one hub; name one of: $names" >&2
    return 1
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
