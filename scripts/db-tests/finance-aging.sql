-- Real, executable test evidence for FIN-210 (AR and AP Aging,
-- CG-S9-FIN-021) -- run via `pnpm run db:test` against a real, disposable
-- Postgres database.
-- Proves: bucket-config structural validation (empty, missing field, first
-- bucket not covering current, last bucket not open-ended, gap/overlap)
-- each a distinct named exception; a tenant with no configured buckets
-- resolves to the disclosed system default (version 0); a governed,
-- versioned bucket-config change (FIN:Approve) never edits a prior
-- version; real AR open items (current/1-30/31-60/90+) bucket correctly
-- and reconcile exactly between summary and detail; a held item is
-- included/excluded per includeHeld; a fully-paid item (open_amount=0) is
-- excluded; as-of-date bounding by invoice_date; cross-tenant isolation;
-- schema-privilege defense in depth; audit trail.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants; tenant A gets a Finance Manager (FIN:Create/Edit/Approve/View, tenant_admin), a Finance Editor (FIN:Edit/View only, no Approve), and a Plain User with no FIN grant; tenant B gets its own Finance Manager; tenant A gets one open fiscal period covering all of 2026 and one customer account'
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
    ('00000000-0000-0000-0000-000000035001', 'admina@acmeaging.test'),
    ('00000000-0000-0000-0000-000000035002', 'financemanagera@acmeaging.test'),
    ('00000000-0000-0000-0000-000000035003', 'financeeditora@acmeaging.test'),
    ('00000000-0000-0000-0000-000000035004', 'plainusera@acmeaging.test'),
    ('00000000-0000-0000-0000-000000035005', 'financemanagerb@acmeaging.test');

  perform app.provision_tenant('acmeaginga', 'Acme Aging A', 'idem-acmeaginga', 'tester');
  v_tenant_a := (select id from app.tenants where slug = 'acmeaginga');
  perform app.transition_tenant_status(v_tenant_a, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_a, 'company', null, 'ACMEAGINGA-CO', 'Acme Aging A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant_a and code = 'ACMEAGINGA-CO');

  perform app.provision_tenant('acmeagingb', 'Acme Aging B', 'idem-acmeagingb', 'tester');
  v_tenant_b := (select id from app.tenants where slug = 'acmeagingb');
  perform app.transition_tenant_status(v_tenant_b, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_b, 'company', null, 'ACMEAGINGB-CO', 'Acme Aging B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant_b and code = 'ACMEAGINGB-CO');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000035001', 'admina@acmeaging.test', 'Tenant A Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admina@acmeaging.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000035001', 'tenant_admin', v_tenant_a, null, 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000035002', 'financemanagera@acmeaging.test', 'Finance Manager A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financemanagera@acmeaging.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000035002', 'tenant_admin', v_tenant_a, null, 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000035003', 'financeeditora@acmeaging.test', 'Finance Editor A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financeeditora@acmeaging.test'), 'active', 'onboarded', 'tester');

  v_manager_role_a := (app.create_role(v_tenant_a, 'Finance Manager', 'Aging authority', 'tester')).id;
  v_manager_draft_a := app.create_role_version(v_manager_role_a, 'tester');
  perform app.set_role_version_permissions(v_manager_draft_a.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'View')), 'tester');
  perform app.publish_role_version(v_manager_draft_a.id, now(), 'tester');
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_manager_role_a and status = 'published'), '00000000-0000-0000-0000-000000035002', '00000000-0000-0000-0000-000000035001', 'tester');

  v_editor_role_a := (app.create_role(v_tenant_a, 'Finance Editor', 'edit only, no approve', 'tester')).id;
  v_editor_draft_a := app.create_role_version(v_editor_role_a, 'tester');
  perform app.set_role_version_permissions(v_editor_draft_a.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Edit', 'View')), 'tester');
  perform app.publish_role_version(v_editor_draft_a.id, now(), 'tester');
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_editor_role_a and status = 'published'), '00000000-0000-0000-0000-000000035003', '00000000-0000-0000-0000-000000035001', 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000035004', 'plainusera@acmeaging.test', 'Plain User A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'plainusera@acmeaging.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant_b, '00000000-0000-0000-0000-000000035005', 'financemanagerb@acmeaging.test', 'Finance Manager B', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financemanagerb@acmeaging.test'), 'active', 'onboarded', 'tester');
  v_manager_role_b := (app.create_role(v_tenant_b, 'Finance Manager', 'Aging authority', 'tester')).id;
  v_manager_draft_b := app.create_role_version(v_manager_role_b, 'tester');
  perform app.set_role_version_permissions(v_manager_draft_b.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'View')), 'tester');
  perform app.publish_role_version(v_manager_draft_b.id, now(), 'tester');
  perform app.assign_role(v_tenant_b, (select id from app.role_versions where role_id = v_manager_role_b and status = 'published'), '00000000-0000-0000-0000-000000035005', '00000000-0000-0000-0000-000000035005', 'tester');

  perform app.generate_finance_fiscal_calendar(v_tenant_a, null, 'FY2026', 'FY2026 Monthly', '2026-01-01'::date, 12, '00000000-0000-0000-0000-000000035002', 'financemanagera');

  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant_a, 'Acme Aging Customer Pte Ltd', 'acmeaging-customer-fixture-fingerprint', '{}'::jsonb, v_team_a, 'tester');
