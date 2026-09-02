-- ISS-2026-146 -- cross-tenant tenant_id disclosure via exception message text.
-- Continuation pass (Operations module -- core operations capabilities, not
-- Advanced TMS/WMS, which remains open for a future pass), reusing the SAME
-- already-established, already-precedented fix as 20260902100000-20260902104000 and
-- this same day's 20260902200000 (Commercial): fold
-- app.has_active_tenant_membership(<row>.tenant_id, p_actor_auth_user_id) into the
-- SAME not-found branch the row-miss case already raises, using the identical generic
-- message/errcode (no_data_found) a genuinely nonexistent id would already produce. A
-- genuine same-tenant member who simply lacks the specific role authority is
-- completely unaffected -- same message, same errcode, same behavior as before; only a
-- caller with NO relationship to the tenant sees a different (and less disclosing)
-- outcome. No permission check itself is weakened; only the ordering relative to a
-- tenant-membership pre-check moved.
--
-- Every function below is CREATE OR REPLACE against its CURRENT, live body (fetched
-- via pg_get_functiondef immediately before writing this migration, not reconstructed
-- from a possibly-stale migration file) -- signatures are unchanged throughout, so
-- grants are unaffected.
--
-- Scope note: 1 Operations RISK_UNSCOPED_LOOKUP function is deliberately NOT included
-- here (app.remove_actual_cost_component) -- its row is looked up via a foreign-key
-- derived id (v_component.actual_cost_id) with no pre-existing "if not found" branch to
-- fold into, same reasoning as this same day's Commercial migration's own scope note.

CREATE OR REPLACE FUNCTION app.acknowledge_exception(p_exception_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.operational_exceptions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_exception app.operational_exceptions;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  select * into v_exception from app.operational_exceptions where id = p_exception_id;
  if not found or not app.has_active_tenant_membership(v_exception.tenant_id, p_actor_auth_user_id) then
    raise exception 'exception_not_found: %', p_exception_id using errcode = 'no_data_found';
  end if;
  if v_exception.record_version <> p_expected_version then
    raise exception 'stale_version: exception % expected version % but found %', p_exception_id, p_expected_version, v_exception.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_exception.status not in ('open', 'reopened') then
    raise exception 'invalid_transition: exception % is % and cannot be acknowledged', p_exception_id, v_exception.status
      using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_exception.shipment_order_id;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_exception.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_exception.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_exception.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.operational_exceptions
  set status = 'acknowledged'
  where id = p_exception_id and record_version = p_expected_version
  returning * into v_exception;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: acknowledge_exception target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_exception.tenant_id, p_actor_auth_user_id, p_actor_label, 'acknowledge_exception',
    'app.operational_exceptions', v_exception.id, 'success', null, null, '{}'::jsonb
  );

  return v_exception;
end;
$function$;

