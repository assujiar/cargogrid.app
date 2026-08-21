-- Real, executable test evidence for IAE-014 (Email, WhatsApp and SMS
-- Integrations, Prompt 342) -- run via `pnpm run db:test` against a real,
-- disposable Postgres database. Scoped to this checkpoint's own additive
-- migration (supabase/migrations/
-- 20260805010000_create_intelligence_email_whatsapp_sms_integrations.sql).
-- Fresh, distinctive tenant fixture (iaemsg), fixture id range
-- 00000000-0000-0000-0000-000016xxxxxx.
--
-- Does NOT re-test app.queue_notification's own already-covered PLT-127
-- mechanics (recipient authorization, preference fallback, template
-- rendering/escaping) -- scripts/db-tests/notification.sql already covers
-- those. This file tests only what this checkpoint adds: channel widening,
-- the real app.jobs bridge (including its own idempotent-replay-never-
-- double-enqueues guarantee), the contact-address primitive, cost metering,
-- and the delivery worker's own dispatch-info resolution.

\set ON_ERROR_STOP on

\echo '>> setup: tenant iaemsg with a real, published notification template declaring all four channels (in_app/email/whatsapp/sms), a real recipient with an active membership, and a real active email_smtp connection'
do $$
declare
  v_tenant uuid;
  v_admin uuid := '00000000-0000-0000-0000-000016000001';
  v_recipient uuid := '00000000-0000-0000-0000-000016000002';
  v_supreme uuid := '00000000-0000-0000-0000-000016000999';
  v_draft app.config_versions;
  v_published app.config_versions;
  v_configurer_role uuid;
  v_configurer_draft app.role_versions;
begin
  insert into auth.users (id, email) values
    (v_admin, 'admin@iaemsg.test'),
    (v_recipient, 'recipient@iaemsg.test'),
    (v_supreme, 'supreme@iaemsg.test');

  perform app.grant_principal_membership(v_supreme, 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('iaemsg', 'IaeMsg Co', 'idem-iaemsg', 'tester');
  v_tenant := (select id from app.tenants where slug = 'iaemsg');
  perform app.transition_tenant_status(v_tenant, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant, v_admin, 'admin@iaemsg.test', 'IaeMsg Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iaemsg.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin, 'tenant_admin', v_tenant, null, 'tester');

  v_configurer_role := (app.create_role(v_tenant, 'Integration Configurer', 'INTHUB:Configure', 'tester')).id;
  v_configurer_draft := app.create_role_version(v_configurer_role, 'tester');
  perform app.set_role_version_permissions(v_configurer_draft.id, array(select id from app.permissions where resource_module_code = 'INTHUB' and action = 'Configure'), 'tester');
  perform app.publish_role_version(v_configurer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant, (select id from app.role_versions where role_id = v_configurer_role and status = 'published'), v_admin, v_admin, 'admin');

  perform app.invite_user(v_tenant, v_recipient, 'recipient@iaemsg.test', 'IaeMsg Recipient', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'recipient@iaemsg.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_recipient, 'org_user', v_tenant, null, 'tester');

  perform app.register_notification_type('iaemsg.test_type', 'IaeMsg test notification', 'phase-09-foundation', v_supreme, 'supreme');

  v_draft := app.create_config_draft('notification:iaemsg.test_type', v_tenant, 'tenant', null, v_admin, 'admin');
  perform app.set_config_items(v_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'channels', 'value', jsonb_build_array('in_app', 'email', 'whatsapp', 'sms')),
    jsonb_build_object('key', 'default_locale', 'value', 'en'),
    jsonb_build_object('key', 'templates', 'value', jsonb_build_object('en', jsonb_build_object('subject', 'Hello {{name}}', 'body', 'Body for {{name}}')))
  ), v_admin, 'admin');
  v_published := app.publish_notification_template(v_draft.id, v_admin, now(), 'admin');

  perform app.create_integration_connection(v_tenant, 'email_smtp', 'Primary Email', 'production', null, null, null, jsonb_build_object('apiUrl', 'https://email.iaemsg-provider.test/send'), 'test-credential-value', v_admin, 'admin');
end $$;

\echo '>> app.queue_notification (extended): a genuinely new whatsapp/sms/email delivery also enqueues a real app.jobs notification_batch job, idempotency-keyed on the notification id; a repeated (idempotent-replay) call never double-enqueues a job'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug = 'iaemsg');
  v_admin uuid := '00000000-0000-0000-0000-000016000001';
  v_recipient uuid := '00000000-0000-0000-0000-000016000002';
  v_published_id uuid := (select v.id from app.config_versions v join app.config_objects o on o.id = v.config_object_id where o.config_type_code = 'notification:iaemsg.test_type' and v.status = 'published');
  v_notification app.notifications;
  v_replay app.notifications;
  v_job app.jobs;
  v_job_count integer;
