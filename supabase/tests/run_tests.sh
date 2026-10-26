#!/usr/bin/env bash
# Rebuild from zero, then run the suite.
#
# The suite is NOT idempotent against a used database: section 8c calls
# add_recipe_to_shopping_list, which commits. Re-running without a
# rebuild makes the section 1 row counts drift. Always go through this
# script rather than calling psql directly.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DB="${DB:-recipes}"

pg_isready -q || { service postgresql start >/dev/null 2>&1; sleep 4; }

"$ROOT/tests/rebuild.sh" >/dev/null

LOG="$ROOT/tests/LAST_RUN.txt"
su postgres -c "psql -d $DB -f $ROOT/tests/rls_negative_control.sql" 2>&1 \
  | grep -E '^(PASS|FAIL|=+ )' > "$LOG" || true

PASS=$(grep -c '^PASS' "$LOG" || true)
FAIL=$(grep -c '^FAIL' "$LOG" || true)

printf '\n%s\n' "$(cat "$LOG")"
printf '\n---------------------------------------------\n'
printf 'PASS %s   FAIL %s\n' "$PASS" "$FAIL"

[ "$FAIL" -eq 0 ]
