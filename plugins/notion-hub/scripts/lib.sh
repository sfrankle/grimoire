# Shared helpers for the notion-hub scripts.
# Source this file; it sets no options and prints nothing.

# The directory holding config.json, rules.md and index.md.
hub_dir() {
  printf '%s\n' "${NOTION_HUB_DIR:-$HOME/.claude/notion-hub}"
}

# Replace a leading ~ or ~/ with $HOME.
expand_tilde() {
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
