# Live Supabase Migration Report

Applying `supabase/migrations/` to the live `cargogrid.app` project for the first time, before
Phase 10 begins.

- **Project:** `cargogrid.app` (`awdlicmwzdxquopwtcfd`), `ap-northeast-1`, PostgreSQL 17.6
- **Branch:** `claude/supabase-cargogrid-migration-10qvt8`
- **Starting state:** empty — 0 tables, 0 rows in the migration ledger
- **Date:** 2026-08-23

## Why this was worth doing

Every defect below passed CI and failed on a real project. They share one root cause: the CI
fixture models an environment that differs from a hosted Supabase project, so the resolution
path production actually takes was never exercised. Each fix therefore lands at the root — the
extension's schema, the stub's column types — rather than at the call site, so CI can catch the
class on its own from now on.

## Result

| | |
|---|---|
| Migrations applied | **306 / 306**, no SQL errors |
| Objects created | 603 tables, ~2,900 routines, 38 views, 17 types |
| RLS | 568 tables enabled, 448 policies |
| Ledger | 306 rows, in sync with `supabase/migrations/` |
| Security advisors | 0 findings attributable to application code |
| db-tests (live) | **199 / 229 passed**; 22 of the 30 failures are harness limitations — see [Test results](#test-results) |

## Defects found and fixed

### 1. pgcrypto resolved from the wrong schema — `75278d3`

`20260716075355_create_tenants.sql` ran an unqualified `create extension if not exists
pgcrypto`. A hosted project ships pgcrypto pre-installed into `extensions`, making that
statement a silent no-op; a bare CI Postgres has nothing pre-installed, so it creates pgcrypto
in `public`. Any function pinning `set search_path = app, public, pg_temp` therefore resolved
pgcrypto on CI and failed on a real project.

Proven on the live project:

```
default search_path : "$user", public, extensions
  pinned search_path -> function digest(unknown, unknown) does not exist
  unpinned           -> resolves
```

plpgsql bodies are not validated at `CREATE`, so 20 deployed functions were broken only at call
time: webhook signature computation, API key hashing and rotation, public shipment tracking
tokens, vendor intake tokens, and the five transaction-lineage hash-chain triggers. The failure
only became visible when migration `20260730610000` — which is `language sql`, whose body *is*
validated — refused to apply.

**Fix:** install pgcrypto into `extensions` explicitly (creating the schema first, so CI matches
the hosted layout), and add `extensions` to the pinned search_path of the 39 functions that call
it, across 22 migrations.

### 2. Unpinned functions inherit the caller's search_path — `11bd409`

The first fix left functions with no `set search_path` alone, assuming they fall back to the
session default. They do not: they inherit the **caller's** search_path. `app.authenticate_api_key`
resolved `digest()` when called directly and failed when reached from a function pinning
`set search_path = app, pg_temp`:

```
ERROR: 42883: function digest(text, unknown) does not exist
CONTEXT: PL/pgSQL function authenticate_api_key(text) line 10
         called from ingest_direct_device_telemetry_batch
```

**Fix:** pinned `set search_path = app, public, extensions, pg_temp` on the seven affected
functions (`create_api_key`, `rotate_api_key`, `authenticate_api_key`, `register_webhook_endpoint`,
`rotate_webhook_secret`, `compute_webhook_signature`, `get_quotation_for_customer_decision`).
This also closes the mutable-search_path advisory on those seven.

### 3. `auth.users.email` is `varchar(255)`, not `text` — `d82cd6f`

```
ERROR: 42804: structure of query does not match function result type
DETAIL: Returned type character varying(255) does not match expected type text in column 16
```

`scripts/db-tests/fixtures/auth-schema-stub.sql` declared `email` as `text`. Supabase declares
it `varchar(255)` (as it does `role`; `phone` is `text`). A function selecting `au.email` into a
`returns table (... text ...)` type-checks on CI and fails at call time on a real project.

**Fix:** cast the four affected sites to `::text`, and correct the stub's column types so CI can
catch this class itself.

### 4. RLS policies re-evaluating `auth.uid()` per row — `11bd409`

157 of 448 policies called `auth.uid()` directly inside `USING` / `WITH CHECK`. A bare call
cannot be hoisted by the planner and is evaluated once per candidate row; wrapping it in a
scalar subquery makes it an InitPlan evaluated once per statement. `auth.uid()` is `STABLE` and
row-independent, so the forms are semantically identical.

Rewrote `auth.uid()` as `(select auth.uid())` at 228 call sites in 171 policy statements across
65 migrations. The cost is invisible while the tables are empty; it would not stay invisible once
they carry tenant data.

## Verified on the live project

```
pgcrypto schema                                          extensions
pgcrypto callers with a pinned path lacking extensions    0
SECURITY DEFINER functions                             1,878  (100% pinned search_path)
SECURITY DEFINER with mutable search_path                  0
SECURITY DEFINER + mutable + callable by anon/auth          0
```

## Advisor findings

**Security — 922 raised, 0 attributable to application code.**

| Finding | Count | Assessment |
|---|---|---|
| `function_search_path_mutable` | 791 | Not exploitable. All 791 are `security invoker`, so they carry no privilege to escalate. Every one of the 1,878 `SECURITY DEFINER` functions pins its search_path. |
| `rls_enabled_no_policy` | 120 | INFO. Default-deny by design. |
| `extension_in_public` | 3 | postgis, pg_trgm, btree_gist. See open items. |
| `*_security_definer_function_executable` | 6 | PostGIS's own `st_estimatedextent`, exposed because postgis sits in `public`. |
| `rls_disabled_in_public` | 1 (ERROR) | PostGIS's own `spatial_ref_sys`. |
| `auth_leaked_password_protection` | 1 | Dashboard setting. |

Note that `app` is **not** exposed through the Data API (`db_schema = public,graphql_public`), so
no `app` table is reachable over PostgREST regardless of its RLS state.

**Performance — 2,031 raised.** 982 `unused_index` (noise: the database has served no queries)
and 892 `unindexed_foreign_keys` (a design question, not a defect). The 157 `auth_rls_initplan`
warnings were the actionable set and are fixed above.

## Test results

`scripts/db-tests/*.sql` were executed against the live project. `run.sh` could not be used —
this environment blocks port 5432, so psql cannot connect — so the files were driven through the
Management API by a harness that reproduces the psql behaviours the tests depend on:
per-statement autocommit (so a `set local` inside a `do` block cannot leak forward) and psql
variables (`\set`, `:name`, `\gset`).

**199 / 229 passed.** Of the 30 failures, 22 are harness limitations rather than defects:

| Cause | Count | Why it cannot work over the Management API |
|---|---|---|
| `\! bash …helper.sh` | 15 | psql's shell escape. These tests deliberately open a second concurrent psql session to exercise row locking and race conditions. There is no shell and no second session. |
| `pg_temp` function collisions | 5 | `run.sh` starts a new psql session per file, so each gets a fresh `pg_temp`. Pooled HTTP connections reuse one across files. |
| Temp tables not surviving | 2 | A `\gset` splits the file across requests, and a temp table does not outlive its connection. |

These are covered by CI, which runs the real `run.sh` against a Postgres service container.

### One test defect found

`hris-overtime-timesheet.sql` asserts `eligible_classification = 'weekday'`, but derives the
work date from a clock-in recorded with `now()`. It therefore fails on Saturdays and Sundays —
this run was Sunday 2026-08-23, and the server correctly classified the overtime as `weekend`.
The production code is right; the test is date-dependent and will fail in CI on any weekend run.

## Open items for Phase 10

Nothing below blocks Phase 10. Each is recorded because it could not be resolved from this
session, not because it was deprioritised.

1. **Six assertion failures not individually root-caused.**
   `customer-loyalty-membership-tier`, `customer-warehouse-order-visibility`,
   `disaster-recovery-enterprise-support`, `enterprise-monitoring-observability`,
   `finance-job-profitability`, `support-access`. All six use relative time heavily (5–15
   references each) and a sibling case in the same run was proven date-dependent, but that is a
   hypothesis for these six, not a finding — each needs its own triage. Confirm against a
   weekday CI run before treating any as a production defect.

2. **`rbac-enforcement.sql` times out on the catalogue scan.** The test walks `pg_proc` and calls
   `pg_get_functiondef()` for every function in `app`. At ~2,900 functions this exceeds the
   statement timeout. Not a production code path, but it will keep getting slower as the schema
   grows and will eventually time out in CI too. Worth scoping the scan or raising its timeout.

3. **postgis, pg_trgm and btree_gist live in `public`.** This is the same root-cause class as
   defect 1 — extension placement — and moving them to `extensions` would clear seven of the
   eight non-noise security findings, including the sole ERROR. It was left alone deliberately:
   every function touching `geometry`/`geography` types or `ST_*` would need `extensions` added
   to its search_path, which is a far larger blast radius than the pgcrypto change and deserves
   its own prompt.

4. **`max_locks_per_transaction` is too low to drop the schema in one transaction.**
   `drop schema app cascade` fails with `53200: out of shared memory` at ~1,400 objects. The
   statement is atomic, so it rolls back cleanly and nothing is corrupted — but any teardown must
   drop objects in batches, each in its own transaction. Relevant to disaster-recovery runbooks.

5. **Migrations are not idempotent.** Tables are created with bare `create table` and there is no
   explicit transaction wrapper, so re-running any applied migration fails. The Management API
   wraps each file in one implicit transaction, so a file either lands whole or not at all, and
   `supabase_migrations.schema_migrations` is the only thing preventing a re-run. Worth stating
   explicitly in the deployment runbook.

6. **`auth.users` survives a schema reset.** The db-tests seed fixtures into `auth.users`, which
   is Supabase's schema and is untouched by dropping `app`. `run.sh` never has to think about
   this because it drops the whole disposable database. Any live test cycle must clear
   `auth.users` as part of teardown, or every rerun collides on `users_pkey`.

7. **Dashboard settings, not migrations.** Enable leaked-password protection (Auth → Password
   Protection). `spatial_ref_sys` cannot have RLS enabled — it belongs to the PostGIS extension
   and `postgres` is not superuser on a hosted project.
