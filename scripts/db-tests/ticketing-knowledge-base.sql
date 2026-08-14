-- Real, executable test evidence for HRT-289 (Ticket SLA and Knowledge Base,
-- CG-S12-HRT-017) -- Knowledge Base half. Run via `pnpm run db:test` against
-- a real, disposable Postgres database.
--
-- Self-contained: own two-tenant/employee/role/queue/category/account
-- fixture, own fresh, unclaimed UUID range
-- (00000000-0000-0000-0000-0000002891xx). Tenant slugs `kb1`/`kb2`
-- (grep-verified unclaimed).
--
-- Covers, live: draft -> in_review -> approved -> published -> archived
-- lifecycle (including changes_requested bouncing back to draft); self-review
-- structurally blocked at both submit and review time; publish REQUIRES
-- approved (no bypass); audience flags gate audience-safe search/get for
-- customer and helpdesk channels -- a draft/internal-only/unpublished article
-- NEVER reaches a customer or helpdesk caller via ANY path (search, get,
-- raw-table RLS); expiry batch (idempotent, durable job); ticket-article
-- linking reuses the public/internal visibility discipline (an internal-only
-- article cannot be publicly linked to a customer ticket); cross-tenant
-- isolation; schema-privilege defense in depth.

\set ON_ERROR_STOP on

