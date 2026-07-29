-- Real, executable test evidence for FIN-198 (Receipt and Payment Allocation,
-- CG-S9-FIN-009) -- run via `pnpm run db:test` against a real, disposable
-- Postgres database.
-- Proves: idempotent receipt capture (retried call returns the unchanged
-- original receipt, duplicate bank reference rejected); exact multi-invoice
-- allocation with unapplied remainder; over-allocation rejected; idempotent
-- allocate replay (never double-applies, composing correctly with FIN-196's
-- own idempotent app.apply_finance_ar_allocation); currency/customer mismatch
-- rejection; governed deallocation (FIN:Approve-gated, mandatory reason,
-- composing with FIN-196's own app.reverse_finance_ar_allocation); candidate
-- search; cross-tenant isolation; schema-privilege defense in depth; audit
-- trail.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants; tenant A gets a Finance Manager (FIN:Edit/Approve/View), a Finance Editor (FIN:Edit/View only, no Approve), and a Plain User with no FIN grant; tenant B gets its own Finance Manager; tenant A gets six open fiscal periods (Jan-Jun 2026), one customer account, and three AR open items (1,000,000 / 500,000 / 300,000 IDR)'
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
  v_customer_id uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000028501', 'admina@acmerecv.test'),
    ('00000000-0000-0000-0000-000000028502', 'financemanagera@acmerecv.test'),
    ('00000000-0000-0000-0000-000000028503', 'financeeditora@acmerecv.test'),
    ('00000000-0000-0000-0000-000000028504', 'plainusera@acmerecv.test'),
    ('00000000-0000-0000-0000-000000028505', 'financemanagerb@acmerecv.test');

  perform app.provision_tenant('acmerecva', 'Acme Receipt A', 'idem-acmerecva', 'tester');
  v_tenant_a := (select id from app.tenants where slug = 'acmerecva');
  perform app.transition_tenant_status(v_tenant_a, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_a, 'company', null, 'ACMERECVA-CO', 'Acme Receipt A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant_a and code = 'ACMERECVA-CO');

  perform app.provision_tenant('acmerecvb', 'Acme Receipt B', 'idem-acmerecvb', 'tester');
  v_tenant_b := (select id from app.tenants where slug = 'acmerecvb');
  perform app.transition_tenant_status(v_tenant_b, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_b, 'company', null, 'ACMERECVB-CO', 'Acme Receipt B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant_b and code = 'ACMERECVB-CO');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000028501', 'admina@acmerecv.test', 'Tenant A Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admina@acmerecv.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000028501', 'tenant_admin', v_tenant_a, null, 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000028502', 'financemanagera@acmerecv.test', 'Finance Manager A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financemanagera@acmerecv.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000028502', 'tenant_admin', v_tenant_a, null, 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000028503', 'financeeditora@acmerecv.test', 'Finance Editor A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financeeditora@acmerecv.test'), 'active', 'onboarded', 'tester');

  v_manager_role_a := (app.create_role(v_tenant_a, 'Finance Manager', 'receipt authority', 'tester')).id;
  v_manager_draft_a := app.create_role_version(v_manager_role_a, 'tester');
  perform app.set_role_version_permissions(v_manager_draft_a.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Edit', 'Approve', 'View')), 'tester');
  perform app.publish_role_version(v_manager_draft_a.id, now(), 'tester');
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_manager_role_a and status = 'published'), '00000000-0000-0000-0000-000000028502', '00000000-0000-0000-0000-000000028501', 'tester');

  v_editor_role_a := (app.create_role(v_tenant_a, 'Finance Editor', 'edit only, no approve', 'tester')).id;
  v_editor_draft_a := app.create_role_version(v_editor_role_a, 'tester');
  perform app.set_role_version_permissions(v_editor_draft_a.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Edit', 'View')), 'tester');
  perform app.publish_role_version(v_editor_draft_a.id, now(), 'tester');
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_editor_role_a and status = 'published'), '00000000-0000-0000-0000-000000028503', '00000000-0000-0000-0000-000000028501', 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000028504', 'plainusera@acmerecv.test', 'Plain User A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'plainusera@acmerecv.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant_b, '00000000-0000-0000-0000-000000028505', 'financemanagerb@acmerecv.test', 'Finance Manager B', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financemanagerb@acmerecv.test'), 'active', 'onboarded', 'tester');
  v_manager_role_b := (app.create_role(v_tenant_b, 'Finance Manager', 'receipt authority', 'tester')).id;
  v_manager_draft_b := app.create_role_version(v_manager_role_b, 'tester');
  perform app.set_role_version_permissions(v_manager_draft_b.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Edit', 'Approve', 'View')), 'tester');
  perform app.publish_role_version(v_manager_draft_b.id, now(), 'tester');
  perform app.assign_role(v_tenant_b, (select id from app.role_versions where role_id = v_manager_role_b and status = 'published'), '00000000-0000-0000-0000-000000028505', '00000000-0000-0000-0000-000000028505', 'tester');

  perform app.generate_finance_fiscal_calendar(v_tenant_a, null, 'FY2026', 'FY2026 Monthly', '2026-01-01'::date, 6, '00000000-0000-0000-0000-000000028502', 'financemanagera');

  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant_a, 'Acme Receipt Customer Pte Ltd', 'acmerecv-customer-fixture-fingerprint', '{}'::jsonb, v_team_a, 'tester');
  v_customer_id := (select id from app.accounts where tenant_id = v_tenant_a);

  perform app.post_finance_ar_open_item(v_tenant_a, null, v_customer_id, 'invoice', gen_random_uuid(), 'IDR', 1000000, '2026-03-01'::date, '2026-03-31'::date, '00000000-0000-0000-0000-000000028502', 'financemanagera');
  perform app.post_finance_ar_open_item(v_tenant_a, null, v_customer_id, 'invoice', gen_random_uuid(), 'IDR', 500000, '2026-03-02'::date, '2026-04-01'::date, '00000000-0000-0000-0000-000000028502', 'financemanagera');
  perform app.post_finance_ar_open_item(v_tenant_a, null, v_customer_id, 'invoice', gen_random_uuid(), 'IDR', 300000, '2026-03-03'::date, '2026-04-02'::date, '00000000-0000-0000-0000-000000028502', 'financemanagera');