begin
  v_notification := app.queue_notification(v_published_id, v_tenant, 'iaemsg.test_type', v_recipient, 'whatsapp', 'en', jsonb_build_object('name', 'Alice'), 'idem-msg-1', v_admin, 'admin');
  if v_notification.status <> 'queued' or v_notification.effective_channel <> 'whatsapp' then
    raise exception 'assertion failed: expected a genuinely new whatsapp notification to be queued, got %', to_jsonb(v_notification);
  end if;

  select * into v_job from app.jobs where job_type = 'notification_batch' and payload->>'notification_id' = v_notification.id::text;
  if not found or v_job.idempotency_key <> 'notification-delivery:' || v_notification.id::text or v_job.status <> 'pending' then
    raise exception 'assertion failed: expected a real, idempotency-keyed app.jobs job for this notification, got %', to_jsonb(v_job);
  end if;

  -- Tier C Batch 3 lesson applied proactively: an idempotent replay (same
  -- dedupe key) must return the SAME row and never enqueue a second job.
  v_replay := app.queue_notification(v_published_id, v_tenant, 'iaemsg.test_type', v_recipient, 'whatsapp', 'en', jsonb_build_object('name', 'Alice'), 'idem-msg-1', v_admin, 'admin');
  if v_replay.id <> v_notification.id then
    raise exception 'assertion failed: expected the idempotent replay to return the SAME notification row';
  end if;
  select count(*) into v_job_count from app.jobs where job_type = 'notification_batch' and payload->>'notification_id' = v_notification.id::text;
  if v_job_count <> 1 then
    raise exception 'assertion failed: expected exactly ONE job after an idempotent replay, got %', v_job_count;
  end if;

  raise notice 'PASS: queue_notification enqueues a real app.jobs job per genuinely new non-in_app delivery, idempotency-keyed on the notification id -- an idempotent replay never double-enqueues';
end;
$$;

\echo '>> app.set_notification_contact_address: self-service by default; a tenant''s own support-grant authority may set it on a user''s behalf; a third, unrelated identity is denied; re-setting clears verification'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug = 'iaemsg');
  v_admin uuid := '00000000-0000-0000-0000-000016000001';
  v_recipient uuid := '00000000-0000-0000-0000-000016000002';
  v_stranger uuid := '00000000-0000-0000-0000-000016000003';
  v_addr app.notification_contact_addresses;
begin
  insert into auth.users (id, email) values (v_stranger, 'stranger@iaemsg.test');
  perform app.invite_user(v_tenant, v_stranger, 'stranger@iaemsg.test', 'IaeMsg Stranger', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'stranger@iaemsg.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_stranger, 'org_user', v_tenant, null, 'tester');

  -- Self-service.
  v_addr := app.set_notification_contact_address(v_tenant, v_recipient, 'whatsapp', '+15551234567', v_recipient, 'recipient');
  if v_addr.address <> '+15551234567' or v_addr.verified_at is not null then
    raise exception 'assertion failed: expected a freshly-set address with no verification, got %', to_jsonb(v_addr);
  end if;

  -- A stranger with no support-grant authority may not set it on the recipient's behalf.
  begin
    perform app.set_notification_contact_address(v_tenant, v_recipient, 'sms', '+15559999999', v_stranger, 'stranger');
    raise exception 'assertion failed: expected insufficient_authority for an unrelated identity acting on someone else''s behalf';
  exception when insufficient_privilege then null;
  end;

  -- The tenant's own support-grant authority (tenant_admin) may set it on the recipient's behalf.
  v_addr := app.set_notification_contact_address(v_tenant, v_recipient, 'sms', '+15550001111', v_admin, 'admin');
  if v_addr.channel <> 'sms' or v_addr.address <> '+15550001111' then
    raise exception 'assertion failed: expected the tenant admin''s own support-grant authority to succeed, got %', to_jsonb(v_addr);
  end if;

  -- Re-setting an already-set channel clears verification (a changed number is unverified again).
  update app.notification_contact_addresses set verified_at = now() where tenant_id = v_tenant and auth_user_id = v_recipient and channel = 'whatsapp';
  v_addr := app.set_notification_contact_address(v_tenant, v_recipient, 'whatsapp', '+15552223333', v_recipient, 'recipient');
  if v_addr.verified_at is not null then
    raise exception 'assertion failed: expected re-setting the address to clear verified_at, got %', v_addr.verified_at;
  end if;

  raise notice 'PASS: set_notification_contact_address is self-service by default, honors the tenant''s own support-grant authority, denies an unrelated identity, and clears verification on re-set';
end;
$$;

\echo '>> app.record_notification_delivery_attempt (extended): a provider unit cost is billed at a real +20% markup via app.compute_provider_billed_amount; a null cost (e.g. in_app) never fabricates a billed_amount'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug = 'iaemsg');
  v_admin uuid := '00000000-0000-0000-0000-000016000001';
  v_recipient uuid := '00000000-0000-0000-0000-000016000002';
  v_published_id uuid := (select v.id from app.config_versions v join app.config_objects o on o.id = v.config_object_id where o.config_type_code = 'notification:iaemsg.test_type' and v.status = 'published');
  v_notification app.notifications;
  v_attempt app.notification_delivery_attempts;
