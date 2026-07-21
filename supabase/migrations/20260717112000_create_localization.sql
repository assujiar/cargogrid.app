-- Platform Core capability PLT-119 (Localization, CG-S6-PLT-016)
-- Canonical localization primitives: locale/timezone/currency-display resolution and
-- tenant terminology overrides, with a three-tier fallback (user -> tenant -> platform
-- default, Prompt 119 §22) and versioned draft/publish/rollback governance mirroring
-- PLT-117's white-label model.
--
-- Scope, disclosed rather than left implicit (matching every prior checkpoint's
-- discipline):
--
-- * **Only two locales are populated**: `id` (Bahasa Indonesia) and `en` (English) --
--   `docs/standards/DESIGN_SYSTEM.md` §10, verbatim: "only Bahasa Indonesia/English are
--   populated at MVP" (RPD-016's Indonesia-first sequencing). The catalogue structure
--   (a CHECK-constrained closed set, validated by `app.validate_locale_code()`)
--   accommodates additional locales later without a tenant-specific source fork, per
--   that same section's own framing -- adding a third locale is a future data change,
--   not a schema change.
-- * **Currency here is display formatting metadata only -- never exchange-rate or
--   financial-conversion logic.** `docs/ai-agent-build-prompt-package/00-control/
--   07_PROMPT_PACKAGE_MANIFEST.md` names a dedicated future capability (`M-194`,
--   `09-phase-04-finance/194_CURRENCY_EXCHANGE_RATE_PROMPT.md`, Phase 4) for "exact
--   currency/rate/version/rounding control" with its own RPD-016 SME activation gate --
--   this checkpoint's `default_currency` is a tenant's *display* preference (which
--   symbol/code/decimal convention to render with) and structurally cannot represent an
--   exchange rate, a conversion, or a financial posting. Only `IDR` (Indonesia-first
--   primary) and `USD` (a common secondary reference currency) validate.
-- * **No statutory/tax logic exists here** (Prompt 119 §12/§24, forbidden) -- Indonesia-
--   first tax/payroll rules are `FIN-194..195`'s own Phase 4 capability, gated on real
--   SME evidence per RPD-016. This migration never computes a tax amount, a payroll
--   figure, or any statutory value.
-- * **Timezone catalogue is a real, sourced, bounded set**: Indonesia's three IANA zones
--   (`Asia/Jakarta`/WIB, `Asia/Makassar`/WITA, `Asia/Jayapura`/WIT) plus `UTC` as the
--   platform-neutral default -- not an open-ended IANA-database validator (which would
--   accept values with no real product support behind them yet).
-- * **Terminology override keys are a real, sourced, bounded catalogue**
--   (`app.canonical_terms`), not an open-ended key space -- seeded directly from this
--   repository's own already-shipped `CHECK`-constrained enum values (`PLT-105`'s tenant
--   statuses, `PLT-108`'s principal layers, `PLT-109`'s org-unit types, `PLT-110`'s user
--   statuses, `PLT-117`'s brand-version statuses, `PLT-118`'s domain statuses -- 21 real
--   terms total). No business-domain module exists yet in this still-Platform-Core-only
--   repository, so no business-domain status/entity terminology (shipment status,
--   invoice status, etc.) can be seeded honestly yet -- each business-domain phase seeds
--   its own canonical terms into this same table when it ships, the same "reuse the
--   canonical mechanism, don't fork a new one" discipline `PLT-117`'s adoption of
--   `PLT-116`'s audit trail already established. **Canonical values themselves never
--   change** (Prompt 119 §24) -- a terminology override changes only the *label* a
--   tenant sees; `code` (the canonical machine value) is what every other capability's
--   `CHECK` constraint, RLS policy, and API response continues to use, untouched.
-- * **No bespoke `*_history` table** -- every lifecycle event routes through `PLT-116`'s
--   canonical `app.capture_audit_event()`, the same convention `PLT-117`/`118` already
--   adopted.
-- * Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`, found and fixed at `PLT-118`):
--   this migration carries its own explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA
--   app FROM PUBLIC` statement before its final grants, the new standing per-migration
--   convention.

create function app.validate_locale_code(p_locale text)
returns boolean
language sql
immutable
as $$
  select p_locale in ('id', 'en');
$$;

comment on function app.validate_locale_code is
  'PLT-119: the closed, MVP-populated locale set (DESIGN_SYSTEM.md §10) -- Bahasa Indonesia and English only.';