end;
$$;

\echo '>> idempotent capture: Plain User A is denied; unknown customer, unsupported currency, and non-positive amount are each rejected; Finance Manager A captures once and a retried call for the same idempotency_key returns the same receipt unchanged; a duplicate bank reference is rejected'
do $$
declare
  v_tenant_a uuid;
  v_customer_id uuid;
  v_receipt app.finance_receipts;
  v_retry app.finance_receipts;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmerecva');
  v_customer_id := (select id from app.accounts where tenant_id = v_tenant_a);

  begin
    perform app.capture_finance_receipt(v_tenant_a, null, v_customer_id, 'BANKREF-001', '2026-03-10'::date, 'Jane Payer', 'BCA ****1234', 'IDR', 1300000, 'capture-1', '00000000-0000-0000-0000-000000028504', 'plainusera');
    raise exception 'assertion failed: expected insufficient_authority for Plain User A';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.capture_finance_receipt(v_tenant_a, null, gen_random_uuid(), 'BANKREF-BAD', '2026-03-10'::date, 'Jane Payer', 'BCA ****1234', 'IDR', 1300000, 'capture-bad-customer', '00000000-0000-0000-0000-000000028502', 'financemanagera');
    raise exception 'assertion failed: expected finance_receipt_customer_not_found';
  exception
    when others then
      if sqlerrm !~ 'finance_receipt_customer_not_found' then
        raise exception 'assertion failed: expected finance_receipt_customer_not_found, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.capture_finance_receipt(v_tenant_a, null, v_customer_id, 'BANKREF-BAD2', '2026-03-10'::date, 'Jane Payer', 'BCA ****1234', 'IDR', 0, 'capture-bad-amount', '00000000-0000-0000-0000-000000028502', 'financemanagera');
    raise exception 'assertion failed: expected finance_receipt_invalid_amount for a zero amount';
  exception
    when others then
      if sqlerrm !~ 'finance_receipt_invalid_amount' then
        raise exception 'assertion failed: expected finance_receipt_invalid_amount, got %', sqlerrm;
      end if;
  end;

  select * into v_receipt from app.capture_finance_receipt(v_tenant_a, null, v_customer_id, 'BANKREF-001', '2026-03-10'::date, 'Jane Payer', 'BCA ****1234', 'IDR', 1300000, 'capture-1', '00000000-0000-0000-0000-000000028502', 'financemanagera');
  if v_receipt.amount <> 1300000 or v_receipt.unapplied_amount <> 1300000 then
    raise exception 'assertion failed: expected a captured receipt of 1,300,000 fully unapplied, got amount=% unapplied=%', v_receipt.amount, v_receipt.unapplied_amount;
  end if;

  select * into v_retry from app.capture_finance_receipt(v_tenant_a, null, v_customer_id, 'BANKREF-001', '2026-03-10'::date, 'Jane Payer', 'BCA ****1234', 'IDR', 9999, 'capture-1', '00000000-0000-0000-0000-000000028502', 'financemanagera');
  if v_retry.id <> v_receipt.id or v_retry.amount <> 1300000 then
    raise exception 'assertion failed: expected a retried capture for the same idempotency_key to return the original receipt unchanged, got id=% amount=%', v_retry.id, v_retry.amount;
  end if;

  begin
    perform app.capture_finance_receipt(v_tenant_a, null, v_customer_id, 'BANKREF-001', '2026-03-11'::date, 'Jane Payer', 'BCA ****1234', 'IDR', 500000, 'capture-2', '00000000-0000-0000-0000-000000028502', 'financemanagera');
    raise exception 'assertion failed: expected finance_receipt_duplicate_reference for a reused bank reference under a different idempotency_key';
  exception
    when others then
      if sqlerrm !~ 'finance_receipt_duplicate_reference' then
        raise exception 'assertion failed: expected finance_receipt_duplicate_reference, got %', sqlerrm;
      end if;
  end;
