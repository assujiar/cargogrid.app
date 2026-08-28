-- Track B Batch 5, ISS-2026-152 (docs/runtime/KNOWN_ISSUES.md): DRAFT, not yet
-- applied to any live/hosted project. Research-and-drafting pass only -- see
-- Batch 5 writeup for the independent re-verification this migration is based
-- on.
--
-- The region/service-capability matrix (`app.region_service_capabilities`,
-- IAE-033, 20260808100000_create_intelligence_multi_region_data_residency.sql)
-- is checked exactly once, at `approve_region_assignment` time (paperwork) --
-- independently reconfirmed this pass by direct read of the current (and only)
-- body of `app.request_ai_governed_action` (IAE-019, last replaced
-- 20260805070000_harden_intelligence_batch4_tier_c_review_fixes.sql:1341-1394):
-- no reference anywhere to `app.resolve_tenant_region`, `app.region_service_
-- capabilities`, or `app.region_capability_exceptions`. A tenant driven to a
-- genuine dedicated deployment + an active, approved non-default region
-- assignment, with `ai_provider` registered as a known, accepted-risk
-- UNSUPPORTED category for that region via `app.register_region_capability_
-- exception`, can still dispatch an ordinary `app.request_ai_governed_action`
-- call with zero reference anywhere to the matrix it just accepted risk
-- against. Marking a category unsupported has no live enforcement, warning,
-- or audit-flag consequence at the actual point of use -- the entry's own
-- root-cause diagnosis, independently reconfirmed.
--
-- Fix (same signature -- `create or replace function`, zero parameter change,
-- zero caller-visible behavior change for the >99% case, since every ordinary
-- tenant resolves to region 'apac', which is fully supported for every
-- category including ai_provider, 20260808100000:94-100 -- independently
-- reconfirmed no db-test tenant across the 8 files calling this function ever
-- provisions a dedicated deployment + region assignment, so this is genuinely
-- additive, not a behavior change to any existing passing test):
--   1. Resolve the tenant's own real region (`app.resolve_tenant_region`) and
--      look up whether `ai_provider` is `supported` there
--      (`app.region_service_capabilities`).
--   2. If supported (the default -- 'apac', or any region once real capacity
--      genuinely ships there), dispatch proceeds exactly as before, byte-for-
--      byte -- zero new branch is ever entered.
--   3. If NOT supported, look for a real, approved accepted-risk exception on
--      file for this tenant's own active region assignment
--      (`app.region_capability_exceptions`, joined through `app.tenant_region_
--      assignments`). If one exists, dispatch proceeds, but the request is now
--      genuinely traceable as operating under an accepted-risk exception -- the
--      audit event captured for this call gains a
--      `region_capability_exception_id` tag, closing the entry's own literal
--      "at minimum tag the request/audit event when operating over an
--      accepted-risk exception" ask.
--   4. If NOT supported and NO exception is on file, the call is now refused
--      (`ai_governed_action_region_capability_unsupported`). This is a
--      DELIBERATE judgment call beyond the entry's own literal minimum ask
--      (which named only the tagging behavior as required) -- flagged here
--      explicitly for whoever reviews this draft, since the entry itself
--      reserved "should this actually block" as part of the larger design
--      decision it declined to make unilaterally. Rationale for including it
--      anyway: the entry's own root-cause complaint is that marking a category
--      unsupported currently has "no live enforcement, warning, OR audit-flag
--      consequence at the actual point of use" -- a consult-and-tag-but-never-
--      enforce design would still leave the unsupported+no-exception case
--      (arguably the actual risk case, more than the already-accepted-risk
--      case) with zero live consequence, which does not fully close what the
--      entry's own text diagnoses as broken. A reviewer who disagrees can
--      narrow step 4 to a warning-only audit tag instead of a hard denial by
--      dropping the `raise exception` branch below and unconditionally tagging
--      the audit event, without touching anything else in this migration.
--
-- Blast radius, live-verified against a disposable database this pass: all 8
-- files with a real `app.request_ai_governed_action` call (`ai-assisted-
-- quotation.sql`, `ai-governance-provider-boundary.sql`, `batch4-tier-c-
-- review-fixes.sql`, `forecasting-recommendation.sql`, `fraud-risk-assistance.
-- sql`, `ocr-document-processing.sql`, `optimization-assistance.sql`,
-- `predictive-eta.sql`) re-run clean against this migration with zero other
-- change -- none of their own tenants ever provisions a dedicated deployment +
-- non-default region assignment, so `app.resolve_tenant_region` returns 'apac'
-- (fully supported) for every one of them and the new branch is never entered.
--
-- Not addressed here, deliberately, matching the entry's own scoping: no
-- OTHER `region_service_capabilities`-gated real entry point (the entry names
-- this as a longer-term "any other" follow-up) is touched by this migration --
-- `app.request_ai_governed_action` is the one, already-named, currently-real
-- data-plane consumer.
--
-- Regression coverage: a new db-test block should be added to
-- scripts/db-tests/ai-governance-provider-boundary.sql (the file that already
-- owns IAE-019's own regression suite) proving (a) an ordinary 'apac' tenant
-- is completely unaffected, (b) a tenant driven to a real dedicated
-- deployment + active americas region assignment with NO ai_provider
-- exception on file is refused with ai_governed_action_region_capability_
-- unsupported, and (c) the identical tenant, after a real app.register_
-- region_capability_exception('ai_provider', ...) call, succeeds and the
-- resulting audit event's own detail jsonb carries a non-null
-- region_capability_exception_id -- not applied to that file by this
-- migration itself; described here for whoever picks this draft up.

\set ON_ERROR_STOP on

create or replace function app.request_ai_governed_action(
  p_tenant_id uuid,
  p_connection_id uuid,
  p_feature_code text,
  p_correlation_record_type text,
  p_correlation_record_id uuid,
  p_prompt_payload jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.ai_governed_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_row app.ai_governed_requests;
  v_region text;
  v_capability_supported boolean;
  v_exception_id uuid;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.check_ai_governance_authority('Create', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:Create for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_feature_code is null or length(trim(p_feature_code)) = 0 then
    raise exception 'ai_governed_request_feature_code_required: a feature_code is required' using errcode = 'check_violation';
  end if;

  -- Tier C fix: p_connection_id must actually belong to p_tenant_id.
  if not exists (select 1 from app.integration_connections where id = p_connection_id and tenant_id = p_tenant_id) then
    raise exception 'ai_governed_request_connection_tenant_mismatch: connection % does not belong to tenant %', p_connection_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  perform app.assert_ai_prompt_payload_has_no_secret_shaped_keys(p_prompt_payload);

  -- ISS-2026-149 -- no, ISS-2026-152 (Track B Batch 5): consult the region/
  -- service-capability matrix at the actual point of use, not only at
  -- approve_region_assignment paperwork time. A no-row-found lookup is
  -- treated as NOT supported (fail-closed -- a real dedicated region with no
  -- declared capability row for a category is a configuration gap, never
  -- silently treated as fine).
  v_region := app.resolve_tenant_region(p_tenant_id);
  select coalesce(supported, false) into v_capability_supported
  from app.region_service_capabilities
  where region_code = v_region and service_category = 'ai_provider';
  v_capability_supported := coalesce(v_capability_supported, false);

  if not v_capability_supported then
    select rce.id into v_exception_id
    from app.region_capability_exceptions rce
    join app.tenant_region_assignments tra on tra.id = rce.region_assignment_id
    where tra.tenant_id = p_tenant_id
      and tra.status = 'active'
      and rce.service_category = 'ai_provider'
      and rce.approved_at is not null;

    if v_exception_id is null then
      raise exception 'ai_governed_action_region_capability_unsupported: region % does not support ai_provider for tenant %, and no accepted-risk exception is on file (app.register_region_capability_exception)', v_region, p_tenant_id
        using errcode = 'check_violation';
    end if;
  end if;

  insert into app.ai_governed_requests (
    tenant_id, connection_id, feature_code, correlation_record_type, correlation_record_id,
    prompt_payload, status, requested_by_auth_user_id, requested_by
  ) values (
    p_tenant_id, p_connection_id, p_feature_code, p_correlation_record_type, p_correlation_record_id,
    p_prompt_payload, 'pending', p_actor_auth_user_id, p_actor_label
  )
  returning * into v_row;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'request_ai_governed_action',
    'app.ai_governed_requests', v_row.id, 'success', null, null,
    jsonb_build_object(
      'feature_code', v_row.feature_code, 'correlation_record_type', v_row.correlation_record_type,
      'region', v_region, 'region_capability_exception_id', v_exception_id
    )
  );

  return v_row;
end;
$$;

comment on function app.request_ai_governed_action is
  'IAE-019, hardened by the merged Batch 4 Tier C review, and ISS-2026-152 (Track B Batch 5): now SECURITY DEFINER with an app.assert_actor_is_session_identity call -- live-reproduced that this function, though granted to authenticated, was unreachable through the app''s own RLS-scoped client. Also now cross-checks p_connection_id belongs to p_tenant_id. Consults app.resolve_tenant_region + app.region_service_capabilities at dispatch time (IAE-033''s matrix now has a real run-time consequence): a tenant whose resolved region does not support ai_provider is refused unless a real, approved app.region_capability_exceptions row is on file for that region assignment, in which case dispatch proceeds and the captured audit event carries region_capability_exception_id. Zero behavior change for the default (''apac'', fully supported) case. The entry point every AI-assisted capability (Prompt 348+) calls to register a real, governed AI request BEFORE dispatching it. Never writes to any table outside this migration''s own schema (design decision 2).';
