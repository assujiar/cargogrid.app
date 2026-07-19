-- Platform Core capability PLT-127 (Notification Engine, CG-S6-PLT-024)
-- Tenant-aware in-app/email-ready notification primitives -- templates, preferences,
-- dedupe, retries, and audit (Prompt 127 §4). A notification *template* is not a new
-- table family, exactly like `PLT-122`/`123`/`124`/`125`/`126`'s definitions -- it is
-- `PLT-121`'s own Configuration Engine, reused directly, with one dedicated
-- `notification:<code>` config_type minted per notification type (the same "registry,
-- not enum" composition `PLT-124`'s Status Engine established, for the identical
-- structural reason: the single shared seeded `'notification'` type can host at most
-- one tenant-scoped object).
--
-- Scope, disclosed rather than left implicit (matching every prior checkpoint's
-- discipline):
--
-- * **No real provider send exists anywhere in this migration** (§12, forbidden: "live
--   provider sends without authority... generic integration hub"; §19: "no real
--   recipient sends during migration/tests"). `in_app` delivery is real and complete --
--   the notification row's own existence *is* the delivery, there is no external
--   dependency. Any non-`in_app` channel (currently just `email`) is real up through
--   "queued" -- `app.queue_notification()` renders the template, resolves the
--   authorized recipient, and inserts a durable, auditable row -- but no code anywhere
--   in this repository ever calls a real email provider. `app.record_notification_
--   delivery_attempt()` is the bounded adapter interface §11 asks for: a future
--   capability that owns a real provider integration calls it to report success/
--   failure; this migration never calls it against a fabricated provider itself.
-- * **No domain notification type exists anywhere in this migration.** The one
--   representative example (a `role_assignment_granted`-shaped notification) is built
--   and proven entirely inside `scripts/db-tests/notification.sql` -- no type/template
--   row of any kind is seeded into this migration itself.
-- * **Template escaping is real, at both write time and render time** (§16). Every
--   template string is a `config_items.value`, so it already passes through
--   `PLT-121`'s own `app.validate_config_value()` `<>`-rejecting CHECK constraint at
--   definition time -- no HTML/script markup can ever be stored in a template.
--   `app.render_notification_template()` applies the identical `<>` rejection to every
--   *context* value substituted in at render time too (`notification_unsafe_context_
--   value`) -- the real injection vector is untrusted event/recipient data flowing
--   through `{{token}}` substitution, not the tenant-authored template text alone.
-- * **A real link allowlist, not a fabricated one** (§16). Any context value that looks
--   like a URL (`scheme://...`) must use `https://` -- `app.render_notification_
--   template()` rejects any other scheme (`notification_unsafe_link`), structurally
--   ruling out `javascript:`/`data:`-scheme injection through templated action links.
-- * **Recipient authorization is real and fails safely** (§16/§23/§25: "No send to
--   unauthorized/deactivated/wrong-tenant user"). `app.queue_notification()` requires
--   the recipient to be an *active* member of the target tenant right now
--   (`app.has_active_tenant_membership()`) -- a revoked/deactivated/wrong-tenant
--   identity is refused outright (`notification_recipient_unauthorized`), never queued
--   and never delivered.
-- * **Preference-aware fallback is real** (§22: "User preference/channel unavailable
--   uses allowed fallback/in-app delivery"). If a recipient has explicitly disabled
--   their requested channel, `app.queue_notification()` falls back to `in_app` when the
--   definition also allows it and the recipient has not also disabled that -- otherwise
--   the attempt is recorded as `skipped`, never silently dropped without a trace.
-- * **Notifications are never workflow truth** (§24). This migration creates no status
--   column any other capability reads as authoritative -- `entity_type`/`entity_id`
--   context (inside the `context` jsonb payload, not a structural FK) is purely
--   informational, the same disclosed posture every prior instance/request table in
--   this session already carries forward.
-- * **The in-app inbox RLS posture is deliberately tighter than every prior engine's**
--   business-data table (`PLT-113`/`122`/`123`/`125`/`126`'s own `has_active_tenant_
--   membership()`-wide posture) -- `app.notifications`/`app.notification_preferences`
--   are a personal inbox/personal settings, not shared tenant business data, so RLS
--   scopes `SELECT` to `recipient_auth_user_id = auth.uid()` / `auth_user_id =
--   auth.uid()` (plus Supreme Admin), not "any active tenant member."
-- * Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration carries its own
--   explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement
--   before its final grants, the standing per-migration convention since `PLT-118`.

create table app.notification_types (
  code text primary key,
  name text not null,
  owner_primitive_code text not null,
  registered_by text,
  created_at timestamptz not null default now()
);

comment on table app.notification_types is
  'PLT-127: the registry of notification type identities. Registering a type also mints its own dedicated app.config_types row (code ''notification:<code>'') via app.register_config_type() -- this migration''s own header explains why one shared generic type cannot host every notification type''s independent tenant template.';

create function app.register_notification_type(
  p_code text,
  p_name text,
  p_owner_primitive_code text,
  p_actor_auth_user_id uuid,
  p_registered_by text
)
returns app.notification_types
language plpgsql
as $$
declare
  v_existing app.notification_types;
  v_type app.notification_types;
begin
  if not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: only Supreme Admin may register a notification type'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_existing from app.notification_types where code = p_code;
  if found then
    return v_existing;
  end if;

  insert into app.notification_types (code, name, owner_primitive_code, registered_by)
  values (p_code, p_name, p_owner_primitive_code, p_registered_by)
  returning * into v_type;

  perform app.register_config_type('notification:' || p_code, p_name, p_owner_primitive_code, p_actor_auth_user_id, p_registered_by);

  perform app.capture_audit_event(
    null, p_actor_auth_user_id, p_registered_by, 'register_notification_type',
    'app.notification_types', null, 'success', null, null, to_jsonb(v_type)
  );

  return v_type;
end;
$$;

-- Publish-time structural gate over a 'notification:<code>'-typed config_version's own
-- config_items (Prompt 127 §20 task 1/2). Expects 'channels' (jsonb array, subset of
-- the bounded allowlist), 'default_locale' (a real PLT-119 locale code), and
-- 'templates' (jsonb object keyed by locale, each {subject, body}).
create function app.validate_notification_template(p_version_id uuid)
returns boolean
language plpgsql
as $$
declare
  v_channels jsonb;
  v_channel text;
  v_default_locale text;
  v_templates jsonb;
  v_locale text;
  v_template jsonb;
  v_allowed_channels text[] := array['in_app', 'email'];
begin
  select value into v_channels from app.config_items where config_version_id = p_version_id and key = 'channels';
  select value #>> '{}' into v_default_locale from app.config_items where config_version_id = p_version_id and key = 'default_locale';
  select value into v_templates from app.config_items where config_version_id = p_version_id and key = 'templates';

  if v_channels is null or jsonb_typeof(v_channels) <> 'array' or jsonb_array_length(v_channels) = 0 then
    raise exception 'notification_missing_channels: version % has no ''channels'' item, or it is not a non-empty array', p_version_id
      using errcode = 'check_violation';
  end if;
  for v_channel in select * from jsonb_array_elements_text(v_channels) loop
    if not (v_channel = any (v_allowed_channels)) then
      raise exception 'notification_invalid_channel: channel % is not one of in_app/email', v_channel
        using errcode = 'check_violation';
    end if;
  end loop;

  if v_default_locale is null or not app.validate_locale_code(v_default_locale) then
    raise exception 'notification_invalid_locale: default_locale % is not a supported locale', v_default_locale
      using errcode = 'check_violation';
  end if;

  if v_templates is null or jsonb_typeof(v_templates) <> 'object' then
    raise exception 'notification_missing_templates: version % has no ''templates'' item, or it is not an object', p_version_id
      using errcode = 'check_violation';
  end if;
  if not (v_templates ? v_default_locale) then
    raise exception 'notification_missing_default_template: templates has no entry for default_locale %', v_default_locale
      using errcode = 'check_violation';
  end if;

  for v_locale, v_template in select * from jsonb_each(v_templates) loop
    if not app.validate_locale_code(v_locale) then
      raise exception 'notification_invalid_locale: templates key % is not a supported locale', v_locale
        using errcode = 'check_violation';
    end if;
    if coalesce(v_template ->> 'subject', '') = '' then
      raise exception 'notification_missing_subject: locale %''s template has no non-empty subject', v_locale
        using errcode = 'check_violation';
    end if;
    if coalesce(v_template ->> 'body', '') = '' then
      raise exception 'notification_missing_body: locale %''s template has no non-empty body', v_locale
        using errcode = 'check_violation';
    end if;
    if (length(v_template ->> 'subject') - length(replace(v_template ->> 'subject', '{{', ''))) / 2 <>
       (length(v_template ->> 'subject') - length(replace(v_template ->> 'subject', '}}', ''))) / 2
    then
      raise exception 'notification_invalid_template_tokens: locale %''s subject has unbalanced {{ }} token braces', v_locale
        using errcode = 'check_violation';
    end if;
    if (length(v_template ->> 'body') - length(replace(v_template ->> 'body', '{{', ''))) / 2 <>
       (length(v_template ->> 'body') - length(replace(v_template ->> 'body', '}}', ''))) / 2
    then
      raise exception 'notification_invalid_template_tokens: locale %''s body has unbalanced {{ }} token braces', v_locale
        using errcode = 'check_violation';
    end if;
  end loop;

  return true;
end;
$$;

comment on function app.validate_notification_template is
  'PLT-127: the publish-time structural gate -- channels are a real bounded allowlist, default_locale and every templates key is a real PLT-119 locale code, every locale has a non-empty subject/body with balanced {{ }} token braces. Raises a distinct, named exception per failure mode.';

create function app.publish_notification_template(
  p_version_id uuid,
  p_actor_auth_user_id uuid,
  p_effective_from timestamptz,
  p_actor_label text
)
returns app.config_versions
language plpgsql
as $$
begin
  perform app.validate_notification_template(p_version_id);
  return app.publish_config_version(p_version_id, p_actor_auth_user_id, p_effective_from, p_actor_label);
end;
$$;

-- Pure rendering: locale-aware template lookup (falling back to default_locale) plus
-- bounded {{token}} substitution from p_context. Real, load-bearing safety checks on
-- every substituted value -- never on the static template text alone (this migration's
-- own header): any context value containing '<' or '>' is rejected outright
-- (notification_unsafe_context_value), and any context value shaped like a URL must be
-- https:// (notification_unsafe_link).
-- SECURITY DEFINER: app.config_items carries no direct authenticated grant at all
-- (draft-bearing config content, PLT-121's own posture) -- this function is a real
-- read path for authenticated (a live template preview), so it must run with the
-- owner's privilege to see the underlying config_items rows, the exact bug class
-- ERR-2026-004 first caught in app.mask_email().
create function app.render_notification_template(p_config_version_id uuid, p_locale text, p_context jsonb)
returns table (subject text, body text)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_default_locale text;
  v_templates jsonb;
  v_template jsonb;
  v_effective_locale text;
  v_subject text;
  v_body text;
  v_key text;
  v_value jsonb;
  v_value_text text;
begin
  select value #>> '{}' into v_default_locale from app.config_items where config_version_id = p_config_version_id and key = 'default_locale';
  select value into v_templates from app.config_items where config_version_id = p_config_version_id and key = 'templates';

  v_effective_locale := case when v_templates ? p_locale then p_locale else v_default_locale end;
  v_template := v_templates -> v_effective_locale;
  v_subject := v_template ->> 'subject';
  v_body := v_template ->> 'body';

  for v_key, v_value in select * from jsonb_each(coalesce(p_context, '{}'::jsonb)) loop
    v_value_text := coalesce(v_value #>> '{}', '');
    if v_value_text ~ '[<>]' then
      raise exception 'notification_unsafe_context_value: context key % contains an angle bracket, refusing to render', v_key
        using errcode = 'check_violation';
    end if;
    if v_value_text ~ '^[a-zA-Z][a-zA-Z0-9+.-]*://' and v_value_text !~ '^https://' then
      raise exception 'notification_unsafe_link: context key % is a non-https:// URL, refusing to render', v_key
        using errcode = 'check_violation';
    end if;
    -- javascript:/data:/vbscript: URIs carry no "://" (unlike http(s)://), so the
    -- scheme://-shaped check above alone would miss them -- a real, bounded
    -- known-dangerous-scheme blocklist catches this class without false-positiving on
    -- ordinary colon-containing text (e.g. "Note: important"), which a broader
    -- "any word followed by a colon" pattern would.
    if v_value_text ~* '^(javascript|data|vbscript):' then
      raise exception 'notification_unsafe_link: context key % uses a disallowed URI scheme, refusing to render', v_key
        using errcode = 'check_violation';
    end if;
    v_subject := replace(v_subject, '{{' || v_key || '}}', v_value_text);
    v_body := replace(v_body, '{{' || v_key || '}}', v_value_text);
  end loop;

  return query select v_subject, v_body;
end;
$$;

create table app.notification_preferences (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  auth_user_id uuid not null references auth.users (id),
  notification_type_code text not null,
  channel text not null,
  enabled boolean not null default true,
  updated_at timestamptz not null default now(),
  constraint notification_preferences_channel_check check (channel in ('in_app', 'email')),
  constraint notification_preferences_unique unique (tenant_id, auth_user_id, notification_type_code, channel)
);

create index notification_preferences_recipient_idx on app.notification_preferences (tenant_id, auth_user_id);

-- Self-service by default; a tenant's own support-grant authority (PLT-115's
-- app.is_support_grant_authority(), the same authority PLT-121's
-- app.check_config_object_authority() composes for non-global scopes) may also set a
-- preference on a user's behalf.
create function app.set_notification_preference(
  p_tenant_id uuid,
  p_auth_user_id uuid,
  p_notification_type_code text,
  p_channel text,
  p_enabled boolean,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.notification_preferences
language plpgsql
as $$
declare
  v_existing app.notification_preferences;
  v_row app.notification_preferences;
begin
  if p_actor_auth_user_id <> p_auth_user_id and not app.is_support_grant_authority(p_actor_auth_user_id, p_tenant_id) then
    raise exception 'insufficient_authority: identity % may not set a notification preference on behalf of %', p_actor_auth_user_id, p_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_existing from app.notification_preferences where tenant_id = p_tenant_id and auth_user_id = p_auth_user_id and notification_type_code = p_notification_type_code and channel = p_channel;

  insert into app.notification_preferences (tenant_id, auth_user_id, notification_type_code, channel, enabled)
  values (p_tenant_id, p_auth_user_id, p_notification_type_code, p_channel, p_enabled)
  on conflict (tenant_id, auth_user_id, notification_type_code, channel)
  do update set enabled = p_enabled, updated_at = now()
  returning * into v_row;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'set_notification_preference',
    'app.notification_preferences', v_row.id, 'success', null, to_jsonb(v_existing), to_jsonb(v_row)
  );

  return v_row;
end;
$$;

-- SECURITY DEFINER: the function's own authority check (self, or a tenant's support-
-- grant authority) is the real access boundary here, deliberately broader than the
-- table's own self-only RLS policy would allow for a non-Supreme admin-on-behalf-of
-- read -- the same "the function itself is the access-control boundary" posture
-- PLT-126's app.get_custom_field_values() already established.
create function app.get_notification_preferences(p_tenant_id uuid, p_auth_user_id uuid, p_actor_auth_user_id uuid)
returns setof app.notification_preferences
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  if p_actor_auth_user_id <> p_auth_user_id and not app.is_support_grant_authority(p_actor_auth_user_id, p_tenant_id) then
    raise exception 'insufficient_authority: identity % may not read notification preferences for %', p_actor_auth_user_id, p_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.notification_preferences where tenant_id = p_tenant_id and auth_user_id = p_auth_user_id;
end;
$$;

create table app.notifications (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  config_version_id uuid not null references app.config_versions (id),
  notification_type_code text not null,
  recipient_auth_user_id uuid not null references auth.users (id),
  requested_channel text not null,
  effective_channel text not null,
  locale text not null,
  subject text not null,
  body text not null,
  context jsonb not null default '{}'::jsonb,
  status text not null default 'queued',
  dedupe_key text not null,
  triggered_by_auth_user_id uuid references auth.users (id),
  triggered_by text,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint notifications_requested_channel_check check (requested_channel in ('in_app', 'email')),
  constraint notifications_effective_channel_check check (effective_channel in ('in_app', 'email')),
  constraint notifications_status_check check (status in ('queued', 'sent', 'failed', 'skipped')),
  constraint notifications_context_check check (app.validate_config_value(context)),
  constraint notifications_dedupe_unique unique (tenant_id, notification_type_code, recipient_auth_user_id, requested_channel, dedupe_key)
);

comment on table app.notifications is
  'PLT-127: one row per queued/delivered notification. in_app delivery is real and complete the instant this row exists (status=sent); any other channel (email) is real only up through status=queued -- no live provider send happens anywhere in this repository (this migration''s own header). Notifications are never workflow truth (Prompt 127 §24) -- context is informational only, never a structural FK to a source record.';

create index notifications_recipient_idx on app.notifications (tenant_id, recipient_auth_user_id, created_at);
create index notifications_config_version_id_idx on app.notifications (config_version_id);

create function app.touch_notifications_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger notifications_touch_row
  before update on app.notifications
  for each row
  execute function app.touch_notifications_row();

create table app.notification_delivery_attempts (
  id uuid primary key default gen_random_uuid(),
  notification_id uuid not null references app.notifications (id),
  attempt_number integer not null,
  status text not null,
  error_message text,
  attempted_at timestamptz not null default now(),
  constraint notification_delivery_attempts_status_check check (status in ('success', 'failed')),
  constraint notification_delivery_attempts_number_check check (attempt_number >= 1),
  constraint notification_delivery_attempts_unique unique (notification_id, attempt_number)
);

comment on table app.notification_delivery_attempts is
  'PLT-127: append-only retry evidence (Prompt 127 §17/§28: "retry" tests). app.record_notification_delivery_attempt() is the bounded adapter interface a future real-provider capability calls to report success/failure -- this migration itself never calls it against a fabricated provider.';

create index notification_delivery_attempts_notification_id_idx on app.notification_delivery_attempts (notification_id, attempt_number);

-- Trigger-time authority (Prompt 127 §26): who may cause a notification to be queued --
-- the same has_active_tenant_membership()-or-Supreme instance-level posture
-- PLT-122/123/125/126's own instance-level authority checks use.
create function app.check_notification_trigger_authority(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
as $$
  select app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) or app.is_supreme_admin(p_actor_auth_user_id);
$$;

-- The main "send" entry point (Prompt 127 §21/§22/§23/§25). Idempotent on
-- (tenant, notification_type, recipient, requested_channel, dedupe_key). Refuses to
-- queue for a recipient who is not currently an active tenant member
-- (notification_recipient_unauthorized). Applies the real preference-aware fallback:
-- a disabled requested channel falls back to in_app when the definition allows it and
-- in_app is not also disabled; otherwise the attempt is recorded as status=skipped
-- (never silently dropped without a trace).
create function app.queue_notification(
  p_config_version_id uuid,
  p_tenant_id uuid,
  p_notification_type_code text,
  p_recipient_auth_user_id uuid,
  p_channel text,
  p_locale text,
  p_context jsonb,
  p_dedupe_key text,
  p_actor_auth_user_id uuid,
  p_triggered_by text
)
returns app.notifications
language plpgsql
as $$
declare
  v_version app.config_versions;
  v_existing app.notifications;
  v_channels jsonb;
  v_effective_channel text;
  v_status text;
  v_requested_pref app.notification_preferences;
  v_in_app_pref app.notification_preferences;
  v_rendered record;
  v_row app.notifications;
begin
  if not app.check_notification_trigger_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_version from app.config_versions where id = p_config_version_id;
  if not found or v_version.status <> 'published' then
    raise exception 'notification_template_not_published: config version % is not a published notification template', p_config_version_id
      using errcode = 'check_violation';
  end if;

  if not app.has_active_tenant_membership(p_tenant_id, p_recipient_auth_user_id) then
    raise exception 'notification_recipient_unauthorized: identity % is not an active member of tenant % -- refusing to queue', p_recipient_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_existing from app.notifications where tenant_id = p_tenant_id and notification_type_code = p_notification_type_code and recipient_auth_user_id = p_recipient_auth_user_id and requested_channel = p_channel and dedupe_key = p_dedupe_key;
  if found then
    return v_existing;
  end if;

  select value into v_channels from app.config_items where config_version_id = p_config_version_id and key = 'channels';
  if not (v_channels ? p_channel) then
    raise exception 'notification_channel_not_supported: channel % is not declared by this notification type', p_channel
      using errcode = 'check_violation';
  end if;

  select * into v_requested_pref from app.notification_preferences where tenant_id = p_tenant_id and auth_user_id = p_recipient_auth_user_id and notification_type_code = p_notification_type_code and channel = p_channel;

  if found and not v_requested_pref.enabled then
    select * into v_in_app_pref from app.notification_preferences where tenant_id = p_tenant_id and auth_user_id = p_recipient_auth_user_id and notification_type_code = p_notification_type_code and channel = 'in_app';
    if p_channel <> 'in_app' and (v_channels ? 'in_app') and not (found and not v_in_app_pref.enabled) then
      v_effective_channel := 'in_app';
      v_status := 'sent';
    else
      v_effective_channel := p_channel;
      v_status := 'skipped';
    end if;
  else
    v_effective_channel := p_channel;
    v_status := case when p_channel = 'in_app' then 'sent' else 'queued' end;
  end if;

  if v_status = 'skipped' then
    insert into app.notifications (tenant_id, config_version_id, notification_type_code, recipient_auth_user_id, requested_channel, effective_channel, locale, subject, body, context, status, dedupe_key, triggered_by_auth_user_id, triggered_by)
    values (p_tenant_id, p_config_version_id, p_notification_type_code, p_recipient_auth_user_id, p_channel, v_effective_channel, coalesce(p_locale, 'en'), '', '', coalesce(p_context, '{}'::jsonb), v_status, p_dedupe_key, p_actor_auth_user_id, p_triggered_by)
    returning * into v_row;
  else
    select * into v_rendered from app.render_notification_template(p_config_version_id, p_locale, p_context);
    insert into app.notifications (tenant_id, config_version_id, notification_type_code, recipient_auth_user_id, requested_channel, effective_channel, locale, subject, body, context, status, dedupe_key, triggered_by_auth_user_id, triggered_by)
    values (p_tenant_id, p_config_version_id, p_notification_type_code, p_recipient_auth_user_id, p_channel, v_effective_channel, coalesce(p_locale, 'en'), v_rendered.subject, v_rendered.body, coalesce(p_context, '{}'::jsonb), v_status, p_dedupe_key, p_actor_auth_user_id, p_triggered_by)
    returning * into v_row;
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_triggered_by, 'queue_notification',
    'app.notifications', v_row.id, 'success', null, null, to_jsonb(v_row)
  );

  return v_row;
end;
$$;

-- Bounded adapter interface (Prompt 127 §11: "one bounded adapter interface"). A real
-- external-provider integration (not built here -- this migration's own header) calls
-- this to report the outcome of one delivery attempt against a non-in_app notification.
create function app.record_notification_delivery_attempt(
  p_notification_id uuid,
  p_status text,
  p_error_message text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.notification_delivery_attempts
language plpgsql
as $$
declare
  v_notification app.notifications;
  v_next_attempt integer;
  v_attempt app.notification_delivery_attempts;
begin
  select * into v_notification from app.notifications where id = p_notification_id;
  if not found then
    raise exception 'notification_not_found: no notification %', p_notification_id
      using errcode = 'no_data_found';
  end if;
  if not app.check_notification_trigger_authority(v_notification.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, v_notification.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_status not in ('success', 'failed') then
    raise exception 'notification_invalid_attempt_status: status % must be success or failed', p_status
      using errcode = 'check_violation';
  end if;

  select coalesce(max(attempt_number), 0) + 1 into v_next_attempt from app.notification_delivery_attempts where notification_id = p_notification_id;

  insert into app.notification_delivery_attempts (notification_id, attempt_number, status, error_message)
  values (p_notification_id, v_next_attempt, p_status, p_error_message)
  returning * into v_attempt;

  update app.notifications set status = case when p_status = 'success' then 'sent' else 'failed' end where id = p_notification_id;

  perform app.capture_audit_event(
    v_notification.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_notification_delivery_attempt',
    'app.notification_delivery_attempts', v_attempt.id, case when p_status = 'success' then 'success' else 'failure' end, p_error_message, null, to_jsonb(v_attempt)
  );

  return v_attempt;
end;
$$;

-- Only the recipient themselves (or Supreme) may mark their own notification read.
-- SECURITY DEFINER: authenticated holds no direct UPDATE grant on app.notifications
-- (writes stay RPC-only) -- this function's own authority check is the write boundary.
create function app.mark_notification_read(
  p_notification_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.notifications
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_notification app.notifications;
  v_updated app.notifications;
begin
  select * into v_notification from app.notifications where id = p_notification_id;
  if not found then
    raise exception 'notification_not_found: no notification %', p_notification_id
      using errcode = 'no_data_found';
  end if;
  if p_actor_auth_user_id <> v_notification.recipient_auth_user_id and not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % may not mark another identity''s notification read', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.notifications set read_at = coalesce(read_at, now()) where id = p_notification_id returning * into v_updated;

  perform app.capture_audit_event(
    v_notification.tenant_id, p_actor_auth_user_id, p_actor_label, 'mark_notification_read',
    'app.notifications', v_updated.id, 'success', null, to_jsonb(v_notification), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

-- The in-app inbox view model (Prompt 127 §15: "in-app notification list/count").
-- SECURITY DEFINER: makes the function's own authority check (self, or Supreme) the
-- real access boundary, rather than depending on auth.uid()/parameter alignment with
-- the table's own RLS policy.
create function app.list_notifications_for_recipient(
  p_tenant_id uuid,
  p_recipient_auth_user_id uuid,
  p_actor_auth_user_id uuid,
  p_unread_only boolean default false
)
returns setof app.notifications
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  if p_actor_auth_user_id <> p_recipient_auth_user_id and not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % may not list another identity''s notifications', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;
  return query
    select * from app.notifications
    where tenant_id = p_tenant_id and recipient_auth_user_id = p_recipient_auth_user_id
      and (not p_unread_only or (read_at is null and effective_channel = 'in_app'))
    order by created_at desc;
end;
$$;

-- SECURITY DEFINER: same reasoning as app.list_notifications_for_recipient() above.
create function app.count_unread_notifications(
  p_tenant_id uuid,
  p_recipient_auth_user_id uuid,
  p_actor_auth_user_id uuid
)
returns integer
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_count integer;
begin
  if p_actor_auth_user_id <> p_recipient_auth_user_id and not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % may not count another identity''s notifications', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;
  select count(*) into v_count from app.notifications
  where tenant_id = p_tenant_id and recipient_auth_user_id = p_recipient_auth_user_id
    and effective_channel = 'in_app' and read_at is null and status = 'sent';
  return v_count;
end;
$$;

alter table app.notification_types enable row level security;
alter table app.notification_preferences enable row level security;
alter table app.notifications enable row level security;

-- app.notification_types is platform-owned reference data -- safe to expose broadly,
-- the same posture PLT-122/124/126's own registries already established.
create policy notification_types_select_authenticated on app.notification_types
  for select to authenticated
  using (true);

-- Personal inbox / personal settings, not shared tenant business data -- this
-- migration's own header explains the deliberately tighter (self-only) RLS posture.
create policy notification_preferences_select_own on app.notification_preferences
  for select to authenticated
  using (auth_user_id = auth.uid() or app.is_supreme_admin());

create policy notifications_select_own on app.notifications
  for select to authenticated
  using (recipient_auth_user_id = auth.uid() or app.is_supreme_admin());

-- app.notification_delivery_attempts has no tenant_id/recipient column of its own (it
-- belongs to a notification) and no domain UI needs to browse it directly yet -- no
-- direct authenticated grant at all, service_role-only internal evidence, the same
-- posture PLT-116's audit_logs and PLT-122's workflow_transition_history established
-- for a table with no simple direct RLS predicate and no dedicated read function built
-- in this bounded checkpoint.

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke
-- of PostgreSQL's PUBLIC-execute default, the standing per-migration convention since
-- PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant select on app.notification_types to authenticated, service_role;
grant insert, update, delete on app.notification_types to service_role;
grant select on app.notification_preferences to authenticated, service_role;
grant insert, update, delete on app.notification_preferences to service_role;
grant select on app.notifications to authenticated, service_role;
grant insert, update, delete on app.notifications to service_role;
grant select, insert, update, delete on app.notification_delivery_attempts to service_role;

grant execute on function app.register_notification_type(text, text, text, uuid, text) to service_role;
grant execute on function app.validate_notification_template(uuid) to service_role;
grant execute on function app.publish_notification_template(uuid, uuid, timestamptz, text) to service_role;
grant execute on function app.render_notification_template(uuid, text, jsonb) to authenticated, service_role;
grant execute on function app.set_notification_preference(uuid, uuid, text, text, boolean, uuid, text) to service_role;
grant execute on function app.get_notification_preferences(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.check_notification_trigger_authority(uuid, uuid) to service_role;
grant execute on function app.queue_notification(uuid, uuid, text, uuid, text, text, jsonb, text, uuid, text) to service_role;
grant execute on function app.record_notification_delivery_attempt(uuid, text, text, uuid, text) to service_role;
grant execute on function app.mark_notification_read(uuid, uuid, text) to authenticated, service_role;
grant execute on function app.list_notifications_for_recipient(uuid, uuid, uuid, boolean) to authenticated, service_role;
grant execute on function app.count_unread_notifications(uuid, uuid, uuid) to authenticated, service_role;
