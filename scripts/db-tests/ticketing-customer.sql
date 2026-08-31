-- Real, executable test evidence for HRT-287 (Customer-to-Tenant Ticket,
-- CG-S12-HRT-015) -- run via `pnpm run db:test` against a real, disposable
-- Postgres database (and standalone via psql, per ISS-2026-059/077's
-- documented time-of-day workaround, since a full harness run may abort
-- before reaching this alphabetically-late file).
--
-- Own, separate file from scripts/db-tests/ticketing-internal.sql
-- (deliberate -- see build log HRT-287.md for the "extend vs. new file"
-- decision): a genuinely new principal type (Layer 4 customer_user)
-- deserves its own fixture rather than growing HRT-286's already-large one,
-- and this lets ticketing-internal.sql remain the frozen, byte-for-byte
-- regression proof that the internal channel is unchanged.
--
-- Self-contained: own fresh, unclaimed UUID range
-- (00000000-0000-0000-0000-0000002870xx). Tenant slugs `tkc1`/`tkc2`
-- (grep-verified unclaimed). Two tenants AND two customer accounts within
-- tenant 1 (mandatory convention per this task's own instruction).
--
-- Covers, live: customer self-service creation (account-scope validated,
-- never trusted from payload); forged/unowned account id rejection
-- (anti-enumeration -- same error for "not yours" and "does not exist");
-- cross-tenant account-id forgery; category customer-visibility gating
-- (queue_required when no default queue, category_not_available when not
-- customer_visible); staff-side projection (get_ticket/list_tickets) still
-- sees the customer ticket via LEFT JOIN, with the customer's account name
-- resolved; staff RPCs explicitly refuse a customer_user-layer caller
-- (decision 6); customer-safe projection excludes queue/assignee identity
-- and internal notes structurally; a second customer account cannot read
-- the first account's ticket; revoked customer_user membership loses
-- access immediately (live, not cached); reply visibility is hardcoded
-- public through app.reply_to_customer_ticket even if a caller tries to
-- force 'internal' through the underlying app.reply_to_ticket directly;
-- close/reopen-as-configured (cancel + reopen) reached through the SAME
-- generic app.transition_ticket_status; watcher management is staff-only
-- for a customer-channel ticket; raw-table RLS admits ZERO rows to a
-- customer_user-layer actor on tickets/messages/watchers/events (RPC-only
-- access, decision 7); an internal-channel ticket is unreachable through
-- every customer RPC (channel filter applied before any scope check); a
-- ticket link exposes no shipment/invoice/warehouse/vendor id (structural
-- projection-shape check, since Prompt 292/Linked Records has not shipped
-- yet -- decision 10); idempotent replay for customer creation.

\set ON_ERROR_STOP on

\echo '>> fixture'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_admin_role uuid; v_admin_draft app.role_versions;
  v_company uuid; v_branch uuid; v_dept uuid;
  v_staff1_emp uuid;
  v_account_a uuid; v_account_b uuid; v_account_t2 uuid;
  v_queue uuid;
  v_category_novisible uuid; v_category_noqueue uuid; v_category_visible uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000287001', 'admin@tkc1.test'),
    ('00000000-0000-0000-0000-000000287002', 'staff1@tkc1.test'),
    ('00000000-0000-0000-0000-000000287010', 'cust-a1@tkc1.test'),
    ('00000000-0000-0000-0000-000000287011', 'cust-a2@tkc1.test'),
    ('00000000-0000-0000-0000-000000287012', 'cust-b1@tkc1.test'),
    ('00000000-0000-0000-0000-000000287021', 'admin@tkc2.test'),
    ('00000000-0000-0000-0000-000000287022', 'cust-t2@tkc2.test');

  perform app.provision_tenant('tkc1', 'Ticket Customer Co 1', 'idem-tkc1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'tkc1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.provision_tenant('tkc2', 'Ticket Customer Co 2', 'idem-tkc2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'tkc2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000287001', 'admin@tkc1.test', 'Tkc1 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@tkc1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000287001', 'tenant_admin', v_tenant1, null, 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000287002', 'staff1@tkc1.test', 'Tkc1 Staff One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff1@tkc1.test'), 'active', 'onboarded', 'tester');

  -- Customer identities: two accounts (a, b) in tenant1 -- cust-a1/a2 both
  -- scoped to account A (two-user-per-account, so the "any active member of
  -- the account sees the account's tickets" claim is actually exercised),
  -- cust-b1 scoped to account B only. cust-t2 is tenant2's own customer.
  -- None of these customer identities gets app.invite_user/tenant_user_
  -- identities linkage through the employee path -- grant_principal_
  -- membership's own FK requires an app.tenant_user_identities row, so we
  -- invite them as plain (non-employee) tenant users, exactly mirroring
  -- ATW-023's own established fixture pattern.
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000287010', 'cust-a1@tkc1.test', 'Customer A1', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'cust-a1@tkc1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000287011', 'cust-a2@tkc1.test', 'Customer A2', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'cust-a2@tkc1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000287012', 'cust-b1@tkc1.test', 'Customer B1', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'cust-b1@tkc1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000287021', 'admin@tkc2.test', 'Tkc2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@tkc2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000287021', 'tenant_admin', v_tenant2, null, 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000287022', 'cust-t2@tkc2.test', 'Customer T2', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'cust-t2@tkc2.test'), 'active', 'onboarded', 'tester');

  -- HR role: HRS Create/Edit/Approve/Export/View -- needed by admin to
  -- drive the employee-lifecycle fixture below (mirrors HRT-286's own
  -- fixture precedent exactly).
  declare
    v_hr_role uuid; v_hr_draft app.role_versions;
  begin
    v_hr_role := (app.create_role(v_tenant1, 'HR Admin', 'HRS Create/Edit/Approve/Export/View', 'tester')).id;
    v_hr_draft := app.create_role_version(v_hr_role, 'tester');
    perform app.set_role_version_permissions(v_hr_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('Create', 'Edit', 'Approve', 'Export', 'View')), 'tester');
    perform app.publish_role_version(v_hr_draft.id, now(), 'tester');
    perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_hr_role and status = 'published'), '00000000-0000-0000-0000-000000287001', '00000000-0000-0000-0000-000000287001', 'tester');
  end;

  -- TKT admin role (Edit/Assign/Close/Reopen/Export) -- staff1 only.
  v_admin_role := (app.create_role(v_tenant1, 'Ticket Admin', 'TKT Edit/Assign/Close/Reopen/Export', 'tester')).id;
  v_admin_draft := app.create_role_version(v_admin_role, 'tester');
  perform app.set_role_version_permissions(v_admin_draft.id, array(select id from app.permissions where resource_module_code = 'TKT' and action in ('Edit', 'Override', 'Assign', 'Close', 'Reopen', 'Export')), 'tester');
  perform app.publish_role_version(v_admin_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_admin_role and status = 'published'), '00000000-0000-0000-0000-000000287002', '00000000-0000-0000-0000-000000287001', 'tester');

  v_company := (app.create_org_unit(v_tenant1, 'company', null, 'CO-TKC1', 'Tkc1 Co', 'tester')).id;
  v_branch := (app.create_org_unit(v_tenant1, 'branch', v_company, 'BR-TKC1', 'Tkc1 Branch', 'tester')).id;
  v_dept := (app.create_org_unit(v_tenant1, 'department', v_branch, 'DEPT-SUP', 'Support', 'tester')).id;

  perform app.create_employee_draft(v_tenant1, 'Tkc1 Staff One', 'full_time', 'staff1work@tkc1.test', 'staff1p@tkc1.test', '0900000001', null, null, null, '2024-01-01', v_company, v_branch, v_dept, 'Support Agent', null, (select id from app.users where email = 'staff1@tkc1.test'), null, 'hr_created', 'idem-staff1-tkc1', '00000000-0000-0000-0000-000000287001', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@tkc1.test'), 'Emergency Contact for Staff One', 'spouse', '0910000000', null, true, '00000000-0000-0000-0000-000000287001', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@tkc1.test'), 1, '00000000-0000-0000-0000-000000287001', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@tkc1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000287001', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@tkc1.test'), 3, '00000000-0000-0000-0000-000000287001', 'tester');
  v_staff1_emp := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@tkc1.test');

  v_queue := (app.create_ticket_queue(v_tenant1, v_dept, 'Q-SUP', 'Support Queue', null, '00000000-0000-0000-0000-000000287002', 'staff1')).id;
  perform app.add_ticket_queue_member(v_queue, v_staff1_emp, '00000000-0000-0000-0000-000000287002', 'staff1');

  -- Three categories: one never made customer_visible (internal-only), one
  -- that FAILS to become customer_visible because it has no default queue
  -- (queue_required), one that succeeds (the one actually usable by
  -- customers).
  v_category_novisible := (app.create_ticket_category(v_tenant1, 'CAT-INTERNAL', 'Internal Only', v_queue, '00000000-0000-0000-0000-000000287002', 'staff1')).id;
  v_category_noqueue := (app.create_ticket_category(v_tenant1, 'CAT-NOQUEUE', 'No Default Queue', null, '00000000-0000-0000-0000-000000287002', 'staff1')).id;
  v_category_visible := (app.create_ticket_category(v_tenant1, 'CAT-BILLING', 'Billing Question', v_queue, '00000000-0000-0000-0000-000000287002', 'staff1')).id;
  perform app.set_ticket_category_customer_visibility(v_category_visible, true, '00000000-0000-0000-0000-000000287002', 'staff1');

  -- app.accounts: two accounts in tenant1 (A, B), one in tenant2.
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Customer Account A', 'fp-tkc1-a', '{}'::jsonb, v_company, 'tester')
  returning id into v_account_a;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Customer Account B', 'fp-tkc1-b', '{}'::jsonb, v_company, 'tester')
  returning id into v_account_b;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant2, 'Customer Account T2', 'fp-tkc2-t2', '{}'::jsonb, null, 'tester')
  returning id into v_account_t2;

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000287010', 'customer_user', v_tenant1, v_account_a::text, 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000287011', 'customer_user', v_tenant1, v_account_a::text, 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000287012', 'customer_user', v_tenant1, v_account_b::text, 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000287022', 'customer_user', v_tenant2, v_account_t2::text, 'tester');

  raise notice 'fixture ready: tenant1=%, tenant2=%, account_a=%, account_b=%, account_t2=%, category_visible=%, category_noqueue=%, category_novisible=%, queue=%, staff1_emp=%',
    v_tenant1, v_tenant2, v_account_a, v_account_b, v_account_t2, v_category_visible, v_category_noqueue, v_category_novisible, v_queue, v_staff1_emp;
