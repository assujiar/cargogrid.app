-- ISS-2026-273 (docs/runtime/KNOWN_ISSUES.md, High) -- two coupled gaps, closed together
-- because closing either alone would leave the other making the first one untrue:
--
--   (a) **No bulk opening-balance import path exists at all.** Prompt 385 §24 states
--       "Financial opening balances require exact reconciliation."
--       `app.post_finance_ar_open_item`/`app.post_finance_ap_open_item` are real,
--       genuinely idempotent single-record RPCs, but nothing batches them: no staging, no
--       validation, no preview, no commit adapter. A tenant migrating thousands of open
--       invoices at cutover had to post them one call at a time.
--
--   (b) **Opening balances never reach the general ledger.** `FIN-202` discloses this in
--       its own header ("`opening_balance` source type ... do not yet emit a subledger
--       batch"), and `app.get_finance_subledger_reconciliation_summary` works around it by
--       filtering its open-item totals to `source_document_type = 'invoice'`/`'vendor_bill'`
--       -- excluding opening balances from the comparison rather than reconciling them.
--       Live-reproduced at `HDN-385`: three opening-balance postings reconciled exactly at
--       the open-items level while `app.finance_subledger_batches` stayed at zero rows.
--
-- FIN-202's disclosure was correct when written, and says so precisely: the gap was
-- acceptable "since Phase 4 remains a greenfield internal delivery gate with no real
-- historical balance to reconcile yet", and its own §19 constraint is described as live
-- "on any *future* opening-balance import". This migration builds that future import. So
-- closing (b) here is the follow-through FIN-202 itself anticipated, not a reversal of it.
--
-- ---------------------------------------------------------------------------------------
-- The double entry, and why the counter-account is configuration rather than a constant
-- ---------------------------------------------------------------------------------------
--
-- An opening balance has no originating business event inside CargoGrid -- it is a
-- statement that money was already owed on the day the tenant started. The standard
-- double entry every migration uses is against an opening-balance equity account:
--
--   AR opening balance   debit  ar_control            credit opening_balance_equity
--   AP opening balance   debit  opening_balance_equity credit ap_control
--
-- `opening_balance_equity` is a NEW `app.finance_posting_map` key, not a hardcoded account.
-- Which real GL account it points at is a decision for the tenant's own accountant, and
-- the posting map is exactly the mechanism this repository already uses for `ar_control`,
-- `ap_control` and every other routed account. A tenant that has not configured the key
-- gets `finance_subledger_missing_mapping` and nothing posts -- fail-closed, and the right
-- failure: guessing an equity account on a customer's behalf is how migrations end up
-- silently wrong.
--
-- ---------------------------------------------------------------------------------------
-- The reconciliation summary is corrected, not just widened
-- ---------------------------------------------------------------------------------------
--
-- Once opening balances emit batches, the existing
-- `source_document_type = 'invoice'` filter becomes actively wrong: the subledger side of
-- the comparison sums every line hitting `ar_control` (which now includes opening
-- balances) while the open-item side would still exclude them, so a correctly-migrated
-- tenant would read as UNRECONCILED.
--
-- Widening the filter to include all opening balances would be equally wrong in the other
-- direction: an opening balance posted before this migration, or posted while the
-- posting-map key is unconfigured, has no batch, and counting it would make a genuine
-- difference disappear into a total.
--
-- So the summary now does three things instead of one: it counts opening balances that
-- HAVE a posted batch inside the reconciled total; it reports those that do NOT as an
-- explicit separate figure; and it carries a boolean saying whether every opening balance
-- has reached the GL. "Exact reconciliation" (§24) means being able to see the difference,
-- not excluding it from the comparison.
--
-- ---------------------------------------------------------------------------------------
-- Import design
-- ---------------------------------------------------------------------------------------
--
-- One `finance_opening_balance_import` schema handles both AR and AP: the file carries an
-- `open_item_type` column (`ar`/`ap`) per row, because a cutover extract is normally one
-- trial-balance file, not two. Each committed row does BOTH halves in the same
-- transaction -- the open item and its GL batch -- so a partially-migrated state where the
-- subledger and the ledger disagree cannot exist even if the commit fails midway (the
-- whole transaction rolls back).
--
-- **`source_document_id` is the staging row id.** No new provenance column is added, and
-- that is deliberate: `finance_ar_open_items_source_unique` /
-- `finance_ap_open_items_source_unique` already make `(tenant, source_type,
-- source_document_id)` the idempotency key, and both primitives already return the
-- existing row on a retry. Adding a second `source_import_staging_row_id` column (as the
-- vendor/customer/item adapters needed, because their targets had no such key) would
-- create two sources of truth for the same fact that could disagree.
--
-- Authority mirrors the single-record path exactly: posting an `opening_balance` open item
-- already requires `FIN:Approve`, so the adapter requires `app.is_support_grant_authority`
-- AND `FIN:Import`, and the primitives then enforce `FIN:Approve` per row. The bulk path
-- is strictly additive to the single-record path's authority, never a way around it.
--
-- `unique_violation` is not caught anywhere in the commit loop, deliberately: both
-- primitives resolve their own idempotency internally by RETURNING the existing row rather
-- than raising, so any `unique_violation` that escapes is a real failure and must abort the
-- whole commit. `p_client_ip` carries `ISS-2026-278`'s IP-allowlist shape at birth.
--
-- Per `ERR-2026-004`: explicit `revoke execute on all functions in schema app from public;`
-- before the final grants. No already-applied migration is edited.

-- ===========================================================================
-- 1. RBAC seed addition.
-- ===========================================================================

insert into app.permissions (action, resource_module_code, category, protected) values
  ('Import', 'FIN', 'standard', false);

-- ===========================================================================
-- 2. Widen the subledger batch source_type to admit opening balances.
--    A CHECK constraint replacement on a table whose existing rows all carry
--    one of the four already-permitted values -- no existing row can fail it.
-- ===========================================================================

alter table app.finance_subledger_batches
  drop constraint finance_subledger_batches_source_type_check;

alter table app.finance_subledger_batches
  add constraint finance_subledger_batches_source_type_check
  check (source_type in ('invoice', 'receipt_allocation', 'vendor_bill', 'settlement', 'opening_balance'));

comment on table app.finance_subledger_batches is
  'FIN-202: one idempotent, balanced subledger batch per source event (unique on tenant/source_type/source_id). Widened at ISS-2026-273 with source_type=''opening_balance'' -- FIN-202''s own header disclosed that opening balances did not yet emit a batch and named that a live constraint on any future opening-balance import; this is that import. gl_journal_id is FIN-203''s own forward reference. status=reversed is FIN-206''s.';

-- ===========================================================================
-- 2b. Widen app.post_finance_subledger_batch's own source-type guard.
--
--     The CHECK constraint above is not the only gate: the posting function
--     carries its own `p_source_type not in (...)` list, and widening one
--     without the other leaves opening balances rejected with
--     `finance_subledger_unsupported_source_type` -- which is exactly what
--     happened on this migration's first local run, caught by the regression
--     rather than reasoned about.
--
--     The body below is a MECHANICAL, script-extracted copy of
--     20260811000000's own definition (the latest of five successive
--     CREATE OR REPLACEs of this function), with exactly one line changed.
--     Nothing is retyped: re-stating ~140 lines of balanced-posting and
--     journal-emission logic by hand is precisely the transcription risk this
--     migration's header argues against elsewhere, and it applies here too.
--     Its `security definer` and `set search_path` clauses come along with it
--     -- omitting them would silently revert this function to INVOKER, the
--     defect 20260811200000 introduced on app.request_finance_settlement_
--     reversal and RGL-404 later had to find.
-- ===========================================================================

