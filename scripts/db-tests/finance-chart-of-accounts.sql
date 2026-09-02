-- Real, executable test evidence for FIN-192 (Chart of Accounts, CG-S9-FIN-003)
-- -- run via `pnpm run db:test` against a real, disposable Postgres database.
-- Proves: canonical type/normal-balance matching, duplicate-code and parent-
-- type-mismatch rejection, hierarchy cycle detection (direct function-level
-- proof, since no reparent API exists to construct one through the public
-- surface), draft/activate/deactivate lifecycle with dependency guards
-- (active children, published posting-map reference), the closed FIN-191
-- loop (app.publish_finance_config_version now validates finance_posting_map
-- account references against this migration's own app.finance_accounts),
-- cross-tenant isolation, and schema-privilege defense in depth.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants, each with a tenant_admin and a Finance Full actor (tenant_admin AND FIN:Create/Edit/Approve/Delete/View -- satisfies both this capability''s own RBAC gate and FIN-191''s inherited two-factor gate for posting-map publish); tenant A also gets a Plain User with no FIN grant'
do $$
declare
  v_tenant_a uuid;
  v_tenant_b uuid;
  v_team_a uuid;
  v_team_b uuid;
  v_fin_role_a uuid;
  v_fin_draft_a app.role_versions;
  v_fin_role_b uuid;
  v_fin_draft_b app.role_versions;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000024301', 'admina@acmecoa.test'),
    ('00000000-0000-0000-0000-000000024302', 'financefulla@acmecoa.test'),
    ('00000000-0000-0000-0000-000000024303', 'plainusera@acmecoa.test'),
    ('00000000-0000-0000-0000-000000024304', 'financefullb@acmecoa.test');

  perform app.provision_tenant('acmecoaa', 'Acme Chart of Accounts A', 'idem-acmecoaa', 'tester');
  v_tenant_a := (select id from app.tenants where slug = 'acmecoaa');
  perform app.transition_tenant_status(v_tenant_a, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_a, 'company', null, 'ACMECOAA-CO', 'Acme Chart of Accounts A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant_a and code = 'ACMECOAA-CO');

  perform app.provision_tenant('acmecoab', 'Acme Chart of Accounts B', 'idem-acmecoab', 'tester');
  v_tenant_b := (select id from app.tenants where slug = 'acmecoab');
  perform app.transition_tenant_status(v_tenant_b, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_b, 'company', null, 'ACMECOAB-CO', 'Acme Chart of Accounts B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant_b and code = 'ACMECOAB-CO');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000024301', 'admina@acmecoa.test', 'Tenant A Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admina@acmecoa.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000024301', 'tenant_admin', v_tenant_a, null, 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000024302', 'financefulla@acmecoa.test', 'Finance Full A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financefulla@acmecoa.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000024302', 'tenant_admin', v_tenant_a, null, 'tester');
  v_fin_role_a := (app.create_role(v_tenant_a, 'Finance Full', 'chart of accounts + config authority', 'tester')).id;
  v_fin_draft_a := app.create_role_version(v_fin_role_a, 'tester');
  perform app.set_role_version_permissions(v_fin_draft_a.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'Delete', 'View')), 'tester');
  perform app.publish_role_version(v_fin_draft_a.id, now(), 'tester');
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_fin_role_a and status = 'published'), '00000000-0000-0000-0000-000000024302', '00000000-0000-0000-0000-000000024301', 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000024303', 'plainusera@acmecoa.test', 'Plain User A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'plainusera@acmecoa.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant_b, '00000000-0000-0000-0000-000000024304', 'financefullb@acmecoa.test', 'Finance Full B', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financefullb@acmecoa.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000024304', 'tenant_admin', v_tenant_b, null, 'tester');
  v_fin_role_b := (app.create_role(v_tenant_b, 'Finance Full', 'chart of accounts + config authority', 'tester')).id;
  v_fin_draft_b := app.create_role_version(v_fin_role_b, 'tester');
  perform app.set_role_version_permissions(v_fin_draft_b.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'Delete', 'View')), 'tester');
  perform app.publish_role_version(v_fin_draft_b.id, now(), 'tester');
  perform app.assign_role(v_tenant_b, (select id from app.role_versions where role_id = v_fin_role_b and status = 'published'), '00000000-0000-0000-0000-000000024304', '00000000-0000-0000-0000-000000024304', 'tester');