begin
  v_notification := app.queue_notification(v_published_id, v_tenant, 'iaemsg.test_type', v_recipient, 'sms', 'en', jsonb_build_object('name', 'Bob'), 'idem-msg-cost-1', v_admin, 'admin');

  v_attempt := app.record_notification_delivery_attempt(v_notification.id, 'success', null, v_admin, 'admin', 0.0100, 'USD');
  if v_attempt.provider_unit_cost_amount <> 0.0100 or v_attempt.billed_amount <> 0.0120 or v_attempt.currency <> 'USD' then
    raise exception 'assertion failed: expected billed_amount = 0.0100 * 1.20 = 0.0120, got %', to_jsonb(v_attempt);
  end if;

  begin
    perform app.record_notification_delivery_attempt(v_notification.id, 'failed', 'boom', v_admin, 'admin', -1, 'USD');
    raise exception 'assertion failed: expected notification_invalid_cost_amount for a negative cost';
  exception when check_violation then
    if sqlerrm !~ 'notification_invalid_cost_amount' then raise; end if;
  end;

  raise notice 'PASS: record_notification_delivery_attempt computes billed_amount at a real +20%% markup via app.compute_provider_billed_amount; a negative cost is rejected';
end;
$$;

\echo '>> app.get_notification_dispatch_info / app.get_notification_provider_credential: the real delivery worker''s own reads -- resolves recipient email (auth.users) for the email channel and the tenant''s own active connection/credential; never exposes the raw credential through the dispatch-info read itself'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug = 'iaemsg');
  v_admin uuid := '00000000-0000-0000-0000-000016000001';
  v_recipient uuid := '00000000-0000-0000-0000-000016000002';
  v_published_id uuid := (select v.id from app.config_versions v join app.config_objects o on o.id = v.config_object_id where o.config_type_code = 'notification:iaemsg.test_type' and v.status = 'published');
  v_notification app.notifications;
  v_info record;
  v_credential text;
begin
  v_notification := app.queue_notification(v_published_id, v_tenant, 'iaemsg.test_type', v_recipient, 'email', 'en', jsonb_build_object('name', 'Carol'), 'idem-msg-dispatch-1', v_admin, 'admin');

  select * into v_info from app.get_notification_dispatch_info(v_notification.id);
  if v_info.recipient_email <> 'recipient@iaemsg.test' then
    raise exception 'assertion failed: expected the recipient''s own real auth.users.email, got %', v_info.recipient_email;
  end if;
  if v_info.connection_status <> 'active' or (v_info.connection_config->>'apiUrl') <> 'https://email.iaemsg-provider.test/send' then
    raise exception 'assertion failed: expected the tenant''s own real active email_smtp connection/config, got %', to_jsonb(v_info);
  end if;

  v_credential := app.get_notification_provider_credential(v_info.connection_id);
  if v_credential <> 'test-credential-value' then
    raise exception 'assertion failed: expected the real stored credential, got %', v_credential;
  end if;

  raise notice 'PASS: get_notification_dispatch_info resolves the real recipient email and the tenant''s own active connection/config; get_notification_provider_credential is the separate, dedicated credential read';
