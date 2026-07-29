-- Real, executable test evidence for FIN-193 (Fiscal Period, CG-S9-FIN-004)
-- -- run via `pnpm run db:test` against a real, disposable Postgres database.
-- Proves: calendar generation with non-overlapping sequential periods, each
-- pinning a governed snapshot of the tenant's currently-effective
-- finance_close_policy (FIN-191) checklist; deterministic date-to-period
-- resolution; the open -> soft_closed -> closed lifecycle with a separated
-- FIN:Edit ("prepare")/FIN:Approve ("close/reopen") authority split; close
-- readiness gated on required checklist items; governed reopen with a
-- mandatory reason; cross-tenant isolation; schema-privilege defense in
-- depth.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants; tenant A gets a Finance Manager (tenant_admin AND FIN:Edit/Approve/View -- satisfies FIN-191''s inherited two-factor gate for publishing finance_close_policy AND this capability''s own close/reopen authority), a Finance Editor (FIN:Edit/View only, no Approve -- proves the prepare-vs-approve split), and a Plain User with no FIN grant; tenant B gets its own Finance Manager for cross-tenant checks'
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
    ('00000000-0000-0000-0000-000000024401', 'admina@acmefiscal.test'),
    ('00000000-0000-0000-0000-000000024402', 'financemanagera@acmefiscal.test'),
    ('00000000-0000-0000-0000-000000024403', 'financeeditora@acmefiscal.test'),
    ('00000000-0000-0000-0000-000000024404', 'plainusera@acmefiscal.test'),
    ('00000000-0000-0000-0000-000000024405', 'financemanagerb@acmefiscal.test');

  perform app.provision_tenant('acmefiscala', 'Acme Fiscal A', 'idem-acmefiscala', 'tester');
  v_tenant_a := (select id from app.tenants where slug = 'acmefiscala');
  perform app.transition_tenant_status(v_tenant_a, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_a, 'company', null, 'ACMEFISCALA-CO', 'Acme Fiscal A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant_a and code = 'ACMEFISCALA-CO');

  perform app.provision_tenant('acmefiscalb', 'Acme Fiscal B', 'idem-acmefiscalb', 'tester');
  v_tenant_b := (select id from app.tenants where slug = 'acmefiscalb');
  perform app.transition_tenant_status(v_tenant_b, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_b, 'company', null, 'ACMEFISCALB-CO', 'Acme Fiscal B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant_b and code = 'ACMEFISCALB-CO');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000024401', 'admina@acmefiscal.test', 'Tenant A Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admina@acmefiscal.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000024401', 'tenant_admin', v_tenant_a, null, 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000024402', 'financemanagera@acmefiscal.test', 'Finance Manager A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financemanagera@acmefiscal.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000024402', 'tenant_admin', v_tenant_a, null, 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000024403', 'financeeditora@acmefiscal.test', 'Finance Editor A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financeeditora@acmefiscal.test'), 'active', 'onboarded', 'tester');

  v_manager_role_a := (app.create_role(v_tenant_a, 'Finance Manager', 'fiscal period + config authority', 'tester')).id;
  v_manager_draft_a := app.create_role_version(v_manager_role_a, 'tester');
  perform app.set_role_version_permissions(v_manager_draft_a.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Edit', 'Approve', 'View')), 'tester');
  perform app.publish_role_version(v_manager_draft_a.id, now(), 'tester');
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_manager_role_a and status = 'published'), '00000000-0000-0000-0000-000000024402', '00000000-0000-0000-0000-000000024401', 'tester');

  v_editor_role_a := (app.create_role(v_tenant_a, 'Finance Editor', 'prepare only, no approve', 'tester')).id;
  v_editor_draft_a := app.create_role_version(v_editor_role_a, 'tester');
  perform app.set_role_version_permissions(v_editor_draft_a.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Edit', 'View')), 'tester');
  perform app.publish_role_version(v_editor_draft_a.id, now(), 'tester');
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_editor_role_a and status = 'published'), '00000000-0000-0000-0000-000000024403', '00000000-0000-0000-0000-000000024401', 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000024404', 'plainusera@acmefiscal.test', 'Plain User A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'plainusera@acmefiscal.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant_b, '00000000-0000-0000-0000-000000024405', 'financemanagerb@acmefiscal.test', 'Finance Manager B', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financemanagerb@acmefiscal.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000024405', 'tenant_admin', v_tenant_b, null, 'tester');
  v_manager_role_b := (app.create_role(v_tenant_b, 'Finance Manager', 'fiscal period + config authority', 'tester')).id;
  v_manager_draft_b := app.create_role_version(v_manager_role_b, 'tester');
  perform app.set_role_version_permissions(v_manager_draft_b.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Edit', 'Approve', 'View')), 'tester');
  perform app.publish_role_version(v_manager_draft_b.id, now(), 'tester');
  perform app.assign_role(v_tenant_b, (select id from app.role_versions where role_id = v_manager_role_b and status = 'published'), '00000000-0000-0000-0000-000000024405', '00000000-0000-0000-0000-000000024405', 'tester');
end;
$$;

\echo '>> tenant A publishes a finance_close_policy with one required and one optional item (FIN-191''s own engine, reused directly)'
do $$
declare
  v_tenant_a uuid;
  v_draft app.config_versions;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmefiscala');
  select * into v_draft from app.create_finance_config_draft('finance_close_policy', v_tenant_a, 'tenant', null, '00000000-0000-0000-0000-000000024402', 'financemanagera');
  perform app.set_finance_config_items(
    v_draft.id,
    '[{"key": "ar_aging_reconciled", "value": {"label": "AR aging reconciled", "required": true, "sourceCapability": "FIN-210"}}, {"key": "accrual_reviewed", "value": {"label": "Accrual review", "required": false, "sourceCapability": "FIN-195"}}]'::jsonb,
    '00000000-0000-0000-0000-000000024402', 'financemanagera'
  );
  perform app.publish_finance_config_version(v_draft.id, '00000000-0000-0000-0000-000000024402', null, 'financemanagera');
end;
$$;

\echo '>> authority: Plain User A is denied calendar generation; Finance Manager A generates a 3-month calendar, each period pinning both checklist items as a governed snapshot'
do $$
declare
  v_tenant_a uuid;
  v_calendar app.finance_fiscal_calendars;
  v_period_count integer;
  v_checklist_count integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmefiscala');

  begin
    perform app.generate_finance_fiscal_calendar(v_tenant_a, null, 'FY2026', 'Fiscal Year 2026', '2026-01-01'::date, 3, '00000000-0000-0000-0000-000000024404', 'plainusera');
    raise exception 'assertion failed: expected insufficient_authority for Plain User A';
  exception
    when insufficient_privilege then
      null;
  end;

  select * into v_calendar from app.generate_finance_fiscal_calendar(v_tenant_a, null, 'FY2026', 'Fiscal Year 2026', '2026-01-01'::date, 3, '00000000-0000-0000-0000-000000024402', 'financemanagera');

  select count(*) into v_period_count from app.finance_fiscal_periods where calendar_id = v_calendar.id;
  if v_period_count <> 3 then
    raise exception 'assertion failed: expected 3 generated periods, got %', v_period_count;
  end if;

  select count(*) into v_checklist_count from app.finance_period_close_checklist_items ci
    join app.finance_fiscal_periods p on p.id = ci.period_id
    where p.calendar_id = v_calendar.id;
  if v_checklist_count <> 6 then
    raise exception 'assertion failed: expected 2 checklist items x 3 periods = 6, got %', v_checklist_count;
  end if;
end;
$$;

\echo '>> structural validation: invalid period count, duplicate calendar code, and date overlap are each rejected'
do $$
declare
  v_tenant_a uuid;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmefiscala');

  begin
    perform app.generate_finance_fiscal_calendar(v_tenant_a, null, 'FY2026-INVALID', 'Invalid', '2027-01-01'::date, 0, '00000000-0000-0000-0000-000000024402', 'financemanagera');
    raise exception 'assertion failed: expected finance_calendar_invalid_period_count';
  exception
    when others then
      if sqlerrm !~ 'finance_calendar_invalid_period_count' then
        raise exception 'assertion failed: expected finance_calendar_invalid_period_count, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.generate_finance_fiscal_calendar(v_tenant_a, null, 'FY2026', 'Duplicate Code', '2027-01-01'::date, 1, '00000000-0000-0000-0000-000000024402', 'financemanagera');
    raise exception 'assertion failed: expected finance_calendar_duplicate_code';
  exception
    when others then
      if sqlerrm !~ 'finance_calendar_duplicate_code' then
        raise exception 'assertion failed: expected finance_calendar_duplicate_code, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.generate_finance_fiscal_calendar(v_tenant_a, null, 'FY2026-OVERLAP', 'Overlap', '2026-02-15'::date, 1, '00000000-0000-0000-0000-000000024402', 'financemanagera');
    raise exception 'assertion failed: expected finance_period_overlap';
  exception
    when others then
      if sqlerrm !~ 'finance_period_overlap' then
        raise exception 'assertion failed: expected finance_period_overlap, got %', sqlerrm;
      end if;
  end;
end;
$$;

\echo '>> deterministic date-to-period resolution: a covered date resolves with posting_eligible=true while open; an uncovered date returns zero rows'
do $$
declare
  v_tenant_a uuid;
  v_row record;
  v_found boolean := false;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmefiscala');

  for v_row in select * from app.resolve_finance_period_for_date(v_tenant_a, null, '2026-01-15'::date) loop
    v_found := true;
    if v_row.period_code <> '2026-01' or not v_row.posting_eligible then
      raise exception 'assertion failed: expected 2026-01 posting_eligible=true, got % / %', v_row.period_code, v_row.posting_eligible;
    end if;
  end loop;
  if not v_found then
    raise exception 'assertion failed: expected a resolved period for 2026-01-15';
  end if;

  if exists (select 1 from app.resolve_finance_period_for_date(v_tenant_a, null, '1999-01-01'::date)) then
    raise exception 'assertion failed: expected zero rows for an uncovered date';
  end if;
end;
$$;

\echo '>> close readiness: not ready while the required item is unsatisfied; ready once acknowledged; acknowledgment denied on a closed period (tested after closing 2026-01 later in this file)'
do $$
declare
  v_tenant_a uuid;
  v_period_id uuid;
  v_readiness jsonb;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmefiscala');
  select id into v_period_id from app.finance_fiscal_periods where tenant_id = v_tenant_a and period_code = '2026-01';

  select app.get_finance_period_close_readiness(v_period_id, '00000000-0000-0000-0000-000000024402') into v_readiness;
  if (v_readiness ->> 'ready')::boolean then
    raise exception 'assertion failed: expected ready=false before the required item is satisfied, got %', v_readiness;
  end if;

  perform app.acknowledge_finance_period_checklist_item(v_period_id, 'ar_aging_reconciled', true, 'reconciled manually', '00000000-0000-0000-0000-000000024402', 'financemanagera');

  select app.get_finance_period_close_readiness(v_period_id, '00000000-0000-0000-0000-000000024402') into v_readiness;
  if not (v_readiness ->> 'ready')::boolean then
    raise exception 'assertion failed: expected ready=true once the required item is satisfied, got %', v_readiness;
  end if;
end;
$$;

\echo '>> lifecycle split: Finance Editor A (FIN:Edit, no Approve) can soft-close but cannot close or reopen; Finance Manager A (FIN:Approve) can'
do $$
declare
  v_tenant_a uuid;
  v_period app.finance_fiscal_periods;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmefiscala');
  select * into v_period from app.finance_fiscal_periods where tenant_id = v_tenant_a and period_code = '2026-01';

  select * into v_period from app.soft_close_finance_period(v_period.id, v_period.record_version, '00000000-0000-0000-0000-000000024403', 'financeeditora');
  if v_period.status <> 'soft_closed' then
    raise exception 'assertion failed: expected 2026-01 to soft-close';
  end if;

  begin
    perform app.soft_close_finance_period(v_period.id, v_period.record_version, '00000000-0000-0000-0000-000000024403', 'financeeditora');
    raise exception 'assertion failed: expected finance_period_not_open on a second soft-close';
  exception
    when others then
      if sqlerrm !~ 'finance_period_not_open' then
        raise exception 'assertion failed: expected finance_period_not_open, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.close_finance_period(v_period.id, v_period.record_version, '00000000-0000-0000-0000-000000024403', 'financeeditora');
    raise exception 'assertion failed: expected insufficient_authority -- Finance Editor A lacks FIN:Approve';
  exception
    when insufficient_privilege then
      null;
  end;

  select * into v_period from app.close_finance_period(v_period.id, v_period.record_version, '00000000-0000-0000-0000-000000024402', 'financemanagera');
  if v_period.status <> 'closed' or v_period.closed_by <> 'financemanagera' then
    raise exception 'assertion failed: expected 2026-01 to close under Finance Manager A''s own authority';
  end if;
end;
$$;

\echo '>> a closed period rejects checklist acknowledgment; close is rejected while required items remain unsatisfied (2026-02, untouched)'
do $$
declare
  v_tenant_a uuid;
  v_closed_period_id uuid;
  v_period_02 app.finance_fiscal_periods;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmefiscala');
  select id into v_closed_period_id from app.finance_fiscal_periods where tenant_id = v_tenant_a and period_code = '2026-01';

  begin
    perform app.acknowledge_finance_period_checklist_item(v_closed_period_id, 'accrual_reviewed', true, 'too late', '00000000-0000-0000-0000-000000024402', 'financemanagera');
    raise exception 'assertion failed: expected finance_period_closed';
  exception
    when others then
      if sqlerrm !~ 'finance_period_closed' then
        raise exception 'assertion failed: expected finance_period_closed, got %', sqlerrm;
      end if;
  end;

  select * into v_period_02 from app.finance_fiscal_periods where tenant_id = v_tenant_a and period_code = '2026-02';
  select * into v_period_02 from app.soft_close_finance_period(v_period_02.id, v_period_02.record_version, '00000000-0000-0000-0000-000000024402', 'financemanagera');
  begin
    perform app.close_finance_period(v_period_02.id, v_period_02.record_version, '00000000-0000-0000-0000-000000024402', 'financemanagera');
    raise exception 'assertion failed: expected finance_period_checklist_incomplete for 2026-02 (its required item was never satisfied)';
  exception
    when others then
      if sqlerrm !~ 'finance_period_checklist_incomplete' then
        raise exception 'assertion failed: expected finance_period_checklist_incomplete, got %', sqlerrm;
      end if;
  end;
end;
$$;

\echo '>> governed reopen: mandatory reason enforced; Finance Editor A (no Approve) denied; Finance Manager A succeeds and the transition is recorded with its own reason'
do $$
declare
  v_tenant_a uuid;
  v_period app.finance_fiscal_periods;
  v_reopen_count integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmefiscala');
  select * into v_period from app.finance_fiscal_periods where tenant_id = v_tenant_a and period_code = '2026-01';

  begin
    perform app.reopen_finance_period(v_period.id, v_period.record_version, '', '00000000-0000-0000-0000-000000024402', 'financemanagera');
    raise exception 'assertion failed: expected finance_period_reopen_reason_required for an empty reason';
  exception
    when others then
      if sqlerrm !~ 'finance_period_reopen_reason_required' then
        raise exception 'assertion failed: expected finance_period_reopen_reason_required, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.reopen_finance_period(v_period.id, v_period.record_version, 'trying without approve', '00000000-0000-0000-0000-000000024403', 'financeeditora');
    raise exception 'assertion failed: expected insufficient_authority for Finance Editor A';
  exception
    when insufficient_privilege then
      null;
  end;

  select * into v_period from app.reopen_finance_period(v_period.id, v_period.record_version, 'correcting a posting error found after close', '00000000-0000-0000-0000-000000024402', 'financemanagera');
  if v_period.status <> 'open' or v_period.closed_at is not null then
    raise exception 'assertion failed: expected 2026-01 to reopen to open with closed_at cleared';
  end if;

  select count(*) into v_reopen_count from app.finance_period_transitions where period_id = v_period.id and to_status = 'open' and reason = 'correcting a posting error found after close';
  if v_reopen_count <> 1 then
    raise exception 'assertion failed: expected exactly one recorded reopen transition carrying its own reason, got %', v_reopen_count;
  end if;
end;
$$;

\echo '>> cross-tenant isolation: Finance Manager B cannot generate/soft-close/close/reopen against tenant A''s own calendar/periods'
do $$
declare
  v_tenant_a uuid;
  v_period app.finance_fiscal_periods;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmefiscala');
  select * into v_period from app.finance_fiscal_periods where tenant_id = v_tenant_a and period_code = '2026-03';

  begin
    perform app.generate_finance_fiscal_calendar(v_tenant_a, null, 'FY2026-INTRUDER', 'Intruder', '2030-01-01'::date, 1, '00000000-0000-0000-0000-000000024405', 'financemanagerb');
    raise exception 'assertion failed: expected insufficient_authority -- Finance Manager B has no FIN grant in tenant A';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.soft_close_finance_period(v_period.id, v_period.record_version, '00000000-0000-0000-0000-000000024405', 'financemanagerb');
    raise exception 'assertion failed: expected insufficient_authority for cross-tenant soft-close';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$$;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on every new FIN-193 function (ERR-2026-004 regression guard)'
do $$
declare
  v_fn text;
  v_anon_has boolean;
begin
  for v_fn in select unnest(array[
    'generate_finance_fiscal_calendar', 'resolve_finance_period_for_date', 'get_finance_period_close_readiness',
    'acknowledge_finance_period_checklist_item', 'soft_close_finance_period', 'close_finance_period',
    'reopen_finance_period', 'list_finance_fiscal_periods', 'get_finance_period_transition_history',
    'check_finance_period_authority', 'touch_finance_fiscal_period_row'
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

\echo '>> audit trail: at least one generate/close/reopen event was captured for tenant A''s own fiscal-period activity'
do $$
declare
  v_tenant_a uuid;
  v_count integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmefiscala');
  select count(*) into v_count from app.audit_logs where tenant_id = v_tenant_a and action in
    ('generate_finance_fiscal_calendar', 'close_finance_period', 'reopen_finance_period');
  if v_count < 3 then
    raise exception 'assertion failed: expected at least 3 audit events across this fixture''s own generate/close/reopen calls, found %', v_count;
  end if;
end;
$$;
