-- Finance capability FIN-202 (Subledger, CG-S9-FIN-013)
-- Canonical source subledgers translating invoice, receipt-allocation,
-- vendor-bill and settlement events into balanced, reconcilable accounting
-- events -- built on top of FIN-191/192's own `finance_posting_map`
-- configuration engine and chart of accounts, which were built exactly for
-- this purpose (FIN-191's own migration header: "FIN-192... to add real
-- account-existence checking for the finance_posting_map class").
--
-- Posting-map-driven account resolution (Prompt 202 section 21: "service
-- resolves captured policy/accounts/dimensions"): `app.resolve_finance_posting_map_account`
-- resolves one tenant's own published `finance_posting_map` config
-- (`app.resolve_finance_config`, FIN-191) for a well-known key
-- (`ar_control`, `ap_control`, `revenue_default`, `expense_default`,
-- `cash_default`, `tax_payable_default`, `input_tax_default`,
-- `fee_expense_default`) to a real, active, postable `app.finance_accounts`
-- row (FIN-192) -- never a hardcoded account, never a silent default. A
-- missing/inactive/non-postable mapping blocks the *entire* source posting
-- (invoice issue, receipt allocation, vendor bill post, settlement post all
-- run inside one transaction with their own subledger effect), matching
-- Prompt 202 section 23's "Block missing/inactive account... never hide or
-- bypass failure" -- the source document simply does not post until the
-- tenant's own posting map is corrected, a real, safe, disclosed resume
-- point, not a silently skipped ledger entry.
--
-- Governed tax-account override (Prompt 202 section 4's own "translate...
-- into reconcilable accounting events"): a tax line whose own
-- `app.finance_tax_rule_versions` row carries a real `output_account_id`
-- (invoice) or `recoverable_account_id` (vendor bill) posts directly to that
-- already-governed account (validated active/postable/same-tenant at
-- FIN-195's own draft/approval time) instead of the generic
-- `tax_payable_default`/`input_tax_default` posting-map fallback -- one
-- governed account reference, never re-typed or duplicated.
--
-- Real integration, not a placeholder engine (Definition of Done: "without
-- placeholder/fake persistence/dead action"): this migration
-- `CREATE OR REPLACE FUNCTION`s `app.issue_finance_invoice` (FIN-197),
-- `app.allocate_finance_receipt` (FIN-198), `app.post_finance_vendor_bill`
-- (FIN-200) and `app.post_finance_settlement` (FIN-201) -- the established
-- later-migration-extends-an-earlier-one's-function-by-full-replacement
-- pattern this repository has used since
-- `20260724290000_create_commercial_customer_account_conversion.sql` -- to
-- each emit exactly one balanced `app.finance_subledger_batches` row at
-- their own existing posting moment, inside the same transaction, with
-- every other line of each function's own body byte-for-byte unchanged.
-- Reversal/adjustment posting (governed correction of an already-posted
-- subledger batch) is explicitly `FIN-206`'s own scope (Reversal and
-- Adjustment) -- not retrofitted here, so "Each source produces at most one
-- intended subledger effect" (Prompt 202 section 33) holds structurally: a
-- reversed AR/AP balance today has no reversing subledger line yet,
-- disclosed, not silently claimed reconciled past that point.
--
-- GL journal reference (Prompt 202 section 13): `gl_journal_id` is a bare
-- `uuid` column, deliberately not a foreign key -- `app.finance_journals`
-- does not exist yet in this dependency order (`FIN-203`, Double-Entry
-- Journal, is the very next capability). Mirrors FIN-191's own disclosed
-- "posting-map account-code references stored structurally only" idiom
-- exactly: `FIN-203`'s own migration is expected to populate this column
-- once its own journal table exists, not this one.
--
-- Bounded MVP scope, disclosed: `fee_expense_default`/`revenue_default`/
-- `expense_default`/`cash_default` are single default accounts per tenant,
-- not a dimension-routed (branch/service/customer-class) chart -- Prompt
-- 202 section 58's own "account/dimension" scope is bounded to the account
-- axis only at this checkpoint, the same class of proportionate-effort
-- decision every prior FIN-19x/20x checkpoint's own header has recorded.
-- `app.finance_ar_open_items`/`finance_ap_open_items` rows created via the
-- `opening_balance` source type (FIN-196/199's own approved-migration path)
-- do not yet emit a subledger batch -- disclosed, not a defect, since Phase
-- 4 remains a greenfield internal delivery gate with no real historical
-- balance to reconcile yet (Prompt 202 section 19's own "opening subledger
-- import... unexplained differences are blockers" is a live constraint on
-- any *future* opening-balance import, not on this checkpoint's own
-- zero-history starting state).
--
-- Money/decimal discipline: every amount column is `numeric(14,2)`, never
-- `float`; every subledger batch is balanced by construction (debit total
-- must equal credit total or the batch is rejected before any row is
-- written).
--
-- Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration
-- carries its own explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app
-- FROM PUBLIC` statement before its final grants, the standing
-- per-migration convention since `PLT-118`.

create table app.finance_subledger_batches (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  company_id uuid references app.org_units (id),
  source_type text not null,
  source_id uuid not null,
  currency text not null,
  total_amount numeric(14, 2) not null,
  status text not null default 'posted',
  posting_period_id uuid references app.finance_fiscal_periods (id),
  gl_journal_id uuid,
  posted_by text,
  posted_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint finance_subledger_batches_source_type_check check (source_type in ('invoice', 'receipt_allocation', 'vendor_bill', 'settlement')),
  constraint finance_subledger_batches_status_check check (status in ('posted', 'reversed')),
  constraint finance_subledger_batches_currency_check check (currency ~ '^[A-Z]{3}$'),
  constraint finance_subledger_batches_total_amount_check check (total_amount > 0),
  constraint finance_subledger_batches_source_unique unique (tenant_id, source_type, source_id)
);

comment on table app.finance_subledger_batches is
  'FIN-202: one idempotent, balanced subledger batch per source event (unique on tenant/source_type/source_id). gl_journal_id is deliberately not a foreign key -- app.finance_journals does not exist until FIN-203, the next capability; this column is FIN-203''s own disclosed forward reference to populate. status=reversed is reserved for FIN-206 (Reversal and Adjustment), never set by this migration.';

create index finance_subledger_batches_tenant_source_idx on app.finance_subledger_batches (tenant_id, source_type);
create index finance_subledger_batches_tenant_period_idx on app.finance_subledger_batches (tenant_id, posting_period_id);

create table app.finance_subledger_lines (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references app.finance_subledger_batches (id),
  tenant_id uuid not null references app.tenants (id),
  line_number integer not null,
  account_id uuid not null references app.finance_accounts (id),
  posting_map_key text,
  direction text not null,
  amount numeric(14, 2) not null,
  open_item_type text,
  open_item_id uuid,
  created_at timestamptz not null default now(),
  constraint finance_subledger_lines_direction_check check (direction in ('debit', 'credit')),
  constraint finance_subledger_lines_amount_check check (amount > 0),
  constraint finance_subledger_lines_open_item_type_check check (open_item_type is null or open_item_type in ('ar_open_item', 'ap_open_item')),
  constraint finance_subledger_lines_batch_line_unique unique (batch_id, line_number)
);

comment on table app.finance_subledger_lines is
  'FIN-202: one exact debit/credit line. posting_map_key records which app.finance_posting_map key resolved account_id (null when the line instead posts directly to an already-governed FIN-195 tax rule account) -- full lineage from account back to policy, per Prompt 202 section 18.';

create index finance_subledger_lines_batch_idx on app.finance_subledger_lines (batch_id);
create index finance_subledger_lines_account_idx on app.finance_subledger_lines (tenant_id, account_id);
create index finance_subledger_lines_open_item_idx on app.finance_subledger_lines (open_item_type, open_item_id) where open_item_id is not null;

create function app.check_finance_subledger_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
as $$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'FIN', p_action)).allowed;
$$;

comment on function app.check_finance_subledger_authority is
  'FIN-202: FIN:Edit gates app.post_finance_subledger_batch itself (defense in depth -- every real caller today is an already-FIN:Edit/FIN:Approve-checked source posting: invoice issue, receipt allocation, vendor bill post, settlement post, per Prompt 202 section 24''s own "Normal users cannot create arbitrary source events"). FIN:View gates every read/preview/reconciliation-query operation.';

-- Resolves one posting-map key to a real, active, postable account for the
-- tenant. Raises a distinct, named exception for every failure mode in
-- Prompt 202 section 23 ("Block missing/inactive account").
create function app.resolve_finance_posting_map_account(p_tenant_id uuid, p_key text)
returns app.finance_accounts
language plpgsql
stable
as $$
declare
  v_config record;
  v_item jsonb;
  v_account app.finance_accounts;
begin
  select * into v_config from app.resolve_finance_config('finance_posting_map', p_tenant_id);
  if not found then
    raise exception 'finance_subledger_missing_posting_map: no published finance posting map exists for tenant %', p_tenant_id
      using errcode = 'no_data_found';
  end if;

  v_item := v_config.items -> p_key;
  if v_item is null then
    raise exception 'finance_subledger_missing_mapping: posting map key % is not configured for tenant %', p_key, p_tenant_id
      using errcode = 'no_data_found';
  end if;

  select * into v_account from app.finance_accounts where tenant_id = p_tenant_id and code = (v_item ->> 'accountCodeRef');
  if not found then
    raise exception 'finance_subledger_unresolved_mapping: posting map key % references account code % which does not exist for tenant %', p_key, v_item ->> 'accountCodeRef', p_tenant_id
      using errcode = 'no_data_found';
  end if;
  if v_account.status <> 'active' then
    raise exception 'finance_subledger_inactive_mapped_account: posting map key % resolves to account % which is not active (status=%)', p_key, v_account.code, v_account.status
      using errcode = 'check_violation';
  end if;
  if not v_account.is_postable then
    raise exception 'finance_subledger_not_postable_mapped_account: posting map key % resolves to account % which is not postable (control account)', p_key, v_account.code
      using errcode = 'check_violation';
  end if;

  return v_account;
end;
$$;

-- The one idempotent, balanced posting entry point (Prompt 202 section 21).
-- p_lines is a jsonb array of {"postingMapKey": text, "direction": text,
-- "amount": numeric, "openItemType": text, "openItemId": uuid} OR
-- {"accountId": uuid, "direction": ..., "amount": ...} for an
-- already-governed direct account reference (e.g. a FIN-195 tax rule's own
-- output/recoverable account). Rejects an unbalanced batch before writing
-- any row.
create function app.post_finance_subledger_batch(
  p_tenant_id uuid,
  p_company_id uuid,
  p_source_type text,
  p_source_id uuid,
  p_posting_date date,
  p_currency text,
  p_lines jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_subledger_batches
language plpgsql
as $$
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
begin
  if p_source_type not in ('invoice', 'receipt_allocation', 'vendor_bill', 'settlement') then
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

  insert into app.finance_subledger_batches (tenant_id, company_id, source_type, source_id, currency, total_amount, posting_period_id, posted_by)
  values (p_tenant_id, p_company_id, p_source_type, p_source_id, p_currency, v_debit_total, v_period.period_id, p_actor_label)
  returning * into v_batch;

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
  end loop;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'post_finance_subledger_batch',
    'app.finance_subledger_batches', v_batch.id, 'success', null, null,
    jsonb_build_object('sourceType', p_source_type, 'sourceId', p_source_id, 'totalAmount', v_debit_total)
  );

  return v_batch;
end;
$$;

-- Read-only preview (Prompt 202 section 15/21's own "debit/credit preview"):
-- resolves the same accounts and balance check as app.post_finance_subledger_batch
-- but persists nothing.
create function app.preview_finance_subledger_posting(p_tenant_id uuid, p_lines jsonb, p_actor_auth_user_id uuid)
returns jsonb
language plpgsql
stable
as $$
declare
  v_line jsonb;
  v_direction text;
  v_amount numeric;
  v_account app.finance_accounts;
  v_key text;
  v_debit_total numeric(14, 2) := 0;
  v_credit_total numeric(14, 2) := 0;
  v_resolved jsonb := '[]'::jsonb;
begin
  if not app.check_finance_subledger_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_lines is null or jsonb_array_length(p_lines) = 0 then
    raise exception 'finance_subledger_empty_batch: at least one line is required' using errcode = 'check_violation';
  end if;

  for v_line in select * from jsonb_array_elements(p_lines) loop
    v_direction := v_line ->> 'direction';
    v_amount := (v_line ->> 'amount')::numeric;
    if v_direction not in ('debit', 'credit') then
      raise exception 'finance_subledger_invalid_direction: % is not debit or credit', v_direction using errcode = 'check_violation';
    end if;
    if v_amount is null or v_amount <= 0 then
      raise exception 'finance_subledger_invalid_line_amount: line amount must be positive, got %', v_amount using errcode = 'check_violation';
    end if;

    if v_line ->> 'accountId' is not null then
      select * into v_account from app.finance_accounts where id = (v_line ->> 'accountId')::uuid and tenant_id = p_tenant_id;
      if not found then
        raise exception 'finance_subledger_unresolved_account: % is not a known account for tenant %', v_line ->> 'accountId', p_tenant_id
          using errcode = 'no_data_found';
      end if;
      v_key := null;
    else
      v_key := v_line ->> 'postingMapKey';
      v_account := app.resolve_finance_posting_map_account(p_tenant_id, v_key);
    end if;

    if v_direction = 'debit' then
      v_debit_total := v_debit_total + v_amount;
    else
      v_credit_total := v_credit_total + v_amount;
    end if;

    v_resolved := v_resolved || jsonb_build_array(jsonb_build_object(
      'postingMapKey', v_key, 'accountId', v_account.id, 'accountCode', v_account.code, 'direction', v_direction, 'amount', v_amount
    ));
  end loop;

  return jsonb_build_object('lines', v_resolved, 'debitTotal', v_debit_total, 'creditTotal', v_credit_total, 'balanced', v_debit_total = v_credit_total);
end;
$$;

create function app.list_finance_subledger_batches(
  p_tenant_id uuid,
  p_company_id uuid,
  p_source_type text,
  p_actor_auth_user_id uuid
)
returns setof app.finance_subledger_batches
language plpgsql
stable
as $$
begin
  if not app.check_finance_subledger_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_subledger_batches
    where tenant_id = p_tenant_id
      and (p_company_id is null or company_id = p_company_id)
      and (p_source_type is null or source_type = p_source_type)
    order by posted_at desc
    limit 200;
end;
$$;

create function app.get_finance_subledger_lines(p_batch_id uuid, p_actor_auth_user_id uuid)
returns setof app.finance_subledger_lines
language plpgsql
stable
as $$
declare
  v_batch app.finance_subledger_batches;
begin
  select * into v_batch from app.finance_subledger_batches where id = p_batch_id;
  if not found then
    raise exception 'finance_subledger_batch_not_found: %', p_batch_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_subledger_authority('View', v_batch.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, v_batch.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_subledger_lines where batch_id = p_batch_id order by line_number asc;
end;
$$;

-- Control-account reconciliation (Prompt 202 section 33: "Control-account
-- reconciliation is explainable to source/version"). Compares the
-- subledger's own posted balance for the ar_control/ap_control accounts
-- against FIN-196/FIN-199's own live open-item totals -- a real, direct
-- comparison, not an asserted-equal claim.
create function app.get_finance_subledger_reconciliation_summary(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns jsonb
language plpgsql
stable
as $$
declare
  v_ar_account app.finance_accounts;
  v_ap_account app.finance_accounts;
  v_ar_subledger_balance numeric(14, 2) := 0;
  v_ap_subledger_balance numeric(14, 2) := 0;
  v_ar_open_total numeric(14, 2) := 0;
  v_ap_open_total numeric(14, 2) := 0;
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

  select coalesce(sum(open_amount), 0) into v_ar_open_total from app.finance_ar_open_items where tenant_id = p_tenant_id and source_document_type = 'invoice';
  select coalesce(sum(open_amount), 0) into v_ap_open_total from app.finance_ap_open_items where tenant_id = p_tenant_id and source_document_type = 'vendor_bill';

  return jsonb_build_object(
    'arControlAccountCode', v_ar_account.code,
    'arControlSubledgerBalance', v_ar_subledger_balance,
    'arOpenItemTotal', v_ar_open_total,
    'arReconciled', v_ar_subledger_balance = v_ar_open_total,
    'apControlAccountCode', v_ap_account.code,
    'apControlSubledgerBalance', v_ap_subledger_balance,
    'apOpenItemTotal', v_ap_open_total,
    'apReconciled', v_ap_subledger_balance = v_ap_open_total
  );
end;
$$;

-- FIN-202 retrofit: FIN-197's own app.issue_finance_invoice now additionally
-- emits one balanced subledger batch at issue time. Every other line of this
-- function's own body is byte-for-byte unchanged from FIN-197's original.
create or replace function app.issue_finance_invoice(
  p_invoice_id uuid,
  p_expected_version integer,
  p_issue_date date,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_invoices
language plpgsql
as $$
declare
  v_invoice app.finance_invoices;
  v_period record;
  v_year integer;
  v_seq integer;
  v_number text;
  v_ar_item app.finance_ar_open_items;
  v_due_date date;
  v_lines jsonb;
  v_tax_line app.finance_invoice_lines;
  v_tax_rule app.finance_tax_rule_versions;
begin
  select * into v_invoice from app.finance_invoices where id = p_invoice_id;
  if not found then
    raise exception 'finance_invoice_not_found: %', p_invoice_id using errcode = 'no_data_found';
  end if;
  if v_invoice.status = 'issued' then
    return v_invoice;
  end if;
  if not app.check_finance_invoice_authority('Approve', v_invoice.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_invoice.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_invoice.record_version <> p_expected_version then
    raise exception 'stale_version: invoice % expected version % but found %', p_invoice_id, p_expected_version, v_invoice.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_invoice.status <> 'approved' then
    raise exception 'finance_invoice_not_approved: invoice % is % not approved', p_invoice_id, v_invoice.status
      using errcode = 'check_violation';
  end if;

  select * into v_period from app.resolve_finance_period_for_date(v_invoice.tenant_id, v_invoice.company_id, p_issue_date);
  if not found then
    raise exception 'finance_invoice_period_not_found: no fiscal period covers %', p_issue_date
      using errcode = 'no_data_found';
  end if;
  if not v_period.posting_eligible then
    raise exception 'finance_invoice_period_not_open: fiscal period % for % is not open', v_period.period_code, p_issue_date
      using errcode = 'check_violation';
  end if;

  v_year := extract(year from p_issue_date)::integer;
  insert into app.finance_invoice_number_counters (tenant_id, company_id, year, next_seq)
  values (v_invoice.tenant_id, v_invoice.company_id, v_year, 2)
  on conflict (tenant_id, coalesce(company_id, '00000000-0000-0000-0000-000000000000'::uuid), year)
  do update set next_seq = app.finance_invoice_number_counters.next_seq + 1
  returning next_seq - 1 into v_seq;
  v_number := 'INV-' || v_year::text || '-' || lpad(v_seq::text, 6, '0');

  v_due_date := p_issue_date + (v_invoice.payment_term_days || ' days')::interval;

  select * into v_ar_item from app.post_finance_ar_open_item(
    v_invoice.tenant_id, v_invoice.company_id, v_invoice.customer_account_id, 'invoice', v_invoice.id,
    v_invoice.currency, v_invoice.total_amount, p_issue_date, v_due_date, p_actor_auth_user_id, p_actor_label
  );

  -- FIN-202: debit AR control for the full total; credit revenue for the
  -- subtotal; credit each tax line's own governed output account (or the
  -- tax_payable_default posting-map key when none is configured).
  v_lines := jsonb_build_array(
    jsonb_build_object('postingMapKey', 'ar_control', 'direction', 'debit', 'amount', v_invoice.total_amount, 'openItemType', 'ar_open_item', 'openItemId', v_ar_item.id)
  );
  if v_invoice.subtotal_amount > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('postingMapKey', 'revenue_default', 'direction', 'credit', 'amount', v_invoice.subtotal_amount));
  end if;
  for v_tax_line in select * from app.finance_invoice_lines where invoice_id = p_invoice_id and line_type = 'tax' and amount > 0 loop
    v_tax_rule := null;
    if v_tax_line.tax_rule_version_id is not null then
      select * into v_tax_rule from app.finance_tax_rule_versions where id = v_tax_line.tax_rule_version_id and output_account_id is not null;
    end if;
    if v_tax_rule is not null then
      v_lines := v_lines || jsonb_build_array(jsonb_build_object('accountId', v_tax_rule.output_account_id, 'direction', 'credit', 'amount', v_tax_line.amount));
    else
      v_lines := v_lines || jsonb_build_array(jsonb_build_object('postingMapKey', 'tax_payable_default', 'direction', 'credit', 'amount', v_tax_line.amount));
    end if;
  end loop;

  perform app.post_finance_subledger_batch(
    v_invoice.tenant_id, v_invoice.company_id, 'invoice', v_invoice.id, p_issue_date, v_invoice.currency,
    v_lines, p_actor_auth_user_id, p_actor_label
  );

  update app.finance_invoices
    set status = 'issued', invoice_number = v_number, issue_date = p_issue_date, due_date = v_due_date,
        posting_period_id = v_period.period_id, ar_open_item_id = v_ar_item.id, issued_by = p_actor_label, issued_at = now()
    where id = p_invoice_id
    returning * into v_invoice;

  perform app.capture_audit_event(
    v_invoice.tenant_id, p_actor_auth_user_id, p_actor_label, 'issue_finance_invoice',
    'app.finance_invoices', v_invoice.id, 'success', null, null, to_jsonb(v_invoice)
  );

  return v_invoice;
end;
$$;

-- FIN-202 retrofit: FIN-198's own app.allocate_finance_receipt now
-- additionally emits one balanced subledger batch per allocate call (one
-- batch per app.finance_receipt_allocation_batches row -- the natural,
-- already-idempotent per-call source id). Every other line of this
-- function's own body is byte-for-byte unchanged from FIN-198's original.
create or replace function app.allocate_finance_receipt(
  p_receipt_id uuid,
  p_idempotency_key text,
  p_allocations jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_receipts
language plpgsql
as $$
declare
  v_receipt app.finance_receipts;
  v_batch app.finance_receipt_allocation_batches;
  v_item jsonb;
  v_open_item_id uuid;
  v_amount numeric;
  v_open_item app.finance_ar_open_items;
  v_total numeric := 0;
begin
  select * into v_receipt from app.finance_receipts where id = p_receipt_id for update;
  if not found then
    raise exception 'finance_receipt_not_found: %', p_receipt_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_receipt_authority('Edit', v_receipt.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_receipt.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: a non-empty idempotency_key is required' using errcode = 'check_violation';
  end if;

  select * into v_batch from app.finance_receipt_allocation_batches where tenant_id = v_receipt.tenant_id and receipt_id = p_receipt_id and idempotency_key = p_idempotency_key;
  if found then
    return v_receipt;
  end if;

  if p_allocations is null or jsonb_array_length(p_allocations) = 0 then
    raise exception 'finance_receipt_empty_allocation: at least one allocation line is required' using errcode = 'check_violation';
  end if;

  for v_item in select * from jsonb_array_elements(p_allocations) loop
    v_amount := (v_item ->> 'amount')::numeric;
    if v_amount is null or v_amount <= 0 then
      raise exception 'finance_receipt_invalid_allocation_amount: allocation amount must be positive, got %', v_amount
        using errcode = 'check_violation';
    end if;
    v_total := v_total + v_amount;
  end loop;

  if v_total > v_receipt.unapplied_amount then
    raise exception 'finance_receipt_over_allocation: total allocation % exceeds unapplied amount % for receipt %', v_total, v_receipt.unapplied_amount, p_receipt_id
      using errcode = 'check_violation';
  end if;

  insert into app.finance_receipt_allocation_batches (tenant_id, receipt_id, idempotency_key, created_by)
  values (v_receipt.tenant_id, p_receipt_id, p_idempotency_key, p_actor_label)
  returning * into v_batch;

  for v_item in select * from jsonb_array_elements(p_allocations) loop
    v_open_item_id := (v_item ->> 'arOpenItemId')::uuid;
    v_amount := (v_item ->> 'amount')::numeric;

    select * into v_open_item from app.finance_ar_open_items where id = v_open_item_id and tenant_id = v_receipt.tenant_id;
    if not found then
      raise exception 'finance_receipt_open_item_not_found: % is not a known AR open item for tenant %', v_open_item_id, v_receipt.tenant_id
        using errcode = 'no_data_found';
    end if;
    if v_open_item.customer_account_id <> v_receipt.customer_account_id then
      raise exception 'finance_receipt_customer_mismatch: AR open item % does not belong to receipt %''s own customer', v_open_item_id, p_receipt_id
        using errcode = 'check_violation';
    end if;
    if v_open_item.currency <> v_receipt.currency then
      raise exception 'finance_receipt_currency_mismatch: AR open item % is % but receipt % is %', v_open_item_id, v_open_item.currency, p_receipt_id, v_receipt.currency
        using errcode = 'check_violation';
    end if;

    perform app.apply_finance_ar_allocation(v_open_item_id, v_amount, 'receipt', p_receipt_id, p_idempotency_key || ':' || v_open_item_id::text, p_actor_auth_user_id, p_actor_label);

    insert into app.finance_receipt_allocations (tenant_id, receipt_id, batch_id, ar_open_item_id, amount, created_by)
    values (v_receipt.tenant_id, p_receipt_id, v_batch.id, v_open_item_id, v_amount, p_actor_label);
  end loop;

  -- FIN-202: debit cash for the total received; credit AR control for the
  -- same total -- one control-account line for the whole batch, matching
  -- app.finance_receipt_allocations' own already-established per-item
  -- lineage rows for open-item-level detail.
  perform app.post_finance_subledger_batch(
    v_receipt.tenant_id, v_receipt.company_id, 'receipt_allocation', v_batch.id, v_receipt.receipt_date, v_receipt.currency,
    jsonb_build_array(
      jsonb_build_object('postingMapKey', 'cash_default', 'direction', 'debit', 'amount', v_total),
      jsonb_build_object('postingMapKey', 'ar_control', 'direction', 'credit', 'amount', v_total)
    ),
    p_actor_auth_user_id, p_actor_label
  );

  update app.finance_receipts set allocated_amount = allocated_amount + v_total where id = p_receipt_id returning * into v_receipt;

  perform app.capture_audit_event(
    v_receipt.tenant_id, p_actor_auth_user_id, p_actor_label, 'allocate_finance_receipt',
    'app.finance_receipts', v_receipt.id, 'success', null, null, jsonb_build_object('total', v_total, 'batchId', v_batch.id)
  );

  return v_receipt;
end;
$$;

-- FIN-202 retrofit: FIN-200's own app.post_finance_vendor_bill now
-- additionally emits one balanced subledger batch at post time. Every other
-- line of this function's own body is byte-for-byte unchanged from
-- FIN-200's original.
create or replace function app.post_finance_vendor_bill(
  p_bill_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_vendor_bills
language plpgsql
as $$
declare
  v_bill app.finance_vendor_bills;
  v_period record;
  v_year integer;
  v_seq integer;
  v_number text;
  v_ap_item app.finance_ap_open_items;
  v_lines jsonb;
  v_tax_line app.finance_vendor_bill_lines;
  v_tax_rule app.finance_tax_rule_versions;
begin
  select * into v_bill from app.finance_vendor_bills where id = p_bill_id;
  if not found then
    raise exception 'finance_vendor_bill_not_found: %', p_bill_id using errcode = 'no_data_found';
  end if;
  if v_bill.status = 'posted' then
    return v_bill;
  end if;
  if not app.check_finance_vendor_bill_authority('Approve', v_bill.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_bill.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_bill.record_version <> p_expected_version then
    raise exception 'stale_version: bill % expected version % but found %', p_bill_id, p_expected_version, v_bill.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_bill.status <> 'approved' then
    raise exception 'finance_vendor_bill_not_approved: bill % is % not approved', p_bill_id, v_bill.status
      using errcode = 'check_violation';
  end if;

  select * into v_period from app.resolve_finance_period_for_date(v_bill.tenant_id, v_bill.company_id, v_bill.bill_date);
  if not found then
    raise exception 'finance_vendor_bill_period_not_found: no fiscal period covers %', v_bill.bill_date
      using errcode = 'no_data_found';
  end if;
  if not v_period.posting_eligible then
    raise exception 'finance_vendor_bill_period_not_open: fiscal period % for % is not open', v_period.period_code, v_bill.bill_date
      using errcode = 'check_violation';
  end if;

  v_year := extract(year from v_bill.bill_date)::integer;
  insert into app.finance_vendor_bill_number_counters (tenant_id, company_id, year, next_seq)
  values (v_bill.tenant_id, v_bill.company_id, v_year, 2)
  on conflict (tenant_id, coalesce(company_id, '00000000-0000-0000-0000-000000000000'::uuid), year)
  do update set next_seq = app.finance_vendor_bill_number_counters.next_seq + 1
  returning next_seq - 1 into v_seq;
  v_number := 'BILL-' || v_year::text || '-' || lpad(v_seq::text, 6, '0');

  select * into v_ap_item from app.post_finance_ap_open_item(
    v_bill.tenant_id, v_bill.company_id, v_bill.vendor_master_id, 'vendor_bill', v_bill.id,
    v_bill.currency, v_bill.total_amount, v_bill.bill_date, v_bill.due_date, p_actor_auth_user_id, p_actor_label
  );

  -- FIN-202: debit expense for the subtotal; debit each tax line's own
  -- governed recoverable account (or the input_tax_default posting-map key
  -- when none is configured); credit AP control for the full total.
  v_lines := '[]'::jsonb;
  if v_bill.subtotal_amount > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('postingMapKey', 'expense_default', 'direction', 'debit', 'amount', v_bill.subtotal_amount));
  end if;
  for v_tax_line in select * from app.finance_vendor_bill_lines where bill_id = p_bill_id and line_type = 'tax' and amount > 0 loop
    v_tax_rule := null;
    if v_tax_line.tax_rule_version_id is not null then
      select * into v_tax_rule from app.finance_tax_rule_versions where id = v_tax_line.tax_rule_version_id and recoverable_account_id is not null;
    end if;
    if v_tax_rule is not null then
      v_lines := v_lines || jsonb_build_array(jsonb_build_object('accountId', v_tax_rule.recoverable_account_id, 'direction', 'debit', 'amount', v_tax_line.amount));
    else
      v_lines := v_lines || jsonb_build_array(jsonb_build_object('postingMapKey', 'input_tax_default', 'direction', 'debit', 'amount', v_tax_line.amount));
    end if;
  end loop;
  v_lines := v_lines || jsonb_build_array(jsonb_build_object('postingMapKey', 'ap_control', 'direction', 'credit', 'amount', v_bill.total_amount, 'openItemType', 'ap_open_item', 'openItemId', v_ap_item.id));

  perform app.post_finance_subledger_batch(
    v_bill.tenant_id, v_bill.company_id, 'vendor_bill', v_bill.id, v_bill.bill_date, v_bill.currency,
    v_lines, p_actor_auth_user_id, p_actor_label
  );

  update app.finance_vendor_bills
    set status = 'posted', bill_number = v_number, posting_period_id = v_period.period_id, ap_open_item_id = v_ap_item.id,
        posted_by = p_actor_label, posted_at = now()
    where id = p_bill_id
    returning * into v_bill;

  perform app.capture_audit_event(
    v_bill.tenant_id, p_actor_auth_user_id, p_actor_label, 'post_finance_vendor_bill',
    'app.finance_vendor_bills', v_bill.id, 'success', null, null, to_jsonb(v_bill)
  );

  return v_bill;
end;
$$;

-- FIN-202 retrofit: FIN-201's own app.post_finance_settlement now
-- additionally emits one balanced subledger batch at post time. Every other
-- line of this function's own body is byte-for-byte unchanged from
-- FIN-201's original.
create or replace function app.post_finance_settlement(
  p_settlement_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_settlements
language plpgsql
as $$
declare
  v_settlement app.finance_settlements;
  v_period record;
  v_year integer;
  v_seq integer;
  v_number text;
  v_allocation app.finance_settlement_allocations;
  v_lines jsonb;
begin
  select * into v_settlement from app.finance_settlements where id = p_settlement_id;
  if not found then
    raise exception 'finance_settlement_not_found: %', p_settlement_id using errcode = 'no_data_found';
  end if;
  if v_settlement.status = 'posted' then
    return v_settlement;
  end if;
  if not app.check_finance_settlement_authority('Approve', v_settlement.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_settlement.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_settlement.record_version <> p_expected_version then
    raise exception 'stale_version: settlement % expected version % but found %', p_settlement_id, p_expected_version, v_settlement.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_settlement.status <> 'executed' then
    raise exception 'finance_settlement_not_executed: settlement % is % not executed', p_settlement_id, v_settlement.status
      using errcode = 'check_violation';
  end if;

  select * into v_period from app.resolve_finance_period_for_date(v_settlement.tenant_id, v_settlement.company_id, v_settlement.settlement_date);
  if not found then
    raise exception 'finance_settlement_period_not_found: no fiscal period covers %', v_settlement.settlement_date
      using errcode = 'no_data_found';
  end if;
  if not v_period.posting_eligible then
    raise exception 'finance_settlement_period_not_open: fiscal period % for % is not open', v_period.period_code, v_settlement.settlement_date
      using errcode = 'check_violation';
  end if;

  for v_allocation in select * from app.finance_settlement_allocations where settlement_id = p_settlement_id and status = 'applied' order by created_at asc loop
    perform app.apply_finance_ap_settlement(
      v_allocation.ap_open_item_id, v_allocation.amount, 'settlement', v_settlement.id,
      v_settlement.idempotency_key || ':' || v_allocation.ap_open_item_id::text, p_actor_auth_user_id, p_actor_label
    );
  end loop;

  -- FIN-202: debit AP control for the allocated total (plus a governed fee
  -- expense debit when a fee applies); credit cash for the full total.
  v_lines := jsonb_build_array(
    jsonb_build_object('postingMapKey', 'ap_control', 'direction', 'debit', 'amount', v_settlement.allocated_amount)
  );
  if v_settlement.fee_amount > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('postingMapKey', 'fee_expense_default', 'direction', 'debit', 'amount', v_settlement.fee_amount));
  end if;
  v_lines := v_lines || jsonb_build_array(jsonb_build_object('postingMapKey', 'cash_default', 'direction', 'credit', 'amount', v_settlement.total_amount));

  perform app.post_finance_subledger_batch(
    v_settlement.tenant_id, v_settlement.company_id, 'settlement', v_settlement.id, v_settlement.settlement_date, v_settlement.currency,
    v_lines, p_actor_auth_user_id, p_actor_label
  );

  v_year := extract(year from v_settlement.settlement_date)::integer;
  insert into app.finance_settlement_number_counters (tenant_id, company_id, year, next_seq)
  values (v_settlement.tenant_id, v_settlement.company_id, v_year, 2)
  on conflict (tenant_id, coalesce(company_id, '00000000-0000-0000-0000-000000000000'::uuid), year)
  do update set next_seq = app.finance_settlement_number_counters.next_seq + 1
  returning next_seq - 1 into v_seq;
  v_number := 'SETL-' || v_year::text || '-' || lpad(v_seq::text, 6, '0');

  update app.finance_settlements
    set status = 'posted', settlement_number = v_number, posting_period_id = v_period.period_id,
        posted_by = p_actor_label, posted_at = now()
    where id = p_settlement_id
    returning * into v_settlement;

  perform app.capture_audit_event(
    v_settlement.tenant_id, p_actor_auth_user_id, p_actor_label, 'post_finance_settlement',
    'app.finance_settlements', v_settlement.id, 'success', null, null, to_jsonb(v_settlement)
  );

  return v_settlement;
end;
$$;

alter table app.finance_subledger_batches enable row level security;
alter table app.finance_subledger_lines enable row level security;

create policy finance_subledger_batches_select_scoped on app.finance_subledger_batches
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

create policy finance_subledger_lines_select_scoped on app.finance_subledger_lines
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable
-- revoke of PostgreSQL's PUBLIC-execute default, the standing per-migration
-- convention since PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant select on app.finance_subledger_batches to authenticated, service_role;
grant select on app.finance_subledger_lines to authenticated, service_role;
grant insert, update, delete on app.finance_subledger_batches to service_role;
grant insert, update, delete on app.finance_subledger_lines to service_role;

grant execute on function app.check_finance_subledger_authority(text, uuid, uuid) to service_role;
grant execute on function app.resolve_finance_posting_map_account(uuid, text) to service_role;
grant execute on function app.post_finance_subledger_batch(uuid, uuid, text, uuid, date, text, jsonb, uuid, text) to authenticated, service_role;
grant execute on function app.preview_finance_subledger_posting(uuid, jsonb, uuid) to authenticated, service_role;
grant execute on function app.list_finance_subledger_batches(uuid, uuid, text, uuid) to authenticated, service_role;
grant execute on function app.get_finance_subledger_lines(uuid, uuid) to authenticated, service_role;
grant execute on function app.get_finance_subledger_reconciliation_summary(uuid, uuid) to authenticated, service_role;
