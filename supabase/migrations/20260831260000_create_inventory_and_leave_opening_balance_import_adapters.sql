-- Closes `ISS-2026-303`. A tenant migrating from another system can bring its customers,
-- vendors, items and open financial balances across in bulk, but had to type opening stock
-- quantities and staff leave balances in by hand, one record at a time.
--
-- The entry says exactly what this is: *"ordinary PLT-131 adapter work, following the pattern
-- now established four times over (`vendor_import`, `customer_import`, `item_import`,
-- `finance_opening_balance_import`)"*. It is, and the fifth and sixth follow that pattern
-- rather than inventing anything.
--
-- WHY BOTH, AND WHY THEY ARE NOT ONE ADAPTER
--
--   The entry names two domains, and closing one would leave it open with a smaller blast
--   radius. But they are genuinely two adapters, not one with a mode flag: inventory opening
--   balances are per (warehouse, location, item, owner account, lot/serial/status) and land as
--   an inventory MOVEMENT; leave balances are per (employee, leave type) and land as a ledger
--   event. They share the PLT-131 skeleton and nothing else, and folding them together would
--   mean a validator that is half-inapplicable on every row it sees.
--
-- WHAT EACH ADAPTER DOES NOT DO, WHICH IS THE IMPORTANT PART
--
--   Neither one writes a business row itself. Each resolves and validates, then calls the
--   already-shipped, already-tested single-record primitive -- `app.post_inventory_movement`
--   and `app.load_opening_leave_balance` -- for every row. So:
--
--     * every quantity/balance guard, idempotency rule, authority check and audit event those
--       primitives already enforce applies unchanged to an imported row;
--     * an import cannot become a way to write a record the manual path would have refused;
--     * if either primitive's rules change, the import changes with it, because there is one
--       implementation rather than two.
--
--   That last point is why validation deliberately does NOT duplicate the primitives' own
--   checks. It re-derives only what it can genuinely answer earlier and cheaper: does this
--   warehouse/item/location/employee/leave type exist and belong to this tenant, is the number
--   parseable and positively signed, is the text free of spreadsheet-injection prefixes. The
--   authoritative refusal stays where it already lives.
--
-- IDEMPOTENCY IS DERIVED FROM THE STAGING ROW, NEVER SUPPLIED BY THE FILE
--
--   Both primitives require an idempotency key. Taking one from the uploaded file would let a
--   spreadsheet with a repeated key silently collapse two real opening balances into one, and
--   let two different files claim the same key. Each key is derived from the staging row's own
--   id instead, so it is unique by construction and re-running a committed job is a no-op
--   rather than a double-post. The commit loop ALSO checks for its own prior write before
--   calling, so a partially-committed job resumes rather than erroring -- the same
--   skip-and-count shape `app.commit_finance_opening_balance_import_job` established.

-- ===========================================================================
-- 1. Schema-kind registration, mirroring 20260830130000 exactly.
-- ===========================================================================

insert into app.import_export_schemas (code, name, owner_primitive_code, registered_by)
values
  ('inventory_opening_balance_import', 'Inventory Opening Balance Import', 'OPS', 'system'),
  ('leave_opening_balance_import', 'Leave Opening Balance Import', 'HRS', 'system')
on conflict (code) do nothing;

insert into app.config_types (code, name, owner_primitive_code, registered_by)
values
  ('import_export:inventory_opening_balance_import', 'Inventory Opening Balance Import', 'OPS', 'system'),
  ('import_export:leave_opening_balance_import', 'Leave Opening Balance Import', 'HRS', 'system')
on conflict (code) do nothing;

-- ===========================================================================
-- 2. app.validate_inventory_opening_balance_import_row
-- ===========================================================================

