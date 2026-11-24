#!/usr/bin/env bash
# Push the local privacy denylist to the PRIVACY_DENYLIST repo secret, and use it for a local check.
# The list lives outside the repo so it can never be committed.
# Usage: sync-denylist.sh [path]   (default: ~/.config/grimoire/privacy-denylist)
set -euo pipefail

list="${1:-$HOME/.config/grimoire/privacy-denylist}"
[[ -f "$list" ]] || { echo "No denylist at $list" >&2; exit 1; }

# Drop comments and blank lines before sending.
terms="$(grep -vE '^[[:space:]]*(#|$)' "$list")"

cd "$(git rev-parse --show-toplevel)"
PRIVACY_DENYLIST="$terms" scripts/ci/check-privacy.sh
printf '%s\n' "$terms" | gh secret set PRIVACY_DENYLIST
echo "PRIVACY_DENYLIST updated with $(printf '%s\n' "$terms" | wc -l | tr -d ' ') terms."
