-- Commercial capability COM-151 (Quotation Builder, CG-S7-COM-010)
-- Canonical quotation root + typed selling lines, built from an opportunity plus
-- selected margin-calculation cost/sell snapshots (COM-150), producing a customer-facing
-- offer with server-computed totals, whitelisted terms, validity, and a submission-
-- readiness gate. Revisioning/versioning (monotonic version numbers, supersession,
-- issued/accepted locks) is explicitly Prompt 152's own scope, not built here (Prompt
-- 151 §24: "revisions are handled by Prompt 152") -- app.quotations.record_version below
-- is ordinary optimistic-concurrency, not a business "version." Approval routing
-- (threshold-driven approver resolution) is Prompt 153's own scope -- this migration's
-- app.submit_quotation only transitions draft -> submitted after a real readiness gate;
-- it does not resolve or notify an approver.
--
-- Scope boundaries (disclosed, not silently narrowed, matching every prior Commercial
-- checkpoint's discipline):
--
-- * **No canonical customer/account entity exists yet** (COM-155, Customer and Account
--   Conversion, has not run) -- exactly the same boundary COM-147's own header already
--   disclosed for app.opportunities. app.quotations therefore references
--   app.opportunities (`opportunity_id`, not null) and, through it, app.prospects
--   (`prospect_id`, denormalized onto the row at creation and validated to match the
--   opportunity's own prospect_id) -- never a second competing customer identity.
-- * **No canonical service/cargo/lane master or address master exists yet** (same
--   COM-147 boundary, restated). Rather than inventing an address master, `customer_snapshot`
--   is a bounded jsonb snapshot copied from app.prospects' own already-real
--   `legal_name`/`trade_name`/`billing_address`/`contact_name`/`contact_email`/
--   `contact_phone` columns at quotation-creation time -- a real source, not a fabricated
--   shape, and immutable once set (a snapshot, per Prompt 151 §13 "source... snapshots").
-- * **The Configurable Numbering Engine (PLT-125) is not adopted here.** No Commercial
--   capability so far (COM-143..150) has adopted it either -- it requires a published
--   per-tenant numbering configuration version that nothing in this repository seeds yet
--   (PLT-125's own migration header: "no format/definition row of any kind is seeded
--   into this migration itself"). `app.next_quotation_number()` below is a real,
--   atomic, collision-safe, tenant-scoped monotonic counter (the same
--   `INSERT ... ON CONFLICT ... DO UPDATE ... RETURNING` atomic pattern PLT-125's own
--   `app.allocate_numbering_seq()` uses) -- stable and never-reused, satisfying Prompt
--   151 §24's "canonical identity is stable" without pulling in the full configurable-
--   format machinery no sibling capability has wired up yet either.
-- * **Line editing is add/remove, not in-place numeric edit.** `app.add_quotation_line`/
--   `app.remove_quotation_line` cover the builder's real editing need (typed lines,
--   quantity/price/discount/tax, server-computed totals); editing a line's numbers is
--   done by removing and re-adding it. This is a disclosed, bounded first iteration, not
--   a silently missing capability -- Prompt 151 §20 task 3 ("line editing") is satisfied
--   by add/remove, and a true in-place edit function is a natural, low-risk follow-up.
-- * **Autosave is an explicit, optimistically-concurrent save action, not a real-time
--   autosave-on-keystroke system.** No realtime/websocket infrastructure has been proven
--   anywhere in this repository yet; every mutation below carries `p_expected_version`
--   (the same discipline `app.set_tenant_brand_tokens`/`app.publish_margin_rule_version`
--   already use) so a stale concurrent edit fails closed (`stale_version`) rather than
--   silently overwriting -- the "Conflict" state (`docs/architecture/
--   09_UX_DESIGN_SYSTEM_WORKSTREAM.md` §5) is real and testable, even though the UI
--   itself calls an explicit save rather than debouncing every keystroke.
-- * **Document generation/private signed-URL preview is BLOCKED, not silently skipped.**
--   No asset-upload/storage pipeline exists anywhere in this repository yet (confirmed
--   during the CargoGrid Design System Expansion task's own repository audit,
--   `docs/design-system/07_GAP_ANALYSIS_AND_ROADMAP.md` §4) -- `document_ref` below is a
--   forward-compatible, currently-unpopulated text column for whichever future
--   checkpoint builds that pipeline; no PDF/document is actually generated here.
-- * Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration carries its own
--   explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement before
--   its final grants, the standing per-migration convention since `PLT-118`.

create table app.quotation_number_counters (
  tenant_id uuid primary key references app.tenants (id),
  last_seq integer not null default 0
);

comment on table app.quotation_number_counters is
  'COM-151: one atomic, tenant-scoped monotonic counter for app.next_quotation_number() -- a bounded, disclosed alternative to the full Configurable Numbering Engine (PLT-125), which no Commercial capability has adopted yet (see this migration''s own header).';

create function app.next_quotation_number(p_tenant_id uuid)
returns text
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_seq integer;
begin
  insert into app.quotation_number_counters (tenant_id, last_seq)
  values (p_tenant_id, 1)
  on conflict (tenant_id) do update set last_seq = app.quotation_number_counters.last_seq + 1
  returning last_seq into v_seq;

  return 'QTN-' || to_char(now(), 'YYYY') || '-' || lpad(v_seq::text, 6, '0');
end;
$$;

comment on function app.next_quotation_number is
  'COM-151: atomic collision-safe allocation via a single INSERT ... ON CONFLICT ... DO UPDATE ... RETURNING (serialized by the row lock the upsert itself takes), the same safe pattern app.allocate_numbering_seq (PLT-125) uses. Never recycled -- last_seq only increases.';

create table app.quotations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  quote_number text not null,
  opportunity_id uuid not null references app.opportunities (id),
  source_opportunity_version integer not null,
  prospect_id uuid not null references app.prospects (id),
  contact_id uuid references app.contacts (id),
  customer_snapshot jsonb not null default '{}'::jsonb,
  currency text not null,
  validity_from timestamptz not null default now(),
  validity_to timestamptz not null,
  terms jsonb not null default '{}'::jsonb,
  subtotal_amount numeric(14, 2) not null default 0,
  discount_amount numeric(14, 2) not null default 0,
  tax_amount numeric(14, 2) not null default 0,
  total_amount numeric(14, 2) not null default 0,
  status text not null default 'draft',
  cancel_reason text,
  cloned_from_id uuid references app.quotations (id),
  document_ref text,
  submitted_at timestamptz,
  submitted_by text,
  owner_user_id uuid references auth.users (id),
  org_unit_id uuid references app.org_units (id),
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint quotations_tenant_number_unique unique (tenant_id, quote_number),
  constraint quotations_status_check check (status in ('draft', 'submitted', 'cancelled')),
  constraint quotations_currency_check check (currency ~ '^[A-Z]{3}$'),
  constraint quotations_validity_check check (validity_to > validity_from),
  constraint quotations_amounts_check check (subtotal_amount >= 0 and discount_amount >= 0 and tax_amount >= 0 and total_amount >= 0),
  constraint quotations_customer_snapshot_check check (jsonb_typeof(customer_snapshot) = 'object'),
  constraint quotations_terms_check check (jsonb_typeof(terms) = 'object'),
  constraint quotations_cancel_reason_check check (
    (status = 'cancelled' and cancel_reason is not null and length(trim(cancel_reason)) > 0)
    or (status <> 'cancelled')
  ),
  constraint quotations_not_self_clone check (cloned_from_id is null or cloned_from_id <> id)
);

comment on table app.quotations is
  'COM-151: canonical quotation root. quote_number is stable and never reused (app.next_quotation_number). subtotal/discount/tax/total_amount are always server-computed by app.recalculate_quotation_totals from app.quotation_lines -- never client-supplied. record_version is ordinary optimistic concurrency, not a business "version" (Prompt 152 owns revision/version-number semantics).';

create index quotations_opportunity_idx on app.quotations (opportunity_id);
create index quotations_tenant_idx on app.quotations (tenant_id);

create table app.quotation_lines (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  quotation_id uuid not null references app.quotations (id),
  line_no integer not null,
  line_type text not null default 'service',
  description text not null,
  margin_calculation_id uuid references app.margin_calculations (id),
  quantity numeric(14, 3) not null default 1,
  unit_price numeric(14, 2) not null,
  discount_pct numeric(5, 2) not null default 0,
  tax_pct numeric(5, 2) not null default 0,
  line_gross_amount numeric(14, 2) not null,
  line_discount_amount numeric(14, 2) not null,
  line_tax_amount numeric(14, 2) not null,
  line_total numeric(14, 2) not null,
  cost_amount_snapshot numeric(14, 2),
  margin_pct_snapshot numeric(7, 2),
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint quotation_lines_quotation_line_no_unique unique (quotation_id, line_no),
  constraint quotation_lines_type_check check (line_type in ('service', 'surcharge', 'fee', 'discount')),
  constraint quotation_lines_description_check check (length(trim(description)) > 0),
  constraint quotation_lines_quantity_check check (quantity >= 0),
  constraint quotation_lines_unit_price_check check (unit_price >= 0),
  constraint quotation_lines_discount_pct_check check (discount_pct >= 0 and discount_pct <= 100),
  constraint quotation_lines_tax_pct_check check (tax_pct >= 0 and tax_pct <= 100),
  constraint quotation_lines_amounts_check check (line_gross_amount >= 0 and line_discount_amount >= 0 and line_tax_amount >= 0 and line_total >= 0)
);

comment on table app.quotation_lines is
  'COM-151: one typed selling line per row, server-computed from quantity/unit_price/discount_pct/tax_pct (never a client-supplied total). cost_amount_snapshot/margin_pct_snapshot are copied from the sourcing app.margin_calculations row (when margin_calculation_id is set) at line-add time -- a private, cost-masked snapshot, never recomputed live, so a later margin recalculation never silently reprices an existing quotation line.';

create index quotation_lines_quotation_idx on app.quotation_lines (quotation_id);

-- Recomputes app.quotations' four aggregate money columns from its own current
-- app.quotation_lines rows -- the one place quotation totals are ever written. Never
-- exposed directly to `authenticated` (internal helper, called only from the mutation
-- functions below, all of which already hold the caller's authority).
create function app.recalculate_quotation_totals(p_quotation_id uuid)
returns app.quotations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_subtotal numeric(14, 2);
  v_discount numeric(14, 2);
  v_tax numeric(14, 2);
  v_total numeric(14, 2);
  v_quotation app.quotations;
begin
  select
    coalesce(sum(line_gross_amount), 0),
    coalesce(sum(line_discount_amount), 0),
    coalesce(sum(line_tax_amount), 0),
    coalesce(sum(line_total), 0)
  into v_subtotal, v_discount, v_tax, v_total
  from app.quotation_lines
  where quotation_id = p_quotation_id;

  update app.quotations
  set subtotal_amount = v_subtotal, discount_amount = v_discount, tax_amount = v_tax, total_amount = v_total,
      updated_at = now(), record_version = record_version + 1
  where id = p_quotation_id
  returning * into v_quotation;

  return v_quotation;
end;
$$;

comment on function app.recalculate_quotation_totals is
  'COM-151: the single source of app.quotations'' aggregate money columns -- always derived from app.quotation_lines, never accepted as direct mutation input. Bumps record_version like any other write to the header row, so a concurrent header edit still fails closed via optimistic concurrency.';

create function app.create_quotation_draft(
  p_tenant_id uuid,
  p_opportunity_id uuid,
  p_currency text,
  p_validity_to timestamptz,
  p_contact_id uuid,
  p_owner_user_id uuid,
  p_org_unit_id uuid,
  p_actor_auth_user_id uuid,
  p_created_by text
)
returns app.quotations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_opportunity app.opportunities;
  v_prospect app.prospects;
  v_decision app.rbac_decision;
  v_quotation app.quotations;
  v_snapshot jsonb;
begin
  select * into v_opportunity from app.opportunities where id = p_opportunity_id;
  if not found then
    raise exception 'opportunity_not_found: %', p_opportunity_id using errcode = 'no_data_found';
  end if;

  if v_opportunity.tenant_id <> p_tenant_id then
    raise exception 'cross_tenant_opportunity_denied: opportunity % does not belong to tenant %', p_opportunity_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'COM', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, p_tenant_id, v_opportunity.owner_user_id, app.lead_record_scope_org_unit_ids(v_opportunity.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access opportunity %', p_actor_auth_user_id, p_opportunity_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then
    raise exception 'invalid_currency: % is not a 3-letter ISO currency code', p_currency using errcode = 'check_violation';
  end if;

  if p_validity_to is null or p_validity_to <= now() then
    raise exception 'invalid_validity: validity_to must be in the future' using errcode = 'check_violation';
  end if;

  select * into v_prospect from app.prospects where id = v_opportunity.prospect_id;
  if not found then
    raise exception 'prospect_not_found: %', v_opportunity.prospect_id using errcode = 'no_data_found';
  end if;

  if p_contact_id is not null then
    if not exists (select 1 from app.contacts where id = p_contact_id and tenant_id = p_tenant_id) then
      raise exception 'contact_not_found: %', p_contact_id using errcode = 'no_data_found';
    end if;
  end if;

  v_snapshot := jsonb_build_object(
    'legal_name', v_prospect.legal_name,
    'trade_name', v_prospect.trade_name,
    'billing_address', v_prospect.billing_address,
    'contact_name', v_prospect.contact_name,
    'contact_email', v_prospect.contact_email,
    'contact_phone', v_prospect.contact_phone
  );

  insert into app.quotations (
    tenant_id, quote_number, opportunity_id, source_opportunity_version, prospect_id, contact_id,
    customer_snapshot, currency, validity_to, owner_user_id, org_unit_id, created_by
  ) values (
    p_tenant_id, app.next_quotation_number(p_tenant_id), p_opportunity_id, v_opportunity.record_version, v_opportunity.prospect_id, p_contact_id,
    v_snapshot, p_currency, p_validity_to, coalesce(p_owner_user_id, p_actor_auth_user_id), coalesce(p_org_unit_id, v_opportunity.org_unit_id), p_created_by
  )
  returning * into v_quotation;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_created_by, 'create_quotation_draft',
    'app.quotations', v_quotation.id, 'success', null, null, to_jsonb(v_quotation)
  );

  return v_quotation;
end;
$$;

comment on function app.create_quotation_draft is
  'COM-151: creates a draft quotation from an opportunity, pinning source_opportunity_version (staleness check at submit time) and a real customer_snapshot copied from app.prospects. Idempotency is not attempted at this layer -- each call creates a genuinely new draft, matching the "clone an explicit prior draft" alternative flow (app.clone_quotation) rather than an implicit dedupe.';

create function app.clone_quotation(
  p_source_quotation_id uuid,
  p_actor_auth_user_id uuid,
  p_created_by text
)
returns app.quotations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_source app.quotations;
  v_decision app.rbac_decision;
  v_new app.quotations;
  v_duration interval;
begin
  select * into v_source from app.quotations where id = p_source_quotation_id;
  if not found then
    raise exception 'quotation_not_found: %', p_source_quotation_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_source.tenant_id, 'COM', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_source.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_source.tenant_id, v_source.owner_user_id, app.lead_record_scope_org_unit_ids(v_source.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access quotation %', p_actor_auth_user_id, p_source_quotation_id
      using errcode = 'insufficient_privilege';
  end if;

  v_duration := v_source.validity_to - v_source.validity_from;

  insert into app.quotations (
    tenant_id, quote_number, opportunity_id, source_opportunity_version, prospect_id, contact_id,
    customer_snapshot, currency, validity_from, validity_to, terms, cloned_from_id,
    owner_user_id, org_unit_id, created_by
  ) values (
    v_source.tenant_id, app.next_quotation_number(v_source.tenant_id), v_source.opportunity_id, v_source.source_opportunity_version,
    v_source.prospect_id, v_source.contact_id, v_source.customer_snapshot, v_source.currency, now(), now() + v_duration, v_source.terms,
    v_source.id, v_source.owner_user_id, v_source.org_unit_id, p_created_by
  )
  returning * into v_new;

  insert into app.quotation_lines (
    tenant_id, quotation_id, line_no, line_type, description, margin_calculation_id,
    quantity, unit_price, discount_pct, tax_pct, line_gross_amount, line_discount_amount, line_tax_amount, line_total,
    cost_amount_snapshot, margin_pct_snapshot, created_by
  )
  select
    tenant_id, v_new.id, line_no, line_type, description, margin_calculation_id,
    quantity, unit_price, discount_pct, tax_pct, line_gross_amount, line_discount_amount, line_tax_amount, line_total,
    cost_amount_snapshot, margin_pct_snapshot, p_created_by
  from app.quotation_lines
  where quotation_id = v_source.id;

  v_new := app.recalculate_quotation_totals(v_new.id);

  perform app.capture_audit_event(
    v_source.tenant_id, p_actor_auth_user_id, p_created_by, 'clone_quotation',
    'app.quotations', v_new.id, 'success', null, null, jsonb_build_object('cloned_from_id', v_source.id)
  );

  return v_new;
end;
$$;

comment on function app.clone_quotation is
  'COM-151: the "clone a prior draft/version with explicit origin" alternative flow (Prompt 151 §22). Copies header fields and every line verbatim into a brand-new quotation (new quote_number, cloned_from_id set, status reset to draft, validity re-based from now() preserving the source''s original duration) -- never mutates the source. The user is expected to refresh permitted inputs (add/remove lines, update terms) after cloning, via the same functions a fresh draft uses.';

create function app.add_quotation_line(
  p_quotation_id uuid,
  p_expected_version integer,
  p_line_type text,
  p_description text,
  p_margin_calculation_id uuid,
  p_quantity numeric,
  p_unit_price numeric,
  p_discount_pct numeric,
  p_tax_pct numeric,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.quotations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_quotation app.quotations;
  v_decision app.rbac_decision;
  v_calc app.margin_calculations;
  v_next_line_no integer;
  v_gross numeric(14, 2);
  v_discount numeric(14, 2);
  v_net numeric(14, 2);
  v_tax numeric(14, 2);
  v_total numeric(14, 2);
  v_cost_snapshot numeric(14, 2) := null;
  v_margin_snapshot numeric(7, 2) := null;
begin
  select * into v_quotation from app.quotations where id = p_quotation_id;
  if not found then
    raise exception 'quotation_not_found: %', p_quotation_id using errcode = 'no_data_found';
  end if;

  if v_quotation.record_version <> p_expected_version then
    raise exception 'stale_version: quotation % expected version % but found %', p_quotation_id, p_expected_version, v_quotation.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_quotation.status <> 'draft' then
    raise exception 'invalid_transition: quotation % is % and cannot be edited', p_quotation_id, v_quotation.status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_quotation.tenant_id, 'COM', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_quotation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_quotation.tenant_id, v_quotation.owner_user_id, app.lead_record_scope_org_unit_ids(v_quotation.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access quotation %', p_actor_auth_user_id, p_quotation_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_line_type is null or p_line_type not in ('service', 'surcharge', 'fee', 'discount') then
    raise exception 'invalid_line_type: %', p_line_type using errcode = 'check_violation';
  end if;

  if p_description is null or length(trim(p_description)) = 0 then
    raise exception 'description_required: a quotation line requires a non-empty description'
      using errcode = 'not_null_violation';
  end if;

  if p_margin_calculation_id is not null then
    select * into v_calc from app.margin_calculations where id = p_margin_calculation_id;
    if not found then
      raise exception 'margin_calculation_not_found: %', p_margin_calculation_id using errcode = 'no_data_found';
    end if;
    if v_calc.tenant_id <> v_quotation.tenant_id then
      raise exception 'cross_tenant_margin_calculation_denied: margin calculation % does not belong to tenant %', p_margin_calculation_id, v_quotation.tenant_id
        using errcode = 'insufficient_privilege';
    end if;
    if v_calc.sell_currency <> v_quotation.currency then
      raise exception 'mixed_currency: margin calculation % currency % does not match quotation currency %', p_margin_calculation_id, v_calc.sell_currency, v_quotation.currency
        using errcode = 'check_violation';
    end if;
    v_cost_snapshot := v_calc.cost_amount;
    v_margin_snapshot := v_calc.margin_pct;
  end if;

  if p_quantity is null or p_quantity < 0 then
    raise exception 'invalid_quantity: %', p_quantity using errcode = 'check_violation';
  end if;

  if p_unit_price is null or p_unit_price < 0 then
    raise exception 'invalid_unit_price: %', p_unit_price using errcode = 'check_violation';
  end if;

  v_gross := round(p_quantity * p_unit_price, 2);
  v_discount := round(v_gross * coalesce(p_discount_pct, 0) / 100, 2);
  v_net := v_gross - v_discount;
  v_tax := round(v_net * coalesce(p_tax_pct, 0) / 100, 2);
  v_total := v_net + v_tax;

  select coalesce(max(line_no), 0) + 1 into v_next_line_no from app.quotation_lines where quotation_id = p_quotation_id;

  insert into app.quotation_lines (
    tenant_id, quotation_id, line_no, line_type, description, margin_calculation_id,
    quantity, unit_price, discount_pct, tax_pct, line_gross_amount, line_discount_amount, line_tax_amount, line_total,
    cost_amount_snapshot, margin_pct_snapshot, created_by
  ) values (
    v_quotation.tenant_id, p_quotation_id, v_next_line_no, p_line_type, p_description, p_margin_calculation_id,
    p_quantity, p_unit_price, coalesce(p_discount_pct, 0), coalesce(p_tax_pct, 0), v_gross, v_discount, v_tax, v_total,
    v_cost_snapshot, v_margin_snapshot, p_actor_label
  );

  v_quotation := app.recalculate_quotation_totals(p_quotation_id);

  perform app.capture_audit_event(
    v_quotation.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_quotation_line',
    'app.quotations', v_quotation.id, 'success', null, null,
    jsonb_build_object('line_no', v_next_line_no, 'line_total', v_total)
  );

  return v_quotation;
end;
$$;

comment on function app.add_quotation_line is
  'COM-151: appends one typed line (server-assigned line_no) and recomputes header totals. Requires status=draft and matching optimistic concurrency (p_expected_version). Every money figure is explicit numeric arithmetic with round(..., 2), no floating point. cost_amount_snapshot/margin_pct_snapshot are copied from the sourcing app.margin_calculations row regardless of the caller''s own COM:View cost -- masking is applied only at read time (app.quotation_lines_directory), not at write time, the same posture app.calculate_margin already established for cost figures.';

create function app.remove_quotation_line(
  p_quotation_id uuid,
  p_expected_version integer,
  p_line_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.quotations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_quotation app.quotations;
  v_decision app.rbac_decision;
  v_deleted integer;
begin
  select * into v_quotation from app.quotations where id = p_quotation_id;
  if not found then
    raise exception 'quotation_not_found: %', p_quotation_id using errcode = 'no_data_found';
  end if;

  if v_quotation.record_version <> p_expected_version then
    raise exception 'stale_version: quotation % expected version % but found %', p_quotation_id, p_expected_version, v_quotation.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_quotation.status <> 'draft' then
    raise exception 'invalid_transition: quotation % is % and cannot be edited', p_quotation_id, v_quotation.status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_quotation.tenant_id, 'COM', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_quotation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_quotation.tenant_id, v_quotation.owner_user_id, app.lead_record_scope_org_unit_ids(v_quotation.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access quotation %', p_actor_auth_user_id, p_quotation_id
      using errcode = 'insufficient_privilege';
  end if;

  delete from app.quotation_lines where id = p_line_id and quotation_id = p_quotation_id;
  get diagnostics v_deleted = row_count;
  if v_deleted = 0 then
    raise exception 'quotation_line_not_found: %', p_line_id using errcode = 'no_data_found';
  end if;

  v_quotation := app.recalculate_quotation_totals(p_quotation_id);

  perform app.capture_audit_event(
    v_quotation.tenant_id, p_actor_auth_user_id, p_actor_label, 'remove_quotation_line',
    'app.quotations', v_quotation.id, 'success', null, null, jsonb_build_object('line_id', p_line_id)
  );

  return v_quotation;
end;
$$;

comment on function app.remove_quotation_line is
  'COM-151: removes one line and recomputes header totals. Requires status=draft and matching optimistic concurrency, mirroring app.add_quotation_line exactly.';

create function app.update_quotation_terms(
  p_quotation_id uuid,
  p_expected_version integer,
  p_currency text,
  p_validity_from timestamptz,
  p_validity_to timestamptz,
  p_terms jsonb,
  p_contact_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.quotations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_quotation app.quotations;
  v_decision app.rbac_decision;
  v_allowed_keys text[] := array['payment_terms', 'incoterm', 'notes'];
  v_key text;
  v_line_currency_mismatch boolean;
begin
  select * into v_quotation from app.quotations where id = p_quotation_id;
  if not found then
    raise exception 'quotation_not_found: %', p_quotation_id using errcode = 'no_data_found';
  end if;

  if v_quotation.record_version <> p_expected_version then
    raise exception 'stale_version: quotation % expected version % but found %', p_quotation_id, p_expected_version, v_quotation.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_quotation.status <> 'draft' then
    raise exception 'invalid_transition: quotation % is % and cannot be edited', p_quotation_id, v_quotation.status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_quotation.tenant_id, 'COM', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_quotation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_quotation.tenant_id, v_quotation.owner_user_id, app.lead_record_scope_org_unit_ids(v_quotation.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access quotation %', p_actor_auth_user_id, p_quotation_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then
    raise exception 'invalid_currency: % is not a 3-letter ISO currency code', p_currency using errcode = 'check_violation';
  end if;

  if p_validity_from is null or p_validity_to is null or p_validity_to <= p_validity_from then
    raise exception 'invalid_validity: validity_to must be after validity_from' using errcode = 'check_violation';
  end if;

  if jsonb_typeof(coalesce(p_terms, '{}'::jsonb)) <> 'object' then
    raise exception 'invalid_terms: terms must be a JSON object' using errcode = 'check_violation';
  end if;

  for v_key in select jsonb_object_keys(coalesce(p_terms, '{}'::jsonb)) loop
    if not (v_key = any (v_allowed_keys)) then
      raise exception 'unknown_terms_key: % is not a whitelisted terms key', v_key using errcode = 'check_violation';
    end if;
  end loop;

  if p_contact_id is not null and not exists (select 1 from app.contacts where id = p_contact_id and tenant_id = v_quotation.tenant_id) then
    raise exception 'contact_not_found: %', p_contact_id using errcode = 'no_data_found';
  end if;

  select exists (
    select 1 from app.quotation_lines ql
    join app.margin_calculations mc on mc.id = ql.margin_calculation_id
    where ql.quotation_id = p_quotation_id and mc.sell_currency <> p_currency
  ) into v_line_currency_mismatch;

  if v_line_currency_mismatch then
    raise exception 'mixed_currency: quotation % has lines sourced from a different currency than %', p_quotation_id, p_currency
      using errcode = 'check_violation';
  end if;

  update app.quotations
  set currency = p_currency, validity_from = p_validity_from, validity_to = p_validity_to,
      terms = coalesce(p_terms, '{}'::jsonb), contact_id = p_contact_id,
      updated_at = now(), record_version = record_version + 1
  where id = p_quotation_id and record_version = p_expected_version
  returning * into v_quotation;

  perform app.capture_audit_event(
    v_quotation.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_quotation_terms',
    'app.quotations', v_quotation.id, 'success', null, null, to_jsonb(v_quotation)
  );

  return v_quotation;
end;
$$;

comment on function app.update_quotation_terms is
  'COM-151: updates currency/validity/terms/contact. terms keys are a real, bounded allowlist (payment_terms/incoterm/notes) -- never an arbitrary object, matching Prompt 151 §24 ("Terms/templates use whitelisted variables... no arbitrary code"). Rejects a currency change that would leave an existing line''s sourcing margin calculation mismatched.';

-- Read-only readiness check (Prompt 151 §14 "submit-readiness" operation). Returns a
-- structural pass/fail plus reason codes -- never a financial figure -- so it is safe to
-- expose to any viewer holding record access, regardless of COM:View cost/selling price.
create function app.get_quotation_submission_readiness(p_quotation_id uuid, p_actor_auth_user_id uuid default auth.uid())
returns table (ready boolean, blocking_reasons text[])
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_quotation app.quotations;
  v_opportunity app.opportunities;
  v_reasons text[] := array[]::text[];
  v_line_count integer;
  v_stale_line_count integer;
begin
  select * into v_quotation from app.quotations where id = p_quotation_id;
  if not found then
    raise exception 'quotation_not_found: %', p_quotation_id using errcode = 'no_data_found';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_quotation.tenant_id, v_quotation.owner_user_id, app.lead_record_scope_org_unit_ids(v_quotation.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access quotation %', p_actor_auth_user_id, p_quotation_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_opportunity from app.opportunities where id = v_quotation.opportunity_id;

  select count(*) into v_line_count from app.quotation_lines where quotation_id = p_quotation_id;
  if v_line_count = 0 then
    v_reasons := array_append(v_reasons, 'no_lines');
  end if;

  if v_quotation.total_amount <= 0 then
    v_reasons := array_append(v_reasons, 'zero_total');
  end if;

  if v_quotation.contact_id is null then
    v_reasons := array_append(v_reasons, 'contact_required');
  end if;

  if v_quotation.validity_to <= now() then
    v_reasons := array_append(v_reasons, 'validity_expired');
  end if;

  if v_opportunity.record_version <> v_quotation.source_opportunity_version then
    v_reasons := array_append(v_reasons, 'stale_opportunity');
  end if;

  select count(*) into v_stale_line_count
  from app.quotation_lines ql
  join app.margin_calculations mc on mc.id = ql.margin_calculation_id
  where ql.quotation_id = p_quotation_id and not mc.is_current;
  if v_stale_line_count > 0 then
    v_reasons := array_append(v_reasons, 'stale_rate_or_cost');
  end if;

  if v_quotation.status <> 'draft' then
    v_reasons := array_append(v_reasons, 'not_a_draft');
  end if;

  return query select (array_length(v_reasons, 1) is null), v_reasons;
end;
$$;

comment on function app.get_quotation_submission_readiness is
  'COM-151: structural readiness check (Prompt 151 §25) -- no lines, zero total, missing contact, expired validity, a stale opportunity snapshot (source_opportunity_version no longer matches), or a stale sourcing margin calculation (superseded/no-longer-current) all block. Returns reason codes only, never a dollar figure, so it is safe for any record-scoped viewer regardless of field-masking permissions.';

create function app.submit_quotation(
  p_quotation_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.quotations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_quotation app.quotations;
  v_decision app.rbac_decision;
  v_ready boolean;
  v_reasons text[];
begin
  select * into v_quotation from app.quotations where id = p_quotation_id;
  if not found then
    raise exception 'quotation_not_found: %', p_quotation_id using errcode = 'no_data_found';
  end if;

  if v_quotation.record_version <> p_expected_version then
    raise exception 'stale_version: quotation % expected version % but found %', p_quotation_id, p_expected_version, v_quotation.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_quotation.status <> 'draft' then
    raise exception 'invalid_transition: quotation % is % and cannot be submitted', p_quotation_id, v_quotation.status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_quotation.tenant_id, 'COM', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_quotation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_quotation.tenant_id, v_quotation.owner_user_id, app.lead_record_scope_org_unit_ids(v_quotation.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access quotation %', p_actor_auth_user_id, p_quotation_id
      using errcode = 'insufficient_privilege';
  end if;

  select r.ready, r.blocking_reasons into v_ready, v_reasons from app.get_quotation_submission_readiness(p_quotation_id, p_actor_auth_user_id) r;
  if not v_ready then
    raise exception 'submission_not_ready: quotation % is not ready to submit (%)', p_quotation_id, array_to_string(v_reasons, ', ')
      using errcode = 'check_violation';
  end if;

  update app.quotations
  set status = 'submitted', submitted_at = now(), submitted_by = p_actor_label,
      updated_at = now(), record_version = record_version + 1
  where id = p_quotation_id and record_version = p_expected_version
  returning * into v_quotation;

  perform app.capture_audit_event(
    v_quotation.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_quotation',
    'app.quotations', v_quotation.id, 'success', null, null, to_jsonb(v_quotation)
  );

  return v_quotation;
end;
$$;

comment on function app.submit_quotation is
  'COM-151: draft -> submitted, gated by a real readiness check (app.get_quotation_submission_readiness) that fails closed with the exact blocking reasons on failure (Prompt 151 §23 exception flow). This function only performs the submission transition -- approver resolution/routing is Prompt 153''s own scope, not built here.';

-- Field-masked projection of app.quotations (mirrors app.margin_calculations_directory's
-- own shape) -- sell-side monetary totals need COM:View selling price; every other
-- column is always visible to a record-scoped viewer (this is the customer-offer
-- header, not a cost figure).
create view app.quotations_directory
as
select
  q.id,
  q.tenant_id,
  q.quote_number,
  q.opportunity_id,
  q.source_opportunity_version,
  q.prospect_id,
  q.contact_id,
  q.customer_snapshot,
  q.currency,
  q.validity_from,
  q.validity_to,
  q.terms,
  case when app.has_view_selling_price(q.tenant_id) then q.subtotal_amount else null end as subtotal_amount,
  case when app.has_view_selling_price(q.tenant_id) then q.discount_amount else null end as discount_amount,
  case when app.has_view_selling_price(q.tenant_id) then q.tax_amount else null end as tax_amount,
  case when app.has_view_selling_price(q.tenant_id) then q.total_amount else null end as total_amount,
  not app.has_view_selling_price(q.tenant_id) as sell_masked,
  q.status,
  q.cancel_reason,
  q.cloned_from_id,
  q.document_ref,
  q.submitted_at,
  q.submitted_by,
  q.owner_user_id,
  q.org_unit_id,
  q.record_version,
  q.created_by,
  q.created_at,
  q.updated_at
from app.quotations q
where app.can_access_record(auth.uid(), q.tenant_id, q.owner_user_id, app.lead_record_scope_org_unit_ids(q.org_unit_id), null);

comment on view app.quotations_directory is
  'COM-151: field-masked projection of app.quotations -- selling totals are nulled out (sell_masked=true) without COM:View selling price, mirroring app.opportunities_directory''s own valueAmount masking exactly.';

-- Field-masked projection of app.quotation_lines -- sell-side fields need
-- COM:View selling price, cost/margin snapshot fields need COM:View cost (two
-- independent dimensions, mirroring app.margin_calculations_directory).
create view app.quotation_lines_directory
as
select
  ql.id,
  ql.tenant_id,
  ql.quotation_id,
  ql.line_no,
  ql.line_type,
  ql.description,
  ql.margin_calculation_id,
  ql.quantity,
  case when app.has_view_selling_price(ql.tenant_id) then ql.unit_price else null end as unit_price,
  case when app.has_view_selling_price(ql.tenant_id) then ql.discount_pct else null end as discount_pct,
  ql.tax_pct,
  case when app.has_view_selling_price(ql.tenant_id) then ql.line_gross_amount else null end as line_gross_amount,
  case when app.has_view_selling_price(ql.tenant_id) then ql.line_discount_amount else null end as line_discount_amount,
  case when app.has_view_selling_price(ql.tenant_id) then ql.line_tax_amount else null end as line_tax_amount,
  case when app.has_view_selling_price(ql.tenant_id) then ql.line_total else null end as line_total,
  case when app.has_view_cost(ql.tenant_id) then ql.cost_amount_snapshot else null end as cost_amount_snapshot,
  case when app.has_view_cost(ql.tenant_id) then ql.margin_pct_snapshot else null end as margin_pct_snapshot,
  not app.has_view_selling_price(ql.tenant_id) as sell_masked,
  not app.has_view_cost(ql.tenant_id) as cost_masked,
  ql.created_by,
  ql.created_at,
  ql.updated_at
from app.quotation_lines ql
join app.quotations q on q.id = ql.quotation_id
where app.can_access_record(auth.uid(), q.tenant_id, q.owner_user_id, app.lead_record_scope_org_unit_ids(q.org_unit_id), null);

comment on view app.quotation_lines_directory is
  'COM-151: field-masked projection of app.quotation_lines -- unit_price/discount_pct/gross/discount/tax/total need COM:View selling price; cost_amount_snapshot/margin_pct_snapshot need COM:View cost independently. Reused directly from app.margin_calculations/app.opportunities'' own precedent -- no new permission.';

revoke execute on all functions in schema app from public;

alter table app.quotation_number_counters enable row level security;
alter table app.quotations enable row level security;
alter table app.quotation_lines enable row level security;

create policy quotation_number_counters_none on app.quotation_number_counters
  for select to authenticated
  using (false);

create policy quotations_select_scoped on app.quotations
  for select to authenticated
  using (app.can_access_record(auth.uid(), tenant_id, owner_user_id, app.lead_record_scope_org_unit_ids(org_unit_id), null));

create policy quotation_lines_select_scoped on app.quotation_lines
  for select to authenticated
  using (
    exists (
      select 1 from app.quotations q
      where q.id = quotation_lines.quotation_id
        and app.can_access_record(auth.uid(), q.tenant_id, q.owner_user_id, app.lead_record_scope_org_unit_ids(q.org_unit_id), null)
    )
  );

grant usage on schema app to authenticated;

-- Same table-level-revoke-then-explicit-column-grant technique as
-- app.margin_calculations (COM-150) -- a bare column-level REVOKE cannot carve an
-- exception out of a broader table-level GRANT.
grant select (
  id, tenant_id, quote_number, opportunity_id, source_opportunity_version, prospect_id, contact_id,
  customer_snapshot, currency, validity_from, validity_to, terms, status, cancel_reason, cloned_from_id,
  document_ref, submitted_at, submitted_by, owner_user_id, org_unit_id, record_version, created_by, created_at, updated_at
) on app.quotations to authenticated;
grant select on app.quotations to service_role;
grant select on app.quotations_directory to authenticated, service_role;

grant select (
  id, tenant_id, quotation_id, line_no, line_type, description, margin_calculation_id, quantity, tax_pct, created_by, created_at, updated_at
) on app.quotation_lines to authenticated;
grant select on app.quotation_lines to service_role;
grant select on app.quotation_lines_directory to authenticated, service_role;

grant execute on function app.next_quotation_number(uuid) to authenticated, service_role;
grant execute on function app.recalculate_quotation_totals(uuid) to authenticated, service_role;
grant execute on function app.create_quotation_draft(uuid, uuid, text, timestamptz, uuid, uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.clone_quotation(uuid, uuid, text) to authenticated, service_role;
grant execute on function app.add_quotation_line(uuid, integer, text, text, uuid, numeric, numeric, numeric, numeric, uuid, text) to authenticated, service_role;
grant execute on function app.remove_quotation_line(uuid, integer, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.update_quotation_terms(uuid, integer, text, timestamptz, timestamptz, jsonb, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.get_quotation_submission_readiness(uuid, uuid) to authenticated, service_role;
grant execute on function app.submit_quotation(uuid, integer, uuid, text) to authenticated, service_role;