end;
$$;

\echo '>> candidate search: returns exactly the three seeded open items for this customer/currency, due-date ordered'
do $$
declare
  v_tenant_a uuid;
  v_receipt_id uuid;
  v_candidates app.finance_ar_open_items[];
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmerecva');
  select id into v_receipt_id from app.finance_receipts where tenant_id = v_tenant_a and receipt_reference = 'BANKREF-001';

  select array_agg(r) into v_candidates from app.search_finance_ar_candidates_for_receipt(v_receipt_id, '00000000-0000-0000-0000-000000028502') r;
  if array_length(v_candidates, 1) <> 3 then
    raise exception 'assertion failed: expected exactly 3 candidate open items, found %', array_length(v_candidates, 1);
  end if;
end;
$$;

\echo '>> exact multi-invoice allocation: 1,300,000 receipt allocates 1,000,000 + 300,000 across two open items, leaving 500,000 open item untouched and 0 unapplied; over-allocation and cross-currency/cross-customer mismatches are each rejected; a retried allocate with the same idempotency_key never double-applies'
do $$
declare
  v_tenant_a uuid;
  v_customer_id uuid;
  v_receipt_id uuid;
  v_receipt app.finance_receipts;
  v_item_1000 uuid;
  v_item_500 uuid;
  v_item_300 uuid;
  v_open_amount_1000 numeric;
  v_open_amount_500 numeric;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmerecva');
  v_customer_id := (select id from app.accounts where tenant_id = v_tenant_a);
  select id into v_receipt_id from app.finance_receipts where tenant_id = v_tenant_a and receipt_reference = 'BANKREF-001';
  select id into v_item_1000 from app.finance_ar_open_items where tenant_id = v_tenant_a and original_amount = 1000000;
  select id into v_item_500 from app.finance_ar_open_items where tenant_id = v_tenant_a and original_amount = 500000;
  select id into v_item_300 from app.finance_ar_open_items where tenant_id = v_tenant_a and original_amount = 300000;

  begin
    perform app.allocate_finance_receipt(
      v_receipt_id, 'alloc-over-1',
      jsonb_build_array(jsonb_build_object('arOpenItemId', v_item_1000, 'amount', 2000000)),
      '00000000-0000-0000-0000-000000028502', 'financemanagera'
    );
    raise exception 'assertion failed: expected finance_receipt_over_allocation';
  exception
    when others then
      if sqlerrm !~ 'finance_receipt_over_allocation' then
        raise exception 'assertion failed: expected finance_receipt_over_allocation, got %', sqlerrm;
      end if;
  end;

  select * into v_receipt from app.allocate_finance_receipt(
    v_receipt_id, 'alloc-real-1',
    jsonb_build_array(
      jsonb_build_object('arOpenItemId', v_item_1000, 'amount', 1000000),
      jsonb_build_object('arOpenItemId', v_item_300, 'amount', 300000)
    ),
    '00000000-0000-0000-0000-000000028502', 'financemanagera'
  );
  if v_receipt.allocated_amount <> 1300000 or v_receipt.unapplied_amount <> 0 then
    raise exception 'assertion failed: expected allocated_amount 1,300,000 and unapplied_amount 0, got allocated=% unapplied=%', v_receipt.allocated_amount, v_receipt.unapplied_amount;
  end if;

  select open_amount into v_open_amount_1000 from app.finance_ar_open_items where id = v_item_1000;
  select open_amount into v_open_amount_500 from app.finance_ar_open_items where id = v_item_500;
  if v_open_amount_1000 <> 0 or v_open_amount_500 <> 500000 then
    raise exception 'assertion failed: expected the 1,000,000 item fully paid (open 0) and the 500,000 item untouched (open 500,000), got %/%', v_open_amount_1000, v_open_amount_500;
  end if;

  -- Idempotent replay: same idempotency_key must never double-apply.
  select * into v_receipt from app.allocate_finance_receipt(
    v_receipt_id, 'alloc-real-1',
    jsonb_build_array(jsonb_build_object('arOpenItemId', v_item_1000, 'amount', 1000000)),
    '00000000-0000-0000-0000-000000028502', 'financemanagera'
  );
  if v_receipt.allocated_amount <> 1300000 then
    raise exception 'assertion failed: expected a retried allocate with the same idempotency_key to never double-apply, got allocated_amount=%', v_receipt.allocated_amount;
  end if;
