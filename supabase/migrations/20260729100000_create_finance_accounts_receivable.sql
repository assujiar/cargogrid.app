-- Finance capability FIN-196 (Accounts Receivable Subledger, CG-S9-FIN-007)
-- Source-linked AR open items and their balance lifecycle. AR is created only
-- by a balanced source posting (Prompt 196 section 24: "never ad hoc UI
-- entry except approved migration/opening balance") -- this migration defines
-- the generic, idempotent posting primitive (`app.post_finance_ar_open_item`)
-- that a later source capability calls, plus the allocation/deallocation
-- primitives `FIN-198` (Receipt and Payment Allocation) will call directly.
--
-- Dependency-order disclosure (matching every prior FIN checkpoint's own
-- discipline): `FIN-197` (Invoice) does not exist yet at this checkpoint --
-- per `189_FINANCE_README.md` section 4, Accounts Receivable (196) precedes
-- Invoice (197) in the capability catalogue. This migration therefore builds
-- the AR open-item *subledger primitive* generically (source_document_type
-- bounded to `invoice`/`opening_balance` today), the same "build the shared
-- primitive first, the next capability becomes its first real caller"
-- pattern `FIN-191`'s own `finance_posting_map` forward reference and
-- `FIN-192`'s own later extension of `app.publish_finance_config_version`
-- already established. `FIN-197`'s own `app.issue_finance_invoice` is
-- expected to call `app.post_finance_ar_open_item` directly once it exists.
--
-- GL posting scope disclosure: per `189_FINANCE_README.md` section 4, AR/AP
-- and Source Subledgers (`FIN-202`) and the Double-Entry Journal (`FIN-203`)
-- are later capabilities than this one. This migration captures a
-- `posting_period_id` (resolved via `FIN-193`'s own
-- `app.resolve_finance_period_for_date`, rejecting a date with no open
-- period) and full source lineage, but creates zero GL journal line --
-- that remains `FIN-202`/`FIN-203`'s own scope, the same disclosed
-- forward-reference discipline every prior Finance capability in this
-- dependency order has established.
--
-- Status is a pure function of balance (`open`/`partial`/`paid`), computed
-- by the allocation functions themselves, never accepted from a caller.
-- Collection hold is an orthogonal flag (`is_held`), not a status value --
-- Prompt 196 section 22's own alternative flow lists "place a hold" and
-- "handle partial allocation" as independent axes. Posted-item correction
-- (a governed reversal to a genuinely wrong original_amount) remains
-- `FIN-206`'s own scope, not built yet -- disclosed, not silently promised;
-- this migration exposes no direct-edit or void path for a posted open item.
--
-- Money/decimal discipline: every amount column is `numeric(14,2)` (this
-- repository's own established money-column precision, matching
-- `app.shipment_actual_costs.total_amount`/`app.job_orders`' own revenue
-- snapshot amounts), never `float`/`real`. `open_amount` is a generated
-- column (`original_amount - allocated_amount`), always exactly
-- reconstructible, never independently mutable.
--
-- Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration carries
-- its own explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM
-- PUBLIC` statement before its final grants, the standing per-migration
-- convention since `PLT-118`.

create table app.finance_ar_open_items (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  company_id uuid references app.org_units (id),
  customer_account_id uuid not null references app.accounts (id),
  source_document_type text not null,
  source_document_id uuid not null,
  currency text not null,
  original_amount numeric(14, 2) not null,
  allocated_amount numeric(14, 2) not null default 0,
  open_amount numeric(14, 2) generated always as (original_amount - allocated_amount) stored,
  status text not null default 'open',
  is_held boolean not null default false,
  hold_reason text,
  held_by text,
  held_at timestamptz,
  released_by text,
  released_at timestamptz,
  invoice_date date not null,
  due_date date not null,
  posting_period_id uuid references app.finance_fiscal_periods (id),
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint finance_ar_open_items_source_type_check check (source_document_type in ('invoice', 'opening_balance')),
  constraint finance_ar_open_items_status_check check (status in ('open', 'partial', 'paid')),
  constraint finance_ar_open_items_currency_check check (currency ~ '^[A-Z]{3}$'),
  constraint finance_ar_open_items_original_amount_check check (original_amount > 0),
  constraint finance_ar_open_items_allocated_amount_check check (allocated_amount >= 0 and allocated_amount <= original_amount),
  constraint finance_ar_open_items_due_date_check check (due_date >= invoice_date),
  constraint finance_ar_open_items_source_unique unique (tenant_id, source_document_type, source_document_id)
);

comment on table app.finance_ar_open_items is
  'FIN-196: one idempotent AR open item per source document (unique on tenant/source_document_type/source_document_id). open_amount is a generated column (original_amount - allocated_amount), never independently mutable. status is a pure function of balance, computed only by app.apply_finance_ar_allocation/app.reverse_finance_ar_allocation. is_held is orthogonal to status. Carries no GL journal line -- FIN-202/203''s own scope.';

create index finance_ar_open_items_tenant_customer_idx on app.finance_ar_open_items (tenant_id, customer_account_id);
create index finance_ar_open_items_tenant_status_idx on app.finance_ar_open_items (tenant_id, status);
create index finance_ar_open_items_tenant_due_date_idx on app.finance_ar_open_items (tenant_id, due_date);
create index finance_ar_open_items_company_idx on app.finance_ar_open_items (company_id);

create function app.touch_finance_ar_open_item_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger finance_ar_open_items_touch_row
  before update on app.finance_ar_open_items
  for each row
  execute function app.touch_finance_ar_open_item_row();

-- Append-only lifecycle/allocation evidence (mirrors OPS-170's own
-- app.shipment_status_transitions shape for the same "real history, never
-- overwritten" reason). idempotency_key guards a retried allocate/deallocate
-- call from ever double-applying.
create table app.finance_ar_open_item_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  open_item_id uuid not null references app.finance_ar_open_items (id),
  event_type text not null,
  amount_delta numeric(14, 2),
  reason text,
  source_type text,
  source_id uuid,
  idempotency_key text,
  actor_auth_user_id uuid,
  actor_label text,
  created_at timestamptz not null default now(),
  constraint finance_ar_open_item_events_event_type_check check (event_type in ('created', 'allocated', 'deallocated', 'hold_placed', 'hold_released')),
  constraint finance_ar_open_item_events_idempotency_unique unique (tenant_id, open_item_id, idempotency_key)
);

comment on table app.finance_ar_open_item_events is
  'FIN-196: append-only AR open-item audit trail. idempotency_key (nullable, unique per open item when present) is the guard app.apply_finance_ar_allocation/app.reverse_finance_ar_allocation use so a retried call never double-applies.';

create index finance_ar_open_item_events_open_item_idx on app.finance_ar_open_item_events (open_item_id, created_at);

create function app.check_finance_ar_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
as $$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'FIN', p_action)).allowed;
$$;

comment on function app.check_finance_ar_authority is
  'FIN-196: FIN:Edit gates invoice-sourced posting/hold/allocation; FIN:Approve gates opening-balance posting/hold-release/deallocation (governed correction); FIN:View gates read -- the canonical PLT-111 FIN permission catalogue, reused directly.';

-- The one idempotent posting entry point (Prompt 196 section 21: "A posted
-- invoice creates one idempotent AR open item"). source_document_type
-- 'invoice' requires FIN:Edit (the internal posting-flow gate FIN-197 will
-- use); 'opening_balance' requires FIN:Approve (Prompt 196 section 24's own
-- "approved migration/opening balance" exception).
create function app.post_finance_ar_open_item(
  p_tenant_id uuid,
  p_company_id uuid,
  p_customer_account_id uuid,
  p_source_document_type text,
  p_source_document_id uuid,
  p_currency text,
  p_original_amount numeric,
  p_invoice_date date,
  p_due_date date,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_ar_open_items
language plpgsql
as $$
declare
  v_item app.finance_ar_open_items;
  v_customer app.accounts;
  v_period record;
  v_required_action text;
begin
  if p_source_document_type not in ('invoice', 'opening_balance') then
    raise exception 'finance_ar_unsupported_source_type: % is not a supported AR source document type', p_source_document_type
      using errcode = 'check_violation';
  end if;
  v_required_action := case when p_source_document_type = 'opening_balance' then 'Approve' else 'Edit' end;

  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_ar_authority(v_required_action, p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:% for tenant %', p_actor_auth_user_id, v_required_action, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent: a retried call for the same source document returns the
  -- existing open item rather than raising a duplicate error.
  select * into v_item from app.finance_ar_open_items
    where tenant_id = p_tenant_id and source_document_type = p_source_document_type and source_document_id = p_source_document_id;
  if found then
    return v_item;
  end if;

  select * into v_customer from app.accounts where id = p_customer_account_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'finance_ar_customer_not_found: % is not a known customer account for tenant %', p_customer_account_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;

  if not app.validate_currency_code(p_currency) then
    raise exception 'finance_ar_unsupported_currency: % is not a registered, active currency', p_currency
      using errcode = 'check_violation';
  end if;
  if p_original_amount is null or p_original_amount <= 0 then
    raise exception 'finance_ar_invalid_amount: original amount must be positive, got %', p_original_amount
      using errcode = 'check_violation';
  end if;
  if p_due_date < p_invoice_date then
    raise exception 'finance_ar_invalid_due_date: due date % is before invoice date %', p_due_date, p_invoice_date
      using errcode = 'check_violation';
  end if;

  select * into v_period from app.resolve_finance_period_for_date(p_tenant_id, p_company_id, p_invoice_date);
  if not found then
    raise exception 'finance_ar_period_not_found: no fiscal period covers %', p_invoice_date
      using errcode = 'no_data_found';
  end if;
  if not v_period.posting_eligible then
    raise exception 'finance_ar_period_not_open: fiscal period % for % is not open', v_period.period_code, p_invoice_date
      using errcode = 'check_violation';
  end if;

  begin
    insert into app.finance_ar_open_items (
      tenant_id, company_id, customer_account_id, source_document_type, source_document_id,
      currency, original_amount, invoice_date, due_date, posting_period_id, created_by
    )
    values (
      p_tenant_id, p_company_id, p_customer_account_id, p_source_document_type, p_source_document_id,
      p_currency, p_original_amount, p_invoice_date, p_due_date, v_period.period_id, p_actor_label
    )
    returning * into v_item;
  exception
    when unique_violation then
      select * into v_item from app.finance_ar_open_items
        where tenant_id = p_tenant_id and source_document_type = p_source_document_type and source_document_id = p_source_document_id;
      return v_item;
  end;

  insert into app.finance_ar_open_item_events (tenant_id, open_item_id, event_type, amount_delta, source_type, source_id, actor_auth_user_id, actor_label)
  values (p_tenant_id, v_item.id, 'created', p_original_amount, p_source_document_type, p_source_document_id, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'post_finance_ar_open_item',
    'app.finance_ar_open_items', v_item.id, 'success', null, null, to_jsonb(v_item)
  );

  return v_item;
end;
$$;

create function app.place_finance_ar_hold(
  p_open_item_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_ar_open_items
language plpgsql
as $$
declare
  v_item app.finance_ar_open_items;
begin
  select * into v_item from app.finance_ar_open_items where id = p_open_item_id;
  if not found then
    raise exception 'finance_ar_open_item_not_found: %', p_open_item_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_ar_authority('Edit', v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_item.record_version <> p_expected_version then
    raise exception 'stale_version: open item % expected version % but found %', p_open_item_id, p_expected_version, v_item.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_ar_hold_reason_required: a non-empty reason is required to place a hold'
      using errcode = 'check_violation';
  end if;
  if v_item.is_held then
    raise exception 'finance_ar_already_held: open item % is already held', p_open_item_id
      using errcode = 'check_violation';
  end if;

  update app.finance_ar_open_items
    set is_held = true, hold_reason = p_reason, held_by = p_actor_label, held_at = now(), released_by = null, released_at = null
    where id = p_open_item_id
    returning * into v_item;

  insert into app.finance_ar_open_item_events (tenant_id, open_item_id, event_type, reason, actor_auth_user_id, actor_label)
  values (v_item.tenant_id, v_item.id, 'hold_placed', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'place_finance_ar_hold',
    'app.finance_ar_open_items', v_item.id, 'success', p_reason, null, to_jsonb(v_item)
  );

  return v_item;
end;
$$;

create function app.release_finance_ar_hold(
  p_open_item_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_ar_open_items
language plpgsql
as $$
declare
  v_item app.finance_ar_open_items;
begin
  select * into v_item from app.finance_ar_open_items where id = p_open_item_id;
  if not found then
    raise exception 'finance_ar_open_item_not_found: %', p_open_item_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_ar_authority('Approve', v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_item.record_version <> p_expected_version then
    raise exception 'stale_version: open item % expected version % but found %', p_open_item_id, p_expected_version, v_item.record_version
      using errcode = 'serialization_failure';
  end if;
  if not v_item.is_held then
    raise exception 'finance_ar_not_held: open item % is not currently held', p_open_item_id
      using errcode = 'check_violation';
  end if;

  update app.finance_ar_open_items
    set is_held = false, released_by = p_actor_label, released_at = now()
    where id = p_open_item_id
    returning * into v_item;

  insert into app.finance_ar_open_item_events (tenant_id, open_item_id, event_type, reason, actor_auth_user_id, actor_label)
  values (v_item.tenant_id, v_item.id, 'hold_released', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'release_finance_ar_hold',
    'app.finance_ar_open_items', v_item.id, 'success', p_reason, null, to_jsonb(v_item)
  );

  return v_item;
end;
$$;

-- The shared allocation primitive FIN-198 (Receipt and Payment Allocation)
-- calls directly. Row-locked (`for update`) so concurrent allocation attempts
-- against the same open item serialize rather than both reading a stale
-- open_amount (Prompt 196 section 25: "preview and commit preserve exact
-- balance under retry and concurrency"). Idempotent on
-- (tenant_id, open_item_id, idempotency_key) via
-- app.finance_ar_open_item_events' own unique constraint.
create function app.apply_finance_ar_allocation(
  p_open_item_id uuid,
  p_amount numeric,
  p_source_type text,
  p_source_id uuid,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_ar_open_items
language plpgsql
as $$
declare
  v_item app.finance_ar_open_items;
  v_existing_event app.finance_ar_open_item_events;
  v_new_allocated numeric;
  v_new_status text;
begin
  select * into v_item from app.finance_ar_open_items where id = p_open_item_id for update;
  if not found then
    raise exception 'finance_ar_open_item_not_found: %', p_open_item_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_ar_authority('Edit', v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing_event from app.finance_ar_open_item_events
      where tenant_id = v_item.tenant_id and open_item_id = p_open_item_id and idempotency_key = p_idempotency_key;
    if found then
      return v_item;
    end if;
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'finance_ar_invalid_allocation_amount: allocation amount must be positive, got %', p_amount
      using errcode = 'check_violation';
  end if;
  if p_amount > v_item.open_amount then
    raise exception 'finance_ar_over_allocation: allocation % exceeds open amount % for open item %', p_amount, v_item.open_amount, p_open_item_id
      using errcode = 'check_violation';
  end if;

  v_new_allocated := v_item.allocated_amount + p_amount;
  v_new_status := case when v_new_allocated >= v_item.original_amount then 'paid' when v_new_allocated > 0 then 'partial' else 'open' end;

  update app.finance_ar_open_items
    set allocated_amount = v_new_allocated, status = v_new_status
    where id = p_open_item_id
    returning * into v_item;

  insert into app.finance_ar_open_item_events (tenant_id, open_item_id, event_type, amount_delta, source_type, source_id, idempotency_key, actor_auth_user_id, actor_label)
  values (v_item.tenant_id, v_item.id, 'allocated', p_amount, p_source_type, p_source_id, p_idempotency_key, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'apply_finance_ar_allocation',
    'app.finance_ar_open_items', v_item.id, 'success', null, null, jsonb_build_object('amount', p_amount, 'newStatus', v_new_status)
  );

  return v_item;
end;
$$;

-- Governed deallocation (reversal). FIN:Approve-gated -- Prompt 196 section 24's
-- own "posted correction uses governed reversal/adjustment, never direct edit."
create function app.reverse_finance_ar_allocation(
  p_open_item_id uuid,
  p_amount numeric,
  p_reason text,
  p_source_type text,
  p_source_id uuid,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_ar_open_items
language plpgsql
as $$
declare
  v_item app.finance_ar_open_items;
  v_existing_event app.finance_ar_open_item_events;
  v_new_allocated numeric;
  v_new_status text;
begin
  select * into v_item from app.finance_ar_open_items where id = p_open_item_id for update;
  if not found then
    raise exception 'finance_ar_open_item_not_found: %', p_open_item_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_ar_authority('Approve', v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing_event from app.finance_ar_open_item_events
      where tenant_id = v_item.tenant_id and open_item_id = p_open_item_id and idempotency_key = p_idempotency_key;
    if found then
      return v_item;
    end if;
  end if;

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_ar_deallocation_reason_required: a non-empty reason is required to reverse an allocation'
      using errcode = 'check_violation';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'finance_ar_invalid_allocation_amount: reversal amount must be positive, got %', p_amount
      using errcode = 'check_violation';
  end if;
  if p_amount > v_item.allocated_amount then
    raise exception 'finance_ar_over_reversal: reversal % exceeds allocated amount % for open item %', p_amount, v_item.allocated_amount, p_open_item_id
      using errcode = 'check_violation';
  end if;

  v_new_allocated := v_item.allocated_amount - p_amount;
  v_new_status := case when v_new_allocated >= v_item.original_amount then 'paid' when v_new_allocated > 0 then 'partial' else 'open' end;

  update app.finance_ar_open_items
    set allocated_amount = v_new_allocated, status = v_new_status
    where id = p_open_item_id
    returning * into v_item;

  insert into app.finance_ar_open_item_events (tenant_id, open_item_id, event_type, amount_delta, reason, source_type, source_id, idempotency_key, actor_auth_user_id, actor_label)
  values (v_item.tenant_id, v_item.id, 'deallocated', -p_amount, p_reason, p_source_type, p_source_id, p_idempotency_key, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'reverse_finance_ar_allocation',
    'app.finance_ar_open_items', v_item.id, 'success', p_reason, null, jsonb_build_object('amount', p_amount, 'newStatus', v_new_status)
  );

  return v_item;
end;
$$;

create function app.list_finance_ar_open_items(
  p_tenant_id uuid,
  p_company_id uuid,
  p_customer_account_id uuid,
  p_status text,
  p_overdue_only boolean,
  p_actor_auth_user_id uuid
)
returns setof app.finance_ar_open_items
language plpgsql
stable
as $$
begin
  if not app.check_finance_ar_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_ar_open_items
    where tenant_id = p_tenant_id
      and (p_company_id is null or company_id = p_company_id)
      and (p_customer_account_id is null or customer_account_id = p_customer_account_id)
      and (p_status is null or status = p_status)
      and (not coalesce(p_overdue_only, false) or (status <> 'paid' and due_date < current_date))
    order by due_date asc
    limit 200;
end;
$$;

create function app.get_finance_ar_open_item_activity(p_open_item_id uuid, p_actor_auth_user_id uuid)
returns setof app.finance_ar_open_item_events
language plpgsql
stable
as $$
declare
  v_item app.finance_ar_open_items;
begin
  select * into v_item from app.finance_ar_open_items where id = p_open_item_id;
  if not found then
    raise exception 'finance_ar_open_item_not_found: %', p_open_item_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_ar_authority('View', v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_ar_open_item_events where open_item_id = p_open_item_id order by created_at asc;
end;
$$;

-- Credit exposure summary (Prompt 196 section 3's own "credit exposure"
-- feature slice). Internal Finance aggregate only -- customer-facing
-- visibility is deferred to Step 13 (Prompt 196 section 26).
create function app.get_finance_ar_exposure_summary(p_tenant_id uuid, p_customer_account_id uuid, p_actor_auth_user_id uuid)
returns jsonb
language plpgsql
stable
as $$
declare
  v_summary record;
begin
  if not app.check_finance_ar_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select
    coalesce(sum(open_amount), 0) as total_open,
    count(*) filter (where status <> 'paid') as open_count,
    coalesce(sum(open_amount) filter (where status <> 'paid' and due_date < current_date), 0) as overdue_open,
    count(*) filter (where status <> 'paid' and due_date < current_date) as overdue_count
  into v_summary
  from app.finance_ar_open_items
  where tenant_id = p_tenant_id and customer_account_id = p_customer_account_id;

  return jsonb_build_object(
    'totalOpen', v_summary.total_open,
    'openCount', v_summary.open_count,
    'overdueOpen', v_summary.overdue_open,
    'overdueCount', v_summary.overdue_count
  );
end;
$$;

alter table app.finance_ar_open_items enable row level security;
alter table app.finance_ar_open_item_events enable row level security;

create policy finance_ar_open_items_select_scoped on app.finance_ar_open_items
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

create policy finance_ar_open_item_events_select_scoped on app.finance_ar_open_item_events
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable
-- revoke of PostgreSQL's PUBLIC-execute default, the standing per-migration
-- convention since PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant select on app.finance_ar_open_items to authenticated, service_role;
grant select on app.finance_ar_open_item_events to authenticated, service_role;
grant insert, update, delete on app.finance_ar_open_items to service_role;
grant insert, update, delete on app.finance_ar_open_item_events to service_role;

grant execute on function app.touch_finance_ar_open_item_row() to service_role;
grant execute on function app.check_finance_ar_authority(text, uuid, uuid) to service_role;
grant execute on function app.post_finance_ar_open_item(uuid, uuid, uuid, text, uuid, text, numeric, date, date, uuid, text) to authenticated, service_role;
grant execute on function app.place_finance_ar_hold(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.release_finance_ar_hold(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.apply_finance_ar_allocation(uuid, numeric, text, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.reverse_finance_ar_allocation(uuid, numeric, text, text, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.list_finance_ar_open_items(uuid, uuid, uuid, text, boolean, uuid) to authenticated, service_role;
grant execute on function app.get_finance_ar_open_item_activity(uuid, uuid) to authenticated, service_role;
grant execute on function app.get_finance_ar_exposure_summary(uuid, uuid, uuid) to authenticated, service_role;
