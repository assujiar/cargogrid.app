-- Real, executable test evidence for HDN-387 (Release Blocker Triage and
-- Remediation, Step 15) -- run via `pnpm run db:test` against a real, disposable
-- Postgres database. Covers Parts 1, 3, 4, 5 of
-- 20260819000000_harden_release_blocker_triage_remediation.sql (HDN-BLK-023,
-- HDN-BLK-019, HDN-BLK-022, HDN-BLK-027). Part 6 (HDN-BLK-010's nested-exception
-- race guard, and the ISS-2026-163 defective-handler fix) was proven via a live,
-- forced two-session race and a forced unrelated-constraint collision directly
-- against a disposable probe database, mirroring HDN-371.md §6.2/6.3's own
-- established evidentiary standard for this exact mechanism -- not committed here
-- as a permanent test file, matching that precedent (no other checkpoint in this
-- repository committed one either); see HDN-387.md §11 for the transcript.
--
-- Fixture identifier range: 00000000-0000-0000-0000-000039000001..010.
-- Grep-verified unclaimed against every other *.sql fixture in this directory
-- before use.

\set ON_ERROR_STOP on

-- ISS-2026-257: fixed test-only key for app.integration_secrets_encryption_key() --
-- production key provisioning/rotation/custody is a disclosed, out-of-scope
-- infrastructure concern (mirrors app.vendor_financial_encryption_keys own pattern).
select set_config('app.integration_secrets_encryption_key', 'test-only-key-not-for-production', false);

