#!/usr/bin/env bash
# Usage: build-index.sh <rows.json>
# Turns raw connector rows into $(hub_dir)/index.md.
# On any error it prints one reason to stderr, exits 1 and leaves index.md as it was.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

fail() {
  printf 'build-index: %s\n' "$1" >&2
  exit 1
}

rows="$1"
dir="$(hub_dir)"
config="$dir/config.json"

need_jq || fail "jq is required but not installed."
[ -n "$rows" ] || fail "usage: build-index.sh <rows.json>"
[ -f "$config" ] || fail "no config at $config. Run /notion-setup first."
[ -f "$rows" ] || fail "rows file not found: $rows"

# Every page has a title, so a title column in no row means config.json fields is out of date.
jq -e --slurpfile cfg "$config" '$cfg[0].fields.title as $t | any(.[]; (.properties // {}) | has($t))' "$rows" >/dev/null 2>&1 \
  || fail "no row has the mapped title column, or the rows are malformed. Check config.json fields, index left unchanged."

tmp="$(mktemp "$dir/.index.md.XXXXXX")" || fail "cannot write to $dir."
trap 'rm -f "$tmp"' EXIT

name="$(jq -r '.hub.name // "Notion hub"' "$config")"
url="$(jq -r '.hub.database_url // ""' "$config")"

{
  printf '# Notion hub index: %s\n\n' "$name"
  printf 'Built %s from %s. If that is more than a week ago, suggest /notion-refresh.\n' "$(date +%Y-%m-%d)" "$url"
  cat <<'HEADER'
Row flags: shared|private / always|auto|ask / ro|edit|own.
always = fetch before your first answer. auto = fetch when the task matches the title, summary or keywords. ask = fetch only when the user names it.
ro = never edit, propose changes in chat. edit = smallest edit to the right section. own = agent-owned, keep current.

HEADER
  jq -r --slurpfile cfg "$config" '
    $cfg[0] as $c
    | ($c.fields // {}) as $f
    | ($c.values // {}) as $v
    | def arr: if . == null then [] elif type == "array" then map(tostring) else [tostring] end;
      ($c.scopes.private_values | arr) as $priv
    | def prop($k): if $f[$k] == null then [] else (.properties // {})[$f[$k]] | arr end;
      def hit($vals; $set): ($set | arr) as $s | any($vals[]; . as $x | ($s | index($x)) != null);
      def norm: tostring | gsub("\\|"; "/") | gsub("\\s+"; " ") | sub("^ "; "") | sub(" $"; "");
      def opt($k): (prop($k) | map(norm) | map(select(. != "")) | join(", "))
        | if . == "" then empty else "\($k): \(.)" end;
    [ .[]
      | (prop("visibility")) as $vis
      | (prop("load")) as $load
      | (prop("edit")) as $edit
      | (prop("title") | join(" ") | norm) as $title
      | { title: $title,
          line: ([
            ( ((if ($vis | length) > 0 and all($vis[]; . as $x | ($priv | index($x)) != null)
                then "private" else "shared" end)
              + "/"
              + (if hit($load; $v.load.always) then "always"
                 elif hit($load; $v.load.ask) then "ask" else "auto" end)
              + "/"
              + (if hit($edit; $v.edit.small_edits) then "edit"
                 elif hit($edit; $v.edit.agent_owned) then "own" else "ro" end)) ),
            $title,
            (prop("summary") | join(" ") | norm),
            (opt("category")),
            (opt("keywords")),
            ((.url // "") | norm)
          ] | join(" | ")) }
    ]
    | sort_by(.title | ascii_downcase)
    | .[] | "- " + .line
  ' "$rows"
} > "$tmp" 2>/dev/null || fail "could not map rows with the config, index left unchanged."

count="$(grep -c '^- ' "$tmp")"
[ "$count" -gt 0 ] || fail "no rows produced, index left unchanged."

mv "$tmp" "$dir/index.md" || fail "could not write index.md."
trap - EXIT
printf 'Indexed %s pages.\n' "$count"
