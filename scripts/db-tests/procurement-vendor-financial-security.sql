-- Real, executable test evidence for PRC-254 (Vendor Banking and Tax Security,
-- CG-S11-PRC-005) -- run via `pnpm run db:test` against a real, disposable Postgres
-- database.

\set ON_ERROR_STOP on

-- Fixed test-only encryption key (migration design note 1) -- production key
-- provisioning/rotation/custody is a disclosed, out-of-scope infrastructure concern.
select set_config('app.vendor_financial_encryption_key', 'test-only-key-not-for-production', false);

\echo '>> setup: two tenants (pfin1, pfin2). pfin1 gets a tenant_admin, PRC staff (Create/Edit/View), an approver (Approve/Reject/View), an override manager (Override/View), a personal-data viewer (View personal data/View), a plain viewer (View), and a customer_user-layer actor. pfin2 gets its own tenant_admin/staff for cross-tenant checks. A global Supreme Admin is also seeded.'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_staff_role uuid;
  v_staff_draft app.role_versions;
  v_approver_role uuid;
  v_approver_draft app.role_versions;
  v_manager_role uuid;
  v_manager_draft app.role_versions;
  v_pdv_role uuid;
  v_pdv_draft app.role_versions;
  v_viewer_role uuid;
  v_viewer_draft app.role_versions;
  v_t2_staff_role uuid;
  v_t2_staff_draft app.role_versions;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000092101', 'admin@pfin1.test'),
    ('00000000-0000-0000-0000-000000092102', 'staff@pfin1.test'),
    ('00000000-0000-0000-0000-000000092103', 'approver@pfin1.test'),
    ('00000000-0000-0000-0000-000000092104', 'manager@pfin1.test'),
    ('00000000-0000-0000-0000-000000092105', 'pdv@pfin1.test'),
    ('00000000-0000-0000-0000-000000092106', 'viewer@pfin1.test'),
    ('00000000-0000-0000-0000-000000092107', 'customer@pfin1.test'),
    ('00000000-0000-0000-0000-000000092108', 'manager2@pfin1.test'),
    ('00000000-0000-0000-0000-000000092201', 'admin@pfin2.test'),
    ('00000000-0000-0000-0000-000000092202', 'staff@pfin2.test'),
    ('00000000-0000-0000-0000-000000092999', 'supreme@pfin.test');

  perform app.provision_tenant('pfin1', 'Vendor Financial Co 1', 'idem-pfin1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'pfin1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('pfin2', 'Vendor Financial Co 2', 'idem-pfin2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'pfin2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000092101', 'admin@pfin1.test', 'Pfin1 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@pfin1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000092101', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000092102', 'staff@pfin1.test', 'Pfin1 Staff', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@pfin1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000092103', 'approver@pfin1.test', 'Pfin1 Approver', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'approver@pfin1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000092104', 'manager@pfin1.test', 'Pfin1 Manager', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'manager@pfin1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000092105', 'pdv@pfin1.test', 'Pfin1 PDV', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'pdv@pfin1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000092106', 'viewer@pfin1.test', 'Pfin1 Viewer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@pfin1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000092107', 'customer@pfin1.test', 'Pfin1 Customer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer@pfin1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000092107', 'customer_user', v_tenant1, 'external-customer-account', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000092108', 'manager2@pfin1.test', 'Pfin1 Manager 2', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'manager2@pfin1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000092201', 'admin@pfin2.test', 'Pfin2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@pfin2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000092201', 'tenant_admin', v_tenant2, null, 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000092202', 'staff@pfin2.test', 'Pfin2 Staff', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@pfin2.test'), 'active', 'onboarded', 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000092999', 'supreme_admin', null, null, 'tester');

  v_staff_role := (app.create_role(v_tenant1, 'PRC Financial Staff', 'Create/Edit/View', 'tester')).id;
  v_staff_draft := app.create_role_version(v_staff_role, 'tester');
  perform app.set_role_version_permissions(v_staff_draft.id, array(select id from app.permissions where resource_module_code = 'PRC' and action in ('Create', 'Edit', 'View', 'Download')), 'tester');
  perform app.publish_role_version(v_staff_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_staff_role and status = 'published'), '00000000-0000-0000-0000-000000092102', '00000000-0000-0000-0000-000000092101', 'tester');

  v_approver_role := (app.create_role(v_tenant1, 'PRC Financial Approver', 'Approve/Reject/View', 'tester')).id;
  v_approver_draft := app.create_role_version(v_approver_role, 'tester');
  perform app.set_role_version_permissions(v_approver_draft.id, array(select id from app.permissions where resource_module_code = 'PRC' and action in ('Approve', 'Reject', 'View')), 'tester');
  perform app.publish_role_version(v_approver_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_approver_role and status = 'published'), '00000000-0000-0000-0000-000000092103', '00000000-0000-0000-0000-000000092101', 'tester');

  v_manager_role := (app.create_role(v_tenant1, 'PRC Financial Manager', 'Override/View', 'tester')).id;
  v_manager_draft := app.create_role_version(v_manager_role, 'tester');
  perform app.set_role_version_permissions(v_manager_draft.id, array(select id from app.permissions where resource_module_code = 'PRC' and action in ('Override', 'View')), 'tester');
  perform app.publish_role_version(v_manager_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_manager_role and status = 'published'), '00000000-0000-0000-0000-000000092104', '00000000-0000-0000-0000-000000092101', 'tester');
  -- A second, independent Override holder (092108) -- needed to test that reactivate
  -- blocks the SAME actor who placed the hold (self_reactivation_not_allowed) while
  -- still succeeding for a genuinely different Override holder.
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_manager_role and status = 'published'), '00000000-0000-0000-0000-000000092108', '00000000-0000-0000-0000-000000092101', 'tester');

  v_pdv_role := (app.create_role(v_tenant1, 'PRC Financial Personal Data Viewer', 'View personal data/View', 'tester')).id;
  v_pdv_draft := app.create_role_version(v_pdv_role, 'tester');
  perform app.set_role_version_permissions(v_pdv_draft.id, array(select id from app.permissions where resource_module_code = 'PRC' and action in ('View personal data', 'View')), 'tester');
  perform app.publish_role_version(v_pdv_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_pdv_role and status = 'published'), '00000000-0000-0000-0000-000000092105', '00000000-0000-0000-0000-000000092101', 'tester');

  v_viewer_role := (app.create_role(v_tenant1, 'PRC Financial Viewer', 'View only', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'PRC' and action in ('View')), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000092106', '00000000-0000-0000-0000-000000092101', 'tester');

  v_t2_staff_role := (app.create_role(v_tenant2, 'PRC Financial Staff T2', 'Create/Edit/View', 'tester')).id;
  v_t2_staff_draft := app.create_role_version(v_t2_staff_role, 'tester');
  perform app.set_role_version_permissions(v_t2_staff_draft.id, array(select id from app.permissions where resource_module_code = 'PRC' and action in ('Create', 'Edit', 'View')), 'tester');
  perform app.publish_role_version(v_t2_staff_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_t2_staff_role and status = 'published'), '00000000-0000-0000-0000-000000092202', '00000000-0000-0000-0000-000000092201', 'tester');
end $$;

\echo '>> setup: one vendor per tenant, plus a second pfin1 vendor for duplicate-hash tests; register + publish the vendor_financial_verification_document document type in both tenants'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pfin1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'pfin2');
  v_admin1 uuid := '00000000-0000-0000-0000-000000092101';
  v_admin2 uuid := '00000000-0000-0000-0000-000000092201';
  v_staff uuid := '00000000-0000-0000-0000-000000092102';
  v_t2_staff uuid := '00000000-0000-0000-0000-000000092202';
  v_profile app.vendor_profiles;
  v_profile2 app.vendor_profiles;
  v_t2_profile app.vendor_profiles;
  v_doctype_draft app.config_versions;
  v_t2_doctype_draft app.config_versions;