\echo '>> setup: tenant hdn387a (INTHUB:Configure holder, an enterprise_sso_oidc connection and a payment_gateway connection); tenant hdn387b (a tenant_admin, an HRS:View holder, a zero-HRS-role org_user, a position_grades row); tenant hdn387c (a document-type-registered contract upload, a file under legal hold, a file_access_logs row, a Supreme Admin); tenant hdn387d (an INTHUB:Configure holder, a payment_gateway connection, for the webhook-alert-wiring proof)'
do $$
declare
  v_tenant_a uuid;
  v_configurer_role uuid;
  v_configurer_draft app.role_versions;
  v_sso_conn app.integration_connections;
  v_pg_conn app.integration_connections;

  v_tenant_b uuid;
  v_hr_full_role uuid;
  v_hr_full_draft app.role_versions;
  v_hr_view_role uuid;
  v_hr_view_draft app.role_versions;

  v_tenant_c uuid;
  v_org_unit_c uuid;
  v_doc_draft app.config_versions;
  v_file app.files;
  v_log app.file_access_logs;

  v_tenant_d uuid;
  v_d_configurer_role uuid;
  v_d_configurer_draft app.role_versions;
  v_d_conn app.integration_connections;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000039000001', 'configurer@hdn387a.test'),
    ('00000000-0000-0000-0000-000039000002', 'admin@hdn387b.test'),
    ('00000000-0000-0000-0000-000039000003', 'hrviewer@hdn387b.test'),
    ('00000000-0000-0000-0000-000039000004', 'zerorole@hdn387b.test'),
    ('00000000-0000-0000-0000-000039000005', 'admin@hdn387c.test'),
    ('00000000-0000-0000-0000-000039000006', 'supreme@hdn387c.test'),
    ('00000000-0000-0000-0000-000039000007', 'admin@hdn387d.test');

  -- Tenant A: Part 1 (HDN-BLK-023, SSO activation gate).
  perform app.provision_tenant('hdn387a', 'HDN387 A Co', 'idem-hdn387a', 'tester');
  v_tenant_a := (select id from app.tenants where slug = 'hdn387a');
  perform app.transition_tenant_status(v_tenant_a, 'active', 'setup', 'tester');
  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000039000001', 'configurer@hdn387a.test', 'Configurer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'configurer@hdn387a.test'), 'active', 'onboarded', 'tester');
  v_configurer_role := (app.create_role(v_tenant_a, 'Configurer', 'INTHUB:Configure', 'tester')).id;
  v_configurer_draft := app.create_role_version(v_configurer_role, 'tester');
  perform app.set_role_version_permissions(v_configurer_draft.id, array(select id from app.permissions where resource_module_code = 'INTHUB' and action = 'Configure'), 'tester');
  perform app.publish_role_version(v_configurer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_configurer_role and status = 'published'), '00000000-0000-0000-0000-000039000001', '00000000-0000-0000-0000-000039000001', 'tester');
  select * into v_sso_conn from app.create_integration_connection(v_tenant_a, 'enterprise_sso_oidc', 'Okta OIDC HDN387', 'production', null, null, null,
    '{"issuer": "https://hdn387a.okta.com", "client_id": "cg-client"}'::jsonb, 'okta-secret', '00000000-0000-0000-0000-000039000001', 'configurer');
  select * into v_pg_conn from app.create_integration_connection(v_tenant_a, 'payment_gateway', 'Payment Gateway HDN387', 'production', null, null, null,
    '{"apiUrl": "https://pay.hdn387a.test"}'::jsonb, 'pay-secret', '00000000-0000-0000-0000-000039000001', 'configurer');

  -- Tenant B: Part 4 (HDN-BLK-022, HRIS RLS gate on position_grades).
  perform app.provision_tenant('hdn387b', 'HDN387 B Co', 'idem-hdn387b', 'tester');
  v_tenant_b := (select id from app.tenants where slug = 'hdn387b');
  perform app.transition_tenant_status(v_tenant_b, 'active', 'setup', 'tester');
  perform app.invite_user(v_tenant_b, '00000000-0000-0000-0000-000039000002', 'admin@hdn387b.test', 'Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@hdn387b.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000039000002', 'tenant_admin', v_tenant_b, null, 'tester');
  perform app.invite_user(v_tenant_b, '00000000-0000-0000-0000-000039000003', 'hrviewer@hdn387b.test', 'HR Viewer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'hrviewer@hdn387b.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant_b, '00000000-0000-0000-0000-000039000004', 'zerorole@hdn387b.test', 'Zero Role', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'zerorole@hdn387b.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000039000004', 'org_user', v_tenant_b, null, 'tester');

  v_hr_full_role := (app.create_role(v_tenant_b, 'HR Full', 'HRS full', 'tester')).id;
  v_hr_full_draft := app.create_role_version(v_hr_full_role, 'tester');
  perform app.set_role_version_permissions(v_hr_full_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('Create', 'Edit', 'View')), 'tester');
  perform app.publish_role_version(v_hr_full_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant_b, (select id from app.role_versions where role_id = v_hr_full_role and status = 'published'), '00000000-0000-0000-0000-000039000002', '00000000-0000-0000-0000-000039000002', 'tester');

  v_hr_view_role := (app.create_role(v_tenant_b, 'HR Viewer', 'HRS:View', 'tester')).id;
  v_hr_view_draft := app.create_role_version(v_hr_view_role, 'tester');
  perform app.set_role_version_permissions(v_hr_view_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action = 'View'), 'tester');
  perform app.publish_role_version(v_hr_view_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant_b, (select id from app.role_versions where role_id = v_hr_view_role and status = 'published'), '00000000-0000-0000-0000-000039000003', '00000000-0000-0000-0000-000039000002', 'tester');

  perform app.create_position_grade(v_tenant_b, 'GR-HDN387', 'HDN387 Probe Grade', 1, 'probe', '00000000-0000-0000-0000-000039000002', 'admin');

  -- Tenant C: Part 3 (HDN-BLK-019, file_access_logs legal-hold trigger).
  perform app.provision_tenant('hdn387c', 'HDN387 C Co', 'idem-hdn387c', 'tester');
  v_tenant_c := (select id from app.tenants where slug = 'hdn387c');
  perform app.transition_tenant_status(v_tenant_c, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_c, 'company', null, 'HDN387C-CO', 'HDN387 C Co HQ', 'tester');
  v_org_unit_c := (select id from app.org_units where tenant_id = v_tenant_c and code = 'HDN387C-CO');
  perform app.invite_user(v_tenant_c, '00000000-0000-0000-0000-000039000005', 'admin@hdn387c.test', 'Admin', v_org_unit_c, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@hdn387c.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000039000005', 'tenant_admin', v_tenant_c, null, 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000039000006', 'supreme_admin', null, null, 'tester');

  if not exists (select 1 from app.document_types where code = 'contract') then
    perform app.register_document_type('contract', 'Contract', 'DOC', '00000000-0000-0000-0000-000039000006', 'supreme admin');
  end if;
  v_doc_draft := app.create_config_draft('document:contract', v_tenant_c, 'tenant', null, '00000000-0000-0000-0000-000039000005', 'admin');
  perform app.set_config_items(v_doc_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('application/pdf')),
    jsonb_build_object('key', 'max_size_bytes', 'value', to_jsonb(10485760)),
    jsonb_build_object('key', 'retention_class', 'value', to_jsonb('operational_contract_plus_90d'::text)),
    jsonb_build_object('key', 'default_classification', 'value', to_jsonb('confidential'::text)),
    jsonb_build_object('key', 'legal_hold_eligible', 'value', to_jsonb(true))
  ), '00000000-0000-0000-0000-000039000005', 'admin');
  perform app.publish_document_type_definition(v_doc_draft.id, '00000000-0000-0000-0000-000039000005', now(), 'admin');

  v_file := app.initiate_file_upload(v_tenant_c, 'contract', 'shipment', gen_random_uuid(), 'hdn387-held.pdf', 'application/pdf', 1000, null, false, null, array[v_org_unit_c], null, 'idem-hdn387c-1', '00000000-0000-0000-0000-000039000005', 'admin');
  v_log := app.authorize_file_access(v_file.id, 'download', '00000000-0000-0000-0000-000039000005');
  perform app.set_file_legal_hold(v_file.id, true, 'HDN387 probe litigation hold', '00000000-0000-0000-0000-000039000005', 'admin');

  -- Tenant D: Part 5 (HDN-BLK-027, webhook signature-failure alert wiring).
  perform app.provision_tenant('hdn387d', 'HDN387 D Co', 'idem-hdn387d', 'tester');
  v_tenant_d := (select id from app.tenants where slug = 'hdn387d');
  perform app.transition_tenant_status(v_tenant_d, 'active', 'setup', 'tester');
  perform app.invite_user(v_tenant_d, '00000000-0000-0000-0000-000039000007', 'admin@hdn387d.test', 'Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@hdn387d.test'), 'active', 'onboarded', 'tester');
  v_d_configurer_role := (app.create_role(v_tenant_d, 'Configurer', 'INTHUB:Configure', 'tester')).id;
  v_d_configurer_draft := app.create_role_version(v_d_configurer_role, 'tester');
  perform app.set_role_version_permissions(v_d_configurer_draft.id, array(select id from app.permissions where resource_module_code = 'INTHUB' and action = 'Configure'), 'tester');
  perform app.publish_role_version(v_d_configurer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant_d, (select id from app.role_versions where role_id = v_d_configurer_role and status = 'published'), '00000000-0000-0000-0000-000039000007', '00000000-0000-0000-0000-000039000007', 'tester');
  select * into v_d_conn from app.create_integration_connection(v_tenant_d, 'payment_gateway', 'Payment Gateway HDN387D', 'production', null, null, null,
    '{"apiUrl": "https://pay.hdn387d.test"}'::jsonb, 'pay-secret', '00000000-0000-0000-0000-000039000007', 'admin');

  raise notice 'FIXTURE OK tenant_a=%, sso_conn=%, pg_conn=%, tenant_b=%, tenant_c=%, file=%, log=%, tenant_d=%, d_conn=%',
    v_tenant_a, v_sso_conn.id, v_pg_conn.id, v_tenant_b, v_tenant_c, v_file.id, v_log.id, v_tenant_d, v_d_conn.id;
