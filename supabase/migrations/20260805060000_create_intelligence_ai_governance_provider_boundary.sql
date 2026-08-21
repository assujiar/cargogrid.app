-- Intelligence, Automation and Enterprise Expansion: AI Governance Provider
-- Boundary (IAE-019, CG-S14-IAE-019, Prompt 347). Sixth and last
-- independently-buildable prompt of the merged Batch 4 (`00_EXECUTION_
-- INDEX.md` §5 revision, Prompts 342-348) -- Prompt 348 (IAE-020) depends
-- on this one reaching `VERIFIED`.
--
-- This checkpoint is NOT itself an AI feature. It is the governance
-- FOUNDATION (analogous to what IAE-336/IAE-008, the Integration Hub, was
-- for provider integrations) that Prompt 348 and every later AI-assisted
-- capability (349-353) builds on top of. Confirmed genuinely greenfield by
-- direct grep before writing any code (zero AI/OCR/LLM table, function,
-- route, or contract anywhere in this repository -- re-confirmed
-- independently by `ADR-0025`'s own identical grep).
--
-- Design decisions, disclosed rather than left implicit:
--
-- 1. **A brand-new `AI` entitlement module is Supreme-registered here** --
--    already ratified in `docs/architecture/01_MODULE_DEPENDENCY_MAP.md`
--    §2.1 (`AI | ... | 347-353 | ... | advisory-only outputs, human-
--    approval gated`) but not yet present in `app.entitlement_modules`.
--    Mirrors IAE-007's own direct-INSERT seeding of `INTHUB` exactly --
--    `app.entitlement_modules` has no CHECK enum (an open registry, unlike
--    `app.jobs.job_type`), so this is a single-place SQL insert, not a
--    lockstep. Three actions seeded: `Create` (submit a governed AI
--    request), `View` (read requests/evidence), `Approve` (decide a
--    human-approval-gated output). Provider CONNECTION setup itself
--    deliberately stays under the EXISTING `INTHUB:Configure` (consistent
--    with every prior Batch 4 capability -- connection management is an
--    Integration Hub concern, never duplicated under a new module).
-- 2. **AI output can NEVER autonomously write to any domain table --
--    structurally, not by convention.** No function in this migration
--    grants INSERT/UPDATE/DELETE on any table outside this checkpoint's
--    own new schema. This is the literal, strongest reading of "AI cannot
--    autonomously post ledgers/payments, approve legal/tax status, change
--    contracts, release payroll, assign blame or finalize critical
--    decisions" and "AI output is suggestion/evidence, not source truth" --
--    a downstream capability (Prompt 348+) reads this checkpoint's own
--    evidence and applies a value through ITS OWN existing, unmodified
--    domain RPCs, exactly mirroring IAE-018's own "never writes to
--    app.employees/app.finance_accounts" boundary discipline, itself
--    modeled on HRT-282's Payroll->Finance handoff.
-- 3. **No prompt-injection CONTENT classifier is built -- a deliberate,
--    disclosed choice, not a gap.** A heuristic text classifier would be a
--    fake/placeholder defense prone to false confidence (explicitly
--    forbidden by this project's own "no placeholder/fake" Definition of
--    Done). Confirmed no precedent exists anywhere in the repository for
--    this concept. The REAL defense this checkpoint provides is
--    structural: decision 2's own guarantee (AI output has no write path
--    into any domain table) plus decision 6's own mandatory human-approval
--    gate before a downstream capability may treat an output as
--    actionable -- "prompt injection and untrusted content are treated as
--    hostile" is satisfied by never trusting AI output enough to act on it
--    unsupervised, not by trying to detect the injection itself.
-- 4. **Redaction is a caller responsibility, not a DB-enforced content
--    scrubber.** `app.redact_audit_payload` (PLT-101) is confirmed
--    key-name-only (a fixed regex over jsonb KEYS, never VALUE content) --
--    inadequate for free-text prompt/output payloads whose sensitive
--    content, if any, lives in the text itself, not in a key name. This
--    checkpoint's own `app.request_ai_governed_action` applies a
--    STRUCTURAL safety net only (`app.validate_config_value` for size/
--    shape, plus a secret-shaped-key-name guard mirroring `app.redact_
--    audit_payload`'s own regex) -- genuine content-aware scoping/
--    redaction of what goes INTO a prompt is necessarily the caller's own
--    responsibility (it must decide what context is safe to send before
--    ever reaching this boundary), disclosed here rather than silently
--    assumed solved.
-- 5. **Single-adapter dispatch shape, mirrors IAE-015's own geocode client
--    exactly** -- one adapter (`openai_multimodal`, RPD-021's own named
--    default), a live SYNCHRONOUS request/response call (prompt in, output
--    out), never `app.jobs`-queued (matching geocoding's own "not every
--    real outbound call is async" precedent) -- the ninth real outbound
--    HTTP client in this repository.
-- 6. **Human approval reuses the generic Platform Approval Engine
--    (PLT-123) via a domain-scoped `SECURITY DEFINER` proxy pair**,
--    mirroring `app.request_automation_rule_publish_approval`/`app.
--    decide_automation_rule_publish_approval` (IAE-007) exactly -- never a
--    bespoke approval mechanism. A tenant publishes its own `approval:
--    ai_output_acceptance` definition (config type registered here,
--    mirroring `approval:automation_rule_publish`'s own registration
--    precedent) before any request can seek approval. Whether a given AI
--    output NEEDS approval before a downstream capability treats it as
--    actionable is that downstream capability's own judgment call (RPD-021
--    names "before financial/legal posting or critical status changes" as
--    the trigger) -- this checkpoint provides the mechanism, never forces
--    every request through it.
-- 7. **Cost metering (`RPD-028`) reuses `app.compute_provider_billed_
--    amount` directly (IAE-014)** -- AI/OCR is explicitly named alongside
--    messaging/maps/third-party services in RPD-028's own text.
-- 8. **`feature_code` is free text, never a CHECK enum** -- RPD-038's own
--    "no generic connector claim" spirit extended to AI features: Prompt
--    348 and every later AI-assisted capability names its own feature_code
--    when it calls this boundary; this migration makes no claim about
--    which future features exist.
-- 9. Per `ERR-2026-004`: this migration carries its own explicit `revoke
--    execute on all functions in schema app from public` before its final
--    grants.

-- ===========================================================================
-- AI entitlement module (design decision 1)
-- ===========================================================================

insert into app.entitlement_modules (code, name, owning_phase) values
  ('AI', 'AI-assisted capability with human governance (quotation, OCR, ETA, optimization, fraud, forecasting)', 9);

insert into app.permissions (action, resource_module_code, category, protected) values
  ('Create', 'AI', 'standard', false),
  ('View', 'AI', 'standard', false),
  ('Approve', 'AI', 'workflow', false);

-- ===========================================================================
-- Approval config type (design decision 6)
-- ===========================================================================

insert into app.config_types (code, name, owner_primitive_code, registered_by) values
  ('approval:ai_output_acceptance', 'AI Output Acceptance Approval', 'AI', 'phase-09-foundation');

-- ===========================================================================
-- Authority helper
-- ===========================================================================

create function app.check_ai_governance_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
as $$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'AI', p_action)).allowed;
$$;

