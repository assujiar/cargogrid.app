-- Finance capability FIN-199 (Accounts Payable Subledger, CG-S9-FIN-010)
-- Source-linked AP open items and their balance lifecycle -- the vendor-side
-- mirror of FIN-196's own Accounts Receivable design. AP is created only by
-- a controlled bill posting, never ad hoc UI entry, except an approved
-- opening-balance path (Prompt 199 section 24).
--
-- Dependency-order disclosure (matching every prior FIN checkpoint's own
-- discipline): `FIN-200` (Vendor Bill) does not exist yet at this checkpoint
-- -- per `189_FINANCE_README.md` section 4, Accounts Payable (199) precedes
-- Vendor Bill (200). This migration therefore builds the AP open-item
-- subledger primitive generically (`source_document_type` bounded to
-- `vendor_bill`/`opening_balance`), the exact same "build the shared
-- primitive first, the next capability becomes its first real caller"
-- pattern `FIN-196`'s own migration already established for its AR
-- counterpart. `FIN-200`'s own `app.post_finance_vendor_bill` is expected to
-- call `app.post_finance_ap_open_item` directly once it exists.
--
-- Vendor reference boundary (Prompt 199 section 24: "Phase 4 uses available
-- verified vendor references; full onboarding/PO/contract/performance
-- remains Step 11"): `vendor_master_id` references `app.master_records`
-- (`master_type_code = 'vendor'`, registered by `OPS-172`), the exact same
-- vendor identity `app.shipment_actual_cost_components.vendor_id`
-- (`OPS-178`) already references -- no new vendor-identity table, no
-- Procurement vendor-lifecycle scope smuggled in.
--
-- GL posting scope disclosure: per `189_FINANCE_README.md` section 4, AR/AP
-- and Source Subledgers (`FIN-202`) and the Double-Entry Journal (`FIN-203`)
-- are later capabilities than this one. This migration captures a
-- `posting_period_id` (resolved via `FIN-193`'s own
-- `app.resolve_finance_period_for_date`, rejecting a date with no open
-- period) and full source lineage, but creates zero GL journal line.
--
-- Status is a pure function of balance (`open`/`partial`/`settled`),
-- computed by the settlement functions themselves, never accepted from a
-- caller. Collection/payment hold is an orthogonal flag (`is_held`), not a
-- status value -- mirrors `FIN-196`'s own AR design exactly. Posted-item
-- correction to a genuinely wrong `original_amount` remains `FIN-206`'s own
-- scope; this migration exposes no direct-edit or void path for a posted
-- open item.
--
-- Money/decimal discipline: every amount column is `numeric(14,2)`, never
-- `float`/`real`. `open_amount` is a generated column
-- (`original_amount - settled_amount`), always exactly reconstructible,
-- never independently mutable.
--
-- Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration carries
-- its own explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM
-- PUBLIC` statement before its final grants, the standing per-migration
-- convention since `PLT-118`.

create table app.finance_ap_open_items (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  company_id uuid references app.org_units (id),
  vendor_master_id uuid not null references app.master_records (id),
  source_document_type text not null,
  source_document_id uuid not null,
  currency text not null,
  original_amount numeric(14, 2) not null,
  settled_amount numeric(14, 2) not null default 0,
  open_amount numeric(14, 2) generated always as (original_amount - settled_amount) stored,
  status text not null default 'open',
  is_held boolean not null default false,
  hold_reason text,
  held_by text,
  held_at timestamptz,
  released_by text,
  released_at timestamptz,
  bill_date date not null,
  due_date date not null,
  posting_period_id uuid references app.finance_fiscal_periods (id),
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint finance_ap_open_items_source_type_check check (source_document_type in ('vendor_bill', 'opening_balance')),
  constraint finance_ap_open_items_status_check check (status in ('open', 'partial', 'settled')),
  constraint finance_ap_open_items_currency_check check (currency ~ '^[A-Z]{3}$'),
  constraint finance_ap_open_items_original_amount_check check (original_amount > 0),
  constraint finance_ap_open_items_settled_amount_check check (settled_amount >= 0 and settled_amount <= original_amount),
  constraint finance_ap_open_items_due_date_check check (due_date >= bill_date),
  constraint finance_ap_open_items_source_unique unique (tenant_id, source_document_type, source_document_id)
);

comment on table app.finance_ap_open_items is
  'FIN-199: one idempotent AP open item per source document (unique on tenant/source_document_type/source_document_id) -- the vendor-side mirror of FIN-196''s own finance_ar_open_items. open_amount is a generated column, never independently mutable. status is a pure function of balance. Carries no GL journal line -- FIN-202/203''s own scope.';

create index finance_ap_open_items_tenant_vendor_idx on app.finance_ap_open_items (tenant_id, vendor_master_id);
create index finance_ap_open_items_tenant_status_idx on app.finance_ap_open_items (tenant_id, status);
create index finance_ap_open_items_tenant_due_date_idx on app.finance_ap_open_items (tenant_id, due_date);
create index finance_ap_open_items_company_idx on app.finance_ap_open_items (company_id);

create function app.touch_finance_ap_open_item_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger finance_ap_open_items_touch_row
  before update on app.finance_ap_open_items
  for each row
  execute function app.touch_finance_ap_open_item_row();

create table app.finance_ap_open_item_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  open_item_id uuid not null references app.finance_ap_open_items (id),
  event_type text not null,
  amount_delta numeric(14, 2),
  reason text,
  source_type text,
  source_id uuid,
  idempotency_key text,
  actor_auth_user_id uuid,
  actor_label text,
  created_at timestamptz not null default now(),
  constraint finance_ap_open_item_events_event_type_check check (event_type in ('created', 'settled', 'unsettled', 'hold_placed', 'hold_released')),
  constraint finance_ap_open_item_events_idempotency_unique unique (tenant_id, open_item_id, idempotency_key)
);

comment on table app.finance_ap_open_item_events is
  'FIN-199: append-only AP open-item audit trail, mirrors FIN-196''s own finance_ar_open_item_events. idempotency_key (nullable, unique per open item when present) guards app.apply_finance_ap_settlement/app.reverse_finance_ap_settlement replay.';

create index finance_ap_open_item_events_open_item_idx on app.finance_ap_open_item_events (open_item_id, created_at);

create function app.check_finance_ap_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
as $$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'FIN', p_action)).allowed;
$$;

comment on function app.check_finance_ap_authority is
  'FIN-199: FIN:Edit gates vendor-bill-sourced posting/hold/settlement; FIN:Approve gates opening-balance posting/hold-release/governed unsettlement; FIN:View gates read -- mirrors FIN-196''s own authority mapping exactly.';

create function app.post_finance_ap_open_item(
  p_tenant_id uuid,
  p_company_id uuid,
  p_vendor_master_id uuid,
  p_source_document_type text,
  p_source_document_id uuid,
  p_currency text,
  p_original_amount numeric,
  p_bill_date date,
  p_due_date date,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_ap_open_items
language plpgsql
as $$
declare
  v_item app.finance_ap_open_items;
  v_vendor app.master_records;
  v_period record;
  v_required_action text;
begin
  if p_source_document_type not in ('vendor_bill', 'opening_balance') then
    raise exception 'finance_ap_unsupported_source_type: % is not a supported AP source document type', p_source_document_type
      using errcode = 'check_violation';
  end if;
  v_required_action := case when p_source_document_type = 'opening_balance' then 'Approve' else 'Edit' end;

  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_ap_authority(v_required_action, p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:% for tenant %', p_actor_auth_user_id, v_required_action, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_item from app.finance_ap_open_items
    where tenant_id = p_tenant_id and source_document_type = p_source_document_type and source_document_id = p_source_document_id;
  if found then
    return v_item;
  end if;

  select * into v_vendor from app.master_records
    where id = p_vendor_master_id and master_type_code = 'vendor' and canonical_status = 'active'
      and (tenant_id = p_tenant_id or tenant_id is null);
  if not found then
    raise exception 'finance_ap_vendor_not_found: % is not a known active vendor reference for tenant %', p_vendor_master_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;

  if not app.validate_currency_code(p_currency) then
    raise exception 'finance_ap_unsupported_currency: % is not a registered, active currency', p_currency
      using errcode = 'check_violation';
  end if;
  if p_original_amount is null or p_original_amount <= 0 then
    raise exception 'finance_ap_invalid_amount: original amount must be positive, got %', p_original_amount
      using errcode = 'check_violation';
  end if;
  if p_due_date < p_bill_date then
    raise exception 'finance_ap_invalid_due_date: due date % is before bill date %', p_due_date, p_bill_date
      using errcode = 'check_violation';
  end if;

  select * into v_period from app.resolve_finance_period_for_date(p_tenant_id, p_company_id, p_bill_date);
  if not found then
    raise exception 'finance_ap_period_not_found: no fiscal period covers %', p_bill_date
      using errcode = 'no_data_found';
  end if;
  if not v_period.posting_eligible then
    raise exception 'finance_ap_period_not_open: fiscal period % for % is not open', v_period.period_code, p_bill_date
      using errcode = 'check_violation';
  end if;

  begin
    insert into app.finance_ap_open_items (
      tenant_id, company_id, vendor_master_id, source_document_type, source_document_id,
      currency, original_amount, bill_date, due_date, posting_period_id, created_by
    )
    values (
      p_tenant_id, p_company_id, p_vendor_master_id, p_source_document_type, p_source_document_id,
      p_currency, p_original_amount, p_bill_date, p_due_date, v_period.period_id, p_actor_label
    )
    returning * into v_item;
  exception
    when unique_violation then
      select * into v_item from app.finance_ap_open_items
        where tenant_id = p_tenant_id and source_document_type = p_source_document_type and source_document_id = p_source_document_id;
      return v_item;
  end;

  insert into app.finance_ap_open_item_events (tenant_id, open_item_id, event_type, amount_delta, source_type, source_id, actor_auth_user_id, actor_label)
  values (p_tenant_id, v_item.id, 'created', p_original_amount, p_source_document_type, p_source_document_id, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'post_finance_ap_open_item',
    'app.finance_ap_open_items', v_item.id, 'success', null, null, to_jsonb(v_item)
  );

  return v_item;
end;
$$;

create function app.place_finance_ap_hold(
  p_open_item_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_ap_open_items
language plpgsql
as $$
declare
  v_item app.finance_ap_open_items;
begin
  select * into v_item from app.finance_ap_open_items where id = p_open_item_id;
  if not found then
    raise exception 'finance_ap_open_item_not_found: %', p_open_item_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_ap_authority('Edit', v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_item.record_version <> p_expected_version then
    raise exception 'stale_version: open item % expected version % but found %', p_open_item_id, p_expected_version, v_item.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_ap_hold_reason_required: a non-empty reason is required to place a hold'
      using errcode = 'check_violation';
  end if;
  if v_item.is_held then
    raise exception 'finance_ap_already_held: open item % is already held', p_open_item_id
      using errcode = 'check_violation';
  end if;

  update app.finance_ap_open_items
    set is_held = true, hold_reason = p_reason, held_by = p_actor_label, held_at = now(), released_by = null, released_at = null
    where id = p_open_item_id
    returning * into v_item;

  insert into app.finance_ap_open_item_events (tenant_id, open_item_id, event_type, reason, actor_auth_user_id, actor_label)
  values (v_item.tenant_id, v_item.id, 'hold_placed', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'place_finance_ap_hold',
    'app.finance_ap_open_items', v_item.id, 'success', p_reason, null, to_jsonb(v_item)
  );

  return v_item;
end;
$$;

create function app.release_finance_ap_hold(
  p_open_item_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_ap_open_items
language plpgsql
as $$
declare
  v_item app.finance_ap_open_items;
begin
  select * into v_item from app.finance_ap_open_items where id = p_open_item_id;
  if not found then
    raise exception 'finance_ap_open_item_not_found: %', p_open_item_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_ap_authority('Approve', v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_item.record_version <> p_expected_version then
    raise exception 'stale_version: open item % expected version % but found %', p_open_item_id, p_expected_version, v_item.record_version
      using errcode = 'serialization_failure';
  end if;
  if not v_item.is_held then
    raise exception 'finance_ap_not_held: open item % is not currently held', p_open_item_id
      using errcode = 'check_violation';
  end if;

  update app.finance_ap_open_items
    set is_held = false, released_by = p_actor_label, released_at = now()
    where id = p_open_item_id
    returning * into v_item;

  insert into app.finance_ap_open_item_events (tenant_id, open_item_id, event_type, reason, actor_auth_user_id, actor_label)
  values (v_item.tenant_id, v_item.id, 'hold_released', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'release_finance_ap_hold',
    'app.finance_ap_open_items', v_item.id, 'success', p_reason, null, to_jsonb(v_item)
  );

  return v_item;
end;
$$;

-- The shared settlement primitive FIN-201 (Settlement) is expected to call
-- directly. Row-locked so concurrent settlement attempts serialize rather
-- than both reading a stale open_amount. Idempotent on
-- (tenant_id, open_item_id, idempotency_key).
create function app.apply_finance_ap_settlement(
  p_open_item_id uuid,
  p_amount numeric,
  p_source_type text,
  p_source_id uuid,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_ap_open_items
language plpgsql
as $$
declare
  v_item app.finance_ap_open_items;
  v_existing_event app.finance_ap_open_item_events;
  v_new_settled numeric;
  v_new_status text;
begin
  select * into v_item from app.finance_ap_open_items where id = p_open_item_id for update;
  if not found then
    raise exception 'finance_ap_open_item_not_found: %', p_open_item_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_ap_authority('Edit', v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing_event from app.finance_ap_open_item_events
      where tenant_id = v_item.tenant_id and open_item_id = p_open_item_id and idempotency_key = p_idempotency_key;
    if found then
      return v_item;
    end if;
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'finance_ap_invalid_settlement_amount: settlement amount must be positive, got %', p_amount
      using errcode = 'check_violation';
  end if;
  if p_amount > v_item.open_amount then
    raise exception 'finance_ap_over_settlement: settlement % exceeds open amount % for open item %', p_amount, v_item.open_amount, p_open_item_id
      using errcode = 'check_violation';
  end if;

  v_new_settled := v_item.settled_amount + p_amount;
  v_new_status := case when v_new_settled >= v_item.original_amount then 'settled' when v_new_settled > 0 then 'partial' else 'open' end;

  update app.finance_ap_open_items
    set settled_amount = v_new_settled, status = v_new_status
    where id = p_open_item_id
    returning * into v_item;

  insert into app.finance_ap_open_item_events (tenant_id, open_item_id, event_type, amount_delta, source_type, source_id, idempotency_key, actor_auth_user_id, actor_label)
  values (v_item.tenant_id, v_item.id, 'settled', p_amount, p_source_type, p_source_id, p_idempotency_key, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'apply_finance_ap_settlement',
    'app.finance_ap_open_items', v_item.id, 'success', null, null, jsonb_build_object('amount', p_amount, 'newStatus', v_new_status)
  );

  return v_item;
end;
$$;

-- Governed reversal. FIN:Approve-gated -- Prompt 199 section 24's own "posted
-- correction uses governed reversal/adjustment, never direct edit."
create function app.reverse_finance_ap_settlement(
  p_open_item_id uuid,
  p_amount numeric,
  p_reason text,
  p_source_type text,
  p_source_id uuid,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_ap_open_items
language plpgsql
as $$
declare
  v_item app.finance_ap_open_items;
  v_existing_event app.finance_ap_open_item_events;
  v_new_settled numeric;
  v_new_status text;
begin
  select * into v_item from app.finance_ap_open_items where id = p_open_item_id for update;
  if not found then
    raise exception 'finance_ap_open_item_not_found: %', p_open_item_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_ap_authority('Approve', v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing_event from app.finance_ap_open_item_events
      where tenant_id = v_item.tenant_id and open_item_id = p_open_item_id and idempotency_key = p_idempotency_key;
    if found then
      return v_item;
    end if;
  end if;

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_ap_unsettlement_reason_required: a non-empty reason is required to reverse a settlement'
      using errcode = 'check_violation';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'finance_ap_invalid_settlement_amount: reversal amount must be positive, got %', p_amount
      using errcode = 'check_violation';
  end if;
  if p_amount > v_item.settled_amount then
    raise exception 'finance_ap_over_reversal: reversal % exceeds settled amount % for open item %', p_amount, v_item.settled_amount, p_open_item_id
      using errcode = 'check_violation';
  end if;

  v_new_settled := v_item.settled_amount - p_amount;
  v_new_status := case when v_new_settled >= v_item.original_amount then 'settled' when v_new_settled > 0 then 'partial' else 'open' end;

  update app.finance_ap_open_items
    set settled_amount = v_new_settled, status = v_new_status
    where id = p_open_item_id
    returning * into v_item;

  insert into app.finance_ap_open_item_events (tenant_id, open_item_id, event_type, amount_delta, reason, source_type, source_id, idempotency_key, actor_auth_user_id, actor_label)
  values (v_item.tenant_id, v_item.id, 'unsettled', -p_amount, p_reason, p_source_type, p_source_id, p_idempotency_key, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'reverse_finance_ap_settlement',
    'app.finance_ap_open_items', v_item.id, 'success', p_reason, null, jsonb_build_object('amount', p_amount, 'newStatus', v_new_status)
  );

  return v_item;
end;
$$;

create function app.list_finance_ap_open_items(
  p_tenant_id uuid,
  p_company_id uuid,
  p_vendor_master_id uuid,
  p_status text,
  p_overdue_only boolean,
  p_actor_auth_user_id uuid
)
returns setof app.finance_ap_open_items
language plpgsql
stable
as $$
begin
  if not app.check_finance_ap_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_ap_open_items
    where tenant_id = p_tenant_id
      and (p_company_id is null or company_id = p_company_id)
      and (p_vendor_master_id is null or vendor_master_id = p_vendor_master_id)
      and (p_status is null or status = p_status)
      and (not coalesce(p_overdue_only, false) or (status <> 'settled' and due_date < current_date))
    order by due_date asc
    limit 200;
end;
$$;

create function app.get_finance_ap_open_item_activity(p_open_item_id uuid, p_actor_auth_user_id uuid)
returns setof app.finance_ap_open_item_events
language plpgsql
stable
as $$
declare
  v_item app.finance_ap_open_items;
begin
  select * into v_item from app.finance_ap_open_items where id = p_open_item_id;
  if not found then
    raise exception 'finance_ap_open_item_not_found: %', p_open_item_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_ap_authority('View', v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_ap_open_item_events where open_item_id = p_open_item_id order by created_at asc;
end;
$$;

-- Vendor obligation summary -- the payable mirror of FIN-196's own credit
-- exposure summary.
create function app.get_finance_ap_exposure_summary(p_tenant_id uuid, p_vendor_master_id uuid, p_actor_auth_user_id uuid)
returns jsonb
language plpgsql
stable
as $$
declare
  v_summary record;
begin
  if not app.check_finance_ap_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select
    coalesce(sum(open_amount), 0) as total_open,
    count(*) filter (where status <> 'settled') as open_count,
    coalesce(sum(open_amount) filter (where status <> 'settled' and due_date < current_date), 0) as overdue_open,
    count(*) filter (where status <> 'settled' and due_date < current_date) as overdue_count
  into v_summary
  from app.finance_ap_open_items
  where tenant_id = p_tenant_id and vendor_master_id = p_vendor_master_id;

  return jsonb_build_object(
    'totalOpen', v_summary.total_open,
    'openCount', v_summary.open_count,
    'overdueOpen', v_summary.overdue_open,
    'overdueCount', v_summary.overdue_count
  );
end;
$$;

alter table app.finance_ap_open_items enable row level security;
alter table app.finance_ap_open_item_events enable row level security;

create policy finance_ap_open_items_select_scoped on app.finance_ap_open_items
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

create policy finance_ap_open_item_events_select_scoped on app.finance_ap_open_item_events
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable
-- revoke of PostgreSQL's PUBLIC-execute default, the standing per-migration
-- convention since PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant select on app.finance_ap_open_items to authenticated, service_role;
grant select on app.finance_ap_open_item_events to authenticated, service_role;
grant insert, update, delete on app.finance_ap_open_items to service_role;
grant insert, update, delete on app.finance_ap_open_item_events to service_role;

grant execute on function app.touch_finance_ap_open_item_row() to service_role;
grant execute on function app.check_finance_ap_authority(text, uuid, uuid) to service_role;
grant execute on function app.post_finance_ap_open_item(uuid, uuid, uuid, text, uuid, text, numeric, date, date, uuid, text) to authenticated, service_role;
grant execute on function app.place_finance_ap_hold(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.release_finance_ap_hold(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.apply_finance_ap_settlement(uuid, numeric, text, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.reverse_finance_ap_settlement(uuid, numeric, text, text, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.list_finance_ap_open_items(uuid, uuid, uuid, text, boolean, uuid) to authenticated, service_role;
grant execute on function app.get_finance_ap_open_item_activity(uuid, uuid) to authenticated, service_role;
grant execute on function app.get_finance_ap_exposure_summary(uuid, uuid, uuid) to authenticated, service_role;
