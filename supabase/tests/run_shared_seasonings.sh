#!/usr/bin/env bash
# Rebuild the disposable test database through the current migration chain.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DB="${DB:-recipes}"

FULL_MIGRATIONS=1 "$ROOT/tests/rebuild.sh"
su postgres -c "psql -v ON_ERROR_STOP=1 -d $DB -f $ROOT/tests/shared_seasonings.sql"
