-- Real, executable test evidence for HRT-288 (Tenant-to-CargoGrid Helpdesk,
-- CG-S12-HRT-016) -- run via `pnpm run db:test` against a real, disposable
-- Postgres database (and standalone via psql, per ISS-2026-059/077's
-- documented time-of-day workaround, since a full harness run may abort
-- before reaching this alphabetically-late file).
--
-- Own, separate file from scripts/db-tests/ticketing-internal.sql /
-- ticketing-customer.sql (mirrors HRT-287's own "extend vs. new file"
-- decision): a THIRD genuinely new principal shape (the tenant itself as
-- requester; CargoGrid Platform support as staff) deserves its own fixture,
-- leaving both prior files as frozen, byte-for-byte regression proof.
--
-- Self-contained: own fresh, unclaimed UUID range
-- (00000000-0000-0000-0000-0000002880xx). Tenant slugs `tkh1`/`tkh2`
-- (grep-verified unclaimed). Two tenants, plus a NEW principal type this
-- prompt introduces: Supreme Admin as Platform support staff (`app.
-- is_supreme_admin`), correlated against a real PLT-115 support access
-- grant (never merged with it).
--
-- Covers, live: tenant-side helpdesk creation (tenant_admin AND a plain
-- TKT:Edit-holding org_user, NOT tenant_admin -- both count as "authorized
-- tenant user"), a bystander employee with neither rejected; category
-- helpdesk-visibility gating; a Platform Supreme Admin who is NOT enrolled
-- in the tenant is REJECTED from creating a helpdesk case as "the tenant"
-- (the RPD-022-bypass defect this migration's own header discloses finding
-- and fixing during design); tenant-visible-vs-Platform-internal message
-- distinction (a tenant's own TKT:Edit holder cannot read/post internal
-- notes on their own helpdesk case, Supreme Admin can); staff-facing
-- get_ticket/list_tickets/list_ticket_messages/list_ticket_watchers/
-- list_ticket_events all refuse a helpdesk ticket to a non-Supreme-Admin
-- caller (even the ticket's own tenant-side requester party) and admit a
-- Supreme Admin (LEFT JOIN fix, queue_code null); raw-table RLS excludes a
-- helpdesk ticket from EVERY non-Supreme-Admin actor; redact_ticket_message/
-- assign_ticket/transfer_ticket_queue/update_ticket_classification all
-- explicitly reject a helpdesk ticket; the dedicated
-- assign_helpdesk_ticket/transfer_helpdesk_support_queue/update_helpdesk_
-- ticket_classification/link_helpdesk_support_grant Supreme-Admin-gated
-- RPCs; cross-tenant isolation; the support-grant CORRELATION-NOT-ACCESS
-- guarantee (a forged case ref rejected; a real, even EXPIRED/REVOKED grant
-- correlates for display; an actor holding an active support grant but not
-- Supreme Admin gains ZERO helpdesk-staff status from it; linking/
-- unlinking a case ref never creates/approves/starts/extends/revokes a
-- grant or session); cross-tenant Platform queue view; idempotent replay;
-- re-running ticketing-internal.sql/ticketing-customer.sql afterward
-- (separately, by run.sh's own alphabetical/full-suite execution) proves
-- both prior channels are genuinely unaffected.

\set ON_ERROR_STOP on

\echo '>> fixture'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_admin_role uuid; v_admin_draft app.role_versions;
  v_company uuid; v_branch uuid; v_dept uuid;
  v_bystander_emp uuid;
  v_category_support uuid; v_category_novisible uuid;
  v_queue_billing uuid; v_queue_tech uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000288001', 'admin@tkh1.test'),
    ('00000000-0000-0000-0000-000000288002', 'edit-staff@tkh1.test'),
    ('00000000-0000-0000-0000-000000288003', 'bystander@tkh1.test'),
    ('00000000-0000-0000-0000-000000288021', 'admin@tkh2.test'),
    ('00000000-0000-0000-0000-000000288090', 'supreme@platform.test'),
    ('00000000-0000-0000-0000-000000288091', 'supreme2@platform.test'),
    ('00000000-0000-0000-0000-000000288092', 'support-agent@platform.test');

  perform app.provision_tenant('tkh1', 'Ticket Helpdesk Co 1', 'idem-tkh1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'tkh1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.provision_tenant('tkh2', 'Ticket Helpdesk Co 2', 'idem-tkh2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'tkh2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000288001', 'admin@tkh1.test', 'Tkh1 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@tkh1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000288001', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000288002', 'edit-staff@tkh1.test', 'Tkh1 Edit Staff', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'edit-staff@tkh1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000288003', 'bystander@tkh1.test', 'Tkh1 Bystander', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'bystander@tkh1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000288021', 'admin@tkh2.test', 'Tkh2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@tkh2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000288021', 'tenant_admin', v_tenant2, null, 'tester');

  -- Global Supreme Admin principals (Platform support staff, per this
  -- migration's own decision 3 -- Supreme-Admin-only, no dedicated support
  -- role). supreme2 is a SECOND supreme admin (assignment target).
  -- support-agent holds NO principal_membership of any kind -- an ordinary
  -- auth.users identity who will separately be granted a PLT-115 support
  -- access GRANT (decision 7's own correlation-not-staff-status proof).
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000288090', 'supreme_admin', null, null, 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000288091', 'supreme_admin', null, null, 'tester');

  -- HR role: HRS Create/Edit/Approve/Export/View -- needed by admin to
  -- drive the employee-lifecycle fixture below (mirrors HRT-286/287's own
  -- fixture precedent exactly).
  declare
    v_hr_role uuid; v_hr_draft app.role_versions;
  begin
    v_hr_role := (app.create_role(v_tenant1, 'HR Admin', 'HRS Create/Edit/Approve/Export/View', 'tester')).id;
    v_hr_draft := app.create_role_version(v_hr_role, 'tester');
    perform app.set_role_version_permissions(v_hr_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('Create', 'Edit', 'Approve', 'Export', 'View')), 'tester');
    perform app.publish_role_version(v_hr_draft.id, now(), 'tester');
    perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_hr_role and status = 'published'), '00000000-0000-0000-0000-000000288001', '00000000-0000-0000-0000-000000288001', 'tester');
  end;

  -- TKT:Edit role, held ONLY by edit-staff (an org_user, NOT tenant_admin)
  -- -- proves "authorized tenant user" admits a TKT:Edit holder too, not
  -- only tenant_admin (decision 4).
  v_admin_role := (app.create_role(v_tenant1, 'Ticket Config Admin', 'TKT Edit', 'tester')).id;
  v_admin_draft := app.create_role_version(v_admin_role, 'tester');
  perform app.set_role_version_permissions(v_admin_draft.id, array(select id from app.permissions where resource_module_code = 'TKT' and action in ('Edit', 'Override')), 'tester');
  perform app.publish_role_version(v_admin_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_admin_role and status = 'published'), '00000000-0000-0000-0000-000000288002', '00000000-0000-0000-0000-000000288001', 'tester');

  v_company := (app.create_org_unit(v_tenant1, 'company', null, 'CO-TKH1', 'Tkh1 Co', 'tester')).id;
  v_branch := (app.create_org_unit(v_tenant1, 'branch', v_company, 'BR-TKH1', 'Tkh1 Branch', 'tester')).id;
  v_dept := (app.create_org_unit(v_tenant1, 'department', v_branch, 'DEPT-OPS', 'Ops', 'tester')).id;

  -- bystander is a real employee with NO tenant_admin/TKT:Edit authority --
  -- proves an ordinary employee is NOT "authorized" merely by being on the
  -- payroll.
  perform app.create_employee_draft(v_tenant1, 'Tkh1 Bystander', 'full_time', 'bystanderwork@tkh1.test', 'bystanderp@tkh1.test', '0900000002', null, null, null, '2024-01-01', v_company, v_branch, v_dept, 'Ops Clerk', null, (select id from app.users where email = 'bystander@tkh1.test'), null, 'hr_created', 'idem-bystander-tkh1', '00000000-0000-0000-0000-000000288001', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'bystanderwork@tkh1.test'), 'Emergency Contact for Bystander', 'spouse', '0910000002', null, true, '00000000-0000-0000-0000-000000288001', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'bystanderwork@tkh1.test'), 1, '00000000-0000-0000-0000-000000288001', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'bystanderwork@tkh1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000288001', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'bystanderwork@tkh1.test'), 3, '00000000-0000-0000-0000-000000288001', 'tester');
  v_bystander_emp := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'bystanderwork@tkh1.test');

  -- Two categories: one helpdesk_visible, one not.
  v_category_support := (app.create_ticket_category(v_tenant1, 'CAT-SUPPORT', 'Platform Support', null, '00000000-0000-0000-0000-000000288002', 'edit-staff')).id;
  perform app.set_ticket_category_helpdesk_visibility(v_category_support, true, '00000000-0000-0000-0000-000000288002', 'edit-staff');
  v_category_novisible := (app.create_ticket_category(v_tenant1, 'CAT-NOTVISIBLE', 'Not Helpdesk Visible', null, '00000000-0000-0000-0000-000000288002', 'edit-staff')).id;

  -- Two Platform-global support queues, created by a Supreme Admin.
  v_queue_billing := (app.create_support_queue('SQ-BILLING', 'Billing Support', null, '00000000-0000-0000-0000-000000288090', 'supreme')).id;
  v_queue_tech := (app.create_support_queue('SQ-TECH', 'Technical Support', null, '00000000-0000-0000-0000-000000288090', 'supreme')).id;

  raise notice 'fixture ready: tenant1=%, tenant2=%, category_support=%, category_novisible=%, queue_billing=%, queue_tech=%, bystander_emp=%',
    v_tenant1, v_tenant2, v_category_support, v_category_novisible, v_queue_billing, v_queue_tech, v_bystander_emp;
