-- Operations capability OPS-186 (Operations Security and Financial Hardening,
-- CG-S8-OPS-020) -- four real, disclosed, evidence-backed hardening fixes found by a
-- targeted audit sweep of all 18 Operations migrations, ranked by severity. Not a new
-- capability; no scope expansion (Prompt 186 §24). Per the immutable-migrations
-- convention, no prior applied migration is edited -- functions are patched via
-- `CREATE OR REPLACE FUNCTION` (identical name/signature, so existing grants remain
-- unchanged) and the one table needing a new constraint gets it via `ALTER TABLE ADD
-- CONSTRAINT`, both additive/non-destructive techniques already used at OPS-185's own
-- hardening migration.
--
-- Finding 1 (Critical -- same bug class OPS-185 already found and fixed once):
-- `app.prepare_job_order` (OPS-168, 20260727090000_create_operations_job_order.sql)
-- checked only tenant-wide `OPS:Create`, never `app.can_access_record` against the
-- source `app.job_order_handoffs` row (which does carry owner_user_id/org_unit_id) --
-- before copying its revenue/contract/credit snapshot payload into a new Job Order the
-- calling actor now owns. Any actor holding tenant-wide `OPS:Create` could convert any
-- handoff in the tenant, including ones outside their own org-unit/ownership scope, and
-- receive back financial/acceptance snapshot data they have no other access path to.
--
-- Finding 2 (Critical -- identical shape): `app.create_shipment_order_from_job`
-- (OPS-169, 20260727100000_create_operations_shipment_order.sql) checked only tenant-
-- wide `OPS:Create`, never `app.can_access_record` against the source `app.job_orders`
-- row, before creating a Shipment Order that inherits its customer/cargo snapshot.
--
-- Finding 3 (High, bounded): `app.detect_transaction_lineage_anomalies` (OPS-184,
-- 20260728170000_create_operations_transaction_lineage.sql) is gated only on tenant-
-- wide `OPS:Override`. Its two ORPHAN diagnostics (`orphan_shipment_order`,
-- `orphan_billing_readiness`) each report on one single record's own missing edge --
-- unlike its own sibling `app.get_transaction_lineage` in the same file, which filters
-- every row through `app.can_access_record`, these two queries returned every orphan
-- tenant-wide with zero record-scope filtering, so any `OPS:Override` holder anywhere in
-- the tenant could see orphan records across every org unit/owner. Fixed by filtering
-- each on its own row's (or, for billing-readiness, its Job Order's) owner/org columns,
-- exactly like `app.get_transaction_lineage` already does. A Supreme Admin still sees
-- every orphan via `can_access_record`'s own bypass.
--
-- The other two diagnostics (`duplicate_target`, `cross_tenant_mismatch`) are
-- deliberately left tenant-wide, unchanged: both compare TWO edges that, by definition,
-- may belong to different owners/org units (a duplicate spans two distinct sources; a
-- mismatch is about a tenant boundary, not an org-unit one) -- there is no single
-- "whose record scope" to apply, and these are genuinely tenant-level integrity reports
-- an `OPS:Override` holder is already trusted to run.
--
-- Finding 4 (Medium -- financial precision): `app.job_profitability_snapshots`
-- (OPS-179, 20260728120000_create_operations_job_profitability.sql) has no `>= 0` check
-- on `revenue_amount`/`cost_amount`, unlike every other monetary column in the Operations
-- schema (`shipment_actual_costs.total_amount`/`estimated_amount`,
-- `shipment_actual_cost_components.rate`/`minimum_charge`/`surcharge`/`amount`,
-- `operational_exceptions.claim_amount` all have one). `margin_amount` is correctly left
-- unconstrained (a loss is a legitimate negative margin) -- only the two amounts that can
-- never legitimately be negative are hardened here.
--
-- Audit completeness (checked, no fix needed): every mutating function across the 18
-- files calls `app.capture_audit_event`; the only exceptions are internal
-- `service_role`-only helpers never exposed to `authenticated` and `touch_*` triggers.
-- Money precision (checked, no fix needed beyond Finding 4): zero `float`/`double
-- precision`/`real` columns anywhere in the Operations schema. Public/anon surface
-- (checked, no fix needed): `app.lookup_public_shipment_tracking` remains the one and
-- only `anon`-granted function across all 18 files, already rate-limited and attempt-
-- logged (OPS-180's own db-test already proves this). IDOR/enumeration (checked, no fix
-- needed): every authenticated-facing function already uses the consistent
-- `X_not_found` / `insufficient_authority: cannot access X` two-step pattern.

