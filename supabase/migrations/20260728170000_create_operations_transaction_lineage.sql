-- Operations capability OPS-184 (Operations Transaction Lineage, CG-S8-OPS-018)
--
-- Enforces complete canonical lineage across the full Phase 3 quote-to-billing chain:
-- Commercial's own accepted-quote handoff (`app.job_order_handoffs`, COM-160) -> Job
-- Order (OPS-168) -> Shipment Order (OPS-169) -> ePOD (OPS-177) / Actual Cost (OPS-178)
-- -> Job Profitability (OPS-179) -> Billing Readiness (OPS-181). No prior migration is
-- edited (the immutable-migrations convention every Phase 2/3 checkpoint has honored) --
-- this migration is purely additive: one new append-only edge table plus six new
-- `AFTER INSERT` triggers on the six already-existing tables above. A trigger is the only
-- way to capture "atomic lineage creation at each domain transition" (Prompt 184 §20.2)
-- without reopening OPS-168/169/177/178/179/181's own migration files -- every trigger
-- function is a thin wrapper that calls the one shared `app.capture_transaction_lineage_edge`
-- helper, mirroring the "one shared capture primitive, many thin call sites" shape
-- `app.capture_audit_event` itself already established for every other capability.
--
-- No new permission-catalogue row: reads reuse the identical `app.can_access_record`
-- row-filter every OPS-182 dashboard function already uses (never a broader
-- `evaluate_permission` gate on the read path, matching that same precedent); the
-- correction/reconciliation actions (`record_transaction_lineage_override`,
-- `detect_transaction_lineage_anomalies`, `backfill_transaction_lineage`) reuse the
-- already-seeded `OPS:Override` action (OPS-181's own gate for billing-readiness
-- overrides) rather than inventing a redundant lineage-specific permission.
--
-- Milestones (OPS-173) are deliberately NOT modeled as a persisted lineage edge: a
-- shipment can accumulate many milestone events, and persisting one edge per event would
-- be exactly the "unbounded graph query" Prompt 184 §17 forbids. Instead the traversal
-- function folds in the shipment's own current `app.shipment_milestone_projections` row
-- (already a bounded, one-row-per-shipment projection, OPS-173) as an attribute of the
-- shipment node, not a separate graph edge.
--
-- Customer/public-facing lineage is out of scope here by design: OPS-180's own public
-- tracking token (`app.lookup_public_shipment_tracking`) already serves the "purpose-
-- limited sanitized timeline, not the internal lineage graph" requirement (Prompt 184
-- §26) for external parties; this capability's traversal (`app.get_transaction_lineage`)
-- is for internal, tenant-authenticated roles only.
--
-- Per ERR-2026-004: this migration carries its own explicit
-- `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` before its final grants.

create table app.transaction_lineage_edges (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  relation_type text not null,
  source_type text not null,
  source_id uuid not null,
  target_type text not null,
  target_id uuid not null,
  source_version_hash text,
  owner_user_id uuid references auth.users (id),
  org_unit_id uuid references app.org_units (id),
  is_override boolean not null default false,
  override_reason text,
  created_by_auth_user_id uuid references auth.users (id),
  created_by_label text not null,
  created_at timestamptz not null default now(),
  constraint transaction_lineage_edges_relation_type_check check (
    relation_type in (
      'quote_to_job', 'job_to_shipment', 'shipment_to_epod', 'shipment_to_cost',
      'job_to_profitability', 'job_to_billing_readiness'
    )
  ),
  constraint transaction_lineage_edges_node_type_check check (
    source_type in ('job_order_handoff', 'job_order', 'shipment_order')
    and target_type in ('job_order', 'shipment_order', 'epod_capture', 'shipment_actual_cost', 'job_profitability_snapshot', 'billing_readiness_evaluation')
  ),
  constraint transaction_lineage_edges_relation_pair_check check (
    (relation_type = 'quote_to_job' and source_type = 'job_order_handoff' and target_type = 'job_order')
    or (relation_type = 'job_to_shipment' and source_type = 'job_order' and target_type = 'shipment_order')
    or (relation_type = 'shipment_to_epod' and source_type = 'shipment_order' and target_type = 'epod_capture')
    or (relation_type = 'shipment_to_cost' and source_type = 'shipment_order' and target_type = 'shipment_actual_cost')
    or (relation_type = 'job_to_profitability' and source_type = 'job_order' and target_type = 'job_profitability_snapshot')
    or (relation_type = 'job_to_billing_readiness' and source_type = 'job_order' and target_type = 'billing_readiness_evaluation')
  ),
  constraint transaction_lineage_edges_override_reason_check check (not is_override or (override_reason is not null and length(trim(override_reason)) > 0)),
  constraint transaction_lineage_edges_tenant_edge_unique unique (tenant_id, source_type, source_id, target_type, target_id, relation_type)
);

