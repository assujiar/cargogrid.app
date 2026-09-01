-- ISS-2026-123 item 1 (docs/runtime/KNOWN_ISSUES.md) -- a dedicated, separately-authorized
-- legal-identity change-request path for the two fields CPL-314's own
-- app.customer_portal_profile_change_requests deliberately excludes: legal_name/tax_id
-- (supabase/migrations/20260801150000_create_customer_portal_customer_profile.sql, design
-- decision 2: "legal identity/KYC fields... has compliance implications outside this prompt's
-- bounded mandate"). Read that migration in full before this one -- every structural
-- convention below (status lifecycle, review fields, idempotency-key unique index, touch/
-- transition triggers, C-05 anti-enumeration fold, self-approval defense-in-depth, RLS/grant
-- shape) is its own literal template, reproduced as genuinely SEPARATE objects, never a
-- widening of that table's own cppcr_field_name_check (which stays exactly {trade_name,
-- billing_address} -- scripts/db-tests/customer-profile-visibility.sql's own raw-INSERT
-- assertion that legal_name/tax_id are rejected there is a real security boundary, untouched).
--
-- ===========================================================================
-- Design decisions
-- ===========================================================================
--
-- 1. **A separate table, not a widened CHECK on the existing low-authority one.** legal_name/
--    tax_id feed app.accounts.normalized_legal_name/normalized_tax_id/duplicate_fingerprint
--    (COM-155, 20260724290000_create_commercial_customer_account_conversion.sql) -- CANONICAL
--    CUSTOMER-IDENTITY DEDUP. A collision or a bad edit here is a data-integrity incident, not
--    a cosmetic profile field; it earns its own table, its own decide RPC, and (design decision
--    3) a real step-up-MFA gate the trade_name/billing_address path was never asked to carry.
-- 2. **Structural mirror of app.customer_portal_profile_change_requests, verified live before
--    writing a single line here** (not assumed from reading that migration's own file, which
--    could have been superseded since): status lifecycle pending -> approved | rejected |
--    withdrawn (all terminal), the same enforce-transition + touch-row trigger pair, the same
--    (tenant_id, idempotency_key) partial unique index, the same review-fields/review-reason
--    CHECK pair, the same scope-check-before-idempotent-short-circuit ordering, the same C-05
--    not-found fold in decide (has_active_tenant_membership OR resolved account scope) BEFORE
--    the COM:Approve check, the same unconditional (approve AND reject) review_reason
--    requirement, the same self-approval defense-in-depth guard, the same "authenticated holds
--    zero direct table grant" RLS posture.
-- 3. **The step-up-MFA gate this checkpoint adds, and the stale premise it corrects.** This
--    entry's own prior text claimed "no configured authorization/approval workflow exists
--    anywhere in this repository" for a change this sensitive. Re-verified live, that premise
--    is now FALSE: 20260807100000_create_intelligence_enterprise_mfa_session_controls.sql
--    (IAE-027) shipped a real, applied step-up-MFA mechanism at the app.evaluate_permission
--    chokepoint, hardened by 20260830110000 (ISS-2026-236). app.decide_customer_legal_identity_
--    change_request calls app.assert_current_step_up_authorization(tenant, actor, 'COM',
--    'Approve') immediately after the ordinary COM:Approve gate -- a strict no-op for any
--    tenant that has not opted into MFA (app.mfa_tenant_policies has no row, or
--    tenant_wide_required is false: app.is_high_risk_action returns false for the 'COM'/
--    'Approve' tuple unless a tenant's OWN additional_high_risk_actions list names it, and
--    assert_current_step_up_authorization itself no-ops whenever is_high_risk_action is false)
--    and a real, enforced control for a tenant that configures it via the already-shipped
--    app.set_mfa_tenant_policy. This migration never widens app.is_high_risk_action's own
--    hardcoded platform-default tuple list -- that is a global classification change with its
--    own blast radius on every existing fixture; a tenant that wants this specific decision
--    gated adds ('COM','Approve') to its own additional_high_risk_actions, additively, per
--    tenant, exactly the mechanism IAE-027 built for this.
-- 4. **app.accounts carries NO computed-fields trigger for legal_name/tax_id** -- confirmed
--    live (`select tgname from pg_trigger where tgrelid = 'app.accounts'::regclass and not
--    tgisinternal` returns only accounts_touch_row, which bumps updated_at/record_version and
--    nothing else) before writing the approve branch below, not assumed from the COM-155
--    migration's own file. The approve branch therefore recomputes normalized_legal_name/
--    normalized_tax_id/duplicate_fingerprint itself, reusing app.normalize_prospect_identifier/
--    app.compute_prospect_duplicate_fingerprint -- the SAME two functions app.
--    convert_quotation_to_account (COM-155) already calls for this exact purpose -- never
--    hand-duplicated arithmetic. Written as an explicit if/elsif/else with a real `else` that
--    raises unhandled_field_name: a field_name this branch does not recognize must fail loudly,
--    never silently mark the request approved while leaving app.accounts unchanged.
-- 5. **accounts_tenant_fingerprint_active_unique (tenant_id, duplicate_fingerprint) WHERE
--    status = 'active'** is a real, live constraint an approved rename can collide with (two
--    active accounts in the same tenant converging on the same normalized identity). The
--    approve branch's own UPDATE is wrapped in `exception when unique_violation` and re-raises
--    a clearly-named identity_fingerprint_conflict error -- never silently swallowed, never a
--    silent overwrite. Because this re-raise happens before this function's own request-status
--    UPDATE runs, the entire decide call aborts atomically: the request row is provably left
--    `pending`, and BOTH accounts are provably left untouched (proven live in this migration's
--    own db-test, not merely asserted from reading the code).
-- 6. Every actor-taking function calls app.assert_actor_is_session_identity as its own literal
--    first statement. Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries
--    its own explicit `revoke execute on all functions in schema app from public` before its
--    final grants. public.* wrappers (RGL-394 Option 2) ship in this same migration, mirroring
--    every migration since 20260826000000 -- app is not exposed to PostgREST.

