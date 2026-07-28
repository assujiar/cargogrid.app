-- Operations capability OPS-185 (Operations Integrated Verification, CG-S8-OPS-019) --
-- one real, disclosed hardening fix discovered during this checkpoint's own integrated
-- cross-capability db-test (scripts/db-tests/operations-integrated-verification.sql),
-- not a new capability.
--
-- Discovery: `app.record_transaction_lineage_override` (OPS-184,
-- 20260728170000_create_operations_transaction_lineage.sql) checked only tenant-wide
-- `OPS:Override` permission -- it never checked whether the calling actor could actually
-- access the specific Job Order/Shipment Order/handoff record named as the correction's
-- source or target. Since `OPS:Override` is a tenant-wide role grant, not a record-scoped
-- one, this meant any actor holding that permission anywhere in the tenant could inject a
-- lineage correction referencing a record they own no ownership/org-unit stake in and
-- would otherwise be denied on every other read/write path for -- the exact "existence/
-- count/errors cannot reveal inaccessible records" and record-scope discipline every
-- other Operations mutation function already enforces. The integrated-verification
-- fixture's own "sibling-team outsider, wrong record scope, full grants incl Override"
-- probe caught this directly: the outsider was NOT denied.
--
-- Per this repository's immutable-migrations convention, `20260728170000_*.sql` is never
-- edited -- this migration `CREATE OR REPLACE FUNCTION`s the exact same signature with the
-- missing checks added, the same "extend via a new migration" discipline every other
-- checkpoint this session has followed for functions (as opposed to whole tables/rows,
-- which are extended via new INSERTs/columns instead).
--
-- Fix: resolve record-scope from whichever side(s) of the edge are one of the three
-- anchor node types that actually carry owner_user_id/org_unit_id
-- (job_order_handoff/job_order/shipment_order) -- every one of the six relation types has
-- at least one such anchor on its source or target per the table's own
-- transaction_lineage_edges_relation_pair_check constraint. A side that resolves to a
-- real row is record-scope-checked; a side that does not exist yet (a genuinely-orphan
-- correction, extremely rare) is left unchecked rather than blocking a legitimate repair,
-- matching app.get_transaction_lineage's own "check what actually resolves" posture.

create or replace function app.record_transaction_lineage_override(
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
  v_job app.job_orders;
  v_shipment app.shipment_orders;
  v_handoff app.job_order_handoffs;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'transaction_lineage_override_reason_required: a non-empty reason is required to override a lineage mapping' using errcode = 'check_violation';
  end if;

  if p_source_type = 'job_order' then
    select * into v_job from app.job_orders where id = p_source_id;
    if found and not app.can_access_record(p_actor_auth_user_id, v_job.tenant_id, v_job.owner_user_id, app.lead_record_scope_org_unit_ids(v_job.org_unit_id), null) then
      raise exception 'insufficient_authority: identity % cannot access job order % (source)', p_actor_auth_user_id, p_source_id using errcode = 'insufficient_privilege';
    end if;
  elsif p_source_type = 'shipment_order' then
    select * into v_shipment from app.shipment_orders where id = p_source_id;
    if found and not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
      raise exception 'insufficient_authority: identity % cannot access shipment order % (source)', p_actor_auth_user_id, p_source_id using errcode = 'insufficient_privilege';
    end if;
  elsif p_source_type = 'job_order_handoff' then
    select * into v_handoff from app.job_order_handoffs where id = p_source_id;
    if found and not app.can_access_record(p_actor_auth_user_id, v_handoff.tenant_id, v_handoff.owner_user_id, app.lead_record_scope_org_unit_ids(v_handoff.org_unit_id), null) then
      raise exception 'insufficient_authority: identity % cannot access job order handoff % (source)', p_actor_auth_user_id, p_source_id using errcode = 'insufficient_privilege';
    end if;
  end if;

  if p_target_type = 'job_order' then
    select * into v_job from app.job_orders where id = p_target_id;
    if found and not app.can_access_record(p_actor_auth_user_id, v_job.tenant_id, v_job.owner_user_id, app.lead_record_scope_org_unit_ids(v_job.org_unit_id), null) then
      raise exception 'insufficient_authority: identity % cannot access job order % (target)', p_actor_auth_user_id, p_target_id using errcode = 'insufficient_privilege';
    end if;
  elsif p_target_type = 'shipment_order' then
    select * into v_shipment from app.shipment_orders where id = p_target_id;
    if found and not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
      raise exception 'insufficient_authority: identity % cannot access shipment order % (target)', p_actor_auth_user_id, p_target_id using errcode = 'insufficient_privilege';
    end if;
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
  'OPS-184/OPS-185-hardened: the one authorized way to add a lineage edge outside the six automatic triggers -- OPS:Override-gated AND record-scope-checked on whichever side(s) resolve to a real job_order/shipment_order/job_order_handoff row, reason-mandatory, rejects (unique_violation) a pairing that already exists. The record-scope check was missing at OPS-184''s own authoring and is added here, discovered by OPS-185''s own integrated cross-capability verification fixture.';

-- No grant/revoke statements needed -- CREATE OR REPLACE FUNCTION preserves the exact
-- same name/signature/owner, so the grants already issued at OPS-184's own migration
-- (authenticated, service_role; anon holds none) remain in force unchanged.
