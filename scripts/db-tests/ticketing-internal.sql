-- Real, executable test evidence for HRT-286 (Internal and Interdepartmental
-- Ticket, CG-S12-HRT-014) -- run via `pnpm run db:test` against a real,
-- disposable Postgres database (and standalone via psql, per this task's own
-- ISS-2026-077 workaround instructions, since a full harness run may abort
-- before reaching this alphabetically-late file).
--
-- Self-contained: own two-tenant/employee/role fixture, own fresh, unclaimed
-- UUID range (00000000-0000-0000-0000-0000002860xx). Tenant slugs `tkt1`/
-- `tkt2` (grep-verified unclaimed).
--
-- Covers, live: canonical ticket creation (self-service + on-behalf) with a
-- real opening message; queue/category catalog idempotent creation; explicit
-- queue staffing (add/remove); reply vs internal-note visibility, enforced at
-- BOTH the RPC read path and raw-table RLS -- a plain requester never sees an
-- internal note through any path; watcher add/remove (explicit, revocable --
-- department membership alone does not imply access); the full transition
-- graph (new->open->pending->resolved->closed, reopen, on_hold, cancel,
-- rejecting an invalid jump); assignment (validated against real queue
-- staffing); queue transfer; classification change; message redaction
-- (content genuinely gone, never recoverable via audit_logs); attachment
-- malware-scan gating (infected/unscanned rejected, clean accepted);
-- idempotent replay (full-tuple compare, not just the key) for ticket
-- creation and for a reply; a genuine concurrent double-reply/status-change
-- race; cross-tenant RLS isolation; an unrelated employee (same tenant,
-- zero participation) denied read access to a ticket they are not part of;
-- schema-privilege defense in depth (anon has zero access).

\set ON_ERROR_STOP on

\echo '>> fixture'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_admin_role uuid; v_admin_draft app.role_versions;
  v_company uuid; v_branch uuid; v_dept_a uuid; v_dept_b uuid;
  v_req1_emp uuid; v_req2_emp uuid; v_staff1_emp uuid; v_staff2_emp uuid; v_bystander_emp uuid;
  v_admin_emp uuid;
  v_queue_a uuid; v_queue_b uuid;
  v_category uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000286001', 'admin@tkt1.test'),
    ('00000000-0000-0000-0000-000000286002', 'requester1@tkt1.test'),
    ('00000000-0000-0000-0000-000000286003', 'requester2@tkt1.test'),
    ('00000000-0000-0000-0000-000000286004', 'staff1@tkt1.test'),
    ('00000000-0000-0000-0000-000000286005', 'staff2@tkt1.test'),
    ('00000000-0000-0000-0000-000000286006', 'bystander@tkt1.test'),
    ('00000000-0000-0000-0000-000000286021', 'admin@tkt2.test'),
    ('00000000-0000-0000-0000-000000286022', 'requester1@tkt2.test');

  perform app.provision_tenant('tkt1', 'Ticket Co 1', 'idem-tkt1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'tkt1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.provision_tenant('tkt2', 'Ticket Co 2', 'idem-tkt2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'tkt2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000286001', 'admin@tkt1.test', 'Tkt1 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@tkt1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000286001', 'tenant_admin', v_tenant1, null, 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000286002', 'requester1@tkt1.test', 'Tkt1 Requester One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'requester1@tkt1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000286003', 'requester2@tkt1.test', 'Tkt1 Requester Two', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'requester2@tkt1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000286004', 'staff1@tkt1.test', 'Tkt1 Staff One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff1@tkt1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000286005', 'staff2@tkt1.test', 'Tkt1 Staff Two', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff2@tkt1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000286006', 'bystander@tkt1.test', 'Tkt1 Bystander', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'bystander@tkt1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000286021', 'admin@tkt2.test', 'Tkt2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@tkt2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000286021', 'tenant_admin', v_tenant2, null, 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000286022', 'requester1@tkt2.test', 'Tkt2 Requester One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'requester1@tkt2.test'), 'active', 'onboarded', 'tester');

  -- HR role: HRS Create/Edit/Approve/Export/View -- needed by admin (028401)
  -- to drive the employee-lifecycle fixture below (create_employee_draft/
  -- submit_employee_for_approval/decide_employee_approval/activate_employee
  -- all gate on real HRS permissions -- tenant_admin layer alone does not
  -- imply them, mirrors HRT-284's own fixture precedent exactly).
  declare
    v_hr_role uuid; v_hr_draft app.role_versions;
  begin
    v_hr_role := (app.create_role(v_tenant1, 'HR Admin', 'HRS Create/Edit/Approve/Export/View', 'tester')).id;
    v_hr_draft := app.create_role_version(v_hr_role, 'tester');
    perform app.set_role_version_permissions(v_hr_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('Create', 'Edit', 'Approve', 'Export', 'View')), 'tester');
    perform app.publish_role_version(v_hr_draft.id, now(), 'tester');
    perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_hr_role and status = 'published'), '00000000-0000-0000-0000-000000286001', '00000000-0000-0000-0000-000000286001', 'tester');
  end;

  -- TKT admin role: Edit/Override/Assign/Export (queue/category config, on-behalf
  -- create, redaction, assignment, export, and -- since ISS-2026-086 split them apart --
  -- the tenant-wide ticket-content override that used to ride along with TKT:Edit)
  -- granted to staff1 only. TKT:Override is listed explicitly here rather than
  -- inherited, which is the whole point of the split: this fixture WANTS the blanket
  -- override (a later assertion has staff1 reply to a ticket after a queue transfer left
  -- them without membership), so it now has to say so.
  v_admin_role := (app.create_role(v_tenant1, 'Ticket Admin', 'TKT Edit/Override/Assign/Export', 'tester')).id;
  v_admin_draft := app.create_role_version(v_admin_role, 'tester');
  perform app.set_role_version_permissions(v_admin_draft.id, array(select id from app.permissions where resource_module_code = 'TKT' and action in ('Edit', 'Override', 'Assign', 'Export', 'Close', 'Reopen')), 'tester');
  perform app.publish_role_version(v_admin_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_admin_role and status = 'published'), '00000000-0000-0000-0000-000000286004', '00000000-0000-0000-0000-000000286001', 'tester');

  v_company := (app.create_org_unit(v_tenant1, 'company', null, 'CO-TKT1', 'Tkt1 Co', 'tester')).id;
  v_branch := (app.create_org_unit(v_tenant1, 'branch', v_company, 'BR-TKT1', 'Tkt1 Branch', 'tester')).id;
  v_dept_a := (app.create_org_unit(v_tenant1, 'department', v_branch, 'DEPT-A', 'IT Support', 'tester')).id;
  v_dept_b := (app.create_org_unit(v_tenant1, 'department', v_branch, 'DEPT-B', 'Facilities', 'tester')).id;

  perform app.create_employee_draft(v_tenant1, 'Tkt1 Admin', 'full_time', 'adminwork@tkt1.test', 'adminp@tkt1.test', '0900000001', null, null, null, '2024-01-01', v_company, v_branch, v_dept_a, 'Admin', null, (select id from app.users where email = 'admin@tkt1.test'), null, 'hr_created', 'idem-admin-tkt1', '00000000-0000-0000-0000-000000286001', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'adminwork@tkt1.test'), 'Emergency Contact for Tkt1 Admin', 'spouse', '0910000000', null, true, '00000000-0000-0000-0000-000000286001', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'adminwork@tkt1.test'), 1, '00000000-0000-0000-0000-000000286001', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'adminwork@tkt1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000286001', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'adminwork@tkt1.test'), 3, '00000000-0000-0000-0000-000000286001', 'tester');
  v_admin_emp := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'adminwork@tkt1.test');

  perform app.create_employee_draft(v_tenant1, 'Tkt1 Requester One', 'full_time', 'req1work@tkt1.test', 'req1p@tkt1.test', '0900000002', null, null, null, '2024-01-01', v_company, v_branch, v_dept_b, 'Staff', null, (select id from app.users where email = 'requester1@tkt1.test'), null, 'hr_created', 'idem-req1-tkt1', '00000000-0000-0000-0000-000000286001', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'req1work@tkt1.test'), 'Emergency Contact for Tkt1 Requester One', 'spouse', '0910000000', null, true, '00000000-0000-0000-0000-000000286001', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'req1work@tkt1.test'), 1, '00000000-0000-0000-0000-000000286001', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'req1work@tkt1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000286001', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'req1work@tkt1.test'), 3, '00000000-0000-0000-0000-000000286001', 'tester');
  v_req1_emp := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'req1work@tkt1.test');

  perform app.create_employee_draft(v_tenant1, 'Tkt1 Requester Two', 'full_time', 'req2work@tkt1.test', 'req2p@tkt1.test', '0900000003', null, null, null, '2024-01-01', v_company, v_branch, v_dept_b, 'Staff', null, (select id from app.users where email = 'requester2@tkt1.test'), null, 'hr_created', 'idem-req2-tkt1', '00000000-0000-0000-0000-000000286001', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'req2work@tkt1.test'), 'Emergency Contact for Tkt1 Requester Two', 'spouse', '0910000000', null, true, '00000000-0000-0000-0000-000000286001', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'req2work@tkt1.test'), 1, '00000000-0000-0000-0000-000000286001', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'req2work@tkt1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000286001', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'req2work@tkt1.test'), 3, '00000000-0000-0000-0000-000000286001', 'tester');
  v_req2_emp := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'req2work@tkt1.test');

  perform app.create_employee_draft(v_tenant1, 'Tkt1 Staff One', 'full_time', 'staff1work@tkt1.test', 'staff1p@tkt1.test', '0900000004', null, null, null, '2024-01-01', v_company, v_branch, v_dept_a, 'IT Support Agent', null, (select id from app.users where email = 'staff1@tkt1.test'), null, 'hr_created', 'idem-staff1-tkt1', '00000000-0000-0000-0000-000000286001', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@tkt1.test'), 'Emergency Contact for Tkt1 Staff One', 'spouse', '0910000000', null, true, '00000000-0000-0000-0000-000000286001', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@tkt1.test'), 1, '00000000-0000-0000-0000-000000286001', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@tkt1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000286001', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@tkt1.test'), 3, '00000000-0000-0000-0000-000000286001', 'tester');
  v_staff1_emp := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@tkt1.test');

  perform app.create_employee_draft(v_tenant1, 'Tkt1 Staff Two', 'full_time', 'staff2work@tkt1.test', 'staff2p@tkt1.test', '0900000005', null, null, null, '2024-01-01', v_company, v_branch, v_dept_a, 'IT Support Agent', null, (select id from app.users where email = 'staff2@tkt1.test'), null, 'hr_created', 'idem-staff2-tkt1', '00000000-0000-0000-0000-000000286001', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff2work@tkt1.test'), 'Emergency Contact for Tkt1 Staff Two', 'spouse', '0910000000', null, true, '00000000-0000-0000-0000-000000286001', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff2work@tkt1.test'), 1, '00000000-0000-0000-0000-000000286001', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff2work@tkt1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000286001', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff2work@tkt1.test'), 3, '00000000-0000-0000-0000-000000286001', 'tester');
  v_staff2_emp := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff2work@tkt1.test');

  -- Bystander: an ordinary employee in the SAME tenant, zero relation to any
  -- ticket -- the "unrelated employee" adversarial-test actor.
  perform app.create_employee_draft(v_tenant1, 'Tkt1 Bystander', 'full_time', 'bystanderwork@tkt1.test', 'bystanderp@tkt1.test', '0900000006', null, null, null, '2024-01-01', v_company, v_branch, v_dept_b, 'Staff', null, (select id from app.users where email = 'bystander@tkt1.test'), null, 'hr_created', 'idem-bystander-tkt1', '00000000-0000-0000-0000-000000286001', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'bystanderwork@tkt1.test'), 'Emergency Contact for Tkt1 Bystander', 'spouse', '0910000000', null, true, '00000000-0000-0000-0000-000000286001', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'bystanderwork@tkt1.test'), 1, '00000000-0000-0000-0000-000000286001', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'bystanderwork@tkt1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000286001', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'bystanderwork@tkt1.test'), 3, '00000000-0000-0000-0000-000000286001', 'tester');
  v_bystander_emp := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'bystanderwork@tkt1.test');

  -- Queue/category catalog.
  v_queue_a := (app.create_ticket_queue(v_tenant1, v_dept_a, 'IT', 'IT Support', 'IT support queue', '00000000-0000-0000-0000-000000286004', 'staff1')).id;
  v_queue_b := (app.create_ticket_queue(v_tenant1, v_dept_b, 'FAC', 'Facilities', 'Facilities queue', '00000000-0000-0000-0000-000000286004', 'staff1')).id;
  v_category := (app.create_ticket_category(v_tenant1, 'HARDWARE', 'Hardware Issue', v_queue_a, '00000000-0000-0000-0000-000000286004', 'staff1')).id;
  perform app.create_ticket_category(v_tenant1, 'FACILITIES', 'Facilities Request', v_queue_b, '00000000-0000-0000-0000-000000286004', 'staff1');

  perform app.add_ticket_queue_member(v_queue_a, v_staff1_emp, '00000000-0000-0000-0000-000000286004', 'staff1');
  perform app.add_ticket_queue_member(v_queue_a, v_staff2_emp, '00000000-0000-0000-0000-000000286004', 'staff1');

  -- Tenant 2: minimal cross-tenant isolation fixture.
  declare
    v_hr_role2 uuid; v_hr_draft2 app.role_versions;
  begin
    v_hr_role2 := (app.create_role(v_tenant2, 'HR Admin', 'HRS Create/Edit/Approve/Export/View', 'tester')).id;
    v_hr_draft2 := app.create_role_version(v_hr_role2, 'tester');
    perform app.set_role_version_permissions(v_hr_draft2.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('Create', 'Edit', 'Approve', 'Export', 'View')), 'tester');
    perform app.publish_role_version(v_hr_draft2.id, now(), 'tester');
    perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_hr_role2 and status = 'published'), '00000000-0000-0000-0000-000000286021', '00000000-0000-0000-0000-000000286021', 'tester');
  end;
  v_company := (app.create_org_unit(v_tenant2, 'company', null, 'CO-TKT2', 'Tkt2 Co', 'tester')).id;
  perform app.create_employee_draft(v_tenant2, 'Tkt2 Admin', 'full_time', 'adminwork@tkt2.test', 'adminp@tkt2.test', '0900000021', null, null, null, '2024-01-01', v_company, null, null, 'Admin', null, (select id from app.users where email = 'admin@tkt2.test'), null, 'hr_created', 'idem-admin-tkt2', '00000000-0000-0000-0000-000000286021', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant2 and work_email = 'adminwork@tkt2.test'), 'Emergency Contact for Tkt2 Admin', 'spouse', '0910000000', null, true, '00000000-0000-0000-0000-000000286021', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant2 and work_email = 'adminwork@tkt2.test'), 1, '00000000-0000-0000-0000-000000286021', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant2 and work_email = 'adminwork@tkt2.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000286021', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant2 and work_email = 'adminwork@tkt2.test'), 3, '00000000-0000-0000-0000-000000286021', 'tester');
  perform app.create_employee_draft(v_tenant2, 'Tkt2 Requester One', 'full_time', 'req1work@tkt2.test', 'req1p@tkt2.test', '0900000022', null, null, null, '2024-01-01', v_company, null, null, 'Staff', null, (select id from app.users where email = 'requester1@tkt2.test'), null, 'hr_created', 'idem-req1-tkt2', '00000000-0000-0000-0000-000000286021', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant2 and work_email = 'req1work@tkt2.test'), 'Emergency Contact for Tkt2 Requester One', 'spouse', '0910000000', null, true, '00000000-0000-0000-0000-000000286021', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant2 and work_email = 'req1work@tkt2.test'), 1, '00000000-0000-0000-0000-000000286021', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant2 and work_email = 'req1work@tkt2.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000286021', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant2 and work_email = 'req1work@tkt2.test'), 3, '00000000-0000-0000-0000-000000286021', 'tester');

  raise notice 'fixture ready: tenant1=%, tenant2=%, queue_a=%, queue_b=%, category=%, req1_emp=%, req2_emp=%, staff1_emp=%, staff2_emp=%, bystander_emp=%, admin_emp=%',
    v_tenant1, v_tenant2, v_queue_a, v_queue_b, v_category, v_req1_emp, v_req2_emp, v_staff1_emp, v_staff2_emp, v_bystander_emp, v_admin_emp;
