-- HDN-386 (Step 15, Prompt 386, Full-System Hardening Integrated Verification) --
-- bounded repair authorized by this checkpoint's own charter ("performs only
-- authorized bounded repairs or documents handoff"), closing the two Critical/High
-- findings both explicitly named "Required of `HDN-386`" in `BLOCKER_LEDGER.md`:
--
-- `HDN-BLK-020` (Critical, `ISS-2026-229`, found at `HDN-377`'s own Tier C):
-- `app.audit_logs.legal_hold` was enforced nowhere -- neither the native flag nor the
-- generic (IAE-031) `app._is_under_legal_hold()` mechanism was checked before physical
-- deletion of the platform's own canonical audit trail. Live-forced at `HDN-377`:
-- setting `legal_hold=true` via `app.supreme_admin_mutate_audit_log`, then calling
-- `app.supreme_admin_delete_audit_log` on the same row, succeeded -- the row was gone,
-- with zero distinct trace that an active legal hold was overridden.
--
-- `HDN-BLK-021` (High, `ISS-2026-230`, found at the same review): `app.tenants.legal_
-- hold`'s own native trigger (`app.enforce_tenant_status_transition`) correctly blocks
-- termination on the NATIVE flag, but was never bridged to the GENERIC mechanism in
-- either direction -- live-forced: a generic hold placed via `app.request_legal_hold`
-- (scope `app.tenants`) did NOT prevent `app.transition_tenant_status(...,
-- 'terminated', ...)` from succeeding.
--
-- Both entries bundle this fix with `HDN-BLK-018`'s own separate, much larger,
-- systemic append-only-guard rollout (~90+ tables, only 13 currently covered) --
-- deliberately NOT attempted here. That rollout is a genuine, wide-blast-radius design
-- decision (which tables get which invariant, in what order, with what regression
-- shape) squarely outside a bounded-repair pass; it remains registered, unchanged,
-- owner `HDN-387`. This migration closes only the two SPECIFIC, reproducible,
-- Critical/High bypasses named above, mirroring `HDN-377`'s own already-proven,
-- already-reviewed fix pattern for the identical defect shape on `app.files`
-- (`app.protect_files_legal_hold_from_deletion`,
-- `20260814100000_harden_storage_signed_url_audit_tierc_fixes.sql`) rather than
-- inventing a new one.
--
-- `HDN-BLK-023` (Critical, `app.set_integration_connection_status`'s own independent
-- bypass) and `HDN-BLK-024` (High, `is_high_risk_action` wiring gap) are NOT attempted
-- here -- both are explicit, self-disclosed genuine design decisions ("the correct fix
-- requires a genuine design decision... touching a shared, heavily-reused primitive,
-- exceeding what a Tier C review pass should rush", `HDN-378.md`), not mechanical,
-- bounded, already-proven-pattern repairs. Formally handed to `HDN-387` with a
-- concrete remediation scope in this checkpoint's own build log, per the same
-- mechanical-fix-vs-genuine-design-decision judgment this session has applied
-- throughout Step 15 (e.g. `HDN-385`'s own duplicate-swallow fix vs. its registered
-- un-keyed-duplicate-detection gap).

-- ===========================================================================
-- Part 1: bridge app.audit_logs and app.tenants into the generic (IAE-031) legal-hold
-- primitive, mirroring the existing app.files bridge branch exactly.
-- ===========================================================================

create or replace function app._is_under_legal_hold(p_tenant_id uuid, p_record_class text, p_source_table text, p_source_record_id uuid)
returns boolean
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select
    exists (
      select 1 from app.legal_holds
      where status = 'active' and scope_record_table = lower(trim(p_source_table)) and scope_record_id = p_source_record_id
    )
    or
    exists (
      select 1 from app.legal_holds
      where tenant_id = p_tenant_id and record_class = p_record_class and status = 'active'
        and scope_record_table is null and scope_record_id is null
    )
    or
    (
      lower(trim(p_source_table)) = 'app.files'
      and exists (select 1 from app.files where id = p_source_record_id and legal_hold = true)
    )
    or
    (
      lower(trim(p_source_table)) = 'app.audit_logs'
      and exists (select 1 from app.audit_logs where id = p_source_record_id and legal_hold = true)
    )
    or
    (
      lower(trim(p_source_table)) = 'app.tenants'
      and exists (select 1 from app.tenants where id = p_source_record_id and legal_hold = true)
    );
$$;

comment on function app._is_under_legal_hold is
  'IAE-031: internal-only primitive, no actor/authority parameter -- never granted to anon/authenticated. A specific-record hold matches on (source_table, source_record_id) ALONE, independent of the caller''s own tenant_id/record_class claim (HDN-373 Tier C review fix); a whole-class hold necessarily still matches on the caller''s own (tenant_id, record_class) declaration, since there is no specific record to anchor against instead. HDN-377 (Storage and Signed URL Audit): also true whenever source_table=''app.files'' and that file''s own legal_hold column is set -- bridges PLT-128''s file-native hold flag into this generic cross-domain primitive. HDN-377 Tier C fix: p_source_table is normalized (lower/trim) before comparison, matching app.request_legal_hold()''s own write-time normalization -- a case/whitespace variant no longer silently fails to match a real, active hold. HDN-386 (Full-System Hardening Integrated Verification, bounded repair closing HDN-BLK-020/021): also true whenever source_table=''app.audit_logs'' or ''app.tenants'' and that row''s own native legal_hold column is set -- bridges PLT-116''s audit-log-native and PLT-105''s tenant-native hold flags into this same generic primitive, the identical shape as the app.files bridge above.';

-- ===========================================================================
-- Part 2: app.audit_logs schema-level DELETE backstop, mirroring
-- app.protect_files_legal_hold_from_deletion exactly. app.audit_logs has no
-- soft-delete column (its own deletion is always the physical DELETE performed by
-- app.supreme_admin_delete_audit_log), so only BEFORE DELETE is needed -- there is no
-- UPDATE-based soft-delete transition to also guard, unlike app.files.
-- ===========================================================================

create function app.protect_audit_logs_legal_hold_from_deletion()
returns trigger
language plpgsql
as $$
declare
  v_actor uuid;
  v_held boolean;
begin
  v_actor := auth.uid();
  v_held := OLD.legal_hold or app._is_under_legal_hold(OLD.tenant_id, 'audit_security', 'app.audit_logs', OLD.id);

  if not v_held then
    return OLD;
  end if;

  if not app.is_supreme_admin(v_actor) then
    raise exception 'audit_log_legal_hold_blocks_deletion: audit_logs row % is under legal hold (%), it cannot be physically deleted -- app.supreme_admin_delete_audit_log already requires Supreme Admin, this is the schema-level backstop for a direct DELETE bypassing that RPC entirely', OLD.id, OLD.legal_hold_reason
      using errcode = 'insufficient_privilege';
  end if;

  -- RPD-022's disclosed residual risk: Supreme Admin retains absolute CRUD and may
  -- still delete a legally-held audit_logs row (this codebase never claims audit
  -- records are immutable or tamper-proof, `20260716113048_create_audit_trail.sql`
  -- line 249-251). What HDN-BLK-020 actually closes is the SILENCE -- before this
  -- fix, app.supreme_admin_delete_audit_log's own generic audit event gave no
  -- distinct trace that an active legal hold was overridden. This branch captures
  -- that override honestly and distinctly, mirroring app.files' own identical
  -- override-disclosure pattern, rather than attempting to make Supreme Admin's own
  -- documented absolute-CRUD authority unreachable (out of scope, and contrary to
  -- RPD-022 as written).
  perform app.capture_audit_event(
    OLD.tenant_id, v_actor, 'supreme_admin_absolute_crud', 'delete_legally_held_audit_log',
    'app.audit_logs', OLD.id, 'success',
    'RPD-022 absolute-CRUD exception invoked (best-effort evidence, not a preventive control) -- app.audit_logs is otherwise blocked from physical deletion while under legal hold, native or generic (app.legal_holds)',
    to_jsonb(OLD), null
  );

  return OLD;
end;
$$;

comment on function app.protect_audit_logs_legal_hold_from_deletion is
  'HDN-386 (Full-System Hardening Integrated Verification): BEFORE DELETE guard for app.audit_logs, closing HDN-BLK-020 (Critical). Checks BOTH the PLT-116-native app.audit_logs.legal_hold flag AND the bridged generic (IAE-031) app._is_under_legal_hold(), mirroring app.protect_files_legal_hold_from_deletion exactly. A non-Supreme-Admin caller (including a raw service_role DELETE with no session-bound actor, which is the exact bypass HDN-BLK-020 live-forced) is blocked outright; a genuine Supreme Admin RPC caller may still override per RPD-022''s disclosed absolute-CRUD residual risk, but the override is now honestly and distinctly captured rather than silent.';

create trigger audit_logs_protect_legal_hold_from_deletion
  before delete on app.audit_logs
  for each row
  execute function app.protect_audit_logs_legal_hold_from_deletion();

-- ===========================================================================
-- Part 3: app.tenants -- bridge the GENERIC hold mechanism into the existing NATIVE
-- termination guard. Closes HDN-BLK-021's own live-forced reproduction directly: a
-- generic hold (app.request_legal_hold, scope 'app.tenants') did not prevent
-- app.transition_tenant_status(..., 'terminated', ...) from succeeding, because
-- app.enforce_tenant_status_transition only ever checked the native flag.
--
-- HDN-BLK-021's own second ask -- "decide whether a real RPC should set the native
-- flag at all going forward, or whether the generic mechanism alone should govern
-- tenants" -- is a genuine product/API-surface decision (does Legal/Compliance need a
-- first-class "hold this tenant" RPC, or is routing every tenant hold through the
-- already-existing generic app.request_legal_hold() sufficient going forward?), left
-- explicitly undecided here and registered for `HDN-387` rather than guessed at.
-- ===========================================================================

create or replace function app.enforce_tenant_status_transition()
returns trigger
language plpgsql
as $$
begin
  if new.canonical_status = old.canonical_status then
    return new;
  end if;

  if old.canonical_status = 'terminated' then
    raise exception 'invalid_tenant_transition: tenant % is terminated, no further transition is allowed', old.id
      using errcode = 'check_violation';
  end if;

  if not (
    (old.canonical_status = 'provisioning' and new.canonical_status in ('active', 'terminated'))
    or (old.canonical_status = 'active' and new.canonical_status in ('suspended', 'terminated'))
    or (old.canonical_status = 'suspended' and new.canonical_status in ('active', 'terminated'))
  ) then
    raise exception 'invalid_tenant_transition: % -> % is not a canonical transition', old.canonical_status, new.canonical_status
      using errcode = 'check_violation';
  end if;

  if new.canonical_status = 'terminated'
     and (old.legal_hold or app._is_under_legal_hold(old.id, 'operational', 'app.tenants', old.id))
  then
    raise exception 'invalid_tenant_transition: tenant % has an active legal hold (native or generic) and cannot be terminated', old.id
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

comment on function app.enforce_tenant_status_transition is
  'Blocks a tenant''s own canonical_status transition into ''terminated'' while under legal hold. HDN-386 (Full-System Hardening Integrated Verification, closing HDN-BLK-021, High): now checks BOTH the PLT-105-native app.tenants.legal_hold flag AND the bridged generic (IAE-031) app._is_under_legal_hold() -- previously only the native flag was checked, so a hold placed exclusively via the generic mechanism (app.request_legal_hold, scope app.tenants) did not block termination, live-forced at HDN-377''s own Tier C review. Whether a dedicated RPC should exist to set the native flag going forward, or whether the generic mechanism alone should govern tenant holds, remains an open product decision -- registered for HDN-387, not decided here.';

-- app.protect_audit_logs_legal_hold_from_deletion is a genuinely new function (the
-- other two are create-or-replace on already-existing functions, whose prior grants
-- persist across replace) -- strip the default PUBLIC EXECUTE grant Postgres applies
-- to any newly created function, matching this repository's own established
-- convention for every migration that creates a new function in schema app.
revoke execute on all functions in schema app from public;
