-- Commercial capability COM-152 (Quotation Versioning, CG-S7-COM-011)
-- Extends COM-151's app.quotations with real business versioning: a root/version
-- identity, monotonic version numbers, an is_current/superseded_by_id chain (the same
-- pattern app.margin_calculations, COM-150, already established), and normal-role lock
-- enforcement so an issued/superseded version can never be edited in place -- only
-- revised into a brand-new version.
--
-- Never edits COM-151's migration file (AGENTS.md: "never edit an applied migration") --
-- every widened function below is `CREATE OR REPLACE FUNCTION`/`CREATE OR REPLACE VIEW`
-- with an identical signature/output-column-prefix, the same technique COM-149 used on
-- `app.can_access_record` and COM-132 used on three PLT-131 functions.
--
-- Scope boundaries (disclosed, not silently narrowed):
--
-- * **"issued"/"accepted" status values do not exist yet.** Prompt 152 §23/§24 name an
--   "accepted lock" exception -- but no function anywhere in this repository (COM-153
--   Quotation Approval, COM-154 Customer Acceptance) has run yet to ever produce an
--   "approved"/"sent"/"accepted" status. Inventing those enum values now, with no real
--   producer, would be exactly the kind of ahead-of-evidence status this repository's own
--   governance forbids (the same discipline COM-146/149/150 already applied to FX/
--   per-org-unit/Phase-3 features). The lock rule this checkpoint implements is bounded
--   to what is real today: a version may be revised only while it `is_current` and its
--   `status <> 'cancelled'` -- the exact extension point for COM-153/154 to widen once
--   real approved/accepted states exist is named here, not silently assumed.
-- * **"Supersede" is not a separate user-invoked action.** Prompt 152 §14 lists it among
--   the API operations, but it is the internal side-effect `app.create_quotation_revision`
--   performs on the prior current row (`is_current=false`, `superseded_by_id` set) -- the
--   same posture `app.calculate_margin` (COM-150) already established for its own
--   supersession chain. No standalone `app.supersede_quotation_version` function exists.
-- * **"Compare" is computed in the service layer, not a new SQL function.** Two already
--   field-masked `app.quotations_directory`/`app.quotation_lines_directory` reads (one per
--   version) already carry every access-control decision that matters; the diff itself has
--   no authorization or data-integrity requirement beyond what those reads already enforce,
--   so `server/lib/quotation-version-diff.ts`* computes it in TypeScript, pure and
--   unit-tested, rather than a third SQL function with no real DB-side rule to enforce.
--   (*exact path recorded in this checkpoint's own build log, not invented here.)
-- * **RPD-022 (Supreme Admin absolute CRUD) is disclosed, not newly implemented.** Supreme
--   Admin's existing service-role/absolute-CRUD authority is a platform-wide reality this
--   migration does not alter -- these normal-role lock checks apply to `authenticated`
--   callers of `app.create_quotation_revision`/`app.add_quotation_line`/etc. only, never to
--   a Supreme-authorized service-role mutation, and this migration does not claim any
--   quotation version is tamper-proof or immutable.
-- * **Legacy data migration is not applicable.** Greenfield table, no live environment,
--   Prompt 152 §19's own "map legacy revisions" concern has no real predecessor data to map.
-- * Per `ERR-2026-004`: this migration carries its own explicit
--   `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` before its final grants.

alter table app.quotations add column root_quotation_id uuid references app.quotations (id);
alter table app.quotations add column version_number integer not null default 1;
alter table app.quotations add column is_current boolean not null default true;
alter table app.quotations add column superseded_by_id uuid references app.quotations (id);
alter table app.quotations add column revision_reason text;

-- Backfill: every quotation created before this migration is its own root, version 1
-- (COM-151 never produced more than one row per quote_number). Not exercised against real
-- data in this sandbox (no live environment/greenfield table), included for correctness on
-- principle -- the same "expand-and-backfill" discipline every prior widening migration
-- (COM-132, COM-149) already followed.
update app.quotations set root_quotation_id = id where root_quotation_id is null;

alter table app.quotations alter column root_quotation_id set not null;

-- Superseding the COM-151 unique(tenant_id, quote_number) constraint -- multiple version
-- rows now legitimately share one quote_number, distinguished by version_number.
alter table app.quotations drop constraint quotations_tenant_number_unique;
alter table app.quotations add constraint quotations_tenant_number_version_unique unique (tenant_id, quote_number, version_number);

alter table app.quotations add constraint quotations_root_version_unique unique (root_quotation_id, version_number);

-- "Only one version can hold [the current] state" (Prompt 152 §24) -- a real database
-- guarantee, the same partial-unique-index technique app.margin_calculations_current_unique
-- (COM-150) already established.
create unique index quotations_root_current_unique on app.quotations (root_quotation_id) where is_current;

create index quotations_root_idx on app.quotations (root_quotation_id);

comment on column app.quotations.root_quotation_id is
  'COM-152: the first version''s own id -- every version of one canonical quote (same quote_number) shares this value. Self-referencing for a version-1 row.';
comment on column app.quotations.version_number is
  'COM-152: 1 for the first version, monotonically incremented per root by app.create_quotation_revision. Never reused, never decremented.';
comment on column app.quotations.is_current is
  'COM-152: true for exactly one row per root_quotation_id (quotations_root_current_unique) -- the latest version. A normal-role caller can only mutate lines/terms/submit while is_current=true.';
comment on column app.quotations.revision_reason is
  'COM-152: why this version was created (mandatory for every version after the first, via app.create_quotation_revision''s p_reason) -- null only for the original version-1 row.';

-- Widens COM-151's app.create_quotation_draft to set root/version identity on the very
-- first row of a new quote -- identical signature, only the insert's own column list
-- changes. The id is generated explicitly (mirrors app.calculate_margin's v_new_id
-- pattern, COM-150) so root_quotation_id can self-reference it in the same insert.
create or replace function app.create_quotation_draft(
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
  v_new_id uuid := gen_random_uuid();
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
    id, tenant_id, quote_number, opportunity_id, source_opportunity_version, prospect_id, contact_id,
    customer_snapshot, currency, validity_to, root_quotation_id, version_number, is_current,
    owner_user_id, org_unit_id, created_by
  ) values (
    v_new_id, p_tenant_id, app.next_quotation_number(p_tenant_id), p_opportunity_id, v_opportunity.record_version, v_opportunity.prospect_id, p_contact_id,
    v_snapshot, p_currency, p_validity_to, v_new_id, 1, true,
    coalesce(p_owner_user_id, p_actor_auth_user_id), coalesce(p_org_unit_id, v_opportunity.org_unit_id), p_created_by
  )
  returning * into v_quotation;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_created_by, 'create_quotation_draft',
    'app.quotations', v_quotation.id, 'success', null, null, to_jsonb(v_quotation)
  );

  return v_quotation;
