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
