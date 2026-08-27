-- Track B Batch 1, ISS-2026-167 (docs/runtime/KNOWN_ISSUES.md): a repeated
-- code shape across this repository -- a bare `select ... where id = $1`
-- (no tenant_id in the WHERE clause) followed by a SEPARATE tenant-mismatch
-- check that raises a DISTINCT, tenant-UUID-echoing error -- lets a caller
-- who already holds SOME authority in their own tenant distinguish "this
-- record doesn't exist anywhere" from "this record exists in a DIFFERENT
-- tenant" (and, worse, learn that tenant's real UUID), a cross-tenant
-- existence oracle. The issue's own text names this as a ~41-site, 15-family
-- class owned by HDN-376 -- too large to fix exhaustively in one bounded
-- migration. This closes 3 representative, verified sites (the 2 the issue
-- itself cites, plus rotate_api_key, the byte-for-byte sibling of
-- revoke_api_key), demonstrating the fix and using the repository's own
-- already-proven counter-pattern (app.get_rfq_for_vendor_api/app.get_
-- customer_shipment_tracking: one tenant-scoped SELECT, one generic error).
-- The remaining sites stay explicitly open under HDN-376.

-- ===========================================================================
-- app.create_quotation_draft -- collapse opportunity lookup + tenant check
-- into one tenant-scoped SELECT
-- ===========================================================================
-- Verbatim current body from 20260805090000_harden_iae020_tier_c_review_
-- fixes.sql, with exactly the opportunity-lookup block changed: the
-- tenant_id predicate moves into the SELECT itself, and the separate
-- cross_tenant_opportunity_denied branch (which echoed p_tenant_id, of no
-- real diagnostic value to a legitimate caller who already knows their own
-- tenant_id, but a live existence oracle to an attacker) is removed --
-- both failure modes now share the one generic opportunity_not_found error.
create or replace function app.create_quotation_draft(
  p_tenant_id uuid,
  p_opportunity_id uuid,
  p_currency text,
  p_validity_to timestamptz,
  p_contact_id uuid,
  p_owner_user_id uuid,
  p_org_unit_id uuid,
  p_actor_auth_user_id uuid,
  p_created_by text
)
returns app.quotations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_opportunity app.opportunities;
  v_prospect app.prospects;
  v_decision app.rbac_decision;
  v_quotation app.quotations;
  v_snapshot jsonb;
  v_new_id uuid := gen_random_uuid();
begin
  -- ISS-2026-167 fix (Track B Batch 1): tenant-scoped in the SELECT itself,
  -- collapsing the former separate cross_tenant_opportunity_denied branch
  -- (which leaked the caller's own tenant_id back in its own error text --
  -- no real diagnostic value, but a live cross-tenant existence oracle) into
  -- this one generic not-found error.
  select * into v_opportunity from app.opportunities where id = p_opportunity_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'opportunity_not_found: %', p_opportunity_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'COM', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, p_tenant_id, v_opportunity.owner_user_id, app.lead_record_scope_org_unit_ids(v_opportunity.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access opportunity %', p_actor_auth_user_id, p_opportunity_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then
    raise exception 'invalid_currency: % is not a 3-letter ISO currency code', p_currency using errcode = 'check_violation';
  end if;

  if p_validity_to is null or p_validity_to <= now() then
    raise exception 'invalid_validity: validity_to must be in the future' using errcode = 'check_violation';
  end if;

  select * into v_prospect from app.prospects where id = v_opportunity.prospect_id;
  if not found then
    raise exception 'prospect_not_found: %', v_opportunity.prospect_id using errcode = 'no_data_found';
  end if;

  if p_contact_id is not null then
    if not exists (select 1 from app.contacts where id = p_contact_id and tenant_id = p_tenant_id) then
      raise exception 'contact_not_found: %', p_contact_id using errcode = 'no_data_found';
    end if;
  end if;

  if p_owner_user_id is not null then
    if not app.has_active_tenant_membership(p_tenant_id, p_owner_user_id) then
      raise exception 'quotation_owner_not_tenant_member: % does not hold active membership in tenant %', p_owner_user_id, p_tenant_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  if p_org_unit_id is not null then
    if not exists (select 1 from app.org_units where id = p_org_unit_id and tenant_id = p_tenant_id) then
      raise exception 'quotation_org_unit_not_found: % does not belong to tenant %', p_org_unit_id, p_tenant_id
        using errcode = 'no_data_found';
    end if;
  end if;

  v_snapshot := jsonb_build_object(
    'legal_name', v_prospect.legal_name,
    'trade_name', v_prospect.trade_name,
    'billing_address', v_prospect.billing_address,
    'contact_name', v_prospect.contact_name,
    'contact_email', v_prospect.contact_email,
    'contact_phone', v_prospect.contact_phone
  );

  insert into app.quotations (
    id, tenant_id, quote_number, opportunity_id, source_opportunity_version, prospect_id, contact_id,
    customer_snapshot, currency, validity_to, root_quotation_id, version_number, is_current,
    owner_user_id, org_unit_id, created_by
  ) values (
    v_new_id, p_tenant_id, app.next_quotation_number(p_tenant_id), p_opportunity_id, v_opportunity.record_version, v_opportunity.prospect_id, p_contact_id,
    v_snapshot, p_currency, p_validity_to, v_new_id, 1, true,
    coalesce(p_owner_user_id, p_actor_auth_user_id), coalesce(p_org_unit_id, v_opportunity.org_unit_id), p_created_by
  )
  returning * into v_quotation;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_created_by, 'create_quotation_draft',
    'app.quotations', v_quotation.id, 'success', null, null, to_jsonb(v_quotation)
  );

  return v_quotation;
