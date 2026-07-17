-- Platform Core capability PLT-114 (Field-Level and Record-Level Access, CG-S6-PLT-011)
-- Stages 5-6 of the 8-stage access-evaluation flow (docs/architecture/06_RLS_RBAC_WORKSTREAM.md
-- §3: "5 Field-level policy", "6 Status/value rule"). Two independent mechanisms, both
-- "shared policy model" foundations per Prompt 114 §4/§20 task 1 -- not yet wired to any
-- business-domain table, since none exists in Phase 1 Platform Core.
--
-- (1) app.can_access_record() -- the exact real function name and STABLE-helper pattern
-- docs/architecture/06_RLS_RBAC_WORKSTREAM.md already names twice: line 87 ("Tech Arch
-- §11.3's app.can_access_record example, verbatim") and line 149 (listing it alongside
-- app.current_tenant_id()/app.is_tenant_member() as a STABLE helper every RLS policy
-- calls). Record ownership follows owner_user_id with sharing expressed as additional
-- scope grants -- team/department/branch (i.e. app.org_units) -- "never a second
-- ownership column" (§5.3, verbatim). No table in this repository carries owner_user_id
-- yet (it belongs to business-domain tables -- lead/opportunity/quote/task per
-- 05_DATABASE_SCHEMA_WORKSTREAM.md line 44 -- none of which exist in Phase 1), so this
-- function is proven exhaustively by direct call in scripts/db-tests/field-record-access.sql
-- rather than by a live RLS policy on a real table -- disclosed, not silently skipped, the
-- same NOT_RUN discipline every prior "no live consumer yet" capability this session used.
--
-- (2) Field-level masking, the concrete "foundation example" §12 explicitly permits
-- ("Domain-specific policies beyond foundation examples" are forbidden, implying exactly
-- one foundation example is expected). app.users.email is the one real, already-existing
-- PII-classified column in Platform Core today (docs/standards/DATA_CLASSIFICATION_STANDARDS.md's
-- PII category); it is masked from anyone who does not hold the already-seeded, real
-- 'View personal data' permission (PLT-111, HRS module, category='sensitive',
-- protected=true -- docs/architecture/06_RLS_RBAC_WORKSTREAM.md §5.2's exact field-masking
-- table). A column-level REVOKE on app.users.email (not merely "please use the view")
-- makes the raw column itself unreachable by `authenticated` -- a database guarantee, not
-- an application convention, matching this session's discipline since PLT-105.

create function app.can_access_record(
  p_auth_user_id uuid,
  p_tenant_id uuid,
  p_owner_user_id uuid,
  p_shared_org_unit_ids uuid[] default '{}',
  p_customer_account_ref text default null
)
returns boolean
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select
    app.has_active_tenant_membership(p_tenant_id, p_auth_user_id)
    and (
      app.is_supreme_admin(p_auth_user_id)
      or p_owner_user_id = p_auth_user_id
      or exists (
        select 1 from app.users u
        where u.auth_user_id = p_auth_user_id
          and u.tenant_id = p_tenant_id
          and u.status = 'active'
          and u.org_unit_id = any(p_shared_org_unit_ids)
      )
      or (
        p_customer_account_ref is not null
        and exists (
          select 1 from app.principal_memberships pm
          where pm.auth_user_id = p_auth_user_id
            and pm.tenant_id = p_tenant_id
            and pm.layer = 'customer_user'
            and pm.status = 'active'
            and pm.customer_account_ref = p_customer_account_ref
        )
      )
    );
$$;

comment on function app.can_access_record is
  'Record-scope evaluator (PLT-114) -- the real app.can_access_record() name docs/architecture/06_RLS_RBAC_WORKSTREAM.md already fixes (Tech Arch §11.3/§11.2). Tenant membership is a hard prerequisite (fails closed regardless of owner/share/customer match); within that, access is granted by ownership (owner_user_id), shared team/branch scope (the caller''s own app.org_units assignment, PLT-110), customer-account scope (PLT-108''s customer_user layer), or the Supreme Admin exception. No business-domain table references this function yet -- proven by direct call only (see build log §2).';

grant execute on function app.can_access_record(uuid, uuid, uuid, uuid[], text) to authenticated;
grant execute on function app.can_access_record(uuid, uuid, uuid, uuid[], text) to service_role;

