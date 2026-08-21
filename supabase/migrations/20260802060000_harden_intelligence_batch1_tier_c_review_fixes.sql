-- Phase 9 Batch 1 (IAE-002..006, Prompts 330-334) Tier C fix pass, per
-- AGENTS.md's batched-review cadence. Four parallel adversarial lenses
-- (spec-compliance; security/RLS/tenant, live-tested; correctness/
-- concurrency, live-tested; cross-prompt integration) reviewed the already-
-- committed batch; this migration is the fix pass for every confirmed
-- finding, plus the mandatory propagation sweep across the other 4
-- capabilities in the same batch for each pattern found. Bounded defect
-- repair, not new capability -- no already-applied migration's own PAST
-- statements are edited (`create or replace function`/`alter table ...
-- add column` only), no gate weakened, no test disabled.
--
-- ===========================================================================
-- Findings fixed, by capability
-- ===========================================================================
--
-- IAE-006 (Scheduled Reports):
--
-- 1. (Critical, security-rls-tenant) app.run_scheduled_report resolved the
--    notification config_version via an UNSCOPED join (no tenant_id/scope
--    filter, no ORDER BY, no LIMIT) -- live-reproduced: an ordinary
--    tenant_admin in ANY tenant could publish a tenant-scoped override for
--    the shared config_type_code 'notification:scheduled_report_ready'
--    (using already-shipped, generic Configuration Engine RPCs) and have it
--    win for every OTHER tenant's own scheduled-report notifications,
--    system-wide, purely by UUID-sort chance. Fixed by replacing the
--    hand-rolled lookup with the already-existing, correctly tenant-scoped
--    6-level resolver, app.resolve_config (PLT-121,
--    20260717130000_create_configuration_engine.sql:656) -- the exact
--    reuse-not-duplicate discipline this migration's own header already
--    claims to follow for app.jobs/app.queue_notification.
-- 2. (High, spec-compliance) app.run_scheduled_report was not idempotent
--    PER DUE OCCURRENCE: only the app.jobs enqueue was deduplicated (via
--    enqueue_job's own idempotency key) -- the scheduled_report_runs
--    bookkeeping row and every recipient notification dedupe key were keyed
--    off a freshly-generated v_run.id on EVERY call, so a re-triggered run
--    for the SAME occurrence created a duplicate run-history row and sent
--    real duplicate notifications. Fixed with an occurrence-scoped upsert
--    (new occurrence_at column, unique on (scheduled_report_id,
--    occurrence_at)) for the run row, and a notification dedupe key derived
--    from (schedule_id, occurrence timestamp, recipient_id) instead of the
--    ephemeral v_run.id.
-- 3. (High, correctness-concurrency) Two genuinely concurrent calls each
--    passed the row's own `for update` lock sequentially and each computed a
--    DIFFERENT occurrence, because the second call only read next_run_at
--    after the first had already advanced it -- live-reproduced with two
--    parallel psql sessions: two distinct occurrences got processed
--    (double notification, next_run_at skipped a real due date). Fixed by
--    capturing the occurrence THIS caller intends to trigger via an
--    UNLOCKED read before requesting the row lock; if the locked re-read
--    shows next_run_at already moved past that value, this call is stale
--    for an occurrence a concurrent winner already handled -- it returns
--    that winner's own run instead of silently processing a second,
--    not-yet-actually-due occurrence.
-- 4. (Medium, security-rls-tenant, propagation) app.add_scheduled_report_
--    recipient and app.run_scheduled_report's own live reauthorization loop
--    both used a plain has_active_tenant_membership check to decide whether
--    a recipient is a valid, addressable internal tenant member -- but per
--    this SAME batch's own established finding, a customer_user-layer
--    (portal) principal ALSO satisfies has_active_tenant_membership. Without
--    excluding that layer, a portal account could be added as (or remain) a
--    recipient of an internal scheduled report, directly contradicting this
--    migration's own "recipients are internal tenant members only" design
--    decision (Prompt 334 §24). Found via the mandatory propagation sweep
--    for the customer_user-layer-exclusion pattern the lenses flagged
--    elsewhere in this batch (IAE-004/IAE-005) -- not itself a lens finding.
-- 5. (Medium, security-rls-tenant) app.set_scheduled_report_status, app.add_
--    scheduled_report_recipient, app.remove_scheduled_report_recipient and
--    app.run_scheduled_report all looked up their target row by id with no
--    tenant filter, then raised insufficient_authority embedding the row's
--    real tenant_id for a caller with no relationship to that tenant at all
--    -- a distinguishable oracle from the genuinely-missing-id not_found
--    error (the exact C-05/PRC-269 class IAE-002's own migration named and
--    fixed in cancel_report_run, but did not apply to these 4 sibling
--    functions). Fixed by folding the cross-tenant case into the SAME
--    not_found error the genuinely-missing-id case already raises, mirroring
--    cancel_report_run's own established shape exactly.
-- 6. (Medium, cross-prompt-integration) app.run_scheduled_report never wrote
--    an app.report_runs row, so every scheduled execution was structurally
--    invisible to IAE-002's own Report Library and IAE-005's own
--    mv_report_usage_daily analytics aggregate, both of which read
--    exclusively from app.report_runs. Fixed by inserting a linked
--    app.report_runs row (idempotent on job_id, never a second bookkeeping
--    row for a re-triggered/deduped occurrence) alongside the existing
--    app.jobs/app.scheduled_report_runs linkage.
--
-- IAE-003 (Dashboard Builder):
--
-- 7. (Medium, security-rls-tenant, same C-05 pattern as finding 5) app.add_
--    dashboard_widget, app.remove_dashboard_widget, app.publish_tenant_
--    dashboard_version and app.rollback_tenant_dashboard all carried the
--    identical by-id-lookup oracle -- fixed identically.
--
-- IAE-004 (Saved View and Configurable Report):
--
-- 8. (High, spec-compliance) app.list_saved_report_views' own sharing_scope
--    = 'tenant' branch had no app.actor_holds_customer_user_layer exclusion,
--    unlike this table's own RLS policy on the very same migration --
--    live-reproduced: a customer_user-layer principal with active tenant
--    membership received every tenant-shared saved view's own configuration
--    (report_type_code, filters, columns) via this RPC, which the table's
--    own RLS policy would correctly deny on a direct SELECT. Fixed by
--    mirroring the RLS policy's own already-correct predicate.
-- 9. (High, spec-compliance, propagation) app.create_saved_report_view's own
--    private-view branch made the IDENTICAL mistake -- its own doc comment
--    already claimed "a private view requires only active, non-customer_
--    user-layer tenant membership", but the code never checked it. Found via
--    the mandatory propagation sweep for the same pattern within this same
--    migration file -- not itself a lens finding. Fixed to match its own
--    documented contract.
--
-- IAE-005 (Analytics and Materialized Views):
--
-- 10. (High, security-rls-tenant) app.get_report_usage_daily -- the SOLE
--     tenant-isolation mechanism for app.mv_report_usage_daily, since
--     Postgres has no RLS on a materialized view -- omitted the same
--     customer_user-layer exclusion this batch established as mandatory
--     convention. Live-reproduced and fixed identically to findings 8/9.
-- 11. (Medium, correctness-concurrency) app.refresh_analytics_view's
--     reconciliation check compared row_count_after (captured immediately
--     after REFRESH ... CONCURRENTLY) against a live count computed by a
--     LATER, independently-committed SELECT -- any legitimate report run
--     recorded by ANY tenant in the gap between the two statements produced
--     a false reconciled=false, live-reproduced. Fixed by capturing a
--     boundary timestamp immediately before the REFRESH statement and
--     bounding the live reconciliation count to rows committed before it.
--
-- IAE-002 (Reporting Engine):
--
-- 12. (Low, cross-prompt-integration) app.cancel_report_run's override-cancel
--     authority (for a caller who is not the run's own requester) was
--     hardcoded to COM:Export regardless of the report's own domain,
--     inconsistent with this batch's own new cross-domain REP:Configure/
--     REP:Export convention. Fixed by ALSO accepting REP:Export (never
--     replacing COM:Export outright, which would strip override-cancel from
--     every already-provisioned COM:Export holder, since no tenant role has
--     ever been granted REP:Export/Configure before this batch).
--
-- Findings NOT changed here (false positive, or deliberately handled outside
-- SQL -- see each capability's own build log "Tier C fix pass" section for
-- the full explanation):
--   * app.enqueue_report_export/app.record_report_run's own lack of a
--     customer_user-layer exclusion is a PRE-EXISTING COM-159 (Phase 2)
--     condition, not introduced or substantively touched by this batch
--     (re-created via `create or replace` with byte-identical authority
--     logic) -- out of this batch's own Tier C scope, not silently ignored.
--   * app.queue_notification (PLT-127) validating the passed config_version's
--     own scope against p_tenant_id, offered as defense-in-depth alongside
--     finding 1 -- PLT-127 predates this batch and is not one of its 5
--     migrations; finding 1's own root-cause fix (app.resolve_config) fully
--     closes the exploitable path within this batch's own code.
--   * Saved view -> scheduled report integration, and saved-view columns/
--     sort/grouping not threaded through export -- both disclosed, not
--     fixed, per each finding's own offered alternative; see IAE-332.md/
--     IAE-334.md's own new Tier C sections.
--   * mv_report_usage_daily's failed_count conflating real failures with
--     requester-cancelled runs -- relabelled at the presentation layer only
--     (UI column header + contract doc comment), not a schema change; see
--     app/(tenant)/[tenantSlug]/analytics/page.tsx and
--     server/contracts/analytics/analytics.ts.
--   * Report Library Cancel button reachable only via the requester-self
--     path -- error copy corrected to not claim a narrower rule than the RPC
--     enforces; see app/(tenant)/[tenantSlug]/reports/actions.ts. Extending
--     the UI to surface the COM:Export/REP:Export/Supreme-Admin override path
--     is out of this fix pass's own minimal-change scope, disclosed instead.
--
-- Live-verified against a real disposable Postgres 16 database
-- (cargogrid_tierc_fix) before being considered fixed -- see each affected
-- capability's own build log "Tier C fix pass" section for the specific
-- reproduction/regression evidence.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- IAE-006 schema: occurrence-scoped run bookkeeping (findings 2, 3)
-- ---------------------------------------------------------------------------

alter table app.scheduled_report_runs add column occurrence_at timestamptz;

-- Backfill any pre-existing row (none expected in a fresh environment, but
-- additive migrations never assume an empty table) from its own started_at
-- -- the closest available approximation for a row that predates this column.
update app.scheduled_report_runs set occurrence_at = started_at where occurrence_at is null;

alter table app.scheduled_report_runs alter column occurrence_at set not null;

alter table app.scheduled_report_runs
  add constraint scheduled_report_runs_occurrence_unique unique (scheduled_report_id, occurrence_at);

comment on column app.scheduled_report_runs.occurrence_at is
  'Tier C fix: the due occurrence (scheduled_reports.next_run_at at trigger time) this run represents. Unique per (scheduled_report_id, occurrence_at) -- a re-triggered call for the SAME occurrence reuses this row via app.run_scheduled_report''s own on-conflict upsert, instead of generating a fresh row and a fresh notification-dedupe key every call.';

-- ---------------------------------------------------------------------------
-- IAE-006: app.run_scheduled_report (findings 1, 2, 3, 4, 5, 6)
-- ---------------------------------------------------------------------------

create or replace function app.run_scheduled_report(
  p_scheduled_report_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.scheduled_report_runs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_schedule app.scheduled_reports;
  v_decision app.rbac_decision;
  v_job app.jobs;
  v_run app.scheduled_report_runs;
  v_recipient record;
  v_total integer := 0;
  v_reauthorized integer := 0;
  v_denied integer := 0;
  v_idempotency_key text;
  v_config_version_id uuid;
  v_intended_occurrence timestamptz;
  v_report_type_version_id uuid;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- Tier C fix (finding 3, correctness-concurrency): capture the occurrence
  -- THIS caller intends to trigger via an UNLOCKED read, BEFORE requesting
  -- the row lock below (and therefore before any lock-induced wait). See the
  -- staleness check further down for why this closes the concurrent-double-
  -- trigger race a live two-session test reproduced.
  select next_run_at into v_intended_occurrence from app.scheduled_reports where id = p_scheduled_report_id;

  select * into v_schedule from app.scheduled_reports where id = p_scheduled_report_id for update;
  if not found then
    raise exception 'scheduled_report_not_found: %', p_scheduled_report_id using errcode = 'no_data_found';
  end if;
  if v_schedule.status <> 'active' then
    raise exception 'scheduled_report_not_active: % is %, only an active schedule may run', p_scheduled_report_id, v_schedule.status using errcode = 'check_violation';
  end if;

  -- Tier C fix (finding 5, C-05 discipline, mirrors app.cancel_report_run's
  -- own established precedent): a caller with zero standing in this
  -- schedule's own tenant gets the identical scheduled_report_not_found a
  -- genuinely missing id would produce, never insufficient_authority, which
  -- would disclose the row's own real tenant_id to a totally unrelated actor.
  if not (app.has_active_tenant_membership(v_schedule.tenant_id, p_actor_auth_user_id) or app.is_supreme_admin(p_actor_auth_user_id)) then
    raise exception 'scheduled_report_not_found: %', p_scheduled_report_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_schedule.tenant_id, 'REP', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks REP:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_schedule.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Tier C fix (finding 3, correctness-concurrency): if a concurrent call,
  -- serialized ahead of this one by the FOR UPDATE lock above, already
  -- advanced next_run_at past the occurrence THIS call observed before
  -- waiting for the lock, this call is stale for an occurrence a concurrent
  -- winner already handled -- return that winner's own run instead of
  -- silently processing a SECOND, not-yet-actually-due occurrence and
  -- double-advancing the schedule (live-reproduced: two near-simultaneous
  -- "Run Now" clicks each getting to "own" a distinct occurrence, silently
  -- skipping the real next due date).
  if v_intended_occurrence is not null and v_schedule.next_run_at <> v_intended_occurrence then
    select * into v_run from app.scheduled_report_runs
    where scheduled_report_id = p_scheduled_report_id and occurrence_at = v_intended_occurrence;
    if found then
      return v_run;
    end if;
    raise exception 'scheduled_report_occurrence_already_advanced: % was concurrently advanced past the occurrence this request observed (%) -- retry to trigger the current occurrence', p_scheduled_report_id, v_intended_occurrence
      using errcode = 'serialization_failure';
  end if;

  -- Idempotency key ties the enqueued job to THIS due occurrence -- a
  -- re-triggered call for the same next_run_at can never double-enqueue.
  v_idempotency_key := 'scheduled-report-' || p_scheduled_report_id || '-' || to_char(v_schedule.next_run_at, 'YYYYMMDDHH24MI');

  v_job := app.enqueue_job(
    v_schedule.tenant_id, 'report_generation',
    jsonb_build_object('scheduled_report_id', p_scheduled_report_id, 'report_type_code', v_schedule.report_type_code, 'filters', v_schedule.filters),
    0, v_idempotency_key, 3, p_actor_auth_user_id, p_actor_label
  );

  select id into v_report_type_version_id from app.report_type_versions
  where report_type_code = v_schedule.report_type_code order by version_number desc limit 1;

  -- Tier C fix (finding 6, cross-prompt-integration): link this execution
  -- into the SAME app.report_runs evidence trail IAE-002's own Report
  -- Library and IAE-005's own mv_report_usage_daily already read
  -- exclusively -- without this, a scheduled execution was structurally
  -- invisible to both. Kept idempotent on job_id -- never a second
  -- bookkeeping row for the same underlying job on a re-triggered/deduped
  -- occurrence.
  if not exists (select 1 from app.report_runs where job_id = v_job.job_id) then
    insert into app.report_runs (
      tenant_id, report_type_code, run_type, status, parameters, job_id,
      report_type_version_id, requested_by_auth_user_id, created_by
    ) values (
      v_schedule.tenant_id, v_schedule.report_type_code, 'export', 'queued', v_schedule.filters, v_job.job_id,
      v_report_type_version_id, p_actor_auth_user_id, p_actor_label
    );
  end if;

  -- Tier C fix (finding 2, spec-compliance): occurrence-scoped upsert -- a
  -- re-triggered call for the SAME due occurrence reuses the existing run
  -- row (same id) rather than generating a fresh one every call, mirroring
  -- app.add_scheduled_report_recipient's own established
  -- "on conflict ... do update set <pk column> = excluded.<pk column>"
  -- self-referential no-op idiom in this same file.
  insert into app.scheduled_report_runs (scheduled_report_id, job_id, occurrence_at, artifact_expires_at, triggered_by_auth_user_id, triggered_by_label)
  values (p_scheduled_report_id, v_job.job_id, v_schedule.next_run_at, now() + interval '7 days', p_actor_auth_user_id, p_actor_label)
  on conflict (scheduled_report_id, occurrence_at) do update set scheduled_report_id = excluded.scheduled_report_id
  returning * into v_run;

  -- Tier C fix (finding 1, Critical, security-rls-tenant): resolve via the
  -- already-existing, correctly tenant-scoped 6-level config resolver
  -- (PLT-121) instead of an unscoped join that could non-deterministically
  -- pick ANY tenant's own published config_version for this shared
  -- config_type_code.
  select resolved_version_id into v_config_version_id
  from app.resolve_config('notification:scheduled_report_ready', v_schedule.tenant_id);

  -- Recipient reauthorization AT RUN TIME (Prompt 334 §24) -- never deferred
  -- to add-time membership alone.
  for v_recipient in select * from app.scheduled_report_recipients where scheduled_report_id = p_scheduled_report_id loop
    v_total := v_total + 1;
    -- Tier C fix (finding 4, security-rls-tenant, propagation): a
    -- customer_user-layer (portal) principal also satisfies plain
    -- has_active_tenant_membership -- without this exclusion, a portal
    -- account could remain a "reauthorized" recipient of an internal
    -- scheduled report, contradicting this migration's own "recipients are
    -- internal tenant members only" design decision.
    if app.has_active_tenant_membership(v_schedule.tenant_id, v_recipient.recipient_auth_user_id)
      and not app.actor_holds_customer_user_layer(v_schedule.tenant_id, v_recipient.recipient_auth_user_id)
    then
      v_reauthorized := v_reauthorized + 1;
      if v_config_version_id is not null then
        perform app.queue_notification(
          v_config_version_id, v_schedule.tenant_id, 'scheduled_report_ready', v_recipient.recipient_auth_user_id,
          'in_app', 'en', jsonb_build_object('scheduledReportName', v_schedule.name, 'runId', v_run.id),
          -- Tier C fix (finding 2, spec-compliance): the dedupe key is now
          -- derived from the (schedule, occurrence, recipient) tuple, not
          -- the ephemeral v_run.id -- a re-triggered call for the SAME due
          -- occurrence now computes the IDENTICAL key every time, so
          -- app.queue_notification's own exact-key dedupe actually prevents
          -- the second real notification it was always documented to
          -- prevent.
          'scheduled-report-run-' || p_scheduled_report_id || '-' || to_char(v_schedule.next_run_at, 'YYYYMMDDHH24MI') || '-' || v_recipient.recipient_auth_user_id,
          p_actor_auth_user_id, p_actor_label
        );
      end if;
    else
      v_denied := v_denied + 1;
    end if;
  end loop;

  update app.scheduled_report_runs
  set recipients_total = v_total, recipients_reauthorized = v_reauthorized, recipients_denied = v_denied
  where id = v_run.id
  returning * into v_run;

  update app.scheduled_reports
  set last_run_at = now(), next_run_at = app.compute_scheduled_report_next_run(cron_minute, cron_hour, cron_day_of_month, cron_day_of_week, timezone, v_schedule.next_run_at)
  where id = p_scheduled_report_id;

  perform app.capture_audit_event(
    v_schedule.tenant_id, p_actor_auth_user_id, p_actor_label, 'run_scheduled_report',
    'app.scheduled_report_runs', v_run.id, 'success', null, null, to_jsonb(v_run)
  );

  return v_run;
end;
$$;

comment on function app.run_scheduled_report is
  'IAE-006: the real execution entrypoint -- both a manual "run now" and what a future scheduler would call at next_run_at (none exists in this environment, the same disclosed condition every job type here carries). Reauthorizes every recipient live (excluding a customer_user-layer principal even if somehow added as a recipient, Tier C fix); enqueues via the shared app.jobs queue with an occurrence-scoped idempotency key; advances next_run_at forward from the JUST-triggered occurrence, never from now(). Tier C fixes: resolves the notification config_version via the tenant-scoped app.resolve_config (was an unscoped, cross-tenant-leaking join); the run row and notification dedupe key are occurrence-scoped (an occurrence-unique upsert), so a re-triggered call for the SAME occurrence never re-notifies or duplicates run history; a genuinely concurrent second call detects it is stale for an already-superseded occurrence (an unlocked pre-read compared against the post-lock value) and returns the concurrent winner''s own run instead of double-advancing; also links a matching app.report_runs row (idempotent on job_id) so scheduled executions are no longer invisible to the Report Library/analytics; the not-found path is C-05 folded against a cross-tenant caller.';

-- ---------------------------------------------------------------------------
-- IAE-006: app.set_scheduled_report_status (finding 5)
-- ---------------------------------------------------------------------------

create or replace function app.set_scheduled_report_status(
  p_scheduled_report_id uuid,
  p_status text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.scheduled_reports
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_row app.scheduled_reports;
  v_decision app.rbac_decision;
  v_updated app.scheduled_reports;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_row from app.scheduled_reports where id = p_scheduled_report_id for update;
  if not found then
    raise exception 'scheduled_report_not_found: %', p_scheduled_report_id using errcode = 'no_data_found';
  end if;

  -- Tier C fix (finding 5, C-05 discipline): a caller with zero standing in
  -- this schedule's own tenant gets the identical scheduled_report_not_found
  -- a genuinely missing id would produce, never insufficient_authority.
  if not (app.has_active_tenant_membership(v_row.tenant_id, p_actor_auth_user_id) or app.is_supreme_admin(p_actor_auth_user_id)) then
    raise exception 'scheduled_report_not_found: %', p_scheduled_report_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_row.tenant_id, 'REP', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks REP:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_row.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not (p_status = any (array['active', 'paused', 'archived'])) then
    raise exception 'scheduled_report_invalid_status: %', p_status using errcode = 'check_violation';
  end if;

  update app.scheduled_reports set status = p_status where id = p_scheduled_report_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_row.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_scheduled_report_status',
    'app.scheduled_reports', v_row.id, 'success', null, jsonb_build_object('status', v_row.status), jsonb_build_object('status', v_updated.status)
  );

  return v_updated;
end;
$$;

comment on function app.set_scheduled_report_status is
  'IAE-006: pause/resume/archive (Prompt 334''s own "unsubscribe/suspend controls"). Pausing never deletes next_run_at -- resuming continues the SAME schedule, never recomputing from now(). Tier C fix: a cross-tenant caller now gets the same scheduled_report_not_found a missing id would produce (C-05), never a tenant-id-disclosing insufficient_authority.';

-- ---------------------------------------------------------------------------
-- IAE-006: app.add_scheduled_report_recipient (findings 4, 5)
-- ---------------------------------------------------------------------------

create or replace function app.add_scheduled_report_recipient(
  p_scheduled_report_id uuid,
  p_recipient_auth_user_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.scheduled_report_recipients
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_schedule app.scheduled_reports;
  v_decision app.rbac_decision;
  v_row app.scheduled_report_recipients;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_schedule from app.scheduled_reports where id = p_scheduled_report_id;
  if not found then
    raise exception 'scheduled_report_not_found: %', p_scheduled_report_id using errcode = 'no_data_found';
  end if;

  -- Tier C fix (finding 5, C-05 discipline): a caller with zero standing in
  -- this schedule's own tenant gets the identical scheduled_report_not_found
  -- a genuinely missing id would produce, never insufficient_authority.
  if not (app.has_active_tenant_membership(v_schedule.tenant_id, p_actor_auth_user_id) or app.is_supreme_admin(p_actor_auth_user_id)) then
    raise exception 'scheduled_report_not_found: %', p_scheduled_report_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_schedule.tenant_id, 'REP', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks REP:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_schedule.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Tier C fix (finding 4, security-rls-tenant, propagation): a
  -- customer_user-layer (portal) principal also satisfies plain
  -- has_active_tenant_membership -- without this exclusion, a portal
  -- account could be ADDED as a recipient of an internal scheduled report,
  -- contradicting this migration's own "recipients are internal tenant
  -- members only" design decision (Prompt 334 §24).
  if not app.has_active_tenant_membership(v_schedule.tenant_id, p_recipient_auth_user_id)
    or app.actor_holds_customer_user_layer(v_schedule.tenant_id, p_recipient_auth_user_id)
  then
    raise exception 'scheduled_report_recipient_not_member: % has no active, non-customer_user-layer membership in tenant %', p_recipient_auth_user_id, v_schedule.tenant_id
      using errcode = 'check_violation';
  end if;

  insert into app.scheduled_report_recipients (scheduled_report_id, recipient_auth_user_id, added_by_auth_user_id)
  values (p_scheduled_report_id, p_recipient_auth_user_id, p_actor_auth_user_id)
  on conflict (scheduled_report_id, recipient_auth_user_id) do update set scheduled_report_id = excluded.scheduled_report_id
  returning * into v_row;

  perform app.capture_audit_event(
    v_schedule.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_scheduled_report_recipient',
    'app.scheduled_report_recipients', v_row.id, 'success', null, null, to_jsonb(v_row)
  );

  return v_row;
end;
$$;

comment on function app.add_scheduled_report_recipient is
  'IAE-006: REP:Configure-gated. Rejects a recipient with no active, non-customer_user-layer membership in the schedule''s own tenant (Tier C fix: the customer_user-layer exclusion was missing) -- re-validated again, live, at every run.';

-- ---------------------------------------------------------------------------
-- IAE-006: app.remove_scheduled_report_recipient (finding 5)
-- ---------------------------------------------------------------------------

create or replace function app.remove_scheduled_report_recipient(
  p_recipient_row_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns void
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_recipient app.scheduled_report_recipients;
  v_schedule app.scheduled_reports;
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_recipient from app.scheduled_report_recipients where id = p_recipient_row_id;
  if not found then
    raise exception 'scheduled_report_recipient_not_found: %', p_recipient_row_id using errcode = 'no_data_found';
  end if;

  select * into v_schedule from app.scheduled_reports where id = v_recipient.scheduled_report_id;

  -- Tier C fix (finding 5, C-05 discipline): a caller with zero standing in
  -- this recipient row's own tenant gets the identical scheduled_report_
  -- recipient_not_found a genuinely missing id would produce, never
  -- insufficient_authority.
  if not (app.has_active_tenant_membership(v_schedule.tenant_id, p_actor_auth_user_id) or app.is_supreme_admin(p_actor_auth_user_id)) then
    raise exception 'scheduled_report_recipient_not_found: %', p_recipient_row_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_schedule.tenant_id, 'REP', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks REP:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_schedule.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  delete from app.scheduled_report_recipients where id = p_recipient_row_id;

  perform app.capture_audit_event(
    v_schedule.tenant_id, p_actor_auth_user_id, p_actor_label, 'remove_scheduled_report_recipient',
    'app.scheduled_report_recipients', p_recipient_row_id, 'success', null, to_jsonb(v_recipient), null
  );
end;
$$;

comment on function app.remove_scheduled_report_recipient is
  'IAE-006: REP:Configure-gated. Tier C fix: a cross-tenant caller now gets the same scheduled_report_recipient_not_found a missing id would produce (C-05), never a tenant-id-disclosing insufficient_authority.';

-- ---------------------------------------------------------------------------
-- IAE-003: app.add_dashboard_widget (finding 7)
-- ---------------------------------------------------------------------------

create or replace function app.add_dashboard_widget(
  p_dashboard_version_id uuid,
  p_report_type_code text,
  p_title text,
  p_position jsonb,
  p_parameter_overrides jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.tenant_dashboard_widgets
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_version app.tenant_dashboard_versions;
  v_dashboard app.tenant_dashboards;
  v_type app.report_types;
  v_decision app.rbac_decision;
  v_widget app.tenant_dashboard_widgets;
  v_next_order integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_version from app.tenant_dashboard_versions where id = p_dashboard_version_id;
  if not found then
    raise exception 'dashboard_version_not_found: %', p_dashboard_version_id using errcode = 'no_data_found';
  end if;

  select * into v_dashboard from app.tenant_dashboards where id = v_version.dashboard_id;

  -- Tier C fix (finding 7, C-05 discipline, mirrors app.cancel_report_run's
  -- own established precedent): a caller with zero standing in this
  -- widget's own tenant gets the identical dashboard_version_not_found a
  -- genuinely missing id would produce, never insufficient_authority, which
  -- would disclose the row's own real tenant_id.
  if not (app.has_active_tenant_membership(v_dashboard.tenant_id, p_actor_auth_user_id) or app.is_supreme_admin(p_actor_auth_user_id)) then
    raise exception 'dashboard_version_not_found: %', p_dashboard_version_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_dashboard.tenant_id, 'REP', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks REP:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_dashboard.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_version.status <> 'draft' then
    raise exception 'dashboard_version_not_editable: version % is % (only a draft version accepts widget changes)', p_dashboard_version_id, v_version.status
      using errcode = 'check_violation';
  end if;

  select * into v_type from app.report_types where code = p_report_type_code;
  if not found then
    raise exception 'report_type_unknown: %', p_report_type_code using errcode = 'no_data_found';
  end if;
  if v_type.status <> 'active' then
    raise exception 'report_type_retired: % is retired and cannot be added to a dashboard', p_report_type_code using errcode = 'check_violation';
  end if;

  if not app.validate_report_parameters(v_type.parameter_schema, coalesce(p_parameter_overrides, '{}'::jsonb)) then
    raise exception 'widget_unsafe_parameters: parameter_overrides failed structural or schema validation'
      using errcode = 'check_violation';
  end if;

  if p_title is null or length(trim(p_title)) = 0 then
    raise exception 'widget_title_required: title must not be empty' using errcode = 'check_violation';
  end if;

  select coalesce(max(display_order), -1) + 1 into v_next_order
  from app.tenant_dashboard_widgets where dashboard_version_id = p_dashboard_version_id;

  insert into app.tenant_dashboard_widgets (
    dashboard_version_id, report_type_code, title, position, parameter_overrides, display_order
  ) values (
    p_dashboard_version_id, p_report_type_code, p_title, coalesce(p_position, '{}'::jsonb), coalesce(p_parameter_overrides, '{}'::jsonb), v_next_order
  )
  returning * into v_widget;

  perform app.capture_audit_event(
    v_dashboard.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_dashboard_widget',
    'app.tenant_dashboard_widgets', v_widget.id, 'success', null, null,
    jsonb_build_object('dashboard_version_id', p_dashboard_version_id, 'report_type_code', p_report_type_code)
  );

  return v_widget;
end;
$$;

comment on function app.add_dashboard_widget is
  'IAE-003: REP:Configure-gated, draft-only. Rejects an unknown/retired report_type_code and validates parameter_overrides via app.validate_report_parameters (IAE-002, reused directly). Tier C fix: a cross-tenant caller now gets the same dashboard_version_not_found a missing id would produce (C-05), never a tenant-id-disclosing insufficient_authority.';

-- ---------------------------------------------------------------------------
-- IAE-003: app.remove_dashboard_widget (finding 7)
-- ---------------------------------------------------------------------------

create or replace function app.remove_dashboard_widget(
  p_widget_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns void
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_widget app.tenant_dashboard_widgets;
  v_version app.tenant_dashboard_versions;
  v_dashboard app.tenant_dashboards;
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_widget from app.tenant_dashboard_widgets where id = p_widget_id;
  if not found then
    raise exception 'dashboard_widget_not_found: %', p_widget_id using errcode = 'no_data_found';
  end if;

  select * into v_version from app.tenant_dashboard_versions where id = v_widget.dashboard_version_id;
  select * into v_dashboard from app.tenant_dashboards where id = v_version.dashboard_id;

  -- Tier C fix (finding 7, C-05 discipline): a caller with zero standing in
  -- this widget's own tenant gets the identical dashboard_widget_not_found a
  -- genuinely missing id would produce, never insufficient_authority.
  if not (app.has_active_tenant_membership(v_dashboard.tenant_id, p_actor_auth_user_id) or app.is_supreme_admin(p_actor_auth_user_id)) then
    raise exception 'dashboard_widget_not_found: %', p_widget_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_dashboard.tenant_id, 'REP', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks REP:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_dashboard.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_version.status <> 'draft' then
    raise exception 'dashboard_version_not_editable: version % is % (only a draft version accepts widget changes)', v_version.id, v_version.status
      using errcode = 'check_violation';
  end if;

  delete from app.tenant_dashboard_widgets where id = p_widget_id;

  perform app.capture_audit_event(
    v_dashboard.tenant_id, p_actor_auth_user_id, p_actor_label, 'remove_dashboard_widget',
    'app.tenant_dashboard_widgets', p_widget_id, 'success', null, null,
    jsonb_build_object('dashboard_version_id', v_widget.dashboard_version_id, 'report_type_code', v_widget.report_type_code)
  );
end;
$$;

comment on function app.remove_dashboard_widget is
  'IAE-003: REP:Configure-gated, draft-only, mirrors app.add_dashboard_widget''s own gate exactly. Tier C fix: a cross-tenant caller now gets the same dashboard_widget_not_found a missing id would produce (C-05), never a tenant-id-disclosing insufficient_authority.';

-- ---------------------------------------------------------------------------
-- IAE-003: app.publish_tenant_dashboard_version (finding 7)
-- ---------------------------------------------------------------------------

create or replace function app.publish_tenant_dashboard_version(
  p_dashboard_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.tenant_dashboard_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_dashboard app.tenant_dashboards;
  v_decision app.rbac_decision;
  v_draft app.tenant_dashboard_versions;
  v_next_version integer;
  v_new_draft app.tenant_dashboard_versions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_dashboard from app.tenant_dashboards where id = p_dashboard_id for update;
  if not found then
    raise exception 'dashboard_not_found: %', p_dashboard_id using errcode = 'no_data_found';
  end if;

  -- Tier C fix (finding 7, C-05 discipline): a caller with zero standing in
  -- this dashboard's own tenant gets the identical dashboard_not_found a
  -- genuinely missing id would produce, never insufficient_authority.
  if not (app.has_active_tenant_membership(v_dashboard.tenant_id, p_actor_auth_user_id) or app.is_supreme_admin(p_actor_auth_user_id)) then
    raise exception 'dashboard_not_found: %', p_dashboard_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_dashboard.tenant_id, 'REP', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks REP:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_dashboard.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_draft from app.tenant_dashboard_versions
  where dashboard_id = p_dashboard_id and status = 'draft'
  order by version_number desc limit 1;
  if not found then
    raise exception 'dashboard_no_draft_version: dashboard % has no draft version to publish', p_dashboard_id using errcode = 'no_data_found';
  end if;

  if not exists (select 1 from app.tenant_dashboard_widgets where dashboard_version_id = v_draft.id) then
    raise exception 'dashboard_empty_version: a version with zero widgets cannot be published' using errcode = 'check_violation';
  end if;

  update app.tenant_dashboard_versions
  set status = 'published', published_by_auth_user_id = p_actor_auth_user_id, published_by = p_actor_label, published_at = now()
  where id = v_draft.id;

  update app.tenant_dashboards
  set status = 'published', current_version_id = v_draft.id
  where id = p_dashboard_id;

  v_next_version := v_draft.version_number + 1;
  insert into app.tenant_dashboard_versions (dashboard_id, version_number, layout, status)
  values (p_dashboard_id, v_next_version, v_draft.layout, 'draft')
  returning * into v_new_draft;

  insert into app.tenant_dashboard_widgets (dashboard_version_id, report_type_code, title, position, parameter_overrides, display_order)
  select v_new_draft.id, report_type_code, title, position, parameter_overrides, display_order
  from app.tenant_dashboard_widgets
  where dashboard_version_id = v_draft.id;

  perform app.capture_audit_event(
    v_dashboard.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_tenant_dashboard_version',
    'app.tenant_dashboard_versions', v_draft.id, 'success', null, null,
    jsonb_build_object('dashboard_id', p_dashboard_id, 'version_number', v_draft.version_number)
  );

  select * into v_draft from app.tenant_dashboard_versions where id = v_draft.id;
  return v_draft;
end;
$$;

comment on function app.publish_tenant_dashboard_version is
  'IAE-003: REP:Configure-gated. Locks the dashboard row for update before deciding (C-04). Publishes the current draft (rejecting an empty one), points current_version_id at it, then opens a fresh draft version copying the just-published widgets. Tier C fix: a cross-tenant caller now gets the same dashboard_not_found a missing id would produce (C-05), never a tenant-id-disclosing insufficient_authority.';

-- ---------------------------------------------------------------------------
-- IAE-003: app.rollback_tenant_dashboard (finding 7)
-- ---------------------------------------------------------------------------

create or replace function app.rollback_tenant_dashboard(
  p_dashboard_id uuid,
  p_target_version_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.tenant_dashboards
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_dashboard app.tenant_dashboards;
  v_decision app.rbac_decision;
  v_target app.tenant_dashboard_versions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_dashboard from app.tenant_dashboards where id = p_dashboard_id for update;
  if not found then
    raise exception 'dashboard_not_found: %', p_dashboard_id using errcode = 'no_data_found';
  end if;

  -- Tier C fix (finding 7, C-05 discipline): a caller with zero standing in
  -- this dashboard's own tenant gets the identical dashboard_not_found a
  -- genuinely missing id would produce, never insufficient_authority.
  if not (app.has_active_tenant_membership(v_dashboard.tenant_id, p_actor_auth_user_id) or app.is_supreme_admin(p_actor_auth_user_id)) then
    raise exception 'dashboard_not_found: %', p_dashboard_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_dashboard.tenant_id, 'REP', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks REP:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_dashboard.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_target from app.tenant_dashboard_versions
  where id = p_target_version_id and dashboard_id = p_dashboard_id and status = 'published';
  if not found then
    raise exception 'dashboard_target_version_invalid: % is not a published version of dashboard %', p_target_version_id, p_dashboard_id
      using errcode = 'check_violation';
  end if;

  update app.tenant_dashboards set current_version_id = p_target_version_id where id = p_dashboard_id
  returning * into v_dashboard;

  perform app.capture_audit_event(
    v_dashboard.tenant_id, p_actor_auth_user_id, p_actor_label, 'rollback_tenant_dashboard',
    'app.tenant_dashboards', p_dashboard_id, 'success', null, null,
    jsonb_build_object('target_version_id', p_target_version_id, 'target_version_number', v_target.version_number)
  );

  return v_dashboard;
end;
$$;

comment on function app.rollback_tenant_dashboard is
  'IAE-003: REP:Configure-gated. Locks the dashboard row for update before deciding (C-04). Points current_version_id at an older PUBLISHED version only. Tier C fix: a cross-tenant caller now gets the same dashboard_not_found a missing id would produce (C-05), never a tenant-id-disclosing insufficient_authority.';

-- ---------------------------------------------------------------------------
-- IAE-004: app.create_saved_report_view (finding 9)
-- ---------------------------------------------------------------------------

create or replace function app.create_saved_report_view(
  p_tenant_id uuid,
  p_report_type_code text,
  p_name text,
  p_description text,
  p_columns jsonb,
  p_filters jsonb,
  p_sort jsonb,
  p_grouping jsonb,
  p_sharing_scope text,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.saved_report_views
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_type app.report_types;
  v_decision app.rbac_decision;
  v_sharing_scope text := coalesce(p_sharing_scope, 'private');
  v_columns jsonb := coalesce(p_columns, '[]'::jsonb);
  v_filters jsonb := coalesce(p_filters, '{}'::jsonb);
  v_sort jsonb := coalesce(p_sort, '{}'::jsonb);
  v_grouping jsonb := coalesce(p_grouping, '{}'::jsonb);
  v_version_id uuid;
  v_existing app.saved_report_views;
  v_view app.saved_report_views;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not (v_sharing_scope = any (array['private', 'tenant'])) then
    raise exception 'saved_view_invalid_sharing_scope: % is not private or tenant', v_sharing_scope using errcode = 'check_violation';
  end if;

  if v_sharing_scope = 'tenant' then
    v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'REP', 'Configure');
    if not v_decision.allowed then
      raise exception 'insufficient_authority: identity % lacks REP:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
        using errcode = 'insufficient_privilege';
    end if;
  else
    -- Tier C fix (finding 9, spec-compliance, propagation): this function's
    -- own comment already documented "a private view requires only active,
    -- non-customer_user-layer tenant membership" -- the code never actually
    -- checked the non-customer_user-layer half. Mirrors the identical
    -- exclusion this same migration's own RLS policy
    -- (saved_report_views_select_scoped) and app.list_saved_report_views
    -- (fixed alongside this) already apply.
    if not app.is_supreme_admin(p_actor_auth_user_id)
      and (not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) or app.actor_holds_customer_user_layer(p_tenant_id, p_actor_auth_user_id))
    then
      raise exception 'insufficient_authority: identity % has no active, non-customer_user-layer membership in tenant %', p_actor_auth_user_id, p_tenant_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  select * into v_type from app.report_types where code = p_report_type_code;
  if not found then
    raise exception 'report_type_unknown: %', p_report_type_code using errcode = 'no_data_found';
  end if;
  if v_type.status <> 'active' then
    raise exception 'report_type_retired: % is retired and cannot back a saved view', p_report_type_code using errcode = 'check_violation';
  end if;

  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'name_required: a saved view requires a non-empty name' using errcode = 'check_violation';
  end if;
  if jsonb_array_length(v_columns) = 0 then
    raise exception 'saved_view_columns_required: at least one column must be selected' using errcode = 'check_violation';
  end if;
  if not app.validate_config_value(v_columns) then
    raise exception 'saved_view_unsafe_columns: columns failed structural validation' using errcode = 'check_violation';
  end if;
  if not app.validate_report_parameters(v_type.parameter_schema, v_filters) then
    raise exception 'saved_view_unsafe_filters: filters failed structural or schema validation' using errcode = 'check_violation';
  end if;
  if not app.validate_config_value(v_sort) then
    raise exception 'saved_view_unsafe_sort: sort failed structural validation' using errcode = 'check_violation';
  end if;
  if not app.validate_config_value(v_grouping) then
    raise exception 'saved_view_unsafe_grouping: grouping failed structural validation' using errcode = 'check_violation';
  end if;

  select id into v_version_id from app.report_type_versions
  where report_type_code = p_report_type_code
  order by version_number desc limit 1;

  -- C-01: idempotency replay compares the FULL target tuple, not just the key.
  if p_idempotency_key is not null then
    select * into v_existing
    from app.saved_report_views
    where tenant_id = p_tenant_id and owner_auth_user_id = p_actor_auth_user_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.report_type_code is distinct from p_report_type_code
        or v_existing.name is distinct from p_name
        or v_existing.description is distinct from p_description
        or v_existing.sharing_scope is distinct from v_sharing_scope
        or v_existing.columns is distinct from v_columns
        or v_existing.filters is distinct from v_filters
        or v_existing.sort is distinct from v_sort
        or v_existing.grouping is distinct from v_grouping
      then
        raise exception 'idempotency_key_conflict: key % was already used for a different saved view', p_idempotency_key
          using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  -- C-02: the insert alone is nested in its own exception scope, so a genuine
  -- concurrent-insert race is recovered here without swallowing the deliberate
  -- idempotency_key_conflict raise above.
  begin
    insert into app.saved_report_views (
      tenant_id, report_type_code, report_type_version_id, owner_auth_user_id, owner_label,
      name, description, sharing_scope, columns, filters, sort, grouping, idempotency_key, created_by
    ) values (
      p_tenant_id, p_report_type_code, v_version_id, p_actor_auth_user_id, p_actor_label,
      p_name, p_description, v_sharing_scope, v_columns, v_filters, v_sort, v_grouping, p_idempotency_key, p_actor_label
    )
    returning * into v_view;
  exception when unique_violation then
    select * into v_existing
    from app.saved_report_views
    where tenant_id = p_tenant_id and owner_auth_user_id = p_actor_auth_user_id and idempotency_key = p_idempotency_key;
    if found then
      return v_existing;
    end if;
    raise;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_saved_report_view',
    'app.saved_report_views', v_view.id, 'success', null, null, to_jsonb(v_view)
  );

  return v_view;
end;
$$;

comment on function app.create_saved_report_view is
  'IAE-004: a private view requires only active, non-customer_user-layer tenant membership (Tier C fix: now actually enforced, matching this comment''s own always-documented contract); a tenant-shared view requires REP:Configure. Stamps report_type_version_id to the report''s own current latest version for later staleness detection.';

-- ---------------------------------------------------------------------------
-- IAE-004: app.list_saved_report_views (finding 8)
-- ---------------------------------------------------------------------------

create or replace function app.list_saved_report_views(
  p_tenant_id uuid,
  p_report_type_code text,
  p_actor_auth_user_id uuid,
  p_limit integer default 25,
  p_cursor timestamptz default null
)
returns setof app.saved_report_views
language plpgsql
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) and not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % has no active membership in tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select * from app.saved_report_views
  where tenant_id = p_tenant_id
    and (p_report_type_code is null or report_type_code = p_report_type_code)
    and (
      owner_auth_user_id = p_actor_auth_user_id
      -- Tier C fix (finding 8, spec-compliance): mirrors the RLS policy's
      -- own already-correct predicate on this same table
      -- (saved_report_views_select_scoped) -- a customer_user-layer
      -- (portal) principal, who also satisfies plain
      -- has_active_tenant_membership, no longer receives every OTHER
      -- owner's tenant-shared view configuration through this RPC.
      or (sharing_scope = 'tenant' and not app.actor_holds_customer_user_layer(p_tenant_id, p_actor_auth_user_id))
      or app.is_supreme_admin(p_actor_auth_user_id)
    )
    and (p_cursor is null or created_at < p_cursor)
  order by created_at desc
  limit least(coalesce(p_limit, 25), 100);
end;
$$;

comment on function app.list_saved_report_views is
  'IAE-004: the calling actor''s own views (any sharing_scope, unconditional) PLUS every tenant-shared view from any owner -- EXCLUDING a customer_user-layer caller from that second half (Tier C fix, mirrors this table''s own RLS policy). Cursor-paginated on created_at desc.';

-- ---------------------------------------------------------------------------
-- IAE-005: app.get_report_usage_daily (finding 10)
-- ---------------------------------------------------------------------------

create or replace function app.get_report_usage_daily(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_report_type_code text default null,
  p_from_date date default null,
  p_to_date date default null
)
returns table (
  report_type_code text,
  usage_date timestamptz,
  preview_count bigint,
  export_count bigint,
  failed_count bigint,
  last_run_at timestamptz
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- Tier C fix (finding 10, security-rls-tenant): app.mv_report_usage_daily
  -- carries zero direct grants and Postgres has no RLS on a materialized
  -- view, so this function is the SOLE tenant-isolation mechanism -- mirrors
  -- the customer_user-layer exclusion this batch already established as
  -- mandatory convention (IAE-003/IAE-004), which this function omitted.
  if not app.is_supreme_admin(p_actor_auth_user_id)
    and (not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) or app.actor_holds_customer_user_layer(p_tenant_id, p_actor_auth_user_id))
  then
    raise exception 'insufficient_authority: identity % has no active, non-customer_user-layer membership in tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select v.report_type_code, v.usage_date, v.preview_count, v.export_count, v.failed_count, v.last_run_at
  from app.mv_report_usage_daily v
  where v.tenant_id = p_tenant_id
    and (p_report_type_code is null or v.report_type_code = p_report_type_code)
    and (p_from_date is null or v.usage_date >= p_from_date)
    and (p_to_date is null or v.usage_date <= p_to_date)
  order by v.usage_date desc, v.report_type_code;
end;
$$;

comment on function app.get_report_usage_daily is
  'IAE-005: the ONLY read path into app.mv_report_usage_daily -- the view itself carries zero direct grants. Tenant-filtered and authority-checked; Tier C fix: now also excludes a customer_user-layer (portal) caller, mirroring this batch''s own established convention -- previously the sole tenant-isolation mechanism for this materialized view admitted a portal account exactly like an ordinary org_user.';

-- ---------------------------------------------------------------------------
-- IAE-005: app.refresh_analytics_view (finding 11)
-- ---------------------------------------------------------------------------

create or replace function app.refresh_analytics_view(
  p_view_code text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.analytics_refresh_runs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_view app.analytics_view_registry;
  v_run app.analytics_refresh_runs;
  v_count_before integer;
  v_count_after integer;
  v_live_count integer;
  v_boundary_at timestamptz;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: only Supreme Admin may refresh an analytics view' using errcode = 'insufficient_privilege';
  end if;

  select * into v_view from app.analytics_view_registry where view_code = p_view_code;
  if not found then
    raise exception 'analytics_view_unknown: % is not a registered analytics view', p_view_code using errcode = 'no_data_found';
  end if;
  if v_view.status <> 'active' then
    raise exception 'analytics_view_retired: % is retired and cannot be refreshed', p_view_code using errcode = 'check_violation';
  end if;

  insert into app.analytics_refresh_runs (view_code, status, triggered_by_auth_user_id, triggered_by_label)
  values (p_view_code, 'running', p_actor_auth_user_id, p_actor_label)
  returning * into v_run;

  -- The ENTIRE working body -- including the before-count -- is inside this
  -- one exception scope. A dropped/renamed view fails at the very first
  -- dynamic statement, not only at the REFRESH itself; either way it must
  -- surface as a real 'failed' run, never a raised exception the caller must
  -- catch (Prompt 333's own Alternative flow).
  begin
    execute format('select count(*) from app.%I', v_view.view_name) into v_count_before;

    -- Tier C fix (finding 11, correctness-concurrency): captured
    -- immediately before the REFRESH statement itself -- any row committed
    -- at or after this instant may or may not have been captured by
    -- REFRESH's own snapshot, so it is deliberately excluded from the
    -- reconciliation count below rather than risking a false "mismatch"
    -- purely from ordinary concurrent write activity elsewhere in the
    -- system during the refresh window (live-reproduced: a legitimate
    -- report run recorded by any tenant in the gap between REFRESH and the
    -- old, unbounded reconciliation SELECT produced a false reconciled=false
    -- even though the refresh itself captured everything that existed at
    -- refresh time).
    v_boundary_at := clock_timestamp();
    execute format('refresh materialized view concurrently app.%I', v_view.view_name);
    execute format('select count(*) from app.%I', v_view.view_name) into v_count_after;

    -- Reconciliation: an independently-computed live count from the SOURCE
    -- table, never read back from the view that was just refreshed off the
    -- identical query -- a real drift-catching assertion, not a tautology.
    -- Bounded to v_boundary_at (Tier C fix) so the comparison is apples-to-
    -- apples with what REFRESH's own snapshot could possibly have captured.
    if v_view.view_code = 'report_usage_daily' then
      select count(distinct (tenant_id, report_type_code, date_trunc('day', requested_at)))
      into v_live_count
      from app.report_runs
      where requested_at < v_boundary_at;
    else
      v_live_count := v_count_after;
    end if;

    update app.analytics_refresh_runs
    set status = 'completed', row_count_before = v_count_before, row_count_after = v_count_after,
        reconciled = (v_count_after = v_live_count), completed_at = now()
    where id = v_run.id
    returning * into v_run;
  exception when others then
    update app.analytics_refresh_runs
    set status = 'failed', error_reason = sqlerrm, completed_at = now()
    where id = v_run.id
    returning * into v_run;

    perform app.capture_audit_event(
      null, p_actor_auth_user_id, p_actor_label, 'refresh_analytics_view',
      'app.analytics_refresh_runs', v_run.id, 'failure', sqlerrm, null, to_jsonb(v_run)
    );

    return v_run;
  end;

  perform app.capture_audit_event(
    null, p_actor_auth_user_id, p_actor_label, 'refresh_analytics_view',
    'app.analytics_refresh_runs', v_run.id, 'success', null, null, to_jsonb(v_run)
  );

  return v_run;
end;
$$;

comment on function app.refresh_analytics_view is
  'IAE-005: Supreme-only. Uses REFRESH MATERIALIZED VIEW CONCURRENTLY -- the prior snapshot stays queryable for the full duration. A refresh failure is captured as a failed run (never a raised exception the caller must catch), preserving the last completed snapshot untouched. Tier C fix: the reconciliation live-count is now bounded to rows committed before a boundary timestamp captured immediately before the REFRESH statement, so ordinary concurrent write activity elsewhere in the system during the refresh window can no longer produce a false reconciliation mismatch.';

-- ---------------------------------------------------------------------------
-- IAE-002: app.cancel_report_run (finding 12)
-- ---------------------------------------------------------------------------

create or replace function app.cancel_report_run(
  p_run_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.report_runs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_run app.report_runs;
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_run from app.report_runs where id = p_run_id;
  if not found then
    raise exception 'report_run_not_found: %', p_run_id using errcode = 'no_data_found';
  end if;

  -- C-05 (docs/standards/RECURRING_DEFECT_TAXONOMY.md): a caller with no relationship
  -- to this run's own tenant gets the identical report_run_not_found a genuinely
  -- missing id would produce, never insufficient_authority -- which would disclose
  -- that a run/tenant exists at all, mirroring the already-established
  -- vendor_payment_term_proposal_not_found precedent (PRC-269, ISS-2026-054 C-05).
  if not (app.has_active_tenant_membership(v_run.tenant_id, p_actor_auth_user_id) or app.is_supreme_admin(p_actor_auth_user_id)) then
    raise exception 'report_run_not_found: %', p_run_id using errcode = 'no_data_found';
  end if;

  if v_run.requested_by_auth_user_id <> p_actor_auth_user_id and not app.is_supreme_admin(p_actor_auth_user_id) then
    -- Tier C fix (finding 12, cross-prompt-integration): accept COM:Export
    -- (the pre-existing grant every already-provisioned COM:Export holder
    -- still carries -- never removed, which would silently strip
    -- override-cancel capability from all of them) OR REP:Export (this
    -- batch's own correct, cross-domain reporting-authority module,
    -- established by IAE-003/004/005/006 but not consumed here until now).
    v_decision := app.evaluate_permission(p_actor_auth_user_id, v_run.tenant_id, 'COM', 'Export');
    if not v_decision.allowed then
      v_decision := app.evaluate_permission(p_actor_auth_user_id, v_run.tenant_id, 'REP', 'Export');
    end if;
    if not v_decision.allowed then
      raise exception 'insufficient_authority: identity % may not cancel a report run it did not request', p_actor_auth_user_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  if v_run.status <> 'queued' then
    raise exception 'report_run_not_cancellable: status is % (only queued runs can be cancelled)', v_run.status
      using errcode = 'check_violation';
  end if;

  update app.report_runs
  set status = 'failed', error_reason = 'cancelled_by_requester', completed_at = now()
  where id = p_run_id
  returning * into v_run;

  perform app.capture_audit_event(
    v_run.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_report_run',
    'app.report_runs', v_run.id, 'success', null, null,
    jsonb_build_object('report_type_code', v_run.report_type_code)
  );

  return v_run;
end;
$$;

comment on function app.cancel_report_run is
  'IAE-002: cancels a still-queued export run (the only state a cancel is meaningful in). The original requester, an actor holding COM:Export OR REP:Export (Tier C fix -- widened, never narrowed, to also accept this batch''s own correct cross-domain reporting-authority module without stripping capability from any already-provisioned COM:Export holder), or Supreme Admin may cancel; a completed/failed run cannot be re-cancelled.';