create function app.validate_timezone_name(p_timezone text)
returns boolean
language sql
immutable
as $$
  select p_timezone in ('Asia/Jakarta', 'Asia/Makassar', 'Asia/Jayapura', 'UTC');
$$;

comment on function app.validate_timezone_name is
  'PLT-119: Indonesia''s three real IANA timezones (WIB/WITA/WIT) plus UTC as the platform-neutral default -- a bounded, sourced set, not an open IANA-database validator.';

create function app.validate_currency_code(p_currency text)
returns boolean
language sql
immutable
as $$
  select p_currency in ('IDR', 'USD');
$$;

comment on function app.validate_currency_code is
  'PLT-119: display-formatting currency codes only (ISO 4217) -- never an exchange rate or financial figure. Real currency/FX control is a dedicated future Phase 4 capability (see this migration''s own header).';

-- Real, sourced canonical terminology catalogue -- seeded from this repository's own
-- already-shipped CHECK-constrained enum values (see this migration's own header for
-- the full per-capability sourcing). category groups related terms for a future admin
-- UI; default_label_en/default_label_id are the platform's own baseline copy, always
-- available as the fallback when a tenant has no override.
create table app.canonical_terms (
  code text primary key,
  category text not null,
  default_label_en text not null,
  default_label_id text not null,
  created_at timestamptz not null default now()
);

comment on table app.canonical_terms is
  'PLT-119: the real, bounded set of canonical machine values a tenant may attach a display label to via app.tenant_locale_versions.terminology_overrides. Never itself mutated by a tenant -- codes are seeded/extended only by future capability migrations as each business domain ships its own canonical statuses/entities.';

insert into app.canonical_terms (code, category, default_label_en, default_label_id) values
  ('tenant_status.provisioning', 'tenant_status', 'Provisioning', 'Sedang Disiapkan'),
  ('tenant_status.active', 'tenant_status', 'Active', 'Aktif'),
  ('tenant_status.suspended', 'tenant_status', 'Suspended', 'Ditangguhkan'),
  ('tenant_status.terminated', 'tenant_status', 'Terminated', 'Diberhentikan'),
  ('principal_layer.supreme_admin', 'principal_layer', 'Supreme Admin', 'Admin Utama'),
  ('principal_layer.tenant_admin', 'principal_layer', 'Tenant Admin', 'Admin Tenant'),
  ('principal_layer.org_user', 'principal_layer', 'Internal User', 'Pengguna Internal'),
  ('principal_layer.customer_user', 'principal_layer', 'Customer User', 'Pengguna Pelanggan'),
  ('org_unit_type.company', 'org_unit_type', 'Company', 'Perusahaan'),
  ('org_unit_type.branch', 'org_unit_type', 'Branch', 'Cabang'),
  ('org_unit_type.department', 'org_unit_type', 'Department', 'Departemen'),
  ('org_unit_type.business_unit', 'org_unit_type', 'Business Unit', 'Unit Bisnis'),
  ('user_status.invited', 'user_status', 'Invited', 'Diundang'),
  ('user_status.active', 'user_status', 'Active', 'Aktif'),
  ('user_status.suspended', 'user_status', 'Suspended', 'Ditangguhkan'),
  ('user_status.revoked', 'user_status', 'Revoked', 'Dicabut'),
  ('brand_version_status.draft', 'brand_version_status', 'Draft', 'Draf'),
  ('brand_version_status.published', 'brand_version_status', 'Published', 'Diterbitkan'),
  ('brand_version_status.archived', 'brand_version_status', 'Archived', 'Diarsipkan'),
  ('domain_status.pending_verification', 'domain_status', 'Pending Verification', 'Menunggu Verifikasi'),
  ('domain_status.verified', 'domain_status', 'Verified', 'Terverifikasi'),
  ('domain_status.active', 'domain_status', 'Active', 'Aktif'),
  ('domain_status.disabled', 'domain_status', 'Disabled', 'Dinonaktifkan'),
  ('domain_status.rejected', 'domain_status', 'Rejected', 'Ditolak'),
  ('domain_status.expired', 'domain_status', 'Expired', 'Kedaluwarsa');

-- Terminology override validation (Prompt 119 §16/§24: no injection, canonical values
-- never move). Keys must already exist in app.canonical_terms -- an override for an
-- undefined code is rejected outright, the structural form of "missing/unused keys
-- detectable" (§25) applied in reverse (a typo'd or invented key can never silently
-- persist). Values are plain text only, length-capped, no angle brackets -- the same
-- injection defense PLT-117's document-template text fields established.
create function app.validate_terminology_overrides(p_overrides jsonb)
returns boolean
language plpgsql
stable
as $$
declare
  v_key text;
  v_value jsonb;
  v_text text;
