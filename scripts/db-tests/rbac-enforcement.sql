-- Real, executable test evidence for PLT-112 (RBAC Enforcement, CG-S6-PLT-009).

\set ON_ERROR_STOP on

\echo '>> setup: a tenant, two active users, and a published "Finance Approver" role granting FIN:Approve'
do $$
declare
  v_tenant_id uuid;
  v_role_id uuid;
  v_draft app.role_versions;
  v_permission_id uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000000401', 'grantee@example.test'),
    ('00000000-0000-0000-0000-000000000402', 'nobody@example.test');

  perform app.provision_tenant('acmerbac', 'Acme RBAC Co', 'idem-acmerbac', 'tester');
  v_tenant_id := (select id from app.tenants where slug = 'acmerbac');
  perform app.transition_tenant_status(v_tenant_id, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000000401', 'grantee@example.test', 'Grantee', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'grantee@example.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000000402', 'nobody@example.test', 'Nobody', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'nobody@example.test'), 'active', 'onboarded', 'tester');

  select id into v_role_id from app.create_role(v_tenant_id, 'RBAC Finance Approver', null, 'tester');
  select * into v_draft from app.create_role_version(v_role_id, 'tester');
  select id into v_permission_id from app.permissions where resource_module_code = 'FIN' and action = 'Approve';
  perform app.set_role_version_permissions(v_draft.id, array[v_permission_id], 'tester');
  perform app.publish_role_version(v_draft.id, now(), 'tester');

  perform app.assign_role(
    v_tenant_id,
    (select id from app.role_versions where role_id = v_role_id and status = 'published'),
    '00000000-0000-0000-0000-000000000401',
    '00000000-0000-0000-0000-000000000401',
    'tester'
  );
end;
$$;

\echo '>> a granted permission evaluates allowed=true with the role/version traced in the decision'
do $$
declare
  v_tenant_id uuid;
  v_decision app.rbac_decision;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmerbac');
  v_decision := app.evaluate_permission('00000000-0000-0000-0000-000000000401', v_tenant_id, 'FIN', 'Approve');
  if not v_decision.allowed or v_decision.reason <> 'role_grant' or v_decision.role_version_id is null then
    raise exception 'assertion failed: expected allowed=true reason=role_grant with a role_version_id, got allowed=% reason=%', v_decision.allowed, v_decision.reason;
  end if;
end;
$$;

\echo '>> an ungranted permission for the same identity fails closed with a distinct reason from "no assignment at all"'
do $$
declare
  v_tenant_id uuid;
  v_decision app.rbac_decision;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmerbac');
  v_decision := app.evaluate_permission('00000000-0000-0000-0000-000000000401', v_tenant_id, 'FIN', 'Reject');
  if v_decision.allowed or v_decision.reason <> 'no_granting_role' then
    raise exception 'assertion failed: expected allowed=false reason=no_granting_role, got allowed=% reason=%', v_decision.allowed, v_decision.reason;
  end if;
end;
$$;

\echo '>> an identity with no role assignment at all fails closed with its own distinct reason'
do $$
declare
  v_tenant_id uuid;
  v_decision app.rbac_decision;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmerbac');
  v_decision := app.evaluate_permission('00000000-0000-0000-0000-000000000402', v_tenant_id, 'FIN', 'Approve');
  if v_decision.allowed or v_decision.reason <> 'no_active_assignment' then
    raise exception 'assertion failed: expected allowed=false reason=no_active_assignment, got allowed=% reason=%', v_decision.allowed, v_decision.reason;
  end if;
end;
$$;

\echo '>> an unknown module/action pair fails closed rather than raising'
do $$
declare
  v_tenant_id uuid;
  v_decision app.rbac_decision;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmerbac');
  v_decision := app.evaluate_permission('00000000-0000-0000-0000-000000000401', v_tenant_id, 'FIN', 'Teleport');
  if v_decision.allowed or v_decision.reason <> 'unknown_permission' then
    raise exception 'assertion failed: expected allowed=false reason=unknown_permission, got allowed=% reason=%', v_decision.allowed, v_decision.reason;
  end if;
end;
$$;

\echo '>> a revoked role assignment fails closed even though the role version is still published'
do $$
declare
  v_tenant_id uuid;
  v_assignment app.role_assignments;
  v_decision app.rbac_decision;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmerbac');
  select * into v_assignment from app.role_assignments where tenant_id = v_tenant_id and auth_user_id = '00000000-0000-0000-0000-000000000401' and status = 'active';
  perform app.revoke_role_assignment(v_assignment.id, 'test revoke', 'tester');

  v_decision := app.evaluate_permission('00000000-0000-0000-0000-000000000401', v_tenant_id, 'FIN', 'Approve');
  if v_decision.allowed then
    raise exception 'assertion failed: expected a revoked assignment to deny, but it allowed';
  end if;

  -- re-grant for the remaining tests in this file
  perform app.assign_role(
    v_tenant_id,
    (select id from app.role_versions where role_id = (select id from app.roles where name = 'RBAC Finance Approver') and status = 'published'),
    '00000000-0000-0000-0000-000000000401',
    '00000000-0000-0000-0000-000000000401',
    'tester'
  );
end;
$$;

\echo '>> a stale assignment (still active, but pointing at a now-archived, superseded role version) fails closed -- PLT-112 §23''s "stale permission fails closed"'
do $$
declare
  v_tenant_id uuid;
  v_role_id uuid;
  v_new_draft app.role_versions;
  v_decision app.rbac_decision;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmerbac');
  v_role_id := (select id from app.roles where name = 'RBAC Finance Approver');

  -- Publish a *new* version of the same role -- this archives (supersedes) the version
  -- the existing assignment still points to, without touching app.role_assignments itself.
  select * into v_new_draft from app.create_role_version(v_role_id, 'tester');
  perform app.set_role_version_permissions(v_new_draft.id, array[(select id from app.permissions where resource_module_code = 'FIN' and action = 'Approve')], 'tester');
  perform app.publish_role_version(v_new_draft.id, now(), 'tester');

  v_decision := app.evaluate_permission('00000000-0000-0000-0000-000000000401', v_tenant_id, 'FIN', 'Approve');
  if v_decision.allowed or v_decision.reason <> 'no_granting_role' then
    raise exception 'assertion failed: expected the stale assignment to deny (reason=no_granting_role), got allowed=% reason=%', v_decision.allowed, v_decision.reason;
  end if;

  -- re-assigning to the newly published version restores access -- proving the denial
  -- above was caused by staleness, not by some other unrelated breakage.
  perform app.assign_role(
    v_tenant_id, v_new_draft.id,
    '00000000-0000-0000-0000-000000000401', '00000000-0000-0000-0000-000000000401', 'tester'
  );
  v_decision := app.evaluate_permission('00000000-0000-0000-0000-000000000401', v_tenant_id, 'FIN', 'Approve');
  if not v_decision.allowed then
    raise exception 'assertion failed: expected access restored once re-assigned to the newly published version';
  end if;
end;
$$;

\echo '>> role names never authorize: a role literally named to sound like a bypass, with no matching permission, still denies'
do $$
declare
  v_tenant_id uuid;
  v_role_id uuid;
  v_draft app.role_versions;
  v_unrelated_permission_id uuid;
  v_decision app.rbac_decision;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmerbac');
  select id into v_role_id from app.create_role(v_tenant_id, 'SuperAdminBypassAllChecks', 'A role whose *name* implies unlimited access', 'tester');
  select * into v_draft from app.create_role_version(v_role_id, 'tester');
  select id into v_unrelated_permission_id from app.permissions where resource_module_code = 'TKT' and action = 'View';
  perform app.set_role_version_permissions(v_draft.id, array[v_unrelated_permission_id], 'tester');
  perform app.publish_role_version(v_draft.id, now(), 'tester');
  perform app.assign_role(
    v_tenant_id,
    (select id from app.role_versions where role_id = v_role_id and status = 'published'),
    '00000000-0000-0000-0000-000000000402',
    '00000000-0000-0000-0000-000000000401',
    'tester'
  );

  v_decision := app.evaluate_permission('00000000-0000-0000-0000-000000000402', v_tenant_id, 'FIN', 'Approve');
  if v_decision.allowed then
    raise exception 'assertion failed: expected a role whose name implies bypass, but whose bindings do not grant FIN:Approve, to deny -- got allowed=true';
  end if;

  -- the same identity IS granted the one permission actually bound to that role
  v_decision := app.evaluate_permission('00000000-0000-0000-0000-000000000402', v_tenant_id, 'TKT', 'View');
  if not v_decision.allowed then
    raise exception 'assertion failed: expected the actually-bound permission to be granted regardless of the role''s name';
  end if;
end;
$$;

\echo '>> multiple granted roles combine additively (union): a second role grants a second, distinct permission'
do $$
declare
  v_tenant_id uuid;
  v_role_id uuid;
  v_draft app.role_versions;
  v_permission_id uuid;
  v_decision_fin app.rbac_decision;
  v_decision_tkt app.rbac_decision;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmerbac');
  select id into v_role_id from app.create_role(v_tenant_id, 'Ticket Closer', null, 'tester');
  select * into v_draft from app.create_role_version(v_role_id, 'tester');
  select id into v_permission_id from app.permissions where resource_module_code = 'TKT' and action = 'Close';
  perform app.set_role_version_permissions(v_draft.id, array[v_permission_id], 'tester');
  perform app.publish_role_version(v_draft.id, now(), 'tester');
  perform app.assign_role(
    v_tenant_id,
    (select id from app.role_versions where role_id = v_role_id and status = 'published'),
    '00000000-0000-0000-0000-000000000402',
    '00000000-0000-0000-0000-000000000401',
    'tester'
  );

  v_decision_tkt := app.evaluate_permission('00000000-0000-0000-0000-000000000402', v_tenant_id, 'TKT', 'Close');
  v_decision_fin := app.evaluate_permission('00000000-0000-0000-0000-000000000402', v_tenant_id, 'TKT', 'View');
  if not v_decision_tkt.allowed or not v_decision_fin.allowed then
    raise exception 'assertion failed: expected both roles'' distinct grants to independently allow, got Close=% View=%', v_decision_tkt.allowed, v_decision_fin.allowed;
  end if;
end;
$$;

\echo '>> cross-tenant isolation: a role assignment in one tenant grants nothing when evaluated against another tenant'
do $$
declare
  v_other_tenant_id uuid;
  v_decision app.rbac_decision;
begin
  perform app.provision_tenant('gizmorbac', 'Gizmo RBAC Co', 'idem-gizmorbac', 'tester');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmorbac');
  perform app.transition_tenant_status(v_other_tenant_id, 'active', 'setup', 'tester');

  v_decision := app.evaluate_permission('00000000-0000-0000-0000-000000000401', v_other_tenant_id, 'FIN', 'Approve');
  if v_decision.allowed then
    raise exception 'assertion failed: expected a grant in acmerbac to never apply to gizmorbac, but it allowed';
  end if;
end;
$$;

\echo '>> the Supreme Admin exception (RPD-022) bypasses the role/permission lookup entirely, even with zero role assignments'
do $$
declare
  v_tenant_id uuid;
  v_new_identity uuid := '00000000-0000-0000-0000-000000000403';
  v_decision app.rbac_decision;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmerbac');
  insert into auth.users (id, email) values (v_new_identity, 'supreme@example.test');
  perform app.grant_principal_membership(v_new_identity, 'supreme_admin', null, null, 'tester');

  v_decision := app.evaluate_permission(v_new_identity, v_tenant_id, 'FIN', 'Approve');
  if not v_decision.allowed or v_decision.reason <> 'supreme_admin_exception' then
    raise exception 'assertion failed: expected allowed=true reason=supreme_admin_exception, got allowed=% reason=%', v_decision.allowed, v_decision.reason;
  end if;
end;
$$;

\echo '>> defense in depth: anon and authenticated cannot call the evaluator; service_role can'
do $$
begin
  set local role anon;
  begin
    perform app.evaluate_permission('00000000-0000-0000-0000-000000000401', (select id from app.tenants where slug = 'acmerbac'), 'FIN', 'Approve');
    raise exception 'assertion failed: anon must be denied execute privilege on app.evaluate_permission';
  exception
    when insufficient_privilege then
      null; -- expected
  end;
  reset role;
end;
$$;

do $$
declare
  v_decision app.rbac_decision;
begin
  set local role service_role;
  v_decision := app.evaluate_permission('00000000-0000-0000-0000-000000000401', (select id from app.tenants where slug = 'acmerbac'), 'FIN', 'Approve');
  if not v_decision.allowed then
    raise exception 'assertion failed: service_role must be able to evaluate and get the expected allowed result';
  end if;
  reset role;
end;
$$;

\echo '>> ATW-031 (ISS-2026-017): an authenticated session may not act as another identity. Every SECURITY DEFINER RPC takes the acting identity as an ordinary parameter; until this repair none cross-checked it against auth.uid(), so any authenticated session could pass an arbitrary UUID and have authority, record scope and audit all evaluated as that other user. app.evaluate_permission -- the single authority gate 416 functions share -- now calls app.assert_actor_is_session_identity first.'
do $$
declare
  v_self uuid := '00000000-0000-0000-0000-000000000401';
  v_victim uuid := '00000000-0000-0000-0000-000000000402';
  v_raised boolean := false;
  v_wired boolean;
begin
  -- 1. The wiring: app.evaluate_permission really does call the assertion. Proven against
  --    the live function body, not assumed from the migration text.
  select prosrc like '%assert_actor_is_session_identity%' into v_wired
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'evaluate_permission';
  if not coalesce(v_wired, false) then
    raise exception 'assertion failed: app.evaluate_permission does not call app.assert_actor_is_session_identity -- the ISS-2026-017 cross-check is not wired in';
  end if;

  -- 2. No JWT -- the service_role/superuser/db-test/nested-definer path. auth.uid() is
  --    NULL, so the check is a deliberate no-op and no existing caller is affected.
  perform app.assert_actor_is_session_identity(v_victim);

  -- 3. A genuine authenticated session claiming to be SOMEONE ELSE must be refused.
  perform set_config('request.jwt.claims', json_build_object('sub', v_self::text, 'role', 'authenticated')::text, true);
  begin
    perform app.assert_actor_is_session_identity(v_victim);
    raise exception 'assertion failed: a session authenticated as % was allowed to act as % -- ISS-2026-017 is still open', v_self, v_victim;
  exception
    when insufficient_privilege then
      if sqlerrm !~ 'actor_identity_mismatch' then raise; end if;
      v_raised := true;
  end;
  if not v_raised then
    raise exception 'assertion failed: expected actor_identity_mismatch';
  end if;

  -- 4. The same session acting as ITSELF is completely unaffected -- which is exactly what
  --    this repository's own TypeScript service layer always does (it derives the actor
  --    from the server-resolved session, never from user input).
  perform app.assert_actor_is_session_identity(v_self);

  perform set_config('request.jwt.claims', '', true);
  raise notice 'ATW-031 actor-identity proof: app.evaluate_permission is wired to the check; an authenticated session may act only as itself; a NULL session identity remains an intentional no-op';
