-- Track B Batch 6, ISS-2026-177 (docs/runtime/KNOWN_ISSUES.md): app.request_support_
-- access/approve_support_access/deny_support_access/start_support_session/end_support_
-- session/complete_support_access_post_review all write to app.support_access_events
-- (this capability's own capability-scoped trail) but only app.revoke_support_access
-- also writes app.audit_logs -- the canonical, tenant-admin-queryable surface
-- (app.query_audit_logs, supabase/migrations/20260716113048_create_audit_trail.sql) --
-- so the session-open moment (the actual point live tenant-data access begins, per the
-- ISS-2026-187/188 fix in this same batch) is absent from the trail a tenant admin
-- actually reads. app.support_access_events itself has no tenant-visible read path at
-- all (deferred at PLT-116, per the issue's own text) -- this is a granularity gap in
-- the canonical surface, not a blind spot in the capability-scoped one.
--
-- Smallest correct fix, mirroring the ONLY existing precedent for this exact shape --
-- app.revoke_support_access's own capture_audit_event call
-- (supabase/migrations/20260716113048_create_audit_trail.sql:406-412) -- verbatim call
-- shape (tenant_id, actor_auth_user_id, actor_label, action, resource_type, resource_id,
-- result, reason, before_value, after_value), added as one more statement at the end of
-- app.start_support_session, right after its existing app.support_access_events insert,
-- no other line touched. Placed only on the genuine-new-session path, not the idempotent
-- "already open" early return (line ~586 of the original migration) -- re-calling
-- start_support_session on an already-open session is a no-op and no new session-open
-- event actually occurred, so it must not be double-logged.
--
-- actor_auth_user_id is the grantee (v_grant.grantee_auth_user_id), not a separate
-- caller identity -- app.start_support_session's own signature (p_grant_id,
-- p_reauth_confirmed_at, p_started_by) has no actor-id parameter of its own, only the
-- p_started_by text label, exactly matching app.current_support_session's own "the
-- session belongs to the grantee" framing. p_support_access_grant_id (the audit table's
-- IAE-029/037 linkage column) is deliberately left to auto-default from app.capture_
-- audit_event's own IAE-037 Tier C fix (supabase/migrations/20260809100000_harden_
-- intelligence_iae037_security_ai_hardening.sql:1205-1259): by the time this call runs,
-- the just-inserted session is already the caller's own open app.current_support_session
-- for this tenant, so the linkage populates itself the same way every other real
-- support-session-scoped mutation already does, with no extra argument needed here.
--
-- Same signature (p_grant_id uuid, p_reauth_confirmed_at timestamptz, p_started_by
-- text), so CREATE OR REPLACE -- no public.* wrapper exists for app.start_support_session
-- (service_role-only, worker/RPC-context caller per its own original grant, never
-- PostgREST-exposed), so no wrapper update is needed either.

create or replace function app.start_support_session(
  p_grant_id uuid,
  p_reauth_confirmed_at timestamptz,
  p_started_by text
)
returns app.support_access_sessions
language plpgsql
as $$
declare
  v_grant app.support_access_grants;
  v_existing app.support_access_sessions;
  v_session app.support_access_sessions;
begin
  select * into v_existing from app.support_access_sessions where grant_id = p_grant_id and ended_at is null;
  if found then
    return v_existing;
  end if;

  select * into v_grant from app.support_access_grants where id = p_grant_id;
  if not found then
    raise exception 'grant_not_found: no support access grant %', p_grant_id using errcode = 'no_data_found';
  end if;

  if v_grant.status <> 'approved' then
    raise exception 'grant_not_approved: grant % is %, cannot start a session', p_grant_id, v_grant.status
      using errcode = 'check_violation';
  end if;
  if v_grant.revoked_at is not null then
    raise exception 'grant_revoked: grant % was revoked at %', p_grant_id, v_grant.revoked_at
      using errcode = 'check_violation';
  end if;
  if v_grant.expires_at <= now() then
    raise exception 'grant_expired: grant % expired at %', p_grant_id, v_grant.expires_at
      using errcode = 'check_violation';
  end if;

  if p_reauth_confirmed_at is null or p_reauth_confirmed_at > now() or now() - p_reauth_confirmed_at > interval '5 minutes' then
    raise exception 'reauth_required: re-authentication must have completed within the last 5 minutes'
      using errcode = 'insufficient_privilege';
  end if;

  insert into app.support_access_sessions (grant_id, tenant_id, grantee_auth_user_id, reauth_confirmed_at)
  values (p_grant_id, v_grant.tenant_id, v_grant.grantee_auth_user_id, p_reauth_confirmed_at)
  returning * into v_session;

  insert into app.support_access_events (grant_id, session_id, tenant_id, grantee_auth_user_id, event_type, actor, detail)
  values (v_grant.id, v_session.id, v_grant.tenant_id, v_grant.grantee_auth_user_id, 'session_started', p_started_by, null);

  -- ISS-2026-177 fix: the canonical, tenant-admin-queryable trail (app.query_audit_logs)
  -- now also carries the session-open moment, mirroring app.revoke_support_access's own
  -- capture_audit_event call exactly.
  perform app.capture_audit_event(
    v_grant.tenant_id, v_grant.grantee_auth_user_id, p_started_by, 'start_support_session',
    'app.support_access_sessions', v_session.id, 'success', null,
    null, to_jsonb(v_session)
  );

  return v_session;
end;
$$;

comment on function app.start_support_session is
  'Activation (Prompt 115 section 4: "re-authentication"). p_reauth_confirmed_at must be a fresh (<=5 minute old) timestamp the caller obtained by having the grantee actually re-authenticate immediately beforehand. ISS-2026-177 fix: a genuinely NEW session (not the idempotent already-open return) now also leaves a canonical app.audit_logs entry via app.capture_audit_event, mirroring app.revoke_support_access''s own existing representative-platform-event integration -- closing the prior gap where session-open was recorded only in this capability''s own app.support_access_events trail, never the tenant-admin-queryable surface.';

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries its own
-- explicit `revoke execute on all functions in schema app from public` statement before
-- its final grants, the standing per-migration convention since PLT-118.
revoke execute on all functions in schema app from public;

grant execute on function app.start_support_session(uuid, timestamptz, text) to service_role;
