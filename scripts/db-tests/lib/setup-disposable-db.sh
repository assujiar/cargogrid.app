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
  # Track B Batch 8 (ISS-2026-161): this function's own header above
  # documents "from a caller that has already set -euo pipefail" as a
  # USAGE CONTRACT, but never enforced it itself -- a caller that skips that
  # (this repository's one shipped caller, scripts/db-tests/run.sh line 14,
  # already does it; a future/ad hoc caller can easily forget, exactly as
  # observed live at HDN-370's Tier C session) got a function that reaches
  # its own final `export` statement and returns 0 even when every `psql`
  # call inside failed (e.g. Postgres down: "Connection refused" on every
  # migration, function still reports success). Setting it here makes the
  # safety property hold unconditionally rather than depending on every
  # caller remembering the documented contract -- safe and idempotent to set
  # again even when a stricter caller already has (`set -e`/`-u`/`-o
  # pipefail` are shell-global flags, not function-scoped; re-asserting an
  # already-set flag is a no-op). This intentionally leaves the calling
  # shell in `-euo pipefail` mode after this function returns, matching the
  # documented contract every real caller already independently opts into.
  set -euo pipefail

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

  # ISS-2026-309: creating the three roles is NOT enough to mirror a real Supabase project.
  # Supabase also ships an ALTER DEFAULT PRIVILEGES rule, granted BY postgres on schema
  # public, that gives anon/authenticated/service_role EXECUTE on every newly created
  # function (and the table/sequence equivalents). Read verbatim from the live project's
  # pg_default_acl:
  #
  #   f (function) public postgres=X/postgres | anon=X/postgres | authenticated=X/postgres | service_role=X/postgres
  #   r (table)    public postgres=arwdDxtm/postgres | anon=arwdDxtm/... | authenticated=... | service_role=...
  #   S (sequence) public postgres=rwU/postgres | anon=rwU/... | authenticated=... | service_role=...
  #
  # Without this, a `revoke execute on function public.f() from public` -- which revokes the
  # PUBLIC pseudo-role and NOT the anon/authenticated roles -- looks correct locally and
  # leaves the function anon-executable on the hosted project. That is exactly how two
  # SECURITY DEFINER wrappers (public.evaluate_ip_access, the 7-arg
  # public.raise_observability_alert) shipped anon-reachable while
  # scripts/db-tests/public-api-wrapper-regression.sql -- which DOES assert exhaustive grant
  # parity, and is not at fault -- passed green. The gate was correct; the environment it ran
  # in did not reproduce the condition. Mirroring the rule here makes that whole class visible
  # to the existing gate before it reaches a real project.
  echo "==> setup-disposable-db: mirroring Supabase's ALTER DEFAULT PRIVILEGES on schema public (ISS-2026-309)"
  psql "$CARGOGRID_TEST_DB_URL" -v ON_ERROR_STOP=1 -c "
alter default privileges in schema public grant execute on functions to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
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
