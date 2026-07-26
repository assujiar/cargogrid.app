-- Commercial capability COM-153 (Quotation Approval, CG-S7-COM-012)
-- Configurable quotation approval driven by margin/discount/value thresholds, instantiating
-- (not re-forking) two already-VERIFIED Platform primitives: `PLT-121`'s Configuration
-- Engine + `PLT-123`'s Approval Engine (`app.config_objects/config_versions/config_items`,
-- `app.approval_requests/approval_request_steps/approval_decisions/approval_delegations`,
-- `app.request_approval/decide_approval_step/cancel_approval_request/escalate_approval_step/
-- create_approval_delegation/revoke_approval_delegation`). `COM-151`'s own migration header
-- disclosed exactly this boundary in advance: "Approval routing (threshold-driven approver
-- resolution) is Prompt 153's own scope -- this migration's app.submit_quotation only
-- transitions draft -> submitted ... it does not resolve or notify an approver." This
-- migration is that follow-through.
--
-- Scope boundaries (disclosed, not silently narrowed, matching every prior checkpoint's
-- discipline):
--
-- * **Two axes, not one.** `app.quotations.status` (draft/submitted/cancelled, `COM-151`)
--   keeps meaning "submission lifecycle state" only. A new `approval_status`
--   (not_required/pending/approved/rejected) is the approval-routing outcome for the exact
--   submitted version -- kept as its own column rather than folded into `status`, because
--   "Approval always binds one exact quote version and calculation snapshot" (Prompt 153
--   §24) is a property of the version, independent of whether it happens to still say
--   `submitted`.
-- * **Thresholds are a bespoke, tenant-wide versioned policy table
--   (`app.quotation_approval_rules`), not a second Configuration Engine instantiation.**
--   `COM-150`'s own `app.margin_rule_versions` is the direct precedent for this shape
--   (draft/published/archived, `supersedes_version_id`, exactly one published row per
--   tenant via a partial unique index) -- deciding "is a threshold rule a versioned business
--   policy or a generic Configuration Engine object" the same way `COM-150` already decided
--   it for margin rules, not a fresh call. Margin/discount/value are covered; customer,
--   service, and organizational thresholds are a real, larger feature not built in this
--   bounded slice (the same "tenant-wide only, no per-org-unit rule" disclosure `COM-150`'s
--   own header already made for margin rules).
-- * **The approval *routing* definition (pattern/steps/approvers) is the Approval Engine's
--   own `config_type_code='approval'` object, scoped `tenant` -- exactly one per tenant in
--   this bounded slice** (entity_type discriminates the request, not a second definition
--   dimension). Publishing it uses the already-existing, already-VERIFIED generic Platform
--   RPCs (`app.create_config_draft`/`app.set_config_items`/`app.publish_approval_definition`)
--   directly -- no new SQL and no dedicated Commercial UI to author routing steps is built
--   here, the same "ships with zero authoring UI" precedent `PLT-123` itself already set.
-- * **`app.submit_quotation` (CREATE OR REPLACE, widening `COM-151`/`COM-152`'s own body,
--   never editing an already-applied migration file) is where routing happens**, not a
--   second API call -- Prompt 153 §21's "Submitted quote resolves the correct approvers"
--   reads as one atomic action, so requesting approval (or auto-approving when no threshold
--   is crossed) happens inside the same transaction as the draft -> submitted transition.
--   A tenant with no published `app.quotation_approval_rules` row skips routing entirely
--   (`approval_status='not_required'`) -- thresholds are opt-in, not a default block. A
--   tenant whose thresholds ARE crossed but has no published routing definition fails
--   closed (`approval_definition_not_configured`) rather than silently letting the
--   quotation through -- Prompt 153 §23's "threshold conflict ... blocks safely."
-- * **`app.decide_quotation_approval_step` is the one domain-specific sync wrapper this
--   migration adds over the Approval Engine.** The engine itself is entity-agnostic (Prompt
--   123's own disclosed scope) and cannot write back to `app.quotations` -- this wrapper
--   calls `app.decide_approval_step` (unchanged, not re-implemented) and, only when the
--   underlying request reaches a final state, syncs `approval_status` on the bound
--   quotation. Delegation and escalation need no domain sync (neither changes a request's
--   final outcome) -- the API layer calls `app.create_approval_delegation`/
--   `app.revoke_approval_delegation`/`app.escalate_approval_step` directly, unwrapped.
-- * **"Request revision" is not a fourth decision verb.** The Approval Engine's own
--   `approval_decisions.decision` CHECK is `approved`/`rejected` only (Prompt 123's own
--   bounded scope, not widened here for one call site). An approver requesting revision
--   decides `rejected` with a reason; `app.create_quotation_revision` (`COM-152`, already
--   built) is the real "a new/revised quote returns through a fresh governed approval path"
--   mechanism (Prompt 153 §22) -- the new revision starts at `approval_status='not_required'`
--   by column default (its INSERT never lists the new columns), so it is re-evaluated from
--   scratch on its own next submission, never inheriting a rejected verdict.
-- * **Legacy submitted quotations are never retroactively approved.** Every `app.quotations`
--   row that predates this migration defaults to `approval_status='not_required'` (the
--   column default) purely because it was never routed through this capability -- it is NOT
--   backfilled to `'approved'`, and no batch reconciliation runs here (Prompt 153 §19:
--   "never auto-approve legacy records"). Whether a pre-existing submitted quotation should
--   be acceptance-eligible is `COM-154`'s own reconciliation policy to define, not invented
--   here.
-- * **Money stays `numeric` end to end** in the threshold evaluator, matching `COM-150`'s
--   own discipline -- no implicit float cast anywhere in `app.evaluate_quotation_approval_
--   requirement`.
-- * Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration carries its own
--   explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement before
--   its final grants, the standing per-migration convention since `PLT-118`.

create table app.quotation_approval_rules (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  min_margin_pct numeric(5, 2),
  max_discount_pct numeric(5, 2),
  min_value_amount numeric(14, 2),
  status text not null default 'draft',
  supersedes_version_id uuid references app.quotation_approval_rules (id),
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint quotation_approval_rules_status_check check (status in ('draft', 'published', 'archived')),
  constraint quotation_approval_rules_min_margin_check check (min_margin_pct is null or (min_margin_pct >= 0 and min_margin_pct <= 100)),
  constraint quotation_approval_rules_max_discount_check check (max_discount_pct is null or (max_discount_pct >= 0 and max_discount_pct <= 100)),
  constraint quotation_approval_rules_min_value_check check (min_value_amount is null or min_value_amount >= 0),
  constraint quotation_approval_rules_at_least_one_threshold check (min_margin_pct is not null or max_discount_pct is not null or min_value_amount is not null),
  constraint quotation_approval_rules_not_self_supersede check (supersedes_version_id is null or supersedes_version_id <> id)
);

comment on table app.quotation_approval_rules is
  'COM-153: a versioned, tenant-wide quotation approval threshold policy -- min_margin_pct/max_discount_pct/min_value_amount are each optional (null = that dimension never triggers approval), but at least one must be set. Editing a published rule in place is never allowed -- app.publish_quotation_approval_rule_version''s p_supersedes_version_id parameter archives the prior published rule and links the new one, the same versioned-never-edited-in-place mechanism app.publish_margin_rule_version (COM-150) already established.';

create unique index quotation_approval_rules_tenant_published_unique on app.quotation_approval_rules (tenant_id) where status = 'published';
create index quotation_approval_rules_tenant_status_idx on app.quotation_approval_rules (tenant_id, status);

create function app.create_quotation_approval_rule_version(
  p_tenant_id uuid,
  p_min_margin_pct numeric,
  p_max_discount_pct numeric,
  p_min_value_amount numeric,
  p_actor_auth_user_id uuid,
  p_created_by text
)
returns app.quotation_approval_rules
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_rule app.quotation_approval_rules;
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

  insert into app.quotation_approval_rules (tenant_id, min_margin_pct, max_discount_pct, min_value_amount, created_by)
  values (p_tenant_id, p_min_margin_pct, p_max_discount_pct, p_min_value_amount, p_created_by)
  returning * into v_rule;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_created_by, 'create_quotation_approval_rule_version',
    'app.quotation_approval_rules', v_rule.id, 'success', null, null, to_jsonb(v_rule)
  );

  return v_rule;
