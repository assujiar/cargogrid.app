-- Track B Batch 7 -- ISS-2026-203 (found at CG-S15-HDN-007, OPEN, Low, owner HDN-386):
-- the 4 app.job_orders snapshot JSONB columns (customer_snapshot, cargo_service_snapshot,
-- revenue_snapshot, acceptance_snapshot) do not self-embed a `quotationId`/`quotationVersion`
-- key inside their own JSONB payload, even though full lineage IS relationally recoverable
-- (job_orders.quotation_id is a live FK pinned to the exact immutable app.quotations row/
-- version the snapshot was captured from -- app.quotations is version-immutable per row, a
-- revision inserts a brand-new row, never mutates the old one).
--
-- Investigated for a same-checkpoint bounded fix (the entry's own charter: "Not fixed here
-- -- embedding a version marker...touches every writer and reader...a larger consistency
-- change than a bounded repair", owner HDN-386 to judge whether the cross-domain touch is
-- worth it). Live read of every writer confirms the touch is NOT actually cross-domain:
-- app.job_orders has exactly ONE write site for all 6 of its own snapshot columns --
-- app.prepare_job_order's own single INSERT -- copying each sub-object verbatim from
-- app.job_order_handoffs.payload. No other function, migration, or application code path
-- ever writes these columns (grep-confirmed: `insert into app.job_orders` appears exactly
-- once in the whole migrations tree). Readers (app.job_orders_directory, app.override_
-- job_order_field, the public.* wrapper, every db-test) only ever read existing keys by
-- name -- adding two new keys is additive and cannot collide (customer/cargoService/
-- pricing/acceptance's own existing key sets, built by app.build_job_order_draft_payload,
-- contain no `quotationId`/`quotationVersion` member today).
--
-- CORRECTED BASE BODY (exhaustive redefinition search, not the original create_table
-- migration): app.prepare_job_order has TWO later redefinitions after its own
-- 20260727090000 origin -- `20260728190000_harden_operations_security_financial.sql`
-- (OPS-186 Finding 1: adds a record-scope check, `app.can_access_record` against the
-- handoff's own owner_user_id/org_unit_id, so a sibling-team/wrong-org-unit actor holding
-- OPS:Create is correctly denied) and `20260819000000_harden_release_blocker_triage_
-- remediation.sql` (HDN-387/ISS-2026-163: the unique_violation handler now requires
-- `found` before returning the re-selected row, re-raising instead of silently returning
-- an all-NULL app.job_orders composite when the violation is not the idempotency key's
-- own constraint). This migration is built on that TRUE latest body -- both fixes are
-- preserved byte-for-byte -- not the stale original body a first draft of this fix was
-- mistakenly based on (caught by `scripts/db-tests/operations-security-financial-
-- hardening.sql`'s own OPS-186 Finding 1 regression failing before this migration was
-- ever applied live).
--
-- Fix: app.prepare_job_order now looks up the source quotation's own canonical
-- version_number (app.quotations.version_number, the real "business version" column,
-- COM-152) and merges `{"quotationId": ..., "quotationVersion": ...}` into each of the 4
-- named snapshots at the one INSERT that creates them -- contract_snapshot/credit_snapshot
-- are deliberately left untouched (not named by this entry; contract/credit already carry
-- their own distinct root-contract/check-scoped identifiers, a different lineage question
-- outside this entry's own scope). Existing rows are NOT backfilled -- this is a forward-
-- looking convenience addition for a Low-severity, already-recoverable gap (the relational
-- path via job_orders.quotation_id has always been correct and remains the authoritative
-- lineage trace); a reader of an old snapshot still recovers the source version via the
-- parent row's own quotation_id, exactly as before this migration.

create or replace function app.prepare_job_order(
  p_source_handoff_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.job_orders
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_handoff app.job_order_handoffs;
  v_decision app.rbac_decision;
  v_existing app.job_orders;
  v_job_order app.job_orders;
  v_number text;
  v_quotation_version integer;
  v_lineage jsonb;
begin
  select * into v_handoff from app.job_order_handoffs where id = p_source_handoff_id;
  if not found then
    raise exception 'handoff_not_found: %', p_source_handoff_id using errcode = 'no_data_found';
  end if;

  select * into v_existing from app.job_orders where tenant_id = v_handoff.tenant_id and source_handoff_id = p_source_handoff_id;
  if found then
    return v_existing;
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_handoff.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_handoff.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_handoff.tenant_id, v_handoff.owner_user_id, app.lead_record_scope_org_unit_ids(v_handoff.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access job order handoff %', p_actor_auth_user_id, p_source_handoff_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_handoff.payload is null then
    raise exception 'handoff_payload_unavailable: handoff % carries no payload to convert', p_source_handoff_id
      using errcode = 'check_violation';
  end if;

  v_number := app.next_job_order_number(v_handoff.tenant_id);

  -- ISS-2026-203 fix: the same immutable quotation row/version every snapshot below was
  -- built from (v_handoff.quotation_id is already the live FK pinned to it) -- reads the
  -- real, canonical app.quotations.version_number column, never re-derived from the
  -- handoff payload's own already-copied source.versionNumber value.
  select version_number into v_quotation_version from app.quotations where id = v_handoff.quotation_id;
  v_lineage := jsonb_build_object('quotationId', v_handoff.quotation_id, 'quotationVersion', v_quotation_version);

  begin
    insert into app.job_orders (
      tenant_id, job_number, source_handoff_id, quotation_id, account_id,
      customer_snapshot, cargo_service_snapshot, revenue_snapshot, contract_snapshot, credit_snapshot, acceptance_snapshot,
      owner_user_id, created_by
    ) values (
      v_handoff.tenant_id, v_number, v_handoff.id, v_handoff.quotation_id, v_handoff.account_id,
      (v_handoff.payload -> 'customer') || v_lineage, (v_handoff.payload -> 'cargoService') || v_lineage, (v_handoff.payload -> 'pricing') || v_lineage,
      v_handoff.payload -> 'contract', v_handoff.payload -> 'credit', (v_handoff.payload -> 'acceptance') || v_lineage,
      p_actor_auth_user_id, p_actor_label
    )
    returning * into v_job_order;
  exception
    when unique_violation then
      -- HDN-387 (ISS-2026-163 fix, preserved verbatim from the true latest body): re-select
      -- on the correct idempotency key and require `found` before returning, else re-raise
      -- -- never silently return an all-NULL app.job_orders composite for an unrelated
      -- unique_violation (e.g. the table's own separate job_orders_tenant_number_unique
      -- constraint).
      select * into v_job_order from app.job_orders where tenant_id = v_handoff.tenant_id and source_handoff_id = p_source_handoff_id;
      if found then
        return v_job_order;
      end if;
      raise;
  end;

  perform app.capture_audit_event(
    v_handoff.tenant_id, p_actor_auth_user_id, p_actor_label, 'prepare_job_order',
    'app.job_orders', v_job_order.id, 'success', null, null,
    jsonb_build_object('source_handoff_id', p_source_handoff_id, 'job_number', v_number)
  );

  return v_job_order;
end;
$$;

comment on function app.prepare_job_order is
  'OPS-168/OPS-186-hardened, HDN-387 (ISS-2026-163 fix): idempotent on (tenant_id, source_handoff_id) -- a repeated call, including under a concurrent-insert race, returns the exact same Job Order row, never a duplicate, and correctly re-raises (rather than silently returning an all-NULL row) when the unique_violation is not the idempotency key''s own constraint. Every snapshot column is copied verbatim from the handoff''s own already-canonical payload. Record-scope-checked against the source handoff (OPS-186). ISS-2026-203 fix (Track B Batch 7, 20260828150000): customer_snapshot/cargo_service_snapshot/revenue_snapshot/acceptance_snapshot additionally self-embed quotationId/quotationVersion (the same app.quotations row/version job_orders.quotation_id already pins to) so a reader given only the raw snapshot JSONB, without the parent row, can self-trace its own source version -- contract_snapshot/credit_snapshot are unchanged.';

-- app.prepare_job_order's own public.* PostgREST wrapper (20260826000000_create_public_
-- api_data_wrappers.sql) is a thin pass-through on an unchanged signature/return type --
-- no wrapper or grant change required.

revoke execute on all functions in schema app from public;

grant execute on function app.prepare_job_order(uuid, uuid, text) to authenticated, service_role;