begin
  v_profile := app.create_vendor_profile_draft(v_tenant1, 'PT Pfin Trucking', 'Contoso', 'PT', 'REG-9401', 'trucking', 30, 'staff_created', 'idem-pfin-vendor-1', v_staff, 'staff');
  v_profile2 := app.create_vendor_profile_draft(v_tenant1, 'PT Pfin Duplicate Test', null, 'PT', 'REG-9402', 'trucking', 45, 'staff_created', 'idem-pfin-vendor-2', v_staff, 'staff');
  v_t2_profile := app.create_vendor_profile_draft(v_tenant2, 'PT Pfin2 Vendor', null, 'PT', 'REG-9501', 'trucking', 30, 'staff_created', 'idem-pfin2-vendor-1', v_t2_staff, 'staff');

  perform app.register_document_type('vendor_financial_verification_document', 'Vendor Financial Verification Document', 'DOC', '00000000-0000-0000-0000-000000092999', 'supreme');
  v_doctype_draft := app.create_config_draft('document:vendor_financial_verification_document', v_tenant1, 'tenant', null, v_admin1, 'admin');
  perform app.set_config_items(v_doctype_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('application/pdf', 'image/jpeg')),
    jsonb_build_object('key', 'max_size_bytes', 'value', to_jsonb(10485760)),
    jsonb_build_object('key', 'retention_class', 'value', to_jsonb('operational_contract_plus_90d'::text)),
    jsonb_build_object('key', 'default_classification', 'value', to_jsonb('confidential'::text)),
    jsonb_build_object('key', 'legal_hold_eligible', 'value', to_jsonb(true))
  ), v_admin1, 'admin');
  perform app.publish_document_type_definition(v_doctype_draft.id, v_admin1, now(), 'admin');

  v_t2_doctype_draft := app.create_config_draft('document:vendor_financial_verification_document', v_tenant2, 'tenant', null, v_admin2, 'admin2');
  perform app.set_config_items(v_t2_doctype_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('application/pdf')),
    jsonb_build_object('key', 'max_size_bytes', 'value', to_jsonb(10485760)),
    jsonb_build_object('key', 'retention_class', 'value', to_jsonb('operational_contract_plus_90d'::text)),
    jsonb_build_object('key', 'default_classification', 'value', to_jsonb('confidential'::text)),
    jsonb_build_object('key', 'legal_hold_eligible', 'value', to_jsonb(false))
  ), v_admin2, 'admin2');
  perform app.publish_document_type_definition(v_t2_doctype_draft.id, v_admin2, now(), 'admin2');
end $$;

\echo '>> encryption-key-not-configured fail-closed: unset the GUC, confirm a clean error (not a crash), then restore it'
do $$
declare
  v_vendor_id uuid := (select master_record_id from app.vendor_profiles where legal_name = 'PT Pfin Trucking');
  v_staff uuid := '00000000-0000-0000-0000-000000092102';
begin
  perform set_config('app.vendor_financial_encryption_key', '', true);
  begin
    perform app.create_vendor_bank_account_draft(v_vendor_id, 'Contoso Trucking', 'Bank Mandiri', '1234567890', 'IDR', 'primary', null, null, 'idem-pfin-keytest', v_staff, 'staff');
    raise exception 'assertion failed: expected encryption_key_not_configured with the GUC unset';
  exception
    when others then
      if sqlerrm not like 'encryption_key_not_configured%' then raise; end if;
  end;
  perform set_config('app.vendor_financial_encryption_key', 'test-only-key-not-for-production', true);
  -- confirm it works again once the key is restored (also proves nothing was
  -- partially/incorrectly persisted by the failed attempt above).
  if exists (select 1 from app.vendor_bank_accounts where idempotency_key = 'idem-pfin-keytest') then
    raise exception 'assertion failed: the failed-encryption attempt must not have persisted any row';
  end if;
end $$;

\echo '>> bank account lifecycle: draft validation -> idempotency replay/mismatch -> update -> submit -> self-approval blocked -> stale reauth blocked -> viewer/staff cannot decide -> approve (fresh reauth, different actor) -> masked read never contains plaintext/ciphertext -> raw-SQL column-grant defense in depth -> reveal requires View personal data + reauth + reason, and is audited'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pfin1');
  v_vendor_id uuid := (select master_record_id from app.vendor_profiles where legal_name = 'PT Pfin Trucking');
  v_staff uuid := '00000000-0000-0000-0000-000000092102';
  v_approver uuid := '00000000-0000-0000-0000-000000092103';
  v_viewer uuid := '00000000-0000-0000-0000-000000092106';
  v_pdv uuid := '00000000-0000-0000-0000-000000092105';
  v_account app.vendor_bank_accounts;
  v_replay app.vendor_bank_accounts;
  v_masked record;
  v_revealed record;
  v_audit_count integer;