-- ===========================================================================
-- Core evidence ledger (design decisions 2, 3, 4, 7, 8)
-- ===========================================================================

create table app.ai_governed_requests (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  connection_id uuid not null references app.integration_connections (id),
  feature_code text not null,
  correlation_record_type text,
  correlation_record_id uuid,
  prompt_payload jsonb not null,
  status text not null default 'pending',
  output_payload jsonb,
  confidence_label text,
  model_version text,
  provider_unit_cost_amount numeric,
  currency text,
  billed_amount numeric,
  error_message text,
  approval_request_id uuid references app.approval_requests (id),
  requested_by_auth_user_id uuid references auth.users (id),
  requested_by text,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  constraint ai_governed_requests_feature_code_check check (length(trim(feature_code)) > 0),
  constraint ai_governed_requests_status_check check (status in ('pending', 'succeeded', 'failed')),
  constraint ai_governed_requests_confidence_label_check check (confidence_label is null or confidence_label in ('high', 'medium', 'low')),
  constraint ai_governed_requests_prompt_payload_check check (app.validate_config_value(prompt_payload)),
  constraint ai_governed_requests_cost_check check (provider_unit_cost_amount is null or provider_unit_cost_amount >= 0)
);

comment on table app.ai_governed_requests is
  'IAE-019: the shared evidence ledger every AI-assisted capability (Prompt 348+) records its own requests against. NEVER a source of domain truth (design decision 2) -- output_payload is suggestion/evidence only, a downstream capability applies a value through its own existing, unmodified domain RPCs after reading this row (and, if approval_request_id resolves to app.approval_requests.status = ''approved'', only after that human decision). correlation_record_type/correlation_record_id are a soft, polymorphic reference (never a foreign key), the same posture app.files.record_id/app.external_sync_entity_links.internal_record_id already established.';

