#!/usr/bin/env bash
# SessionStart hook: prints the user's rules, the active projects, and the likely project's state and units.
# Takes no arguments.
# Reads the hook input JSON on stdin, CLAUDE_PROJECT_DIR (falls back to PWD), THREADS_DIR and THREADS_MAX_CHARS.
# Always exits 0 and prints nothing to stderr.
#
# Output cap: Claude Code caps a hook's plain stdout at 10,000 characters.
# Over the cap the output is replaced by a file path and a 2,000 character preview.
# Source: https://code.claude.com/docs/en/hooks (checked 2026-11-24).
# The default below leaves 500 characters of headroom.
DEFAULT_MAX_CHARS=9500
# The trimmer never cuts F lines, so each long F block has its own cap.
# rules.md is cut to this many characters.
RULES_MAX_CHARS=1000
# The likely project's state.md body is cut to this many characters.
BODY_MAX_CHARS=1500

exec 2>/dev/null

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

# Usage: tagged <tag> <text>: prints each line of text prefixed with a one-letter tag for the trimmer.
# F lines are never cut, P (project) and U (unit) lines can be.
tagged() {
  printf '%s\n' "$2" | awk -v t="$1" '{ print t $0 }'
}

# The state.md text after the frontmatter, leading blank lines dropped.
body_of() {
  awk '{ sub(/\r$/, "") } NR == 1 { next } !done && /^---[ \t]*$/ { done = 1; next } done { print }' "$1" | awk 'NF { p = 1 } p'
}

# Usage: capped <text> <max> <file>: prints the text, cut to max characters with a pointer to the file.
capped() {
  if [ "${#1}" -gt "$2" ]; then
    printf '%s\n… (truncated, read %s)\n' "${1:0:$2}" "$3"
  else
    printf '%s\n' "$1"
  fi
}

# One "- <project> | <summary> | <path>, <path>" line per active project, alphabetical.
project_lines() {
  local state name summary paths
  for state in "$1"/*/state.md; do
    if [ ! -f "$state" ] || ! usable "$state"; then continue; fi
    name="$(basename "$(dirname "$state")")"
    summary="$(one_line "$(front "$state" summary)")"
    paths="$(one_line "$(front_list "$state" paths | awk '{ printf "%s%s", (NR > 1 ? ", " : ""), $0 }')")"
    if [ -n "$paths" ]; then
      printf -- '- %s | %s | %s\n' "$name" "$summary" "$paths"
    else
      printf -- '- %s | %s\n' "$name" "$summary"
    fi
  done
}

# One "- <unit> | <summary>" line per active unit, most recent log.md (else state.md) first.
# Order comes from ls -t, since stat flags differ between macOS and Linux.
unit_lines() {
  local state files=() f dir
  for state in "$1"/*/state.md; do
    if [ ! -f "$state" ] || ! usable "$state"; then continue; fi
    dir="$(dirname "$state")"
    if [ -f "$dir/log.md" ]; then files+=("$dir/log.md"); else files+=("$state"); fi
  done
  [ "${#files[@]}" -gt 0 ] || return 0
  # Every path is built from checked names, so ls output is safe to read line by line.
  # shellcheck disable=SC2012
  ls -1t -- "${files[@]}" | while IFS= read -r f; do
    dir="$(dirname "$f")"
    printf -- '- %s | %s\n' "$(basename "$dir")" "$(one_line "$(front "$dir/state.md" summary)")"
  done
}

