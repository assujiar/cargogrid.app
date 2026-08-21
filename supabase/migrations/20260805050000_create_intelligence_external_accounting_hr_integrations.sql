-- Intelligence, Automation and Enterprise Expansion: External Accounting and
-- HR Integrations (IAE-018, CG-S14-IAE-018, Prompt 346). Fifth prompt of the
-- merged Batch 4 (`00_EXECUTION_INDEX.md` §5 revision, Prompts 342-348).
--
-- Design decisions, disclosed rather than left implicit:
--
-- 1. **Case-by-case adapters (RPD-038).** Two adapter codes seeded
--    (`external_accounting_system`, `external_hr_system`), reusing `app.
--    integration_connections`/`app.integration_connection_credentials`
--    (IAE-336) directly.
-- 2. **Field/entity ownership direction is this checkpoint's own genuine
--    contribution -- confirmed absent repository-wide before writing any
--    code (grepped for source_of_truth/ownership_direction/read_only_field/
--    external_owned -- zero hits anywhere).** `app.external_sync_entity_
--    mappings` makes "CargoGrid source-domain ownership must be explicit
--    before sync" (business rule) a HARD GATE, not a convention: every
--    ingestion/review/list RPC below refuses to act on an entity_type with
--    no active mapping row. `ownership_direction` ('cargogrid_source'
--    means CargoGrid leads and any external divergence is flagged a
--    conflict; 'external_source' means the external system leads and
--    CargoGrid records a read-only reference, matching this prompt's own
--    Alternative flow verbatim: "Accounting system remains source for a
--    subset during transition; CargoGrid records read-only references and
--    exceptions"; 'bidirectional' flags any divergence for review either
--    way) governs how `app.record_external_sync_snapshot` classifies a
--    diff.
-- 3. **This checkpoint NEVER writes to `app.employees`, `app.employee_
--    lifecycle_versions`, `app.finance_accounts`, or `app.finance_journals`
--    -- structurally, not by convention.** No function in this migration
--    grants INSERT/UPDATE/DELETE on any of those tables (grep-verified,
--    recorded here per this session's own established disclosure
--    discipline). This is the literal reading of "external sync cannot
--    silently overwrite posted Finance or finalized HR/payroll records" --
--    mirrors HRT-282's own "Payroll NEVER writes to any app.finance_*
--    table directly" boundary discipline, applied here even more strictly:
--    this checkpoint has no counterpart "acknowledge and apply" RPC at
--    all yet (disclosed, deferred, §8 of the build log) -- every inbound
--    sync stops at evidence + conflict-flagging, a human always acts
--    through HRIS/Finance's own existing, unmodified update paths
--    separately, off-platform for now.
-- 4. **Entity linking is ALWAYS explicit, never best-effort/auto-matched**
--    -- a deliberate divergence from IAE-016/017's own best-effort
--    reference-field correlation (`app.match_logistics_partner_event_to_
--    shipment`/`app.match_finance_payment_gateway_event_to_transaction`).
--    Employee identity linking carries higher misattribution risk than a
--    shipment/bank-transaction reference match; `app.link_external_sync_
--    entity` requires a human to explicitly assert the external_entity_id
--    <-> internal record correspondence once, then every later snapshot
--    for that external_entity_id resolves through the stored link.
-- 5. **"Dry-run mapping and validation" (business rule) is an inherent
--    property of this design, not a separate mode -- confirmed already
--    adequate as-is, not a scope cut.** Because ingestion NEVER writes to
--    a domain table (decision 3), every sync IS a dry run in the sense
--    that matters: nothing commits to HRIS/Finance truth. Field diffs and
--    conflict flags are computed and recorded as real, queryable evidence
--    before any human decision, satisfying the business requirement
--    without a separate preview code path.
-- 6. **One shared job type, `external_sync`**, covering BOTH entity types
--    via an `entity_type` payload discriminator -- mirrors IAE-016's own
--    `logistics_partner_sync` precedent (one job type spanning 4 adapter
--    categories), not a job type per entity type. Widened in the standing
--    four-place lockstep (`app.jobs_job_type_check`, `app.generic_job_
--    types()`, `GENERIC_JOB_TYPES`, `IMPORT_EXPORT_JOB_TYPES`).
-- 7. **Authority is entity-type-dispatched**: `app.check_external_sync_
--    entity_authority(p_action, p_entity_type, ...)` resolves `employee`
--    to the `HRS` module and `gl_account` to the `FIN` module, mirroring
--    IAE-017's own "FIN:Edit, not instance-level" divergence for the
--    accounting side, and the equivalent HRS convention for the HR side.
--    Connection/mapping setup remains `INTHUB:Configure`.
-- 8. **Cost metering (`RPD-028`) does not apply here** -- unlike IAE-014/
--    015/016/017, this prompt's own business rules cite no per-call
--    provider billing; `app.compute_provider_billed_amount` is not reused
--    (disclosed, not an oversight).
-- 9. Per `ERR-2026-004`: this migration carries its own explicit `revoke
--    execute on all functions in schema app from public` before its final
--    grants.

