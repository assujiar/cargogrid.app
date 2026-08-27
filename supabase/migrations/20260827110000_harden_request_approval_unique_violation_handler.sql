-- Track B Batch 2, ISS-2026-044 (docs/runtime/KNOWN_ISSUES.md): app.request_approval
-- (PLT-123, the Platform Approval Engine's shared entry point, composed by Commercial
-- quotation/credit approvals, HRIS, Intelligence, and every Procurement capability that
-- opens an approval -- at least 10 distinct call sites repo-wide) does its own
-- (tenant_id, idempotency_key) idempotency check via an unlocked SELECT followed by a
-- plain INSERT with no `exception when unique_violation` handler of its own. Two real
-- concurrent double-calls with the identical idempotency key both pass the unlocked
-- pre-check SELECT, then the loser's own INSERT hits the unique constraint and the raw,
-- unhandled `duplicate key value violates unique constraint "approval_requests_tenant_
-- idempotency_unique"` propagates all the way up through the caller -- already
-- live-reproduced once via a caller (app.decide_vendor_profile_review calling this
-- function with no lock on its own parent row), and disclosed by name (without being
-- fixed at the source) in scripts/db-tests/batch4-tier-c-review-fixes.sql for a second,
-- unrelated caller (app.request_ai_output_approval, via app.decide_vendor_profile_review's
-- kind).
--
-- Fixed at the single shared choke point rather than per-caller, mirroring this
-- repository's own already-established "insert-or-return-existing" idempotent-replay
-- pattern (app.convert_quotation_to_account, 20260724290000_create_commercial_customer_
-- account_conversion.sql: an unlocked pre-check SELECT plus the INSERT itself wrapped in
-- `begin ... exception when unique_violation then select existing ... end`) -- closing this
-- class for every one of app.request_approval's own callers at once.
--
-- Verbatim current body from 20260730390000_harden_platform_operations_finance_
-- idempotency_target_mismatch.sql (the latest of 2 prior redefinitions, NOT the original
-- 20260719090000_create_approval_engine.sql body -- checked exhaustively, case-insensitive,
-- across every migration before drafting, after an earlier draft of this same migration was
-- caught basing itself on the stale original and silently dropping this later migration's
-- own ATW-031/ISS-2026-029 idempotency_key_conflict check), with exactly the INSERT block
-- changed: wrapped in its own BEGIN...EXCEPTION...END, returning the winning concurrent
-- caller's own row on a unique_violation rather than propagating the raw
-- constraint-violation error. A caught unique_violation here means another caller's own
-- request_approval call already fully committed (request row + all step rows + its own
-- audit event) before this transaction's SELECT -- so this branch RETURNs immediately,
-- never falling through to insert a second, duplicate set of app.approval_request_steps
-- rows or capture a second audit event for the identical logical request. The
-- idempotency_key_conflict check above the INSERT is completely unaffected -- it still
-- runs first, on the pre-check SELECT's own result, exactly as before.
create or replace function app.request_approval(p_config_version_id uuid, p_tenant_id uuid, p_entity_type text, p_entity_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_requested_by text)
returns app.approval_requests
language plpgsql
as $$
declare
  v_version app.config_versions;
  v_existing app.approval_requests;
  v_pattern text;
  v_steps jsonb;
  v_step jsonb;
  v_step_order integer;
  v_approver_type text;
  v_role_id uuid;
  v_specific_user_id uuid;
  v_required_approvals integer;
  v_eligible_count integer;
  v_request app.approval_requests;
  v_step_status text;
