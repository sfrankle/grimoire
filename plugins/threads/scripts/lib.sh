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

# Return 0 when the name is a safe folder name (characters spelled out, since ranges follow the locale): lowercase letters, digits and hyphens, not starting with a hyphen.
valid_name() {
  case "$1" in
    "" | -* | *[!abcdefghijklmnopqrstuvwxyz0123456789-]*) return 1 ;;
  esac
  return 0
}

# Print the text on one line: whitespace runs become one space, | becomes /, ends trimmed.
one_line() {
  printf '%s' "$1" | tr '|' '/' | tr -s '[:space:]' ' ' | sed -e 's/^ //' -e 's/ $//'
  printf '\n'
}

# Print the lines of the frontmatter block (between the first two --- lines) of a file.
# A trailing carriage return is dropped from every line, so CRLF files read the same as LF ones.
# Prints nothing when the file does not start with ---.
frontmatter() {
  awk '{ sub(/\r$/, "") } NR == 1 { if ($0 !~ /^---[ \t]*$/) exit; next } /^---[ \t]*$/ { exit } { print }' "$1" 2>/dev/null
}

# Return 0 when the file opens with a --- line and a later --- line closes the block.
has_frontmatter() {
  awk '{ sub(/\r$/, "") } NR == 1 { if ($0 !~ /^---[ \t]*$/) exit 1; next } /^---[ \t]*$/ { found = 1; exit } END { exit !found }' "$1" 2>/dev/null
}

# Return 0 when the state.md is active: status unset or set to active.
is_active() {
  local status
  status="$(front "$1" status)"
  [ -z "$status" ] || [ "$status" = "active" ]
}

# Return 0 when a state.md can be listed: valid folder name, closed frontmatter, active.
usable() {
  valid_name "$(basename "$(dirname "$1")")" && has_frontmatter "$1" && is_active "$1"
}

# Awk function shared by front and front_list: trims a value and drops one pair of surrounding quotes.
AWK_CLEAN='
  function clean(v) {
    sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
    if (v ~ /^".*"$/ || v ~ /^\047.*\047$/) v = substr(v, 2, length(v) - 2)
    return v
  }'

# Print a scalar frontmatter value, empty when absent.
# Usage: front <file> <key>
front() {
  frontmatter "$1" | awk -v key="$2" "$AWK_CLEAN"'
    index($0, key ":") == 1 { print clean(substr($0, length(key) + 2)); exit }'
}

# Print the items of a frontmatter list, one per line.
# Reads a block list ("key:" then "  - item" lines), an inline list ("key: [a, b]") or a single scalar ("key: a").
# Usage: front_list <file> <key>
front_list() {
  frontmatter "$1" | awk -v key="$2" "$AWK_CLEAN"'
    !inlist && index($0, key ":") == 1 {
      v = clean(substr($0, length(key) + 2))
      if (v == "") { inlist = 1; next }
      if (v ~ /^\[.*\]$/) {
        n = split(substr(v, 2, length(v) - 2), items, ",")
        for (i = 1; i <= n; i++) { item = clean(items[i]); if (item != "") print item }
      } else print v
      exit
    }
    inlist && /^[ \t]*-[ \t]/ { v = $0; sub(/^[ \t]*-/, "", v); print clean(v); next }
    inlist && /^[ \t]*$/ { next }
    inlist { exit }'
}

# Print the physical path of an existing folder, or the path unchanged when it does not exist.
physical_dir() {
  (cd "$1" 2>/dev/null && pwd -P) || printf '%s\n' "$1"
}

# Print the active project whose expanded paths contain <dir>, the longest path winning.
# Paths are compared as written and again with symlinks resolved, so /tmp and /private/tmp match.
# Projects that are not usable are skipped.
# Prints nothing when none match.
# Usage: match_project <dir>
match_project() {
  local dir="${1%/}" rdir root state name p rp best="" best_len=0
  rdir="$(physical_dir "$dir")"
  root="$(threads_dir)"
  for state in "$root"/*/state.md; do
    [ -f "$state" ] || continue
    usable "$state" || continue
    name="$(basename "$(dirname "$state")")"
    while IFS= read -r p; do
      p="$(expand_tilde "$p")"
      p="${p%/}"
      [ -n "$p" ] || continue
      rp="$(physical_dir "$p")"
      case "$dir" in
        "$p" | "$p"/*) ;;
        *) case "$rdir" in "$rp" | "$rp"/*) ;; *) continue ;; esac ;;
      esac
      if [ "${#p}" -gt "$best_len" ]; then
        best="$name"
        best_len="${#p}"
      fi
    done <<EOF_PATHS
$(front_list "$state" paths)
EOF_PATHS
  done
  [ -z "$best" ] || printf '%s\n' "$best"
  return 0
}
