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
    -- app.get_self_employee's own exemption reason CORRECTED at HDN-372 (Step 15,
    -- Prompt 372, Tenant Isolation Audit) -- this sweep's own closure genuinely requires
    -- it to stay named here, since it has no AUTHORITY check (evaluate_permission/
    -- can_access_record/etc.) and structurally needs none: once identity is proven, the
    -- query is inherently self-scoped (`u.auth_user_id = p_actor_auth_user_id`) and can
    -- only ever return the CALLING actor's own linked employee row. What was WRONG in
    -- the original reasoning is the IDENTITY half: it claimed "every one of its own call
    -- sites additionally calls app.assert_actor_is_session_identity before invoking it"
    -- as the reason the gap was safe -- true for its intended callers, but it is
    -- SECURITY DEFINER and granted EXECUTE directly to authenticated, so any session
    -- could call it standalone, bypassing whatever a caller-side wrapper does. HDN-372
    -- live-forced exactly this and confirmed a real cross-tenant PII read
    -- (docs/build-log/full-system-hardening/HDN-372.md). Fixed at the root: the assert
    -- now lives inside app.get_self_employee itself
    -- (20260810000000_harden_tenant_isolation_actor_identity_gaps.sql) rather than being
    -- assumed from caller convention -- verified by the separate, dedicated HDN-372
    -- regression check further down this file, which this authority-surface sweep does
    -- not replace (identity and authority remain two different checks in this codebase's
    -- own vocabulary, and this function only ever needed the former).
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
    'accept_customer_portal_invite',
    -- IAE-026 (Prompt 354, Enterprise IAM SSO/SAML/SCIM): app.resolve_
    -- enterprise_idp_by_email_domain is deliberately anon-facing by design --
    -- the identical class app.resolve_tenant_by_domain above already
    -- documents (a safe public resolver returning only connection_id/
    -- protocol/display_name for an ACTIVE domain claim + ACTIVE connection,
    -- never a config/credential/authorization decision). Genuinely
    -- correct-by-design, not a live gap.
    'resolve_enterprise_idp_by_email_domain',
    -- IAE-027 (Prompt 355, Enterprise MFA and Session Controls): app.verify_
    -- mfa_step_up_challenge (`where id = p_challenge_id and auth_user_id =
    -- p_actor_auth_user_id`), app.consume_mfa_exception (`where id =
    -- p_exception_id and target_auth_user_id = p_actor_auth_user_id`), and
    -- app.assert_current_step_up_authorization (its own step-up-verified
    -- lookup is scoped `where auth_user_id = p_actor_auth_user_id`) are each
    -- the identical raw self-row-identity equality shape app.get_self_
    -- employee/app.is_ticket_queue_member/app.accept_customer_portal_invite
    -- above already document and are exempted for -- a caller-supplied
    -- identity can only ever act on or read the ONE row/challenge/exception
    -- that names it, never reach another identity's own. Genuinely
    -- correct-by-design, not a live gap.
    'verify_mfa_step_up_challenge', 'consume_mfa_exception', 'assert_current_step_up_authorization',
    -- HDN-373 Tier C completeness fix (Step 15, Prompt 373): converting these two to
    -- SECURITY DEFINER (part of closing the wider Finance/Config authority-chain
    -- reachability gap, HDN-BLK-015) newly surfaced them to this sweep. Both are
    -- genuinely correct-by-design, not a live gap: app.list_n8n_action_allowlist takes
    -- no arguments and reads app.n8n_action_allowlist, a platform-wide reference
    -- catalog with no tenant_id column at all (grep-confirmed) -- there is no tenant
    -- data to scope. app.validate_automation_rule_definition takes no id/tenant
    -- parameter either (only p_trigger_event_type/p_conditions/p_actions) and performs
    -- pure structural JSON validation plus one existence check against app.
    -- notification_types (itself a shared, non-tenant-scoped catalog) -- it reads no
    -- tenant-scoped row and returns only a boolean, so a forged or absent actor changes
    -- nothing a caller could not already determine from the input they themselves
    -- supplied. Two sibling functions surfaced by the same conversion,
    -- app.preview_finance_config_impact and app.validate_custom_field_values, were
    -- NOT added here -- both genuinely lacked a tenant check (a real cross-tenant
    -- config-disclosure gap) and were fixed with an app.has_active_tenant_membership
    -- check instead of being exempted; see 20260810900000_harden_finance_authority_
    -- chain_tierc_completeness.sql's own header.
    'list_n8n_action_allowlist', 'validate_automation_rule_definition'
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
    -- ISS-2026-145 (HDN-379): rewritten from an O(n^2) fn x fn self-join (one regex
    -- match per PAIR, ~2,700^2 pairs at current scale, 15-20+ minutes) to an O(n) pass
    -- extracting every app.<name>( call from each function's own definition once, then
    -- joining on proname -- mirrors the identical technique already used unmodified in
    -- this same file's own ATW-032/ISS-2026-033 sibling block above (the `edge as
    -- (select f.proname caller, m[1] callee from fn f, regexp_matches(f.prosrc, ...)`
    -- shape). Only edge construction changes; the covered/closure recursive walk below
    -- is untouched, so multi-hop transitive coverage (a function that calls a helper
    -- that calls another helper that finally reaches evaluate_permission) is preserved
    -- exactly. Verified via a same-schema matched-pair run (original vs rewrite, one
    -- disposable database, no rebuild in between) that both produce an identical
    -- verdict before this migration landed -- see HDN-379.md.
    --
    -- HDN-379 Tier C fix: the first draft's regex dropped two structural properties
    -- the original self-join carried for free -- a leading `\m` word-boundary anchor
    -- (so `webapp.foo(` cannot be mistaken for a call to app.foo), and a real
    -- join-against-fn requirement (so `insert into app.some_table (...)` cannot be
    -- mistaken for a call to a function named after the table). Live-forced: on the
    -- current 2,700-function schema this never produced a wrong verdict (876 spurious
    -- edges, all traced to unindexed table names with zero overlap against any real
    -- function name), but a future function literally named after an existing table,
    -- or a call site shaped like `wordapp.<realname>(`, could silently mark a caller
    -- "covered" with no test failure -- restored both properties here, at the same
    -- O(n) cost (the `in (select proname from fn)` filter is a hash semi-join against
    -- the same already-materialized `fn` CTE, not a new cross join).
    select f.proname as caller, m[1] as callee
    from fn f, regexp_matches(f.def, '\mapp\.([a-z0-9_]+)\s*\(', 'g') m
    where m[1] <> f.proname
      and m[1] in (select proname from fn)
  ),
  covered(proname) as (
    select proname from fn where proname in ('evaluate_permission', 'assert_actor_is_session_identity')
    union
    select e.caller from edge e join covered on e.callee = covered.proname
  )
  select array_agg(f.proname order by f.proname) into v_unguarded
  from fn f
  where f.args ~ 'p_(actor|requester)_auth_user_id'   -- claims to act as somebody --
                                                       -- HDN-372: broadened from
                                                       -- 'p_actor_auth_user_id' alone,
                                                       -- which is exactly the gap that
                                                       -- let app.query_audit_logs/
                                                       -- app.export_audit_logs (named
                                                       -- p_requester_auth_user_id) go
                                                       -- unswept and unfixed until HDN-372
    and f.auth_exec                       -- and a logged-in session can call it
    and f.provolatile = 'v'               -- and it has a side effect (pure reads are exempt)
    and f.proname not in (select proname from covered);

  if v_unguarded is not null then
    raise exception 'assertion failed: % side-effecting function(s) are granted to authenticated and take p_actor_auth_user_id but reach neither app.evaluate_permission nor app.assert_actor_is_session_identity, so any authenticated session may pass another identity UUID and act as them: %', array_length(v_unguarded, 1), v_unguarded;
  end if;

  raise notice 'ATW-032 actor-authority proof: no side-effecting client-callable function accepts a p_actor_auth_user_id it never proves belongs to the caller';
end;
$$;

\echo '>> HDN-372 (Step 15, Prompt 372, Tenant Isolation Audit, ISS-2026-164): the ATW-032 sweep above deliberately exempts `provolatile = ''v''` reads on the premise "a forged actor changes nothing a caller could not already read." That premise is false for a SECURITY DEFINER reader -- it bypasses RLS, so a forged actor is exactly what lets a caller read what they could not otherwise. 13 such functions (9 found and fixed first, 4 more found by this same checkpoint''s own Tier C review and fixed in a second migration) were live-forced and confirmed exploitable (full disposition docs/build-log/full-system-hardening/HDN-372.md) and fixed at 20260810000000_harden_tenant_isolation_actor_identity_gaps.sql / 20260810100000_harden_tenant_isolation_actor_identity_gaps_round2.sql. This is a narrow, named-list regression proof for exactly those 13 -- not a widening of the general sweep above, which would also flag the functions HDN-372 explicitly deferred to HDN-373 (ISS-2026-165, ISS-2026-179) rather than silently reopening Tier A for work that lane, not this gate, owns. Position-aware: the assert must be the function''s first executable statement (optionally after leading comment lines), not merely present anywhere in the body -- a bare substring match would still pass if the call were commented out or moved after a data read.'
do $$
declare
  v_fn text;
  v_missing text[];
begin
  foreach v_fn in array array['get_self_employee', 'resolve_customer_owner_account_scope',
                              'query_audit_logs', 'export_audit_logs',
                              'list_notifications_for_recipient', 'count_unread_notifications',
                              'get_workflow_instance_history', 'get_approval_request_history',
                              'get_shipment_status_history', 'get_notification_preferences',
                              'get_custom_field_values', 'list_pending_approval_steps_for_actor',
                              'resolve_actor_owner_account_scope'] loop
    if not exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'app' and p.proname = v_fn
        and pg_get_functiondef(p.oid) ~ 'begin\s*(--[^\n]*\n\s*)*perform\s+app\.assert_actor_is_session_identity\('
    ) then
      v_missing := array_append(v_missing, v_fn);
    end if;
  end loop;

  if v_missing is not null then
    raise exception 'assertion failed: % of the 13 functions HDN-372 fixed no longer call app.assert_actor_is_session_identity as their first statement -- the tenant-isolation regression this gate exists to prevent: %', array_length(v_missing, 1), v_missing;
  end if;

  raise notice 'HDN-372 actor-identity regression proof: all 13 fixed functions still call app.assert_actor_is_session_identity as their first statement';
end;
$$;

\echo '>> HDN-372 (ISS-2026-164): live two-session forced-spoof regression. A genuine authenticated session -- claimed via request.jwt.claims, not a role switch, since assert_actor_is_session_identity compares auth.uid() (GUC-derived) to the claimed actor regardless of calling role, exactly as the pre-existing ATW-031 proof above already establishes for this file -- must be refused by a representative sample of the 13 fixed functions when it claims to act as a different identity: the same live attack this checkpoint used to find and re-verify the defect, now committed as regression evidence rather than only pasted console output in the build log.'
do $$
declare
  v_self uuid := '00000000-0000-0000-0000-000000000401';
  v_victim uuid := '00000000-0000-0000-0000-000000000402';
  v_fake_tenant uuid := gen_random_uuid();
  v_raised boolean;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', v_self::text, 'role', 'authenticated')::text, true);

  -- app.get_self_employee: original 9, "add the assert" shape, LANGUAGE sql -> plpgsql.
  v_raised := false;
  begin
    perform app.get_self_employee(v_fake_tenant, v_victim);
  exception
    when insufficient_privilege then
      if sqlerrm !~ 'actor_identity_mismatch' then raise; end if;
      v_raised := true;
  end;
  if not v_raised then
    raise exception 'assertion failed: app.get_self_employee did not reject a forged actor from a genuine authenticated session -- HDN-372/ISS-2026-164 has regressed';
  end if;

  -- app.resolve_customer_owner_account_scope: root of the 10-function ATW-023 family.
  v_raised := false;
  begin
    perform app.resolve_customer_owner_account_scope(v_victim, v_fake_tenant);
  exception
    when insufficient_privilege then
      if sqlerrm !~ 'actor_identity_mismatch' then raise; end if;
      v_raised := true;
  end;
  if not v_raised then
    raise exception 'assertion failed: app.resolve_customer_owner_account_scope did not reject a forged actor -- HDN-372/ISS-2026-164 has regressed, and the whole ATW-023 family is exposed again';
  end if;

  -- app.query_audit_logs: the p_requester_auth_user_id-named shape ATW-032's own
  -- candidate regex missed until HDN-372 broadened it, above in this same file.
  v_raised := false;
  begin
    perform app.query_audit_logs(v_victim, v_fake_tenant);
  exception
    when insufficient_privilege then
      if sqlerrm !~ 'actor_identity_mismatch' then raise; end if;
      v_raised := true;
  end;
  if not v_raised then
    raise exception 'assertion failed: app.query_audit_logs did not reject a forged actor -- HDN-372/ISS-2026-164 has regressed';
  end if;

  -- app.get_notification_preferences: round-2 sibling of app.list_notifications_for_
  -- recipient/app.count_unread_notifications, found by this checkpoint's own Tier C
  -- review after the first migration had already landed.
  v_raised := false;
  begin
    perform app.get_notification_preferences(v_fake_tenant, v_victim, v_victim);
  exception
    when insufficient_privilege then
      if sqlerrm !~ 'actor_identity_mismatch' then raise; end if;
      v_raised := true;
  end;
  if not v_raised then
    raise exception 'assertion failed: app.get_notification_preferences did not reject a forged actor -- HDN-372 round 2 has regressed';
  end if;

  -- The same session acting as ITSELF must not be blanket-denied -- v_self holds no
  -- real tenant membership, so this must fail on a DIFFERENT, later check (or return
  -- empty), never actor_identity_mismatch, proving the fix is not a blanket deny.
  begin
    perform app.resolve_customer_owner_account_scope(v_self, v_fake_tenant);
  exception
    when insufficient_privilege then
      if sqlerrm ~ 'actor_identity_mismatch' then
        raise exception 'assertion failed: app.resolve_customer_owner_account_scope rejected the caller acting as themselves -- the fix has become a blanket deny, not an identity check';
      end if;
    when others then
      null; -- any non-identity failure past the assert is fine and expected here
  end;

  perform set_config('request.jwt.claims', '', true);
  raise notice 'HDN-372 live two-session forced-spoof proof: app.get_self_employee, app.resolve_customer_owner_account_scope, app.query_audit_logs and app.get_notification_preferences all reject a forged actor from a genuine authenticated (non-superuser-identity) session; an own-identity call is not blanket-denied';
end;
$$;

\echo '>> HDN-373 (Step 15, Prompt 373, RLS and RBAC Audit, ISS-2026-165): closes HDN-BLK-012, carried forward from HDN-372''s own Tier C review -- 13 dashboard functions (app.get_ops_dashboard_* x6, app.get_dashboard_* x7) shared HDN-BLK-011''s exact actor-forgery shape with no common root to fix once, so each is fixed individually at 20260810200000_harden_dashboard_actor_identity_gaps.sql. Position-aware, mirroring the HDN-372 check above: the assert must be the function''s first executable statement.'
do $$
declare
  v_fn text;
  v_missing text[];
begin
  foreach v_fn in array array['get_ops_dashboard_shipment_status', 'get_ops_dashboard_milestone_sla',
                              'get_ops_dashboard_exception_queue', 'get_ops_dashboard_epod_completion',
                              'get_ops_dashboard_cost_variance', 'get_ops_dashboard_billing_readiness',
                              'get_dashboard_lead_aging', 'get_dashboard_activity_queue',
                              'get_dashboard_pipeline_summary', 'get_dashboard_quote_sla',
                              'get_dashboard_margin_summary', 'get_dashboard_win_loss_summary',
                              'get_dashboard_forecast_summary'] loop
    if not exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'app' and p.proname = v_fn
        and pg_get_functiondef(p.oid) ~ 'begin\s*(--[^\n]*\n\s*)*perform\s+app\.assert_actor_is_session_identity\('
    ) then
      v_missing := array_append(v_missing, v_fn);
    end if;
  end loop;

  if v_missing is not null then
    raise exception 'assertion failed: % of the 13 dashboard functions HDN-373 fixed no longer call app.assert_actor_is_session_identity as their first statement -- HDN-BLK-012 has regressed: %', array_length(v_missing, 1), v_missing;
  end if;

  raise notice 'HDN-373 dashboard actor-identity regression proof: all 13 fixed functions still call app.assert_actor_is_session_identity as their first statement';
end;
$$;

\echo '>> HDN-373 (ISS-2026-165): live two-session forced-spoof regression for a representative sample of the 13 dashboard functions, same methodology as the HDN-372 proof above.'
do $$
declare
  v_self uuid := '00000000-0000-0000-0000-000000000401';
  v_victim uuid := '00000000-0000-0000-0000-000000000402';
  v_fake_tenant uuid := gen_random_uuid();
  v_raised boolean;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', v_self::text, 'role', 'authenticated')::text, true);

  v_raised := false;
  begin
    perform * from app.get_ops_dashboard_shipment_status(v_fake_tenant, null, null, v_victim);
  exception
    when insufficient_privilege then
      if sqlerrm !~ 'actor_identity_mismatch' then raise; end if;
      v_raised := true;
  end;
  if not v_raised then
    raise exception 'assertion failed: app.get_ops_dashboard_shipment_status did not reject a forged actor -- HDN-373/HDN-BLK-012 has regressed';
  end if;

  v_raised := false;
  begin
    perform * from app.get_dashboard_pipeline_summary(v_fake_tenant, null, null, v_victim);
  exception
    when insufficient_privilege then
      if sqlerrm !~ 'actor_identity_mismatch' then raise; end if;
      v_raised := true;
  end;
  if not v_raised then
    raise exception 'assertion failed: app.get_dashboard_pipeline_summary did not reject a forged actor -- HDN-373/HDN-BLK-012 has regressed';
  end if;

  v_raised := false;
  begin
    perform * from app.get_dashboard_margin_summary(v_fake_tenant, null, null, null, null, v_victim);
  exception
    when insufficient_privilege then
      if sqlerrm !~ 'actor_identity_mismatch' then raise; end if;
      v_raised := true;
  end;
  if not v_raised then
    raise exception 'assertion failed: app.get_dashboard_margin_summary did not reject a forged actor -- HDN-373/HDN-BLK-012 has regressed (this one also gates a field-masking entitlement bypass, not merely a scope widening)';
  end if;

  perform set_config('request.jwt.claims', '', true);
  raise notice 'HDN-373 live two-session forced-spoof proof: app.get_ops_dashboard_shipment_status, app.get_dashboard_pipeline_summary and app.get_dashboard_margin_summary all reject a forged actor from a genuine authenticated session';
end;
$$;

\echo '>> Track B Batch 6 (ISS-2026-186 partial fix, 20260828121000): position-aware wiring check for the 3 shared record-scope primitives re-derived as genuinely self-referential-only (zero third-party call sites anywhere in supabase/migrations/) and fixed with the identical HDN-372/373 assert-first pattern. LANGUAGE sql functions have no BEGIN block, so the assert is the first SELECT statement in the body, not "begin ... perform" -- mirrors app.current_support_session''s own already-shipped convention.'
do $$
declare
  v_fn text;
  v_missing text[];
begin
  -- app.claim_case_record_scope_ok / app.wms_pick_record_scope_ok: LANGUAGE sql, the
  -- assert is the body's first statement (a bare `select`, not `begin ... perform`).
  -- pg_get_functiondef() re-renders the dollar-quote tag as "function", never
  -- preserving the source's own two-dollar-sign tag -- confirmed directly (a
  -- throwaway LANGUAGE sql function created and inspected via
  -- pg_get_functiondef renders "AS dollar-function-dollar", not the original
  -- two-dollar-sign tag) -- so the tag itself must be matched generically,
  -- not hardcoded to a bare two-dollar-sign pattern (which never matches and
  -- made this check unconditionally fail as a false positive, not a real
  -- regression). NOTE: this comment deliberately avoids writing the literal
  -- two-character dollar-quote sequence itself -- inside a do-block already
  -- opened with that same sequence, Postgres' lexer treats ANY occurrence of
  -- it (even inside a -- comment) as the block's own closing delimiter, which
  -- is exactly the self-inflicted syntax error a first version of this note
  -- caused and this rewrite fixes.
  foreach v_fn in array array['claim_case_record_scope_ok', 'wms_pick_record_scope_ok'] loop
    if not exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'app' and p.proname = v_fn
        and pg_get_functiondef(p.oid) ~ '\$[A-Za-z_]*\$\s*(--[^\n]*\n\s*)*select\s+app\.assert_actor_is_session_identity\('
    ) then
      v_missing := array_append(v_missing, v_fn);
    end if;
  end loop;

  -- app.label_subject_record_scope_ok: LANGUAGE plpgsql, the standard
  -- "begin ... perform app.assert_actor_is_session_identity(...)" shape.
  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'label_subject_record_scope_ok'
      and pg_get_functiondef(p.oid) ~ 'begin\s*(--[^\n]*\n\s*)*perform\s+app\.assert_actor_is_session_identity\('
  ) then
    v_missing := array_append(v_missing, 'label_subject_record_scope_ok');
  end if;

  if v_missing is not null then
    raise exception 'assertion failed: % of the 3 shared record-scope primitives Track B Batch 6 fixed no longer call app.assert_actor_is_session_identity as their first statement -- ISS-2026-186''s partial fix has regressed: %', array_length(v_missing, 1), v_missing;
  end if;

  raise notice 'Track B Batch 6 record-scope-primitive actor-identity regression proof: all 3 fixed functions still call app.assert_actor_is_session_identity as their first statement';
end;
$$;

\echo '>> Track B Batch 6 (ISS-2026-186 partial fix): live two-session forced-spoof regression for the same 3 functions, identical methodology to the HDN-372/373 proofs above.'
do $$
declare
  v_self uuid := '00000000-0000-0000-0000-000000000401';
  v_victim uuid := '00000000-0000-0000-0000-000000000402';
  v_fake_tenant uuid := gen_random_uuid();
  v_fake_id uuid := gen_random_uuid();
  v_raised boolean;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', v_self::text, 'role', 'authenticated')::text, true);

  v_raised := false;
  begin
    perform app.claim_case_record_scope_ok(v_victim, v_fake_tenant, v_fake_id);
  exception
    when insufficient_privilege then
      if sqlerrm !~ 'actor_identity_mismatch' then raise; end if;
      v_raised := true;
  end;
  if not v_raised then
    raise exception 'assertion failed: app.claim_case_record_scope_ok did not reject a forged actor from a genuine authenticated session -- ISS-2026-186''s partial fix has regressed';
  end if;

  v_raised := false;
  begin
    perform app.wms_pick_record_scope_ok(v_victim, v_fake_id, 'irrelevant');
  exception
    when insufficient_privilege then
      if sqlerrm !~ 'actor_identity_mismatch' then raise; end if;
      v_raised := true;
  end;
  if not v_raised then
    raise exception 'assertion failed: app.wms_pick_record_scope_ok did not reject a forged actor -- ISS-2026-186''s partial fix has regressed';
  end if;

  v_raised := false;
  begin
    perform app.label_subject_record_scope_ok(v_victim, v_fake_tenant, 'bin', v_fake_id);
  exception
    when insufficient_privilege then
      if sqlerrm !~ 'actor_identity_mismatch' then raise; end if;
      v_raised := true;
  end;
  if not v_raised then
    raise exception 'assertion failed: app.label_subject_record_scope_ok did not reject a forged actor -- ISS-2026-186''s partial fix has regressed';
  end if;

  -- The same session acting as ITSELF must not be blanket-denied -- v_self holds no real
  -- warehouse/case/label row, so this must fail on a DIFFERENT, later check (or return
  -- false), never actor_identity_mismatch, proving the fix is not a blanket deny.
  begin
    perform app.wms_pick_record_scope_ok(v_self, v_fake_id, 'irrelevant');
  exception
    when insufficient_privilege then
      if sqlerrm ~ 'actor_identity_mismatch' then
        raise exception 'assertion failed: app.wms_pick_record_scope_ok rejected the caller acting as themselves -- the fix has become a blanket deny, not an identity check';
      end if;
    when others then
      null; -- any non-identity failure past the assert is fine and expected here
  end;

  perform set_config('request.jwt.claims', '', true);
  raise notice 'Track B Batch 6 live two-session forced-spoof proof: app.claim_case_record_scope_ok, app.wms_pick_record_scope_ok and app.label_subject_record_scope_ok all reject a forged actor from a genuine authenticated session; an own-identity call is not blanket-denied';
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

\echo '>> HDN-373 (Step 15, Prompt 373, RLS and RBAC Audit): app.evaluate_permission -- the single authority gate ~1,124 functions share -- now denies once a claimed actor is no longer a genuine active tenant member (app.has_active_tenant_membership), even when their app.role_assignments row was never separately cleaned up. app.revoke_auth_identity (Platform Core''s own tenant-membership-revocation RPC, distinct from HRT-295''s app.transition_user_status fix immediately above, which only cascades role_assignments for its own HRIS-domain status-transition path) touches only app.tenant_user_identities -- it never cascades to role_assignments, and this gate is the reason that omission no longer matters.'
do $$
declare
  v_tenant_id uuid;
  v_decision app.rbac_decision;
  v_active_count integer;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmerbac');

  -- Baseline restored by the HRT-295 block immediately above: grantee holds a genuine,
  -- active FIN:Approve role_assignment again.
  v_decision := app.evaluate_permission('00000000-0000-0000-0000-000000000401', v_tenant_id, 'FIN', 'Approve');
  if not v_decision.allowed then
    raise exception 'assertion failed: expected grantee to hold FIN:Approve before this block''s own revoke_auth_identity call, got allowed=%', v_decision.allowed;
  end if;

  perform app.revoke_auth_identity('00000000-0000-0000-0000-000000000401', v_tenant_id, 'HDN-373 revocation-propagation regression', 'tester');

  -- The vulnerability class, made concrete: the role_assignment itself is genuinely
  -- untouched by revoke_auth_identity -- this is not a no-op repro, the stale grant
  -- really is still sitting there.
  select count(*) into v_active_count from app.role_assignments
  where tenant_id = v_tenant_id and auth_user_id = '00000000-0000-0000-0000-000000000401' and status = 'active';
  if v_active_count = 0 then
    raise exception 'assertion failed: expected the active role_assignment to survive revoke_auth_identity untouched (that is the defect this test proves is now mitigated at evaluate_permission itself), found 0 -- test fixture assumption broken';
  end if;

  v_decision := app.evaluate_permission('00000000-0000-0000-0000-000000000401', v_tenant_id, 'FIN', 'Approve');
  if v_decision.allowed then
    raise exception 'assertion failed: a revoked tenant member (app.tenant_user_identities.status=revoked) still evaluated allowed=true via a stale role_assignments row -- the HDN-373 tenant-membership regression this gate exists to prevent has reappeared';
  end if;
  if v_decision.reason is distinct from 'not_active_tenant_member' then
    raise exception 'assertion failed: expected reason=not_active_tenant_member for a revoked tenant member, got %', v_decision.reason;
  end if;

  -- Supreme Admin is unaffected by this fix -- RPD-022's own cross-tenant residual risk
  -- is independent of any single tenant's own membership state.
  v_decision := app.evaluate_permission('00000000-0000-0000-0000-000000000403', v_tenant_id, 'FIN', 'Approve');
  if v_decision.reason <> 'supreme_admin_exception' then
    raise exception 'assertion failed: expected Supreme Admin to remain unaffected by the tenant-membership check (supreme_admin_exception), got reason=%', v_decision.reason;
  end if;

  raise notice 'HDN-373 RBAC-evaluator tenant-membership regression proof: a revoked tenant member with a surviving, uncleaned role_assignment is now correctly denied (not_active_tenant_member), and Supreme Admin remains unaffected';
end;
$$;

\echo '>> ISS-2026-072 (Step 16 historical-issue-backlog remediation, 20260826040000): app.evaluate_permission now independently re-checks app.users.status, defense in depth against exactly the drift class the two blocks above do NOT cover -- an app.users.status change made OUTSIDE app.transition_user_status (a raw UPDATE, deliberately used here instead of the governed transition, so the role_assignments cascade does NOT fire) leaves role_assignments untouched, yet must still be denied. A fresh, dedicated actor is used (not the grantee/401 fixture above, whose tenant membership is already revoked by the HDN-373 block immediately above) so this test genuinely exercises "still an active tenant member, active role_assignments row, but app.users.status itself is not active" -- the one path neither prior fix reaches.'
do $$
declare
  v_tenant_id uuid;
  v_actor uuid := '00000000-0000-0000-0000-000000000404';
  v_decision app.rbac_decision;
  v_active_count integer;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmerbac');

  insert into auth.users (id, email) values (v_actor, 'platformstatus@example.test');
  perform app.invite_user(v_tenant_id, v_actor, 'platformstatus@example.test', 'Platform Status Actor', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'platformstatus@example.test'), 'active', 'onboarded', 'tester');
  perform app.assign_role(
    v_tenant_id,
    (select rv.id from app.role_versions rv join app.roles r on r.id = rv.role_id where r.tenant_id = v_tenant_id and r.name = 'RBAC Finance Approver' and rv.status = 'published'),
    v_actor,
    v_actor,
    'tester'
  );

  -- Baseline: a genuine, active tenant member with an active role_assignments row is
  -- allowed, exactly like grantee/401 originally was.
  v_decision := app.evaluate_permission(v_actor, v_tenant_id, 'FIN', 'Approve');
  if not v_decision.allowed or v_decision.reason <> 'role_grant' then
    raise exception 'assertion failed: expected this fresh actor to hold FIN:Approve via role_grant before any status manipulation, got allowed=%, reason=%', v_decision.allowed, v_decision.reason;
  end if;

  -- Deliberately bypass app.transition_user_status -- a raw UPDATE, exactly the drift
  -- path HRT-295''s own cascade cannot see (it only fires when THAT function performs the
  -- transition). This is the live-forced defect this migration closes, not a synthetic one.
  update app.users set status = 'suspended' where tenant_id = v_tenant_id and auth_user_id = v_actor;

  select count(*) into v_active_count from app.role_assignments
  where tenant_id = v_tenant_id and auth_user_id = v_actor and status = 'active';
  if v_active_count = 0 then
    raise exception 'assertion failed: expected the role_assignments row to survive a raw app.users.status UPDATE untouched (that is the whole point of this test -- the cascade must NOT have fired), found 0 -- test fixture assumption broken';
  end if;

  v_decision := app.evaluate_permission(v_actor, v_tenant_id, 'FIN', 'Approve');
  if v_decision.allowed then
    raise exception 'assertion failed: an actor whose app.users.status is suspended (via a raw UPDATE that never touched role_assignments) still evaluated allowed=true -- ISS-2026-072''s app.users.status half has reappeared';
  end if;
  if v_decision.reason is distinct from 'not_active_platform_user' then
    raise exception 'assertion failed: expected reason=not_active_platform_user for a suspended app.users row with a surviving active role_assignment, got %', v_decision.reason;
  end if;

  -- Same proof for 'revoked'.
  update app.users set status = 'revoked' where tenant_id = v_tenant_id and auth_user_id = v_actor;
  v_decision := app.evaluate_permission(v_actor, v_tenant_id, 'FIN', 'Approve');
  if v_decision.allowed or v_decision.reason is distinct from 'not_active_platform_user' then
    raise exception 'assertion failed: expected reason=not_active_platform_user for a revoked app.users row too, got allowed=%, reason=%', v_decision.allowed, v_decision.reason;
  end if;

  -- Restoring app.users.status alone (still bypassing app.transition_user_status) is
  -- immediately reflected -- this is a live re-check every call, not a one-way sticky flag.
  update app.users set status = 'active' where tenant_id = v_tenant_id and auth_user_id = v_actor;
  v_decision := app.evaluate_permission(v_actor, v_tenant_id, 'FIN', 'Approve');
  if not v_decision.allowed or v_decision.reason <> 'role_grant' then
    raise exception 'assertion failed: expected FIN:Approve to be allowed again immediately once app.users.status returned to active, got allowed=%, reason=%', v_decision.allowed, v_decision.reason;
  end if;

  -- The one real design decision this migration made, live-proved rather than assumed:
  -- Supreme Admin (000000403, granted globally at this file''s own later setup block,
  -- with ZERO app.users row in ANY tenant, confirmed by this file''s own fixture) remains
  -- unaffected -- proving the new check''s placement AFTER the Supreme Admin branch is
  -- correct. Placing it before would have made this assertion fail.
  v_decision := app.evaluate_permission('00000000-0000-0000-0000-000000000403', v_tenant_id, 'FIN', 'Approve');
  if v_decision.reason <> 'supreme_admin_exception' then
    raise exception 'assertion failed: expected Supreme Admin (who holds no app.users row in this tenant at all) to remain unaffected by the new app.users.status check (supreme_admin_exception), got reason=%', v_decision.reason;
  end if;

  raise notice 'ISS-2026-072 app.users.status defense-in-depth proof: a raw, out-of-band status change (bypassing app.transition_user_status entirely) is correctly denied even though role_assignments never cascaded, recovers immediately once status returns to active, and Supreme Admin (who has no app.users row in this tenant) remains unaffected';
end;
$$;

\echo '>> ISS-2026-264 (Step 16 historical-issue-backlog remediation, 20260826110000): app.evaluate_permission now denies an actor whose every tracked app.user_sessions row for this tenant is revoked -- the real enforcement half app.revoke_all_actor_sessions previously lacked entirely -- while an actor who has never had any session registered at all remains completely unaffected (this check must never universally deny an untracked actor).'
do $$
declare
  v_tenant_id uuid;
  v_actor uuid := '00000000-0000-0000-0000-000000000405';
  v_decision app.rbac_decision;
  v_session_1 app.user_sessions;
  v_session_2 app.user_sessions;
  v_revoked_count integer;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmerbac');

  insert into auth.users (id, email) values (v_actor, 'sessionrevocation@example.test');
  perform app.invite_user(v_tenant_id, v_actor, 'sessionrevocation@example.test', 'Session Revocation Actor', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'sessionrevocation@example.test'), 'active', 'onboarded', 'tester');
  perform app.assign_role(
    v_tenant_id,
    (select rv.id from app.role_versions rv join app.roles r on r.id = rv.role_id where r.tenant_id = v_tenant_id and r.name = 'RBAC Finance Approver' and rv.status = 'published'),
    v_actor,
    v_actor,
    'tester'
  );

  -- Baseline, before any session is ever registered: completely unaffected -- this is
  -- the exact scenario every real login predating this fix (and any future login path
  -- that never calls app.register_user_session) must remain in. If this check ever
  -- became "deny when zero active sessions exist" instead of "deny when at least one
  -- session is tracked and all are revoked," this assertion would immediately fail.
  v_decision := app.evaluate_permission(v_actor, v_tenant_id, 'FIN', 'Approve');
  if not v_decision.allowed or v_decision.reason <> 'role_grant' then
    raise exception 'assertion failed: expected an actor with zero tracked sessions to be completely unaffected by this check, got allowed=%, reason=%', v_decision.allowed, v_decision.reason;
  end if;

  -- Register 2 sessions (2 devices) -- still allowed with at least one active.
  v_session_1 := app.register_user_session(v_tenant_id, 'laptop', '203.0.113.10', v_actor, 'tester');
  v_session_2 := app.register_user_session(v_tenant_id, 'phone', '203.0.113.11', v_actor, 'tester');
  v_decision := app.evaluate_permission(v_actor, v_tenant_id, 'FIN', 'Approve');
  if not v_decision.allowed or v_decision.reason <> 'role_grant' then
    raise exception 'assertion failed: expected an actor with 2 active tracked sessions to remain allowed, got allowed=%, reason=%', v_decision.allowed, v_decision.reason;
  end if;

  -- Revoke ALL of this actor's sessions in this tenant (the real HDN-384 incident-drill
  -- action, called by Supreme Admin 403 who already holds SEC:Configure via the
  -- supreme_admin_exception). This is the real enforcement gap ISS-2026-264 found: before
  -- this fix, this call had zero effect on evaluate_permission's own decision.
  v_revoked_count := app.revoke_all_actor_sessions(v_tenant_id, v_actor, 'security review', '00000000-0000-0000-0000-000000000403', 'tester');
  if v_revoked_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 sessions revoked, got %', v_revoked_count;
  end if;

  v_decision := app.evaluate_permission(v_actor, v_tenant_id, 'FIN', 'Approve');
  if v_decision.allowed then
    raise exception 'assertion failed: an actor whose every tracked session is revoked still evaluated allowed=true -- ISS-2026-264''s own enforcement gap has reappeared';
  end if;
  if v_decision.reason is distinct from 'all_sessions_revoked' then
    raise exception 'assertion failed: expected reason=all_sessions_revoked once every tracked session is revoked, got %', v_decision.reason;
  end if;

  -- A fresh sign-in (a new session registered, exactly what lib/auth/register-login-
  -- session.ts wires into the real login action) immediately restores authority -- a
  -- live re-check every call, not a one-way sticky lockout.
  perform app.register_user_session(v_tenant_id, 'laptop-2', '203.0.113.12', v_actor, 'tester');
  v_decision := app.evaluate_permission(v_actor, v_tenant_id, 'FIN', 'Approve');
  if not v_decision.allowed or v_decision.reason <> 'role_grant' then
    raise exception 'assertion failed: expected FIN:Approve to be allowed again immediately once a fresh session was registered, got allowed=%, reason=%', v_decision.allowed, v_decision.reason;
  end if;

  -- Supreme Admin (000000403, zero app.users row in any tenant) remains unaffected --
  -- proving this check's placement after the Supreme Admin branch is correct, mirroring
  -- ISS-2026-072's own identical proof above.
  v_decision := app.evaluate_permission('00000000-0000-0000-0000-000000000403', v_tenant_id, 'FIN', 'Approve');
  if v_decision.reason <> 'supreme_admin_exception' then
    raise exception 'assertion failed: expected Supreme Admin to remain unaffected by the new session-revocation check, got reason=%', v_decision.reason;
  end if;

  raise notice 'ISS-2026-264 session-revocation enforcement proof: an untracked actor is unaffected, an actor with an active tracked session is allowed, an actor whose every tracked session is revoked is denied all_sessions_revoked, a fresh session immediately restores authority, and Supreme Admin remains unaffected';
end;
$$;

\echo '>> HDN-373 (ISS-2026-171/173, carried forward from HDN-372; plus app.notification_preferences, found this checkpoint): own-row RLS policies on app.notifications/app.notification_preferences/app.saved_report_views now require an active tenant membership, not merely row ownership -- a revoked ex-member no longer retains RLS-level read access to their own past rows. Live-tested for notification_preferences (achievable without a large cross-table fixture); structurally verified for all three via the live policy expression, mirroring this file''s own established pg_get_expr sweep pattern.'
do $$
declare
  v_tenant_id uuid;
  v_grantee_auth_id uuid := '00000000-0000-0000-0000-000000000401';
  v_raised boolean;
  v_count integer;
  v_bad_policies text[];
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmerbac');

  -- Structural check first: every one of the three own-row policies' own-row branch must
  -- reference has_active_tenant_membership. A regex on the full policy expression (not
  -- just the own-row branch) is intentionally loose -- correctness of the exact reference
  -- live proof for notification_preferences below.
  select array_agg(c.relname || '.' || pol.polname order by c.relname, pol.polname) into v_bad_policies
  from pg_policy pol
  join pg_class c on c.oid = pol.polrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'app'
    and c.relname in ('notifications', 'notification_preferences', 'saved_report_views')
    and pol.polname in ('notifications_select_own', 'notification_preferences_select_own', 'saved_report_views_select_scoped')
    and pg_get_expr(pol.polqual, pol.polrelid) !~ 'has_active_tenant_membership';

  if v_bad_policies is not null then
    raise exception 'assertion failed: % own-row policy(ies) missing has_active_tenant_membership -- ISS-2026-171/173 has regressed: %', array_length(v_bad_policies, 1), v_bad_policies;
  end if;

  -- Live behavioral proof for notification_preferences (the simplest of the three to
  -- fixture -- no config_version_id/report_type_code cross-table dependency).
  insert into app.notification_preferences (tenant_id, auth_user_id, notification_type_code, channel, enabled)
  values (v_tenant_id, v_grantee_auth_id, 'test.hdn373.own_row_revoked', 'in_app', true);

  perform app.revoke_auth_identity(v_grantee_auth_id, v_tenant_id, 'HDN-373 own-row RLS regression', 'tester');

  begin
    set local role authenticated;
    perform set_config('request.jwt.claims', json_build_object('sub', v_grantee_auth_id::text, 'role', 'authenticated')::text, true);
    if (select current_user) <> 'authenticated' then
      raise exception 'harness failure: role switch to authenticated did not take effect';
    end if;

    select count(*) into v_count from app.notification_preferences
    where tenant_id = v_tenant_id and auth_user_id = v_grantee_auth_id and notification_type_code = 'test.hdn373.own_row_revoked';
    if v_count <> 0 then
      raise exception 'assertion failed: a revoked ex-member still read their own app.notification_preferences row via direct RLS (% rows) -- ISS-2026-171-shaped regression', v_count;
    end if;

    reset role;
  exception
    when others then
      reset role;
      raise;
  end;
  perform set_config('request.jwt.claims', '', true);

  -- No restoration needed: this is the final block in this file, and grantee's
  -- tenant_user_identities status in this tenant is not read by anything after this
  -- point (their app.role_assignments state, exercised by the block above this one, is a
  -- separate table already left in a defined state by that block's own final re-grant).

  raise notice 'HDN-373 own-row RLS membership regression proof: notifications/notification_preferences/saved_report_views policies all reference has_active_tenant_membership; a revoked ex-member live-confirmed denied on notification_preferences';
end;
$$;

-- ===========================================================================
-- ISS-2026-176 (Track B Batch 1): structural regression guard, not a
-- functional fix. app-schema views granted SELECT to authenticated run in
-- owner mode by default (no security_invoker), which is CORRECT and
-- REQUIRED for this repository's own RBAC column-masking views (flipping to
-- invoker mode reproduces a real, previously-shipped failure --
-- 20260723210000_create_commercial_opportunity_management.sql's own
-- documented "permission denied for table opportunities" -- since
-- authenticated has no column-level grant on the masked columns on the base
-- table) and for the hand-rolled-predicate plain views (base-table RLS has
-- also been proven untrustworthy under this role's BYPASSRLS setting --
-- app.users_directory's own history, 20260716113048_create_audit_trail.sql).
-- So this does NOT flip any view to security_invoker=true -- it fails the
-- suite if a FUTURE view is added to this set (granted to authenticated,
-- not security_invoker) without being added to this reviewed allow-list,
-- catching an unreviewed addition rather than assuming every future view
-- author rediscovers this same reasoning.
do $$
declare
  v_expected text[] := array[
    -- RBAC column-masking views (22) -- security_invoker=false is required,
    -- not incidental: each nulls sensitive columns via a permission check,
    -- and the base table's own column-level grant excludes those columns.
    'users_directory', 'opportunities_directory', 'costing_responses_directory',
    'rate_selections_directory', 'margin_calculations_directory', 'quotations_directory',
    'quotation_lines_directory', 'customer_contract_price_components_directory',
    'credit_profiles_directory', 'credit_check_snapshots_directory', 'credit_profile_overrides_directory',
    'job_order_handoffs_directory', 'job_orders_directory', 'exceptions_directory',
    'shipment_actual_costs_directory', 'job_profitability_directory', 'vendor_rate_tiers_directory',
    'vendor_rate_versions_directory', 'sourcing_requests_directory', 'rfq_responses_directory',
    'purchase_orders_directory', 'purchase_order_events_directory',
    -- ISS-2026-060: app.vendor_rate_zone_distance_tiers_directory (20260902030000)
    -- -- mirrors vendor_rate_tiers_directory''s own hardened pattern-5 row predicate
    -- and PRC:View cost (app.has_prc_view_cost) column-masking byte-for-byte;
    -- security_invoker=false is required for the identical reason every other
    -- entry on this list needs it (the base table''s own column-level grant
    -- excludes amount/minimum_charge, so an invoker-mode view could not read
    -- them at all to mask them).
    'vendor_rate_zone_distance_tiers_directory',
    -- Plain, unmasked projection views (13) -- exist for the "always read
    -- through a _directory-shaped view" convention; carry their own
    -- hand-rolled tenant/row predicate, proven correct independently.
    'v_active_vendor_rates', 'sourcing_candidates_directory', 'rfqs_directory',
    'rfq_requirement_lines_directory', 'rfq_invitations_directory', 'rfq_clarifications_directory',
    'dispatch_ready_queue', 'dispatch_board_queue', 'vendor_comparisons_directory',
    'vendor_comparison_offers_directory', 'vendor_comparison_offer_scores_directory',
    'vendor_comparison_events_directory', 'purchase_order_lines_directory'
  ];
  v_unreviewed text[];
  v_expected_count integer;
  v_reviewed_still_granted_count integer;
begin
  select array_agg(c.relname order by c.relname) into v_unreviewed
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'app' and c.relkind = 'v'
    and has_table_privilege('authenticated', c.oid, 'SELECT')
    and not coalesce(c.reloptions::text[] && array['security_invoker=true'], false)
    and c.relname <> all (v_expected);

  if v_unreviewed is not null then
    raise exception 'assertion failed: % app-schema view(s) granted to authenticated with no security_invoker=true and not on the reviewed allow-list: % (ISS-2026-176 regression -- review the new view''s own predicate/masking correctness, then add its name to v_expected in rbac-enforcement.sql)', array_length(v_unreviewed, 1), v_unreviewed;
  end if;

  -- Symmetry check: every name ON the allow-list should still actually
  -- exist, be granted to authenticated, and still be non-invoker -- catches
  -- the allow-list itself silently drifting stale (e.g. a view renamed or
  -- dropped, or someone flipping one to security_invoker without pruning
  -- this list, which would otherwise never be re-noticed).
  select count(*) into v_expected_count from unnest(v_expected);
  select count(*) into v_reviewed_still_granted_count
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'app' and c.relkind = 'v'
    and has_table_privilege('authenticated', c.oid, 'SELECT')
    and not coalesce(c.reloptions::text[] && array['security_invoker=true'], false)
    and c.relname = any (v_expected);

  if v_reviewed_still_granted_count <> v_expected_count then
    raise exception 'assertion failed: the ISS-2026-176 allow-list names % views, but only % of them are still (authenticated-granted, non-invoker) app views -- the allow-list has drifted stale (a view was renamed, dropped, or flipped to security_invoker without updating rbac-enforcement.sql)', v_expected_count, v_reviewed_still_granted_count;
  end if;

  raise notice 'ISS-2026-176 view-grant regression guard: % reviewed views confirmed, zero unreviewed authenticated-granted non-invoker app view found', v_expected_count;
end;
$$;


\echo '>> ISS-2026-186 closure: the six remaining RBAC boolean-oracle primitives are closed AT THE public.* WRAPPER, which is the only layer PostgREST can reach -- and the app.* functions they delegate to are deliberately left unguarded, because they are RLS predicates in ~918 policies and are called with genuinely third-party actor arguments inside other definer functions.'
do $$
declare
  v_self uuid := '00000000-0000-0000-0000-000000000401';
  v_victim uuid := '00000000-0000-0000-0000-000000000402';
  v_fake_tenant uuid := gen_random_uuid();
  v_raised boolean;
  v_ok boolean;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', v_self::text, 'role', 'authenticated')::text, true);

  -- PROPERTY 1 -- the oracle is closed. Each public.* wrapper must refuse to answer a
  -- question about an identity that is not the calling session's own.
  v_raised := false;
  begin
    perform public.is_supreme_admin(v_victim);
  exception
    when insufficient_privilege then
      if sqlerrm !~ 'actor_identity_mismatch' then raise; end if;
      v_raised := true;
  end;
  if not v_raised then
    raise exception 'assertion failed: public.is_supreme_admin answered about another identity -- ISS-2026-186 has regressed and the platform authority graph is a boolean oracle again';
  end if;

  v_raised := false;
  begin
    perform public.has_active_tenant_membership(v_fake_tenant, v_victim);
  exception
    when insufficient_privilege then
      if sqlerrm !~ 'actor_identity_mismatch' then raise; end if;
      v_raised := true;
  end;
  if not v_raised then
    raise exception 'assertion failed: public.has_active_tenant_membership answered about another identity -- ISS-2026-186 has regressed';
  end if;

  v_raised := false;
  begin
    perform public.actor_holds_customer_user_layer(v_fake_tenant, v_victim);
  exception
    when insufficient_privilege then
      if sqlerrm !~ 'actor_identity_mismatch' then raise; end if;
      v_raised := true;
  end;
  if not v_raised then
    raise exception 'assertion failed: public.actor_holds_customer_user_layer answered about another identity -- ISS-2026-186 has regressed';
  end if;

  v_raised := false;
  begin
    perform public.has_active_support_grant(v_fake_tenant, v_victim);
  exception
    when insufficient_privilege then
      if sqlerrm !~ 'actor_identity_mismatch' then raise; end if;
      v_raised := true;
  end;
  if not v_raised then
    raise exception 'assertion failed: public.has_active_support_grant answered about another identity -- ISS-2026-186 has regressed';
  end if;

  v_raised := false;
  begin
    perform public.can_access_record(v_victim, v_fake_tenant, v_victim, '{}'::uuid[], null);
  exception
    when insufficient_privilege then
      if sqlerrm !~ 'actor_identity_mismatch' then raise; end if;
      v_raised := true;
  end;
  if not v_raised then
    raise exception 'assertion failed: public.can_access_record answered for a forged actor -- ISS-2026-186 has regressed';
  end if;

  v_raised := false;
  begin
    perform public.resolve_locale_context(v_fake_tenant, v_victim);
  exception
    when insufficient_privilege then
      if sqlerrm !~ 'actor_identity_mismatch' then raise; end if;
      v_raised := true;
  end;
  if not v_raised then
    raise exception 'assertion failed: public.resolve_locale_context answered about another identity -- ISS-2026-186 has regressed';
  end if;

  -- PROPERTY 2 -- the guard is not a blanket denial. Asking about YOURSELF still works, or
  -- the "fix" would simply have broken the customer-portal guard and the API request pipeline,
  -- both of which pass the session's own id.
  v_ok := public.is_supreme_admin(v_self);
  if v_ok is null then
    raise exception 'assertion failed: public.is_supreme_admin returned null for an own-identity call -- the guard is denying the legitimate self case';
  end if;
  v_ok := public.has_active_tenant_membership(v_fake_tenant, v_self);
  if v_ok is null then
    raise exception 'assertion failed: public.has_active_tenant_membership returned null for an own-identity call';
  end if;

  -- PROPERTY 3 -- GUARD THE GUARD, and the single most important assertion in this block.
  -- The app.* functions must STILL answer about a third party, because that is exactly what
  -- ~918 RLS policies and every internal third-party-actor call site depend on. If a future
  -- change "tidies up" by pushing the assert down into app.*, this fails -- which is the whole
  -- point: it would silently convert row-level denials into aborted queries across the product.
  v_ok := app.is_supreme_admin(v_victim);
  if v_ok is null then
    raise exception 'assertion failed: app.is_supreme_admin no longer answers about a third party -- the assert was pushed down into the app.* layer, which breaks 304 RLS policies and every internal third-party call site';
  end if;
  v_ok := app.has_active_tenant_membership(v_fake_tenant, v_victim);
  if v_ok is null then
    raise exception 'assertion failed: app.has_active_tenant_membership no longer answers about a third party -- this backs 266 RLS policies and app.evaluate_permission''s own not_active_tenant_member denial, which would become a query error';
  end if;
  v_ok := app.actor_holds_customer_user_layer(v_fake_tenant, v_victim);
  if v_ok is null then
    raise exception 'assertion failed: app.actor_holds_customer_user_layer no longer answers about a third party -- 276 RLS policies depend on it';
  end if;

  perform set_config('request.jwt.claims', '', true);

  -- PROPERTY 4 -- anonymous, pre-login locale resolution must still work. resolve_locale_context
  -- is the one wrapper of the six granted to anon, because a tenant's login page has to render
  -- in the right language before any session exists. With no session, auth.uid() is null and the
  -- assert is a no-op by construction -- asserted here rather than reasoned about.
  perform public.resolve_locale_context(v_fake_tenant);
  perform public.resolve_locale_context(v_fake_tenant, null);

  raise notice 'ISS-2026-186 closure: all six public.* wrappers refuse a forged actor; own-identity calls still answer; the app.* layer still answers about third parties (RLS and internal callers intact); anonymous pre-login locale resolution still works';
end;
$$;

\echo 'ALL PLT-112 db-test assertions passed.'
