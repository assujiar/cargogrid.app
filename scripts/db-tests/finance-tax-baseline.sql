-- Real, executable test evidence for FIN-195 (Tax Baseline, CG-S9-FIN-006) --
-- run via `pnpm run db:test` against a real, disposable Postgres database.
-- Proves: the seeded tax-code catalogue never carries an approved rate; the
-- one seeded example fixture can never be approved
-- (finance_tax_rule_example_fixture_not_activatable); draft -> approved lifecycle
-- with a real evidence-required gate; authority split (Edit drafts, Approve
-- activates); approval overlap rejection; deterministic tenant-then-global
-- resolution; exact-decimal calculation with FIN-191's own rounding tie-in and
-- missing-rule rejection (never a silent zero/default); account-mapping
-- validation against FIN-192's own chart of accounts; cross-tenant isolation;
-- schema-privilege defense in depth; audit trail.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants; tenant A gets a Finance Manager (FIN:Edit/Approve/View, acting as the authorized SME approver), a Finance Editor (FIN:Edit/View only, no Approve), and a Plain User with no FIN grant; tenant B gets its own Finance Manager for cross-tenant checks'
do $$
declare
  v_tenant_a uuid;
  v_tenant_b uuid;
  v_team_a uuid;
  v_team_b uuid;
  v_manager_role_a uuid;
  v_manager_draft_a app.role_versions;
  v_editor_role_a uuid;
  v_editor_draft_a app.role_versions;
  v_manager_role_b uuid;
  v_manager_draft_b app.role_versions;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000025501', 'admina@acmetax.test'),
    ('00000000-0000-0000-0000-000000025502', 'financemanagera@acmetax.test'),
    ('00000000-0000-0000-0000-000000025503', 'financeeditora@acmetax.test'),
    ('00000000-0000-0000-0000-000000025504', 'plainusera@acmetax.test'),
    ('00000000-0000-0000-0000-000000025505', 'financemanagerb@acmetax.test'),
    ('00000000-0000-0000-0000-000000025506', 'supremetax@example.test');

  perform app.provision_tenant('acmetaxa', 'Acme Tax A', 'idem-acmetaxa', 'tester');
  v_tenant_a := (select id from app.tenants where slug = 'acmetaxa');
  perform app.transition_tenant_status(v_tenant_a, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_a, 'company', null, 'ACMETAXA-CO', 'Acme Tax A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant_a and code = 'ACMETAXA-CO');

  perform app.provision_tenant('acmetaxb', 'Acme Tax B', 'idem-acmetaxb', 'tester');
  v_tenant_b := (select id from app.tenants where slug = 'acmetaxb');
  perform app.transition_tenant_status(v_tenant_b, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_b, 'company', null, 'ACMETAXB-CO', 'Acme Tax B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant_b and code = 'ACMETAXB-CO');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000025501', 'admina@acmetax.test', 'Tenant A Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admina@acmetax.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000025501', 'tenant_admin', v_tenant_a, null, 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000025502', 'financemanagera@acmetax.test', 'Finance Manager A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financemanagera@acmetax.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000025502', 'tenant_admin', v_tenant_a, null, 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000025503', 'financeeditora@acmetax.test', 'Finance Editor A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financeeditora@acmetax.test'), 'active', 'onboarded', 'tester');

  v_manager_role_a := (app.create_role(v_tenant_a, 'Finance Manager', 'tax authority', 'tester')).id;
  v_manager_draft_a := app.create_role_version(v_manager_role_a, 'tester');
  perform app.set_role_version_permissions(v_manager_draft_a.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'View')), 'tester');
  perform app.publish_role_version(v_manager_draft_a.id, now(), 'tester');
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_manager_role_a and status = 'published'), '00000000-0000-0000-0000-000000025502', '00000000-0000-0000-0000-000000025501', 'tester');

  v_editor_role_a := (app.create_role(v_tenant_a, 'Finance Editor', 'draft only, no approve', 'tester')).id;
  v_editor_draft_a := app.create_role_version(v_editor_role_a, 'tester');
  perform app.set_role_version_permissions(v_editor_draft_a.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Edit', 'View')), 'tester');
  perform app.publish_role_version(v_editor_draft_a.id, now(), 'tester');
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_editor_role_a and status = 'published'), '00000000-0000-0000-0000-000000025503', '00000000-0000-0000-0000-000000025501', 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000025504', 'plainusera@acmetax.test', 'Plain User A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'plainusera@acmetax.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant_b, '00000000-0000-0000-0000-000000025505', 'financemanagerb@acmetax.test', 'Finance Manager B', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financemanagerb@acmetax.test'), 'active', 'onboarded', 'tester');
  v_manager_role_b := (app.create_role(v_tenant_b, 'Finance Manager', 'tax authority', 'tester')).id;
  v_manager_draft_b := app.create_role_version(v_manager_role_b, 'tester');
  perform app.set_role_version_permissions(v_manager_draft_b.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'View')), 'tester');
  perform app.publish_role_version(v_manager_draft_b.id, now(), 'tester');
  perform app.assign_role(v_tenant_b, (select id from app.role_versions where role_id = v_manager_role_b and status = 'published'), '00000000-0000-0000-0000-000000025505', '00000000-0000-0000-0000-000000025505', 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000025506', 'supreme_admin', null, null, 'tester');
end;
$$;

\echo '>> setup: an active, postable finance_accounts row for tenant A (FIN-192), used as this fixture''s own tax output-account mapping'
do $$
declare
  v_tenant_a uuid;
  v_account app.finance_accounts;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmetaxa');
  select * into v_account from app.create_finance_account_draft(v_tenant_a, null, 'PPN-OUT-2000', 'PPN Output Tax Payable', 'liability', 'credit', null, false, null, '00000000-0000-0000-0000-000000025502', 'financemanagera');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000025502', 'financemanagera');
end;
$$;

\echo '>> seed integrity: the seeded example fixture is structurally inert (rate_value = 0, is_example_fixture = true, draft) and is never approved -- checked directly, not via a whole-database "zero approved" count (which would be a false invariant once any other fixture legitimately approves its own tenant-scoped, evidence-backed rule, e.g. FIN-197''s own db-test)'
do $$
declare
  v_fixture app.finance_tax_rule_versions;
begin
  select * into v_fixture from app.finance_tax_rule_versions where is_example_fixture;
  if not found or v_fixture.rate_value <> 0 or v_fixture.status <> 'draft' then
    raise exception 'assertion failed: expected exactly one seeded example fixture, draft, rate_value 0';
  end if;

  if exists (select 1 from app.finance_tax_rule_versions where tenant_id is null and status = 'approved') then
    raise exception 'assertion failed: expected zero platform-wide-default (tenant_id null) tax rule to ever be approved by any seed or fixture in this suite';
  end if;

  begin
    perform app.approve_finance_tax_rule(v_fixture.id, v_fixture.record_version, '00000000-0000-0000-0000-000000025506', 'supremetax');
    raise exception 'assertion failed: expected finance_tax_rule_example_fixture_not_activatable for the seeded fixture';
  exception
    when others then
      if sqlerrm !~ 'finance_tax_rule_example_fixture_not_activatable' then
        raise exception 'assertion failed: expected finance_tax_rule_example_fixture_not_activatable, got %', sqlerrm;
      end if;
  end;
end;
$$;

\echo '>> authority + structural validation: Plain User A is denied draft creation; an inactive/unknown tax code, unsupported basis, and invalid account mapping are each rejected; Finance Manager A creates a valid PPN draft with an account mapping'
do $$
declare
  v_tenant_a uuid;
  v_ppn_code_id uuid;
  v_account_id uuid;
  v_rule app.finance_tax_rule_versions;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmetaxa');
  v_ppn_code_id := (select id from app.finance_tax_codes where tenant_id is null and code = 'PPN');
  v_account_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'PPN-OUT-2000');

  begin
    perform app.create_finance_tax_rule_draft(v_tenant_a, v_ppn_code_id, 'percentage', 0.11, null, null, null, '2026-01-01'::date, null, '00000000-0000-0000-0000-000000025504', 'plainusera');
    raise exception 'assertion failed: expected insufficient_authority for Plain User A';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.create_finance_tax_rule_draft(v_tenant_a, gen_random_uuid(), 'percentage', 0.11, null, null, null, '2026-01-01'::date, null, '00000000-0000-0000-0000-000000025502', 'financemanagera');
    raise exception 'assertion failed: expected finance_tax_rule_unsupported_code for an unknown tax code id';
  exception
    when others then
      if sqlerrm !~ 'finance_tax_rule_unsupported_code' then
        raise exception 'assertion failed: expected finance_tax_rule_unsupported_code, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.create_finance_tax_rule_draft(v_tenant_a, v_ppn_code_id, 'formula', 0.11, null, null, null, '2026-01-01'::date, null, '00000000-0000-0000-0000-000000025502', 'financemanagera');
    raise exception 'assertion failed: expected finance_tax_rule_unsupported_basis for a formula basis';
  exception
    when others then
      if sqlerrm !~ 'finance_tax_rule_unsupported_basis' then
        raise exception 'assertion failed: expected finance_tax_rule_unsupported_basis, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.create_finance_tax_rule_draft(v_tenant_a, v_ppn_code_id, 'percentage', 0.11, null, gen_random_uuid(), null, '2026-01-01'::date, null, '00000000-0000-0000-0000-000000025502', 'financemanagera');
    raise exception 'assertion failed: expected finance_tax_rule_invalid_account_mapping for an unknown output account';
  exception
    when others then
      if sqlerrm !~ 'finance_tax_rule_invalid_account_mapping' then
        raise exception 'assertion failed: expected finance_tax_rule_invalid_account_mapping, got %', sqlerrm;
      end if;
  end;

  select * into v_rule from app.create_finance_tax_rule_draft(v_tenant_a, v_ppn_code_id, 'percentage', 0.11, null, v_account_id, null, '2026-01-01'::date, null, '00000000-0000-0000-0000-000000025502', 'financemanagera');
  if v_rule.status <> 'draft' or v_rule.rate_value <> 0.11 then
    raise exception 'assertion failed: expected a draft PPN rule at 0.11, got % / %', v_rule.status, v_rule.rate_value;
  end if;
