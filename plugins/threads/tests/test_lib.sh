#!/usr/bin/env bash
# Literal ~ in fixtures is intentional: paths are stored unexpanded.
# shellcheck disable=SC2088
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=assert.sh
. "$here/assert.sh"
# shellcheck source=../scripts/lib.sh
. "$ROOT/scripts/lib.sh"
setup

assert_eq "$T/threads" "$(threads_dir)" "threads_dir honours THREADS_DIR"
assert_eq "$HOME/.claude/threads" "$(unset THREADS_DIR; threads_dir)" "threads_dir default"
assert_eq "$HOME/x" "$(expand_tilde '~/x')" "expand_tilde expands ~/"
assert_eq "$HOME" "$(expand_tilde '~')" "expand_tilde expands ~"
assert_eq "/a/b" "$(expand_tilde /a/b)" "expand_tilde leaves absolute paths"

for n in homelab a1 threads-design; do
  assert_exit 0 "valid_name accepts $n" -- valid_name "$n"
done
for n in "" -x Homelab a/b .. "a b" a_b; do
  assert_exit 1 "valid_name rejects '$n'" -- valid_name "$n"
done

# shellcheck disable=SC2016
# Bracket ranges follow the locale's collation order, so check under a real locale too.
if locale -a 2>/dev/null | grep -qx 'en_US.UTF-8'; then
  for n in Homelab aAb é; do
    assert_exit 1 "valid_name rejects '$n' under en_US.UTF-8" -- env LC_ALL=en_US.UTF-8 bash -c '. "$1"; valid_name "$2"' _ "$ROOT/scripts/lib.sh" "$n"
  done
  assert_exit 0 "valid_name accepts threads-2 under en_US.UTF-8" -- env LC_ALL=en_US.UTF-8 bash -c '. "$1"; valid_name "$2"' _ "$ROOT/scripts/lib.sh" threads-2
else
  echo "PASS (skipped: en_US.UTF-8 locale not installed)"
fi

assert_eq "a / b" "$(one_line $'a |\n  b')" "one_line flattens whitespace and pipes"
assert_eq "x y" "$(one_line $'  x \t y  ')" "one_line trims"

mkdir -p "$T/p"
cat > "$T/p/state.md" <<'EOT'
---
summary: Rebuild the home server
status: active
paths:
  - ~/code/homelab
  - ~/notes/homelab/
---
body: not frontmatter
summary: wrong
EOT
printf 'no frontmatter here\nsummary: nope\n' > "$T/p/plain.md"
assert_eq "Rebuild the home server" "$(front "$T/p/state.md" summary)" "front reads scalar"
assert_eq "" "$(front "$T/p/state.md" missing)" "front missing key is empty"
assert_eq "" "$(front "$T/p/plain.md" summary)" "front without frontmatter is empty"
assert_eq "$(printf '~/code/homelab\n~/notes/homelab/')" "$(front_list "$T/p/state.md" paths)" "front_list reads items"
assert_eq "" "$(front_list "$T/p/plain.md" paths)" "front_list without frontmatter is empty"

proj() { # name status paths...
  local n="$1" s="$2"; shift 2
  mkdir -p "$THREADS_DIR/$n"
  { printf -- '---\nsummary: s\nstatus: %s\npaths:\n' "$s"; for p in "$@"; do printf '  - %s\n' "$p"; done; printf -- '---\n'; } > "$THREADS_DIR/$n/state.md"
}
proj code active '~/code'
proj homelab active '~/code/homelab/'
assert_eq "homelab" "$(match_project "$HOME/code/homelab/sub")" "match: under project path"
assert_eq "homelab" "$(match_project "$HOME/code/homelab/")" "match: trailing slash"
assert_eq "code" "$(match_project "$HOME/code/other")" "match: shorter path"
assert_eq "" "$(match_project "$HOME/elsewhere")" "match: none"
proj homelab closed '~/code/homelab/'
assert_eq "code" "$(match_project "$HOME/code/homelab/sub")" "match: closed project ignored"
assert_eq "" "$(match_project "$HOME/elsewhere")" "match: closed project, elsewhere"

# Hand-edited frontmatter shapes: CRLF, quotes, trailing spaces, inline and scalar lists.
printf -- '---\r\nsummary: "Quoted"\r\nstatus: "active"\r\npaths: \r\n  - "~/crlf"\r\n---\r\n' > "$T/p/crlf.md"
assert_eq "yes" "$(has_frontmatter "$T/p/crlf.md" && echo yes)" "crlf: frontmatter found"
assert_eq "Quoted" "$(front "$T/p/crlf.md" summary)" "crlf: quotes and carriage return dropped"
assert_eq "yes" "$(is_active "$T/p/crlf.md" && echo yes)" "quoted status is active"
assert_eq "~/crlf" "$(front_list "$T/p/crlf.md" paths)" "crlf: list key with trailing space read"
printf -- "---\npaths: [~/a, '~/b' , \"~/c\"]\n---\n" > "$T/p/inline.md"
assert_eq "$(printf '~/a\n~/b\n~/c')" "$(front_list "$T/p/inline.md" paths)" "inline list read"
printf -- '---\npaths: ~/one\n---\n' > "$T/p/scalar.md"
assert_eq "~/one" "$(front_list "$T/p/scalar.md" paths)" "scalar list read as one item"

# Symlinked paths match their resolved form.
mkdir -p "$T/real/code/linked/sub"
ln -s "$T/real/code" "$HOME/code-link"
proj linked active '~/code-link/linked'
assert_eq "linked" "$(match_project "$T/real/code/linked/sub")" "match: symlinked path resolves"
mkdir -p "$THREADS_DIR/inline"
printf -- '---\nstatus: active\npaths: [%s]\n---\n' "$T/real/code/inline" > "$THREADS_DIR/inline/state.md"
assert_eq "inline" "$(match_project "$T/real/code/inline")" "match: inline list path"
finish
