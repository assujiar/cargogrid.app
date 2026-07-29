-- Finance capability FIN-197 (Customer Invoice, CG-S9-FIN-008)
-- Versioned customer invoices prepared from verified Operations
-- BillingReadinessHandoff evidence (OPS-181), with exact charge/tax lines,
-- approval, and one idempotent issue/post to FIN-196's own AR subledger.
--
-- Consumes verified evidence without re-entering it (Prompt 197 section 24 /
-- 189_FINANCE_README.md section 5): `app.prepare_finance_invoice_from_readiness`
-- reads `app.billing_readiness_handoffs` -> `app.job_orders`
-- (`account_id`/`org_unit_id`/`revenue_snapshot`/`job_number`) directly.
-- `app.handoff_billing_readiness` (OPS-181) only ever creates a handoff row
-- when the evaluation's own `effective_status = 'ready'` at handoff time --
-- confirmed by direct inspection of that function's own body -- so a handoff
-- row existing is itself the readiness proof; this migration does not
-- re-evaluate readiness evidence.
--
-- One handoff, one invoice, idempotent (Prompt 197 section 24's "a readiness
-- item can be billed only according to versioned consolidation/split rules
-- and uniqueness keys"): `unique (tenant_id, billing_readiness_handoff_id)`.
-- Consolidating multiple Job Orders/handoffs into a single invoice, and
-- splitting one handoff across multiple invoices, are Prompt 197 section 22's
-- own alternative flow -- deliberately out of this MVP checkpoint's bounded
-- scope (disclosed, not silently promised), the same class of proportionate-
-- effort scope decision `OPS-181`'s own fixed `rule_version` placeholder and
-- `OPS-179`'s own "no FX conversion" boundary already established. A real
-- multi-handoff consolidation engine is left for a later capability.
--
-- Charge-line derivation (disclosed, bounded MVP scope): one summary charge
-- line per invoice, from `app.job_orders.revenue_snapshot ->> 'totalAmount'`/
-- `'currency'` -- the exact governed revenue basis `OPS-179`'s own Job
-- Profitability capability already reads verbatim from the same column, per
-- that capability's own "read the governed snapshot verbatim, never
-- re-derive" discipline. Per-charge-code line-level granularity (freight vs.
-- handling vs. customs, etc.) is not available at this dependency point --
-- `app.job_orders.revenue_snapshot` is itself already a single governed
-- total, not a per-charge-code breakdown -- so this migration cannot invent
-- finer granularity than its own source evidence provides.
--
-- Tax-line integration: an optional tax code parameter to
-- `app.prepare_finance_invoice_from_readiness` calls `FIN-195`'s own
-- `app.calculate_finance_tax` directly -- the exact-decimal, SME-approval-
-- gated calculation service that capability built. No tax rate is computed
-- independently here; a missing/unapproved tax rule propagates
-- `finance_tax_rule_missing` unchanged (never a silent zero tax line).
--
-- Numbering (disclosed, bounded MVP scope): `app.finance_invoice_number_counters`
-- is a simple per-tenant/company/year sequential counter, assigned only at
-- issue time (never at draft time, so a discarded draft never burns a
-- number) -- a bounded, proportionate-effort alternative to the full
-- pattern-based numbering `FIN-191`'s own `finance_numbering` config class
-- describes as policy metadata only (no generator implemented anywhere yet
-- in this repository), the same class of disclosed simplification
-- `COM-151`'s own header recorded for the Configurable Numbering Engine
-- boundary.
--
-- AR posting integration: `app.issue_finance_invoice` (approved -> issued)
-- is idempotent (a retried call against an already-issued invoice returns it
-- unchanged) and calls `FIN-196`'s own `app.post_finance_ar_open_item`
-- directly (`source_document_type = 'invoice'`, `source_document_id` = this
-- invoice's own `id`) -- one idempotent AR open item per issued invoice,
-- Prompt 197 section 21's own "posts once to AR". GL journal posting
-- (`FIN-202`/`FIN-203`) remains disclosed, not built -- this migration
-- captures `posting_period_id` and the `ar_open_item_id` link but creates
-- zero journal line.
--
-- Correction: a normal role cannot edit a posted (issued) invoice -- no
-- direct-edit path exists past `issued`; `app.discard_finance_invoice_draft`
-- only ever operates on `draft`/`submitted`. Governed credit/debit/reversal
-- correction of an issued invoice remains `FIN-206`'s own scope, disclosed.
--
-- Money/decimal discipline: every amount column is `numeric(14,2)`, never
-- `float`; `total_amount` is a generated column
-- (`subtotal_amount + tax_amount`), never independently mutable.
--
-- Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration carries
-- its own explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM
-- PUBLIC` statement before its final grants, the standing per-migration
-- convention since `PLT-118`.

create table app.finance_invoices (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  company_id uuid references app.org_units (id),
  invoice_number text,
  customer_account_id uuid not null references app.accounts (id),
  job_order_id uuid not null references app.job_orders (id),
  billing_readiness_handoff_id uuid not null references app.billing_readiness_handoffs (id),
  currency text not null,
  status text not null default 'draft',
  subtotal_amount numeric(14, 2) not null default 0,
  tax_amount numeric(14, 2) not null default 0,
  total_amount numeric(14, 2) generated always as (subtotal_amount + tax_amount) stored,
  payment_term_days integer not null default 30,
  issue_date date,
  due_date date,
  posting_period_id uuid references app.finance_fiscal_periods (id),
  ar_open_item_id uuid references app.finance_ar_open_items (id),
  submitted_by text,
  submitted_at timestamptz,
  approved_by text,
  approved_at timestamptz,
  issued_by text,
  issued_at timestamptz,
  void_reason text,
  voided_by text,
  voided_at timestamptz,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint finance_invoices_status_check check (status in ('draft', 'submitted', 'approved', 'issued', 'void')),
  constraint finance_invoices_currency_check check (currency ~ '^[A-Z]{3}$'),
  constraint finance_invoices_subtotal_check check (subtotal_amount >= 0),
  constraint finance_invoices_tax_check check (tax_amount >= 0),
  constraint finance_invoices_payment_term_check check (payment_term_days >= 0),
  constraint finance_invoices_handoff_unique unique (tenant_id, billing_readiness_handoff_id)
);

comment on table app.finance_invoices is
  'FIN-197: one idempotent invoice per BillingReadinessHandoff (unique on tenant/billing_readiness_handoff_id). total_amount is a generated column, never independently mutable. invoice_number is null until app.issue_finance_invoice assigns one (never burned by a discarded draft). Carries no GL journal line -- FIN-202/203''s own scope.';

create unique index finance_invoices_tenant_number_unique on app.finance_invoices (tenant_id, invoice_number) where invoice_number is not null;
create index finance_invoices_tenant_customer_idx on app.finance_invoices (tenant_id, customer_account_id);
create index finance_invoices_tenant_status_idx on app.finance_invoices (tenant_id, status);
create index finance_invoices_job_order_idx on app.finance_invoices (job_order_id);

create function app.touch_finance_invoice_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger finance_invoices_touch_row
  before update on app.finance_invoices
  for each row
  execute function app.touch_finance_invoice_row();

create table app.finance_invoice_lines (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references app.finance_invoices (id),
  line_number integer not null,
  line_type text not null,
  description text not null,
  amount numeric(14, 2) not null,
  tax_code_id uuid references app.finance_tax_codes (id),
  tax_rule_version_id uuid references app.finance_tax_rule_versions (id),
  created_at timestamptz not null default now(),
  constraint finance_invoice_lines_line_type_check check (line_type in ('charge', 'tax')),
  constraint finance_invoice_lines_amount_check check (amount >= 0),
  constraint finance_invoice_lines_tax_ref_check check (line_type = 'tax' or (tax_code_id is null and tax_rule_version_id is null)),
  constraint finance_invoice_lines_invoice_line_unique unique (invoice_id, line_number)
);

comment on table app.finance_invoice_lines is
  'FIN-197: exact charge/tax lines. A tax line captures its own tax_code_id/tax_rule_version_id lineage -- the amount is reproducible from the captured rule version at any later time, per FIN-195''s own acceptance criteria.';

create index finance_invoice_lines_invoice_id_idx on app.finance_invoice_lines (invoice_id);

-- Bounded MVP sequential numbering (disclosed, this migration's own header).
create table app.finance_invoice_number_counters (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  company_id uuid,
  year integer not null,
  next_seq integer not null default 1
);

comment on table app.finance_invoice_number_counters is
  'FIN-197: a simple per-tenant/company/year sequential counter for invoice numbers, assigned only at issue time. company_id may be null (tenant-wide, no company scope on the source Job Order) -- the unique index coalesces it to a sentinel, mirroring FIN-192/193''s own tenant/company scope convention.';

create unique index finance_invoice_number_counters_scope_unique on app.finance_invoice_number_counters (
  tenant_id, coalesce(company_id, '00000000-0000-0000-0000-000000000000'::uuid), year
);

create function app.check_finance_invoice_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
as $$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'FIN', p_action)).allowed;
$$;

comment on function app.check_finance_invoice_authority is
  'FIN-197: FIN:Edit gates prepare/submit/discard; FIN:Approve gates approve/issue (issuing composes with FIN-196''s own app.post_finance_ar_open_item, which itself requires FIN:Edit for an invoice-sourced item -- a deliberate layered-authority composition, the same class FIN-191''s own two-factor gate already established); FIN:View gates read.';

-- The one idempotent preparation entry point (Prompt 197 section 21: "system
-- inherits source data, prepares charge/tax lines"). Idempotent on
-- (tenant_id, billing_readiness_handoff_id) -- a retried call returns the
-- existing invoice rather than raising a duplicate error (Prompt 197 section
-- 23's "duplicate source billing" is structurally impossible past this
-- point, not merely rejected).
create function app.prepare_finance_invoice_from_readiness(
  p_tenant_id uuid,
  p_billing_readiness_handoff_id uuid,
  p_payment_term_days integer,
  p_tax_code text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_invoices
language plpgsql
as $$
declare
  v_invoice app.finance_invoices;
  v_handoff app.billing_readiness_handoffs;
  v_job app.job_orders;
  v_subtotal numeric(14, 2);
  v_currency text;
  v_tax_result jsonb;
  v_tax_amount numeric(14, 2) := 0;
  v_tax_code_id uuid;
  v_tax_rule_version_id uuid;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_invoice_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_invoice from app.finance_invoices where tenant_id = p_tenant_id and billing_readiness_handoff_id = p_billing_readiness_handoff_id;
  if found then
    return v_invoice;
  end if;

  select * into v_handoff from app.billing_readiness_handoffs where id = p_billing_readiness_handoff_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'finance_invoice_handoff_not_found: % is not a known BillingReadinessHandoff for tenant %', p_billing_readiness_handoff_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;

  select * into v_job from app.job_orders where id = v_handoff.job_order_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'finance_invoice_job_order_not_found: % is not a known Job Order for tenant %', v_handoff.job_order_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;

  v_currency := v_job.revenue_snapshot ->> 'currency';
  v_subtotal := (v_job.revenue_snapshot ->> 'totalAmount')::numeric(14, 2);
  if v_currency is null or v_subtotal is null then
    raise exception 'finance_invoice_revenue_snapshot_incomplete: job order % has no usable revenue snapshot', v_job.id
      using errcode = 'check_violation';
  end if;
  if not app.validate_currency_code(v_currency) then
    raise exception 'finance_invoice_unsupported_currency: % is not a registered, active currency', v_currency
      using errcode = 'check_violation';
  end if;
  if v_subtotal <= 0 then
    raise exception 'finance_invoice_invalid_subtotal: revenue snapshot total % must be positive', v_subtotal
      using errcode = 'check_violation';
  end if;

  if p_tax_code is not null then
    select app.calculate_finance_tax(p_tenant_id, p_tax_code, v_subtotal, current_date, p_actor_auth_user_id) into v_tax_result;
    v_tax_amount := (v_tax_result ->> 'taxAmount')::numeric(14, 2);
    v_tax_rule_version_id := (v_tax_result ->> 'ruleVersionId')::uuid;
    select id into v_tax_code_id from app.finance_tax_codes where code = p_tax_code and (tenant_id = p_tenant_id or tenant_id is null) order by tenant_id nulls last limit 1;
  end if;

  insert into app.finance_invoices (
    tenant_id, company_id, customer_account_id, job_order_id, billing_readiness_handoff_id,
    currency, subtotal_amount, tax_amount, payment_term_days, created_by
  )
  values (
    p_tenant_id, v_job.org_unit_id, v_job.account_id, v_job.id, p_billing_readiness_handoff_id,
    v_currency, v_subtotal, v_tax_amount, coalesce(p_payment_term_days, 30), p_actor_label
  )
  returning * into v_invoice;

  insert into app.finance_invoice_lines (invoice_id, line_number, line_type, description, amount)
  values (v_invoice.id, 1, 'charge', 'Freight and service charges per Job Order ' || v_job.job_number, v_subtotal);

  if v_tax_amount > 0 then
    insert into app.finance_invoice_lines (invoice_id, line_number, line_type, description, amount, tax_code_id, tax_rule_version_id)
    values (v_invoice.id, 2, 'tax', p_tax_code || ' tax', v_tax_amount, v_tax_code_id, v_tax_rule_version_id);
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'prepare_finance_invoice_from_readiness',
    'app.finance_invoices', v_invoice.id, 'success', null, null, to_jsonb(v_invoice)
  );

  return v_invoice;
end;
$$;

create function app.submit_finance_invoice_for_approval(
  p_invoice_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_invoices
language plpgsql
as $$
declare
  v_invoice app.finance_invoices;
begin
  select * into v_invoice from app.finance_invoices where id = p_invoice_id;
  if not found then
    raise exception 'finance_invoice_not_found: %', p_invoice_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_invoice_authority('Edit', v_invoice.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_invoice.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_invoice.record_version <> p_expected_version then
    raise exception 'stale_version: invoice % expected version % but found %', p_invoice_id, p_expected_version, v_invoice.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_invoice.status <> 'draft' then
    raise exception 'finance_invoice_not_draft: invoice % is % not draft', p_invoice_id, v_invoice.status
      using errcode = 'check_violation';
  end if;

  update app.finance_invoices set status = 'submitted', submitted_by = p_actor_label, submitted_at = now() where id = p_invoice_id returning * into v_invoice;

  perform app.capture_audit_event(
    v_invoice.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_finance_invoice_for_approval',
    'app.finance_invoices', v_invoice.id, 'success', null, null, to_jsonb(v_invoice)
  );

  return v_invoice;
end;
$$;

create function app.discard_finance_invoice_draft(
  p_invoice_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_invoices
language plpgsql
as $$
declare
  v_invoice app.finance_invoices;
begin
  select * into v_invoice from app.finance_invoices where id = p_invoice_id;
  if not found then
    raise exception 'finance_invoice_not_found: %', p_invoice_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_invoice_authority('Edit', v_invoice.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_invoice.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_invoice.record_version <> p_expected_version then
    raise exception 'stale_version: invoice % expected version % but found %', p_invoice_id, p_expected_version, v_invoice.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_invoice.status not in ('draft', 'submitted') then
    raise exception 'finance_invoice_not_cancellable: invoice % is %, only a draft or submitted invoice may be discarded', p_invoice_id, v_invoice.status
      using errcode = 'check_violation';
  end if;

  update app.finance_invoices set status = 'void', void_reason = p_reason, voided_by = p_actor_label, voided_at = now() where id = p_invoice_id returning * into v_invoice;

  perform app.capture_audit_event(
    v_invoice.tenant_id, p_actor_auth_user_id, p_actor_label, 'discard_finance_invoice_draft',
    'app.finance_invoices', v_invoice.id, 'success', p_reason, null, to_jsonb(v_invoice)
  );

  return v_invoice;
end;
$$;

create function app.approve_finance_invoice(
  p_invoice_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_invoices
language plpgsql
as $$
declare
  v_invoice app.finance_invoices;
begin
  select * into v_invoice from app.finance_invoices where id = p_invoice_id;
  if not found then
    raise exception 'finance_invoice_not_found: %', p_invoice_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_invoice_authority('Approve', v_invoice.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_invoice.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_invoice.record_version <> p_expected_version then
    raise exception 'stale_version: invoice % expected version % but found %', p_invoice_id, p_expected_version, v_invoice.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_invoice.status <> 'submitted' then
    raise exception 'finance_invoice_not_submitted: invoice % is % not submitted', p_invoice_id, v_invoice.status
      using errcode = 'check_violation';
  end if;

  update app.finance_invoices set status = 'approved', approved_by = p_actor_label, approved_at = now() where id = p_invoice_id returning * into v_invoice;

  perform app.capture_audit_event(
    v_invoice.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_finance_invoice',
    'app.finance_invoices', v_invoice.id, 'success', null, null, to_jsonb(v_invoice)
  );

  return v_invoice;
end;
$$;

-- One idempotent issue/post (Prompt 197 section 21/33: "posts once to AR").
-- A retried call against an already-issued invoice returns it unchanged.
create function app.issue_finance_invoice(
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

create function app.list_finance_invoices(
  p_tenant_id uuid,
  p_company_id uuid,
  p_customer_account_id uuid,
  p_status text,
  p_actor_auth_user_id uuid
)
returns setof app.finance_invoices
language plpgsql
stable
as $$
begin
  if not app.check_finance_invoice_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_invoices
    where tenant_id = p_tenant_id
      and (p_company_id is null or company_id = p_company_id)
      and (p_customer_account_id is null or customer_account_id = p_customer_account_id)
      and (p_status is null or status = p_status)
    order by created_at desc
    limit 200;
end;
$$;

create function app.get_finance_invoice_lines(p_invoice_id uuid, p_actor_auth_user_id uuid)
returns setof app.finance_invoice_lines
language plpgsql
stable
as $$
declare
  v_invoice app.finance_invoices;
begin
  select * into v_invoice from app.finance_invoices where id = p_invoice_id;
  if not found then
    raise exception 'finance_invoice_not_found: %', p_invoice_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_invoice_authority('View', v_invoice.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, v_invoice.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_invoice_lines where invoice_id = p_invoice_id order by line_number asc;
end;
$$;

alter table app.finance_invoices enable row level security;
alter table app.finance_invoice_lines enable row level security;

create policy finance_invoices_select_scoped on app.finance_invoices
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

create policy finance_invoice_lines_select_scoped on app.finance_invoice_lines
  for select to authenticated
  using (exists (select 1 from app.finance_invoices i where i.id = finance_invoice_lines.invoice_id and (app.has_active_tenant_membership(i.tenant_id) or app.is_supreme_admin())));

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable
-- revoke of PostgreSQL's PUBLIC-execute default, the standing per-migration
-- convention since PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant select on app.finance_invoices to authenticated, service_role;
grant select on app.finance_invoice_lines to authenticated, service_role;
grant insert, update, delete on app.finance_invoices to service_role;
grant insert, update, delete on app.finance_invoice_lines to service_role;
grant select, insert, update on app.finance_invoice_number_counters to service_role;

grant execute on function app.touch_finance_invoice_row() to service_role;
grant execute on function app.check_finance_invoice_authority(text, uuid, uuid) to service_role;
grant execute on function app.prepare_finance_invoice_from_readiness(uuid, uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.submit_finance_invoice_for_approval(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.discard_finance_invoice_draft(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.approve_finance_invoice(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.issue_finance_invoice(uuid, integer, date, uuid, text) to authenticated, service_role;
grant execute on function app.list_finance_invoices(uuid, uuid, uuid, text, uuid) to authenticated, service_role;
grant execute on function app.get_finance_invoice_lines(uuid, uuid) to authenticated, service_role;
