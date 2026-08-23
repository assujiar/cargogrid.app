#!/usr/bin/env bash
# Shared disposable-database setup logic (CG-S10-ATW-024, Prompt 243). Extracted
# from scripts/db-tests/run.sh so scripts/load-tests/'s own harness can reuse the
# identical role-creation and migration-apply logic without duplicating it
# (ISS-2026-014's own remediation: "do not duplicate that logic verbatim, extract/
# source a shared helper"). scripts/db-tests/run.sh itself was updated to source
# this file and call cargogrid_setup_disposable_db() in place of its own former
# inline steps -- byte-for-byte identical resulting behavior, re-verified via a
# full `pnpm run db:test` pass before and after the extraction.
#
# Not a migration, not a test file on its own (scripts/db-tests/run.sh only globs
# *.sql as test files/fixtures; this is a *.sh library, sourced, never executed
# directly, and lives under lib/ so neither run.sh's fixture glob nor its own test
# glob picks it up).
#
# Usage (from a caller that has already set -euo pipefail):
#   source "$REPO_ROOT/scripts/db-tests/lib/setup-disposable-db.sh"
#   cargogrid_setup_disposable_db "$DATABASE_ADMIN_URL" "$TEST_DB_NAME" "$REPO_ROOT" "$FIXTURES_DIR"
#   # afterward, $CARGOGRID_TEST_DB_URL is set and ready to use.

cargogrid_setup_disposable_db() {
  local admin_url="$1"
  local db_name="$2"
  local repo_root="$3"
  local fixtures_dir="$4"
  local migrations_dir="$repo_root/supabase/migrations"

  echo "==> setup-disposable-db: recreating disposable database '$db_name'"
  psql "$admin_url" -v ON_ERROR_STOP=1 -c "DROP DATABASE IF EXISTS $db_name;"
  psql "$admin_url" -v ON_ERROR_STOP=1 -c "CREATE DATABASE $db_name;"

  CARGOGRID_TEST_DB_URL="${admin_url%/*}/$db_name"

  # Mirror the session search_path a hosted Supabase project ships with. Supabase sets it at
  # the database level and pgcrypto lives in `extensions`, so an unqualified digest()/hmac()
  # call resolves there. A bare Postgres defaults to '"$user", public' with no `extensions`,
  # which made test files that call those functions directly fail locally while passing against
  # the live project -- the mirror image of the bug that made them pass on CI and fail live
  # (docs/build-log/phase-09/LIVE_SUPABASE_MIGRATION_REPORT.md). Setting it here keeps the two
  # environments resolving identically, which is the whole point of this harness.
  echo "==> setup-disposable-db: mirroring Supabase's database-level search_path"
  psql "$admin_url" -v ON_ERROR_STOP=1 \
    -c "ALTER DATABASE $db_name SET search_path TO \"\$user\", public, extensions;"

  echo "==> setup-disposable-db: creating the standard anon/authenticated/service_role roles (mirrors a real Supabase project's role model)"
  psql "$CARGOGRID_TEST_DB_URL" -v ON_ERROR_STOP=1 -c "
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
  local fixtures=("$fixtures_dir"/*.sql)
  if [ ${#fixtures[@]} -gt 0 ]; then
    echo "==> setup-disposable-db: loading ${#fixtures[@]} local-only test fixture(s) (never real migrations -- see each file's own header)"
    local fixture
    for fixture in "${fixtures[@]}"; do
      echo "  -- $(basename "$fixture")"
      psql "$CARGOGRID_TEST_DB_URL" -v ON_ERROR_STOP=1 -f "$fixture"
    done
  fi

  local migrations=("$migrations_dir"/*.sql)
  if [ ${#migrations[@]} -eq 0 ]; then
    echo "==> setup-disposable-db: no migrations found under $migrations_dir -- nothing to apply"
    return 0
  fi

  echo "==> setup-disposable-db: applying ${#migrations[@]} migration(s) in order"
  local migration
  for migration in "${migrations[@]}"; do
    echo "  -- $(basename "$migration")"
    psql "$CARGOGRID_TEST_DB_URL" -v ON_ERROR_STOP=1 -f "$migration"
  done

  export CARGOGRID_TEST_DB_URL
}