end;
$$;

\echo '>> Part 1 (HDN-BLK-023, Critical): app.request_integration_connection_status_change refuses to reactivate an enterprise SSO connection through the generic path; non-active transitions on the same connection still work; a non-SSO connection reactivates unchanged; the underlying core no longer holds an authenticated/service_role EXECUTE grant'
do $$
declare
  v_sso_conn uuid := (select id from app.integration_connections where tenant_id = (select id from app.tenants where slug = 'hdn387a') and adapter_code = 'enterprise_sso_oidc');
  v_pg_conn uuid := (select id from app.integration_connections where tenant_id = (select id from app.tenants where slug = 'hdn387a') and adapter_code = 'payment_gateway');
  v_actor uuid := '00000000-0000-0000-0000-000039000001';
  v_result app.integration_connections;
begin
  begin
    perform app.request_integration_connection_status_change(v_sso_conn, 'active', 'test reactivation', v_actor, 'configurer');
    raise exception 'assertion failed: expected enterprise_sso_activation_requires_specialized_wrapper, but the call succeeded';
  exception
    when others then
      if SQLERRM !~ 'enterprise_sso_activation_requires_specialized_wrapper' then raise; end if;
  end;

  select * into v_result from app.request_integration_connection_status_change(v_sso_conn, 'disabled', 'probe disable', v_actor, 'configurer');
  if v_result.status <> 'disabled' then
    raise exception 'assertion failed: expected the SSO connection to disable via the new entry point, got status=%', v_result.status;
  end if;

  perform app.request_integration_connection_status_change(v_pg_conn, 'disabled', 'probe disable', v_actor, 'configurer');
  select * into v_result from app.request_integration_connection_status_change(v_pg_conn, 'active', 'probe reactivate', v_actor, 'configurer');
  if v_result.status <> 'active' then
    raise exception 'assertion failed: expected the non-SSO connection to reactivate unchanged via the new entry point, got status=%', v_result.status;
  end if;

  if exists (
    select 1 from information_schema.role_routine_grants
    where routine_schema = 'app' and routine_name = 'set_integration_connection_status' and grantee in ('authenticated', 'service_role')
  ) then
    raise exception 'assertion failed: app.set_integration_connection_status must not hold an authenticated/service_role EXECUTE grant -- the SSO bypass is not closed';
  end if;
  if not exists (
    select 1 from information_schema.role_routine_grants
    where routine_schema = 'app' and routine_name = 'request_integration_connection_status_change' and grantee in ('authenticated', 'service_role')
  ) then
    raise exception 'assertion failed: app.request_integration_connection_status_change is missing its own authenticated/service_role EXECUTE grant';
  end if;