begin
  -- validation: bad currency, bad purpose, too-short account number.
  begin
    perform app.create_vendor_bank_account_draft(v_vendor_id, 'Contoso Trucking', 'Bank Mandiri', '1234567890', 'ZZZ', 'primary', null, null, 'idem-pfin-bad-ccy', v_staff, 'staff');
    raise exception 'assertion failed: expected invalid_currency';
  exception
    when others then
      if sqlerrm not like 'invalid_currency%' then raise; end if;
  end;
  begin
    perform app.create_vendor_bank_account_draft(v_vendor_id, 'Contoso Trucking', 'Bank Mandiri', '1234567890', 'IDR', 'nonsense', null, null, 'idem-pfin-bad-purpose', v_staff, 'staff');
    raise exception 'assertion failed: expected invalid_purpose';
  exception
    when others then
      if sqlerrm not like 'invalid_purpose%' then raise; end if;
  end;
  begin
    perform app.create_vendor_bank_account_draft(v_vendor_id, 'Contoso Trucking', 'Bank Mandiri', '12', 'IDR', 'primary', null, null, 'idem-pfin-bad-acctnum', v_staff, 'staff');
    raise exception 'assertion failed: expected invalid_account_number';
  exception
    when others then
      if sqlerrm not like 'invalid_account_number%' then raise; end if;
  end;

  v_account := app.create_vendor_bank_account_draft(v_vendor_id, 'Contoso Trucking', 'Bank Mandiri', '1234567890123', 'IDR', 'primary', null, null, 'idem-pfin-acct-1', v_staff, 'staff');
  if v_account.status <> 'draft' or v_account.account_number_last4 <> '0123' or v_account.account_family_id is null then
    raise exception 'assertion failed: expected draft with last4=0123 and a minted family id, got status=% last4=%', v_account.status, v_account.account_number_last4;
  end if;

  -- idempotency-key replay returns the same row; a target mismatch (different
  -- account_number_hash) is rejected.
  v_replay := app.create_vendor_bank_account_draft(v_vendor_id, 'Contoso Trucking', 'Bank Mandiri', '1234567890123', 'IDR', 'primary', null, null, 'idem-pfin-acct-1', v_staff, 'staff');
  if v_replay.id <> v_account.id then
    raise exception 'assertion failed: expected idempotency replay to return the exact same row';
  end if;
  begin
    perform app.create_vendor_bank_account_draft(v_vendor_id, 'Contoso Trucking', 'Bank Mandiri', '9999999999999', 'IDR', 'primary', null, null, 'idem-pfin-acct-1', v_staff, 'staff');
    raise exception 'assertion failed: expected idempotency_key_conflict for a reused key with a different account number';
  exception
    when others then
      if sqlerrm not like 'idempotency_key_conflict%' then raise; end if;
  end;
  begin
    perform app.create_vendor_bank_account_draft(v_vendor_id, 'Contoso Trucking', 'Bank Mandiri', '1234567890123', 'USD', 'primary', null, null, 'idem-pfin-acct-1', v_staff, 'staff');
    raise exception 'assertion failed: expected idempotency_key_conflict for a reused key with a different currency';
  exception
    when others then
      if sqlerrm not like 'idempotency_key_conflict%' then raise; end if;
  end;
  begin
    perform app.create_vendor_bank_account_draft(v_vendor_id, 'Contoso Trucking', 'Bank Mandiri', '1234567890123', 'IDR', 'settlement', null, null, 'idem-pfin-acct-1', v_staff, 'staff');
    raise exception 'assertion failed: expected idempotency_key_conflict for a reused key with a different purpose';
  exception
    when others then
      if sqlerrm not like 'idempotency_key_conflict%' then raise; end if;
  end;
  -- correctness-concurrency fix: effective_from and evidence_file_id are now also
  -- load-bearing in the idempotency-key comparison (the exact under-compared-field
  -- gap class PRC-253's own review found twice, for expiry_date then reminder_offsets).
  begin
    perform app.create_vendor_bank_account_draft(v_vendor_id, 'Contoso Trucking', 'Bank Mandiri', '1234567890123', 'IDR', 'primary', current_date + 30, null, 'idem-pfin-acct-1', v_staff, 'staff');
    raise exception 'assertion failed: expected idempotency_key_conflict for a reused key with a different effective_from';
  exception
    when others then
      if sqlerrm not like 'idempotency_key_conflict%' then raise; end if;
  end;

  -- update draft; stale_version on a second update with the stale expected_version.
  v_account := app.update_vendor_bank_account_draft(v_account.id, v_account.record_version, 'Contoso Trucking Renamed', 'Bank Mandiri', '1234567890123', 'IDR', 'primary', null, null, v_staff, 'staff');
  begin
    perform app.update_vendor_bank_account_draft(v_account.id, 1, 'Another rename', 'Bank Mandiri', '1234567890123', 'IDR', 'primary', null, null, v_staff, 'staff');
    raise exception 'assertion failed: expected stale_version on update with a stale expected_version';
  exception
    when others then
      if sqlerrm not like 'stale_version%' then raise; end if;
  end;

  v_account := app.submit_vendor_bank_account_for_approval(v_account.id, v_account.record_version, v_staff, 'staff');
  if v_account.status <> 'pending_approval' then
    raise exception 'assertion failed: expected pending_approval, got %', v_account.status;
  end if;

  -- a viewer (not the maker, no Approve) cannot decide -- insufficient_authority.
  -- (staff -- the maker -- deciding their own proposal is exercised separately below
  -- as self_approval_not_allowed, which this RPC checks BEFORE the authority gate,
  -- since it is the more specific rule; see design note 7.)
  begin
    perform app.decide_vendor_bank_account_approval(v_account.id, v_account.record_version, 'approved', null, null, now(), v_viewer, 'viewer');
    raise exception 'assertion failed: expected insufficient_authority for viewer deciding';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- MFA freshness: a stale reauth timestamp is rejected (checked before the
  -- self-approval/authority checks even run).
  begin
    perform app.decide_vendor_bank_account_approval(v_account.id, v_account.record_version, 'approved', null, null, now() - interval '10 minutes', v_approver, 'approver');
    raise exception 'assertion failed: expected reauth_required for a stale reauth timestamp';
  exception
    when others then
      if sqlerrm not like 'reauth_required%' then raise; end if;
  end;
  -- a missing reauth timestamp is rejected too.
  begin
    perform app.decide_vendor_bank_account_approval(v_account.id, v_account.record_version, 'approved', null, null, null, v_approver, 'approver');
    raise exception 'assertion failed: expected reauth_required for a null reauth timestamp';
  exception
    when others then
      if sqlerrm not like 'reauth_required%' then raise; end if;
  end;

  -- self-approval blocked: the maker (staff) cannot also be the checker, even with a
  -- fresh reauth timestamp and (hypothetically) the right authority.
  begin
    perform app.decide_vendor_bank_account_approval(v_account.id, v_account.record_version, 'approved', null, null, now(), v_staff, 'staff');
    raise exception 'assertion failed: expected self_approval_not_allowed for the maker deciding their own proposal';
  exception
    when others then
      if sqlerrm not like 'self_approval_not_allowed%' then raise; end if;
  end;

  -- a genuinely different, Approve-holding actor with a fresh reauth succeeds.
  v_account := app.decide_vendor_bank_account_approval(v_account.id, v_account.record_version, 'approved', null, null, now(), v_approver, 'approver');
  if v_account.status <> 'active' or v_account.approved_by_auth_user_id <> v_approver or v_account.reauth_confirmed_at is null then
    raise exception 'assertion failed: expected active with approved_by_auth_user_id=approver and a recorded reauth_confirmed_at, got status=%', v_account.status;
  end if;

  -- masked read: PRC:View caller sees last4/status/currency, never plaintext/ciphertext.
  select * into v_masked from app.get_vendor_bank_account_masked(v_account.id, v_viewer);
  if v_masked.account_number_last4 <> '0123' or v_masked.status <> 'active' or v_masked.currency <> 'IDR' then
    raise exception 'assertion failed: masked read did not return expected last4/status/currency';
  end if;

  -- raw-SQL column-grant defense in depth: a plain authenticated role (even the
  -- viewer, same tenant) cannot SELECT the encrypted/hash columns directly.
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000092106", "role": "authenticated"}', true);
  begin
    perform account_number_encrypted from app.vendor_bank_accounts where id = v_account.id;
    raise exception 'assertion failed: expected a real Postgres permission-denied error selecting account_number_encrypted directly';
  exception
    when insufficient_privilege then null; -- expected
  end;
  begin
    perform account_number_hash from app.vendor_bank_accounts where id = v_account.id;
    raise exception 'assertion failed: expected a real Postgres permission-denied error selecting account_number_hash directly';
  exception
    when insufficient_privilege then null; -- expected
  end;
  -- but the non-secret columns ARE selectable directly (RLS-scoped, same tenant).
  if (select account_number_last4 from app.vendor_bank_accounts where id = v_account.id) <> '0123' then
    raise exception 'assertion failed: expected direct SELECT of account_number_last4 to succeed for a same-tenant authenticated caller';
  end if;
  reset role;
  -- request.jwt.claims is transaction-local (is_local=true) and survives `reset role`
  -- on its own -- explicitly clear it too, otherwise the RPC calls below (which pass
  -- their OWN p_actor_auth_user_id, e.g. v_pdv) would trip
  -- app.assert_actor_is_session_identity's cross-check against the now-stale viewer
  -- session identity still set above.
  perform set_config('request.jwt.claims', '{}', true);

  -- reveal: requires PRC:View personal data (viewer lacks it).
  begin
    perform app.reveal_vendor_bank_account_number(v_account.id, 'invoice matching', now(), v_viewer, 'viewer');
    raise exception 'assertion failed: expected insufficient_authority for a viewer revealing';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
  -- requires a non-empty reveal reason.
  begin
    perform app.reveal_vendor_bank_account_number(v_account.id, '', now(), v_pdv, 'pdv');
    raise exception 'assertion failed: expected reveal_reason_required for an empty reason';
  exception
    when others then
      if sqlerrm not like 'reveal_reason_required%' then raise; end if;
  end;
  -- requires MFA freshness too.
  begin
    perform app.reveal_vendor_bank_account_number(v_account.id, 'invoice matching', now() - interval '10 minutes', v_pdv, 'pdv');
    raise exception 'assertion failed: expected reauth_required for a stale reveal reauth timestamp';
  exception
    when others then
      if sqlerrm not like 'reauth_required%' then raise; end if;
  end;

  select * into v_revealed from app.reveal_vendor_bank_account_number(v_account.id, 'invoice matching verification', now(), v_pdv, 'pdv');
  if v_revealed.account_number <> '1234567890123' then
    raise exception 'assertion failed: expected the real decrypted account number back, got %', v_revealed.account_number;
  end if;

  -- the reveal is unconditionally audited, and the audit row NEVER carries the
  -- plaintext or the ciphertext -- only last4 and the reveal reason. Note the audit
  -- payload's own JSONB key is 'account_last4', not 'account_number_last4' -- the
  -- latter would trip app.redact_audit_payload's pre-existing key-name regex (which
  -- matches the substring "account_number") and silently become "[REDACTED]" instead
  -- of the real last4 value (migration design note 9's own disclosed finding).
  select count(*) into v_audit_count from app.audit_logs
  where action = 'reveal_vendor_bank_account_number' and resource_id = v_account.id and actor_auth_user_id = v_pdv
    and after_value->>'account_last4' = '0123' and after_value->>'reveal_reason' = 'invoice matching verification'
    and after_value::text not like '%1234567890123%';
  if v_audit_count <> 1 then
    raise exception 'assertion failed: expected exactly one masked, plaintext-free audit row for the reveal, found %', v_audit_count;
  end if;
end $$;

\echo '>> bank account: structural active-scope guard (a second, independent active account for the same vendor/purpose/currency is rejected unless it supersedes the existing one); supersede-on-approve deactivates the prior active row and carries the family id forward; hold/reactivate/deactivate lifecycle'
do $$
declare
  v_vendor_id uuid := (select master_record_id from app.vendor_profiles where legal_name = 'PT Pfin Trucking');
  v_staff uuid := '00000000-0000-0000-0000-000000092102';
  v_approver uuid := '00000000-0000-0000-0000-000000092103';
  v_manager uuid := '00000000-0000-0000-0000-000000092104';
  v_manager2 uuid := '00000000-0000-0000-0000-000000092108';
  v_original app.vendor_bank_accounts;
  v_second app.vendor_bank_accounts;
  v_reloaded app.vendor_bank_accounts;
  v_wrong_currency app.vendor_bank_accounts;
begin
  select * into v_original from app.vendor_bank_accounts where vendor_master_record_id = v_vendor_id and purpose = 'primary' and currency = 'IDR' and status = 'active';

  -- an independent second draft for the identical vendor/purpose/currency scope,
  -- approved WITHOUT supersedes_account_id, is rejected -- the account_family_id it
  -- was minted with is brand new (unrelated to v_original's), so only the defensive
  -- scope-tuple unique index can (and does) fire.
  v_second := app.create_vendor_bank_account_draft(v_vendor_id, 'Contoso Trucking', 'Bank BCA', '5555666677778', 'IDR', 'primary', null, null, 'idem-pfin-acct-2', v_staff, 'staff');
  v_second := app.submit_vendor_bank_account_for_approval(v_second.id, v_second.record_version, v_staff, 'staff');
  begin
    perform app.decide_vendor_bank_account_approval(v_second.id, v_second.record_version, 'approved', null, null, now(), v_approver, 'approver');
    raise exception 'assertion failed: expected active_account_exists for an independent second active account at the same scope';
  exception
    when others then
      if sqlerrm not like 'active_account_exists%' then raise; end if;
  end;

  -- approving it AS a supersede of the original succeeds, deactivates the original,
  -- and carries the original's account_family_id forward onto the new row.
  select * into v_second from app.vendor_bank_accounts where id = v_second.id;
  v_second := app.decide_vendor_bank_account_approval(v_second.id, v_second.record_version, 'approved', v_original.id, null, now(), v_approver, 'approver');
  if v_second.status <> 'active' or v_second.account_family_id <> v_original.account_family_id then
    raise exception 'assertion failed: expected the superseding account active with the ORIGINAL family id carried forward, got status=% family=%', v_second.status, v_second.account_family_id;
  end if;
  select * into v_reloaded from app.vendor_bank_accounts where id = v_original.id;
  if v_reloaded.status <> 'deactivated' or v_reloaded.deactivation_reason is null then
    raise exception 'assertion failed: expected the original account deactivated with a reason, got status=%', v_reloaded.status;
  end if;

  -- security-rls Finding 2 fix: a different-CURRENCY active account for the same
  -- vendor/purpose is rejected as an invalid supersede target, not silently
  -- deactivated -- the active-scope tuple this mechanism services is vendor+purpose+
  -- currency (all three), not just vendor+purpose.
  v_wrong_currency := app.create_vendor_bank_account_draft(v_vendor_id, 'Contoso Trucking', 'Bank BCA', '9999000011112', 'USD', 'settlement', null, null, 'idem-pfin-acct-wrong-ccy', v_staff, 'staff');
  v_wrong_currency := app.submit_vendor_bank_account_for_approval(v_wrong_currency.id, v_wrong_currency.record_version, v_staff, 'staff');
  begin
    perform app.decide_vendor_bank_account_approval(v_wrong_currency.id, v_wrong_currency.record_version, 'approved', v_second.id, null, now(), v_approver, 'approver');
    raise exception 'assertion failed: expected invalid_supersede for a currency-mismatched supersede target (IDR account superseded by a USD proposal)';
  exception
    when others then
      if sqlerrm not like 'invalid_supersede%' then raise; end if;
  end;
  select * into v_reloaded from app.vendor_bank_accounts where id = v_second.id;
  if v_reloaded.status <> 'active' then
    raise exception 'assertion failed: the rejected cross-currency supersede must NOT have deactivated the unrelated active account, got status=%', v_reloaded.status;
  end if;

  -- hold requires a non-empty reason, a fresh reauth timestamp, and PRC:Override
  -- (staff lacks it) -- spec-compliance fix: hold/reactivate/deactivate now carry
  -- the same MFA reauth freshness requirement as decide/reveal.
  begin
    perform app.hold_vendor_bank_account(v_second.id, v_second.record_version, '', now(), v_manager, 'manager');
    raise exception 'assertion failed: expected reason_required for an empty hold reason';
  exception
    when others then
      if sqlerrm not like 'reason_required%' then raise; end if;
  end;
  begin
    perform app.hold_vendor_bank_account(v_second.id, v_second.record_version, 'suspected fraud pattern', now() - interval '10 minutes', v_manager, 'manager');
    raise exception 'assertion failed: expected reauth_required for a stale hold reauth timestamp';
  exception
    when others then
      if sqlerrm not like 'reauth_required%' then raise; end if;
  end;
  begin
    perform app.hold_vendor_bank_account(v_second.id, v_second.record_version, 'suspected fraud pattern', now(), v_staff, 'staff');
    raise exception 'assertion failed: expected insufficient_authority for staff (no Override) placing a hold';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
  v_second := app.hold_vendor_bank_account(v_second.id, v_second.record_version, 'suspected fraud pattern', now(), v_manager, 'manager');
  if v_second.status <> 'hold' or v_second.hold_reason <> 'suspected fraud pattern' then
    raise exception 'assertion failed: expected hold with the recorded reason, got status=%', v_second.status;
  end if;

  -- reactivate blocks the SAME actor who placed the hold (self_reactivation_not_allowed) --
  -- a single Override holder must not unilaterally place a hold and immediately undo it.
  begin
    perform app.reactivate_vendor_bank_account(v_second.id, v_second.record_version, now(), v_manager, 'manager');
    raise exception 'assertion failed: expected self_reactivation_not_allowed for the same actor who placed the hold';
  exception
    when others then
      if sqlerrm not like 'self_reactivation_not_allowed%' then raise; end if;
  end;
  -- reactivate also requires a fresh reauth timestamp, even for a genuinely different actor.
  begin
    perform app.reactivate_vendor_bank_account(v_second.id, v_second.record_version, null, v_manager2, 'manager2');
    raise exception 'assertion failed: expected reauth_required for a missing reactivate reauth timestamp';
  exception
    when others then
      if sqlerrm not like 'reauth_required%' then raise; end if;
  end;
  v_second := app.reactivate_vendor_bank_account(v_second.id, v_second.record_version, now(), v_manager2, 'manager2');
  if v_second.status <> 'active' or v_second.hold_reason is not null then
    raise exception 'assertion failed: expected reactivated to active with hold_reason cleared, got status=% hold_reason=%', v_second.status, v_second.hold_reason;
  end if;

  begin
    perform app.deactivate_vendor_bank_account(v_second.id, v_second.record_version, '', now(), v_manager, 'manager');
    raise exception 'assertion failed: expected reason_required for an empty deactivation reason';
  exception
    when others then
      if sqlerrm not like 'reason_required%' then raise; end if;
  end;
  v_second := app.deactivate_vendor_bank_account(v_second.id, v_second.record_version, 'vendor offboarded', now(), v_manager, 'manager');
  if v_second.status <> 'deactivated' then
    raise exception 'assertion failed: expected deactivated, got %', v_second.status;
  end if;
  -- deactivating an already-deactivated account is rejected.
  begin
    perform app.deactivate_vendor_bank_account(v_second.id, v_second.record_version, 'again', now(), v_manager, 'manager');
    raise exception 'assertion failed: expected invalid_transition deactivating an already-deactivated account';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;
end $$;

\echo '>> bank account: duplicate-hash detection across two different vendors, WITHOUT decryption'
do $$
declare
  v_vendor1_id uuid := (select master_record_id from app.vendor_profiles where legal_name = 'PT Pfin Trucking');
  v_vendor2_id uuid := (select master_record_id from app.vendor_profiles where legal_name = 'PT Pfin Duplicate Test');
  v_staff uuid := '00000000-0000-0000-0000-000000092102';
  v_approver uuid := '00000000-0000-0000-0000-000000092103';
  v_viewer uuid := '00000000-0000-0000-0000-000000092106';
  v_shared_number text := '7777888899990';
  v_acct1 app.vendor_bank_accounts;
  v_acct2 app.vendor_bank_accounts;
  v_masked1 record;
  v_masked2 record;
begin
  v_acct1 := app.create_vendor_bank_account_draft(v_vendor1_id, 'Contoso Trucking', 'Bank BRI', v_shared_number, 'IDR', 'settlement', null, null, 'idem-pfin-dup-1', v_staff, 'staff');
  v_acct1 := app.submit_vendor_bank_account_for_approval(v_acct1.id, v_acct1.record_version, v_staff, 'staff');
  v_acct1 := app.decide_vendor_bank_account_approval(v_acct1.id, v_acct1.record_version, 'approved', null, null, now(), v_approver, 'approver');

  -- v_acct2 is submitted (pending_approval) rather than left draft -- the
  -- is_duplicate_candidate flag only counts active/pending_approval rows (design
  -- note 2), matching the same fixture discipline applied to the tax-identity
  -- duplicate-hash test below.
  v_acct2 := app.create_vendor_bank_account_draft(v_vendor2_id, 'Contoso Duplicate Test', 'Bank BRI', v_shared_number, 'IDR', 'primary', null, null, 'idem-pfin-dup-2', v_staff, 'staff');
  v_acct2 := app.submit_vendor_bank_account_for_approval(v_acct2.id, v_acct2.record_version, v_staff, 'staff');

  select * into v_masked1 from app.get_vendor_bank_account_masked(v_acct1.id, v_viewer);
  select * into v_masked2 from app.get_vendor_bank_account_masked(v_acct2.id, v_viewer);
  if not v_masked1.is_duplicate_candidate or not v_masked2.is_duplicate_candidate then
    raise exception 'assertion failed: expected both accounts sharing the same account number (different vendors) flagged is_duplicate_candidate=true, got %/%', v_masked1.is_duplicate_candidate, v_masked2.is_duplicate_candidate;
  end if;

  -- the SAME vendor's own prior account sharing a hash is never flagged as a
  -- cross-vendor duplicate (the flag excludes d.vendor_master_record_id = a.vendor_master_record_id).
  if exists (
    select 1 from app.get_vendor_bank_account_masked(v_acct1.id, v_viewer) m
    where m.is_duplicate_candidate and m.vendor_master_record_id = v_acct1.vendor_master_record_id
      and not exists (select 1 from app.vendor_bank_accounts d where d.account_number_hash = (select account_number_hash from app.vendor_bank_accounts where id = v_acct1.id) and d.vendor_master_record_id <> v_acct1.vendor_master_record_id)
  ) then
    raise exception 'assertion failed: unexpected duplicate flag with no cross-vendor match';
  end if;
end $$;

\echo '>> bank account: cross-tenant isolation and RLS default-deny for a customer_user-layer principal'
do $$
declare
  v_vendor_id uuid := (select master_record_id from app.vendor_profiles where legal_name = 'PT Pfin Trucking');
  v_t2_staff uuid := '00000000-0000-0000-0000-000000092202';
  v_account app.vendor_bank_accounts;
  v_row_count integer;
begin
  select * into v_account from app.vendor_bank_accounts where vendor_master_record_id = v_vendor_id and status = 'active' limit 1;

  -- RPC-level: a pfin2 staff member cannot act on a pfin1 vendor's own bank account.
  begin
    perform app.create_vendor_bank_account_draft(v_vendor_id, 'Foreign Attempt', 'Foreign Bank', '1111222233334', 'IDR', 'primary', null, null, 'idem-pfin-crosstenant-reuse', v_t2_staff, 'staff2');
    raise exception 'assertion failed: expected insufficient_authority for a foreign-tenant staff member';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
  -- reused-real-idempotency-key attack: same key as an existing tenant1 row, from a
  -- tenant2 actor -- must still fail on authority, never silently reuse tenant1's row.
  begin
    perform app.create_vendor_bank_account_draft(v_vendor_id, 'Foreign Attempt', 'Foreign Bank', '1111222233334', 'IDR', 'primary', null, null, 'idem-pfin-acct-1', v_t2_staff, 'staff2');
    raise exception 'assertion failed: expected insufficient_authority for a foreign-tenant staff member reusing a real idempotency key';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- raw-RLS-level: a pfin2 staff session sees ZERO rows on app.vendor_bank_accounts,
  -- even by primary key.
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000092202", "role": "authenticated"}', true);
  select count(*) into v_row_count from app.vendor_bank_accounts where id = v_account.id;
  if v_row_count <> 0 then
    raise exception 'assertion failed: expected zero rows visible to a foreign-tenant principal under RLS, got %', v_row_count;
  end if;
  reset role;

  -- RLS default-deny for a customer_user-layer principal within the OWNING tenant.
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000092107", "role": "authenticated"}', true);
  select count(*) into v_row_count from app.vendor_bank_accounts;
  if v_row_count <> 0 then
    raise exception 'assertion failed: expected zero rows visible to a customer_user-layer principal, got %', v_row_count;
  end if;
  select count(*) into v_row_count from app.vendor_tax_identities;
  if v_row_count <> 0 then
    raise exception 'assertion failed: expected zero rows visible to a customer_user-layer principal on vendor_tax_identities, got %', v_row_count;
  end if;
  reset role;
end $$;

\echo '>> bank account evidence: unsafe/pending scan, cross-tenant, wrong-record-type all rejected on create; a clean, correctly-scoped file is accepted; the evidence-access RPC is authority-gated and audited'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pfin1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'pfin2');
  v_vendor_id uuid := (select master_record_id from app.vendor_profiles where legal_name = 'PT Pfin Trucking');
  v_staff uuid := '00000000-0000-0000-0000-000000092102';
  v_t2_staff uuid := '00000000-0000-0000-0000-000000092202';
  v_viewer uuid := '00000000-0000-0000-0000-000000092106';
  v_pending_file app.files;
  v_foreign_file app.files;
  v_wrong_record_file app.files;
  v_clean_file app.files;
  v_account app.vendor_bank_accounts;
  v_access record;
begin
  v_pending_file := app.initiate_file_upload(
    v_tenant1, 'vendor_financial_verification_document', 'vendor_financial_verification', v_vendor_id,
    'bank-letter.pdf', 'application/pdf', 51200, 'confidential', false, null, null, null,
    'idem-pfin-evidence-pending', v_staff, 'staff'
  );
  begin
    perform app.create_vendor_bank_account_draft(v_vendor_id, 'Contoso Trucking', 'Bank Danamon', '2223334445556', 'IDR', 'other', null, v_pending_file.id, 'idem-pfin-evidence-doc-1', v_staff, 'staff');
    raise exception 'assertion failed: expected financial_unsafe_evidence for a still-pending-scan file';
  exception
    when others then
      if sqlerrm not like 'financial_unsafe_evidence%' then raise; end if;
  end;

  v_foreign_file := app.initiate_file_upload(
    v_tenant2, 'vendor_financial_verification_document', 'vendor_financial_verification', gen_random_uuid(),
    'unrelated-pfin2-file.pdf', 'application/pdf', 1024, 'confidential', false, null, null, null,
    'idem-pfin2-foreign-evidence', v_t2_staff, 'staff2'
  );
  perform app.record_file_scan_result(v_foreign_file.id, 'clean', 'test-scanner-ref', v_t2_staff, 'staff2');
  begin
    perform app.create_vendor_bank_account_draft(v_vendor_id, 'Contoso Trucking', 'Bank Danamon', '2223334445556', 'IDR', 'other', null, v_foreign_file.id, 'idem-pfin-evidence-doc-2', v_staff, 'staff');
    raise exception 'assertion failed: expected financial_evidence_file_mismatch for a cross-tenant file';
  exception
    when others then
      if sqlerrm not like 'financial_evidence_file_mismatch%' then raise; end if;
  end;

  v_wrong_record_file := app.initiate_file_upload(
    v_tenant1, 'vendor_financial_verification_document', 'vendor_profile', v_vendor_id,
    'wrong-record-type.pdf', 'application/pdf', 1024, 'confidential', false, null, null, null,
    'idem-pfin-wrongrecord-evidence', v_staff, 'staff'
  );
  perform app.record_file_scan_result(v_wrong_record_file.id, 'clean', 'test-scanner-ref', v_staff, 'staff');
  begin
    perform app.create_vendor_bank_account_draft(v_vendor_id, 'Contoso Trucking', 'Bank Danamon', '2223334445556', 'IDR', 'other', null, v_wrong_record_file.id, 'idem-pfin-evidence-doc-3', v_staff, 'staff');
    raise exception 'assertion failed: expected financial_evidence_file_mismatch for a wrong record_type file';
  exception
    when others then
      if sqlerrm not like 'financial_evidence_file_mismatch%' then raise; end if;
  end;

  v_clean_file := app.initiate_file_upload(
    v_tenant1, 'vendor_financial_verification_document', 'vendor_financial_verification', v_vendor_id,
    'bank-letter-clean.pdf', 'application/pdf', 51200, 'confidential', false, null, null, null,
    'idem-pfin-evidence-clean', v_staff, 'staff'
  );
  perform app.record_file_scan_result(v_clean_file.id, 'clean', 'test-scanner-ref', v_staff, 'staff');
  v_account := app.create_vendor_bank_account_draft(v_vendor_id, 'Contoso Trucking', 'Bank Danamon', '2223334445556', 'IDR', 'other', null, v_clean_file.id, 'idem-pfin-evidence-doc-4', v_staff, 'staff');
  if v_account.evidence_file_id <> v_clean_file.id then
    raise exception 'assertion failed: expected the clean evidence file attached';
  end if;

  -- evidence access: viewer lacks PRC:Download. security-rls Finding 1 fix -- this
  -- RPC no longer RAISES for an authority denial (a raised exception would roll back
  -- its own audit insert); it returns a 'denied' row instead, with file_id nulled out
  -- so the denial itself never reveals whether evidence is attached, and the denial
  -- IS captured in app.audit_logs (unlike an un-auditable raise would have been).
  select * into v_access from app.access_vendor_bank_account_evidence(v_account.id, 'metadata_view', v_viewer, 'viewer');
  if v_access.access_result <> 'denied' or v_access.access_reason not like 'insufficient_authority%' or v_access.file_id is not null then
    raise exception 'assertion failed: expected a denied, file_id-nulled result for a viewer lacking PRC:Download, got result=% reason=% file_id=%', v_access.access_result, v_access.access_reason, v_access.file_id;
  end if;
  if not exists (
    select 1 from app.audit_logs
    where action = 'access_vendor_bank_account_evidence' and resource_id = v_account.id and result = 'failure'
      and after_value ->> 'gate' = 'insufficient_authority'
  ) then
    raise exception 'assertion failed: expected the authority-denied evidence access to be captured in app.audit_logs -- this is the exact probing scenario security-rls Finding 1 requires an audit trail for';
  end if;
  select * into v_access from app.access_vendor_bank_account_evidence(v_account.id, 'metadata_view', v_staff, 'staff');
  if v_access.access_result <> 'granted' or v_access.original_filename <> 'bank-letter-clean.pdf' then
    raise exception 'assertion failed: expected a granted evidence access with the real filename, got result=% filename=%', v_access.access_result, v_access.original_filename;
  end if;
  if not exists (select 1 from app.audit_logs where action = 'access_vendor_bank_account_evidence' and resource_id = v_account.id and result = 'success') then
    raise exception 'assertion failed: expected the evidence access to be captured in app.audit_logs';
  end if;

  -- HDN-377 (Storage and Signed URL Audit) regression: the SECOND denial branch --
  -- PRC:Download authority passes, but app.authorize_file_access itself denies
  -- (malware/record-access/classification) -- previously left file_id unmasked,
  -- contradicting this RPC's own "denial nulls out every file-identifying field"
  -- contract asserted for the authority-denial branch above. Live-forced via the
  -- content-gate branch (infected file), the same shape the compliance-evidence
  -- sibling's own existing regression exercises.
  update app.files set malware_scan_status = 'infected' where id = v_clean_file.id;
  select * into v_access from app.access_vendor_bank_account_evidence(v_account.id, 'download', v_staff, 'staff');
  if v_access.access_result <> 'denied' or v_access.file_id is not null then
    raise exception 'assertion failed: expected file_id nulled out on the content-gate denial branch too, got result=% file_id=%', v_access.access_result, v_access.file_id;
  end if;
  update app.files set malware_scan_status = 'clean' where id = v_clean_file.id;
end $$;

\echo '>> tax identity lifecycle: create/update/submit/decide (self-approval + MFA blocked), masked read, reveal (audited, plaintext never in the audit row), duplicate-hash detection, hold/deactivate'
do $$
declare
  v_vendor_id uuid := (select master_record_id from app.vendor_profiles where legal_name = 'PT Pfin Trucking');
  v_vendor2_id uuid := (select master_record_id from app.vendor_profiles where legal_name = 'PT Pfin Duplicate Test');
  v_staff uuid := '00000000-0000-0000-0000-000000092102';
  v_approver uuid := '00000000-0000-0000-0000-000000092103';
  v_manager uuid := '00000000-0000-0000-0000-000000092104';
  v_manager2 uuid := '00000000-0000-0000-0000-000000092108';
  v_pdv uuid := '00000000-0000-0000-0000-000000092105';
  v_viewer uuid := '00000000-0000-0000-0000-000000092106';
  v_tax app.vendor_tax_identities;
  v_tax2 app.vendor_tax_identities;
  v_masked record;
  v_masked2 record;
  v_revealed record;
  v_audit_count integer;
begin
  v_tax := app.create_vendor_tax_identity_draft(v_vendor_id, 'NPWP', '01.234.567.8-901.000', 'PT Pfin Trucking', null, null, 'idem-pfin-tax-1', v_staff, 'staff');
  if v_tax.status <> 'draft' or v_tax.tax_id_last4 <> '.000' then
    raise exception 'assertion failed: expected draft tax identity with last4=.000, got status=% last4=%', v_tax.status, v_tax.tax_id_last4;
  end if;

  -- idempotency-key replay returns the same row; correctness-concurrency fix:
  -- effective_from is now also load-bearing in the comparison (mirrors the
  -- bank-account draft's own coverage above).
  if (app.create_vendor_tax_identity_draft(v_vendor_id, 'NPWP', '01.234.567.8-901.000', 'PT Pfin Trucking', null, null, 'idem-pfin-tax-1', v_staff, 'staff')).id <> v_tax.id then
    raise exception 'assertion failed: expected idempotency replay to return the exact same tax identity row';
  end if;
  begin
    perform app.create_vendor_tax_identity_draft(v_vendor_id, 'NPWP', '01.234.567.8-901.000', 'PT Pfin Trucking', current_date + 30, null, 'idem-pfin-tax-1', v_staff, 'staff');
    raise exception 'assertion failed: expected idempotency_key_conflict for a reused tax identity key with a different effective_from';
  exception
    when others then
      if sqlerrm not like 'idempotency_key_conflict%' then raise; end if;
  end;

  v_tax := app.update_vendor_tax_identity_draft(v_tax.id, v_tax.record_version, 'NPWP', '01.234.567.8-901.000', 'PT Pfin Trucking (Legal)', null, null, v_staff, 'staff');
  v_tax := app.submit_vendor_tax_identity_for_approval(v_tax.id, v_tax.record_version, v_staff, 'staff');

  begin
    perform app.decide_vendor_tax_identity_approval(v_tax.id, v_tax.record_version, 'approved', null, null, now(), v_staff, 'staff');
    raise exception 'assertion failed: expected self_approval_not_allowed for the maker deciding their own tax identity proposal';
  exception
    when others then
      if sqlerrm not like 'self_approval_not_allowed%' then raise; end if;
  end;
  begin
    perform app.decide_vendor_tax_identity_approval(v_tax.id, v_tax.record_version, 'approved', null, null, now() - interval '1 hour', v_approver, 'approver');
    raise exception 'assertion failed: expected reauth_required for a stale reauth timestamp';
  exception
    when others then
      if sqlerrm not like 'reauth_required%' then raise; end if;
  end;

  v_tax := app.decide_vendor_tax_identity_approval(v_tax.id, v_tax.record_version, 'approved', null, null, now(), v_approver, 'approver');
  if v_tax.status <> 'active' then
    raise exception 'assertion failed: expected active tax identity, got %', v_tax.status;
  end if;

  select * into v_masked from app.get_vendor_tax_identity_masked(v_tax.id, v_viewer);
  if v_masked.tax_id_last4 <> '.000' or v_masked.status <> 'active' then
    raise exception 'assertion failed: masked tax identity read did not return expected last4/status';
  end if;

  -- reveal: view-only lacks PRC:View personal data.
  begin
    perform app.reveal_vendor_tax_identity_number(v_tax.id, 'tax audit prep', now(), v_viewer, 'viewer');
    raise exception 'assertion failed: expected insufficient_authority for a viewer revealing a tax identity';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
  select * into v_revealed from app.reveal_vendor_tax_identity_number(v_tax.id, 'annual tax audit prep', now(), v_pdv, 'pdv');
  if v_revealed.tax_id <> '01.234.567.8-901.000' then
    raise exception 'assertion failed: expected the real decrypted tax id back, got %', v_revealed.tax_id;
  end if;
  select count(*) into v_audit_count from app.audit_logs
  where action = 'reveal_vendor_tax_identity_number' and resource_id = v_tax.id and actor_auth_user_id = v_pdv
    and after_value->>'tax_id_last4' = '.000' and after_value::text not like '%01.234.567.8-901.000%';
  if v_audit_count <> 1 then
    raise exception 'assertion failed: expected exactly one masked, plaintext-free audit row for the tax identity reveal, found %', v_audit_count;
  end if;

  -- duplicate-hash detection across two different vendors sharing the same tax id.
  -- v_tax2 is submitted (pending_approval) rather than left draft -- the
  -- is_duplicate_candidate flag only counts active/pending_approval rows, and this
  -- same pending_approval row is what the next test block below approves as v_original.
  v_tax2 := app.create_vendor_tax_identity_draft(v_vendor2_id, 'NPWP', '01.234.567.8-901.000', 'PT Pfin Duplicate Test', null, null, 'idem-pfin-tax-2', v_staff, 'staff');
  v_tax2 := app.submit_vendor_tax_identity_for_approval(v_tax2.id, v_tax2.record_version, v_staff, 'staff');
  select * into v_masked from app.get_vendor_tax_identity_masked(v_tax.id, v_viewer);
  select * into v_masked2 from app.get_vendor_tax_identity_masked(v_tax2.id, v_viewer);
  if not v_masked.is_duplicate_candidate or not v_masked2.is_duplicate_candidate then
    raise exception 'assertion failed: expected both tax identities sharing the same tax id (different vendors) flagged is_duplicate_candidate=true';
  end if;

  -- hold/deactivate lifecycle (Override-gated, reasons required, fresh reauth
  -- required, reactivate blocked for the same actor who placed the hold).
  v_tax := app.hold_vendor_tax_identity(v_tax.id, v_tax.record_version, 'pending legal name discrepancy review', now(), v_manager, 'manager');
  if v_tax.status <> 'hold' then
    raise exception 'assertion failed: expected hold, got %', v_tax.status;
  end if;
  begin
    perform app.reactivate_vendor_tax_identity(v_tax.id, v_tax.record_version, now(), v_manager, 'manager');
    raise exception 'assertion failed: expected self_reactivation_not_allowed for the same actor who placed the hold';
  exception
    when others then
      if sqlerrm not like 'self_reactivation_not_allowed%' then raise; end if;
  end;
  v_tax := app.reactivate_vendor_tax_identity(v_tax.id, v_tax.record_version, now(), v_manager2, 'manager2');
  if v_tax.status <> 'active' then
    raise exception 'assertion failed: expected reactivated to active, got %', v_tax.status;
  end if;
  v_tax := app.deactivate_vendor_tax_identity(v_tax.id, v_tax.record_version, 'vendor tax identity retired', now(), v_manager, 'manager');
  if v_tax.status <> 'deactivated' then
    raise exception 'assertion failed: expected deactivated, got %', v_tax.status;
  end if;
end $$;

\echo '>> tax identity: structural active-scope guard and supersede-on-approve carrying tax_family_id forward'
do $$
declare
  v_vendor_id uuid := (select master_record_id from app.vendor_profiles where legal_name = 'PT Pfin Duplicate Test');
  v_staff uuid := '00000000-0000-0000-0000-000000092102';
  v_approver uuid := '00000000-0000-0000-0000-000000092103';
  v_original app.vendor_tax_identities;
  v_second app.vendor_tax_identities;
  v_reloaded app.vendor_tax_identities;
begin
  select * into v_original from app.vendor_tax_identities where vendor_master_record_id = v_vendor_id and tax_id_type = 'NPWP' and status = 'pending_approval';
  v_original := app.decide_vendor_tax_identity_approval(v_original.id, v_original.record_version, 'approved', null, null, now(), v_approver, 'approver');

  v_second := app.create_vendor_tax_identity_draft(v_vendor_id, 'NPWP', '09.876.543.2-109.000', 'PT Pfin Duplicate Test (Corrected)', null, null, 'idem-pfin-tax-3', v_staff, 'staff');
  v_second := app.submit_vendor_tax_identity_for_approval(v_second.id, v_second.record_version, v_staff, 'staff');
  begin
    perform app.decide_vendor_tax_identity_approval(v_second.id, v_second.record_version, 'approved', null, null, now(), v_approver, 'approver');
    raise exception 'assertion failed: expected active_tax_identity_exists for an independent second active tax identity of the same type';
  exception
    when others then
      if sqlerrm not like 'active_tax_identity_exists%' then raise; end if;
  end;

  select * into v_second from app.vendor_tax_identities where id = v_second.id;
  v_second := app.decide_vendor_tax_identity_approval(v_second.id, v_second.record_version, 'approved', v_original.id, null, now(), v_approver, 'approver');
  if v_second.status <> 'active' or v_second.tax_family_id <> v_original.tax_family_id then
    raise exception 'assertion failed: expected the superseding tax identity active with the ORIGINAL family id carried forward';
  end if;
  select * into v_reloaded from app.vendor_tax_identities where id = v_original.id;
  if v_reloaded.status <> 'deactivated' then
    raise exception 'assertion failed: expected the original tax identity deactivated, got %', v_reloaded.status;
  end if;
end $$;

\echo '>> record_version stale-version rejection on the post-UPDATE re-check (a genuine two-call race, not merely a stale caller-supplied number)'
do $$
declare
  v_vendor_id uuid := (select master_record_id from app.vendor_profiles where legal_name = 'PT Pfin Duplicate Test');
  v_staff uuid := '00000000-0000-0000-0000-000000092102';
  v_manager uuid := '00000000-0000-0000-0000-000000092104';
  v_account app.vendor_bank_accounts;
begin
  v_account := app.create_vendor_bank_account_draft(v_vendor_id, 'Contoso Duplicate Test', 'Bank CIMB', '3334445556667', 'IDR', 'primary', null, null, 'idem-pfin-race-1', v_staff, 'staff');
  -- simulate a concurrent winner: bump record_version directly (mirrors the
  -- established "genuine two-call race" test convention used elsewhere in this
  -- repository -- a bare stale-number check alone would not exercise the post-UPDATE
  -- re-check path).
  update app.vendor_bank_accounts set updated_at = now(), record_version = record_version + 1 where id = v_account.id;
  begin
    perform app.update_vendor_bank_account_draft(v_account.id, v_account.record_version, 'Renamed', 'Bank CIMB', '3334445556667', 'IDR', 'primary', null, null, v_staff, 'staff');
    raise exception 'assertion failed: expected stale_version on the post-UPDATE re-check after a concurrent winner';
  exception
    when others then
      if sqlerrm not like 'stale_version%' then raise; end if;
  end;
end $$;

\echo '>> payment-term change proposal/approval: propose -> self-approval blocked -> MFA required -> approve updates app.vendor_profiles.payment_term_days -> pending-unique guard -> no-op rejection -> reject path'
do $$
declare
  v_vendor_id uuid := (select master_record_id from app.vendor_profiles where legal_name = 'PT Pfin Trucking');
  v_staff uuid := '00000000-0000-0000-0000-000000092102';
  v_approver uuid := '00000000-0000-0000-0000-000000092103';
  v_proposal app.vendor_payment_term_proposals;
  v_proposal2 app.vendor_payment_term_proposals;
  v_vendor app.vendor_profiles;
begin
  select * into v_vendor from app.vendor_profiles where master_record_id = v_vendor_id;
  if v_vendor.payment_term_days <> 30 then
    raise exception 'assertion failed: fixture expected payment_term_days=30 before this test, got %', v_vendor.payment_term_days;
  end if;

  -- no-op proposal (identical to the current value) is rejected outright.
  begin
    perform app.propose_vendor_payment_term_change(v_vendor_id, 30, 'no real change', 'idem-pfin-pterm-noop', v_staff, 'staff');
    raise exception 'assertion failed: expected no_op_proposal for a proposal matching the current value';
  exception
    when others then
      if sqlerrm not like 'no_op_proposal%' then raise; end if;
  end;

  v_proposal := app.propose_vendor_payment_term_change(v_vendor_id, 45, 'renegotiated commercial terms', 'idem-pfin-pterm-1', v_staff, 'staff');
  if v_proposal.status <> 'pending_approval' or v_proposal.current_payment_term_days <> 30 then
    raise exception 'assertion failed: expected pending_approval with current_payment_term_days=30 snapshotted, got status=% current=%', v_proposal.status, v_proposal.current_payment_term_days;
  end if;

  -- only one pending proposal per vendor at a time.
  begin
    perform app.propose_vendor_payment_term_change(v_vendor_id, 60, 'a second, competing proposal', 'idem-pfin-pterm-2', v_staff, 'staff');
    raise exception 'assertion failed: expected pending_proposal_exists while one is already pending';
  exception
    when others then
      if sqlerrm not like 'pending_proposal_exists%' then raise; end if;
  end;

  -- self-approval blocked.
  begin
    perform app.decide_vendor_payment_term_change_proposal(v_proposal.id, v_proposal.record_version, 'approved', null, now(), v_staff, 'staff');
    raise exception 'assertion failed: expected self_approval_not_allowed for the maker deciding their own payment-term proposal';
  exception
    when others then
      if sqlerrm not like 'self_approval_not_allowed%' then raise; end if;
  end;
  -- MFA required.
  begin
    perform app.decide_vendor_payment_term_change_proposal(v_proposal.id, v_proposal.record_version, 'approved', null, now() - interval '10 minutes', v_approver, 'approver');
    raise exception 'assertion failed: expected reauth_required for a stale reauth timestamp';
  exception
    when others then
      if sqlerrm not like 'reauth_required%' then raise; end if;
  end;

  v_proposal := app.decide_vendor_payment_term_change_proposal(v_proposal.id, v_proposal.record_version, 'approved', null, now(), v_approver, 'approver');
  if v_proposal.status <> 'approved' then
    raise exception 'assertion failed: expected approved, got %', v_proposal.status;
  end if;
  select * into v_vendor from app.vendor_profiles where master_record_id = v_vendor_id;
  if v_vendor.payment_term_days <> 45 then
    raise exception 'assertion failed: expected app.vendor_profiles.payment_term_days updated to 45, got %', v_vendor.payment_term_days;
  end if;

  -- a fresh proposal, then rejected -- requires a reason and never touches vendor_profiles.
  v_proposal2 := app.propose_vendor_payment_term_change(v_vendor_id, 60, 'exploring a longer term', 'idem-pfin-pterm-3', v_staff, 'staff');
  begin
    perform app.decide_vendor_payment_term_change_proposal(v_proposal2.id, v_proposal2.record_version, 'rejected', '', now(), v_approver, 'approver');
    raise exception 'assertion failed: expected reason_required for an empty rejection reason';
  exception
    when others then
      if sqlerrm not like 'reason_required%' then raise; end if;
  end;
  v_proposal2 := app.decide_vendor_payment_term_change_proposal(v_proposal2.id, v_proposal2.record_version, 'rejected', 'terms already renegotiated this quarter', now(), v_approver, 'approver');
  if v_proposal2.status <> 'rejected' then
    raise exception 'assertion failed: expected rejected, got %', v_proposal2.status;
  end if;
  select * into v_vendor from app.vendor_profiles where master_record_id = v_vendor_id;
  if v_vendor.payment_term_days <> 45 then
    raise exception 'assertion failed: expected payment_term_days unchanged at 45 after a rejection, got %', v_vendor.payment_term_days;
  end if;
end $$;

\echo '>> idempotency-key reused-for-a-different-target rejection on payment-term proposals; downstream verification-status composition (bank+tax active -> true/true, no hold; then hold flips on_hold=true)'
do $$
declare
  v_vendor_id uuid := (select master_record_id from app.vendor_profiles where legal_name = 'PT Pfin Trucking');
  v_staff uuid := '00000000-0000-0000-0000-000000092102';
  v_approver uuid := '00000000-0000-0000-0000-000000092103';
  v_viewer uuid := '00000000-0000-0000-0000-000000092106';
  v_manager uuid := '00000000-0000-0000-0000-000000092104';
  v_manager2 uuid := '00000000-0000-0000-0000-000000092108';
  v_status record;
  v_account app.vendor_bank_accounts;
  v_tax app.vendor_tax_identities;
begin
  -- this vendor's own earlier NPWP tax identity (the "tax identity lifecycle" test
  -- block above) was deliberately driven all the way to 'deactivated' by that test's
  -- own hold/reactivate/deactivate coverage -- a genuinely different, still-ACTIVE
  -- tax identity (a different tax_id_type, its own family) is needed here so the
  -- downstream read's own has_verified_tax_identity=true branch is exercised for
  -- real, not left to accidentally pass against stale state.
  v_tax := app.create_vendor_tax_identity_draft(v_vendor_id, 'BUSINESS_LICENSE', '9988776655443', 'PT Pfin Trucking', null, null, 'idem-pfin-tax-downstream', v_staff, 'staff');
  v_tax := app.submit_vendor_tax_identity_for_approval(v_tax.id, v_tax.record_version, v_staff, 'staff');
  v_tax := app.decide_vendor_tax_identity_approval(v_tax.id, v_tax.record_version, 'approved', null, null, now(), v_approver, 'approver');
  if v_tax.status <> 'active' then
    raise exception 'assertion failed: expected the fresh downstream-test tax identity active, got %', v_tax.status;
  end if;

  -- reused-for-a-different-target: the same idempotency key already used for
  -- idem-pfin-pterm-1 (target = 45 days), replayed for a genuinely different value.
  begin
    perform app.propose_vendor_payment_term_change(v_vendor_id, 90, 'a different value entirely', 'idem-pfin-pterm-1', v_staff, 'staff');
    raise exception 'assertion failed: expected idempotency_key_conflict reusing idem-pfin-pterm-1 for a different proposed_payment_term_days';
  exception
    when others then
      if sqlerrm not like 'idempotency_key_conflict%' then raise; end if;
  end;

  select * into v_status from app.get_vendor_financial_verification_status(v_vendor_id, v_viewer);
  if not v_status.has_verified_bank_account or not v_status.has_verified_tax_identity or v_status.on_hold then
    raise exception 'assertion failed: expected has_verified_bank_account=true, has_verified_tax_identity=true, on_hold=false, got %/%/%', v_status.has_verified_bank_account, v_status.has_verified_tax_identity, v_status.on_hold;
  end if;

  select * into v_account from app.vendor_bank_accounts where vendor_master_record_id = v_vendor_id and status = 'active' order by created_at desc limit 1;
  perform app.hold_vendor_bank_account(v_account.id, v_account.record_version, 'downstream hold test', now(), v_manager, 'manager');

  select * into v_status from app.get_vendor_financial_verification_status(v_vendor_id, v_viewer);
  if not v_status.on_hold then
    raise exception 'assertion failed: expected on_hold=true once the active bank account is placed on hold, got %', v_status.on_hold;
  end if;
  -- has_verified_bank_account correctly flips to false too -- the account is no
  -- longer status='active' (it is 'hold'), which is the literal contract this read
  -- exposes ("verified bank account exists": an on-hold account is not a currently
  -- verified, usable one).
  if v_status.has_verified_bank_account then
    raise exception 'assertion failed: expected has_verified_bank_account=false once the only active account moved to hold';
  end if;

  -- restore for cleanliness (not strictly required, but keeps the fixture's own
  -- final state coherent for anyone reading it later). Reactivate with a DIFFERENT
  -- actor than whoever placed the hold (v_manager2, not v_manager) -- self_reactivation_not_allowed.
  select * into v_account from app.vendor_bank_accounts where id = v_account.id;
  perform app.reactivate_vendor_bank_account(v_account.id, v_account.record_version, now(), v_manager2, 'manager2');
end $$;

\echo '>> Prompt 269 (ISS-2026-054, C-05): app.get_vendor_payment_term_proposal -- a pfin2 actor with zero membership in pfin1 gets the SAME vendor_payment_term_proposal_not_found a genuinely missing id would produce, never insufficient_authority (which would disclose the real tenant_id)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pfin1');
  v_t2_staff uuid := '00000000-0000-0000-0000-000000092202';
  v_target_proposal_id uuid := (select id from app.vendor_payment_term_proposals where tenant_id = v_tenant1 and idempotency_key = 'idem-pfin-pterm-1');
