-- RGL-BLK-009 (Go/No-Go Report, Prompt 404): closes HDN-BLK-016/ISS-2026-199, escalated to
-- Critical at RGL-404 ("financial mis-posting" per 00_RELEASE_GO_LIVE_EXECUTION_INDEX.md
-- §8.1) -- `app.request_finance_settlement_reversal` reversed the AP subledger's own
-- settled_amount/status but never posted a reversing GL journal, permanently desyncing the
-- GL from the AP subledger on every settlement reversal (live-forced at HDN-374).
--
-- Fix, mirroring this codebase's own already-established correction pattern
-- (app.post_finance_correction, 20260729200000): locate the settlement's own posted GL
-- journal via its app.finance_subledger_batches row (source_type='settlement'), read that
-- journal's own lines, flip debit<->credit (identical technique post_finance_correction
-- already uses for a general journal reversal), and post the flipped lines as a new
-- 'correction'-sourced journal via the same app.create_and_post_finance_system_journal this
-- codebase already uses for every other governed journal-posting path. A
-- app.finance_journal_corrections row is also inserted (status 'posted' immediately, since
-- this whole action is a single FIN:Approve-gated atomic call -- unlike a general journal
-- correction's own separate prepare/submit/approve/post maker-checker workflow, which would
-- require the caller to ALSO hold a distinct FIN:Edit/FIN:Approve-on-corrections grant this
-- settlement-reversal actor was never expected to need) so the correction ledger and
-- app.get_finance_correction_chain remain a complete, queryable record either way.
--
-- Design decision this migration makes explicitly, per HDN-BLK-016's own "Required of
-- HDN-386" field ("automatic vs. a separate governed step"): AUTOMATIC. The AP-side reversal
-- this function already performs is itself a single atomic call with no separate approval
-- step; posting the GL side under a second, differently-scoped authority chain would only
-- reintroduce the exact "AP reversed but GL not yet" partial-state window this fix exists to
-- close, and would surprise a FIN:Approve holder who has never needed FIN:Edit-on-corrections
-- to reverse a settlement before.
--
-- SEPARATELY, and found only while implementing this fix (not previously registered
-- anywhere): live catalog inspection of the hosted project shows
-- app.request_finance_settlement_reversal is currently SECURITY INVOKER
-- (prosecdef=false), not SECURITY DEFINER. 20260810700000 (RGL-397's own migration
-- catch-up) converted it to SECURITY DEFINER along with 94 sibling Finance functions: but
-- 20260811200000 (a same-day, later-timestamped migration fixing this exact function's own
-- period-lock bypass, HDN-374 Tier C finding 3) re-created it via `CREATE OR REPLACE
-- FUNCTION` WITHOUT restating `SECURITY DEFINER` -- Postgres does not preserve an omitted
-- security-mode clause across a CREATE OR REPLACE, so this silently reverted the DEFINER fix
-- for this one function only, immediately after RGL-397 shipped it. Live-verified via
-- `select prosecdef from pg_proc where proname='request_finance_settlement_reversal'` ->
-- false. Consequence: since `authenticated` holds no direct grant on the underlying
-- app.finance_settlements/app.finance_ap_open_items tables, this function has been
-- completely unreachable by any real authenticated tenant user since 20260811200000 shipped
-- -- the identical "Finance write RPC unreachable" bug class RGL-397/RGL-BLK-006 already
-- found and fixed for 95 other functions, recurring here via a different mechanism (a later
-- migration's own incomplete CREATE OR REPLACE, not a migration that was simply never
-- applied). Fixed in the same CREATE OR REPLACE below, since this migration already needs to
-- re-create this function's own body for the GL-journal fix.

