-- Track B Batch 6, ISS-2026-187 + ISS-2026-188 (docs/runtime/KNOWN_ISSUES.md), same root
-- cause, closed with the one fix ISS-2026-188's own text names verbatim: "either make
-- end_support_session revoke the grant (if one-session-per-grant is the intended model)
-- or make has_active_support_grant require an open session, closing this and
-- ISS-2026-187 with the same fix."
--
-- app.has_active_support_grant (supabase/migrations/20260716111315_create_support_access.
-- sql:250-266) never consulted app.support_access_sessions at all -- only the grant row's
-- own approved/expiry/revoked state -- so the intended reauth/session-start step
-- app.start_support_session (PLT-115, Prompt 115 section 4 "re-authentication") implies
-- was never actually enforced by the ONE function every support_access_gated RLS policy
-- and RPC composes through app.has_active_tenant_membership (same migration, line 285-298).
-- Full data access existed the moment a grant was approved, before any session-start
-- call -- ISS-2026-187. And because the grant alone (not the session) was the gate,
-- app.end_support_session (line 625-656) leaving the grant row untouched meant it never
-- actually ended access either -- only the SEPARATE, admin-only app.revoke_support_access
-- kill switch did -- ISS-2026-188.
--
-- Chose the has_active_support_grant fix over the end_support_session-revokes-the-grant
-- alternative because the one-session-per-grant model that alternative assumes is NOT
-- this schema's own intended model: app.support_access_sessions' own table comment
-- (20260716111315...sql:132-133) says explicitly "the grant may support multiple
-- sequential sessions within its own time window (support_access_sessions_one_open_per_
-- grant below allows only one *open* session per grant at a time, not one session
-- total)." Making end_support_session revoke the grant would contradict that documented,
-- structurally-enforced (the partial unique index, not the revoke-on-end alternative)
-- model -- a support engineer's normal end-of-session action would silently destroy a
-- still-valid, still-approved grant, forcing a fresh tenant-admin approval for a routine
-- follow-up call within the same authorized window. Requiring an open session instead
-- composes cleanly with that model: ending a session closes access immediately (this
-- fixes ISS-2026-188) without touching the grant, and starting a NEW session under the
-- same still-approved grant (no new approval needed) restores it, exactly the "multiple
-- sequential sessions" shape this schema already committed to.
--
-- Same signature, so CREATE OR REPLACE (no DROP needed, no public.* wrapper to update --
-- supabase/migrations/20260826000000_create_public_api_data_wrappers.sql:18574-18590's
-- public.has_active_support_grant is a pure pass-through to app.has_active_support_grant
-- with the same two arguments, unaffected by a body-only change). Grant set unchanged
-- (authenticated, service_role) -- app.has_active_support_grant also stays on rbac-
-- enforcement.sql's own ATW-032 authority-primitive exemption list unmodified, since it
-- is still the same kind of "identity-scoped RLS primitive granted directly to
-- authenticated because RLS policy bodies run as the querying role" function it always
-- was, just a tighter predicate.
--
-- Downstream callers re-checked before drafting this fix, not assumed safe: (1)
-- app.has_active_tenant_membership composes this function's OR-branch -- unaffected in
-- shape, just tighter. (2) app._ticket_link_actor_may_view_tenant_data
-- (20260731170000_create_ticket_linked_records.sql:332) composes it directly for
-- HRT-292's helpdesk-channel gate -- correctly tightens the same way (a support grant
-- with no open session now also can't view/link tenant ticket data, closing the
-- identical bug through that surface). (3) app.current_support_session (line 308-325 of
-- the same original migration) already independently required ended_at is null AND the
-- grant's own approved/unrevoked/unexpired state -- this migration does not touch it,
-- and the two functions are now consistent with each other rather than one being
-- stricter than the other. scripts/db-tests/ticketing-linked-records.sql's own section 8
-- test (helpdesk channel, an emergency self-authorized grant) needed a start_support_
-- session call added after its request_support_access call to keep matching the new,
-- correct semantics -- updated in this batch alongside this migration, not left broken.

create or replace function app.has_active_support_grant(p_tenant_id uuid, p_auth_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select exists (
    select 1
    from app.support_access_grants g
    join app.support_access_sessions s
      on s.grant_id = g.id
     and s.ended_at is null
    where g.tenant_id = p_tenant_id
      and g.grantee_auth_user_id = p_auth_user_id
      and g.status = 'approved'
      and g.granted_at is not null
      and g.expires_at > now()
      and g.revoked_at is null
  );
$$;

comment on function app.has_active_support_grant is
  'True if the identity holds a live (approved, unexpired, unrevoked) support access grant into the given tenant AND currently has a live, open app.support_access_sessions row under that grant (PLT-115, docs/architecture/06_RLS_RBAC_WORKSTREAM.md section 2.3''s expires_at/revoked_at condition, tightened by ISS-2026-187/188 to also require the documented reauth/session-start step -- see supabase/migrations/20260828110000_harden_support_session_gates_active_grant.sql). An approved grant alone, with no session ever started or with its session already ended, now grants zero access -- app.start_support_session (fresh reauth) or a new session on the same still-approved grant is required first. Composed into app.has_active_tenant_membership() below -- still the support_access_gated policy family (section 4): one reused predicate, not a duplicated policy per table.';

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries its own
-- explicit `revoke execute on all functions in schema app from public` statement before
-- its final grants, the standing per-migration convention since PLT-118.
revoke execute on all functions in schema app from public;

grant execute on function app.has_active_support_grant(uuid, uuid) to authenticated, service_role;
