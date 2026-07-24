-- Commercial capability COM-150 (Margin Calculation, CG-S7-COM-009)
-- Exact, versioned, explainable quotation margin calculation: a selected cost snapshot
-- (app.rate_selections, COM-149) plus selling inputs (sell amount/currency/discount)
-- produce a deterministic, server-computed margin/markup and a policy-driven threshold
-- outcome -- never client-computed money, never silently repriced by a later rule change
-- (Prompt 150 §24: "configuration changes do not silently reprice" an issued calculation).
--
-- Scope boundaries (disclosed, not silently narrowed):
--  1. Money stays PostgreSQL `numeric` end to end (never binary floating point, Prompt
--     150 §24) -- every amount/percentage column below is `numeric`, and every
--     arithmetic step in app.calculate_margin is `numeric` arithmetic with an explicit
--     `round(..., 2)` at each money-producing step (never an implicit cast to `float`).
--  2. Margin rules are tenant-wide only (no per-org-unit rule in this bounded slice,
--     unlike `COM-146`'s own org-unit-scoped `app.sales_plans`) -- exactly one published
--     `app.margin_rule_versions` row per tenant at a time (enforced by a partial unique
--     index), mirroring `app.win_loss_reasons`'s own tenant-wide-only simplicity. A
--     per-org-unit margin policy is a real, larger feature this task does not build.
--  3. FX/multi-currency conversion is out of scope -- `app.calculate_margin` requires the
--     selling currency to exactly match the pinned cost snapshot's own currency and fails
--     closed (`mixed_currency`) otherwise (Prompt 150 §23: "mixed/unknown currency ...
--     fails closed"). A real FX-rate lookup/conversion service is Finance's own future
--     scope, not invented here.
--  4. This is the calculation engine and its own governed override -- not the Quotation
--     Builder itself (`COM-151`, the very next capability, is expected to be the first
--     real consumer that issues a customer-facing quote from a passing/overridden
--     calculation).
--
-- Reuses, not duplicates: `app.rate_selections` (`COM-149`) is the one cost-snapshot
-- source (never a second cost input path); `app.has_view_cost` (`COM-148`) masks
-- cost/margin/markup figures directly, and `app.has_view_selling_price` (`COM-147`) masks
-- the sell-side figures -- no new permission is seeded. `COM:Approve` gates both
-- publishing a margin rule and overriding a below-threshold result, mirroring
-- `COM-146`'s own `app.publish_sales_plan`/`COM-147`'s close-to-won gate exactly (a
-- governance action, not an ordinary edit). Every masked view below is
-- `security_invoker = false` from the start (the `COM-147`/`148`/`149` lesson, not
-- rediscovered a fourth time) with its own explicit `app.can_access_record(...)` row
-- filter through the owning costing request, the same join-through pattern
-- `app.costing_responses_directory`/`app.rate_selections_directory` already established.
--
-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries its own
-- explicit REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC before its final
-- grants, the standing per-migration convention since PLT-118.

create table app.margin_rule_versions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  minimum_margin_pct numeric(5, 2) not null,
  rounding_mode text not null default 'half_up',
  status text not null default 'draft',
  supersedes_version_id uuid references app.margin_rule_versions (id),
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint margin_rule_versions_status_check check (status in ('draft', 'published', 'archived')),
  constraint margin_rule_versions_minimum_check check (minimum_margin_pct >= 0 and minimum_margin_pct <= 100),
  constraint margin_rule_versions_rounding_check check (rounding_mode in ('half_up', 'half_even', 'floor', 'ceiling')),
  constraint margin_rule_versions_not_self_supersede check (supersedes_version_id is null or supersedes_version_id <> id)
);

comment on table app.margin_rule_versions is
  'COM-150: a versioned, tenant-wide minimum-margin-percentage policy. Editing a published rule in place is never allowed -- app.publish_margin_rule_version''s p_supersedes_version_id parameter archives the prior published rule and links the new one, the same "versioned, never edited in place" mechanism app.publish_sales_plan (COM-146) already established.';

create unique index margin_rule_versions_tenant_published_unique on app.margin_rule_versions (tenant_id) where status = 'published';
create index margin_rule_versions_tenant_status_idx on app.margin_rule_versions (tenant_id, status);

create table app.margin_calculations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  costing_request_id uuid not null references app.costing_requests (id),
  rate_selection_id uuid not null references app.rate_selections (id),
  cost_amount numeric(14, 2) not null,
  cost_currency text not null,
  sell_amount numeric(14, 2) not null,
  sell_currency text not null,
  discount_pct numeric(5, 2) not null default 0,
  discount_amount numeric(14, 2) not null,
  net_sell_amount numeric(14, 2) not null,
  margin_amount numeric(14, 2) not null,
  margin_pct numeric(7, 2) not null,
  markup_pct numeric(7, 2),
  rule_version_id uuid not null references app.margin_rule_versions (id),
  minimum_margin_pct_snapshot numeric(5, 2) not null,
  rounding_mode_snapshot text not null,
  threshold_outcome text not null,
  is_overridden boolean not null default false,
  override_reason text,
  override_by text,
  override_at timestamptz,
  is_current boolean not null default true,
  superseded_by_id uuid references app.margin_calculations (id),
  owner_user_id uuid references auth.users (id),
  org_unit_id uuid references app.org_units (id),
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint margin_calculations_cost_currency_check check (cost_currency ~ '^[A-Z]{3}$'),
  constraint margin_calculations_sell_currency_check check (sell_currency ~ '^[A-Z]{3}$'),
  constraint margin_calculations_currency_match_check check (cost_currency = sell_currency),
  constraint margin_calculations_cost_amount_check check (cost_amount >= 0),
  constraint margin_calculations_sell_amount_check check (sell_amount >= 0),
  constraint margin_calculations_discount_pct_check check (discount_pct >= 0 and discount_pct <= 100),
  constraint margin_calculations_threshold_outcome_check check (threshold_outcome in ('pass', 'requires_approval')),
  constraint margin_calculations_override_reason_check check (
    (is_overridden and override_reason is not null and length(trim(override_reason)) > 0)
    or not is_overridden
  )
);

