-- Batch 3 Tier C review fix pass (Prompts 337-341, IAE-009 through IAE-013).
-- Four independent adversarial lenses (spec-compliance; security/RLS/tenant,
-- live-tested; correctness/concurrency, live-tested; cross-prompt
-- integration) found 2 Critical, 4 High, and several Medium/Low issues
-- against the freshly-COMPLETED batch. This migration fixes every Critical
-- and High finding plus the cheaply-fixable Medium/Low ones; the remaining
-- Low findings are disclosed, not fixed, in docs/build-log/phase-09/IAE-33{7..
-- 9}.md and IAE-34{0,1}.md's own updated residual-limitations sections.
--
-- 1. **[Critical] app.replay_webhook_delivery permanently broke the delivery
--    it replayed.** It reset `attempts=0`, but `app.webhook_delivery_
--    attempts` (PLT-129) is append-only and its own
--    `webhook_delivery_attempts_unique (webhook_delivery_id, attempt_number)`
--    constraint is never cleared -- the unmodified `app.record_webhook_
--    delivery_attempt` computes the next `attempt_number` as `v_delivery.
--    attempts + 1`, so resetting to 0 guarantees the next real attempt
--    collides with attempt_number=1, already recorded before the replay.
--    100% reproducible, no concurrency required; the worker has no recovery
--    from this and crash-loops on the reclaimed job. Fixed by NEVER
--    resetting `attempts` (preserving the append-only invariant `attempts ==
--    count(*) of webhook_delivery_attempts for this delivery`, which `record_
--    webhook_delivery_attempt` depends on) and instead giving the delivery a
--    fresh BUDGET of `max_attempts` (the delivery's own currently-configured
--    value) additional real attempts on top of whatever was already used --
--    `max_attempts := attempts + max_attempts`.
-- 2. **[Critical] app.replay_webhook_delivery had no row lock.** Two
--    concurrent replays of the same dead_letter delivery both passed the
--    `status = 'dead_letter'` check and both enqueued an independent job for
--    the SAME delivery -- live-proven to double-enqueue and, combined with
--    finding 1, to collide on the attempt-history constraint. Fixed by
--    `select ... for update` on the initial read: a second concurrent caller
--    now blocks until the first commits, then re-reads the ALREADY-UPDATED
--    row (status='pending', no longer 'dead_letter') and is cleanly rejected
--    by the existing `webhook_delivery_not_replayable` check -- the same
--    lock-then-recheck pattern already correct in this repository's own
--    `app.submit_rfq_response_via_vendor_api` (IAE-011).
-- 3. **[High] app.rotate_api_key had no row lock and no idempotency
--    signal**, so two concurrent (or client-retried) rotations of the same
--    active key each independently succeeded, minting TWO live successor
--    keys from one source key -- live-proven. Status alone cannot serve as
--    the guard because a normal overlap-window rotation (`p_overlap_minutes
--    > 0`) deliberately LEAVES the old key active for the overlap period.
--    Fixed by a new nullable `app.api_keys.superseded_by_key_id` column, set
--    exactly once under a `select ... for update` lock on the source key --
--    a second concurrent/retried rotation of the SAME already-rotated key now
--    raises `api_key_already_rotated` instead of minting a duplicate
--    successor. Rotating the NEW successor key later is unaffected (a
--    normal, expected iterative-rotation workflow).
-- 4. **[High] rotating an n8n connector's key via the reused generic
--    RotateApiKeyForm silently orphaned the connector's own governance
--    linkage.** app.rotate_api_key mints a brand-new app.api_keys row (unlike
--    revoke, which updates the SAME row in place); app.n8n_connectors.
--    api_key_id (unique, not null) was never updated to follow it, so a
--    rotated/immediately-revoked-by-overlap=0 connector could show
--    status=revoked in the console while an unlabeled, fully active successor
--    key with the connector's own scopes remained live and unreachable
--    through this console's own revoke path. Fixed by a new app.rotate_n8n_
--    connector, composing app.rotate_api_key and re-pointing app.n8n_
--    connectors.api_key_id at the new row -- the UI/action/mutation layer is
--    updated in this same fix pass to call it instead of the generic rotate
--    action for a connector.
-- 5. **[High, security] SSRF -- the real webhook delivery worker (IAE-012)
--    has no runtime protection against a hostname that only resolves to a
--    private/loopback/link-local/cloud-metadata address at actual dispatch
--    time (DNS rebinding).** `app.validate_webhook_url` (PLT-129) only
--    rejects a LITERAL private IP at registration time -- its own migration
--    header explicitly disclosed this as a gap for "the not-yet-built
--    delivery worker" to close; IAE-012 built that worker without closing it.
--    Fixed in TypeScript, not SQL: `lib/webhooks/ssrf-guard.server.ts` (new)
--    re-resolves the endpoint hostname immediately before every dispatch and
--    refuses to send if any resolved address is private/reserved; `lib/
--    webhooks/process-webhook-delivery-job.server.ts` is wired to call it and
--    to never auto-follow a redirect (`redirect: 'manual'`), closing the
--    matching redirect-based SSRF vector. No database change was needed for
--    this finding; it is recorded here only for a complete, one-place Tier C
--    disclosure.
-- 6. **[Medium] app.register_n8n_allowlisted_action was not idempotent under
--    real concurrency** despite its own doc comment's claim -- an unlocked
--    check-then-insert raised a raw `n8n_action_allowlist_pkey` constraint
--    violation instead of returning the existing row when two callers raced
--    the same scope. Fixed via a single atomic `insert ... on conflict
--    (scope) do update ... returning *` (a true upsert) -- `created_at` is
--    never touched by the update, so the identical-row idempotency guarantee
--    still holds; `description`/`registered_by` now refresh on a deliberate
--    re-registration (a reasonable, harmless behavior change: idempotent-by-
--    scope was always about never duplicating the row, not about freezing
--    its metadata).
-- 7. **[Medium] app.queue_webhook_delivery had the same unlocked
--    check-then-insert idempotency gap** on its own new delivery row --
--    live-proven to surface a raw `webhook_deliveries_idempotency_unique`
--    violation to one of two concurrent callers sharing an idempotency key,
--    instead of the documented idempotent no-op. Fixed via `insert ... on
--    conflict (tenant_id, webhook_endpoint_id, idempotency_key) do nothing
--    returning *`, enqueuing the real app.jobs job ONLY when FOUND is true
--    (i.e. only for the row this exact call actually inserted) -- a losing
--    concurrent caller now falls through to a plain re-select of the winner's
--    already-committed row instead of erroring or double-enqueuing.
-- 8. **[Low] app.create_n8n_connector allowed linking a disabled webhook
--    endpoint with no warning** -- a connector linked this way would simply
--    never receive deliveries (app.queue_webhook_delivery's own fan-out only
--    selects status='active' endpoints) until someone noticed. Fixed by
--    requiring the linked endpoint to be active at link time, raising
--    `webhook_endpoint_not_active` otherwise.
-- 9. **[Low, defense in depth] app.n8n_connectors/app.n8n_action_allowlist
--    shipped without RLS enabled**, relying only on the absence of any direct
--    table grant to `authenticated`/`anon` (live-confirmed non-exploitable
--    today -- both are RPC-only reads). Enabling RLS now, even with zero
--    policies, is a cheap, permanent backstop: `authenticated`/`anon` would
--    get zero rows via direct table access even if some FUTURE migration
--    ever granted one, without needing that future migration to remember to
--    add RLS itself. The table owner (the migration-owner role every
--    `service_role`-granted/`security definer` function in this batch runs
--    as, absent `FORCE ROW LEVEL SECURITY`) is unaffected.
-- 10. Per `ERR-2026-004`: this migration carries its own explicit
--     `revoke execute on all functions in schema app from public;` before its
--     final grants.

