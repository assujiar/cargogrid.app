-- LOCAL TEST FIXTURE ONLY -- never a real migration, never applied to a real Supabase
-- project. In any real deployment, Supabase provisions and owns the entire `auth`
-- schema (identities, passwords, OAuth state, MFA, sessions) -- this repository's own
-- migrations (supabase/migrations/) must never create, alter, or drop anything in it.
--
-- A live Supabase project now exists and is fully migrated -- `cargogrid.app`
-- (awdlicmwzdxquopwtcfd), ap-northeast-1, PostgreSQL 17.6, all 306 migrations applied
-- (docs/build-log/phase-09/LIVE_SUPABASE_MIGRATION_REPORT.md). The former claim here that
-- "this repository has no live Supabase project yet (ADR-0010, PH0-094; still true as of
-- PLT-107)" was stale on both counts, and corrected at CG-S15-HDN-001 (Prompt 369) as part
-- of Step 15's own state freeze: it is no longer true, and neither ADR-0010 nor PH0-094
-- ever asserted it (both were checked directly -- the citation was itself wrong). The
-- fixture is still required, and still local-only: run.sh applies migrations to a
-- disposable bare Postgres that has no Supabase-managed `auth` schema of its own.
-- run.sh loads this fixture, and only this fixture, before
-- applying supabase/migrations/*.sql, purely so PLT-107's app.tenant_user_identities
-- foreign key to auth.users(id) has a real target to validate against locally. The
-- columns below are the minimal real subset of Supabase's actual auth.users shape
-- needed for that FK and for scripts/db-tests/auth-identity.sql's own assertions --
-- not a claim that this fully replicates Supabase's real auth schema.

create schema if not exists auth;

-- Column TYPES here must match the real auth.users, not merely its column names. Supabase
-- declares email and role as character varying(255); declaring them `text` here let a function
-- that returns `au.email` inside a `returns table (... text ...)` pass CI and fail on a real
-- project with `42804: structure of query does not match function result type -- Returned type
-- character varying(255) does not match expected type text`. Verified against the live project:
--   email character varying(255) | role character varying(255) | phone text
create table if not exists auth.users (
  id uuid primary key default gen_random_uuid(),
  email varchar(255) unique,
  role varchar(255),
  phone text,
  created_at timestamptz not null default now()
);

-- Real Supabase auth.uid()/auth.role(), reproduced verbatim from Supabase's own published
-- reference implementation (both read the `request.jwt.claims` GUC PostgREST/Supabase's
-- real request layer sets per request) -- added at PLT-113 (RLS Tenant Policy Foundation)
-- so this checkpoint's RLS policies can be exercised against a simulated authenticated
-- session (`set local role authenticated; set local request.jwt.claims = '{"sub": "...",
-- "role": "authenticated"}';`), the same mechanism a real Supabase/PostgREST deployment
-- uses, not a stand-in behavior invented for this repository.
create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::json->>'sub', '')::uuid
$$;

create or replace function auth.role()
returns text
language sql
stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::json->>'role', '')::text
$$;
