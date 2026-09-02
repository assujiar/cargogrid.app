-- ISS-2026-146 -- cross-tenant tenant_id disclosure via exception message text.
-- Third fix pass, Procurement lane (vendor compliance + vendor financial security).
--
-- Root cause (unchanged since the original disclosure): these SECURITY DEFINER functions
-- look a record up by its own bare `id` (the caller does not yet know which tenant owns
-- it), THEN evaluate the actor's authority against the looked-up row's own real
-- tenant_id, and on denial raise 'insufficient_authority: ... for tenant %', interpolating
-- that real tenant_id -- disclosing it to a caller who has not been shown to have any
-- relationship to that tenant at all.
--
-- Fix (identical to the already-established, already-precedented shape this repository
-- has used for the same defect class in ISS-2026-043/048/054 and in the merged
-- 20260902100000-20260902104000 / 20260902200000-20260902201000 passes): fold
-- `app.has_active_tenant_membership(<row>.tenant_id, p_actor_auth_user_id)` into the SAME
-- not-found branch the row-miss case already raises, reusing that branch's identical
-- generic message and errcode='no_data_found'. A caller with zero relationship to the
-- record's real tenant now gets exactly the error a nonexistent id already produced; only
-- a confirmed member of that tenant (or a Supreme Admin / live support grant, both of
-- which app.has_active_tenant_membership already returns true for) ever reaches the
-- specific, tenant_id-bearing insufficient_authority line below it.
--
-- No authority check is weakened anywhere: every evaluate_permission /
-- check_*_authority call below is byte-identical to its pre-existing body, and a genuine
-- same-tenant member who merely lacks the role authority still gets the same
-- insufficient_authority message with the same insufficient_privilege errcode as before.
-- Only a zero-membership foreigner's outcome changes, and only to a less disclosing one.
--
-- Source of every body below: the CURRENT live definition on disk -- the LAST migration
-- that defines each function (20260730600000_create_procurement_vendor_compliance.sql, 20260730610000_create_procurement_vendor_financial_security.sql) -- copied
-- verbatim, with the single `if not found` line per function changed as described above.
-- Signatures are unchanged throughout, so grants are unaffected.
--
-- This file: 36 functions, 37 at-risk raise sites.

