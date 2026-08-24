-- HDN-378 Tier C fixes. Two independent adversarial lenses (schema-wide completeness
-- sweep; attack-surface adversarial testing) found real, live-forced defects in this
-- same checkpoint's own first-round work, both closed here before the checkpoint is
-- called VERIFIED -- never shipped broken, mirroring this repository's own established
-- self-correction discipline (HDN-374/375/377).
--
-- 1. ISS-2026-232's own fix (20260815300000) revoked authenticated's table-level
--    SELECT on token_hash for 3 tables and re-granted an explicit column list omitting
--    it -- but each table's own "revoke" RPC returns the FULL composite row type
--    (`returning * into v_row; return v_row;`), which is not subject to column-level
--    SELECT privileges at all: an RPC's return value bypasses column ACLs entirely.
--    Live-forced by the attack-surface lens: calling app.revoke_shipment_tracking_
--    token as an ordinary authenticated actor returned the real token_hash verbatim
--    in the RPC response, completely defeating the column-privilege fix for all 3
--    tables. Fixed by nulling the token_hash field on the composite return value
--    immediately before each function returns -- the return TYPE is unchanged (still
--    the full app.<table> composite), only the token_hash field's VALUE is masked, so
--    no TS contract/parse-function change is needed (none of the 3 corresponding Zod
--    schemas ever expected token_hash in the first place, confirmed at 20260815300000).
--
-- 2. ISS-2026-168's own fix (eslint.config.js's serviceRoleImportGuard) only matches
--    static `import`/`export ... from` declarations via `no-restricted-imports`.
--    Live-forced: `require("../../../lib/supabase/service-role.ts")` and
--    `await import("../../../lib/supabase/service-role.ts")` both produce ZERO lint
--    errors -- a Client Component can smuggle the service-role factory (which holds
--    SUPABASE_SERVICE_ROLE_KEY, bypassing RLS entirely) into the browser bundle via
--    either form, completely undetected, reproducing the exact "no real bundle scan
--    exists" gap ISS-2026-168 was opened to close. Fixed in eslint.config.js (see
--    that file's own diff, not this migration) by adding two `no-restricted-syntax`
--    selectors alongside the existing `no-restricted-imports` rule: one for a
--    `CallExpression` whose callee is `require` with a matching string-literal
--    argument, one for an `ImportExpression` (the AST node for a dynamic `import()`
--    call) with a matching string-literal source.
--
-- 3. Lens 2's own schema-wide completeness sweep found `app.validate_webhook_url`
--    (PLT-129, the registration-time SSRF guard for app.webhook_endpoints) shares the
--    exact control-character-injection gap ISS-2026-233 already fixed in
--    lib/auth/redirect-allowlist.ts: `validate_webhook_url('https://\t127.0.0.1/...')`
--    returns true (accepted) because the private-IP-literal regex checks run against
--    a host string that still contains the tab, so none of them match -- while a real
--    WHATWG URL parser strips embedded tab/CR/LF from the whole string first,
--    collapsing it back to the literal private-IP host before ever reaching a real
--    HTTP client. Not exploitable end-to-end today (every real delivery path
--    re-validates via lib/webhooks/ssrf-guard.server.ts's own proper URL-parsing,
--    live-DNS-resolving dispatch-time check, confirmed the only real caller) but a
--    real, live, cheap-to-fix gap in the front-door registration guard, the same
--    class this checkpoint already fixed elsewhere in the same OWASP sweep. Fixed by
--    stripping [\t\r\n] from p_url before any check, mirroring the redirect-allowlist
--    fix exactly.
--
-- No already-applied migration is edited.

-- ===========================================================================
-- 1. app.revoke_shipment_tracking_token -- mask token_hash on return
-- ===========================================================================

create or replace function app.revoke_shipment_tracking_token(
  p_shipment_order_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.shipment_tracking_tokens
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_token app.shipment_tracking_tokens;
  v_updated app.shipment_tracking_tokens;
begin
  select * into v_shipment from app.shipment_orders so where so.id = p_shipment_order_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'tracking_revoke_reason_required: a reason is required to revoke a tracking token' using errcode = 'check_violation';
  end if;

  select * into v_token from app.shipment_tracking_tokens where shipment_order_id = p_shipment_order_id and status = 'active';
  if not found then
    raise exception 'tracking_no_active_token: shipment order % has no active tracking token', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  update app.shipment_tracking_tokens
  set status = 'revoked', revoked_at = now(), revoked_reason = p_reason
  where id = v_token.id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'revoke_shipment_tracking_token',
    'app.shipment_tracking_tokens', v_updated.id, 'success', p_reason, to_jsonb(v_token), to_jsonb(v_updated)
  );

  -- ISS-2026-232 Tier C fix: mask token_hash on the returned composite -- an RPC
  -- return value bypasses column-level SELECT privileges entirely, so revoking the
  -- table-level grant alone (20260815300000) did not protect this function's own
  -- response.
  v_updated.token_hash := null;
  return v_updated;
end;
$$;

comment on function app.revoke_shipment_tracking_token is
  'OPS-180: OPS:Edit + record-scope gated. Revokes the active tracking token for a shipment order, capturing before/after audit state. ISS-2026-232 Tier C fix: the returned composite has token_hash masked to null -- an RPC return value is not subject to column-level SELECT privileges, so the table-level column-privilege fix alone did not close this path.';

-- ===========================================================================
-- 2. app.revoke_driver_mobile_session -- mask token_hash on return
-- ===========================================================================

