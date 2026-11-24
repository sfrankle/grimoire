# shellcheck shell=bash
# Shared helpers for the threads scripts.
# Source this file; it sets no options and prints nothing on success.

# The root folder holding config.json, rules.md and one folder per project.
threads_dir() {
  printf '%s\n' "${THREADS_DIR:-$HOME/.claude/threads}"
}

# Replace a leading ~ or ~/ with $HOME.
expand_tilde() {
  # The quoted ~ is a literal match on purpose: paths arrive unexpanded.
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

# Return 0 when the name is a safe folder name: lowercase letters, digits and hyphens, not starting with a hyphen.
valid_name() {
  case "$1" in
    "" | -* | *[!a-z0-9-]*) return 1 ;;
  esac
  return 0
}

# Print the text on one line: whitespace runs become one space, | becomes /, ends trimmed.
one_line() {
  printf '%s' "$1" | tr '|' '/' | tr -s '[:space:]' ' ' | sed -e 's/^ //' -e 's/ $//'
  printf '\n'
}

# Print the lines of the frontmatter block (between the first two --- lines) of a file.
# Prints nothing when the file does not start with ---.
frontmatter() {
  awk 'NR == 1 { if ($0 != "---") exit; next } $0 == "---" { exit } { print }' "$1" 2>/dev/null
}

# Print a scalar frontmatter value, empty when absent.
# Usage: front <file> <key>
front() {
  frontmatter "$1" | awk -v key="$2" '
    index($0, key ":") == 1 {
      v = substr($0, length(key) + 2)
      sub(/^[ \t]+/, "", v)
      sub(/[ \t\r]+$/, "", v)
      print v
      exit
    }'
}

# Print the items of a block list in the frontmatter, one per line.
# Usage: front_list <file> <key>
front_list() {
  frontmatter "$1" | awk -v key="$2" '
    $0 == key ":" { inlist = 1; next }
    inlist && /^[ \t]*-[ \t]/ {
      v = $0
      sub(/^[ \t]*-[ \t]+/, "", v)
      sub(/[ \t\r]+$/, "", v)
      print v
      next
    }
    inlist { exit }'
}

# Print the active project whose expanded paths contain <dir>, the longest path winning.
# A project is active unless its status is set to something other than active.
# Prints nothing when none match.
# Usage: match_project <dir>
match_project() {
  local dir="${1%/}" root state name status p best="" best_len=0
  root="$(threads_dir)"
  for state in "$root"/*/state.md; do
    [ -f "$state" ] || continue
    name="$(basename "$(dirname "$state")")"
    status="$(front "$state" status)"
    [ -z "$status" ] || [ "$status" = "active" ] || continue
    while IFS= read -r p; do
      p="$(expand_tilde "$p")"
      p="${p%/}"
      [ -n "$p" ] || continue
      case "$dir" in
        "$p" | "$p"/*)
          if [ "${#p}" -gt "$best_len" ]; then
            best="$name"
            best_len="${#p}"
          fi
          ;;
      esac
    done <<EOF_PATHS
$(front_list "$state" paths)
EOF_PATHS
  done
  [ -z "$best" ] || printf '%s\n' "$best"
  return 0
}
