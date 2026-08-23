-- Intelligence, Automation and Enterprise Expansion: OCR Document Processing
-- (IAE-021, CG-S14-IAE-021, Prompt 349). First of Group 6 ("Further
-- AI-Assisted Capabilities", Prompts 349-353), authorized fresh this
-- checkpoint per the operator's own explicit "continue prompts 349-368"
-- instruction (00_EXECUTION_INDEX.md's own standing gate for this range).
-- Depends on IAE-019 (AI Governance Provider Boundary, VERIFIED) exactly as
-- IAE-020 (AI-Assisted Quotation) already does -- this checkpoint reuses
-- dispatchAiGovernedRequest and the AI entitlement module unmodified, adding
-- zero new module/adapter/config-type rows beyond one new document type.
--
-- Design decisions, disclosed rather than left implicit:
--
-- 1. **OCR output can NEVER reach any domain table directly -- structurally,
--    not by convention.** This migration's own table (app.ocr_document_jobs)
--    never stores the AI's own extracted field values at all; it only
--    references app.ai_governed_requests.output_payload (IAE-019's own
--    evidence ledger) by id, exactly mirroring app.ai_quotation_suggestions'
--    "three genuinely distinct tables, three genuinely distinct writers"
--    shape. The ONE apply path (app.apply_ocr_document_job_to_ticket) never
--    parses or trusts output_payload -- it takes only human-typed, explicitly
--    parameterized field values (p_subject/p_body/p_category_id/p_queue_id/
--    p_priority/p_requester_employee_id), handed unchanged to the existing,
--    UNMODIFIED app.create_ticket_for_employee (HRT-286). This is also the
--    structural defense against prompt injection inside a scanned document
--    (business rule "untrusted document text cannot control prompts/tools/
--    actions"): the AI's own text never becomes a ticket subject/body by
--    itself, a human always retypes/confirms it first.
-- 2. **Bounded, disclosed "apply" target: Ticketing only, not Finance/HR
--    directly.** Every existing Finance/Commercial "create draft" entry
--    point in this repository (app.prepare_finance_invoice_from_readiness,
--    app.prepare_finance_vendor_bill_from_actual_cost,
--    app.create_quotation_draft via IAE-020) is deliberately sourced from
--    its own canonical upstream evidence chain (billing readiness / actual
--    cost / costing-margin chain), never from arbitrary caller-supplied
--    header fields -- confirmed by reading each function's own signature
--    before choosing a target. Forcing OCR to feed those functions directly
--    would either bypass canonical domain ownership (this prompt's own
--    §13 "preserve canonical domain ownership" requirement) or require
--    fabricating upstream evidence that does not exist. app.create_ticket_
--    for_employee (HRT-286) has no such precondition -- it is the correct,
--    real, non-colliding "apply to a draft record" target this checkpoint
--    can wire end to end without inventing fake evidence. Finance/HR
--    document apply-targets are a disclosed, deferred future extension
--    (consistent with every prior AI-assisted capability's own scope
--    boundary, e.g. IAE-020 deferring its own review UI) -- the extraction/
--    classification/review/correction pipeline itself (decisions 3-5 below)
--    is fully generic across document_type_hint and not itself limited to
--    ticket-bound documents.
-- 3. **Every job is gated on a real, already-clean file.**
--    app.submit_ocr_document_job refuses any app.files row whose
--    malware_scan_status is not 'clean' (business rule "unscanned/
--    quarantined files never enter OCR") and re-checks the file's own
--    record-level access via app.can_access_record (the same primitive
--    app.files' own owner/shared_org_unit/customer_account_ref columns are
--    shaped for) -- never a bespoke ACL.
-- 4. **Low-confidence output requires an explicit, elevated override, never
--    a silent apply and never a permanent block.** IAE-020 hard-blocked low
--    confidence outright; here the prompt's own alternative flow ("routes to
--    manual review", not "is refused forever") calls for a genuine override
--    path: apply_ocr_document_job_to_ticket requires AI:Approve (not merely
--    AI:Create) plus a non-empty p_low_confidence_override_reason whenever
--    the underlying governed request's confidence_label is null or 'low'.
-- 5. **Correction capture is its own bounded, non-authoritative scratch
--    state.** app.save_ocr_document_job_correction stores whatever the
--    reviewer is drafting (reviewer_corrected_fields) purely for UI
--    convenience/audit continuity -- the actual apply call always takes its
--    OWN final explicit parameters, never reads reviewer_corrected_fields
--    back as trusted input (the same "human decision is the only source of
--    truth for what gets applied" discipline as IAE-020's p_accepted_lines).
-- 6. **AI dispatch reuses dispatchAiGovernedRequest (IAE-019) completely
--    unmodified** -- feature_code = 'ocr_document_extraction',
--    correlation_record_type = 'file', correlation_record_id = the file's
--    own id. Zero new rows in app.integration_adapters/app.jobs.
-- 7. **No new entitlement module.** The AI module's own comment (IAE-019's
--    migration) already names OCR as one of its owned features -- reused
--    directly, Create/View/Approve only, matching precedent.
-- 8. **Every authenticated-granted function is SECURITY DEFINER plus
--    app.assert_actor_is_session_identity from the very first draft** -- the
--    Batch 4/IAE-020 Tier C review's own most-repeated lesson, applied
--    proactively here rather than discovered again.
-- 9. **RETURNS TABLE column names are always qualified with an explicit
--    table alias** -- IAE-020's own self-caught column-shadowing bug,
--    applied proactively.
-- 10. **Nullable-column correlation cross-checks always use IS DISTINCT
--    FROM, never bare <>** -- IAE-020's own self-caught nullable-<> bug,
--    applied proactively.
-- 11. Per ERR-2026-004: this migration carries its own explicit
--    `revoke execute on all functions in schema app from public` before its
--    final grants.
-- 12. **Self-caught, live concurrency bug**: app.create_ticket_for_employee
--    (HRT-286, pre-existing, unmodified) does not catch its own idempotency-
--    key unique_violation the way app.create_ticket_queue does -- a real
--    6-way concurrent race proved 2 of 6 callers got a raw Postgres error
--    instead of a clean idempotent return. Handled locally in
--    app.apply_ocr_document_job_to_ticket (catch + re-select) rather than
--    widening this migration's blast radius onto a widely-depended-on
--    Phase-7 primitive.

-- ===========================================================================
-- Document type for OCR-eligible source files (design decision 2's own
-- upstream file registration -- mirrors every prior document-type-consuming
-- capability's own fixture pattern exactly).
-- ===========================================================================

-- Mirrors HRT-274's own 'employee_document' direct-INSERT convention exactly:
-- app.register_document_type gates on Supreme Admin, and a migration-apply
-- context has no live actor session, so this migration inserts both the
-- app.document_types row AND its matching 'document:<code>' app.config_types
-- row directly (register_document_type's own body mints both together --
-- skipping the second insert is a real, reproducible foreign-key failure the
-- first db-test run against this migration would hit, not a theoretical
-- concern). Each tenant still separately configures and PUBLISHES its own
-- document:ocr_scan_source column definition before any real upload can
-- succeed -- the same per-tenant onboarding step every other document type
-- in this repository requires.
insert into app.document_types (code, name, owner_primitive_code, registered_by)
values ('ocr_scan_source', 'OCR Scan Source Document', 'AI', 'system')
on conflict (code) do nothing;

insert into app.config_types (code, name, owner_primitive_code, registered_by)
values ('document:ocr_scan_source', 'OCR Scan Source Document', 'AI', 'system')
on conflict (code) do nothing;

comment on column app.document_types.code is
  'IAE-021: ''ocr_scan_source'' is this checkpoint''s own registered code for any document a tenant configures as OCR-eligible (logistics/finance/HR/ticket scans alike) -- one document type, tenant-configured allowed_mime_types/max_size_bytes/classification like any other, no per-domain fork.';

-- ===========================================================================
-- Core job table (design decisions 1, 3, 4, 5)
-- ===========================================================================

create table app.ocr_document_jobs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  file_id uuid not null references app.files (id),
  ai_governed_request_id uuid unique references app.ai_governed_requests (id),
  document_type_hint text not null,
  status text not null default 'pending',
  reviewer_corrected_fields jsonb,
  low_confidence_override_reason text,
  applied_target_type text,
  applied_target_id uuid,
  dismiss_reason text,
  requested_by_auth_user_id uuid not null,
  requested_by text,
  reviewed_by_auth_user_id uuid,
  reviewed_by text,
  idempotency_key text,
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  applied_at timestamptz,
  constraint ocr_document_jobs_document_type_hint_check check (document_type_hint in ('logistics', 'finance', 'hr', 'ticket', 'other')),
  constraint ocr_document_jobs_status_check check (status in ('pending', 'extracted', 'failed', 'reviewed', 'applied', 'dismissed')),
  constraint ocr_document_jobs_applied_shape_check check ((status = 'applied') = (applied_target_type is not null and applied_target_id is not null)),
  constraint ocr_document_jobs_idempotency_key_unique unique (tenant_id, idempotency_key)
);

comment on table app.ocr_document_jobs is
  'IAE-021: one row per OCR extraction job. NEVER a source of domain truth (design decision 1) -- output/classification/confidence live only in the referenced app.ai_governed_requests row (IAE-019); the only write path into a domain table is app.apply_ocr_document_job_to_ticket, which takes exclusively human-typed field values, never the AI''s own output_payload.';

create index ocr_document_jobs_tenant_idx on app.ocr_document_jobs (tenant_id, created_at desc);
create index ocr_document_jobs_file_idx on app.ocr_document_jobs (tenant_id, file_id);
create index ocr_document_jobs_status_idx on app.ocr_document_jobs (tenant_id, status);

create function app.touch_ocr_document_jobs_row()
returns trigger
language plpgsql
as $$
begin
  new.reviewed_at := case when new.status = 'reviewed' and old.status <> 'reviewed' then now() else old.reviewed_at end;
  new.applied_at := case when new.status = 'applied' and old.status <> 'applied' then now() else old.applied_at end;
  return new;
end;
$$;

create trigger ocr_document_jobs_touch before update on app.ocr_document_jobs
for each row execute function app.touch_ocr_document_jobs_row();

-- ===========================================================================
-- Authority helper
-- ===========================================================================

create function app.check_ocr_document_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
as $$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'AI', p_action)).allowed;
$$;

-- ===========================================================================
-- Submit (design decision 3)
-- ===========================================================================

create function app.submit_ocr_document_job(
  p_tenant_id uuid,
  p_file_id uuid,
  p_document_type_hint text,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.ocr_document_jobs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_existing app.ocr_document_jobs;
  v_file app.files;
  v_row app.ocr_document_jobs;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.check_ocr_document_authority('Create', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:Create for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_document_type_hint not in ('logistics', 'finance', 'hr', 'ticket', 'other') then
    raise exception 'ocr_document_job_invalid_type_hint: % is not one of logistics/finance/hr/ticket/other', p_document_type_hint
      using errcode = 'check_violation';
  end if;

  select * into v_existing from app.ocr_document_jobs where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.file_id is distinct from p_file_id or v_existing.document_type_hint is distinct from p_document_type_hint then
      raise exception 'idempotency_key_conflict: key % was already used for a different OCR job', p_idempotency_key
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  select * into v_file from app.files where id = p_file_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'ocr_document_job_file_not_found: % is not a known file for tenant %', p_file_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  if v_file.lifecycle_status <> 'active' then
    raise exception 'ocr_document_job_file_not_active: file % is % not active', p_file_id, v_file.lifecycle_status using errcode = 'check_violation';
  end if;

  if v_file.malware_scan_status <> 'clean' then
    raise exception 'ocr_document_job_file_not_scanned: file % has malware_scan_status % -- unscanned/quarantined files never enter OCR', p_file_id, v_file.malware_scan_status
      using errcode = 'check_violation';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, p_tenant_id, v_file.uploaded_by_auth_user_id, v_file.shared_org_unit_ids, v_file.customer_account_ref) then
    raise exception 'insufficient_authority: identity % may not access file %', p_actor_auth_user_id, p_file_id
      using errcode = 'insufficient_privilege';
  end if;

  insert into app.ocr_document_jobs (
    tenant_id, file_id, document_type_hint, status, requested_by_auth_user_id, requested_by, idempotency_key
  ) values (
    p_tenant_id, p_file_id, p_document_type_hint, 'pending', p_actor_auth_user_id, p_actor_label, p_idempotency_key
  )
  returning * into v_row;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_ocr_document_job',
    'app.ocr_document_jobs', v_row.id, 'success', null, null,
    jsonb_build_object('file_id', v_row.file_id, 'document_type_hint', v_row.document_type_hint)
  );

  return v_row;
end;
$$;

comment on function app.submit_ocr_document_job is
  'IAE-021: the entry point the TS orchestration client calls before dispatching a real governed AI request. Never writes to app.ai_governed_requests itself.';

-- ===========================================================================
-- Record outcome after dispatch (design decisions 1, 6, 10)
-- ===========================================================================

create function app.record_ocr_document_job_outcome(
  p_job_id uuid,
  p_ai_governed_request_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.ocr_document_jobs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_job app.ocr_document_jobs;
  v_request app.ai_governed_requests;
  v_row app.ocr_document_jobs;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_job from app.ocr_document_jobs where id = p_job_id;
  if not found then
    raise exception 'ocr_document_job_not_found: %', p_job_id using errcode = 'no_data_found';
  end if;

  if not app.check_ocr_document_authority('Create', v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:Create for tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent replay: a job already synced to this exact governed request returns as-is.
  if v_job.ai_governed_request_id is not null then
    if v_job.ai_governed_request_id = p_ai_governed_request_id then
      return v_job;
    end if;
    raise exception 'ocr_document_job_outcome_already_recorded: job % is already linked to a different governed request', p_job_id
      using errcode = 'check_violation';
  end if;

  if v_job.status <> 'pending' then
    raise exception 'ocr_document_job_not_pending: job % is % not pending', p_job_id, v_job.status using errcode = 'check_violation';
  end if;

  select * into v_request from app.ai_governed_requests where id = p_ai_governed_request_id;
  if not found then
    raise exception 'ai_governed_request_not_found: %', p_ai_governed_request_id using errcode = 'no_data_found';
  end if;

  if v_request.tenant_id <> v_job.tenant_id then
    raise exception 'ocr_document_job_request_tenant_mismatch: governed request % does not belong to tenant %', p_ai_governed_request_id, v_job.tenant_id
      using errcode = 'check_violation';
  end if;
  if v_request.feature_code <> 'ocr_document_extraction' then
    raise exception 'ocr_document_job_wrong_feature: governed request % has feature_code % not ocr_document_extraction', p_ai_governed_request_id, v_request.feature_code
      using errcode = 'check_violation';
  end if;
  if v_request.correlation_record_type is distinct from 'file' or v_request.correlation_record_id is distinct from v_job.file_id then
    raise exception 'ocr_document_job_correlation_mismatch: governed request % does not correlate to job %''s own file %', p_ai_governed_request_id, p_job_id, v_job.file_id
      using errcode = 'check_violation';
  end if;
  if v_request.status not in ('succeeded', 'failed') then
    raise exception 'ocr_document_job_request_not_completed: governed request % is % not succeeded/failed', p_ai_governed_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  -- Tier C fix (Group 6 review): the WHERE clause itself is the concurrency
  -- guard against a lost-update race between two concurrent callers each
  -- holding a DIFFERENT real, succeeded governed request for the SAME
  -- still-pending job -- live-reproduced on the sibling IAE-022 function
  -- before this fix (both callers returned a false "success", the loser's
  -- own outcome silently overwritten with no error), applied proactively
  -- here.
  update app.ocr_document_jobs
  set ai_governed_request_id = p_ai_governed_request_id,
      status = case when v_request.status = 'succeeded' then 'extracted' else 'failed' end
  where id = p_job_id and status = 'pending'
  returning * into v_row;

  if not found then
    select * into v_row from app.ocr_document_jobs where id = p_job_id;
    if v_row.ai_governed_request_id = p_ai_governed_request_id then
      return v_row;
    end if;
    raise exception 'ocr_document_job_outcome_already_recorded: job % is already linked to a different governed request', p_job_id
      using errcode = 'check_violation';
  end if;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_ocr_document_job_outcome',
    'app.ocr_document_jobs', v_row.id, case when v_request.status = 'succeeded' then 'success' else 'failure' end, null, null,
    jsonb_build_object('status', v_row.status, 'ai_governed_request_id', v_row.ai_governed_request_id)
  );

  return v_row;
end;
$$;

comment on function app.record_ocr_document_job_outcome is
  'IAE-021: called by the AI-dispatch orchestration client AFTER a real dispatchAiGovernedRequest round trip, regardless of outcome. Idempotent per (job, governed request) pair.';

-- ===========================================================================
-- Correction capture (design decision 5)
-- ===========================================================================

create function app.save_ocr_document_job_correction(
  p_job_id uuid,
  p_tenant_id uuid,
  p_corrected_fields jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.ocr_document_jobs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_job app.ocr_document_jobs;
  v_row app.ocr_document_jobs;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_job from app.ocr_document_jobs where id = p_job_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'ocr_document_job_not_found: %', p_job_id using errcode = 'no_data_found';
  end if;

  if not app.check_ocr_document_authority('Create', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:Create for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_job.status not in ('extracted', 'reviewed') then
    raise exception 'ocr_document_job_not_reviewable: job % is % -- only extracted/reviewed jobs accept a correction', p_job_id, v_job.status
      using errcode = 'check_violation';
  end if;

  if not app.validate_config_value(p_corrected_fields) then
    raise exception 'ocr_document_job_invalid_correction_shape: corrected_fields failed the structural safety check' using errcode = 'check_violation';
  end if;

  update app.ocr_document_jobs
  set reviewer_corrected_fields = p_corrected_fields, status = 'reviewed',
      reviewed_by_auth_user_id = p_actor_auth_user_id, reviewed_by = p_actor_label
  where id = p_job_id
  returning * into v_row;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'save_ocr_document_job_correction',
    'app.ocr_document_jobs', v_row.id, 'success', null, null, null
  );

  return v_row;
end;
$$;

comment on function app.save_ocr_document_job_correction is
  'IAE-021: purely scratch review state for UI convenience/audit continuity -- app.apply_ocr_document_job_to_ticket never reads reviewer_corrected_fields back as trusted input, it takes its own final explicit parameters (design decision 5).';

-- ===========================================================================
-- Dismiss
-- ===========================================================================

create function app.dismiss_ocr_document_job(
  p_job_id uuid,
  p_tenant_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.ocr_document_jobs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_row app.ocr_document_jobs;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.check_ocr_document_authority('Create', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:Create for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'ocr_document_job_dismiss_reason_required: a reason is required' using errcode = 'check_violation';
  end if;

  -- Atomic pending-only-shaped transition (C-01-class race guard): the WHERE
  -- clause itself is the concurrency guard, never a separate check-then-act.
  update app.ocr_document_jobs
  set status = 'dismissed', dismiss_reason = p_reason
  where id = p_job_id and tenant_id = p_tenant_id and status in ('pending', 'extracted', 'failed', 'reviewed')
  returning * into v_row;

  if not found then
    if exists (select 1 from app.ocr_document_jobs where id = p_job_id and tenant_id = p_tenant_id) then
      raise exception 'ocr_document_job_not_dismissible: job % is already applied/dismissed', p_job_id using errcode = 'check_violation';
    end if;
    raise exception 'ocr_document_job_not_found: %', p_job_id using errcode = 'no_data_found';
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'dismiss_ocr_document_job',
    'app.ocr_document_jobs', v_row.id, 'success', null, null, jsonb_build_object('dismiss_reason', v_row.dismiss_reason)
  );

  return v_row;
end;
$$;

-- ===========================================================================
-- Apply to a real ticket draft (design decisions 1, 2, 4)
-- ===========================================================================

create function app.apply_ocr_document_job_to_ticket(
  p_job_id uuid,
  p_tenant_id uuid,
  p_requester_employee_id uuid,
  p_category_id uuid,
  p_queue_id uuid,
  p_priority text,
  p_subject text,
  p_body text,
  p_low_confidence_override_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.ocr_document_jobs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_job app.ocr_document_jobs;
  v_request app.ai_governed_requests;
  v_ticket app.tickets;
  v_row app.ocr_document_jobs;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- C-05-class: authority checked before any read of the job/governed request.
  if not app.check_ocr_document_authority('Create', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:Create for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_job from app.ocr_document_jobs where id = p_job_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'ocr_document_job_not_found: %', p_job_id using errcode = 'no_data_found';
  end if;

  if v_job.status not in ('extracted', 'reviewed') then
    raise exception 'ocr_document_job_not_applyable: job % is % -- only extracted/reviewed jobs may be applied', p_job_id, v_job.status
      using errcode = 'check_violation';
  end if;

  if p_subject is null or length(trim(p_subject)) = 0 then
    raise exception 'ocr_document_job_subject_required: a human-authored subject is required' using errcode = 'check_violation';
  end if;
  if p_body is null or length(trim(p_body)) = 0 then
    raise exception 'ocr_document_job_body_required: a human-authored body is required' using errcode = 'check_violation';
  end if;

  select * into v_request from app.ai_governed_requests where id = v_job.ai_governed_request_id;
  if not found then
    raise exception 'ai_governed_request_not_found: job % has no linked governed request', p_job_id using errcode = 'no_data_found';
  end if;

  if v_request.confidence_label is null or v_request.confidence_label = 'low' then
    if p_low_confidence_override_reason is null or length(trim(p_low_confidence_override_reason)) = 0 then
      raise exception 'ocr_document_job_low_confidence_override_required: confidence is % -- a non-empty override reason is required', v_request.confidence_label
        using errcode = 'check_violation';
    end if;
    if not app.check_ocr_document_authority('Approve', p_tenant_id, p_actor_auth_user_id) then
      raise exception 'insufficient_authority: identity % lacks AI:Approve required to apply a low-confidence extraction', p_actor_auth_user_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  -- The domain write happens FIRST, through the existing, unmodified
  -- HRT-286 entry point, keyed to a job-scoped idempotency key -- mirrors
  -- IAE-020's own Tier C reordering fix (domain write before the local
  -- atomic-guard transition) applied proactively from the start.
  --
  -- Self-caught, live concurrency bug (before this migration was ever
  -- committed a second time): unlike app.create_ticket_queue's own
  -- established idempotent-retry pattern (catch unique_violation, re-select),
  -- app.create_ticket_for_employee/app._create_ticket (HRT-286, pre-existing,
  -- unmodified) does NOT catch its own idempotency-key unique_violation --
  -- a real 6-way concurrent race on this function proved 2 of 6 callers got
  -- a raw, unhandled Postgres unique_violation instead of a clean idempotent
  -- return. Rather than widen this migration's blast radius by editing a
  -- widely-depended-on Phase-7 primitive, the retry is handled locally here:
  -- a losing caller re-selects the SAME ticket the winner already created.
  begin
    select * into v_ticket from app.create_ticket_for_employee(
      p_tenant_id, p_requester_employee_id, p_category_id, p_queue_id, p_priority, p_subject, p_body,
      'ocr-job-' || p_job_id::text, p_actor_auth_user_id, p_actor_label
    );
  exception
    when unique_violation then
      select * into v_ticket from app.tickets
      where tenant_id = p_tenant_id and requester_employee_id = p_requester_employee_id and idempotency_key = 'ocr-job-' || p_job_id::text;
      if not found then
        raise;
      end if;
  end;

  update app.ocr_document_jobs
  set status = 'applied', applied_target_type = 'ticket', applied_target_id = v_ticket.id,
      low_confidence_override_reason = p_low_confidence_override_reason
  where id = p_job_id and status in ('extracted', 'reviewed')
  returning * into v_row;

  if not found then
    -- Lost the race after an idempotent ticket create (same job-scoped key):
    -- re-select rather than error, since the winner already recorded 'applied'.
    select * into v_row from app.ocr_document_jobs where id = p_job_id;
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'apply_ocr_document_job_to_ticket',
    'app.ocr_document_jobs', v_row.id, 'success', null, null,
    jsonb_build_object('applied_target_type', v_row.applied_target_type, 'applied_target_id', v_row.applied_target_id)
  );

  return v_row;
end;
$$;

comment on function app.apply_ocr_document_job_to_ticket is
  'IAE-021: the ONLY write path from an OCR job into a real domain table. Never reads app.ai_governed_requests.output_payload -- every applied field is an explicit, human-typed parameter. Low confidence requires AI:Approve plus a non-empty override reason (design decision 4).';

-- ===========================================================================
-- Reads
-- ===========================================================================

create function app.get_ocr_document_job(p_job_id uuid, p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, tenant_id uuid, file_id uuid, ai_governed_request_id uuid, document_type_hint text, status text,
  reviewer_corrected_fields jsonb, low_confidence_override_reason text, applied_target_type text, applied_target_id uuid,
  dismiss_reason text, requested_by text, reviewed_by text, created_at timestamptz, reviewed_at timestamptz, applied_at timestamptz,
  output_payload jsonb, confidence_label text, model_version text, request_status text
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.check_ocr_document_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select j.id, j.tenant_id, j.file_id, j.ai_governed_request_id, j.document_type_hint, j.status,
         j.reviewer_corrected_fields, j.low_confidence_override_reason, j.applied_target_type, j.applied_target_id,
         j.dismiss_reason, j.requested_by, j.reviewed_by, j.created_at, j.reviewed_at, j.applied_at,
         r.output_payload, r.confidence_label, r.model_version, r.status
  from app.ocr_document_jobs j
  left join app.ai_governed_requests r on r.id = j.ai_governed_request_id
  where j.id = p_job_id and j.tenant_id = p_tenant_id;
end;
$$;

create function app.list_ocr_document_jobs_for_tenant(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_status text default null,
  p_limit integer default 50
)
returns table (
  id uuid, tenant_id uuid, file_id uuid, ai_governed_request_id uuid, document_type_hint text, status text,
  applied_target_type text, applied_target_id uuid, requested_by text, created_at timestamptz,
  confidence_label text, request_status text
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.check_ocr_document_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_limit is null or p_limit <= 0 or p_limit > 200 then
    raise exception 'ocr_document_job_invalid_limit: limit must be between 1 and 200' using errcode = 'check_violation';
  end if;

  return query
  select j.id, j.tenant_id, j.file_id, j.ai_governed_request_id, j.document_type_hint, j.status,
         j.applied_target_type, j.applied_target_id, j.requested_by, j.created_at,
         r.confidence_label, r.status
  from app.ocr_document_jobs j
  left join app.ai_governed_requests r on r.id = j.ai_governed_request_id
  where j.tenant_id = p_tenant_id and (p_status is null or j.status = p_status)
  order by j.created_at desc
  limit p_limit;
end;
$$;

-- ===========================================================================
-- RLS
-- ===========================================================================

alter table app.ocr_document_jobs enable row level security;

-- No direct authenticated grant and zero policies -- the only read paths are
-- app.get_ocr_document_job / app.list_ocr_document_jobs_for_tenant (AI:View-gated),
-- mirroring app.ai_quotation_suggestions' own posture exactly.

-- ===========================================================================
-- Grants
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant execute on function app.check_ocr_document_authority(text, uuid, uuid) to service_role;
grant execute on function app.submit_ocr_document_job(uuid, uuid, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.record_ocr_document_job_outcome(uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.save_ocr_document_job_correction(uuid, uuid, jsonb, uuid, text) to authenticated, service_role;
grant execute on function app.dismiss_ocr_document_job(uuid, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.apply_ocr_document_job_to_ticket(uuid, uuid, uuid, uuid, uuid, text, text, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.get_ocr_document_job(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.list_ocr_document_jobs_for_tenant(uuid, uuid, text, integer) to authenticated, service_role;
