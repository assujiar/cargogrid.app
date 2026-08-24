-- HDN-373 (Step 15, Prompt 373, RLS and RBAC Audit, `CG-S15-HDN-005`) — closes 16 of the
-- `HDN-BLK-014`/`ISS-2026-179` candidates that `HDN-372` registered and handed to this
-- checkpoint rather than silently bundling into its own bounded-repair scope.
--
-- The defect is one class, already fixed three times in this repository under three
-- different names: a `SECURITY DEFINER` function granted `EXECUTE` directly to
-- `authenticated` takes a claimed-actor parameter (`p_actor_auth_user_id`, or
-- `p_auth_user_id` for `app.current_support_session`), evaluates authority/scope/
-- readiness against THAT uuid, and never cross-checks it against `auth.uid()`, the only
-- identity the session actually proved. Any authenticated session may therefore pass any
-- other identity's uuid and have the function answer as that identity — `ATW-031`
-- (`ISS-2026-017`, fixed at the `app.evaluate_permission` choke point for 416
-- functions), `ATW-032` (`ISS-2026-032`, the standalone authority surface), and
-- `HDN-372` (`ISS-2026-164`, 13 functions across
-- `20260810000000_harden_tenant_isolation_actor_identity_gaps.sql` and its round-2
-- successor) each closed one slice of exactly this. `SECURITY DEFINER` is what makes it
-- reachable: the function bypasses RLS, so a forged actor is precisely what lets a
-- caller read (or learn the existence/shape of) what its own session could not.
--
-- These 16 were judged safe to fix this way — with the assert INSIDE the function, at
-- its own root — because every one of them is self-referential: its actor parameter
-- names the caller itself, and at every internal call site across the whole
-- `supabase/migrations/` tree that parameter is passed straight through, unmutated, from
-- the calling function's own actor parameter. None is used anywhere as a
-- general-purpose "evaluate a THIRD PARTY's status" primitive, so binding the parameter
-- to the session identity cannot break a legitimate caller. That is exactly the
-- distinction that keeps `app.has_active_tenant_membership`, `app.can_access_record` and
-- `app.is_supreme_admin` OUT of this migration: those genuinely are called cross-actor
-- elsewhere in this codebase (asking about an identity other than the caller is their
-- job), so the identical assert would be a behavior change, not a repair. They stay open
-- under `HDN-BLK-014` with their own disposition — deliberately excluded, not
-- overlooked.
--
-- Full per-candidate disposition for `HDN-BLK-014`/`ISS-2026-179` (which of the
-- registered candidates are fixed here, which are excluded, and why) lives in
-- `docs/build-log/full-system-hardening/HDN-373.md` §6.
--
-- Each function below is reproduced from its own current EFFECTIVE definition —
-- byte-identical signature, return type, language, volatility, security mode,
-- `search_path` setting and body — with exactly one line inserted as the first statement
-- of the body. Three of the sixteen had been redefined after their original migration,
-- and the LATER definition is the one reproduced here:
--   * `app.evaluate_quotation_approval_requirement` — the `COM-163` widened two-argument
--     form from `20260726090000_create_commercial_hardening.sql` (which dropped
--     `COM-153`'s original single-argument form), not the original.
--   * `app.get_quotation_submission_readiness` — the `COM-153` `not_current_version`
--     form from `20260724240000_create_commercial_quotation_versioning.sql`.
--   * `app.get_job_shipment_allocation_balance` — the `ATW-032` deterministic-basis-tie
--     form from `20260730530000_harden_operations_inventory_tracking_record_scope.sql`.
--
-- One deliberate, disclosed variation from the `HDN-372` fix shape: 15 of the 16 are
-- `LANGUAGE plpgsql` and take the standard
-- `perform app.assert_actor_is_session_identity(...)` as their first statement.
-- `app.current_support_session` (`PLT-115`) is `LANGUAGE sql`, which has no `PERFORM`
-- and no `BEGIN` block, so its assert is written as the equivalent
-- `select app.assert_actor_is_session_identity(p_auth_user_id);` — a non-final statement
-- in the SQL body, executed before the lookup, its result discarded. Keeping it
-- `LANGUAGE sql` — rather than converting it to `plpgsql` just to gain a `BEGIN` block —
-- holds this migration to its own rule: language, volatility, security mode, signature
-- and result semantics are unchanged for all 16. Verified empirically on a scratch
-- database against a byte-identical pre-fix control clone of this function: with no open
-- support session for the actor (the overwhelming majority case, and the one
-- `app.capture_audit_event`'s own `IAE-037` support-grant defaulting reads), the pre-fix
-- and post-fix forms are indistinguishable — both yield the same all-NULL
-- `app.support_access_sessions` value when called as a scalar, and the same single
-- all-NULL row and `FOUND` when called as `select * into v_session from
-- app.current_support_session(...)`.
--
-- `app.assert_actor_is_session_identity` (`ATW-031`,
-- `20260730440000_harden_actor_identity_session_crosscheck.sql`) is a no-op when
-- `auth.uid()` is NULL — service_role, superuser, and the `scripts/db-tests/` harness —
-- so it engages only for a genuine authenticated session, the one principal that could
-- impersonate. Additive migration: no table, policy, grant, signature or call site
-- changes; the trailing grants below reproduce each function's currently-live grantee
-- list exactly, neither widened nor narrowed.

create or replace function app.find_duplicate_accounts(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_legal_name text,
  p_tax_id text
)
returns setof app.accounts
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_fingerprint text;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_fingerprint := app.compute_prospect_duplicate_fingerprint(
    p_tenant_id, app.normalize_prospect_identifier(p_legal_name), app.normalize_prospect_identifier(p_tax_id)
  );

  return query
    select * from app.accounts
    where tenant_id = p_tenant_id
      and duplicate_fingerprint = v_fingerprint
      and status <> 'merged'
    order by created_at;
end;
$$;

create or replace function app.find_duplicate_contacts(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_email text,
  p_phone text
)
returns setof app.contacts
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_fingerprint text;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_fingerprint := app.compute_contact_duplicate_fingerprint(
    p_tenant_id, app.normalize_lead_email(p_email), app.normalize_lead_phone(p_phone)
  );

  return query
    select * from app.contacts
    where tenant_id = p_tenant_id
      and duplicate_fingerprint = v_fingerprint
      and status = 'active'
    order by created_at;
end;
$$;

create or replace function app.find_duplicate_leads(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_email text,
  p_phone text,
  p_company_name text
)
returns setof app.leads
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_fingerprint text;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_fingerprint := app.compute_lead_duplicate_fingerprint(
    p_tenant_id, app.normalize_lead_email(p_email), app.normalize_lead_phone(p_phone), p_company_name
  );

  return query
    select * from app.leads
    where tenant_id = p_tenant_id
      and duplicate_fingerprint = v_fingerprint
      and status <> 'merged'
    order by created_at;
end;
$$;

create or replace function app.find_duplicate_prospects(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_legal_name text,
  p_tax_id text
)
returns setof app.prospects
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_fingerprint text;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_fingerprint := app.compute_prospect_duplicate_fingerprint(
    p_tenant_id, app.normalize_prospect_identifier(p_legal_name), app.normalize_prospect_identifier(p_tax_id)
  );

  return query
    select * from app.prospects
    where tenant_id = p_tenant_id
      and duplicate_fingerprint = v_fingerprint
      and status <> 'merged'
    order by created_at;
end;
$$;

create or replace function app.find_existing_accounts_for_lead(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_lead_id uuid
)
returns setof app.accounts
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_lead app.leads;
  v_normalized_name text;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_lead from app.leads where id = p_lead_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'lead_not_found: no lead % in tenant %', p_lead_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  v_normalized_name := app.normalize_prospect_identifier(v_lead.company_name);
  if v_normalized_name is null then
    return;
  end if;

  return query
    select * from app.accounts
    where tenant_id = p_tenant_id
      and status <> 'merged'
      and normalized_legal_name = v_normalized_name
    order by created_at;
end;
$$;

create or replace function app.find_existing_accounts_for_prospect(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_prospect_id uuid
)
returns setof app.accounts
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_prospect app.prospects;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_prospect from app.prospects where id = p_prospect_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'prospect_not_found: no prospect % in tenant %', p_prospect_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  return query select * from app.find_duplicate_accounts(p_tenant_id, p_actor_auth_user_id, v_prospect.legal_name, v_prospect.tax_id);
end;
$$;

create or replace function app.resolve_warehouse_location_by_barcode(p_tenant_id uuid, p_barcode text, p_actor_auth_user_id uuid)
returns app.warehouse_locations
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_location app.warehouse_locations;
  v_warehouse app.warehouses;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if p_barcode is null or length(trim(p_barcode)) = 0 then
    raise exception 'invalid_barcode: barcode is required' using errcode = 'check_violation';
  end if;
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % has no active membership in tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_location from app.warehouse_locations where tenant_id = p_tenant_id and barcode = p_barcode;
  if not found then
    raise exception 'location_not_found: no location with barcode %', p_barcode using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_location.warehouse_id;

  if not app.can_access_record(p_actor_auth_user_id, p_tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot view location %', p_actor_auth_user_id, v_location.id using errcode = 'insufficient_privilege';
  end if;

  return v_location;
end;
$$;

create or replace function app.compute_sales_metric_count(
  p_tenant_id uuid,
  p_metric_type text,
  p_target_org_unit_id uuid,
  p_target_owner_user_id uuid,
  p_period_start date,
  p_period_end date,
  p_actor_auth_user_id uuid
)
returns integer
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_scope_org_unit_ids uuid[];
  v_count integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  v_scope_org_unit_ids := app.pipeline_scope_org_unit_ids(p_target_org_unit_id);

  case p_metric_type
    when 'leads_captured' then
      select count(*) into v_count
      from app.leads l
      where l.tenant_id = p_tenant_id
        and l.org_unit_id = any(v_scope_org_unit_ids)
        and (p_target_owner_user_id is null or l.owner_user_id = p_target_owner_user_id)
        and l.created_at::date between p_period_start and p_period_end
        and app.can_access_record(p_actor_auth_user_id, l.tenant_id, l.owner_user_id, app.lead_record_scope_org_unit_ids(l.org_unit_id), null);
    when 'leads_qualified' then
      select count(*) into v_count
      from app.leads l
      where l.tenant_id = p_tenant_id
        and l.org_unit_id = any(v_scope_org_unit_ids)
        and (p_target_owner_user_id is null or l.owner_user_id = p_target_owner_user_id)
        and l.qualified_at is not null
        and l.qualified_at::date between p_period_start and p_period_end
        and app.can_access_record(p_actor_auth_user_id, l.tenant_id, l.owner_user_id, app.lead_record_scope_org_unit_ids(l.org_unit_id), null);
    when 'prospects_created' then
      select count(*) into v_count
      from app.prospects p
      where p.tenant_id = p_tenant_id
        and p.org_unit_id = any(v_scope_org_unit_ids)
        and (p_target_owner_user_id is null or p.owner_user_id = p_target_owner_user_id)
        and p.created_at::date between p_period_start and p_period_end
        and app.can_access_record(p_actor_auth_user_id, p.tenant_id, p.owner_user_id, app.lead_record_scope_org_unit_ids(p.org_unit_id), null);
    when 'prospects_disqualified' then
      select count(*) into v_count
      from app.prospects p
      where p.tenant_id = p_tenant_id
        and p.org_unit_id = any(v_scope_org_unit_ids)
        and (p_target_owner_user_id is null or p.owner_user_id = p_target_owner_user_id)
        and p.disqualified_at is not null
        and p.disqualified_at::date between p_period_start and p_period_end
        and app.can_access_record(p_actor_auth_user_id, p.tenant_id, p.owner_user_id, app.lead_record_scope_org_unit_ids(p.org_unit_id), null);
    else
      raise exception 'unknown_metric_type: %', p_metric_type using errcode = 'check_violation';
  end case;

  return coalesce(v_count, 0);
end;
$$;

create or replace function app.get_sales_target_actual(
  p_sales_target_id uuid,
  p_actor_auth_user_id uuid
)
returns integer
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_target app.sales_targets;
  v_plan app.sales_plans;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_target from app.sales_targets where id = p_sales_target_id;
  if not found then
    raise exception 'sales_target_not_found: %', p_sales_target_id using errcode = 'no_data_found';
  end if;

  select * into v_plan from app.sales_plans where id = v_target.sales_plan_id;

  if not app.can_access_record(p_actor_auth_user_id, v_target.tenant_id, v_target.owner_user_id, app.lead_record_scope_org_unit_ids(v_target.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access sales target %', p_actor_auth_user_id, p_sales_target_id
      using errcode = 'insufficient_privilege';
  end if;

  return app.compute_sales_metric_count(
    v_target.tenant_id, v_target.metric_type, v_target.org_unit_id, v_target.owner_user_id,
    v_plan.period_start, v_plan.period_end, p_actor_auth_user_id
  );
end;
$$;

create or replace function app.evaluate_quotation_approval_requirement(
  p_quotation_id uuid,
  p_actor_auth_user_id uuid default auth.uid()
)
returns table (required boolean, reasons text[], rule_version_id uuid)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_quotation app.quotations;
  v_rule app.quotation_approval_rules;
  v_reasons text[] := array[]::text[];
  v_min_line_margin numeric;
  v_effective_discount_pct numeric;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_quotation from app.quotations where id = p_quotation_id;
  if not found then
    raise exception 'quotation_not_found: %', p_quotation_id using errcode = 'no_data_found';
  end if;

  -- COM-163 hardening: the one check this function's own sibling,
  -- app.get_quotation_submission_readiness (COM-152/153), already performs -- closes the
  -- cross-tenant business-intelligence disclosure this migration's own header describes.
  if not app.can_access_record(p_actor_auth_user_id, v_quotation.tenant_id, v_quotation.owner_user_id, app.lead_record_scope_org_unit_ids(v_quotation.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access quotation %', p_actor_auth_user_id, p_quotation_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_rule from app.quotation_approval_rules where tenant_id = v_quotation.tenant_id and status = 'published';
  if not found then
    return query select false, array[]::text[], null::uuid;
    return;
  end if;

  if v_rule.min_margin_pct is not null then
    select min(margin_pct_snapshot) into v_min_line_margin
    from app.quotation_lines
    where quotation_id = p_quotation_id and margin_pct_snapshot is not null;
    if v_min_line_margin is not null and v_min_line_margin < v_rule.min_margin_pct then
      v_reasons := array_append(v_reasons, 'below_minimum_margin');
    end if;
  end if;

  if v_rule.max_discount_pct is not null and v_quotation.subtotal_amount > 0 then
    v_effective_discount_pct := (v_quotation.discount_amount / v_quotation.subtotal_amount) * 100;
    if v_effective_discount_pct > v_rule.max_discount_pct then
      v_reasons := array_append(v_reasons, 'discount_exceeds_maximum');
    end if;
  end if;

  if v_rule.min_value_amount is not null and v_quotation.total_amount >= v_rule.min_value_amount then
    v_reasons := array_append(v_reasons, 'value_meets_threshold');
  end if;

  return query select (array_length(v_reasons, 1) is not null), v_reasons, v_rule.id;
end;
$$;

create or replace function app.get_quotation_submission_readiness(p_quotation_id uuid, p_actor_auth_user_id uuid default auth.uid())
returns table (ready boolean, blocking_reasons text[])
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_quotation app.quotations;
  v_opportunity app.opportunities;
  v_reasons text[] := array[]::text[];
  v_line_count integer;
  v_stale_line_count integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_quotation from app.quotations where id = p_quotation_id;
  if not found then
    raise exception 'quotation_not_found: %', p_quotation_id using errcode = 'no_data_found';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_quotation.tenant_id, v_quotation.owner_user_id, app.lead_record_scope_org_unit_ids(v_quotation.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access quotation %', p_actor_auth_user_id, p_quotation_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_opportunity from app.opportunities where id = v_quotation.opportunity_id;

  if not v_quotation.is_current then
    v_reasons := array_append(v_reasons, 'not_current_version');
  end if;

  select count(*) into v_line_count from app.quotation_lines where quotation_id = p_quotation_id;
  if v_line_count = 0 then
    v_reasons := array_append(v_reasons, 'no_lines');
  end if;

  if v_quotation.total_amount <= 0 then
    v_reasons := array_append(v_reasons, 'zero_total');
  end if;

  if v_quotation.contact_id is null then
    v_reasons := array_append(v_reasons, 'contact_required');
  end if;

  if v_quotation.validity_to <= now() then
    v_reasons := array_append(v_reasons, 'validity_expired');
  end if;

  if v_opportunity.record_version <> v_quotation.source_opportunity_version then
    v_reasons := array_append(v_reasons, 'stale_opportunity');
  end if;

  select count(*) into v_stale_line_count
  from app.quotation_lines ql
  join app.margin_calculations mc on mc.id = ql.margin_calculation_id
  where ql.quotation_id = p_quotation_id and not mc.is_current;
  if v_stale_line_count > 0 then
    v_reasons := array_append(v_reasons, 'stale_rate_or_cost');
  end if;

  if v_quotation.status <> 'draft' then
    v_reasons := array_append(v_reasons, 'not_a_draft');
  end if;

  return query select (array_length(v_reasons, 1) is null), v_reasons;
end;
$$;

create or replace function app.get_account_conversion_readiness(p_quotation_id uuid, p_actor_auth_user_id uuid default auth.uid())
returns table (ready boolean, blocking_reasons text[], duplicate_candidate_ids uuid[])
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_quotation app.quotations;
  v_prospect app.prospects;
  v_reasons text[] := array[]::text[];
  v_candidates uuid[] := array[]::uuid[];
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_quotation from app.quotations where id = p_quotation_id;
  if not found then
    raise exception 'quotation_not_found: %', p_quotation_id using errcode = 'no_data_found';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_quotation.tenant_id, v_quotation.owner_user_id, app.lead_record_scope_org_unit_ids(v_quotation.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access quotation %', p_actor_auth_user_id, p_quotation_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_prospect from app.prospects where id = v_quotation.prospect_id;

  if v_quotation.customer_decision is distinct from 'accepted' then
    v_reasons := array_append(v_reasons, 'quotation_not_accepted');
  end if;

  if exists (select 1 from app.account_conversions c where c.quotation_id = p_quotation_id) then
    v_reasons := array_append(v_reasons, 'already_converted');
  end if;

  if v_prospect.legal_name is null or length(trim(v_prospect.legal_name)) = 0 then
    v_reasons := array_append(v_reasons, 'missing_legal_name');
  end if;

  if v_quotation.customer_decision = 'accepted' and v_prospect.legal_name is not null then
    select coalesce(array_agg(a.id), array[]::uuid[]) into v_candidates
    from app.find_duplicate_accounts(v_quotation.tenant_id, p_actor_auth_user_id, v_prospect.legal_name, v_prospect.tax_id) a;
  end if;

  return query select (array_length(v_reasons, 1) is null), v_reasons, v_candidates;
end;
$$;

create or replace function app.get_job_order_conversion_readiness(
  p_source_handoff_id uuid,
  p_actor_auth_user_id uuid default auth.uid()
)
returns table (ready boolean, blocking_reasons text[], existing_job_order_id uuid)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_handoff app.job_order_handoffs;
  v_reasons text[] := array[]::text[];
  v_existing uuid;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_handoff from app.job_order_handoffs where id = p_source_handoff_id;
  if not found then
    raise exception 'handoff_not_found: %', p_source_handoff_id using errcode = 'no_data_found';
  end if;

  if not app.has_active_tenant_membership(v_handoff.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, v_handoff.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select id into v_existing from app.job_orders where tenant_id = v_handoff.tenant_id and source_handoff_id = p_source_handoff_id;
  if v_existing is not null then
    v_reasons := array_append(v_reasons, 'already_converted');
  end if;

  if v_handoff.payload is null then
    v_reasons := array_append(v_reasons, 'handoff_payload_unavailable');
  end if;

  return query select (array_length(v_reasons, 1) is null), v_reasons, v_existing;
end;
$$;

CREATE OR REPLACE FUNCTION app.get_job_shipment_allocation_balance(p_job_order_id uuid, p_actor_auth_user_id uuid DEFAULT auth.uid())
 RETURNS TABLE(basis_quantity numeric, basis_weight_kg numeric, basis_volume_cbm numeric, allocated_quantity numeric, allocated_weight_kg numeric, allocated_volume_cbm numeric, remaining_quantity numeric, remaining_weight_kg numeric, remaining_volume_cbm numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_job app.job_orders;
  v_basis_qty numeric;
  v_basis_weight numeric;
  v_basis_volume numeric;
  v_alloc_qty numeric;
  v_alloc_weight numeric;
  v_alloc_volume numeric;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_job from app.job_orders where id = p_job_order_id;
  if not found then
    raise exception 'job_order_not_found: %', p_job_order_id using errcode = 'no_data_found';
  end if;

  if not app.has_active_tenant_membership(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- The basis is declared once, on the very first Shipment Order ever created for
  -- this Job Order -- looked up across every row regardless of its own current
  -- status, since a later cancellation of that first row must never erase the
  -- basis it already declared.
  select so.basis_quantity, so.basis_weight_kg, so.basis_volume_cbm
    into v_basis_qty, v_basis_weight, v_basis_volume
  from app.shipment_orders so
  where so.job_order_id = p_job_order_id
  -- ATW-032 (ISS-2026-034): created_at alone is not a total order (it is the transaction
  -- timestamp), so "the very first Shipment Order ever created" was ambiguous for any two
  -- rows sharing it. so.id breaks the tie deterministically.
  order by so.created_at asc, so.id asc
  limit 1;

  select coalesce(sum(so.allocated_quantity), 0), coalesce(sum(so.allocated_weight_kg), 0), coalesce(sum(so.allocated_volume_cbm), 0)
    into v_alloc_qty, v_alloc_weight, v_alloc_volume
  from app.shipment_orders so
  where so.job_order_id = p_job_order_id and so.status <> 'cancelled';

  return query select
    v_basis_qty, v_basis_weight, v_basis_volume,
    v_alloc_qty, v_alloc_weight, v_alloc_volume,
    case when v_basis_qty is null then null else v_basis_qty - v_alloc_qty end,
    case when v_basis_weight is null then null else v_basis_weight - v_alloc_weight end,
    case when v_basis_volume is null then null else v_basis_volume - v_alloc_volume end;
end;
$function$
;

create or replace function app.get_opportunity_costing_readiness(
  p_opportunity_id uuid,
  p_actor_auth_user_id uuid
)
returns table (ready boolean, missing text[])
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_opportunity app.opportunities;
  v_missing text[] := '{}';
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_opportunity from app.opportunities where id = p_opportunity_id;
  if not found then
    raise exception 'opportunity_not_found: %', p_opportunity_id using errcode = 'no_data_found';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_opportunity.tenant_id, v_opportunity.owner_user_id, app.lead_record_scope_org_unit_ids(v_opportunity.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access opportunity %', p_actor_auth_user_id, p_opportunity_id
      using errcode = 'insufficient_privilege';
  end if;

  if coalesce(v_opportunity.requirements ->> 'service_type', '') = '' then
    v_missing := v_missing || 'service_type'::text;
  end if;
  if coalesce(v_opportunity.requirements ->> 'cargo_description', '') = '' then
    v_missing := v_missing || 'cargo_description'::text;
  end if;
  if coalesce(v_opportunity.requirements ->> 'origin', '') = '' then
    v_missing := v_missing || 'origin'::text;
  end if;
  if coalesce(v_opportunity.requirements ->> 'destination', '') = '' then
    v_missing := v_missing || 'destination'::text;
  end if;
  if coalesce(v_opportunity.requirements ->> 'target_ready_date', '') = '' then
    v_missing := v_missing || 'target_ready_date'::text;
  end if;

  return query select (array_length(v_missing, 1) is null), v_missing;
end;
$$;

create or replace function app.current_support_session(p_tenant_id uuid, p_auth_user_id uuid default auth.uid())
returns app.support_access_sessions
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select app.assert_actor_is_session_identity(p_auth_user_id);
  select s.*
  from app.support_access_sessions s
  join app.support_access_grants g on g.id = s.grant_id
  where s.tenant_id = p_tenant_id
    and s.grantee_auth_user_id = p_auth_user_id
    and s.ended_at is null
    and g.status = 'approved'
    and g.revoked_at is null
    and g.expires_at > now()
  limit 1;
$$;

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke of
-- PostgreSQL's PUBLIC-execute default, the standing per-migration convention since
-- PLT-118, applied here before any role-specific grant. Every grant below reproduces the
-- function's own currently-live grant statement verbatim -- same signature, same
-- grantees.
revoke execute on all functions in schema app from public;

grant execute on function app.find_duplicate_accounts(uuid, uuid, text, text) to authenticated, service_role;
grant execute on function app.find_duplicate_contacts(uuid, uuid, text, text) to authenticated, service_role;
grant execute on function app.find_duplicate_leads(uuid, uuid, text, text, text) to authenticated, service_role;
grant execute on function app.find_duplicate_prospects(uuid, uuid, text, text) to authenticated, service_role;
grant execute on function app.find_existing_accounts_for_lead(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.find_existing_accounts_for_prospect(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.resolve_warehouse_location_by_barcode(uuid, text, uuid) to authenticated, service_role;
grant execute on function app.compute_sales_metric_count(uuid, text, uuid, uuid, date, date, uuid) to authenticated, service_role;
grant execute on function app.get_sales_target_actual(uuid, uuid) to authenticated, service_role;
grant execute on function app.evaluate_quotation_approval_requirement(uuid, uuid) to authenticated, service_role;
grant execute on function app.get_quotation_submission_readiness(uuid, uuid) to authenticated, service_role;
grant execute on function app.get_account_conversion_readiness(uuid, uuid) to authenticated, service_role;
grant execute on function app.get_job_order_conversion_readiness(uuid, uuid) to authenticated, service_role;
grant execute on function app.get_job_shipment_allocation_balance(uuid, uuid) to authenticated, service_role;
grant execute on function app.get_opportunity_costing_readiness(uuid, uuid) to authenticated, service_role;
grant execute on function app.current_support_session(uuid, uuid) to authenticated, service_role;