CREATE OR REPLACE FUNCTION app.add_actual_cost_component(p_actual_cost_id uuid, p_category text, p_source_type text, p_vendor_id uuid, p_assignment_id uuid, p_document_file_id uuid, p_description text, p_quantity numeric, p_uom text, p_rate numeric, p_minimum_charge numeric, p_surcharge numeric, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.shipment_actual_cost_components
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_cost app.shipment_actual_costs;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_existing app.shipment_actual_cost_components;
  v_amount numeric(14, 2);
  v_component app.shipment_actual_cost_components;
begin
  select * into v_cost from app.shipment_actual_costs where id = p_actual_cost_id;
  if not found or not app.has_active_tenant_membership(v_cost.tenant_id, p_actor_auth_user_id) then
    raise exception 'actual_cost_not_found: %', p_actual_cost_id using errcode = 'no_data_found';
  end if;
  select * into v_shipment from app.shipment_orders so where so.id = v_cost.shipment_order_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_cost.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_cost.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.has_view_actual_cost(v_cost.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks OPS:View cost for tenant %', p_actor_auth_user_id, v_cost.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_cost.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_cost.status <> 'draft' then
    raise exception 'invalid_transition: actual cost % is % and cannot accept new components', p_actual_cost_id, v_cost.status
      using errcode = 'check_violation';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.shipment_actual_cost_components where actual_cost_id = p_actual_cost_id and idempotency_key = p_idempotency_key;
    if found then
      -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
      -- conflict, never a replay. Returning the earlier target's row here silently
      -- misattributed this request to it (or silently discarded it entirely).
      if v_existing.category is distinct from p_category or v_existing.source_type is distinct from p_source_type or v_existing.vendor_id is distinct from p_vendor_id or v_existing.assignment_id is distinct from p_assignment_id then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different actual cost component (category %/source %, not category %/source %)', p_idempotency_key, v_existing.category, v_existing.source_type, p_category, p_source_type
          using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  if p_source_type = 'vendor' and p_vendor_id is null then
    raise exception 'actual_cost_vendor_required: a vendor_id is required when source_type is vendor' using errcode = 'check_violation';
  end if;
  if p_assignment_id is not null and not exists (select 1 from app.resource_assignments where id = p_assignment_id and shipment_order_id = v_cost.shipment_order_id) then
    raise exception 'actual_cost_assignment_mismatch: assignment % does not belong to shipment order %', p_assignment_id, v_cost.shipment_order_id
      using errcode = 'check_violation';
  end if;
  if p_document_file_id is not null and not exists (select 1 from app.files where id = p_document_file_id and tenant_id = v_cost.tenant_id and record_type = 'shipment_order' and record_id = v_cost.shipment_order_id) then
    raise exception 'actual_cost_document_mismatch: document % does not belong to shipment order %', p_document_file_id, v_cost.shipment_order_id
      using errcode = 'check_violation';
  end if;

  v_amount := app.compute_actual_cost_component_amount(p_quantity, p_rate, p_minimum_charge, p_surcharge);

  insert into app.shipment_actual_cost_components (
    tenant_id, actual_cost_id, category, source_type, vendor_id, assignment_id, document_file_id,
    description, quantity, uom, rate, minimum_charge, surcharge, amount, currency, idempotency_key, created_by
  ) values (
    v_cost.tenant_id, p_actual_cost_id, p_category, p_source_type, p_vendor_id, p_assignment_id, p_document_file_id,
    p_description, p_quantity, p_uom, p_rate, p_minimum_charge, coalesce(p_surcharge, 0), v_amount, v_cost.currency, p_idempotency_key, p_actor_label
  )
  returning * into v_component;

  perform app.recalculate_actual_cost_total(p_actual_cost_id);

  perform app.capture_audit_event(
    v_cost.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_actual_cost_component',
    'app.shipment_actual_cost_components', v_component.id, 'success', null, null, to_jsonb(v_component)
  );

  return v_component;
end;
$function$;

CREATE OR REPLACE FUNCTION app.assign_exception_owner(p_exception_id uuid, p_owner_user_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.operational_exceptions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_exception app.operational_exceptions;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  select * into v_exception from app.operational_exceptions where id = p_exception_id;
  if not found or not app.has_active_tenant_membership(v_exception.tenant_id, p_actor_auth_user_id) then
    raise exception 'exception_not_found: %', p_exception_id using errcode = 'no_data_found';
  end if;
  if v_exception.owner_user_id is not null and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'reason_required: reassigning an already-owned exception requires a non-empty reason' using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_exception.shipment_order_id;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_exception.tenant_id, 'OPS', 'Assign');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Assign (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_exception.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_exception.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.operational_exceptions
  set owner_user_id = p_owner_user_id
  where id = p_exception_id
  returning * into v_exception;

  perform app.capture_audit_event(
    v_exception.tenant_id, p_actor_auth_user_id, p_actor_label, 'assign_exception_owner',
    'app.operational_exceptions', v_exception.id, 'success', null, null, jsonb_build_object('owner_user_id', p_owner_user_id, 'reason', p_reason)
  );

  return v_exception;
end;
$function$;

CREATE OR REPLACE FUNCTION app.assign_resource(p_shipment_order_id uuid, p_role text, p_resource_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.resource_assignments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_shipment app.shipment_orders;
  v_resource app.master_records;
  v_decision app.rbac_decision;
  v_assignment app.resource_assignments;
begin
  if p_role not in ('vendor', 'fleet', 'vehicle', 'driver') then
    raise exception 'invalid_role: % is not a supported resource-assignment role', p_role using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;
  if v_shipment.status in ('cancelled', 'delivered', 'epod', 'closed') then
    raise exception 'invalid_transition: shipment order % is % and can no longer receive resource assignments', p_shipment_order_id, v_shipment.status
      using errcode = 'check_violation';
  end if;

  select * into v_resource from app.master_records where id = p_resource_id;
  if not found or v_resource.master_type_code <> p_role or v_resource.tenant_id <> v_shipment.tenant_id or v_resource.canonical_status <> 'active' then
    raise exception 'invalid_resource: % is not an active % master record for tenant %', p_resource_id, p_role, v_shipment.tenant_id
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Assign');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Assign (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if exists (
    select 1 from app.resource_assignments ra
    where ra.tenant_id = v_shipment.tenant_id
      and ra.resource_id = p_resource_id
      and ra.is_current
      and ra.status = 'active'
      and ra.shipment_order_id <> p_shipment_order_id
  ) then
    raise exception 'assignment_conflict: resource % is already actively assigned on another shipment order', p_resource_id
      using errcode = 'check_violation';
  end if;

  if exists (
    select 1 from app.resource_assignments ra
    where ra.tenant_id = v_shipment.tenant_id
      and ra.shipment_order_id = p_shipment_order_id
      and ra.role = p_role
      and ra.is_current
  ) then
    raise exception 'already_assigned: shipment order % already has a current % assignment -- use reassign_resource', p_shipment_order_id, p_role
      using errcode = 'check_violation';
  end if;

  insert into app.resource_assignments (
    tenant_id, shipment_order_id, role, resource_id, resource_snapshot, created_by
  ) values (
    v_shipment.tenant_id, p_shipment_order_id, p_role, p_resource_id,
    jsonb_build_object('code', v_resource.code, 'name', v_resource.name), p_actor_label
  )
  returning * into v_assignment;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'assign_resource',
    'app.resource_assignments', v_assignment.id, 'success', null, null,
    jsonb_build_object('shipment_order_id', p_shipment_order_id, 'role', p_role, 'resource_id', p_resource_id)
  );

  return v_assignment;
end;
$function$;

CREATE OR REPLACE FUNCTION app.calculate_job_profitability(p_job_order_id uuid, p_recalculation_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.job_profitability_snapshots
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_job app.job_orders;
  v_decision app.rbac_decision;
  v_existing_current app.job_profitability_snapshots;
  v_revenue_currency text;
  v_revenue_amount numeric(14, 2);
  v_cost_currency_count integer;
  v_cost_currency text;
  v_cost_amount numeric(14, 2);
  v_cost_count integer;
  v_cost_version_ids uuid[];
  v_status text;
  v_blocked_reason text;
  v_margin_amount numeric(14, 2);
  v_margin_percent numeric(9, 4);
  v_new_version integer;
  v_snapshot app.job_profitability_snapshots;
  v_base_currency text;
  v_revenue_fx_as_of timestamptz;
  v_revenue_base_amount numeric(14, 2);
  v_revenue_fx_rate numeric;
  v_revenue_fx_status text;
  v_invoice_currency_count integer;
  v_invoice_count integer;
  v_invoiced_currency text;
  v_invoiced_amount numeric(14, 2);
  v_invoiced_as_of timestamptz;
  v_invoice_ids uuid[];
  v_invoiced_status text;
  v_invoiced_base_amount numeric(14, 2);
  v_invoiced_fx_rate numeric;
  v_invoiced_fx_status text;
begin
  select * into v_job from app.job_orders jo where jo.id = p_job_order_id;
  if not found or not app.has_active_tenant_membership(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'job_order_not_found: %', p_job_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_job.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.has_view_job_margin(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks OPS:View margin for tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_job.tenant_id, v_job.owner_user_id, app.lead_record_scope_org_unit_ids(v_job.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access job order %', p_actor_auth_user_id, p_job_order_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_existing_current from app.job_profitability_snapshots where job_order_id = p_job_order_id and is_current;
  if found and (p_recalculation_reason is null or length(trim(p_recalculation_reason)) = 0) then
    raise exception 'job_profitability_recalculation_reason_required: a reason is required to recalculate an existing profitability snapshot' using errcode = 'check_violation';
  end if;

  v_revenue_currency := v_job.revenue_snapshot ->> 'currency';
  v_revenue_amount := (v_job.revenue_snapshot ->> 'totalAmount')::numeric(14, 2);

  select count(distinct sac.currency), count(*), coalesce(sum(sac.total_amount), 0), coalesce(array_agg(sac.id), '{}'::uuid[])
  into v_cost_currency_count, v_cost_count, v_cost_amount, v_cost_version_ids
  from app.shipment_actual_costs sac
  join app.shipment_orders so on so.id = sac.shipment_order_id
  where so.job_order_id = p_job_order_id and sac.is_current and sac.status = 'approved';

  if v_cost_count = 0 then
    v_status := 'unavailable';
    v_blocked_reason := 'no_approved_cost';
    v_cost_currency := null;
    v_cost_amount := null;
    v_margin_amount := null;
    v_margin_percent := null;
  elsif v_cost_currency_count > 1 or (select sac.currency from app.shipment_actual_costs sac where sac.id = v_cost_version_ids[1]) <> v_revenue_currency then
    v_status := 'unavailable';
    v_blocked_reason := 'mixed_currency';
    v_cost_currency := null;
    v_cost_amount := null;
    v_margin_amount := null;
    v_margin_percent := null;
  else
    v_status := 'calculated';
    v_blocked_reason := null;
    v_cost_currency := v_revenue_currency;
    v_margin_amount := v_revenue_amount - v_cost_amount;
    v_margin_percent := case when v_revenue_amount <> 0 then round((v_margin_amount / v_revenue_amount) * 100, 4) else null end;
  end if;

  select default_currency into v_base_currency from app.resolve_tenant_locale(v_job.tenant_id);

  v_revenue_fx_as_of := v_job.created_at;
  select converted_amount, fx_rate, fx_status
  into v_revenue_base_amount, v_revenue_fx_rate, v_revenue_fx_status
  from app.resolve_operations_fx_conversion(v_job.tenant_id, v_revenue_amount, v_revenue_currency, v_base_currency, v_revenue_fx_as_of);

  select count(distinct fi.currency), count(*), sum(fi.subtotal_amount), max(fi.currency), max(fi.issue_date)::timestamptz, coalesce(array_agg(fi.id), '{}'::uuid[])
  into v_invoice_currency_count, v_invoice_count, v_invoiced_amount, v_invoiced_currency, v_invoiced_as_of, v_invoice_ids
  from app.finance_invoices fi
  where fi.job_order_id = p_job_order_id and fi.status = 'issued';

  if v_invoice_count = 0 then
    v_invoiced_status := 'not_yet_invoiced';
    v_invoiced_currency := null;
    v_invoiced_amount := null;
    v_invoiced_as_of := null;
  elsif v_invoice_currency_count > 1 then
    v_invoiced_status := 'mixed_currency';
    v_invoiced_currency := null;
    v_invoiced_amount := null;
  else
    v_invoiced_status := 'available';
  end if;

  if v_invoiced_status = 'available' then
    select converted_amount, fx_rate, fx_status
    into v_invoiced_base_amount, v_invoiced_fx_rate, v_invoiced_fx_status
    from app.resolve_operations_fx_conversion(v_job.tenant_id, v_invoiced_amount, v_invoiced_currency, v_base_currency, v_invoiced_as_of);
  else
    v_invoiced_base_amount := null;
    v_invoiced_fx_rate := null;
    v_invoiced_fx_status := null;
  end if;

  v_new_version := coalesce(v_existing_current.version_number, 0) + 1;
  if found then
    update app.job_profitability_snapshots set is_current = false where id = v_existing_current.id;
  end if;

  insert into app.job_profitability_snapshots (
    tenant_id, job_order_id, version_number, is_current, status, blocked_reason, revenue_basis,
    revenue_currency, revenue_amount, cost_currency, cost_amount, margin_amount, margin_percent,
    source_cost_version_ids, recalculation_reason, calculated_by_auth_user_id, created_by,
    base_currency, revenue_base_amount, revenue_fx_rate, revenue_fx_as_of, revenue_fx_status,
    invoiced_currency, invoiced_amount, invoiced_status, invoiced_base_amount, invoiced_fx_rate,
    invoiced_fx_as_of, invoiced_fx_status, source_invoice_ids
  ) values (
    v_job.tenant_id, p_job_order_id, v_new_version, true, v_status, v_blocked_reason, 'quoted',
    v_revenue_currency, v_revenue_amount, v_cost_currency, v_cost_amount, v_margin_amount, v_margin_percent,
    v_cost_version_ids, p_recalculation_reason, p_actor_auth_user_id, p_actor_label,
    v_base_currency, v_revenue_base_amount, v_revenue_fx_rate, v_revenue_fx_as_of, v_revenue_fx_status,
    v_invoiced_currency, v_invoiced_amount, v_invoiced_status, v_invoiced_base_amount, v_invoiced_fx_rate,
    v_invoiced_as_of, v_invoiced_fx_status, v_invoice_ids
  )
  returning * into v_snapshot;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'calculate_job_profitability',
    'app.job_profitability_snapshots', v_snapshot.id, 'success', p_recalculation_reason, null, to_jsonb(v_snapshot)
  );

  return v_snapshot;
end;
$function$;

CREATE OR REPLACE FUNCTION app.cancel_shipment_order(p_shipment_order_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.shipment_orders
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'cancel_reason_required: a non-empty reason is required to cancel a Shipment Order' using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  if v_shipment.record_version <> p_expected_version then
    raise exception 'stale_version: shipment order % expected version % but found %', p_shipment_order_id, p_expected_version, v_shipment.record_version
      using errcode = 'serialization_failure';
  end if;

  -- ATW-032 (ISS-2026-034). This guard was written at OPS-169, when the status CHECK
  -- constraint only admitted draft/confirmed/cancelled -- so "not already cancelled" WAS
  -- complete. OPS-170 widened that constraint to eleven statuses and did not widen this
  -- guard, and the function's own committed comment still scopes it to "draft/confirmed ->
  -- cancelled". The result was an out-of-matrix edge: an OPS:Edit holder could drive a
  -- settled, CLOSED shipment straight to the terminal 'cancelled' state, defeating
  -- app.transition_shipment_order's own RPD-022 rule that reopening a closed shipment
  -- requires Supreme Admin. epod is excluded for the same reason -- delivery evidence has
  -- been captured by then.
  if v_shipment.status not in ('draft', 'confirmed', 'planned', 'assigned', 'dispatched', 'in_transit', 'held', 'delivered') then
    raise exception 'invalid_transition: shipment order % is % -- only a pre-ePOD, non-terminal shipment order may be cancelled', p_shipment_order_id, v_shipment.status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.shipment_orders
  set status = 'cancelled'
  where id = p_shipment_order_id and record_version = p_expected_version
  returning * into v_shipment;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: cancel_shipment_order target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_shipment_order',
    'app.shipment_orders', v_shipment.id, 'success', null, null, jsonb_build_object('reason', p_reason)
  );

  return v_shipment;
end;
$function$;

CREATE OR REPLACE FUNCTION app.change_shipment_mode(p_shipment_order_id uuid, p_new_mode text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.shipment_orders
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  if p_new_mode not in ('land', 'air', 'sea') then
    raise exception 'invalid_mode: % is not a supported mode', p_new_mode using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  if v_shipment.record_version <> p_expected_version then
    raise exception 'stale_version: shipment order % expected version % but found %', p_shipment_order_id, p_expected_version, v_shipment.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_shipment.status <> 'draft' then
    raise exception 'confirmed_mode_change_blocked: shipment order % is % -- mode may only change while draft', p_shipment_order_id, v_shipment.status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_shipment.mode <> p_new_mode then
    delete from app.shipment_mode_profiles where shipment_order_id = p_shipment_order_id;
  end if;

  update app.shipment_orders
  set mode = p_new_mode
  where id = p_shipment_order_id and record_version = p_expected_version
  returning * into v_shipment;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: change_shipment_mode target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'change_shipment_mode',
    'app.shipment_orders', v_shipment.id, 'success', null, null, jsonb_build_object('mode', p_new_mode)
  );

  return v_shipment;
end;
$function$;

CREATE OR REPLACE FUNCTION app.close_exception(p_exception_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.operational_exceptions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_exception app.operational_exceptions;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  select * into v_exception from app.operational_exceptions where id = p_exception_id;
  if not found or not app.has_active_tenant_membership(v_exception.tenant_id, p_actor_auth_user_id) then
    raise exception 'exception_not_found: %', p_exception_id using errcode = 'no_data_found';
  end if;
  if v_exception.record_version <> p_expected_version then
    raise exception 'stale_version: exception % expected version % but found %', p_exception_id, p_expected_version, v_exception.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_exception.status <> 'resolved' then
    raise exception 'invalid_transition: exception % is % and cannot be closed', p_exception_id, v_exception.status
      using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_exception.shipment_order_id;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_exception.tenant_id, 'OPS', 'Close');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Close (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_exception.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_exception.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.operational_exceptions
  set status = 'closed', closed_at = now()
  where id = p_exception_id and record_version = p_expected_version
  returning * into v_exception;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: close_exception target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_exception.tenant_id, p_actor_auth_user_id, p_actor_label, 'close_exception',
    'app.operational_exceptions', v_exception.id, 'success', null, null, '{}'::jsonb
  );

  return v_exception;
end;
$function$;

CREATE OR REPLACE FUNCTION app.complete_epod_capture(p_capture_id uuid, p_expected_capture_version integer, p_shipment_expected_version integer, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.epod_captures
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
declare
  v_capture app.epod_captures;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_updated app.epod_captures;
begin
  -- ATW-032 (ISS-2026-034): 20260730480000 gave this family its row locks by sweeping for
  -- the parameter name p_expected_version; this function calls its own p_expected_capture_
  -- version and was the one member the sweep could not see. Not exploitable today (from
  -- 'approved' no other writer exists), but leaving one sibling unlocked is how the next
  -- writer inherits a race.
  select * into v_capture from app.epod_captures where id = p_capture_id for update;
  if not found or not app.has_active_tenant_membership(v_capture.tenant_id, p_actor_auth_user_id) then
    raise exception 'epod_capture_not_found: %', p_capture_id using errcode = 'no_data_found';
  end if;
  if v_capture.record_version <> p_expected_capture_version then
    raise exception 'concurrent_modification: ePOD capture % has moved from expected version % to %', p_capture_id, p_expected_capture_version, v_capture.record_version
      using errcode = 'check_violation';
  end if;
  select * into v_shipment from app.shipment_orders so where so.id = v_capture.shipment_order_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_capture.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_capture.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_capture.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_capture.status <> 'approved' then
    raise exception 'invalid_transition: ePOD capture % is % and cannot be completed', p_capture_id, v_capture.status
      using errcode = 'check_violation';
  end if;

  perform app.transition_shipment_order(v_capture.shipment_order_id, 'epod', p_shipment_expected_version, null, p_capture_id::text, p_idempotency_key, p_actor_auth_user_id, p_actor_label);

  update app.epod_captures
  set status = 'completed'
  where id = p_capture_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_capture.tenant_id, p_actor_auth_user_id, p_actor_label, 'complete_epod_capture',
    'app.epod_captures', v_updated.id, 'success', null, to_jsonb(v_capture), to_jsonb(v_updated)
  );

  return v_updated;
end;
$function$;

CREATE OR REPLACE FUNCTION app.confirm_job_order(p_job_order_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.job_orders
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_job_order app.job_orders;
  v_decision app.rbac_decision;
begin
  select * into v_job_order from app.job_orders where id = p_job_order_id;
  if not found or not app.has_active_tenant_membership(v_job_order.tenant_id, p_actor_auth_user_id) then
    raise exception 'job_order_not_found: %', p_job_order_id using errcode = 'no_data_found';
  end if;

  if v_job_order.record_version <> p_expected_version then
    raise exception 'stale_version: job order % expected version % but found %', p_job_order_id, p_expected_version, v_job_order.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_job_order.status <> 'draft' then
    raise exception 'invalid_transition: job order % is % and cannot be confirmed', p_job_order_id, v_job_order.status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_job_order.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_job_order.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_job_order.tenant_id, v_job_order.owner_user_id, app.lead_record_scope_org_unit_ids(v_job_order.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access job order %', p_actor_auth_user_id, p_job_order_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.job_orders
  set status = 'confirmed'
  where id = p_job_order_id and record_version = p_expected_version
  returning * into v_job_order;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: confirm_job_order target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_job_order.tenant_id, p_actor_auth_user_id, p_actor_label, 'confirm_job_order',
    'app.job_orders', v_job_order.id, 'success', null, null, jsonb_build_object('status', v_job_order.status)
  );

  return v_job_order;
end;
$function$;

CREATE OR REPLACE FUNCTION app.confirm_shipment_order(p_shipment_order_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.shipment_orders
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  if v_shipment.record_version <> p_expected_version then
    raise exception 'stale_version: shipment order % expected version % but found %', p_shipment_order_id, p_expected_version, v_shipment.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_shipment.status <> 'draft' then
    raise exception 'invalid_transition: shipment order % is % and cannot be confirmed', p_shipment_order_id, v_shipment.status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.shipment_orders
  set status = 'confirmed'
  where id = p_shipment_order_id and record_version = p_expected_version
  returning * into v_shipment;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: confirm_shipment_order target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'confirm_shipment_order',
    'app.shipment_orders', v_shipment.id, 'success', null, null, jsonb_build_object('status', v_shipment.status)
  );

  return v_shipment;
end;
$function$;

CREATE OR REPLACE FUNCTION app.create_actual_cost_adjustment(p_previous_actual_cost_id uuid, p_adjustment_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.shipment_actual_costs
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_prev app.shipment_actual_costs;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_new app.shipment_actual_costs;
begin
  if p_adjustment_reason is null or length(trim(p_adjustment_reason)) = 0 then
    raise exception 'actual_cost_adjustment_reason_required: a reason is required to adjust an approved actual cost' using errcode = 'check_violation';
  end if;

  select * into v_prev from app.shipment_actual_costs where id = p_previous_actual_cost_id;
  if not found or not app.has_active_tenant_membership(v_prev.tenant_id, p_actor_auth_user_id) then
    raise exception 'actual_cost_not_found: %', p_previous_actual_cost_id using errcode = 'no_data_found';
  end if;
  select * into v_shipment from app.shipment_orders so where so.id = v_prev.shipment_order_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_prev.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_prev.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.has_view_actual_cost(v_prev.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks OPS:View cost for tenant %', p_actor_auth_user_id, v_prev.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_prev.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_prev.status <> 'approved' then
    raise exception 'invalid_transition: actual cost % is % and cannot be adjusted -- only an approved version may be adjusted', p_previous_actual_cost_id, v_prev.status
      using errcode = 'check_violation';
  end if;
  if not v_prev.is_current then
    raise exception 'actual_cost_not_current: actual cost % is not the current version', p_previous_actual_cost_id
      using errcode = 'check_violation';
  end if;

  update app.shipment_actual_costs set is_current = false where id = v_prev.id;

  insert into app.shipment_actual_costs (tenant_id, shipment_order_id, version_number, is_current, supersedes_version_id, status, currency, estimated_amount, adjustment_reason, created_by)
  values (v_prev.tenant_id, v_prev.shipment_order_id, v_prev.version_number + 1, true, v_prev.id, 'draft', v_prev.currency, v_prev.estimated_amount, p_adjustment_reason, p_actor_label)
  returning * into v_new;

  insert into app.shipment_actual_cost_components (
    tenant_id, actual_cost_id, category, source_type, vendor_id, assignment_id, document_file_id,
    description, quantity, uom, rate, minimum_charge, surcharge, amount, currency, created_by
  )
  select
    tenant_id, v_new.id, category, source_type, vendor_id, assignment_id, document_file_id,
    description, quantity, uom, rate, minimum_charge, surcharge, amount, currency, p_actor_label
  from app.shipment_actual_cost_components
  where actual_cost_id = v_prev.id;

  perform app.recalculate_actual_cost_total(v_new.id);
  select * into v_new from app.shipment_actual_costs where id = v_new.id;

  perform app.capture_audit_event(
    v_prev.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_actual_cost_adjustment',
    'app.shipment_actual_costs', v_new.id, 'success', p_adjustment_reason, to_jsonb(v_prev), to_jsonb(v_new)
  );

  return v_new;
end;
$function$;

CREATE OR REPLACE FUNCTION app.create_actual_cost_draft(p_tenant_id uuid, p_shipment_order_id uuid, p_currency text, p_estimated_amount numeric, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.shipment_actual_costs
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_existing_draft app.shipment_actual_costs;
  v_cost app.shipment_actual_costs;
begin
  select * into v_shipment from app.shipment_orders so where so.id = p_shipment_order_id;
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.has_view_actual_cost(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks OPS:View cost for tenant %', p_actor_auth_user_id, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_existing_draft from app.shipment_actual_costs where shipment_order_id = p_shipment_order_id and status = 'draft';
  if found then
    return v_existing_draft;
  end if;

  if exists (select 1 from app.shipment_actual_costs where shipment_order_id = p_shipment_order_id and is_current) then
    raise exception 'actual_cost_already_exists: shipment order % already has a current actual-cost version -- use app.create_actual_cost_adjustment to start a new one', p_shipment_order_id
      using errcode = 'check_violation';
  end if;

  insert into app.shipment_actual_costs (tenant_id, shipment_order_id, currency, estimated_amount, created_by)
  values (v_shipment.tenant_id, p_shipment_order_id, p_currency, p_estimated_amount, p_actor_label)
  returning * into v_cost;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_actual_cost_draft',
    'app.shipment_actual_costs', v_cost.id, 'success', null, null, to_jsonb(v_cost)
  );

  return v_cost;
end;
$function$;

CREATE OR REPLACE FUNCTION app.create_shipment_order_from_job(p_job_order_id uuid, p_idempotency_key text, p_consignee jsonb, p_notify_party jsonb, p_service_type text, p_mode text, p_origin text, p_destination text, p_planned_pickup_at timestamp with time zone, p_planned_delivery_at timestamp with time zone, p_allocated_quantity numeric, p_allocated_weight_kg numeric, p_allocated_volume_cbm numeric, p_basis_quantity numeric, p_basis_weight_kg numeric, p_basis_volume_cbm numeric, p_split_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.shipment_orders
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_job app.job_orders;
  v_decision app.rbac_decision;
  v_existing app.shipment_orders;
  v_shipment app.shipment_orders;
  v_number text;
  v_existing_count integer;
  v_any_count integer;
  v_balance record;
  v_basis_quantity numeric;
  v_basis_weight_kg numeric;
  v_basis_volume_cbm numeric;
begin
  if p_mode not in ('land', 'air', 'sea') then
    raise exception 'invalid_mode: % is not a supported mode' , p_mode using errcode = 'check_violation';
  end if;

  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: a non-empty idempotency key is required' using errcode = 'check_violation';
  end if;

  select * into v_job from app.job_orders where id = p_job_order_id;
  if not found or not app.has_active_tenant_membership(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'job_order_not_found: %', p_job_order_id using errcode = 'no_data_found';
  end if;

  if v_job.status <> 'confirmed' then
    raise exception 'job_order_not_confirmed: job order % is % and is not eligible for Shipment Order creation', p_job_order_id, v_job.status
      using errcode = 'check_violation';
  end if;

  select * into v_existing from app.shipment_orders where tenant_id = v_job.tenant_id and job_order_id = p_job_order_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
    -- conflict, never a replay. Returning the earlier target's row here silently
    -- misattributed this request to it (or silently discarded it entirely).
    if v_existing.mode is distinct from p_mode or v_existing.origin is distinct from p_origin or v_existing.destination is distinct from p_destination or v_existing.service_type is distinct from p_service_type then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different shipment order split (mode %/route %->%, not mode %/route %->%)', p_idempotency_key, v_existing.mode, v_existing.origin, v_existing.destination, p_mode, p_origin, p_destination
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_job.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_job.tenant_id, v_job.owner_user_id, app.lead_record_scope_org_unit_ids(v_job.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access job order %', p_actor_auth_user_id, p_job_order_id
      using errcode = 'insufficient_privilege';
  end if;

  select count(*) into v_existing_count from app.shipment_orders where job_order_id = p_job_order_id and status <> 'cancelled';
  -- ATW-032 (ISS-2026-034): the basis is WRITTEN when no NON-CANCELLED sibling exists, but
  -- app.get_job_shipment_allocation_balance READS it from the very first shipment order ever
  -- created for the job, "regardless of that row's own current status" (its own committed
  -- comment). Cancel SO#1 and SO#2 legitimately declares a new basis -- which the reader then
  -- never sees, because it is still resolving SO#1. If SO#1 declared a null basis, every
  -- later over-allocation check is skipped permanently while the operator sees a declared
  -- basis on SO#2. v_any_count matches the reader's scope exactly; v_existing_count keeps its
  -- own, different and correct, job: deciding whether a split_reason is required.
  select count(*) into v_any_count from app.shipment_orders where job_order_id = p_job_order_id;
  if v_existing_count > 0 and (p_split_reason is null or length(trim(p_split_reason)) = 0) then
    raise exception 'split_reason_required: a non-empty split_reason is required when another Shipment Order already exists for job order %', p_job_order_id
      using errcode = 'check_violation';
  end if;

  if v_any_count > 0 then
    select * into v_balance from app.get_job_shipment_allocation_balance(p_job_order_id, p_actor_auth_user_id);
    if v_balance.basis_quantity is not null and coalesce(p_allocated_quantity, 0) > coalesce(v_balance.remaining_quantity, 0) then
      raise exception 'over_allocation: allocated_quantity % exceeds remaining % for job order %', p_allocated_quantity, v_balance.remaining_quantity, p_job_order_id
        using errcode = 'check_violation';
    end if;
    if v_balance.basis_weight_kg is not null and coalesce(p_allocated_weight_kg, 0) > coalesce(v_balance.remaining_weight_kg, 0) then
      raise exception 'over_allocation: allocated_weight_kg % exceeds remaining % for job order %', p_allocated_weight_kg, v_balance.remaining_weight_kg, p_job_order_id
        using errcode = 'check_violation';
    end if;
    if v_balance.basis_volume_cbm is not null and coalesce(p_allocated_volume_cbm, 0) > coalesce(v_balance.remaining_volume_cbm, 0) then
      raise exception 'over_allocation: allocated_volume_cbm % exceeds remaining % for job order %', p_allocated_volume_cbm, v_balance.remaining_volume_cbm, p_job_order_id
        using errcode = 'check_violation';
    end if;
  end if;

  if v_any_count = 0 then
    v_basis_quantity := p_basis_quantity;
    v_basis_weight_kg := p_basis_weight_kg;
    v_basis_volume_cbm := p_basis_volume_cbm;
  end if;

  v_number := app.next_shipment_number(v_job.tenant_id);

  begin
    insert into app.shipment_orders (
      tenant_id, job_order_id, shipment_number, idempotency_key, shipper_account_id,
      consignee_snapshot, notify_party_snapshot, cargo_service_snapshot,
      service_type, mode, origin, destination, planned_pickup_at, planned_delivery_at,
      basis_quantity, basis_weight_kg, basis_volume_cbm,
      allocated_quantity, allocated_weight_kg, allocated_volume_cbm, split_reason,
      owner_user_id, created_by
    ) values (
      v_job.tenant_id, p_job_order_id, v_number, p_idempotency_key, v_job.account_id,
      coalesce(p_consignee, v_job.customer_snapshot), p_notify_party, v_job.cargo_service_snapshot,
      p_service_type, p_mode, p_origin, p_destination, p_planned_pickup_at, p_planned_delivery_at,
      v_basis_quantity, v_basis_weight_kg, v_basis_volume_cbm,
      p_allocated_quantity, p_allocated_weight_kg, p_allocated_volume_cbm, p_split_reason,
      p_actor_auth_user_id, p_actor_label
    )
    returning * into v_shipment;
  exception
    when unique_violation then
      select * into v_shipment from app.shipment_orders where tenant_id = v_job.tenant_id and job_order_id = p_job_order_id and idempotency_key = p_idempotency_key;
      return v_shipment;
  end;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_shipment_order_from_job',
    'app.shipment_orders', v_shipment.id, 'success', null, null,
    jsonb_build_object('job_order_id', p_job_order_id, 'shipment_number', v_number, 'split_reason', p_split_reason)
  );

  return v_shipment;
end;
$function$;

CREATE OR REPLACE FUNCTION app.decide_actual_cost(p_actual_cost_id uuid, p_decision text, p_reason text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.shipment_actual_costs
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_cost app.shipment_actual_costs;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_updated app.shipment_actual_costs;
begin
  if p_decision not in ('approved', 'rejected') then
    raise exception 'actual_cost_invalid_decision: % is not one of approved/rejected', p_decision using errcode = 'check_violation';
  end if;

  select * into v_cost from app.shipment_actual_costs where id = p_actual_cost_id for update;
  if not found or not app.has_active_tenant_membership(v_cost.tenant_id, p_actor_auth_user_id) then
    raise exception 'actual_cost_not_found: %', p_actual_cost_id using errcode = 'no_data_found';
  end if;
  if v_cost.record_version <> p_expected_version then
    raise exception 'concurrent_modification: actual cost % has moved from expected version % to %', p_actual_cost_id, p_expected_version, v_cost.record_version
      using errcode = 'check_violation';
  end if;
  select * into v_shipment from app.shipment_orders so where so.id = v_cost.shipment_order_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_cost.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_cost.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.has_view_actual_cost(v_cost.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks OPS:View cost for tenant %', p_actor_auth_user_id, v_cost.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_cost.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_cost.status <> 'submitted' then
    raise exception 'invalid_transition: actual cost % is % and cannot be decided', p_actual_cost_id, v_cost.status
      using errcode = 'check_violation';
  end if;
  if p_decision = 'rejected' and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'actual_cost_rejection_reason_required: a reason is required to reject' using errcode = 'check_violation';
  end if;

  update app.shipment_actual_costs
  set status = p_decision,
      approved_by_auth_user_id = case when p_decision = 'approved' then p_actor_auth_user_id else null end,
      approved_at = case when p_decision = 'approved' then now() else null end,
      rejection_reason = case when p_decision = 'rejected' then p_reason else null end
  where id = p_actual_cost_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_cost.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_actual_cost',
    'app.shipment_actual_costs', v_updated.id, 'success', null, to_jsonb(v_cost), to_jsonb(v_updated)
  );

  return v_updated;
end;
$function$;

CREATE OR REPLACE FUNCTION app.dispatch_shipment_order(p_shipment_order_id uuid, p_expected_version integer, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.dispatch_commands
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_existing app.dispatch_commands;
  v_readiness record;
  v_command app.dispatch_commands;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: a non-empty idempotency key is required' using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  select * into v_existing from app.dispatch_commands
  where tenant_id = v_shipment.tenant_id and shipment_order_id = p_shipment_order_id and idempotency_key = p_idempotency_key;
  if found then
    return v_existing;
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_readiness from app.evaluate_dispatch_readiness(p_shipment_order_id);
  if not v_readiness.is_ready then
    -- Deliberately not captured via app.capture_audit_event here: a raise exception
    -- unwinds to the nearest enclosing exception block (this function's own caller,
    -- or app.bulk_dispatch_shipment_orders' per-record catch), which rolls back to an
    -- implicit savepoint and would silently discard any insert made before the raise.
    -- The blockers are carried in the exception message itself instead.
    raise exception 'dispatch_not_ready: shipment order % is not ready to dispatch (%)', p_shipment_order_id, v_readiness.blockers
      using errcode = 'check_violation';
  end if;

  perform app.transition_shipment_order(p_shipment_order_id, 'dispatched', p_expected_version, null, null, p_idempotency_key, p_actor_auth_user_id, p_actor_label);

  begin
    insert into app.dispatch_commands (tenant_id, shipment_order_id, readiness_snapshot, idempotency_key, actor_auth_user_id, actor_label)
    values (v_shipment.tenant_id, p_shipment_order_id, to_jsonb(v_readiness), p_idempotency_key, p_actor_auth_user_id, p_actor_label)
    returning * into v_command;
  exception
    when unique_violation then
      select * into v_command from app.dispatch_commands
      where tenant_id = v_shipment.tenant_id and shipment_order_id = p_shipment_order_id and idempotency_key = p_idempotency_key;
      return v_command;
  end;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'dispatch_shipment_order',
    'app.dispatch_commands', v_command.id, 'success', null, null, jsonb_build_object('shipment_order_id', p_shipment_order_id)
  );

  return v_command;
end;
$function$;

CREATE OR REPLACE FUNCTION app.escalate_exception(p_exception_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.operational_exceptions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_exception app.operational_exceptions;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_new_level integer;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: escalating an exception requires a non-empty reason' using errcode = 'check_violation';
  end if;

  select * into v_exception from app.operational_exceptions where id = p_exception_id;
  if not found or not app.has_active_tenant_membership(v_exception.tenant_id, p_actor_auth_user_id) then
    raise exception 'exception_not_found: %', p_exception_id using errcode = 'no_data_found';
  end if;
  if v_exception.status in ('resolved', 'closed') then
    raise exception 'invalid_transition: exception % is % and can no longer be escalated', p_exception_id, v_exception.status
      using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_exception.shipment_order_id;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_exception.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_exception.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_exception.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  v_new_level := v_exception.escalation_level + 1;

  update app.operational_exceptions
  set escalation_level = v_new_level
  where id = p_exception_id
  returning * into v_exception;

  insert into app.exception_escalations (tenant_id, exception_id, escalation_level, reason, actor_auth_user_id, actor_label)
  values (v_exception.tenant_id, p_exception_id, v_new_level, p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_exception.tenant_id, p_actor_auth_user_id, p_actor_label, 'escalate_exception',
    'app.operational_exceptions', v_exception.id, 'success', null, null, jsonb_build_object('escalation_level', v_new_level, 'reason', p_reason)
  );

  return v_exception;
end;
$function$;

CREATE OR REPLACE FUNCTION app.evaluate_actual_cost_variance(p_actual_cost_id uuid, p_actor_auth_user_id uuid)
 RETURNS TABLE(total_amount numeric, estimated_amount numeric, variance_amount numeric, variance_available boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_cost app.shipment_actual_costs;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  select * into v_cost from app.shipment_actual_costs where id = p_actual_cost_id;
  if not found or not app.has_active_tenant_membership(v_cost.tenant_id, p_actor_auth_user_id) then
    raise exception 'actual_cost_not_found: %', p_actual_cost_id using errcode = 'no_data_found';
  end if;
  select * into v_shipment from app.shipment_orders so where so.id = v_cost.shipment_order_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_cost.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_cost.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.has_view_actual_cost(v_cost.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks OPS:View cost for tenant %', p_actor_auth_user_id, v_cost.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_cost.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select
    v_cost.total_amount,
    v_cost.estimated_amount,
    case when v_cost.estimated_amount is not null then v_cost.total_amount - v_cost.estimated_amount else null end,
    v_cost.estimated_amount is not null;
end;
$function$;

CREATE OR REPLACE FUNCTION app.evaluate_billing_readiness(p_job_order_id uuid, p_reevaluation_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.billing_readiness_evaluations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_job app.job_orders;
  v_decision app.rbac_decision;
  v_existing app.billing_readiness_evaluations;
  v_has_existing boolean;
  v_blockers jsonb := '[]'::jsonb;
  v_shipment record;
  v_shipment_count integer := 0;
  v_shipment_ids uuid[] := '{}';
  v_actual_cost_ids uuid[] := '{}';
  v_epod_capture_ids uuid[] := '{}';
  v_missing_mandatory jsonb;
  v_epod app.epod_captures;
  v_cost app.shipment_actual_costs;
  v_active_exception_count integer;
  v_credit_outcome text;
  v_evaluated_status text;
  v_evidence jsonb;
  v_new app.billing_readiness_evaluations;
begin
  select * into v_job from app.job_orders where id = p_job_order_id;
  if not found or not app.has_active_tenant_membership(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'job_order_not_found: %', p_job_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_job.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_job.tenant_id, v_job.owner_user_id, app.lead_record_scope_org_unit_ids(v_job.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access job order %', p_actor_auth_user_id, p_job_order_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_existing from app.billing_readiness_evaluations where job_order_id = p_job_order_id and is_current;
  v_has_existing := found;
  if v_has_existing and (p_reevaluation_reason is null or length(trim(p_reevaluation_reason)) = 0) then
    raise exception 'billing_readiness_reevaluation_reason_required: a non-empty reason is required to reevaluate a Job Order that already has a current billing-readiness evaluation' using errcode = 'check_violation';
  end if;

  if v_job.status <> 'confirmed' then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'job_order_not_confirmed', 'jobOrderStatus', v_job.status));
  end if;

  for v_shipment in
    select * from app.shipment_orders so where so.job_order_id = p_job_order_id and so.status <> 'cancelled' order by so.created_at
  loop
    v_shipment_count := v_shipment_count + 1;
    v_shipment_ids := v_shipment_ids || v_shipment.id;

    if v_shipment.status not in ('epod', 'closed') then
      v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'shipment_not_delivered', 'shipmentOrderId', v_shipment.id, 'status', v_shipment.status));
    end if;

    select coalesce(jsonb_agg(jsonb_build_object('checklistItemId', ci.id, 'documentTypeCode', ci.document_type_code)), '[]'::jsonb)
    into v_missing_mandatory
    from app.shipment_document_checklist_items ci
    left join app.files f on f.id = ci.file_id
    where ci.shipment_order_id = v_shipment.id
      and ci.criticality = 'mandatory'
      and not (
        ci.review_status = 'approved'
        and (ci.expires_at is null or ci.expires_at > now())
        and f.malware_scan_status = 'clean'
      );
    if jsonb_array_length(v_missing_mandatory) > 0 then
      v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'documents_incomplete', 'shipmentOrderId', v_shipment.id, 'missingMandatory', v_missing_mandatory));
    end if;

    select * into v_epod from app.epod_captures where shipment_order_id = v_shipment.id and is_latest_version;
    if not found or v_epod.status <> 'completed' then
      v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'epod_incomplete', 'shipmentOrderId', v_shipment.id, 'epodStatus', v_epod.status));
    else
      v_epod_capture_ids := v_epod_capture_ids || v_epod.id;
    end if;

    select count(*) into v_active_exception_count from app.operational_exceptions where shipment_order_id = v_shipment.id and status not in ('resolved', 'closed');
    if v_active_exception_count > 0 then
      v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'active_exception', 'shipmentOrderId', v_shipment.id, 'activeExceptionCount', v_active_exception_count));
    end if;

    select * into v_cost from app.shipment_actual_costs where shipment_order_id = v_shipment.id and is_current;
    if not found then
      v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'actual_cost_not_approved', 'shipmentOrderId', v_shipment.id, 'costStatus', null));
    elsif v_cost.status <> 'approved' then
      v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'actual_cost_not_approved', 'shipmentOrderId', v_shipment.id, 'costStatus', v_cost.status));
    else
      v_actual_cost_ids := v_actual_cost_ids || v_cost.id;
    end if;
  end loop;

  if v_shipment_count = 0 then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'no_shipments'));
  end if;

  v_credit_outcome := v_job.credit_snapshot ->> 'outcome';
  if v_job.credit_snapshot is null then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'billing_profile_missing'));
  elsif v_credit_outcome <> 'allow' then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'billing_profile_not_cleared', 'creditOutcome', v_credit_outcome));
  end if;

  v_evaluated_status := case when jsonb_array_length(v_blockers) = 0 then 'ready' else 'not_ready' end;
  v_evidence := jsonb_build_object(
    'shipmentOrderIds', to_jsonb(v_shipment_ids),
    'actualCostIds', to_jsonb(v_actual_cost_ids),
    'epodCaptureIds', to_jsonb(v_epod_capture_ids),
    'creditOutcome', v_credit_outcome,
    'jobOrderStatus', v_job.status
  );

  if v_has_existing then
    update app.billing_readiness_evaluations set is_current = false where id = v_existing.id;
  end if;

  insert into app.billing_readiness_evaluations (
    tenant_id, job_order_id, version_number, evaluated_status, blockers, evidence, rule_version,
    reevaluation_reason, supersedes_evaluation_id, evaluated_by_auth_user_id, evaluated_by, created_by
  ) values (
    v_job.tenant_id, p_job_order_id, coalesce(v_existing.version_number, 0) + 1, v_evaluated_status, v_blockers, v_evidence, 1,
    p_reevaluation_reason, v_existing.id, p_actor_auth_user_id, p_actor_label, p_actor_label
  )
  returning * into v_new;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'evaluate_billing_readiness',
    'app.billing_readiness_evaluations', v_new.id, 'success', p_reevaluation_reason,
    case when v_existing.id is not null then jsonb_build_object('evaluated_status', v_existing.evaluated_status) else null end,
    jsonb_build_object('evaluated_status', v_new.evaluated_status, 'blockers', v_new.blockers)
  );

  return v_new;