end $$;

\echo '>> 1. category customer-visibility gating: no default queue is rejected, a plain internal category stays invisible'
do $$
declare
  v_category_noqueue uuid := (select id from app.ticket_categories where tenant_id = (select id from app.tenants where slug = 'tkc1') and code = 'CAT-NOQUEUE');
  v_failed boolean := false;
begin
  begin
    perform app.set_ticket_category_customer_visibility(v_category_noqueue, true, '00000000-0000-0000-0000-000000287002', 'staff1');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'queue_required:%' then
      raise exception 'expected queue_required, got: %', sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'expected set_ticket_category_customer_visibility to reject a category with no default queue';
  end if;
  raise notice 'PASS: a category with no default queue cannot be marked customer_visible';
end $$;

\echo '>> 2. customer self-service creation: valid account, opening message, ticket_number'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tkc1');
  v_account_a uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Customer Account A');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'CAT-BILLING');
  v_ticket app.tickets;
  v_msg_count integer;
begin
  v_ticket := app.create_customer_ticket(v_tenant1, v_account_a, v_category, 'normal', 'Invoice discrepancy', 'My invoice total does not match the quote.', 'idem-cust-create-1', '00000000-0000-0000-0000-000000287010', 'Customer A1');
  if v_ticket.channel <> 'customer' or v_ticket.requester_customer_account_id <> v_account_a or v_ticket.requester_employee_id is not null then
    raise exception 'expected a customer-channel ticket with requester_customer_account_id=% and null requester_employee_id, got channel=% account=% employee=%', v_account_a, v_ticket.channel, v_ticket.requester_customer_account_id, v_ticket.requester_employee_id;
  end if;
  if v_ticket.ticket_number is null or v_ticket.status <> 'new' then
    raise exception 'expected a real ticket_number and status=new';
  end if;
  select count(*) into v_msg_count from app.ticket_messages where ticket_id = v_ticket.id;
  if v_msg_count <> 1 then
    raise exception 'expected exactly one opening message, got %', v_msg_count;
  end if;

  -- Idempotent replay: identical tuple + key returns the SAME ticket.
  if (app.create_customer_ticket(v_tenant1, v_account_a, v_category, 'normal', 'Invoice discrepancy', 'My invoice total does not match the quote.', 'idem-cust-create-1', '00000000-0000-0000-0000-000000287010', 'Customer A1')).id <> v_ticket.id then
    raise exception 'expected idempotent replay to return the same ticket';
  end if;

  raise notice 'PASS: customer self-service creation + opening message + idempotent replay (ticket %)', v_ticket.ticket_number;