end;
$$;

\echo '>> Part 3 (HDN-BLK-019, High): a legally-held file''s own file_access_logs row is protected from raw UPDATE and DELETE for a non-Supreme-Admin, in both directions; a Supreme Admin''s RPD-022 absolute-CRUD override still works and is audited'
do $$
declare
  v_log_id uuid := (select id from app.file_access_logs where file_id = (select id from app.files where tenant_id = (select id from app.tenants where slug = 'hdn387c')));
begin
  begin
    delete from app.file_access_logs where id = v_log_id;
    raise exception 'assertion failed: expected file_access_log_legal_hold_blocks_deletion on a raw DELETE, but it succeeded';
  exception
    when others then
      if SQLERRM !~ 'file_access_log_legal_hold_blocks_deletion' then raise; end if;
  end;

  begin
    update app.file_access_logs set result = 'denied' where id = v_log_id;
    raise exception 'assertion failed: expected file_access_log_legal_hold_blocks_deletion on a raw UPDATE, but it succeeded';
  exception
    when others then
      if SQLERRM !~ 'file_access_log_legal_hold_blocks_deletion' then raise; end if;
  end;

  if not exists (select 1 from app.file_access_logs where id = v_log_id and result = 'granted') then
    raise exception 'assertion failed: expected the row to survive both blocked attempts, unchanged';
  end if;
end;
$$;

do $$
declare
  v_log_id uuid := (select id from app.file_access_logs where file_id = (select id from app.files where tenant_id = (select id from app.tenants where slug = 'hdn387c')));
  v_audit_count_before integer;
  v_audit_count_after integer;
begin
  select count(*) into v_audit_count_before from app.audit_logs where resource_type = 'app.file_access_logs' and resource_id = v_log_id;

  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000039000006", "role": "authenticated"}', true);
  update app.file_access_logs set result = 'denied' where id = v_log_id;
  perform set_config('request.jwt.claims', 'null', true);

  if (select result from app.file_access_logs where id = v_log_id) <> 'denied' then
    raise exception 'assertion failed: expected the Supreme Admin absolute-CRUD override to actually apply the UPDATE';
  end if;

  select count(*) into v_audit_count_after from app.audit_logs where resource_type = 'app.file_access_logs' and resource_id = v_log_id;
  if v_audit_count_after <> v_audit_count_before + 1 then
    raise exception 'assertion failed: expected exactly one new audit_logs row for the Supreme Admin override, before=% after=%', v_audit_count_before, v_audit_count_after;
  end if;
  if not exists (select 1 from app.audit_logs where resource_type = 'app.file_access_logs' and resource_id = v_log_id and action = 'update_legally_held_file_access_log') then
    raise exception 'assertion failed: expected the new audit_logs row to be action=update_legally_held_file_access_log';
  end if;
end;
$$;

\echo '>> Part 4 (HDN-BLK-022, High): app.position_grades -- a tenant member holding zero HRS role sees zero rows at the raw-RLS level despite active tenant membership; an HRS:View holder sees the real row; app.check_hris_authority holds its own explicit authenticated EXECUTE grant'
do $$
declare
  v_tenant_b uuid := (select id from app.tenants where slug = 'hdn387b');