end;
$function$;

CREATE OR REPLACE FUNCTION app.evaluate_shipment_document_checklist_completeness(p_shipment_order_id uuid, p_actor_auth_user_id uuid)
 RETURNS TABLE(is_complete boolean, missing_mandatory jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_missing jsonb;
begin
  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('checklist_item_id', ci.id, 'document_type_code', ci.document_type_code, 'party', ci.party)), '[]'::jsonb)
  into v_missing
  from app.shipment_document_checklist_items ci
  left join app.files f on f.id = ci.file_id
  where ci.shipment_order_id = p_shipment_order_id
    and ci.criticality = 'mandatory'
    and not (
      ci.review_status = 'approved'
      and (ci.expires_at is null or ci.expires_at > now())
      and f.malware_scan_status = 'clean'
    );

  return query select (jsonb_array_length(v_missing) = 0), v_missing;
end;
$function$;

CREATE OR REPLACE FUNCTION app.get_dispatch_readiness(p_shipment_order_id uuid, p_actor_auth_user_id uuid)
 RETURNS TABLE(is_ready boolean, blockers jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.evaluate_dispatch_readiness(p_shipment_order_id);
end;
$function$;

CREATE OR REPLACE FUNCTION app.get_epod_capture_history(p_shipment_order_id uuid, p_actor_auth_user_id uuid)
 RETURNS SETOF app.epod_captures
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  select * into v_shipment from app.shipment_orders so where so.id = p_shipment_order_id;
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.epod_captures where shipment_order_id = p_shipment_order_id order by version_group_id, version_number asc;
end;
$function$;

CREATE OR REPLACE FUNCTION app.get_exception_escalation_history(p_exception_id uuid, p_actor_auth_user_id uuid)
 RETURNS SETOF app.exception_escalations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_exception app.operational_exceptions;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  select * into v_exception from app.operational_exceptions where id = p_exception_id;
  if not found or not app.has_active_tenant_membership(v_exception.tenant_id, p_actor_auth_user_id) then
    raise exception 'exception_not_found: %', p_exception_id using errcode = 'no_data_found';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_exception.shipment_order_id;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_exception.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_exception.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_exception.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.exception_escalations where exception_id = p_exception_id order by escalated_at asc;
end;
$function$;

CREATE OR REPLACE FUNCTION app.get_resource_assignment_history(p_shipment_order_id uuid, p_actor_auth_user_id uuid)
 RETURNS SETOF app.resource_assignments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
    select * from app.resource_assignments
    where shipment_order_id = p_shipment_order_id
    order by created_at asc;
end;
$function$;

CREATE OR REPLACE FUNCTION app.get_shipment_document_checklist(p_shipment_order_id uuid, p_actor_auth_user_id uuid)
 RETURNS TABLE(id uuid, requirement_definition_id uuid, party text, document_type_code text, criticality text, file_id uuid, malware_scan_status text, review_status text, reviewed_by_auth_user_id uuid, reviewed_at timestamp with time zone, review_notes text, expires_at timestamp with time zone, effective_status text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  select * into v_shipment from app.shipment_orders so where so.id = p_shipment_order_id;
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select
    ci.id, ci.requirement_definition_id, ci.party, ci.document_type_code, ci.criticality,
    ci.file_id, f.malware_scan_status, ci.review_status, ci.reviewed_by_auth_user_id, ci.reviewed_at, ci.review_notes, ci.expires_at,
    case
      when ci.review_status = 'approved' and (ci.expires_at is null or ci.expires_at > now()) then 'approved'
      when ci.review_status = 'approved' and ci.expires_at <= now() then 'expired'
      when ci.review_status = 'rejected' then 'rejected'
      when ci.file_id is not null then 'pending_review'
      else 'missing'
    end as effective_status
  from app.shipment_document_checklist_items ci
  left join app.files f on f.id = ci.file_id
  where ci.shipment_order_id = p_shipment_order_id
  order by ci.pinned_at asc;
end;
$function$;

CREATE OR REPLACE FUNCTION app.get_shipment_milestone_projection(p_shipment_order_id uuid, p_actor_auth_user_id uuid)
 RETURNS app.shipment_milestone_projections
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_projection app.shipment_milestone_projections;
begin
  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_projection from app.shipment_milestone_projections where shipment_order_id = p_shipment_order_id;
  return v_projection;
end;
$function$;

CREATE OR REPLACE FUNCTION app.get_shipment_milestone_timeline(p_shipment_order_id uuid, p_actor_auth_user_id uuid, p_customer_visible_only boolean DEFAULT false)
 RETURNS SETOF app.milestone_events
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
    select e.* from app.milestone_events e
    join app.milestone_codes mc on mc.code = e.milestone_code
    where e.shipment_order_id = p_shipment_order_id
      and (not p_customer_visible_only or mc.is_customer_visible)
    order by e.event_time asc, e.received_time asc, e.sequence_no asc;
end;
$function$;

CREATE OR REPLACE FUNCTION app.handoff_billing_readiness(p_job_order_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.billing_readiness_handoffs
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_job app.job_orders;
  v_decision app.rbac_decision;
  v_current app.billing_readiness_evaluations;
  v_handoff app.billing_readiness_handoffs;
begin
  select * into v_job from app.job_orders where id = p_job_order_id;
  if not found or not app.has_active_tenant_membership(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'job_order_not_found: %', p_job_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_job.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_job.tenant_id, v_job.owner_user_id, app.lead_record_scope_org_unit_ids(v_job.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access job order %', p_actor_auth_user_id, p_job_order_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: a non-empty idempotency_key is required' using errcode = 'check_violation';
  end if;

  select * into v_current from app.billing_readiness_evaluations where job_order_id = p_job_order_id and is_current;
  if not found then
    raise exception 'billing_readiness_not_evaluated: job order % has never been evaluated', p_job_order_id using errcode = 'no_data_found';
  end if;
  if v_current.effective_status <> 'ready' then
    raise exception 'billing_readiness_not_ready: job order % is not effectively ready for billing handoff', p_job_order_id using errcode = 'check_violation';
  end if;

  begin
    insert into app.billing_readiness_handoffs (
      tenant_id, job_order_id, evaluation_id, idempotency_key, handed_off_by_auth_user_id, handed_off_by
    ) values (
      v_job.tenant_id, p_job_order_id, v_current.id, p_idempotency_key, p_actor_auth_user_id, p_actor_label
    )
    returning * into v_handoff;

    perform app.capture_audit_event(
      v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'handoff_billing_readiness',
      'app.billing_readiness_handoffs', v_handoff.id, 'success', null, null,
      jsonb_build_object('evaluation_id', v_current.id, 'idempotency_key', p_idempotency_key)
    );
  exception
    when unique_violation then
      select * into v_handoff from app.billing_readiness_handoffs
      where tenant_id = v_job.tenant_id and job_order_id = p_job_order_id and idempotency_key = p_idempotency_key;
  end;

  return v_handoff;
end;
$function$;

CREATE OR REPLACE FUNCTION app.hold_resource_assignment(p_shipment_order_id uuid, p_role text, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.resource_assignments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_current app.resource_assignments;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: holding a resource assignment requires a non-empty reason' using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_current
  from app.resource_assignments
  where tenant_id = v_shipment.tenant_id and shipment_order_id = p_shipment_order_id and role = p_role and is_current;
  if not found then
    raise exception 'no_current_assignment: shipment order % has no current % assignment', p_shipment_order_id, p_role
      using errcode = 'check_violation';
  end if;
  if v_current.status <> 'active' then
    raise exception 'invalid_transition: current % assignment on shipment order % is % -- only an active assignment may be held', p_role, p_shipment_order_id, v_current.status
      using errcode = 'check_violation';
  end if;

  update app.resource_assignments
  set status = 'held', reason = p_reason
  where id = v_current.id
  returning * into v_current;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'hold_resource_assignment',
    'app.resource_assignments', v_current.id, 'success', null, null,
    jsonb_build_object('shipment_order_id', p_shipment_order_id, 'role', p_role, 'reason', p_reason)
  );

  return v_current;
end;
$function$;

CREATE OR REPLACE FUNCTION app.ingest_milestone_event(p_shipment_order_id uuid, p_milestone_code text, p_event_time timestamp with time zone, p_received_time timestamp with time zone, p_location jsonb, p_source text, p_reason text, p_corrects_event_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text, p_source_class text DEFAULT NULL::text, p_source_confidence_score numeric DEFAULT NULL::numeric, p_source_freshness_status text DEFAULT NULL::text, p_source_candidate_id uuid DEFAULT NULL::uuid)
 RETURNS app.milestone_events
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_corrected app.milestone_events;
  v_next_seq integer;
  v_event app.milestone_events;
begin
  if p_source not in ('manual', 'api', 'webhook', 'import', 'system') then
    raise exception 'milestone_invalid_source: % is not one of manual/api/webhook/import/system', p_source using errcode = 'check_violation';
  end if;
  if not exists (select 1 from app.milestone_codes where code = p_milestone_code) then
    raise exception 'milestone_unknown_code: % is not a registered milestone code', p_milestone_code using errcode = 'check_violation';
  end if;
  if p_source_class is not null and p_source_class not in ('driver_mobile', 'direct_device', 'third_party_platform') then
    raise exception 'milestone_invalid_source_class: % is not a supported telemetry source class', p_source_class using errcode = 'check_violation';
  end if;
  if p_source_confidence_score is not null and (p_source_confidence_score < 0 or p_source_confidence_score > 1) then
    raise exception 'milestone_invalid_confidence: source_confidence_score must be between 0 and 1' using errcode = 'check_violation';
  end if;
  if p_source_freshness_status is not null and p_source_freshness_status not in ('healthy', 'stale', 'offline') then
    raise exception 'milestone_invalid_freshness: % is not a supported freshness status', p_source_freshness_status using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;
  if v_shipment.status = 'cancelled' then
    raise exception 'invalid_transition: shipment order % is cancelled and can no longer receive milestone events', p_shipment_order_id
      using errcode = 'check_violation';
  end if;

  if p_corrects_event_id is not null then
    if p_reason is null or length(trim(p_reason)) = 0 then
      raise exception 'reason_required: a correction requires a non-empty reason' using errcode = 'check_violation';
    end if;
    select * into v_corrected from app.milestone_events where id = p_corrects_event_id and shipment_order_id = p_shipment_order_id;
    if not found then
      raise exception 'milestone_event_not_found: % is not a prior event on shipment order %', p_corrects_event_id, p_shipment_order_id
        using errcode = 'no_data_found';
    end if;
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_event from app.milestone_events where tenant_id = v_shipment.tenant_id and shipment_order_id = p_shipment_order_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
    -- conflict, never a replay. Returning the earlier target's row here silently
    -- misattributed this request to it (or silently discarded it entirely).
    if v_event.milestone_code is distinct from p_milestone_code then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different milestone event (milestone %, not %)', p_idempotency_key, v_event.milestone_code, p_milestone_code
        using errcode = 'unique_violation';
    end if;
    return v_event;
  end if;

  select coalesce(max(sequence_no), 0) + 1 into v_next_seq from app.milestone_events where shipment_order_id = p_shipment_order_id;

  insert into app.milestone_events (
    tenant_id, shipment_order_id, milestone_code, event_time, received_time, location, source, reason, corrects_event_id, idempotency_key, sequence_no, created_by,
    source_class, source_confidence_score, source_freshness_status, source_candidate_id
  ) values (
    v_shipment.tenant_id, p_shipment_order_id, p_milestone_code, p_event_time, coalesce(p_received_time, now()), p_location, p_source, p_reason, p_corrects_event_id, p_idempotency_key, v_next_seq, p_actor_label,
    p_source_class, p_source_confidence_score, p_source_freshness_status, p_source_candidate_id
  )
  returning * into v_event;

  perform app.recalculate_shipment_milestone_projection(p_shipment_order_id);

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'ingest_milestone_event',
    'app.milestone_events', v_event.id, 'success', null, null,
    jsonb_build_object('shipment_order_id', p_shipment_order_id, 'milestone_code', p_milestone_code, 'source', p_source, 'corrects_event_id', p_corrects_event_id, 'source_class', p_source_class)
  );

  return v_event;
exception
  when unique_violation then
    select * into v_event from app.milestone_events where tenant_id = v_shipment.tenant_id and shipment_order_id = p_shipment_order_id and idempotency_key = p_idempotency_key;
    if not found then
      raise;
    end if;
    -- ATW-032 (ISS-2026-034): the ATW-031 guard in the body above raises with
    -- errcode = 'unique_violation', which is exactly the condition THIS handler traps --
    -- so the guard was caught here and the mismatched row returned anyway, and the
    -- misattribution it was written to stop still happened. Re-applying the discriminator
    -- inside the handler is what makes it real: an exception raised from within a handler
    -- is not re-caught by that same handler, so this one propagates.
    if v_event.milestone_code is distinct from p_milestone_code then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different milestone event (milestone %, not %)', p_idempotency_key, v_event.milestone_code, p_milestone_code
        using errcode = 'unique_violation';
    end if;
    return v_event;
end;
$function$;

CREATE OR REPLACE FUNCTION app.issue_shipment_tracking_token(p_shipment_order_id uuid, p_validity_days integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS TABLE(token_id uuid, raw_token text, expires_at timestamp with time zone, shipment_order_id uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'public', 'extensions', 'pg_temp'
AS $function$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_existing app.shipment_tracking_tokens;
  v_raw_token text;
  v_token_hash text;
  v_expires_at timestamptz;
  v_token app.shipment_tracking_tokens;
begin
  select * into v_shipment from app.shipment_orders so where so.id = p_shipment_order_id;
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if coalesce(p_validity_days, 0) <= 0 then
    raise exception 'tracking_invalid_validity_days: validity_days must be positive' using errcode = 'check_violation';
  end if;

  update app.shipment_tracking_tokens t
  set status = 'revoked', revoked_at = now(), revoked_reason = 'superseded_by_new_issuance'
  where t.shipment_order_id = p_shipment_order_id and t.status = 'active'
  returning * into v_existing;

  v_raw_token := encode(gen_random_bytes(32), 'hex');
  v_token_hash := encode(digest(v_raw_token, 'sha256'), 'hex');
  v_expires_at := now() + (p_validity_days || ' days')::interval;

  insert into app.shipment_tracking_tokens (tenant_id, shipment_order_id, token_hash, expires_at, created_by)
  values (v_shipment.tenant_id, p_shipment_order_id, v_token_hash, v_expires_at, p_actor_label)
  returning * into v_token;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'issue_shipment_tracking_token',
    'app.shipment_tracking_tokens', v_token.id, 'success', null, null, jsonb_build_object('expires_at', v_expires_at)
  );

  return query select v_token.id, v_raw_token, v_token.expires_at, p_shipment_order_id;
end;
$function$;

CREATE OR REPLACE FUNCTION app.link_document_to_checklist_item(p_checklist_item_id uuid, p_file_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.shipment_document_checklist_items
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_item app.shipment_document_checklist_items;
  v_shipment app.shipment_orders;
  v_file app.files;
  v_decision app.rbac_decision;
  v_updated app.shipment_document_checklist_items;
begin
  select * into v_item from app.shipment_document_checklist_items where id = p_checklist_item_id;
  if not found or not app.has_active_tenant_membership(v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'document_checklist_item_not_found: %', p_checklist_item_id using errcode = 'no_data_found';
  end if;
  select * into v_shipment from app.shipment_orders where id = v_item.shipment_order_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_item.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_item.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_file from app.files where id = p_file_id;
  if not found then
    raise exception 'document_file_not_found: %', p_file_id using errcode = 'no_data_found';
  end if;
  if v_file.tenant_id <> v_item.tenant_id then
    raise exception 'document_checklist_cross_tenant: file % does not belong to tenant %', p_file_id, v_item.tenant_id
      using errcode = 'check_violation';
  end if;
  if v_file.record_type <> 'shipment_order' or v_file.record_id <> v_item.shipment_order_id then
    raise exception 'document_checklist_record_mismatch: file % is not linked to shipment order %', p_file_id, v_item.shipment_order_id
      using errcode = 'check_violation';
  end if;
  if v_file.document_type_code <> v_item.document_type_code then
    raise exception 'document_checklist_type_mismatch: file % is a % document, checklist item requires %', p_file_id, v_file.document_type_code, v_item.document_type_code
      using errcode = 'check_violation';
  end if;
  if v_file.deleted_at is not null then
    raise exception 'document_checklist_file_deleted: file % has been deleted', p_file_id using errcode = 'check_violation';
  end if;

  update app.shipment_document_checklist_items
  set file_id = p_file_id, review_status = 'pending', reviewed_by_auth_user_id = null, reviewed_at = null, review_notes = null, expires_at = null
  where id = p_checklist_item_id
  returning * into v_updated;

  insert into app.document_checklist_events (tenant_id, checklist_item_id, event_type, file_id, actor_auth_user_id)
  values (v_item.tenant_id, v_updated.id, 'linked', p_file_id, p_actor_auth_user_id);

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'link_document_to_checklist_item',
    'app.shipment_document_checklist_items', v_updated.id, 'success', null, to_jsonb(v_item), to_jsonb(v_updated)
  );

  return v_updated;
end;
$function$;

CREATE OR REPLACE FUNCTION app.list_actual_cost_components(p_actual_cost_id uuid, p_actor_auth_user_id uuid)
 RETURNS SETOF app.shipment_actual_cost_components
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_cost app.shipment_actual_costs;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  select * into v_cost from app.shipment_actual_costs where id = p_actual_cost_id;
  if not found or not app.has_active_tenant_membership(v_cost.tenant_id, p_actor_auth_user_id) then
    raise exception 'actual_cost_not_found: %', p_actual_cost_id using errcode = 'no_data_found';
  end if;
  select * into v_shipment from app.shipment_orders so where so.id = v_cost.shipment_order_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_cost.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_cost.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.has_view_actual_cost(v_cost.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks OPS:View cost for tenant %', p_actor_auth_user_id, v_cost.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_cost.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.shipment_actual_cost_components where actual_cost_id = p_actual_cost_id order by created_at asc;
end;
$function$;

CREATE OR REPLACE FUNCTION app.override_billing_readiness(p_job_order_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.billing_readiness_evaluations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_job app.job_orders;
  v_decision app.rbac_decision;
  v_current app.billing_readiness_evaluations;
  v_updated app.billing_readiness_evaluations;
begin
  select * into v_job from app.job_orders where id = p_job_order_id;
  if not found or not app.has_active_tenant_membership(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'job_order_not_found: %', p_job_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_job.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_job.tenant_id, v_job.owner_user_id, app.lead_record_scope_org_unit_ids(v_job.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access job order %', p_actor_auth_user_id, p_job_order_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_current from app.billing_readiness_evaluations where job_order_id = p_job_order_id and is_current;
  if not found then
    raise exception 'billing_readiness_not_evaluated: job order % has never been evaluated', p_job_order_id using errcode = 'no_data_found';
  end if;
  if v_current.record_version <> p_expected_version then
    raise exception 'stale_version: billing readiness evaluation % expected version % but found %', v_current.id, p_expected_version, v_current.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'billing_readiness_override_reason_required: a non-empty reason is required to override a billing-readiness evaluation' using errcode = 'check_violation';
  end if;
  if v_current.effective_status = 'ready' then
    raise exception 'billing_readiness_override_not_needed: job order % is already effectively ready', p_job_order_id using errcode = 'check_violation';
  end if;

  update app.billing_readiness_evaluations
  set is_overridden = true, override_reason = p_reason, overridden_by_auth_user_id = p_actor_auth_user_id, overridden_by = p_actor_label, overridden_at = now(),
      override_revoked_reason = null, override_revoked_by = null, override_revoked_at = null
  where id = v_current.id and record_version = p_expected_version
  returning * into v_updated;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: override_billing_readiness target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'override_billing_readiness',
    'app.billing_readiness_evaluations', v_updated.id, 'success', p_reason,
    jsonb_build_object('evaluated_status', v_current.evaluated_status),
    jsonb_build_object('effective_status', v_updated.effective_status, 'override_reason', p_reason)
  );

  return v_updated;
end;
$function$;

CREATE OR REPLACE FUNCTION app.override_job_order_field(p_job_order_id uuid, p_expected_version integer, p_snapshot_column text, p_field_path text, p_new_value jsonb, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.job_orders
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_job_order app.job_orders;
  v_decision app.rbac_decision;
  v_previous_value jsonb;
begin
  if p_snapshot_column not in ('customer_snapshot', 'cargo_service_snapshot') then
    raise exception 'invalid_snapshot_column: % is not an overridable snapshot', p_snapshot_column using errcode = 'check_violation';
  end if;

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'override_reason_required: a non-empty reason is required to override a Job Order snapshot field' using errcode = 'check_violation';
  end if;

  select * into v_job_order from app.job_orders where id = p_job_order_id;
  if not found or not app.has_active_tenant_membership(v_job_order.tenant_id, p_actor_auth_user_id) then
    raise exception 'job_order_not_found: %', p_job_order_id using errcode = 'no_data_found';
  end if;

  if v_job_order.record_version <> p_expected_version then
    raise exception 'stale_version: job order % expected version % but found %', p_job_order_id, p_expected_version, v_job_order.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_job_order.status = 'cancelled' then
    raise exception 'invalid_transition: job order % is cancelled and cannot be overridden', p_job_order_id
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_job_order.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_job_order.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_job_order.tenant_id, v_job_order.owner_user_id, app.lead_record_scope_org_unit_ids(v_job_order.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access job order %', p_actor_auth_user_id, p_job_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_snapshot_column = 'customer_snapshot' then
    v_previous_value := v_job_order.customer_snapshot #> string_to_array(p_field_path, '.');
    update app.job_orders
    set customer_snapshot = jsonb_set(customer_snapshot, string_to_array(p_field_path, '.'), p_new_value, true)
    where id = p_job_order_id and record_version = p_expected_version
    returning * into v_job_order;
    -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
    -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
    -- execution fell straight through with a NULL composite, so the audit trail gained a
    -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
    -- record instead of the 'stale_version' its own error contract already handles.
    if not found then
      raise exception 'stale_version: override_job_order_field target row was concurrently modified (expected version %)', p_expected_version
        using errcode = 'serialization_failure';
    end if;
  else
    v_previous_value := v_job_order.cargo_service_snapshot #> string_to_array(p_field_path, '.');
    update app.job_orders
    set cargo_service_snapshot = jsonb_set(cargo_service_snapshot, string_to_array(p_field_path, '.'), p_new_value, true)
    where id = p_job_order_id and record_version = p_expected_version
    returning * into v_job_order;
    -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
    -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
    -- execution fell straight through with a NULL composite, so the audit trail gained a
    -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
    -- record instead of the 'stale_version' its own error contract already handles.
    if not found then
      raise exception 'stale_version: override_job_order_field target row was concurrently modified (expected version %)', p_expected_version
        using errcode = 'serialization_failure';
    end if;
  end if;

  insert into app.job_order_overrides (
    tenant_id, job_order_id, snapshot_column, field_path, previous_value, new_value, reason, overridden_by
  ) values (
    v_job_order.tenant_id, p_job_order_id, p_snapshot_column, p_field_path, v_previous_value, p_new_value, p_reason, p_actor_label
  );

  perform app.capture_audit_event(
    v_job_order.tenant_id, p_actor_auth_user_id, p_actor_label, 'override_job_order_field',
    'app.job_orders', v_job_order.id, 'success', null,
    jsonb_build_object('field_path', p_field_path, 'previous_value', v_previous_value),
    jsonb_build_object('field_path', p_field_path, 'new_value', p_new_value, 'reason', p_reason)
  );

  return v_job_order;
end;
$function$;

CREATE OR REPLACE FUNCTION app.pin_shipment_document_checklist(p_shipment_order_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS SETOF app.shipment_document_checklist_items
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_def record;
  v_item app.shipment_document_checklist_items;
begin
  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  for v_def in
    select * from app.document_requirement_definitions
    where tenant_id = v_shipment.tenant_id and status = 'published'
      and (mode is null or mode = v_shipment.mode)
      and (service_type is null or service_type = v_shipment.service_type)
  loop
    insert into app.shipment_document_checklist_items (tenant_id, shipment_order_id, requirement_definition_id, party, document_type_code, criticality)
    values (v_shipment.tenant_id, v_shipment.id, v_def.id, v_def.party, v_def.document_type_code, v_def.criticality)
    on conflict (tenant_id, shipment_order_id, requirement_definition_id) do nothing
    returning * into v_item;

    if found then
      insert into app.document_checklist_events (tenant_id, checklist_item_id, event_type, actor_auth_user_id, notes)
      values (v_shipment.tenant_id, v_item.id, 'pinned', p_actor_auth_user_id, 'requirement=' || v_def.id::text);
    end if;
  end loop;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'pin_shipment_document_checklist',
    'app.shipment_orders', v_shipment.id, 'success', null, null, '{}'::jsonb
  );

  return query select * from app.shipment_document_checklist_items where shipment_order_id = p_shipment_order_id order by pinned_at asc;
end;
$function$;

CREATE OR REPLACE FUNCTION app.prepare_job_order(p_source_handoff_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.job_orders
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_handoff app.job_order_handoffs;
  v_decision app.rbac_decision;
  v_existing app.job_orders;
  v_job_order app.job_orders;
  v_number text;
  v_quotation_version integer;
  v_lineage jsonb;
begin
  select * into v_handoff from app.job_order_handoffs where id = p_source_handoff_id;
  if not found or not app.has_active_tenant_membership(v_handoff.tenant_id, p_actor_auth_user_id) then
    raise exception 'handoff_not_found: %', p_source_handoff_id using errcode = 'no_data_found';
  end if;

  select * into v_existing from app.job_orders where tenant_id = v_handoff.tenant_id and source_handoff_id = p_source_handoff_id;
  if found then
    return v_existing;
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_handoff.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_handoff.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_handoff.tenant_id, v_handoff.owner_user_id, app.lead_record_scope_org_unit_ids(v_handoff.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access job order handoff %', p_actor_auth_user_id, p_source_handoff_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_handoff.payload is null then
    raise exception 'handoff_payload_unavailable: handoff % carries no payload to convert', p_source_handoff_id
      using errcode = 'check_violation';
  end if;

  v_number := app.next_job_order_number(v_handoff.tenant_id);

  -- ISS-2026-203 fix: the same immutable quotation row/version every snapshot below was
  -- built from (v_handoff.quotation_id is already the live FK pinned to it) -- reads the
  -- real, canonical app.quotations.version_number column, never re-derived from the
  -- handoff payload's own already-copied source.versionNumber value.
  select version_number into v_quotation_version from app.quotations where id = v_handoff.quotation_id;
  v_lineage := jsonb_build_object('quotationId', v_handoff.quotation_id, 'quotationVersion', v_quotation_version);

  begin
    insert into app.job_orders (
      tenant_id, job_number, source_handoff_id, quotation_id, account_id,
      customer_snapshot, cargo_service_snapshot, revenue_snapshot, contract_snapshot, credit_snapshot, acceptance_snapshot,
      owner_user_id, created_by
    ) values (
      v_handoff.tenant_id, v_number, v_handoff.id, v_handoff.quotation_id, v_handoff.account_id,
      (v_handoff.payload -> 'customer') || v_lineage, (v_handoff.payload -> 'cargoService') || v_lineage, (v_handoff.payload -> 'pricing') || v_lineage,
      v_handoff.payload -> 'contract', v_handoff.payload -> 'credit', (v_handoff.payload -> 'acceptance') || v_lineage,
      p_actor_auth_user_id, p_actor_label
    )
    returning * into v_job_order;
  exception
    when unique_violation then
      -- HDN-387 (ISS-2026-163 fix, preserved verbatim from the true latest body): re-select
      -- on the correct idempotency key and require `found` before returning, else re-raise
      -- -- never silently return an all-NULL app.job_orders composite for an unrelated
      -- unique_violation (e.g. the table's own separate job_orders_tenant_number_unique
      -- constraint).
      select * into v_job_order from app.job_orders where tenant_id = v_handoff.tenant_id and source_handoff_id = p_source_handoff_id;
      if found then
        return v_job_order;
      end if;
      raise;
  end;

  perform app.capture_audit_event(
    v_handoff.tenant_id, p_actor_auth_user_id, p_actor_label, 'prepare_job_order',
    'app.job_orders', v_job_order.id, 'success', null, null,
    jsonb_build_object('source_handoff_id', p_source_handoff_id, 'job_number', v_number)
  );

  return v_job_order;
end;
$function$;

CREATE OR REPLACE FUNCTION app.publish_exception_sla_policy_version(p_version_id uuid, p_expected_version integer, p_supersedes_version_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.exception_sla_policy_versions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_version app.exception_sla_policy_versions;
  v_superseded app.exception_sla_policy_versions;
  v_decision app.rbac_decision;
begin
  select * into v_version from app.exception_sla_policy_versions where id = p_version_id;
  if not found or not app.has_active_tenant_membership(v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'exception_sla_policy_not_found: %', p_version_id using errcode = 'no_data_found';
  end if;
  if v_version.record_version <> p_expected_version then
    raise exception 'stale_version: exception SLA policy % expected version % but found %', p_version_id, p_expected_version, v_version.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_version.status <> 'draft' then
    raise exception 'invalid_transition: exception SLA policy % is % and cannot be published', p_version_id, v_version.status
      using errcode = 'check_violation';
  end if;
  if v_version.sla_hours is null then
    raise exception 'exception_invalid_sla_hours: a policy cannot publish without sla_hours set' using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_version.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_supersedes_version_id is not null then
    select * into v_superseded from app.exception_sla_policy_versions where id = p_supersedes_version_id;
    if not found then
      raise exception 'exception_sla_policy_not_found: supersedes target % not found', p_supersedes_version_id using errcode = 'no_data_found';
    end if;
    if v_superseded.status = 'published' then
      update app.exception_sla_policy_versions set status = 'archived' where id = p_supersedes_version_id;
    end if;
  end if;

  update app.exception_sla_policy_versions
  set status = 'published', supersedes_version_id = p_supersedes_version_id
  where id = p_version_id and record_version = p_expected_version
  returning * into v_version;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: publish_exception_sla_policy_version target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_exception_sla_policy_version',
    'app.exception_sla_policy_versions', v_version.id, 'success', null, null,
    jsonb_build_object('type', v_version.type, 'severity', v_version.severity, 'supersedes_version_id', p_supersedes_version_id)
  );

  return v_version;
end;
$function$;

CREATE OR REPLACE FUNCTION app.publish_milestone_template_version(p_version_id uuid, p_expected_version integer, p_supersedes_version_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.milestone_template_versions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_version app.milestone_template_versions;
  v_superseded app.milestone_template_versions;
  v_decision app.rbac_decision;
  v_element jsonb;
  v_seen text[] := array[]::text[];
  v_code text;
begin
  select * into v_version from app.milestone_template_versions where id = p_version_id;
  if not found or not app.has_active_tenant_membership(v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'milestone_template_not_found: %', p_version_id using errcode = 'no_data_found';
  end if;
  if v_version.record_version <> p_expected_version then
    raise exception 'stale_version: milestone template % expected version % but found %', p_version_id, p_expected_version, v_version.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_version.status <> 'draft' then
    raise exception 'invalid_transition: milestone template % is % and cannot be published', p_version_id, v_version.status
      using errcode = 'check_violation';
  end if;
  if jsonb_array_length(v_version.sequence) = 0 then
    raise exception 'milestone_invalid_sequence: a milestone template cannot publish with an empty sequence' using errcode = 'check_violation';
  end if;

  for v_element in select * from jsonb_array_elements(v_version.sequence) loop
    v_code := v_element ->> 'code';
    if not exists (select 1 from app.milestone_codes where code = v_code) then
      raise exception 'milestone_unknown_code: % is not a registered milestone code', v_code using errcode = 'check_violation';
    end if;
    if v_code = any (v_seen) then
      raise exception 'milestone_duplicate_code: % appears more than once in the sequence', v_code using errcode = 'check_violation';
    end if;
    v_seen := array_append(v_seen, v_code);
  end loop;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_version.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_supersedes_version_id is not null then
    select * into v_superseded from app.milestone_template_versions where id = p_supersedes_version_id;
    if not found then
      raise exception 'milestone_template_not_found: supersedes target % not found', p_supersedes_version_id using errcode = 'no_data_found';
    end if;
    -- ATW-032: the supersede target was previously resolved by id ALONE and then archived,
    -- while the authority check above is against the tenant of the version being PUBLISHED.
    -- A tenant admin could therefore pass another tenant's published template version id and
    -- archive it -- a cross-tenant write, and exactly the class CPD-004/INV-002 exist to
    -- prevent. The target must belong to the same tenant as the version being published.
    if v_superseded.tenant_id <> v_version.tenant_id then
      raise exception 'milestone_template_not_found: supersedes target % is not a template version of tenant %', p_supersedes_version_id, v_version.tenant_id
        using errcode = 'no_data_found';
    end if;
    if v_superseded.status = 'published' then
      update app.milestone_template_versions set status = 'archived' where id = p_supersedes_version_id;
    end if;
  end if;

  update app.milestone_template_versions
  set status = 'published', supersedes_version_id = p_supersedes_version_id
  where id = p_version_id and record_version = p_expected_version
  returning * into v_version;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: publish_milestone_template_version target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_milestone_template_version',
    'app.milestone_template_versions', v_version.id, 'success', null, null,
    jsonb_build_object('mode', v_version.mode, 'supersedes_version_id', p_supersedes_version_id)
  );

  return v_version;
end;
$function$;

CREATE OR REPLACE FUNCTION app.reassign_resource(p_shipment_order_id uuid, p_role text, p_new_resource_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.resource_assignments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_shipment app.shipment_orders;
  v_resource app.master_records;
  v_decision app.rbac_decision;
  v_prior app.resource_assignments;
  v_assignment app.resource_assignments;
begin
  if p_role not in ('vendor', 'fleet', 'vehicle', 'driver') then
    raise exception 'invalid_role: % is not a supported resource-assignment role', p_role using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: reassigning a resource requires a non-empty reason' using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;
  if v_shipment.status in ('cancelled', 'delivered', 'epod', 'closed') then
    raise exception 'invalid_transition: shipment order % is % and can no longer receive resource assignments', p_shipment_order_id, v_shipment.status
      using errcode = 'check_violation';
  end if;

  select * into v_resource from app.master_records where id = p_new_resource_id;
  if not found or v_resource.master_type_code <> p_role or v_resource.tenant_id <> v_shipment.tenant_id or v_resource.canonical_status <> 'active' then
    raise exception 'invalid_resource: % is not an active % master record for tenant %', p_new_resource_id, p_role, v_shipment.tenant_id
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Assign');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Assign (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_prior
  from app.resource_assignments
  where tenant_id = v_shipment.tenant_id and shipment_order_id = p_shipment_order_id and role = p_role and is_current;
  if not found then
    raise exception 'no_current_assignment: shipment order % has no current % assignment -- use assign_resource', p_shipment_order_id, p_role
      using errcode = 'check_violation';
  end if;

  if exists (
    select 1 from app.resource_assignments ra
    where ra.tenant_id = v_shipment.tenant_id
      and ra.resource_id = p_new_resource_id
      and ra.is_current
      and ra.status = 'active'
      and ra.shipment_order_id <> p_shipment_order_id
  ) then
    raise exception 'assignment_conflict: resource % is already actively assigned on another shipment order', p_new_resource_id
      using errcode = 'check_violation';
  end if;

  update app.resource_assignments
  set is_current = false, effective_to = now()
  where id = v_prior.id;

  insert into app.resource_assignments (
    tenant_id, shipment_order_id, role, resource_id, resource_snapshot, reason, created_by
  ) values (
    v_shipment.tenant_id, p_shipment_order_id, p_role, p_new_resource_id,
    jsonb_build_object('code', v_resource.code, 'name', v_resource.name), p_reason, p_actor_label
  )
  returning * into v_assignment;

  update app.resource_assignments
  set superseded_by_id = v_assignment.id
  where id = v_prior.id;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'reassign_resource',
    'app.resource_assignments', v_assignment.id, 'success', null, null,
    jsonb_build_object('shipment_order_id', p_shipment_order_id, 'role', p_role, 'prior_assignment_id', v_prior.id, 'reason', p_reason)
  );

  return v_assignment;
end;
$function$;

CREATE OR REPLACE FUNCTION app.reopen_exception(p_exception_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.operational_exceptions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_exception app.operational_exceptions;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: reopening an exception requires a non-empty reason' using errcode = 'check_violation';
  end if;

  select * into v_exception from app.operational_exceptions where id = p_exception_id;
  if not found or not app.has_active_tenant_membership(v_exception.tenant_id, p_actor_auth_user_id) then
    raise exception 'exception_not_found: %', p_exception_id using errcode = 'no_data_found';
  end if;
  if v_exception.record_version <> p_expected_version then
    raise exception 'stale_version: exception % expected version % but found %', p_exception_id, p_expected_version, v_exception.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_exception.status not in ('resolved', 'closed') then
    raise exception 'invalid_transition: exception % is % and cannot be reopened', p_exception_id, v_exception.status
      using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_exception.shipment_order_id;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_exception.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_exception.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_exception.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.operational_exceptions
  set status = 'reopened', reopened_at = now()
  where id = p_exception_id and record_version = p_expected_version
  returning * into v_exception;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: reopen_exception target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_exception.tenant_id, p_actor_auth_user_id, p_actor_label, 'reopen_exception',
    'app.operational_exceptions', v_exception.id, 'success', null, null, jsonb_build_object('reason', p_reason)
  );

  return v_exception;
end;
$function$;

CREATE OR REPLACE FUNCTION app.report_exception(p_shipment_order_id uuid, p_milestone_event_id uuid, p_type text, p_severity text, p_description text, p_source text, p_correlation_key text, p_actor_auth_user_id uuid, p_actor_label text, p_source_class text DEFAULT NULL::text, p_source_confidence_score numeric DEFAULT NULL::numeric, p_source_freshness_status text DEFAULT NULL::text, p_source_signal_id uuid DEFAULT NULL::uuid)
 RETURNS app.operational_exceptions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_policy app.exception_sla_policy_versions;
  v_existing app.operational_exceptions;
  v_exception app.operational_exceptions;
begin
  if p_type not in ('delay', 'hold', 'damage', 'loss', 'incident') then
    raise exception 'exception_invalid_type: % is not a supported exception type', p_type using errcode = 'check_violation';
  end if;
  if p_severity not in ('low', 'medium', 'high', 'critical') then
    raise exception 'exception_invalid_severity: % is not a supported severity', p_severity using errcode = 'check_violation';
  end if;
  if p_source not in ('manual', 'system') then
    raise exception 'exception_invalid_source: % is not one of manual/system', p_source using errcode = 'check_violation';
  end if;
  if p_source_class is not null and p_source_class not in ('driver_mobile', 'direct_device', 'third_party_platform') then
    raise exception 'exception_invalid_source_class: % is not a supported telemetry source class', p_source_class using errcode = 'check_violation';
  end if;
  if p_source_confidence_score is not null and (p_source_confidence_score < 0 or p_source_confidence_score > 1) then
    raise exception 'exception_invalid_confidence: source_confidence_score must be between 0 and 1' using errcode = 'check_violation';
  end if;
  if p_source_freshness_status is not null and p_source_freshness_status not in ('healthy', 'stale', 'offline') then
    raise exception 'exception_invalid_freshness: % is not a supported freshness status', p_source_freshness_status using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  if p_milestone_event_id is not null and not exists (select 1 from app.milestone_events where id = p_milestone_event_id and shipment_order_id = p_shipment_order_id) then
    raise exception 'milestone_event_not_found: % is not an event on shipment order %', p_milestone_event_id, p_shipment_order_id
      using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_source = 'system' and p_correlation_key is not null then
    select * into v_existing from app.operational_exceptions
    where tenant_id = v_shipment.tenant_id and shipment_order_id = p_shipment_order_id and correlation_key = p_correlation_key;
    if found then
      return v_existing;
    end if;
  end if;

  select * into v_policy from app.exception_sla_policy_versions
  where tenant_id = v_shipment.tenant_id and type = p_type and severity = p_severity and status = 'published';

  insert into app.operational_exceptions (
    tenant_id, shipment_order_id, milestone_event_id, type, severity, source, correlation_key, description,
    sla_policy_version_id, sla_hours, due_at, created_by,
    source_class, source_confidence_score, source_freshness_status, source_signal_id
  ) values (
    v_shipment.tenant_id, p_shipment_order_id, p_milestone_event_id, p_type, p_severity, p_source, p_correlation_key, p_description,
    v_policy.id, v_policy.sla_hours, case when v_policy.sla_hours is not null then now() + (v_policy.sla_hours || ' hours')::interval else null end,
    p_actor_label,
    p_source_class, p_source_confidence_score, p_source_freshness_status, p_source_signal_id
  )
  returning * into v_exception;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'report_exception',
    'app.operational_exceptions', v_exception.id, 'success', null, null,
    jsonb_build_object('shipment_order_id', p_shipment_order_id, 'type', p_type, 'severity', p_severity, 'source', p_source, 'source_class', p_source_class)
  );

  return v_exception;
exception
  when unique_violation then
    select * into v_exception from app.operational_exceptions
    where tenant_id = v_shipment.tenant_id and shipment_order_id = p_shipment_order_id and correlation_key = p_correlation_key;
    return v_exception;
end;
$function$;

CREATE OR REPLACE FUNCTION app.resolve_exception(p_exception_id uuid, p_expected_version integer, p_resolution_evidence text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.operational_exceptions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_exception app.operational_exceptions;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  if p_resolution_evidence is null or length(trim(p_resolution_evidence)) = 0 then
    raise exception 'evidence_required: resolving an exception requires non-empty resolution_evidence' using errcode = 'check_violation';
  end if;

  select * into v_exception from app.operational_exceptions where id = p_exception_id;
  if not found or not app.has_active_tenant_membership(v_exception.tenant_id, p_actor_auth_user_id) then
    raise exception 'exception_not_found: %', p_exception_id using errcode = 'no_data_found';
  end if;
  if v_exception.record_version <> p_expected_version then
    raise exception 'stale_version: exception % expected version % but found %', p_exception_id, p_expected_version, v_exception.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_exception.status not in ('open', 'acknowledged', 'reopened') then
    raise exception 'invalid_transition: exception % is % and cannot be resolved', p_exception_id, v_exception.status
      using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_exception.shipment_order_id;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_exception.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_exception.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_exception.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.operational_exceptions
  set status = 'resolved', resolution_evidence = p_resolution_evidence, resolved_at = now()
  where id = p_exception_id and record_version = p_expected_version
  returning * into v_exception;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: resolve_exception target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_exception.tenant_id, p_actor_auth_user_id, p_actor_label, 'resolve_exception',
    'app.operational_exceptions', v_exception.id, 'success', null, null, jsonb_build_object('resolution_evidence', p_resolution_evidence)
  );

  return v_exception;
end;
$function$;

CREATE OR REPLACE FUNCTION app.resume_resource_assignment(p_shipment_order_id uuid, p_role text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.resource_assignments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_current app.resource_assignments;
begin
  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_current
  from app.resource_assignments
  where tenant_id = v_shipment.tenant_id and shipment_order_id = p_shipment_order_id and role = p_role and is_current;
  if not found then
    raise exception 'no_current_assignment: shipment order % has no current % assignment', p_shipment_order_id, p_role
      using errcode = 'check_violation';
  end if;
  if v_current.status <> 'held' then
    raise exception 'invalid_transition: current % assignment on shipment order % is % -- only a held assignment may be resumed', p_role, p_shipment_order_id, v_current.status
      using errcode = 'check_violation';
  end if;

  update app.resource_assignments
  set status = 'active'
  where id = v_current.id
  returning * into v_current;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'resume_resource_assignment',
    'app.resource_assignments', v_current.id, 'success', null, null,
    jsonb_build_object('shipment_order_id', p_shipment_order_id, 'role', p_role)
  );

  return v_current;
end;
$function$;

CREATE OR REPLACE FUNCTION app.review_document_checklist_item(p_checklist_item_id uuid, p_decision text, p_notes text, p_expires_at timestamp with time zone, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.shipment_document_checklist_items
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_item app.shipment_document_checklist_items;
  v_shipment app.shipment_orders;
  v_file app.files;
  v_decision app.rbac_decision;
  v_updated app.shipment_document_checklist_items;
begin
  if p_decision not in ('approved', 'rejected') then
    raise exception 'document_checklist_invalid_decision: % is not one of approved/rejected', p_decision using errcode = 'check_violation';
  end if;

  select * into v_item from app.shipment_document_checklist_items where id = p_checklist_item_id;
  if not found or not app.has_active_tenant_membership(v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'document_checklist_item_not_found: %', p_checklist_item_id using errcode = 'no_data_found';
  end if;
  select * into v_shipment from app.shipment_orders where id = v_item.shipment_order_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_item.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_item.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_item.file_id is null then
    raise exception 'document_checklist_no_linked_file: checklist item % has no linked file to review', p_checklist_item_id
      using errcode = 'check_violation';
  end if;

  if p_decision = 'approved' then
    select * into v_file from app.files where id = v_item.file_id;
    if v_file.malware_scan_status <> 'clean' then
      raise exception 'document_checklist_unsafe_file: linked file % has scan status % -- only clean evidence may be approved', v_item.file_id, v_file.malware_scan_status
        using errcode = 'check_violation';
    end if;
  end if;

  update app.shipment_document_checklist_items
  set review_status = p_decision,
      reviewed_by_auth_user_id = p_actor_auth_user_id,
      reviewed_at = now(),
      review_notes = p_notes,
      expires_at = case when p_decision = 'approved' then p_expires_at else null end
  where id = p_checklist_item_id
  returning * into v_updated;

  insert into app.document_checklist_events (tenant_id, checklist_item_id, event_type, file_id, actor_auth_user_id, notes)
  values (v_item.tenant_id, v_updated.id, p_decision, v_item.file_id, p_actor_auth_user_id, p_notes);

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'review_document_checklist_item',
    'app.shipment_document_checklist_items', v_updated.id, 'success', null, to_jsonb(v_item), to_jsonb(v_updated)
  );

  return v_updated;
end;
$function$;

CREATE OR REPLACE FUNCTION app.review_epod_capture(p_capture_id uuid, p_decision text, p_notes text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.epod_captures
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
declare
  v_capture app.epod_captures;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_updated app.epod_captures;
begin
  if p_decision not in ('approved', 'revision_requested') then
    raise exception 'epod_invalid_decision: % is not one of approved/revision_requested', p_decision using errcode = 'check_violation';
  end if;

  select * into v_capture from app.epod_captures where id = p_capture_id for update;
  if not found or not app.has_active_tenant_membership(v_capture.tenant_id, p_actor_auth_user_id) then
    raise exception 'epod_capture_not_found: %', p_capture_id using errcode = 'no_data_found';
  end if;
  if v_capture.record_version <> p_expected_version then
    raise exception 'concurrent_modification: ePOD capture % has moved from expected version % to %', p_capture_id, p_expected_version, v_capture.record_version
      using errcode = 'check_violation';
  end if;
  select * into v_shipment from app.shipment_orders so where so.id = v_capture.shipment_order_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_capture.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_capture.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_capture.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_capture.status <> 'submitted' then
    raise exception 'invalid_transition: ePOD capture % is % and cannot be reviewed', p_capture_id, v_capture.status
      using errcode = 'check_violation';
  end if;
  if p_decision = 'revision_requested' and (p_notes is null or length(trim(p_notes)) = 0) then
    raise exception 'epod_revision_reason_required: notes are required when requesting a revision' using errcode = 'check_violation';
  end if;

  update app.epod_captures
  set status = p_decision, reviewed_by_auth_user_id = p_actor_auth_user_id, reviewed_at = now(), review_notes = p_notes
  where id = p_capture_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_capture.tenant_id, p_actor_auth_user_id, p_actor_label, 'review_epod_capture',
    'app.epod_captures', v_updated.id, 'success', null, to_jsonb(v_capture), to_jsonb(v_updated)
  );

  return v_updated;
end;
$function$;

CREATE OR REPLACE FUNCTION app.revise_epod_capture(p_previous_capture_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.epod_captures
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
declare
  v_prev app.epod_captures;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_new_id uuid := gen_random_uuid();
  v_capture app.epod_captures;
begin
  select * into v_prev from app.epod_captures where id = p_previous_capture_id;
  if not found or not app.has_active_tenant_membership(v_prev.tenant_id, p_actor_auth_user_id) then
    raise exception 'epod_capture_not_found: %', p_previous_capture_id using errcode = 'no_data_found';
  end if;
  select * into v_shipment from app.shipment_orders so where so.id = v_prev.shipment_order_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_prev.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_prev.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_prev.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_prev.status <> 'revision_requested' then
    raise exception 'invalid_transition: ePOD capture % is % and is not awaiting revision', p_previous_capture_id, v_prev.status
      using errcode = 'check_violation';
  end if;
  if not v_prev.is_latest_version then
    raise exception 'epod_not_latest_version: capture % is not the latest version of its group', p_previous_capture_id
      using errcode = 'check_violation';
  end if;

  update app.epod_captures set is_latest_version = false where id = v_prev.id;

  insert into app.epod_captures (
    id, tenant_id, shipment_order_id, milestone_event_id, version_group_id, version_number, is_latest_version,
    status, receiver_name, receiver_position, signature_file_id, photo_file_ids, delivery_geog, captured_at, created_by
  ) values (
    v_new_id, v_prev.tenant_id, v_prev.shipment_order_id, v_prev.milestone_event_id, v_prev.version_group_id, v_prev.version_number + 1, true,
    'draft', v_prev.receiver_name, v_prev.receiver_position, v_prev.signature_file_id, v_prev.photo_file_ids, v_prev.delivery_geog, v_prev.captured_at, p_actor_label
  )
  returning * into v_capture;

  perform app.capture_audit_event(
    v_prev.tenant_id, p_actor_auth_user_id, p_actor_label, 'revise_epod_capture',
    'app.epod_captures', v_capture.id, 'success', null, to_jsonb(v_prev), to_jsonb(v_capture)
  );

  return v_capture;
end;
$function$;

CREATE OR REPLACE FUNCTION app.revoke_billing_readiness_override(p_job_order_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.billing_readiness_evaluations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_job app.job_orders;
  v_decision app.rbac_decision;
  v_current app.billing_readiness_evaluations;
  v_updated app.billing_readiness_evaluations;
begin
  select * into v_job from app.job_orders where id = p_job_order_id;
  if not found or not app.has_active_tenant_membership(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'job_order_not_found: %', p_job_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_job.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_job.tenant_id, v_job.owner_user_id, app.lead_record_scope_org_unit_ids(v_job.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access job order %', p_actor_auth_user_id, p_job_order_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_current from app.billing_readiness_evaluations where job_order_id = p_job_order_id and is_current;
  if not found then
    raise exception 'billing_readiness_not_evaluated: job order % has never been evaluated', p_job_order_id using errcode = 'no_data_found';
  end if;
  if v_current.record_version <> p_expected_version then
    raise exception 'stale_version: billing readiness evaluation % expected version % but found %', v_current.id, p_expected_version, v_current.record_version
      using errcode = 'serialization_failure';
  end if;
  if not v_current.is_overridden then
    raise exception 'billing_readiness_not_overridden: job order % has no active override to revoke', p_job_order_id using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'billing_readiness_revoke_reason_required: a non-empty reason is required to revoke a billing-readiness override' using errcode = 'check_violation';
  end if;

  update app.billing_readiness_evaluations
  set is_overridden = false, override_revoked_reason = p_reason, override_revoked_by = p_actor_label, override_revoked_at = now()
  where id = v_current.id and record_version = p_expected_version
  returning * into v_updated;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: revoke_billing_readiness_override target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'revoke_billing_readiness_override',
    'app.billing_readiness_evaluations', v_updated.id, 'success', p_reason,
    jsonb_build_object('effective_status', 'ready'),
    jsonb_build_object('effective_status', v_updated.effective_status)
  );

  return v_updated;
end;
$function$;

CREATE OR REPLACE FUNCTION app.revoke_shipment_tracking_token(p_shipment_order_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.shipment_tracking_tokens
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_token app.shipment_tracking_tokens;
  v_updated app.shipment_tracking_tokens;
begin
  select * into v_shipment from app.shipment_orders so where so.id = p_shipment_order_id;
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'tracking_revoke_reason_required: a reason is required to revoke a tracking token' using errcode = 'check_violation';
  end if;

  select * into v_token from app.shipment_tracking_tokens where shipment_order_id = p_shipment_order_id and status = 'active';
  if not found then
    raise exception 'tracking_no_active_token: shipment order % has no active tracking token', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  update app.shipment_tracking_tokens
  set status = 'revoked', revoked_at = now(), revoked_reason = p_reason
  where id = v_token.id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'revoke_shipment_tracking_token',
    'app.shipment_tracking_tokens', v_updated.id, 'success', p_reason, to_jsonb(v_token), to_jsonb(v_updated)
  );

  v_updated.token_hash := null;
  return v_updated;
end;
$function$;

CREATE OR REPLACE FUNCTION app.set_epod_evidence(p_capture_id uuid, p_receiver_name text, p_receiver_position text, p_signature_file_id uuid, p_photo_file_ids uuid[], p_delivery_geojson jsonb, p_captured_at timestamp with time zone, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.epod_captures
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'public', 'extensions', 'pg_temp'
AS $function$
declare
  v_capture app.epod_captures;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_file app.files;
  v_photo_id uuid;
  v_geog geography;
  v_updated app.epod_captures;
begin
  select * into v_capture from app.epod_captures where id = p_capture_id;
  if not found or not app.has_active_tenant_membership(v_capture.tenant_id, p_actor_auth_user_id) then
    raise exception 'epod_capture_not_found: %', p_capture_id using errcode = 'no_data_found';
  end if;
  select * into v_shipment from app.shipment_orders so where so.id = v_capture.shipment_order_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_capture.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_capture.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_capture.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_capture.status not in ('draft', 'revision_requested') then
    raise exception 'invalid_transition: ePOD capture % is % and its evidence can no longer be edited', p_capture_id, v_capture.status
      using errcode = 'check_violation';
  end if;

  if p_signature_file_id is not null then
    select * into v_file from app.files where id = p_signature_file_id;
    if not found or v_file.tenant_id <> v_capture.tenant_id or v_file.record_type <> 'shipment_order' or v_file.record_id <> v_capture.shipment_order_id then
      raise exception 'epod_evidence_file_mismatch: signature file % does not belong to shipment order %', p_signature_file_id, v_capture.shipment_order_id
        using errcode = 'check_violation';
    end if;
  end if;

  if p_photo_file_ids is not null then
    foreach v_photo_id in array p_photo_file_ids loop
      select * into v_file from app.files where id = v_photo_id;
      if not found or v_file.tenant_id <> v_capture.tenant_id or v_file.record_type <> 'shipment_order' or v_file.record_id <> v_capture.shipment_order_id then
        raise exception 'epod_evidence_file_mismatch: photo file % does not belong to shipment order %', v_photo_id, v_capture.shipment_order_id
          using errcode = 'check_violation';
      end if;
    end loop;
  end if;

  if p_delivery_geojson is not null then
    v_geog := app.geojson_point_to_geography(p_delivery_geojson);
  end if;

  update app.epod_captures
  set receiver_name = p_receiver_name,
      receiver_position = p_receiver_position,
      signature_file_id = p_signature_file_id,
      photo_file_ids = coalesce(p_photo_file_ids, '{}'::uuid[]),
      delivery_geog = v_geog,
      captured_at = p_captured_at,
      status = 'draft'
  where id = p_capture_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_capture.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_epod_evidence',
    'app.epod_captures', v_updated.id, 'success', null, to_jsonb(v_capture), to_jsonb(v_updated)
  );

  return v_updated;
end;
$function$;

CREATE OR REPLACE FUNCTION app.set_exception_sensitive_fields(p_exception_id uuid, p_internal_notes text, p_damage_loss_details jsonb, p_claim_amount numeric, p_claim_currency text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.operational_exceptions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_exception app.operational_exceptions;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  select * into v_exception from app.operational_exceptions where id = p_exception_id;
  if not found or not app.has_active_tenant_membership(v_exception.tenant_id, p_actor_auth_user_id) then
    raise exception 'exception_not_found: %', p_exception_id using errcode = 'no_data_found';
  end if;
  if p_claim_amount is not null and p_claim_amount < 0 then
    raise exception 'exception_invalid_claim_amount: claim_amount must not be negative' using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_exception.shipment_order_id;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_exception.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_exception.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.has_view_exception_cost(v_exception.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks OPS:View cost for tenant %', p_actor_auth_user_id, v_exception.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_exception.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.operational_exceptions
  set internal_notes = p_internal_notes, damage_loss_details = p_damage_loss_details, claim_amount = p_claim_amount, claim_currency = p_claim_currency
  where id = p_exception_id
  returning * into v_exception;

  perform app.capture_audit_event(
    v_exception.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_exception_sensitive_fields',
    'app.operational_exceptions', v_exception.id, 'success', null, null, '{}'::jsonb
  );

  return v_exception;
end;
$function$;

CREATE OR REPLACE FUNCTION app.set_shipment_mode_profile(p_shipment_order_id uuid, p_land_vehicle_ref text, p_land_vendor_ref text, p_land_pickup_address text, p_land_delivery_address text, p_air_awb_number text, p_air_flight_number text, p_air_origin_airport text, p_air_destination_airport text, p_sea_bl_number text, p_sea_booking_number text, p_sea_vessel_name text, p_sea_origin_port text, p_sea_destination_port text, p_sea_container_number text, p_sea_container_type text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.shipment_mode_profiles
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_profile app.shipment_mode_profiles;
begin
  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  if v_shipment.status = 'cancelled' then
    raise exception 'invalid_transition: shipment order % is cancelled and its mode profile can no longer be set', p_shipment_order_id
      using errcode = 'check_violation';
  end if;

  if v_shipment.mode = 'land' and (p_land_vehicle_ref is null or p_land_vendor_ref is null or p_land_pickup_address is null or p_land_delivery_address is null) then
    raise exception 'missing_required_reference: land mode requires vehicle_ref, vendor_ref, pickup_address and delivery_address' using errcode = 'check_violation';
  end if;
  if v_shipment.mode = 'air' and (p_air_awb_number is null or p_air_flight_number is null or p_air_origin_airport is null or p_air_destination_airport is null) then
    raise exception 'missing_required_reference: air mode requires awb_number, flight_number, origin_airport and destination_airport' using errcode = 'check_violation';
  end if;
  if v_shipment.mode = 'sea' and (p_sea_bl_number is null or p_sea_booking_number is null or p_sea_vessel_name is null or p_sea_origin_port is null or p_sea_destination_port is null) then
    raise exception 'missing_required_reference: sea mode requires bl_number, booking_number, vessel_name, origin_port and destination_port' using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  insert into app.shipment_mode_profiles (
    tenant_id, shipment_order_id, mode,
    land_vehicle_ref, land_vendor_ref, land_pickup_address, land_delivery_address,
    air_awb_number, air_flight_number, air_origin_airport, air_destination_airport,
    sea_bl_number, sea_booking_number, sea_vessel_name, sea_origin_port, sea_destination_port, sea_container_number, sea_container_type,
    created_by
  ) values (
    v_shipment.tenant_id, p_shipment_order_id, v_shipment.mode,
    p_land_vehicle_ref, p_land_vendor_ref, p_land_pickup_address, p_land_delivery_address,
    p_air_awb_number, p_air_flight_number, p_air_origin_airport, p_air_destination_airport,
    p_sea_bl_number, p_sea_booking_number, p_sea_vessel_name, p_sea_origin_port, p_sea_destination_port, p_sea_container_number, p_sea_container_type,
    p_actor_label
  )
  on conflict (shipment_order_id) do update set
    mode = excluded.mode,
    land_vehicle_ref = excluded.land_vehicle_ref, land_vendor_ref = excluded.land_vendor_ref,
    land_pickup_address = excluded.land_pickup_address, land_delivery_address = excluded.land_delivery_address,
    air_awb_number = excluded.air_awb_number, air_flight_number = excluded.air_flight_number,
    air_origin_airport = excluded.air_origin_airport, air_destination_airport = excluded.air_destination_airport,
    sea_bl_number = excluded.sea_bl_number, sea_booking_number = excluded.sea_booking_number,
    sea_vessel_name = excluded.sea_vessel_name, sea_origin_port = excluded.sea_origin_port, sea_destination_port = excluded.sea_destination_port,
    sea_container_number = excluded.sea_container_number, sea_container_type = excluded.sea_container_type
  returning * into v_profile;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_shipment_mode_profile',
    'app.shipment_mode_profiles', v_profile.id, 'success', null, null,
    jsonb_build_object('shipment_order_id', p_shipment_order_id, 'mode', v_shipment.mode)
  );

  return v_profile;
end;
$function$;

CREATE OR REPLACE FUNCTION app.start_epod_capture(p_tenant_id uuid, p_shipment_order_id uuid, p_milestone_event_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.epod_captures
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_existing app.epod_captures;
  v_new_id uuid := gen_random_uuid();
  v_capture app.epod_captures;
begin
  select * into v_shipment from app.shipment_orders so where so.id = p_shipment_order_id;
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.epod_captures where tenant_id = v_shipment.tenant_id and idempotency_key = p_idempotency_key;
    if found then
      -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
      -- conflict, never a replay. Returning the earlier target's row here silently
      -- misattributed this request to it (or silently discarded it entirely).
      if v_existing.shipment_order_id is distinct from p_shipment_order_id then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different ePOD capture (shipment order %, not %)', p_idempotency_key, v_existing.shipment_order_id, p_shipment_order_id
          using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  if v_shipment.status <> 'delivered' then
    raise exception 'epod_shipment_not_delivered: shipment order % is % -- ePOD capture may only begin once a shipment reaches delivered', p_shipment_order_id, v_shipment.status
      using errcode = 'check_violation';
  end if;

  insert into app.epod_captures (id, tenant_id, shipment_order_id, milestone_event_id, version_group_id, version_number, is_latest_version, status, idempotency_key, created_by)
  values (v_new_id, v_shipment.tenant_id, p_shipment_order_id, p_milestone_event_id, v_new_id, 1, true, 'draft', p_idempotency_key, p_actor_label)
  returning * into v_capture;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'start_epod_capture',
    'app.epod_captures', v_capture.id, 'success', null, null, to_jsonb(v_capture)
  );

  return v_capture;
end;
$function$;

CREATE OR REPLACE FUNCTION app.submit_actual_cost(p_actual_cost_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.shipment_actual_costs
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_cost app.shipment_actual_costs;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_component_count integer;
  v_updated app.shipment_actual_costs;
begin
  select * into v_cost from app.shipment_actual_costs where id = p_actual_cost_id for update;
  if not found or not app.has_active_tenant_membership(v_cost.tenant_id, p_actor_auth_user_id) then
    raise exception 'actual_cost_not_found: %', p_actual_cost_id using errcode = 'no_data_found';
  end if;
  if v_cost.record_version <> p_expected_version then
    raise exception 'concurrent_modification: actual cost % has moved from expected version % to %', p_actual_cost_id, p_expected_version, v_cost.record_version
      using errcode = 'check_violation';
  end if;
  select * into v_shipment from app.shipment_orders so where so.id = v_cost.shipment_order_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_cost.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_cost.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_cost.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_cost.status <> 'draft' then
    raise exception 'invalid_transition: actual cost % is % and cannot be submitted', p_actual_cost_id, v_cost.status
      using errcode = 'check_violation';
  end if;

  select count(*) into v_component_count from app.shipment_actual_cost_components where actual_cost_id = p_actual_cost_id;
  if v_component_count = 0 then
    raise exception 'actual_cost_no_components: at least one cost component is required before submission' using errcode = 'check_violation';
  end if;

  update app.shipment_actual_costs set status = 'submitted' where id = p_actual_cost_id returning * into v_updated;

  perform app.capture_audit_event(
    v_cost.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_actual_cost',
    'app.shipment_actual_costs', v_updated.id, 'success', null, to_jsonb(v_cost), to_jsonb(v_updated)
  );

  return v_updated;
end;
$function$;

CREATE OR REPLACE FUNCTION app.submit_epod_capture(p_capture_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.epod_captures
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
declare
  v_capture app.epod_captures;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_photo_id uuid;
  v_scan_status text;
  v_updated app.epod_captures;
begin
  select * into v_capture from app.epod_captures where id = p_capture_id for update;
  if not found or not app.has_active_tenant_membership(v_capture.tenant_id, p_actor_auth_user_id) then
    raise exception 'epod_capture_not_found: %', p_capture_id using errcode = 'no_data_found';
  end if;
  if v_capture.record_version <> p_expected_version then
    raise exception 'concurrent_modification: ePOD capture % has moved from expected version % to %', p_capture_id, p_expected_version, v_capture.record_version
      using errcode = 'check_violation';
  end if;
  select * into v_shipment from app.shipment_orders so where so.id = v_capture.shipment_order_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_capture.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_capture.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_capture.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_capture.status not in ('draft', 'revision_requested') then
    raise exception 'invalid_transition: ePOD capture % is % and cannot be submitted', p_capture_id, v_capture.status
      using errcode = 'check_violation';
  end if;

  if v_capture.receiver_name is null or length(trim(v_capture.receiver_name)) = 0 then
    raise exception 'epod_missing_receiver: a receiver name is required before submission' using errcode = 'check_violation';
  end if;
  if v_capture.signature_file_id is null and array_length(v_capture.photo_file_ids, 1) is null then
    raise exception 'epod_missing_evidence: at least one of a signature or a photo is required before submission' using errcode = 'check_violation';
  end if;

  if v_capture.signature_file_id is not null then
    select malware_scan_status into v_scan_status from app.files where id = v_capture.signature_file_id;
    if v_scan_status <> 'clean' then
      raise exception 'epod_unsafe_evidence: signature file % has scan status % -- only clean evidence may be submitted', v_capture.signature_file_id, v_scan_status
        using errcode = 'check_violation';
    end if;
  end if;
  foreach v_photo_id in array v_capture.photo_file_ids loop
    select malware_scan_status into v_scan_status from app.files where id = v_photo_id;
    if v_scan_status <> 'clean' then
      raise exception 'epod_unsafe_evidence: photo file % has scan status % -- only clean evidence may be submitted', v_photo_id, v_scan_status
        using errcode = 'check_violation';
    end if;
  end loop;

  update app.epod_captures
  set status = 'submitted'
  where id = p_capture_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_capture.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_epod_capture',
    'app.epod_captures', v_updated.id, 'success', null, to_jsonb(v_capture), to_jsonb(v_updated)
  );

  return v_updated;
end;
$function$;

CREATE OR REPLACE FUNCTION app.transition_shipment_order(p_shipment_order_id uuid, p_to_status text, p_expected_version integer, p_reason text, p_evidence_ref text, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.shipment_orders
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_existing_transition app.shipment_status_transitions;
  v_from_status text;
  v_next_status text;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: a non-empty idempotency key is required' using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  select * into v_existing_transition from app.shipment_status_transitions
  where tenant_id = v_shipment.tenant_id and shipment_order_id = p_shipment_order_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
    -- conflict, never a replay. Returning the earlier target's row here silently
    -- misattributed this request to it (or silently discarded it entirely).
    if v_existing_transition.to_status is distinct from p_to_status then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different status transition (transition to %, not to %)', p_idempotency_key, v_existing_transition.to_status, p_to_status
        using errcode = 'unique_violation';
    end if;
    return v_shipment;
  end if;

  if v_shipment.record_version <> p_expected_version then
    raise exception 'stale_version: shipment order % expected version % but found %', p_shipment_order_id, p_expected_version, v_shipment.record_version
      using errcode = 'serialization_failure';
  end if;

  v_from_status := v_shipment.status;

  -- The canonical matrix. 'held'/'cancelled' branch off most active states; 'held'
  -- resumes only into its own recorded held_from_status; 'closed' may only reopen
  -- into 'delivered'/'epod' (Supreme-only, checked below), never further back.
  if v_from_status = 'held' then
    if p_to_status <> v_shipment.held_from_status and p_to_status <> 'cancelled' then
      raise exception 'invalid_transition: a held shipment order % may only resume into % or cancel', p_shipment_order_id, v_shipment.held_from_status
        using errcode = 'check_violation';
    end if;
  elsif v_from_status = 'closed' then
    if p_to_status not in ('delivered', 'epod') then
      raise exception 'invalid_transition: shipment order % is closed and may only reopen into delivered or epod', p_shipment_order_id
        using errcode = 'check_violation';
    end if;
    if not app.is_supreme_admin(p_actor_auth_user_id) then
      raise exception 'insufficient_authority: reopening a closed shipment order requires Supreme Admin authority (RPD-022)'
        using errcode = 'insufficient_privilege';
    end if;
  elsif v_from_status = 'cancelled' then
    raise exception 'invalid_transition: shipment order % is cancelled, a terminal state', p_shipment_order_id using errcode = 'check_violation';
  elsif v_from_status = 'draft' and p_to_status in ('confirmed', 'cancelled') then
    null;
  elsif v_from_status in ('confirmed', 'planned', 'assigned', 'dispatched', 'in_transit') and p_to_status in ('held', 'cancelled') then
    null;
  elsif v_from_status = 'confirmed' and p_to_status = 'planned' then
    null;
  elsif v_from_status = 'planned' and p_to_status = 'assigned' then
    null;
  elsif v_from_status = 'assigned' and p_to_status = 'dispatched' then
    null;
  elsif v_from_status = 'dispatched' and p_to_status = 'in_transit' then
    null;
  elsif v_from_status = 'in_transit' and p_to_status = 'delivered' then
    null;
  elsif v_from_status = 'delivered' and p_to_status in ('epod', 'cancelled') then
    null;
  elsif v_from_status = 'epod' and p_to_status = 'closed' then
    null;
  else
    raise exception 'invalid_transition: % -> % is not a legal Shipment Order transition', v_from_status, p_to_status
      using errcode = 'check_violation';
  end if;

  if p_to_status in ('held', 'cancelled') and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'reason_required: a non-empty reason is required to enter %', p_to_status using errcode = 'check_violation';
  end if;

  if p_to_status in ('delivered', 'epod', 'closed') and (p_evidence_ref is null or length(trim(p_evidence_ref)) = 0) then
    raise exception 'evidence_required: a non-empty evidence reference is required to enter %', p_to_status using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  v_next_status := p_to_status;

  begin
    insert into app.shipment_status_transitions (
      tenant_id, shipment_order_id, from_status, to_status, reason, evidence_ref, idempotency_key, actor_auth_user_id, actor_label
    ) values (
      v_shipment.tenant_id, p_shipment_order_id, v_from_status, v_next_status, p_reason, p_evidence_ref, p_idempotency_key, p_actor_auth_user_id, p_actor_label
    );
  exception
    when unique_violation then
      select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
      return v_shipment;
  end;

  update app.shipment_orders
  set status = v_next_status,
      held_from_status = case when v_next_status = 'held' then v_from_status else null end
  where id = p_shipment_order_id and record_version = p_expected_version
  returning * into v_shipment;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: transition_shipment_order target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'transition_shipment_order',
    'app.shipment_orders', v_shipment.id, 'success', null,
    jsonb_build_object('status', v_from_status),
    jsonb_build_object('status', v_next_status, 'reason', p_reason, 'evidence_ref', p_evidence_ref)
  );

  return v_shipment;
end;
$function$;

CREATE OR REPLACE FUNCTION app.unassign_resource(p_shipment_order_id uuid, p_role text, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.resource_assignments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_current app.resource_assignments;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: unassigning a resource requires a non-empty reason' using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Assign');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Assign (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_current
  from app.resource_assignments
  where tenant_id = v_shipment.tenant_id and shipment_order_id = p_shipment_order_id and role = p_role and is_current;
  if not found then
    raise exception 'no_current_assignment: shipment order % has no current % assignment', p_shipment_order_id, p_role
      using errcode = 'check_violation';
  end if;

  update app.resource_assignments
  set status = 'unassigned', is_current = false, effective_to = now(), reason = p_reason
  where id = v_current.id
  returning * into v_current;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'unassign_resource',
    'app.resource_assignments', v_current.id, 'success', null, null,
    jsonb_build_object('shipment_order_id', p_shipment_order_id, 'role', p_role, 'reason', p_reason)
  );

  return v_current;
end;
$function$;