create or replace function app.post_finance_subledger_batch(p_tenant_id uuid, p_company_id uuid, p_source_type text, p_source_id uuid, p_posting_date date, p_currency text, p_lines jsonb, p_actor_auth_user_id uuid, p_actor_label text)
returns app.finance_subledger_batches
language plpgsql
security definer
set search_path to 'app', 'pg_temp'
as $function$
declare
  v_batch app.finance_subledger_batches;
  v_period record;
  v_line jsonb;
  v_line_number integer := 0;
  v_debit_total numeric(14, 2) := 0;
  v_credit_total numeric(14, 2) := 0;
  v_direction text;
  v_amount numeric;
  v_account app.finance_accounts;
  v_key text;
  v_journal_lines jsonb := '[]'::jsonb;
  v_journal app.finance_journals;
  v_lock_scope text;
begin
  if p_source_type not in ('invoice', 'receipt_allocation', 'vendor_bill', 'settlement', 'opening_balance') then
    -- ISS-2026-273: 'opening_balance' added. This is the ONLY change to this function's
    -- body; every other line is a mechanical, script-extracted copy of
    -- 20260811000000's own definition (the latest), including its `security definer`
    -- and `set search_path` clauses, so no line is retyped and none can drift.
    raise exception 'finance_subledger_unsupported_source_type: % is not a supported subledger source type', p_source_type
      using errcode = 'check_violation';
  end if;
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_subledger_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_batch from app.finance_subledger_batches where tenant_id = p_tenant_id and source_type = p_source_type and source_id = p_source_id;
  if found then
    return v_batch;
  end if;

  if p_lines is null or jsonb_array_length(p_lines) = 0 then
    raise exception 'finance_subledger_empty_batch: at least one line is required' using errcode = 'check_violation';
  end if;

  select * into v_period from app.resolve_finance_period_for_date(p_tenant_id, p_company_id, p_posting_date);
  if not found then
    raise exception 'finance_subledger_period_not_found: no fiscal period covers %', p_posting_date
      using errcode = 'no_data_found';
  end if;
  if not v_period.posting_eligible then
    raise exception 'finance_subledger_period_not_open: fiscal period % for % is not open', v_period.period_code, p_posting_date
      using errcode = 'check_violation';
  end if;

  v_lock_scope := case when p_source_type in ('invoice', 'receipt_allocation') then 'ar' when p_source_type in ('vendor_bill', 'settlement') then 'ap' else 'gl' end;
  perform app.assert_finance_period_open_for_posting(p_tenant_id, p_company_id, v_period.period_id, v_lock_scope);

  for v_line in select * from jsonb_array_elements(p_lines) loop
    v_direction := v_line ->> 'direction';
    v_amount := (v_line ->> 'amount')::numeric;
    if v_direction not in ('debit', 'credit') then
      raise exception 'finance_subledger_invalid_direction: % is not debit or credit', v_direction using errcode = 'check_violation';
    end if;
    if v_amount is null or v_amount <= 0 then
      raise exception 'finance_subledger_invalid_line_amount: line amount must be positive, got %', v_amount using errcode = 'check_violation';
    end if;
    if v_direction = 'debit' then
      v_debit_total := v_debit_total + v_amount;
    else
      v_credit_total := v_credit_total + v_amount;
    end if;
  end loop;

  if v_debit_total <> v_credit_total then
    raise exception 'finance_subledger_unbalanced_batch: debit total % does not equal credit total % for source % %', v_debit_total, v_credit_total, p_source_type, p_source_id
      using errcode = 'check_violation';
  end if;

  -- HDN-374 finding 3 (new instance, not in HDN-BLK-010's original scope): a genuine
  -- race between the select above and this insert (two concurrent callers posting the
  -- same source_type/source_id) is resolved by re-selecting and returning the winner.
  -- Backed by finance_subledger_batches_source_unique. Caught here, before any
  -- finance_subledger_lines row is written, so the losing caller leaves no partial state.
  begin
    insert into app.finance_subledger_batches (tenant_id, company_id, source_type, source_id, currency, total_amount, posting_period_id, posted_by)
    values (p_tenant_id, p_company_id, p_source_type, p_source_id, p_currency, v_debit_total, v_period.period_id, p_actor_label)
    returning * into v_batch;
  exception
    when unique_violation then
      select * into v_batch from app.finance_subledger_batches where tenant_id = p_tenant_id and source_type = p_source_type and source_id = p_source_id;
      if found then
        return v_batch;
      end if;
      raise;
  end;

  for v_line in select * from jsonb_array_elements(p_lines) loop
    v_line_number := v_line_number + 1;

    if v_line ->> 'accountId' is not null then
      select * into v_account from app.finance_accounts where id = (v_line ->> 'accountId')::uuid and tenant_id = p_tenant_id;
      if not found then
        raise exception 'finance_subledger_unresolved_account: % is not a known account for tenant %', v_line ->> 'accountId', p_tenant_id
          using errcode = 'no_data_found';
      end if;
      if v_account.status <> 'active' then
        raise exception 'finance_subledger_inactive_mapped_account: account % is not active (status=%)', v_account.code, v_account.status
          using errcode = 'check_violation';
      end if;
      if not v_account.is_postable then
        raise exception 'finance_subledger_not_postable_mapped_account: account % is not postable (control account)', v_account.code
          using errcode = 'check_violation';
      end if;
      v_key := null;
    else
      v_key := v_line ->> 'postingMapKey';
      v_account := app.resolve_finance_posting_map_account(p_tenant_id, v_key);
    end if;

    insert into app.finance_subledger_lines (batch_id, tenant_id, line_number, account_id, posting_map_key, direction, amount, open_item_type, open_item_id)
    values (
      v_batch.id, p_tenant_id, v_line_number, v_account.id, v_key, v_line ->> 'direction', (v_line ->> 'amount')::numeric,
      v_line ->> 'openItemType', nullif(v_line ->> 'openItemId', '')::uuid
    );

    v_journal_lines := v_journal_lines || jsonb_build_array(jsonb_build_object('accountId', v_account.id, 'direction', v_line ->> 'direction', 'amount', (v_line ->> 'amount')::numeric));
  end loop;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'post_finance_subledger_batch',
    'app.finance_subledger_batches', v_batch.id, 'success', null, null,
    jsonb_build_object('sourceType', p_source_type, 'sourceId', p_source_id, 'totalAmount', v_debit_total)
  );

  select * into v_journal from app.create_and_post_finance_system_journal(
    p_tenant_id, p_company_id, 'subledger', v_batch.id, p_posting_date, p_currency, v_journal_lines, p_actor_auth_user_id, p_actor_label, v_lock_scope
  );
  update app.finance_subledger_batches set gl_journal_id = v_journal.id where id = v_batch.id returning * into v_batch;

  return v_batch;
