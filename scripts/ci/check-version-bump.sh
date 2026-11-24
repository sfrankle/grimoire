#!/usr/bin/env bash
# Fail when a plugin's shipped files change but its plugin.json version does not.
# Usage: check-version-bump.sh <base-ref>
set -euo pipefail

base="${1:?usage: check-version-bump.sh <base-ref>}"
status=0

for manifest in plugins/*/.claude-plugin/plugin.json; do
  dir="${manifest%/.claude-plugin/plugin.json}"
  plugin="${dir#plugins/}"

  # Tests don't ship to users, so they don't need a bump.
  if git diff --quiet "$base"...HEAD -- "$dir" ":(exclude)$dir/tests"; then
    continue
  fi

  # A plugin that is new on this branch has nothing to bump from.
  if ! git cat-file -e "$base:$manifest" 2>/dev/null; then
    continue
  fi

  old="$(git show "$base:$manifest" | jq -r .version)"
  new="$(jq -r .version "$manifest")"
  if [[ "$old" == "$new" ]]; then
    echo "::error file=$manifest::$plugin changed but its version is still $old. Bump it so /plugin update picks up the change."
    status=1
  else
    echo "$plugin: $old -> $new"
  fi
done

exit "$status"
