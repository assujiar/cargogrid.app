-- ISS-2026-146 -- cross-tenant tenant_id disclosure via exception message text.
-- Lane: Ticketing / white-label / localization / IAM "and the rest" (the residual after the
-- 20260902100000..20260902104000 Finance/HRIS/Procurement/Ticketing/Platform-Core batch).
--
-- Root cause, unchanged from the original disclosure: a SECURITY DEFINER function looks a
-- record up by its own bare id (unscoped, because the caller does not yet know which tenant
-- owns it), THEN evaluates the actor's authority against the looked-up row's own real
-- tenant_id, and on denial raises 'insufficient_authority: ... for tenant %' interpolating
-- that genuine tenant_id -- handing it to a caller with no demonstrated relationship to that
-- tenant at all.
--
-- Fix, identical in shape to the already-merged precedent (20260902100000, ISS-2026-043/048/
-- 054, and 20260730820000 before them): fold
-- app.has_active_tenant_membership(<row>.tenant_id, <actor>) into the SAME not-found branch
-- the row-miss case already raises, reusing that branch's own generic message and
-- errcode='no_data_found'. A caller with zero relationship to the record's tenant now gets
-- byte-for-byte the error a nonexistent id already produces. A SAME-TENANT member who merely
-- lacks the ROLE authority is untouched: they still reach the insufficient_authority raise
-- below with errcode='insufficient_privilege', exactly as before. That distinction is the
-- whole point of the shape and is preserved deliberately.
--
-- No permission check is weakened. The authority check itself (app.evaluate_permission /
-- app.check_*_authority) is byte-for-byte unchanged; only a tenant-membership pre-check was
-- placed ahead of it. app.evaluate_permission has itself required
-- app.has_active_tenant_membership since 20260810300000 (it returns
-- 'not_active_tenant_member' otherwise), and every app.check_*_authority helper is a thin
-- wrapper over it -- so the added gate can never deny a caller that the authority check
-- would have allowed.
--
-- Bodies were taken from each function's CURRENT, LIVE definition -- the LAST migration in
-- filename order that defines that name, not its creating migration. 40 of them were last
-- defined by 20260831270000 (the p_client_ip widening), which DROPped the pre-p_client_ip
-- signature; the p_client_ip signature below is therefore the only live one and CREATE OR
-- REPLACE matches it exactly. Signatures, SECURITY DEFINER, search_path, volatility and
-- return types are unchanged throughout, so no grant and no public.* wrapper is affected.
--
-- Part 2 of 4: Platform core and IAM -- support access grants, white-label branding,
-- custom domains, localization, master data, webhook endpoints, enterprise SSO domain
-- claims, IP-allowlist bypass, audit export and data retention / legal hold.
--
-- 29 functions in this part.

