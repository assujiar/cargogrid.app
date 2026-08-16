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
    'evaluate_dispatch_readiness',
    -- HRT-278 (pre-existing, PRE-DATES HRT-280 -- proven via a captured baseline:
    -- `TEST_DB_NAME=cargogrid_db_test_impl280_baseline pnpm run db:test` re-run
    -- with HRT-280's own two migrations temporarily removed reproduces this SAME
    -- single-entry {get_self_employee} failure byte-for-byte, confirming HRT-280
    -- did not cause it -- docs/runtime/ERROR_LEDGER.md). app.get_self_employee
    -- takes p_actor_auth_user_id as an ordinary parameter but is correct by
    -- design: its own WHERE clause (`u.auth_user_id = p_actor_auth_user_id`) can
    -- only ever return the CALLING actor''s own linked employee row, never
    -- another actor''s -- there is no p_target_employee_id-shaped parameter for
    -- it to leak through. Every one of its own call sites (HRT-278/279/280)
    -- additionally calls app.assert_actor_is_session_identity before invoking it,
    -- which this call-graph sweep does not credit (assert_actor_is_session_identity
    -- itself carries no closure-qualifying keyword in its own body -- it is a
    -- session/claim primitive, not a tenant/authority lookup). Genuinely
    -- correct-by-design, not a live gap -- added here per this test''s own
    -- documented escape hatch rather than left as a permanently-red Tier A gate
    -- for every future checkpoint.
    'get_self_employee',
    -- HRT-287 (Prompt 287, Customer-to-Tenant Ticket, CG-S12-HRT-015): this
    -- migration is the first to use app.actor_holds_customer_user_layer as a
    -- POSITIVE gate (app.list_customer_ticket_categories/app.list_my_tickets
    -- return rows only if it is TRUE, the mirror image of its established
    -- negative-exclusion use in RLS -- "not actor_holds_customer_user_layer").
    -- It genuinely IS a real, narrow authority/context primitive (an active
    -- customer_user-layer app.principal_memberships row check, the same
    -- conceptual class as is_supreme_admin/actor_can_view_owner_scoped_row,
    -- both already base keywords below) -- so the base regex keyword list is
    -- widened here to include it, rather than special-casing each caller by
    -- name, matching the sweep's own established evolution (ATW-023's own
    -- resolve_customer_owner_account_scope/customer_warehouse_eligibility_
    -- active/actor_can_view_owner_scoped_row were added the same way). This
    -- credits app.list_customer_ticket_categories and app.list_my_tickets
    -- (which now also calls it, HRT-287) transitively via the closure query
    -- below -- neither needs its own v_expected entry.
    --
    -- HRT-288 (Prompt 288, Tenant-to-CargoGrid Helpdesk, CG-S12-HRT-016):
    -- identically widens the base regex again for
    -- app._is_tenant_helpdesk_authorized -- a real, narrow tenant-authority
    -- primitive (a direct app.principal_memberships/app.role_assignments
    -- query, deliberately NOT app.evaluate_permission/app.
    -- check_ticket_authority, see that function's own header) used as a
    -- POSITIVE gate by app.create_helpdesk_ticket, app.
    -- list_helpdesk_ticket_categories, and app.list_tenant_helpdesk_tickets
    -- -- all three credited transitively via the closure query below, no
    -- separate v_expected entry needed for any of them.
    --
    -- app.is_ticket_queue_member (HRT-286, pre-existing -- this sweep never
    -- actually reached the ticketing schema before HRT-287's own session,
    -- since every prior db:test full-harness run aborted earlier at
    -- ISS-2026-059's time-of-day-dependent procurement failure) is a
    -- DIFFERENT, genuinely correct-by-design shape: its own WHERE clause
    -- (`u.auth_user_id = p_auth_user_id`) can only ever answer "is THIS
    -- caller-supplied identity an active member of this queue" -- a raw
    -- self/other-scope equality predicate, the identical false-positive
    -- shape app.get_self_employee/app.acknowledge_performance_outcome above
    -- already document and are exempted for. Independently verified low-risk
    -- even though p_auth_user_id is a plain parameter (not auth.uid()-only):
    -- the boolean it discloses ("is employee X on queue Y") is already
    -- broadly readable by any tenant employee via the catalog-visible
    -- app.list_ticket_queue_members RPC (ticket_queue_members_select_scoped
    -- RLS), so this function discloses nothing a legitimate tenant member
    -- could not already see through the already-granted list RPC. Genuinely
    -- correct-by-design, not a live gap -- added here per this test's own
    -- documented escape hatch.
    'is_ticket_queue_member',
    -- HRT-283 (Prompt 283, KPI and Performance) batch-283-285 Tier C review:
    -- app.acknowledge_performance_outcome, app.submit_performance_appeal, and
    -- app.submit_performance_self_assessment each take
    -- p_actor_auth_user_id, call app.assert_actor_is_session_identity first
    -- (ATW-031), and then enforce a genuine, direct self-scope EQUALITY
    -- check against the resolved caller''s own employee row before any
    -- disclosure or mutation --
    -- `v_self.master_record_id <> v_outcome.employee_id` (raises
    -- insufficient_authority) for the first two, and an equivalent
    -- `where ... employee_id = v_self.master_record_id` predicate on the
    -- self-assessment row lookup for the third -- independently read and
    -- reproduced live against each function''s own pg_get_functiondef
    -- during the batch 283-285 Tier C review, not merely cited. This
    -- sweep''s own `base` keyword list (evaluate_permission,
    -- check_*_authority, is_supreme_admin, etc.) does not credit a raw
    -- equality-based self-scope predicate as an authority check -- the
    -- identical class of false positive `get_self_employee` above already
    -- documents. Genuinely correct-by-design (independently re-verified,
    -- not accepted from either function''s own build log), not a live
    -- authority gap -- added here per this test''s own documented escape
    -- hatch rather than left as a permanently-red Tier A gate.
    'acknowledge_performance_outcome', 'submit_performance_appeal', 'submit_performance_self_assessment',
    -- HRT-288 (Prompt 288, Tenant-to-CargoGrid Helpdesk, CG-S12-HRT-016):
    -- app.ticket_channel_of takes ONLY p_ticket_id (no actor parameter at
    -- all) and returns a single ticket's channel value -- it exists purely
    -- so the ticket_messages/ticket_watchers/ticket_events SELECT policies
    -- (which have no channel column of their own) can apply the same
    -- helpdesk-channel exclusion app.tickets' own policy applies directly.
    -- It is called from RLS policy expressions, which are evaluated as the
    -- QUERYING role, so it must stay executable by authenticated -- the
    -- identical "RLS-support primitive, not itself an authority check"
    -- shape every base keyword above already covers structurally, but its
    -- own body carries none of those keywords (a bare one-column select).
    -- What it discloses to a direct, ungated call (an arbitrary ticket
    -- id's channel -- one of 3 fixed values, no tenant/business content) is
    -- lower-sensitivity than app.is_ticket_queue_member's own already-
    -- accepted disclosure (a real membership boolean) -- genuinely
    -- correct-by-design, not a live gap.
    'ticket_channel_of',
    -- CPL-300 (Prompt 300, Customer User Scope, CG-S13-CPL-002): app.
    -- resolve_customer_account_scope and app.actor_is_active_customer_
    -- portal_account_admin are genuinely new authority/scope PRIMITIVES (the
    -- same class as resolve_customer_owner_account_scope/actor_holds_
    -- customer_user_layer already above) -- they ARE the check, so they
    -- cannot check themselves, and the base regex keyword list is widened
    -- (rather than special-cased per caller) to credit every caller
    -- transitively, matching resolve_customer_owner_account_scope's own
    -- original addition and HRT-287/288's own actor_holds_customer_user_
    -- layer/_is_tenant_helpdesk_authorized precedent exactly. This credits
    -- app.get_customer_portal_scope_context, app.invite_customer_portal_
    -- user, app.set_customer_portal_account_membership_status, and app.
    -- list_customer_portal_account_memberships transitively via the closure
    -- query below -- no separate v_expected entry needed for any of them.
    'resolve_customer_account_scope', 'actor_is_active_customer_portal_account_admin',
    -- app.accept_customer_portal_invite's own authority shape is a raw
    -- self-row-identity equality check ("only the invited identity may
    -- accept their own invite", v_membership.auth_user_id <>
    -- p_auth_user_id) -- the identical false-positive class app.get_self_
    -- employee/app.is_ticket_queue_member above already document and are
    -- exempted for (a caller-supplied identity can only ever be compared
    -- against the ONE row it names, never used to reach a third party's
    -- data). Genuinely correct-by-design, not a live gap -- added here per
    -- this test's own documented escape hatch.
    'accept_customer_portal_invite'
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

  -- 2b. Tier C security-rls/correctness-spec review fix (CPL-300, Prompt 300, Finding 1,
  --     CRITICAL): every one of this migration's 8 SECURITY DEFINER functions granted to
  --     authenticated must itself call app.assert_actor_is_session_identity -- not merely be
  --     covered transitively via the base-regex closure below (section 3), which exempts
  --     STABLE/pure-read functions from the separate side-effecting-only actor-authority sweep
  --     further down this file (`f.provolatile = 'v'`). These four reads (resolve_customer_
  --     account_scope, actor_is_active_customer_portal_account_admin, get_customer_portal_
  --     scope_context, list_customer_portal_account_memberships) are exactly the shape that
  --     blanket "reads are exempt" reasoning does not cover: the identity parameter IS the
  --     scoping mechanism, not a value re-derived from an already-scoped row, so forging it is
  --     the entire attack, not a no-op -- live-verified IDOR, both lenses independently
  --     reproduced. A static, narrow, named-list check (this repository's own established
  --     pattern, section 2 above) rather than widening the STABLE-inclusive general sweep,
  --     which would also flag the pre-existing, out-of-this-checkpoint's-scope ATW-023/ATW-242
  --     functions (app.resolve_customer_owner_account_scope, app.evaluate_customer_inventory_
  --     access, etc.) this migration mirrors but does not own.
  foreach v_fn in array array['resolve_customer_account_scope', 'actor_is_active_customer_portal_account_admin',
                              'get_customer_portal_scope_context', 'invite_customer_portal_user',
                              'accept_customer_portal_invite', 'set_customer_portal_account_membership_status',
                              'list_customer_portal_account_memberships', 'grant_initial_customer_portal_account_admin'] loop
    if not exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'app' and p.proname = v_fn
        and p.prosrc like '%assert_actor_is_session_identity%'
    ) then
      raise exception 'assertion failed: app.% must call app.assert_actor_is_session_identity -- it is granted to authenticated and takes an identity/actor parameter as the sole scoping mechanism (CPL-300 Tier C review fix, Finding 1)', v_fn;
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
    where prosrc ~ 'evaluate_permission|can_access_record|is_supreme_admin|has_active_membership|check_[a-z_]*authority|is_eligible_[a-z_]*approver|resolve_customer_owner_account_scope|customer_warehouse_eligibility_active|actor_can_view_owner_scoped_row|authorize_file_access|assert_session_identity_in_tenant|actor_holds_customer_user_layer|_is_tenant_helpdesk_authorized|resolve_customer_account_scope|actor_is_active_customer_portal_account_admin'
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

\echo '>> ATW-032 (ISS-2026-032): an authority check is not an identity check. A function that gates on app.evaluate_permission(p_actor_auth_user_id, ...) is covered by ATW-031, which wired app.assert_actor_is_session_identity into that one choke point. A function that instead asks its own question -- is_support_grant_authority(p_actor_auth_user_id, ...), recipient_auth_user_id <> p_actor_auth_user_id -- validates the CLAIMED actor and never the caller, so any authenticated session could pass a colleague UUID and act as them. Every side-effecting, client-callable function taking p_actor_auth_user_id must therefore reach one of the two checks.'
do $$
declare
  v_unguarded text[];
begin
  -- The same transitive closure the ATW-032 classification pass used: start at the two
  -- actor-check primitives and walk callers, so a function that delegates its authority
  -- decision to a checked helper counts as covered rather than being flagged.
  with recursive fn as (
    select p.oid, p.proname, pg_get_functiondef(p.oid) as def, p.provolatile,
           has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth_exec,
           pg_get_function_identity_arguments(p.oid) as args
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.prokind = 'f'
  ),
  edge as (
    select c.proname as caller, e.proname as callee
    from fn c join fn e on c.oid <> e.oid
    where c.def ~ ('\mapp\.' || e.proname || '\s*\(')
  ),
  covered(proname) as (
    select proname from fn where proname in ('evaluate_permission', 'assert_actor_is_session_identity')
    union
    select e.caller from edge e join covered on e.callee = covered.proname
  )
  select array_agg(f.proname order by f.proname) into v_unguarded
  from fn f
  where f.args ~ 'p_actor_auth_user_id'   -- claims to act as somebody
    and f.auth_exec                       -- and a logged-in session can call it
    and f.provolatile = 'v'               -- and it has a side effect (pure reads are exempt)
    and f.proname not in (select proname from covered);

  if v_unguarded is not null then
    raise exception 'assertion failed: % side-effecting function(s) are granted to authenticated and take p_actor_auth_user_id but reach neither app.evaluate_permission nor app.assert_actor_is_session_identity, so any authenticated session may pass another identity UUID and act as them: %', array_length(v_unguarded, 1), v_unguarded;
  end if;

  raise notice 'ATW-032 actor-authority proof: no side-effecting client-callable function accepts a p_actor_auth_user_id it never proves belongs to the caller';
end;
$$;

\echo '>> ATW-032 (ISS-2026-010): a customer_user-layer principal must fail CLOSED by default. app.invite_user writes a tenant_user_identities row and app.has_active_tenant_membership reads exactly that table, so a portal principal satisfies plain tenant membership -- any SELECT policy whose ENTIRE test is that membership admits it. Which records the portal may read is Phase 8 scope; that the default is deny is not, and this gate holds the default.'
do $$
declare
  v_open text[];
begin
  select array_agg(c.relname || '.' || pol.polname order by c.relname, pol.polname) into v_open
  from pg_policy pol
  join pg_class c on c.oid = pol.polrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'app' and pol.polcmd = 'r'
    and pg_get_expr(pol.polqual, pol.polrelid) ~* 'has_active_tenant_membership'
    -- Excluded, and each exclusion is deliberate: a policy carrying an owner-scope branch, a
    -- warehouse-eligibility gate, app.can_access_record, or an org-unit/branch predicate either
    -- IS a designed customer-visible path or already fails closed on a customer_user's own NULL
    -- org_unit_id. Only policies where tenant membership is the whole test are in scope here.
    and pg_get_expr(pol.polqual, pol.polrelid) !~* 'customer_user_layer|owner_account|customer_account|can_access_record|warehouse|org_unit|branch';

  if v_open is not null then
    raise exception 'assertion failed: % SELECT policy/policies test tenant membership and nothing else, so a customer_user-layer principal reads them through a raw client with no portal code involved. Narrow each with app.actor_holds_customer_user_layer beside its own membership call: %', array_length(v_open, 1), v_open;
  end if;

  raise notice 'ATW-032 portal default-deny proof: no SELECT policy admits a customer_user-layer principal on tenant membership alone';
end;
$$;

\echo '>> HRT-295 / ISS-2026-072 fix (the role_assignments half, previously OPEN, High -- docs/runtime/KNOWN_ISSUES.md): app.transition_user_status'' own suspend/revoke branch now strips every ACTIVE app.role_assignments row for the target identity in this tenant, centrally, for EVERY caller -- not merely the one call site (app.request_onboarding_access_revocation) that used to duplicate this inline. Re-grant afterward is always a separate, explicit, governed act -- never an automatic side effect of a later suspended -> active status flip.'
do $$
declare
  v_tenant_id uuid;
  v_grantee_id uuid;
  v_decision app.rbac_decision;
  v_active_count integer;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmerbac');
  v_grantee_id := (select id from app.users where email = 'grantee@example.test');

  -- Baseline: grantee still holds the active FIN:Approve role_assignment from this
  -- file's own setup block, unaffected by every test above.
  v_decision := app.evaluate_permission('00000000-0000-0000-0000-000000000401', v_tenant_id, 'FIN', 'Approve');
  if not v_decision.allowed then
    raise exception 'assertion failed: expected grantee to still hold FIN:Approve before this block''s own suspend call, got allowed=%', v_decision.allowed;
  end if;

  perform app.transition_user_status(v_grantee_id, 'suspended', 'HRT-295 role_assignments cascade regression', 'tester');

  select count(*) into v_active_count from app.role_assignments
  where tenant_id = v_tenant_id and auth_user_id = '00000000-0000-0000-0000-000000000401' and status = 'active';
  if v_active_count <> 0 then
    raise exception 'assertion failed: expected zero active role_assignments after suspend, found %', v_active_count;
  end if;

  v_decision := app.evaluate_permission('00000000-0000-0000-0000-000000000401', v_tenant_id, 'FIN', 'Approve');
  if v_decision.allowed then
    raise exception 'assertion failed: expected FIN:Approve to be denied for a suspended identity once its role_assignments are revoked, got allowed=true';
  end if;

  -- Reactivating the Platform user (suspended -> active, a pre-existing, unblocked
  -- transition) does NOT auto-restore the stripped role_assignment.
  perform app.transition_user_status(v_grantee_id, 'active', 'back on duty', 'tester');

  v_decision := app.evaluate_permission('00000000-0000-0000-0000-000000000401', v_tenant_id, 'FIN', 'Approve');
  if v_decision.allowed then
    raise exception 'assertion failed: expected FIN:Approve to remain denied after reactivation -- role_assignments are never auto-restored by a status flip';
  end if;

  -- A real, separate, explicit re-grant restores it -- proving the intended
  -- division of responsibility, not merely that revoke works.
  perform app.assign_role(
    v_tenant_id,
    (select rv.id from app.role_versions rv join app.roles r on r.id = rv.role_id where r.tenant_id = v_tenant_id and r.name = 'RBAC Finance Approver' and rv.status = 'published'),
    '00000000-0000-0000-0000-000000000401',
    '00000000-0000-0000-0000-000000000401',
    'tester'
  );
  v_decision := app.evaluate_permission('00000000-0000-0000-0000-000000000401', v_tenant_id, 'FIN', 'Approve');
  if not v_decision.allowed then
    raise exception 'assertion failed: expected FIN:Approve restored after an explicit, separate app.assign_role re-grant';
  end if;

  raise notice 'HRT-295 role_assignments cascade proof: suspend strips active grants system-wide, reactivation alone never restores them, an explicit re-grant does';
end;
$$;

\echo 'ALL PLT-112 db-test assertions passed.'
