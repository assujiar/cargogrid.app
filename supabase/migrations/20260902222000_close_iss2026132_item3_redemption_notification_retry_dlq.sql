-- ISS-2026-132 item 3 (docs/runtime/KNOWN_ISSUES.md) -- "no notification/retry/DLQ
-- mechanism exists yet" for a loyalty redemption decision. Wires the real PLT-127
-- app.queue_notification primitive (the same one HRT-291's app._queue_ticket_escalation_
-- notification already uses, and the one this entry's own recommended fix names by
-- number) to every loyalty redemption state transition, with a genuine retry-count
-- column and a dead-letter status after repeated failures -- mirroring PLT-131/132's own
-- webhook_deliveries/app.jobs DLQ shape (attempts/max_attempts/status='dead_letter',
-- exponential backoff via power(2, attempts)) rather than inventing a new vocabulary.
--
-- DESIGN: an AFTER INSERT trigger on app.loyalty_redemption_events, not five separate
-- edits to app.submit_loyalty_redemption/app.decide_loyalty_redemption/app.cancel_
-- loyalty_redemption/app.mark_loyalty_redemption_fulfilled/app.mark_loyalty_redemption_
-- fulfillment_failed. Every one of those five already-hardened, security-sensitive RPCs
-- inserts into this ONE append-only table for every real state transition -- a trigger
-- fires uniformly across all five, with zero risk of re-deriving or drifting from any of
-- their own already-verified business logic, and zero need to touch any of them. The
-- trigger function catches every exception of its own internally (a bare `exception when
-- others then return new`) -- an uncaught error inside an AFTER trigger would otherwise
-- roll back the very event row it fired on, and everything else in that same statement,
-- which is exactly the failure mode this fix exists to prevent.
--
-- RECIPIENT RESOLUTION: app.loyalty_redemptions carries no customer auth identity today
-- (only a customer_account_id, which can have several customer_user members) -- a new,
-- nullable submitted_by_auth_user_id column captures the REAL submitting identity
-- (already available as app.submit_loyalty_redemption's own p_actor_auth_user_id, staff
-- or customer alike) going forward only. A redemption submitted before this migration has
-- no captured identity to notify -- a disclosed limitation, mirroring ISS-2026-130's own
-- "captured going forward only" precedent -- and the trigger silently skips it (no
-- delivery row, no error) rather than guessing a recipient.
--
-- RETRY/DLQ: app.loyalty_redemption_notification_deliveries is one MUTABLE row per
-- notified event (never append-only -- this is delivery-tracking machinery, the same
-- shape as app.jobs/app.webhook_deliveries, not a compliance ledger). attempts/
-- max_attempts/status('pending'/'sent'/'failed'/'dead_letter')/next_attempt_at mirror
-- app.jobs' own app.record_job_failure exactly (exponential backoff, dead_letter once
-- attempts >= max_attempts). Two staff RPCs -- retry (for 'failed') and requeue (for
-- 'dead_letter', resets attempts to 0 first) -- mirror app.record_job_failure/app.
-- requeue_dead_letter_job's own split exactly, adapted for a domain with no background
-- worker sweeping this queue: both are staff-triggered, the identical "on-demand/
-- staff-triggered only" precedent this whole Loyalty domain has consistently disclosed.

-- ===========================================================================
-- 1. app.loyalty_redemptions.submitted_by_auth_user_id -- additive, nullable.
-- ===========================================================================

alter table app.loyalty_redemptions add column submitted_by_auth_user_id uuid references auth.users (id);

comment on column app.loyalty_redemptions.submitted_by_auth_user_id is
  'ISS-2026-132 item 3: the real identity that called app.submit_loyalty_redemption (p_actor_auth_user_id, staff or customer alike) -- captured going forward only (nullable; a pre-migration redemption has none). The recipient app.loyalty_redemption_notification_deliveries notifies on every later decision/cancellation/fulfillment event for this redemption.';

