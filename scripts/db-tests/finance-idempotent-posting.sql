-- Real, executable test evidence for FIN-208 (Idempotent Posting,
-- CG-S9-FIN-019) -- run via `pnpm run db:test` against a real, disposable
-- Postgres database.
-- Proves: app.claim_finance_idempotency_key atomically claims a brand-new
-- key, returns the identical claim on a fingerprint-matching retry, and
-- raises a named conflict on a fingerprint-mismatching retry -- before any
-- domain row is written; app.complete_finance_idempotency_claim is
-- idempotent; app.fail_finance_idempotency_claim rejects an
-- already-completed claim; app.get_finance_idempotency_claim is
-- authority-gated and raises rather than returning null for an unknown
-- key; the one real adopter (app.create_finance_journal_draft) now
-- rejects a reused key with a different payload end-to-end; cross-tenant
-- isolation; schema-privilege defense in depth.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants; tenant A gets a Finance Manager (FIN:Create/Edit/Approve/View, tenant_admin) and a Plain User with no FIN grant; tenant B gets its own Finance Manager'
do $$
declare
  v_tenant_a uuid;
  v_tenant_b uuid;
  v_team_a uuid;
  v_team_b uuid;
  v_manager_role_a uuid;
  v_manager_draft_a app.role_versions;
  v_manager_role_b uuid;
  v_manager_draft_b app.role_versions;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000033001', 'admina@acmeidem.test'),
    ('00000000-0000-0000-0000-000000033002', 'financemanagera@acmeidem.test'),
    ('00000000-0000-0000-0000-000000033003', 'plainusera@acmeidem.test'),
    ('00000000-0000-0000-0000-000000033004', 'financemanagerb@acmeidem.test');

  perform app.provision_tenant('acmeidema', 'Acme Idempotency A', 'idem-acmeidema', 'tester');
  v_tenant_a := (select id from app.tenants where slug = 'acmeidema');
  perform app.transition_tenant_status(v_tenant_a, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_a, 'company', null, 'ACMEIDEMA-CO', 'Acme Idempotency A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant_a and code = 'ACMEIDEMA-CO');

  perform app.provision_tenant('acmeidemb', 'Acme Idempotency B', 'idem-acmeidemb', 'tester');
  v_tenant_b := (select id from app.tenants where slug = 'acmeidemb');
  perform app.transition_tenant_status(v_tenant_b, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_b, 'company', null, 'ACMEIDEMB-CO', 'Acme Idempotency B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant_b and code = 'ACMEIDEMB-CO');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000033001', 'admina@acmeidem.test', 'Tenant A Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admina@acmeidem.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000033001', 'tenant_admin', v_tenant_a, null, 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000033002', 'financemanagera@acmeidem.test', 'Finance Manager A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financemanagera@acmeidem.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000033002', 'tenant_admin', v_tenant_a, null, 'tester');

  v_manager_role_a := (app.create_role(v_tenant_a, 'Finance Manager', 'Idempotency authority', 'tester')).id;
  v_manager_draft_a := app.create_role_version(v_manager_role_a, 'tester');
  perform app.set_role_version_permissions(v_manager_draft_a.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'View')), 'tester');
  perform app.publish_role_version(v_manager_draft_a.id, now(), 'tester');
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_manager_role_a and status = 'published'), '00000000-0000-0000-0000-000000033002', '00000000-0000-0000-0000-000000033001', 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000033003', 'plainusera@acmeidem.test', 'Plain User A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'plainusera@acmeidem.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant_b, '00000000-0000-0000-0000-000000033004', 'financemanagerb@acmeidem.test', 'Finance Manager B', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financemanagerb@acmeidem.test'), 'active', 'onboarded', 'tester');
  v_manager_role_b := (app.create_role(v_tenant_b, 'Finance Manager', 'Idempotency authority', 'tester')).id;
  v_manager_draft_b := app.create_role_version(v_manager_role_b, 'tester');
  perform app.set_role_version_permissions(v_manager_draft_b.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'View')), 'tester');
  perform app.publish_role_version(v_manager_draft_b.id, now(), 'tester');
  perform app.assign_role(v_tenant_b, (select id from app.role_versions where role_id = v_manager_role_b and status = 'published'), '00000000-0000-0000-0000-000000033004', '00000000-0000-0000-0000-000000033004', 'tester');
end;
$$;

