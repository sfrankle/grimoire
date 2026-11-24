#!/usr/bin/env bash
# Literal ~ in fixtures is intentional: paths are stored unexpanded.
# shellcheck disable=SC2088
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=assert.sh
. "$here/assert.sh"

NOTION_LINE="Settled facts that outlive a unit: suggest /notion-save when that skill is listed."

# run_hook <project dir> [stdin]: prints the hook's output, stderr merged so noise is caught.
run_hook() { printf '%s' "${2-}" | CLAUDE_PROJECT_DIR="$1" bash "$HOOK" 2>&1; }

# hook_exit <project dir> [stdin]: prints the hook's exit code.
hook_exit() { printf '%s' "${2-}" | CLAUDE_PROJECT_DIR="$1" bash "$HOOK" >/dev/null 2>&1; echo $?; }

# hook_stderr <project dir> [stdin]: prints only what the hook wrote to stderr.
# The 2>&1 >/dev/null order is deliberate: stderr to the capture, stdout dropped.
# shellcheck disable=SC2069
hook_stderr() { printf '%s' "${2-}" | CLAUDE_PROJECT_DIR="$1" bash "$HOOK" 2>&1 >/dev/null; }

last_line() { printf '%s\n' "$1" | tail -n 1; }

# Number of characters before the first occurrence of $2 in $1, or -1.
pos() {
  case "$1" in
    *"$2"*) local before="${1%%"$2"*}"; printf '%s' "${#before}" ;;
    *) printf '%s' "-1" ;;
  esac
}

# set_status <state.md> <status>: rewrites the status line.
set_status() {
  awk -v s="$2" '/^status: / { print "status: " s; next } { print }' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}

# fixture: the sandbox plus example config and rules, two active projects, one closed, and units.
fixture() {
  setup
  cp "$ROOT/examples/config.json" "$ROOT/examples/rules.md" "$THREADS_DIR/"
  bash "$NEW" project homelab "Rebuild the home server" '~/code/homelab' >/dev/null
  bash "$NEW" project calculus "Pass the calculus final" '~/notes/calculus' '~/code/calculus' >/dev/null
  bash "$NEW" project garden "Plan the garden" '~/code/garden' >/dev/null
  set_status "$THREADS_DIR/garden/state.md" closed
  printf '\nHomelab body: the NAS is slow, back up first.\n' >> "$THREADS_DIR/homelab/state.md"
  local u="$THREADS_DIR/homelab/units"
  bash "$NEW" unit homelab dns-cutover "Move DNS to the new box" >/dev/null
  bash "$NEW" unit homelab backups "Nightly backups to the NAS" >/dev/null
  bash "$NEW" unit homelab monitoring "Add uptime checks" >/dev/null
  bash "$NEW" unit homelab old-vpn "Retire the old VPN" >/dev/null
  set_status "$u/old-vpn/state.md" closed
  printf -- '- 2026-11-20 | a | x\n' > "$u/dns-cutover/log.md"
  printf -- '- 2026-11-23 | b | y\n' > "$u/backups/log.md"
  printf -- '- 2026-11-24 | c | z\n' > "$u/old-vpn/log.md"
  touch -t 202611200900 "$u/dns-cutover/log.md"
  touch -t 202611230900 "$u/backups/log.md"
  touch -t 202611240900 "$u/old-vpn/log.md"
  touch -t 202611100900 "$u/monitoring/state.md"
}

test_no_config() {
  setup
  local out; out="$(run_hook "$HOME/code/homelab")"
  assert_eq "Threads is not set up. Run /threads-setup to create your workspace." "$out" "no config: the one line"
  assert_eq "0" "$(hook_exit "$HOME/code/homelab")" "no config: exit 0"
}

test_bad_config() {
  local bad out
  for bad in '{' '[1,2]' '{"version":1,"notion_hub":"maybe"}'; do
    fixture; printf '%s' "$bad" > "$THREADS_DIR/config.json"
    out="$(run_hook "$HOME/code/homelab")"
    assert_eq "Threads config is invalid. Run /threads-setup to fix it." "$out" "bad config $bad: the one line"
    assert_eq "0" "$(hook_exit "$HOME/code/homelab")" "bad config $bad: exit 0"
  done
}

test_no_jq() {
  fixture
  local bin="$T/bin" tool
  mkdir -p "$bin"
  for tool in bash awk cat dirname basename grep sed tr head tail wc ls; do
    ln -s "$(command -v "$tool")" "$bin/$tool"
  done
  local out; out="$(CLAUDE_PROJECT_DIR="$HOME/code/homelab" PATH="$bin" "$bin/bash" "$HOOK" </dev/null 2>&1)"
  local code=$?
  assert_eq "Threads needs jq to read its config. Install jq and start a new session." "$out" "no jq: the one line"
  assert_eq "0" "$code" "no jq: exit 0"
}