end $$;

\echo '>> 3. forged/unowned account id rejected -- same error whether the account exists (but is not theirs) or does not exist at all'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tkc1');
  v_account_b uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Customer Account B');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'CAT-BILLING');
  v_err_real text;
  v_err_fake text;
begin
  begin
    perform app.create_customer_ticket(v_tenant1, v_account_b, v_category, 'normal', 'x', 'x', 'idem-forge-real', '00000000-0000-0000-0000-000000287010', 'Customer A1');
  exception when others then v_err_real := sqlerrm;
  end;
  begin
    perform app.create_customer_ticket(v_tenant1, '00000000-0000-0000-0000-000000009999', v_category, 'normal', 'x', 'x', 'idem-forge-fake', '00000000-0000-0000-0000-000000287010', 'Customer A1');
  exception when others then v_err_fake := sqlerrm;
  end;
  if v_err_real is null or v_err_fake is null then
    raise exception 'expected both forged-account attempts to fail: real=% fake=%', v_err_real, v_err_fake;
  end if;
  if v_err_real not like 'account_not_available:%' or v_err_fake not like 'account_not_available:%' then
    raise exception 'expected account_not_available for both: real=% fake=%', v_err_real, v_err_fake;
  end if;
  raise notice 'PASS: a real-but-unowned account id and a genuinely nonexistent account id are indistinguishable (both account_not_available)';
end $$;

\echo '>> 4. cross-tenant account-id forgery: tenant2 customer cannot use a tenant1 account id, even scoped to their own tenant call'
do $$
declare
  v_tenant2 uuid := (select id from app.tenants where slug = 'tkc2');
  v_tenant1 uuid := (select id from app.tenants where slug = 'tkc1');
  v_account_a uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Customer Account A');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'CAT-BILLING');
  v_failed boolean := false;