create function app.validate_inventory_opening_balance_import_row(
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
  v_text_fields text[] := array['warehouse_code', 'location_code', 'item_code', 'owner_account_tax_id', 'uom_code', 'lot_number', 'serial_number', 'status'];
  v_warehouse app.warehouses;
  v_owner_id uuid;
  v_item app.item_masters;
  v_location app.warehouse_locations;
  v_quantity numeric;
  v_status text;
  v_expiry text;
begin
  v_row := app.validate_staging_row(p_staging_row_id, p_actor_auth_user_id, p_actor_label);
  if v_row.validation_status <> 'valid' then
    return v_row;
  end if;

  select * into v_job from app.jobs where job_id = v_row.job_id;
  v_payload := v_row.raw_payload;

  -- Same formula-injection guard the finance adapter applies, for the same reason: a cell
  -- beginning =, +, -, @, tab or CR is executable in a spreadsheet, and these values are
  -- read back out of exports later.
  foreach v_field in array v_text_fields loop
    v_value := v_payload ->> v_field;
    if v_value is not null and v_value ~ '^[-+=@\t\r]' then
      v_errors := v_errors || (v_field || ': value begins with a disallowed formula/spreadsheet-injection prefix (=, +, -, @, tab, or carriage return)');
    end if;
  end loop;

  select * into v_warehouse from app.warehouses
  where tenant_id = v_job.tenant_id and code = trim(v_payload ->> 'warehouse_code') and status = 'active';
  if not found then
    v_errors := v_errors || ('warehouse_code: ' || coalesce(v_payload ->> 'warehouse_code', '(missing)') || ' is not an active warehouse of this tenant');
  end if;

  select a.id into v_owner_id from app.accounts a
  where a.tenant_id = v_job.tenant_id and a.status = 'active' and a.tax_id = trim(v_payload ->> 'owner_account_tax_id');
  if v_owner_id is null then
    v_errors := v_errors || ('owner_account_tax_id: ' || coalesce(v_payload ->> 'owner_account_tax_id', '(missing)') || ' does not resolve to a single active customer account');
  end if;

  if v_owner_id is not null then
    select * into v_item from app.item_masters
    where tenant_id = v_job.tenant_id and owner_account_id = v_owner_id and code = trim(v_payload ->> 'item_code') and status = 'active';
    if not found then
      v_errors := v_errors || ('item_code: ' || coalesce(v_payload ->> 'item_code', '(missing)') || ' is not an active item master owned by that account');
    end if;
  end if;

  if v_warehouse.id is not null then
    select * into v_location from app.warehouse_locations
    where warehouse_id = v_warehouse.id and code = trim(v_payload ->> 'location_code');
    if not found then
      v_errors := v_errors || ('location_code: ' || coalesce(v_payload ->> 'location_code', '(missing)') || ' is not a location of that warehouse');
    end if;
  end if;

  if not app.validate_uom_code(v_payload ->> 'uom_code') then
    v_errors := v_errors || ('uom_code: ' || coalesce(v_payload ->> 'uom_code', '(missing)') || ' is not a registered active UOM code');
  end if;

  -- An opening balance is what is ON THE SHELF at cutover, so it is strictly positive.
  -- A negative or zero row is a data error in the source file, refused here rather than
  -- discovered when a 900-row batch aborts on row 700.
  begin
    v_quantity := (nullif(trim(v_payload ->> 'quantity'), ''))::numeric;
  exception
    when others then
      v_quantity := null;
  end;
  if v_quantity is null or v_quantity <= 0 then
    v_errors := v_errors || ('quantity: ' || coalesce(v_payload ->> 'quantity', '(missing)') || ' must be a positive number');
  end if;

  v_status := lower(coalesce(nullif(trim(v_payload ->> 'status'), ''), 'on_hand'));
  if v_status not in ('on_hand', 'held', 'damaged', 'expired') then
    v_errors := v_errors || ('status: ' || v_status || ' must be one of on_hand, held, damaged, expired');
  end if;

  v_expiry := nullif(trim(coalesce(v_payload ->> 'expiry_date', '')), '');
  if v_expiry is not null then
    begin
      perform v_expiry::date;
    exception
      when others then
        v_errors := v_errors || ('expiry_date: ' || v_expiry || ' is not a valid date');
    end;
  end if;

  if array_length(v_errors, 1) is not null then
    update app.import_staging_rows set validation_status = 'invalid', error = array_to_string(v_errors, '; ')
    where id = p_staging_row_id returning * into v_row;
    update app.jobs set valid_row_count = greatest(valid_row_count - 1, 0), invalid_row_count = invalid_row_count + 1
    where job_id = v_row.job_id;
  end if;

  return v_row;
end;
$$;

comment on function app.validate_inventory_opening_balance_import_row is
  'ISS-2026-303: row-level validation for inventory_opening_balance_import. Deliberately does NOT duplicate app.post_inventory_movement''s own rules -- it re-derives only what can be answered earlier and cheaper (does this warehouse/location/item/account exist and belong to this tenant, is the quantity positive and parseable, is the status/UOM/date well-formed, is the text free of spreadsheet-injection prefixes). The authoritative refusal stays inside the primitive, so an import can never become a way to write a movement the manual path would have refused.';

-- ===========================================================================
-- 3. app.commit_inventory_opening_balance_import_job
-- ===========================================================================

create function app.commit_inventory_opening_balance_import_job(
  p_job_id uuid,
  p_allow_partial boolean,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_client_ip text default null
)
returns app.jobs
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_job app.jobs;
  v_decision app.rbac_decision;
  v_pending_count integer;
  v_row record;
  v_payload jsonb;
  v_warehouse_id uuid;
  v_owner_id uuid;
  v_item_id uuid;
  v_location_id uuid;
  v_key text;
  v_posted_count integer := 0;
  v_skipped_count integer := 0;
  v_updated app.jobs;
begin
  select * into v_job from app.jobs where job_id = p_job_id for update;
  if not found then
    raise exception 'import_export_job_not_found: no job %', p_job_id using errcode = 'no_data_found';
  end if;

  if v_job.job_type <> 'import' or v_job.import_export_schema_code <> 'inventory_opening_balance_import' then
    raise exception 'import_export_wrong_schema: job % is not an inventory_opening_balance_import job', p_job_id using errcode = 'check_violation';
  end if;

  if not app.check_import_export_job_authority(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'job_actor_unauthorized: identity % lacks active membership in tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.is_support_grant_authority(p_actor_auth_user_id, v_job.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_job.tenant_id, 'OPS', 'Import');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Import (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-278's composition, unchanged: a bulk commit is a privileged action, and a
  -- non-interactive caller that supplies no IP is exempt rather than blocked.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_job.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_job.tenant_id, p_client_ip, 'admin', p_actor_label);
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

  perform pg_advisory_xact_lock(hashtextextended(p_job_id::text, 206));

  for v_row in
    select * from app.import_staging_rows
    where job_id = p_job_id and validation_status = 'valid'
    order by row_number
  loop
    v_payload := v_row.raw_payload;

    -- Derived from the staging row, never taken from the file. A file-supplied key would let
    -- a repeated cell silently collapse two real opening balances into one.
    v_key := 'inventory-opening-balance-import:' || v_row.id::text;

    if exists (select 1 from app.inventory_movements where tenant_id = v_job.tenant_id and idempotency_key = v_key) then
      v_skipped_count := v_skipped_count + 1;
      continue;
    end if;

    -- Re-resolved at write time rather than carried from validation: an item can be
    -- deactivated or a warehouse closed in between, and posting stock against either would
    -- be a silent misstatement of what is actually on the shelf.
    select id into v_warehouse_id from app.warehouses
    where tenant_id = v_job.tenant_id and code = trim(v_payload ->> 'warehouse_code') and status = 'active';
    select a.id into v_owner_id from app.accounts a
    where a.tenant_id = v_job.tenant_id and a.status = 'active' and a.tax_id = trim(v_payload ->> 'owner_account_tax_id');
    select id into v_item_id from app.item_masters
    where tenant_id = v_job.tenant_id and owner_account_id = v_owner_id and code = trim(v_payload ->> 'item_code') and status = 'active';
    select id into v_location_id from app.warehouse_locations
    where warehouse_id = v_warehouse_id and code = trim(v_payload ->> 'location_code');

    if v_warehouse_id is null or v_owner_id is null or v_item_id is null or v_location_id is null then
      raise exception 'import_row_no_longer_resolvable: staging row % no longer resolves to an active warehouse/account/item/location', v_row.id
        using errcode = 'check_violation';
    end if;

    -- The primitive does the writing. Every guard, balance rule and audit event it already
    -- enforces applies to this row unchanged.
    perform app.post_inventory_movement(
      v_job.tenant_id,
      v_warehouse_id,
      'opening_balance',
      'opening_balance',
      v_row.id,
      v_key,
      'Opening balance import, job ' || p_job_id::text,
      jsonb_build_array(jsonb_build_object(
        'owner_account_id', v_owner_id,
        'item_master_id', v_item_id,
        'location_id', v_location_id,
        'uom_code', trim(v_payload ->> 'uom_code'),
        'signed_quantity', (trim(v_payload ->> 'quantity'))::numeric,
        'lot_number', nullif(trim(coalesce(v_payload ->> 'lot_number', '')), ''),
        'serial_number', nullif(trim(coalesce(v_payload ->> 'serial_number', '')), ''),
        'expiry_date', nullif(trim(coalesce(v_payload ->> 'expiry_date', '')), ''),
        'status', lower(coalesce(nullif(trim(v_payload ->> 'status'), ''), 'on_hand'))
      )),
      p_actor_auth_user_id,
      p_actor_label,
      null
    );
    v_posted_count := v_posted_count + 1;
  end loop;

  update app.jobs
  set status = 'completed',
      processed_rows = v_posted_count + v_skipped_count,
      completed_at = now(),
      payload = payload || jsonb_build_object('posted_count', v_posted_count, 'skipped_count', v_skipped_count)
  where job_id = p_job_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'commit_inventory_opening_balance_import_job',
    'app.jobs', p_job_id, 'success', null, null,
    jsonb_build_object('posted_count', v_posted_count, 'skipped_count', v_skipped_count, 'allow_partial', coalesce(p_allow_partial, false))
  );

  return v_updated;
