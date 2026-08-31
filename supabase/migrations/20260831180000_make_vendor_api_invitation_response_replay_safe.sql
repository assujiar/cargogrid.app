-- Closes `ISS-2026-208`: `app.accept_vendor_assignment_invitation_via_vendor_api` and
-- `app.decline_...` answered a lost-response retry with `stale_version` (HTTP 409) instead of the
-- row the client's retry was asking about, so a vendor integration could not tell "my own retry
-- already landed" from "someone else changed this" without a separate re-fetch.
--
-- WHY THE ENTRY'S OWN BLOCKER DOES NOT APPLY, WHICH IS WHY THIS CLOSES IN ONE FUNCTION BODY
--
--   `ISS-2026-208` was deferred twice on the grounds that a fix "needs a new parameter and its own
--   column/index design, not a copy of an existing pattern -- a design decision, not a bounded
--   repair." That reasoning assumed the answer had to be an idempotency key, because that is what
--   every sibling Vendor API mutation uses.
--
--   It does not. An idempotency key exists to tell two *different* requests apart when the
--   operation would otherwise happen twice -- creating a second booking, posting a second
--   response. **Accepting an invitation is not that kind of operation.** There is exactly one
--   meaningful acceptance per invitation, the row itself already records whether it happened, and
--   the vendor is the only party who can perform it. The row IS the idempotency record. Adding a
--   key would be ceremony around a fact the table already holds.
--
--   So this needs no new column, no new index, and no new parameter -- only for the two functions
--   to recognise their own completed work when they see it.
--
-- THE PRECISE CONDITION, AND WHY IT IS NOT SIMPLY "ALREADY ACCEPTED -> RETURN 200"
--
--   Returning the row whenever it is already accepted would be too generous: it would also
--   swallow the case of a client whose view is stale by *several* changes, telling them everything
--   is fine when they have in fact missed things. `stale_version` is the right answer there.
--
--   A genuine lost-response retry has an exact signature: the caller presents the version they
--   held *before* their own write, the row now sits at **exactly one** version higher, and it is
--   in **exactly the state that write would have produced**. All three, or it is not a replay.
--   For decline, the stored reason must match the one being retried too -- a different reason is
--   a different request, not a retry of this one.
--
-- WHAT THE AUDIT TRAIL SAYS
--
--   A replay must not record a second acceptance; nothing was accepted twice, and a trail that
--   says otherwise is worse than one that says nothing. It is also not silent -- a retry is real
--   information about the integration. So the replay captures the same action tagged
--   `idempotent_replay`, leaving one true acceptance and one clearly-labelled retry on the record.

create or replace function app.accept_vendor_assignment_invitation_via_vendor_api(
  p_tenant_id uuid,
  p_vendor_master_record_id uuid,
  p_invitation_id uuid,
  p_expected_version integer
)
returns app.vendor_assignment_invitations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_invitation app.vendor_assignment_invitations;
begin
  select * into v_invitation from app.vendor_assignment_invitations where id = p_invitation_id and tenant_id = p_tenant_id;
  if not found or v_invitation.vendor_master_id <> p_vendor_master_record_id then
    raise exception 'vendor_assignment_invitation_not_found: no vendor assignment invitation % for this vendor in tenant %', p_invitation_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  if v_invitation.record_version <> p_expected_version then
    -- ISS-2026-208. All three conditions, not one: the row is in the state THIS call would have
    -- produced, it advanced by exactly one version (app.touch_vendor_assignment_invitations_row
    -- bumps by 1 per write), and that version is the caller's own. Anything else -- two bumps, a
    -- different terminal state -- means the caller has missed something real and stale_version is
    -- the honest answer.
    if v_invitation.status = 'accepted' and v_invitation.record_version = p_expected_version + 1 then
      perform app.capture_audit_event(
        v_invitation.tenant_id, null, 'Vendor API', 'accept_vendor_assignment_invitation_via_vendor_api',
        'app.vendor_assignment_invitations', v_invitation.id, 'success', null, null,
        jsonb_build_object('vendor_master_record_id', p_vendor_master_record_id, 'idempotent_replay', true)
      );
      return v_invitation;
    end if;
    raise exception 'stale_version: vendor assignment invitation % expected version % but found %', p_invitation_id, p_expected_version, v_invitation.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_invitation.status <> 'invited' then
    raise exception 'invalid_transition: vendor assignment invitation % is % and cannot be accepted', p_invitation_id, v_invitation.status
      using errcode = 'check_violation';
  end if;

  update app.vendor_assignment_invitations set status = 'accepted' where id = p_invitation_id and record_version = p_expected_version returning * into v_invitation;
  if not found then
    raise exception 'stale_version: vendor assignment invitation % target row was concurrently modified (expected version %)', p_invitation_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_invitation.tenant_id, null, 'Vendor API', 'accept_vendor_assignment_invitation_via_vendor_api',
    'app.vendor_assignment_invitations', v_invitation.id, 'success', null, null, jsonb_build_object('vendor_master_record_id', p_vendor_master_record_id)
  );

  return v_invitation;