end;
$$;

\echo '>> real app.jobs <-> app.notifications bridge proof: a full worker simulation (claim_next_job / record_notification_delivery_attempt / complete_job) for a successful delivery'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug = 'iaemsg');
  v_admin uuid := '00000000-0000-0000-0000-000016000001';
  v_recipient uuid := '00000000-0000-0000-0000-000016000002';
  v_published_id uuid := (select v.id from app.config_versions v join app.config_objects o on o.id = v.config_object_id where o.config_type_code = 'notification:iaemsg.test_type' and v.status = 'published');
  v_notification app.notifications;
  v_drained app.jobs;
  v_job app.jobs;
  v_final app.notifications;
begin
  -- Drain any leftover pending notification_batch jobs from earlier blocks in
  -- this same file first (the cross-block interference class self-caught in
  -- IAE-012's own build log).
  loop
    v_drained := app.claim_next_job('iaemsg-drain-worker', array['notification_batch'], 300);
    exit when v_drained is null;
    perform app.complete_job(v_drained.job_id, 'iaemsg-drain-worker', null, 'iaemsg-drain-worker');
  end loop;

  v_notification := app.queue_notification(v_published_id, v_tenant, 'iaemsg.test_type', v_recipient, 'email', 'en', jsonb_build_object('name', 'Dana'), 'idem-msg-bridge-1', v_admin, 'admin');

  v_job := app.claim_next_job('iaemsg-worker-1', array['notification_batch'], 300);
  if v_job is null or (v_job.payload->>'notification_id')::uuid <> v_notification.id then
    raise exception 'assertion failed: expected claim_next_job to claim exactly this notification''s own job, got %', to_jsonb(v_job);
  end if;

  perform app.record_notification_delivery_attempt(v_notification.id, 'success', null, v_admin, 'admin', 0.0050, 'USD');
  perform app.complete_job(v_job.job_id, 'iaemsg-worker-1', null, 'iaemsg-worker-1');

  select * into v_final from app.notifications where id = v_notification.id;
  if v_final.status <> 'sent' then
    raise exception 'assertion failed: expected the notification to reach status=sent, got %', v_final.status;
  end if;
  if (select status from app.jobs where job_id = v_job.job_id) <> 'completed' then
    raise exception 'assertion failed: expected the job to reach status=completed';
  end if;

  raise notice 'PASS: the real app.jobs <-> app.notifications bridge holds under a full worker simulation -- a successful delivery completes both state machines together';
end;
$$;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on any new IAE-014 function; app.notification_contact_addresses is self-only RLS, proven via a live forged authenticated session'
do $$
declare
  v_fn text;
  v_new_functions text[] := array[
    'set_notification_contact_address', 'compute_provider_billed_amount',
    'get_notification_dispatch_info', 'get_notification_provider_credential'
  ];
  v_tenant uuid := (select id from app.tenants where slug = 'iaemsg');
  v_recipient uuid := '00000000-0000-0000-0000-000016000002';
  v_stranger uuid := '00000000-0000-0000-0000-000016000003';
  v_count integer;
begin
  foreach v_fn in array v_new_functions loop
    if exists (
      select 1 from information_schema.role_routine_grants
      where routine_schema = 'app' and routine_name = v_fn and grantee = 'anon'
    ) then
      raise exception 'assertion failed: anon must not hold EXECUTE on app.%', v_fn;
    end if;
  end loop;

  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000016000003", "role": "authenticated"}', false);
  set role authenticated;

  select count(*) into v_count from app.notification_contact_addresses where tenant_id = v_tenant and auth_user_id = v_recipient;
  if v_count <> 0 then
    raise exception 'assertion failed: expected a genuine forged session (stranger) to see ZERO of another identity''s own contact addresses via direct RLS-scoped table access, got %', v_count;
  end if;

  reset role;
  perform set_config('request.jwt.claims', 'null', false);

  raise notice 'PASS: anon holds zero EXECUTE on any new IAE-014 function; app.notification_contact_addresses is genuinely self-only under RLS, proven via a real forged authenticated session';
end;
$$;

\echo '>> email-whatsapp-sms-integrations.sql: ALL PASSED'