end;
$function$;

comment on function app.post_finance_subledger_batch(uuid, uuid, text, uuid, date, text, jsonb, uuid, text) is
  'FIN-202, latest body from 20260811000000, widened at ISS-2026-273 with source_type=''opening_balance'' only. Every other line is a script-extracted copy of that definition, security definer and search_path included.';

-- ===========================================================================
-- 3. app.post_finance_opening_balance_batch -- the GL half.
-- ===========================================================================

create function app.post_finance_opening_balance_batch(
  p_open_item_type text,
  p_open_item_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_subledger_batches
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_ar app.finance_ar_open_items;
  v_ap app.finance_ap_open_items;
  v_tenant_id uuid;
  v_company_id uuid;
  v_currency text;
  v_amount numeric(14, 2);
  v_posting_date date;
  v_lines jsonb;
  v_batch app.finance_subledger_batches;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_open_item_type not in ('ar', 'ap') then
    raise exception 'finance_opening_balance_unknown_item_type: % is not ar or ap', p_open_item_type using errcode = 'check_violation';
  end if;

  if p_open_item_type = 'ar' then
    select * into v_ar from app.finance_ar_open_items where id = p_open_item_id;
    if not found then
      raise exception 'finance_ar_open_item_not_found: %', p_open_item_id using errcode = 'no_data_found';
    end if;
    if v_ar.source_document_type <> 'opening_balance' then
      raise exception 'finance_opening_balance_wrong_source_type: AR open item % is sourced from %, not an opening balance', p_open_item_id, v_ar.source_document_type
        using errcode = 'check_violation';
    end if;
    v_tenant_id := v_ar.tenant_id; v_company_id := v_ar.company_id; v_currency := v_ar.currency;
    v_amount := v_ar.original_amount; v_posting_date := v_ar.invoice_date;
  else
    select * into v_ap from app.finance_ap_open_items where id = p_open_item_id;
    if not found then
      raise exception 'finance_ap_open_item_not_found: %', p_open_item_id using errcode = 'no_data_found';
    end if;
    if v_ap.source_document_type <> 'opening_balance' then
      raise exception 'finance_opening_balance_wrong_source_type: AP open item % is sourced from %, not an opening balance', p_open_item_id, v_ap.source_document_type
        using errcode = 'check_violation';
    end if;
    v_tenant_id := v_ap.tenant_id; v_company_id := v_ap.company_id; v_currency := v_ap.currency;
    v_amount := v_ap.original_amount; v_posting_date := v_ap.bill_date;
  end if;

  -- FIN:Approve, matching what posting the opening balance itself already required. A GL
  -- posting path that asked for less than the subledger posting it mirrors would be a way
  -- around that gate.
  if not app.check_finance_subledger_authority('Approve', v_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent by the batch's own (tenant, source_type, source_id) uniqueness -- the same
  -- guarantee app.post_finance_subledger_batch already provides; the pre-check here only
  -- avoids re-deriving lines for a batch that already exists.
  select * into v_batch from app.finance_subledger_batches
  where tenant_id = v_tenant_id and source_type = 'opening_balance' and source_id = p_open_item_id;
  if found then
    return v_batch;
  end if;

  -- The double entry. See this migration's header for why opening_balance_equity is a
  -- posting-map key rather than a constant: an unconfigured tenant fails closed with
  -- finance_subledger_missing_mapping, which is the correct outcome.
  if p_open_item_type = 'ar' then
    v_lines := jsonb_build_array(
      jsonb_build_object('postingMapKey', 'ar_control', 'direction', 'debit', 'amount', v_amount,
                         'openItemType', 'ar_open_item', 'openItemId', p_open_item_id),
      jsonb_build_object('postingMapKey', 'opening_balance_equity', 'direction', 'credit', 'amount', v_amount)
    );
  else
    v_lines := jsonb_build_array(
      jsonb_build_object('postingMapKey', 'opening_balance_equity', 'direction', 'debit', 'amount', v_amount),
      jsonb_build_object('postingMapKey', 'ap_control', 'direction', 'credit', 'amount', v_amount,
                         'openItemType', 'ap_open_item', 'openItemId', p_open_item_id)
    );
  end if;

  v_batch := app.post_finance_subledger_batch(
    v_tenant_id, v_company_id, 'opening_balance', p_open_item_id, v_posting_date, v_currency,
    v_lines, p_actor_auth_user_id, p_actor_label
  );

  return v_batch;
end;
$$;

comment on function app.post_finance_opening_balance_batch is
  'ISS-2026-273: emits the balanced GL-bound subledger batch an opening-balance AR/AP open item never had (FIN-202 disclosed the gap and named it a live constraint on any future opening-balance import). AR debits ar_control and credits opening_balance_equity; AP debits opening_balance_equity and credits ap_control. opening_balance_equity is a finance_posting_map key, never a hardcoded account -- an unconfigured tenant fails closed with finance_subledger_missing_mapping rather than having an equity account guessed on its behalf. Requires FIN:Approve, matching what posting the opening balance itself required. Idempotent per open item via finance_subledger_batches_source_unique.';

-- ===========================================================================
-- 4. Corrected reconciliation summary.
-- ===========================================================================

-- SECURITY DEFINER and `set search_path` are restated deliberately: this function was
-- hardened to SECURITY DEFINER at 20260810900000 (Finance authority-chain Tier C
-- completeness), and a CREATE OR REPLACE that omits the clause silently reverts it to the
-- Postgres default (INVOKER) -- exactly the latent defect 20260811200000 introduced on
-- app.request_finance_settlement_reversal and that RGL-404 later had to find and fix.
-- Caught here before commit by scripts/db-tests/public-api-wrapper-regression.sql's
-- exhaustive mode-parity check, on the first run of this migration.
create or replace function app.get_finance_subledger_reconciliation_summary(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_ar_account app.finance_accounts;
  v_ap_account app.finance_accounts;
  v_ar_subledger_balance numeric(14, 2) := 0;
  v_ap_subledger_balance numeric(14, 2) := 0;
  v_ar_open_total numeric(14, 2) := 0;
  v_ap_open_total numeric(14, 2) := 0;
  v_ar_unposted numeric(14, 2) := 0;
  v_ap_unposted numeric(14, 2) := 0;
begin
  if not app.check_finance_subledger_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_ar_account := app.resolve_finance_posting_map_account(p_tenant_id, 'ar_control');
  v_ap_account := app.resolve_finance_posting_map_account(p_tenant_id, 'ap_control');

  select coalesce(sum(case when l.direction = 'debit' then l.amount else -l.amount end), 0) into v_ar_subledger_balance
    from app.finance_subledger_lines l join app.finance_subledger_batches b on b.id = l.batch_id
    where b.tenant_id = p_tenant_id and l.account_id = v_ar_account.id;

  select coalesce(sum(case when l.direction = 'credit' then l.amount else -l.amount end), 0) into v_ap_subledger_balance
    from app.finance_subledger_lines l join app.finance_subledger_batches b on b.id = l.batch_id
    where b.tenant_id = p_tenant_id and l.account_id = v_ap_account.id;

  -- ISS-2026-273: opening balances now emit subledger batches, so the open-item side of
  -- the comparison must include the ones that DID -- otherwise a correctly-migrated tenant
  -- reads as unreconciled, since the subledger side already counts them. Opening balances
  -- with NO batch (posted before this fix, or posted while opening_balance_equity is
  -- unconfigured) are deliberately reported separately rather than folded into either
  -- side: a real difference must be visible, not absorbed. Prompt 385 §24's "exact
  -- reconciliation" means being able to see the difference, not excluding it.
  select coalesce(sum(i.open_amount), 0) into v_ar_open_total
    from app.finance_ar_open_items i
    where i.tenant_id = p_tenant_id
      and (i.source_document_type = 'invoice'
           or (i.source_document_type = 'opening_balance'
               and exists (select 1 from app.finance_subledger_batches b
                           where b.tenant_id = p_tenant_id and b.source_type = 'opening_balance' and b.source_id = i.id)));

  select coalesce(sum(i.open_amount), 0) into v_ar_unposted
    from app.finance_ar_open_items i
    where i.tenant_id = p_tenant_id and i.source_document_type = 'opening_balance'
      and not exists (select 1 from app.finance_subledger_batches b
                      where b.tenant_id = p_tenant_id and b.source_type = 'opening_balance' and b.source_id = i.id);

  select coalesce(sum(i.open_amount), 0) into v_ap_open_total
    from app.finance_ap_open_items i
    where i.tenant_id = p_tenant_id
      and (i.source_document_type = 'vendor_bill'
           or (i.source_document_type = 'opening_balance'
               and exists (select 1 from app.finance_subledger_batches b
                           where b.tenant_id = p_tenant_id and b.source_type = 'opening_balance' and b.source_id = i.id)));

  select coalesce(sum(i.open_amount), 0) into v_ap_unposted
    from app.finance_ap_open_items i
    where i.tenant_id = p_tenant_id and i.source_document_type = 'opening_balance'
      and not exists (select 1 from app.finance_subledger_batches b
                      where b.tenant_id = p_tenant_id and b.source_type = 'opening_balance' and b.source_id = i.id);

  return jsonb_build_object(
    'arControlAccountCode', v_ar_account.code,
    'arControlSubledgerBalance', v_ar_subledger_balance,
    'arOpenItemTotal', v_ar_open_total,
    'arReconciled', v_ar_subledger_balance = v_ar_open_total,
    'arOpeningBalanceNotPostedToGl', v_ar_unposted,
    'apControlAccountCode', v_ap_account.code,
    'apControlSubledgerBalance', v_ap_subledger_balance,
    'apOpenItemTotal', v_ap_open_total,
    'apReconciled', v_ap_subledger_balance = v_ap_open_total,
    'apOpeningBalanceNotPostedToGl', v_ap_unposted,
    'openingBalancesFullyPostedToGl', v_ar_unposted = 0 and v_ap_unposted = 0
  );
end;
$$;

comment on function app.get_finance_subledger_reconciliation_summary is
  'FIN-202, corrected at ISS-2026-273. Previously it filtered open-item totals to invoice/vendor_bill only, excluding opening balances from the comparison because they never reached the subledger. Now that they do, the open-item side counts every opening balance that HAS a posted batch (otherwise a correctly-migrated tenant would read as unreconciled, since the subledger side already counts them), and reports those that do NOT as arOpeningBalanceNotPostedToGl/apOpeningBalanceNotPostedToGl plus a top-level openingBalancesFullyPostedToGl boolean. A real difference is made visible rather than absorbed into a total -- Prompt 385 §24''s "exact reconciliation" requires seeing the difference, not excluding it.';

-- ===========================================================================
-- 5. Schema-kind registration.
-- ===========================================================================

insert into app.import_export_schemas (code, name, owner_primitive_code, registered_by)
values ('finance_opening_balance_import', 'Finance Opening Balance Import', 'FIN', 'system')
on conflict (code) do nothing;

insert into app.config_types (code, name, owner_primitive_code, registered_by)
values ('import_export:finance_opening_balance_import', 'Finance Opening Balance Import', 'FIN', 'system')
on conflict (code) do nothing;

-- ===========================================================================
-- 6. app.validate_finance_opening_balance_import_row
-- ===========================================================================

create function app.validate_finance_opening_balance_import_row(
  p_staging_row_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.import_staging_rows
language plpgsql
as $$
declare
  v_row app.import_staging_rows;
  v_job app.jobs;
  v_payload jsonb;
  v_field text;
  v_value text;
  v_errors text[] := array[]::text[];
  v_text_fields text[] := array['open_item_type', 'party_tax_id', 'party_legal_name', 'party_vendor_code', 'currency'];
  v_type text;
  v_amount numeric;
  v_doc_date date;
  v_due_date date;
  v_match_count integer;
  v_period record;
begin
  v_row := app.validate_staging_row(p_staging_row_id, p_actor_auth_user_id, p_actor_label);
  if v_row.validation_status <> 'valid' then
    return v_row;
  end if;

  select * into v_job from app.jobs where job_id = v_row.job_id;
  v_payload := v_row.raw_payload;

  foreach v_field in array v_text_fields loop
    v_value := v_payload ->> v_field;
    if v_value is not null and v_value ~ '^[-+=@\t\r]' then
      v_errors := v_errors || (v_field || ': value begins with a disallowed formula/spreadsheet-injection prefix (=, +, -, @, tab, or carriage return)');
    end if;
  end loop;

  v_type := lower(coalesce(trim(v_payload ->> 'open_item_type'), ''));
  if v_type not in ('ar', 'ap') then
    v_errors := v_errors || ('open_item_type: ' || coalesce(v_payload ->> 'open_item_type', '(missing)') || ' must be ar or ap');
  end if;

  if not app.validate_currency_code(v_payload ->> 'currency') then
    v_errors := v_errors || ('currency: ' || coalesce(v_payload ->> 'currency', '(missing)') || ' is not a registered, active currency');
  end if;

  -- Amount. A zero or negative opening balance is refused HERE rather than mid-commit --
  -- a whole cutover batch aborting on row 700 because of a sign error is a bad outcome
  -- when the row could have been marked invalid up front. Fractional units beyond the
  -- stored numeric(14,2) scale are also refused rather than silently rounded: rounding a
  -- customer's opening debt is exactly the kind of quiet difference §24 forbids.
  begin
    v_amount := (nullif(v_payload ->> 'original_amount', ''))::numeric;
  exception when others then
    v_amount := null;
  end;
  if v_amount is null then
    v_errors := v_errors || ('original_amount: ' || coalesce(v_payload ->> 'original_amount', '(missing)') || ' is not a number');
  elsif v_amount <= 0 then
    v_errors := v_errors || ('original_amount: must be positive, got ' || v_amount);
  elsif v_amount <> round(v_amount, 2) then
    v_errors := v_errors || ('original_amount: ' || v_amount || ' carries more than 2 decimal places and would be silently rounded on storage');
  end if;

  begin
    v_doc_date := (nullif(v_payload ->> 'document_date', ''))::date;
  exception when others then
    v_doc_date := null;
  end;
  begin
    v_due_date := (nullif(v_payload ->> 'due_date', ''))::date;
  exception when others then
    v_due_date := null;
  end;
  if v_doc_date is null then
    v_errors := v_errors || ('document_date: ' || coalesce(v_payload ->> 'document_date', '(missing)') || ' is not a valid date');
  end if;
  if v_due_date is null then
    v_errors := v_errors || ('due_date: ' || coalesce(v_payload ->> 'due_date', '(missing)') || ' is not a valid date');
  end if;
  if v_doc_date is not null and v_due_date is not null and v_due_date < v_doc_date then
    v_errors := v_errors || ('due_date: ' || v_due_date || ' is before document_date ' || v_doc_date);
  end if;

  -- The fiscal period must exist AND be open for the document date. Both primitives check
  -- this, but they check it mid-commit -- by which point earlier rows in the same batch
  -- have already been written and the whole transaction has to roll back.
  if v_doc_date is not null then
    select * into v_period from app.resolve_finance_period_for_date(v_job.tenant_id, null, v_doc_date);
    if not found then
      v_errors := v_errors || ('document_date: no fiscal period covers ' || v_doc_date);
    elsif not v_period.posting_eligible then
      v_errors := v_errors || ('document_date: fiscal period ' || v_period.period_code || ' covering ' || v_doc_date || ' is not open for posting');
    end if;
  end if;

  -- Counterparty resolution. AR names a customer account (by tax id, preferred, or legal
  -- name); AP names a vendor master record (by its vendor code). Ambiguity is an error,
  -- never a silent pick: posting one customer's opening debt against another customer's
  -- account is a financial misstatement, not a tidiness problem.
  if v_type = 'ar' then
    if coalesce(trim(v_payload ->> 'party_tax_id'), '') <> '' then
      select count(*) into v_match_count from app.accounts
      where tenant_id = v_job.tenant_id and status = 'active'
        and normalized_tax_id = app.normalize_prospect_identifier(v_payload ->> 'party_tax_id');
      if v_match_count = 0 then
        v_errors := v_errors || ('party_tax_id: ' || (v_payload ->> 'party_tax_id') || ' does not resolve to an active customer account in this tenant');
      elsif v_match_count > 1 then
        v_errors := v_errors || ('party_tax_id: ' || (v_payload ->> 'party_tax_id') || ' matches ' || v_match_count || ' active accounts -- ambiguous, refusing to guess whose balance this is');
      end if;
    elsif coalesce(trim(v_payload ->> 'party_legal_name'), '') <> '' then
      select count(*) into v_match_count from app.accounts
      where tenant_id = v_job.tenant_id and status = 'active'
        and normalized_legal_name = app.normalize_prospect_identifier(v_payload ->> 'party_legal_name');
      if v_match_count = 0 then
        v_errors := v_errors || ('party_legal_name: ' || (v_payload ->> 'party_legal_name') || ' does not resolve to an active customer account in this tenant');
      elsif v_match_count > 1 then
        v_errors := v_errors || ('party_legal_name: ' || (v_payload ->> 'party_legal_name') || ' matches ' || v_match_count || ' active accounts -- ambiguous, supply party_tax_id instead');
      end if;
    else
      v_errors := v_errors || 'party: an AR opening balance requires party_tax_id or party_legal_name naming the customer account'::text;
    end if;
  elsif v_type = 'ap' then
    if coalesce(trim(v_payload ->> 'party_vendor_code'), '') = '' then
      v_errors := v_errors || 'party: an AP opening balance requires party_vendor_code naming the vendor master record'::text;
    else
      select count(*) into v_match_count from app.master_records
      where tenant_id = v_job.tenant_id and master_type_code = 'vendor' and code = (v_payload ->> 'party_vendor_code');
      if v_match_count = 0 then
        v_errors := v_errors || ('party_vendor_code: ' || (v_payload ->> 'party_vendor_code') || ' does not resolve to a registered vendor in this tenant');
      end if;
    end if;
  end if;

  if array_length(v_errors, 1) is not null then
    update app.import_staging_rows
    set validation_status = 'invalid', error = array_to_string(v_errors, '; ')
    where id = p_staging_row_id
    returning * into v_row;

    update app.jobs
    set valid_row_count = valid_row_count - 1, invalid_row_count = invalid_row_count + 1
    where job_id = v_row.job_id;
  end if;

  return v_row;
end;
$$;

comment on function app.validate_finance_opening_balance_import_row is
  'ISS-2026-273: domain row validator for finance_opening_balance_import. Calls app.validate_staging_row UNCHANGED, then adds what it cannot do: formula-injection rejection, ar/ap discrimination, a registered active currency, a positive amount that does not carry more than 2 decimal places (rounding a customer''s opening debt is exactly the quiet difference Prompt 385 §24 forbids), real dates with due >= document, a fiscal period that exists and is OPEN for the document date, and counterparty resolution (customer by tax id or legal name for AR, vendor code for AP). Ambiguity is an error, never a silent pick -- posting one customer''s opening debt against another''s account is a financial misstatement. Every one of these is checked at validation time precisely so a thousand-row cutover does not abort on row 700 and roll back everything before it.';

-- ===========================================================================
-- 7. app.commit_finance_opening_balance_import_job
-- ===========================================================================

create function app.commit_finance_opening_balance_import_job(
  p_job_id uuid,
  p_allow_partial boolean,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_client_ip text default null
)
returns app.jobs
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_job app.jobs;
  v_decision app.rbac_decision;
  v_pending_count integer;
  v_row record;
  v_payload jsonb;
  v_type text;
  v_party_id uuid;
  v_ar app.finance_ar_open_items;
  v_ap app.finance_ap_open_items;
  v_ar_count integer := 0;
  v_ap_count integer := 0;
  v_batch_count integer := 0;
  v_skipped_count integer := 0;
  v_updated app.jobs;
begin
  select * into v_job from app.jobs where job_id = p_job_id for update;
  if not found then
    raise exception 'import_export_job_not_found: no job %', p_job_id using errcode = 'no_data_found';
  end if;

  if v_job.job_type <> 'import' or v_job.import_export_schema_code <> 'finance_opening_balance_import' then
    raise exception 'import_export_wrong_schema: job % is not a finance_opening_balance_import job', p_job_id using errcode = 'check_violation';
  end if;

  if not app.check_import_export_job_authority(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'job_actor_unauthorized: identity % lacks active membership in tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.is_support_grant_authority(p_actor_auth_user_id, v_job.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_job.tenant_id, 'FIN', 'Import');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks FIN:Import (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_job.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_job.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  if v_job.status <> 'in_progress' then
    raise exception 'import_export_job_not_committable: job % is %, only an in_progress job may be committed', p_job_id, v_job.status
      using errcode = 'check_violation';
  end if;

  select count(*) into v_pending_count from app.import_staging_rows where job_id = p_job_id and validation_status = 'pending';
  if v_pending_count > 0 then
    raise exception 'import_export_job_not_fully_validated: job % still has % row(s) pending validation', p_job_id, v_pending_count
      using errcode = 'check_violation';
  end if;

  if v_job.invalid_row_count > 0 and not coalesce(p_allow_partial, false) then
    raise exception 'import_export_job_has_invalid_rows: job % has % invalid row(s); pass p_allow_partial to accept a partial commit', p_job_id, v_job.invalid_row_count
      using errcode = 'check_violation';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_job_id::text, 205));

  for v_row in
    select * from app.import_staging_rows
    where job_id = p_job_id and validation_status = 'valid'
    order by row_number
  loop
    v_payload := v_row.raw_payload;
    v_type := lower(trim(v_payload ->> 'open_item_type'));

    if v_type = 'ar' then
      if exists (
        select 1 from app.finance_ar_open_items
        where tenant_id = v_job.tenant_id and source_document_type = 'opening_balance' and source_document_id = v_row.id
      ) then
        v_skipped_count := v_skipped_count + 1;
        continue;
      end if;

      -- Re-resolved at write time, not carried from validation: an account can be merged
      -- or deactivated in between, and posting a balance to a merged account would be a
      -- silent misstatement.
      if coalesce(trim(v_payload ->> 'party_tax_id'), '') <> '' then
        select a.id into v_party_id from app.accounts a
        where a.tenant_id = v_job.tenant_id and a.status = 'active'
          and a.normalized_tax_id = app.normalize_prospect_identifier(v_payload ->> 'party_tax_id');
      else
        select a.id into v_party_id from app.accounts a
        where a.tenant_id = v_job.tenant_id and a.status = 'active'
          and a.normalized_legal_name = app.normalize_prospect_identifier(v_payload ->> 'party_legal_name');
      end if;
      if v_party_id is null then
        raise exception 'import_opening_balance_party_not_found: staged row % no longer resolves to exactly one active customer account in tenant %', v_row.row_number, v_job.tenant_id
          using errcode = 'check_violation';
      end if;

      -- The staged row id IS the source document id. See this migration's header: the
      -- existing finance_ar_open_items_source_unique already makes that the idempotency
      -- key, and a second provenance column would be a competing source of truth.
      -- company_id is null: app.jobs is tenant-scoped and carries no company column, and
      -- inventing one would attribute a balance to an org unit the file never named.
      -- app.finance_ar_open_items.company_id is nullable, and
      -- app.resolve_finance_period_for_date resolves tenant-level periods with a null
      -- company -- the same null this row's own validation already checked against.
      v_ar := app.post_finance_ar_open_item(
        v_job.tenant_id, null, v_party_id, 'opening_balance', v_row.id,
        v_payload ->> 'currency', (v_payload ->> 'original_amount')::numeric,
        (v_payload ->> 'document_date')::date, (v_payload ->> 'due_date')::date,
        p_actor_auth_user_id, p_actor_label
      );
      v_ar_count := v_ar_count + 1;

      -- Both halves in the SAME transaction. A subledger row without its GL batch is the
      -- exact state ISS-2026-273 exists to end, so it must not be reachable even by a
      -- commit that fails halfway: if this raises, the open item above rolls back with it.
      perform app.post_finance_opening_balance_batch('ar', v_ar.id, p_actor_auth_user_id, p_actor_label);
      v_batch_count := v_batch_count + 1;
    else
      if exists (
        select 1 from app.finance_ap_open_items
        where tenant_id = v_job.tenant_id and source_document_type = 'opening_balance' and source_document_id = v_row.id
      ) then
        v_skipped_count := v_skipped_count + 1;
        continue;
      end if;

      select m.id into v_party_id from app.master_records m
      where m.tenant_id = v_job.tenant_id and m.master_type_code = 'vendor' and m.code = (v_payload ->> 'party_vendor_code');
      if v_party_id is null then
        raise exception 'import_opening_balance_party_not_found: staged row % names vendor code %, which no longer resolves in tenant %', v_row.row_number, v_payload ->> 'party_vendor_code', v_job.tenant_id
          using errcode = 'check_violation';
      end if;

      v_ap := app.post_finance_ap_open_item(
        v_job.tenant_id, null, v_party_id, 'opening_balance', v_row.id,
        v_payload ->> 'currency', (v_payload ->> 'original_amount')::numeric,
        (v_payload ->> 'document_date')::date, (v_payload ->> 'due_date')::date,
        p_actor_auth_user_id, p_actor_label
      );
      v_ap_count := v_ap_count + 1;

      perform app.post_finance_opening_balance_batch('ap', v_ap.id, p_actor_auth_user_id, p_actor_label);
      v_batch_count := v_batch_count + 1;
    end if;
  end loop;

  update app.jobs
  set status = 'completed', completed_at = now()
  where job_id = p_job_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'commit_finance_opening_balance_import_job',
    'app.jobs', p_job_id, 'success', null, to_jsonb(v_job),
    jsonb_build_object(
      'status', v_updated.status,
      'ar_open_items_created', v_ar_count,
      'ap_open_items_created', v_ap_count,
      'subledger_batches_posted', v_batch_count,
      'rows_already_committed_skipped', v_skipped_count
    )
  );

  return v_updated;
end;
$$;

comment on function app.commit_finance_opening_balance_import_job is
  'ISS-2026-273: the PLT-131 domain-write adapter for finance_opening_balance_import, closing the "no bulk opening-balance path exists at all" half of that entry. One schema handles both AR and AP (a cutover extract is normally one trial-balance file). Requires BOTH app.is_support_grant_authority AND FIN:Import; app.post_finance_ar_open_item/app.post_finance_ap_open_item then enforce their own FIN:Approve per row, since opening_balance already demanded Approve. Every committed row does BOTH halves in the same transaction -- the open item AND its GL batch -- so a state where the subledger and the ledger disagree is not reachable even by a commit that fails midway. The staged row id is the source_document_id, which is already the primitives'' own idempotency key; no second provenance column is added, because two sources of truth for the same fact can disagree. The counterparty is re-resolved at write time, since an account can be merged between validate and commit. No unique_violation handler exists anywhere in the loop, deliberately: both primitives return the existing row rather than raising, so anything that escapes is a real failure and must abort the whole commit.';

-- ===========================================================================
-- 8. PostgREST wrappers (mode parity with each app.* counterpart).
-- ===========================================================================

create function public.post_finance_opening_balance_batch(p_open_item_type text, p_open_item_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns app.finance_subledger_batches
language sql
security definer
set search_path = app, public, pg_temp
as $$
  select app.post_finance_opening_balance_batch(p_open_item_type, p_open_item_id, p_actor_auth_user_id, p_actor_label);
$$;

create function public.validate_finance_opening_balance_import_row(p_staging_row_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns app.import_staging_rows
language sql
set search_path = app, public, pg_temp
as $$
  select app.validate_finance_opening_balance_import_row(p_staging_row_id, p_actor_auth_user_id, p_actor_label);
$$;

create function public.commit_finance_opening_balance_import_job(p_job_id uuid, p_allow_partial boolean, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
returns app.jobs
language sql
security definer
set search_path = app, public, pg_temp
as $$
  select app.commit_finance_opening_balance_import_job(p_job_id, p_allow_partial, p_actor_auth_user_id, p_actor_label, p_client_ip);
$$;

-- ===========================================================================
-- 9. Grants (ERR-2026-004).
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant execute on function app.post_finance_opening_balance_batch(text, uuid, uuid, text) to service_role;
grant execute on function app.validate_finance_opening_balance_import_row(uuid, uuid, text) to service_role;
grant execute on function app.commit_finance_opening_balance_import_job(uuid, boolean, uuid, text, text) to service_role;

revoke execute on function public.post_finance_opening_balance_batch(text, uuid, uuid, text) from anon, authenticated, service_role, public;
grant execute on function public.post_finance_opening_balance_batch(text, uuid, uuid, text) to service_role;

revoke execute on function public.validate_finance_opening_balance_import_row(uuid, uuid, text) from anon, authenticated, service_role, public;
grant execute on function public.validate_finance_opening_balance_import_row(uuid, uuid, text) to service_role;

revoke execute on function public.commit_finance_opening_balance_import_job(uuid, boolean, uuid, text, text) from anon, authenticated, service_role, public;
grant execute on function public.commit_finance_opening_balance_import_job(uuid, boolean, uuid, text, text) to service_role;