create index ai_governed_requests_tenant_idx on app.ai_governed_requests (tenant_id, created_at desc);
create index ai_governed_requests_correlation_idx on app.ai_governed_requests (tenant_id, correlation_record_type, correlation_record_id) where correlation_record_id is not null;
create index ai_governed_requests_feature_idx on app.ai_governed_requests (tenant_id, feature_code, created_at desc);

-- ===========================================================================
-- Structural payload safety net (design decision 4) -- mirrors app.redact_
-- audit_payload's own secret-shaped-key regex, applied as a REJECTION gate
-- here rather than a silent redaction (a caller that includes a
-- secret-shaped key in a prompt payload has a real bug worth surfacing,
-- not silently masking).
-- ===========================================================================

create function app.assert_ai_prompt_payload_has_no_secret_shaped_keys(p_payload jsonb)
returns void
language plpgsql
immutable
as $$
declare
  v_key text;
begin
  for v_key in select jsonb_object_keys(p_payload) loop
    if v_key ~* '(secret|password|token|api_key|authorization|cookie|ssn|npwp|bank|account_number|salary|payroll)' then
      raise exception 'ai_governed_request_secret_shaped_key: prompt_payload key "%" looks credential/PII-shaped -- redact or rename before submitting', v_key
        using errcode = 'check_violation';
    end if;
  end loop;
end;
$$;

comment on function app.assert_ai_prompt_payload_has_no_secret_shaped_keys is
  'IAE-019 (design decision 4): a structural backstop only -- mirrors app.redact_audit_payload''s own key-name regex, but REJECTS rather than silently redacts (a prompt payload is caller-authored; a secret-shaped key here is a real bug worth surfacing). Never a content-aware scrubber -- genuine redaction/scoping of what goes into a prompt remains the caller''s own responsibility.';

-- ===========================================================================
-- Real dispatch client reads (mirrors app.get_maps_provider_dispatch_info
-- exactly -- single adapter, no adapter_code param needed).
-- ===========================================================================

