-- IAE-020's own trailing single-capability Tier C review fix pass
-- (CG-S14-IAE-020, Prompt 348, AI-Assisted Quotation). This capability was
-- deliberately excluded from the merged Batch 4's own already-closed Tier C
-- review (00_EXECUTION_INDEX.md §14) since it required `IAE-019` `VERIFIED`
-- as a precondition to even begin -- it therefore undergoes its own
-- trailing "batch of 1" review, run and closed here.
--
-- 4 parallel adversarial lenses (spec-compliance; security/RLS/tenant,
-- live-tested; correctness/concurrency, live-tested; cross-prompt
-- integration) found 2 High and 1 Medium real, undisclosed findings, fixed
-- below. The correctness/concurrency and cross-prompt integration lenses
-- found zero blocking findings (full detail in
-- docs/build-log/phase-09/00_EXECUTION_INDEX.md §14 and
-- docs/build-log/phase-09/IAE-348.md §13).
--
-- Fix 1 (High, spec-compliance lens): `lib/ai-quotation/generate-quotation-
-- suggestion.server.ts`'s own module contract requires a service-role
-- client (`dispatchAiGovernedRequest`'s internal `record_ai_governed_
-- request_outcome` call is `service_role`-only, IAE-019) -- but it then
-- read opportunity/costing/margin context through `opportunities_
-- directory`/`margin_calculations_directory`, both of which gate on
-- `auth.uid()` directly in their own view body, not a bypassable RLS
-- policy. A service-role client carries no session, so `auth.uid()`
-- resolves to NULL there -- `opportunities_directory` would return zero
-- rows and the whole orchestration would fail on its very first read. Fixed
-- with ONE new, explicit-actor `SECURITY DEFINER` function
-- (`app.get_ai_quotation_prompt_context`) mirroring `app.get_ai_governed_
-- dispatch_info`'s own established "explicit actor, not auth.uid()"
-- pattern from IAE-019 -- the TS orchestration client is updated to call it
-- instead of the three session-scoped reads.
--
-- Fix 2 (High, security/RLS/tenant lens, live-reproduced and committed):
-- `app.create_quotation_draft` (COM-151, pre-existing, unmodified by
-- IAE-020's own original migration) accepts `p_owner_user_id`/`p_org_
-- unit_id` with NO tenant-membership/tenant-ownership validation -- unlike
-- its own sibling `p_contact_id` check two lines below. IAE-020's own
-- `accept_ai_quotation_suggestion_as_draft` is a new, second reachable
-- caller of this pre-existing gap (no compensating check of its own), and
-- the security lens live-reproduced writing a genuinely foreign tenant's
-- `owner_user_id` into a real, COMMITTED `app.quotations` row. Fixed at the
-- source, mirroring the existing `p_contact_id` check's own shape exactly,
-- so every caller of `create_quotation_draft` (not just IAE-020's own) is
-- protected -- the same "fix the shared primitive, not just the new
-- caller" precedent Batch 3's own Tier C review already established for
-- `app.rotate_api_key`.
--
-- Fix 3 (Medium, spec-compliance lens): `app.get_ai_quotation_suggestion`/
-- `app.list_ai_quotation_suggestions_for_opportunity` returned the
-- underlying governed request's own `output_payload` verbatim to ANY
-- `COM:View` holder, including a role with none of `View cost`/`View
-- selling price`/`View margin` -- the same class of sensitive pricing data
-- `app.quotation_lines_directory` already masks for such an actor
-- (Prompt 348 §24: "Customer-specific sensitive/margin fields are
-- protected by role policy"). Fixed: both functions now null out `output_
-- payload` for an actor lacking `COM:View cost`, adding a companion
-- `output_payload_masked` boolean column (mirroring the `sell_masked`/
-- `cost_masked` naming convention `app.quotation_lines_directory` already
-- uses) so an unauthorized viewer still sees the suggestion's own status/
-- confidence/model, just not the raw drafted figures. `RETURNS TABLE`
-- column list changes for both, so each is `DROP FUNCTION`/`CREATE
-- FUNCTION` (not `CREATE OR REPLACE`, per the IAE-011-established lesson
-- that a widened `RETURNS TABLE` clause is not `CREATE OR REPLACE`-safe),
-- with grants re-issued identically.
--
-- Everything else from all 4 lenses was either already correctly built
-- (re-verified live) or is disclosed, not fixed, in this checkpoint's own
-- build log §13/execution index §14 -- most notably a Low/informational,
-- pre-existing FK-driven row-locking interaction between `create_
-- quotation_draft`/`add_quotation_line` and `app.opportunities`/`app.
-- margin_calculations` (dormant, no live exploit path, not introduced by
-- this checkpoint) and the identical "no dedicated review UI" scope
-- boundary every other Batch 4 capability already disclosed.

-- ===========================================================================
-- Fix 2: app.create_quotation_draft (COM-151) -- add owner/org_unit tenant
-- checks, mirroring the existing p_contact_id check exactly.
-- ===========================================================================

create or replace function app.create_quotation_draft(
  p_tenant_id uuid,
  p_opportunity_id uuid,
  p_currency text,
  p_validity_to timestamptz,
  p_contact_id uuid,
  p_owner_user_id uuid,
  p_org_unit_id uuid,
  p_actor_auth_user_id uuid,
  p_created_by text
)
returns app.quotations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_opportunity app.opportunities;
  v_prospect app.prospects;
  v_decision app.rbac_decision;
  v_quotation app.quotations;
  v_snapshot jsonb;
  v_new_id uuid := gen_random_uuid();
begin
  select * into v_opportunity from app.opportunities where id = p_opportunity_id;
  if not found then
    raise exception 'opportunity_not_found: %', p_opportunity_id using errcode = 'no_data_found';
  end if;

  if v_opportunity.tenant_id <> p_tenant_id then
    raise exception 'cross_tenant_opportunity_denied: opportunity % does not belong to tenant %', p_opportunity_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'COM', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, p_tenant_id, v_opportunity.owner_user_id, app.lead_record_scope_org_unit_ids(v_opportunity.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access opportunity %', p_actor_auth_user_id, p_opportunity_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then
    raise exception 'invalid_currency: % is not a 3-letter ISO currency code', p_currency using errcode = 'check_violation';
  end if;

  if p_validity_to is null or p_validity_to <= now() then
    raise exception 'invalid_validity: validity_to must be in the future' using errcode = 'check_violation';
  end if;

  select * into v_prospect from app.prospects where id = v_opportunity.prospect_id;
  if not found then
    raise exception 'prospect_not_found: %', v_opportunity.prospect_id using errcode = 'no_data_found';
  end if;

  if p_contact_id is not null then
    if not exists (select 1 from app.contacts where id = p_contact_id and tenant_id = p_tenant_id) then
      raise exception 'contact_not_found: %', p_contact_id using errcode = 'no_data_found';
    end if;
  end if;

  -- Tier C fix (IAE-020's own trailing review): p_owner_user_id/p_org_unit_id
  -- were previously accepted from ANY tenant with no validation, unlike the
  -- p_contact_id check immediately above -- live-reproduced writing a
  -- foreign tenant's identity/org unit into a real, committed quotation row.
  if p_owner_user_id is not null then
    if not app.has_active_tenant_membership(p_tenant_id, p_owner_user_id) then
      raise exception 'quotation_owner_not_tenant_member: % does not hold active membership in tenant %', p_owner_user_id, p_tenant_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  if p_org_unit_id is not null then
    if not exists (select 1 from app.org_units where id = p_org_unit_id and tenant_id = p_tenant_id) then
      raise exception 'quotation_org_unit_not_found: % does not belong to tenant %', p_org_unit_id, p_tenant_id
        using errcode = 'no_data_found';
    end if;
  end if;

  v_snapshot := jsonb_build_object(
    'legal_name', v_prospect.legal_name,
    'trade_name', v_prospect.trade_name,
    'billing_address', v_prospect.billing_address,
    'contact_name', v_prospect.contact_name,
    'contact_email', v_prospect.contact_email,
    'contact_phone', v_prospect.contact_phone
  );

  insert into app.quotations (
    id, tenant_id, quote_number, opportunity_id, source_opportunity_version, prospect_id, contact_id,
    customer_snapshot, currency, validity_to, root_quotation_id, version_number, is_current,
    owner_user_id, org_unit_id, created_by
  ) values (
    v_new_id, p_tenant_id, app.next_quotation_number(p_tenant_id), p_opportunity_id, v_opportunity.record_version, v_opportunity.prospect_id, p_contact_id,
    v_snapshot, p_currency, p_validity_to, v_new_id, 1, true,
    coalesce(p_owner_user_id, p_actor_auth_user_id), coalesce(p_org_unit_id, v_opportunity.org_unit_id), p_created_by
  )
  returning * into v_quotation;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_created_by, 'create_quotation_draft',
    'app.quotations', v_quotation.id, 'success', null, null, to_jsonb(v_quotation)
  );

  return v_quotation;
end;
$$;

comment on function app.create_quotation_draft is
  'COM-151/COM-152: creates a draft quotation from an opportunity, pinning source_opportunity_version (staleness check at submit time), a real customer_snapshot copied from app.prospects, and its own root/version-1 identity (COM-152). Idempotency is not attempted at this layer -- each call creates a genuinely new draft, matching the "clone an explicit prior draft" alternative flow (app.clone_quotation) rather than an implicit dedupe. Tier C fix (IAE-020''s own review): p_owner_user_id/p_org_unit_id are now validated against the tenant, mirroring the p_contact_id check.';

-- ===========================================================================
-- Fix 1: app.get_ai_quotation_prompt_context -- explicit-actor read for the
-- AI-dispatch orchestration client, never relying on auth.uid() (which is
-- NULL for the service-role client this capability's own dispatch client
-- must use per IAE-019's own service_role-only outcome-recording call).
-- ===========================================================================

create function app.get_ai_quotation_prompt_context(
  p_tenant_id uuid,
  p_opportunity_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  opportunity_name text,
  opportunity_stage text,
  opportunity_value_amount numeric,
  opportunity_value_currency text,
  opportunity_requirements jsonb,
  costing_request_id uuid,
  margin_calculation_id uuid,
  rate_selection_id uuid,
  rule_version_id uuid,
  sell_amount numeric,
  sell_currency text,
  margin_pct numeric
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_opportunity app.opportunities;
  v_costing_request_id uuid;
  v_can_view_cost boolean;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- Not-found/wrong-tenant returns ZERO ROWS rather than raising -- the
  -- orchestration client (lib/ai-quotation/generate-quotation-suggestion.
  -- server.ts) treats an empty result as its own clean, named precondition
  -- failure. Deliberately indistinguishable from a genuine "does not
  -- exist" (never leaks whether a foreign-tenant id exists at all).
  -- Authority failures below remain real, distinct raised exceptions.
  select * into v_opportunity from app.opportunities where id = p_opportunity_id;
  if not found or v_opportunity.tenant_id <> p_tenant_id then
    return;
  end if;

  -- Same authority gate app.record_ai_quotation_suggestion itself requires
  -- -- if this actor cannot ultimately record a suggestion for this
  -- opportunity, there is no reason to hand its own cost/margin evidence to
  -- an external AI provider on their behalf.
  if not app.check_ai_quotation_suggestion_authority('Create', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks COM:Create for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, p_tenant_id, v_opportunity.owner_user_id, app.lead_record_scope_org_unit_ids(v_opportunity.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access opportunity %', p_actor_auth_user_id, p_opportunity_id
      using errcode = 'insufficient_privilege';
  end if;

  v_can_view_cost := app.check_ai_quotation_suggestion_authority('View cost', p_tenant_id, p_actor_auth_user_id);

  select cr.id into v_costing_request_id from app.costing_requests cr where cr.opportunity_id = p_opportunity_id order by cr.created_at desc limit 1;

  -- LEFT JOIN from a single dummy row: always exactly one header row even
  -- when there is no costing request / no current margin calculation yet
  -- (all margin_* columns null in that case) -- N rows when N current
  -- margin calculations exist.
  return query
  select
    v_opportunity.name, v_opportunity.stage, v_opportunity.value_amount, v_opportunity.value_currency, v_opportunity.requirements,
    v_costing_request_id,
    mc.id, mc.rate_selection_id, mc.rule_version_id,
    case when v_can_view_cost then mc.sell_amount else null end,
    mc.sell_currency,
    case when v_can_view_cost then mc.margin_pct else null end
  from (select 1) as _dummy
  left join app.margin_calculations mc on mc.costing_request_id = v_costing_request_id and mc.is_current;
end;
$$;

comment on function app.get_ai_quotation_prompt_context is
  'IAE-020 Tier C fix: the AI-dispatch orchestration client''s own explicit-actor read -- never relies on auth.uid(), which is NULL for the service-role client this capability must use (IAE-019''s own record_ai_governed_request_outcome is service_role-only). Mirrors app.get_ai_governed_dispatch_info''s own established explicit-actor pattern. Cost/margin fields are null unless the actor holds COM:View cost.';

-- ===========================================================================
-- Fix 3: mask output_payload behind COM:View cost on both read paths.
-- RETURNS TABLE column list changes -- DROP + CREATE, not CREATE OR REPLACE
-- (the IAE-011-established lesson).
-- ===========================================================================

drop function app.get_ai_quotation_suggestion(uuid, uuid);

create function app.get_ai_quotation_suggestion(p_suggestion_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, tenant_id uuid, opportunity_id uuid, ai_governed_request_id uuid, status text,
  accepted_quotation_id uuid, dismiss_reason text, requested_by text, reviewed_by text, reviewed_at timestamptz, created_at timestamptz,
  output_payload jsonb, output_payload_masked boolean, confidence_label text, model_version text, billed_amount numeric, request_status text
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_suggestion app.ai_quotation_suggestions;
  v_can_view_cost boolean;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select s.* into v_suggestion from app.ai_quotation_suggestions s where s.id = p_suggestion_id;
  if not found then
    raise exception 'ai_quotation_suggestion_not_found: %', p_suggestion_id using errcode = 'no_data_found';
  end if;

  if not app.check_ai_quotation_suggestion_authority('View', v_suggestion.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks COM:View for tenant %', p_actor_auth_user_id, v_suggestion.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_can_view_cost := app.check_ai_quotation_suggestion_authority('View cost', v_suggestion.tenant_id, p_actor_auth_user_id);

  return query
  select s.id, s.tenant_id, s.opportunity_id, s.ai_governed_request_id, s.status,
    s.accepted_quotation_id, s.dismiss_reason, s.requested_by, s.reviewed_by, s.reviewed_at, s.created_at,
    case when v_can_view_cost then r.output_payload else null end, not v_can_view_cost,
    r.confidence_label, r.model_version, r.billed_amount, r.status
  from app.ai_quotation_suggestions s
  join app.ai_governed_requests r on r.id = s.ai_governed_request_id
  where s.id = p_suggestion_id;
end;
$$;

comment on function app.get_ai_quotation_suggestion is
  'IAE-020 Tier C fix: output_payload is now null (output_payload_masked=true) for an actor lacking COM:View cost -- it may carry drafted sell/cost/margin figures, the same class of sensitive data app.quotation_lines_directory already masks.';

drop function app.list_ai_quotation_suggestions_for_opportunity(uuid, uuid, uuid, integer);

create function app.list_ai_quotation_suggestions_for_opportunity(
  p_tenant_id uuid,
  p_opportunity_id uuid,
  p_actor_auth_user_id uuid,
  p_limit integer default 50
)
returns table (
  id uuid, tenant_id uuid, opportunity_id uuid, ai_governed_request_id uuid, status text,
  accepted_quotation_id uuid, dismiss_reason text, requested_by text, reviewed_by text, reviewed_at timestamptz, created_at timestamptz,
  output_payload jsonb, output_payload_masked boolean, confidence_label text, model_version text, billed_amount numeric, request_status text
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_can_view_cost boolean;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.check_ai_quotation_suggestion_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks COM:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_limit is null or p_limit <= 0 or p_limit > 200 then
    raise exception 'ai_quotation_suggestion_invalid_limit: limit must be between 1 and 200' using errcode = 'check_violation';
  end if;

  v_can_view_cost := app.check_ai_quotation_suggestion_authority('View cost', p_tenant_id, p_actor_auth_user_id);

  return query
  select s.id, s.tenant_id, s.opportunity_id, s.ai_governed_request_id, s.status,
    s.accepted_quotation_id, s.dismiss_reason, s.requested_by, s.reviewed_by, s.reviewed_at, s.created_at,
    case when v_can_view_cost then r.output_payload else null end, not v_can_view_cost,
    r.confidence_label, r.model_version, r.billed_amount, r.status
  from app.ai_quotation_suggestions s
  join app.ai_governed_requests r on r.id = s.ai_governed_request_id
  where s.tenant_id = p_tenant_id and s.opportunity_id = p_opportunity_id
  order by s.created_at desc
  limit p_limit;
end;
$$;

comment on function app.list_ai_quotation_suggestions_for_opportunity is
  'IAE-020 Tier C fix: output_payload is now null (output_payload_masked=true) for an actor lacking COM:View cost.';

-- ===========================================================================
-- Grants (ERR-2026-004: explicit revoke before every grant)
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant execute on function app.get_ai_quotation_prompt_context(uuid, uuid, uuid) to service_role;
grant execute on function app.get_ai_quotation_suggestion(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_ai_quotation_suggestions_for_opportunity(uuid, uuid, uuid, integer) to authenticated, service_role;
