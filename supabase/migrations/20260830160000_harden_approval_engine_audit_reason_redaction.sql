-- ISS-2026-093 (docs/runtime/KNOWN_ISSUES.md, Medium) -- `app.cancel_approval_request`, the
-- shared cross-domain PLT-123 approval-engine primitive, passes its caller-supplied
-- `p_reason` straight into `app.audit_logs.reason`, which `app.query_audit_logs` exposes to
-- ANY plain `tenant_admin` with zero domain permission. Live-reproduced when the entry was
-- filed: cancelling an onboarding case with reason `'reorg cancelled the exit'` produced an
-- audit row carrying that text verbatim.
--
-- The entry disclosed it rather than fixing it because PLT-123 is Platform Core
-- infrastructure called by Finance, Commercial, Procurement and HR alike, and widening the
-- blast radius was outside a Phase-7-HR checkpoint's charter. Under `ADR-0027` Part A that
-- constraint no longer applies, so it is fixed here at the engine.
--
-- ---------------------------------------------------------------------------------------
-- Two corrections to the entry's own premise, both found by checking rather than assuming
-- ---------------------------------------------------------------------------------------
--
-- **1. It is two functions, not one.** `app.decide_approval_step` -- the same engine's
-- decision primitive, and by far the more frequently called of the two -- passes `p_reason`
-- raw in exactly the same shape. The entry names only `cancel_approval_request`. Fixing one
-- and leaving its sibling would have closed the smaller half of the same defect.
--
-- **2. The two halves are not equally severe, and the entry's reasoning fits the one it
-- does not name.** Checked directly against the approval engine's own grants:
--
--   * `app.approval_decisions` (where `decide_approval_step`'s reason is durably stored)
--     carries **no `authenticated` grant at all** -- `service_role` only. So for that
--     function, `app.audit_logs` genuinely was the one path by which a plain `tenant_admin`
--     could read an approver's stated reason for rejecting something. **That is a real
--     narrowing.**
--   * `app.approval_requests` (where `cancel_approval_request`'s reason lands, in
--     `ended_reason`) carries `grant select ... to authenticated` on the whole table, and its
--     RLS policy admits any active member of the tenant. So `ended_reason` is **already**
--     readable by every active tenant member -- a broader audience than the tenant_admins the
--     entry is concerned about. Removing it from the audit log there is consistency and
--     defence-in-depth, and it is stated as that rather than dressed up as a narrowing it is
--     not.
--
-- The genuinely wider exposure for the cancellation reason is therefore the **table grant**,
-- not the audit log. Changing a shared PLT-123 table grant would ripple through every
-- domain's read paths and every domain's regression suite; that is a real decision, not a
-- hardening tweak, and it is registered as `ISS-2026-305` rather than made quietly here.
--
-- ---------------------------------------------------------------------------------------
-- Why the jsonb snapshot mattered too
-- ---------------------------------------------------------------------------------------
--
-- `app.capture_audit_event` runs both payloads through `app.redact_audit_payload`, which
-- matches by KEY NAME against `(secret|password|token|key|authorization|cookie|ssn|npwp|
-- bank|account_number|salary|payroll)`. `ended_reason` matches none of those. So
-- `cancel_approval_request`'s `to_jsonb(v_updated)` carried the reason verbatim into
-- `after_value`, and passing `null` for the scalar argument alone would have closed one
-- vector while leaving the other untouched -- a fix that reads as complete and is not. The
-- established answer in this repository is a purpose-built non-PII projection
-- (`app.leave_request_audit_projection`, HRT-280/293), and this migration adds the same for
-- approval requests.
--
-- `app.decide_approval_step` needs no projection: `app.approval_request_steps` has no reason
-- column of its own, so its two snapshots never carried one. Checked rather than assumed.
--
-- Both function bodies below are MECHANICALLY EXTRACTED copies of their current
-- definitions (`20260827130000` and `20260828160000` respectively), with only the
-- `capture_audit_event` call changed. Nothing is retyped: between them they carry the
-- C-21 lock-ordering fix, `ISS-2026-048`/`049`'s not-found-shaped tenant-disclosure fixes
-- and `ISS-2026-213`'s null-actor self-approval guard, and re-stating ~170 lines of that by
-- hand to change two arguments is exactly the transcription hazard this repository keeps
-- meeting.
--
-- Per `ERR-2026-004`: explicit `revoke execute on all functions in schema app from public;`
-- before the final grants. No already-applied migration is edited.

-- ===========================================================================
-- 1. The non-PII projection.
-- ===========================================================================

create function app._approval_request_audit_projection(p_request app.approval_requests)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'id', p_request.id,
    'tenantId', p_request.tenant_id,
    'entityType', p_request.entity_type,
    'entityId', p_request.entity_id,
    'pattern', p_request.pattern,
    'status', p_request.status,
    'requestedByAuthUserId', p_request.requested_by_auth_user_id,
    'startedAt', p_request.started_at,
    'endedAt', p_request.ended_at,
    'recordVersion', p_request.record_version
  );
$$;

comment on function app._approval_request_audit_projection is
  'ISS-2026-093: the audit-safe shape of an approval request -- every field EXCEPT ended_reason, the caller-supplied free text. app.redact_audit_payload matches by key name and ended_reason matches none of its patterns, so to_jsonb() carried that text verbatim into app.audit_logs.after_value. Mirrors app.leave_request_audit_projection (HRT-280/293), the shape this repository already settled on for exactly this problem. A new field added to app.approval_requests will NOT appear here until someone adds it deliberately -- which is the point: a projection that auto-included everything would re-open this the next time a free-text column is added.';