end;
$$;

create function app.publish_quotation_approval_rule_version(
  p_rule_version_id uuid,
  p_expected_version integer,
  p_supersedes_version_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.quotation_approval_rules
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_rule app.quotation_approval_rules;
  v_superseded app.quotation_approval_rules;
  v_decision app.rbac_decision;
begin
  select * into v_rule from app.quotation_approval_rules where id = p_rule_version_id;
  if not found then
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
$$;

comment on function app.publish_quotation_approval_rule_version is
  'COM-153: draft -> published, archiving p_supersedes_version_id (if supplied) first so at most one published rule ever exists per tenant (enforced by quotation_approval_rules_tenant_published_unique) -- mirrors app.publish_margin_rule_version (COM-150) exactly.';

-- Two new axes on the quotation header (Prompt 153 §13/§24: approval binds one exact
-- quote version). approval_status defaults 'not_required' -- both a brand-new draft quotation
-- and every pre-existing row from before this migration land here, and only
-- app.submit_quotation ever moves it away from that default (never a backfill, this
-- migration's own header).
alter table app.quotations
  add column approval_status text not null default 'not_required',
  add column approval_request_id uuid references app.approval_requests (id),
  add column approval_rule_version_id uuid references app.quotation_approval_rules (id),
  add column approval_required_reasons text[] not null default array[]::text[];

alter table app.quotations
  add constraint quotations_approval_status_check check (approval_status in ('not_required', 'pending', 'approved', 'rejected'));

comment on column app.quotations.approval_status is
  'COM-153: the approval-routing outcome for this exact quotation version, independent of app.quotations.status (submission lifecycle). Set only by app.submit_quotation (initial routing) and app.decide_quotation_approval_step (final sync back from the Approval Engine).';

-- Read-only threshold evaluator (mirrors app.get_quotation_submission_readiness''s own
-- "reason codes only, never a dollar figure" discipline, COM-151) -- safe to expose
-- regardless of COM:View cost/COM:View selling price, even though it reads
-- margin_pct_snapshot/subtotal/discount/total internally to decide.
create function app.evaluate_quotation_approval_requirement(p_quotation_id uuid)
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
  select * into v_quotation from app.quotations where id = p_quotation_id;
  if not found then
    raise exception 'quotation_not_found: %', p_quotation_id using errcode = 'no_data_found';
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

comment on function app.evaluate_quotation_approval_requirement is
  'COM-153: the one deterministic, explainable "does this quotation need approval" decision (Prompt 153 §113: "Resolve ... threshold inputs ... server-side"). Margin uses the cheapest-sourced line (min across app.quotation_lines.margin_pct_snapshot); discount uses the header''s own effective discount_amount/subtotal_amount; value uses total_amount directly. Customer/service/organizational thresholds are this migration''s own disclosed boundary, not built here.';

-- Widens COM-151/152's app.submit_quotation -- resolves approval routing inside the same
-- transaction as the draft -> submitted transition (Prompt 153 §21's "Submitted quote
-- resolves the correct approvers" reads as one atomic action, not a second API call).
create or replace function app.submit_quotation(
  p_quotation_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.quotations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
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
  if not found then
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
  from app.evaluate_quotation_approval_requirement(p_quotation_id) e;

  if v_required then
    select cv.id into v_approval_config_version_id
    from app.config_versions cv
    join app.config_objects co on co.id = cv.config_object_id
    where co.config_type_code = 'approval' and co.tenant_id = v_quotation.tenant_id and co.scope_level = 'tenant' and cv.status = 'published';

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
  else
    update app.quotations
    set status = 'submitted', submitted_at = now(), submitted_by = p_actor_label,
        approval_status = 'approved', approval_request_id = null,
        approval_rule_version_id = v_rule_version_id, approval_required_reasons = v_approval_reasons,
        updated_at = now(), record_version = record_version + 1
    where id = p_quotation_id and record_version = p_expected_version
    returning * into v_quotation;
  end if;

  perform app.capture_audit_event(
    v_quotation.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_quotation',
    'app.quotations', v_quotation.id, 'success', null, null, to_jsonb(v_quotation)
  );

  return v_quotation;
end;
$$;

comment on function app.submit_quotation is
  'COM-151/152/153: draft -> submitted, gated by a real readiness check, then routed in the same transaction -- app.evaluate_quotation_approval_requirement decides whether a threshold is crossed; if not, the quotation is auto-approved (approval_status=approved, no request created); if so, app.request_approval opens a real routed request against the tenant''s published approval definition (approval_status=pending), failing closed with approval_definition_not_configured if none is published.';

-- The one domain-specific sync wrapper over the Approval Engine (this migration''s own
-- header: the engine itself cannot write back to app.quotations, being entity-agnostic).
-- Delegation/escalation need no such wrapper -- neither changes a request''s final outcome.
create function app.decide_quotation_approval_step(
  p_request_step_id uuid,
  p_decision text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_reason text default null
)
returns app.quotations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_step app.approval_request_steps;
  v_request app.approval_requests;
  v_updated_request app.approval_requests;
  v_quotation app.quotations;
begin
  select * into v_step from app.approval_request_steps where id = p_request_step_id;
  if not found then
    raise exception 'approval_step_not_found: no approval request step %', p_request_step_id
      using errcode = 'no_data_found';
  end if;

  select * into v_request from app.approval_requests where id = v_step.request_id;
  if v_request.entity_type <> 'quotation' or v_request.entity_id is null then
    raise exception 'not_a_quotation_approval: approval request % is not a quotation approval', v_request.id
      using errcode = 'check_violation';
  end if;

  -- The real decision, eligibility/self-approval/idempotency checks and all -- never
  -- re-implemented here (this migration's own header).
  perform app.decide_approval_step(p_request_step_id, p_decision, p_actor_auth_user_id, p_actor_label, p_reason);

  select * into v_updated_request from app.approval_requests where id = v_request.id;

  if v_updated_request.status = 'approved' then
    update app.quotations set approval_status = 'approved', updated_at = now(), record_version = record_version + 1
    where id = v_request.entity_id
    returning * into v_quotation;
  elsif v_updated_request.status = 'rejected' then
    update app.quotations set approval_status = 'rejected', updated_at = now(), record_version = record_version + 1
    where id = v_request.entity_id
    returning * into v_quotation;
  else
    -- Still pending (a sequential/threshold pattern with steps remaining) -- no sync needed.
    select * into v_quotation from app.quotations where id = v_request.entity_id;
  end if;

  return v_quotation;
end;
$$;

comment on function app.decide_quotation_approval_step is
  'COM-153: wraps app.decide_approval_step (PLT-123, unchanged) and syncs app.quotations.approval_status only once the bound request reaches a final state (approved/rejected) -- a request still mid-routing (e.g. sequential pattern, step 1 of 2) leaves the quotation at approval_status=pending. Like every prior quotation mutation (app.submit_quotation, app.add_quotation_line, ...), returns the raw app.quotations row -- masking is view-layer only (app.quotations_directory), the same established precedent, not a new discipline invented here.';

-- Widens COM-151's app.quotations_directory (COM-152 already appended 5 version columns;
-- this appends 4 more at the end -- the only shape CREATE OR REPLACE VIEW structurally
-- allows). approval_status/approval_request_id/approval_rule_version_id/
-- approval_required_reasons are reason codes/references only, never a dollar figure, so
-- they are visible to any record-scoped viewer regardless of COM:View cost/selling price
-- (the same app.get_quotation_submission_readiness precedent, COM-151).
create or replace view app.quotations_directory
as
select
  q.id,
  q.tenant_id,
  q.quote_number,
  q.opportunity_id,
  q.source_opportunity_version,
  q.prospect_id,
  q.contact_id,
  q.customer_snapshot,
  q.currency,
  q.validity_from,
  q.validity_to,
  q.terms,
  case when app.has_view_selling_price(q.tenant_id) then q.subtotal_amount else null end as subtotal_amount,
  case when app.has_view_selling_price(q.tenant_id) then q.discount_amount else null end as discount_amount,
  case when app.has_view_selling_price(q.tenant_id) then q.tax_amount else null end as tax_amount,
  case when app.has_view_selling_price(q.tenant_id) then q.total_amount else null end as total_amount,
  not app.has_view_selling_price(q.tenant_id) as sell_masked,
  q.status,
  q.cancel_reason,
  q.cloned_from_id,
  q.document_ref,
  q.submitted_at,
  q.submitted_by,
  q.owner_user_id,
  q.org_unit_id,
  q.record_version,
  q.created_by,
  q.created_at,
  q.updated_at,
  q.root_quotation_id,
  q.version_number,
  q.is_current,
  q.superseded_by_id,
  q.revision_reason,
  q.approval_status,
  q.approval_request_id,
  q.approval_rule_version_id,
  q.approval_required_reasons
from app.quotations q
where app.can_access_record(auth.uid(), q.tenant_id, q.owner_user_id, app.lead_record_scope_org_unit_ids(q.org_unit_id), null);

alter table app.quotation_approval_rules enable row level security;

-- Tenant-wide reference/policy data (mirrors app.margin_rule_versions'' own posture,
-- COM-150) -- never field-masked, direct RLS-scoped select for any active tenant member.
create policy quotation_approval_rules_select_scoped on app.quotation_approval_rules
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke of
-- PostgreSQL's PUBLIC-execute default, the standing per-migration convention since PLT-118.
revoke execute on all functions in schema app from public;

grant select on app.quotation_approval_rules to authenticated, service_role;
grant insert, update, delete on app.quotation_approval_rules to service_role;

grant select (approval_status, approval_request_id, approval_rule_version_id, approval_required_reasons) on app.quotations to authenticated;

grant execute on function app.create_quotation_approval_rule_version(uuid, numeric, numeric, numeric, uuid, text) to authenticated, service_role;
grant execute on function app.publish_quotation_approval_rule_version(uuid, integer, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.evaluate_quotation_approval_requirement(uuid) to authenticated, service_role;
grant execute on function app.submit_quotation(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.decide_quotation_approval_step(uuid, text, uuid, text, text) to authenticated, service_role;
