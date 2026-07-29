-- Finance capability FIN-192 (Chart of Accounts, CG-S9-FIN-003)
-- A tenant/company-aware chart of accounts with canonical account semantics
-- (type, normal balance, hierarchy, posting eligibility, effective state) --
-- the account master required for balanced posting, statements, and
-- reconciliation later in Phase 4.
--
-- Reuse decision (disclosed, matching FIN-191's own header discipline): this
-- capability is a real domain table with its own draft/active/inactive
-- lifecycle, NOT layered on `PLT-121`'s Configuration Engine -- a chart of
-- accounts is hierarchical account *master data*, structurally unlike a flat
-- key/value policy set, and every other Finance capability's own authority
-- model in this phase (RBAC via `app.evaluate_permission`, no forced
-- `tenant_admin` layering) matches this repository's own established
-- standalone-business-table pattern (`app.margin_rule_versions`, COM-150)
-- rather than the Configuration Engine's own stricter `tenant_admin`/Supreme
-- draft-authority requirement (which FIN-191 disclosed as a deliberate,
-- capability-specific stricter gate for *policy configuration*, not a
-- repository-wide requirement for every Finance table).
--
-- Closes FIN-191's own disclosed forward reference: `finance_posting_map`
-- config items stored account-code references structurally only (no Chart of
-- Accounts existed yet in that dependency order). This migration
-- `CREATE OR REPLACE FUNCTION`s `app.publish_finance_config_version` (the
-- established later-migration-extends-an-earlier-one's-function pattern,
-- e.g. `20260724290000_create_commercial_customer_account_conversion.sql`)
-- to add a real existence/active/postable check for `finance_posting_map`
-- publishes from this point forward -- Prompt 191 section 25's "every posting
-- map resolves to active compatible accounts" is now genuinely enforced, not
-- merely disclosed as pending.
--
-- Money/decimal discipline: this migration introduces zero money-shaped
-- column (the account master carries no balance -- posting/balance capture is
-- a later capability's own scope, `FIN-202`/`FIN-203`).
--
-- Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration carries
-- its own explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM
-- PUBLIC` statement before its final grants, the standing per-migration
-- convention since `PLT-118`.

create table app.finance_accounts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  company_id uuid references app.org_units (id),
  code text not null,
  name text not null,
  account_type text not null,
  normal_balance text not null,
  parent_account_id uuid references app.finance_accounts (id),
  is_control_account boolean not null default false,
  is_postable boolean not null default true,
  currency_restriction text,
  status text not null default 'draft',
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint finance_accounts_status_check check (status in ('draft', 'active', 'inactive')),
  constraint finance_accounts_account_type_check check (account_type in ('asset', 'liability', 'equity', 'revenue', 'expense')),
  constraint finance_accounts_normal_balance_check check (normal_balance in ('debit', 'credit')),
  -- Canonical accounting identity (Prompt 192 section 24: "canonical accounting states
  -- and dimensions remain stable"): asset/expense are debit-normal;
  -- liability/equity/revenue are credit-normal. Never configurable per tenant.
  constraint finance_accounts_type_balance_match_check check (
    (account_type in ('asset', 'expense') and normal_balance = 'debit') or
    (account_type in ('liability', 'equity', 'revenue') and normal_balance = 'credit')
  ),
  constraint finance_accounts_not_self_parent check (parent_account_id is null or parent_account_id <> id),
  constraint finance_accounts_currency_restriction_check check (currency_restriction is null or currency_restriction ~ '^[A-Z]{3}$'),
  -- A control account is never itself directly postable unless an explicit,
  -- approved rule overrides it (Prompt 192 section 24) -- this checkpoint has no such
  -- override mechanism, so a control account is structurally never postable.
  constraint finance_accounts_control_not_postable_check check (not (is_control_account and is_postable))
);

comment on table app.finance_accounts is
  'FIN-192: tenant/company-aware chart-of-accounts master. company_id null = tenant-wide account; non-null = company-scoped (Prompt 192 section 3). Carries no balance -- posting/balance capture is FIN-202/203''s own scope.';

create unique index finance_accounts_tenant_company_code_unique on app.finance_accounts (
  tenant_id, coalesce(company_id, '00000000-0000-0000-0000-000000000000'::uuid), code
);
create index finance_accounts_tenant_id_idx on app.finance_accounts (tenant_id);
create index finance_accounts_parent_account_id_idx on app.finance_accounts (parent_account_id);
create index finance_accounts_tenant_status_idx on app.finance_accounts (tenant_id, status);

create function app.touch_finance_account_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger finance_accounts_touch_row
  before update on app.finance_accounts
  for each row
  execute function app.touch_finance_account_row();

create function app.check_finance_account_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
as $$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'FIN', p_action)).allowed;
$$;

comment on function app.check_finance_account_authority is
  'FIN-192: FIN:Create/Edit gates draft/amend; FIN:Approve gates activate; FIN:Delete gates deactivate; FIN:View gates read -- the canonical PLT-111 FIN permission catalogue, reused directly (no new permission-catalogue row), matching FIN-191''s own authority-mapping discipline.';

-- Bounded, acyclic hierarchy walk (depth<=10, mirroring PLT-120's own
-- app.resolve_master_record() merge-chain bound for the same "never loop
-- forever on malformed/adversarial data" reason). Returns true if walking up
-- from p_start_account_id's own parent chain ever reaches p_start_account_id
-- again, or exceeds the depth bound (treated as a cycle -- an honest,
-- disclosed fail-closed choice, not a silent pass).
create function app.detect_finance_account_hierarchy_cycle(p_start_account_id uuid, p_candidate_parent_id uuid)
returns boolean
language plpgsql
stable
as $$
declare
  v_current uuid := p_candidate_parent_id;
  v_depth integer := 0;
begin
  if p_candidate_parent_id is null then
    return false;
  end if;
  while v_current is not null loop
    if v_current = p_start_account_id then
      return true;
    end if;
    v_depth := v_depth + 1;
    if v_depth > 10 then
      return true;
    end if;
    select parent_account_id into v_current from app.finance_accounts where id = v_current;
  end loop;
  return false;
end;
$$;

create function app.create_finance_account_draft(
  p_tenant_id uuid,
  p_company_id uuid,
  p_code text,
  p_name text,
  p_account_type text,
  p_normal_balance text,
  p_parent_account_id uuid,
  p_is_control_account boolean,
  p_currency_restriction text,
  p_actor_auth_user_id uuid,
  p_created_by text
)
returns app.finance_accounts
language plpgsql
as $$
declare
  v_parent app.finance_accounts;
  v_account app.finance_accounts;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_account_authority('Create', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Create for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_parent_account_id is not null then
    select * into v_parent from app.finance_accounts where id = p_parent_account_id;
    if not found then
      raise exception 'finance_account_parent_not_found: %', p_parent_account_id using errcode = 'no_data_found';
    end if;
    if v_parent.tenant_id <> p_tenant_id or v_parent.company_id is distinct from p_company_id then
      raise exception 'finance_account_cross_scope_parent: parent account % does not share this account''s own tenant/company scope', p_parent_account_id
        using errcode = 'check_violation';
    end if;
    if v_parent.account_type <> p_account_type then
      raise exception 'finance_account_type_mismatch: parent account % is type % but child requests type %', p_parent_account_id, v_parent.account_type, p_account_type
        using errcode = 'check_violation';
    end if;
  end if;

  begin
    insert into app.finance_accounts (
      tenant_id, company_id, code, name, account_type, normal_balance,
      parent_account_id, is_control_account, is_postable, currency_restriction, created_by
    )
    values (
      p_tenant_id, p_company_id, p_code, p_name, p_account_type, p_normal_balance,
      p_parent_account_id, coalesce(p_is_control_account, false), not coalesce(p_is_control_account, false), p_currency_restriction, p_created_by
    )
    returning * into v_account;
  exception
    when unique_violation then
      raise exception 'finance_account_duplicate_code: code % already exists in this tenant/company scope', p_code
        using errcode = 'unique_violation';
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_created_by, 'create_finance_account_draft',
    'app.finance_accounts', v_account.id, 'success', null, null, to_jsonb(v_account)
  );

  return v_account;
end;
$$;

create function app.amend_finance_account_draft(
  p_account_id uuid,
  p_expected_version integer,
  p_name text,
  p_currency_restriction text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_accounts
language plpgsql
as $$
declare
  v_account app.finance_accounts;
begin
  select * into v_account from app.finance_accounts where id = p_account_id;
  if not found then
    raise exception 'finance_account_not_found: %', p_account_id using errcode = 'no_data_found';
  end if;

  if v_account.record_version <> p_expected_version then
    raise exception 'stale_version: account % expected version % but found %', p_account_id, p_expected_version, v_account.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_account.status <> 'draft' then
    raise exception 'finance_account_not_draft: account % is %, only a draft may be amended (use governed correction otherwise)', p_account_id, v_account.status
      using errcode = 'check_violation';
  end if;

  if not app.check_finance_account_authority('Edit', v_account.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_account.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.finance_accounts
  set name = coalesce(p_name, name), currency_restriction = p_currency_restriction
  where id = p_account_id and record_version = p_expected_version
  returning * into v_account;

  perform app.capture_audit_event(
    v_account.tenant_id, p_actor_auth_user_id, p_actor_label, 'amend_finance_account_draft',
    'app.finance_accounts', v_account.id, 'success', null, null, to_jsonb(v_account)
  );

  return v_account;
end;
$$;

create function app.activate_finance_account(
  p_account_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_accounts
language plpgsql
as $$
declare
  v_account app.finance_accounts;
  v_parent app.finance_accounts;
begin
  select * into v_account from app.finance_accounts where id = p_account_id;
  if not found then
    raise exception 'finance_account_not_found: %', p_account_id using errcode = 'no_data_found';
  end if;

  if v_account.record_version <> p_expected_version then
    raise exception 'stale_version: account % expected version % but found %', p_account_id, p_expected_version, v_account.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_account.status <> 'draft' then
    raise exception 'finance_account_not_draft: account % is %, only a draft may be activated', p_account_id, v_account.status
      using errcode = 'check_violation';
  end if;

  if not app.check_finance_account_authority('Approve', v_account.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_account.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if app.detect_finance_account_hierarchy_cycle(v_account.id, v_account.parent_account_id) then
    raise exception 'finance_account_hierarchy_cycle: activating account % would create or confirm a cyclic/over-deep hierarchy', p_account_id
      using errcode = 'check_violation';
  end if;

  if v_account.parent_account_id is not null then
    select * into v_parent from app.finance_accounts where id = v_account.parent_account_id;
    if v_parent.status = 'inactive' then
      raise exception 'finance_account_parent_inactive: parent account % is inactive', v_account.parent_account_id
        using errcode = 'check_violation';
    end if;
  end if;

  update app.finance_accounts
  set status = 'active'
  where id = p_account_id and record_version = p_expected_version
  returning * into v_account;

  perform app.capture_audit_event(
    v_account.tenant_id, p_actor_auth_user_id, p_actor_label, 'activate_finance_account',
    'app.finance_accounts', v_account.id, 'success', null, null, to_jsonb(v_account)
  );

  return v_account;
end;
$$;

-- Dependency-impact preview (Prompt 192 section 14's own "dependency-impact
-- operation"): every direct child, plus whether any published finance_posting_map
-- item at any scope for this tenant currently references this account's own code.
create function app.get_finance_account_dependency_impact(p_account_id uuid, p_actor_auth_user_id uuid)
returns jsonb
language plpgsql
as $$
declare
  v_account app.finance_accounts;
  v_child_count integer;
  v_referenced_by_posting_map boolean := false;
  v_row record;
begin
  select * into v_account from app.finance_accounts where id = p_account_id;
  if not found then
    raise exception 'finance_account_not_found: %', p_account_id using errcode = 'no_data_found';
  end if;

  if not app.check_finance_account_authority('View', v_account.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, v_account.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select count(*) into v_child_count from app.finance_accounts where parent_account_id = p_account_id and status <> 'inactive';

  for v_row in select * from app.resolve_finance_config('finance_posting_map', v_account.tenant_id) loop
    if exists (
      select 1 from jsonb_each(v_row.items) e
      where (e.value ->> 'accountCodeRef') = v_account.code
    ) then
      v_referenced_by_posting_map := true;
    end if;
  end loop;

  return jsonb_build_object(
    'accountId', v_account.id,
    'code', v_account.code,
    'activeChildAccountCount', v_child_count,
    'referencedByPublishedPostingMap', v_referenced_by_posting_map
  );
end;
$$;

comment on function app.get_finance_account_dependency_impact is
  'FIN-192: the dependency-impact read path (Prompt 192 section 14/section 25). referencedByPublishedPostingMap closes FIN-191''s own disclosed forward reference -- the first point in this dependency order where a posting-map account-code reference can be resolved against a real account.';

-- Deactivation guard (Prompt 192 section 23/section 24: "reject ... deactivation of an
-- account required by active/posted records", "referenced accounts are never
-- hard-deleted by normal roles"). This checkpoint checks the one real
-- reference that exists today (an active/draft child account) plus the
-- published-posting-map reference surfaced by the dependency-impact read
-- above. No journal/subledger/posting table exists yet in this dependency
-- order -- that reference class is FIN-202/203's own forward hook, added via
-- `CREATE OR REPLACE FUNCTION` once it exists, the same disclosed-forward-
-- reference discipline FIN-191's own header already established.
create function app.deactivate_finance_account(
  p_account_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_accounts
language plpgsql
as $$
declare
  v_account app.finance_accounts;
  v_child_count integer;
  v_referenced_by_posting_map boolean := false;
  v_row record;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_account_deactivation_reason_required: a non-empty reason is required'
      using errcode = 'check_violation';
  end if;

  select * into v_account from app.finance_accounts where id = p_account_id;
  if not found then
    raise exception 'finance_account_not_found: %', p_account_id using errcode = 'no_data_found';
  end if;

  if v_account.record_version <> p_expected_version then
    raise exception 'stale_version: account % expected version % but found %', p_account_id, p_expected_version, v_account.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_account.status <> 'active' then
    raise exception 'finance_account_not_active: account % is %, only an active account may be deactivated', p_account_id, v_account.status
      using errcode = 'check_violation';
  end if;

  if not app.check_finance_account_authority('Delete', v_account.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Delete for tenant %', p_actor_auth_user_id, v_account.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select count(*) into v_child_count from app.finance_accounts where parent_account_id = p_account_id and status <> 'inactive';
  if v_child_count > 0 then
    raise exception 'finance_account_has_active_children: account % has % active/draft child account(s) -- deactivate or reparent them first', p_account_id, v_child_count
      using errcode = 'check_violation';
  end if;

  for v_row in select * from app.resolve_finance_config('finance_posting_map', v_account.tenant_id) loop
    if exists (select 1 from jsonb_each(v_row.items) e where (e.value ->> 'accountCodeRef') = v_account.code) then
      v_referenced_by_posting_map := true;
    end if;
  end loop;
  if v_referenced_by_posting_map then
    raise exception 'finance_account_referenced_by_posting_map: account % is referenced by a published posting map -- update the posting map first', p_account_id
      using errcode = 'check_violation';
  end if;

  update app.finance_accounts
  set status = 'inactive'
  where id = p_account_id and record_version = p_expected_version
  returning * into v_account;

  perform app.capture_audit_event(
    v_account.tenant_id, p_actor_auth_user_id, p_actor_label, 'deactivate_finance_account',
    'app.finance_accounts', v_account.id, 'success', p_reason, null, to_jsonb(v_account)
  );

  return v_account;
end;
$$;

-- List/tree read (Prompt 192 section 14's own "list/tree" operation) -- server-side,
-- bounded, RLS-scoped (no browser-loaded full dataset -- callers page/filter by
-- tenant/company/status at the query layer, this function only adds the
-- authority gate the plain RLS-scoped select does not need for a read).
create function app.list_finance_accounts(
  p_tenant_id uuid,
  p_company_id uuid,
  p_status text,
  p_actor_auth_user_id uuid
)
returns setof app.finance_accounts
language plpgsql
stable
as $$
begin
  if not app.check_finance_account_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
    select * from app.finance_accounts
    where tenant_id = p_tenant_id
      and company_id is not distinct from p_company_id
      and (p_status is null or status = p_status)
    order by code asc;
end;
$$;

-- Closes FIN-191's own disclosed forward reference (this migration's own
-- header): extends the finance_posting_map publish gate with a real
-- existence/active/postable check now that app.finance_accounts exists.
-- CREATE OR REPLACE (not a new function) -- the established later-migration-
-- extends-an-earlier-one's-function pattern.
create or replace function app.publish_finance_config_version(
  p_version_id uuid,
  p_actor_auth_user_id uuid,
  p_effective_from timestamptz,
  p_actor_label text
)
returns app.config_versions
language plpgsql
as $$
declare
  v_version app.config_versions;
  v_object app.config_objects;
  v_item record;
  v_ref text;
  v_account app.finance_accounts;
begin
  select * into v_version from app.config_versions where id = p_version_id;
  if not found then
    raise exception 'config_version_not_found: no config version %', p_version_id
      using errcode = 'no_data_found';
  end if;
  select * into v_object from app.config_objects where id = v_version.config_object_id;

  if not app.is_finance_config_type(v_object.config_type_code) then
    raise exception 'not_finance_config_type: % is not a Finance Configuration class', v_object.config_type_code
      using errcode = 'check_violation';
  end if;
  if not app.check_finance_config_authority('Approve', v_object.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_object.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  perform app.validate_finance_config_version(p_version_id, v_object.config_type_code);

  -- FIN-192 addition: a finance_posting_map publish now also requires every
  -- referenced account code to resolve to an active, postable account in this
  -- tenant -- Prompt 191 section 25 / Prompt 192's own closed forward reference.
  if v_object.config_type_code = 'finance_posting_map' then
    for v_item in select key, value from app.config_items where config_version_id = p_version_id loop
      v_ref := v_item.value ->> 'accountCodeRef';
      select * into v_account from app.finance_accounts
        where tenant_id = v_object.tenant_id and code = v_ref
          and company_id is not distinct from case when v_object.scope_level = 'company' then v_object.scope_id else null end;
      if not found then
        raise exception 'finance_posting_map_unresolved_account: posting map key % references account code % which does not exist in this tenant''s chart of accounts', v_item.key, v_ref
          using errcode = 'check_violation';
      end if;
      if v_account.status <> 'active' then
        raise exception 'finance_posting_map_inactive_account: posting map key % references account code % which is not active (status=%)', v_item.key, v_ref, v_account.status
          using errcode = 'check_violation';
      end if;
      if not v_account.is_postable then
        raise exception 'finance_posting_map_not_postable_account: posting map key % references account code % which is not postable (control account)', v_item.key, v_ref
          using errcode = 'check_violation';
      end if;
    end loop;
  end if;

  return app.publish_config_version(p_version_id, p_actor_auth_user_id, p_effective_from, p_actor_label);
end;
$$;

comment on function app.publish_finance_config_version is
  'FIN-191/FIN-192: FIN:Approve-gated publish, structurally validated per class. From FIN-192 onward, a finance_posting_map publish additionally requires every referenced account code to resolve to an active, postable app.finance_accounts row in this tenant -- closes FIN-191''s own disclosed forward reference.';

alter table app.finance_accounts enable row level security;

create policy finance_accounts_select_scoped on app.finance_accounts
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable
-- revoke of PostgreSQL's PUBLIC-execute default, the standing per-migration
-- convention since PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant select on app.finance_accounts to authenticated, service_role;
grant insert, update, delete on app.finance_accounts to service_role;
grant execute on function app.touch_finance_account_row() to service_role;
grant execute on function app.check_finance_account_authority(text, uuid, uuid) to service_role;
grant execute on function app.detect_finance_account_hierarchy_cycle(uuid, uuid) to service_role;
grant execute on function app.create_finance_account_draft(uuid, uuid, text, text, text, text, uuid, boolean, text, uuid, text) to authenticated, service_role;
grant execute on function app.amend_finance_account_draft(uuid, integer, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.activate_finance_account(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.deactivate_finance_account(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.get_finance_account_dependency_impact(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_finance_accounts(uuid, uuid, text, uuid) to authenticated, service_role;