begin
  begin
    perform app.create_customer_ticket(v_tenant2, v_account_a, v_category, 'normal', 'x', 'x', 'idem-cross-tenant', '00000000-0000-0000-0000-000000287022', 'Customer T2');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'account_not_available:%' then
      raise exception 'expected account_not_available, got: %', sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'expected cross-tenant account forgery to fail';
  end if;
  raise notice 'PASS: cross-tenant account-id forgery rejected';
end $$;

\echo '>> 5. non-customer-visible category is rejected for customer creation'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tkc1');
  v_account_a uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Customer Account A');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'CAT-INTERNAL');
  v_failed boolean := false;
begin
  begin
    perform app.create_customer_ticket(v_tenant1, v_account_a, v_category, 'normal', 'x', 'x', 'idem-notvisible', '00000000-0000-0000-0000-000000287010', 'Customer A1');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'category_not_available:%' then
      raise exception 'expected category_not_available, got: %', sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'expected non-customer-visible category to be rejected';
  end if;
  raise notice 'PASS: a non-customer-visible category cannot be used for customer creation';
end $$;

\echo '>> 6. staff-side projection (get_ticket/list_tickets) sees the customer ticket with account name resolved; staff RPC refuses a customer_user caller'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tkc1');
  v_ticket_id uuid := (select id from app.tickets where tenant_id = v_tenant1 and channel = 'customer' and subject = 'Invoice discrepancy');
  v_detail record;
  v_list_count integer;
  v_staff_as_customer_count integer;
begin
  select * into v_detail from app.get_ticket(v_ticket_id, '00000000-0000-0000-0000-000000287002');
  if v_detail.id is null then
    raise exception 'expected staff to see the customer ticket via get_ticket';
  end if;
  if v_detail.requester_name <> 'Customer Account A' or v_detail.requester_employee_id is not null then
    raise exception 'expected requester_name=Customer Account A and null requester_employee_id, got name=% employee=%', v_detail.requester_name, v_detail.requester_employee_id;
  end if;
  if v_detail.queue_code is null then
    raise exception 'expected the staff projection to still show queue_code';
  end if;

  select count(*) into v_list_count from app.list_tickets(v_tenant1, '00000000-0000-0000-0000-000000287002', null, null, null, null, null, 50, null) t where t.id = v_ticket_id;
  if v_list_count <> 1 then
    raise exception 'expected staff list_tickets to include the customer ticket exactly once, got %', v_list_count;
  end if;

  -- The staff RPC must refuse a customer_user-layer caller entirely, even
  -- for their OWN ticket -- app.can_access_ticket would now legitimately
  -- admit them structurally, but get_ticket is the STAFF projection.
  select count(*) into v_staff_as_customer_count from app.get_ticket(v_ticket_id, '00000000-0000-0000-0000-000000287010');
  if v_staff_as_customer_count <> 0 then
    raise exception 'expected the staff get_ticket RPC to refuse a customer_user-layer caller, got % rows', v_staff_as_customer_count;
  end if;

  raise notice 'PASS: staff projection sees the customer ticket (account name resolved via LEFT JOIN); the staff RPC itself refuses a customer_user-layer caller';
end $$;

\echo '>> 7. customer-safe projection: own ticket visible, no queue/assignee identity, internal notes structurally absent'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tkc1');
  v_ticket_id uuid := (select id from app.tickets where tenant_id = v_tenant1 and channel = 'customer' and subject = 'Invoice discrepancy');
  v_detail record;
  v_reply app.ticket_messages;
  v_internal_note app.ticket_messages;
  v_msg_count integer;
  v_internal_leak_count integer;
begin
  select * into v_detail from app.get_customer_ticket(v_ticket_id, '00000000-0000-0000-0000-000000287010');
  if v_detail.id is null then
    raise exception 'expected the ticket''s own customer to see it via get_customer_ticket';
  end if;
  if v_detail.account_name <> 'Customer Account A' then
    raise exception 'expected account_name=Customer Account A, got %', v_detail.account_name;
  end if;

  -- Customer reply via the dedicated wrapper.
  v_reply := app.reply_to_customer_ticket(v_ticket_id, 'Any update on this?', null, 'idem-cust-reply-1', '00000000-0000-0000-0000-000000287010', 'Customer A1');
  if v_reply.visibility <> 'public' or v_reply.author_role <> 'requester' then
    raise exception 'expected a public requester-authored reply, got visibility=% role=%', v_reply.visibility, v_reply.author_role;
  end if;

  -- Staff posts one public reply and one internal note.
  perform app.reply_to_ticket(v_ticket_id, 'Looking into this now.', 'public', null, 'idem-staff-reply-1', '00000000-0000-0000-0000-000000287002', 'Staff One');
  v_internal_note := app.reply_to_ticket(v_ticket_id, 'INTERNAL-MARKER: escalate to billing team, customer is a VIP.', 'internal', null, 'idem-staff-note-1', '00000000-0000-0000-0000-000000287002', 'Staff One');

  select count(*) into v_msg_count from app.list_customer_ticket_messages(v_ticket_id, '00000000-0000-0000-0000-000000287010', 100, null);
  if v_msg_count <> 3 then
    raise exception 'expected exactly 3 public messages (opening + customer reply + staff public reply) visible to the customer, got %', v_msg_count;
  end if;
  select count(*) into v_internal_leak_count from app.list_customer_ticket_messages(v_ticket_id, '00000000-0000-0000-0000-000000287010', 100, null) m where m.id = v_internal_note.id;
  if v_internal_leak_count <> 0 then
    raise exception 'CRITICAL: internal note leaked into the customer-facing message list';
  end if;

  -- The staff-authored public reply is labeled generically, never the real
  -- staff name.
  if not exists (select 1 from app.list_customer_ticket_messages(v_ticket_id, '00000000-0000-0000-0000-000000287010', 100, null) m where m.author_role = 'staff' and m.author_display = 'Support Team') then
    raise exception 'expected the staff-authored public reply to display as Support Team, not the real staff label';
  end if;

  raise notice 'PASS: customer-safe projection correct -- own ticket visible, internal note structurally absent, staff identity genericized';
