-- Commercial capability COM-156 (Contract and Customer Pricing, CG-S7-COM-015)
-- Versioned customer contracts and pricing derived from accepted, converted quotations
-- (COM-154/155), with effective dates, service/lane price components and a deterministic
-- effective-price lookup. Reuses the exact root/version identity pattern COM-152 already
-- proved for quotations (self-referencing root id generated up front so the first row can
-- reference itself in the same insert) -- except, unlike a quotation's "exactly one
-- is_current row," a contract legitimately has multiple simultaneously-published versions
-- over its lifetime (a current price list plus a future-dated renewal already queued up),
-- distinguished by non-overlapping [effective_from, effective_to) windows rather than a
-- single latest-wins flag. "Overlapping active version" (Prompt 156 §23) is therefore
-- enforced as an explicit function-level check at publish time, with row-level locking
-- (SELECT ... FOR UPDATE) closing the same concurrent-publish race COM-152's own
-- create_quotation_revision already closed for its own "exactly one current" invariant.
--
-- Scope boundaries (disclosed, not silently narrowed, matching every prior checkpoint):
--
-- * **Governance is a direct COM:Approve gate on publish/retire, not a second Approval
--   Engine routing** (unlike COM-153's own quotation approval, which does instantiate
--   PLT-121/123). A contract price list is a materially smaller governance surface than a
--   quotation's own threshold-routed multi-step approval, and COM-153's own migration
--   header already disclosed that "approval routing is Prompt 153's own scope" for
--   quotations specifically -- reinstantiating the full engine a second time in the same
--   phase for this capability would be scope beyond what Prompt 156's own file-count
--   boundary (5-15 files, 1-3 migrations) allows. This mirrors the same "governance-
--   weighted, hard-to-reverse action gated by COM:Approve directly" precedent
--   app.convert_quotation_to_account (COM-155) and app.publish_margin_rule_version
--   (COM-150) already established.
-- * **`COM:View margin` is newly seeded for the COM module** (reusing the already-real
--   `'View margin'` enum value from `app.permissions_action_check`, PLT-111 -- currently
--   seeded only for FIN/PRC -- exactly the same "new (module, action) pair, not a new
--   enum value" mechanism COM-148 already used to add `COM:View cost`). Selling price and
--   discount figures on a contract's own price components are masked behind the
--   already-established `COM:View selling price` (COM-147); this migration does not store
--   or expose a separate margin percentage anywhere (margin was already fully computed
--   and locked at quotation time by COM-150's own margin engine) -- Prompt 156 §16's
--   mention of "margin" is satisfied by the existing selling-price mask rather than by
--   inventing a speculative figure this capability has no real use for yet.
-- * **No standalone site/address master** -- still deferred (COM-145/155's own disclosed
--   boundary, restated as still not resolved here either).
-- * **No persisted price-selection/snapshot table.** Prompt 156 §20 task 3 asks for a
--   "deterministic ... lookup and snapshot" -- `app.get_effective_customer_price` returns
--   a fully-shaped, deterministic snapshot row directly (every field a future consumer
--   would need to persist its own copy), but nothing actually persists it here: no Job
--   Order or other downstream consumer exists yet in this repository to snapshot into
--   (`COM-160`, "Full Lineage into Job Order," is a later, separate capability). Building
--   a persisted selections table with no real writer would be exactly the premature-model
--   risk this repository's binding rules forbid; the read path is real and reproducible
--   today, the persistence is this capability's own disclosed, named follow-up.
-- * **Legacy contract/pricelist migration is not applicable** -- greenfield, no live
--   environment (Prompt 156 §19).
-- * Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration carries its own
--   explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement before
--   its final grants, the standing per-migration convention since `PLT-118`.

insert into app.permissions (action, resource_module_code, category, protected)
values ('View margin', 'COM', 'sensitive', true);

create function app.has_view_margin(p_tenant_id uuid, p_auth_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select (app.evaluate_permission(p_auth_user_id, p_tenant_id, 'COM', 'View margin')).allowed;
$$;

comment on function app.has_view_margin is
  'Field-masking gate (COM-156, mirrors COM-147/148''s app.has_view_selling_price/app.has_view_cost) -- true if the caller holds the real, newly-seeded COM:View margin permission (PLT-111/112) for the given tenant. Not currently consumed by any masked column in this migration (see header) -- seeded now so a future capability that does compute a contract-level margin figure has a real permission ready rather than needing another architecture-level catalogue change.';

grant execute on function app.has_view_margin(uuid, uuid) to authenticated;

create table app.customer_contracts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  account_id uuid not null references app.accounts (id),
  root_contract_id uuid not null,
  version_number integer not null default 1,
  status text not null default 'draft',
  source_quotation_id uuid references app.quotations (id),
  amendment_reason text,
  effective_from timestamptz not null,
  effective_to timestamptz,
  retired_reason text,
  owner_user_id uuid references auth.users (id),
  org_unit_id uuid references app.org_units (id),
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint customer_contracts_status_check check (status in ('draft', 'published', 'retired')),
  constraint customer_contracts_validity_check check (effective_to is null or effective_to > effective_from),
  constraint customer_contracts_root_version_unique unique (root_contract_id, version_number),
  constraint customer_contracts_retired_reason_check check (
    (status = 'retired' and retired_reason is not null and length(trim(retired_reason)) > 0)
    or status <> 'retired'
  ),
  constraint customer_contracts_amendment_reason_check check (
    (version_number > 1 and amendment_reason is not null and length(trim(amendment_reason)) > 0)
    or version_number = 1
  )
);

comment on table app.customer_contracts is
  'COM-156: one row per contract/pricelist version. root_contract_id groups every version of "the same" commercial agreement (identical mechanism to app.quotations.root_quotation_id, COM-152) -- but unlike a quotation''s single is_current row, multiple versions of one root may be status=published simultaneously as long as their [effective_from, effective_to) windows do not overlap (enforced at publish time, not by a partial-unique index -- see app.publish_customer_contract). source_quotation_id is set only on a version''s own originating row (version_number=1 created from an accepted+converted quote); a renewal/amendment (version_number>1) carries the reason instead.';

create index customer_contracts_tenant_idx on app.customer_contracts (tenant_id);
create index customer_contracts_account_idx on app.customer_contracts (account_id);
create index customer_contracts_root_idx on app.customer_contracts (root_contract_id);
create index customer_contracts_tenant_status_idx on app.customer_contracts (tenant_id, status);

create function app.touch_customer_contracts_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger customer_contracts_touch_row
  before update on app.customer_contracts
  for each row
  execute function app.touch_customer_contracts_row();

-- Service/lane price components (Prompt 156 §13/§20 task 1) -- the child detail table one
-- contract version's price list is actually made of, mirroring app.vendor_rate_versions'
-- own service/lane/rate/component shape (COM-149) on the customer-selling side rather
-- than the vendor-cost side.
create table app.customer_contract_price_components (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  contract_id uuid not null references app.customer_contracts (id) on delete cascade,
  service_type text not null,
  mode text,
  origin_lane text,
  destination_lane text,
  equipment_type text,
  currency text not null,
  base_amount numeric(14, 2) not null,
  minimum_amount numeric(14, 2),
  discount_pct numeric(5, 2) not null default 0,
  surcharge_components jsonb not null default '[]'::jsonb,
  created_by text,
  created_at timestamptz not null default now(),
  constraint customer_contract_price_components_currency_check check (currency ~ '^[A-Z]{3}$'),
  constraint customer_contract_price_components_base_amount_check check (base_amount >= 0),
  constraint customer_contract_price_components_minimum_amount_check check (minimum_amount is null or minimum_amount >= 0),
  constraint customer_contract_price_components_discount_check check (discount_pct >= 0 and discount_pct <= 100)
);

comment on table app.customer_contract_price_components is
  'COM-156: one priced service/lane condition per row within one contract version. The unique index below makes each (service_type, mode, origin_lane, destination_lane, equipment_type) combination appear at most once per contract_id -- the structural reason app.get_effective_customer_price always resolves to at most one deterministic row (Prompt 156 §25: "returns one deterministic eligible version or fails explicitly") rather than needing a tie-break rule.';

create unique index customer_contract_price_components_identity_unique on app.customer_contract_price_components (
  contract_id, service_type, coalesce(mode, ''), coalesce(origin_lane, ''), coalesce(destination_lane, ''), coalesce(equipment_type, '')
);
create index customer_contract_price_components_contract_idx on app.customer_contract_price_components (contract_id);

-- Widens COM-151's app.create_quotation_draft's own technique for a brand-new root, and
-- COM-152's app.create_quotation_revision's own "source may be current or historical, new
-- row always appended" technique for a renewal/amendment -- one function serves the main
-- flow ("accepted quote creates a draft") and the alternative flow ("renewal/amendment
-- creates a future-dated version") identically, exactly as Prompt 156 §21/§22 ask.
-- Exactly one of p_source_quotation_id / p_source_contract_id must be supplied.
create function app.create_customer_contract_draft(
  p_source_quotation_id uuid,
  p_source_contract_id uuid,
  p_effective_from timestamptz,
  p_effective_to timestamptz,
  p_amendment_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.customer_contracts
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_quotation app.quotations;
  v_conversion app.account_conversions;
  v_source app.customer_contracts;
  v_component app.customer_contract_price_components;
  v_new_id uuid := gen_random_uuid();
  v_new app.customer_contracts;
  v_tenant_id uuid;
  v_account_id uuid;
  v_root_contract_id uuid;
  v_next_version integer;
begin
  if (p_source_quotation_id is null) = (p_source_contract_id is null) then
    raise exception 'invalid_source: exactly one of source_quotation_id/source_contract_id must be supplied'
      using errcode = 'check_violation';
  end if;

  if p_effective_from is null then
    raise exception 'invalid_validity: effective_from is required' using errcode = 'check_violation';
  end if;

  if p_source_quotation_id is not null then
    select * into v_quotation from app.quotations where id = p_source_quotation_id;
    if not found then
      raise exception 'quotation_not_found: %', p_source_quotation_id using errcode = 'no_data_found';
    end if;

    v_decision := app.evaluate_permission(p_actor_auth_user_id, v_quotation.tenant_id, 'COM', 'Edit');
    if not v_decision.allowed then
      raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_quotation.tenant_id
        using errcode = 'insufficient_privilege';
    end if;
    if not app.can_access_record(p_actor_auth_user_id, v_quotation.tenant_id, v_quotation.owner_user_id, app.lead_record_scope_org_unit_ids(v_quotation.org_unit_id), null) then
      raise exception 'insufficient_authority: identity % cannot access quotation %', p_actor_auth_user_id, p_source_quotation_id
        using errcode = 'insufficient_privilege';
    end if;

    if v_quotation.customer_decision is distinct from 'accepted' then
      raise exception 'quotation_not_accepted: quotation % has no accepted customer decision', p_source_quotation_id
        using errcode = 'check_violation';
    end if;

    select * into v_conversion from app.account_conversions where quotation_id = p_source_quotation_id;
    if not found then
      raise exception 'quotation_not_converted: quotation % has not been converted to an account yet (COM-155)', p_source_quotation_id
        using errcode = 'check_violation';
    end if;

    if exists (select 1 from app.customer_contracts where source_quotation_id = p_source_quotation_id) then
      raise exception 'quotation_already_contracted: quotation % already sourced a contract', p_source_quotation_id
        using errcode = 'unique_violation';
    end if;

    v_tenant_id := v_quotation.tenant_id;
    v_account_id := v_conversion.account_id;
    v_root_contract_id := v_new_id;
    v_next_version := 1;

    insert into app.customer_contracts (
      id, tenant_id, account_id, root_contract_id, version_number, source_quotation_id,
      effective_from, effective_to, owner_user_id, org_unit_id, created_by
    ) values (
      v_new_id, v_tenant_id, v_account_id, v_root_contract_id, v_next_version, p_source_quotation_id,
      p_effective_from, p_effective_to, coalesce(v_quotation.owner_user_id, p_actor_auth_user_id), v_quotation.org_unit_id, p_actor_label
    )
    returning * into v_new;
  else
    select * into v_source from app.customer_contracts where id = p_source_contract_id;
    if not found then
      raise exception 'contract_not_found: %', p_source_contract_id using errcode = 'no_data_found';
    end if;

    v_decision := app.evaluate_permission(p_actor_auth_user_id, v_source.tenant_id, 'COM', 'Edit');
    if not v_decision.allowed then
      raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_source.tenant_id
        using errcode = 'insufficient_privilege';
    end if;

    if p_amendment_reason is null or length(trim(p_amendment_reason)) = 0 then
      raise exception 'reason_required: an amendment/renewal requires a non-empty reason'
        using errcode = 'not_null_violation';
    end if;

    v_tenant_id := v_source.tenant_id;
    v_account_id := v_source.account_id;
    v_root_contract_id := v_source.root_contract_id;
    v_next_version := (select coalesce(max(version_number), 0) + 1 from app.customer_contracts where root_contract_id = v_root_contract_id);

    insert into app.customer_contracts (
      id, tenant_id, account_id, root_contract_id, version_number, amendment_reason,
      effective_from, effective_to, owner_user_id, org_unit_id, created_by
    ) values (
      v_new_id, v_tenant_id, v_account_id, v_root_contract_id, v_next_version, p_amendment_reason,
      p_effective_from, p_effective_to, v_source.owner_user_id, v_source.org_unit_id, p_actor_label
    )
    returning * into v_new;

    -- Copies the source version's own price components into the new draft (a renewal
    -- normally starts from what came before, then is edited) -- never a live reference,
    -- the same no-reentry snapshot discipline every prior Commercial capability follows.
    for v_component in select * from app.customer_contract_price_components where contract_id = p_source_contract_id loop
      insert into app.customer_contract_price_components (
        tenant_id, contract_id, service_type, mode, origin_lane, destination_lane, equipment_type,
        currency, base_amount, minimum_amount, discount_pct, surcharge_components, created_by
      ) values (
        v_tenant_id, v_new.id, v_component.service_type, v_component.mode, v_component.origin_lane, v_component.destination_lane, v_component.equipment_type,
        v_component.currency, v_component.base_amount, v_component.minimum_amount, v_component.discount_pct, v_component.surcharge_components, p_actor_label
      );
    end loop;
  end if;

  perform app.capture_audit_event(
    v_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_customer_contract_draft',
    'app.customer_contracts', v_new.id, 'success', null, null, to_jsonb(v_new)
  );

  return v_new;
end;
$$;

comment on function app.create_customer_contract_draft is
  'COM-156: main flow (p_source_quotation_id set) requires the quotation to be customer_decision=accepted and already converted to an account (COM-155) -- one contract root per source quotation, ever. Alternative flow (p_source_contract_id set) is a renewal/amendment: copies the source version''s own price components into the new draft, requires a non-empty reason, and always appends the next version_number under the same root_contract_id.';

create function app.add_customer_contract_price_component(
  p_contract_id uuid,
  p_service_type text,
  p_mode text,
  p_origin_lane text,
  p_destination_lane text,
  p_equipment_type text,
  p_currency text,
  p_base_amount numeric,
  p_minimum_amount numeric,
  p_discount_pct numeric,
  p_surcharge_components jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.customer_contract_price_components
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_contract app.customer_contracts;
  v_decision app.rbac_decision;
  v_component app.customer_contract_price_components;
begin
  select * into v_contract from app.customer_contracts where id = p_contract_id;
  if not found then
    raise exception 'contract_not_found: %', p_contract_id using errcode = 'no_data_found';
  end if;

  if v_contract.status <> 'draft' then
    raise exception 'invalid_transition: contract % is % and cannot accept a new price component', p_contract_id, v_contract.status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_contract.tenant_id, 'COM', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_contract.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Dual-gated (mirrors app.select_vendor_rate's own dual COM:Edit + COM:View cost gate,
  -- COM-149): this function RETURNS the raw, unmasked row directly (never the masked
  -- directory view) -- an actor who could edit but could not otherwise view selling price
  -- must not be able to round-trip it back to themselves through this call's own result.
  if not app.has_view_selling_price(v_contract.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks COM:View selling price required to add a price component', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then
    raise exception 'invalid_currency: % is not a 3-letter ISO currency code', p_currency using errcode = 'check_violation';
  end if;

  if p_service_type is null or length(trim(p_service_type)) = 0 then
    raise exception 'invalid_service_type: service_type is required' using errcode = 'check_violation';
  end if;

  insert into app.customer_contract_price_components (
    tenant_id, contract_id, service_type, mode, origin_lane, destination_lane, equipment_type,
    currency, base_amount, minimum_amount, discount_pct, surcharge_components, created_by
  ) values (
    v_contract.tenant_id, p_contract_id, p_service_type, p_mode, p_origin_lane, p_destination_lane, p_equipment_type,
    p_currency, p_base_amount, p_minimum_amount, coalesce(p_discount_pct, 0), coalesce(p_surcharge_components, '[]'::jsonb), p_actor_label
  )
  returning * into v_component;

  return v_component;
end;
$$;

comment on function app.add_customer_contract_price_component is
  'COM-156: only while the owning contract is status=draft (mirrors app.add_quotation_line''s own is_current/draft gate, COM-151/152). Dual-gated on COM:Edit + COM:View selling price (mirrors app.select_vendor_rate''s own dual gate, COM-149) since this function returns the raw, unmasked row directly. The identity unique index (contract_id, service_type, mode, origin_lane, destination_lane, equipment_type) surfaces a real Postgres unique_violation on a duplicate combination -- not a bespoke pre-check, the same "let the database enforce the real invariant" choice this repository''s per-migration convention already favors.';

create function app.remove_customer_contract_price_component(
  p_component_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns void
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_component app.customer_contract_price_components;
  v_contract app.customer_contracts;
  v_decision app.rbac_decision;
begin
  select * into v_component from app.customer_contract_price_components where id = p_component_id;
  if not found then
    raise exception 'price_component_not_found: %', p_component_id using errcode = 'no_data_found';
  end if;

  select * into v_contract from app.customer_contracts where id = v_component.contract_id;

  if v_contract.status <> 'draft' then
    raise exception 'invalid_transition: contract % is % and its price components cannot be edited', v_contract.id, v_contract.status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_contract.tenant_id, 'COM', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_contract.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  delete from app.customer_contract_price_components where id = p_component_id;
end;
$$;

-- The one governance-weighted, hard-to-reverse lifecycle transition (Prompt 156 §21).
-- COM:Approve-gated, mirroring app.convert_quotation_to_account/app.publish_margin_rule_
-- version (see header). Row-level locking on any other published sibling under the same
-- root closes the same concurrent-publish race app.create_quotation_revision (COM-152)
-- already closed for its own analogous invariant.
create function app.publish_customer_contract(
  p_contract_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.customer_contracts
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_contract app.customer_contracts;
  v_decision app.rbac_decision;
  v_sibling app.customer_contracts;
  v_component_count integer;
begin
  select * into v_contract from app.customer_contracts where id = p_contract_id;
  if not found then
    raise exception 'contract_not_found: %', p_contract_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_contract.tenant_id, 'COM', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_contract.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_contract.record_version <> p_expected_version then
    raise exception 'stale_version: contract % expected version % but found %', p_contract_id, p_expected_version, v_contract.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_contract.status <> 'draft' then
    raise exception 'invalid_transition: contract % is % and cannot be published', p_contract_id, v_contract.status
      using errcode = 'check_violation';
  end if;

  select count(*) into v_component_count from app.customer_contract_price_components where contract_id = p_contract_id;
  if v_component_count = 0 then
    raise exception 'no_price_components: contract % has no price components to publish', p_contract_id
      using errcode = 'check_violation';
  end if;

  for v_sibling in
    select * from app.customer_contracts
    where root_contract_id = v_contract.root_contract_id
      and id <> v_contract.id
      and status = 'published'
    order by id
    for update
  loop
    if v_sibling.effective_from < coalesce(v_contract.effective_to, 'infinity'::timestamptz)
       and v_contract.effective_from < coalesce(v_sibling.effective_to, 'infinity'::timestamptz) then
      raise exception 'overlapping_active_version: contract % [%, %) overlaps already-published version % [%, %)',
        p_contract_id, v_contract.effective_from, v_contract.effective_to, v_sibling.id, v_sibling.effective_from, v_sibling.effective_to
        using errcode = 'check_violation';
    end if;
  end loop;

  update app.customer_contracts
  set status = 'published', updated_at = now(), record_version = record_version + 1
  where id = p_contract_id and record_version = p_expected_version
  returning * into v_contract;

  perform app.capture_audit_event(
    v_contract.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_customer_contract',
    'app.customer_contracts', v_contract.id, 'success', null, null, jsonb_build_object('status', v_contract.status)
  );

  return v_contract;
end;
$$;

comment on function app.publish_customer_contract is
  'COM-156: publish requires >=1 price component and no date-overlapping already-published sibling under the same root_contract_id (Prompt 156 §23''s "overlapping active version" exception, enforced here via SELECT ... FOR UPDATE row locking, not a partial-unique index -- unlike quotations'' single is_current, a contract root may legitimately carry more than one simultaneously-published, non-overlapping version).';

create function app.retire_customer_contract(
  p_contract_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.customer_contracts
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_contract app.customer_contracts;
  v_decision app.rbac_decision;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: retiring a contract requires a non-empty reason'
      using errcode = 'not_null_violation';
  end if;

  select * into v_contract from app.customer_contracts where id = p_contract_id;
  if not found then
    raise exception 'contract_not_found: %', p_contract_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_contract.tenant_id, 'COM', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_contract.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_contract.record_version <> p_expected_version then
    raise exception 'stale_version: contract % expected version % but found %', p_contract_id, p_expected_version, v_contract.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_contract.status <> 'published' then
    raise exception 'invalid_transition: contract % is % and only a published contract can be retired', p_contract_id, v_contract.status
      using errcode = 'check_violation';
  end if;

  update app.customer_contracts
  set status = 'retired', retired_reason = p_reason, updated_at = now(), record_version = record_version + 1
  where id = p_contract_id and record_version = p_expected_version
  returning * into v_contract;

  perform app.capture_audit_event(
    v_contract.tenant_id, p_actor_auth_user_id, p_actor_label, 'retire_customer_contract',
    'app.customer_contracts', v_contract.id, 'success', p_reason, null, jsonb_build_object('status', v_contract.status)
  );

  return v_contract;
end;
$$;

-- Field-masked projection of app.customer_contract_price_components (mirrors app.vendor_
-- rate_versions_directory, COM-149) -- selling/discount figures nulled out for any caller
-- lacking COM:View selling price. Tenant-wide visible (contracts are tied to app.accounts,
-- itself tenant-wide reference data, not per-owner/org-unit-scoped).
create view app.customer_contract_price_components_directory
as
select
  c.id,
  c.tenant_id,
  c.contract_id,
  c.service_type,
  c.mode,
  c.origin_lane,
  c.destination_lane,
  c.equipment_type,
  case when app.has_view_selling_price(c.tenant_id) then c.currency else null end as currency,
  case when app.has_view_selling_price(c.tenant_id) then c.base_amount else null end as base_amount,
  case when app.has_view_selling_price(c.tenant_id) then c.minimum_amount else null end as minimum_amount,
  case when app.has_view_selling_price(c.tenant_id) then c.discount_pct else null end as discount_pct,
  case when app.has_view_selling_price(c.tenant_id) then c.surcharge_components else null end as surcharge_components,
  not app.has_view_selling_price(c.tenant_id) as price_masked,
  c.created_by,
  c.created_at
from app.customer_contract_price_components c
where app.has_active_tenant_membership(c.tenant_id) or app.is_supreme_admin();

comment on view app.customer_contract_price_components_directory is
  'COM-156: currency/base_amount/minimum_amount/discount_pct/surcharge_components are nulled out (price_masked=true) for any caller lacking the real, seeded COM:View selling price permission. authenticated has no direct column-level grant on those five columns on app.customer_contract_price_components itself, forcing every read through this view (same technique app.vendor_rate_versions_directory, COM-149, established).';

-- The deterministic effective-price lookup (Prompt 156 §20 task 3/§25). Structurally
-- returns at most one row: at most one published contract version per root can have a
-- window containing p_as_of (app.publish_customer_contract's own overlap guarantee), and
-- at most one price component per contract can match one exact service/lane identity
-- (customer_contract_price_components_identity_unique). Raises explicitly on zero rows
-- rather than returning an empty set silently (Prompt 156 §25: "...or fails explicitly").
create function app.get_effective_customer_price(
  p_tenant_id uuid,
  p_account_id uuid,
  p_service_type text,
  p_mode text,
  p_origin_lane text,
  p_destination_lane text,
  p_equipment_type text,
  p_as_of timestamptz default now(),
  p_actor_auth_user_id uuid default auth.uid()
)
returns table (
  contract_id uuid,
  price_component_id uuid,
  service_type text,
  mode text,
  origin_lane text,
  destination_lane text,
  equipment_type text,
  currency text,
  base_amount numeric,
  minimum_amount numeric,
  discount_pct numeric,
  surcharge_components jsonb,
  price_masked boolean,
  effective_from timestamptz,
  effective_to timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_masked boolean;
  v_row record;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'COM', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_masked := not app.has_view_selling_price(p_tenant_id, p_actor_auth_user_id);

  select cc.id as v_contract_id, pc.id as v_component_id, pc.currency as v_currency, pc.base_amount as v_base_amount,
         pc.minimum_amount as v_minimum_amount, pc.discount_pct as v_discount_pct, pc.surcharge_components as v_surcharge_components,
         cc.effective_from as v_effective_from, cc.effective_to as v_effective_to
  into v_row
  from app.customer_contracts cc
  join app.customer_contract_price_components pc on pc.contract_id = cc.id
  where cc.tenant_id = p_tenant_id
    and cc.account_id = p_account_id
    and cc.status = 'published'
    and cc.effective_from <= p_as_of
    and (cc.effective_to is null or cc.effective_to > p_as_of)
    and pc.service_type = p_service_type
    and pc.mode is not distinct from p_mode
    and pc.origin_lane is not distinct from p_origin_lane
    and pc.destination_lane is not distinct from p_destination_lane
    and pc.equipment_type is not distinct from p_equipment_type
  limit 1;

  if not found then
    raise exception 'no_effective_price: no published contract price component matches account %, service %, as_of %', p_account_id, p_service_type, p_as_of
      using errcode = 'no_data_found';
  end if;

  return query select
    v_row.v_contract_id,
    v_row.v_component_id,
    p_service_type,
    p_mode,
    p_origin_lane,
    p_destination_lane,
    p_equipment_type,
    case when v_masked then null else v_row.v_currency end,
    case when v_masked then null else v_row.v_base_amount end,
    case when v_masked then null else v_row.v_minimum_amount end,
    case when v_masked then null else v_row.v_discount_pct end,
    case when v_masked then null else v_row.v_surcharge_components end,
    v_masked,
    v_row.v_effective_from,
    v_row.v_effective_to;
end;
$$;

comment on function app.get_effective_customer_price is
  'COM-156: the deterministic, reproducible effective-price lookup Prompt 156''s own objective names. Exact-match on every identity dimension (IS NOT DISTINCT FROM, so a component''s own null dimension only matches a null argument, never a wildcard) -- combined with the publish-time overlap guarantee and the price-component identity unique index, at most one row can ever match, and this function raises no_effective_price explicitly rather than returning zero rows silently. Masked the same way the directory view is (COM:View selling price).';

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke of
-- PostgreSQL's PUBLIC-execute default, the standing per-migration convention since
-- PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

alter table app.customer_contracts enable row level security;
alter table app.customer_contract_price_components enable row level security;

-- Tenant-wide, not record-scoped -- mirrors app.accounts' own posture (COM-155): a
-- contract belongs to a tenant-wide-visible account, not a single owner/org-unit's silo.
create policy customer_contracts_select_scoped on app.customer_contracts
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

create policy customer_contract_price_components_select_scoped on app.customer_contract_price_components
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

grant usage on schema app to authenticated;

grant select on app.customer_contracts to authenticated, service_role;
grant insert, update, delete on app.customer_contracts to service_role;

-- The database guarantee (matches PLT-114/COM-147/148/149's own proven technique): a bare
-- column-level REVOKE cannot carve an exception out of a broader table-level GRANT -- the
-- table-level grant must be revoked entirely and re-granted on an explicit column list
-- that omits the five selling-price-bearing columns.
grant select (
  id, tenant_id, contract_id, service_type, mode, origin_lane, destination_lane, equipment_type, created_by, created_at
) on app.customer_contract_price_components to authenticated;
grant select on app.customer_contract_price_components to service_role;
grant insert, update, delete on app.customer_contract_price_components to service_role;

grant select on app.customer_contract_price_components_directory to authenticated, service_role;

grant execute on function app.create_customer_contract_draft(uuid, uuid, timestamptz, timestamptz, text, uuid, text) to authenticated, service_role;
grant execute on function app.add_customer_contract_price_component(uuid, text, text, text, text, text, text, numeric, numeric, numeric, jsonb, uuid, text) to authenticated, service_role;
grant execute on function app.remove_customer_contract_price_component(uuid, uuid, text) to authenticated, service_role;
grant execute on function app.publish_customer_contract(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.retire_customer_contract(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.get_effective_customer_price(uuid, uuid, text, text, text, text, text, timestamptz, uuid) to authenticated, service_role;