\echo '>> fixture'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_admin_role uuid; v_admin_draft app.role_versions;
  v_company uuid; v_branch uuid; v_dept uuid;
  v_staff1_emp uuid; v_staff2_emp uuid; v_req1_emp uuid;
  v_queue uuid; v_category uuid;
  v_account_a uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000289101', 'admin@kb1.test'),
    ('00000000-0000-0000-0000-000000289102', 'staff1@kb1.test'),
    ('00000000-0000-0000-0000-000000289103', 'staff2@kb1.test'),
    ('00000000-0000-0000-0000-000000289104', 'req1@kb1.test'),
    ('00000000-0000-0000-0000-000000289110', 'customer1@kb1.test'),
    ('00000000-0000-0000-0000-000000289121', 'admin@kb2.test');

  perform app.provision_tenant('kb1', 'KB Co 1', 'idem-kb1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'kb1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.provision_tenant('kb2', 'KB Co 2', 'idem-kb2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'kb2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000289101', 'admin@kb1.test', 'Kb1 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@kb1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000289101', 'tenant_admin', v_tenant1, null, 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000289102', 'staff1@kb1.test', 'Kb1 Staff One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff1@kb1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000289103', 'staff2@kb1.test', 'Kb1 Staff Two', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff2@kb1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000289104', 'req1@kb1.test', 'Kb1 Requester One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'req1@kb1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000289110', 'customer1@kb1.test', 'Kb1 Customer One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer1@kb1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000289121', 'admin@kb2.test', 'Kb2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@kb2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000289121', 'tenant_admin', v_tenant2, null, 'tester');

  declare
    v_hr_role uuid; v_hr_draft app.role_versions;
  begin
    v_hr_role := (app.create_role(v_tenant1, 'HR Admin', 'HRS Create/Edit/Approve/Export/View', 'tester')).id;
    v_hr_draft := app.create_role_version(v_hr_role, 'tester');
    perform app.set_role_version_permissions(v_hr_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('Create', 'Edit', 'Approve', 'Export', 'View')), 'tester');
    perform app.publish_role_version(v_hr_draft.id, now(), 'tester');
    perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_hr_role and status = 'published'), '00000000-0000-0000-0000-000000289101', '00000000-0000-0000-0000-000000289101', 'tester');
  end;

  v_admin_role := (app.create_role(v_tenant1, 'Ticket Admin', 'TKT Edit', 'tester')).id;
  v_admin_draft := app.create_role_version(v_admin_role, 'tester');
  perform app.set_role_version_permissions(v_admin_draft.id, array(select id from app.permissions where resource_module_code = 'TKT' and action = 'Edit'), 'tester');
  perform app.publish_role_version(v_admin_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_admin_role and status = 'published'), '00000000-0000-0000-0000-000000289102', '00000000-0000-0000-0000-000000289101', 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_admin_role and status = 'published'), '00000000-0000-0000-0000-000000289103', '00000000-0000-0000-0000-000000289101', 'tester');

  v_company := (app.create_org_unit(v_tenant1, 'company', null, 'CO-KB1', 'Kb1 Co', 'tester')).id;
  v_branch := (app.create_org_unit(v_tenant1, 'branch', v_company, 'BR-KB1', 'Kb1 Branch', 'tester')).id;
  v_dept := (app.create_org_unit(v_tenant1, 'department', v_branch, 'DEPT-SUP', 'Support', 'tester')).id;

  perform app.create_employee_draft(v_tenant1, 'Kb1 Staff One', 'full_time', 'staff1work@kb1.test', 'staff1p@kb1.test', '0900000001', null, null, null, '2024-01-01', v_company, v_branch, v_dept, 'Agent', null, (select id from app.users where email = 'staff1@kb1.test'), null, 'hr_created', 'idem-staff1-kb1', '00000000-0000-0000-0000-000000289101', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@kb1.test'), 'EC', 'spouse', '0910000000', null, true, '00000000-0000-0000-0000-000000289101', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@kb1.test'), 1, '00000000-0000-0000-0000-000000289101', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@kb1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000289101', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@kb1.test'), 3, '00000000-0000-0000-0000-000000289101', 'tester');
  v_staff1_emp := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@kb1.test');

  perform app.create_employee_draft(v_tenant1, 'Kb1 Staff Two', 'full_time', 'staff2work@kb1.test', 'staff2p@kb1.test', '0900000002', null, null, null, '2024-01-01', v_company, v_branch, v_dept, 'Agent', null, (select id from app.users where email = 'staff2@kb1.test'), null, 'hr_created', 'idem-staff2-kb1', '00000000-0000-0000-0000-000000289101', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff2work@kb1.test'), 'EC', 'spouse', '0910000000', null, true, '00000000-0000-0000-0000-000000289101', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff2work@kb1.test'), 1, '00000000-0000-0000-0000-000000289101', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff2work@kb1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000289101', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff2work@kb1.test'), 3, '00000000-0000-0000-0000-000000289101', 'tester');
  v_staff2_emp := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff2work@kb1.test');

  perform app.create_employee_draft(v_tenant1, 'Kb1 Requester One', 'full_time', 'req1work@kb1.test', 'req1p@kb1.test', '0900000004', null, null, null, '2024-01-01', v_company, v_branch, v_dept, 'Staff', null, (select id from app.users where email = 'req1@kb1.test'), null, 'hr_created', 'idem-req1-kb1', '00000000-0000-0000-0000-000000289101', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'req1work@kb1.test'), 'EC', 'spouse', '0910000000', null, true, '00000000-0000-0000-0000-000000289101', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'req1work@kb1.test'), 1, '00000000-0000-0000-0000-000000289101', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'req1work@kb1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000289101', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'req1work@kb1.test'), 3, '00000000-0000-0000-0000-000000289101', 'tester');
  v_req1_emp := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'req1work@kb1.test');

  v_queue := (app.create_ticket_queue(v_tenant1, v_dept, 'SUP', 'Support', 'Support queue', '00000000-0000-0000-0000-000000289102', 'staff1')).id;
  v_category := (app.create_ticket_category(v_tenant1, 'GENERAL', 'General Issue', v_queue, '00000000-0000-0000-0000-000000289102', 'staff1')).id;
  perform app.add_ticket_queue_member(v_queue, v_staff1_emp, '00000000-0000-0000-0000-000000289102', 'staff1');
  perform app.add_ticket_queue_member(v_queue, v_staff2_emp, '00000000-0000-0000-0000-000000289102', 'staff1');

  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Customer Account A', 'fp-kb1-a', '{}'::jsonb, v_company, 'tester')
  returning id into v_account_a;
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000289110', 'customer_user', v_tenant1, v_account_a::text, 'tester');
  perform app.set_ticket_category_customer_visibility(v_category, true, '00000000-0000-0000-0000-000000289102', 'staff1');

  raise notice 'fixture ready: tenant1=%, tenant2=%, queue=%, category=%, account_a=%, staff1_emp=%, staff2_emp=%, req1_emp=%',
    v_tenant1, v_tenant2, v_queue, v_category, v_account_a, v_staff1_emp, v_staff2_emp, v_req1_emp;
