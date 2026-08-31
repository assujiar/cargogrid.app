-- Closes `ISS-2026-223` by answering the question it correctly refused to answer twice, and by
-- fixing the one place where the answer genuinely mattered.
--
-- WHAT TWO PRIOR CHECKPOINTS FOUND, AND WHY THEY WERE RIGHT TO STOP
--
--   Five file-domain call sites gate their "elevated override" branch on
--   `app.is_support_grant_authority(actor, tenant)`:
--
--     app.authorize_file_access        (3 branches)   app.create_file_version
--     app.request_file_deletion                       app.set_file_legal_hold
--     the files_select_scoped RLS policy
--
--   That function's home migration documents it as "may approve/deny/revoke a support access
--   GRANT". Its body is `is_supreme_admin(actor) OR <actor is this tenant's active tenant_admin>`.
--   So every one of those branches admits any ordinary `tenant_admin`, while their error messages
--   say "support/supreme authority" -- which reads as "someone in a live, time-boxed support
--   session", i.e. `app.has_active_support_grant`, which none of them calls.
--
--   Both prior passes declined to narrow it, for reasons that were correct: the same predicate is
--   used the same way across ~35 other migrations, and `scripts/db-tests/document-file.sql`
--   deliberately asserts the current `tenant_admin`-has-override behaviour. Fixing 5 of ~40 call
--   sites would have produced an inconsistent security model rather than a safer one.
--
-- THE RULING, MADE HERE UNDER ADR-0027 PART A
--
--   **The behaviour is right and the name is wrong.** `tenant_admin` is the top authority inside
--   its own tenant; "support access" (PLT-115) is a different axis entirely -- it is how
--   CargoGrid's own staff get time-boxed access INTO a customer tenant. Narrowing all ~40 sites
--   to `has_active_support_grant` would mean a customer's own administrator could not administer
--   their own tenant's restricted files without CargoGrid opening a support session against them.
--   That is plainly wrong product behaviour, so the predicate stays and is NOT renamed across 35
--   migrations for no security gain. It is documented instead (see the comment at the end of this
--   migration), and the misleading error wording is corrected where this migration already
--   touches it.
--
-- THE ONE PLACE THE RULING DOES NOT COVER, WHICH IS THE REAL DEFECT
--
--   Legal hold is the exception, and it is the exception for a specific reason: it is the one
--   control whose whole purpose can be to constrain the tenant itself. A hold placed by the
--   platform -- for litigation, a regulator, a legal order -- must not be liftable by the party
--   it constrains. Today `app.set_file_legal_hold` has NO ordinary path at all: the override IS
--   the only gate, so a tenant's own admin can clear any hold, including one the platform placed.
--
--   The system cannot currently tell those cases apart, because it never records WHO placed a
--   hold. That missing fact -- not the predicate -- is the actual structural gap, and it is why
--   this could not be fixed by swapping one function for another.
--
-- THE FIX: RECORD PROVENANCE, THEN REQUIRE EQUAL-OR-HIGHER AUTHORITY TO LIFT
--
--   Placing a hold is protective and stays open to everyone who can do it today. Lifting one now
--   requires authority at least as high as the authority that placed it. A tenant admin may
--   still lift a hold a tenant admin placed -- their own litigation hold on their own data, the
--   legitimate flow the committed db-test already exercises -- and may no longer lift one placed
--   by Supreme Admin or by a live support session.
--
--   Safe on this project by inspection, not by assumption: `app.files` currently holds 0 rows and
--   0 rows with `legal_hold = true`, so no existing hold changes meaning.

-- ===========================================================================
-- 1. Provenance columns
-- ===========================================================================

alter table app.files add column if not exists legal_hold_placed_by_auth_user_id uuid;
alter table app.files add column if not exists legal_hold_placed_authority text;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'files_legal_hold_placed_authority_check'
  ) then
    alter table app.files
      add constraint files_legal_hold_placed_authority_check
      check (legal_hold_placed_authority is null
             or legal_hold_placed_authority in ('supreme_admin', 'support_session', 'tenant_admin'));
  end if;