create or replace function app.archive_vendor_compliance_requirement(p_requirement_version_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_compliance_requirements
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_requirement app.vendor_compliance_requirements;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to archive a vendor compliance requirement' using errcode = 'check_violation';
  end if;

  select * into v_requirement from app.vendor_compliance_requirements where id = p_requirement_version_id;
  if not found or not app.has_active_tenant_membership(v_requirement.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_compliance_requirement_not_found: %', p_requirement_version_id using errcode = 'no_data_found';
  end if;
  if v_requirement.record_version <> p_expected_version then
    raise exception 'stale_version: vendor compliance requirement % expected version % but found %', p_requirement_version_id, p_expected_version, v_requirement.record_version
      using errcode = 'serialization_failure';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_requirement.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_requirement.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_requirement.status <> 'published' then
    raise exception 'invalid_transition: vendor compliance requirement % is % and cannot be archived', p_requirement_version_id, v_requirement.status
      using errcode = 'check_violation';
  end if;

  update app.vendor_compliance_requirements
  set status = 'archived', updated_at = now(), record_version = record_version + 1
  where id = p_requirement_version_id and record_version = p_expected_version
  returning * into v_requirement;
  if not found then
    raise exception 'stale_version: vendor compliance requirement % target row was concurrently modified (expected version %)', p_requirement_version_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_requirement.tenant_id, p_actor_auth_user_id, p_actor_label, 'archive_vendor_compliance_requirement',
    'app.vendor_compliance_requirements', v_requirement.id, 'success', p_reason, null, '{}'::jsonb
  );

  return v_requirement;
end;
$$;

create or replace function app.assert_vendor_bank_account_editable(p_account_id uuid, p_actor_auth_user_id uuid, out v_account app.vendor_bank_accounts)
language plpgsql
as $$
declare
  v_decision app.rbac_decision;
begin
  select * into v_account from app.vendor_bank_accounts where id = p_account_id for update;
  if not found or not app.has_active_tenant_membership(v_account.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_bank_account_not_found: %', p_account_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_account.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_account.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_account.status <> 'draft' then
    raise exception 'vendor_bank_account_not_draft: bank account % is % -- it may only be edited while draft', p_account_id, v_account.status
      using errcode = 'check_violation';
  end if;
end;
$$;

create or replace function app.assert_vendor_compliance_requirement_editable(p_requirement_version_id uuid, p_actor_auth_user_id uuid, out v_requirement app.vendor_compliance_requirements)
language plpgsql
as $$
declare
  v_decision app.rbac_decision;
begin
  -- `for update` (design note 13): serializes draft-CRUD against
  -- app.publish_vendor_compliance_requirement's own terminal UPDATE on the same row.
  select * into v_requirement from app.vendor_compliance_requirements where id = p_requirement_version_id for update;
  if not found or not app.has_active_tenant_membership(v_requirement.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_compliance_requirement_not_found: %', p_requirement_version_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_requirement.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_requirement.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_requirement.status <> 'draft' then
    raise exception 'vendor_compliance_requirement_not_draft: requirement version % is % -- it may only be edited while draft', p_requirement_version_id, v_requirement.status
      using errcode = 'check_violation';
  end if;
end;
$$;

create or replace function app.assert_vendor_tax_identity_editable(p_tax_identity_id uuid, p_actor_auth_user_id uuid, out v_tax_identity app.vendor_tax_identities)
language plpgsql
as $$
declare
  v_decision app.rbac_decision;
begin
  select * into v_tax_identity from app.vendor_tax_identities where id = p_tax_identity_id for update;
  if not found or not app.has_active_tenant_membership(v_tax_identity.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_tax_identity_not_found: %', p_tax_identity_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tax_identity.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tax_identity.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_tax_identity.status <> 'draft' then
    raise exception 'vendor_tax_identity_not_draft: tax identity % is % -- it may only be edited while draft', p_tax_identity_id, v_tax_identity.status
      using errcode = 'check_violation';
  end if;
end;
$$;

create or replace function app.create_vendor_bank_account_draft(
  p_vendor_master_record_id uuid,
  p_account_holder_name text,
  p_bank_name text,
  p_account_number text,
  p_currency text,
  p_purpose text,
  p_effective_from date,
  p_evidence_file_id uuid,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_bank_accounts
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_vendor app.vendor_profiles;
  v_file app.files;
  v_existing app.vendor_bank_accounts;
  v_account app.vendor_bank_accounts;
  v_hash text;
  v_last4 text;
  v_encrypted bytea;
begin
  select * into v_vendor from app.vendor_profiles where master_record_id = p_vendor_master_record_id;
  if not found or not app.has_active_tenant_membership(v_vendor.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_profile_not_found: %', p_vendor_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_vendor.tenant_id, 'PRC', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_vendor.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_account_holder_name is null or length(trim(p_account_holder_name)) = 0 then
    raise exception 'invalid_account_holder_name: account_holder_name must not be empty' using errcode = 'check_violation';
  end if;
  if p_bank_name is null or length(trim(p_bank_name)) = 0 then
    raise exception 'invalid_bank_name: bank_name must not be empty' using errcode = 'check_violation';
  end if;
  if p_account_number is null or length(regexp_replace(p_account_number, '\s', '', 'g')) < 4 then
    raise exception 'invalid_account_number: account_number must have at least 4 significant characters' using errcode = 'check_violation';
  end if;
  if not app.validate_currency_code(p_currency) then
    raise exception 'invalid_currency: % is not a registered, active currency', p_currency using errcode = 'check_violation';
  end if;
  if coalesce(p_purpose, 'primary') not in ('primary', 'settlement', 'other') then
    raise exception 'invalid_purpose: % is not primary, settlement, or other', p_purpose using errcode = 'check_violation';
  end if;

  -- Evidence re-validation (design note 8, mandatory pattern): re-fetch and reject on
  -- tenant mismatch, wrong record scope, or a non-clean malware scan.
  if p_evidence_file_id is not null then
    select * into v_file from app.files where id = p_evidence_file_id;
    if not found then
      raise exception 'evidence_file_not_found: %', p_evidence_file_id using errcode = 'no_data_found';
    end if;
    if v_file.tenant_id <> v_vendor.tenant_id or v_file.record_type <> 'vendor_financial_verification' or v_file.record_id <> p_vendor_master_record_id then
      raise exception 'financial_evidence_file_mismatch: file % was not uploaded for vendor %''s own financial verification purpose in tenant %', p_evidence_file_id, p_vendor_master_record_id, v_vendor.tenant_id
        using errcode = 'check_violation';
    end if;
    if v_file.malware_scan_status <> 'clean' then
      raise exception 'financial_unsafe_evidence: evidence file % has scan status % -- only clean evidence may be attached', p_evidence_file_id, v_file.malware_scan_status
        using errcode = 'check_violation';
    end if;
  end if;

  -- Encrypt/hash/last4 (design notes 1-3) -- computed once, never re-derived from a
  -- decrypt in this function.
  v_hash := app._hash_vendor_financial_value(p_account_number);
  v_last4 := app._last4_vendor_financial_value(p_account_number);
  v_encrypted := app._encrypt_vendor_financial_value(p_account_number);

  if p_idempotency_key is not null then
    select * into v_existing from app.vendor_bank_accounts where tenant_id = v_vendor.tenant_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.vendor_master_record_id is distinct from p_vendor_master_record_id or v_existing.account_holder_name is distinct from p_account_holder_name
        or v_existing.bank_name is distinct from p_bank_name or v_existing.account_number_hash is distinct from v_hash
        or v_existing.currency is distinct from p_currency or v_existing.purpose is distinct from coalesce(p_purpose, 'primary')
        or v_existing.effective_from is distinct from p_effective_from or v_existing.evidence_file_id is distinct from p_evidence_file_id
      then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different bank account proposal', p_idempotency_key
          using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  begin
    insert into app.vendor_bank_accounts (
      tenant_id, vendor_master_record_id, account_holder_name, bank_name, account_number_encrypted, account_number_hash,
      account_number_last4, currency, purpose, effective_from, evidence_file_id, proposed_by, proposed_by_auth_user_id,
      idempotency_key, created_by
    ) values (
      v_vendor.tenant_id, p_vendor_master_record_id, p_account_holder_name, p_bank_name, v_encrypted, v_hash,
      v_last4, p_currency, coalesce(p_purpose, 'primary'), p_effective_from, p_evidence_file_id, p_actor_label, p_actor_auth_user_id,
      p_idempotency_key, p_actor_label
    )
    returning * into v_account;
  exception
    when unique_violation then
      select * into v_existing from app.vendor_bank_accounts where tenant_id = v_vendor.tenant_id and idempotency_key = p_idempotency_key;
      if not found then
        raise;
      end if;
      if v_existing.vendor_master_record_id is distinct from p_vendor_master_record_id or v_existing.account_holder_name is distinct from p_account_holder_name
        or v_existing.bank_name is distinct from p_bank_name or v_existing.account_number_hash is distinct from v_hash
        or v_existing.currency is distinct from p_currency or v_existing.purpose is distinct from coalesce(p_purpose, 'primary')
        or v_existing.effective_from is distinct from p_effective_from or v_existing.evidence_file_id is distinct from p_evidence_file_id
      then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different bank account proposal', p_idempotency_key
          using errcode = 'unique_violation';
      end if;
      return v_existing;
  end;

  -- Design note 9: never to_jsonb(row) -- would serialize account_number_encrypted.
  perform app.capture_audit_event(
    v_vendor.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_vendor_bank_account_draft',
    'app.vendor_bank_accounts', v_account.id, 'success', null, null,
    jsonb_build_object('account_holder_name', v_account.account_holder_name, 'institution_name', v_account.bank_name, 'account_last4', v_account.account_number_last4, 'currency', v_account.currency, 'purpose', v_account.purpose, 'status', v_account.status)
  );

  return v_account;
end;
$$;

create or replace function app.create_vendor_tax_identity_draft(
  p_vendor_master_record_id uuid,
  p_tax_id_type text,
  p_tax_id text,
  p_legal_name_on_file text,
  p_effective_from date,
  p_evidence_file_id uuid,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_tax_identities
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_vendor app.vendor_profiles;
  v_file app.files;
  v_existing app.vendor_tax_identities;
  v_tax_identity app.vendor_tax_identities;
  v_hash text;
  v_last4 text;
  v_encrypted bytea;
begin
  select * into v_vendor from app.vendor_profiles where master_record_id = p_vendor_master_record_id;
  if not found or not app.has_active_tenant_membership(v_vendor.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_profile_not_found: %', p_vendor_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_vendor.tenant_id, 'PRC', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_vendor.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_tax_id_type is null or length(trim(p_tax_id_type)) = 0 then
    raise exception 'invalid_tax_id_type: tax_id_type must not be empty' using errcode = 'check_violation';
  end if;
  if p_legal_name_on_file is null or length(trim(p_legal_name_on_file)) = 0 then
    raise exception 'invalid_legal_name: legal_name_on_file must not be empty' using errcode = 'check_violation';
  end if;
  if p_tax_id is null or length(regexp_replace(p_tax_id, '\s', '', 'g')) < 4 then
    raise exception 'invalid_tax_id: tax_id must have at least 4 significant characters' using errcode = 'check_violation';
  end if;

  if p_evidence_file_id is not null then
    select * into v_file from app.files where id = p_evidence_file_id;
    if not found then
      raise exception 'evidence_file_not_found: %', p_evidence_file_id using errcode = 'no_data_found';
    end if;
    if v_file.tenant_id <> v_vendor.tenant_id or v_file.record_type <> 'vendor_financial_verification' or v_file.record_id <> p_vendor_master_record_id then
      raise exception 'financial_evidence_file_mismatch: file % was not uploaded for vendor %''s own financial verification purpose in tenant %', p_evidence_file_id, p_vendor_master_record_id, v_vendor.tenant_id
        using errcode = 'check_violation';
    end if;
    if v_file.malware_scan_status <> 'clean' then
      raise exception 'financial_unsafe_evidence: evidence file % has scan status % -- only clean evidence may be attached', p_evidence_file_id, v_file.malware_scan_status
        using errcode = 'check_violation';
    end if;
  end if;

  v_hash := app._hash_vendor_financial_value(p_tax_id);
  v_last4 := app._last4_vendor_financial_value(p_tax_id);
  v_encrypted := app._encrypt_vendor_financial_value(p_tax_id);

  if p_idempotency_key is not null then
    select * into v_existing from app.vendor_tax_identities where tenant_id = v_vendor.tenant_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.vendor_master_record_id is distinct from p_vendor_master_record_id or v_existing.tax_id_type is distinct from p_tax_id_type
        or v_existing.tax_id_hash is distinct from v_hash or v_existing.legal_name_on_file is distinct from p_legal_name_on_file
        or v_existing.effective_from is distinct from p_effective_from or v_existing.evidence_file_id is distinct from p_evidence_file_id
      then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different tax identity proposal', p_idempotency_key
          using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  begin
    insert into app.vendor_tax_identities (
      tenant_id, vendor_master_record_id, tax_id_type, tax_id_encrypted, tax_id_hash, tax_id_last4, legal_name_on_file,
      effective_from, evidence_file_id, proposed_by, proposed_by_auth_user_id, idempotency_key, created_by
    ) values (
      v_vendor.tenant_id, p_vendor_master_record_id, p_tax_id_type, v_encrypted, v_hash, v_last4, p_legal_name_on_file,
      p_effective_from, p_evidence_file_id, p_actor_label, p_actor_auth_user_id, p_idempotency_key, p_actor_label
    )
    returning * into v_tax_identity;
  exception
    when unique_violation then
      select * into v_existing from app.vendor_tax_identities where tenant_id = v_vendor.tenant_id and idempotency_key = p_idempotency_key;
      if not found then
        raise;
      end if;
      if v_existing.vendor_master_record_id is distinct from p_vendor_master_record_id or v_existing.tax_id_type is distinct from p_tax_id_type
        or v_existing.tax_id_hash is distinct from v_hash or v_existing.legal_name_on_file is distinct from p_legal_name_on_file
        or v_existing.effective_from is distinct from p_effective_from or v_existing.evidence_file_id is distinct from p_evidence_file_id
      then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different tax identity proposal', p_idempotency_key
          using errcode = 'unique_violation';
      end if;
      return v_existing;
  end;

  perform app.capture_audit_event(
    v_vendor.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_vendor_tax_identity_draft',
    'app.vendor_tax_identities', v_tax_identity.id, 'success', null, null,
    jsonb_build_object('tax_id_type', v_tax_identity.tax_id_type, 'tax_id_last4', v_tax_identity.tax_id_last4, 'legal_name_on_file', v_tax_identity.legal_name_on_file, 'status', v_tax_identity.status)
  );

  return v_tax_identity;
end;
$$;

create or replace function app.deactivate_vendor_bank_account(p_account_id uuid, p_expected_version integer, p_reason text, p_reauth_confirmed_at timestamptz, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_bank_accounts
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_account app.vendor_bank_accounts;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to deactivate a bank account' using errcode = 'check_violation';
  end if;
  if p_reauth_confirmed_at is null or p_reauth_confirmed_at > now() or now() - p_reauth_confirmed_at > interval '5 minutes' then
    raise exception 'reauth_required: re-authentication must have completed within the last 5 minutes'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_account from app.vendor_bank_accounts where id = p_account_id for update;
  if not found or not app.has_active_tenant_membership(v_account.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_bank_account_not_found: %', p_account_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_account.tenant_id, 'PRC', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_account.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_account.record_version <> p_expected_version then
    raise exception 'stale_version: vendor bank account % expected version % but found %', p_account_id, p_expected_version, v_account.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_account.status not in ('active', 'hold') then
    raise exception 'invalid_transition: vendor bank account % is % and cannot be deactivated', p_account_id, v_account.status
      using errcode = 'check_violation';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_account.vendor_master_record_id::text || ':' || v_account.account_family_id::text, 101));

  update app.vendor_bank_accounts
  set status = 'deactivated', deactivation_reason = p_reason, reauth_confirmed_at = p_reauth_confirmed_at, updated_at = now(), record_version = record_version + 1
  where id = p_account_id and record_version = p_expected_version
  returning * into v_account;
  if not found then
    raise exception 'stale_version: vendor bank account % target row was concurrently modified (expected version %)', p_account_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_account.tenant_id, p_actor_auth_user_id, p_actor_label, 'deactivate_vendor_bank_account',
    'app.vendor_bank_accounts', v_account.id, 'success', p_reason, null, jsonb_build_object('status', v_account.status)
  );

  return v_account;
end;
$$;

create or replace function app.deactivate_vendor_tax_identity(p_tax_identity_id uuid, p_expected_version integer, p_reason text, p_reauth_confirmed_at timestamptz, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_tax_identities
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tax_identity app.vendor_tax_identities;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to deactivate a tax identity' using errcode = 'check_violation';
  end if;
  if p_reauth_confirmed_at is null or p_reauth_confirmed_at > now() or now() - p_reauth_confirmed_at > interval '5 minutes' then
    raise exception 'reauth_required: re-authentication must have completed within the last 5 minutes'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_tax_identity from app.vendor_tax_identities where id = p_tax_identity_id for update;
  if not found or not app.has_active_tenant_membership(v_tax_identity.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_tax_identity_not_found: %', p_tax_identity_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tax_identity.tenant_id, 'PRC', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tax_identity.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_tax_identity.record_version <> p_expected_version then
    raise exception 'stale_version: vendor tax identity % expected version % but found %', p_tax_identity_id, p_expected_version, v_tax_identity.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_tax_identity.status not in ('active', 'hold') then
    raise exception 'invalid_transition: vendor tax identity % is % and cannot be deactivated', p_tax_identity_id, v_tax_identity.status
      using errcode = 'check_violation';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_tax_identity.vendor_master_record_id::text || ':' || v_tax_identity.tax_family_id::text, 102));

  update app.vendor_tax_identities
  set status = 'deactivated', deactivation_reason = p_reason, reauth_confirmed_at = p_reauth_confirmed_at, updated_at = now(), record_version = record_version + 1
  where id = p_tax_identity_id and record_version = p_expected_version
  returning * into v_tax_identity;
  if not found then
    raise exception 'stale_version: vendor tax identity % target row was concurrently modified (expected version %)', p_tax_identity_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_tax_identity.tenant_id, p_actor_auth_user_id, p_actor_label, 'deactivate_vendor_tax_identity',
    'app.vendor_tax_identities', v_tax_identity.id, 'success', p_reason, null, jsonb_build_object('status', v_tax_identity.status)
  );

  return v_tax_identity;
end;
$$;

create or replace function app.decide_vendor_bank_account_approval(
  p_account_id uuid,
  p_expected_version integer,
  p_decision text,
  p_supersedes_account_id uuid,
  p_rejection_reason text,
  p_reauth_confirmed_at timestamptz,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_bank_accounts
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_account app.vendor_bank_accounts;
  v_superseded app.vendor_bank_accounts;
  v_gate text;
  v_family_id uuid;
  v_lock_family_id uuid;
  v_constraint_name text;
begin
  if p_decision not in ('approved', 'rejected') then
    raise exception 'invalid_decision: % is not approved or rejected', p_decision using errcode = 'check_violation';
  end if;
  if p_decision = 'rejected' and (p_rejection_reason is null or length(trim(p_rejection_reason)) = 0) then
    raise exception 'reason_required: a non-empty reason is required to reject a bank account proposal' using errcode = 'check_violation';
  end if;
  if p_reauth_confirmed_at is null or p_reauth_confirmed_at > now() or now() - p_reauth_confirmed_at > interval '5 minutes' then
    raise exception 'reauth_required: re-authentication must have completed within the last 5 minutes'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_account from app.vendor_bank_accounts where id = p_account_id for update;
  if not found or not app.has_active_tenant_membership(v_account.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_bank_account_not_found: %', p_account_id using errcode = 'no_data_found';
  end if;

  -- Maker-checker (design note 7): the same identity that proposed may not decide.
  if v_account.proposed_by_auth_user_id = p_actor_auth_user_id then
    raise exception 'self_approval_not_allowed: identity % proposed bank account % and may not also decide it', p_actor_auth_user_id, p_account_id
      using errcode = 'insufficient_privilege';
  end if;

  v_gate := case p_decision when 'approved' then 'Approve' else 'Reject' end;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_account.tenant_id, 'PRC', v_gate);
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:% (%) for tenant %', p_actor_auth_user_id, v_gate, v_decision.reason, v_account.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_account.record_version <> p_expected_version then
    raise exception 'stale_version: vendor bank account % expected version % but found %', p_account_id, p_expected_version, v_account.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_account.status <> 'pending_approval' then
    raise exception 'invalid_transition: vendor bank account % is % and cannot be decided', p_account_id, v_account.status
      using errcode = 'check_violation';
  end if;

  -- Advisory family lock (design note 14) -- serializes this decision against a
  -- bystander hold/reactivate/deactivate acting on a DIFFERENT row (the currently
  -- active one) in the SAME family. Correctness-concurrency fix: when this decision
  -- supersedes a prior active row, the actual contention point is THAT row's family
  -- (v_superseded.account_family_id), never this pending_approval draft's own,
  -- freshly-minted, never-contended account_family_id -- locking on the draft's own
  -- family (the original bug) was dead code for exactly the race this mechanism
  -- exists to close, since no bystander hold/reactivate/deactivate call ever targets
  -- a brand-new draft row. Look up the superseded row's family BEFORE taking the
  -- lock, then re-fetch that row `for update` AFTER the lock is held below (a
  -- concurrent mutation could otherwise change it in the gap between the two reads).
  if p_decision = 'approved' and p_supersedes_account_id is not null then
    select account_family_id into v_lock_family_id from app.vendor_bank_accounts where id = p_supersedes_account_id;
    if v_lock_family_id is null then
      raise exception 'superseded_account_not_found: %', p_supersedes_account_id using errcode = 'no_data_found';
    end if;
  else
    v_lock_family_id := v_account.account_family_id;
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_account.vendor_master_record_id::text || ':' || v_lock_family_id::text, 101));

  v_family_id := v_account.account_family_id;

  if p_decision = 'approved' and p_supersedes_account_id is not null then
    select * into v_superseded from app.vendor_bank_accounts where id = p_supersedes_account_id for update;
    if not found then
      raise exception 'superseded_account_not_found: %', p_supersedes_account_id using errcode = 'no_data_found';
    end if;
    -- Security-rls Finding 2 fix: the active-scope tuple this supersede mechanism
    -- services is THREE columns (vendor_master_record_id, purpose, currency) --
    -- exactly what vendor_bank_accounts_active_scope_unique enforces. Comparing only
    -- vendor+purpose let an approver supply an unrelated, different-currency active
    -- account as p_supersedes_account_id and silently deactivate it.
    if v_superseded.vendor_master_record_id <> v_account.vendor_master_record_id or v_superseded.purpose <> v_account.purpose or v_superseded.currency <> v_account.currency then
      raise exception 'invalid_supersede: superseded bank account must share the same vendor, purpose and currency' using errcode = 'check_violation';
    end if;
    if v_superseded.status <> 'active' then
      raise exception 'invalid_supersede: superseded bank account % is % (must be active)', p_supersedes_account_id, v_superseded.status using errcode = 'check_violation';
    end if;

    v_family_id := v_superseded.account_family_id;

    update app.vendor_bank_accounts
    set status = 'deactivated', deactivation_reason = 'superseded_by_approved_change', updated_at = now(), record_version = record_version + 1
    where id = p_supersedes_account_id and record_version = v_superseded.record_version and status = 'active';
    if not found then
      raise exception 'stale_version: superseded vendor bank account % was concurrently modified (expected version %)', p_supersedes_account_id, v_superseded.record_version
        using errcode = 'serialization_failure';
    end if;
  end if;

  begin
    update app.vendor_bank_accounts
    set status = case when p_decision = 'approved' then 'active' else 'rejected' end,
        account_family_id = case when p_decision = 'approved' then v_family_id else account_family_id end,
        rejection_reason = case when p_decision = 'rejected' then p_rejection_reason else null end,
        effective_from = case when p_decision = 'approved' then coalesce(effective_from, current_date) else effective_from end,
        approved_by = p_actor_label, approved_by_auth_user_id = p_actor_auth_user_id, reauth_confirmed_at = p_reauth_confirmed_at,
        updated_at = now(), record_version = record_version + 1
    where id = p_account_id and record_version = p_expected_version
    returning * into v_account;
  exception
    when unique_violation then
      get stacked diagnostics v_constraint_name = constraint_name;
      if v_constraint_name = 'vendor_bank_accounts_active_scope_unique' then
        raise exception 'active_account_exists: an active bank account already exists for vendor %, purpose %, currency % -- supply p_supersedes_account_id to replace it', v_account.vendor_master_record_id, v_account.purpose, v_account.currency
          using errcode = 'check_violation';
      else
        raise;
      end if;
  end;
  if not found then
    raise exception 'stale_version: vendor bank account % target row was concurrently modified (expected version %)', p_account_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_account.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_vendor_bank_account_approval',
    'app.vendor_bank_accounts', v_account.id, 'success', p_rejection_reason, null,
    jsonb_build_object('decision', p_decision, 'account_last4', v_account.account_number_last4, 'status', v_account.status, 'supersedes_account_id', p_supersedes_account_id)
  );

  return v_account;
end;
$$;

create or replace function app.decide_vendor_compliance_document(
  p_document_id uuid, p_expected_version integer, p_decision text, p_rejection_reason text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_compliance_documents
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_document app.vendor_compliance_documents;
  v_requirement app.vendor_compliance_requirements;
  v_gate text;
begin
  if p_decision not in ('verified', 'rejected', 'revision_requested') then
    raise exception 'invalid_decision: % is not verified, rejected, or revision_requested', p_decision using errcode = 'check_violation';
  end if;
  if p_decision in ('rejected', 'revision_requested') and (p_rejection_reason is null or length(trim(p_rejection_reason)) = 0) then
    raise exception 'reason_required: a non-empty reason is required to reject or request revision of a compliance document' using errcode = 'check_violation';
  end if;

  select * into v_document from app.vendor_compliance_documents where id = p_document_id for update;
  if not found or not app.has_active_tenant_membership(v_document.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_compliance_document_not_found: %', p_document_id using errcode = 'no_data_found';
  end if;
  if v_document.record_version <> p_expected_version then
    raise exception 'stale_version: vendor compliance document % expected version % but found %', p_document_id, p_expected_version, v_document.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_document.verification_status <> 'pending' then
    raise exception 'invalid_transition: vendor compliance document % is already %', p_document_id, v_document.verification_status using errcode = 'check_violation';
  end if;

  v_gate := case p_decision when 'verified' then 'Approve' else 'Reject' end;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_document.tenant_id, 'PRC', v_gate);
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:% (%) for tenant %', p_actor_auth_user_id, v_gate, v_decision.reason, v_document.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_requirement from app.vendor_compliance_requirements where id = v_document.requirement_version_id;
  if p_decision = 'verified' and v_requirement.requires_expiry and v_document.expiry_date is null then
    raise exception 'expiry_required_for_verification: document % has no expiry_date but requirement % requires one', p_document_id, v_requirement.id
      using errcode = 'check_violation';
  end if;

  update app.vendor_compliance_documents
  set verification_status = p_decision, rejection_reason = case when p_decision = 'verified' then null else p_rejection_reason end,
      verified_by = p_actor_label, verified_by_auth_user_id = p_actor_auth_user_id, verified_at = now(),
      record_version = record_version + 1, updated_at = now()
  where id = p_document_id and record_version = p_expected_version
  returning * into v_document;
  if not found then
    raise exception 'stale_version: vendor compliance document % target row was concurrently modified (expected version %)', p_document_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app._recalculate_vendor_compliance_status_family(v_document.vendor_master_record_id, v_requirement.requirement_family_id, p_actor_label);

  perform app.capture_audit_event(
    v_document.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_vendor_compliance_document',
    'app.vendor_compliance_documents', v_document.id, 'success', p_rejection_reason, null, jsonb_build_object('decision', p_decision)
  );

  return v_document;
end;
$$;

create or replace function app.decide_vendor_payment_term_change_proposal(
  p_proposal_id uuid, p_expected_version integer, p_decision text, p_decision_reason text, p_reauth_confirmed_at timestamptz, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_payment_term_proposals
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_proposal app.vendor_payment_term_proposals;
  v_vendor app.vendor_profiles;
  v_gate text;
begin
  if p_decision not in ('approved', 'rejected') then
    raise exception 'invalid_decision: % is not approved or rejected', p_decision using errcode = 'check_violation';
  end if;
  if p_decision = 'rejected' and (p_decision_reason is null or length(trim(p_decision_reason)) = 0) then
    raise exception 'reason_required: a non-empty reason is required to reject a payment-term proposal' using errcode = 'check_violation';
  end if;
  if p_reauth_confirmed_at is null or p_reauth_confirmed_at > now() or now() - p_reauth_confirmed_at > interval '5 minutes' then
    raise exception 'reauth_required: re-authentication must have completed within the last 5 minutes'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_proposal from app.vendor_payment_term_proposals where id = p_proposal_id for update;
  if not found or not app.has_active_tenant_membership(v_proposal.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_payment_term_proposal_not_found: %', p_proposal_id using errcode = 'no_data_found';
  end if;

  if v_proposal.proposed_by_auth_user_id = p_actor_auth_user_id then
    raise exception 'self_approval_not_allowed: identity % proposed payment-term change % and may not also decide it', p_actor_auth_user_id, p_proposal_id
      using errcode = 'insufficient_privilege';
  end if;

  v_gate := case p_decision when 'approved' then 'Approve' else 'Reject' end;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_proposal.tenant_id, 'PRC', v_gate);
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:% (%) for tenant %', p_actor_auth_user_id, v_gate, v_decision.reason, v_proposal.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_proposal.record_version <> p_expected_version then
    raise exception 'stale_version: payment-term proposal % expected version % but found %', p_proposal_id, p_expected_version, v_proposal.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_proposal.status <> 'pending_approval' then
    raise exception 'invalid_transition: payment-term proposal % is % and cannot be decided', p_proposal_id, v_proposal.status
      using errcode = 'check_violation';
  end if;

  if p_decision = 'approved' then
    select * into v_vendor from app.vendor_profiles where master_record_id = v_proposal.vendor_master_record_id for update;
    if v_vendor.record_version <> v_proposal.vendor_profile_expected_version then
      raise exception 'vendor_profile_changed_since_proposal: vendor % profile changed since this proposal was made (expected version %, found %) -- reject and re-propose', v_proposal.vendor_master_record_id, v_proposal.vendor_profile_expected_version, v_vendor.record_version
        using errcode = 'serialization_failure';
    end if;

    update app.vendor_profiles
    set payment_term_days = v_proposal.proposed_payment_term_days, updated_at = now(), record_version = record_version + 1
    where master_record_id = v_proposal.vendor_master_record_id and record_version = v_proposal.vendor_profile_expected_version;
    if not found then
      raise exception 'stale_version: vendor profile % was concurrently modified (expected version %)', v_proposal.vendor_master_record_id, v_proposal.vendor_profile_expected_version
        using errcode = 'serialization_failure';
    end if;
  end if;

  update app.vendor_payment_term_proposals
  set status = case when p_decision = 'approved' then 'approved' else 'rejected' end,
      decision_reason = p_decision_reason, approved_by = p_actor_label, approved_by_auth_user_id = p_actor_auth_user_id,
      reauth_confirmed_at = p_reauth_confirmed_at, updated_at = now(), record_version = record_version + 1
  where id = p_proposal_id and record_version = p_expected_version
  returning * into v_proposal;
  if not found then
    raise exception 'stale_version: payment-term proposal % target row was concurrently modified (expected version %)', p_proposal_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_proposal.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_vendor_payment_term_change_proposal',
    'app.vendor_payment_term_proposals', v_proposal.id, 'success', p_decision_reason, null, to_jsonb(v_proposal)
  );

  return v_proposal;
end;
$$;

create or replace function app.decide_vendor_tax_identity_approval(
  p_tax_identity_id uuid,
  p_expected_version integer,
  p_decision text,
  p_supersedes_tax_identity_id uuid,
  p_rejection_reason text,
  p_reauth_confirmed_at timestamptz,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_tax_identities
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tax_identity app.vendor_tax_identities;
  v_superseded app.vendor_tax_identities;
  v_gate text;
  v_family_id uuid;
  v_lock_family_id uuid;
  v_constraint_name text;
begin
  if p_decision not in ('approved', 'rejected') then
    raise exception 'invalid_decision: % is not approved or rejected', p_decision using errcode = 'check_violation';
  end if;
  if p_decision = 'rejected' and (p_rejection_reason is null or length(trim(p_rejection_reason)) = 0) then
    raise exception 'reason_required: a non-empty reason is required to reject a tax identity proposal' using errcode = 'check_violation';
  end if;
  if p_reauth_confirmed_at is null or p_reauth_confirmed_at > now() or now() - p_reauth_confirmed_at > interval '5 minutes' then
    raise exception 'reauth_required: re-authentication must have completed within the last 5 minutes'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_tax_identity from app.vendor_tax_identities where id = p_tax_identity_id for update;
  if not found or not app.has_active_tenant_membership(v_tax_identity.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_tax_identity_not_found: %', p_tax_identity_id using errcode = 'no_data_found';
  end if;

  if v_tax_identity.proposed_by_auth_user_id = p_actor_auth_user_id then
    raise exception 'self_approval_not_allowed: identity % proposed tax identity % and may not also decide it', p_actor_auth_user_id, p_tax_identity_id
      using errcode = 'insufficient_privilege';
  end if;

  v_gate := case p_decision when 'approved' then 'Approve' else 'Reject' end;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tax_identity.tenant_id, 'PRC', v_gate);
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:% (%) for tenant %', p_actor_auth_user_id, v_gate, v_decision.reason, v_tax_identity.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_tax_identity.record_version <> p_expected_version then
    raise exception 'stale_version: vendor tax identity % expected version % but found %', p_tax_identity_id, p_expected_version, v_tax_identity.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_tax_identity.status <> 'pending_approval' then
    raise exception 'invalid_transition: vendor tax identity % is % and cannot be decided', p_tax_identity_id, v_tax_identity.status
      using errcode = 'check_violation';
  end if;

  -- Correctness-concurrency fix (mirrors the bank-account decide RPC's own fix
  -- immediately above): lock on the SUPERSEDED row's family when superseding, never
  -- this pending_approval draft's own freshly-minted family.
  if p_decision = 'approved' and p_supersedes_tax_identity_id is not null then
    select tax_family_id into v_lock_family_id from app.vendor_tax_identities where id = p_supersedes_tax_identity_id;
    if v_lock_family_id is null then
      raise exception 'superseded_tax_identity_not_found: %', p_supersedes_tax_identity_id using errcode = 'no_data_found';
    end if;
  else
    v_lock_family_id := v_tax_identity.tax_family_id;
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_tax_identity.vendor_master_record_id::text || ':' || v_lock_family_id::text, 102));

  v_family_id := v_tax_identity.tax_family_id;

  if p_decision = 'approved' and p_supersedes_tax_identity_id is not null then
    select * into v_superseded from app.vendor_tax_identities where id = p_supersedes_tax_identity_id for update;
    if not found then
      raise exception 'superseded_tax_identity_not_found: %', p_supersedes_tax_identity_id using errcode = 'no_data_found';
    end if;
    if v_superseded.vendor_master_record_id <> v_tax_identity.vendor_master_record_id or v_superseded.tax_id_type <> v_tax_identity.tax_id_type then
      raise exception 'invalid_supersede: superseded tax identity must share the same vendor and tax_id_type' using errcode = 'check_violation';
    end if;
    if v_superseded.status <> 'active' then
      raise exception 'invalid_supersede: superseded tax identity % is % (must be active)', p_supersedes_tax_identity_id, v_superseded.status using errcode = 'check_violation';
    end if;

    v_family_id := v_superseded.tax_family_id;

    update app.vendor_tax_identities
    set status = 'deactivated', deactivation_reason = 'superseded_by_approved_change', updated_at = now(), record_version = record_version + 1
    where id = p_supersedes_tax_identity_id and record_version = v_superseded.record_version and status = 'active';
    if not found then
      raise exception 'stale_version: superseded vendor tax identity % was concurrently modified (expected version %)', p_supersedes_tax_identity_id, v_superseded.record_version
        using errcode = 'serialization_failure';
    end if;
  end if;

  begin
    update app.vendor_tax_identities
    set status = case when p_decision = 'approved' then 'active' else 'rejected' end,
        tax_family_id = case when p_decision = 'approved' then v_family_id else tax_family_id end,
        rejection_reason = case when p_decision = 'rejected' then p_rejection_reason else null end,
        effective_from = case when p_decision = 'approved' then coalesce(effective_from, current_date) else effective_from end,
        approved_by = p_actor_label, approved_by_auth_user_id = p_actor_auth_user_id, reauth_confirmed_at = p_reauth_confirmed_at,
        updated_at = now(), record_version = record_version + 1
    where id = p_tax_identity_id and record_version = p_expected_version
    returning * into v_tax_identity;
  exception
    when unique_violation then
      get stacked diagnostics v_constraint_name = constraint_name;
      if v_constraint_name = 'vendor_tax_identities_active_scope_unique' then
        raise exception 'active_tax_identity_exists: an active tax identity already exists for vendor %, type % -- supply p_supersedes_tax_identity_id to replace it', v_tax_identity.vendor_master_record_id, v_tax_identity.tax_id_type
          using errcode = 'check_violation';
      else
        raise;
      end if;
  end;
  if not found then
    raise exception 'stale_version: vendor tax identity % target row was concurrently modified (expected version %)', p_tax_identity_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_tax_identity.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_vendor_tax_identity_approval',
    'app.vendor_tax_identities', v_tax_identity.id, 'success', p_rejection_reason, null,
    jsonb_build_object('decision', p_decision, 'tax_id_last4', v_tax_identity.tax_id_last4, 'status', v_tax_identity.status, 'supersedes_tax_identity_id', p_supersedes_tax_identity_id)
  );

  return v_tax_identity;
end;
$$;

create or replace function app.get_vendor_bank_account_masked(p_account_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, tenant_id uuid, vendor_master_record_id uuid, account_family_id uuid, account_holder_name text, bank_name text,
  account_number_last4 text, currency text, purpose text, status text, effective_from date, evidence_file_id uuid,
  is_duplicate_candidate boolean, proposed_by text, approved_by text, hold_reason text, rejection_reason text,
  deactivation_reason text, record_version integer, created_at timestamptz, updated_at timestamptz
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_account app.vendor_bank_accounts;
begin
  -- Table-qualified (not bare `id`) -- this RPC's own RETURNS TABLE declares a
  -- same-named `id` OUT parameter, which Postgres implicitly turns into a plpgsql
  -- variable; an unqualified `where id = ...` here is ambiguous (the exact class of
  -- bug PRC-251's own build log records finding and fixing three times).
  select * into v_account from app.vendor_bank_accounts where app.vendor_bank_accounts.id = p_account_id;
  if not found or not app.has_active_tenant_membership(v_account.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_bank_account_not_found: %', p_account_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_account.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_account.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select a.id, a.tenant_id, a.vendor_master_record_id, a.account_family_id, a.account_holder_name, a.bank_name,
    a.account_number_last4, a.currency, a.purpose, a.status, a.effective_from, a.evidence_file_id,
    exists (
      select 1 from app.vendor_bank_accounts d
      where d.tenant_id = a.tenant_id and d.account_number_hash = a.account_number_hash and d.id <> a.id
        and d.vendor_master_record_id <> a.vendor_master_record_id and d.status in ('active', 'pending_approval')
    ) as is_duplicate_candidate,
    a.proposed_by, a.approved_by, a.hold_reason, a.rejection_reason, a.deactivation_reason, a.record_version, a.created_at, a.updated_at
  from app.vendor_bank_accounts a
  where a.id = p_account_id;
end;
$$;

create or replace function app.get_vendor_compliance_eligibility(p_vendor_master_record_id uuid, p_actor_auth_user_id uuid)
returns table (
  requirement_family_id uuid, requirement_version_id uuid, requirement_name text, blocking_effect text,
  document_type_code text, status text, eligibility_hold boolean, current_document_id uuid, expiry_date date,
  reminder_offsets integer[], days_until_expiry integer, reminder_tier_days integer, computed_at timestamptz
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_vendor app.vendor_profiles;
begin
  select * into v_vendor from app.vendor_profiles where master_record_id = p_vendor_master_record_id;
  if not found or not app.has_active_tenant_membership(v_vendor.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_profile_not_found: %', p_vendor_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_vendor.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_vendor.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select s.requirement_family_id, s.current_requirement_version_id, r.name, r.blocking_effect, r.document_type_code,
    s.status, s.eligibility_hold, s.current_document_id, d.expiry_date, r.reminder_offsets,
    (d.expiry_date - current_date) as days_until_expiry,
    (select min(o) from unnest(r.reminder_offsets) o where o >= (d.expiry_date - current_date)) as reminder_tier_days,
    s.computed_at
  from app.vendor_compliance_status s
  left join app.vendor_compliance_requirements r on r.id = s.current_requirement_version_id
  left join app.vendor_compliance_documents d on d.id = s.current_document_id
  where s.vendor_master_record_id = p_vendor_master_record_id
  order by r.name nulls last;
end;
$$;

create or replace function app.get_vendor_financial_verification_status(p_vendor_master_record_id uuid, p_actor_auth_user_id uuid)
returns table (vendor_master_record_id uuid, has_verified_bank_account boolean, has_verified_tax_identity boolean, on_hold boolean, computed_at timestamptz)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_vendor app.vendor_profiles;
begin
  select * into v_vendor from app.vendor_profiles where master_record_id = p_vendor_master_record_id;
  if not found or not app.has_active_tenant_membership(v_vendor.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_profile_not_found: %', p_vendor_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_vendor.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_vendor.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select
    p_vendor_master_record_id,
    exists (select 1 from app.vendor_bank_accounts a where a.vendor_master_record_id = p_vendor_master_record_id and a.status = 'active'),
    exists (select 1 from app.vendor_tax_identities t where t.vendor_master_record_id = p_vendor_master_record_id and t.status = 'active'),
    exists (select 1 from app.vendor_bank_accounts a where a.vendor_master_record_id = p_vendor_master_record_id and a.status = 'hold')
      or exists (select 1 from app.vendor_tax_identities t where t.vendor_master_record_id = p_vendor_master_record_id and t.status = 'hold'),
    now();
end;
$$;

create or replace function app.get_vendor_tax_identity_masked(p_tax_identity_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, tenant_id uuid, vendor_master_record_id uuid, tax_family_id uuid, tax_id_type text, tax_id_last4 text,
  legal_name_on_file text, status text, effective_from date, evidence_file_id uuid, is_duplicate_candidate boolean,
  proposed_by text, approved_by text, hold_reason text, rejection_reason text, deactivation_reason text,
  record_version integer, created_at timestamptz, updated_at timestamptz
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tax_identity app.vendor_tax_identities;
begin
  -- Table-qualified -- see the identical comment on app.get_vendor_bank_account_masked.
  select * into v_tax_identity from app.vendor_tax_identities where app.vendor_tax_identities.id = p_tax_identity_id;
  if not found or not app.has_active_tenant_membership(v_tax_identity.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_tax_identity_not_found: %', p_tax_identity_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tax_identity.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tax_identity.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select t.id, t.tenant_id, t.vendor_master_record_id, t.tax_family_id, t.tax_id_type, t.tax_id_last4, t.legal_name_on_file,
    t.status, t.effective_from, t.evidence_file_id,
    exists (
      select 1 from app.vendor_tax_identities d
      where d.tenant_id = t.tenant_id and d.tax_id_hash = t.tax_id_hash and d.id <> t.id
        and d.vendor_master_record_id <> t.vendor_master_record_id and d.status in ('active', 'pending_approval')
    ) as is_duplicate_candidate,
    t.proposed_by, t.approved_by, t.hold_reason, t.rejection_reason, t.deactivation_reason, t.record_version, t.created_at, t.updated_at
  from app.vendor_tax_identities t
  where t.id = p_tax_identity_id;
end;
$$;

create or replace function app.hold_vendor_bank_account(p_account_id uuid, p_expected_version integer, p_reason text, p_reauth_confirmed_at timestamptz, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_bank_accounts
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_account app.vendor_bank_accounts;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to place a bank account on hold' using errcode = 'check_violation';
  end if;
  if p_reauth_confirmed_at is null or p_reauth_confirmed_at > now() or now() - p_reauth_confirmed_at > interval '5 minutes' then
    raise exception 'reauth_required: re-authentication must have completed within the last 5 minutes'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_account from app.vendor_bank_accounts where id = p_account_id for update;
  if not found or not app.has_active_tenant_membership(v_account.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_bank_account_not_found: %', p_account_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_account.tenant_id, 'PRC', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_account.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_account.record_version <> p_expected_version then
    raise exception 'stale_version: vendor bank account % expected version % but found %', p_account_id, p_expected_version, v_account.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_account.status <> 'active' then
    raise exception 'invalid_transition: vendor bank account % is % and cannot be placed on hold', p_account_id, v_account.status
      using errcode = 'check_violation';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_account.vendor_master_record_id::text || ':' || v_account.account_family_id::text, 101));

  update app.vendor_bank_accounts
  set status = 'hold', hold_reason = p_reason, hold_by_auth_user_id = p_actor_auth_user_id, reauth_confirmed_at = p_reauth_confirmed_at, updated_at = now(), record_version = record_version + 1
  where id = p_account_id and record_version = p_expected_version
  returning * into v_account;
  if not found then
    raise exception 'stale_version: vendor bank account % target row was concurrently modified (expected version %)', p_account_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_account.tenant_id, p_actor_auth_user_id, p_actor_label, 'hold_vendor_bank_account',
    'app.vendor_bank_accounts', v_account.id, 'success', p_reason, null, jsonb_build_object('status', v_account.status)
  );

  return v_account;
end;
$$;

create or replace function app.hold_vendor_tax_identity(p_tax_identity_id uuid, p_expected_version integer, p_reason text, p_reauth_confirmed_at timestamptz, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_tax_identities
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tax_identity app.vendor_tax_identities;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to place a tax identity on hold' using errcode = 'check_violation';
  end if;
  if p_reauth_confirmed_at is null or p_reauth_confirmed_at > now() or now() - p_reauth_confirmed_at > interval '5 minutes' then
    raise exception 'reauth_required: re-authentication must have completed within the last 5 minutes'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_tax_identity from app.vendor_tax_identities where id = p_tax_identity_id for update;
  if not found or not app.has_active_tenant_membership(v_tax_identity.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_tax_identity_not_found: %', p_tax_identity_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tax_identity.tenant_id, 'PRC', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tax_identity.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_tax_identity.record_version <> p_expected_version then
    raise exception 'stale_version: vendor tax identity % expected version % but found %', p_tax_identity_id, p_expected_version, v_tax_identity.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_tax_identity.status <> 'active' then
    raise exception 'invalid_transition: vendor tax identity % is % and cannot be placed on hold', p_tax_identity_id, v_tax_identity.status
      using errcode = 'check_violation';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_tax_identity.vendor_master_record_id::text || ':' || v_tax_identity.tax_family_id::text, 102));

  update app.vendor_tax_identities
  set status = 'hold', hold_reason = p_reason, hold_by_auth_user_id = p_actor_auth_user_id, reauth_confirmed_at = p_reauth_confirmed_at, updated_at = now(), record_version = record_version + 1
  where id = p_tax_identity_id and record_version = p_expected_version
  returning * into v_tax_identity;
  if not found then
    raise exception 'stale_version: vendor tax identity % target row was concurrently modified (expected version %)', p_tax_identity_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_tax_identity.tenant_id, p_actor_auth_user_id, p_actor_label, 'hold_vendor_tax_identity',
    'app.vendor_tax_identities', v_tax_identity.id, 'success', p_reason, null, jsonb_build_object('status', v_tax_identity.status)
  );

  return v_tax_identity;
end;
$$;

create or replace function app.list_vendor_bank_accounts_masked(
  p_vendor_master_record_id uuid, p_actor_auth_user_id uuid, p_status_filter text default null, p_limit integer default 100, p_after_id uuid default null
)
returns table (
  id uuid, tenant_id uuid, vendor_master_record_id uuid, account_family_id uuid, account_holder_name text, bank_name text,
  account_number_last4 text, currency text, purpose text, status text, effective_from date, evidence_file_id uuid,
  is_duplicate_candidate boolean, proposed_by text, approved_by text, hold_reason text, rejection_reason text,
  deactivation_reason text, record_version integer, created_at timestamptz, updated_at timestamptz
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_vendor app.vendor_profiles;
begin
  select * into v_vendor from app.vendor_profiles where master_record_id = p_vendor_master_record_id;
  if not found or not app.has_active_tenant_membership(v_vendor.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_profile_not_found: %', p_vendor_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_vendor.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_vendor.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_status_filter is not null and p_status_filter not in ('draft', 'pending_approval', 'active', 'rejected', 'hold', 'deactivated') then
    raise exception 'invalid_status_filter: %', p_status_filter using errcode = 'check_violation';
  end if;

  return query
  select a.id, a.tenant_id, a.vendor_master_record_id, a.account_family_id, a.account_holder_name, a.bank_name,
    a.account_number_last4, a.currency, a.purpose, a.status, a.effective_from, a.evidence_file_id,
    exists (
      select 1 from app.vendor_bank_accounts d
      where d.tenant_id = a.tenant_id and d.account_number_hash = a.account_number_hash and d.id <> a.id
        and d.vendor_master_record_id <> a.vendor_master_record_id and d.status in ('active', 'pending_approval')
    ) as is_duplicate_candidate,
    a.proposed_by, a.approved_by, a.hold_reason, a.rejection_reason, a.deactivation_reason, a.record_version, a.created_at, a.updated_at
  from app.vendor_bank_accounts a
  where a.vendor_master_record_id = p_vendor_master_record_id
    and (p_status_filter is null or a.status = p_status_filter)
    and (p_after_id is null or a.id > p_after_id)
  order by a.id
  limit least(coalesce(p_limit, 100), 500);
end;
$$;

create or replace function app.list_vendor_compliance_document_versions(p_version_group_id uuid, p_actor_auth_user_id uuid)
returns setof app.vendor_compliance_documents
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_any app.vendor_compliance_documents;
begin
  select * into v_any from app.vendor_compliance_documents where version_group_id = p_version_group_id limit 1;
  if not found or not app.has_active_tenant_membership(v_any.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_compliance_document_not_found: no document with version_group_id %', p_version_group_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_any.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_any.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.vendor_compliance_documents where version_group_id = p_version_group_id order by version_number;
end;
$$;

create or replace function app.list_vendor_compliance_documents(
  p_vendor_master_record_id uuid, p_actor_auth_user_id uuid, p_requirement_version_id uuid default null,
  p_latest_only boolean default true, p_limit integer default 100, p_after_id uuid default null
)
returns setof app.vendor_compliance_documents
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_vendor app.vendor_profiles;
begin
  select * into v_vendor from app.vendor_profiles where master_record_id = p_vendor_master_record_id;
  if not found or not app.has_active_tenant_membership(v_vendor.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_profile_not_found: %', p_vendor_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_vendor.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_vendor.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select d.* from app.vendor_compliance_documents d
  where d.vendor_master_record_id = p_vendor_master_record_id
    and (p_requirement_version_id is null or d.requirement_version_id = p_requirement_version_id)
    and (not p_latest_only or d.is_latest_version)
    and (p_after_id is null or d.id > p_after_id)
  order by d.id
  limit least(coalesce(p_limit, 100), 500);
end;
$$;

create or replace function app.list_vendor_compliance_waivers(
  p_vendor_master_record_id uuid, p_actor_auth_user_id uuid, p_status_filter text default null, p_limit integer default 50, p_after_id uuid default null
)
returns setof app.vendor_compliance_waivers
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_vendor app.vendor_profiles;
begin
  select * into v_vendor from app.vendor_profiles where master_record_id = p_vendor_master_record_id;
  if not found or not app.has_active_tenant_membership(v_vendor.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_profile_not_found: %', p_vendor_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_vendor.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_vendor.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_status_filter is not null and p_status_filter not in ('pending', 'approved', 'rejected', 'expired', 'revoked') then
    raise exception 'invalid_status_filter: %', p_status_filter using errcode = 'check_violation';
  end if;

  return query
  select w.* from app.vendor_compliance_waivers w
  where w.vendor_master_record_id = p_vendor_master_record_id
    and (p_status_filter is null or w.status = p_status_filter)
    and (p_after_id is null or w.id > p_after_id)
  order by w.id
  limit least(coalesce(p_limit, 50), 200);
end;
$$;

create or replace function app.list_vendor_payment_term_proposals(
  p_vendor_master_record_id uuid, p_actor_auth_user_id uuid, p_status_filter text default null, p_limit integer default 100, p_after_id uuid default null
)
returns setof app.vendor_payment_term_proposals
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_vendor app.vendor_profiles;
begin
  select * into v_vendor from app.vendor_profiles where master_record_id = p_vendor_master_record_id;
  if not found or not app.has_active_tenant_membership(v_vendor.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_profile_not_found: %', p_vendor_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_vendor.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_vendor.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_status_filter is not null and p_status_filter not in ('pending_approval', 'approved', 'rejected') then
    raise exception 'invalid_status_filter: %', p_status_filter using errcode = 'check_violation';
  end if;

  return query
  select p.* from app.vendor_payment_term_proposals p
  where p.vendor_master_record_id = p_vendor_master_record_id
    and (p_status_filter is null or p.status = p_status_filter)
    and (p_after_id is null or p.id > p_after_id)
  order by p.id
  limit least(coalesce(p_limit, 100), 500);
end;
$$;

create or replace function app.list_vendor_tax_identities_masked(
  p_vendor_master_record_id uuid, p_actor_auth_user_id uuid, p_status_filter text default null, p_limit integer default 100, p_after_id uuid default null
)
returns table (
  id uuid, tenant_id uuid, vendor_master_record_id uuid, tax_family_id uuid, tax_id_type text, tax_id_last4 text,
  legal_name_on_file text, status text, effective_from date, evidence_file_id uuid, is_duplicate_candidate boolean,
  proposed_by text, approved_by text, hold_reason text, rejection_reason text, deactivation_reason text,
  record_version integer, created_at timestamptz, updated_at timestamptz
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_vendor app.vendor_profiles;
begin
  select * into v_vendor from app.vendor_profiles where master_record_id = p_vendor_master_record_id;
  if not found or not app.has_active_tenant_membership(v_vendor.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_profile_not_found: %', p_vendor_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_vendor.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_vendor.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_status_filter is not null and p_status_filter not in ('draft', 'pending_approval', 'active', 'rejected', 'hold', 'deactivated') then
    raise exception 'invalid_status_filter: %', p_status_filter using errcode = 'check_violation';
  end if;

  return query
  select t.id, t.tenant_id, t.vendor_master_record_id, t.tax_family_id, t.tax_id_type, t.tax_id_last4, t.legal_name_on_file,
    t.status, t.effective_from, t.evidence_file_id,
    exists (
      select 1 from app.vendor_tax_identities d
      where d.tenant_id = t.tenant_id and d.tax_id_hash = t.tax_id_hash and d.id <> t.id
        and d.vendor_master_record_id <> t.vendor_master_record_id and d.status in ('active', 'pending_approval')
    ) as is_duplicate_candidate,
    t.proposed_by, t.approved_by, t.hold_reason, t.rejection_reason, t.deactivation_reason, t.record_version, t.created_at, t.updated_at
  from app.vendor_tax_identities t
  where t.vendor_master_record_id = p_vendor_master_record_id
    and (p_status_filter is null or t.status = p_status_filter)
    and (p_after_id is null or t.id > p_after_id)
  order by t.id
  limit least(coalesce(p_limit, 100), 500);
end;
$$;

create or replace function app.propose_vendor_payment_term_change(
  p_vendor_master_record_id uuid, p_proposed_payment_term_days integer, p_reason text, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_payment_term_proposals
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_vendor app.vendor_profiles;
  v_existing app.vendor_payment_term_proposals;
  v_proposal app.vendor_payment_term_proposals;
  v_constraint_name text;
begin
  select * into v_vendor from app.vendor_profiles where master_record_id = p_vendor_master_record_id;
  if not found or not app.has_active_tenant_membership(v_vendor.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_profile_not_found: %', p_vendor_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_vendor.tenant_id, 'PRC', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_vendor.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_proposed_payment_term_days is null or p_proposed_payment_term_days < 0 then
    raise exception 'invalid_payment_term_days: proposed_payment_term_days must be >= 0' using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to propose a payment-term change' using errcode = 'check_violation';
  end if;
  if p_proposed_payment_term_days = v_vendor.payment_term_days then
    raise exception 'no_op_proposal: proposed_payment_term_days % matches the vendor''s current payment_term_days', p_proposed_payment_term_days using errcode = 'check_violation';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.vendor_payment_term_proposals where tenant_id = v_vendor.tenant_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.vendor_master_record_id is distinct from p_vendor_master_record_id or v_existing.proposed_payment_term_days is distinct from p_proposed_payment_term_days then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different payment-term proposal', p_idempotency_key
          using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  begin
    insert into app.vendor_payment_term_proposals (
      tenant_id, vendor_master_record_id, current_payment_term_days, proposed_payment_term_days, vendor_profile_expected_version,
      reason, proposed_by, proposed_by_auth_user_id, idempotency_key, created_by
    ) values (
      v_vendor.tenant_id, p_vendor_master_record_id, v_vendor.payment_term_days, p_proposed_payment_term_days, v_vendor.record_version,
      p_reason, p_actor_label, p_actor_auth_user_id, p_idempotency_key, p_actor_label
    )
    returning * into v_proposal;
  exception
    when unique_violation then
      get stacked diagnostics v_constraint_name = constraint_name;
      if v_constraint_name = 'vendor_payment_term_proposals_idempotency_key_unique' and p_idempotency_key is not null then
        select * into v_existing from app.vendor_payment_term_proposals where tenant_id = v_vendor.tenant_id and idempotency_key = p_idempotency_key;
        if not found then
          raise;
        end if;
        if v_existing.vendor_master_record_id is distinct from p_vendor_master_record_id or v_existing.proposed_payment_term_days is distinct from p_proposed_payment_term_days then
          raise exception 'idempotency_key_conflict: idempotency key % was already used for a different payment-term proposal', p_idempotency_key
            using errcode = 'unique_violation';
        end if;
        return v_existing;
      elsif v_constraint_name = 'vendor_payment_term_proposals_pending_unique' then
        raise exception 'pending_proposal_exists: vendor % already has a pending payment-term proposal -- decide it before proposing another', p_vendor_master_record_id
          using errcode = 'check_violation';
      else
        raise;
      end if;
  end;

  perform app.capture_audit_event(
    v_vendor.tenant_id, p_actor_auth_user_id, p_actor_label, 'propose_vendor_payment_term_change',
    'app.vendor_payment_term_proposals', v_proposal.id, 'success', p_reason, null, to_jsonb(v_proposal)
  );

  return v_proposal;
end;
$$;

create or replace function app.publish_vendor_compliance_requirement(
  p_requirement_version_id uuid, p_expected_version integer, p_supersedes_version_id uuid, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_compliance_requirements
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_requirement app.vendor_compliance_requirements;
  v_superseded app.vendor_compliance_requirements;
  v_family_id uuid;
begin
  select * into v_requirement from app.vendor_compliance_requirements where id = p_requirement_version_id for update;
  if not found or not app.has_active_tenant_membership(v_requirement.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_compliance_requirement_not_found: %', p_requirement_version_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_requirement.tenant_id, 'PRC', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_requirement.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_requirement.record_version <> p_expected_version then
    raise exception 'stale_version: vendor compliance requirement % expected version % but found %', p_requirement_version_id, p_expected_version, v_requirement.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_requirement.status <> 'draft' then
    raise exception 'invalid_transition: vendor compliance requirement % is % and cannot be published', p_requirement_version_id, v_requirement.status
      using errcode = 'check_violation';
  end if;

  v_family_id := v_requirement.requirement_family_id;

  if p_supersedes_version_id is not null then
    -- `for update` (design note 13, mirrors PRC-252's own adversarial-review fix):
    -- closes the same TOCTOU class where a concurrent, independent archive call on
    -- the SAME superseded row could commit between this read and the terminal
    -- UPDATE below.
    select * into v_superseded from app.vendor_compliance_requirements where id = p_supersedes_version_id for update;
    if not found then
      raise exception 'superseded_requirement_not_found: %', p_supersedes_version_id using errcode = 'no_data_found';
    end if;
    if v_superseded.tenant_id <> v_requirement.tenant_id
      or coalesce(v_superseded.vendor_category, '') <> coalesce(v_requirement.vendor_category, '')
      or coalesce(v_superseded.service_type, '') <> coalesce(v_requirement.service_type, '')
      or v_superseded.document_type_code <> v_requirement.document_type_code
    then
      raise exception 'invalid_supersede: superseded requirement must share the same tenant/vendor_category/service_type/document_type_code' using errcode = 'check_violation';
    end if;
    if v_superseded.status <> 'published' then
      raise exception 'invalid_supersede: superseded requirement % is % (must be published)', p_supersedes_version_id, v_superseded.status using errcode = 'check_violation';
    end if;

    v_family_id := v_superseded.requirement_family_id;

    update app.vendor_compliance_requirements
    set status = 'archived', updated_at = now(), record_version = record_version + 1
    where id = p_supersedes_version_id and record_version = v_superseded.record_version and status = 'published';
    if not found then
      raise exception 'stale_version: superseded vendor compliance requirement % was concurrently modified (expected version %)', p_supersedes_version_id, v_superseded.record_version
        using errcode = 'serialization_failure';
    end if;
  end if;

  begin
    update app.vendor_compliance_requirements
    set status = 'published', supersedes_version_id = p_supersedes_version_id, requirement_family_id = v_family_id, updated_at = now(), record_version = record_version + 1
    where id = p_requirement_version_id and record_version = p_expected_version
    returning * into v_requirement;
  exception
    when unique_violation then
      raise exception 'active_requirement_exists: a published compliance requirement already exists for tenant %, scope %/%/% -- supply p_supersedes_version_id to replace it', v_requirement.tenant_id, v_requirement.vendor_category, v_requirement.service_type, v_requirement.document_type_code
        using errcode = 'check_violation';
  end;
  if not found then
    raise exception 'stale_version: vendor compliance requirement % target row was concurrently modified (expected version %)', p_requirement_version_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_requirement.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_vendor_compliance_requirement',
    'app.vendor_compliance_requirements', v_requirement.id, 'success', null, null, jsonb_build_object('supersedes_version_id', p_supersedes_version_id, 'requirement_family_id', v_family_id)
  );

  return v_requirement;
end;
$$;

create or replace function app.reactivate_vendor_bank_account(p_account_id uuid, p_expected_version integer, p_reauth_confirmed_at timestamptz, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_bank_accounts
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_account app.vendor_bank_accounts;
begin
  if p_reauth_confirmed_at is null or p_reauth_confirmed_at > now() or now() - p_reauth_confirmed_at > interval '5 minutes' then
    raise exception 'reauth_required: re-authentication must have completed within the last 5 minutes'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_account from app.vendor_bank_accounts where id = p_account_id for update;
  if not found or not app.has_active_tenant_membership(v_account.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_bank_account_not_found: %', p_account_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_account.tenant_id, 'PRC', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_account.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Maker-checker separation: whoever placed this hold may not be the one to lift it.
  if v_account.hold_by_auth_user_id is not null and v_account.hold_by_auth_user_id = p_actor_auth_user_id then
    raise exception 'self_reactivation_not_allowed: identity % placed bank account % on hold and may not also reactivate it', p_actor_auth_user_id, p_account_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_account.record_version <> p_expected_version then
    raise exception 'stale_version: vendor bank account % expected version % but found %', p_account_id, p_expected_version, v_account.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_account.status <> 'hold' then
    raise exception 'invalid_transition: vendor bank account % is % and cannot be reactivated', p_account_id, v_account.status
      using errcode = 'check_violation';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_account.vendor_master_record_id::text || ':' || v_account.account_family_id::text, 101));

  update app.vendor_bank_accounts
  set status = 'active', hold_reason = null, hold_by_auth_user_id = null, reauth_confirmed_at = p_reauth_confirmed_at, updated_at = now(), record_version = record_version + 1
  where id = p_account_id and record_version = p_expected_version
  returning * into v_account;
  if not found then
    raise exception 'stale_version: vendor bank account % target row was concurrently modified (expected version %)', p_account_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_account.tenant_id, p_actor_auth_user_id, p_actor_label, 'reactivate_vendor_bank_account',
    'app.vendor_bank_accounts', v_account.id, 'success', null, null, jsonb_build_object('status', v_account.status)
  );

  return v_account;
end;
$$;

create or replace function app.reactivate_vendor_tax_identity(p_tax_identity_id uuid, p_expected_version integer, p_reauth_confirmed_at timestamptz, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_tax_identities
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tax_identity app.vendor_tax_identities;
begin
  if p_reauth_confirmed_at is null or p_reauth_confirmed_at > now() or now() - p_reauth_confirmed_at > interval '5 minutes' then
    raise exception 'reauth_required: re-authentication must have completed within the last 5 minutes'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_tax_identity from app.vendor_tax_identities where id = p_tax_identity_id for update;
  if not found or not app.has_active_tenant_membership(v_tax_identity.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_tax_identity_not_found: %', p_tax_identity_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tax_identity.tenant_id, 'PRC', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tax_identity.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_tax_identity.hold_by_auth_user_id is not null and v_tax_identity.hold_by_auth_user_id = p_actor_auth_user_id then
    raise exception 'self_reactivation_not_allowed: identity % placed tax identity % on hold and may not also reactivate it', p_actor_auth_user_id, p_tax_identity_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_tax_identity.record_version <> p_expected_version then
    raise exception 'stale_version: vendor tax identity % expected version % but found %', p_tax_identity_id, p_expected_version, v_tax_identity.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_tax_identity.status <> 'hold' then
    raise exception 'invalid_transition: vendor tax identity % is % and cannot be reactivated', p_tax_identity_id, v_tax_identity.status
      using errcode = 'check_violation';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_tax_identity.vendor_master_record_id::text || ':' || v_tax_identity.tax_family_id::text, 102));

  update app.vendor_tax_identities
  set status = 'active', hold_reason = null, hold_by_auth_user_id = null, reauth_confirmed_at = p_reauth_confirmed_at, updated_at = now(), record_version = record_version + 1
  where id = p_tax_identity_id and record_version = p_expected_version
  returning * into v_tax_identity;
  if not found then
    raise exception 'stale_version: vendor tax identity % target row was concurrently modified (expected version %)', p_tax_identity_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_tax_identity.tenant_id, p_actor_auth_user_id, p_actor_label, 'reactivate_vendor_tax_identity',
    'app.vendor_tax_identities', v_tax_identity.id, 'success', null, null, jsonb_build_object('status', v_tax_identity.status)
  );

  return v_tax_identity;
end;
$$;

create or replace function app.recalculate_vendor_compliance_status(p_vendor_master_record_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns setof app.vendor_compliance_status
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_vendor app.vendor_profiles;
begin
  select * into v_vendor from app.vendor_profiles where master_record_id = p_vendor_master_record_id;
  if not found or not app.has_active_tenant_membership(v_vendor.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_profile_not_found: %', p_vendor_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_vendor.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_vendor.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app._recalculate_vendor_compliance_status_all_families(p_vendor_master_record_id, p_actor_label);
end;
$$;

create or replace function app.renew_vendor_compliance_document(
  p_previous_document_id uuid,
  p_file_id uuid,
  p_issue_date date,
  p_expiry_date date,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_compliance_documents
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_prev app.vendor_compliance_documents;
  v_requirement app.vendor_compliance_requirements;
  v_file app.files;
  v_new app.vendor_compliance_documents;
begin
  select * into v_prev from app.vendor_compliance_documents where id = p_previous_document_id for update;
  if not found or not app.has_active_tenant_membership(v_prev.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_compliance_document_not_found: %', p_previous_document_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_prev.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_prev.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not v_prev.is_latest_version then
    raise exception 'vendor_compliance_document_not_latest: document % is not the latest version of its lineage, renewal must start from the latest', p_previous_document_id
      using errcode = 'check_violation';
  end if;

  select * into v_requirement from app.vendor_compliance_requirements where id = v_prev.requirement_version_id;

  if p_expiry_date is not null and p_issue_date is not null and p_expiry_date < p_issue_date then
    raise exception 'inconsistent_issue_expiry_date: expiry_date % is before issue_date %', p_expiry_date, p_issue_date using errcode = 'check_violation';
  end if;
  if v_requirement.requires_expiry and p_expiry_date is null then
    raise exception 'expiry_date_required: requirement % requires an expiry date', v_prev.requirement_version_id using errcode = 'check_violation';
  end if;
  if not v_requirement.requires_expiry and p_expiry_date is not null then
    raise exception 'expiry_date_not_applicable: requirement % does not track expiry -- omit expiry_date', v_prev.requirement_version_id using errcode = 'check_violation';
  end if;

  select * into v_file from app.files where id = p_file_id;
  if not found then
    raise exception 'evidence_file_not_found: %', p_file_id using errcode = 'no_data_found';
  end if;
  if v_file.tenant_id <> v_prev.tenant_id or v_file.record_type <> 'vendor_compliance' or v_file.record_id <> v_prev.vendor_master_record_id then
    raise exception 'compliance_evidence_file_mismatch: file % was not uploaded for vendor %''s own compliance purpose in tenant %', p_file_id, v_prev.vendor_master_record_id, v_prev.tenant_id
      using errcode = 'check_violation';
  end if;
  if v_file.malware_scan_status <> 'clean' then
    raise exception 'compliance_unsafe_evidence: evidence file % has scan status % -- only clean evidence may be submitted', p_file_id, v_file.malware_scan_status
      using errcode = 'check_violation';
  end if;

  update app.vendor_compliance_documents
  set is_latest_version = false
  where id = v_prev.id;

  insert into app.vendor_compliance_documents (
    tenant_id, vendor_master_record_id, requirement_version_id, file_id, version_group_id, version_number, is_latest_version,
    issue_date, expiry_date, created_by
  ) values (
    v_prev.tenant_id, v_prev.vendor_master_record_id, v_prev.requirement_version_id, p_file_id, v_prev.version_group_id, v_prev.version_number + 1, true,
    p_issue_date, p_expiry_date, p_actor_label
  )
  returning * into v_new;

  perform app._recalculate_vendor_compliance_status_family(v_prev.vendor_master_record_id, v_requirement.requirement_family_id, p_actor_label);

  perform app.capture_audit_event(
    v_prev.tenant_id, p_actor_auth_user_id, p_actor_label, 'renew_vendor_compliance_document',
    'app.vendor_compliance_documents', v_new.id, 'success', null, to_jsonb(v_prev), to_jsonb(v_new)
  );

  return v_new;
end;
$$;

create or replace function app.request_vendor_compliance_waiver(
  p_requirement_version_id uuid, p_vendor_master_record_id uuid, p_reason text, p_valid_from date, p_valid_until date,
  p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_compliance_waivers
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_vendor app.vendor_profiles;
  v_requirement app.vendor_compliance_requirements;
  v_existing app.vendor_compliance_waivers;
  v_waiver app.vendor_compliance_waivers;
begin
  select * into v_vendor from app.vendor_profiles where master_record_id = p_vendor_master_record_id;
  if not found or not app.has_active_tenant_membership(v_vendor.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_profile_not_found: %', p_vendor_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_vendor.tenant_id, 'PRC', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_vendor.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_requirement from app.vendor_compliance_requirements where id = p_requirement_version_id and tenant_id = v_vendor.tenant_id;
  if not found then
    raise exception 'vendor_compliance_requirement_not_found: %', p_requirement_version_id using errcode = 'no_data_found';
  end if;
  if not app._vendor_compliance_requirement_applies(v_vendor, v_requirement) then
    raise exception 'requirement_not_applicable: requirement % does not apply to vendor % (category/service scope mismatch)', p_requirement_version_id, p_vendor_master_record_id
      using errcode = 'check_violation';
  end if;

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to request a compliance waiver' using errcode = 'check_violation';
  end if;
  if p_valid_from is null or p_valid_until is null or p_valid_until < p_valid_from then
    raise exception 'invalid_validity_window: valid_until must be on or after valid_from' using errcode = 'check_violation';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.vendor_compliance_waivers where tenant_id = v_vendor.tenant_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.requirement_version_id is distinct from p_requirement_version_id or v_existing.vendor_master_record_id is distinct from p_vendor_master_record_id
        or v_existing.valid_from is distinct from p_valid_from or v_existing.valid_until is distinct from p_valid_until
      then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different waiver request', p_idempotency_key
          using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  begin
    insert into app.vendor_compliance_waivers (
      tenant_id, requirement_version_id, vendor_master_record_id, reason, valid_from, valid_until,
      requested_by, requested_by_auth_user_id, idempotency_key, created_by
    ) values (
      v_vendor.tenant_id, p_requirement_version_id, p_vendor_master_record_id, p_reason, p_valid_from, p_valid_until,
      p_actor_label, p_actor_auth_user_id, p_idempotency_key, p_actor_label
    )
    returning * into v_waiver;
  exception
    when unique_violation then
      select * into v_existing from app.vendor_compliance_waivers where tenant_id = v_vendor.tenant_id and idempotency_key = p_idempotency_key;
      if not found then
        raise;
      end if;
      if v_existing.requirement_version_id is distinct from p_requirement_version_id or v_existing.vendor_master_record_id is distinct from p_vendor_master_record_id
        or v_existing.valid_from is distinct from p_valid_from or v_existing.valid_until is distinct from p_valid_until
      then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different waiver request', p_idempotency_key
          using errcode = 'unique_violation';
      end if;
      return v_existing;
  end;

  perform app.capture_audit_event(
    v_vendor.tenant_id, p_actor_auth_user_id, p_actor_label, 'request_vendor_compliance_waiver',
    'app.vendor_compliance_waivers', v_waiver.id, 'success', null, null, to_jsonb(v_waiver)
  );

  return v_waiver;
end;
$$;

create or replace function app.reveal_vendor_tax_identity_number(
  p_tax_identity_id uuid, p_reveal_reason text, p_reauth_confirmed_at timestamptz, p_actor_auth_user_id uuid, p_actor_label text, p_correlation_id uuid default null
)
returns table (tax_id text, tax_id_type text, legal_name_on_file text, status text)
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_tax_identity app.vendor_tax_identities;
  v_plaintext text;
begin
  if p_reveal_reason is null or length(trim(p_reveal_reason)) = 0 then
    raise exception 'reveal_reason_required: a non-empty, purpose-bound reason is required to reveal a tax identity' using errcode = 'check_violation';
  end if;
  if p_reauth_confirmed_at is null or p_reauth_confirmed_at > now() or now() - p_reauth_confirmed_at > interval '5 minutes' then
    raise exception 'reauth_required: re-authentication must have completed within the last 5 minutes'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_tax_identity from app.vendor_tax_identities where id = p_tax_identity_id;
  if not found or not app.has_active_tenant_membership(v_tax_identity.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_tax_identity_not_found: %', p_tax_identity_id using errcode = 'no_data_found';
  end if;

  if not app.has_prc_view_personal_data(v_tax_identity.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks PRC:View personal data for tenant %', p_actor_auth_user_id, v_tax_identity.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_plaintext := app._decrypt_vendor_financial_value(v_tax_identity.tax_id_encrypted);

  perform app.capture_audit_event(
    v_tax_identity.tenant_id, p_actor_auth_user_id, p_actor_label, 'reveal_vendor_tax_identity_number',
    'app.vendor_tax_identities', v_tax_identity.id, 'success', p_reveal_reason, null,
    jsonb_build_object('tax_id_last4', v_tax_identity.tax_id_last4, 'reveal_reason', p_reveal_reason),
    p_correlation_id
  );

  return query select v_plaintext, v_tax_identity.tax_id_type, v_tax_identity.legal_name_on_file, v_tax_identity.status;
end;
$$;

create or replace function app.revoke_vendor_compliance_waiver(p_waiver_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_compliance_waivers
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_waiver app.vendor_compliance_waivers;
  v_requirement app.vendor_compliance_requirements;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to revoke a compliance waiver' using errcode = 'check_violation';
  end if;

  select * into v_waiver from app.vendor_compliance_waivers where id = p_waiver_id for update;
  if not found or not app.has_active_tenant_membership(v_waiver.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_compliance_waiver_not_found: %', p_waiver_id using errcode = 'no_data_found';
  end if;
  if v_waiver.record_version <> p_expected_version then
    raise exception 'stale_version: vendor compliance waiver % expected version % but found %', p_waiver_id, p_expected_version, v_waiver.record_version
      using errcode = 'serialization_failure';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_waiver.tenant_id, 'PRC', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_waiver.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_waiver.status <> 'approved' then
    raise exception 'invalid_transition: vendor compliance waiver % is % and cannot be revoked', p_waiver_id, v_waiver.status using errcode = 'check_violation';
  end if;

  update app.vendor_compliance_waivers
  set status = 'revoked', decision_reason = p_reason, record_version = record_version + 1, updated_at = now()
  where id = p_waiver_id and record_version = p_expected_version
  returning * into v_waiver;
  if not found then
    raise exception 'stale_version: vendor compliance waiver % target row was concurrently modified (expected version %)', p_waiver_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  select * into v_requirement from app.vendor_compliance_requirements where id = v_waiver.requirement_version_id;
  perform app._recalculate_vendor_compliance_status_family(v_waiver.vendor_master_record_id, v_requirement.requirement_family_id, p_actor_label);

  perform app.capture_audit_event(
    v_waiver.tenant_id, p_actor_auth_user_id, p_actor_label, 'revoke_vendor_compliance_waiver',
    'app.vendor_compliance_waivers', v_waiver.id, 'success', p_reason, null, '{}'::jsonb
  );

  return v_waiver;
end;
$$;

create or replace function app.submit_vendor_bank_account_for_approval(p_account_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_bank_accounts
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_account app.vendor_bank_accounts;
begin
  select * into v_account from app.vendor_bank_accounts where id = p_account_id for update;
  if not found or not app.has_active_tenant_membership(v_account.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_bank_account_not_found: %', p_account_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_account.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_account.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_account.record_version <> p_expected_version then
    raise exception 'stale_version: vendor bank account % expected version % but found %', p_account_id, p_expected_version, v_account.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_account.status <> 'draft' then
    raise exception 'invalid_transition: vendor bank account % is % and cannot be submitted', p_account_id, v_account.status
      using errcode = 'check_violation';
  end if;

  update app.vendor_bank_accounts
  set status = 'pending_approval', updated_at = now(), record_version = record_version + 1
  where id = p_account_id and record_version = p_expected_version
  returning * into v_account;
  if not found then
    raise exception 'stale_version: vendor bank account % target row was concurrently modified (expected version %)', p_account_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_account.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_vendor_bank_account_for_approval',
    'app.vendor_bank_accounts', v_account.id, 'success', null, null, jsonb_build_object('status', v_account.status)
  );

  return v_account;
end;
$$;

create or replace function app.submit_vendor_compliance_document(
  p_vendor_master_record_id uuid,
  p_requirement_version_id uuid,
  p_file_id uuid,
  p_issue_date date,
  p_expiry_date date,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_compliance_documents
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_vendor app.vendor_profiles;
  v_requirement app.vendor_compliance_requirements;
  v_file app.files;
  v_existing app.vendor_compliance_documents;
  v_constraint_name text;
  v_document app.vendor_compliance_documents;
begin
  select * into v_vendor from app.vendor_profiles where master_record_id = p_vendor_master_record_id;
  if not found or not app.has_active_tenant_membership(v_vendor.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_profile_not_found: %', p_vendor_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_vendor.tenant_id, 'PRC', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_vendor.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_requirement from app.vendor_compliance_requirements where id = p_requirement_version_id and tenant_id = v_vendor.tenant_id;
  if not found or v_requirement.status <> 'published' then
    raise exception 'requirement_not_published: vendor compliance requirement % is not a published requirement for tenant %', p_requirement_version_id, v_vendor.tenant_id
      using errcode = 'check_violation';
  end if;
  if not app._vendor_compliance_requirement_applies(v_vendor, v_requirement) then
    raise exception 'requirement_not_applicable: requirement % does not apply to vendor % (category/service scope mismatch)', p_requirement_version_id, p_vendor_master_record_id
      using errcode = 'check_violation';
  end if;

  if p_expiry_date is not null and p_issue_date is not null and p_expiry_date < p_issue_date then
    raise exception 'inconsistent_issue_expiry_date: expiry_date % is before issue_date %', p_expiry_date, p_issue_date using errcode = 'check_violation';
  end if;
  if v_requirement.requires_expiry and p_expiry_date is null then
    raise exception 'expiry_date_required: requirement % requires an expiry date', p_requirement_version_id using errcode = 'check_violation';
  end if;
  if not v_requirement.requires_expiry and p_expiry_date is not null then
    raise exception 'expiry_date_not_applicable: requirement % does not track expiry -- omit expiry_date', p_requirement_version_id using errcode = 'check_violation';
  end if;

  -- Evidence re-validation (design note 5, mandatory pattern): re-fetch and reject
  -- on tenant mismatch, wrong record scope, or a non-clean malware scan. record_type
  -- ='vendor_compliance', record_id=the vendor's own master_record_id -- the file
  -- was uploaded "for this vendor's compliance purpose" (this task's own Sec.16/24
  -- wording for a pre-existing-upload link).
  select * into v_file from app.files where id = p_file_id;
  if not found then
    raise exception 'evidence_file_not_found: %', p_file_id using errcode = 'no_data_found';
  end if;
  if v_file.tenant_id <> v_vendor.tenant_id or v_file.record_type <> 'vendor_compliance' or v_file.record_id <> p_vendor_master_record_id then
    raise exception 'compliance_evidence_file_mismatch: file % was not uploaded for vendor %''s own compliance purpose in tenant %', p_file_id, p_vendor_master_record_id, v_vendor.tenant_id
      using errcode = 'check_violation';
  end if;
  if v_file.malware_scan_status <> 'clean' then
    raise exception 'compliance_unsafe_evidence: evidence file % has scan status % -- only clean evidence may be submitted', p_file_id, v_file.malware_scan_status
      using errcode = 'check_violation';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.vendor_compliance_documents where tenant_id = v_vendor.tenant_id and idempotency_key = p_idempotency_key;
    if found then
      -- Fix-pass addition (HIGH-severity finding, adversarial review): issue_date/
      -- expiry_date were missing from this comparison -- expiry_date is the single
      -- most consequential field in this entire capability (the sole input that
      -- flips verified/expiring_soon/expired, which in turn drives eligibility_hold),
      -- so a replay silently carrying a corrected date must be rejected, not
      -- silently ignored, exactly like every other identity-defining column here.
      if v_existing.vendor_master_record_id is distinct from p_vendor_master_record_id or v_existing.requirement_version_id is distinct from p_requirement_version_id
        or v_existing.file_id is distinct from p_file_id or v_existing.issue_date is distinct from p_issue_date or v_existing.expiry_date is distinct from p_expiry_date
      then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different compliance document submission', p_idempotency_key
          using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  begin
    insert into app.vendor_compliance_documents (
      tenant_id, vendor_master_record_id, requirement_version_id, file_id, issue_date, expiry_date, idempotency_key, created_by
    ) values (
      v_vendor.tenant_id, p_vendor_master_record_id, p_requirement_version_id, p_file_id, p_issue_date, p_expiry_date, p_idempotency_key, p_actor_label
    )
    returning * into v_document;
  exception
    when unique_violation then
      get stacked diagnostics v_constraint_name = constraint_name;
      if v_constraint_name = 'vendor_compliance_documents_idempotency_key_unique' and p_idempotency_key is not null then
        select * into v_existing from app.vendor_compliance_documents where tenant_id = v_vendor.tenant_id and idempotency_key = p_idempotency_key;
        if not found then
          raise;
        end if;
        if v_existing.vendor_master_record_id is distinct from p_vendor_master_record_id or v_existing.requirement_version_id is distinct from p_requirement_version_id
          or v_existing.file_id is distinct from p_file_id or v_existing.issue_date is distinct from p_issue_date or v_existing.expiry_date is distinct from p_expiry_date
        then
          raise exception 'idempotency_key_conflict: idempotency key % was already used for a different compliance document submission', p_idempotency_key
            using errcode = 'unique_violation';
        end if;
        return v_existing;
      elsif v_constraint_name = 'vendor_compliance_documents_one_active_slot_idx' then
        raise exception 'active_submission_exists: vendor % already has an active submission for requirement % -- use renew instead', p_vendor_master_record_id, p_requirement_version_id
          using errcode = 'check_violation';
      else
        raise;
      end if;
  end;

  perform app._recalculate_vendor_compliance_status_family(p_vendor_master_record_id, v_requirement.requirement_family_id, p_actor_label);

  perform app.capture_audit_event(
    v_vendor.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_vendor_compliance_document',
    'app.vendor_compliance_documents', v_document.id, 'success', null, null, to_jsonb(v_document)
  );

  return v_document;
end;
$$;

create or replace function app.submit_vendor_tax_identity_for_approval(p_tax_identity_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_tax_identities
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tax_identity app.vendor_tax_identities;
begin
  select * into v_tax_identity from app.vendor_tax_identities where id = p_tax_identity_id for update;
  if not found or not app.has_active_tenant_membership(v_tax_identity.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_tax_identity_not_found: %', p_tax_identity_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tax_identity.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tax_identity.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_tax_identity.record_version <> p_expected_version then
    raise exception 'stale_version: vendor tax identity % expected version % but found %', p_tax_identity_id, p_expected_version, v_tax_identity.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_tax_identity.status <> 'draft' then
    raise exception 'invalid_transition: vendor tax identity % is % and cannot be submitted', p_tax_identity_id, v_tax_identity.status
      using errcode = 'check_violation';
  end if;

  update app.vendor_tax_identities
  set status = 'pending_approval', updated_at = now(), record_version = record_version + 1
  where id = p_tax_identity_id and record_version = p_expected_version
  returning * into v_tax_identity;
  if not found then
    raise exception 'stale_version: vendor tax identity % target row was concurrently modified (expected version %)', p_tax_identity_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_tax_identity.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_vendor_tax_identity_for_approval',
    'app.vendor_tax_identities', v_tax_identity.id, 'success', null, null, jsonb_build_object('status', v_tax_identity.status)
  );

  return v_tax_identity;
end;
$$;