comment on table app.transaction_lineage_edges is
  'OPS-184: one append-only, never-updated, never-deleted row per real domain transition across the quote-to-billing chain -- unique on (tenant_id, source_type, source_id, target_type, target_id, relation_type), the "no silent re-entry" no-reentry guarantee (Prompt 184 §24). Six relation types are captured automatically via AFTER INSERT triggers on their own target table; is_override rows are the one authorized, reasoned exception, added via app.record_transaction_lineage_override without ever deleting or mutating the row(s) they correct.';

create index transaction_lineage_edges_tenant_target_idx on app.transaction_lineage_edges (tenant_id, target_type, target_id);
create index transaction_lineage_edges_tenant_source_idx on app.transaction_lineage_edges (tenant_id, source_type, source_id);
create index transaction_lineage_edges_tenant_owner_idx on app.transaction_lineage_edges (tenant_id, owner_user_id);

-- Shared capture primitive -- idempotent (on conflict do nothing), audited only when a
-- new row is actually inserted (a repeat call, e.g. from app.backfill_transaction_lineage
-- re-scanning already-captured rows, is a deliberate silent no-op, never a duplicate
-- audit entry).
create function app.capture_transaction_lineage_edge(
  p_tenant_id uuid,
  p_relation_type text,
  p_source_type text,
  p_source_id uuid,
  p_target_type text,
  p_target_id uuid,
  p_source_version_hash text,
  p_owner_user_id uuid,
  p_org_unit_id uuid
)
returns app.transaction_lineage_edges
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_edge app.transaction_lineage_edges;
begin
  insert into app.transaction_lineage_edges (
    tenant_id, relation_type, source_type, source_id, target_type, target_id,
    source_version_hash, owner_user_id, org_unit_id, created_by_label
  ) values (
    p_tenant_id, p_relation_type, p_source_type, p_source_id, p_target_type, p_target_id,
    p_source_version_hash, p_owner_user_id, p_org_unit_id, 'system:trigger'
  )
  on conflict (tenant_id, source_type, source_id, target_type, target_id, relation_type) do nothing
  returning * into v_edge;

  if v_edge.id is not null then
    perform app.capture_audit_event(
      p_tenant_id, null, 'system:trigger', 'capture_transaction_lineage_edge',
      'app.transaction_lineage_edges', v_edge.id, 'success', p_relation_type,
      null,
      jsonb_build_object('source_type', p_source_type, 'source_id', p_source_id, 'target_type', p_target_type, 'target_id', p_target_id)
    );
  end if;

  return v_edge;
end;
$$;

comment on function app.capture_transaction_lineage_edge is
  'OPS-184: the one shared insert-and-audit primitive every trigger function and app.backfill_transaction_lineage call -- never invoked directly by authenticated/service_role (no grant given; only reachable via the triggers below or the owner-privileged backfill function).';

-- Trigger 1/6: Commercial's accepted-quote handoff -> Job Order (OPS-168).
create function app.trg_capture_lineage_quote_to_job()
returns trigger
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_hash text;
begin
  select payload_hash into v_hash from app.job_order_handoffs where id = new.source_handoff_id;
  perform app.capture_transaction_lineage_edge(
    new.tenant_id, 'quote_to_job', 'job_order_handoff', new.source_handoff_id, 'job_order', new.id,
    v_hash, new.owner_user_id, new.org_unit_id
  );
  return new;
end;
$$;

create trigger job_orders_capture_lineage
  after insert on app.job_orders
  for each row
  execute function app.trg_capture_lineage_quote_to_job();

