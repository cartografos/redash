#!/usr/bin/env bash
# SessionStart hook: warns if REDASH_* env vars are missing (does not block the session).
set -u

missing=()
for var in REDASH_URL REDASH_API_KEY; do
  if [[ -z "${!var:-}" ]]; then
    missing+=("$var")
  fi
done

if (( ${#missing[@]} > 0 )); then
  echo "⚠️  redash-plugin: missing env vars: ${missing[*]}" >&2
  echo "   Export them before using /redash:* — see plugin README." >&2
fi

exit 0