-- ===========================================================================
-- 1. app.customer_portal_legal_identity_change_requests
-- ===========================================================================

create table app.customer_portal_legal_identity_change_requests (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  account_id uuid not null references app.accounts (id),
  requested_by_actor_auth_user_id uuid not null references auth.users (id),
  field_name text not null,
  proposed_value jsonb not null,
  status text not null default 'pending',
  reviewed_by text,
  reviewed_at timestamptz,
  review_reason text,
  idempotency_key text,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint cplicr_field_name_check check (field_name in ('legal_name', 'tax_id')),
  constraint cplicr_proposed_value_shape_check check (
    jsonb_typeof(proposed_value) = 'string' and length(trim(coalesce(proposed_value #>> '{}', ''))) > 0
  ),
  constraint cplicr_status_check check (status in ('pending', 'approved', 'rejected', 'withdrawn')),
  constraint cplicr_review_fields_check check (
    (status in ('approved', 'rejected')) = (reviewed_by is not null and reviewed_at is not null)
  ),
  constraint cplicr_review_reason_check check (
    (status in ('approved', 'rejected') and review_reason is not null and length(trim(review_reason)) > 0)
    or (status not in ('approved', 'rejected'))
  )
);

comment on table app.customer_portal_legal_identity_change_requests is
  'ISS-2026-123 item 1: the portal-owned legal-identity (legal_name/tax_id) change REQUEST -- never a direct write into app.accounts (COM-155) from a customer-initiated RPC, structurally mirroring app.customer_portal_profile_change_requests (CPL-314) as a genuinely SEPARATE table. field_name is CHECK-constrained to exactly {legal_name, tax_id} -- the exact two fields CPL-314''s own table deliberately rejects. RLS enabled, authenticated holds zero direct grant -- the 4 RPCs below are the only sanctioned access path. Its own decide RPC additionally requires a current step-up-MFA authorization when the tenant has configured one for (COM, Approve) -- see app.decide_customer_legal_identity_change_request''s own comment.';

create unique index cplicr_tenant_idempotency_key_uq
  on app.customer_portal_legal_identity_change_requests (tenant_id, idempotency_key)
  where idempotency_key is not null;

create index cplicr_tenant_updated_id_idx
  on app.customer_portal_legal_identity_change_requests (tenant_id, updated_at desc, id desc);

create index cplicr_account_idx on app.customer_portal_legal_identity_change_requests (account_id);

create index cplicr_account_pending_idx
  on app.customer_portal_legal_identity_change_requests (account_id, status, created_at desc)
  where status = 'pending';

-- ===========================================================================
-- 2. Triggers -- mirror app.customer_portal_profile_change_requests' own
-- triggers (CPL-314) exactly (design decision 2)
-- ===========================================================================

create function app.enforce_cplicr_transition()
returns trigger
language plpgsql
as $$
begin
  if new.status = old.status then
    return new;
  end if;

  if old.status <> 'pending' then
    raise exception 'invalid_cplicr_transition: legal identity change request % is % and is terminal, no further transition is allowed', old.id, old.status
      using errcode = 'check_violation';
  end if;

  if new.status not in ('approved', 'rejected', 'withdrawn') then
    raise exception 'invalid_cplicr_transition: pending -> % is not a canonical transition', new.status
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

create trigger cplicr_enforce_transition
  before update of status on app.customer_portal_legal_identity_change_requests
  for each row
  execute function app.enforce_cplicr_transition();

create function app.touch_cplicr_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger cplicr_touch_row
  before update on app.customer_portal_legal_identity_change_requests
  for each row
  execute function app.touch_cplicr_row();

-- ===========================================================================
-- 3. app.submit_customer_legal_identity_change_request
-- ===========================================================================

create function app.submit_customer_legal_identity_change_request(
  p_tenant_id uuid,
  p_account_id uuid,
  p_field_name text,
  p_proposed_value jsonb,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.customer_portal_legal_identity_change_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_existing app.customer_portal_legal_identity_change_requests;
  v_request app.customer_portal_legal_identity_change_requests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_field_name not in ('legal_name', 'tax_id') then
    raise exception 'invalid_field_name: % is not a field a customer may propose a legal identity change for', p_field_name using errcode = 'check_violation';
  end if;

  -- Scope/authority check BEFORE the idempotent short-circuit -- mirrors CPL-314 design
  -- decision 8 exactly: an unowned/forged account_id must never let a caller probe for an
  -- existing idempotency_key's own outcome before their own authority over the account is
  -- established.
  if not (p_account_id = any (app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id))) then
    raise exception 'account_not_available: % is not an account this identity may propose a legal identity change for', p_account_id using errcode = 'no_data_found';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.customer_portal_legal_identity_change_requests where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.account_id = p_account_id then
        return v_existing;
      end if;
      raise exception 'idempotency_key_conflict: key % was already used for a different account''s legal identity change request %', p_idempotency_key, v_existing.id
        using errcode = 'unique_violation';
    end if;
  end if;

  if jsonb_typeof(p_proposed_value) <> 'string' or length(trim(coalesce(p_proposed_value #>> '{}', ''))) = 0 then
    raise exception 'invalid_proposed_value: % must be proposed as a non-empty JSON string', p_field_name using errcode = 'check_violation';
  end if;

  -- Real exception handler, not merely a pre-check -- mirrors CPL-314 design decision 8: a
  -- genuine concurrent double-submit under the identical key converges on one row.
  begin
    insert into app.customer_portal_legal_identity_change_requests (
      tenant_id, account_id, requested_by_actor_auth_user_id, field_name, proposed_value, idempotency_key
    ) values (
      p_tenant_id, p_account_id, p_actor_auth_user_id, p_field_name, p_proposed_value, p_idempotency_key
    )
    returning * into v_request;
  exception
    when unique_violation then
      if p_idempotency_key is null then
        raise;
      end if;
      select * into v_request from app.customer_portal_legal_identity_change_requests where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      if not found or v_request.account_id <> p_account_id then
        raise;
      end if;
      return v_request;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_customer_legal_identity_change_request',
    'app.customer_portal_legal_identity_change_requests', v_request.id, 'success', null, null, to_jsonb(v_request)
  );

  return v_request;
end;
$$;

comment on function app.submit_customer_legal_identity_change_request is
  'ISS-2026-123 item 1: creates a pending legal identity change request for exactly one of {legal_name, tax_id}. p_account_id must already be in app.resolve_customer_account_scope(actor, tenant) -- checked BEFORE the idempotent short-circuit. Idempotent on (tenant_id, idempotency_key) when a key is supplied; the INSERT itself carries a real unique_violation handler, not only a pre-check.';

-- ===========================================================================
-- 4. app.withdraw_customer_legal_identity_change_request -- pending -> withdrawn
-- ===========================================================================

create function app.withdraw_customer_legal_identity_change_request(
  p_request_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.customer_portal_legal_identity_change_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_request app.customer_portal_legal_identity_change_requests;
  v_updated app.customer_portal_legal_identity_change_requests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_request from app.customer_portal_legal_identity_change_requests where id = p_request_id for update;
  if not found or not (v_request.account_id = any (app.resolve_customer_account_scope(p_actor_auth_user_id, v_request.tenant_id))) then
    raise exception 'record_not_found: no permitted legal identity change request exists for %', p_request_id using errcode = 'no_data_found';
  end if;

  -- Verified live against the CURRENT (post-CPL-324) body of app.withdraw_customer_profile_
  -- change_request, not the original CPL-314 migration file text: a NULL p_expected_version
  -- must never silently bypass this guard.
  if p_expected_version is null or v_request.record_version <> p_expected_version then
    raise exception 'stale_version: legal identity change request % expected version % but found %', p_request_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_request.status <> 'pending' then
    raise exception 'invalid_transition: legal identity change request % is % and can no longer be withdrawn', p_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  -- CPL-324-shaped defense-in-depth: the version predicate is repeated atomically in the
  -- UPDATE's own WHERE clause.
  update app.customer_portal_legal_identity_change_requests
  set status = 'withdrawn'
  where id = p_request_id and record_version = p_expected_version
  returning * into v_updated;

  if not found then
    raise exception 'stale_version: legal identity change request % was concurrently modified (expected version %)', p_request_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'withdraw_customer_legal_identity_change_request',
    'app.customer_portal_legal_identity_change_requests', v_updated.id, 'success', null, null, to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

comment on function app.withdraw_customer_legal_identity_change_request is
  'ISS-2026-123 item 1: pending -> withdrawn only. Any active member of the request''s own account may withdraw it, not only its original requester. Optimistic concurrency (stale_version) checked before the status check, so a genuine retry against an already-decided row surfaces the more informative error first.';

-- ===========================================================================
-- 5. app.list_customer_portal_legal_identity_change_requests -- keyset paginated
-- ===========================================================================

create function app.list_customer_portal_legal_identity_change_requests(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_account_id uuid default null,
  p_status text default null,
  p_cursor_updated_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns setof app.customer_portal_legal_identity_change_requests
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_scope uuid[];
  v_limit integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_cursor_id is not null and p_cursor_updated_at is null then
    raise exception 'invalid_cursor: p_cursor_updated_at is required when p_cursor_id is supplied' using errcode = 'invalid_parameter_value';
  end if;

  v_scope := app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id);
  if array_length(v_scope, 1) is null then
    return;
  end if;
  if p_account_id is not null and not (p_account_id = any (v_scope)) then
    return;
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select r.*
  from app.customer_portal_legal_identity_change_requests r
  where r.tenant_id = p_tenant_id
    and r.account_id = any (v_scope)
    and (p_account_id is null or r.account_id = p_account_id)
    and (p_status is null or r.status = p_status)
    and (p_cursor_id is null or (r.updated_at, r.id) < (p_cursor_updated_at, p_cursor_id))
  order by r.updated_at desc, r.id desc
  limit v_limit;
end;
$$;

comment on function app.list_customer_portal_legal_identity_change_requests is
  'ISS-2026-123 item 1: keyset-paginated (tenant_id, updated_at desc, id desc), never OFFSET, hard-capped at 200. Deny-by-default: zero scope or an out-of-scope p_account_id both return an empty result, never an error.';

-- ===========================================================================
-- 6. app.decide_customer_legal_identity_change_request -- staff, COM:Approve
-- + step-up MFA (design decision 3), the ONLY place this migration writes to
-- app.accounts (design decisions 4-5)
-- ===========================================================================

create function app.decide_customer_legal_identity_change_request(
  p_request_id uuid,
  p_expected_version integer,
  p_decision text,
  p_review_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.customer_portal_legal_identity_change_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_request app.customer_portal_legal_identity_change_requests;
  v_decision app.rbac_decision;
  v_account app.accounts;
  v_new_legal_name text;
  v_new_tax_id text;
  v_normalized_legal_name text;
  v_normalized_tax_id text;
  v_fingerprint text;
  v_updated app.customer_portal_legal_identity_change_requests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_request from app.customer_portal_legal_identity_change_requests where id = p_request_id for update;
  -- C-05 fold (mirrors CPL-314 design decision 9 exactly): a caller with zero standing in this
  -- row's own tenant gets the identical not-found a missing row would produce.
  if not found or not (
    app.has_active_tenant_membership(v_request.tenant_id, p_actor_auth_user_id)
    or (v_request.account_id = any (app.resolve_customer_account_scope(p_actor_auth_user_id, v_request.tenant_id)))
  ) then
    raise exception 'legal_identity_change_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'COM', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Design decision 3: a strict no-op unless this tenant has itself opted (COM, Approve) into
  -- its own additional_high_risk_actions AND turned MFA on -- see app.assert_current_step_up_
  -- authorization / app.is_high_risk_action (20260807100000, IAE-027). Never widens the
  -- platform-default high-risk tuple list.
  perform app.assert_current_step_up_authorization(v_request.tenant_id, p_actor_auth_user_id, 'COM', 'Approve');

  -- Defense-in-depth, mirrors CPL-314 design decision 10 exactly.
  if v_request.requested_by_actor_auth_user_id = p_actor_auth_user_id then
    raise exception 'self_approval_not_permitted: an actor may not decide their own legal identity change request' using errcode = 'insufficient_privilege';
  end if;

  if p_decision not in ('approve', 'reject') then
    raise exception 'invalid_decision: % must be approve or reject', p_decision using errcode = 'check_violation';
  end if;

  if p_review_reason is null or length(trim(p_review_reason)) = 0 then
    raise exception 'reason_required: a reason is required to decide a legal identity change request' using errcode = 'not_null_violation';
  end if;

  -- Verified live against the CURRENT (post-CPL-324) body of app.decide_customer_profile_
  -- change_request, not the original CPL-314 migration file text: a NULL p_expected_version
  -- must never silently bypass this guard.
  if p_expected_version is null or v_request.record_version <> p_expected_version then
    raise exception 'stale_version: legal identity change request % expected version % but found %', p_request_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_request.status <> 'pending' then
    raise exception 'invalid_transition: legal identity change request % is % and cannot be decided', p_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  if p_decision = 'approve' then
    select * into v_account from app.accounts where id = v_request.account_id for update;

    -- Explicit if/elsif/else with a real ELSE (design decision 4) -- field_name is CHECK-
    -- constrained to {legal_name, tax_id} so this else is structurally unreachable, but an
    -- else-less branch is exactly the shape that would silently mark a request approved while
    -- changing nothing.
    if v_request.field_name = 'legal_name' then
      v_new_legal_name := v_request.proposed_value #>> '{}';
      v_new_tax_id := v_account.tax_id;
    elsif v_request.field_name = 'tax_id' then
      v_new_legal_name := v_account.legal_name;
      v_new_tax_id := v_request.proposed_value #>> '{}';
    else
      raise exception 'unhandled_field_name: % is not a recognized legal identity field', v_request.field_name using errcode = 'data_exception';
    end if;

    -- Design decision 4: reuses the SAME normalization/fingerprint functions app.
    -- convert_quotation_to_account (COM-155) already calls -- never hand-duplicated.
    v_normalized_legal_name := app.normalize_prospect_identifier(v_new_legal_name);
    v_normalized_tax_id := app.normalize_prospect_identifier(v_new_tax_id);
    v_fingerprint := app.compute_prospect_duplicate_fingerprint(v_account.tenant_id, v_normalized_legal_name, v_normalized_tax_id);

    begin
      update app.accounts
      set legal_name = v_new_legal_name,
          tax_id = v_new_tax_id,
          normalized_legal_name = v_normalized_legal_name,
          normalized_tax_id = v_normalized_tax_id,
          duplicate_fingerprint = v_fingerprint
      where id = v_account.id;
    exception
      when unique_violation then
        -- Design decision 5: re-raised, never swallowed -- this abort propagates out of the
        -- whole function, so the request-status UPDATE below never runs either. Proven live
        -- (same-transaction rollback, both accounts unchanged) in this migration's own db-test.
        raise exception 'identity_fingerprint_conflict: approving this change would make account %''s legal identity collide with another active account''s own identity fingerprint in tenant %', v_account.id, v_account.tenant_id
          using errcode = 'unique_violation';
    end;
  end if;

  -- CPL-324-shaped defense-in-depth: the version predicate is repeated atomically in the
  -- UPDATE's own WHERE clause. If the approve-branch app.accounts write above was taken, it
  -- rolls back together with this UPDATE's own failure -- same transaction, no partial effect.
  update app.customer_portal_legal_identity_change_requests
  set status = case p_decision when 'approve' then 'approved' else 'rejected' end,
      reviewed_by = p_actor_label, reviewed_at = now(), review_reason = p_review_reason
  where id = p_request_id and record_version = p_expected_version
  returning * into v_updated;

  if not found then
    raise exception 'stale_version: legal identity change request % was concurrently modified (expected version %)', p_request_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  -- p_review_reason is never routed into the audit before/after jsonb unredacted -- mirrors
  -- CPL-314 design decision 13.
  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_customer_legal_identity_change_request',
    'app.customer_portal_legal_identity_change_requests', v_updated.id, 'success', null,
    jsonb_build_object('status', v_request.status, 'field_name', v_request.field_name),
    jsonb_build_object('status', v_updated.status, 'field_name', v_updated.field_name)
  );

  return v_updated;
end;
$$;

comment on function app.decide_customer_legal_identity_change_request is
  'ISS-2026-123 item 1: staff-only (COM:Approve), ADDITIONALLY gated on app.assert_current_step_up_authorization(tenant, actor, ''COM'', ''Approve'') immediately after the ordinary authority check -- a no-op unless the tenant has both turned on MFA (app.mfa_tenant_policies.tenant_wide_required) AND added (COM, Approve) to its own additional_high_risk_actions list (app.set_mfa_tenant_policy) -- never a change to the platform-default high-risk classification. pending -> approved | rejected. review_reason is mandatory for BOTH outcomes, never persisted into the audit before/after snapshot unredacted. On approve, recomputes normalized_legal_name/normalized_tax_id/duplicate_fingerprint via app.normalize_prospect_identifier/app.compute_prospect_duplicate_fingerprint (the same functions app.convert_quotation_to_account already uses) and applies the change to the real app.accounts row in the SAME transaction -- the ONLY place this migration writes to app.accounts. A resulting identity_fingerprint_conflict (accounts_tenant_fingerprint_active_unique) aborts the whole decision atomically -- the request stays pending and app.accounts is completely unchanged. On reject, app.accounts is left completely untouched. Self-approval is structurally blocked.';

-- ===========================================================================
-- 7. RLS -- enable, grant service_role only (mirrors CPL-314 design decision 15)
-- ===========================================================================

alter table app.customer_portal_legal_identity_change_requests enable row level security;

grant select, insert, update, delete on app.customer_portal_legal_identity_change_requests to service_role;

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke of
-- PostgreSQL's PUBLIC-execute default before any role-specific grant.
revoke execute on all functions in schema app from public;

grant execute on function app.submit_customer_legal_identity_change_request(uuid, uuid, text, jsonb, text, uuid, text) to authenticated, service_role;
grant execute on function app.withdraw_customer_legal_identity_change_request(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.list_customer_portal_legal_identity_change_requests(uuid, uuid, uuid, text, timestamptz, uuid, integer) to authenticated, service_role;
grant execute on function app.decide_customer_legal_identity_change_request(uuid, integer, text, text, uuid, text) to authenticated, service_role;

-- ===========================================================================
-- 8. public.* wrappers (RGL-394 Option 2) -- app is not exposed to PostgREST,
-- mirrors every migration's own convention since 20260826000000
-- ===========================================================================

create function public.submit_customer_legal_identity_change_request(
  p_tenant_id uuid, p_account_id uuid, p_field_name text, p_proposed_value jsonb,
  p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.customer_portal_legal_identity_change_requests
language sql
security definer
set search_path = app, public, pg_temp
as $wrap$
  select app.submit_customer_legal_identity_change_request(p_tenant_id, p_account_id, p_field_name, p_proposed_value, p_idempotency_key, p_actor_auth_user_id, p_actor_label);
$wrap$;

comment on function public.submit_customer_legal_identity_change_request(uuid, uuid, text, jsonb, text, uuid, text) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.submit_customer_legal_identity_change_request, never a reimplementation.';

revoke execute on function public.submit_customer_legal_identity_change_request(uuid, uuid, text, jsonb, text, uuid, text) from anon, authenticated, service_role, public;
grant execute on function public.submit_customer_legal_identity_change_request(uuid, uuid, text, jsonb, text, uuid, text) to authenticated, service_role;

create function public.withdraw_customer_legal_identity_change_request(p_request_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.customer_portal_legal_identity_change_requests
language sql
security definer
set search_path = app, public, pg_temp
as $wrap$
  select app.withdraw_customer_legal_identity_change_request(p_request_id, p_expected_version, p_actor_auth_user_id, p_actor_label);
$wrap$;

comment on function public.withdraw_customer_legal_identity_change_request(uuid, integer, uuid, text) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.withdraw_customer_legal_identity_change_request, never a reimplementation.';

revoke execute on function public.withdraw_customer_legal_identity_change_request(uuid, integer, uuid, text) from anon, authenticated, service_role, public;
grant execute on function public.withdraw_customer_legal_identity_change_request(uuid, integer, uuid, text) to authenticated, service_role;

create function public.list_customer_portal_legal_identity_change_requests(
  p_tenant_id uuid, p_actor_auth_user_id uuid, p_account_id uuid default null::uuid, p_status text default null::text,
  p_cursor_updated_at timestamptz default null::timestamptz, p_cursor_id uuid default null::uuid, p_limit integer default 50
)
returns setof app.customer_portal_legal_identity_change_requests
language sql
stable
security definer
set search_path = app, public, pg_temp
as $wrap$
  select * from app.list_customer_portal_legal_identity_change_requests(p_tenant_id, p_actor_auth_user_id, p_account_id, p_status, p_cursor_updated_at, p_cursor_id, p_limit);
$wrap$;

comment on function public.list_customer_portal_legal_identity_change_requests(uuid, uuid, uuid, text, timestamptz, uuid, integer) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.list_customer_portal_legal_identity_change_requests, never a reimplementation.';

revoke execute on function public.list_customer_portal_legal_identity_change_requests(uuid, uuid, uuid, text, timestamptz, uuid, integer) from anon, authenticated, service_role, public;
grant execute on function public.list_customer_portal_legal_identity_change_requests(uuid, uuid, uuid, text, timestamptz, uuid, integer) to authenticated, service_role;

create function public.decide_customer_legal_identity_change_request(p_request_id uuid, p_expected_version integer, p_decision text, p_review_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.customer_portal_legal_identity_change_requests
language sql
security definer
set search_path = app, public, pg_temp
as $wrap$
  select app.decide_customer_legal_identity_change_request(p_request_id, p_expected_version, p_decision, p_review_reason, p_actor_auth_user_id, p_actor_label);
$wrap$;

comment on function public.decide_customer_legal_identity_change_request(uuid, integer, text, text, uuid, text) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.decide_customer_legal_identity_change_request, never a reimplementation.';

revoke execute on function public.decide_customer_legal_identity_change_request(uuid, integer, text, text, uuid, text) from anon, authenticated, service_role, public;
grant execute on function public.decide_customer_legal_identity_change_request(uuid, integer, text, text, uuid, text) to authenticated, service_role;