end $$;

\echo '>> 1. tenant-side helpdesk creation: tenant_admin succeeds, category/queue shape correct, opening message present'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tkh1');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'CAT-SUPPORT');
  v_ticket app.tickets;
  v_msg_count integer;
begin
  v_ticket := app.create_helpdesk_ticket(v_tenant1, v_category, 'normal', 'high', 'Billing', 'production', 'PO-4471', 'Invoice totals mismatch', 'Our invoice does not match the quoted rate card.', 'idem-hd-create-1', '00000000-0000-0000-0000-000000288001', 'Tkh1 Admin');
  if v_ticket.channel <> 'helpdesk' or v_ticket.requester_employee_id is not null or v_ticket.requester_customer_account_id is not null then
    raise exception 'expected a helpdesk ticket with NEITHER requester_employee_id NOR requester_customer_account_id set, got channel=% employee=% account=%', v_ticket.channel, v_ticket.requester_employee_id, v_ticket.requester_customer_account_id;
  end if;
  if v_ticket.queue_id is not null then
    raise exception 'expected queue_id to be null at creation (Platform triage-only), got %', v_ticket.queue_id;
  end if;
  if v_ticket.severity <> 'high' or v_ticket.product_area <> 'Billing' or v_ticket.environment <> 'production' or v_ticket.external_reference <> 'PO-4471' then
    raise exception 'expected severity/product_area/environment/external_reference to be populated as given';
  end if;
  select count(*) into v_msg_count from app.ticket_messages where ticket_id = v_ticket.id;
  if v_msg_count <> 1 then
    raise exception 'expected exactly one opening message, got %', v_msg_count;
  end if;

  -- Idempotent replay: identical tuple + key returns the SAME ticket.
  if (app.create_helpdesk_ticket(v_tenant1, v_category, 'normal', 'high', 'Billing', 'production', 'PO-4471', 'Invoice totals mismatch', 'Our invoice does not match the quoted rate card.', 'idem-hd-create-1', '00000000-0000-0000-0000-000000288001', 'Tkh1 Admin')).id <> v_ticket.id then
    raise exception 'expected idempotent replay to return the same ticket';
  end if;

  raise notice 'PASS: tenant_admin opened a helpdesk case, queue null at creation, metadata populated, idempotent replay (ticket %)', v_ticket.ticket_number;
