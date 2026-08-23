-- Operations capability OPS-181 (Billing Readiness, CG-S8-OPS-015)
-- A versioned, deterministic, explainable billing-readiness evaluation per Job Order
-- -- exact blockers when not ready, a bounded authorized-override path, and one
-- idempotent Finance handoff record. Explicitly evidence status, never an invoice,
-- accounts receivable (AR), general ledger (GL) entry, or journal (Prompt 181 §24).
--
-- Scope and design decisions, disclosed rather than left implicit:
--
-- * **No new permission action.** Evaluation/handoff reuse `OPS:Edit`, the same
--   general write gate every prior Operations lifecycle mutation (confirm/transition/
--   dispatch/etc.) already uses. Override/revoke-override reuse `OPS:Override`
--   (the fixed 19-action `PLT-111` vocabulary, already registered for `OPS` at
--   `PLT-110` and already exercised by `OPS-168`'s own `app.override_job_order_field`)
--   -- no new catalogue row, matching `OPS-178`'s own "reuse an existing action when
--   one already fits" precedent.
-- * **Evidence checked per Shipment Order belonging to the Job Order** (cancelled
--   shipments are excluded -- they carry no billing obligation): delivery+ePOD
--   completion (`status in ('epod', 'closed')` -- the only two statuses reachable via
--   `OPS-177`'s own `app.complete_epod_capture`, so this is the real evidence, not a
--   proxy), the document checklist (`OPS-176`'s own missing-mandatory-items query,
--   inlined rather than calling that capability's own RPC a second time and paying its
--   permission check twice), no active operational exception (`OPS-174`'s own
--   `app.operational_exceptions.status not in ('resolved', 'closed')`), and an
--   approved actual cost (`OPS-178`'s own `is_current and status = 'approved'`).
-- * **The customer billing profile check reuses `app.job_orders.credit_snapshot`
--   verbatim** -- the exact `{outcome, checkedAt}` object `COM-164`'s own
--   `app.prepare_job_order_handoff` already pinned from the most recent
--   `app.credit_check_snapshots` row for the account, at handoff time. This is the
--   same "read the governed snapshot verbatim, never re-derive" discipline `OPS-179`
--   already established for `revenue_snapshot` -- no new live cross-module read is
--   invented. `outcome = 'allow'` is ready; a null snapshot (`billing_profile_missing`,
--   no credit check was ever run before this Job Order's own handoff) or any
--   `blocked_*` outcome (`billing_profile_not_cleared`, the exact outcome recorded for
--   explainability) is not ready.
-- * **No configurable rule-engine table.** `rule_version` is a fixed, disclosed
--   placeholder (`1`) recorded on every evaluation for forward compatibility -- a full
--   editable rule-configuration surface is out of scope for this MVP slice, the same
--   class of disclosed simplification `OPS-179`'s own "no FX conversion" boundary
--   already established.
-- * **Versioned, `is_current`-exclusive, never rewritten in place** (§24): the first
--   evaluation for a Job Order needs no reason; every subsequent evaluation while a
--   current row already exists requires a non-empty `reevaluation_reason` -- the same
--   discipline `OPS-178`/`OPS-179`'s own recalculation/adjustment reasoning already
--   established. A reevaluation always resets any prior override (§24: "evidence
--   changes do not silently preserve readiness") -- overriding is a disposition on one
--   specific evaluated snapshot, not a standing exemption.
-- * **Override is bounded to forcing an evaluated `not_ready` row to an effective
--   `ready` outcome, never the reverse** -- `effective_status` is a generated column
--   (`ready` while `is_overridden`, else the evidence-based `evaluated_status`), so the
--   raw evidence result remains visible and queryable even while overridden. Revoking
--   an override restores the evidence-based status; it never re-evaluates evidence
--   itself (`app.evaluate_billing_readiness` is the only evidence-reading path).
-- * **The Finance handoff is a stable, idempotent record, not a live Finance
--   integration** (Phase 4 does not exist yet) -- `app.billing_readiness_handoffs` is
--   the same "structurally ready, not yet populated by a real consumer" disclosure
--   `app.job_orders.downstream_reference`/`app.job_order_handoffs` already established
--   for the Commercial->Operations boundary, now for the Operations->Finance boundary.
--   Idempotent on `(tenant_id, job_order_id, idempotency_key)` -- the same
--   "unique_violation caught, current row re-selected" idiom `OPS-173`/`OPS-175`
--   already established. Multiple handoffs may exist for one Job Order over time (one
--   per evaluation version actually handed off) -- this migration does not forbid a
--   legitimate re-handoff after a later reevaluation.
-- * Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries its own
--   explicit REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC statement before
--   its final grants, the standing per-migration convention since PLT-118.

create table app.billing_readiness_evaluations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  job_order_id uuid not null references app.job_orders (id),
  version_number integer not null default 1,
  is_current boolean not null default true,
  evaluated_status text not null,
  effective_status text generated always as (case when is_overridden then 'ready' else evaluated_status end) stored,
  blockers jsonb not null default '[]'::jsonb,
  evidence jsonb not null default '{}'::jsonb,
  rule_version integer not null default 1,
  is_overridden boolean not null default false,
  override_reason text,
  overridden_by_auth_user_id uuid,
  overridden_by text,
  overridden_at timestamptz,
  override_revoked_reason text,
  override_revoked_by text,
  override_revoked_at timestamptz,
  reevaluation_reason text,
  supersedes_evaluation_id uuid references app.billing_readiness_evaluations (id),
  evaluated_by_auth_user_id uuid not null,
  evaluated_by text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint billing_readiness_evaluations_status_check check (evaluated_status in ('ready', 'not_ready')),
  constraint billing_readiness_evaluations_version_number_check check (version_number > 0),
  constraint billing_readiness_evaluations_override_reason_check check (not is_overridden or (override_reason is not null and length(trim(override_reason)) > 0)),
  constraint billing_readiness_evaluations_not_self_supersede check (supersedes_evaluation_id is null or supersedes_evaluation_id <> id)
);

comment on table app.billing_readiness_evaluations is
  'OPS-181: one versioned, deterministic billing-readiness evaluation per Job Order (is_current exclusive via partial unique index). effective_status is a generated column -- ready while is_overridden, else the raw evidence-based evaluated_status -- so an override never hides the underlying evidence result. blockers/evidence are the capability''s own explainability seam: exact, named, source-versioned reasons, never a vague "not ready".';

create unique index billing_readiness_evaluations_one_current_idx on app.billing_readiness_evaluations (job_order_id) where is_current;
create index billing_readiness_evaluations_tenant_job_idx on app.billing_readiness_evaluations (tenant_id, job_order_id);

create function app.touch_billing_readiness_evaluations_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger billing_readiness_evaluations_touch_row
  before update on app.billing_readiness_evaluations
  for each row
  execute function app.touch_billing_readiness_evaluations_row();

create table app.billing_readiness_handoffs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  job_order_id uuid not null references app.job_orders (id),
  evaluation_id uuid not null references app.billing_readiness_evaluations (id),
  idempotency_key text not null,
  handed_off_by_auth_user_id uuid not null,
  handed_off_by text,
  handed_off_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint billing_readiness_handoffs_tenant_job_idempotency_unique unique (tenant_id, job_order_id, idempotency_key)
);

comment on table app.billing_readiness_handoffs is
  'OPS-181: one append-only, idempotent Finance-handoff record per successful app.handoff_billing_readiness call -- the stable Phase 4 input this capability produces (Prompt 181 §4). No Finance/AR/GL system exists yet to consume it; this is the same disclosed "structurally ready, not yet populated by a real consumer" posture app.job_order_handoffs (COM-164) already established for the Commercial->Operations boundary.';

create index billing_readiness_handoffs_tenant_job_idx on app.billing_readiness_handoffs (tenant_id, job_order_id);

-- The one evidence-reading, versioning entry point (Prompt 181 §20 task 2).
create function app.evaluate_billing_readiness(
  p_job_order_id uuid,
  p_reevaluation_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.billing_readiness_evaluations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
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
  if not found then
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
$$;

comment on function app.evaluate_billing_readiness is
  'OPS-181: the one evidence-reading, versioning entry point. The first evaluation for a Job Order needs no reason; every subsequent evaluation while a current row already exists requires a non-empty reevaluation_reason. Always inserts a brand-new version -- the prior version remains linked (supersedes_evaluation_id), never rewritten.';

-- Bounded, reason-mandatory override -- may only force an evaluated not_ready row to
-- an effective ready outcome (Prompt 181 §22).
create function app.override_billing_readiness(
  p_job_order_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.billing_readiness_evaluations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_job app.job_orders;
  v_decision app.rbac_decision;
  v_current app.billing_readiness_evaluations;
  v_updated app.billing_readiness_evaluations;
begin
  select * into v_job from app.job_orders where id = p_job_order_id;
  if not found then
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

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'override_billing_readiness',
    'app.billing_readiness_evaluations', v_updated.id, 'success', p_reason,
    jsonb_build_object('evaluated_status', v_current.evaluated_status),
    jsonb_build_object('effective_status', v_updated.effective_status, 'override_reason', p_reason)
  );

  return v_updated;
end;
$$;

comment on function app.override_billing_readiness is
  'OPS-181: forces the current evaluation''s effective_status to ready via the generated column (evaluated_status itself is never mutated) -- bounded to a not_ready row (billing_readiness_override_not_needed otherwise), optimistic-concurrency-checked, reason mandatory.';

create function app.revoke_billing_readiness_override(
  p_job_order_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.billing_readiness_evaluations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_job app.job_orders;
  v_decision app.rbac_decision;
  v_current app.billing_readiness_evaluations;
  v_updated app.billing_readiness_evaluations;
begin
  select * into v_job from app.job_orders where id = p_job_order_id;
  if not found then
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

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'revoke_billing_readiness_override',
    'app.billing_readiness_evaluations', v_updated.id, 'success', p_reason,
    jsonb_build_object('effective_status', 'ready'),
    jsonb_build_object('effective_status', v_updated.effective_status)
  );

  return v_updated;
end;
$$;

comment on function app.revoke_billing_readiness_override is
  'OPS-181: restores the evidence-based evaluated_status as the effective outcome -- never re-evaluates evidence itself. override_reason is preserved (never nulled) for lineage; override_revoked_reason/_by/_at record the revocation separately.';

-- Idempotent Finance handoff (Prompt 181 §20 task 3) -- requires the current
-- evaluation to be effectively ready (evidence-based or overridden).
create function app.handoff_billing_readiness(
  p_job_order_id uuid,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.billing_readiness_handoffs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_job app.job_orders;
  v_decision app.rbac_decision;
  v_current app.billing_readiness_evaluations;
  v_handoff app.billing_readiness_handoffs;
begin
  select * into v_job from app.job_orders where id = p_job_order_id;
  if not found then
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
$$;

comment on function app.handoff_billing_readiness is
  'OPS-181: idempotent on (tenant_id, job_order_id, idempotency_key) -- a genuine retry with the same key returns the exact same handoff row (unique_violation caught, current row re-selected), never a duplicate. Requires the current evaluation''s effective_status = ready; the exception this raises for a not_ready job order is a normal validation failure, not a state this function itself needs to durably log before failing, so it is never caught by an enclosing block here.';

alter table app.billing_readiness_evaluations enable row level security;
alter table app.billing_readiness_handoffs enable row level security;

create policy billing_readiness_evaluations_select_scoped on app.billing_readiness_evaluations
  for select to authenticated
  using (
    exists (
      select 1 from app.job_orders jo
      where jo.id = billing_readiness_evaluations.job_order_id
        and app.can_access_record((select auth.uid()), jo.tenant_id, jo.owner_user_id, app.lead_record_scope_org_unit_ids(jo.org_unit_id), null)
    )
  );

create policy billing_readiness_handoffs_select_scoped on app.billing_readiness_handoffs
  for select to authenticated
  using (
    exists (
      select 1 from app.job_orders jo
      where jo.id = billing_readiness_handoffs.job_order_id
        and app.can_access_record((select auth.uid()), jo.tenant_id, jo.owner_user_id, app.lead_record_scope_org_unit_ids(jo.org_unit_id), null)
    )
  );

revoke execute on all functions in schema app from public;

grant select on app.billing_readiness_evaluations to authenticated, service_role;
grant insert, update, delete on app.billing_readiness_evaluations to service_role;
grant select on app.billing_readiness_handoffs to authenticated, service_role;
grant insert, update, delete on app.billing_readiness_handoffs to service_role;

grant execute on function app.evaluate_billing_readiness(uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.override_billing_readiness(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.revoke_billing_readiness_override(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.handoff_billing_readiness(uuid, text, uuid, text) to authenticated, service_role;
