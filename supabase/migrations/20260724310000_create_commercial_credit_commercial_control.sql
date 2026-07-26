-- Commercial capability COM-157 (Credit and Commercial Control, CG-S7-COM-016)
-- Commercial credit profile and transaction eligibility controls: a customer's credit
-- limit is requested, routed for governed approval through the already-`VERIFIED`
-- Platform Approval Engine (`PLT-121`/`123`, `app.request_approval`/`app.decide_approval_
-- step` reused unchanged -- Prompt 157 §20 task 2's own literal instruction, unlike
-- `COM-156`'s own deliberately smaller direct-gate choice for contract publish/retire),
-- then held/released as needed. A deterministic, reproducible, append-only check
-- (`app.check_customer_credit`) is the one thing a future Operations/Job Order capability
-- consumes -- it never invents an AR/GL balance, only evaluates this capability's own
-- profile/override state.
--
-- Scope boundaries (disclosed, not silently narrowed, matching every prior checkpoint):
--
-- * **No AR/GL/payment balance of any kind is modeled or invented.** Prompt 157 §24's own
--   business rule ("Phase 2 never invents AR exposure, payment or GL balances") is
--   structural here, not just a comment: `app.credit_check_snapshots` has no exposure/
--   balance/outstanding column at all -- the check evaluates only `approved_limit_amount`
--   (or a valid override) against the one requested transaction amount passed in. Phase 4
--   Finance is the real, disclosed, un-built consumer/producer of any such signal; this
--   check's own stable shape (`app.credit_check_snapshots`'s columns) is the "stable
--   Finance integration contract" Prompt 157 §14 asks this checkpoint to expose.
-- * **Governance routing reuses `PLT-121`'s single, generic `config_type_code='approval'`
--   config object directly** -- the exact same tenant-wide published routing definition
--   `COM-153`'s own `app.submit_quotation` already resolves for quotations, distinguished
--   only by `app.approval_requests.entity_type='credit_profile'` on this capability's own
--   requests. No new config type is registered; a tenant that has already published an
--   approval routing definition for quotations governs credit requests with the same
--   definition. Unlike `COM-153`'s own *conditional* (threshold-crossed) routing, every
--   credit profile request is *unconditionally* routed here -- Prompt 157 §24's "customer
--   creation does not imply credit approval" means credit governance is never skipped,
--   not even below some invented threshold.
-- * **"MFA for privileged approvers" (Prompt 157 §16) reuses `PLT-115`'s own
--   `reauth_confirmed_at`-freshness mechanism** (`app.support_access_sessions.activate_
--   support_access_session`'s own "re-authentication must have completed within the last
--   5 minutes" check, reproduced here verbatim) rather than inventing a second, unproven
--   pattern -- no live MFA/IdP challenge provider exists anywhere in this repository (the
--   same disclosed boundary `PLT-115` itself already carries). Applied to every privileged-
--   approver action this capability adds: deciding a routed request, hold, release, and
--   creating an override.
-- * **Credit limit/override amounts are masked via the already-established `COM:View
--   selling price`** (`COM-147`), not a new permission -- framed as another customer-
--   facing commercial figure, the same reuse choice `COM-156` already made for contract
--   pricing rather than inventing a mismatched new action for a concept the fixed
--   `app.permissions_action_check` 19-action enum has no dedicated slot for (`COM-155`'s
--   own `'View billing'` finding, not re-litigated here).
-- * **One credit profile "in flight" at a time per account.** A fresh request may follow a
--   prior `rejected`/`expired` profile (linked via `supersedes_profile_id`, the same
--   "revise = new row, mark history" pattern `app.vendor_rate_versions`/`app.customer_
--   contracts` already established) but never while `requested`/`active`/`held` already
--   exists -- database-enforced via a partial unique index, not merely an application
--   check.
-- * **Expiry is lazy-flipped on read/check**, the same mechanism `app.quotation_
--   acceptance_tokens` (`COM-154`) already established -- no scheduled job exists anywhere
--   in this repository (`PLT-132`'s Background Job Framework has no live worker).
-- * **Legacy credit data migration is not applicable** -- greenfield, no live environment.
-- * Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration carries its own
--   explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement before
--   its final grants, the standing per-migration convention since `PLT-118`.

create table app.credit_profiles (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  account_id uuid not null references app.accounts (id),
  currency text not null,
  requested_limit_amount numeric(14, 2) not null,
  approved_limit_amount numeric(14, 2),
  status text not null default 'requested',
  effective_from timestamptz,
  effective_to timestamptz,
  hold_reason text,
  rejected_reason text,
  approval_request_id uuid references app.approval_requests (id),
  supersedes_profile_id uuid references app.credit_profiles (id),
  approved_by text,
  approved_at timestamptz,
  owner_user_id uuid references auth.users (id),
  org_unit_id uuid references app.org_units (id),
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint credit_profiles_currency_check check (currency ~ '^[A-Z]{3}$'),
  constraint credit_profiles_requested_amount_check check (requested_limit_amount >= 0),
  constraint credit_profiles_approved_amount_check check (approved_limit_amount is null or approved_limit_amount >= 0),
  constraint credit_profiles_status_check check (status in ('requested', 'active', 'held', 'expired', 'rejected')),
  constraint credit_profiles_validity_check check (effective_to is null or effective_from is null or effective_to > effective_from),
  constraint credit_profiles_not_self_supersede check (supersedes_profile_id is null or supersedes_profile_id <> id),
  constraint credit_profiles_hold_reason_check check (
    (status = 'held' and hold_reason is not null and length(trim(hold_reason)) > 0) or status <> 'held'
  ),
  constraint credit_profiles_rejected_reason_check check (
    (status = 'rejected' and rejected_reason is not null and length(trim(rejected_reason)) > 0) or status <> 'rejected'
  )
);

comment on table app.credit_profiles is
  'COM-157: one row per requested/active credit relationship for one account. Only one row per (tenant_id, account_id) may be in a non-terminal state at a time (credit_profiles_tenant_account_live_unique below) -- a fresh request after rejection/expiry is a new row linked via supersedes_profile_id, never an in-place resurrection of history.';

create unique index credit_profiles_tenant_account_live_unique on app.credit_profiles (tenant_id, account_id) where status in ('requested', 'active', 'held');
create index credit_profiles_tenant_idx on app.credit_profiles (tenant_id);
create index credit_profiles_account_idx on app.credit_profiles (account_id);
create index credit_profiles_tenant_status_idx on app.credit_profiles (tenant_id, status);

-- The alternative flow (Prompt 157 §22): a bounded, reasoned, mandatorily-expiring
-- exception permitting one specific transaction context to exceed the profile's own
-- approved_limit_amount -- never a silent, permanent limit increase (that is the ordinary
-- request/approve flow's own job).
create table app.credit_profile_overrides (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  credit_profile_id uuid not null references app.credit_profiles (id),
  amount numeric(14, 2) not null,
  reason text not null,
  expires_at timestamptz not null,
  approved_by text,
  created_by text,
  created_at timestamptz not null default now(),
  constraint credit_profile_overrides_amount_check check (amount >= 0),
  constraint credit_profile_overrides_reason_check check (length(trim(reason)) > 0),
  constraint credit_profile_overrides_expiry_check check (expires_at > created_at)
);

comment on table app.credit_profile_overrides is
  'COM-157: a bounded, reasoned, always-expiring exception -- app.check_customer_credit uses the single currently-valid (not yet expired) override for a profile, if any, as the effective limit instead of approved_limit_amount, never in addition to it.';

create index credit_profile_overrides_profile_idx on app.credit_profile_overrides (credit_profile_id);

-- The deterministic, reproducible, append-only pre-conversion check (Prompt 157 §20 task
-- 3/§33: "Operations can consume a stable check snapshot in Step 8"). Never rewritten --
-- a later profile/override change produces a new snapshot on its next check, the same
-- no-reentry snapshot discipline every prior Commercial capability follows.
create table app.credit_check_snapshots (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  account_id uuid not null references app.accounts (id),
  credit_profile_id uuid references app.credit_profiles (id),
  profile_status_at_check text,
  profile_record_version integer,
  override_id uuid references app.credit_profile_overrides (id),
  context_type text,
  context_id uuid,
  currency text not null,
  requested_amount numeric(14, 2) not null,
  effective_limit_amount numeric(14, 2),
  outcome text not null,
  checked_by text,
  checked_at timestamptz not null default now(),
  constraint credit_check_snapshots_currency_check check (currency ~ '^[A-Z]{3}$'),
  constraint credit_check_snapshots_requested_amount_check check (requested_amount >= 0),
  constraint credit_check_snapshots_outcome_check check (
    outcome in ('allow', 'blocked_no_profile', 'blocked_not_active', 'blocked_hold', 'blocked_currency_mismatch', 'blocked_limit')
  )
);

comment on table app.credit_check_snapshots is
  'COM-157: the one stable, immutable evidence record a future Operations/Job Order capability pins (Prompt 157 §33) -- effective_limit_amount is null only for blocked_no_profile (nothing to compare against). No exposure/balance/outstanding column exists here or anywhere in this migration (Prompt 157 §24: never invented).';

create index credit_check_snapshots_tenant_idx on app.credit_check_snapshots (tenant_id);
create index credit_check_snapshots_account_idx on app.credit_check_snapshots (account_id);
create index credit_check_snapshots_profile_idx on app.credit_check_snapshots (credit_profile_id);

create function app.touch_credit_profiles_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger credit_profiles_touch_row
  before update on app.credit_profiles
  for each row
  execute function app.touch_credit_profiles_row();

create function app.request_customer_credit_profile(
  p_tenant_id uuid,
  p_account_id uuid,
  p_currency text,
  p_requested_limit_amount numeric,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.credit_profiles
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_account app.accounts;
  v_prior app.credit_profiles;
  v_approval_config_version_id uuid;
  v_request app.approval_requests;
  v_profile app.credit_profiles;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'COM', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_account from app.accounts where id = p_account_id;
  if not found or v_account.tenant_id <> p_tenant_id then
    raise exception 'account_not_found: no account % in tenant %', p_account_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then
    raise exception 'invalid_currency: % is not a 3-letter ISO currency code', p_currency using errcode = 'check_violation';
  end if;

  if p_requested_limit_amount is null or p_requested_limit_amount < 0 then
    raise exception 'invalid_amount: requested_limit_amount must be a non-negative amount' using errcode = 'check_violation';
  end if;

  if exists (select 1 from app.credit_profiles where tenant_id = p_tenant_id and account_id = p_account_id and status in ('requested', 'active', 'held')) then
    raise exception 'credit_profile_already_requested: account % already has a live credit profile', p_account_id using errcode = 'unique_violation';
  end if;

  select id into v_prior from app.credit_profiles where tenant_id = p_tenant_id and account_id = p_account_id order by created_at desc limit 1;

  select cv.id into v_approval_config_version_id
  from app.config_versions cv
  join app.config_objects co on co.id = cv.config_object_id
  where co.config_type_code = 'approval' and co.tenant_id = p_tenant_id and co.scope_level = 'tenant' and cv.status = 'published';

  if v_approval_config_version_id is null then
    raise exception 'approval_definition_not_configured: tenant % has no published approval routing definition', p_tenant_id
      using errcode = 'check_violation';
  end if;

  insert into app.credit_profiles (
    tenant_id, account_id, currency, requested_limit_amount, supersedes_profile_id, owner_user_id, created_by
  ) values (
    p_tenant_id, p_account_id, p_currency, p_requested_limit_amount, v_prior.id, p_actor_auth_user_id, p_actor_label
  )
  returning * into v_profile;

  select * into v_request from app.request_approval(
    v_approval_config_version_id, p_tenant_id, 'credit_profile', v_profile.id, v_profile.id::text, p_actor_auth_user_id, p_actor_label
  );

  update app.credit_profiles
  set approval_request_id = v_request.id, updated_at = now(), record_version = record_version + 1
  where id = v_profile.id
  returning * into v_profile;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'request_customer_credit_profile',
    'app.credit_profiles', v_profile.id, 'success', null, null, to_jsonb(v_profile)
  );

  return v_profile;
end;
$$;

comment on function app.request_customer_credit_profile is
  'COM-157: unconditionally routes through the Platform Approval Engine (PLT-121/123, entity_type=credit_profile) -- unlike app.submit_quotation''s own threshold-conditional routing, credit approval is never skipped. Fails closed (approval_definition_not_configured) if the tenant has never published an approval routing definition, the same fail-closed posture app.submit_quotation already established.';

-- The privileged-approver decision (Prompt 157 §16: MFA -- see migration header for the
-- reused app.support_access_sessions reauth-freshness mechanism this checks explicitly).
create function app.decide_credit_profile_approval_step(
  p_request_step_id uuid,
  p_decision text,
  p_reason text,
  p_reauth_confirmed_at timestamptz,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.credit_profiles
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_step app.approval_request_steps;
  v_request app.approval_requests;
  v_updated_request app.approval_requests;
  v_profile app.credit_profiles;
begin
  if p_reauth_confirmed_at is null or p_reauth_confirmed_at > now() or now() - p_reauth_confirmed_at > interval '5 minutes' then
    raise exception 'reauth_required: re-authentication must have completed within the last 5 minutes'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_step from app.approval_request_steps where id = p_request_step_id;
  if not found then
    raise exception 'approval_step_not_found: no approval request step %', p_request_step_id using errcode = 'no_data_found';
  end if;

  select * into v_request from app.approval_requests where id = v_step.request_id;
  if v_request.entity_type <> 'credit_profile' or v_request.entity_id is null then
    raise exception 'not_a_credit_profile_approval: approval request % is not a credit profile approval', v_request.id
      using errcode = 'check_violation';
  end if;

  perform app.decide_approval_step(p_request_step_id, p_decision, p_actor_auth_user_id, p_actor_label, p_reason);

  select * into v_updated_request from app.approval_requests where id = v_request.id;

  if v_updated_request.status = 'approved' then
    update app.credit_profiles
    set status = 'active', approved_limit_amount = requested_limit_amount, approved_by = p_actor_label, approved_at = now(),
        effective_from = now(), updated_at = now(), record_version = record_version + 1
    where id = v_request.entity_id
    returning * into v_profile;
  elsif v_updated_request.status = 'rejected' then
    update app.credit_profiles
    set status = 'rejected', rejected_reason = coalesce(p_reason, 'Rejected'), updated_at = now(), record_version = record_version + 1
    where id = v_request.entity_id
    returning * into v_profile;
  else
    select * into v_profile from app.credit_profiles where id = v_request.entity_id;
  end if;

  return v_profile;
end;
$$;

comment on function app.decide_credit_profile_approval_step is
  'COM-157: wraps app.decide_approval_step (PLT-123, unchanged) and syncs app.credit_profiles only once the bound request reaches a final state -- mirrors app.decide_quotation_approval_step (COM-153) exactly, plus the reauth-freshness gate Prompt 157 §16 requires for a privileged approver action.';

create function app.hold_credit_profile(
  p_profile_id uuid,
  p_expected_version integer,
  p_reason text,
  p_reauth_confirmed_at timestamptz,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.credit_profiles
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_profile app.credit_profiles;
  v_decision app.rbac_decision;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: holding a credit profile requires a non-empty reason' using errcode = 'not_null_violation';
  end if;

  if p_reauth_confirmed_at is null or p_reauth_confirmed_at > now() or now() - p_reauth_confirmed_at > interval '5 minutes' then
    raise exception 'reauth_required: re-authentication must have completed within the last 5 minutes'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_profile from app.credit_profiles where id = p_profile_id;
  if not found then
    raise exception 'credit_profile_not_found: %', p_profile_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_profile.tenant_id, 'COM', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_profile.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_profile.record_version <> p_expected_version then
    raise exception 'stale_version: credit profile % expected version % but found %', p_profile_id, p_expected_version, v_profile.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_profile.status <> 'active' then
    raise exception 'invalid_transition: credit profile % is % and cannot be held', p_profile_id, v_profile.status
      using errcode = 'check_violation';
  end if;

  update app.credit_profiles
  set status = 'held', hold_reason = p_reason, updated_at = now(), record_version = record_version + 1
  where id = p_profile_id and record_version = p_expected_version
  returning * into v_profile;

  perform app.capture_audit_event(
    v_profile.tenant_id, p_actor_auth_user_id, p_actor_label, 'hold_credit_profile',
    'app.credit_profiles', v_profile.id, 'success', p_reason, null, jsonb_build_object('status', v_profile.status)
  );

  return v_profile;
end;
$$;

create function app.release_credit_profile(
  p_profile_id uuid,
  p_expected_version integer,
  p_reauth_confirmed_at timestamptz,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.credit_profiles
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_profile app.credit_profiles;
  v_decision app.rbac_decision;
begin
  if p_reauth_confirmed_at is null or p_reauth_confirmed_at > now() or now() - p_reauth_confirmed_at > interval '5 minutes' then
    raise exception 'reauth_required: re-authentication must have completed within the last 5 minutes'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_profile from app.credit_profiles where id = p_profile_id;
  if not found then
    raise exception 'credit_profile_not_found: %', p_profile_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_profile.tenant_id, 'COM', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_profile.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_profile.record_version <> p_expected_version then
    raise exception 'stale_version: credit profile % expected version % but found %', p_profile_id, p_expected_version, v_profile.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_profile.status <> 'held' then
    raise exception 'invalid_transition: credit profile % is % and cannot be released', p_profile_id, v_profile.status
      using errcode = 'check_violation';
  end if;

  update app.credit_profiles
  set status = 'active', hold_reason = null, updated_at = now(), record_version = record_version + 1
  where id = p_profile_id and record_version = p_expected_version
  returning * into v_profile;

  perform app.capture_audit_event(
    v_profile.tenant_id, p_actor_auth_user_id, p_actor_label, 'release_credit_profile',
    'app.credit_profiles', v_profile.id, 'success', null, null, jsonb_build_object('status', v_profile.status)
  );

  return v_profile;
end;
$$;

create function app.create_credit_override(
  p_profile_id uuid,
  p_amount numeric,
  p_reason text,
  p_expires_at timestamptz,
  p_reauth_confirmed_at timestamptz,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.credit_profile_overrides
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_profile app.credit_profiles;
  v_decision app.rbac_decision;
  v_override app.credit_profile_overrides;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a credit override requires a non-empty reason' using errcode = 'not_null_violation';
  end if;

  if p_expires_at is null or p_expires_at <= now() then
    raise exception 'invalid_expiry: a credit override must expire in the future' using errcode = 'check_violation';
  end if;

  if p_amount is null or p_amount < 0 then
    raise exception 'invalid_amount: override amount must be non-negative' using errcode = 'check_violation';
  end if;

  if p_reauth_confirmed_at is null or p_reauth_confirmed_at > now() or now() - p_reauth_confirmed_at > interval '5 minutes' then
    raise exception 'reauth_required: re-authentication must have completed within the last 5 minutes'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_profile from app.credit_profiles where id = p_profile_id;
  if not found then
    raise exception 'credit_profile_not_found: %', p_profile_id using errcode = 'no_data_found';
  end if;

  -- Elevated approval (Prompt 157 §22) -- COM:Approve-gated directly, the same governance-
  -- weight tier hold/release use, not a second Approval Engine routing instantiation
  -- within this one capability (see migration header).
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_profile.tenant_id, 'COM', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_profile.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_profile.status not in ('active', 'held') then
    raise exception 'invalid_transition: credit profile % is % and cannot receive an override', p_profile_id, v_profile.status
      using errcode = 'check_violation';
  end if;

  insert into app.credit_profile_overrides (tenant_id, credit_profile_id, amount, reason, expires_at, approved_by, created_by)
  values (v_profile.tenant_id, p_profile_id, p_amount, p_reason, p_expires_at, p_actor_label, p_actor_label)
  returning * into v_override;

  perform app.capture_audit_event(
    v_profile.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_credit_override',
    'app.credit_profile_overrides', v_override.id, 'success', p_reason,
    null, jsonb_build_object('credit_profile_id', p_profile_id, 'amount', p_amount, 'expires_at', p_expires_at)
  );

  return v_override;
end;
$$;

comment on function app.create_credit_override is
  'COM-157: a bounded, reasoned, always-expiring exception on top of an active or held profile -- never a silent permanent limit change (app.request_customer_credit_profile/app.decide_credit_profile_approval_step own that). COM:Approve + reauth-freshness gated (the "elevated approval" Prompt 157 §22 asks for).';

-- The deterministic, reproducible pre-conversion check (Prompt 157 §20 task 3). Lazily
-- flips an expired-but-still-marked-active profile in the same transaction (the same
-- mechanism app.get_quotation_for_customer_decision, COM-154, already established) before
-- evaluating. Never raises for a legitimate business outcome (no profile, held, expired,
-- over limit, currency mismatch) -- only for a structural/programmer error -- so every
-- call produces a real, pinnable snapshot row, per Prompt 157 §33.
create function app.check_customer_credit(
  p_tenant_id uuid,
  p_account_id uuid,
  p_currency text,
  p_requested_amount numeric,
  p_context_type text,
  p_context_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns table (
  id uuid,
  credit_profile_id uuid,
  profile_status_at_check text,
  currency text,
  requested_amount numeric,
  effective_limit_amount numeric,
  amount_masked boolean,
  outcome text,
  checked_at timestamptz
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_profile app.credit_profiles;
  v_override app.credit_profile_overrides;
  v_effective_limit numeric;
  v_outcome text;
  v_snapshot app.credit_check_snapshots;
  v_masked boolean;
begin
  v_masked := not app.has_view_selling_price(p_tenant_id, p_actor_auth_user_id);
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'COM', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then
    raise exception 'invalid_currency: % is not a 3-letter ISO currency code', p_currency using errcode = 'check_violation';
  end if;

  if p_requested_amount is null or p_requested_amount < 0 then
    raise exception 'invalid_amount: requested_amount must be non-negative' using errcode = 'check_violation';
  end if;

  select * into v_profile
  from app.credit_profiles
  where tenant_id = p_tenant_id and account_id = p_account_id and status in ('active', 'held', 'expired')
  order by created_at desc
  limit 1;

  if not found then
    insert into app.credit_check_snapshots (
      tenant_id, account_id, credit_profile_id, profile_status_at_check, profile_record_version,
      context_type, context_id, currency, requested_amount, effective_limit_amount, outcome, checked_by
    ) values (
      p_tenant_id, p_account_id, null, null, null, p_context_type, p_context_id, p_currency, p_requested_amount, null, 'blocked_no_profile', p_actor_label
    )
    returning * into v_snapshot;
    return query select
      v_snapshot.id, v_snapshot.credit_profile_id, v_snapshot.profile_status_at_check,
      case when v_masked then null else v_snapshot.currency end,
      case when v_masked then null else v_snapshot.requested_amount end,
      case when v_masked then null else v_snapshot.effective_limit_amount end,
      v_masked, v_snapshot.outcome, v_snapshot.checked_at;
    return;
  end if;

  if v_profile.status = 'active' and v_profile.effective_to is not null and v_profile.effective_to <= now() then
    update app.credit_profiles cp set status = 'expired', updated_at = now(), record_version = record_version + 1
    where cp.id = v_profile.id
    returning cp.* into v_profile;
  end if;

  if v_profile.status = 'held' then
    v_outcome := 'blocked_hold';
    v_effective_limit := null;
  elsif v_profile.status <> 'active' then
    v_outcome := 'blocked_not_active';
    v_effective_limit := null;
  elsif v_profile.currency <> p_currency then
    v_outcome := 'blocked_currency_mismatch';
    v_effective_limit := null;
  else
    select * into v_override
    from app.credit_profile_overrides o
    where o.credit_profile_id = v_profile.id and o.expires_at > now()
    order by o.created_at desc
    limit 1;

    v_effective_limit := coalesce(v_override.amount, v_profile.approved_limit_amount);
    v_outcome := case when p_requested_amount <= v_effective_limit then 'allow' else 'blocked_limit' end;
  end if;

  insert into app.credit_check_snapshots (
    tenant_id, account_id, credit_profile_id, profile_status_at_check, profile_record_version,
    override_id, context_type, context_id, currency, requested_amount, effective_limit_amount, outcome, checked_by
  ) values (
    p_tenant_id, p_account_id, v_profile.id, v_profile.status, v_profile.record_version,
    v_override.id, p_context_type, p_context_id, p_currency, p_requested_amount, v_effective_limit, v_outcome, p_actor_label
  )
  returning * into v_snapshot;

  return query select
    v_snapshot.id, v_snapshot.credit_profile_id, v_snapshot.profile_status_at_check,
    case when v_masked then null else v_snapshot.currency end,
    case when v_masked then null else v_snapshot.requested_amount end,
    case when v_masked then null else v_snapshot.effective_limit_amount end,
    v_masked, v_snapshot.outcome, v_snapshot.checked_at;
end;
$$;

comment on function app.check_customer_credit is
  'COM-157: the one deterministic, reproducible pre-conversion check. Every outcome (allow/blocked_no_profile/blocked_not_active/blocked_hold/blocked_currency_mismatch/blocked_limit) is a real, structurally distinct value on the persisted snapshot, never a bare boolean -- no exposure/balance figure is ever consulted or invented (Prompt 157 §24). The persisted app.credit_check_snapshots row is always fully unmasked (the source of truth); this function''s own returned row is masked per-caller (COM:View selling price), the same "mask the function''s own output, not just a view" technique app.get_effective_customer_price (COM-156) and app.search_vendor_rates (COM-149) already established -- so an ordinary COM:View holder still gets the real outcome (Prompt 157 §26) without the raw figures.';

-- Field-masked projection (COM:View selling price, reused -- see migration header) of
-- app.credit_profiles -- currency/requested_limit_amount/approved_limit_amount are nulled
-- out for any caller lacking it. Tenant-wide visible (mirrors app.accounts, COM-155).
create view app.credit_profiles_directory
as
select
  p.id,
  p.tenant_id,
  p.account_id,
  case when app.has_view_selling_price(p.tenant_id) then p.currency else null end as currency,
  case when app.has_view_selling_price(p.tenant_id) then p.requested_limit_amount else null end as requested_limit_amount,
  case when app.has_view_selling_price(p.tenant_id) then p.approved_limit_amount else null end as approved_limit_amount,
  not app.has_view_selling_price(p.tenant_id) as amount_masked,
  p.status,
  p.effective_from,
  p.effective_to,
  p.hold_reason,
  p.rejected_reason,
  p.approval_request_id,
  p.supersedes_profile_id,
  p.approved_by,
  p.approved_at,
  p.record_version,
  p.created_by,
  p.created_at,
  p.updated_at
from app.credit_profiles p
where app.has_active_tenant_membership(p.tenant_id) or app.is_supreme_admin();

comment on view app.credit_profiles_directory is
  'COM-157: currency/requested_limit_amount/approved_limit_amount are nulled out (amount_masked=true) for any caller lacking COM:View selling price. authenticated has no direct column-level grant on those three columns on app.credit_profiles itself, forcing every read through this view (same technique app.customer_contract_price_components_directory, COM-156, established).';

-- Same masking discipline applied to the check snapshot's own two money-bearing columns
-- (Prompt 157 §16) -- the outcome itself (allow/blocked_*) is never masked (Prompt 157
-- §26: "Commercial may request/view allowed status"), only the literal figures.
create view app.credit_check_snapshots_directory
as
select
  s.id,
  s.tenant_id,
  s.account_id,
  s.credit_profile_id,
  s.profile_status_at_check,
  s.profile_record_version,
  s.override_id,
  s.context_type,
  s.context_id,
  case when app.has_view_selling_price(s.tenant_id) then s.currency else null end as currency,
  case when app.has_view_selling_price(s.tenant_id) then s.requested_amount else null end as requested_amount,
  case when app.has_view_selling_price(s.tenant_id) then s.effective_limit_amount else null end as effective_limit_amount,
  not app.has_view_selling_price(s.tenant_id) as amount_masked,
  s.outcome,
  s.checked_by,
  s.checked_at
from app.credit_check_snapshots s
where app.has_active_tenant_membership(s.tenant_id) or app.is_supreme_admin();

comment on view app.credit_check_snapshots_directory is
  'COM-157: currency/requested_amount/effective_limit_amount are nulled out (amount_masked=true) for any caller lacking COM:View selling price -- the outcome column itself is never masked, so "allowed to proceed or not" is always visible per Prompt 157 §26.';

-- Same masking discipline applied to the override's own amount column.
create view app.credit_profile_overrides_directory
as
select
  o.id,
  o.tenant_id,
  o.credit_profile_id,
  case when app.has_view_selling_price(o.tenant_id) then o.amount else null end as amount,
  not app.has_view_selling_price(o.tenant_id) as amount_masked,
  o.reason,
  o.expires_at,
  o.approved_by,
  o.created_by,
  o.created_at
from app.credit_profile_overrides o
where app.has_active_tenant_membership(o.tenant_id) or app.is_supreme_admin();

comment on view app.credit_profile_overrides_directory is
  'COM-157: amount is nulled out (amount_masked=true) for any caller lacking COM:View selling price -- authenticated has no direct column-level grant on that column on app.credit_profile_overrides itself, forcing every read through this view.';

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke of
-- PostgreSQL's PUBLIC-execute default, the standing per-migration convention since
-- PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

alter table app.credit_profiles enable row level security;
alter table app.credit_profile_overrides enable row level security;
alter table app.credit_check_snapshots enable row level security;

create policy credit_profiles_select_scoped on app.credit_profiles
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

create policy credit_profile_overrides_select_scoped on app.credit_profile_overrides
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

create policy credit_check_snapshots_select_scoped on app.credit_check_snapshots
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

grant usage on schema app to authenticated;

-- The database guarantee (matches PLT-114/COM-147/148/149/156's own proven technique): a
-- bare column-level REVOKE cannot carve an exception out of a broader table-level GRANT --
-- the table-level grant must be revoked entirely and re-granted on an explicit column list
-- that omits the three amount-bearing columns.
grant select (
  id, tenant_id, account_id, status, effective_from, effective_to, hold_reason, rejected_reason,
  approval_request_id, supersedes_profile_id, approved_by, approved_at, record_version, created_by, created_at, updated_at
) on app.credit_profiles to authenticated;
grant select on app.credit_profiles to service_role;
grant insert, update, delete on app.credit_profiles to service_role;

grant select (id, tenant_id, credit_profile_id, reason, expires_at, approved_by, created_by, created_at) on app.credit_profile_overrides to authenticated;
grant select on app.credit_profile_overrides to service_role;
grant insert, update, delete on app.credit_profile_overrides to service_role;

grant select (
  id, tenant_id, account_id, credit_profile_id, profile_status_at_check, profile_record_version,
  override_id, context_type, context_id, outcome, checked_by, checked_at
) on app.credit_check_snapshots to authenticated;
grant select on app.credit_check_snapshots to service_role;
grant insert, update, delete on app.credit_check_snapshots to service_role;

grant select on app.credit_profiles_directory to authenticated, service_role;
grant select on app.credit_check_snapshots_directory to authenticated, service_role;
grant select on app.credit_profile_overrides_directory to authenticated, service_role;

grant execute on function app.request_customer_credit_profile(uuid, uuid, text, numeric, uuid, text) to authenticated, service_role;
grant execute on function app.decide_credit_profile_approval_step(uuid, text, text, timestamptz, uuid, text) to authenticated, service_role;
grant execute on function app.hold_credit_profile(uuid, integer, text, timestamptz, uuid, text) to authenticated, service_role;
grant execute on function app.release_credit_profile(uuid, integer, timestamptz, uuid, text) to authenticated, service_role;
grant execute on function app.create_credit_override(uuid, numeric, text, timestamptz, timestamptz, uuid, text) to authenticated, service_role;
grant execute on function app.check_customer_credit(uuid, uuid, text, numeric, text, uuid, uuid, text) to authenticated, service_role;