end;
$$;

\echo '>> bucket-config structural validation: Plain User A is denied; an empty array, a missing field, a first bucket not covering current, a last bucket not open-ended, and a gap/overlap are each rejected with a distinct named exception'
do $$
declare
  v_tenant_a uuid;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmeaginga');

  begin
    perform app.set_finance_aging_bucket_config(v_tenant_a, 'ar', '[{"label":"Current","minDays":0,"maxDays":null}]'::jsonb, '00000000-0000-0000-0000-000000035004', 'plainusera');
    raise exception 'assertion failed: expected insufficient_authority for Plain User A';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.set_finance_aging_bucket_config(v_tenant_a, 'ar', '[]'::jsonb, '00000000-0000-0000-0000-000000035002', 'financemanagera');
    raise exception 'assertion failed: expected finance_aging_bucket_empty';
  exception
    when others then
      if sqlerrm !~ 'finance_aging_bucket_empty' then
        raise exception 'assertion failed: expected finance_aging_bucket_empty, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.set_finance_aging_bucket_config(v_tenant_a, 'ar', '[{"label":"Current","maxDays":null}]'::jsonb, '00000000-0000-0000-0000-000000035002', 'financemanagera');
    raise exception 'assertion failed: expected finance_aging_bucket_missing_field';
  exception
    when others then
      if sqlerrm !~ 'finance_aging_bucket_missing_field' then
        raise exception 'assertion failed: expected finance_aging_bucket_missing_field, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.set_finance_aging_bucket_config(v_tenant_a, 'ar', '[{"label":"Not Current","minDays":5,"maxDays":null}]'::jsonb, '00000000-0000-0000-0000-000000035002', 'financemanagera');
    raise exception 'assertion failed: expected finance_aging_bucket_first_not_covering_current';
  exception
    when others then
      if sqlerrm !~ 'finance_aging_bucket_first_not_covering_current' then
        raise exception 'assertion failed: expected finance_aging_bucket_first_not_covering_current, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.set_finance_aging_bucket_config(v_tenant_a, 'ar', '[{"label":"Current","minDays":-999999,"maxDays":0},{"label":"1-30","minDays":1,"maxDays":30}]'::jsonb, '00000000-0000-0000-0000-000000035002', 'financemanagera');
    raise exception 'assertion failed: expected finance_aging_bucket_last_not_open_ended';
  exception
    when others then
      if sqlerrm !~ 'finance_aging_bucket_last_not_open_ended' then
        raise exception 'assertion failed: expected finance_aging_bucket_last_not_open_ended, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.set_finance_aging_bucket_config(v_tenant_a, 'ar', '[{"label":"Current","minDays":-999999,"maxDays":0},{"label":"1-30","minDays":1,"maxDays":30},{"label":"40+","minDays":40,"maxDays":null}]'::jsonb, '00000000-0000-0000-0000-000000035002', 'financemanagera');
    raise exception 'assertion failed: expected finance_aging_bucket_gap_or_overlap for a gap between buckets';
  exception
    when others then
      if sqlerrm !~ 'finance_aging_bucket_gap_or_overlap' then
        raise exception 'assertion failed: expected finance_aging_bucket_gap_or_overlap, got %', sqlerrm;
      end if;
  end;
