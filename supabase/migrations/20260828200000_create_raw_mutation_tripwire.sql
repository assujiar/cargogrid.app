-- ISS-2026-259 (Step 16 historical-issue-backlog remediation, Track B Batch 8,
-- docs/runtime/KNOWN_ISSUES.md) -- app.audit_logs is structurally blind to raw-SQL or
-- infra-level data corruption: app.capture_audit_event only ever fires from inside an
-- RPC function, so a raw statement (a botched migration, or a support engineer's direct
-- psql intervention during an incident) leaves zero trace. Live-proved at HDN-384: a bare
-- `DELETE FROM app.leads;` left zero matching rows in app.audit_logs.
--
-- This migration adds a genuinely bounded, real, testable detection mechanism -- NOT a
-- fix for the underlying blindness (raw SQL will always be able to mutate a table without
-- going through app.capture_audit_event; that is inherent to how Postgres privileges
-- work, and is explicitly out of scope, per this entry's own text, of anything short of a
-- lower-level architectural addition such as WAL-based change capture). What this DOES
-- add is a passive, always-on tripwire: a statement-level trigger, attached directly to
-- the protected table (not routed through any application code path a raw statement could
-- bypass), that records every DELETE/UPDATE/TRUNCATE against that table regardless of
-- caller -- RPC-mediated or raw SQL alike -- into a durable log. A companion read
-- function then reports exactly which of those recorded mutations have no corresponding
-- app.audit_logs entry from the same database transaction, using Postgres's own
-- transaction id (txid_current()) as the correlation key -- not a fragile session flag or
-- a time-window heuristic, both of which would misfire on the (common, RPC-audit
-- ordering here typically mutate-then-audit) case where the audit call happens moments
-- after the mutation within the same function/transaction. Because the trigger and
-- app.capture_audit_event share one transaction whenever both fire, they always agree on
-- txid_current() regardless of statement order within that transaction.
--
-- Deliberately bounded scope, honestly disclosed, not silently generalized: this
-- migration attaches the mechanism to exactly 2 tables --
--   * app.leads: the identical table HDN-384's own live reproduction used, so the fix is
--     proven against the exact scenario the finding named, not a proxy.
--   * app.audit_logs itself: protects the audit trail's own integrity against direct
--     tampering (e.g. a raw DELETE erasing evidence of an incident) -- the single
--     highest-value target for this mechanism, and safe to include because this
--     repository already has one legitimate, self-auditing raw DELETE/UPDATE path against
--     this table (app.supreme_admin_delete_audit_log / app.supreme_admin_mutate_audit_log,
--     20260716113048_create_audit_trail.sql), which this migration's own regression proves
--     is correctly recognized as tracked (same-transaction capture_audit_event call), not
--     a false positive.
-- The 9 tables ISS-2026-265 separately named ("security/integrity-relevant" tables with an
-- existing but TRUNCATE-bypassable row trigger) are NOT covered here -- extending this
-- exact mechanism to them, or to any other table, is a mechanical follow-up (2 CREATE
-- TRIGGER statements per table, zero new code) deliberately left to a future task rather
-- than risked in one unreviewed pass across tables this session has not built fixtures
-- for. The general repo-wide blindness for every other ordinary table remains open,
-- exactly as this entry's own text already discloses -- this migration narrows, and does
-- not claim to close, that gap.
--
-- Fails open by design: an insert failure into the log itself (e.g. a future migration
-- accidentally revoking the trigger function's own access) is caught and downgraded to a
-- RAISE WARNING, never allowed to abort the underlying DML -- a detection mechanism must
-- never become an availability risk for the operation it observes.
--
-- Known, disclosed limitation of the txid correlation key -- coarse at TRANSACTION
-- granularity, not per-statement: if a single transaction contains BOTH an audited
-- mutation and a separate, genuinely untracked one (e.g. a multi-statement raw script
-- that deletes from 2 protected tables but only explicitly audits one), the untracked
-- statement would share the audited one's own txid and be missed -- app.audit_logs
-- existing at all for that txid is treated as "this transaction was audited," not "this
-- specific statement was." The realistic threat model this migration targets -- a single
-- raw autocommit statement, exactly HDN-384's own `DELETE FROM app.leads;` reproduction,
-- with nothing else in its transaction -- is unaffected by this limitation; a genuinely
-- more precise (per-statement) mechanism would need to carry a correlation id through
-- every RPC call explicitly, a materially larger change than this migration's own bounded
-- scope. scripts/db-tests/raw-mutation-tripwire.sql''s own regression is deliberately
-- structured as one isolated top-level transaction per case specifically to test the
-- realistic scenario correctly, not to paper over this limitation.
--
-- Also disclosed: TRUNCATE coverage (both protected tables carry an AFTER TRUNCATE
-- trigger below) is real but NOT exercised by the local db-tests regression -- TRUNCATE
-- is a database-wide, cross-tenant, destructive statement, unsafe to run against the
-- single shared disposable database scripts/db-tests/run.sh executes every *.sql file
-- against in sequence. See the regression file's own header for the full reasoning.

-- ---------------------------------------------------------------------------------------
-- 1. Correlation key: app.audit_logs gains a nullable xact_id column, defaulted (not
--    backfilled -- a volatile default on ADD COLUMN would force a full table rewrite to
--    populate a value for pre-existing rows that would carry no real meaning anyway, since
--    txid_current() at ALTER TABLE time reflects this migration's own transaction, not
--    each historical row's real one). Every future app.capture_audit_event() insert picks
--    this up automatically -- no change to that function's body, signature, or behavior.
-- ---------------------------------------------------------------------------------------
alter table app.audit_logs add column xact_id bigint;
alter table app.audit_logs alter column xact_id set default txid_current();
comment on column app.audit_logs.xact_id is
  'ISS-2026-259: the Postgres transaction id (txid_current()) that inserted this row, captured automatically via column default. Used by app.list_untracked_table_mutations() to correlate a tripwire-logged mutation with the audit event (if any) that explains it -- both share the same value whenever a legitimate RPC mutates a protected table and calls app.capture_audit_event() in the same transaction, regardless of which happens first. NULL on every row inserted before this migration (a pre-existing row was never meaningfully "in" any transaction this mechanism can compare against).';

-- ---------------------------------------------------------------------------------------
-- 2. The tripwire log itself. Deliberately in `public` schema, not `app` -- the same
--    established technique as public.security_state_snapshots (ISS-2026-254) and the
--    ISS-2026-267 advisory lock: it survives the composed in-place restore procedure's own
--    step (a) `app`-schema drop, so evidence of a mutation that happened shortly before an
--    interrupted restore is not itself lost along with the schema. RLS enabled and every
--    default table privilege explicitly revoked from the moment of creation -- learned
--    directly from this repository's own ISS-2026-299 (the identical class of gap,
--    self-caught only AFTER the fact for public.security_state_snapshots); not repeating
--    that mistake here.
-- ---------------------------------------------------------------------------------------
create table public.raw_mutation_tripwire_log (
  id uuid primary key default gen_random_uuid(),
  table_name text not null,
  operation text not null,
  affected_row_count integer,
  xact_id bigint not null default txid_current(),
  database_user text not null default session_user,
  application_name text,
  client_addr inet,
  statement_query text,
  detected_at timestamptz not null default clock_timestamp(),
  constraint raw_mutation_tripwire_log_operation_check check (operation in ('DELETE', 'UPDATE', 'TRUNCATE'))
);

comment on table public.raw_mutation_tripwire_log is
  'ISS-2026-259: every DELETE/UPDATE/TRUNCATE against a table this migration protects (app._raw_mutation_tripwire trigger), regardless of caller -- RPC-mediated or raw SQL. Deliberately public schema so it survives the in-place restore procedure''s own app-schema drop (same technique as public.security_state_snapshots, ISS-2026-254). Compare against app.audit_logs via xact_id (app.list_untracked_table_mutations does this) to find mutations with no corresponding audit trail entry.';

alter table public.raw_mutation_tripwire_log enable row level security;
revoke all on public.raw_mutation_tripwire_log from public, anon, authenticated;
grant all on public.raw_mutation_tripwire_log to service_role;

create index raw_mutation_tripwire_log_xact_id_idx on public.raw_mutation_tripwire_log (xact_id);
create index raw_mutation_tripwire_log_detected_at_idx on public.raw_mutation_tripwire_log (detected_at);
create index audit_logs_xact_id_idx on app.audit_logs (xact_id);

-- ---------------------------------------------------------------------------------------
-- 3. The trigger function. SECURITY DEFINER so the INSERT into the log succeeds
--    regardless of the DML caller's own privileges (the entire point: a raw psql session
--    with elevated database credentials but no grant on this table must still be captured
--    -- exactly the scenario this entry describes). Cannot be invoked directly as an
--    ordinary function (Postgres refuses to call a `returns trigger` function outside
--    trigger context), so no separate REVOKE/GRANT is needed or meaningful here, matching
--    this repository's own existing convention of never granting on trigger functions
--    (e.g. app.set_lead_computed_fields has none).
-- ---------------------------------------------------------------------------------------
create function app._raw_mutation_tripwire()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_row_count integer;
begin
  if tg_op = 'DELETE' then
    select count(*) into v_row_count from old_rows;
  elsif tg_op = 'UPDATE' then
    select count(*) into v_row_count from new_rows;
  else
    -- TRUNCATE: no transition table is available (standard Postgres limitation), so the
    -- affected row count is genuinely unknown here, not merely uncomputed.
    v_row_count := null;
  end if;

  begin
    insert into public.raw_mutation_tripwire_log (
      table_name, operation, affected_row_count, database_user, application_name, client_addr, statement_query
    ) values (
      tg_table_schema || '.' || tg_table_name, tg_op, v_row_count, session_user,
      current_setting('application_name', true), inet_client_addr(), current_query()
    );
  exception when others then
    -- Fail open: a detection mechanism must never become a reason the underlying,
    -- possibly entirely legitimate, DML statement itself fails.
    raise warning 'app._raw_mutation_tripwire: failed to record tripwire event for %.% (%): %', tg_table_schema, tg_table_name, tg_op, sqlerrm;
  end;

  return null;