end;
$$;

\echo '>> 1. catalog idempotent creation'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tkt1');
  v_dept_a uuid := (select id from app.org_units where tenant_id = v_tenant1 and code = 'DEPT-A');
  v_q1 app.ticket_queues;
  v_q2 app.ticket_queues;
begin
  v_q1 := app.create_ticket_queue(v_tenant1, v_dept_a, 'IT', 'IT Support Renamed Attempt', 'x', '00000000-0000-0000-0000-000000286004', 'staff1');
  v_q2 := app.create_ticket_queue(v_tenant1, v_dept_a, 'IT', 'IT Support Renamed Attempt', 'x', '00000000-0000-0000-0000-000000286004', 'staff1');
  if v_q1.id <> v_q2.id then
    raise exception 'FAIL: create_ticket_queue not idempotent by code';
  end if;
  if v_q1.name <> 'IT Support' then
    raise exception 'FAIL: idempotent create_ticket_queue must return the ORIGINAL row, got name=%', v_q1.name;
  end if;
  raise notice 'PASS: create_ticket_queue idempotent-by-code';
end;
$$;

\echo '>> 2. self-service ticket creation + opening message'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tkt1');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'HARDWARE');
  v_ticket app.tickets;
  v_msg_count integer;
begin
  v_ticket := app.create_ticket(v_tenant1, v_category, null, 'high', 'Laptop will not boot', 'My laptop shows a black screen after the login prompt.', 'idem-t1-create', '00000000-0000-0000-0000-000000286002', 'requester1');
  if v_ticket.status <> 'new' or v_ticket.priority <> 'high' or v_ticket.channel <> 'internal' then
    raise exception 'FAIL: unexpected ticket shape: status=%, priority=%, channel=%', v_ticket.status, v_ticket.priority, v_ticket.channel;
  end if;
  if v_ticket.queue_id is null then
    raise exception 'FAIL: queue was not resolved from category default_queue_id';
  end if;
  select count(*) into v_msg_count from app.ticket_messages where ticket_id = v_ticket.id;
  if v_msg_count <> 1 then
    raise exception 'FAIL: expected exactly 1 opening message, got %', v_msg_count;
  end if;
  if not exists (select 1 from app.ticket_messages where ticket_id = v_ticket.id and visibility = 'public' and author_role = 'requester') then
    raise exception 'FAIL: opening message must be public/requester-authored';
  end if;

  -- Idempotent replay: identical inputs return the SAME ticket.
  if (app.create_ticket(v_tenant1, v_category, null, 'high', 'Laptop will not boot', 'My laptop shows a black screen after the login prompt.', 'idem-t1-create', '00000000-0000-0000-0000-000000286002', 'requester1')).id <> v_ticket.id then
    raise exception 'FAIL: idempotent replay returned a different ticket';
  end if;

  -- Same key, DIFFERENT subject: genuine conflict, not silently accepted.
  begin
    perform app.create_ticket(v_tenant1, v_category, null, 'high', 'A totally different subject', 'different body', 'idem-t1-create', '00000000-0000-0000-0000-000000286002', 'requester1');
    raise exception 'FAIL: idempotency_key reuse with a different subject should have raised idempotency_key_conflict';
  exception
    when others then
      if sqlerrm not like 'idempotency_key_conflict%' then
        raise exception 'FAIL: expected idempotency_key_conflict, got: %', sqlerrm;
      end if;
  end;
  raise notice 'PASS: self-service creation + opening message + idempotent replay (full-tuple) + genuine conflict detection';
