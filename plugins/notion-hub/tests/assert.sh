# shellcheck shell=bash disable=SC2034  # HOOK, SCOPED and friends are read by the files that source this.
# Test helpers. Source this file, then call finish at the end of the test file.
FAILS=0

pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1" >&2; FAILS=$((FAILS + 1)); }

assert_eq() {
  if [ "$1" = "$2" ]; then pass "$3"; else
    fail "$3"; printf '  expected: %s\n  actual:   %s\n' "$1" "$2" >&2
  fi
}

assert_contains() {
  case "$1" in *"$2"*) pass "$3" ;; *) fail "$3"; printf '  missing: %s\n  in: %s\n' "$2" "$1" >&2 ;; esac
}

assert_not_contains() {
  case "$1" in *"$2"*) fail "$3"; printf '  unexpected: %s\n  in: %s\n' "$2" "$1" >&2 ;; *) pass "$3" ;; esac
}

# assert_exit <code> <name> -- <cmd...>
assert_exit() {
  local want="$1" name="$2"
  shift 3
  "$@" >/dev/null 2>&1
  local got=$?
  if [ "$got" = "$want" ]; then pass "$name"; else fail "$name"; printf '  expected exit %s, got %s\n' "$want" "$got" >&2; fi
}

finish() { [ "$FAILS" -eq 0 ]; exit $?; }

# Shared sandbox for the notion-hub tests.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/scripts/build-index.sh"
HOOK="$ROOT/scripts/session-start.sh"
SCOPED="$ROOT/scripts/scoped-index.sh"
ROWS="$ROOT/tests/fixtures/rows.json"
TMPS=""

# setup: fresh HOME and hub dir holding the example config; sets T, HOME and NOTION_HUB_DIR.
setup() {
  T="$(mktemp -d)"
  TMPS="$TMPS $T"
  export HOME="$T/home" NOTION_HUB_DIR="$T/hub"
  mkdir -p "$HOME" "$NOTION_HUB_DIR"
  cp "$ROOT/examples/config.json" "$NOTION_HUB_DIR/config.json"
  unset NOTION_HUB_MAX_CHARS
}
# Called from the EXIT trap below.
# shellcheck disable=SC2329
cleanup() { for d in $TMPS; do rm -rf "$d"; done; }
trap cleanup EXIT

build() { bash "$BUILD" "${1:-$ROWS}" >/dev/null; }

# patch_config '<jq filter>': rewrite the sandbox config in place.
patch_config() { jq "$1" "$NOTION_HUB_DIR/config.json" > "$T/c" && mv "$T/c" "$NOTION_HUB_DIR/config.json"; }