end;
$$;

\echo '>> evidence-gated approval: approval is rejected with no evidence attached; Finance Editor A (no Approve) is denied; attaching evidence then approving as Finance Manager A succeeds'
do $$
declare
  v_tenant_a uuid;
  v_rule app.finance_tax_rule_versions;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmetaxa');
  select * into v_rule from app.finance_tax_rule_versions where tenant_id = v_tenant_a and status = 'draft' and rate_value = 0.11;

  begin
    perform app.approve_finance_tax_rule(v_rule.id, v_rule.record_version, '00000000-0000-0000-0000-000000025502', 'financemanagera');
    raise exception 'assertion failed: expected finance_tax_rule_evidence_missing before any evidence is attached';
  exception
    when others then
      if sqlerrm !~ 'finance_tax_rule_evidence_missing' then
        raise exception 'assertion failed: expected finance_tax_rule_evidence_missing, got %', sqlerrm;
      end if;
  end;

  select * into v_rule from app.attach_finance_tax_rule_evidence(v_rule.id, v_rule.record_version, null, 'PMK regulation reference and effective SME sign-off memo, tester fixture.', '00000000-0000-0000-0000-000000025502', 'financemanagera');

  begin
    perform app.approve_finance_tax_rule(v_rule.id, v_rule.record_version, '00000000-0000-0000-0000-000000025503', 'financeeditora');
    raise exception 'assertion failed: expected insufficient_authority -- Finance Editor A lacks FIN:Approve';
  exception
    when insufficient_privilege then
      null;
  end;

  select * into v_rule from app.approve_finance_tax_rule(v_rule.id, v_rule.record_version, '00000000-0000-0000-0000-000000025502', 'financemanagera');
  if v_rule.status <> 'approved' or v_rule.approved_by <> 'financemanagera' then
    raise exception 'assertion failed: expected the PPN draft to approve under Finance Manager A''s own SME authority';
  end if;
