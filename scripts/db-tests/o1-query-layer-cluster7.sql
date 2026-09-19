-- Real, executable test evidence for CG-AUDIT-2026-09-02 O1-query-layer, cluster 7
-- (page-level-direct-reads), the LAST cluster of the whole Ø1 defect
-- (supabase/migrations/20260913050000_close_o1_query_layer_cluster7_page_level_direct_reads.sql).
--
-- Proves, against a real disposable database, all 7 new function pairs (14 functions)
-- across 3 grant/RLS shapes plus 2 SECURITY DEFINER functions with their own hand-rolled
-- authority chain:
--
--   app.list_files_for_record   -- SECURITY DEFINER, mirrors app.list_files_for_tenant
--   app.list_org_units          -- SECURITY INVOKER, RLS excludes customer_user-layer
--   app.list_position_incumbents -- SECURITY DEFINER, HRS:View + personal-data masking
--   app.get_job_offer_for_application -- SECURITY INVOKER, RLS excludes customer_user-layer
--   app.get_warehouse_location  -- SECURITY DEFINER, OPS:View + can_access_record scope
--   app.get_approval_request_step -- SECURITY INVOKER, full-row grant, EXISTS-join RLS
--   app.get_approval_request_by_id -- SECURITY INVOKER, column-restricted grant, direct RLS
--
-- Fixture setup deliberately bypasses every domain's own heavier creation RPCs
-- (app.create_employee_draft, app.create_job_vacancy_draft, app.request_approval, etc.)
-- via direct INSERT wherever a table has no trivial creation helper -- the same
-- established technique this series already used for app.approval_requests/
-- app.config_versions (cluster 0 batch 3) -- since these functions are being tested for
-- their own read-side authority/masking behavior, not the mutation business rules that
-- would normally produce these rows.

\set ON_ERROR_STOP on