begin
  if p_overrides is null or jsonb_typeof(p_overrides) <> 'object' then
    return false;
  end if;

  for v_key, v_value in select * from jsonb_each(p_overrides) loop
    if not exists (select 1 from app.canonical_terms where code = v_key) then
      return false;
    end if;
    if jsonb_typeof(v_value) <> 'string' then
      return false;
    end if;
    v_text := v_value #>> '{}';
    if length(v_text) = 0 or length(v_text) > 80 or v_text ~ '[<>]' then
      return false;
    end if;
  end loop;

  return true;
end;
$$;

comment on function app.validate_terminology_overrides is
  'PLT-119: terminology_overrides keys must reference a real app.canonical_terms code; values are non-empty, <=80-char plain text with no angle brackets (no HTML/script injection). Not a table CHECK constraint, since it queries another table (STABLE, not IMMUTABLE) -- applied via a trigger instead, see below.';

create table app.tenant_locale_versions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  version_number integer not null,
  status text not null default 'draft',
  default_locale text not null default 'id',
  default_timezone text not null default 'Asia/Jakarta',
  default_currency text not null default 'IDR',
  terminology_overrides jsonb not null default '{}'::jsonb,
  effective_from timestamptz,
  cloned_from_version_id uuid references app.tenant_locale_versions (id),
  rollback_of_version_id uuid references app.tenant_locale_versions (id),
  created_by text,
  published_by text,
  published_at timestamptz,
  archived_at timestamptz,
  archived_reason text,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint tenant_locale_versions_status_check check (status in ('draft', 'published', 'archived')),
  constraint tenant_locale_versions_tenant_version_unique unique (tenant_id, version_number),
  constraint tenant_locale_versions_locale_check check (app.validate_locale_code(default_locale)),
  constraint tenant_locale_versions_timezone_check check (app.validate_timezone_name(default_timezone)),
  constraint tenant_locale_versions_currency_check check (app.validate_currency_code(default_currency))
);

comment on table app.tenant_locale_versions is
  'Versioned tenant locale/timezone/currency-display default and terminology-override configuration (PLT-119) -- draft/publish/rollback, mirroring PLT-117''s app.tenant_brand_versions discipline exactly. terminology_overrides is validated by a trigger (app.enforce_terminology_overrides_valid), not a CHECK constraint, since validation requires a lookup against app.canonical_terms (STABLE, not IMMUTABLE).';

create index tenant_locale_versions_tenant_id_idx on app.tenant_locale_versions (tenant_id);
create unique index tenant_locale_versions_single_draft_per_tenant
  on app.tenant_locale_versions (tenant_id) where status = 'draft';
create unique index tenant_locale_versions_single_published_per_tenant
  on app.tenant_locale_versions (tenant_id) where status = 'published';

create function app.enforce_terminology_overrides_valid()
returns trigger
language plpgsql
as $$
begin
  if not app.validate_terminology_overrides(new.terminology_overrides) then
    raise exception 'invalid_terminology_overrides: terminology_overrides contains an unknown canonical_terms code, a non-string value, or an unsafe/oversized label'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger tenant_locale_versions_enforce_terminology
  before insert or update on app.tenant_locale_versions
  for each row
  execute function app.enforce_terminology_overrides_valid();

create function app.touch_tenant_locale_version_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger tenant_locale_versions_touch_row
  before update on app.tenant_locale_versions
  for each row
  execute function app.touch_tenant_locale_version_row();

-- Idempotent draft creation, authority-gated identically to PLT-117/118 (Tenant Admin of
-- own tenant, or Supreme Admin -- app.is_support_grant_authority(), reused verbatim).
create function app.create_tenant_locale_draft(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_created_by text
)
returns app.tenant_locale_versions
language plpgsql
as $$
declare
  v_existing_draft app.tenant_locale_versions;
  v_next_version integer;
  v_version app.tenant_locale_versions;
begin
  if not app.is_support_grant_authority(p_actor_auth_user_id, p_tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_existing_draft from app.tenant_locale_versions where tenant_id = p_tenant_id and status = 'draft';
  if found then
    return v_existing_draft;
  end if;

  select coalesce(max(version_number), 0) + 1 into v_next_version from app.tenant_locale_versions where tenant_id = p_tenant_id;

  insert into app.tenant_locale_versions (tenant_id, version_number, created_by)
  values (p_tenant_id, v_next_version, p_created_by)
  returning * into v_version;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_created_by, 'create_tenant_locale_draft',
    'app.tenant_locale_versions', v_version.id, 'success', null, null, to_jsonb(v_version)
  );

  return v_version;
