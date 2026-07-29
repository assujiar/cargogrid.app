-- Finance capability FIN-201 (Settlement, CG-S9-FIN-012)
-- Governed vendor settlement: one payment instruction/record allocated across
-- one or more of FIN-199's own AP open items, with a distinct approval,
-- execution and posting lifecycle -- the AP-side mirror of FIN-198's own
-- Receipt and Payment Allocation, composed with FIN-199's own settlement
-- primitive rather than re-deriving AP balance mutation.
--
-- Reuse decision (disclosed, matching FIN-198's own "delegate, never
-- re-derive" discipline): `app.post_finance_settlement` is the one caller
-- `FIN-199`'s own `app.apply_finance_ap_settlement` explicitly documented
-- itself for ("The shared settlement primitive FIN-201 (Settlement) is
-- expected to call directly. Row-locked ... idempotent on (tenant_id,
-- open_item_id, idempotency_key)"). This migration owns settlement
-- preparation, the settlement-to-AP-item allocation mapping, and the
-- prepare -> submit -> approve -> execute -> post lifecycle only; it never
-- opens a second, competing AP-balance mechanism. Governed reversal
-- similarly composes `FIN-199`'s own `app.reverse_finance_ap_settlement`.
--
-- Execution vs. posting (Prompt 201 section 24: "Execution/posting are
-- distinct canonical states and retries cannot duplicate either"): approval
-- authorizes payment; execution records that a payment instruction actually
-- left the bank/payment channel (an external reference, optionally supplied
-- by treasury/accounting); posting is the one idempotent event that reduces
-- AP and reconciles cash by calling `app.apply_finance_ap_settlement` per
-- allocation line. No table row transitions both states at once, and a
-- retried `app.post_finance_settlement` call against an already-posted
-- settlement returns it unchanged, mirroring `FIN-200`'s own
-- `app.post_finance_vendor_bill` idempotency idiom exactly.
--
-- Idempotency (Prompt 201 section 24 / `189_FINANCE_README.md` section 5):
-- `finance_settlements` carries its own `idempotency_key`
-- (`unique (tenant_id, idempotency_key)`) at preparation time -- a retried
-- `app.prepare_finance_settlement` call for the same key returns the
-- settlement unchanged, mirroring `FIN-198`'s own `app.capture_finance_receipt`
-- idiom (settlement is treasury-initiated, not derived 1:1 from a single
-- upstream document the way a vendor bill is, so a natural-key unique
-- constraint does not apply here). Each allocation line's own AP-settlement
-- call additionally carries a derived idempotency key
-- (`idempotency_key || ':' || ap_open_item_id`), so a partial retry after a
-- crash mid-post cannot double-apply any single line either.
--
-- Exact allocation, decided once (Prompt 201 section 21: "prepares exact
-- allocations ... obtains approval, records controlled execution, and posts
-- settlement once"): allocations are supplied as a fixed set at preparation
-- time (mirrors FIN-197/FIN-200's own "prepare with lines in one call"
-- design, not FIN-198's own "capture now, allocate later" design --
-- deliberately different because a settlement's whole purpose is a single
-- governed payment run against a chosen set of open items, not an
-- open-ended cash pool). `allocated_amount` is the sum of those lines,
-- computed once at preparation and never independently mutable after.
--
-- Fee/withholding (Prompt 201 section 60/108, bounded MVP scope, the same
-- class of proportionate-effort decision `FIN-200`'s own bounded
-- basic-match variance recorded): `fee_amount` is one governed total per
-- settlement, not an itemized fee/withholding line ledger -- itemized
-- bank-fee/withholding-tax lines with their own tax-code lineage remain a
-- later capability's scope, disclosed rather than silently simulated here.
-- `total_amount = allocated_amount + fee_amount` is a generated column.
--
-- Currency/FX boundary (bounded MVP scope, matching FIN-198's own AR
-- allocation currency-match rule): a settlement's own currency must exactly
-- match every AP open item it allocates against; cross-currency settlement
-- with FX conversion is out of this checkpoint's bounded scope, disclosed.
--
-- Bank/payment field sensitivity (Prompt 201 section 16: "bank
-- credentials/details are server-only/masked"): `bank_account_label` is a
-- display label only (no raw account/routing number column exists on this
-- table), the identical posture FIN-198's own `finance_receipts.bank_account_label`
-- already uses; per-field masking/redaction beyond role gating remains
-- FIN-214's own dedicated scope (Financial Field-Level Security).
--
-- GL posting scope disclosure (matching every prior FIN-19x checkpoint):
-- this migration captures `posting_period_id` and full source lineage but
-- creates zero GL journal line -- FIN-202/FIN-203's own scope.
--
-- No autonomous AI/unapproved payment execution (Prompt 201 section 110 /
-- `189_FINANCE_README.md` section 5): every lifecycle transition requires an
-- authenticated, authority-checked human actor; no provider/bank adapter is
-- called by this migration at all (Prompt 201 section 14's own "external
-- payment adapter only when explicitly scoped" is out of this bounded
-- checkpoint).
--
-- Money/decimal discipline: every amount column is `numeric(14,2)`, never
-- `float`; `total_amount` is a generated column.
--
-- Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration carries
-- its own explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM
-- PUBLIC` statement before its final grants, the standing per-migration
-- convention since `PLT-118`.

create table app.finance_settlements (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  company_id uuid references app.org_units (id),
  settlement_number text,
  vendor_master_id uuid not null references app.master_records (id),
  payment_reference text,
  bank_account_label text,
  currency text not null,
  status text not null default 'draft',
  allocated_amount numeric(14, 2) not null default 0,
  fee_amount numeric(14, 2) not null default 0,
  total_amount numeric(14, 2) generated always as (allocated_amount + fee_amount) stored,
  settlement_date date not null,
  idempotency_key text not null,
  posting_period_id uuid references app.finance_fiscal_periods (id),
  execution_reference text,
  submitted_by text,
  submitted_at timestamptz,
  approved_by text,
  approved_at timestamptz,
  executed_by text,
  executed_at timestamptz,
  posted_by text,
  posted_at timestamptz,
  void_reason text,
  voided_by text,
  voided_at timestamptz,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint finance_settlements_status_check check (status in ('draft', 'submitted', 'approved', 'executed', 'posted', 'void', 'reversed')),
  constraint finance_settlements_currency_check check (currency ~ '^[A-Z]{3}$'),
  constraint finance_settlements_allocated_amount_check check (allocated_amount >= 0),
  constraint finance_settlements_fee_amount_check check (fee_amount >= 0),
  constraint finance_settlements_idempotency_unique unique (tenant_id, idempotency_key)
);

comment on table app.finance_settlements is
  'FIN-201: one governed vendor settlement (payment instruction/record) allocated across one or more FIN-199 AP open items. total_amount is a generated column. settlement_number is null until app.post_finance_settlement assigns one. Carries no GL journal line -- FIN-202/203''s own scope.';

create unique index finance_settlements_tenant_number_unique on app.finance_settlements (tenant_id, settlement_number) where settlement_number is not null;
create index finance_settlements_tenant_vendor_idx on app.finance_settlements (tenant_id, vendor_master_id);
create index finance_settlements_tenant_status_idx on app.finance_settlements (tenant_id, status);

create function app.touch_finance_settlement_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger finance_settlements_touch_row
  before update on app.finance_settlements
  for each row
  execute function app.touch_finance_settlement_row();

create table app.finance_settlement_allocations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  settlement_id uuid not null references app.finance_settlements (id),
  ap_open_item_id uuid not null references app.finance_ap_open_items (id),
  amount numeric(14, 2) not null,
  status text not null default 'applied',
  reason text,
  reversed_by text,
  reversed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint finance_settlement_allocations_status_check check (status in ('applied', 'reversed')),
  constraint finance_settlement_allocations_amount_check check (amount > 0),
  constraint finance_settlement_allocations_settlement_item_unique unique (settlement_id, ap_open_item_id)
);

comment on table app.finance_settlement_allocations is
  'FIN-201: one exact settlement-to-AP-open-item allocation line, decided once at preparation. The actual AP balance mutation is delegated to FIN-199''s own app.apply_finance_ap_settlement/app.reverse_finance_ap_settlement -- this row is the settlement-side lineage record.';

create index finance_settlement_allocations_settlement_idx on app.finance_settlement_allocations (settlement_id);
create index finance_settlement_allocations_open_item_idx on app.finance_settlement_allocations (ap_open_item_id);

create table app.finance_settlement_number_counters (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  company_id uuid,
  year integer not null,
  next_seq integer not null default 1
);

comment on table app.finance_settlement_number_counters is
  'FIN-201: a simple per-tenant/company/year sequential counter for settlement numbers, assigned only at post time -- mirrors FIN-200''s own app.finance_vendor_bill_number_counters exactly.';

create unique index finance_settlement_number_counters_scope_unique on app.finance_settlement_number_counters (
  tenant_id, coalesce(company_id, '00000000-0000-0000-0000-000000000000'::uuid), year
);

create function app.check_finance_settlement_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
as $$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'FIN', p_action)).allowed;
$$;

comment on function app.check_finance_settlement_authority is
  'FIN-201: FIN:Edit gates prepare/submit/discard; FIN:Approve gates approve/execute/post/reversal (this checkpoint has no separate treasury role, so execute and post are both FIN:Approve-gated -- disclosed bound, not a silent claim of separation-of-duties depth beyond what is built); FIN:View gates read.';

-- The one idempotent preparation entry point. p_allocations is a jsonb array
-- of {"apOpenItemId": uuid, "amount": numeric}, an exact fixed set decided
-- once (Prompt 201 section 21).
create function app.prepare_finance_settlement(
  p_tenant_id uuid,
  p_company_id uuid,
  p_vendor_master_id uuid,
  p_payment_reference text,
  p_bank_account_label text,
  p_currency text,
  p_settlement_date date,
  p_allocations jsonb,
  p_fee_amount numeric,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_settlements
language plpgsql
as $$
declare
  v_settlement app.finance_settlements;
  v_vendor app.master_records;
  v_item jsonb;
  v_open_item_id uuid;
  v_amount numeric;
  v_open_item app.finance_ap_open_items;
  v_total numeric := 0;
  v_fee numeric := coalesce(p_fee_amount, 0);
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_settlement_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: a non-empty idempotency_key is required' using errcode = 'check_violation';
  end if;

  select * into v_settlement from app.finance_settlements where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    return v_settlement;
  end if;

  select * into v_vendor from app.master_records
    where id = p_vendor_master_id and master_type_code = 'vendor' and canonical_status = 'active'
      and (tenant_id = p_tenant_id or tenant_id is null);
  if not found then
    raise exception 'finance_settlement_vendor_not_found: % is not a known active vendor reference for tenant %', p_vendor_master_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;

  if not app.validate_currency_code(p_currency) then
    raise exception 'finance_settlement_unsupported_currency: % is not a registered, active currency', p_currency
      using errcode = 'check_violation';
  end if;
  if v_fee < 0 then
    raise exception 'finance_settlement_invalid_fee: fee amount must not be negative, got %', v_fee
      using errcode = 'check_violation';
  end if;
  if p_allocations is null or jsonb_array_length(p_allocations) = 0 then
    raise exception 'finance_settlement_empty_allocation: at least one AP allocation line is required' using errcode = 'check_violation';
  end if;

  for v_item in select * from jsonb_array_elements(p_allocations) loop
    v_open_item_id := (v_item ->> 'apOpenItemId')::uuid;
    v_amount := (v_item ->> 'amount')::numeric;
    if v_amount is null or v_amount <= 0 then
      raise exception 'finance_settlement_invalid_allocation_amount: allocation amount must be positive, got %', v_amount
        using errcode = 'check_violation';
    end if;

    select * into v_open_item from app.finance_ap_open_items where id = v_open_item_id and tenant_id = p_tenant_id;
    if not found then
      raise exception 'finance_settlement_open_item_not_found: % is not a known AP open item for tenant %', v_open_item_id, p_tenant_id
        using errcode = 'no_data_found';
    end if;
    if v_open_item.vendor_master_id <> p_vendor_master_id then
      raise exception 'finance_settlement_vendor_mismatch: AP open item % does not belong to vendor %', v_open_item_id, p_vendor_master_id
        using errcode = 'check_violation';
    end if;
    if v_open_item.currency <> p_currency then
      raise exception 'finance_settlement_currency_mismatch: AP open item % is % but settlement is %', v_open_item_id, v_open_item.currency, p_currency
        using errcode = 'check_violation';
    end if;
    if v_open_item.is_held then
      raise exception 'finance_settlement_open_item_held: AP open item % is held and cannot be settled', v_open_item_id
        using errcode = 'check_violation';
    end if;
    if v_open_item.status = 'settled' then
      raise exception 'finance_settlement_open_item_already_settled: AP open item % is already fully settled', v_open_item_id
        using errcode = 'check_violation';
    end if;
    if v_amount > v_open_item.open_amount then
      raise exception 'finance_settlement_over_allocation: allocation % exceeds open amount % for AP open item %', v_amount, v_open_item.open_amount, v_open_item_id
        using errcode = 'check_violation';
    end if;

    v_total := v_total + v_amount;
  end loop;

  insert into app.finance_settlements (
    tenant_id, company_id, vendor_master_id, payment_reference, bank_account_label,
    currency, allocated_amount, fee_amount, settlement_date, idempotency_key, created_by
  )
  values (
    p_tenant_id, p_company_id, p_vendor_master_id, p_payment_reference, p_bank_account_label,
    p_currency, v_total, v_fee, p_settlement_date, p_idempotency_key, p_actor_label
  )
  returning * into v_settlement;

  for v_item in select * from jsonb_array_elements(p_allocations) loop
    insert into app.finance_settlement_allocations (tenant_id, settlement_id, ap_open_item_id, amount)
    values (p_tenant_id, v_settlement.id, (v_item ->> 'apOpenItemId')::uuid, (v_item ->> 'amount')::numeric);
  end loop;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'prepare_finance_settlement',
    'app.finance_settlements', v_settlement.id, 'success', null, null, to_jsonb(v_settlement)
  );

  return v_settlement;
end;
$$;

create function app.submit_finance_settlement_for_approval(
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
begin
  select * into v_settlement from app.finance_settlements where id = p_settlement_id;
  if not found then
    raise exception 'finance_settlement_not_found: %', p_settlement_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_settlement_authority('Edit', v_settlement.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_settlement.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_settlement.record_version <> p_expected_version then
    raise exception 'stale_version: settlement % expected version % but found %', p_settlement_id, p_expected_version, v_settlement.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_settlement.status <> 'draft' then
    raise exception 'finance_settlement_not_draft: settlement % is % not draft', p_settlement_id, v_settlement.status
      using errcode = 'check_violation';
  end if;

  update app.finance_settlements set status = 'submitted', submitted_by = p_actor_label, submitted_at = now() where id = p_settlement_id returning * into v_settlement;

  perform app.capture_audit_event(
    v_settlement.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_finance_settlement_for_approval',
    'app.finance_settlements', v_settlement.id, 'success', null, null, to_jsonb(v_settlement)
  );

  return v_settlement;
end;
$$;

create function app.discard_finance_settlement_draft(
  p_settlement_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_settlements
language plpgsql
as $$
declare
  v_settlement app.finance_settlements;
begin
  select * into v_settlement from app.finance_settlements where id = p_settlement_id;
  if not found then
    raise exception 'finance_settlement_not_found: %', p_settlement_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_settlement_authority('Edit', v_settlement.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_settlement.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_settlement.record_version <> p_expected_version then
    raise exception 'stale_version: settlement % expected version % but found %', p_settlement_id, p_expected_version, v_settlement.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_settlement.status not in ('draft', 'submitted') then
    raise exception 'finance_settlement_not_cancellable: settlement % is %, only a draft or submitted settlement may be discarded', p_settlement_id, v_settlement.status
      using errcode = 'check_violation';
  end if;

  update app.finance_settlements set status = 'void', void_reason = p_reason, voided_by = p_actor_label, voided_at = now() where id = p_settlement_id returning * into v_settlement;

  perform app.capture_audit_event(
    v_settlement.tenant_id, p_actor_auth_user_id, p_actor_label, 'discard_finance_settlement_draft',
    'app.finance_settlements', v_settlement.id, 'success', p_reason, null, to_jsonb(v_settlement)
  );

  return v_settlement;
end;
$$;

create function app.approve_finance_settlement(
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
begin
  select * into v_settlement from app.finance_settlements where id = p_settlement_id;
  if not found then
    raise exception 'finance_settlement_not_found: %', p_settlement_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_settlement_authority('Approve', v_settlement.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_settlement.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_settlement.record_version <> p_expected_version then
    raise exception 'stale_version: settlement % expected version % but found %', p_settlement_id, p_expected_version, v_settlement.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_settlement.status <> 'submitted' then
    raise exception 'finance_settlement_not_submitted: settlement % is % not submitted', p_settlement_id, v_settlement.status
      using errcode = 'check_violation';
  end if;

  update app.finance_settlements set status = 'approved', approved_by = p_actor_label, approved_at = now() where id = p_settlement_id returning * into v_settlement;

  perform app.capture_audit_event(
    v_settlement.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_finance_settlement',
    'app.finance_settlements', v_settlement.id, 'success', null, null, to_jsonb(v_settlement)
  );

  return v_settlement;
end;
$$;

-- Records that an approved payment instruction was actually sent through the
-- bank/payment channel -- a distinct canonical state from posting (Prompt
-- 201 section 24). Carries zero AP/cash effect by itself.
create function app.execute_finance_settlement(
  p_settlement_id uuid,
  p_expected_version integer,
  p_execution_reference text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_settlements
language plpgsql
as $$
declare
  v_settlement app.finance_settlements;
begin
  select * into v_settlement from app.finance_settlements where id = p_settlement_id;
  if not found then
    raise exception 'finance_settlement_not_found: %', p_settlement_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_settlement_authority('Approve', v_settlement.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_settlement.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_settlement.record_version <> p_expected_version then
    raise exception 'stale_version: settlement % expected version % but found %', p_settlement_id, p_expected_version, v_settlement.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_settlement.status <> 'approved' then
    raise exception 'finance_settlement_not_approved: settlement % is % not approved', p_settlement_id, v_settlement.status
      using errcode = 'check_violation';
  end if;

  update app.finance_settlements
    set status = 'executed', execution_reference = p_execution_reference, executed_by = p_actor_label, executed_at = now()
    where id = p_settlement_id
    returning * into v_settlement;

  perform app.capture_audit_event(
    v_settlement.tenant_id, p_actor_auth_user_id, p_actor_label, 'execute_finance_settlement',
    'app.finance_settlements', v_settlement.id, 'success', null, null, to_jsonb(v_settlement)
  );

  return v_settlement;
end;
$$;

-- One idempotent post (mirrors FIN-200's own app.post_finance_vendor_bill
-- exactly). A retried call against an already-posted settlement returns it
-- unchanged. Composes FIN-199's own app.apply_finance_ap_settlement, never a
-- second AP-balance mechanism.
create function app.post_finance_settlement(
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

-- Governed reversal (Prompt 201 section 24: "posted correction uses governed
-- reversal/adjustment, never direct edit"). FIN:Approve-gated, mandatory
-- reason, delegates each allocation's own balance reversal to FIN-199's own
-- app.reverse_finance_ap_settlement.
create function app.request_finance_settlement_reversal(
  p_settlement_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_settlements
language plpgsql
as $$
declare
  v_settlement app.finance_settlements;
  v_allocation app.finance_settlement_allocations;
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
$$;

create function app.list_finance_settlements(
  p_tenant_id uuid,
  p_company_id uuid,
  p_vendor_master_id uuid,
  p_status text,
  p_actor_auth_user_id uuid
)
returns setof app.finance_settlements
language plpgsql
stable
as $$
begin
  if not app.check_finance_settlement_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_settlements
    where tenant_id = p_tenant_id
      and (p_company_id is null or company_id = p_company_id)
      and (p_vendor_master_id is null or vendor_master_id = p_vendor_master_id)
      and (p_status is null or status = p_status)
    order by created_at desc
    limit 200;
end;
$$;

create function app.get_finance_settlement_allocations(p_settlement_id uuid, p_actor_auth_user_id uuid)
returns setof app.finance_settlement_allocations
language plpgsql
stable
as $$
declare
  v_settlement app.finance_settlements;
begin
  select * into v_settlement from app.finance_settlements where id = p_settlement_id;
  if not found then
    raise exception 'finance_settlement_not_found: %', p_settlement_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_settlement_authority('View', v_settlement.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, v_settlement.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_settlement_allocations where settlement_id = p_settlement_id order by created_at asc;
end;
$$;

-- Suggested candidates: same vendor, same currency, not fully settled, not
-- held, due-date ordered (mirrors FIN-198's own
-- app.search_finance_ar_candidates_for_receipt).
create function app.search_finance_ap_candidates_for_settlement(p_tenant_id uuid, p_vendor_master_id uuid, p_currency text, p_actor_auth_user_id uuid)
returns setof app.finance_ap_open_items
language plpgsql
stable
as $$
begin
  if not app.check_finance_settlement_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_ap_open_items
    where tenant_id = p_tenant_id
      and vendor_master_id = p_vendor_master_id
      and currency = p_currency
      and status <> 'settled'
      and not is_held
    order by due_date asc
    limit 200;
end;
$$;

alter table app.finance_settlements enable row level security;
alter table app.finance_settlement_allocations enable row level security;

create policy finance_settlements_select_scoped on app.finance_settlements
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

create policy finance_settlement_allocations_select_scoped on app.finance_settlement_allocations
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable
-- revoke of PostgreSQL's PUBLIC-execute default, the standing per-migration
-- convention since PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant select on app.finance_settlements to authenticated, service_role;
grant select on app.finance_settlement_allocations to authenticated, service_role;
grant insert, update, delete on app.finance_settlements to service_role;
grant insert, update, delete on app.finance_settlement_allocations to service_role;
grant select, insert, update on app.finance_settlement_number_counters to service_role;

grant execute on function app.touch_finance_settlement_row() to service_role;
grant execute on function app.check_finance_settlement_authority(text, uuid, uuid) to service_role;
grant execute on function app.prepare_finance_settlement(uuid, uuid, uuid, text, text, text, date, jsonb, numeric, text, uuid, text) to authenticated, service_role;
grant execute on function app.submit_finance_settlement_for_approval(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.discard_finance_settlement_draft(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.approve_finance_settlement(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.execute_finance_settlement(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.post_finance_settlement(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.request_finance_settlement_reversal(uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.list_finance_settlements(uuid, uuid, uuid, text, uuid) to authenticated, service_role;
grant execute on function app.get_finance_settlement_allocations(uuid, uuid) to authenticated, service_role;
grant execute on function app.search_finance_ap_candidates_for_settlement(uuid, uuid, text, uuid) to authenticated, service_role;