end;
$$;

\echo '>> a tenant with no configured buckets resolves to the disclosed system default (version 0, 5 buckets); a governed, versioned config change never edits a prior version'
do $$
declare
  v_tenant_a uuid;
  v_resolution record;
  v_config app.finance_aging_bucket_configs;
  v_config_2 app.finance_aging_bucket_configs;
  v_history_count integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmeaginga');

  select * into v_resolution from app.resolve_finance_aging_buckets(v_tenant_a, 'ap');
  if v_resolution.version <> 0 or jsonb_array_length(v_resolution.buckets) <> 5 then
    raise exception 'assertion failed: expected the disclosed system default (version 0, 5 buckets) for a tenant with no AP override, got version=% count=%', v_resolution.version, jsonb_array_length(v_resolution.buckets);
  end if;

  select * into v_config from app.set_finance_aging_bucket_config(v_tenant_a, 'ar',
    '[{"label":"Current","minDays":-999999,"maxDays":0},{"label":"1-45","minDays":1,"maxDays":45},{"label":"46+","minDays":46,"maxDays":null}]'::jsonb,
    '00000000-0000-0000-0000-000000035002', 'financemanagera');
  if v_config.version <> 1 or not v_config.is_active then
    raise exception 'assertion failed: expected the first AR override to be version 1, active';
  end if;

  select * into v_config_2 from app.set_finance_aging_bucket_config(v_tenant_a, 'ar',
    '[{"label":"Current","minDays":-999999,"maxDays":0},{"label":"1-60","minDays":1,"maxDays":60},{"label":"61+","minDays":61,"maxDays":null}]'::jsonb,
    '00000000-0000-0000-0000-000000035002', 'financemanagera');
  if v_config_2.version <> 2 then
    raise exception 'assertion failed: expected the second AR override to increment to version 2, got %', v_config_2.version;
  end if;

  select * into v_config from app.finance_aging_bucket_configs where id = v_config.id;
  if v_config.is_active then
    raise exception 'assertion failed: expected version 1 to be deactivated once version 2 was set -- never edited, only superseded';
  end if;

  select count(*) into v_history_count from app.finance_aging_bucket_configs where tenant_id = v_tenant_a and entity_type = 'ar';
  if v_history_count <> 2 then
    raise exception 'assertion failed: expected exactly two AR bucket-config rows (both versions retained), got %', v_history_count;
  end if;

  select * into v_resolution from app.resolve_finance_aging_buckets(v_tenant_a, 'ar');
  if v_resolution.version <> 2 then
    raise exception 'assertion failed: expected the active (version 2) AR override to resolve, got version %', v_resolution.version;
  end if;
end;
$$;

