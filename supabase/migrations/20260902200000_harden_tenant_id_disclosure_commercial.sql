-- ISS-2026-146 -- cross-tenant tenant_id disclosure via exception message text.
-- Continuation pass (Commercial module), reusing the SAME already-established,
-- already-precedented fix as 20260902100000-20260902104000 (Finance/HRIS/Procurement/
-- Ticketing/Platform Core): fold app.has_active_tenant_membership(<row>.tenant_id,
-- p_actor_auth_user_id) into the SAME not-found branch the row-miss case already
-- raises, using the identical generic message/errcode (no_data_found) a genuinely
-- nonexistent id would already produce. A genuine same-tenant member who simply lacks
-- the specific role authority is completely unaffected -- same message, same errcode,
-- same behavior as before; only a caller with NO relationship to the tenant sees a
-- different (and less disclosing) outcome. No permission check itself is weakened;
-- only the ordering relative to a tenant-membership pre-check moved.
--
-- Every function below is CREATE OR REPLACE against its CURRENT, live body (fetched
-- via pg_get_functiondef immediately before writing this migration, not reconstructed
-- from a possibly-stale migration file) -- signatures are unchanged throughout, so
-- grants are unaffected.
--
-- Scope note: 4 Commercial RISK_UNSCOPED_LOOKUP functions are deliberately NOT
-- included here (app.calculate_margin, app.log_activity, app.record_pipeline_outcome,
-- app.remove_customer_contract_price_component) -- each looks its row up via a foreign
-- key/helper-function derived id with NO pre-existing "if not found" branch to fold
-- into (the lookup is trusted implicitly, e.g. via a FK relationship or a
-- resolve_commercial_record_ref() helper call), so the established "fold into the SAME
-- branch" shape does not apply as-is; introducing a brand-new not-found branch where
-- none exists today is a different, less-precedented change and is left for a follow-up
-- that can design it deliberately rather than reuse this migration's narrow shape by
-- assumption.