end;
$$;

\echo '>> 3. on-behalf creation (TKT:Edit gated)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tkt1');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'FACILITIES');
  v_req2_emp uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'req2work@tkt1.test');
  v_ticket app.tickets;
begin
  -- requester1 (no TKT:Edit) may NOT create on behalf of another employee.
  begin
    perform app.create_ticket_for_employee(v_tenant1, v_req2_emp, v_category, null, 'normal', 'AC broken', 'The AC in room 4 is broken.', null, '00000000-0000-0000-0000-000000286002', 'requester1');
    raise exception 'FAIL: requester1 without TKT:Edit should not be able to create on behalf of another employee';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then
        raise exception 'FAIL: expected insufficient_authority, got: %', sqlerrm;
      end if;
  end;

  -- staff1 (TKT:Edit) may.
  v_ticket := app.create_ticket_for_employee(v_tenant1, v_req2_emp, v_category, null, 'normal', 'AC broken', 'The AC in room 4 is broken.', 'idem-onbehalf-1', '00000000-0000-0000-0000-000000286004', 'staff1');
  if v_ticket.requester_employee_id <> v_req2_emp then
    raise exception 'FAIL: on-behalf ticket requester mismatch';
  end if;
  if v_ticket.requested_by_auth_user_id <> '00000000-0000-0000-0000-000000286004' then
    raise exception 'FAIL: on-behalf ticket requested_by_auth_user_id should be the ACTUAL submitter (staff1), not the requester';
  end if;
  raise notice 'PASS: on-behalf creation TKT:Edit-gated, requester vs. actual-submitter correctly distinguished';
end;
$$;

\echo '>> 4. visibility: internal note structurally never reaches a requester-visible read path'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tkt1');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'HARDWARE');
  v_ticket app.tickets;
  v_public_msg app.ticket_messages;
  v_internal_msg app.ticket_messages;
  v_visible_count integer;
begin
  v_ticket := app.create_ticket(v_tenant1, v_category, null, 'normal', 'Mouse not working', 'My mouse stopped responding.', 'idem-vis-1', '00000000-0000-0000-0000-000000286003', 'requester2');

  -- Requester (not staff) may NOT post an internal note.
  begin
    perform app.reply_to_ticket(v_ticket.id, 'trying to sneak an internal note', 'internal', null, null, '00000000-0000-0000-0000-000000286003', 'requester2');
    raise exception 'FAIL: a plain requester should not be able to post an internal-visibility message';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then
        raise exception 'FAIL: expected insufficient_authority, got: %', sqlerrm;
      end if;
  end;

  -- Staff posts a public reply and an internal note.
  v_public_msg := app.reply_to_ticket(v_ticket.id, 'Have you tried a different USB port?', 'public', null, null, '00000000-0000-0000-0000-000000286004', 'staff1');
  v_internal_msg := app.reply_to_ticket(v_ticket.id, 'Internal: this model has a known USB controller defect, escalate to hardware team if unresolved.', 'internal', null, null, '00000000-0000-0000-0000-000000286004', 'staff1');

  -- Requester's own read RPC never returns the internal message.
  select count(*) into v_visible_count from app.list_ticket_messages(v_ticket.id, '00000000-0000-0000-0000-000000286003', 100, null) m where m.id = v_internal_msg.id;
  if v_visible_count <> 0 then
    raise exception 'FAIL: app.list_ticket_messages leaked an internal note to the requester';
  end if;
  select count(*) into v_visible_count from app.list_ticket_messages(v_ticket.id, '00000000-0000-0000-0000-000000286003', 100, null) m where m.id = v_public_msg.id;
  if v_visible_count <> 1 then
    raise exception 'FAIL: the requester should see the public reply';
  end if;

  -- Staff sees both.
  select count(*) into v_visible_count from app.list_ticket_messages(v_ticket.id, '00000000-0000-0000-0000-000000286004', 100, null) m where m.id in (v_public_msg.id, v_internal_msg.id);
  if v_visible_count <> 2 then
    raise exception 'FAIL: staff should see both the public reply and the internal note';
  end if;

  raise notice 'PASS: internal note never reaches the requester''s own read RPC; staff sees both (message id % is the internal note under test)', v_internal_msg.id;
end;
$$;

\echo '>> 5. RLS as a real forged session (request.jwt.claims + set role authenticated, the same technique every db-test file in this repository uses): requester sees own ticket, bystander does not, internal note never leaks raw-table either'
do $$
declare
  v_ticket_id uuid := (select id from app.tickets where subject = 'Mouse not working');
  v_count integer;
begin
  -- Requester (own ticket): sees the ticket row and the public message, never the internal note, via raw RLS.
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000286003", "role": "authenticated"}', false);
  set role authenticated;
  select count(*) into v_count from app.tickets where id = v_ticket_id;
  if v_count <> 1 then raise exception 'FAIL (RLS): requester should see own ticket via raw table RLS, got %', v_count; end if;
  select count(*) into v_count from app.ticket_messages where ticket_id = v_ticket_id and visibility = 'internal';
  if v_count <> 0 then raise exception 'FAIL (RLS/C-24-shaped leak): requester sees % internal note row(s) via raw table RLS, expected 0', v_count; end if;
  select count(*) into v_count from app.ticket_messages where ticket_id = v_ticket_id and visibility = 'public';
  if v_count <> 2 then raise exception 'FAIL (RLS): requester should see both public messages (opening + staff reply) via raw table RLS, got %', v_count; end if;
  reset role;
  perform set_config('request.jwt.claims', 'null', false);

  -- Bystander (same tenant, zero participation): sees NOTHING of this ticket via raw RLS.
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000286006", "role": "authenticated"}', false);
  set role authenticated;
  select count(*) into v_count from app.tickets where id = v_ticket_id;
  if v_count <> 0 then raise exception 'FAIL (RLS): unrelated bystander (same tenant) sees % row(s) of a ticket they are not part of, expected 0', v_count; end if;
  reset role;
  perform set_config('request.jwt.claims', 'null', false);

  -- Staff (queue member): sees both the public reply and the internal note via raw RLS.
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000286004", "role": "authenticated"}', false);
  set role authenticated;
  select count(*) into v_count from app.ticket_messages where ticket_id = v_ticket_id and visibility = 'internal';
  if v_count <> 1 then raise exception 'FAIL (RLS): staff should see the internal note via raw table RLS, got %', v_count; end if;
  reset role;
  perform set_config('request.jwt.claims', 'null', false);

  raise notice 'PASS: live forged-session RLS probe -- requester sees own ticket + public reply but zero internal notes; bystander sees zero rows; staff sees the internal note. Raw-table access, not RPC -- this is what a direct PostgREST/supabase-js read would see.';
end;
$$;

\echo '>> 6. watchers: explicit add/revoke, department membership alone insufficient'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tkt1');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'HARDWARE');
  v_bystander_emp uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'bystanderwork@tkt1.test');
  v_ticket app.tickets;
  v_watcher app.ticket_watchers;
  v_can_access boolean;