comment on table app.margin_calculations is
  'COM-150: one deterministic margin/markup calculation per (rate_selection, sell inputs), pinning the exact cost snapshot (rate_selection_id, cost_amount/cost_currency copied at calculation time) and the exact margin rule version/minimum/rounding in effect (rule_version_id, minimum_margin_pct_snapshot, rounding_mode_snapshot) -- a later edit to either never silently reprices or re-judges this row (Prompt 150 §24). A recalculation (app.calculate_margin, called again for the same rate_selection_id) creates a NEW row and marks the prior one is_current=false/superseded_by_id -- never edited in place, mirroring app.pipeline_outcomes'' (COM-146) own is_current/superseded_by_id chain.';

create index margin_calculations_request_idx on app.margin_calculations (costing_request_id);
create index margin_calculations_rate_selection_idx on app.margin_calculations (rate_selection_id);
create unique index margin_calculations_current_unique on app.margin_calculations (rate_selection_id) where is_current;

create function app.create_margin_rule_version(
  p_tenant_id uuid,
  p_minimum_margin_pct numeric,
  p_rounding_mode text,
  p_actor_auth_user_id uuid,
  p_created_by text
)
returns app.margin_rule_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_rule app.margin_rule_versions;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'COM', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  insert into app.margin_rule_versions (tenant_id, minimum_margin_pct, rounding_mode, created_by)
  values (p_tenant_id, p_minimum_margin_pct, coalesce(p_rounding_mode, 'half_up'), p_created_by)
  returning * into v_rule;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_created_by, 'create_margin_rule_version',
    'app.margin_rule_versions', v_rule.id, 'success', null, null, to_jsonb(v_rule)
  );

  return v_rule;
end;
$$;

create function app.publish_margin_rule_version(
  p_rule_version_id uuid,
  p_expected_version integer,
  p_supersedes_version_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.margin_rule_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_rule app.margin_rule_versions;
  v_superseded app.margin_rule_versions;
  v_decision app.rbac_decision;
begin
  select * into v_rule from app.margin_rule_versions where id = p_rule_version_id;
  if not found then
    raise exception 'margin_rule_not_found: %', p_rule_version_id using errcode = 'no_data_found';
  end if;

  if v_rule.record_version <> p_expected_version then
    raise exception 'stale_version: margin rule % expected version % but found %', p_rule_version_id, p_expected_version, v_rule.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_rule.status <> 'draft' then
    raise exception 'invalid_transition: margin rule % is % and cannot be published', p_rule_version_id, v_rule.status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_rule.tenant_id, 'COM', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_rule.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_supersedes_version_id is not null then
    select * into v_superseded from app.margin_rule_versions where id = p_supersedes_version_id;
    if not found then
      raise exception 'superseded_rule_not_found: %', p_supersedes_version_id using errcode = 'no_data_found';
    end if;
    if v_superseded.tenant_id <> v_rule.tenant_id then
      raise exception 'invalid_supersede: superseded rule must share the same tenant'
        using errcode = 'check_violation';
    end if;
    if v_superseded.status <> 'published' then
      raise exception 'invalid_supersede: superseded rule % is % (must be published)', p_supersedes_version_id, v_superseded.status
        using errcode = 'check_violation';
    end if;
    update app.margin_rule_versions set status = 'archived', updated_at = now(), record_version = record_version + 1 where id = p_supersedes_version_id;
  end if;

  begin
    update app.margin_rule_versions
    set status = 'published', supersedes_version_id = p_supersedes_version_id, updated_at = now(), record_version = record_version + 1
    where id = p_rule_version_id and record_version = p_expected_version
    returning * into v_rule;
  exception
    when unique_violation then
      raise exception 'active_rule_exists: tenant % already has a published margin rule -- supply p_supersedes_version_id to replace it', v_rule.tenant_id
        using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    v_rule.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_margin_rule_version',
    'app.margin_rule_versions', v_rule.id, 'success', null, null, jsonb_build_object('supersedes_version_id', p_supersedes_version_id)
  );

  return v_rule;