end;
$$;

-- Widens COM-151's app.clone_quotation -- a clone is always a brand-new root/version-1
-- (distinct from a revision, which shares the source's root), identical signature.
create or replace function app.clone_quotation(
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
  v_new_id uuid := gen_random_uuid();
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
    id, tenant_id, quote_number, opportunity_id, source_opportunity_version, prospect_id, contact_id,
    customer_snapshot, currency, validity_from, validity_to, terms, cloned_from_id,
    root_quotation_id, version_number, is_current,
    owner_user_id, org_unit_id, created_by
  ) values (
    v_new_id, v_source.tenant_id, app.next_quotation_number(v_source.tenant_id), v_source.opportunity_id, v_source.source_opportunity_version,
    v_source.prospect_id, v_source.contact_id, v_source.customer_snapshot, v_source.currency, now(), now() + v_duration, v_source.terms,
    v_source.id, v_new_id, 1, true,
    v_source.owner_user_id, v_source.org_unit_id, p_created_by
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

-- The core versioning function -- serves BOTH Prompt 152's main flow ("creates a new draft
-- revision from the latest eligible quote") and alternative flow ("an older version is
-- restored as a new latest draft"): p_source_quotation_id may be the current version (the
-- ordinary "revise" case) or any historical version of the same root (the "restore" case).
-- In both cases the effect is identical -- copy the source's header/lines into a brand-new
-- version, supersede whichever row was is_current beforehand.
create function app.create_quotation_revision(
  p_source_quotation_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.quotations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_source app.quotations;
  v_current app.quotations;
  v_decision app.rbac_decision;
  v_next_version integer;
  v_new_id uuid := gen_random_uuid();
  v_new app.quotations;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: creating a quotation revision requires a non-empty reason'
      using errcode = 'not_null_violation';
  end if;

  select * into v_source from app.quotations where id = p_source_quotation_id;
  if not found then
    raise exception 'quotation_not_found: %', p_source_quotation_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_source.tenant_id, 'COM', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_source.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_source.tenant_id, v_source.owner_user_id, app.lead_record_scope_org_unit_ids(v_source.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access quotation %', p_actor_auth_user_id, p_source_quotation_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Row-level lock on the root's current version -- a concurrent second call blocks here
  -- until the first commits, then re-reads and finds a *different* current row (the one
  -- the first call just created), so its own supersede UPDATE below naturally affects zero
  -- rows and this call fails closed rather than creating a divergent branch (Prompt 152
  -- §23: "Concurrent next-version request... fails without partial revision").
  select * into v_current from app.quotations where root_quotation_id = v_source.root_quotation_id and is_current for update;

  if v_current.status = 'cancelled' then
    raise exception 'invalid_transition: quotation root % is cancelled and cannot be revised', v_source.root_quotation_id
      using errcode = 'check_violation';
  end if;

  v_next_version := (select coalesce(max(version_number), 0) + 1 from app.quotations where root_quotation_id = v_source.root_quotation_id);

  update app.quotations
  set is_current = false, updated_at = now(), record_version = record_version + 1
  where id = v_current.id and is_current = true
  returning * into v_current;

  if not found then
    raise exception 'concurrent_revision: another revision was created concurrently for quotation root %', v_source.root_quotation_id
      using errcode = 'serialization_failure';
  end if;

  insert into app.quotations (
    id, tenant_id, quote_number, opportunity_id, source_opportunity_version, prospect_id, contact_id,
    customer_snapshot, currency, validity_from, validity_to, terms,
    root_quotation_id, version_number, is_current, revision_reason,
    owner_user_id, org_unit_id, created_by
  ) values (
    v_new_id, v_source.tenant_id, v_source.quote_number, v_source.opportunity_id, v_source.source_opportunity_version,
    v_source.prospect_id, v_source.contact_id, v_source.customer_snapshot, v_source.currency, now(), v_source.validity_to, v_source.terms,
    v_source.root_quotation_id, v_next_version, true, p_reason,
    v_source.owner_user_id, v_source.org_unit_id, p_actor_label
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
    cost_amount_snapshot, margin_pct_snapshot, p_actor_label
  from app.quotation_lines
  where quotation_id = v_source.id;

  v_new := app.recalculate_quotation_totals(v_new.id);

  update app.quotations set superseded_by_id = v_new_id where id = v_current.id;

  perform app.capture_audit_event(
    v_source.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_quotation_revision',
    'app.quotations', v_new.id, 'success', p_reason, to_jsonb(v_source), to_jsonb(v_new)
  );

  return v_new;
end;
$$;

comment on function app.create_quotation_revision is
  'COM-152: creates version_number = max(root)+1 from p_source_quotation_id (current or historical), supersedes whichever row was is_current beforehand via row-level locking (SELECT ... FOR UPDATE on the current row, not merely optimistic concurrency) -- serves both the "revise the latest" main flow and the "restore an older version" alternative flow identically. Mandatory p_reason. Blocked once the root''s current version is status=cancelled.';

-- Widens COM-151's app.add_quotation_line to additionally require is_current=true -- a
-- superseded historical version (even one whose own status column still literally reads
-- 'draft', since it was revised before ever being submitted) must never be directly
-- editable; only app.create_quotation_revision may act on it (as a *source*, not a target).
create or replace function app.add_quotation_line(
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

  if v_quotation.status <> 'draft' or not v_quotation.is_current then
    raise exception 'invalid_transition: quotation % is % (is_current=%) and cannot be edited', p_quotation_id, v_quotation.status, v_quotation.is_current
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

-- Widens COM-151's app.remove_quotation_line -- same is_current addition as add_quotation_line above.
create or replace function app.remove_quotation_line(
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

  if v_quotation.status <> 'draft' or not v_quotation.is_current then
    raise exception 'invalid_transition: quotation % is % (is_current=%) and cannot be edited', p_quotation_id, v_quotation.status, v_quotation.is_current
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

-- Widens COM-151's app.update_quotation_terms -- same is_current addition.
create or replace function app.update_quotation_terms(
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

  if v_quotation.status <> 'draft' or not v_quotation.is_current then
    raise exception 'invalid_transition: quotation % is % (is_current=%) and cannot be edited', p_quotation_id, v_quotation.status, v_quotation.is_current
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

-- Widens COM-151's app.get_quotation_submission_readiness -- adds a not_current reason.
create or replace function app.get_quotation_submission_readiness(p_quotation_id uuid, p_actor_auth_user_id uuid default auth.uid())
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

  if not v_quotation.is_current then
    v_reasons := array_append(v_reasons, 'not_current_version');
  end if;

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

-- Widens COM-151's app.submit_quotation -- same is_current addition.
create or replace function app.submit_quotation(
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

  if v_quotation.status <> 'draft' or not v_quotation.is_current then
    raise exception 'invalid_transition: quotation % is % (is_current=%) and cannot be submitted', p_quotation_id, v_quotation.status, v_quotation.is_current
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

-- Widens COM-151's app.quotations_directory -- appends the five new columns at the end
-- (existing column order/expressions unchanged, the only shape CREATE OR REPLACE VIEW
-- structurally allows).
create or replace view app.quotations_directory
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
  q.updated_at,
  q.root_quotation_id,
  q.version_number,
  q.is_current,
  q.superseded_by_id,
  q.revision_reason
from app.quotations q
where app.can_access_record(auth.uid(), q.tenant_id, q.owner_user_id, app.lead_record_scope_org_unit_ids(q.org_unit_id), null);

revoke execute on all functions in schema app from public;

grant select (root_quotation_id, version_number, is_current, superseded_by_id, revision_reason) on app.quotations to authenticated;

grant execute on function app.create_quotation_revision(uuid, text, uuid, text) to authenticated, service_role;