end;
$$;

comment on function app.accept_vendor_assignment_invitation_via_vendor_api is
  'IAE-011: the Vendor API''s own accept path into the SAME app.vendor_assignment_invitations table app.accept_vendor_assignment_invitation (staff-only) already writes into. Authorized by vendor-scope containment, not staff RBAC. Optimistic-concurrency-safe: the UPDATE''s own WHERE re-checks record_version at write time (ATW-032 discipline), no separate lock-then-decide race. ISS-2026-208 (20260831180000): a lost-response retry now replays to the accepted row instead of a 409. No idempotency key was added -- accepting an invitation happens at most once by construction, so the row itself is the idempotency record and a key would be ceremony around a fact the table already holds. The replay is recognised only on an exact signature (already accepted, exactly one version above the caller''s own), never on "already accepted" alone, which would also swallow a client who has genuinely missed several changes.';

create or replace function app.decline_vendor_assignment_invitation_via_vendor_api(
  p_tenant_id uuid,
  p_vendor_master_record_id uuid,
  p_invitation_id uuid,
  p_expected_version integer,
  p_reason text
)
returns app.vendor_assignment_invitations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_invitation app.vendor_assignment_invitations;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to decline a vendor assignment invitation' using errcode = 'check_violation';
  end if;

  select * into v_invitation from app.vendor_assignment_invitations where id = p_invitation_id and tenant_id = p_tenant_id;
  if not found or v_invitation.vendor_master_id <> p_vendor_master_record_id then
    raise exception 'vendor_assignment_invitation_not_found: no vendor assignment invitation % for this vendor in tenant %', p_invitation_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  if v_invitation.record_version <> p_expected_version then
    -- Same three conditions as accept, plus a fourth: the stored reason must be the one being
    -- retried. A retry carries the same payload; a different reason is a different request, and
    -- treating it as a replay would silently discard what the caller actually said.
    if v_invitation.status = 'declined'
       and v_invitation.record_version = p_expected_version + 1
       and v_invitation.decline_reason is not distinct from p_reason
    then
      perform app.capture_audit_event(
        v_invitation.tenant_id, null, 'Vendor API', 'decline_vendor_assignment_invitation_via_vendor_api',
        'app.vendor_assignment_invitations', v_invitation.id, 'success', p_reason, null,
        jsonb_build_object('vendor_master_record_id', p_vendor_master_record_id, 'idempotent_replay', true)
      );
      return v_invitation;
    end if;
    raise exception 'stale_version: vendor assignment invitation % expected version % but found %', p_invitation_id, p_expected_version, v_invitation.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_invitation.status <> 'invited' then
    raise exception 'invalid_transition: vendor assignment invitation % is % and cannot be declined', p_invitation_id, v_invitation.status
      using errcode = 'check_violation';
  end if;

  update app.vendor_assignment_invitations set status = 'declined', decline_reason = p_reason where id = p_invitation_id and record_version = p_expected_version returning * into v_invitation;
  if not found then
    raise exception 'stale_version: vendor assignment invitation % target row was concurrently modified (expected version %)', p_invitation_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_invitation.tenant_id, null, 'Vendor API', 'decline_vendor_assignment_invitation_via_vendor_api',
    'app.vendor_assignment_invitations', v_invitation.id, 'success', p_reason, null, jsonb_build_object('vendor_master_record_id', p_vendor_master_record_id)
  );

  return v_invitation;
end;
$$;

comment on function app.decline_vendor_assignment_invitation_via_vendor_api is
  'IAE-011: the Vendor API''s own decline path, mirroring app.accept_vendor_assignment_invitation_via_vendor_api''s own vendor-scope authority. ISS-2026-208 (20260831180000): replay-safe on the same exact signature as accept, plus a fourth condition -- the stored decline_reason must be the one being retried. A retry carries the same payload; a different reason is a different request, and treating it as a replay would silently discard what the caller actually said.';