end;
$$;

comment on function app.publish_margin_rule_version is
  'COM-150: draft -> published, archiving p_supersedes_version_id (if supplied) first so at most one published rule ever exists per tenant (enforced by the partial unique index margin_rule_versions_tenant_published_unique) -- mirrors app.publish_sales_plan (COM-146) exactly.';

-- The one deterministic calculation service (Prompt 150 §14: "one shared calculation
-- service used by REST/GraphQL/UI/jobs") -- every money-producing step is explicit
-- `numeric` arithmetic with round(..., 2), never an implicit float cast (Prompt 150 §24).
create function app.calculate_margin(
  p_rate_selection_id uuid,
  p_sell_amount numeric,
  p_sell_currency text,
  p_discount_pct numeric,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.margin_calculations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_selection app.rate_selections;
  v_request app.costing_requests;
  v_decision_edit app.rbac_decision;
  v_rule app.margin_rule_versions;
  v_discount_pct numeric;
  v_discount_amount numeric;
  v_net_sell numeric;
  v_margin_amount numeric;
  v_margin_pct numeric;
  v_markup_pct numeric;
  v_threshold_outcome text;
  v_new_id uuid := gen_random_uuid();
  v_prior_id uuid;
  v_calc app.margin_calculations;
begin
  select * into v_selection from app.rate_selections where id = p_rate_selection_id;
  if not found then
    raise exception 'rate_selection_not_found: %', p_rate_selection_id using errcode = 'no_data_found';
  end if;

  select * into v_request from app.costing_requests where id = v_selection.costing_request_id;

  v_decision_edit := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'COM', 'Edit');
  if not v_decision_edit.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision_edit.reason, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.has_view_cost(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks COM:View cost required to calculate a margin', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_request.tenant_id, v_request.owner_user_id, app.lead_record_scope_org_unit_ids(v_request.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access costing request %', p_actor_auth_user_id, v_request.id
      using errcode = 'insufficient_privilege';
  end if;

  if p_sell_currency is null or p_sell_currency <> v_selection.currency then
    raise exception 'mixed_currency: sell currency % does not match the pinned cost snapshot''s currency %', p_sell_currency, v_selection.currency
      using errcode = 'check_violation';
  end if;

  select * into v_rule from app.margin_rule_versions where tenant_id = v_request.tenant_id and status = 'published';
  if not found then
    raise exception 'no_active_margin_rule: tenant % has no published margin rule -- calculation cannot proceed', v_request.tenant_id
      using errcode = 'check_violation';
  end if;

  v_discount_pct := coalesce(p_discount_pct, 0);
  if v_discount_pct < 0 or v_discount_pct > 100 then
    raise exception 'invalid_discount: discount_pct % is out of the 0..100 range', v_discount_pct
      using errcode = 'check_violation';
  end if;

  v_discount_amount := round(p_sell_amount * v_discount_pct / 100, 2);
  v_net_sell := p_sell_amount - v_discount_amount;
  v_margin_amount := round(v_net_sell - v_selection.amount, 2);
  v_margin_pct := case when v_net_sell = 0 then 0 else round(v_margin_amount / v_net_sell * 100, 2) end;
  v_markup_pct := case when v_selection.amount = 0 then null else round(v_margin_amount / v_selection.amount * 100, 2) end;
  v_threshold_outcome := case when v_margin_pct >= v_rule.minimum_margin_pct then 'pass' else 'requires_approval' end;

  -- Three-step supersede, in this exact order: (1) the prior current row is marked
  -- not-current *before* the new row is inserted, since the partial unique index
  -- margin_calculations_current_unique (rate_selection_id where is_current) would
  -- otherwise reject the new insert while the old row is still is_current=true; (2) the
  -- new row is inserted; (3) only now can the prior row's superseded_by_id (a foreign
  -- key) be set, since it must reference a row that already exists.
  select id into v_prior_id from app.margin_calculations where rate_selection_id = p_rate_selection_id and is_current;

  if v_prior_id is not null then
    update app.margin_calculations
    set is_current = false, updated_at = now(), record_version = record_version + 1
    where id = v_prior_id;
  end if;

  insert into app.margin_calculations (
    id, tenant_id, costing_request_id, rate_selection_id,
    cost_amount, cost_currency, sell_amount, sell_currency,
    discount_pct, discount_amount, net_sell_amount, margin_amount, margin_pct, markup_pct,
    rule_version_id, minimum_margin_pct_snapshot, rounding_mode_snapshot, threshold_outcome,
    owner_user_id, org_unit_id, created_by
  ) values (
    v_new_id, v_request.tenant_id, v_request.id, p_rate_selection_id,
    v_selection.amount, v_selection.currency, p_sell_amount, p_sell_currency,
    v_discount_pct, v_discount_amount, v_net_sell, v_margin_amount, v_margin_pct, v_markup_pct,
    v_rule.id, v_rule.minimum_margin_pct, v_rule.rounding_mode, v_threshold_outcome,
    v_request.owner_user_id, v_request.org_unit_id, p_actor_label
  )
  returning * into v_calc;

  if v_prior_id is not null then
    update app.margin_calculations set superseded_by_id = v_new_id where id = v_prior_id;
  end if;

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'calculate_margin',
    'app.margin_calculations', v_calc.id, 'success', null, null,
    jsonb_build_object('margin_pct', v_margin_pct, 'threshold_outcome', v_threshold_outcome, 'rule_version_id', v_rule.id)
  );

  return v_calc;
