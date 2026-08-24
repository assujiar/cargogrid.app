-- HDN-386 (Step 15, Prompt 386, Full-System Hardening Integrated Verification) --
-- Tier C adversarial review fix pass. Four independent parallel Tier C lenses
-- (correctness re-derivation; schema-wide completeness sweep; ledger/documentation
-- consistency; attack-surface adversarial testing) ran against the first-round commit
-- (`114f86e`).
--
-- ===========================================================================
-- Attack-surface lens finding, CRITICAL, live-forced: `app.protect_audit_logs_legal_
-- hold_from_deletion` (first round, `HDN-BLK-020`'s own fix) was `BEFORE DELETE` only,
-- on the stated assumption that `app.audit_logs` has no soft-delete/UPDATE-based
-- deletion path unlike `app.files`. Live-forced, that assumption is correct as far as
-- it goes (there IS no `deleted_at`-style soft-delete column) -- but it missed a
-- distinct, equally real bypass: a raw `service_role` `UPDATE` (reachable by the
-- exact same actor class the DELETE trigger exists to guard against, since `app.
-- audit_logs` carries no other write grant) can, with zero trigger interference:
-- (1) null out `before_value`/`after_value`/`reason` on a held row, destroying its
-- informational content while the row itself survives; or (2) flip `legal_hold` back
-- to `false` directly, after which a follow-up `DELETE` succeeds outright -- fully
-- reproducing the exact "row gone, no distinct trace" failure mode `HDN-BLK-020` was
-- meant to close, just via UPDATE-then-DELETE instead of a bare DELETE.
--
-- This is the identical defect shape `HDN-377`'s own Tier C already found and fixed
-- once for `app.files` (`ISS-2026-226`, "the first round's own new BEFORE DELETE guard
-- trigger... never covers a soft-delete-shaped UPDATE path") -- reusing that
-- already-proven fix pattern here: widen the guard from `BEFORE DELETE` to `BEFORE
-- UPDATE OR DELETE`. `app.audit_logs` has no legitimate non-Supreme-Admin write path
-- at all (the only intended UPDATE caller, `app.supreme_admin_mutate_audit_log`,
-- already requires `is_supreme_admin`) -- so, unlike `app.files`' own narrower
-- "only the soft-delete transition" UPDATE guard, this one blocks ANY UPDATE of a held
-- row by a non-Supreme-Admin actor, not just a specific column transition.
-- ===========================================================================

create or replace function app.protect_audit_logs_legal_hold_from_deletion()
returns trigger
language plpgsql
as $$
declare
  v_actor uuid;
  v_held boolean;
begin
  -- Computed lazily, after this early return -- this trigger now fires on every
  -- UPDATE (not just DELETE), and auth.uid() raises on a session where request.jwt.
  -- claims was never set to valid JSON at all (e.g. a service-context caller with no
  -- JWT claims GUC), which the overwhelming majority of ordinary, non-hold-related
  -- UPDATEs on this table are (including app.supreme_admin_mutate_audit_log's own
  -- routine, unheld-row writes) -- mirrors app.protect_files_legal_hold_from_deletion's
  -- own identical lazy-computation discipline, adapted since app.audit_logs has no
  -- single column-transition to gate the early exit on the way app.files does.
  v_held := OLD.legal_hold or app._is_under_legal_hold(OLD.tenant_id, 'audit_security', 'app.audit_logs', OLD.id);

  if not v_held then
    if TG_OP = 'DELETE' then
      return OLD;
    end if;
    return NEW;
  end if;

  v_actor := auth.uid();
  if not app.is_supreme_admin(v_actor) then
    if TG_OP = 'DELETE' then
      raise exception 'audit_log_legal_hold_blocks_deletion: audit_logs row % is under legal hold (%), it cannot be physically deleted -- app.supreme_admin_delete_audit_log already requires Supreme Admin, this is the schema-level backstop for a direct DELETE bypassing that RPC entirely', OLD.id, OLD.legal_hold_reason
        using errcode = 'insufficient_privilege';
    else
      raise exception 'audit_log_legal_hold_blocks_deletion: audit_logs row % is under legal hold (%), it cannot be updated -- app.audit_logs has no legitimate non-Supreme-Admin write path at all, this is the schema-level backstop for a direct UPDATE (including clearing legal_hold itself, or nulling before_value/after_value/reason) that would otherwise defeat the DELETE guard or destroy the row''s own informational content in place', OLD.id, OLD.legal_hold_reason
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  -- RPD-022's disclosed residual risk: Supreme Admin retains absolute CRUD and may
  -- still delete or update a legally-held audit_logs row (this codebase never claims
  -- audit records are immutable or tamper-proof, `20260716113048_create_audit_trail.
  -- sql` line 249-251). What HDN-BLK-020 actually closes is the SILENCE -- before the
  -- first round's own fix, `app.supreme_admin_delete_audit_log`'s own generic audit
  -- event gave no distinct trace that an active legal hold was overridden; before this
  -- Tier C fix, a raw UPDATE gave no trace at all, distinct or otherwise. This branch
  -- captures the override honestly and distinctly for both operations, mirroring
  -- `app.files`' own identical override-disclosure pattern, rather than attempting to
  -- make Supreme Admin's own documented absolute-CRUD authority unreachable (out of
  -- scope, and contrary to RPD-022 as written).
  perform app.capture_audit_event(
    OLD.tenant_id, v_actor, 'supreme_admin_absolute_crud',
    case when TG_OP = 'DELETE' then 'delete_legally_held_audit_log' else 'update_legally_held_audit_log' end,
    'app.audit_logs', OLD.id, 'success',
    'RPD-022 absolute-CRUD exception invoked (best-effort evidence, not a preventive control) -- app.audit_logs is otherwise blocked from physical deletion or update while under legal hold, native or generic (app.legal_holds)',
    to_jsonb(OLD), case when TG_OP = 'DELETE' then null else to_jsonb(NEW) end
  );

  if TG_OP = 'DELETE' then
    return OLD;
  end if;
  return NEW;
end;
$$;

comment on function app.protect_audit_logs_legal_hold_from_deletion is
  'HDN-386 (Full-System Hardening Integrated Verification): BEFORE UPDATE OR DELETE guard for app.audit_logs, closing HDN-BLK-020 (Critical). Checks BOTH the PLT-116-native app.audit_logs.legal_hold flag AND the bridged generic (IAE-031) app._is_under_legal_hold(), mirroring app.protect_files_legal_hold_from_deletion. Tier C fix (attack-surface lens, live-reproduced): widened from DELETE-only to also cover UPDATE -- app.audit_logs has no legitimate non-Supreme-Admin write path at all, so ANY update of a held row by a non-Supreme-Admin actor is blocked (not just a specific column transition, unlike app.files own narrower soft-delete-only UPDATE guard), closing the raw UPDATE-then-DELETE bypass (content corruption or clearing legal_hold itself) the first round''s own DELETE-only trigger missed. A genuine Supreme Admin RPC caller may still override per RPD-022''s disclosed absolute-CRUD residual risk, but the override is now honestly and distinctly captured for both operations.';

drop trigger audit_logs_protect_legal_hold_from_deletion on app.audit_logs;
create trigger audit_logs_protect_legal_hold_from_deletion
  before update or delete on app.audit_logs
  for each row
  execute function app.protect_audit_logs_legal_hold_from_deletion();

-- ===========================================================================
-- Ledger/documentation consistency lens finding, Low, self-inflicted: this
-- checkpoint's own new "Status as of `HDN-386` first round" section in
-- `BLOCKER_LEDGER.md` stated the post-first-round High-open count as 23, but the
-- entry's own listed IDs (9 pre-existing + 12 unowned `HDN-BLK-027..038` + 1 new
-- `HDN-BLK-039` = 22) sum to 22, not 23 -- a fresh instance of the exact stale-tally
-- defect class `ISS-2026-283` (this same checkpoint's own finding) exists to warn
-- about, introduced in the very section meant to demonstrate the fix. Corrected
-- directly in `docs/build-log/full-system-hardening/BLOCKER_LEDGER.md`, not via a
-- migration (no schema/code implication).
-- ===========================================================================