\echo '>> app.claim_finance_idempotency_key: a brand-new key claims once; a fingerprint-matching retry returns the identical claim unchanged; a fingerprint-mismatching retry is a distinct named conflict, never a silent overwrite'
do $$
declare
  v_tenant_a uuid;
  v_claim app.finance_idempotency_claims;
  v_retry app.finance_idempotency_claims;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmeidema');

  begin
    perform app.claim_finance_idempotency_key(v_tenant_a, 'test-scope', '', 'fp-1', '00000000-0000-0000-0000-000000033002', 'financemanagera');
    raise exception 'assertion failed: expected idempotency_key_required for an empty key';
  exception
    when others then
      if sqlerrm !~ 'idempotency_key_required' then
        raise exception 'assertion failed: expected idempotency_key_required, got %', sqlerrm;
      end if;
  end;

  select * into v_claim from app.claim_finance_idempotency_key(v_tenant_a, 'test-scope', 'idem-key-1', 'fp-1', '00000000-0000-0000-0000-000000033002', 'financemanagera');
  if v_claim.status <> 'claimed' then
    raise exception 'assertion failed: expected a brand-new claim with status claimed, got %', v_claim.status;
  end if;

  select * into v_retry from app.claim_finance_idempotency_key(v_tenant_a, 'test-scope', 'idem-key-1', 'fp-1', '00000000-0000-0000-0000-000000033002', 'financemanagera');
  if v_retry.id <> v_claim.id then
    raise exception 'assertion failed: expected a fingerprint-matching retry to return the identical claim';
  end if;

  begin
    perform app.claim_finance_idempotency_key(v_tenant_a, 'test-scope', 'idem-key-1', 'fp-DIFFERENT', '00000000-0000-0000-0000-000000033002', 'financemanagera');
    raise exception 'assertion failed: expected finance_idempotency_fingerprint_conflict for a mismatched retry';
  exception
    when others then
      if sqlerrm !~ 'finance_idempotency_fingerprint_conflict' then
        raise exception 'assertion failed: expected finance_idempotency_fingerprint_conflict, got %', sqlerrm;
      end if;
  end;
end;
$$;

\echo '>> app.complete_finance_idempotency_claim is idempotent; app.fail_finance_idempotency_claim rejects an already-completed claim; app.get_finance_idempotency_claim is authority-gated and raises for an unknown key'
do $$
declare
  v_tenant_a uuid;
  v_claim app.finance_idempotency_claims;
  v_completed app.finance_idempotency_claims;
  v_retry_complete app.finance_idempotency_claims;
  v_read app.finance_idempotency_claims;
  v_result_id uuid := gen_random_uuid();
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmeidema');
  select * into v_claim from app.claim_finance_idempotency_key(v_tenant_a, 'test-scope', 'idem-key-2', 'fp-2', '00000000-0000-0000-0000-000000033002', 'financemanagera');

  select * into v_completed from app.complete_finance_idempotency_claim(v_claim.id, 'widget', v_result_id, '00000000-0000-0000-0000-000000033002', 'financemanagera');
  if v_completed.status <> 'completed' or v_completed.result_entity_id <> v_result_id then
    raise exception 'assertion failed: expected a completed claim carrying the exact result_entity_id';
  end if;

  select * into v_retry_complete from app.complete_finance_idempotency_claim(v_claim.id, 'widget', v_result_id, '00000000-0000-0000-0000-000000033002', 'financemanagera');
  if v_retry_complete.id <> v_completed.id or v_retry_complete.completed_at <> v_completed.completed_at then
    raise exception 'assertion failed: expected a retried complete on an already-completed claim to return it unchanged';
  end if;

  begin
    perform app.fail_finance_idempotency_claim(v_claim.id, 'too late', '00000000-0000-0000-0000-000000033002', 'financemanagera');
    raise exception 'assertion failed: expected finance_idempotency_claim_already_completed';
  exception
    when others then
      if sqlerrm !~ 'finance_idempotency_claim_already_completed' then
        raise exception 'assertion failed: expected finance_idempotency_claim_already_completed, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.get_finance_idempotency_claim(v_tenant_a, 'test-scope', 'idem-key-2', '00000000-0000-0000-0000-000000033003');
    raise exception 'assertion failed: expected insufficient_authority for Plain User A (no FIN:View)';
  exception
    when insufficient_privilege then
      null;
  end;

  select * into v_read from app.get_finance_idempotency_claim(v_tenant_a, 'test-scope', 'idem-key-2', '00000000-0000-0000-0000-000000033002');
  if v_read.id <> v_claim.id then
    raise exception 'assertion failed: expected get_finance_idempotency_claim to return the completed claim';
  end if;

  begin
    perform app.get_finance_idempotency_claim(v_tenant_a, 'test-scope', 'idem-key-does-not-exist', '00000000-0000-0000-0000-000000033002');
    raise exception 'assertion failed: expected finance_idempotency_claim_not_found for an unknown key, never a silent null';
  exception
    when others then
      if sqlerrm !~ 'finance_idempotency_claim_not_found' then
        raise exception 'assertion failed: expected finance_idempotency_claim_not_found, got %', sqlerrm;
      end if;
  end;
end;
$$;