end;
$$;

comment on function app.calculate_margin is
  'COM-150: requires both COM:Edit and COM:View cost (mirrors app.submit_costing_response/app.select_vendor_rate''s own dual gate -- computing a margin necessarily reveals cost). Fails closed (mixed_currency) unless p_sell_currency exactly matches the pinned app.rate_selections snapshot''s own currency -- no FX conversion in this bounded slice. Fails closed (no_active_margin_rule) if the tenant has no published margin rule. A repeated call for the same rate_selection_id supersedes the prior current calculation (is_current/superseded_by_id) rather than editing it in place.';

create function app.override_margin_threshold(
  p_margin_calculation_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.margin_calculations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_calc app.margin_calculations;
  v_decision app.rbac_decision;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: overriding a margin threshold requires a non-empty reason'
      using errcode = 'not_null_violation';
  end if;

  select * into v_calc from app.margin_calculations where id = p_margin_calculation_id;
  if not found then
    raise exception 'margin_calculation_not_found: %', p_margin_calculation_id using errcode = 'no_data_found';
  end if;

  if v_calc.record_version <> p_expected_version then
    raise exception 'stale_version: margin calculation % expected version % but found %', p_margin_calculation_id, p_expected_version, v_calc.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_calc.threshold_outcome <> 'requires_approval' or v_calc.is_overridden then
    raise exception 'invalid_transition: margin calculation % is not an un-overridden requires_approval result', p_margin_calculation_id
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_calc.tenant_id, 'COM', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_calc.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_calc.tenant_id, v_calc.owner_user_id, app.lead_record_scope_org_unit_ids(v_calc.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access margin calculation %', p_actor_auth_user_id, p_margin_calculation_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.margin_calculations
  set is_overridden = true, override_reason = p_reason, override_by = p_actor_label, override_at = now(), updated_at = now(), record_version = record_version + 1
  where id = p_margin_calculation_id and record_version = p_expected_version
  returning * into v_calc;

  perform app.capture_audit_event(
    v_calc.tenant_id, p_actor_auth_user_id, p_actor_label, 'override_margin_threshold',
    'app.margin_calculations', v_calc.id, 'success', p_reason, null, jsonb_build_object('threshold_outcome', v_calc.threshold_outcome)
  );

  return v_calc;
end;
$$;

comment on function app.override_margin_threshold is
  'COM-150: COM:Approve-gated (a governance action, mirrors app.publish_sales_plan/the close-to-won gate), requires a non-empty reason, and only valid against an un-overridden requires_approval result -- never changes the source cost/margin figures themselves (Prompt 150 §22: "without changing source cost").';

-- Field-masked projection of app.margin_calculations (COM-150, mirrors
-- app.costing_responses_directory/app.rate_selections_directory) -- security_invoker=false
-- from the start. Two independent masking dimensions: sell-side figures need
-- COM:View selling price (COM-147); cost/margin/markup figures need COM:View cost
-- (COM-148) -- reused directly, no new permission seeded.
create view app.margin_calculations_directory
as
select
  c.id,
  c.tenant_id,
  c.costing_request_id,
  c.rate_selection_id,
  case when app.has_view_cost(c.tenant_id) then c.cost_amount else null end as cost_amount,
  c.cost_currency,
  case when app.has_view_selling_price(c.tenant_id) then c.sell_amount else null end as sell_amount,
  c.sell_currency,
  case when app.has_view_selling_price(c.tenant_id) then c.discount_pct else null end as discount_pct,
  case when app.has_view_cost(c.tenant_id) then c.discount_amount else null end as discount_amount,
  case when app.has_view_selling_price(c.tenant_id) then c.net_sell_amount else null end as net_sell_amount,
  case when app.has_view_cost(c.tenant_id) then c.margin_amount else null end as margin_amount,
  case when app.has_view_cost(c.tenant_id) then c.margin_pct else null end as margin_pct,
  case when app.has_view_cost(c.tenant_id) then c.markup_pct else null end as markup_pct,
  not app.has_view_cost(c.tenant_id) as cost_masked,
  not app.has_view_selling_price(c.tenant_id) as sell_masked,
  c.rule_version_id,
  c.minimum_margin_pct_snapshot,
  c.rounding_mode_snapshot,
  c.threshold_outcome,
  c.is_overridden,
  c.override_reason,
  c.override_by,
  c.override_at,
  c.is_current,
  c.superseded_by_id,
  c.record_version,
  c.created_by,
  c.created_at,
  c.updated_at
from app.margin_calculations c
join app.costing_requests cr on cr.id = c.costing_request_id
where app.can_access_record(auth.uid(), cr.tenant_id, cr.owner_user_id, app.lead_record_scope_org_unit_ids(cr.org_unit_id), null);

comment on view app.margin_calculations_directory is
  'COM-150: field-masked projection of app.margin_calculations -- cost/margin/markup figures are nulled out (cost_masked=true) without COM:View cost, and sell/discount/net-sell figures are nulled out (sell_masked=true) without COM:View selling price. threshold_outcome/override state stay visible to anyone with record access (governance status, not a money figure).';

revoke execute on all functions in schema app from public;

alter table app.margin_rule_versions enable row level security;
alter table app.margin_calculations enable row level security;

-- Tenant-wide reference/policy data (mirrors app.win_loss_reasons/app.master_records'
-- own RLS shape) -- a minimum-margin-percentage policy is not itself a specific deal's
-- financial figure, so no field masking is applied here.
create policy margin_rule_versions_select_scoped on app.margin_rule_versions
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

create policy margin_calculations_select_scoped on app.margin_calculations
  for select to authenticated
  using (
    exists (
      select 1 from app.costing_requests cr
      where cr.id = margin_calculations.costing_request_id
        and app.can_access_record(auth.uid(), cr.tenant_id, cr.owner_user_id, app.lead_record_scope_org_unit_ids(cr.org_unit_id), null)
    )
  );

grant usage on schema app to authenticated;
grant select on app.margin_rule_versions to authenticated, service_role;

-- The database guarantee (matches PLT-114/COM-147/148/149's own proven technique): a bare
-- column-level REVOKE cannot carve an exception out of a broader table-level GRANT -- the
-- table-level grant must be revoked entirely and re-granted on an explicit column list
-- that omits every cost/sell/discount/margin/markup column.
grant select (
  id, tenant_id, costing_request_id, rate_selection_id, cost_currency, sell_currency,
  rule_version_id, minimum_margin_pct_snapshot, rounding_mode_snapshot, threshold_outcome,
  is_overridden, override_reason, override_by, override_at, is_current, superseded_by_id,
  owner_user_id, org_unit_id, record_version, created_by, created_at, updated_at
) on app.margin_calculations to authenticated;
grant select on app.margin_calculations to service_role;
grant select on app.margin_calculations_directory to authenticated, service_role;

grant execute on function app.create_margin_rule_version(uuid, numeric, text, uuid, text) to authenticated, service_role;
grant execute on function app.publish_margin_rule_version(uuid, integer, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.calculate_margin(uuid, numeric, text, numeric, uuid, text) to authenticated, service_role;
grant execute on function app.override_margin_threshold(uuid, integer, text, uuid, text) to authenticated, service_role;