end $$;

\echo '>> 2. a TKT:Edit-holding org_user (NOT tenant_admin) is ALSO an authorized tenant user'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tkh1');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'CAT-SUPPORT');
  v_ticket app.tickets;
begin
  v_ticket := app.create_helpdesk_ticket(v_tenant1, v_category, 'normal', null, null, null, null, 'Config question', 'How do we configure SSO?', 'idem-hd-create-editstaff', '00000000-0000-0000-0000-000000288002', 'Edit Staff');
  if v_ticket.channel <> 'helpdesk' then
    raise exception 'expected a helpdesk ticket from the TKT:Edit-holding org_user';
  end if;
  raise notice 'PASS: a TKT:Edit holder (not tenant_admin) is also an authorized tenant user (ticket %)', v_ticket.ticket_number;
end $$;

\echo '>> 3. a bystander employee (no tenant_admin/TKT:Edit) is REJECTED'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tkh1');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'CAT-SUPPORT');
  v_failed boolean := false;
begin
  begin
    perform app.create_helpdesk_ticket(v_tenant1, v_category, 'normal', null, null, null, null, 'x', 'x', 'idem-hd-bystander', '00000000-0000-0000-0000-000000288003', 'Bystander');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'insufficient_authority%' then
      raise exception 'expected insufficient_authority, got: %', sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'CRITICAL: an unauthorized tenant employee opened a helpdesk case';
  end if;
  raise notice 'PASS: an ordinary employee (no tenant_admin/TKT:Edit) cannot open a helpdesk case merely by being on the payroll';
end $$;

\echo '>> 4. a Platform Supreme Admin, NOT enrolled in tkh1, is REJECTED from opening a helpdesk case AS the tenant (the RPD-022-bypass defect this migration''s own header discloses finding and fixing)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tkh1');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'CAT-SUPPORT');
  v_failed boolean := false;
  v_direct_check boolean;
begin
  -- Direct check of the underlying helper: app._is_tenant_helpdesk_
  -- authorized must be false for a Supreme Admin who holds no real
  -- tenant_admin/TKT:Edit grant for tkh1 -- if app.check_ticket_authority
  -- (RPD-022-bypassing) had been reused here instead, this would
  -- incorrectly be true.
  select app._is_tenant_helpdesk_authorized(v_tenant1, '00000000-0000-0000-0000-000000288090') into v_direct_check;
  if v_direct_check then
    raise exception 'CRITICAL: app._is_tenant_helpdesk_authorized incorrectly admits a Platform Supreme Admin as the tenant-side requester party';
  end if;

  begin
    perform app.create_helpdesk_ticket(v_tenant1, v_category, 'normal', null, null, null, null, 'x', 'x', 'idem-hd-supreme-as-tenant', '00000000-0000-0000-0000-000000288090', 'Supreme');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'insufficient_authority%' then
      raise exception 'expected insufficient_authority, got: %', sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'CRITICAL: a Platform Supreme Admin opened a helpdesk case as if they were the filing tenant';
  end if;
  raise notice 'PASS: a Supreme Admin cannot masquerade as the tenant-side requester party for a tenant they hold no real tenant_admin/TKT:Edit grant in';
end $$;

\echo '>> 5. a non-helpdesk-visible category is rejected'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tkh1');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'CAT-NOTVISIBLE');
  v_failed boolean := false;
begin
  begin
    perform app.create_helpdesk_ticket(v_tenant1, v_category, 'normal', null, null, null, null, 'x', 'x', 'idem-hd-notvisible', '00000000-0000-0000-0000-000000288001', 'Tkh1 Admin');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'category_not_available%' then
      raise exception 'expected category_not_available, got: %', sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'expected a non-helpdesk-visible category to be rejected';
  end if;
  raise notice 'PASS: a non-helpdesk-visible category cannot be used to open a helpdesk case';
end $$;

\echo '>> 6. tenant-visible vs. Platform-internal message distinction: tenant cannot post/read internal; Supreme Admin can'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tkh1');
  v_ticket_id uuid := (select id from app.tickets where tenant_id = v_tenant1 and channel = 'helpdesk' and subject = 'Invoice totals mismatch');
  v_reply app.ticket_messages;
  v_internal_note app.ticket_messages;
  v_failed boolean := false;
  v_tenant_msg_count integer;
  v_internal_leak_count integer;