end $$;

\echo '>> 8. a second account cannot read the first account''s ticket'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tkc1');
  v_ticket_id uuid := (select id from app.tickets where tenant_id = v_tenant1 and channel = 'customer' and subject = 'Invoice discrepancy');
  v_get_count integer;
  v_list_count integer;
  v_messages_count integer;
begin
  select count(*) into v_get_count from app.get_customer_ticket(v_ticket_id, '00000000-0000-0000-0000-000000287012');
  select count(*) into v_list_count from app.list_customer_tickets(v_tenant1, '00000000-0000-0000-0000-000000287012', null, null, 50, null) t where t.id = v_ticket_id;
  select count(*) into v_messages_count from app.list_customer_ticket_messages(v_ticket_id, '00000000-0000-0000-0000-000000287012', 100, null);
  if v_get_count <> 0 or v_list_count <> 0 or v_messages_count <> 0 then
    raise exception 'CRITICAL: customer B read customer A''s ticket -- get=% list=% messages=%', v_get_count, v_list_count, v_messages_count;
  end if;
  raise notice 'PASS: cross-account isolation within the same tenant holds across get/list/messages';
end $$;

\echo '>> 9. a second member of the SAME account (cust-a2) sees the account''s ticket -- account-level access, not per-individual (decision 8)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tkc1');
  v_ticket_id uuid := (select id from app.tickets where tenant_id = v_tenant1 and channel = 'customer' and subject = 'Invoice discrepancy');
  v_get_count integer;
begin
  select count(*) into v_get_count from app.get_customer_ticket(v_ticket_id, '00000000-0000-0000-0000-000000287011');
  if v_get_count <> 1 then
    raise exception 'expected cust-a2 (same account as the requester) to see the ticket, got % rows', v_get_count;
  end if;
  raise notice 'PASS: any active customer_user membership scoped to the account sees that account''s ticket';
end $$;

\echo '>> 10. cross-tenant customer isolation'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tkc1');
  v_ticket_id uuid := (select id from app.tickets where tenant_id = v_tenant1 and channel = 'customer' and subject = 'Invoice discrepancy');
  v_get_count integer;
begin
  select count(*) into v_get_count from app.get_customer_ticket(v_ticket_id, '00000000-0000-0000-0000-000000287022');
  if v_get_count <> 0 then
    raise exception 'CRITICAL: tenant2''s customer read a tenant1 ticket';
  end if;
  raise notice 'PASS: cross-tenant customer isolation holds';
end $$;

\echo '>> 11. revoked customer_user membership loses access immediately'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tkc1');
  v_ticket_id uuid := (select id from app.tickets where tenant_id = v_tenant1 and channel = 'customer' and subject = 'Invoice discrepancy');
  v_membership_id uuid;
  v_before_count integer;
  v_after_count integer;
begin
  select id into v_membership_id from app.principal_memberships where auth_user_id = '00000000-0000-0000-0000-000000287011' and layer = 'customer_user' and status = 'active';
  select count(*) into v_before_count from app.get_customer_ticket(v_ticket_id, '00000000-0000-0000-0000-000000287011');
  if v_before_count <> 1 then
    raise exception 'expected cust-a2 to have access before revocation';
  end if;

  perform app.revoke_principal_membership(v_membership_id, 'test revocation', 'tester');

  select count(*) into v_after_count from app.get_customer_ticket(v_ticket_id, '00000000-0000-0000-0000-000000287011');
  if v_after_count <> 0 then
    raise exception 'CRITICAL: revoked customer_user membership still has access';
  end if;
  raise notice 'PASS: revoked customer_user membership loses access immediately (live query, no caching)';
end $$;

\echo '>> 12. customer cannot force an internal-visibility message through the underlying reply_to_ticket RPC directly'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tkc1');
  v_ticket_id uuid := (select id from app.tickets where tenant_id = v_tenant1 and channel = 'customer' and subject = 'Invoice discrepancy');
  v_failed boolean := false;