test_no_projects() {
  setup
  cp "$ROOT/examples/config.json" "$THREADS_DIR/"
  local want="No projects yet. Run /threads-project to create one."
  local out; out="$(run_hook "$HOME/code/homelab")"
  assert_eq "$want" "$out" "no projects: the one line"
  assert_eq "0" "$(hook_exit "$HOME/code/homelab")" "no projects: exit 0"
  cp "$ROOT/examples/rules.md" "$THREADS_DIR/"
  bash "$NEW" project garden "Plan the garden" >/dev/null
  set_status "$THREADS_DIR/garden/state.md" closed
  out="$(run_hook "$HOME/code/homelab")"
  assert_eq "$(cat "$ROOT/examples/rules.md")"$'\n\n'"$want" "$out" "no active projects: rules then the one line"
}

test_project_list() {
  fixture
  local out; out="$(run_hook "$HOME/elsewhere")"
  assert_contains "$out" "Threads rules" "list: rules printed"
  assert_contains "$out" "Threads: $THREADS_DIR" "list: names the root"
  assert_contains "$out" "- calculus | Pass the calculus final | ~/notes/calculus, ~/code/calculus" "list: calculus line with paths"
  assert_contains "$out" "- homelab | Rebuild the home server | ~/code/homelab" "list: homelab line"
  assert_not_contains "$out" "garden" "list: closed project absent"
  local c h; c="$(pos "$out" "- calculus |")"; h="$(pos "$out" "- homelab |")"
  if [ "$c" -lt "$h" ]; then pass "list: alphabetical"; else fail "list: alphabetical"; fi
  if [ "$(pos "$out" "Threads rules")" -lt "$(pos "$out" "Threads: ")" ]; then pass "list: rules first"; else fail "list: rules first"; fi
  assert_not_contains "$out" "Likely project:" "elsewhere: no likely project"
  assert_not_contains "$out" "Units, most recent first:" "elsewhere: no units"
  assert_eq "0" "$(hook_exit "$HOME/elsewhere")" "list: exit 0"
}

test_likely_project() {
  fixture
  local out; out="$(run_hook "$HOME/code/homelab/sub")"
  assert_contains "$out" "Likely project: homelab" "likely: names homelab"
  assert_contains "$out" "Homelab body: the NAS is slow, back up first." "likely: prints the body"
  assert_not_contains "$out" "name: homelab" "likely: no frontmatter in body"
  assert_contains "$out" "Units, most recent first:" "likely: units header"
  assert_contains "$out" "- backups | Nightly backups to the NAS" "likely: unit line"
  assert_not_contains "$out" "old-vpn" "likely: closed unit absent"
  local b d m; b="$(pos "$out" "- backups |")"; d="$(pos "$out" "- dns-cutover |")"; m="$(pos "$out" "- monitoring |")"
  if [ "$b" -ge 0 ] && [ "$b" -lt "$d" ] && [ "$d" -lt "$m" ]; then pass "likely: most recent log first, state.md fallback last"; else fail "likely: unit order ($b $d $m)"; fi
  if [ "$(pos "$out" "Projects:")" -lt "$(pos "$out" "Likely project:")" ]; then pass "likely: after the project list"; else fail "likely: after the project list"; fi
}

test_session_id() {
  fixture
  assert_contains "$(run_hook "$HOME/elsewhere" '{"session_id":"abc-123"}')" "Session: abc-123" "session: id printed"
  local input
  for input in '' 'not json' '{"session_id":"a b"}' '[1]'; do
    assert_not_contains "$(run_hook "$HOME/elsewhere" "$input")" "Session:" "session '$input': no line"
    assert_eq "" "$(hook_stderr "$HOME/elsewhere" "$input")" "session '$input': nothing on stderr"
    assert_eq "0" "$(hook_exit "$HOME/elsewhere" "$input")" "session '$input': exit 0"
  done
}

test_notion_line() {
  fixture
  assert_contains "$(run_hook "$HOME/elsewhere")" "$NOTION_LINE" "notion auto: line kept"
  printf '{"version":1,"notion_hub":"off"}' > "$THREADS_DIR/config.json"
  assert_not_contains "$(run_hook "$HOME/elsewhere")" "/notion-save" "notion off: line dropped"
  printf '{"version":1}' > "$THREADS_DIR/config.json"
  assert_contains "$(run_hook "$HOME/elsewhere")" "$NOTION_LINE" "notion unset: line kept"
}

test_skips_broken() {
  fixture
  mkdir -p "$THREADS_DIR/no-state"
  mkdir -p "$THREADS_DIR/broken"
  printf -- '---\nname: broken\nsummary: Never closed\npaths:\n  - ~/code/broken\nstatus: active\n' > "$THREADS_DIR/broken/state.md"
  mkdir -p "$THREADS_DIR/homelab/units/no-state"
  local out; out="$(run_hook "$HOME/code/broken")"
  assert_not_contains "$out" "no-state" "broken: folder without state.md skipped"
  assert_not_contains "$out" "broken" "broken: unclosed frontmatter skipped"
  assert_not_contains "$out" "Likely project:" "broken: unclosed frontmatter never the likely project"
  assert_contains "$out" "- homelab |" "broken: others still print"
  out="$(run_hook "$HOME/code/homelab")"
  assert_contains "$out" "- backups |" "broken: units still print"
  assert_not_contains "$out" "no-state" "broken: unit folder without state.md skipped"
}