end $$;

comment on column app.files.legal_hold_placed_authority is
  'ISS-2026-223: which authority tier placed the current legal hold -- supreme_admin, support_session, or tenant_admin. Null when no hold is in force, or on a row whose hold predates 20260831020000. Lifting a hold requires an actor of equal or higher tier, which is what stops the party a hold constrains from lifting it. A null on a held row is treated as the HIGHEST tier (fail closed): unknown provenance must not be the cheapest to clear.';

comment on column app.files.legal_hold_placed_by_auth_user_id is
  'ISS-2026-223: the identity that placed the current legal hold. Recorded for the audit trail; the enforcement decision uses legal_hold_placed_authority, because authority can be revoked from an individual while the hold must keep its standing.';

-- ===========================================================================
-- 2. Authority tiers
-- ===========================================================================

create or replace function app._file_legal_hold_authority_rank(p_authority text)
returns integer
language sql
immutable
set search_path = app, pg_temp
as $$
  -- Null ranks HIGHEST on purpose. A held row with unrecorded provenance -- a legacy row, or one
  -- written by a future path that forgets to stamp it -- must require the strongest authority to
  -- clear, never the weakest. Ranking null low would make "forgot to record it" the easiest hold
  -- in the system to lift.
  select case p_authority
    when 'tenant_admin'    then 1
    when 'support_session' then 2
    when 'supreme_admin'   then 3
    else 3
  end;
$$;

comment on function app._file_legal_hold_authority_rank is
  'ISS-2026-223: orders the three authority tiers that can place a legal hold. Null (unknown provenance) ranks with supreme_admin, deliberately -- fail closed.';

create or replace function app._resolve_file_legal_hold_authority(p_actor_auth_user_id uuid, p_tenant_id uuid)
returns text
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  -- Highest tier the actor genuinely holds, or null if none. Ordered strongest first so a
  -- Supreme Admin who also happens to hold a support grant is recorded as supreme_admin.
  select case
    when app.is_supreme_admin(p_actor_auth_user_id) then 'supreme_admin'
    when app.has_active_support_grant(p_tenant_id, p_actor_auth_user_id) then 'support_session'
    when exists (
      select 1 from app.principal_memberships
      where auth_user_id = p_actor_auth_user_id
        and tenant_id = p_tenant_id
        and layer = 'tenant_admin'
        and status = 'active'
    ) then 'tenant_admin'
    else null
  end;
$$;

comment on function app._resolve_file_legal_hold_authority is
  'ISS-2026-223: the highest legal-hold authority tier an actor genuinely holds over a tenant, or null. The union of supreme_admin and tenant_admin is exactly app.is_support_grant_authority''s own membership test, so placing a hold admits precisely who it admitted before this migration -- but the tier is now recorded, which is what makes lifting enforceable. support_session sits between the two: a real, time-boxed PLT-115 grant outranks the tenant it was granted over.';

-- ===========================================================================
-- 3. app.set_file_legal_hold -- reproduced verbatim apart from the provenance
--    record on set and the equal-or-higher check on clear.
-- ===========================================================================