end;
$$;

\echo '>> approval overlap rejection: a second draft covering the same tax code/scope/window cannot be approved over an already-approved one'
do $$
declare
  v_tenant_a uuid;
  v_ppn_code_id uuid;
  v_account_id uuid;
  v_overlap app.finance_tax_rule_versions;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmetaxa');
  v_ppn_code_id := (select id from app.finance_tax_codes where tenant_id is null and code = 'PPN');
  v_account_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'PPN-OUT-2000');

  select * into v_overlap from app.create_finance_tax_rule_draft(v_tenant_a, v_ppn_code_id, 'percentage', 0.12, null, v_account_id, null, '2026-06-01'::date, null, '00000000-0000-0000-0000-000000025502', 'financemanagera');
  select * into v_overlap from app.attach_finance_tax_rule_evidence(v_overlap.id, v_overlap.record_version, null, 'overlap test fixture evidence note', '00000000-0000-0000-0000-000000025502', 'financemanagera');

  begin
    perform app.approve_finance_tax_rule(v_overlap.id, v_overlap.record_version, '00000000-0000-0000-0000-000000025502', 'financemanagera');
    raise exception 'assertion failed: expected finance_tax_rule_overlap';
  exception
    when others then
      if sqlerrm !~ 'finance_tax_rule_overlap' then
        raise exception 'assertion failed: expected finance_tax_rule_overlap, got %', sqlerrm;
      end if;
  end;

  perform app.discard_finance_tax_rule_draft(v_overlap.id, v_overlap.record_version, 'superseded, no real second window in this fixture', '00000000-0000-0000-0000-000000025502', 'financemanagera');