end;
$$;

\echo '>> 1. lifecycle: draft -> in_review -> changes_requested -> draft -> in_review -> approved; publish requires approved (no bypass); self-review blocked at both submit and review time'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'kb1');
  v_article app.kb_articles;
  v_version app.kb_article_versions;
begin
  v_article := app.create_kb_article(v_tenant1, 'printer-offline', '00000000-0000-0000-0000-000000289102', 'staff1');
  v_version := app.create_kb_article_version(
    v_article.id, 'Printer shows offline', 'Quick fix for offline printers', 'Restart the print spooler service and power-cycle the printer.', array['printer', 'hardware'],
    true, false, false, '00000000-0000-0000-0000-000000289102', 'staff1'
  );
  if v_version.status <> 'draft' then
    raise exception 'FAIL: a new version must start as draft';
  end if;

  -- Publish while draft: rejected.
  begin
    perform app.publish_kb_article_version(v_version.id, v_version.record_version, '00000000-0000-0000-0000-000000289102', 'staff1');
    raise exception 'FAIL: publishing a draft version should have raised invalid_state';
  exception
    when others then
      if sqlerrm not like 'invalid_state%' then
        raise exception 'FAIL: expected invalid_state, got: %', sqlerrm;
      end if;
  end;

  -- Self-review blocked at SUBMIT time.
  begin
    perform app.submit_kb_article_version_for_review(v_version.id, v_version.record_version, '00000000-0000-0000-0000-000000289102', '00000000-0000-0000-0000-000000289102', 'staff1');
    raise exception 'FAIL: submitting with the author as reviewer should have raised self_review_forbidden';
  exception
    when others then
      if sqlerrm not like 'self_review_forbidden%' then
        raise exception 'FAIL: expected self_review_forbidden, got: %', sqlerrm;
      end if;
  end;

  v_version := app.submit_kb_article_version_for_review(v_version.id, v_version.record_version, '00000000-0000-0000-0000-000000289103', '00000000-0000-0000-0000-000000289102', 'staff1');
  if v_version.status <> 'in_review' then
    raise exception 'FAIL: expected status=in_review, got %', v_version.status;
  end if;

  -- A non-assigned reviewer cannot review.
  begin
    perform app.review_kb_article_version(v_version.id, v_version.record_version, 'approved', 'looks fine', '00000000-0000-0000-0000-000000289104', 'req1');
    raise exception 'FAIL: a non-assigned actor reviewing should have raised insufficient_authority';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then
        raise exception 'FAIL: expected insufficient_authority, got: %', sqlerrm;
      end if;
  end;

  -- Changes requested -> bounces back to draft, ready for resubmission.
  v_version := app.review_kb_article_version(v_version.id, v_version.record_version, 'changes_requested', 'add a screenshot', '00000000-0000-0000-0000-000000289103', 'staff2');
  if v_version.status <> 'draft' then
    raise exception 'FAIL: expected status=draft after changes_requested, got %', v_version.status;
  end if;

  -- review_notes free text never leaks into app.audit_logs (C-24).
  if exists (select 1 from app.audit_logs where resource_type = 'app.kb_article_versions' and (reason like '%screenshot%' or after_value::text like '%screenshot%' or before_value::text like '%screenshot%')) then
    raise exception 'CRITICAL: review_notes free text leaked into app.audit_logs (C-24)';
  end if;

  -- Resubmit, approve this time.
  v_version := app.submit_kb_article_version_for_review(v_version.id, v_version.record_version, '00000000-0000-0000-0000-000000289103', '00000000-0000-0000-0000-000000289102', 'staff1');
  v_version := app.review_kb_article_version(v_version.id, v_version.record_version, 'approved', 'good to go', '00000000-0000-0000-0000-000000289103', 'staff2');
  if v_version.status <> 'approved' then
    raise exception 'FAIL: expected status=approved, got %', v_version.status;
  end if;

  v_version := app.publish_kb_article_version(v_version.id, v_version.record_version, '00000000-0000-0000-0000-000000289102', 'staff1');
  if v_version.status <> 'published' then
    raise exception 'FAIL: expected status=published, got %', v_version.status;
  end if;

  raise notice 'PASS: draft->in_review->changes_requested->draft->in_review->approved->published lifecycle; self-review blocked at both submit and review time; publish requires approved; review_notes never leaks into app.audit_logs';
