-- CG-S10-ATW-031 (post-Prompt-248 codebase audit, part 2 — closes `ISS-2026-029`).
-- Completes the repair `CG-S10-ATW-030` began. `ATW-030` closed the unguarded
-- idempotent-replay defect in the 20 Phase 5 WMS mutation functions where it was first
-- live-reproduced; `ISS-2026-029` recorded that the identical defect class remained open
-- across Platform Core, Operations, Finance and Advanced TMS. This migration closes it
-- there — 27 functions, 29 replay short-circuits.
--
-- The defect: a replay short-circuit that matches on the idempotency key alone and
-- returns the found row without checking it belongs to the target the caller named.
-- Two damage shapes, both live-reproduced in the WMS half at `ATW-030`:
--   (a) MISATTRIBUTION — the caller receives a DIFFERENT target's row and believes it
--       is their own. `app.initiate_file_upload` was the starkest case here, and its own
--       db-test had BAKED THE DEFECT IN: the test's "replay" call passed a fresh
--       `gen_random_uuid()` as `p_record_id`, so it was never a replay at all — it was an
--       upload against a genuinely different record that the unguarded short-circuit
--       answered with the FIRST record's file row, and the test asserted that as correct.
--       That is precisely why no prior checkpoint caught this class: the suite encoded
--       the same assumption as the code. The fixture is corrected in this checkpoint.
--   (b) SILENT NO-OP — the function returns the freshly-read parent row, so the caller
--       sees success while the requested operation never happened. The Finance
--       open-item events are the sharpest instance: `apply_finance_ar_allocation` and
--       `reverse_finance_ar_allocation` write the SAME table under the SAME
--       `(tenant_id, open_item_id, idempotency_key)` unique key, so reusing a key to
--       reverse an allocation it had previously applied silently did nothing and
--       returned the open item unchanged — the reversal never posted, on a
--       Finance-schema record. `apply_finance_ap_settlement`/`reverse_finance_ap_settlement`
--       and `prepare_finance_journal_reversal`/`prepare_finance_journal_adjustment`
--       (both writing `finance_journal_corrections`) share that exact shape.
--
-- `p_idempotency_key` is user-supplied free text in this product — the Finance UI reads
-- it straight from `<input name="idempotencyKey" type="text" required>` (see
-- `app/(tenant)/[tenantSlug]/finance/**/actions.ts`). Key reuse across two different
-- operations is an ordinary operator mistake, not an attack needing a race window.
--
-- ===========================================================================
-- Scope: which functions are repaired, and which are deliberately left alone
-- ===========================================================================
--
-- A function is only a defect when its replay LOOKUP is broader than the identity of
-- the request. Where the table's own unique index already scopes the key to the parent
-- (e.g. `dispatch_commands_tenant_shipment_idempotency_unique`) AND the function's
-- lookup uses that same scope AND no further request parameter distinguishes two calls,
-- reuse across parents is legitimately allowed and nothing is wrong. Two functions are
-- in that position and are deliberately NOT modified:
--   * `app.dispatch_shipment_order` — lookup scoped by `shipment_order_id`, matching its
--     unique index exactly; `p_expected_version` is a concurrency token, not an identity.
--   * `app.allocate_finance_receipt` — lookup scoped by `receipt_id`, matching its unique
--     index exactly; `finance_receipt_allocation_batches` carries no other identity column.
--
-- A third function, `app.provision_tenant`, IS reachable by the sweep and IS unscoped
-- (its unique index is global on `idempotency_key`), but is deliberately NOT modified.
-- Its "later arguments are ignored" semantic is a RATIFIED decision, not an oversight:
-- its own committed `comment on function` states "A duplicate call with the same
-- idempotency_key returns the original row unchanged", and `scripts/db-tests/
-- tenant-lifecycle.sql` asserts it explicitly ("Same idempotency key, deliberately
-- different slug/name -- must be ignored"). It is also `service_role`-only — it carries
-- none of the user-typed free-text-key exposure that makes this defect class dangerous
-- elsewhere. Per `AGENTS.md` instruction precedence, a ratified decision is not
-- contradicted by an audit checkpoint's own inference; changing it would require its own
-- prompt and ADR. Recorded here so the next agent does not "re-discover" and silently
-- flip it.
--
-- Every other function reachable by the sweep is repaired below.
--
-- The 28 repaired split into two classes:
--   * TENANT-SCOPED LOOKUP (the silent-misattribution class): allocate_or_reserve_number, initiate_file_upload, start_workflow_instance,
--     request_approval, set_custom_field_values, enqueue_job, create_import_export_job,
--     start_epod_capture, capture_finance_receipt, prepare_finance_settlement,
--     prepare_finance_journal_reversal, prepare_finance_journal_adjustment,
--     post_inventory_movement, reserve_inventory, create_cycle_count_plan,
--     stage_finance_exchange_rate_import.
--   * PARENT-SCOPED LOOKUP, but a within-parent operation distinction the key ignores:
--     transition_shipment_order (`to_status`), ingest_milestone_event (`milestone_code`),
--     add_actual_cost_component (`category`/`source_type`), the four AR/AP open-item
--     event functions (`event_type`), create_shipment_order_from_job (`mode`/route),
--     add_shipment_leg (`sequence_no`), prepare_route_planning_scenario and
--     reserve_vehicle_capacity (requested weight/volume).
--
-- ===========================================================================
-- Method and safety
-- ===========================================================================
--
-- Every function below is its own live `pg_get_functiondef` output with ONLY the replay
-- short-circuit patched — each `if found then return X; end if;` becomes
-- `if found then if <target mismatch> then raise idempotency_key_conflict; end if;
-- return X; end if;`. No other statement, signature, volatility, security attribute,
-- search_path, grant, or comment changes. Where a function also carries an
-- `exception when unique_violation` race-handler re-read, that block is guarded too
-- (`create_cycle_count_plan`, `reserve_vehicle_capacity`) — it had the identical defect.
--
-- Comparisons use `is distinct from`, so a NULL on either side is handled correctly and
-- a legitimate NULL-valued replay is never turned into a spurious conflict.
--
-- Behavior preserved for correct callers: a genuine retry — same key, same target —
-- still replays exactly as before and returns the identical row. Only a key reused
-- across genuinely DIFFERENT targets now raises, which previously corrupted silently.
--
-- Additive and reversible: `CREATE OR REPLACE FUNCTION` on identical signatures only.
-- No table, column, index, constraint, grant, or policy is touched, and no already-
-- applied migration file is edited. Rollback = `git revert` this migration.
--
-- Per `ERR-2026-004`: this migration carries its own explicit `revoke execute on all
-- functions in schema app from public` before its final grants, the standing
-- per-migration convention since `PLT-118`.

CREATE OR REPLACE FUNCTION app.allocate_or_reserve_number(p_status text, p_config_version_id uuid, p_tenant_id uuid, p_scope_key text, p_entity_type text, p_entity_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_allocated_by text)
 RETURNS app.numbering_allocations
 LANGUAGE plpgsql
AS $function$
declare
  v_version app.config_versions;
  v_existing app.numbering_allocations;
  v_format text;
  v_reset_period text;
  v_padding integer;
  v_period_key text;
  v_seq integer;
  v_formatted text;
  v_allocation app.numbering_allocations;
begin
  if not app.check_numbering_allocation_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_version from app.config_versions where id = p_config_version_id;
  if not found or v_version.status <> 'published' then
    raise exception 'numbering_definition_not_published: config version % is not a published numbering definition', p_config_version_id
      using errcode = 'check_violation';
  end if;

  select * into v_existing from app.numbering_allocations where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
    -- conflict, never a replay. Returning the earlier target's row here silently
    -- misattributed this request to it (or silently discarded it entirely).
    if v_existing.scope_key is distinct from p_scope_key or v_existing.entity_type is distinct from p_entity_type or v_existing.entity_id is distinct from p_entity_id then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different number allocation (scope %/entity % %, not scope %/entity % %)', p_idempotency_key, v_existing.scope_key, v_existing.entity_type, v_existing.entity_id, p_scope_key, p_entity_type, p_entity_id
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  select value #>> '{}' into v_format from app.config_items where config_version_id = p_config_version_id and key = 'format';
  select value #>> '{}' into v_reset_period from app.config_items where config_version_id = p_config_version_id and key = 'reset_period';
  select (value #>> '{}')::integer into v_padding from app.config_items where config_version_id = p_config_version_id and key = 'padding';

  v_period_key := case v_reset_period
    when 'never' then 'ALL'
    when 'yearly' then to_char(now(), 'YYYY')
    when 'monthly' then to_char(now(), 'YYYY-MM')
    when 'daily' then to_char(now(), 'YYYY-MM-DD')
  end;

  v_seq := app.allocate_numbering_seq(p_config_version_id, coalesce(p_scope_key, 'default'), v_period_key);
  v_formatted := app.format_numbering_value(v_format, v_seq, v_padding, p_scope_key, now());

  insert into app.numbering_allocations (
    tenant_id, config_version_id, scope_key, period_key, seq, formatted_number,
    entity_type, entity_id, status, idempotency_key, allocated_by
  )
  values (
    p_tenant_id, p_config_version_id, coalesce(p_scope_key, 'default'), v_period_key, v_seq, v_formatted,
    coalesce(p_entity_type, 'generic'), p_entity_id, p_status, p_idempotency_key, p_allocated_by
  )
  returning * into v_allocation;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_allocated_by,
    case when p_status = 'reserved' then 'reserve_number' else 'allocate_number' end,
    'app.numbering_allocations', v_allocation.id, 'success', null, null, to_jsonb(v_allocation)
  );

  return v_allocation;
end;
$function$;

CREATE OR REPLACE FUNCTION app.initiate_file_upload(p_tenant_id uuid, p_document_type_code text, p_record_type text, p_record_id uuid, p_original_filename text, p_mime_type text, p_size_bytes bigint, p_classification text, p_legal_hold boolean, p_legal_hold_reason text, p_shared_org_unit_ids uuid[], p_customer_account_ref text, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.files
 LANGUAGE plpgsql
AS $function$
declare
  v_existing app.files;
  v_def record;
  v_effective_classification text;
  v_new_id uuid := gen_random_uuid();
  v_file app.files;
begin
  if not app.check_file_action_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'file_actor_unauthorized: identity % lacks active membership in tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.files where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
    if found then
      -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
      -- conflict, never a replay. Returning the earlier target's row here silently
      -- misattributed this request to it (or silently discarded it entirely).
      if v_existing.record_type is distinct from p_record_type or v_existing.record_id is distinct from p_record_id or v_existing.document_type_code is distinct from p_document_type_code then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different file upload (record % %/document type %, not record % %/document type %)', p_idempotency_key, v_existing.record_type, v_existing.record_id, v_existing.document_type_code, p_record_type, p_record_id, p_document_type_code
          using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  if p_original_filename is null or length(p_original_filename) = 0 or length(p_original_filename) > 255
     or position('/' in p_original_filename) > 0
     or position('\' in p_original_filename) > 0
     or position('..' in p_original_filename) > 0
  then
    raise exception 'document_unsafe_filename: filename is missing, empty, too long, or contains a path separator/traversal sequence'
      using errcode = 'check_violation';
  end if;

  select * into v_def from app.resolve_document_type_definition(p_tenant_id, p_document_type_code);

  if not exists (
    select 1 from jsonb_array_elements_text(v_def.allowed_mime_types) as t(mime) where t.mime = p_mime_type
  ) then
    raise exception 'document_mime_type_not_allowed: % is not an allowed MIME type for document type %', p_mime_type, p_document_type_code
      using errcode = 'check_violation';
  end if;

  if p_size_bytes <= 0 or p_size_bytes > v_def.max_size_bytes then
    raise exception 'document_file_too_large: % bytes exceeds the % byte limit for document type % (or is not positive)', p_size_bytes, v_def.max_size_bytes, p_document_type_code
      using errcode = 'check_violation';
  end if;

  v_effective_classification := coalesce(p_classification, v_def.default_classification);
  if app.classification_level_rank(v_effective_classification) is null then
    raise exception 'document_invalid_classification: % is not a recognized sensitivity level', v_effective_classification
      using errcode = 'check_violation';
  end if;
  if app.classification_level_rank(v_effective_classification) < app.classification_level_rank(v_def.default_classification) then
    raise exception 'document_classification_too_weak: % is weaker than document type %''s default classification %', v_effective_classification, p_document_type_code, v_def.default_classification
      using errcode = 'check_violation';
  end if;

  if coalesce(p_legal_hold, false) then
    if not v_def.legal_hold_eligible then
      raise exception 'document_type_not_legal_hold_eligible: document type % may not be placed under legal hold', p_document_type_code
        using errcode = 'check_violation';
    end if;
    if p_legal_hold_reason is null or length(trim(p_legal_hold_reason)) = 0 then
      raise exception 'document_legal_hold_reason_required: legal_hold_reason is required when legal_hold is true'
        using errcode = 'check_violation';
    end if;
  end if;

  insert into app.files (
    id, tenant_id, document_type_code, config_version_id, record_type, record_id,
    classification, original_filename, mime_type, size_bytes,
    storage_path, malware_scan_status, version_group_id, version_number, is_latest_version,
    lifecycle_status, legal_hold, legal_hold_reason, uploaded_by_auth_user_id,
    shared_org_unit_ids, customer_account_ref, idempotency_key
  ) values (
    v_new_id, p_tenant_id, p_document_type_code, v_def.config_version_id, p_record_type, p_record_id,
    v_effective_classification, p_original_filename, p_mime_type, p_size_bytes,
    'tenant/' || p_tenant_id::text || '/' || p_document_type_code || '/' || v_new_id::text,
    'pending', v_new_id, 1, true,
    'active', coalesce(p_legal_hold, false), p_legal_hold_reason, p_actor_auth_user_id,
    coalesce(p_shared_org_unit_ids, array[]::uuid[]), p_customer_account_ref, p_idempotency_key
  )
  returning * into v_file;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'initiate_file_upload',
    'app.files', v_file.id, 'success', null, null, to_jsonb(v_file)
  );

  return v_file;
end;
$function$;

CREATE OR REPLACE FUNCTION app.start_workflow_instance(p_config_version_id uuid, p_tenant_id uuid, p_entity_type text, p_entity_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_started_by text)
 RETURNS app.workflow_instances
 LANGUAGE plpgsql
AS $function$
declare
  v_version app.config_versions;
  v_initial_state text;
  v_existing app.workflow_instances;
  v_instance app.workflow_instances;
begin
  if not app.check_workflow_instance_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_version from app.config_versions where id = p_config_version_id;
  if not found or v_version.status <> 'published' then
    raise exception 'workflow_definition_not_published: config version % is not a published workflow definition', p_config_version_id
      using errcode = 'check_violation';
  end if;

  select * into v_existing from app.workflow_instances where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
    -- conflict, never a replay. Returning the earlier target's row here silently
    -- misattributed this request to it (or silently discarded it entirely).
    if v_existing.entity_type is distinct from p_entity_type or v_existing.entity_id is distinct from p_entity_id or v_existing.config_version_id is distinct from p_config_version_id then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different workflow instance (entity % %, not % %)', p_idempotency_key, v_existing.entity_type, v_existing.entity_id, p_entity_type, p_entity_id
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  select value #>> '{}' into v_initial_state from app.config_items where config_version_id = p_config_version_id and key = 'initial_state';
  if v_initial_state is null then
    raise exception 'workflow_definition_not_published: config version % has no initial_state item', p_config_version_id
      using errcode = 'check_violation';
  end if;

  insert into app.workflow_instances (tenant_id, config_version_id, entity_type, entity_id, current_state, idempotency_key, started_by)
  values (p_tenant_id, p_config_version_id, coalesce(p_entity_type, 'generic'), p_entity_id, v_initial_state, p_idempotency_key, p_started_by)
  returning * into v_instance;

  insert into app.workflow_transition_history (instance_id, event_type, from_state, to_state, actor_auth_user_id, actor_label, reason)
  values (v_instance.id, 'start', null, v_initial_state, p_actor_auth_user_id, p_started_by, 'workflow started');

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_started_by, 'start_workflow_instance',
    'app.workflow_instances', v_instance.id, 'success', null, null, to_jsonb(v_instance)
  );

  return v_instance;
end;
$function$;

CREATE OR REPLACE FUNCTION app.request_approval(p_config_version_id uuid, p_tenant_id uuid, p_entity_type text, p_entity_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_requested_by text)
 RETURNS app.approval_requests
 LANGUAGE plpgsql
AS $function$
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

  insert into app.approval_requests (tenant_id, config_version_id, entity_type, entity_id, pattern, idempotency_key, requested_by_auth_user_id, requested_by)
  values (p_tenant_id, p_config_version_id, coalesce(p_entity_type, 'generic'), p_entity_id, v_pattern, p_idempotency_key, p_actor_auth_user_id, p_requested_by)
  returning * into v_request;

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
$function$;

CREATE OR REPLACE FUNCTION app.set_custom_field_values(p_config_version_id uuid, p_tenant_id uuid, p_entity_type text, p_entity_id uuid, p_values jsonb, p_idempotency_key text, p_actor_auth_user_id uuid, p_submitted_by text)
 RETURNS app.custom_field_values
 LANGUAGE plpgsql
AS $function$
declare
  v_version app.config_versions;
  v_existing_by_key app.custom_field_values;
  v_existing_by_entity app.custom_field_values;
  v_row app.custom_field_values;
begin
  if not app.check_custom_field_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_version from app.config_versions where id = p_config_version_id;
  if not found or v_version.status <> 'published' then
    raise exception 'custom_field_definition_not_published: config version % is not a published form definition', p_config_version_id
      using errcode = 'check_violation';
  end if;

  select * into v_existing_by_key from app.custom_field_values where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
    -- conflict, never a replay. Returning the earlier target's row here silently
    -- misattributed this request to it (or silently discarded it entirely).
    if v_existing_by_key.entity_type is distinct from p_entity_type or v_existing_by_key.entity_id is distinct from p_entity_id or v_existing_by_key.config_version_id is distinct from p_config_version_id then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different custom field value set (entity % %, not % %)', p_idempotency_key, v_existing_by_key.entity_type, v_existing_by_key.entity_id, p_entity_type, p_entity_id
        using errcode = 'unique_violation';
    end if;
    return v_existing_by_key;
  end if;

  perform app.validate_custom_field_values(p_config_version_id, p_values);

  select * into v_existing_by_entity from app.custom_field_values where tenant_id = p_tenant_id and entity_type = coalesce(p_entity_type, 'generic') and entity_id = p_entity_id;

  if found then
    update app.custom_field_values
    set config_version_id = p_config_version_id, values = p_values, idempotency_key = p_idempotency_key,
        submitted_by_auth_user_id = p_actor_auth_user_id, submitted_by = p_submitted_by
    where id = v_existing_by_entity.id
    returning * into v_row;
  else
    insert into app.custom_field_values (tenant_id, config_version_id, entity_type, entity_id, values, submitted_by_auth_user_id, submitted_by, idempotency_key)
    values (p_tenant_id, p_config_version_id, coalesce(p_entity_type, 'generic'), p_entity_id, p_values, p_actor_auth_user_id, p_submitted_by, p_idempotency_key)
    returning * into v_row;
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_submitted_by, 'set_custom_field_values',
    'app.custom_field_values', v_row.id, 'success', null, to_jsonb(v_existing_by_entity), to_jsonb(v_row)
  );

  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION app.enqueue_job(p_tenant_id uuid, p_job_type text, p_payload jsonb, p_priority integer, p_idempotency_key text, p_max_attempts integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.jobs
 LANGUAGE plpgsql
AS $function$
declare
  v_existing app.jobs;
  v_job app.jobs;
  v_valid_job_types text[] := array[
    'report_generation', 'notification_batch', 'webhook_retry', 'document_generation',
    'dashboard_refresh', 'loyalty_expiration', 'recurring_billing', 'integration_sync',
    'route_load_planning', 'print_label'
  ];
begin
  if not app.check_job_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'job_actor_unauthorized: identity % lacks active membership in tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_job_type in ('import', 'export') then
    raise exception 'job_type_requires_dedicated_entrypoint: % jobs must be created via app.create_import_export_job()', p_job_type
      using errcode = 'check_violation';
  end if;

  if not (p_job_type = any (v_valid_job_types)) then
    raise exception 'job_invalid_type: % is not a known generic job type', p_job_type
      using errcode = 'check_violation';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.jobs where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
    if found then
      -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
      -- conflict, never a replay. Returning the earlier target's row here silently
      -- misattributed this request to it (or silently discarded it entirely).
      if v_existing.job_type is distinct from p_job_type then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different job (job type %, not %)', p_idempotency_key, v_existing.job_type, p_job_type
          using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  if not app.validate_config_value(coalesce(p_payload, '{}'::jsonb)) then
    raise exception 'job_unsafe_payload: payload failed structural validation'
      using errcode = 'check_violation';
  end if;

  if coalesce(p_max_attempts, 3) <= 0 then
    raise exception 'job_invalid_max_attempts: max_attempts must be positive'
      using errcode = 'check_violation';
  end if;

  insert into app.jobs (
    tenant_id, job_type, payload, priority, max_attempts, idempotency_key,
    requested_by_auth_user_id, created_by
  ) values (
    p_tenant_id, p_job_type, coalesce(p_payload, '{}'::jsonb), coalesce(p_priority, 0), coalesce(p_max_attempts, 3), p_idempotency_key,
    p_actor_auth_user_id, p_actor_label
  )
  returning * into v_job;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'enqueue_job',
    'app.jobs', v_job.job_id, 'success', null, null,
    jsonb_build_object('job_id', v_job.job_id, 'job_type', v_job.job_type)
  );

  return v_job;
end;
$function$;

CREATE OR REPLACE FUNCTION app.create_import_export_job(p_tenant_id uuid, p_job_type text, p_schema_code text, p_source_file_id uuid, p_filters jsonb, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.jobs
 LANGUAGE plpgsql
AS $function$
declare
  v_existing app.jobs;
  v_def record;
  v_job app.jobs;
begin
  if not app.check_import_export_job_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'job_actor_unauthorized: identity % lacks active membership in tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not (p_job_type = any (array['import', 'export'])) then
    raise exception 'import_export_invalid_job_type: % is not one of import/export', p_job_type
      using errcode = 'check_violation';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.jobs where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
    if found then
      -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
      -- conflict, never a replay. Returning the earlier target's row here silently
      -- misattributed this request to it (or silently discarded it entirely).
      if v_existing.job_type is distinct from p_job_type then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different import/export job (job type %, not %)', p_idempotency_key, v_existing.job_type, p_job_type
          using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  if not app.validate_config_value(coalesce(p_filters, '{}'::jsonb)) then
    raise exception 'import_export_unsafe_payload: filters failed structural validation'
      using errcode = 'check_violation';
  end if;

  select * into v_def from app.resolve_import_export_schema_columns(p_tenant_id, p_schema_code);

  if p_job_type = 'import' then
    if p_source_file_id is null then
      raise exception 'import_missing_source_file: an import job requires a source_file_id'
        using errcode = 'check_violation';
    end if;
    if not exists (select 1 from app.files f where f.id = p_source_file_id and f.tenant_id = p_tenant_id) then
      raise exception 'import_source_file_not_found: no file % in tenant %', p_source_file_id, p_tenant_id
        using errcode = 'no_data_found';
    end if;
  else
    if p_source_file_id is not null then
      raise exception 'export_unexpected_source_file: an export job may not reference a source_file_id'
        using errcode = 'check_violation';
    end if;
  end if;

  insert into app.jobs (
    tenant_id, job_type, payload, requested_by_auth_user_id, idempotency_key,
    import_export_schema_code, source_file_id, created_by
  ) values (
    p_tenant_id, p_job_type, coalesce(p_filters, '{}'::jsonb), p_actor_auth_user_id, p_idempotency_key,
    p_schema_code, p_source_file_id, p_actor_label
  )
  returning * into v_job;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_import_export_job',
    'app.jobs', v_job.job_id, 'success', null, null,
    jsonb_build_object('job_id', v_job.job_id, 'job_type', v_job.job_type, 'schema_code', p_schema_code)
  );

  return v_job;
end;
$function$;

CREATE OR REPLACE FUNCTION app.transition_shipment_order(p_shipment_order_id uuid, p_to_status text, p_expected_version integer, p_reason text, p_evidence_ref text, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.shipment_orders
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_existing_transition app.shipment_status_transitions;
  v_from_status text;
  v_next_status text;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: a non-empty idempotency key is required' using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  select * into v_existing_transition from app.shipment_status_transitions
  where tenant_id = v_shipment.tenant_id and shipment_order_id = p_shipment_order_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
    -- conflict, never a replay. Returning the earlier target's row here silently
    -- misattributed this request to it (or silently discarded it entirely).
    if v_existing_transition.to_status is distinct from p_to_status then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different status transition (transition to %, not to %)', p_idempotency_key, v_existing_transition.to_status, p_to_status
        using errcode = 'unique_violation';
    end if;
    return v_shipment;
  end if;

  if v_shipment.record_version <> p_expected_version then
    raise exception 'stale_version: shipment order % expected version % but found %', p_shipment_order_id, p_expected_version, v_shipment.record_version
      using errcode = 'serialization_failure';
  end if;

  v_from_status := v_shipment.status;

  -- The canonical matrix. 'held'/'cancelled' branch off most active states; 'held'
  -- resumes only into its own recorded held_from_status; 'closed' may only reopen
  -- into 'delivered'/'epod' (Supreme-only, checked below), never further back.
  if v_from_status = 'held' then
    if p_to_status <> v_shipment.held_from_status and p_to_status <> 'cancelled' then
      raise exception 'invalid_transition: a held shipment order % may only resume into % or cancel', p_shipment_order_id, v_shipment.held_from_status
        using errcode = 'check_violation';
    end if;
  elsif v_from_status = 'closed' then
    if p_to_status not in ('delivered', 'epod') then
      raise exception 'invalid_transition: shipment order % is closed and may only reopen into delivered or epod', p_shipment_order_id
        using errcode = 'check_violation';
    end if;
    if not app.is_supreme_admin(p_actor_auth_user_id) then
      raise exception 'insufficient_authority: reopening a closed shipment order requires Supreme Admin authority (RPD-022)'
        using errcode = 'insufficient_privilege';
    end if;
  elsif v_from_status = 'cancelled' then
    raise exception 'invalid_transition: shipment order % is cancelled, a terminal state', p_shipment_order_id using errcode = 'check_violation';
  elsif v_from_status = 'draft' and p_to_status in ('confirmed', 'cancelled') then
    null;
  elsif v_from_status in ('confirmed', 'planned', 'assigned', 'dispatched', 'in_transit') and p_to_status in ('held', 'cancelled') then
    null;
  elsif v_from_status = 'confirmed' and p_to_status = 'planned' then
    null;
  elsif v_from_status = 'planned' and p_to_status = 'assigned' then
    null;
  elsif v_from_status = 'assigned' and p_to_status = 'dispatched' then
    null;
  elsif v_from_status = 'dispatched' and p_to_status = 'in_transit' then
    null;
  elsif v_from_status = 'in_transit' and p_to_status = 'delivered' then
    null;
  elsif v_from_status = 'delivered' and p_to_status in ('epod', 'cancelled') then
    null;
  elsif v_from_status = 'epod' and p_to_status = 'closed' then
    null;
  else
    raise exception 'invalid_transition: % -> % is not a legal Shipment Order transition', v_from_status, p_to_status
      using errcode = 'check_violation';
  end if;

  if p_to_status in ('held', 'cancelled') and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'reason_required: a non-empty reason is required to enter %', p_to_status using errcode = 'check_violation';
  end if;

  if p_to_status in ('delivered', 'epod', 'closed') and (p_evidence_ref is null or length(trim(p_evidence_ref)) = 0) then
    raise exception 'evidence_required: a non-empty evidence reference is required to enter %', p_to_status using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  v_next_status := p_to_status;

  begin
    insert into app.shipment_status_transitions (
      tenant_id, shipment_order_id, from_status, to_status, reason, evidence_ref, idempotency_key, actor_auth_user_id, actor_label
    ) values (
      v_shipment.tenant_id, p_shipment_order_id, v_from_status, v_next_status, p_reason, p_evidence_ref, p_idempotency_key, p_actor_auth_user_id, p_actor_label
    );
  exception
    when unique_violation then
      select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
      return v_shipment;
  end;

  update app.shipment_orders
  set status = v_next_status,
      held_from_status = case when v_next_status = 'held' then v_from_status else null end
  where id = p_shipment_order_id and record_version = p_expected_version
  returning * into v_shipment;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'transition_shipment_order',
    'app.shipment_orders', v_shipment.id, 'success', null,
    jsonb_build_object('status', v_from_status),
    jsonb_build_object('status', v_next_status, 'reason', p_reason, 'evidence_ref', p_evidence_ref)
  );

  return v_shipment;
end;
$function$;

CREATE OR REPLACE FUNCTION app.ingest_milestone_event(p_shipment_order_id uuid, p_milestone_code text, p_event_time timestamp with time zone, p_received_time timestamp with time zone, p_location jsonb, p_source text, p_reason text, p_corrects_event_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text, p_source_class text DEFAULT NULL::text, p_source_confidence_score numeric DEFAULT NULL::numeric, p_source_freshness_status text DEFAULT NULL::text, p_source_candidate_id uuid DEFAULT NULL::uuid)
 RETURNS app.milestone_events
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_corrected app.milestone_events;
  v_next_seq integer;
  v_event app.milestone_events;
begin
  if p_source not in ('manual', 'api', 'webhook', 'import', 'system') then
    raise exception 'milestone_invalid_source: % is not one of manual/api/webhook/import/system', p_source using errcode = 'check_violation';
  end if;
  if not exists (select 1 from app.milestone_codes where code = p_milestone_code) then
    raise exception 'milestone_unknown_code: % is not a registered milestone code', p_milestone_code using errcode = 'check_violation';
  end if;
  if p_source_class is not null and p_source_class not in ('driver_mobile', 'direct_device', 'third_party_platform') then
    raise exception 'milestone_invalid_source_class: % is not a supported telemetry source class', p_source_class using errcode = 'check_violation';
  end if;
  if p_source_confidence_score is not null and (p_source_confidence_score < 0 or p_source_confidence_score > 1) then
    raise exception 'milestone_invalid_confidence: source_confidence_score must be between 0 and 1' using errcode = 'check_violation';
  end if;
  if p_source_freshness_status is not null and p_source_freshness_status not in ('healthy', 'stale', 'offline') then
    raise exception 'milestone_invalid_freshness: % is not a supported freshness status', p_source_freshness_status using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;
  if v_shipment.status = 'cancelled' then
    raise exception 'invalid_transition: shipment order % is cancelled and can no longer receive milestone events', p_shipment_order_id
      using errcode = 'check_violation';
  end if;

  if p_corrects_event_id is not null then
    if p_reason is null or length(trim(p_reason)) = 0 then
      raise exception 'reason_required: a correction requires a non-empty reason' using errcode = 'check_violation';
    end if;
    select * into v_corrected from app.milestone_events where id = p_corrects_event_id and shipment_order_id = p_shipment_order_id;
    if not found then
      raise exception 'milestone_event_not_found: % is not a prior event on shipment order %', p_corrects_event_id, p_shipment_order_id
        using errcode = 'no_data_found';
    end if;
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_event from app.milestone_events where tenant_id = v_shipment.tenant_id and shipment_order_id = p_shipment_order_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
    -- conflict, never a replay. Returning the earlier target's row here silently
    -- misattributed this request to it (or silently discarded it entirely).
    if v_event.milestone_code is distinct from p_milestone_code then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different milestone event (milestone %, not %)', p_idempotency_key, v_event.milestone_code, p_milestone_code
        using errcode = 'unique_violation';
    end if;
    return v_event;
  end if;

  select coalesce(max(sequence_no), 0) + 1 into v_next_seq from app.milestone_events where shipment_order_id = p_shipment_order_id;

  insert into app.milestone_events (
    tenant_id, shipment_order_id, milestone_code, event_time, received_time, location, source, reason, corrects_event_id, idempotency_key, sequence_no, created_by,
    source_class, source_confidence_score, source_freshness_status, source_candidate_id
  ) values (
    v_shipment.tenant_id, p_shipment_order_id, p_milestone_code, p_event_time, coalesce(p_received_time, now()), p_location, p_source, p_reason, p_corrects_event_id, p_idempotency_key, v_next_seq, p_actor_label,
    p_source_class, p_source_confidence_score, p_source_freshness_status, p_source_candidate_id
  )
  returning * into v_event;

  perform app.recalculate_shipment_milestone_projection(p_shipment_order_id);

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'ingest_milestone_event',
    'app.milestone_events', v_event.id, 'success', null, null,
    jsonb_build_object('shipment_order_id', p_shipment_order_id, 'milestone_code', p_milestone_code, 'source', p_source, 'corrects_event_id', p_corrects_event_id, 'source_class', p_source_class)
  );

  return v_event;
exception
  when unique_violation then
    select * into v_event from app.milestone_events where tenant_id = v_shipment.tenant_id and shipment_order_id = p_shipment_order_id and idempotency_key = p_idempotency_key;
    return v_event;
end;
$function$;

CREATE OR REPLACE FUNCTION app.start_epod_capture(p_tenant_id uuid, p_shipment_order_id uuid, p_milestone_event_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.epod_captures
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_existing app.epod_captures;
  v_new_id uuid := gen_random_uuid();
  v_capture app.epod_captures;
begin
  select * into v_shipment from app.shipment_orders so where so.id = p_shipment_order_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.epod_captures where tenant_id = v_shipment.tenant_id and idempotency_key = p_idempotency_key;
    if found then
      -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
      -- conflict, never a replay. Returning the earlier target's row here silently
      -- misattributed this request to it (or silently discarded it entirely).
      if v_existing.shipment_order_id is distinct from p_shipment_order_id then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different ePOD capture (shipment order %, not %)', p_idempotency_key, v_existing.shipment_order_id, p_shipment_order_id
          using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  if v_shipment.status <> 'delivered' then
    raise exception 'epod_shipment_not_delivered: shipment order % is % -- ePOD capture may only begin once a shipment reaches delivered', p_shipment_order_id, v_shipment.status
      using errcode = 'check_violation';
  end if;

  insert into app.epod_captures (id, tenant_id, shipment_order_id, milestone_event_id, version_group_id, version_number, is_latest_version, status, idempotency_key, created_by)
  values (v_new_id, v_shipment.tenant_id, p_shipment_order_id, p_milestone_event_id, v_new_id, 1, true, 'draft', p_idempotency_key, p_actor_label)
  returning * into v_capture;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'start_epod_capture',
    'app.epod_captures', v_capture.id, 'success', null, null, to_jsonb(v_capture)
  );

  return v_capture;
end;
$function$;

CREATE OR REPLACE FUNCTION app.add_actual_cost_component(p_actual_cost_id uuid, p_category text, p_source_type text, p_vendor_id uuid, p_assignment_id uuid, p_document_file_id uuid, p_description text, p_quantity numeric, p_uom text, p_rate numeric, p_minimum_charge numeric, p_surcharge numeric, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.shipment_actual_cost_components
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_cost app.shipment_actual_costs;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_existing app.shipment_actual_cost_components;
  v_amount numeric(14, 2);
  v_component app.shipment_actual_cost_components;
begin
  select * into v_cost from app.shipment_actual_costs where id = p_actual_cost_id;
  if not found then
    raise exception 'actual_cost_not_found: %', p_actual_cost_id using errcode = 'no_data_found';
  end if;
  select * into v_shipment from app.shipment_orders so where so.id = v_cost.shipment_order_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_cost.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_cost.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.has_view_actual_cost(v_cost.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks OPS:View cost for tenant %', p_actor_auth_user_id, v_cost.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_cost.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_cost.status <> 'draft' then
    raise exception 'invalid_transition: actual cost % is % and cannot accept new components', p_actual_cost_id, v_cost.status
      using errcode = 'check_violation';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.shipment_actual_cost_components where actual_cost_id = p_actual_cost_id and idempotency_key = p_idempotency_key;
    if found then
      -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
      -- conflict, never a replay. Returning the earlier target's row here silently
      -- misattributed this request to it (or silently discarded it entirely).
      if v_existing.category is distinct from p_category or v_existing.source_type is distinct from p_source_type or v_existing.vendor_id is distinct from p_vendor_id or v_existing.assignment_id is distinct from p_assignment_id then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different actual cost component (category %/source %, not category %/source %)', p_idempotency_key, v_existing.category, v_existing.source_type, p_category, p_source_type
          using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  if p_source_type = 'vendor' and p_vendor_id is null then
    raise exception 'actual_cost_vendor_required: a vendor_id is required when source_type is vendor' using errcode = 'check_violation';
  end if;
  if p_assignment_id is not null and not exists (select 1 from app.resource_assignments where id = p_assignment_id and shipment_order_id = v_cost.shipment_order_id) then
    raise exception 'actual_cost_assignment_mismatch: assignment % does not belong to shipment order %', p_assignment_id, v_cost.shipment_order_id
      using errcode = 'check_violation';
  end if;
  if p_document_file_id is not null and not exists (select 1 from app.files where id = p_document_file_id and tenant_id = v_cost.tenant_id and record_type = 'shipment_order' and record_id = v_cost.shipment_order_id) then
    raise exception 'actual_cost_document_mismatch: document % does not belong to shipment order %', p_document_file_id, v_cost.shipment_order_id
      using errcode = 'check_violation';
  end if;

  v_amount := app.compute_actual_cost_component_amount(p_quantity, p_rate, p_minimum_charge, p_surcharge);

  insert into app.shipment_actual_cost_components (
    tenant_id, actual_cost_id, category, source_type, vendor_id, assignment_id, document_file_id,
    description, quantity, uom, rate, minimum_charge, surcharge, amount, currency, idempotency_key, created_by
  ) values (
    v_cost.tenant_id, p_actual_cost_id, p_category, p_source_type, p_vendor_id, p_assignment_id, p_document_file_id,
    p_description, p_quantity, p_uom, p_rate, p_minimum_charge, coalesce(p_surcharge, 0), v_amount, v_cost.currency, p_idempotency_key, p_actor_label
  )
  returning * into v_component;

  perform app.recalculate_actual_cost_total(p_actual_cost_id);

  perform app.capture_audit_event(
    v_cost.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_actual_cost_component',
    'app.shipment_actual_cost_components', v_component.id, 'success', null, null, to_jsonb(v_component)
  );

  return v_component;
end;
$function$;

CREATE OR REPLACE FUNCTION app.capture_finance_receipt(p_tenant_id uuid, p_company_id uuid, p_customer_account_id uuid, p_receipt_reference text, p_receipt_date date, p_payer_name text, p_bank_account_label text, p_currency text, p_amount numeric, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_receipts
 LANGUAGE plpgsql
AS $function$
declare
  v_receipt app.finance_receipts;
  v_period record;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_receipt_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: a non-empty idempotency_key is required' using errcode = 'check_violation';
  end if;

  select * into v_receipt from app.finance_receipts where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
    -- conflict, never a replay. Returning the earlier target's row here silently
    -- misattributed this request to it (or silently discarded it entirely).
    if v_receipt.company_id is distinct from p_company_id or v_receipt.customer_account_id is distinct from p_customer_account_id then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different receipt (company %/customer %, not company %/customer %)', p_idempotency_key, v_receipt.company_id, v_receipt.customer_account_id, p_company_id, p_customer_account_id
        using errcode = 'unique_violation';
    end if;
    return v_receipt;
  end if;

  if not exists (select 1 from app.accounts where id = p_customer_account_id and tenant_id = p_tenant_id) then
    raise exception 'finance_receipt_customer_not_found: % is not a known customer account for tenant %', p_customer_account_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;
  if not app.validate_currency_code(p_currency) then
    raise exception 'finance_receipt_unsupported_currency: % is not a registered, active currency', p_currency
      using errcode = 'check_violation';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'finance_receipt_invalid_amount: amount must be positive, got %', p_amount
      using errcode = 'check_violation';
  end if;

  select * into v_period from app.resolve_finance_period_for_date(p_tenant_id, p_company_id, p_receipt_date);
  if not found then
    raise exception 'finance_receipt_period_not_found: no fiscal period covers %', p_receipt_date
      using errcode = 'no_data_found';
  end if;
  if not v_period.posting_eligible then
    raise exception 'finance_receipt_period_not_open: fiscal period % for % is not open', v_period.period_code, p_receipt_date
      using errcode = 'check_violation';
  end if;

  begin
    insert into app.finance_receipts (
      tenant_id, company_id, customer_account_id, receipt_reference, receipt_date, payer_name, bank_account_label,
      currency, amount, posting_period_id, idempotency_key, created_by
    )
    values (
      p_tenant_id, p_company_id, p_customer_account_id, p_receipt_reference, p_receipt_date, p_payer_name, p_bank_account_label,
      p_currency, p_amount, v_period.period_id, p_idempotency_key, p_actor_label
    )
    returning * into v_receipt;
  exception
    when unique_violation then
      raise exception 'finance_receipt_duplicate_reference: bank reference % already exists for tenant %', p_receipt_reference, p_tenant_id
        using errcode = 'unique_violation';
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'capture_finance_receipt',
    'app.finance_receipts', v_receipt.id, 'success', null, null, to_jsonb(v_receipt)
  );

  return v_receipt;
end;
$function$;

CREATE OR REPLACE FUNCTION app.prepare_finance_settlement(p_tenant_id uuid, p_company_id uuid, p_vendor_master_id uuid, p_payment_reference text, p_bank_account_label text, p_currency text, p_settlement_date date, p_allocations jsonb, p_fee_amount numeric, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_settlements
 LANGUAGE plpgsql
AS $function$
declare
  v_settlement app.finance_settlements;
  v_vendor app.master_records;
  v_item jsonb;
  v_open_item_id uuid;
  v_amount numeric;
  v_open_item app.finance_ap_open_items;
  v_total numeric := 0;
  v_fee numeric := coalesce(p_fee_amount, 0);
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_settlement_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: a non-empty idempotency_key is required' using errcode = 'check_violation';
  end if;

  select * into v_settlement from app.finance_settlements where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
    -- conflict, never a replay. Returning the earlier target's row here silently
    -- misattributed this request to it (or silently discarded it entirely).
    if v_settlement.company_id is distinct from p_company_id or v_settlement.vendor_master_id is distinct from p_vendor_master_id then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different settlement (company %/vendor %, not company %/vendor %)', p_idempotency_key, v_settlement.company_id, v_settlement.vendor_master_id, p_company_id, p_vendor_master_id
        using errcode = 'unique_violation';
    end if;
    return v_settlement;
  end if;

  select * into v_vendor from app.master_records
    where id = p_vendor_master_id and master_type_code = 'vendor' and canonical_status = 'active'
      and (tenant_id = p_tenant_id or tenant_id is null);
  if not found then
    raise exception 'finance_settlement_vendor_not_found: % is not a known active vendor reference for tenant %', p_vendor_master_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;

  if not app.validate_currency_code(p_currency) then
    raise exception 'finance_settlement_unsupported_currency: % is not a registered, active currency', p_currency
      using errcode = 'check_violation';
  end if;
  if v_fee < 0 then
    raise exception 'finance_settlement_invalid_fee: fee amount must not be negative, got %', v_fee
      using errcode = 'check_violation';
  end if;
  if p_allocations is null or jsonb_array_length(p_allocations) = 0 then
    raise exception 'finance_settlement_empty_allocation: at least one AP allocation line is required' using errcode = 'check_violation';
  end if;

  for v_item in select * from jsonb_array_elements(p_allocations) loop
    v_open_item_id := (v_item ->> 'apOpenItemId')::uuid;
    v_amount := (v_item ->> 'amount')::numeric;
    if v_amount is null or v_amount <= 0 then
      raise exception 'finance_settlement_invalid_allocation_amount: allocation amount must be positive, got %', v_amount
        using errcode = 'check_violation';
    end if;

    select * into v_open_item from app.finance_ap_open_items where id = v_open_item_id and tenant_id = p_tenant_id;
    if not found then
      raise exception 'finance_settlement_open_item_not_found: % is not a known AP open item for tenant %', v_open_item_id, p_tenant_id
        using errcode = 'no_data_found';
    end if;
    if v_open_item.vendor_master_id <> p_vendor_master_id then
      raise exception 'finance_settlement_vendor_mismatch: AP open item % does not belong to vendor %', v_open_item_id, p_vendor_master_id
        using errcode = 'check_violation';
    end if;
    if v_open_item.currency <> p_currency then
      raise exception 'finance_settlement_currency_mismatch: AP open item % is % but settlement is %', v_open_item_id, v_open_item.currency, p_currency
        using errcode = 'check_violation';
    end if;
    if v_open_item.is_held then
      raise exception 'finance_settlement_open_item_held: AP open item % is held and cannot be settled', v_open_item_id
        using errcode = 'check_violation';
    end if;
    if v_open_item.status = 'settled' then
      raise exception 'finance_settlement_open_item_already_settled: AP open item % is already fully settled', v_open_item_id
        using errcode = 'check_violation';
    end if;
    if v_amount > v_open_item.open_amount then
      raise exception 'finance_settlement_over_allocation: allocation % exceeds open amount % for AP open item %', v_amount, v_open_item.open_amount, v_open_item_id
        using errcode = 'check_violation';
    end if;

    v_total := v_total + v_amount;
  end loop;

  insert into app.finance_settlements (
    tenant_id, company_id, vendor_master_id, payment_reference, bank_account_label,
    currency, allocated_amount, fee_amount, settlement_date, idempotency_key, created_by
  )
  values (
    p_tenant_id, p_company_id, p_vendor_master_id, p_payment_reference, p_bank_account_label,
    p_currency, v_total, v_fee, p_settlement_date, p_idempotency_key, p_actor_label
  )
  returning * into v_settlement;

  for v_item in select * from jsonb_array_elements(p_allocations) loop
    insert into app.finance_settlement_allocations (tenant_id, settlement_id, ap_open_item_id, amount)
    values (p_tenant_id, v_settlement.id, (v_item ->> 'apOpenItemId')::uuid, (v_item ->> 'amount')::numeric);
  end loop;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'prepare_finance_settlement',
    'app.finance_settlements', v_settlement.id, 'success', null, null, to_jsonb(v_settlement)
  );

  return v_settlement;
end;
$function$;

CREATE OR REPLACE FUNCTION app.prepare_finance_journal_reversal(p_tenant_id uuid, p_company_id uuid, p_original_journal_id uuid, p_correction_date date, p_reason text, p_evidence_ref text, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_journal_corrections
 LANGUAGE plpgsql
AS $function$
declare
  v_correction app.finance_journal_corrections;
  v_original app.finance_journals;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_correction_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: a non-empty idempotency_key is required' using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_correction_reason_required: a non-empty reason is required' using errcode = 'check_violation';
  end if;

  select * into v_correction from app.finance_journal_corrections where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
    -- conflict, never a replay. Returning the earlier target's row here silently
    -- misattributed this request to it (or silently discarded it entirely).
    if v_correction.original_journal_id is distinct from p_original_journal_id or v_correction.correction_type is distinct from 'reversal' or v_correction.company_id is distinct from p_company_id then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different journal correction (journal %/type %, not journal %/type reversal)', p_idempotency_key, v_correction.original_journal_id, v_correction.correction_type, p_original_journal_id
        using errcode = 'unique_violation';
    end if;
    return v_correction;
  end if;

  select * into v_original from app.finance_journals where id = p_original_journal_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'finance_journal_not_found: % is not a known journal for tenant %', p_original_journal_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;
  if v_original.status <> 'posted' then
    raise exception 'finance_correction_original_not_posted: journal % is % not posted', p_original_journal_id, v_original.status
      using errcode = 'check_violation';
  end if;
  if exists (
    select 1 from app.finance_journal_corrections
    where tenant_id = p_tenant_id and original_journal_id = p_original_journal_id
      and correction_type = 'reversal' and status <> 'discarded'
  ) then
    raise exception 'finance_correction_duplicate_reversal: journal % already has an active reversal request', p_original_journal_id
      using errcode = 'check_violation';
  end if;

  insert into app.finance_journal_corrections (
    tenant_id, company_id, original_journal_id, correction_type, correction_date, reason, evidence_ref, idempotency_key, created_by
  )
  values (p_tenant_id, p_company_id, p_original_journal_id, 'reversal', p_correction_date, p_reason, p_evidence_ref, p_idempotency_key, p_actor_label)
  returning * into v_correction;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'prepare_finance_journal_reversal',
    'app.finance_journal_corrections', v_correction.id, 'success', p_reason, null, to_jsonb(v_correction)
  );

  return v_correction;
end;
$function$;

CREATE OR REPLACE FUNCTION app.prepare_finance_journal_adjustment(p_tenant_id uuid, p_company_id uuid, p_original_journal_id uuid, p_correction_date date, p_reason text, p_evidence_ref text, p_adjustment_lines jsonb, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_journal_corrections
 LANGUAGE plpgsql
AS $function$
declare
  v_correction app.finance_journal_corrections;
  v_original app.finance_journals;
  v_line jsonb;
  v_account app.finance_accounts;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_correction_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: a non-empty idempotency_key is required' using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_correction_reason_required: a non-empty reason is required' using errcode = 'check_violation';
  end if;

  select * into v_correction from app.finance_journal_corrections where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
    -- conflict, never a replay. Returning the earlier target's row here silently
    -- misattributed this request to it (or silently discarded it entirely).
    if v_correction.original_journal_id is distinct from p_original_journal_id or v_correction.correction_type is distinct from 'adjustment' or v_correction.company_id is distinct from p_company_id then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different journal correction (journal %/type %, not journal %/type adjustment)', p_idempotency_key, v_correction.original_journal_id, v_correction.correction_type, p_original_journal_id
        using errcode = 'unique_violation';
    end if;
    return v_correction;
  end if;

  select * into v_original from app.finance_journals where id = p_original_journal_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'finance_journal_not_found: % is not a known journal for tenant %', p_original_journal_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;
  if v_original.status <> 'posted' then
    raise exception 'finance_correction_original_not_posted: journal % is % not posted', p_original_journal_id, v_original.status
      using errcode = 'check_violation';
  end if;

  perform app.validate_finance_journal_line_balance(p_adjustment_lines);

  for v_line in select * from jsonb_array_elements(p_adjustment_lines) loop
    select * into v_account from app.finance_accounts where id = (v_line ->> 'accountId')::uuid and tenant_id = p_tenant_id;
    if not found then
      raise exception 'finance_journal_account_not_found: % is not a known account for tenant %', v_line ->> 'accountId', p_tenant_id
        using errcode = 'no_data_found';
    end if;
    if v_account.status <> 'active' or not v_account.is_postable then
      raise exception 'finance_journal_not_postable_account: account % is not active/postable', v_account.code
        using errcode = 'check_violation';
    end if;
  end loop;

  insert into app.finance_journal_corrections (
    tenant_id, company_id, original_journal_id, correction_type, correction_date, reason, evidence_ref, adjustment_lines, idempotency_key, created_by
  )
  values (p_tenant_id, p_company_id, p_original_journal_id, 'adjustment', p_correction_date, p_reason, p_evidence_ref, p_adjustment_lines, p_idempotency_key, p_actor_label)
  returning * into v_correction;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'prepare_finance_journal_adjustment',
    'app.finance_journal_corrections', v_correction.id, 'success', p_reason, null, to_jsonb(v_correction)
  );

  return v_correction;
end;
$function$;

CREATE OR REPLACE FUNCTION app.apply_finance_ar_allocation(p_open_item_id uuid, p_amount numeric, p_source_type text, p_source_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_ar_open_items
 LANGUAGE plpgsql
AS $function$
declare
  v_item app.finance_ar_open_items;
  v_existing_event app.finance_ar_open_item_events;
  v_new_allocated numeric;
  v_new_status text;
begin
  select * into v_item from app.finance_ar_open_items where id = p_open_item_id for update;
  if not found then
    raise exception 'finance_ar_open_item_not_found: %', p_open_item_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_ar_authority('Edit', v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing_event from app.finance_ar_open_item_events
      where tenant_id = v_item.tenant_id and open_item_id = p_open_item_id and idempotency_key = p_idempotency_key;
    if found then
      -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
      -- conflict, never a replay. Returning the earlier target's row here silently
      -- misattributed this request to it (or silently discarded it entirely).
      if v_existing_event.event_type is distinct from 'allocated' then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different AR open-item event (event type %, not allocated)', p_idempotency_key, v_existing_event.event_type
          using errcode = 'unique_violation';
      end if;
      return v_item;
    end if;
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'finance_ar_invalid_allocation_amount: allocation amount must be positive, got %', p_amount
      using errcode = 'check_violation';
  end if;
  if p_amount > v_item.open_amount then
    raise exception 'finance_ar_over_allocation: allocation % exceeds open amount % for open item %', p_amount, v_item.open_amount, p_open_item_id
      using errcode = 'check_violation';
  end if;

  v_new_allocated := v_item.allocated_amount + p_amount;
  v_new_status := case when v_new_allocated >= v_item.original_amount then 'paid' when v_new_allocated > 0 then 'partial' else 'open' end;

  update app.finance_ar_open_items
    set allocated_amount = v_new_allocated, status = v_new_status
    where id = p_open_item_id
    returning * into v_item;

  insert into app.finance_ar_open_item_events (tenant_id, open_item_id, event_type, amount_delta, source_type, source_id, idempotency_key, actor_auth_user_id, actor_label)
  values (v_item.tenant_id, v_item.id, 'allocated', p_amount, p_source_type, p_source_id, p_idempotency_key, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'apply_finance_ar_allocation',
    'app.finance_ar_open_items', v_item.id, 'success', null, null, jsonb_build_object('amount', p_amount, 'newStatus', v_new_status)
  );

  return v_item;
end;
$function$;

CREATE OR REPLACE FUNCTION app.reverse_finance_ar_allocation(p_open_item_id uuid, p_amount numeric, p_reason text, p_source_type text, p_source_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_ar_open_items
 LANGUAGE plpgsql
AS $function$
declare
  v_item app.finance_ar_open_items;
  v_existing_event app.finance_ar_open_item_events;
  v_new_allocated numeric;
  v_new_status text;
begin
  select * into v_item from app.finance_ar_open_items where id = p_open_item_id for update;
  if not found then
    raise exception 'finance_ar_open_item_not_found: %', p_open_item_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_ar_authority('Approve', v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing_event from app.finance_ar_open_item_events
      where tenant_id = v_item.tenant_id and open_item_id = p_open_item_id and idempotency_key = p_idempotency_key;
    if found then
      -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
      -- conflict, never a replay. Returning the earlier target's row here silently
      -- misattributed this request to it (or silently discarded it entirely).
      if v_existing_event.event_type is distinct from 'deallocated' then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different AR open-item event (event type %, not deallocated)', p_idempotency_key, v_existing_event.event_type
          using errcode = 'unique_violation';
      end if;
      return v_item;
    end if;
  end if;

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_ar_deallocation_reason_required: a non-empty reason is required to reverse an allocation'
      using errcode = 'check_violation';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'finance_ar_invalid_allocation_amount: reversal amount must be positive, got %', p_amount
      using errcode = 'check_violation';
  end if;
  if p_amount > v_item.allocated_amount then
    raise exception 'finance_ar_over_reversal: reversal % exceeds allocated amount % for open item %', p_amount, v_item.allocated_amount, p_open_item_id
      using errcode = 'check_violation';
  end if;

  v_new_allocated := v_item.allocated_amount - p_amount;
  v_new_status := case when v_new_allocated >= v_item.original_amount then 'paid' when v_new_allocated > 0 then 'partial' else 'open' end;

  update app.finance_ar_open_items
    set allocated_amount = v_new_allocated, status = v_new_status
    where id = p_open_item_id
    returning * into v_item;

  insert into app.finance_ar_open_item_events (tenant_id, open_item_id, event_type, amount_delta, reason, source_type, source_id, idempotency_key, actor_auth_user_id, actor_label)
  values (v_item.tenant_id, v_item.id, 'deallocated', -p_amount, p_reason, p_source_type, p_source_id, p_idempotency_key, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'reverse_finance_ar_allocation',
    'app.finance_ar_open_items', v_item.id, 'success', p_reason, null, jsonb_build_object('amount', p_amount, 'newStatus', v_new_status)
  );

  return v_item;
end;
$function$;

CREATE OR REPLACE FUNCTION app.apply_finance_ap_settlement(p_open_item_id uuid, p_amount numeric, p_source_type text, p_source_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_ap_open_items
 LANGUAGE plpgsql
AS $function$
declare
  v_item app.finance_ap_open_items;
  v_existing_event app.finance_ap_open_item_events;
  v_new_settled numeric;
  v_new_status text;
begin
  select * into v_item from app.finance_ap_open_items where id = p_open_item_id for update;
  if not found then
    raise exception 'finance_ap_open_item_not_found: %', p_open_item_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_ap_authority('Edit', v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing_event from app.finance_ap_open_item_events
      where tenant_id = v_item.tenant_id and open_item_id = p_open_item_id and idempotency_key = p_idempotency_key;
    if found then
      -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
      -- conflict, never a replay. Returning the earlier target's row here silently
      -- misattributed this request to it (or silently discarded it entirely).
      if v_existing_event.event_type is distinct from 'settled' then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different AP open-item event (event type %, not settled)', p_idempotency_key, v_existing_event.event_type
          using errcode = 'unique_violation';
      end if;
      return v_item;
    end if;
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'finance_ap_invalid_settlement_amount: settlement amount must be positive, got %', p_amount
      using errcode = 'check_violation';
  end if;
  if p_amount > v_item.open_amount then
    raise exception 'finance_ap_over_settlement: settlement % exceeds open amount % for open item %', p_amount, v_item.open_amount, p_open_item_id
      using errcode = 'check_violation';
  end if;

  v_new_settled := v_item.settled_amount + p_amount;
  v_new_status := case when v_new_settled >= v_item.original_amount then 'settled' when v_new_settled > 0 then 'partial' else 'open' end;

  update app.finance_ap_open_items
    set settled_amount = v_new_settled, status = v_new_status
    where id = p_open_item_id
    returning * into v_item;

  insert into app.finance_ap_open_item_events (tenant_id, open_item_id, event_type, amount_delta, source_type, source_id, idempotency_key, actor_auth_user_id, actor_label)
  values (v_item.tenant_id, v_item.id, 'settled', p_amount, p_source_type, p_source_id, p_idempotency_key, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'apply_finance_ap_settlement',
    'app.finance_ap_open_items', v_item.id, 'success', null, null, jsonb_build_object('amount', p_amount, 'newStatus', v_new_status)
  );

  return v_item;
end;
$function$;

CREATE OR REPLACE FUNCTION app.reverse_finance_ap_settlement(p_open_item_id uuid, p_amount numeric, p_reason text, p_source_type text, p_source_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_ap_open_items
 LANGUAGE plpgsql
AS $function$
declare
  v_item app.finance_ap_open_items;
  v_existing_event app.finance_ap_open_item_events;
  v_new_settled numeric;
  v_new_status text;
begin
  select * into v_item from app.finance_ap_open_items where id = p_open_item_id for update;
  if not found then
    raise exception 'finance_ap_open_item_not_found: %', p_open_item_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_ap_authority('Approve', v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing_event from app.finance_ap_open_item_events
      where tenant_id = v_item.tenant_id and open_item_id = p_open_item_id and idempotency_key = p_idempotency_key;
    if found then
      -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
      -- conflict, never a replay. Returning the earlier target's row here silently
      -- misattributed this request to it (or silently discarded it entirely).
      if v_existing_event.event_type is distinct from 'unsettled' then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different AP open-item event (event type %, not unsettled)', p_idempotency_key, v_existing_event.event_type
          using errcode = 'unique_violation';
      end if;
      return v_item;
    end if;
  end if;

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_ap_unsettlement_reason_required: a non-empty reason is required to reverse a settlement'
      using errcode = 'check_violation';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'finance_ap_invalid_settlement_amount: reversal amount must be positive, got %', p_amount
      using errcode = 'check_violation';
  end if;
  if p_amount > v_item.settled_amount then
    raise exception 'finance_ap_over_reversal: reversal % exceeds settled amount % for open item %', p_amount, v_item.settled_amount, p_open_item_id
      using errcode = 'check_violation';
  end if;

  v_new_settled := v_item.settled_amount - p_amount;
  v_new_status := case when v_new_settled >= v_item.original_amount then 'settled' when v_new_settled > 0 then 'partial' else 'open' end;

  update app.finance_ap_open_items
    set settled_amount = v_new_settled, status = v_new_status
    where id = p_open_item_id
    returning * into v_item;

  insert into app.finance_ap_open_item_events (tenant_id, open_item_id, event_type, amount_delta, reason, source_type, source_id, idempotency_key, actor_auth_user_id, actor_label)
  values (v_item.tenant_id, v_item.id, 'unsettled', -p_amount, p_reason, p_source_type, p_source_id, p_idempotency_key, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'reverse_finance_ap_settlement',
    'app.finance_ap_open_items', v_item.id, 'success', p_reason, null, jsonb_build_object('amount', p_amount, 'newStatus', v_new_status)
  );

  return v_item;
end;
$function$;

CREATE OR REPLACE FUNCTION app.post_inventory_movement(p_tenant_id uuid, p_warehouse_id uuid, p_movement_type text, p_source_type text, p_source_id uuid, p_idempotency_key text, p_reason text, p_lines jsonb, p_actor_auth_user_id uuid, p_actor_label text, p_corrects_movement_id uuid DEFAULT NULL::uuid)
 RETURNS app.inventory_movements
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_warehouse app.warehouses;
  v_existing app.inventory_movements;
  v_movement app.inventory_movements;
  v_line jsonb;
  v_owner_account_id uuid;
  v_item_master_id uuid;
  v_location_id uuid;
  v_uom_code text;
  v_signed_quantity numeric;
  v_lot_number text;
  v_serial_number text;
  v_expiry_date date;
  v_status text;
  v_item app.item_masters;
  v_location app.warehouse_locations;
  v_line_count integer := 0;
  v_transfer_sum numeric := 0;
  v_new_on_hand numeric;
  v_serial_on_hand numeric;
  v_balance_id uuid;
  v_current_on_hand numeric;
begin
  select * into v_warehouse from app.warehouses where id = p_warehouse_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'warehouse_not_found: % is not a warehouse of tenant %', p_warehouse_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, p_tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot post a movement under warehouse %', p_actor_auth_user_id, p_warehouse_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_movement_type not in ('receipt', 'transfer', 'consumption', 'adjustment', 'opening_balance', 'reversal') then
    raise exception 'invalid_movement_type: % is not a recognized movement type', p_movement_type using errcode = 'check_violation';
  end if;
  if p_movement_type in ('adjustment', 'reversal') and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'invalid_reason: a non-empty reason is required for a % movement', p_movement_type using errcode = 'check_violation';
  end if;
  if p_movement_type = 'reversal' and p_corrects_movement_id is null then
    raise exception 'invalid_correction: a reversal movement requires p_corrects_movement_id' using errcode = 'check_violation';
  end if;
  if p_movement_type <> 'reversal' and p_corrects_movement_id is not null then
    raise exception 'invalid_correction: p_corrects_movement_id may only be set on a reversal movement' using errcode = 'check_violation';
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required' using errcode = 'check_violation';
  end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'invalid_lines: p_lines must be a non-empty JSON array' using errcode = 'check_violation';
  end if;

  select * into v_existing from app.inventory_movements where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
    -- conflict, never a replay. Returning the earlier target's row here silently
    -- misattributed this request to it (or silently discarded it entirely).
    if v_existing.warehouse_id is distinct from p_warehouse_id or v_existing.movement_type is distinct from p_movement_type or v_existing.source_type is distinct from p_source_type or v_existing.source_id is distinct from p_source_id then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different inventory movement (warehouse %/type %/source % %, not warehouse %/type %/source % %)', p_idempotency_key, v_existing.warehouse_id, v_existing.movement_type, v_existing.source_type, v_existing.source_id, p_warehouse_id, p_movement_type, p_source_type, p_source_id
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  -- Bug class (d), widened (design note 0b): a nested begin/exception unique_violation
  -- recovery -- nothing else has mutated yet at this point in the function, so the
  -- block's own implicit savepoint has nothing else to undo.
  begin
    insert into app.inventory_movements (tenant_id, warehouse_id, movement_type, source_type, source_id, idempotency_key, reason, posted_by, corrects_movement_id)
    values (p_tenant_id, p_warehouse_id, p_movement_type, p_source_type, p_source_id, p_idempotency_key, p_reason, p_actor_label, p_corrects_movement_id)
    returning * into v_movement;
  exception
    when unique_violation then
      raise exception 'idempotency_key_conflict: idempotency key % was already used by a different, concurrent movement request', p_idempotency_key using errcode = 'unique_violation';
  end;

  for v_line in select * from jsonb_array_elements(p_lines) loop
    v_owner_account_id := (v_line ->> 'owner_account_id')::uuid;
    v_item_master_id := (v_line ->> 'item_master_id')::uuid;
    v_location_id := (v_line ->> 'location_id')::uuid;
    v_uom_code := v_line ->> 'uom_code';
    v_signed_quantity := (v_line ->> 'signed_quantity')::numeric;
    v_lot_number := v_line ->> 'lot_number';
    v_serial_number := v_line ->> 'serial_number';
    v_expiry_date := nullif(v_line ->> 'expiry_date', '')::date;
    v_status := coalesce(v_line ->> 'status', 'on_hand');

    if v_signed_quantity is null or v_signed_quantity = 0 then
      raise exception 'invalid_quantity: signed_quantity must be non-zero' using errcode = 'check_violation';
    end if;
    if v_status not in ('on_hand', 'held', 'damaged', 'expired') then
      raise exception 'invalid_status: % is not a recognized balance status', v_status using errcode = 'check_violation';
    end if;
    if not app.validate_uom_code(v_uom_code) then
      raise exception 'invalid_uom: % is not a registered active UOM code', v_uom_code using errcode = 'check_violation';
    end if;

    select * into v_item from app.item_masters where id = v_item_master_id and tenant_id = p_tenant_id and owner_account_id = v_owner_account_id and status = 'active';
    if not found then
      raise exception 'item_not_eligible: % is not an active item master owned by account %', v_item_master_id, v_owner_account_id using errcode = 'check_violation';
    end if;

    select * into v_location from app.warehouse_locations where id = v_location_id and warehouse_id = p_warehouse_id;
    if not found then
      raise exception 'location_not_eligible: % is not a location of warehouse %', v_location_id, p_warehouse_id using errcode = 'check_violation';
    end if;

    insert into app.inventory_movement_lines (
      tenant_id, movement_id, warehouse_id, owner_account_id, item_master_id, location_id, uom_code,
      signed_quantity, lot_number, serial_number, expiry_date, status
    ) values (
      p_tenant_id, v_movement.id, p_warehouse_id, v_owner_account_id, v_item_master_id, v_location_id, v_uom_code,
      v_signed_quantity, v_lot_number, v_serial_number, v_expiry_date, v_status
    );

    -- Race-safe read-then-write (design note 1, revised) -- deliberately NOT a single
    -- INSERT ... ON CONFLICT DO UPDATE: Postgres validates a table's own CHECK constraints
    -- against the raw candidate row *before* ON CONFLICT ever redirects to the UPDATE
    -- branch, so an upsert of a raw negative delta (e.g. -20 against an existing on_hand
    -- of 100) trips inventory_balances_on_hand_check on the doomed INSERT attempt even
    -- though the real, would-be-updated balance (80) is perfectly valid. SELECT ... FOR
    -- UPDATE against the coalesce-normalized dimension tuple locks the row first (or
    -- proves none exists), the resulting on_hand is computed here in PL/pgSQL, and only
    -- that already-validated value is ever written -- the table's own check constraint
    -- becomes a pure defense-in-depth backstop, never a value the write path can trip
    -- for a legitimate movement. A concurrent first-insert race is resolved by retrying
    -- through the same loop on unique_violation, exactly like app.create_warehouse_location's
    -- own precedent (ATW-014).
    loop
      select id, on_hand into v_balance_id, v_current_on_hand
        from app.inventory_balances
        where tenant_id = p_tenant_id and warehouse_id = p_warehouse_id and owner_account_id = v_owner_account_id
          and item_master_id = v_item_master_id and location_id = v_location_id
          and coalesce(lot_number, '') = coalesce(v_lot_number, '') and coalesce(serial_number, '') = coalesce(v_serial_number, '')
          and status = v_status
        for update;

      if found then
        v_new_on_hand := v_current_on_hand + v_signed_quantity;
        if v_new_on_hand < 0 then
          raise exception 'insufficient_stock: movement would drive on_hand negative for item % at location %', v_item_master_id, v_location_id
            using errcode = 'check_violation';
        end if;
        update app.inventory_balances
          set on_hand = v_new_on_hand, updated_at = now(), record_version = record_version + 1
          where id = v_balance_id;
        exit;
      else
        v_new_on_hand := v_signed_quantity;
        if v_new_on_hand < 0 then
          raise exception 'insufficient_stock: movement would drive on_hand negative for item % at location %', v_item_master_id, v_location_id
            using errcode = 'check_violation';
        end if;
        begin
          insert into app.inventory_balances (
            tenant_id, warehouse_id, owner_account_id, item_master_id, location_id, lot_number, serial_number, status, on_hand
          ) values (
            p_tenant_id, p_warehouse_id, v_owner_account_id, v_item_master_id, v_location_id, v_lot_number, v_serial_number, v_status, v_new_on_hand
          );
          exit;
        exception
          when unique_violation then
            -- Lost a concurrent first-insert race; loop back and take the update branch.
            continue;
        end;
      end if;
    end loop;

    if v_serial_number is not null and v_item.serial_controlled then
      select on_hand into v_serial_on_hand from app.inventory_balances
        where tenant_id = p_tenant_id and warehouse_id = p_warehouse_id and item_master_id = v_item_master_id and serial_number = v_serial_number and status = v_status;
      if v_serial_on_hand > 1 then
        raise exception 'serial_conflict: serial % of item % would exceed on-hand quantity 1', v_serial_number, v_item_master_id using errcode = 'check_violation';
      end if;
    end if;

    if p_movement_type = 'transfer' then
      v_transfer_sum := v_transfer_sum + v_signed_quantity;
    end if;
    v_line_count := v_line_count + 1;
  end loop;

  if p_movement_type = 'transfer' and v_transfer_sum <> 0 then
    raise exception 'unbalanced_transfer: a transfer movement''s own lines must sum to exactly zero, got %', v_transfer_sum using errcode = 'check_violation';
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'post_inventory_movement',
    'app.inventory_movements', v_movement.id, 'success', p_reason, null,
    jsonb_build_object('movement_type', p_movement_type, 'source_type', p_source_type, 'line_count', v_line_count)
  );

  return v_movement;
end;
$function$;

CREATE OR REPLACE FUNCTION app.reserve_inventory(p_tenant_id uuid, p_warehouse_id uuid, p_owner_account_id uuid, p_item_master_id uuid, p_location_id uuid, p_lot_number text, p_serial_number text, p_quantity numeric, p_source_type text, p_source_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.inventory_reservations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_warehouse app.warehouses;
  v_balance app.inventory_balances;
  v_existing app.inventory_reservations;
  v_reservation app.inventory_reservations;
begin
  select * into v_warehouse from app.warehouses where id = p_warehouse_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'warehouse_not_found: % is not a warehouse of tenant %', p_warehouse_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, p_tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot reserve stock under warehouse %', p_actor_auth_user_id, p_warehouse_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'invalid_quantity: reservation quantity must be greater than zero' using errcode = 'check_violation';
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required' using errcode = 'check_violation';
  end if;

  select * into v_existing from app.inventory_reservations where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
    -- conflict, never a replay. Returning the earlier target's row here silently
    -- misattributed this request to it (or silently discarded it entirely).
    if v_existing.source_type is distinct from p_source_type or v_existing.source_id is distinct from p_source_id then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different inventory reservation (source % %, not source % %)', p_idempotency_key, v_existing.source_type, v_existing.source_id, p_source_type, p_source_id
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  select * into v_balance from app.inventory_balances
    where tenant_id = p_tenant_id and warehouse_id = p_warehouse_id and owner_account_id = p_owner_account_id
      and item_master_id = p_item_master_id and location_id = p_location_id
      and coalesce(lot_number, '') = coalesce(p_lot_number, '') and coalesce(serial_number, '') = coalesce(p_serial_number, '')
      and status = 'on_hand'
    for update;
  if not found then
    raise exception 'balance_not_found: no on-hand balance exists for the requested dimension' using errcode = 'no_data_found';
  end if;
  if v_balance.available < p_quantity then
    raise exception 'insufficient_available_stock: % available but % requested', v_balance.available, p_quantity using errcode = 'check_violation';
  end if;

  -- Bug class (d), widened by ATW-017 design note 0b: a nested begin/exception
  -- unique_violation recovery around BOTH the reserved-balance mutation and the
  -- reservation insert -- the block's own implicit savepoint cleanly undoes the
  -- reserved-balance increment too, so no partial effect survives a losing race.
  -- Hardening (this migration, on top of ATW-017's own fix): the reserved-balance
  -- UPDATE now also bumps record_version/updated_at identically to app.post_inventory_
  -- movement's own on_hand UPDATE, so a reservation placed against this balance is no
  -- longer invisible to any caller's own optimistic-concurrency check (e.g. ATW-020's
  -- app.approve_cycle_count_variance).
  begin
    update app.inventory_balances set reserved = reserved + p_quantity, updated_at = now(), record_version = record_version + 1 where id = v_balance.id;

    insert into app.inventory_reservations (tenant_id, balance_id, reserved_quantity, source_type, source_id, idempotency_key, created_by)
    values (p_tenant_id, v_balance.id, p_quantity, p_source_type, p_source_id, p_idempotency_key, p_actor_label)
    returning * into v_reservation;
  exception
    when unique_violation then
      raise exception 'idempotency_key_conflict: idempotency key % was already used by a different, concurrent reservation request', p_idempotency_key using errcode = 'unique_violation';
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'reserve_inventory',
    'app.inventory_reservations', v_reservation.id, 'success', null, null,
    jsonb_build_object('balance_id', v_balance.id, 'quantity', p_quantity)
  );

  return v_reservation;
end;
$function$;

CREATE OR REPLACE FUNCTION app.create_cycle_count_plan(p_tenant_id uuid, p_warehouse_id uuid, p_method text, p_variance_threshold_pct numeric, p_recount_threshold_pct numeric, p_requires_separate_approver boolean, p_scope_filter_zone_id uuid, p_scope_filter_location_id uuid, p_scope_filter_item_master_id uuid, p_scope_filter_owner_account_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.cycle_count_plans
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_warehouse app.warehouses;
  v_existing app.cycle_count_plans;
  v_plan app.cycle_count_plans;
  v_method text;
  v_number text;
  v_zone app.warehouse_zones;
  v_location app.warehouse_locations;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required to create a cycle count plan' using errcode = 'check_violation';
  end if;

  select * into v_warehouse from app.warehouses where id = p_warehouse_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'warehouse_not_found: % is not a warehouse of tenant %', p_warehouse_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, p_tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot create a cycle count plan under warehouse %', p_actor_auth_user_id, p_warehouse_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent replay short-circuit -- only after authority is confirmed above, never
  -- before.
  select * into v_existing from app.cycle_count_plans where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
    -- conflict, never a replay. Returning the earlier target's row here silently
    -- misattributed this request to it (or silently discarded it entirely).
    if v_existing.warehouse_id is distinct from p_warehouse_id then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different cycle count plan (warehouse %, not %)', p_idempotency_key, v_existing.warehouse_id, p_warehouse_id
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  v_method := coalesce(p_method, 'full');
  if v_method not in ('full', 'abc', 'spot') then
    raise exception 'invalid_method: % is not a recognized cycle count method', v_method using errcode = 'check_violation';
  end if;
  if p_variance_threshold_pct is null or p_variance_threshold_pct < 0 then
    raise exception 'invalid_variance_threshold: variance_threshold_pct must be zero or greater' using errcode = 'check_violation';
  end if;
  if p_recount_threshold_pct is null or p_recount_threshold_pct < 0 then
    raise exception 'invalid_recount_threshold: recount_threshold_pct must be zero or greater' using errcode = 'check_violation';
  end if;

  if p_scope_filter_zone_id is not null then
    select * into v_zone from app.warehouse_zones where id = p_scope_filter_zone_id;
    if not found or v_zone.warehouse_id <> p_warehouse_id then
      raise exception 'scope_filter_zone_not_found: % is not a zone of warehouse %', p_scope_filter_zone_id, p_warehouse_id using errcode = 'check_violation';
    end if;
  end if;
  if p_scope_filter_location_id is not null then
    select * into v_location from app.warehouse_locations where id = p_scope_filter_location_id;
    if not found or v_location.warehouse_id <> p_warehouse_id then
      raise exception 'scope_filter_location_not_found: % is not a location of warehouse %', p_scope_filter_location_id, p_warehouse_id using errcode = 'check_violation';
    end if;
  end if;
  if p_scope_filter_item_master_id is not null and not exists (select 1 from app.item_masters where id = p_scope_filter_item_master_id and tenant_id = p_tenant_id) then
    raise exception 'scope_filter_item_master_not_found: % is not an item master of tenant %', p_scope_filter_item_master_id, p_tenant_id using errcode = 'check_violation';
  end if;
  if p_scope_filter_owner_account_id is not null and not exists (select 1 from app.accounts where id = p_scope_filter_owner_account_id and tenant_id = p_tenant_id) then
    raise exception 'scope_filter_owner_account_not_found: % is not an account of tenant %', p_scope_filter_owner_account_id, p_tenant_id using errcode = 'check_violation';
  end if;

  v_number := app.next_cycle_count_plan_number(p_tenant_id);

  begin
    insert into app.cycle_count_plans (
      tenant_id, warehouse_id, plan_number, method, variance_threshold_pct, recount_threshold_pct, requires_separate_approver,
      scope_filter_zone_id, scope_filter_location_id, scope_filter_item_master_id, scope_filter_owner_account_id, idempotency_key, created_by
    ) values (
      p_tenant_id, p_warehouse_id, v_number, v_method, p_variance_threshold_pct, p_recount_threshold_pct, coalesce(p_requires_separate_approver, true),
      p_scope_filter_zone_id, p_scope_filter_location_id, p_scope_filter_item_master_id, p_scope_filter_owner_account_id, p_idempotency_key, p_actor_label
    )
    returning * into v_plan;
  exception
    when unique_violation then
      select * into v_existing from app.cycle_count_plans where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      if found then
        -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
        -- conflict, never a replay. Returning the earlier target's row here silently
        -- misattributed this request to it (or silently discarded it entirely).
        if v_existing.warehouse_id is distinct from p_warehouse_id then
          raise exception 'idempotency_key_conflict: idempotency key % was already used for a different cycle count plan (warehouse %, not %)', p_idempotency_key, v_existing.warehouse_id, p_warehouse_id
            using errcode = 'unique_violation';
        end if;
        return v_existing;
      end if;
      raise exception 'idempotency_key_conflict: idempotency key % was already used by a different, concurrent plan creation request', p_idempotency_key using errcode = 'unique_violation';
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_cycle_count_plan',
    'app.cycle_count_plans', v_plan.id, 'success', null, null,
    jsonb_build_object('plan_number', v_number, 'warehouse_id', p_warehouse_id, 'method', v_method)
  );

  return v_plan;
end;
$function$;

CREATE OR REPLACE FUNCTION app.create_shipment_order_from_job(p_job_order_id uuid, p_idempotency_key text, p_consignee jsonb, p_notify_party jsonb, p_service_type text, p_mode text, p_origin text, p_destination text, p_planned_pickup_at timestamp with time zone, p_planned_delivery_at timestamp with time zone, p_allocated_quantity numeric, p_allocated_weight_kg numeric, p_allocated_volume_cbm numeric, p_basis_quantity numeric, p_basis_weight_kg numeric, p_basis_volume_cbm numeric, p_split_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.shipment_orders
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
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
    -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
    -- conflict, never a replay. Returning the earlier target's row here silently
    -- misattributed this request to it (or silently discarded it entirely).
    if v_existing.mode is distinct from p_mode or v_existing.origin is distinct from p_origin or v_existing.destination is distinct from p_destination or v_existing.service_type is distinct from p_service_type then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different shipment order split (mode %/route %->%, not mode %/route %->%)', p_idempotency_key, v_existing.mode, v_existing.origin, v_existing.destination, p_mode, p_origin, p_destination
        using errcode = 'unique_violation';
    end if;
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
$function$;

CREATE OR REPLACE FUNCTION app.add_shipment_leg(p_shipment_order_id uuid, p_idempotency_key text, p_sequence_no integer, p_mode text, p_carrier_master_id uuid, p_planned_departure_at timestamp with time zone, p_planned_arrival_at timestamp with time zone, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.shipment_legs
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_existing app.shipment_legs;
  v_leg app.shipment_legs;
  v_sequence_taken boolean;
begin
  if p_mode not in ('land', 'air', 'sea') then
    raise exception 'invalid_mode: % is not a supported mode', p_mode using errcode = 'check_violation';
  end if;

  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: a non-empty idempotency key is required' using errcode = 'check_violation';
  end if;

  if p_sequence_no is null or p_sequence_no <= 0 then
    raise exception 'invalid_sequence: sequence_no must be a positive integer' using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  select * into v_existing from app.shipment_legs
    where tenant_id = v_shipment.tenant_id and shipment_order_id = p_shipment_order_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
    -- conflict, never a replay. Returning the earlier target's row here silently
    -- misattributed this request to it (or silently discarded it entirely).
    if v_existing.sequence_no is distinct from p_sequence_no or v_existing.mode is distinct from p_mode then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different shipment leg (sequence %/mode %, not sequence %/mode %)', p_idempotency_key, v_existing.sequence_no, v_existing.mode, p_sequence_no, p_mode
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  select exists (
    select 1 from app.shipment_legs where tenant_id = v_shipment.tenant_id and shipment_order_id = p_shipment_order_id and sequence_no = p_sequence_no and leg_status <> 'cancelled'
  ) into v_sequence_taken;
  if v_sequence_taken then
    raise exception 'leg_sequence_duplicate: sequence % is already used by an active leg of shipment order %', p_sequence_no, p_shipment_order_id
      using errcode = 'check_violation';
  end if;

  if p_carrier_master_id is not null then
    if not exists (
      select 1 from app.master_records
      where id = p_carrier_master_id and master_type_code in ('vendor', 'fleet') and canonical_status = 'active'
        and (tenant_id = v_shipment.tenant_id or tenant_id is null)
    ) then
      raise exception 'carrier_not_found: % is not a known active vendor/fleet reference for tenant %', p_carrier_master_id, v_shipment.tenant_id
        using errcode = 'no_data_found';
    end if;
  end if;

  begin
    insert into app.shipment_legs (
      tenant_id, shipment_order_id, sequence_no, idempotency_key, mode, carrier_master_id,
      planned_departure_at, planned_arrival_at, owner_user_id, created_by
    ) values (
      v_shipment.tenant_id, p_shipment_order_id, p_sequence_no, p_idempotency_key, p_mode, p_carrier_master_id,
      p_planned_departure_at, p_planned_arrival_at, v_shipment.owner_user_id, p_actor_label
    )
    returning * into v_leg;
  exception
    when unique_violation then
      select * into v_leg from app.shipment_legs
        where tenant_id = v_shipment.tenant_id and shipment_order_id = p_shipment_order_id and idempotency_key = p_idempotency_key;
      return v_leg;
  end;

  if v_shipment.leg_network_status = 'confirmed' then
    update app.shipment_orders set leg_network_status = 'draft' where id = p_shipment_order_id;
  elsif v_shipment.leg_network_status is null then
    update app.shipment_orders set leg_network_status = 'draft' where id = p_shipment_order_id;
  end if;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_shipment_leg',
    'app.shipment_legs', v_leg.id, 'success', null, null,
    jsonb_build_object('shipment_order_id', p_shipment_order_id, 'sequence_no', p_sequence_no, 'mode', p_mode)
  );

  return v_leg;
end;
$function$;

CREATE OR REPLACE FUNCTION app.prepare_route_planning_scenario(p_shipment_order_id uuid, p_idempotency_key text, p_requested_weight_kg numeric, p_requested_volume_cbm numeric, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.route_planning_scenarios
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_existing app.route_planning_scenarios;
  v_scenario app.route_planning_scenarios;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: a non-empty idempotency key is required' using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  select * into v_existing from app.route_planning_scenarios
    where tenant_id = v_shipment.tenant_id and shipment_order_id = p_shipment_order_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
    -- conflict, never a replay. Returning the earlier target's row here silently
    -- misattributed this request to it (or silently discarded it entirely).
    if v_existing.requested_weight_kg is distinct from p_requested_weight_kg or v_existing.requested_volume_cbm is distinct from p_requested_volume_cbm then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different route planning scenario (weight %/volume %, not weight %/volume %)', p_idempotency_key, v_existing.requested_weight_kg, v_existing.requested_volume_cbm, p_requested_weight_kg, p_requested_volume_cbm
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_requested_weight_kg is not null and p_requested_weight_kg < 0 then
    raise exception 'invalid_requested_weight: requested_weight_kg must not be negative' using errcode = 'check_violation';
  end if;
  if p_requested_volume_cbm is not null and p_requested_volume_cbm < 0 then
    raise exception 'invalid_requested_volume: requested_volume_cbm must not be negative' using errcode = 'check_violation';
  end if;

  begin
    insert into app.route_planning_scenarios (
      tenant_id, shipment_order_id, idempotency_key, requested_weight_kg, requested_volume_cbm, owner_user_id, created_by
    ) values (
      v_shipment.tenant_id, p_shipment_order_id, p_idempotency_key, p_requested_weight_kg, p_requested_volume_cbm, v_shipment.owner_user_id, p_actor_label
    )
    returning * into v_scenario;
  exception
    when unique_violation then
      select * into v_scenario from app.route_planning_scenarios
        where tenant_id = v_shipment.tenant_id and shipment_order_id = p_shipment_order_id and idempotency_key = p_idempotency_key;
      return v_scenario;
  end;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'prepare_route_planning_scenario',
    'app.route_planning_scenarios', v_scenario.id, 'success', null, null,
    jsonb_build_object('shipment_order_id', p_shipment_order_id)
  );

  return v_scenario;
end;
$function$;

CREATE OR REPLACE FUNCTION app.reserve_vehicle_capacity(p_shipment_leg_id uuid, p_requested_weight_kg numeric, p_requested_volume_cbm numeric, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.vehicle_capacity_reservations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_leg app.shipment_legs;
  v_shipment record;
  v_vehicle_master_id uuid;
  v_profile app.vehicle_operational_profiles;
  v_existing app.vehicle_capacity_reservations;
  v_reservation app.vehicle_capacity_reservations;
  v_reserved_weight numeric;
  v_reserved_volume numeric;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: a non-empty idempotency key is required' using errcode = 'check_violation';
  end if;
  if p_requested_weight_kg is not null and p_requested_weight_kg < 0 then
    raise exception 'invalid_requested_weight: requested_weight_kg must not be negative' using errcode = 'check_violation';
  end if;
  if p_requested_volume_cbm is not null and p_requested_volume_cbm < 0 then
    raise exception 'invalid_requested_volume: requested_volume_cbm must not be negative' using errcode = 'check_violation';
  end if;

  select * into v_leg from app.shipment_legs where id = p_shipment_leg_id;
  if not found then
    raise exception 'leg_not_found: %', p_shipment_leg_id using errcode = 'no_data_found';
  end if;

  select * into v_existing from app.vehicle_capacity_reservations
    where tenant_id = v_leg.tenant_id and shipment_leg_id = p_shipment_leg_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
    -- conflict, never a replay. Returning the earlier target's row here silently
    -- misattributed this request to it (or silently discarded it entirely).
    if v_existing.requested_weight_kg is distinct from p_requested_weight_kg or v_existing.requested_volume_cbm is distinct from p_requested_volume_cbm then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different capacity reservation (weight %/volume %, not weight %/volume %)', p_idempotency_key, v_existing.requested_weight_kg, v_existing.requested_volume_cbm, p_requested_weight_kg, p_requested_volume_cbm
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_leg.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_leg.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_leg.shipment_order_id;
  if not app.can_access_record(p_actor_auth_user_id, v_leg.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_leg.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_leg.planned_departure_at is null or v_leg.planned_arrival_at is null then
    raise exception 'leg_schedule_required: leg % has no planned_departure_at/planned_arrival_at to reserve a capacity window against', p_shipment_leg_id
      using errcode = 'check_violation';
  end if;

  if exists (select 1 from app.vehicle_capacity_reservations where shipment_leg_id = p_shipment_leg_id and status in ('held', 'consumed')) then
    raise exception 'reservation_already_active: leg % already has an active (held/consumed) capacity reservation -- release it before reserving again', p_shipment_leg_id
      using errcode = 'check_violation';
  end if;

  select resource_id into v_vehicle_master_id from app.resource_assignments
    where shipment_order_id = v_leg.shipment_order_id and role = 'vehicle' and is_current and status = 'active';
  if v_vehicle_master_id is null then
    raise exception 'vehicle_not_assigned: leg % (shipment order %) has no current active vehicle resource assignment', p_shipment_leg_id, v_leg.shipment_order_id
      using errcode = 'check_violation';
  end if;

  -- Row lock on the vehicle's own operational profile -- see design note 3. Every
  -- reservation attempt against this vehicle acquires this same single row lock
  -- before reading the overlapping-reservation sum, serializing concurrent attempts.
  select * into v_profile from app.vehicle_operational_profiles
    where tenant_id = v_leg.tenant_id and vehicle_master_id = v_vehicle_master_id
    for update;
  if not found or v_profile.status <> 'active' then
    raise exception 'vehicle_not_active: vehicle % is not an active operational profile', v_vehicle_master_id using errcode = 'check_violation';
  end if;

  select coalesce(sum(requested_weight_kg), 0), coalesce(sum(requested_volume_cbm), 0)
    into v_reserved_weight, v_reserved_volume
    from app.vehicle_capacity_reservations
    where tenant_id = v_leg.tenant_id
      and vehicle_master_id = v_vehicle_master_id
      and shipment_leg_id <> p_shipment_leg_id
      and status in ('held', 'consumed')
      and window_start < v_leg.planned_arrival_at
      and window_end > v_leg.planned_departure_at;

  if p_requested_weight_kg is not null and v_profile.capacity_weight_kg is not null
    and (v_reserved_weight + p_requested_weight_kg) > v_profile.capacity_weight_kg
  then
    raise exception 'capacity_exceeded: vehicle % weight capacity % kg, already holding % kg over this window, requested % kg would exceed it',
      v_vehicle_master_id, v_profile.capacity_weight_kg, v_reserved_weight, p_requested_weight_kg
      using errcode = 'check_violation';
  end if;
  if p_requested_volume_cbm is not null and v_profile.capacity_volume_cbm is not null
    and (v_reserved_volume + p_requested_volume_cbm) > v_profile.capacity_volume_cbm
  then
    raise exception 'capacity_exceeded: vehicle % volume capacity % cbm, already holding % cbm over this window, requested % cbm would exceed it',
      v_vehicle_master_id, v_profile.capacity_volume_cbm, v_reserved_volume, p_requested_volume_cbm
      using errcode = 'check_violation';
  end if;

  begin
    insert into app.vehicle_capacity_reservations (
      tenant_id, shipment_leg_id, vehicle_master_id, idempotency_key,
      requested_weight_kg, requested_volume_cbm, window_start, window_end, created_by
    ) values (
      v_leg.tenant_id, p_shipment_leg_id, v_vehicle_master_id, p_idempotency_key,
      p_requested_weight_kg, p_requested_volume_cbm, v_leg.planned_departure_at, v_leg.planned_arrival_at, p_actor_label
    )
    returning * into v_reservation;
  exception
    when unique_violation then
      select * into v_reservation from app.vehicle_capacity_reservations
        where tenant_id = v_leg.tenant_id and shipment_leg_id = p_shipment_leg_id and idempotency_key = p_idempotency_key;
      if found then
        -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
        -- conflict, never a replay. Returning the earlier target's row here silently
        -- misattributed this request to it (or silently discarded it entirely).
        if v_existing.requested_weight_kg is distinct from p_requested_weight_kg or v_existing.requested_volume_cbm is distinct from p_requested_volume_cbm then
          raise exception 'idempotency_key_conflict: idempotency key % was already used for a different capacity reservation (weight %/volume %, not weight %/volume %)', p_idempotency_key, v_existing.requested_weight_kg, v_existing.requested_volume_cbm, p_requested_weight_kg, p_requested_volume_cbm
            using errcode = 'unique_violation';
        end if;
        return v_reservation;
      end if;
      -- The pre-check above already covers the common case; this is a narrow
      -- defense-in-depth path for the disclosed single-threaded-sandbox race
      -- (design note 3) between that check and this insert.
      raise exception 'reservation_already_active: leg % already has an active (held/consumed) capacity reservation under a different idempotency key', p_shipment_leg_id
        using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    v_leg.tenant_id, p_actor_auth_user_id, p_actor_label, 'reserve_vehicle_capacity',
    'app.vehicle_capacity_reservations', v_reservation.id, 'success', null, null,
    jsonb_build_object('shipment_leg_id', p_shipment_leg_id, 'vehicle_master_id', v_vehicle_master_id, 'requested_weight_kg', p_requested_weight_kg, 'requested_volume_cbm', p_requested_volume_cbm)
  );

  return v_reservation;
end;
$function$;

CREATE OR REPLACE FUNCTION app.stage_finance_exchange_rate_import(p_tenant_id uuid, p_idempotency_key text, p_rows jsonb, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_exchange_rate_import_batches
 LANGUAGE plpgsql
AS $function$
declare
  v_batch app.finance_exchange_rate_import_batches;
  v_row jsonb;
  v_count integer := 0;
begin
  if not app.check_finance_exchange_rate_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_batch from app.finance_exchange_rate_import_batches
    where coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(p_tenant_id, '00000000-0000-0000-0000-000000000000'::uuid)
      and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
    -- conflict, never a replay. Returning the earlier target's row here silently
    -- misattributed this request to it (or silently discarded it entirely).
    if v_batch.row_count is distinct from coalesce(jsonb_array_length(p_rows), 0) then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different exchange rate import batch (row count %, not %)', p_idempotency_key, v_batch.row_count, coalesce(jsonb_array_length(p_rows), 0)
        using errcode = 'unique_violation';
    end if;
    return v_batch;
  end if;

  insert into app.finance_exchange_rate_import_batches (tenant_id, idempotency_key, created_by)
  values (p_tenant_id, p_idempotency_key, p_actor_label)
  returning * into v_batch;

  for v_row in select * from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    insert into app.finance_exchange_rates (
      tenant_id, rate_type, source_currency, target_currency, rate, source, effective_from, effective_to, import_batch_id, created_by
    )
    values (
      p_tenant_id,
      coalesce(v_row ->> 'rate_type', 'spot'),
      v_row ->> 'source_currency',
      v_row ->> 'target_currency',
      (v_row ->> 'rate')::numeric,
      coalesce(v_row ->> 'source', 'import'),
      (v_row ->> 'effective_from')::timestamptz,
      (v_row ->> 'effective_to')::timestamptz,
      v_batch.id,
      p_actor_label
    );
    v_count := v_count + 1;
  end loop;

  update app.finance_exchange_rate_import_batches set row_count = v_count where id = v_batch.id returning * into v_batch;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'stage_finance_exchange_rate_import',
    'app.finance_exchange_rate_import_batches', v_batch.id, 'success', null, null, jsonb_build_object('row_count', v_count)
  );

  return v_batch;
end;
$function$;


revoke execute on all functions in schema app from public;

-- Re-granted exactly as each function's own original migration did. CREATE OR REPLACE
-- preserves a prior grant automatically; restated here only for this migration's own
-- self-contained auditability, not structurally required and deliberately not widened.
grant execute on function app.add_actual_cost_component(uuid,text,text,uuid,uuid,uuid,text,numeric,text,numeric,numeric,numeric,text,uuid,text) to authenticated, service_role;
grant execute on function app.add_shipment_leg(uuid,text,integer,text,uuid,timestamp with time zone,timestamp with time zone,uuid,text) to authenticated, service_role;
grant execute on function app.allocate_or_reserve_number(text,uuid,uuid,text,text,uuid,text,uuid,text) to service_role;
grant execute on function app.apply_finance_ap_settlement(uuid,numeric,text,uuid,text,uuid,text) to authenticated, service_role;
grant execute on function app.apply_finance_ar_allocation(uuid,numeric,text,uuid,text,uuid,text) to authenticated, service_role;
grant execute on function app.capture_finance_receipt(uuid,uuid,uuid,text,date,text,text,text,numeric,text,uuid,text) to authenticated, service_role;
grant execute on function app.create_cycle_count_plan(uuid,uuid,text,numeric,numeric,boolean,uuid,uuid,uuid,uuid,text,uuid,text) to authenticated, service_role;
grant execute on function app.create_import_export_job(uuid,text,text,uuid,jsonb,text,uuid,text) to service_role;
grant execute on function app.create_shipment_order_from_job(uuid,text,jsonb,jsonb,text,text,text,text,timestamp with time zone,timestamp with time zone,numeric,numeric,numeric,numeric,numeric,numeric,text,uuid,text) to authenticated, service_role;
grant execute on function app.enqueue_job(uuid,text,jsonb,integer,text,integer,uuid,text) to authenticated, service_role;
grant execute on function app.ingest_milestone_event(uuid,text,timestamp with time zone,timestamp with time zone,jsonb,text,text,uuid,text,uuid,text,text,numeric,text,uuid) to authenticated, service_role;
grant execute on function app.initiate_file_upload(uuid,text,text,uuid,text,text,bigint,text,boolean,text,uuid[],text,text,uuid,text) to service_role;
grant execute on function app.post_inventory_movement(uuid,uuid,text,text,uuid,text,text,jsonb,uuid,text,uuid) to authenticated, service_role;
grant execute on function app.prepare_finance_journal_adjustment(uuid,uuid,uuid,date,text,text,jsonb,text,uuid,text) to authenticated, service_role;
grant execute on function app.prepare_finance_journal_reversal(uuid,uuid,uuid,date,text,text,text,uuid,text) to authenticated, service_role;
grant execute on function app.prepare_finance_settlement(uuid,uuid,uuid,text,text,text,date,jsonb,numeric,text,uuid,text) to authenticated, service_role;
grant execute on function app.prepare_route_planning_scenario(uuid,text,numeric,numeric,uuid,text) to authenticated, service_role;
grant execute on function app.request_approval(uuid,uuid,text,uuid,text,uuid,text) to service_role;
grant execute on function app.reserve_inventory(uuid,uuid,uuid,uuid,uuid,text,text,numeric,text,uuid,text,uuid,text) to authenticated, service_role;
grant execute on function app.reserve_vehicle_capacity(uuid,numeric,numeric,text,uuid,text) to authenticated, service_role;
grant execute on function app.reverse_finance_ap_settlement(uuid,numeric,text,text,uuid,text,uuid,text) to authenticated, service_role;
grant execute on function app.reverse_finance_ar_allocation(uuid,numeric,text,text,uuid,text,uuid,text) to authenticated, service_role;
grant execute on function app.set_custom_field_values(uuid,uuid,text,uuid,jsonb,text,uuid,text) to service_role;
grant execute on function app.stage_finance_exchange_rate_import(uuid,text,jsonb,uuid,text) to authenticated, service_role;
grant execute on function app.start_epod_capture(uuid,uuid,uuid,text,uuid,text) to authenticated, service_role;
grant execute on function app.start_workflow_instance(uuid,uuid,text,uuid,text,uuid,text) to service_role;
grant execute on function app.transition_shipment_order(uuid,text,integer,text,text,text,uuid,text) to authenticated, service_role;