begin
  v_ticket := app.create_ticket(v_tenant1, v_category, null, 'normal', 'Keyboard sticky keys', 'The K key sticks.', 'idem-watch-1', '00000000-0000-0000-0000-000000286002', 'requester1');

  -- Before being watched, the bystander (same dept as requester1 even) has NO access.
  v_can_access := app.can_access_ticket(v_ticket.id, '00000000-0000-0000-0000-000000286006');
  if v_can_access then
    raise exception 'FAIL: bystander should not have access before being added as a watcher';
  end if;

  v_watcher := app.add_ticket_watcher(v_ticket.id, v_bystander_emp, '00000000-0000-0000-0000-000000286002', 'requester1');
  v_can_access := app.can_access_ticket(v_ticket.id, '00000000-0000-0000-0000-000000286006');
  if not v_can_access then
    raise exception 'FAIL: bystander should have access after being added as an explicit watcher';
  end if;

  -- Idempotent re-add.
  if (app.add_ticket_watcher(v_ticket.id, v_bystander_emp, '00000000-0000-0000-0000-000000286002', 'requester1')).id <> v_watcher.id then
    raise exception 'FAIL: re-adding an already-active watcher should be idempotent';
  end if;

  perform app.remove_ticket_watcher(v_watcher.id, v_watcher.record_version, '00000000-0000-0000-0000-000000286002', 'requester1');
  v_can_access := app.can_access_ticket(v_ticket.id, '00000000-0000-0000-0000-000000286006');
  if v_can_access then
    raise exception 'FAIL: bystander should lose access after being removed as a watcher (revocation)';
  end if;

  raise notice 'PASS: watcher add is explicit/idempotent, revocation actually removes access';
end;
$$;

\echo '>> 7. status transition graph: valid chain, invalid jump rejected, self-cancel, staff-only resolve'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tkt1');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'HARDWARE');
  v_ticket app.tickets;
begin
  v_ticket := app.create_ticket(v_tenant1, v_category, null, 'normal', 'Monitor flickering', 'The external monitor flickers.', 'idem-status-1', '00000000-0000-0000-0000-000000286002', 'requester1');

  -- Invalid jump: new -> closed has no row in app.ticket_status_transitions.
  begin
    perform app.transition_ticket_status(v_ticket.id, v_ticket.record_version, 'closed', null, '00000000-0000-0000-0000-000000286004', 'staff1');
    raise exception 'FAIL: new -> closed should be rejected as an invalid transition';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then
        raise exception 'FAIL: expected invalid_transition, got: %', sqlerrm;
      end if;
  end;

  v_ticket := app.transition_ticket_status(v_ticket.id, v_ticket.record_version, 'open', null, '00000000-0000-0000-0000-000000286004', 'staff1');
  if v_ticket.status <> 'open' then raise exception 'FAIL: expected open, got %', v_ticket.status; end if;

  -- A bare requester (no TKT:Close) may not resolve.
  begin
    perform app.transition_ticket_status(v_ticket.id, v_ticket.record_version, 'resolved', 'fixed it myself', '00000000-0000-0000-0000-000000286002', 'requester1');
    raise exception 'FAIL: requester should not be able to resolve a ticket';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then
        raise exception 'FAIL: expected insufficient_authority, got: %', sqlerrm;
      end if;
  end;

  -- staff2 (queue member, but no TKT:Close) may not resolve either.
  begin
    perform app.transition_ticket_status(v_ticket.id, v_ticket.record_version, 'resolved', 'reseated the cable', '00000000-0000-0000-0000-000000286005', 'staff2');
    raise exception 'FAIL: a queue member without TKT:Close should not be able to resolve';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then
        raise exception 'FAIL: expected insufficient_authority, got: %', sqlerrm;
      end if;
  end;

  -- Resolve requires a reason.
  begin
    perform app.transition_ticket_status(v_ticket.id, v_ticket.record_version, 'resolved', null, '00000000-0000-0000-0000-000000286004', 'staff1');
    raise exception 'FAIL: resolve without a reason should be rejected';
  exception
    when others then
      if sqlerrm not like 'reason_required%' then
        raise exception 'FAIL: expected reason_required, got: %', sqlerrm;
      end if;
  end;

  -- staff1 (TKT:Close) resolves.
  v_ticket := app.transition_ticket_status(v_ticket.id, v_ticket.record_version, 'resolved', 'Reseated the cable, confirmed with requester.', '00000000-0000-0000-0000-000000286004', 'staff1');
  if v_ticket.status <> 'resolved' or v_ticket.resolution_summary is null or v_ticket.resolved_at is null then
    raise exception 'FAIL: resolve did not set status/resolution_summary/resolved_at correctly';
  end if;

  -- Requester reopens their own resolved ticket (requester_allowed=true).
  v_ticket := app.transition_ticket_status(v_ticket.id, v_ticket.record_version, 'open', 'It broke again.', '00000000-0000-0000-0000-000000286002', 'requester1');
  if v_ticket.status <> 'open' or v_ticket.reopen_count <> 1 then
    raise exception 'FAIL: requester reopen did not work correctly (status=%, reopen_count=%)', v_ticket.status, v_ticket.reopen_count;
  end if;

  -- Requester self-cancel.
  v_ticket := app.transition_ticket_status(v_ticket.id, v_ticket.record_version, 'cancelled', 'No longer needed.', '00000000-0000-0000-0000-000000286002', 'requester1');
  if v_ticket.status <> 'cancelled' or v_ticket.cancelled_reason is null then
    raise exception 'FAIL: self-cancel did not work correctly';
  end if;

  -- Cancelled is terminal.
  begin
    perform app.transition_ticket_status(v_ticket.id, v_ticket.record_version, 'open', 'reason', '00000000-0000-0000-0000-000000286004', 'staff1');
    raise exception 'FAIL: cancelled should be a terminal state';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then
        raise exception 'FAIL: expected invalid_transition, got: %', sqlerrm;
      end if;
  end;

  -- Cancelled ticket rejects new messages.
  begin
    perform app.reply_to_ticket(v_ticket.id, 'still trying to reply', 'public', null, null, '00000000-0000-0000-0000-000000286002', 'requester1');
    raise exception 'FAIL: a cancelled ticket should reject new messages';
  exception
    when others then
      if sqlerrm not like 'ticket_cancelled%' then
        raise exception 'FAIL: expected ticket_cancelled, got: %', sqlerrm;
      end if;
  end;

  raise notice 'PASS: full status transition graph (valid chain, invalid jump rejected, staff-only resolve, self-cancel/reopen, terminal cancelled, closed-to-new-messages block)';
end;
$$;

\echo '>> 8. assignment validated against real queue staffing'
-- Note: staff1 legitimately holds TKT:Assign in this fixture (the Ticket
-- Admin role, assigned above) -- the real "lacks TKT:Assign" negative case
-- below uses requester1 (a bare requester with no TKT permission at all),
-- and the "structurally invalid target" negative case uses the bystander
-- (not a member of any queue) as the assignment TARGET.
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tkt1');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'HARDWARE');
  v_bystander_emp uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'bystanderwork@tkt1.test');
  v_staff1_emp uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@tkt1.test');
  v_ticket app.tickets;
begin
  v_ticket := app.create_ticket(v_tenant1, v_category, null, 'normal', 'Printer offline', 'The 3rd floor printer is offline.', 'idem-assign-1', '00000000-0000-0000-0000-000000286002', 'requester1');

  -- A bare requester (no TKT:Assign) may not assign.
  begin
    perform app.assign_ticket(v_ticket.id, v_ticket.record_version, v_staff1_emp, '00000000-0000-0000-0000-000000286002', 'requester1');
    raise exception 'FAIL: requester without TKT:Assign should not be able to assign';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then
        raise exception 'FAIL: expected insufficient_authority, got: %', sqlerrm;
      end if;
  end;

  -- staff1 (has TKT:Assign) may not assign to a non-queue-member (bystander).
  begin
    perform app.assign_ticket(v_ticket.id, v_ticket.record_version, v_bystander_emp, '00000000-0000-0000-0000-000000286004', 'staff1');
    raise exception 'FAIL: assigning to a non-queue-member should be rejected';
  exception
    when others then
      if sqlerrm not like 'assignee_not_queue_member%' then
        raise exception 'FAIL: expected assignee_not_queue_member, got: %', sqlerrm;
      end if;
  end;

  -- staff1 assigns to staff1 (a real, active queue member) -- succeeds.
  v_ticket := app.assign_ticket(v_ticket.id, v_ticket.record_version, v_staff1_emp, '00000000-0000-0000-0000-000000286004', 'staff1');
  if v_ticket.assignee_employee_id <> v_staff1_emp then
    raise exception 'FAIL: assignment did not stick';
  end if;
  if v_ticket.status <> 'new' then
    raise exception 'FAIL: assignment must never implicitly change status (decision 6), got status=%', v_ticket.status;
  end if;

  raise notice 'PASS: assignment authority-gated (TKT:Assign) and structurally validated against real queue staffing; no implicit status side effect';
end;
$$;

\echo '>> 9. queue transfer clears assignee; classification change'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tkt1');
  v_queue_b uuid := (select id from app.ticket_queues where tenant_id = v_tenant1 and code = 'FAC');
  v_category_fac uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'FACILITIES');
  v_ticket app.tickets;
begin
  select * into v_ticket from app.tickets where subject = 'Printer offline' limit 1;
  if v_ticket.assignee_employee_id is null then
    raise exception 'FAIL: precondition -- ticket should already be assigned from test 8';
  end if;

  v_ticket := app.transfer_ticket_queue(v_ticket.id, v_ticket.record_version, v_queue_b, 'Actually a facilities issue (power outlet).', '00000000-0000-0000-0000-000000286004', 'staff1');
  if v_ticket.queue_id <> v_queue_b or v_ticket.assignee_employee_id is not null then
    raise exception 'FAIL: transfer should move queue and clear assignee';
  end if;

  v_ticket := app.update_ticket_classification(v_ticket.id, v_ticket.record_version, v_category_fac, 'urgent', '00000000-0000-0000-0000-000000286004', 'staff1');
  if v_ticket.category_id <> v_category_fac or v_ticket.priority <> 'urgent' then
    raise exception 'FAIL: classification change did not stick';
  end if;

  raise notice 'PASS: queue transfer clears assignee, classification change updates category/priority';
