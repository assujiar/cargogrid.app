-- ISS-2026-123 -- closes a real, missing functional dependency discovered while building this
-- entry's own two new request tables: NO staff-facing list RPC exists for ANY customer-portal
-- change-request table, including the already-applied, already-VERIFIED sibling
-- app.customer_portal_profile_change_requests (CPL-314). Confirmed live before writing this
-- migration, not assumed: app.list_customer_portal_profile_change_requests (20260801150000)
-- gates its own result set on `app.resolve_customer_account_scope(p_actor_auth_user_id,
-- p_tenant_id)` -- a Layer-4 CUSTOMER's own resolved account scope. A staff identity holds no
-- such scope (it has no app.customer_portal_account_memberships row at all in the ordinary
-- case), so that function always returns EMPTY for a staff caller, tenant-wide, regardless of
-- how many requests are actually pending. The identical shape was about to repeat verbatim for
-- this entry's own two new list RPCs (app.list_customer_portal_legal_identity_change_requests /
-- app.list_customer_portal_contact_change_requests, both 20260901080000/20260901090000) --
-- every one of the three tables was, and without this migration would remain, a write-only
-- inbox: real requests land, and no RPC exists anywhere a staff reviewer could call to see them.
--
-- This migration adds exactly one new, staff-facing, COM:Approve-gated list RPC per table --
-- never edits any already-applied function or table, never widens an existing customer-facing
-- list RPC's own scope (that would blur a Layer-4/staff authority boundary that is currently
-- clean: the existing three list RPCs stay account-scope-only, customer-callable only in
-- practice). Deny-by-default mirrors every other list RPC in this codebase: an actor lacking
-- COM:Approve gets an empty result, never an error (a list is not a get-by-id; no enumeration
-- oracle risk either way, since "the request exists" is not something an unauthorized staff
-- caller could infer from an empty list any more than from a populated tenant).
--
-- Every actor-taking function calls app.assert_actor_is_session_identity as its own literal
-- first statement. Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit
-- `revoke execute on all functions in schema app from public` before final grants. public.*
-- wrappers (RGL-394 Option 2) ship in this same migration.

create function app.list_profile_change_requests_staff_review(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_status text default 'pending',
  p_cursor_updated_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns setof app.customer_portal_profile_change_requests
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_limit integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_cursor_id is not null and p_cursor_updated_at is null then
    raise exception 'invalid_cursor: p_cursor_updated_at is required when p_cursor_id is supplied' using errcode = 'invalid_parameter_value';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'COM', 'Approve');
  if not v_decision.allowed then
    return;
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select r.*
  from app.customer_portal_profile_change_requests r
  where r.tenant_id = p_tenant_id
    and (p_status is null or r.status = p_status)
    and (p_cursor_id is null or (r.updated_at, r.id) < (p_cursor_updated_at, p_cursor_id))
  order by r.updated_at desc, r.id desc
  limit v_limit;
end;
$$;

comment on function app.list_profile_change_requests_staff_review is
  'ISS-2026-123: staff-facing (COM:Approve-gated), TENANT-WIDE listing of app.customer_portal_profile_change_requests -- the account-scope-only app.list_customer_portal_profile_change_requests (CPL-314) always returns empty for a staff caller, which has no customer account scope. Deny-by-default: an actor lacking COM:Approve gets an empty result, never an error. Keyset-paginated (tenant_id, updated_at desc, id desc), hard-capped at 200.';

create function app.list_legal_identity_change_requests_staff_review(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_status text default 'pending',
  p_cursor_updated_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns setof app.customer_portal_legal_identity_change_requests
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_limit integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_cursor_id is not null and p_cursor_updated_at is null then
    raise exception 'invalid_cursor: p_cursor_updated_at is required when p_cursor_id is supplied' using errcode = 'invalid_parameter_value';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'COM', 'Approve');
  if not v_decision.allowed then
    return;
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select r.*
  from app.customer_portal_legal_identity_change_requests r
  where r.tenant_id = p_tenant_id
    and (p_status is null or r.status = p_status)
    and (p_cursor_id is null or (r.updated_at, r.id) < (p_cursor_updated_at, p_cursor_id))
  order by r.updated_at desc, r.id desc
  limit v_limit;
end;
$$;

comment on function app.list_legal_identity_change_requests_staff_review is
  'ISS-2026-123: staff-facing (COM:Approve-gated), TENANT-WIDE listing of app.customer_portal_legal_identity_change_requests -- mirrors app.list_profile_change_requests_staff_review exactly, for the same reason (the account-scope-only list RPC always returns empty for a staff caller).';