-- ===========================================================================
-- 2. app.cancel_approval_request -- scalar reason nulled, snapshots projected.
-- ===========================================================================

create or replace function app.cancel_approval_request(
  p_request_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_reason text
)
returns app.approval_requests
language plpgsql
as $$
declare
  v_request app.approval_requests;
  v_updated app.approval_requests;
begin
  select * into v_request from app.approval_requests where id = p_request_id;
  if not found then
    raise exception 'approval_request_not_found: no approval request %', p_request_id
      using errcode = 'no_data_found';
  end if;

  -- ISS-2026-048 extension fix (Track B Batch 2): a genuine stranger to
  -- v_request.tenant_id (zero membership, not Supreme Admin -- exactly what
  -- app.check_approval_request_authority already tests) now gets the same
  -- not-found error a nonexistent request id produces, never learning this
  -- request's real tenant_id via a tenant-echoing insufficient_authority error.
  if not app.check_approval_request_authority(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'approval_request_not_found: no approval request %', p_request_id
      using errcode = 'no_data_found';
  end if;
  if v_request.status <> 'pending' then
    raise exception 'approval_request_not_pending: request % is %, only a pending request can be cancelled', p_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  -- Batch 260 review (C-21, HIGH, live-reproduced): app.approval_request_steps is now
  -- locked BEFORE app.approval_requests -- matching app.decide_approval_step's own
  -- order exactly (see this section's own header comment above). Final state is
  -- byte-for-byte identical to before; only lock ACQUISITION order changed.
  update app.approval_request_steps set status = 'skipped' where request_id = p_request_id and status in ('pending', 'active');
  update app.approval_requests set status = 'cancelled', ended_at = now(), ended_reason = p_reason where id = p_request_id returning * into v_updated;

  -- ISS-2026-093: the scalar reason argument is now null, and the before/after snapshots
  -- go through app._approval_request_audit_projection instead of to_jsonb -- which carried
  -- ended_reason verbatim, so passing null alone would have closed one vector and left the
  -- other wide open. Mirrors app.leave_request_audit_projection (HRT-280/293), the shape
  -- this repository already settled on for exactly this.
  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_approval_request',
    'app.approval_requests', v_updated.id, 'success', null,
    app._approval_request_audit_projection(v_request), app._approval_request_audit_projection(v_updated)
  );

  return v_updated;
end;
$$;

comment on function app.cancel_approval_request is
  'PLT-123: cancels a pending approval request and skips every still-pending/active step. Carries forward the Batch 260 C-21 lock-ordering fix and ISS-2026-048''s not-found-shaped tenant-disclosure fix unchanged. ISS-2026-093: the audit-log reason argument is now null and both snapshots go through app._approval_request_audit_projection -- ended_reason lives only in app.approval_requests. Note honestly: that column is readable by any active tenant member via the table''s own grant, so this is defence-in-depth rather than a real narrowing; the wider exposure is the grant itself, registered as ISS-2026-305.';

-- ===========================================================================
-- 3. app.decide_approval_step -- scalar reason nulled. The real narrowing.
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

  -- ISS-2026-093 (widened): the scalar reason argument is now null. This is the genuine
  -- narrowing of the two -- p_reason is durably stored in app.approval_decisions.reason,
  -- which carries NO `authenticated` grant at all (service_role only), so app.audit_logs
  -- was the one path by which a plain tenant_admin with zero domain permission could read
  -- an approver's stated reason for rejecting something. The two jsonb snapshots need no
  -- projection: app.approval_request_steps has no reason column of its own.
  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_approval_step',
    'app.approval_request_steps', p_request_step_id, 'success', null, to_jsonb(v_step), to_jsonb(v_updated_step)
  );

  select * into v_updated_step from app.approval_request_steps where id = p_request_step_id;
  return v_updated_step;
end;
$$;

comment on function app.decide_approval_step is
  'PLT-123: the core decision engine. Carries forward every prior hardening unchanged -- the reject-requires-reason gate, ISS-2026-049''s not-found-shaped tenant-disclosure fix, and ISS-2026-213''s coalesce null-actor self-approval guard. ISS-2026-093 (widened beyond that entry''s own naming): the audit-log reason argument is now null. This is the genuine narrowing of the pair -- p_reason is durably stored in app.approval_decisions.reason, a table with NO authenticated grant at all, so app.audit_logs was the one path by which a plain tenant_admin with zero domain permission could read an approver''s stated reason for rejecting something. No projection is needed here: app.approval_request_steps has no reason column.';

revoke execute on all functions in schema app from public;

-- service_role only, and underscore-prefixed: this is an internal audit helper, never a
-- client-facing read. This repository's convention is that `app._*` functions are internal
-- and exempt from the public.* wrapper requirement -- which is exactly what
-- scripts/db-tests/public-api-wrapper-regression.sql enforces, and what caught the first
-- draft of this migration naming it without the prefix.
grant execute on function app._approval_request_audit_projection(app.approval_requests) to service_role;
grant execute on function app.cancel_approval_request(uuid, uuid, text, text) to service_role;
grant execute on function app.decide_approval_step(uuid, text, uuid, text, text) to service_role;
