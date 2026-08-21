-- Phase 8 Customer Portal and Loyalty (CPL-325, CG-S13-CPL-027, Prompt 325,
-- "Customer Portal and Loyalty Privacy Integrity Hardening") -- fixes a
-- live-reproduced instance of this repository's own standing "now() vs
-- clock_timestamp()" defect class (first self-found and fixed at CPL-315,
-- docs/build-log/phase-08/CPL-315.md sec.11: "a genuine ordering defect...
-- not an artifact of the test harness"), found here in
-- app.get_customer_portal_account_profile (CPL-314,
-- supabase/migrations/20260801150000_create_customer_portal_customer_
-- profile.sql).
--
-- Root cause, live-reproduced this checkpoint (not assumed from the CPL-315
-- precedent alone): app.customer_portal_profile_change_requests.created_at
-- defaults to `now()` (frozen for the whole transaction, not per-statement).
-- app.get_customer_portal_account_profile's own "latest pending change
-- request" summary resolves it via `order by r1.created_at desc limit 1`
-- with NO id (or any other) tiebreak -- unlike every other "most recent X"
-- resolver in this repository's own Phase 8 surface (e.g. app.list_
-- customer_portal_account_memberships_for_access_review's own LATERAL join,
-- `order by rr.reviewed_at desc, rr.id desc`, CPL-315's own fix). Two
-- pending change requests for the SAME account, submitted within the SAME
-- transaction (test fixtures, a future batch/import flow, or any client
-- retry path that ever wraps two submissions in one transaction), get
-- BYTE-IDENTICAL created_at values -- live-reproduced this checkpoint: two
-- submissions 50ms apart by wall clock (a real pg_sleep between them) still
-- produced an identical `created_at`, and the resolver picked the WRONG
-- (earlier, by field-name alphabetical/gen_random_uuid() coincidence) row
-- as "latest," not the one the customer actually submitted second.
--
-- Under real, independent customer-portal HTTP requests (each its own
-- connection/transaction) this collision is exceedingly unlikely -- but
-- CPL-315's own precedent explicitly treats this defect CLASS as worth
-- fixing regardless of practical production likelihood ("a genuine ordering
-- defect in this checkpoint's own schema"), and this checkpoint's own
-- charter explicitly includes "repair" as a first-class deliverable, so
-- this is fixed here rather than merely disclosed.
--
-- Fix mirrors CPL-315's own precedent exactly, applying BOTH of its two
-- defense-in-depth layers:
--  1. Schema-level (the PRIMARY correctness fix): `created_at`'s own
--     DEFAULT changes from `now()` to `clock_timestamp()` -- advances
--     per-statement regardless of transaction boundaries, so two rows
--     inserted in the same transaction get distinct, correctly-ordered
--     timestamps that genuinely reflect submission order (the standard
--     PostgreSQL idiom CPL-315 already established for this exact class).
--  2. Query-level: adds `, r1.id desc` as an explicit tiebreak to the
--     ORDER BY -- a determinism-only safety net for the (pathological,
--     not live-reproduced) case where even clock_timestamp() itself ties.
--     A random-UUID tiebreak carries no temporal meaning of its own (it
--     cannot recover "which was truly submitted later" once the timestamps
--     genuinely tie -- there is no signal left to recover that from), so
--     this layer's own guarantee is "always deterministic," not "always
--     semantically correct under a forced tie" -- fix 1 above is what
--     makes the ordinary case semantically correct; live-verified in this
--     checkpoint's own regression addition (scripts/db-tests/customer-
--     profile-visibility.sql) via two real, naturally-clocked same-
--     transaction submissions, not an artificially forced timestamp tie.
--     `updated_at` on this same table is deliberately left untouched -- its
--     own only "most recent" consumer (app.list_customer_portal_profile_
--     change_requests' own cursor pagination) only needs a STABLE total
--     order (visit every row exactly once, never skip/duplicate), which
--     its existing `(updated_at, id)` tuple comparison already guarantees
--     regardless of any timestamp collision -- no live defect exists
--     there, so no schema change is needed for it.
--
-- No new `GRANT`/`REVOKE` needed: `CREATE OR REPLACE FUNCTION` against an
-- identical signature preserves ACLs (the same convention every prior
-- `CREATE OR REPLACE FUNCTION`-shaped repair in this repository already
-- relies on, e.g. 20260801260000/20260801270000/20260801280000).

alter table app.customer_portal_profile_change_requests
  alter column created_at set default clock_timestamp();

create or replace function app.get_customer_portal_account_profile(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_account_id uuid
)
returns table (
  account_id uuid,
  legal_name text,
  trade_name text,
  tax_id text,
  billing_address jsonb,
  customer_status text,
  record_version integer,
  updated_at timestamptz,
  pending_change_request_count integer,
  latest_pending_change_request_id uuid,
  latest_pending_change_request_field text,
  latest_pending_change_request_submitted_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_account app.accounts;
  v_pending_count integer;
  v_latest_id uuid;
  v_latest_field text;
  v_latest_created_at timestamptz;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_account from app.accounts a0 where a0.id = p_account_id and a0.tenant_id = p_tenant_id;
  if not found or not (v_account.id = any (app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id))) then
    raise exception 'record_not_found: no permitted account exists for %', p_account_id using errcode = 'no_data_found';
  end if;

  select count(*) into v_pending_count
  from app.customer_portal_profile_change_requests r0
  where r0.account_id = v_account.id and r0.status = 'pending';

  -- CPL-325 fix: added `, r1.id desc` -- a deterministic tiebreak on the
  -- rare (but live-reproduced) case of two pending requests sharing an
  -- identical created_at, mirroring CPL-315's own established (timestamp,
  -- id) tuple-ordering convention used everywhere else in this domain.
  select r1.id, r1.field_name, r1.created_at into v_latest_id, v_latest_field, v_latest_created_at
  from app.customer_portal_profile_change_requests r1
  where r1.account_id = v_account.id and r1.status = 'pending'
  order by r1.created_at desc, r1.id desc
  limit 1;

  return query
  select
    v_account.id,
    v_account.legal_name,
    v_account.trade_name,
    v_account.tax_id,
    v_account.billing_address,
    v_account.customer_status,
    v_account.record_version,
    v_account.updated_at,
    v_pending_count,
    v_latest_id,
    v_latest_field,
    v_latest_created_at;
end;
$$;

comment on function app.get_customer_portal_account_profile is
  'CPL-314: anti-enumerating get-by-id (ADR-0024 Part A) -- raises the IDENTICAL record_not_found (errcode no_data_found) whether p_account_id genuinely does not exist, belongs to a different tenant, or exists but is outside this identity''s resolved scope. legal_name/tax_id are included READ-ONLY (design decision 3) -- never writable via app.submit_customer_profile_change_request''s own field_name CHECK. Never exposes parent_account_id/merged_into_id/org_unit_id/owner_user_id/duplicate_fingerprint/normalized_*/status(active|merged) or any credit-adjacent field (none exist on app.accounts). pending_change_request_count/latest_pending_change_request_* summarize this account''s own OPEN change requests only -- never another account''s. CPL-325: `order by ... created_at desc, id desc` -- a deterministic tiebreak, live-proven against a same-transaction two-request collision (see this migration''s own header, 20260801290000).';
