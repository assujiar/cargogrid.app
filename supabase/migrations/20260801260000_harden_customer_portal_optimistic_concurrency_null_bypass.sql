-- CPL-324 (CG-S13-CPL-026, Prompt 324, Customer Portal and Loyalty
-- Integrated Verification) -- bounded defect repair, not new capability.
--
-- ===========================================================================
-- Root cause, independently re-derived from direct code reads (not accepted
-- from any lens report on its word).
-- ===========================================================================
--
-- The standing repository-wide defect class this task's own orchestrator
-- instructions name explicitly ("a bare 'record_version <> p_expected_
-- version' check that silently passes when p_expected_version IS NULL
-- unless the UPDATE itself also repeats the version predicate") is present
-- in TWELVE Phase 8 customer-portal mutation RPCs across FIVE already-
-- applied migration files. In PL/pgSQL, `x <> NULL` evaluates to SQL NULL,
-- not TRUE, so `if v_row.record_version <> p_expected_version then raise
-- ...` never fires when a caller supplies p_expected_version = NULL --
-- execution falls straight through to the UPDATE below. In each of the
-- twelve functions fixed here, that UPDATE's own WHERE clause named only
-- `id = <the row's own id>`, with no repeated `record_version =
-- p_expected_version` predicate and no `IF NOT FOUND` fallback -- so a
-- caller who omits (or forges NULL for) the version parameter silently
-- defeats the optimistic-concurrency guard entirely: the mutation proceeds
-- unconditionally, clobbering any intervening concurrent change with no
-- conflict ever raised.
--
-- Independently reproduced live (not assumed) against a fresh disposable
-- database, six of the twelve instances, before writing this fix: a
-- p_expected_version = NULL call to app.set_customer_portal_account_
-- membership_status, app.cancel_customer_quote_request, app.withdraw_
-- customer_profile_change_request, app.request_customer_booking_
-- cancellation, and the staff-facing app.respond_to_customer_shipment_
-- order_change_request all succeeded and silently advanced the row's own
-- status/record_version with no exception raised, exactly as this header
-- predicts. The remaining six were confirmed by direct code inspection
-- (identical shape: early check missing `p_expected_version is null or`,
-- UPDATE missing the repeated predicate) -- listed in full below.
--
-- This is NOT a tenant/account-scope escalation -- every one of the twelve
-- functions still independently enforces its own real RBAC/ownership check
-- before ever reaching the version comparison (re-confirmed this same
-- checkpoint: forged/cross-tenant/cross-account callers are still correctly
-- rejected). The exposure is a defeated optimistic-concurrency/lost-update
-- guard only: a genuine stale retry, or a client bug that omits the version
-- field, silently clobbers an intervening state change with no conflict
-- signal.
--
-- A full repository-wide grep of every remaining `record_version <>
-- p_expected_version` occurrence in the Phase 8 migration set (`supabase/
-- migrations/2026080*.sql`) was independently re-run and every OTHER hit
-- was individually read and confirmed ALREADY SAFE by one of two
-- established patterns, so is deliberately left untouched here:
--   (a) the UPDATE's own WHERE clause already repeats `and record_version =
--       p_expected_version` with an `if not found then raise 'stale_
--       version'` fallback (double-defended -- a NULL still correctly
--       yields zero matching rows and the fallback still fires) --
--       app.unlink_ticket_portal_record, app.update_customer_portal_
--       account_membership_role, every mutation in CPL-316 (loyalty
--       program/earning), CPL-317 (membership tier), CPL-318 (points
--       ledger/adjustment), and app.reverse_loyalty_benefit_entitlement
--       (CPL-319);
--   (b) the early check already carries `if p_expected_version is null or
--       v_row.record_version <> p_expected_version` -- every mutation in
--       CPL-320 (reward catalogue), CPL-321 (redemption approval/
--       fulfillment), CPL-322 (expiry/fraud prevention), and CPL-323
--       (liability reconciliation), each of which learned this exact lesson
--       at its own Tier C review before this checkpoint;
--   (c) app.redeem_loyalty_benefit_entitlement (CPL-319) uses `if
--       p_expected_version is not null and v_entitlement.record_version <>
--       p_expected_version` DELIBERATELY (its own comment: "p_expected_
--       version is nullable... when null, the atomic status='issued'
--       transition alone is the concurrency guard") -- its UPDATE's own
--       `where id = v_entitlement.id and status = 'issued'` is a real,
--       independent atomic guard, confirmed not a defect.
--
-- ===========================================================================
-- Fix: `CREATE OR REPLACE FUNCTION` against all twelve affected functions,
-- adding `p_expected_version is null or` to each early check AND repeating
-- `and record_version = p_expected_version` in each UPDATE's own WHERE
-- clause (with a matching `if not found then raise 'stale_version...
-- concurrently modified'` fallback) -- the exact two-part, already-proven
-- pattern this same migration set already uses correctly in CPL-320/321/
-- 322/323 and in app.unlink_ticket_portal_record/app.update_customer_
-- portal_account_membership_role. Every other line of every function below
-- is byte-identical to its own already-applied body -- no other predicate,
-- column, ordering, side effect, or anti-enumeration shape is touched, and
-- no already-applied migration file is edited (mirrors this repository's
-- own established `harden_*.sql` pattern, e.g. `20260801160000_harden_
-- customer_portal_ticket_link_invoice_status_gate.sql`).
--
-- Functions fixed (file : original line of the vulnerable early check):
--   1. app.accept_customer_portal_invite                              (20260801010000:554)
--   2. app.set_customer_portal_account_membership_status              (20260801010000:644)
--   3. app.update_customer_quote_request_draft                        (20260801030000:467)
--   4. app.submit_customer_quote_request                               (20260801030000:558)
--   5. app.cancel_customer_quote_request                                (20260801030000:637)
--   6. app.update_customer_booking_request_draft                      (20260801040000:478)
--   7. app.submit_customer_booking_request                             (20260801040000:555)
--   8. app.request_customer_booking_reschedule                        (20260801040000:626)
--   9. app.request_customer_booking_cancellation                      (20260801040000:699)
--  10. app.respond_to_customer_shipment_order_change_request           (20260801050000:683)
--  11. app.withdraw_customer_profile_change_request                    (20260801150000:414)
--  12. app.decide_customer_profile_change_request                      (20260801150000:690)
--
-- No new GRANT/REVOKE statement is needed (mirrors `20260801160000`'s own
-- identical note): every function below is `CREATE OR REPLACE` on an
-- already-existing, identical signature -- PostgreSQL preserves the
-- existing ACL across a replace.
--
-- Regression coverage: a new NULL-bypass regression block is added to each
-- of the five affected files' own `scripts/db-tests/*.sql` counterpart
-- (customer-portal-scope.sql, customer-quote-requests.sql, customer-
-- booking-requests.sql, customer-shipment-orders.sql, customer-profile-
-- visibility.sql), mirroring `scripts/db-tests/customer-loyalty-
-- redemption.sql`'s own already-established "NULL-bypass regression proof"
-- shape (NULL p_expected_version rejected with stale_version, row proven
-- byte-for-byte unchanged, then the real version succeeds).
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1/12. app.accept_customer_portal_invite (CPL-300)
-- ---------------------------------------------------------------------------

create or replace function app.accept_customer_portal_invite(
  p_membership_id uuid,
  p_expected_version integer,
  p_auth_user_id uuid
)
returns app.customer_portal_account_memberships
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_membership app.customer_portal_account_memberships;
  v_updated app.customer_portal_account_memberships;
begin
  perform app.assert_actor_is_session_identity(p_auth_user_id);

  select * into v_membership from app.customer_portal_account_memberships where id = p_membership_id for update;
  if not found then
    raise exception 'customer_portal_membership_not_found: %', p_membership_id using errcode = 'no_data_found';
  end if;

  -- Business rule (source prompt §"RPCs to create" item 4): only the identity
  -- the invite names may accept it -- a raw self-row-identity equality check,
  -- the same class app.get_self_employee/app.is_ticket_queue_member already
  -- document as correct-by-design (design decision 10).
  if v_membership.auth_user_id <> p_auth_user_id then
    raise exception 'insufficient_authority: only the invited identity may accept customer portal membership %', p_membership_id
      using errcode = 'insufficient_privilege';
  end if;

  -- CPL-324 Tier C fix: p_expected_version = NULL no longer silently
  -- bypasses this guard.
  if p_expected_version is null or v_membership.record_version <> p_expected_version then
    raise exception 'stale_version: customer portal membership % expected version % but found %', p_membership_id, p_expected_version, v_membership.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_membership.status <> 'invited' then
    raise exception 'invalid_transition: customer portal membership % is %, only a pending invite can be accepted', p_membership_id, v_membership.status
      using errcode = 'check_violation';
  end if;

  -- CPL-324 Tier C fix: repeat the version predicate as defense-in-depth.
  update app.customer_portal_account_memberships
  set status = 'active', accepted_at = now()
  where id = p_membership_id and record_version = p_expected_version
  returning * into v_updated;

  if not found then
    raise exception 'stale_version: customer portal membership % was concurrently modified (expected version %)', p_membership_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.customer_portal_account_membership_history
    (membership_id, auth_user_id, tenant_id, account_id, from_status, to_status, reason, requested_by)
  values
    (v_updated.id, v_updated.auth_user_id, v_updated.tenant_id, v_updated.account_id, 'invited', 'active', 'invite accepted', p_auth_user_id::text);

  -- Tier C security-rls review fix (moved from app.invite_customer_portal_
  -- user, see that function's own comment): the Layer-4 CHECK-required app.
  -- principal_memberships marker (design decision 2) is granted HERE, on
  -- genuine acceptance, not at invite time -- idempotent, safe to call every
  -- time. This is the point at which the identity first becomes entitled to
  -- live WMS/inventory (ATW-023) and portal-entry (app.actor_holds_
  -- customer_user_layer) access through the legacy resolver.
  perform app.grant_principal_membership(v_updated.auth_user_id, 'customer_user', v_updated.tenant_id, v_updated.account_id::text, v_updated.invited_by);

  return v_updated;
end;
$$;

comment on function app.accept_customer_portal_invite is
  'CPL-300: invited -> active only, by the invited identity itself. p_auth_user_id must equal the row''s own auth_user_id (raises insufficient_authority otherwise) -- a forged/copied auth_user_id on accept is rejected. Optimistic-concurrency record_version check (stale_version), mirroring app.decide_overtime_request''s own version-check shape. Grants the legacy app.principal_memberships marker here (Tier C review fix, moved from app.invite_customer_portal_user) -- an invited-but-not-yet-accepted identity holds no legacy WMS/inventory or portal-entry access. CPL-324 Tier C fix (integrated verification): p_expected_version=NULL no longer silently bypasses the version check -- the early guard now treats NULL as automatically stale, and the UPDATE''s own WHERE clause repeats the record_version predicate (IF NOT FOUND raises stale_version) as defense-in-depth, matching the pattern already used by app.unlink_ticket_portal_record/app.update_customer_portal_account_membership_role and every CPL-320..323 mutation.';

-- ---------------------------------------------------------------------------
-- 2/12. app.set_customer_portal_account_membership_status (CPL-300)
-- ---------------------------------------------------------------------------

create or replace function app.set_customer_portal_account_membership_status(
  p_membership_id uuid,
  p_expected_version integer,
  p_to_status text,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.customer_portal_account_memberships
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_membership app.customer_portal_account_memberships;
  v_updated app.customer_portal_account_memberships;
  v_legacy_membership_id uuid;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_to_status not in ('active', 'suspended', 'revoked') then
    raise exception 'invalid_status: % is not a status this function may set', p_to_status using errcode = 'check_violation';
  end if;

  -- Mandatory non-empty reason for suspend/revoke, mirroring app.hold_credit_
  -- profile's own mandatory-reason discipline -- checked before touching the
  -- row, same ordering that function itself uses.
  if p_to_status in ('suspended', 'revoked') and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'reason_required: a non-empty reason is required to % a customer portal membership', p_to_status using errcode = 'not_null_violation';
  end if;

  select * into v_membership from app.customer_portal_account_memberships where id = p_membership_id for update;
  if not found then
    raise exception 'customer_portal_membership_not_found: %', p_membership_id using errcode = 'no_data_found';
  end if;

  if not app.actor_is_active_customer_portal_account_admin(v_membership.tenant_id, v_membership.account_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active account_admin on account %', p_actor_auth_user_id, v_membership.account_id
      using errcode = 'insufficient_privilege';
  end if;

  -- invited -> active is exclusively app.accept_customer_portal_invite's own
  -- job (self-accept only, business rule above) -- an admin may not force it
  -- here even though the underlying transition trigger would otherwise permit
  -- invited -> active.
  if v_membership.status = 'invited' and p_to_status = 'active' then
    raise exception 'accept_required: an invited membership may only be activated by the invited identity itself, via app.accept_customer_portal_invite'
      using errcode = 'check_violation';
  end if;

  -- CPL-324 Tier C fix: p_expected_version = NULL no longer silently
  -- bypasses this guard.
  if p_expected_version is null or v_membership.record_version <> p_expected_version then
    raise exception 'stale_version: customer portal membership % expected version % but found %', p_membership_id, p_expected_version, v_membership.record_version
      using errcode = 'serialization_failure';
  end if;

  -- CPL-324 Tier C fix: repeat the version predicate as defense-in-depth.
  update app.customer_portal_account_memberships
  set status = p_to_status,
      suspended_by = case when p_to_status = 'suspended' then p_actor_label else suspended_by end,
      suspended_at = case when p_to_status = 'suspended' then now() else suspended_at end,
      suspended_reason = case when p_to_status = 'suspended' then p_reason else suspended_reason end,
      revoked_by = case when p_to_status = 'revoked' then p_actor_label else revoked_by end,
      revoked_at = case when p_to_status = 'revoked' then now() else revoked_at end,
      revoked_reason = case when p_to_status = 'revoked' then p_reason else revoked_reason end
  where id = p_membership_id and record_version = p_expected_version
  returning * into v_updated;

  if not found then
    raise exception 'stale_version: customer portal membership % was concurrently modified (expected version %)', p_membership_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.customer_portal_account_membership_history
    (membership_id, auth_user_id, tenant_id, account_id, from_status, to_status, reason, requested_by)
  values
    (v_updated.id, v_updated.auth_user_id, v_updated.tenant_id, v_updated.account_id, v_membership.status, p_to_status, p_reason, p_actor_label);

  -- Tier C security-rls review fix (Finding 2): propagate suspend/revoke/
  -- reactivate to the legacy app.principal_memberships row this migration's
  -- own accept/bootstrap flow grants -- otherwise already-shipped consumers
  -- of app.resolve_customer_owner_account_scope (ATW-023 WMS/inventory, the
  -- ticketing customer channel's app._is_ticket_requester_party) and app.
  -- actor_holds_customer_user_layer (this migration's own portal-entry
  -- guard) keep admitting a suspended/revoked member indefinitely -- a
  -- live-verified bypass both lenses independently reproduced. Mirrors app.
  -- transition_user_status' own established HRT-295 pattern of driving
  -- app.revoke_principal_membership off the matching active row, never
  -- re-derived. principal_memberships' own revoke is terminal (no
  -- suspend-in-place primitive exists there), so a later suspended -> active
  -- reactivation through this same RPC re-grants a fresh row via app.grant_
  -- principal_membership (idempotent, and a new row is exactly how that
  -- table's own re-grant-after-revoke shape already works).
  if p_to_status in ('suspended', 'revoked') then
    select id into v_legacy_membership_id
    from app.principal_memberships
    where auth_user_id = v_updated.auth_user_id
      and tenant_id = v_updated.tenant_id
      and layer = 'customer_user'
      and customer_account_ref = v_updated.account_id::text
      and status = 'active';

    if found then
      perform app.revoke_principal_membership(v_legacy_membership_id, p_reason, p_actor_label);
    end if;
  elsif p_to_status = 'active' and v_membership.status = 'suspended' then
    perform app.grant_principal_membership(v_updated.auth_user_id, 'customer_user', v_updated.tenant_id, v_updated.account_id::text, p_actor_label);
  end if;

  return v_updated;
end;
$$;

comment on function app.set_customer_portal_account_membership_status is
  'CPL-300: suspend/revoke/reactivate, caller-gated by app.actor_is_active_customer_portal_account_admin on the SAME account_id (design decision 5). Source prompt §24: "Revocation invalidates sessions, saved views, exports, signed URLs and cached summaries" -- every read RPC in this migration re-checks status=''active'' LIVE against this table on every call, never caching it, so revocation takes effect immediately by construction (design decision 7). Tier C review fix: ALSO drives the legacy app.principal_memberships row this migration''s own accept/bootstrap flow grants (revoke on suspend/revoke, re-grant on suspended -> active reactivation) so already-shipped legacy consumers (ATW-023 WMS/inventory, the ticketing customer channel, this migration''s own portal-entry guard) lose/regain access in step, not only this migration''s own resolver -- no separate session-invalidation mechanism is built beyond that, none exists anywhere in this repository. CPL-324 Tier C fix (integrated verification): p_expected_version=NULL no longer silently bypasses the version check -- the early guard now treats NULL as automatically stale, and the UPDATE''s own WHERE clause repeats the record_version predicate (IF NOT FOUND raises stale_version) as defense-in-depth.';

-- ---------------------------------------------------------------------------
-- 3/12. app.update_customer_quote_request_draft (CPL-302)
-- ---------------------------------------------------------------------------

create or replace function app.update_customer_quote_request_draft(
  p_request_id uuid,
  p_expected_version integer,
  p_cargo_description text,
  p_origin jsonb,
  p_destination jsonb,
  p_service_type text,
  p_requested_pickup_date date,
  p_requested_delivery_date date,
  p_notes text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.customer_portal_quote_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_request app.customer_portal_quote_requests;
  v_updated app.customer_portal_quote_requests;
  v_origin jsonb := coalesce(p_origin, '{}'::jsonb);
  v_destination jsonb := coalesce(p_destination, '{}'::jsonb);
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_request from app.customer_portal_quote_requests where id = p_request_id for update;
  if not found or not (v_request.account_id = any (app.resolve_customer_account_scope(p_actor_auth_user_id, v_request.tenant_id))) then
    raise exception 'record_not_found: no permitted quote request exists for %', p_request_id using errcode = 'no_data_found';
  end if;

  if v_request.status <> 'draft' then
    raise exception 'invalid_transition: quote request % is % and can no longer be edited', p_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  -- CPL-324 Tier C fix: p_expected_version = NULL no longer silently
  -- bypasses this guard.
  if p_expected_version is null or v_request.record_version <> p_expected_version then
    raise exception 'stale_version: quote request % expected version % but found %', p_request_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;

  if jsonb_typeof(v_origin) <> 'object' or jsonb_typeof(v_destination) <> 'object' then
    raise exception 'invalid_location: origin/destination must each be a JSON object' using errcode = 'check_violation';
  end if;

  if p_requested_pickup_date is not null and p_requested_delivery_date is not null and p_requested_delivery_date < p_requested_pickup_date then
    raise exception 'invalid_dates: requested_delivery_date cannot be before requested_pickup_date' using errcode = 'check_violation';
  end if;

  -- CPL-324 Tier C fix: repeat the version predicate as defense-in-depth.
  update app.customer_portal_quote_requests
  set cargo_description = p_cargo_description,
      origin = v_origin,
      destination = v_destination,
      service_type = p_service_type,
      requested_pickup_date = p_requested_pickup_date,
      requested_delivery_date = p_requested_delivery_date,
      notes = p_notes
  where id = p_request_id and record_version = p_expected_version
  returning * into v_updated;

  if not found then
    raise exception 'stale_version: quote request % was concurrently modified (expected version %)', p_request_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_customer_quote_request_draft',
    'app.customer_portal_quote_requests', v_updated.id, 'success', null, to_jsonb(v_request), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

comment on function app.update_customer_quote_request_draft is
  'CPL-302: draft-only edit of cargo/route/service/dates/notes. Any active member of the request''s own account may edit it (design decision 9), not only its original requester. Optimistic concurrency via select ... for update + explicit stale_version raise (CPL-300''s own shape). CPL-324 Tier C fix (integrated verification): p_expected_version=NULL no longer silently bypasses the version check -- the early guard now treats NULL as automatically stale, and the UPDATE''s own WHERE clause repeats the record_version predicate (IF NOT FOUND raises stale_version) as defense-in-depth.';

-- ---------------------------------------------------------------------------
-- 4/12. app.submit_customer_quote_request (CPL-302)
-- ---------------------------------------------------------------------------

create or replace function app.submit_customer_quote_request(
  p_request_id uuid,
  p_expected_version integer,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.customer_portal_quote_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_request app.customer_portal_quote_requests;
  v_updated app.customer_portal_quote_requests;
  v_conflict_id uuid;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: a non-empty idempotency key is required to submit a quote request' using errcode = 'not_null_violation';
  end if;

  select * into v_request from app.customer_portal_quote_requests where id = p_request_id for update;
  if not found or not (v_request.account_id = any (app.resolve_customer_account_scope(p_actor_auth_user_id, v_request.tenant_id))) then
    raise exception 'record_not_found: no permitted quote request exists for %', p_request_id using errcode = 'no_data_found';
  end if;

  -- Idempotent retry: a repeated submit call carrying the SAME idempotency key
  -- this exact row already recorded returns it unchanged, regardless of the
  -- caller's own (now-stale) p_expected_version -- protects a genuine
  -- double-click/network-retry from a spurious stale_version/invalid_transition
  -- error (design decision 3).
  if v_request.status = 'submitted' and v_request.submitted_idempotency_key = p_idempotency_key then
    return v_request;
  end if;

  select id into v_conflict_id
  from app.customer_portal_quote_requests
  where tenant_id = v_request.tenant_id and account_id = v_request.account_id
    and submitted_idempotency_key = p_idempotency_key and id <> p_request_id;
  if found then
    raise exception 'idempotency_conflict: idempotency key already used by a different quote request % on this account', v_conflict_id
      using errcode = 'unique_violation';
  end if;

  if v_request.status <> 'draft' then
    raise exception 'invalid_transition: quote request % is % and cannot be submitted', p_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  -- CPL-324 Tier C fix: p_expected_version = NULL no longer silently
  -- bypasses this guard.
  if p_expected_version is null or v_request.record_version <> p_expected_version then
    raise exception 'stale_version: quote request % expected version % but found %', p_request_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;

  -- Tier C fix (spec-compliance): source prompt §23 ("Block ... unscanned
  -- file") and §24 ("Files remain private, scanned and scope-bound before
  -- any download or handoff") -- submission IS this capability's own
  -- "internal Commercial handoff" moment (source prompt §20). Checked only
  -- for a genuine draft -> submitted transition (after the status/version
  -- gates above), never ahead of a caller's own invalid_transition/
  -- stale_version error. Any attachment still pending/infected/error scan
  -- status blocks submission; a clean scan, or no attachment at all, does
  -- not.
  if exists (
    select 1 from app.files
    where record_type = 'customer_portal_quote_request'
      and record_id = p_request_id
      and tenant_id = v_request.tenant_id
      and lifecycle_status = 'active'
      and malware_scan_status <> 'clean'
  ) then
    raise exception 'unscanned_attachment: quote request % has an attachment that has not cleared malware scanning', p_request_id
      using errcode = 'check_violation';
  end if;

  -- CPL-324 Tier C fix: repeat the version predicate as defense-in-depth.
  update app.customer_portal_quote_requests
  set status = 'submitted', submitted_at = now(), submitted_idempotency_key = p_idempotency_key
  where id = p_request_id and record_version = p_expected_version
  returning * into v_updated;

  if not found then
    raise exception 'stale_version: quote request % was concurrently modified (expected version %)', p_request_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_customer_quote_request',
    'app.customer_portal_quote_requests', v_updated.id, 'success', null, null, to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

comment on function app.submit_customer_quote_request is
  'CPL-302: draft -> submitted. p_idempotency_key is mandatory and unique per (tenant_id, account_id) -- a repeated call with the SAME key on the SAME already-submitted row is a no-op idempotent return; the SAME key against a DIFFERENT row on the same account is a real idempotency_conflict, never a silent overwrite. This is not a rated quote or price commitment (source prompt §24) -- it only hands the request to Commercial''s own intake queue for staff review. Tier C fix (spec-compliance): submission now blocks (unscanned_attachment) if any active attachment on this request has not cleared malware scanning. CPL-324 Tier C fix (integrated verification): p_expected_version=NULL no longer silently bypasses the version check -- the early guard now treats NULL as automatically stale, and the UPDATE''s own WHERE clause repeats the record_version predicate (IF NOT FOUND raises stale_version) as defense-in-depth.';

-- ---------------------------------------------------------------------------
-- 5/12. app.cancel_customer_quote_request (CPL-302)
-- ---------------------------------------------------------------------------

create or replace function app.cancel_customer_quote_request(
  p_request_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.customer_portal_quote_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_request app.customer_portal_quote_requests;
  v_updated app.customer_portal_quote_requests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to cancel a quote request' using errcode = 'not_null_violation';
  end if;

  select * into v_request from app.customer_portal_quote_requests where id = p_request_id for update;
  if not found or not (v_request.account_id = any (app.resolve_customer_account_scope(p_actor_auth_user_id, v_request.tenant_id))) then
    raise exception 'record_not_found: no permitted quote request exists for %', p_request_id using errcode = 'no_data_found';
  end if;

  if v_request.status not in ('draft', 'submitted') then
    raise exception 'invalid_transition: quote request % is % and can no longer be cancelled', p_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  -- CPL-324 Tier C fix: p_expected_version = NULL no longer silently
  -- bypasses this guard.
  if p_expected_version is null or v_request.record_version <> p_expected_version then
    raise exception 'stale_version: quote request % expected version % but found %', p_request_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;

  -- CPL-324 Tier C fix: repeat the version predicate as defense-in-depth.
  update app.customer_portal_quote_requests
  set status = 'cancelled', cancelled_at = now(), cancelled_reason = p_reason
  where id = p_request_id and record_version = p_expected_version
  returning * into v_updated;

  if not found then
    raise exception 'stale_version: quote request % was concurrently modified (expected version %)', p_request_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_customer_quote_request',
    'app.customer_portal_quote_requests', v_updated.id, 'success', null, null, to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

comment on function app.cancel_customer_quote_request is
  'CPL-302: draft or submitted -> cancelled, mandatory non-empty reason. Cancellation before internal (staff) acceptance is always available to any account-scoped member -- once app.link_customer_quote_request_to_quotation has converted a request, it is terminal and this function correctly refuses it (invalid_transition). CPL-324 Tier C fix (integrated verification): p_expected_version=NULL no longer silently bypasses the version check -- the early guard now treats NULL as automatically stale, and the UPDATE''s own WHERE clause repeats the record_version predicate (IF NOT FOUND raises stale_version) as defense-in-depth.';

-- ---------------------------------------------------------------------------
-- 6/12. app.update_customer_booking_request_draft (CPL-303)
-- ---------------------------------------------------------------------------

create or replace function app.update_customer_booking_request_draft(
  p_booking_request_id uuid,
  p_expected_version integer,
  p_cargo_description text,
  p_pickup jsonb,
  p_delivery jsonb,
  p_requested_pickup_at timestamptz,
  p_requested_delivery_at timestamptz,
  p_special_instructions text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.customer_portal_booking_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_booking app.customer_portal_booking_requests;
  v_updated app.customer_portal_booking_requests;
  v_pickup jsonb := coalesce(p_pickup, '{}'::jsonb);
  v_delivery jsonb := coalesce(p_delivery, '{}'::jsonb);
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_booking from app.customer_portal_booking_requests where id = p_booking_request_id for update;
  if not found or not (v_booking.account_id = any (app.resolve_customer_account_scope(p_actor_auth_user_id, v_booking.tenant_id))) then
    raise exception 'record_not_found: no permitted booking request exists for %', p_booking_request_id using errcode = 'no_data_found';
  end if;

  if v_booking.status <> 'draft' then
    raise exception 'invalid_transition: booking request % is % and can no longer be edited', p_booking_request_id, v_booking.status
      using errcode = 'check_violation';
  end if;

  -- CPL-324 Tier C fix: p_expected_version = NULL no longer silently
  -- bypasses this guard.
  if p_expected_version is null or v_booking.record_version <> p_expected_version then
    raise exception 'stale_version: booking request % expected version % but found %', p_booking_request_id, p_expected_version, v_booking.record_version
      using errcode = 'serialization_failure';
  end if;

  if jsonb_typeof(v_pickup) <> 'object' or jsonb_typeof(v_delivery) <> 'object' then
    raise exception 'invalid_location: pickup/delivery must each be a JSON object' using errcode = 'check_violation';
  end if;

  if p_requested_pickup_at is not null and p_requested_delivery_at is not null and p_requested_delivery_at < p_requested_pickup_at then
    raise exception 'invalid_dates: requested_delivery_at cannot be before requested_pickup_at' using errcode = 'check_violation';
  end if;

  -- CPL-324 Tier C fix: repeat the version predicate as defense-in-depth.
  update app.customer_portal_booking_requests
  set cargo_description = p_cargo_description,
      pickup = v_pickup,
      delivery = v_delivery,
      requested_pickup_at = p_requested_pickup_at,
      requested_delivery_at = p_requested_delivery_at,
      special_instructions = p_special_instructions
  where id = p_booking_request_id and record_version = p_expected_version
  returning * into v_updated;

  if not found then
    raise exception 'stale_version: booking request % was concurrently modified (expected version %)', p_booking_request_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_customer_booking_request_draft',
    'app.customer_portal_booking_requests', v_updated.id, 'success', null, to_jsonb(v_booking), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

comment on function app.update_customer_booking_request_draft is
  'CPL-303: draft-only edit of cargo/pickup/delivery/schedule/instructions. Any active member of the request''s own account may edit it (mirrors CPL-302 design decision 9), not only its original requester. linked_quote_request_id is immutable after creation. Optimistic concurrency via select ... for update + explicit stale_version raise. CPL-324 Tier C fix (integrated verification): p_expected_version=NULL no longer silently bypasses the version check -- the early guard now treats NULL as automatically stale, and the UPDATE''s own WHERE clause repeats the record_version predicate (IF NOT FOUND raises stale_version) as defense-in-depth.';

-- ---------------------------------------------------------------------------
-- 7/12. app.submit_customer_booking_request (CPL-303)
-- ---------------------------------------------------------------------------

create or replace function app.submit_customer_booking_request(
  p_booking_request_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.customer_portal_booking_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_booking app.customer_portal_booking_requests;
  v_updated app.customer_portal_booking_requests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_booking from app.customer_portal_booking_requests where id = p_booking_request_id for update;
  if not found or not (v_booking.account_id = any (app.resolve_customer_account_scope(p_actor_auth_user_id, v_booking.tenant_id))) then
    raise exception 'record_not_found: no permitted booking request exists for %', p_booking_request_id using errcode = 'no_data_found';
  end if;

  -- Idempotent no-op (design decision 4): a genuine retry of an
  -- already-submitted row is a safe, unchanged return -- draft -> submitted
  -- is a pure status flip with no other side effect, so no separate
  -- submit-stage idempotency key is needed the way CPL-302's own submit
  -- required one.
  if v_booking.status = 'submitted' then
    return v_booking;
  end if;

  if v_booking.status <> 'draft' then
    raise exception 'invalid_transition: booking request % is % and cannot be submitted', p_booking_request_id, v_booking.status
      using errcode = 'check_violation';
  end if;

  -- CPL-324 Tier C fix: p_expected_version = NULL no longer silently
  -- bypasses this guard.
  if p_expected_version is null or v_booking.record_version <> p_expected_version then
    raise exception 'stale_version: booking request % expected version % but found %', p_booking_request_id, p_expected_version, v_booking.record_version
      using errcode = 'serialization_failure';
  end if;

  -- CPL-324 Tier C fix: repeat the version predicate as defense-in-depth.
  update app.customer_portal_booking_requests
  set status = 'submitted', submitted_at = now()
  where id = p_booking_request_id and record_version = p_expected_version
  returning * into v_updated;

  if not found then
    raise exception 'stale_version: booking request % was concurrently modified (expected version %)', p_booking_request_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.customer_portal_booking_request_history (booking_request_id, tenant_id, account_id, from_status, to_status, reason, requested_by)
  values (v_updated.id, v_updated.tenant_id, v_updated.account_id, 'draft', 'submitted', 'booking request submitted', p_actor_label);

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_customer_booking_request',
    'app.customer_portal_booking_requests', v_updated.id, 'success', null, null, to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

comment on function app.submit_customer_booking_request is
  'CPL-303: draft -> submitted, hands the request to Operations/Commercial''s own intake for staff review and eventual canonical handoff (app.prepare_job_order_handoff and downstream) -- never itself a canonical job/shipment order. Idempotent no-op if already submitted (design decision 4). CPL-324 Tier C fix (integrated verification): p_expected_version=NULL no longer silently bypasses the version check -- the early guard now treats NULL as automatically stale, and the UPDATE''s own WHERE clause repeats the record_version predicate (IF NOT FOUND raises stale_version) as defense-in-depth.';

-- ---------------------------------------------------------------------------
-- 8/12. app.request_customer_booking_reschedule (CPL-303)
-- ---------------------------------------------------------------------------

create or replace function app.request_customer_booking_reschedule(
  p_booking_request_id uuid,
  p_expected_version integer,
  p_requested_pickup_at timestamptz,
  p_requested_delivery_at timestamptz,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.customer_portal_booking_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_booking app.customer_portal_booking_requests;
  v_updated app.customer_portal_booking_requests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to request a reschedule' using errcode = 'not_null_violation';
  end if;

  if p_requested_pickup_at is null and p_requested_delivery_at is null then
    raise exception 'reschedule_date_required: at least one new requested pickup or delivery date/time is required' using errcode = 'not_null_violation';
  end if;

  if p_requested_pickup_at is not null and p_requested_delivery_at is not null and p_requested_delivery_at < p_requested_pickup_at then
    raise exception 'invalid_dates: requested_delivery_at cannot be before requested_pickup_at' using errcode = 'check_violation';
  end if;

  select * into v_booking from app.customer_portal_booking_requests where id = p_booking_request_id for update;
  if not found or not (v_booking.account_id = any (app.resolve_customer_account_scope(p_actor_auth_user_id, v_booking.tenant_id))) then
    raise exception 'record_not_found: no permitted booking request exists for %', p_booking_request_id using errcode = 'no_data_found';
  end if;

  if v_booking.status not in ('submitted', 'converted') then
    raise exception 'invalid_transition: booking request % is % and cannot be rescheduled', p_booking_request_id, v_booking.status
      using errcode = 'check_violation';
  end if;

  -- CPL-324 Tier C fix: p_expected_version = NULL no longer silently
  -- bypasses this guard.
  if p_expected_version is null or v_booking.record_version <> p_expected_version then
    raise exception 'stale_version: booking request % expected version % but found %', p_booking_request_id, p_expected_version, v_booking.record_version
      using errcode = 'serialization_failure';
  end if;

  -- CPL-324 Tier C fix: repeat the version predicate as defense-in-depth.
  update app.customer_portal_booking_requests
  set status = 'reschedule_requested',
      reschedule_requested_pickup_at = p_requested_pickup_at,
      reschedule_requested_delivery_at = p_requested_delivery_at,
      reschedule_reason = p_reason,
      reschedule_requested_at = now()
  where id = p_booking_request_id and record_version = p_expected_version
  returning * into v_updated;

  if not found then
    raise exception 'stale_version: booking request % was concurrently modified (expected version %)', p_booking_request_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.customer_portal_booking_request_history (booking_request_id, tenant_id, account_id, from_status, to_status, reason, requested_by)
  values (v_updated.id, v_updated.tenant_id, v_updated.account_id, v_booking.status, 'reschedule_requested', p_reason, p_actor_label);

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'request_customer_booking_reschedule',
    'app.customer_portal_booking_requests', v_updated.id, 'success', p_reason, to_jsonb(v_booking), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

comment on function app.request_customer_booking_reschedule is
  'CPL-303: submitted or converted -> reschedule_requested. Mandatory non-empty reason and at least one new proposed pickup/delivery date/time (design decision 6). This is a REQUEST only -- the real requested_pickup_at/requested_delivery_at columns and any already-linked job/shipment order are never mutated here. Terminal within this checkpoint''s own RPC surface (design decision 10). CPL-324 Tier C fix (integrated verification): p_expected_version=NULL no longer silently bypasses the version check -- the early guard now treats NULL as automatically stale, and the UPDATE''s own WHERE clause repeats the record_version predicate (IF NOT FOUND raises stale_version) as defense-in-depth.';

-- ---------------------------------------------------------------------------
-- 9/12. app.request_customer_booking_cancellation (CPL-303)
-- ---------------------------------------------------------------------------

create or replace function app.request_customer_booking_cancellation(
  p_booking_request_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.customer_portal_booking_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_booking app.customer_portal_booking_requests;
  v_updated app.customer_portal_booking_requests;
  v_target_status text;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to cancel a booking request' using errcode = 'not_null_violation';
  end if;

  select * into v_booking from app.customer_portal_booking_requests where id = p_booking_request_id for update;
  if not found or not (v_booking.account_id = any (app.resolve_customer_account_scope(p_actor_auth_user_id, v_booking.tenant_id))) then
    raise exception 'record_not_found: no permitted booking request exists for %', p_booking_request_id using errcode = 'no_data_found';
  end if;

  -- Design decision 5: draft/submitted (no operational truth committed yet)
  -- cancel straight to `cancelled`; converted (real job/shipment order rows
  -- already exist) instead becomes `cancel_requested` for staff review.
  if v_booking.status in ('draft', 'submitted') then
    v_target_status := 'cancelled';
  elsif v_booking.status = 'converted' then
    v_target_status := 'cancel_requested';
  else
    raise exception 'invalid_transition: booking request % is % and can no longer be cancelled', p_booking_request_id, v_booking.status
      using errcode = 'check_violation';
  end if;

  -- CPL-324 Tier C fix: p_expected_version = NULL no longer silently
  -- bypasses this guard.
  if p_expected_version is null or v_booking.record_version <> p_expected_version then
    raise exception 'stale_version: booking request % expected version % but found %', p_booking_request_id, p_expected_version, v_booking.record_version
      using errcode = 'serialization_failure';
  end if;

  -- CPL-324 Tier C fix: repeat the version predicate as defense-in-depth.
  update app.customer_portal_booking_requests
  set status = v_target_status,
      cancelled_reason = p_reason,
      cancelled_at = case when v_target_status = 'cancelled' then now() else cancelled_at end
  where id = p_booking_request_id and record_version = p_expected_version
  returning * into v_updated;

  if not found then
    raise exception 'stale_version: booking request % was concurrently modified (expected version %)', p_booking_request_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.customer_portal_booking_request_history (booking_request_id, tenant_id, account_id, from_status, to_status, reason, requested_by)
  values (v_updated.id, v_updated.tenant_id, v_updated.account_id, v_booking.status, v_target_status, p_reason, p_actor_label);

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'request_customer_booking_cancellation',
    'app.customer_portal_booking_requests', v_updated.id, 'success', p_reason, to_jsonb(v_booking), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

comment on function app.request_customer_booking_cancellation is
  'CPL-303: mandatory non-empty reason (reused for both the cancel_requested and the terminal cancelled outcome, design decision 6). draft/submitted cancel directly to cancelled; converted becomes cancel_requested (design decision 5) -- terminal within this checkpoint''s own RPC surface (design decision 10). CPL-324 Tier C fix (integrated verification): p_expected_version=NULL no longer silently bypasses the version check -- the early guard now treats NULL as automatically stale, and the UPDATE''s own WHERE clause repeats the record_version predicate (IF NOT FOUND raises stale_version) as defense-in-depth.';

-- ---------------------------------------------------------------------------
-- 10/12. app.respond_to_customer_shipment_order_change_request (CPL-304)
-- ---------------------------------------------------------------------------

create or replace function app.respond_to_customer_shipment_order_change_request(
  p_change_request_id uuid,
  p_expected_version integer,
  p_to_status text,
  p_staff_response text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.customer_portal_shipment_change_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_request app.customer_portal_shipment_change_requests;
  v_updated app.customer_portal_shipment_change_requests;
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_to_status not in ('acknowledged', 'resolved', 'rejected') then
    raise exception 'invalid_status: % is not a status this function may set', p_to_status using errcode = 'check_violation';
  end if;

  if p_staff_response is null or length(trim(p_staff_response)) = 0 then
    raise exception 'staff_response_required: a non-empty staff response is required' using errcode = 'not_null_violation';
  end if;

  select * into v_request from app.customer_portal_shipment_change_requests where id = p_change_request_id for update;
  -- Tier C fix (C-05 discipline): fold a tenant-standing check into the SAME
  -- not-found branch, BEFORE the specific-permission check. "Standing" here
  -- is deliberately wider than staff-only has_active_tenant_membership
  -- alone: this RPC is reachable by BOTH a staff caller AND a genuine
  -- customer_user-layer caller with real portal scope in this tenant
  -- (resolve_customer_account_scope) -- that identity's own app.
  -- tenant_user_identities row is deliberately NEVER 'active' (CPL-302
  -- design decision 4(b)), so has_active_tenant_membership alone would
  -- wrongly hide insufficient_authority from a customer who is genuinely a
  -- member of this tenant. A caller satisfying EITHER predicate still
  -- reaches the informative insufficient_authority branch below; a caller
  -- satisfying NEITHER (e.g. a customer_user of a completely different
  -- tenant) gets the identical not-found error a missing row would produce.
  if not found or not (
    app.has_active_tenant_membership(v_request.tenant_id, p_actor_auth_user_id)
    or array_length(app.resolve_customer_account_scope(p_actor_auth_user_id, v_request.tenant_id), 1) is not null
  ) then
    raise exception 'change_request_not_found: %', p_change_request_id using errcode = 'no_data_found';
  end if;

  -- Reuses the already-existing OPS:Edit action (the same module/action
  -- app.confirm_shipment_order/app.cancel_shipment_order/CPL-303's own
  -- link_customer_booking_request_to_operational_records already require);
  -- no new module/action added.
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent no-op (design decision 3d): a genuine retry landing on the
  -- SAME target status AND the same response text returns the row
  -- unchanged, mirroring app.submit_customer_booking_request''s own
  -- status-check-before-version-check shape (CPL-303).
  if v_request.status = p_to_status and v_request.staff_response = p_staff_response then
    return v_request;
  end if;

  if not (
    (v_request.status = 'submitted')
    or (v_request.status = 'acknowledged' and p_to_status in ('resolved', 'rejected'))
  ) then
    raise exception 'invalid_transition: change request % is % and cannot move to %', p_change_request_id, v_request.status, p_to_status
      using errcode = 'check_violation';
  end if;

  -- CPL-324 Tier C fix: p_expected_version = NULL no longer silently
  -- bypasses this guard.
  if p_expected_version is null or v_request.record_version <> p_expected_version then
    raise exception 'stale_version: change request % expected version % but found %', p_change_request_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;

  -- CPL-324 Tier C fix: repeat the version predicate as defense-in-depth.
  update app.customer_portal_shipment_change_requests
  set status = p_to_status, staff_response = p_staff_response, staff_responded_by = p_actor_label, staff_responded_at = now()
  where id = p_change_request_id and record_version = p_expected_version
  returning * into v_updated;

  if not found then
    raise exception 'stale_version: change request % was concurrently modified (expected version %)', p_change_request_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'respond_to_customer_shipment_order_change_request',
    'app.customer_portal_shipment_change_requests', v_updated.id, 'success', p_staff_response, to_jsonb(v_request), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

comment on function app.respond_to_customer_shipment_order_change_request is
  'CPL-304: staff-only (OPS:Edit) response/resolution -- submitted -> acknowledged|resolved|rejected, or acknowledged -> resolved|rejected (resolved/rejected are terminal). Mandatory non-empty staff_response. Optimistic concurrency via select ... for update + explicit p_expected_version check (design decision 3d). Idempotent only for a retry landing on the exact SAME target status and response text. Tier C fix (C-05 discipline): the not-found branch also requires has_active_tenant_membership on the row''s own tenant, BEFORE the OPS:Edit check runs. CPL-324 Tier C fix (integrated verification): p_expected_version=NULL no longer silently bypasses the version check -- the early guard now treats NULL as automatically stale, and the UPDATE''s own WHERE clause repeats the record_version predicate (IF NOT FOUND raises stale_version) as defense-in-depth.';

-- ---------------------------------------------------------------------------
-- 11/12. app.withdraw_customer_profile_change_request (CPL-314)
-- ---------------------------------------------------------------------------

create or replace function app.withdraw_customer_profile_change_request(
  p_request_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.customer_portal_profile_change_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_request app.customer_portal_profile_change_requests;
  v_updated app.customer_portal_profile_change_requests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_request from app.customer_portal_profile_change_requests where id = p_request_id for update;
  if not found or not (v_request.account_id = any (app.resolve_customer_account_scope(p_actor_auth_user_id, v_request.tenant_id))) then
    raise exception 'record_not_found: no permitted profile change request exists for %', p_request_id using errcode = 'no_data_found';
  end if;

  -- CPL-324 Tier C fix: p_expected_version = NULL no longer silently
  -- bypasses this guard.
  if p_expected_version is null or v_request.record_version <> p_expected_version then
    raise exception 'stale_version: profile change request % expected version % but found %', p_request_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_request.status <> 'pending' then
    raise exception 'invalid_transition: profile change request % is % and can no longer be withdrawn', p_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  -- CPL-324 Tier C fix: repeat the version predicate as defense-in-depth.
  update app.customer_portal_profile_change_requests
  set status = 'withdrawn'
  where id = p_request_id and record_version = p_expected_version
  returning * into v_updated;

  if not found then
    raise exception 'stale_version: profile change request % was concurrently modified (expected version %)', p_request_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'withdraw_customer_profile_change_request',
    'app.customer_portal_profile_change_requests', v_updated.id, 'success', null, null, to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

comment on function app.withdraw_customer_profile_change_request is
  'CPL-314: pending -> withdrawn only. Any active member of the request''s own account may withdraw it (design decision 12), not only its original requester. Optimistic concurrency (stale_version) checked before the status check. CPL-324 Tier C fix (integrated verification): p_expected_version=NULL no longer silently bypasses the version check -- the early guard now treats NULL as automatically stale, and the UPDATE''s own WHERE clause repeats the record_version predicate (IF NOT FOUND raises stale_version) as defense-in-depth.';

-- ---------------------------------------------------------------------------
-- 12/12. app.decide_customer_profile_change_request (CPL-314)
-- ---------------------------------------------------------------------------

create or replace function app.decide_customer_profile_change_request(
  p_request_id uuid,
  p_expected_version integer,
  p_decision text,
  p_review_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.customer_portal_profile_change_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_request app.customer_portal_profile_change_requests;
  v_decision app.rbac_decision;
  v_account app.accounts;
  v_updated app.customer_portal_profile_change_requests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_request from app.customer_portal_profile_change_requests where id = p_request_id for update;
  -- C-05 fold (design decision 9): a caller with zero standing in this row's
  -- own tenant (neither staff, nor a customer_user with real scope over the
  -- row's own account) gets the identical not-found a missing row would
  -- produce. A genuine customer who already knows this row exists instead
  -- reaches the informative insufficient_authority branch below -- mirrors
  -- app.link_customer_quote_request_to_quotation (CPL-302) exactly.
  if not found or not (
    app.has_active_tenant_membership(v_request.tenant_id, p_actor_auth_user_id)
    or (v_request.account_id = any (app.resolve_customer_account_scope(p_actor_auth_user_id, v_request.tenant_id)))
  ) then
    raise exception 'profile_change_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'COM', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Defense-in-depth, structurally unreachable today (design decision 10):
  -- requested_by_actor_auth_user_id is only ever set by app.submit_customer_
  -- profile_change_request, which has no staff caller. Retained and tested
  -- anyway, mirroring app.decide_payroll_reimbursement_request's own C-18
  -- guard (HRT-282).
  if v_request.requested_by_actor_auth_user_id = p_actor_auth_user_id then
    raise exception 'self_approval_not_permitted: an actor may not decide their own profile change request' using errcode = 'insufficient_privilege';
  end if;

  if p_decision not in ('approve', 'reject') then
    raise exception 'invalid_decision: % must be approve or reject', p_decision using errcode = 'check_violation';
  end if;

  if p_review_reason is null or length(trim(p_review_reason)) = 0 then
    raise exception 'reason_required: a reason is required to decide a profile change request' using errcode = 'not_null_violation';
  end if;

  -- CPL-324 Tier C fix: p_expected_version = NULL no longer silently
  -- bypasses this guard.
  if p_expected_version is null or v_request.record_version <> p_expected_version then
    raise exception 'stale_version: profile change request % expected version % but found %', p_request_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_request.status <> 'pending' then
    raise exception 'invalid_transition: profile change request % is % and cannot be decided', p_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  if p_decision = 'approve' then
    -- Applies the already-reviewed change to the real canonical row, in the
    -- SAME transaction as the request's own approval (design decision 1).
    -- app.accounts' own pre-existing accounts_touch_row trigger bumps
    -- record_version/updated_at -- the "effective version" (design decision
    -- 6), no separate versioning column is invented here.
    select * into v_account from app.accounts where id = v_request.account_id for update;
    if v_request.field_name = 'trade_name' then
      update app.accounts set trade_name = (v_request.proposed_value #>> '{}') where id = v_account.id;
    elsif v_request.field_name = 'billing_address' then
      update app.accounts set billing_address = v_request.proposed_value where id = v_account.id;
    end if;
  end if;

  -- CPL-324 Tier C fix: repeat the version predicate as defense-in-depth.
  -- (The app.accounts write above, if taken, rolls back together with this
  -- UPDATE's own failure -- same transaction, no partial effect possible.)
  update app.customer_portal_profile_change_requests
  set status = case p_decision when 'approve' then 'approved' else 'rejected' end,
      reviewed_by = p_actor_label, reviewed_at = now(), review_reason = p_review_reason
  where id = p_request_id and record_version = p_expected_version
  returning * into v_updated;

  if not found then
    raise exception 'stale_version: profile change request % was concurrently modified (expected version %)', p_request_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  -- p_review_reason is never routed into the audit before/after jsonb
  -- unredacted (design decision 13, HRT-282's own established fix).
  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_customer_profile_change_request',
    'app.customer_portal_profile_change_requests', v_updated.id, 'success', null,
    jsonb_build_object('status', v_request.status, 'field_name', v_request.field_name),
    jsonb_build_object('status', v_updated.status, 'field_name', v_updated.field_name)
  );

  return v_updated;
end;
$$;

comment on function app.decide_customer_profile_change_request is
  'CPL-314: staff-only (COM:Approve) -- pending -> approved | rejected. review_reason is mandatory for BOTH outcomes (design decision 13), never persisted into the audit before/after snapshot unredacted. On approve, applies the change to the real app.accounts row (trade_name or billing_address) in the SAME transaction. On reject, app.accounts is left completely untouched. Self-approval is structurally blocked (design decision 10). CPL-324 Tier C fix (integrated verification): p_expected_version=NULL no longer silently bypasses the version check -- the early guard now treats NULL as automatically stale, and the UPDATE''s own WHERE clause repeats the record_version predicate (IF NOT FOUND raises stale_version) as defense-in-depth -- if the version check now fails after an approve-branch app.accounts write, the WHOLE transaction (including that write) rolls back, so no partial effect is possible.';
