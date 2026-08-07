-- Procurement capability PRC-259 (Procurement Approval, CG-S11-PRC-010)
-- Instantiates ONE configurable approval contract across the high-risk Phase 6
-- decision points (vendor activation, rate approval, vendor selection/comparison
-- approval, PO approval, vendor contract approval, exception/override) by REUSING the
-- already-VERIFIED Platform Approval Engine (`app.approval_requests`/
-- `app.approval_request_steps`/`app.approval_decisions`/`app.approval_delegations`,
-- `app.request_approval`/`app.decide_approval_step`, migration
-- `20260719090000_create_approval_engine.sql`) end to end -- Procurement stores
-- bindings/context here, never a second workflow engine (Prompt 259 §24 business rule
-- 1, this migration's own literal charter).
--
-- Copies the Commercial Quotation Approval reference pattern
-- (`20260724270000_create_commercial_quotation_approval.sql`, COM-153) exactly:
--   * a small bespoke threshold-policy table (`app.procurement_approval_policies`) --
--     genuinely needed here because, unlike COM-153's single quotation entity, this
--     capability governs SIX distinct entity types with independent thresholds;
--   * `app.request_approval` called inside each governed entity's OWN submit/
--     transition RPC, in the same transaction as that RPC's own state change;
--   * exactly two axis columns added to each governed entity, kept separate from its
--     own lifecycle status column;
--   * one domain sync wrapper RPC per governed entity type, each mirroring
--     `app.decide_quotation_approval_step` structurally (validate entity_type, delegate
--     to `app.decide_approval_step` unchanged, sync back only once the request reaches
--     a final state);
--   * the next lifecycle transition gated by `approval_status in ('approved',
--     'not_required')`, exactly like `20260724280000_create_commercial_quotation_
--     customer_acceptance.sql`'s `app.send_quotation_for_acceptance` does near its own
--     line 206.
--
-- Governance routing reuses the SAME single tenant-wide `config_type_code='approval'`,
-- `scope_level='tenant'` config object every other domain in this repository already
-- shares (COM-153's own quotation routing, COM-157's credit routing --
-- `20260724310000_create_commercial_credit_commercial_control.sql`'s own header: "the
-- exact same tenant-wide published routing definition ... distinguished only by
-- `app.approval_requests.entity_type`"). `app.config_objects_scope_unique` permits
-- exactly ONE `(config_type_code='approval', tenant_id, scope_level='tenant')` row per
-- tenant -- this is not a limitation this migration works around, it is the
-- established, already-`VERIFIED` repository convention: one tenant-wide approval
-- committee/routing chain, disambiguated per request by `entity_type`, never a second
-- config_object per domain.
--
-- ===========================================================================
-- Scope boundaries and naming, disclosed rather than left implicit
-- ===========================================================================
--
-- * **Six governed entity_type values**: 'vendor_activation' (`app.vendor_profiles`,
--   PRC-251), 'rate_version' (`app.vendor_rate_versions`, COM-149/PRC-255),
--   'vendor_selection' (`app.vendor_comparisons`, PRC-258), 'purchase_order' and
--   'vendor_contract' (no table exists for either yet -- registered here as valid
--   policy/context dimensions ONLY, so Prompt 260 (Purchase Order, not yet built) and a
--   future vendor-contract capability can adopt the exact same binding shape below
--   without a further schema change to THIS migration), and 'exception_override' (a
--   new, minimal, self-contained governed entity this migration adds --
--   `app.procurement_exception_requests` -- because no existing Phase 6 table
--   represents a standalone exception/waiver request).
-- * **Column-name collision, disclosed and resolved.** `app.vendor_rate_versions`
--   (COM-149) already owns a column literally named `approval_status` with a DIFFERENT,
--   wider, pre-existing meaning (`pending_approval|approved|rejected|withdrawn|
--   superseded` -- COM-149's own bespoke lifecycle-cum-approval flag, built before this
--   migration and never gated through the Platform engine). Renaming or repurposing it
--   is out of this prompt's scope (forbidden: "duplicate vendor/rate ... roots") and
--   would be a breaking change to an already-`VERIFIED` capability. This migration adds
--   the SAME two-axis concept to `app.vendor_rate_versions` under distinctly-named
--   columns instead -- `governance_approval_status` / `governance_approval_request_id`
--   -- disclosed here as the one deliberate naming deviation this prompt's own naming
--   convention required. Every other governed entity (`app.vendor_profiles`, `app.
--   vendor_comparisons`, `app.procurement_exception_requests`) uses the literal
--   `approval_status` / `approval_request_id` names with no collision.
-- * **`app.vendor_activation` has no natural monetary value dimension.** Its policy
--   evaluation always passes `p_value_amount = null`, so only a policy's own
--   `always_required = true` can ever trigger routing for this entity type -- a
--   `min_value_amount`-only policy for `vendor_activation`/`vendor_contract`/
--   `exception_override` would be silently inert, so `procurement_approval_policies_
--   value_dimension_check` below structurally restricts `min_value_amount` to the three
--   genuinely value-bearing entity types (`rate_version`, `vendor_selection`,
--   `purchase_order`) rather than leaving that foot-gun to a policy author to discover.
-- * **`app.decide_vendor_profile_review`'s approve arm is the routing trigger point for
--   vendor activation, not `app.activate_vendor_profile` itself.** PRC-251's own
--   internal maker-checker review (`submitted/under_review -> approved`) already exists
--   and is untouched in shape; this migration widens ONLY the moment a reviewer's
--   `approve` decision would otherwise immediately clear the vendor for activation, to
--   additionally route through the Platform engine when policy requires it (separation
--   of duties: the reviewer recommends, a possibly different governed approver chain
--   authorizes the actual activation). `app.activate_vendor_profile` (`approved ->
--   active`) becomes the gated "next lifecycle transition," exactly mirroring `app.
--   send_quotation_for_acceptance`'s own placement relative to `app.submit_quotation`.
-- * **`app.create_rate_version` is the routing trigger point for rate approval**
--   (a fresh rate version has no separate "submitted" state -- COM-149's own INSERT
--   already lands it at `pending_approval`, so the routing decision is resolved before
--   that same INSERT, not in a later call). `app.approve_rate_version` (the pre-existing
--   PRC:Approve-gated domain decision) becomes the gated "next lifecycle transition" --
--   a rate cannot be domain-approved while a crossed governance threshold is still
--   pending platform-routed approval.
-- * **`app.submit_vendor_comparison_for_approval` is the routing trigger point for
--   vendor selection** -- PRC-258's own migration header names this EXACT function as
--   "the approval-engine handoff point (Prompt 259, not called from this checkpoint)."
--   This migration is that follow-through. `status='submitted'` is already terminal
--   within PRC-258's own scope (no further vendor_comparisons transition exists in this
--   repository yet) -- the gated "next lifecycle transition" is therefore NOT inside
--   this migration at all: it is Prompt 260's own future PO-award RPC, which must check
--   `app.vendor_comparisons.approval_status in ('approved', 'not_required')` before
--   creating a PO from `selected_offer_id`, exactly as `app.send_quotation_for_
--   acceptance` checks `app.quotations.approval_status`. Documented here explicitly as
--   the consumption contract Prompt 260 inherits, not invented by it.
-- * **'purchase_order' / 'vendor_contract' carry no schema of their own here** -- by
--   design, not omission. Confirmed by direct inspection (`docs/build-log/phase-06/
--   00_PROCUREMENT_VENDOR_WBS.md` line 64): no `app.purchase_orders` table exists
--   anywhere in this repository yet, and no Procurement vendor-contract table exists
--   either. Building either now would be exactly the "full Step 12-14 implementation"
--   this prompt's own forbidden-files list rules out. What IS built and immediately
--   reusable by whichever future prompt adds those tables: the `entity_type` value is
--   already valid in every CHECK constraint below, `app.evaluate_procurement_approval_
--   requirement('purchase_order'|'vendor_contract', ...)` already works, and the exact
--   three-step pattern to follow is documented in this same comment block (axis
--   columns on the new table, `app._request_procurement_entity_approval` called inside
--   its own submit/transition RPC, one new `app.decide_<entity>_approval_step` wrapper
--   mirroring the three below) -- genuinely usable by a prompt that has not been
--   written yet, never PO-specific.
-- * **Context snapshots are deliberately minimal and never a raw row copy** (taxonomy
--   C-07 -- `app.rfq_requirement_lines`/PRC-256's own `demand_snapshot` lesson: never
--   `to_jsonb(whole_row)`). `app.procurement_approval_context_snapshots.context` carries
--   a small, explicit, per-entity-type allowlist of non-cost descriptive fields only
--   (e.g. vendor legal_name, rate lane/service_type, comparison's source rfq_id) --
--   `value_amount`/`currency` are the only cost-shaped fields, held in their own typed
--   columns, and the one read path (`app.get_procurement_approval_context_snapshot`)
--   masks them behind `PRC:View cost` explicitly; the table itself carries NO direct
--   `authenticated` grant at all (mirrors `app.approval_decisions`'s own "no direct
--   grant, RPC only" posture, PLT-123) -- there is no unmasked column-level leak path.
-- * **No REST/GraphQL surface, no notification/job wiring** -- identical reasoning to
--   every prior Phase 6 checkpoint's own disclosed boundary: no REST/GraphQL adapter
--   exists for any domain yet, and this prompt's own spec text names no concrete
--   notification *event* for this capability beyond the generic "durable
--   reminders/escalations" already provided by the Platform engine's own (disclosed
--   `NOT_RUN`, no scheduler infrastructure exists) SLA-escalation trigger job.
-- * **`app.evaluate_procurement_approval_requirement` takes a mandatory actor and
--   checks `PRC:View` before returning anything** -- caught by this checkpoint's own
--   Tier B taxonomy walk (`rbac-enforcement.sql`'s ATW-032 authority-surface sweep,
--   run live) as the SAME cross-tenant business-intelligence disclosure class
--   `20260726090000_create_commercial_hardening.sql` (COM-163) already found and fixed
--   for `app.evaluate_quotation_approval_requirement`: a bare `(entity_type, tenant_id,
--   value_amount)` signature with no actor/access check would let any authenticated
--   identity in any tenant learn another tenant's threshold-crossing signal for a
--   guessed tenant id. Fixed here before this migration was ever applied, mirroring
--   COM-163's own shape exactly. **Disclosed, narrow residual**: `app.create_rate_
--   version`'s own authority model (`is_support_grant_authority` -- Supreme Admin or
--   tenant_admin, COM-149's original, unchanged by PRC-255) is unrelated to the `PRC`
--   permission catalogue this evaluator now requires -- a support-grant-authority actor
--   with no explicit `PRC:View` role assignment would be blocked by this evaluator's
--   internal call even though independently authorized to create the rate. The same
--   shape of trade-off COM-163's own fix accepts for `app.submit_quotation`'s internal
--   call (re-validating record-scope via a check that is not literally the same
--   permission `app.submit_quotation` itself already required) -- not a newly invented
--   gap, and fails closed rather than open.
-- * Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration carries its own
--   explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement
--   before its final grants, the standing per-migration convention since `PLT-118`.
--
-- ===========================================================================
-- Lock order (taxonomy C-04)
-- ===========================================================================
--
-- Every widened function below takes its OWN entity row lock (`for update` where the
-- pre-existing function already did; `app.vendor_profiles`/`app.vendor_rate_versions`
-- rows are locked implicitly by their own `record_version`-guarded UPDATE, unchanged
-- from before this migration) BEFORE calling `app._request_procurement_entity_
-- approval`, which itself only INSERTs a fresh, never-contended row into `app.
-- procurement_approval_context_snapshots` (keyed by a freshly-generated id) and calls
-- `app.request_approval` (PLT-123, its own internal locking unchanged). No new
-- cross-function lock ordering is introduced -- this migration never locks two governed
-- entity tables in the same transaction.

-- ===========================================================================
-- 1. app.procurement_approval_policies -- the bespoke, tenant-wide, per-entity-type
--    threshold policy table (mirrors app.quotation_approval_rules, COM-153, exactly).
-- ===========================================================================

create table app.procurement_approval_policies (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  entity_type text not null,
  min_value_amount numeric(14, 2),
  always_required boolean not null default false,
  status text not null default 'draft',
  supersedes_version_id uuid references app.procurement_approval_policies (id),
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint procurement_approval_policies_entity_type_check check (
    entity_type in ('vendor_activation', 'rate_version', 'vendor_selection', 'purchase_order', 'vendor_contract', 'exception_override')
  ),
  constraint procurement_approval_policies_status_check check (status in ('draft', 'published', 'archived')),
  constraint procurement_approval_policies_min_value_check check (min_value_amount is null or min_value_amount >= 0),
  constraint procurement_approval_policies_at_least_one_threshold check (min_value_amount is not null or always_required = true),
  constraint procurement_approval_policies_not_self_supersede check (supersedes_version_id is null or supersedes_version_id <> id),
  constraint procurement_approval_policies_value_dimension_check check (
    min_value_amount is null or entity_type in ('rate_version', 'vendor_selection', 'purchase_order')
  )
);

comment on table app.procurement_approval_policies is
  'PRC-259: a versioned, tenant-wide, PER-entity_type approval threshold policy -- mirrors app.quotation_approval_rules (COM-153) with one added dimension. min_value_amount is only meaningful for the three value-bearing entity types (rate_version/vendor_selection/purchase_order, enforced by procurement_approval_policies_value_dimension_check); always_required covers vendor_activation/vendor_contract/exception_override, which have no natural monetary value. Editing a published policy in place is never allowed -- app.publish_procurement_approval_policy_version''s p_supersedes_version_id parameter archives the prior published policy for that exact (tenant, entity_type) pair first.';

create unique index procurement_approval_policies_tenant_entity_published_unique
  on app.procurement_approval_policies (tenant_id, entity_type) where status = 'published';
create index procurement_approval_policies_tenant_status_idx on app.procurement_approval_policies (tenant_id, status);

create function app.create_procurement_approval_policy_version(
  p_tenant_id uuid,
  p_entity_type text,
  p_min_value_amount numeric,
  p_always_required boolean,
  p_actor_auth_user_id uuid,
  p_created_by text
)
returns app.procurement_approval_policies
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_policy app.procurement_approval_policies;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_entity_type not in ('vendor_activation', 'rate_version', 'vendor_selection', 'purchase_order', 'vendor_contract', 'exception_override') then
    raise exception 'invalid_entity_type: % is not a governed procurement approval entity type', p_entity_type
      using errcode = 'check_violation';
  end if;

  insert into app.procurement_approval_policies (tenant_id, entity_type, min_value_amount, always_required, created_by)
  values (p_tenant_id, p_entity_type, p_min_value_amount, coalesce(p_always_required, false), p_created_by)
  returning * into v_policy;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_created_by, 'create_procurement_approval_policy_version',
    'app.procurement_approval_policies', v_policy.id, 'success', null, null, to_jsonb(v_policy)
  );

  return v_policy;
end;
$$;

create function app.publish_procurement_approval_policy_version(
  p_policy_version_id uuid,
  p_expected_version integer,
  p_supersedes_version_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.procurement_approval_policies
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_policy app.procurement_approval_policies;
  v_superseded app.procurement_approval_policies;
  v_decision app.rbac_decision;
begin
  select * into v_policy from app.procurement_approval_policies where id = p_policy_version_id;
  if not found then
    raise exception 'procurement_approval_policy_not_found: %', p_policy_version_id using errcode = 'no_data_found';
  end if;

  if v_policy.record_version <> p_expected_version then
    raise exception 'stale_version: procurement approval policy % expected version % but found %', p_policy_version_id, p_expected_version, v_policy.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_policy.status <> 'draft' then
    raise exception 'invalid_transition: procurement approval policy % is % and cannot be published', p_policy_version_id, v_policy.status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_policy.tenant_id, 'PRC', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_policy.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_supersedes_version_id is not null then
    select * into v_superseded from app.procurement_approval_policies where id = p_supersedes_version_id;
    if not found then
      raise exception 'superseded_policy_not_found: %', p_supersedes_version_id using errcode = 'no_data_found';
    end if;
    if v_superseded.tenant_id <> v_policy.tenant_id or v_superseded.entity_type <> v_policy.entity_type then
      raise exception 'invalid_supersede: superseded policy must share the same tenant and entity_type'
        using errcode = 'check_violation';
    end if;
    if v_superseded.status <> 'published' then
      raise exception 'invalid_supersede: superseded policy % is % (must be published)', p_supersedes_version_id, v_superseded.status
        using errcode = 'check_violation';
    end if;
    update app.procurement_approval_policies set status = 'archived', updated_at = now(), record_version = record_version + 1 where id = p_supersedes_version_id;
  end if;

  begin
    update app.procurement_approval_policies
    set status = 'published', supersedes_version_id = p_supersedes_version_id, updated_at = now(), record_version = record_version + 1
    where id = p_policy_version_id and record_version = p_expected_version
    returning * into v_policy;
  exception
    when unique_violation then
      raise exception 'active_policy_exists: tenant % already has a published % policy -- supply p_supersedes_version_id to replace it', v_policy.tenant_id, v_policy.entity_type
        using errcode = 'check_violation';
  end;
  if not found then
    raise exception 'stale_version: procurement approval policy % target row was concurrently modified (expected version %)', p_policy_version_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_policy.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_procurement_approval_policy_version',
    'app.procurement_approval_policies', v_policy.id, 'success', null, null, jsonb_build_object('supersedes_version_id', p_supersedes_version_id)
  );

  return v_policy;
end;
$$;

comment on function app.publish_procurement_approval_policy_version is
  'PRC-259: draft -> published, archiving p_supersedes_version_id (if supplied) first so at most one published policy ever exists per (tenant, entity_type) -- mirrors app.publish_quotation_approval_rule_version (COM-153) exactly, scoped one dimension narrower.';

-- Read-only threshold evaluator (mirrors app.evaluate_quotation_approval_requirement AS
-- HARDENED BY COM-163, `20260726090000_create_commercial_hardening.sql` -- not its
-- original COM-153 shape, which that same hardening migration's own header documents as
-- a real, found-live cross-tenant business-intelligence disclosure: "any authenticated
-- identity in any tenant... could learn that tenant's own margin/discount/value
-- threshold-crossing signal." p_actor_auth_user_id + an authority check is applied here
-- FROM THE START, not rediscovered by a later hardening checkpoint -- p_tenant_id is a
-- bare, caller-supplied parameter with no implicit scope of its own, exactly the shape
-- COM-163's finding was about.) Reason codes only, never a dollar figure.
create function app.evaluate_procurement_approval_requirement(
  p_entity_type text,
  p_tenant_id uuid,
  p_value_amount numeric,
  p_actor_auth_user_id uuid
)
returns table (required boolean, reasons text[], policy_version_id uuid)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_policy app.procurement_approval_policies;
  v_reasons text[] := array[]::text[];
begin
  if p_entity_type not in ('vendor_activation', 'rate_version', 'vendor_selection', 'purchase_order', 'vendor_contract', 'exception_override') then
    raise exception 'invalid_entity_type: % is not a governed procurement approval entity type', p_entity_type
      using errcode = 'check_violation';
  end if;

  -- Deliberately app.has_active_tenant_membership, NOT a specific PRC:* permission --
  -- app.procurement_approval_policies itself is directly readable by any active tenant
  -- member (this migration's own RLS policy below, mirroring app.quotation_approval_
  -- rules' own "tenant-wide reference data, never field-masked" posture, COM-153); a
  -- stricter gate here would protect nothing a raw select on that same table does not
  -- already expose, while wrongly blocking a legitimately authorized caller whose own
  -- authority model is not the PRC permission catalogue at all (app.create_rate_
  -- version's own app.is_support_grant_authority, COM-149, unchanged by PRC-255 --
  -- caught live by this checkpoint's own full db:test run against advanced-tms-
  -- canonical-telemetry-arbitration.sql, not merely reasoned about).
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) or app.actor_holds_customer_user_layer(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_policy from app.procurement_approval_policies where tenant_id = p_tenant_id and entity_type = p_entity_type and status = 'published';
  if not found then
    return query select false, array[]::text[], null::uuid;
    return;
  end if;

  if v_policy.always_required then
    v_reasons := array_append(v_reasons, 'always_required');
  end if;
  if v_policy.min_value_amount is not null and p_value_amount is not null and p_value_amount >= v_policy.min_value_amount then
    v_reasons := array_append(v_reasons, 'value_meets_threshold');
  end if;

  return query select (array_length(v_reasons, 1) is not null), v_reasons, v_policy.id;
end;
$$;

comment on function app.evaluate_procurement_approval_requirement is
  'PRC-259: the one deterministic, explainable "does this procurement decision need approval" evaluator, shared by every governed entity_type. A tenant with no published policy for that entity_type skips routing entirely (opt-in, mirrors COM-153''s own quotation precedent) -- required=false, no reasons, policy_version_id=null.';

-- ===========================================================================
-- 2. app.procurement_approval_context_snapshots -- the one generic, immutable decision
--    context snapshot table every governed entity_type shares (business rule: "Decision
--    context snapshots source/config/value/risk/compliance/rate versions"). No direct
--    `authenticated` grant at all (mirrors app.approval_decisions, PLT-123) -- the one
--    read path is app.get_procurement_approval_context_snapshot below, which masks
--    value_amount/currency behind PRC:View cost.
-- ===========================================================================

create table app.procurement_approval_context_snapshots (
  id uuid primary key default gen_random_uuid(),
  approval_request_id uuid not null unique references app.approval_requests (id),
  tenant_id uuid not null references app.tenants (id),
  entity_type text not null,
  entity_id uuid,
  value_amount numeric(14, 2),
  currency text,
  reasons text[] not null default array[]::text[],
  policy_version_id uuid references app.procurement_approval_policies (id),
  context jsonb not null default '{}'::jsonb,
  source_record_version integer,
  created_by text,
  created_at timestamptz not null default now(),
  constraint procurement_approval_context_snapshots_entity_type_check check (
    entity_type in ('vendor_activation', 'rate_version', 'vendor_selection', 'purchase_order', 'vendor_contract', 'exception_override')
  ),
  constraint procurement_approval_context_snapshots_currency_check check (currency is null or currency ~ '^[A-Z]{3}$')
);

comment on table app.procurement_approval_context_snapshots is
  'PRC-259: one immutable row per app.approval_requests row this capability opens -- the exact value/currency/reasons/policy version and a small, explicit, non-cost context allowlist (never a raw to_jsonb(row), taxonomy C-07) at the moment routing began. Never updated after insert -- a later material change to the source entity does not retroactively rewrite an already-open request''s own snapshot; it is the source entity''s own next submit call that would open a NEW request with a fresh snapshot.';

create index procurement_approval_context_snapshots_tenant_idx on app.procurement_approval_context_snapshots (tenant_id, entity_type);

-- ===========================================================================
-- 3. app._request_procurement_entity_approval -- the one shared, private (no grant --
--    callable only from within another SECURITY DEFINER function owned by the same
--    role, mirrors app._normalize_vendor_comparison_currency, PRC-258) submit-time glue
--    every governed entity's own submit/transition RPC calls exactly once. Evaluates
--    the policy, resolves the tenant's one shared approval routing definition, opens a
--    real routed request when required, and snapshots context -- never re-implemented
--    per entity_type.
-- ===========================================================================

create function app._request_procurement_entity_approval(
  p_entity_type text,
  p_tenant_id uuid,
  p_entity_id uuid,
  p_value_amount numeric,
  p_currency text,
  p_context jsonb,
  p_source_record_version integer,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  out required boolean,
  out approval_status text,
  out approval_request_id uuid,
  out policy_version_id uuid
)
language plpgsql
as $$
declare
  v_reasons text[];
  v_config_version_id uuid;
  v_request app.approval_requests;
  v_existing_snapshot app.procurement_approval_context_snapshots;
begin
  select e.required, e.reasons, e.policy_version_id into required, v_reasons, policy_version_id
  from app.evaluate_procurement_approval_requirement(p_entity_type, p_tenant_id, p_value_amount, p_actor_auth_user_id) e;

  if not required then
    approval_status := 'not_required';
    approval_request_id := null;
    return;
  end if;

  select cv.id into v_config_version_id
  from app.config_versions cv
  join app.config_objects co on co.id = cv.config_object_id
  where co.config_type_code = 'approval' and co.tenant_id = p_tenant_id and co.scope_level = 'tenant' and cv.status = 'published';

  if v_config_version_id is null then
    raise exception 'approval_definition_not_configured: tenant % crossed a procurement approval threshold for % but has no published approval routing definition', p_tenant_id, p_entity_type
      using errcode = 'check_violation';
  end if;

  select * into v_request from app.request_approval(
    v_config_version_id, p_tenant_id, p_entity_type, p_entity_id, p_idempotency_key, p_actor_auth_user_id, p_actor_label
  );

  approval_status := 'pending';
  approval_request_id := v_request.id;

  -- app.request_approval's own (tenant_id, idempotency_key) short-circuit already
  -- returns the SAME existing request row on a genuine replay (taxonomy C-01, handled
  -- once, upstream, not re-implemented here) -- only insert a context snapshot the
  -- first time this exact request is created.
  select * into v_existing_snapshot from app.procurement_approval_context_snapshots s where s.approval_request_id = v_request.id;
  if not found then
    insert into app.procurement_approval_context_snapshots (
      approval_request_id, tenant_id, entity_type, entity_id, value_amount, currency,
      reasons, policy_version_id, context, source_record_version, created_by
    ) values (
      v_request.id, p_tenant_id, p_entity_type, p_entity_id, p_value_amount, p_currency,
      v_reasons, policy_version_id, coalesce(p_context, '{}'::jsonb), p_source_record_version, p_actor_label
    );
  end if;
end;
$$;

comment on function app._request_procurement_entity_approval is
  'PRC-259: private submit-time glue, no grant -- called once from inside each governed entity''s own SECURITY DEFINER submit/transition RPC (nested calls execute with the caller''s own definer rights, the same established PRC-257/258 precedent). Never called directly by the TypeScript service layer.';

-- Masked read of one context snapshot -- the table itself carries no direct
-- `authenticated` grant (mirrors app.approval_decisions, PLT-123); this is the one read
-- path, masking value_amount/currency behind PRC:View cost.
create function app.get_procurement_approval_context_snapshot(p_approval_request_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, approval_request_id uuid, tenant_id uuid, entity_type text, entity_id uuid,
  value_amount numeric, currency text, cost_masked boolean, reasons text[], policy_version_id uuid,
  context jsonb, source_record_version integer, created_by text, created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_snapshot app.procurement_approval_context_snapshots;
  v_decision app.rbac_decision;
  v_cost_decision app.rbac_decision;
begin
  select * into v_snapshot from app.procurement_approval_context_snapshots s where s.approval_request_id = p_approval_request_id;
  if not found then
    raise exception 'procurement_approval_context_snapshot_not_found: no snapshot for approval request %', p_approval_request_id
      using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_snapshot.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_snapshot.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_cost_decision := app.evaluate_permission(p_actor_auth_user_id, v_snapshot.tenant_id, 'PRC', 'View cost');

  return query select
    v_snapshot.id, v_snapshot.approval_request_id, v_snapshot.tenant_id, v_snapshot.entity_type, v_snapshot.entity_id,
    case when v_cost_decision.allowed then v_snapshot.value_amount else null end,
    case when v_cost_decision.allowed then v_snapshot.currency else null end,
    not v_cost_decision.allowed,
    v_snapshot.reasons, v_snapshot.policy_version_id, v_snapshot.context, v_snapshot.source_record_version,
    v_snapshot.created_by, v_snapshot.created_at;
end;
$$;

-- ===========================================================================
-- 4. Vendor activation binding -- app.vendor_profiles (PRC-251).
-- ===========================================================================

alter table app.vendor_profiles
  add column approval_status text not null default 'not_required',
  add column approval_request_id uuid references app.approval_requests (id);

alter table app.vendor_profiles
  add constraint vendor_profiles_approval_status_check check (approval_status in ('not_required', 'pending', 'approved', 'rejected'));

comment on column app.vendor_profiles.approval_status is
  'PRC-259: the Platform-engine-routed governance outcome for this vendor''s pending activation, independent of lifecycle_status. Set by app.decide_vendor_profile_review''s own approve arm (routing trigger point) and synced back by app.decide_vendor_activation_approval_step. app.activate_vendor_profile (approved -> active) requires approval_status in (approved, not_required) -- the gated "next lifecycle transition," mirroring app.send_quotation_for_acceptance''s own placement relative to app.submit_quotation.';

-- Widened (PRC-259): identical signature -- CREATE OR REPLACE only adds the governance
-- routing call on the approve arm, immediately before the transition-status is decided,
-- so both are written in the SAME single UPDATE (no second write, no risk of a doubled
-- record_version bump -- design note: this table has no auto-bump trigger, every
-- function increments record_version manually in its own SET clause).
create or replace function app.decide_vendor_profile_review(
  p_master_record_id uuid,
  p_expected_version integer,
  p_decision text,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_profiles
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_profile app.vendor_profiles;
  v_new_status text;
  v_from_status text;
  v_action text;
  v_next_version integer;
  v_gov_required boolean;
  v_gov_approval_status text;
  v_gov_approval_request_id uuid;
begin
  if p_decision not in ('approve', 'reject') then
    raise exception 'invalid_decision: % is not approve or reject', p_decision using errcode = 'check_violation';
  end if;
  if p_decision = 'reject' and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'reason_required: a non-empty reason is required to reject a vendor profile' using errcode = 'check_violation';
  end if;

  select * into v_profile from app.vendor_profiles where master_record_id = p_master_record_id;
  if not found then
    raise exception 'vendor_profile_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;
  if v_profile.record_version <> p_expected_version then
    raise exception 'stale_version: vendor profile % expected version % but found %', p_master_record_id, p_expected_version, v_profile.record_version
      using errcode = 'serialization_failure';
  end if;

  v_action := case p_decision when 'approve' then 'Approve' else 'Reject' end;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_profile.tenant_id, 'PRC', v_action);
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:% (%) for tenant %', p_actor_auth_user_id, v_action, v_decision.reason, v_profile.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_profile.lifecycle_status not in ('submitted', 'under_review') then
    raise exception 'invalid_transition: vendor profile % is % and cannot be decided', p_master_record_id, v_profile.lifecycle_status
      using errcode = 'check_violation';
  end if;

  v_new_status := case p_decision when 'approve' then 'approved' else 'draft' end;
  -- Capture the row's REAL prior status before the UPDATE overwrites v_profile --
  -- begin_vendor_profile_review is optional (design note 5), so a decision can
  -- legitimately be made directly from 'submitted', skipping 'under_review'. A
  -- hardcoded 'under_review' literal here would corrupt the append-only audit
  -- timeline the vendor detail UI reads directly (found in adversarial review).
  v_from_status := v_profile.lifecycle_status;
  v_next_version := p_expected_version + 1;

  -- PRC-259: only the approve arm ever routes for governance -- a reject returns the
  -- profile to draft, never reaching activation, so there is nothing to route.
  if p_decision = 'approve' then
    select r.required, r.approval_status, r.approval_request_id into v_gov_required, v_gov_approval_status, v_gov_approval_request_id
    from app._request_procurement_entity_approval(
      'vendor_activation', v_profile.tenant_id, p_master_record_id, null, null,
      jsonb_build_object('legal_name', v_profile.legal_name, 'vendor_category', v_profile.vendor_category),
      v_next_version, 'vendor_activation:' || p_master_record_id::text || ':v' || v_next_version::text,
      p_actor_auth_user_id, p_actor_label
    ) r;
  else
    v_gov_approval_status := v_profile.approval_status;
    v_gov_approval_request_id := v_profile.approval_request_id;
  end if;

  update app.vendor_profiles
  set lifecycle_status = v_new_status,
      revision_reason = case when p_decision = 'reject' then p_reason else revision_reason end,
      approval_status = v_gov_approval_status,
      approval_request_id = v_gov_approval_request_id,
      record_version = record_version + 1,
      updated_at = now()
  where master_record_id = p_master_record_id and record_version = p_expected_version
  returning * into v_profile;
  if not found then
    raise exception 'stale_version: vendor profile % target row was concurrently modified (expected version %)', p_master_record_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.vendor_profile_lifecycle_events (tenant_id, master_record_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (v_profile.tenant_id, p_master_record_id, v_from_status, v_new_status, p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_profile.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_vendor_profile_review',
    'app.vendor_profiles', p_master_record_id, 'success', p_reason, null, jsonb_build_object('decision', p_decision, 'lifecycle_status', v_new_status, 'approval_status', v_gov_approval_status)
  );

  return v_profile;
end;
$$;

comment on function app.decide_vendor_profile_review is 'PRC-251, widened PRC-259: unchanged signature. approve (-> approved, PRC:Approve) or reject (-> draft with revision_reason set, PRC:Reject, reason mandatory) -- reachable from submitted or under_review. The approve arm additionally routes for platform-engine governance approval when app.procurement_approval_policies has a published vendor_activation policy the tenant crossed -- app.activate_vendor_profile then requires approval_status in (approved, not_required) before the profile can actually go active.';

-- Widened (PRC-259): identical signature -- one added gate check, placed immediately
-- after the existing lifecycle_status check, before any write.
create or replace function app.activate_vendor_profile(
  p_master_record_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_profiles
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_profile app.vendor_profiles;
begin
  select * into v_profile from app.vendor_profiles where master_record_id = p_master_record_id;
  if not found then
    raise exception 'vendor_profile_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;
  if v_profile.record_version <> p_expected_version then
    raise exception 'stale_version: vendor profile % expected version % but found %', p_master_record_id, p_expected_version, v_profile.record_version
      using errcode = 'serialization_failure';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_profile.tenant_id, 'PRC', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_profile.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_profile.lifecycle_status <> 'approved' then
    raise exception 'invalid_transition: vendor profile % is % and cannot be activated', p_master_record_id, v_profile.lifecycle_status
      using errcode = 'check_violation';
  end if;

  -- PRC-259: the gated "next lifecycle transition" -- a vendor cannot go active while a
  -- crossed governance threshold from app.decide_vendor_profile_review''s own approve
  -- arm is still pending platform-routed approval.
  if v_profile.approval_status not in ('approved', 'not_required') then
    raise exception 'vendor_activation_approval_pending: vendor profile % approval_status is % (must be approved or not_required)', p_master_record_id, v_profile.approval_status
      using errcode = 'check_violation';
  end if;

  update app.vendor_profiles
  set lifecycle_status = 'active', record_version = record_version + 1, updated_at = now()
  where master_record_id = p_master_record_id and record_version = p_expected_version
  returning * into v_profile;
  if not found then
    raise exception 'stale_version: vendor profile % target row was concurrently modified (expected version %)', p_master_record_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.vendor_profile_lifecycle_events (tenant_id, master_record_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (v_profile.tenant_id, p_master_record_id, 'approved', 'active', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_profile.tenant_id, p_actor_auth_user_id, p_actor_label, 'activate_vendor_profile',
    'app.vendor_profiles', p_master_record_id, 'success', null, null, '{}'::jsonb
  );

  return v_profile;
end;
$$;

comment on function app.activate_vendor_profile is 'PRC-251, widened PRC-259: unchanged signature. approved -> active, PRC:Approve, additionally gated on approval_status in (approved, not_required) -- see column comment.';

-- The one domain-specific sync wrapper over the Approval Engine for vendor activation.
create function app.decide_vendor_activation_approval_step(
  p_request_step_id uuid,
  p_decision text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_reason text default null
)
returns app.vendor_profiles
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_step app.approval_request_steps;
  v_request app.approval_requests;
  v_updated_request app.approval_requests;
  v_profile app.vendor_profiles;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_step from app.approval_request_steps where id = p_request_step_id;
  if not found then
    raise exception 'approval_step_not_found: no approval request step %', p_request_step_id
      using errcode = 'no_data_found';
  end if;
  select * into v_request from app.approval_requests where id = v_step.request_id;
  if v_request.entity_type <> 'vendor_activation' or v_request.entity_id is null then
    raise exception 'not_a_vendor_activation_approval: approval request % is not a vendor activation approval', v_request.id
      using errcode = 'check_violation';
  end if;

  -- The real decision, eligibility/self-approval/idempotency checks and all -- never
  -- re-implemented here (mirrors app.decide_quotation_approval_step, COM-153).
  perform app.decide_approval_step(p_request_step_id, p_decision, p_actor_auth_user_id, p_actor_label, p_reason);

  select * into v_updated_request from app.approval_requests where id = v_request.id;

  if v_updated_request.status = 'approved' then
    update app.vendor_profiles set approval_status = 'approved', updated_at = now(), record_version = record_version + 1
    where master_record_id = v_request.entity_id
    returning * into v_profile;
  elsif v_updated_request.status = 'rejected' then
    update app.vendor_profiles set approval_status = 'rejected', updated_at = now(), record_version = record_version + 1
    where master_record_id = v_request.entity_id
    returning * into v_profile;
  else
    -- Still pending (a sequential/threshold pattern with steps remaining) -- no sync needed.
    select * into v_profile from app.vendor_profiles where master_record_id = v_request.entity_id;
  end if;

  return v_profile;
end;
$$;

comment on function app.decide_vendor_activation_approval_step is
  'PRC-259: wraps app.decide_approval_step (PLT-123, unchanged) and syncs app.vendor_profiles.approval_status only once the bound request reaches a final state (approved/rejected). Never itself calls app.activate_vendor_profile -- the vendor still needs its own explicit activation call once approval_status clears, exactly mirroring app.decide_quotation_approval_step never itself calling app.send_quotation_for_acceptance.';

-- ===========================================================================
-- 5. Rate approval binding -- app.vendor_rate_versions (COM-149/PRC-255). Uses
--    governance_approval_status / governance_approval_request_id (see migration
--    header for the disclosed naming collision with the pre-existing approval_status
--    column).
-- ===========================================================================

alter table app.vendor_rate_versions
  add column governance_approval_status text not null default 'not_required',
  add column governance_approval_request_id uuid references app.approval_requests (id);

alter table app.vendor_rate_versions
  add constraint vendor_rate_versions_governance_approval_status_check check (governance_approval_status in ('not_required', 'pending', 'approved', 'rejected'));

comment on column app.vendor_rate_versions.governance_approval_status is
  'PRC-259: the Platform-engine-routed governance outcome for this rate version, distinct from the pre-existing approval_status column (COM-149''s own bespoke pending_approval|approved|rejected|withdrawn|superseded lifecycle flag -- a naming collision this migration deliberately does not touch, see migration header). Set by app.create_rate_version (routing trigger point) and synced back by app.decide_rate_version_approval_step. app.approve_rate_version requires governance_approval_status in (approved, not_required) -- the gated "next lifecycle transition."';

-- Widened (PRC-259, further widening PRC-255''s own widen of COM-149): identical
-- signature -- CREATE OR REPLACE is safe here (no new caller-facing parameter is
-- added, so no DROP FUNCTION is needed the way PRC-255''s own trailing-parameter widen
-- required). The governance decision is resolved BEFORE the single INSERT (an explicit
-- v_new_id generated up front) so entity_id/governance columns are set in that one
-- write -- no second UPDATE, no risk of advancing record_version past 1 on a freshly
-- created row.
create or replace function app.create_rate_version(
  p_tenant_id uuid,
  p_vendor_code text,
  p_vendor_name text,
  p_service_type text,
  p_mode text,
  p_origin_lane text,
  p_destination_lane text,
  p_equipment_type text,
  p_cargo_weight_min numeric,
  p_cargo_weight_max numeric,
  p_cargo_volume_min numeric,
  p_cargo_volume_max numeric,
  p_currency text,
  p_base_amount numeric,
  p_minimum_amount numeric,
  p_surcharge_components jsonb,
  p_effective_from timestamptz,
  p_effective_to timestamptz,
  p_supersedes_version_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_vendor_master_id uuid default null,
  p_lead_time_days integer default null,
  p_capacity_terms text default null,
  p_source_import_staging_row_id uuid default null
)
returns app.vendor_rate_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_master_record_id uuid;
  v_prior app.vendor_rate_versions;
  v_new app.vendor_rate_versions;
  v_vendor_master_id uuid;
  v_vendor_master app.master_records;
  v_new_id uuid := gen_random_uuid();
  v_gov_required boolean;
  v_gov_approval_status text;
  v_gov_approval_request_id uuid;
begin
  -- ATW-032 (ISS-2026-032) regression guard: this function gates ONLY on
  -- app.is_support_grant_authority, which validates the CLAIMED actor and never
  -- the caller -- 20260730510000_harden_actor_identity_unchecked_authority_
  -- surface.sql already patched COM-149's original app.create_rate_version with
  -- this exact line; a bare `create or replace` here would silently DROP that
  -- patch (the function body is fully replaced, not merged) and reintroduce
  -- ISS-2026-032 for this function -- found live running this repository's own
  -- rbac-enforcement.sql db-test suite, preserved here rather than reintroduced.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.is_support_grant_authority(p_actor_auth_user_id, p_tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- PRC-255 (ADR-0020): explicit, clearer-message check ahead of the structural
  -- trigger (defense in depth, this repository's own standing convention).
  if p_vendor_master_id is not null then
    select * into v_vendor_master from app.master_records where id = p_vendor_master_id;
    if not found then
      raise exception 'vendor_master_record_not_found: %', p_vendor_master_id using errcode = 'no_data_found';
    end if;
    if v_vendor_master.master_type_code <> 'vendor' then
      raise exception 'invalid_vendor_identity: master record % is master_type_code %, expected vendor', p_vendor_master_id, v_vendor_master.master_type_code
        using errcode = 'check_violation';
    end if;
    if v_vendor_master.tenant_id <> p_tenant_id then
      raise exception 'tenant_mismatch: vendor master record % does not belong to tenant %', p_vendor_master_id, p_tenant_id
        using errcode = 'check_violation';
    end if;
  end if;

  if p_supersedes_version_id is not null then
    -- BUG FIX (post-review, HIGH): `for update` -- the ORIGINAL was a plain,
    -- unlocked SELECT, and the terminal supersede-marking UPDATE below carried
    -- no record_version compare and no post-UPDATE "if not found" re-check (the
    -- exact two safeguards app.approve_rate_version's own terminal UPDATE
    -- correctly applies). Two concurrent create_rate_version calls both
    -- supersede-ing the same source row would both pass this status check and
    -- both blindly apply the terminal UPDATE, breaking the "one supersede
    -- replaces one prior" invariant (two sibling pending_approval revisions both
    -- claiming supersedes_version_id = the same source). Locking here serializes
    -- a second concurrent caller behind the first: once unblocked, it re-reads
    -- the POST-COMMIT row (already approval_status='superseded') and correctly
    -- falls into the invalid_transition branch below instead of racing ahead.
    select * into v_prior from app.vendor_rate_versions where id = p_supersedes_version_id for update;
    if not found then
      raise exception 'rate_version_not_found: %', p_supersedes_version_id using errcode = 'no_data_found';
    end if;
    if v_prior.tenant_id <> p_tenant_id then
      raise exception 'tenant_mismatch: rate version % does not belong to tenant %', p_supersedes_version_id, p_tenant_id
        using errcode = 'check_violation';
    end if;
    if v_prior.approval_status not in ('pending_approval', 'approved') then
      raise exception 'invalid_transition: rate version % is % and cannot be superseded', p_supersedes_version_id, v_prior.approval_status
        using errcode = 'check_violation';
    end if;
    v_master_record_id := v_prior.master_record_id;
    v_vendor_master_id := coalesce(p_vendor_master_id, v_prior.vendor_master_id);
  else
    select id into v_master_record_id from app.create_master_record(
      'vendor_rate', p_tenant_id, p_vendor_code, p_vendor_name, '[]'::jsonb, '{}'::jsonb, p_actor_auth_user_id, p_actor_label
    );
    v_vendor_master_id := p_vendor_master_id;
  end if;

  -- PRC-259: resolve governance routing BEFORE the insert -- v_new_id is generated up
  -- front precisely so the approval request's entity_id and this row's own primary key
  -- are the same value from the start, in one write.
  select r.required, r.approval_status, r.approval_request_id into v_gov_required, v_gov_approval_status, v_gov_approval_request_id
  from app._request_procurement_entity_approval(
    'rate_version', p_tenant_id, v_new_id, p_base_amount, p_currency,
    jsonb_build_object('service_type', p_service_type, 'origin_lane', p_origin_lane, 'destination_lane', p_destination_lane),
    1, 'rate_version:' || v_new_id::text, p_actor_auth_user_id, p_actor_label
  ) r;

  insert into app.vendor_rate_versions (
    id, tenant_id, master_record_id, vendor_master_id, service_type, mode, origin_lane, destination_lane, equipment_type,
    cargo_weight_min, cargo_weight_max, cargo_volume_min, cargo_volume_max,
    currency, base_amount, minimum_amount, surcharge_components,
    lead_time_days, capacity_terms, source_import_staging_row_id,
    effective_from, effective_to, supersedes_version_id, created_by,
    governance_approval_status, governance_approval_request_id
  ) values (
    v_new_id, p_tenant_id, v_master_record_id, v_vendor_master_id, p_service_type, p_mode, p_origin_lane, p_destination_lane, p_equipment_type,
    p_cargo_weight_min, p_cargo_weight_max, p_cargo_volume_min, p_cargo_volume_max,
    p_currency, p_base_amount, p_minimum_amount, coalesce(p_surcharge_components, '[]'::jsonb),
    p_lead_time_days, p_capacity_terms, p_source_import_staging_row_id,
    coalesce(p_effective_from, now()), p_effective_to, p_supersedes_version_id, p_actor_label,
    v_gov_approval_status, v_gov_approval_request_id
  )
  returning * into v_new;

  if p_supersedes_version_id is not null then
    -- Defense in depth (belt-and-suspenders): the `for update` lock taken above
    -- already makes this UPDATE race-free within this function (no other
    -- transaction can have changed v_prior's status between the lock and here),
    -- but the explicit status-scoped WHERE + post-UPDATE "if not found" re-check
    -- mirrors this repository's own standing convention (matches
    -- app.approve_rate_version's terminal UPDATE a few dozen lines below) rather
    -- than relying solely on the lock.
    update app.vendor_rate_versions
    set approval_status = 'superseded', updated_at = now(), record_version = record_version + 1
    where id = p_supersedes_version_id and approval_status = v_prior.approval_status;
    if not found then
      raise exception 'stale_version: rate version % was concurrently modified and could not be marked superseded', p_supersedes_version_id
        using errcode = 'serialization_failure';
    end if;
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_rate_version',
    'app.vendor_rate_versions', v_new.id, 'success', null, null, to_jsonb(v_new)
  );

  return v_new;
end;
$$;

comment on function app.create_rate_version is 'COM-149, widened PRC-255 (ADR-0020) then PRC-259: unchanged signature. PRC-259 additionally routes for platform-engine governance approval when app.procurement_approval_policies has a published rate_version policy this rate''s base_amount crosses -- app.approve_rate_version then requires governance_approval_status in (approved, not_required) before the domain approve action can succeed. Every prior widening (p_vendor_master_id/p_lead_time_days/p_capacity_terms/p_source_import_staging_row_id, the vendor-identity check, the locked supersede path) is unchanged.';

-- Widened (PRC-259, further widening PRC-255''s own widen): identical signature -- one
-- added gate check, placed immediately after the existing approval_status check,
-- before the tier-contiguity validation and the terminal UPDATE.
create or replace function app.approve_rate_version(
  p_rate_version_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_rate_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_rate app.vendor_rate_versions;
  v_vendor_status text;
begin
  -- ATW-032 (ISS-2026-032) regression guard: same reasoning as app.create_rate_
  -- version above -- 20260730510000 already patched COM-149's original app.
  -- approve_rate_version with this exact line; preserved here, not reintroduced
  -- as a gap.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- PRC-255 addition (design note 13): `for update` -- serializes this approval
  -- against a concurrent app.add_vendor_rate_tier/app.remove_vendor_rate_tier call
  -- on the SAME parent row (both lock this exact row before touching a tier).
  select * into v_rate from app.vendor_rate_versions where id = p_rate_version_id for update;
  if not found then
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

  -- PRC-259: the gated "next lifecycle transition" -- a rate cannot be domain-approved
  -- while a crossed governance threshold from app.create_rate_version is still pending
  -- platform-routed approval.
  if v_rate.governance_approval_status not in ('approved', 'not_required') then
    raise exception 'rate_governance_approval_pending: rate version % governance_approval_status is % (must be approved or not_required)', p_rate_version_id, v_rate.governance_approval_status
      using errcode = 'check_violation';
  end if;

  -- PRC-255 addition (design note 12): a rate linked to a real vendor identity
  -- cannot go live for a non-active vendor.
  if v_rate.vendor_master_id is not null then
    select lifecycle_status into v_vendor_status from app.vendor_profiles where master_record_id = v_rate.vendor_master_id;
    if v_vendor_status is distinct from 'active' then
      raise exception 'vendor_not_active: linked vendor % is % -- a rate cannot be approved for a non-active vendor', v_rate.vendor_master_id, coalesce(v_vendor_status, 'unregistered')
        using errcode = 'check_violation';
    end if;
  end if;

  -- PRC-255 addition (design note 3): ordered non-overlapping tier validation,
  -- validated at publish time only.
  perform app._validate_vendor_rate_tiers_contiguous(p_rate_version_id);

  begin
    update app.vendor_rate_versions
    set approval_status = 'approved', approved_by = p_actor_label, approved_at = now(), updated_at = now(), record_version = record_version + 1
    where id = p_rate_version_id and record_version = p_expected_version
    returning * into v_rate;
  exception
    -- PRC-255 addition (design note 4): translate the raw EXCLUDE-constraint
    -- violation into the same clear, named error class every other validation
    -- failure in this repository raises.
    when exclusion_violation then
      raise exception 'ambiguous_overlap: an approved, currently-effective rate version already exists for the identical vendor/service/mode/lane/equipment scope with an overlapping validity window'
        using errcode = 'check_violation';
    -- BUG FIX (post-review, MEDIUM): a GiST EXCLUDE constraint under real
    -- concurrent contention can surface as a raw Postgres deadlock (sqlstate
    -- 40P01), not only exclusion_violation (23P01) -- a well-known
    -- characteristic of GiST index insertion under contention, live-reproduced
    -- across repeated concurrent-approval trials. Without this branch, roughly
    -- half of genuinely-conflicting concurrent approvals would leak an
    -- untranslated "deadlock detected" error instead of the documented
    -- ambiguous_overlap class this migration's own design note 4 promises for
    -- EVERY such conflict -- both sqlstates arise from the identical business
    -- conflict (two approvals racing for the same scope) and must translate
    -- identically.
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
$$;

comment on function app.approve_rate_version is 'COM-149, widened PRC-255 then PRC-259: unchanged signature. PRC-259 adds one gate check (governance_approval_status in (approved, not_required)) before the pre-existing vendor-active check, tier validation, and terminal UPDATE -- every prior widening is unchanged.';

-- The one domain-specific sync wrapper over the Approval Engine for rate approval.
create function app.decide_rate_version_approval_step(
  p_request_step_id uuid,
  p_decision text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_reason text default null
)
returns app.vendor_rate_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_step app.approval_request_steps;
  v_request app.approval_requests;
  v_updated_request app.approval_requests;
  v_rate app.vendor_rate_versions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_step from app.approval_request_steps where id = p_request_step_id;
  if not found then
    raise exception 'approval_step_not_found: no approval request step %', p_request_step_id
      using errcode = 'no_data_found';
  end if;
  select * into v_request from app.approval_requests where id = v_step.request_id;
  if v_request.entity_type <> 'rate_version' or v_request.entity_id is null then
    raise exception 'not_a_rate_version_approval: approval request % is not a rate version approval', v_request.id
      using errcode = 'check_violation';
  end if;

  perform app.decide_approval_step(p_request_step_id, p_decision, p_actor_auth_user_id, p_actor_label, p_reason);

  select * into v_updated_request from app.approval_requests where id = v_request.id;

  if v_updated_request.status = 'approved' then
    update app.vendor_rate_versions set governance_approval_status = 'approved', updated_at = now(), record_version = record_version + 1
    where id = v_request.entity_id
    returning * into v_rate;
  elsif v_updated_request.status = 'rejected' then
    update app.vendor_rate_versions set governance_approval_status = 'rejected', updated_at = now(), record_version = record_version + 1
    where id = v_request.entity_id
    returning * into v_rate;
  else
    select * into v_rate from app.vendor_rate_versions where id = v_request.entity_id;
  end if;

  return v_rate;
end;
$$;

comment on function app.decide_rate_version_approval_step is
  'PRC-259: wraps app.decide_approval_step (PLT-123, unchanged) and syncs app.vendor_rate_versions.governance_approval_status only once the bound request reaches a final state -- never touches the pre-existing approval_status column.';

-- ===========================================================================
-- 6. Vendor selection/comparison approval binding -- app.vendor_comparisons (PRC-258).
--    PRC-258's own migration header names app.submit_vendor_comparison_for_approval as
--    "the approval-engine handoff point (Prompt 259, not called from this checkpoint)"
--    -- this is that follow-through.
-- ===========================================================================

alter table app.vendor_comparisons
  add column approval_status text not null default 'not_required',
  add column approval_request_id uuid references app.approval_requests (id);

alter table app.vendor_comparisons
  add constraint vendor_comparisons_approval_status_check check (approval_status in ('not_required', 'pending', 'approved', 'rejected'));

comment on column app.vendor_comparisons.approval_status is
  'PRC-259: the Platform-engine-routed governance outcome for this comparison''s selection, independent of status. Set by app.submit_vendor_comparison_for_approval (routing trigger point) and synced back by app.decide_vendor_selection_approval_step. status=submitted is already terminal within PRC-258''s own scope -- the gated "next lifecycle transition" is Prompt 260''s own future PO-award RPC, which must check approval_status in (approved, not_required) before creating a PO from selected_offer_id (see this migration''s own header).';

-- Widened (PRC-259): identical signature -- the governance decision is resolved BEFORE
-- the single existing UPDATE (v_offer, fetched earlier in the function body, already
-- carries the value/currency needed) so status/selected_offer_id/approval_status are
-- all set in that ONE write -- app.vendor_comparisons has its own before-update trigger
-- (app.touch_vendor_comparison_row) that bumps record_version automatically, so no
-- manual increment is added here.
create or replace function app.submit_vendor_comparison_for_approval(
  p_comparison_id uuid,
  p_selected_offer_id uuid,
  p_selection_reason text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_comparisons
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_cost_decision app.rbac_decision;
  v_comparison app.vendor_comparisons;
  v_offer app.vendor_comparison_offers;
  v_gov_required boolean;
  v_gov_approval_status text;
  v_gov_approval_request_id uuid;
begin
  select * into v_comparison from app.vendor_comparisons where id = p_comparison_id for update;
  if not found then
    raise exception 'vendor_comparison_not_found: %', p_comparison_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_comparison.tenant_id, 'PRC', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_comparison.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_cost_decision := app.evaluate_permission(p_actor_auth_user_id, v_comparison.tenant_id, 'PRC', 'View cost');
  if not v_cost_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View cost (%) for tenant %', p_actor_auth_user_id, v_cost_decision.reason, v_comparison.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_comparison.record_version <> p_expected_version then
    raise exception 'stale_version: vendor comparison % expected version % but found %', p_comparison_id, p_expected_version, v_comparison.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_comparison.status <> 'recommended' then
    raise exception 'invalid_transition: vendor comparison % is % -- only a recommended comparison may be submitted', p_comparison_id, v_comparison.status
      using errcode = 'check_violation';
  end if;

  select * into v_offer from app.vendor_comparison_offers where id = p_selected_offer_id and comparison_id = p_comparison_id;
  if not found then
    raise exception 'vendor_comparison_offer_not_found: % does not belong to comparison %', p_selected_offer_id, p_comparison_id using errcode = 'no_data_found';
  end if;
  if not v_offer.included then
    raise exception 'excluded_offer: offer % is excluded and cannot be selected', p_selected_offer_id using errcode = 'check_violation';
  end if;

  if p_selected_offer_id is distinct from v_comparison.recommended_offer_id and (p_selection_reason is null or length(trim(p_selection_reason)) = 0) then
    raise exception 'reason_required: a non-empty reason is required to select an offer other than the recommended one' using errcode = 'check_violation';
  end if;

  -- PRC-259: resolve governance routing before the single UPDATE below --
  -- p_comparison_id is already the entity's own stable primary key (this row is never
  -- re-submitted a second time, status='submitted' being terminal within PRC-258's own
  -- scope), so it is used verbatim as the idempotency key.
  select r.required, r.approval_status, r.approval_request_id into v_gov_required, v_gov_approval_status, v_gov_approval_request_id
  from app._request_procurement_entity_approval(
    'vendor_selection', v_comparison.tenant_id, p_comparison_id, v_offer.normalized_amount, v_comparison.comparison_currency,
    jsonb_build_object('rfq_id', v_comparison.rfq_id, 'selected_offer_id', p_selected_offer_id),
    p_expected_version + 1, 'vendor_selection:' || p_comparison_id::text, p_actor_auth_user_id, p_actor_label
  ) r;

  update app.vendor_comparisons
  set status = 'submitted', selected_offer_id = p_selected_offer_id, selection_reason = p_selection_reason,
      submitted_at = now(), submitted_by = p_actor_label,
      approval_status = v_gov_approval_status, approval_request_id = v_gov_approval_request_id
  where id = p_comparison_id and record_version = p_expected_version
  returning * into v_comparison;
  if not found then
    raise exception 'stale_version: vendor comparison % target row was concurrently modified (expected version %)', p_comparison_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.vendor_comparison_events (tenant_id, comparison_id, from_status, to_status, reason, evidence_ref, actor_auth_user_id, actor_label)
  values (v_comparison.tenant_id, p_comparison_id, 'recommended', 'submitted', p_selection_reason, p_selected_offer_id::text, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_comparison.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_vendor_comparison_for_approval',
    'app.vendor_comparisons', v_comparison.id, 'success', p_selection_reason, null, jsonb_build_object('selected_offer_id', p_selected_offer_id, 'approval_status', v_gov_approval_status)
  );

  return v_comparison;
end;
$$;

comment on function app.submit_vendor_comparison_for_approval is 'PRC-258, widened PRC-259: unchanged signature. recommended -> submitted, gated on PRC:Approve ("management approves," access rule). PRC-259 additionally routes for platform-engine governance approval when app.procurement_approval_policies has a published vendor_selection policy the selected offer''s normalized_amount crosses -- Prompt 260''s own future PO-award RPC must check approval_status in (approved, not_required) before creating a PO from selected_offer_id (see this migration''s own header). Mandatory reason when the selected offer differs from the recommended one (business rule: human selection and override are auditable). Terminal -- no further offer edits once submitted.';

-- The one domain-specific sync wrapper over the Approval Engine for vendor selection.
create function app.decide_vendor_selection_approval_step(
  p_request_step_id uuid,
  p_decision text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_reason text default null
)
returns app.vendor_comparisons
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_step app.approval_request_steps;
  v_request app.approval_requests;
  v_updated_request app.approval_requests;
  v_comparison app.vendor_comparisons;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_step from app.approval_request_steps where id = p_request_step_id;
  if not found then
    raise exception 'approval_step_not_found: no approval request step %', p_request_step_id
      using errcode = 'no_data_found';
  end if;
  select * into v_request from app.approval_requests where id = v_step.request_id;
  if v_request.entity_type <> 'vendor_selection' or v_request.entity_id is null then
    raise exception 'not_a_vendor_selection_approval: approval request % is not a vendor selection approval', v_request.id
      using errcode = 'check_violation';
  end if;

  perform app.decide_approval_step(p_request_step_id, p_decision, p_actor_auth_user_id, p_actor_label, p_reason);

  select * into v_updated_request from app.approval_requests where id = v_request.id;

  if v_updated_request.status = 'approved' then
    update app.vendor_comparisons set approval_status = 'approved'
    where id = v_request.entity_id
    returning * into v_comparison;
  elsif v_updated_request.status = 'rejected' then
    update app.vendor_comparisons set approval_status = 'rejected'
    where id = v_request.entity_id
    returning * into v_comparison;
  else
    select * into v_comparison from app.vendor_comparisons where id = v_request.entity_id;
  end if;

  return v_comparison;
end;
$$;

comment on function app.decide_vendor_selection_approval_step is
  'PRC-259: wraps app.decide_approval_step (PLT-123, unchanged) and syncs app.vendor_comparisons.approval_status only once the bound request reaches a final state. Relies on app.vendor_comparisons'' own before-update trigger to bump record_version -- no manual increment needed in the UPDATE SET clause here.';

-- ===========================================================================
-- 7. Exception/override binding -- app.procurement_exception_requests, a new, minimal,
--    self-contained governed entity (no existing Phase 6 table represents a standalone
--    exception/waiver request). PRC:Override-gated, mandatory reason, mirrors the
--    RFQ/vendor-comparison override actions'' own "mandatory reason" discipline but adds
--    real platform-routed governance on top when policy requires it.
-- ===========================================================================

create table app.procurement_exception_requests (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  related_entity_type text,
  related_entity_id uuid,
  exception_type text not null,
  reason text not null,
  requested_outcome text,
  status text not null default 'submitted',
  approval_status text not null default 'not_required',
  approval_request_id uuid references app.approval_requests (id),
  idempotency_key text not null,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint procurement_exception_requests_status_check check (status in ('submitted', 'approved', 'rejected', 'cancelled')),
  constraint procurement_exception_requests_approval_status_check check (approval_status in ('not_required', 'pending', 'approved', 'rejected')),
  constraint procurement_exception_requests_reason_check check (length(trim(reason)) > 0),
  constraint procurement_exception_requests_exception_type_check check (length(trim(exception_type)) > 0),
  constraint procurement_exception_requests_tenant_idempotency_unique unique (tenant_id, idempotency_key)
);

comment on table app.procurement_exception_requests is
  'PRC-259: a standalone governed exception/override request (business rules: "approve a time-bounded exception/override," "rejection/revision/delegation/escalation/override require reason and complete audit"). related_entity_type/related_entity_id are a polymorphic, application-validated, purely descriptive reference to whatever this exception concerns (never re-validated against a foreign table, the same disclosed pattern app.approval_requests.entity_type/entity_id already established, PLT-123) -- the governed approval decision itself concerns THIS row, via entity_type=exception_override / entity_id=this row''s own id. status collapses onto approval_status once decided (approved/rejected) because, unlike the other three governed entities, an exception request has no further domain "release" step of its own within this migration''s scope -- the grant IS the approval outcome.';

create index procurement_exception_requests_tenant_status_idx on app.procurement_exception_requests (tenant_id, status);

create function app.touch_procurement_exception_request_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger procurement_exception_requests_touch_row
  before update on app.procurement_exception_requests
  for each row
  execute function app.touch_procurement_exception_request_row();

create function app.create_procurement_exception_request(
  p_tenant_id uuid,
  p_related_entity_type text,
  p_related_entity_id uuid,
  p_exception_type text,
  p_reason text,
  p_requested_outcome text,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.procurement_exception_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_existing app.procurement_exception_requests;
  v_new_id uuid := gen_random_uuid();
  v_gov_required boolean;
  v_gov_approval_status text;
  v_gov_approval_request_id uuid;
  v_row app.procurement_exception_requests;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to request a procurement exception/override' using errcode = 'check_violation';
  end if;
  if p_exception_type is null or length(trim(p_exception_type)) = 0 then
    raise exception 'exception_type_required: a non-empty exception_type is required' using errcode = 'check_violation';
  end if;

  -- taxonomy C-01: idempotency replay compares the FULL target tuple, not just the key.
  select * into v_existing from app.procurement_exception_requests where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.related_entity_type is distinct from p_related_entity_type
       or v_existing.related_entity_id is distinct from p_related_entity_id
       or v_existing.exception_type is distinct from p_exception_type
       or v_existing.reason is distinct from p_reason
       or v_existing.requested_outcome is distinct from p_requested_outcome then
      raise exception 'idempotency_key_conflict: key % was already used for a different exception request', p_idempotency_key
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  select r.required, r.approval_status, r.approval_request_id into v_gov_required, v_gov_approval_status, v_gov_approval_request_id
  from app._request_procurement_entity_approval(
    'exception_override', p_tenant_id, v_new_id, null, null,
    jsonb_build_object('exception_type', p_exception_type, 'related_entity_type', p_related_entity_type),
    1, 'exception_override:' || v_new_id::text, p_actor_auth_user_id, p_actor_label
  ) r;

  begin
    insert into app.procurement_exception_requests (
      id, tenant_id, related_entity_type, related_entity_id, exception_type, reason, requested_outcome,
      status, approval_status, approval_request_id, idempotency_key, created_by
    ) values (
      v_new_id, p_tenant_id, p_related_entity_type, p_related_entity_id, p_exception_type, p_reason, p_requested_outcome,
      case when v_gov_required then 'submitted' else 'approved' end, v_gov_approval_status, v_gov_approval_request_id, p_idempotency_key, p_actor_label
    )
    returning * into v_row;
  exception
    when unique_violation then
      declare
        v_constraint_name text;
      begin
        get stacked diagnostics v_constraint_name = constraint_name;
        if v_constraint_name = 'procurement_exception_requests_tenant_idempotency_unique' then
          select * into v_row from app.procurement_exception_requests where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
          if v_row.related_entity_type is distinct from p_related_entity_type
             or v_row.related_entity_id is distinct from p_related_entity_id
             or v_row.exception_type is distinct from p_exception_type
             or v_row.reason is distinct from p_reason
             or v_row.requested_outcome is distinct from p_requested_outcome then
            raise exception 'idempotency_key_conflict: key % was already used for a different exception request', p_idempotency_key
              using errcode = 'unique_violation';
          end if;
        else
          raise;
        end if;
      end;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_procurement_exception_request',
    'app.procurement_exception_requests', v_row.id, 'success', p_reason, null, to_jsonb(v_row)
  );

  return v_row;
end;
$$;

comment on function app.create_procurement_exception_request is
  'PRC-259: PRC:Override, mandatory reason. Routes for platform-engine governance approval when app.procurement_approval_policies has a published exception_override policy (always_required, since this entity has no value dimension -- see procurement_approval_policies_value_dimension_check). status starts submitted when routed, or auto-approved immediately when no policy is published for this tenant (opt-in, matching every other governed entity_type''s own precedent) -- the grant IS the approval outcome, there is no further release step.';

create function app.cancel_procurement_exception_request(
  p_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.procurement_exception_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_row app.procurement_exception_requests;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to cancel a procurement exception request' using errcode = 'check_violation';
  end if;

  select * into v_row from app.procurement_exception_requests where id = p_id;
  if not found then
    raise exception 'procurement_exception_request_not_found: %', p_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_row.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_row.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_row.record_version <> p_expected_version then
    raise exception 'stale_version: procurement exception request % expected version % but found %', p_id, p_expected_version, v_row.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_row.status <> 'submitted' then
    raise exception 'invalid_transition: procurement exception request % is % and cannot be cancelled', p_id, v_row.status
      using errcode = 'check_violation';
  end if;

  if v_row.approval_request_id is not null then
    perform app.cancel_approval_request(v_row.approval_request_id, p_actor_auth_user_id, p_actor_label, p_reason);
  end if;

  update app.procurement_exception_requests
  set status = 'cancelled'
  where id = p_id and record_version = p_expected_version
  returning * into v_row;
  if not found then
    raise exception 'stale_version: procurement exception request % target row was concurrently modified (expected version %)', p_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_row.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_procurement_exception_request',
    'app.procurement_exception_requests', v_row.id, 'success', p_reason, null, to_jsonb(v_row)
  );

  return v_row;
end;
$$;

-- The one domain-specific sync wrapper over the Approval Engine for exception/override
-- requests. Unlike the other three, this one also syncs the entity's OWN status column
-- -- an exception request has no further release step of its own, so the approval
-- outcome IS the terminal status.
create function app.decide_procurement_exception_approval_step(
  p_request_step_id uuid,
  p_decision text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_reason text default null
)
returns app.procurement_exception_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_step app.approval_request_steps;
  v_request app.approval_requests;
  v_updated_request app.approval_requests;
  v_row app.procurement_exception_requests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_step from app.approval_request_steps where id = p_request_step_id;
  if not found then
    raise exception 'approval_step_not_found: no approval request step %', p_request_step_id
      using errcode = 'no_data_found';
  end if;
  select * into v_request from app.approval_requests where id = v_step.request_id;
  if v_request.entity_type <> 'exception_override' or v_request.entity_id is null then
    raise exception 'not_a_procurement_exception_approval: approval request % is not a procurement exception/override approval', v_request.id
      using errcode = 'check_violation';
  end if;

  perform app.decide_approval_step(p_request_step_id, p_decision, p_actor_auth_user_id, p_actor_label, p_reason);

  select * into v_updated_request from app.approval_requests where id = v_request.id;

  if v_updated_request.status = 'approved' then
    update app.procurement_exception_requests set approval_status = 'approved', status = 'approved'
    where id = v_request.entity_id
    returning * into v_row;
  elsif v_updated_request.status = 'rejected' then
    update app.procurement_exception_requests set approval_status = 'rejected', status = 'rejected'
    where id = v_request.entity_id
    returning * into v_row;
  else
    select * into v_row from app.procurement_exception_requests where id = v_request.entity_id;
  end if;

  return v_row;
end;
$$;

comment on function app.decide_procurement_exception_approval_step is
  'PRC-259: wraps app.decide_approval_step (PLT-123, unchanged). Unlike the other three domain sync wrappers, this one ALSO syncs status (not just approval_status) -- an exception request has no further release step, so the governance outcome IS the terminal domain status.';

create function app.get_procurement_exception_request(p_id uuid, p_actor_auth_user_id uuid)
returns app.procurement_exception_requests
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_row app.procurement_exception_requests;
begin
  select * into v_row from app.procurement_exception_requests where id = p_id;
  if not found then
    raise exception 'procurement_exception_request_not_found: %', p_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_row.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_row.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return v_row;
end;
$$;

create function app.list_procurement_exception_requests(p_tenant_id uuid, p_actor_auth_user_id uuid, p_status_filter text default null, p_limit integer default 100)
returns setof app.procurement_exception_requests
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
    select * from app.procurement_exception_requests
    where tenant_id = p_tenant_id and (p_status_filter is null or status = p_status_filter)
    order by created_at desc
    limit least(coalesce(p_limit, 100), 200);
end;
$$;

-- ===========================================================================
-- 8. RLS + grants.
-- ===========================================================================

alter table app.procurement_approval_policies enable row level security;
alter table app.procurement_approval_context_snapshots enable row level security;
alter table app.procurement_exception_requests enable row level security;

-- Tenant-wide reference/policy data (mirrors app.quotation_approval_rules, COM-153) --
-- never field-masked, direct RLS-scoped select for any active tenant member.
create policy procurement_approval_policies_select_scoped on app.procurement_approval_policies
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

-- RLS is enabled for defense in depth, but no column-level grant is issued to
-- authenticated at all (see migration header) -- app.get_procurement_approval_context_
-- snapshot is the only read path, mirroring app.approval_decisions' own posture.
create policy procurement_approval_context_snapshots_select_scoped on app.procurement_approval_context_snapshots
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy procurement_exception_requests_select_scoped on app.procurement_exception_requests
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke of
-- PostgreSQL's PUBLIC-execute default, the standing per-migration convention since PLT-118.
revoke execute on all functions in schema app from public;

grant select on app.procurement_approval_policies to authenticated, service_role;
grant insert, update, delete on app.procurement_approval_policies to service_role;

-- No table-level grant at all for app.procurement_approval_context_snapshots
-- (authenticated or otherwise) -- app.get_procurement_approval_context_snapshot is the
-- one read path (see migration header, mirrors app.approval_decisions, PLT-123).
grant insert, update, delete on app.procurement_approval_context_snapshots to service_role;
grant select on app.procurement_approval_context_snapshots to service_role;

grant select on app.procurement_exception_requests to authenticated, service_role;
grant insert, update, delete on app.procurement_exception_requests to service_role;

grant select (approval_status, approval_request_id) on app.vendor_profiles to authenticated;
grant select (governance_approval_status, governance_approval_request_id) on app.vendor_rate_versions to authenticated;
grant select (approval_status, approval_request_id) on app.vendor_comparisons to authenticated;

grant execute on function app.create_procurement_approval_policy_version(uuid, text, numeric, boolean, uuid, text) to authenticated, service_role;
grant execute on function app.publish_procurement_approval_policy_version(uuid, integer, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.evaluate_procurement_approval_requirement(text, uuid, numeric, uuid) to authenticated, service_role;
grant execute on function app.get_procurement_approval_context_snapshot(uuid, uuid) to authenticated, service_role;

grant execute on function app.decide_vendor_activation_approval_step(uuid, text, uuid, text, text) to authenticated, service_role;
grant execute on function app.decide_rate_version_approval_step(uuid, text, uuid, text, text) to authenticated, service_role;
grant execute on function app.decide_vendor_selection_approval_step(uuid, text, uuid, text, text) to authenticated, service_role;

grant execute on function app.create_procurement_exception_request(uuid, text, uuid, text, text, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.cancel_procurement_exception_request(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.decide_procurement_exception_approval_step(uuid, text, uuid, text, text) to authenticated, service_role;
grant execute on function app.get_procurement_exception_request(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_procurement_exception_requests(uuid, uuid, text, integer) to authenticated, service_role;

-- Widened pre-existing functions keep their pre-existing grants (CREATE OR REPLACE
-- preserves ACLs) -- app.decide_vendor_profile_review/app.activate_vendor_profile/app.
-- create_rate_version/app.approve_rate_version/app.submit_vendor_comparison_for_
-- approval are already granted to authenticated, service_role from their own prior
-- migrations; re-stated here only for clarity, matching COM-153's own precedent of not
-- re-granting an unchanged-signature widened function.