create or replace function app.request_finance_settlement_reversal(
  p_settlement_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_settlements
language plpgsql
security definer
set search_path to 'app', 'pg_temp'
as $function$
declare
  v_settlement app.finance_settlements;
  v_allocation app.finance_settlement_allocations;
  v_period record;
  v_batch app.finance_subledger_batches;
  v_original_journal app.finance_journals;
  v_reversal_lines jsonb := '[]'::jsonb;
  v_line record;
  v_flipped text;
  v_correction app.finance_journal_corrections;
  v_reversal_journal app.finance_journals;
begin
  select * into v_settlement from app.finance_settlements where id = p_settlement_id for update;
  if not found then
    raise exception 'finance_settlement_not_found: %', p_settlement_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_settlement_authority('Approve', v_settlement.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_settlement.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_settlement_reversal_reason_required: a non-empty reason is required to reverse a posted settlement'
      using errcode = 'check_violation';
  end if;
  if v_settlement.status <> 'posted' then
    raise exception 'finance_settlement_not_posted: settlement % is % not posted', p_settlement_id, v_settlement.status
      using errcode = 'check_violation';
  end if;

  -- HDN-374 Tier C finding 3: mirrors app.post_finance_settlement's own period-lock check --
  -- a reversal is a financial mutation against the settlement's own original posting period
  -- and must not bypass that period being locked, the same as any other posting.
  select * into v_period from app.resolve_finance_period_for_date(v_settlement.tenant_id, v_settlement.company_id, v_settlement.settlement_date);
  if not found then
    raise exception 'finance_settlement_reversal_period_not_found: no fiscal period covers %', v_settlement.settlement_date
      using errcode = 'no_data_found';
  end if;
  if not v_period.posting_eligible then
    raise exception 'finance_settlement_reversal_period_not_open: fiscal period % for % is not open', v_period.period_code, v_settlement.settlement_date
      using errcode = 'check_violation';
  end if;

  -- RGL-BLK-009: locate the settlement's own posted GL journal via its subledger batch
  -- (app.post_finance_settlement always creates exactly one, source_type='settlement',
  -- before this function's own precondition above -- status must already be 'posted' --
  -- can ever hold true).
  select * into v_batch from app.finance_subledger_batches where tenant_id = v_settlement.tenant_id and source_type = 'settlement' and source_id = v_settlement.id;
  if not found or v_batch.gl_journal_id is null then
    raise exception 'finance_settlement_reversal_batch_not_found: settlement % has no posted subledger batch/GL journal to reverse -- data integrity anomaly', p_settlement_id
      using errcode = 'no_data_found';
  end if;
  select * into v_original_journal from app.finance_journals where id = v_batch.gl_journal_id;
  if not found or v_original_journal.status <> 'posted' then
    raise exception 'finance_settlement_reversal_journal_not_posted: journal % for settlement % is not posted', v_batch.gl_journal_id, p_settlement_id
      using errcode = 'check_violation';
  end if;

  -- Same technique app.post_finance_correction already uses for a general journal
  -- reversal: read the original journal's own lines and flip debit<->credit, never
  -- re-resolving a posting-map account -- the reversal must land on the exact same
  -- accounts the original entry did.
  for v_line in select direction, account_id, amount, dimension from app.finance_journal_lines where journal_id = v_original_journal.id order by line_number asc loop
    v_flipped := case when v_line.direction = 'debit' then 'credit' else 'debit' end;
    v_reversal_lines := v_reversal_lines || jsonb_build_array(jsonb_build_object('accountId', v_line.account_id, 'direction', v_flipped, 'amount', v_line.amount, 'dimension', v_line.dimension));
  end loop;

  -- RGL-BLK-009 fix, corrected during local db-test validation: the reversal journal is
  -- posted against v_settlement.settlement_date -- the SAME date already validated open
  -- for posting by this function's own period-lock check above -- never `current_date`.
  -- `current_date` would make this function's own success depend on whichever fiscal
  -- period happens to be open on the wall-clock day the reversal call is made, an
  -- unrelated and untested precondition; reusing the already-validated settlement date is
  -- both deterministic and the more defensible accounting choice (the reversal lands in
  -- the same period as the entry it reverses).
  insert into app.finance_journal_corrections (
    tenant_id, company_id, original_journal_id, correction_type, correction_date, reason, evidence_ref, adjustment_lines,
    status, idempotency_key, submitted_by, submitted_at, approved_by, approved_at, created_by
  )
  values (
    v_settlement.tenant_id, v_settlement.company_id, v_original_journal.id, 'reversal', v_settlement.settlement_date, p_reason, null, null,
    'approved', 'settlement_reversal:' || v_settlement.id::text, p_actor_label, now(), p_actor_label, now(), p_actor_label
  )
  returning * into v_correction;

  select * into v_reversal_journal from app.create_and_post_finance_system_journal(
    v_settlement.tenant_id, v_settlement.company_id, 'correction', v_correction.id, v_settlement.settlement_date,
    v_original_journal.currency, v_reversal_lines, p_actor_auth_user_id, p_actor_label, 'ap'
  );

  update app.finance_journal_corrections
    set status = 'posted', correction_journal_id = v_reversal_journal.id, posted_by = p_actor_label, posted_at = now()
    where id = v_correction.id
    returning * into v_correction;

  update app.finance_subledger_batches set status = 'reversed' where id = v_batch.id and status = 'posted';

  perform app.capture_audit_event(
    v_settlement.tenant_id, p_actor_auth_user_id, p_actor_label, 'post_finance_correction',
    'app.finance_journal_corrections', v_correction.id, 'success', p_reason, null, to_jsonb(v_correction)
  );

  for v_allocation in select * from app.finance_settlement_allocations where settlement_id = p_settlement_id and status = 'applied' order by created_at asc loop
    perform app.reverse_finance_ap_settlement(
      v_allocation.ap_open_item_id, v_allocation.amount, p_reason, 'settlement', v_settlement.id,
      'reversal:' || v_settlement.id::text || ':' || v_allocation.ap_open_item_id::text, p_actor_auth_user_id, p_actor_label
    );
    update app.finance_settlement_allocations set status = 'reversed', reason = p_reason, reversed_by = p_actor_label, reversed_at = now() where id = v_allocation.id;
  end loop;

  update app.finance_settlements set status = 'reversed', void_reason = p_reason, voided_by = p_actor_label, voided_at = now() where id = p_settlement_id returning * into v_settlement;

  perform app.capture_audit_event(
    v_settlement.tenant_id, p_actor_auth_user_id, p_actor_label, 'request_finance_settlement_reversal',
    'app.finance_settlements', v_settlement.id, 'success', p_reason, null, to_jsonb(v_settlement)
  );

  return v_settlement;
end;
$function$
;

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable
-- revoke of PostgreSQL's PUBLIC-execute default, the standing per-migration
-- convention since PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant execute on function app.request_finance_settlement_reversal(uuid, text, uuid, text) to authenticated, service_role;

-- The RGL-BLK-002 Option 2 wrapper layer's own zero-tolerance security-mode-matching
-- regression guard (scripts/db-tests/public-api-wrapper-regression.sql) correctly flags
-- public.request_finance_settlement_reversal as now mismatched against its app.*
-- counterpart -- the wrapper was created security invoker, matching app.*'s own broken
-- (pre-this-migration) invoker state; restoring app.* to definer above leaves the wrapper
-- behind unless it is updated too. Fixed here, same technique as the 140-wrapper Tier C fix
-- in 20260826010000 (identical body, only the security clause added).
create or replace function public.request_finance_settlement_reversal(p_settlement_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.finance_settlements
language sql
security definer
set search_path to 'pg_catalog', 'pg_temp'
as $function$
  select app.request_finance_settlement_reversal(p_settlement_id, p_reason, p_actor_auth_user_id, p_actor_label);
$function$;
