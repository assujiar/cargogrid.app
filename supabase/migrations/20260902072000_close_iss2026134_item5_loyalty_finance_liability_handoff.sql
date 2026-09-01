-- ISS-2026-134 item 5 / ISS-2026-129 item 1 (CPL-323/CPL-319 disclosed
-- boundary) -- the Finance liability-handoff mechanism both entries name as
-- deferred, built now mirroring the ONE already-established cross-domain
-- handoff precedent in this repository: HRT-282's `app.prepare_finance_
-- payroll_disbursement_handoff_from_payroll_run` family
-- (20260731010000_bind_hris_payroll_to_finance_handoff.sql), itself
-- explicitly mirroring FIN-200's `app.prepare_finance_vendor_bill_from_
-- actual_cost` naming shape. Read live before writing anything (pg_
-- get_functiondef, list_tables) -- both cited live and unmodified since
-- their own migrations.
--
-- ADR-0024 Part D discipline, restated concretely for this migration: the
-- SOURCE domain (Loyalty) reads its OWN already-committed state (a
-- `certified` app.loyalty_liability_reconciliation_runs row -- never
-- `open`/`exceptions_pending`, mirroring HRT-282's own `finalized`-only
-- gate on app.payroll_runs) and writes ONLY into a NEW table this migration
-- creates, `app.loyalty_finance_liability_handoff_batches` -- zero write to
-- any `app.finance_*` table, `app.journal_entries`, `app.finance_
-- settlements`, or `app.finance_payments` anywhere in this file, grep-
-- verifiable exactly as HRT-282's own header states for its own tables.
-- Finance discovers and acknowledges through its OWN authority (FIN:View /
-- FIN:Edit) -- the one place a Finance-side actor's authority is checked,
-- never Loyalty's.
--
-- The five liability totals are copied VERBATIM from the certified run --
-- never re-derived, re-summed, or re-typed (identical discipline to HRT-282's
-- own "sums this run's ALREADY-COMPUTED, immutable... totals -- never
-- re-derives or re-calculates a figure"). Kept as five separate columns,
-- never blended into one "total_liability" -- the reconciliation run's own
-- design decision 6 (points_liability_total is a RAW POINTS total, never
-- currency-converted) makes a single summed figure actively misleading;
-- Finance receives the same per-unit-type dimensioning the run itself
-- already established, not a new one invented here.
--
-- Per ERR-2026-004: explicit REVOKE EXECUTE before this migration's own
-- final grants.

create table app.loyalty_finance_liability_handoff_batches (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  reconciliation_run_id uuid not null references app.loyalty_liability_reconciliation_runs (id),
  as_of timestamptz not null,
  currency text not null,
  points_liability_total numeric(14, 2) not null,
  cashback_liability_total numeric(14, 2) not null,
  discount_liability_total numeric(14, 2) not null,
  voucher_liability_total numeric(14, 2) not null,
  reward_fulfillment_liability_total numeric(14, 2) not null,
  status text not null default 'pending_acknowledgement',
  generated_by text,
  generated_at timestamptz not null default now(),
  acknowledged_by text,
  acknowledged_at timestamptz,
  record_version integer not null default 1,
  updated_at timestamptz not null default now(),
  constraint lflhb_status_check check (status in ('pending_acknowledgement', 'acknowledged')),
  constraint lflhb_currency_check check (currency ~ '^[A-Z]{3}$'),
  constraint lflhb_totals_nonneg_check check (
    points_liability_total >= 0 and cashback_liability_total >= 0 and discount_liability_total >= 0
    and voucher_liability_total >= 0 and reward_fulfillment_liability_total >= 0
  ),
  constraint lflhb_ack_shape_check check (
    (status = 'pending_acknowledgement' and acknowledged_by is null and acknowledged_at is null)
    or (status = 'acknowledged' and acknowledged_by is not null and acknowledged_at is not null)
  ),
  constraint lflhb_run_unique unique (reconciliation_run_id)
);

comment on table app.loyalty_finance_liability_handoff_batches is
  'ISS-2026-134 item 5: the ONE handoff artifact per certified app.loyalty_liability_reconciliation_runs row -- still Loyalty-owned (mirrors app.payroll_finance_handoff_batches, HRT-282), never a app.finance_* table. Generated ONLY from a run whose status=certified. acknowledged_by/acknowledged_at are set ONLY by an actor holding FIN:Edit.';

create index lflhb_tenant_status_idx on app.loyalty_finance_liability_handoff_batches (tenant_id, status);

create function app.touch_loyalty_finance_liability_handoff_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := clock_timestamp();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger loyalty_finance_liability_handoff_batches_touch before update on app.loyalty_finance_liability_handoff_batches
  for each row execute function app.touch_loyalty_finance_liability_handoff_row();

-- ===========================================================================
-- app.prepare_finance_liability_handoff_from_loyalty_liability -- the
-- prepare_finance_*_from_* generator. Loyalty's OWN authority (LYL:
-- Configure, the same bar app.certify_loyalty_liability_reconciliation_run
-- itself requires) generates the handoff -- still Loyalty acting on its own
-- certified data, never a Finance action.
-- ===========================================================================

create function app.prepare_finance_liability_handoff_from_loyalty_liability(
  p_tenant_id uuid,
  p_run_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_finance_liability_handoff_batches
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_run app.loyalty_liability_reconciliation_runs;
  v_existing app.loyalty_finance_liability_handoff_batches;
  v_batch app.loyalty_finance_liability_handoff_batches;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_run from app.loyalty_liability_reconciliation_runs where id = p_run_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'loyalty_liability_reconciliation_run_not_found: %', p_run_id using errcode = 'no_data_found';
  end if;
  if v_run.status <> 'certified' then
    raise exception 'loyalty_liability_reconciliation_run_not_certified: run % is % -- only a certified run may generate a Finance handoff', p_run_id, v_run.status
      using errcode = 'check_violation';
  end if;

  -- Idempotent on reconciliation_run_id -- a replay returns the existing
  -- batch unchanged, never a second batch for the same run.
  select * into v_existing from app.loyalty_finance_liability_handoff_batches where reconciliation_run_id = p_run_id;
  if found then
    return v_existing;
  end if;

  insert into app.loyalty_finance_liability_handoff_batches (
    tenant_id, reconciliation_run_id, as_of, currency,
    points_liability_total, cashback_liability_total, discount_liability_total, voucher_liability_total, reward_fulfillment_liability_total,
    generated_by
  ) values (
    p_tenant_id, v_run.id, v_run.as_of, v_run.currency,
    v_run.points_liability_total, v_run.cashback_liability_total, v_run.discount_liability_total, v_run.voucher_liability_total, v_run.reward_fulfillment_liability_total,
    p_actor_label
  )
  returning * into v_batch;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'prepare_finance_liability_handoff_from_loyalty_liability',
    'app.loyalty_finance_liability_handoff_batches', v_batch.id, 'success', null, null,
    jsonb_build_object('reconciliation_run_id', p_run_id, 'currency', v_run.currency, 'as_of', v_run.as_of)
  );

  return v_batch;
end;
$$;

comment on function app.prepare_finance_liability_handoff_from_loyalty_liability is
  'ISS-2026-134 item 5: mirrors app.prepare_finance_payroll_disbursement_handoff_from_payroll_run (HRT-282) exactly -- idempotent on reconciliation_run_id, only a certified run qualifies, every total copied verbatim from the run''s own already-computed columns, zero write to any app.finance_* table.';

-- ===========================================================================
-- Finance-side discovery and acknowledgement.
-- ===========================================================================

create function app.search_loyalty_finance_liability_handoffs_pending_acknowledgement(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns setof app.loyalty_finance_liability_handoff_batches
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'FIN', 'View')).allowed then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.loyalty_finance_liability_handoff_batches
    where tenant_id = p_tenant_id and status = 'pending_acknowledgement'
    order by generated_at asc
    limit 200;
end;
$$;

comment on function app.search_loyalty_finance_liability_handoffs_pending_acknowledgement is
  'ISS-2026-134 item 5: mirrors app.search_payroll_finance_handoffs_pending_acknowledgement (HRT-282) exactly -- how Finance discovers what Loyalty has prepared, gated on FIN:View, without Loyalty ever reaching into a Finance table.';

create function app.acknowledge_loyalty_finance_liability_handoff(p_batch_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.loyalty_finance_liability_handoff_batches
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_batch app.loyalty_finance_liability_handoff_batches;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_batch from app.loyalty_finance_liability_handoff_batches where id = p_batch_id for update;
  if not found then
    raise exception 'loyalty_finance_liability_handoff_batch_not_found: %', p_batch_id using errcode = 'no_data_found';
  end if;

  -- The ONE place in this handoff pair the calling actor must hold FINANCE
  -- authority, not Loyalty authority -- proves the acknowledging actor is
  -- genuinely Finance-side.
  if not (app.evaluate_permission(p_actor_auth_user_id, v_batch.tenant_id, 'FIN', 'Edit')).allowed then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_batch.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_batch.status = 'acknowledged' then
    return v_batch;
  end if;
  -- Double-defended NULL-bypass (this repository's own established
  -- discipline, ISS-2026-318): a null p_expected_version is rejected
  -- outright, never silently treated as "no concurrency check requested."
  if p_expected_version is null or v_batch.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_batch.record_version
      using errcode = 'serialization_failure';
  end if;

  update app.loyalty_finance_liability_handoff_batches set status = 'acknowledged', acknowledged_by = p_actor_label, acknowledged_at = now()
  where id = p_batch_id and record_version = p_expected_version
  returning * into v_batch;
  if not found then
    raise exception 'stale_version: concurrent update detected for handoff batch %', p_batch_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_batch.tenant_id, p_actor_auth_user_id, p_actor_label, 'acknowledge_loyalty_finance_liability_handoff',
    'app.loyalty_finance_liability_handoff_batches', v_batch.id, 'success', null, null, jsonb_build_object('status', v_batch.status)
  );

  return v_batch;
end;
$$;

comment on function app.acknowledge_loyalty_finance_liability_handoff is
  'ISS-2026-134 item 5: FIN:Edit-gated, mirrors app.acknowledge_payroll_finance_handoff_batch (HRT-282) exactly. Idempotent: a repeat acknowledgement of an already-acknowledged batch is a safe no-op. NULL p_expected_version is rejected outright (ISS-2026-318 discipline).';

create function app.get_loyalty_finance_liability_handoff(p_batch_id uuid, p_actor_auth_user_id uuid)
returns app.loyalty_finance_liability_handoff_batches
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_batch app.loyalty_finance_liability_handoff_batches;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_batch from app.loyalty_finance_liability_handoff_batches where id = p_batch_id;
  if not found or not (
    (app.evaluate_permission(p_actor_auth_user_id, v_batch.tenant_id, 'LYL', 'View')).allowed
    or (app.evaluate_permission(p_actor_auth_user_id, v_batch.tenant_id, 'FIN', 'View')).allowed
  ) then
    raise exception 'loyalty_finance_liability_handoff_batch_not_found: %', p_batch_id using errcode = 'no_data_found';
  end if;
  return v_batch;
end;
$$;

comment on function app.get_loyalty_finance_liability_handoff is
  'ISS-2026-134 item 5: readable by either side of the handoff boundary -- Loyalty (LYL:View) or Finance (FIN:View) -- mirrors app.get_payroll_finance_handoff_batch (HRT-282).';

-- ===========================================================================
-- RLS.
-- ===========================================================================

alter table app.loyalty_finance_liability_handoff_batches enable row level security;

create policy loyalty_finance_liability_handoff_batches_select_scoped on app.loyalty_finance_liability_handoff_batches
  for select to authenticated
  using (
    app.is_supreme_admin()
    or (app.evaluate_permission((select auth.uid()), tenant_id, 'LYL', 'View')).allowed
    or (app.evaluate_permission((select auth.uid()), tenant_id, 'FIN', 'View')).allowed
  );

comment on policy loyalty_finance_liability_handoff_batches_select_scoped on app.loyalty_finance_liability_handoff_batches is
  'ISS-2026-134 item 5: readable by either side of the handoff boundary -- Loyalty (LYL:View) or Finance (FIN:View) -- never by plain tenant membership, mirroring payroll_finance_handoff_batches_select_scoped (HRT-282).';

-- ===========================================================================
-- Grants. Per ERR-2026-004: explicit REVOKE before this migration's own
-- final grants. Zero GRANT of any kind, anywhere in this migration, on any
-- app.finance_* table, app.journal_entries, app.finance_settlements, or
-- app.finance_payments.
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant select on app.loyalty_finance_liability_handoff_batches to authenticated, service_role;
grant insert, update, delete on app.loyalty_finance_liability_handoff_batches to service_role;

grant execute on function app.touch_loyalty_finance_liability_handoff_row() to service_role;
grant execute on function app.prepare_finance_liability_handoff_from_loyalty_liability(uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.search_loyalty_finance_liability_handoffs_pending_acknowledgement(uuid, uuid) to authenticated, service_role;
grant execute on function app.acknowledge_loyalty_finance_liability_handoff(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.get_loyalty_finance_liability_handoff(uuid, uuid) to authenticated, service_role;