-- app.activate_enterprise_sso_domain_claim -- live definition from 20260807000000_create_intelligence_enterprise_iam_sso.sql
create or replace function app.activate_enterprise_sso_domain_claim(
  p_claim_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.iam_domain_claims
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_claim app.iam_domain_claims;
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_claim from app.iam_domain_claims where id = p_claim_id and status = 'verified' for update;
  if not found or not app.has_active_tenant_membership(v_claim.tenant_id, p_actor_auth_user_id) then
    raise exception 'iam_domain_claim_not_verified: % is not in a verified, activatable state', p_claim_id
      using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_claim.tenant_id, 'IAM', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks IAM:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_claim.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.iam_domain_claims
  set status = 'active', activated_at = now(), activated_by = p_actor_label
  where id = p_claim_id
  returning * into v_claim;

  perform app.capture_audit_event(
    v_claim.tenant_id, p_actor_auth_user_id, p_actor_label, 'activate_enterprise_sso_domain_claim',
    'app.iam_domain_claims', v_claim.id, 'success', null, null, to_jsonb(v_claim)
  );

  return v_claim;
end;
$$;

-- app.activate_tenant_domain -- live definition from 20260717103015_create_custom_domain.sql
create or replace function app.activate_tenant_domain(
  p_domain_id uuid,
  p_actor_auth_user_id uuid,
  p_activated_by text
)
returns app.tenant_custom_domains
language plpgsql
as $$
declare
  v_before app.tenant_custom_domains;
  v_after app.tenant_custom_domains;
begin
  select * into v_before from app.tenant_custom_domains where id = p_domain_id;
  if not found or not app.has_active_tenant_membership(v_before.tenant_id, p_actor_auth_user_id) then
    raise exception 'domain_not_found: no tenant custom domain %', p_domain_id
      using errcode = 'no_data_found';
  end if;

  if not app.is_support_grant_authority(p_actor_auth_user_id, v_before.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_before.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_before.status <> 'verified' then
    raise exception 'domain_not_verified: domain % is %, only a verified domain may be activated', p_domain_id, v_before.status
      using errcode = 'check_violation';
  end if;

  update app.tenant_custom_domains
  set status = 'active', activated_at = now(), activated_by = p_activated_by
  where id = p_domain_id
  returning * into v_after;

  perform app.capture_audit_event(
    v_after.tenant_id, p_actor_auth_user_id, p_activated_by, 'activate_tenant_domain',
    'app.tenant_custom_domains', v_after.id, 'success', null, to_jsonb(v_before), to_jsonb(v_after)
  );

  return v_after;
end;
$$;

-- app.approve_ip_allowlist_bypass -- live definition from 20260807200000_create_intelligence_ip_restriction_network_access.sql
create or replace function app.approve_ip_allowlist_bypass(
  p_grant_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.ip_allowlist_bypass_grants
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_grant app.ip_allowlist_bypass_grants;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_grant from app.ip_allowlist_bypass_grants where id = p_grant_id and status = 'pending' for update;
  if not found or not app.has_active_tenant_membership(v_grant.tenant_id, p_actor_auth_user_id) then
    raise exception 'ip_bypass_not_pending: % is not a pending bypass request', p_grant_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_grant.tenant_id, 'SEC', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks SEC:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_grant.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_grant.requested_by_auth_user_id = p_actor_auth_user_id then
    raise exception 'ip_bypass_self_approval_forbidden: identity % cannot approve their own request', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.ip_allowlist_bypass_grants
  set status = 'approved', approved_by_auth_user_id = p_actor_auth_user_id, approved_by = p_actor_label, decided_at = now()
  where id = p_grant_id
  returning * into v_grant;

  perform app.capture_audit_event(
    v_grant.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_ip_allowlist_bypass',
    'app.ip_allowlist_bypass_grants', v_grant.id, 'success', null, null, to_jsonb(v_grant)
  );

  return v_grant;
end;
$$;

-- app.approve_support_access -- live definition from 20260716111315_create_support_access.sql
create or replace function app.approve_support_access(
  p_grant_id uuid,
  p_approver_auth_user_id uuid,
  p_approved_by text,
  p_expires_at timestamptz default null
)
returns app.support_access_grants
language plpgsql
as $$
declare
  v_grant app.support_access_grants;
  v_updated app.support_access_grants;
begin
  select * into v_grant from app.support_access_grants where id = p_grant_id;
  if not found or not app.has_active_tenant_membership(v_grant.tenant_id, p_approver_auth_user_id) then
    raise exception 'grant_not_found: no support access grant %', p_grant_id using errcode = 'no_data_found';
  end if;

  if v_grant.status <> 'pending_approval' then
    raise exception 'invalid_grant_status: grant % is %, expected pending_approval', p_grant_id, v_grant.status
      using errcode = 'check_violation';
  end if;

  -- Self-escalation guard, mirroring PLT-111's assign_role() pattern: the grantee cannot
  -- approve their own request into their own support access.
  if p_approver_auth_user_id = v_grant.grantee_auth_user_id then
    raise exception 'self_approval_forbidden: identity % cannot approve their own support access grant', p_approver_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.is_support_grant_authority(p_approver_auth_user_id, v_grant.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_approver_auth_user_id, v_grant.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.support_access_grants
  set status = 'approved',
      granted_at = now(),
      approved_by = p_approved_by,
      expires_at = coalesce(p_expires_at, expires_at)
  where id = p_grant_id
  returning * into v_updated;

  insert into app.support_access_events (grant_id, tenant_id, grantee_auth_user_id, event_type, actor, detail)
  values (v_updated.id, v_updated.tenant_id, v_updated.grantee_auth_user_id, 'approved', p_approved_by, null);

  return v_updated;
end;
$$;

-- app.deactivate_master_record -- live definition from 20260717120000_create_master_data.sql
create or replace function app.deactivate_master_record(
  p_record_id uuid,
  p_actor_auth_user_id uuid,
  p_reason text,
  p_actor_label text
)
returns app.master_records
language plpgsql
as $$
declare
  v_before app.master_records;
  v_after app.master_records;
begin
  select * into v_before from app.master_records where id = p_record_id;
  if not found or not app.has_active_tenant_membership(v_before.tenant_id, p_actor_auth_user_id) then
    raise exception 'master_record_not_found: no master record %', p_record_id
      using errcode = 'no_data_found';
  end if;

  if v_before.tenant_id is null then
    if not app.is_supreme_admin(p_actor_auth_user_id) then
      raise exception 'insufficient_authority: only Supreme Admin may deactivate a global-scoped master record'
        using errcode = 'insufficient_privilege';
    end if;
  else
    if not app.is_support_grant_authority(p_actor_auth_user_id, v_before.tenant_id) then
      raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_before.tenant_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  if v_before.canonical_status <> 'active' then
    raise exception 'master_record_not_active: record % is %, only an active record may be deactivated', p_record_id, v_before.canonical_status
      using errcode = 'check_violation';
  end if;

  update app.master_records
  set canonical_status = 'deactivated', deactivated_at = now(), deactivated_by = p_actor_label, deactivated_reason = p_reason, effective_to = now()
  where id = p_record_id
  returning * into v_after;

  perform app.capture_audit_event(
    v_after.tenant_id, p_actor_auth_user_id, p_actor_label, 'deactivate_master_record',
    'app.master_records', v_after.id, 'success', p_reason, to_jsonb(v_before), to_jsonb(v_after)
  );

  return v_after;
end;
$$;

-- app.deny_support_access -- live definition from 20260716111315_create_support_access.sql
create or replace function app.deny_support_access(
  p_grant_id uuid,
  p_denier_auth_user_id uuid,
  p_denied_by text,
  p_reason text
)
returns app.support_access_grants
language plpgsql
as $$
declare
  v_grant app.support_access_grants;
  v_updated app.support_access_grants;
begin
  select * into v_grant from app.support_access_grants where id = p_grant_id;
  if not found or not app.has_active_tenant_membership(v_grant.tenant_id, p_denier_auth_user_id) then
    raise exception 'grant_not_found: no support access grant %', p_grant_id using errcode = 'no_data_found';
  end if;

  if v_grant.status <> 'pending_approval' then
    raise exception 'invalid_grant_status: grant % is %, expected pending_approval', p_grant_id, v_grant.status
      using errcode = 'check_violation';
  end if;

  if not app.is_support_grant_authority(p_denier_auth_user_id, v_grant.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_denier_auth_user_id, v_grant.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.support_access_grants
  set status = 'denied', denied_at = now(), denied_by = p_denied_by, denial_reason = p_reason
  where id = p_grant_id
  returning * into v_updated;

  insert into app.support_access_events (grant_id, tenant_id, grantee_auth_user_id, event_type, actor, detail)
  values (v_updated.id, v_updated.tenant_id, v_updated.grantee_auth_user_id, 'denied', p_denied_by, p_reason);

  return v_updated;
end;
$$;

-- app.disable_enterprise_sso_domain_claim -- live definition from 20260807000000_create_intelligence_enterprise_iam_sso.sql
create or replace function app.disable_enterprise_sso_domain_claim(
  p_claim_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.iam_domain_claims
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_claim app.iam_domain_claims;
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_claim from app.iam_domain_claims where id = p_claim_id and status in ('verified', 'active') for update;
  if not found or not app.has_active_tenant_membership(v_claim.tenant_id, p_actor_auth_user_id) then
    raise exception 'iam_domain_claim_not_disableable: % is not in a verified/active state', p_claim_id
      using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_claim.tenant_id, 'IAM', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks IAM:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_claim.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.iam_domain_claims
  set status = 'disabled', disabled_at = now(), disabled_by = p_actor_label, disabled_reason = p_reason
  where id = p_claim_id
  returning * into v_claim;

  perform app.capture_audit_event(
    v_claim.tenant_id, p_actor_auth_user_id, p_actor_label, 'disable_enterprise_sso_domain_claim',
    'app.iam_domain_claims', v_claim.id, 'success', p_reason, null, to_jsonb(v_claim)
  );

  return v_claim;
end;
$$;

-- app.disable_tenant_domain -- live definition from 20260717103015_create_custom_domain.sql
create or replace function app.disable_tenant_domain(
  p_domain_id uuid,
  p_actor_auth_user_id uuid,
  p_reason text,
  p_disabled_by text
)
returns app.tenant_custom_domains
language plpgsql
as $$
declare
  v_before app.tenant_custom_domains;
  v_after app.tenant_custom_domains;
begin
  select * into v_before from app.tenant_custom_domains where id = p_domain_id;
  if not found or not app.has_active_tenant_membership(v_before.tenant_id, p_actor_auth_user_id) then
    raise exception 'domain_not_found: no tenant custom domain %', p_domain_id
      using errcode = 'no_data_found';
  end if;

  if not app.is_support_grant_authority(p_actor_auth_user_id, v_before.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_before.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_before.status not in ('verified', 'active') then
    raise exception 'domain_not_disableable: domain % is %, only a verified or active domain may be disabled', p_domain_id, v_before.status
      using errcode = 'check_violation';
  end if;

  update app.tenant_custom_domains
  set status = 'disabled', disabled_at = now(), disabled_by = p_disabled_by, disabled_reason = p_reason
  where id = p_domain_id
  returning * into v_after;

  perform app.capture_audit_event(
    v_after.tenant_id, p_actor_auth_user_id, p_disabled_by, 'disable_tenant_domain',
    'app.tenant_custom_domains', v_after.id, 'success', p_reason, to_jsonb(v_before), to_jsonb(v_after)
  );

  return v_after;
end;
$$;

-- app.disable_webhook_endpoint -- live definition from 20260719150000_create_api_key_webhook_primitives.sql
create or replace function app.disable_webhook_endpoint(
  p_endpoint_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.webhook_endpoints
language plpgsql
as $$
declare
  v_endpoint app.webhook_endpoints;
  v_updated app.webhook_endpoints;
begin
  select * into v_endpoint from app.webhook_endpoints where id = p_endpoint_id;
  if not found or not app.has_active_tenant_membership(v_endpoint.tenant_id, p_actor_auth_user_id) then
    raise exception 'webhook_endpoint_not_found: no endpoint %', p_endpoint_id using errcode = 'no_data_found';
  end if;

  if not app.check_api_webhook_admin_authority(v_endpoint.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks authority to manage webhook endpoints for tenant %', p_actor_auth_user_id, v_endpoint.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_endpoint.status = 'disabled' then
    return v_endpoint;
  end if;

  update app.webhook_endpoints
  set status = 'disabled', auto_disabled_at = now(), disabled_reason = coalesce(p_reason, 'manual disable')
  where id = p_endpoint_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'disable_webhook_endpoint',
    'app.webhook_endpoints', v_updated.id, 'success', p_reason,
    jsonb_build_object('status', v_endpoint.status), jsonb_build_object('status', v_updated.status)
  );

  return v_updated;
end;
$$;

-- app.discard_tenant_brand_draft -- live definition from 20260717090512_create_white_label.sql
create or replace function app.discard_tenant_brand_draft(
  p_version_id uuid,
  p_actor_auth_user_id uuid,
  p_reason text,
  p_actor_label text
)
returns app.tenant_brand_versions
language plpgsql
as $$
declare
  v_version app.tenant_brand_versions;
  v_updated app.tenant_brand_versions;
begin
  select * into v_version from app.tenant_brand_versions where id = p_version_id;
  if not found or not app.has_active_tenant_membership(v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'brand_version_not_found: no tenant brand version %', p_version_id
      using errcode = 'no_data_found';
  end if;

  if not app.is_support_grant_authority(p_actor_auth_user_id, v_version.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_version.status <> 'draft' then
    raise exception 'brand_version_not_draft: version % is %, only a draft may be discarded', p_version_id, v_version.status
      using errcode = 'check_violation';
  end if;

  update app.tenant_brand_versions
  set status = 'archived', archived_at = now(), archived_reason = coalesce(p_reason, 'discarded')
  where id = p_version_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'discard_tenant_brand_draft',
    'app.tenant_brand_versions', v_updated.id, 'success', p_reason, to_jsonb(v_version), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

-- app.discard_tenant_locale_draft -- live definition from 20260717112000_create_localization.sql
create or replace function app.discard_tenant_locale_draft(
  p_version_id uuid,
  p_actor_auth_user_id uuid,
  p_reason text,
  p_actor_label text
)
returns app.tenant_locale_versions
language plpgsql
as $$
declare
  v_version app.tenant_locale_versions;
  v_updated app.tenant_locale_versions;
begin
  select * into v_version from app.tenant_locale_versions where id = p_version_id;
  if not found or not app.has_active_tenant_membership(v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'locale_version_not_found: no tenant locale version %', p_version_id
      using errcode = 'no_data_found';
  end if;

  if not app.is_support_grant_authority(p_actor_auth_user_id, v_version.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_version.status <> 'draft' then
    raise exception 'locale_version_not_draft: version % is %, only a draft may be discarded', p_version_id, v_version.status
      using errcode = 'check_violation';
  end if;

  update app.tenant_locale_versions
  set status = 'archived', archived_at = now(), archived_reason = coalesce(p_reason, 'discarded')
  where id = p_version_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'discard_tenant_locale_draft',
    'app.tenant_locale_versions', v_updated.id, 'success', p_reason, to_jsonb(v_version), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

-- app.get_audit_export -- live definition from 20260807300000_create_intelligence_advanced_audit_impersonation.sql
create or replace function app.get_audit_export(
  p_request_id uuid,
  p_actor_auth_user_id uuid
)
returns app.audit_export_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_request app.audit_export_requests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_request from app.audit_export_requests where id = p_request_id;
  if not found or not app.has_active_tenant_membership(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'audit_export_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;

  if not app.is_support_grant_authority(p_actor_auth_user_id, v_request.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_request.status = 'ready' and v_request.expires_at < now() then
    update app.audit_export_requests set status = 'expired', result_payload = null where id = p_request_id
    returning * into v_request;
  end if;

  return v_request;
end;
$$;

-- app.get_retention_archive_request -- live definition from 20260807500000_create_intelligence_data_retention_archival.sql
create or replace function app.get_retention_archive_request(p_request_id uuid, p_actor_auth_user_id uuid)
returns app.retention_archive_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_request app.retention_archive_requests;
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_request from app.retention_archive_requests where id = p_request_id;
  if not found or not app.has_active_tenant_membership(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'retention_archive_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'RET', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks RET:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return v_request;
end;
$$;

-- app.list_audit_logs_for_support_session -- live definition from 20260807300000_create_intelligence_advanced_audit_impersonation.sql
create or replace function app.list_audit_logs_for_support_session(
  p_requester_auth_user_id uuid,
  p_grant_id uuid,
  p_limit integer default 200
)
returns setof app.audit_logs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_grant app.support_access_grants;
  v_limit integer;
begin
  perform app.assert_actor_is_session_identity(p_requester_auth_user_id);

  select * into v_grant from app.support_access_grants where id = p_grant_id;
  if not found or not app.has_active_tenant_membership(v_grant.tenant_id, p_requester_auth_user_id) then
    raise exception 'support_access_grant_not_found: %', p_grant_id using errcode = 'no_data_found';
  end if;

  if not app.is_support_grant_authority(p_requester_auth_user_id, v_grant.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_requester_auth_user_id, v_grant.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 200), 1), 1000);

  return query
    select * from app.audit_logs
    where support_access_grant_id = p_grant_id
    order by occurred_at asc, id asc
    limit v_limit;
end;
$$;

-- app.merge_master_records -- live definition from 20260717120000_create_master_data.sql
create or replace function app.merge_master_records(
  p_source_id uuid,
  p_target_id uuid,
  p_actor_auth_user_id uuid,
  p_reason text,
  p_actor_label text
)
returns app.master_records
language plpgsql
as $$
declare
  v_source app.master_records;
  v_target app.master_records;
  v_merged_aliases jsonb;
  v_updated_target app.master_records;
begin
  if p_source_id = p_target_id then
    raise exception 'invalid_merge: cannot merge a master record into itself'
      using errcode = 'check_violation';
  end if;

  select * into v_source from app.master_records where id = p_source_id;
  if not found or not app.has_active_tenant_membership(v_source.tenant_id, p_actor_auth_user_id) then
    raise exception 'master_record_not_found: no master record %', p_source_id
      using errcode = 'no_data_found';
  end if;

  select * into v_target from app.master_records where id = p_target_id;
  if not found then
    raise exception 'master_record_not_found: no master record %', p_target_id
      using errcode = 'no_data_found';
  end if;

  if v_source.master_type_code <> v_target.master_type_code or v_source.tenant_id is distinct from v_target.tenant_id then
    raise exception 'invalid_merge: source and target must share the same master type and tenant scope'
      using errcode = 'check_violation';
  end if;

  if v_source.canonical_status <> 'active' or v_target.canonical_status <> 'active' then
    raise exception 'invalid_merge: both source and target must be active (source=%, target=%)', v_source.canonical_status, v_target.canonical_status
      using errcode = 'check_violation';
  end if;

  if v_source.tenant_id is null then
    if not app.is_supreme_admin(p_actor_auth_user_id) then
      raise exception 'insufficient_authority: only Supreme Admin may merge a global-scoped master record'
        using errcode = 'insufficient_privilege';
    end if;
  else
    if not app.is_support_grant_authority(p_actor_auth_user_id, v_source.tenant_id) then
      raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_source.tenant_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  v_merged_aliases := v_target.aliases || v_source.aliases || jsonb_build_array(v_source.code);
  if jsonb_array_length(v_merged_aliases) > 20 then
    v_merged_aliases := (select jsonb_agg(elem) from (select elem from jsonb_array_elements(v_merged_aliases) elem limit 20) sub);
  end if;

  update app.master_records
  set aliases = v_merged_aliases
  where id = p_target_id
  returning * into v_updated_target;

  update app.master_records
  set canonical_status = 'merged', merged_into_id = p_target_id, merged_at = now(), merged_by = p_actor_label, effective_to = now()
  where id = p_source_id;

  perform app.capture_audit_event(
    v_source.tenant_id, p_actor_auth_user_id, p_actor_label, 'merge_master_records',
    'app.master_records', p_source_id, 'success', p_reason, to_jsonb(v_source), jsonb_build_object('merged_into_id', p_target_id)
  );

  return v_updated_target;
end;
$$;

-- app.publish_tenant_brand_version -- live definition from 20260717090512_create_white_label.sql
create or replace function app.publish_tenant_brand_version(
  p_version_id uuid,
  p_actor_auth_user_id uuid,
  p_effective_from timestamptz,
  p_actor_label text
)
returns app.tenant_brand_versions
language plpgsql
as $$
declare
  v_version app.tenant_brand_versions;
  v_prior_published app.tenant_brand_versions;
  v_updated app.tenant_brand_versions;
  v_contrast numeric;
begin
  select * into v_version from app.tenant_brand_versions where id = p_version_id;
  if not found or not app.has_active_tenant_membership(v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'brand_version_not_found: no tenant brand version %', p_version_id
      using errcode = 'no_data_found';
  end if;

  if not app.is_support_grant_authority(p_actor_auth_user_id, v_version.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_version.status <> 'draft' then
    raise exception 'brand_version_not_draft: version % is %, only a draft may be published', p_version_id, v_version.status
      using errcode = 'check_violation';
  end if;

  if v_version.tokens ? 'primary' then
    v_contrast := app.hex_color_contrast_ratio(v_version.tokens ->> 'primary', '#fafafa');
    if v_contrast < 4.5 then
      raise exception 'insufficient_contrast: primary color contrast ratio % is below the 4.5:1 WCAG AA minimum', v_contrast
        using errcode = 'check_violation';
    end if;
  end if;

  select * into v_prior_published from app.tenant_brand_versions where tenant_id = v_version.tenant_id and status = 'published';
  if found then
    update app.tenant_brand_versions
    set status = 'archived', archived_at = now(), archived_reason = 'superseded by a newer published version'
    where id = v_prior_published.id;
  end if;

  update app.tenant_brand_versions
  set status = 'published',
      published_by = p_actor_label,
      published_at = now(),
      effective_from = coalesce(p_effective_from, now()),
      contrast_validated = true,
      contrast_report = case when v_contrast is not null
        then jsonb_build_object('primary_vs_neutral_50', v_contrast, 'threshold', 4.5, 'checked_at', now())
        else contrast_report
      end
  where id = p_version_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_tenant_brand_version',
    'app.tenant_brand_versions', v_updated.id, 'success', null, to_jsonb(v_version), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

-- app.publish_tenant_locale_version -- live definition from 20260717112000_create_localization.sql
create or replace function app.publish_tenant_locale_version(
  p_version_id uuid,
  p_actor_auth_user_id uuid,
  p_effective_from timestamptz,
  p_actor_label text
)
returns app.tenant_locale_versions
language plpgsql
as $$
declare
  v_version app.tenant_locale_versions;
  v_prior_published app.tenant_locale_versions;
  v_updated app.tenant_locale_versions;
begin
  select * into v_version from app.tenant_locale_versions where id = p_version_id;
  if not found or not app.has_active_tenant_membership(v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'locale_version_not_found: no tenant locale version %', p_version_id
      using errcode = 'no_data_found';
  end if;

  if not app.is_support_grant_authority(p_actor_auth_user_id, v_version.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_version.status <> 'draft' then
    raise exception 'locale_version_not_draft: version % is %, only a draft may be published', p_version_id, v_version.status
      using errcode = 'check_violation';
  end if;

  select * into v_prior_published from app.tenant_locale_versions where tenant_id = v_version.tenant_id and status = 'published';
  if found then
    update app.tenant_locale_versions
    set status = 'archived', archived_at = now(), archived_reason = 'superseded by a newer published version'
    where id = v_prior_published.id;
  end if;

  update app.tenant_locale_versions
  set status = 'published', published_by = p_actor_label, published_at = now(), effective_from = coalesce(p_effective_from, now())
  where id = p_version_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_tenant_locale_version',
    'app.tenant_locale_versions', v_updated.id, 'success', null, to_jsonb(v_version), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

-- app.reenable_webhook_endpoint -- live definition from 20260719150000_create_api_key_webhook_primitives.sql
create or replace function app.reenable_webhook_endpoint(
  p_endpoint_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.webhook_endpoints
language plpgsql
as $$
declare
  v_endpoint app.webhook_endpoints;
  v_updated app.webhook_endpoints;
begin
  select * into v_endpoint from app.webhook_endpoints where id = p_endpoint_id;
  if not found or not app.has_active_tenant_membership(v_endpoint.tenant_id, p_actor_auth_user_id) then
    raise exception 'webhook_endpoint_not_found: no endpoint %', p_endpoint_id using errcode = 'no_data_found';
  end if;

  if not app.check_api_webhook_admin_authority(v_endpoint.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks authority to manage webhook endpoints for tenant %', p_actor_auth_user_id, v_endpoint.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.webhook_endpoints
  set status = 'active', consecutive_failure_count = 0, auto_disabled_at = null, disabled_reason = null
  where id = p_endpoint_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'reenable_webhook_endpoint',
    'app.webhook_endpoints', v_updated.id, 'success', null,
    jsonb_build_object('status', v_endpoint.status), jsonb_build_object('status', v_updated.status)
  );

  return v_updated;
end;
$$;

-- app.reject_tenant_domain -- live definition from 20260717103015_create_custom_domain.sql
create or replace function app.reject_tenant_domain(
  p_domain_id uuid,
  p_actor_auth_user_id uuid,
  p_reason text,
  p_rejected_by text
)
returns app.tenant_custom_domains
language plpgsql
as $$
declare
  v_before app.tenant_custom_domains;
  v_after app.tenant_custom_domains;
begin
  select * into v_before from app.tenant_custom_domains where id = p_domain_id;
  if not found or not app.has_active_tenant_membership(v_before.tenant_id, p_actor_auth_user_id) then
    raise exception 'domain_not_found: no tenant custom domain %', p_domain_id
      using errcode = 'no_data_found';
  end if;

  if not app.is_support_grant_authority(p_actor_auth_user_id, v_before.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_before.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_before.status <> 'pending_verification' then
    raise exception 'domain_not_pending: domain % is %, only a pending_verification domain may be rejected', p_domain_id, v_before.status
      using errcode = 'check_violation';
  end if;

  update app.tenant_custom_domains
  set status = 'rejected', rejected_at = now(), rejected_by = p_rejected_by, rejected_reason = p_reason
  where id = p_domain_id
  returning * into v_after;

  perform app.capture_audit_event(
    v_after.tenant_id, p_actor_auth_user_id, p_rejected_by, 'reject_tenant_domain',
    'app.tenant_custom_domains', v_after.id, 'success', p_reason, to_jsonb(v_before), to_jsonb(v_after)
  );

  return v_after;
end;
$$;

-- app.release_legal_hold -- live definition from 20260807500000_create_intelligence_data_retention_archival.sql
create or replace function app.release_legal_hold(
  p_hold_id uuid,
  p_release_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.legal_holds
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_hold app.legal_holds;
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_hold from app.legal_holds where id = p_hold_id and status = 'active' for update;
  if not found or not app.has_active_tenant_membership(v_hold.tenant_id, p_actor_auth_user_id) then
    raise exception 'legal_hold_not_active: % is not an active legal hold', p_hold_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_hold.tenant_id, 'RET', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks RET:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_hold.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_hold.placed_by_auth_user_id = p_actor_auth_user_id then
    raise exception 'legal_hold_self_release_forbidden: identity % cannot release a hold they themselves placed', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.legal_holds
  set status = 'released', released_by_auth_user_id = p_actor_auth_user_id, released_by = p_actor_label, released_at = now(), release_reason = p_release_reason
  where id = p_hold_id
  returning * into v_hold;

  perform app.capture_audit_event(
    v_hold.tenant_id, p_actor_auth_user_id, p_actor_label, 'release_legal_hold',
    'app.legal_holds', v_hold.id, 'success', null, null, to_jsonb(v_hold)
  );

  return v_hold;
end;
$$;

-- app.resolve_enterprise_sso_claims -- live definition from 20260807000000_create_intelligence_enterprise_iam_sso.sql
create or replace function app.resolve_enterprise_sso_claims(
  p_connection_id uuid,
  p_subject_claim text,
  p_raw_email_claim text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.iam_sso_login_attempts
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_connection app.integration_connections;
  v_decision app.rbac_decision;
  v_email text;
  v_claim app.iam_domain_claims;
  v_matches integer;
  v_user app.users;
  v_identity app.tenant_user_identities;
  v_outcome text;
  v_resolved_auth_user_id uuid;
  v_attempt app.iam_sso_login_attempts;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_connection from app.integration_connections where id = p_connection_id;
  if not found or not app.has_active_tenant_membership(v_connection.tenant_id, p_actor_auth_user_id) then
    raise exception 'iam_connection_not_found: %', p_connection_id using errcode = 'no_data_found';
  end if;
  if v_connection.adapter_code not in ('enterprise_sso_oidc', 'enterprise_sso_saml') then
    raise exception 'iam_connection_wrong_adapter: % is not an enterprise SSO connection', p_connection_id
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_connection.tenant_id, 'IAM', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks IAM:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_connection.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if coalesce(length(trim(p_subject_claim)), 0) = 0 then
    raise exception 'iam_missing_subject_claim: a non-empty subject claim is required' using errcode = 'check_violation';
  end if;

  v_email := app._parse_iam_email_claim(p_raw_email_claim);

  if v_connection.status = 'disabled' then
    v_outcome := 'connection_not_active';
  elsif v_email is null then
    v_outcome := 'invalid_email_claim';
  else
    select * into v_claim
    from app.iam_domain_claims
    where connection_id = p_connection_id and status = 'active'
      and email_domain = app.normalize_domain_hostname(split_part(v_email, '@', 2));

    if not found then
      v_outcome := 'no_domain_claim';
    else
      select count(*) into v_matches from app.users where tenant_id = v_connection.tenant_id and lower(email) = v_email;
      if v_matches = 0 then
        v_outcome := 'no_user_match';
      elsif v_matches > 1 then
        v_outcome := 'ambiguous_match';
      else
        select * into v_user from app.users where tenant_id = v_connection.tenant_id and lower(email) = v_email;
        select * into v_identity from app.tenant_user_identities where auth_user_id = v_user.auth_user_id and tenant_id = v_connection.tenant_id;
        if not found or v_identity.status <> 'active' then
          v_outcome := 'deprovisioned';
        else
          v_outcome := 'matched';
          v_resolved_auth_user_id := v_user.auth_user_id;
        end if;
      end if;
    end if;
  end if;

  insert into app.iam_sso_login_attempts (
    tenant_id, connection_id, domain_claim_id, subject_claim, email_claim,
    resolved_auth_user_id, outcome, resolved_by_auth_user_id
  ) values (
    v_connection.tenant_id, p_connection_id, v_claim.id, p_subject_claim, p_raw_email_claim,
    v_resolved_auth_user_id, v_outcome, p_actor_auth_user_id
  )
  returning * into v_attempt;

  perform app.capture_audit_event(
    v_connection.tenant_id, p_actor_auth_user_id, p_actor_label, 'resolve_enterprise_sso_claims',
    'app.iam_sso_login_attempts', v_attempt.id, 'success', v_outcome, null,
    jsonb_build_object('connection_id', p_connection_id, 'outcome', v_outcome)
  );

  return v_attempt;
end;
$$;

-- app.revoke_support_access -- live definition from 20260716113048_create_audit_trail.sql
create or replace function app.revoke_support_access(
  p_grant_id uuid,
  p_revoker_auth_user_id uuid,
  p_revoked_by text,
  p_reason text
)
returns app.support_access_grants
language plpgsql
as $$
declare
  v_grant app.support_access_grants;
  v_updated app.support_access_grants;
  v_open_session app.support_access_sessions;
begin
  select * into v_grant from app.support_access_grants where id = p_grant_id;
  if not found or not app.has_active_tenant_membership(v_grant.tenant_id, p_revoker_auth_user_id) then
    raise exception 'grant_not_found: no support access grant %', p_grant_id using errcode = 'no_data_found';
  end if;

  if v_grant.status = 'revoked' then
    return v_grant;
  end if;

  if v_grant.status <> 'approved' then
    raise exception 'invalid_grant_status: grant % is %, only an approved grant can be revoked', p_grant_id, v_grant.status
      using errcode = 'check_violation';
  end if;

  if not app.is_support_grant_authority(p_revoker_auth_user_id, v_grant.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_revoker_auth_user_id, v_grant.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.support_access_grants
  set status = 'revoked', revoked_at = now(), revoked_by = p_revoked_by, revoked_reason = p_reason
  where id = p_grant_id
  returning * into v_updated;

  select * into v_open_session
  from app.support_access_sessions
  where grant_id = p_grant_id and ended_at is null;

  if found then
    update app.support_access_sessions
    set ended_at = now(), ended_reason = 'revoked'
    where id = v_open_session.id;

    insert into app.support_access_events (grant_id, session_id, tenant_id, grantee_auth_user_id, event_type, actor, detail)
    values (v_updated.id, v_open_session.id, v_updated.tenant_id, v_updated.grantee_auth_user_id, 'session_ended', p_revoked_by, 'ended by kill switch');
  end if;

  insert into app.support_access_events (grant_id, tenant_id, grantee_auth_user_id, event_type, actor, detail)
  values (v_updated.id, v_updated.tenant_id, v_updated.grantee_auth_user_id, 'revoked', p_revoked_by, p_reason);

  perform app.capture_audit_event(
    v_updated.tenant_id, p_revoker_auth_user_id, p_revoked_by, 'revoke_support_access',
    'app.support_access_grants', v_updated.id, 'success', p_reason,
    to_jsonb(v_grant), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

-- app.rollback_tenant_brand_version -- live definition from 20260717090512_create_white_label.sql
create or replace function app.rollback_tenant_brand_version(
  p_target_version_id uuid,
  p_actor_auth_user_id uuid,
  p_reason text,
  p_actor_label text
)
returns app.tenant_brand_versions
language plpgsql
as $$
declare
  v_target app.tenant_brand_versions;
  v_contrast numeric;
  v_next_version integer;
  v_new_row app.tenant_brand_versions;
  v_prior_published app.tenant_brand_versions;
  v_published app.tenant_brand_versions;
begin
  select * into v_target from app.tenant_brand_versions where id = p_target_version_id;
  if not found or not app.has_active_tenant_membership(v_target.tenant_id, p_actor_auth_user_id) then
    raise exception 'brand_version_not_found: no tenant brand version %', p_target_version_id
      using errcode = 'no_data_found';
  end if;

  if v_target.status = 'draft' then
    raise exception 'cannot_rollback_draft: version % is still a draft, nothing stable to roll back to', p_target_version_id
      using errcode = 'check_violation';
  end if;

  if not app.is_support_grant_authority(p_actor_auth_user_id, v_target.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_target.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_target.tokens ? 'primary' then
    v_contrast := app.hex_color_contrast_ratio(v_target.tokens ->> 'primary', '#fafafa');
    if v_contrast < 4.5 then
      raise exception 'insufficient_contrast: primary color contrast ratio % is below the 4.5:1 WCAG AA minimum', v_contrast
        using errcode = 'check_violation';
    end if;
  end if;

  select coalesce(max(version_number), 0) + 1 into v_next_version from app.tenant_brand_versions where tenant_id = v_target.tenant_id;

  insert into app.tenant_brand_versions (
    tenant_id, version_number, tokens, logo_asset_url, email_sender_name, email_logo_asset_url,
    document_template_refs, cloned_from_version_id, rollback_of_version_id, created_by
  )
  values (
    v_target.tenant_id, v_next_version, v_target.tokens, v_target.logo_asset_url, v_target.email_sender_name,
    v_target.email_logo_asset_url, v_target.document_template_refs, p_target_version_id, p_target_version_id, p_actor_label
  )
  returning * into v_new_row;

  select * into v_prior_published from app.tenant_brand_versions where tenant_id = v_target.tenant_id and status = 'published';
  if found then
    update app.tenant_brand_versions
    set status = 'archived', archived_at = now(), archived_reason = 'superseded by rollback to version ' || v_target.version_number
    where id = v_prior_published.id;
  end if;

  update app.tenant_brand_versions
  set status = 'published',
      published_by = p_actor_label,
      published_at = now(),
      effective_from = now(),
      contrast_validated = true,
      contrast_report = jsonb_build_object('rollback_of_version_number', v_target.version_number, 'checked_at', now())
  where id = v_new_row.id
  returning * into v_published;

  perform app.capture_audit_event(
    v_published.tenant_id, p_actor_auth_user_id, p_actor_label, 'rollback_tenant_brand_version',
    'app.tenant_brand_versions', v_published.id, 'success', p_reason, to_jsonb(v_target), to_jsonb(v_published)
  );

  return v_published;
end;
$$;

-- app.rollback_tenant_locale_version -- live definition from 20260717112000_create_localization.sql
create or replace function app.rollback_tenant_locale_version(
  p_target_version_id uuid,
  p_actor_auth_user_id uuid,
  p_reason text,
  p_actor_label text
)
returns app.tenant_locale_versions
language plpgsql
as $$
declare
  v_target app.tenant_locale_versions;
  v_next_version integer;
  v_new_row app.tenant_locale_versions;
  v_prior_published app.tenant_locale_versions;
  v_published app.tenant_locale_versions;
begin
  select * into v_target from app.tenant_locale_versions where id = p_target_version_id;
  if not found or not app.has_active_tenant_membership(v_target.tenant_id, p_actor_auth_user_id) then
    raise exception 'locale_version_not_found: no tenant locale version %', p_target_version_id
      using errcode = 'no_data_found';
  end if;

  if v_target.status = 'draft' then
    raise exception 'cannot_rollback_draft: version % is still a draft, nothing stable to roll back to', p_target_version_id
      using errcode = 'check_violation';
  end if;

  if not app.is_support_grant_authority(p_actor_auth_user_id, v_target.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_target.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select coalesce(max(version_number), 0) + 1 into v_next_version from app.tenant_locale_versions where tenant_id = v_target.tenant_id;

  insert into app.tenant_locale_versions (
    tenant_id, version_number, default_locale, default_timezone, default_currency,
    terminology_overrides, cloned_from_version_id, rollback_of_version_id, created_by
  )
  values (
    v_target.tenant_id, v_next_version, v_target.default_locale, v_target.default_timezone, v_target.default_currency,
    v_target.terminology_overrides, p_target_version_id, p_target_version_id, p_actor_label
  )
  returning * into v_new_row;

  select * into v_prior_published from app.tenant_locale_versions where tenant_id = v_target.tenant_id and status = 'published';
  if found then
    update app.tenant_locale_versions
    set status = 'archived', archived_at = now(), archived_reason = 'superseded by rollback to version ' || v_target.version_number
    where id = v_prior_published.id;
  end if;

  update app.tenant_locale_versions
  set status = 'published', published_by = p_actor_label, published_at = now(), effective_from = now()
  where id = v_new_row.id
  returning * into v_published;

  perform app.capture_audit_event(
    v_published.tenant_id, p_actor_auth_user_id, p_actor_label, 'rollback_tenant_locale_version',
    'app.tenant_locale_versions', v_published.id, 'success', p_reason, to_jsonb(v_target), to_jsonb(v_published)
  );

  return v_published;
end;
$$;

-- app.send_test_webhook_delivery -- live definition from 20260804040000_create_intelligence_webhook_management.sql
create or replace function app.send_test_webhook_delivery(
  p_endpoint_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.webhook_deliveries
language plpgsql
as $$
declare
  v_endpoint app.webhook_endpoints;
  v_delivery app.webhook_deliveries;
  v_idempotency_key text;
begin
  select * into v_endpoint from app.webhook_endpoints where id = p_endpoint_id;
  if not found or not app.has_active_tenant_membership(v_endpoint.tenant_id, p_actor_auth_user_id) then
    raise exception 'webhook_endpoint_not_found: no endpoint %', p_endpoint_id using errcode = 'no_data_found';
  end if;

  if not app.check_api_webhook_admin_authority(v_endpoint.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks authority to manage webhook endpoints for tenant %', p_actor_auth_user_id, v_endpoint.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_idempotency_key := 'webhook-test:' || p_endpoint_id::text || ':' || extract(epoch from clock_timestamp())::text;

  insert into app.webhook_deliveries (tenant_id, webhook_endpoint_id, event_type_code, payload, idempotency_key, max_attempts, next_attempt_at)
  values (
    v_endpoint.tenant_id, p_endpoint_id, 'webhook.test',
    jsonb_build_object('message', 'This is a test delivery from CargoGrid.', 'endpoint_id', p_endpoint_id, 'sent_at', now()),
    v_idempotency_key, 1, now()
  )
  returning * into v_delivery;

  perform app.enqueue_job(
    v_endpoint.tenant_id, 'webhook_retry',
    jsonb_build_object('delivery_id', v_delivery.id),
    10, v_idempotency_key, 1,
    p_actor_auth_user_id, p_actor_label
  );

  perform app.capture_audit_event(
    v_endpoint.tenant_id, p_actor_auth_user_id, p_actor_label, 'send_test_webhook_delivery',
    'app.webhook_deliveries', v_delivery.id, 'success', null, null,
    jsonb_build_object('id', v_delivery.id, 'webhook_endpoint_id', p_endpoint_id)
  );

  return v_delivery;
end;
$$;

-- app.set_tenant_brand_tokens -- live definition from 20260717090512_create_white_label.sql
create or replace function app.set_tenant_brand_tokens(
  p_version_id uuid,
  p_actor_auth_user_id uuid,
  p_tokens jsonb,
  p_logo_asset_url text,
  p_email_sender_name text,
  p_email_logo_asset_url text,
  p_document_template_refs jsonb,
  p_actor_label text
)
returns app.tenant_brand_versions
language plpgsql
as $$
declare
  v_before app.tenant_brand_versions;
  v_after app.tenant_brand_versions;
  v_contrast numeric;
begin
  select * into v_before from app.tenant_brand_versions where id = p_version_id;
  if not found or not app.has_active_tenant_membership(v_before.tenant_id, p_actor_auth_user_id) then
    raise exception 'brand_version_not_found: no tenant brand version %', p_version_id
      using errcode = 'no_data_found';
  end if;

  if not app.is_support_grant_authority(p_actor_auth_user_id, v_before.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_before.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_before.status <> 'draft' then
    raise exception 'brand_version_not_draft: version % is %, only a draft''s tokens may be changed', p_version_id, v_before.status
      using errcode = 'check_violation';
  end if;

  if p_tokens ? 'primary' then
    v_contrast := app.hex_color_contrast_ratio(p_tokens ->> 'primary', '#fafafa');
  end if;

  update app.tenant_brand_versions
  set tokens = p_tokens,
      logo_asset_url = p_logo_asset_url,
      email_sender_name = p_email_sender_name,
      email_logo_asset_url = p_email_logo_asset_url,
      document_template_refs = coalesce(p_document_template_refs, '{}'::jsonb),
      contrast_validated = coalesce(v_contrast >= 4.5, false),
      contrast_report = case when v_contrast is not null
        then jsonb_build_object('primary_vs_neutral_50', v_contrast, 'threshold', 4.5, 'checked_at', now())
        else null
      end
  where id = p_version_id
  returning * into v_after;

  perform app.capture_audit_event(
    v_after.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_tenant_brand_tokens',
    'app.tenant_brand_versions', v_after.id, 'success', null, to_jsonb(v_before), to_jsonb(v_after)
  );

  return v_after;
end;
$$;

-- app.set_tenant_locale_config -- live definition from 20260717112000_create_localization.sql
create or replace function app.set_tenant_locale_config(
  p_version_id uuid,
  p_actor_auth_user_id uuid,
  p_default_locale text,
  p_default_timezone text,
  p_default_currency text,
  p_terminology_overrides jsonb,
  p_actor_label text
)
returns app.tenant_locale_versions
language plpgsql
as $$
declare
  v_before app.tenant_locale_versions;
  v_after app.tenant_locale_versions;
begin
  select * into v_before from app.tenant_locale_versions where id = p_version_id;
  if not found or not app.has_active_tenant_membership(v_before.tenant_id, p_actor_auth_user_id) then
    raise exception 'locale_version_not_found: no tenant locale version %', p_version_id
      using errcode = 'no_data_found';
  end if;

  if not app.is_support_grant_authority(p_actor_auth_user_id, v_before.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_before.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_before.status <> 'draft' then
    raise exception 'locale_version_not_draft: version % is %, only a draft may be changed', p_version_id, v_before.status
      using errcode = 'check_violation';
  end if;

  update app.tenant_locale_versions
  set default_locale = p_default_locale,
      default_timezone = p_default_timezone,
      default_currency = p_default_currency,
      terminology_overrides = coalesce(p_terminology_overrides, '{}'::jsonb)
  where id = p_version_id
  returning * into v_after;

  perform app.capture_audit_event(
    v_after.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_tenant_locale_config',
    'app.tenant_locale_versions', v_after.id, 'success', null, to_jsonb(v_before), to_jsonb(v_after)
  );

  return v_after;
end;
$$;

-- app.verify_enterprise_sso_domain_claim -- live definition from 20260807000000_create_intelligence_enterprise_iam_sso.sql
create or replace function app.verify_enterprise_sso_domain_claim(
  p_claim_id uuid,
  p_observed_txt_value text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.iam_domain_claims
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_claim app.iam_domain_claims;
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_claim from app.iam_domain_claims where id = p_claim_id for update;
  if not found or not app.has_active_tenant_membership(v_claim.tenant_id, p_actor_auth_user_id) then
    raise exception 'iam_domain_claim_not_found: %', p_claim_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_claim.tenant_id, 'IAM', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks IAM:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_claim.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_claim.status <> 'pending_verification' then
    raise exception 'iam_domain_claim_not_pending: claim % is % not pending_verification', p_claim_id, v_claim.status
      using errcode = 'check_violation';
  end if;

  if v_claim.expires_at < now() then
    raise exception 'iam_domain_claim_expired: claim % expired at %', p_claim_id, v_claim.expires_at
      using errcode = 'check_violation';
  end if;

  if p_observed_txt_value is null or p_observed_txt_value <> v_claim.verification_token then
    raise exception 'iam_domain_claim_token_mismatch: observed TXT value does not match the stored verification token'
      using errcode = 'check_violation';
  end if;

  update app.iam_domain_claims
  set status = 'verified', verified_at = now(), verified_by = p_actor_label
  where id = p_claim_id
  returning * into v_claim;

  perform app.capture_audit_event(
    v_claim.tenant_id, p_actor_auth_user_id, p_actor_label, 'verify_enterprise_sso_domain_claim',
    'app.iam_domain_claims', v_claim.id, 'success', null, null, to_jsonb(v_claim)
  );

  return v_claim;
end;
$$;

-- app.verify_tenant_domain -- live definition from 20260717103015_create_custom_domain.sql
create or replace function app.verify_tenant_domain(
  p_domain_id uuid,
  p_actor_auth_user_id uuid,
  p_observed_txt_value text,
  p_verified_by text
)
returns app.tenant_custom_domains
language plpgsql
as $$
declare
  v_before app.tenant_custom_domains;
  v_after app.tenant_custom_domains;
begin
  select * into v_before from app.tenant_custom_domains where id = p_domain_id;
  if not found or not app.has_active_tenant_membership(v_before.tenant_id, p_actor_auth_user_id) then
    raise exception 'domain_not_found: no tenant custom domain %', p_domain_id
      using errcode = 'no_data_found';
  end if;

  if not app.is_support_grant_authority(p_actor_auth_user_id, v_before.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_before.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_before.status <> 'pending_verification' then
    raise exception 'domain_not_pending: domain % is %, only a pending_verification domain may be verified', p_domain_id, v_before.status
      using errcode = 'check_violation';
  end if;

  if v_before.expires_at < now() then
    raise exception 'verification_expired: domain % challenge expired at %', p_domain_id, v_before.expires_at
      using errcode = 'check_violation';
  end if;

  if p_observed_txt_value is distinct from v_before.verification_token then
    raise exception 'verification_token_mismatch: observed TXT value does not match the issued challenge token for domain %', p_domain_id
      using errcode = 'check_violation';
  end if;

  update app.tenant_custom_domains
  set status = 'verified', verified_at = now(), verified_by = p_verified_by
  where id = p_domain_id
  returning * into v_after;

  perform app.capture_audit_event(
    v_after.tenant_id, p_actor_auth_user_id, p_verified_by, 'verify_tenant_domain',
    'app.tenant_custom_domains', v_after.id, 'success', null, to_jsonb(v_before), to_jsonb(v_after)
  );

  return v_after;
end;
$$;