end;
$$;

\echo '>> 10. redaction: content genuinely gone, never recoverable via audit_logs'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tkt1');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'HARDWARE');
  v_ticket app.tickets;
  v_msg app.ticket_messages;
  v_updated app.ticket_messages;
  v_leak_count integer;
begin
  v_ticket := app.create_ticket(v_tenant1, v_category, null, 'normal', 'Sensitive complaint', 'This message will be redacted.', 'idem-redact-1', '00000000-0000-0000-0000-000000286002', 'requester1');
  v_msg := app.reply_to_ticket(v_ticket.id, 'CONFIDENTIAL-SECRET-PAYLOAD-XYZ this contains something sensitive', 'internal', null, null, '00000000-0000-0000-0000-000000286004', 'staff1');

  -- staff2 (queue member, no TKT:Edit) may not redact.
  begin
    perform app.redact_ticket_message(v_msg.id, v_msg.record_version, 'contains PII', '00000000-0000-0000-0000-000000286005', 'staff2');
    raise exception 'FAIL: staff2 without TKT:Edit should not be able to redact';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then
        raise exception 'FAIL: expected insufficient_authority, got: %', sqlerrm;
      end if;
  end;

  v_updated := app.redact_ticket_message(v_msg.id, v_msg.record_version, 'contains PII, redacted per policy', '00000000-0000-0000-0000-000000286004', 'staff1');
  if not v_updated.is_redacted or v_updated.body = v_msg.body then
    raise exception 'FAIL: redaction did not overwrite the body';
  end if;
  if v_updated.body like '%CONFIDENTIAL-SECRET-PAYLOAD-XYZ%' then
    raise exception 'FAIL: redacted body still contains the original secret text';
  end if;

  select count(*) into v_leak_count from app.audit_logs
  where (before_value::text like '%CONFIDENTIAL-SECRET-PAYLOAD-XYZ%' or after_value::text like '%CONFIDENTIAL-SECRET-PAYLOAD-XYZ%' or coalesce(reason, '') like '%CONFIDENTIAL-SECRET-PAYLOAD-XYZ%');
  if v_leak_count <> 0 then
    raise exception 'FAIL (C-24): the original message body leaked into app.audit_logs -- % row(s)', v_leak_count;
  end if;

  -- Idempotent re-redact.
  v_updated := app.redact_ticket_message(v_msg.id, v_updated.record_version, 'ignored', '00000000-0000-0000-0000-000000286004', 'staff1');
  if v_updated.body <> '[redacted]' then
    raise exception 'FAIL: re-redacting an already-redacted message should be a safe no-op';
  end if;

  raise notice 'PASS: redaction destroys content in place, zero leakage into app.audit_logs, idempotent re-redact';
end;
$$;

\echo '>> 11. attachment malware-scan gating'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tkt1');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'HARDWARE');
  v_ticket app.tickets;
  v_file_clean uuid;
  v_file_infected uuid;
  v_file_pending uuid;
  v_msg app.ticket_messages;
begin
  v_ticket := app.create_ticket(v_tenant1, v_category, null, 'normal', 'Attachment test', 'See attached screenshot.', 'idem-attach-1', '00000000-0000-0000-0000-000000286002', 'requester1');

  -- Publish a document-type definition for 'ticket_attachment' so
  -- app.initiate_file_upload can resolve it.
  declare
    v_def_version uuid;
  begin
    v_def_version := (app.create_config_draft(
      'document:ticket_attachment', v_tenant1, 'tenant', null, '00000000-0000-0000-0000-000000286001', 'tester'
    )).id;
    perform app.set_config_items(v_def_version, jsonb_build_array(
      jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('image/png', 'application/pdf')),
      jsonb_build_object('key', 'max_size_bytes', 'value', to_jsonb(5000000)),
      jsonb_build_object('key', 'retention_class', 'value', to_jsonb('operational_contract_plus_90d'::text)),
      jsonb_build_object('key', 'default_classification', 'value', to_jsonb('internal'::text)),
      jsonb_build_object('key', 'legal_hold_eligible', 'value', to_jsonb(false))
    ), '00000000-0000-0000-0000-000000286001', 'tester');
    perform app.publish_document_type_definition(v_def_version, '00000000-0000-0000-0000-000000286001', now(), 'tester');
  end;

  v_file_clean := (app.initiate_file_upload(v_tenant1, 'ticket_attachment', 'ticket', v_ticket.id, 'screenshot.png', 'image/png', 1024, null, false, null, '{}', null, 'idem-file-clean', '00000000-0000-0000-0000-000000286002', 'requester1')).id;
  perform app.record_file_scan_result(v_file_clean, 'clean', 'test-scanner', '00000000-0000-0000-0000-000000286002', 'requester1');

  v_file_infected := (app.initiate_file_upload(v_tenant1, 'ticket_attachment', 'ticket', v_ticket.id, 'malware.png', 'image/png', 1024, null, false, null, '{}', null, 'idem-file-infected', '00000000-0000-0000-0000-000000286002', 'requester1')).id;
  perform app.record_file_scan_result(v_file_infected, 'infected', 'test-scanner', '00000000-0000-0000-0000-000000286002', 'requester1');

  v_file_pending := (app.initiate_file_upload(v_tenant1, 'ticket_attachment', 'ticket', v_ticket.id, 'unscanned.png', 'image/png', 1024, null, false, null, '{}', null, 'idem-file-pending', '00000000-0000-0000-0000-000000286002', 'requester1')).id;

  begin
    perform app.reply_to_ticket(v_ticket.id, 'here is a bad file', 'public', array[v_file_infected], null, '00000000-0000-0000-0000-000000286002', 'requester1');
    raise exception 'FAIL: an infected attachment should be rejected';
  exception
    when others then
      if sqlerrm not like 'evidence_file_infected%' then
        raise exception 'FAIL: expected evidence_file_infected, got: %', sqlerrm;
      end if;
  end;

  begin
    perform app.reply_to_ticket(v_ticket.id, 'here is an unscanned file', 'public', array[v_file_pending], null, '00000000-0000-0000-0000-000000286002', 'requester1');
    raise exception 'FAIL: an unscanned attachment should be rejected';
  exception
    when others then
      if sqlerrm not like 'evidence_file_not_scanned%' then
        raise exception 'FAIL: expected evidence_file_not_scanned, got: %', sqlerrm;
      end if;
  end;

  v_msg := app.reply_to_ticket(v_ticket.id, 'here is a clean file', 'public', array[v_file_clean], null, '00000000-0000-0000-0000-000000286002', 'requester1');
  if v_msg.attachment_file_ids <> array[v_file_clean] then
    raise exception 'FAIL: clean attachment should have been accepted';
  end if;

  raise notice 'PASS: attachment malware-scan gating (infected/unscanned rejected, clean accepted)';
end;
$$;

\echo '>> 12. cross-tenant isolation'
do $$
declare
  v_tenant2 uuid := (select id from app.tenants where slug = 'tkt2');
  v_ticket_t1 uuid := (select id from app.tickets where subject = 'Printer offline');
  v_t2_admin uuid := '00000000-0000-0000-0000-000000286021';
  v_can_access boolean;
begin
  v_can_access := app.can_access_ticket(v_ticket_t1, v_t2_admin);
  if v_can_access then
    raise exception 'FAIL: a tenant2 admin should never access a tenant1 ticket';
  end if;

  if exists (select 1 from app.list_tickets(v_tenant2, v_t2_admin, null, null, null, null, null, 50, null) lt where lt.id = v_ticket_t1) then
    raise exception 'FAIL: app.list_tickets leaked a tenant1 ticket into a tenant2 listing';
  end if;

  if (select count(*) from app.get_ticket(v_ticket_t1, v_t2_admin)) <> 0 then
    raise exception 'FAIL: app.get_ticket returned a cross-tenant ticket';
  end if;

  raise notice 'PASS: cross-tenant isolation (can_access_ticket, list_tickets, get_ticket)';
end;
$$;

\echo '>> 13. concurrent double-reply race (real, forged-idempotency-key concurrency, single-session serialized proof)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tkt1');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'HARDWARE');
  v_ticket app.tickets;
  v_m1 app.ticket_messages;
  v_m2 app.ticket_messages;
begin
  v_ticket := app.create_ticket(v_tenant1, v_category, null, 'normal', 'Race test ticket', 'body', 'idem-race-1', '00000000-0000-0000-0000-000000286002', 'requester1');
  -- Two "concurrent" replies with the SAME idempotency key and SAME content
  -- must collapse to one row (the exception-handler path, decision 10) --
  -- true multi-process concurrency is exercised separately in the adversarial
  -- report (two real psql sessions); this asserts the safe-replay half within
  -- one session deterministically.
  v_m1 := app.reply_to_ticket(v_ticket.id, 'same content', 'public', null, 'idem-reply-race', '00000000-0000-0000-0000-000000286002', 'requester1');
  v_m2 := app.reply_to_ticket(v_ticket.id, 'same content', 'public', null, 'idem-reply-race', '00000000-0000-0000-0000-000000286002', 'requester1');
  if v_m1.id <> v_m2.id then
    raise exception 'FAIL: replaying the identical reply with the same idempotency key should collapse to one message';
  end if;
  if (select count(*) from app.ticket_messages where ticket_id = v_ticket.id and idempotency_key = 'idem-reply-race') <> 1 then
    raise exception 'FAIL: exactly one message row should exist for this idempotency key';
  end if;
  raise notice 'PASS: reply idempotency replay collapses to a single row';
