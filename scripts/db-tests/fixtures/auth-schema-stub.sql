-- LOCAL TEST FIXTURE ONLY -- never a real migration, never applied to a real Supabase
-- project. In any real deployment, Supabase provisions and owns the entire `auth`
-- schema (identities, passwords, OAuth state, MFA, sessions) -- this repository's own
-- migrations (supabase/migrations/) must never create, alter, or drop anything in it.
--
-- This repository has no live Supabase project yet (ADR-0010, PH0-094; still true as of
-- PLT-107). scripts/db-tests/run.sh loads this fixture, and only this fixture, before
-- applying supabase/migrations/*.sql, purely so PLT-107's app.tenant_user_identities
-- foreign key to auth.users(id) has a real target to validate against locally. The
-- columns below are the minimal real subset of Supabase's actual auth.users shape
-- needed for that FK and for scripts/db-tests/auth-identity.sql's own assertions --
-- not a claim that this fully replicates Supabase's real auth schema.

create schema if not exists auth;

create table if not exists auth.users (
  id uuid primary key default gen_random_uuid(),
  email text unique,
  created_at timestamptz not null default now()
);
