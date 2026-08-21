-- Intelligence, Automation and Enterprise Expansion: Email, WhatsApp and SMS
-- Integrations (IAE-014, CG-S14-IAE-014, Prompt 342). First prompt of the
-- merged Batch 4 (`00_EXECUTION_INDEX.md` §5 revision, Prompts 342-348).
--
-- Design decisions, disclosed rather than left implicit:
--
-- 1. **Extends `app.notifications`/`app.notification_delivery_attempts`
--    (PLT-127), never a fourth delivery-attempt table shape.** PLT-127's own
--    migration header disclosed exactly this gap: "Any non-in_app channel
--    (currently just email) is real up through 'queued'... app.record_
--    notification_delivery_attempt() is the bounded adapter interface... a
--    future capability that owns a real provider integration calls it." This
--    checkpoint is that future capability. `whatsapp`/`sms` are additively
--    widened into the existing `channel`/`requested_channel`/
--    `effective_channel` CHECK constraints and `app.validate_notification_
--    template`'s own allowlist -- never a parallel channel enum.
-- 2. **`app.queue_notification` is extended (not forked) to bridge into the
--    real `app.jobs` queue** for any genuinely-new, non-skipped delivery --
--    the same `webhook_retry`-style bridge IAE-012 (Prompt 340) already
--    established for `app.webhook_deliveries`, reusing the ALREADY-
--    REGISTERED-but-dormant `notification_batch` job type (present in
--    `app.jobs_job_type_check`/`app.generic_job_types()` since PLT-132,
--    confirmed live by direct repository-wide grep before writing this
--    migration: zero real producer/consumer anywhere, only test/contract
--    fixture references) -- no job-type-registry widening needed.
-- 3. **Self-caught, proactively fixed: `app.queue_notification`'s own
--    pre-existing idempotency check was an unlocked select-then-insert** --
--    exactly the race class Batch 3's own Tier C review just found (and
--    fixed) in `app.queue_webhook_delivery`/`app.register_n8n_allowlisted_
--    action`. Applying that lesson proactively here, before it could ever be
--    independently rediscovered: rewritten as a single atomic `insert ... on
--    conflict (...) do nothing returning *`, enqueuing the real `app.jobs`
--    row ONLY when `FOUND` is true (the row this exact call actually
--    inserted) -- a losing concurrent caller now cleanly re-selects the
--    winner's row instead of erroring or double-enqueuing.
-- 4. **Provider credentials reuse `app.integration_connections`/`app.
--    integration_connection_credentials` (IAE-336) directly** -- never a
--    parallel credential table. Three adapters are seeded at migration-apply
--    time (mirroring `app.api_versions`/`app.webhook_event_types`/`app.n8n_
--    action_allowlist`'s own established seeding precedent): `email_smtp`,
--    `whatsapp_business`, `sms_gateway`, category `'communication'`.
-- 5. **A genuinely new primitive, disclosed as net-new**: `app.notification_
--    contact_addresses` -- WhatsApp/SMS delivery needs a phone number bound
--    to the recipient identity, and no such field exists anywhere in this
--    repository's identity model (`auth.users`/`app.users` carry no phone
--    column, confirmed by direct grep before writing this migration; email
--    already has a canonical, verified address at `auth.users.email`, so no
--    equivalent table is needed for that channel). Self-service by default,
--    mirroring `app.notification_preferences`'s own identical authority
--    shape (self, or the tenant's own support-grant authority) exactly.
-- 6. **Cost metering (`RPD-028`: "billed at actual provider cost +20% with
--    customer-visible metering") is genuinely new** -- confirmed by direct
--    grep that no `cost_meter`/`provider_cost`/`usage_meter` schema exists
--    anywhere in this repository before this migration. `app.record_
--    notification_delivery_attempt` is extended with trailing, DEFAULT-
--    valued parameters (`p_provider_unit_cost_amount`, `p_currency`) --
--    every existing call site remains valid unchanged. `app.compute_
--    provider_billed_amount` is the one pure function that ever computes the
--    +20% markup -- a future capability billing a DIFFERENT provider cost
--    (343-346) should call this same function, never re-derive the 20%
--    literal.
-- 7. **The real outbound worker is channel-branching, not channel-generic**,
--    per `RPD-038`/`ADR-0025` Part C's own "no generic provider abstraction,
--    case-by-case adapters" ruling -- `lib/notifications/process-
--    notification-delivery-job.server.ts` shares only the generic `app.jobs`
--    claim/dispatch/report plumbing IAE-012's own webhook worker already
--    established (itself just queue mechanics, not "the adapter"); the
--    actual request shape sent to each of the three providers is a distinct,
--    named function per channel (`dispatchEmail`/`dispatchWhatsApp`/
--    `dispatchSms`), each free to diverge in real payload shape.
-- 8. **The SSRF guard from Batch 3's own Tier C fix is reused proactively,
--    not rediscovered.** This worker is the SECOND real outbound HTTP client
--    in this repository (after IAE-012's webhook delivery worker) dispatching
--    to a tenant-configured URL (`app.integration_connections.config.
--    apiUrl`) -- `lib/webhooks/ssrf-guard.server.ts`'s own `checkWebhookDispatchUrlIsSafe`
--    is reused directly (it is already channel-agnostic: "is this URL safe
--    to POST to"), applying the exact lesson Batch 3's Tier C review had to
--    catch live for IAE-012, rather than waiting for a future review to
--    catch it here too.
-- 9. **`INTHUB:Configure`/`INTHUB:View` (already seeded by IAE-007) govern
--    connection setup** -- reused directly via IAE-336's own already-built
--    `app.create_integration_connection`/etc.; this migration needs no new
--    `app.entitlement_modules`/`app.permissions` row.
-- 10. Per `ERR-2026-004`: this migration carries its own explicit `revoke
--     execute on all functions in schema app from public` before its final
--     grants.

-- ===========================================================================
-- Finding-class 3 lesson applied proactively (design decision 3): app.
-- notifications/app.notification_preferences channel widening.
-- ===========================================================================

alter table app.notification_preferences drop constraint notification_preferences_channel_check;
alter table app.notification_preferences add constraint notification_preferences_channel_check
  check (channel in ('in_app', 'email', 'whatsapp', 'sms'));

alter table app.notifications drop constraint notifications_requested_channel_check;
alter table app.notifications add constraint notifications_requested_channel_check
  check (requested_channel in ('in_app', 'email', 'whatsapp', 'sms'));

alter table app.notifications drop constraint notifications_effective_channel_check;
alter table app.notifications add constraint notifications_effective_channel_check
  check (effective_channel in ('in_app', 'email', 'whatsapp', 'sms'));

create or replace function app.validate_notification_template(p_version_id uuid)
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
  v_allowed_channels text[] := array['in_app', 'email', 'whatsapp', 'sms'];
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
      raise exception 'notification_invalid_channel: channel % is not one of in_app/email/whatsapp/sms', v_channel
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
  'PLT-127, widened by IAE-014: channels allowlist now includes whatsapp/sms. Structural gate otherwise unchanged.';

-- ===========================================================================
-- app.notification_contact_addresses (design decision 5)
-- ===========================================================================

create table app.notification_contact_addresses (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  auth_user_id uuid not null references auth.users (id),
  channel text not null,
  address text not null,
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint notification_contact_addresses_channel_check check (channel in ('whatsapp', 'sms')),
  constraint notification_contact_addresses_address_check check (length(trim(address)) > 0),
  constraint notification_contact_addresses_unique unique (tenant_id, auth_user_id, channel)
);

comment on table app.notification_contact_addresses is
  'IAE-014: the phone number bound to a recipient identity for whatsapp/sms delivery -- email already has a canonical, verified address at auth.users.email, so no equivalent row exists for that channel. verified_at is a real column but no verification flow is built in this checkpoint (disclosed NOT_RUN, mirroring IAE-008''s own disclosed-but-unconsumed app.check_integration_connection_active precedent).';

create index notification_contact_addresses_recipient_idx on app.notification_contact_addresses (tenant_id, auth_user_id);

create function app.touch_notification_contact_addresses_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger notification_contact_addresses_touch_row
  before update on app.notification_contact_addresses
  for each row
  execute function app.touch_notification_contact_addresses_row();

-- Mirrors app.set_notification_preference's own identical authority shape
-- exactly (self, or the tenant's own support-grant authority).
create function app.set_notification_contact_address(
  p_tenant_id uuid,
  p_auth_user_id uuid,
  p_channel text,
  p_address text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.notification_contact_addresses
language plpgsql
as $$
declare
  v_existing app.notification_contact_addresses;
  v_row app.notification_contact_addresses;
begin
  if p_actor_auth_user_id <> p_auth_user_id and not app.is_support_grant_authority(p_actor_auth_user_id, p_tenant_id) then
    raise exception 'insufficient_authority: identity % may not set a contact address on behalf of %', p_actor_auth_user_id, p_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_channel not in ('whatsapp', 'sms') then
    raise exception 'notification_contact_invalid_channel: % is not one of whatsapp/sms', p_channel
      using errcode = 'check_violation';
  end if;
  if coalesce(length(trim(p_address)), 0) = 0 then
    raise exception 'notification_contact_missing_address: a non-empty address is required' using errcode = 'check_violation';
  end if;

  select * into v_existing from app.notification_contact_addresses where tenant_id = p_tenant_id and auth_user_id = p_auth_user_id and channel = p_channel;

  insert into app.notification_contact_addresses (tenant_id, auth_user_id, channel, address)
  values (p_tenant_id, p_auth_user_id, p_channel, p_address)
  on conflict (tenant_id, auth_user_id, channel)
  do update set address = excluded.address, verified_at = null
  returning * into v_row;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'set_notification_contact_address',
    'app.notification_contact_addresses', v_row.id, 'success', null,
    case when v_existing.id is null then null else jsonb_build_object('channel', v_existing.channel) end,
    jsonb_build_object('channel', v_row.channel)
  );

  return v_row;
end;
$$;

comment on function app.set_notification_contact_address is
  'IAE-014: self-service by default; a tenant''s own support-grant authority may set it on a user''s behalf. Re-setting the address clears verified_at (a changed number is unverified again) -- no verification flow exists yet (disclosed).';

-- ===========================================================================
-- app.queue_notification (PLT-127): extended, not forked (design decisions
-- 2, 3)
-- ===========================================================================

create or replace function app.queue_notification(
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

  -- Tier C Batch 3 lesson applied proactively (design decision 3): a single
  -- atomic INSERT ... ON CONFLICT DO NOTHING replaces the prior unlocked
  -- select-then-insert -- a losing concurrent caller sharing the same
  -- dedupe key now cleanly re-selects the winner's row instead of racing.
  if v_status = 'skipped' then
    insert into app.notifications (tenant_id, config_version_id, notification_type_code, recipient_auth_user_id, requested_channel, effective_channel, locale, subject, body, context, status, dedupe_key, triggered_by_auth_user_id, triggered_by)
    values (p_tenant_id, p_config_version_id, p_notification_type_code, p_recipient_auth_user_id, p_channel, v_effective_channel, coalesce(p_locale, 'en'), '', '', coalesce(p_context, '{}'::jsonb), v_status, p_dedupe_key, p_actor_auth_user_id, p_triggered_by)
    on conflict (tenant_id, notification_type_code, recipient_auth_user_id, requested_channel, dedupe_key) do nothing
    returning * into v_row;
  else
    select * into v_rendered from app.render_notification_template(p_config_version_id, p_locale, p_context);
    insert into app.notifications (tenant_id, config_version_id, notification_type_code, recipient_auth_user_id, requested_channel, effective_channel, locale, subject, body, context, status, dedupe_key, triggered_by_auth_user_id, triggered_by)
    values (p_tenant_id, p_config_version_id, p_notification_type_code, p_recipient_auth_user_id, p_channel, v_effective_channel, coalesce(p_locale, 'en'), v_rendered.subject, v_rendered.body, coalesce(p_context, '{}'::jsonb), v_status, p_dedupe_key, p_actor_auth_user_id, p_triggered_by)
    on conflict (tenant_id, notification_type_code, recipient_auth_user_id, requested_channel, dedupe_key) do nothing
    returning * into v_row;
  end if;

  if not found then
    select * into v_row from app.notifications
    where tenant_id = p_tenant_id and notification_type_code = p_notification_type_code
      and recipient_auth_user_id = p_recipient_auth_user_id and requested_channel = p_channel and dedupe_key = p_dedupe_key;
    return v_row;
  end if;

  -- Design decision 2: the real app.jobs bridge -- one notification_batch
  -- job per genuinely new, non-skipped, non-in_app delivery. in_app needs
  -- no worker (the row's own existence IS the delivery); skipped needs no
  -- worker either (nothing to attempt).
  if v_status = 'queued' then
    perform app.enqueue_job(
      p_tenant_id, 'notification_batch',
      jsonb_build_object('notification_id', v_row.id), 0,
      'notification-delivery:' || v_row.id::text, 5,
      p_actor_auth_user_id, p_triggered_by
    );
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_triggered_by, 'queue_notification',
    'app.notifications', v_row.id, 'success', null, null, to_jsonb(v_row)
  );

  return v_row;
end;
$$;

comment on function app.queue_notification is
  'PLT-127, extended by IAE-014 (design decisions 2, 3): now enqueues one real app.jobs notification_batch job per genuinely new, queued (non-in_app, non-skipped) notification -- the real scheduling bridge a delivery worker polls. Idempotency check rewritten as a single atomic INSERT ... ON CONFLICT DO NOTHING (Tier C Batch 3 lesson applied proactively), never a raw constraint violation to a losing concurrent caller.';

-- ===========================================================================
-- app.record_notification_delivery_attempt (PLT-127): extended with cost
-- metering (design decision 6)
-- ===========================================================================

create function app.compute_provider_billed_amount(p_provider_unit_cost_amount numeric, p_markup numeric default 0.20)
returns numeric
language sql
immutable
as $$
  select case when p_provider_unit_cost_amount is null then null else round(p_provider_unit_cost_amount * (1 + p_markup), 4) end;
$$;

comment on function app.compute_provider_billed_amount is
  'IAE-014 (RPD-028): the ONE place the "actual provider cost +20%" markup is ever computed -- any future capability billing a third-party provider cost (343-346) should call this, never re-derive the 20% literal.';

-- CREATE OR REPLACE cannot add new trailing parameters to an existing
-- function -- it creates a second overload instead of replacing it (the same
-- class of gotcha this session already discovered for RETURNS TABLE column
-- widening, IAE-011). Explicit DROP + CREATE, grants re-issued below.
drop function app.record_notification_delivery_attempt(uuid, text, text, uuid, text);

create function app.record_notification_delivery_attempt(
  p_notification_id uuid,
  p_status text,
  p_error_message text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_provider_unit_cost_amount numeric default null,
  p_currency text default null
)
returns app.notification_delivery_attempts
language plpgsql
as $$
declare
  v_notification app.notifications;
  v_next_attempt integer;
  v_attempt app.notification_delivery_attempts;
  v_billed_amount numeric;
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
  if p_provider_unit_cost_amount is not null and p_provider_unit_cost_amount < 0 then
    raise exception 'notification_invalid_cost_amount: provider_unit_cost_amount must not be negative' using errcode = 'check_violation';
  end if;

  select coalesce(max(attempt_number), 0) + 1 into v_next_attempt from app.notification_delivery_attempts where notification_id = p_notification_id;
  v_billed_amount := app.compute_provider_billed_amount(p_provider_unit_cost_amount);

  insert into app.notification_delivery_attempts (notification_id, attempt_number, status, error_message, provider_unit_cost_amount, currency, billed_amount)
  values (p_notification_id, v_next_attempt, p_status, p_error_message, p_provider_unit_cost_amount, p_currency, v_billed_amount)
  returning * into v_attempt;

  update app.notifications set status = case when p_status = 'success' then 'sent' else 'failed' end where id = p_notification_id;

  perform app.capture_audit_event(
    v_notification.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_notification_delivery_attempt',
    'app.notification_delivery_attempts', v_attempt.id, case when p_status = 'success' then 'success' else 'failure' end, p_error_message, null, to_jsonb(v_attempt)
  );

  return v_attempt;
end;
$$;

comment on function app.record_notification_delivery_attempt is
  'PLT-127, extended by IAE-014 (design decision 6): trailing DEFAULT-valued cost params -- every existing call site remains valid unchanged. billed_amount is computed server-side via app.compute_provider_billed_amount, never trusted from the caller directly.';

alter table app.notification_delivery_attempts add column provider_unit_cost_amount numeric;
alter table app.notification_delivery_attempts add column currency text;
alter table app.notification_delivery_attempts add column billed_amount numeric;
alter table app.notification_delivery_attempts add constraint notification_delivery_attempts_cost_check check (provider_unit_cost_amount is null or provider_unit_cost_amount >= 0);

comment on column app.notification_delivery_attempts.billed_amount is
  'IAE-014 (RPD-028): provider_unit_cost_amount * 1.20, computed by app.compute_provider_billed_amount -- null for in_app/free deliveries (nothing billable).';

-- ===========================================================================
-- app.get_notification_dispatch_info / app.get_notification_provider_credential
-- (the real delivery worker's own minimal reads -- design decisions 7, 8)
-- ===========================================================================

create function app.get_notification_dispatch_info(p_notification_id uuid)
returns table (
  notification_id uuid, tenant_id uuid, status text, effective_channel text,
  subject text, body text, recipient_email text, recipient_contact_address text,
  connection_id uuid, connection_status text, connection_config jsonb
)
language sql
stable
as $$
  select
    n.id, n.tenant_id, n.status, n.effective_channel, n.subject, n.body,
    u.email,
    ca.address,
    c.id, c.status, c.config
  from app.notifications n
  left join auth.users u on u.id = n.recipient_auth_user_id
  left join app.notification_contact_addresses ca
    on ca.tenant_id = n.tenant_id and ca.auth_user_id = n.recipient_auth_user_id and ca.channel = n.effective_channel
  left join lateral (
    select ic.id, ic.status, ic.config
    from app.integration_connections ic
    where ic.tenant_id = n.tenant_id
      and ic.adapter_code = case n.effective_channel
        when 'email' then 'email_smtp'
        when 'whatsapp' then 'whatsapp_business'
        when 'sms' then 'sms_gateway'
        else null
      end
    order by (ic.environment = 'production') desc, ic.created_at desc
    limit 1
  ) c on true
  where n.id = p_notification_id;
$$;

comment on function app.get_notification_dispatch_info is
  'IAE-014: the real delivery worker''s own minimal read -- deliberately never selects the raw provider credential (app.get_notification_provider_credential is the separate, dedicated read for that). Resolves the recipient''s own contact address (auth.users.email for email; app.notification_contact_addresses for whatsapp/sms) and the tenant''s own active connection for the effective channel''s adapter in one query.';

create function app.get_notification_provider_credential(p_connection_id uuid)
returns text
language sql
stable
as $$
  select credential_value from app.integration_connection_credentials where connection_id = p_connection_id;
$$;

comment on function app.get_notification_provider_credential is
  'IAE-014: service_role-only (the worker''s own real service-role identity already has direct SELECT on app.integration_connection_credentials -- IAE-008''s own zero-authenticated-grant isolation, no SECURITY DEFINER needed here since this function itself is never granted to authenticated).';

-- ===========================================================================
-- Real adapter seed (design decision 4) -- direct insert at migration-apply
-- time, mirroring app.api_versions'/app.webhook_event_types'/app.n8n_action_
-- allowlist's own established seeding precedent.
-- ===========================================================================

insert into app.integration_adapters (code, name, category, registered_by) values
  ('email_smtp', 'Email (transactional send API)', 'communication', 'phase-09-foundation'),
  ('whatsapp_business', 'WhatsApp Business Platform', 'communication', 'phase-09-foundation'),
  ('sms_gateway', 'SMS Gateway', 'communication', 'phase-09-foundation');

-- ===========================================================================
-- RLS
-- ===========================================================================

alter table app.notification_contact_addresses enable row level security;

create policy notification_contact_addresses_select_own on app.notification_contact_addresses
  for select to authenticated
  using (auth_user_id = auth.uid() or app.is_supreme_admin());

-- ===========================================================================
-- Grants
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant select on app.notification_contact_addresses to authenticated, service_role;
grant insert, update on app.notification_contact_addresses to service_role;
grant execute on function app.set_notification_contact_address(uuid, uuid, text, text, uuid, text) to service_role;
grant execute on function app.record_notification_delivery_attempt(uuid, text, text, uuid, text, numeric, text) to service_role;
grant execute on function app.compute_provider_billed_amount(numeric, numeric) to service_role;
grant execute on function app.get_notification_dispatch_info(uuid) to service_role;
grant execute on function app.get_notification_provider_credential(uuid) to service_role;
