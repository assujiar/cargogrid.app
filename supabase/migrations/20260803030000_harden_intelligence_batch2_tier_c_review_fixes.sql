-- Phase 9 Batch 2 (IAE-007..008, Prompts 335-336) Tier C fix pass, per
-- AGENTS.md's batched-review cadence. Four parallel adversarial lenses
-- (spec-compliance; security/RLS/tenant, live-tested; correctness/
-- concurrency, live-tested; cross-prompt integration) reviewed the already-
-- committed batch; this migration is the fix pass for every confirmed
-- finding. Bounded defect repair, not new capability -- no already-applied
-- migration's own PAST statements are edited (`create or replace
-- function`/`create table` only), no gate weakened, no test disabled.
--
-- ===========================================================================
-- Findings fixed, by capability
-- ===========================================================================
--
-- IAE-007 (Automation Rule Engine):
--
-- 1. (Critical, reported independently by the spec-compliance, security/RLS/
--    tenant, and cross-prompt-integration lenses -- one real bug, not three).
--    `app.evaluate_event_for_automation_rules`' own `transition_workflow`
--    action resolved the target `app.workflow_instances` row by id ALONE,
--    with zero `tenant_id` filter -- live-reproduced: a dual-tenant-member
--    actor (an ordinary, fully-supported multi-tenant-membership scenario,
--    e.g. a contractor/platform-staff account) firing tenant A's own
--    automation rule with an event payload naming tenant B's own real
--    workflow instance id caused tenant A's rule to actually transition
--    tenant B's own instance (`draft` -> `approved`/`a` -> `b`), with zero
--    relationship between the firing rule/tenant and the target instance
--    required. The downstream `app.transition_workflow_instance` only
--    checks authority against the INSTANCE's own tenant, never the firing
--    RULE's tenant -- nothing in the call chain validated the two match.
--    Contrast with the `notify` action in the very same loop, which IS
--    correctly bound to `p_tenant_id` via `app.queue_notification`'s own
--    `has_active_tenant_membership(p_tenant_id, recipient)` check -- this was
--    the one action type that never got the equivalent discipline. Fixed by
--    scoping the instance lookup to `tenant_id = p_tenant_id`, folding a
--    resolved-but-wrong-tenant id into the SAME
--    `automation_action_workflow_instance_not_found` error a genuinely
--    missing id already produces (never a distinguishable oracle).
-- 2. (Critical, correctness-concurrency, live-reproduced both sequentially
--    and under genuine two-OS-process concurrency). Approval-gated publish
--    was bypassable: `app.publish_automation_rule_version` only checked that
--    the approved request's `entity_id` equals the draft ROW's id -- never
--    that the draft's own CONTENT still matches what was actually reviewed.
--    `app.set_automation_rule_definition` has no lock against editing a draft
--    that already has an approved-but-unpublished request open against it.
--    Live-reproduced: request approval for a reviewed `notify` action, get it
--    approved, THEN edit the SAME draft to a completely different, never-
--    reviewed `enqueue_job` action, THEN publish with the stale (already-
--    approved) request id -- the swapped, unreviewed content published
--    cleanly under the old approval, no error, both sequentially and in a
--    genuine concurrent race between the editor and the publisher. Fixed by
--    freezing a content hash (`md5(trigger_event_type || conditions::text ||
--    actions::text)`) of the draft at the moment
--    `request_automation_rule_publish_approval` opens the request (new table
--    `app.automation_rule_publish_approval_content_hashes`, one row per
--    request, isolated the same way `app.integration_connection_credentials`
--    is -- RLS enabled, zero policies, zero grant, `SECURITY DEFINER`-only
--    access), and having `publish_automation_rule_version` recompute the
--    draft's CURRENT hash and reject the publish
--    (`automation_rule_publish_content_changed`) if it no longer matches what
--    was actually approved.
-- 3. (High, security-rls-tenant). `app.decide_automation_rule_publish_
--    approval` was the ONE by-id lookup in this migration that did not fold
--    a cross-tenant caller into a not-found error -- live-reproduced: a
--    tenant-2 actor with zero relationship to tenant-1's own real approval
--    step got `insufficient_authority: identity ... is not an active member
--    of tenant <tenant-1's real UUID>`, raised from the delegated
--    `app.decide_approval_step` (PLT-123) rather than folded by this
--    function's own proxy -- a distinguishable oracle from the genuinely-
--    missing-id `automation_rule_publish_approval_step_not_found` every
--    sibling by-id function in this same migration already produces. Fixed
--    by checking the caller's active membership in the resolved request's
--    own tenant BEFORE delegating, folding a mismatch into the same
--    `automation_rule_publish_approval_step_not_found` a missing id produces
--    -- never disclosing a foreign tenant's real id.
-- 4. (High, correctness-concurrency, live-reproduced with two genuine
--    concurrent OS processes racing on the SAME rule row lock).
--    `app.evaluate_event_for_automation_rules`' own idempotency-key check ran
--    BEFORE the `for update` row lock was acquired -- a TOCTOU window: two
--    concurrent callers for the SAME source event both pass the unlocked
--    pre-check (seeing nothing yet), then serialize on the lock; the loser
--    unblocks into a now-stale decision (the rule just fired, so it now
--    reads as within cooldown) and attempts to insert its OWN
--    'suppressed'/'cooldown' execution row under the SAME idempotency key
--    the winner's row already committed under -- an unhandled
--    `unique_violation` on `automation_rule_executions_rule_key_unique`
--    propagates out of the function entirely, instead of the documented
--    "the SAME source event redelivered reuses the SAME execution row"
--    idempotency guarantee (design decision 7), which the pre-existing
--    db-test only ever proved under SEQUENTIAL replay. Fixed by re-running
--    the identical idempotency-key existence check again immediately AFTER
--    the row lock is acquired, short-circuiting to the now-visible
--    committed row instead of racing the insert.
-- 5. (High, correctness-concurrency, the literal "realistic collision path"
--    check the review brief called for in the key-derivation formula, not a
--    race). A single rule version with more than one `enqueue_job` action
--    (or more than one `notify` action to the same recipient/type/channel)
--    computed the IDENTICAL idempotency/dedupe key for every one of them,
--    since the key depended only on the rule id and the execution's own
--    idempotency_key, never on the action's own position in the array.
--    Live-reproduced: a rule with two DIFFERENT `enqueue_job` payloads
--    (`first_job`/`second_job`) fired once -- `app.enqueue_job`'s own
--    check-then-insert dedupe silently returned the FIRST action's
--    already-inserted row to the SECOND call, which was recorded as a
--    false 'completed' success in `actions_taken` with zero error and zero
--    trace that the second payload was ever dropped -- real, silent data
--    loss. Fixed by threading a real per-action loop counter into both the
--    `enqueue_job` idempotency key and the `notify` dedupe key, so two
--    different actions of the same type within one rule version now always
--    get distinct keys.
-- 6. (Low, spec-compliance). `app.dry_run_automation_rule` never called
--    `app.validate_automation_rule_definition` against the draft it
--    simulates -- live-reproduced: a draft saved with an action_type
--    (`delete_customer_ledger_entry`) entirely outside the publish-time
--    allowlist was reported by dry-run as something that "would fire",
--    even though `app.validate_automation_rule_definition` (invoked from
--    both the request-approval and publish paths) would reject it outright
--    and the rule could never actually be published as drafted. Not a
--    security gap (publish/approval still correctly blocks it) but a
--    materially misleading preview for an admin testing a draft mid-edit.
--    Fixed by having `dry_run_automation_rule` also attempt
--    `app.validate_automation_rule_definition` and return `valid`/
--    `validation_error` fields alongside the existing simulation result,
--    rather than silently reporting a governance-rejected action as a real
--    would-fire candidate.
--
-- IAE-008 (Integration Hub): no findings against this capability's own
-- code survived independent verification -- see "Findings NOT changed here"
-- below for the one Medium finding reported against it and why it is
-- disclosed rather than fixed here.
--
-- Cross-capability (background job type registry, PLT-131/ATW-031):
--
-- 7. (Medium, cross-prompt-integration). IAE-007 widened
--    `app.generic_job_types()` (+`automation_action_execution`) but the
--    TypeScript single-source-of-truth counterpart,
--    `server/contracts/background-job/background-job.ts`'s own
--    `GENERIC_JOB_TYPES`, was never updated -- and had not been updated by
--    ANY of the 10 prior migrations that widened the DB-side registry since
--    the original ATW-031 fix, confirmed via `git log --follow`. The
--    existing regression test
--    (`background-job.test.ts`'s "GENERIC_JOB_TYPES matches
--    app.generic_job_types() exactly") asserted the TS array against a
--    second hand-copied literal in the SAME file, never against the live
--    database or a migration -- structurally incapable of catching this
--    drift. Live-verified: `app.generic_job_types()` returns 21 values on a
--    fully-migrated database; `GENERIC_JOB_TYPES` held only 10 -- the exact
--    11 missing values the lens named. Fixed by adding all 11 missing
--    values to `GENERIC_JOB_TYPES` (not only IAE-007's own
--    `automation_action_execution` -- the other 10 were already-shipped,
--    already-live gaps from earlier capabilities, closed here rather than
--    left half-fixed), and by adding a genuine drift gate to
--    `scripts/db-tests/background-job.sql` that compares a hardcoded
--    TS-mirror literal against the live `app.generic_job_types()` output --
--    a future SQL-side addition that is not mirrored into the TS array (or
--    into this SQL literal) now fails `pnpm run db:test`, not only a
--    same-file tautology.
--
-- ===========================================================================
-- Findings NOT changed here
-- ===========================================================================
--
--   * (Medium, cross-prompt-integration) "IAE-008's migration has no
--     explicit dependency guard on IAE-007 having seeded the shared INTHUB
--     module." Live-reproduced exactly as reported: applying every
--     migration EXCEPT `20260803010000` (IAE-007) and then applying
--     `20260803020000` (IAE-008) standalone succeeds with zero error (no DDL
--     in IAE-008 references `app.entitlement_modules`/`app.permissions` at
--     apply time, only inside function bodies evaluated later), after which
--     every INTHUB:Configure-gated IAE-008 RPC fails with a generic
--     `unknown_permission`/`insufficient_authority` that does not point at
--     the real root cause. The finding is real; it is NOT fixed here because
--     its own recommended remedy (a fail-fast guard at the top of
--     `20260803020000`'s own migration body) requires editing an
--     ALREADY-APPLIED migration, which this fix pass's own governing rule
--     (AGENTS.md's batched-review cadence, mirrored in Batch 1's own fix
--     migration header) explicitly forbids -- a guard placed instead in
--     THIS migration (`20260803030000`, which necessarily applies AFTER
--     both) would run only once IAE-008's own tables/functions already
--     exist, too late to prevent the exact silent-success-then-lockout
--     sequence the finding describes. Separately, and why this is accepted
--     as a documented risk rather than worked around some other way: this
--     repository's own migration-application model (a strictly filename-
--     timestamp-ordered sequence, applied in full via
--     `scripts/db-tests/lib/setup-disposable-db.sh`'s own plain sorted glob
--     loop, and via every other apply path in this repository) has no
--     mechanism to selectively skip one migration and apply a later one --
--     the reproduction required deliberately constructing an alternate
--     migrations directory with `20260803010000` removed, a scenario this
--     repository's own real tooling cannot produce. Reviewed and disclosed,
--     not silently dropped.
--
-- Live-verified against a real disposable Postgres 16 database
-- (tierc_batch2_fix_9f21) before being considered fixed -- see each
-- affected capability's own build log "Tier C fix pass" section for the
-- specific reproduction/regression evidence.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- IAE-007: app.evaluate_event_for_automation_rules (findings 1, 4, 5)
-- ---------------------------------------------------------------------------

create or replace function app.evaluate_event_for_automation_rules(
  p_tenant_id uuid,
  p_event_type text,
  p_event_payload jsonb,
  p_source_event_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns setof app.automation_rule_executions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_match record;
  v_rule app.automation_rules;
  v_version app.automation_rule_versions;
  v_matched boolean;
  v_idempotency_key text;
  v_existing app.automation_rule_executions;
  v_execution app.automation_rule_executions;
  v_action jsonb;
  v_action_index integer;
  v_actions_taken jsonb;
  v_action_status text;
  v_action_error text;
  v_config_version_id uuid;
  v_recipient uuid;
  v_instance app.workflow_instances;
  v_had_failure boolean;
begin
  if not (app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) or app.is_supreme_admin(p_actor_auth_user_id)) then
    raise exception 'insufficient_authority: identity % lacks active membership in tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  for v_match in
    select r.id as rule_id, v.id as version_id
    from app.automation_rules r
    join app.automation_rule_versions v on v.id = r.current_version_id
    where r.tenant_id = p_tenant_id and r.status = 'active' and r.current_version_id is not null
      and v.trigger_event_type = p_event_type
    order by r.created_at
  loop
    select * into v_version from app.automation_rule_versions where id = v_match.version_id;

    v_matched := app.evaluate_automation_condition(v_version.conditions, coalesce(p_event_payload, '{}'::jsonb));
    if not v_matched then
      continue;
    end if;

    v_idempotency_key := coalesce(p_source_event_id::text, gen_random_uuid()::text);

    select * into v_existing from app.automation_rule_executions
    where automation_rule_id = v_match.rule_id and idempotency_key = v_idempotency_key;
    if found then
      return next v_existing;
      continue;
    end if;

    -- Real, concurrency-safe cooldown/storm decision -- row-locked before
    -- deciding, mirroring this same batch's own Tier C app.run_scheduled_
    -- report concurrency lesson (design decision 6).
    select * into v_rule from app.automation_rules where id = v_match.rule_id for update;

    -- Tier C fix (finding 4, High, correctness-concurrency): re-run the
    -- IDENTICAL idempotency-key check again now that the rule row is
    -- genuinely locked -- closes the TOCTOU window a live two-OS-process
    -- race proved real: a concurrent caller that passed the unlocked
    -- pre-check above (seeing nothing yet) and then blocked on this SAME
    -- lock must see the just-committed winner's row here and return it,
    -- rather than falling through into a stale cooldown/storm decision and
    -- colliding with that winner's own idempotency key on its own insert
    -- below (previously an unhandled unique_violation propagating out of
    -- this function entirely).
    select * into v_existing from app.automation_rule_executions
    where automation_rule_id = v_match.rule_id and idempotency_key = v_idempotency_key;
    if found then
      return next v_existing;
      continue;
    end if;

    if v_rule.status <> 'active' or v_rule.current_version_id is distinct from v_match.version_id then
      -- Concurrently paused/republished since the unlocked match above --
      -- skip silently rather than act against a superseded version.
      continue;
    end if;

    if v_rule.last_fired_at is not null and v_rule.last_fired_at > now() - make_interval(secs => v_rule.cooldown_seconds) then
      insert into app.automation_rule_executions (
        tenant_id, automation_rule_id, automation_rule_version_id, trigger_event_type, source_event_id,
        event_payload, status, suppressed_reason, idempotency_key, triggered_by
      ) values (
        p_tenant_id, v_rule.id, v_version.id, p_event_type, p_source_event_id,
        coalesce(p_event_payload, '{}'::jsonb), 'suppressed', 'cooldown', v_idempotency_key, p_actor_label
      ) returning * into v_execution;
      return next v_execution;
      continue;
    end if;

    if v_rule.window_started_at is null or v_rule.window_started_at < now() - make_interval(secs => v_rule.window_seconds) then
      update app.automation_rules set window_started_at = now(), fire_count_in_window = 0 where id = v_rule.id
      returning * into v_rule;
    end if;

    if v_rule.fire_count_in_window >= v_rule.max_fires_per_window then
      insert into app.automation_rule_executions (
        tenant_id, automation_rule_id, automation_rule_version_id, trigger_event_type, source_event_id,
        event_payload, status, suppressed_reason, idempotency_key, triggered_by
      ) values (
        p_tenant_id, v_rule.id, v_version.id, p_event_type, p_source_event_id,
        coalesce(p_event_payload, '{}'::jsonb), 'suppressed', 'storm_window_exceeded', v_idempotency_key, p_actor_label
      ) returning * into v_execution;
      return next v_execution;
      continue;
    end if;

    update app.automation_rules
    set last_fired_at = now(), fire_count_in_window = fire_count_in_window + 1
    where id = v_rule.id;

    v_actions_taken := '[]'::jsonb;
    v_had_failure := false;
    v_action_index := 0;

    for v_action in select * from jsonb_array_elements(v_version.actions) loop
      v_action_index := v_action_index + 1;
      v_action_status := 'completed';
      v_action_error := null;
      begin
        if v_action ->> 'action_type' = 'notify' then
          v_recipient := nullif(p_event_payload ->> (v_action ->> 'recipient_field'), '')::uuid;
          if v_recipient is null then
            raise exception 'automation_action_missing_recipient: event payload has no usable % field', v_action ->> 'recipient_field';
          end if;

          select resolved_version_id into v_config_version_id
          from app.resolve_config('notification:' || (v_action ->> 'notification_type_code'), p_tenant_id);
          if v_config_version_id is null then
            raise exception 'automation_action_notification_type_unconfigured: % has no resolvable config for tenant %', v_action ->> 'notification_type_code', p_tenant_id;
          end if;

          perform app.queue_notification(
            v_config_version_id, p_tenant_id, v_action ->> 'notification_type_code', v_recipient,
            v_action ->> 'channel', coalesce(v_action ->> 'locale', 'en'), coalesce(p_event_payload, '{}'::jsonb),
            -- Tier C fix (finding 5, High): the dedupe key now includes the
            -- action's own position in the actions array -- previously
            -- IDENTICAL for every notify action in the same rule version,
            -- so a second notify action to the same recipient/type/channel
            -- would silently dedupe away against the first.
            'automation-' || v_rule.id || '-' || v_idempotency_key || '-notify-' || v_action_index,
            p_actor_auth_user_id, p_actor_label
          );
        elsif v_action ->> 'action_type' = 'transition_workflow' then
          -- Tier C fix (finding 1, Critical, security-rls-tenant): scope the
          -- instance lookup to THIS rule's own firing tenant -- previously
          -- unscoped, live-proven to let one tenant's automation rule
          -- transition an unrelated tenant's own workflow instance whenever
          -- the acting identity happened to hold active membership in both
          -- (an ordinary, fully-supported multi-tenant scenario, e.g. a
          -- contractor account). A resolved-but-wrong-tenant id now folds
          -- into the SAME not-found error a genuinely missing id produces,
          -- mirroring the notify action's own p_tenant_id-bound discipline.
          select * into v_instance from app.workflow_instances
          where id = nullif(p_event_payload ->> (v_action ->> 'instance_id_field'), '')::uuid
            and tenant_id = p_tenant_id;
          if v_instance.id is null then
            raise exception 'automation_action_workflow_instance_not_found: event payload has no resolvable % workflow instance', v_action ->> 'instance_id_field';
          end if;

          perform app.transition_workflow_instance(
            v_instance.id, v_instance.current_state, v_action ->> 'to_state',
            p_actor_auth_user_id, p_actor_label, v_action ->> 'reason'
          );
        elsif v_action ->> 'action_type' = 'enqueue_job' then
          perform app.enqueue_job(
            p_tenant_id, 'automation_action_execution', coalesce(v_action -> 'payload', '{}'::jsonb),
            0,
            -- Tier C fix (finding 5, High, live-reproduced real data loss):
            -- the idempotency key now includes the action's own position in
            -- the actions array -- previously IDENTICAL for every
            -- enqueue_job action in the same rule version (depended only on
            -- the rule id and the execution's own idempotency_key), so a
            -- SECOND enqueue_job action with a genuinely different payload
            -- silently deduped away against the first inside
            -- app.enqueue_job's own check-then-insert, while still being
            -- reported as a false 'completed' success with no error.
            'automation-' || v_rule.id || '-' || v_idempotency_key || '-enqueue_job-' || v_action_index,
            3, p_actor_auth_user_id, p_actor_label
          );
        end if;
      exception when others then
        v_action_status := 'failed';
        v_action_error := sqlerrm;
        v_had_failure := true;
      end;

      v_actions_taken := v_actions_taken || jsonb_build_array(jsonb_build_object(
        'action_type', v_action ->> 'action_type', 'status', v_action_status, 'error', v_action_error
      ));
    end loop;

    insert into app.automation_rule_executions (
      tenant_id, automation_rule_id, automation_rule_version_id, trigger_event_type, source_event_id,
      event_payload, status, actions_taken, idempotency_key, triggered_by
    ) values (
      p_tenant_id, v_rule.id, v_version.id, p_event_type, p_source_event_id,
      coalesce(p_event_payload, '{}'::jsonb), case when v_had_failure then 'failed' else 'completed' end,
      v_actions_taken, v_idempotency_key, p_actor_label
    ) returning * into v_execution;

    return next v_execution;
  end loop;

  return;
end;
$$;

comment on function app.evaluate_event_for_automation_rules is
  'IAE-007: the real trigger-evaluation entrypoint (design decision 5) -- service_role-only, a trusted system dispatcher, never a live end-user session. For every active, published rule in the tenant matching p_event_type: evaluates conditions, enforces cooldown_seconds/max_fires_per_window under a real row lock (design decision 6), and on a genuine fire executes notify/transition_workflow/enqueue_job actions in order, recording one real app.automation_rule_executions row per attempt (completed/suppressed/failed, never a silent no-op). Tier C fixes: the transition_workflow action now scopes its workflow-instance lookup to the firing rule''s own tenant (previously unscoped -- a real, live-proven cross-tenant mutation); the idempotency-key check is re-run after the row lock is acquired, closing a TOCTOU window a concurrent same-source-event redelivery could otherwise crash on; the notify/enqueue_job dedupe and idempotency keys now include the action''s own position in the actions array, closing a silent-data-loss collision when a rule carries more than one action of the same type. No domain capability calls this automatically yet -- disclosed, not fabricated (design decision 5).';

-- ---------------------------------------------------------------------------
-- IAE-007: app.dry_run_automation_rule (finding 6)
-- ---------------------------------------------------------------------------

create or replace function app.dry_run_automation_rule(
  p_rule_id uuid,
  p_sample_event_payload jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns jsonb
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_rule app.automation_rules;
  v_decision app.rbac_decision;
  v_draft app.automation_rule_versions;
  v_matched boolean;
  v_valid boolean := true;
  v_validation_error text := null;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_rule from app.automation_rules where id = p_rule_id;
  if not found then
    raise exception 'automation_rule_not_found: %', p_rule_id using errcode = 'no_data_found';
  end if;

  if not (app.has_active_tenant_membership(v_rule.tenant_id, p_actor_auth_user_id) or app.is_supreme_admin(p_actor_auth_user_id)) then
    raise exception 'automation_rule_not_found: %', p_rule_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_rule.tenant_id, 'INTHUB', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks INTHUB:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_rule.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_draft from app.automation_rule_versions
  where automation_rule_id = p_rule_id and status = 'draft'
  order by version_number desc limit 1;
  if not found then
    raise exception 'automation_rule_no_open_draft: rule % has no open draft version', p_rule_id using errcode = 'check_violation';
  end if;

  -- Tier C fix (finding 6, Low, spec-compliance): the dry run now also
  -- reports whether the draft is actually publishable, exactly the way
  -- app.request_automation_rule_publish_approval/app.publish_automation_rule_
  -- version would evaluate it -- previously a draft carrying an action_type
  -- entirely outside the publish-time allowlist (or otherwise structurally
  -- invalid) was reported as something that "would fire" with no indication
  -- governance would reject it outright. Never blocks the simulation itself
  -- (an admin mid-edit should still see the match/would-fire preview) --
  -- only adds an honest valid/validation_error signal alongside it.
  begin
    perform app.validate_automation_rule_definition(v_draft.trigger_event_type, v_draft.conditions, v_draft.actions);
  exception when others then
    v_valid := false;
    v_validation_error := sqlerrm;
  end;

  v_matched := app.evaluate_automation_condition(v_draft.conditions, coalesce(p_sample_event_payload, '{}'::jsonb));

  -- Pure simulation -- NO app.queue_notification/app.enqueue_job/app.transition_workflow_instance
  -- call anywhere in this function (design decision 9), proven directly in
  -- the db-test by asserting zero side-effect rows result from a dry run.
  return jsonb_build_object(
    'matched', v_matched,
    'trigger_event_type', v_draft.trigger_event_type,
    'would_fire_actions', case when v_matched then v_draft.actions else '[]'::jsonb end,
    'valid', v_valid,
    'validation_error', v_validation_error
  );
end;
$$;

comment on function app.dry_run_automation_rule is
  'IAE-007: INTHUB:Configure-gated. Evaluates the rule''s own current DRAFT version''s conditions against a caller-supplied sample event payload and reports which actions WOULD fire -- a pure, side-effect-free simulation (design decision 9), never a real notification/job/transition. Tier C fix: also reports valid/validation_error (app.validate_automation_rule_definition run against the draft) so a structurally-invalid draft is never reported as a real would-fire candidate without qualification.';

-- ---------------------------------------------------------------------------
-- IAE-007: approval-content binding (finding 2) -- a new, isolated table
-- recording the content hash of the EXACT draft state a publish-approval
-- request was opened against, so a later edit to the same draft row cannot
-- silently ride a stale approval to publish. Isolated the same way
-- app.integration_connection_credentials is (IAE-008 design decision 3):
-- RLS enabled, zero policies, zero grant to authenticated/anon -- only a
-- SECURITY DEFINER function (running as its own owner, which bypasses RLS
-- the same way every other SECURITY DEFINER function in this repository
-- already relies on) can ever touch it.
-- ---------------------------------------------------------------------------

create table app.automation_rule_publish_approval_content_hashes (
  request_id uuid primary key references app.approval_requests (id),
  content_hash text not null,
  created_at timestamptz not null default now()
);

comment on table app.automation_rule_publish_approval_content_hashes is
  'Tier C fix (finding 2, Critical): one row per app.approval_requests row opened by app.request_automation_rule_publish_approval, recording md5(trigger_event_type || conditions::text || actions::text) of the EXACT draft content that was reviewed at request time. app.publish_automation_rule_version recomputes the draft''s CURRENT hash at publish time and refuses to publish if it no longer matches -- closes a live-proven bypass where set_automation_rule_definition could edit an already-approved draft''s content in place before publish, and publish would accept the swapped, never-reviewed content because it only ever checked the draft ROW id, never its content.';

alter table app.automation_rule_publish_approval_content_hashes enable row level security;

-- ---------------------------------------------------------------------------
-- IAE-007: app.request_automation_rule_publish_approval (finding 2)
-- ---------------------------------------------------------------------------

create or replace function app.request_automation_rule_publish_approval(
  p_rule_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.approval_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_rule app.automation_rules;
  v_decision app.rbac_decision;
  v_draft app.automation_rule_versions;
  v_approval_version_id uuid;
  v_request app.approval_requests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_rule from app.automation_rules where id = p_rule_id;
  if not found then
    raise exception 'automation_rule_not_found: %', p_rule_id using errcode = 'no_data_found';
  end if;

  if not (app.has_active_tenant_membership(v_rule.tenant_id, p_actor_auth_user_id) or app.is_supreme_admin(p_actor_auth_user_id)) then
    raise exception 'automation_rule_not_found: %', p_rule_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_rule.tenant_id, 'INTHUB', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks INTHUB:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_rule.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_draft from app.automation_rule_versions
  where automation_rule_id = p_rule_id and status = 'draft'
  order by version_number desc limit 1;
  if not found then
    raise exception 'automation_rule_no_open_draft: rule % has no open draft version', p_rule_id using errcode = 'check_violation';
  end if;

  perform app.validate_automation_rule_definition(v_draft.trigger_event_type, v_draft.conditions, v_draft.actions);

  select cv.id into v_approval_version_id
  from app.config_objects co
  join app.config_versions cv on cv.config_object_id = co.id and cv.status = 'published'
  where co.config_type_code = 'approval:automation_rule_publish' and co.tenant_id = v_rule.tenant_id and co.scope_level = 'tenant';

  if v_approval_version_id is null then
    raise exception 'automation_rule_publish_approval_not_configured: tenant % has not published an approval:automation_rule_publish definition yet', v_rule.tenant_id
      using errcode = 'check_violation';
  end if;

  select * into v_request from app.request_approval(
    v_approval_version_id, v_rule.tenant_id, 'automation_rule_version', v_draft.id,
    'automation-rule-publish-' || v_draft.id, p_actor_auth_user_id, p_actor_label
  );

  -- Tier C fix (finding 2, Critical): freeze the content this request is
  -- actually reviewed against. on conflict do nothing -- a replayed request
  -- (app.request_approval's own idempotency, same request row returned)
  -- must never overwrite an already-frozen hash with the draft's possibly-
  -- since-mutated current content.
  insert into app.automation_rule_publish_approval_content_hashes (request_id, content_hash)
  values (v_request.id, md5(coalesce(v_draft.trigger_event_type, '') || '|' || v_draft.conditions::text || '|' || v_draft.actions::text))
  on conflict (request_id) do nothing;

  return v_request;
end;
$$;

comment on function app.request_automation_rule_publish_approval is
  'IAE-007: INTHUB:Configure-gated. Validates the draft is structurally publishable, then opens a real app.approval_requests row against the tenant''s own published approval:automation_rule_publish definition (PLT-123, reused directly), bound to this exact draft version via entity_type/entity_id (design decision 3). Tier C fix: also freezes a content hash of the draft at this exact moment (app.automation_rule_publish_approval_content_hashes) -- app.publish_automation_rule_version checks the draft has not been edited since.';

-- ---------------------------------------------------------------------------
-- IAE-007: app.decide_automation_rule_publish_approval (finding 3)
-- ---------------------------------------------------------------------------

create or replace function app.decide_automation_rule_publish_approval(
  p_request_step_id uuid,
  p_decision text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_reason text default null
)
returns app.approval_request_steps
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_step app.approval_request_steps;
  v_request app.approval_requests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_step from app.approval_request_steps where id = p_request_step_id;
  if not found then
    raise exception 'automation_rule_publish_approval_step_not_found: %', p_request_step_id using errcode = 'no_data_found';
  end if;

  select * into v_request from app.approval_requests where id = v_step.request_id;

  -- Tier C fix (finding 3, High, C-05 discipline, live-reproduced): a caller
  -- with zero standing in the resolved request's own tenant previously got
  -- app.decide_approval_step's own insufficient_authority error, which
  -- embeds the tenant's real UUID verbatim -- a distinguishable oracle from
  -- the genuinely-missing-id not-found error every sibling by-id function in
  -- this same migration already produces. Folded into the SAME
  -- automation_rule_publish_approval_step_not_found a missing id produces,
  -- checked BEFORE the entity_type domain check below and before ever
  -- delegating to app.decide_approval_step.
  if not (app.has_active_tenant_membership(v_request.tenant_id, p_actor_auth_user_id) or app.is_supreme_admin(p_actor_auth_user_id)) then
    raise exception 'automation_rule_publish_approval_step_not_found: %', p_request_step_id using errcode = 'no_data_found';
  end if;

  if v_request.entity_type <> 'automation_rule_version' then
    raise exception 'automation_rule_publish_approval_wrong_domain: step % does not belong to an automation rule publish request', p_request_step_id
      using errcode = 'check_violation';
  end if;

  return app.decide_approval_step(p_request_step_id, p_decision, p_actor_auth_user_id, p_actor_label, p_reason);
end;
$$;

comment on function app.decide_automation_rule_publish_approval is
  'IAE-007: a domain-scoped SECURITY DEFINER proxy to app.decide_approval_step (PLT-123, service_role-only) -- lets a real, eligible tenant approver decide a step through the same eligibility/separation-of-duties/idempotent-decision logic app.decide_approval_step already enforces, without granting authenticated broad access to decide ANY approval step in the tenant. Refuses a step that does not belong to an automation_rule_version request by name. Tier C fix: a cross-tenant caller now gets the same automation_rule_publish_approval_step_not_found a missing id would produce (C-05), never a tenant-id-disclosing insufficient_authority delegated from app.decide_approval_step.';

-- ---------------------------------------------------------------------------
-- IAE-007: app.publish_automation_rule_version (finding 2)
-- ---------------------------------------------------------------------------

create or replace function app.publish_automation_rule_version(
  p_rule_id uuid,
  p_approval_request_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.automation_rules
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_rule app.automation_rules;
  v_decision app.rbac_decision;
  v_draft app.automation_rule_versions;
  v_request app.approval_requests;
  v_next_version integer;
  v_expected_hash text;
  v_current_hash text;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_rule from app.automation_rules where id = p_rule_id for update;
  if not found then
    raise exception 'automation_rule_not_found: %', p_rule_id using errcode = 'no_data_found';
  end if;

  if not (app.has_active_tenant_membership(v_rule.tenant_id, p_actor_auth_user_id) or app.is_supreme_admin(p_actor_auth_user_id)) then
    raise exception 'automation_rule_not_found: %', p_rule_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_rule.tenant_id, 'INTHUB', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks INTHUB:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_rule.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_draft from app.automation_rule_versions
  where automation_rule_id = p_rule_id and status = 'draft'
  order by version_number desc limit 1;
  if not found then
    raise exception 'automation_rule_no_open_draft: rule % has no open draft version', p_rule_id using errcode = 'check_violation';
  end if;

  select * into v_request from app.approval_requests where id = p_approval_request_id;
  if not found or v_request.tenant_id <> v_rule.tenant_id then
    raise exception 'automation_rule_publish_approval_not_found: no approval request % for tenant %', p_approval_request_id, v_rule.tenant_id
      using errcode = 'no_data_found';
  end if;
  if v_request.entity_type <> 'automation_rule_version' or v_request.entity_id <> v_draft.id then
    raise exception 'automation_rule_publish_approval_mismatch: approval request % is not for the exact draft version being published', p_approval_request_id
      using errcode = 'check_violation';
  end if;
  if v_request.status <> 'approved' then
    raise exception 'automation_rule_publish_not_approved: approval request % is %, not approved', p_approval_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  -- Tier C fix (finding 2, Critical, live-reproduced both sequentially and
  -- under genuine concurrency): the approval was previously bound only to
  -- the draft ROW id (checked above), never its CONTENT -- app.set_
  -- automation_rule_definition has no lock preventing an edit to the same
  -- draft row after its approval was granted but before publish. Recompute
  -- the draft's CURRENT content hash and compare it against the hash frozen
  -- at the moment this exact request was opened
  -- (app.request_automation_rule_publish_approval); reject the publish if
  -- the draft has been mutated since -- never silently publish swapped,
  -- unreviewed content under a stale approval.
  select content_hash into v_expected_hash
  from app.automation_rule_publish_approval_content_hashes
  where request_id = p_approval_request_id;

  v_current_hash := md5(coalesce(v_draft.trigger_event_type, '') || '|' || v_draft.conditions::text || '|' || v_draft.actions::text);

  if v_expected_hash is null or v_current_hash <> v_expected_hash then
    raise exception 'automation_rule_publish_content_changed: draft % was edited after approval request % was opened -- request a fresh approval for the current content', v_draft.id, p_approval_request_id
      using errcode = 'check_violation';
  end if;

  perform app.validate_automation_rule_definition(v_draft.trigger_event_type, v_draft.conditions, v_draft.actions);

  update app.automation_rule_versions set status = 'published', published_at = now() where id = v_draft.id;

  select coalesce(max(version_number), 0) + 1 into v_next_version from app.automation_rule_versions where automation_rule_id = p_rule_id;
  insert into app.automation_rule_versions (automation_rule_id, version_number, status, trigger_event_type, conditions, actions, created_by_auth_user_id, created_by)
  values (p_rule_id, v_next_version, 'draft', v_draft.trigger_event_type, v_draft.conditions, v_draft.actions, p_actor_auth_user_id, p_actor_label);

  update app.automation_rules set current_version_id = v_draft.id where id = p_rule_id
  returning * into v_rule;

  perform app.capture_audit_event(
    v_rule.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_automation_rule_version',
    'app.automation_rule_versions', v_draft.id, 'success', null, null,
    jsonb_build_object('approval_request_id', p_approval_request_id)
  );

  return v_rule;
end;
$$;

comment on function app.publish_automation_rule_version is
  'IAE-007: INTHUB:Configure-gated. Locks the rule row for update before deciding (C-04). Requires an approved app.approval_requests row bound to the EXACT draft version being published (design decision 3) -- a different, unrelated, or non-approved request is rejected by name, never silently accepted. Tier C fix: ALSO requires the draft''s current content hash to still match what was actually reviewed at request time (app.automation_rule_publish_approval_content_hashes) -- closes a live-proven bypass where the draft could be edited in place after approval and published anyway under the stale approval. Publishes the draft, points current_version_id at it, then opens a fresh draft copying the just-published definition, mirroring app.publish_tenant_dashboard_version''s own established shape.';

-- ===========================================================================
-- Grants -- the new table only, everything else already granted by
-- 20260803010000 and unaffected by a create-or-replace of the same
-- signature.
-- ===========================================================================

revoke execute on all functions in schema app from public;
-- app.automation_rule_publish_approval_content_hashes: deliberately ZERO
-- grant to authenticated/anon, not even select -- only a SECURITY DEFINER
-- function (running as its own owner) may ever touch it, mirroring
-- app.integration_connection_credentials (IAE-008 design decision 3).