end;
$$;

\echo '>> governed deallocation: Finance Editor A (no Approve) is denied; a reason is required; Finance Manager A reverses one allocation line, restoring both the receipt''s own unapplied amount and the AR open item''s own open balance'
do $$
declare
  v_tenant_a uuid;
  v_receipt_id uuid;
  v_allocation_id uuid;
  v_item_300 uuid;
  v_receipt app.finance_receipts;
  v_open_amount numeric;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmerecva');
  select id into v_receipt_id from app.finance_receipts where tenant_id = v_tenant_a and receipt_reference = 'BANKREF-001';
  select id into v_item_300 from app.finance_ar_open_items where tenant_id = v_tenant_a and original_amount = 300000;
  select id into v_allocation_id from app.finance_receipt_allocations where receipt_id = v_receipt_id and ar_open_item_id = v_item_300 and status = 'applied';

  begin
    perform app.request_finance_receipt_deallocation(v_allocation_id, 'reversing', '00000000-0000-0000-0000-000000028503', 'financeeditora');
    raise exception 'assertion failed: expected insufficient_authority -- Finance Editor A lacks FIN:Approve';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.request_finance_receipt_deallocation(v_allocation_id, '', '00000000-0000-0000-0000-000000028502', 'financemanagera');
    raise exception 'assertion failed: expected finance_receipt_deallocation_reason_required for an empty reason';
  exception
    when others then
      if sqlerrm !~ 'finance_receipt_deallocation_reason_required' then
        raise exception 'assertion failed: expected finance_receipt_deallocation_reason_required, got %', sqlerrm;
      end if;
  end;

  select * into v_receipt from app.request_finance_receipt_deallocation(v_allocation_id, 'receipt bounced, reversing the 300,000 line', '00000000-0000-0000-0000-000000028502', 'financemanagera');
  if v_receipt.allocated_amount <> 1000000 or v_receipt.unapplied_amount <> 300000 then
    raise exception 'assertion failed: expected allocated_amount 1,000,000 and unapplied_amount 300,000 after reversal, got allocated=% unapplied=%', v_receipt.allocated_amount, v_receipt.unapplied_amount;
  end if;

  select open_amount into v_open_amount from app.finance_ar_open_items where id = v_item_300;
  if v_open_amount <> 300000 then
    raise exception 'assertion failed: expected the 300,000 AR open item to be fully open again after reversal, got open_amount=%', v_open_amount;
  end if;

  begin
    perform app.request_finance_receipt_deallocation(v_allocation_id, 'again', '00000000-0000-0000-0000-000000028502', 'financemanagera');
    raise exception 'assertion failed: expected finance_receipt_allocation_not_applied for an already-reversed allocation';
  exception
    when others then
      if sqlerrm !~ 'finance_receipt_allocation_not_applied' then
        raise exception 'assertion failed: expected finance_receipt_allocation_not_applied, got %', sqlerrm;
      end if;
  end;