begin
  -- Tenant reply via the dedicated wrapper.
  v_reply := app.reply_to_helpdesk_ticket(v_ticket_id, 'Any update on this?', null, 'idem-hd-reply-1', '00000000-0000-0000-0000-000000288001', 'Tkh1 Admin');
  if v_reply.visibility <> 'public' or v_reply.author_role <> 'requester' then
    raise exception 'expected a public requester-authored reply, got visibility=% role=%', v_reply.visibility, v_reply.author_role;
  end if;

  -- Tenant cannot sneak an internal note through the underlying reply_to_ticket RPC.
  begin
    perform app.reply_to_ticket(v_ticket_id, 'trying to sneak an internal note', 'internal', null, 'idem-hd-tenant-sneak-internal', '00000000-0000-0000-0000-000000288001', 'Tkh1 Admin');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'insufficient_authority%' then
      raise exception 'expected insufficient_authority, got: %', sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'CRITICAL: a tenant posted an internal-visibility message on their own helpdesk case';
  end if;

  -- Tenant's own TKT:Edit holder ALSO cannot post an internal note (proves
  -- the tenant-wide TKT:Edit bypass is genuinely closed for helpdesk).
  v_failed := false;
  begin
    perform app.reply_to_ticket(v_ticket_id, 'trying via TKT:Edit', 'internal', null, 'idem-hd-editstaff-sneak-internal', '00000000-0000-0000-0000-000000288002', 'Edit Staff');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'insufficient_authority%' then
      raise exception 'expected insufficient_authority, got: %', sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'CRITICAL: a tenant''s own TKT:Edit holder posted an internal-visibility message on a helpdesk case (tenant-wide TKT:Edit staff bypass NOT closed for helpdesk)';
  end if;

  -- Supreme Admin (Platform support staff) posts one public reply and one
  -- internal note.
  perform app.reply_to_ticket(v_ticket_id, 'Looking into this now.', 'public', null, 'idem-hd-staff-public-1', '00000000-0000-0000-0000-000000288090', 'CargoGrid Support');
  v_internal_note := app.reply_to_ticket(v_ticket_id, 'INTERNAL-MARKER: escalate to billing, likely a rate-card sync bug.', 'internal', null, 'idem-hd-staff-internal-1', '00000000-0000-0000-0000-000000288090', 'CargoGrid Support');

  -- Tenant-safe projection: exactly 3 public messages, internal note
  -- structurally absent, staff identity genericized.
  select count(*) into v_tenant_msg_count from app.list_tenant_helpdesk_ticket_messages(v_ticket_id, '00000000-0000-0000-0000-000000288001', 100, null);
  if v_tenant_msg_count <> 3 then
    raise exception 'expected exactly 3 public messages visible to the tenant, got %', v_tenant_msg_count;
  end if;
  select count(*) into v_internal_leak_count from app.list_tenant_helpdesk_ticket_messages(v_ticket_id, '00000000-0000-0000-0000-000000288001', 100, null) m where m.id = v_internal_note.id;
  if v_internal_leak_count <> 0 then
    raise exception 'CRITICAL: Platform-internal note leaked into the tenant-facing helpdesk message list';
  end if;
  if not exists (select 1 from app.list_tenant_helpdesk_ticket_messages(v_ticket_id, '00000000-0000-0000-0000-000000288001', 100, null) m where m.author_role = 'staff' and m.author_display = 'CargoGrid Support') then
    raise exception 'expected the staff-authored public reply to display as CargoGrid Support, not the real staff label';
  end if;

  -- edit-staff (tenant TKT:Edit holder) ALSO cannot see the internal note
  -- via the tenant-safe read path (they are not the actual thread
  -- participant on THIS ticket, but even if scoped, the visibility filter
  -- is hard structural).
  select count(*) into v_internal_leak_count from app.list_tenant_helpdesk_ticket_messages(v_ticket_id, '00000000-0000-0000-0000-000000288002', 100, null) m where m.id = v_internal_note.id;
  if v_internal_leak_count <> 0 then
    raise exception 'CRITICAL: Platform-internal note leaked to a second tenant-side authorized user';
  end if;

  raise notice 'PASS: tenant (including its own TKT:Edit holder) can never post/read a Platform-internal note; Supreme Admin can post both, tenant-safe read structurally excludes internal';
end $$;

\echo '>> 7. staff-facing get_ticket/list_tickets/list_ticket_messages/list_ticket_watchers/list_ticket_events all refuse a helpdesk ticket to a non-Supreme-Admin caller, INCLUDING the ticket''s own tenant-side requester party'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tkh1');
  v_ticket_id uuid := (select id from app.tickets where tenant_id = v_tenant1 and channel = 'helpdesk' and subject = 'Invoice totals mismatch');
  v_get_count integer;
  v_list_count integer;
  v_messages_count integer;
  v_watchers_count integer;
  v_events_count integer;
begin
  select count(*) into v_get_count from app.get_ticket(v_ticket_id, '00000000-0000-0000-0000-000000288001');
  select count(*) into v_list_count from app.list_tickets(v_tenant1, '00000000-0000-0000-0000-000000288001', null, null, null, null, null, 50, null) t where t.id = v_ticket_id;
  select count(*) into v_messages_count from app.list_ticket_messages(v_ticket_id, '00000000-0000-0000-0000-000000288001', 100, null);
  select count(*) into v_watchers_count from app.list_ticket_watchers(v_ticket_id, '00000000-0000-0000-0000-000000288001');
  select count(*) into v_events_count from app.list_ticket_events(v_ticket_id, '00000000-0000-0000-0000-000000288001');
  if v_get_count <> 0 or v_list_count <> 0 or v_messages_count <> 0 or v_watchers_count <> 0 or v_events_count <> 0 then
    raise exception 'CRITICAL: the staff projection admitted the ticket''s own tenant-side requester party -- get=% list=% messages=% watchers=% events=%', v_get_count, v_list_count, v_messages_count, v_watchers_count, v_events_count;
  end if;
  raise notice 'PASS: every staff-facing internal-projection RPC refuses a helpdesk ticket to the tenant-side actor, even the ticket''s own authorized requester';
end $$;

\echo '>> 8. Supreme Admin CAN read the helpdesk ticket through the staff-facing RPCs (LEFT JOIN fix -- queue_code correctly null, not silently dropped)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tkh1');
  v_ticket_id uuid := (select id from app.tickets where tenant_id = v_tenant1 and channel = 'helpdesk' and subject = 'Invoice totals mismatch');
  v_detail record;
  v_list_count integer;
  v_messages_count integer;
