-- Intelligence, Automation and Enterprise Expansion: AI-Assisted Quotation
-- (IAE-020, CG-S14-IAE-020, Prompt 348). Seventh and final capability of the
-- merged Batch 4 (`00_EXECUTION_INDEX.md` §5 revision, Prompts 342-348) --
-- required `IAE-019` `VERIFIED` (not merely `COMPLETED`) first, per the
-- dependency-graph annotation; that requirement was satisfied by the merged
-- batch's own Tier C review close.
--
-- This is the FIRST real consumer of IAE-019's own AI governance boundary.
-- It lets a sales user request an AI-drafted quotation suggestion (service
-- lines, citing real, versioned rate/margin sources) which a human must
-- explicitly review and accept before it becomes a real quotation draft --
-- and from that point on, the EXISTING, wholly unmodified Commercial
-- quotation submit -> approve -> send -> customer-decision flow (COM-151
-- through COM-154) is the only path to a customer-facing commitment. No new
-- send/accept mechanism is built here.
--
-- Design decisions, disclosed rather than left implicit:
--
-- 1. **AI output can NEVER reach `app.quotations`/`app.quotation_lines`
--    directly -- structurally, not by convention.** No function in this
--    migration ever constructs a quotation line from the AI's own raw
--    `output_payload`. The ONLY write path into those tables is `app.
--    accept_ai_quotation_suggestion_as_draft`, and even that function never
--    parses or trusts the AI's own output shape -- it only accepts
--    `p_accepted_lines`, an explicitly-typed, human-submitted parameter
--    that is then handed, unchanged, to the EXISTING, UNMODIFIED `app.
--    create_quotation_draft`/`app.add_quotation_line` (COM-151/152), which
--    independently re-validate authority, record access, currency match
--    and every other business rule exactly as they already do for a
--    manually-typed quotation. This is the strictest possible reading of
--    "AI never sends quote, approves margin or commits price...
--    autonomously" (Prompt 348 §24) and mirrors every prior AI-adjacent
--    capability's own "never a second writer of domain truth" discipline
--    (IAE-016 never calls `transition_shipment_order`; IAE-018 never
--    writes to `app.employees`/`app.finance_accounts`; IAE-019 never
--    writes to any table outside its own schema at all).
-- 2. **Human edits and the final decision are recorded SEPARATELY from the
--    AI suggestion, by construction, not by an extra "diff" table.** The
--    AI's own suggestion is immutable evidence in IAE-019's own `app.
--    ai_governed_requests.output_payload` (never edited after creation).
--    This migration's own `app.ai_quotation_suggestions` tracks ONLY the
--    human's review decision (pending/accepted/dismissed) and, once
--    accepted, which REAL quotation resulted. The actual accepted lines
--    (which may differ arbitrarily from the AI's own raw suggestion --
--    that IS the human edit) live only in `app.quotation_lines`, a
--    separate, human-owned, independently-mutable table. Three genuinely
--    distinct tables, three genuinely distinct writers -- never conflated.
-- 3. **"Low-confidence/no-source output blocks auto-draft acceptance"
--    (business rule, Prompt 348 §24) is enforced at the ONE convenience
--    RPC this blocks, never elsewhere.** `app.accept_ai_quotation_
--    suggestion_as_draft` refuses to run unless the underlying governed
--    request's own `confidence_label` is `high` or `medium` (never `low`,
--    never null) AND at least one accepted line is provided AND every
--    accepted line cites a real `margin_calculation_id` (never null) --
--    "Rate/tax/currency values must come from canonical sources" (§24)
--    made a hard, structural gate rather than a UI convention. A human is
--    never blocked from drafting a quotation manually through the
--    existing, unmodified flow regardless of what this gate does --
--    exactly the prompt's own Alternative flow ("AI flags missing rate/
--    source evidence; user routes... instead of generating a quote").
-- 4. **No new approval step is required before accepting a suggestion into
--    a DRAFT.** IAE-019's own domain-scoped approval proxy pair (`app.
--    request_ai_output_approval`/`app.decide_ai_output_approval`) remains
--    available and is deliberately NOT invoked here -- IAE-019's own design
--    decision 6 leaves "whether a given AI output needs approval before a
--    downstream capability treats it as actionable" to that capability's
--    own judgment, naming RPD-021's own trigger ("before financial/legal
--    posting or critical status changes") as the bar. Entering `draft`
--    status commits nothing customer-facing and is fully reversible (a
--    draft can be edited or discarded exactly like a manually-typed one);
--    the REAL critical-status gate is the existing, unmodified COM-153
--    quotation-approval step and COM-154 send/customer-decision step,
--    both of which sit unchanged between an AI-influenced draft and any
--    actual commitment. This is a disclosed choice, not an oversight.
-- 5. **`app.create_quotation_draft`/`app.add_quotation_line` are called
--    exactly as any other caller would, inside ONE function-call
--    transaction.** If any accepted line fails validation (stale margin
--    calculation, currency mismatch, etc. -- all pre-existing, unmodified
--    checks), the entire `accept_ai_quotation_suggestion_as_draft` call
--    rolls back atomically, including its own suggestion-status flip --
--    the suggestion is left exactly as it was (`pending`), safe to retry
--    with corrected lines, never left half-applied.
-- 6. **The AI dispatch itself reuses `lib/ai-governance/dispatch-ai-
--    governed-request.server.ts` (IAE-019) completely unmodified** --
--    `feature_code = 'ai_assisted_quotation'`, `correlation_record_type =
--    'opportunity'` (a quotation does not yet exist at suggestion-request
--    time; the AI is being asked to help draft one FROM opportunity
--    context). No new AI dispatch path, no new provider adapter, no new
--    job type -- this checkpoint adds zero rows to `app.integration_
--    adapters` and zero new `app.jobs` job types.
-- 7. **Authority reuses the existing `COM` module directly** -- `COM:
--    Create` (requesting a suggestion; accepting one into a draft, exactly
--    mirroring `app.create_quotation_draft`'s own gate) and `COM:View`
--    (reading/listing suggestions), `COM:Edit` (dismissing one). No new
--    `app.entitlement_modules`/`app.permissions` row -- unlike IAE-019's
--    own brand-new `AI` module (used only for the generic governance
--    ledger itself), the DOMAIN action of drafting a quotation stays on
--    the SAME module every other Commercial quotation capability already
--    uses, consistent with `app.request_ai_governed_action`'s own separate
--    `AI:Create` check (layered underneath, not replacing, `COM:Create`).
-- 8. **Every `authenticated`-granted function here is `SECURITY DEFINER`
--    plus `app.assert_actor_is_session_identity` from the very first
--    draft** -- the merged Batch 4 Tier C review's own most-repeated
--    lesson (4 functions across IAE-016/017/018/019 were granted to
--    `authenticated` but were plain `SECURITY INVOKER` calling a `service_
--    role`-only authority helper, completely unreachable through the
--    app's own RLS-scoped client), applied proactively here rather than
--    waiting to be independently rediscovered.
-- 9. Per `ERR-2026-004`: this migration carries its own explicit `revoke
--    execute on all functions in schema app from public` before its final
--    grants.

-- ===========================================================================
-- app.ai_quotation_suggestions (design decisions 1, 2)
-- ===========================================================================

create table app.ai_quotation_suggestions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  opportunity_id uuid not null references app.opportunities (id),
  ai_governed_request_id uuid not null references app.ai_governed_requests (id),
  status text not null default 'pending',
  accepted_quotation_id uuid references app.quotations (id),
  dismiss_reason text,
  requested_by_auth_user_id uuid references auth.users (id),
  requested_by text,
  reviewed_by_auth_user_id uuid references auth.users (id),
  reviewed_by text,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint ai_quotation_suggestions_status_check check (status in ('pending', 'accepted', 'dismissed')),
  constraint ai_quotation_suggestions_governed_request_unique unique (ai_governed_request_id),
  constraint ai_quotation_suggestions_accepted_shape_check check (
    (status = 'accepted' and accepted_quotation_id is not null)
    or (status <> 'accepted' and accepted_quotation_id is null)
  )
);

comment on table app.ai_quotation_suggestions is
  'IAE-020: tracks ONLY the human''s own review decision on an AI-drafted quotation suggestion. The AI''s own suggestion is immutable evidence in app.ai_governed_requests.output_payload (IAE-019); the resulting real quotation, once accepted, lives entirely in app.quotations/app.quotation_lines -- three genuinely distinct tables, never conflated (design decision 2).';

create index ai_quotation_suggestions_tenant_idx on app.ai_quotation_suggestions (tenant_id, created_at desc);
create index ai_quotation_suggestions_opportunity_idx on app.ai_quotation_suggestions (tenant_id, opportunity_id, created_at desc);

-- ===========================================================================
-- Authority helper (design decision 7)
-- ===========================================================================

create function app.check_ai_quotation_suggestion_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
as $$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'COM', p_action)).allowed;
$$;

-- ===========================================================================
-- Record a suggestion after a real AI dispatch (design decisions 1, 6)
-- ===========================================================================

create function app.record_ai_quotation_suggestion(
  p_tenant_id uuid,
  p_opportunity_id uuid,
  p_ai_governed_request_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.ai_quotation_suggestions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_opportunity app.opportunities;
  v_request app.ai_governed_requests;
  v_row app.ai_quotation_suggestions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_opportunity from app.opportunities where id = p_opportunity_id;
  if not found or v_opportunity.tenant_id <> p_tenant_id then
    raise exception 'ai_quotation_suggestion_opportunity_not_found: %', p_opportunity_id using errcode = 'no_data_found';
  end if;

  if not app.check_ai_quotation_suggestion_authority('Create', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks COM:Create for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, p_tenant_id, v_opportunity.owner_user_id, app.lead_record_scope_org_unit_ids(v_opportunity.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access opportunity %', p_actor_auth_user_id, p_opportunity_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Tier C-lesson applied proactively: the governed request must genuinely
  -- belong to this tenant, this exact opportunity, and this exact feature --
  -- never trust a caller-supplied id blindly.
  select * into v_request from app.ai_governed_requests where id = p_ai_governed_request_id;
  if not found or v_request.tenant_id <> p_tenant_id then
    raise exception 'ai_quotation_suggestion_request_tenant_mismatch: governed request % does not belong to tenant %', p_ai_governed_request_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;
  if v_request.feature_code <> 'ai_assisted_quotation' then
    raise exception 'ai_quotation_suggestion_wrong_feature: governed request % is not an ai_assisted_quotation request', p_ai_governed_request_id
      using errcode = 'check_violation';
  end if;
  -- IS DISTINCT FROM (not <>): correlation_record_type/id are nullable, and
  -- `null <> 'opportunity'` evaluates to NULL -- which plpgsql's IF treats as
  -- false, silently skipping this raise for a request with no correlation
  -- set at all. That would let ANY succeeded governed request sharing this
  -- tenant/feature_code be tracked as a suggestion for an unrelated
  -- opportunity, defeating the whole point of this cross-check.
  if v_request.correlation_record_type is distinct from 'opportunity' or v_request.correlation_record_id is distinct from p_opportunity_id then
    raise exception 'ai_quotation_suggestion_correlation_mismatch: governed request % is not correlated to opportunity %', p_ai_governed_request_id, p_opportunity_id
      using errcode = 'check_violation';
  end if;
  if v_request.status <> 'succeeded' then
    raise exception 'ai_quotation_suggestion_request_not_succeeded: governed request % is % not succeeded', p_ai_governed_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  -- Idempotent: a retried record call for the SAME governed request returns
  -- the existing row rather than raising or duplicating.
  insert into app.ai_quotation_suggestions (tenant_id, opportunity_id, ai_governed_request_id, requested_by_auth_user_id, requested_by)
  values (p_tenant_id, p_opportunity_id, p_ai_governed_request_id, p_actor_auth_user_id, p_actor_label)
  on conflict (ai_governed_request_id) do nothing
  returning * into v_row;

  if v_row.id is null then
    select * into v_row from app.ai_quotation_suggestions where ai_governed_request_id = p_ai_governed_request_id;
    return v_row;
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'record_ai_quotation_suggestion',
    'app.ai_quotation_suggestions', v_row.id, 'success', null, null,
    jsonb_build_object('opportunity_id', p_opportunity_id, 'ai_governed_request_id', p_ai_governed_request_id)
  );

  return v_row;
end;
$$;

comment on function app.record_ai_quotation_suggestion is
  'IAE-020: the entry point the AI-dispatch orchestration calls AFTER a real, succeeded app.request_ai_governed_action/app.record_ai_governed_request_outcome round trip -- never before. Cross-checks the governed request genuinely belongs to this tenant/opportunity/feature before tracking it.';

-- ===========================================================================
-- Read paths
-- ===========================================================================

create function app.get_ai_quotation_suggestion(p_suggestion_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, tenant_id uuid, opportunity_id uuid, ai_governed_request_id uuid, status text,
  accepted_quotation_id uuid, dismiss_reason text, requested_by text, reviewed_by text, reviewed_at timestamptz, created_at timestamptz,
  output_payload jsonb, confidence_label text, model_version text, billed_amount numeric, request_status text
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_suggestion app.ai_quotation_suggestions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- Table alias required: RETURNS TABLE(id, ...) implicitly declares `id`
  -- (and every other out-column name) as a plpgsql variable in this
  -- function's own namespace, so a bare `where id = ...` is ambiguous
  -- against the table's own `id` column.
  select s.* into v_suggestion from app.ai_quotation_suggestions s where s.id = p_suggestion_id;
  if not found then
    raise exception 'ai_quotation_suggestion_not_found: %', p_suggestion_id using errcode = 'no_data_found';
  end if;

  if not app.check_ai_quotation_suggestion_authority('View', v_suggestion.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks COM:View for tenant %', p_actor_auth_user_id, v_suggestion.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select s.id, s.tenant_id, s.opportunity_id, s.ai_governed_request_id, s.status,
    s.accepted_quotation_id, s.dismiss_reason, s.requested_by, s.reviewed_by, s.reviewed_at, s.created_at,
    r.output_payload, r.confidence_label, r.model_version, r.billed_amount, r.status
  from app.ai_quotation_suggestions s
  join app.ai_governed_requests r on r.id = s.ai_governed_request_id
  where s.id = p_suggestion_id;
end;
$$;

create function app.list_ai_quotation_suggestions_for_opportunity(
  p_tenant_id uuid,
  p_opportunity_id uuid,
  p_actor_auth_user_id uuid,
  p_limit integer default 50
)
returns table (
  id uuid, tenant_id uuid, opportunity_id uuid, ai_governed_request_id uuid, status text,
  accepted_quotation_id uuid, dismiss_reason text, requested_by text, reviewed_by text, reviewed_at timestamptz, created_at timestamptz,
  output_payload jsonb, confidence_label text, model_version text, billed_amount numeric, request_status text
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.check_ai_quotation_suggestion_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks COM:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_limit is null or p_limit <= 0 or p_limit > 200 then
    raise exception 'ai_quotation_suggestion_invalid_limit: limit must be between 1 and 200' using errcode = 'check_violation';
  end if;

  return query
  select s.id, s.tenant_id, s.opportunity_id, s.ai_governed_request_id, s.status,
    s.accepted_quotation_id, s.dismiss_reason, s.requested_by, s.reviewed_by, s.reviewed_at, s.created_at,
    r.output_payload, r.confidence_label, r.model_version, r.billed_amount, r.status
  from app.ai_quotation_suggestions s
  join app.ai_governed_requests r on r.id = s.ai_governed_request_id
  where s.tenant_id = p_tenant_id and s.opportunity_id = p_opportunity_id
  order by s.created_at desc
  limit p_limit;
end;
$$;

-- ===========================================================================
-- Dismiss (design decision 8, terminal-state-guard lesson applied
-- proactively)
-- ===========================================================================

create function app.dismiss_ai_quotation_suggestion(
  p_suggestion_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.ai_quotation_suggestions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_suggestion app.ai_quotation_suggestions;
  v_row app.ai_quotation_suggestions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_suggestion from app.ai_quotation_suggestions where id = p_suggestion_id;
  if not found then
    raise exception 'ai_quotation_suggestion_not_found: %', p_suggestion_id using errcode = 'no_data_found';
  end if;

  if not app.check_ai_quotation_suggestion_authority('Edit', v_suggestion.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks COM:Edit for tenant %', p_actor_auth_user_id, v_suggestion.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Atomic pending-only transition (Tier C fix 12's own lesson applied
  -- proactively): the WHERE clause itself is the concurrency guard, not a
  -- separate SELECT-then-check.
  update app.ai_quotation_suggestions
  set status = 'dismissed', dismiss_reason = p_reason, reviewed_by_auth_user_id = p_actor_auth_user_id, reviewed_by = p_actor_label, reviewed_at = now()
  where id = p_suggestion_id and status = 'pending'
  returning * into v_row;

  if v_row.id is null then
    raise exception 'ai_quotation_suggestion_not_pending: suggestion % is % not pending', p_suggestion_id, v_suggestion.status using errcode = 'check_violation';
  end if;

  perform app.capture_audit_event(
    v_suggestion.tenant_id, p_actor_auth_user_id, p_actor_label, 'dismiss_ai_quotation_suggestion',
    'app.ai_quotation_suggestions', v_row.id, 'success', null, to_jsonb(v_suggestion), to_jsonb(v_row)
  );

  return v_row;
end;
$$;

-- ===========================================================================
-- Accept into a real quotation draft (design decisions 1, 3, 4, 5) -- the
-- key function.
-- ===========================================================================

create function app.accept_ai_quotation_suggestion_as_draft(
  p_suggestion_id uuid,
  p_currency text,
  p_validity_to timestamptz,
  p_contact_id uuid,
  p_owner_user_id uuid,
  p_org_unit_id uuid,
  p_accepted_lines jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.quotations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_suggestion app.ai_quotation_suggestions;
  v_request app.ai_governed_requests;
  v_line jsonb;
  v_row app.ai_quotation_suggestions;
  v_quotation app.quotations;
  v_current_status text;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_suggestion from app.ai_quotation_suggestions where id = p_suggestion_id;
  if not found then
    raise exception 'ai_quotation_suggestion_not_found: %', p_suggestion_id using errcode = 'no_data_found';
  end if;

  -- C-05: permission checked before any state mutation, not merely relied
  -- on to fail inside app.create_quotation_draft further down.
  if not app.check_ai_quotation_suggestion_authority('Create', v_suggestion.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks COM:Create for tenant %', p_actor_auth_user_id, v_suggestion.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Cheap, non-authoritative fast-fail -- avoids creating and immediately
  -- discarding a real quotation draft on an obviously-already-decided
  -- suggestion. The atomic UPDATE below (not this read) is the real guard.
  if v_suggestion.status <> 'pending' then
    raise exception 'ai_quotation_suggestion_not_pending: suggestion % is % not pending', p_suggestion_id, v_suggestion.status using errcode = 'check_violation';
  end if;

  select * into v_request from app.ai_governed_requests where id = v_suggestion.ai_governed_request_id;

  -- Design decision 3: the hard, structural gate -- "Low-confidence/no-
  -- source output blocks auto-draft acceptance" (Prompt 348 §24).
  if v_request.confidence_label is null or v_request.confidence_label = 'low' then
    raise exception 'ai_quotation_suggestion_low_confidence_blocked: request % has confidence_label % -- only high/medium may be accepted as a draft', v_suggestion.ai_governed_request_id, v_request.confidence_label
      using errcode = 'check_violation';
  end if;
  if p_accepted_lines is null or jsonb_typeof(p_accepted_lines) <> 'array' or jsonb_array_length(p_accepted_lines) = 0 then
    raise exception 'ai_quotation_suggestion_no_lines_provided: at least one accepted line is required' using errcode = 'check_violation';
  end if;
  for v_line in select * from jsonb_array_elements(p_accepted_lines) loop
    if nullif(v_line ->> 'margin_calculation_id', '') is null then
      raise exception 'ai_quotation_suggestion_missing_source: every accepted line must cite a real margin_calculation_id -- rate/tax/currency values must come from canonical sources'
        using errcode = 'check_violation';
    end if;
  end loop;

  -- Design decisions 1, 5: the EXISTING, UNMODIFIED Commercial RPCs do all
  -- the real work -- created BEFORE the suggestion's own atomic transition
  -- below, so that if any line fails their own independent validation,
  -- this whole function raises and NOTHING it did survives (a single
  -- top-level function call is one atomic statement -- whole-function
  -- rollback, not merely the suggestion's own status flip).
  v_quotation := app.create_quotation_draft(
    v_suggestion.tenant_id, v_suggestion.opportunity_id, p_currency, p_validity_to,
    p_contact_id, p_owner_user_id, p_org_unit_id, p_actor_auth_user_id, p_actor_label
  );

  for v_line in select * from jsonb_array_elements(p_accepted_lines) loop
    v_quotation := app.add_quotation_line(
      v_quotation.id, v_quotation.record_version,
      v_line ->> 'line_type', v_line ->> 'description', (v_line ->> 'margin_calculation_id')::uuid,
      (v_line ->> 'quantity')::numeric, (v_line ->> 'unit_price')::numeric,
      (v_line ->> 'discount_pct')::numeric, (v_line ->> 'tax_pct')::numeric,
      p_actor_auth_user_id, p_actor_label
    );
  end loop;

  -- Atomic pending-only transition LAST -- status and accepted_quotation_id
  -- are set together in ONE statement (the table's own accepted-shape check
  -- constraint requires both change together; a two-step write here would
  -- violate it on the first step). The WHERE clause alone remains the
  -- concurrency guard (Tier C fix 12's own lesson): a losing concurrent
  -- caller's own create_quotation_draft/add_quotation_line calls above are
  -- rolled back along with the raise below, never left as an orphan draft.
  update app.ai_quotation_suggestions
  set status = 'accepted', accepted_quotation_id = v_quotation.id, reviewed_by_auth_user_id = p_actor_auth_user_id, reviewed_by = p_actor_label, reviewed_at = now()
  where id = p_suggestion_id and status = 'pending'
  returning * into v_row;

  if v_row.id is null then
    select status into v_current_status from app.ai_quotation_suggestions where id = p_suggestion_id;
    raise exception 'ai_quotation_suggestion_not_pending: suggestion % is % not pending', p_suggestion_id, v_current_status using errcode = 'check_violation';
  end if;

  perform app.capture_audit_event(
    v_suggestion.tenant_id, p_actor_auth_user_id, p_actor_label, 'accept_ai_quotation_suggestion_as_draft',
    'app.ai_quotation_suggestions', v_suggestion.id, 'success', null, null,
    jsonb_build_object('ai_governed_request_id', v_suggestion.ai_governed_request_id, 'quotation_id', v_quotation.id)
  );

  return v_quotation;
end;
$$;

comment on function app.accept_ai_quotation_suggestion_as_draft is
  'IAE-020: the ONLY path from an AI suggestion into a real app.quotations row -- never parses or trusts the AI''s own output_payload, only the human-submitted p_accepted_lines, handed unchanged to the existing, unmodified app.create_quotation_draft/app.add_quotation_line. Blocks low-confidence/no-source acceptance (design decision 3); never requires a separate approval step to reach draft status (design decision 4).';

-- ===========================================================================
-- RLS
-- ===========================================================================

alter table app.ai_quotation_suggestions enable row level security;

-- No direct authenticated grant -- the only read paths are app.get_ai_
-- quotation_suggestion/app.list_ai_quotation_suggestions_for_opportunity
-- (COM:View-gated), mirroring every prior Batch 4 capability's own posture
-- for a table with no simple direct RLS predicate and a dedicated read
-- function.

-- ===========================================================================
-- Grants
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant select, insert, update on app.ai_quotation_suggestions to service_role;

grant execute on function app.check_ai_quotation_suggestion_authority(text, uuid, uuid) to service_role;
grant execute on function app.record_ai_quotation_suggestion(uuid, uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.get_ai_quotation_suggestion(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_ai_quotation_suggestions_for_opportunity(uuid, uuid, uuid, integer) to authenticated, service_role;
grant execute on function app.dismiss_ai_quotation_suggestion(uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.accept_ai_quotation_suggestion_as_draft(uuid, text, timestamptz, uuid, uuid, uuid, jsonb, uuid, text) to authenticated, service_role;