create function app.list_contact_change_requests_staff_review(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_status text default 'pending',
  p_cursor_updated_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns setof app.customer_portal_contact_change_requests
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_limit integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_cursor_id is not null and p_cursor_updated_at is null then
    raise exception 'invalid_cursor: p_cursor_updated_at is required when p_cursor_id is supplied' using errcode = 'invalid_parameter_value';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'COM', 'Approve');
  if not v_decision.allowed then
    return;
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select r.*
  from app.customer_portal_contact_change_requests r
  where r.tenant_id = p_tenant_id
    and (p_status is null or r.status = p_status)
    and (p_cursor_id is null or (r.updated_at, r.id) < (p_cursor_updated_at, p_cursor_id))
  order by r.updated_at desc, r.id desc
  limit v_limit;
end;
$$;

comment on function app.list_contact_change_requests_staff_review is
  'ISS-2026-123: staff-facing (COM:Approve-gated), TENANT-WIDE listing of app.customer_portal_contact_change_requests -- mirrors app.list_profile_change_requests_staff_review exactly.';

revoke execute on all functions in schema app from public;

grant execute on function app.list_profile_change_requests_staff_review(uuid, uuid, text, timestamptz, uuid, integer) to authenticated, service_role;
grant execute on function app.list_legal_identity_change_requests_staff_review(uuid, uuid, text, timestamptz, uuid, integer) to authenticated, service_role;
grant execute on function app.list_contact_change_requests_staff_review(uuid, uuid, text, timestamptz, uuid, integer) to authenticated, service_role;

-- ===========================================================================
-- public.* wrappers (RGL-394 Option 2)
-- ===========================================================================

create function public.list_profile_change_requests_staff_review(
  p_tenant_id uuid, p_actor_auth_user_id uuid, p_status text default 'pending'::text,
  p_cursor_updated_at timestamptz default null::timestamptz, p_cursor_id uuid default null::uuid, p_limit integer default 50
)
returns setof app.customer_portal_profile_change_requests
language sql
stable
security definer
set search_path = app, public, pg_temp
as $wrap$
  select * from app.list_profile_change_requests_staff_review(p_tenant_id, p_actor_auth_user_id, p_status, p_cursor_updated_at, p_cursor_id, p_limit);
$wrap$;

comment on function public.list_profile_change_requests_staff_review(uuid, uuid, text, timestamptz, uuid, integer) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.list_profile_change_requests_staff_review, never a reimplementation.';

revoke execute on function public.list_profile_change_requests_staff_review(uuid, uuid, text, timestamptz, uuid, integer) from anon, authenticated, service_role, public;
grant execute on function public.list_profile_change_requests_staff_review(uuid, uuid, text, timestamptz, uuid, integer) to authenticated, service_role;

create function public.list_legal_identity_change_requests_staff_review(
  p_tenant_id uuid, p_actor_auth_user_id uuid, p_status text default 'pending'::text,
  p_cursor_updated_at timestamptz default null::timestamptz, p_cursor_id uuid default null::uuid, p_limit integer default 50
)
returns setof app.customer_portal_legal_identity_change_requests
language sql
stable
security definer
set search_path = app, public, pg_temp
as $wrap$
  select * from app.list_legal_identity_change_requests_staff_review(p_tenant_id, p_actor_auth_user_id, p_status, p_cursor_updated_at, p_cursor_id, p_limit);
$wrap$;

comment on function public.list_legal_identity_change_requests_staff_review(uuid, uuid, text, timestamptz, uuid, integer) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.list_legal_identity_change_requests_staff_review, never a reimplementation.';

revoke execute on function public.list_legal_identity_change_requests_staff_review(uuid, uuid, text, timestamptz, uuid, integer) from anon, authenticated, service_role, public;
grant execute on function public.list_legal_identity_change_requests_staff_review(uuid, uuid, text, timestamptz, uuid, integer) to authenticated, service_role;

create function public.list_contact_change_requests_staff_review(
  p_tenant_id uuid, p_actor_auth_user_id uuid, p_status text default 'pending'::text,
  p_cursor_updated_at timestamptz default null::timestamptz, p_cursor_id uuid default null::uuid, p_limit integer default 50
)
returns setof app.customer_portal_contact_change_requests
language sql
stable
security definer
set search_path = app, public, pg_temp
as $wrap$
  select * from app.list_contact_change_requests_staff_review(p_tenant_id, p_actor_auth_user_id, p_status, p_cursor_updated_at, p_cursor_id, p_limit);
$wrap$;

comment on function public.list_contact_change_requests_staff_review(uuid, uuid, text, timestamptz, uuid, integer) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.list_contact_change_requests_staff_review, never a reimplementation.';

revoke execute on function public.list_contact_change_requests_staff_review(uuid, uuid, text, timestamptz, uuid, integer) from anon, authenticated, service_role, public;
grant execute on function public.list_contact_change_requests_staff_review(uuid, uuid, text, timestamptz, uuid, integer) to authenticated, service_role;
