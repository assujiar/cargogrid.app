-- CG-AUDIT-2026-09-02 UNTRACKED-D4 (support-access console). PLT-115's own
-- support-access grant/approve/deny/revoke lifecycle (app.request_support_access
-- / app.approve_support_access / app.deny_support_access / app.revoke_support_access
-- / app.complete_support_access_post_review, 20260716111315_create_support_access.sql)
-- has been fully built, fully tested (scripts/db-tests/support-access.sql), and
-- fully wired at the server/mutations/support-access.ts layer since it shipped --
-- but had zero callers anywhere in app/. AGENTS.md itself names this control by
-- name ("Support access is purpose/time-bound, logged, tenant-visible, and
-- revocable") and today it cannot be exercised through the product at all: an
-- operator cannot grant, approve, deny, or revoke support access to a live
-- tenant, and the one real kill switch (revoke_support_access) is unreachable.
--
-- The lifecycle RPCs above are already usable as-is from a Server Action via the
-- established "explicit actor, service-role execution" pattern
-- (app/(tenant)/[tenantSlug]/admin/roles/actions.ts's own precedent -- those RPCs
-- are service_role-only too) -- no schema change needed for them. The one real
-- gap is a LIST view: app.support_access_grants already carries a real RLS SELECT
-- policy (support_access_grants_select_visible) granting exactly the right
-- visibility (the grantee's own grants; Supreme Admin sees every grant; a
-- tenant's own active tenant_admin sees every grant into that tenant), but this
-- codebase's own O1-query-layer remediation (this session, clusters 0-7)
-- eliminated every direct `.from()` read from page-level code in favor of a
-- dedicated, paginated RPC -- app.list_supreme_tenants
-- (20260913040000_close_o1_query_layer_cluster6_batch4_scheduled_reports_dashboards.sql)
-- is the exact precedent this migration mirrors: SECURITY INVOKER, zero actor
-- parameter, DELIBERATELY no in-function authority check (the table's own RLS
-- policy already decides visibility correctly), `count(*) over()` pagination,
-- identical [1,100] page-size clamp.
create function app.list_support_access_grants_for_admin(p_page integer default 1, p_page_size integer default 50)
returns table (
  id uuid,
  tenant_id uuid,
  grantee_auth_user_id uuid,
  reason text,
  case_id text,
  scope text,
  emergency boolean,
  status text,
  requested_by text,
  requested_at timestamptz,
  authorized_by_auth_user_id uuid,
  approved_by text,
  granted_at timestamptz,
  denied_by text,
  denied_at timestamptz,
  denial_reason text,
  expires_at timestamptz,
  revoked_at timestamptz,
  revoked_by text,
  revoked_reason text,
  post_review_completed_at timestamptz,
  post_review_by text,
  post_review_note text,
  record_version integer,
  created_at timestamptz,
  updated_at timestamptz,
  total_count bigint
)
language plpgsql
stable
as $$
declare
  v_limit integer;
  v_page integer;
begin
  v_limit := least(greatest(coalesce(p_page_size, 50), 1), 100);
  v_page := greatest(coalesce(p_page, 1), 1);

  return query
    select
      g.id, g.tenant_id, g.grantee_auth_user_id, g.reason, g.case_id, g.scope, g.emergency, g.status,
      g.requested_by, g.requested_at, g.authorized_by_auth_user_id, g.approved_by, g.granted_at,
      g.denied_by, g.denied_at, g.denial_reason, g.expires_at, g.revoked_at, g.revoked_by, g.revoked_reason,
      g.post_review_completed_at, g.post_review_by, g.post_review_note, g.record_version, g.created_at, g.updated_at,
      count(*) over() as total_count
    from app.support_access_grants g
    order by g.requested_at desc
    limit v_limit
    offset (v_page - 1) * v_limit;
end;
$$;

comment on function app.list_support_access_grants_for_admin is
  'CG-AUDIT-2026-09-02 UNTRACKED-D4: the support-access console''s own paginated grant list. Security invoker, zero actor parameter -- app.support_access_grants'' own support_access_grants_select_visible RLS policy already grants exactly the intended visibility (grantee sees their own grants; Supreme Admin sees every grant; a tenant''s own active tenant_admin sees every grant into that tenant), so no in-function authority check duplicates it. Mirrors app.list_supreme_tenants'' own precedent exactly (same count(*) over() pagination idiom, same [1,100] page-size clamp).';

-- RGL-394 Option-2 wrapper: app is not exposed to PostgREST.
create function public.list_support_access_grants_for_admin(p_page integer default 1, p_page_size integer default 50)
returns table (
  id uuid,
  tenant_id uuid,
  grantee_auth_user_id uuid,
  reason text,
  case_id text,
  scope text,
  emergency boolean,
  status text,
  requested_by text,
  requested_at timestamptz,
  authorized_by_auth_user_id uuid,
  approved_by text,
  granted_at timestamptz,
  denied_by text,
  denied_at timestamptz,
  denial_reason text,
  expires_at timestamptz,
  revoked_at timestamptz,
  revoked_by text,
  revoked_reason text,
  post_review_completed_at timestamptz,
  post_review_by text,
  post_review_note text,
  record_version integer,
  created_at timestamptz,
  updated_at timestamptz,
  total_count bigint
)
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_support_access_grants_for_admin(p_page, p_page_size);
$wrap$;

comment on function public.list_support_access_grants_for_admin(integer, integer) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.list_support_access_grants_for_admin with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.list_support_access_grants_for_admin(integer, integer) from public;
grant execute on function app.list_support_access_grants_for_admin(integer, integer) to authenticated, service_role;

revoke execute on function public.list_support_access_grants_for_admin(integer, integer) from anon, authenticated, service_role, public;
grant execute on function public.list_support_access_grants_for_admin(integer, integer) to authenticated, service_role;