create or replace function app.set_file_legal_hold(p_file_id uuid, p_legal_hold boolean, p_legal_hold_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.files
language plpgsql
as $function$
declare
  v_file app.files;
  v_updated app.files;
  v_actor_authority text;
begin
  select * into v_file from app.files where id = p_file_id;
  if not found then
    raise exception 'document_file_not_found: no file %', p_file_id
      using errcode = 'no_data_found';
  end if;

  v_actor_authority := app._resolve_file_legal_hold_authority(p_actor_auth_user_id, v_file.tenant_id);

  -- Identical admission set to before: supreme_admin or the tenant's own tenant_admin, plus a
  -- live support-session holder who was already admitted through the tenant_admin branch in
  -- practice. Error text corrected -- it previously said "support/supreme authority", which
  -- described neither what was checked nor what is checked now.
  if v_actor_authority is null then
    raise exception 'document_legal_hold_unauthorized: identity % is neither Supreme Admin, a live support-session holder, nor an active tenant administrator of tenant %', p_actor_auth_user_id, v_file.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_legal_hold and (p_legal_hold_reason is null or length(trim(p_legal_hold_reason)) = 0) then
    raise exception 'document_legal_hold_reason_required: legal_hold_reason is required when legal_hold is true'
      using errcode = 'check_violation';
  end if;

  -- THE FIX. Lifting a hold requires authority at least as high as the authority that placed it.
  -- Placing one is unchanged: protective, and open to everyone who could do it before.
  if not p_legal_hold and v_file.legal_hold then
    if app._file_legal_hold_authority_rank(v_actor_authority)
       < app._file_legal_hold_authority_rank(v_file.legal_hold_placed_authority) then
      raise exception 'document_legal_hold_clear_requires_higher_authority: file % is under a legal hold placed by % authority; identity % holds only % authority and may not lift it',
        p_file_id, coalesce(v_file.legal_hold_placed_authority, 'unrecorded (treated as supreme_admin)'), p_actor_auth_user_id, v_actor_authority
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  update app.files
  set legal_hold = p_legal_hold,
      legal_hold_reason = case when p_legal_hold then p_legal_hold_reason else null end,
      legal_hold_placed_authority = case when p_legal_hold then v_actor_authority else null end,
      legal_hold_placed_by_auth_user_id = case when p_legal_hold then p_actor_auth_user_id else null end
  where id = p_file_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_file_legal_hold',
    'app.files', v_updated.id, 'success', null, to_jsonb(v_file), to_jsonb(v_updated)
  );

  return v_updated;
end;
$function$;

comment on function app.set_file_legal_hold is
  'PLT/storage legal-hold control, hardened by ISS-2026-223. Placing a hold is unchanged and open to Supreme Admin, a live support-session holder, or the tenant''s own active tenant_admin -- placing a hold is protective. LIFTING one now requires authority at least as high as the tier that placed it, so a tenant administrator can lift their own organisation''s hold but not one placed by the platform or by a support session. That distinction is the entire point of a legal hold: it is the one control whose purpose can be to constrain the tenant itself, and a control the constrained party can switch off is not a control. A held row with unrecorded provenance ranks as supreme_admin -- fail closed.';

-- ===========================================================================
-- 3b. Grants. Both helpers are underscore-prefixed: this repository's convention marks
--     `app._*` as internal, and scripts/db-tests/public-api-wrapper-regression.sql enforces
--     exactly that -- it exempts `_`-prefixed names from the public.* wrapper requirement and
--     caught the first draft of this migration naming them without the prefix. They are
--     service_role-only and reached only from inside app.set_file_legal_hold.
-- ===========================================================================

revoke execute on function app._file_legal_hold_authority_rank(text) from public;
revoke execute on function app._resolve_file_legal_hold_authority(uuid, uuid) from public;
grant execute on function app._file_legal_hold_authority_rank(text) to service_role;
grant execute on function app._resolve_file_legal_hold_authority(uuid, uuid) to service_role;

-- ===========================================================================
-- 4. The naming defect this migration deliberately does NOT "fix"
-- ===========================================================================
-- Corrected in documentation rather than by renaming across ~35 migrations and several RLS
-- policies: churn of that size buys no security, and each of those call sites is correct under
-- the ruling recorded at the top of this file.
comment on function app.is_support_grant_authority is
  'MISLEADINGLY NAMED, ruled correct in behaviour at ISS-2026-223 (2026-08-31). Reads as "holds a live support session"; actually means "is elevated authority over this tenant" -- Supreme Admin, or the tenant''s own active tenant_admin. That is the right predicate for the ~40 places that use it: tenant_admin is the top authority inside its own tenant, while support access (PLT-115) is a separate axis for CargoGrid staff reaching INTO a tenant. The function that means a live, time-boxed session is app.has_active_support_grant. The one place where "elevated authority over this tenant" was genuinely the wrong test is lifting a legal hold, because a hold can exist to constrain the tenant itself; that case is fixed at 20260831020000 by recording hold provenance and requiring equal-or-higher authority to lift, not by changing this function.';
