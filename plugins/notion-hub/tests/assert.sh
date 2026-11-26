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
ROWS_GARDEN="$ROOT/tests/fixtures/rows-garden.json"
TMPS=""

# setup: fresh HOME and hub root holding one hub, homelab, with the example config.
# Sets T, HOME, NOTION_HUB_DIR (the root) and HUB (the homelab folder).
setup() {
  T="$(mktemp -d)"
  TMPS="$TMPS $T"
  export HOME="$T/home" NOTION_HUB_DIR="$T/hub"
  HUB="$NOTION_HUB_DIR/homelab"
  mkdir -p "$HOME" "$HUB"
  cp "$ROOT/examples/hubs/homelab/config.json" "$HUB/config.json"
  unset NOTION_HUB_MAX_CHARS
}
# setup_multi: fresh HOME and hub root holding homelab/ and garden/ plus the routing rules.
setup_multi() {
  setup
  local h
  for h in homelab garden; do
    mkdir -p "$NOTION_HUB_DIR/$h"
    cp "$ROOT/examples/hubs/$h/config.json" "$ROOT/examples/hubs/$h/rules.md" "$NOTION_HUB_DIR/$h/"
  done
  cp "$ROOT/examples/rules.md" "$NOTION_HUB_DIR/rules.md"
}

# Called from the EXIT trap below.
# shellcheck disable=SC2329
cleanup() { for d in $TMPS; do rm -rf "$d"; done; }
trap cleanup EXIT

# build_hub <id> [rows]: build one hub's index.
build_hub() { bash "$BUILD" "${2:-$ROWS}" "$1" >/dev/null; }

build() { bash "$BUILD" "${1:-$ROWS}" >/dev/null; }

# patch_config '<jq filter>': rewrite the single hub's config in place.
patch_config() { patch_hub homelab "$1"; }

# add_bad_hub: a hub folder whose name is not a valid id, copied from the example garden config.
add_bad_hub() { mkdir -p "$NOTION_HUB_DIR/Bad Name"; cp "$ROOT/examples/hubs/garden/config.json" "$NOTION_HUB_DIR/Bad Name/config.json"; }

# patch_hub <id> '<jq filter>': rewrite one hub's config in place.
patch_hub() { jq "$2" "$NOTION_HUB_DIR/$1/config.json" > "$T/c" && mv "$T/c" "$NOTION_HUB_DIR/$1/config.json"; }