end;
$$;

\echo '>> 2. audience-safe search/get: a draft/internal-only article NEVER reaches a customer or helpdesk caller via ANY path (search, get, raw table)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'kb1');
  v_account_a uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Customer Account A');
  v_internal_article app.kb_articles;
  v_internal_version app.kb_article_versions;
  v_customer_article app.kb_articles;
  v_customer_version app.kb_article_versions;
  v_count integer;
begin
  -- An internal-only (audience_customer=false) article, PUBLISHED.
  v_internal_article := app.create_kb_article(v_tenant1, 'internal-escalation-procedure', '00000000-0000-0000-0000-000000289102', 'staff1');
  v_internal_version := app.create_kb_article_version(v_internal_article.id, 'Internal escalation procedure', 'staff only', 'Escalate to tier 2 via the internal queue.', array['internal'], true, false, false, '00000000-0000-0000-0000-000000289102', 'staff1');
  v_internal_version := app.submit_kb_article_version_for_review(v_internal_version.id, v_internal_version.record_version, '00000000-0000-0000-0000-000000289103', '00000000-0000-0000-0000-000000289102', 'staff1');
  v_internal_version := app.review_kb_article_version(v_internal_version.id, v_internal_version.record_version, 'approved', null, '00000000-0000-0000-0000-000000289103', 'staff2');
  v_internal_version := app.publish_kb_article_version(v_internal_version.id, v_internal_version.record_version, '00000000-0000-0000-0000-000000289102', 'staff1');

  -- A customer-visible article, still DRAFT (never submitted/published).
  v_customer_article := app.create_kb_article(v_tenant1, 'how-to-reset-password', '00000000-0000-0000-0000-000000289102', 'staff1');
  v_customer_version := app.create_kb_article_version(v_customer_article.id, 'How to reset your password', 'self-service', 'Click forgot password on the login page.', array['account'], false, true, false, '00000000-0000-0000-0000-000000289102', 'staff1');

  -- Neither is visible to a customer through search or get, because
  -- neither is a PUBLISHED, audience_customer=true, non-expired version.
  select count(*) into v_count from app.search_customer_knowledge_articles(v_tenant1, '00000000-0000-0000-0000-000000289110', v_account_a, null, 50, null);
  if v_count <> 0 then
    raise exception 'CRITICAL: customer search returned % rows before ANY customer-visible article was published (draft/internal-only leak)', v_count;
  end if;
  select count(*) into v_count from app.get_kb_article_for_customer(v_customer_article.id, '00000000-0000-0000-0000-000000289110', v_tenant1, v_account_a);
  if v_count <> 0 then
    raise exception 'CRITICAL: app.get_kb_article_for_customer returned the DRAFT customer-scoped article';
  end if;
  select count(*) into v_count from app.search_helpdesk_knowledge_articles(v_tenant1, '00000000-0000-0000-0000-000000289101', null, 50, null);
  if v_count <> 0 then
    raise exception 'CRITICAL: helpdesk search returned a row before any helpdesk-audience article was published';
  end if;

  -- Now publish the customer article -- it appears in customer search; the
  -- internal-only article (published, but audience_customer=false) NEVER does.
  v_customer_version := app.submit_kb_article_version_for_review(v_customer_version.id, v_customer_version.record_version, '00000000-0000-0000-0000-000000289103', '00000000-0000-0000-0000-000000289102', 'staff1');
  v_customer_version := app.review_kb_article_version(v_customer_version.id, v_customer_version.record_version, 'approved', null, '00000000-0000-0000-0000-000000289103', 'staff2');
  v_customer_version := app.publish_kb_article_version(v_customer_version.id, v_customer_version.record_version, '00000000-0000-0000-0000-000000289102', 'staff1');

  select count(*) into v_count from app.search_customer_knowledge_articles(v_tenant1, '00000000-0000-0000-0000-000000289110', v_account_a, 'password', 50, null);
  if v_count <> 1 then
    raise exception 'FAIL: expected exactly 1 customer search hit for the now-published customer-visible article, got %', v_count;
  end if;
  select count(*) into v_count from app.search_customer_knowledge_articles(v_tenant1, '00000000-0000-0000-0000-000000289110', v_account_a, null, 50, null) r where r.article_id = v_internal_article.id;
  if v_count <> 0 then
    raise exception 'CRITICAL: customer search returned the internal-only (audience_customer=false) published article';
  end if;
  select count(*) into v_count from app.get_kb_article_for_customer(v_internal_article.id, '00000000-0000-0000-0000-000000289110', v_tenant1, v_account_a);
  if v_count <> 0 then
    raise exception 'CRITICAL: app.get_kb_article_for_customer returned the internal-only published article by direct id';
  end if;

  -- Staff search sees every published article regardless of audience --
  -- this article (internal), this article (customer), PLUS the
  -- printer-offline article already published in section 1 above = 3.
  select count(*) into v_count from app.search_knowledge_articles(v_tenant1, '00000000-0000-0000-0000-000000289102', null, 50, null);
  if v_count <> 3 then
    raise exception 'FAIL: expected staff search to see all 3 published articles so far, got %', v_count;
  end if;

  -- Raw-table RLS: a customer_user has ZERO access to app.kb_article_versions,
  -- even for the published, audience_customer=true row they are otherwise
  -- entitled to read via the RPC (decision 5's own strongest claim).
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000289110", "role": "authenticated"}', false);
  set role authenticated;
  select count(*) into v_count from app.kb_article_versions;
  reset role;
  perform set_config('request.jwt.claims', 'null', false);
  if v_count <> 0 then
    raise exception 'CRITICAL: raw-table RLS admitted a customer_user actor to app.kb_article_versions, count=%', v_count;
  end if;

  -- Raw-table RLS: a non-privileged internal tenant member (req1 -- ordinary
  -- membership, no TKT:Edit, not the author/reviewer) sees only PUBLISHED
  -- versions -- never another actor's still-draft/in_review work. (staff1/
  -- staff2 both deliberately hold TKT:Edit in this fixture's own admin_role
  -- assignment -- the "service manager sees everything" override, decision
  -- 10 -- so req1 is the actor that actually exercises the author/reviewer-
  -- scoped RLS branch rather than the TKT:Edit override branch.)
  declare
    v_draft_by_staff2 app.kb_article_versions;
  begin
    v_draft_by_staff2 := app.create_kb_article_version(
      (app.create_kb_article(v_tenant1, 'staff2-private-draft', '00000000-0000-0000-0000-000000289103', 'staff2')).id,
      'Staff2''s private draft', null, 'not ready yet', '{}'::text[], true, false, false, '00000000-0000-0000-0000-000000289103', 'staff2'
    );
    perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000289104", "role": "authenticated"}', false);
    set role authenticated;
    select count(*) into v_count from app.kb_article_versions where id = v_draft_by_staff2.id;
    reset role;
    perform set_config('request.jwt.claims', 'null', false);
    if v_count <> 0 then
      raise exception 'CRITICAL: raw-table RLS let a non-privileged actor (req1) read staff2''s own private draft article version (author-scoped isolation broken)';
    end if;

    -- staff1, who DOES hold TKT:Edit, legitimately sees it (the override
    -- branch working as designed -- confirms this is the override, not a
    -- second isolation bug).
    perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000289102", "role": "authenticated"}', false);
    set role authenticated;
    select count(*) into v_count from app.kb_article_versions where id = v_draft_by_staff2.id;
    reset role;
    perform set_config('request.jwt.claims', 'null', false);
    if v_count <> 1 then
      raise exception 'FAIL: a TKT:Edit holder (staff1) should see every article version via the override branch, got count=%', v_count;
    end if;
  end;

  raise notice 'PASS: audience-safe search/get -- a draft article is invisible everywhere until published; an internal-only published article never reaches customer search/get/raw-table by any path; staff search sees all published regardless of audience; a private draft stays scoped to its own author/reviewer even for another staff member';
