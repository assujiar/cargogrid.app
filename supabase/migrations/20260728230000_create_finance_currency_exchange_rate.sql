-- Finance capability FIN-194 (Currency and Exchange Rate, CG-S9-FIN-005)
-- Governed currencies and exchange rates with exact-decimal conversion,
-- versioned sources, and deterministic rounding -- so invoices, bills,
-- payments, and journals preserve transaction and functional-currency truth
-- without silent rate changes.
--
-- Closes PLT-119's own disclosed forward reference verbatim: "display-
-- formatting currency codes only (ISO 4217) -- never an exchange rate or
-- financial figure. Real currency/FX control is a dedicated future Phase 4
-- capability" (`20260717112000_create_localization.sql`'s own comment on
-- `app.validate_currency_code`). This migration `CREATE OR REPLACE FUNCTION`s
-- that exact function (the established later-migration-extends-an-earlier-
-- one's-function pattern) so it resolves against this migration's own real
-- `app.finance_currencies` registry instead of the two-code hardcoded list
-- PLT-119 disclosed as a placeholder -- a strictly additive widening (every
-- code PLT-119 already accepted, IDR/USD, remains accepted; nothing that
-- validated before now fails), never a narrowing of any existing tenant's
-- locale/currency-display configuration. The function's own volatility
-- category changes from IMMUTABLE to STABLE (it now reads a real table) --
-- disclosed, not silently changed; Postgres does not require a CHECK
-- constraint's function to be IMMUTABLE, only that it not be VOLATILE, and
-- neither of this function's two existing CHECK-constraint call sites
-- (`app.tenant_locale_versions`, `app.users`) is used in an index expression.
--
-- Ties into FIN-191's own rounding policy directly (Prompt 191 section 6 / Prompt 194
-- section 6's own "rounding tie-in" requirement): `app.apply_finance_rounding`
-- implements the same four bounded rounding conventions
-- `app.finance_rounding_modes` (FIN-191) already catalogues, and
-- `app.convert_finance_amount` resolves the tenant's own effective
-- `finance_rounding` config (key `fx_conversion`, falling back to `default`,
-- falling back to a disclosed safe default) rather than inventing a second,
-- competing rounding mechanism.
--
-- Imports use a staged, idempotent batch (Prompt 194 section 14's own "imports use
-- staged idempotent jobs") -- a bounded, disclosed alternative to adopting the
-- full generic Import/Export Job Framework (`PLT-129`) for this one capability,
-- the same class of proportionate-effort decision `COM-151`'s own header
-- recorded for the Configurable Numbering Engine ("no sibling capability has
-- adopted it either... a bounded, disclosed alternative... without pulling in
-- the full... machinery").
--
-- Money/decimal discipline (Prompt 194 section 24, the binding rule this entire
-- phase shares): every rate/amount column is `numeric`, never `float`/`real`;
-- `app.apply_finance_rounding` is the one place rounding happens, always
-- explicit `numeric` arithmetic.
--
-- Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration carries
-- its own explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM
-- PUBLIC` statement before its final grants, the standing per-migration
-- convention since `PLT-118`.

create table app.finance_currencies (
  code text primary key,
  name text not null,
  minor_unit_precision integer not null default 2,
  is_active boolean not null default true,
  constraint finance_currencies_code_format_check check (code ~ '^[A-Z]{3}$'),
  constraint finance_currencies_precision_check check (minor_unit_precision >= 0 and minor_unit_precision <= 6)
);

comment on table app.finance_currencies is
  'FIN-194: the real, governed currency registry PLT-119''s own app.validate_currency_code header forward-referenced. minor_unit_precision is a real ISO 4217 fact (e.g. JPY=0), never a tax/legal figure.';

insert into app.finance_currencies (code, name, minor_unit_precision) values
  ('IDR', 'Indonesian Rupiah', 2),
  ('USD', 'United States Dollar', 2),
  ('SGD', 'Singapore Dollar', 2),
  ('EUR', 'Euro', 2),
  ('JPY', 'Japanese Yen', 0);

-- Widens app.validate_currency_code (PLT-119) to resolve against the real
-- registry above -- CREATE OR REPLACE, not a new function (this migration's
-- own header). Strictly additive: IDR/USD (the only two codes PLT-119 ever
-- accepted) remain accepted.
create or replace function app.validate_currency_code(p_currency text)
returns boolean
language sql
stable
as $$
  select exists (select 1 from app.finance_currencies where code = p_currency and is_active);
$$;

comment on function app.validate_currency_code is
  'PLT-119/FIN-194: real, governed ISO 4217 currency-code validation against app.finance_currencies -- widened from PLT-119''s own disclosed two-code placeholder (IDR/USD), which remains a strict subset of what this function now accepts. Display-formatting purposes only -- never an exchange rate or financial figure (unchanged from PLT-119''s own scope statement).';

-- Exact-decimal rounding conventions (mirrors FIN-191's own app.finance_rounding_modes
-- catalogue -- the same four modes, reused as the real implementation those
-- catalogue rows describe, never a second competing set).
create function app.apply_finance_rounding(p_value numeric, p_precision integer, p_mode text)
returns numeric
language plpgsql
immutable
as $$
declare
  v_scale numeric := power(10, p_precision);
  v_scaled numeric;
  v_floor numeric;
  v_diff numeric;
begin
  if p_precision < 0 or p_precision > 6 then
    raise exception 'finance_rounding_invalid_precision: precision % must be between 0 and 6', p_precision
      using errcode = 'check_violation';
  end if;

  if p_mode = 'round_half_up' then
    return round(p_value, p_precision);
  elsif p_mode = 'round_down' then
    return trunc(p_value, p_precision);
  elsif p_mode = 'round_up' then
    if p_value >= 0 then
      return ceil(p_value * v_scale) / v_scale;
    else
      return floor(p_value * v_scale) / v_scale;
    end if;
  elsif p_mode = 'round_half_even' then
    v_scaled := p_value * v_scale;
    v_floor := floor(v_scaled);
    v_diff := v_scaled - v_floor;
    if v_diff < 0.5 then
      return v_floor / v_scale;
    elsif v_diff > 0.5 then
      return (v_floor + 1) / v_scale;
    elsif mod(v_floor::bigint, 2) = 0 then
      return v_floor / v_scale;
    else
      return (v_floor + 1) / v_scale;
    end if;
  else
    raise exception 'finance_rounding_invalid_mode: % is not a registered rounding mode', p_mode
      using errcode = 'check_violation';
  end if;
end;
$$;

comment on function app.apply_finance_rounding is
  'FIN-194: the one real implementation of the four rounding conventions FIN-191''s own app.finance_rounding_modes catalogues (round_half_up/round_half_even/round_down/round_up). Never a tax/legal rate -- a math convention only.';

-- tenant_id null = a platform-wide default rate, resolved only when no
-- tenant-specific approved rate covers the requested instant (the same
-- global-fallback shape PLT-121's own config engine already established for
-- its own 6-level precedence, narrowed here to a 2-level tenant/global one
-- since exchange rates have no company/branch/role/user precedence need).
create table app.finance_exchange_rates (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references app.tenants (id),
  rate_type text not null default 'spot',
  source_currency text not null,
  target_currency text not null,
  rate numeric(24, 10) not null,
  source text not null default 'manual',
  effective_from timestamptz not null,
  effective_to timestamptz,
  status text not null default 'draft',
  approved_by text,
  approved_at timestamptz,
  import_batch_id uuid,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint finance_exchange_rates_status_check check (status in ('draft', 'approved', 'archived')),
  constraint finance_exchange_rates_rate_positive_check check (rate > 0),
  constraint finance_exchange_rates_currency_pair_check check (source_currency <> target_currency),
  constraint finance_exchange_rates_effective_order_check check (effective_to is null or effective_to > effective_from)
);

comment on table app.finance_exchange_rates is
  'FIN-194: a versioned exchange-rate quote. draft -> approved -> archived (never edited in place once approved -- a correction is a new draft approved over a narrowed/ended window, the same "versioned, never edited in place" discipline FIN-191/192/193 all already established). tenant_id null = platform-wide default, resolved only as a fallback.';

create index finance_exchange_rates_lookup_idx on app.finance_exchange_rates (
  coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), rate_type, source_currency, target_currency, status
);

create function app.touch_finance_exchange_rate_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger finance_exchange_rates_touch_row
  before update on app.finance_exchange_rates
  for each row
  execute function app.touch_finance_exchange_rate_row();

-- Staged idempotent import batch (Prompt 194 section 14) -- a bounded, disclosed
-- alternative to the full generic Import/Export Job Framework (this
-- migration's own header).
create table app.finance_exchange_rate_import_batches (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references app.tenants (id),
  idempotency_key text not null,
  row_count integer not null default 0,
  created_by text,
  created_at timestamptz not null default now(),
  constraint finance_exchange_rate_import_batches_tenant_key_unique unique (tenant_id, idempotency_key)
);

comment on table app.finance_exchange_rate_import_batches is
  'FIN-194: one row per staged import call, unique on (tenant_id, idempotency_key) -- a retried import with the same key returns the original batch''s own drafts rather than duplicating them.';

-- A null p_tenant_id means a platform-wide default rate (this migration's own
-- "tenant_id null = a platform-wide default" convention) -- there is no
-- tenant-scoped FIN role to evaluate for it, so authority falls to Supreme
-- Admin instead, mirroring PLT-121's own app.check_config_object_authority
-- ("when p_scope_level = 'global' then app.is_supreme_admin(...)").
create function app.check_finance_exchange_rate_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
as $$
  select case
    when p_tenant_id is null then app.is_supreme_admin(p_actor_auth_user_id)
    else (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'FIN', p_action)).allowed
  end;
$$;

comment on function app.check_finance_exchange_rate_authority is
  'FIN-194: FIN:Edit gates draft/discard/import; FIN:Approve gates rate approval; FIN:View gates read/resolve/convert-preview -- the canonical PLT-111 FIN permission catalogue, reused directly for a tenant-scoped rate. A platform-wide default rate (tenant_id null) has no tenant-scoped FIN role to evaluate, so it falls to Supreme Admin instead (PLT-121''s own global-scope precedent).';

create function app.create_finance_exchange_rate_draft(
  p_tenant_id uuid,
  p_rate_type text,
  p_source_currency text,
  p_target_currency text,
  p_rate numeric,
  p_source text,
  p_effective_from timestamptz,
  p_effective_to timestamptz,
  p_actor_auth_user_id uuid,
  p_created_by text
)
returns app.finance_exchange_rates
language plpgsql
as $$
declare
  v_rate app.finance_exchange_rates;
begin
  -- A platform-wide default draft (p_tenant_id null) has no tenant to hold
  -- membership in -- app.check_finance_exchange_rate_authority's own
  -- Supreme-Admin fallback is the sole gate for that case.
  if p_tenant_id is not null and not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_exchange_rate_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.validate_currency_code(p_source_currency) then
    raise exception 'finance_exchange_rate_unsupported_currency: % is not a registered, active currency', p_source_currency
      using errcode = 'check_violation';
  end if;
  if not app.validate_currency_code(p_target_currency) then
    raise exception 'finance_exchange_rate_unsupported_currency: % is not a registered, active currency', p_target_currency
      using errcode = 'check_violation';
  end if;

  if p_rate is null or p_rate <= 0 then
    raise exception 'finance_exchange_rate_invalid_rate: rate must be a positive value, got %', p_rate
      using errcode = 'check_violation';
  end if;

  insert into app.finance_exchange_rates (
    tenant_id, rate_type, source_currency, target_currency, rate, source, effective_from, effective_to, created_by
  )
  values (
    p_tenant_id, coalesce(p_rate_type, 'spot'), p_source_currency, p_target_currency, p_rate, coalesce(p_source, 'manual'), p_effective_from, p_effective_to, p_created_by
  )
  returning * into v_rate;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_created_by, 'create_finance_exchange_rate_draft',
    'app.finance_exchange_rates', v_rate.id, 'success', null, null, to_jsonb(v_rate)
  );

  return v_rate;
end;
$$;

create function app.discard_finance_exchange_rate_draft(
  p_rate_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_exchange_rates
language plpgsql
as $$
declare
  v_rate app.finance_exchange_rates;
begin
  select * into v_rate from app.finance_exchange_rates where id = p_rate_id;
  if not found then
    raise exception 'finance_exchange_rate_not_found: %', p_rate_id using errcode = 'no_data_found';
  end if;

  if v_rate.record_version <> p_expected_version then
    raise exception 'stale_version: rate % expected version % but found %', p_rate_id, p_expected_version, v_rate.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_rate.status <> 'draft' then
    raise exception 'finance_exchange_rate_not_draft: rate % is %, only a draft may be discarded', p_rate_id, v_rate.status
      using errcode = 'check_violation';
  end if;

  if not app.check_finance_exchange_rate_authority('Edit', v_rate.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_rate.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.finance_exchange_rates
  set status = 'archived'
  where id = p_rate_id and record_version = p_expected_version
  returning * into v_rate;

  perform app.capture_audit_event(
    v_rate.tenant_id, p_actor_auth_user_id, p_actor_label, 'discard_finance_exchange_rate_draft',
    'app.finance_exchange_rates', v_rate.id, 'success', p_reason, null, to_jsonb(v_rate)
  );

  return v_rate;
end;
$$;

-- Approval rejects an overlapping already-approved window for the same
-- (tenant scope, rate_type, pair) -- Prompt 194 section 23's own "overlapping
-- approved versions" exception. FIN:Approve-gated.
create function app.approve_finance_exchange_rate(
  p_rate_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_exchange_rates
language plpgsql
as $$
declare
  v_rate app.finance_exchange_rates;
  v_overlap_count integer;
begin
  select * into v_rate from app.finance_exchange_rates where id = p_rate_id;
  if not found then
    raise exception 'finance_exchange_rate_not_found: %', p_rate_id using errcode = 'no_data_found';
  end if;

  if v_rate.record_version <> p_expected_version then
    raise exception 'stale_version: rate % expected version % but found %', p_rate_id, p_expected_version, v_rate.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_rate.status <> 'draft' then
    raise exception 'finance_exchange_rate_not_draft: rate % is %, only a draft may be approved', p_rate_id, v_rate.status
      using errcode = 'check_violation';
  end if;

  if not app.check_finance_exchange_rate_authority('Approve', v_rate.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_rate.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select count(*) into v_overlap_count from app.finance_exchange_rates
    where id <> p_rate_id
      and status = 'approved'
      and coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(v_rate.tenant_id, '00000000-0000-0000-0000-000000000000'::uuid)
      and rate_type = v_rate.rate_type
      and source_currency = v_rate.source_currency
      and target_currency = v_rate.target_currency
      and effective_from <= coalesce(v_rate.effective_to, 'infinity'::timestamptz)
      and coalesce(effective_to, 'infinity'::timestamptz) >= v_rate.effective_from;
  if v_overlap_count > 0 then
    raise exception 'finance_exchange_rate_overlap: an approved rate already covers an overlapping window for this scope/type/pair'
      using errcode = 'check_violation';
  end if;

  update app.finance_exchange_rates
  set status = 'approved', approved_by = p_actor_label, approved_at = now()
  where id = p_rate_id and record_version = p_expected_version
  returning * into v_rate;

  perform app.capture_audit_event(
    v_rate.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_finance_exchange_rate',
    'app.finance_exchange_rates', v_rate.id, 'success', null, null, to_jsonb(v_rate)
  );

  return v_rate;
end;
$$;

-- Deterministic resolution (Prompt 194 section 24): a tenant-specific approved rate
-- covering p_as_of wins; otherwise the platform-wide default (tenant_id is
-- null) covering p_as_of; otherwise no row (callers must treat that as
-- "missing rate," never assume one -- Prompt 194 section 23's own "missing... rate
-- ... block posting").
create function app.resolve_finance_exchange_rate(
  p_tenant_id uuid,
  p_rate_type text,
  p_source_currency text,
  p_target_currency text,
  p_as_of timestamptz default now()
)
returns setof app.finance_exchange_rates
language sql
stable
as $$
  select *
  from app.finance_exchange_rates
  where status = 'approved'
    and rate_type = p_rate_type
    and source_currency = p_source_currency
    and target_currency = p_target_currency
    and effective_from <= p_as_of
    and (effective_to is null or effective_to > p_as_of)
    and (tenant_id = p_tenant_id or tenant_id is null)
  order by (tenant_id is null) asc, effective_from desc
  limit 1;
$$;

comment on function app.resolve_finance_exchange_rate is
  'FIN-194: tenant-specific approved rate wins over the platform-wide default (order by (tenant_id is null) puts a real tenant match, false=0, before a global fallback, true=1) -- deterministic, single-row resolution. Declared `setof` (not a bare composite) so a no-match call genuinely returns zero rows rather than one all-NULL row -- a bare composite return, called via `select ... into ... from func()`, always yields exactly one row (FOUND=true) even when its own body query matches nothing, which would have silently broken every caller''s own not-found/missing-rate check (this function''s sole caller, app.convert_finance_amount, included).';

-- Convert-preview (Prompt 194 section 14). Same-currency amounts short-circuit
-- (never require a stored rate). Rounding resolves the tenant's own
-- effective finance_rounding config (FIN-191), key 'fx_conversion' then
-- 'default', then a disclosed safe default (round_half_up at the target
-- currency's own minor_unit_precision).
create function app.convert_finance_amount(
  p_tenant_id uuid,
  p_amount numeric,
  p_source_currency text,
  p_target_currency text,
  p_rate_type text,
  p_as_of timestamptz,
  p_actor_auth_user_id uuid
)
returns jsonb
language plpgsql
as $$
declare
  v_rate app.finance_exchange_rates;
  v_rounding_row record;
  v_mode text;
  v_precision integer;
  v_order text;
  v_target_precision integer;
  v_converted numeric;
begin
  if not app.check_finance_exchange_rate_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select minor_unit_precision into v_target_precision from app.finance_currencies where code = p_target_currency;
  if v_target_precision is null then
    raise exception 'finance_exchange_rate_unsupported_currency: % is not a registered, active currency', p_target_currency
      using errcode = 'check_violation';
  end if;

  if p_source_currency = p_target_currency then
    return jsonb_build_object(
      'amount', p_amount, 'sourceCurrency', p_source_currency, 'targetCurrency', p_target_currency,
      'rate', 1, 'rateId', null, 'convertedAmount', round(p_amount, v_target_precision), 'roundingMode', 'identity'
    );
  end if;

  select * into v_rate from app.resolve_finance_exchange_rate(p_tenant_id, coalesce(p_rate_type, 'spot'), p_source_currency, p_target_currency, coalesce(p_as_of, now()));
  if not found then
    raise exception 'finance_exchange_rate_missing: no approved % rate from % to % covers %', coalesce(p_rate_type, 'spot'), p_source_currency, p_target_currency, coalesce(p_as_of, now())
      using errcode = 'no_data_found';
  end if;

  v_mode := 'round_half_up';
  v_precision := v_target_precision;
  v_order := 'convert_then_round';

  for v_rounding_row in select * from app.resolve_finance_config('finance_rounding', p_tenant_id) loop
    if v_rounding_row.items ? 'fx_conversion' then
      v_mode := coalesce(v_rounding_row.items -> 'fx_conversion' ->> 'mode', v_mode);
      v_precision := coalesce((v_rounding_row.items -> 'fx_conversion' ->> 'precision')::integer, v_precision);
      v_order := coalesce(v_rounding_row.items -> 'fx_conversion' ->> 'order', v_order);
    elsif v_rounding_row.items ? 'default' then
      v_mode := coalesce(v_rounding_row.items -> 'default' ->> 'mode', v_mode);
      v_precision := coalesce((v_rounding_row.items -> 'default' ->> 'precision')::integer, v_precision);
      v_order := coalesce(v_rounding_row.items -> 'default' ->> 'order', v_order);
    end if;
  end loop;

  v_converted := app.apply_finance_rounding(p_amount * v_rate.rate, v_precision, v_mode);

  return jsonb_build_object(
    'amount', p_amount, 'sourceCurrency', p_source_currency, 'targetCurrency', p_target_currency,
    'rate', v_rate.rate, 'rateId', v_rate.id, 'convertedAmount', v_converted, 'roundingMode', v_mode, 'roundingOrder', v_order
  );
end;
$$;

comment on function app.convert_finance_amount is
  'FIN-194: the shared, deterministic conversion service (Prompt 194 section 14''s "convert-preview"). Resolves the tenant''s own effective finance_rounding config (FIN-191) for its own rounding contract -- never a second, competing rounding mechanism.';

create function app.list_finance_exchange_rates(
  p_tenant_id uuid,
  p_rate_type text,
  p_source_currency text,
  p_target_currency text,
  p_actor_auth_user_id uuid
)
returns setof app.finance_exchange_rates
language plpgsql
stable
as $$
begin
  if not app.check_finance_exchange_rate_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
    select * from app.finance_exchange_rates
    where coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(p_tenant_id, '00000000-0000-0000-0000-000000000000'::uuid)
      and (p_rate_type is null or rate_type = p_rate_type)
      and (p_source_currency is null or source_currency = p_source_currency)
      and (p_target_currency is null or target_currency = p_target_currency)
    order by effective_from desc;
end;
$$;

-- Staged idempotent import (Prompt 194 section 14/section 23: "imports use staged
-- idempotent jobs"; "stale import" rejected -- here, a retried call with the
-- same idempotency_key returns the original batch's own drafts rather than
-- re-staging). p_rows is a jsonb array of {rate_type, source_currency,
-- target_currency, rate, source, effective_from, effective_to}.
create function app.stage_finance_exchange_rate_import(
  p_tenant_id uuid,
  p_idempotency_key text,
  p_rows jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_exchange_rate_import_batches
language plpgsql
as $$
declare
  v_batch app.finance_exchange_rate_import_batches;
  v_row jsonb;
  v_count integer := 0;
begin
  if not app.check_finance_exchange_rate_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_batch from app.finance_exchange_rate_import_batches
    where coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(p_tenant_id, '00000000-0000-0000-0000-000000000000'::uuid)
      and idempotency_key = p_idempotency_key;
  if found then
    return v_batch;
  end if;

  insert into app.finance_exchange_rate_import_batches (tenant_id, idempotency_key, created_by)
  values (p_tenant_id, p_idempotency_key, p_actor_label)
  returning * into v_batch;

  for v_row in select * from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    insert into app.finance_exchange_rates (
      tenant_id, rate_type, source_currency, target_currency, rate, source, effective_from, effective_to, import_batch_id, created_by
    )
    values (
      p_tenant_id,
      coalesce(v_row ->> 'rate_type', 'spot'),
      v_row ->> 'source_currency',
      v_row ->> 'target_currency',
      (v_row ->> 'rate')::numeric,
      coalesce(v_row ->> 'source', 'import'),
      (v_row ->> 'effective_from')::timestamptz,
      (v_row ->> 'effective_to')::timestamptz,
      v_batch.id,
      p_actor_label
    );
    v_count := v_count + 1;
  end loop;

  update app.finance_exchange_rate_import_batches set row_count = v_count where id = v_batch.id returning * into v_batch;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'stage_finance_exchange_rate_import',
    'app.finance_exchange_rate_import_batches', v_batch.id, 'success', null, null, jsonb_build_object('row_count', v_count)
  );

  return v_batch;
end;
$$;

alter table app.finance_currencies enable row level security;
alter table app.finance_exchange_rates enable row level security;
alter table app.finance_exchange_rate_import_batches enable row level security;

create policy finance_currencies_select_authenticated on app.finance_currencies
  for select to authenticated
  using (true);

create policy finance_exchange_rates_select_scoped on app.finance_exchange_rates
  for select to authenticated
  using (tenant_id is null or app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

create policy finance_exchange_rate_import_batches_select_scoped on app.finance_exchange_rate_import_batches
  for select to authenticated
  using (tenant_id is null or app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable
-- revoke of PostgreSQL's PUBLIC-execute default, the standing per-migration
-- convention since PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant select on app.finance_currencies to authenticated, service_role;
grant select on app.finance_exchange_rates to authenticated, service_role;
grant select on app.finance_exchange_rate_import_batches to authenticated, service_role;
grant insert, update, delete on app.finance_currencies to service_role;
grant insert, update, delete on app.finance_exchange_rates to service_role;
grant insert, update, delete on app.finance_exchange_rate_import_batches to service_role;

-- app.validate_currency_code's own grant (service_role only) is untouched --
-- CREATE OR REPLACE FUNCTION preserves existing grants, and this migration
-- issues no new grant statement for it, so its access posture is exactly
-- what PLT-119 already established (OPS-186's own "grants survive CREATE OR
-- REPLACE FUNCTION" precedent, directly re-verified in this checkpoint's own
-- db-test).
grant execute on function app.apply_finance_rounding(numeric, integer, text) to authenticated, service_role;
grant execute on function app.touch_finance_exchange_rate_row() to service_role;
grant execute on function app.check_finance_exchange_rate_authority(text, uuid, uuid) to service_role;
grant execute on function app.create_finance_exchange_rate_draft(uuid, text, text, text, numeric, text, timestamptz, timestamptz, uuid, text) to authenticated, service_role;
grant execute on function app.discard_finance_exchange_rate_draft(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.approve_finance_exchange_rate(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.resolve_finance_exchange_rate(uuid, text, text, text, timestamptz) to authenticated, service_role;
grant execute on function app.convert_finance_amount(uuid, numeric, text, text, text, timestamptz, uuid) to authenticated, service_role;
grant execute on function app.list_finance_exchange_rates(uuid, text, text, text, uuid) to authenticated, service_role;
grant execute on function app.stage_finance_exchange_rate_import(uuid, text, jsonb, uuid, text) to authenticated, service_role;