begin
  begin
    perform app.reply_to_ticket(v_ticket_id, 'trying to sneak an internal note', 'internal', null, 'idem-cust-sneak-internal', '00000000-0000-0000-0000-000000287010', 'Customer A1');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'insufficient_authority%' then
      raise exception 'expected insufficient_authority, got: %', sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'CRITICAL: a customer posted an internal-visibility message';
  end if;
  raise notice 'PASS: a customer cannot post an internal-visibility message via any path';
end $$;

\echo '>> 13. close/reopen-as-configured: customer self-cancel, then staff resolves+closes, customer reopens -- all through the SAME generic transition RPC'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tkc1');
  v_account_a uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Customer Account A');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'CAT-BILLING');
  v_ticket app.tickets;
  v_after app.tickets;
  v_failed boolean := false;
begin
  v_ticket := app.create_customer_ticket(v_tenant1, v_account_a, v_category, 'normal', 'Second issue', 'Please help.', 'idem-second-issue', '00000000-0000-0000-0000-000000287010', 'Customer A1');

  -- Customer self-cancel (new -> cancelled, requester_allowed).
  v_after := app.transition_ticket_status(v_ticket.id, v_ticket.record_version, 'cancelled', 'no longer needed', '00000000-0000-0000-0000-000000287010', 'Customer A1');
  if v_after.status <> 'cancelled' then
    raise exception 'expected customer self-cancel to succeed';
  end if;

  -- A customer may NOT resolve/close (staff-only, TKT:Close-gated) --
  -- exercised on a fresh ticket since cancelled is terminal.
  v_ticket := app.create_customer_ticket(v_tenant1, v_account_a, v_category, 'normal', 'Third issue', 'Please help again.', 'idem-third-issue', '00000000-0000-0000-0000-000000287010', 'Customer A1');
  v_after := app.transition_ticket_status(v_ticket.id, v_ticket.record_version, 'open', null, '00000000-0000-0000-0000-000000287002', 'Staff One');
  begin
    perform app.transition_ticket_status(v_after.id, v_after.record_version, 'resolved', 'trying to self-resolve', '00000000-0000-0000-0000-000000287010', 'Customer A1');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'insufficient_authority%' then
      raise exception 'expected insufficient_authority, got: %', sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'CRITICAL: a customer resolved their own ticket without TKT:Close';
  end if;

  -- Staff resolves and closes; customer reopens (resolved -> open,
  -- requester_allowed).
  v_after := app.transition_ticket_status(v_after.id, v_after.record_version, 'resolved', 'fixed the billing record', '00000000-0000-0000-0000-000000287002', 'Staff One');
  v_after := app.transition_ticket_status(v_after.id, v_after.record_version, 'closed', null, '00000000-0000-0000-0000-000000287002', 'Staff One');
  v_after := app.transition_ticket_status(v_after.id, v_after.record_version, 'open', 'this is not actually fixed', '00000000-0000-0000-0000-000000287010', 'Customer A1');
  if v_after.status <> 'open' or v_after.reopen_count <> 1 then
    raise exception 'expected customer reopen to succeed and increment reopen_count, got status=% reopen_count=%', v_after.status, v_after.reopen_count;
  end if;

  raise notice 'PASS: close/reopen-as-configured reached through app.transition_ticket_status verbatim -- no new customer-specific transition RPC';
end $$;

\echo '>> 14. watcher management is staff-only for a customer-channel ticket'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tkc1');
  v_ticket_id uuid := (select id from app.tickets where tenant_id = v_tenant1 and channel = 'customer' and subject = 'Invoice discrepancy');
  v_staff1_emp uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@tkc1.test');
  v_failed boolean := false;
begin
  begin
    perform app.add_ticket_watcher(v_ticket_id, v_staff1_emp, '00000000-0000-0000-0000-000000287010', 'Customer A1');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'insufficient_authority%' then
      raise exception 'expected insufficient_authority, got: %', sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'CRITICAL: a customer added a watcher to their own ticket';
  end if;

  -- Staff CAN add a watcher to a customer-channel ticket.
  perform app.add_ticket_watcher(v_ticket_id, v_staff1_emp, '00000000-0000-0000-0000-000000287002', 'Staff One');
  raise notice 'PASS: watcher management is staff-only on a customer-channel ticket; staff itself can still watch';
end $$;

\echo '>> 15. raw-table RLS admits ZERO rows to a customer_user-layer actor on tickets/messages/watchers/events -- RPC-only access (decision 7)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tkc1');
  v_ticket_id uuid := (select id from app.tickets where tenant_id = v_tenant1 and channel = 'customer' and subject = 'Invoice discrepancy');
  v_tickets_count integer;
  v_messages_count integer;
begin
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000287010", "role": "authenticated"}', false);
  set role authenticated;

  select count(*) into v_tickets_count from app.tickets where id = v_ticket_id;
  select count(*) into v_messages_count from app.ticket_messages where ticket_id = v_ticket_id;

  reset role;
  perform set_config('request.jwt.claims', 'null', false);

  if v_tickets_count <> 0 or v_messages_count <> 0 then
    raise exception 'CRITICAL: a customer_user-layer actor read tickets/messages via raw table RLS -- tickets=% messages=%', v_tickets_count, v_messages_count;
  end if;
  raise notice 'PASS: raw-table RLS excludes a customer_user-layer actor entirely, even for their own account''s ticket -- the RPC layer is the only sanctioned read path';