begin
  select * into v_detail from app.get_ticket(v_ticket_id, '00000000-0000-0000-0000-000000288090');
  if v_detail.id is null then
    raise exception 'expected Supreme Admin to see the helpdesk ticket via get_ticket';
  end if;
  if v_detail.queue_code is not null or v_detail.queue_id is not null then
    raise exception 'expected queue_id/queue_code to be null for a helpdesk ticket, got queue_id=% queue_code=%', v_detail.queue_id, v_detail.queue_code;
  end if;
  if v_detail.channel <> 'helpdesk' or not v_detail.is_staff_viewer then
    raise exception 'expected channel=helpdesk and is_staff_viewer=true for Supreme Admin';
  end if;

  select count(*) into v_list_count from app.list_tickets(v_tenant1, '00000000-0000-0000-0000-000000288090', null, null, null, null, null, 50, null) t where t.id = v_ticket_id;
  if v_list_count <> 1 then
    raise exception 'expected Supreme Admin list_tickets to include the helpdesk ticket exactly once (LEFT JOIN fix), got %', v_list_count;
  end if;

  -- All 3 public + 1 internal = 4 messages visible to staff.
  select count(*) into v_messages_count from app.list_ticket_messages(v_ticket_id, '00000000-0000-0000-0000-000000288090', 100, null);
  if v_messages_count <> 4 then
    raise exception 'expected Supreme Admin to see all 4 messages (3 public + 1 internal), got %', v_messages_count;
  end if;

  raise notice 'PASS: Supreme Admin reads the helpdesk ticket correctly through the staff-facing RPCs, queue fields correctly null (not silently excluded by an inner join)';
end $$;

\echo '>> 9. raw-table RLS excludes a helpdesk ticket from every non-Supreme-Admin actor, even the ticket''s own tenant-side requester party'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tkh1');
  v_ticket_id uuid := (select id from app.tickets where tenant_id = v_tenant1 and channel = 'helpdesk' and subject = 'Invoice totals mismatch');
  v_tickets_count integer;
  v_messages_count integer;
begin
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000288001", "role": "authenticated"}', false);
  set role authenticated;

  select count(*) into v_tickets_count from app.tickets where id = v_ticket_id;
  select count(*) into v_messages_count from app.ticket_messages where ticket_id = v_ticket_id;

  reset role;
  perform set_config('request.jwt.claims', 'null', false);

  if v_tickets_count <> 0 or v_messages_count <> 0 then
    raise exception 'CRITICAL: the tenant-side requester party read a helpdesk ticket via raw table RLS -- tickets=% messages=%', v_tickets_count, v_messages_count;
  end if;
  raise notice 'PASS: raw-table RLS excludes a helpdesk ticket from a non-Supreme-Admin actor entirely -- the dedicated tenant-safe RPCs are the only sanctioned read path';
end $$;

\echo '>> 10. app.redact_ticket_message / app.assign_ticket / app.transfer_ticket_queue / app.update_ticket_classification all explicitly reject a helpdesk ticket'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tkh1');
  v_ticket app.tickets := (select t from app.tickets t where t.tenant_id = v_tenant1 and t.channel = 'helpdesk' and t.subject = 'Invoice totals mismatch');
  v_public_msg_id uuid := (select id from app.ticket_messages where ticket_id = v_ticket.id and visibility = 'public' and author_role = 'requester' limit 1);
  v_failed boolean;
begin
  -- edit-staff (tenant TKT:Edit) cannot redact ANY message, even a public
  -- one, on a helpdesk ticket -- Platform-staff-only.
  v_failed := false;
  begin
    perform app.redact_ticket_message(v_public_msg_id, 1, 'trying to redact', '00000000-0000-0000-0000-000000288002', 'Edit Staff');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'insufficient_authority%' then
      raise exception 'expected insufficient_authority, got: %', sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'CRITICAL: a tenant''s TKT:Edit holder redacted content on a helpdesk case';
  end if;

  v_failed := false;
  begin
    perform app.assign_ticket(v_ticket.id, v_ticket.record_version, null, '00000000-0000-0000-0000-000000288002', 'Edit Staff');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'channel_not_supported%' then
      raise exception 'expected channel_not_supported, got: %', sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'CRITICAL: app.assign_ticket silently accepted a helpdesk ticket';
  end if;

  v_failed := false;
  begin
    perform app.transfer_ticket_queue(v_ticket.id, v_ticket.record_version, (select id from app.ticket_queues limit 1), 'x', '00000000-0000-0000-0000-000000288090', 'Supreme');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'channel_not_supported%' then
      raise exception 'expected channel_not_supported, got: %', sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'CRITICAL: app.transfer_ticket_queue silently accepted a helpdesk ticket';
  end if;

  v_failed := false;
  begin
    perform app.update_ticket_classification(v_ticket.id, v_ticket.record_version, (select id from app.ticket_categories where tenant_id = v_tenant1 limit 1), 'high', '00000000-0000-0000-0000-000000288090', 'Supreme');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'channel_not_supported%' then
      raise exception 'expected channel_not_supported, got: %', sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'CRITICAL: app.update_ticket_classification silently accepted a helpdesk ticket';
  end if;

  -- Supreme Admin CAN redact (Platform-staff-only, satisfied).
  perform app.redact_ticket_message(v_public_msg_id, 1, 'redacting a stray PII fragment', '00000000-0000-0000-0000-000000288090', 'Supreme');
  if not (select is_redacted from app.ticket_messages where id = v_public_msg_id) then
    raise exception 'expected Supreme Admin redaction to succeed';
  end if;

  raise notice 'PASS: the four generic staff-lifecycle RPCs all explicitly reject a helpdesk ticket for the wrong actor/RPC pairing; Supreme Admin redaction succeeds';
end $$;

\echo '>> 11. dedicated Platform-side helpdesk RPCs: assign/transfer/classify (Supreme-Admin-gated, tenant admin refused)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tkh1');
  v_ticket app.tickets := (select t from app.tickets t where t.tenant_id = v_tenant1 and t.channel = 'helpdesk' and t.subject = 'Invoice totals mismatch');
  v_queue_billing uuid := (select id from app.support_queues where code = 'SQ-BILLING');
  v_queue_tech uuid := (select id from app.support_queues where code = 'SQ-TECH');
  v_after app.tickets;
  v_failed boolean;