end;
$$;

comment on function app.create_quotation_draft is
  'COM-151/COM-152: creates a draft quotation from an opportunity, pinning source_opportunity_version (staleness check at submit time), a real customer_snapshot copied from app.prospects, and its own root/version-1 identity (COM-152). Idempotency is not attempted at this layer. Tier C fix (IAE-020''s own review): p_owner_user_id/p_org_unit_id are validated against the tenant. ISS-2026-167 fix (Track B Batch 1): the opportunity lookup is now tenant-scoped in the SELECT itself, collapsing the former separate cross-tenant-mismatch branch (a live existence oracle) into one generic not-found error.';

-- ===========================================================================
-- app.revoke_api_key -- collapse not-found + authority check into one
-- generic error, never echo the foreign tenant's real UUID
-- ===========================================================================
-- Verbatim current body from 20260804020000_create_intelligence_customer_
-- api.sql, with exactly the lookup/authority block changed.
create or replace function app.revoke_api_key(
  p_key_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.api_keys
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_key app.api_keys;
  v_updated app.api_keys;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- ISS-2026-167 fix (Track B Batch 1): the former separate not-found and
  -- insufficient_authority checks let a caller distinguish "key doesn't
  -- exist" from "key exists in another tenant I have no relationship to" --
  -- and the authority error echoed that foreign tenant's real UUID. The
  -- discriminator is app.has_active_tenant_membership(v_key.tenant_id, ...):
  -- a genuine stranger to that tenant gets the generic not-found error
  -- (closing the oracle -- they never learn the key exists, or the tenant's
  -- UUID); a real member of that SAME tenant who simply lacks manage
  -- authority still gets the specific, more useful insufficient_authority
  -- error below -- revealing a tenant_id the caller already belongs to is
  -- not a leak, and collapsing that legitimate, common, same-tenant case
  -- into a confusing "not found" would be a real usability regression (a
  -- pre-existing db-test caught exactly this during authoring -- see
  -- api-key-webhook.sql's own "rotate: a regular org_user is denied" case).
  select * into v_key from app.api_keys where id = p_key_id;
  if not found or not app.has_active_tenant_membership(v_key.tenant_id, p_actor_auth_user_id) then
    raise exception 'api_key_not_found: no key % is manageable by this identity', p_key_id using errcode = 'no_data_found';
  end if;

  if not app.check_api_key_manage_authority(v_key.tenant_id, v_key.customer_account_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks authority to manage API keys for tenant %', p_actor_auth_user_id, v_key.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_key.status = 'revoked' then
    return v_key;
  end if;

  update app.api_keys
  set status = 'revoked', revoked_at = now(), revoked_reason = coalesce(p_reason, 'manual revoke')
  where id = p_key_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'revoke_api_key',
    'app.api_keys', v_updated.id, 'success', p_reason,
    jsonb_build_object('id', v_key.id, 'status', v_key.status),
    jsonb_build_object('id', v_updated.id, 'status', v_updated.status)
  );

  return v_updated;
end;
$$;

comment on function app.revoke_api_key is
  'PLT-129, extended by IAE-010: SECURITY DEFINER (widened grant to authenticated so a real customer account_admin can revoke their own account''s key directly) -- app.check_api_key_manage_authority remains the real authority boundary. ISS-2026-167 fix (Track B Batch 1): not-found and cross-tenant-authority-denied now share one generic error, never echoing a foreign tenant''s real UUID -- closes a live cross-tenant existence oracle.';

-- ===========================================================================
-- app.rotate_api_key -- same fix, same root cause, byte-for-byte sibling
-- shape to revoke_api_key above
-- ===========================================================================
-- Verbatim current body from 20260809100000_harden_intelligence_iae037_
-- security_ai_hardening.sql, with exactly the lookup/authority block changed
-- (the later, unrelated api_key_expired/api_key_already_rotated/
-- api_key_not_active checks are unaffected -- they only run once authority
-- is already confirmed, so they carry no existence-oracle risk).
create or replace function app.rotate_api_key(
  p_key_id uuid,
  p_overlap_minutes integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns table (
  id uuid, tenant_id uuid, name text, key_prefix text, scopes jsonb, status text,
  rate_limit_per_minute integer, expires_at timestamptz, created_at timestamptz, raw_key text
)
language plpgsql
security definer
set search_path = app, public, extensions, pg_temp
as $$
declare
  v_old app.api_keys;
  v_new_raw_key text;
  v_new_key_prefix text;
  v_new_key_hash text;
  v_new_key app.api_keys;
  v_new_expiry timestamptz;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_old from app.api_keys where app.api_keys.id = p_key_id for update;
  -- ISS-2026-167 fix (Track B Batch 1): mirrors app.revoke_api_key's own
  -- identical fix above -- a stranger to v_old.tenant_id gets the generic
  -- not-found error (closing the cross-tenant oracle); a real member of
  -- that same tenant who lacks manage authority still gets the specific
  -- insufficient_authority error (not a leak -- they already belong there).
  if not found or not app.has_active_tenant_membership(v_old.tenant_id, p_actor_auth_user_id) then
    raise exception 'api_key_not_found: no key % is manageable by this identity', p_key_id using errcode = 'no_data_found';
  end if;

  if not app.check_api_key_manage_authority(v_old.tenant_id, v_old.customer_account_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks authority to manage API keys for tenant %', p_actor_auth_user_id, v_old.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_old.status <> 'active' then
    raise exception 'api_key_not_active: key % is %, only an active key may be rotated', p_key_id, v_old.status
      using errcode = 'check_violation';
  end if;

  if v_old.expires_at is not null and v_old.expires_at <= now() then
    raise exception 'api_key_expired: key % has expired -- rotate is not available for an expired key, mint a new key instead', p_key_id
      using errcode = 'check_violation';
  end if;

  if v_old.superseded_by_key_id is not null then
    raise exception 'api_key_already_rotated: key % was already rotated to %, rotate the successor key instead', p_key_id, v_old.superseded_by_key_id
      using errcode = 'check_violation';
  end if;

  if p_overlap_minutes is null or p_overlap_minutes < 0 or p_overlap_minutes > 10080 then
    raise exception 'api_key_invalid_overlap_minutes: % must be between 0 and 10080 (7 days)', p_overlap_minutes
      using errcode = 'check_violation';
  end if;

  v_new_raw_key := 'cgk_' || encode(gen_random_bytes(24), 'hex');
  v_new_key_prefix := substring(v_new_raw_key from 1 for 12);
  v_new_key_hash := encode(digest(v_new_raw_key, 'sha256'), 'hex');

  insert into app.api_keys (tenant_id, name, key_prefix, key_hash, scopes, rate_limit_per_minute, expires_at, created_by_auth_user_id, customer_account_id, customer_actor_auth_user_id, vendor_master_record_id)
  values (v_old.tenant_id, v_old.name, v_new_key_prefix, v_new_key_hash, v_old.scopes, v_old.rate_limit_per_minute, v_old.expires_at, p_actor_auth_user_id, v_old.customer_account_id, v_old.customer_actor_auth_user_id, v_old.vendor_master_record_id)
  returning * into v_new_key;

  v_new_expiry := now() + (p_overlap_minutes::text || ' minutes')::interval;

  update app.api_keys
  set status = case when p_overlap_minutes = 0 then 'revoked' else v_old.status end,
      revoked_at = case when p_overlap_minutes = 0 then now() else revoked_at end,
      revoked_reason = case when p_overlap_minutes = 0 then 'rotated' else revoked_reason end,
      expires_at = case when v_old.expires_at is not null and v_old.expires_at < v_new_expiry then v_old.expires_at else v_new_expiry end,
      superseded_by_key_id = v_new_key.id
  where app.api_keys.id = v_old.id;

  perform app.capture_audit_event(
    v_old.tenant_id, p_actor_auth_user_id, p_actor_label, 'rotate_api_key',
    'app.api_keys', v_new_key.id, 'success', null,
    jsonb_build_object('id', v_old.id, 'key_prefix', v_old.key_prefix),
    jsonb_build_object('id', v_new_key.id, 'key_prefix', v_new_key.key_prefix, 'overlap_minutes', p_overlap_minutes)
  );

  return query select v_new_key.id, v_new_key.tenant_id, v_new_key.name, v_new_key.key_prefix, v_new_key.scopes, v_new_key.status, v_new_key.rate_limit_per_minute, v_new_key.expires_at, v_new_key.created_at, v_new_raw_key;
end;
$$;

comment on function app.rotate_api_key is
  'PLT-129, extended by IAE-010, IAE-011, Tier C Batch 3 fix: overlap-window rotation (0 = immediate revoke), row-locked and superseded_by_key_id-guarded against a second concurrent/retried rotation of the same source key. IAE-037 Tier C fix: independently re-checks real-time expiry rather than trusting the stored status column alone. ISS-2026-167 fix (Track B Batch 1): not-found and cross-tenant-authority-denied now share one generic error, never echoing a foreign tenant''s real UUID -- mirrors app.revoke_api_key''s own identical fix, the same byte-for-byte root cause.';