end $$;

\echo '>> 16. an internal-channel ticket is unreachable through every customer RPC (channel filter applied before scope), even for a real tenant employee who somehow also holds a customer_user membership on some account'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tkc1');
  v_internal_ticket_id uuid;
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'CAT-INTERNAL');
  v_queue uuid := (select id from app.ticket_queues where tenant_id = v_tenant1 and code = 'Q-SUP');
  v_staff1_emp uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@tkc1.test');
  v_get_count integer;
  v_messages_count integer;
begin
  v_internal_ticket_id := (app.create_ticket_for_employee(v_tenant1, v_staff1_emp, v_category, v_queue, 'normal', 'Internal only ticket', 'staff-only body', 'idem-internal-only', '00000000-0000-0000-0000-000000287002', 'staff1')).id;

  -- staff1 (a real employee, structurally staff-eligible) has no customer
  -- account scope at all -- confirm the customer RPCs return zero rows for
  -- this genuinely internal ticket id regardless.
  select count(*) into v_get_count from app.get_customer_ticket(v_internal_ticket_id, '00000000-0000-0000-0000-000000287002');
  select count(*) into v_messages_count from app.list_customer_ticket_messages(v_internal_ticket_id, '00000000-0000-0000-0000-000000287002', 100, null);
  if v_get_count <> 0 or v_messages_count <> 0 then
    raise exception 'CRITICAL: an internal-channel ticket leaked through a customer RPC';
  end if;
  raise notice 'PASS: an internal-channel ticket id is structurally unreachable through every customer RPC';
end $$;

\echo '>> 17. linked-record leakage is N/A (Prompt 292 not shipped) -- structural proof that no customer projection carries a shipment/invoice/warehouse/vendor column'
do $$
declare
  v_leak_count integer;
begin
  select count(*) into v_leak_count
  from information_schema.parameters p
  join information_schema.routines r on r.specific_name = p.specific_name and r.routine_schema = p.specific_schema
  where r.routine_schema = 'app'
    and r.routine_name in ('get_customer_ticket', 'list_customer_tickets', 'list_customer_ticket_messages')
    and p.parameter_mode = 'OUT'
    and (p.parameter_name ilike '%shipment%' or p.parameter_name ilike '%invoice%' or p.parameter_name ilike '%warehouse%' or p.parameter_name ilike '%vendor%');
  if v_leak_count <> 0 then
    raise exception 'CRITICAL: a customer-facing projection carries a linked-record column ahead of Prompt 292 ever defining what customer access to it should be';
  end if;
  raise notice 'PASS: no customer-facing projection carries a shipment/invoice/warehouse/vendor column (Prompt 292/Linked Records has not shipped -- ISS tracked, not fabricated here)';
end $$;

\echo '>> 18. list_customer_accounts_for_actor / list_customer_ticket_categories reachable (C-02 defense: every new RPC actually called)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tkc1');
  v_accounts_count integer;
  v_categories_count integer;
begin
  select count(*) into v_accounts_count from app.list_customer_accounts_for_actor(v_tenant1, '00000000-0000-0000-0000-000000287012');
  if v_accounts_count <> 1 then
    raise exception 'expected cust-b1 to see exactly 1 account, got %', v_accounts_count;
  end if;
  select count(*) into v_categories_count from app.list_customer_ticket_categories(v_tenant1, '00000000-0000-0000-0000-000000287012');
  if v_categories_count <> 1 then
    raise exception 'expected exactly 1 customer-visible category (CAT-BILLING), got %', v_categories_count;
  end if;
  raise notice 'PASS: list_customer_accounts_for_actor / list_customer_ticket_categories reachable and scoped correctly';
end $$;

\echo '>> 19. schema-privilege defense in depth (anon has zero access to the new functions)'
do $$
begin
  if has_function_privilege('anon', 'app.create_customer_ticket(uuid, uuid, uuid, text, text, text, text, uuid, text)', 'execute') then
    raise exception 'CRITICAL: anon can execute app.create_customer_ticket';
  end if;
  if has_function_privilege('anon', 'app.get_customer_ticket(uuid, uuid)', 'execute') then
    raise exception 'CRITICAL: anon can execute app.get_customer_ticket';
  end if;
  raise notice 'PASS: anon has zero schema privilege on the new customer ticket functions';
end $$;

\echo '>> 20. CPL-325 file-privacy hardening: a ticket attachment corrected to infected post-attach (the disclosed RPD-022 exception path) is no longer returned by either app.list_customer_ticket_messages or app.list_ticket_messages, and every exposure (granted and denied) is logged to app.file_access_logs'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tkc1');
  v_ticket_id uuid := (select id from app.tickets where tenant_id = v_tenant1 and channel = 'customer' and subject = 'Invoice discrepancy');
  v_def_version uuid;
  v_file_clean uuid;
  v_msg app.ticket_messages;
  v_customer_row record;
  v_staff_row record;
  v_granted_count integer;
  v_denied_count integer;