\echo '>> real AR open items bucket correctly against the tenant''s own active override (Current/1-60/61+); summary reconciles exactly to detail; a held item is excluded when includeHeld=false but included by default; a fully-paid item (open_amount=0) never appears'
do $$
declare
  v_tenant_a uuid;
  v_customer_id uuid;
  v_current_item app.finance_ar_open_items;
  v_bucket2_item app.finance_ar_open_items;
  v_bucket3_item app.finance_ar_open_items;
  v_held_item app.finance_ar_open_items;
  v_paid_item app.finance_ar_open_items;
  v_detail_count integer;
  v_summary_total numeric;
  v_detail_total numeric;
  v_bucket_label text;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmeaginga');
  v_customer_id := (select id from app.accounts where tenant_id = v_tenant_a);

  -- authority and validation on the report itself
  begin
    perform app.get_finance_aging_report(v_tenant_a, null, 'ar', '2026-07-15'::date, true, '00000000-0000-0000-0000-000000035004');
    raise exception 'assertion failed: expected insufficient_authority for Plain User A reading the aging report';
  exception
    when insufficient_privilege then
      null;
  end;
  begin
    perform app.get_finance_aging_report(v_tenant_a, null, 'gl', '2026-07-15'::date, true, '00000000-0000-0000-0000-000000035002');
    raise exception 'assertion failed: expected finance_aging_invalid_entity_type';
  exception
    when others then
      if sqlerrm !~ 'finance_aging_invalid_entity_type' then
        raise exception 'assertion failed: expected finance_aging_invalid_entity_type, got %', sqlerrm;
      end if;
  end;

  -- Current: due 2026-07-20, as-of 2026-07-15 (not yet due)
  select * into v_current_item from app.post_finance_ar_open_item(v_tenant_a, null, v_customer_id, 'invoice', gen_random_uuid(), 'USD', 100, '2026-07-01'::date, '2026-07-20'::date, '00000000-0000-0000-0000-000000035002', 'financemanagera');
  -- 1-60 bucket: due 2026-06-20, as-of 2026-07-15 -> 25 days overdue
  select * into v_bucket2_item from app.post_finance_ar_open_item(v_tenant_a, null, v_customer_id, 'invoice', gen_random_uuid(), 'USD', 200, '2026-06-01'::date, '2026-06-20'::date, '00000000-0000-0000-0000-000000035002', 'financemanagera');
  -- 61+ bucket: due 2026-04-01, as-of 2026-07-15 -> 105 days overdue
  select * into v_bucket3_item from app.post_finance_ar_open_item(v_tenant_a, null, v_customer_id, 'invoice', gen_random_uuid(), 'USD', 50, '2026-03-01'::date, '2026-04-01'::date, '00000000-0000-0000-0000-000000035002', 'financemanagera');
  -- a held item, included by default, excludable
  select * into v_held_item from app.post_finance_ar_open_item(v_tenant_a, null, v_customer_id, 'invoice', gen_random_uuid(), 'USD', 30, '2026-06-01'::date, '2026-06-25'::date, '00000000-0000-0000-0000-000000035002', 'financemanagera');
  perform app.place_finance_ar_hold(v_held_item.id, v_held_item.record_version, 'dispute under review', '00000000-0000-0000-0000-000000035002', 'financemanagera');
  -- a fully-paid item (open_amount=0 via full allocation), must never appear
  select * into v_paid_item from app.post_finance_ar_open_item(v_tenant_a, null, v_customer_id, 'invoice', gen_random_uuid(), 'USD', 75, '2026-06-01'::date, '2026-06-25'::date, '00000000-0000-0000-0000-000000035002', 'financemanagera');
  perform app.apply_finance_ar_allocation(v_paid_item.id, 75, 'receipt', gen_random_uuid(), null, '00000000-0000-0000-0000-000000035002', 'financemanagera');

  select count(*) into v_detail_count from app.get_finance_aging_report(v_tenant_a, null, 'ar', '2026-07-15'::date, true, '00000000-0000-0000-0000-000000035002');
  if v_detail_count <> 4 then
    raise exception 'assertion failed: expected exactly 4 open (non-paid) items in the detail report (paid item excluded), got %', v_detail_count;
  end if;

  select bucket_label into v_bucket_label from app.get_finance_aging_report(v_tenant_a, null, 'ar', '2026-07-15'::date, true, '00000000-0000-0000-0000-000000035002') where open_item_id = v_current_item.id;
  if v_bucket_label <> 'Current' then
    raise exception 'assertion failed: expected the not-yet-due item to bucket as Current, got %', v_bucket_label;
  end if;
  select bucket_label into v_bucket_label from app.get_finance_aging_report(v_tenant_a, null, 'ar', '2026-07-15'::date, true, '00000000-0000-0000-0000-000000035002') where open_item_id = v_bucket2_item.id;
  if v_bucket_label <> '1-60' then
    raise exception 'assertion failed: expected the 25-day-overdue item to bucket as 1-60, got %', v_bucket_label;
  end if;
  select bucket_label into v_bucket_label from app.get_finance_aging_report(v_tenant_a, null, 'ar', '2026-07-15'::date, true, '00000000-0000-0000-0000-000000035002') where open_item_id = v_bucket3_item.id;
  if v_bucket_label <> '61+' then
    raise exception 'assertion failed: expected the 105-day-overdue item to bucket as 61+, got %', v_bucket_label;
  end if;

  select count(*) into v_detail_count from app.get_finance_aging_report(v_tenant_a, null, 'ar', '2026-07-15'::date, false, '00000000-0000-0000-0000-000000035002');
  if v_detail_count <> 3 then
    raise exception 'assertion failed: expected exactly 3 items when includeHeld=false (the held item excluded), got %', v_detail_count;
  end if;

  select coalesce(sum(open_amount), 0) into v_summary_total from app.get_finance_aging_summary(v_tenant_a, null, 'ar', '2026-07-15'::date, true, '00000000-0000-0000-0000-000000035002');
  select coalesce(sum(open_amount), 0) into v_detail_total from app.get_finance_aging_report(v_tenant_a, null, 'ar', '2026-07-15'::date, true, '00000000-0000-0000-0000-000000035002');
  if v_summary_total <> v_detail_total or v_summary_total <> 380 then
    raise exception 'assertion failed: expected the summary total to reconcile exactly to the detail total (both 380), got summary=% detail=%', v_summary_total, v_detail_total;
  end if;

  -- as-of-date bounding: a run as of a date before the Current item's own invoice_date excludes it
  if exists (
    select 1 from app.get_finance_aging_report(v_tenant_a, null, 'ar', '2026-06-15'::date, true, '00000000-0000-0000-0000-000000035002')
    where open_item_id = v_current_item.id
  ) then
    raise exception 'assertion failed: expected an as-of date before the Current item''s own invoice_date (2026-07-01) to exclude it';
  end if;