-- app.users_directory (below) needs to know whether the caller holds 'HRS:View personal
-- data' -- but app.evaluate_permission() (PLT-112) is SECURITY INVOKER, and its own
-- internal reads (app.permissions, app.role_version_permissions, ...) are deliberately
-- service_role-only per PLT-113's own scope decision (global catalogues were left out of
-- authenticated's grants there). Granting authenticated broad direct access to those
-- catalogue tables just to make one field-masking check work would widen PLT-113's scope
-- decision for a reason that has nothing to do with it. Instead, this narrow, SECURITY
-- DEFINER wrapper answers exactly one bounded question -- proven empirically during
-- authoring (build log §8): a SECURITY DEFINER function's elevated privilege context
-- carries through to functions it calls internally (even SECURITY INVOKER ones like
-- evaluate_permission), so the wrapper's owner rights are what evaluate_permission's own
-- internal catalogue reads run under here, not authenticated's.
create function app.has_view_personal_data(p_tenant_id uuid, p_auth_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select (app.evaluate_permission(p_auth_user_id, p_tenant_id, 'HRS', 'View personal data')).allowed;
$$;

comment on function app.has_view_personal_data is
  'Field-masking gate (PLT-114) -- true if the caller holds the real, seeded HRS:View personal data permission (PLT-111/112) for the given tenant. SECURITY DEFINER so app.users_directory can call it without authenticated needing direct access to app.permissions/app.role_version_permissions.';

grant execute on function app.has_view_personal_data(uuid, uuid) to authenticated;

-- Field masking: a deterministic, non-reversible redaction shape (keeps only the first
-- character and the domain) -- not a security control on its own (a masked value is still
-- server-computed and never derivable by the caller from anything they legitimately have),
-- just a safe, recognizable placeholder for UI rendering per Prompt 114 §15's "render
-- masked ... states from server metadata."
create function app.mask_email(p_email text)
returns text
language sql
immutable
as $$
  select case
    when p_email is null then null
    when position('@' in p_email) <= 1 then '***'
    else left(p_email, 1) || '***@' || split_part(p_email, '@', 2)
  end;
$$;

comment on function app.mask_email is 'Deterministic email redaction for field-masking (PLT-114) -- e.g. j***@example.com. Rendering aid only; the real access control is the column-scoped grant below, not this function.';

-- The database guarantee: `authenticated` can no longer SELECT the raw email column at
-- all, on any row, regardless of RLS -- forcing every read through app.users_directory
-- below, which decides per-row whether to reveal it.
--
-- A bare `revoke select (email) on app.users from authenticated` is NOT sufficient here --
-- proven empirically during authoring (see build log §8): table-level and column-level
-- ACLs in Postgres are additive, not layered with override semantics. A column-level
-- REVOKE only removes a *previous column-level* GRANT; it cannot carve an exception out of
-- PLT-113's broader table-level `grant select on app.users to authenticated`. The correct,
-- documented pattern is to REVOKE the table-level grant entirely and re-GRANT SELECT on an
-- explicit column list that omits `email` -- proven to actually deny direct email access
-- in scripts/db-tests/field-record-access.sql.
revoke select on app.users from authenticated;
grant select (
  id, tenant_id, auth_user_id, display_name, status, org_unit_id, invited_by, invited_at,
  invite_expires_at, activated_at, suspended_at, suspended_reason, revoked_at,
  revoked_reason, record_version, created_at, updated_at
) on app.users to authenticated;

-- security_invoker defaults to false (Postgres's pre-15 legacy behavior, still the
-- default in 16) -- the view's defining query runs with its OWNER's privileges, which is
-- exactly what lets it read the raw (REVOKEd-from-authenticated) email column internally
-- while still deciding, per row, what the querying `authenticated` role is shown.
create view app.users_directory as
select
  u.id,
  u.tenant_id,
  u.auth_user_id,
  u.display_name,
  u.status,
  u.org_unit_id,
  case
    when app.has_view_personal_data(u.tenant_id) then u.email
    else app.mask_email(u.email)
  end as email,
  not app.has_view_personal_data(u.tenant_id) as email_masked,
  u.created_at,
  u.updated_at
from app.users u;

comment on view app.users_directory is
  'Field-masked projection of app.users (PLT-114) -- the foundation example for field-level policy. email is redacted (app.mask_email()) unless the caller holds the real, seeded ''HRS:View personal data'' permission (PLT-111/112); email_masked tells a future UI which state it is looking at without guessing.';

grant select on app.users_directory to authenticated;
grant select on app.users_directory to service_role;