-- ===========================================================================
-- Adapter code registry helper (design decision 1)
-- ===========================================================================

create function app.external_sync_adapter_codes()
returns text[]
language sql
immutable
as $$
  select array['external_accounting_system', 'external_hr_system']::text[];
$$;

-- ===========================================================================
-- Entity-type-dispatched authority (design decision 7)
-- ===========================================================================

create function app.check_external_sync_entity_authority(p_action text, p_entity_type text, p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language plpgsql
stable
as $$
declare
  v_module text;
begin
  v_module := case p_entity_type when 'employee' then 'HRS' when 'gl_account' then 'FIN' else null end;
  if v_module is null then
    return false;
  end if;
  return (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, v_module, p_action)).allowed;
end;
$$;

comment on function app.check_external_sync_entity_authority is
  'IAE-018: dispatches employee -> HRS, gl_account -> FIN, mirroring IAE-017''s own "FIN:Edit, not instance-level" trigger-authority divergence, extended to a second module.';

-- ===========================================================================
-- Ownership-direction mapping (design decisions 2, 5) -- the hard gate.
-- ===========================================================================

create table app.external_sync_entity_mappings (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  adapter_code text not null references app.integration_adapters (code),
  entity_type text not null,
  ownership_direction text not null,
  status text not null default 'active',
  notes text,
  created_by_auth_user_id uuid references auth.users (id),
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  record_version integer not null default 1,
  constraint external_sync_entity_mappings_entity_type_check check (entity_type in ('employee', 'gl_account')),
  constraint external_sync_entity_mappings_ownership_check check (ownership_direction in ('cargogrid_source', 'external_source', 'bidirectional')),
  constraint external_sync_entity_mappings_status_check check (status in ('active', 'inactive')),
  constraint external_sync_entity_mappings_unique unique (tenant_id, adapter_code, entity_type)
);

comment on table app.external_sync_entity_mappings is
  'IAE-018: makes "CargoGrid source-domain ownership must be explicit before sync" a structural gate -- app.record_external_sync_snapshot refuses to run for an entity_type with no active row here.';