begin
  if not app.check_approval_request_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_version from app.config_versions where id = p_config_version_id;
  if not found or v_version.status <> 'published' then
    raise exception 'approval_definition_not_published: config version % is not a published approval definition', p_config_version_id
      using errcode = 'check_violation';
  end if;

  select * into v_existing from app.approval_requests where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
    -- conflict, never a replay. Returning the earlier target's row here silently
    -- misattributed this request to it (or silently discarded it entirely).
    if v_existing.entity_type is distinct from p_entity_type or v_existing.entity_id is distinct from p_entity_id or v_existing.config_version_id is distinct from p_config_version_id then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different approval request (entity % %, not % %)', p_idempotency_key, v_existing.entity_type, v_existing.entity_id, p_entity_type, p_entity_id
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  select value #>> '{}' into v_pattern from app.config_items where config_version_id = p_config_version_id and key = 'pattern';
  select value into v_steps from app.config_items where config_version_id = p_config_version_id and key = 'steps';
  if v_pattern is null or v_steps is null then
    raise exception 'approval_definition_not_published: config version % has no pattern/steps item', p_config_version_id
      using errcode = 'check_violation';
  end if;

  for v_step in select * from jsonb_array_elements(v_steps) loop
    v_approver_type := v_step ->> 'approver_type';
    v_role_id := nullif(v_step ->> 'role_id', '')::uuid;
    v_specific_user_id := nullif(v_step ->> 'specific_user_id', '')::uuid;
    v_eligible_count := app.count_eligible_approvers_for_step(p_tenant_id, v_approver_type, v_role_id, v_specific_user_id);
    if v_eligible_count = 0 then
      raise exception 'approval_no_eligible_approver: step % has zero currently-eligible approvers in tenant %', v_step ->> 'step_order', p_tenant_id
        using errcode = 'check_violation';
    end if;
  end loop;

  -- ISS-2026-044 fix (Track B Batch 2): the pre-check SELECT above is unlocked, so two
  -- genuinely concurrent callers with the identical idempotency key can both reach this
  -- INSERT. Whichever one loses now returns the winner's own committed row instead of
  -- propagating a raw unique_violation. (A colliding key used for a genuinely different
  -- target still cannot reach this point at all -- the idempotency_key_conflict check
  -- above already raised for that case using the pre-check SELECT's own result.)
  begin
    insert into app.approval_requests (tenant_id, config_version_id, entity_type, entity_id, pattern, idempotency_key, requested_by_auth_user_id, requested_by)
    values (p_tenant_id, p_config_version_id, coalesce(p_entity_type, 'generic'), p_entity_id, v_pattern, p_idempotency_key, p_actor_auth_user_id, p_requested_by)
    returning * into v_request;
  exception
    when unique_violation then
      select * into v_request from app.approval_requests where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      return v_request;
  end;

  for v_step in select * from jsonb_array_elements(v_steps) loop
    v_step_order := (v_step ->> 'step_order')::integer;
    v_approver_type := v_step ->> 'approver_type';
    v_role_id := nullif(v_step ->> 'role_id', '')::uuid;
    v_specific_user_id := nullif(v_step ->> 'specific_user_id', '')::uuid;
    v_required_approvals := coalesce((v_step ->> 'required_approvals')::integer, 1);
    v_step_status := case when v_pattern = 'sequential' and v_step_order <> 1 then 'pending' else 'active' end;

    insert into app.approval_request_steps (request_id, step_order, approver_type, role_id, specific_user_id, required_approvals, status)
    values (v_request.id, v_step_order, v_approver_type, v_role_id, v_specific_user_id, v_required_approvals, v_step_status);
  end loop;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_requested_by, 'request_approval',
    'app.approval_requests', v_request.id, 'success', null, null, to_jsonb(v_request)
  );

  return v_request;
end;
$$;

comment on function app.request_approval is
  'PLT-123: idempotent (unique on tenant_id+idempotency_key) request creation -- reads pattern/steps/threshold_required_steps/allow_self_approval from the bound published definition''s own config_items, materializes one app.approval_request_steps row per declared step, and opens the correct step(s) per pattern (sequential: only step_order=1; parallel/threshold: every step at once). Refuses to create a request against any step with zero currently-eligible approvers (Prompt 123 §23''s "no approver" exception case, checked proactively rather than left to silently stall). ATW-031 (ISS-2026-029): a replayed idempotency key bound to a DIFFERENT target (entity_type/entity_id/config_version_id) raises idempotency_key_conflict rather than silently misattributing or discarding the request. ISS-2026-044 fix (Track B Batch 2): the INSERT itself is now wrapped in a unique_violation handler, so two genuinely concurrent callers with the identical idempotency key (and the identical target) both resolve to the same winning row instead of the loser crashing with a raw, unhandled constraint-violation error -- closes this class at app.request_approval''s own single shared choke point for every domain composing the Platform Approval Engine.';
