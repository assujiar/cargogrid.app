-- Advanced TMS/WMS capability ATW-021 (CG-S10-ATW-021, Prompt 240, "Label and Barcode
-- Operations" -- docs/build-log/phase-05/ADVANCED_TMS_WMS_EXECUTION_INDEX.md §1).
-- Implements this prompt's own §4 objective verbatim: "secure, traceable label
-- generation, printing and scan resolution across warehouse tasks without treating a
-- barcode as authorization."
--
-- Direct upstream: ATW-230 (app.resolve_warehouse_location_by_barcode -- the literal
-- template for "a barcode resolves a candidate subject; it never itself authorizes
-- anything," generalized here from one subject (location) to seven), ATW-016
-- (app.item_control_policy_versions / app.publish_item_control_policy_version -- the
-- direct template for the governed draft->published->archived template-version
-- lifecycle, and app.actor_can_view_owner_scoped_row / app.resolve_actor_owner_account_
-- scope, reused verbatim, never re-derived), ATW-224 (the app.jobs job_type widening
-- mechanic), PLT-132 (the generic app.jobs queue and its claim/complete/fail
-- lifecycle), ATW-017/ATW-018 (app.wms_pick_tasks / app.wms_packages id shapes and
-- app.wms_pick_record_scope_ok, reused directly), ATW-011A (app.item_masters' own
-- tenant-wide, non-owner-scoped RLS shape, mirrored here for app.label_templates /
-- app.label_template_versions / app.label_printers).
--
-- Design boundary (disclosed):
--
-- 1. **Seven subject types, one shared dispatch, never seven bespoke record-scope
--    functions.** `app.label_subject_record_scope_ok()` is the single internal
--    predicate every RPC below that must reauthorize a labeled subject calls --
--    `app.print_label`/`app.reprint_label` (via the shared `app.execute_label_print`),
--    `app.void_label`, `app.get_label_instance`, and `app.resolve_label` all dispatch
--    through it, never duplicating the seven-way `case` a second time. It dispatches
--    exactly per subject_type: `bin` -> `app.warehouse_locations` (org-unit record
--    scope via `app.can_access_record`/`app.lead_record_scope_org_unit_ids`, no owner
--    dimension -- a bin has no owner_account_id); `item`/`lot`/`serial` ->
--    `app.item_masters`/`app.lot_identities`/`app.serial_identities` (all three tables
--    are tenant-wide, not warehouse-scoped -- `app.actor_can_view_owner_scoped_row`
--    alone is the real gate, RBAC already having confirmed OPS:View/Edit/Override
--    tenant-wide at the caller); `package`/`pallet` -> `app.wms_packages` (a pallet is
--    just a top-level package row, `parent_package_id is null` -- Prompt 240 names no
--    separate pallet table, and none exists downstream of ATW-018); `task` ->
--    `app.wms_pick_tasks`. Package/task both reuse `app.wms_pick_record_scope_ok`
--    directly (ATW-017's own SECURITY DEFINER helper), the identical predicate their
--    own RLS policies already use -- never re-derived a second way.
-- 2. **The scope check always re-reads the LIVE subject row, never the label's own
--    cached `owner_account_id`/`warehouse_id` columns.** Those two columns on
--    `app.label_instances` are audit/query-convenience denormalizations captured once
--    at generation time (so a list/read RPC does not need to join out to seven
--    different tables just to filter); the actual authorization decision inside
--    `app.label_subject_record_scope_ok` always looks the subject row up fresh. This
--    is the literal mechanism behind Prompt 240 §16's "every resolution reauthorizes
--    tenant/customer/warehouse/record access" -- a label generated while an actor held
--    access, scanned after that access was revoked (or the underlying subject's own
--    ownership changed), is re-evaluated against the CURRENT state, not the
--    generation-time snapshot.
-- 3. **Deliberately NOT granted to `authenticated`: `app.resolve_label_subject()` and
--    `app.execute_label_print()`.** `resolve_label_subject` returns a subject's real
--    `owner_account_id`/`warehouse_id` for ANY `subject_id` a caller supplies, with no
--    RBAC/record-scope gate of its own (that gate lives in its caller,
--    `app.generate_label`) -- granting it directly to `authenticated` would let any
--    tenant member use it as a cross-owner/cross-warehouse existence-and-ownership
--    oracle. `execute_label_print` is the shared print/reprint mutation core but
--    performs record-scope only, not the RBAC action-tier check (`OPS:Edit` for a
--    print, `OPS:Override` for a reprint) -- that check lives exclusively in its two
--    callers, `app.print_label`/`app.reprint_label`. Both remain fully usable from
--    every RPC in this migration (their SECURITY DEFINER owner always holds implicit
--    execute on its own functions regardless of PUBLIC/authenticated grants) -- only
--    direct client invocation is blocked. `app.compute_label_checksum_digit`,
--    `app.render_label_content`, and `app.label_subject_record_scope_ok` carry no such
--    risk (a pure digit/render function and a boolean predicate respectively, the
--    identical class `app.wms_pick_record_scope_ok`/`app.actor_can_view_owner_scoped_
--    row` already expose directly) and are granted normally.
-- 4. **The deterministic checksum/encoding algorithm is exactly the one this
--    checkpoint's own spec names, implemented once and reused at both ends.**
--    `app.compute_label_checksum_digit(p_core text)` is the one pure, IMMUTABLE
--    building block both `app.generate_label` (to mint a code) and `app.resolve_label`
--    (to verify a scanned code's own trailing digit BEFORE ever querying
--    `app.label_instances`) call -- a structurally malformed or forged code is
--    rejected (`rejection_reason='invalid_checksum'`, design note 12 below) without
--    ever touching the table, the concrete "unknown/duplicate/void/forged code"
--    exception-flow requirement (Prompt 240 §23).
-- 5. **A necessary, disclosed deviation from the literal column list this task's own
--    brief enumerated for `app.label_instances`: an `idempotency_key text not null`
--    column, with a real `unique (tenant_id, idempotency_key)` constraint, was added.**
--    The brief's own RPC behavior spec requires `app.generate_label` to be "Idempotent
--    on (tenant_id, idempotency_key)" but its own enumerated column list for
--    `app.label_instances` omitted the column that guarantee requires -- encoded_value
--    cannot serve as the idempotency key itself, since it is derived from a freshly
--    minted `gen_random_uuid()` (the label instance's own `id`), never reproducibly
--    from a caller-supplied key. This mirrors the exact, already-established
--    `app.serial_identities.idempotency_key` precedent (ATW-016 design note 3) -- a
--    real, separate unique constraint from the natural/business key.
-- 6. **A second, structurally necessary deviation: `app.label_print_jobs.app_job_id`
--    is nullable, not `not null`, at the actual table-DDL level**, despite the brief's
--    own column list naming it `not null references app.jobs (job_id)`. The brief's
--    own RPC behavior spec (item 9) explicitly requires inserting the
--    `label_print_jobs` row FIRST, then enqueuing the job (which needs that row's own
--    `id` in its payload), then UPDATE-ing `app_job_id` onto it in a second statement
--    -- a real chicken-and-egg `app.enqueue_job`/label_print_jobs.id circular
--    dependency, since `app.enqueue_job`'s own already-established signature (ATW-224,
--    never altered here beyond the additive `job_type` widening this migration also
--    performs) has no parameter to accept a caller-supplied job_id. A true `NOT NULL`
--    column cannot ever hold a NULL mid-transaction, even briefly, so the column is
--    declared nullable; both `app.print_label`/`app.reprint_label` (via
--    `app.execute_label_print`) always populate it via the immediate second UPDATE
--    inside the identical function invocation before returning -- no caller of either
--    RPC can ever observe a row with a null `app_job_id`, since the insert and the
--    update are the same atomic transaction (either both commit or neither does).
-- 7. **No live print worker/hardware exists in this repository** (disclosed, the first
--    such disclosure for this exact capability, matching the GPS Gateway's ATW-226D
--    precedent of "a real, callable interface with no live hardware behind it yet").
--    `app.print_label`/`app.reprint_label` enqueue a genuine `app.jobs` row (job_type
--    `print_label`) via the already-proven generic queue (PLT-132); `app.record_label_
--    print_outcome` is the one domain completion-sync helper a future worker calls
--    AFTER it has already called the generic `app.complete_job`/`app.record_job_
--    failure` -- this migration does not build a domain-specific claim loop, since
--    `app.claim_next_job` (PLT-132) already generically covers `job_type = 'print_
--    label'` the moment it is added to the valid-type list, with zero further code.
--    `app.label_print_jobs.rendered_payload` is the real, fully-substituted,
--    whitelist-only-rendered text artifact this checkpoint produces -- no PDF/ZPL
--    binary rendering and no Document/File Engine (PLT-128) integration exists yet
--    (`app.files.uploaded_by_auth_user_id` is `NOT NULL` with no system-actor path,
--    making it a poor fit for a job-generated artifact without first extending that
--    engine -- out of this task's own bounded scope, disclosed rather than silently
--    worked around).
-- 8. **`app.label_scan_events`' own RLS reads owner-scope through its associated
--    `app.label_instances` row, since the scan-event table itself carries no
--    `owner_account_id` column of its own** (by design -- a scan event's own real
--    identity is `encoded_value`/`resolved`/`rejection_reason`, and it must be
--    insertable even for a code that never resolved to any real row at all, e.g. an
--    `unknown_code`, at which point no owner exists to record). The policy predicate is
--    therefore `label_instance_id is null or <the linked instance's own owner-scope
--    check>` -- a null-instance scan event (never resolved) is visible tenant-wide,
--    exactly the same "no owner to narrow by" logic `app.label_instances` itself uses
--    for a `bin`-subject label.
-- 9. **`app.list_label_scan_events` is explicitly, disclosedly tenant-wide, not
--    owner-narrowed at the RPC layer** (Prompt 240's own brief item 21, applied
--    verbatim) -- this is a deliberate asymmetry from `app.list_label_instances`
--    (which IS owner-filtered): a scan-event row never exposes an expected/sensitive
--    business quantity, only scan metadata (encoded_value/resolved/rejection_reason/
--    timestamp/actor) for an OPS:View-holding staff actor auditing print/scan
--    activity across the whole tenant. The underlying table's own RLS (design note 8)
--    still narrows a raw SELECT for a customer_user-layer actor even though this
--    particular RPC does not -- disclosed, not silently inconsistent.
-- 10. **`search_path` on `app.generate_label` is `app, public, pg_temp`, not the usual
--     bare `app, pg_temp`** -- the identical, already-established `app.send_quotation_
--     for_acceptance`/`app.record_quotation_customer_decision` (ATW-... commercial
--     quotation acceptance) precedent: `pgcrypto` installs `digest()` into `public`,
--     and every table/function reference in this migration's own bodies is already
--     fully schema-qualified, so this is a real, narrower-than-default restriction,
--     not a regression of the `ERR-2026-004` discipline.
-- 11. Per `ERR-2026-004`: this migration carries its own explicit `REVOKE EXECUTE ON
--     ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement before its final grants.
-- 12. **`app.resolve_label` RETURNS a discriminated result for every ordinary,
--     expected rejection (invalid_checksum/unknown_code/void_code/insufficient_
--     authority), it does not RAISE for them** -- a real, proactively-found
--     correctness issue: PostgreSQL has no autonomous-transaction primitive available
--     in this repository, so an "INSERT the scan-event log row, then RAISE" sequence
--     does not actually persist that INSERT once the exception propagates (an
--     uncaught exception rolls back the whole statement; a caller's own BEGIN/
--     EXCEPTION block rolls back to its own savepoint just the same) -- which would
--     silently violate this checkpoint's own "every resolve attempt produces exactly
--     one label_scan_events row" acceptance criterion. This migration instead follows
--     the IDENTICAL, already-established precedent `app.resolve_gps_device_for_
--     handshake` (ATW-226D) already uses for the identical tension. See `app.resolve_
--     label`'s own function-level comment for the full ordering.
--
-- Residual scope (disclosed, matching every one of ATW-012 through ATW-020's own
-- identical boundary): NO UI this checkpoint -- no `app/` route, no REST/GraphQL
-- surface. Every RPC below is a direct Postgres function, callable only via the
-- Supabase RPC channel or this migration's own db-test.

-- === Widen the shared job queue for the one new domain job_type this task needs ===
-- (ATW-224's own established mechanic: DROP/ADD the CHECK constraint, then CREATE OR
-- REPLACE app.enqueue_job with the identical body, widening only its own
-- v_valid_job_types array literal. Base copied from the LAST migration that widened
-- it, supabase/migrations/20260729320000_create_advanced_tms_route_load_planning.sql,
-- unmodified beyond adding 'print_label' to both lists.)

alter table app.jobs drop constraint jobs_job_type_check;
alter table app.jobs add constraint jobs_job_type_check check (
  job_type in (
    'import', 'export', 'report_generation', 'notification_batch', 'webhook_retry',
    'document_generation', 'dashboard_refresh', 'loyalty_expiration', 'recurring_billing',
    'integration_sync', 'route_load_planning', 'print_label'
  )
);

create or replace function app.enqueue_job(
  p_tenant_id uuid,
  p_job_type text,
  p_payload jsonb,
  p_priority integer,
  p_idempotency_key text,
  p_max_attempts integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.jobs
language plpgsql
as $$
declare
  v_existing app.jobs;
  v_job app.jobs;
  v_valid_job_types text[] := array[
    'report_generation', 'notification_batch', 'webhook_retry', 'document_generation',
    'dashboard_refresh', 'loyalty_expiration', 'recurring_billing', 'integration_sync',
    'route_load_planning', 'print_label'
  ];
begin
  if not app.check_job_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'job_actor_unauthorized: identity % lacks active membership in tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_job_type in ('import', 'export') then
    raise exception 'job_type_requires_dedicated_entrypoint: % jobs must be created via app.create_import_export_job()', p_job_type
      using errcode = 'check_violation';
  end if;

  if not (p_job_type = any (v_valid_job_types)) then
    raise exception 'job_invalid_type: % is not a known generic job type', p_job_type
      using errcode = 'check_violation';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.jobs where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
    if found then
      return v_existing;
    end if;
  end if;

  if not app.validate_config_value(coalesce(p_payload, '{}'::jsonb)) then
    raise exception 'job_unsafe_payload: payload failed structural validation'
      using errcode = 'check_violation';
  end if;

  if coalesce(p_max_attempts, 3) <= 0 then
    raise exception 'job_invalid_max_attempts: max_attempts must be positive'
      using errcode = 'check_violation';
  end if;

  insert into app.jobs (
    tenant_id, job_type, payload, priority, max_attempts, idempotency_key,
    requested_by_auth_user_id, created_by
  ) values (
    p_tenant_id, p_job_type, coalesce(p_payload, '{}'::jsonb), coalesce(p_priority, 0), coalesce(p_max_attempts, 3), p_idempotency_key,
    p_actor_auth_user_id, p_actor_label
  )
  returning * into v_job;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'enqueue_job',
    'app.jobs', v_job.job_id, 'success', null, null,
    jsonb_build_object('job_id', v_job.job_id, 'job_type', v_job.job_type)
  );

  return v_job;
end;
$$;

-- === Schema ===

-- 1. Immutable identity header.
create table app.label_templates (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  code text not null,
  name text not null,
  subject_type text not null,
  created_by text,
  created_at timestamptz not null default now(),
  constraint label_templates_code_check check (length(trim(code)) > 0),
  constraint label_templates_name_check check (length(trim(name)) > 0),
  constraint label_templates_subject_type_check check (subject_type in ('bin', 'item', 'lot', 'serial', 'package', 'pallet', 'task')),
  constraint label_templates_code_unique unique (tenant_id, code)
);

comment on table app.label_templates is
  'ATW-021: an immutable identity header (code/subject_type never change once created -- no update RPC exists for this table, only new versions on app.label_template_versions). Mirrors app.item_masters'' own tenant-wide, non-owner-scoped RLS shape.';

create index label_templates_tenant_subject_idx on app.label_templates (tenant_id, subject_type);

-- 2. Governed, versioned content -- mirrors app.item_control_policy_versions (ATW-016) almost exactly.
create table app.label_template_versions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  template_id uuid not null references app.label_templates (id),
  version_number integer not null,
  content_template text not null,
  allowed_variables text[] not null default '{}'::text[],
  symbology text not null default 'code128',
  status text not null default 'draft',
  supersedes_version_id uuid references app.label_template_versions (id),
  effective_from timestamptz not null default now(),
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint label_template_versions_content_check check (length(trim(content_template)) > 0),
  constraint label_template_versions_version_number_check check (version_number > 0),
  constraint label_template_versions_symbology_check check (symbology in ('code128', 'code39', 'qr', 'datamatrix')),
  constraint label_template_versions_status_check check (status in ('draft', 'published', 'archived')),
  constraint label_template_versions_not_self_supersede check (supersedes_version_id is null or supersedes_version_id <> id),
  constraint label_template_versions_template_version_unique unique (template_id, version_number)
);

comment on table app.label_template_versions is
  'ATW-021: content_template is a plain string with {{variable_name}} placeholders (no templating-engine dependency); allowed_variables is the whitelist every placeholder in content_template must appear in (enforced at draft time by app.create_label_template_version_draft, unwhitelisted_template_variable otherwise -- fail as early as possible). At most one published version per template at a time (label_template_versions_template_published_unique, the identical partial-unique-index mechanism item_control_policy_versions_item_published_unique already established).';

create unique index label_template_versions_template_published_unique on app.label_template_versions (template_id) where status = 'published';
create index label_template_versions_tenant_template_idx on app.label_template_versions (tenant_id, template_id, status);

create function app.touch_label_template_versions_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger label_template_versions_touch_row
  before update on app.label_template_versions
  for each row
  execute function app.touch_label_template_versions_row();

-- 3. Printer administration.
create table app.label_printers (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  warehouse_id uuid references app.warehouses (id),
  code text not null,
  name text not null,
  connection_descriptor jsonb not null default '{}'::jsonb,
  status text not null default 'active',
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint label_printers_code_check check (length(trim(code)) > 0),
  constraint label_printers_name_check check (length(trim(name)) > 0),
  constraint label_printers_status_check check (status in ('active', 'inactive')),
  constraint label_printers_connection_descriptor_check check (app.validate_master_attributes(connection_descriptor)),
  constraint label_printers_code_unique unique (tenant_id, code)
);

comment on table app.label_printers is
  'ATW-021: warehouse_id is nullable -- a tenant-wide "virtual"/office printer is allowed. connection_descriptor is an opaque, disclosed-non-functional descriptor (e.g. {"type":"network","address":"..."}) -- never validated/connected to for real, structurally identical to the "no live hardware behind it yet" boundary this migration''s own header discloses.';

create index label_printers_tenant_warehouse_idx on app.label_printers (tenant_id, warehouse_id);

create function app.touch_label_printers_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger label_printers_touch_row
  before update on app.label_printers
  for each row
  execute function app.touch_label_printers_row();

-- 4. The encoded identifier + subject lineage -- created ONCE per logical label; print/
-- reprint are separate job events referencing the same instance, never creating a new
-- one. idempotency_key (design note 5, a disclosed necessary deviation from the
-- literal brief column list) and app_job_id-shaped columns on app.label_print_jobs
-- below (design note 6) are the two places this migration's own DDL diverges from the
-- brief's literal enumeration, both disclosed above.
create table app.label_instances (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  template_version_id uuid not null references app.label_template_versions (id),
  subject_type text not null,
  subject_id uuid not null,
  owner_account_id uuid references app.accounts (id),
  warehouse_id uuid references app.warehouses (id),
  encoded_value text not null,
  encoded_value_digest text not null,
  variables_snapshot jsonb not null default '{}'::jsonb,
  status text not null default 'active',
  void_reason text,
  voided_by_auth_user_id uuid references auth.users (id),
  voided_by_label text,
  voided_at timestamptz,
  idempotency_key text not null,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint label_instances_subject_type_check check (subject_type in ('bin', 'item', 'lot', 'serial', 'package', 'pallet', 'task')),
  constraint label_instances_status_check check (status in ('active', 'void')),
  constraint label_instances_void_shape_check check (
    (status = 'active' and void_reason is null and voided_by_auth_user_id is null and voided_by_label is null and voided_at is null)
    or (status = 'void' and void_reason is not null and voided_by_auth_user_id is not null and voided_by_label is not null and voided_at is not null)
  ),
  constraint label_instances_tenant_idempotency_unique unique (tenant_id, idempotency_key)
);

comment on table app.label_instances is
  'ATW-021: subject_id is a polymorphic reference with no live FK, exactly mirroring app.files'' record_type/record_id and app.event_logs'' resource_type/resource_id precedent. encoded_value uniqueness is enforced only among status=active rows (label_instances_tenant_encoded_value_active_unique) -- code possession grants no access regardless; that guarantee is enforced structurally by app.resolve_label''s own re-authorization, never by this index. owner_account_id/warehouse_id are audit/query-convenience denormalizations captured once at generation time -- NEVER the authorization source of truth (design note 2 above; app.label_subject_record_scope_ok always re-reads the live subject row).';

create unique index label_instances_tenant_encoded_value_active_unique on app.label_instances (tenant_id, encoded_value) where status = 'active';
create index label_instances_tenant_subject_idx on app.label_instances (tenant_id, subject_type, subject_id);
create index label_instances_owner_idx on app.label_instances (tenant_id, owner_account_id) where owner_account_id is not null;

create function app.touch_label_instances_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger label_instances_touch_row
  before update on app.label_instances
  for each row
  execute function app.touch_label_instances_row();

-- 5. One row per print or reprint attempt, linked to the shared app.jobs queue.
-- app_job_id is nullable (design note 6, a disclosed necessary deviation).
create table app.label_print_jobs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  label_instance_id uuid not null references app.label_instances (id),
  printer_id uuid not null references app.label_printers (id),
  app_job_id uuid references app.jobs (job_id),
  copies integer not null default 1,
  is_reprint boolean not null default false,
  reprint_reason text,
  rendered_payload text not null,
  status text not null default 'queued',
  outcome_error text,
  requested_by_auth_user_id uuid references auth.users (id),
  requested_by_label text,
  requested_at timestamptz not null default now(),
  completed_at timestamptz,
  idempotency_key text not null,
  record_version integer not null default 1,
  updated_at timestamptz not null default now(),
  constraint label_print_jobs_copies_check check (copies > 0),
  constraint label_print_jobs_status_check check (status in ('queued', 'succeeded', 'failed', 'cancelled')),
  constraint label_print_jobs_reprint_reason_check check (
    (is_reprint = false and reprint_reason is null)
    or (is_reprint = true and reprint_reason is not null and length(trim(reprint_reason)) > 0)
  ),
  constraint label_print_jobs_tenant_idempotency_unique unique (tenant_id, idempotency_key)
);

comment on table app.label_print_jobs is
  'ATW-021: status is synced from the underlying app.jobs row exclusively by app.record_label_print_outcome (a service_role-only worker callback), never read live off app.jobs by a client (design note 7 -- no live print worker/hardware exists yet). rendered_payload is the real, fully-substituted, whitelist-only-rendered text print artifact -- no PDF/ZPL binary rendering or Document/File Engine integration exists this checkpoint (disclosed).';

create index label_print_jobs_tenant_instance_idx on app.label_print_jobs (tenant_id, label_instance_id);
create index label_print_jobs_tenant_status_idx on app.label_print_jobs (tenant_id, status);

create function app.touch_label_print_jobs_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger label_print_jobs_touch_row
  before update on app.label_print_jobs
  for each row
  execute function app.touch_label_print_jobs_row();

-- 6. Append-only evidence of every scan attempt, resolved or rejected. No touch
-- trigger -- pure append-only, never updated.
create table app.label_scan_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  encoded_value text not null,
  label_instance_id uuid references app.label_instances (id),
  subject_type text,
  resolved boolean not null,
  rejection_reason text,
  scanned_by_auth_user_id uuid references auth.users (id),
  scanned_by_label text,
  scanned_at timestamptz not null default now(),
  constraint label_scan_events_rejection_reason_values_check check (
    rejection_reason is null or rejection_reason in ('invalid_checksum', 'unknown_code', 'void_code', 'insufficient_authority')
  ),
  constraint label_scan_events_resolved_shape_check check (
    (resolved = true and rejection_reason is null) or (resolved = false and rejection_reason is not null)
  )
);

comment on table app.label_scan_events is
  'ATW-021: append-only. label_instance_id is null whenever resolution failed before a row was found at all (malformed/forged checksum, or a genuinely unknown code) -- design note 8''s own RLS predicate reads owner-scope through this column when it is set.';

create index label_scan_events_tenant_idx on app.label_scan_events (tenant_id, scanned_at desc);
create index label_scan_events_label_instance_idx on app.label_scan_events (label_instance_id) where label_instance_id is not null;

-- === Shared internal building blocks ===

-- Pure, IMMUTABLE checksum digit -- design note 4. Called both by app.generate_label
-- (to mint a code) and app.resolve_label (to verify a scanned code's own trailing
-- digit before ever querying app.label_instances).
create function app.compute_label_checksum_digit(p_core text)
returns integer
language sql
immutable
as $$
  select (select sum(ascii(substr(p_core, i, 1))) from generate_series(1, length(p_core)) i)::integer % 10;
$$;

comment on function app.compute_label_checksum_digit is
  'ATW-021: sum of ASCII codes of every character in p_core, mod 10. Deterministic and independently verifiable both at generation and at every later scan -- see this migration''s own header for the full encoding algorithm.';

-- Whitelist-validated, injection-safe render -- shared by app.preview_label and
-- app.generate_label (never duplicated a second, divergent way). Every key in
-- p_variables not present in p_allowed_variables is rejected unsafe_variable; every
-- substituted value is escaped by replacing <, >, &, ", '' with their literal name in
-- brackets before substitution.
create function app.render_label_content(p_content_template text, p_allowed_variables text[], p_variables jsonb)
returns text
language plpgsql
stable
as $$
declare
  v_key text;
  v_value jsonb;
  v_rendered text := p_content_template;
  v_escaped text;
  v_allowed text[] := coalesce(p_allowed_variables, '{}'::text[]);
begin
  if p_variables is not null then
    for v_key, v_value in select * from jsonb_each(p_variables) loop
      if not (v_key = any (v_allowed)) then
        raise exception 'unsafe_variable: % is not a whitelisted variable for this template version', v_key using errcode = 'check_violation';
      end if;
      v_escaped := coalesce(v_value #>> '{}', '');
      v_escaped := replace(v_escaped, '&', '[amp]');
      v_escaped := replace(v_escaped, '<', '[lt]');
      v_escaped := replace(v_escaped, '>', '[gt]');
      v_escaped := replace(v_escaped, '"', '[quot]');
      v_escaped := replace(v_escaped, '''', '[apos]');
      v_rendered := replace(v_rendered, '{{' || v_key || '}}', v_escaped);
    end loop;
  end if;
  return v_rendered;
end;
$$;

comment on function app.render_label_content is
  'ATW-021: the one shared placeholder-substitution renderer app.preview_label and app.generate_label both call -- rejects any p_variables key not in p_allowed_variables (unsafe_variable) and escapes every substituted value (<,>,&,",'' -> [lt]/[gt]/[amp]/[quot]/[apos]) before substitution, since this content may later be embedded in an HTML print-preview surface even though no UI is built this checkpoint.';

-- Subject existence + owner/warehouse derivation -- used ONLY by app.generate_label
-- (design note 3: deliberately not granted to authenticated, since it has no RBAC/
-- record-scope gate of its own and would otherwise serve as a cross-owner existence
-- oracle).
create type app.label_subject_lookup as (
  found boolean,
  owner_account_id uuid,
  warehouse_id uuid
);

create function app.resolve_label_subject(p_tenant_id uuid, p_subject_type text, p_subject_id uuid)
returns app.label_subject_lookup
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_result app.label_subject_lookup;
  v_location app.warehouse_locations;
  v_item app.item_masters;
  v_lot app.lot_identities;
  v_serial app.serial_identities;
  v_package app.wms_packages;
  v_task app.wms_pick_tasks;
begin
  v_result.found := false;

  if p_subject_type = 'bin' then
    select * into v_location from app.warehouse_locations where id = p_subject_id and tenant_id = p_tenant_id;
    if found then
      v_result.found := true;
      v_result.warehouse_id := v_location.warehouse_id;
    end if;
  elsif p_subject_type = 'item' then
    select * into v_item from app.item_masters where id = p_subject_id and tenant_id = p_tenant_id;
    if found then
      v_result.found := true;
      v_result.owner_account_id := v_item.owner_account_id;
    end if;
  elsif p_subject_type = 'lot' then
    select * into v_lot from app.lot_identities where id = p_subject_id and tenant_id = p_tenant_id;
    if found then
      v_result.found := true;
      v_result.owner_account_id := v_lot.owner_account_id;
    end if;
  elsif p_subject_type = 'serial' then
    select * into v_serial from app.serial_identities where id = p_subject_id and tenant_id = p_tenant_id;
    if found then
      v_result.found := true;
      v_result.owner_account_id := v_serial.owner_account_id;
    end if;
  elsif p_subject_type in ('package', 'pallet') then
    select * into v_package from app.wms_packages where id = p_subject_id and tenant_id = p_tenant_id;
    if found then
      v_result.found := true;
      v_result.owner_account_id := v_package.owner_account_id;
      v_result.warehouse_id := v_package.warehouse_id;
    end if;
  elsif p_subject_type = 'task' then
    select * into v_task from app.wms_pick_tasks where id = p_subject_id and tenant_id = p_tenant_id;
    if found then
      v_result.found := true;
      v_result.owner_account_id := v_task.owner_account_id;
      v_result.warehouse_id := v_task.warehouse_id;
    end if;
  end if;

  return v_result;
end;
$$;

comment on function app.resolve_label_subject is
  'ATW-021: real, tenant-scoped subject existence + owner/warehouse derivation for app.generate_label. Deliberately NOT granted to authenticated (design note 3) -- carries no RBAC/record-scope gate of its own.';

-- The single record-scope predicate every RPC that must reauthorize a labeled subject
-- shares (design note 1/2). Always re-reads the LIVE subject row.
create function app.label_subject_record_scope_ok(
  p_actor_auth_user_id uuid,
  p_tenant_id uuid,
  p_subject_type text,
  p_subject_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_location app.warehouse_locations;
  v_warehouse app.warehouses;
  v_item app.item_masters;
  v_lot app.lot_identities;
  v_serial app.serial_identities;
  v_package app.wms_packages;
  v_task app.wms_pick_tasks;
begin
  if p_subject_type = 'bin' then
    select * into v_location from app.warehouse_locations where id = p_subject_id and tenant_id = p_tenant_id;
    if not found then
      return false;
    end if;
    select * into v_warehouse from app.warehouses where id = v_location.warehouse_id;
    return app.can_access_record(p_actor_auth_user_id, p_tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null);
  elsif p_subject_type = 'item' then
    select * into v_item from app.item_masters where id = p_subject_id and tenant_id = p_tenant_id;
    if not found then
      return false;
    end if;
    return app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, p_tenant_id, v_item.owner_account_id);
  elsif p_subject_type = 'lot' then
    select * into v_lot from app.lot_identities where id = p_subject_id and tenant_id = p_tenant_id;
    if not found then
      return false;
    end if;
    return app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, p_tenant_id, v_lot.owner_account_id);
  elsif p_subject_type = 'serial' then
    select * into v_serial from app.serial_identities where id = p_subject_id and tenant_id = p_tenant_id;
    if not found then
      return false;
    end if;
    return app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, p_tenant_id, v_serial.owner_account_id);
  elsif p_subject_type in ('package', 'pallet') then
    select * into v_package from app.wms_packages where id = p_subject_id and tenant_id = p_tenant_id;
    if not found then
      return false;
    end if;
    return app.wms_pick_record_scope_ok(p_actor_auth_user_id, v_package.warehouse_id, v_package.owner_account_id::text)
      and app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, p_tenant_id, v_package.owner_account_id);
  elsif p_subject_type = 'task' then
    select * into v_task from app.wms_pick_tasks where id = p_subject_id and tenant_id = p_tenant_id;
    if not found then
      return false;
    end if;
    return app.wms_pick_record_scope_ok(p_actor_auth_user_id, v_task.warehouse_id, v_task.owner_account_id::text)
      and app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, p_tenant_id, v_task.owner_account_id);
  else
    return false;
  end if;
end;
$$;

comment on function app.label_subject_record_scope_ok is
  'ATW-021: the one shared record-scope dispatch app.print_label/app.reprint_label (via app.execute_label_print)/app.void_label/app.get_label_instance/app.resolve_label all call -- always re-reads the LIVE subject row (design note 2), never the label''s own cached owner_account_id/warehouse_id.';

-- === Template/version lifecycle ===

create function app.create_label_template(
  p_tenant_id uuid,
  p_code text,
  p_name text,
  p_subject_type text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.label_templates
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_template app.label_templates;
begin
  if p_code is null or length(trim(p_code)) = 0 then
    raise exception 'invalid_code: code is required' using errcode = 'check_violation';
  end if;
  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'invalid_name: name is required' using errcode = 'check_violation';
  end if;
  if p_subject_type not in ('bin', 'item', 'lot', 'serial', 'package', 'pallet', 'task') then
    raise exception 'invalid_subject_type: % is not a valid subject type', p_subject_type using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_template from app.label_templates where tenant_id = p_tenant_id and code = p_code;
  if found then
    if v_template.subject_type <> p_subject_type or v_template.name <> p_name then
      raise exception 'label_template_code_conflict: code % already exists for tenant % with a different name/subject_type', p_code, p_tenant_id
        using errcode = 'unique_violation';
    end if;
    return v_template;
  end if;

  begin
    insert into app.label_templates (tenant_id, code, name, subject_type, created_by)
    values (p_tenant_id, p_code, p_name, p_subject_type, p_actor_label)
    returning * into v_template;
  exception
    when unique_violation then
      select * into v_template from app.label_templates where tenant_id = p_tenant_id and code = p_code;
      if found then
        return v_template;
      end if;
      raise;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_label_template',
    'app.label_templates', v_template.id, 'success', null, null,
    jsonb_build_object('code', p_code, 'subject_type', p_subject_type)
  );

  return v_template;
end;
$$;

comment on function app.create_label_template is
  'ATW-021: idempotent on (tenant_id, code). code/subject_type are immutable once created -- no update RPC exists for this table.';

create function app.create_label_template_version_draft(
  p_template_id uuid,
  p_content_template text,
  p_allowed_variables text[],
  p_symbology text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.label_template_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_template app.label_templates;
  v_version app.label_template_versions;
  v_symbology text;
  v_allowed text[];
  v_match text[];
  v_var text;
  v_next_version integer;
begin
  select * into v_template from app.label_templates where id = p_template_id;
  if not found then
    raise exception 'label_template_not_found: %', p_template_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_template.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_template.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_content_template is null or length(trim(p_content_template)) = 0 then
    raise exception 'invalid_content_template: content_template is required' using errcode = 'check_violation';
  end if;
  v_symbology := coalesce(p_symbology, 'code128');
  if v_symbology not in ('code128', 'code39', 'qr', 'datamatrix') then
    raise exception 'invalid_symbology: % is not a recognized symbology', v_symbology using errcode = 'check_violation';
  end if;
  v_allowed := coalesce(p_allowed_variables, '{}'::text[]);

  -- Fail as early as possible (design note in table 2's own comment): every {{name}}
  -- placeholder in content_template must already be whitelisted at DRAFT time, never
  -- deferred to generate/preview time.
  for v_match in select regexp_matches(p_content_template, '\{\{([a-zA-Z0-9_]+)\}\}', 'g') loop
    v_var := v_match[1];
    if not (v_var = any (v_allowed)) then
      raise exception 'unwhitelisted_template_variable: % is used in content_template but is not present in allowed_variables', v_var
        using errcode = 'check_violation';
    end if;
  end loop;

  select coalesce(max(version_number), 0) + 1 into v_next_version from app.label_template_versions where template_id = p_template_id;

  insert into app.label_template_versions (
    tenant_id, template_id, version_number, content_template, allowed_variables, symbology, created_by
  ) values (
    v_template.tenant_id, p_template_id, v_next_version, p_content_template, v_allowed, v_symbology, p_actor_label
  )
  returning * into v_version;

  perform app.capture_audit_event(
    v_template.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_label_template_version_draft',
    'app.label_template_versions', v_version.id, 'success', null, null,
    jsonb_build_object('template_id', p_template_id, 'version_number', v_version.version_number)
  );

  return v_version;
end;
$$;

comment on function app.create_label_template_version_draft is
  'ATW-021: rejects unwhitelisted_template_variable at DRAFT time (fail as early as possible), never deferred to generate/preview time.';

create function app.publish_label_template_version(
  p_version_id uuid,
  p_expected_version integer,
  p_supersedes_version_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.label_template_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_version app.label_template_versions;
  v_superseded app.label_template_versions;
begin
  select * into v_version from app.label_template_versions where id = p_version_id;
  if not found then
    raise exception 'label_template_version_not_found: %', p_version_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_version.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_version.record_version <> p_expected_version then
    raise exception 'stale_version: label template version % expected version % but found %', p_version_id, p_expected_version, v_version.record_version
      using errcode = 'check_violation';
  end if;
  if v_version.status <> 'draft' then
    raise exception 'invalid_transition: label template version % is % and cannot be published', p_version_id, v_version.status using errcode = 'check_violation';
  end if;

  if p_supersedes_version_id is not null then
    -- `for update` (findings review LOW #7): locks the row between this read and the
    -- archive UPDATE below so a concurrent modification cannot slip in between them.
    select * into v_superseded from app.label_template_versions where id = p_supersedes_version_id for update;
    if not found then
      raise exception 'superseded_version_not_found: %', p_supersedes_version_id using errcode = 'no_data_found';
    end if;
    if v_superseded.template_id <> v_version.template_id then
      raise exception 'invalid_supersede: superseded version must share the same template_id' using errcode = 'check_violation';
    end if;
    if v_superseded.status <> 'published' then
      raise exception 'invalid_supersede: superseded version % is % (must be published)', p_supersedes_version_id, v_superseded.status using errcode = 'check_violation';
    end if;
    update app.label_template_versions set status = 'archived' where id = p_supersedes_version_id and status = 'published';
  end if;

  begin
    update app.label_template_versions
    set status = 'published', supersedes_version_id = p_supersedes_version_id
    where id = p_version_id and record_version = p_expected_version
    returning * into v_version;
  exception
    when unique_violation then
      raise exception 'active_template_version_exists: template % already has a published version -- supply p_supersedes_version_id to replace it', v_version.template_id
        using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_label_template_version',
    'app.label_template_versions', v_version.id, 'success', null, null, jsonb_build_object('supersedes_version_id', p_supersedes_version_id)
  );

  return v_version;
end;
$$;

comment on function app.publish_label_template_version is
  'ATW-021: draft -> published, archiving p_supersedes_version_id first so at most one published version ever exists per template (label_template_versions_template_published_unique). Mirrors app.publish_item_control_policy_version (ATW-016) almost exactly.';

create function app.set_label_template_version_status(
  p_version_id uuid,
  p_new_status text,
  p_reason text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.label_template_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_version app.label_template_versions;
begin
  if p_new_status <> 'archived' then
    raise exception 'invalid_status_transition: this function only supports transitioning to archived -- use app.create_label_template_version_draft/app.publish_label_template_version for draft/published'
      using errcode = 'check_violation';
  end if;

  select * into v_version from app.label_template_versions where id = p_version_id for update;
  if not found then
    raise exception 'label_template_version_not_found: %', p_version_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_version.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_version.status = 'archived' then
    return v_version;
  end if;

  if v_version.record_version <> p_expected_version then
    raise exception 'stale_version: label template version % expected version % but found %', p_version_id, p_expected_version, v_version.record_version
      using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to archive a label template version' using errcode = 'check_violation';
  end if;

  update app.label_template_versions set status = 'archived' where id = p_version_id returning * into v_version;

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_label_template_version_status',
    'app.label_template_versions', v_version.id, 'success', p_reason, null, jsonb_build_object('new_status', 'archived')
  );

  return v_version;
end;
$$;

comment on function app.set_label_template_version_status is
  'ATW-021: the archive path only (draft->archived or published->archived) -- rejects transitioning into draft/published via this generic function (those have their own dedicated RPCs above).';

-- === Printer administration ===

create function app.create_label_printer(
  p_tenant_id uuid,
  p_warehouse_id uuid,
  p_code text,
  p_name text,
  p_connection_descriptor jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.label_printers
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_warehouse app.warehouses;
  v_printer app.label_printers;
begin
  if p_code is null or length(trim(p_code)) = 0 then
    raise exception 'invalid_code: code is required' using errcode = 'check_violation';
  end if;
  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'invalid_name: name is required' using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_warehouse_id is not null then
    select * into v_warehouse from app.warehouses where id = p_warehouse_id and tenant_id = p_tenant_id;
    if not found then
      raise exception 'warehouse_not_found: %', p_warehouse_id using errcode = 'no_data_found';
    end if;
    if not app.can_access_record(p_actor_auth_user_id, p_tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
      raise exception 'insufficient_authority: identity % cannot create a printer under warehouse %', p_actor_auth_user_id, p_warehouse_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  if not app.validate_master_attributes(coalesce(p_connection_descriptor, '{}'::jsonb)) then
    raise exception 'invalid_connection_descriptor: connection_descriptor failed structural validation' using errcode = 'check_violation';
  end if;

  select * into v_printer from app.label_printers where tenant_id = p_tenant_id and code = p_code;
  if found then
    if v_printer.warehouse_id is distinct from p_warehouse_id or v_printer.name <> p_name or v_printer.connection_descriptor is distinct from coalesce(p_connection_descriptor, '{}'::jsonb) then
      raise exception 'label_printer_code_conflict: code % already exists for tenant % with a different warehouse/name/connection_descriptor', p_code, p_tenant_id
        using errcode = 'unique_violation';
    end if;
    return v_printer;
  end if;

  begin
    insert into app.label_printers (tenant_id, warehouse_id, code, name, connection_descriptor, created_by)
    values (p_tenant_id, p_warehouse_id, p_code, p_name, coalesce(p_connection_descriptor, '{}'::jsonb), p_actor_label)
    returning * into v_printer;
  exception
    when unique_violation then
      select * into v_printer from app.label_printers where tenant_id = p_tenant_id and code = p_code;
      if found then
        if v_printer.warehouse_id is distinct from p_warehouse_id or v_printer.name <> p_name or v_printer.connection_descriptor is distinct from coalesce(p_connection_descriptor, '{}'::jsonb) then
          raise exception 'label_printer_code_conflict: code % already exists for tenant % with a different warehouse/name/connection_descriptor', p_code, p_tenant_id
            using errcode = 'unique_violation';
        end if;
        return v_printer;
      end if;
      raise;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_label_printer',
    'app.label_printers', v_printer.id, 'success', null, null, jsonb_build_object('code', p_code, 'warehouse_id', p_warehouse_id)
  );

  return v_printer;
end;
$$;

comment on function app.create_label_printer is
  'ATW-021: idempotent on (tenant_id, code). warehouse_id, when given, must belong to the same tenant -- a null warehouse_id is a tenant-wide "virtual"/office printer. A code match against a DIFFERENT warehouse_id/name/connection_descriptor raises label_printer_code_conflict rather than silently returning the existing, mismatched printer (findings review MEDIUM #6), mirroring app.create_label_template''s own equivalent check.';

create function app.set_label_printer_status(
  p_printer_id uuid,
  p_new_status text,
  p_reason text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.label_printers
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_printer app.label_printers;
begin
  if p_new_status not in ('active', 'inactive') then
    raise exception 'invalid_status: % is not a valid printer status', p_new_status using errcode = 'check_violation';
  end if;

  select * into v_printer from app.label_printers where id = p_printer_id for update;
  if not found then
    raise exception 'label_printer_not_found: %', p_printer_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_printer.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_printer.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_printer.status = p_new_status then
    return v_printer;
  end if;

  if v_printer.record_version <> p_expected_version then
    raise exception 'stale_version: label printer % expected version % but found %', p_printer_id, p_expected_version, v_printer.record_version
      using errcode = 'check_violation';
  end if;
  if p_new_status = 'inactive' and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'reason_required: a non-empty reason is required to deactivate a printer' using errcode = 'check_violation';
  end if;

  update app.label_printers set status = p_new_status where id = p_printer_id returning * into v_printer;

  perform app.capture_audit_event(
    v_printer.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_label_printer_status',
    'app.label_printers', v_printer.id, 'success', p_reason, null, jsonb_build_object('new_status', p_new_status)
  );

  return v_printer;
end;
$$;

-- === Label generation, preview, print, reprint, void ===

create function app.preview_label(
  p_template_version_id uuid,
  p_variables jsonb,
  p_actor_auth_user_id uuid
)
returns text
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_version app.label_template_versions;
begin
  select * into v_version from app.label_template_versions where id = p_template_version_id;
  if not found then
    raise exception 'label_template_version_not_found: %', p_template_version_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_version.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return app.render_label_content(v_version.content_template, v_version.allowed_variables, coalesce(p_variables, '{}'::jsonb));
end;
$$;

comment on function app.preview_label is
  'ATW-021: STABLE, no insert of any kind, pure render -- creates no row. Shares app.render_label_content with app.generate_label (never duplicated a second, divergent way).';

create function app.generate_label(
  p_tenant_id uuid,
  p_template_code text,
  p_subject_type text,
  p_subject_id uuid,
  p_variables jsonb,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.label_instances
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_template app.label_templates;
  v_version app.label_template_versions;
  v_existing app.label_instances;
  v_subject app.label_subject_lookup;
  v_new_id uuid;
  v_core text;
  v_core_short text;
  v_checksum integer;
  v_encoded text;
  v_instance app.label_instances;
  v_attempt integer := 0;
begin
  if p_subject_type not in ('bin', 'item', 'lot', 'serial', 'package', 'pallet', 'task') then
    raise exception 'invalid_subject_type: % is not a valid subject type', p_subject_type using errcode = 'check_violation';
  end if;

  select * into v_template from app.label_templates where tenant_id = p_tenant_id and code = p_template_code;
  if not found then
    raise exception 'label_template_not_found: no template % for tenant %', p_template_code, p_tenant_id using errcode = 'no_data_found';
  end if;

  -- OPS:Create tenant-wide is the FIRST authority gate here -- generate_label is a
  -- staff-only action (Prompt 240 §26: "warehouse staff print task labels ... customer
  -- users resolve only permitted subjects" -- generation is never in the customer-
  -- facing set at all). A second, per-subject app.label_subject_record_scope_ok gate
  -- is ALSO enforced below, once the subject is confirmed to exist (findings review
  -- HIGH #2): calling it only after subject_not_found is already ruled out means it
  -- can never mask a real subject_not_found behind a misleading insufficient_authority,
  -- and costs no extra existence lookup -- app.resolve_label_subject has already
  -- proven the row is there.
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required to generate a label' using errcode = 'check_violation';
  end if;

  -- Idempotent replay -- only after authority is confirmed above, never before. A key
  -- match against a DIFFERENT subject is a conflict, never a silent wrong-subject
  -- return (findings review CRITICAL #1/#3/#8 -- the exact ATW-020 bug class this
  -- migration's own header cites as convention baseline).
  select * into v_existing from app.label_instances where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.subject_type <> p_subject_type or v_existing.subject_id <> p_subject_id then
      raise exception 'idempotency_key_conflict: idempotency key % was already used by a different subject (% %, not % %)', p_idempotency_key, v_existing.subject_type, v_existing.subject_id, p_subject_type, p_subject_id
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  if v_template.subject_type <> p_subject_type then
    raise exception 'subject_type_mismatch: template % is scoped to % but % was requested', p_template_code, v_template.subject_type, p_subject_type
      using errcode = 'check_violation';
  end if;

  select * into v_version from app.label_template_versions where template_id = v_template.id and status = 'published' and effective_from <= now();
  if not found then
    raise exception 'stale_template: template % has no currently published version', p_template_code using errcode = 'check_violation';
  end if;

  v_subject := app.resolve_label_subject(p_tenant_id, p_subject_type, p_subject_id);
  if not v_subject.found then
    raise exception 'subject_not_found: no % % for tenant %', p_subject_type, p_subject_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  if not app.label_subject_record_scope_ok(p_actor_auth_user_id, p_tenant_id, p_subject_type, p_subject_id) then
    raise exception 'insufficient_authority: identity % cannot generate a label for % %', p_actor_auth_user_id, p_subject_type, p_subject_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Validates/escapes/renders identically to app.preview_label (shared function,
  -- design note in app.render_label_content's own comment) -- defense in depth: an
  -- unwhitelisted variable is rejected here even if it somehow bypassed draft-time
  -- validation. The rendered string itself is not persisted on app.label_instances --
  -- app.print_label/app.reprint_label re-render from template_version_id +
  -- variables_snapshot at print time, guaranteeing preview/print always agree.
  perform app.render_label_content(v_version.content_template, v_version.allowed_variables, coalesce(p_variables, '{}'::jsonb));

  loop
    v_attempt := v_attempt + 1;
    v_new_id := gen_random_uuid();
    v_core := upper(replace(v_new_id::text, '-', ''));
    v_core_short := left(v_core, 12);
    v_checksum := app.compute_label_checksum_digit(v_core_short);
    v_encoded := upper(left(p_subject_type, 3)) || '-' || v_core_short || '-' || v_checksum::text;

    begin
      insert into app.label_instances (
        id, tenant_id, template_version_id, subject_type, subject_id, owner_account_id, warehouse_id,
        encoded_value, encoded_value_digest, variables_snapshot, idempotency_key, created_by
      ) values (
        v_new_id, p_tenant_id, v_version.id, p_subject_type, p_subject_id, v_subject.owner_account_id, v_subject.warehouse_id,
        v_encoded, encode(digest(v_encoded, 'sha256'), 'hex'), coalesce(p_variables, '{}'::jsonb), p_idempotency_key, p_actor_label
      )
      returning * into v_instance;
      exit;
    exception
      when unique_violation then
        select * into v_instance from app.label_instances where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
        if found then
          -- A genuinely concurrent request under the SAME idempotency key raced us here
          -- -- but it must be for the SAME subject, never silently handed back to a
          -- caller whose real target was a different subject entirely (findings review
          -- CRITICAL #1/#3/#8).
          if v_instance.subject_type <> p_subject_type or v_instance.subject_id <> p_subject_id then
            raise exception 'idempotency_key_conflict: idempotency key % was already used by a different subject (% %, not % %)', p_idempotency_key, v_instance.subject_type, v_instance.subject_id, p_subject_type, p_subject_id
              using errcode = 'unique_violation';
          end if;
          return v_instance;
        end if;
        -- A genuine encoded_value collision (astronomically unlikely) -- retry with a
        -- freshly minted id/encoded_value, the same defensive pattern every other
        -- create-once insert in this repository uses.
        if v_attempt >= 5 then
          raise;
        end if;
    end;
  end loop;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'generate_label',
    'app.label_instances', v_instance.id, 'success', null, null,
    jsonb_build_object('template_code', p_template_code, 'subject_type', p_subject_type, 'subject_id', p_subject_id, 'encoded_value', v_instance.encoded_value)
  );

  return v_instance;
end;
$$;

comment on function app.generate_label is
  'ATW-021: resolves the template by code, then its own currently-published version (stale_template if none published); rejects subject_type mismatch; dispatches on p_subject_type to confirm the subject exists and derive owner_account_id/warehouse_id from the LIVE subject row (never a caller-supplied value) -- subject_not_found otherwise. Reauthorizes the specific subject via app.label_subject_record_scope_ok once its existence is confirmed (findings review HIGH #2) -- insufficient_authority for an out-of-scope subject. Idempotent on (tenant_id, idempotency_key), rejecting idempotency_key_conflict when the key was already used for a different subject (findings review CRITICAL #1/#3/#8) -- never silently returns the wrong subject''s label. encoded_value is computed per this migration''s own header algorithm from the label instance''s OWN freshly minted id, never the subject''s id.';

create function app.execute_label_print(
  p_label_instance_id uuid,
  p_printer_id uuid,
  p_copies integer,
  p_is_reprint boolean,
  p_reprint_reason text,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.label_print_jobs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_label app.label_instances;
  v_printer app.label_printers;
  v_version app.label_template_versions;
  v_existing app.label_print_jobs;
  v_job app.label_print_jobs;
  v_app_job app.jobs;
  v_rendered text;
begin
  select * into v_label from app.label_instances where id = p_label_instance_id for update;
  if not found then
    raise exception 'label_instance_not_found: %', p_label_instance_id using errcode = 'no_data_found';
  end if;

  if not app.label_subject_record_scope_ok(p_actor_auth_user_id, v_label.tenant_id, v_label.subject_type, v_label.subject_id) then
    raise exception 'insufficient_authority: identity % cannot % label %', p_actor_auth_user_id, (case when p_is_reprint then 'reprint' else 'print' end), p_label_instance_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required to print a label' using errcode = 'check_violation';
  end if;

  -- Idempotent replay -- only after authority is confirmed above, never before. A key
  -- match against a DIFFERENT label instance/printer/reprint-flag is a conflict, never
  -- a silent wrong-job return (findings review CRITICAL #1/#4/#9): the caller believes
  -- their own real target was queued when it never was.
  select * into v_existing from app.label_print_jobs where tenant_id = v_label.tenant_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.label_instance_id <> p_label_instance_id or v_existing.printer_id <> p_printer_id or v_existing.is_reprint <> p_is_reprint then
      raise exception 'idempotency_key_conflict: idempotency key % was already used by a different print/reprint request (label % printer % is_reprint %, not label % printer % is_reprint %)',
        p_idempotency_key, v_existing.label_instance_id, v_existing.printer_id, v_existing.is_reprint, p_label_instance_id, p_printer_id, p_is_reprint
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  if p_is_reprint and (p_reprint_reason is null or length(trim(p_reprint_reason)) = 0) then
    raise exception 'reason_required: a non-empty reason is required to reprint a label' using errcode = 'check_violation';
  end if;

  select * into v_printer from app.label_printers where id = p_printer_id;
  if not found or v_printer.tenant_id <> v_label.tenant_id then
    raise exception 'label_printer_not_found: %', p_printer_id using errcode = 'no_data_found';
  end if;
  if v_label.status = 'void' then
    raise exception 'label_voided: label instance % is void', p_label_instance_id using errcode = 'check_violation';
  end if;
  if v_printer.status <> 'active' then
    raise exception 'printer_inactive: printer % is not active', p_printer_id using errcode = 'check_violation';
  end if;
  if coalesce(p_copies, 1) <= 0 then
    raise exception 'invalid_copies: copies must be positive' using errcode = 'check_violation';
  end if;

  select * into v_version from app.label_template_versions where id = v_label.template_version_id;
  v_rendered := app.render_label_content(v_version.content_template, v_version.allowed_variables, v_label.variables_snapshot);

  -- Wrapped like every other create-once insert in this migration (app.generate_
  -- label's own retry loop, app.create_label_template, app.create_label_printer):
  -- two genuinely concurrent calls sharing an idempotency key but targeting DIFFERENT
  -- label_instance_id rows do not serialize on the `for update` lock taken above (that
  -- lock is per-label-instance-row), so both can pass the idempotent-replay check
  -- before either commits (findings review HIGH #5/#10). Without this handler the
  -- loser's raw INSERT would raise an unhandled unique_violation straight to the
  -- client instead of resolving idempotently or rejecting cleanly.
  begin
    insert into app.label_print_jobs (
      tenant_id, label_instance_id, printer_id, copies, is_reprint, reprint_reason,
      rendered_payload, requested_by_auth_user_id, requested_by_label, idempotency_key
    ) values (
      v_label.tenant_id, p_label_instance_id, p_printer_id, coalesce(p_copies, 1), p_is_reprint,
      (case when p_is_reprint then p_reprint_reason else null end), v_rendered, p_actor_auth_user_id, p_actor_label, p_idempotency_key
    )
    returning * into v_job;
  exception
    when unique_violation then
      select * into v_job from app.label_print_jobs where tenant_id = v_label.tenant_id and idempotency_key = p_idempotency_key;
      if not found then
        raise;
      end if;
      if v_job.label_instance_id <> p_label_instance_id or v_job.printer_id <> p_printer_id or v_job.is_reprint <> p_is_reprint then
        raise exception 'idempotency_key_conflict: idempotency key % was already used by a different, concurrent print/reprint request (label % printer % is_reprint %, not label % printer % is_reprint %)',
          p_idempotency_key, v_job.label_instance_id, v_job.printer_id, v_job.is_reprint, p_label_instance_id, p_printer_id, p_is_reprint
          using errcode = 'unique_violation';
      end if;
      return v_job;
  end;

  v_app_job := app.enqueue_job(
    v_label.tenant_id, 'print_label',
    jsonb_build_object('label_print_job_id', v_job.id, 'label_instance_id', p_label_instance_id, 'printer_id', p_printer_id, 'copies', v_job.copies, 'is_reprint', p_is_reprint),
    0, 'label-print-job-' || v_job.id::text, 3, p_actor_auth_user_id, p_actor_label
  );

  update app.label_print_jobs set app_job_id = v_app_job.job_id where id = v_job.id returning * into v_job;

  perform app.capture_audit_event(
    v_label.tenant_id, p_actor_auth_user_id, p_actor_label, (case when p_is_reprint then 'reprint_label' else 'print_label' end),
    'app.label_print_jobs', v_job.id, 'success', p_reprint_reason, null,
    jsonb_build_object('label_instance_id', p_label_instance_id, 'printer_id', p_printer_id, 'app_job_id', v_app_job.job_id, 'is_reprint', p_is_reprint)
  );

  return v_job;
end;
$$;

comment on function app.execute_label_print is
  'ATW-021: the shared print/reprint mutation core app.print_label/app.reprint_label both call -- record-scope only, NOT the RBAC action-tier check (that lives exclusively in its two callers). Deliberately NOT granted to authenticated (design note 3). Inserts the label_print_jobs row first, then enqueues the app.jobs row (whose payload needs the print job''s own id), then UPDATEs app_job_id onto it -- all inside one atomic invocation (design note 6). Idempotent on (tenant_id, idempotency_key), rejecting idempotency_key_conflict (both on the initial short-circuit and on a genuine concurrent-insert race) when the key was already used for a different label_instance_id/printer_id/is_reprint (findings review CRITICAL #1/#4/#5/#9/#10) -- never silently returns or races into the wrong print job.';

create function app.print_label(
  p_label_instance_id uuid,
  p_printer_id uuid,
  p_copies integer,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.label_print_jobs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_label app.label_instances;
begin
  select * into v_label from app.label_instances where id = p_label_instance_id;
  if not found then
    raise exception 'label_instance_not_found: %', p_label_instance_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_label.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_label.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return app.execute_label_print(p_label_instance_id, p_printer_id, p_copies, false, null, p_idempotency_key, p_actor_auth_user_id, p_actor_label);
end;
$$;

comment on function app.print_label is
  'ATW-021: OPS:Edit-gated (routine staff print action). Enqueues a real app.jobs row (job_type=print_label). Idempotent on (tenant_id, idempotency_key).';

create function app.reprint_label(
  p_label_instance_id uuid,
  p_printer_id uuid,
  p_copies integer,
  p_reason text,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.label_print_jobs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_label app.label_instances;
begin
  select * into v_label from app.label_instances where id = p_label_instance_id;
  if not found then
    raise exception 'label_instance_not_found: %', p_label_instance_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_label.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_label.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return app.execute_label_print(p_label_instance_id, p_printer_id, p_copies, true, p_reason, p_idempotency_key, p_actor_auth_user_id, p_actor_label);
end;
$$;

comment on function app.reprint_label is
  'ATW-021: OPS:Override-gated (a governed reprint action). Same core as app.print_label (shared app.execute_label_print) but is_reprint=true, reprint_reason=p_reason (required, non-empty). Preserves the SAME label_instance_id -- never creates a second instance.';

create function app.void_label(
  p_label_instance_id uuid,
  p_reason text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.label_instances
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_label app.label_instances;
begin
  select * into v_label from app.label_instances where id = p_label_instance_id for update;
  if not found then
    raise exception 'label_instance_not_found: %', p_label_instance_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_label.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_label.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.label_subject_record_scope_ok(p_actor_auth_user_id, v_label.tenant_id, v_label.subject_type, v_label.subject_id) then
    raise exception 'insufficient_authority: identity % cannot void label %', p_actor_auth_user_id, p_label_instance_id using errcode = 'insufficient_privilege';
  end if;

  if v_label.status = 'void' then
    raise exception 'already_void: label instance % is already void', p_label_instance_id using errcode = 'check_violation';
  end if;

  if v_label.record_version <> p_expected_version then
    raise exception 'stale_version: label instance % expected version % but found %', p_label_instance_id, p_expected_version, v_label.record_version
      using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to void a label' using errcode = 'check_violation';
  end if;

  update app.label_instances set
    status = 'void',
    void_reason = p_reason,
    voided_by_auth_user_id = p_actor_auth_user_id,
    voided_by_label = p_actor_label,
    voided_at = now()
  where id = p_label_instance_id
  returning * into v_label;

  perform app.capture_audit_event(
    v_label.tenant_id, p_actor_auth_user_id, p_actor_label, 'void_label',
    'app.label_instances', v_label.id, 'success', p_reason, null, jsonb_build_object('new_status', 'void')
  );

  return v_label;
end;
$$;

comment on function app.void_label is
  'ATW-021: OPS:Override-gated. Rejects if already void (already_void, a hard rejection, not an idempotent no-op). Does not touch/delete any existing label_print_jobs/label_scan_events row (lineage preserved). Once void, both app.print_label and app.reprint_label reject label_voided (enforced by the shared app.execute_label_print both already call).';

-- === Worker-side completion sync (service_role only -- no authenticated grant) ===

-- Note: PostgreSQL requires every parameter after the first one carrying a DEFAULT to
-- also carry a default -- p_actor_auth_user_id/p_actor_label are therefore declared
-- `default null` here purely for signature legality; both remain effectively required
-- (this function's own body raises no_data_found/insufficient-shaped errors downstream
-- if a real actor is not supplied, and the TypeScript service layer always passes
-- both explicitly). This keeps the brief's own literal parameter ordering
-- (p_label_print_job_id, p_outcome_status, p_error, p_actor_auth_user_id,
-- p_actor_label) intact rather than silently reordering it.
create function app.record_label_print_outcome(
  p_label_print_job_id uuid,
  p_outcome_status text,
  p_error text default null,
  p_actor_auth_user_id uuid default null,
  p_actor_label text default null
)
returns app.label_print_jobs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_job app.label_print_jobs;
begin
  if p_actor_label is null or length(trim(p_actor_label)) = 0 then
    raise exception 'invalid_actor_label: an actor label is required to record a print outcome' using errcode = 'check_violation';
  end if;
  if p_outcome_status not in ('succeeded', 'failed') then
    raise exception 'invalid_outcome_status: % is not a recognized print outcome status', p_outcome_status using errcode = 'check_violation';
  end if;

  select * into v_job from app.label_print_jobs where id = p_label_print_job_id for update;
  if not found then
    raise exception 'label_print_job_not_found: %', p_label_print_job_id using errcode = 'no_data_found';
  end if;

  if v_job.status in ('succeeded', 'failed', 'cancelled') then
    if v_job.status = p_outcome_status then
      return v_job;
    end if;
    raise exception 'label_print_job_already_resolved: print job % is already % and cannot be recorded as %', p_label_print_job_id, v_job.status, p_outcome_status
      using errcode = 'check_violation';
  end if;

  update app.label_print_jobs set
    status = p_outcome_status,
    outcome_error = (case when p_outcome_status = 'failed' then p_error else null end),
    completed_at = now()
  where id = p_label_print_job_id
  returning * into v_job;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_label_print_outcome',
    'app.label_print_jobs', v_job.id, 'success', p_error, null, jsonb_build_object('status', p_outcome_status)
  );

  return v_job;
end;
$$;

comment on function app.record_label_print_outcome is
  'ATW-021: a worker-side callback called AFTER a future worker has already called the generic app.complete_job/app.record_job_failure (PLT-132) -- syncs this domain table''s own status column, never read live off app.jobs by a client. service_role only (no authenticated grant at all, design/grants section below). Idempotent: a same-outcome retry on an already-terminal row is a clean no-op; a conflicting second outcome raises label_print_job_already_resolved.';

-- === The flagship scan-resolution RPC ===

-- Design note (a real, proactively-found correctness issue, disclosed rather than
-- silently worked around): PostgreSQL has no autonomous-transaction primitive
-- available in this repository (no dblink/pg_background anywhere in supabase/
-- migrations/). A plain "INSERT the log row, then RAISE EXCEPTION" sequence inside one
-- function call does NOT actually persist that INSERT once the exception propagates --
-- an uncaught exception rolls back the entire statement (including any INSERT it
-- performed), and a CALLER that wraps the call in its own BEGIN/EXCEPTION block (the
-- normal way a client distinguishes one rejection reason from another) rolls it back
-- to that block's own implicit savepoint just the same. Since this checkpoint's own
-- acceptance criteria requires "every resolve attempt (successful and rejected)
-- produces exactly one label_scan_events row" -- a real, testable guarantee -- app.
-- resolve_label follows the IDENTICAL, already-established precedent this repository's
-- own app.resolve_gps_device_for_handshake (ATW-226D) already uses for the identical
-- tension ("every attempt, accepted or rejected, is captured via app.capture_audit_
-- event"): it RETURNS a discriminated result (resolved/rejection_reason fields) for
-- every ORDINARY, expected rejection outcome (steps b/c/d/e below -- invalid_checksum/
-- unknown_code/void_code/insufficient_authority) rather than raising for them, so the
-- log INSERT commits as part of the function's own successful (non-erroring) return.
-- Only the PRIOR authority gate (step a, tenant membership) still raises -- that
-- indicates the caller was never a legitimate scan-attempt participant in this tenant
-- at all (no row to log against, mirroring app.resolve_gps_device_for_handshake''s own
-- distinction between an ordinary per-device outcome and a broken caller credential).
create type app.label_resolve_result as (
  resolved boolean,
  rejection_reason text,
  label_instance_id uuid,
  template_version_id uuid,
  subject_type text,
  subject_id uuid,
  encoded_value text,
  status text,
  subject_code text,
  subject_name text,
  subject_status text
);

create function app.resolve_label(
  p_tenant_id uuid,
  p_encoded_value text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.label_resolve_result
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_core text;
  v_checksum_text text;
  v_checksum integer;
  v_recomputed integer;
  v_label app.label_instances;
  v_result app.label_resolve_result;
  v_location app.warehouse_locations;
  v_item app.item_masters;
  v_lot app.lot_identities;
  v_serial app.serial_identities;
  v_package app.wms_packages;
  v_task app.wms_pick_tasks;
begin
  -- (a) Tenant-membership gate first, before anything else -- raises (no scan-event
  -- row to log yet; this caller is not a legitimate scan-attempt participant at all).
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % has no active membership in tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- (b) Malformed shape at all -> log + return resolved=false, before ever touching
  -- label_instances.
  if p_encoded_value is null or p_encoded_value !~ '^[A-Z]{3}-[0-9A-F]{12}-[0-9]$' then
    insert into app.label_scan_events (tenant_id, encoded_value, label_instance_id, subject_type, resolved, rejection_reason, scanned_by_auth_user_id, scanned_by_label)
    values (p_tenant_id, coalesce(p_encoded_value, ''), null, null, false, 'invalid_checksum', p_actor_auth_user_id, p_actor_label);
    v_result.resolved := false;
    v_result.rejection_reason := 'invalid_checksum';
    return v_result;
  end if;

  v_core := split_part(p_encoded_value, '-', 2);
  v_checksum_text := split_part(p_encoded_value, '-', 3);
  v_checksum := v_checksum_text::integer;
  v_recomputed := app.compute_label_checksum_digit(v_core);
  if v_recomputed <> v_checksum then
    insert into app.label_scan_events (tenant_id, encoded_value, label_instance_id, subject_type, resolved, rejection_reason, scanned_by_auth_user_id, scanned_by_label)
    values (p_tenant_id, p_encoded_value, null, null, false, 'invalid_checksum', p_actor_auth_user_id, p_actor_label);
    v_result.resolved := false;
    v_result.rejection_reason := 'invalid_checksum';
    return v_result;
  end if;

  -- (c) Look up regardless of status (need to see void ones too, to distinguish
  -- void_code from unknown_code).
  select * into v_label from app.label_instances where tenant_id = p_tenant_id and encoded_value = p_encoded_value;
  if not found then
    insert into app.label_scan_events (tenant_id, encoded_value, label_instance_id, subject_type, resolved, rejection_reason, scanned_by_auth_user_id, scanned_by_label)
    values (p_tenant_id, p_encoded_value, null, null, false, 'unknown_code', p_actor_auth_user_id, p_actor_label);
    v_result.resolved := false;
    v_result.rejection_reason := 'unknown_code';
    return v_result;
  end if;

  -- (d) status = 'void'.
  if v_label.status = 'void' then
    insert into app.label_scan_events (tenant_id, encoded_value, label_instance_id, subject_type, resolved, rejection_reason, scanned_by_auth_user_id, scanned_by_label)
    values (p_tenant_id, p_encoded_value, v_label.id, v_label.subject_type, false, 'void_code', p_actor_auth_user_id, p_actor_label);
    v_result.resolved := false;
    v_result.rejection_reason := 'void_code';
    v_result.label_instance_id := v_label.id;
    v_result.subject_type := v_label.subject_type;
    v_result.subject_id := v_label.subject_id;
    v_result.encoded_value := v_label.encoded_value;
    v_result.status := v_label.status;
    return v_result;
  end if;

  -- (e) Re-derive current owner/warehouse scope from the LIVE subject row -- the
  -- literal "every resolution reauthorizes... access" requirement.
  if not app.label_subject_record_scope_ok(p_actor_auth_user_id, p_tenant_id, v_label.subject_type, v_label.subject_id) then
    insert into app.label_scan_events (tenant_id, encoded_value, label_instance_id, subject_type, resolved, rejection_reason, scanned_by_auth_user_id, scanned_by_label)
    values (p_tenant_id, p_encoded_value, v_label.id, v_label.subject_type, false, 'insufficient_authority', p_actor_auth_user_id, p_actor_label);
    v_result.resolved := false;
    v_result.rejection_reason := 'insufficient_authority';
    return v_result;
  end if;

  -- (f) Success.
  insert into app.label_scan_events (tenant_id, encoded_value, label_instance_id, subject_type, resolved, rejection_reason, scanned_by_auth_user_id, scanned_by_label)
  values (p_tenant_id, p_encoded_value, v_label.id, v_label.subject_type, true, null, p_actor_auth_user_id, p_actor_label);

  v_result.resolved := true;
  v_result.rejection_reason := null;
  v_result.label_instance_id := v_label.id;
  v_result.template_version_id := v_label.template_version_id;
  v_result.subject_type := v_label.subject_type;
  v_result.subject_id := v_label.subject_id;
  v_result.encoded_value := v_label.encoded_value;
  v_result.status := v_label.status;

  -- Least-data label content (Prompt 240 §16) -- a minimal code/name/status
  -- projection, never the full subject row.
  if v_label.subject_type = 'bin' then
    select * into v_location from app.warehouse_locations where id = v_label.subject_id;
    v_result.subject_code := v_location.code;
    v_result.subject_name := v_location.name;
    v_result.subject_status := v_location.status;
  elsif v_label.subject_type = 'item' then
    select * into v_item from app.item_masters where id = v_label.subject_id;
    v_result.subject_code := v_item.code;
    v_result.subject_name := v_item.name;
    v_result.subject_status := v_item.status;
  elsif v_label.subject_type = 'lot' then
    select * into v_lot from app.lot_identities where id = v_label.subject_id;
    v_result.subject_code := v_lot.lot_number;
    v_result.subject_status := v_lot.status;
  elsif v_label.subject_type = 'serial' then
    select * into v_serial from app.serial_identities where id = v_label.subject_id;
    v_result.subject_code := v_serial.serial_number;
    v_result.subject_status := v_serial.status;
  elsif v_label.subject_type in ('package', 'pallet') then
    select * into v_package from app.wms_packages where id = v_label.subject_id;
    v_result.subject_code := v_package.package_number;
    v_result.subject_status := v_package.status;
  elsif v_label.subject_type = 'task' then
    select * into v_task from app.wms_pick_tasks where id = v_label.subject_id;
    v_result.subject_status := v_task.status;
  end if;

  return v_result;
end;
$$;

comment on function app.resolve_label is
  'ATW-021: THE flagship scan-resolution RPC. Order: (a) tenant-membership + OPS:View gate (raises -- no scan attempt to log yet), (b) recompute checksum from the scanned value''s own embedded core BEFORE ever querying label_instances (a structurally malformed/forged code never touches the table), (c) look up regardless of status, (d) void check, (e) re-derive current record-scope from the LIVE subject row via app.label_subject_record_scope_ok (never the label''s own cached owner/warehouse columns), (f) log + return a minimal subject projection. Steps (b)-(e) RETURN resolved=false/rejection_reason rather than raising (see this function''s own header design note -- the app.resolve_gps_device_for_handshake/ATW-226D precedent) so the log INSERT always commits. Every attempt, resolved or rejected, produces exactly one app.label_scan_events row.';

-- === Reads ===

create function app.get_label_template(p_template_id uuid, p_actor_auth_user_id uuid)
returns app.label_templates
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_template app.label_templates;
begin
  select * into v_template from app.label_templates where id = p_template_id;
  if not found then
    raise exception 'label_template_not_found: %', p_template_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_template.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_template.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return v_template;
end;
$$;

create function app.list_label_templates(p_tenant_id uuid, p_actor_auth_user_id uuid, p_subject_type_filter text default null, p_limit integer default 50)
returns setof app.label_templates
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_limit integer;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select * from app.label_templates t
  where t.tenant_id = p_tenant_id
    and (p_subject_type_filter is null or t.subject_type = p_subject_type_filter)
  order by t.created_at desc
  limit v_limit;
end;
$$;

create function app.list_label_template_versions(p_template_id uuid, p_actor_auth_user_id uuid, p_status_filter text default null, p_limit integer default 50)
returns setof app.label_template_versions
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_template app.label_templates;
  v_limit integer;
begin
  select * into v_template from app.label_templates where id = p_template_id;
  if not found then
    raise exception 'label_template_not_found: %', p_template_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_template.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_template.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select * from app.label_template_versions v
  where v.template_id = p_template_id
    and (p_status_filter is null or v.status = p_status_filter)
  order by v.version_number desc
  limit v_limit;
end;
$$;

create function app.list_label_printers(p_tenant_id uuid, p_actor_auth_user_id uuid, p_warehouse_id uuid default null, p_status_filter text default null, p_limit integer default 50)
returns setof app.label_printers
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_limit integer;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select * from app.label_printers p
  where p.tenant_id = p_tenant_id
    and (p_warehouse_id is null or p.warehouse_id = p_warehouse_id)
    and (p_status_filter is null or p.status = p_status_filter)
  order by p.created_at desc
  limit v_limit;
end;
$$;

create function app.get_label_instance(p_label_instance_id uuid, p_actor_auth_user_id uuid)
returns app.label_instances
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_label app.label_instances;
begin
  select * into v_label from app.label_instances where id = p_label_instance_id;
  if not found then
    raise exception 'label_instance_not_found: %', p_label_instance_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_label.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_label.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.label_subject_record_scope_ok(p_actor_auth_user_id, v_label.tenant_id, v_label.subject_type, v_label.subject_id) then
    raise exception 'insufficient_authority: identity % cannot view label %', p_actor_auth_user_id, p_label_instance_id using errcode = 'insufficient_privilege';
  end if;

  return v_label;
end;
$$;

comment on function app.get_label_instance is
  'ATW-021: same shared record-scope dispatch as app.resolve_label, no scan-event logging -- this is a direct lookup-by-id for an already-known label, not a scan.';

create function app.list_label_instances(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_subject_type text default null,
  p_subject_id uuid default null,
  p_status_filter text default null,
  p_limit integer default 50
)
returns setof app.label_instances
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_limit integer;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select * from app.label_instances i
  where i.tenant_id = p_tenant_id
    and (p_subject_type is null or i.subject_type = p_subject_type)
    and (p_subject_id is null or i.subject_id = p_subject_id)
    and (p_status_filter is null or i.status = p_status_filter)
    and (i.owner_account_id is null or app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, p_tenant_id, i.owner_account_id))
  order by i.created_at desc
  limit v_limit;
end;
$$;

create function app.list_label_print_jobs(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_label_instance_id uuid default null,
  p_status_filter text default null,
  p_limit integer default 50
)
returns setof app.label_print_jobs
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_limit integer;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select * from app.label_print_jobs j
  where j.tenant_id = p_tenant_id
    and (p_label_instance_id is null or j.label_instance_id = p_label_instance_id)
    and (p_status_filter is null or j.status = p_status_filter)
  order by j.requested_at desc
  limit v_limit;
end;
$$;

comment on function app.list_label_print_jobs is
  'ATW-021: tenant-wide (design note: this is a staff-only operational table -- print/reprint are never customer-facing per Prompt 240 §26).';

create function app.list_label_scan_events(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_label_instance_id uuid default null,
  p_limit integer default 50
)
returns setof app.label_scan_events
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_limit integer;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select * from app.label_scan_events e
  where e.tenant_id = p_tenant_id
    and (p_label_instance_id is null or e.label_instance_id = p_label_instance_id)
  order by e.scanned_at desc
  limit v_limit;
end;
$$;

comment on function app.list_label_scan_events is
  'ATW-021: OPS:View, tenant-wide (design note 9) -- deliberately NOT owner-narrowed at the RPC layer, disclosed rather than silently applying a different rule than every other read in this migration. The underlying table''s own RLS (design note 8) still narrows a raw SELECT.';

-- === RLS ===

alter table app.label_templates enable row level security;

create policy label_templates_select_scoped on app.label_templates
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

alter table app.label_template_versions enable row level security;

create policy label_template_versions_select_scoped on app.label_template_versions
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

alter table app.label_printers enable row level security;

create policy label_printers_select_scoped on app.label_printers
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

alter table app.label_instances enable row level security;

create policy label_instances_select_scoped on app.label_instances
  for select to authenticated
  using (
    (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin())
    and (owner_account_id is null or app.actor_can_view_owner_scoped_row(auth.uid(), tenant_id, owner_account_id))
  );

alter table app.label_print_jobs enable row level security;

create policy label_print_jobs_select_scoped on app.label_print_jobs
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

alter table app.label_scan_events enable row level security;

create policy label_scan_events_select_scoped on app.label_scan_events
  for select to authenticated
  using (
    (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin())
    and (
      label_instance_id is null
      or exists (
        select 1 from app.label_instances li
        where li.id = label_scan_events.label_instance_id
          and (li.owner_account_id is null or app.actor_can_view_owner_scoped_row(auth.uid(), label_scan_events.tenant_id, li.owner_account_id))
      )
    )
  );

-- === Grants ===

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke
-- of PostgreSQL's PUBLIC-execute default, the standing per-migration convention since
-- PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant select on app.label_templates, app.label_template_versions, app.label_printers, app.label_instances, app.label_print_jobs, app.label_scan_events to authenticated, service_role;
grant insert, update, delete on app.label_templates, app.label_template_versions, app.label_printers, app.label_instances, app.label_print_jobs, app.label_scan_events to service_role;

-- Shared internal building blocks -- see design note 3: app.resolve_label_subject and
-- app.execute_label_print are deliberately NOT granted to authenticated.
grant execute on function app.compute_label_checksum_digit(text) to authenticated, service_role;
grant execute on function app.render_label_content(text, text[], jsonb) to authenticated, service_role;
grant execute on function app.label_subject_record_scope_ok(uuid, uuid, text, uuid) to authenticated, service_role;
grant execute on function app.resolve_label_subject(uuid, text, uuid) to service_role;
grant execute on function app.execute_label_print(uuid, uuid, integer, boolean, text, text, uuid, text) to service_role;

-- Template/version lifecycle.
grant execute on function app.create_label_template(uuid, text, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.create_label_template_version_draft(uuid, text, text[], text, uuid, text) to authenticated, service_role;
grant execute on function app.publish_label_template_version(uuid, integer, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.set_label_template_version_status(uuid, text, text, integer, uuid, text) to authenticated, service_role;

-- Printer administration.
grant execute on function app.create_label_printer(uuid, uuid, text, text, jsonb, uuid, text) to authenticated, service_role;
grant execute on function app.set_label_printer_status(uuid, text, text, integer, uuid, text) to authenticated, service_role;

-- Generation, preview, print, reprint, void.
grant execute on function app.preview_label(uuid, jsonb, uuid) to authenticated, service_role;
grant execute on function app.generate_label(uuid, text, text, uuid, jsonb, text, uuid, text) to authenticated, service_role;
grant execute on function app.print_label(uuid, uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.reprint_label(uuid, uuid, integer, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.void_label(uuid, text, integer, uuid, text) to authenticated, service_role;

-- Worker-side completion sync -- service_role only, no authenticated grant at all
-- (design brief item 12: "a worker-side callback, not a client action").
grant execute on function app.record_label_print_outcome(uuid, text, text, uuid, text) to service_role;

-- Flagship scan resolution.
grant execute on function app.resolve_label(uuid, text, uuid, text) to authenticated, service_role;

-- Reads.
grant execute on function app.get_label_template(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_label_templates(uuid, uuid, text, integer) to authenticated, service_role;
grant execute on function app.list_label_template_versions(uuid, uuid, text, integer) to authenticated, service_role;
grant execute on function app.list_label_printers(uuid, uuid, uuid, text, integer) to authenticated, service_role;
grant execute on function app.get_label_instance(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_label_instances(uuid, uuid, text, uuid, text, integer) to authenticated, service_role;
grant execute on function app.list_label_print_jobs(uuid, uuid, uuid, text, integer) to authenticated, service_role;
grant execute on function app.list_label_scan_events(uuid, uuid, uuid, integer) to authenticated, service_role;