end;
$$;

\echo '>> ATW-032 (ISS-2026-033): the SECURITY DEFINER authority surface. A SECURITY DEFINER function runs as its owner and bypasses RLS, so granting one to authenticated hands every logged-in user of every tenant whatever it does unless the function checks authority itself. This asserts the sweep stays closed: the internal helpers stay un-granted, the guarded ones stay guarded, and the functions that are correct by design keep the grant they need.'
do $$
declare
  v_fn text;
  v_unauthorized text[];
  v_expected text[] := array[
    -- Anon-facing by design, or authenticated by another mechanism entirely.
    'ingest_third_party_provider_webhook_event', 'lookup_public_shipment_tracking',
    'evaluate_tenant_brand', 'resolve_tenant_by_domain', 'resolve_tenant_locale',
    'resolve_locale_context',
    -- Authority/scope PRIMITIVES. These are the check, so they cannot check themselves, and
    -- they must stay executable by authenticated because RLS policy expressions and view
    -- bodies are evaluated as the QUERYING role -- revoking one breaks every authenticated
    -- read of the tables whose policies call it.
    'is_supreme_admin', 'lead_record_scope_org_unit_ids', 'actor_can_view_owner_scoped_row',
    'actor_holds_customer_user_layer', 'resolve_commercial_record_ref',
    'pipeline_scope_org_unit_ids', 'assert_actor_is_session_identity',
    'current_support_session', 'has_active_support_grant',
    'customer_warehouse_eligibility_active', 'resolve_customer_owner_account_scope',
    'evaluate_dispatch_readiness'
  ];
