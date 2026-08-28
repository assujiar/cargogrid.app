-- Track B Batch 7 -- ISS-2026-213 (found at CG-S15-HDN-008's own Tier C review, OPEN,
-- Low, owner HDN-386): 6 self-approval/maker-checker functions share ISS-2026-209's own
-- "boolean-equality-on-a-nullable-column fails open" comparison shape -- a nullable
-- <actor_column> compared to p_actor_auth_user_id with a bare `=`, which evaluates to SQL
-- NULL (never TRUE) whenever the nullable column is null, so `if v_record.<actor_column> =
-- p_actor_auth_user_id then <deny self-approval>` silently skips the deny branch instead of
-- raising. ISS-2026-209's own fix precedent (20260813000000_harden_api_compatibility_audit_
-- findings.sql, mirrored again at ISS-2026-210) is the proven shape: make the null case an
-- explicit, self-documenting, DENY-by-default outcome rather than an implicit fail-open one.
--
-- Verified independently (not merely trusted from the KNOWN_ISSUES.md entry) before
-- drafting this fix:
--   1. All 6 actor columns below are genuinely nullable in their own table DDL (`uuid
--      references auth.users (id)`, no `not null`): app.approval_requests.requested_by_
--      auth_user_id (20260719090000 line 185), app.cycle_count_observations.counted_by_
--      auth_user_id (20260730270000 line 302), app.tenant_deployment_records.created_by_
--      auth_user_id (20260808000000 line 90), app.tenant_region_assignments.created_by_
--      auth_user_id (20260808100000 line 176), app.warehouse_billing_events.reviewed_by_
--      auth_user_id (20260730300000 line 288).
--   2. All 6 functions genuinely sit behind their own prior app.evaluate_permission()/
--      app.check_approval_request_authority() authority gate on the same mutation path
--      that would need to populate the nullable column with NULL in the first place --
--      confirming the entry's own "not live-forced exploitable today" claim (no live
--      caller can currently reach the equality check with a null actor column AND pass
--      the authority gate), which is why this is Low, not Critical like ISS-2026-209 itself
--      (a true unauthenticated boundary with no prior gate of any kind).
--   3. app.decide_approval_step (`create or replace function`, most recently redefined at
--      20260827130000_harden_tenant_disclosure_representative_extension_batch2.sql) is the
--      LATEST body edited here -- the two earlier definitions (20260719090000,
--      20260730670000) are intentionally left untouched (never edit an applied migration).
--
-- Fix shape, identical across all 6 (a single comparison-operator change each, no other
-- line touched): wrap the existing `<column> = p_actor_auth_user_id` equality in
-- `coalesce(..., true)`, mirroring this codebase's own established idiom for turning a
-- nullable boolean into a deterministic one before using it in a conditional (already used
-- immediately adjacent to 2 of these 6 call sites: `coalesce(v_allow_self_approval, false)`
-- in app.decide_approval_step, `coalesce(v_supported, false)` in app.approve_region_
-- assignment). `coalesce(x = y, true)` reads as "if we cannot determine this is NOT a
-- self-approval, treat it as one" -- fail-closed on missing data, deterministic regardless
-- of which side is null, and self-documenting at the call site (no separate guard block
-- needed, no duplicated raise message). Every other line of each function body is
-- byte-for-byte unchanged from its current live definition -- CREATE OR REPLACE, same
-- signature, no grant/wrapper change needed (server/generated public.* pass-through
-- wrappers in 20260826000000_create_public_api_data_wrappers.sql all `select
-- app.<fn>(...)` verbatim and pick up the new body automatically; confirmed by grep that
-- none of the 6 wrappers re-declare any of this logic).
--
-- Incidental, OUT-OF-SCOPE finding disclosed rather than silently fixed alongside this:
-- app.tenant_deployment_records/app.tenant_region_assignments both also carry a table-level
-- CHECK constraint (`..._no_self_approval check (approved_by_auth_user_id is null or
-- approved_by_auth_user_id <> created_by_auth_user_id)`) which has the SAME fail-open shape
-- one level down (a CHECK that evaluates to NULL, not FALSE, is satisfied) -- but a
-- CHECK-constraint rewrite is a different taxonomy class than a function-body fix, was not
-- one of ISS-2026-213's own 6 named functions, and is left to whoever owns that entry.
--
-- Regression coverage: scripts/db-tests/approval.sql, advanced-tms-cycle-count-
-- adjustment.sql, dedicated-enterprise-deployment.sql, multi-region-data-residency.sql,
-- advanced-tms-warehouse-billing-events.sql each gain one new block proving
-- a NULL actor column now denies self-approval rather than silently passing it through --
-- structurally unreachable via any live caller today (the upstream authority gate already
-- excludes it), so exercised the same way ISS-2026-210's own dormant-defect regression
-- test was: a direct super-user-context function call with the nullable column forced to
-- NULL, bypassing the (already-verified-effective) upstream gate on purpose to prove this
-- specific comparison, in isolation, is now deterministic.