begin
  -- Publish a document-type definition for 'ticket_attachment' so
  -- app.initiate_file_upload can resolve it (mirrors scripts/db-tests/
  -- ticketing-internal.sql's own established fixture pattern exactly).
  v_def_version := (app.create_config_draft(
    'document:ticket_attachment', v_tenant1, 'tenant', null, '00000000-0000-0000-0000-000000287001', 'tester'
  )).id;
  perform app.set_config_items(v_def_version, jsonb_build_array(
    jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('image/png', 'application/pdf')),
    jsonb_build_object('key', 'max_size_bytes', 'value', to_jsonb(5000000)),
    jsonb_build_object('key', 'retention_class', 'value', to_jsonb('operational_contract_plus_90d'::text)),
    jsonb_build_object('key', 'default_classification', 'value', to_jsonb('internal'::text)),
    jsonb_build_object('key', 'legal_hold_eligible', 'value', to_jsonb(false))
  ), '00000000-0000-0000-0000-000000287001', 'tester');
  perform app.publish_document_type_definition(v_def_version, '00000000-0000-0000-0000-000000287001', now(), 'tester');

  v_file_clean := (app.initiate_file_upload(v_tenant1, 'ticket_attachment', 'ticket', v_ticket_id, 'evidence.png', 'image/png', 1024, null, false, null, '{}', null, 'idem-cpl325-file-clean', '00000000-0000-0000-0000-000000287010', 'Customer A1')).id;
  perform app.record_file_scan_result(v_file_clean, 'clean', 'test-scanner', '00000000-0000-0000-0000-000000287010', 'Customer A1');

  v_msg := app.reply_to_customer_ticket(v_ticket_id, 'here is my evidence photo', array[v_file_clean], 'idem-cpl325-reply-1', '00000000-0000-0000-0000-000000287010', 'Customer A1');

  -- Before correction: attached because clean, visible through both the
  -- customer and staff projections.
  select * into v_customer_row from app.list_customer_ticket_messages(v_ticket_id, '00000000-0000-0000-0000-000000287010', 100, null) m where m.id = v_msg.id;
  if v_customer_row.attachment_file_ids <> array[v_file_clean] then
    raise exception 'assertion failed: expected the clean file to be visible pre-correction (customer), got %', v_customer_row.attachment_file_ids;
  end if;
  select * into v_staff_row from app.list_ticket_messages(v_ticket_id, '00000000-0000-0000-0000-000000287002', 100, null) m where m.id = v_msg.id;
  if v_staff_row.attachment_file_ids <> array[v_file_clean] then
    raise exception 'assertion failed: expected the clean file to be visible pre-correction (staff), got %', v_staff_row.attachment_file_ids;
  end if;

  -- Simulate the exact RPD-022 Supreme-Admin post-completion correction
  -- scenario CPL-307's own db-test already exercises for ePOD
  -- (scripts/db-tests/customer-epod-access.sql) -- direct table correction,
  -- the only way this state is reachable today, matching that migration's
  -- own disclosed RPD-022 residual-risk reasoning.
  update app.files set malware_scan_status = 'infected' where id = v_file_clean;

  select * into v_customer_row from app.list_customer_ticket_messages(v_ticket_id, '00000000-0000-0000-0000-000000287010', 100, null) m where m.id = v_msg.id;
  if v_customer_row.attachment_file_ids <> '{}'::uuid[] then
    raise exception 'CRITICAL: expected the now-infected file to be filtered out of the customer projection, got %', v_customer_row.attachment_file_ids;
  end if;
  if v_customer_row.body <> 'here is my evidence photo' then
    raise exception 'assertion failed: expected the message itself (body) to remain visible even though its attachment was filtered, got %', v_customer_row.body;
  end if;

  select * into v_staff_row from app.list_ticket_messages(v_ticket_id, '00000000-0000-0000-0000-000000287002', 100, null) m where m.id = v_msg.id;
  if v_staff_row.attachment_file_ids <> '{}'::uuid[] then
    raise exception 'CRITICAL: expected the now-infected file to be filtered out of the staff projection, got %', v_staff_row.attachment_file_ids;
  end if;

  -- Every exposure (pre- and post-correction, both projections) is logged.
  select count(*) into v_granted_count from app.file_access_logs where file_id = v_file_clean and result = 'granted';
  if v_granted_count < 2 then
    raise exception 'assertion failed: expected at least 2 granted app.file_access_logs rows (customer + staff pre-correction reads), got %', v_granted_count;
  end if;
  select count(*) into v_denied_count from app.file_access_logs where file_id = v_file_clean and result = 'denied' and reason = 'document_infected_quarantined';
  if v_denied_count < 2 then
    raise exception 'assertion failed: expected at least 2 denied app.file_access_logs rows (customer + staff post-correction reads) with reason=document_infected_quarantined, got %', v_denied_count;
  end if;

  raise notice 'PASS: a ticket attachment corrected to infected post-attach is filtered out of both list_customer_ticket_messages and list_ticket_messages, and every exposure (granted and denied) is logged to app.file_access_logs';
end $$;

\echo '>> all ticketing-customer (HRT-287) assertions passed'
