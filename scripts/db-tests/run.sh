#!/usr/bin/env bash
# Real, executable database-migration + RLS test runner (PLT-105, CG-S6-PLT-002 and
# onward). Applies every migration in supabase/migrations/ to a fresh, disposable
# database, then runs every *.sql test file in this directory against it.
#
# Requires a reachable Postgres server -- DATABASE_ADMIN_URL must point at a
# superuser-or-equivalent connection (needed to create/drop the disposable test
# database and to create the anon/authenticated/service_role roles this test suite
# relies on, mirroring a real Supabase project's own role model). Defaults to the
# same postgres/postgres/localhost:5432 convention GitHub Actions' own postgres
# service container documentation uses -- a well-known local-only development
# credential, never a real secret (docs/standards/SECURITY_STANDARDS.md §3's
# credential-shaped-value scanner correctly does not flag this: it is not assigned
# to a variable named secret/password/token/api_key/private_key).
set -euo pipefail

DATABASE_ADMIN_URL="${DATABASE_ADMIN_URL:-postgresql://postgres:postgres@127.0.0.1:5432/postgres}"
TEST_DB_NAME="${TEST_DB_NAME:-cargogrid_db_test}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MIGRATIONS_DIR="$REPO_ROOT/supabase/migrations"

echo "==> db-tests: recreating disposable database '$TEST_DB_NAME'"
psql "$DATABASE_ADMIN_URL" -v ON_ERROR_STOP=1 -c "DROP DATABASE IF EXISTS $TEST_DB_NAME;"
psql "$DATABASE_ADMIN_URL" -v ON_ERROR_STOP=1 -c "CREATE DATABASE $TEST_DB_NAME;"

TEST_DB_URL="${DATABASE_ADMIN_URL%/*}/$TEST_DB_NAME"

echo "==> db-tests: creating the standard anon/authenticated/service_role roles (mirrors a real Supabase project's role model; this repository has no live Supabase project yet)"
psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -c "
do \$\$
begin
  if not exists (select from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
  if not exists (select from pg_roles where rolname = 'service_role') then
    create role service_role nologin bypassrls;
  end if;
end
\$\$;
"

shopt -s nullglob
migrations=("$MIGRATIONS_DIR"/*.sql)
if [ ${#migrations[@]} -eq 0 ]; then
  echo "==> db-tests: no migrations found under $MIGRATIONS_DIR -- nothing to test"
  exit 0
fi

echo "==> db-tests: applying ${#migrations[@]} migration(s) in order"
for migration in "${migrations[@]}"; do
  echo "  -- $(basename "$migration")"
  psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -f "$migration"
done

test_files=("$SCRIPT_DIR"/*.sql)
if [ ${#test_files[@]} -eq 0 ]; then
  echo "==> db-tests: no test files found under $SCRIPT_DIR"
  exit 0
fi

echo "==> db-tests: running ${#test_files[@]} test file(s)"
for test_file in "${test_files[@]}"; do
  echo "  -- $(basename "$test_file")"
  psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -f "$test_file"
done

echo "==> db-tests: dropping disposable database '$TEST_DB_NAME'"
psql "$DATABASE_ADMIN_URL" -v ON_ERROR_STOP=1 -c "DROP DATABASE IF EXISTS $TEST_DB_NAME;"

echo "==> db-tests: ALL PASSED"