-- ===========================================================================
-- 1. app.decide_approval_step -- self-approval check against approval_requests.
--    requested_by_auth_user_id (nullable). Latest body verbatim from 20260827130000,
--    single comparison-operator change on the self-approval line.
-- ===========================================================================

create or replace function app.decide_approval_step(
  p_request_step_id uuid,
  p_decision text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_reason text default null
)
returns app.approval_request_steps
language plpgsql
as $$
declare
  v_step app.approval_request_steps;
  v_request app.approval_requests;
  v_allow_self_approval boolean;
  v_updated_step app.approval_request_steps;
  v_next_step_id uuid;
  v_remaining_active integer;
  v_approved_step_count integer;
  v_total_step_count integer;
  v_threshold_required_steps integer;
begin
  if p_decision not in ('approved', 'rejected') then
    raise exception 'approval_invalid_decision: decision % must be approved or rejected', p_decision
      using errcode = 'check_violation';
  end if;

  if p_decision = 'rejected' and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'reason_required: a non-empty reason is required to reject an approval step' using errcode = 'check_violation';
  end if;

  select * into v_step from app.approval_request_steps where id = p_request_step_id;
  if not found then
    raise exception 'approval_step_not_found: no approval request step %', p_request_step_id
      using errcode = 'no_data_found';
  end if;
  select * into v_request from app.approval_requests where id = v_step.request_id;

  if not app.check_approval_request_authority(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'approval_step_not_found: no approval request step %', p_request_step_id
      using errcode = 'no_data_found';
  end if;

  if v_request.status <> 'pending' then
    raise exception 'approval_request_not_pending: request % is %, only a pending request can be decided', v_request.id, v_request.status
      using errcode = 'check_violation';
  end if;
  if v_step.status <> 'active' then
    raise exception 'approval_step_not_active: step % is %, only an active step can be decided', p_request_step_id, v_step.status
      using errcode = 'check_violation';
  end if;

  select coalesce((value #>> '{}')::boolean, false) into v_allow_self_approval
  from app.config_items where config_version_id = v_request.config_version_id and key = 'allow_self_approval';
  -- ISS-2026-213 fix: coalesce(..., true) -- a null v_request.requested_by_auth_user_id
  -- (structurally unreachable today, see this migration's own header) now denies rather
  -- than silently passing.
  if not coalesce(v_allow_self_approval, false) and coalesce(v_request.requested_by_auth_user_id = p_actor_auth_user_id, true) then
    raise exception 'approval_self_approval_denied: identity % requested this approval and self-approval is not allowed', p_actor_auth_user_id
      using errcode = 'check_violation';
  end if;

  if not app.is_eligible_approval_approver(v_step, v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an eligible approver for step %', p_actor_auth_user_id, p_request_step_id
      using errcode = 'insufficient_privilege';
  end if;

  begin
    insert into app.approval_decisions (request_step_id, actor_auth_user_id, actor_label, decision, reason)
    values (p_request_step_id, p_actor_auth_user_id, p_actor_label, p_decision, p_reason);
  exception
    when unique_violation then
      raise exception 'approval_decision_already_recorded: identity % has already decided step %', p_actor_auth_user_id, p_request_step_id
        using errcode = 'unique_violation';
  end;

  if p_decision = 'rejected' then
    update app.approval_request_steps set status = 'rejected' where id = p_request_step_id and status = 'active' returning * into v_updated_step;
    if not found then
      raise exception 'approval_step_not_active: step % changed concurrently, no longer active', p_request_step_id
        using errcode = 'check_violation';
    end if;
    update app.approval_request_steps set status = 'skipped' where request_id = v_request.id and status in ('pending', 'active') and id <> p_request_step_id;
    update app.approval_requests set status = 'rejected', ended_at = now(), ended_reason = p_reason where id = v_request.id;
  else
    update app.approval_request_steps
    set approvals_count = approvals_count + 1,
        status = case when approvals_count + 1 >= required_approvals then 'approved' else 'active' end
    where id = p_request_step_id and status = 'active'
    returning * into v_updated_step;
    if not found then
      raise exception 'approval_step_not_active: step % changed concurrently, no longer active', p_request_step_id
        using errcode = 'check_violation';
    end if;

    if v_updated_step.status = 'approved' then
      if v_request.pattern = 'sequential' then
        select id into v_next_step_id from app.approval_request_steps where request_id = v_request.id and step_order = v_updated_step.step_order + 1;
        if found then
          update app.approval_request_steps set status = 'active' where id = v_next_step_id;
        else
          update app.approval_requests set status = 'approved', ended_at = now(), ended_reason = 'all sequential steps approved' where id = v_request.id;
        end if;
      elsif v_request.pattern = 'parallel' then
        select count(*) into v_remaining_active from app.approval_request_steps where request_id = v_request.id and status not in ('approved', 'skipped');
        if v_remaining_active = 0 then
          update app.approval_requests set status = 'approved', ended_at = now(), ended_reason = 'all parallel steps approved' where id = v_request.id;
        end if;
      else -- threshold
        select count(*) into v_approved_step_count from app.approval_request_steps where request_id = v_request.id and status = 'approved';
        select count(*) into v_total_step_count from app.approval_request_steps where request_id = v_request.id;
        select (value #>> '{}')::integer into v_threshold_required_steps from app.config_items where config_version_id = v_request.config_version_id and key = 'threshold_required_steps';
        if v_approved_step_count >= v_threshold_required_steps then
          update app.approval_request_steps set status = 'skipped' where request_id = v_request.id and status in ('pending', 'active');
          update app.approval_requests set status = 'approved', ended_at = now(), ended_reason = format('threshold %s of %s steps approved', v_threshold_required_steps, v_total_step_count) where id = v_request.id;
        end if;
      end if;
    end if;
  end if;

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_approval_step',
    'app.approval_request_steps', p_request_step_id, 'success', p_reason, to_jsonb(v_step), to_jsonb(v_updated_step)
  );

  select * into v_updated_step from app.approval_request_steps where id = p_request_step_id;
  return v_updated_step;
end;
$$;

comment on function app.decide_approval_step is 'PLT-123: the core decision engine (Prompt 123 §20 task 3/§21/§22/§25). Real optimistic concurrency and no-duplicate-decision protection come from two structural guarantees: the atomic UPDATE ... WHERE status = ''active'' below, and approval_decisions'' own unique(request_step_id, actor_auth_user_id). Batch 257-259 review (C-18-adjacent, MEDIUM): a reject now requires a non-empty p_reason at this shared choke point. ISS-2026-049 fix, second half (Track B Batch 2): a genuine stranger to the request''s tenant now gets the same not-found error a nonexistent step id produces, never a tenant-echoing insufficient_authority error -- also closes ISS-2026-043/048''s own class at this shared engine choke point. ISS-2026-049''s own first half (entity_type checked before authority in each decide_*_approval_step wrapper) is unrelated and stays open. ISS-2026-213 fix (Track B Batch 7): the self-approval check''s own equality against the nullable requested_by_auth_user_id now uses coalesce(..., true) -- a null requester now denies self-approval rather than silently passing, mirroring ISS-2026-209/210''s own proven null-guard shape.';

-- ===========================================================================
-- 2. app.approve_cycle_count_variance -- self-approval check against
--    cycle_count_observations.counted_by_auth_user_id (nullable). Body verbatim from
--    20260730270000, single comparison-operator change.
-- ===========================================================================

create or replace function app.approve_cycle_count_variance(
  p_scope_item_id uuid,
  p_expected_version integer,
  p_reason text,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.cycle_count_scope_items
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_item app.cycle_count_scope_items;
  v_plan app.cycle_count_plans;
  v_last_observation app.cycle_count_observations;
  v_balance app.inventory_balances;
  v_movement app.inventory_movements;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required to approve a cycle count variance' using errcode = 'check_violation';
  end if;

  select * into v_item from app.cycle_count_scope_items where id = p_scope_item_id for update;
  if not found then
    raise exception 'scope_item_not_found: %', p_scope_item_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_item.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.wms_pick_record_scope_ok(p_actor_auth_user_id, v_item.warehouse_id, v_item.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot approve scope item %', p_actor_auth_user_id, p_scope_item_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_item.tenant_id, v_item.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped to approve scope item %', p_actor_auth_user_id, p_scope_item_id using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent replay short-circuit -- only after authority is confirmed above, never
  -- before. Never re-posts a second ledger movement for an already-adjusted item.
  if v_item.status = 'adjusted' and v_item.adjustment_movement_id is not null then
    return v_item;
  end if;

  if v_item.status <> 'pending_review' then
    raise exception 'task_not_pending_review: scope item % is % -- only a pending_review item may be approved', p_scope_item_id, v_item.status using errcode = 'check_violation';
  end if;
  if v_item.record_version <> p_expected_version then
    raise exception 'stale_version: cycle count scope item % expected version % but found %', p_scope_item_id, p_expected_version, v_item.record_version using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalid_reason: a non-empty reason is required to approve a cycle count variance' using errcode = 'check_violation';
  end if;

  select * into v_plan from app.cycle_count_plans where id = v_item.plan_id;

  if v_plan.requires_separate_approver then
    select * into v_last_observation from app.cycle_count_observations
      where scope_item_id = p_scope_item_id
      order by attempt_number desc
      limit 1;
    -- ISS-2026-213 fix: coalesce(..., true) -- a null v_last_observation.counted_by_
    -- auth_user_id (structurally unreachable today, see this migration's own header) now
    -- denies rather than silently passing.
    if found and coalesce(v_last_observation.counted_by_auth_user_id = p_actor_auth_user_id, true) then
      raise exception 'self_approval_not_allowed: identity % submitted the most recent count for scope item % and may not also approve its own variance', p_actor_auth_user_id, p_scope_item_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  -- Design note 4: stale-snapshot detection -- re-lock the CURRENT balance row and
  -- compare its live record_version against the snapshot's own captured version.
  select * into v_balance from app.inventory_balances where id = v_item.snapshot_balance_id for update;
  if not found then
    raise exception 'balance_not_found: snapshot balance % no longer exists', v_item.snapshot_balance_id using errcode = 'no_data_found';
  end if;
  if v_balance.record_version <> v_item.snapshot_record_version then
    raise exception 'balance_changed_since_snapshot: balance % has changed since scope item %''s own snapshot was taken (expected version %, found %) -- cancel this scope item and refreeze rather than post a now-incorrect adjustment', v_item.snapshot_balance_id, p_scope_item_id, v_item.snapshot_record_version, v_balance.record_version
      using errcode = 'check_violation';
  end if;

  -- The one and only place a cycle count ever changes on_hand -- via the canonical
  -- app.post_inventory_movement primitive, never a direct balance write (Prompt 239
  -- section 24, this task's own objective).
  v_movement := app.post_inventory_movement(
    v_item.tenant_id, v_item.warehouse_id, 'adjustment', 'cycle_count', p_scope_item_id, p_idempotency_key, p_reason,
    jsonb_build_array(jsonb_build_object(
      'owner_account_id', v_item.owner_account_id, 'item_master_id', v_item.item_master_id, 'location_id', v_item.location_id,
      'uom_code', v_item.uom_code, 'signed_quantity', v_item.variance_quantity, 'lot_number', v_item.lot_number, 'serial_number', v_item.serial_number, 'status', 'on_hand'
    )),
    p_actor_auth_user_id, p_actor_label
  );

  -- Findings review (HIGH #4): app.post_inventory_movement's own idempotency dedups
  -- purely on (tenant_id, idempotency_key) -- it has no way to know this call's own
  -- scope item. If p_idempotency_key was already used by a DIFFERENT scope item's
  -- approval, the call above silently returns THAT item's already-posted movement
  -- unchanged. Attaching it to the CURRENT item here would mark it adjusted with a
  -- movement that reflects a completely different item/location/lot/quantity, and its
  -- own real variance would never be posted -- reject instead, exactly like a genuine
  -- idempotency-key collision anywhere else in this migration.
  if v_movement.source_type <> 'cycle_count' or v_movement.source_id <> p_scope_item_id then
    raise exception 'idempotency_key_conflict: idempotency key % was already used by a different movement (source_type=%, source_id=%), not scope item %', p_idempotency_key, v_movement.source_type, v_movement.source_id, p_scope_item_id
      using errcode = 'unique_violation';
  end if;

  update app.cycle_count_scope_items set
    adjustment_movement_id = v_movement.id,
    status = 'adjusted',
    reviewed_by_auth_user_id = p_actor_auth_user_id,
    reviewed_by_label = p_actor_label,
    reviewed_at = now(),
    review_reason = p_reason
  where id = p_scope_item_id
  returning * into v_item;

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_cycle_count_variance',
    'app.cycle_count_scope_items', v_item.id, 'success', p_reason, null,
    jsonb_build_object('movement_id', v_movement.id, 'variance_quantity', v_item.variance_quantity)
  );

  return v_item;
end;
$$;

comment on function app.approve_cycle_count_variance is
  'ATW-020: pending_review -> adjusted, posting exactly one app.post_inventory_movement (movement_type=adjustment, source_type=cycle_count, design note 4/8) -- never a direct balance write. Idempotent: a same-item retry after success returns the identical row unchanged, never re-posts. Rejects self_approval_not_allowed when the plan requires a separate approver and the acting identity submitted the most recent count. Rejects balance_changed_since_snapshot if the underlying balance moved between freeze and approval. Rejects idempotency_key_conflict if p_idempotency_key was already used by a DIFFERENT scope item''s approval -- never attaches another item''s movement to this one. ISS-2026-213 fix (Track B Batch 7): the self_approval_not_allowed check''s own equality against the nullable counted_by_auth_user_id now uses coalesce(..., true).';

-- ===========================================================================
-- 3. app.reject_cycle_count_variance -- identical self-approval check, same
--    nullable column. Body verbatim from 20260730270000, single comparison-operator
--    change.
-- ===========================================================================

create or replace function app.reject_cycle_count_variance(
  p_scope_item_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.cycle_count_scope_items
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_item app.cycle_count_scope_items;
  v_plan app.cycle_count_plans;
  v_last_observation app.cycle_count_observations;
begin
  select * into v_item from app.cycle_count_scope_items where id = p_scope_item_id for update;
  if not found then
    raise exception 'scope_item_not_found: %', p_scope_item_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_item.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.wms_pick_record_scope_ok(p_actor_auth_user_id, v_item.warehouse_id, v_item.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot reject scope item %', p_actor_auth_user_id, p_scope_item_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_item.tenant_id, v_item.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped to reject scope item %', p_actor_auth_user_id, p_scope_item_id using errcode = 'insufficient_privilege';
  end if;

  if v_item.status <> 'pending_review' then
    raise exception 'task_not_pending_review: scope item % is % -- only a pending_review item may be rejected', p_scope_item_id, v_item.status using errcode = 'check_violation';
  end if;
  if v_item.record_version <> p_expected_version then
    raise exception 'stale_version: cycle count scope item % expected version % but found %', p_scope_item_id, p_expected_version, v_item.record_version using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalid_reason: a non-empty reason is required to reject a cycle count variance' using errcode = 'check_violation';
  end if;

  select * into v_plan from app.cycle_count_plans where id = v_item.plan_id;
  if v_plan.requires_separate_approver then
    select * into v_last_observation from app.cycle_count_observations
      where scope_item_id = p_scope_item_id
      order by attempt_number desc
      limit 1;
    -- ISS-2026-213 fix: coalesce(..., true) -- see app.approve_cycle_count_variance's own
    -- identical fix above, applied here to its sibling reject path.
    if found and coalesce(v_last_observation.counted_by_auth_user_id = p_actor_auth_user_id, true) then
      raise exception 'self_approval_not_allowed: identity % submitted the most recent count for scope item % and may not also reject its own variance', p_actor_auth_user_id, p_scope_item_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  -- Design note 7: reviewed_by_auth_user_id/reviewed_at/review_reason are reserved for
  -- a real adjusted resolution (cycle_count_scope_items_adjusted_requires_review_check)
  -- -- never set here. Who rejected and why is captured in the audit event below.
  update app.cycle_count_scope_items set status = 'recount_required' where id = p_scope_item_id returning * into v_item;

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'reject_cycle_count_variance',
    'app.cycle_count_scope_items', v_item.id, 'success', p_reason, null, null
  );

  return v_item;
end;
$$;

comment on function app.reject_cycle_count_variance is
  'ATW-020: pending_review -> recount_required (design note 7) -- sends the item back for a fresh count rather than silently discarding the variance. Never sets reviewed_by/reviewed_at/review_reason (reserved for a real adjusted resolution). ISS-2026-213 fix (Track B Batch 7): the self_approval_not_allowed check''s own equality against the nullable counted_by_auth_user_id now uses coalesce(..., true).';

-- ===========================================================================
-- 4. app.approve_dedicated_deployment_qualification -- self-approval check against
--    tenant_deployment_records.created_by_auth_user_id (nullable). Body verbatim from
--    20260808000000, single comparison-operator change.
-- ===========================================================================

create or replace function app.approve_dedicated_deployment_qualification(
  p_deployment_record_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.tenant_deployment_records
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_record app.tenant_deployment_records;
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_record from app.tenant_deployment_records where id = p_deployment_record_id and status = 'pending_qualification' for update;
  if not found then
    raise exception 'deployment_record_not_pending_qualification: % is not a pending-qualification deployment record', p_deployment_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_record.tenant_id, 'DEPLOY', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks DEPLOY:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_record.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-213 fix: coalesce(..., true) -- a null v_record.created_by_auth_user_id
  -- (structurally unreachable today, see this migration's own header) now denies rather
  -- than silently passing.
  if coalesce(v_record.created_by_auth_user_id = p_actor_auth_user_id, true) then
    raise exception 'deployment_self_approval_forbidden: identity % cannot approve a dedicated deployment qualification they themselves requested', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.tenant_deployment_records
  set status = 'qualified', approved_by_auth_user_id = p_actor_auth_user_id, approved_by = p_actor_label, approved_at = now()
  where id = p_deployment_record_id
  returning * into v_record;

  perform app.capture_audit_event(
    v_record.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_dedicated_deployment_qualification',
    'app.tenant_deployment_records', v_record.id, 'success', null, null, to_jsonb(v_record)
  );

  return v_record;
end;
$$;

comment on function app.approve_dedicated_deployment_qualification is
  'IAE-032: "Provisioning requires contract/security/CTO approval" (Prompt 360 §24) -- DEPLOY:Approve is a real, separate authority tier from DEPLOY:Configure (which merely requested the qualification); the underlying app.principal_memberships/app.role_assignments authority model does not by itself prevent one identity from holding both, so self-approval is additionally forbidden explicitly here (deployment_self_approval_forbidden) AND at the tenant_deployment_records_no_self_approval CHECK-constraint level, mirroring IAE-031''s own legal_holds_no_self_release precedent. ISS-2026-213 fix (Track B Batch 7): the deployment_self_approval_forbidden check''s own equality against the nullable created_by_auth_user_id now uses coalesce(..., true).';

-- ===========================================================================
-- 5. app.approve_region_assignment -- self-approval check against
--    tenant_region_assignments.created_by_auth_user_id (nullable). Body verbatim from
--    20260808100000, single comparison-operator change.
-- ===========================================================================

create or replace function app.approve_region_assignment(
  p_region_assignment_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.tenant_region_assignments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_record app.tenant_region_assignments;
  v_decision app.rbac_decision;
  v_category text;
  v_supported boolean;
  v_has_exception boolean;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_record from app.tenant_region_assignments where id = p_region_assignment_id and status = 'pending_review' for update;
  if not found then
    raise exception 'region_assignment_not_pending_review: % is not a pending-review region assignment', p_region_assignment_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_record.tenant_id, 'DEPLOY', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks DEPLOY:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_record.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-213 fix: coalesce(..., true) -- a null v_record.created_by_auth_user_id
  -- (structurally unreachable today, see this migration's own header) now denies rather
  -- than silently passing.
  if coalesce(v_record.created_by_auth_user_id = p_actor_auth_user_id, true) then
    raise exception 'region_self_approval_forbidden: identity % cannot approve a region assignment they themselves requested', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  if app.resolve_tenant_deployment_type(v_record.tenant_id) <> 'dedicated' then
    raise exception 'region_requires_dedicated_deployment: tenant % has no active dedicated deployment (RPD-013 -- dedicated region requires dedicated deployment)', v_record.tenant_id
      using errcode = 'check_violation';
  end if;

  foreach v_category in array array['database', 'secrets', 'backup', 'files', 'observability', 'ai_provider']
  loop
    select supported into v_supported from app.region_service_capabilities where region_code = v_record.region_code and service_category = v_category;
    if not coalesce(v_supported, false) then
      select exists(
        select 1 from app.region_capability_exceptions
        where region_assignment_id = v_record.id and service_category = v_category
      ) into v_has_exception;
      if not v_has_exception then
        raise exception 'region_capability_gap_unresolved: % is not supported in % and no exception has been registered', v_category, v_record.region_code
          using errcode = 'check_violation';
      end if;
    end if;
  end loop;

  update app.tenant_region_assignments
  set status = 'approved', approved_by_auth_user_id = p_actor_auth_user_id, approved_by = p_actor_label, approved_at = now()
  where id = p_region_assignment_id
  returning * into v_record;

  perform app.capture_audit_event(
    v_record.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_region_assignment',
    'app.tenant_region_assignments', v_record.id, 'success', null, null, to_jsonb(v_record)
  );

  return v_record;
end;
$$;

comment on function app.approve_region_assignment is
  'IAE-033: real, structural enforcement of RPD-013 (dedicated region requires dedicated deployment, design decision 3) and Prompt 361''s own "do not claim multi-region availability without deployed architecture" rule (design decision 4) -- approval is impossible until every one of the six fixed service categories is either genuinely supported in the target region or has a real, separately-registered DEPLOY:Approve exception. ISS-2026-213 fix (Track B Batch 7): the region_self_approval_forbidden check''s own equality against the nullable created_by_auth_user_id now uses coalesce(..., true).';

-- ===========================================================================
-- 6. app.approve_warehouse_billing_event -- self-approval check against
--    warehouse_billing_events.reviewed_by_auth_user_id (nullable). Base body corrected
--    to its TRUE latest redefinition, 20260730520000_harden_stale_version_no_op_and_
--    swallowed_idempotency_guard.sql (exhaustive redefinition search caught a first
--    draft of this fix mistakenly based on the stale 20260730300000 origin body, which
--    is MISSING that migration's own ATW-032/ISS-2026-034 lost-update guard -- the
--    `if not found then raise stale_version ...` block immediately after the UPDATE,
--    closing a race where a losing concurrent UPDATE fell through silently with a NULL
--    composite and a fabricated 'success' audit row instead of the stale_version error
--    its own contract already promises). That guard is preserved verbatim below; only
--    the self-approval comparison operator is changed.
-- ===========================================================================

create or replace function app.approve_warehouse_billing_event(
  p_event_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.warehouse_billing_events
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_event app.warehouse_billing_events;
begin
  select * into v_event from app.warehouse_billing_events where id = p_event_id for update;
  if not found then
    raise exception 'warehouse_billing_event_not_found: %', p_event_id using errcode = 'no_data_found';
  end if;

  -- A governed release-to-Finance decision -- OPS:Override.
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_event.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_event.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.wms_pick_record_scope_ok(p_actor_auth_user_id, v_event.warehouse_id, v_event.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot approve billing event %', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_event.tenant_id, v_event.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped for billing event %', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;

  if v_event.status <> 'reviewed' then
    raise exception 'invalid_transition: billing event % is % -- only reviewed may be approved', p_event_id, v_event.status using errcode = 'check_violation';
  end if;
  if v_event.record_version <> p_expected_version then
    raise exception 'stale_version: billing event % expected version % but found %', p_event_id, p_expected_version, v_event.record_version using errcode = 'check_violation';
  end if;
  -- Segregation of duties (mirrors ATW-020's own established self_approval_not_allowed
  -- pattern): the same identity that reviewed an event may not also approve it.
  -- ISS-2026-213 fix: coalesce(..., true) -- a null v_event.reviewed_by_auth_user_id
  -- (structurally unreachable today, see this migration's own header) now denies rather
  -- than silently passing.
  if coalesce(v_event.reviewed_by_auth_user_id = p_actor_auth_user_id, true) then
    raise exception 'self_approval_not_allowed: identity % reviewed billing event % and may not also approve it', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;

  update app.warehouse_billing_events set
    status = 'approved', approved_by_auth_user_id = p_actor_auth_user_id, approved_by_label = p_actor_label, approved_at = now()
  where id = p_event_id and record_version = p_expected_version
  returning * into v_event;
  -- ATW-032 (ISS-2026-034), preserved verbatim from the true latest body: the version
  -- predicate above already PREVENTS the lost update -- the loser's UPDATE simply
  -- matches no row -- but execution must not fall straight through with a NULL
  -- composite (which would both fabricate a 'success' audit row with a NULL tenant_id
  -- and hand the caller an all-NULL record instead of this function's own documented
  -- stale_version error).
  if not found then
    raise exception 'stale_version: approve_warehouse_billing_event target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_event.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_warehouse_billing_event',
    'app.warehouse_billing_events', v_event.id, 'success', null, null, null
  );

  return v_event;
end;
$$;

comment on function app.approve_warehouse_billing_event is
  'ATW-020 sibling: mirrors app.approve_cycle_count_variance''s own self_approval_not_allowed segregation-of-duties pattern -- the identity that reviewed a billing event may not also approve it. ATW-032 (ISS-2026-034): a concurrently-lost UPDATE race re-raises stale_version rather than falling through with a NULL composite. ISS-2026-213 fix (Track B Batch 7): the self_approval_not_allowed check''s own equality against the nullable reviewed_by_auth_user_id now uses coalesce(..., true).';

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries its own
-- explicit `revoke execute on all functions in schema app from public` statement before
-- its final grants, the standing per-migration convention since PLT-118. CREATE OR
-- REPLACE FUNCTION does not itself drop an existing grant, but every grant below is
-- re-asserted explicitly, verbatim from each function's own current live grant
-- statement, rather than relying on that Postgres behavior implicitly.
revoke execute on all functions in schema app from public;

grant execute on function app.decide_approval_step(uuid, text, uuid, text, text) to service_role;
grant execute on function app.approve_cycle_count_variance(uuid, integer, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.reject_cycle_count_variance(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.approve_dedicated_deployment_qualification(uuid, uuid, text) to authenticated, service_role;
grant execute on function app.approve_region_assignment(uuid, uuid, text) to authenticated, service_role;
grant execute on function app.approve_warehouse_billing_event(uuid, integer, uuid, text) to authenticated, service_role;
