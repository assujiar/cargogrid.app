-- Finance capability FIN-198 (Receipt and Payment Allocation, CG-S9-FIN-009)
-- Customer receipt capture and exact, idempotent allocation to FIN-196's own
-- AR open items, with governed unapplied-cash and deallocation control.
--
-- Reuse decision (disclosed): every allocate/deallocate call delegates the
-- actual balance mutation to `FIN-196`'s own `app.apply_finance_ar_allocation`/
-- `app.reverse_finance_ar_allocation` directly -- this migration owns receipt
-- capture and the receipt-to-AR-item mapping only, never a second, competing
-- AR-balance mechanism. `app.apply_finance_ar_allocation` is itself row-locked
-- and idempotent per open item, so composing it here preserves FIN-196's own
-- "never over-allocate, even under concurrency" guarantee without
-- reimplementing it.
--
-- Idempotency (Prompt 198 section 24: "sum of allocations plus unapplied
-- amount equals receipt amount exactly ... under retry and concurrency"):
-- `app.finance_receipt_allocation_batches` mirrors `FIN-194`'s own staged-
-- import idempotency idiom (`unique (tenant_id, receipt_id, idempotency_key)`)
-- -- a retried `app.allocate_finance_receipt` call for the same batch key
-- returns the receipt unchanged rather than re-applying. Each individual
-- FIN-196 allocation call additionally carries its own derived idempotency
-- key (`batch idempotency_key || ':' || open_item_id`), so a partial retry
-- after a crash mid-batch cannot double-apply any single line either.
--
-- Unapplied cash (Prompt 198 section 21/22): `unapplied_amount` is a
-- generated column (`amount - allocated_amount`), never independently
-- mutable -- any remainder after allocation is simply left unapplied,
-- structurally, not tracked by a separate flag.
--
-- Deallocation is a governed reversal (`FIN:Approve`-gated, mandatory
-- reason), never a direct edit, per Prompt 198 section 24 and
-- `189_FINANCE_README.md` section 5.
--
-- GL posting scope disclosure (matching every prior FIN-19x checkpoint):
-- this migration captures `posting_period_id` and full source lineage but
-- creates zero GL journal line -- `FIN-202`/`FIN-203`'s own scope.
--
-- Bank/payment field sensitivity (Prompt 198 section 16: "bank/payment
-- fields are highly restricted"): general `FIN:View`/`FIN:Edit` gating
-- applies at this checkpoint, the same posture every prior FIN-19x table
-- has used; per-field masking/redaction beyond role gating is `FIN-214`'s
-- own dedicated scope (Financial Field-Level Security, `FINANCE_EXECUTION_INDEX.md`
-- row 214) -- disclosed, not silently promised here.
--
-- Money/decimal discipline: every amount column is `numeric(14,2)`, never
-- `float`; `unapplied_amount` is a generated column.
--
-- Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration carries
-- its own explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM
-- PUBLIC` statement before its final grants, the standing per-migration
-- convention since `PLT-118`.

create table app.finance_receipts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  company_id uuid references app.org_units (id),
  customer_account_id uuid not null references app.accounts (id),
  receipt_reference text,
  receipt_date date not null,
  payer_name text,
  bank_account_label text,
  currency text not null,
  amount numeric(14, 2) not null,
  allocated_amount numeric(14, 2) not null default 0,
  unapplied_amount numeric(14, 2) generated always as (amount - allocated_amount) stored,
  status text not null default 'captured',
  idempotency_key text not null,
  posting_period_id uuid references app.finance_fiscal_periods (id),
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint finance_receipts_status_check check (status in ('captured', 'void')),
  constraint finance_receipts_currency_check check (currency ~ '^[A-Z]{3}$'),
  constraint finance_receipts_amount_check check (amount > 0),
  constraint finance_receipts_allocated_amount_check check (allocated_amount >= 0 and allocated_amount <= amount),
  constraint finance_receipts_idempotency_unique unique (tenant_id, idempotency_key)
);

comment on table app.finance_receipts is
  'FIN-198: one captured customer receipt. unapplied_amount is a generated column (amount - allocated_amount), never independently mutable -- any remainder after allocation is simply left unapplied. Carries no GL journal line -- FIN-202/203''s own scope.';

create unique index finance_receipts_tenant_reference_unique on app.finance_receipts (tenant_id, receipt_reference) where receipt_reference is not null;
create index finance_receipts_tenant_customer_idx on app.finance_receipts (tenant_id, customer_account_id);
create index finance_receipts_tenant_status_idx on app.finance_receipts (tenant_id, status);

create function app.touch_finance_receipt_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger finance_receipts_touch_row
  before update on app.finance_receipts
  for each row
  execute function app.touch_finance_receipt_row();

-- Staged-batch idempotency (mirrors FIN-194's own staged-import idiom).
create table app.finance_receipt_allocation_batches (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  receipt_id uuid not null references app.finance_receipts (id),
  idempotency_key text not null,
  created_by text,
  created_at timestamptz not null default now(),
  constraint finance_receipt_allocation_batches_idempotency_unique unique (tenant_id, receipt_id, idempotency_key)
);

comment on table app.finance_receipt_allocation_batches is
  'FIN-198: one allocate-call batch per (tenant, receipt, idempotency_key) -- a retried app.allocate_finance_receipt call for the same key returns the receipt unchanged rather than re-applying.';

create table app.finance_receipt_allocations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  receipt_id uuid not null references app.finance_receipts (id),
  batch_id uuid not null references app.finance_receipt_allocation_batches (id),
  ar_open_item_id uuid not null references app.finance_ar_open_items (id),
  amount numeric(14, 2) not null,
  status text not null default 'applied',
  reason text,
  reversed_by text,
  reversed_at timestamptz,
  created_by text,
  created_at timestamptz not null default now(),
  constraint finance_receipt_allocations_status_check check (status in ('applied', 'reversed')),
  constraint finance_receipt_allocations_amount_check check (amount > 0)
);

comment on table app.finance_receipt_allocations is
  'FIN-198: one exact receipt-to-AR-open-item allocation line. The actual AR balance mutation is delegated to FIN-196''s own app.apply_finance_ar_allocation/app.reverse_finance_ar_allocation -- this row is the receipt-side lineage record.';

create index finance_receipt_allocations_receipt_idx on app.finance_receipt_allocations (receipt_id);
create index finance_receipt_allocations_open_item_idx on app.finance_receipt_allocations (ar_open_item_id);

create function app.check_finance_receipt_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
as $$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'FIN', p_action)).allowed;
$$;

comment on function app.check_finance_receipt_authority is
  'FIN-198: FIN:Edit gates capture/allocate; FIN:Approve gates governed deallocation (reversal); FIN:View gates read/candidate-search.';

create function app.capture_finance_receipt(
  p_tenant_id uuid,
  p_company_id uuid,
  p_customer_account_id uuid,
  p_receipt_reference text,
  p_receipt_date date,
  p_payer_name text,
  p_bank_account_label text,
  p_currency text,
  p_amount numeric,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_receipts
language plpgsql
as $$
declare
  v_receipt app.finance_receipts;
  v_period record;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_receipt_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: a non-empty idempotency_key is required' using errcode = 'check_violation';
  end if;

  select * into v_receipt from app.finance_receipts where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    return v_receipt;
  end if;

  if not exists (select 1 from app.accounts where id = p_customer_account_id and tenant_id = p_tenant_id) then
    raise exception 'finance_receipt_customer_not_found: % is not a known customer account for tenant %', p_customer_account_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;
  if not app.validate_currency_code(p_currency) then
    raise exception 'finance_receipt_unsupported_currency: % is not a registered, active currency', p_currency
      using errcode = 'check_violation';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'finance_receipt_invalid_amount: amount must be positive, got %', p_amount
      using errcode = 'check_violation';
  end if;

  select * into v_period from app.resolve_finance_period_for_date(p_tenant_id, p_company_id, p_receipt_date);
  if not found then
    raise exception 'finance_receipt_period_not_found: no fiscal period covers %', p_receipt_date
      using errcode = 'no_data_found';
  end if;
  if not v_period.posting_eligible then
    raise exception 'finance_receipt_period_not_open: fiscal period % for % is not open', v_period.period_code, p_receipt_date
      using errcode = 'check_violation';
  end if;

  begin
    insert into app.finance_receipts (
      tenant_id, company_id, customer_account_id, receipt_reference, receipt_date, payer_name, bank_account_label,
      currency, amount, posting_period_id, idempotency_key, created_by
    )
    values (
      p_tenant_id, p_company_id, p_customer_account_id, p_receipt_reference, p_receipt_date, p_payer_name, p_bank_account_label,
      p_currency, p_amount, v_period.period_id, p_idempotency_key, p_actor_label
    )
    returning * into v_receipt;
  exception
    when unique_violation then
      raise exception 'finance_receipt_duplicate_reference: bank reference % already exists for tenant %', p_receipt_reference, p_tenant_id
        using errcode = 'unique_violation';
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'capture_finance_receipt',
    'app.finance_receipts', v_receipt.id, 'success', null, null, to_jsonb(v_receipt)
  );

  return v_receipt;
end;
$$;

-- Suggested candidates: same customer, same currency, not fully paid, not
-- held, due-date ordered (Prompt 198 section 15's "suggested candidates").
create function app.search_finance_ar_candidates_for_receipt(p_receipt_id uuid, p_actor_auth_user_id uuid)
returns setof app.finance_ar_open_items
language plpgsql
stable
as $$
declare
  v_receipt app.finance_receipts;
begin
  select * into v_receipt from app.finance_receipts where id = p_receipt_id;
  if not found then
    raise exception 'finance_receipt_not_found: %', p_receipt_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_receipt_authority('View', v_receipt.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, v_receipt.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_ar_open_items
    where tenant_id = v_receipt.tenant_id
      and customer_account_id = v_receipt.customer_account_id
      and currency = v_receipt.currency
      and status <> 'paid'
      and not is_held
    order by due_date asc
    limit 200;
end;
$$;

-- The one idempotent allocate entry point (Prompt 198 section 21: "previews
-- exact allocations and posts once"). p_allocations is a jsonb array of
-- {"arOpenItemId": uuid, "amount": numeric}. Delegates every balance mutation
-- to FIN-196's own app.apply_finance_ar_allocation.
create function app.allocate_finance_receipt(
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

  update app.finance_receipts set allocated_amount = allocated_amount + v_total where id = p_receipt_id returning * into v_receipt;

  perform app.capture_audit_event(
    v_receipt.tenant_id, p_actor_auth_user_id, p_actor_label, 'allocate_finance_receipt',
    'app.finance_receipts', v_receipt.id, 'success', null, null, jsonb_build_object('total', v_total, 'batchId', v_batch.id)
  );

  return v_receipt;
end;
$$;

-- Governed deallocation (Prompt 198 section 24: "posted allocation
-- correction uses governed reversal/deallocation ... never direct edit").
-- FIN:Approve-gated, mandatory reason, delegates to FIN-196's own
-- app.reverse_finance_ar_allocation.
create function app.request_finance_receipt_deallocation(
  p_allocation_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_receipts
language plpgsql
as $$
declare
  v_allocation app.finance_receipt_allocations;
  v_receipt app.finance_receipts;
begin
  select * into v_allocation from app.finance_receipt_allocations where id = p_allocation_id for update;
  if not found then
    raise exception 'finance_receipt_allocation_not_found: %', p_allocation_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_receipt_authority('Approve', v_allocation.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_allocation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_receipt_deallocation_reason_required: a non-empty reason is required to reverse an allocation'
      using errcode = 'check_violation';
  end if;
  if v_allocation.status <> 'applied' then
    raise exception 'finance_receipt_allocation_not_applied: allocation % is % not applied', p_allocation_id, v_allocation.status
      using errcode = 'check_violation';
  end if;

  perform app.reverse_finance_ar_allocation(
    v_allocation.ar_open_item_id, v_allocation.amount, p_reason, 'receipt', v_allocation.receipt_id,
    'dealloc:' || v_allocation.id::text, p_actor_auth_user_id, p_actor_label
  );

  update app.finance_receipt_allocations set status = 'reversed', reason = p_reason, reversed_by = p_actor_label, reversed_at = now() where id = p_allocation_id;

  update app.finance_receipts set allocated_amount = allocated_amount - v_allocation.amount where id = v_allocation.receipt_id returning * into v_receipt;

  perform app.capture_audit_event(
    v_allocation.tenant_id, p_actor_auth_user_id, p_actor_label, 'request_finance_receipt_deallocation',
    'app.finance_receipt_allocations', v_allocation.id, 'success', p_reason, null, jsonb_build_object('amount', v_allocation.amount)
  );

  return v_receipt;
end;
$$;

create function app.list_finance_receipts(
  p_tenant_id uuid,
  p_company_id uuid,
  p_customer_account_id uuid,
  p_status text,
  p_actor_auth_user_id uuid
)
returns setof app.finance_receipts
language plpgsql
stable
as $$
begin
  if not app.check_finance_receipt_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_receipts
    where tenant_id = p_tenant_id
      and (p_company_id is null or company_id = p_company_id)
      and (p_customer_account_id is null or customer_account_id = p_customer_account_id)
      and (p_status is null or status = p_status)
    order by receipt_date desc
    limit 200;
end;
$$;

create function app.get_finance_receipt_allocations(p_receipt_id uuid, p_actor_auth_user_id uuid)
returns setof app.finance_receipt_allocations
language plpgsql
stable
as $$
declare
  v_receipt app.finance_receipts;
begin
  select * into v_receipt from app.finance_receipts where id = p_receipt_id;
  if not found then
    raise exception 'finance_receipt_not_found: %', p_receipt_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_receipt_authority('View', v_receipt.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, v_receipt.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_receipt_allocations where receipt_id = p_receipt_id order by created_at asc;
end;
$$;

alter table app.finance_receipts enable row level security;
alter table app.finance_receipt_allocation_batches enable row level security;
alter table app.finance_receipt_allocations enable row level security;

create policy finance_receipts_select_scoped on app.finance_receipts
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

create policy finance_receipt_allocation_batches_select_scoped on app.finance_receipt_allocation_batches
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

create policy finance_receipt_allocations_select_scoped on app.finance_receipt_allocations
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable
-- revoke of PostgreSQL's PUBLIC-execute default, the standing per-migration
-- convention since PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant select on app.finance_receipts to authenticated, service_role;
grant select on app.finance_receipt_allocation_batches to authenticated, service_role;
grant select on app.finance_receipt_allocations to authenticated, service_role;
grant insert, update, delete on app.finance_receipts to service_role;
grant insert, update, delete on app.finance_receipt_allocation_batches to service_role;
grant insert, update, delete on app.finance_receipt_allocations to service_role;

grant execute on function app.touch_finance_receipt_row() to service_role;
grant execute on function app.check_finance_receipt_authority(text, uuid, uuid) to service_role;
grant execute on function app.capture_finance_receipt(uuid, uuid, uuid, text, date, text, text, text, numeric, text, uuid, text) to authenticated, service_role;
grant execute on function app.search_finance_ar_candidates_for_receipt(uuid, uuid) to authenticated, service_role;
grant execute on function app.allocate_finance_receipt(uuid, text, jsonb, uuid, text) to authenticated, service_role;
grant execute on function app.request_finance_receipt_deallocation(uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.list_finance_receipts(uuid, uuid, uuid, text, uuid) to authenticated, service_role;
grant execute on function app.get_finance_receipt_allocations(uuid, uuid) to authenticated, service_role;
