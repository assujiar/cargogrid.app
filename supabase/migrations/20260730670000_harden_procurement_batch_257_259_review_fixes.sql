-- Batch review fix pass (CG-S11-PRC-008..010, Prompts 257-259, ADR-0021 Tier C).
-- Every fix below closes a finding CONFIRMED by live reproduction or direct code
-- derivation against the four adversarial review lenses that ran against the
-- combined 257-259 diff. See the batch's own git commit message for the full
-- disposition (findings closed / disclosed / rejected).
--
-- ===========================================================================
-- 1. C-13 (security-rls lens, HIGH): app.evaluate_procurement_approval_requirement
--    never asserted caller-is-actor, enabling cross-tenant impersonation to read
--    another tenant's approval-threshold signal. Live-reproduced: an unrelated
--    Tenant-2 session supplying a real Tenant-1 member's UUID as
--    p_actor_auth_user_id received that tenant's real published rate_version
--    threshold. Every sibling function this SAME migration added (the four
--    decide_*_approval_step wrappers) already calls
--    app.assert_actor_is_session_identity as its first statement -- this
--    function was the one gap in its own neighborhood. Same signature, CREATE OR
--    REPLACE only (preserves the existing grant, no re-GRANT needed).
-- ===========================================================================

create or replace function app.evaluate_procurement_approval_requirement(
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
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

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
  'PRC-259: the one deterministic, explainable "does this procurement decision need approval" evaluator, shared by every governed entity_type. A tenant with no published policy for that entity_type skips routing entirely (opt-in, mirrors COM-153''s own quotation precedent) -- required=false, no reasons, policy_version_id=null. Batch 257-259 review (C-13, HIGH): now asserts caller-is-actor first, closing a live-reproduced cross-tenant impersonation read of another tenant''s threshold signal -- the one function in this migration''s own neighborhood that had not yet been given the fix its four sibling decide_*_approval_step wrappers already carried.';

-- ===========================================================================
-- 2. C-05 (security-rls lens, MEDIUM): every by-id read RPC this batch added
--    resolves the target row's real tenant_id BEFORE checking whether the
--    caller may access that tenant at all, then echoes that real tenant_id
--    verbatim into the resulting insufficient_authority error text -- letting
--    any authenticated user, given an arbitrary UUID, learn (a) whether it is a
--    real row and (b) which real tenant owns it, with zero membership in that
--    tenant. Live-reproduced against app.get_rfq. Fixed here for all 13 by-id
--    read RPCs this batch's own three migrations added, by folding a
--    has_active_tenant_membership check into the SAME not-found branch so a
--    non-member gets the identical not-found error a genuinely missing row
--    would produce, never the real tenant_id. A tenant MEMBER who lacks the
--    specific PRC permission still gets the informative error (their own
--    already-known tenant_id is not new information to them) -- unchanged.
--    The identical pattern is inherited, repository-wide (already-VERIFIED
--    PRC-256's app.get_sourcing_request and, per the review, likely most by-id
--    read RPCs across the repository) -- that wider sweep is out of this
--    batch's own allowed-files scope and is registered as ISS-2026-043 in
--    docs/runtime/KNOWN_ISSUES.md rather than attempted here.
-- ===========================================================================

create or replace function app.get_rfq(p_rfq_id uuid, p_actor_auth_user_id uuid)
returns app.rfqs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tenant_id uuid;
  v_row app.rfqs;
begin
  select tenant_id into v_tenant_id from app.rfqs where id = p_rfq_id;
  if v_tenant_id is null or not app.has_active_tenant_membership(v_tenant_id, p_actor_auth_user_id) then
    raise exception 'rfq_not_found: %', p_rfq_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_row from app.rfqs where id = p_rfq_id;
  return v_row;
end;
$$;

create or replace function app.list_rfq_requirement_lines(p_rfq_id uuid, p_actor_auth_user_id uuid)
returns setof app.rfq_requirement_lines
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tenant_id uuid;
begin
  select tenant_id into v_tenant_id from app.rfqs where id = p_rfq_id;
  if v_tenant_id is null or not app.has_active_tenant_membership(v_tenant_id, p_actor_auth_user_id) then
    raise exception 'rfq_not_found: %', p_rfq_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.rfq_requirement_lines where rfq_id = p_rfq_id order by line_no;
end;
$$;

create or replace function app.list_rfq_invitations(p_rfq_id uuid, p_actor_auth_user_id uuid)
returns setof app.rfq_invitations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tenant_id uuid;
begin
  select tenant_id into v_tenant_id from app.rfqs where id = p_rfq_id;
  if v_tenant_id is null or not app.has_active_tenant_membership(v_tenant_id, p_actor_auth_user_id) then
    raise exception 'rfq_not_found: %', p_rfq_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.rfq_invitations where rfq_id = p_rfq_id order by invited_at;
end;
$$;

create or replace function app.list_rfq_clarifications(p_rfq_id uuid, p_actor_auth_user_id uuid)
returns setof app.rfq_clarifications
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tenant_id uuid;
begin
  select tenant_id into v_tenant_id from app.rfqs where id = p_rfq_id;
  if v_tenant_id is null or not app.has_active_tenant_membership(v_tenant_id, p_actor_auth_user_id) then
    raise exception 'rfq_not_found: %', p_rfq_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.rfq_clarifications where rfq_id = p_rfq_id order by asked_at;
end;
$$;

create or replace function app.list_rfq_responses(p_rfq_id uuid, p_actor_auth_user_id uuid)
returns setof app.rfq_responses_directory
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tenant_id uuid;
begin
  select tenant_id into v_tenant_id from app.rfqs where id = p_rfq_id;
  if v_tenant_id is null or not app.has_active_tenant_membership(v_tenant_id, p_actor_auth_user_id) then
    raise exception 'rfq_not_found: %', p_rfq_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select
    r.id, r.tenant_id, r.rfq_id, r.rfq_invitation_id, r.vendor_master_id, r.version, r.previous_version_id, r.status,
    case when app.has_prc_view_cost(r.tenant_id, p_actor_auth_user_id) then r.currency else null end,
    case when app.has_prc_view_cost(r.tenant_id, p_actor_auth_user_id) then r.total_amount else null end,
    case when app.has_prc_view_cost(r.tenant_id, p_actor_auth_user_id) then r.validity_until else null end,
    r.lead_time_days,
    case when app.has_prc_view_cost(r.tenant_id, p_actor_auth_user_id) then r.commercial_terms else '{}'::jsonb end,
    not app.has_prc_view_cost(r.tenant_id, p_actor_auth_user_id),
    r.capture_mode, r.source_message_ref, r.received_at, r.vendor_confirmed, r.late_capture, r.late_reason, r.comparison_eligible,
    r.idempotency_key, r.actor_auth_user_id, r.actor_label, r.record_version, r.created_at, r.updated_at
  from app.rfq_responses r
  where r.rfq_id = p_rfq_id
  order by r.created_at;
end;
$$;

comment on function app.list_rfq_responses is 'PRC-257: comparison read. Masks currency/total_amount/validity_until/commercial_terms behind PRC:View cost, threading p_actor_auth_user_id explicitly into app.has_prc_view_cost -- never selecting from app.rfq_responses_directory itself (whose own row filter/mask default to auth.uid()), mirroring app.search_vendor_rates (PRC-255) / app.list_sourcing_requests (PRC-256) exactly. Batch 257-259 review (C-05, MEDIUM): the not-found check now also requires active tenant membership, so a non-member cannot learn the real tenant_id via the insufficient_authority error path below it.';

create or replace function app.list_rfq_response_attachments(p_rfq_response_id uuid, p_actor_auth_user_id uuid)
returns setof app.rfq_response_attachments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tenant_id uuid;
begin
  select tenant_id into v_tenant_id from app.rfq_responses where id = p_rfq_response_id;
  if v_tenant_id is null or not app.has_active_tenant_membership(v_tenant_id, p_actor_auth_user_id) then
    raise exception 'rfq_response_not_found: %', p_rfq_response_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.rfq_response_attachments where rfq_response_id = p_rfq_response_id order by created_at;
end;
$$;

create or replace function app.get_rfq_history(p_rfq_id uuid, p_actor_auth_user_id uuid)
returns setof app.rfq_events
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tenant_id uuid;
begin
  select tenant_id into v_tenant_id from app.rfqs where id = p_rfq_id;
  if v_tenant_id is null or not app.has_active_tenant_membership(v_tenant_id, p_actor_auth_user_id) then
    raise exception 'rfq_not_found: %', p_rfq_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.rfq_events where rfq_id = p_rfq_id order by occurred_at;
end;
$$;

create or replace function app.get_vendor_comparison(p_comparison_id uuid, p_actor_auth_user_id uuid)
returns app.vendor_comparisons
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tenant_id uuid;
  v_row app.vendor_comparisons;
begin
  select tenant_id into v_tenant_id from app.vendor_comparisons where id = p_comparison_id;
  if v_tenant_id is null or not app.has_active_tenant_membership(v_tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_comparison_not_found: %', p_comparison_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tenant_id, 'PRC', 'View cost');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View cost (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_row from app.vendor_comparisons where id = p_comparison_id;
  return v_row;
end;
$$;

create or replace function app.list_vendor_comparison_offers(p_comparison_id uuid, p_actor_auth_user_id uuid)
returns setof app.vendor_comparison_offers
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tenant_id uuid;
begin
  select tenant_id into v_tenant_id from app.vendor_comparisons where id = p_comparison_id;
  if v_tenant_id is null or not app.has_active_tenant_membership(v_tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_comparison_not_found: %', p_comparison_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tenant_id, 'PRC', 'View cost');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View cost (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.vendor_comparison_offers where comparison_id = p_comparison_id order by rank nulls last, normalized_amount nulls last;
end;
$$;

create or replace function app.list_vendor_comparison_offer_scores(p_comparison_offer_id uuid, p_actor_auth_user_id uuid)
returns setof app.vendor_comparison_offer_scores
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tenant_id uuid;
begin
  select tenant_id into v_tenant_id from app.vendor_comparison_offers where id = p_comparison_offer_id;
  if v_tenant_id is null or not app.has_active_tenant_membership(v_tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_comparison_offer_not_found: %', p_comparison_offer_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tenant_id, 'PRC', 'View cost');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View cost (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.vendor_comparison_offer_scores where comparison_offer_id = p_comparison_offer_id order by criterion_key;
end;
$$;

create or replace function app.get_vendor_comparison_history(p_comparison_id uuid, p_actor_auth_user_id uuid)
returns setof app.vendor_comparison_events
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tenant_id uuid;
begin
  select tenant_id into v_tenant_id from app.vendor_comparisons where id = p_comparison_id;
  if v_tenant_id is null or not app.has_active_tenant_membership(v_tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_comparison_not_found: %', p_comparison_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tenant_id, 'PRC', 'View cost');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View cost (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.vendor_comparison_events where comparison_id = p_comparison_id order by occurred_at;
end;
$$;

create or replace function app.get_procurement_approval_context_snapshot(p_approval_request_id uuid, p_actor_auth_user_id uuid)
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
  if not found or not app.has_active_tenant_membership(v_snapshot.tenant_id, p_actor_auth_user_id) then
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

create or replace function app.get_procurement_exception_request(p_id uuid, p_actor_auth_user_id uuid)
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
  if not found or not app.has_active_tenant_membership(v_row.tenant_id, p_actor_auth_user_id) then
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

-- ===========================================================================
-- 3. C-11 (security-rls lens, CRITICAL; independently reproduced by the
--    cross-prompt lens too): app.vendor_comparisons / app.vendor_comparison_
--    offers / app.vendor_comparison_offer_scores / app.vendor_comparison_events
--    grant unrestricted SELECT to `authenticated`, bypassing the PRC:View cost
--    RPC gate entirely -- live-reproduced: a tenant member holding PRC:View but
--    explicitly NOT PRC:View cost read real bid amounts, normalized amounts,
--    composite scores and ranks via a raw table select, and a tenant member
--    with ZERO PRC permission read the same rows directly. The RPC layer
--    (app.get_vendor_comparison / app.list_vendor_comparison_offers / app.
--    list_vendor_comparison_offer_scores / app.get_vendor_comparison_history)
--    correctly denies both actors -- only the raw grant bypasses it. The two
--    `_directory` views were ALSO unmasked (`select o.* ... where <tenant
--    membership only>`, this migration's own design note 8: "the whole surface
--    gates on PRC:View cost inside the RPCs, never row/field-masked at the
--    view level... a table with nothing to mask" -- demonstrably wrong: the
--    RPCs gate the FULL row, so there is exactly the same amount to mask as
--    app.rfq_responses/app.rfq_responses_directory already mask correctly, in
--    the SAME batch, one migration earlier).
--
--    Fixed by mirroring app.rfq_responses' own established technique exactly:
--    REVOKE the blanket grant, column-restrict `authenticated` to the
--    non-cost columns, and mask the same columns in each `_directory` view
--    behind app.has_prc_view_cost -- for all four tables (vendor_comparisons
--    and vendor_comparison_events included: both are ALSO live-reproducibly
--    readable in full by a zero-View-cost actor via the raw table grant, even
--    though app.get_vendor_comparison/app.list_vendor_comparisons/app.get_
--    vendor_comparison_history gate the ENTIRE row on PRC:View cost -- the
--    identical bypass class, same migration, in scope for the same sweep).
--    Neither `_directory` view has any TypeScript or db-test caller today
--    (grepped clean) -- the masking is defense in depth for the grant surface
--    itself, matching the batch's own already-established rfq_responses
--    precedent, not a behavior change for any existing reader.
-- ===========================================================================

revoke select on app.vendor_comparisons from authenticated;
revoke select on app.vendor_comparison_offers from authenticated;
revoke select on app.vendor_comparison_offer_scores from authenticated;
revoke select on app.vendor_comparison_events from authenticated;

grant select (
  id, tenant_id, org_unit_id, rfq_id, sourcing_request_id, version, revised_from_id, comparison_currency, status,
  submitted_at, submitted_by, idempotency_key, record_version, created_by, created_at, updated_at,
  approval_status, approval_request_id
) on app.vendor_comparisons to authenticated;

grant select (
  id, tenant_id, comparison_id, rfq_response_id, rfq_invitation_id, vendor_master_id, rate_version_id,
  included, exclusion_reason, record_version, created_at, updated_at
) on app.vendor_comparison_offers to authenticated;

grant select (
  id, tenant_id, comparison_offer_id, criterion_key, notes, scored_by, scored_at
) on app.vendor_comparison_offer_scores to authenticated;

grant select (
  id, tenant_id, comparison_id, from_status, to_status, actor_auth_user_id, actor_label, occurred_at
) on app.vendor_comparison_events to authenticated;

-- drop + create (not `create or replace`) throughout this section: masking a
-- fixed-precision numeric column behind a `case when ... else null end` widens
-- its type to unqualified `numeric`, which `create or replace view` refuses
-- ("cannot change data type of view column") -- the same reason app.rfq_
-- responses_directory''s own masked numeric columns were never retrofitted
-- onto a `create or replace`. None of these four views has any TypeScript or
-- db-test caller (grepped clean), so a drop is safe.
drop view if exists app.vendor_comparisons_directory;

create view app.vendor_comparisons_directory as
select
  c.id, c.tenant_id, c.org_unit_id, c.rfq_id, c.sourcing_request_id, c.version, c.revised_from_id, c.comparison_currency,
  case when app.has_prc_view_cost(c.tenant_id) then c.basis_weight else null end as basis_weight,
  case when app.has_prc_view_cost(c.tenant_id) then c.basis_volume else null end as basis_volume,
  case when app.has_prc_view_cost(c.tenant_id) then c.basis_quantity else null end as basis_quantity,
  case when app.has_prc_view_cost(c.tenant_id) then c.criteria_snapshot else '[]'::jsonb end as criteria_snapshot,
  c.status,
  case when app.has_prc_view_cost(c.tenant_id) then c.recommended_offer_id else null end as recommended_offer_id,
  case when app.has_prc_view_cost(c.tenant_id) then c.recommended_reason else null end as recommended_reason,
  case when app.has_prc_view_cost(c.tenant_id) then c.recommended_at else null end as recommended_at,
  case when app.has_prc_view_cost(c.tenant_id) then c.selected_offer_id else null end as selected_offer_id,
  case when app.has_prc_view_cost(c.tenant_id) then c.selection_reason else null end as selection_reason,
  c.submitted_at, c.submitted_by,
  not app.has_prc_view_cost(c.tenant_id) as cost_masked,
  c.idempotency_key, c.record_version, c.created_by, c.created_at, c.updated_at, c.approval_status, c.approval_request_id
from app.vendor_comparisons c
where (app.has_active_tenant_membership(c.tenant_id) and not app.actor_holds_customer_user_layer(c.tenant_id)) or app.is_supreme_admin();

drop view if exists app.vendor_comparison_offers_directory;

create view app.vendor_comparison_offers_directory as
select
  o.id, o.tenant_id, o.comparison_id, o.rfq_response_id, o.rfq_invitation_id, o.vendor_master_id, o.rate_version_id,
  case when app.has_prc_view_cost(o.tenant_id) then o.source_currency else null end as source_currency,
  case when app.has_prc_view_cost(o.tenant_id) then o.source_total_amount else null end as source_total_amount,
  case when app.has_prc_view_cost(o.tenant_id) then o.engine_computed_amount else null end as engine_computed_amount,
  case when app.has_prc_view_cost(o.tenant_id) then o.engine_currency else null end as engine_currency,
  case when app.has_prc_view_cost(o.tenant_id) then o.engine_breakdown else '{}'::jsonb end as engine_breakdown,
  case when app.has_prc_view_cost(o.tenant_id) then o.normalized_amount else null end as normalized_amount,
  case when app.has_prc_view_cost(o.tenant_id) then o.normalization_lineage else '{}'::jsonb end as normalization_lineage,
  o.included, o.exclusion_reason,
  case when app.has_prc_view_cost(o.tenant_id) then o.price_score else null end as price_score,
  case when app.has_prc_view_cost(o.tenant_id) then o.non_price_score else null end as non_price_score,
  case when app.has_prc_view_cost(o.tenant_id) then o.composite_score else null end as composite_score,
  case when app.has_prc_view_cost(o.tenant_id) then o.rank else null end as rank,
  not app.has_prc_view_cost(o.tenant_id) as cost_masked,
  o.record_version, o.created_at, o.updated_at
from app.vendor_comparison_offers o
where (app.has_active_tenant_membership(o.tenant_id) and not app.actor_holds_customer_user_layer(o.tenant_id)) or app.is_supreme_admin();

drop view if exists app.vendor_comparison_offer_scores_directory;

create view app.vendor_comparison_offer_scores_directory as
select
  s.id, s.tenant_id, s.comparison_offer_id, s.criterion_key,
  case when app.has_prc_view_cost(s.tenant_id) then s.criterion_weight else null end as criterion_weight,
  case when app.has_prc_view_cost(s.tenant_id) then s.score else null end as score,
  s.notes, s.scored_by, s.scored_at,
  not app.has_prc_view_cost(s.tenant_id) as cost_masked
from app.vendor_comparison_offer_scores s
where (app.has_active_tenant_membership(s.tenant_id) and not app.actor_holds_customer_user_layer(s.tenant_id)) or app.is_supreme_admin();

drop view if exists app.vendor_comparison_events_directory;

create view app.vendor_comparison_events_directory as
select
  e.id, e.tenant_id, e.comparison_id, e.from_status, e.to_status,
  case when app.has_prc_view_cost(e.tenant_id) then e.reason else null end as reason,
  case when app.has_prc_view_cost(e.tenant_id) then e.evidence_ref else null end as evidence_ref,
  e.actor_auth_user_id, e.actor_label, e.occurred_at,
  not app.has_prc_view_cost(e.tenant_id) as cost_masked
from app.vendor_comparison_events e
where (app.has_active_tenant_membership(e.tenant_id) and not app.actor_holds_customer_user_layer(e.tenant_id)) or app.is_supreme_admin();

comment on view app.vendor_comparisons_directory is 'PRC-258, hardened batch 257-259 review (C-11, CRITICAL): field-masked projection of app.vendor_comparisons -- basis_weight/basis_volume/basis_quantity/criteria_snapshot/recommended_offer_id/recommended_reason/recommended_at/selected_offer_id/selection_reason nulled (cost_masked=true) for a caller lacking PRC:View cost, mirroring app.rfq_responses_directory''s own established technique. Was previously a plain, unmasked `select c.*` -- the base table''s own `authenticated` grant is now column-restricted to match.';
comment on view app.vendor_comparison_offers_directory is 'PRC-258, hardened batch 257-259 review (C-11, CRITICAL): field-masked projection of app.vendor_comparison_offers -- every cost-bearing column (source/engine/normalized amounts, breakdown, lineage, price/non-price/composite scores, rank) nulled (cost_masked=true) for a caller lacking PRC:View cost. Live-reproduced before this fix: a PRC:View-only (no View cost) tenant member read real bid amounts and ranks directly off the base table, which the RPC layer (app.list_vendor_comparison_offers) correctly denied.';
comment on view app.vendor_comparison_offer_scores_directory is 'PRC-258, hardened batch 257-259 review (C-11, CRITICAL): field-masked projection of app.vendor_comparison_offer_scores -- score/criterion_weight nulled (cost_masked=true) for a caller lacking PRC:View cost, mirroring app.list_vendor_comparison_offer_scores'' own RPC-level gate.';
comment on view app.vendor_comparison_events_directory is 'PRC-258, hardened batch 257-259 review (C-11, CRITICAL): field-masked projection of app.vendor_comparison_events -- reason/evidence_ref nulled (cost_masked=true) for a caller lacking PRC:View cost, mirroring app.get_vendor_comparison_history''s own RPC-level gate.';

-- Re-GRANT: dropping each view above also dropped its own prior grants.
grant select on app.vendor_comparisons_directory to authenticated, service_role;
grant select on app.vendor_comparison_offers_directory to authenticated, service_role;
grant select on app.vendor_comparison_offer_scores_directory to authenticated, service_role;
grant select on app.vendor_comparison_events_directory to authenticated, service_role;

-- ===========================================================================
-- 4. C-04 (correctness/concurrency lens, HIGH): app.decide_vendor_profile_review
--    read app.vendor_profiles WITHOUT a lock, unlike every other governed-entity
--    RPC this same migration widened. A concurrent double-decide (double-click,
--    client retry) with the SAME p_expected_version both pass the version/
--    lifecycle checks and both derive the IDENTICAL governance routing
--    idempotency key ('vendor_activation:' || master_record_id || ':v' ||
--    v_next_version), so the loser crashes on a raw, unhandled unique_violation
--    from app.request_approval's own INSERT -- live-reproduced with two real
--    overlapping psql transactions. Fixed by taking `for update` on the first
--    read, matching every sibling governed-entity RPC's own lock discipline in
--    this migration (app.submit_vendor_comparison_for_approval locks its
--    parent row first, etc.) -- the concurrent second caller now blocks until
--    the first commits, then re-reads the now-updated row and fails cleanly at
--    the pre-existing record_version/lifecycle_status checks instead of ever
--    reaching the routing call with a colliding key.
--
--    Note (disclosed, not fixed here): the underlying defense-in-depth gap --
--    app.request_approval's own INSERT (PLT-123, `20260719090000_create_
--    approval_engine.sql`, unmodified by this batch) has no `exception when
--    unique_violation` handler of its own -- is pre-existing PLT-123 code
--    shared by every domain that composes the Platform Approval Engine
--    (Commercial quotation/credit approvals included), not specific to this
--    batch's own files, and is registered as ISS-2026-044 in
--    docs/runtime/KNOWN_ISSUES.md rather than patched here. This migration's
--    own fix closes the ONLY reachable path to that collision this batch's
--    code introduces (the missing lock); no other call site in this batch
--    reaches app.request_approval with a caller-influenced, potentially
--    colliding key without first holding a row lock that already serializes it
--    (app._request_procurement_entity_approval's own callers all either hold a
--    lock already or, for app.create_procurement_exception_request, are fixed
--    below with an explicit advisory lock).
-- ===========================================================================

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

  -- Batch 257-259 review (C-04, HIGH): locked, closing a live-reproduced
  -- concurrent-double-decide crash (see migration header above this function).
  select * into v_profile from app.vendor_profiles where master_record_id = p_master_record_id for update;
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

comment on function app.decide_vendor_profile_review is 'PRC-251, widened PRC-259: unchanged signature. approve (-> approved, PRC:Approve) or reject (-> draft with revision_reason set, PRC:Reject, reason mandatory) -- reachable from submitted or under_review. The approve arm additionally routes for platform-engine governance approval when app.procurement_approval_policies has a published vendor_activation policy the tenant crossed -- app.activate_vendor_profile then requires approval_status in (approved, not_required) before the profile can actually go active. Batch 257-259 review (C-04, HIGH): the initial read now takes `for update`, closing a live-reproduced concurrent-double-decide crash on a colliding governance idempotency key.';

-- ===========================================================================
-- 5. C-04 (correctness/concurrency lens, HIGH): app.close_rfq_for_comparison
--    locked app.rfqs FIRST, then implicitly locked app.rfq_invitations rows
--    second via an unlocked bulk UPDATE -- the exact inverse of "design note 8"
--    (child locked before parent), which app.submit_rfq_response and app.
--    decline_rfq_invitation both already follow correctly. Live-reproduced as a
--    genuine Postgres deadlock (SQLSTATE 40P01) between a real, unmodified
--    app.close_rfq_for_comparison call and a concurrent session taking the
--    invitation-then-rfq lock order app.submit_rfq_response's own code takes,
--    on the same RFQ's two different rows. Fixed by locking every still-
--    'invited' app.rfq_invitations row for this rfq_id BEFORE locking/reading
--    app.rfqs, matching design note 8's own documented order.
-- ===========================================================================

create or replace function app.close_rfq_for_comparison(
  p_rfq_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.rfqs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_rfq app.rfqs;
begin
  -- Batch 257-259 review (C-04, HIGH): child (invitations) locked before parent
  -- (rfq), matching design note 8 and closing a live-reproduced deadlock against
  -- app.submit_rfq_response/app.decline_rfq_invitation's own established order.
  -- A no-op (locks nothing) when p_rfq_id has zero currently-invited invitations.
  perform 1 from app.rfq_invitations where rfq_id = p_rfq_id and status = 'invited' for update;

  select * into v_rfq from app.rfqs where id = p_rfq_id for update;
  if not found then
    raise exception 'rfq_not_found: %', p_rfq_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_rfq.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_rfq.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_rfq.record_version <> p_expected_version then
    raise exception 'stale_version: rfq % expected version % but found %', p_rfq_id, p_expected_version, v_rfq.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_rfq.status <> 'issued' then
    raise exception 'invalid_transition: rfq % is % and cannot be closed for comparison', p_rfq_id, v_rfq.status
      using errcode = 'check_violation';
  end if;

  update app.rfq_invitations set status = 'no_response' where rfq_id = p_rfq_id and status = 'invited';

  update app.rfqs
  set status = 'closed', closed_at = now()
  where id = p_rfq_id and record_version = p_expected_version
  returning * into v_rfq;
  if not found then
    raise exception 'stale_version: rfq % target row was concurrently modified (expected version %)', p_rfq_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.rfq_events (tenant_id, rfq_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (v_rfq.tenant_id, p_rfq_id, 'issued', 'closed', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_rfq.tenant_id, p_actor_auth_user_id, p_actor_label, 'close_rfq_for_comparison',
    'app.rfqs', v_rfq.id, 'success', null, null, jsonb_build_object('status', v_rfq.status)
  );

  return v_rfq;
end;
$$;

comment on function app.close_rfq_for_comparison is 'PRC-257: issued -> closed. Every still-invited (no response ever submitted) invitation is marked no_response. Comparison reads app.list_rfq_responses for this RFQ once closed -- comparison_eligible already distinguishes on-time vs late-captured responses. Batch 257-259 review (C-04, HIGH): now locks invitations before the rfq (design note 8), closing a live-reproduced deadlock against app.submit_rfq_response/app.decline_rfq_invitation''s own established invitation-then-rfq order.';

-- ===========================================================================
-- 6. C-04/C-01-adjacent (correctness/concurrency lens, HIGH): app.create_
--    procurement_exception_request's own idempotency check (an unlocked select
--    against app.procurement_exception_requests) ran BEFORE it calls app.
--    _request_procurement_entity_approval, which opens a real, fully-routed
--    app.approval_requests row using a FRESH gen_random_uuid()-derived key that
--    never collides across two racing calls with the SAME caller-supplied
--    p_idempotency_key. Live-reproduced with two real concurrent psql sessions:
--    both returned the same procurement_exception_requests row (no error
--    surfaced), but app.approval_requests grew by TWO rows, not one -- the
--    second, losing race's own governance request is permanently orphaned
--    (referenced by no procurement_exception_requests row), yet its first step
--    still appears in a real approver's pending inbox and deciding it silently
--    returns an all-NULL composite with no SQL error, which crashes the
--    TypeScript layer (parseProcurementExceptionRequest requires a non-null
--    uuid id) instead of surfacing a typed error.
--
--    Fixed by serializing on (tenant_id, idempotency_key) via
--    pg_advisory_xact_lock BEFORE the idempotency check, mirroring this
--    repository's own established per-key advisory-lock idiom (e.g. app.
--    register_gps_device, app.recalculate_vendor_compliance_status_family).
--    A genuine concurrent retry with the same key now blocks until the first
--    attempt's row (and its own real approval_requests row) commits, then
--    replays cleanly with no second approval_requests row ever created.
--
--    Defense in depth: the four domain sync wrappers (decide_vendor_activation_
--    approval_step / decide_rate_version_approval_step / decide_vendor_
--    selection_approval_step / decide_procurement_exception_approval_step) now
--    also raise a clear, typed not-found error instead of silently returning an
--    all-NULL composite when the bound entity no longer resolves -- see section
--    8 below -- so any residual pre-existing orphan (from before this fix) or
--    any other unforeseen path fails loudly rather than crashing the caller
--    with an opaque Zod error.
-- ===========================================================================

create or replace function app.create_procurement_exception_request(
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
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: p_idempotency_key must not be empty' using errcode = 'check_violation';
  end if;

  -- Batch 257-259 review (C-04/C-01-adjacent, HIGH): serialize a genuine
  -- concurrent retry with the same (tenant, idempotency_key) BEFORE the
  -- idempotency check below, closing a live-reproduced orphaned-approval-
  -- request race (see migration header above this function).
  perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text || ':' || p_idempotency_key, 0));

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
  'PRC-259: PRC:Override, mandatory reason. Routes for platform-engine governance approval when app.procurement_approval_policies has a published exception_override policy (always_required, since this entity has no value dimension -- see procurement_approval_policies_value_dimension_check). status starts submitted when routed, or auto-approved immediately when no policy is published for this tenant (opt-in, matching every other governed entity_type''s own precedent) -- the grant IS the approval outcome, there is no further release step. Batch 257-259 review (C-04/C-01-adjacent, HIGH): now takes a per-(tenant, idempotency_key) advisory lock before its own idempotency check, closing a live-reproduced race that orphaned a real, fully-routed app.approval_requests row on a genuine concurrent retry.';

-- ===========================================================================
-- 7. C-08 (cross-prompt lens, HIGH): this migration's own ALTER TABLE widened
--    app.vendor_rate_versions with two new PRC-governance columns
--    (governance_approval_status / governance_approval_request_id). The
--    pre-existing, already-VERIFIED COM-149/PRC-255 function app.select_vendor_
--    rate (`20260730620000_extend_commercial_vendor_rate_for_procurement.sql`)
--    snapshots the ENTIRE rate row via `to_jsonb(v_rate)` into app.rate_
--    selections.snapshot on its flat (non-tier) branch, gated only by the
--    pre-existing COM:Edit + COM:View cost check (no PRC permission at all) --
--    Postgres composite row types widen automatically, so the two new PRC-
--    gated columns are now silently included in that snapshot for every
--    caller, and app.rate_selections_directory only masks on COM:View cost,
--    never PRC:View. Live-confirmed: `to_jsonb(v)::jsonb ? 'governance_
--    approval_status'` is true for the widened `app.vendor_rate_versions` row
--    type. This is the exact defect class app.select_vendor_rate itself
--    already had to be hardened against once for PRC-255's own tier-cost
--    fields (see this function's own header comment). Fixed by stripping the
--    two governance keys from the snapshot at write time, mirroring app.draft_
--    rfq_from_sourcing's own `demand_snapshot - 'budget_amount'` write-time
--    strip precedent -- the read path (app.rate_selections_directory) is
--    unchanged, no new PRC check is added to a function whose own authority
--    model this migration has no mandate to widen.
-- ===========================================================================

create or replace function app.select_vendor_rate(
  p_costing_request_id uuid,
  p_rate_version_id uuid,
  p_is_adhoc boolean,
  p_adhoc_currency text,
  p_adhoc_amount numeric,
  p_override_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_weight numeric default null,
  p_volume numeric default null,
  p_quantity numeric default null
)
returns app.rate_selections
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_request app.costing_requests;
  v_decision_edit app.rbac_decision;
  v_decision_prc_cost app.rbac_decision;
  v_rate app.vendor_rate_versions;
  v_selection app.rate_selections;
  v_calc record;
  v_amount numeric;
  v_snapshot jsonb;
begin
  select * into v_request from app.costing_requests where id = p_costing_request_id;
  if not found then
    raise exception 'costing_request_not_found: %', p_costing_request_id using errcode = 'no_data_found';
  end if;

  if v_request.status in ('cancelled', 'superseded') then
    raise exception 'invalid_transition: costing request % is % and cannot accept a rate selection', p_costing_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  v_decision_edit := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'COM', 'Edit');
  if not v_decision_edit.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision_edit.reason, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.has_view_cost(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks COM:View cost required to select a rate', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_request.tenant_id, v_request.owner_user_id, app.lead_record_scope_org_unit_ids(v_request.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access costing request %', p_actor_auth_user_id, p_costing_request_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_is_adhoc then
    if p_override_reason is null or length(trim(p_override_reason)) = 0 then
      raise exception 'reason_required: an ad-hoc rate selection requires a non-empty override reason'
        using errcode = 'not_null_violation';
    end if;
    if p_adhoc_currency is null or p_adhoc_currency !~ '^[A-Z]{3}$' or p_adhoc_amount is null or p_adhoc_amount < 0 then
      raise exception 'invalid_adhoc_rate: an ad-hoc selection requires a valid 3-letter currency and a non-negative amount'
        using errcode = 'check_violation';
    end if;

    insert into app.rate_selections (tenant_id, costing_request_id, rate_version_id, is_adhoc, currency, amount, snapshot, override_reason, selected_by)
    values (
      v_request.tenant_id, p_costing_request_id, null, true, p_adhoc_currency, p_adhoc_amount,
      jsonb_build_object('is_adhoc', true, 'currency', p_adhoc_currency, 'amount', p_adhoc_amount, 'override_reason', p_override_reason),
      p_override_reason, p_actor_label
    )
    returning * into v_selection;
  else
    select * into v_rate from app.vendor_rate_versions where id = p_rate_version_id;
    if not found then
      raise exception 'rate_version_not_found: %', p_rate_version_id using errcode = 'no_data_found';
    end if;
    if v_rate.tenant_id <> v_request.tenant_id then
      raise exception 'tenant_mismatch: rate version % does not belong to tenant %', p_rate_version_id, v_request.tenant_id
        using errcode = 'check_violation';
    end if;
    if v_rate.approval_status <> 'approved' and (p_override_reason is null or length(trim(p_override_reason)) = 0) then
      raise exception 'reason_required: selecting a % (not approved) rate version requires a non-empty override reason', v_rate.approval_status
        using errcode = 'not_null_violation';
    end if;

    -- PRC-255 addition: when tier-matching inputs are supplied, snapshot the exact
    -- tier-matched calculation (RPD-040) via the SAME private helper app.calculate_
    -- vendor_rate itself calls -- omitting them (every pre-PRC-255 caller)
    -- reproduces COM-149's original flat base_amount behavior unchanged.
    --
    -- SECURITY FIX (post-review): computing a tier-matched amount embeds the
    -- SAME sensitive tier cost breakdown (matched_tier_id, matched_tier_amount,
    -- tier_component, ...) that app.calculate_vendor_rate/app.vendor_rate_tiers_
    -- directory correctly gate behind PRC:View cost (design note 2/ADR-0020's own
    -- directed reuse of that gate for this checkpoint's new sensitive-field
    -- class). The pre-existing COM:Edit + COM:View cost gate above is COM-149's
    -- own unchanged authority for the flat-base_amount case, but it is NOT
    -- sufficient authority for the tier-derived case -- a Commercial-side actor
    -- holding only COM:View cost (no PRC permissions at all) could otherwise
    -- supply p_weight/p_volume/p_quantity and receive the full negotiated
    -- vendor-tier cost structure in the returned snapshot, bypassing the separate
    -- PRC:View cost boundary this migration's own design intends. So: PRC:View
    -- cost is required IN ADDITION to the unchanged COM gates, but ONLY on this
    -- branch (tier inputs supplied) -- every pre-PRC-255 caller (all three null)
    -- never reaches this check and is completely unaffected.
    if p_weight is not null or p_volume is not null or p_quantity is not null then
      v_decision_prc_cost := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'PRC', 'View cost');
      if not v_decision_prc_cost.allowed then
        raise exception 'insufficient_authority: identity % lacks PRC:View cost (%) required to compute/snapshot a tier-matched rate amount', p_actor_auth_user_id, v_decision_prc_cost.reason
          using errcode = 'insufficient_privilege';
      end if;
      select * into v_calc from app._compute_vendor_rate_amount(v_rate, p_weight, p_volume, p_quantity);
      v_amount := v_calc.computed_amount;
      -- Batch 257-259 review (C-08, HIGH): strip the two PRC-259 governance
      -- columns app.vendor_rate_versions was widened with -- to_jsonb(v_rate)
      -- would otherwise silently carry them into a snapshot this function's own
      -- COM-only authority model never re-checks against PRC:View.
      v_snapshot := (to_jsonb(v_rate) - 'governance_approval_status' - 'governance_approval_request_id') || jsonb_build_object('calculation', to_jsonb(v_calc));
    else
      v_amount := v_rate.base_amount;
      v_snapshot := to_jsonb(v_rate) - 'governance_approval_status' - 'governance_approval_request_id';
    end if;

    insert into app.rate_selections (tenant_id, costing_request_id, rate_version_id, is_adhoc, currency, amount, snapshot, override_reason, selected_by)
    values (
      v_request.tenant_id, p_costing_request_id, v_rate.id, false, v_rate.currency, v_amount, v_snapshot, p_override_reason, p_actor_label
    )
    returning * into v_selection;
  end if;

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'select_vendor_rate',
    'app.rate_selections', v_selection.id, 'success', null, null,
    jsonb_build_object('costing_request_id', p_costing_request_id, 'is_adhoc', v_selection.is_adhoc, 'rate_version_id', v_selection.rate_version_id)
  );

  return v_selection;
end;
$$;

comment on function app.select_vendor_rate is 'COM-149, widened PRC-255: three new optional trailing parameters (p_weight, p_volume, p_quantity). Every pre-PRC-255 caller (all null) reproduces the original flat base_amount snapshot unchanged and needs only the unchanged COM:Edit + COM:View cost gate; supplying any of them additionally REQUIRES PRC:View cost (post-review security fix -- computing/snapshotting a tier-matched amount exposes the same sensitive tier cost breakdown app.calculate_vendor_rate/app.vendor_rate_tiers_directory correctly gate on PRC:View cost, and COM:View cost alone must never be sufficient to read it). Batch 257-259 review (C-08, HIGH): the snapshot now strips governance_approval_status/governance_approval_request_id (added to app.vendor_rate_versions by PRC-259) at write time on both branches, closing a live-confirmed silent leak of PRC-gated governance fields to a COM:View-cost-only, zero-PRC caller via to_jsonb(v_rate)''s automatic composite widening.';

-- ===========================================================================
-- 8. C-18 (spec-compliance lens, HIGH): Prompt 259's own source spec requires
--    MFA for privileged financial/credential approvals in seven places (§16,
--    §18, §23, §25, §27, §28, §33 acceptance criteria) -- completely absent
--    from this migration (grepped clean: zero mfa|MFA|reauth matches anywhere
--    in the migration, the server layer, or the UI). The build log's own
--    Tier B walk incorrectly marked this "N/A" on the claim that the Platform
--    Approval Engine "already provides it uniformly" -- the engine
--    (`20260719090000_create_approval_engine.sql`) has zero MFA/reauth
--    construct of its own. This repository already has a proven, reusable
--    pattern for exactly this requirement -- `p_reauth_confirmed_at
--    timestamptz` with a 5-minute freshness window, established at PRC-254
--    (`app.decide_vendor_bank_account_approval` et al.) and reused verbatim at
--    COM-157 (`app.decide_credit_profile_approval_step`) -- composed here into
--    all four PRC-259 domain decide-wrappers (the PRC:Approve/Reject-gated
--    governance decision points this capability adds). Adding a new required
--    parameter changes each function's signature, so `DROP FUNCTION` +
--    `CREATE FUNCTION` (this repository's own established technique, e.g.
--    `20260730620000_extend_commercial_vendor_rate_for_procurement.sql`'s own
--    `p_weight`/`p_volume`/`p_quantity` widen) is used, with an explicit
--    re-`GRANT` after each. Callers reach these RPCs exclusively through
--    Supabase's named-parameter `.rpc()` call convention (never positional),
--    so the new parameter's position in the SQL signature does not by itself
--    require the server layer's own call sites to change ordering -- they are
--    updated in the same commit regardless, to actually supply the new value
--    (server/contracts, server/mutations, and the approvals decision UI).
--
--    Also folds in the F8 defense-in-depth guard (section 6 above): each
--    wrapper now raises a clear, typed not-found error instead of silently
--    returning an all-NULL composite when the bound entity no longer resolves.
-- ===========================================================================

drop function app.decide_vendor_activation_approval_step(uuid, text, uuid, text, text);

create function app.decide_vendor_activation_approval_step(
  p_request_step_id uuid,
  p_decision text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_reauth_confirmed_at timestamptz,
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

  -- Batch 257-259 review (C-18, HIGH): Prompt 259 §16/§18/§23/§25/§27/§28/§33
  -- require MFA for this exact class of privileged approval decision -- the
  -- established p_reauth_confirmed_at/5-minute-freshness pattern (PRC-254,
  -- reused at COM-157), not a new construct.
  if p_reauth_confirmed_at is null or p_reauth_confirmed_at > now() or now() - p_reauth_confirmed_at > interval '5 minutes' then
    raise exception 'reauth_required: re-authentication must have completed within the last 5 minutes'
      using errcode = 'insufficient_privilege';
  end if;

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

  -- Batch 257-259 review (F8 defense in depth, HIGH): a bound entity that no
  -- longer resolves (e.g. a pre-existing orphaned request from before section 6's
  -- own fix) now fails loudly instead of returning an all-NULL composite that
  -- crashes the TypeScript layer's own non-nullable id parse.
  if v_profile.master_record_id is null then
    raise exception 'vendor_activation_target_not_found: approval request % entity % no longer resolves to a vendor profile', v_request.id, v_request.entity_id
      using errcode = 'no_data_found';
  end if;

  return v_profile;
end;
$$;

comment on function app.decide_vendor_activation_approval_step is
  'PRC-259: wraps app.decide_approval_step (PLT-123, unchanged) and syncs app.vendor_profiles.approval_status only once the bound request reaches a final state (approved/rejected). Never itself calls app.activate_vendor_profile -- the vendor still needs its own explicit activation call once approval_status clears, exactly mirroring app.decide_quotation_approval_step never itself calling app.send_quotation_for_acceptance. Batch 257-259 review (C-18, HIGH): now requires p_reauth_confirmed_at (5-minute MFA freshness window, PRC-254/COM-157 pattern) and raises a typed not-found error instead of an all-NULL composite when the bound entity is missing.';

grant execute on function app.decide_vendor_activation_approval_step(uuid, text, uuid, text, timestamptz, text) to authenticated, service_role;

drop function app.decide_rate_version_approval_step(uuid, text, uuid, text, text);

create function app.decide_rate_version_approval_step(
  p_request_step_id uuid,
  p_decision text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_reauth_confirmed_at timestamptz,
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

  if p_reauth_confirmed_at is null or p_reauth_confirmed_at > now() or now() - p_reauth_confirmed_at > interval '5 minutes' then
    raise exception 'reauth_required: re-authentication must have completed within the last 5 minutes'
      using errcode = 'insufficient_privilege';
  end if;

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

  if v_rate.id is null then
    raise exception 'rate_version_target_not_found: approval request % entity % no longer resolves to a vendor rate version', v_request.id, v_request.entity_id
      using errcode = 'no_data_found';
  end if;

  return v_rate;
end;
$$;

comment on function app.decide_rate_version_approval_step is
  'PRC-259: wraps app.decide_approval_step (PLT-123, unchanged) and syncs app.vendor_rate_versions.governance_approval_status only once the bound request reaches a final state -- never touches the pre-existing approval_status column. Batch 257-259 review (C-18, HIGH): now requires p_reauth_confirmed_at (5-minute MFA freshness window, PRC-254/COM-157 pattern) and raises a typed not-found error instead of an all-NULL composite when the bound entity is missing.';

grant execute on function app.decide_rate_version_approval_step(uuid, text, uuid, text, timestamptz, text) to authenticated, service_role;

drop function app.decide_vendor_selection_approval_step(uuid, text, uuid, text, text);

create function app.decide_vendor_selection_approval_step(
  p_request_step_id uuid,
  p_decision text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_reauth_confirmed_at timestamptz,
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

  if p_reauth_confirmed_at is null or p_reauth_confirmed_at > now() or now() - p_reauth_confirmed_at > interval '5 minutes' then
    raise exception 'reauth_required: re-authentication must have completed within the last 5 minutes'
      using errcode = 'insufficient_privilege';
  end if;

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

  if v_comparison.id is null then
    raise exception 'vendor_selection_target_not_found: approval request % entity % no longer resolves to a vendor comparison', v_request.id, v_request.entity_id
      using errcode = 'no_data_found';
  end if;

  return v_comparison;
end;
$$;

comment on function app.decide_vendor_selection_approval_step is
  'PRC-259: wraps app.decide_approval_step (PLT-123, unchanged) and syncs app.vendor_comparisons.approval_status only once the bound request reaches a final state. Relies on app.vendor_comparisons'' own before-update trigger to bump record_version -- no manual increment needed in the UPDATE SET clause here. Batch 257-259 review (C-18, HIGH): now requires p_reauth_confirmed_at (5-minute MFA freshness window, PRC-254/COM-157 pattern) and raises a typed not-found error instead of an all-NULL composite when the bound entity is missing.';

grant execute on function app.decide_vendor_selection_approval_step(uuid, text, uuid, text, timestamptz, text) to authenticated, service_role;

drop function app.decide_procurement_exception_approval_step(uuid, text, uuid, text, text);

create function app.decide_procurement_exception_approval_step(
  p_request_step_id uuid,
  p_decision text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_reauth_confirmed_at timestamptz,
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

  if p_reauth_confirmed_at is null or p_reauth_confirmed_at > now() or now() - p_reauth_confirmed_at > interval '5 minutes' then
    raise exception 'reauth_required: re-authentication must have completed within the last 5 minutes'
      using errcode = 'insufficient_privilege';
  end if;

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

  if v_row.id is null then
    raise exception 'procurement_exception_target_not_found: approval request % entity % no longer resolves to a procurement exception request', v_request.id, v_request.entity_id
      using errcode = 'no_data_found';
  end if;

  return v_row;
end;
$$;

comment on function app.decide_procurement_exception_approval_step is
  'PRC-259: wraps app.decide_approval_step (PLT-123, unchanged). Unlike the other three domain sync wrappers, this one ALSO syncs status (not just approval_status) -- an exception request has no further release step, so the governance outcome IS the terminal domain status. Batch 257-259 review (C-18, HIGH): now requires p_reauth_confirmed_at (5-minute MFA freshness window, PRC-254/COM-157 pattern) and raises a typed not-found error instead of an all-NULL composite when the bound entity is missing -- this is the exact function that live-reproduced the F8 orphan-composite crash before this fix.';

grant execute on function app.decide_procurement_exception_approval_step(uuid, text, uuid, text, timestamptz, text) to authenticated, service_role;

-- ===========================================================================
-- 9. C-18-adjacent (spec-compliance lens, MEDIUM): Prompt 259's own business
--    rule ("Rejection/revision/delegation/escalation/override require reason
--    and complete audit", §24) is enforced only in the Next.js Server Action
--    (decideProcurementApprovalStepAction), never at the RPC/database layer --
--    bypassable by any authenticated session with real approval eligibility
--    calling the granted RPC directly. The identical gap already existed in
--    app.decide_quotation_approval_step (COM-153, already VERIFIED), which
--    PRC-259 copied forward without closing. Fixed at the single shared choke
--    point every one of these domain wrappers composes -- app.decide_
--    approval_step itself (PLT-123, `20260719090000_create_approval_engine.
--    sql`) -- so COM-153/COM-157/PRC-259 all close at once, per the
--    propagation-sweep discipline (`BUILD_EXECUTION_PROTOCOL.md` §5.4).
--    Verified against every existing db-test 'rejected' call site in this
--    repository (`approval.sql`, `commercial-quotation-approval.sql`,
--    `commercial-credit-commercial-control.sql`, `procurement-approval.sql`) --
--    every one already supplies a real, non-empty reason, so this tightening
--    changes no currently-passing test's expected outcome. Same 5-argument
--    signature, CREATE OR REPLACE only (no re-GRANT needed).
-- ===========================================================================

create or replace function app.decide_approval_step(
  p_request_step_id uuid,
  p_decision text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_reason text default null
)
returns app.approval_request_steps
language plpgsql
as $$
declare
  v_step app.approval_request_steps;
  v_request app.approval_requests;
  v_allow_self_approval boolean;
  v_updated_step app.approval_request_steps;
  v_next_step_id uuid;
  v_remaining_active integer;
  v_approved_step_count integer;
  v_total_step_count integer;
  v_threshold_required_steps integer;
begin
  if p_decision not in ('approved', 'rejected') then
    raise exception 'approval_invalid_decision: decision % must be approved or rejected', p_decision
      using errcode = 'check_violation';
  end if;

  -- Batch 257-259 review (C-18-adjacent, MEDIUM): a reject requires a real
  -- reason at the RPC layer itself, not only in a calling Server Action --
  -- closes the identical, previously-undisclosed gap in every domain that
  -- composes this shared engine function (quotation/credit/procurement).
  if p_decision = 'rejected' and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'reason_required: a non-empty reason is required to reject an approval step' using errcode = 'check_violation';
  end if;

  select * into v_step from app.approval_request_steps where id = p_request_step_id;
  if not found then
    raise exception 'approval_step_not_found: no approval request step %', p_request_step_id
      using errcode = 'no_data_found';
  end if;
  select * into v_request from app.approval_requests where id = v_step.request_id;

  if not app.check_approval_request_authority(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_request.status <> 'pending' then
    raise exception 'approval_request_not_pending: request % is %, only a pending request can be decided', v_request.id, v_request.status
      using errcode = 'check_violation';
  end if;
  if v_step.status <> 'active' then
    raise exception 'approval_step_not_active: step % is %, only an active step can be decided', p_request_step_id, v_step.status
      using errcode = 'check_violation';
  end if;

  select coalesce((value #>> '{}')::boolean, false) into v_allow_self_approval
  from app.config_items where config_version_id = v_request.config_version_id and key = 'allow_self_approval';
  if not coalesce(v_allow_self_approval, false) and v_request.requested_by_auth_user_id = p_actor_auth_user_id then
    raise exception 'approval_self_approval_denied: identity % requested this approval and self-approval is not allowed', p_actor_auth_user_id
      using errcode = 'check_violation';
  end if;

  if not app.is_eligible_approval_approver(v_step, v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an eligible approver for step %', p_actor_auth_user_id, p_request_step_id
      using errcode = 'insufficient_privilege';
  end if;

  begin
    insert into app.approval_decisions (request_step_id, actor_auth_user_id, actor_label, decision, reason)
    values (p_request_step_id, p_actor_auth_user_id, p_actor_label, p_decision, p_reason);
  exception
    when unique_violation then
      raise exception 'approval_decision_already_recorded: identity % has already decided step %', p_actor_auth_user_id, p_request_step_id
        using errcode = 'unique_violation';
  end;

  if p_decision = 'rejected' then
    update app.approval_request_steps set status = 'rejected' where id = p_request_step_id and status = 'active' returning * into v_updated_step;
    if not found then
      raise exception 'approval_step_not_active: step % changed concurrently, no longer active', p_request_step_id
        using errcode = 'check_violation';
    end if;
    update app.approval_request_steps set status = 'skipped' where request_id = v_request.id and status in ('pending', 'active') and id <> p_request_step_id;
    update app.approval_requests set status = 'rejected', ended_at = now(), ended_reason = p_reason where id = v_request.id;
  else
    update app.approval_request_steps
    set approvals_count = approvals_count + 1,
        status = case when approvals_count + 1 >= required_approvals then 'approved' else 'active' end
    where id = p_request_step_id and status = 'active'
    returning * into v_updated_step;
    if not found then
      raise exception 'approval_step_not_active: step % changed concurrently, no longer active', p_request_step_id
        using errcode = 'check_violation';
    end if;

    if v_updated_step.status = 'approved' then
      if v_request.pattern = 'sequential' then
        select id into v_next_step_id from app.approval_request_steps where request_id = v_request.id and step_order = v_updated_step.step_order + 1;
        if found then
          update app.approval_request_steps set status = 'active' where id = v_next_step_id;
        else
          update app.approval_requests set status = 'approved', ended_at = now(), ended_reason = 'all sequential steps approved' where id = v_request.id;
        end if;
      elsif v_request.pattern = 'parallel' then
        select count(*) into v_remaining_active from app.approval_request_steps where request_id = v_request.id and status not in ('approved', 'skipped');
        if v_remaining_active = 0 then
          update app.approval_requests set status = 'approved', ended_at = now(), ended_reason = 'all parallel steps approved' where id = v_request.id;
        end if;
      else -- threshold
        select count(*) into v_approved_step_count from app.approval_request_steps where request_id = v_request.id and status = 'approved';
        select count(*) into v_total_step_count from app.approval_request_steps where request_id = v_request.id;
        select (value #>> '{}')::integer into v_threshold_required_steps from app.config_items where config_version_id = v_request.config_version_id and key = 'threshold_required_steps';
        if v_approved_step_count >= v_threshold_required_steps then
          update app.approval_request_steps set status = 'skipped' where request_id = v_request.id and status in ('pending', 'active');
          update app.approval_requests set status = 'approved', ended_at = now(), ended_reason = format('threshold %s of %s steps approved', v_threshold_required_steps, v_total_step_count) where id = v_request.id;
        end if;
      end if;
    end if;
  end if;

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_approval_step',
    'app.approval_request_steps', p_request_step_id, 'success', p_reason, to_jsonb(v_step), to_jsonb(v_updated_step)
  );

  select * into v_updated_step from app.approval_request_steps where id = p_request_step_id;
  return v_updated_step;
end;
$$;

comment on function app.decide_approval_step is 'PLT-123: the core decision engine (Prompt 123 §20 task 3/§21/§22/§25). Real optimistic concurrency and no-duplicate-decision protection come from two structural guarantees: the atomic UPDATE ... WHERE status = ''active'' below, and approval_decisions'' own unique(request_step_id, actor_auth_user_id). Batch 257-259 review (C-18-adjacent, MEDIUM): a reject now requires a non-empty p_reason at this shared choke point, closing an RPC-layer gap every domain composing this engine (quotation/credit/procurement approvals) previously had, enforced client-side only.';