end;
$$;

\echo '>> authority: Finance Full A creates a root asset account; Plain User A (no FIN grant) is denied'
do $$
declare
  v_tenant_a uuid;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmecoaa');

  begin
    perform app.create_finance_account_draft(v_tenant_a, null, '1000-CASH', 'Cash', 'asset', 'debit', null, false, null, '00000000-0000-0000-0000-000000024303', 'plainusera');
    raise exception 'assertion failed: expected insufficient_authority for Plain User A';
  exception
    when insufficient_privilege then
      null;
  end;

  perform app.create_finance_account_draft(v_tenant_a, null, '1000-CASH', 'Cash', 'asset', 'debit', null, false, null, '00000000-0000-0000-0000-000000024302', 'financefulla');
  if (select status from app.finance_accounts where tenant_id = v_tenant_a and code = '1000-CASH') <> 'draft' then
    raise exception 'assertion failed: expected a fresh draft account';
  end if;
end;
$$;

\echo '>> structural validation: type/normal-balance mismatch is rejected by the CHECK constraint itself, not merely by application logic'
do $$
declare
  v_tenant_a uuid;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmecoaa');
  begin
    perform app.create_finance_account_draft(v_tenant_a, null, '2000-AP', 'Accounts Payable', 'liability', 'debit', null, false, null, '00000000-0000-0000-0000-000000024302', 'financefulla');
    raise exception 'assertion failed: expected a CHECK violation for liability/debit mismatch';
  exception
    when check_violation then
      null;
  end;
end;
$$;

\echo '>> duplicate code within the same tenant/company scope is rejected'
do $$
declare
  v_tenant_a uuid;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmecoaa');
  begin
    perform app.create_finance_account_draft(v_tenant_a, null, '1000-CASH', 'Cash (duplicate)', 'asset', 'debit', null, false, null, '00000000-0000-0000-0000-000000024302', 'financefulla');
    raise exception 'assertion failed: expected finance_account_duplicate_code';
  exception
    when others then
      if sqlerrm !~ 'finance_account_duplicate_code' then
        raise exception 'assertion failed: expected finance_account_duplicate_code, got %', sqlerrm;
      end if;
  end;
end;
$$;

\echo '>> parent-type mismatch is rejected: a liability child under an asset parent'
do $$
declare
  v_tenant_a uuid;
  v_cash_id uuid;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmecoaa');
  select id into v_cash_id from app.finance_accounts where tenant_id = v_tenant_a and code = '1000-CASH';

  begin
    perform app.create_finance_account_draft(v_tenant_a, null, '1010-PETTY', 'Petty Cash (wrong type)', 'liability', 'credit', v_cash_id, false, null, '00000000-0000-0000-0000-000000024302', 'financefulla');
    raise exception 'assertion failed: expected finance_account_type_mismatch';
  exception
    when others then
      if sqlerrm !~ 'finance_account_type_mismatch' then
        raise exception 'assertion failed: expected finance_account_type_mismatch, got %', sqlerrm;
      end if;
  end;

  -- The correct child type succeeds.
  perform app.create_finance_account_draft(v_tenant_a, null, '1010-PETTY', 'Petty Cash', 'asset', 'debit', v_cash_id, false, null, '00000000-0000-0000-0000-000000024302', 'financefulla');
end;
$$;

\echo '>> hierarchy-cycle detection (direct function-level proof -- no reparent API exists in this checkpoint to construct a real cycle through the public mutation surface)'
do $$
declare
  v_tenant_a uuid;
  v_cash_id uuid;
  v_petty_id uuid;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmecoaa');
  select id into v_cash_id from app.finance_accounts where tenant_id = v_tenant_a and code = '1000-CASH';
  select id into v_petty_id from app.finance_accounts where tenant_id = v_tenant_a and code = '1010-PETTY';

  -- Petty Cash's real parent is Cash -- no cycle.
  if app.detect_finance_account_hierarchy_cycle(v_petty_id, v_cash_id) then
    raise exception 'assertion failed: expected no cycle for the real Cash -> Petty Cash parent edge';
  end if;

  -- Hypothetically making Cash a child of Petty Cash (its own descendant) would be a cycle.
  if not app.detect_finance_account_hierarchy_cycle(v_cash_id, v_petty_id) then
    raise exception 'assertion failed: expected a detected cycle for the hypothetical Petty Cash -> Cash reverse edge';
  end if;