end;
$$;

\echo '>> deterministic resolution: the approved PPN rule resolves for a covered date; zero rows for an uncovered date or an unrelated code'
do $$
declare
  v_tenant_a uuid;
  v_resolved app.finance_tax_rule_versions;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmetaxa');

  select * into v_resolved from app.resolve_finance_tax_rule(v_tenant_a, 'PPN', '2026-03-01'::date);
  if not found or v_resolved.rate_value <> 0.11 then
    raise exception 'assertion failed: expected the approved PPN rule (0.11) to resolve for 2026-03-01, got %', v_resolved.rate_value;
  end if;

  if exists (select 1 from app.resolve_finance_tax_rule(v_tenant_a, 'PPN', '2025-01-01'::date)) then
    raise exception 'assertion failed: expected zero rows for a date before the rule''s own effective_from';
  end if;

  if exists (select 1 from app.resolve_finance_tax_rule(v_tenant_a, 'PPH23', '2026-03-01'::date)) then
    raise exception 'assertion failed: expected zero rows for a tax code with no approved rule at all';
  end if;
end;
$$;

\echo '>> exact-decimal calculation: 1,000,000.00 base at the approved PPN rate rounds to the disclosed safe default (round_half_up, 2dp); FIN-191''s own published tax_calculation rounding override is honoured; an unresolvable tax code is rejected, never silently zero'
do $$
declare
  v_tenant_a uuid;
  v_result jsonb;
  v_draft app.config_versions;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmetaxa');

  select app.calculate_finance_tax(v_tenant_a, 'PPN', 1000000, '2026-03-01'::date, '00000000-0000-0000-0000-000000025502') into v_result;
  if (v_result ->> 'taxAmount')::numeric <> 110000.00 then
    raise exception 'assertion failed: expected 1,000,000 * 0.11 = 110000.00, got %', v_result;
  end if;

  select * into v_draft from app.create_finance_config_draft('finance_rounding', v_tenant_a, 'tenant', null, '00000000-0000-0000-0000-000000025502', 'financemanagera');
  perform app.set_finance_config_items(
    v_draft.id,
    '[{"key": "tax_calculation", "value": {"mode": "round_up", "precision": 0, "order": "convert_then_round"}}]'::jsonb,
    '00000000-0000-0000-0000-000000025502', 'financemanagera'
  );
  perform app.publish_finance_config_version(v_draft.id, '00000000-0000-0000-0000-000000025502', null, 'financemanagera');

  select app.calculate_finance_tax(v_tenant_a, 'PPN', 1000001, '2026-03-01'::date, '00000000-0000-0000-0000-000000025502') into v_result;
  if (v_result ->> 'taxAmount')::numeric <> 110001 or (v_result ->> 'roundingMode') <> 'round_up' then
    raise exception 'assertion failed: expected FIN-191''s own published tax_calculation rounding (round_up, precision 0) to apply, got %', v_result;
  end if;

  begin
    perform app.calculate_finance_tax(v_tenant_a, 'PPH23', 500000, '2026-03-01'::date, '00000000-0000-0000-0000-000000025502');
    raise exception 'assertion failed: expected finance_tax_rule_missing -- never a silent zero/default tax amount';
  exception
    when others then
      if sqlerrm !~ 'finance_tax_rule_missing' then
        raise exception 'assertion failed: expected finance_tax_rule_missing, got %', sqlerrm;
      end if;
  end;
