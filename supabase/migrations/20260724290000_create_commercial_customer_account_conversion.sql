-- Commercial capability COM-155 (Customer and Account Conversion, CG-S7-COM-014)
-- Idempotent conversion from an accepted quotation (`app.quotations.customer_decision =
-- 'accepted'`, `COM-154`) plus its source prospect (`app.prospects`, `COM-144`) into the
-- first canonical customer/account master this repository builds. `ADR-0018` is the
-- controlling document for the shape/ownership decision this migration implements --
-- read it first: a flat, typed-column, Commercial-owned `app.accounts` table (mirroring
-- `app.prospects`, reusing its normalization/fingerprint functions directly), not
-- `PLT-120`'s Master Data Engine (the pattern `ADR-0015` selected for `vendor_rate`, for
-- a cross-module-ownership reason that does not apply here).
--
-- Closes a forward-reference multiple prior migrations disclosed in advance:
-- `app.opportunities.account_ref` (`COM-147`, `20260723210000_...`) is backfilled by
-- `app.convert_quotation_to_account` below -- its own column comment names this exact
-- checkpoint as the expected backfiller.
--
-- Scope boundaries (disclosed, not silently narrowed, matching every prior checkpoint's
-- discipline):
--
-- * **"Account" and "customer" are one entity, not two** (`ADR-0018`'s own resolution of
--   Prompt 155 §20 task 1). `app.accounts.customer_status` (`active`/`inactive`) is the
--   relationship status; there is no separate `app.customers` table to keep in sync.
-- * **Visibility is tenant-wide, not record-scoped** -- unlike `app.leads`/`app.prospects`/
--   `app.opportunities` (owner/org-unit `can_access_record` scoping), `app.accounts` is a
--   shared reference master any active tenant member may read, mirroring
--   `app.vendor_rate_versions_directory`/`app.quotation_approval_rules`' own posture: many
--   reps across many teams legitimately transact against the same canonical customer over
--   time, so per-owner siloing would be the wrong default here, not a stricter one.
-- * **No credit field of any kind exists on `app.accounts`** (Prompt 155 §24: "conversion
--   does not grant credit automatically"). `COM-157` (Credit and Commercial Control) owns
--   that concept entirely -- not even a placeholder column is added here, since a fake
--   placeholder would risk conflicting with that capability's own real design.
-- * **No standalone site/address master.** `billing_address` is reused directly as jsonb,
--   the exact shape `app.prospects.billing_address` already established (`COM-144`) --
--   `COM-145`'s own disclosed deferral of a normalized site/address master to
--   "COM-155/156" is restated here as still-deferred, not resolved: no capability yet
--   needs multi-site delivery/pickup tracking, so building one ahead of a real requirement
--   would be exactly the premature-model risk this repository's binding rules forbid.
-- * **`tax_id`/`billing_address` carry no per-field masking permission.** Prompt 155 §16
--   asks to "restrict legal/tax/billing/credit fields" -- but `app.permissions_action_
--   check` (`PLT-111`) is a fixed, closed 19-action enum reproduced verbatim from
--   `docs/architecture/06_RLS_RBAC_WORKSTREAM.md` §5.1, with no billing-shaped action to
--   reuse (`View cost`/`View selling price`/`View margin`/`View payroll`/`View personal
--   data` are all a different sensitivity axis) -- widening that architecture-level
--   catalogue is out of this bounded task's scope. `app.accounts` therefore applies the
--   same disclosed precedent `COM-150`/`COM-153` already established for
--   `app.margin_rule_versions`/`app.quotation_approval_rules` ("tenant-wide policy
--   reference, not a specific deal's figure, not masked"): every column is visible to
--   any active tenant member via the base table's own RLS policy directly -- no separate
--   masked directory view (unlike `app.quotations_directory`, which masks real columns).
--   The real
--   restriction Prompt 155 asks for is enforced one layer up instead -- only an actor
--   holding `COM:Approve` may create/convert an account at all (see
--   `app.convert_quotation_to_account` below), the same governance-weight gate
--   `app.publish_margin_rule_version`/`app.publish_quotation_approval_rule_version`
--   already use.
-- * **"Merge duplicate accounts" is not built.** The conversion flow's own "link to an
--   existing account after duplicate review" path (Prompt 155's alternative flow) covers
--   the real duplicate-avoidance need; a separate post-hoc `app.merge_accounts` (mirroring
--   `app.merge_prospects`/`app.merge_leads`) is a real, disclosed, un-built follow-up, not
--   silently assumed absent.
-- * **Legacy data migration is not applicable** -- greenfield table, no live environment
--   (Prompt 155 §19's "reconciliation queue" is therefore not built either).
-- * Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration carries its own
--   explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement before
--   its final grants, the standing per-migration convention since `PLT-118`.

create table app.accounts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  legal_name text not null,
  trade_name text,
  tax_id text,
  normalized_legal_name text,
  normalized_tax_id text,
  duplicate_fingerprint text not null,
  billing_address jsonb not null default '{}'::jsonb,
  customer_status text not null default 'active',
  parent_account_id uuid references app.accounts (id),
  source_prospect_id uuid references app.prospects (id),
  status text not null default 'active',
  merged_into_id uuid references app.accounts (id),
  merged_at timestamptz,
  merged_by text,
  owner_user_id uuid references auth.users (id),
  org_unit_id uuid references app.org_units (id),
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint accounts_legal_name_check check (length(trim(legal_name)) > 0),
  constraint accounts_status_check check (status in ('active', 'merged')),
  constraint accounts_customer_status_check check (customer_status in ('active', 'inactive')),
  constraint accounts_billing_address_check check (jsonb_typeof(billing_address) = 'object'),
  constraint accounts_not_self_parent check (parent_account_id is null or parent_account_id <> id)
);

comment on table app.accounts is
  'COM-155: the canonical customer/account master (ADR-0018) -- flat, typed columns, Commercial-owned, tenant-wide visible (not record-scoped). customer_status is the account/customer relationship distinction Prompt 155 asked this checkpoint to define -- one entity, one identity, no separate app.customers table.';

create unique index accounts_tenant_fingerprint_active_unique on app.accounts (tenant_id, duplicate_fingerprint) where status = 'active';
create index accounts_tenant_idx on app.accounts (tenant_id);
create index accounts_parent_idx on app.accounts (parent_account_id);

create function app.touch_accounts_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger accounts_touch_row
  before update on app.accounts
  for each row
  execute function app.touch_accounts_row();

-- Idempotency/evidence for one conversion action -- unique(quotation_id) is the real,
-- database-enforced "one source context yields one canonical outcome" guarantee (Prompt
-- 155 §33), not merely an application-level check.
create table app.account_conversions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  quotation_id uuid not null references app.quotations (id),
  prospect_id uuid not null references app.prospects (id),
  account_id uuid not null references app.accounts (id),
  outcome text not null,
  duplicate_candidate_ids uuid[] not null default array[]::uuid[],
  converted_by text,
  converted_at timestamptz not null default now(),
  constraint account_conversions_outcome_check check (outcome in ('created', 'linked_existing')),
  constraint account_conversions_quotation_unique unique (quotation_id)
);

comment on table app.account_conversions is
  'COM-155: append-only conversion evidence. outcome=created means a brand-new app.accounts row was minted from the source prospect/quotation snapshot; outcome=linked_existing means the accepted quotation was bound to an already-existing account chosen after duplicate review (Prompt 155''s own alternative flow) -- both are exactly one row per quotation_id, ever.';

create index account_conversions_tenant_idx on app.account_conversions (tenant_id);
create index account_conversions_account_idx on app.account_conversions (account_id);

-- Tenant-scoped only, fails closed on missing membership -- mirrors app.find_duplicate_
-- prospects (COM-144) exactly, reusing its own normalize/fingerprint functions directly
-- rather than re-authoring near-duplicates (their bodies are generic despite the
-- prospect-specific names, the same reuse precedent COM-144 already established for
-- app.lead_record_scope_org_unit_ids).
create function app.find_duplicate_accounts(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_legal_name text,
  p_tax_id text
)
returns setof app.accounts
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_fingerprint text;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_fingerprint := app.compute_prospect_duplicate_fingerprint(
    p_tenant_id, app.normalize_prospect_identifier(p_legal_name), app.normalize_prospect_identifier(p_tax_id)
  );

  return query
    select * from app.accounts
    where tenant_id = p_tenant_id
      and duplicate_fingerprint = v_fingerprint
      and status <> 'merged'
    order by created_at;
end;
$$;

comment on function app.find_duplicate_accounts is
  'COM-155: tenant-scoped only, fails closed on missing membership -- structurally cannot probe another tenant''s accounts, the same discipline app.find_duplicate_prospects (COM-144) already established. Reuses app.normalize_prospect_identifier/app.compute_prospect_duplicate_fingerprint directly.';

-- Read-only preview (Prompt 155 §15/§20 task 2: "preview/mapping and scoped duplicate
-- candidates"). Reason codes only, never a dollar figure -- safe to expose broadly,
-- mirroring app.get_quotation_submission_readiness (COM-151).
create function app.get_account_conversion_readiness(p_quotation_id uuid, p_actor_auth_user_id uuid default auth.uid())
returns table (ready boolean, blocking_reasons text[], duplicate_candidate_ids uuid[])
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_quotation app.quotations;
  v_prospect app.prospects;
  v_reasons text[] := array[]::text[];
  v_candidates uuid[] := array[]::uuid[];
begin
  select * into v_quotation from app.quotations where id = p_quotation_id;
  if not found then
    raise exception 'quotation_not_found: %', p_quotation_id using errcode = 'no_data_found';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_quotation.tenant_id, v_quotation.owner_user_id, app.lead_record_scope_org_unit_ids(v_quotation.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access quotation %', p_actor_auth_user_id, p_quotation_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_prospect from app.prospects where id = v_quotation.prospect_id;

  if v_quotation.customer_decision is distinct from 'accepted' then
    v_reasons := array_append(v_reasons, 'quotation_not_accepted');
  end if;

  if exists (select 1 from app.account_conversions c where c.quotation_id = p_quotation_id) then
    v_reasons := array_append(v_reasons, 'already_converted');
  end if;

  if v_prospect.legal_name is null or length(trim(v_prospect.legal_name)) = 0 then
    v_reasons := array_append(v_reasons, 'missing_legal_name');
  end if;

  if v_quotation.customer_decision = 'accepted' and v_prospect.legal_name is not null then
    select coalesce(array_agg(a.id), array[]::uuid[]) into v_candidates
    from app.find_duplicate_accounts(v_quotation.tenant_id, p_actor_auth_user_id, v_prospect.legal_name, v_prospect.tax_id) a;
  end if;

  return query select (array_length(v_reasons, 1) is null), v_reasons, v_candidates;
end;
$$;

comment on function app.get_account_conversion_readiness is
  'COM-155: structural readiness check -- not yet accepted, already converted, or missing the one mandatory field (legal_name) all block. duplicate_candidate_ids surfaces app.find_duplicate_accounts'' own result so the conversion UI can render a duplicate-review step before the caller decides create-new vs. link-existing.';

-- The one atomic, idempotent conversion action (Prompt 155 §20 task 3/§21/§22).
-- COM:Approve-gated (governance-weighted, hard-to-reverse -- mirrors app.publish_margin_
-- rule_version/app.publish_quotation_approval_rule_version, not an ordinary COM:Edit).
-- p_target_account_id set = the alternative "link to existing" flow (after duplicate
-- review); null = create a brand-new account from the source snapshot. A concurrent
-- create-new race against the same legal identity is caught (unique_violation on the
-- fingerprint index) and gracefully re-resolved as a link to the winning row, rather than
-- erroring -- Prompt 155 §27's own "concurrent retry" scenario.
create function app.convert_quotation_to_account(
  p_quotation_id uuid,
  p_target_account_id uuid,
  p_parent_account_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.accounts
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_quotation app.quotations;
  v_prospect app.prospects;
  v_decision app.rbac_decision;
  v_existing_conversion app.account_conversions;
  v_account app.accounts;
  v_outcome text;
  v_normalized_legal_name text;
  v_normalized_tax_id text;
  v_fingerprint text;
  v_link app.contact_links%rowtype;
begin
  select * into v_quotation from app.quotations where id = p_quotation_id;
  if not found then
    raise exception 'quotation_not_found: %', p_quotation_id using errcode = 'no_data_found';
  end if;

  select * into v_existing_conversion from app.account_conversions where quotation_id = p_quotation_id;
  if found then
    select * into v_account from app.accounts where id = v_existing_conversion.account_id;
    return v_account;
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_quotation.tenant_id, 'COM', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_quotation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_quotation.tenant_id, v_quotation.owner_user_id, app.lead_record_scope_org_unit_ids(v_quotation.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access quotation %', p_actor_auth_user_id, p_quotation_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_quotation.customer_decision is distinct from 'accepted' then
    raise exception 'quotation_not_accepted: quotation % has no accepted customer decision', p_quotation_id
      using errcode = 'check_violation';
  end if;

  select * into v_prospect from app.prospects where id = v_quotation.prospect_id;
  if v_prospect.legal_name is null or length(trim(v_prospect.legal_name)) = 0 then
    raise exception 'missing_legal_name: prospect % has no legal_name to convert', v_prospect.id
      using errcode = 'check_violation';
  end if;

  if p_target_account_id is not null then
    select * into v_account from app.accounts where id = p_target_account_id;
    if not found or v_account.tenant_id <> v_quotation.tenant_id or v_account.status = 'merged' then
      raise exception 'target_account_not_found: no active account % in tenant %', p_target_account_id, v_quotation.tenant_id
        using errcode = 'no_data_found';
    end if;
    v_outcome := 'linked_existing';
  else
    v_normalized_legal_name := app.normalize_prospect_identifier(v_prospect.legal_name);
    v_normalized_tax_id := app.normalize_prospect_identifier(v_prospect.tax_id);
    v_fingerprint := app.compute_prospect_duplicate_fingerprint(v_quotation.tenant_id, v_normalized_legal_name, v_normalized_tax_id);

    begin
      insert into app.accounts (
        tenant_id, legal_name, trade_name, tax_id, normalized_legal_name, normalized_tax_id,
        duplicate_fingerprint, billing_address, parent_account_id, source_prospect_id,
        owner_user_id, org_unit_id, created_by
      ) values (
        v_quotation.tenant_id, v_prospect.legal_name, v_prospect.trade_name, v_prospect.tax_id,
        v_normalized_legal_name, v_normalized_tax_id, v_fingerprint,
        coalesce(v_quotation.customer_snapshot -> 'billing_address', v_prospect.billing_address, '{}'::jsonb),
        p_parent_account_id, v_prospect.id, p_actor_auth_user_id, v_quotation.org_unit_id, p_actor_label
      )
      returning * into v_account;
      v_outcome := 'created';
    exception
      when unique_violation then
        select * into v_account from app.accounts where tenant_id = v_quotation.tenant_id and duplicate_fingerprint = v_fingerprint and status = 'active';
        v_outcome := 'linked_existing';
    end;
  end if;

  begin
    insert into app.account_conversions (tenant_id, quotation_id, prospect_id, account_id, outcome, converted_by)
    values (v_quotation.tenant_id, p_quotation_id, v_prospect.id, v_account.id, v_outcome, p_actor_label);
  exception
    when unique_violation then
      select * into v_existing_conversion from app.account_conversions where quotation_id = p_quotation_id;
      select * into v_account from app.accounts where id = v_existing_conversion.account_id;
      return v_account;
  end;

  -- Reuse contacts (Prompt 155 §20 task 3: "reused contacts/address/site relationships")
  -- -- every contact linked to the source prospect is also linked to the resulting
  -- account, idempotent via app.link_contact_to_record's own (contact_id, related_type,
  -- related_id, role) uniqueness.
  for v_link in select * from app.contact_links where related_type = 'prospect' and related_id = v_prospect.id loop
    perform app.link_contact_to_record(v_link.contact_id, 'account', v_account.id, v_link.role, v_link.is_primary, p_actor_auth_user_id, p_actor_label);
  end loop;

  -- Closes app.opportunities.account_ref's own disclosed forward-reference (COM-147).
  update app.opportunities set account_ref = v_account.id::text where id = v_quotation.opportunity_id;

  perform app.capture_audit_event(
    v_quotation.tenant_id, p_actor_auth_user_id, p_actor_label, 'convert_quotation_to_account',
    'app.accounts', v_account.id, 'success', null,
    jsonb_build_object('quotation_id', p_quotation_id, 'prospect_id', v_prospect.id),
    jsonb_build_object('outcome', v_outcome, 'account_id', v_account.id)
  );

  return v_account;
end;
$$;

comment on function app.convert_quotation_to_account is
  'COM-155: the one atomic, idempotent (unique(quotation_id) on app.account_conversions) create-or-link operation. A concurrent create-new race against the same legal identity is caught (unique_violation on accounts_tenant_fingerprint_active_unique) and re-resolved as a link to the winning row, never a duplicate account and never a hard failure on genuine concurrency (Prompt 155 §27''s own scenario).';

-- Extends the one shared polymorphic resolver (COM-145, extended by COM-147) to a fourth
-- related_type, rather than adding a second competing resolver.
create or replace function app.resolve_commercial_record_ref(
  p_related_type text,
  p_related_id uuid
)
returns table (tenant_id uuid, owner_user_id uuid, org_unit_id uuid)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  if p_related_type = 'lead' then
    return query select l.tenant_id, l.owner_user_id, l.org_unit_id from app.leads l where l.id = p_related_id;
  elsif p_related_type = 'prospect' then
    return query select p.tenant_id, p.owner_user_id, p.org_unit_id from app.prospects p where p.id = p_related_id;
  elsif p_related_type = 'opportunity' then
    return query select o.tenant_id, o.owner_user_id, o.org_unit_id from app.opportunities o where o.id = p_related_id;
  elsif p_related_type = 'account' then
    return query select a.tenant_id, a.owner_user_id, a.org_unit_id from app.accounts a where a.id = p_related_id;
  else
    raise exception 'unknown_related_type: %', p_related_type using errcode = 'check_violation';
  end if;

  if not found then
    raise exception 'related_record_not_found: % %', p_related_type, p_related_id using errcode = 'no_data_found';
  end if;
end;
$$;

comment on function app.resolve_commercial_record_ref is
  'COM-145, extended by COM-147/COM-155: the one shared polymorphic-target resolver for contact_links/activities and any later Commercial polymorphic table -- extend the IF/ELSIF chain here, never add a second competing resolver. COM-155 adds the ''account'' branch.';

alter table app.contact_links drop constraint contact_links_related_type_check;
alter table app.contact_links add constraint contact_links_related_type_check check (related_type in ('lead', 'prospect', 'opportunity', 'account'));

-- No separate masked directory view -- unlike app.quotations_directory/app.margin_
-- calculations_directory (which mask real columns), nothing on app.accounts needs
-- masking (this migration's own header discloses why: no billing-shaped action exists
-- in the fixed permissions_action_check enum to gate one on). app.accounts' own RLS
-- policy below is the complete read path, the same choice this migration family already
-- made for app.quotation_approval_rules (COM-153) -- a directory view only when masking
-- is real, never a reflexive one-per-table habit.

alter table app.accounts enable row level security;
alter table app.account_conversions enable row level security;

create policy accounts_select_scoped on app.accounts
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

create policy account_conversions_select_scoped on app.account_conversions
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke of
-- PostgreSQL's PUBLIC-execute default, the standing per-migration convention since
-- PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant select on app.accounts to authenticated, service_role;
grant insert, update, delete on app.accounts to service_role;
grant select on app.account_conversions to authenticated, service_role;
grant insert, update, delete on app.account_conversions to service_role;

grant execute on function app.find_duplicate_accounts(uuid, uuid, text, text) to authenticated, service_role;
grant execute on function app.get_account_conversion_readiness(uuid, uuid) to authenticated, service_role;
grant execute on function app.convert_quotation_to_account(uuid, uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.resolve_commercial_record_ref(text, uuid) to authenticated, service_role;
