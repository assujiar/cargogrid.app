-- Phase 7 (HRIS and Ticketing) capability CG-S12-HRT-002 (Employee Master, Prompt 274)
-- -- the FIRST Phase 7 capability. Builds app.employees as the canonical tenant-scoped
-- workforce profile: linked to -- never replacing -- Platform user identity
-- (app.users) and organization truth (app.org_units), per ADR-0023
-- (docs/adr/ADR-0023-phase7-hris-organization-team-and-employee-identity-
-- reconciliation.md, Part B).
--
-- Design decisions, disclosed rather than left implicit (matching every prior
-- checkpoint's discipline, mirrors ADR-0020/PRC-251's own header shape):
--
-- 1. **master_type_code='employee' IS registered** (ADR-0023 Part B left this open for
--    this checkpoint's own decision, "recommended, not forced"). Decision: register it,
--    mirroring the existing vendor/driver 1:1-extension-of-app.master_records pattern
--    exactly (app.vendor_profiles, 20260730580000; app.driver_operational_profiles,
--    20260729310000). Reasoning: (a) the `driver` master-type row was already seeded at
--    Phase 3 with owner_module_code='HRS' (20260727130000:60-64) -- Operations itself
--    anticipated eventual HR ownership of this shape before Phase 7 existed; (b)
--    app.master_records already carries a stable natural code (the employee number) and
--    canonical_status/deactivated_*/merged_into_id (soft-lifecycle and dedupe-lineage
--    primitives, "never hard-delete", section 24) for free -- reinventing these on a
--    bespoke app.employees-only table would duplicate, not reuse, existing platform
--    truth; (c) a future capability (Recruitment/ATS onboarding conversion, Prompt 277;
--    Payroll, Prompt 282) can resolve "is this master_record_id an employee" uniformly
--    the same way vendor/driver resolution already works, with zero new lookup shape.
--    The alternative (a bespoke app.employees table with its own code/uniqueness/lineage
--    machinery, no master_records row at all) was rejected as the literal "duplicate
--    root" ADR-0023's own Part A reasoning already forbids for a different, but
--    structurally identical, question.
--
--    CORRECTION (this checkpoint's own fix round, closing a self-review finding):
--    master_records.effective_from/effective_to were originally, and incorrectly,
--    claimed here to satisfy section 13's "effective dates" requirement. Live
--    verification found that claim false -- no function in this migration reads or
--    writes those two columns for any employee purpose; app.employees itself carries no
--    effective_from/effective_to (or any other time-boxed) column; no write RPC accepts
--    an effective-date parameter; every change (hire, transfer, status transition) takes
--    effect immediately at now(), with no ability to schedule, backdate, or query "as of"
--    a point in time. This checkpoint does NOT implement effective-dated employee
--    identity/lifecycle -- disclosed as ISS-2026-065 (open, HIGH) rather than left as a
--    silent false claim. hire_date/probation_end_date/employment_end_date remain real,
--    simple point-in-time date columns (sufficient for the lifecycle transitions this
--    checkpoint itself performs), just not a general effective-dating mechanism.
--
-- 2. **app.employees.user_id is a NULLABLE FK to app.users(id), unique when populated**
--    (ADR-0023 Part B, corrected). NOT a required FK -- Prompt 274 section 22's own
--    "create a profile before a user account, link an existing user later" alternative
--    flow would be structurally impossible under a NOT NULL column. app.link_employee_
--    user is the dedicated RPC that sets it later; a partial unique index
--    (employees_user_id_unique) additionally enforces the symmetric half of the ADR's
--    invariant -- one app.users row may back at most one employee, ever, at the
--    database level, not merely by convention.
--
-- 3. **Position/manager/company/branch/department: reserved as real, nullable,
--    validated FK-shaped columns now**, not deferred entirely to Prompt 275. Decision,
--    per Prompt 274 section 10's own "downstream impact" instruction to consider
--    HRT-275..297: company_org_unit_id/branch_org_unit_id/department_org_unit_id are
--    real FKs into the existing app.org_units tree (never a second hierarchy),
--    structurally validated for unit_type and tenant/ancestor consistency by
--    app.enforce_employee_org_unit_shape(). manager_employee_id is a real,
--    self-referential nullable FK to app.employees(master_record_id) (an employee's
--    manager is another employee, not merely a Platform user) -- cyclic reporting
--    lines are rejected by app.assert_no_employee_manager_cycle(), called from every
--    RPC that can set it. position_title is a plain, ungoverned free-text column --
--    Prompt 275's own chartered scope ("Organization and Position Linkage") is the
--    formal position/grade/eligibility table; this checkpoint does not anticipate its
--    shape, and adding a governed position_id FK now would be exactly the kind of
--    "full Step 13/14 implementation" Prompt 274 section 12 forbids for OTHER later
--    prompts' own chartered scope. When Prompt 275 ships, position_title remains as a
--    display fallback and a new, additive position_id column is expected to be added
--    then -- never retrofitted here speculatively.
--
-- 4. **Documents reuse app.files directly** (record_type='employee', record_id=
--    master_record_id) -- PLT-128, RPD-032 true quarantine, app.authorize_file_access()
--    -- never a second file table (Prompt 274's own binding convention).
--
-- 5. **Sensitive personal fields are minimized and column-classified**
--    (scripts/data-classification/registry.ts's new HRS_REGISTRY): national_id_number,
--    date_of_birth, gender, personal_address_*, personal_phone, personal_email,
--    emergency-contact phone/email. All masked by the SAME field-masking helper
--    PLT-114 already built for the HRS module (app.has_view_personal_data, gated on
--    the already-seeded HRS:View personal data permission) -- reused directly, never
--    re-implemented. No bank/tax/payroll-shaped column exists on this table at all --
--    'payroll' is a category this checkpoint's own instructions reserve for the future
--    Payroll capability (Prompt 282); Employee Master carries zero payroll fields.
--
-- 6. **Lifecycle state machine** (section 20-24's own business/exception rules):
--    draft -> submitted -> approved -> active; active <-> on_leave; active <->
--    suspended; {active, on_leave, suspended} -> terminated (terminal, requires a
--    reason and an effective employment_end_date, preserves all history); {draft,
--    submitted, approved, terminated} -> archived (terminal administrative closure --
--    reachable both from a profile that was never activated AND, separately, from a
--    terminated one, per section 22's "suspend OR archive with preserved history"
--    framing two sibling closure paths); {submitted, approved} -> draft (reject, with
--    revision_reason, never a separate terminal status, mirroring PRC-251's own
--    identical choice). Never a hard delete anywhere in this migration.
--    on_leave/suspended here are coarse HR-set states only -- a full leave-request
--    approval workflow (accrual, balances, multi-day requests) is explicitly Prompt
--    280's own chartered scope ("Leave, permit and business trip"), not anticipated
--    here, matching this migration's own "reserve the field, do not build the future
--    capability" discipline from decision 3.
--
-- 7. **RBAC seed.** Four new app.permissions rows for resource_module_code 'HRS':
--    ('Reject','HRS','workflow',false), ('Import','HRS','standard',false),
--    ('Download','HRS','standard',false), ('Override','HRS','workflow',false).
--    View/Create/Edit/Delete/Approve/Export/View personal data already exist
--    (20260716103445:61-63) and are reused unchanged. All eight action values are
--    already legal under the fixed, repository-wide permissions_action_check
--    CHECK constraint -- only new seed rows, the CHECK constraint itself is never
--    altered (mirrors ADR-0020's own identical discipline).
--
-- 8. **Authority routes exclusively through app.evaluate_permission(..., 'HRS', ...)**,
--    which itself already asserts caller-is-session-identity internally
--    (app.assert_actor_is_session_identity, wired at 20260730440000) for every one of
--    the write RPCs below that calls it. The two RPCs that do NOT call evaluate_
--    permission -- app.get_my_employee_profile and app.request_employee_change, both
--    genuinely self-service, identity-match-gated rather than permission-gated -- each
--    carry an EXPLICIT `perform app.assert_actor_is_session_identity(...)` call of
--    their own, matching 20260730510000's own established classification-pass
--    discipline for "authority check reached, but not through evaluate_permission."
--
-- 9. **Concurrency.** Every write RPC below: SELECT ... FOR UPDATE the target row
--    first (locks across the whole check-then-write window, per
--    20260730480000's own hardened, mandatory shape), folds a non-member caller into
--    the SAME not_found branch a genuinely missing row would produce (never discloses
--    a real tenant_id to a non-member -- the already-hardened "C-05" shape
--    20260730820000 converged Procurement onto, adopted here from day one rather than
--    retrofitted later), checks authority BEFORE checking record_version (never
--    discloses a real record_version to an unauthorized caller -- the "ISS-2026-055"
--    shape, likewise adopted from day one), and repeats `record_version =
--    p_expected_version` in the terminal UPDATE's own WHERE clause as a second,
--    belt-and-suspenders concurrency guard beyond the row lock.
--
-- 10. **Duplicate detection is entirely human-reviewed, never auto-merged** (section
--     24's own binding rule, identical to PRC-251's). app.search_employee_duplicate_
--     candidates (pg_trgm fuzzy name match, newly enabled by this migration, plus
--     exact national_id_number/work_email/personal_email match) is a manual search HR
--     staff runs; app.flag_employee_duplicate_candidate records a candidate pairing for
--     review; app.decide_employee_duplicate_candidate records linked/dismissed, never
--     invoking app.merge_master_records itself. app.submit_employee_for_approval
--     blocks submission while any 'pending' candidate remains against this profile.
--
-- 11. **Staged import** (PLT-131/132, the fifth-plus real domain-write adapter after
--     PRC-255's app.commit_vendor_rate_import_job, closing part of ISS-2026-013 for
--     this domain). Schema code 'employee_import' is registered directly (structural,
--     tenant-independent row, mirroring 'vendor_rate_import`'s own direct-INSERT
--     convention -- app.register_import_export_schema gates on Supreme Admin and a
--     migration-apply context has no live actor session). Each tenant still separately
--     configures and PUBLISHES its own import_export:employee_import column
--     definition via the existing Configuration Engine before creating a job against
--     this schema code. app.validate_employee_import_row calls app.validate_staging_
--     row UNCHANGED first (generic structural pass), then adds a domain-specific
--     formula/spreadsheet-injection rejection pass (identical prefix set to PRC-255's
--     own: =, +, -, @, tab, carriage return) plus org-unit-code resolution.
--     app.commit_employee_import_job is idempotent per staging row
--     (source_import_staging_row_id is unique-when-set on app.employees, defended by a
--     pre-check AND a nested unique_violation handler) and job-scoped-advisory-lock
--     serialized, exactly mirroring commit_vendor_rate_import_job's own proven shape.
--
-- 12. **Employee numbering.** app.master_records.code holds the employee number (the
--     stable natural identity, mirroring vendor_code). app.next_employee_number
--     generates a fixed 'EMP-YYYY-NNNNNN' default (mirrors app.next_vendor_code
--     exactly, same atomic INSERT...ON CONFLICT...RETURNING counter shape,
--     internal-only, never granted to `authenticated` directly -- ISS-2026-033's own
--     lesson). A caller MAY supply an explicit employee number instead (validated for
--     tenant-uniqueness by master_records' own existing unique index) -- this is this
--     checkpoint's own disclosed, bounded interpretation of section 13's "configurable
--     format": a fixed default generator plus an explicit-override escape hatch, NOT a
--     tenant-configurable template-string engine (no such engine exists anywhere in
--     this repository to reuse, and inventing one is disproportionate scope for this
--     checkpoint -- disclosed, not silently narrowed).
--
-- 13. **REST/GraphQL.** No live REST/GraphQL adapter layer exists for any business
--     domain yet (confirmed by direct repository inspection, matching every Phase 1-6
--     precedent's own identical disclosure) -- this capability follows the same
--     domain-service-layer + Next.js Server Actions-only shape.
--
-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries its own
-- explicit REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC statement before
-- its final grants, the standing per-migration convention since PLT-118.

create extension if not exists pg_trgm;

-- ===========================================================================
-- 1. RBAC seed additions (decision 7) -- new (action, module) rows only, the fixed
--    permissions_action_check CHECK constraint is never altered.
-- ===========================================================================

insert into app.permissions (action, resource_module_code, category, protected) values
  ('Reject', 'HRS', 'workflow', false),
  ('Import', 'HRS', 'standard', false),
  ('Download', 'HRS', 'standard', false),
  ('Override', 'HRS', 'workflow', false);

-- ===========================================================================
-- 2. master_type_code='employee' registration (decision 1).
-- ===========================================================================

insert into app.master_types (code, name, scope, owner_module_code, registered_by) values
  ('employee', 'Employee', 'tenant', 'HRS', 'hris-employee-master-foundation');

-- ===========================================================================
-- 3. Employee numbering (decision 12) -- internal-only, never granted to
--    `authenticated` (ISS-2026-033's own lesson).
-- ===========================================================================

create table app.employee_number_counters (
  tenant_id uuid primary key references app.tenants (id),
  last_seq integer not null default 0
);

comment on table app.employee_number_counters is
  'HRT-274: one atomic, tenant-scoped monotonic counter for app.next_employee_number(), mirroring app.vendor_code_counters (PRC-251). Never reused.';

create function app.next_employee_number(p_tenant_id uuid)
returns text
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_seq integer;
begin
  insert into app.employee_number_counters (tenant_id, last_seq)
  values (p_tenant_id, 1)
  on conflict (tenant_id) do update set last_seq = app.employee_number_counters.last_seq + 1
  returning last_seq into v_seq;

  return 'EMP-' || to_char(now(), 'YYYY') || '-' || lpad(v_seq::text, 6, '0');
end;
$$;

comment on function app.next_employee_number is
  'HRT-274: internal-only (no authenticated grant) -- called exclusively from inside this migration''s already-authorized SECURITY DEFINER functions. A fixed default format (decision 12); a caller may instead supply an explicit employee number, validated for tenant-uniqueness by master_records'' own unique index.';

-- ===========================================================================
-- 4. app.employees -- governed 1:1 extension of app.master_records
--    (master_type_code='employee'), per ADR-0023 Part B and decision 1.
-- ===========================================================================

create table app.employees (
  master_record_id uuid primary key references app.master_records (id),
  tenant_id uuid not null references app.tenants (id),
  user_id uuid references app.users (id),
  full_name text not null,
  employment_type text not null,
  lifecycle_status text not null default 'draft',
  intake_source text not null,
  work_email text,
  work_phone text,
  personal_email text,
  personal_phone text,
  national_id_number text,
  date_of_birth date,
  gender text,
  personal_address_street text,
  personal_address_city text,
  personal_address_province text,
  personal_address_postal_code text,
  personal_address_country text,
  hire_date date,
  probation_end_date date,
  employment_end_date date,
  company_org_unit_id uuid references app.org_units (id),
  branch_org_unit_id uuid references app.org_units (id),
  department_org_unit_id uuid references app.org_units (id),
  position_title text,
  manager_employee_id uuid references app.employees (master_record_id),
  revision_reason text,
  suspend_reason text,
  terminate_reason text,
  archive_reason text,
  leave_reason text,
  source_import_staging_row_id uuid references app.import_staging_rows (id),
  source_config_version_id uuid references app.config_versions (id),
  idempotency_key text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint employees_full_name_check check (length(trim(full_name)) > 0),
  constraint employees_employment_type_check check (employment_type in ('full_time', 'part_time', 'contract', 'intern', 'probation', 'daily_worker')),
  constraint employees_lifecycle_status_check check (
    lifecycle_status in ('draft', 'submitted', 'approved', 'active', 'on_leave', 'suspended', 'terminated', 'archived')
  ),
  constraint employees_intake_source_check check (intake_source in ('hr_created', 'bulk_import')),
  constraint employees_work_email_check check (work_email is null or work_email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'),
  constraint employees_personal_email_check check (personal_email is null or personal_email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'),
  constraint employees_manager_not_self_check check (manager_employee_id is distinct from master_record_id),
  constraint employees_suspend_reason_check check (lifecycle_status <> 'suspended' or (suspend_reason is not null and length(trim(suspend_reason)) > 0)),
  constraint employees_terminate_reason_check check (
    lifecycle_status <> 'terminated' or (terminate_reason is not null and length(trim(terminate_reason)) > 0 and employment_end_date is not null)
  )
);

comment on table app.employees is
  'HRT-274: governed 1:1 extension of app.master_records where master_type_code=''employee'' (ADR-0023 Part B, decision 1) -- the single canonical employee workforce identity. user_id is nullable and unique-when-set (ADR-0023 Part B, corrected) -- an employee links to at most one Platform authentication identity, optionally, and never duplicates it. tenant_id is duplicated from the referenced master_records row (enforced by app.enforce_employee_identity, never merely a convention), matching app.vendor_profiles'' own established choice.';

create index employees_tenant_status_idx on app.employees (tenant_id, lifecycle_status);
create index employees_tenant_company_idx on app.employees (tenant_id, company_org_unit_id) where company_org_unit_id is not null;
create index employees_tenant_branch_idx on app.employees (tenant_id, branch_org_unit_id) where branch_org_unit_id is not null;
create index employees_tenant_department_idx on app.employees (tenant_id, department_org_unit_id) where department_org_unit_id is not null;
create index employees_tenant_manager_idx on app.employees (tenant_id, manager_employee_id) where manager_employee_id is not null;
create index employees_national_id_idx on app.employees (tenant_id, national_id_number) where national_id_number is not null;
create index employees_personal_email_idx on app.employees (tenant_id, personal_email) where personal_email is not null;
create index employees_work_email_idx on app.employees (tenant_id, work_email) where work_email is not null;
create index employees_full_name_trgm_idx on app.employees using gin (full_name gin_trgm_ops);
create unique index employees_idempotency_key_unique on app.employees (tenant_id, idempotency_key) where idempotency_key is not null;
create unique index employees_user_id_unique on app.employees (user_id) where user_id is not null;
create unique index employees_source_staging_row_unique on app.employees (source_import_staging_row_id) where source_import_staging_row_id is not null;

create function app.enforce_employee_identity()
returns trigger
language plpgsql
as $$
declare
  v_master app.master_records;
begin
  select * into v_master from app.master_records where id = new.master_record_id;
  if not found then
    raise exception 'master_record_not_found: no master record %', new.master_record_id using errcode = 'foreign_key_violation';
  end if;
  if v_master.master_type_code <> 'employee' then
    raise exception 'invalid_employee_identity: master record % is master_type_code %, expected employee', new.master_record_id, v_master.master_type_code
      using errcode = 'check_violation';
  end if;
  if v_master.tenant_id is distinct from new.tenant_id then
    raise exception 'invalid_employee_identity: master record % belongs to tenant %, not %', new.master_record_id, v_master.tenant_id, new.tenant_id
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger employees_enforce_identity
  before insert or update of master_record_id, tenant_id on app.employees
  for each row
  execute function app.enforce_employee_identity();

-- Company/branch/department shape validation (decision 3): each column, when set,
-- must reference a same-tenant app.org_units row of the matching unit_type, and when
-- more than one is set, the more specific one's own materialized `path` must contain
-- the less specific one's id (a real ancestor relationship, never merely "same tenant").
create function app.enforce_employee_org_unit_shape()
returns trigger
language plpgsql
as $$
declare
  v_company app.org_units;
  v_branch app.org_units;
  v_department app.org_units;
begin
  if new.company_org_unit_id is not null then
    select * into v_company from app.org_units where id = new.company_org_unit_id;
    if not found or v_company.tenant_id <> new.tenant_id then
      raise exception 'org_unit_not_found: company_org_unit_id % is not a valid unit for tenant %', new.company_org_unit_id, new.tenant_id using errcode = 'no_data_found';
    end if;
    if v_company.unit_type <> 'company' then
      raise exception 'invalid_org_unit_type: company_org_unit_id % is a %, expected company', new.company_org_unit_id, v_company.unit_type using errcode = 'check_violation';
    end if;
    if v_company.status <> 'active' then
      raise exception 'org_unit_inactive: company_org_unit_id % is inactive and cannot be assigned to an employee', new.company_org_unit_id using errcode = 'check_violation';
    end if;
  end if;

  if new.branch_org_unit_id is not null then
    select * into v_branch from app.org_units where id = new.branch_org_unit_id;
    if not found or v_branch.tenant_id <> new.tenant_id then
      raise exception 'org_unit_not_found: branch_org_unit_id % is not a valid unit for tenant %', new.branch_org_unit_id, new.tenant_id using errcode = 'no_data_found';
    end if;
    if v_branch.unit_type <> 'branch' then
      raise exception 'invalid_org_unit_type: branch_org_unit_id % is a %, expected branch', new.branch_org_unit_id, v_branch.unit_type using errcode = 'check_violation';
    end if;
    if v_branch.status <> 'active' then
      raise exception 'org_unit_inactive: branch_org_unit_id % is inactive and cannot be assigned to an employee', new.branch_org_unit_id using errcode = 'check_violation';
    end if;
    if new.company_org_unit_id is not null and not (v_branch.path @> array[new.company_org_unit_id]) then
      raise exception 'org_unit_ancestor_mismatch: branch % is not under company %', new.branch_org_unit_id, new.company_org_unit_id using errcode = 'check_violation';
    end if;
  end if;

  if new.department_org_unit_id is not null then
    select * into v_department from app.org_units where id = new.department_org_unit_id;
    if not found or v_department.tenant_id <> new.tenant_id then
      raise exception 'org_unit_not_found: department_org_unit_id % is not a valid unit for tenant %', new.department_org_unit_id, new.tenant_id using errcode = 'no_data_found';
    end if;
    if v_department.unit_type <> 'department' then
      raise exception 'invalid_org_unit_type: department_org_unit_id % is a %, expected department', new.department_org_unit_id, v_department.unit_type using errcode = 'check_violation';
    end if;
    if v_department.status <> 'active' then
      raise exception 'org_unit_inactive: department_org_unit_id % is inactive and cannot be assigned to an employee', new.department_org_unit_id using errcode = 'check_violation';
    end if;
    if new.branch_org_unit_id is not null and not (v_department.path @> array[new.branch_org_unit_id] or v_department.id = new.branch_org_unit_id) then
      raise exception 'org_unit_ancestor_mismatch: department % is not under branch %', new.department_org_unit_id, new.branch_org_unit_id using errcode = 'check_violation';
    end if;
    if new.company_org_unit_id is not null and not (v_department.path @> array[new.company_org_unit_id]) then
      raise exception 'org_unit_ancestor_mismatch: department % is not under company %', new.department_org_unit_id, new.company_org_unit_id using errcode = 'check_violation';
    end if;
  end if;

  return new;
end;
$$;

create trigger employees_enforce_org_unit_shape
  before insert or update of company_org_unit_id, branch_org_unit_id, department_org_unit_id on app.employees
  for each row
  execute function app.enforce_employee_org_unit_shape();

comment on function app.enforce_employee_org_unit_shape is
  'HRT-274 (decision 3): company/branch/department, when jointly set, must form a genuine ancestor chain in app.org_units'' own materialized path -- never merely three independently-chosen same-tenant nodes. Each referenced unit must also be status=''active'' (section 23''s "block ... inactive organization" rule, fixed in this checkpoint''s own review round) -- fires only when one of these three columns is itself part of the INSERT/UPDATE, so an already-assigned employee is never retroactively invalidated by a LATER org-unit deactivation.';

-- Cyclic reporting-line guard (decision 3, section 25 "reject cyclic reporting
-- lines"). A bounded chain walk (200 hops -- generously above any plausible real org
-- depth) rather than a materialized path table, since Prompt 275 (not this
-- checkpoint) is chartered to build the formal position/reporting-line governance
-- layer this simpler guard is a deliberate placeholder for.
create function app.assert_no_employee_manager_cycle(p_employee_id uuid, p_candidate_manager_id uuid)
returns void
language plpgsql
stable
as $$
declare
  v_current uuid := p_candidate_manager_id;
  v_hops integer := 0;
begin
  if p_candidate_manager_id is null then
    return;
  end if;
  if p_candidate_manager_id = p_employee_id then
    raise exception 'cyclic_reporting_line: an employee may not be their own manager' using errcode = 'check_violation';
  end if;

  loop
    v_hops := v_hops + 1;
    if v_hops > 200 then
      raise exception 'cyclic_reporting_line: manager chain exceeds 200 hops for candidate %, refusing (probable cycle)', p_candidate_manager_id using errcode = 'check_violation';
    end if;

    select manager_employee_id into v_current from app.employees where master_record_id = v_current;
    if v_current is null then
      return;
    end if;
    if v_current = p_employee_id then
      raise exception 'cyclic_reporting_line: setting % as manager of % would create a cyclic reporting line', p_candidate_manager_id, p_employee_id using errcode = 'check_violation';
    end if;
  end loop;
end;
$$;

create function app.touch_employees_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger employees_touch_row
  before update on app.employees
  for each row
  execute function app.touch_employees_row();

-- Non-PII audit-log projection (this checkpoint's own review-round fix, closing a
-- CRITICAL finding): app.capture_audit_event's own app.redact_audit_payload
-- key-name-pattern redaction (secret|password|token|key|authorization|cookie|ssn|
-- npwp|bank|account_number|salary|payroll) does not match this table's own column
-- names, so passing to_jsonb() of a raw app.employees row wrote national_id_number,
-- personal_email, personal_phone, date_of_birth, gender, and personal_address_* into
-- app.audit_logs in plaintext -- readable by any tenant_admin via app.query_audit_logs
-- regardless of whether they hold HRS:View personal data. Every capture_audit_event
-- call against app.employees in this migration uses this explicit, non-PII projection
-- instead of to_jsonb(v_employee); nothing in scripts/data-classification/registry.ts's
-- own HRS_REGISTRY "never copied into app.audit_logs" claim is true unless this holds.
create function app.employee_audit_projection(p_employee app.employees)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'master_record_id', p_employee.master_record_id, 'full_name', p_employee.full_name,
    'employment_type', p_employee.employment_type, 'lifecycle_status', p_employee.lifecycle_status,
    'intake_source', p_employee.intake_source, 'work_email', p_employee.work_email, 'work_phone', p_employee.work_phone,
    'hire_date', p_employee.hire_date, 'probation_end_date', p_employee.probation_end_date,
    'employment_end_date', p_employee.employment_end_date, 'company_org_unit_id', p_employee.company_org_unit_id,
    'branch_org_unit_id', p_employee.branch_org_unit_id, 'department_org_unit_id', p_employee.department_org_unit_id,
    'position_title', p_employee.position_title, 'manager_employee_id', p_employee.manager_employee_id,
    'user_id', p_employee.user_id, 'record_version', p_employee.record_version
  );
$$;

comment on function app.employee_audit_projection is
  'HRT-274 review-round fix: the ONLY shape passed to app.capture_audit_event for an app.employees row -- deliberately omits national_id_number/personal_email/personal_phone/date_of_birth/gender/personal_address_* (classified pii, HRS_REGISTRY) and revision/suspend/terminate/archive/leave reason free-text.';

-- ===========================================================================
-- 5. Child tables.
-- ===========================================================================

create table app.employee_emergency_contacts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  master_record_id uuid not null references app.employees (master_record_id),
  name text not null,
  relationship text,
  phone text,
  email text,
  is_primary boolean not null default false,
  status text not null default 'active',
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint employee_emergency_contacts_name_check check (length(trim(name)) > 0),
  constraint employee_emergency_contacts_status_check check (status in ('active', 'removed')),
  constraint employee_emergency_contacts_email_check check (email is null or email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$')
);

comment on table app.employee_emergency_contacts is 'HRT-274: one row per emergency contact for an employee. phone/email are sensitive personal data of a named third party -- masked identically to the employee''s own fields (HRS:View personal data). Soft-deleted (status=''removed''), never physically deleted.';
create index employee_emergency_contacts_master_record_idx on app.employee_emergency_contacts (master_record_id) where status = 'active';
create unique index employee_emergency_contacts_one_primary_idx on app.employee_emergency_contacts (master_record_id) where status = 'active' and is_primary;

create function app.touch_employee_child_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger employee_emergency_contacts_touch_row before update on app.employee_emergency_contacts for each row execute function app.touch_employee_child_row();

-- Non-PII audit-log projection for app.employee_emergency_contacts -- phone/email are a
-- named third party''s personal data (HRS_REGISTRY hrs:employee_emergency_contacts.phone_email),
-- masked identically to the employee''s own fields; never copied into app.audit_logs.
create function app.employee_emergency_contact_audit_projection(p_contact app.employee_emergency_contacts)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'id', p_contact.id, 'master_record_id', p_contact.master_record_id, 'name', p_contact.name,
    'relationship', p_contact.relationship, 'is_primary', p_contact.is_primary, 'status', p_contact.status,
    'record_version', p_contact.record_version
  );
$$;

comment on function app.employee_emergency_contact_audit_projection is
  'HRT-274 review-round fix: the ONLY shape passed to app.capture_audit_event for an app.employee_emergency_contacts row -- deliberately omits phone/email (classified pii, a named third party''s personal data).';

create table app.employee_lifecycle_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  master_record_id uuid not null references app.employees (master_record_id),
  from_status text not null,
  to_status text not null,
  reason text,
  metadata jsonb not null default '{}'::jsonb,
  actor_auth_user_id uuid,
  actor_label text,
  occurred_at timestamptz not null default now()
);

comment on table app.employee_lifecycle_events is 'HRT-274: append-only lifecycle transition history (including transfers, whose before/after company/branch/department/position/manager values live in metadata), one row per real transition, written by every lifecycle/transfer RPC in the same transaction as the change itself. Distinct from app.audit_logs -- this is the domain-shaped timeline the employee detail UI''s History tab reads directly.';
create index employee_lifecycle_events_master_record_idx on app.employee_lifecycle_events (master_record_id, occurred_at);

create table app.employee_duplicate_candidates (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  source_master_record_id uuid not null references app.employees (master_record_id),
  candidate_master_record_id uuid not null references app.employees (master_record_id),
  similarity_basis text not null,
  similarity_score numeric,
  decision text not null default 'pending',
  decided_by text,
  decided_at timestamptz,
  decided_reason text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  constraint employee_duplicate_candidates_not_self_check check (source_master_record_id <> candidate_master_record_id),
  constraint employee_duplicate_candidates_similarity_basis_check check (length(trim(similarity_basis)) > 0),
  constraint employee_duplicate_candidates_decision_check check (decision in ('pending', 'linked', 'dismissed')),
  constraint employee_duplicate_candidates_decided_shape_check check (
    (decision = 'pending' and decided_at is null and decided_by is null and decided_reason is null) or
    (decision <> 'pending' and decided_at is not null and decided_by is not null and decided_reason is not null and length(trim(decided_reason)) > 0)
  )
);

comment on table app.employee_duplicate_candidates is 'HRT-274 (decision 10): source draft -> candidate existing employee pairing, flagged for human review. decision=''linked'' documents a reviewer''s finding, never triggers an automatic merge -- mirrors app.vendor_duplicate_candidates (PRC-251) exactly.';
create index employee_duplicate_candidates_source_idx on app.employee_duplicate_candidates (source_master_record_id);
create index employee_duplicate_candidates_source_pending_idx on app.employee_duplicate_candidates (source_master_record_id) where decision = 'pending';

create table app.employee_change_requests (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  master_record_id uuid not null references app.employees (master_record_id),
  requested_by_user_id uuid not null references app.users (id),
  field_key text not null,
  current_value_snapshot text,
  requested_value text not null,
  reason text,
  status text not null default 'pending',
  decided_by text,
  decided_at timestamptz,
  decided_reason text,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint employee_change_requests_field_key_check check (
    field_key in ('personal_email', 'personal_phone', 'personal_address_street', 'personal_address_city', 'personal_address_province', 'personal_address_postal_code', 'personal_address_country')
  ),
  constraint employee_change_requests_status_check check (status in ('pending', 'approved', 'rejected')),
  constraint employee_change_requests_decided_shape_check check (
    (status = 'pending' and decided_at is null and decided_by is null) or
    (status <> 'pending' and decided_at is not null and decided_by is not null)
  )
);

comment on table app.employee_change_requests is 'HRT-274: an employee''s own governed self-service correction request against a fixed allow-list of own-editable fields (section 22''s "request personal-data correction"), gated by identity match (requested_by_user_id must resolve to THIS employee''s own user_id) rather than HRS:Edit -- an ordinary employee is not expected to hold any HRS permission. app.decide_employee_change_request (HR-gated) applies an approved request to the real app.employees column via a fixed, non-dynamic column allow-list.';
create index employee_change_requests_master_record_idx on app.employee_change_requests (master_record_id, created_at desc);
create index employee_change_requests_pending_idx on app.employee_change_requests (tenant_id) where status = 'pending';

create function app.touch_employee_change_requests_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger employee_change_requests_touch_row before update on app.employee_change_requests for each row execute function app.touch_employee_change_requests_row();

-- ===========================================================================
-- 6. Lifecycle RPCs (decisions 6, 9).
-- ===========================================================================

-- Idempotency-key replay guard (this checkpoint's own review-round fix): an
-- idempotency-key match is only a safe replay when the FULL caller-supplied input
-- tuple agrees with the row already on file -- comparing full_name alone (the
-- original, defective shape) let a replayed key with the SAME name but DIFFERENT
-- employment_type/contact/national-id/org-unit/manager/user/number/intake_source
-- silently return the first call's stale data with no error. Shared by both the
-- pre-check and the unique_violation retry handler in app.create_employee_draft so
-- the comparison is defined exactly once.
create function app.assert_employee_draft_idempotent_replay(
  p_existing app.employees,
  p_existing_employee_number text,
  p_full_name text,
  p_employment_type text,
  p_work_email text,
  p_personal_email text,
  p_personal_phone text,
  p_national_id_number text,
  p_date_of_birth date,
  p_gender text,
  p_hire_date date,
  p_company_org_unit_id uuid,
  p_branch_org_unit_id uuid,
  p_department_org_unit_id uuid,
  p_position_title text,
  p_manager_employee_id uuid,
  p_user_id uuid,
  p_intake_source text,
  p_employee_number text,
  p_idempotency_key text
)
returns void
language plpgsql
as $$
declare
  v_requested_number text := nullif(trim(coalesce(p_employee_number, '')), '');
begin
  if p_existing.full_name is distinct from p_full_name
     or p_existing.employment_type is distinct from p_employment_type
     or p_existing.work_email is distinct from p_work_email
     or p_existing.personal_email is distinct from p_personal_email
     or p_existing.personal_phone is distinct from p_personal_phone
     or p_existing.national_id_number is distinct from p_national_id_number
     or p_existing.date_of_birth is distinct from p_date_of_birth
     or p_existing.gender is distinct from p_gender
     or p_existing.hire_date is distinct from p_hire_date
     or p_existing.company_org_unit_id is distinct from p_company_org_unit_id
     or p_existing.branch_org_unit_id is distinct from p_branch_org_unit_id
     or p_existing.department_org_unit_id is distinct from p_department_org_unit_id
     or p_existing.position_title is distinct from p_position_title
     or p_existing.manager_employee_id is distinct from p_manager_employee_id
     or p_existing.user_id is distinct from p_user_id
     or p_existing.intake_source is distinct from p_intake_source
     or (v_requested_number is not null and p_existing_employee_number is distinct from v_requested_number)
  then
    raise exception 'idempotency_key_conflict: idempotency key % was already used with different employee data (existing full_name %)', p_idempotency_key, p_existing.full_name
      using errcode = 'unique_violation';
  end if;
end;
$$;

comment on function app.assert_employee_draft_idempotent_replay is
  'HRT-274 review-round fix: compares the FULL create_employee_draft input tuple (not merely full_name) against an existing idempotency-key match before treating it as a safe replay -- a same-key-different-payload call now raises idempotency_key_conflict instead of silently discarding the new data.';

create function app.create_employee_draft(
  p_tenant_id uuid,
  p_full_name text,
  p_employment_type text,
  p_work_email text,
  p_personal_email text,
  p_personal_phone text,
  p_national_id_number text,
  p_date_of_birth date,
  p_gender text,
  p_hire_date date,
  p_company_org_unit_id uuid,
  p_branch_org_unit_id uuid,
  p_department_org_unit_id uuid,
  p_position_title text,
  p_manager_employee_id uuid,
  p_user_id uuid,
  p_employee_number text,
  p_intake_source text,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.employees
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_existing app.employees;
  v_existing_number text;
  v_number text;
  v_master app.master_records;
  v_employee app.employees;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_full_name is null or length(trim(p_full_name)) = 0 then
    raise exception 'invalid_full_name: full_name must not be empty' using errcode = 'check_violation';
  end if;
  if p_employment_type not in ('full_time', 'part_time', 'contract', 'intern', 'probation', 'daily_worker') then
    raise exception 'invalid_employment_type: %', p_employment_type using errcode = 'check_violation';
  end if;
  if p_intake_source not in ('hr_created', 'bulk_import') then
    raise exception 'invalid_intake_source: % is not valid for direct draft creation', p_intake_source using errcode = 'check_violation';
  end if;
  -- No cycle check is needed here: a brand-new draft has no id yet, so no existing
  -- row's manager chain can possibly already reach it -- a cycle is structurally
  -- impossible at creation time. app.assert_no_employee_manager_cycle is called from
  -- app.update_employee_draft and app.transfer_employee instead, the only two paths
  -- that can point manager_employee_id at an ALREADY-EXISTING row's chain.

  if p_manager_employee_id is not null and not exists (select 1 from app.employees where master_record_id = p_manager_employee_id and tenant_id = p_tenant_id) then
    raise exception 'employee_not_found: manager % is not a valid employee for tenant %', p_manager_employee_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  if p_user_id is not null and not exists (select 1 from app.users where id = p_user_id and tenant_id = p_tenant_id) then
    raise exception 'user_not_found: % is not a valid user for tenant %', p_user_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  if p_idempotency_key is not null then
    select e.* into v_existing
    from app.employees e
    where e.tenant_id = p_tenant_id and e.idempotency_key = p_idempotency_key;
    if found then
      select code into v_existing_number from app.master_records where id = v_existing.master_record_id;
      perform app.assert_employee_draft_idempotent_replay(
        v_existing, v_existing_number, p_full_name, p_employment_type, p_work_email, p_personal_email,
        p_personal_phone, p_national_id_number, p_date_of_birth, p_gender, p_hire_date,
        p_company_org_unit_id, p_branch_org_unit_id, p_department_org_unit_id, p_position_title,
        p_manager_employee_id, p_user_id, p_intake_source, p_employee_number, p_idempotency_key
      );
      return v_existing;
    end if;
  end if;

  v_number := coalesce(nullif(trim(p_employee_number), ''), app.next_employee_number(p_tenant_id));

  begin
    insert into app.master_records (master_type_code, tenant_id, code, name, aliases, attributes, created_by)
    values ('employee', p_tenant_id, v_number, p_full_name, '[]'::jsonb, '{}'::jsonb, p_actor_label)
    returning * into v_master;
  exception
    when unique_violation then
      raise exception 'employee_number_conflict: employee number % is already in use for this tenant', v_number
        using errcode = 'unique_violation';
  end;

  begin
    insert into app.employees (
      master_record_id, tenant_id, user_id, full_name, employment_type, intake_source,
      work_email, personal_email, personal_phone, national_id_number, date_of_birth, gender,
      hire_date, company_org_unit_id, branch_org_unit_id, department_org_unit_id,
      position_title, manager_employee_id, idempotency_key, created_by
    )
    values (
      v_master.id, p_tenant_id, p_user_id, p_full_name, p_employment_type, p_intake_source,
      p_work_email, p_personal_email, p_personal_phone, p_national_id_number, p_date_of_birth, p_gender,
      p_hire_date, p_company_org_unit_id, p_branch_org_unit_id, p_department_org_unit_id,
      p_position_title, p_manager_employee_id, p_idempotency_key, p_actor_label
    )
    returning * into v_employee;
  exception
    when unique_violation then
      select e.* into v_existing
      from app.employees e
      where e.tenant_id = p_tenant_id and e.idempotency_key = p_idempotency_key;
      if not found then
        raise;
      end if;
      select code into v_existing_number from app.master_records where id = v_existing.master_record_id;
      perform app.assert_employee_draft_idempotent_replay(
        v_existing, v_existing_number, p_full_name, p_employment_type, p_work_email, p_personal_email,
        p_personal_phone, p_national_id_number, p_date_of_birth, p_gender, p_hire_date,
        p_company_org_unit_id, p_branch_org_unit_id, p_department_org_unit_id, p_position_title,
        p_manager_employee_id, p_user_id, p_intake_source, p_employee_number, p_idempotency_key
      );
      return v_existing;
  end;

  insert into app.employee_lifecycle_events (tenant_id, master_record_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (p_tenant_id, v_employee.master_record_id, 'none', 'draft', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_employee_draft',
    'app.employees', v_employee.master_record_id, 'success', null, null, app.employee_audit_projection(v_employee)
  );

  return v_employee;
end;
$$;

comment on function app.create_employee_draft is 'HRT-274: creates the canonical master_records row (master_type_code=''employee'') and its employees extension together, in one transaction. Gates exclusively on HRS:Create.';

create function app.update_employee_draft(
  p_master_record_id uuid,
  p_expected_version integer,
  p_full_name text,
  p_employment_type text,
  p_work_email text,
  p_personal_email text,
  p_personal_phone text,
  p_national_id_number text,
  p_date_of_birth date,
  p_gender text,
  p_hire_date date,
  p_probation_end_date date,
  p_company_org_unit_id uuid,
  p_branch_org_unit_id uuid,
  p_department_org_unit_id uuid,
  p_position_title text,
  p_manager_employee_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.employees
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
begin
  select * into v_employee from app.employees where master_record_id = p_master_record_id for update;
  if not found or not app.has_active_tenant_membership(v_employee.tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_employee.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_employee.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_employee.record_version <> p_expected_version then
    raise exception 'stale_version: employee % expected version % but found %', p_master_record_id, p_expected_version, v_employee.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_employee.lifecycle_status <> 'draft' then
    raise exception 'employee_not_draft: employee % is % -- only a draft profile may be edited this way', p_master_record_id, v_employee.lifecycle_status
      using errcode = 'check_violation';
  end if;

  if p_full_name is null or length(trim(p_full_name)) = 0 then
    raise exception 'invalid_full_name: full_name must not be empty' using errcode = 'check_violation';
  end if;
  if p_employment_type not in ('full_time', 'part_time', 'contract', 'intern', 'probation', 'daily_worker') then
    raise exception 'invalid_employment_type: %', p_employment_type using errcode = 'check_violation';
  end if;

  if p_manager_employee_id is not null then
    if not exists (select 1 from app.employees where master_record_id = p_manager_employee_id and tenant_id = v_employee.tenant_id) then
      raise exception 'employee_not_found: manager % is not a valid employee for tenant %', p_manager_employee_id, v_employee.tenant_id using errcode = 'no_data_found';
    end if;
    perform app.assert_no_employee_manager_cycle(p_master_record_id, p_manager_employee_id);
  end if;

  update app.employees
  set full_name = p_full_name, employment_type = p_employment_type, work_email = p_work_email,
      personal_email = p_personal_email, personal_phone = p_personal_phone, national_id_number = p_national_id_number,
      date_of_birth = p_date_of_birth, gender = p_gender, hire_date = p_hire_date, probation_end_date = p_probation_end_date,
      company_org_unit_id = p_company_org_unit_id, branch_org_unit_id = p_branch_org_unit_id, department_org_unit_id = p_department_org_unit_id,
      position_title = p_position_title, manager_employee_id = p_manager_employee_id
  where master_record_id = p_master_record_id and record_version = p_expected_version
  returning * into v_employee;
  if not found then
    raise exception 'stale_version: employee % target row was concurrently modified (expected version %)', p_master_record_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  update app.master_records set name = p_full_name where id = p_master_record_id;

  perform app.capture_audit_event(
    v_employee.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_employee_draft',
    'app.employees', p_master_record_id, 'success', null, null, app.employee_audit_projection(v_employee)
  );

  return v_employee;
end;
$$;

create function app.submit_employee_for_approval(
  p_master_record_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.employees
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
  v_pending_dupes integer;
  v_contact_count integer;
begin
  select * into v_employee from app.employees where master_record_id = p_master_record_id for update;
  if not found or not app.has_active_tenant_membership(v_employee.tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_employee.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_employee.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_employee.record_version <> p_expected_version then
    raise exception 'stale_version: employee % expected version % but found %', p_master_record_id, p_expected_version, v_employee.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_employee.lifecycle_status <> 'draft' then
    raise exception 'invalid_transition: employee % is % and cannot be submitted for approval', p_master_record_id, v_employee.lifecycle_status
      using errcode = 'check_violation';
  end if;

  if v_employee.hire_date is null then
    raise exception 'missing_required_field: employee % has no hire_date', p_master_record_id using errcode = 'check_violation';
  end if;
  if v_employee.company_org_unit_id is null and v_employee.branch_org_unit_id is null and v_employee.department_org_unit_id is null then
    raise exception 'missing_required_field: employee % has no company/branch/department assignment', p_master_record_id using errcode = 'check_violation';
  end if;

  select count(*) into v_contact_count from app.employee_emergency_contacts where master_record_id = p_master_record_id and status = 'active';
  if v_contact_count = 0 then
    raise exception 'missing_required_contact: employee % has no active emergency contact', p_master_record_id using errcode = 'check_violation';
  end if;

  select count(*) into v_pending_dupes from app.employee_duplicate_candidates where source_master_record_id = p_master_record_id and decision = 'pending';
  if v_pending_dupes > 0 then
    raise exception 'unresolved_duplicate_candidates: employee % has % unresolved duplicate candidate(s)', p_master_record_id, v_pending_dupes
      using errcode = 'check_violation';
  end if;

  update app.employees
  set lifecycle_status = 'submitted'
  where master_record_id = p_master_record_id and record_version = p_expected_version
  returning * into v_employee;
  if not found then
    raise exception 'stale_version: employee % target row was concurrently modified (expected version %)', p_master_record_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.employee_lifecycle_events (tenant_id, master_record_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (v_employee.tenant_id, p_master_record_id, 'draft', 'submitted', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_employee.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_employee_for_approval',
    'app.employees', p_master_record_id, 'success', null, null, jsonb_build_object('lifecycle_status', v_employee.lifecycle_status)
  );

  return v_employee;
end;
$$;

create function app.decide_employee_approval(
  p_master_record_id uuid,
  p_expected_version integer,
  p_decision text,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.employees
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
  v_new_status text;
  v_action text;
begin
  if p_decision not in ('approve', 'reject') then
    raise exception 'invalid_decision: % is not approve or reject', p_decision using errcode = 'check_violation';
  end if;
  if p_decision = 'reject' and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'reason_required: a non-empty reason is required to reject an employee profile' using errcode = 'check_violation';
  end if;

  select * into v_employee from app.employees where master_record_id = p_master_record_id for update;
  if not found or not app.has_active_tenant_membership(v_employee.tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_action := case p_decision when 'approve' then 'Approve' else 'Reject' end;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_employee.tenant_id, 'HRS', v_action);
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:% (%) for tenant %', p_actor_auth_user_id, v_action, v_decision.reason, v_employee.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_employee.record_version <> p_expected_version then
    raise exception 'stale_version: employee % expected version % but found %', p_master_record_id, p_expected_version, v_employee.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_employee.lifecycle_status <> 'submitted' then
    raise exception 'invalid_transition: employee % is % and cannot be decided', p_master_record_id, v_employee.lifecycle_status
      using errcode = 'check_violation';
  end if;

  v_new_status := case p_decision when 'approve' then 'approved' else 'draft' end;

  update app.employees
  set lifecycle_status = v_new_status,
      revision_reason = case when p_decision = 'reject' then p_reason else revision_reason end
  where master_record_id = p_master_record_id and record_version = p_expected_version
  returning * into v_employee;
  if not found then
    raise exception 'stale_version: employee % target row was concurrently modified (expected version %)', p_master_record_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.employee_lifecycle_events (tenant_id, master_record_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (v_employee.tenant_id, p_master_record_id, 'submitted', v_new_status, p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_employee.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_employee_approval',
    'app.employees', p_master_record_id, 'success', p_reason, null, jsonb_build_object('decision', p_decision, 'lifecycle_status', v_new_status)
  );

  return v_employee;
end;
$$;

create function app.activate_employee(
  p_master_record_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.employees
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
begin
  select * into v_employee from app.employees where master_record_id = p_master_record_id for update;
  if not found or not app.has_active_tenant_membership(v_employee.tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_employee.tenant_id, 'HRS', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_employee.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_employee.record_version <> p_expected_version then
    raise exception 'stale_version: employee % expected version % but found %', p_master_record_id, p_expected_version, v_employee.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_employee.lifecycle_status <> 'approved' then
    raise exception 'invalid_transition: employee % is % and cannot be activated', p_master_record_id, v_employee.lifecycle_status
      using errcode = 'check_violation';
  end if;

  update app.employees
  set lifecycle_status = 'active'
  where master_record_id = p_master_record_id and record_version = p_expected_version
  returning * into v_employee;
  if not found then
    raise exception 'stale_version: employee % target row was concurrently modified (expected version %)', p_master_record_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.employee_lifecycle_events (tenant_id, master_record_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (v_employee.tenant_id, p_master_record_id, 'approved', 'active', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_employee.tenant_id, p_actor_auth_user_id, p_actor_label, 'activate_employee',
    'app.employees', p_master_record_id, 'success', null, null, '{}'::jsonb
  );

  return v_employee;
end;
$$;

create function app.link_employee_user(
  p_master_record_id uuid,
  p_expected_version integer,
  p_user_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.employees
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
begin
  select * into v_employee from app.employees where master_record_id = p_master_record_id for update;
  if not found or not app.has_active_tenant_membership(v_employee.tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_employee.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_employee.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_employee.record_version <> p_expected_version then
    raise exception 'stale_version: employee % expected version % but found %', p_master_record_id, p_expected_version, v_employee.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_employee.lifecycle_status in ('terminated', 'archived') then
    raise exception 'invalid_transition: employee % is % and may not be linked to a user', p_master_record_id, v_employee.lifecycle_status
      using errcode = 'check_violation';
  end if;

  if not exists (select 1 from app.users where id = p_user_id and tenant_id = v_employee.tenant_id) then
    raise exception 'user_not_found: % is not a valid user for tenant %', p_user_id, v_employee.tenant_id using errcode = 'no_data_found';
  end if;

  begin
    update app.employees
    set user_id = p_user_id
    where master_record_id = p_master_record_id and record_version = p_expected_version
    returning * into v_employee;
  exception
    when unique_violation then
      raise exception 'user_already_linked: user % is already linked to a different employee' , p_user_id using errcode = 'unique_violation';
  end;
  if not found then
    raise exception 'stale_version: employee % target row was concurrently modified (expected version %)', p_master_record_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_employee.tenant_id, p_actor_auth_user_id, p_actor_label, 'link_employee_user',
    'app.employees', p_master_record_id, 'success', null, null, jsonb_build_object('user_id', p_user_id)
  );

  return v_employee;
end;
$$;

comment on function app.link_employee_user is 'HRT-274 (ADR-0023 Part B, alternative flow section 22): links an existing Platform user to an employee profile created ahead of the user account. app.employees.user_id''s own partial unique index enforces the symmetric half of the invariant -- one user backs at most one employee.';

create function app.start_employee_leave(
  p_master_record_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.employees
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
begin
  select * into v_employee from app.employees where master_record_id = p_master_record_id for update;
  if not found or not app.has_active_tenant_membership(v_employee.tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_employee.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_employee.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_employee.record_version <> p_expected_version then
    raise exception 'stale_version: employee % expected version % but found %', p_master_record_id, p_expected_version, v_employee.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_employee.lifecycle_status <> 'active' then
    raise exception 'invalid_transition: employee % is % and cannot start leave', p_master_record_id, v_employee.lifecycle_status
      using errcode = 'check_violation';
  end if;

  update app.employees
  set lifecycle_status = 'on_leave', leave_reason = p_reason
  where master_record_id = p_master_record_id and record_version = p_expected_version
  returning * into v_employee;
  if not found then
    raise exception 'stale_version: employee % target row was concurrently modified (expected version %)', p_master_record_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.employee_lifecycle_events (tenant_id, master_record_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (v_employee.tenant_id, p_master_record_id, 'active', 'on_leave', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_employee.tenant_id, p_actor_auth_user_id, p_actor_label, 'start_employee_leave',
    'app.employees', p_master_record_id, 'success', p_reason, null, '{}'::jsonb
  );

  return v_employee;
end;
$$;

comment on function app.start_employee_leave is 'HRT-274 (decision 6): a coarse, HR-set lifecycle state only -- accrual/balance/multi-day-request leave workflow is Prompt 280''s own chartered scope, not built here.';

create function app.end_employee_leave(
  p_master_record_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.employees
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
begin
  select * into v_employee from app.employees where master_record_id = p_master_record_id for update;
  if not found or not app.has_active_tenant_membership(v_employee.tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_employee.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_employee.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_employee.record_version <> p_expected_version then
    raise exception 'stale_version: employee % expected version % but found %', p_master_record_id, p_expected_version, v_employee.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_employee.lifecycle_status <> 'on_leave' then
    raise exception 'invalid_transition: employee % is % and cannot end leave', p_master_record_id, v_employee.lifecycle_status
      using errcode = 'check_violation';
  end if;

  update app.employees
  set lifecycle_status = 'active', leave_reason = null
  where master_record_id = p_master_record_id and record_version = p_expected_version
  returning * into v_employee;
  if not found then
    raise exception 'stale_version: employee % target row was concurrently modified (expected version %)', p_master_record_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.employee_lifecycle_events (tenant_id, master_record_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (v_employee.tenant_id, p_master_record_id, 'on_leave', 'active', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_employee.tenant_id, p_actor_auth_user_id, p_actor_label, 'end_employee_leave',
    'app.employees', p_master_record_id, 'success', null, null, '{}'::jsonb
  );

  return v_employee;
end;
$$;

create function app.suspend_employee(
  p_master_record_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.employees
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
  v_from_status text;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to suspend an employee' using errcode = 'check_violation';
  end if;

  select * into v_employee from app.employees where master_record_id = p_master_record_id for update;
  if not found or not app.has_active_tenant_membership(v_employee.tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_employee.tenant_id, 'HRS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_employee.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_employee.record_version <> p_expected_version then
    raise exception 'stale_version: employee % expected version % but found %', p_master_record_id, p_expected_version, v_employee.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_employee.lifecycle_status not in ('active', 'on_leave') then
    raise exception 'invalid_transition: employee % is % and cannot be suspended', p_master_record_id, v_employee.lifecycle_status
      using errcode = 'check_violation';
  end if;
  v_from_status := v_employee.lifecycle_status;

  update app.employees
  set lifecycle_status = 'suspended', suspend_reason = p_reason
  where master_record_id = p_master_record_id and record_version = p_expected_version
  returning * into v_employee;
  if not found then
    raise exception 'stale_version: employee % target row was concurrently modified (expected version %)', p_master_record_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.employee_lifecycle_events (tenant_id, master_record_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (v_employee.tenant_id, p_master_record_id, v_from_status, 'suspended', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_employee.tenant_id, p_actor_auth_user_id, p_actor_label, 'suspend_employee',
    'app.employees', p_master_record_id, 'success', p_reason, null, '{}'::jsonb
  );

  return v_employee;
end;
$$;

create function app.reactivate_employee(
  p_master_record_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.employees
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
  v_restore_status text;
begin
  select * into v_employee from app.employees where master_record_id = p_master_record_id for update;
  if not found or not app.has_active_tenant_membership(v_employee.tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_employee.tenant_id, 'HRS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_employee.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_employee.record_version <> p_expected_version then
    raise exception 'stale_version: employee % expected version % but found %', p_master_record_id, p_expected_version, v_employee.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_employee.lifecycle_status <> 'suspended' then
    raise exception 'invalid_transition: employee % is % and cannot be reactivated', p_master_record_id, v_employee.lifecycle_status
      using errcode = 'check_violation';
  end if;

  -- Restore the status the employee was suspended FROM (this checkpoint's own
  -- review-round fix): app.suspend_employee allows suspension from EITHER 'active' OR
  -- 'on_leave' and records the true from_status in app.employee_lifecycle_events, but
  -- reactivation previously always hardcoded 'active' -- silently losing an on_leave
  -- employee's real state. Falls back to 'active' only if no such event is somehow on
  -- file (defensive; suspend_employee always logs one).
  select from_status into v_restore_status
  from app.employee_lifecycle_events
  where master_record_id = p_master_record_id and to_status = 'suspended'
  order by occurred_at desc
  limit 1;
  if v_restore_status is null or v_restore_status not in ('active', 'on_leave') then
    v_restore_status := 'active';
  end if;

  update app.employees
  set lifecycle_status = v_restore_status, suspend_reason = null
  where master_record_id = p_master_record_id and record_version = p_expected_version
  returning * into v_employee;
  if not found then
    raise exception 'stale_version: employee % target row was concurrently modified (expected version %)', p_master_record_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.employee_lifecycle_events (tenant_id, master_record_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (v_employee.tenant_id, p_master_record_id, 'suspended', v_restore_status, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_employee.tenant_id, p_actor_auth_user_id, p_actor_label, 'reactivate_employee',
    'app.employees', p_master_record_id, 'success', null, null, '{}'::jsonb
  );

  return v_employee;
end;
$$;

create function app.terminate_employee(
  p_master_record_id uuid,
  p_expected_version integer,
  p_reason text,
  p_employment_end_date date,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.employees
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
  v_from_status text;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to terminate an employee' using errcode = 'check_violation';
  end if;
  if p_employment_end_date is null then
    raise exception 'employment_end_date_required: an effective employment_end_date is required to terminate an employee' using errcode = 'check_violation';
  end if;

  select * into v_employee from app.employees where master_record_id = p_master_record_id for update;
  if not found or not app.has_active_tenant_membership(v_employee.tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_employee.tenant_id, 'HRS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_employee.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_employee.record_version <> p_expected_version then
    raise exception 'stale_version: employee % expected version % but found %', p_master_record_id, p_expected_version, v_employee.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_employee.lifecycle_status not in ('active', 'on_leave', 'suspended') then
    raise exception 'invalid_transition: employee % is % and cannot be terminated', p_master_record_id, v_employee.lifecycle_status
      using errcode = 'check_violation';
  end if;
  v_from_status := v_employee.lifecycle_status;

  update app.employees
  set lifecycle_status = 'terminated', terminate_reason = p_reason, employment_end_date = p_employment_end_date,
      suspend_reason = null, leave_reason = null
  where master_record_id = p_master_record_id and record_version = p_expected_version
  returning * into v_employee;
  if not found then
    raise exception 'stale_version: employee % target row was concurrently modified (expected version %)', p_master_record_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.employee_lifecycle_events (tenant_id, master_record_id, from_status, to_status, reason, metadata, actor_auth_user_id, actor_label)
  values (v_employee.tenant_id, p_master_record_id, v_from_status, 'terminated', p_reason, jsonb_build_object('employment_end_date', p_employment_end_date), p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_employee.tenant_id, p_actor_auth_user_id, p_actor_label, 'terminate_employee',
    'app.employees', p_master_record_id, 'success', p_reason, null, jsonb_build_object('employment_end_date', p_employment_end_date)
  );

  return v_employee;
end;
$$;

comment on function app.terminate_employee is 'HRT-274 (section 24: "never erases required payroll, attendance, Operations or audit history"): terminal, but the row and every child/history row is preserved unchanged -- no delete anywhere. user_id remains linked (Platform authentication revocation, if any, is a separate PLT-107/108 action, not performed here).';

create function app.archive_employee_profile(
  p_master_record_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.employees
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
  v_from_status text;
begin
  select * into v_employee from app.employees where master_record_id = p_master_record_id for update;
  if not found or not app.has_active_tenant_membership(v_employee.tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_employee.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_employee.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_employee.record_version <> p_expected_version then
    raise exception 'stale_version: employee % expected version % but found %', p_master_record_id, p_expected_version, v_employee.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_employee.lifecycle_status not in ('draft', 'submitted', 'approved', 'terminated') then
    raise exception 'invalid_transition: employee % is % and cannot be archived', p_master_record_id, v_employee.lifecycle_status
      using errcode = 'check_violation';
  end if;
  v_from_status := v_employee.lifecycle_status;

  update app.employees
  set lifecycle_status = 'archived', archive_reason = p_reason
  where master_record_id = p_master_record_id and record_version = p_expected_version
  returning * into v_employee;
  if not found then
    raise exception 'stale_version: employee % target row was concurrently modified (expected version %)', p_master_record_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.employee_lifecycle_events (tenant_id, master_record_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (v_employee.tenant_id, p_master_record_id, v_from_status, 'archived', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_employee.tenant_id, p_actor_auth_user_id, p_actor_label, 'archive_employee_profile',
    'app.employees', p_master_record_id, 'success', p_reason, null, '{}'::jsonb
  );

  return v_employee;
end;
$$;

comment on function app.archive_employee_profile is 'HRT-274 (decision 6): reachable from a never-activated profile (draft/submitted/approved) OR from terminated -- two disclosed sibling closure paths, section 22''s "suspend OR archive with preserved history." Never from active/on_leave/suspended directly (must terminate first).';

-- ===========================================================================
-- 7. Transfer (decision 3, section 22 "transfer company/branch/department/position").
-- ===========================================================================

create function app.transfer_employee(
  p_master_record_id uuid,
  p_expected_version integer,
  p_company_org_unit_id uuid,
  p_branch_org_unit_id uuid,
  p_department_org_unit_id uuid,
  p_position_title text,
  p_manager_employee_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.employees
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
  v_before jsonb;
begin
  select * into v_employee from app.employees where master_record_id = p_master_record_id for update;
  if not found or not app.has_active_tenant_membership(v_employee.tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_employee.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_employee.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_employee.record_version <> p_expected_version then
    raise exception 'stale_version: employee % expected version % but found %', p_master_record_id, p_expected_version, v_employee.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_employee.lifecycle_status in ('terminated', 'archived') then
    raise exception 'invalid_transition: employee % is % and cannot be transferred', p_master_record_id, v_employee.lifecycle_status
      using errcode = 'check_violation';
  end if;

  if p_manager_employee_id is not null then
    if not exists (select 1 from app.employees where master_record_id = p_manager_employee_id and tenant_id = v_employee.tenant_id) then
      raise exception 'employee_not_found: manager % is not a valid employee for tenant %', p_manager_employee_id, v_employee.tenant_id using errcode = 'no_data_found';
    end if;
    perform app.assert_no_employee_manager_cycle(p_master_record_id, p_manager_employee_id);
  end if;

  v_before := jsonb_build_object(
    'company_org_unit_id', v_employee.company_org_unit_id, 'branch_org_unit_id', v_employee.branch_org_unit_id,
    'department_org_unit_id', v_employee.department_org_unit_id, 'position_title', v_employee.position_title,
    'manager_employee_id', v_employee.manager_employee_id
  );

  update app.employees
  set company_org_unit_id = p_company_org_unit_id, branch_org_unit_id = p_branch_org_unit_id,
      department_org_unit_id = p_department_org_unit_id, position_title = p_position_title,
      manager_employee_id = p_manager_employee_id
  where master_record_id = p_master_record_id and record_version = p_expected_version
  returning * into v_employee;
  if not found then
    raise exception 'stale_version: employee % target row was concurrently modified (expected version %)', p_master_record_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.employee_lifecycle_events (tenant_id, master_record_id, from_status, to_status, reason, metadata, actor_auth_user_id, actor_label)
  values (
    v_employee.tenant_id, p_master_record_id, v_employee.lifecycle_status, v_employee.lifecycle_status, p_reason,
    jsonb_build_object(
      'event', 'transfer', 'before', v_before,
      'after', jsonb_build_object(
        'company_org_unit_id', p_company_org_unit_id, 'branch_org_unit_id', p_branch_org_unit_id,
        'department_org_unit_id', p_department_org_unit_id, 'position_title', p_position_title,
        'manager_employee_id', p_manager_employee_id
      )
    ),
    p_actor_auth_user_id, p_actor_label
  );

  perform app.capture_audit_event(
    v_employee.tenant_id, p_actor_auth_user_id, p_actor_label, 'transfer_employee',
    'app.employees', p_master_record_id, 'success', p_reason, v_before, app.employee_audit_projection(v_employee)
  );

  return v_employee;
end;
$$;

comment on function app.transfer_employee is 'HRT-274 (section 22): moves company/branch/department/position/manager while preserving full before/after history in app.employee_lifecycle_events.metadata -- lifecycle_status itself is unchanged by a transfer (from_status=to_status in the event row, a real, disclosed shape distinguishing a transfer event from a status transition). Callable from any non-terminal status.';

-- ===========================================================================
-- 8. Emergency contact CRUD.
-- ===========================================================================

create function app.assert_employee_editable_for_child_crud(p_master_record_id uuid, p_actor_auth_user_id uuid, out v_employee app.employees)
language plpgsql
as $$
declare
  v_decision app.rbac_decision;
begin
  select * into v_employee from app.employees where master_record_id = p_master_record_id for update;
  if not found or not app.has_active_tenant_membership(v_employee.tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_employee.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_employee.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_employee.lifecycle_status in ('terminated', 'archived') then
    raise exception 'employee_closed: employee % is % -- child records may not be edited', p_master_record_id, v_employee.lifecycle_status
      using errcode = 'check_violation';
  end if;
end;
$$;

comment on function app.assert_employee_editable_for_child_crud is 'HRT-274: shared authority+state precondition for emergency-contact CRUD -- HRS:Edit plus a non-terminal lifecycle_status, under a `for update` row lock (mirrors app.assert_vendor_profile_editable, PRC-251). Unlike vendor child records, emergency contacts are editable throughout the employee''s active life, not draft-only -- an operational necessity, not registration-only data.';

create function app.add_employee_emergency_contact(
  p_master_record_id uuid, p_name text, p_relationship text, p_phone text, p_email text, p_is_primary boolean,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.employee_emergency_contacts
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_employee app.employees;
  v_contact app.employee_emergency_contacts;
begin
  v_employee := app.assert_employee_editable_for_child_crud(p_master_record_id, p_actor_auth_user_id);

  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'invalid_contact: name must not be empty' using errcode = 'check_violation';
  end if;

  if coalesce(p_is_primary, false) then
    update app.employee_emergency_contacts set is_primary = false where master_record_id = p_master_record_id and status = 'active' and is_primary;
  end if;

  insert into app.employee_emergency_contacts (tenant_id, master_record_id, name, relationship, phone, email, is_primary, created_by)
  values (v_employee.tenant_id, p_master_record_id, p_name, p_relationship, p_phone, p_email, coalesce(p_is_primary, false), p_actor_label)
  returning * into v_contact;

  perform app.capture_audit_event(
    v_employee.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_employee_emergency_contact',
    'app.employee_emergency_contacts', v_contact.id, 'success', null, null, app.employee_emergency_contact_audit_projection(v_contact)
  );

  return v_contact;
end;
$$;

create function app.update_employee_emergency_contact(
  p_contact_id uuid, p_expected_version integer, p_name text, p_relationship text, p_phone text, p_email text, p_is_primary boolean,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.employee_emergency_contacts
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_contact app.employee_emergency_contacts;
  v_employee app.employees;
begin
  select * into v_contact from app.employee_emergency_contacts where id = p_contact_id and status = 'active';
  if not found then
    raise exception 'contact_not_found: %', p_contact_id using errcode = 'no_data_found';
  end if;

  -- Authority BEFORE record_version (this checkpoint's own review-round fix, matching
  -- decision 9's own discipline every other write RPC in this file already follows):
  -- app.assert_employee_editable_for_child_crud folds a non-member/unauthorized caller
  -- into employee_not_found/insufficient_authority. Only a real, authorized editor ever
  -- reaches the record_version check below -- an unauthorized caller can no longer probe
  -- a Tenant A contact's real current record_version via a deliberately stale
  -- p_expected_version before being told they lack authority.
  v_employee := app.assert_employee_editable_for_child_crud(v_contact.master_record_id, p_actor_auth_user_id);

  if v_contact.record_version <> p_expected_version then
    raise exception 'stale_version: emergency contact % expected version % but found %', p_contact_id, p_expected_version, v_contact.record_version
      using errcode = 'serialization_failure';
  end if;

  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'invalid_contact: name must not be empty' using errcode = 'check_violation';
  end if;

  if coalesce(p_is_primary, false) then
    update app.employee_emergency_contacts set is_primary = false where master_record_id = v_contact.master_record_id and status = 'active' and is_primary and id <> p_contact_id;
  end if;

  update app.employee_emergency_contacts
  set name = p_name, relationship = p_relationship, phone = p_phone, email = p_email, is_primary = coalesce(p_is_primary, false)
  where id = p_contact_id and record_version = p_expected_version
  returning * into v_contact;
  if not found then
    raise exception 'stale_version: emergency contact % target row was concurrently modified (expected version %)', p_contact_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_employee.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_employee_emergency_contact',
    'app.employee_emergency_contacts', v_contact.id, 'success', null, null, app.employee_emergency_contact_audit_projection(v_contact)
  );

  return v_contact;
end;
$$;

create function app.remove_employee_emergency_contact(p_contact_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.employee_emergency_contacts
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_contact app.employee_emergency_contacts;
  v_employee app.employees;
begin
  select * into v_contact from app.employee_emergency_contacts where id = p_contact_id and status = 'active';
  if not found then
    raise exception 'contact_not_found: %', p_contact_id using errcode = 'no_data_found';
  end if;

  -- Authority BEFORE record_version -- see the identical fix/rationale in
  -- app.update_employee_emergency_contact immediately above.
  v_employee := app.assert_employee_editable_for_child_crud(v_contact.master_record_id, p_actor_auth_user_id);

  if v_contact.record_version <> p_expected_version then
    raise exception 'stale_version: emergency contact % expected version % but found %', p_contact_id, p_expected_version, v_contact.record_version
      using errcode = 'serialization_failure';
  end if;

  update app.employee_emergency_contacts
  set status = 'removed', is_primary = false
  where id = p_contact_id and record_version = p_expected_version
  returning * into v_contact;
  if not found then
    raise exception 'stale_version: emergency contact % target row was concurrently modified (expected version %)', p_contact_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_employee.tenant_id, p_actor_auth_user_id, p_actor_label, 'remove_employee_emergency_contact',
    'app.employee_emergency_contacts', v_contact.id, 'success', null, null, '{}'::jsonb
  );

  return v_contact;
end;
$$;

-- ===========================================================================
-- 9. Duplicate review (decision 10).
-- ===========================================================================

create function app.flag_employee_duplicate_candidate(
  p_source_master_record_id uuid, p_candidate_master_record_id uuid, p_similarity_basis text, p_similarity_score numeric,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.employee_duplicate_candidates
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_source app.employees;
  v_candidate app.employees;
  v_row app.employee_duplicate_candidates;
begin
  select * into v_source from app.employees where master_record_id = p_source_master_record_id;
  if not found or not app.has_active_tenant_membership(v_source.tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_source_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_source.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_source.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_candidate from app.employees where master_record_id = p_candidate_master_record_id and tenant_id = v_source.tenant_id;
  if not found then
    raise exception 'employee_not_found: candidate % is not a valid employee for tenant %', p_candidate_master_record_id, v_source.tenant_id using errcode = 'no_data_found';
  end if;

  if p_similarity_basis is null or length(trim(p_similarity_basis)) = 0 then
    raise exception 'invalid_similarity_basis: similarity_basis must not be empty' using errcode = 'check_violation';
  end if;

  insert into app.employee_duplicate_candidates (tenant_id, source_master_record_id, candidate_master_record_id, similarity_basis, similarity_score, created_by)
  values (v_source.tenant_id, p_source_master_record_id, p_candidate_master_record_id, p_similarity_basis, p_similarity_score, p_actor_label)
  returning * into v_row;

  perform app.capture_audit_event(
    v_source.tenant_id, p_actor_auth_user_id, p_actor_label, 'flag_employee_duplicate_candidate',
    'app.employee_duplicate_candidates', v_row.id, 'success', null, null, to_jsonb(v_row)
  );

  return v_row;
end;
$$;

create function app.decide_employee_duplicate_candidate(
  p_candidate_id uuid, p_expected_version integer, p_decision text, p_reason text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.employee_duplicate_candidates
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_row app.employee_duplicate_candidates;
  v_tenant_id uuid;
begin
  if p_decision not in ('linked', 'dismissed') then
    raise exception 'invalid_decision: % is not linked or dismissed', p_decision using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to decide a duplicate candidate' using errcode = 'check_violation';
  end if;

  select * into v_row from app.employee_duplicate_candidates where id = p_candidate_id for update;
  if not found or not app.has_active_tenant_membership(v_row.tenant_id, p_actor_auth_user_id) then
    raise exception 'duplicate_candidate_not_found: %', p_candidate_id using errcode = 'no_data_found';
  end if;
  v_tenant_id := v_row.tenant_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_row.record_version <> p_expected_version then
    raise exception 'stale_version: duplicate candidate % expected version % but found %', p_candidate_id, p_expected_version, v_row.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_row.decision <> 'pending' then
    raise exception 'duplicate_candidate_already_decided: candidate % is already %', p_candidate_id, v_row.decision using errcode = 'check_violation';
  end if;

  update app.employee_duplicate_candidates
  set decision = p_decision, decided_by = p_actor_label, decided_at = now(), decided_reason = p_reason, record_version = record_version + 1
  where id = p_candidate_id and record_version = p_expected_version
  returning * into v_row;
  if not found then
    raise exception 'stale_version: duplicate candidate % target row was concurrently modified (expected version %)', p_candidate_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_employee_duplicate_candidate',
    'app.employee_duplicate_candidates', p_candidate_id, 'success', p_reason, null, jsonb_build_object('decision', p_decision)
  );

  return v_row;
end;
$$;

comment on function app.decide_employee_duplicate_candidate is 'HRT-274 (decision 10): decision=''linked'' documents a reviewer''s finding only -- it never invokes app.merge_master_records itself. A real data merge remains a deliberate, separate tenant_admin/Supreme action through PLT-120''s own existing tooling.';

-- ===========================================================================
-- 10. Own-profile change requests (decision, section 22 "request personal-data
--     correction"). Identity-match-gated, NOT app.evaluate_permission-gated -- an
--     ordinary employee is not expected to hold any HRS permission.
-- ===========================================================================

create function app.request_employee_change(
  p_master_record_id uuid,
  p_field_key text,
  p_requested_value text,
  p_reason text,
  p_actor_auth_user_id uuid
)
returns app.employee_change_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_employee app.employees;
  v_caller_user_id uuid;
  v_current_value text;
  v_request app.employee_change_requests;
begin
  -- Does not call app.evaluate_permission (identity-match-gated, not permission-gated)
  -- -- explicit session-identity assertion required, per decision 8.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_field_key not in ('personal_email', 'personal_phone', 'personal_address_street', 'personal_address_city', 'personal_address_province', 'personal_address_postal_code', 'personal_address_country') then
    raise exception 'invalid_field_key: % is not a self-editable field', p_field_key using errcode = 'check_violation';
  end if;
  if p_requested_value is null or length(trim(p_requested_value)) = 0 then
    raise exception 'invalid_requested_value: requested_value must not be empty' using errcode = 'check_violation';
  end if;

  select * into v_employee from app.employees where master_record_id = p_master_record_id;
  if not found then
    raise exception 'employee_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  select id into v_caller_user_id from app.users where auth_user_id = p_actor_auth_user_id and tenant_id = v_employee.tenant_id;
  if v_caller_user_id is null or v_employee.user_id is distinct from v_caller_user_id then
    raise exception 'not_own_profile: identity % may not request a change against employee %', p_actor_auth_user_id, p_master_record_id
      using errcode = 'insufficient_privilege';
  end if;

  execute format('select ($1).%I::text', p_field_key) into v_current_value using v_employee;

  insert into app.employee_change_requests (tenant_id, master_record_id, requested_by_user_id, field_key, current_value_snapshot, requested_value, reason)
  values (v_employee.tenant_id, p_master_record_id, v_caller_user_id, p_field_key, v_current_value, p_requested_value, p_reason)
  returning * into v_request;

  -- app.audit_logs.actor_label is NOT NULL and this RPC carries no p_actor_label
  -- parameter (a genuinely self-service action, no separate human-readable label
  -- threaded through) -- p_actor_auth_user_id::text is the same fallback the
  -- calling Server Action layer already uses whenever no display name is
  -- available (mirrors app/(tenant)/[tenantSlug]/procurement/vendors/actions.ts's
  -- own `actorLabel: access.authUserId` convention), found live running this
  -- checkpoint's own db-test suite (a real NOT NULL violation, not a lint nit).
  -- Deliberately NOT to_jsonb(v_request): current_value_snapshot/requested_value are
  -- always a classified pii value for every legal field_key on this table (the
  -- employee_change_requests_field_key_check allow-list is entirely personal_email/
  -- personal_phone/personal_address_* -- there is no non-pii field_key), so the raw
  -- row must never reach app.audit_logs (this checkpoint's own review-round fix,
  -- same defect class as app.employee_audit_projection above).
  perform app.capture_audit_event(
    v_employee.tenant_id, p_actor_auth_user_id, p_actor_auth_user_id::text, 'request_employee_change',
    'app.employee_change_requests', v_request.id, 'success', p_reason, null,
    jsonb_build_object('field_key', v_request.field_key, 'status', v_request.status, 'record_version', v_request.record_version)
  );

  return v_request;
end;
$$;

comment on function app.request_employee_change is 'HRT-274: the ''create a profile before a user account'' flow (ADR-0023) means an employee with no linked user_id can never satisfy the identity-match check here -- correctly, since there is no session identity to request on their behalf yet. p_field_key''s dynamic column read uses `format(...)` against a FIXED CHECK-constrained allow-list only (never a caller-controlled arbitrary column), so no SQL injection surface exists despite the dynamic EXECUTE.';

create function app.decide_employee_change_request(
  p_request_id uuid,
  p_expected_version integer,
  p_decision text,
  p_decided_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.employee_change_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_request app.employee_change_requests;
  v_employee app.employees;
begin
  if p_decision not in ('approved', 'rejected') then
    raise exception 'invalid_decision: % is not approved or rejected', p_decision using errcode = 'check_violation';
  end if;
  if p_decided_reason is null or length(trim(p_decided_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to decide a change request' using errcode = 'check_violation';
  end if;

  select * into v_request from app.employee_change_requests where id = p_request_id for update;
  if not found or not app.has_active_tenant_membership(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'change_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_request.record_version <> p_expected_version then
    raise exception 'stale_version: change request % expected version % but found %', p_request_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_request.status <> 'pending' then
    raise exception 'change_request_already_decided: request % is already %', p_request_id, v_request.status using errcode = 'check_violation';
  end if;

  if p_decision = 'approved' then
    select * into v_employee from app.employees where master_record_id = v_request.master_record_id for update;
    -- Fixed column allow-list applied via a real CASE, never dynamic SQL against a
    -- caller-influenced identifier (unlike the read-only snapshot in
    -- app.request_employee_change, this WRITES, so no format()/EXECUTE is used at
    -- all here -- an explicit branch per legal field_key).
    case v_request.field_key
      when 'personal_email' then update app.employees set personal_email = v_request.requested_value where master_record_id = v_request.master_record_id;
      when 'personal_phone' then update app.employees set personal_phone = v_request.requested_value where master_record_id = v_request.master_record_id;
      when 'personal_address_street' then update app.employees set personal_address_street = v_request.requested_value where master_record_id = v_request.master_record_id;
      when 'personal_address_city' then update app.employees set personal_address_city = v_request.requested_value where master_record_id = v_request.master_record_id;
      when 'personal_address_province' then update app.employees set personal_address_province = v_request.requested_value where master_record_id = v_request.master_record_id;
      when 'personal_address_postal_code' then update app.employees set personal_address_postal_code = v_request.requested_value where master_record_id = v_request.master_record_id;
      when 'personal_address_country' then update app.employees set personal_address_country = v_request.requested_value where master_record_id = v_request.master_record_id;
      else raise exception 'invalid_field_key: % is not a recognized self-editable field', v_request.field_key using errcode = 'check_violation';
    end case;

    insert into app.employee_lifecycle_events (tenant_id, master_record_id, from_status, to_status, reason, metadata, actor_auth_user_id, actor_label)
    values (v_request.tenant_id, v_request.master_record_id, v_employee.lifecycle_status, v_employee.lifecycle_status, p_decided_reason, jsonb_build_object('event', 'change_request_applied', 'field_key', v_request.field_key), p_actor_auth_user_id, p_actor_label);
  end if;

  update app.employee_change_requests
  set status = p_decision, decided_by = p_actor_label, decided_at = now(), decided_reason = p_decided_reason
  where id = p_request_id and record_version = p_expected_version
  returning * into v_request;
  if not found then
    raise exception 'stale_version: change request % target row was concurrently modified (expected version %)', p_request_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_employee_change_request',
    'app.employee_change_requests', p_request_id, 'success', p_decided_reason, null, jsonb_build_object('decision', p_decision)
  );

  return v_request;
end;
$$;

-- ===========================================================================
-- 11. Read RPCs (HRS:View, unless noted).
-- ===========================================================================

create function app.list_employees(
  p_tenant_id uuid, p_actor_auth_user_id uuid, p_status_filter text default null, p_department_org_unit_id uuid default null,
  p_search text default null, p_limit integer default 50, p_after_employee_number text default null
)
returns table (
  master_record_id uuid, employee_number text, full_name text, employment_type text, lifecycle_status text,
  department_org_unit_id uuid, position_title text, hire_date date, record_version integer, created_at timestamptz, updated_at timestamptz
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_status_filter is not null and p_status_filter not in ('draft', 'submitted', 'approved', 'active', 'on_leave', 'suspended', 'terminated', 'archived') then
    raise exception 'invalid_status_filter: %', p_status_filter using errcode = 'check_violation';
  end if;

  return query
  select e.master_record_id, m.code, e.full_name, e.employment_type, e.lifecycle_status,
         e.department_org_unit_id, e.position_title, e.hire_date, e.record_version, e.created_at, e.updated_at
  from app.employees e
  join app.master_records m on m.id = e.master_record_id
  where e.tenant_id = p_tenant_id
    and (p_status_filter is null or e.lifecycle_status = p_status_filter)
    and (p_department_org_unit_id is null or e.department_org_unit_id = p_department_org_unit_id)
    and (p_search is null or m.code ilike '%' || p_search || '%' or e.full_name ilike '%' || p_search || '%')
    and (p_after_employee_number is null or m.code > p_after_employee_number)
  order by m.code
  limit least(coalesce(p_limit, 50), 200);
end;
$$;

comment on function app.list_employees is 'HRT-274: cursor-paginated (employee_number-keyset), server-filtered/searched directory projection -- selective columns only, no SELECT *, no PII column at all (personal data is never in a list projection, only in app.get_employee_profile''s own masked single-record read).';

create function app.get_employee_profile(p_master_record_id uuid, p_actor_auth_user_id uuid)
returns table (
  master_record_id uuid, employee_number text, tenant_id uuid, user_id uuid, full_name text, employment_type text, lifecycle_status text, intake_source text,
  work_email text, work_phone text, personal_email text, personal_phone text, national_id_number text, date_of_birth date, gender text,
  personal_address_street text, personal_address_city text, personal_address_province text, personal_address_postal_code text, personal_address_country text,
  hire_date date, probation_end_date date, employment_end_date date, company_org_unit_id uuid, branch_org_unit_id uuid, department_org_unit_id uuid,
  position_title text, manager_employee_id uuid, revision_reason text, suspend_reason text, terminate_reason text, archive_reason text, leave_reason text,
  record_version integer, created_at timestamptz, updated_at timestamptz, personal_data_masked boolean
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
  v_master app.master_records;
  v_caller_user_id uuid;
  v_is_self boolean;
  v_unmasked boolean;
begin
  -- Table-aliased and explicitly qualified: this function's own RETURNS TABLE
  -- includes both master_record_id and tenant_id, so a bare reference to either
  -- name is genuinely ambiguous against those OUT columns (the identical class of
  -- bug app.get_my_employee_profile hit, found live running this checkpoint's own
  -- db-test suite).
  select * into v_employee from app.employees e where e.master_record_id = p_master_record_id;
  if not found or not app.has_active_tenant_membership(v_employee.tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  select u.id into v_caller_user_id from app.users u where u.auth_user_id = p_actor_auth_user_id and u.tenant_id = v_employee.tenant_id;
  v_is_self := v_caller_user_id is not null and v_employee.user_id is not distinct from v_caller_user_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_employee.tenant_id, 'HRS', 'View');
  if not v_decision.allowed and not v_is_self then
    raise exception 'insufficient_authority: identity % lacks HRS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_employee.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_unmasked := v_is_self or app.has_view_personal_data(v_employee.tenant_id, p_actor_auth_user_id);

  select * into v_master from app.master_records where id = p_master_record_id;

  return query
  select
    v_employee.master_record_id, v_master.code, v_employee.tenant_id, v_employee.user_id, v_employee.full_name, v_employee.employment_type,
    v_employee.lifecycle_status, v_employee.intake_source, v_employee.work_email, v_employee.work_phone,
    case when v_unmasked then v_employee.personal_email else null end,
    case when v_unmasked then v_employee.personal_phone else null end,
    case when v_unmasked then v_employee.national_id_number else null end,
    case when v_unmasked then v_employee.date_of_birth else null end,
    case when v_unmasked then v_employee.gender else null end,
    case when v_unmasked then v_employee.personal_address_street else null end,
    case when v_unmasked then v_employee.personal_address_city else null end,
    case when v_unmasked then v_employee.personal_address_province else null end,
    case when v_unmasked then v_employee.personal_address_postal_code else null end,
    case when v_unmasked then v_employee.personal_address_country else null end,
    v_employee.hire_date, v_employee.probation_end_date, v_employee.employment_end_date,
    v_employee.company_org_unit_id, v_employee.branch_org_unit_id, v_employee.department_org_unit_id,
    v_employee.position_title, v_employee.manager_employee_id, v_employee.revision_reason, v_employee.suspend_reason,
    v_employee.terminate_reason, v_employee.archive_reason, v_employee.leave_reason,
    v_employee.record_version, v_employee.created_at, v_employee.updated_at, not v_unmasked;
end;
$$;

comment on function app.get_employee_profile is 'HRT-274: HR/self-service detail read. Sensitive personal columns are nulled (personal_data_masked=true) unless the caller holds HRS:View personal data OR is reading their own linked profile (v_is_self) -- own-profile access never requires the HR permission.';

create function app.get_my_employee_profile(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (
  master_record_id uuid, employee_number text, tenant_id uuid, user_id uuid, full_name text, employment_type text, lifecycle_status text, intake_source text,
  work_email text, work_phone text, personal_email text, personal_phone text, national_id_number text, date_of_birth date, gender text,
  personal_address_street text, personal_address_city text, personal_address_province text, personal_address_postal_code text, personal_address_country text,
  hire_date date, probation_end_date date, employment_end_date date, company_org_unit_id uuid, branch_org_unit_id uuid, department_org_unit_id uuid,
  position_title text, manager_employee_id uuid, record_version integer, created_at timestamptz, updated_at timestamptz
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_caller_user_id uuid;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    return;
  end if;

  -- Table-aliased and explicitly qualified (u.tenant_id/u.auth_user_id): a bare
  -- `tenant_id` here is genuinely ambiguous against this function's own RETURNS
  -- TABLE column of the identical name, found live running this checkpoint's own
  -- db-test suite (a real Postgres plpgsql ambiguous-column error, not a lint nit).
  select u.id into v_caller_user_id from app.users u where u.auth_user_id = p_actor_auth_user_id and u.tenant_id = p_tenant_id;
  if v_caller_user_id is null then
    return;
  end if;

  return query
  select
    e.master_record_id, m.code, e.tenant_id, e.user_id, e.full_name, e.employment_type, e.lifecycle_status, e.intake_source,
    e.work_email, e.work_phone, e.personal_email, e.personal_phone, e.national_id_number, e.date_of_birth, e.gender,
    e.personal_address_street, e.personal_address_city, e.personal_address_province, e.personal_address_postal_code, e.personal_address_country,
    e.hire_date, e.probation_end_date, e.employment_end_date, e.company_org_unit_id, e.branch_org_unit_id, e.department_org_unit_id,
    e.position_title, e.manager_employee_id, e.record_version, e.created_at, e.updated_at
  from app.employees e
  join app.master_records m on m.id = e.master_record_id
  where e.tenant_id = p_tenant_id and e.user_id = v_caller_user_id;
end;
$$;

comment on function app.get_my_employee_profile is 'HRT-274: self-only, unmasked (it is always the caller''s own data) -- returns zero rows (never raises) when the caller has no linked employee profile yet, matching this repository''s "never a fabricated result" discipline while still degrading gracefully for an unlinked account.';

create function app.list_my_team_employees(p_tenant_id uuid, p_actor_auth_user_id uuid, p_limit integer default 50, p_after_employee_number text default null)
returns table (master_record_id uuid, employee_number text, full_name text, employment_type text, lifecycle_status text, position_title text, hire_date date)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_caller_user_id uuid;
  v_manager_employee_id uuid;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    return;
  end if;

  select u.id into v_caller_user_id from app.users u where u.auth_user_id = p_actor_auth_user_id and u.tenant_id = p_tenant_id;
  if v_caller_user_id is null then
    return;
  end if;

  -- Table-aliased: this function's own RETURNS TABLE includes master_record_id,
  -- so a bare reference to it is genuinely ambiguous against that OUT column
  -- (the identical class of bug app.get_employee_profile hit, above).
  select e.master_record_id into v_manager_employee_id from app.employees e where e.tenant_id = p_tenant_id and e.user_id = v_caller_user_id;
  if v_manager_employee_id is null then
    return;
  end if;

  return query
  select e.master_record_id, m.code, e.full_name, e.employment_type, e.lifecycle_status, e.position_title, e.hire_date
  from app.employees e
  join app.master_records m on m.id = e.master_record_id
  where e.tenant_id = p_tenant_id and e.manager_employee_id = v_manager_employee_id
    and (p_after_employee_number is null or m.code > p_after_employee_number)
  order by m.code
  limit least(coalesce(p_limit, 50), 200);
end;
$$;

comment on function app.list_my_team_employees is 'HRT-274 (section 26: "managers see current effective team fields"): manager-scoped, self-resolved (the caller''s OWN employee row determines their team, never a caller-supplied manager id). Deliberately excludes every sensitive personal column regardless of permission -- a manager''s team view is organizational fields only, never PII (a disclosed, narrower scope than HR''s own HRS:View personal data-gated read).';

create function app.get_employee_lifecycle_history(p_master_record_id uuid, p_actor_auth_user_id uuid)
returns setof app.employee_lifecycle_events
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
begin
  select * into v_employee from app.employees where master_record_id = p_master_record_id;
  if not found or not app.has_active_tenant_membership(v_employee.tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_employee.tenant_id, 'HRS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_employee.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.employee_lifecycle_events where master_record_id = p_master_record_id order by occurred_at;
end;
$$;

create function app.list_employee_emergency_contacts(p_master_record_id uuid, p_actor_auth_user_id uuid)
returns table (id uuid, master_record_id uuid, name text, relationship text, phone text, email text, is_primary boolean, record_version integer, created_at timestamptz)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
  v_masked boolean;
begin
  -- Table-aliased: this function's own RETURNS TABLE includes master_record_id,
  -- so a bare reference to it is genuinely ambiguous against that OUT column.
  select * into v_employee from app.employees e where e.master_record_id = p_master_record_id;
  if not found or not app.has_active_tenant_membership(v_employee.tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_employee.tenant_id, 'HRS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_employee.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_masked := not app.has_view_personal_data(v_employee.tenant_id, p_actor_auth_user_id);

  return query
  select c.id, c.master_record_id, c.name, c.relationship,
         case when v_masked then null else c.phone end,
         case when v_masked then null else c.email end,
         c.is_primary, c.record_version, c.created_at
  from app.employee_emergency_contacts c
  where c.master_record_id = p_master_record_id and c.status = 'active'
  order by c.is_primary desc, c.created_at;
end;
$$;

create function app.list_employee_duplicate_candidates(p_master_record_id uuid, p_actor_auth_user_id uuid)
returns setof app.employee_duplicate_candidates
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
begin
  select * into v_employee from app.employees where master_record_id = p_master_record_id;
  if not found or not app.has_active_tenant_membership(v_employee.tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_employee.tenant_id, 'HRS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_employee.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.employee_duplicate_candidates where source_master_record_id = p_master_record_id order by created_at desc;
end;
$$;

create function app.search_employee_duplicate_candidates(p_tenant_id uuid, p_full_name text, p_national_id_number text, p_work_email text, p_personal_email text, p_actor_auth_user_id uuid, p_limit integer default 10)
returns table (master_record_id uuid, employee_number text, full_name text, similarity_score real, match_basis text)
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select e.master_record_id, m.code, e.full_name,
         case
           when p_national_id_number is not null and e.national_id_number = p_national_id_number then 1.0::real
           when p_work_email is not null and e.work_email = p_work_email then 1.0::real
           when p_personal_email is not null and e.personal_email = p_personal_email then 1.0::real
           else similarity(e.full_name, coalesce(p_full_name, ''))
         end as score,
         case
           when p_national_id_number is not null and e.national_id_number = p_national_id_number then 'national_id_number exact match'
           when p_work_email is not null and e.work_email = p_work_email then 'work_email exact match'
           when p_personal_email is not null and e.personal_email = p_personal_email then 'personal_email exact match'
           else 'full_name trigram similarity'
         end as basis
  from app.employees e
  join app.master_records m on m.id = e.master_record_id
  where e.tenant_id = p_tenant_id
    and (
      (p_national_id_number is not null and e.national_id_number = p_national_id_number)
      or (p_work_email is not null and e.work_email = p_work_email)
      or (p_personal_email is not null and e.personal_email = p_personal_email)
      or (p_full_name is not null and e.full_name % p_full_name)
    )
  order by score desc
  limit least(coalesce(p_limit, 10), 50);
end;
$$;

comment on function app.search_employee_duplicate_candidates is 'HRT-274 (decision 10): exact match on national_id_number/work_email/personal_email (score 1.0) OR pg_trgm fuzzy match on full_name -- never over app.master_records directly, matching app.search_vendor_duplicate_candidates'' own established shape.';

create function app.export_employees(p_tenant_id uuid, p_actor_auth_user_id uuid, p_status_filter text default null, p_limit integer default 500)
returns table (employee_number text, full_name text, employment_type text, lifecycle_status text, hire_date date, department_org_unit_id uuid, position_title text)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'Export');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Export (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_status_filter is not null and p_status_filter not in ('draft', 'submitted', 'approved', 'active', 'on_leave', 'suspended', 'terminated', 'archived') then
    raise exception 'invalid_status_filter: %', p_status_filter using errcode = 'check_violation';
  end if;

  return query
  select m.code, e.full_name, e.employment_type, e.lifecycle_status, e.hire_date, e.department_org_unit_id, e.position_title
  from app.employees e
  join app.master_records m on m.id = e.master_record_id
  where e.tenant_id = p_tenant_id and (p_status_filter is null or e.lifecycle_status = p_status_filter)
  order by m.code
  limit least(coalesce(p_limit, 500), 5000);
end;
$$;

comment on function app.export_employees is 'HRT-274 (section 14 "scoped export"): a deliberately narrow, non-PII projection -- no personal_email/personal_phone/national_id_number/date_of_birth/gender/address column is ever included in an export, regardless of the caller''s HRS:View personal data standing. Exporting sensitive personal data in bulk is out of this checkpoint''s own scope; disclosed, not silently narrowed.';

-- ===========================================================================
-- 12. Staged import (decision 11, PLT-131/132, fifth-plus real domain-write adapter).
-- ===========================================================================

-- Document type registration (decision 4: documents reuse app.files directly, never a
-- second file table). Mirrors 'vendor_rate_import''s own direct-INSERT convention --
-- app.register_document_type gates on Supreme Admin and a migration-apply context has
-- no live actor session. Each tenant still separately configures and PUBLISHES its own
-- document:employee_document column definition (allowed MIME types, max size,
-- retention class, default classification, legal-hold eligibility) via the existing
-- Configuration Engine before any real upload against this document type can succeed
-- -- the identical, already-established per-tenant onboarding step every other
-- document type in this repository requires (PLT-128's own design).
insert into app.document_types (code, name, owner_primitive_code, registered_by)
values ('employee_document', 'Employee Document', 'HRS', 'system')
on conflict (code) do nothing;

-- app.register_document_type (the normal, Supreme-Admin-gated path) always mints a
-- matching 'document:<code>' app.config_types row alongside the document_types row
-- (register_document_type's own body: `perform app.register_config_type('document:'
-- || p_code, ...)`) -- since this migration bypasses that function (no live actor at
-- migration-apply time, identical reasoning to decision 11's import_export_schemas
-- dual-insert), it must mint the SAME config_types row directly too, or
-- app.create_config_draft('document:employee_document', ...) has no row to reference
-- (a real, live-reproduced foreign-key failure this checkpoint's own db-test suite
-- caught, not a theoretical concern).
insert into app.config_types (code, name, owner_primitive_code, registered_by)
values ('document:employee_document', 'Employee Document', 'HRS', 'system')
on conflict (code) do nothing;

insert into app.import_export_schemas (code, name, owner_primitive_code, registered_by)
values ('employee_import', 'Employee Import', 'HRS', 'system')
on conflict (code) do nothing;

insert into app.config_types (code, name, owner_primitive_code, registered_by)
values ('import_export:employee_import', 'Employee Import', 'HRS', 'system')
on conflict (code) do nothing;

create function app.validate_employee_import_row(
  p_staging_row_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.import_staging_rows
language plpgsql
as $$
declare
  v_row app.import_staging_rows;
  v_job app.jobs;
  v_payload jsonb;
  v_field text;
  v_value text;
  v_errors text[] := array[]::text[];
  v_text_fields text[] := array['employee_number', 'full_name', 'work_email', 'personal_email', 'personal_phone', 'employment_type', 'company_org_unit_code', 'branch_org_unit_code', 'department_org_unit_code', 'position_title'];
begin
  v_row := app.validate_staging_row(p_staging_row_id, p_actor_auth_user_id, p_actor_label);

  if v_row.validation_status <> 'valid' then
    return v_row;
  end if;

  select * into v_job from app.jobs where job_id = v_row.job_id;
  v_payload := v_row.raw_payload;

  foreach v_field in array v_text_fields loop
    v_value := v_payload ->> v_field;
    if v_value is not null and v_value ~ '^[-+=@\t\r]' then
      v_errors := v_errors || (v_field || ': value begins with a disallowed formula/spreadsheet-injection prefix (=, +, -, @, tab, or carriage return)');
    end if;
  end loop;

  if coalesce(v_payload ->> 'employment_type', '') <> '' and (v_payload ->> 'employment_type') not in ('full_time', 'part_time', 'contract', 'intern', 'probation', 'daily_worker') then
    v_errors := v_errors || ('employment_type: ' || (v_payload ->> 'employment_type') || ' is not a recognized employment type');
  end if;

  if coalesce(v_payload ->> 'company_org_unit_code', '') <> '' and not exists (select 1 from app.org_units where tenant_id = v_job.tenant_id and code = (v_payload ->> 'company_org_unit_code') and unit_type = 'company') then
    v_errors := v_errors || ('company_org_unit_code: ' || (v_payload ->> 'company_org_unit_code') || ' does not resolve to a company org unit in this tenant');
  end if;
  if coalesce(v_payload ->> 'branch_org_unit_code', '') <> '' and not exists (select 1 from app.org_units where tenant_id = v_job.tenant_id and code = (v_payload ->> 'branch_org_unit_code') and unit_type = 'branch') then
    v_errors := v_errors || ('branch_org_unit_code: ' || (v_payload ->> 'branch_org_unit_code') || ' does not resolve to a branch org unit in this tenant');
  end if;
  if coalesce(v_payload ->> 'department_org_unit_code', '') <> '' and not exists (select 1 from app.org_units where tenant_id = v_job.tenant_id and code = (v_payload ->> 'department_org_unit_code') and unit_type = 'department') then
    v_errors := v_errors || ('department_org_unit_code: ' || (v_payload ->> 'department_org_unit_code') || ' does not resolve to a department org unit in this tenant');
  end if;

  if array_length(v_errors, 1) is not null then
    update app.import_staging_rows
    set validation_status = 'invalid', error = array_to_string(v_errors, '; ')
    where id = p_staging_row_id
    returning * into v_row;

    update app.jobs
    set invalid_row_count = invalid_row_count + 1, valid_row_count = valid_row_count - 1
    where job_id = v_row.job_id;
  end if;

  return v_row;
end;
$$;

comment on function app.validate_employee_import_row is 'HRT-274 (decision 11): calls app.validate_staging_row UNCHANGED first (generic structural pass, never reimplemented), then a formula/spreadsheet-injection rejection pass (identical prefix set to app.validate_vendor_rate_import_row, PRC-255) plus org-unit-code resolution.';

create function app.commit_employee_import_job(
  p_job_id uuid,
  p_allow_partial boolean,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.jobs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_job app.jobs;
  v_decision app.rbac_decision;
  v_pending_count integer;
  v_row record;
  v_payload jsonb;
  v_company_id uuid;
  v_branch_id uuid;
  v_department_id uuid;
  v_number text;
  v_master app.master_records;
  v_employee app.employees;
  v_created_count integer := 0;
  v_skipped_count integer := 0;
  v_updated app.jobs;
  v_config_version_id uuid;
begin
  select * into v_job from app.jobs where job_id = p_job_id for update;
  if not found then
    raise exception 'import_export_job_not_found: no job %', p_job_id using errcode = 'no_data_found';
  end if;

  if v_job.job_type <> 'import' or v_job.import_export_schema_code <> 'employee_import' then
    raise exception 'import_export_wrong_schema: job % is not an employee_import job', p_job_id using errcode = 'check_violation';
  end if;

  if not app.check_import_export_job_authority(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'job_actor_unauthorized: identity % lacks active membership in tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_job.tenant_id, 'HRS', 'Import');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Import (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_job.status <> 'in_progress' then
    raise exception 'import_export_job_not_committable: job % is %, only an in_progress job may be committed', p_job_id, v_job.status
      using errcode = 'check_violation';
  end if;

  select count(*) into v_pending_count from app.import_staging_rows where job_id = p_job_id and validation_status = 'pending';
  if v_pending_count > 0 then
    raise exception 'import_export_job_not_fully_validated: job % still has % row(s) pending validation', p_job_id, v_pending_count
      using errcode = 'check_violation';
  end if;

  if v_job.invalid_row_count > 0 and not coalesce(p_allow_partial, false) then
    raise exception 'import_export_job_has_invalid_rows: job % has % invalid row(s); pass p_allow_partial to accept a partial commit', p_job_id, v_job.invalid_row_count
      using errcode = 'check_violation';
  end if;

  select config_version_id into v_config_version_id from app.resolve_import_export_schema_columns(v_job.tenant_id, 'employee_import');

  -- Job-scoped advisory lock (mirrors app.commit_vendor_rate_import_job, PRC-255)
  -- -- resolved and taken before any staging row is read, serializing any
  -- concurrent/replayed commit call on this SAME job.
  perform pg_advisory_xact_lock(hashtextextended(p_job_id::text, 274));

  for v_row in
    select * from app.import_staging_rows
    where job_id = p_job_id and validation_status = 'valid'
    order by row_number
  loop
    if exists (select 1 from app.employees where source_import_staging_row_id = v_row.id) then
      v_skipped_count := v_skipped_count + 1;
      continue;
    end if;

    v_payload := v_row.raw_payload;

    v_company_id := null;
    v_branch_id := null;
    v_department_id := null;
    if coalesce(v_payload ->> 'company_org_unit_code', '') <> '' then
      select id into v_company_id from app.org_units where tenant_id = v_job.tenant_id and code = (v_payload ->> 'company_org_unit_code') and unit_type = 'company';
    end if;
    if coalesce(v_payload ->> 'branch_org_unit_code', '') <> '' then
      select id into v_branch_id from app.org_units where tenant_id = v_job.tenant_id and code = (v_payload ->> 'branch_org_unit_code') and unit_type = 'branch';
    end if;
    if coalesce(v_payload ->> 'department_org_unit_code', '') <> '' then
      select id into v_department_id from app.org_units where tenant_id = v_job.tenant_id and code = (v_payload ->> 'department_org_unit_code') and unit_type = 'department';
    end if;

    v_number := coalesce(nullif(v_payload ->> 'employee_number', ''), app.next_employee_number(v_job.tenant_id));

    begin
      insert into app.master_records (master_type_code, tenant_id, code, name, aliases, attributes, created_by)
      values ('employee', v_job.tenant_id, v_number, v_payload ->> 'full_name', '[]'::jsonb, '{}'::jsonb, p_actor_label)
      returning * into v_master;
    exception
      when unique_violation then
        -- Same defect class as app.create_employee_draft's own duplicate-number fix
        -- (this checkpoint's own review round): a row with an explicit, caller-supplied
        -- employee_number colliding with another row already committed in this job (or
        -- created outside it) previously raised a raw, unclassified unique_violation
        -- that aborted the WHOLE job, rolling back every already-created row. Treated
        -- instead as a per-row skip, consistent with the nested app.employees
        -- unique_violation handler immediately below.
        v_skipped_count := v_skipped_count + 1;
        continue;
    end;

    begin
      insert into app.employees (
        master_record_id, tenant_id, full_name, employment_type, intake_source,
        work_email, personal_email, personal_phone, company_org_unit_id, branch_org_unit_id, department_org_unit_id,
        position_title, source_import_staging_row_id, source_config_version_id, created_by
      )
      values (
        v_master.id, v_job.tenant_id, v_payload ->> 'full_name', coalesce(v_payload ->> 'employment_type', 'full_time'), 'bulk_import',
        nullif(v_payload ->> 'work_email', ''), nullif(v_payload ->> 'personal_email', ''), nullif(v_payload ->> 'personal_phone', ''),
        v_company_id, v_branch_id, v_department_id, nullif(v_payload ->> 'position_title', ''), v_row.id, v_config_version_id, p_actor_label
      )
      returning * into v_employee;
    exception
      when unique_violation then
        v_skipped_count := v_skipped_count + 1;
        continue;
    end;

    insert into app.employee_lifecycle_events (tenant_id, master_record_id, from_status, to_status, actor_auth_user_id, actor_label, metadata)
    values (v_job.tenant_id, v_employee.master_record_id, 'none', 'draft', p_actor_auth_user_id, p_actor_label, jsonb_build_object('source', 'bulk_import', 'job_id', p_job_id));

    v_created_count := v_created_count + 1;
  end loop;

  update app.jobs
  set status = 'completed', completed_at = now()
  where job_id = p_job_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'commit_employee_import_job',
    'app.jobs', p_job_id, 'success', null, to_jsonb(v_job),
    jsonb_build_object('created_count', v_created_count, 'skipped_count', v_skipped_count)
  );

  return v_updated;
end;
$$;

comment on function app.commit_employee_import_job is 'HRT-274 (decision 11): idempotent per staging row (source_import_staging_row_id is unique-when-set on app.employees, defended by a pre-check AND a nested unique_violation handler) and job-scoped-advisory-lock serialized, mirroring app.commit_vendor_rate_import_job (PRC-255) exactly. Every created row is a real draft employee -- submit/approve/activate remain separate, deliberate HR actions afterward, never auto-activated by import.';

-- ===========================================================================
-- 13. RLS -- default-deny form (pattern (3)): tenant membership AND NOT a
--     customer_user-layer principal, OR Supreme Admin. Employee data is HR-internal;
--     a customer_user-layer principal must never read it.
-- ===========================================================================

alter table app.employee_number_counters enable row level security;

create policy employee_number_counters_none on app.employee_number_counters
  for select to authenticated
  using (false);

comment on policy employee_number_counters_none on app.employee_number_counters is 'HRT-274: belt-and-suspenders deny-all -- this table carries no authenticated/anon grant at all (design note 12, ISS-2026-033''s own lesson), mirroring app.vendor_code_counters_none (PRC-251).';

alter table app.employees enable row level security;
alter table app.employee_emergency_contacts enable row level security;
alter table app.employee_lifecycle_events enable row level security;
alter table app.employee_duplicate_candidates enable row level security;
alter table app.employee_change_requests enable row level security;

create policy employees_select_scoped on app.employees
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy employee_emergency_contacts_select_scoped on app.employee_emergency_contacts
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy employee_lifecycle_events_select_scoped on app.employee_lifecycle_events
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy employee_duplicate_candidates_select_scoped on app.employee_duplicate_candidates
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy employee_change_requests_select_scoped on app.employee_change_requests
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

-- ===========================================================================
-- 14. Grants.
-- ===========================================================================

revoke execute on all functions in schema app from public;

-- app.employees / app.employee_emergency_contacts / app.employee_change_requests carry
-- classified pii columns (HRS_REGISTRY: national_id_number, date_of_birth, gender,
-- personal_address_*, personal_phone, personal_email; a named third party's phone/email
-- on emergency contacts; current_value_snapshot/requested_value on change requests,
-- which are ALWAYS a pii value since the field_key CHECK constraint only allows
-- personal_email/personal_phone/personal_address_* keys). The masking the RPC layer
-- performs (app.get_employee_profile/app.list_employee_emergency_contacts, gated on
-- app.has_view_personal_data) is a return-projection concern, not an access-control
-- one -- it does nothing to a RAW `select <col> from app.employees` issued directly
-- against the table by anyone holding the `authenticated` Postgres role (any real
-- Supabase JWT), since RLS filters ROWS, never COLUMNS. This checkpoint's own review
-- round found that gap live: a zero-HRS-permission tenant member's raw SELECT returned
-- real national_id_number/personal_email/personal_phone/date_of_birth values for every
-- employee in the tenant. Fixed the same way PLT-114 (app.users/app.users_directory,
-- 20260716110430) already established and proved for this EXACT defect shape:
-- REVOKE the table-level grant entirely and re-GRANT SELECT on an explicit column list
-- that omits every classified column -- a database guarantee `authenticated` cannot
-- read regardless of RLS, not merely an RPC-side convention. service_role (used
-- exclusively by this migration's own SECURITY DEFINER RPCs, which run under the
-- function owner's privileges and so are unaffected) keeps full, unrestricted SELECT.
grant select (
  master_record_id, tenant_id, user_id, full_name, employment_type, lifecycle_status, intake_source,
  work_email, work_phone, hire_date, probation_end_date, employment_end_date,
  company_org_unit_id, branch_org_unit_id, department_org_unit_id, position_title, manager_employee_id,
  revision_reason, suspend_reason, terminate_reason, archive_reason, leave_reason,
  source_import_staging_row_id, source_config_version_id, idempotency_key,
  record_version, created_by, created_at, updated_at
) on app.employees to authenticated;
grant select on app.employees to service_role;
grant insert, update, delete on app.employees to service_role;

grant select (
  id, tenant_id, master_record_id, name, relationship, is_primary, status, record_version, created_by, created_at, updated_at
) on app.employee_emergency_contacts to authenticated;
grant select on app.employee_emergency_contacts to service_role;
grant insert, update, delete on app.employee_emergency_contacts to service_role;

grant select on app.employee_lifecycle_events to authenticated, service_role;
grant insert on app.employee_lifecycle_events to service_role;
grant select on app.employee_duplicate_candidates to authenticated, service_role;
grant insert, update on app.employee_duplicate_candidates to service_role;

grant select (
  id, tenant_id, master_record_id, requested_by_user_id, field_key, reason, status,
  decided_by, decided_at, decided_reason, record_version, created_at, updated_at
) on app.employee_change_requests to authenticated;
grant select on app.employee_change_requests to service_role;
grant insert, update on app.employee_change_requests to service_role;
grant select, insert, update on app.employee_number_counters to service_role;

grant execute on function app.next_employee_number(uuid) to service_role;
grant execute on function app.assert_no_employee_manager_cycle(uuid, uuid) to service_role;
grant execute on function app.employee_audit_projection(app.employees) to service_role;
grant execute on function app.employee_emergency_contact_audit_projection(app.employee_emergency_contacts) to service_role;
grant execute on function app.assert_employee_draft_idempotent_replay(app.employees, text, text, text, text, text, text, text, date, text, date, uuid, uuid, uuid, text, uuid, uuid, text, text, text) to service_role;

grant execute on function app.create_employee_draft(uuid, text, text, text, text, text, text, date, text, date, uuid, uuid, uuid, text, uuid, uuid, text, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.update_employee_draft(uuid, integer, text, text, text, text, text, text, date, text, date, date, uuid, uuid, uuid, text, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.submit_employee_for_approval(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.decide_employee_approval(uuid, integer, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.activate_employee(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.link_employee_user(uuid, integer, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.start_employee_leave(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.end_employee_leave(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.suspend_employee(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.reactivate_employee(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.terminate_employee(uuid, integer, text, date, uuid, text) to authenticated, service_role;
grant execute on function app.archive_employee_profile(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.transfer_employee(uuid, integer, uuid, uuid, uuid, text, uuid, text, uuid, text) to authenticated, service_role;

grant execute on function app.add_employee_emergency_contact(uuid, text, text, text, text, boolean, uuid, text) to authenticated, service_role;
grant execute on function app.update_employee_emergency_contact(uuid, integer, text, text, text, text, boolean, uuid, text) to authenticated, service_role;
grant execute on function app.remove_employee_emergency_contact(uuid, integer, uuid, text) to authenticated, service_role;

grant execute on function app.flag_employee_duplicate_candidate(uuid, uuid, text, numeric, uuid, text) to authenticated, service_role;
grant execute on function app.decide_employee_duplicate_candidate(uuid, integer, text, text, uuid, text) to authenticated, service_role;

grant execute on function app.request_employee_change(uuid, text, text, text, uuid) to authenticated, service_role;
grant execute on function app.decide_employee_change_request(uuid, integer, text, text, uuid, text) to authenticated, service_role;

grant execute on function app.list_employees(uuid, uuid, text, uuid, text, integer, text) to authenticated, service_role;
grant execute on function app.get_employee_profile(uuid, uuid) to authenticated, service_role;
grant execute on function app.get_my_employee_profile(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_my_team_employees(uuid, uuid, integer, text) to authenticated, service_role;
grant execute on function app.get_employee_lifecycle_history(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_employee_emergency_contacts(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_employee_duplicate_candidates(uuid, uuid) to authenticated, service_role;
grant execute on function app.search_employee_duplicate_candidates(uuid, text, text, text, text, uuid, integer) to authenticated, service_role;
grant execute on function app.export_employees(uuid, uuid, text, integer) to authenticated, service_role;

-- app.validate_employee_import_row is service_role-only (mirrors app.validate_staging_
-- row / app.validate_vendor_rate_import_row exactly): it delegates its own authority
-- check to app.check_import_export_job_authority, which validates tenant membership
-- but never reaches app.evaluate_permission or app.assert_actor_is_session_identity --
-- ATW-032's own live rbac-enforcement.sql gate caught this directly (a real, run
-- assertion, not a documentation-only claim) and confirmed granting it to
-- `authenticated` would let a session claim another identity's p_actor_auth_user_id
-- with no identity cross-check anywhere in the call chain. The calling Server Action
-- uses the service-role Supabase client (lib/supabase/service-role.ts), matching
-- app/(tenant)/[tenantSlug]/procurement/vendors/[masterRecordId]/financial/actions.ts's
-- own established precedent for this exact function family.
grant execute on function app.validate_employee_import_row(uuid, uuid, text) to service_role;
grant execute on function app.commit_employee_import_job(uuid, boolean, uuid, text) to authenticated, service_role;
