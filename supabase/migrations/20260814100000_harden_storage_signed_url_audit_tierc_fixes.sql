-- HDN-377 (Step 15, Prompt 377, Storage and Signed URL Audit) -- Tier C adversarial
-- review fix pass. Four independent parallel Tier C lenses (correctness re-derivation;
-- schema-wide completeness sweep; ledger/documentation consistency; attack-surface
-- adversarial testing) ran against the first-round commit (`b537866`).
--
-- ===========================================================================
-- Attack-surface lens finding, CRITICAL, live-forced: the first round's own new
-- `BEFORE DELETE` guard trigger (`app.protect_files_legal_hold_from_deletion`, Finding
-- C / `ISS-2026-218`) checked only `OLD.legal_hold` (the PLT-128-native flag) and never
-- called `app._is_under_legal_hold()` -- the very bridge the SAME migration's own
-- Finding B (`ISS-2026-217`) added to make the generic (IAE-031) hold mechanism visible
-- everywhere. Because `app.request_legal_hold()` never writes back to `app.files.legal_
-- hold`, a file held exclusively via the generic mechanism kept `legal_hold=false`
-- forever, so the new trigger let a raw `service_role` DELETE physically destroy it --
-- live-forced, reproducible, with NO exception raised and NO audit event captured
-- (the trigger's own audit branch is gated on the same false flag). This directly
-- falsified the first round's own claim that the bridge "closes both directions at
-- once" -- it closed the read/retention-archive/RPC-deletion directions, not this
-- schema-level DELETE-trigger direction added in the same commit.
--
-- Completeness-sweep lens finding, HIGH, live-forced: the same schema-level-backstop
-- gap (C-26) recurs twice more on `app.files` itself, in this checkpoint's own domain:
-- (1) `app.request_file_deletion()`'s legal-hold check has no backstop against the
-- UPDATE-based SOFT-delete path (`deleted_at`) -- only the physical DELETE got a
-- trigger; a raw `UPDATE app.files SET deleted_at = now(), lifecycle_status='deleted'`
-- on a held row succeeds unimpeded. (2) `app.record_file_scan_result()`'s own
-- "cannot re-resolve an already-resolved scan" invariant (`document_scan_already_
-- resolved`) has zero trigger backstop -- a raw UPDATE flips `malware_scan_status`
-- freely, including flipping a live-forced `infected` (quarantined) file straight to
-- `clean`, the literal gate the whole checkpoint's own charter depends on.
--
-- (1) is fixed below by extending the existing trigger to also cover the soft-delete
-- UPDATE transition (bridged-hold-aware, same as the DELETE path) -- it does not touch
-- any other UPDATE path (versioning supersede, classification change, etc.).
--
-- (2) was drafted as a matching `BEFORE UPDATE` guard, then discovered before commit
-- to directly conflict with an established, deliberate, already-committed pattern this
-- codebase uses in at least 4 other test suites (`customer-epod-access.sql`,
-- `procurement-vendor-compliance.sql`, `procurement-vendor-financial-security.sql`,
-- `ticketing-customer.sql`): a raw, direct `UPDATE app.files SET malware_scan_status =
-- 'infected'` re-flagging an already-`clean` file, executed with NO session-bound actor
-- context at all, explicitly documented at each call site as simulating "the disclosed
-- RPD-022 Supreme Admin residual-risk correction path... never reachable through
-- app.record_file_scan_result once resolved." The drafted trigger's own
-- `is_supreme_admin(auth.uid())` bypass check requires a session-bound actor, which
-- none of these established call sites establish (they represent an out-of-band,
-- service-level correction, not a browser session) -- so the drafted fix would have
-- broken 4 pre-existing, deliberately-designed, currently-passing tests to close a
-- gap this same codebase already has a disclosed, accepted, differently-shaped
-- residual-risk path for. Discarded rather than shipped broken or hastily
-- re-designed under Tier C's own time budget, mirroring `HDN-374`'s own Finding-2 and
-- `HDN-375`'s own `finance_subledger_batches` self-correction precedent. Registered
-- instead (`ISS-2026-226`, below) with the exact conflict disclosed, rather than
-- fixed or silently dropped.
-- ===========================================================================

create or replace function app.protect_files_legal_hold_from_deletion()
returns trigger
language plpgsql
as $$
declare
  v_actor uuid;
  v_held boolean;
begin
  -- Computed lazily, after this early return, not in the declare block's own
  -- initializer -- this trigger now fires on every UPDATE (not just DELETE), and
  -- auth.uid() raises on a session where request.jwt.claims was never set to valid
  -- JSON at all (e.g. a service-context caller with no JWT claims GUC), which the
  -- overwhelming majority of ordinary, non-deletion UPDATEs on this table are.
  if TG_OP = 'UPDATE' and not (NEW.deleted_at is not null and OLD.deleted_at is null) then
    return NEW;
  end if;

  v_actor := auth.uid();
  v_held := OLD.legal_hold or app._is_under_legal_hold(OLD.tenant_id, 'operational', 'app.files', OLD.id);

  if not v_held then
    if TG_OP = 'DELETE' then
      return OLD;
    end if;
    return NEW;
  end if;

  if not app.is_supreme_admin(v_actor) then
    if TG_OP = 'DELETE' then
      raise exception 'document_legal_hold_blocks_deletion: file % is under legal hold (%), it cannot be physically deleted -- app.request_file_deletion already refuses this at the RPC layer, this is the schema-level backstop for a direct DELETE', OLD.id, OLD.legal_hold_reason
        using errcode = 'insufficient_privilege';
    else
      raise exception 'document_legal_hold_blocks_deletion: file % is under legal hold (%), it cannot be soft-deleted -- app.request_file_deletion already refuses this at the RPC layer, this is the schema-level backstop for a direct UPDATE setting deleted_at', OLD.id, OLD.legal_hold_reason
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  perform app.capture_audit_event(
    OLD.tenant_id, v_actor, 'supreme_admin_absolute_crud',
    case when TG_OP = 'DELETE' then 'delete_legally_held_file' else 'soft_delete_legally_held_file' end,
    'app.files', OLD.id, 'success',
    'RPD-022 absolute-CRUD exception invoked (best-effort evidence, not a preventive control) -- app.files is otherwise blocked from deletion (physical or soft) while under legal hold, native or generic (app.legal_holds)',
    to_jsonb(OLD), case when TG_OP = 'DELETE' then null else to_jsonb(NEW) end
  );

  if TG_OP = 'DELETE' then
    return OLD;
  end if;
  return NEW;
end;
$$;

comment on function app.protect_files_legal_hold_from_deletion is
  'HDN-377 (Storage and Signed URL Audit): BEFORE UPDATE OR DELETE guard for app.files. Blocks physical DELETE and the soft-delete UPDATE transition (deleted_at newly set) of any row under legal hold -- checks BOTH the PLT-128-native app.files.legal_hold flag AND the bridged generic (IAE-031) app._is_under_legal_hold(), closing the Tier C-found gap where the first round''s own trigger checked only the native flag despite the same migration''s own Finding B bridging the generic mechanism elsewhere. Every other UPDATE path (scan-status transitions, versioning supersede, classification change) is unaffected -- only fires its own hold check on DELETE or a deleted_at-setting UPDATE. Supreme Admin RPD-022 override still works, audited both ways.';

drop trigger files_protect_legal_hold_from_deletion on app.files;
create trigger files_protect_legal_hold_from_deletion
  before update or delete on app.files
  for each row
  execute function app.protect_files_legal_hold_from_deletion();

-- ===========================================================================
-- Attack-surface lens finding, MEDIUM-HIGH, live-forced: app.request_legal_hold()'s
-- p_scope_record_table parameter is unvalidated free text compared by exact string
-- equality in app._is_under_legal_hold() (both the pre-existing specific-record branch
-- and this checkpoint's own new app.files bridge branch). A hold placed with wrong
-- case ('app.Files'), leading whitespace (' app.files'), or a missing schema prefix
-- ('files') inserted successfully, looked like a genuine active hold, and silently
-- protected nothing -- app.request_file_deletion() still succeeded. Fixed by
-- normalizing (lower/trim) at write time in app.request_legal_hold() and requiring a
-- schema-qualified value (rejecting a missing-prefix mistake loudly instead of
-- silently creating a non-protecting hold), plus normalizing the read-side comparison
-- in app._is_under_legal_hold() for defense in depth against any future caller.
-- ===========================================================================

create or replace function app.request_legal_hold(
  p_tenant_id uuid,
  p_record_class text,
  p_scope_record_table text,
  p_scope_record_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.legal_holds
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_hold app.legal_holds;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'RET', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks RET:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_record_class not in ('finance_tax', 'audit_security', 'operational') then
    raise exception 'retention_invalid_record_class: %', p_record_class using errcode = 'check_violation';
  end if;
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'legal_hold_reason_required: a legal hold must state a real reason' using errcode = 'check_violation';
  end if;
  if (p_scope_record_table is null) <> (p_scope_record_id is null) then
    raise exception 'legal_hold_invalid_scope: scope_record_table and scope_record_id must both be set, or both null' using errcode = 'check_violation';
  end if;

  if p_scope_record_table is not null then
    p_scope_record_table := lower(trim(p_scope_record_table));
    if position('.' in p_scope_record_table) = 0 then
      raise exception 'legal_hold_scope_table_not_qualified: scope_record_table must be schema-qualified (e.g. app.files), got %', p_scope_record_table
        using errcode = 'check_violation';
    end if;
  end if;

  insert into app.legal_holds (tenant_id, record_class, scope_record_table, scope_record_id, reason, placed_by_auth_user_id, placed_by)
  values (p_tenant_id, p_record_class, p_scope_record_table, p_scope_record_id, p_reason, p_actor_auth_user_id, p_actor_label)
  returning * into v_hold;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'request_legal_hold',
    'app.legal_holds', v_hold.id, 'success', null, null, to_jsonb(v_hold)
  );

  return v_hold;
end;
$$;

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
    );
$$;

comment on function app._is_under_legal_hold is
  'IAE-031: internal-only primitive, no actor/authority parameter -- never granted to anon/authenticated. A specific-record hold matches on (source_table, source_record_id) ALONE, independent of the caller''s own tenant_id/record_class claim (HDN-373 Tier C review fix); a whole-class hold necessarily still matches on the caller''s own (tenant_id, record_class) declaration, since there is no specific record to anchor against instead. HDN-377 (Storage and Signed URL Audit): also true whenever source_table=''app.files'' and that file''s own legal_hold column is set -- bridges PLT-128''s file-native hold flag into this generic cross-domain primitive. HDN-377 Tier C fix: p_source_table is normalized (lower/trim) before comparison, matching app.request_legal_hold()''s own write-time normalization -- a case/whitespace variant no longer silently fails to match a real, active hold.';

revoke execute on all functions in schema app from public;
