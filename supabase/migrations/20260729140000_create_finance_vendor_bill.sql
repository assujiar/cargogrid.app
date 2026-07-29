-- Finance capability FIN-200 (Vendor Bill, CG-S9-FIN-011)
-- Vendor bills linked to verified Operations actual cost (OPS-178) and
-- available governed vendor references (OPS-172), with basic non-PO
-- validation, tax integration, approval, and one idempotent post to
-- FIN-199's own AP subledger.
--
-- Evidence-consumption boundary (disclosed, matching FIN-197's own
-- "consume without re-entering" discipline): `app.prepare_finance_vendor_bill_from_actual_cost`
-- reads `app.shipment_actual_costs`/`app.shipment_actual_cost_components`
-- (`OPS-178`) directly -- only `status = 'approved'` and `is_current` actual
-- cost is a valid source, and only its own vendor-sourced components
-- (`source_type = 'vendor'`) for the requested vendor are ever summed into a
-- bill. No cost amount is re-typed or independently computed.
--
-- One (actual cost, vendor) pair, one bill, idempotent (Prompt 200 section 24's
-- "duplicate vendor reference/file hash ... blocked"): `unique (tenant_id,
-- actual_cost_id, vendor_master_id)`. A single actual cost may still produce
-- multiple bills across different vendors (each vendor's own components are
-- summed independently) -- this is the intended multi-vendor-per-shipment
-- case, not a duplicate.
--
-- Basic match (Prompt 200 section 24: "Phase 4 supports basic source/cost
-- matching; PO/contract/three-way and vendor lifecycle depth remain Step
-- 11"): an optional `p_vendor_stated_amount` parameter represents the amount
-- a human read off the vendor's own paper/PDF bill (AI/OCR extraction
-- assistance and file capture are Prompt 200 section 16's own scope, not
-- built by this migration -- disclosed, not silently promised). When
-- provided, `variance_amount = |vendor_stated_amount - subtotal|` against a
-- small fixed tolerance (1.00 minor unit) -- a bounded MVP tolerance, not
-- driven by `FIN-191`'s own `finance_rounding` config (that governs rounding
-- computation, not match tolerance, a deliberately distinct concept). A
-- material variance sets `variance_status = 'requires_approval'`, disclosed
-- to the approver at approval time, but does not by itself block approval --
-- Phase 4 has no configurable threshold-routing engine (that scale of
-- capability is out of this MVP checkpoint's bounded scope, the same class
-- of proportionate-effort decision every prior FIN-19x checkpoint's own
-- header has recorded). When omitted, the bill trivially matches its own
-- source components (`variance_amount = 0`).
--
-- Vendor reference boundary: `vendor_master_id` references `app.master_records`
-- (`master_type_code = 'vendor'`), the identical reference `FIN-199`'s own
-- `app.finance_ap_open_items.vendor_master_id` already uses -- one vendor
-- identity, never duplicated.
--
-- Numbering and AP posting integration mirror `FIN-197`'s own Invoice design
-- exactly: `app.finance_vendor_bill_number_counters` is a bounded per-tenant/
-- company/year sequential counter assigned only at post time; `app.post_finance_vendor_bill`
-- (approved -> posted) is idempotent and calls `FIN-199`'s own
-- `app.post_finance_ap_open_item` directly (`source_document_type =
-- 'vendor_bill'`). GL journal posting (`FIN-202`/`FIN-203`) remains
-- disclosed, not built. No direct-edit path exists past `posted`; governed
-- debit/reversal correction remains `FIN-206`'s own scope.
--
-- Money/decimal discipline: every amount column is `numeric(14,2)`, never
-- `float`; `total_amount` is a generated column
-- (`subtotal_amount + tax_amount`).
--
-- Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration carries
-- its own explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM
-- PUBLIC` statement before its final grants, the standing per-migration
-- convention since `PLT-118`.

create table app.finance_vendor_bills (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  company_id uuid references app.org_units (id),
  bill_number text,
  vendor_master_id uuid not null references app.master_records (id),
  vendor_reference text,
  shipment_order_id uuid references app.shipment_orders (id),
  actual_cost_id uuid not null references app.shipment_actual_costs (id),
  currency text not null,
  status text not null default 'draft',
  subtotal_amount numeric(14, 2) not null default 0,
  tax_amount numeric(14, 2) not null default 0,
  total_amount numeric(14, 2) generated always as (subtotal_amount + tax_amount) stored,
  vendor_stated_amount numeric(14, 2),
  variance_amount numeric(14, 2) not null default 0,
  variance_status text not null default 'within_tolerance',
  payment_term_days integer not null default 30,
  bill_date date not null,
  due_date date not null,
  posting_period_id uuid references app.finance_fiscal_periods (id),
  ap_open_item_id uuid references app.finance_ap_open_items (id),
  submitted_by text,
  submitted_at timestamptz,
  approved_by text,
  approved_at timestamptz,
  posted_by text,
  posted_at timestamptz,
  void_reason text,
  voided_by text,
  voided_at timestamptz,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint finance_vendor_bills_status_check check (status in ('draft', 'submitted', 'approved', 'posted', 'void')),
  constraint finance_vendor_bills_variance_status_check check (variance_status in ('within_tolerance', 'requires_approval')),
  constraint finance_vendor_bills_currency_check check (currency ~ '^[A-Z]{3}$'),
  constraint finance_vendor_bills_subtotal_check check (subtotal_amount >= 0),
  constraint finance_vendor_bills_tax_check check (tax_amount >= 0),
  constraint finance_vendor_bills_variance_check check (variance_amount >= 0),
  constraint finance_vendor_bills_payment_term_check check (payment_term_days >= 0),
  constraint finance_vendor_bills_actual_cost_vendor_unique unique (tenant_id, actual_cost_id, vendor_master_id)
);

comment on table app.finance_vendor_bills is
  'FIN-200: one idempotent vendor bill per (actual cost, vendor) pair. total_amount is a generated column. bill_number is null until app.post_finance_vendor_bill assigns one. Carries no GL journal line -- FIN-202/203''s own scope.';

create unique index finance_vendor_bills_tenant_number_unique on app.finance_vendor_bills (tenant_id, bill_number) where bill_number is not null;
create unique index finance_vendor_bills_tenant_vendor_reference_unique on app.finance_vendor_bills (tenant_id, vendor_master_id, vendor_reference) where vendor_reference is not null;
create index finance_vendor_bills_tenant_vendor_idx on app.finance_vendor_bills (tenant_id, vendor_master_id);
create index finance_vendor_bills_tenant_status_idx on app.finance_vendor_bills (tenant_id, status);
create index finance_vendor_bills_actual_cost_idx on app.finance_vendor_bills (actual_cost_id);

create function app.touch_finance_vendor_bill_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger finance_vendor_bills_touch_row
  before update on app.finance_vendor_bills
  for each row
  execute function app.touch_finance_vendor_bill_row();

create table app.finance_vendor_bill_lines (
  id uuid primary key default gen_random_uuid(),
  bill_id uuid not null references app.finance_vendor_bills (id),
  line_number integer not null,
  line_type text not null,
  description text not null,
  amount numeric(14, 2) not null,
  source_component_id uuid references app.shipment_actual_cost_components (id),
  tax_code_id uuid references app.finance_tax_codes (id),
  tax_rule_version_id uuid references app.finance_tax_rule_versions (id),
  created_at timestamptz not null default now(),
  constraint finance_vendor_bill_lines_line_type_check check (line_type in ('cost', 'tax')),
  constraint finance_vendor_bill_lines_amount_check check (amount >= 0),
  constraint finance_vendor_bill_lines_source_check check (line_type = 'cost' or source_component_id is null),
  constraint finance_vendor_bill_lines_tax_ref_check check (line_type = 'tax' or (tax_code_id is null and tax_rule_version_id is null)),
  constraint finance_vendor_bill_lines_bill_line_unique unique (bill_id, line_number)
);

comment on table app.finance_vendor_bill_lines is
  'FIN-200: exact cost/tax lines. A cost line carries source_component_id, its own lineage to app.shipment_actual_cost_components (OPS-178) -- never re-typed. A tax line carries tax_code_id/tax_rule_version_id lineage, mirroring FIN-197''s own invoice-line discipline.';

create index finance_vendor_bill_lines_bill_id_idx on app.finance_vendor_bill_lines (bill_id);

create table app.finance_vendor_bill_number_counters (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  company_id uuid,
  year integer not null,
  next_seq integer not null default 1
);

comment on table app.finance_vendor_bill_number_counters is
  'FIN-200: a simple per-tenant/company/year sequential counter for vendor bill numbers, assigned only at post time -- mirrors FIN-197''s own app.finance_invoice_number_counters exactly.';

create unique index finance_vendor_bill_number_counters_scope_unique on app.finance_vendor_bill_number_counters (
  tenant_id, coalesce(company_id, '00000000-0000-0000-0000-000000000000'::uuid), year
);

create function app.check_finance_vendor_bill_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
as $$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'FIN', p_action)).allowed;
$$;

comment on function app.check_finance_vendor_bill_authority is
  'FIN-200: FIN:Edit gates prepare/submit/discard; FIN:Approve gates approve/post (posting composes with FIN-199''s own app.post_finance_ap_open_item, which itself requires FIN:Edit for a vendor-bill-sourced item -- the same layered-authority composition FIN-197''s own Invoice already established); FIN:View gates read.';

-- The one idempotent preparation entry point. Sums only the requested
-- vendor's own approved actual-cost components -- never re-typed.
create function app.prepare_finance_vendor_bill_from_actual_cost(
  p_tenant_id uuid,
  p_actual_cost_id uuid,
  p_vendor_master_id uuid,
  p_vendor_reference text,
  p_bill_date date,
  p_payment_term_days integer,
  p_vendor_stated_amount numeric,
  p_tax_code text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_vendor_bills
language plpgsql
as $$
declare
  v_bill app.finance_vendor_bills;
  v_cost app.shipment_actual_costs;
  v_vendor app.master_records;
  v_subtotal numeric(14, 2);
  v_line_number integer := 0;
  v_component app.shipment_actual_cost_components;
  v_variance numeric(14, 2) := 0;
  v_variance_status text := 'within_tolerance';
  v_tax_result jsonb;
  v_tax_amount numeric(14, 2) := 0;
  v_tax_code_id uuid;
  v_tax_rule_version_id uuid;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_vendor_bill_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_bill from app.finance_vendor_bills where tenant_id = p_tenant_id and actual_cost_id = p_actual_cost_id and vendor_master_id = p_vendor_master_id;
  if found then
    return v_bill;
  end if;

  select * into v_cost from app.shipment_actual_costs where id = p_actual_cost_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'finance_vendor_bill_actual_cost_not_found: % is not a known actual cost for tenant %', p_actual_cost_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;
  if v_cost.status <> 'approved' or not v_cost.is_current then
    raise exception 'finance_vendor_bill_actual_cost_not_approved: actual cost % is not the current approved version', p_actual_cost_id
      using errcode = 'check_violation';
  end if;

  select * into v_vendor from app.master_records
    where id = p_vendor_master_id and master_type_code = 'vendor' and canonical_status = 'active'
      and (tenant_id = p_tenant_id or tenant_id is null);
  if not found then
    raise exception 'finance_vendor_bill_vendor_not_found: % is not a known active vendor reference for tenant %', p_vendor_master_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;

  select coalesce(sum(amount), 0) into v_subtotal
    from app.shipment_actual_cost_components
    where actual_cost_id = p_actual_cost_id and source_type = 'vendor' and vendor_id = p_vendor_master_id;
  if v_subtotal <= 0 then
    raise exception 'finance_vendor_bill_no_matching_components: no vendor-sourced cost component for vendor % on actual cost %', p_vendor_master_id, p_actual_cost_id
      using errcode = 'no_data_found';
  end if;

  if p_vendor_stated_amount is not null then
    v_variance := abs(p_vendor_stated_amount - v_subtotal);
    if v_variance > 1.00 then
      v_variance_status := 'requires_approval';
    end if;
  end if;

  if p_tax_code is not null then
    select app.calculate_finance_tax(p_tenant_id, p_tax_code, v_subtotal, coalesce(p_bill_date, current_date), p_actor_auth_user_id) into v_tax_result;
    v_tax_amount := (v_tax_result ->> 'taxAmount')::numeric(14, 2);
    v_tax_rule_version_id := (v_tax_result ->> 'ruleVersionId')::uuid;
    select id into v_tax_code_id from app.finance_tax_codes where code = p_tax_code and (tenant_id = p_tenant_id or tenant_id is null) order by tenant_id nulls last limit 1;
  end if;

  insert into app.finance_vendor_bills (
    tenant_id, company_id, vendor_master_id, vendor_reference, shipment_order_id, actual_cost_id,
    currency, subtotal_amount, tax_amount, vendor_stated_amount, variance_amount, variance_status,
    payment_term_days, bill_date, due_date, created_by
  )
  select
    p_tenant_id, so.org_unit_id, p_vendor_master_id, p_vendor_reference, v_cost.shipment_order_id, p_actual_cost_id,
    v_cost.currency, v_subtotal, v_tax_amount, p_vendor_stated_amount, v_variance, v_variance_status,
    coalesce(p_payment_term_days, 30), p_bill_date, p_bill_date + (coalesce(p_payment_term_days, 30) || ' days')::interval, p_actor_label
  from app.shipment_orders so where so.id = v_cost.shipment_order_id
  returning * into v_bill;

  for v_component in
    select * from app.shipment_actual_cost_components
    where actual_cost_id = p_actual_cost_id and source_type = 'vendor' and vendor_id = p_vendor_master_id
    order by created_at asc
  loop
    v_line_number := v_line_number + 1;
    insert into app.finance_vendor_bill_lines (bill_id, line_number, line_type, description, amount, source_component_id)
    values (v_bill.id, v_line_number, 'cost', coalesce(v_component.description, v_component.category), v_component.amount, v_component.id);
  end loop;

  if v_tax_amount > 0 then
    v_line_number := v_line_number + 1;
    insert into app.finance_vendor_bill_lines (bill_id, line_number, line_type, description, amount, tax_code_id, tax_rule_version_id)
    values (v_bill.id, v_line_number, 'tax', p_tax_code || ' tax', v_tax_amount, v_tax_code_id, v_tax_rule_version_id);
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'prepare_finance_vendor_bill_from_actual_cost',
    'app.finance_vendor_bills', v_bill.id, 'success', null, null, to_jsonb(v_bill)
  );

  return v_bill;
end;
$$;

create function app.submit_finance_vendor_bill_for_approval(
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
begin
  select * into v_bill from app.finance_vendor_bills where id = p_bill_id;
  if not found then
    raise exception 'finance_vendor_bill_not_found: %', p_bill_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_vendor_bill_authority('Edit', v_bill.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_bill.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_bill.record_version <> p_expected_version then
    raise exception 'stale_version: bill % expected version % but found %', p_bill_id, p_expected_version, v_bill.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_bill.status <> 'draft' then
    raise exception 'finance_vendor_bill_not_draft: bill % is % not draft', p_bill_id, v_bill.status
      using errcode = 'check_violation';
  end if;

  update app.finance_vendor_bills set status = 'submitted', submitted_by = p_actor_label, submitted_at = now() where id = p_bill_id returning * into v_bill;

  perform app.capture_audit_event(
    v_bill.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_finance_vendor_bill_for_approval',
    'app.finance_vendor_bills', v_bill.id, 'success', null, null, to_jsonb(v_bill)
  );

  return v_bill;
end;
$$;

create function app.discard_finance_vendor_bill_draft(
  p_bill_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_vendor_bills
language plpgsql
as $$
declare
  v_bill app.finance_vendor_bills;
begin
  select * into v_bill from app.finance_vendor_bills where id = p_bill_id;
  if not found then
    raise exception 'finance_vendor_bill_not_found: %', p_bill_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_vendor_bill_authority('Edit', v_bill.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_bill.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_bill.record_version <> p_expected_version then
    raise exception 'stale_version: bill % expected version % but found %', p_bill_id, p_expected_version, v_bill.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_bill.status not in ('draft', 'submitted') then
    raise exception 'finance_vendor_bill_not_cancellable: bill % is %, only a draft or submitted bill may be discarded', p_bill_id, v_bill.status
      using errcode = 'check_violation';
  end if;

  update app.finance_vendor_bills set status = 'void', void_reason = p_reason, voided_by = p_actor_label, voided_at = now() where id = p_bill_id returning * into v_bill;

  perform app.capture_audit_event(
    v_bill.tenant_id, p_actor_auth_user_id, p_actor_label, 'discard_finance_vendor_bill_draft',
    'app.finance_vendor_bills', v_bill.id, 'success', p_reason, null, to_jsonb(v_bill)
  );

  return v_bill;
end;
$$;

create function app.approve_finance_vendor_bill(
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
begin
  select * into v_bill from app.finance_vendor_bills where id = p_bill_id;
  if not found then
    raise exception 'finance_vendor_bill_not_found: %', p_bill_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_vendor_bill_authority('Approve', v_bill.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_bill.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_bill.record_version <> p_expected_version then
    raise exception 'stale_version: bill % expected version % but found %', p_bill_id, p_expected_version, v_bill.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_bill.status <> 'submitted' then
    raise exception 'finance_vendor_bill_not_submitted: bill % is % not submitted', p_bill_id, v_bill.status
      using errcode = 'check_violation';
  end if;

  update app.finance_vendor_bills set status = 'approved', approved_by = p_actor_label, approved_at = now() where id = p_bill_id returning * into v_bill;

  perform app.capture_audit_event(
    v_bill.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_finance_vendor_bill',
    'app.finance_vendor_bills', v_bill.id, 'success', null, jsonb_build_object('varianceStatus', v_bill.variance_status), to_jsonb(v_bill)
  );

  return v_bill;
end;
$$;

-- One idempotent post (mirrors FIN-197's own app.issue_finance_invoice
-- exactly). A retried call against an already-posted bill returns it
-- unchanged.
create function app.post_finance_vendor_bill(
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

create function app.list_finance_vendor_bills(
  p_tenant_id uuid,
  p_company_id uuid,
  p_vendor_master_id uuid,
  p_status text,
  p_actor_auth_user_id uuid
)
returns setof app.finance_vendor_bills
language plpgsql
stable
as $$
begin
  if not app.check_finance_vendor_bill_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_vendor_bills
    where tenant_id = p_tenant_id
      and (p_company_id is null or company_id = p_company_id)
      and (p_vendor_master_id is null or vendor_master_id = p_vendor_master_id)
      and (p_status is null or status = p_status)
    order by created_at desc
    limit 200;
end;
$$;

create function app.get_finance_vendor_bill_lines(p_bill_id uuid, p_actor_auth_user_id uuid)
returns setof app.finance_vendor_bill_lines
language plpgsql
stable
as $$
declare
  v_bill app.finance_vendor_bills;
begin
  select * into v_bill from app.finance_vendor_bills where id = p_bill_id;
  if not found then
    raise exception 'finance_vendor_bill_not_found: %', p_bill_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_vendor_bill_authority('View', v_bill.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, v_bill.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_vendor_bill_lines where bill_id = p_bill_id order by line_number asc;
end;
$$;

alter table app.finance_vendor_bills enable row level security;
alter table app.finance_vendor_bill_lines enable row level security;

create policy finance_vendor_bills_select_scoped on app.finance_vendor_bills
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

create policy finance_vendor_bill_lines_select_scoped on app.finance_vendor_bill_lines
  for select to authenticated
  using (exists (select 1 from app.finance_vendor_bills b where b.id = finance_vendor_bill_lines.bill_id and (app.has_active_tenant_membership(b.tenant_id) or app.is_supreme_admin())));

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable
-- revoke of PostgreSQL's PUBLIC-execute default, the standing per-migration
-- convention since PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant select on app.finance_vendor_bills to authenticated, service_role;
grant select on app.finance_vendor_bill_lines to authenticated, service_role;
grant insert, update, delete on app.finance_vendor_bills to service_role;
grant insert, update, delete on app.finance_vendor_bill_lines to service_role;
grant select, insert, update on app.finance_vendor_bill_number_counters to service_role;

grant execute on function app.touch_finance_vendor_bill_row() to service_role;
grant execute on function app.check_finance_vendor_bill_authority(text, uuid, uuid) to service_role;
grant execute on function app.prepare_finance_vendor_bill_from_actual_cost(uuid, uuid, uuid, text, date, integer, numeric, text, uuid, text) to authenticated, service_role;
grant execute on function app.submit_finance_vendor_bill_for_approval(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.discard_finance_vendor_bill_draft(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.approve_finance_vendor_bill(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.post_finance_vendor_bill(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.list_finance_vendor_bills(uuid, uuid, uuid, text, uuid) to authenticated, service_role;
grant execute on function app.get_finance_vendor_bill_lines(uuid, uuid) to authenticated, service_role;
