-- Platform Core capability PLT-106 (Subscription/Module/Feature Entitlement, CG-S6-PLT-003)
-- Versioned tenant entitlements: package -> granted modules/features/quotas -> tenant
-- assignment -> per-tenant reasoned override, plus the evaluator that answers stage 1 of
-- the 8-stage access-evaluation flow (docs/architecture/06_RLS_RBAC_WORKSTREAM.md §3:
-- "1 Entitlement: module/feature subscribed" -- the first gate, before tenant membership
-- (stage 2) or RBAC (stage 3). Entitlement is necessary but never sufficient authorization
-- (Prompt 106 §16/§24) -- this migration grants no role/record/field access by itself.

-- Canonical module/feature catalogue -- reproduced verbatim from the already-VERIFIED
-- docs/architecture/01_MODULE_DEPENDENCY_MAP.md §3.2 business-domain table (module codes)
-- and each domain's own sub-module column (feature codes), not invented. Codes are stable;
-- names may be relabeled later without ever renumbering a code (Prompt 106 §24).
create table app.entitlement_modules (
  code text primary key,
  name text not null,
  owning_phase integer not null,
  created_at timestamptz not null default now()
);

comment on table app.entitlement_modules is
  'Canonical business-domain module catalogue (PLT-106), reproduced from docs/architecture/01_MODULE_DEPENDENCY_MAP.md §3.2. Codes are stable and never reused for a different domain.';

insert into app.entitlement_modules (code, name, owning_phase) values
  ('COM', 'Commercial (CRM, Quotation)', 2),
  ('OPS', 'Operations (Job/Shipment, TMS, WMS, Milestone, ePOD)', 3),
  ('FIN', 'Finance and Accounting', 4),
  ('PRC', 'Procurement and Vendor Management', 6),
  ('HRS', 'HRIS', 7),
  ('TKT', 'Ticketing', 7),
  ('CPT', 'Customer Portal', 3),
  ('LYL', 'Loyalty and Rewards', 8),
  ('REP', 'Reporting/Analytics Engine', 1);

create table app.entitlement_features (
  code text primary key,
  module_code text not null references app.entitlement_modules (code),
  name text not null,
  created_at timestamptz not null default now()
);

comment on table app.entitlement_features is
  'Canonical sub-module (feature) catalogue per business domain (PLT-106), reproduced from docs/architecture/01_MODULE_DEPENDENCY_MAP.md §3.2''s per-domain sub-module column.';

create index entitlement_features_module_code_idx on app.entitlement_features (module_code);

insert into app.entitlement_features (code, module_code, name) values
  ('COM-LEAD', 'COM', 'Lead management'),
  ('COM-CRM', 'COM', 'CRM'),
  ('COM-OPP', 'COM', 'Opportunity management'),
  ('COM-QTN', 'COM', 'Quotation'),
  ('COM-CPR', 'COM', 'Commercial pricing/rates'),
  ('OPS-SHP', 'OPS', 'Job/Shipment'),
  ('OPS-TMS', 'OPS', 'Transport management'),
  ('OPS-WMS', 'OPS', 'Warehouse management'),
  ('OPS-TRK', 'OPS', 'Milestone tracking'),
  ('OPS-DOC', 'OPS', 'ePOD/operations documents'),
  ('OPS-CST', 'OPS', 'Operations cost'),
  ('FIN-GL', 'FIN', 'General ledger'),
  ('FIN-AR', 'FIN', 'Accounts receivable'),
  ('FIN-AP', 'FIN', 'Accounts payable'),
  ('FIN-TAX', 'FIN', 'Tax'),
  ('FIN-CLS', 'FIN', 'Period close'),
  ('FIN-PRF', 'FIN', 'Financial reporting/profitability'),
  ('PRC-VND', 'PRC', 'Vendor management'),
  ('PRC-ASM', 'PRC', 'Assignment/sourcing'),
  ('PRC-RTE', 'PRC', 'Rate management'),
  ('PRC-SRC', 'PRC', 'Procurement sourcing'),
  ('PRC-POI', 'PRC', 'Purchase order/invoice'),
  ('HRS-EMP', 'HRS', 'Employee records'),
  ('HRS-REC', 'HRS', 'Recruitment'),
  ('HRS-ATT', 'HRS', 'Attendance'),
  ('HRS-PAY', 'HRS', 'Payroll'),
  ('HRS-KPI', 'HRS', 'Performance/KPI'),
  ('HRS-ESS', 'HRS', 'Employee self-service'),
  ('TKT-INT', 'TKT', 'Internal ticketing'),
  ('TKT-CUS', 'TKT', 'Customer ticketing'),
  ('TKT-HLP', 'TKT', 'Help desk'),
  ('TKT-SLA', 'TKT', 'SLA management'),
  ('CPT-QBK', 'CPT', 'Quote/booking'),
  ('CPT-TRK', 'CPT', 'Customer tracking'),
  ('CPT-WHS', 'CPT', 'Warehouse order (customer-facing)'),
  ('CPT-BIL', 'CPT', 'Customer billing view'),
  ('CPT-CX', 'CPT', 'Customer experience'),
  ('LYL-PRG', 'LYL', 'Loyalty program'),
  ('LYL-PNT', 'LYL', 'Points'),
  ('LYL-RDM', 'LYL', 'Redemption'),
  ('LYL-ANL', 'LYL', 'Loyalty analytics');

-- Versioned package catalogue -- Supreme-controlled, global (not tenant-specific). A
-- published version is immutable; a "new version" is a new row, never an in-place edit
-- of a row a tenant may already be assigned to (Prompt 106 §20 task 1: "versioned...
-- effective-date behavior").
create table app.entitlement_packages (
  id uuid primary key default gen_random_uuid(),
  code text not null,
  name text not null,
  version integer not null,
  status text not null default 'draft',
  granted_modules text[] not null default '{}',
  feature_limits jsonb not null default '{}'::jsonb,
  effective_from timestamptz,
  effective_until timestamptz,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint entitlement_packages_status_check
    check (status in ('draft', 'published', 'retired')),
  constraint entitlement_packages_code_version_unique unique (code, version)
);

comment on table app.entitlement_packages is
  'Versioned subscription package catalogue (PLT-106). granted_modules lists module codes this package version grants; feature_limits maps a feature code to its numeric quota (JSON null = unlimited). A published version is treated as immutable by convention -- enforced at the application layer today, a trigger is added if Prompt 138 hardening finds it necessary.';

create index entitlement_packages_code_idx on app.entitlement_packages (code, version desc);

-- Tenant assignment -- Prompt 106 §20 task 2: "tenant assignment/renewal/trial/suspend/
-- expire transitions." Only one non-terminal (trial/active/suspended) assignment per
-- tenant at a time -- enforced by the partial unique index below, not merely convention.
create table app.tenant_entitlements (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  package_id uuid not null references app.entitlement_packages (id),
  status text not null default 'trial',
  trial_ends_at timestamptz,
  effective_from timestamptz not null default now(),
  effective_until timestamptz,
  assigned_by text,
  reason text,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint tenant_entitlements_status_check
    check (status in ('trial', 'active', 'suspended', 'expired', 'cancelled'))
);

comment on table app.tenant_entitlements is
  'Tenant-to-package assignment lifecycle (PLT-106): trial -> active -> suspended -> active (reactivate) -> expired|cancelled (terminal). Mirrors app.tenants'' own lifecycle-trigger pattern from PLT-105.';

create unique index tenant_entitlements_one_active_per_tenant
  on app.tenant_entitlements (tenant_id)
  where status in ('trial', 'active', 'suspended');

create index tenant_entitlements_tenant_id_idx on app.tenant_entitlements (tenant_id, effective_from desc);

-- Reasoned, time-bounded, audited override -- Prompt 106 §22 ("Trial/grace/override uses
-- explicit authority/expiry/reason and remains audited") and §24's "no hard-coded tenant
-- exceptions": this is a *data* row an authorized actor creates, with a mandatory reason
-- and a mandatory expiry, never an application-code branch keyed on a tenant id.
create table app.tenant_entitlement_overrides (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  module_code text not null references app.entitlement_modules (code),
  feature_code text references app.entitlement_features (code),
  granted boolean not null,
  limit_override numeric,
  reason text not null,
  granted_by text not null,
  expires_at timestamptz not null,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  constraint tenant_entitlement_overrides_expiry_check check (expires_at > created_at)
);

comment on table app.tenant_entitlement_overrides is
  'Explicit, reasoned, time-bounded per-tenant entitlement override (PLT-106) -- a data row, never hard-coded tenant-specific application logic (Prompt 106 §24). feature_code null means the override applies at module level.';

create index tenant_entitlement_overrides_lookup_idx
  on app.tenant_entitlement_overrides (tenant_id, module_code, feature_code)
  where revoked_at is null;

-- Append-only assignment/transition audit trail -- Prompt 106 §18 ("Record package/
-- version/assignment/change/override/reason/effective actor"), the identical bounded
-- lifecycle-audit pattern app.tenant_status_history already established at PLT-105.
create table app.entitlement_assignment_history (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  from_package_id uuid references app.entitlement_packages (id),
  to_package_id uuid references app.entitlement_packages (id),
  from_status text,
  to_status text not null,
  reason text,
  requested_by text,
  occurred_at timestamptz not null default now()
);

create index entitlement_assignment_history_tenant_id_idx
  on app.entitlement_assignment_history (tenant_id, occurred_at desc);

-- Valid transition matrix (same discipline as PLT-105's app.enforce_tenant_status_transition
-- -- one canonical definition, enforced in the database, never duplicated in application code):
--   trial     -> active | expired | cancelled
--   active    -> suspended | expired | cancelled
--   suspended -> active | expired | cancelled
--   expired, cancelled -> (none; terminal)
create function app.enforce_tenant_entitlement_transition()
returns trigger
language plpgsql
as $$
begin
  if new.status = old.status then
    return new;
  end if;

  if old.status in ('expired', 'cancelled') then
    raise exception 'invalid_entitlement_transition: tenant entitlement % is %, no further transition is allowed', old.id, old.status
      using errcode = 'check_violation';
  end if;

  if not (
    (old.status = 'trial' and new.status in ('active', 'expired', 'cancelled'))
    or (old.status = 'active' and new.status in ('suspended', 'expired', 'cancelled'))
    or (old.status = 'suspended' and new.status in ('active', 'expired', 'cancelled'))
  ) then
    raise exception 'invalid_entitlement_transition: % -> % is not a canonical transition', old.status, new.status
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

create trigger tenant_entitlements_enforce_transition
  before update of status on app.tenant_entitlements
  for each row
  execute function app.enforce_tenant_entitlement_transition();

create function app.touch_tenant_entitlement_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger tenant_entitlements_touch_row
  before update on app.tenant_entitlements
  for each row
  execute function app.touch_tenant_entitlement_row();

-- Assign a tenant to a package version (Prompt 106 §20 task 2). If the tenant already has
-- a non-terminal entitlement, it is transitioned to 'cancelled' first (recorded in history)
-- before the new assignment is inserted -- the partial unique index above makes any other
-- outcome impossible, this just makes the supersession an explicit, reasoned, auditable step
-- rather than a constraint-violation error.
create function app.assign_entitlement(
  p_tenant_id uuid,
  p_package_id uuid,
  p_status text,
  p_reason text,
  p_requested_by text,
  p_trial_ends_at timestamptz default null,
  p_effective_from timestamptz default now(),
  p_effective_until timestamptz default null
)
returns app.tenant_entitlements
language plpgsql
as $$
declare
  v_existing app.tenant_entitlements;
  v_assignment app.tenant_entitlements;
begin
  select * into v_existing
  from app.tenant_entitlements
  where tenant_id = p_tenant_id and status in ('trial', 'active', 'suspended');

  if found then
    update app.tenant_entitlements set status = 'cancelled', reason = 'superseded by new assignment'
    where id = v_existing.id;

    insert into app.entitlement_assignment_history (tenant_id, from_package_id, to_package_id, from_status, to_status, reason, requested_by)
    values (p_tenant_id, v_existing.package_id, p_package_id, v_existing.status, 'cancelled', 'superseded by new assignment', p_requested_by);
  end if;

  insert into app.tenant_entitlements (tenant_id, package_id, status, trial_ends_at, effective_from, effective_until, assigned_by, reason)
  values (p_tenant_id, p_package_id, p_status, p_trial_ends_at, p_effective_from, p_effective_until, p_requested_by, p_reason)
  returning * into v_assignment;

  insert into app.entitlement_assignment_history (tenant_id, from_package_id, to_package_id, from_status, to_status, reason, requested_by)
  values (p_tenant_id, null, p_package_id, null, p_status, p_reason, p_requested_by);

  return v_assignment;
end;
$$;

create function app.transition_entitlement_status(
  p_tenant_id uuid,
  p_new_status text,
  p_reason text,
  p_requested_by text
)
returns app.tenant_entitlements
language plpgsql
as $$
declare
  v_current app.tenant_entitlements;
  v_updated app.tenant_entitlements;
begin
  select * into v_current
  from app.tenant_entitlements
  where tenant_id = p_tenant_id and status in ('trial', 'active', 'suspended');

  if not found then
    raise exception 'entitlement_not_found: no active entitlement for tenant %', p_tenant_id
      using errcode = 'no_data_found';
  end if;

  update app.tenant_entitlements
  set status = p_new_status, reason = p_reason
  where id = v_current.id
  returning * into v_updated;

  insert into app.entitlement_assignment_history (tenant_id, from_package_id, to_package_id, from_status, to_status, reason, requested_by)
  values (p_tenant_id, v_current.package_id, v_current.package_id, v_current.status, p_new_status, p_reason, p_requested_by);

  return v_updated;
end;
$$;

-- The evaluator -- stage 1 of the 8-stage access flow (docs/architecture/06_RLS_RBAC_WORKSTREAM.md
-- §3). Deterministic, fail-closed on any unknown/missing/expired/stale state (Prompt 106 §23/§25).
-- Precedence, highest first: (1) a non-expired, non-revoked override for this tenant+module
-- [+feature] always wins, in either direction; (2) otherwise the tenant's current package
-- grant; (3) otherwise deny. A trial past its own trial_ends_at is treated as expired at
-- evaluation time even if no lifecycle job has transitioned the row yet (Prompt 106 §23:
-- "stale entitlement fails closed").
create type app.entitlement_decision as (
  allowed boolean,
  reason text,
  limit_value numeric,
  package_code text,
  evaluated_at timestamptz
);

create function app.evaluate_entitlement(
  p_tenant_id uuid,
  p_module_code text,
  p_feature_code text default null,
  p_as_of timestamptz default now()
)
returns app.entitlement_decision
language plpgsql
stable
as $$
declare
  v_assignment app.tenant_entitlements;
  v_package app.entitlement_packages;
  v_override app.tenant_entitlement_overrides;
  v_limit numeric;
  v_allowed boolean;
begin
  select te.* into v_assignment
  from app.tenant_entitlements te
  where te.tenant_id = p_tenant_id
    and te.status in ('trial', 'active')
    and te.effective_from <= p_as_of
    and (te.effective_until is null or te.effective_until > p_as_of)
  order by te.effective_from desc
  limit 1;

  if not found then
    return row(false, 'no_active_entitlement', null, null, p_as_of)::app.entitlement_decision;
  end if;

  if v_assignment.status = 'trial' and v_assignment.trial_ends_at is not null and v_assignment.trial_ends_at <= p_as_of then
    return row(false, 'trial_expired', null, null, p_as_of)::app.entitlement_decision;
  end if;

  select * into v_package from app.entitlement_packages where id = v_assignment.package_id;

  if not found or v_package.status <> 'published' then
    return row(false, 'package_not_published', null, null, p_as_of)::app.entitlement_decision;
  end if;

  if p_module_code = any (v_package.granted_modules) then
    v_allowed := true;
    if p_feature_code is null then
      v_limit := null;
    elsif v_package.feature_limits ? p_feature_code then
      v_limit := (v_package.feature_limits ->> p_feature_code)::numeric;
    else
      v_allowed := false;
    end if;
  else
    v_allowed := false;
  end if;

  select * into v_override
  from app.tenant_entitlement_overrides o
  where o.tenant_id = p_tenant_id
    and o.module_code = p_module_code
    and (o.feature_code is not distinct from p_feature_code or (o.feature_code is null and p_feature_code is not null))
    and o.revoked_at is null
    and o.expires_at > p_as_of
  order by o.created_at desc
  limit 1;

  if found then
    if v_override.granted then
      return row(true, 'override_granted', coalesce(v_override.limit_override, v_limit), v_package.code, p_as_of)::app.entitlement_decision;
    else
      return row(false, 'override_denied', null, v_package.code, p_as_of)::app.entitlement_decision;
    end if;
  end if;

  if v_allowed then
    return row(true, 'package_granted', v_limit, v_package.code, p_as_of)::app.entitlement_decision;
  end if;

  if p_feature_code is not null then
    return row(false, 'feature_not_entitled', null, v_package.code, p_as_of)::app.entitlement_decision;
  end if;
  return row(false, 'module_not_entitled', null, v_package.code, p_as_of)::app.entitlement_decision;
end;
$$;

comment on function app.evaluate_entitlement is
  'Stage-1 entitlement evaluator (PLT-106) -- deterministic, fail-closed, override-aware. Necessary but never sufficient authorization on its own (stages 2-8 of docs/architecture/06_RLS_RBAC_WORKSTREAM.md §3 still apply).';

-- RLS: identical defense-in-depth posture to PLT-105 -- anon/authenticated receive no
-- schema-level grant on any table this migration creates; service_role gets an explicit
-- grant. The general tenant-scoped exposure model remains PLT-113's own later capability.
alter table app.entitlement_modules enable row level security;
alter table app.entitlement_features enable row level security;
alter table app.entitlement_packages enable row level security;
alter table app.tenant_entitlements enable row level security;
alter table app.tenant_entitlement_overrides enable row level security;
alter table app.entitlement_assignment_history enable row level security;

grant select, insert, update, delete
  on app.entitlement_modules, app.entitlement_features, app.entitlement_packages,
     app.tenant_entitlements, app.tenant_entitlement_overrides, app.entitlement_assignment_history
  to service_role;
grant execute on function app.assign_entitlement(uuid, uuid, text, text, text, timestamptz, timestamptz, timestamptz) to service_role;
grant execute on function app.transition_entitlement_status(uuid, text, text, text) to service_role;
grant execute on function app.evaluate_entitlement(uuid, text, text, timestamptz) to service_role;