main() {
  local root input sid notion rules projects likely body units max
  root="$(threads_dir)"

  if [ ! -f "$root/config.json" ]; then
    echo "Threads is not set up. Run /threads-setup to create your workspace."
    return 0
  fi
  if ! need_jq; then
    echo "Threads needs jq to read its config. Install jq and start a new session."
    return 0
  fi
  if ! jq -e 'type == "object" and ((has("notion_hub") | not) or (.notion_hub | . == "auto" or . == "off"))' "$root/config.json" >/dev/null; then
    echo "Threads config is invalid. Run /threads-setup to fix it."
    return 0
  fi
  notion="$(jq -r '.notion_hub // "auto"' "$root/config.json")"

  rules=""
  [ -f "$root/rules.md" ] && rules="$(capped "$(tr -d '\r' < "$root/rules.md")" "$RULES_MAX_CHARS" "$root/rules.md")"

  projects="$(project_lines "$root")"
  if [ -z "$projects" ]; then
    [ -n "$rules" ] && printf '%s\n\n' "$rules"
    echo "No projects yet. Run /threads-project to create one."
    return 0
  fi

  # The session id is only printed when it could go into a log line unchanged.
  input=""
  [ -t 0 ] || input="$(cat)"
  sid="$(printf '%s' "$input" | jq -r 'if type == "object" then .session_id else empty end | strings')"
  case "$sid" in *[[:space:]]* | *'|'*) sid="" ;; esac

  likely="$(match_project "${CLAUDE_PROJECT_DIR:-$PWD}")"
  body=""
  units=""
  if [ -n "$likely" ]; then
    body="$(capped "$(body_of "$root/$likely/state.md")" "$BODY_MAX_CHARS" "$root/$likely/state.md")"
    units="$(unit_lines "$root/$likely/units")"
  fi

  max="${THREADS_MAX_CHARS:-$DEFAULT_MAX_CHARS}"
  case "$max" in '' | *[!0-9]*) max="$DEFAULT_MAX_CHARS" ;; esac

  {
    [ -n "$rules" ] && tagged F "$rules" && tagged F ""
    tagged F "Threads: $root"
    [ -n "$sid" ] && tagged F "Session: $sid"
    [ "$notion" = "off" ] || tagged F "Settled facts that outlive a unit: suggest /notion-save when that skill is listed."
    tagged F "Projects:"
    tagged P "$projects"
    if [ -n "$likely" ]; then
      tagged F "Likely project: $likely"
      [ -n "$body" ] && tagged F "$body"
      [ -n "$units" ] && tagged F "Units, most recent first:" && tagged U "$units"
    fi
  } | THREADS_ROOT="$root" THREADS_UNITS="$root/$likely/units" awk -v max="$max" '
    # Trimming runs last, over the whole output.
    # F lines are never cut.
    # Project lines get the budget before unit lines, so unit lines are cut first.
    # Within each kind, the first line that does not fit and every line after it are cut, so order is kept.
    {
      n++; tag[n] = substr($0, 1, 1); txt[n] = substr($0, 2)
      size = length(txt[n]) + 1; total += size
      if (tag[n] == "F") fixed += size; else count[tag[n]]++
    }
    function note(p, u, root, units) {
      if (p && u) return sprintf("%d more projects and %d more units did not fit. List %s and %s to see them all.", p, u, root, units)
      if (p) return sprintf("%d more projects did not fit. List %s to see them all.", p, root)
      return sprintf("%d more units did not fit. List %s to see them all.", u, units)
    }
    # Marks the lines to cut so the kept ones fit in budget; sets cuts["P"] and cuts["U"].
    function trim(budget,    k, kind, stop, used, i) {
      split("", cut); cuts["P"] = cuts["U"] = 0
      for (k = 1; k <= 2; k++) {
        # Units are cut before projects, so once any project line is cut every unit line goes too.
        kind = (k == 1) ? "P" : "U"; stop = (kind == "U" && cuts["P"] > 0)
        for (i = 1; i <= n; i++) {
          if (tag[i] != kind) continue
          if (!stop && used + length(txt[i]) + 1 <= budget) used += length(txt[i]) + 1
          else { stop = 1; cut[i] = 1; cuts[kind]++ }
        }
      }
    }
    END {
      root = ENVIRON["THREADS_ROOT"]; units = ENVIRON["THREADS_UNITS"]
      if (total > max) {
        # Reserve room for the note: first as if only units are cut, then for the longer note if projects are cut too.
        # The total counts bound the digits, so the reserve is never short.
        trim(max - fixed - length(note(count["U"] ? 0 : count["P"], count["U"], root, units)) - 2)
        if (cuts["P"] && count["U"]) trim(max - fixed - length(note(count["P"], count["U"], root, units)) - 2)
      }
      for (i = 1; i <= n; i++) if (!cut[i]) print txt[i]
      if (cuts["P"] || cuts["U"]) printf "\n%s\n", note(cuts["P"], cuts["U"], root, units)
    }'
}

main || true
exit 0