test_body_cap() {
  fixture
  local state="$THREADS_DIR/homelab/state.md" big
  big="$(printf '%5000s' '' | tr ' ' 'z')"
  printf -- '---\nname: homelab\nsummary: Rebuild\npaths:\n  - ~/code/homelab\nstatus: active\n---\n%s\n' "$big" > "$state"
  local out run; out="$(run_hook "$HOME/code/homelab")"
  run="$(printf '%s\n' "$out" | grep -o 'zz*' | awk '{ if (length($0) > m) m = length($0) } END { print m + 0 }')"
  assert_eq "1500" "$run" "body: capped at 1,500 characters"
  assert_contains "$out" "… (truncated, read $state)" "body: truncated line names the file"
  assert_contains "$out" "- backups |" "body: units still print"
}

test_cap() {
  fixture
  # Short rules, so the fixed lines leave room for trimming even with macOS's long temp paths.
  printf 'Rule: keep notes short.\n' > "$THREADS_DIR/rules.md"
  local i
  for i in $(seq 1 40); do bash "$NEW" unit homelab "unit-$i" "Filler unit number $i with a summary" >/dev/null; done
  local full; full="$(run_hook "$HOME/code/homelab" '{"session_id":"abc-123"}')"
  assert_not_contains "$full" "did not fit" "cap: no note when everything fits"
  THREADS_MAX_CHARS=600 run_hook "$HOME/code/homelab" '{"session_id":"abc-123"}' > "$T/out"
  local out chars; out="$(cat "$T/out")"; chars="$(LC_ALL=C wc -c < "$T/out" | tr -d ' ')"
  if [ "$chars" -le 600 ]; then pass "cap: at most 600 characters"; else fail "cap: at most 600 characters ($chars)"; fi
  assert_contains "$out" "Rule: keep notes short." "cap: rules kept"
  assert_contains "$out" "Session: abc-123" "cap: session kept"
  assert_contains "$out" "Likely project: homelab" "cap: likely project kept"
  assert_contains "$out" "Homelab body: the NAS is slow" "cap: body kept"
  assert_contains "$out" "- calculus |" "cap: project lines kept while units are cut"
  assert_contains "$(last_line "$out")" "did not fit" "cap: ends with the note"
  assert_contains "$(last_line "$out")" "$THREADS_DIR/homelab/units" "cap: note names the units folder"
  THREADS_MAX_CHARS=800 run_hook "$HOME/code/homelab" '{"session_id":"abc-123"}' > "$T/out"
  chars="$(LC_ALL=C wc -c < "$T/out" | tr -d ' ')"
  if [ "$chars" -le 800 ]; then pass "cap 800: within the cap"; else fail "cap 800: within the cap ($chars)"; fi
  if grep -q '^- unit-' "$T/out"; then pass "cap 800: units that fit are kept"; else fail "cap 800: units that fit are kept"; fi
  out="$(THREADS_MAX_CHARS=10 run_hook "$HOME/code/homelab" '{"session_id":"abc-123"}')"
  assert_contains "$out" "Homelab body: the NAS is slow" "cap: tiny cap still keeps the body"
  assert_not_contains "$out" "- calculus |" "cap: tiny cap cuts project lines"
  assert_contains "$(last_line "$out")" "$THREADS_DIR" "cap: tiny cap note names the root"
}

# A long project line that misses must not let a short unit line take the leftover budget.
test_cap_units_before_projects() {
  setup
  cp "$ROOT/examples/config.json" "$THREADS_DIR/"
  printf 'Rule: keep notes short.\n' > "$THREADS_DIR/rules.md"
  bash "$NEW" project aaa "First" '~/code/aaa' >/dev/null
  bash "$NEW" project bbb "$(printf '%400s' '' | tr ' ' 'b')" >/dev/null
  bash "$NEW" project ccc "Third" >/dev/null
  bash "$NEW" unit aaa u1 "s" >/dev/null
  local out; out="$(THREADS_MAX_CHARS=600 run_hook "$HOME/code/aaa")"
  assert_contains "$out" "- aaa | First" "cap order: project line that fits is kept"
  assert_not_contains "$out" "- u1 |" "cap order: no unit line while project lines are cut"
  assert_contains "$(last_line "$out")" "2 more projects and 1 more units did not fit" "cap order: note counts both"
}

test_no_config; test_bad_config; test_no_jq; test_no_projects
test_project_list; test_likely_project; test_session_id; test_notion_line
test_skips_broken; test_body_cap; test_cap; test_cap_units_before_projects
finish