end;
$$;

\echo '>> 14. schema-privilege defense in depth (anon has zero access)'
do $$
declare
  v_has_priv boolean;
begin
  select has_table_privilege('anon', 'app.tickets', 'select') into v_has_priv;
  if v_has_priv then
    raise exception 'FAIL: anon should have zero privilege on app.tickets';
  end if;
  select has_function_privilege('anon', 'app.create_ticket(uuid, uuid, uuid, text, text, text, text, uuid, text)', 'execute') into v_has_priv;
  if v_has_priv then
    raise exception 'FAIL: anon should have zero execute privilege on app.create_ticket';
  end if;
  raise notice 'PASS: anon has zero schema privilege on ticket tables/functions';
end;
$$;

\echo '>> 15. every list/get RPC is reachable and returns sane data (C-02 defense: no ambiguous-id crash)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tkt1');
  v_ticket_id uuid := (select id from app.tickets where subject = 'Printer offline');
  v_queue_a uuid := (select id from app.ticket_queues where tenant_id = v_tenant1 and code = 'IT');
  v_count integer;
begin
  select count(*) into v_count from app.list_ticket_queues(v_tenant1, '00000000-0000-0000-0000-000000286002');
  if v_count < 2 then raise exception 'FAIL: list_ticket_queues returned too few rows (%)', v_count; end if;

  select count(*) into v_count from app.list_ticket_categories(v_tenant1, '00000000-0000-0000-0000-000000286002');
  if v_count < 2 then raise exception 'FAIL: list_ticket_categories returned too few rows (%)', v_count; end if;

  select count(*) into v_count from app.list_ticket_queue_members(v_queue_a, '00000000-0000-0000-0000-000000286004');
  if v_count <> 2 then raise exception 'FAIL: list_ticket_queue_members expected 2, got %', v_count; end if;

  select count(*) into v_count from app.get_ticket(v_ticket_id, '00000000-0000-0000-0000-000000286004');
  if v_count <> 1 then raise exception 'FAIL: get_ticket (ambiguous-id C-02 probe) expected 1 row, got %', v_count; end if;

  select count(*) into v_count from app.list_tickets(v_tenant1, '00000000-0000-0000-0000-000000286004', null, null, null, null, null, 50, null);
  if v_count < 1 then raise exception 'FAIL: list_tickets returned zero rows for staff1'; end if;

  select count(*) into v_count from app.list_my_tickets(v_tenant1, '00000000-0000-0000-0000-000000286002', null, 50, null);
  if v_count < 1 then raise exception 'FAIL: list_my_tickets returned zero rows for requester1'; end if;

  select count(*) into v_count from app.list_ticket_messages(v_ticket_id, '00000000-0000-0000-0000-000000286004', 100, null);
  if v_count < 1 then raise exception 'FAIL: list_ticket_messages returned zero rows'; end if;

  select count(*) into v_count from app.list_ticket_watchers(
    (select id from app.tickets where subject = 'Keyboard sticky keys'), '00000000-0000-0000-0000-000000286002'
  );
  -- watcher was removed in test 6, so 0 active watchers is correct here.
  if v_count <> 0 then raise exception 'FAIL: list_ticket_watchers expected 0 active watchers after revocation, got %', v_count; end if;

  select count(*) into v_count from app.list_ticket_events(v_ticket_id, '00000000-0000-0000-0000-000000286004');
  if v_count < 1 then raise exception 'FAIL: list_ticket_events returned zero rows (ambiguous-id C-02 probe)'; end if;

  select count(*) into v_count from app.export_tickets(v_tenant1, '00000000-0000-0000-0000-000000286004', (current_date - interval '1 year')::date, current_date);
  if v_count < 1 then raise exception 'FAIL: export_tickets returned zero rows for a TKT:Export holder'; end if;

  raise notice 'PASS: every list/get/export RPC reachable, no ambiguous-id crash (C-02 defense), sane row counts';
end;
$$;

\echo '>> 16. closed/cancelled tickets are mutation-inert for app.add_ticket_watcher and app.reply_to_ticket (new-engagement operations); app.remove_ticket_watcher remains permitted as legitimate post-closure cleanup (HRT-295 fix for ISS-2026-109, supabase/migrations/20260731270000)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tkt1');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'HARDWARE');
  v_staff1 uuid := '00000000-0000-0000-0000-000000286004';
  v_req1 uuid := '00000000-0000-0000-0000-000000286002';
  v_bystander_emp uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'bystanderwork@tkt1.test');
  v_ticket_closed app.tickets;
  v_ticket_cancelled app.tickets;
  v_watcher app.ticket_watchers;
  v_msg text;
begin
  -- Ticket A -> driven to CLOSED (new -> open -> resolved -> closed, the
  -- real graph app.ticket_status_transitions defines).
  v_ticket_closed := app.create_ticket(v_tenant1, v_category, null, 'normal', 'Terminal Status Guard Test A', 'body', 'idem-term-closed-a', v_req1, 'requester1');
  v_watcher := app.add_ticket_watcher(v_ticket_closed.id, v_bystander_emp, v_staff1, 'staff1');
  v_ticket_closed := app.transition_ticket_status(v_ticket_closed.id, v_ticket_closed.record_version, 'open', null, v_staff1, 'staff1');
  v_ticket_closed := app.transition_ticket_status(v_ticket_closed.id, v_ticket_closed.record_version, 'resolved', 'done', v_staff1, 'staff1');
  v_ticket_closed := app.transition_ticket_status(v_ticket_closed.id, v_ticket_closed.record_version, 'closed', null, v_staff1, 'staff1');
  if v_ticket_closed.status <> 'closed' then raise exception 'FAIL (fixture bug): ticket A must be closed'; end if;

  begin
    perform app.add_ticket_watcher(v_ticket_closed.id, v_bystander_emp, v_staff1, 'staff1');
    raise exception 'FAIL: adding a watcher to a closed ticket must be rejected';
  exception when others then
    v_msg := sqlerrm;
    if v_msg not like 'invalid_transition%' then raise exception 'FAIL: expected invalid_transition, got: %', v_msg; end if;
  end;

  begin
    perform app.reply_to_ticket(v_ticket_closed.id, 'still trying to reply after close', 'public', null, null, v_req1, 'requester1');
    raise exception 'FAIL: a closed ticket should reject new messages';
  exception when others then
    v_msg := sqlerrm;
    if v_msg not like 'ticket_closed%' then raise exception 'FAIL: expected ticket_closed, got: %', v_msg; end if;
  end;

  -- Removal of the PRE-EXISTING watcher (added before close) remains
  -- permitted -- deliberate design decision, see the migration's own
  -- header: cleanup is not a new engagement.
  perform app.remove_ticket_watcher(v_watcher.id, v_watcher.record_version, v_staff1, 'staff1');
  if (select status from app.ticket_watchers where id = v_watcher.id) <> 'removed' then
    raise exception 'FAIL: remove_ticket_watcher must still succeed on a closed ticket (cleanup remains permitted)';
  end if;

  -- Ticket B -> driven to CANCELLED (new -> cancelled, self-cancel).
  v_ticket_cancelled := app.create_ticket(v_tenant1, v_category, null, 'normal', 'Terminal Status Guard Test B', 'body', 'idem-term-cancel-b', v_req1, 'requester1');
  v_watcher := app.add_ticket_watcher(v_ticket_cancelled.id, v_bystander_emp, v_staff1, 'staff1');
  v_ticket_cancelled := app.transition_ticket_status(v_ticket_cancelled.id, v_ticket_cancelled.record_version, 'cancelled', 'no longer needed', v_req1, 'requester1');
  if v_ticket_cancelled.status <> 'cancelled' then raise exception 'FAIL (fixture bug): ticket B must be cancelled'; end if;

  begin
    perform app.add_ticket_watcher(v_ticket_cancelled.id, v_bystander_emp, v_staff1, 'staff1');
    raise exception 'FAIL: adding a watcher to a cancelled ticket must be rejected';
  exception when others then
    v_msg := sqlerrm;
    if v_msg not like 'invalid_transition%' then raise exception 'FAIL: expected invalid_transition, got: %', v_msg; end if;
  end;

  begin
    perform app.reply_to_ticket(v_ticket_cancelled.id, 'still trying to reply after cancel', 'public', null, null, v_req1, 'requester1');
    raise exception 'FAIL: a cancelled ticket should reject new messages (re-confirms section 7''s own pre-existing assertion, co-located here for the full closed/cancelled matrix)';
  exception when others then
    v_msg := sqlerrm;
    if v_msg not like 'ticket_cancelled%' then raise exception 'FAIL: expected ticket_cancelled, got: %', v_msg; end if;
  end;

  perform app.remove_ticket_watcher(v_watcher.id, v_watcher.record_version, v_staff1, 'staff1');
  if (select status from app.ticket_watchers where id = v_watcher.id) <> 'removed' then
    raise exception 'FAIL: remove_ticket_watcher must still succeed on a cancelled ticket (cleanup remains permitted)';
  end if;

  raise notice 'PASS: add_ticket_watcher and reply_to_ticket reject both closed and cancelled tickets (invalid_transition / ticket_closed / ticket_cancelled); remove_ticket_watcher remains permitted on both as the deliberate cleanup-is-allowed design decision';