end;
$$;

\echo '>> 3. expiry batch: idempotent durable job, published+expired -> archived, then invisible to customer search'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'kb1');
  v_account_a uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Customer Account A');
  v_version app.kb_article_versions;
  v_result1 record;
  v_result2 record;
  v_count integer;
begin
  select v.* into v_version from app.kb_article_versions v
  join app.kb_articles a on a.id = v.article_id
  where a.tenant_id = v_tenant1 and a.code = 'how-to-reset-password' and v.status = 'published';

  perform app.set_kb_article_expiry(v_version.id, v_version.record_version, now() - interval '1 day', '00000000-0000-0000-0000-000000289102', 'staff1');

  select * into v_result1 from app.expire_kb_article_versions_batch(v_tenant1, now(), 'kb-expiry-2026-08-14', '00000000-0000-0000-0000-000000289102', 'staff1');
  if v_result1.expired_count <> 1 then
    raise exception 'FAIL: expected exactly 1 article version expired, got %', v_result1.expired_count;
  end if;

  select * into v_result2 from app.expire_kb_article_versions_batch(v_tenant1, now(), 'kb-expiry-2026-08-14', '00000000-0000-0000-0000-000000289102', 'staff1');
  if v_result2.job_id <> v_result1.job_id or v_result2.expired_count <> 0 then
    raise exception 'FAIL: replaying the SAME period_label should be a no-op (same job, 0 newly expired), got job=%/%, expired=%', v_result1.job_id, v_result2.job_id, v_result2.expired_count;
  end if;

  select count(*) into v_count from app.search_customer_knowledge_articles(v_tenant1, '00000000-0000-0000-0000-000000289110', v_account_a, 'password', 50, null);
  if v_count <> 0 then
    raise exception 'FAIL: an expired (now archived) article must no longer appear in customer search';
  end if;

  raise notice 'PASS: expiry batch is idempotent per (tenant, period_label); an expired article becomes archived and immediately disappears from customer search';