create function app.get_ai_governed_dispatch_info(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (connection_id uuid, connection_status text, connection_config jsonb)
language plpgsql
stable
as $$
begin
  if not app.check_ai_governance_authority('Create', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:Create for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select ic.id, ic.status, ic.config
  from app.integration_connections ic
  where ic.tenant_id = p_tenant_id and ic.adapter_code = 'openai_multimodal'
  order by (ic.environment = 'production') desc, ic.created_at desc
  limit 1;
end;
$$;

create function app.get_ai_governed_credential(p_connection_id uuid)
returns text
language sql
stable
as $$
  select credential_value from app.integration_connection_credentials where connection_id = p_connection_id;
$$;

comment on function app.get_ai_governed_credential is
  'IAE-019: service_role-only, mirrors app.get_maps_provider_credential (IAE-015) exactly.';

-- ===========================================================================
-- Request/outcome recording (design decisions 2, 3, 4, 7)
-- ===========================================================================

create function app.request_ai_governed_action(
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
as $$
declare
  v_row app.ai_governed_requests;
begin
  if not app.check_ai_governance_authority('Create', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:Create for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_feature_code is null or length(trim(p_feature_code)) = 0 then
    raise exception 'ai_governed_request_feature_code_required: a feature_code is required' using errcode = 'check_violation';
  end if;

  perform app.assert_ai_prompt_payload_has_no_secret_shaped_keys(p_prompt_payload);

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
    jsonb_build_object('feature_code', v_row.feature_code, 'correlation_record_type', v_row.correlation_record_type)
  );

  return v_row;
end;
$$;

comment on function app.request_ai_governed_action is
  'IAE-019: the entry point every AI-assisted capability (Prompt 348+) calls to register a real, governed AI request BEFORE dispatching it. Never writes to any table outside this migration''s own schema (design decision 2).';

create function app.record_ai_governed_request_outcome(
  p_request_id uuid,
  p_status text,
  p_output_payload jsonb,
  p_confidence_label text,
  p_model_version text,
  p_provider_unit_cost_amount numeric,
  p_currency text,
  p_error_message text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.ai_governed_requests
language plpgsql
as $$
declare
  v_request app.ai_governed_requests;
  v_billed_amount numeric;
  v_row app.ai_governed_requests;
begin
  select * into v_request from app.ai_governed_requests where id = p_request_id;
  if not found then
    raise exception 'ai_governed_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;

  if not app.check_ai_governance_authority('Create', v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:Create for tenant %', p_actor_auth_user_id, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_status not in ('succeeded', 'failed') then
    raise exception 'ai_governed_request_invalid_status: % is not one of succeeded/failed', p_status using errcode = 'check_violation';
  end if;
  if v_request.status <> 'pending' then
    raise exception 'ai_governed_request_not_pending: request % is % not pending', p_request_id, v_request.status using errcode = 'check_violation';
  end if;
  if p_provider_unit_cost_amount is not null and p_provider_unit_cost_amount < 0 then
    raise exception 'ai_governed_request_invalid_cost_amount: provider_unit_cost_amount must not be negative' using errcode = 'check_violation';
  end if;
  if p_output_payload is not null then
    perform app.assert_ai_prompt_payload_has_no_secret_shaped_keys(p_output_payload);
  end if;

  v_billed_amount := app.compute_provider_billed_amount(p_provider_unit_cost_amount);

  update app.ai_governed_requests
  set status = p_status, output_payload = p_output_payload, confidence_label = p_confidence_label, model_version = p_model_version,
      provider_unit_cost_amount = p_provider_unit_cost_amount, currency = p_currency, billed_amount = v_billed_amount,
      error_message = p_error_message, completed_at = now()
  where id = p_request_id
  returning * into v_row;

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_ai_governed_request_outcome',
    'app.ai_governed_requests', v_row.id, case when p_status = 'succeeded' then 'success' else 'failure' end, p_error_message, null,
    jsonb_build_object('status', v_row.status, 'confidence_label', v_row.confidence_label)
  );

  return v_row;
end;
$$;

comment on function app.record_ai_governed_request_outcome is
  'IAE-019: the real dispatch client''s own bounded write. billed_amount computed server-side via app.compute_provider_billed_amount (RPD-028), never trusted from the caller. Refuses to transition a non-pending request (idempotency: the dispatch client calls this exactly once per real HTTP outcome).';

create function app.list_ai_governed_requests_for_tenant(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_feature_code text default null,
  p_limit integer default 50
)
returns setof app.ai_governed_requests
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.check_ai_governance_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_limit is null or p_limit <= 0 or p_limit > 200 then
    raise exception 'ai_governed_request_invalid_limit: limit must be between 1 and 200' using errcode = 'check_violation';
  end if;

  return query
  select * from app.ai_governed_requests
  where tenant_id = p_tenant_id and (p_feature_code is null or feature_code = p_feature_code)
  order by created_at desc
  limit p_limit;
end;
$$;

-- ===========================================================================
-- Human approval (design decision 6) -- domain-scoped proxy pair over the
-- generic Platform Approval Engine (PLT-123), mirrors app.request_
-- automation_rule_publish_approval/app.decide_automation_rule_publish_
-- approval (IAE-007) exactly.
-- ===========================================================================

create function app.request_ai_output_approval(
  p_request_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.approval_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_request app.ai_governed_requests;
  v_approval_version_id uuid;
  v_approval_request app.approval_requests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_request from app.ai_governed_requests where id = p_request_id;
  if not found then
    raise exception 'ai_governed_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;

  if not app.check_ai_governance_authority('Create', v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:Create for tenant %', p_actor_auth_user_id, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_request.status <> 'succeeded' then
    raise exception 'ai_governed_request_not_succeeded: request % is % not succeeded -- only a real, completed output may be sent for approval', p_request_id, v_request.status
      using errcode = 'check_violation';
  end if;
  if v_request.approval_request_id is not null then
    raise exception 'ai_governed_request_approval_already_requested: request % already has an approval request', p_request_id using errcode = 'check_violation';
  end if;

  select cv.id into v_approval_version_id
  from app.config_objects co
  join app.config_versions cv on cv.config_object_id = co.id and cv.status = 'published'
  where co.config_type_code = 'approval:ai_output_acceptance' and co.tenant_id = v_request.tenant_id and co.scope_level = 'tenant';

  if v_approval_version_id is null then
    raise exception 'ai_output_acceptance_approval_not_configured: tenant % has not published an approval:ai_output_acceptance definition yet', v_request.tenant_id
      using errcode = 'check_violation';
  end if;

  select * into v_approval_request from app.request_approval(
    v_approval_version_id, v_request.tenant_id, 'ai_governed_output', v_request.id,
    'ai-output-acceptance-' || v_request.id, p_actor_auth_user_id, p_actor_label
  );

  update app.ai_governed_requests set approval_request_id = v_approval_request.id where id = p_request_id;

  return v_approval_request;
end;
$$;

comment on function app.request_ai_output_approval is
  'IAE-019: a domain-scoped SECURITY DEFINER proxy to app.request_approval (PLT-123, service_role-only), mirrors app.request_automation_rule_publish_approval (IAE-007) exactly. Only a real, succeeded output may be sent for approval, and only once per request.';

create function app.decide_ai_output_approval(
  p_request_step_id uuid,
  p_decision text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_reason text default null
)
returns app.approval_request_steps
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_step app.approval_request_steps;
  v_approval_request app.approval_requests;
  v_request app.ai_governed_requests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_step from app.approval_request_steps where id = p_request_step_id;
  if not found then
    raise exception 'ai_output_approval_step_not_found: %', p_request_step_id using errcode = 'no_data_found';
  end if;

  select * into v_approval_request from app.approval_requests where id = v_step.request_id;
  if v_approval_request.entity_type <> 'ai_governed_output' then
    raise exception 'ai_output_approval_wrong_domain: step % does not belong to an AI output acceptance request', p_request_step_id
      using errcode = 'check_violation';
  end if;

  select * into v_request from app.ai_governed_requests where id = v_approval_request.entity_id;
  if not app.check_ai_governance_authority('Approve', v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:Approve for tenant %', p_actor_auth_user_id, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return app.decide_approval_step(p_request_step_id, p_decision, p_actor_auth_user_id, p_actor_label, p_reason);
end;
$$;

comment on function app.decide_ai_output_approval is
  'IAE-019: a domain-scoped SECURITY DEFINER proxy to app.decide_approval_step (PLT-123, service_role-only), mirrors app.decide_automation_rule_publish_approval (IAE-007) exactly. Folds a step that does not belong to an ai_governed_output request into a clean not-found-shaped error, never a tenant-id-disclosing insufficient_authority. Layers AI:Approve on top of the generic engine''s own step-level eligibility check, the same defense-in-depth every prior Batch 4 capability''s own connection-active-plus-domain-permission pattern already established.';

-- ===========================================================================
-- Real adapter seed (design decision 5)
-- ===========================================================================

insert into app.integration_adapters (code, name, category, owner_primitive_code, registered_by) values
  ('openai_multimodal', 'OpenAI Multimodal (AI/OCR Provider Boundary)', 'ai_provider', 'AI', 'phase-09-foundation');

-- ===========================================================================
-- RLS
-- ===========================================================================

alter table app.ai_governed_requests enable row level security;

-- No direct authenticated grant -- the only read path is app.list_ai_
-- governed_requests_for_tenant (AI:View-gated), mirroring every prior
-- Batch 4 capability's own posture for a table with no simple direct RLS
-- predicate and a dedicated read function.

-- ===========================================================================
-- Grants
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant select, insert, update on app.ai_governed_requests to service_role;

grant execute on function app.check_ai_governance_authority(text, uuid, uuid) to service_role;
grant execute on function app.assert_ai_prompt_payload_has_no_secret_shaped_keys(jsonb) to service_role;
grant execute on function app.get_ai_governed_dispatch_info(uuid, uuid) to service_role;
grant execute on function app.get_ai_governed_credential(uuid) to service_role;
grant execute on function app.request_ai_governed_action(uuid, uuid, text, text, uuid, jsonb, uuid, text) to authenticated, service_role;
grant execute on function app.record_ai_governed_request_outcome(uuid, text, jsonb, text, text, numeric, text, text, uuid, text) to service_role;
grant execute on function app.list_ai_governed_requests_for_tenant(uuid, uuid, text, integer) to authenticated, service_role;
grant execute on function app.request_ai_output_approval(uuid, uuid, text) to authenticated, service_role;
grant execute on function app.decide_ai_output_approval(uuid, text, uuid, text, text) to authenticated, service_role;