begin
  if not exists (
    select 1 from information_schema.role_routine_grants
    where routine_schema = 'app' and routine_name = 'check_hris_authority' and grantee = 'authenticated'
  ) then
    raise exception 'assertion failed: app.check_hris_authority must hold its own explicit authenticated EXECUTE grant -- an RLS policy predicate is evaluated AS the querying role';
  end if;
end;
$$;

-- RLS itself is bypassed for the superuser/table-owner role this whole file
-- otherwise runs as -- request.jwt.claims alone proves nothing without also
-- switching to the real `authenticated` role, mirroring every other RLS probe in
-- this test suite (e.g. scripts/db-tests/audit-trail.sql's own `set local role
-- authenticated` blocks). Caught live: the first draft of this block used only
-- set_config and passed vacuously (both actors "saw" every row) because the
-- connecting role bypasses RLS outright, regardless of claims.
begin;
set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000039000004", "role": "authenticated"}';
do $$
declare
  v_tenant_b uuid := (select id from app.tenants where slug = 'hdn387b');
  v_zero_count integer;
begin
  select count(*) into v_zero_count from app.position_grades where tenant_id = v_tenant_b;
  if v_zero_count <> 0 then
    raise exception 'assertion failed: expected a zero-HRS-role tenant member to see zero position_grades rows at the raw-RLS level, got %', v_zero_count;
  end if;
end;
$$;
reset role;
commit;

begin;
set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000039000003", "role": "authenticated"}';
do $$
declare
  v_tenant_b uuid := (select id from app.tenants where slug = 'hdn387b');
  v_view_count integer;
begin
  select count(*) into v_view_count from app.position_grades where tenant_id = v_tenant_b;
  if v_view_count <> 1 then
    raise exception 'assertion failed: expected the HRS:View holder to see exactly 1 position_grades row, got %', v_view_count;
  end if;
end;
$$;
reset role;
commit;

\echo '>> Part 5 (HDN-BLK-027, High): app.ingest_finance_payment_gateway_webhook_event''s own signature_verification_failed branch now raises a real observability alert, mirroring app.record_job_failure''s own dead-letter alert pattern; the ingestion attempt itself is still recorded exactly as before (no change to the caller-facing contract)'
do $$
declare
  v_conn_id uuid := (select id from app.integration_connections where tenant_id = (select id from app.tenants where slug = 'hdn387d') and adapter_code = 'payment_gateway');
  v_tenant_d uuid := (select id from app.tenants where slug = 'hdn387d');
  v_ts bigint := extract(epoch from now())::bigint;
  v_payload text := jsonb_build_object('event_id', 'hdn387-evt-1', 'event_type', 'payment_confirmed', 'external_reference', 'HDN387-REF-1')::text;
  v_result record;
  v_incident_count_before integer;
  v_incident_count_after integer;
begin
  select count(*) into v_incident_count_before from app.incidents where tenant_id = v_tenant_d and source_type = 'webhook';

  select * into v_result from app.ingest_finance_payment_gateway_webhook_event(v_conn_id, 'client-key-hdn387', v_payload, v_ts, 'deliberately-bad-signature');
  if v_result.ingest_status <> 'invalid' then
    raise exception 'assertion failed: expected ingest_status=invalid for a bad signature, got %', v_result.ingest_status;
  end if;

  if not exists (select 1 from app.finance_payment_gateway_ingestion_attempts where connection_id = v_conn_id and result = 'invalid' and reason = 'signature_verification_failed') then
    raise exception 'assertion failed: expected the ingestion attempt to still be recorded exactly as before this checkpoint';
  end if;

  select count(*) into v_incident_count_after from app.incidents where tenant_id = v_tenant_d and source_type = 'webhook';
  if v_incident_count_after <> v_incident_count_before + 1 then
    raise exception 'assertion failed: expected exactly one new app.incidents row after the signature failure, before=% after=%', v_incident_count_before, v_incident_count_after;
  end if;
  if not exists (select 1 from app.incidents where tenant_id = v_tenant_d and source_type = 'webhook' and signal_type = 'error' and severity = 'high') then
    raise exception 'assertion failed: expected the new incident to carry source_type=webhook, signal_type=error, severity=high';
  end if;
end;
$$;

\echo 'ALL HDN-387 (Release Blocker Triage and Remediation) db-test assertions passed.'