begin
  -- Tenant admin (not Supreme Admin) is refused on every dedicated RPC.
  v_failed := false;
  begin
    perform app.assign_helpdesk_ticket(v_ticket.id, v_ticket.record_version, '00000000-0000-0000-0000-000000288090', '00000000-0000-0000-0000-000000288001', 'Tkh1 Admin');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'insufficient_authority%' then raise exception 'expected insufficient_authority, got: %', sqlerrm; end if;
  end;
  if not v_failed then raise exception 'CRITICAL: a tenant admin assigned a helpdesk ticket to Platform support staff'; end if;

  -- Supreme Admin transfers to the Billing support queue.
  v_after := app.transfer_helpdesk_support_queue(v_ticket.id, v_ticket.record_version, v_queue_billing, 'route to billing team', '00000000-0000-0000-0000-000000288090', 'Supreme');
  if v_after.support_queue_id <> v_queue_billing then
    raise exception 'expected support_queue_id=%, got %', v_queue_billing, v_after.support_queue_id;
  end if;

  -- Assigning to a non-Supreme-Admin identity is rejected.
  v_failed := false;
  begin
    perform app.assign_helpdesk_ticket(v_after.id, v_after.record_version, '00000000-0000-0000-0000-000000288001', '00000000-0000-0000-0000-000000288090', 'Supreme');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'assignee_not_support_staff%' then raise exception 'expected assignee_not_support_staff, got: %', sqlerrm; end if;
  end;
  if not v_failed then raise exception 'CRITICAL: a helpdesk ticket was assigned to a non-Platform-support identity'; end if;

  -- Assigning to a real second Supreme Admin succeeds.
  v_after := app.assign_helpdesk_ticket(v_after.id, v_after.record_version, '00000000-0000-0000-0000-000000288091', '00000000-0000-0000-0000-000000288090', 'Supreme');
  if v_after.assignee_support_auth_user_id <> '00000000-0000-0000-0000-000000288091' then
    raise exception 'expected assignee_support_auth_user_id=%, got %', '00000000-0000-0000-0000-000000288091', v_after.assignee_support_auth_user_id;
  end if;

  -- Transferring to a DIFFERENT queue clears the assignee (mirrors
  -- app.transfer_ticket_queue's own established behavior).
  v_after := app.transfer_helpdesk_support_queue(v_after.id, v_after.record_version, v_queue_tech, 'reclassify to technical', '00000000-0000-0000-0000-000000288090', 'Supreme');
  if v_after.assignee_support_auth_user_id is not null then
    raise exception 'expected assignee to be cleared on queue transfer';
  end if;

  -- Reclassification.
  v_after := app.update_helpdesk_ticket_classification(v_after.id, v_after.record_version, (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'CAT-SUPPORT'), 'urgent', 'critical', 'Rate cards', 'production', '00000000-0000-0000-0000-000000288090', 'Supreme');
  if v_after.priority <> 'urgent' or v_after.severity <> 'critical' or v_after.product_area <> 'Rate cards' then
    raise exception 'expected reclassification to apply';
  end if;

  -- Invalid severity is rejected.
  v_failed := false;
  begin
    perform app.update_helpdesk_ticket_classification(v_after.id, v_after.record_version, v_after.category_id, 'normal', 'not-a-real-severity', null, null, '00000000-0000-0000-0000-000000288090', 'Supreme');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'invalid_severity%' then raise exception 'expected invalid_severity, got: %', sqlerrm; end if;
  end;
  if not v_failed then raise exception 'expected an invalid severity value to be rejected'; end if;

  raise notice 'PASS: dedicated Platform-side helpdesk assign/transfer/classify RPCs are Supreme-Admin-gated and behave correctly';
end $$;

\echo '>> 12. correlation-not-access-grant guarantee: forged case ref rejected; a real (even later revoked) grant correlates for DISPLAY only; holding an active support grant confers ZERO helpdesk staff status on its own'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tkh1');
  v_ticket app.tickets := (select t from app.tickets t where t.tenant_id = v_tenant1 and t.channel = 'helpdesk' and t.subject = 'Invoice totals mismatch');
  v_grant app.support_access_grants;
  v_failed boolean := false;
  v_after app.tickets;
  v_detail record;
  v_agent_staff boolean;
  v_agent_access boolean;
begin
  -- 12a. Forged/nonexistent case ref rejected.
  begin
    perform app.link_helpdesk_support_grant(v_ticket.id, v_ticket.record_version, 'CASE-DOES-NOT-EXIST', '00000000-0000-0000-0000-000000288090', 'Supreme');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'support_grant_not_found%' then raise exception 'expected support_grant_not_found, got: %', sqlerrm; end if;
  end;
  if not v_failed then raise exception 'CRITICAL: a forged support-access case reference was accepted for correlation'; end if;

  -- Tenant admin cannot call the correlation RPC at all (Supreme-Admin-only).
  v_failed := false;
  begin
    perform app.link_helpdesk_support_grant(v_ticket.id, v_ticket.record_version, 'CASE-ANY', '00000000-0000-0000-0000-000000288001', 'Tkh1 Admin');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'insufficient_authority%' then raise exception 'expected insufficient_authority, got: %', sqlerrm; end if;
  end;
  if not v_failed then raise exception 'CRITICAL: a tenant admin linked a support-access correlation ref'; end if;

  -- 12b. Create a REAL support access grant for support-agent (an ordinary
  -- auth.users identity, NOT Supreme Admin, NOT tenant_admin/TKT:Edit for
  -- tkh1), approved by the tenant's own tenant_admin (is_support_grant_
  -- authority), then immediately revoked (the kill switch) -- the grant is
  -- REVOKED by the time it is linked, proving correlation display never
  -- requires a currently-live grant.
  v_grant := app.request_support_access(v_tenant1, '00000000-0000-0000-0000-000000288092', 'investigating invoice mismatch per case', 'CASE-500', 60, 'supreme', 'read_only', false, null);
  v_grant := app.approve_support_access(v_grant.id, '00000000-0000-0000-0000-000000288001', 'Tkh1 Admin', null);
  if v_grant.status <> 'approved' then
    raise exception 'expected the support grant to be approved';
  end if;

  -- Adversarial check BEFORE revocation: support-agent holds a live,
  -- APPROVED, unexpired grant into tkh1 -- does that alone make them
  -- helpdesk "staff" or grant them access to THIS ticket? It must not --
  -- staff status for a helpdesk ticket is is_supreme_admin only.
  select app.is_ticket_staff(v_ticket.id, '00000000-0000-0000-0000-000000288092') into v_agent_staff;
  select app.can_access_ticket(v_ticket.id, '00000000-0000-0000-0000-000000288092') into v_agent_access;
  if v_agent_staff or v_agent_access then
    raise exception 'CRITICAL: an active support-access grant alone granted helpdesk-ticket staff/access status (staff=% access=%) -- a support ticket and a support grant must remain two independent mechanisms', v_agent_staff, v_agent_access;
  end if;

  v_grant := app.revoke_support_access(v_grant.id, '00000000-0000-0000-0000-000000288001', 'Tkh1 Admin', 'investigation concluded');
  if v_grant.status <> 'revoked' then
    raise exception 'expected the support grant to be revoked';
  end if;

  -- 12c. Linking the now-REVOKED grant's case_id succeeds (display-only,
  -- history is legitimate) -- this call is NOT itself an access grant.
  v_after := app.link_helpdesk_support_grant(v_ticket.id, v_ticket.record_version, 'CASE-500', '00000000-0000-0000-0000-000000288090', 'Supreme');
  if v_after.support_access_case_ref <> 'CASE-500' then
    raise exception 'expected support_access_case_ref=CASE-500, got %', v_after.support_access_case_ref;
  end if;

  -- 12d. The Platform staff detail view shows the REAL, revoked status --
  -- never hides it, never implies live access.
  select * into v_detail from app.get_platform_helpdesk_ticket(v_after.id, '00000000-0000-0000-0000-000000288090');
  if v_detail.support_access_case_ref <> 'CASE-500' or v_detail.support_grant_status <> 'revoked' or v_detail.support_grant_revoked_at is null then
    raise exception 'expected the platform detail view to show the real revoked grant status, got case_ref=% status=% revoked_at=%', v_detail.support_access_case_ref, v_detail.support_grant_status, v_detail.support_grant_revoked_at;
  end if;

  -- 12e. After correlation, support-agent STILL has zero helpdesk staff/
  -- access status (linking a case ref never resurrects or creates access).
  select app.is_ticket_staff(v_after.id, '00000000-0000-0000-0000-000000288092') into v_agent_staff;
  select app.can_access_ticket(v_after.id, '00000000-0000-0000-0000-000000288092') into v_agent_access;
  if v_agent_staff or v_agent_access then
    raise exception 'CRITICAL: linking a support-access case correlation resurrected/created ticket access for the grantee';
  end if;
  if app.has_active_support_grant(v_tenant1, '00000000-0000-0000-0000-000000288092') then
    raise exception 'CRITICAL: the revoked grant is still reported active';
  end if;

  -- 12f. Unlinking (null case ref) succeeds without any grant validation.
  v_after := app.link_helpdesk_support_grant(v_after.id, v_after.record_version, null, '00000000-0000-0000-0000-000000288090', 'Supreme');
  if v_after.support_access_case_ref is not null then
    raise exception 'expected support_access_case_ref to be cleared';
  end if;

  raise notice 'PASS: support-grant correlation is genuinely display/audit-only -- a forged ref is rejected, a real (even revoked) grant correlates for display, and holding an active grant confers zero helpdesk ticket staff/access status on its own';
