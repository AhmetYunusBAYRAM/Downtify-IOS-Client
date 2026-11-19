#!/usr/bin/env bash
# Scans a directory (xcresult bundle, exported attachments, logs) for staging secrets.
# Usage: scripts/check_no_secrets_in_artifacts.sh <dir>
# Reads secret values from the environment (DOWNTIFY_TEST_PASSWORD, DOWNTIFY_TEST_USER, DOWNTIFY_TEST_SERVER)
# and checks for Bearer token patterns. Prints only counts and file names, never matched values.
set -euo pipefail

DIR="${1:?usage: check_no_secrets_in_artifacts.sh <dir>}"
[[ -d "$DIR" ]] || { echo "not a directory: $DIR"; exit 2; }

needles=()
[[ -n "${DOWNTIFY_TEST_PASSWORD:-}" ]] && needles+=("password|$DOWNTIFY_TEST_PASSWORD")
[[ -n "${DOWNTIFY_TEST_USER:-}" ]] && needles+=("username|$DOWNTIFY_TEST_USER")
if [[ -n "${DOWNTIFY_TEST_SERVER:-}" ]]; then
  host=$(python3 -c 'import sys,urllib.parse as u; print(u.urlsplit(sys.argv[1]).hostname or "")' "$DOWNTIFY_TEST_SERVER")
  [[ -n "$host" ]] && needles+=("server-host|$host") && needles+=("server-url|$DOWNTIFY_TEST_SERVER")
fi

failures=0
for entry in "${needles[@]+"${needles[@]}"}"; do
  label="${entry%%|*}"
  value="${entry#*|}"
  # -l lists files only; the value itself is never printed.
  matches=$(grep -rla -F -- "$value" "$DIR" 2>/dev/null || true)
  if [[ -n "$matches" ]]; then
    count=$(printf '%s\n' "$matches" | wc -l | tr -d ' ')
    echo "LEAK: $label found in $count file(s):"
    printf '  %s\n' $matches
    failures=$((failures + count))
  fi
done

bearer=$(grep -rlaE "Bearer [A-Za-z0-9._~+/=-]{16,}" "$DIR" 2>/dev/null || true)
if [[ -n "$bearer" ]]; then
  count=$(printf '%s\n' "$bearer" | wc -l | tr -d ' ')
  echo "LEAK: Bearer token pattern found in $count file(s):"
  printf '  %s\n' $bearer
  failures=$((failures + count))
fi

if [[ "$failures" -eq 0 ]]; then
  echo "OK: no staging secrets found under $DIR (checked ${#needles[@]} value(s) + Bearer pattern)."
  exit 0
fi
echo "RESULT: $failures leak location(s). Do not share this directory."
exit 1