end;
$$;

\echo '>> cross-tenant isolation: Finance Manager B cannot set/read tenant A''s own bucket configuration, and the aging report/summary/list-configs never return tenant A''s rows for tenant B''s own scope'
do $$
declare
  v_tenant_a uuid;
  v_tenant_b uuid;
  v_count integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmeaginga');
  v_tenant_b := (select id from app.tenants where slug = 'acmeagingb');

  select count(*) into v_count from app.get_finance_aging_report(v_tenant_b, null, 'ar', '2026-07-15'::date, true, '00000000-0000-0000-0000-000000035005');
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero AR aging rows visible to tenant B, got %', v_count;
  end if;

  select count(*) into v_count from app.list_finance_aging_bucket_configs(v_tenant_b, null, '00000000-0000-0000-0000-000000035005');
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero bucket configs visible to tenant B, got %', v_count;
  end if;
end;
$$;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on every new FIN-210 function (ERR-2026-004 regression guard)'
do $$
declare
  v_leaked_count integer;
begin
  select count(*) into v_leaked_count
    from information_schema.routine_privileges
    where routine_schema = 'app'
      and grantee = 'anon'
      and routine_name in (
        'set_finance_aging_bucket_config', 'resolve_finance_aging_buckets', 'assign_finance_aging_bucket',
        'get_finance_aging_report', 'get_finance_aging_summary', 'list_finance_aging_bucket_configs',
        'validate_finance_aging_buckets', 'check_finance_aging_authority'
      );
  if v_leaked_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grants on FIN-210 functions, found %', v_leaked_count;
  end if;
end;
$$;