begin
  -- 1. The five internal helpers must carry NO authenticated grant. Each takes no actor
  --    parameter, so it cannot check authority even in principle; before ATW-032 any
  --    logged-in user could call them with another tenant's identifiers -- including
  --    rewriting that tenant's quotation money columns.
  foreach v_fn in array array['recalculate_quotation_totals', 'next_quotation_number',
                              'generate_route_planning_candidates',
                              'check_leg_tracking_source_eligible', 'dashboard_scope_org_unit_ids'] loop
    if exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      cross join lateral aclexplode(p.proacl) a
      where n.nspname = 'app' and p.proname = v_fn
        and a.privilege_type = 'EXECUTE' and pg_get_userbyid(a.grantee) in ('anon', 'authenticated')
    ) then
      raise exception 'assertion failed: app.% must NOT be granted to anon/authenticated -- it takes no actor parameter and cannot check authority (ISS-2026-033)', v_fn;
    end if;
  end loop;

  -- 2. The seven client-callable ones must still carry the guard.
  foreach v_fn in array array['resolve_config', 'verify_config_version_current',
                              'evaluate_feature_flag', 'record_customer_inventory_access_denial',
                              'run_next_route_planning_job', 'get_shipment_leg_network_state',
                              'render_notification_template'] loop
    if not exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'app' and p.proname = v_fn
        and p.prosrc like '%assert_session_identity_in_tenant%'
    ) then
      raise exception 'assertion failed: app.% must call app.assert_session_identity_in_tenant -- it is granted to authenticated and has no other authority check (ISS-2026-033)', v_fn;
    end if;
  end loop;

  -- 3. The sweep itself: no NEW function may join the unauthorized set. This is the part
  --    that keeps the class closed as Phase 6+ adds surface, rather than re-opening it.
  with recursive fn as (
    select p.oid, p.proname, p.prosrc, p.prosecdef, p.proacl
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'app'
  ),
  edge as (select f.proname caller, m[1] callee from fn f, regexp_matches(f.prosrc, 'app\.([a-z0-9_]+)\s*\(', 'g') m),
  base as (
    select distinct proname from fn
    where prosrc ~ 'evaluate_permission|can_access_record|is_supreme_admin|has_active_membership|check_[a-z_]*authority|is_eligible_[a-z_]*approver|resolve_customer_owner_account_scope|customer_warehouse_eligibility_active|actor_can_view_owner_scoped_row|authorize_file_access|assert_session_identity_in_tenant'
  ),
  closure as (
    select proname from base
    union
    select e.caller from edge e join closure c on c.proname = e.callee
  )
  select array_agg(f.proname order by f.proname) into v_unauthorized
  from fn f
  where f.prosecdef
    and exists (select 1 from aclexplode(f.proacl) a where a.privilege_type = 'EXECUTE' and pg_get_userbyid(a.grantee) = 'authenticated')
    and f.proname not in (select proname from closure)
    and f.proname <> all (v_expected);

  if v_unauthorized is not null then
    raise exception 'assertion failed: % SECURITY DEFINER function(s) are granted to authenticated with no authority check anywhere in their call graph, and are not on the reviewed-and-justified list: %. Either add app.evaluate_permission + app.can_access_record (or app.assert_session_identity_in_tenant), revoke the grant, or -- if it is genuinely correct by design -- add it to v_expected here WITH a written reason (ISS-2026-033)', array_length(v_unauthorized, 1), v_unauthorized;
  end if;

  raise notice 'ATW-032 authority-surface proof: 5 internal helpers carry no client grant, 7 client-callable functions carry the session-membership guard, and no unreviewed SECURITY DEFINER function is granted to authenticated';
