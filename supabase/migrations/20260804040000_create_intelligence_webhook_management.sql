-- Intelligence, Automation and Enterprise Expansion: Webhook Management (IAE-012,
-- CG-S14-IAE-012, Prompt 340). Fourth prompt of Batch 3. Builds the real outbound
-- delivery worker `PLT-129` disclosed as not-yet-built ("The bounded delivery
-- adapter interface... never calls a live HTTP endpoint itself") -- on `app.jobs`,
-- per `ADR-0025` Part B, never a bespoke poller over `app.webhook_deliveries`
-- directly.
--
-- Design decisions, disclosed rather than left implicit:
--
-- 1. **The real delivery worker is built on `app.jobs`'s own existing `webhook_
--    retry` job type** (already present in `app.jobs_job_type_check`/`app.
--    generic_job_types()` since PLT-132, unused until now) -- confirmed live by
--    direct migration read before writing any code, per `ADR-0025` Part B's own
--    explicit instruction. `app.queue_webhook_delivery` (PLT-129) is extended
--    (`create or replace function`, same signature) to also `app.enqueue_job()`
--    one `webhook_retry` job per GENUINELY NEW delivery row (never for an
--    idempotent-replay hit, so a repeated `queue_webhook_delivery` call for the
--    same logical event never double-enqueues a job) -- idempotency-keyed on the
--    delivery's own id (`'webhook-delivery:'||id`), and carrying the delivery's
--    own `max_attempts` forward as the job's own `max_attempts` (design decision
--    2).
-- 2. **Two independent retry/backoff state machines are kept numerically
--    ALIGNED, not physically unified.** `app.jobs`'s own generic backoff
--    (`app.record_job_failure`, PLT-132, already live/tested/unmodified) becomes
--    the REAL scheduling driver a worker polls (`app.claim_next_job` checks
--    `app.jobs.next_attempt_at`, never `app.webhook_deliveries.next_attempt_at`).
--    `app.webhook_deliveries`'s own `attempts`/`next_attempt_at`/`status`
--    (updated by the EXISTING, unmodified `app.record_webhook_delivery_attempt`)
--    remain PLT-129's own original informational/delivery-log display state --
--    genuinely accurate evidence of what happened, but not what schedules the
--    next attempt. Alignment is maintained by explicitly propagating the
--    delivery's own `max_attempts` into every `enqueue_job()` call this
--    migration makes (design decisions 1, 5, 6) -- disclosed as "kept aligned by
--    construction," not physically merged into one counter.
-- 3. **The real, first-ever outbound HTTP client in this repository**
--    (`lib/webhooks/process-webhook-delivery-job.server.ts`, TypeScript, not
--    SQL) -- confirmed live by direct repository-wide grep before writing any
--    code: zero `fetch()`/`axios`/`http.request` call to an arbitrary external
--    URL exists anywhere in `app/`, `lib/`, `server/` today. Bounded 10-second
--    timeout via `AbortController`; HMAC-SHA256 signature/timestamp headers
--    (`ADR-0011`) computed via the EXISTING `app.compute_webhook_signature` RPC
--    -- the raw signing secret itself never leaves the database into
--    application memory at all, only the already-computed signature does.
-- 4. **A real, runnable worker script**
--    (`scripts/jobs/webhook-delivery-worker.ts`) polls `app.claim_next_job` for
--    `webhook_retry` and dispatches to the module above -- mirroring `scripts/
--    load-tests/job-poll-worker.sh`'s own disclosed "NOT a production
--    scheduler" shape, since NO live cron/daemon/scheduler exists anywhere in
--    this repository for ANY `app.jobs` job type (`ISS-2026-015`, a standing,
--    disclosed, accepted repository-wide risk this checkpoint does not newly
--    introduce and does not purport to close). What this checkpoint delivers is
--    the first REAL, correct, tested dispatch logic for a job type in this
--    repository -- ready to be wired to a real scheduler whenever that standing
--    gap is addressed, not a fabricated "it runs automatically" claim.
-- 5. **`app.send_test_webhook_delivery`**: staff-only
--    (`app.check_api_webhook_admin_authority`), creates a synthetic delivery
--    scoped to exactly ONE named endpoint (bypassing the subscription-fanout
--    loop `app.queue_webhook_delivery` itself uses -- a test send must never
--    fan out to every OTHER endpoint subscribed to the same test event type),
--    against a new `webhook.test` event type, then enqueues a real job via the
--    SAME `app.enqueue_job` path -- so "Test" in the console UI genuinely
--    exercises the real worker end to end, never a UI-only stub.
--    `max_attempts=1` (fail fast, no long backoff wait -- a test should give
--    quick feedback) and elevated `priority=10` (jumps the routine backlog).
-- 6. **`app.replay_webhook_delivery`**: staff-only, valid ONLY from
--    `status='dead_letter'` -- resets the delivery's own state (`status=
--    'pending'`, `attempts=0`, `next_attempt_at=now()`) and enqueues a FRESH
--    job with a new idempotency key (`'webhook-replay:'||id||':'||<epoch>`),
--    since the delivery's own original job already reached its own terminal
--    state and `app.jobs`'s own idempotency key is permanent, never reusable.
-- 7. **`app.list_webhook_deliveries_for_tenant`**: staff-only read, joined with
--    the endpoint's own `url` for display, optional status filter -- the
--    delivery-log/DLQ view's own data source. `security definer`, calls `app.
--    assert_actor_is_session_identity` first (ATW-032 discipline, applied
--    proactively from the first draft, matching `app.list_webhook_endpoints_
--    for_tenant`'s own already-hardened shape).
-- 8. **Seeds real, business-accurate event-type catalog rows** via direct
--    `insert` at migration-apply time (mirrors IAE-009's own `app.api_versions`
--    `v1` seeding precedent -- migration-apply-time execution runs as the
--    migration-owner role, a one-time bootstrap action, not a live RPC call
--    subject to `app.register_webhook_event_type`'s own Supreme-only
--    authority): `shipment.status_changed`, `ticket.created`, `invoice.issued`
--    (matching Prompt 340's own main-flow text verbatim), plus `webhook.test`
--    (design decision 5). **Wiring a LIVE trigger into an existing domain
--    mutation (e.g. a real shipment-status-transition function calling `app.
--    queue_webhook_delivery` itself) is disclosed, deferred future work** --
--    `app.queue_webhook_delivery` is already fully generic and callable today
--    by any authorized actor for any subscribed event type; this checkpoint
--    proves the full mechanism end to end via direct calls against a REAL
--    local HTTP test server in its own db-test, rather than fabricating a live
--    call site inside an already-shipped, already-tested domain mutation this
--    checkpoint would otherwise put at avoidable regression risk.
-- 9. **UI extends the existing `admin/api-keys` console** (IAE-009) -- endpoint
--    registration/list/rotate-secret/disable/reenable/test-send, and a
--    delivery-log/DLQ view with manual replay. Reuses `app.register_webhook_
--    endpoint`/`rotate_webhook_secret`/`disable_webhook_endpoint`/`reenable_
--    webhook_endpoint`/`list_webhook_endpoints_for_tenant` (PLT-129) unchanged.
-- 10. No job-type-registry widening needed -- `webhook_retry` already exists in
--    `app.jobs_job_type_check`/`app.generic_job_types()` (confirmed live,
--    unused until now); this migration touches neither.
-- 11. Per `ERR-2026-004`: this migration carries its own explicit
--    `revoke execute on all functions in schema app from public;` before its
--    final grants.

-- ===========================================================================
-- app.queue_webhook_delivery (PLT-129): extended, not forked (design
-- decisions 1, 2)
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
  v_existing app.webhook_deliveries;
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
    select * into v_existing
    from app.webhook_deliveries
    where tenant_id = p_tenant_id and webhook_endpoint_id = v_endpoint.id and idempotency_key = p_idempotency_key;

    if found then
      v_delivery := v_existing;
    else
      insert into app.webhook_deliveries (tenant_id, webhook_endpoint_id, event_type_code, payload, idempotency_key, next_attempt_at)
      values (p_tenant_id, v_endpoint.id, p_event_type_code, p_payload, p_idempotency_key, now())
      returning * into v_delivery;

      -- IAE-012 (design decisions 1, 2): the real app.jobs bridge -- one
      -- webhook_retry job per genuinely new delivery, idempotency-keyed on the
      -- delivery's own id, carrying the delivery's own max_attempts forward.
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
    end if;

    return next v_delivery;
  end loop;

  return;
end;
$$;

comment on function app.queue_webhook_delivery is
  'PLT-129, extended by IAE-012 (design decisions 1, 2): fans out to every active subscribed endpoint, idempotent per (tenant, endpoint, idempotency_key). Now also enqueues one real app.jobs webhook_retry job per genuinely new delivery -- the real scheduling bridge a delivery worker polls (app.claim_next_job), never re-derived from app.webhook_deliveries.next_attempt_at directly.';

-- ===========================================================================
-- app.get_webhook_delivery_dispatch_info (design decision 3) -- the minimal
-- read the delivery worker needs; never exposes the raw signing secret.
-- ===========================================================================

create function app.get_webhook_delivery_dispatch_info(p_delivery_id uuid)
returns table (
  delivery_id uuid, tenant_id uuid, status text, event_type_code text, payload jsonb,
  webhook_endpoint_id uuid, endpoint_url text, endpoint_status text
)
language sql
stable
as $$
  select d.id, d.tenant_id, d.status, d.event_type_code, d.payload, d.webhook_endpoint_id, e.url, e.status
  from app.webhook_deliveries d
  join app.webhook_endpoints e on e.id = d.webhook_endpoint_id
  where d.id = p_delivery_id;
$$;

comment on function app.get_webhook_delivery_dispatch_info is
  'IAE-012: the real delivery worker''s own minimal read -- deliberately never selects app.webhook_endpoints.secret_value; the worker calls app.compute_webhook_signature() instead, so the raw signing secret never leaves the database into application memory.';

-- ===========================================================================
-- app.send_test_webhook_delivery (design decision 5)
-- ===========================================================================

create function app.send_test_webhook_delivery(
  p_endpoint_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.webhook_deliveries
language plpgsql
as $$
declare
  v_endpoint app.webhook_endpoints;
  v_delivery app.webhook_deliveries;
  v_idempotency_key text;
begin
  select * into v_endpoint from app.webhook_endpoints where id = p_endpoint_id;
  if not found then
    raise exception 'webhook_endpoint_not_found: no endpoint %', p_endpoint_id using errcode = 'no_data_found';
  end if;

  if not app.check_api_webhook_admin_authority(v_endpoint.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks authority to manage webhook endpoints for tenant %', p_actor_auth_user_id, v_endpoint.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_idempotency_key := 'webhook-test:' || p_endpoint_id::text || ':' || extract(epoch from clock_timestamp())::text;

  insert into app.webhook_deliveries (tenant_id, webhook_endpoint_id, event_type_code, payload, idempotency_key, max_attempts, next_attempt_at)
  values (
    v_endpoint.tenant_id, p_endpoint_id, 'webhook.test',
    jsonb_build_object('message', 'This is a test delivery from CargoGrid.', 'endpoint_id', p_endpoint_id, 'sent_at', now()),
    v_idempotency_key, 1, now()
  )
  returning * into v_delivery;

  perform app.enqueue_job(
    v_endpoint.tenant_id, 'webhook_retry',
    jsonb_build_object('delivery_id', v_delivery.id),
    10, v_idempotency_key, 1,
    p_actor_auth_user_id, p_actor_label
  );

  perform app.capture_audit_event(
    v_endpoint.tenant_id, p_actor_auth_user_id, p_actor_label, 'send_test_webhook_delivery',
    'app.webhook_deliveries', v_delivery.id, 'success', null, null,
    jsonb_build_object('id', v_delivery.id, 'webhook_endpoint_id', p_endpoint_id)
  );

  return v_delivery;
end;
$$;

comment on function app.send_test_webhook_delivery is
  'IAE-012: staff-only, scoped to exactly ONE named endpoint (never the subscription-fanout app.queue_webhook_delivery itself uses) -- enqueues a real app.jobs job against the webhook.test event type so a console "Test" action genuinely exercises the real worker end to end. max_attempts=1 (fail fast), priority=10 (jumps the routine backlog).';

-- ===========================================================================
-- app.replay_webhook_delivery (design decision 6)
-- ===========================================================================

create function app.replay_webhook_delivery(
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
  select * into v_delivery from app.webhook_deliveries where id = p_delivery_id;
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

  update app.webhook_deliveries
  set status = 'pending', attempts = 0, next_attempt_at = now()
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
  'IAE-012: staff-only, valid ONLY from status=dead_letter -- resets the delivery''s own state and enqueues a FRESH app.jobs job with a new idempotency key, since the original job already reached its own terminal state and app.jobs'' own idempotency key is permanent.';

-- ===========================================================================
-- app.list_webhook_deliveries_for_tenant (design decision 7)
-- ===========================================================================

create function app.list_webhook_deliveries_for_tenant(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_status text,
  p_limit integer default 50
)
returns table (
  id uuid, webhook_endpoint_id uuid, endpoint_url text, event_type_code text,
  status text, attempts integer, max_attempts integer, next_attempt_at timestamptz,
  created_at timestamptz, updated_at timestamptz
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.check_api_webhook_admin_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks authority to view webhook deliveries for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_limit is null or p_limit <= 0 or p_limit > 200 then
    raise exception 'webhook_invalid_limit: limit must be between 1 and 200' using errcode = 'check_violation';
  end if;

  if p_status is not null and not (p_status = any (array['pending', 'delivered', 'dead_letter'])) then
    raise exception 'webhook_invalid_status_filter: % is not one of pending/delivered/dead_letter', p_status
      using errcode = 'check_violation';
  end if;

  return query
  select d.id, d.webhook_endpoint_id, e.url, d.event_type_code, d.status, d.attempts, d.max_attempts, d.next_attempt_at, d.created_at, d.updated_at
  from app.webhook_deliveries d
  join app.webhook_endpoints e on e.id = d.webhook_endpoint_id
  where d.tenant_id = p_tenant_id and (p_status is null or d.status = p_status)
  order by d.created_at desc
  limit p_limit;
end;
$$;

comment on function app.list_webhook_deliveries_for_tenant is
  'IAE-012: staff-only delivery-log/DLQ read, joined with the endpoint''s own url. security definer, calls app.assert_actor_is_session_identity first (ATW-032 discipline, applied proactively).';

-- ===========================================================================
-- Real event-type catalog seed (design decision 8) -- direct insert at
-- migration-apply time, mirroring app.api_versions' own v1 seeding precedent
-- (IAE-009).
-- ===========================================================================

insert into app.webhook_event_types (code, name, owner_primitive_code, registered_by) values
  ('shipment.status_changed', 'Shipment status changed', 'OPS', 'phase-09-foundation'),
  ('ticket.created', 'Support ticket created', 'TKT', 'phase-09-foundation'),
  ('invoice.issued', 'Invoice issued', 'FIN', 'phase-09-foundation'),
  ('webhook.test', 'Webhook test delivery', 'PLT', 'phase-09-foundation');

-- ===========================================================================
-- Grants
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant execute on function app.queue_webhook_delivery(uuid, text, jsonb, text, uuid, text) to service_role;
grant execute on function app.get_webhook_delivery_dispatch_info(uuid) to service_role;
grant execute on function app.send_test_webhook_delivery(uuid, uuid, text) to service_role;
grant execute on function app.replay_webhook_delivery(uuid, uuid, text) to service_role;
grant execute on function app.list_webhook_deliveries_for_tenant(uuid, uuid, text, integer) to authenticated, service_role;