-- Trigger 2/6: Job Order -> Shipment Order (OPS-169). No natural upstream hash exists,
-- so the fingerprint is a digest of the shipment's own defining fields -- a stable
-- version marker, never a copy of the domain payload itself (Prompt 184 §14).
create function app.trg_capture_lineage_job_to_shipment()
returns trigger
language plpgsql
security definer
set search_path = app, public, extensions, pg_temp
as $$
declare
  v_hash text;
begin
  v_hash := encode(digest(
    coalesce(new.consignee_snapshot::text, '') || '|' || coalesce(new.cargo_service_snapshot::text, '') || '|' ||
    new.service_type || '|' || new.mode || '|' || new.origin || '|' || new.destination,
    'sha256'
  ), 'hex');
  perform app.capture_transaction_lineage_edge(
    new.tenant_id, 'job_to_shipment', 'job_order', new.job_order_id, 'shipment_order', new.id,
    v_hash, new.owner_user_id, new.org_unit_id
  );
  return new;
end;
$$;

create trigger shipment_orders_capture_lineage
  after insert on app.shipment_orders
  for each row
  execute function app.trg_capture_lineage_job_to_shipment();

-- Trigger 3/6: Shipment Order -> ePOD capture (OPS-177). Owner/org unit are derived from
-- the parent Shipment Order -- app.epod_captures itself carries neither column.
create function app.trg_capture_lineage_shipment_to_epod()
returns trigger
language plpgsql
security definer
set search_path = app, public, extensions, pg_temp
as $$
declare
  v_shipment app.shipment_orders;
  v_hash text;
begin
  select * into v_shipment from app.shipment_orders where id = new.shipment_order_id;
  v_hash := encode(digest(
    coalesce(new.receiver_name, '') || '|' || coalesce(new.signature_file_id::text, '') || '|' ||
    coalesce(array_to_string(new.photo_file_ids, ','), '') || '|' || coalesce(new.captured_at::text, ''),
    'sha256'
  ), 'hex');
  perform app.capture_transaction_lineage_edge(
    new.tenant_id, 'shipment_to_epod', 'shipment_order', new.shipment_order_id, 'epod_capture', new.id,
    v_hash, v_shipment.owner_user_id, v_shipment.org_unit_id
  );
  return new;
end;
$$;

create trigger epod_captures_capture_lineage
  after insert on app.epod_captures
  for each row
  execute function app.trg_capture_lineage_shipment_to_epod();

-- Trigger 4/6: Shipment Order -> Actual Cost (OPS-178). Owner/org unit derived from the
-- parent Shipment Order the same way as ePOD above.
create function app.trg_capture_lineage_shipment_to_cost()
returns trigger
language plpgsql
security definer
set search_path = app, public, extensions, pg_temp
as $$
declare
  v_shipment app.shipment_orders;
  v_hash text;
begin
  select * into v_shipment from app.shipment_orders where id = new.shipment_order_id;
  v_hash := encode(digest(coalesce(new.currency, '') || '|' || coalesce(new.total_amount::text, '') || '|' || new.status, 'sha256'), 'hex');
  perform app.capture_transaction_lineage_edge(
    new.tenant_id, 'shipment_to_cost', 'shipment_order', new.shipment_order_id, 'shipment_actual_cost', new.id,
    v_hash, v_shipment.owner_user_id, v_shipment.org_unit_id
  );
  return new;
end;
$$;

create trigger shipment_actual_costs_capture_lineage
  after insert on app.shipment_actual_costs
  for each row
  execute function app.trg_capture_lineage_shipment_to_cost();

-- Trigger 5/6: Job Order -> Job Profitability snapshot (OPS-179).
create function app.trg_capture_lineage_job_to_profitability()
returns trigger
language plpgsql
security definer
set search_path = app, public, extensions, pg_temp
as $$
declare
  v_job app.job_orders;
  v_hash text;
begin
  select * into v_job from app.job_orders where id = new.job_order_id;
  v_hash := encode(digest(
    coalesce(new.revenue_amount::text, '') || '|' || coalesce(new.cost_amount::text, '') || '|' ||
    coalesce(new.margin_amount::text, '') || '|' || new.status,
    'sha256'
  ), 'hex');
  perform app.capture_transaction_lineage_edge(
    new.tenant_id, 'job_to_profitability', 'job_order', new.job_order_id, 'job_profitability_snapshot', new.id,
    v_hash, v_job.owner_user_id, v_job.org_unit_id
  );
  return new;
