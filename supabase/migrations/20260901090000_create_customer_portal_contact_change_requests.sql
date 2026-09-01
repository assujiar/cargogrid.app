-- ISS-2026-123 item 2 (docs/runtime/KNOWN_ISSUES.md) -- a customer-initiated contact add/
-- update/remove change-request path for app.contacts/app.contact_links (COM-145/COM-155),
-- read into the customer portal today ONLY via the read-only app.list_customer_portal_
-- account_contacts (CPL-314, 20260801150000_create_customer_portal_customer_profile.sql,
-- design decision 4 -- read that migration and this one's own sibling,
-- 20260901080000_create_customer_portal_legal_identity_change_requests.sql, in full first: the
-- same status lifecycle, review fields, idempotency-key unique index, touch/transition trigger
-- pair, C-05 not-found fold, self-approval guard and RLS/grant shape are reproduced verbatim
-- below as genuinely separate objects for a genuinely different resource).
--
-- ===========================================================================
-- Design decisions
-- ===========================================================================
--
-- 1. **change_kind {add, update, remove}, target_contact_id required for update/remove and
--    forbidden for add -- enforced by CHECK, at the database, not merely the RPC.** A contact
--    lives on TWO tables: app.contacts (full_name/title/email/phone) and app.contact_links
--    (the account link's own role/is_primary). 'add' proposes both a new app.contacts row and
--    its link to this account; 'update' proposes a partial change to either or both (any
--    column left null in the request means "unchanged" -- there is no "clear this field to
--    empty" affordance, matching every other partial-update shape in this repository and never
--    letting a request leave a contact violating contacts_contact_identifier_check); 'remove'
--    proposes unlinking (never deleting the underlying app.contacts row -- COM-145's own
--    "contacts are shared, links are the account association" ownership model is preserved,
--    matching app.unlink_contact_from_record's own established behavior).
-- 2. **Submit re-verifies "genuinely linked to THIS account," never merely "exists somewhere,"
--    for update/remove -- and returns the SAME not-found-shaped error (errcode no_data_found)
--    whether the contact does not exist, belongs to a different tenant, or is linked to a
--    DIFFERENT account.** Queried directly against app.contact_links/app.contacts (verified
--    live: contact_links.related_type/related_id is the join, contact_links_unique is (contact_
--    id, related_type, related_id, role)) -- the three causes are structurally indistinguishable
--    by design, an anti-enumeration/oracle discipline mirroring CPL-314's own get-by-id
--    convention. Re-verified again, still locked, inside decide's own approve branch -- the
--    link may have been removed by a different actor between submit and decide.
-- 3. **Decide's approve branch reuses the existing creation/linking/unlinking primitives --
--    never a raw table write for add/remove.** 'add' calls app.create_contact (COM:Create) then
--    app.link_contact_to_record (COM:Edit + app.can_access_record on both sides) -- verified
--    live signatures below -- so the SAME authority/audit discipline those functions already
--    carry applies here, never bypassed. 'remove' calls app.unlink_contact_from_record
--    (COM:Edit + app.can_access_record) rather than a raw DELETE, for the identical reason --
--    live-verified it captures its own app.capture_audit_event('unlink_contact_from_record',
--    ...), so a remove approved through this path is provably audited on that existing surface,
--    not merely on this migration's own decide-level audit row. Both created-contact fields
--    (owner_user_id/org_unit_id) are deliberately set to the DECIDING staff actor / the
--    account's own org_unit_id respectively -- the natural "who is accountable for this record"
--    default this repository's own contacts_select_scoped RLS policy already keys visibility
--    on, since app.accounts itself is tenant-wide visible (COM-155) and carries no owner of its
--    own to inherit.
-- 4. **'update' has no reusable generic "update_contact" primitive to call** (verified live:
--    app.update_vendor_contact/app.update_employee_emergency_contact are for a DIFFERENT
--    domain's own contact-shaped tables, not app.contacts) -- a direct, explicit UPDATE is the
--    correct shape here, not a gap. app.contacts carries exactly one trigger,
--    contacts_set_computed_fields (BEFORE INSERT OR UPDATE OF email, phone -- verified live via
--    pg_trigger, not assumed from any migration file that may have been superseded since),
--    which recomputes normalized_email/normalized_phone/duplicate_fingerprint/updated_at -- but
--    NEVER record_version, which no trigger on this table touches at all. The approve branch's
--    own UPDATE therefore always names email/phone/full_name/title together (so the trigger
--    reliably fires whenever any of those four change) AND always bumps updated_at/
--    record_version explicitly itself -- never relying on the trigger for the one column it
--    does not cover. A role/is_primary change against app.contact_links is wrapped in its own
--    `exception when unique_violation` (contact_links_unique) and re-raises a clearly-named
--    contact_link_conflict, never a raw constraint violation leaking to the caller.
-- 5. Every actor-taking function calls app.assert_actor_is_session_identity as its own literal
--    first statement. Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries
--    its own explicit `revoke execute on all functions in schema app from public` before its
--    final grants. public.* wrappers (RGL-394 Option 2) ship in this same migration.
-- 6. **Decide's step-up-MFA gate mirrors this migration's own legal-identity sibling exactly**
--    (app.assert_current_step_up_authorization(tenant, actor, 'COM', 'Approve'), immediately
--    after the ordinary COM:Approve gate) -- a real, live authorization mechanism (IAE-027,
--    20260807100000/20260830110000) that did not exist when ISS-2026-123 was first disclosed,
--    a strict no-op for any tenant that has not additively opted (COM, Approve) into its own
--    app.mfa_tenant_policies.additional_high_risk_actions AND turned MFA on. This migration
--    never widens app.is_high_risk_action's own platform-default tuple list.

-- ===========================================================================
-- 1. app.customer_portal_contact_change_requests
-- ===========================================================================

create table app.customer_portal_contact_change_requests (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  account_id uuid not null references app.accounts (id),
  requested_by_actor_auth_user_id uuid not null references auth.users (id),
  change_kind text not null,
  target_contact_id uuid references app.contacts (id),
  full_name text,
  title text,
  email text,
  phone text,
  role text,
  is_primary boolean,
  status text not null default 'pending',
  reviewed_by text,
  reviewed_at timestamptz,
  review_reason text,
  idempotency_key text,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint cpccr_change_kind_check check (change_kind in ('add', 'update', 'remove')),
  constraint cpccr_target_contact_shape_check check (
    (change_kind = 'add' and target_contact_id is null)
    or (change_kind in ('update', 'remove') and target_contact_id is not null)
  ),
  constraint cpccr_add_fields_check check (
    change_kind <> 'add'
    or (full_name is not null and length(trim(full_name)) > 0 and (email is not null or phone is not null))
  ),
  constraint cpccr_update_fields_check check (
    change_kind <> 'update'
    or (full_name is not null or title is not null or email is not null or phone is not null or role is not null or is_primary is not null)
  ),
  constraint cpccr_remove_fields_check check (
    change_kind <> 'remove'
    or (full_name is null and title is null and email is null and phone is null and role is null and is_primary is null)
  ),
  constraint cpccr_role_check check (role is null or role in ('primary', 'billing', 'technical', 'decision_maker', 'other')),
  constraint cpccr_status_check check (status in ('pending', 'approved', 'rejected', 'withdrawn')),
  constraint cpccr_review_fields_check check (
    (status in ('approved', 'rejected')) = (reviewed_by is not null and reviewed_at is not null)
  ),
  constraint cpccr_review_reason_check check (
    (status in ('approved', 'rejected') and review_reason is not null and length(trim(review_reason)) > 0)
    or (status not in ('approved', 'rejected'))
  )
);

comment on table app.customer_portal_contact_change_requests is
  'ISS-2026-123 item 2: the portal-owned contact add/update/remove change REQUEST for a customer''s own account (app.contacts/app.contact_links, COM-145/COM-155) -- never a direct write from a customer-initiated RPC. change_kind is CHECK-constrained to {add, update, remove}; target_contact_id is required for update/remove and forbidden for add (cpccr_target_contact_shape_check). RLS enabled, authenticated holds zero direct grant -- the 4 RPCs below are the only sanctioned access path. Its own decide RPC additionally requires a current step-up-MFA authorization when the tenant has configured one for (COM, Approve).';

create unique index cpccr_tenant_idempotency_key_uq
  on app.customer_portal_contact_change_requests (tenant_id, idempotency_key)
  where idempotency_key is not null;

create index cpccr_tenant_updated_id_idx
  on app.customer_portal_contact_change_requests (tenant_id, updated_at desc, id desc);

create index cpccr_account_idx on app.customer_portal_contact_change_requests (account_id);

create index cpccr_account_pending_idx
  on app.customer_portal_contact_change_requests (account_id, status, created_at desc)
  where status = 'pending';

-- ===========================================================================
-- 2. Triggers -- mirror this migration's own legal-identity sibling exactly
-- ===========================================================================

create function app.enforce_cpccr_transition()
returns trigger
language plpgsql
as $$
begin
  if new.status = old.status then
    return new;
  end if;

  if old.status <> 'pending' then
    raise exception 'invalid_cpccr_transition: contact change request % is % and is terminal, no further transition is allowed', old.id, old.status
      using errcode = 'check_violation';
  end if;

  if new.status not in ('approved', 'rejected', 'withdrawn') then
    raise exception 'invalid_cpccr_transition: pending -> % is not a canonical transition', new.status
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

create trigger cpccr_enforce_transition
  before update of status on app.customer_portal_contact_change_requests
  for each row
  execute function app.enforce_cpccr_transition();

create function app.touch_cpccr_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger cpccr_touch_row
  before update on app.customer_portal_contact_change_requests
  for each row
  execute function app.touch_cpccr_row();

-- ===========================================================================
-- 3. app.submit_customer_contact_change_request
-- ===========================================================================

create function app.submit_customer_contact_change_request(
  p_tenant_id uuid,
  p_account_id uuid,
  p_change_kind text,
  p_target_contact_id uuid,
  p_full_name text,
  p_title text,
  p_email text,
  p_phone text,
  p_role text,
  p_is_primary boolean,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.customer_portal_contact_change_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_existing app.customer_portal_contact_change_requests;
  v_request app.customer_portal_contact_change_requests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_change_kind not in ('add', 'update', 'remove') then
    raise exception 'invalid_change_kind: % is not add, update or remove', p_change_kind using errcode = 'check_violation';
  end if;

  -- Scope/authority check BEFORE the idempotent short-circuit -- mirrors this migration's own
  -- legal-identity sibling and CPL-314's design decision 8 exactly.
  if not (p_account_id = any (app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id))) then
    raise exception 'account_not_available: % is not an account this identity may propose a contact change for', p_account_id using errcode = 'no_data_found';
  end if;

  if p_change_kind = 'add' then
    if p_target_contact_id is not null then
      raise exception 'invalid_target_contact: a target contact may not be supplied for an add request' using errcode = 'check_violation';
    end if;
    if p_full_name is null or length(trim(p_full_name)) = 0 then
      raise exception 'invalid_proposed_value: full_name is required to add a contact' using errcode = 'check_violation';
    end if;
    if p_email is null and p_phone is null then
      raise exception 'invalid_proposed_value: at least one of email or phone is required to add a contact' using errcode = 'check_violation';
    end if;
  else
    if p_target_contact_id is null then
      raise exception 'invalid_target_contact: a target contact is required for % requests', p_change_kind using errcode = 'check_violation';
    end if;

    -- Design decision 2: the SAME not-found-shaped error whether the contact does not exist,
    -- belongs to a different tenant, or is linked to a different account.
    if not exists (
      select 1 from app.contact_links cl
      join app.contacts c on c.id = cl.contact_id
      where cl.contact_id = p_target_contact_id
        and cl.related_type = 'account'
        and cl.related_id = p_account_id
        and cl.tenant_id = p_tenant_id
        and c.tenant_id = p_tenant_id
        and c.status = 'active'
    ) then
      raise exception 'contact_not_available: % is not a contact linked to this account', p_target_contact_id using errcode = 'no_data_found';
    end if;

    if p_change_kind = 'update' and p_full_name is null and p_title is null and p_email is null and p_phone is null and p_role is null and p_is_primary is null then
      raise exception 'invalid_proposed_value: at least one field must be proposed for an update request' using errcode = 'check_violation';
    end if;
    if p_change_kind = 'remove' and (p_full_name is not null or p_title is not null or p_email is not null or p_phone is not null or p_role is not null or p_is_primary is not null) then
      raise exception 'invalid_proposed_value: a remove request carries no field values' using errcode = 'check_violation';
    end if;
  end if;

  if p_role is not null and p_role not in ('primary', 'billing', 'technical', 'decision_maker', 'other') then
    raise exception 'invalid_role: % is not a recognized contact role', p_role using errcode = 'check_violation';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.customer_portal_contact_change_requests where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.account_id = p_account_id then
        return v_existing;
      end if;
      raise exception 'idempotency_key_conflict: key % was already used for a different account''s contact change request %', p_idempotency_key, v_existing.id
        using errcode = 'unique_violation';
    end if;
  end if;

  -- Real exception handler, not merely a pre-check -- mirrors CPL-314 design decision 8.
  begin
    insert into app.customer_portal_contact_change_requests (
      tenant_id, account_id, requested_by_actor_auth_user_id, change_kind, target_contact_id,
      full_name, title, email, phone, role, is_primary, idempotency_key
    ) values (
      p_tenant_id, p_account_id, p_actor_auth_user_id, p_change_kind, p_target_contact_id,
      p_full_name, p_title, p_email, p_phone, p_role, p_is_primary, p_idempotency_key
    )
    returning * into v_request;
  exception
    when unique_violation then
      if p_idempotency_key is null then
        raise;
      end if;
      select * into v_request from app.customer_portal_contact_change_requests where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      if not found or v_request.account_id <> p_account_id then
        raise;
      end if;
      return v_request;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_customer_contact_change_request',
    'app.customer_portal_contact_change_requests', v_request.id, 'success', null, null, to_jsonb(v_request)
  );

  return v_request;
end;
$$;

comment on function app.submit_customer_contact_change_request is
  'ISS-2026-123 item 2: creates a pending contact change request (add/update/remove) for an account this identity holds real scope over (app.resolve_customer_account_scope, checked BEFORE the idempotent short-circuit). For update/remove, target_contact_id must be genuinely linked to THIS account (design decision 2) -- the same anti-enumerating contact_not_available error whether the contact does not exist, belongs to a different tenant, or is linked elsewhere. Idempotent on (tenant_id, idempotency_key) when a key is supplied.';

-- ===========================================================================
-- 4. app.withdraw_customer_contact_change_request -- pending -> withdrawn
-- ===========================================================================

create function app.withdraw_customer_contact_change_request(
  p_request_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.customer_portal_contact_change_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_request app.customer_portal_contact_change_requests;
  v_updated app.customer_portal_contact_change_requests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_request from app.customer_portal_contact_change_requests where id = p_request_id for update;
  if not found or not (v_request.account_id = any (app.resolve_customer_account_scope(p_actor_auth_user_id, v_request.tenant_id))) then
    raise exception 'record_not_found: no permitted contact change request exists for %', p_request_id using errcode = 'no_data_found';
  end if;

  -- Verified live against the CURRENT (post-CPL-324) body of app.withdraw_customer_profile_
  -- change_request, not the original CPL-314 migration file text: a NULL p_expected_version
  -- must never silently bypass this guard.
  if p_expected_version is null or v_request.record_version <> p_expected_version then
    raise exception 'stale_version: contact change request % expected version % but found %', p_request_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_request.status <> 'pending' then
    raise exception 'invalid_transition: contact change request % is % and can no longer be withdrawn', p_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  -- CPL-324-shaped defense-in-depth: the version predicate is repeated atomically in the
  -- UPDATE's own WHERE clause.
  update app.customer_portal_contact_change_requests
  set status = 'withdrawn'
  where id = p_request_id and record_version = p_expected_version
  returning * into v_updated;

  if not found then
    raise exception 'stale_version: contact change request % was concurrently modified (expected version %)', p_request_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'withdraw_customer_contact_change_request',
    'app.customer_portal_contact_change_requests', v_updated.id, 'success', null, null, to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

comment on function app.withdraw_customer_contact_change_request is
  'ISS-2026-123 item 2: pending -> withdrawn only. Any active member of the request''s own account may withdraw it, not only its original requester. Optimistic concurrency (stale_version) checked before the status check.';

-- ===========================================================================
-- 5. app.list_customer_portal_contact_change_requests -- keyset paginated
-- ===========================================================================

create function app.list_customer_portal_contact_change_requests(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_account_id uuid default null,
  p_status text default null,
  p_cursor_updated_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns setof app.customer_portal_contact_change_requests
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
  from app.customer_portal_contact_change_requests r
  where r.tenant_id = p_tenant_id
    and r.account_id = any (v_scope)
    and (p_account_id is null or r.account_id = p_account_id)
    and (p_status is null or r.status = p_status)
    and (p_cursor_id is null or (r.updated_at, r.id) < (p_cursor_updated_at, p_cursor_id))
  order by r.updated_at desc, r.id desc
  limit v_limit;
end;
$$;

comment on function app.list_customer_portal_contact_change_requests is
  'ISS-2026-123 item 2: keyset-paginated (tenant_id, updated_at desc, id desc), never OFFSET, hard-capped at 200. Deny-by-default: zero scope or an out-of-scope p_account_id both return an empty result, never an error.';

-- ===========================================================================
-- 6. app.decide_customer_contact_change_request -- staff, COM:Approve + step-up
-- MFA (design decision 6); approve reuses create_contact/link_contact_to_
-- record/unlink_contact_from_record (design decision 3) or a direct, explicit
-- UPDATE for 'update' (design decision 4)
-- ===========================================================================

create function app.decide_customer_contact_change_request(
  p_request_id uuid,
  p_expected_version integer,
  p_decision text,
  p_review_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.customer_portal_contact_change_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_request app.customer_portal_contact_change_requests;
  v_decision app.rbac_decision;
  v_account app.accounts;
  v_contact app.contacts;
  v_link app.contact_links;
  v_updated app.customer_portal_contact_change_requests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_request from app.customer_portal_contact_change_requests where id = p_request_id for update;
  -- C-05 fold (mirrors CPL-314 design decision 9 exactly).
  if not found or not (
    app.has_active_tenant_membership(v_request.tenant_id, p_actor_auth_user_id)
    or (v_request.account_id = any (app.resolve_customer_account_scope(p_actor_auth_user_id, v_request.tenant_id)))
  ) then
    raise exception 'contact_change_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'COM', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Design decision 6: a strict no-op unless this tenant has itself opted (COM, Approve) into
  -- its own additional_high_risk_actions AND turned MFA on.
  perform app.assert_current_step_up_authorization(v_request.tenant_id, p_actor_auth_user_id, 'COM', 'Approve');

  if v_request.requested_by_actor_auth_user_id = p_actor_auth_user_id then
    raise exception 'self_approval_not_permitted: an actor may not decide their own contact change request' using errcode = 'insufficient_privilege';
  end if;

  if p_decision not in ('approve', 'reject') then
    raise exception 'invalid_decision: % must be approve or reject', p_decision using errcode = 'check_violation';
  end if;

  if p_review_reason is null or length(trim(p_review_reason)) = 0 then
    raise exception 'reason_required: a reason is required to decide a contact change request' using errcode = 'not_null_violation';
  end if;

  -- Verified live against the CURRENT (post-CPL-324) body of app.decide_customer_profile_
  -- change_request, not the original CPL-314 migration file text: a NULL p_expected_version
  -- must never silently bypass this guard.
  if p_expected_version is null or v_request.record_version <> p_expected_version then
    raise exception 'stale_version: contact change request % expected version % but found %', p_request_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_request.status <> 'pending' then
    raise exception 'invalid_transition: contact change request % is % and cannot be decided', p_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  if p_decision = 'approve' then
    select * into v_account from app.accounts where id = v_request.account_id;

    -- Explicit if/elsif/else with a real ELSE -- change_kind is CHECK-constrained to {add,
    -- update, remove} so this else is structurally unreachable, but never silently a no-op.
    if v_request.change_kind = 'add' then
      -- Design decision 3: reuses app.create_contact (COM:Create) + app.link_contact_to_record
      -- (COM:Edit) -- never a raw INSERT. owner_user_id is the deciding staff actor,
      -- org_unit_id inherits the account's own -- app.accounts carries no owner of its own to
      -- inherit (COM-155, tenant-wide visible).
      v_contact := app.create_contact(
        v_request.tenant_id, v_request.full_name, v_request.title, v_request.email, v_request.phone,
        p_actor_auth_user_id, v_account.org_unit_id, p_actor_auth_user_id, p_actor_label
      );
      perform app.link_contact_to_record(
        v_contact.id, 'account', v_request.account_id, coalesce(v_request.role, 'other'), coalesce(v_request.is_primary, false),
        p_actor_auth_user_id, p_actor_label
      );
    elsif v_request.change_kind = 'update' then
      -- Design decision 2: re-verified live, locked -- the link may have been removed by a
      -- different actor between submit and decide.
      select * into v_link from app.contact_links
      where contact_id = v_request.target_contact_id and related_type = 'account' and related_id = v_request.account_id and tenant_id = v_request.tenant_id
      order by is_primary desc, created_at asc
      limit 1
      for update;
      if not found then
        raise exception 'contact_not_available: % is no longer a contact linked to this account', v_request.target_contact_id using errcode = 'no_data_found';
      end if;

      if v_request.full_name is not null or v_request.title is not null or v_request.email is not null or v_request.phone is not null then
        -- Design decision 4: email/phone are always named in the SET clause (even when
        -- COALESCEd to their own current value) so contacts_set_computed_fields (BEFORE UPDATE
        -- OF email, phone) reliably fires; record_version/updated_at are bumped explicitly
        -- here regardless, since no trigger on this table ever touches record_version.
        update app.contacts
        set full_name = coalesce(v_request.full_name, full_name),
            title = coalesce(v_request.title, title),
            email = coalesce(v_request.email, email),
            phone = coalesce(v_request.phone, phone),
            updated_at = now(),
            record_version = record_version + 1
        where id = v_request.target_contact_id;
      end if;

      if v_request.role is not null or v_request.is_primary is not null then
        begin
          update app.contact_links
          set role = coalesce(v_request.role, role),
              is_primary = coalesce(v_request.is_primary, is_primary)
          where id = v_link.id;
        exception
          when unique_violation then
            raise exception 'contact_link_conflict: this role change would collide with an existing link for the same contact and account' using errcode = 'unique_violation';
        end;
      end if;
    elsif v_request.change_kind = 'remove' then
      select * into v_link from app.contact_links
      where contact_id = v_request.target_contact_id and related_type = 'account' and related_id = v_request.account_id and tenant_id = v_request.tenant_id
      order by is_primary desc, created_at asc
      limit 1
      for update;
      if not found then
        raise exception 'contact_not_available: % is no longer a contact linked to this account', v_request.target_contact_id using errcode = 'no_data_found';
      end if;

      -- Design decision 3: reuses app.unlink_contact_from_record -- never a raw DELETE. That
      -- function captures its own audit event on 'app.contact_links'.
      perform app.unlink_contact_from_record(v_link.id, p_actor_auth_user_id, p_actor_label);
    else
      raise exception 'unhandled_change_kind: % is not a recognized contact change kind', v_request.change_kind using errcode = 'data_exception';
    end if;
  end if;

  -- CPL-324-shaped defense-in-depth: the version predicate is repeated atomically in the
  -- UPDATE's own WHERE clause. If the approve-branch contact/link writes above were taken,
  -- they roll back together with this UPDATE's own failure -- same transaction, no partial
  -- effect.
  update app.customer_portal_contact_change_requests
  set status = case p_decision when 'approve' then 'approved' else 'rejected' end,
      reviewed_by = p_actor_label, reviewed_at = now(), review_reason = p_review_reason
  where id = p_request_id and record_version = p_expected_version
  returning * into v_updated;

  if not found then
    raise exception 'stale_version: contact change request % was concurrently modified (expected version %)', p_request_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_customer_contact_change_request',
    'app.customer_portal_contact_change_requests', v_updated.id, 'success', null,
    jsonb_build_object('status', v_request.status, 'change_kind', v_request.change_kind),
    jsonb_build_object('status', v_updated.status, 'change_kind', v_updated.change_kind)
  );

  return v_updated;
end;
$$;

comment on function app.decide_customer_contact_change_request is
  'ISS-2026-123 item 2: staff-only (COM:Approve), ADDITIONALLY gated on app.assert_current_step_up_authorization(tenant, actor, ''COM'', ''Approve'') immediately after the ordinary authority check -- a no-op unless the tenant has both turned on MFA AND added (COM, Approve) to its own additional_high_risk_actions list. pending -> approved | rejected. review_reason is mandatory for both outcomes. On approve: add calls app.create_contact + app.link_contact_to_record; remove calls app.unlink_contact_from_record; update issues a direct, explicit UPDATE against app.contacts/app.contact_links (no generic update primitive exists for this table) and explicitly bumps app.contacts.record_version, which no trigger on that table touches. Self-approval is structurally blocked.';

-- ===========================================================================
-- 7. RLS -- enable, grant service_role only (mirrors CPL-314 design decision 15)
-- ===========================================================================

alter table app.customer_portal_contact_change_requests enable row level security;

grant select, insert, update, delete on app.customer_portal_contact_change_requests to service_role;

revoke execute on all functions in schema app from public;

grant execute on function app.submit_customer_contact_change_request(uuid, uuid, text, uuid, text, text, text, text, text, boolean, text, uuid, text) to authenticated, service_role;
grant execute on function app.withdraw_customer_contact_change_request(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.list_customer_portal_contact_change_requests(uuid, uuid, uuid, text, timestamptz, uuid, integer) to authenticated, service_role;
grant execute on function app.decide_customer_contact_change_request(uuid, integer, text, text, uuid, text) to authenticated, service_role;

-- ===========================================================================
-- 8. public.* wrappers (RGL-394 Option 2) -- app is not exposed to PostgREST
-- ===========================================================================

create function public.submit_customer_contact_change_request(
  p_tenant_id uuid, p_account_id uuid, p_change_kind text, p_target_contact_id uuid,
  p_full_name text, p_title text, p_email text, p_phone text, p_role text, p_is_primary boolean,
  p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.customer_portal_contact_change_requests
language sql
security definer
set search_path = app, public, pg_temp
as $wrap$
  select app.submit_customer_contact_change_request(p_tenant_id, p_account_id, p_change_kind, p_target_contact_id, p_full_name, p_title, p_email, p_phone, p_role, p_is_primary, p_idempotency_key, p_actor_auth_user_id, p_actor_label);
$wrap$;

comment on function public.submit_customer_contact_change_request(uuid, uuid, text, uuid, text, text, text, text, text, boolean, text, uuid, text) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.submit_customer_contact_change_request, never a reimplementation.';

revoke execute on function public.submit_customer_contact_change_request(uuid, uuid, text, uuid, text, text, text, text, text, boolean, text, uuid, text) from anon, authenticated, service_role, public;
grant execute on function public.submit_customer_contact_change_request(uuid, uuid, text, uuid, text, text, text, text, text, boolean, text, uuid, text) to authenticated, service_role;

create function public.withdraw_customer_contact_change_request(p_request_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.customer_portal_contact_change_requests
language sql
security definer
set search_path = app, public, pg_temp
as $wrap$
  select app.withdraw_customer_contact_change_request(p_request_id, p_expected_version, p_actor_auth_user_id, p_actor_label);
$wrap$;

comment on function public.withdraw_customer_contact_change_request(uuid, integer, uuid, text) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.withdraw_customer_contact_change_request, never a reimplementation.';

revoke execute on function public.withdraw_customer_contact_change_request(uuid, integer, uuid, text) from anon, authenticated, service_role, public;
grant execute on function public.withdraw_customer_contact_change_request(uuid, integer, uuid, text) to authenticated, service_role;

create function public.list_customer_portal_contact_change_requests(
  p_tenant_id uuid, p_actor_auth_user_id uuid, p_account_id uuid default null::uuid, p_status text default null::text,
  p_cursor_updated_at timestamptz default null::timestamptz, p_cursor_id uuid default null::uuid, p_limit integer default 50
)
returns setof app.customer_portal_contact_change_requests
language sql
stable
security definer
set search_path = app, public, pg_temp
as $wrap$
  select * from app.list_customer_portal_contact_change_requests(p_tenant_id, p_actor_auth_user_id, p_account_id, p_status, p_cursor_updated_at, p_cursor_id, p_limit);
$wrap$;

comment on function public.list_customer_portal_contact_change_requests(uuid, uuid, uuid, text, timestamptz, uuid, integer) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.list_customer_portal_contact_change_requests, never a reimplementation.';

revoke execute on function public.list_customer_portal_contact_change_requests(uuid, uuid, uuid, text, timestamptz, uuid, integer) from anon, authenticated, service_role, public;
grant execute on function public.list_customer_portal_contact_change_requests(uuid, uuid, uuid, text, timestamptz, uuid, integer) to authenticated, service_role;

create function public.decide_customer_contact_change_request(p_request_id uuid, p_expected_version integer, p_decision text, p_review_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.customer_portal_contact_change_requests
language sql
security definer
set search_path = app, public, pg_temp
as $wrap$
  select app.decide_customer_contact_change_request(p_request_id, p_expected_version, p_decision, p_review_reason, p_actor_auth_user_id, p_actor_label);
$wrap$;

comment on function public.decide_customer_contact_change_request(uuid, integer, text, text, uuid, text) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.decide_customer_contact_change_request, never a reimplementation.';

revoke execute on function public.decide_customer_contact_change_request(uuid, integer, text, text, uuid, text) from anon, authenticated, service_role, public;
grant execute on function public.decide_customer_contact_change_request(uuid, integer, text, text, uuid, text) to authenticated, service_role;
