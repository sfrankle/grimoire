#!/usr/bin/env bash
# Fail when tracked files contain personal details that don't belong in a public repo.
# Extra terms (real names, clients, folders, IDs) come from PRIVACY_DENYLIST, one per line, kept as a repo secret.
# Terms match as whole words, case-insensitive, so "frankle" does not flag "sfrankle".
set -euo pipefail

status=0
self=':(exclude)scripts/ci/check-privacy.sh'

if git grep -nE '/(Users|home)/[A-Za-z0-9._-]+' -- . "$self"; then
  echo "::error::Absolute home-directory paths found. Use ~ or an invented path."
  status=1
fi

emails="$(git grep -nIE '[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}' -- . "$self" \
  | grep -vE 'noreply@|@example\.(com|org|net)' || true)"
if [[ -n "$emails" ]]; then
  echo "$emails"
  echo "::error::Email addresses found. Use an example.com address."
  status=1
fi

if [[ -n "${PRIVACY_DENYLIST:-}" ]]; then
  terms="$(mktemp)"
  printf '%s\n' "$PRIVACY_DENYLIST" | sed '/^[[:space:]]*$/d' > "$terms"
  # Print only file:line so the denylisted terms never reach the log.
  hits="$(git grep -wniIF -f "$terms" -- . "$self" | cut -d: -f1,2 || true)"
  rm -f "$terms"
  if [[ -n "$hits" ]]; then
    echo "$hits"
    echo "::error::Denylisted terms found at the lines above."
    status=1
  fi
else
  echo "PRIVACY_DENYLIST not set; skipping the denylist check."
fi

exit "$status"
