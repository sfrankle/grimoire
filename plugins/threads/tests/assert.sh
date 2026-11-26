# shellcheck shell=bash disable=SC2034  # HOOK, NEW and friends are read by the files that source this.
# Test helpers.
# Source this file, then call finish at the end of the test file.
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

# Shared sandbox for the threads tests.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NEW="$ROOT/scripts/new.sh"
LOG="$ROOT/scripts/log-line.sh"
HOOK="$ROOT/scripts/session-start.sh"
TMPS=""

# setup: fresh HOME and threads dir; sets T, HOME and THREADS_DIR.
setup() {
  T="$(mktemp -d)"
  TMPS="$TMPS $T"
  export HOME="$T/home" THREADS_DIR="$T/threads"
  mkdir -p "$HOME" "$THREADS_DIR"
  unset THREADS_MAX_CHARS
}
# Called from the EXIT trap below.
# shellcheck disable=SC2329
cleanup() { for d in $TMPS; do rm -rf "$d"; done; }
trap cleanup EXIT
