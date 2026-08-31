-- Real, executable test evidence for IAE-012 (Webhook Management, Prompt 340) --
-- run via `pnpm run db:test` against a real, disposable Postgres database. Scoped
-- to this checkpoint's own additive migration (supabase/migrations/
-- 20260804040000_create_intelligence_webhook_management.sql). Fresh, distinctive
-- tenant fixture (iaewebhook/iaewebhook2), fixture id range
-- 00000000-0000-0000-0000-000014xxxxxx.
--
-- Does NOT re-test app.register_webhook_endpoint/rotate_webhook_secret/
-- disable_webhook_endpoint/reenable_webhook_endpoint's own already-covered
-- authority/behavior (scripts/db-tests/api-key-webhook.sql) -- only that this
-- checkpoint's own new functions correctly compose them. Does NOT exercise the
-- real outbound HTTP client itself (lib/webhooks/process-webhook-delivery-job.
-- server.ts's own live-HTTP-server proof lives in its own .test.ts, matching
-- this repository's established two-layer split: SQL functions proven here via
-- direct RPC calls; TypeScript business logic proven in its own .test.ts). What
-- THIS file proves is the real app.jobs <-> app.webhook_deliveries bridge this
-- checkpoint's own migration builds -- simulating exactly what a real worker
-- would do (claim_next_job / record_webhook_delivery_attempt / complete_job /
-- record_job_failure) via direct SQL calls, the same "prove the mechanism
-- without a live process fleet" convention every prior job-queue capability in
-- this session already established.

\set ON_ERROR_STOP on

-- ISS-2026-257: fixed test-only key for app.integration_secrets_encryption_key() --
-- production key provisioning/rotation/custody is a disclosed, out-of-scope
-- infrastructure concern (mirrors app.vendor_financial_encryption_keys own pattern).
select set_config('app.integration_secrets_encryption_key', 'test-only-key-not-for-production', false);

\echo '>> setup: tenant iaewebhook (tenant_admin with staff authority, a plain PRC:View-only staff member with no admin authority) and a second tenant iaewebhook2 (its own tenant_admin, for cross-tenant isolation). Two endpoints in tenant1, both subscribed to webhook.test and shipment.status_changed.'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_admin1 uuid := '00000000-0000-0000-0000-000014000001';
  v_staff1 uuid := '00000000-0000-0000-0000-000014000002';
  v_admin2 uuid := '00000000-0000-0000-0000-000014000003';
  v_staff_role uuid;
  v_endpoint_a record;
  v_endpoint_b record;