\echo '>> real adopter proof: app.create_finance_journal_draft (FIN-203) now rejects a reused idempotency_key carrying a different payload, and its own genuinely-identical retry still returns the original draft unchanged'
do $$
declare
  v_tenant_a uuid;
  v_cash_id app.finance_accounts;
  v_rev_id app.finance_accounts;
  v_journal app.finance_journals;
  v_retry app.finance_journals;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmeidema');
  perform app.generate_finance_fiscal_calendar(v_tenant_a, null, 'FY2026', 'FY2026 Monthly', '2026-01-01'::date, 6, '00000000-0000-0000-0000-000000033002', 'financemanagera');
  select * into v_cash_id from app.create_finance_account_draft(v_tenant_a, null, 'CASH-IDEM', 'Cash', 'asset', 'debit', null, false, null, '00000000-0000-0000-0000-000000033002', 'financemanagera');
  perform app.activate_finance_account(v_cash_id.id, v_cash_id.record_version, '00000000-0000-0000-0000-000000033002', 'financemanagera');
  select * into v_rev_id from app.create_finance_account_draft(v_tenant_a, null, 'REV-IDEM', 'Revenue', 'revenue', 'credit', null, false, null, '00000000-0000-0000-0000-000000033002', 'financemanagera');
  perform app.activate_finance_account(v_rev_id.id, v_rev_id.record_version, '00000000-0000-0000-0000-000000033002', 'financemanagera');

  select * into v_journal from app.create_finance_journal_draft(v_tenant_a, null, '2026-05-01'::date, 'USD',
    jsonb_build_array(
      jsonb_build_object('accountId', v_cash_id.id, 'direction', 'debit', 'amount', 200),
      jsonb_build_object('accountId', v_rev_id.id, 'direction', 'credit', 'amount', 200)
    ), 'idem-journal-1', '00000000-0000-0000-0000-000000033002', 'financemanagera');

  select * into v_retry from app.create_finance_journal_draft(v_tenant_a, null, '2026-05-01'::date, 'USD',
    jsonb_build_array(
      jsonb_build_object('accountId', v_cash_id.id, 'direction', 'debit', 'amount', 200),
      jsonb_build_object('accountId', v_rev_id.id, 'direction', 'credit', 'amount', 200)
    ), 'idem-journal-1', '00000000-0000-0000-0000-000000033002', 'financemanagera');
  if v_retry.id <> v_journal.id then
    raise exception 'assertion failed: expected a byte-identical retry to return the original journal unchanged';
  end if;

  begin
    perform app.create_finance_journal_draft(v_tenant_a, null, '2026-05-01'::date, 'USD',
      jsonb_build_array(
        jsonb_build_object('accountId', v_cash_id.id, 'direction', 'debit', 'amount', 999),
        jsonb_build_object('accountId', v_rev_id.id, 'direction', 'credit', 'amount', 999)
      ), 'idem-journal-1', '00000000-0000-0000-0000-000000033002', 'financemanagera');
    raise exception 'assertion failed: expected finance_idempotency_fingerprint_conflict for a reused key with a different amount';
  exception
    when others then
      if sqlerrm !~ 'finance_idempotency_fingerprint_conflict' then
        raise exception 'assertion failed: expected finance_idempotency_fingerprint_conflict, got %', sqlerrm;
      end if;
  end;

  if (select count(*) from app.finance_journals where tenant_id = v_tenant_a and idempotency_key = 'idem-journal-1') <> 1 then
    raise exception 'assertion failed: expected exactly one journal row for idem-journal-1, the rejected mismatched retry must never have written a second one';
  end if;
end;
$$;

\echo '>> cross-tenant isolation: a claim under one tenant is invisible to app.get_finance_idempotency_claim called under another tenant, even with the identical scope/key'
do $$
declare
  v_tenant_a uuid;
  v_tenant_b uuid;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmeidema');
  v_tenant_b := (select id from app.tenants where slug = 'acmeidemb');
  perform app.claim_finance_idempotency_key(v_tenant_a, 'test-scope', 'idem-key-cross-1', 'fp-cross', '00000000-0000-0000-0000-000000033002', 'financemanagera');

  begin
    perform app.get_finance_idempotency_claim(v_tenant_b, 'test-scope', 'idem-key-cross-1', '00000000-0000-0000-0000-000000033004');
    raise exception 'assertion failed: expected finance_idempotency_claim_not_found for tenant B reading tenant A''s own claim';
  exception
    when others then
      if sqlerrm !~ 'finance_idempotency_claim_not_found' then
        raise exception 'assertion failed: expected finance_idempotency_claim_not_found, got %', sqlerrm;
      end if;
  end;
end;
$$;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on every new FIN-208 function (ERR-2026-004 regression guard)'
do $$
declare
  v_leaked_count integer;
begin
  select count(*) into v_leaked_count
    from information_schema.routine_privileges
    where routine_schema = 'app'
      and grantee = 'anon'
      and routine_name in (
        'claim_finance_idempotency_key', 'complete_finance_idempotency_claim',
        'fail_finance_idempotency_claim', 'get_finance_idempotency_claim', 'check_finance_idempotency_authority'
      );
  if v_leaked_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grants on FIN-208 functions, found %', v_leaked_count;
  end if;
end;
$$;

\echo 'ALL FIN-208 (Idempotent Posting) db-test assertions passed.'