end;
$$;

\echo '>> cross-tenant isolation: Finance Manager B cannot mutate tenant A''s own approved rule, and list_finance_tax_rule_versions never returns tenant A''s rows for tenant B''s own scope'
do $$
declare
  v_tenant_a uuid;
  v_tenant_b uuid;
  v_rule app.finance_tax_rule_versions;
  v_rows app.finance_tax_rule_versions[];
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmetaxa');
  v_tenant_b := (select id from app.tenants where slug = 'acmetaxb');
  select * into v_rule from app.finance_tax_rule_versions where tenant_id = v_tenant_a and status = 'approved';

  begin
    -- ISS-2026-146: financemanagerb has zero app.principal_memberships row in tenant A
    -- at all, so app.discard_finance_tax_rule_draft's tenant-membership pre-check now
    -- refuses with the same generic not-found a nonexistent rule id would, rather than
    -- disclosing tenant A's real tenant_id via insufficient_authority.
    perform app.discard_finance_tax_rule_draft(v_rule.id, v_rule.record_version, 'intruder attempt', '00000000-0000-0000-0000-000000025505', 'financemanagerb');
    raise exception 'assertion failed: expected finance_tax_rule_not_found for a caller with zero relationship to tenant A, the call unexpectedly succeeded';
  exception
    when no_data_found then
      null;
  end;

  select array_agg(r) into v_rows from app.list_finance_tax_rule_versions(v_tenant_b, null, '00000000-0000-0000-0000-000000025505') r;
  if v_rows is not null and exists (select 1 from unnest(v_rows) r where r.tenant_id = v_tenant_a) then
    raise exception 'assertion failed: expected tenant B''s own list_finance_tax_rule_versions to never return a tenant A row';
  end if;
end;
$$;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on every new FIN-195 function (ERR-2026-004 regression guard)'
do $$
declare
  v_fn text;
  v_anon_has boolean;
begin
  for v_fn in select unnest(array[
    'touch_finance_tax_rule_version_row', 'check_finance_tax_authority', 'create_finance_tax_rule_draft',
    'attach_finance_tax_rule_evidence', 'discard_finance_tax_rule_draft', 'approve_finance_tax_rule',
    'resolve_finance_tax_rule', 'calculate_finance_tax', 'list_finance_tax_codes', 'list_finance_tax_rule_versions'
  ]) loop
    select bool_or(has_function_privilege('anon', p.oid, 'EXECUTE'))
      into v_anon_has
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'app' and p.proname = v_fn;
    if coalesce(v_anon_has, false) then
      raise exception 'assertion failed: expected anon to hold zero EXECUTE on app.%, found at least one overload granted', v_fn;
    end if;
  end loop;
end;
$$;

\echo '>> audit trail: at least one create/approve event was captured for tenant A''s own tax-rule activity'
do $$
declare
  v_tenant_a uuid;
  v_count integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmetaxa');
  select count(*) into v_count from app.audit_logs where tenant_id = v_tenant_a and action in
    ('create_finance_tax_rule_draft', 'approve_finance_tax_rule');
  if v_count < 2 then
    raise exception 'assertion failed: expected at least 2 audit events across this fixture''s own create/approve calls, found %', v_count;
  end if;
end;
$$;
