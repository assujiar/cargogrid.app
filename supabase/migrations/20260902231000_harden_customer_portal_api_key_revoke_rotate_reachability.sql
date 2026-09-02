-- Bundled, directly-blocking finding discovered while implementing ISS-2026-125 item 2
-- (docs/runtime/KNOWN_ISSUES.md), fixed in this companion migration rather than folded silently
-- into 20260902230000: live-testing that migration's own new API-key revocation branch inside
-- app.set_customer_portal_account_membership_status surfaced that app.revoke_api_key (and its
-- identical sibling app.rotate_api_key) are structurally UNREACHABLE for any genuine
-- customer_user-layer actor at all, regardless of app.check_api_key_manage_authority's own
-- already-correct accommodation for one.
--
-- Root cause, read live via pg_get_functiondef before concluding, not assumed: both functions'
-- own not-found discriminator (`if not found or not app.has_active_tenant_membership(...)`) was
-- added by ISS-2026-167 (`20260827010000`, three weeks AFTER IAE-010's own
-- `20260804020000_create_intelligence_customer_api.sql`, which had already wired
-- app.check_api_key_manage_authority's customer-account_admin OR-branch into these same two
-- functions and documented the intent explicitly in server/mutations/customer-api.ts's own header
-- comment: "app.revoke_api_key/app.rotate_api_key are extended in-place ... to compose the new
-- customer-account_admin authority path, never forked"). app.has_active_tenant_membership checks
-- ONLY app.tenant_user_identities (the staff/Layer-2-3 employment relationship) or supreme_admin
-- or an active support grant -- never the customer_user layer, whose own app.tenant_user_
-- identities row deliberately never reaches 'active' (the identical shape ISS-2026-125 item 1's
-- own fix, 20260901140000, already found and fixed once for app.request_mfa_step_up_challenge,
-- itself citing the original PLT-128/CPL-302 precedent for app.check_file_action_authority).
-- ISS-2026-167's own fix was correct for the cross-tenant-oracle problem it was solving and never
-- intended to touch the customer-actor path at all -- it simply used the wrong "is this identity
-- a stranger to this tenant" predicate for a function two OTHER authority branches already served.
--
-- Live effect before this fix, confirmed by an actual live-forced call during this session's own
-- db-test authoring (scripts/db-tests/customer-user-management.sql): a real customer-portal
-- account_admin calling app.revoke_api_key or app.rotate_api_key on a key app.check_api_key_
-- manage_authority already says they may manage gets api_key_not_found instead -- the specific,
-- correct authority decision is never reached. This is not hypothetical or newly risky: it made
-- 20260902230000's own new API-key revocation branch inside app.set_customer_portal_account_
-- membership_status raise and roll back the ENTIRE membership-status transaction whenever the
-- target identity held an active API key, which is exactly the live-forced failure that surfaced
-- this finding rather than shipping silently broken.
--
-- Fix: the identical widening shape already established -- OR in app.actor_holds_customer_user_
-- layer(tenant_id, actor) alongside app.has_active_tenant_membership in both functions' own
-- not-found discriminator. This changes ONLY which identities pass the "is this a stranger to the
-- tenant" gate (so a customer_user-layer actor now gets the correct, specific insufficient_
-- authority when they lack manage authority for a SPECIFIC key, instead of a misleading not-found)
-- -- it does not touch app.check_api_key_manage_authority, which already, correctly, gates the
-- actual decision by account. A staff actor's own existing behavior is completely unchanged (the
-- OR only ever adds true, never removes it). Both bodies rebuilt via CREATE OR REPLACE FUNCTION
-- from the LIVE pg_get_functiondef output, verified byte-for-byte identical apart from this one
-- predicate change; language/security definer/search_path all restated explicitly.

create or replace function app.revoke_api_key(p_key_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
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
  --
  -- Widened here (this migration, bundled with ISS-2026-125 item 2): OR in
  -- app.actor_holds_customer_user_layer, the identical "is this identity a
  -- genuine member of this tenant" test for the customer_user layer that
  -- app.has_active_tenant_membership already is for staff -- see this
  -- migration's own header comment for why the un-widened predicate made
  -- this function unreachable for any customer-portal actor at all.
  select * into v_key from app.api_keys where id = p_key_id;
  if not found or not (
    app.has_active_tenant_membership(v_key.tenant_id, p_actor_auth_user_id)
    or app.actor_holds_customer_user_layer(v_key.tenant_id, p_actor_auth_user_id)
  ) then
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
  'PLT-129, extended by IAE-010 (customer-account_admin authority via app.check_api_key_manage_authority) and ISS-2026-167 (cross-tenant not-found discriminator), hardened by this migration: the not-found discriminator now also accepts app.actor_holds_customer_user_layer, so a customer-portal actor genuinely reaches the authority decision IAE-010 already intended for them instead of a misleading api_key_not_found.';

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
  -- Widened here (this migration, bundled with ISS-2026-125 item 2): the
  -- identical OR-in of app.actor_holds_customer_user_layer app.
  -- revoke_api_key just above gets, and for the identical reason -- see
  -- this migration's own header comment.
  if not found or not (
    app.has_active_tenant_membership(v_old.tenant_id, p_actor_auth_user_id)
    or app.actor_holds_customer_user_layer(v_old.tenant_id, p_actor_auth_user_id)
  ) then
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
  'PLT-129, extended by IAE-010 (customer-account_admin authority via app.check_api_key_manage_authority) and ISS-2026-167 (cross-tenant not-found discriminator), hardened by this migration: the not-found discriminator now also accepts app.actor_holds_customer_user_layer, so a customer-portal actor genuinely reaches the authority decision IAE-010 already intended for them instead of a misleading api_key_not_found.';