create function app.set_external_sync_entity_mapping(
  p_tenant_id uuid,
  p_adapter_code text,
  p_entity_type text,
  p_ownership_direction text,
  p_notes text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.external_sync_entity_mappings
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_row app.external_sync_entity_mappings;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'INTHUB', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks INTHUB:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not (p_adapter_code = any (app.external_sync_adapter_codes())) then
    raise exception 'external_sync_invalid_adapter_code: % is not a recognized external accounting/HR adapter', p_adapter_code using errcode = 'check_violation';
  end if;
  if p_entity_type not in ('employee', 'gl_account') then
    raise exception 'external_sync_invalid_entity_type: % is not one of employee/gl_account', p_entity_type using errcode = 'check_violation';
  end if;
  if p_ownership_direction not in ('cargogrid_source', 'external_source', 'bidirectional') then
    raise exception 'external_sync_invalid_ownership_direction: % is not one of cargogrid_source/external_source/bidirectional', p_ownership_direction using errcode = 'check_violation';
  end if;

  insert into app.external_sync_entity_mappings (tenant_id, adapter_code, entity_type, ownership_direction, notes, created_by_auth_user_id, created_by)
  values (p_tenant_id, p_adapter_code, p_entity_type, p_ownership_direction, p_notes, p_actor_auth_user_id, p_actor_label)
  on conflict (tenant_id, adapter_code, entity_type) do update
    set ownership_direction = excluded.ownership_direction, notes = excluded.notes, status = 'active', updated_at = now(), record_version = app.external_sync_entity_mappings.record_version + 1
  returning * into v_row;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'set_external_sync_entity_mapping',
    'app.external_sync_entity_mappings', v_row.id, 'success', null, null, to_jsonb(v_row)
  );

  return v_row;
end;
$$;

create function app.get_external_sync_entity_mapping(p_tenant_id uuid, p_adapter_code text, p_entity_type text)
returns app.external_sync_entity_mappings
language sql
stable
as $$
  select * from app.external_sync_entity_mappings
  where tenant_id = p_tenant_id and adapter_code = p_adapter_code and entity_type = p_entity_type and status = 'active';
$$;

-- ===========================================================================
-- Explicit entity linking (design decision 4)
-- ===========================================================================

create table app.external_sync_entity_links (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  adapter_code text not null references app.integration_adapters (code),
  entity_type text not null,
  external_entity_id text not null,
  internal_record_id uuid not null,
  linked_by_auth_user_id uuid references auth.users (id),
  linked_by text,
  linked_at timestamptz not null default now(),
  constraint external_sync_entity_links_entity_type_check check (entity_type in ('employee', 'gl_account')),
  constraint external_sync_entity_links_unique unique (tenant_id, adapter_code, entity_type, external_entity_id)
);

comment on table app.external_sync_entity_links is
  'IAE-018: the ONLY correlation mechanism -- no best-effort auto-matching (design decision 4). internal_record_id is a soft reference (app.employees.master_record_id or app.finance_accounts.id depending on entity_type), never a foreign key, the same polymorphic-reference posture app.files.record_id already established.';

create index external_sync_entity_links_internal_record_idx on app.external_sync_entity_links (tenant_id, entity_type, internal_record_id);