begin
  insert into auth.users (id, email) values
    (v_admin1, 'admin@iaewebhook.test'),
    (v_staff1, 'staff@iaewebhook.test'),
    (v_admin2, 'admin@iaewebhook2.test');

  perform app.provision_tenant('iaewebhook', 'IaeWebhook Co', 'idem-iaewebhook', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'iaewebhook');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.provision_tenant('iaewebhook2', 'IaeWebhook Co 2', 'idem-iaewebhook2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'iaewebhook2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, v_admin1, 'admin@iaewebhook.test', 'IaeWebhook Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iaewebhook.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin1, 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, v_staff1, 'staff@iaewebhook.test', 'IaeWebhook Staff', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@iaewebhook.test'), 'active', 'onboarded', 'tester');
  v_staff_role := (app.create_role(v_tenant1, 'IaeWebhook Viewer', 'PRC:View only, no admin authority', 'tester')).id;
  perform app.set_role_version_permissions((app.create_role_version(v_staff_role, 'tester')).id, array(select id from app.permissions where resource_module_code = 'PRC' and action = 'View'), 'tester');
  perform app.publish_role_version((select id from app.role_versions where role_id = v_staff_role and status = 'draft'), now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_staff_role and status = 'published'), v_staff1, v_admin1, 'admin');

  perform app.invite_user(v_tenant2, v_admin2, 'admin@iaewebhook2.test', 'IaeWebhook2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iaewebhook2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin2, 'tenant_admin', v_tenant2, null, 'tester');

  select * into v_endpoint_a from app.register_webhook_endpoint(v_tenant1, 'https://a.iaewebhook.test/hook', '["webhook.test", "shipment.status_changed"]'::jsonb, v_admin1, 'admin');
  select * into v_endpoint_b from app.register_webhook_endpoint(v_tenant1, 'https://b.iaewebhook.test/hook', '["webhook.test"]'::jsonb, v_admin1, 'admin');
end $$;

\echo '>> app.queue_webhook_delivery (extended): a genuinely new delivery also enqueues a real app.jobs webhook_retry job, idempotency-keyed on the delivery id, carrying the delivery''s own max_attempts forward; a repeated (idempotent-replay) call never double-enqueues a job'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaewebhook');
  v_admin1 uuid := '00000000-0000-0000-0000-000014000001';
  v_deliveries app.webhook_deliveries[];
  v_delivery app.webhook_deliveries;
  v_job app.jobs;
  v_job_count integer;
begin
  select array_agg(d) into v_deliveries from app.queue_webhook_delivery(v_tenant1, 'shipment.status_changed', '{"shipment_id": "test-1"}'::jsonb, 'idem-iwh-event-1', v_admin1, 'admin') d;
  if array_length(v_deliveries, 1) <> 1 then
    raise exception 'assertion failed: expected exactly 1 delivery (only endpoint A is subscribed to shipment.status_changed), got %', array_length(v_deliveries, 1);
  end if;
  v_delivery := v_deliveries[1];

  select * into v_job from app.jobs where tenant_id = v_tenant1 and job_type = 'webhook_retry' and payload->>'delivery_id' = v_delivery.id::text;
  if not found then
    raise exception 'assertion failed: expected a real app.jobs webhook_retry job to have been enqueued for delivery %', v_delivery.id;
  end if;
  if v_job.max_attempts <> v_delivery.max_attempts or v_job.idempotency_key <> 'webhook-delivery:' || v_delivery.id::text or v_job.status <> 'pending' then
    raise exception 'assertion failed: unexpected job shape for delivery %: %', v_delivery.id, to_jsonb(v_job);
  end if;

  -- Idempotent replay: same event, same idempotency key -- returns the SAME
  -- delivery, never a second job.
  perform app.queue_webhook_delivery(v_tenant1, 'shipment.status_changed', '{"shipment_id": "test-1"}'::jsonb, 'idem-iwh-event-1', v_admin1, 'admin');
  select count(*) into v_job_count from app.jobs where tenant_id = v_tenant1 and job_type = 'webhook_retry' and payload->>'delivery_id' = v_delivery.id::text;
  if v_job_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 job for delivery % even after an idempotent replay, got %', v_delivery.id, v_job_count;
  end if;

  raise notice 'PASS: queue_webhook_delivery enqueues a real app.jobs job per genuinely new delivery, aligned max_attempts, idempotency-keyed on the delivery id -- a replay never double-enqueues';
end;
$$;

\echo '>> app.send_test_webhook_delivery: staff-only, scoped to exactly ONE named endpoint (never the subscription-fanout app.queue_webhook_delivery itself uses); enqueues a real job with max_attempts=1, priority=10; a non-admin is denied'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaewebhook');
  v_admin1 uuid := '00000000-0000-0000-0000-000014000001';
  v_staff1 uuid := '00000000-0000-0000-0000-000014000002';
  v_endpoint_a uuid := (select id from app.webhook_endpoints where tenant_id = v_tenant1 and url = 'https://a.iaewebhook.test/hook');
  v_endpoint_b uuid := (select id from app.webhook_endpoints where tenant_id = v_tenant1 and url = 'https://b.iaewebhook.test/hook');
  v_delivery app.webhook_deliveries;
  v_job app.jobs;
  v_count_b integer;
begin
  v_delivery := app.send_test_webhook_delivery(v_endpoint_a, v_admin1, 'admin');
  if v_delivery.webhook_endpoint_id <> v_endpoint_a or v_delivery.event_type_code <> 'webhook.test' or v_delivery.max_attempts <> 1 then
    raise exception 'assertion failed: unexpected test delivery shape: %', to_jsonb(v_delivery);
  end if;

  select count(*) into v_count_b from app.webhook_deliveries where webhook_endpoint_id = v_endpoint_b and event_type_code = 'webhook.test';
  if v_count_b <> 0 then
    raise exception 'assertion failed: expected a test send to endpoint A to create ZERO deliveries for endpoint B, got %', v_count_b;
  end if;

  select * into v_job from app.jobs where payload->>'delivery_id' = v_delivery.id::text;
  if v_job.max_attempts <> 1 or v_job.priority <> 10 then
    raise exception 'assertion failed: expected the test job to carry max_attempts=1, priority=10, got %', to_jsonb(v_job);
  end if;

  begin
    perform app.send_test_webhook_delivery(v_endpoint_a, v_staff1, 'staff');
    raise exception 'assertion failed: expected insufficient_authority for a PRC:View-only staff member';
  exception when insufficient_privilege then null;
  end;

  raise notice 'PASS: send_test_webhook_delivery is scoped to exactly one endpoint, never fans out to another endpoint subscribed to the same event type; enqueues a fast-fail (max_attempts=1), high-priority (10) job; a non-admin is denied';
end;
$$;

\echo '>> app.replay_webhook_delivery: valid ONLY from status=dead_letter; resets delivery state and enqueues a FRESH job with a new idempotency key; denied for a non-dead_letter delivery and for a non-admin'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaewebhook');
  v_admin1 uuid := '00000000-0000-0000-0000-000014000001';
  v_staff1 uuid := '00000000-0000-0000-0000-000014000002';
  v_endpoint_a uuid := (select id from app.webhook_endpoints where tenant_id = v_tenant1 and url = 'https://a.iaewebhook.test/hook');
  v_pending_delivery app.webhook_deliveries;
  v_dead_delivery app.webhook_deliveries;
  v_original_job app.jobs;
  v_replayed app.webhook_deliveries;
  v_new_job app.jobs;
begin
  v_pending_delivery := app.send_test_webhook_delivery(v_endpoint_a, v_admin1, 'admin');

  begin
    perform app.replay_webhook_delivery(v_pending_delivery.id, v_admin1, 'admin');
    raise exception 'assertion failed: expected webhook_delivery_not_replayable for a pending (not dead_letter) delivery';
  exception when check_violation then
    if sqlerrm !~ 'webhook_delivery_not_replayable' then raise; end if;
  end;

  -- Drive it to dead_letter directly (max_attempts=1 -- one failed attempt
  -- suffices), mirroring what a real worker would report.
  select * into v_original_job from app.jobs where payload->>'delivery_id' = v_pending_delivery.id::text;
  perform app.record_webhook_delivery_attempt(v_pending_delivery.id, 'failed', 503, 'simulated failure', v_admin1, 'admin');
  select * into v_dead_delivery from app.webhook_deliveries where id = v_pending_delivery.id;
  if v_dead_delivery.status <> 'dead_letter' then
    raise exception 'assertion failed: expected status=dead_letter after 1 failed attempt against max_attempts=1, got %', v_dead_delivery.status;
  end if;

  -- ISS-2026-249 (Track B Batch 1): this dead-letter transition must now
  -- raise a real observability alert -- previously this producer never
  -- alerted at all.
  if not exists (
    select 1 from app.incidents
    where tenant_id = v_tenant1 and source_type = 'webhook' and signal_type = 'error' and severity = 'high'
      and title like 'webhook delivery dead-lettered:%'
  ) then
    raise exception 'assertion failed: expected a real app.incidents row (source_type=webhook, signal_type=error, high) after this dead-letter transition -- ISS-2026-249 regression';
  end if;

  begin
    perform app.replay_webhook_delivery(v_dead_delivery.id, v_staff1, 'staff');
    raise exception 'assertion failed: expected insufficient_authority for a PRC:View-only staff member';
  exception when insufficient_privilege then null;
  end;

  -- Tier C Batch 3 fix (Critical finding 1): a replay must NEVER reset the
  -- append-only `attempts` counter -- app.webhook_delivery_attempts'' own
  -- unique constraint (webhook_delivery_id, attempt_number) is computed from
  -- it by the unmodified app.record_webhook_delivery_attempt, so resetting
  -- to 0 would collide with the already-recorded history on the very next
  -- attempt. A replay instead grants a fresh BUDGET of max_attempts (the
  -- delivery's own currently-configured value) MORE real attempts.
  v_replayed := app.replay_webhook_delivery(v_dead_delivery.id, v_admin1, 'admin');
  if v_replayed.status <> 'pending' or v_replayed.attempts <> v_dead_delivery.attempts or v_replayed.max_attempts <> v_dead_delivery.attempts + v_dead_delivery.max_attempts then
    raise exception 'assertion failed: expected replay to reset status=pending WITHOUT resetting attempts, and to grant a fresh max_attempts budget, got %', to_jsonb(v_replayed);
  end if;

  select * into v_new_job from app.jobs where payload->>'delivery_id' = v_dead_delivery.id::text and job_id <> v_original_job.job_id;
  if not found or v_new_job.idempotency_key = v_original_job.idempotency_key then
    raise exception 'assertion failed: expected a FRESH job with a NEW idempotency key, distinct from the original job %', v_original_job.job_id;
  end if;

  -- Tier C Batch 3 REGRESSION PROOF (Critical finding 1): recording a real
  -- attempt after the replay must NOT collide with app.webhook_delivery_
  -- attempts_unique -- this is the exact bug the fix closes; a plain
  -- CREATE OR REPLACE reverting the fix would make this block fail loudly.
  perform app.record_webhook_delivery_attempt(v_dead_delivery.id, 'failed', 503, 'simulated failure after replay', v_admin1, 'admin');

  -- Drive it back to dead_letter (the replay budget was max_attempts=1
  -- originally, so ONE more failure exhausts the fresh budget too) and
  -- replay a SECOND time -- proving the fix holds across multiple replay
  -- cycles, not just one.
  select * into v_dead_delivery from app.webhook_deliveries where id = v_pending_delivery.id;
  if v_dead_delivery.status <> 'dead_letter' then
    raise exception 'assertion failed: expected dead_letter again after exhausting the replay budget, got %', v_dead_delivery.status;
  end if;
  perform app.replay_webhook_delivery(v_dead_delivery.id, v_admin1, 'admin');
  perform app.record_webhook_delivery_attempt(v_dead_delivery.id, 'success', 200, null, v_admin1, 'admin');

  raise notice 'PASS: replay_webhook_delivery is valid only from dead_letter, resets status WITHOUT resetting the append-only attempts counter (Tier C Batch 3 fix), and enqueues a genuinely fresh job (new idempotency key) -- a real attempt recorded after replay never collides with delivery-attempt history, across two full replay cycles -- denied for a non-terminal delivery and for a non-admin';
end;
$$;

\echo '>> app.replay_webhook_delivery: concurrent double-replay of the SAME dead_letter delivery -- the row lock (Tier C Batch 3 fix) must let exactly ONE succeed, never double-enqueue'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaewebhook');
  v_admin1 uuid := '00000000-0000-0000-0000-000014000001';
  v_endpoint_a uuid := (select id from app.webhook_endpoints where tenant_id = v_tenant1 and url = 'https://a.iaewebhook.test/hook');
  v_delivery app.webhook_deliveries;
  v_original_job app.jobs;
  v_drained app.jobs;
  v_job_count integer;
begin
  -- Drain any leftover pending webhook_retry jobs from earlier blocks in
  -- this same file first (the exact cross-block interference class
  -- self-caught in IAE-012's own build log) -- otherwise claim_next_job
  -- below could pick up a STALE job instead of the one this block's own
  -- send_test_webhook_delivery call creates.
  loop
    v_drained := app.claim_next_job('tierc3-drain-worker', array['webhook_retry'], 300);
    exit when v_drained is null;
    perform app.complete_job(v_drained.job_id, 'tierc3-drain-worker', null, 'tierc3-drain-worker');
  end loop;

  v_delivery := app.send_test_webhook_delivery(v_endpoint_a, v_admin1, 'admin');
  v_original_job := app.claim_next_job('tierc3-test-worker', array['webhook_retry'], 300);
  perform app.record_webhook_delivery_attempt(v_delivery.id, 'failed', 503, 'simulated failure', v_admin1, 'admin');
  perform app.record_job_failure(v_original_job.job_id, 'simulated failure', v_admin1, 'admin');

  -- A single-connection sequential proxy for the row lock: the SAME delivery
  -- id replayed twice inside two SEPARATE, sequential transactions is the
  -- weakest form of this proof available inside a single psql -f session
  -- (a real two-connection concurrent proof was performed live against a
  -- scratch database during the Tier C fix pass -- see docs/build-log/
  -- phase-09/IAE-340.md's own updated Tier C section). What THIS block
  -- proves permanently: a delivery already reset to pending by one replay
  -- can never be replayed again until it returns to dead_letter -- the
  -- actual guard the row lock makes airtight under real concurrency.
  perform app.replay_webhook_delivery(v_delivery.id, v_admin1, 'admin');
  begin
    perform app.replay_webhook_delivery(v_delivery.id, v_admin1, 'admin');
    raise exception 'assertion failed: expected webhook_delivery_not_replayable for an already-replayed (now pending) delivery';
  exception when check_violation then
    if sqlerrm !~ 'webhook_delivery_not_replayable' then raise; end if;
  end;

  select count(*) into v_job_count from app.jobs where payload->>'delivery_id' = v_delivery.id::text and status not in ('completed', 'dead_letter');
  if v_job_count <> 1 then
    raise exception 'assertion failed: expected exactly ONE live (non-terminal) job for this delivery after the rejected re-replay attempt -- the original job is dead_letter, only the single successful replay job should still be live -- got %', v_job_count;
  end if;

  raise notice 'PASS: a delivery already reset to pending by one replay can never be replayed again until it returns to dead_letter -- the guard a concurrent double-replay relies on';
end;
$$;

\echo '>> app.list_webhook_deliveries_for_tenant: scoped to this tenant, optional status filter, joined endpoint url; a non-admin and a cross-tenant admin are both denied'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaewebhook');
  v_admin1 uuid := '00000000-0000-0000-0000-000014000001';
  v_staff1 uuid := '00000000-0000-0000-0000-000014000002';
  v_admin2 uuid := '00000000-0000-0000-0000-000014000003';
  v_endpoint_a uuid := (select id from app.webhook_endpoints where tenant_id = v_tenant1 and url = 'https://a.iaewebhook.test/hook');
  v_row record;
  v_found_dead_letter boolean := false;
  v_dead_count integer := 0;
  v_dead_delivery app.webhook_deliveries;
begin
  -- A fresh delivery left in dead_letter (never replayed) -- the prior
  -- assertion block's own dead_letter delivery was already reset to pending
  -- by app.replay_webhook_delivery, so this block needs its own.
  v_dead_delivery := app.send_test_webhook_delivery(v_endpoint_a, v_admin1, 'admin');
  perform app.record_webhook_delivery_attempt(v_dead_delivery.id, 'failed', 500, 'simulated failure for list filter test', v_admin1, 'admin');

  for v_row in select * from app.list_webhook_deliveries_for_tenant(v_tenant1, v_admin1, null, 50) loop
    if v_row.endpoint_url is null or length(v_row.endpoint_url) = 0 then
      raise exception 'assertion failed: expected every delivery row to carry a real joined endpoint_url';
    end if;
    if v_row.status = 'dead_letter' then
      v_found_dead_letter := true;
    end if;
  end loop;
  if not v_found_dead_letter then
    raise exception 'assertion failed: expected at least one dead_letter delivery from the prior assertion block';
  end if;

  select count(*) into v_dead_count from app.list_webhook_deliveries_for_tenant(v_tenant1, v_admin1, 'dead_letter', 50);
  if v_dead_count = 0 then
    raise exception 'assertion failed: expected the status=dead_letter filter to return at least one row';
  end if;

  begin
    perform app.list_webhook_deliveries_for_tenant(v_tenant1, v_staff1, null, 50);
    raise exception 'assertion failed: expected insufficient_authority for a PRC:View-only staff member';
  exception when insufficient_privilege then null;
  end;

  begin
    perform app.list_webhook_deliveries_for_tenant(v_tenant1, v_admin2, null, 50);
    raise exception 'assertion failed: expected insufficient_authority for tenant2''s own admin against tenant1''s own deliveries';
  exception when insufficient_privilege then null;
  end;

  raise notice 'PASS: list_webhook_deliveries_for_tenant is scoped to this tenant with a real joined endpoint_url and a working status filter; a non-admin and a cross-tenant admin are both denied';
end;
$$;

\echo '>> ISS-2026-147 item 2 (webhook half): p_webhook_endpoint_id isolates one connector''s delivery history, composes with the status filter, leaves the unfiltered default unchanged, and refuses another tenant''s endpoint id indistinguishably from a nonexistent one'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaewebhook');
  v_admin1 uuid := '00000000-0000-0000-0000-000014000001';
  v_endpoint_a uuid := (select id from app.webhook_endpoints where tenant_id = v_tenant1 and url = 'https://a.iaewebhook.test/hook');
  v_endpoint_b uuid := (select id from app.webhook_endpoints where tenant_id = v_tenant1 and url = 'https://b.iaewebhook.test/hook');
  v_foreign_endpoint uuid;
  v_total integer;
  v_only_a integer;
  v_only_b integer;
  v_mismatched integer;
begin
  -- One fresh delivery per endpoint, so both connectors genuinely have history to separate.
  perform app.send_test_webhook_delivery(v_endpoint_a, v_admin1, 'admin');
  perform app.send_test_webhook_delivery(v_endpoint_b, v_admin1, 'admin');

  select count(*) into v_total from app.list_webhook_deliveries_for_tenant(v_tenant1, v_admin1, null, 200);
  select count(*) into v_only_a from app.list_webhook_deliveries_for_tenant(v_tenant1, v_admin1, null, 200, v_endpoint_a);
  select count(*) into v_only_b from app.list_webhook_deliveries_for_tenant(v_tenant1, v_admin1, null, 200, v_endpoint_b);

  if v_only_a = 0 or v_only_b = 0 then
    raise exception 'assertion failed: both endpoints must have deliveries of their own (a=%, b=%)', v_only_a, v_only_b;
  end if;
  if v_only_a >= v_total or v_only_b >= v_total then
    raise exception 'assertion failed: a per-endpoint slice must be strictly smaller than the tenant-wide list (total=%, a=%, b=%)', v_total, v_only_a, v_only_b;
  end if;

  -- The stronger claim than counting: not one returned row belongs to the other endpoint.
  select count(*) into v_mismatched from app.list_webhook_deliveries_for_tenant(v_tenant1, v_admin1, null, 200, v_endpoint_a) d
  where d.webhook_endpoint_id <> v_endpoint_a;
  if v_mismatched <> 0 then
    raise exception 'assertion failed: endpoint A''s filtered history contains % row(s) belonging to another endpoint', v_mismatched;
  end if;

  -- Composes with, rather than replaces, the pre-existing status filter.
  select count(*) into v_mismatched from app.list_webhook_deliveries_for_tenant(v_tenant1, v_admin1, 'dead_letter', 200, v_endpoint_a) d
  where d.webhook_endpoint_id <> v_endpoint_a or d.status <> 'dead_letter';
  if v_mismatched <> 0 then
    raise exception 'assertion failed: the endpoint and status filters must both apply, found % violating row(s)', v_mismatched;
  end if;

  -- Registered here rather than picked out of whatever another test file happened to leave in
  -- the shared database: the control has to be a KNOWN foreign endpoint, not an incidental one.
  v_foreign_endpoint := (app.register_webhook_endpoint(
    (select id from app.tenants where slug = 'iaewebhook2'),
    'https://foreign.iaewebhook2.test/hook', '["webhook.test"]'::jsonb,
    '00000000-0000-0000-0000-000014000003', 'admin'
  )).id;
  begin
    perform app.list_webhook_deliveries_for_tenant(v_tenant1, v_admin1, null, 50, v_foreign_endpoint);
    raise exception 'assertion failed: expected webhook_endpoint_not_found for another tenant''s endpoint';
  exception when no_data_found then
    if sqlerrm not like 'webhook_endpoint_not_found%' then raise; end if;
  end;
  begin
    perform app.list_webhook_deliveries_for_tenant(v_tenant1, v_admin1, null, 50, gen_random_uuid());
    raise exception 'assertion failed: expected webhook_endpoint_not_found for an id that exists nowhere';
  exception when no_data_found then
    if sqlerrm not like 'webhook_endpoint_not_found%' then raise; end if;
  end;

  raise notice 'PASS: ISS-2026-147 item 2 (webhook half) -- per-endpoint delivery filtering isolates correctly (total=%, a=%, b=%), composes with the status filter, and refuses a foreign endpoint id indistinguishably from a nonexistent one', v_total, v_only_a, v_only_b;
end;
$$;

\echo '>> real app.jobs <-> app.webhook_deliveries bridge proof: a full worker simulation (claim_next_job / record_webhook_delivery_attempt / complete_job) for a successful delivery, and (claim_next_job / record_webhook_delivery_attempt / record_job_failure, repeated) for one that exhausts max_attempts -- proving the two independent, deliberately-aligned retry state machines (design decision 2) actually stay aligned: BOTH the delivery and the job reach a terminal state together'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaewebhook');
  v_admin1 uuid := '00000000-0000-0000-0000-000014000001';
  v_endpoint_a uuid := (select id from app.webhook_endpoints where tenant_id = v_tenant1 and url = 'https://a.iaewebhook.test/hook');
  v_delivery app.webhook_deliveries;
  v_claimed app.jobs;
  v_completed app.jobs;
  v_failed_job app.jobs;
  v_final_delivery app.webhook_deliveries;
  v_i integer;
begin
  -- Drain any leftover pending webhook_retry jobs from earlier assertion
  -- blocks (each of which resolves its own DELIVERY state directly via
  -- app.record_webhook_delivery_attempt without necessarily claiming/
  -- resolving the corresponding JOB row) so this block starts from a
  -- genuinely empty queue -- claim_next_job's own priority/created_at
  -- ordering would otherwise pick up a stray leftover job instead of the
  -- one this block itself creates.
  loop
    v_claimed := app.claim_next_job('iwh-drain-worker', array['webhook_retry'], 300);
    exit when v_claimed is null;
    perform app.complete_job(v_claimed.job_id, 'iwh-drain-worker', null, 'iwh-drain-worker');
  end loop;

  -- Success path.
  v_delivery := app.send_test_webhook_delivery(v_endpoint_a, v_admin1, 'admin');
  v_claimed := app.claim_next_job('iwh-worker-1', array['webhook_retry'], 300);
  if v_claimed is null or (v_claimed.payload->>'delivery_id')::uuid <> v_delivery.id then
    raise exception 'assertion failed: expected claim_next_job to claim exactly this delivery''s own job, got %', to_jsonb(v_claimed);
  end if;
  perform app.record_webhook_delivery_attempt(v_delivery.id, 'success', 200, null, v_admin1, 'admin');
  v_completed := app.complete_job(v_claimed.job_id, 'iwh-worker-1', null, 'iwh-worker-1');
  if v_completed.status <> 'completed' then
    raise exception 'assertion failed: expected the job to complete, got %', v_completed.status;
  end if;
  select * into v_delivery from app.webhook_deliveries where id = v_delivery.id;
  if v_delivery.status <> 'delivered' then
    raise exception 'assertion failed: expected the delivery to be delivered, got %', v_delivery.status;
  end if;

  -- Exhaustion path: max_attempts=1 (a test delivery) -- the FIRST failure
  -- must dead-letter BOTH the delivery and the job together.
  v_delivery := app.send_test_webhook_delivery(v_endpoint_a, v_admin1, 'admin');
  v_claimed := app.claim_next_job('iwh-worker-1', array['webhook_retry'], 300);
  perform app.record_webhook_delivery_attempt(v_delivery.id, 'failed', 500, 'simulated failure', v_admin1, 'admin');
  v_failed_job := app.record_job_failure(v_claimed.job_id, 'simulated failure', v_admin1, 'admin');
  if v_failed_job.status <> 'dead_letter' then
    raise exception 'assertion failed: expected the job to reach dead_letter after exhausting max_attempts=1, got %', v_failed_job.status;
  end if;
  select * into v_final_delivery from app.webhook_deliveries where id = v_delivery.id;
  if v_final_delivery.status <> 'dead_letter' then
    raise exception 'assertion failed: expected the delivery to ALSO reach dead_letter, staying aligned with the job -- got %', v_final_delivery.status;
  end if;

  raise notice 'PASS: the real app.jobs <-> app.webhook_deliveries bridge holds under a full worker simulation -- a successful delivery completes both state machines together, and exhausting max_attempts dead-letters both together, staying numerically aligned as designed';
end;
$$;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on any new IAE-012 function'
do $$
declare
  v_fn text;
  v_new_functions text[] := array[
    'get_webhook_delivery_dispatch_info', 'send_test_webhook_delivery', 'replay_webhook_delivery',
    'list_webhook_deliveries_for_tenant'
  ];
begin
  foreach v_fn in array v_new_functions loop
    if exists (
      select 1 from information_schema.role_routine_grants
      where routine_schema = 'app' and routine_name = v_fn and grantee = 'anon'
    ) then
      raise exception 'assertion failed: anon must not hold EXECUTE on app.%', v_fn;
    end if;
  end loop;

  raise notice 'PASS: anon holds zero EXECUTE on any new IAE-012 function';
end;
$$;

\echo '>> live forged-session proof (request.jwt.claims + set role authenticated): the REAL tenant_admin, acting through a genuine authenticated session (not the connecting superuser), can list webhook deliveries end to end; the same session cannot claim a different identity (ATW-032)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaewebhook');
  v_admin1 uuid := '00000000-0000-0000-0000-000014000001';
  v_staff1 uuid := '00000000-0000-0000-0000-000014000002';
  v_count integer;
begin
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000014000001", "role": "authenticated"}', false);
  set role authenticated;

  select count(*) into v_count from app.list_webhook_deliveries_for_tenant(v_tenant1, v_admin1, null, 50);
  if v_count = 0 then
    raise exception 'assertion failed: expected a genuine authenticated session to list at least one real delivery';
  end if;

  begin
    perform app.list_webhook_deliveries_for_tenant(v_tenant1, v_staff1, null, 50);
    raise exception 'assertion failed: expected actor_identity_mismatch -- session % must not claim identity %', v_admin1, v_staff1;
  exception
    when insufficient_privilege then
      if sqlerrm !~ 'actor_identity_mismatch' then raise; end if;
  end;

  reset role;
  perform set_config('request.jwt.claims', 'null', false);

  raise notice 'PASS: a real forged authenticated session, not the connecting superuser, lists real webhook deliveries end to end; the same session cannot claim a different identity';
end;
$$;

\echo '>> webhook-management.sql: ALL PASSED'