end;
$$;

create trigger job_profitability_snapshots_capture_lineage
  after insert on app.job_profitability_snapshots
  for each row
  execute function app.trg_capture_lineage_job_to_profitability();

-- Trigger 6/6: Job Order -> Billing Readiness evaluation (OPS-181) -- the terminal node
-- Finance receives its one stable readiness evidence manifest from (Prompt 184 §33).
create function app.trg_capture_lineage_job_to_billing_readiness()
returns trigger
language plpgsql
security definer
set search_path = app, public, extensions, pg_temp
as $$
declare
  v_job app.job_orders;
  v_hash text;
begin
  select * into v_job from app.job_orders where id = new.job_order_id;
  v_hash := encode(digest(new.evaluated_status || '|' || coalesce(new.blockers::text, ''), 'sha256'), 'hex');
  perform app.capture_transaction_lineage_edge(
    new.tenant_id, 'job_to_billing_readiness', 'job_order', new.job_order_id, 'billing_readiness_evaluation', new.id,
    v_hash, v_job.owner_user_id, v_job.org_unit_id
  );
  return new;
end;
$$;

create trigger billing_readiness_evaluations_capture_lineage
  after insert on app.billing_readiness_evaluations
  for each row
  execute function app.trg_capture_lineage_job_to_billing_readiness();

-- Bounded, permission-aware traversal rooted at one Job Order. Every hop is filtered
-- through the identical app.can_access_record check its own owning table's RLS policy
-- already uses; an inaccessible shipment (and everything hanging off it -- its ePOD,
-- its cost, its lineage edges) is silently omitted, never surfaced as an "inaccessible"
-- placeholder -- "existence/count/errors cannot reveal inaccessible records" (Prompt 184
-- §16). Depth/breadth is fixed by the schema itself (one job -> N shipments -> at most
-- one current ePOD/cost/milestone projection each -> one current profitability/billing-
-- readiness snapshot) -- never a recursive or unbounded graph walk (§17).
create function app.get_transaction_lineage(
  p_job_order_id uuid,
  p_actor_auth_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_job app.job_orders;
  v_handoff app.job_order_handoffs;
  v_shipment record;
  v_epod app.epod_captures;
  v_cost app.shipment_actual_costs;
  v_milestone app.shipment_milestone_projections;
  v_profitability app.job_profitability_snapshots;
  v_billing app.billing_readiness_evaluations;
  v_shipments jsonb := '[]'::jsonb;
  v_accessible_shipment_ids uuid[] := '{}';
  v_edges jsonb;
  v_manifest jsonb;
begin
  select * into v_job from app.job_orders where id = p_job_order_id;
  if not found then
    raise exception 'job_order_not_found: %', p_job_order_id using errcode = 'no_data_found';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_job.tenant_id, v_job.owner_user_id, app.lead_record_scope_org_unit_ids(v_job.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access job order %', p_actor_auth_user_id, p_job_order_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_handoff from app.job_order_handoffs where id = v_job.source_handoff_id;

  for v_shipment in select * from app.shipment_orders where job_order_id = p_job_order_id order by created_at loop
    if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
      continue;
    end if;

    v_accessible_shipment_ids := v_accessible_shipment_ids || v_shipment.id;

    select * into v_epod from app.epod_captures where shipment_order_id = v_shipment.id and is_latest_version;
    select * into v_cost from app.shipment_actual_costs where shipment_order_id = v_shipment.id and is_current;
    select * into v_milestone from app.shipment_milestone_projections where shipment_order_id = v_shipment.id;

    v_shipments := v_shipments || jsonb_build_object(
      'shipmentOrderId', v_shipment.id,
      'shipmentNumber', v_shipment.shipment_number,
      'status', v_shipment.status,
      'milestone', case when v_milestone.shipment_order_id is not null then jsonb_build_object(
        'lastMilestoneCode', v_milestone.last_milestone_code,
        'isDelayed', v_milestone.is_delayed,
        'currentEta', v_milestone.current_eta
      ) else null end,
      'epod', case when v_epod.id is not null then jsonb_build_object(
        'epodCaptureId', v_epod.id, 'status', v_epod.status, 'versionNumber', v_epod.version_number
      ) else null end,
      'actualCost', case when v_cost.id is not null then jsonb_build_object(
        'shipmentActualCostId', v_cost.id, 'status', v_cost.status, 'versionNumber', v_cost.version_number
      ) else null end
    );
  end loop;

  select * into v_profitability from app.job_profitability_snapshots where job_order_id = p_job_order_id and is_current;
  select * into v_billing from app.billing_readiness_evaluations where job_order_id = p_job_order_id and is_current;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', e.id, 'relationType', e.relation_type, 'sourceType', e.source_type, 'sourceId', e.source_id,
    'targetType', e.target_type, 'targetId', e.target_id, 'sourceVersionHash', e.source_version_hash,
    'isOverride', e.is_override, 'overrideReason', e.override_reason, 'createdAt', e.created_at
  ) order by e.created_at), '[]'::jsonb)
  into v_edges
  from app.transaction_lineage_edges e
  where e.tenant_id = v_job.tenant_id
    and (
      (e.relation_type in ('quote_to_job', 'job_to_profitability', 'job_to_billing_readiness') and (e.source_id = p_job_order_id or e.target_id = p_job_order_id))
      or (e.relation_type = 'job_to_shipment' and e.source_id = p_job_order_id and e.target_id = any (v_accessible_shipment_ids))
      or (e.relation_type in ('shipment_to_epod', 'shipment_to_cost') and e.source_id = any (v_accessible_shipment_ids))
    );

  v_manifest := jsonb_build_object(
    'jobOrderId', v_job.id,
    'jobNumber', v_job.job_number,
    'sourceHandoffId', v_job.source_handoff_id,
    'sourceQuotationId', case when v_handoff.id is not null then v_handoff.quotation_id else null end,
    'sourcePayloadHash', case when v_handoff.id is not null then v_handoff.payload_hash else null end,
    'shipments', v_shipments,
    'profitability', case when v_profitability.id is not null then jsonb_build_object(
      'jobProfitabilitySnapshotId', v_profitability.id, 'status', v_profitability.status, 'versionNumber', v_profitability.version_number
    ) else null end,
    'billingReadiness', case when v_billing.id is not null then jsonb_build_object(
      'billingReadinessEvaluationId', v_billing.id, 'effectiveStatus', v_billing.effective_status, 'versionNumber', v_billing.version_number
    ) else null end,
    'edges', v_edges
  );

  return v_manifest;