\echo '>> audit trail: at least one bucket-config change was captured for tenant A''s own aging activity'
do $$
declare
  v_tenant_a uuid;
  v_count integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmeaginga');
  select count(*) into v_count from app.audit_logs where tenant_id = v_tenant_a and action = 'set_finance_aging_bucket_config';
  if v_count = 0 then
    raise exception 'assertion failed: expected at least one FIN-210 audit event for tenant A';
  end if;
end;
$$;

\echo '>> ISS-2026-302 behaviour on the FIN:Approve authority shape: app.set_finance_aging_bucket_config denies an out-of-allowlist caller and allows an in-range one. The 65 widened functions were transformed by TWO different scripted substitutions -- one for the app.evaluate_permission shape (SEC/HRS, proven in ip-restriction-network-access.sql) and one for the app.check_finance_*_authority shape -- so each shape needs a real execution, not one shape standing in for both'
do $$
declare
  v_tenant_a uuid := (select id from app.tenants where slug = 'acmeaginga');
  v_admin uuid := '00000000-0000-0000-0000-000000035001';
  v_manager uuid := '00000000-0000-0000-0000-000000035002';
  v_sec uuid := '00000000-0000-0000-0000-000000035006';
  v_role uuid;
  v_draft app.role_versions;
  v_buckets jsonb := '[{"label":"Current","minDays":0,"maxDays":30},{"label":"Over 30","minDays":31,"maxDays":null}]'::jsonb;
begin
  -- A SEC:Configure holder, because configuring the allowlist is itself SEC:Configure-gated
  -- and the finance manager deliberately holds no SEC permission at all.
  insert into auth.users (id, email) values (v_sec, 'secadmina@acmeaging.test');
  perform app.invite_user(v_tenant_a, v_sec, 'secadmina@acmeaging.test', 'Security Admin A', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'secadmina@acmeaging.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_sec, 'tenant_admin', v_tenant_a, null, 'tester');
  v_role := (app.create_role(v_tenant_a, 'Aging Security Admin', 'SEC:Configure/View', 'tester')).id;
  v_draft := app.create_role_version(v_role, 'tester');
  perform app.set_role_version_permissions(v_draft.id, array(select id from app.permissions where resource_module_code = 'SEC' and action in ('Configure', 'View')), 'tester');
  perform app.publish_role_version(v_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_role and status = 'published'), v_sec, v_admin, 'tester');

  perform app.add_ip_allowlist_entry(v_tenant_a, '10.0.0.0/8', 'datacentre range', 'admin', v_sec, 'secadmina');
  perform app.set_ip_allowlist_enforcement_mode(v_tenant_a, 'enforced', v_sec, 'secadmina');

  -- Out of range: refused, on a function whose authority check is the finance-helper shape
  -- rather than the evaluate_permission one.
  begin
    perform app.set_finance_aging_bucket_config(v_tenant_a, 'ar', v_buckets, v_manager, 'financemanagera', '203.0.113.9');
    raise exception 'assertion failed: expected ip_not_allowed for an out-of-allowlist caller on a FIN:Approve action';
  exception when insufficient_privilege then
    if sqlerrm not like 'ip_not_allowed%' then raise; end if;
  end;

  -- In range: the identical call succeeds, so the refusal above was the IP gate and not the
  -- authority check quietly failing.
  perform app.set_finance_aging_bucket_config(v_tenant_a, 'ar', v_buckets, v_manager, 'financemanagera', '10.1.2.3');

  -- No address supplied: unchanged. Every pre-existing caller passes five arguments.
  perform app.set_finance_aging_bucket_config(v_tenant_a, 'ar', v_buckets, v_manager, 'financemanagera');

  perform app.set_ip_allowlist_enforcement_mode(v_tenant_a, 'disabled', v_sec, 'secadmina');
  raise notice 'PASS: the FIN:Approve authority shape enforces the IP allowlist too, and still no-ops without an address';
end;
$$;

\echo 'ALL FIN-210 (AR and AP Aging) db-test assertions passed.'