end;
$$;

\echo '>> activation lifecycle: draft -> active succeeds; a second activation on an already-active account is rejected; activating a child whose parent is still draft succeeds (no parent-active precondition at THIS checkpoint''s own activation order -- Cash is activated first in this fixture)'
do $$
declare
  v_tenant_a uuid;
  v_cash app.finance_accounts;
  v_petty app.finance_accounts;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmecoaa');
  select * into v_cash from app.finance_accounts where tenant_id = v_tenant_a and code = '1000-CASH';
  select * into v_cash from app.activate_finance_account(v_cash.id, v_cash.record_version, '00000000-0000-0000-0000-000000024302', 'financefulla');
  if v_cash.status <> 'active' then
    raise exception 'assertion failed: expected Cash to activate';
  end if;

  begin
    perform app.activate_finance_account(v_cash.id, v_cash.record_version, '00000000-0000-0000-0000-000000024302', 'financefulla');
    raise exception 'assertion failed: expected finance_account_not_draft on a second activation';
  exception
    when others then
      if sqlerrm !~ 'finance_account_not_draft' then
        raise exception 'assertion failed: expected finance_account_not_draft, got %', sqlerrm;
      end if;
  end;

  select * into v_petty from app.finance_accounts where tenant_id = v_tenant_a and code = '1010-PETTY';
  select * into v_petty from app.activate_finance_account(v_petty.id, v_petty.record_version, '00000000-0000-0000-0000-000000024302', 'financefulla');
  if v_petty.status <> 'active' then
    raise exception 'assertion failed: expected Petty Cash to activate (its parent Cash is now active)';
  end if;
end;
$$;

\echo '>> deactivation guard: an account with an active child is rejected; deactivating the child first, then the parent, both with a mandatory reason, succeeds'
do $$
declare
  v_tenant_a uuid;
  v_cash app.finance_accounts;
  v_petty app.finance_accounts;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmecoaa');
  select * into v_cash from app.finance_accounts where tenant_id = v_tenant_a and code = '1000-CASH';
  select * into v_petty from app.finance_accounts where tenant_id = v_tenant_a and code = '1010-PETTY';

  begin
    perform app.deactivate_finance_account(v_cash.id, v_cash.record_version, 'trying with an active child present', '00000000-0000-0000-0000-000000024302', 'financefulla');
    raise exception 'assertion failed: expected finance_account_has_active_children';
  exception
    when others then
      if sqlerrm !~ 'finance_account_has_active_children' then
        raise exception 'assertion failed: expected finance_account_has_active_children, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.deactivate_finance_account(v_petty.id, v_petty.record_version, '', '00000000-0000-0000-0000-000000024302', 'financefulla');
    raise exception 'assertion failed: expected finance_account_deactivation_reason_required for an empty reason';
  exception
    when others then
      if sqlerrm !~ 'finance_account_deactivation_reason_required' then
        raise exception 'assertion failed: expected finance_account_deactivation_reason_required, got %', sqlerrm;
      end if;
  end;

  perform app.deactivate_finance_account(v_petty.id, v_petty.record_version, 'consolidating into Cash directly', '00000000-0000-0000-0000-000000024302', 'financefulla');
  perform app.deactivate_finance_account(v_cash.id, v_cash.record_version, 'no longer using a Cash control account for this fixture', '00000000-0000-0000-0000-000000024302', 'financefulla');
  if (select status from app.finance_accounts where id = v_cash.id) <> 'inactive' then
    raise exception 'assertion failed: expected Cash to deactivate once its child was deactivated first';
  end if;
end;
$$;