CREATE OR REPLACE FUNCTION app.add_customer_contract_price_component(p_contract_id uuid, p_service_type text, p_mode text, p_origin_lane text, p_destination_lane text, p_equipment_type text, p_currency text, p_base_amount numeric, p_minimum_amount numeric, p_discount_pct numeric, p_surcharge_components jsonb, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.customer_contract_price_components
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_contract app.customer_contracts;
  v_decision app.rbac_decision;
  v_component app.customer_contract_price_components;
begin
  select * into v_contract from app.customer_contracts where id = p_contract_id;
  if not found or not app.has_active_tenant_membership(v_contract.tenant_id, p_actor_auth_user_id) then
    raise exception 'contract_not_found: %', p_contract_id using errcode = 'no_data_found';
  end if;

  if v_contract.status <> 'draft' then
    raise exception 'invalid_transition: contract % is % and cannot accept a new price component', p_contract_id, v_contract.status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_contract.tenant_id, 'COM', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_contract.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Dual-gated (mirrors app.select_vendor_rate's own dual COM:Edit + COM:View cost gate,
  -- COM-149): this function RETURNS the raw, unmasked row directly (never the masked
  -- directory view) -- an actor who could edit but could not otherwise view selling price
  -- must not be able to round-trip it back to themselves through this call's own result.
  if not app.has_view_selling_price(v_contract.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks COM:View selling price required to add a price component', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then
    raise exception 'invalid_currency: % is not a 3-letter ISO currency code', p_currency using errcode = 'check_violation';
  end if;

  if p_service_type is null or length(trim(p_service_type)) = 0 then
    raise exception 'invalid_service_type: service_type is required' using errcode = 'check_violation';
  end if;

  insert into app.customer_contract_price_components (
    tenant_id, contract_id, service_type, mode, origin_lane, destination_lane, equipment_type,
    currency, base_amount, minimum_amount, discount_pct, surcharge_components, created_by
  ) values (
    v_contract.tenant_id, p_contract_id, p_service_type, p_mode, p_origin_lane, p_destination_lane, p_equipment_type,
    p_currency, p_base_amount, p_minimum_amount, coalesce(p_discount_pct, 0), coalesce(p_surcharge_components, '[]'::jsonb), p_actor_label
  )
  returning * into v_component;

  return v_component;
end;
$function$;

CREATE OR REPLACE FUNCTION app.add_quotation_line(p_quotation_id uuid, p_expected_version integer, p_line_type text, p_description text, p_margin_calculation_id uuid, p_quantity numeric, p_unit_price numeric, p_discount_pct numeric, p_tax_pct numeric, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.quotations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_quotation app.quotations;
  v_decision app.rbac_decision;
  v_calc app.margin_calculations;
  v_next_line_no integer;
  v_gross numeric(14, 2);
  v_discount numeric(14, 2);
  v_net numeric(14, 2);
  v_tax numeric(14, 2);
  v_total numeric(14, 2);
  v_cost_snapshot numeric(14, 2) := null;
  v_margin_snapshot numeric(7, 2) := null;
begin
  select * into v_quotation from app.quotations where id = p_quotation_id;
  if not found or not app.has_active_tenant_membership(v_quotation.tenant_id, p_actor_auth_user_id) then
    raise exception 'quotation_not_found: %', p_quotation_id using errcode = 'no_data_found';
  end if;

  if v_quotation.record_version <> p_expected_version then
    raise exception 'stale_version: quotation % expected version % but found %', p_quotation_id, p_expected_version, v_quotation.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_quotation.status <> 'draft' or not v_quotation.is_current then
    raise exception 'invalid_transition: quotation % is % (is_current=%) and cannot be edited', p_quotation_id, v_quotation.status, v_quotation.is_current
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_quotation.tenant_id, 'COM', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_quotation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_quotation.tenant_id, v_quotation.owner_user_id, app.lead_record_scope_org_unit_ids(v_quotation.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access quotation %', p_actor_auth_user_id, p_quotation_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_line_type is null or p_line_type not in ('service', 'surcharge', 'fee', 'discount') then
    raise exception 'invalid_line_type: %', p_line_type using errcode = 'check_violation';
  end if;

  if p_description is null or length(trim(p_description)) = 0 then
    raise exception 'description_required: a quotation line requires a non-empty description'
      using errcode = 'not_null_violation';
  end if;

  if p_margin_calculation_id is not null then
    select * into v_calc from app.margin_calculations where id = p_margin_calculation_id;
    if not found then
      raise exception 'margin_calculation_not_found: %', p_margin_calculation_id using errcode = 'no_data_found';
    end if;
    if v_calc.tenant_id <> v_quotation.tenant_id then
      raise exception 'cross_tenant_margin_calculation_denied: margin calculation % does not belong to tenant %', p_margin_calculation_id, v_quotation.tenant_id
        using errcode = 'insufficient_privilege';
    end if;
    if v_calc.sell_currency <> v_quotation.currency then
      raise exception 'mixed_currency: margin calculation % currency % does not match quotation currency %', p_margin_calculation_id, v_calc.sell_currency, v_quotation.currency
        using errcode = 'check_violation';
    end if;
    v_cost_snapshot := v_calc.cost_amount;
    v_margin_snapshot := v_calc.margin_pct;
  end if;

  if p_quantity is null or p_quantity < 0 then
    raise exception 'invalid_quantity: %', p_quantity using errcode = 'check_violation';
  end if;

  if p_unit_price is null or p_unit_price < 0 then
    raise exception 'invalid_unit_price: %', p_unit_price using errcode = 'check_violation';
  end if;

  v_gross := round(p_quantity * p_unit_price, 2);
  v_discount := round(v_gross * coalesce(p_discount_pct, 0) / 100, 2);
  v_net := v_gross - v_discount;
  v_tax := round(v_net * coalesce(p_tax_pct, 0) / 100, 2);
  v_total := v_net + v_tax;

  select coalesce(max(line_no), 0) + 1 into v_next_line_no from app.quotation_lines where quotation_id = p_quotation_id;

  insert into app.quotation_lines (
    tenant_id, quotation_id, line_no, line_type, description, margin_calculation_id,
    quantity, unit_price, discount_pct, tax_pct, line_gross_amount, line_discount_amount, line_tax_amount, line_total,
    cost_amount_snapshot, margin_pct_snapshot, created_by
  ) values (
    v_quotation.tenant_id, p_quotation_id, v_next_line_no, p_line_type, p_description, p_margin_calculation_id,
    p_quantity, p_unit_price, coalesce(p_discount_pct, 0), coalesce(p_tax_pct, 0), v_gross, v_discount, v_tax, v_total,
    v_cost_snapshot, v_margin_snapshot, p_actor_label
  );

  v_quotation := app.recalculate_quotation_totals(p_quotation_id);

  perform app.capture_audit_event(
    v_quotation.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_quotation_line',
    'app.quotations', v_quotation.id, 'success', null, null,
    jsonb_build_object('line_no', v_next_line_no, 'line_total', v_total)
  );

  return v_quotation;
end;
$function$;

CREATE OR REPLACE FUNCTION app.approve_rate_version(p_rate_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.vendor_rate_versions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_rate app.vendor_rate_versions;
  v_vendor_status text;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_rate from app.vendor_rate_versions where id = p_rate_version_id for update;
  if not found or not app.has_active_tenant_membership(v_rate.tenant_id, p_actor_auth_user_id) then
    raise exception 'rate_version_not_found: %', p_rate_version_id using errcode = 'no_data_found';
  end if;

  if not app.is_support_grant_authority(p_actor_auth_user_id, v_rate.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_rate.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_rate.record_version <> p_expected_version then
    raise exception 'stale_version: rate version % expected version % but found %', p_rate_version_id, p_expected_version, v_rate.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_rate.approval_status <> 'pending_approval' then
    raise exception 'invalid_transition: rate version % is % and cannot be approved', p_rate_version_id, v_rate.approval_status
      using errcode = 'check_violation';
  end if;

  if v_rate.governance_approval_status not in ('approved', 'not_required') then
    raise exception 'rate_governance_approval_pending: rate version % governance_approval_status is % (must be approved or not_required)', p_rate_version_id, v_rate.governance_approval_status
      using errcode = 'check_violation';
  end if;

  if v_rate.vendor_master_id is not null then
    select lifecycle_status into v_vendor_status from app.vendor_profiles where master_record_id = v_rate.vendor_master_id;
    if v_vendor_status is distinct from 'active' then
      raise exception 'vendor_not_active: linked vendor % is % -- a rate cannot be approved for a non-active vendor', v_rate.vendor_master_id, coalesce(v_vendor_status, 'unregistered')
        using errcode = 'check_violation';
    end if;
  end if;

  perform app._validate_vendor_rate_tiers_contiguous(p_rate_version_id);

  -- ISS-2026-060 addition (design note 4): the zone/distance sibling validator,
  -- same "validate once, at publish" discipline. A rate version with zero
  -- zone/distance tiers is a trivial, immediate no-op.
  perform app._validate_vendor_rate_zone_distance_tiers_contiguous(p_rate_version_id);

  begin
    update app.vendor_rate_versions
    set approval_status = 'approved', approved_by = p_actor_label, approved_at = now(), updated_at = now(), record_version = record_version + 1
    where id = p_rate_version_id and record_version = p_expected_version
    returning * into v_rate;
  exception
    when exclusion_violation then
      raise exception 'ambiguous_overlap: an approved, currently-effective rate version already exists for the identical vendor/service/mode/lane/equipment scope with an overlapping validity window'
        using errcode = 'check_violation';
    when deadlock_detected then
      raise exception 'ambiguous_overlap: a concurrent approval at the identical vendor/service/mode/lane/equipment scope could not be serialized -- retry the approval'
        using errcode = 'check_violation';
  end;
  if not found then
    raise exception 'stale_version: rate version % target row was concurrently modified (expected version %)', p_rate_version_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_rate.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_rate_version',
    'app.vendor_rate_versions', v_rate.id, 'success', null, null, jsonb_build_object('approval_status', v_rate.approval_status)
  );

  return v_rate;
end;
$function$;

CREATE OR REPLACE FUNCTION app.archive_sales_plan(p_plan_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.sales_plans
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_plan app.sales_plans;
  v_decision app.rbac_decision;
begin
  select * into v_plan from app.sales_plans where id = p_plan_id;
  if not found or not app.has_active_tenant_membership(v_plan.tenant_id, p_actor_auth_user_id) then
    raise exception 'sales_plan_not_found: %', p_plan_id using errcode = 'no_data_found';
  end if;

  if v_plan.record_version <> p_expected_version then
    raise exception 'stale_version: sales plan % expected version % but found %', p_plan_id, p_expected_version, v_plan.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_plan.status = 'archived' then
    raise exception 'invalid_transition: sales plan % is already archived', p_plan_id
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_plan.tenant_id, 'COM', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_plan.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_plan.tenant_id, v_plan.owner_user_id, app.lead_record_scope_org_unit_ids(v_plan.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access sales plan %', p_actor_auth_user_id, p_plan_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.sales_plans
  set status = 'archived', updated_at = now(), record_version = record_version + 1
  where id = p_plan_id and record_version = p_expected_version
  returning * into v_plan;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: archive_sales_plan target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_plan.tenant_id, p_actor_auth_user_id, p_actor_label, 'archive_sales_plan',
    'app.sales_plans', v_plan.id, 'success', null, null, null
  );

  return v_plan;
end;
$function$;

CREATE OR REPLACE FUNCTION app.assert_vendor_rate_version_tier_editable(p_rate_version_id uuid, p_actor_auth_user_id uuid, OUT v_rate app.vendor_rate_versions)
 RETURNS app.vendor_rate_versions
 LANGUAGE plpgsql
AS $function$
declare
  v_decision app.rbac_decision;
begin
  select * into v_rate from app.vendor_rate_versions where id = p_rate_version_id for update;
  if not found or not app.has_active_tenant_membership(v_rate.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_rate_version_not_found: %', p_rate_version_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_rate.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_rate.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_rate.approval_status <> 'pending_approval' then
    raise exception 'vendor_rate_version_not_editable: rate version % is % -- tiers may only be added/removed while pending_approval', p_rate_version_id, v_rate.approval_status
      using errcode = 'check_violation';
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION app.assign_costing_request(p_request_id uuid, p_expected_version integer, p_assignee_user_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.costing_requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_request app.costing_requests;
  v_decision app.rbac_decision;
begin
  select * into v_request from app.costing_requests where id = p_request_id;
  if not found or not app.has_active_tenant_membership(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'costing_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;

  if v_request.record_version <> p_expected_version then
    raise exception 'stale_version: costing request % expected version % but found %', p_request_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_request.status in ('cancelled', 'superseded') then
    raise exception 'invalid_transition: costing request % is % and cannot be assigned', p_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'COM', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_request.tenant_id, v_request.owner_user_id, app.lead_record_scope_org_unit_ids(v_request.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access costing request %', p_actor_auth_user_id, p_request_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.costing_requests
  set assignee_user_id = p_assignee_user_id,
      status = case when status = 'pending' then 'assigned' else status end,
      updated_at = now(),
      record_version = record_version + 1
  where id = p_request_id and record_version = p_expected_version
  returning * into v_request;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: assign_costing_request target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'assign_costing_request',
    'app.costing_requests', v_request.id, 'success', null, null, jsonb_build_object('assignee_user_id', p_assignee_user_id)
  );

  return v_request;
end;
$function$;

CREATE OR REPLACE FUNCTION app.assign_lead(p_lead_id uuid, p_expected_version integer, p_new_owner_user_id uuid, p_new_org_unit_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.leads
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_lead app.leads;
  v_decision app.rbac_decision;
begin
  select * into v_lead from app.leads where id = p_lead_id;
  if not found or not app.has_active_tenant_membership(v_lead.tenant_id, p_actor_auth_user_id) then
    raise exception 'lead_not_found: %', p_lead_id using errcode = 'no_data_found';
  end if;

  if v_lead.record_version <> p_expected_version then
    raise exception 'stale_version: lead % expected version % but found %', p_lead_id, p_expected_version, v_lead.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_lead.status = 'merged' then
    raise exception 'invalid_transition: lead % is merged and cannot be reassigned', p_lead_id
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_lead.tenant_id, 'COM', 'Assign');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Assign (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_lead.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(
    p_actor_auth_user_id, v_lead.tenant_id, v_lead.owner_user_id,
    app.lead_record_scope_org_unit_ids(v_lead.org_unit_id),
    null
  ) then
    raise exception 'insufficient_authority: identity % cannot access lead %', p_actor_auth_user_id, p_lead_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.leads
  set owner_user_id = p_new_owner_user_id,
      org_unit_id = p_new_org_unit_id,
      assigned_at = now(),
      assigned_by = p_actor_label,
      last_activity_at = now(),
      record_version = record_version + 1
  where id = p_lead_id and record_version = p_expected_version
  returning * into v_lead;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: assign_lead target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_lead.tenant_id, p_actor_auth_user_id, p_actor_label, 'assign_lead',
    'app.leads', v_lead.id, 'success', null, null,
    jsonb_build_object('new_owner_user_id', p_new_owner_user_id, 'new_org_unit_id', p_new_org_unit_id)
  );

  return v_lead;
end;
$function$;

CREATE OR REPLACE FUNCTION app.cancel_costing_request(p_request_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.costing_requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_request app.costing_requests;
  v_decision app.rbac_decision;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: cancelling a costing request requires a non-empty reason'
      using errcode = 'not_null_violation';
  end if;

  select * into v_request from app.costing_requests where id = p_request_id;
  if not found or not app.has_active_tenant_membership(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'costing_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;

  if v_request.record_version <> p_expected_version then
    raise exception 'stale_version: costing request % expected version % but found %', p_request_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_request.status in ('cancelled', 'superseded') then
    raise exception 'invalid_transition: costing request % is % and cannot be cancelled', p_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'COM', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_request.tenant_id, v_request.owner_user_id, app.lead_record_scope_org_unit_ids(v_request.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access costing request %', p_actor_auth_user_id, p_request_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.costing_requests
  set status = 'cancelled', cancel_reason = p_reason, updated_at = now(), record_version = record_version + 1
  where id = p_request_id and record_version = p_expected_version
  returning * into v_request;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: cancel_costing_request target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_costing_request',
    'app.costing_requests', v_request.id, 'success', null, null, jsonb_build_object('reason', p_reason)
  );

  return v_request;
end;
$function$;

CREATE OR REPLACE FUNCTION app.capture_forecast_snapshot(p_sales_target_id uuid, p_override_value integer, p_override_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.forecast_snapshots
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_target app.sales_targets;
  v_plan app.sales_plans;
  v_decision app.rbac_decision;
  v_computed integer;
  v_snapshot app.forecast_snapshots;
begin
  select * into v_target from app.sales_targets where id = p_sales_target_id;
  if not found or not app.has_active_tenant_membership(v_target.tenant_id, p_actor_auth_user_id) then
    raise exception 'sales_target_not_found: %', p_sales_target_id using errcode = 'no_data_found';
  end if;

  select * into v_plan from app.sales_plans where id = v_target.sales_plan_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_target.tenant_id, 'COM', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_target.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_target.tenant_id, v_target.owner_user_id, app.lead_record_scope_org_unit_ids(v_target.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access sales target %', p_actor_auth_user_id, p_sales_target_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_override_value is not null and (p_override_reason is null or length(trim(p_override_reason)) = 0) then
    raise exception 'override_reason_required: an override value requires a non-empty override reason'
      using errcode = 'check_violation';
  end if;

  v_computed := app.compute_sales_metric_count(
    v_target.tenant_id, v_target.metric_type, v_target.org_unit_id, v_target.owner_user_id,
    v_plan.period_start, v_plan.period_end, p_actor_auth_user_id
  );

  insert into app.forecast_snapshots (tenant_id, sales_target_id, computed_value, override_value, override_reason, created_by)
  values (v_target.tenant_id, p_sales_target_id, v_computed, p_override_value, p_override_reason, p_actor_label)
  returning * into v_snapshot;

  perform app.capture_audit_event(
    v_target.tenant_id, p_actor_auth_user_id, p_actor_label, 'capture_forecast_snapshot',
    'app.forecast_snapshots', v_snapshot.id, 'success', null, null, to_jsonb(v_snapshot)
  );

  return v_snapshot;
end;
$function$;

CREATE OR REPLACE FUNCTION app.clone_opportunity(p_opportunity_id uuid, p_name text, p_actor_auth_user_id uuid, p_created_by text)
 RETURNS app.opportunities
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_source app.opportunities;
  v_decision app.rbac_decision;
  v_clone app.opportunities;
begin
  select * into v_source from app.opportunities where id = p_opportunity_id;
  if not found or not app.has_active_tenant_membership(v_source.tenant_id, p_actor_auth_user_id) then
    raise exception 'opportunity_not_found: %', p_opportunity_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_source.tenant_id, 'COM', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_source.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_source.tenant_id, v_source.owner_user_id, app.lead_record_scope_org_unit_ids(v_source.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access opportunity %', p_actor_auth_user_id, p_opportunity_id
      using errcode = 'insufficient_privilege';
  end if;

  insert into app.opportunities (
    tenant_id, prospect_id, name, requirements, owner_user_id, org_unit_id, cloned_from_id, created_by
  ) values (
    v_source.tenant_id, v_source.prospect_id, coalesce(p_name, v_source.name || ' (copy)'),
    v_source.requirements, p_actor_auth_user_id, v_source.org_unit_id, v_source.id, p_created_by
  )
  returning * into v_clone;

  insert into app.opportunity_stage_history (tenant_id, opportunity_id, from_stage, to_stage, probability, changed_by)
  values (v_clone.tenant_id, v_clone.id, null, v_clone.stage, v_clone.probability, p_created_by);

  perform app.capture_audit_event(
    v_source.tenant_id, p_actor_auth_user_id, p_created_by, 'clone_opportunity',
    'app.opportunities', v_clone.id, 'success', null, null, jsonb_build_object('cloned_from_id', v_source.id)
  );

  return v_clone;
end;
$function$;

CREATE OR REPLACE FUNCTION app.clone_quotation(p_source_quotation_id uuid, p_actor_auth_user_id uuid, p_created_by text)
 RETURNS app.quotations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_source app.quotations;
  v_decision app.rbac_decision;
  v_new app.quotations;
  v_duration interval;
  v_new_id uuid := gen_random_uuid();
begin
  select * into v_source from app.quotations where id = p_source_quotation_id;
  if not found or not app.has_active_tenant_membership(v_source.tenant_id, p_actor_auth_user_id) then
    raise exception 'quotation_not_found: %', p_source_quotation_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_source.tenant_id, 'COM', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_source.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_source.tenant_id, v_source.owner_user_id, app.lead_record_scope_org_unit_ids(v_source.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access quotation %', p_actor_auth_user_id, p_source_quotation_id
      using errcode = 'insufficient_privilege';
  end if;

  v_duration := v_source.validity_to - v_source.validity_from;

  insert into app.quotations (
    id, tenant_id, quote_number, opportunity_id, source_opportunity_version, prospect_id, contact_id,
    customer_snapshot, currency, validity_from, validity_to, terms, cloned_from_id,
    root_quotation_id, version_number, is_current,
    owner_user_id, org_unit_id, created_by
  ) values (
    v_new_id, v_source.tenant_id, app.next_quotation_number(v_source.tenant_id), v_source.opportunity_id, v_source.source_opportunity_version,
    v_source.prospect_id, v_source.contact_id, v_source.customer_snapshot, v_source.currency, now(), now() + v_duration, v_source.terms,
    v_source.id, v_new_id, 1, true,
    v_source.owner_user_id, v_source.org_unit_id, p_created_by
  )
  returning * into v_new;

  insert into app.quotation_lines (
    tenant_id, quotation_id, line_no, line_type, description, margin_calculation_id,
    quantity, unit_price, discount_pct, tax_pct, line_gross_amount, line_discount_amount, line_tax_amount, line_total,
    cost_amount_snapshot, margin_pct_snapshot, created_by
  )
  select
    tenant_id, v_new.id, line_no, line_type, description, margin_calculation_id,
    quantity, unit_price, discount_pct, tax_pct, line_gross_amount, line_discount_amount, line_tax_amount, line_total,
    cost_amount_snapshot, margin_pct_snapshot, p_created_by
  from app.quotation_lines
  where quotation_id = v_source.id;

  v_new := app.recalculate_quotation_totals(v_new.id);

  perform app.capture_audit_event(
    v_source.tenant_id, p_actor_auth_user_id, p_created_by, 'clone_quotation',
    'app.quotations', v_new.id, 'success', null, null, jsonb_build_object('cloned_from_id', v_source.id)
  );

  return v_new;
end;
$function$;

CREATE OR REPLACE FUNCTION app.commit_vendor_rate_import_job(p_job_id uuid, p_allow_partial boolean, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text DEFAULT NULL::text)
 RETURNS app.jobs
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
declare
  v_job app.jobs;
  v_decision app.rbac_decision;
  v_pending_count integer;
  v_row record;
  v_payload jsonb;
  v_vendor_master_id uuid;
  v_vendor_master app.master_records;
  v_new_rate app.vendor_rate_versions;
  v_created_count integer := 0;
  v_skipped_count integer := 0;
  v_tier_idx integer;
  v_tier_prefix text;
  v_tier_amount numeric;
  v_updated app.jobs;
  v_constraint_name text;
begin
  select * into v_job from app.jobs where job_id = p_job_id for update;
  if not found or not app.has_active_tenant_membership(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'import_export_job_not_found: no job %', p_job_id using errcode = 'no_data_found';
  end if;

  if v_job.job_type <> 'import' or v_job.import_export_schema_code <> 'vendor_rate_import' then
    raise exception 'import_export_wrong_schema: job % is not a vendor_rate_import job', p_job_id using errcode = 'check_violation';
  end if;

  if not app.check_import_export_job_authority(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'job_actor_unauthorized: identity % lacks active membership in tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- PRC-255 addition (design note 11): BOTH the unchanged create_rate_version
  -- authority AND the new PRC:Import action -- see this migration's own header for
  -- why PRC:Import alone must never be sufficient.
  if not app.is_support_grant_authority(p_actor_auth_user_id, v_job.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_job.tenant_id, 'PRC', 'Import');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Import (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-278 (this migration): reuses the SAME PRC:Import pair the check immediately
  -- above already gates on. A strict no-op unless this tenant has itself opted (PRC,
  -- Import) into its own additional_high_risk_actions AND turned MFA on.
  perform app.assert_current_step_up_authorization(v_job.tenant_id, p_actor_auth_user_id, 'PRC', 'Import');

  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_job.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_job.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  if v_job.status <> 'in_progress' then
    raise exception 'import_export_job_not_committable: job % is %, only an in_progress job may be committed', p_job_id, v_job.status
      using errcode = 'check_violation';
  end if;

  select count(*) into v_pending_count from app.import_staging_rows where job_id = p_job_id and validation_status = 'pending';
  if v_pending_count > 0 then
    raise exception 'import_export_job_not_fully_validated: job % still has % row(s) pending validation', p_job_id, v_pending_count
      using errcode = 'check_violation';
  end if;

  if v_job.invalid_row_count > 0 and not coalesce(p_allow_partial, false) then
    raise exception 'import_export_job_has_invalid_rows: job % has % invalid row(s); pass p_allow_partial to accept a partial commit', p_job_id, v_job.invalid_row_count
      using errcode = 'check_violation';
  end if;

  -- Job-scoped advisory lock (pattern 3) -- resolved and taken before any staging
  -- row is read, serializing any concurrent/replayed commit call on this SAME job.
  perform pg_advisory_xact_lock(hashtextextended(p_job_id::text, 205));

  for v_row in
    select * from app.import_staging_rows
    where job_id = p_job_id and validation_status = 'valid'
    order by row_number
  loop
    if exists (select 1 from app.vendor_rate_versions where source_import_staging_row_id = v_row.id) then
      v_skipped_count := v_skipped_count + 1;
      continue;
    end if;

    v_payload := v_row.raw_payload;
    v_vendor_master_id := null;
    if coalesce(v_payload ->> 'vendor_master_code', '') <> '' then
      select * into v_vendor_master from app.master_records
      where tenant_id = v_job.tenant_id and master_type_code = 'vendor' and code = (v_payload ->> 'vendor_master_code');
      if not found then
        raise exception 'import_vendor_master_not_found: staging row % references vendor_master_code % which does not resolve to a registered vendor in tenant %', v_row.row_number, v_payload ->> 'vendor_master_code', v_job.tenant_id
          using errcode = 'check_violation';
      end if;
      v_vendor_master_id := v_vendor_master.id;
    end if;

    begin
      select * into v_new_rate from app.create_rate_version(
        v_job.tenant_id,
        v_payload ->> 'vendor_code',
        v_payload ->> 'vendor_name',
        v_payload ->> 'service_type',
        nullif(v_payload ->> 'mode', ''),
        v_payload ->> 'origin_lane',
        v_payload ->> 'destination_lane',
        nullif(v_payload ->> 'equipment_type', ''),
        null, null, null, null,
        v_payload ->> 'currency',
        (v_payload ->> 'base_amount')::numeric,
        nullif(v_payload ->> 'minimum_amount', '')::numeric,
        '[]'::jsonb,
        now(), null, null,
        p_actor_auth_user_id, p_actor_label,
        v_vendor_master_id,
        nullif(v_payload ->> 'lead_time_days', '')::integer,
        nullif(v_payload ->> 'capacity_terms', ''),
        v_row.id
      );
    exception
      when unique_violation then
        -- Race-recovery (pattern 4): a concurrent/replayed call already committed
        -- this exact staging row between the exists-check above and this INSERT.
        -- BUG FIX (post-review, CRITICAL): the ORIGINAL handler caught ANY
        -- unique_violation unconditionally, which also silently swallowed a
        -- GENUINE vendor_code collision -- app.create_rate_version ->
        -- app.create_master_record has its own unlocked check-then-insert on
        -- master_records_tenant_code_unique and re-raises a real collision as
        -- master_record_already_exists, ALSO sqlstate unique_violation. Treating
        -- that as "safe replay, skip" silently dropped the row: the job still
        -- reported status=completed/valid_row_count as if the rate version had
        -- been created, but no row was ever written, with no error and no
        -- recoverable retry path (a completed job can never be recommitted).
        -- Only a violation of THIS adapter's own idempotency guard
        -- (vendor_rate_versions_source_import_row_unique) means "already
        -- committed, safe to skip" -- any other unique_violation is a REAL
        -- failure and must abort the whole commit (the surrounding transaction
        -- rolls back, so the job is never marked completed with a silently
        -- dropped row).
        get stacked diagnostics v_constraint_name = constraint_name;
        if v_constraint_name = 'vendor_rate_versions_source_import_row_unique' then
          v_skipped_count := v_skipped_count + 1;
          continue;
        end if;
        raise;
    end;

    v_created_count := v_created_count + 1;

    for v_tier_idx in 1..3 loop
      v_tier_prefix := 'tier' || v_tier_idx || '_';
      v_tier_amount := nullif(v_payload ->> (v_tier_prefix || 'amount'), '')::numeric;
      if v_tier_amount is not null then
        perform app._insert_vendor_rate_tier(
          v_new_rate,
          v_tier_idx,
          nullif(v_payload ->> (v_tier_prefix || 'weight_min'), '')::numeric,
          nullif(v_payload ->> (v_tier_prefix || 'weight_max'), '')::numeric,
          nullif(v_payload ->> (v_tier_prefix || 'volume_min'), '')::numeric,
          nullif(v_payload ->> (v_tier_prefix || 'volume_max'), '')::numeric,
          v_tier_amount,
          nullif(v_payload ->> (v_tier_prefix || 'minimum_charge'), '')::numeric,
          null,
          p_actor_label
        );
      end if;
    end loop;
  end loop;

  update app.jobs
  set status = 'completed', completed_at = now()
  where job_id = p_job_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'commit_vendor_rate_import_job',
    'app.jobs', p_job_id, 'success', null, to_jsonb(v_job),
    jsonb_build_object('status', v_updated.status, 'rate_versions_created', v_created_count, 'rows_already_committed_skipped', v_skipped_count)
  );

  return v_updated;
end;
$function$;

CREATE OR REPLACE FUNCTION app.convert_lead_to_prospect(p_lead_id uuid, p_legal_name text, p_trade_name text, p_tax_id text, p_billing_address jsonb, p_actor_auth_user_id uuid, p_created_by text)
 RETURNS app.prospects
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_lead app.leads;
  v_existing app.prospects;
  v_prospect app.prospects;
  v_decision app.rbac_decision;
begin
  select * into v_lead from app.leads where id = p_lead_id;
  if not found or not app.has_active_tenant_membership(v_lead.tenant_id, p_actor_auth_user_id) then
    raise exception 'lead_not_found: %', p_lead_id using errcode = 'no_data_found';
  end if;

  select * into v_existing from app.prospects where lead_id = p_lead_id;
  if found then
    return v_existing;
  end if;

  if v_lead.status <> 'qualified' then
    raise exception 'invalid_transition: lead % is % and cannot convert to a prospect (must be qualified)', p_lead_id, v_lead.status
      using errcode = 'check_violation';
  end if;

  if not app.can_access_record(
    p_actor_auth_user_id, v_lead.tenant_id, v_lead.owner_user_id,
    app.lead_record_scope_org_unit_ids(v_lead.org_unit_id),
    null
  ) then
    raise exception 'insufficient_authority: identity % cannot access lead %', p_actor_auth_user_id, p_lead_id
      using errcode = 'insufficient_privilege';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_lead.tenant_id, 'COM', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_lead.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  insert into app.prospects (
    tenant_id, lead_id, legal_name, trade_name, tax_id, billing_address,
    contact_name, contact_email, contact_phone, owner_user_id, org_unit_id, created_by
  ) values (
    v_lead.tenant_id, p_lead_id, p_legal_name, p_trade_name, p_tax_id, coalesce(p_billing_address, '{}'::jsonb),
    v_lead.contact_name, v_lead.email, v_lead.phone, v_lead.owner_user_id, v_lead.org_unit_id, p_created_by
  )
  returning * into v_prospect;

  update app.leads
  set status = 'converted', converted_at = now(), converted_prospect_id = v_prospect.id, last_activity_at = now(), record_version = record_version + 1
  where id = p_lead_id;

  perform app.capture_audit_event(
    v_lead.tenant_id, p_actor_auth_user_id, p_created_by, 'convert_lead_to_prospect',
    'app.prospects', v_prospect.id, 'success', null, null, to_jsonb(v_prospect)
  );

  return v_prospect;
exception
  when unique_violation then
    select * into v_existing from app.prospects where lead_id = p_lead_id;
    return v_existing;
end;
$function$;

CREATE OR REPLACE FUNCTION app.convert_quotation_to_account(p_quotation_id uuid, p_target_account_id uuid, p_parent_account_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.accounts
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_quotation app.quotations;
  v_prospect app.prospects;
  v_decision app.rbac_decision;
  v_existing_conversion app.account_conversions;
  v_account app.accounts;
  v_outcome text;
  v_normalized_legal_name text;
  v_normalized_tax_id text;
  v_fingerprint text;
  v_link app.contact_links%rowtype;
begin
  select * into v_quotation from app.quotations where id = p_quotation_id;
  if not found or not app.has_active_tenant_membership(v_quotation.tenant_id, p_actor_auth_user_id) then
    raise exception 'quotation_not_found: %', p_quotation_id using errcode = 'no_data_found';
  end if;

  select * into v_existing_conversion from app.account_conversions where quotation_id = p_quotation_id;
  if found then
    select * into v_account from app.accounts where id = v_existing_conversion.account_id;
    return v_account;
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_quotation.tenant_id, 'COM', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_quotation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_quotation.tenant_id, v_quotation.owner_user_id, app.lead_record_scope_org_unit_ids(v_quotation.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access quotation %', p_actor_auth_user_id, p_quotation_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_quotation.customer_decision is distinct from 'accepted' then
    raise exception 'quotation_not_accepted: quotation % has no accepted customer decision', p_quotation_id
      using errcode = 'check_violation';
  end if;

  select * into v_prospect from app.prospects where id = v_quotation.prospect_id;
  if v_prospect.legal_name is null or length(trim(v_prospect.legal_name)) = 0 then
    raise exception 'missing_legal_name: prospect % has no legal_name to convert', v_prospect.id
      using errcode = 'check_violation';
  end if;

  if p_target_account_id is not null then
    select * into v_account from app.accounts where id = p_target_account_id;
    if not found or v_account.tenant_id <> v_quotation.tenant_id or v_account.status = 'merged' then
      raise exception 'target_account_not_found: no active account % in tenant %', p_target_account_id, v_quotation.tenant_id
        using errcode = 'no_data_found';
    end if;
    v_outcome := 'linked_existing';
  else
    v_normalized_legal_name := app.normalize_prospect_identifier(v_prospect.legal_name);
    v_normalized_tax_id := app.normalize_prospect_identifier(v_prospect.tax_id);
    v_fingerprint := app.compute_prospect_duplicate_fingerprint(v_quotation.tenant_id, v_normalized_legal_name, v_normalized_tax_id);

    begin
      insert into app.accounts (
        tenant_id, legal_name, trade_name, tax_id, normalized_legal_name, normalized_tax_id,
        duplicate_fingerprint, billing_address, parent_account_id, source_prospect_id,
        owner_user_id, org_unit_id, created_by
      ) values (
        v_quotation.tenant_id, v_prospect.legal_name, v_prospect.trade_name, v_prospect.tax_id,
        v_normalized_legal_name, v_normalized_tax_id, v_fingerprint,
        coalesce(v_quotation.customer_snapshot -> 'billing_address', v_prospect.billing_address, '{}'::jsonb),
        p_parent_account_id, v_prospect.id, p_actor_auth_user_id, v_quotation.org_unit_id, p_actor_label
      )
      returning * into v_account;
      v_outcome := 'created';
    exception
      when unique_violation then
        select * into v_account from app.accounts where tenant_id = v_quotation.tenant_id and duplicate_fingerprint = v_fingerprint and status = 'active';
        v_outcome := 'linked_existing';
    end;
  end if;

  begin
    insert into app.account_conversions (tenant_id, quotation_id, prospect_id, account_id, outcome, converted_by)
    values (v_quotation.tenant_id, p_quotation_id, v_prospect.id, v_account.id, v_outcome, p_actor_label);
  exception
    when unique_violation then
      select * into v_existing_conversion from app.account_conversions where quotation_id = p_quotation_id;
      select * into v_account from app.accounts where id = v_existing_conversion.account_id;
      return v_account;
  end;

  -- Reuse contacts (Prompt 155 §20 task 3: "reused contacts/address/site relationships")
  -- -- every contact linked to the source prospect is also linked to the resulting
  -- account, idempotent via app.link_contact_to_record's own (contact_id, related_type,
  -- related_id, role) uniqueness.
  for v_link in select * from app.contact_links where related_type = 'prospect' and related_id = v_prospect.id loop
    perform app.link_contact_to_record(v_link.contact_id, 'account', v_account.id, v_link.role, v_link.is_primary, p_actor_auth_user_id, p_actor_label);
  end loop;

  -- COM-161: now sets both the legacy disclosed text placeholder (account_ref, COM-147)
  -- and the canonical FK-backed column (account_id, this checkpoint) from the one same
  -- value -- closing app.opportunities.account_ref's own forward-reference disclosure.
  update app.opportunities set account_ref = v_account.id::text, account_id = v_account.id where id = v_quotation.opportunity_id;

  perform app.capture_audit_event(
    v_quotation.tenant_id, p_actor_auth_user_id, p_actor_label, 'convert_quotation_to_account',
    'app.accounts', v_account.id, 'success', null,
    jsonb_build_object('quotation_id', p_quotation_id, 'prospect_id', v_prospect.id),
    jsonb_build_object('outcome', v_outcome, 'account_id', v_account.id)
  );

  return v_account;
end;
$function$;

CREATE OR REPLACE FUNCTION app.create_credit_override(p_profile_id uuid, p_amount numeric, p_reason text, p_expires_at timestamp with time zone, p_reauth_confirmed_at timestamp with time zone, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.credit_profile_overrides
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
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
  if not found or not app.has_active_tenant_membership(v_profile.tenant_id, p_actor_auth_user_id) then
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
$function$;

CREATE OR REPLACE FUNCTION app.create_customer_contract_draft(p_source_quotation_id uuid, p_source_contract_id uuid, p_effective_from timestamp with time zone, p_effective_to timestamp with time zone, p_amendment_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.customer_contracts
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_quotation app.quotations;
  v_conversion app.account_conversions;
  v_source app.customer_contracts;
  v_component app.customer_contract_price_components;
  v_new_id uuid := gen_random_uuid();
  v_new app.customer_contracts;
  v_tenant_id uuid;
  v_account_id uuid;
  v_root_contract_id uuid;
  v_next_version integer;
begin
  if (p_source_quotation_id is null) = (p_source_contract_id is null) then
    raise exception 'invalid_source: exactly one of source_quotation_id/source_contract_id must be supplied'
      using errcode = 'check_violation';
  end if;

  if p_effective_from is null then
    raise exception 'invalid_validity: effective_from is required' using errcode = 'check_violation';
  end if;

  if p_source_quotation_id is not null then
    select * into v_quotation from app.quotations where id = p_source_quotation_id;
    if not found or not app.has_active_tenant_membership(v_quotation.tenant_id, p_actor_auth_user_id) then
      raise exception 'quotation_not_found: %', p_source_quotation_id using errcode = 'no_data_found';
    end if;

    v_decision := app.evaluate_permission(p_actor_auth_user_id, v_quotation.tenant_id, 'COM', 'Edit');
    if not v_decision.allowed then
      raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_quotation.tenant_id
        using errcode = 'insufficient_privilege';
    end if;
    if not app.can_access_record(p_actor_auth_user_id, v_quotation.tenant_id, v_quotation.owner_user_id, app.lead_record_scope_org_unit_ids(v_quotation.org_unit_id), null) then
      raise exception 'insufficient_authority: identity % cannot access quotation %', p_actor_auth_user_id, p_source_quotation_id
        using errcode = 'insufficient_privilege';
    end if;

    if v_quotation.customer_decision is distinct from 'accepted' then
      raise exception 'quotation_not_accepted: quotation % has no accepted customer decision', p_source_quotation_id
        using errcode = 'check_violation';
    end if;

    select * into v_conversion from app.account_conversions where quotation_id = p_source_quotation_id;
    if not found then
      raise exception 'quotation_not_converted: quotation % has not been converted to an account yet (COM-155)', p_source_quotation_id
        using errcode = 'check_violation';
    end if;

    if exists (select 1 from app.customer_contracts where source_quotation_id = p_source_quotation_id) then
      raise exception 'quotation_already_contracted: quotation % already sourced a contract', p_source_quotation_id
        using errcode = 'unique_violation';
    end if;

    v_tenant_id := v_quotation.tenant_id;
    v_account_id := v_conversion.account_id;
    v_root_contract_id := v_new_id;
    v_next_version := 1;

    insert into app.customer_contracts (
      id, tenant_id, account_id, root_contract_id, version_number, source_quotation_id,
      effective_from, effective_to, owner_user_id, org_unit_id, created_by
    ) values (
      v_new_id, v_tenant_id, v_account_id, v_root_contract_id, v_next_version, p_source_quotation_id,
      p_effective_from, p_effective_to, coalesce(v_quotation.owner_user_id, p_actor_auth_user_id), v_quotation.org_unit_id, p_actor_label
    )
    returning * into v_new;
  else
    select * into v_source from app.customer_contracts where id = p_source_contract_id;
    if not found or not app.has_active_tenant_membership(v_source.tenant_id, p_actor_auth_user_id) then
      raise exception 'contract_not_found: %', p_source_contract_id using errcode = 'no_data_found';
    end if;

    v_decision := app.evaluate_permission(p_actor_auth_user_id, v_source.tenant_id, 'COM', 'Edit');
    if not v_decision.allowed then
      raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_source.tenant_id
        using errcode = 'insufficient_privilege';
    end if;

    if p_amendment_reason is null or length(trim(p_amendment_reason)) = 0 then
      raise exception 'reason_required: an amendment/renewal requires a non-empty reason'
        using errcode = 'not_null_violation';
    end if;

    v_tenant_id := v_source.tenant_id;
    v_account_id := v_source.account_id;
    v_root_contract_id := v_source.root_contract_id;
    v_next_version := (select coalesce(max(version_number), 0) + 1 from app.customer_contracts where root_contract_id = v_root_contract_id);

    insert into app.customer_contracts (
      id, tenant_id, account_id, root_contract_id, version_number, amendment_reason,
      effective_from, effective_to, owner_user_id, org_unit_id, created_by
    ) values (
      v_new_id, v_tenant_id, v_account_id, v_root_contract_id, v_next_version, p_amendment_reason,
      p_effective_from, p_effective_to, v_source.owner_user_id, v_source.org_unit_id, p_actor_label
    )
    returning * into v_new;

    -- Copies the source version's own price components into the new draft (a renewal
    -- normally starts from what came before, then is edited) -- never a live reference,
    -- the same no-reentry snapshot discipline every prior Commercial capability follows.
    for v_component in select * from app.customer_contract_price_components where contract_id = p_source_contract_id loop
      insert into app.customer_contract_price_components (
        tenant_id, contract_id, service_type, mode, origin_lane, destination_lane, equipment_type,
        currency, base_amount, minimum_amount, discount_pct, surcharge_components, created_by
      ) values (
        v_tenant_id, v_new.id, v_component.service_type, v_component.mode, v_component.origin_lane, v_component.destination_lane, v_component.equipment_type,
        v_component.currency, v_component.base_amount, v_component.minimum_amount, v_component.discount_pct, v_component.surcharge_components, p_actor_label
      );
    end loop;
  end if;

  perform app.capture_audit_event(
    v_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_customer_contract_draft',
    'app.customer_contracts', v_new.id, 'success', null, null, to_jsonb(v_new)
  );

  return v_new;
end;
$function$;

CREATE OR REPLACE FUNCTION app.create_quotation_revision(p_source_quotation_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.quotations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_source app.quotations;
  v_current app.quotations;
  v_decision app.rbac_decision;
  v_next_version integer;
  v_new_id uuid := gen_random_uuid();
  v_new app.quotations;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: creating a quotation revision requires a non-empty reason'
      using errcode = 'not_null_violation';
  end if;

  select * into v_source from app.quotations where id = p_source_quotation_id;
  if not found or not app.has_active_tenant_membership(v_source.tenant_id, p_actor_auth_user_id) then
    raise exception 'quotation_not_found: %', p_source_quotation_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_source.tenant_id, 'COM', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_source.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_source.tenant_id, v_source.owner_user_id, app.lead_record_scope_org_unit_ids(v_source.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access quotation %', p_actor_auth_user_id, p_source_quotation_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Row-level lock on the root's current version -- a concurrent second call blocks here
  -- until the first commits, then re-reads and finds a *different* current row (the one
  -- the first call just created), so its own supersede UPDATE below naturally affects zero
  -- rows and this call fails closed rather than creating a divergent branch (Prompt 152
  -- §23: "Concurrent next-version request... fails without partial revision").
  select * into v_current from app.quotations where root_quotation_id = v_source.root_quotation_id and is_current for update;

  if v_current.status = 'cancelled' then
    raise exception 'invalid_transition: quotation root % is cancelled and cannot be revised', v_source.root_quotation_id
      using errcode = 'check_violation';
  end if;

  v_next_version := (select coalesce(max(version_number), 0) + 1 from app.quotations where root_quotation_id = v_source.root_quotation_id);

  update app.quotations
  set is_current = false, updated_at = now(), record_version = record_version + 1
  where id = v_current.id and is_current = true
  returning * into v_current;

  if not found then
    raise exception 'concurrent_revision: another revision was created concurrently for quotation root %', v_source.root_quotation_id
      using errcode = 'serialization_failure';
  end if;

  insert into app.quotations (
    id, tenant_id, quote_number, opportunity_id, source_opportunity_version, prospect_id, contact_id,
    customer_snapshot, currency, validity_from, validity_to, terms,
    root_quotation_id, version_number, is_current, revision_reason,
    owner_user_id, org_unit_id, created_by
  ) values (
    v_new_id, v_source.tenant_id, v_source.quote_number, v_source.opportunity_id, v_source.source_opportunity_version,
    v_source.prospect_id, v_source.contact_id, v_source.customer_snapshot, v_source.currency, now(), v_source.validity_to, v_source.terms,
    v_source.root_quotation_id, v_next_version, true, p_reason,
    v_source.owner_user_id, v_source.org_unit_id, p_actor_label
  )
  returning * into v_new;

  insert into app.quotation_lines (
    tenant_id, quotation_id, line_no, line_type, description, margin_calculation_id,
    quantity, unit_price, discount_pct, tax_pct, line_gross_amount, line_discount_amount, line_tax_amount, line_total,
    cost_amount_snapshot, margin_pct_snapshot, created_by
  )
  select
    tenant_id, v_new.id, line_no, line_type, description, margin_calculation_id,
    quantity, unit_price, discount_pct, tax_pct, line_gross_amount, line_discount_amount, line_tax_amount, line_total,
    cost_amount_snapshot, margin_pct_snapshot, p_actor_label
  from app.quotation_lines
  where quotation_id = v_source.id;

  v_new := app.recalculate_quotation_totals(v_new.id);

  update app.quotations set superseded_by_id = v_new_id where id = v_current.id;

  perform app.capture_audit_event(
    v_source.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_quotation_revision',
    'app.quotations', v_new.id, 'success', p_reason, to_jsonb(v_source), to_jsonb(v_new)
  );

  return v_new;
end;
$function$;

CREATE OR REPLACE FUNCTION app.create_sales_target(p_sales_plan_id uuid, p_pipeline_category_id uuid, p_metric_type text, p_org_unit_id uuid, p_owner_user_id uuid, p_target_value integer, p_actor_auth_user_id uuid, p_created_by text)
 RETURNS app.sales_targets
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_plan app.sales_plans;
  v_decision app.rbac_decision;
  v_target app.sales_targets;
begin
  select * into v_plan from app.sales_plans where id = p_sales_plan_id;
  if not found or not app.has_active_tenant_membership(v_plan.tenant_id, p_actor_auth_user_id) then
    raise exception 'sales_plan_not_found: %', p_sales_plan_id using errcode = 'no_data_found';
  end if;

  if v_plan.status <> 'draft' then
    raise exception 'invalid_transition: sales plan % is % -- targets can only be added while the plan is draft', p_sales_plan_id, v_plan.status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_plan.tenant_id, 'COM', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_plan.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_plan.tenant_id, v_plan.owner_user_id, app.lead_record_scope_org_unit_ids(v_plan.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access sales plan %', p_actor_auth_user_id, p_sales_plan_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_target_value < 0 then
    raise exception 'invalid_target_value: target_value must be non-negative' using errcode = 'check_violation';
  end if;

  insert into app.sales_targets (
    tenant_id, sales_plan_id, pipeline_category_id, metric_type, org_unit_id, owner_user_id, target_value, created_by
  ) values (
    v_plan.tenant_id, p_sales_plan_id, p_pipeline_category_id, p_metric_type, coalesce(p_org_unit_id, v_plan.org_unit_id), p_owner_user_id, p_target_value, p_created_by
  )
  returning * into v_target;

  perform app.capture_audit_event(
    v_plan.tenant_id, p_actor_auth_user_id, p_created_by, 'create_sales_target',
    'app.sales_targets', v_target.id, 'success', null, null, to_jsonb(v_target)
  );

  return v_target;
exception
  when unique_violation then
    raise exception 'duplicate_target: a target for this metric/organization/owner combination already exists on this plan'
      using errcode = 'unique_violation';
end;
$function$;

CREATE OR REPLACE FUNCTION app.hold_credit_profile(p_profile_id uuid, p_expected_version integer, p_reason text, p_reauth_confirmed_at timestamp with time zone, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.credit_profiles
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
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
  if not found or not app.has_active_tenant_membership(v_profile.tenant_id, p_actor_auth_user_id) then
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
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: hold_credit_profile target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_profile.tenant_id, p_actor_auth_user_id, p_actor_label, 'hold_credit_profile',
    'app.credit_profiles', v_profile.id, 'success', p_reason, null, jsonb_build_object('status', v_profile.status)
  );

  return v_profile;
end;
$function$;

CREATE OR REPLACE FUNCTION app.link_contact_to_record(p_contact_id uuid, p_related_type text, p_related_id uuid, p_role text, p_is_primary boolean, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.contact_links
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_contact app.contacts;
  v_ref record;
  v_link app.contact_links;
  v_decision app.rbac_decision;
begin
  select * into v_contact from app.contacts where id = p_contact_id;
  if not found or not app.has_active_tenant_membership(v_contact.tenant_id, p_actor_auth_user_id) then
    raise exception 'contact_not_found: %', p_contact_id using errcode = 'no_data_found';
  end if;

  select * into v_ref from app.resolve_commercial_record_ref(p_related_type, p_related_id);

  if v_contact.tenant_id <> v_ref.tenant_id then
    raise exception 'cross_tenant_link_denied: contact and record belong to different tenants'
      using errcode = 'insufficient_privilege';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_contact.tenant_id, 'COM', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_contact.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not (
    app.can_access_record(p_actor_auth_user_id, v_contact.tenant_id, v_contact.owner_user_id, app.lead_record_scope_org_unit_ids(v_contact.org_unit_id), null)
    and app.can_access_record(p_actor_auth_user_id, v_ref.tenant_id, v_ref.owner_user_id, app.lead_record_scope_org_unit_ids(v_ref.org_unit_id), null)
  ) then
    raise exception 'insufficient_authority: identity % cannot access both the contact and the record', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_link from app.contact_links
  where contact_id = p_contact_id and related_type = p_related_type and related_id = p_related_id and role = p_role;
  if found then
    return v_link;
  end if;

  insert into app.contact_links (tenant_id, contact_id, related_type, related_id, role, is_primary, created_by)
  values (v_contact.tenant_id, p_contact_id, p_related_type, p_related_id, p_role, coalesce(p_is_primary, false), p_actor_label)
  returning * into v_link;

  perform app.capture_audit_event(
    v_contact.tenant_id, p_actor_auth_user_id, p_actor_label, 'link_contact_to_record',
    'app.contact_links', v_link.id, 'success', null, null, to_jsonb(v_link)
  );

  return v_link;
exception
  when unique_violation then
    select * into v_link from app.contact_links
    where contact_id = p_contact_id and related_type = p_related_type and related_id = p_related_id and role = p_role;
    return v_link;
end;
$function$;

CREATE OR REPLACE FUNCTION app.override_margin_threshold(p_margin_calculation_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.margin_calculations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_calc app.margin_calculations;
  v_decision app.rbac_decision;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: overriding a margin threshold requires a non-empty reason'
      using errcode = 'not_null_violation';
  end if;

  select * into v_calc from app.margin_calculations where id = p_margin_calculation_id;
  if not found or not app.has_active_tenant_membership(v_calc.tenant_id, p_actor_auth_user_id) then
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
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: override_margin_threshold target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_calc.tenant_id, p_actor_auth_user_id, p_actor_label, 'override_margin_threshold',
    'app.margin_calculations', v_calc.id, 'success', p_reason, null, jsonb_build_object('threshold_outcome', v_calc.threshold_outcome)
  );

  return v_calc;
end;
$function$;

CREATE OR REPLACE FUNCTION app.prepare_job_order_handoff(p_quotation_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.job_order_handoffs
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'public', 'extensions', 'pg_temp'
AS $function$
declare
  v_quotation app.quotations;
  v_decision app.rbac_decision;
  v_conversion app.account_conversions;
  v_existing app.job_order_handoffs;
  v_payload jsonb;
  v_handoff app.job_order_handoffs;
begin
  select * into v_quotation from app.quotations where id = p_quotation_id;
  if not found or not app.has_active_tenant_membership(v_quotation.tenant_id, p_actor_auth_user_id) then
    raise exception 'quotation_not_found: %', p_quotation_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_quotation.tenant_id, 'COM', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_quotation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_quotation.tenant_id, v_quotation.owner_user_id, app.lead_record_scope_org_unit_ids(v_quotation.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access quotation %', p_actor_auth_user_id, p_quotation_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_existing from app.job_order_handoffs where tenant_id = v_quotation.tenant_id and quotation_id = p_quotation_id and purpose = 'job_order_draft';
  if found then
    if not app.has_view_selling_price(v_quotation.tenant_id, p_actor_auth_user_id) then
      v_existing.payload := null;
      v_existing.payload_hash := null;
    end if;
    return v_existing;
  end if;

  if not v_quotation.is_current then
    raise exception 'not_current_version: quotation % version % is not the current version', p_quotation_id, v_quotation.version_number using errcode = 'check_violation';
  end if;
  if v_quotation.status <> 'submitted' then
    raise exception 'quote_not_submitted: quotation % is % and cannot be handed off', p_quotation_id, v_quotation.status using errcode = 'check_violation';
  end if;
  if v_quotation.approval_status not in ('approved', 'not_required') then
    raise exception 'quote_not_approved: quotation % approval_status is %', p_quotation_id, v_quotation.approval_status using errcode = 'check_violation';
  end if;
  if v_quotation.customer_decision is distinct from 'accepted' then
    raise exception 'quote_not_accepted: quotation % has not been accepted by the customer', p_quotation_id using errcode = 'check_violation';
  end if;

  select * into v_conversion from app.account_conversions where quotation_id = p_quotation_id;
  if not found then
    raise exception 'account_not_converted: quotation % has not been converted to an account', p_quotation_id using errcode = 'check_violation';
  end if;

  v_payload := app.build_job_order_draft_payload(p_quotation_id);

  begin
    insert into app.job_order_handoffs (
      tenant_id, quotation_id, account_id, payload, payload_hash,
      prepared_by_auth_user_id, owner_user_id, org_unit_id, created_by
    ) values (
      v_quotation.tenant_id, p_quotation_id, v_conversion.account_id, v_payload, encode(digest(v_payload::text, 'sha256'), 'hex'),
      p_actor_auth_user_id, v_quotation.owner_user_id, v_quotation.org_unit_id, p_actor_label
    )
    returning * into v_handoff;
  exception
    when unique_violation then
      select * into v_existing from app.job_order_handoffs where tenant_id = v_quotation.tenant_id and quotation_id = p_quotation_id and purpose = 'job_order_draft';
      if found then
        if not app.has_view_selling_price(v_quotation.tenant_id, p_actor_auth_user_id) then
          v_existing.payload := null;
          v_existing.payload_hash := null;
        end if;
        return v_existing;
      end if;
      raise;
  end;

  perform app.capture_audit_event(
    v_quotation.tenant_id, p_actor_auth_user_id, p_actor_label, 'prepare_job_order_handoff',
    'app.job_order_handoffs', v_handoff.id, 'success', null, null,
    jsonb_build_object('quotation_id', p_quotation_id, 'account_id', v_conversion.account_id, 'payload_hash', v_handoff.payload_hash)
  );

  if not app.has_view_selling_price(v_quotation.tenant_id, p_actor_auth_user_id) then
    v_handoff.payload := null;
    v_handoff.payload_hash := null;
  end if;

  return v_handoff;
end;
$function$;

CREATE OR REPLACE FUNCTION app.publish_customer_contract(p_contract_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.customer_contracts
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_contract app.customer_contracts;
  v_decision app.rbac_decision;
  v_sibling app.customer_contracts;
  v_component_count integer;
begin
  select * into v_contract from app.customer_contracts where id = p_contract_id;
  if not found or not app.has_active_tenant_membership(v_contract.tenant_id, p_actor_auth_user_id) then
    raise exception 'contract_not_found: %', p_contract_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_contract.tenant_id, 'COM', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_contract.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_contract.record_version <> p_expected_version then
    raise exception 'stale_version: contract % expected version % but found %', p_contract_id, p_expected_version, v_contract.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_contract.status <> 'draft' then
    raise exception 'invalid_transition: contract % is % and cannot be published', p_contract_id, v_contract.status
      using errcode = 'check_violation';
  end if;

  select count(*) into v_component_count from app.customer_contract_price_components where contract_id = p_contract_id;
  if v_component_count = 0 then
    raise exception 'no_price_components: contract % has no price components to publish', p_contract_id
      using errcode = 'check_violation';
  end if;

  for v_sibling in
    select * from app.customer_contracts
    where root_contract_id = v_contract.root_contract_id
      and id <> v_contract.id
      and status = 'published'
    order by id
    for update
  loop
    if v_sibling.effective_from < coalesce(v_contract.effective_to, 'infinity'::timestamptz)
       and v_contract.effective_from < coalesce(v_sibling.effective_to, 'infinity'::timestamptz) then
      raise exception 'overlapping_active_version: contract % [%, %) overlaps already-published version % [%, %)',
        p_contract_id, v_contract.effective_from, v_contract.effective_to, v_sibling.id, v_sibling.effective_from, v_sibling.effective_to
        using errcode = 'check_violation';
    end if;
  end loop;

  update app.customer_contracts
  set status = 'published', updated_at = now(), record_version = record_version + 1
  where id = p_contract_id and record_version = p_expected_version
  returning * into v_contract;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: publish_customer_contract target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_contract.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_customer_contract',
    'app.customer_contracts', v_contract.id, 'success', null, null, jsonb_build_object('status', v_contract.status)
  );

  return v_contract;
end;
$function$;

CREATE OR REPLACE FUNCTION app.publish_margin_rule_version(p_rule_version_id uuid, p_expected_version integer, p_supersedes_version_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.margin_rule_versions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_rule app.margin_rule_versions;
  v_superseded app.margin_rule_versions;
  v_decision app.rbac_decision;
begin
  select * into v_rule from app.margin_rule_versions where id = p_rule_version_id;
  if not found or not app.has_active_tenant_membership(v_rule.tenant_id, p_actor_auth_user_id) then
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
    -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
    -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
    -- execution fell straight through with a NULL composite, so the audit trail gained a
    -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
    -- record instead of the 'stale_version' its own error contract already handles.
    if not found then
      raise exception 'stale_version: publish_margin_rule_version target row was concurrently modified (expected version %)', p_expected_version
        using errcode = 'serialization_failure';
    end if;
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
$function$;

CREATE OR REPLACE FUNCTION app.publish_quotation_approval_rule_version(p_rule_version_id uuid, p_expected_version integer, p_supersedes_version_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.quotation_approval_rules
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_rule app.quotation_approval_rules;
  v_superseded app.quotation_approval_rules;
  v_decision app.rbac_decision;
begin
  select * into v_rule from app.quotation_approval_rules where id = p_rule_version_id;
  if not found or not app.has_active_tenant_membership(v_rule.tenant_id, p_actor_auth_user_id) then
    raise exception 'quotation_approval_rule_not_found: %', p_rule_version_id using errcode = 'no_data_found';
  end if;

  if v_rule.record_version <> p_expected_version then
    raise exception 'stale_version: quotation approval rule % expected version % but found %', p_rule_version_id, p_expected_version, v_rule.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_rule.status <> 'draft' then
    raise exception 'invalid_transition: quotation approval rule % is % and cannot be published', p_rule_version_id, v_rule.status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_rule.tenant_id, 'COM', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_rule.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_supersedes_version_id is not null then
    select * into v_superseded from app.quotation_approval_rules where id = p_supersedes_version_id;
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
    update app.quotation_approval_rules set status = 'archived', updated_at = now(), record_version = record_version + 1 where id = p_supersedes_version_id;
  end if;

  begin
    update app.quotation_approval_rules
    set status = 'published', supersedes_version_id = p_supersedes_version_id, updated_at = now(), record_version = record_version + 1
    where id = p_rule_version_id and record_version = p_expected_version
    returning * into v_rule;
    -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
    -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
    -- execution fell straight through with a NULL composite, so the audit trail gained a
    -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
    -- record instead of the 'stale_version' its own error contract already handles.
    if not found then
      raise exception 'stale_version: publish_quotation_approval_rule_version target row was concurrently modified (expected version %)', p_expected_version
        using errcode = 'serialization_failure';
    end if;
  exception
    when unique_violation then
      raise exception 'active_rule_exists: tenant % already has a published quotation approval rule -- supply p_supersedes_version_id to replace it', v_rule.tenant_id
        using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    v_rule.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_quotation_approval_rule_version',
    'app.quotation_approval_rules', v_rule.id, 'success', null, null, jsonb_build_object('supersedes_version_id', p_supersedes_version_id)
  );

  return v_rule;
end;
$function$;

CREATE OR REPLACE FUNCTION app.publish_sales_plan(p_plan_id uuid, p_expected_version integer, p_supersedes_plan_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.sales_plans
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_plan app.sales_plans;
  v_superseded app.sales_plans;
  v_decision app.rbac_decision;
  v_overlap_count integer;
begin
  select * into v_plan from app.sales_plans where id = p_plan_id;
  if not found or not app.has_active_tenant_membership(v_plan.tenant_id, p_actor_auth_user_id) then
    raise exception 'sales_plan_not_found: %', p_plan_id using errcode = 'no_data_found';
  end if;

  if v_plan.record_version <> p_expected_version then
    raise exception 'stale_version: sales plan % expected version % but found %', p_plan_id, p_expected_version, v_plan.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_plan.status <> 'draft' then
    raise exception 'invalid_transition: sales plan % is % and cannot be published', p_plan_id, v_plan.status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_plan.tenant_id, 'COM', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_plan.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_plan.tenant_id, v_plan.owner_user_id, app.lead_record_scope_org_unit_ids(v_plan.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access sales plan %', p_actor_auth_user_id, p_plan_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_supersedes_plan_id is not null then
    select * into v_superseded from app.sales_plans where id = p_supersedes_plan_id;
    if not found then
      raise exception 'superseded_plan_not_found: %', p_supersedes_plan_id using errcode = 'no_data_found';
    end if;
    if v_superseded.tenant_id <> v_plan.tenant_id or v_superseded.org_unit_id is distinct from v_plan.org_unit_id then
      raise exception 'invalid_supersede: superseded plan must share tenant and organization scope'
        using errcode = 'check_violation';
    end if;
    if v_superseded.status <> 'published' then
      raise exception 'invalid_supersede: superseded plan % is not published (is %)', p_supersedes_plan_id, v_superseded.status
        using errcode = 'check_violation';
    end if;
  end if;

  select count(*) into v_overlap_count
  from app.sales_plans sp
  where sp.tenant_id = v_plan.tenant_id
    and sp.org_unit_id is not distinct from v_plan.org_unit_id
    and sp.status = 'published'
    and sp.id <> coalesce(p_supersedes_plan_id, '00000000-0000-0000-0000-000000000000'::uuid)
    and sp.period_start <= v_plan.period_end
    and sp.period_end >= v_plan.period_start;

  if v_overlap_count > 0 then
    raise exception 'overlapping_plan: another published plan already covers an overlapping period for this organization scope'
      using errcode = 'check_violation';
  end if;

  if p_supersedes_plan_id is not null then
    update app.sales_plans
    set status = 'archived', updated_at = now(), record_version = record_version + 1
    where id = p_supersedes_plan_id;
  end if;

  update app.sales_plans
  set status = 'published', supersedes_plan_id = p_supersedes_plan_id, updated_at = now(), record_version = record_version + 1
  where id = p_plan_id and record_version = p_expected_version
  returning * into v_plan;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: publish_sales_plan target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_plan.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_sales_plan',
    'app.sales_plans', v_plan.id, 'success', null, null, jsonb_build_object('supersedes_plan_id', p_supersedes_plan_id)
  );

  return v_plan;
end;
$function$;

CREATE OR REPLACE FUNCTION app.reject_rate_version(p_rate_version_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.vendor_rate_versions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_rate app.vendor_rate_versions;
begin
  -- ATW-032 (ISS-2026-032): this function's own authority check asks whether the CLAIMED
  -- actor is allowed, never whether the caller IS that actor. Without this line any
  -- authenticated session could pass a colleague's UUID and act as them.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: rejecting a rate version requires a non-empty reason'
      using errcode = 'not_null_violation';
  end if;

  select * into v_rate from app.vendor_rate_versions where id = p_rate_version_id;
  if not found or not app.has_active_tenant_membership(v_rate.tenant_id, p_actor_auth_user_id) then
    raise exception 'rate_version_not_found: %', p_rate_version_id using errcode = 'no_data_found';
  end if;

  if not app.is_support_grant_authority(p_actor_auth_user_id, v_rate.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_rate.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_rate.record_version <> p_expected_version then
    raise exception 'stale_version: rate version % expected version % but found %', p_rate_version_id, p_expected_version, v_rate.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_rate.approval_status <> 'pending_approval' then
    raise exception 'invalid_transition: rate version % is % and cannot be rejected', p_rate_version_id, v_rate.approval_status
      using errcode = 'check_violation';
  end if;

  update app.vendor_rate_versions
  set approval_status = 'rejected', rejected_reason = p_reason, updated_at = now(), record_version = record_version + 1
  where id = p_rate_version_id and record_version = p_expected_version
  returning * into v_rate;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: reject_rate_version target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_rate.tenant_id, p_actor_auth_user_id, p_actor_label, 'reject_rate_version',
    'app.vendor_rate_versions', v_rate.id, 'success', p_reason, null, jsonb_build_object('approval_status', v_rate.approval_status)
  );

  return v_rate;
end;
$function$;

CREATE OR REPLACE FUNCTION app.release_credit_profile(p_profile_id uuid, p_expected_version integer, p_reauth_confirmed_at timestamp with time zone, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.credit_profiles
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_profile app.credit_profiles;
  v_decision app.rbac_decision;
begin
  if p_reauth_confirmed_at is null or p_reauth_confirmed_at > now() or now() - p_reauth_confirmed_at > interval '5 minutes' then
    raise exception 'reauth_required: re-authentication must have completed within the last 5 minutes'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_profile from app.credit_profiles where id = p_profile_id;
  if not found or not app.has_active_tenant_membership(v_profile.tenant_id, p_actor_auth_user_id) then
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
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: release_credit_profile target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_profile.tenant_id, p_actor_auth_user_id, p_actor_label, 'release_credit_profile',
    'app.credit_profiles', v_profile.id, 'success', null, null, jsonb_build_object('status', v_profile.status)
  );

  return v_profile;
end;
$function$;

CREATE OR REPLACE FUNCTION app.remove_quotation_line(p_quotation_id uuid, p_expected_version integer, p_line_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.quotations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_quotation app.quotations;
  v_decision app.rbac_decision;
  v_deleted integer;
begin
  select * into v_quotation from app.quotations where id = p_quotation_id;
  if not found or not app.has_active_tenant_membership(v_quotation.tenant_id, p_actor_auth_user_id) then
    raise exception 'quotation_not_found: %', p_quotation_id using errcode = 'no_data_found';
  end if;

  if v_quotation.record_version <> p_expected_version then
    raise exception 'stale_version: quotation % expected version % but found %', p_quotation_id, p_expected_version, v_quotation.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_quotation.status <> 'draft' or not v_quotation.is_current then
    raise exception 'invalid_transition: quotation % is % (is_current=%) and cannot be edited', p_quotation_id, v_quotation.status, v_quotation.is_current
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_quotation.tenant_id, 'COM', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_quotation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_quotation.tenant_id, v_quotation.owner_user_id, app.lead_record_scope_org_unit_ids(v_quotation.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access quotation %', p_actor_auth_user_id, p_quotation_id
      using errcode = 'insufficient_privilege';
  end if;

  delete from app.quotation_lines where id = p_line_id and quotation_id = p_quotation_id;
  get diagnostics v_deleted = row_count;
  if v_deleted = 0 then
    raise exception 'quotation_line_not_found: %', p_line_id using errcode = 'no_data_found';
  end if;

  v_quotation := app.recalculate_quotation_totals(p_quotation_id);

  perform app.capture_audit_event(
    v_quotation.tenant_id, p_actor_auth_user_id, p_actor_label, 'remove_quotation_line',
    'app.quotations', v_quotation.id, 'success', null, null, jsonb_build_object('line_id', p_line_id)
  );

  return v_quotation;
end;
$function$;

CREATE OR REPLACE FUNCTION app.request_costing(p_opportunity_id uuid, p_components jsonb, p_due_at timestamp with time zone, p_actor_auth_user_id uuid, p_created_by text)
 RETURNS app.costing_requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_opportunity app.opportunities;
  v_decision app.rbac_decision;
  v_ready boolean;
  v_missing text[];
  v_request app.costing_requests;
  v_component jsonb;
begin
  select * into v_opportunity from app.opportunities where id = p_opportunity_id;
  if not found or not app.has_active_tenant_membership(v_opportunity.tenant_id, p_actor_auth_user_id) then
    raise exception 'opportunity_not_found: %', p_opportunity_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_opportunity.tenant_id, 'COM', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_opportunity.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Reuses app.get_opportunity_costing_readiness (COM-147) directly -- it already
  -- performs its own app.can_access_record check against this opportunity, so no
  -- duplicate access check is needed here.
  select ready, missing into v_ready, v_missing from app.get_opportunity_costing_readiness(p_opportunity_id, p_actor_auth_user_id);
  if not v_ready then
    raise exception 'requirements_incomplete: opportunity % is missing %', p_opportunity_id, array_to_string(v_missing, ', ')
      using errcode = 'check_violation';
  end if;

  begin
    insert into app.costing_requests (
      tenant_id, opportunity_id, source_opportunity_version, requirements_snapshot, due_at,
      owner_user_id, org_unit_id, created_by
    ) values (
      v_opportunity.tenant_id, p_opportunity_id, v_opportunity.record_version, v_opportunity.requirements, p_due_at,
      v_opportunity.owner_user_id, v_opportunity.org_unit_id, p_created_by
    )
    returning * into v_request;
  exception
    when unique_violation then
      select * into v_request from app.costing_requests
      where tenant_id = v_opportunity.tenant_id and opportunity_id = p_opportunity_id and source_opportunity_version = v_opportunity.record_version;
      return v_request;
  end;

  if p_components is not null then
    for v_component in select * from jsonb_array_elements(p_components)
    loop
      insert into app.costing_request_components (tenant_id, costing_request_id, component_code, description, quantity, unit)
      values (
        v_request.tenant_id, v_request.id,
        v_component ->> 'code',
        v_component ->> 'description',
        nullif(v_component ->> 'quantity', '')::numeric,
        v_component ->> 'unit'
      );
    end loop;
  end if;

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_created_by, 'request_costing',
    'app.costing_requests', v_request.id, 'success', null, null, to_jsonb(v_request)
  );

  return v_request;
end;
$function$;

CREATE OR REPLACE FUNCTION app.retire_customer_contract(p_contract_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.customer_contracts
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_contract app.customer_contracts;
  v_decision app.rbac_decision;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: retiring a contract requires a non-empty reason'
      using errcode = 'not_null_violation';
  end if;

  select * into v_contract from app.customer_contracts where id = p_contract_id;
  if not found or not app.has_active_tenant_membership(v_contract.tenant_id, p_actor_auth_user_id) then
    raise exception 'contract_not_found: %', p_contract_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_contract.tenant_id, 'COM', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_contract.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_contract.record_version <> p_expected_version then
    raise exception 'stale_version: contract % expected version % but found %', p_contract_id, p_expected_version, v_contract.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_contract.status <> 'published' then
    raise exception 'invalid_transition: contract % is % and only a published contract can be retired', p_contract_id, v_contract.status
      using errcode = 'check_violation';
  end if;

  update app.customer_contracts
  set status = 'retired', retired_reason = p_reason, updated_at = now(), record_version = record_version + 1
  where id = p_contract_id and record_version = p_expected_version
  returning * into v_contract;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: retire_customer_contract target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_contract.tenant_id, p_actor_auth_user_id, p_actor_label, 'retire_customer_contract',
    'app.customer_contracts', v_contract.id, 'success', p_reason, null, jsonb_build_object('status', v_contract.status)
  );

  return v_contract;
end;
$function$;

CREATE OR REPLACE FUNCTION app.revise_costing_request(p_request_id uuid, p_actor_auth_user_id uuid, p_created_by text)
 RETURNS app.costing_requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_source app.costing_requests;
  v_opportunity app.opportunities;
  v_decision app.rbac_decision;
  v_ready boolean;
  v_missing text[];
  v_new_request app.costing_requests;
begin
  select * into v_source from app.costing_requests where id = p_request_id;
  if not found or not app.has_active_tenant_membership(v_source.tenant_id, p_actor_auth_user_id) then
    raise exception 'costing_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;

  if v_source.status in ('cancelled', 'superseded') then
    raise exception 'invalid_transition: costing request % is % and cannot be revised', p_request_id, v_source.status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_source.tenant_id, 'COM', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_source.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_source.tenant_id, v_source.owner_user_id, app.lead_record_scope_org_unit_ids(v_source.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access costing request %', p_actor_auth_user_id, p_request_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_opportunity from app.opportunities where id = v_source.opportunity_id;

  select ready, missing into v_ready, v_missing from app.get_opportunity_costing_readiness(v_opportunity.id, p_actor_auth_user_id);
  if not v_ready then
    raise exception 'requirements_incomplete: opportunity % is missing %', v_opportunity.id, array_to_string(v_missing, ', ')
      using errcode = 'check_violation';
  end if;

  begin
    insert into app.costing_requests (
      tenant_id, opportunity_id, source_opportunity_version, requirements_snapshot, due_at,
      revised_from_id, owner_user_id, org_unit_id, created_by
    ) values (
      v_opportunity.tenant_id, v_opportunity.id, v_opportunity.record_version, v_opportunity.requirements, v_source.due_at,
      v_source.id, v_opportunity.owner_user_id, v_opportunity.org_unit_id, p_created_by
    )
    returning * into v_new_request;
  exception
    when unique_violation then
      raise exception 'no_new_version: opportunity % has not changed since costing request % -- nothing to revise', v_opportunity.id, p_request_id
        using errcode = 'check_violation';
  end;

  insert into app.costing_request_components (tenant_id, costing_request_id, component_code, description, quantity, unit)
  select v_new_request.tenant_id, v_new_request.id, component_code, description, quantity, unit
  from app.costing_request_components
  where costing_request_id = v_source.id;

  update app.costing_requests
  set status = 'superseded', updated_at = now(), record_version = record_version + 1
  where id = v_source.id;

  perform app.capture_audit_event(
    v_new_request.tenant_id, p_actor_auth_user_id, p_created_by, 'revise_costing_request',
    'app.costing_requests', v_new_request.id, 'success', null, null, jsonb_build_object('revised_from_id', v_source.id)
  );

  return v_new_request;
end;
$function$;

CREATE OR REPLACE FUNCTION app.submit_costing_response(p_request_id uuid, p_source_type text, p_vendor_ref text, p_currency text, p_effective_at timestamp with time zone, p_expiry_at timestamp with time zone, p_components jsonb, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.costing_responses
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_request app.costing_requests;
  v_decision_edit app.rbac_decision;
  v_response app.costing_responses;
  v_component jsonb;
  v_component_id uuid;
  v_amount numeric;
  v_total numeric := 0;
begin
  select * into v_request from app.costing_requests where id = p_request_id;
  if not found or not app.has_active_tenant_membership(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'costing_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;

  if v_request.status in ('cancelled', 'superseded') then
    raise exception 'invalid_transition: costing request % is % and cannot accept a response', p_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  v_decision_edit := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'COM', 'Edit');
  if not v_decision_edit.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision_edit.reason, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.has_view_cost(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks COM:View cost required to submit a cost response', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_request.tenant_id, v_request.owner_user_id, app.lead_record_scope_org_unit_ids(v_request.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access costing request %', p_actor_auth_user_id, p_request_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_components is null or jsonb_array_length(p_components) = 0 then
    raise exception 'components_required: a costing response requires at least one priced component'
      using errcode = 'not_null_violation';
  end if;

  insert into app.costing_responses (
    tenant_id, costing_request_id, source_type, vendor_ref, currency, effective_at, expiry_at, submitted_by
  ) values (
    v_request.tenant_id, p_request_id, p_source_type, p_vendor_ref, p_currency,
    coalesce(p_effective_at, now()), p_expiry_at, p_actor_label
  )
  returning * into v_response;

  for v_component in select * from jsonb_array_elements(p_components)
  loop
    v_component_id := (v_component ->> 'requestComponentId')::uuid;
    v_amount := (v_component ->> 'amount')::numeric;

    if not exists (select 1 from app.costing_request_components where id = v_component_id and costing_request_id = p_request_id) then
      raise exception 'unknown_request_component: % does not belong to costing request %', v_component_id, p_request_id
        using errcode = 'check_violation';
    end if;

    insert into app.costing_response_components (tenant_id, costing_response_id, costing_request_component_id, amount)
    values (v_request.tenant_id, v_response.id, v_component_id, v_amount);

    v_total := v_total + v_amount;
  end loop;

  update app.costing_responses set total_amount = v_total where id = v_response.id returning * into v_response;

  if v_request.status in ('pending', 'assigned') then
    update app.costing_requests set status = 'responded', updated_at = now(), record_version = record_version + 1 where id = p_request_id;
  end if;

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_costing_response',
    'app.costing_responses', v_response.id, 'success', null, null,
    jsonb_build_object('costing_request_id', p_request_id, 'source_type', p_source_type, 'total_amount', v_total, 'currency', p_currency)
  );

  return v_response;
end;
$function$;

CREATE OR REPLACE FUNCTION app.submit_quotation(p_quotation_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.quotations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_quotation app.quotations;
  v_decision app.rbac_decision;
  v_ready boolean;
  v_reasons text[];
  v_required boolean;
  v_approval_reasons text[];
  v_rule_version_id uuid;
  v_approval_config_version_id uuid;
  v_request app.approval_requests;
begin
  select * into v_quotation from app.quotations where id = p_quotation_id;
  if not found or not app.has_active_tenant_membership(v_quotation.tenant_id, p_actor_auth_user_id) then
    raise exception 'quotation_not_found: %', p_quotation_id using errcode = 'no_data_found';
  end if;

  if v_quotation.record_version <> p_expected_version then
    raise exception 'stale_version: quotation % expected version % but found %', p_quotation_id, p_expected_version, v_quotation.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_quotation.status <> 'draft' or not v_quotation.is_current then
    raise exception 'invalid_transition: quotation % is % (is_current=%) and cannot be submitted', p_quotation_id, v_quotation.status, v_quotation.is_current
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_quotation.tenant_id, 'COM', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_quotation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_quotation.tenant_id, v_quotation.owner_user_id, app.lead_record_scope_org_unit_ids(v_quotation.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access quotation %', p_actor_auth_user_id, p_quotation_id
      using errcode = 'insufficient_privilege';
  end if;

  select r.ready, r.blocking_reasons into v_ready, v_reasons from app.get_quotation_submission_readiness(p_quotation_id, p_actor_auth_user_id) r;
  if not v_ready then
    raise exception 'submission_not_ready: quotation % is not ready to submit (%)', p_quotation_id, array_to_string(v_reasons, ', ')
      using errcode = 'check_violation';
  end if;

  select e.required, e.reasons, e.rule_version_id into v_required, v_approval_reasons, v_rule_version_id
  from app.evaluate_quotation_approval_requirement(p_quotation_id, p_actor_auth_user_id) e;

  if v_required then
    select cv.id into v_approval_config_version_id
    from app.config_versions cv
    join app.config_objects co on co.id = cv.config_object_id
    where co.config_type_code = app._resolve_approval_config_type_code(v_quotation.tenant_id, 'quotation') and co.tenant_id = v_quotation.tenant_id and co.scope_level = 'tenant' and cv.status = 'published';

    if v_approval_config_version_id is null then
      raise exception 'approval_definition_not_configured: tenant % crossed an approval threshold but has no published quotation approval routing definition', v_quotation.tenant_id
        using errcode = 'check_violation';
    end if;

    select * into v_request from app.request_approval(
      v_approval_config_version_id, v_quotation.tenant_id, 'quotation', p_quotation_id,
      p_quotation_id::text, p_actor_auth_user_id, p_actor_label
    );

    update app.quotations
    set status = 'submitted', submitted_at = now(), submitted_by = p_actor_label,
        approval_status = 'pending', approval_request_id = v_request.id,
        approval_rule_version_id = v_rule_version_id, approval_required_reasons = v_approval_reasons,
        updated_at = now(), record_version = record_version + 1
    where id = p_quotation_id and record_version = p_expected_version
    returning * into v_quotation;
    -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
    -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
    -- execution fell straight through with a NULL composite, so the audit trail gained a
    -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
    -- record instead of the 'stale_version' its own error contract already handles.
    if not found then
      raise exception 'stale_version: submit_quotation target row was concurrently modified (expected version %)', p_expected_version
        using errcode = 'serialization_failure';
    end if;
  else
    update app.quotations
    set status = 'submitted', submitted_at = now(), submitted_by = p_actor_label,
        approval_status = 'approved', approval_request_id = null,
        approval_rule_version_id = v_rule_version_id, approval_required_reasons = v_approval_reasons,
        updated_at = now(), record_version = record_version + 1
    where id = p_quotation_id and record_version = p_expected_version
    returning * into v_quotation;
    -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
    -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
    -- execution fell straight through with a NULL composite, so the audit trail gained a
    -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
    -- record instead of the 'stale_version' its own error contract already handles.
    if not found then
      raise exception 'stale_version: submit_quotation target row was concurrently modified (expected version %)', p_expected_version
        using errcode = 'serialization_failure';
    end if;
  end if;

  perform app.capture_audit_event(
    v_quotation.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_quotation',
    'app.quotations', v_quotation.id, 'success', null, null, to_jsonb(v_quotation)
  );

  return v_quotation;
end;
$function$;

CREATE OR REPLACE FUNCTION app.transition_opportunity_stage(p_opportunity_id uuid, p_expected_version integer, p_new_stage text, p_probability integer, p_close_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.opportunities
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_opportunity app.opportunities;
  v_decision app.rbac_decision;
  v_default_probability integer;
  v_probability integer;
begin
  select * into v_opportunity from app.opportunities where id = p_opportunity_id;
  if not found or not app.has_active_tenant_membership(v_opportunity.tenant_id, p_actor_auth_user_id) then
    raise exception 'opportunity_not_found: %', p_opportunity_id using errcode = 'no_data_found';
  end if;

  if v_opportunity.record_version <> p_expected_version then
    raise exception 'stale_version: opportunity % expected version % but found %', p_opportunity_id, p_expected_version, v_opportunity.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_opportunity.stage in ('won', 'lost') then
    raise exception 'invalid_transition: opportunity % is closed (%) and cannot change stage again', p_opportunity_id, v_opportunity.stage
      using errcode = 'check_violation';
  end if;

  if p_new_stage not in ('qualifying', 'requirements_gathering', 'ready_for_costing', 'won', 'lost') then
    raise exception 'invalid_stage: % is not a canonical opportunity stage', p_new_stage using errcode = 'check_violation';
  end if;

  if p_new_stage in ('won', 'lost') and (p_close_reason is null or length(trim(p_close_reason)) = 0) then
    raise exception 'reason_required: closing an opportunity as % requires a non-empty reason', p_new_stage
      using errcode = 'not_null_violation';
  end if;

  -- Managers move/close by policy (Prompt 147 §26): closing to a terminal stage requires
  -- COM:Approve; any other forward/lateral stage move requires the ordinary COM:Edit.
  v_decision := app.evaluate_permission(
    p_actor_auth_user_id, v_opportunity.tenant_id, 'COM',
    case when p_new_stage in ('won', 'lost') then 'Approve' else 'Edit' end
  );
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks required COM permission (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_opportunity.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_opportunity.tenant_id, v_opportunity.owner_user_id, app.lead_record_scope_org_unit_ids(v_opportunity.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access opportunity %', p_actor_auth_user_id, p_opportunity_id
      using errcode = 'insufficient_privilege';
  end if;

  v_default_probability := case p_new_stage
    when 'qualifying' then 10
    when 'requirements_gathering' then 30
    when 'ready_for_costing' then 60
    when 'won' then 100
    when 'lost' then 0
  end;
  v_probability := coalesce(p_probability, v_default_probability);
  if v_probability < 0 or v_probability > 100 then
    raise exception 'invalid_probability: % is not between 0 and 100', v_probability using errcode = 'check_violation';
  end if;

  update app.opportunities
  set stage = p_new_stage,
      probability = v_probability,
      close_reason = case when p_new_stage in ('won', 'lost') then p_close_reason else close_reason end,
      updated_at = now(),
      record_version = record_version + 1
  where id = p_opportunity_id and record_version = p_expected_version
  returning * into v_opportunity;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: transition_opportunity_stage target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.opportunity_stage_history (tenant_id, opportunity_id, from_stage, to_stage, probability, reason, changed_by)
  values (v_opportunity.tenant_id, v_opportunity.id, v_opportunity.stage, p_new_stage, v_probability, p_close_reason, p_actor_label);

  perform app.capture_audit_event(
    v_opportunity.tenant_id, p_actor_auth_user_id, p_actor_label, 'transition_opportunity_stage',
    'app.opportunities', v_opportunity.id, 'success', null, null,
    jsonb_build_object('to_stage', p_new_stage, 'probability', v_probability, 'close_reason', p_close_reason)
  );

  return v_opportunity;
end;
$function$;

CREATE OR REPLACE FUNCTION app.unlink_contact_from_record(p_link_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_link app.contact_links;
  v_ref record;
  v_decision app.rbac_decision;
begin
  select * into v_link from app.contact_links where id = p_link_id;
  if not found or not app.has_active_tenant_membership(v_link.tenant_id, p_actor_auth_user_id) then
    raise exception 'contact_link_not_found: %', p_link_id using errcode = 'no_data_found';
  end if;

  select * into v_ref from app.resolve_commercial_record_ref(v_link.related_type, v_link.related_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_link.tenant_id, 'COM', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_link.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_ref.tenant_id, v_ref.owner_user_id, app.lead_record_scope_org_unit_ids(v_ref.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access the linked record', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  delete from app.contact_links where id = p_link_id;

  perform app.capture_audit_event(
    v_link.tenant_id, p_actor_auth_user_id, p_actor_label, 'unlink_contact_from_record',
    'app.contact_links', p_link_id, 'success', null, to_jsonb(v_link), null
  );
end;
$function$;

CREATE OR REPLACE FUNCTION app.update_opportunity(p_opportunity_id uuid, p_expected_version integer, p_name text, p_requirements jsonb, p_next_action text, p_next_action_due_at timestamp with time zone, p_value_amount numeric, p_value_currency text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.opportunities
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_opportunity app.opportunities;
  v_decision app.rbac_decision;
begin
  select * into v_opportunity from app.opportunities where id = p_opportunity_id;
  if not found or not app.has_active_tenant_membership(v_opportunity.tenant_id, p_actor_auth_user_id) then
    raise exception 'opportunity_not_found: %', p_opportunity_id using errcode = 'no_data_found';
  end if;

  if v_opportunity.record_version <> p_expected_version then
    raise exception 'stale_version: opportunity % expected version % but found %', p_opportunity_id, p_expected_version, v_opportunity.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_opportunity.stage in ('won', 'lost') then
    raise exception 'invalid_transition: opportunity % is closed (%) and cannot be edited', p_opportunity_id, v_opportunity.stage
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_opportunity.tenant_id, 'COM', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_opportunity.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_opportunity.tenant_id, v_opportunity.owner_user_id, app.lead_record_scope_org_unit_ids(v_opportunity.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access opportunity %', p_actor_auth_user_id, p_opportunity_id
      using errcode = 'insufficient_privilege';
  end if;

  if (
    (p_value_amount is not null and p_value_amount is distinct from v_opportunity.value_amount)
    or (p_value_currency is not null and p_value_currency is distinct from v_opportunity.value_currency)
  ) and not app.has_view_selling_price(v_opportunity.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks COM:View selling price required to set opportunity value', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.opportunities
  set name = coalesce(p_name, name),
      requirements = coalesce(p_requirements, requirements),
      next_action = coalesce(p_next_action, next_action),
      next_action_due_at = coalesce(p_next_action_due_at, next_action_due_at),
      value_amount = coalesce(p_value_amount, value_amount),
      value_currency = coalesce(p_value_currency, value_currency),
      updated_at = now(),
      record_version = record_version + 1
  where id = p_opportunity_id and record_version = p_expected_version
  returning * into v_opportunity;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: update_opportunity target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_opportunity.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_opportunity',
    'app.opportunities', v_opportunity.id, 'success', null, null, to_jsonb(v_opportunity)
  );

  return v_opportunity;
end;
$function$;

CREATE OR REPLACE FUNCTION app.update_pipeline_category(p_category_id uuid, p_expected_version integer, p_label text, p_sort_order integer, p_is_active boolean, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.pipeline_categories
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_category app.pipeline_categories;
  v_decision app.rbac_decision;
begin
  select * into v_category from app.pipeline_categories where id = p_category_id;
  if not found or not app.has_active_tenant_membership(v_category.tenant_id, p_actor_auth_user_id) then
    raise exception 'pipeline_category_not_found: %', p_category_id using errcode = 'no_data_found';
  end if;

  if v_category.record_version <> p_expected_version then
    raise exception 'stale_version: pipeline category % expected version % but found %', p_category_id, p_expected_version, v_category.record_version
      using errcode = 'serialization_failure';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_category.tenant_id, 'COM', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_category.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.pipeline_categories
  set label = coalesce(p_label, label),
      sort_order = coalesce(p_sort_order, sort_order),
      is_active = coalesce(p_is_active, is_active),
      updated_at = now(),
      record_version = record_version + 1
  where id = p_category_id and record_version = p_expected_version
  returning * into v_category;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: update_pipeline_category target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_category.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_pipeline_category',
    'app.pipeline_categories', v_category.id, 'success', null, null, to_jsonb(v_category)
  );

  return v_category;
end;
$function$;

CREATE OR REPLACE FUNCTION app.update_quotation_terms(p_quotation_id uuid, p_expected_version integer, p_currency text, p_validity_from timestamp with time zone, p_validity_to timestamp with time zone, p_terms jsonb, p_contact_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.quotations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_quotation app.quotations;
  v_decision app.rbac_decision;
  v_allowed_keys text[] := array['payment_terms', 'incoterm', 'notes'];
  v_key text;
  v_line_currency_mismatch boolean;
begin
  select * into v_quotation from app.quotations where id = p_quotation_id;
  if not found or not app.has_active_tenant_membership(v_quotation.tenant_id, p_actor_auth_user_id) then
    raise exception 'quotation_not_found: %', p_quotation_id using errcode = 'no_data_found';
  end if;

  if v_quotation.record_version <> p_expected_version then
    raise exception 'stale_version: quotation % expected version % but found %', p_quotation_id, p_expected_version, v_quotation.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_quotation.status <> 'draft' or not v_quotation.is_current then
    raise exception 'invalid_transition: quotation % is % (is_current=%) and cannot be edited', p_quotation_id, v_quotation.status, v_quotation.is_current
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_quotation.tenant_id, 'COM', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_quotation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_quotation.tenant_id, v_quotation.owner_user_id, app.lead_record_scope_org_unit_ids(v_quotation.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access quotation %', p_actor_auth_user_id, p_quotation_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then
    raise exception 'invalid_currency: % is not a 3-letter ISO currency code', p_currency using errcode = 'check_violation';
  end if;

  if p_validity_from is null or p_validity_to is null or p_validity_to <= p_validity_from then
    raise exception 'invalid_validity: validity_to must be after validity_from' using errcode = 'check_violation';
  end if;

  if jsonb_typeof(coalesce(p_terms, '{}'::jsonb)) <> 'object' then
    raise exception 'invalid_terms: terms must be a JSON object' using errcode = 'check_violation';
  end if;

  for v_key in select jsonb_object_keys(coalesce(p_terms, '{}'::jsonb)) loop
    if not (v_key = any (v_allowed_keys)) then
      raise exception 'unknown_terms_key: % is not a whitelisted terms key', v_key using errcode = 'check_violation';
    end if;
  end loop;

  if p_contact_id is not null and not exists (select 1 from app.contacts where id = p_contact_id and tenant_id = v_quotation.tenant_id) then
    raise exception 'contact_not_found: %', p_contact_id using errcode = 'no_data_found';
  end if;

  select exists (
    select 1 from app.quotation_lines ql
    join app.margin_calculations mc on mc.id = ql.margin_calculation_id
    where ql.quotation_id = p_quotation_id and mc.sell_currency <> p_currency
  ) into v_line_currency_mismatch;

  if v_line_currency_mismatch then
    raise exception 'mixed_currency: quotation % has lines sourced from a different currency than %', p_quotation_id, p_currency
      using errcode = 'check_violation';
  end if;

  update app.quotations
  set currency = p_currency, validity_from = p_validity_from, validity_to = p_validity_to,
      terms = coalesce(p_terms, '{}'::jsonb), contact_id = p_contact_id,
      updated_at = now(), record_version = record_version + 1
  where id = p_quotation_id and record_version = p_expected_version
  returning * into v_quotation;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: update_quotation_terms target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_quotation.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_quotation_terms',
    'app.quotations', v_quotation.id, 'success', null, null, to_jsonb(v_quotation)
  );

  return v_quotation;
end;
$function$;

CREATE OR REPLACE FUNCTION app.update_sales_target(p_target_id uuid, p_expected_version integer, p_target_value integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.sales_targets
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_target app.sales_targets;
  v_plan app.sales_plans;
  v_decision app.rbac_decision;
begin
  select * into v_target from app.sales_targets where id = p_target_id;
  if not found or not app.has_active_tenant_membership(v_target.tenant_id, p_actor_auth_user_id) then
    raise exception 'sales_target_not_found: %', p_target_id using errcode = 'no_data_found';
  end if;

  if v_target.record_version <> p_expected_version then
    raise exception 'stale_version: sales target % expected version % but found %', p_target_id, p_expected_version, v_target.record_version
      using errcode = 'serialization_failure';
  end if;

  select * into v_plan from app.sales_plans where id = v_target.sales_plan_id;
  if v_plan.status <> 'draft' then
    raise exception 'invalid_transition: sales plan % is % -- targets can only be edited while the plan is draft', v_plan.id, v_plan.status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_target.tenant_id, 'COM', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_target.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_target.tenant_id, v_target.owner_user_id, app.lead_record_scope_org_unit_ids(v_target.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access sales target %', p_actor_auth_user_id, p_target_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_target_value < 0 then
    raise exception 'invalid_target_value: target_value must be non-negative' using errcode = 'check_violation';
  end if;

  update app.sales_targets
  set target_value = p_target_value, updated_at = now(), record_version = record_version + 1
  where id = p_target_id and record_version = p_expected_version
  returning * into v_target;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: update_sales_target target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_target.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_sales_target',
    'app.sales_targets', v_target.id, 'success', null, null, jsonb_build_object('target_value', p_target_value)
  );

  return v_target;
end;
$function$;

CREATE OR REPLACE FUNCTION app.update_win_loss_reason(p_reason_id uuid, p_expected_version integer, p_label text, p_is_active boolean, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.win_loss_reasons
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_reason app.win_loss_reasons;
  v_decision app.rbac_decision;
begin
  select * into v_reason from app.win_loss_reasons where id = p_reason_id;
  if not found or not app.has_active_tenant_membership(v_reason.tenant_id, p_actor_auth_user_id) then
    raise exception 'win_loss_reason_not_found: %', p_reason_id using errcode = 'no_data_found';
  end if;

  if v_reason.record_version <> p_expected_version then
    raise exception 'stale_version: win/loss reason % expected version % but found %', p_reason_id, p_expected_version, v_reason.record_version
      using errcode = 'serialization_failure';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_reason.tenant_id, 'COM', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_reason.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.win_loss_reasons
  set label = coalesce(p_label, label),
      is_active = coalesce(p_is_active, is_active),
      updated_at = now(),
      record_version = record_version + 1
  where id = p_reason_id and record_version = p_expected_version
  returning * into v_reason;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: update_win_loss_reason target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_reason.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_win_loss_reason',
    'app.win_loss_reasons', v_reason.id, 'success', null, null, to_jsonb(v_reason)
  );

  return v_reason;
end;
$function$;

CREATE OR REPLACE FUNCTION app.withdraw_rate_version(p_rate_version_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.vendor_rate_versions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_rate app.vendor_rate_versions;
begin
  -- ATW-032 (ISS-2026-032): this function's own authority check asks whether the CLAIMED
  -- actor is allowed, never whether the caller IS that actor. Without this line any
  -- authenticated session could pass a colleague's UUID and act as them.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: withdrawing a rate version requires a non-empty reason'
      using errcode = 'not_null_violation';
  end if;

  select * into v_rate from app.vendor_rate_versions where id = p_rate_version_id;
  if not found or not app.has_active_tenant_membership(v_rate.tenant_id, p_actor_auth_user_id) then
    raise exception 'rate_version_not_found: %', p_rate_version_id using errcode = 'no_data_found';
  end if;

  if not app.is_support_grant_authority(p_actor_auth_user_id, v_rate.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_rate.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_rate.record_version <> p_expected_version then
    raise exception 'stale_version: rate version % expected version % but found %', p_rate_version_id, p_expected_version, v_rate.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_rate.approval_status <> 'approved' then
    raise exception 'invalid_transition: rate version % is % and only an approved rate can be withdrawn', p_rate_version_id, v_rate.approval_status
      using errcode = 'check_violation';
  end if;

  update app.vendor_rate_versions
  set approval_status = 'withdrawn', withdrawn_reason = p_reason, updated_at = now(), record_version = record_version + 1
  where id = p_rate_version_id and record_version = p_expected_version
  returning * into v_rate;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: withdraw_rate_version target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_rate.tenant_id, p_actor_auth_user_id, p_actor_label, 'withdraw_rate_version',
    'app.vendor_rate_versions', v_rate.id, 'success', p_reason, null, jsonb_build_object('approval_status', v_rate.approval_status)
  );

  return v_rate;
end;
$function$;