-- ===========================================================================
-- Finding 9: RLS defense in depth (no policies needed -- see design decision
-- 9 above; owner-executed SECURITY DEFINER/service_role functions unaffected)
-- ===========================================================================

alter table app.n8n_connectors enable row level security;
alter table app.n8n_action_allowlist enable row level security;

-- ===========================================================================
-- Finding 3: app.api_keys.superseded_by_key_id (additive, nullable)
-- ===========================================================================

alter table app.api_keys add column if not exists superseded_by_key_id uuid references app.api_keys (id);

comment on column app.api_keys.superseded_by_key_id is
  'Tier C Batch 3 fix: set exactly once, under a row lock, by app.rotate_api_key -- prevents a second concurrent/retried rotation of the SAME already-rotated key from minting a duplicate live successor. Never set by any other function.';

-- ===========================================================================
-- Finding 1, 2: app.replay_webhook_delivery
-- ===========================================================================

create or replace function app.replay_webhook_delivery(
  p_delivery_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.webhook_deliveries
language plpgsql
as $$
declare
  v_delivery app.webhook_deliveries;
  v_updated app.webhook_deliveries;
  v_idempotency_key text;
begin
  -- Tier C Batch 3 fix (finding 2): FOR UPDATE serializes concurrent
  -- replays of the SAME delivery -- a second caller blocks here, then (once
  -- the first commits) re-reads the ALREADY-UPDATED row and is cleanly
  -- rejected by the status check below instead of double-enqueuing.
  select * into v_delivery from app.webhook_deliveries where id = p_delivery_id for update;
  if not found then
    raise exception 'webhook_delivery_not_found: no delivery %', p_delivery_id using errcode = 'no_data_found';
  end if;

  if not app.check_api_webhook_admin_authority(v_delivery.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks authority to manage webhook endpoints for tenant %', p_actor_auth_user_id, v_delivery.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_delivery.status <> 'dead_letter' then
    raise exception 'webhook_delivery_not_replayable: delivery % is %, only a dead_letter delivery may be replayed', p_delivery_id, v_delivery.status
      using errcode = 'check_violation';
  end if;

  -- Tier C Batch 3 fix (finding 1): NEVER reset attempts -- app.webhook_
  -- delivery_attempts is append-only and app.record_webhook_delivery_attempt
  -- computes the next attempt_number as attempts+1, so resetting to 0 would
  -- collide with the already-recorded history. Instead grant a fresh BUDGET
  -- of max_attempts (the delivery's own currently-configured value) MORE
  -- real attempts on top of whatever was already used.
  update app.webhook_deliveries
  set status = 'pending', next_attempt_at = now(), max_attempts = attempts + max_attempts
  where id = p_delivery_id
  returning * into v_updated;

  v_idempotency_key := 'webhook-replay:' || p_delivery_id::text || ':' || extract(epoch from clock_timestamp())::text;

  perform app.enqueue_job(
    v_delivery.tenant_id, 'webhook_retry',
    jsonb_build_object('delivery_id', p_delivery_id),
    5, v_idempotency_key, v_updated.max_attempts,
    p_actor_auth_user_id, p_actor_label
  );

  perform app.capture_audit_event(
    v_delivery.tenant_id, p_actor_auth_user_id, p_actor_label, 'replay_webhook_delivery',
    'app.webhook_deliveries', p_delivery_id, 'success', null,
    jsonb_build_object('status', v_delivery.status), jsonb_build_object('status', v_updated.status)
  );

  return v_updated;
end;
$$;

comment on function app.replay_webhook_delivery is
  'IAE-012, Tier C Batch 3 fix: staff-only, valid ONLY from status=dead_letter -- row-locked (prevents a concurrent double-replay), grants a fresh budget of max_attempts MORE real attempts WITHOUT resetting the append-only attempts counter (would collide with app.webhook_delivery_attempts'' own unique constraint), and enqueues a FRESH app.jobs job with a new idempotency key.';

-- ===========================================================================
-- Finding 7: app.queue_webhook_delivery
-- ===========================================================================

create or replace function app.queue_webhook_delivery(
  p_tenant_id uuid,
  p_event_type_code text,
  p_payload jsonb,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_triggered_by text
)
returns setof app.webhook_deliveries
language plpgsql
as $$
declare
  v_endpoint record;
  v_delivery app.webhook_deliveries;
begin
  if not app.check_webhook_trigger_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'webhook_actor_unauthorized: identity % lacks active membership in tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.validate_config_value(p_payload) then
    raise exception 'webhook_unsafe_payload: payload failed structural validation'
      using errcode = 'check_violation';
  end if;

  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'webhook_missing_idempotency_key: idempotency_key is required'
      using errcode = 'check_violation';
  end if;

  for v_endpoint in
    select we.id from app.webhook_endpoints we
    join app.webhook_subscriptions ws on ws.webhook_endpoint_id = we.id
    where we.tenant_id = p_tenant_id and we.status = 'active' and ws.event_type_code = p_event_type_code
  loop
    -- Tier C Batch 3 fix (finding 7): a single atomic insert replaces the
    -- prior unlocked select-then-insert -- ON CONFLICT DO NOTHING means a
    -- losing concurrent caller sharing the same idempotency key never sees a
    -- raw constraint violation; FOUND is true ONLY for the row THIS call
    -- actually inserted, so the real app.jobs bridge below fires exactly
    -- once per genuinely new delivery, never twice for one logical event.
    insert into app.webhook_deliveries (tenant_id, webhook_endpoint_id, event_type_code, payload, idempotency_key, next_attempt_at)
    values (p_tenant_id, v_endpoint.id, p_event_type_code, p_payload, p_idempotency_key, now())
    on conflict (tenant_id, webhook_endpoint_id, idempotency_key) do nothing
    returning * into v_delivery;

    if found then
      -- IAE-012 (design decisions 1, 2): the real app.jobs bridge -- one
      -- webhook_retry job per genuinely new delivery, idempotency-keyed on
      -- the delivery's own id, carrying the delivery's own max_attempts
      -- forward.
      perform app.enqueue_job(
        p_tenant_id, 'webhook_retry',
        jsonb_build_object('delivery_id', v_delivery.id),
        0, 'webhook-delivery:' || v_delivery.id::text, v_delivery.max_attempts,
        p_actor_auth_user_id, p_triggered_by
      );

      perform app.capture_audit_event(
        p_tenant_id, p_actor_auth_user_id, p_triggered_by, 'queue_webhook_delivery',
        'app.webhook_deliveries', v_delivery.id, 'success', null, null,
        jsonb_build_object('id', v_delivery.id, 'webhook_endpoint_id', v_delivery.webhook_endpoint_id, 'event_type_code', v_delivery.event_type_code)
      );
    else
      select * into v_delivery
      from app.webhook_deliveries
      where tenant_id = p_tenant_id and webhook_endpoint_id = v_endpoint.id and idempotency_key = p_idempotency_key;
    end if;

    return next v_delivery;
  end loop;

  return;
end;
$$;

comment on function app.queue_webhook_delivery is
  'PLT-129, extended by IAE-012, Tier C Batch 3 fix: fans out to every active subscribed endpoint, idempotent per (tenant, endpoint, idempotency_key) via a single atomic INSERT ... ON CONFLICT DO NOTHING (never a raw constraint violation to a losing concurrent caller). Enqueues one real app.jobs webhook_retry job per genuinely new delivery -- the real scheduling bridge a delivery worker polls.';

-- ===========================================================================
-- Finding 3: app.rotate_api_key
-- ===========================================================================

create or replace function app.rotate_api_key(
  p_key_id uuid,
  p_overlap_minutes integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns table (
  id uuid, tenant_id uuid, name text, key_prefix text, scopes jsonb, status text,
  rate_limit_per_minute integer, expires_at timestamptz, created_at timestamptz, raw_key text
)
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_old app.api_keys;
  v_new_raw_key text;
  v_new_key_prefix text;
  v_new_key_hash text;
  v_new_key app.api_keys;
  v_new_expiry timestamptz;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- Tier C Batch 3 fix (finding 3): FOR UPDATE serializes concurrent/
  -- retried rotations of the SAME source key.
  select * into v_old from app.api_keys where app.api_keys.id = p_key_id for update;
  if not found then
    raise exception 'api_key_not_found: no key %', p_key_id using errcode = 'no_data_found';
  end if;

  if not app.check_api_key_manage_authority(v_old.tenant_id, v_old.customer_account_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks authority to manage API keys for tenant %', p_actor_auth_user_id, v_old.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_old.status <> 'active' then
    raise exception 'api_key_not_active: key % is %, only an active key may be rotated', p_key_id, v_old.status
      using errcode = 'check_violation';
  end if;

  -- Tier C Batch 3 fix (finding 3): status alone cannot guard against a
  -- second rotation, since a normal overlap-window rotation deliberately
  -- leaves the old key status='active'. superseded_by_key_id is the real
  -- guard, checked and set under the SAME row lock acquired above.
  if v_old.superseded_by_key_id is not null then
    raise exception 'api_key_already_rotated: key % was already rotated to %, rotate the successor key instead', p_key_id, v_old.superseded_by_key_id
      using errcode = 'check_violation';
  end if;

  if p_overlap_minutes is null or p_overlap_minutes < 0 or p_overlap_minutes > 10080 then
    raise exception 'api_key_invalid_overlap_minutes: % must be between 0 and 10080 (7 days)', p_overlap_minutes
      using errcode = 'check_violation';
  end if;

  v_new_raw_key := 'cgk_' || encode(gen_random_bytes(24), 'hex');
  v_new_key_prefix := substring(v_new_raw_key from 1 for 12);
  v_new_key_hash := encode(digest(v_new_raw_key, 'sha256'), 'hex');

  insert into app.api_keys (tenant_id, name, key_prefix, key_hash, scopes, rate_limit_per_minute, expires_at, created_by_auth_user_id, customer_account_id, customer_actor_auth_user_id, vendor_master_record_id)
  values (v_old.tenant_id, v_old.name, v_new_key_prefix, v_new_key_hash, v_old.scopes, v_old.rate_limit_per_minute, v_old.expires_at, p_actor_auth_user_id, v_old.customer_account_id, v_old.customer_actor_auth_user_id, v_old.vendor_master_record_id)
  returning * into v_new_key;

  v_new_expiry := now() + (p_overlap_minutes::text || ' minutes')::interval;

  update app.api_keys
  set status = case when p_overlap_minutes = 0 then 'revoked' else v_old.status end,
      revoked_at = case when p_overlap_minutes = 0 then now() else revoked_at end,
      revoked_reason = case when p_overlap_minutes = 0 then 'rotated' else revoked_reason end,
      expires_at = case when v_old.expires_at is not null and v_old.expires_at < v_new_expiry then v_old.expires_at else v_new_expiry end,
      superseded_by_key_id = v_new_key.id
  where app.api_keys.id = v_old.id;

  perform app.capture_audit_event(
    v_old.tenant_id, p_actor_auth_user_id, p_actor_label, 'rotate_api_key',
    'app.api_keys', v_new_key.id, 'success', null,
    jsonb_build_object('id', v_old.id, 'key_prefix', v_old.key_prefix),
    jsonb_build_object('id', v_new_key.id, 'key_prefix', v_new_key.key_prefix, 'overlap_minutes', p_overlap_minutes)
  );

  return query select v_new_key.id, v_new_key.tenant_id, v_new_key.name, v_new_key.key_prefix, v_new_key.scopes, v_new_key.status, v_new_key.rate_limit_per_minute, v_new_key.expires_at, v_new_key.created_at, v_new_raw_key;
end;
$$;

comment on function app.rotate_api_key is
  'PLT-129, extended by IAE-010, IAE-011, Tier C Batch 3 fix: overlap-window rotation (0 = immediate revoke), row-locked and superseded_by_key_id-guarded against a second concurrent/retried rotation of the same source key (status alone cannot guard this, since an overlap-window rotation deliberately leaves the old key active). The rotated key carries customer/vendor scoping columns forward. Also calls app.assert_actor_is_session_identity first.';

-- ===========================================================================
-- Finding 8: app.create_n8n_connector -- require an active linked endpoint
-- ===========================================================================

create or replace function app.create_n8n_connector(
  p_tenant_id uuid,
  p_name text,
  p_scopes jsonb,
  p_webhook_endpoint_id uuid,
  p_rate_limit_per_minute integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns table (
  connector_id uuid, api_key_id uuid, tenant_id uuid, name text, key_prefix text,
  scopes jsonb, status text, rate_limit_per_minute integer, webhook_endpoint_id uuid,
  created_at timestamptz, raw_key text
)
language plpgsql
as $$
declare
  v_scope text;
  v_key record;
  v_connector app.n8n_connectors;
  v_endpoint app.webhook_endpoints;
begin
  if not app.check_api_webhook_admin_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks authority to create an n8n connector for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'n8n_connector_missing_name: p_name must not be empty' using errcode = 'check_violation';
  end if;

  if p_scopes is null or jsonb_typeof(p_scopes) <> 'array' or jsonb_array_length(p_scopes) = 0 then
    raise exception 'api_key_missing_scopes: at least one scope is required' using errcode = 'check_violation';
  end if;
  for v_scope in select * from jsonb_array_elements_text(p_scopes) loop
    if not exists (select 1 from app.n8n_action_allowlist where scope = v_scope) then
      raise exception 'n8n_scope_not_allowlisted: % is not on the n8n safe-action allowlist', v_scope
        using errcode = 'check_violation';
    end if;
  end loop;

  if p_webhook_endpoint_id is not null then
    select * into v_endpoint from app.webhook_endpoints where app.webhook_endpoints.id = p_webhook_endpoint_id and app.webhook_endpoints.tenant_id = p_tenant_id;
    if not found then
      raise exception 'webhook_endpoint_not_found: no endpoint % in tenant %', p_webhook_endpoint_id, p_tenant_id
        using errcode = 'no_data_found';
    end if;
    -- Tier C Batch 3 fix (finding 8): a connector linked to a disabled
    -- endpoint would simply never receive deliveries (app.queue_webhook_
    -- delivery's own fan-out only selects status='active' endpoints) until
    -- someone noticed -- reject it structurally instead.
    if v_endpoint.status <> 'active' then
      raise exception 'webhook_endpoint_not_active: endpoint % is %, link an active endpoint', p_webhook_endpoint_id, v_endpoint.status
        using errcode = 'check_violation';
    end if;
  end if;

  -- Extends, never forks, app.create_api_key (PLT-129) -- it independently
  -- re-validates every scope against the CREATING ACTOR's own current RBAC
  -- (app.evaluate_permission), a second, real check the allowlist above does
  -- not substitute for.
  select * into v_key from app.create_api_key(p_tenant_id, p_name, p_scopes, null, p_rate_limit_per_minute, p_actor_auth_user_id, p_actor_label);

  insert into app.n8n_connectors (tenant_id, api_key_id, webhook_endpoint_id, name, created_by_auth_user_id)
  values (p_tenant_id, v_key.id, p_webhook_endpoint_id, p_name, p_actor_auth_user_id)
  returning * into v_connector;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_n8n_connector',
    'app.n8n_connectors', v_connector.id, 'success', null, null,
    jsonb_build_object('id', v_connector.id, 'api_key_id', v_key.id, 'webhook_endpoint_id', p_webhook_endpoint_id)
  );

  return query select v_connector.id, v_key.id, v_key.tenant_id, v_connector.name, v_key.key_prefix, v_key.scopes, v_key.status, v_key.rate_limit_per_minute, v_connector.webhook_endpoint_id, v_connector.created_at, v_key.raw_key;
end;
$$;

comment on function app.create_n8n_connector is
  'IAE-013, Tier C Batch 3 fix: staff-only. Every requested scope must pass BOTH app.n8n_action_allowlist AND app.create_api_key''s own creating-actor RBAC re-check. An optional linked webhook endpoint must belong to the same tenant AND be active. Returns the raw key exactly once.';

-- ===========================================================================
-- Finding 4: app.rotate_n8n_connector (new)
-- ===========================================================================

create function app.rotate_n8n_connector(
  p_connector_id uuid,
  p_overlap_minutes integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns table (
  connector_id uuid, api_key_id uuid, tenant_id uuid, name text, key_prefix text,
  scopes jsonb, status text, rate_limit_per_minute integer, webhook_endpoint_id uuid,
  created_at timestamptz, raw_key text
)
language plpgsql
as $$
declare
  v_connector app.n8n_connectors;
  v_rotated record;
begin
  select * into v_connector from app.n8n_connectors where id = p_connector_id;
  if not found then
    raise exception 'n8n_connector_not_found: no connector %', p_connector_id using errcode = 'no_data_found';
  end if;

  -- Delegates to app.rotate_api_key for the underlying credential AND its
  -- own authority check -- this function's only own responsibility is
  -- keeping app.n8n_connectors.api_key_id pointed at whichever app.api_keys
  -- row is genuinely live. Unlike revoke (which updates the SAME row in
  -- place, so the connector's own fixed FK never goes stale), rotate mints a
  -- brand-new row -- without this re-pointing step the connector's own
  -- governance record would silently keep referencing a superseded/
  -- immediately-revoked (overlap=0) key while an orphaned, unlabeled
  -- successor stayed live (Tier C Batch 3 finding 4).
  select * into v_rotated from app.rotate_api_key(v_connector.api_key_id, p_overlap_minutes, p_actor_auth_user_id, p_actor_label);

  update app.n8n_connectors set api_key_id = v_rotated.id where id = p_connector_id;

  return query select v_connector.id, v_rotated.id, v_rotated.tenant_id, v_connector.name, v_rotated.key_prefix, v_rotated.scopes, v_rotated.status, v_rotated.rate_limit_per_minute, v_connector.webhook_endpoint_id, v_rotated.created_at, v_rotated.raw_key;
end;
$$;

comment on function app.rotate_n8n_connector is
  'IAE-013, Tier C Batch 3 fix (finding 4): composes app.rotate_api_key and re-points app.n8n_connectors.api_key_id at the newly-minted key row -- the console must call this, never the generic rotate action, for a connector''s own key.';

-- ===========================================================================
-- Finding 6: app.register_n8n_allowlisted_action -- atomic upsert
-- ===========================================================================

create or replace function app.register_n8n_allowlisted_action(
  p_scope text,
  p_description text,
  p_actor_auth_user_id uuid,
  p_registered_by text
)
returns app.n8n_action_allowlist
language plpgsql
as $$
declare
  v_row app.n8n_action_allowlist;
begin
  if not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: only Supreme Admin may register an n8n allowlisted action'
      using errcode = 'insufficient_privilege';
  end if;

  if not exists (select 1 from app.permissions where code = p_scope) then
    raise exception 'n8n_scope_not_a_real_permission: % is not a registered app.permissions code', p_scope
      using errcode = 'check_violation';
  end if;

  -- Tier C Batch 3 fix (finding 6): a single atomic upsert replaces the
  -- prior unlocked select-then-insert, which raised a raw n8n_action_
  -- allowlist_pkey violation instead of the documented idempotent return
  -- when two callers raced the same scope. created_at is never touched by
  -- the update, so the "repeated registration returns the SAME row"
  -- guarantee still holds even though description/registered_by now refresh.
  insert into app.n8n_action_allowlist (scope, description, registered_by)
  values (p_scope, p_description, p_registered_by)
  on conflict (scope) do update set description = excluded.description, registered_by = excluded.registered_by
  returning * into v_row;

  perform app.capture_audit_event(
    null, p_actor_auth_user_id, p_registered_by, 'register_n8n_allowlisted_action',
    'app.n8n_action_allowlist', null, 'success', null, null, to_jsonb(v_row)
  );

  return v_row;
end;
$$;

comment on function app.register_n8n_allowlisted_action is
  'IAE-013, Tier C Batch 3 fix: Supreme-only, atomically idempotent by scope (INSERT ... ON CONFLICT DO UPDATE, never a raw constraint violation under real concurrency). Rejects a scope that is not a real, already-registered app.permissions code.';

-- ===========================================================================
-- Grants (Finding 4's new function; every other function above is create or
-- replace and keeps its existing grant, which survives a plain CREATE OR
-- REPLACE unlike a DROP+CREATE)
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant execute on function app.rotate_n8n_connector(uuid, integer, uuid, text) to service_role;
