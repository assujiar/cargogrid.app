-- Finance capability FIN-205 (Draft-versus-Posted State Control, CG-S9-FIN-016)
-- Implements one canonical draft/in_review/approved/posted/corrected/
-- discarded lifecycle and a shared editability matrix read consistently
-- across the six Finance document types this repository has built so far:
-- invoice (FIN-197), vendor_bill (FIN-200), receipt (FIN-198), settlement
-- (FIN-201), subledger_batch (FIN-202), journal (FIN-203/204).
--
-- Design decision, disclosed: each of the six domains above already owns
-- its own concrete status enum and its own authority-checked transition
-- functions (submit/discard/approve/execute/post/reversal, whichever
-- subset applies) -- these already enforce "database constraints
-- preventing illegal normal-role transitions" (Prompt 205 section 13) at
-- the row level, proven by each domain's own db-test suite. This
-- checkpoint does not fork a second, competing state machine on top of
-- them. Instead it adds the one thing that did not exist anywhere yet: a
-- single, tested, cross-domain mapping from each domain's own concrete
-- status to one small canonical vocabulary
-- (draft/in_review/approved/posted/corrected/discarded), plus a shared
-- editability read -- allowed actions and a human-readable locked reason --
-- resolved from that mapping, so every Finance detail page can render
-- "canonical state, allowed actions... disabled actions explain why"
-- (Prompt 205 section 15) from one source of truth instead of six
-- independently invented ones.
--
-- app.finance_lifecycle_editability_matrix is a static reference table
-- (the same class as FIN-194's finance_currencies/FIN-195's
-- finance_tax_codes), seeded once in this migration with exactly one row
-- per real (entity_type, concrete_status) pair that exists in any of the
-- six domains' own CHECK constraints today -- 26 rows, verified by direct
-- inspection of each domain's own migration, not invented. Two concrete
-- statuses are seeded but not yet reachable by any real function call
-- today, and are labelled as such: app.finance_receipts.void (no void
-- function exists for a receipt yet) and
-- app.finance_subledger_batches.reversed (FIN-206's own disclosed forward
-- reference, exactly as FIN-202's own migration comment already recorded).
--
-- Canonical-state coarsening, disclosed and intentional: a settlement's
-- own 'approved' and 'executed' concrete statuses both map to the single
-- canonical 'approved' bucket -- execution records an external payment
-- reference with zero accounting effect (FIN-201's own design), so no
-- posting-relevant distinction exists between them; the concrete_status
-- field is always returned alongside canonical_state precisely so no
-- caller loses that detail, and allowed_actions is resolved from the real
-- concrete status, not the coarsened bucket, so 'approved' allows
-- ['execute'] while 'executed' allows ['post'] even though both report
-- canonical_state = 'approved'.
--
-- is_editable is false for every one of the 26 rows, structurally, not a
-- placeholder: no Finance document table in this repository yet exposes a
-- direct field-level update-in-place function for a draft row -- every one
-- of FIN-197/198/200/201/203's own build logs already disclosed that
-- amending a prepared draft requires discard-and-reprepare, never a
-- partial edit. This migration records that fact honestly (is_editable
-- uniformly false) rather than fabricating an edit affordance that does
-- not exist anywhere in this codebase.
--
-- posted_trigger_protected is true only for journal's own 'posted' row --
-- the one table-level trigger FIN-204 actually built. Every other posted
-- row above (invoice.issued, vendor_bill.posted, settlement.posted,
-- subledger_batch.posted) still relies on the grant-only protection FIN-197
-- disclosed as the repository-wide PLT-118 baseline (zero UPDATE/DELETE
-- grant for `authenticated`), not a table-level trigger; this column
-- exposes that real, current distinction rather than implying uniform
-- protection that does not yet exist.
--
-- app.get_finance_lifecycle_record_state is the one shared cross-domain
-- reader (Prompt 205 section 14: "shared lifecycle/transition policy used
-- by ... all source services") -- it dispatches to the correct table by
-- entity_type, re-uses each domain's own already-vetted
-- check_finance_*_authority('View', ...) function directly (never a new,
-- parallel authority mechanism), and joins the static matrix above to
-- return one consistent jsonb shape. No cross-domain listing/inbox view is
-- built here -- each domain's own already-shipped paginated list function
-- remains the per-domain listing surface; this checkpoint's own value-add
-- is the canonical-state-and-editability layer consumed per record, not a
-- new aggregate view, a disclosed bound matching this checkpoint's own
-- named objective (lifecycle/editability, not a new work-queue UI).
--
-- Reversal/correction itself is explicitly FIN-206's own scope (Prompt 205
-- section 32 names "corrected" only as a canonical *state*, never a new
-- correction mechanism) -- this migration only records the mapping for the
-- one already-real correction path that exists today (settlement's own
-- 'reversed', built at FIN-201).
--
-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries
-- its own explicit REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM
-- PUBLIC statement before its final grants, the standing per-migration
-- convention since PLT-118.

create table app.finance_lifecycle_editability_matrix (
  entity_type text not null,
  concrete_status text not null,
  canonical_state text not null,
  is_editable boolean not null default false,
  allowed_actions text[] not null default '{}',
  locked_reason text,
  posted_trigger_protected boolean not null default false,
  constraint finance_lifecycle_editability_matrix_pk primary key (entity_type, concrete_status),
  constraint finance_lifecycle_editability_matrix_entity_type_check check (
    entity_type in ('invoice', 'vendor_bill', 'receipt', 'settlement', 'subledger_batch', 'journal')
  ),
  constraint finance_lifecycle_editability_matrix_canonical_state_check check (
    canonical_state in ('draft', 'in_review', 'approved', 'posted', 'corrected', 'discarded')
  )
);

comment on table app.finance_lifecycle_editability_matrix is
  'FIN-205: one canonical lifecycle vocabulary (draft/in_review/approved/posted/corrected/discarded) and editability matrix, mapped from every real concrete status across the six Finance document types (invoice, vendor_bill, receipt, settlement, subledger_batch, journal). Static reference data, seeded once by this migration; the source of truth for app.get_finance_lifecycle_editability/app.get_finance_lifecycle_record_state.';

insert into app.finance_lifecycle_editability_matrix
  (entity_type, concrete_status, canonical_state, is_editable, allowed_actions, locked_reason, posted_trigger_protected)
values
  ('invoice', 'draft', 'draft', false, array['submit', 'discard'], null, false),
  ('invoice', 'submitted', 'in_review', false, array['approve', 'discard'], 'awaiting_approval', false),
  ('invoice', 'approved', 'approved', false, array['issue'], 'awaiting_post', false),
  ('invoice', 'issued', 'posted', false, array[]::text[], 'posted_immutable_normal_role', false),
  ('invoice', 'void', 'discarded', false, array[]::text[], 'discarded', false),

  ('vendor_bill', 'draft', 'draft', false, array['submit', 'discard'], null, false),
  ('vendor_bill', 'submitted', 'in_review', false, array['approve', 'discard'], 'awaiting_approval', false),
  ('vendor_bill', 'approved', 'approved', false, array['post'], 'awaiting_post', false),
  ('vendor_bill', 'posted', 'posted', false, array[]::text[], 'posted_immutable_normal_role', false),
  ('vendor_bill', 'void', 'discarded', false, array[]::text[], 'discarded', false),

  ('receipt', 'captured', 'posted', false, array['allocate', 'request_deallocation'], null, false),
  ('receipt', 'void', 'discarded', false, array[]::text[], 'discarded', false),

  ('settlement', 'draft', 'draft', false, array['submit', 'discard'], null, false),
  ('settlement', 'submitted', 'in_review', false, array['approve', 'discard'], 'awaiting_approval', false),
  ('settlement', 'approved', 'approved', false, array['execute'], 'awaiting_execution', false),
  ('settlement', 'executed', 'approved', false, array['post'], 'awaiting_post', false),
  ('settlement', 'posted', 'posted', false, array['request_reversal'], 'posted_correction_via_governed_reversal_only', false),
  ('settlement', 'void', 'discarded', false, array[]::text[], 'discarded', false),
  ('settlement', 'reversed', 'corrected', false, array[]::text[], 'corrected_terminal', false),

  ('subledger_batch', 'posted', 'posted', false, array[]::text[], 'system_generated_posted_immutable_normal_role', false),
  ('subledger_batch', 'reversed', 'corrected', false, array[]::text[], 'corrected_terminal', false),

  ('journal', 'draft', 'draft', false, array['submit', 'discard'], null, false),
  ('journal', 'submitted', 'in_review', false, array['approve', 'discard'], 'awaiting_approval', false),
  ('journal', 'approved', 'approved', false, array['post'], 'awaiting_post', false),
  ('journal', 'posted', 'posted', false, array[]::text[], 'posted_immutable_normal_role', true),
  ('journal', 'void', 'discarded', false, array[]::text[], 'discarded', false);

-- Pure reference lookup; raises rather than silently returning an
-- all-null/empty row for an unmapped (entity_type, concrete_status) pair
-- (the same "missing rule rejection never a silent... " discipline
-- FIN-195's own resolver already established for tax rules).
create function app.get_finance_lifecycle_editability(p_entity_type text, p_concrete_status text)
returns app.finance_lifecycle_editability_matrix
language plpgsql
stable
as $$
declare
  v_row app.finance_lifecycle_editability_matrix;
begin
  select * into v_row from app.finance_lifecycle_editability_matrix
    where entity_type = p_entity_type and concrete_status = p_concrete_status;
  if not found then
    raise exception 'finance_lifecycle_state_unmapped: entity type % has no mapped canonical state for status %', p_entity_type, p_concrete_status
      using errcode = 'invalid_parameter_value';
  end if;
  return v_row;
end;
$$;

comment on function app.get_finance_lifecycle_editability is
  'FIN-205: resolves the canonical state and editability policy for one (entity_type, concrete_status) pair from app.finance_lifecycle_editability_matrix. Raises finance_lifecycle_state_unmapped rather than returning a silent default for an unrecognized pair.';

-- The one shared cross-domain record-state reader (Prompt 205 section 14).
-- Dispatches to the correct table by entity_type, re-uses each domain's
-- own already-vetted check_finance_*_authority('View', ...) function
-- directly, and joins app.get_finance_lifecycle_editability to return one
-- consistent jsonb shape every Finance detail page can render identically.
create function app.get_finance_lifecycle_record_state(
  p_tenant_id uuid,
  p_entity_type text,
  p_record_id uuid,
  p_actor_auth_user_id uuid
)
returns jsonb
language plpgsql
stable
as $$
declare
  v_status text;
  v_record_version integer;
  v_editability app.finance_lifecycle_editability_matrix;
begin
  if p_entity_type = 'invoice' then
    if not app.check_finance_invoice_authority('View', p_tenant_id, p_actor_auth_user_id) then
      raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
        using errcode = 'insufficient_privilege';
    end if;
    select status, record_version into v_status, v_record_version from app.finance_invoices where id = p_record_id and tenant_id = p_tenant_id;
  elsif p_entity_type = 'vendor_bill' then
    if not app.check_finance_vendor_bill_authority('View', p_tenant_id, p_actor_auth_user_id) then
      raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
        using errcode = 'insufficient_privilege';
    end if;
    select status, record_version into v_status, v_record_version from app.finance_vendor_bills where id = p_record_id and tenant_id = p_tenant_id;
  elsif p_entity_type = 'receipt' then
    if not app.check_finance_receipt_authority('View', p_tenant_id, p_actor_auth_user_id) then
      raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
        using errcode = 'insufficient_privilege';
    end if;
    select status, record_version into v_status, v_record_version from app.finance_receipts where id = p_record_id and tenant_id = p_tenant_id;
  elsif p_entity_type = 'settlement' then
    if not app.check_finance_settlement_authority('View', p_tenant_id, p_actor_auth_user_id) then
      raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
        using errcode = 'insufficient_privilege';
    end if;
    select status, record_version into v_status, v_record_version from app.finance_settlements where id = p_record_id and tenant_id = p_tenant_id;
  elsif p_entity_type = 'subledger_batch' then
    if not app.check_finance_subledger_authority('View', p_tenant_id, p_actor_auth_user_id) then
      raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
        using errcode = 'insufficient_privilege';
    end if;
    -- app.finance_subledger_batches carries no record_version -- it has no
    -- direct-editable normal-role mutation surface at all (system-sourced,
    -- immediate-posted only), so no optimistic-concurrency token was ever
    -- needed for it (FIN-202's own design).
    select status, null into v_status, v_record_version from app.finance_subledger_batches where id = p_record_id and tenant_id = p_tenant_id;
  elsif p_entity_type = 'journal' then
    if not app.check_finance_journal_authority('View', p_tenant_id, p_actor_auth_user_id) then
      raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
        using errcode = 'insufficient_privilege';
    end if;
    select status, record_version into v_status, v_record_version from app.finance_journals where id = p_record_id and tenant_id = p_tenant_id;
  else
    raise exception 'finance_lifecycle_entity_type_unsupported: % is not a recognized Finance lifecycle entity type', p_entity_type
      using errcode = 'invalid_parameter_value';
  end if;

  if v_status is null then
    raise exception 'finance_lifecycle_record_not_found: no % record % found for tenant %', p_entity_type, p_record_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;

  v_editability := app.get_finance_lifecycle_editability(p_entity_type, v_status);

  return jsonb_build_object(
    'entityType', p_entity_type,
    'recordId', p_record_id,
    'tenantId', p_tenant_id,
    'concreteStatus', v_status,
    'canonicalState', v_editability.canonical_state,
    'recordVersion', v_record_version,
    'isEditable', v_editability.is_editable,
    'allowedActions', to_jsonb(v_editability.allowed_actions),
    'lockedReason', v_editability.locked_reason,
    'postedTriggerProtected', v_editability.posted_trigger_protected
  );
end;
$$;

comment on function app.get_finance_lifecycle_record_state is
  'FIN-205: the one shared cross-domain lifecycle-state reader for invoice/vendor_bill/receipt/settlement/subledger_batch/journal. Re-uses each domain''s own check_finance_*_authority(''View'', ...) directly; never a parallel authority mechanism. Raises finance_lifecycle_entity_type_unsupported for an unrecognized entity_type and finance_lifecycle_record_not_found for a missing/wrong-tenant record.';

alter table app.finance_lifecycle_editability_matrix enable row level security;

-- Pure global reference data, no tenant_id column -- mirrors FIN-194's own
-- app.finance_currencies_select_authenticated policy exactly (same class
-- of world-readable, non-sensitive catalog data).
create policy finance_lifecycle_editability_matrix_select_authenticated on app.finance_lifecycle_editability_matrix
  for select to authenticated
  using (true);

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable
-- revoke of PostgreSQL's PUBLIC-execute default, the standing per-migration
-- convention since PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant select on app.finance_lifecycle_editability_matrix to authenticated, service_role;
grant execute on function app.get_finance_lifecycle_editability(text, text) to authenticated, service_role;
grant execute on function app.get_finance_lifecycle_record_state(uuid, text, uuid, uuid) to authenticated, service_role;