end;
$$;

\echo '>> cross-tenant isolation: Finance Manager B cannot capture/allocate against tenant A''s own receipt, and list_finance_receipts never returns tenant A''s rows for tenant B''s own scope'
do $$
declare
  v_tenant_a uuid;
  v_tenant_b uuid;
  v_receipt_id uuid;
  v_item_500 uuid;
  v_rows app.finance_receipts[];
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmerecva');
  v_tenant_b := (select id from app.tenants where slug = 'acmerecvb');
  select id into v_receipt_id from app.finance_receipts where tenant_id = v_tenant_a and receipt_reference = 'BANKREF-001';
  select id into v_item_500 from app.finance_ar_open_items where tenant_id = v_tenant_a and original_amount = 500000;

  begin
    perform app.allocate_finance_receipt(
      v_receipt_id, 'intruder-alloc',
      jsonb_build_array(jsonb_build_object('arOpenItemId', v_item_500, 'amount', 100000)),
      '00000000-0000-0000-0000-000000028505', 'financemanagerb'
    );
    raise exception 'assertion failed: expected insufficient_authority -- Finance Manager B holds no FIN grant for tenant A';
  exception
    when insufficient_privilege then
      null;
  end;

  select array_agg(r) into v_rows from app.list_finance_receipts(v_tenant_b, null, null, null, '00000000-0000-0000-0000-000000028505') r;
  if v_rows is not null and exists (select 1 from unnest(v_rows) r where r.tenant_id = v_tenant_a) then
    raise exception 'assertion failed: expected tenant B''s own list_finance_receipts to never return a tenant A row';
  end if;
end;
$$;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on every new FIN-198 function (ERR-2026-004 regression guard)'
do $$
declare
  v_fn text;
  v_anon_has boolean;
begin
  for v_fn in select unnest(array[
    'touch_finance_receipt_row', 'check_finance_receipt_authority', 'capture_finance_receipt',
    'search_finance_ar_candidates_for_receipt', 'allocate_finance_receipt', 'request_finance_receipt_deallocation',
    'list_finance_receipts', 'get_finance_receipt_allocations'
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

\echo '>> audit trail: at least one capture/allocate/deallocate event was captured for tenant A''s own receipt activity'
do $$
declare
  v_tenant_a uuid;
  v_count integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmerecva');
  select count(*) into v_count from app.audit_logs where tenant_id = v_tenant_a and action in
    ('capture_finance_receipt', 'allocate_finance_receipt', 'request_finance_receipt_deallocation');
  if v_count < 3 then
    raise exception 'assertion failed: expected at least 3 audit events across this fixture''s own capture/allocate/deallocate calls, found %', v_count;
  end if;
end;
$$;
