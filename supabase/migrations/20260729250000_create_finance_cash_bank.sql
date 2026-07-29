-- Finance capability FIN-211 (Cash and Bank Baseline, CG-S9-FIN-022)
-- Tenant/company bank and cash account control, staged statement import,
-- governed transaction matching and a reconciled cash position -- without
-- any unapproved payment-provider behavior (Prompt 211 section 24: "no
-- tenant-specific source fork, silent source re-entry, autonomous AI
-- financial posting"). No live bank-API adapter is built here: statement
-- ingestion is a caller-supplied, already-parsed batch of lines (the same
-- "staged idempotent import of a caller-supplied batch" idiom FIN-194's
-- own exchange-rate import already established), never a direct
-- third-party connection.
--
-- Bank account numbers are stored masked only (`account_number_last4`,
-- at most 4 characters) -- never a full account number, matching Prompt
-- 211 section 16's own "bank data/credentials are highly sensitive,
-- masked and server-only".
--
-- Ties into the one already-real cash-affecting GL activity in this
-- repository: FIN-198's own receipt allocation debits `cash_default` and
-- FIN-201's own settlement credits `cash_default` (the generic posting-map
-- key both already resolve via `app.resolve_finance_posting_map_account`,
-- confirmed by direct inspection of `20260729160000_create_finance_subledger.sql`).
-- `app.get_finance_cash_position` reconciles the statement-derived balance
-- against that identical `cash_default`-mapped account, the same
-- as-of-bounded-by-resolved-period-end technique FIN-209 already
-- established (`app.finance_subledger_batches` carries no direct business
-- posting-date column, only `posted_at`/`posting_period_id`).
--
-- Deduplication (Prompt 211 section 17/25): `finance_bank_transactions`
-- carries a unique `(bank_account_id, line_hash)` index -- a re-imported
-- or overlapping statement line is silently skipped, never double-posted
-- or double-counted, while the containing import batch itself is
-- idempotent on `(tenant_id, bank_account_id, source_reference)`.
--
-- Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration
-- carries its own explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app
-- FROM PUBLIC` statement before its final grants, the standing
-- per-migration convention since `PLT-118`.

create table app.finance_bank_accounts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  company_id uuid references app.org_units (id),
  account_name text not null,
  bank_name text not null,
  account_number_last4 text not null,
  currency text not null,
  gl_account_id uuid not null references app.finance_accounts (id),
  status text not null default 'active',
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint finance_bank_accounts_status_check check (status in ('active', 'inactive')),
  constraint finance_bank_accounts_currency_check check (currency ~ '^[A-Z]{3}$'),
  constraint finance_bank_accounts_last4_check check (account_number_last4 ~ '^[0-9A-Za-z]{1,4}$')
);

comment on table app.finance_bank_accounts is
  'FIN-211: one bank/cash account, masked to its own last 1-4 characters only -- the full account number is never stored. gl_account_id is the tenant''s own GL cash account (validated active/postable at create time); reconciliation against the shared cash_default posting-map key is a separate, tenant-configured concern.';

create index finance_bank_accounts_tenant_idx on app.finance_bank_accounts (tenant_id, status);

create function app.touch_finance_bank_account_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger finance_bank_accounts_touch_row
  before update on app.finance_bank_accounts
  for each row
  execute function app.touch_finance_bank_account_row();

create table app.finance_bank_statement_batches (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  bank_account_id uuid not null references app.finance_bank_accounts (id),
  source_reference text not null,
  line_count integer not null default 0,
  imported_by text,
  imported_at timestamptz not null default now(),
  constraint finance_bank_statement_batches_unique unique (tenant_id, bank_account_id, source_reference)
);

comment on table app.finance_bank_statement_batches is
  'FIN-211: one idempotent staged-import batch per (tenant, bank account, source_reference). line_count reflects only the lines this batch itself actually inserted -- a duplicate line silently skipped by finance_bank_transactions'' own unique index is not counted twice against any batch.';

create table app.finance_bank_transactions (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references app.finance_bank_statement_batches (id),
  tenant_id uuid not null references app.tenants (id),
  bank_account_id uuid not null references app.finance_bank_accounts (id),
  transaction_date date not null,
  direction text not null,
  amount numeric(14, 2) not null,
  reference text,
  description text,
  line_hash text not null,
  match_status text not null default 'unmatched',
  matched_source_type text,
  matched_source_id uuid,
  matched_by text,
  matched_at timestamptz,
  unmatch_reason text,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint finance_bank_transactions_direction_check check (direction in ('debit', 'credit')),
  constraint finance_bank_transactions_amount_check check (amount > 0),
  constraint finance_bank_transactions_match_status_check check (match_status in ('unmatched', 'matched')),
  constraint finance_bank_transactions_matched_source_check check (
    (match_status = 'matched' and matched_source_type is not null) or (match_status = 'unmatched')
  ),
  constraint finance_bank_transactions_dedup_unique unique (bank_account_id, line_hash)
);

comment on table app.finance_bank_transactions is
  'FIN-211: one deduplicated bank/cash statement line. line_hash is a deterministic digest of (bank_account_id, transaction_date, direction, amount, reference) -- the unique index on (bank_account_id, line_hash) is the real, database-enforced deduplication guarantee, not merely an application check. match_status=matched requires a matched_source_type (receipt/settlement/manual); governed unmatch (FIN:Approve) records unmatch_reason but preserves the row.';

create index finance_bank_transactions_account_date_idx on app.finance_bank_transactions (bank_account_id, transaction_date);
create index finance_bank_transactions_match_status_idx on app.finance_bank_transactions (tenant_id, match_status);

create function app.touch_finance_bank_transaction_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger finance_bank_transactions_touch_row
  before update on app.finance_bank_transactions
  for each row
  execute function app.touch_finance_bank_transaction_row();

create function app.check_finance_cash_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
as $$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'FIN', p_action)).allowed;
$$;

comment on function app.check_finance_cash_authority is
  'FIN-211: FIN:Approve gates bank-account creation and governed unmatch (Prompt 211 section 26: "approvers manage accounts/imports"); FIN:Edit gates statement import and match; FIN:View gates read/position.';

create function app.create_finance_bank_account(
  p_tenant_id uuid,
  p_company_id uuid,
  p_account_name text,
  p_bank_name text,
  p_account_number_last4 text,
  p_currency text,
  p_gl_account_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_bank_accounts
language plpgsql
as $$
declare
  v_account app.finance_bank_accounts;
  v_gl_account app.finance_accounts;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_cash_authority('Approve', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.validate_currency_code(p_currency) then
    raise exception 'finance_cash_unsupported_currency: % is not a registered, active currency', p_currency
      using errcode = 'check_violation';
  end if;

  select * into v_gl_account from app.finance_accounts where id = p_gl_account_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'finance_cash_gl_account_not_found: % is not a known account for tenant %', p_gl_account_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;
  if v_gl_account.status <> 'active' or not v_gl_account.is_postable then
    raise exception 'finance_cash_gl_account_not_postable: account % is not active/postable', v_gl_account.code
      using errcode = 'check_violation';
  end if;

  insert into app.finance_bank_accounts (tenant_id, company_id, account_name, bank_name, account_number_last4, currency, gl_account_id, created_by)
  values (p_tenant_id, p_company_id, p_account_name, p_bank_name, p_account_number_last4, p_currency, p_gl_account_id, p_actor_label)
  returning * into v_account;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_finance_bank_account',
    'app.finance_bank_accounts', v_account.id, 'success', null, null, to_jsonb(v_account)
  );

  return v_account;
end;
$$;

-- Staged, idempotent statement import (Prompt 211 section 21/25). Every
-- line is deduplicated by the table's own unique index; a skipped
-- duplicate never raises -- it is a silent, safe no-op, disclosed in the
-- returned batch's own line_count (which reflects only real inserts).
create function app.import_finance_bank_statement(
  p_tenant_id uuid,
  p_bank_account_id uuid,
  p_source_reference text,
  p_lines jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_bank_statement_batches
language plpgsql
as $$
declare
  v_batch app.finance_bank_statement_batches;
  v_account app.finance_bank_accounts;
  v_line jsonb;
  v_hash text;
  v_inserted integer := 0;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_cash_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_source_reference is null or length(trim(p_source_reference)) = 0 then
    raise exception 'finance_cash_source_reference_required: a non-empty source_reference is required' using errcode = 'check_violation';
  end if;

  select * into v_account from app.finance_bank_accounts where id = p_bank_account_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'finance_cash_bank_account_not_found: % is not a known bank account for tenant %', p_bank_account_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;

  select * into v_batch from app.finance_bank_statement_batches where tenant_id = p_tenant_id and bank_account_id = p_bank_account_id and source_reference = p_source_reference;
  if found then
    return v_batch;
  end if;

  if p_lines is null or jsonb_array_length(p_lines) = 0 then
    raise exception 'finance_cash_empty_statement: at least one line is required' using errcode = 'check_violation';
  end if;

  insert into app.finance_bank_statement_batches (tenant_id, bank_account_id, source_reference, imported_by)
  values (p_tenant_id, p_bank_account_id, p_source_reference, p_actor_label)
  returning * into v_batch;

  for v_line in select * from jsonb_array_elements(p_lines) loop
    if v_line ->> 'direction' not in ('debit', 'credit') then
      raise exception 'finance_cash_invalid_direction: % is not debit or credit', v_line ->> 'direction' using errcode = 'check_violation';
    end if;
    if (v_line ->> 'amount')::numeric <= 0 then
      raise exception 'finance_cash_invalid_amount: line amount must be positive, got %', v_line ->> 'amount' using errcode = 'check_violation';
    end if;

    v_hash := md5(p_bank_account_id::text || '|' || (v_line ->> 'transactionDate') || '|' || (v_line ->> 'direction') || '|' || (v_line ->> 'amount') || '|' || coalesce(v_line ->> 'reference', ''));

    insert into app.finance_bank_transactions (batch_id, tenant_id, bank_account_id, transaction_date, direction, amount, reference, description, line_hash)
    values (
      v_batch.id, p_tenant_id, p_bank_account_id, (v_line ->> 'transactionDate')::date, v_line ->> 'direction', (v_line ->> 'amount')::numeric,
      v_line ->> 'reference', v_line ->> 'description', v_hash
    )
    on conflict (bank_account_id, line_hash) do nothing;

    if found then
      v_inserted := v_inserted + 1;
    end if;
  end loop;

  update app.finance_bank_statement_batches set line_count = v_inserted where id = v_batch.id returning * into v_batch;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'import_finance_bank_statement',
    'app.finance_bank_statement_batches', v_batch.id, 'success', null, null,
    jsonb_build_object('sourceReference', p_source_reference, 'submittedLineCount', jsonb_array_length(p_lines), 'insertedLineCount', v_inserted)
  );

  return v_batch;
end;
$$;

create function app.match_finance_bank_transaction(
  p_transaction_id uuid,
  p_expected_version integer,
  p_matched_source_type text,
  p_matched_source_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_bank_transactions
language plpgsql
as $$
declare
  v_transaction app.finance_bank_transactions;
begin
  select * into v_transaction from app.finance_bank_transactions where id = p_transaction_id;
  if not found then
    raise exception 'finance_cash_transaction_not_found: %', p_transaction_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_cash_authority('Edit', v_transaction.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_transaction.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_transaction.record_version <> p_expected_version then
    raise exception 'stale_version: transaction % expected version % but found %', p_transaction_id, p_expected_version, v_transaction.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_matched_source_type not in ('receipt', 'settlement', 'manual') then
    raise exception 'finance_cash_invalid_match_source_type: % is not a supported match source type', p_matched_source_type
      using errcode = 'check_violation';
  end if;
  if v_transaction.match_status <> 'unmatched' then
    raise exception 'finance_cash_transaction_not_unmatched: transaction % is % not unmatched', p_transaction_id, v_transaction.match_status
      using errcode = 'check_violation';
  end if;

  update app.finance_bank_transactions
    set match_status = 'matched', matched_source_type = p_matched_source_type, matched_source_id = p_matched_source_id,
        matched_by = p_actor_label, matched_at = now(), unmatch_reason = null
    where id = p_transaction_id
    returning * into v_transaction;

  perform app.capture_audit_event(
    v_transaction.tenant_id, p_actor_auth_user_id, p_actor_label, 'match_finance_bank_transaction',
    'app.finance_bank_transactions', v_transaction.id, 'success', null, null, to_jsonb(v_transaction)
  );

  return v_transaction;
end;
$$;

-- Governed unmatch (Prompt 211 section 24: "automatic match... may still
-- require human governance"). FIN:Approve, mandatory reason.
create function app.unmatch_finance_bank_transaction(
  p_transaction_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_bank_transactions
language plpgsql
as $$
declare
  v_transaction app.finance_bank_transactions;
begin
  select * into v_transaction from app.finance_bank_transactions where id = p_transaction_id;
  if not found then
    raise exception 'finance_cash_transaction_not_found: %', p_transaction_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_cash_authority('Approve', v_transaction.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_transaction.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_transaction.record_version <> p_expected_version then
    raise exception 'stale_version: transaction % expected version % but found %', p_transaction_id, p_expected_version, v_transaction.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_cash_unmatch_reason_required: a non-empty reason is required' using errcode = 'check_violation';
  end if;
  if v_transaction.match_status <> 'matched' then
    raise exception 'finance_cash_transaction_not_matched: transaction % is % not matched', p_transaction_id, v_transaction.match_status
      using errcode = 'check_violation';
  end if;

  update app.finance_bank_transactions
    set match_status = 'unmatched', matched_source_type = null, matched_source_id = null, matched_by = null, matched_at = null, unmatch_reason = p_reason
    where id = p_transaction_id
    returning * into v_transaction;

  perform app.capture_audit_event(
    v_transaction.tenant_id, p_actor_auth_user_id, p_actor_label, 'unmatch_finance_bank_transaction',
    'app.finance_bank_transactions', v_transaction.id, 'success', p_reason, null, to_jsonb(v_transaction)
  );

  return v_transaction;
end;
$$;

-- Reconciled cash position (Prompt 211 section 5/21): the statement-
-- derived balance versus the shared cash_default-mapped GL account,
-- bounded as-of the same resolved-period-end technique FIN-209 already
-- established. A real, direct comparison, never an asserted-equal claim.
create function app.get_finance_cash_position(
  p_tenant_id uuid,
  p_bank_account_id uuid,
  p_as_of_date date,
  p_actor_auth_user_id uuid
)
returns table (
  bank_account_id uuid,
  currency text,
  statement_balance numeric,
  gl_balance numeric,
  variance_amount numeric
)
language plpgsql
stable
as $$
declare
  v_account app.finance_bank_accounts;
  v_statement_balance numeric(14, 2) := 0;
  v_gl_balance numeric(14, 2) := 0;
begin
  if not app.check_finance_cash_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_account from app.finance_bank_accounts where id = p_bank_account_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'finance_cash_bank_account_not_found: % is not a known bank account for tenant %', p_bank_account_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;

  select coalesce(sum(case when t.direction = 'debit' then t.amount else -t.amount end), 0) into v_statement_balance
    from app.finance_bank_transactions t
    where t.bank_account_id = p_bank_account_id and t.transaction_date <= p_as_of_date;

  select coalesce(sum(case when l.direction = 'debit' then l.amount else -l.amount end), 0) into v_gl_balance
    from app.finance_subledger_lines l
    join app.finance_subledger_batches b on b.id = l.batch_id
    join app.finance_fiscal_periods fp on fp.id = b.posting_period_id
    where b.tenant_id = p_tenant_id and l.account_id = v_account.gl_account_id and fp.end_date <= p_as_of_date;

  return query select v_account.id, v_account.currency, v_statement_balance, v_gl_balance, (v_gl_balance - v_statement_balance);
end;
$$;

create function app.list_finance_bank_accounts(p_tenant_id uuid, p_company_id uuid, p_actor_auth_user_id uuid)
returns setof app.finance_bank_accounts
language plpgsql
stable
as $$
begin
  if not app.check_finance_cash_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_bank_accounts
    where tenant_id = p_tenant_id and (p_company_id is null or company_id = p_company_id)
    order by created_at desc
    limit 200;
end;
$$;

create function app.list_finance_bank_transactions(p_tenant_id uuid, p_bank_account_id uuid, p_match_status text, p_actor_auth_user_id uuid)
returns setof app.finance_bank_transactions
language plpgsql
stable
as $$
begin
  if not app.check_finance_cash_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_bank_transactions
    where tenant_id = p_tenant_id
      and (p_bank_account_id is null or bank_account_id = p_bank_account_id)
      and (p_match_status is null or match_status = p_match_status)
    order by transaction_date desc
    limit 200;
end;
$$;

alter table app.finance_bank_accounts enable row level security;
alter table app.finance_bank_statement_batches enable row level security;
alter table app.finance_bank_transactions enable row level security;

create policy finance_bank_accounts_select_scoped on app.finance_bank_accounts
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

create policy finance_bank_statement_batches_select_scoped on app.finance_bank_statement_batches
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

create policy finance_bank_transactions_select_scoped on app.finance_bank_transactions
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable
-- revoke of PostgreSQL's PUBLIC-execute default, the standing per-migration
-- convention since PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant select on app.finance_bank_accounts to authenticated, service_role;
grant select on app.finance_bank_statement_batches to authenticated, service_role;
grant select on app.finance_bank_transactions to authenticated, service_role;
grant insert, update, delete on app.finance_bank_accounts to service_role;
grant insert, update, delete on app.finance_bank_statement_batches to service_role;
grant insert, update, delete on app.finance_bank_transactions to service_role;

grant execute on function app.touch_finance_bank_account_row() to service_role;
grant execute on function app.touch_finance_bank_transaction_row() to service_role;
grant execute on function app.check_finance_cash_authority(text, uuid, uuid) to service_role;
grant execute on function app.create_finance_bank_account(uuid, uuid, text, text, text, text, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.import_finance_bank_statement(uuid, uuid, text, jsonb, uuid, text) to authenticated, service_role;
grant execute on function app.match_finance_bank_transaction(uuid, integer, text, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.unmatch_finance_bank_transaction(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.get_finance_cash_position(uuid, uuid, date, uuid) to authenticated, service_role;
grant execute on function app.list_finance_bank_accounts(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.list_finance_bank_transactions(uuid, uuid, text, uuid) to authenticated, service_role;