end;
$$;

\echo '>> ATW-032: optimistic concurrency must not be a check-then-act race. Every function that takes p_expected_version must either lock the row it checked (select ... for update) or repeat the version predicate in its own UPDATE. Without one of the two, two callers both read version N, both pass the check, and the second silently overwrites the first -- a lost approval, posting or delivery decision, with neither caller told anything.'
do $$
declare
  v_unsafe text[];
begin
  select array_agg(p.proname order by p.proname) into v_unsafe
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'app'
    and pg_get_function_arguments(p.oid) like '%p_expected_version%'
    and p.prosrc ~ 'update app\.'
    and p.prosrc !~ 'record_version = p_expected_version'   -- no version predicate on the UPDATE
    and p.prosrc !~* 'for update';                          -- and no row lock on the read

  if v_unsafe is not null then
    raise exception 'assertion failed: % function(s) take p_expected_version but neither lock the checked row (select ... for update) nor repeat record_version = p_expected_version in their UPDATE, so two concurrent callers can both pass the check and the second silently overwrites the first: %', array_length(v_unsafe, 1), v_unsafe;
  end if;

  raise notice 'ATW-032 optimistic-concurrency proof: every p_expected_version function either locks the row it checked or re-checks the version at the write';
end;
$$;

\echo 'ALL PLT-112 db-test assertions passed.'