begin
  begin
    perform app.get_vendor_payment_term_proposal(v_target_proposal_id, v_t2_staff);
    raise exception 'assertion failed: expected vendor_payment_term_proposal_not_found for a pfin2 actor reading a pfin1 payment term proposal (never insufficient_authority, which would disclose the real tenant_id)';
  exception
    when others then
      if sqlerrm not like 'vendor_payment_term_proposal_not_found%' then raise; end if;
  end;
end $$;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on every new client-facing function; the private helpers carry no authenticated/service_role/anon grant beyond Postgres'' own implicit owner privilege'
do $$
declare
  v_leaked text;
begin
  select string_agg(p.proname, ', ') into v_leaked
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'app'
    and p.proname in (
      'create_vendor_bank_account_draft', 'update_vendor_bank_account_draft', 'submit_vendor_bank_account_for_approval',
      'decide_vendor_bank_account_approval', 'hold_vendor_bank_account', 'reactivate_vendor_bank_account', 'deactivate_vendor_bank_account',
      'get_vendor_bank_account_masked', 'list_vendor_bank_accounts_masked', 'reveal_vendor_bank_account_number', 'access_vendor_bank_account_evidence',
      'create_vendor_tax_identity_draft', 'update_vendor_tax_identity_draft', 'submit_vendor_tax_identity_for_approval',
      'decide_vendor_tax_identity_approval', 'hold_vendor_tax_identity', 'reactivate_vendor_tax_identity', 'deactivate_vendor_tax_identity',
      'get_vendor_tax_identity_masked', 'list_vendor_tax_identities_masked', 'reveal_vendor_tax_identity_number', 'access_vendor_tax_identity_evidence',
      'propose_vendor_payment_term_change', 'decide_vendor_payment_term_change_proposal', 'get_vendor_payment_term_proposal', 'list_vendor_payment_term_proposals',
      'get_vendor_financial_verification_status'
    )
    and has_function_privilege('anon', p.oid, 'EXECUTE');
  if v_leaked is not null then
    raise exception 'assertion failed: anon must hold zero EXECUTE on any PRC-254 client-facing function, but leaked: %', v_leaked;
  end if;

  select string_agg(p.proname, ', ') into v_leaked
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'app'
    and p.proname in (
      'vendor_financial_encryption_key', '_encrypt_vendor_financial_value', '_decrypt_vendor_financial_value',
      '_hash_vendor_financial_value', '_last4_vendor_financial_value', 'assert_vendor_bank_account_editable', 'assert_vendor_tax_identity_editable'
    )
    and (has_function_privilege('authenticated', p.oid, 'EXECUTE') or has_function_privilege('service_role', p.oid, 'EXECUTE') or has_function_privilege('anon', p.oid, 'EXECUTE'));
  if v_leaked is not null then
    raise exception 'assertion failed: the private encryption/helper functions must carry no authenticated/service_role/anon grant, but leaked: %', v_leaked;
  end if;
end $$;

\echo 'ALL PRC-254 db-test assertions passed.'
