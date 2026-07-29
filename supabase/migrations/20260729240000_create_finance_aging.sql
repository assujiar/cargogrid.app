-- Finance capability FIN-210 (AR and AP Aging, CG-S9-FIN-021)
-- Exact as-of AR/AP aging with versioned, non-overlapping bucket
-- definitions and source-reconcilable open balances.
--
-- Aging is derived, never manually editable (Prompt 210 section 24):
-- every row this checkpoint returns is computed live from FIN-196/199's
-- own `finance_ar_open_items`/`finance_ap_open_items` -- there is no
-- summary balance table anywhere in this migration a caller could write
-- to. Bucket *definitions* are the one governed, versioned object here
-- (`app.finance_aging_bucket_configs`); the aging numbers themselves are
-- never stored, only computed.
--
-- Disclosed bound (shared with FIN-209's own as-of design): each open
-- item's own real business date column bounds inclusion (`invoice_date`
-- for AR, `bill_date` for AP) -- an item dated after the as-of date is
-- excluded. `open_amount` itself reflects the item's *current* balance
-- (FIN-196/199's own generated column), not a full historical
-- reconstruction of allocation/settlement state as it stood on a past
-- as-of date -- a real, named bound, not silently claimed to be a true
-- point-in-time snapshot of every past allocation event.
--
-- Bucket boundaries are explicit, non-overlapping, contiguous and
-- versioned (Prompt 210 section 24): `app.validate_finance_aging_buckets`
-- rejects a gap, an overlap, a missing open-ended final bucket, or a
-- first bucket that does not cover zero/negative days-overdue (i.e. not
-- yet due) -- each a distinct named exception. A tenant that has never
-- configured its own buckets resolves to one disclosed system default
-- (`version = 0`), never a silent empty result.
--
-- Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration
-- carries its own explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app
-- FROM PUBLIC` statement before its final grants, the standing
-- per-migration convention since `PLT-118`.

create table app.finance_aging_bucket_configs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  entity_type text not null,
  version integer not null,
  buckets jsonb not null,
  is_active boolean not null default true,
  created_by text,
  created_at timestamptz not null default now(),
  constraint finance_aging_bucket_configs_entity_type_check check (entity_type in ('ar', 'ap')),
  constraint finance_aging_bucket_configs_version_check check (version > 0),
  constraint finance_aging_bucket_configs_unique unique (tenant_id, entity_type, version)
);

comment on table app.finance_aging_bucket_configs is
  'FIN-210: an optional, versioned, tenant-specific override of the system default aging buckets. At most one active row per (tenant_id, entity_type) -- app.resolve_finance_aging_buckets falls back to a disclosed system default (version 0) when no tenant override is active.';

create unique index finance_aging_bucket_configs_one_active on app.finance_aging_bucket_configs (tenant_id, entity_type) where is_active;

create function app.check_finance_aging_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
as $$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'FIN', p_action)).allowed;
$$;

comment on function app.check_finance_aging_authority is
  'FIN-210: FIN:Approve gates a bucket-configuration change (a governance decision, not a routine edit); FIN:View gates every read (report/summary/bucket read).';

-- Structural validation (Prompt 210 section 24/25): non-overlapping,
-- contiguous, one open-ended final bucket, first bucket covers
-- zero/negative days-overdue. Raises a distinct named exception per
-- violation, never a silent acceptance of a malformed set.
create function app.validate_finance_aging_buckets(p_buckets jsonb)
returns void
language plpgsql
as $$
declare
  v_bucket jsonb;
  v_index integer := 0;
  v_count integer;
  v_prev_max integer;
  v_min integer;
  v_max integer;
begin
  if p_buckets is null or jsonb_typeof(p_buckets) <> 'array' or jsonb_array_length(p_buckets) = 0 then
    raise exception 'finance_aging_bucket_empty: at least one bucket is required' using errcode = 'check_violation';
  end if;
  v_count := jsonb_array_length(p_buckets);

  for v_bucket in select * from jsonb_array_elements(p_buckets) loop
    v_index := v_index + 1;
    if v_bucket ->> 'label' is null or length(trim(v_bucket ->> 'label')) = 0 or v_bucket ->> 'minDays' is null then
      raise exception 'finance_aging_bucket_missing_field: bucket % is missing a required label/minDays field', v_index using errcode = 'check_violation';
    end if;
    v_min := (v_bucket ->> 'minDays')::integer;
    v_max := nullif(v_bucket ->> 'maxDays', 'null')::integer;

    if v_index = 1 and v_min > 0 then
      raise exception 'finance_aging_bucket_first_not_covering_current: the first bucket must cover zero/negative days-overdue (minDays <= 0), got %', v_min
        using errcode = 'check_violation';
    end if;
    if v_index = v_count and v_max is not null then
      raise exception 'finance_aging_bucket_last_not_open_ended: the last bucket must be open-ended (maxDays = null), got %', v_max
        using errcode = 'check_violation';
    end if;
    if v_index < v_count and v_max is null then
      raise exception 'finance_aging_bucket_gap_or_overlap: only the last bucket may be open-ended (maxDays = null), bucket % is not last', v_index
        using errcode = 'check_violation';
    end if;
    if v_max is not null and v_max < v_min then
      raise exception 'finance_aging_bucket_gap_or_overlap: bucket % has maxDays % less than minDays %', v_index, v_max, v_min
        using errcode = 'check_violation';
    end if;
    if v_index > 1 and v_min <> v_prev_max + 1 then
      raise exception 'finance_aging_bucket_gap_or_overlap: bucket % starts at % but the previous bucket ended at % (must be contiguous)', v_index, v_min, v_prev_max
        using errcode = 'check_violation';
    end if;
    v_prev_max := v_max;
  end loop;
end;
$$;

-- Governed bucket-configuration change (Prompt 210 section 24: "versioned").
-- Deactivates the tenant's own prior active version for this entity_type,
-- then inserts a brand-new, incremented version -- never edits history.
create function app.set_finance_aging_bucket_config(
  p_tenant_id uuid,
  p_entity_type text,
  p_buckets jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_aging_bucket_configs
language plpgsql
as $$
declare
  v_config app.finance_aging_bucket_configs;
  v_next_version integer;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_aging_authority('Approve', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_entity_type not in ('ar', 'ap') then
    raise exception 'finance_aging_invalid_entity_type: % is not a supported aging entity type', p_entity_type
      using errcode = 'check_violation';
  end if;

  perform app.validate_finance_aging_buckets(p_buckets);

  select coalesce(max(version), 0) + 1 into v_next_version from app.finance_aging_bucket_configs where tenant_id = p_tenant_id and entity_type = p_entity_type;

  update app.finance_aging_bucket_configs set is_active = false where tenant_id = p_tenant_id and entity_type = p_entity_type and is_active;

  insert into app.finance_aging_bucket_configs (tenant_id, entity_type, version, buckets, created_by)
  values (p_tenant_id, p_entity_type, v_next_version, p_buckets, p_actor_label)
  returning * into v_config;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'set_finance_aging_bucket_config',
    'app.finance_aging_bucket_configs', v_config.id, 'success', null, null, to_jsonb(v_config)
  );

  return v_config;
end;
$$;

-- Resolves the effective bucket set: the tenant's own active override, or
-- the disclosed system default (version 0) -- never a silent empty
-- result. version=0 is a synthesized read, not a real row.
create function app.resolve_finance_aging_buckets(p_tenant_id uuid, p_entity_type text)
returns table (version integer, buckets jsonb)
language plpgsql
stable
as $$
declare
  v_config app.finance_aging_bucket_configs;
begin
  select * into v_config from app.finance_aging_bucket_configs where tenant_id = p_tenant_id and entity_type = p_entity_type and is_active;
  if found then
    return query select v_config.version, v_config.buckets;
    return;
  end if;
  return query select 0, '[
    {"label": "Current", "minDays": -999999, "maxDays": 0},
    {"label": "1-30", "minDays": 1, "maxDays": 30},
    {"label": "31-60", "minDays": 31, "maxDays": 60},
    {"label": "61-90", "minDays": 61, "maxDays": 90},
    {"label": "90+", "minDays": 91, "maxDays": null}
  ]'::jsonb;
end;
$$;

create function app.assign_finance_aging_bucket(p_buckets jsonb, p_days_overdue integer)
returns text
language plpgsql
stable
as $$
declare
  v_bucket jsonb;
  v_min integer;
  v_max integer;
begin
  for v_bucket in select * from jsonb_array_elements(p_buckets) loop
    v_min := (v_bucket ->> 'minDays')::integer;
    v_max := nullif(v_bucket ->> 'maxDays', 'null')::integer;
    if p_days_overdue >= v_min and (v_max is null or p_days_overdue <= v_max) then
      return v_bucket ->> 'label';
    end if;
  end loop;
  raise exception 'finance_aging_bucket_no_match: no configured bucket covers % days overdue', p_days_overdue using errcode = 'check_violation';
end;
$$;

-- The as-of detail report (Prompt 210 section 21). Derived only -- every
-- row is a live read of FIN-196/199's own open items, never a stored
-- summary balance.
create function app.get_finance_aging_report(
  p_tenant_id uuid,
  p_company_id uuid,
  p_entity_type text,
  p_as_of_date date,
  p_include_held boolean,
  p_actor_auth_user_id uuid
)
returns table (
  open_item_id uuid,
  party_id uuid,
  currency text,
  original_amount numeric,
  open_amount numeric,
  document_date date,
  due_date date,
  days_overdue integer,
  bucket_label text,
  is_held boolean,
  source_document_type text,
  source_document_id uuid
)
language plpgsql
stable
as $$
declare
  v_bucket_resolution record;
begin
  if not app.check_finance_aging_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_entity_type not in ('ar', 'ap') then
    raise exception 'finance_aging_invalid_entity_type: % is not a supported aging entity type', p_entity_type
      using errcode = 'check_violation';
  end if;

  select * into v_bucket_resolution from app.resolve_finance_aging_buckets(p_tenant_id, p_entity_type);

  if p_entity_type = 'ar' then
    return query
      select
        i.id, i.customer_account_id, i.currency, i.original_amount, i.open_amount, i.invoice_date, i.due_date,
        greatest(0, p_as_of_date - i.due_date)::integer,
        app.assign_finance_aging_bucket(v_bucket_resolution.buckets, greatest(0, p_as_of_date - i.due_date)::integer),
        i.is_held, i.source_document_type, i.source_document_id
      from app.finance_ar_open_items i
      where i.tenant_id = p_tenant_id
        and (p_company_id is null or i.company_id = p_company_id)
        and i.open_amount > 0
        and i.invoice_date <= p_as_of_date
        and (p_include_held or not i.is_held)
      order by greatest(0, p_as_of_date - i.due_date) desc;
  else
    return query
      select
        i.id, i.vendor_master_id, i.currency, i.original_amount, i.open_amount, i.bill_date, i.due_date,
        greatest(0, p_as_of_date - i.due_date)::integer,
        app.assign_finance_aging_bucket(v_bucket_resolution.buckets, greatest(0, p_as_of_date - i.due_date)::integer),
        i.is_held, i.source_document_type, i.source_document_id
      from app.finance_ap_open_items i
      where i.tenant_id = p_tenant_id
        and (p_company_id is null or i.company_id = p_company_id)
        and i.open_amount > 0
        and i.bill_date <= p_as_of_date
        and (p_include_held or not i.is_held)
      order by greatest(0, p_as_of_date - i.due_date) desc;
  end if;
end;
$$;

-- The as-of summary (Prompt 210 section 21): "displays totals". Always
-- reproducible from -- and reconciles exactly to -- the detail report
-- above, since it aggregates the identical rows.
create function app.get_finance_aging_summary(
  p_tenant_id uuid,
  p_company_id uuid,
  p_entity_type text,
  p_as_of_date date,
  p_include_held boolean,
  p_actor_auth_user_id uuid
)
returns table (bucket_label text, currency text, open_amount numeric, item_count bigint)
language plpgsql
stable
as $$
begin
  return query
    select r.bucket_label, r.currency, sum(r.open_amount), count(*)
    from app.get_finance_aging_report(p_tenant_id, p_company_id, p_entity_type, p_as_of_date, p_include_held, p_actor_auth_user_id) r
    group by r.bucket_label, r.currency
    order by r.bucket_label, r.currency;
end;
$$;

create function app.list_finance_aging_bucket_configs(p_tenant_id uuid, p_entity_type text, p_actor_auth_user_id uuid)
returns setof app.finance_aging_bucket_configs
language plpgsql
stable
as $$
begin
  if not app.check_finance_aging_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_aging_bucket_configs
    where tenant_id = p_tenant_id and (p_entity_type is null or entity_type = p_entity_type)
    order by entity_type, version desc;
end;
$$;

alter table app.finance_aging_bucket_configs enable row level security;

create policy finance_aging_bucket_configs_select_scoped on app.finance_aging_bucket_configs
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable
-- revoke of PostgreSQL's PUBLIC-execute default, the standing per-migration
-- convention since PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant select on app.finance_aging_bucket_configs to authenticated, service_role;
grant insert, update, delete on app.finance_aging_bucket_configs to service_role;

grant execute on function app.check_finance_aging_authority(text, uuid, uuid) to service_role;
grant execute on function app.validate_finance_aging_buckets(jsonb) to service_role;
grant execute on function app.set_finance_aging_bucket_config(uuid, text, jsonb, uuid, text) to authenticated, service_role;
grant execute on function app.resolve_finance_aging_buckets(uuid, text) to authenticated, service_role;
grant execute on function app.assign_finance_aging_bucket(jsonb, integer) to authenticated, service_role;
grant execute on function app.get_finance_aging_report(uuid, uuid, text, date, boolean, uuid) to authenticated, service_role;
grant execute on function app.get_finance_aging_summary(uuid, uuid, text, date, boolean, uuid) to authenticated, service_role;
grant execute on function app.list_finance_aging_bucket_configs(uuid, text, uuid) to authenticated, service_role;