-- Rebuilt via CREATE OR REPLACE FUNCTION -- prior body re-verified byte-for-byte against
-- the LIVE pg_get_functiondef output before editing (unchanged since 20260902074000,
-- ISS-2026-132 item 1's own close). Every line is untouched except the one new column
-- added to the INSERT's own column/value lists.
create or replace function app.submit_loyalty_redemption(
  p_tenant_id uuid,
  p_loyalty_account_id uuid,
  p_reward_id uuid,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_redemptions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_is_staff boolean;
  v_scope uuid[];
  v_existing app.loyalty_redemptions;
  v_account app.loyalty_accounts;
  v_reward app.loyalty_rewards;
  v_held boolean;
  v_current_tier_rank integer;
  v_min_tier_rank integer;
  v_current_points numeric;
  v_points_consumed numeric;
  v_redemption_id uuid;
  v_redemption app.loyalty_redemptions;
  v_principal app.loyalty_redemption_auto_approval_principals;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_is_staff := (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Edit')).allowed;
  v_scope := app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id);
  if not v_is_staff and array_length(v_scope, 1) is null then
    raise exception 'insufficient_authority: identity % holds neither LYL:Edit nor any customer_user account scope for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required' using errcode = 'check_violation';
  end if;

  select * into v_existing from app.loyalty_redemptions where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.loyalty_account_id <> p_loyalty_account_id or v_existing.reward_id <> p_reward_id then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different redemption request', p_idempotency_key using errcode = 'check_violation';
    end if;
    return v_existing;
  end if;

  select * into v_account from app.loyalty_accounts where id = p_loyalty_account_id and tenant_id = p_tenant_id;
  if not found or v_account.status <> 'active' or not (v_is_staff or v_account.customer_account_id = any (v_scope)) then
    raise exception 'loyalty_account_not_found: %', p_loyalty_account_id using errcode = 'no_data_found';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_loyalty_account_id::text, 6));

  select * into v_reward from app.loyalty_rewards where id = p_reward_id and tenant_id = p_tenant_id and program_id = v_account.program_id for update;
  if not found then
    raise exception 'loyalty_reward_not_found: %', p_reward_id using errcode = 'no_data_found';
  end if;
  if v_reward.status <> 'published' or v_reward.effective_from > clock_timestamp() or (v_reward.effective_to is not null and v_reward.effective_to <= clock_timestamp()) then
    raise exception 'reward_not_currently_redeemable: reward % is not currently available for redemption', p_reward_id using errcode = 'check_violation';
  end if;

  select coalesce(is_held, false) into v_held from app.loyalty_account_tier_holds where tenant_id = p_tenant_id and loyalty_account_id = p_loyalty_account_id;
  if coalesce(v_held, false) then
    raise exception 'account_on_hold: this account cannot redeem rewards at this time. Contact your account administrator or support for details.' using errcode = 'check_violation';
  end if;

  select td.tier_rank into v_current_tier_rank
  from app.loyalty_account_tier_movements tm
  join app.loyalty_tier_definitions td on td.id = tm.to_tier_id
  where tm.tenant_id = p_tenant_id and tm.loyalty_account_id = v_account.id
  order by tm.created_at desc, tm.id desc
  limit 1;

  if v_reward.min_tier_id is not null then
    select tier_rank into v_min_tier_rank from app.loyalty_tier_definitions where id = v_reward.min_tier_id;
    if v_current_tier_rank is null or v_current_tier_rank < v_min_tier_rank then
      raise exception 'ineligible_reward: this account does not currently meet the tier requirement for this reward' using errcode = 'check_violation';
    end if;
  end if;

  v_points_consumed := coalesce(v_reward.min_points_required, 0);
  if v_points_consumed > 0 then
    v_current_points := coalesce((select pb.available from app.loyalty_point_balances pb where pb.tenant_id = p_tenant_id and pb.loyalty_account_id = v_account.id), 0);
    if v_current_points < v_points_consumed then
      raise exception 'ineligible_reward: this account does not have enough points for this reward' using errcode = 'check_violation';
    end if;
  end if;

  v_redemption_id := gen_random_uuid();

  begin
    insert into app.loyalty_redemptions (
      id, tenant_id, loyalty_account_id, reward_id, reward_version_number, reward_name, reward_type,
      points_consumed, status, fulfillment_status, idempotency_key, created_by, submitted_by_auth_user_id
    ) values (
      v_redemption_id, p_tenant_id, p_loyalty_account_id, p_reward_id, v_reward.version_number, v_reward.reward_name, v_reward.reward_type,
      v_points_consumed, 'pending_approval', case when v_reward.reward_type = 'discount_voucher' then 'not_applicable' else 'pending' end,
      p_idempotency_key, p_actor_label, p_actor_auth_user_id
    )
    returning * into v_redemption;
  exception
    when unique_violation then
      select * into v_existing from app.loyalty_redemptions where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      if not found then
        raise;
      end if;
      return v_existing;
  end;

  insert into app.loyalty_redemption_events (tenant_id, redemption_id, event_type, reason, actor_auth_user_id, actor_label)
  values (p_tenant_id, v_redemption_id, 'submitted', null, p_actor_auth_user_id, p_actor_label);

  if v_reward.reward_type = 'discount_voucher' and (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Configure')).allowed then
    begin
      v_redemption := app._compose_loyalty_redemption_decision(p_tenant_id, v_redemption_id, p_actor_auth_user_id, p_actor_label, null);
    exception
      when others then
        null;
    end;
  elsif v_reward.reward_type = 'discount_voucher' and not v_is_staff and coalesce(v_reward.auto_approve_customer_redemption, false) then
    select * into v_principal from app.loyalty_redemption_auto_approval_principals where tenant_id = p_tenant_id;
    if found and (app.evaluate_permission(v_principal.auth_user_id, p_tenant_id, 'LYL', 'Edit')).allowed then
      begin
        v_redemption := app._compose_loyalty_redemption_decision(
          p_tenant_id, v_redemption_id, v_principal.auth_user_id,
          'system:' || v_principal.principal_label, 'auto-approved: reward configured for automatic customer redemption'
        );
      exception
        when others then
          null;
      end;
    end if;
  end if;

  return v_redemption;
end;
$$;

-- ===========================================================================
-- 2. app.loyalty_redemption_notification_deliveries -- retry/DLQ tracking, one
-- MUTABLE row per notified event (never append-only; delivery machinery, not a
-- compliance ledger).
-- ===========================================================================

create table app.loyalty_redemption_notification_deliveries (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  redemption_id uuid not null references app.loyalty_redemptions (id),
  redemption_event_id uuid not null references app.loyalty_redemption_events (id),
  event_type text not null,
  recipient_auth_user_id uuid not null references auth.users (id),
  notification_id uuid references app.notifications (id),
  status text not null default 'pending',
  attempts integer not null default 0,
  max_attempts integer not null default 5,
  last_error text,
  last_attempted_at timestamptz,
  next_attempt_at timestamptz,
  record_version integer not null default 1,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint lrnd_status_check check (status in ('pending', 'sent', 'failed', 'dead_letter')),
  constraint lrnd_attempts_check check (attempts >= 0 and attempts <= max_attempts),
  constraint lrnd_max_attempts_check check (max_attempts > 0),
  constraint lrnd_event_type_check check (event_type in ('approved', 'rejected', 'cancelled', 'fulfilled', 'fulfillment_failed')),
  constraint lrnd_redemption_event_unique unique (redemption_event_id)
);

comment on table app.loyalty_redemption_notification_deliveries is
  'ISS-2026-132 item 3: one row per app.loyalty_redemption_events row that warrants a customer notification (every event except ''submitted'' -- the submitting customer already knows). attempts/max_attempts/status/next_attempt_at mirror app.jobs/app.webhook_deliveries'' own DLQ shape exactly (PLT-131/132): status=dead_letter once attempts>=max_attempts. Populated by the app._notify_on_loyalty_redemption_event trigger, attempted via app._attempt_loyalty_redemption_notification_delivery (the single call site both the trigger and the staff retry/requeue RPCs below share), delivered through the real app.queue_notification (PLT-127) primitive -- never a fabricated notification.';

create index lrnd_tenant_status_idx on app.loyalty_redemption_notification_deliveries (tenant_id, status, created_at desc, id desc);
create index lrnd_tenant_created_id_idx on app.loyalty_redemption_notification_deliveries (tenant_id, created_at desc, id desc);
create index lrnd_redemption_idx on app.loyalty_redemption_notification_deliveries (redemption_id);

create function app.touch_loyalty_redemption_notification_delivery_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := clock_timestamp();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger loyalty_redemption_notification_deliveries_touch_row
  before update on app.loyalty_redemption_notification_deliveries
  for each row
  execute function app.touch_loyalty_redemption_notification_delivery_row();

-- ===========================================================================
-- 3. Notification type bootstrap -- direct INSERT, mirrors HRT-291's own
-- 'ticket_escalated' bootstrap exactly (20260731160000 section 0b): migration-
-- apply context has no live actor session, so app.register_notification_type/
-- app.create_config_draft/app.publish_config_version (all Supreme-Admin- or
-- scope-authority-gated) cannot be called here. channels=['in_app'] ONLY -- no
-- live email provider exists anywhere in this repository (PLT-127's own
-- disclosed boundary). Context carries only reward_name/event_type -- never a
-- staff-authored decision_reason free-text field, the same "minimized fields"
-- discipline HRT-291 already applied.
-- ===========================================================================

insert into app.notification_types (code, name, owner_primitive_code, registered_by)
values ('loyalty_redemption_decided', 'Loyalty Redemption Decided', 'LYL', 'system')
on conflict (code) do nothing;

insert into app.config_types (code, name, owner_primitive_code, registered_by)
values ('notification:loyalty_redemption_decided', 'Loyalty Redemption Decided Notification', 'LYL', 'system')
on conflict (code) do nothing;

do $$
declare
  v_object_id uuid;
  v_version_id uuid;
begin
  select id into v_object_id from app.config_objects
  where config_type_code = 'notification:loyalty_redemption_decided' and tenant_id is null and scope_level = 'global' and scope_id is null;

  if v_object_id is null then
    insert into app.config_objects (config_type_code, tenant_id, scope_level, scope_id, created_by)
    values ('notification:loyalty_redemption_decided', null, 'global', null, 'system')
    returning id into v_object_id;
  end if;

  select id into v_version_id from app.config_versions where config_object_id = v_object_id and status = 'published';

  if v_version_id is null then
    insert into app.config_versions (config_object_id, version_number, status, effective_from, created_by, published_by, published_at)
    values (v_object_id, 1, 'published', now(), 'system', 'system', now())
    returning id into v_version_id;

    insert into app.config_items (config_version_id, key, value) values
      (v_version_id, 'channels', '["in_app"]'::jsonb),
      (v_version_id, 'default_locale', '"en"'::jsonb),
      (v_version_id, 'templates', '{"en": {"subject": "Your redemption for {{reward_name}} was {{event_type}}", "body": "Your loyalty redemption for {{reward_name}} is now {{event_type}}. Open your CargoGrid account to review."}}'::jsonb);
  end if;

  raise notice 'loyalty_redemption_decided notification template ready: config_object=%, published_version=%', v_object_id, v_version_id;
end;
$$;

-- ===========================================================================
-- 4. app._attempt_loyalty_redemption_notification_delivery -- the ONE call
-- site both the trigger and the staff retry/requeue RPCs share. Never raises:
-- a queue_notification failure is caught internally and turned into a
-- recorded, retryable failure (or dead_letter), mirroring app.record_job_
-- failure's own backoff/dead_letter arithmetic (power(2, attempts) minutes).
-- ===========================================================================

create function app._attempt_loyalty_redemption_notification_delivery(
  p_delivery_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_redemption_notification_deliveries
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_delivery app.loyalty_redemption_notification_deliveries;
  v_redemption app.loyalty_redemptions;
  v_config_version_id uuid;
  v_notification app.notifications;
  v_error text;
  v_new_attempts integer;
  v_dead_letter boolean;
  v_updated app.loyalty_redemption_notification_deliveries;
begin
  select * into v_delivery from app.loyalty_redemption_notification_deliveries where id = p_delivery_id for update;
  if not found then
    raise exception 'loyalty_redemption_notification_delivery_not_found: %', p_delivery_id using errcode = 'no_data_found';
  end if;

  if v_delivery.status = 'sent' then
    return v_delivery;
  end if;

  if not app.has_active_tenant_membership(v_delivery.tenant_id, v_delivery.recipient_auth_user_id) then
    -- Recipient is no longer an active tenant member -- app.queue_notification's own
    -- authority gate would reject this outright. Recorded as a genuine, retryable
    -- failure (membership could be restored later), never silently dropped.
    v_error := 'notification_recipient_unauthorized: recipient is not an active tenant member';
  else
    select v.id into v_config_version_id
    from app.config_versions v
    join app.config_objects o on o.id = v.config_object_id
    where o.config_type_code = 'notification:loyalty_redemption_decided' and v.status = 'published'
    order by v.version_number desc
    limit 1;

    if v_config_version_id is null then
      v_error := 'no published loyalty_redemption_decided notification template is configured';
    else
      select * into v_redemption from app.loyalty_redemptions where id = v_delivery.redemption_id;

      begin
        v_notification := app.queue_notification(
          v_config_version_id, v_delivery.tenant_id, 'loyalty_redemption_decided', v_delivery.recipient_auth_user_id, 'in_app', 'en',
          jsonb_build_object('reward_name', v_redemption.reward_name, 'event_type', v_delivery.event_type),
          'loyalty-redemption-notify:' || v_delivery.redemption_event_id::text,
          p_actor_auth_user_id, p_actor_label
        );
      exception
        when others then
          v_error := sqlerrm;
      end;
    end if;
  end if;

  if v_error is null then
    update app.loyalty_redemption_notification_deliveries
      set status = 'sent', attempts = attempts + 1, notification_id = v_notification.id,
          last_error = null, last_attempted_at = clock_timestamp(), next_attempt_at = null
      where id = p_delivery_id
      returning * into v_updated;
  else
    v_new_attempts := v_delivery.attempts + 1;
    v_dead_letter := v_new_attempts >= v_delivery.max_attempts;
    update app.loyalty_redemption_notification_deliveries
      set status = case when v_dead_letter then 'dead_letter' else 'failed' end,
          attempts = v_new_attempts, last_error = v_error, last_attempted_at = clock_timestamp(),
          next_attempt_at = case when v_dead_letter then null else clock_timestamp() + (power(2, v_new_attempts)::text || ' minutes')::interval end
      where id = p_delivery_id
      returning * into v_updated;
  end if;

  return v_updated;
end;
$$;

comment on function app._attempt_loyalty_redemption_notification_delivery is
  'ISS-2026-132 item 3: internal (service_role-only), never raises. Locks the delivery row, attempts app.queue_notification, and unconditionally records the outcome -- sent, or failed/dead_letter with exponential backoff (power(2, attempts) minutes), mirroring app.record_job_failure''s own arithmetic. The one call site app._notify_on_loyalty_redemption_event (first attempt) and app.retry_loyalty_redemption_notification_delivery/app.requeue_loyalty_redemption_notification_delivery (staff-triggered re-attempts) all share.';

-- ===========================================================================
-- 5. app._notify_on_loyalty_redemption_event -- AFTER INSERT trigger on the
-- one table every redemption state transition already writes to.
-- ===========================================================================

create function app._notify_on_loyalty_redemption_event()
returns trigger
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_redemption app.loyalty_redemptions;
  v_delivery_id uuid;
begin
  if new.event_type = 'submitted' then
    -- The submitting customer already knows they just submitted; nothing to notify.
    return new;
  end if;

  select * into v_redemption from app.loyalty_redemptions where id = new.redemption_id;
  if not found or v_redemption.submitted_by_auth_user_id is null then
    -- Pre-migration redemption with no captured submitter identity to notify --
    -- disclosed limitation, mirrors ISS-2026-130's own "captured going forward
    -- only" precedent. Never a guessed recipient.
    return new;
  end if;

  insert into app.loyalty_redemption_notification_deliveries (
    tenant_id, redemption_id, redemption_event_id, event_type, recipient_auth_user_id, status
  ) values (
    new.tenant_id, new.redemption_id, new.id, new.event_type, v_redemption.submitted_by_auth_user_id, 'pending'
  )
  returning id into v_delivery_id;

  perform app._attempt_loyalty_redemption_notification_delivery(
    v_delivery_id, new.actor_auth_user_id, coalesce(new.actor_label, 'system')
  );

  return new;
exception
  when others then
    -- Never let a notification-layer failure roll back the event this trigger
    -- fires on, or anything else in the same transaction -- the identical
    -- isolation discipline app._queue_ticket_escalation_notification (HRT-291)
    -- already established for the same class of problem.
    return new;
end;
$$;

comment on function app._notify_on_loyalty_redemption_event is
  'ISS-2026-132 item 3: fires on every app.loyalty_redemption_events insert (all five write RPCs share this one table, so this fires uniformly across all of them with zero edits to any). Wrapped in its own top-level exception handler -- an uncaught error inside an AFTER trigger would otherwise roll back the very event row it fired on.';

create trigger loyalty_redemption_events_notify_after_insert
  after insert on app.loyalty_redemption_events
  for each row
  execute function app._notify_on_loyalty_redemption_event();

-- ===========================================================================
-- 6. Staff retry/requeue/list RPCs -- LYL:Edit (retry/requeue) / LYL:View
-- (list), mirroring app.record_job_failure/app.requeue_dead_letter_job's own
-- state-gated split exactly, adapted for a domain with no background worker:
-- both are staff-triggered, the established "on-demand/staff-triggered only"
-- precedent this Loyalty domain has consistently disclosed.
-- ===========================================================================

create function app.retry_loyalty_redemption_notification_delivery(
  p_tenant_id uuid,
  p_delivery_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_redemption_notification_deliveries
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_delivery app.loyalty_redemption_notification_deliveries;
  v_updated app.loyalty_redemption_notification_deliveries;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_delivery from app.loyalty_redemption_notification_deliveries where id = p_delivery_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'loyalty_redemption_notification_delivery_not_found: %', p_delivery_id using errcode = 'no_data_found';
  end if;
  if v_delivery.status <> 'failed' then
    raise exception 'loyalty_redemption_notification_not_retryable: delivery % is %, only a failed delivery may be retried', p_delivery_id, v_delivery.status
      using errcode = 'check_violation';
  end if;

  v_updated := app._attempt_loyalty_redemption_notification_delivery(p_delivery_id, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'retry_loyalty_redemption_notification_delivery',
    'app.loyalty_redemption_notification_deliveries', p_delivery_id, 'success', null,
    jsonb_build_object('status', v_delivery.status, 'attempts', v_delivery.attempts),
    jsonb_build_object('status', v_updated.status, 'attempts', v_updated.attempts)
  );

  return v_updated;
end;
$$;

create function app.requeue_loyalty_redemption_notification_delivery(
  p_tenant_id uuid,
  p_delivery_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_redemption_notification_deliveries
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_delivery app.loyalty_redemption_notification_deliveries;
  v_updated app.loyalty_redemption_notification_deliveries;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_delivery from app.loyalty_redemption_notification_deliveries where id = p_delivery_id and tenant_id = p_tenant_id for update;
  if not found then
    raise exception 'loyalty_redemption_notification_delivery_not_found: %', p_delivery_id using errcode = 'no_data_found';
  end if;
  if v_delivery.status <> 'dead_letter' then
    raise exception 'loyalty_redemption_notification_not_dead_letter: delivery % is %, only a dead_letter delivery may be requeued', p_delivery_id, v_delivery.status
      using errcode = 'check_violation';
  end if;

  update app.loyalty_redemption_notification_deliveries
    set status = 'pending', attempts = 0, last_error = null, next_attempt_at = null
    where id = p_delivery_id;

  v_updated := app._attempt_loyalty_redemption_notification_delivery(p_delivery_id, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'requeue_loyalty_redemption_notification_delivery',
    'app.loyalty_redemption_notification_deliveries', p_delivery_id, 'success', null,
    jsonb_build_object('status', 'dead_letter'), jsonb_build_object('status', v_updated.status)
  );

  return v_updated;
end;
$$;

create function app.list_loyalty_redemption_notification_deliveries(
  p_tenant_id uuid,
  p_status text,
  p_actor_auth_user_id uuid,
  p_before_created_at timestamptz default null,
  p_before_id uuid default null,
  p_limit integer default 50
)
returns setof app.loyalty_redemption_notification_deliveries
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_limit integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_status is not null and p_status not in ('pending', 'sent', 'failed', 'dead_letter') then
    raise exception 'invalid_status: % is not a recognized delivery status', p_status using errcode = 'check_violation';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select d.*
  from app.loyalty_redemption_notification_deliveries d
  where d.tenant_id = p_tenant_id
    and (p_status is null or d.status = p_status)
    and (p_before_created_at is null or (d.created_at, d.id) < (p_before_created_at, p_before_id))
  order by d.created_at desc, d.id desc
  limit v_limit;
end;
$$;

-- ===========================================================================
-- 7. Grants + public.* wrappers (RGL-394 Option 2).
-- ===========================================================================

grant select, insert, update on app.loyalty_redemption_notification_deliveries to service_role;
grant execute on function app.touch_loyalty_redemption_notification_delivery_row() to service_role;
grant execute on function app._attempt_loyalty_redemption_notification_delivery(uuid, uuid, text) to service_role;
grant execute on function app._notify_on_loyalty_redemption_event() to service_role;

revoke execute on all functions in schema app from public;

grant execute on function app.submit_loyalty_redemption(uuid, uuid, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.retry_loyalty_redemption_notification_delivery(uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.requeue_loyalty_redemption_notification_delivery(uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.list_loyalty_redemption_notification_deliveries(uuid, text, uuid, timestamptz, uuid, integer) to authenticated, service_role;

create function public.retry_loyalty_redemption_notification_delivery(p_tenant_id uuid, p_delivery_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns app.loyalty_redemption_notification_deliveries
language sql
security definer
set search_path = app, public, pg_temp
as $wrap$
  select app.retry_loyalty_redemption_notification_delivery(p_tenant_id, p_delivery_id, p_actor_auth_user_id, p_actor_label);
$wrap$;

comment on function public.retry_loyalty_redemption_notification_delivery(uuid, uuid, uuid, text) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.retry_loyalty_redemption_notification_delivery, never a reimplementation.';

revoke execute on function public.retry_loyalty_redemption_notification_delivery(uuid, uuid, uuid, text) from anon, authenticated, service_role, public;
grant execute on function public.retry_loyalty_redemption_notification_delivery(uuid, uuid, uuid, text) to authenticated, service_role;

create function public.requeue_loyalty_redemption_notification_delivery(p_tenant_id uuid, p_delivery_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns app.loyalty_redemption_notification_deliveries
language sql
security definer
set search_path = app, public, pg_temp
as $wrap$
  select app.requeue_loyalty_redemption_notification_delivery(p_tenant_id, p_delivery_id, p_actor_auth_user_id, p_actor_label);
$wrap$;

comment on function public.requeue_loyalty_redemption_notification_delivery(uuid, uuid, uuid, text) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.requeue_loyalty_redemption_notification_delivery, never a reimplementation.';

revoke execute on function public.requeue_loyalty_redemption_notification_delivery(uuid, uuid, uuid, text) from anon, authenticated, service_role, public;
grant execute on function public.requeue_loyalty_redemption_notification_delivery(uuid, uuid, uuid, text) to authenticated, service_role;

create function public.list_loyalty_redemption_notification_deliveries(
  p_tenant_id uuid, p_status text, p_actor_auth_user_id uuid, p_before_created_at timestamptz default null,
  p_before_id uuid default null, p_limit integer default 50
)
returns setof app.loyalty_redemption_notification_deliveries
language sql
security definer
set search_path = app, public, pg_temp
as $wrap$
  select * from app.list_loyalty_redemption_notification_deliveries(p_tenant_id, p_status, p_actor_auth_user_id, p_before_created_at, p_before_id, p_limit);
$wrap$;

comment on function public.list_loyalty_redemption_notification_deliveries(uuid, text, uuid, timestamptz, uuid, integer) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.list_loyalty_redemption_notification_deliveries, never a reimplementation.';

revoke execute on function public.list_loyalty_redemption_notification_deliveries(uuid, text, uuid, timestamptz, uuid, integer) from anon, authenticated, service_role, public;
grant execute on function public.list_loyalty_redemption_notification_deliveries(uuid, text, uuid, timestamptz, uuid, integer) to authenticated, service_role;

-- Post-migration sanity: exactly one overload of app.submit_loyalty_redemption
-- (guards against the C-29 added-parameter-overload class -- its signature did
-- not change here, but confirmed anyway since the function was touched).
do $$
declare
  v_count integer;
begin
  select count(*) into v_count from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'submit_loyalty_redemption';
  if v_count <> 1 then
    raise exception 'iss2026132_item3_overload_guard: expected exactly 1 overload of app.submit_loyalty_redemption, found %', v_count;
  end if;
end $$;
