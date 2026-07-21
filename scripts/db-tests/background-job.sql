-- Real, executable test evidence for PLT-132 (Background Job Framework, CG-S6-PLT-029).

\set ON_ERROR_STOP on

\echo '>> setup: two tenants; Acme has a requester, a shared-org-unit teammate, an outsider, a tenant_admin (support authority), and a global Supreme Admin'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
  v_org_unit_id uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000004001', 'requesterjob@example.test'),
    ('00000000-0000-0000-0000-000000004002', 'teammatejob@example.test'),
    ('00000000-0000-0000-0000-000000004003', 'outsiderjob@example.test'),
    ('00000000-0000-0000-0000-000000004004', 'tenantadminjob@example.test'),
    ('00000000-0000-0000-0000-000000004005', 'supremejob@example.test'),
    ('00000000-0000-0000-0000-000000004006', 'othertenantjob@example.test');

  perform app.provision_tenant('acmejob', 'Acme Job Co', 'idem-acmejob', 'tester');
  v_tenant_id := (select id from app.tenants where slug = 'acmejob');
  perform app.transition_tenant_status(v_tenant_id, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_id, 'company', null, 'ACMEJOB-CO', 'Acme Co', 'tester');
  v_org_unit_id := (select id from app.org_units where tenant_id = v_tenant_id and code = 'ACMEJOB-CO');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000004001', 'requesterjob@example.test', 'Requester', v_org_unit_id, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'requesterjob@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000004001', 'org_user', v_tenant_id, null, 'tester');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000004002', 'teammatejob@example.test', 'Teammate', v_org_unit_id, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'teammatejob@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000004002', 'org_user', v_tenant_id, null, 'tester');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000004003', 'outsiderjob@example.test', 'Outsider', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'outsiderjob@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000004003', 'org_user', v_tenant_id, null, 'tester');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000004004', 'tenantadminjob@example.test', 'Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'tenantadminjob@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000004004', 'tenant_admin', v_tenant_id, null, 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000004005', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('gizmojob', 'Gizmo Job Co', 'idem-gizmojob', 'tester');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmojob');
  perform app.transition_tenant_status(v_other_tenant_id, 'active', 'setup', 'tester');
  perform app.invite_user(v_other_tenant_id, '00000000-0000-0000-0000-000000004006', 'othertenantjob@example.test', 'Other Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'othertenantjob@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000004006', 'tenant_admin', v_other_tenant_id, null, 'tester');
end;
$$;

\echo '>> app.compute_job_backoff_seconds: equal-jitter bounds hold across a spread of attempts, capped, never below half the computed delay'
do $$
declare
  v_result integer;
  i integer;
begin
  -- attempts=1: uncapped=30, capped=30, expect in [15,30]
  for i in 1..20 loop
    v_result := app.compute_job_backoff_seconds(1);
    if v_result < 15 or v_result > 30 then
      raise exception 'assertion failed: attempts=1 backoff % out of expected [15,30] range', v_result;
    end if;
  end loop;

  -- attempts=3: uncapped=120, capped=120, expect in [60,120]
  for i in 1..20 loop
    v_result := app.compute_job_backoff_seconds(3);
    if v_result < 60 or v_result > 120 then
      raise exception 'assertion failed: attempts=3 backoff % out of expected [60,120] range', v_result;
    end if;
  end loop;

  -- attempts=10: uncapped=30*2^9=15360, capped at 3600, expect in [1800,3600]
  for i in 1..20 loop
    v_result := app.compute_job_backoff_seconds(10);
    if v_result < 1800 or v_result > 3600 then
      raise exception 'assertion failed: attempts=10 backoff % out of expected [1800,3600] cap range', v_result;
    end if;
  end loop;
end;
$$;

\echo '>> app.enqueue_job: authority, import/export must use the dedicated entrypoint, unknown type, unsafe payload, invalid max_attempts, idempotency'
do $$
declare
  v_tenant_id uuid;
  v_job1 app.jobs;
  v_job2 app.jobs;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmejob');

  begin
    perform app.enqueue_job(v_tenant_id, 'notification_batch', '{}'::jsonb, 0, null, 3, '00000000-0000-0000-0000-000000004006', 'outsider tenant admin');
    raise exception 'assertion failed: expected job_actor_unauthorized for an actor with no membership in this tenant';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.enqueue_job(v_tenant_id, 'import', '{}'::jsonb, 0, null, 3, '00000000-0000-0000-0000-000000004001', 'requester');
    raise exception 'assertion failed: expected job_type_requires_dedicated_entrypoint for import';
  exception
    when check_violation then
      if sqlerrm !~ 'job_type_requires_dedicated_entrypoint' then raise; end if;
  end;

  begin
    perform app.enqueue_job(v_tenant_id, 'export', '{}'::jsonb, 0, null, 3, '00000000-0000-0000-0000-000000004001', 'requester');
    raise exception 'assertion failed: expected job_type_requires_dedicated_entrypoint for export';
  exception
    when check_violation then
      if sqlerrm !~ 'job_type_requires_dedicated_entrypoint' then raise; end if;
  end;

  begin
    perform app.enqueue_job(v_tenant_id, 'not_a_real_type', '{}'::jsonb, 0, null, 3, '00000000-0000-0000-0000-000000004001', 'requester');
    raise exception 'assertion failed: expected job_invalid_type';
  exception
    when check_violation then
      if sqlerrm !~ 'job_invalid_type' then raise; end if;
  end;

  begin
    perform app.enqueue_job(v_tenant_id, 'notification_batch', '{}'::jsonb, 0, null, 0, '00000000-0000-0000-0000-000000004001', 'requester');
    raise exception 'assertion failed: expected job_invalid_max_attempts for max_attempts=0';
  exception
    when check_violation then
      if sqlerrm !~ 'job_invalid_max_attempts' then raise; end if;
  end;

  v_job1 := app.enqueue_job(v_tenant_id, 'notification_batch', jsonb_build_object('template', 'welcome'), 5, 'idem-enqueue-1', 3, '00000000-0000-0000-0000-000000004001', 'requester');
  if v_job1.status <> 'pending' or v_job1.job_type <> 'notification_batch' or v_job1.priority <> 5 then
    raise exception 'assertion failed: unexpected initial job state %', v_job1;
  end if;

  v_job2 := app.enqueue_job(v_tenant_id, 'notification_batch', jsonb_build_object('template', 'welcome'), 5, 'idem-enqueue-1', 3, '00000000-0000-0000-0000-000000004001', 'requester');
  if v_job2.job_id <> v_job1.job_id then
    raise exception 'assertion failed: expected a repeated idempotency_key to return the existing job, not create a duplicate';
  end if;
end;
$$;

\echo '>> app.claim_next_job: worker_id/lease validation, priority+FIFO ordering, next_attempt_at gating, stale-lease reclaim (crash recovery), no reclaim of a live lease, returns null when nothing claimable'
do $$
declare
  v_tenant_id uuid;
  v_low_priority app.jobs;
  v_high_priority app.jobs;
  v_claimed1 app.jobs;
  v_claimed2 app.jobs;
  v_claimed3 app.jobs;
  v_future_job app.jobs;
  v_stale_job app.jobs;
  v_reclaimed app.jobs;
  v_live_job app.jobs;
  v_not_reclaimed app.jobs;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmejob');

  begin
    perform app.claim_next_job('', array['notification_batch'], 300);
    raise exception 'assertion failed: expected job_worker_id_required for an empty worker id';
  exception
    when check_violation then
      if sqlerrm !~ 'job_worker_id_required' then raise; end if;
  end;

  begin
    perform app.claim_next_job('worker-1', array['notification_batch'], 0);
    raise exception 'assertion failed: expected job_invalid_lease_duration for a non-positive lease';
  exception
    when check_violation then
      if sqlerrm !~ 'job_invalid_lease_duration' then raise; end if;
  end;

  v_low_priority := app.enqueue_job(v_tenant_id, 'dashboard_refresh', '{}'::jsonb, 0, 'idem-claim-low', 3, '00000000-0000-0000-0000-000000004001', 'requester');
  v_high_priority := app.enqueue_job(v_tenant_id, 'dashboard_refresh', '{}'::jsonb, 10, 'idem-claim-high', 3, '00000000-0000-0000-0000-000000004001', 'requester');

  v_claimed1 := app.claim_next_job('worker-a', array['dashboard_refresh'], 300);
  if v_claimed1.job_id <> v_high_priority.job_id or v_claimed1.status <> 'in_progress' or v_claimed1.locked_by <> 'worker-a' or v_claimed1.locked_until is null then
    raise exception 'assertion failed: expected the higher-priority job to be claimed first, got %', v_claimed1;
  end if;

  v_claimed2 := app.claim_next_job('worker-b', array['dashboard_refresh'], 300);
  if v_claimed2.job_id <> v_low_priority.job_id then
    raise exception 'assertion failed: expected the second claim to get the remaining lower-priority job, got %', v_claimed2;
  end if;

  v_claimed3 := app.claim_next_job('worker-c', array['dashboard_refresh'], 300);
  if v_claimed3 is not null then
    raise exception 'assertion failed: expected no more dashboard_refresh jobs to claim, got %', v_claimed3;
  end if;

  -- next_attempt_at gating: a job scheduled in the future is not claimable yet.
  v_future_job := app.enqueue_job(v_tenant_id, 'webhook_retry', '{}'::jsonb, 0, 'idem-claim-future', 3, '00000000-0000-0000-0000-000000004001', 'requester');
  update app.jobs set next_attempt_at = now() + interval '1 hour' where job_id = v_future_job.job_id;
  v_not_reclaimed := app.claim_next_job('worker-d', array['webhook_retry'], 300);
  if v_not_reclaimed is not null then
    raise exception 'assertion failed: expected a job scheduled in the future to not be claimable yet, got %', v_not_reclaimed;
  end if;
  update app.jobs set next_attempt_at = now() - interval '1 minute' where job_id = v_future_job.job_id;
  v_not_reclaimed := app.claim_next_job('worker-d', array['webhook_retry'], 300);
  if v_not_reclaimed.job_id <> v_future_job.job_id then
    raise exception 'assertion failed: expected the job to become claimable once next_attempt_at has passed, got %', v_not_reclaimed;
  end if;

  -- Stale-lease reclaim: an in_progress job whose lease has already expired (the
  -- worker presumably crashed) is claimable by a different worker.
  v_stale_job := app.enqueue_job(v_tenant_id, 'integration_sync', '{}'::jsonb, 0, 'idem-claim-stale', 3, '00000000-0000-0000-0000-000000004001', 'requester');
  perform app.claim_next_job('worker-crashed', array['integration_sync'], 300);
  update app.jobs set locked_until = now() - interval '1 minute' where job_id = v_stale_job.job_id;
  v_reclaimed := app.claim_next_job('worker-recovering', array['integration_sync'], 300);
  if v_reclaimed.job_id <> v_stale_job.job_id or v_reclaimed.locked_by <> 'worker-recovering' then
    raise exception 'assertion failed: expected the stale-leased job to be reclaimed by a different worker, got %', v_reclaimed;
  end if;

  -- A job with a still-live lease is never reclaimed by a second claim call.
  v_live_job := app.enqueue_job(v_tenant_id, 'loyalty_expiration', '{}'::jsonb, 0, 'idem-claim-live', 3, '00000000-0000-0000-0000-000000004001', 'requester');
  perform app.claim_next_job('worker-holding', array['loyalty_expiration'], 300);
  v_not_reclaimed := app.claim_next_job('worker-intruder', array['loyalty_expiration'], 300);
  if v_not_reclaimed is not null then
    raise exception 'assertion failed: expected a job with a still-live lease to not be reclaimable, got %', v_not_reclaimed;
  end if;
end;
$$;

\echo '>> app.heartbeat_job: extends the lease only for the current holder; rejects a non-holder or a non-in_progress job'
do $$
declare
  v_tenant_id uuid;
  v_job app.jobs;
  v_claimed app.jobs;
  v_heartbeat app.jobs;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmejob');
  v_job := app.enqueue_job(v_tenant_id, 'document_generation', '{}'::jsonb, 0, 'idem-heartbeat-1', 3, '00000000-0000-0000-0000-000000004001', 'requester');
  v_claimed := app.claim_next_job('worker-hb', array['document_generation'], 60);

  begin
    perform app.heartbeat_job(v_claimed.job_id, 'worker-wrong', 60);
    raise exception 'assertion failed: expected job_lease_not_held for the wrong worker id';
  exception
    when check_violation then
      if sqlerrm !~ 'job_lease_not_held' then raise; end if;
  end;

  v_heartbeat := app.heartbeat_job(v_claimed.job_id, 'worker-hb', 600);
  if v_heartbeat.locked_until <= v_claimed.locked_until then
    raise exception 'assertion failed: expected the heartbeat to extend locked_until, got % (was %)', v_heartbeat.locked_until, v_claimed.locked_until;
  end if;

  begin
    perform app.heartbeat_job(gen_random_uuid(), 'worker-hb', 60);
    raise exception 'assertion failed: expected job_not_found for a bogus job id, a distinct code from job_lease_not_held';
  exception
    when no_data_found then
      null;
  end;
end;
$$;

\echo '>> app.complete_job: only the current lease holder may complete; releases the lease and clears error'
do $$
declare
  v_tenant_id uuid;
  v_job app.jobs;
  v_claimed app.jobs;
  v_completed app.jobs;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmejob');
  v_job := app.enqueue_job(v_tenant_id, 'report_generation', '{}'::jsonb, 0, 'idem-complete-1', 3, '00000000-0000-0000-0000-000000004001', 'requester');
  v_claimed := app.claim_next_job('worker-complete', array['report_generation'], 300);

  begin
    perform app.complete_job(v_claimed.job_id, 'worker-not-holder', 'https://example.test/result.pdf', 'worker-not-holder');
    raise exception 'assertion failed: expected job_lease_not_held for a non-holder completion attempt';
  exception
    when check_violation then
      if sqlerrm !~ 'job_lease_not_held' then raise; end if;
  end;

  v_completed := app.complete_job(v_claimed.job_id, 'worker-complete', 'https://example.test/result.pdf', 'worker-complete');
  if v_completed.status <> 'completed' or v_completed.locked_by is not null or v_completed.locked_until is not null or v_completed.result_url <> 'https://example.test/result.pdf' then
    raise exception 'assertion failed: unexpected completed job state %', v_completed;
  end if;
end;
$$;

\echo '>> app.record_job_failure (extended): schedules next_attempt_at via backoff on retry, releases the lease, clears next_attempt_at on dead_letter; a job is not claimable before its next_attempt_at and is claimable after'
do $$
declare
  v_tenant_id uuid;
  v_job app.jobs;
  v_claimed app.jobs;
  v_after_failure app.jobs;
  v_reclaim_too_soon app.jobs;
  v_reclaimed app.jobs;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmejob');
  v_job := app.enqueue_job(v_tenant_id, 'recurring_billing', '{}'::jsonb, 0, 'idem-failure-backoff-1', 5, '00000000-0000-0000-0000-000000004001', 'requester');
  v_claimed := app.claim_next_job('worker-fail', array['recurring_billing'], 300);

  v_after_failure := app.record_job_failure(v_claimed.job_id, 'transient provider error', '00000000-0000-0000-0000-000000004001', 'requester');
  if v_after_failure.status <> 'pending' or v_after_failure.locked_by is not null or v_after_failure.locked_until is not null or v_after_failure.next_attempt_at is null or v_after_failure.next_attempt_at <= now() then
    raise exception 'assertion failed: expected a retryable failure to release the lease and schedule a future next_attempt_at, got %', v_after_failure;
  end if;

  v_reclaim_too_soon := app.claim_next_job('worker-retry-too-soon', array['recurring_billing'], 300);
  if v_reclaim_too_soon is not null then
    raise exception 'assertion failed: expected the job to not be claimable before its scheduled next_attempt_at, got %', v_reclaim_too_soon;
  end if;

  update app.jobs set next_attempt_at = now() - interval '1 minute' where job_id = v_job.job_id;
  v_reclaimed := app.claim_next_job('worker-retry', array['recurring_billing'], 300);
  if v_reclaimed.job_id <> v_job.job_id then
    raise exception 'assertion failed: expected the job to become claimable once its backoff window passed, got %', v_reclaimed;
  end if;

  -- Drive to dead_letter (max_attempts=5, already at attempts=1 after the first
  -- failure above) and confirm next_attempt_at/lease are cleared, not scheduled.
  -- record_job_failure requires no active claim between calls (matches PLT-131's own
  -- existing test pattern for this function).
  perform app.record_job_failure(v_job.job_id, 'still failing', '00000000-0000-0000-0000-000000004001', 'requester');
  perform app.record_job_failure(v_job.job_id, 'still failing', '00000000-0000-0000-0000-000000004001', 'requester');
  perform app.record_job_failure(v_job.job_id, 'still failing', '00000000-0000-0000-0000-000000004001', 'requester');
  v_after_failure := app.record_job_failure(v_job.job_id, 'final failure', '00000000-0000-0000-0000-000000004001', 'requester');
  if v_after_failure.status <> 'dead_letter' or v_after_failure.next_attempt_at is not null or v_after_failure.locked_by is not null or v_after_failure.locked_until is not null then
    raise exception 'assertion failed: expected dead_letter to clear next_attempt_at/lease entirely, got %', v_after_failure;
  end if;
end;
$$;

\echo '>> app.requeue_dead_letter_job (extended): clears next_attempt_at so a requeued job is immediately claimable'
do $$
declare
  v_tenant_id uuid;
  v_job app.jobs;
  v_claimed app.jobs;
  v_dead app.jobs;
  v_requeued app.jobs;
  v_reclaimed app.jobs;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmejob');
  v_job := app.enqueue_job(v_tenant_id, 'integration_sync', '{}'::jsonb, 0, 'idem-requeue-1', 1, '00000000-0000-0000-0000-000000004001', 'requester');
  v_claimed := app.claim_next_job('worker-requeue', array['integration_sync'], 300);
  v_dead := app.record_job_failure(v_claimed.job_id, 'fatal', '00000000-0000-0000-0000-000000004001', 'requester');
  if v_dead.status <> 'dead_letter' then
    raise exception 'assertion failed: expected max_attempts=1 to reach dead_letter on the first failure, got %', v_dead;
  end if;

  v_requeued := app.requeue_dead_letter_job(v_job.job_id, '00000000-0000-0000-0000-000000004004', 'tenant admin');
  if v_requeued.next_attempt_at is not null or v_requeued.status <> 'pending' then
    raise exception 'assertion failed: expected requeue to clear next_attempt_at and reset to pending, got %', v_requeued;
  end if;

  v_reclaimed := app.claim_next_job('worker-after-requeue', array['integration_sync'], 300);
  if v_reclaimed.job_id <> v_job.job_id then
    raise exception 'assertion failed: expected the requeued job to be immediately claimable, got %', v_reclaimed;
  end if;
end;
$$;

\echo '>> app.acknowledge_job_cancellation (extended): releases the worker lease on cancellation'
do $$
declare
  v_tenant_id uuid;
  v_job app.jobs;
  v_claimed app.jobs;
  v_cancelling app.jobs;
  v_acked app.jobs;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmejob');
  -- priority=100: guarantees this job is claimed before the still-pending, lower-
  -- priority (5) leftover 'notification_batch' job the earlier app.enqueue_job
  -- scenario group deliberately left unclaimed (created only to prove idempotency).
  v_job := app.enqueue_job(v_tenant_id, 'notification_batch', '{}'::jsonb, 100, 'idem-cancel-lease-1', 3, '00000000-0000-0000-0000-000000004001', 'requester');
  v_claimed := app.claim_next_job('worker-cancel', array['notification_batch'], 300);
  if v_claimed.job_id <> v_job.job_id then
    raise exception 'assertion failed: expected to claim the just-enqueued highest-priority job, got %', v_claimed;
  end if;
  v_cancelling := app.cancel_import_export_job(v_job.job_id, 'no longer needed', '00000000-0000-0000-0000-000000004001', 'requester');
  if v_cancelling.status <> 'cancelling' then
    raise exception 'assertion failed: expected an in_progress job to move to cancelling, got %', v_cancelling;
  end if;

  v_acked := app.acknowledge_job_cancellation(v_job.job_id, '00000000-0000-0000-0000-000000004001', 'requester');
  if v_acked.status <> 'cancelled' or v_acked.locked_by is not null or v_acked.locked_until is not null then
    raise exception 'assertion failed: expected acknowledge_job_cancellation to release the lease, got %', v_acked;
  end if;
end;
$$;

\echo '>> app.append_event_log / app.dispatch_event_as_job / app.mark_event_dispatch_failed: validation, the outbox drain creates a real linked job, idempotent re-dispatch, invalid job_type, and failure recording'
do $$
declare
  v_tenant_id uuid;
  v_event app.event_logs;
  v_event2 app.event_logs;
  v_dispatched_job app.jobs;
  v_redispatched_job app.jobs;
  v_failed_event app.event_logs;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmejob');

  begin
    perform app.append_event_log(v_tenant_id, '', 'shipment', gen_random_uuid(), '{}'::jsonb, '00000000-0000-0000-0000-000000004001', 'requester');
    raise exception 'assertion failed: expected event_missing_type for an empty event_type';
  exception
    when check_violation then
      if sqlerrm !~ 'event_missing_type' then raise; end if;
  end;

  begin
    perform app.append_event_log(v_tenant_id, 'shipment.dispatched', '', gen_random_uuid(), '{}'::jsonb, '00000000-0000-0000-0000-000000004001', 'requester');
    raise exception 'assertion failed: expected event_missing_resource_type for an empty resource_type';
  exception
    when check_violation then
      if sqlerrm !~ 'event_missing_resource_type' then raise; end if;
  end;

  v_event := app.append_event_log(v_tenant_id, 'shipment.dispatched', 'shipment', gen_random_uuid(), jsonb_build_object('carrier', 'DHL'), '00000000-0000-0000-0000-000000004001', 'requester');
  if v_event.dispatch_status <> 'pending' or v_event.related_job_id is not null then
    raise exception 'assertion failed: unexpected initial event state %', v_event;
  end if;

  begin
    perform app.dispatch_event_as_job(v_event.id, 'not_a_real_type', 0, null, 3, 'outbox-drain');
    raise exception 'assertion failed: expected event_invalid_job_type';
  exception
    when check_violation then
      if sqlerrm !~ 'event_invalid_job_type' then raise; end if;
  end;

  v_dispatched_job := app.dispatch_event_as_job(v_event.id, 'webhook_retry', 0, null, 3, 'outbox-drain');
  if v_dispatched_job.job_type <> 'webhook_retry' or v_dispatched_job.requested_by_auth_user_id is not null or v_dispatched_job.tenant_id <> v_tenant_id then
    raise exception 'assertion failed: unexpected dispatched job state % (system-dispatched jobs must have a null requester)', v_dispatched_job;
  end if;

  select * into v_event2 from app.event_logs where id = v_event.id;
  if v_event2.dispatch_status <> 'dispatched' or v_event2.related_job_id <> v_dispatched_job.job_id then
    raise exception 'assertion failed: expected the event to be marked dispatched and linked to the new job, got %', v_event2;
  end if;

  -- Idempotent re-dispatch: returns the same job, never a second one.
  v_redispatched_job := app.dispatch_event_as_job(v_event.id, 'webhook_retry', 0, null, 3, 'outbox-drain');
  if v_redispatched_job.job_id <> v_dispatched_job.job_id then
    raise exception 'assertion failed: expected re-dispatching an already-dispatched event to return the same job, not create a new one';
  end if;

  v_event := app.append_event_log(v_tenant_id, 'invoice.overdue', 'invoice', gen_random_uuid(), '{}'::jsonb, '00000000-0000-0000-0000-000000004001', 'requester');
  v_failed_event := app.mark_event_dispatch_failed(v_event.id, 'downstream unavailable', '00000000-0000-0000-0000-000000004001', 'requester');
  if v_failed_event.dispatch_status <> 'failed' or v_failed_event.error <> 'downstream unavailable' then
    raise exception 'assertion failed: unexpected failed-dispatch event state %', v_failed_event;
  end if;
end;
$$;

\echo '>> RLS: a null-requester (system-dispatched) job is visible only to Supreme/support authority, never to an arbitrary tenant member (the requested_by_auth_user_id = auth.uid() branch never matches null)'
do $$
declare
  v_visible_count integer;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000004002", "role": "authenticated"}';
  select count(*) into v_visible_count from app.jobs where job_type = 'webhook_retry' and requested_by_auth_user_id is null;
  if v_visible_count <> 0 then raise exception 'assertion failed: expected a mere teammate to be denied visibility of a system-dispatched (null-requester) job via RLS'; end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000004004", "role": "authenticated"}';
  select count(*) into v_visible_count from app.jobs where job_type = 'webhook_retry' and requested_by_auth_user_id is null;
  if v_visible_count <> 1 then raise exception 'assertion failed: expected the tenant_admin (support authority) to see the system-dispatched job via RLS'; end if;
  reset role;
end;
$$;

\echo '>> schema-privilege defense in depth: authenticated has no grant at all on app.event_logs'
do $$
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000004001", "role": "authenticated"}';
  begin
    perform 1 from app.event_logs limit 1;
    raise exception 'assertion failed: authenticated must be denied SELECT on app.event_logs entirely, but the query succeeded';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    insert into app.event_logs (tenant_id, event_type, resource_type) values (gen_random_uuid(), 'x', 'y');
    raise exception 'assertion failed: authenticated must be denied INSERT on app.event_logs, but it succeeded';
  exception
    when insufficient_privilege then
      null;
  end;
  reset role;
end;
$$;

\echo '>> PLT-132 (Background Job Framework) test suite passed'