end;
$$;

comment on function app.get_transaction_lineage is
  'OPS-184: one traceable operational transaction chain for Finance, customers and auditors (Prompt 184 §5) -- rooted at a Job Order, filtered per hop via app.can_access_record, folding in the shipment''s current app.shipment_milestone_projections row rather than any per-event history.';

-- Authorized correction: adds a reasoned lineage mapping without deleting or mutating any
-- prior evidence row (Prompt 184 §22). The table''s own check constraints (relation/node
-- type pairing) and unique constraint (no duplicate edge) are the real validation boundary
-- -- this function only adds the OPS:Override gate and the mandatory-reason rule on top.
create function app.record_transaction_lineage_override(
  p_tenant_id uuid,
  p_relation_type text,
  p_source_type text,
  p_source_id uuid,
  p_target_type text,
  p_target_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.transaction_lineage_edges
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_edge app.transaction_lineage_edges;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'transaction_lineage_override_reason_required: a non-empty reason is required to override a lineage mapping' using errcode = 'check_violation';
  end if;

  insert into app.transaction_lineage_edges (
    tenant_id, relation_type, source_type, source_id, target_type, target_id,
    is_override, override_reason, created_by_auth_user_id, created_by_label
  ) values (
    p_tenant_id, p_relation_type, p_source_type, p_source_id, p_target_type, p_target_id,
    true, p_reason, p_actor_auth_user_id, p_actor_label
  )
  on conflict (tenant_id, source_type, source_id, target_type, target_id, relation_type) do nothing
  returning * into v_edge;

  if v_edge.id is null then
    raise exception 'transaction_lineage_edge_already_recorded: an edge already exists for % % -> % % (%)', p_source_type, p_source_id, p_target_type, p_target_id, p_relation_type
      using errcode = 'unique_violation';
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'record_transaction_lineage_override',
    'app.transaction_lineage_edges', v_edge.id, 'success', p_reason,
    null,
    jsonb_build_object('source_type', p_source_type, 'source_id', p_source_id, 'target_type', p_target_type, 'target_id', p_target_id, 'relation_type', p_relation_type)
  );

  return v_edge;