create function app.link_external_sync_entity(
  p_tenant_id uuid,
  p_adapter_code text,
  p_entity_type text,
  p_external_entity_id text,
  p_internal_record_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.external_sync_entity_links
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_mapping app.external_sync_entity_mappings;
  v_row app.external_sync_entity_links;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.check_external_sync_entity_authority('Edit', p_entity_type, p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks entity-appropriate Edit authority for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_mapping := app.get_external_sync_entity_mapping(p_tenant_id, p_adapter_code, p_entity_type);
  if v_mapping.id is null then
    raise exception 'external_sync_mapping_not_configured: no active ownership-direction mapping for adapter % / entity_type % -- configure one via app.set_external_sync_entity_mapping before linking', p_adapter_code, p_entity_type
      using errcode = 'check_violation';
  end if;

  if p_entity_type = 'employee' then
    if not exists (select 1 from app.employees where master_record_id = p_internal_record_id and tenant_id = p_tenant_id) then
      raise exception 'external_sync_internal_record_not_found: no employee % for tenant %', p_internal_record_id, p_tenant_id using errcode = 'no_data_found';
    end if;
  elsif p_entity_type = 'gl_account' then
    if not exists (select 1 from app.finance_accounts where id = p_internal_record_id and tenant_id = p_tenant_id) then
      raise exception 'external_sync_internal_record_not_found: no gl account % for tenant %', p_internal_record_id, p_tenant_id using errcode = 'no_data_found';
    end if;
  end if;

  insert into app.external_sync_entity_links (tenant_id, adapter_code, entity_type, external_entity_id, internal_record_id, linked_by_auth_user_id, linked_by)
  values (p_tenant_id, p_adapter_code, p_entity_type, p_external_entity_id, p_internal_record_id, p_actor_auth_user_id, p_actor_label)
  on conflict (tenant_id, adapter_code, entity_type, external_entity_id) do update
    set internal_record_id = excluded.internal_record_id, linked_by_auth_user_id = excluded.linked_by_auth_user_id, linked_by = excluded.linked_by, linked_at = now()
  returning * into v_row;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'link_external_sync_entity',
    'app.external_sync_entity_links', v_row.id, 'success', null, null, to_jsonb(v_row)
  );

  return v_row;
end;
$$;

-- ===========================================================================
-- Inbound sync evidence + read-only field-diff (design decisions 2, 3, 5)
-- ===========================================================================

create table app.external_sync_records (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  connection_id uuid not null references app.integration_connections (id),
  entity_type text not null,
  external_entity_id text not null,
  internal_record_id uuid,
  match_status text not null default 'unmatched',
  raw_payload jsonb not null,
  field_diffs jsonb,
  conflict_status text not null default 'no_conflict',
  review_notes text,
  reviewed_by_auth_user_id uuid references auth.users (id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint external_sync_records_entity_type_check check (entity_type in ('employee', 'gl_account')),
  constraint external_sync_records_match_status_check check (match_status in ('matched', 'unmatched')),
  constraint external_sync_records_conflict_status_check check (conflict_status in ('no_conflict', 'conflicts_detected', 'reviewed', 'dismissed')),
  constraint external_sync_records_payload_check check (app.validate_config_value(raw_payload))
);

comment on table app.external_sync_records is
  'IAE-018: append-only inbound external-record evidence, NEVER written back to app.employees/app.finance_accounts (design decision 3). field_diffs is a read-only comparison against the current internal record at ingestion time, classified per the entity_type''s own active ownership_direction mapping.';

create index external_sync_records_tenant_idx on app.external_sync_records (tenant_id, created_at desc);
create index external_sync_records_internal_record_idx on app.external_sync_records (internal_record_id) where internal_record_id is not null;

create function app.record_external_sync_snapshot(
  p_tenant_id uuid,
  p_connection_id uuid,
  p_adapter_code text,
  p_entity_type text,
  p_external_entity_id text,
  p_raw_payload jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.external_sync_records
language plpgsql
as $$
declare
  v_mapping app.external_sync_entity_mappings;
  v_link app.external_sync_entity_links;
  v_current jsonb;
  v_field text;
  v_internal_value jsonb;
  v_external_value jsonb;
  v_diffs jsonb := '{}'::jsonb;
  v_conflict_status text := 'no_conflict';
  v_row app.external_sync_records;
begin
  if not app.check_external_sync_entity_authority('Edit', p_entity_type, p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks entity-appropriate Edit authority for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_mapping := app.get_external_sync_entity_mapping(p_tenant_id, p_adapter_code, p_entity_type);
  if v_mapping.id is null then
    raise exception 'external_sync_mapping_not_configured: no active ownership-direction mapping for adapter % / entity_type %', p_adapter_code, p_entity_type
      using errcode = 'check_violation';
  end if;

  select * into v_link from app.external_sync_entity_links
  where tenant_id = p_tenant_id and adapter_code = p_adapter_code and entity_type = p_entity_type and external_entity_id = p_external_entity_id;

  if found then
    if p_entity_type = 'employee' then
      select jsonb_build_object('fullName', e.full_name, 'workEmail', e.work_email, 'employmentType', e.employment_type, 'positionTitle', e.position_title, 'hireDate', e.hire_date)
      into v_current from app.employees e where e.master_record_id = v_link.internal_record_id;
    elsif p_entity_type = 'gl_account' then
      select jsonb_build_object('code', a.code, 'name', a.name, 'accountType', a.account_type, 'normalBalance', a.normal_balance, 'status', a.status)
      into v_current from app.finance_accounts a where a.id = v_link.internal_record_id;
    end if;

    if v_current is not null then
      for v_field in select jsonb_object_keys(v_current) loop
        v_internal_value := v_current -> v_field;
        v_external_value := p_raw_payload -> v_field;
        if v_external_value is not null and v_external_value is distinct from v_internal_value then
          v_diffs := v_diffs || jsonb_build_object(v_field, jsonb_build_object('internal', v_internal_value, 'external', v_external_value));
        end if;
      end loop;
    end if;

    if v_diffs <> '{}'::jsonb then
      if v_mapping.ownership_direction in ('cargogrid_source', 'bidirectional') then
        v_conflict_status := 'conflicts_detected';
      end if;
      -- ownership_direction = 'external_source': divergence is EXPECTED (the
      -- external system leads), recorded as a read-only reference, never
      -- flagged as a conflict -- the prompt's own Alternative flow verbatim.
    end if;

    insert into app.external_sync_records (tenant_id, connection_id, entity_type, external_entity_id, internal_record_id, match_status, raw_payload, field_diffs, conflict_status)
    values (p_tenant_id, p_connection_id, p_entity_type, p_external_entity_id, v_link.internal_record_id, 'matched', p_raw_payload, nullif(v_diffs, '{}'::jsonb), v_conflict_status)
    returning * into v_row;
  else
    insert into app.external_sync_records (tenant_id, connection_id, entity_type, external_entity_id, internal_record_id, match_status, raw_payload, field_diffs, conflict_status)
    values (p_tenant_id, p_connection_id, p_entity_type, p_external_entity_id, null, 'unmatched', p_raw_payload, null, 'no_conflict')
    returning * into v_row;
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'record_external_sync_snapshot',
    'app.external_sync_records', v_row.id, 'success', null, null,
    jsonb_build_object('entity_type', v_row.entity_type, 'match_status', v_row.match_status, 'conflict_status', v_row.conflict_status)
  );

  return v_row;
end;
$$;

comment on function app.record_external_sync_snapshot is
  'IAE-018: NEVER writes to app.employees/app.finance_accounts (design decision 3) -- read-only comparison only. A bounded, disclosed field list is compared per entity_type (never a blind generic diff over arbitrary keys, per RPD-038''s "no generic connector claim" business rule).';

create function app.review_external_sync_conflict(
  p_record_id uuid,
  p_decision text,
  p_notes text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.external_sync_records
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_record app.external_sync_records;
  v_row app.external_sync_records;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_decision not in ('reviewed', 'dismissed') then
    raise exception 'external_sync_invalid_decision: % is not one of reviewed/dismissed', p_decision using errcode = 'check_violation';
  end if;

  select * into v_record from app.external_sync_records where id = p_record_id;
  if not found then
    raise exception 'external_sync_record_not_found: %', p_record_id using errcode = 'no_data_found';
  end if;

  if not app.check_external_sync_entity_authority('Edit', v_record.entity_type, v_record.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks entity-appropriate Edit authority for tenant %', p_actor_auth_user_id, v_record.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.external_sync_records
  set conflict_status = p_decision, review_notes = p_notes, reviewed_by_auth_user_id = p_actor_auth_user_id, reviewed_at = now()
  where id = p_record_id
  returning * into v_row;

  perform app.capture_audit_event(
    v_record.tenant_id, p_actor_auth_user_id, p_actor_label, 'review_external_sync_conflict',
    'app.external_sync_records', v_row.id, 'success', null, to_jsonb(v_record), to_jsonb(v_row)
  );

  return v_row;
end;
$$;

create function app.list_external_sync_records_for_tenant(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_entity_type text default null,
  p_conflict_status text default null,
  p_limit integer default 50
)
returns setof app.external_sync_records
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_entity_type is not null and not app.check_external_sync_entity_authority('View', p_entity_type, p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks entity-appropriate View authority for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_entity_type is null and not ((app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'View')).allowed or (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'FIN', 'View')).allowed) then
    raise exception 'insufficient_authority: identity % lacks HRS:View or FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_conflict_status is not null and p_conflict_status not in ('no_conflict', 'conflicts_detected', 'reviewed', 'dismissed') then
    raise exception 'external_sync_invalid_conflict_status: % is not a recognized conflict_status', p_conflict_status using errcode = 'check_violation';
  end if;
  if p_limit is null or p_limit <= 0 or p_limit > 200 then
    raise exception 'external_sync_invalid_limit: limit must be between 1 and 200' using errcode = 'check_violation';
  end if;

  return query
  select * from app.external_sync_records
  where tenant_id = p_tenant_id
    and (p_entity_type is null or entity_type = p_entity_type)
    and (p_conflict_status is null or conflict_status = p_conflict_status)
  order by created_at desc
  limit p_limit;
end;
$$;

-- ===========================================================================
-- Poll/sync trigger (design decisions 3, 6, 7)
-- ===========================================================================

create function app.trigger_external_sync(
  p_tenant_id uuid,
  p_connection_id uuid,
  p_entity_type text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.jobs
language plpgsql
as $$
declare
  v_conn app.integration_connections;
begin
  if not app.check_external_sync_entity_authority('Edit', p_entity_type, p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks entity-appropriate Edit authority for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_conn from app.integration_connections where id = p_connection_id and tenant_id = p_tenant_id;
  if not found or not (v_conn.adapter_code = any (app.external_sync_adapter_codes())) then
    raise exception 'external_sync_connection_not_found: %', p_connection_id using errcode = 'no_data_found';
  end if;
  if not app.check_integration_connection_active(p_connection_id) then
    raise exception 'external_sync_connection_not_active: connection % is not active', p_connection_id using errcode = 'check_violation';
  end if;

  if (app.get_external_sync_entity_mapping(p_tenant_id, v_conn.adapter_code, p_entity_type)).id is null then
    raise exception 'external_sync_mapping_not_configured: no active ownership-direction mapping for adapter % / entity_type %', v_conn.adapter_code, p_entity_type
      using errcode = 'check_violation';
  end if;

  return app.enqueue_job(
    p_tenant_id, 'external_sync', jsonb_build_object('connection_id', p_connection_id, 'adapter_code', v_conn.adapter_code, 'entity_type', p_entity_type),
    0, 'external-sync:' || p_connection_id::text || ':' || p_entity_type || ':' || to_char(date_trunc('minute', now()), 'YYYYMMDDHH24MI'),
    3, p_actor_auth_user_id, p_actor_label
  );
end;
$$;

comment on function app.trigger_external_sync is
  'IAE-018: the real third caller of app.check_integration_connection_active (IAE-336), after IAE-016 and IAE-017. Refuses to enqueue without an active ownership-direction mapping (design decision 2''s own hard gate, checked again here since the poll worker itself has no actor-authority context of its own).';

-- ===========================================================================
-- Real client reads (mirrors app.get_finance_provider_dispatch_info /
-- app.get_finance_provider_connection_for_sync exactly).
-- ===========================================================================

create function app.get_external_sync_connection_for_sync(p_connection_id uuid)
returns table (tenant_id uuid, adapter_code text, connection_status text, connection_config jsonb)
language sql
stable
as $$
  select ic.tenant_id, ic.adapter_code, ic.status, ic.config
  from app.integration_connections ic
  where ic.id = p_connection_id;
$$;

comment on function app.get_external_sync_connection_for_sync is
  'IAE-018: the real poll worker''s own actor-authority-free read (trigger authority was already checked once, at app.trigger_external_sync time) -- mirrors app.get_finance_provider_connection_for_sync (IAE-017) exactly.';

create function app.get_external_sync_credential(p_connection_id uuid)
returns text
language sql
stable
as $$
  select credential_value from app.integration_connection_credentials where connection_id = p_connection_id;
$$;

-- ===========================================================================
-- Real adapter seed (design decision 1)
-- ===========================================================================

insert into app.integration_adapters (code, name, category, registered_by) values
  ('external_accounting_system', 'External Accounting/ERP System', 'financial', 'phase-09-foundation'),
  ('external_hr_system', 'External HR/HRIS System', 'hr_workforce', 'phase-09-foundation');

-- ===========================================================================
-- app.jobs job_type widening (design decision 6) -- current full list
-- (verified against 20260805040000's own the most recent `drop constraint
-- jobs_job_type_check`) carried forward verbatim, plus this checkpoint's
-- own one new value.
-- ===========================================================================

alter table app.jobs drop constraint jobs_job_type_check;
alter table app.jobs add constraint jobs_job_type_check check (
  job_type in (
    'import', 'export', 'report_generation', 'notification_batch', 'webhook_retry', 'document_generation',
    'dashboard_refresh', 'loyalty_expiration', 'recurring_billing', 'integration_sync',
    'route_load_planning', 'print_label', 'roster_generation', 'leave_accrual', 'leave_carry_forward_expiry',
    'payroll_calculation', 'training_certificate_expiry', 'training_certificate_expiry_reminder',
    'ticket_sla_evaluation', 'kb_article_expiry', 'ticket_escalation_evaluation', 'loyalty_expiry_sweep',
    'automation_action_execution', 'logistics_partner_sync', 'finance_bank_feed_sync', 'external_sync'
  )
);

comment on constraint jobs_job_type_check on app.jobs is
  'IAE-018: widened to add ''external_sync'' -- one shared job type spanning both employee and gl_account entity types (entity_type carried in the payload), mirroring IAE-016''s own logistics_partner_sync precedent rather than one job type per entity type. Kept set-equal with app.generic_job_types() by the standing ATW-031 drift-gate assertion (scripts/db-tests/background-job.sql).';

create or replace function app.generic_job_types()
returns text[]
language sql
immutable
set search_path = app, pg_temp
as $$
  select array[
    'report_generation', 'notification_batch', 'webhook_retry', 'document_generation',
    'dashboard_refresh', 'loyalty_expiration', 'recurring_billing', 'integration_sync',
    'route_load_planning', 'print_label', 'roster_generation', 'leave_accrual', 'leave_carry_forward_expiry',
    'payroll_calculation', 'training_certificate_expiry', 'training_certificate_expiry_reminder',
    'ticket_sla_evaluation', 'kb_article_expiry', 'ticket_escalation_evaluation', 'loyalty_expiry_sweep',
    'automation_action_execution', 'logistics_partner_sync', 'finance_bank_feed_sync', 'external_sync'
  ]::text[];
$$;

-- ===========================================================================
-- RLS
-- ===========================================================================

alter table app.external_sync_entity_mappings enable row level security;
alter table app.external_sync_entity_links enable row level security;
alter table app.external_sync_records enable row level security;

-- No direct authenticated grant on any of the three tables -- the only read
-- paths are app.get_external_sync_entity_mapping (service_role) and
-- app.list_external_sync_records_for_tenant (entity-dispatched View-gated),
-- mirroring every prior Batch 4 capability's own posture.

-- ===========================================================================
-- Grants
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant select, insert, update on app.external_sync_entity_mappings to service_role;
grant select, insert, update on app.external_sync_entity_links to service_role;
grant select, insert, update on app.external_sync_records to service_role;

grant execute on function app.external_sync_adapter_codes() to authenticated, service_role;
grant execute on function app.check_external_sync_entity_authority(text, text, uuid, uuid) to service_role;
grant execute on function app.set_external_sync_entity_mapping(uuid, text, text, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.get_external_sync_entity_mapping(uuid, text, text) to service_role;
grant execute on function app.link_external_sync_entity(uuid, text, text, text, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.record_external_sync_snapshot(uuid, uuid, text, text, text, jsonb, uuid, text) to service_role;
grant execute on function app.review_external_sync_conflict(uuid, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.list_external_sync_records_for_tenant(uuid, uuid, text, text, integer) to authenticated, service_role;
grant execute on function app.trigger_external_sync(uuid, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.get_external_sync_connection_for_sync(uuid) to service_role;
grant execute on function app.get_external_sync_credential(uuid) to service_role;