end;
$$;

\echo '>> ISS-2026-086: TKT:Edit and the tenant-wide ticket-content override are now separate, separately-revocable grants. A config-only TKT:Edit holder is NOT ticket staff on a queue they do not belong to; adding TKT:Override makes them staff; revoking it alone takes the content access away and leaves the configuration authority intact'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tkt1');
  v_config_only uuid := '00000000-0000-0000-0000-000000286010';
  v_role uuid;
  v_draft app.role_versions;
  v_ticket app.tickets;
begin
  -- 286010: the next free id in this file's own documented 286001..286006 fixture range.
  insert into auth.users (id, email) values (v_config_only, 'configonly@tkt1.test');
  perform app.invite_user(v_tenant1, v_config_only, 'configonly@tkt1.test', 'Tkt1 Config Only', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'configonly@tkt1.test'), 'active', 'onboarded', 'tester');

  -- A genuine queue/category administrator: TKT:Edit and nothing else. Before this fix, this
  -- identity silently held the contents of every ticket in the tenant.
  v_role := (app.create_role(v_tenant1, 'Ticket Config Only', 'TKT Edit alone -- the ISS-2026-086 control', 'tester')).id;
  v_draft := app.create_role_version(v_role, 'tester');
  perform app.set_role_version_permissions(v_draft.id, array(select id from app.permissions where resource_module_code = 'TKT' and action = 'Edit'), 'tester');
  perform app.publish_role_version(v_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_role and status = 'published'), v_config_only, '00000000-0000-0000-0000-000000286001', 'tester');

  if not (app.evaluate_permission(v_config_only, v_tenant1, 'TKT', 'Edit')).allowed then
    raise exception 'assertion failed: the control identity must genuinely hold TKT:Edit';
  end if;
  if (app.evaluate_permission(v_config_only, v_tenant1, 'TKT', 'Override')).allowed then
    raise exception 'assertion failed: the control identity must NOT hold TKT:Override -- that is what makes this test meaningful';
  end if;

  select * into v_ticket from app.tickets where tenant_id = v_tenant1 and channel <> 'helpdesk' limit 1;
  if v_ticket.id is null then
    raise exception 'assertion failed: this test needs a real non-helpdesk ticket from the fixtures above';
  end if;

  -- The fix: configuration authority alone is no longer ticket-content staff status.
  if app.is_ticket_staff(v_ticket.id, v_config_only) then
    raise exception 'assertion failed: a TKT:Edit-only identity must NOT be ticket staff on a queue it does not belong to -- that is exactly ISS-2026-086';
  end if;

  -- And the override still exists for tenants that genuinely want it: it is now a thing they
  -- grant on purpose rather than a thing they cannot avoid granting.
  v_draft := app.create_role_version(v_role, 'tester');
  perform app.set_role_version_permissions(v_draft.id, array(select id from app.permissions where resource_module_code = 'TKT' and action in ('Edit', 'Override')), 'tester');
  perform app.publish_role_version(v_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, v_draft.id, v_config_only, '00000000-0000-0000-0000-000000286001', 'tester');

  if not app.is_ticket_staff(v_ticket.id, v_config_only) then
    raise exception 'assertion failed: adding TKT:Override must confer the tenant-wide ticket-content staff status';
  end if;

  -- The half this whole finding is about: the content access is revocable ON ITS OWN, without
  -- taking the queue/category configuration authority with it. Before the split, revoking one
  -- necessarily revoked the other, because they were the same grant.
  v_draft := app.create_role_version(v_role, 'tester');
  perform app.set_role_version_permissions(v_draft.id, array(select id from app.permissions where resource_module_code = 'TKT' and action = 'Edit'), 'tester');
  perform app.publish_role_version(v_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, v_draft.id, v_config_only, '00000000-0000-0000-0000-000000286001', 'tester');

  if app.is_ticket_staff(v_ticket.id, v_config_only) then
    raise exception 'assertion failed: revoking TKT:Override alone must remove the tenant-wide content access';
  end if;
  if not (app.evaluate_permission(v_config_only, v_tenant1, 'TKT', 'Edit')).allowed then
    raise exception 'assertion failed: revoking TKT:Override must NOT take the TKT:Edit configuration authority with it';
  end if;

  raise notice 'PASS: ISS-2026-086 -- TKT:Edit no longer carries tenant-wide ticket-content staff status; TKT:Override does, and is grantable and revocable on its own';
end;
$$;

\echo '>> 17. ISS-2026-087: app.initiate_ticket_attachment_upload -- requester-or-staff-gated, malware-scan-gated identically to app.reply_to_ticket''s own direct-file-id path (section 11), terminal-status- and cross-tenant-safe'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'tkt1');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'HARDWARE');
  v_bystander_emp uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'bystanderwork@tkt1.test');
  v_ticket app.tickets;
  v_ticket_closed app.tickets;
  v_ticket_cancelled app.tickets;
  v_file_req record;
  v_file_staff record;
  v_file_clean uuid;
  v_file_infected uuid;
  v_file_pending uuid;
  v_msg app.ticket_messages;
  v_msg_text text;
  v_watcher app.ticket_watchers;