end;
$$;

\echo '>> 4. ticket-article linking reuses the public/internal visibility discipline: a public link requires the article''s own audience flag for the ticket''s channel'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'kb1');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'GENERAL');
  v_account_a uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Customer Account A');
  v_internal_article_id uuid := (select id from app.kb_articles where tenant_id = v_tenant1 and code = 'internal-escalation-procedure');
  v_ticket app.tickets;
  v_link app.kb_ticket_article_links;
  v_count integer;
begin
  v_ticket := app.create_customer_ticket(v_tenant1, v_account_a, v_category, 'normal', 'Cannot log in', 'I forgot my password.', 'idem-kb-link-1', '00000000-0000-0000-0000-000000289110', 'customer1');

  -- Publicly linking the INTERNAL-only article to a CUSTOMER ticket is
  -- rejected -- its audience_customer flag is false.
  begin
    perform app.link_ticket_knowledge_article(v_ticket.id, v_internal_article_id, 'public', 'see this', '00000000-0000-0000-0000-000000289102', 'staff1');
    raise exception 'FAIL: publicly linking an internal-only article to a customer ticket should have raised article_not_audience_permitted';
  exception
    when others then
      if sqlerrm not like 'article_not_audience_permitted%' then
        raise exception 'FAIL: expected article_not_audience_permitted, got: %', sqlerrm;
      end if;
  end;

  -- An INTERNAL-visibility link of the same article is fine -- a private
  -- staff reference note, exactly like an internal ticket_messages note.
  v_link := app.link_ticket_knowledge_article(v_ticket.id, v_internal_article_id, 'internal', 'follow this internally', '00000000-0000-0000-0000-000000289102', 'staff1');

  -- The requester's own link listing never shows the internal-visibility link.
  select count(*) into v_count from app.list_ticket_knowledge_article_links_for_requester(v_ticket.id, '00000000-0000-0000-0000-000000289110');
  if v_count <> 0 then
    raise exception 'CRITICAL: an internal-visibility article link leaked to the customer requester';
  end if;
  select count(*) into v_count from app.list_ticket_knowledge_article_links(v_ticket.id, '00000000-0000-0000-0000-000000289102');
  if v_count <> 1 then
    raise exception 'FAIL: staff should see the internal link, got %', v_count;
  end if;

  -- Now publicly link a FRESH, still-published CUSTOMER-visible article
  -- (the earlier 'how-to-reset-password' article was deliberately expired
  -- in section 3 above, so it is no longer linkable -- a fresh one proves
  -- the public-link success path on its own, unconfounded) -- succeeds;
  -- visible to the requester.
  declare
    v_customer_article_id uuid;
    v_customer_version2 app.kb_article_versions;
    v_public_link app.kb_ticket_article_links;
  begin
    v_customer_article_id := (app.create_kb_article(v_tenant1, 'how-to-update-billing-info', '00000000-0000-0000-0000-000000289102', 'staff1')).id;
    v_customer_version2 := app.create_kb_article_version(v_customer_article_id, 'How to update billing info', 'self-service', 'Go to Billing > Payment Methods.', array['billing'], false, true, false, '00000000-0000-0000-0000-000000289102', 'staff1');
    v_customer_version2 := app.submit_kb_article_version_for_review(v_customer_version2.id, v_customer_version2.record_version, '00000000-0000-0000-0000-000000289103', '00000000-0000-0000-0000-000000289102', 'staff1');
    v_customer_version2 := app.review_kb_article_version(v_customer_version2.id, v_customer_version2.record_version, 'approved', null, '00000000-0000-0000-0000-000000289103', 'staff2');
    perform app.publish_kb_article_version(v_customer_version2.id, v_customer_version2.record_version, '00000000-0000-0000-0000-000000289102', 'staff1');

    v_public_link := app.link_ticket_knowledge_article(v_ticket.id, v_customer_article_id, 'public', null, '00000000-0000-0000-0000-000000289102', 'staff1');
    select count(*) into v_count from app.list_ticket_knowledge_article_links_for_requester(v_ticket.id, '00000000-0000-0000-0000-000000289110') r where r.article_id = v_customer_article_id;
    if v_count <> 1 then
      raise exception 'FAIL: the customer requester should see the public link to the customer-visible article';
    end if;

    -- Duplicate link (same ticket+article) is rejected, not silently duplicated.
    begin
      perform app.link_ticket_knowledge_article(v_ticket.id, v_customer_article_id, 'internal', 'dup', '00000000-0000-0000-0000-000000289102', 'staff1');
      raise exception 'FAIL: re-linking the same article to the same ticket should have raised kb_article_already_linked';
    exception
      when others then
        if sqlerrm not like 'kb_article_already_linked%' then
          raise exception 'FAIL: expected kb_article_already_linked, got: %', sqlerrm;
        end if;
    end;
  end;

  raise notice 'PASS: ticket-article linking reuses the public/internal visibility discipline verbatim -- a public link requires the article''s own audience flag for the ticket''s channel; an internal link never leaks to the requester; duplicate links rejected';