end;
$$;

comment on function app._raw_mutation_tripwire is
  'ISS-2026-259: statement-level AFTER trigger function -- records every DELETE/UPDATE/TRUNCATE against a protected table into public.raw_mutation_tripwire_log, regardless of whether the caller went through app.capture_audit_event. Uses PG10+ transition tables (old_rows/new_rows) for a real affected-row count on DELETE/UPDATE; TRUNCATE never gets one, a standard Postgres limitation, not a bug here. Fails open (RAISE WARNING, never an exception) so a logging failure can never block the DML it observes.';

-- Postgres does not allow a transition table (REFERENCING ... AS ...) on a trigger that
-- covers more than one event -- live-caught running this migration against a real disposable
-- database ("ERROR: transition tables cannot be specified for triggers with more than one
-- event"), not assumed from documentation. Fixed by splitting DELETE and UPDATE into 2
-- separate single-event triggers per table (each declaring only the transition table it
-- actually needs), plus the existing separate TRUNCATE trigger -- 3 triggers per table, all
-- still sharing the identical app._raw_mutation_tripwire function body unchanged, since its
-- own tg_op branch only ever references the transition table alias the firing trigger
-- itself declared.

-- app.leads: reproduces HDN-384's own live-proved scenario directly.
create trigger leads_raw_mutation_tripwire_delete
  after delete on app.leads
  referencing old table as old_rows
  for each statement
  execute function app._raw_mutation_tripwire();

create trigger leads_raw_mutation_tripwire_update
  after update on app.leads
  referencing new table as new_rows
  for each statement
  execute function app._raw_mutation_tripwire();

create trigger leads_raw_mutation_tripwire_truncate
  after truncate on app.leads
  for each statement
  execute function app._raw_mutation_tripwire();

-- app.audit_logs: protects the audit trail's own integrity. app.supreme_admin_delete_
-- audit_log / app.supreme_admin_mutate_audit_log are this table's only 2 legitimate
-- direct-mutation paths, and both already call app.capture_audit_event in the same
-- transaction (the "recursive self-audit" pattern that table's own original migration
-- comment names) -- this migration's own regression proves those 2 paths are correctly
-- recognized as tracked, not misflagged.
create trigger audit_logs_raw_mutation_tripwire_delete
  after delete on app.audit_logs
  referencing old table as old_rows
  for each statement
  execute function app._raw_mutation_tripwire();

create trigger audit_logs_raw_mutation_tripwire_update
  after update on app.audit_logs
  referencing new table as new_rows
  for each statement
  execute function app._raw_mutation_tripwire();

create trigger audit_logs_raw_mutation_tripwire_truncate
  after truncate on app.audit_logs
  for each statement
  execute function app._raw_mutation_tripwire();

-- ---------------------------------------------------------------------------------------
-- 4. The read/detection side. service_role only (no `authenticated` grant at all) --
--    this is DR/security-forensics operator tooling, not a tenant-facing capability,
--    exactly matching app.detect_reverted_security_state's own (ISS-2026-254) grant shape.
-- ---------------------------------------------------------------------------------------
create function app.list_untracked_table_mutations(p_since timestamptz default now() - interval '7 days')
returns setof public.raw_mutation_tripwire_log
language sql
stable
security definer
set search_path = app, public, pg_temp
as $$
  select t.*
  from public.raw_mutation_tripwire_log t
  where t.detected_at >= p_since
    and not exists (
      select 1 from app.audit_logs a where a.xact_id = t.xact_id
    )
  order by t.detected_at desc;
$$;

comment on function app.list_untracked_table_mutations is
  'ISS-2026-259: run this to find every DELETE/UPDATE/TRUNCATE tripwire event (since p_since, default last 7 days) against a protected table with no corresponding app.audit_logs entry from the same database transaction (correlated via xact_id) -- i.e. every mutation that bypassed the audit trail entirely. An empty result does not mean nothing happened outside p_since, and only covers the tables app._raw_mutation_tripwire is actually attached to (app.leads, app.audit_logs as of this migration) -- not a repository-wide guarantee.';

revoke execute on all functions in schema app from public;
grant execute on function app.list_untracked_table_mutations(timestamptz) to service_role;

-- Option 2 wrapper (RGL-394): app is not exposed to PostgREST directly -- every
-- externally-callable app.* function needs a matching public.* wrapper, enforced by
-- scripts/db-tests/public-api-wrapper-regression.sql's own zero-tolerance guard.
create function public.list_untracked_table_mutations(p_since timestamptz default now() - interval '7 days')
returns setof public.raw_mutation_tripwire_log
language sql
volatile
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_untracked_table_mutations(p_since);
$wrap$;

comment on function public.list_untracked_table_mutations(p_since timestamptz) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_untracked_table_mutations with an identical grant set, never a reimplementation. See docs/build-log/release-go-live/RGL-394.md.';

-- 20260826010000_harden_public_api_data_wrappers_tierc_fixes.sql's own amended
-- convention (Finding 2 there): Supabase's own platform-level default privilege
-- grants EXECUTE on every new public-schema function to anon/authenticated/service_role
-- automatically at CREATE time -- `revoke ... from public` alone (the PUBLIC
-- pseudo-role) never touches that. Must revoke from the named roles explicitly.
revoke execute on function public.list_untracked_table_mutations(p_since timestamptz) from anon, authenticated, service_role, public;
grant execute on function public.list_untracked_table_mutations(p_since timestamptz) to service_role;