begin
  v_ticket := app.create_ticket(v_tenant1, v_category, null, 'normal', 'ISS-2026-087 upload-path test', 'See attached.', 'idem-iss087-1', '00000000-0000-0000-0000-000000286002', 'requester1');

  -- 17a. The requester-side party may stage an attachment against their own
  -- ticket through the NEW gated RPC (never the raw, unauthorized
  -- app.initiate_file_upload primitive).
  select * into v_file_req from app.initiate_ticket_attachment_upload(v_ticket.id, 'requester-photo.png', 'image/png', 2048, null, 'idem-iss087-req-file', '00000000-0000-0000-0000-000000286002', 'requester1');
  if v_file_req.document_type_code <> 'ticket_attachment' or v_file_req.record_type <> 'ticket' or v_file_req.record_id <> v_ticket.id then
    raise exception 'FAIL: app.initiate_ticket_attachment_upload returned a file not correctly scoped to document_type_code=ticket_attachment/record_type=ticket/record_id=<ticket>, got type=% record_type=% record_id=%', v_file_req.document_type_code, v_file_req.record_type, v_file_req.record_id;
  end if;
  if v_file_req.tenant_id <> v_tenant1 then
    raise exception 'FAIL: uploaded file tenant_id must be the ticket''s own tenant';
  end if;

  -- 17b. Ticket staff may ALSO stage an attachment against the same ticket.
  select * into v_file_staff from app.initiate_ticket_attachment_upload(v_ticket.id, 'staff-annotation.png', 'image/png', 2048, null, 'idem-iss087-staff-file', '00000000-0000-0000-0000-000000286004', 'staff1');
  if v_file_staff.id is null then
    raise exception 'FAIL: ticket staff must be able to stage an attachment too';
  end if;

  -- 17c. A genuinely unrelated bystander (same tenant, zero participation on
  -- THIS ticket) gets the SAME ticket_not_found a nonexistent ticket id
  -- would produce -- existence-oracle-safe, mirroring app.reply_to_ticket's
  -- own C-05 discipline (section 5/12 above) and never insufficient_authority.
  begin
    perform app.initiate_ticket_attachment_upload(v_ticket.id, 'sneaky.png', 'image/png', 1024, null, 'idem-iss087-bystander', '00000000-0000-0000-0000-000000286006', 'bystander');
    raise exception 'FAIL: a non-participant bystander must not be able to stage an attachment';
  exception
    when others then
      get stacked diagnostics v_msg_text = message_text;
      if v_msg_text not like 'ticket_not_found%' then
        raise exception 'FAIL: expected ticket_not_found for a non-participant bystander, got: %', v_msg_text;
      end if;
  end;

  -- 17d. Once the SAME bystander is an explicit, structurally-scoped WATCHER
  -- (app.can_access_ticket now true for them), the bar shifts from
  -- ticket_not_found to insufficient_authority -- proving this RPC checks
  -- the actual requester-or-staff participation bar (mirroring
  -- app.reply_to_ticket's own identical two-tier check), not merely
  -- "can this identity see the ticket at all."
  v_watcher := app.add_ticket_watcher(v_ticket.id, v_bystander_emp, '00000000-0000-0000-0000-000000286002', 'requester1');
  begin
    perform app.initiate_ticket_attachment_upload(v_ticket.id, 'watcher-file.png', 'image/png', 1024, null, 'idem-iss087-watcher', '00000000-0000-0000-0000-000000286006', 'bystander');
    raise exception 'FAIL: a plain watcher (not requester, not staff) must not be able to stage an attachment';
  exception
    when others then
      get stacked diagnostics v_msg_text = message_text;
      if v_msg_text not like 'insufficient_authority%' then
        raise exception 'FAIL: expected insufficient_authority for a watcher-only identity, got: %', v_msg_text;
      end if;
  end;
  perform app.remove_ticket_watcher(v_watcher.id, v_watcher.record_version, '00000000-0000-0000-0000-000000286002', 'requester1');

  -- 17e. A tenant2 identity gets ticket_not_found against a tenant1 ticket
  -- (cross-tenant isolation, mirroring section 12 above).
  begin
    perform app.initiate_ticket_attachment_upload(v_ticket.id, 'cross-tenant.png', 'image/png', 1024, null, 'idem-iss087-crosstenant', '00000000-0000-0000-0000-000000286022', 'tkt2-requester1');
    raise exception 'FAIL: a tenant2 identity must not be able to stage an attachment against a tenant1 ticket';
  exception
    when others then
      get stacked diagnostics v_msg_text = message_text;
      if v_msg_text not like 'ticket_not_found%' then
        raise exception 'FAIL: expected ticket_not_found for a cross-tenant identity, got: %', v_msg_text;
      end if;
  end;

  raise notice 'PASS: app.initiate_ticket_attachment_upload -- requester and staff may stage an attachment; a non-participant gets ticket_not_found (existence-oracle-safe); a plain watcher gets insufficient_authority (proves the real requester-or-staff bar, not just can_access_ticket); a cross-tenant identity gets ticket_not_found';

  -- 17f. Malware-scan gating, exercised through the NEW RPC end-to-end
  -- (upload -> scan -> reply), identical outcomes to section 11's own
  -- direct-app.initiate_file_upload path -- proves the two upload paths are
  -- fully interchangeable from app.reply_to_ticket's point of view.
  v_file_clean := (app.initiate_ticket_attachment_upload(v_ticket.id, 'clean.png', 'image/png', 1024, null, 'idem-iss087-clean', '00000000-0000-0000-0000-000000286002', 'requester1')).id;
  perform app.record_file_scan_result(v_file_clean, 'clean', 'test-scanner', '00000000-0000-0000-0000-000000286002', 'requester1');

  v_file_infected := (app.initiate_ticket_attachment_upload(v_ticket.id, 'infected.png', 'image/png', 1024, null, 'idem-iss087-infected', '00000000-0000-0000-0000-000000286002', 'requester1')).id;
  perform app.record_file_scan_result(v_file_infected, 'infected', 'test-scanner', '00000000-0000-0000-0000-000000286002', 'requester1');

  v_file_pending := (app.initiate_ticket_attachment_upload(v_ticket.id, 'pending.png', 'image/png', 1024, null, 'idem-iss087-pending', '00000000-0000-0000-0000-000000286002', 'requester1')).id;

  begin
    perform app.reply_to_ticket(v_ticket.id, 'attaching an infected file via the new upload path', 'public', array[v_file_infected], null, '00000000-0000-0000-0000-000000286002', 'requester1');
    raise exception 'FAIL: an infected attachment staged via the new RPC should still be rejected by app.reply_to_ticket';
  exception
    when others then
      get stacked diagnostics v_msg_text = message_text;
      if v_msg_text not like 'evidence_file_infected%' then
        raise exception 'FAIL: expected evidence_file_infected, got: %', v_msg_text;
      end if;
  end;

  begin
    perform app.reply_to_ticket(v_ticket.id, 'attaching an unscanned file via the new upload path', 'public', array[v_file_pending], null, '00000000-0000-0000-0000-000000286002', 'requester1');
    raise exception 'FAIL: an unscanned attachment staged via the new RPC should still be rejected by app.reply_to_ticket';
  exception
    when others then
      get stacked diagnostics v_msg_text = message_text;
      if v_msg_text not like 'evidence_file_not_scanned%' then
        raise exception 'FAIL: expected evidence_file_not_scanned, got: %', v_msg_text;
      end if;
  end;

  -- The full, real round trip: stage via the new RPC, clear scanning,
  -- attach via app.reply_to_ticket -- exactly the path ISS-2026-087's own
  -- new Server Action drives. Both attachments must clear scanning BEFORE
  -- the reply -- app.reply_to_ticket rejects any non-'clean' file in the
  -- array atomically (section 11's own established behavior), so scanning
  -- v_file_req.id AFTER the call would make this assertion pass for the
  -- wrong reason (17f above already proves the pending-file rejection).
  perform app.record_file_scan_result(v_file_req.id, 'clean', 'test-scanner', '00000000-0000-0000-0000-000000286002', 'requester1');
  v_msg := app.reply_to_ticket(v_ticket.id, 'here is a clean file via the new upload path', 'public', array[v_file_clean, v_file_req.id], null, '00000000-0000-0000-0000-000000286002', 'requester1');
  if not (v_msg.attachment_file_ids @> array[v_file_clean, v_file_req.id]) then
    raise exception 'FAIL: both clean attachments staged via the new RPC should round-trip through app.reply_to_ticket onto the resulting message';
  end if;

  raise notice 'PASS: app.initiate_ticket_attachment_upload round-trips through app.reply_to_ticket''s malware-scan gating identically to the direct-app.initiate_file_upload path (section 11) -- infected/unscanned rejected, clean accepted';

  -- 17g. Terminal-status guard: a cancelled or closed ticket refuses a NEW
  -- attachment upload with the same ticket_cancelled/ticket_closed
  -- app.reply_to_ticket itself already raises for a new message on the same
  -- ticket (section 16 above) -- proven with two fresh tickets so this
  -- section never depends on section 16's own fixtures/state.
  v_ticket_cancelled := app.create_ticket(v_tenant1, v_category, null, 'normal', 'ISS-2026-087 cancelled-guard test', 'body', 'idem-iss087-cancel', '00000000-0000-0000-0000-000000286002', 'requester1');
  v_ticket_cancelled := app.transition_ticket_status(v_ticket_cancelled.id, v_ticket_cancelled.record_version, 'cancelled', 'no longer needed', '00000000-0000-0000-0000-000000286002', 'requester1');
  begin
    perform app.initiate_ticket_attachment_upload(v_ticket_cancelled.id, 'too-late.png', 'image/png', 1024, null, 'idem-iss087-cancel-upload', '00000000-0000-0000-0000-000000286002', 'requester1');
    raise exception 'FAIL: a cancelled ticket must refuse a new attachment upload';
  exception
    when others then
      get stacked diagnostics v_msg_text = message_text;
      if v_msg_text not like 'ticket_cancelled%' then
        raise exception 'FAIL: expected ticket_cancelled, got: %', v_msg_text;
      end if;
  end;

  v_ticket_closed := app.create_ticket(v_tenant1, v_category, null, 'normal', 'ISS-2026-087 closed-guard test', 'body', 'idem-iss087-close', '00000000-0000-0000-0000-000000286002', 'requester1');
  v_ticket_closed := app.transition_ticket_status(v_ticket_closed.id, v_ticket_closed.record_version, 'open', null, '00000000-0000-0000-0000-000000286004', 'staff1');
  v_ticket_closed := app.transition_ticket_status(v_ticket_closed.id, v_ticket_closed.record_version, 'resolved', 'done', '00000000-0000-0000-0000-000000286004', 'staff1');
  v_ticket_closed := app.transition_ticket_status(v_ticket_closed.id, v_ticket_closed.record_version, 'closed', null, '00000000-0000-0000-0000-000000286004', 'staff1');
  begin
    perform app.initiate_ticket_attachment_upload(v_ticket_closed.id, 'too-late.png', 'image/png', 1024, null, 'idem-iss087-close-upload', '00000000-0000-0000-0000-000000286004', 'staff1');
    raise exception 'FAIL: a closed ticket must refuse a new attachment upload';
  exception
    when others then
      get stacked diagnostics v_msg_text = message_text;
      if v_msg_text not like 'ticket_closed%' then
        raise exception 'FAIL: expected ticket_closed, got: %', v_msg_text;
      end if;
  end;

  raise notice 'PASS: app.initiate_ticket_attachment_upload refuses a new attachment upload against a cancelled (ticket_cancelled) or closed (ticket_closed) ticket, mirroring app.reply_to_ticket''s own terminal-status guard (HRT-295)';

  -- 17h. Schema-privilege defense in depth, mirroring section 14 above's own
  -- static-catalog-check technique (has_function_privilege, not a live
  -- role switch): anon has zero EXECUTE on either the app.* function or its
  -- public.* wrapper.
  declare
    v_has_priv boolean;
  begin
    select has_function_privilege('anon', 'app.initiate_ticket_attachment_upload(uuid, text, text, bigint, text, text, uuid, text)', 'execute') into v_has_priv;
    if v_has_priv then
      raise exception 'FAIL: anon should have zero execute privilege on app.initiate_ticket_attachment_upload';
    end if;
    select has_function_privilege('anon', 'public.initiate_ticket_attachment_upload(uuid, text, text, bigint, text, text, uuid, text)', 'execute') into v_has_priv;
    if v_has_priv then
      raise exception 'FAIL: anon should have zero execute privilege on public.initiate_ticket_attachment_upload';
    end if;
  end;

  raise notice 'PASS: app.initiate_ticket_attachment_upload and its public.* wrapper -- anon has zero schema privilege, defense in depth mirroring section 14';
end;
$$;

\echo '>> all ticketing-internal (HRT-286) assertions passed'