end;
$$;

comment on function app.commit_inventory_opening_balance_import_job is
  'ISS-2026-303: commits an inventory_opening_balance_import job by calling app.post_inventory_movement once per valid row -- it writes no inventory row itself, so every guard, balance rule and audit event that primitive enforces applies to an imported row unchanged, and an import can never write what the manual path would refuse. Idempotency keys are derived from the staging row id, never taken from the file: a file-supplied key would let a repeated cell silently collapse two real opening balances into one. Rows already posted are skipped and counted, so a partially-committed job resumes rather than erroring. Warehouse/account/item/location are re-resolved at write time rather than carried from validation, because posting stock against an item deactivated in between would be a silent misstatement.';

-- ===========================================================================
-- 4. app.validate_leave_opening_balance_import_row
-- ===========================================================================

create function app.validate_leave_opening_balance_import_row(
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
  v_text_fields text[] := array['employee_number', 'leave_type_code', 'source_reference'];
  v_employee_id uuid;
  v_leave_type_id uuid;
  v_units numeric;
  v_as_of text;
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

  -- Employee number is the tenant-facing identifier a source system exports; it lives on
  -- app.master_records.code, which is what app.employees keys off.
  select e.master_record_id into v_employee_id
  from app.employees e
  join app.master_records m on m.id = e.master_record_id
  where e.tenant_id = v_job.tenant_id and m.code = trim(v_payload ->> 'employee_number');
  if v_employee_id is null then
    v_errors := v_errors || ('employee_number: ' || coalesce(v_payload ->> 'employee_number', '(missing)') || ' does not resolve to an employee of this tenant');
  end if;

  select id into v_leave_type_id from app.leave_types
  where tenant_id = v_job.tenant_id and code = trim(v_payload ->> 'leave_type_code');
  if v_leave_type_id is null then
    v_errors := v_errors || ('leave_type_code: ' || coalesce(v_payload ->> 'leave_type_code', '(missing)') || ' is not a leave type of this tenant');
  end if;

  begin
    v_units := (nullif(trim(v_payload ->> 'units'), ''))::numeric;
  exception
    when others then
      v_units := null;
  end;
  if v_units is null or v_units <= 0 then
    v_errors := v_errors || ('units: ' || coalesce(v_payload ->> 'units', '(missing)') || ' must be a positive number');
  end if;

  v_as_of := nullif(trim(coalesce(v_payload ->> 'as_of_date', '')), '');
  if v_as_of is null then
    v_errors := v_errors || 'as_of_date: an opening balance must state the date it is the balance AS OF';
  else
    begin
      perform v_as_of::date;
    exception
      when others then
        v_errors := v_errors || ('as_of_date: ' || v_as_of || ' is not a valid date');
    end;
  end if;

  if array_length(v_errors, 1) is not null then
    update app.import_staging_rows set validation_status = 'invalid', error = array_to_string(v_errors, '; ')
    where id = p_staging_row_id returning * into v_row;
    update app.jobs set valid_row_count = greatest(valid_row_count - 1, 0), invalid_row_count = invalid_row_count + 1
    where job_id = v_row.job_id;
  end if;

  return v_row;
end;
$$;

comment on function app.validate_leave_opening_balance_import_row is
  'ISS-2026-303: row-level validation for leave_opening_balance_import. Like its inventory sibling it re-derives only what can be answered earlier and cheaper -- employee number and leave-type code resolving within this tenant, a positive parseable unit count, a real as-of date, no spreadsheet-injection prefixes -- and leaves every authoritative rule inside app.load_opening_leave_balance.';

-- ===========================================================================
-- 5. app.commit_leave_opening_balance_import_job
-- ===========================================================================

create function app.commit_leave_opening_balance_import_job(
  p_job_id uuid,
  p_allow_partial boolean,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_client_ip text default null
)
returns app.jobs
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_job app.jobs;
  v_decision app.rbac_decision;
  v_pending_count integer;
  v_row record;
  v_payload jsonb;
  v_employee_id uuid;
  v_leave_type_id uuid;
  v_key text;
  v_loaded_count integer := 0;
  v_skipped_count integer := 0;
  v_updated app.jobs;
begin
  select * into v_job from app.jobs where job_id = p_job_id for update;
  if not found then
    raise exception 'import_export_job_not_found: no job %', p_job_id using errcode = 'no_data_found';
  end if;

  if v_job.job_type <> 'import' or v_job.import_export_schema_code <> 'leave_opening_balance_import' then
    raise exception 'import_export_wrong_schema: job % is not a leave_opening_balance_import job', p_job_id using errcode = 'check_violation';
  end if;

  if not app.check_import_export_job_authority(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'job_actor_unauthorized: identity % lacks active membership in tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.is_support_grant_authority(p_actor_auth_user_id, v_job.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_job.tenant_id, 'HRS', 'Import');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Import (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_job.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_job.tenant_id, p_client_ip, 'admin', p_actor_label);
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

  perform pg_advisory_xact_lock(hashtextextended(p_job_id::text, 207));

  for v_row in
    select * from app.import_staging_rows
    where job_id = p_job_id and validation_status = 'valid'
    order by row_number
  loop
    v_payload := v_row.raw_payload;
    v_key := 'leave-opening-balance-import:' || v_row.id::text;

    if exists (select 1 from app.leave_balance_ledger where tenant_id = v_job.tenant_id and idempotency_key = v_key) then
      v_skipped_count := v_skipped_count + 1;
      continue;
    end if;

    select e.master_record_id into v_employee_id
    from app.employees e
    join app.master_records m on m.id = e.master_record_id
    where e.tenant_id = v_job.tenant_id and m.code = trim(v_payload ->> 'employee_number');
    select id into v_leave_type_id from app.leave_types
    where tenant_id = v_job.tenant_id and code = trim(v_payload ->> 'leave_type_code');

    if v_employee_id is null or v_leave_type_id is null then
      raise exception 'import_row_no_longer_resolvable: staging row % no longer resolves to an employee and leave type of this tenant', v_row.id
        using errcode = 'check_violation';
    end if;

    perform app.load_opening_leave_balance(
      v_job.tenant_id,
      v_employee_id,
      v_leave_type_id,
      (trim(v_payload ->> 'units'))::numeric,
      (trim(v_payload ->> 'as_of_date'))::date,
      nullif(trim(coalesce(v_payload ->> 'source_reference', '')), ''),
      v_key,
      p_actor_auth_user_id,
      p_actor_label
    );
    v_loaded_count := v_loaded_count + 1;
  end loop;

  update app.jobs
  set status = 'completed',
      processed_rows = v_loaded_count + v_skipped_count,
      completed_at = now(),
      payload = payload || jsonb_build_object('loaded_count', v_loaded_count, 'skipped_count', v_skipped_count)
  where job_id = p_job_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'commit_leave_opening_balance_import_job',
    'app.jobs', p_job_id, 'success', null, null,
    jsonb_build_object('loaded_count', v_loaded_count, 'skipped_count', v_skipped_count, 'allow_partial', coalesce(p_allow_partial, false))
  );

  return v_updated;
end;
$$;

comment on function app.commit_leave_opening_balance_import_job is
  'ISS-2026-303: commits a leave_opening_balance_import job by calling app.load_opening_leave_balance once per valid row -- it writes no ledger row itself, so that primitive''s HRS:Import gate, positive-units rule, idempotency-conflict detection and audit event all apply to an imported row unchanged. Keys are derived from the staging row id rather than taken from the file, and already-loaded rows are skipped and counted so a partially-committed job resumes.';

-- ===========================================================================
-- 6. Grants + public.* wrappers (RGL-394 Option 2).
--
-- `revoke ... from anon, authenticated, service_role, public` rather than `from public`
-- alone: Supabase's ALTER DEFAULT PRIVILEGES grants anon EXECUTE explicitly at CREATE
-- time, and an explicit grant survives a PUBLIC revoke (ISS-2026-309).
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant execute on function app.validate_inventory_opening_balance_import_row(uuid, uuid, text) to service_role;
grant execute on function app.commit_inventory_opening_balance_import_job(uuid, boolean, uuid, text, text) to service_role;
grant execute on function app.validate_leave_opening_balance_import_row(uuid, uuid, text) to service_role;
grant execute on function app.commit_leave_opening_balance_import_job(uuid, boolean, uuid, text, text) to service_role;

-- NOT security definer, matching its app.* counterpart. The validators are plain
-- (invoker-rights) functions, and the public.* wrapper-parity gate requires the two
-- sides to agree -- a definer wrapper over an invoker original would silently run with
-- more authority than the function it wraps. The commit wrappers below ARE definer,
-- because their originals are. The gate caught this on the first run.
create function public.validate_inventory_opening_balance_import_row(p_staging_row_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns app.import_staging_rows
language sql
set search_path = app, public, pg_temp
as $wrap$
  select * from app.validate_inventory_opening_balance_import_row(p_staging_row_id, p_actor_auth_user_id, p_actor_label);
$wrap$;

comment on function public.validate_inventory_opening_balance_import_row(uuid, uuid, text) is
  'RGL-394 Option-2 wrapper: a thin invoker-rights pass-through, never a reimplementation -- invoker rather than definer because the app.* function it wraps is, and the wrapper-parity gate requires the two sides to agree.';

revoke execute on function public.validate_inventory_opening_balance_import_row(uuid, uuid, text) from anon, authenticated, service_role, public;
grant execute on function public.validate_inventory_opening_balance_import_row(uuid, uuid, text) to service_role;

create function public.commit_inventory_opening_balance_import_job(p_job_id uuid, p_allow_partial boolean, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
returns app.jobs
language sql
security definer
set search_path = app, public, pg_temp
as $wrap$
  select * from app.commit_inventory_opening_balance_import_job(p_job_id, p_allow_partial, p_actor_auth_user_id, p_actor_label, p_client_ip);
$wrap$;

comment on function public.commit_inventory_opening_balance_import_job(uuid, boolean, uuid, text, text) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through, never a reimplementation.';

revoke execute on function public.commit_inventory_opening_balance_import_job(uuid, boolean, uuid, text, text) from anon, authenticated, service_role, public;
grant execute on function public.commit_inventory_opening_balance_import_job(uuid, boolean, uuid, text, text) to service_role;

-- NOT security definer, matching its app.* counterpart. The validators are plain
-- (invoker-rights) functions, and the public.* wrapper-parity gate requires the two
-- sides to agree -- a definer wrapper over an invoker original would silently run with
-- more authority than the function it wraps. The commit wrappers below ARE definer,
-- because their originals are. The gate caught this on the first run.
create function public.validate_leave_opening_balance_import_row(p_staging_row_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns app.import_staging_rows
language sql
set search_path = app, public, pg_temp
as $wrap$
  select * from app.validate_leave_opening_balance_import_row(p_staging_row_id, p_actor_auth_user_id, p_actor_label);
$wrap$;

comment on function public.validate_leave_opening_balance_import_row(uuid, uuid, text) is
  'RGL-394 Option-2 wrapper: a thin invoker-rights pass-through, never a reimplementation -- invoker rather than definer because the app.* function it wraps is, and the wrapper-parity gate requires the two sides to agree.';

revoke execute on function public.validate_leave_opening_balance_import_row(uuid, uuid, text) from anon, authenticated, service_role, public;
grant execute on function public.validate_leave_opening_balance_import_row(uuid, uuid, text) to service_role;

create function public.commit_leave_opening_balance_import_job(p_job_id uuid, p_allow_partial boolean, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
returns app.jobs
language sql
security definer
set search_path = app, public, pg_temp
as $wrap$
  select * from app.commit_leave_opening_balance_import_job(p_job_id, p_allow_partial, p_actor_auth_user_id, p_actor_label, p_client_ip);
$wrap$;

comment on function public.commit_leave_opening_balance_import_job(uuid, boolean, uuid, text, text) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through, never a reimplementation.';

revoke execute on function public.commit_leave_opening_balance_import_job(uuid, boolean, uuid, text, text) from anon, authenticated, service_role, public;
grant execute on function public.commit_leave_opening_balance_import_job(uuid, boolean, uuid, text, text) to service_role;