end;
$$;

create function app.set_tenant_locale_config(
  p_version_id uuid,
  p_actor_auth_user_id uuid,
  p_default_locale text,
  p_default_timezone text,
  p_default_currency text,
  p_terminology_overrides jsonb,
  p_actor_label text
)
returns app.tenant_locale_versions
language plpgsql
as $$
declare
  v_before app.tenant_locale_versions;
  v_after app.tenant_locale_versions;
begin
  select * into v_before from app.tenant_locale_versions where id = p_version_id;
  if not found then
    raise exception 'locale_version_not_found: no tenant locale version %', p_version_id
      using errcode = 'no_data_found';
  end if;

  if not app.is_support_grant_authority(p_actor_auth_user_id, v_before.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_before.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_before.status <> 'draft' then
    raise exception 'locale_version_not_draft: version % is %, only a draft may be changed', p_version_id, v_before.status
      using errcode = 'check_violation';
  end if;

  update app.tenant_locale_versions
  set default_locale = p_default_locale,
      default_timezone = p_default_timezone,
      default_currency = p_default_currency,
      terminology_overrides = coalesce(p_terminology_overrides, '{}'::jsonb)
  where id = p_version_id
  returning * into v_after;

  perform app.capture_audit_event(
    v_after.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_tenant_locale_config',
    'app.tenant_locale_versions', v_after.id, 'success', null, to_jsonb(v_before), to_jsonb(v_after)
  );

  return v_after;
end;
$$;

create function app.publish_tenant_locale_version(
  p_version_id uuid,
  p_actor_auth_user_id uuid,
  p_effective_from timestamptz,
  p_actor_label text
)
returns app.tenant_locale_versions
language plpgsql
as $$
declare
  v_version app.tenant_locale_versions;
  v_prior_published app.tenant_locale_versions;
  v_updated app.tenant_locale_versions;
begin
  select * into v_version from app.tenant_locale_versions where id = p_version_id;
  if not found then
    raise exception 'locale_version_not_found: no tenant locale version %', p_version_id
      using errcode = 'no_data_found';
  end if;

  if not app.is_support_grant_authority(p_actor_auth_user_id, v_version.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_version.status <> 'draft' then
    raise exception 'locale_version_not_draft: version % is %, only a draft may be published', p_version_id, v_version.status
      using errcode = 'check_violation';
  end if;

  select * into v_prior_published from app.tenant_locale_versions where tenant_id = v_version.tenant_id and status = 'published';
  if found then
    update app.tenant_locale_versions
    set status = 'archived', archived_at = now(), archived_reason = 'superseded by a newer published version'
    where id = v_prior_published.id;
  end if;

  update app.tenant_locale_versions
  set status = 'published', published_by = p_actor_label, published_at = now(), effective_from = coalesce(p_effective_from, now())
  where id = p_version_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_tenant_locale_version',
    'app.tenant_locale_versions', v_updated.id, 'success', null, to_jsonb(v_version), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

create function app.discard_tenant_locale_draft(
  p_version_id uuid,
  p_actor_auth_user_id uuid,
  p_reason text,
  p_actor_label text
)
returns app.tenant_locale_versions
language plpgsql
as $$
declare
  v_version app.tenant_locale_versions;
  v_updated app.tenant_locale_versions;
begin
  select * into v_version from app.tenant_locale_versions where id = p_version_id;
  if not found then
    raise exception 'locale_version_not_found: no tenant locale version %', p_version_id
      using errcode = 'no_data_found';
  end if;

  if not app.is_support_grant_authority(p_actor_auth_user_id, v_version.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_version.status <> 'draft' then
    raise exception 'locale_version_not_draft: version % is %, only a draft may be discarded', p_version_id, v_version.status
      using errcode = 'check_violation';
  end if;

  update app.tenant_locale_versions
  set status = 'archived', archived_at = now(), archived_reason = coalesce(p_reason, 'discarded')
  where id = p_version_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'discard_tenant_locale_draft',
    'app.tenant_locale_versions', v_updated.id, 'success', p_reason, to_jsonb(v_version), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

-- Rollback -- never mutates history, clones the target's exact snapshot into a
-- brand-new version and publishes it immediately, the same PLT-117/PLT-111 discipline.
create function app.rollback_tenant_locale_version(
  p_target_version_id uuid,
  p_actor_auth_user_id uuid,
  p_reason text,
  p_actor_label text
)
returns app.tenant_locale_versions
language plpgsql
as $$
declare
  v_target app.tenant_locale_versions;
  v_next_version integer;
  v_new_row app.tenant_locale_versions;
  v_prior_published app.tenant_locale_versions;
  v_published app.tenant_locale_versions;
begin
  select * into v_target from app.tenant_locale_versions where id = p_target_version_id;
  if not found then
    raise exception 'locale_version_not_found: no tenant locale version %', p_target_version_id
      using errcode = 'no_data_found';
  end if;

  if v_target.status = 'draft' then
    raise exception 'cannot_rollback_draft: version % is still a draft, nothing stable to roll back to', p_target_version_id
      using errcode = 'check_violation';
  end if;

  if not app.is_support_grant_authority(p_actor_auth_user_id, v_target.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_target.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select coalesce(max(version_number), 0) + 1 into v_next_version from app.tenant_locale_versions where tenant_id = v_target.tenant_id;

  insert into app.tenant_locale_versions (
    tenant_id, version_number, default_locale, default_timezone, default_currency,
    terminology_overrides, cloned_from_version_id, rollback_of_version_id, created_by
  )
  values (
    v_target.tenant_id, v_next_version, v_target.default_locale, v_target.default_timezone, v_target.default_currency,
    v_target.terminology_overrides, p_target_version_id, p_target_version_id, p_actor_label
  )
  returning * into v_new_row;

  select * into v_prior_published from app.tenant_locale_versions where tenant_id = v_target.tenant_id and status = 'published';
  if found then
    update app.tenant_locale_versions
    set status = 'archived', archived_at = now(), archived_reason = 'superseded by rollback to version ' || v_target.version_number
    where id = v_prior_published.id;
  end if;

  update app.tenant_locale_versions
  set status = 'published', published_by = p_actor_label, published_at = now(), effective_from = now()
  where id = v_new_row.id
  returning * into v_published;

  perform app.capture_audit_event(
    v_published.tenant_id, p_actor_auth_user_id, p_actor_label, 'rollback_tenant_locale_version',
    'app.tenant_locale_versions', v_published.id, 'success', p_reason, to_jsonb(v_target), to_jsonb(v_published)
  );

  return v_published;
end;
$$;

-- Three per-user preference columns (Prompt 119 §22's "user" tier of the fallback
-- chain) -- additive ALTER TABLE on PLT-110's already-shipped app.users, not an edit to
-- an applied migration (AGENTS.md: "never edit an applied migration; add a new
-- migration" -- an additive nullable column via a new migration is exactly that).
alter table app.users add column preferred_locale text;
alter table app.users add column preferred_timezone text;
alter table app.users add column preferred_currency text;
alter table app.users add constraint users_preferred_locale_check check (preferred_locale is null or app.validate_locale_code(preferred_locale));
alter table app.users add constraint users_preferred_timezone_check check (preferred_timezone is null or app.validate_timezone_name(preferred_timezone));
alter table app.users add constraint users_preferred_currency_check check (preferred_currency is null or app.validate_currency_code(preferred_currency));

-- The platform-default fallback (Prompt 119 §22's outermost tier) -- Indonesia-first
-- (RPD-016), sourced from DESIGN_SYSTEM.md §10's own framing: 'id'/'Asia/Jakarta'
-- (Jakarta being the primary/largest real hub implied by "Indonesia-first")/'IDR'.
-- Disclosed as a reasoned inference from ratified decisions, not an invented one --
-- unlike DESIGN_SYSTEM.md §3's still-genuinely-open CargoGrid brand-color decision,
-- Indonesia-first locale sequencing is already ratified (RPD-016), so a default
-- locale/timezone/currency is a defensible platform default, not a new product call.
create function app.resolve_tenant_locale(p_tenant_id uuid)
returns table (
  tenant_id uuid,
  source text,
  version_id uuid,
  version_number integer,
  default_locale text,
  default_timezone text,
  default_currency text,
  terminology_overrides jsonb,
  effective_from timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_tenant app.tenants;
  v_published app.tenant_locale_versions;
begin
  select * into v_tenant from app.tenants t where t.id = p_tenant_id;

  if found and v_tenant.canonical_status = 'active' then
    select * into v_published from app.tenant_locale_versions v where v.tenant_id = p_tenant_id and v.status = 'published';
  end if;

  if v_published.id is not null then
    return query select
      p_tenant_id, 'tenant'::text, v_published.id, v_published.version_number,
      v_published.default_locale, v_published.default_timezone, v_published.default_currency,
      v_published.terminology_overrides, v_published.effective_from;
  else
    return query select
      p_tenant_id, 'default'::text, null::uuid, null::integer,
      'id'::text, 'Asia/Jakarta'::text, 'IDR'::text, '{}'::jsonb, null::timestamptz;
  end if;
end;
$$;

comment on function app.resolve_tenant_locale is
  'Resolves a tenant''s effective locale/timezone/currency-display defaults and terminology overrides (PLT-119): the current published version if the tenant is active and has one, otherwise the Indonesia-first platform default. Mirrors PLT-117''s app.evaluate_tenant_brand() exactly.';

-- Full three-tier resolution (Prompt 119 §22): each of locale/timezone/currency
-- independently prefers a per-user preference (if p_user_auth_user_id is given and the
-- user has one set), then the tenant's published default, then the platform default --
-- never a single all-or-nothing fallback, so a user can override just their own
-- timezone while still inheriting the tenant's locale/currency. terminology_overrides
-- is always tenant-scoped (a per-user terminology override is not a real product
-- concept -- terminology is shared vocabulary within a tenant).
create function app.resolve_locale_context(
  p_tenant_id uuid,
  p_user_auth_user_id uuid default null
)
returns table (
  tenant_id uuid,
  source text,
  locale text,
  timezone text,
  currency text,
  terminology_overrides jsonb
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_tenant_locale record;
  v_user app.users;
begin
  select * into v_tenant_locale from app.resolve_tenant_locale(p_tenant_id);

  if p_user_auth_user_id is not null then
    select * into v_user
    from app.users u
    where u.tenant_id = p_tenant_id and u.auth_user_id = p_user_auth_user_id;
  end if;

  return query select
    p_tenant_id,
    v_tenant_locale.source,
    coalesce(v_user.preferred_locale, v_tenant_locale.default_locale),
    coalesce(v_user.preferred_timezone, v_tenant_locale.default_timezone),
    coalesce(v_user.preferred_currency, v_tenant_locale.default_currency),
    v_tenant_locale.terminology_overrides;
end;
$$;

comment on function app.resolve_locale_context is
  'PLT-119: the real three-tier fallback (user -> tenant -> platform default, Prompt 119 §22), each field independently. Composes app.resolve_tenant_locale() with an optional per-user preference lookup on app.users.';

alter table app.canonical_terms enable row level security;
alter table app.tenant_locale_versions enable row level security;

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke
-- of PostgreSQL's PUBLIC-execute default, the new standing per-migration convention
-- adopted at PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

-- app.canonical_terms is safe to expose broadly (platform-owned baseline copy, no
-- tenant/PII data) -- authenticated may browse it directly (e.g. a future terminology-
-- editor UI listing available codes to override); anon has no need for it pre-auth.
grant select on app.canonical_terms to authenticated, service_role;
-- app.tenant_locale_versions follows PLT-117's posture exactly: no direct SELECT for
-- authenticated/anon, only the SECURITY DEFINER evaluators below.
grant select, insert, update, delete on app.tenant_locale_versions to service_role;
grant execute on function app.validate_locale_code(text) to service_role;
grant execute on function app.validate_timezone_name(text) to service_role;
grant execute on function app.validate_currency_code(text) to service_role;
grant execute on function app.validate_terminology_overrides(jsonb) to service_role;
grant execute on function app.create_tenant_locale_draft(uuid, uuid, text) to service_role;
grant execute on function app.set_tenant_locale_config(uuid, uuid, text, text, text, jsonb, text) to service_role;
grant execute on function app.publish_tenant_locale_version(uuid, uuid, timestamptz, text) to service_role;
grant execute on function app.discard_tenant_locale_draft(uuid, uuid, text, text) to service_role;
grant execute on function app.rollback_tenant_locale_version(uuid, uuid, text, text) to service_role;
-- Deliberately broader, matching app.evaluate_tenant_brand()/app.resolve_tenant_by_domain():
-- rendering a tenant's login page or any pre-authentication surface in the correct
-- language/timezone/currency format needs to work before a session exists.
grant execute on function app.resolve_tenant_locale(uuid) to anon, authenticated, service_role;
grant execute on function app.resolve_locale_context(uuid, uuid) to anon, authenticated, service_role;
