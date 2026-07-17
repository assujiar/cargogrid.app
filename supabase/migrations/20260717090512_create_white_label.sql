-- Platform Core capability PLT-117 (White-Label Foundation, CG-S6-PLT-014)
-- Tenant-scoped white-label configuration: versioned draft/publish/rollback brand
-- tokens/assets/templates, governed by canonical semantic constraints (Prompt 117
-- §4/§20/§24) and RPD-019's fixed tenant-override surface (docs/architecture/
-- 09_UX_DESIGN_SYSTEM_WORKSTREAM.md §10: "logo, colors, domain, email presentation,
-- document templates... not an open-ended theming API").
--
-- Scope, disclosed rather than left implicit (matching every prior checkpoint's
-- discipline):
--
-- * Of RPD-019's five tenant-override items, this migration covers logo, colors, email
--   presentation, and document-template references. Custom domain (the fifth item) is
--   explicitly PLT-118's own capability, next in sequence (docs/architecture/
--   01_MODULE_DEPENDENCY_MAP.md line 91: "WLB (117->118->119)") -- not duplicated here.
-- * Typography is deliberately NOT part of the tenant-override token set. RPD-019/
--   `09_*.md` §10 fixes the override boundary at exactly five items; typography family
--   is a CargoGrid-owned base design-system token (docs/standards/DESIGN_SYSTEM.md §2,
--   "Typography... family choice open" -- open at the CargoGrid-base level, Product/
--   Design's decision, not a tenant one). Prompt 117 §15's "logo/color/typography/
--   template tokens" phrase describes the full set of token categories a tenant surface
--   *renders* through the shared shell, most of which (typography, spacing, radius,
--   elevation) are CargoGrid-owned and not columns on this table.
-- * No `components/ui/`/shared shell exists anywhere in this repository yet -- every
--   Phase 1 capability to date (`PLT-105`..`116`) has been server/database-only, and
--   `09_*.md` §14's own atomic backlog sequences "Portal shells" and "White-label
--   Studio" as separate, later UI slices that have not started. Prompt 117 §15's UI
--   application ("apply approved tokens across shared shell/components with accessible
--   fallbacks") is therefore deliberately deferred to that dedicated UI slice -- this
--   checkpoint delivers the database/evaluator/contract mechanism only, the same
--   backend-first sequencing this session has used for every capability so far.
-- * "Validate assets/URLs/content, malware scan files" (Prompt 117 §16): this migration
--   validates asset *references* structurally (HTTPS-only URL shape, safe character set,
--   no `javascript:`/`data:`/inline-script vector) via CHECK constraints -- real,
--   unconditional, database-enforced injection defense. Actual file upload and malware
--   scanning is `DOC`'s own capability (`PLT-128`, not yet built; AGENTS.md "every
--   upload is scanned before release to another user" applies at that future upload
--   surface, not here since no upload surface exists yet) -- disclosed, not silently
--   skipped, the same "mechanism proven, live wiring deferred" posture `PLT-107`
--   established for GoTrue.
-- * No bespoke `*_history` table is created here. `PLT-116` (Audit Trail Foundation)
--   landed immediately before this checkpoint specifically to be the canonical
--   accountability mechanism every future capability adopts rather than re-inventing --
--   this is the first capability built after it, and it is a deliberate convention
--   shift: every lifecycle event (draft created, tokens set, published, rolled back,
--   discarded) routes directly through `app.capture_audit_event()` (Prompt 117 §18:
--   "Record brand draft/publish/change/rollback/asset access and actor" -- exactly
--   `app.audit_logs`'s existing shape) instead of a seventh one-off `*_history` table.
-- * CargoGrid's own base primary/secondary brand color remains a genuinely open Product/
--   Design decision (`docs/standards/DESIGN_SYSTEM.md` §3, explicitly not blocking non-
--   visual Platform Core work but named as blocking "the first screen that actually
--   needs to render CargoGrid's own default... visual identity"). This migration does
--   not invent one: `app.evaluate_tenant_brand()`'s default fallback below composes only
--   the one already-sourced, already-contrast-vetted `neutral-900` (`#171717`) reference
--   value `DESIGN_SYSTEM.md` §2.1 already gives, for both `primary` and `secondary`,
--   undifferentiated -- a safe, accessible, honestly-sourced placeholder, not a new
--   fabricated brand decision.

-- WCAG 2.2 relative-luminance/contrast-ratio primitives (Prompt 117 §16/§25: "contrast
-- validated... deterministic"). A real implementation of the published W3C formula, not
-- a fabricated approximation -- deterministic and testable against known reference pairs
-- (e.g. black-on-white = exactly 21:1).
create function app.srgb_channel_to_linear(p_channel numeric)
returns numeric
language sql
immutable
as $$
  select case
    when p_channel <= 0.03928 then p_channel / 12.92
    else power((p_channel + 0.055) / 1.055, 2.4)
  end;
$$;

comment on function app.srgb_channel_to_linear is
  'WCAG 2.2 sRGB-to-linear channel transform (PLT-117), one step of the relative-luminance formula used by app.hex_color_relative_luminance().';

create function app.hex_color_relative_luminance(p_hex text)
returns numeric
language plpgsql
immutable
as $$
declare
  v_r numeric;
  v_g numeric;
  v_b numeric;
begin
  if p_hex is null or p_hex !~ '^#[0-9a-fA-F]{6}$' then
    raise exception 'invalid_hex_color: % is not a #RRGGBB hex color', p_hex
      using errcode = 'invalid_text_representation';
  end if;

  v_r := ('x' || substring(p_hex from 2 for 2))::bit(8)::int / 255.0;
  v_g := ('x' || substring(p_hex from 4 for 2))::bit(8)::int / 255.0;
  v_b := ('x' || substring(p_hex from 6 for 2))::bit(8)::int / 255.0;

  return 0.2126 * app.srgb_channel_to_linear(v_r)
       + 0.7152 * app.srgb_channel_to_linear(v_g)
       + 0.0722 * app.srgb_channel_to_linear(v_b);
end;
$$;

comment on function app.hex_color_relative_luminance is
  'WCAG 2.2 relative luminance of a #RRGGBB hex color (PLT-117). Raises invalid_hex_color on malformed input rather than silently returning a wrong value.';

create function app.hex_color_contrast_ratio(p_hex_a text, p_hex_b text)
returns numeric
language plpgsql
immutable
as $$
declare
  v_l_a numeric := app.hex_color_relative_luminance(p_hex_a);
  v_l_b numeric := app.hex_color_relative_luminance(p_hex_b);
  v_lighter numeric := greatest(v_l_a, v_l_b);
  v_darker numeric := least(v_l_a, v_l_b);
begin
  return round((v_lighter + 0.05) / (v_darker + 0.05), 4);
end;
$$;

comment on function app.hex_color_contrast_ratio is
  'WCAG 2.2 contrast ratio between two #RRGGBB hex colors (PLT-117), range 1:1..21:1. app.publish_tenant_brand_version()/app.rollback_tenant_brand_version() enforce a 4.5:1 (AA, normal text) minimum against the fixed neutral-50 (#fafafa) background token (docs/standards/DESIGN_SYSTEM.md §2.1) before allowing a version live.';

-- Token/asset/template structural validation (Prompt 117 §16/§24: "no arbitrary
-- executable style/script," "template variables... never arbitrary code"). Enforced as
-- CHECK constraints on app.tenant_brand_versions below -- a database guarantee, not an
-- application-layer convention, matching PLT-114's "column REVOKE, not a documented
-- rule" discipline.
create function app.validate_brand_tokens(p_tokens jsonb)
returns boolean
language plpgsql
immutable
as $$
declare
  v_key text;
  v_value jsonb;
begin
  if p_tokens is null or jsonb_typeof(p_tokens) <> 'object' then
    return false;
  end if;

  for v_key, v_value in select * from jsonb_each(p_tokens) loop
    if v_key not in ('primary', 'secondary') then
      return false;
    end if;
    if jsonb_typeof(v_value) <> 'string' then
      return false;
    end if;
    if (v_value #>> '{}') !~ '^#[0-9a-fA-F]{6}$' then
      return false;
    end if;
  end loop;

  return true;
end;
$$;

comment on function app.validate_brand_tokens is
  'PLT-117: tokens must be a JSON object containing only the keys primary/secondary (RPD-019''s color override surface), each a #RRGGBB hex string. An empty object ({}) is valid -- a draft may exist before any color is chosen.';

create function app.validate_brand_asset_url(p_url text)
returns boolean
language sql
immutable
as $$
  select p_url is null
    or (
      length(p_url) <= 2048
      and p_url ~ '^https://[a-zA-Z0-9.-]+(/[A-Za-z0-9._~%\-/]*)?$'
    );
$$;

comment on function app.validate_brand_asset_url is
  'PLT-117: an asset reference must be null or a well-formed https:// URL with a safe character set. Structurally rejects javascript:/data:/vbscript: URIs and any embedded quote/angle-bracket/whitespace injection vector -- the URL shape itself, not a documented convention, is what makes an unsafe value unrepresentable.';

create function app.validate_document_template_refs(p_refs jsonb)
returns boolean
language plpgsql
immutable
as $$
declare
  v_key text;
  v_value jsonb;
  v_text text;
begin
  if p_refs is null or jsonb_typeof(p_refs) <> 'object' then
    return false;
  end if;

  for v_key, v_value in select * from jsonb_each(p_refs) loop
    if v_key not in ('invoice_letterhead_url', 'quotation_letterhead_url', 'email_footer_text', 'email_header_text') then
      return false;
    end if;
    if jsonb_typeof(v_value) <> 'string' then
      return false;
    end if;

    v_text := v_value #>> '{}';
    if v_key like '%\_url' escape '\' then
      if not app.validate_brand_asset_url(v_text) then
        return false;
      end if;
    elsif length(v_text) > 500 or v_text ~ '[<>]' then
      return false;
    end if;
  end loop;

  return true;
end;
$$;

comment on function app.validate_document_template_refs is
  'PLT-117: document/email template references are a fixed, whitelisted key set (Prompt 117 §24: "template variables are whitelisted, never arbitrary code") -- *_url keys reuse app.validate_brand_asset_url(); free-text keys are length-capped and reject any angle bracket, so no HTML/script tag can ever be persisted.';

create table app.tenant_brand_versions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  version_number integer not null,
  status text not null default 'draft',
  tokens jsonb not null default '{}'::jsonb,
  logo_asset_url text,
  email_sender_name text,
  email_logo_asset_url text,
  document_template_refs jsonb not null default '{}'::jsonb,
  contrast_validated boolean not null default false,
  contrast_report jsonb,
  cloned_from_version_id uuid references app.tenant_brand_versions (id),
  rollback_of_version_id uuid references app.tenant_brand_versions (id),
  effective_from timestamptz,
  created_by text,
  published_by text,
  published_at timestamptz,
  archived_at timestamptz,
  archived_reason text,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint tenant_brand_versions_status_check check (status in ('draft', 'published', 'archived')),
  constraint tenant_brand_versions_tenant_version_unique unique (tenant_id, version_number),
  constraint tenant_brand_versions_tokens_check check (app.validate_brand_tokens(tokens)),
  constraint tenant_brand_versions_logo_url_check check (app.validate_brand_asset_url(logo_asset_url)),
  constraint tenant_brand_versions_email_logo_url_check check (app.validate_brand_asset_url(email_logo_asset_url)),
  constraint tenant_brand_versions_email_sender_name_check check (
    email_sender_name is null or (length(email_sender_name) <= 120 and email_sender_name !~ '[<>]')
  ),
  constraint tenant_brand_versions_document_template_refs_check check (app.validate_document_template_refs(document_template_refs))
);

comment on table app.tenant_brand_versions is
  'Versioned tenant white-label configuration (PLT-117) -- draft/publish/rollback, matching PLT-111''s app.role_versions immutable-once-published discipline. Every column is structurally validated (CHECK constraints above); the accessibility contrast gate is enforced separately, at publish/rollback time, by app.publish_tenant_brand_version()/app.rollback_tenant_brand_version() -- a draft may be saved below threshold for preview purposes, but can never go live below it.';

create index tenant_brand_versions_tenant_id_idx on app.tenant_brand_versions (tenant_id);
-- At most one draft per tenant at a time.
create unique index tenant_brand_versions_single_draft_per_tenant
  on app.tenant_brand_versions (tenant_id) where status = 'draft';
-- At most one published version per tenant at a time.
create unique index tenant_brand_versions_single_published_per_tenant
  on app.tenant_brand_versions (tenant_id) where status = 'published';

-- record_version/updated_at bump only -- status-transition legality is enforced inside
-- the mutation functions below, the same convention PLT-111's app.role_versions already
-- established (no separate transition-guard trigger there either).
create function app.touch_tenant_brand_version_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger tenant_brand_versions_touch_row
  before update on app.tenant_brand_versions
  for each row
  execute function app.touch_tenant_brand_version_row();

-- Idempotent draft creation, matching the established PLT-111 app.create_role_version
-- pattern. Authority: "Tenant Admin manages own permitted brand; Supreme may manage
-- defaults/override with audit" (Prompt 117 §26) -- exactly PLT-115's
-- app.is_support_grant_authority() (Supreme Admin, or the target tenant's own active
-- tenant_admin), reused verbatim rather than defining a second, competing authority
-- check.
create function app.create_tenant_brand_draft(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_created_by text
)
returns app.tenant_brand_versions
language plpgsql
as $$
declare
  v_existing_draft app.tenant_brand_versions;
  v_next_version integer;
  v_version app.tenant_brand_versions;
begin
  if not app.is_support_grant_authority(p_actor_auth_user_id, p_tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_existing_draft from app.tenant_brand_versions where tenant_id = p_tenant_id and status = 'draft';
  if found then
    return v_existing_draft;
  end if;

  select coalesce(max(version_number), 0) + 1 into v_next_version from app.tenant_brand_versions where tenant_id = p_tenant_id;

  insert into app.tenant_brand_versions (tenant_id, version_number, created_by)
  values (p_tenant_id, v_next_version, p_created_by)
  returning * into v_version;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_created_by, 'create_tenant_brand_draft',
    'app.tenant_brand_versions', v_version.id, 'success', null, null, to_jsonb(v_version)
  );

  return v_version;
end;
$$;

-- Replaces a draft's full token/asset/template set -- only valid while status='draft'
-- (a published version's bindings are never mutated, PLT-111's own discipline). Contrast
-- is computed and stored here as *informational preview evidence* only (a draft may be
-- saved and previewed below threshold); the enforced gate is at publish time, below.
create function app.set_tenant_brand_tokens(
  p_version_id uuid,
  p_actor_auth_user_id uuid,
  p_tokens jsonb,
  p_logo_asset_url text,
  p_email_sender_name text,
  p_email_logo_asset_url text,
  p_document_template_refs jsonb,
  p_actor_label text
)
returns app.tenant_brand_versions
language plpgsql
as $$
declare
  v_before app.tenant_brand_versions;
  v_after app.tenant_brand_versions;
  v_contrast numeric;
begin
  select * into v_before from app.tenant_brand_versions where id = p_version_id;
  if not found then
    raise exception 'brand_version_not_found: no tenant brand version %', p_version_id
      using errcode = 'no_data_found';
  end if;

  if not app.is_support_grant_authority(p_actor_auth_user_id, v_before.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_before.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_before.status <> 'draft' then
    raise exception 'brand_version_not_draft: version % is %, only a draft''s tokens may be changed', p_version_id, v_before.status
      using errcode = 'check_violation';
  end if;

  if p_tokens ? 'primary' then
    v_contrast := app.hex_color_contrast_ratio(p_tokens ->> 'primary', '#fafafa');
  end if;

  update app.tenant_brand_versions
  set tokens = p_tokens,
      logo_asset_url = p_logo_asset_url,
      email_sender_name = p_email_sender_name,
      email_logo_asset_url = p_email_logo_asset_url,
      document_template_refs = coalesce(p_document_template_refs, '{}'::jsonb),
      contrast_validated = coalesce(v_contrast >= 4.5, false),
      contrast_report = case when v_contrast is not null
        then jsonb_build_object('primary_vs_neutral_50', v_contrast, 'threshold', 4.5, 'checked_at', now())
        else null
      end
  where id = p_version_id
  returning * into v_after;

  perform app.capture_audit_event(
    v_after.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_tenant_brand_tokens',
    'app.tenant_brand_versions', v_after.id, 'success', null, to_jsonb(v_before), to_jsonb(v_after)
  );

  return v_after;
end;
$$;

-- Publishing archives the tenant's previously published version (supersession, PLT-111's
-- own app.publish_role_version pattern) and enforces the accessibility gate (Prompt 117
-- §23 exception flow: "poor contrast... is rejected"). A version with no primary color
-- set at all is exactly §22's "missing... tenant override uses accessible CargoGrid/
-- default theme" alternative flow -- nothing to validate, always publishable.
create function app.publish_tenant_brand_version(
  p_version_id uuid,
  p_actor_auth_user_id uuid,
  p_effective_from timestamptz,
  p_actor_label text
)
returns app.tenant_brand_versions
language plpgsql
as $$
declare
  v_version app.tenant_brand_versions;
  v_prior_published app.tenant_brand_versions;
  v_updated app.tenant_brand_versions;
  v_contrast numeric;
begin
  select * into v_version from app.tenant_brand_versions where id = p_version_id;
  if not found then
    raise exception 'brand_version_not_found: no tenant brand version %', p_version_id
      using errcode = 'no_data_found';
  end if;

  if not app.is_support_grant_authority(p_actor_auth_user_id, v_version.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_version.status <> 'draft' then
    raise exception 'brand_version_not_draft: version % is %, only a draft may be published', p_version_id, v_version.status
      using errcode = 'check_violation';
  end if;

  if v_version.tokens ? 'primary' then
    v_contrast := app.hex_color_contrast_ratio(v_version.tokens ->> 'primary', '#fafafa');
    if v_contrast < 4.5 then
      raise exception 'insufficient_contrast: primary color contrast ratio % is below the 4.5:1 WCAG AA minimum', v_contrast
        using errcode = 'check_violation';
    end if;
  end if;

  select * into v_prior_published from app.tenant_brand_versions where tenant_id = v_version.tenant_id and status = 'published';
  if found then
    update app.tenant_brand_versions
    set status = 'archived', archived_at = now(), archived_reason = 'superseded by a newer published version'
    where id = v_prior_published.id;
  end if;

  update app.tenant_brand_versions
  set status = 'published',
      published_by = p_actor_label,
      published_at = now(),
      effective_from = coalesce(p_effective_from, now()),
      contrast_validated = true,
      contrast_report = case when v_contrast is not null
        then jsonb_build_object('primary_vs_neutral_50', v_contrast, 'threshold', 4.5, 'checked_at', now())
        else contrast_report
      end
  where id = p_version_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_tenant_brand_version',
    'app.tenant_brand_versions', v_updated.id, 'success', null, to_jsonb(v_version), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

-- Discards a draft without publishing it (draft -> archived directly) -- distinct from
-- the published -> archived supersession path above.
create function app.discard_tenant_brand_draft(
  p_version_id uuid,
  p_actor_auth_user_id uuid,
  p_reason text,
  p_actor_label text
)
returns app.tenant_brand_versions
language plpgsql
as $$
declare
  v_version app.tenant_brand_versions;
  v_updated app.tenant_brand_versions;
begin
  select * into v_version from app.tenant_brand_versions where id = p_version_id;
  if not found then
    raise exception 'brand_version_not_found: no tenant brand version %', p_version_id
      using errcode = 'no_data_found';
  end if;

  if not app.is_support_grant_authority(p_actor_auth_user_id, v_version.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_version.status <> 'draft' then
    raise exception 'brand_version_not_draft: version % is %, only a draft may be discarded', p_version_id, v_version.status
      using errcode = 'check_violation';
  end if;

  update app.tenant_brand_versions
  set status = 'archived', archived_at = now(), archived_reason = coalesce(p_reason, 'discarded')
  where id = p_version_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'discard_tenant_brand_draft',
    'app.tenant_brand_versions', v_updated.id, 'success', p_reason, to_jsonb(v_version), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

-- Rollback (Prompt 117 §20 task 2: "versioned draft/publish/rollback model"). Never
-- mutates history -- it clones the target version's exact token/asset snapshot into a
-- brand-new version number and publishes that, the same "never mutate a historical
-- snapshot" discipline PLT-111's app.clone_role_version() established. The target may be
-- 'published' (rolling back to the immediately-prior state after a bad publish) or
-- 'archived' (rolling back further than one step) -- but never 'draft' (nothing stable
-- to roll back to). The contrast gate is re-applied here too, deliberately: an archived
-- version could have reached that state via app.discard_tenant_brand_draft() (a draft
-- that was never contrast-validated in the first place), so trusting a stored
-- contrast_validated flag from an arbitrary archived row would not be a real guarantee.
create function app.rollback_tenant_brand_version(
  p_target_version_id uuid,
  p_actor_auth_user_id uuid,
  p_reason text,
  p_actor_label text
)
returns app.tenant_brand_versions
language plpgsql
as $$
declare
  v_target app.tenant_brand_versions;
  v_contrast numeric;
  v_next_version integer;
  v_new_row app.tenant_brand_versions;
  v_prior_published app.tenant_brand_versions;
  v_published app.tenant_brand_versions;
begin
  select * into v_target from app.tenant_brand_versions where id = p_target_version_id;
  if not found then
    raise exception 'brand_version_not_found: no tenant brand version %', p_target_version_id
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

  if v_target.tokens ? 'primary' then
    v_contrast := app.hex_color_contrast_ratio(v_target.tokens ->> 'primary', '#fafafa');
    if v_contrast < 4.5 then
      raise exception 'insufficient_contrast: primary color contrast ratio % is below the 4.5:1 WCAG AA minimum', v_contrast
        using errcode = 'check_violation';
    end if;
  end if;

  select coalesce(max(version_number), 0) + 1 into v_next_version from app.tenant_brand_versions where tenant_id = v_target.tenant_id;

  insert into app.tenant_brand_versions (
    tenant_id, version_number, tokens, logo_asset_url, email_sender_name, email_logo_asset_url,
    document_template_refs, cloned_from_version_id, rollback_of_version_id, created_by
  )
  values (
    v_target.tenant_id, v_next_version, v_target.tokens, v_target.logo_asset_url, v_target.email_sender_name,
    v_target.email_logo_asset_url, v_target.document_template_refs, p_target_version_id, p_target_version_id, p_actor_label
  )
  returning * into v_new_row;

  select * into v_prior_published from app.tenant_brand_versions where tenant_id = v_target.tenant_id and status = 'published';
  if found then
    update app.tenant_brand_versions
    set status = 'archived', archived_at = now(), archived_reason = 'superseded by rollback to version ' || v_target.version_number
    where id = v_prior_published.id;
  end if;

  update app.tenant_brand_versions
  set status = 'published',
      published_by = p_actor_label,
      published_at = now(),
      effective_from = now(),
      contrast_validated = true,
      contrast_report = jsonb_build_object('rollback_of_version_number', v_target.version_number, 'checked_at', now())
  where id = v_new_row.id
  returning * into v_published;

  perform app.capture_audit_event(
    v_published.tenant_id, p_actor_auth_user_id, p_actor_label, 'rollback_tenant_brand_version',
    'app.tenant_brand_versions', v_published.id, 'success', p_reason, to_jsonb(v_target), to_jsonb(v_published)
  );

  return v_published;
end;
$$;

-- Public presentation-data evaluator (Prompt 117 §14: "permission-aware config/read/
-- evaluate contract with cache invalidation" -- "permission-aware" here means "resolves
-- to the one correct tenant's effective brand," not an access-control gate: RPD-019
-- branding is deliberately non-confidential, and a tenant's login page must be able to
-- render its brand *before* the visitor has authenticated at all, so this function is
-- grantable to `anon` as well as `authenticated`/`service_role` -- a deliberate,
-- disclosed departure from this repository's default-deny grant posture, justified by
-- the data's own non-sensitivity rather than an oversight. SECURITY DEFINER + a fixed
-- search_path (closing the standard SECURITY DEFINER search-path-injection footgun)
-- because `authenticated`/`anon` are never granted direct SELECT on
-- app.tenant_brand_versions itself -- draft content is never exposed through this path,
-- only the current published version or the accessible default.
create function app.evaluate_tenant_brand(p_tenant_id uuid)
returns table (
  tenant_id uuid,
  source text,
  version_id uuid,
  version_number integer,
  tokens jsonb,
  logo_asset_url text,
  email_sender_name text,
  email_logo_asset_url text,
  document_template_refs jsonb,
  effective_from timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_tenant app.tenants;
  v_published app.tenant_brand_versions;
begin
  -- Table columns are qualified with an explicit alias throughout this function --
  -- unlike every other function in this migration, this one's own RETURNS TABLE clause
  -- declares an output column literally named tenant_id, which otherwise shadows/
  -- collides with app.tenant_brand_versions.tenant_id (a real ambiguous-reference error
  -- caught by this checkpoint's own db-tests, not a hypothetical).
  select * into v_tenant from app.tenants t where t.id = p_tenant_id;

  if found and v_tenant.canonical_status = 'active' then
    select * into v_published from app.tenant_brand_versions v where v.tenant_id = p_tenant_id and v.status = 'published';
  end if;

  if v_published.id is not null then
    return query select
      p_tenant_id, 'tenant'::text, v_published.id, v_published.version_number,
      v_published.tokens, v_published.logo_asset_url, v_published.email_sender_name,
      v_published.email_logo_asset_url, v_published.document_template_refs, v_published.effective_from;
  else
    -- Accessible CargoGrid default (Prompt 117 §22 alternative flow) -- see this
    -- migration's own header for why both roles map to the one sourced neutral-900
    -- value rather than a fabricated brand color.
    return query select
      p_tenant_id, 'default'::text, null::uuid, null::integer,
      '{"primary": "#171717", "secondary": "#171717"}'::jsonb,
      null::text, null::text, null::text, '{}'::jsonb, null::timestamptz;
  end if;
end;
$$;

comment on function app.evaluate_tenant_brand is
  'Resolves a tenant''s effective white-label brand (PLT-117): the current published version if the tenant is active and has one, otherwise the accessible CargoGrid default (Prompt 117 §22). Deliberately granted to anon as well as authenticated -- see this function''s own comment for why. Cache invalidation (Prompt 117 §14) is the caller''s responsibility (server/queries/white-label.ts), keyed on tenant_id+version_id exactly as app.evaluate_entitlement()''s own cache (PLT-106) already established the pattern -- a new published/rolled-back version_id is a fresh cache key, so no explicit invalidation call is needed.';

alter table app.tenant_brand_versions enable row level security;

-- No RLS SELECT policy is defined for `authenticated`/`anon` -- deliberately, matching
-- PLT-116's app.audit_logs posture: the only read path for anyone but service_role is
-- the SECURITY DEFINER app.evaluate_tenant_brand() above, which structurally never
-- exposes draft content or any tenant's data other than the one requested.
grant select, insert, update, delete on app.tenant_brand_versions to service_role;
grant execute on function app.srgb_channel_to_linear(numeric) to service_role;
grant execute on function app.hex_color_relative_luminance(text) to service_role;
grant execute on function app.hex_color_contrast_ratio(text, text) to service_role;
grant execute on function app.validate_brand_tokens(jsonb) to service_role;
grant execute on function app.validate_brand_asset_url(text) to service_role;
grant execute on function app.validate_document_template_refs(jsonb) to service_role;
-- All five mutation RPCs are service_role-only, matching PLT-115's
-- request/approve/deny/revoke_support_access precedent exactly: every one of them also
-- calls app.is_support_grant_authority() internally (service_role-only itself, never
-- granted to authenticated) as its own defense-in-depth authority check, and this
-- repository's established architecture is that the application server authenticates
-- and authorizes the end-user session itself, then calls these RPCs with service_role
-- credentials -- not a direct authenticated-session-to-RPC path (AGENTS.md: "service-role
-- credentials are server-only"). Only app.evaluate_tenant_brand() (public presentation
-- data, no privileged content) is exposed further, below.
grant execute on function app.create_tenant_brand_draft(uuid, uuid, text) to service_role;
grant execute on function app.set_tenant_brand_tokens(uuid, uuid, jsonb, text, text, text, jsonb, text) to service_role;
grant execute on function app.publish_tenant_brand_version(uuid, uuid, timestamptz, text) to service_role;
grant execute on function app.discard_tenant_brand_draft(uuid, uuid, text, text) to service_role;
grant execute on function app.rollback_tenant_brand_version(uuid, uuid, text, text) to service_role;
grant execute on function app.evaluate_tenant_brand(uuid) to anon, authenticated, service_role;