end;
$$;

comment on function app.record_transaction_lineage_override is
  'OPS-184: the one authorized way to add a lineage edge outside the six automatic triggers -- OPS:Override-gated, reason-mandatory, rejects (unique_violation) a pairing that already exists rather than silently doing nothing, since this is an explicit human-invoked correction.';

create type app.transaction_lineage_anomaly as (
  anomaly_type text,
  relation_type text,
  target_type text,
  target_id uuid,
  detail text
);

-- Reconciliation diagnostic (Prompt 184 §13/§19/§25): detects the three anomaly classes
-- that could, in principle, arise from data captured outside the trigger path (a direct
-- migration, a restored backup, a bug in a future capability) -- never fabricates a
-- source link, only reports what it finds.
create function app.detect_transaction_lineage_anomalies(
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
    and not exists (
      select 1 from app.transaction_lineage_edges e
      where e.tenant_id = so.tenant_id and e.relation_type = 'job_to_shipment' and e.target_type = 'shipment_order' and e.target_id = so.id
    );

  return query
  select 'orphan_billing_readiness'::text, 'job_to_billing_readiness'::text, 'billing_readiness_evaluation'::text, bre.id,
    format('billing readiness evaluation %s (job %s) has no recorded job_to_billing_readiness lineage edge', bre.id, bre.job_order_id)
  from app.billing_readiness_evaluations bre
  where bre.tenant_id = p_tenant_id
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
  'OPS-184: read-only reconciliation diagnostic, OPS:Override-gated (the same tenant-repair authority app.override_billing_readiness already requires) -- never mutates anything itself; a real correction is a separate, explicit app.record_transaction_lineage_override call.';

-- Brownfield backfill (Prompt 184 §19): reconciles any job order/shipment order/ePOD/
-- actual cost/profitability snapshot/billing readiness evaluation row that predates this
-- migration''s triggers (or was otherwise captured outside them) by (re-)deriving its
-- lineage edge -- reuses app.capture_transaction_lineage_edge''s own idempotent insert, so
-- a row that already has its edge is silently skipped, never duplicated.
create function app.backfill_transaction_lineage(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns integer
language plpgsql
security definer
set search_path = app, public, extensions, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_count integer := 0;
  v_job app.job_orders;
  v_shipment app.shipment_orders;
  v_epod app.epod_captures;
  v_cost app.shipment_actual_costs;
  v_profitability app.job_profitability_snapshots;
  v_billing app.billing_readiness_evaluations;
  v_edge app.transaction_lineage_edges;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  for v_job in select * from app.job_orders where tenant_id = p_tenant_id loop
    v_edge := app.capture_transaction_lineage_edge(
      v_job.tenant_id, 'quote_to_job', 'job_order_handoff', v_job.source_handoff_id, 'job_order', v_job.id,
      (select payload_hash from app.job_order_handoffs where id = v_job.source_handoff_id),
      v_job.owner_user_id, v_job.org_unit_id
    );
    if v_edge.id is not null then v_count := v_count + 1; end if;

    select * into v_profitability from app.job_profitability_snapshots where job_order_id = v_job.id and is_current;
    if v_profitability.id is not null then
      v_edge := app.capture_transaction_lineage_edge(
        v_job.tenant_id, 'job_to_profitability', 'job_order', v_job.id, 'job_profitability_snapshot', v_profitability.id,
        encode(digest(coalesce(v_profitability.revenue_amount::text, '') || '|' || coalesce(v_profitability.cost_amount::text, '') || '|' || coalesce(v_profitability.margin_amount::text, '') || '|' || v_profitability.status, 'sha256'), 'hex'),
        v_job.owner_user_id, v_job.org_unit_id
      );
      if v_edge.id is not null then v_count := v_count + 1; end if;
    end if;

    select * into v_billing from app.billing_readiness_evaluations where job_order_id = v_job.id and is_current;
    if v_billing.id is not null then
      v_edge := app.capture_transaction_lineage_edge(
        v_job.tenant_id, 'job_to_billing_readiness', 'job_order', v_job.id, 'billing_readiness_evaluation', v_billing.id,
        encode(digest(v_billing.evaluated_status || '|' || coalesce(v_billing.blockers::text, ''), 'sha256'), 'hex'),
        v_job.owner_user_id, v_job.org_unit_id
      );
      if v_edge.id is not null then v_count := v_count + 1; end if;
    end if;
  end loop;

  for v_shipment in select * from app.shipment_orders where tenant_id = p_tenant_id loop
    v_edge := app.capture_transaction_lineage_edge(
      v_shipment.tenant_id, 'job_to_shipment', 'job_order', v_shipment.job_order_id, 'shipment_order', v_shipment.id,
      encode(digest(
        coalesce(v_shipment.consignee_snapshot::text, '') || '|' || coalesce(v_shipment.cargo_service_snapshot::text, '') || '|' ||
        v_shipment.service_type || '|' || v_shipment.mode || '|' || v_shipment.origin || '|' || v_shipment.destination,
        'sha256'
      ), 'hex'),
      v_shipment.owner_user_id, v_shipment.org_unit_id
    );
    if v_edge.id is not null then v_count := v_count + 1; end if;

    select * into v_epod from app.epod_captures where shipment_order_id = v_shipment.id and is_latest_version;
    if v_epod.id is not null then
      v_edge := app.capture_transaction_lineage_edge(
        v_shipment.tenant_id, 'shipment_to_epod', 'shipment_order', v_shipment.id, 'epod_capture', v_epod.id,
        encode(digest(
          coalesce(v_epod.receiver_name, '') || '|' || coalesce(v_epod.signature_file_id::text, '') || '|' ||
          coalesce(array_to_string(v_epod.photo_file_ids, ','), '') || '|' || coalesce(v_epod.captured_at::text, ''),
          'sha256'
        ), 'hex'),
        v_shipment.owner_user_id, v_shipment.org_unit_id
      );
      if v_edge.id is not null then v_count := v_count + 1; end if;
    end if;

    select * into v_cost from app.shipment_actual_costs where shipment_order_id = v_shipment.id and is_current;
    if v_cost.id is not null then
      v_edge := app.capture_transaction_lineage_edge(
        v_shipment.tenant_id, 'shipment_to_cost', 'shipment_order', v_shipment.id, 'shipment_actual_cost', v_cost.id,
        encode(digest(coalesce(v_cost.currency, '') || '|' || coalesce(v_cost.total_amount::text, '') || '|' || v_cost.status, 'sha256'), 'hex'),
        v_shipment.owner_user_id, v_shipment.org_unit_id
      );
      if v_edge.id is not null then v_count := v_count + 1; end if;
    end if;
  end loop;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'backfill_transaction_lineage',
    'app.transaction_lineage_edges', null, 'success', format('%s edge(s) backfilled', v_count), null, jsonb_build_object('edges_backfilled', v_count)
  );

  return v_count;
end;
$$;

comment on function app.backfill_transaction_lineage is
  'OPS-184: idempotent brownfield reconciliation -- safe to call repeatedly (already-captured rows are silently skipped via app.capture_transaction_lineage_edge''s own ON CONFLICT DO NOTHING), OPS:Override-gated, returns the count of edges newly captured this call.';

alter table app.transaction_lineage_edges enable row level security;

create policy transaction_lineage_edges_select_scoped on app.transaction_lineage_edges
  for select to authenticated
  using (app.can_access_record((select auth.uid()), tenant_id, owner_user_id, app.lead_record_scope_org_unit_ids(org_unit_id), null));

revoke execute on all functions in schema app from public;

grant select on app.transaction_lineage_edges to authenticated, service_role;
grant insert, update, delete on app.transaction_lineage_edges to service_role;

grant execute on function app.get_transaction_lineage(uuid, uuid) to authenticated, service_role;
grant execute on function app.record_transaction_lineage_override(uuid, text, text, uuid, text, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.detect_transaction_lineage_anomalies(uuid, uuid) to authenticated, service_role;
grant execute on function app.backfill_transaction_lineage(uuid, uuid, text) to authenticated, service_role;
