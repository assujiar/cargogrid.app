-- Platform Core capability PLT-131 (Import/Export Job Framework, CG-S6-PLT-028)
-- A tenant/permission-aware asynchronous import/export framework: versioned schema
-- adapters, staging → validate → preview → commit (import) or → complete (export),
-- resumable progress tracking, row-level errors, cooperative cancellation, retry/DLQ,
-- and a real formula-injection (CSV injection) sanitizer.
--
-- Scope and design decisions, disclosed rather than left implicit:
--
-- * **`app.jobs` is created here, not by a not-yet-built generic Background Job
--   Framework.** Prompt 132 (Background Job Framework, `CG-S6-PLT-029`) is `BLOCKED`
--   on THIS task (`00_PLATFORM_CORE_EXECUTION_INDEX.md` row `029`'s own dependency
--   list names `PLT-131`), not the reverse -- confirmed via this checkpoint's own
--   research that no `app.jobs` table exists anywhere in this repository before this
--   migration. `app.jobs` matches `05_DATABASE_SCHEMA_WORKSTREAM.md` line 110's exact
--   Tech Arch §32.11 field list verbatim (`job_id, tenant_id, job_type, status,
--   priority, payload, attempts, max_attempts, locked_by, locked_until, error,
--   result_url, created_by, created_at, completed_at`), extended with this
--   repository's own standing `idempotency_key` convention (§4 of that same document)
--   and the import/export-specific columns this checkpoint's own scope needs
--   (`import_export_schema_code`, `source_file_id`, `result_file_id`, `total_rows`,
--   `processed_rows`, `valid_row_count`, `invalid_row_count`, `cancel_reason`).
--   `job_type` is deliberately `CHECK`-constrained to exactly `('import', 'export')`
--   for this migration's own real scope -- Prompt 132 will need its own migration to
--   widen this constraint when it adds further job types, the same "never fabricate
--   content beyond what this checkpoint actually needs" discipline this session has
--   held throughout. `locked_by`/`locked_until` are real, stored, correctly-typed
--   columns with no function wiring them yet -- distributed worker-locking semantics
--   belong to Prompt 132's own live worker, disclosed `NOT_RUN` here.
-- * **`import_export_jobs` is not a separate table** -- `05_*.md` line 113 states this
--   explicitly: "a specialization row-type of `jobs`, sharing the same table with
--   `job_type = 'import'|'export'`." `app.import_staging_rows` matches that same
--   line's exact field list (`tenant_id`, `job_id`, `row_number`, `raw_payload jsonb`,
--   `validation_status`, `error`), plus this checkpoint's own `id`/`created_at`.
-- * **An import/export schema is a per-instance config registry**, the same
--   `<domain>:<code>` pattern `PLT-124..130` all already established --
--   `app.register_import_export_schema()` mints a dedicated `import_export:<code>`
--   config_type via `PLT-121`'s own `app.register_config_type()`. A tenant's own
--   published definition (`app.publish_import_export_schema()`) holds a bounded
--   `columns` array (`key`/`label`/`required`/`data_type` from a real allowlist:
--   `text`/`number`/`boolean`/`date`/`email`) -- structural shape validation only,
--   not the actual business-domain field catalogue any specific domain's own adapter
--   would define later (no business-domain table exists yet in Phase 1 Platform Core).
-- * **Row validation is structural, not a domain write.** `app.validate_staging_row()`
--   checks required-ness and data-type shape against the schema's own column
--   definitions -- it never inserts a validated row into any canonical business table,
--   since none exists yet. `app.commit_import_job()`'s "commit" therefore means
--   "finalize validation and mark this framework's own job complete," not "write to a
--   real table" -- the actual write is explicitly a future, domain-specific adapter's
--   job (Prompt 131 §24: "Domain adapter uses canonical service/validation, not direct
--   unsafe writes" -- the domain adapter is a separate, later consumer of this
--   framework's validated staging rows, not something this migration performs itself).
--   Commit is all-or-nothing by default (§24 "no partial corruption") -- a job with any
--   `invalid` row is refused unless the caller explicitly passes `p_allow_partial`,
--   which still records every invalid row rather than silently dropping it (the same
--   "skipped, not silently dropped" discipline `PLT-127`'s preference-aware fallback
--   established).
-- * **Malware scanning is composed from `PLT-128`, not reimplemented.**
--   `app.stage_import_rows()` refuses to stage any row from a source file whose
--   `malware_scan_status` is not `clean` (`infected` is refused outright; anything
--   else is refused as "not yet scanned") -- the exact RPD-032 gate this repository's
--   Document/File Engine already enforces, reused via a direct `app.files` lookup
--   rather than a parallel scan mechanism.
-- * **Cooperative cancellation, matching `08_API_INTEGRATION_WORKSTREAM.md` §9's own
--   "cancelling/cancelled, cooperative not hard-kill" language.** A `pending` job
--   cancels immediately; an `in_progress` job moves to `cancelling` and requires a
--   second call (`app.acknowledge_job_cancellation()`, the real function a future
--   worker would call the moment it notices the flag and stops cleanly) to reach
--   `cancelled` -- genuine two-phase semantics, not a single-step pretend cancel.
-- * **A real, tested, disclosed-partial formula-injection (CSV injection) sanitizer.**
--   No `docs/architecture/*.md` document names this control anywhere (confirmed via
--   this checkpoint's own research) -- `app.sanitize_formula_injection()` is this
--   checkpoint's own disclosed construction, applying the OWASP-recommended mitigation
--   (prefixing a leading `=`/`+`/`-`/`@` with a single quote) any future export-file
--   writer would call per output cell, genuinely provable as pure computation without
--   any live file-generation step existing yet (the same "algorithm real, live
--   generation deferred" pattern `ADR-0011`/`ADR-0012` already established this
--   session) -- deliberately NOT wired into import-row validation itself, since a
--   value like `-5` is a legitimate negative number on import, not an injection
--   attempt; the mitigation belongs at export-time cell-writing, not import-time
--   row-shape validation.
-- * **This capability is server-mediated for every write**, the design `PLT-128`/`129`/
--   `130` established -- every mutating function is `service_role`-only, so none of
--   them needs `SECURITY DEFINER` except `app.preview_import_job()`, the one
--   authenticated-facing read function (mirrors `PLT-129`'s `list_api_keys_for_tenant`
--   precedent). `app.jobs` itself carries direct-table RLS for `authenticated` (a
--   requester or their tenant's support/Supreme authority may see a job's own status --
--   the "shared business data" precedent, not the "credential" precedent, since job
--   status is not itself secret); `app.import_staging_rows` (raw imported content, not
--   yet validated) carries zero `authenticated` grant at all, matching
--   `app.file_access_logs`'s precedent for sensitive operational data.
-- * Per `ERR-2026-004`: this migration carries its own explicit
--   `revoke execute on all functions in schema app from public;` before its final
--   grants.

create table app.import_export_schemas (
  code text primary key,
  name text not null,
  owner_primitive_code text not null,
  registered_by text,
  created_at timestamptz not null default now()
);

comment on table app.import_export_schemas is
  'PLT-131: registry of import/export schema kinds. Each tenant configures its own column definitions (key/label/required/data_type) for a given code via a dedicated import_export:<code> config_type minted through app.register_config_type() -- the same per-instance registry pattern every prior Governed Engine this session established.';

create function app.register_import_export_schema(
  p_code text,
  p_name text,
  p_owner_primitive_code text,
  p_actor_auth_user_id uuid,
  p_registered_by text
)
returns app.import_export_schemas
language plpgsql
as $$
declare
  v_existing app.import_export_schemas;
  v_schema app.import_export_schemas;
begin
  if not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: only Supreme Admin may register an import/export schema'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_existing from app.import_export_schemas where code = p_code;
  if found then
    return v_existing;
  end if;

  insert into app.import_export_schemas (code, name, owner_primitive_code, registered_by)
  values (p_code, p_name, p_owner_primitive_code, p_registered_by)
  returning * into v_schema;

  perform app.register_config_type('import_export:' || p_code, p_name, p_owner_primitive_code, p_actor_auth_user_id, p_registered_by);

  perform app.capture_audit_event(
    null, p_actor_auth_user_id, p_registered_by, 'register_import_export_schema',
    'app.import_export_schemas', null, 'success', null, null, to_jsonb(v_schema)
  );

  return v_schema;
end;
$$;

-- Publish-time structural gate over an 'import_export:<code>'-typed config_version's
-- own 'columns' item: a non-empty array of {key, label, required, data_type}, each key
-- unique, data_type from a bounded allowlist -- shape validation only, never a
-- fabricated business-field catalogue.
create function app.validate_import_export_schema_definition(p_version_id uuid)
returns boolean
language plpgsql
as $$
declare
  v_columns jsonb;
  v_column jsonb;
  v_key text;
  v_seen_keys text[] := array[]::text[];
  v_allowed_data_types text[] := array['text', 'number', 'boolean', 'date', 'email'];
begin
  select value into v_columns from app.config_items where config_version_id = p_version_id and key = 'columns';

  if v_columns is null or jsonb_typeof(v_columns) <> 'array' or jsonb_array_length(v_columns) = 0 then
    raise exception 'import_export_missing_columns: version % has no ''columns'' item, or it is not a non-empty array', p_version_id
      using errcode = 'check_violation';
  end if;

  for v_column in select * from jsonb_array_elements(v_columns) loop
    v_key := v_column ->> 'key';
    if v_key is null or length(v_key) = 0 then
      raise exception 'import_export_invalid_column_key: every column requires a non-empty ''key'''
        using errcode = 'check_violation';
    end if;
    if v_key = any (v_seen_keys) then
      raise exception 'import_export_duplicate_column_key: column key % is declared more than once', v_key
        using errcode = 'check_violation';
    end if;
    v_seen_keys := v_seen_keys || v_key;

    if coalesce(v_column ->> 'label', '') = '' then
      raise exception 'import_export_missing_column_label: column % has no non-empty label', v_key
        using errcode = 'check_violation';
    end if;

    if not (v_column ->> 'data_type' = any (v_allowed_data_types)) then
      raise exception 'import_export_invalid_data_type: column %''s data_type % is not one of text/number/boolean/date/email', v_key, v_column ->> 'data_type'
        using errcode = 'check_violation';
    end if;

    if jsonb_typeof(v_column -> 'required') is distinct from 'boolean' then
      raise exception 'import_export_missing_required_flag: column % has no boolean ''required'' flag', v_key
        using errcode = 'check_violation';
    end if;
  end loop;

  return true;
end;
$$;

create function app.publish_import_export_schema(
  p_version_id uuid,
  p_actor_auth_user_id uuid,
  p_effective_from timestamptz,
  p_actor_label text
)
returns app.config_versions
language plpgsql
as $$
begin
  perform app.validate_import_export_schema_definition(p_version_id);
  return app.publish_config_version(p_version_id, p_actor_auth_user_id, p_effective_from, p_actor_label);
end;
$$;

-- Resolves a tenant's currently published column definition for a schema code, raising
-- if the tenant has never published one -- never fabricates a default column set.
create function app.resolve_import_export_schema_columns(p_tenant_id uuid, p_schema_code text)
returns table (config_version_id uuid, columns jsonb)
language plpgsql
stable
as $$
declare
  v_version_id uuid;
begin
  select cv.id into v_version_id
  from app.config_versions cv
  join app.config_objects co on co.id = cv.config_object_id
  where co.config_type_code = 'import_export:' || p_schema_code
    and co.tenant_id = p_tenant_id
    and co.scope_level = 'tenant'
    and cv.status = 'published'
  order by cv.version_number desc
  limit 1;

  if v_version_id is null then
    raise exception 'import_export_schema_not_configured: tenant % has not published a definition for schema %', p_tenant_id, p_schema_code
      using errcode = 'check_violation';
  end if;

  return query
  select v_version_id, (select ci.value from app.config_items ci where ci.config_version_id = v_version_id and ci.key = 'columns');
end;
$$;

-- The job table -- see this migration's own header for the exact field-list provenance.
create table app.jobs (
  job_id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  job_type text not null,
  status text not null default 'pending',
  priority integer not null default 0,
  payload jsonb not null default '{}'::jsonb,
  attempts integer not null default 0,
  max_attempts integer not null default 3,
  locked_by text,
  locked_until timestamptz,
  error text,
  result_url text,
  created_by text,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  requested_by_auth_user_id uuid not null references auth.users (id),
  idempotency_key text,
  import_export_schema_code text references app.import_export_schemas (code),
  source_file_id uuid references app.files (id),
  result_file_id uuid references app.files (id),
  total_rows integer,
  processed_rows integer not null default 0,
  valid_row_count integer not null default 0,
  invalid_row_count integer not null default 0,
  cancel_reason text,
  updated_at timestamptz not null default now(),
  constraint jobs_job_type_check check (job_type in ('import', 'export')),
  constraint jobs_status_check check (status in ('pending', 'in_progress', 'cancelling', 'cancelled', 'completed', 'failed', 'dead_letter')),
  constraint jobs_max_attempts_check check (max_attempts > 0),
  constraint jobs_attempts_check check (attempts >= 0 and attempts <= max_attempts),
  constraint jobs_idempotency_key_unique unique (tenant_id, idempotency_key)
);

comment on table app.jobs is
  'PLT-131: the generic async job table (Tech Arch §32.11 field list verbatim, extended with this repository''s own idempotency_key convention and import/export-specific columns). job_type is CHECK-constrained to (''import'',''export'') for this checkpoint''s own real scope -- Prompt 132 (Background Job Framework) will widen it in its own migration when it adds further job types. locked_by/locked_until are real, correctly-typed columns with no live worker wiring them yet (disclosed NOT_RUN).';

create index jobs_tenant_status_idx on app.jobs (tenant_id, status, created_at desc);
create index jobs_dead_letter_idx on app.jobs (status) where status = 'dead_letter';

create function app.touch_jobs_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger jobs_touch_row
  before update on app.jobs
  for each row
  execute function app.touch_jobs_row();

create table app.import_staging_rows (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  job_id uuid not null references app.jobs (job_id),
  row_number integer not null,
  raw_payload jsonb not null,
  validation_status text not null default 'pending',
  error text,
  created_at timestamptz not null default now(),
  constraint import_staging_rows_validation_status_check check (validation_status in ('pending', 'valid', 'invalid')),
  constraint import_staging_rows_row_number_check check (row_number > 0),
  constraint import_staging_rows_unique unique (job_id, row_number)
);

comment on table app.import_staging_rows is
  'PLT-131: raw imported rows staged for structural validation before any canonical write -- "so a partially-invalid file never corrupts canonical data" (05_DATABASE_SCHEMA_WORKSTREAM.md line 113). Never itself written to a business-domain table -- that is an explicitly later, domain-specific adapter''s job (this migration''s own header).';

create index import_staging_rows_job_idx on app.import_staging_rows (job_id, row_number);
create index import_staging_rows_pending_idx on app.import_staging_rows (job_id) where validation_status = 'pending';

create function app.check_import_export_admin_authority(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
as $$
  select app.is_support_grant_authority(p_actor_auth_user_id, p_tenant_id);
$$;

create function app.check_import_export_job_authority(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
as $$
  select app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) or app.is_supreme_admin(p_actor_auth_user_id);
$$;

-- An import job requires a real, tenant-owned source_file_id (PLT-128); an export job
-- must not carry one (its result file is attached later, on completion).
create function app.create_import_export_job(
  p_tenant_id uuid,
  p_job_type text,
  p_schema_code text,
  p_source_file_id uuid,
  p_filters jsonb,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.jobs
language plpgsql
as $$
declare
  v_existing app.jobs;
  v_def record;
  v_job app.jobs;
begin
  if not app.check_import_export_job_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'job_actor_unauthorized: identity % lacks active membership in tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not (p_job_type = any (array['import', 'export'])) then
    raise exception 'import_export_invalid_job_type: % is not one of import/export', p_job_type
      using errcode = 'check_violation';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.jobs where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
    if found then
      return v_existing;
    end if;
  end if;

  if not app.validate_config_value(coalesce(p_filters, '{}'::jsonb)) then
    raise exception 'import_export_unsafe_payload: filters failed structural validation'
      using errcode = 'check_violation';
  end if;

  select * into v_def from app.resolve_import_export_schema_columns(p_tenant_id, p_schema_code);

  if p_job_type = 'import' then
    if p_source_file_id is null then
      raise exception 'import_missing_source_file: an import job requires a source_file_id'
        using errcode = 'check_violation';
    end if;
    if not exists (select 1 from app.files f where f.id = p_source_file_id and f.tenant_id = p_tenant_id) then
      raise exception 'import_source_file_not_found: no file % in tenant %', p_source_file_id, p_tenant_id
        using errcode = 'no_data_found';
    end if;
  else
    if p_source_file_id is not null then
      raise exception 'export_unexpected_source_file: an export job may not reference a source_file_id'
        using errcode = 'check_violation';
    end if;
  end if;

  insert into app.jobs (
    tenant_id, job_type, payload, requested_by_auth_user_id, idempotency_key,
    import_export_schema_code, source_file_id, created_by
  ) values (
    p_tenant_id, p_job_type, coalesce(p_filters, '{}'::jsonb), p_actor_auth_user_id, p_idempotency_key,
    p_schema_code, p_source_file_id, p_actor_label
  )
  returning * into v_job;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_import_export_job',
    'app.jobs', v_job.job_id, 'success', null, null,
    jsonb_build_object('job_id', v_job.job_id, 'job_type', v_job.job_type, 'schema_code', p_schema_code)
  );

  return v_job;
end;
$$;

-- Refuses to stage a single row until the source file has cleared malware scanning
-- (RPD-032, composed from PLT-128 directly). Each row is itself structurally validated
-- via app.validate_config_value() before staging.
create function app.stage_import_rows(
  p_job_id uuid,
  p_rows jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns integer
language plpgsql
as $$
declare
  v_job app.jobs;
  v_file app.files;
  v_row jsonb;
  v_next_row_number integer;
  v_count integer;
begin
  select * into v_job from app.jobs where job_id = p_job_id;
  if not found then
    raise exception 'import_export_job_not_found: no job %', p_job_id using errcode = 'no_data_found';
  end if;

  if not app.check_import_export_job_authority(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'job_actor_unauthorized: identity % lacks active membership in tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_job.job_type <> 'import' then
    raise exception 'import_export_wrong_job_type: job % is not an import job', p_job_id
      using errcode = 'check_violation';
  end if;

  if v_job.status not in ('pending', 'in_progress') then
    raise exception 'import_export_job_not_stageable: job % is %, rows may only be staged while pending or in_progress', p_job_id, v_job.status
      using errcode = 'check_violation';
  end if;

  select * into v_file from app.files where id = v_job.source_file_id;
  if v_file.malware_scan_status = 'infected' then
    raise exception 'import_source_file_infected: file % is quarantined, cannot stage rows from it', v_job.source_file_id
      using errcode = 'check_violation';
  end if;
  if v_file.malware_scan_status <> 'clean' then
    raise exception 'import_source_file_not_yet_scanned: file % has not yet cleared malware scanning', v_job.source_file_id
      using errcode = 'check_violation';
  end if;

  if p_rows is null or jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then
    raise exception 'import_export_missing_rows: at least one row is required'
      using errcode = 'check_violation';
  end if;

  select coalesce(max(row_number), 0) into v_next_row_number from app.import_staging_rows where job_id = p_job_id;

  for v_row in select * from jsonb_array_elements(p_rows) loop
    if not app.validate_config_value(v_row) then
      raise exception 'import_export_unsafe_row: a staged row failed structural validation'
        using errcode = 'check_violation';
    end if;
    v_next_row_number := v_next_row_number + 1;
    insert into app.import_staging_rows (tenant_id, job_id, row_number, raw_payload)
    values (v_job.tenant_id, p_job_id, v_next_row_number, v_row);
  end loop;

  select count(*) into v_count from app.import_staging_rows where job_id = p_job_id;

  update app.jobs
  set total_rows = v_count, status = case when status = 'pending' then 'in_progress' else status end
  where job_id = p_job_id;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'stage_import_rows',
    'app.jobs', p_job_id, 'success', null, null, jsonb_build_object('staged_count', jsonb_array_length(p_rows), 'total_rows', v_count)
  );

  return v_count;
end;
$$;

-- Structural validation only (required-ness + data-type shape) -- never a domain
-- write. Idempotent-safe: re-validating an already-resolved row adjusts the job's
-- valid/invalid counters by the delta rather than double-counting, and only advances
-- processed_rows on the row's first (pending -> resolved) transition.
create function app.validate_staging_row(
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
  v_def record;
  v_column jsonb;
  v_key text;
  v_value jsonb;
  v_value_text text;
  v_errors text[] := array[]::text[];
  v_old_status text;
  v_updated app.import_staging_rows;
begin
  select * into v_row from app.import_staging_rows where id = p_staging_row_id;
  if not found then
    raise exception 'import_export_staging_row_not_found: no staging row %', p_staging_row_id using errcode = 'no_data_found';
  end if;

  select * into v_job from app.jobs where job_id = v_row.job_id;

  if not app.check_import_export_job_authority(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'job_actor_unauthorized: identity % lacks active membership in tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_def from app.resolve_import_export_schema_columns(v_job.tenant_id, v_job.import_export_schema_code);

  for v_column in select * from jsonb_array_elements(v_def.columns) loop
    v_key := v_column ->> 'key';
    v_value := v_row.raw_payload -> v_key;

    if (v_column ->> 'required')::boolean and (v_value is null or jsonb_typeof(v_value) = 'null') then
      v_errors := v_errors || (v_key || ': required value is missing');
      continue;
    end if;

    if v_value is null or jsonb_typeof(v_value) = 'null' then
      continue;
    end if;

    v_value_text := v_value #>> '{}';

    case v_column ->> 'data_type'
      when 'number' then
        if v_value_text !~ '^-?[0-9]+(\.[0-9]+)?$' then
          v_errors := v_errors || (v_key || ': ' || v_value_text || ' is not a valid number');
        end if;
      when 'boolean' then
        if not (lower(v_value_text) = any (array['true', 'false'])) then
          v_errors := v_errors || (v_key || ': ' || v_value_text || ' is not a valid boolean');
        end if;
      when 'date' then
        if v_value_text !~ '^\d{4}-\d{2}-\d{2}' then
          v_errors := v_errors || (v_key || ': ' || v_value_text || ' is not a valid ISO date');
        end if;
      when 'email' then
        if v_value_text !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
          v_errors := v_errors || (v_key || ': ' || v_value_text || ' is not a valid email');
        end if;
      else
        null;
    end case;
  end loop;

  v_old_status := v_row.validation_status;

  update app.import_staging_rows
  set validation_status = case when array_length(v_errors, 1) is null then 'valid' else 'invalid' end,
      error = case when array_length(v_errors, 1) is null then null else array_to_string(v_errors, '; ') end
  where id = p_staging_row_id
  returning * into v_updated;

  update app.jobs
  set processed_rows = processed_rows + (case when v_old_status = 'pending' then 1 else 0 end),
      valid_row_count = valid_row_count
        + (case when v_updated.validation_status = 'valid' then 1 else 0 end)
        - (case when v_old_status = 'valid' then 1 else 0 end),
      invalid_row_count = invalid_row_count
        + (case when v_updated.validation_status = 'invalid' then 1 else 0 end)
        - (case when v_old_status = 'invalid' then 1 else 0 end)
  where job_id = v_job.job_id;

  return v_updated;
end;
$$;

-- The one authenticated-facing read function (SECURITY DEFINER, mirrors PLT-129's
-- list_api_keys_for_tenant precedent) -- a job's requester or their tenant's
-- support/Supreme authority may preview its staged-row counts.
create function app.preview_import_job(p_job_id uuid, p_actor_auth_user_id uuid)
returns table (total_rows integer, valid_rows integer, invalid_rows integer, pending_rows integer)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_job app.jobs;
begin
  select * into v_job from app.jobs where job_id = p_job_id;
  if not found then
    raise exception 'import_export_job_not_found: no job %', p_job_id using errcode = 'no_data_found';
  end if;

  if not (v_job.requested_by_auth_user_id = p_actor_auth_user_id or app.check_import_export_admin_authority(v_job.tenant_id, p_actor_auth_user_id)) then
    raise exception 'job_actor_unauthorized: identity % may not preview job %', p_actor_auth_user_id, p_job_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select
    coalesce(v_job.total_rows, 0),
    (select count(*)::integer from app.import_staging_rows r where r.job_id = p_job_id and r.validation_status = 'valid'),
    (select count(*)::integer from app.import_staging_rows r where r.job_id = p_job_id and r.validation_status = 'invalid'),
    (select count(*)::integer from app.import_staging_rows r where r.job_id = p_job_id and r.validation_status = 'pending');
end;
$$;

-- All-or-nothing by default (this migration's own header) -- refuses while any row is
-- still pending validation, and refuses while any row is invalid unless the caller
-- explicitly accepts a partial commit.
create function app.commit_import_job(
  p_job_id uuid,
  p_allow_partial boolean,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.jobs
language plpgsql
as $$
declare
  v_job app.jobs;
  v_pending_count integer;
  v_updated app.jobs;
begin
  select * into v_job from app.jobs where job_id = p_job_id;
  if not found then
    raise exception 'import_export_job_not_found: no job %', p_job_id using errcode = 'no_data_found';
  end if;

  if not app.check_import_export_job_authority(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'job_actor_unauthorized: identity % lacks active membership in tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_job.job_type <> 'import' then
    raise exception 'import_export_wrong_job_type: job % is not an import job', p_job_id using errcode = 'check_violation';
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

  update app.jobs
  set status = 'completed', completed_at = now()
  where job_id = p_job_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'commit_import_job',
    'app.jobs', p_job_id, 'success', null, to_jsonb(v_job), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

-- Two-phase cooperative cancel (this migration's own header). A pending job cancels
-- immediately; an in_progress job moves to cancelling and requires
-- app.acknowledge_job_cancellation() to finish.
create function app.cancel_import_export_job(
  p_job_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.jobs
language plpgsql
as $$
declare
  v_job app.jobs;
  v_updated app.jobs;
begin
  select * into v_job from app.jobs where job_id = p_job_id;
  if not found then
    raise exception 'import_export_job_not_found: no job %', p_job_id using errcode = 'no_data_found';
  end if;

  if not (v_job.requested_by_auth_user_id = p_actor_auth_user_id or app.check_import_export_admin_authority(v_job.tenant_id, p_actor_auth_user_id)) then
    raise exception 'job_actor_unauthorized: identity % may not cancel job %', p_actor_auth_user_id, p_job_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_job.status in ('completed', 'cancelled', 'failed', 'dead_letter') then
    raise exception 'import_export_job_already_terminal: job % is already %, cannot cancel', p_job_id, v_job.status
      using errcode = 'check_violation';
  end if;

  update app.jobs
  set status = case when v_job.status = 'pending' then 'cancelled' else 'cancelling' end,
      cancel_reason = p_reason,
      completed_at = case when v_job.status = 'pending' then now() else completed_at end
  where job_id = p_job_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_import_export_job',
    'app.jobs', p_job_id, 'success', p_reason, jsonb_build_object('status', v_job.status), jsonb_build_object('status', v_updated.status)
  );

  return v_updated;
end;
$$;

create function app.acknowledge_job_cancellation(
  p_job_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.jobs
language plpgsql
as $$
declare
  v_job app.jobs;
  v_updated app.jobs;
begin
  select * into v_job from app.jobs where job_id = p_job_id;
  if not found then
    raise exception 'import_export_job_not_found: no job %', p_job_id using errcode = 'no_data_found';
  end if;

  if v_job.status <> 'cancelling' then
    raise exception 'import_export_job_not_cancelling: job % is %, only a cancelling job may acknowledge cancellation', p_job_id, v_job.status
      using errcode = 'check_violation';
  end if;

  update app.jobs
  set status = 'cancelled', completed_at = now()
  where job_id = p_job_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'acknowledge_job_cancellation',
    'app.jobs', p_job_id, 'success', null, null, jsonb_build_object('status', v_updated.status)
  );

  return v_updated;
end;
$$;

-- Attaches a real, tenant-owned result file (PLT-128) to a completed export job --
-- result_url itself stays null/NOT_RUN, disclosed (no live signed-URL generator
-- exists; app.authorize_file_access() against result_file_id is the real, tested
-- access path, this migration's own header).
create function app.complete_export_job(
  p_job_id uuid,
  p_result_file_id uuid,
  p_row_count integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.jobs
language plpgsql
as $$
declare
  v_job app.jobs;
  v_updated app.jobs;
begin
  select * into v_job from app.jobs where job_id = p_job_id;
  if not found then
    raise exception 'import_export_job_not_found: no job %', p_job_id using errcode = 'no_data_found';
  end if;

  if not app.check_import_export_job_authority(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'job_actor_unauthorized: identity % lacks active membership in tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_job.job_type <> 'export' then
    raise exception 'import_export_wrong_job_type: job % is not an export job', p_job_id using errcode = 'check_violation';
  end if;

  if v_job.status not in ('pending', 'in_progress') then
    raise exception 'import_export_job_not_completable: job % is %, only a pending/in_progress export job may be completed', p_job_id, v_job.status
      using errcode = 'check_violation';
  end if;

  if not exists (select 1 from app.files f where f.id = p_result_file_id and f.tenant_id = v_job.tenant_id) then
    raise exception 'export_result_file_not_found: no file % in tenant %', p_result_file_id, v_job.tenant_id
      using errcode = 'no_data_found';
  end if;

  update app.jobs
  set status = 'completed', result_file_id = p_result_file_id, total_rows = p_row_count, processed_rows = p_row_count, completed_at = now()
  where job_id = p_job_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'complete_export_job',
    'app.jobs', p_job_id, 'success', null, null, jsonb_build_object('result_file_id', p_result_file_id, 'row_count', p_row_count)
  );

  return v_updated;
end;
$$;

-- The bounded retry/DLQ adapter interface (Tech Arch §32.17) -- real, tested, never
-- called against a fabricated live worker failure itself.
create function app.record_job_failure(
  p_job_id uuid,
  p_error_message text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.jobs
language plpgsql
as $$
declare
  v_job app.jobs;
  v_new_attempts integer;
  v_updated app.jobs;
begin
  select * into v_job from app.jobs where job_id = p_job_id;
  if not found then
    raise exception 'import_export_job_not_found: no job %', p_job_id using errcode = 'no_data_found';
  end if;

  if v_job.status in ('completed', 'cancelled', 'dead_letter') then
    raise exception 'import_export_job_already_terminal: job % is already %, cannot record a failure', p_job_id, v_job.status
      using errcode = 'check_violation';
  end if;

  v_new_attempts := v_job.attempts + 1;

  update app.jobs
  set attempts = v_new_attempts,
      error = p_error_message,
      status = case when v_new_attempts >= v_job.max_attempts then 'dead_letter' else 'pending' end,
      completed_at = case when v_new_attempts >= v_job.max_attempts then now() else null end
  where job_id = p_job_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_job_failure',
    'app.jobs', p_job_id, 'failure', p_error_message,
    jsonb_build_object('attempts', v_job.attempts, 'status', v_job.status),
    jsonb_build_object('attempts', v_updated.attempts, 'status', v_updated.status)
  );

  return v_updated;
end;
$$;

-- The manual replay step Tech Arch §32.11/§32.17 require -- support/Supreme authority
-- only, matching "requires a Supreme-Admin/authorized-admin action to requeue"
-- (05_DATABASE_SCHEMA_WORKSTREAM.md line 110).
create function app.requeue_dead_letter_job(
  p_job_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.jobs
language plpgsql
as $$
declare
  v_job app.jobs;
  v_updated app.jobs;
begin
  select * into v_job from app.jobs where job_id = p_job_id;
  if not found then
    raise exception 'import_export_job_not_found: no job %', p_job_id using errcode = 'no_data_found';
  end if;

  if not app.check_import_export_admin_authority(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'job_requeue_unauthorized: identity % lacks support/supreme authority over tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_job.status <> 'dead_letter' then
    raise exception 'import_export_job_not_dead_letter: job % is %, only a dead_letter job may be requeued', p_job_id, v_job.status
      using errcode = 'check_violation';
  end if;

  update app.jobs
  set status = 'pending', attempts = 0, error = null, completed_at = null
  where job_id = p_job_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'requeue_dead_letter_job',
    'app.jobs', p_job_id, 'success', null, jsonb_build_object('status', 'dead_letter'), jsonb_build_object('status', 'pending')
  );

  return v_updated;
end;
$$;

-- The OWASP-recommended CSV/formula-injection mitigation (this migration's own
-- header): a leading =, +, -, or @ is prefixed with a single quote, deliberately
-- accepting the well-known false-positive on legitimate leading-sign text (e.g. "-5")
-- as the safe default. A future export-file writer calls this per output cell -- pure
-- computation, provable without any live file-generation step.
create function app.sanitize_formula_injection(p_value text)
returns text
language sql
immutable
as $$
  select case
    when p_value ~ '^[-+=@]' then '''' || p_value
    else p_value
  end;
$$;

-- RLS. app.import_export_schemas is a broadly readable registry. app.jobs carries
-- direct-table RLS for authenticated (a job's own requester or their tenant's
-- support/Supreme authority) -- the "shared business data" precedent, not the
-- "credential" precedent, since job status is not itself secret.
-- app.import_staging_rows carries zero authenticated grant at all (raw, not-yet-
-- validated imported content), matching app.file_access_logs' precedent.
alter table app.import_export_schemas enable row level security;
alter table app.jobs enable row level security;

create policy import_export_schemas_select_all on app.import_export_schemas
for select to authenticated
using (true);

create policy jobs_select_scoped on app.jobs
for select to authenticated
using (
  app.is_supreme_admin()
  or (
    app.has_active_tenant_membership(tenant_id)
    and (requested_by_auth_user_id = auth.uid() or app.is_support_grant_authority(auth.uid(), tenant_id))
  )
);

revoke execute on all functions in schema app from public;

grant select on app.import_export_schemas to authenticated, service_role;
grant insert, update, delete on app.import_export_schemas to service_role;

grant select on app.jobs to authenticated, service_role;
grant insert, update, delete on app.jobs to service_role;

grant select, insert, update, delete on app.import_staging_rows to service_role;

grant execute on function app.check_import_export_admin_authority(uuid, uuid) to service_role;
grant execute on function app.check_import_export_job_authority(uuid, uuid) to service_role;
grant execute on function app.register_import_export_schema(text, text, text, uuid, text) to service_role;
grant execute on function app.validate_import_export_schema_definition(uuid) to service_role;
grant execute on function app.publish_import_export_schema(uuid, uuid, timestamptz, text) to service_role;
grant execute on function app.resolve_import_export_schema_columns(uuid, text) to service_role;
grant execute on function app.create_import_export_job(uuid, text, text, uuid, jsonb, text, uuid, text) to service_role;
grant execute on function app.stage_import_rows(uuid, jsonb, uuid, text) to service_role;
grant execute on function app.validate_staging_row(uuid, uuid, text) to service_role;
grant execute on function app.preview_import_job(uuid, uuid) to authenticated, service_role;
grant execute on function app.commit_import_job(uuid, boolean, uuid, text) to service_role;
grant execute on function app.cancel_import_export_job(uuid, text, uuid, text) to service_role;
grant execute on function app.acknowledge_job_cancellation(uuid, uuid, text) to service_role;
grant execute on function app.complete_export_job(uuid, uuid, integer, uuid, text) to service_role;
grant execute on function app.record_job_failure(uuid, text, uuid, text) to service_role;
grant execute on function app.requeue_dead_letter_job(uuid, uuid, text) to service_role;
grant execute on function app.sanitize_formula_injection(text) to service_role;