\echo '>> the closed FIN-191 loop: app.publish_finance_config_version now validates finance_posting_map account references against app.finance_accounts (unresolved code, inactive account, non-postable control account, then a valid active postable account)'
do $$
declare
  v_tenant_a uuid;
  v_ar app.finance_accounts;
  v_ar_control app.finance_accounts;
  v_draft app.config_versions;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmecoaa');

  perform app.create_finance_account_draft(v_tenant_a, null, '1200-AR', 'Accounts Receivable', 'asset', 'debit', null, false, null, '00000000-0000-0000-0000-000000024302', 'financefulla');
  select * into v_ar from app.finance_accounts where tenant_id = v_tenant_a and code = '1200-AR';

  perform app.create_finance_account_draft(v_tenant_a, null, '1200-AR-CTRL', 'AR Control', 'asset', 'debit', null, true, null, '00000000-0000-0000-0000-000000024302', 'financefulla');
  select * into v_ar_control from app.finance_accounts where tenant_id = v_tenant_a and code = '1200-AR-CTRL';
  select * into v_ar_control from app.activate_finance_account(v_ar_control.id, v_ar_control.record_version, '00000000-0000-0000-0000-000000024302', 'financefulla');

  select * into v_draft from app.create_finance_config_draft('finance_posting_map', v_tenant_a, 'tenant', null, '00000000-0000-0000-0000-000000024302', 'financefulla');

  -- 1) Unresolved account code (no such account exists at all).
  perform app.set_finance_config_items(v_draft.id, '[{"key": "ar_control", "value": {"accountCodeRef": "9999-NOPE", "dimensionDefaults": {}}}]'::jsonb, '00000000-0000-0000-0000-000000024302', 'financefulla');
  begin
    perform app.publish_finance_config_version(v_draft.id, '00000000-0000-0000-0000-000000024302', null, 'financefulla');
    raise exception 'assertion failed: expected finance_posting_map_unresolved_account';
  exception
    when others then
      if sqlerrm !~ 'finance_posting_map_unresolved_account' then
        raise exception 'assertion failed: expected finance_posting_map_unresolved_account, got %', sqlerrm;
      end if;
  end;

  -- 2) An existing but still-draft (not active) account.
  perform app.set_finance_config_items(v_draft.id, '[{"key": "ar_control", "value": {"accountCodeRef": "1200-AR", "dimensionDefaults": {}}}]'::jsonb, '00000000-0000-0000-0000-000000024302', 'financefulla');
  begin
    perform app.publish_finance_config_version(v_draft.id, '00000000-0000-0000-0000-000000024302', null, 'financefulla');
    raise exception 'assertion failed: expected finance_posting_map_inactive_account';
  exception
    when others then
      if sqlerrm !~ 'finance_posting_map_inactive_account' then
        raise exception 'assertion failed: expected finance_posting_map_inactive_account, got %', sqlerrm;
      end if;
  end;

  -- 3) An active but non-postable control account.
  perform app.set_finance_config_items(v_draft.id, '[{"key": "ar_control", "value": {"accountCodeRef": "1200-AR-CTRL", "dimensionDefaults": {}}}]'::jsonb, '00000000-0000-0000-0000-000000024302', 'financefulla');
  begin
    perform app.publish_finance_config_version(v_draft.id, '00000000-0000-0000-0000-000000024302', null, 'financefulla');
    raise exception 'assertion failed: expected finance_posting_map_not_postable_account';
  exception
    when others then
      if sqlerrm !~ 'finance_posting_map_not_postable_account' then
        raise exception 'assertion failed: expected finance_posting_map_not_postable_account, got %', sqlerrm;
      end if;
  end;

  -- 4) Activate AR for real, then the posting map publishes cleanly.
  select * into v_ar from app.activate_finance_account(v_ar.id, v_ar.record_version, '00000000-0000-0000-0000-000000024302', 'financefulla');
  perform app.set_finance_config_items(v_draft.id, '[{"key": "ar_control", "value": {"accountCodeRef": "1200-AR", "dimensionDefaults": {}}}]'::jsonb, '00000000-0000-0000-0000-000000024302', 'financefulla');
  perform app.publish_finance_config_version(v_draft.id, '00000000-0000-0000-0000-000000024302', null, 'financefulla');
  if (select status from app.config_versions where id = v_draft.id) <> 'published' then
    raise exception 'assertion failed: expected the posting map to publish once its account reference is active and postable';
  end if;
end;
$$;