end $$;

\echo '>> 13. cross-tenant isolation: tkh2''s admin cannot read/list tkh1''s helpdesk ticket via any tenant-safe RPC'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tkh1');
  v_ticket_id uuid := (select id from app.tickets where tenant_id = v_tenant1 and channel = 'helpdesk' and subject = 'Invoice totals mismatch');
  v_get_count integer;
  v_list_count integer;
  v_messages_count integer;
begin
  select count(*) into v_get_count from app.get_tenant_helpdesk_ticket(v_ticket_id, '00000000-0000-0000-0000-000000288021');
  select count(*) into v_list_count from app.list_tenant_helpdesk_tickets(v_tenant1, '00000000-0000-0000-0000-000000288021', null, 50, null) t where t.id = v_ticket_id;
  select count(*) into v_messages_count from app.list_tenant_helpdesk_ticket_messages(v_ticket_id, '00000000-0000-0000-0000-000000288021', 100, null);
  if v_get_count <> 0 or v_list_count <> 0 or v_messages_count <> 0 then
    raise exception 'CRITICAL: tkh2''s admin read tkh1''s helpdesk ticket -- get=% list=% messages=%', v_get_count, v_list_count, v_messages_count;
  end if;
  raise notice 'PASS: cross-tenant helpdesk isolation holds across get/list/messages';
end $$;

\echo '>> 14. list_platform_helpdesk_tickets is genuinely cross-tenant for Supreme Admin, refused for a tenant admin'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tkh1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'tkh2');
  v_category2 uuid;
  v_ticket2 app.tickets;
  v_platform_count integer;
  v_tenant_admin_count integer;
