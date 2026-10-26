#!/usr/bin/env bash
# Rebuild the local verification database from zero and apply everything
# in order. Stops at the first error.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DB="${DB:-recipes}"
PSQL="psql -q -v ON_ERROR_STOP=1 -d $DB"

as_pg() { su postgres -c "$*"; }

as_pg "psql -q -c 'drop database if exists $DB;' -c 'create database $DB;'"

FILES=(
  "tests/_local_harness.sql"
  "migrations/0001_init_extensions_enums.sql"
  "migrations/0002_core_tables.sql"
  "migrations/0003_functions_triggers.sql"
  "migrations/0004_rls_policies.sql"
  "migrations/0005_storage_policies.sql"
  "seed.sql"
)

for f in "${FILES[@]}"; do
  if out=$(as_pg "$PSQL -f $ROOT/$f" 2>&1); then
    printf 'ok    %s\n' "$f"
  else
    printf 'FAIL  %s\n%s\n' "$f" "$out"
    exit 1
  fi
  if echo "$out" | grep -qi '^ERROR'; then
    printf 'FAIL  %s\n%s\n' "$f" "$out"
    exit 1
  fi
done

printf '\nDatabase "%s" rebuilt.\n' "$DB"