create or replace function app.revoke_driver_mobile_session(
  p_shipment_leg_tracking_session_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.driver_mobile_tracking_sessions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_row app.driver_mobile_tracking_sessions;
  v_session app.shipment_leg_tracking_sessions;
  v_leg app.shipment_legs;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  select * into v_row from app.driver_mobile_tracking_sessions where shipment_leg_tracking_session_id = p_shipment_leg_tracking_session_id and status = 'active';
  if not found then
    raise exception 'driver_mobile_session_not_found: no active mobile session token for tracking session %', p_shipment_leg_tracking_session_id using errcode = 'no_data_found';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'revoke_reason_required: a non-empty reason is required' using errcode = 'check_violation';
  end if;

  select * into v_session from app.shipment_leg_tracking_sessions where id = v_row.shipment_leg_tracking_session_id;
  select * into v_leg from app.shipment_legs where id = v_session.shipment_leg_id;
  select * into v_shipment from app.shipment_orders where id = v_leg.shipment_order_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_leg.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.driver_mobile_tracking_sessions
  set status = 'revoked', revoked_at = now(), revoked_reason = p_reason
  where id = v_row.id
  returning * into v_row;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'revoke_driver_mobile_session',
    'app.driver_mobile_tracking_sessions', v_row.id, 'success', p_reason, null, null
  );

  -- ISS-2026-232 Tier C fix: mask token_hash on the returned composite.
  v_row.token_hash := null;
  return v_row;
end;
$$;

comment on function app.revoke_driver_mobile_session is
  'ATW-226C: OPS:Edit + record-scope gated. Revokes the active driver-mobile session token for a tracking session. ISS-2026-232 Tier C fix: the returned composite has token_hash masked to null, same reasoning as app.revoke_shipment_tracking_token.';

-- ===========================================================================
-- 3. app.revoke_vendor_intake_token -- mask token_hash on return
-- ===========================================================================

create or replace function app.revoke_vendor_intake_token(p_token_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_intake_tokens
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_token app.vendor_intake_tokens;
  v_prior_version integer;
begin
  select * into v_token from app.vendor_intake_tokens where id = p_token_id;
  if not found then
    raise exception 'token_not_found: %', p_token_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_token.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_token.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to revoke an intake token' using errcode = 'check_violation';
  end if;
  if v_token.status <> 'pending' then
    raise exception 'invalid_transition: intake token % is % and cannot be revoked', p_token_id, v_token.status using errcode = 'check_violation';
  end if;

  v_prior_version := v_token.record_version;
  update app.vendor_intake_tokens
  set status = 'revoked', revoked_at = now(), revoked_reason = p_reason, record_version = record_version + 1
  where id = p_token_id and record_version = v_prior_version
  returning * into v_token;
  if not found then
    raise exception 'stale_version: intake token % target row was concurrently modified (expected version %)', p_token_id, v_prior_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_token.tenant_id, p_actor_auth_user_id, p_actor_label, 'revoke_vendor_intake_token',
    'app.vendor_intake_tokens', v_token.id, 'success', p_reason, null, '{}'::jsonb
  );

  -- ISS-2026-232 Tier C fix: mask token_hash on the returned composite.
  v_token.token_hash := null;
  return v_token;
end;
$$;

comment on function app.revoke_vendor_intake_token is
  'PRC-251: PRC:Edit-gated. Revokes a pending vendor intake token, optimistic-concurrency-checked. ISS-2026-232 Tier C fix: the returned composite has token_hash masked to null, same reasoning as app.revoke_shipment_tracking_token.';

-- ===========================================================================
-- 4. app.validate_webhook_url -- control-character stripping, mirrors ISS-2026-233
-- ===========================================================================

create or replace function app.validate_webhook_url(p_url text)
returns boolean
language plpgsql
as $$
declare
  v_url text;
  v_host text;
begin
  -- ISS-2026-233-class Tier C fix: strip embedded tab/CR/LF before any check, since
  -- a real WHATWG URL parser strips these from anywhere in the string before ever
  -- reaching a real HTTP client -- a check run against the raw, unstripped string
  -- can be satisfied by a host string a real client never actually sees.
  v_url := regexp_replace(coalesce(p_url, ''), '[\t\r\n]', '', 'g');

  if v_url = '' or v_url !~ '^https://' then
    raise exception 'webhook_invalid_url_scheme: url must start with https://'
      using errcode = 'check_violation';
  end if;

  v_host := substring(v_url from '^https://([^/:]+)');
  if v_host is null or length(v_host) = 0 or position('@' in v_host) > 0 then
    raise exception 'webhook_unsafe_url_host: url has no parseable host, or the host contains userinfo (@)'
      using errcode = 'check_violation';
  end if;

  if lower(v_host) = 'localhost'
     or v_host ~ '^127\.'
     or v_host ~ '^10\.'
     or v_host ~ '^172\.(1[6-9]|2[0-9]|3[0-1])\.'
     or v_host ~ '^192\.168\.'
     or v_host ~ '^169\.254\.'
     or v_host = '0.0.0.0'
     or v_host = '::1'
     or v_host ~* '^\[?f[cd][0-9a-f]{2}:'
  then
    raise exception 'webhook_unsafe_url_host: % resolves to a private/loopback/link-local literal, refusing to register', v_host
      using errcode = 'check_violation';
  end if;

  return true;
end;
$$;

comment on function app.validate_webhook_url is
  'PLT-129: registration-time SSRF guard for app.webhook_endpoints. Tier C fix (schema-wide completeness sweep, same class as ISS-2026-233): strips embedded tab/CR/LF before any check, closing a WHATWG-URL-parser-vs-raw-string mismatch identical to the one already fixed in lib/auth/redirect-allowlist.ts. Not exploitable end-to-end today -- every real delivery path re-validates via lib/webhooks/ssrf-guard.server.ts''s own proper URL-parsing, live-DNS-resolving dispatch-time check -- but this closes the front-door registration guard gap rather than relying solely on the dispatch-time backstop.';