begin
  -- Created via Supreme Admin (RPD-022 evaluate_permission bypass covers
  -- ordinary TKT:Edit-gated config RPCs -- unlike app._is_tenant_helpdesk_
  -- authorized, which deliberately does NOT grant Supreme Admin this
  -- bypass, see test 4 above) -- avoids provisioning a second tenant's own
  -- TKT:Edit role purely for this one cross-tenant fixture step.
  v_category2 := (app.create_ticket_category(v_tenant2, 'CAT-SUPPORT2', 'Support', null, '00000000-0000-0000-0000-000000288090', 'Supreme')).id;
  perform app.set_ticket_category_helpdesk_visibility(v_category2, true, '00000000-0000-0000-0000-000000288090', 'Supreme');
  v_ticket2 := app.create_helpdesk_ticket(v_tenant2, v_category2, 'normal', null, null, null, null, 'Tenant 2 case', 'A separate tenant''s own helpdesk case.', 'idem-hd-tenant2', '00000000-0000-0000-0000-000000288021', 'Tkh2 Admin');

  select count(*) into v_platform_count from app.list_platform_helpdesk_tickets('00000000-0000-0000-0000-000000288090', null, null, null, null, 200, null) t where t.tenant_id in (v_tenant1, v_tenant2);
  if v_platform_count < 2 then
    raise exception 'expected the Platform queue view to see helpdesk tickets from BOTH tenants, got %', v_platform_count;
  end if;

  select count(*) into v_tenant_admin_count from app.list_platform_helpdesk_tickets('00000000-0000-0000-0000-000000288001', null, null, null, null, 200, null);
  if v_tenant_admin_count <> 0 then
    raise exception 'CRITICAL: a tenant admin (not Supreme Admin) read the cross-tenant Platform helpdesk queue';
  end if;

  raise notice 'PASS: app.list_platform_helpdesk_tickets is genuinely cross-tenant for Supreme Admin (% rows across 2 tenants) and refused for a tenant admin', v_platform_count;
end $$;

\echo '>> 15. every remaining new list/get RPC reachable (C-02 defense) and schema-privilege defense in depth'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tkh1');
  v_ticket_id uuid := (select id from app.tickets where tenant_id = v_tenant1 and channel = 'helpdesk' and subject = 'Invoice totals mismatch');
  v_queues_count integer;
  v_categories_count integer;
  v_tenant_ticket_count integer;
begin
  select count(*) into v_queues_count from app.list_support_queues('00000000-0000-0000-0000-000000288090');
  if v_queues_count <> 2 then
    raise exception 'expected 2 support queues, got %', v_queues_count;
  end if;
  if exists (select 1 from app.list_support_queues('00000000-0000-0000-0000-000000288001')) then
    raise exception 'CRITICAL: a tenant admin listed the Platform-internal support-queue catalog';
  end if;

  select count(*) into v_categories_count from app.list_helpdesk_ticket_categories(v_tenant1, '00000000-0000-0000-0000-000000288001');
  if v_categories_count <> 1 then
    raise exception 'expected exactly 1 helpdesk-visible category, got %', v_categories_count;
  end if;

  select count(*) into v_tenant_ticket_count from app.list_tenant_helpdesk_tickets(v_tenant1, '00000000-0000-0000-0000-000000288001', null, 50, null);
  if v_tenant_ticket_count < 1 then
    raise exception 'expected list_tenant_helpdesk_tickets to reach at least 1 row';
  end if;

  if not exists (select 1 from app.get_tenant_helpdesk_ticket(v_ticket_id, '00000000-0000-0000-0000-000000288001')) then
    raise exception 'expected get_tenant_helpdesk_ticket to reach a row';
  end if;

  if not exists (select 1 from app.get_platform_helpdesk_ticket(v_ticket_id, '00000000-0000-0000-0000-000000288090')) then
    raise exception 'expected get_platform_helpdesk_ticket to reach a row';
  end if;

  -- create_support_queue idempotent replay by code.
  if (app.create_support_queue('SQ-BILLING', 'Billing Support', null, '00000000-0000-0000-0000-000000288090', 'supreme')).id <> (select id from app.support_queues where code = 'SQ-BILLING') then
    raise exception 'expected create_support_queue idempotent replay to return the existing row';
  end if;

  if has_function_privilege('anon', 'app.create_helpdesk_ticket(uuid, uuid, text, text, text, text, text, text, text, text, uuid, text)', 'execute') then
    raise exception 'CRITICAL: anon can execute app.create_helpdesk_ticket';
  end if;
  if has_function_privilege('anon', 'app.get_platform_helpdesk_ticket(uuid, uuid)', 'execute') then
    raise exception 'CRITICAL: anon can execute app.get_platform_helpdesk_ticket';
  end if;
  if has_function_privilege('anon', 'app.link_helpdesk_support_grant(uuid, integer, text, uuid, text)', 'execute') then
    raise exception 'CRITICAL: anon can execute app.link_helpdesk_support_grant';
  end if;

  raise notice 'PASS: every remaining new RPC reachable; anon has zero schema privilege on any new helpdesk function';
end $$;

\echo '>> 16. structural leak sweep: the tenant-safe helpdesk projections carry no support_queue_id/support_queue_code/assignee_support_auth_user_id/support_access_case_ref column at all'
do $$
declare
  v_leak_count integer;
begin
  select count(*) into v_leak_count
  from information_schema.parameters p
  join information_schema.routines r on r.specific_name = p.specific_name and r.routine_schema = p.specific_schema
  where r.routine_schema = 'app'
    and r.routine_name in ('get_tenant_helpdesk_ticket', 'list_tenant_helpdesk_tickets', 'list_tenant_helpdesk_ticket_messages', 'list_helpdesk_ticket_categories')
    and p.parameter_mode = 'OUT'
    and (p.parameter_name ilike '%support_queue%' or p.parameter_name ilike '%assignee%' or p.parameter_name ilike '%support_access_case_ref%' or p.parameter_name ilike '%assignee_support%');
  if v_leak_count <> 0 then
    raise exception 'CRITICAL: a tenant-facing helpdesk projection carries an internal routing/assignee/correlation column';
  end if;
  raise notice 'PASS: no tenant-facing helpdesk projection carries a support_queue/assignee/support_access_case_ref column';
end $$;

\echo '>> all ticketing-helpdesk (HRT-288) assertions passed'