create or replace function app.prepare_job_order(
  p_source_handoff_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.job_orders
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_handoff app.job_order_handoffs;
  v_decision app.rbac_decision;
  v_existing app.job_orders;
  v_job_order app.job_orders;
  v_number text;
begin
  select * into v_handoff from app.job_order_handoffs where id = p_source_handoff_id;
  if not found then
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

  begin
    insert into app.job_orders (
      tenant_id, job_number, source_handoff_id, quotation_id, account_id,
      customer_snapshot, cargo_service_snapshot, revenue_snapshot, contract_snapshot, credit_snapshot, acceptance_snapshot,
      owner_user_id, created_by
    ) values (
      v_handoff.tenant_id, v_number, v_handoff.id, v_handoff.quotation_id, v_handoff.account_id,
      v_handoff.payload -> 'customer', v_handoff.payload -> 'cargoService', v_handoff.payload -> 'pricing',
      v_handoff.payload -> 'contract', v_handoff.payload -> 'credit', v_handoff.payload -> 'acceptance',
      p_actor_auth_user_id, p_actor_label
    )
    returning * into v_job_order;
  exception
    when unique_violation then
      select * into v_job_order from app.job_orders where tenant_id = v_handoff.tenant_id and source_handoff_id = p_source_handoff_id;
      return v_job_order;
  end;

  perform app.capture_audit_event(
    v_handoff.tenant_id, p_actor_auth_user_id, p_actor_label, 'prepare_job_order',
    'app.job_orders', v_job_order.id, 'success', null, null,
    jsonb_build_object('source_handoff_id', p_source_handoff_id, 'job_number', v_number)
  );

  return v_job_order;
end;
$$;

comment on function app.prepare_job_order is
  'OPS-168/OPS-186-hardened: idempotent on (tenant_id, source_handoff_id) -- a repeated call, including under a concurrent-insert race, returns the exact same Job Order row, never a duplicate. Every snapshot column is copied verbatim from the handoff''s own already-canonical payload. Now record-scope-checked against the source handoff (missing at OPS-168''s own authoring, found by OPS-186''s own audit sweep).';

create or replace function app.create_shipment_order_from_job(
  p_job_order_id uuid,
  p_idempotency_key text,
  p_consignee jsonb,
  p_notify_party jsonb,
  p_service_type text,
  p_mode text,
  p_origin text,
  p_destination text,
  p_planned_pickup_at timestamptz,
  p_planned_delivery_at timestamptz,
  p_allocated_quantity numeric,
  p_allocated_weight_kg numeric,
  p_allocated_volume_cbm numeric,
  p_basis_quantity numeric,
  p_basis_weight_kg numeric,
  p_basis_volume_cbm numeric,
  p_split_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.shipment_orders
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_job app.job_orders;
  v_decision app.rbac_decision;
  v_existing app.shipment_orders;
  v_shipment app.shipment_orders;
  v_number text;
  v_existing_count integer;
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
  if not found then
    raise exception 'job_order_not_found: %', p_job_order_id using errcode = 'no_data_found';
  end if;

  if v_job.status <> 'confirmed' then
    raise exception 'job_order_not_confirmed: job order % is % and is not eligible for Shipment Order creation', p_job_order_id, v_job.status
      using errcode = 'check_violation';
  end if;

  select * into v_existing from app.shipment_orders where tenant_id = v_job.tenant_id and job_order_id = p_job_order_id and idempotency_key = p_idempotency_key;
  if found then
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
  if v_existing_count > 0 and (p_split_reason is null or length(trim(p_split_reason)) = 0) then
    raise exception 'split_reason_required: a non-empty split_reason is required when another Shipment Order already exists for job order %', p_job_order_id
      using errcode = 'check_violation';
  end if;

  if v_existing_count > 0 then
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

  if v_existing_count = 0 then
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
$$;

comment on function app.create_shipment_order_from_job is
  'OPS-169/OPS-186-hardened: idempotent on (tenant_id, job_order_id, idempotency_key); a second Shipment Order against the same Job Order requires split_reason and is allocation-balance-checked. Now record-scope-checked against the source Job Order (missing at OPS-169''s own authoring, found by OPS-186''s own audit sweep).';

create or replace function app.detect_transaction_lineage_anomalies(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid
)
returns setof app.transaction_lineage_anomaly
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select 'orphan_shipment_order'::text, 'job_to_shipment'::text, 'shipment_order'::text, so.id,
    format('shipment order %s (job %s) has no recorded job_to_shipment lineage edge', so.id, so.job_order_id)
  from app.shipment_orders so
  where so.tenant_id = p_tenant_id
    and app.can_access_record(p_actor_auth_user_id, so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)
    and not exists (
      select 1 from app.transaction_lineage_edges e
      where e.tenant_id = so.tenant_id and e.relation_type = 'job_to_shipment' and e.target_type = 'shipment_order' and e.target_id = so.id
    );

  return query
  select 'orphan_billing_readiness'::text, 'job_to_billing_readiness'::text, 'billing_readiness_evaluation'::text, bre.id,
    format('billing readiness evaluation %s (job %s) has no recorded job_to_billing_readiness lineage edge', bre.id, bre.job_order_id)
  from app.billing_readiness_evaluations bre
  join app.job_orders jo on jo.id = bre.job_order_id
  where bre.tenant_id = p_tenant_id
    and app.can_access_record(p_actor_auth_user_id, jo.tenant_id, jo.owner_user_id, app.lead_record_scope_org_unit_ids(jo.org_unit_id), null)
    and not exists (
      select 1 from app.transaction_lineage_edges e
      where e.tenant_id = bre.tenant_id and e.relation_type = 'job_to_billing_readiness' and e.target_type = 'billing_readiness_evaluation' and e.target_id = bre.id
    );

  return query
  select 'duplicate_target'::text, e.relation_type, e.target_type, e.target_id,
    format('target %s (%s) is claimed by %s distinct sources under relation %s', e.target_id, e.target_type, count(distinct e.source_id), e.relation_type)
  from app.transaction_lineage_edges e
  where e.tenant_id = p_tenant_id
  group by e.relation_type, e.target_type, e.target_id
  having count(distinct e.source_id) > 1;

  return query
  select 'cross_tenant_mismatch'::text, e.relation_type, e.target_type, e.target_id,
    format('edge %s stamped tenant %s does not match job order %s tenant %s', e.id, e.tenant_id, jo.id, jo.tenant_id)
  from app.transaction_lineage_edges e
  join app.job_orders jo on (e.source_type = 'job_order' and jo.id = e.source_id) or (e.target_type = 'job_order' and jo.id = e.target_id)
  where jo.tenant_id = p_tenant_id and jo.tenant_id <> e.tenant_id;

  return;
end;
$$;

comment on function app.detect_transaction_lineage_anomalies is
  'OPS-184/OPS-186-hardened: read-only reconciliation diagnostic, OPS:Override-gated. The two single-record orphan diagnostics (orphan_shipment_order/orphan_billing_readiness) are now record-scope-filtered (missing at OPS-184''s own authoring, found by OPS-186''s own audit sweep) -- a Supreme Admin still sees every orphan tenant-wide via app.can_access_record''s own bypass. duplicate_target/cross_tenant_mismatch remain deliberately tenant-wide -- both compare two edges that may belong to different owners/org units by definition, so no single record scope applies. Never mutates anything itself.';

-- Finding 4: revenue_amount/cost_amount can never legitimately be negative (unlike
-- margin_amount, a genuine loss). Existing rows (none yet touch negative values in this
-- greenfield schema) are covered by the default (non-NOT VALID) validation scan.
alter table app.job_profitability_snapshots
  add constraint job_profitability_snapshots_revenue_amount_check check (revenue_amount is null or revenue_amount >= 0),
  add constraint job_profitability_snapshots_cost_amount_check check (cost_amount is null or cost_amount >= 0);

-- No grant/revoke statements needed -- CREATE OR REPLACE FUNCTION preserves the exact
-- same name/signature/owner for all three functions above, so their existing grants
-- remain in force unchanged; the new table constraints require no grant of their own.
