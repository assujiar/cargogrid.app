-- Commercial capability COM-163 (Tenant/Security/Financial/Data Hardening, CG-S7-COM-022)
-- Root-cause repair of the one real, previously-undetected finding from a dedicated
-- security review of the 6 Commercial capability prompts COM-162's own integrated
-- verification did not independently recompose (146, 152, 153, 156, 158, 159) --
-- COM-162's own composed golden path recorded zero Critical/High/Medium finding, so this
-- checkpoint's scope is this one finding, not a manufactured broader pass (Prompt 163
-- §12/§24: no unrelated debt/refactor, no cosmetic cleanup beyond the exact finding).
--
-- Finding (High -- cross-tenant business-intelligence disclosure, IDOR class):
-- `app.evaluate_quotation_approval_requirement(p_quotation_id uuid)` (COM-153,
-- 20260724270000_create_commercial_quotation_approval.sql) is the only function across
-- every Commercial migration granted directly to `authenticated` that takes a bare entity
-- id and NO tenant/actor parameter, and performs NO access check at all -- every sibling
-- function in the same file and migration family (concretely,
-- app.get_quotation_submission_readiness, COM-152, widened by COM-153 in the same file)
-- takes `p_actor_auth_user_id uuid default auth.uid()` and calls
-- app.can_access_record(...) before returning anything. Because this function was
-- granted to `authenticated` unconditionally, any authenticated identity in *any* tenant
-- who obtains a quotation id belonging to a *different* tenant (a leaked URL, a shared
-- log line, or simple enumeration against a low-entropy id scheme in a future migration)
-- could learn that tenant's own margin/discount/value threshold-crossing signal
-- (`required`/`reasons`, e.g. `below_minimum_margin`) for an arbitrary deal it has no
-- entitlement to see -- never a raw dollar figure, but a real, disclosed business-
-- intelligence leak the function's own sibling already guards against. The gap was purely
-- a missing actor/access-check parameter, not a defect in the underlying business logic
-- (unchanged verbatim below).
--
-- Root-cause repair: widen the function to the identical `(p_quotation_id,
-- p_actor_auth_user_id default auth.uid())` shape as
-- app.get_quotation_submission_readiness, and add the identical
-- app.can_access_record(...) check. Postgres requires a `DROP FUNCTION` (not `CREATE OR
-- REPLACE`) to add a parameter -- the old 1-argument overload otherwise remains callable
-- alongside a new 2-argument one, leaving the vulnerability open. app.submit_quotation
-- (COM-151/152/153) already validates the caller's own access before ever calling this
-- function internally, so re-pointing its one call site at the now-mandatory
-- p_actor_auth_user_id parameter is a same-signature `CREATE OR REPLACE FUNCTION`, not a
-- second DROP.
--
-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries its own
-- explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement before
-- its final grants, the standing per-migration convention since PLT-118.

drop function app.evaluate_quotation_approval_requirement(uuid);

create function app.evaluate_quotation_approval_requirement(
  p_quotation_id uuid,
  p_actor_auth_user_id uuid default auth.uid()
)
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

  -- COM-163 hardening: the one check this function's own sibling,
  -- app.get_quotation_submission_readiness (COM-152/153), already performs -- closes the
  -- cross-tenant business-intelligence disclosure this migration's own header describes.
  if not app.can_access_record(p_actor_auth_user_id, v_quotation.tenant_id, v_quotation.owner_user_id, app.lead_record_scope_org_unit_ids(v_quotation.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access quotation %', p_actor_auth_user_id, p_quotation_id
      using errcode = 'insufficient_privilege';
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
  'COM-153, hardened COM-163: the one deterministic, explainable "does this quotation need approval" decision. COM-163 added the missing p_actor_auth_user_id parameter and app.can_access_record(...) check -- the original COM-153 version took only p_quotation_id and performed no access check at all, unlike its own sibling app.get_quotation_submission_readiness, allowing any authenticated identity in any tenant to learn another tenant''s margin/discount/value threshold-crossing signal for a guessed/leaked quotation id. Margin uses the cheapest-sourced line (min across app.quotation_lines.margin_pct_snapshot); discount uses the header''s own effective discount_amount/subtotal_amount; value uses total_amount directly. Customer/service/organizational thresholds remain this capability''s own disclosed boundary, not built here.';

-- Re-authored verbatim from COM-153's own applied body (supabase/migrations/
-- 20260724270000_create_commercial_quotation_approval.sql) with exactly one changed
-- line (the evaluate_quotation_approval_requirement call now passes the already-
-- validated p_actor_auth_user_id) -- same signature, so CREATE OR REPLACE is the correct
-- and sufficient vehicle here (unlike the widened function above).
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
  from app.evaluate_quotation_approval_requirement(p_quotation_id, p_actor_auth_user_id) e;

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
  'COM-151/152/153, hardened COM-163: draft -> submitted, gated by a real readiness check, then routed in the same transaction -- app.evaluate_quotation_approval_requirement decides whether a threshold is crossed; if not, the quotation is auto-approved (approval_status=approved, no request created); if so, app.request_approval opens a real routed request against the tenant''s published approval definition (approval_status=pending), failing closed with approval_definition_not_configured if none is published. COM-163 re-points the internal evaluate_quotation_approval_requirement call at the now-mandatory p_actor_auth_user_id parameter -- no behavior change here, since this function already validated the same actor''s access before this call.';

revoke execute on all functions in schema app from public;

grant execute on function app.evaluate_quotation_approval_requirement(uuid, uuid) to authenticated, service_role;
grant execute on function app.submit_quotation(uuid, integer, uuid, text) to authenticated, service_role;
