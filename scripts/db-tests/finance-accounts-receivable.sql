-- Real, executable test evidence for FIN-196 (Accounts Receivable Subledger,
-- CG-S9-FIN-007) -- run via `pnpm run db:test` against a real, disposable
-- Postgres database.
-- Proves: idempotent posting from a source document (retried call returns
-- the same open item, never duplicates); authority split (Edit posts an
-- invoice-sourced item, Approve required for an opening-balance item);
-- period-aware posting (rejects a date with no open fiscal period);
-- exact-balance allocation/deallocation with status derived purely from
-- balance; over-allocation and over-reversal rejection; idempotent
-- allocation replay; governed hold/release split (Edit places, Approve
-- releases); exposure summary; cross-tenant isolation; schema-privilege
-- defense in depth; audit trail.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants; tenant A gets a Finance Manager (FIN:Edit/Approve/View), a Finance Editor (FIN:Edit/View only, no Approve), and a Plain User with no FIN grant; tenant B gets its own Finance Manager; tenant A gets one active fiscal period (2026-03) and one customer account'
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
  v_calendar app.finance_fiscal_calendars;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000026501', 'admina@acmear.test'),
    ('00000000-0000-0000-0000-000000026502', 'financemanagera@acmear.test'),
    ('00000000-0000-0000-0000-000000026503', 'financeeditora@acmear.test'),
    ('00000000-0000-0000-0000-000000026504', 'plainusera@acmear.test'),
    ('00000000-0000-0000-0000-000000026505', 'financemanagerb@acmear.test'),
    ('00000000-0000-0000-0000-000000026506', 'supremear@example.test');

  perform app.provision_tenant('acmeara', 'Acme AR A', 'idem-acmeara', 'tester');
  v_tenant_a := (select id from app.tenants where slug = 'acmeara');
  perform app.transition_tenant_status(v_tenant_a, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_a, 'company', null, 'ACMEARA-CO', 'Acme AR A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant_a and code = 'ACMEARA-CO');

  perform app.provision_tenant('acmearb', 'Acme AR B', 'idem-acmearb', 'tester');
  v_tenant_b := (select id from app.tenants where slug = 'acmearb');
  perform app.transition_tenant_status(v_tenant_b, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_b, 'company', null, 'ACMEARB-CO', 'Acme AR B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant_b and code = 'ACMEARB-CO');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000026501', 'admina@acmear.test', 'Tenant A Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admina@acmear.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000026501', 'tenant_admin', v_tenant_a, null, 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000026502', 'financemanagera@acmear.test', 'Finance Manager A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financemanagera@acmear.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000026502', 'tenant_admin', v_tenant_a, null, 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000026503', 'financeeditora@acmear.test', 'Finance Editor A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financeeditora@acmear.test'), 'active', 'onboarded', 'tester');

  v_manager_role_a := (app.create_role(v_tenant_a, 'Finance Manager', 'AR authority', 'tester')).id;
  v_manager_draft_a := app.create_role_version(v_manager_role_a, 'tester');
  perform app.set_role_version_permissions(v_manager_draft_a.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Edit', 'Approve', 'View')), 'tester');
  perform app.publish_role_version(v_manager_draft_a.id, now(), 'tester');
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_manager_role_a and status = 'published'), '00000000-0000-0000-0000-000000026502', '00000000-0000-0000-0000-000000026501', 'tester');

  v_editor_role_a := (app.create_role(v_tenant_a, 'Finance Editor', 'edit only, no approve', 'tester')).id;
  v_editor_draft_a := app.create_role_version(v_editor_role_a, 'tester');
  perform app.set_role_version_permissions(v_editor_draft_a.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Edit', 'View')), 'tester');
  perform app.publish_role_version(v_editor_draft_a.id, now(), 'tester');
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_editor_role_a and status = 'published'), '00000000-0000-0000-0000-000000026503', '00000000-0000-0000-0000-000000026501', 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000026504', 'plainusera@acmear.test', 'Plain User A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'plainusera@acmear.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant_b, '00000000-0000-0000-0000-000000026505', 'financemanagerb@acmear.test', 'Finance Manager B', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financemanagerb@acmear.test'), 'active', 'onboarded', 'tester');
  v_manager_role_b := (app.create_role(v_tenant_b, 'Finance Manager', 'AR authority', 'tester')).id;
  v_manager_draft_b := app.create_role_version(v_manager_role_b, 'tester');
  perform app.set_role_version_permissions(v_manager_draft_b.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Edit', 'Approve', 'View')), 'tester');
  perform app.publish_role_version(v_manager_draft_b.id, now(), 'tester');
  perform app.assign_role(v_tenant_b, (select id from app.role_versions where role_id = v_manager_role_b and status = 'published'), '00000000-0000-0000-0000-000000026505', '00000000-0000-0000-0000-000000026505', 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000026506', 'supreme_admin', null, null, 'tester');

  -- Six open fiscal periods (Jan-Jun 2026), covering every March 2026 date this fixture uses (FIN-193).
  select * into v_calendar from app.generate_finance_fiscal_calendar(v_tenant_a, null, 'FY2026', 'FY2026 Monthly', '2026-01-01'::date, 6, '00000000-0000-0000-0000-000000026502', 'financemanagera');

  -- Direct fixture insert (bypasses the full lead->prospect->quotation->convert
  -- Commercial pipeline, out of scope for this capability's own test) -- a
  -- minimal, valid customer account for tenant A.
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant_a, 'Acme AR Customer Pte Ltd', 'acmear-customer-fixture-fingerprint', '{}'::jsonb, v_team_a, 'tester');
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant_b, 'Acme AR B Customer Pte Ltd', 'acmearb-customer-fixture-fingerprint', '{}'::jsonb, v_team_b, 'tester');
end;
$$;

\echo '>> idempotent posting: Plain User A is denied; an unknown customer, unsupported currency, non-positive amount, and a date outside any generated period are each rejected; Finance Manager A posts once and a retried call returns the same row'
do $$
declare
  v_tenant_a uuid;
  v_customer_id uuid;
  v_source_id uuid := gen_random_uuid();
  v_item app.finance_ar_open_items;
  v_retry app.finance_ar_open_items;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmeara');
  v_customer_id := (select id from app.accounts where tenant_id = v_tenant_a);

  begin
    perform app.post_finance_ar_open_item(v_tenant_a, null, v_customer_id, 'invoice', v_source_id, 'USD', 1000, '2026-03-10'::date, '2026-04-09'::date, '00000000-0000-0000-0000-000000026504', 'plainusera');
    raise exception 'assertion failed: expected insufficient_authority for Plain User A';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.post_finance_ar_open_item(v_tenant_a, null, gen_random_uuid(), 'invoice', v_source_id, 'USD', 1000, '2026-03-10'::date, '2026-04-09'::date, '00000000-0000-0000-0000-000000026502', 'financemanagera');
    raise exception 'assertion failed: expected finance_ar_customer_not_found';
  exception
    when others then
      if sqlerrm !~ 'finance_ar_customer_not_found' then
        raise exception 'assertion failed: expected finance_ar_customer_not_found, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.post_finance_ar_open_item(v_tenant_a, null, v_customer_id, 'invoice', v_source_id, 'ZZZ', 1000, '2026-03-10'::date, '2026-04-09'::date, '00000000-0000-0000-0000-000000026502', 'financemanagera');
    raise exception 'assertion failed: expected finance_ar_unsupported_currency';
  exception
    when others then
      if sqlerrm !~ 'finance_ar_unsupported_currency' then
        raise exception 'assertion failed: expected finance_ar_unsupported_currency, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.post_finance_ar_open_item(v_tenant_a, null, v_customer_id, 'invoice', v_source_id, 'USD', 0, '2026-03-10'::date, '2026-04-09'::date, '00000000-0000-0000-0000-000000026502', 'financemanagera');
    raise exception 'assertion failed: expected finance_ar_invalid_amount for a zero amount';
  exception
    when others then
      if sqlerrm !~ 'finance_ar_invalid_amount' then
        raise exception 'assertion failed: expected finance_ar_invalid_amount, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.post_finance_ar_open_item(v_tenant_a, null, v_customer_id, 'invoice', v_source_id, 'USD', 1000, '2099-01-10'::date, '2099-02-09'::date, '00000000-0000-0000-0000-000000026502', 'financemanagera');
    raise exception 'assertion failed: expected finance_ar_period_not_found for a date with no generated fiscal period';
  exception
    when others then
      if sqlerrm !~ 'finance_ar_period_not_found' then
        raise exception 'assertion failed: expected finance_ar_period_not_found, got %', sqlerrm;
      end if;
  end;

  select * into v_item from app.post_finance_ar_open_item(v_tenant_a, null, v_customer_id, 'invoice', v_source_id, 'USD', 1000, '2026-03-10'::date, '2026-04-09'::date, '00000000-0000-0000-0000-000000026502', 'financemanagera');
  if v_item.status <> 'open' or v_item.original_amount <> 1000 or v_item.open_amount <> 1000 then
    raise exception 'assertion failed: expected a fresh open AR item of 1000, got status=% original=% open=%', v_item.status, v_item.original_amount, v_item.open_amount;
  end if;

  select * into v_retry from app.post_finance_ar_open_item(v_tenant_a, null, v_customer_id, 'invoice', v_source_id, 'USD', 9999, '2026-03-10'::date, '2026-04-09'::date, '00000000-0000-0000-0000-000000026502', 'financemanagera');
  if v_retry.id <> v_item.id or v_retry.original_amount <> 1000 then
    raise exception 'assertion failed: expected a retried post for the same source document to return the original item unchanged (idempotent), got id=% original=%', v_retry.id, v_retry.original_amount;
  end if;
end;
$$;

\echo '>> opening-balance authority: Finance Editor A (no Approve) is denied posting an opening_balance item; Finance Manager A (Approve) succeeds'
do $$
declare
  v_tenant_a uuid;
  v_customer_id uuid;
  v_source_id uuid := gen_random_uuid();
  v_item app.finance_ar_open_items;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmeara');
  v_customer_id := (select id from app.accounts where tenant_id = v_tenant_a);

  begin
    perform app.post_finance_ar_open_item(v_tenant_a, null, v_customer_id, 'opening_balance', v_source_id, 'USD', 500, '2026-03-01'::date, '2026-03-31'::date, '00000000-0000-0000-0000-000000026503', 'financeeditora');
    raise exception 'assertion failed: expected insufficient_authority -- Finance Editor A lacks FIN:Approve';
  exception
    when insufficient_privilege then
      null;
  end;

  select * into v_item from app.post_finance_ar_open_item(v_tenant_a, null, v_customer_id, 'opening_balance', v_source_id, 'USD', 500, '2026-03-01'::date, '2026-03-31'::date, '00000000-0000-0000-0000-000000026502', 'financemanagera');
  if v_item.source_document_type <> 'opening_balance' then
    raise exception 'assertion failed: expected an opening_balance AR item to post under Finance Manager A''s own Approve authority';
  end if;
end;
$$;

\echo '>> exact-balance allocation: partial allocation moves status to partial; over-allocation is rejected; a second allocation reaching the full amount moves status to paid; a retried allocation with the same idempotency_key never double-applies'
do $$
declare
  v_tenant_a uuid;
  v_customer_id uuid;
  v_source_id uuid := gen_random_uuid();
  v_item app.finance_ar_open_items;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmeara');
  v_customer_id := (select id from app.accounts where tenant_id = v_tenant_a);
  select * into v_item from app.post_finance_ar_open_item(v_tenant_a, null, v_customer_id, 'invoice', v_source_id, 'USD', 1000, '2026-03-05'::date, '2026-04-04'::date, '00000000-0000-0000-0000-000000026502', 'financemanagera');

  begin
    perform app.apply_finance_ar_allocation(v_item.id, 2000, 'receipt', gen_random_uuid(), 'alloc-over-1', '00000000-0000-0000-0000-000000026502', 'financemanagera');
    raise exception 'assertion failed: expected finance_ar_over_allocation';
  exception
    when others then
      if sqlerrm !~ 'finance_ar_over_allocation' then
        raise exception 'assertion failed: expected finance_ar_over_allocation, got %', sqlerrm;
      end if;
  end;

  select * into v_item from app.apply_finance_ar_allocation(v_item.id, 400, 'receipt', gen_random_uuid(), 'alloc-partial-1', '00000000-0000-0000-0000-000000026502', 'financemanagera');
  if v_item.status <> 'partial' or v_item.open_amount <> 600 then
    raise exception 'assertion failed: expected status partial, open_amount 600, got status=% open=%', v_item.status, v_item.open_amount;
  end if;

  -- Idempotent replay: same idempotency_key must never double-apply.
  select * into v_item from app.apply_finance_ar_allocation(v_item.id, 400, 'receipt', gen_random_uuid(), 'alloc-partial-1', '00000000-0000-0000-0000-000000026502', 'financemanagera');
  if v_item.allocated_amount <> 400 then
    raise exception 'assertion failed: expected a retried allocation with the same idempotency_key to never double-apply, got allocated_amount=%', v_item.allocated_amount;
  end if;

  select * into v_item from app.apply_finance_ar_allocation(v_item.id, 600, 'receipt', gen_random_uuid(), 'alloc-final-1', '00000000-0000-0000-0000-000000026502', 'financemanagera');
  if v_item.status <> 'paid' or v_item.open_amount <> 0 then
    raise exception 'assertion failed: expected status paid, open_amount 0, got status=% open=%', v_item.status, v_item.open_amount;
  end if;
end;
$$;

\echo '>> governed deallocation: Finance Editor A (no Approve) is denied reversal; a reason is required; Finance Manager A reverses part of the allocation and status returns to partial'
do $$
declare
  v_tenant_a uuid;
  v_customer_id uuid;
  v_source_id uuid := gen_random_uuid();
  v_item app.finance_ar_open_items;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmeara');
  v_customer_id := (select id from app.accounts where tenant_id = v_tenant_a);
  select * into v_item from app.post_finance_ar_open_item(v_tenant_a, null, v_customer_id, 'invoice', v_source_id, 'USD', 500, '2026-03-06'::date, '2026-04-05'::date, '00000000-0000-0000-0000-000000026502', 'financemanagera');
  select * into v_item from app.apply_finance_ar_allocation(v_item.id, 500, 'receipt', gen_random_uuid(), 'alloc-dealloc-1', '00000000-0000-0000-0000-000000026502', 'financemanagera');

  begin
    perform app.reverse_finance_ar_allocation(v_item.id, 200, 'correction', 'receipt', gen_random_uuid(), 'dealloc-1', '00000000-0000-0000-0000-000000026503', 'financeeditora');
    raise exception 'assertion failed: expected insufficient_authority -- Finance Editor A lacks FIN:Approve';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.reverse_finance_ar_allocation(v_item.id, 200, '', 'receipt', gen_random_uuid(), 'dealloc-2', '00000000-0000-0000-0000-000000026502', 'financemanagera');
    raise exception 'assertion failed: expected finance_ar_deallocation_reason_required for an empty reason';
  exception
    when others then
      if sqlerrm !~ 'finance_ar_deallocation_reason_required' then
        raise exception 'assertion failed: expected finance_ar_deallocation_reason_required, got %', sqlerrm;
      end if;
  end;

  select * into v_item from app.reverse_finance_ar_allocation(v_item.id, 200, 'receipt bounced, reversing partial application', 'receipt', gen_random_uuid(), 'dealloc-3', '00000000-0000-0000-0000-000000026502', 'financemanagera');
  if v_item.status <> 'partial' or v_item.allocated_amount <> 300 then
    raise exception 'assertion failed: expected status partial, allocated_amount 300 after reversal, got status=% allocated=%', v_item.status, v_item.allocated_amount;
  end if;
end;
$$;

\echo '>> governed hold/release split: Finance Editor A places a hold with a reason (FIN:Edit); only Finance Manager A (FIN:Approve) can release it; an already-held item cannot be held again'
do $$
declare
  v_tenant_a uuid;
  v_customer_id uuid;
  v_source_id uuid := gen_random_uuid();
  v_item app.finance_ar_open_items;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmeara');
  v_customer_id := (select id from app.accounts where tenant_id = v_tenant_a);
  select * into v_item from app.post_finance_ar_open_item(v_tenant_a, null, v_customer_id, 'invoice', v_source_id, 'USD', 250, '2026-03-07'::date, '2026-04-06'::date, '00000000-0000-0000-0000-000000026502', 'financemanagera');

  begin
    perform app.place_finance_ar_hold(v_item.id, v_item.record_version, '', '00000000-0000-0000-0000-000000026503', 'financeeditora');
    raise exception 'assertion failed: expected finance_ar_hold_reason_required for an empty reason';
  exception
    when others then
      if sqlerrm !~ 'finance_ar_hold_reason_required' then
        raise exception 'assertion failed: expected finance_ar_hold_reason_required, got %', sqlerrm;
      end if;
  end;

  select * into v_item from app.place_finance_ar_hold(v_item.id, v_item.record_version, 'disputed invoice line', '00000000-0000-0000-0000-000000026503', 'financeeditora');
  if not v_item.is_held then
    raise exception 'assertion failed: expected the open item to be held';
  end if;

  begin
    perform app.place_finance_ar_hold(v_item.id, v_item.record_version, 'again', '00000000-0000-0000-0000-000000026503', 'financeeditora');
    raise exception 'assertion failed: expected finance_ar_already_held';
  exception
    when others then
      if sqlerrm !~ 'finance_ar_already_held' then
        raise exception 'assertion failed: expected finance_ar_already_held, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.release_finance_ar_hold(v_item.id, v_item.record_version, 'resolved', '00000000-0000-0000-0000-000000026503', 'financeeditora');
    raise exception 'assertion failed: expected insufficient_authority -- Finance Editor A lacks FIN:Approve to release a hold';
  exception
    when insufficient_privilege then
      null;
  end;

  select * into v_item from app.release_finance_ar_hold(v_item.id, v_item.record_version, 'dispute resolved', '00000000-0000-0000-0000-000000026502', 'financemanagera');
  if v_item.is_held then
    raise exception 'assertion failed: expected the open item to be released';
  end if;
end;
$$;

\echo '>> exposure summary and list: totals/overdue counts reconcile; cross-tenant isolation -- Finance Manager B sees zero of tenant A''s own open items'
do $$
declare
  v_tenant_a uuid;
  v_tenant_b uuid;
  v_customer_id uuid;
  v_summary jsonb;
  v_rows app.finance_ar_open_items[];
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmeara');
  v_tenant_b := (select id from app.tenants where slug = 'acmearb');
  v_customer_id := (select id from app.accounts where tenant_id = v_tenant_a);

  select app.get_finance_ar_exposure_summary(v_tenant_a, v_customer_id, '00000000-0000-0000-0000-000000026502') into v_summary;
  if (v_summary ->> 'openCount')::integer < 3 then
    raise exception 'assertion failed: expected at least 3 open/partial/held items for tenant A''s own customer, got %', v_summary;
  end if;

  select array_agg(r) into v_rows from app.list_finance_ar_open_items(v_tenant_b, null, null, null, null, '00000000-0000-0000-0000-000000026505') r;
  if v_rows is not null and exists (select 1 from unnest(v_rows) r where r.tenant_id = v_tenant_a) then
    raise exception 'assertion failed: expected tenant B''s own list_finance_ar_open_items to never return a tenant A row';
  end if;
end;
$$;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on every new FIN-196 function (ERR-2026-004 regression guard)'
do $$
declare
  v_fn text;
  v_anon_has boolean;
begin
  for v_fn in select unnest(array[
    'touch_finance_ar_open_item_row', 'check_finance_ar_authority', 'post_finance_ar_open_item',
    'place_finance_ar_hold', 'release_finance_ar_hold', 'apply_finance_ar_allocation',
    'reverse_finance_ar_allocation', 'list_finance_ar_open_items', 'get_finance_ar_open_item_activity',
    'get_finance_ar_exposure_summary'
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

\echo '>> audit trail: at least one post/allocate/reverse event was captured for tenant A''s own AR activity'
do $$
declare
  v_tenant_a uuid;
  v_count integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmeara');
  select count(*) into v_count from app.audit_logs where tenant_id = v_tenant_a and action in
    ('post_finance_ar_open_item', 'apply_finance_ar_allocation', 'reverse_finance_ar_allocation');
  if v_count < 3 then
    raise exception 'assertion failed: expected at least 3 audit events across this fixture''s own post/allocate/reverse calls, found %', v_count;
  end if;
end;
$$;
