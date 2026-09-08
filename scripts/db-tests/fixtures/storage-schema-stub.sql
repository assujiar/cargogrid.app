-- LOCAL TEST FIXTURE ONLY -- never a real migration, never applied to a real Supabase
-- project. In any real deployment, Supabase provisions and owns the entire `storage`
-- schema (buckets, objects, the Storage API's own upload/download/RLS machinery) --
-- this repository's own migrations (supabase/migrations/) only ever INSERT a bucket
-- row and assert an RLS posture against it, mirroring the `auth` schema stub's own
-- rationale exactly (auth-schema-stub.sql's own header): a disposable bare Postgres
-- used by scripts/db-tests/run.sh has no Supabase-managed `storage` schema of its
-- own, so CG-AUDIT-2026-09-02 A6's bucket-provisioning migration
-- (20260908010000_close_a6_storage_bucket_and_malware_scan_job_type.sql) would fail
-- to apply locally without this fixture.
--
-- Column shapes here are the minimal real subset of Supabase's actual
-- storage.buckets/storage.objects tables needed for that migration's own INSERT and
-- ALTER TABLE ... ENABLE ROW LEVEL SECURITY statements to apply, and for
-- scripts/db-tests/tenant-documents-storage-malware-scan.sql's own assertions --
-- not a claim that this fully replicates Supabase's real Storage schema (no
-- storage-api service exists in this disposable database at all, so no test here
-- ever exercises a real object upload/download over HTTP; that surface is covered
-- by lib/malware-scan/*.server.test.ts's own mocked-client unit tests instead).

create schema if not exists storage;

create table if not exists storage.buckets (
  id text primary key,
  name text not null,
  owner uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  public boolean not null default false,
  avif_autodetection boolean not null default false,
  file_size_limit bigint,
  allowed_mime_types text[],
  owner_id text
);

create table if not exists storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text references storage.buckets (id),
  name text,
  owner uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_accessed_at timestamptz not null default now(),
  metadata jsonb,
  owner_id text,
  user_metadata jsonb
);