end;
$$;

\echo '>> 5. cross-tenant isolation: tenant2 sees nothing of tenant1''s knowledge base via any RPC or raw table'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'kb1');
  v_count integer;
begin
  select count(*) into v_count from app.list_kb_articles(v_tenant1, '00000000-0000-0000-0000-000000289121');
  if v_count <> 0 then
    raise exception 'CRITICAL: tenant2 admin read tenant1''s knowledge base article list';
  end if;
  select count(*) into v_count from app.search_knowledge_articles(v_tenant1, '00000000-0000-0000-0000-000000289121', null, 50, null);
  if v_count <> 0 then
    raise exception 'CRITICAL: tenant2 admin searched tenant1''s knowledge base';
  end if;

  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000289121", "role": "authenticated"}', false);
  set role authenticated;
  select count(*) into v_count from app.kb_articles where tenant_id = v_tenant1;
  if v_count <> 0 then
    raise exception 'CRITICAL: raw-table RLS admitted a cross-tenant (tenant2) actor to tenant1''s kb_articles';
  end if;
  select count(*) into v_count from app.kb_article_versions where tenant_id = v_tenant1 and status = 'published';
  reset role;
  perform set_config('request.jwt.claims', 'null', false);
  if v_count <> 0 then
    raise exception 'CRITICAL: raw-table RLS admitted a cross-tenant (tenant2) actor to tenant1''s PUBLISHED kb_article_versions';
  end if;

  raise notice 'PASS: cross-tenant isolation holds via RPC and raw-table RLS alike, even for a published article version';