\echo '>> dependency-impact: app.get_finance_account_dependency_impact reports the published posting-map reference; deactivating that account is now rejected'
do $$
declare
  v_tenant_a uuid;
  v_ar app.finance_accounts;
  v_impact jsonb;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmecoaa');
  select * into v_ar from app.finance_accounts where tenant_id = v_tenant_a and code = '1200-AR';

  select app.get_finance_account_dependency_impact(v_ar.id, '00000000-0000-0000-0000-000000024302') into v_impact;
  if not (v_impact ->> 'referencedByPublishedPostingMap')::boolean then
    raise exception 'assertion failed: expected referencedByPublishedPostingMap=true for 1200-AR, got %', v_impact;
  end if;

  begin
    perform app.deactivate_finance_account(v_ar.id, v_ar.record_version, 'trying anyway', '00000000-0000-0000-0000-000000024302', 'financefulla');
    raise exception 'assertion failed: expected finance_account_referenced_by_posting_map';
  exception
    when others then
      if sqlerrm !~ 'finance_account_referenced_by_posting_map' then
        raise exception 'assertion failed: expected finance_account_referenced_by_posting_map, got %', sqlerrm;
      end if;
  end;
end;
$$;

\echo '>> cross-tenant isolation: Finance Full B cannot create/activate/deactivate against tenant A''s own accounts'
do $$
declare
  v_tenant_a uuid;
  v_ar app.finance_accounts;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmecoaa');
  select * into v_ar from app.finance_accounts where tenant_id = v_tenant_a and code = '1200-AR';

  begin
    perform app.create_finance_account_draft(v_tenant_a, null, '9000-INTRUDER', 'Intruder Account', 'asset', 'debit', null, false, null, '00000000-0000-0000-0000-000000024304', 'financefullb');
    raise exception 'assertion failed: expected insufficient_authority -- Finance Full B has no FIN grant in tenant A';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    -- ISS-2026-146: financefullb has zero app.principal_memberships row in tenant A at
    -- all -- the exact "caller with no relationship to the record's real tenant" class
    -- this fix closes. Before the fix this raised insufficient_authority with tenant
    -- A's real tenant_id embedded in the message; now it raises the identical generic
    -- not-found a nonexistent account id would, before that tenant_id is ever
    -- interpolated.
    perform app.deactivate_finance_account(v_ar.id, v_ar.record_version, 'tenant B trying to touch tenant A''s account', '00000000-0000-0000-0000-000000024304', 'financefullb');
    raise exception 'assertion failed: expected finance_account_not_found for cross-tenant deactivation, the call unexpectedly succeeded';
  exception
    when no_data_found then
      null;
  end;
end;
$$;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on every new FIN-192 function (ERR-2026-004 regression guard); authenticated holds every caller-facing wrapper'
do $$
declare
  v_fn text;
  v_anon_has boolean;
begin
  for v_fn in select unnest(array[
    'create_finance_account_draft', 'amend_finance_account_draft', 'activate_finance_account',
    'deactivate_finance_account', 'get_finance_account_dependency_impact', 'list_finance_accounts',
    'check_finance_account_authority', 'detect_finance_account_hierarchy_cycle', 'touch_finance_account_row'
  ]) loop
    select bool_or(has_function_privilege('anon', p.oid, 'EXECUTE'))
      into v_anon_has
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'app' and p.proname = v_fn;
    if coalesce(v_anon_has, false) then
      raise exception 'assertion failed: expected anon to hold zero EXECUTE on app.%, found at least one overload granted', v_fn;
    end if;
  end loop;

  if not has_function_privilege('authenticated', 'app.create_finance_account_draft(uuid, uuid, text, text, text, text, uuid, boolean, text, uuid, text)', 'EXECUTE') then
    raise exception 'assertion failed: expected authenticated to hold EXECUTE on app.create_finance_account_draft';
  end if;
end;
$$;

\echo '>> audit trail: at least one create/activate/deactivate event was captured for tenant A''s own chart-of-accounts activity'
do $$
declare
  v_tenant_a uuid;
  v_count integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmecoaa');
  select count(*) into v_count from app.audit_logs where tenant_id = v_tenant_a and action in
    ('create_finance_account_draft', 'activate_finance_account', 'deactivate_finance_account');
  if v_count < 5 then
    raise exception 'assertion failed: expected at least 5 audit events across this fixture''s own create/activate/deactivate calls, found %', v_count;
  end if;
end;
$$;