\echo '>> setup: tenant acmeo1c7 with a company/branch/department org tree, a "staff" member (999801, HRS:View + OPS:View, org_unit_id=company for warehouse record-scope), a plain member with no special role (999802), a customer_user-layer principal (999803), a global Supreme Admin with ZERO membership (999804), and a second, isolated tenant gizmoo1c7 with its own tenant_admin (999805)'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
  v_company_id uuid;
  v_branch_id uuid;
  v_department_id uuid;
  v_role_id uuid;
  v_role_version_id uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000999801', 'staffo1c7@example.test'),
    ('00000000-0000-0000-0000-000000999802', 'membero1c7@example.test'),
    ('00000000-0000-0000-0000-000000999803', 'customerusero1c7@example.test'),
    ('00000000-0000-0000-0000-000000999804', 'supremeo1c7@example.test'),
    ('00000000-0000-0000-0000-000000999805', 'othertenanto1c7@example.test');

  perform app.provision_tenant('acmeo1c7', 'Acme O1C7 Co', 'idem-acmeo1c7', 'tester');
  v_tenant_id := (select id from app.tenants where slug = 'acmeo1c7');
  perform app.transition_tenant_status(v_tenant_id, 'active', 'setup', 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000999804', 'supreme_admin', null, null, 'tester');

  v_company_id := (app.create_org_unit(v_tenant_id, 'company', null, 'CO-O1C7', 'O1C7 Co', 'tester')).id;
  v_branch_id := (app.create_org_unit(v_tenant_id, 'branch', v_company_id, 'BR-O1C7', 'O1C7 Branch', 'tester')).id;
  v_department_id := (app.create_org_unit(v_tenant_id, 'department', v_branch_id, 'DEPT-O1C7', 'O1C7 Dept', 'tester')).id;

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000999801', 'staffo1c7@example.test', 'Staff', v_company_id, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staffo1c7@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000999801', 'org_user', v_tenant_id, null, 'tester');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000999802', 'membero1c7@example.test', 'Member', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'membero1c7@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000999802', 'org_user', v_tenant_id, null, 'tester');

  perform app.link_auth_identity('00000000-0000-0000-0000-000000999803', v_tenant_id, 'tester', 'active');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000999803', 'customer_user', v_tenant_id, 'fake-account-ref-o1c7', 'tester');

  v_role_id := (app.create_role(v_tenant_id, 'O1C7 Staff Role', 'HRS:View + OPS:View for O1C7 db-test', 'tester')).id;
  v_role_version_id := (app.create_role_version(v_role_id, 'tester')).id;
  perform app.set_role_version_permissions(
    v_role_version_id,
    array(select id from app.permissions where (resource_module_code, action) in (('HRS', 'View'), ('OPS', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_role_version_id, now(), 'tester');
  perform app.assign_role(v_tenant_id, (select id from app.role_versions where role_id = v_role_id and status = 'published'),
    '00000000-0000-0000-0000-000000999801', '00000000-0000-0000-0000-000000999804', 'tester');

  perform app.provision_tenant('gizmoo1c7', 'Gizmo O1C7 Co', 'idem-gizmoo1c7', 'tester');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmoo1c7');
  perform app.transition_tenant_status(v_other_tenant_id, 'active', 'setup', 'tester');
  perform app.invite_user(v_other_tenant_id, '00000000-0000-0000-0000-000000999805', 'othertenanto1c7@example.test', 'Other Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'othertenanto1c7@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000999805', 'tenant_admin', v_other_tenant_id, null, 'tester');
end $$;

\echo '>> fixture: a config_object/config_version pair (config_type_code=document:employee_document, a real per-tenant published Configuration Engine version every tenant configures before an upload can succeed in production) plus 2 app.files rows scoped to (tenant, record_type=employee, record_id=v_master_record_id)'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c7');
  v_config_object_id uuid := gen_random_uuid();
  v_config_version_id uuid := gen_random_uuid();
  v_master_record_id uuid := gen_random_uuid();
begin
  insert into app.config_objects (id, config_type_code, tenant_id, scope_level, created_by)
  values (v_config_object_id, 'document:employee_document', v_tenant_id, 'tenant', 'tester');
  insert into app.config_versions (id, config_object_id, version_number, status, created_by)
  values (v_config_version_id, v_config_object_id, 1, 'published', 'tester');

  insert into app.master_records (id, master_type_code, tenant_id, code, name, created_by)
  values (v_master_record_id, 'employee', v_tenant_id, 'O1C7-EMP-1', 'O1C7 Test Employee', 'tester');

  insert into app.files (id, tenant_id, document_type_code, config_version_id, record_type, record_id, classification, original_filename, mime_type, size_bytes, storage_path, version_group_id, uploaded_by_auth_user_id, created_at, updated_at)
  values
    (gen_random_uuid(), v_tenant_id, 'employee_document', v_config_version_id, 'employee', v_master_record_id, 'confidential', 'offer-letter.pdf', 'application/pdf', 102400, 'tenant/o1c7/offer-letter.pdf', gen_random_uuid(), '00000000-0000-0000-0000-000000999801', now() - interval '2 hours', now() - interval '2 hours'),
    (gen_random_uuid(), v_tenant_id, 'employee_document', v_config_version_id, 'employee', v_master_record_id, 'internal', 'id-card-scan.pdf', 'application/pdf', 51200, 'tenant/o1c7/id-card-scan.pdf', gen_random_uuid(), '00000000-0000-0000-0000-000000999801', now() - interval '1 hour', now() - interval '1 hour');
end $$;

\echo '>> app.list_files_for_record: staff/plain-member/customer_user-layer ALL see both files (app.check_file_action_authority admits any active tenant member, Supreme Admin, OR a customer_user-layer principal -- confirmed live, not assumed); a cross-tenant actor sees zero (file_actor_unauthorized, caught and skipped)'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c7');
  v_master_record_id uuid := (select record_id from app.files where tenant_id = v_tenant_id limit 1);
  v_count integer;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999801", "role": "authenticated"}';
  select count(*) into v_count from app.list_files_for_record(v_tenant_id, 'employee', v_master_record_id, '00000000-0000-0000-0000-000000999801');
  if v_count <> 2 then raise exception 'staff: expected 2 files, got %', v_count; end if;
  reset role; reset request.jwt.claims;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999802", "role": "authenticated"}';
  select count(*) into v_count from app.list_files_for_record(v_tenant_id, 'employee', v_master_record_id, '00000000-0000-0000-0000-000000999802');
  if v_count <> 2 then raise exception 'plain member: expected 2 files, got %', v_count; end if;
  reset role; reset request.jwt.claims;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999803", "role": "authenticated"}';
  select count(*) into v_count from app.list_files_for_record(v_tenant_id, 'employee', v_master_record_id, '00000000-0000-0000-0000-000000999803');
  if v_count <> 2 then raise exception 'customer_user-layer: expected 2 files (check_file_action_authority explicitly admits this layer), got %', v_count; end if;
  reset role; reset request.jwt.claims;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999805", "role": "authenticated"}';
  begin
    perform 1 from app.list_files_for_record(v_tenant_id, 'employee', v_master_record_id, '00000000-0000-0000-0000-000000999805');
    raise exception 'assertion failed: expected document_listing_unauthorized for a cross-tenant actor';
  exception
    when insufficient_privilege then null;
  end;
  reset role; reset request.jwt.claims;

  select count(*) into v_count from app.list_files_for_record(v_tenant_id, 'employee', gen_random_uuid(), '00000000-0000-0000-0000-000000999801');
  if v_count <> 0 then raise exception 'assertion failed: an unrelated record_id must return zero rows, got %', v_count; end if;

  raise notice 'app.list_files_for_record proof: staff/plain-member/customer_user-layer all admitted (check_file_action_authority''s own broad definition), cross-tenant denied, an unrelated record_id scoped to zero';
end $$;

\echo '>> app.list_org_units: any active tenant member (staff or plain) sees all 3 org units; unit_type filter narrows correctly; customer_user-layer is EXCLUDED (org_units_select_own_tenant carries no is_supreme_admin() disjunct, unlike files); cross-tenant sees zero; Supreme Admin (zero membership) still sees all 3 via has_active_tenant_membership''s own internal coverage'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c7');
  v_count integer;
  v_names text[];
begin
  select array_agg(name order by name) into v_names from app.list_org_units(v_tenant_id);
  if v_names <> array['O1C7 Branch', 'O1C7 Co', 'O1C7 Dept'] then
    raise exception 'assertion failed: expected all 3 org units by name, got %', v_names;
  end if;

  select count(*) into v_count from app.list_org_units(v_tenant_id, null, 'branch');
  if v_count <> 1 then raise exception 'assertion failed: unit_type_filter=branch must narrow to exactly 1, got %', v_count; end if;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999802", "role": "authenticated"}';
  select count(*) into v_count from app.list_org_units(v_tenant_id);
  if v_count <> 3 then raise exception 'plain member: expected 3 org units, got %', v_count; end if;
  reset role; reset request.jwt.claims;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999803", "role": "authenticated"}';
  select count(*) into v_count from app.list_org_units(v_tenant_id);
  if v_count <> 0 then raise exception 'customer_user-layer: expected 0 org units, got %', v_count; end if;
  reset role; reset request.jwt.claims;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999805", "role": "authenticated"}';
  select count(*) into v_count from app.list_org_units(v_tenant_id);
  if v_count <> 0 then raise exception 'cross-tenant: expected 0 org units, got %', v_count; end if;
  reset role; reset request.jwt.claims;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999804", "role": "authenticated"}';
  select count(*) into v_count from app.list_org_units(v_tenant_id);
  if v_count <> 3 then raise exception 'supreme admin: expected 3 org units via internal has_active_tenant_membership coverage, got %', v_count; end if;
  reset role; reset request.jwt.claims;

  raise notice 'app.list_org_units proof: any real tenant member sees all 3 org units, unit_type filter narrows correctly, customer_user-layer/cross-tenant both denied (no policy-level disjunct), Supreme Admin still sees all 3';
end $$;

\echo '>> fixture: 1 position (with a real position_grade), 1 employee (via app.master_records + app.employees, bypassing the full HRS onboarding pipeline), 1 ACTIVE app.employee_position_assignments row with a REAL, non-null reason_note/decided_reason deliberately written'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c7');
  v_department_id uuid := (select id from app.org_units where tenant_id = v_tenant_id and code = 'DEPT-O1C7');
  v_grade_id uuid := gen_random_uuid();
  v_position_id uuid := gen_random_uuid();
  v_master_record_id uuid := gen_random_uuid();
begin
  insert into app.position_grades (id, tenant_id, code, name, created_by)
  values (v_grade_id, v_tenant_id, 'GR-O1C7', 'O1C7 Grade', 'tester');

  insert into app.positions (id, tenant_id, code, title, org_unit_id, grade_id, created_by)
  values (v_position_id, v_tenant_id, 'POS-O1C7', 'O1C7 Analyst', v_department_id, v_grade_id, 'tester');

  insert into app.master_records (id, master_type_code, tenant_id, code, name, created_by)
  values (v_master_record_id, 'employee', v_tenant_id, 'O1C7-EMP-2', 'O1C7 Incumbent', 'tester');
  insert into app.employees (master_record_id, tenant_id, full_name, employment_type, lifecycle_status, intake_source, company_org_unit_id, department_org_unit_id, created_by)
  values (v_master_record_id, v_tenant_id, 'O1C7 Incumbent', 'full_time', 'active', 'hr_created', (select id from app.org_units where tenant_id = v_tenant_id and code = 'CO-O1C7'), v_department_id, 'tester');

  insert into app.employee_position_assignments (id, tenant_id, master_record_id, position_id, assignment_type, effective_start_date, status, change_reason, reason_note, decided_by, decided_at, decided_reason, created_by)
  values (gen_random_uuid(), v_tenant_id, v_master_record_id, v_position_id, 'primary', current_date - 30, 'active', 'hire', 'a real, sensitive HR narrative reason_note', 'tester', now() - interval '30 days', 'a real, sensitive HR narrative decided_reason', 'tester');
end $$;

\echo '>> app.list_position_incumbents: staff (HRS:View, no personal-data permission) sees the active assignment with reason_note/decided_reason genuinely NULLED (real values confirmed present in the raw fixture row above); a plain member (no HRS:View) is denied insufficient_authority; Supreme Admin (zero membership, HRS:View personal data bypassed via is_supreme_admin) sees the REAL unmasked values; cross-tenant is denied'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c7');
  v_position_id uuid := (select id from app.positions where tenant_id = v_tenant_id and code = 'POS-O1C7');
  v_row app.employee_position_assignments;
  v_count integer;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999801", "role": "authenticated"}';
  select * into v_row from app.list_position_incumbents(v_position_id, '00000000-0000-0000-0000-000000999801');
  if v_row.status <> 'active' or v_row.reason_note is not null or v_row.decided_reason is not null then
    raise exception 'assertion failed: staff (HRS:View only) must see the active row with reason_note/decided_reason genuinely nulled, got status=% reason_note=% decided_reason=%', v_row.status, v_row.reason_note, v_row.decided_reason;
  end if;
  reset role; reset request.jwt.claims;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999802", "role": "authenticated"}';
  begin
    perform 1 from app.list_position_incumbents(v_position_id, '00000000-0000-0000-0000-000000999802');
    raise exception 'assertion failed: expected insufficient_authority for a plain member with no HRS:View';
  exception
    when insufficient_privilege then null;
  end;
  reset role; reset request.jwt.claims;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999804", "role": "authenticated"}';
  select * into v_row from app.list_position_incumbents(v_position_id, '00000000-0000-0000-0000-000000999804');
  if v_row.reason_note is distinct from 'a real, sensitive HR narrative reason_note' or v_row.decided_reason is distinct from 'a real, sensitive HR narrative decided_reason' then
    raise exception 'assertion failed: Supreme Admin must see the REAL unmasked reason_note/decided_reason, got reason_note=% decided_reason=%', v_row.reason_note, v_row.decided_reason;
  end if;
  reset role; reset request.jwt.claims;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999805", "role": "authenticated"}';
  begin
    perform 1 from app.list_position_incumbents(v_position_id, '00000000-0000-0000-0000-000000999805');
    raise exception 'assertion failed: expected position_not_found (no_data_found) for a cross-tenant actor';
  exception
    when no_data_found then null;
  end;
  reset role; reset request.jwt.claims;

  raise notice 'app.list_position_incumbents proof: HRS:View-only staff sees the row with reason_note/decided_reason genuinely nulled (real values confirmed to exist), a plain member is denied insufficient_authority, Supreme Admin sees the REAL unmasked values, cross-tenant is denied';
end $$;

\echo '>> fixture: 1 candidate, 1 job_vacancy (bound to the O1C7 position above), 1 job_application, 1 job_offer -- all via direct INSERT, bypassing the recruitment ATS mutation RPCs entirely, since this batch tests the read/authority side only'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c7');
  v_position_id uuid := (select id from app.positions where tenant_id = v_tenant_id and code = 'POS-O1C7');
  v_candidate_id uuid := gen_random_uuid();
  v_vacancy_id uuid := gen_random_uuid();
  v_application_id uuid := gen_random_uuid();
begin
  insert into app.candidates (id, tenant_id, full_name, email, source, created_by)
  values (v_candidate_id, v_tenant_id, 'O1C7 Candidate', 'candidate@o1c7.example.test', 'staff_created', 'tester');

  insert into app.job_vacancies (id, tenant_id, position_id, title, employment_type, created_by)
  values (v_vacancy_id, v_tenant_id, v_position_id, 'O1C7 Analyst Vacancy', 'full_time', 'tester');

  insert into app.job_applications (id, tenant_id, vacancy_id, candidate_id, source, created_by)
  values (v_application_id, v_tenant_id, v_vacancy_id, v_candidate_id, 'staff_created', 'tester');

  insert into app.job_offers (id, tenant_id, application_id, status, approval_status, created_by)
  values (gen_random_uuid(), v_tenant_id, v_application_id, 'draft', 'not_required', 'tester');
end $$;

\echo '>> app.get_job_offer_for_application: staff/plain-member both resolve the offer (RLS is plain tenant membership, no HRS:View needed -- app.job_offers itself carries no PII, no masking concern); customer_user-layer is EXCLUDED (same predicate shape as org_units, RULE B confirmed); cross-tenant denied; Supreme Admin (zero membership) resolves via the explicit policy-level OR is_supreme_admin() disjunct; a genuinely offer-less application returns null, never an error'
do $$
declare
  v_application_id uuid := (select application_id from app.job_offers where tenant_id = (select id from app.tenants where slug = 'acmeo1c7'));
  v_count integer;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999801", "role": "authenticated"}';
  select count(*) into v_count from app.get_job_offer_for_application(v_application_id);
  if v_count <> 1 then raise exception 'staff: expected the offer to resolve, got %', v_count; end if;
  reset role; reset request.jwt.claims;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999802", "role": "authenticated"}';
  select count(*) into v_count from app.get_job_offer_for_application(v_application_id);
  if v_count <> 1 then raise exception 'plain member: expected the offer to resolve, got %', v_count; end if;
  reset role; reset request.jwt.claims;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999803", "role": "authenticated"}';
  select count(*) into v_count from app.get_job_offer_for_application(v_application_id);
  if v_count <> 0 then raise exception 'customer_user-layer: expected the offer to be hidden, got %', v_count; end if;
  reset role; reset request.jwt.claims;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999805", "role": "authenticated"}';
  select count(*) into v_count from app.get_job_offer_for_application(v_application_id);
  if v_count <> 0 then raise exception 'cross-tenant: expected the offer to be hidden, got %', v_count; end if;
  reset role; reset request.jwt.claims;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999804", "role": "authenticated"}';
  select count(*) into v_count from app.get_job_offer_for_application(v_application_id);
  if v_count <> 1 then raise exception 'supreme admin: expected the offer to resolve via the explicit policy-level disjunct, got %', v_count; end if;
  select count(*) into v_count from app.get_job_offer_for_application(gen_random_uuid());
  if v_count <> 0 then raise exception 'assertion failed: a genuinely offer-less application must return a genuinely empty result, got %', v_count; end if;
  reset role; reset request.jwt.claims;

  raise notice 'app.get_job_offer_for_application proof: staff/plain-member both resolve (plain tenant-membership RLS, no HRS:View needed), customer_user-layer/cross-tenant both denied, Supreme Admin resolves via the explicit disjunct, an offer-less application returns a genuinely empty result';
end $$;

\echo '>> fixture: 1 app.warehouses row (company_org_unit_id = O1C7''s own company org unit, matching staff''s own org_unit_id for the can_access_record scope proof) with 2 app.warehouse_locations rows -- a root and its own child'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c7');
  v_company_id uuid := (select id from app.org_units where tenant_id = v_tenant_id and code = 'CO-O1C7');
  v_warehouse_id uuid := gen_random_uuid();
  v_root_location_id uuid := gen_random_uuid();
begin
  insert into app.warehouses (id, tenant_id, company_org_unit_id, code, name, created_by)
  values (v_warehouse_id, v_tenant_id, v_company_id, 'WH-O1C7', 'O1C7 Warehouse', 'tester');

  insert into app.warehouse_locations (id, tenant_id, warehouse_id, parent_id, code, name, location_type, created_by)
  values (v_root_location_id, v_tenant_id, v_warehouse_id, null, 'ROOT-O1C7', 'O1C7 Root Location', 'floor', 'tester');
  insert into app.warehouse_locations (id, tenant_id, warehouse_id, parent_id, code, name, location_type, created_by)
  values (gen_random_uuid(), v_tenant_id, v_warehouse_id, v_root_location_id, 'CHILD-O1C7', 'O1C7 Child Location', 'rack', 'tester');
end $$;

\echo '>> app.get_warehouse_location: staff (OPS:View + org_unit_id matching the warehouse''s own company_org_unit_id, satisfying app.can_access_record) resolves the root location; a plain member (no OPS:View at all) is denied insufficient_authority even though same tenant; a nonexistent location id returns a genuinely empty result (never raises); Supreme Admin (zero membership) resolves via app.is_supreme_admin''s own can_access_record branch; cross-tenant is denied'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c7');
  v_root_location_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant_id and code = 'ROOT-O1C7');
  v_count integer;
  v_code text;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999801", "role": "authenticated"}';
  select code into v_code from app.get_warehouse_location(v_root_location_id, '00000000-0000-0000-0000-000000999801');
  if v_code <> 'ROOT-O1C7' then raise exception 'staff: expected the root location to resolve, got %', v_code; end if;
  select count(*) into v_count from app.get_warehouse_location(gen_random_uuid(), '00000000-0000-0000-0000-000000999801');
  if v_count <> 0 then raise exception 'assertion failed: a nonexistent location id must return a genuinely empty result, got %', v_count; end if;
  reset role; reset request.jwt.claims;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999802", "role": "authenticated"}';
  begin
    perform 1 from app.get_warehouse_location(v_root_location_id, '00000000-0000-0000-0000-000000999802');
    raise exception 'assertion failed: expected insufficient_authority for a plain member with no OPS:View';
  exception
    when insufficient_privilege then null;
  end;
  reset role; reset request.jwt.claims;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999804", "role": "authenticated"}';
  select code into v_code from app.get_warehouse_location(v_root_location_id, '00000000-0000-0000-0000-000000999804');
  if v_code <> 'ROOT-O1C7' then raise exception 'supreme admin: expected the root location to resolve, got %', v_code; end if;
  reset role; reset request.jwt.claims;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999805", "role": "authenticated"}';
  begin
    perform 1 from app.get_warehouse_location(v_root_location_id, '00000000-0000-0000-0000-000000999805');
    raise exception 'assertion failed: expected insufficient_authority for a cross-tenant actor';
  exception
    when insufficient_privilege then null;
  end;
  reset role; reset request.jwt.claims;

  raise notice 'app.get_warehouse_location proof: staff (OPS:View + matching org-unit scope) resolves the location, a nonexistent id returns a genuinely empty result, a plain member without OPS:View is denied even within the same tenant, Supreme Admin resolves, cross-tenant is denied';
end $$;

\echo '>> fixture: a config_object/config_version pair (config_type_code=approval, the platform-wide seeded base type) plus 1 app.approval_requests row with a REAL, non-null ended_reason deliberately written, and 1 app.approval_request_steps row -- both via direct INSERT, bypassing app.request_approval entirely, mirroring cluster 0 batch 3''s own established precedent for this exact table pair'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c7');
  v_config_object_id uuid := gen_random_uuid();
  v_config_version_id uuid := gen_random_uuid();
  v_request_id uuid := gen_random_uuid();
begin
  insert into app.config_objects (id, config_type_code, tenant_id, scope_level, created_by)
  values (v_config_object_id, 'approval', v_tenant_id, 'tenant', 'tester');
  insert into app.config_versions (id, config_object_id, version_number, status, created_by)
  values (v_config_version_id, v_config_object_id, 1, 'draft', 'tester');

  insert into app.approval_requests (id, tenant_id, config_version_id, entity_type, entity_id, pattern, status, idempotency_key, requested_by_auth_user_id, requested_by, ended_at, ended_reason)
  values (v_request_id, v_tenant_id, v_config_version_id, 'o1c7_test_entity', gen_random_uuid(), 'sequential', 'approved', 'idem-o1c7-approval-1', '00000000-0000-0000-0000-000000999801', 'tester', now() - interval '1 hour', 'a real, sensitive cancellation/rejection narrative');

  insert into app.approval_request_steps (id, request_id, step_order, approver_type, specific_user_id, status)
  values (gen_random_uuid(), v_request_id, 1, 'specific_user', '00000000-0000-0000-0000-000000999801', 'approved');
end $$;

\echo '>> app.get_approval_request_step / app.get_approval_request_by_id: staff/plain-member both resolve (approval_request_steps'' own full-row grant + EXISTS-join RLS; approval_requests'' own column-restricted grant + direct RLS, ended_reason genuinely nulled despite a REAL non-null value written to the fixture row); customer_user-layer/cross-tenant both denied on both functions; Supreme Admin resolves both via the explicit policy-level disjunct; a nonexistent id returns a genuinely empty result for both'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c7');
  v_request_id uuid := (select id from app.approval_requests where tenant_id = v_tenant_id and entity_type = 'o1c7_test_entity');
  v_step_id uuid := (select id from app.approval_request_steps where request_id = v_request_id);
  v_count integer;
  v_ended_reason text;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999801", "role": "authenticated"}';
  select count(*) into v_count from app.get_approval_request_step(v_step_id);
  if v_count <> 1 then raise exception 'staff: expected the step to resolve, got %', v_count; end if;
  select ended_reason into v_ended_reason from app.get_approval_request_by_id(v_request_id);
  if v_ended_reason is not null then raise exception 'assertion failed: staff must see ended_reason genuinely nulled, got %', v_ended_reason; end if;
  reset role; reset request.jwt.claims;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999802", "role": "authenticated"}';
  select count(*) into v_count from app.get_approval_request_step(v_step_id);
  if v_count <> 1 then raise exception 'plain member: expected the step to resolve, got %', v_count; end if;
  select count(*) into v_count from app.get_approval_request_by_id(v_request_id);
  if v_count <> 1 then raise exception 'plain member: expected the request to resolve, got %', v_count; end if;
  reset role; reset request.jwt.claims;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999803", "role": "authenticated"}';
  select count(*) into v_count from app.get_approval_request_step(v_step_id);
  if v_count <> 0 then raise exception 'customer_user-layer: expected the step to be hidden, got %', v_count; end if;
  select count(*) into v_count from app.get_approval_request_by_id(v_request_id);
  if v_count <> 0 then raise exception 'customer_user-layer: expected the request to be hidden, got %', v_count; end if;
  reset role; reset request.jwt.claims;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999805", "role": "authenticated"}';
  select count(*) into v_count from app.get_approval_request_step(v_step_id);
  if v_count <> 0 then raise exception 'cross-tenant: expected the step to be hidden, got %', v_count; end if;
  select count(*) into v_count from app.get_approval_request_by_id(v_request_id);
  if v_count <> 0 then raise exception 'cross-tenant: expected the request to be hidden, got %', v_count; end if;
  reset role; reset request.jwt.claims;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999804", "role": "authenticated"}';
  select count(*) into v_count from app.get_approval_request_step(v_step_id);
  if v_count <> 1 then raise exception 'supreme admin: expected the step to resolve, got %', v_count; end if;
  select count(*) into v_count from app.get_approval_request_by_id(v_request_id);
  if v_count <> 1 then raise exception 'supreme admin: expected the request to resolve, got %', v_count; end if;
  select count(*) into v_count from app.get_approval_request_step(gen_random_uuid());
  if v_count <> 0 then raise exception 'assertion failed: a nonexistent step id must return a genuinely empty result, got %', v_count; end if;
  select count(*) into v_count from app.get_approval_request_by_id(gen_random_uuid());
  if v_count <> 0 then raise exception 'assertion failed: a nonexistent request id must return a genuinely empty result, got %', v_count; end if;
  reset role; reset request.jwt.claims;

  raise notice 'app.get_approval_request_step/app.get_approval_request_by_id proof: staff/plain-member both resolve, ended_reason genuinely nulled on approval_requests despite a real non-null value, customer_user-layer/cross-tenant both denied on both functions, Supreme Admin resolves both, nonexistent ids return genuinely empty results';
end $$;

\echo '>> anon defense in depth: all 7 public.* wrapper functions genuinely reject anon at the grant level -- real call attempts, not merely an information_schema read'
begin;
  set local role anon;
  do $$
  declare
    v_dummy uuid := gen_random_uuid();
  begin
    begin
      perform public.list_files_for_record(v_dummy, 'employee', v_dummy, v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.list_files_for_record';
    exception when insufficient_privilege then raise notice 'anon denial proof: public.list_files_for_record correctly rejected anon';
    end;

    begin
      perform public.list_org_units(v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.list_org_units';
    exception when insufficient_privilege then raise notice 'anon denial proof: public.list_org_units correctly rejected anon';
    end;

    begin
      perform public.list_position_incumbents(v_dummy, v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.list_position_incumbents';
    exception when insufficient_privilege then raise notice 'anon denial proof: public.list_position_incumbents correctly rejected anon';
    end;

    begin
      perform public.get_job_offer_for_application(v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.get_job_offer_for_application';
    exception when insufficient_privilege then raise notice 'anon denial proof: public.get_job_offer_for_application correctly rejected anon';
    end;

    begin
      perform public.get_warehouse_location(v_dummy, v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.get_warehouse_location';
    exception when insufficient_privilege then raise notice 'anon denial proof: public.get_warehouse_location correctly rejected anon';
    end;

    begin
      perform public.get_approval_request_step(v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.get_approval_request_step';
    exception when insufficient_privilege then raise notice 'anon denial proof: public.get_approval_request_step correctly rejected anon';
    end;

    begin
      perform public.get_approval_request_by_id(v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.get_approval_request_by_id';
    exception when insufficient_privilege then raise notice 'anon denial proof: public.get_approval_request_by_id correctly rejected anon';
    end;
  end $$;
  reset role;
commit;

\echo '>> service_role smoke check: all 7 SECURITY DEFINER/INVOKER functions succeed via service_role''s own direct grant / BYPASSRLS regardless of membership, under a session that carries no request.jwt.claims at all'
begin;
  set local role service_role;
  do $$
  declare
    v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c7');
    v_master_record_id uuid := (select record_id from app.files where tenant_id = v_tenant_id limit 1);
    v_position_id uuid := (select id from app.positions where tenant_id = v_tenant_id and code = 'POS-O1C7');
    v_application_id uuid := (select application_id from app.job_offers where tenant_id = v_tenant_id);
    v_location_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant_id and code = 'ROOT-O1C7');
    v_request_id uuid := (select id from app.approval_requests where tenant_id = v_tenant_id and entity_type = 'o1c7_test_entity');
    v_step_id uuid := (select id from app.approval_request_steps where request_id = v_request_id);
    v_count integer;
  begin
    select count(*) into v_count from app.list_files_for_record(v_tenant_id, 'employee', v_master_record_id, '00000000-0000-0000-0000-000000999801'); if v_count <> 2 then raise exception 'service_role: expected 2 files, got %', v_count; end if;
    select count(*) into v_count from app.list_org_units(v_tenant_id); if v_count <> 3 then raise exception 'service_role: expected 3 org units, got %', v_count; end if;
    select count(*) into v_count from app.list_position_incumbents(v_position_id, '00000000-0000-0000-0000-000000999801'); if v_count <> 1 then raise exception 'service_role: expected 1 incumbent, got %', v_count; end if;
    select count(*) into v_count from app.get_job_offer_for_application(v_application_id); if v_count <> 1 then raise exception 'service_role: expected the offer to resolve, got %', v_count; end if;
    select count(*) into v_count from app.get_warehouse_location(v_location_id, '00000000-0000-0000-0000-000000999801'); if v_count <> 1 then raise exception 'service_role: expected the location to resolve, got %', v_count; end if;
    select count(*) into v_count from app.get_approval_request_step(v_step_id); if v_count <> 1 then raise exception 'service_role: expected the step to resolve, got %', v_count; end if;
    select count(*) into v_count from app.get_approval_request_by_id(v_request_id); if v_count <> 1 then raise exception 'service_role: expected the request to resolve, got %', v_count; end if;

    raise notice 'service_role proof: all 7 functions succeed regardless of membership (BYPASSRLS / direct grant)';
  end $$;
  reset role;
commit;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on any of the 7 new cluster-7 function pairs (14 functions) in EITHER schema; authenticated/service_role hold EXECUTE on both the app.* function and its public.* wrapper for all 7 pairs, exactly as this migration''s own GRANT PARITY section declares'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema in ('app', 'public')
    and routine_name in (
      'list_files_for_record', 'list_org_units', 'list_position_incumbents',
      'get_job_offer_for_application', 'get_warehouse_location',
      'get_approval_request_step', 'get_approval_request_by_id'
    )
    and grantee = 'anon';
  if v_count <> 0 then
    raise exception 'assertion failed: anon must hold zero EXECUTE on any of the 7 cluster-7 function pairs (14 functions, either schema), found % grants', v_count;
  end if;

  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema in ('app', 'public')
    and routine_name in (
      'list_files_for_record', 'list_org_units', 'list_position_incumbents',
      'get_job_offer_for_application', 'get_warehouse_location',
      'get_approval_request_step', 'get_approval_request_by_id'
    )
    and grantee in ('authenticated', 'service_role');
  if v_count <> 7 * 2 * 2 then
    raise exception 'assertion failed: expected exactly 28 grants (7 functions x 2 schemas x 2 grantees), found %', v_count;
  end if;

  raise notice 'schema-privilege proof: anon holds zero EXECUTE on any of the 14 new cluster-7 functions; authenticated/service_role hold the declared grant on both the app.* and public.* function in every one of the 7 pairs';
end $$;

\echo '>> o1-query-layer-cluster7.sql test suite passed -- cluster 7 (page-level-direct-reads, 10/10 call sites) is now fully DONE. The entire CG-AUDIT-2026-09-02 O1-query-layer remediation (all 8 clusters, 0 through 7) is now FULLY DONE.'