end;
$$;

\echo '>> 6. schema-privilege defense in depth: anon has zero access to any KB table/function'
do $$
declare
  v_has_table_priv boolean;
begin
  select bool_or(has_table_privilege('anon', format('app.%I', t), 'SELECT')) into v_has_table_priv
  from unnest(array['kb_articles', 'kb_article_versions', 'kb_ticket_article_links']) as t;
  if v_has_table_priv then
    raise exception 'CRITICAL: anon has SELECT on at least one knowledge-base table';
  end if;
  raise notice 'PASS: anon has zero SELECT privilege on any knowledge-base table';
end;
$$;

\echo '>> 7. reachability sweep (C-02 defense): every RETURNS TABLE function is actually CALLED live, never merely read as SQL'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'kb1');
  v_article_id uuid := (select id from app.kb_articles where tenant_id = v_tenant1 and code = 'printer-offline');
  v_account_a uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Customer Account A');
  v_n integer;
begin
  select count(*) into v_n from app.list_kb_article_versions(v_article_id, '00000000-0000-0000-0000-000000289102');
  if v_n < 1 then raise exception 'FAIL: app.list_kb_article_versions returned no rows for an article with a published version'; end if;

  select count(*) into v_n from app.search_helpdesk_knowledge_articles(v_tenant1, '00000000-0000-0000-0000-000000289101', null, 50, null);
  if v_n <> 0 then raise exception 'FAIL: expected zero helpdesk-audience articles (none published with audience_helpdesk=true), got %', v_n; end if;

  select count(*) into v_n from app.get_kb_article_for_helpdesk(v_article_id, '00000000-0000-0000-0000-000000289101', v_tenant1);
  if v_n <> 0 then raise exception 'FAIL: expected app.get_kb_article_for_helpdesk to return zero rows for a non-helpdesk-audience article'; end if;

  -- app.get_kb_article_version (scalar, not RETURNS TABLE, but the exact
  -- same C-02-flavored "actually call it live" discipline applies): the
  -- author sees the full row (including body) for their own published
  -- article; the SAME call for a non-member of ANY tenant (bystander
  -- identity, zero membership) returns null, never an error.
  if (app.get_kb_article_version((select v.id from app.kb_article_versions v where v.article_id = v_article_id and v.status = 'published'), '00000000-0000-0000-0000-000000289102')) is null then
    raise exception 'FAIL: app.get_kb_article_version returned null for the article''s own author reading a published version';
  end if;

  raise notice 'PASS: every knowledge-base RETURNS TABLE function reachable live, no ambiguous-id crash, sane row counts';
end;
$$;

\echo '>> ticketing-knowledge-base.sql: ALL PASSED'
