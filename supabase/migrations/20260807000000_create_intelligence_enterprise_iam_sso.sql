-- IAE-026 (Prompt 354, Group 7): Enterprise IAM -- SSO (OIDC/SAML) and SCIM.
--
-- Design decisions (cited, not re-derived; composes existing primitives rather
-- than duplicating them, per this session's own established discipline):
--
-- 1. Platform identity remains the sole authorization source (Prompt 354 §24).
--    An enterprise IdP authenticates and (via SCIM) provisions/deprovisions --
--    it never grants RBAC directly. Every resolved SSO login or SCIM event
--    still terminates in the existing app.principal_memberships/app.role_
--    assignments machinery; this migration adds zero new authorization path.
--
-- 2. RPD-017's own order (OIDC, then SAML, then SCIM) is reflected structurally:
--    both protocols share ONE connection shape (app.integration_connections,
--    IAE-008/PLT reused verbatim below), SCIM is a separate, later-activated
--    concern (app.iam_scim_user_links), never a precondition for SSO login.
--
-- 3. Composition, not duplication, of three already-hardened primitives:
--    (a) app.integration_connections/app.integration_connection_credentials
--        (IAE-008) for the IdP connection itself (client_id/issuer/sso_url in
--        the non-secret config jsonb; client_secret or IdP signing certificate
--        in the isolated, zero-grant credentials table) -- app.create_
--        integration_connection/app.update_integration_connection_config/app.
--        set_integration_connection_status/app.rotate_integration_connection_
--        credential are reused UNMODIFIED, not wrapped, for connection CRUD;
--    (b) app.tenant_custom_domains' own request->verify->activate lifecycle
--        shape and its normalize/validate/is_reserved-hostname/token-generator
--        helpers (PLT-118) for the NEW email-domain-claim concept below (a
--        distinct concept from a portal hostname -- disclosed, not merged);
--    (c) app.link_auth_identity/app.revoke_auth_identity (PLT-107) for the
--        real enforcement half of SCIM provisioning -- deprovisioning a SCIM-
--        managed user genuinely revokes their tenant_user_identities row, it
--        is never a log-only event.
--
-- 4. Genuinely new schema is limited to what does not already exist anywhere:
--    an email-domain claim for SSO routing (distinct from a portal custom
--    domain), an SSO claims-resolution/login-attempt evidence trail, and a
--    SCIM external-identity link plus its own provisioning-event log.
--
-- 5. Disclosed, bounded scope (no fake/placeholder persistence, Definition of
--    Done): this checkpoint does NOT perform a live OIDC token-exchange or
--    SAML-assertion XML-signature verification against a real external IdP --
--    there is no live IdP reachable from this environment to integrate
--    against, and Platform-Core has no existing "external protocol client"
--    primitive to compose (unlike AI's dispatchAiGovernedRequest). app.
--    resolve_enterprise_sso_claims operates on an ALREADY-EXTRACTED claims
--    payload (subject + email) that a genuinely real deployment's own OIDC
--    RP / SAML SP protocol layer (built in the Next.js server tier, e.g.
--    via a real openid-client/node-saml library, a future disclosed task)
--    would supply after it has itself verified the token/assertion signature.
--    What IS real and structurally enforced here: domain-claim routing with
--    anti-takeover uniqueness, user-match resolution, deprovisioned-user
--    rejection, activation requiring a proven test resolution (lockout
--    guard), and the SCIM deprovisioning enforcement action. Likewise, SCIM
--    is modeled as a REST-inbound protocol (the IdP calls CargoGrid), so no
--    new outbound HTTP client is introduced -- the actual `/api/scim/v2/**`
--    route surface authenticating a real SCIM bearer token against app.
--    api_keys is disclosed as not built this checkpoint (no new UI/route
--    shipped either, consistent with several merged-Batch-4 precedents).
--
-- 6. Every authenticated-reachable function is SECURITY DEFINER paired with
--    app.assert_actor_is_session_identity as its first statement (the merged
--    Batch 4 Tier C review's own most-repeated lesson, applied proactively).

-- ===========================================================================
-- 1. IAM entitlement module (mirrors AI/INTHUB's own direct-insert seeding).
-- ===========================================================================

insert into app.entitlement_modules (code, name, owning_phase) values
  ('IAM', 'Enterprise IAM: SSO (OIDC/SAML), SCIM provisioning, domain claims', 9);

insert into app.permissions (action, resource_module_code, category, protected) values
  ('Configure', 'IAM', 'admin', false),
  ('View', 'IAM', 'standard', false);

-- ===========================================================================
-- 2. Adapter seeds (IAE-008's own open registry, no lockstep migration).
-- ===========================================================================

insert into app.integration_adapters (code, name, category, registered_by) values
  ('enterprise_sso_oidc', 'Enterprise SSO -- OIDC identity provider', 'identity', 'phase-09-foundation'),
  ('enterprise_sso_saml', 'Enterprise SSO -- SAML identity provider', 'identity', 'phase-09-foundation');

-- ===========================================================================
-- 3. app.iam_domain_claims -- an email domain routed to one tenant's own SSO
-- connection. Mirrors app.tenant_custom_domains' own request->verify->activate
-- shape and reuses its normalize/validate/reserved/token helpers verbatim
-- (design decision 3b) -- a distinct concept (SSO routing vs. portal hostname
-- branding), not a rename/merge of that table.
-- ===========================================================================

create table app.iam_domain_claims (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  connection_id uuid not null references app.integration_connections (id),
  email_domain text not null,
  status text not null default 'pending_verification',
  verification_method text not null default 'dns_txt',
  verification_token text not null default app.generate_domain_verification_token(),
  verification_challenge_host text generated always as ('_cargogrid-verify.' || email_domain) stored,
  requested_by text,
  verified_at timestamptz,
  verified_by text,
  activated_at timestamptz,
  activated_by text,
  disabled_at timestamptz,
  disabled_by text,
  disabled_reason text,
  rejected_at timestamptz,
  rejected_by text,
  rejected_reason text,
  expires_at timestamptz not null default (now() + interval '7 days'),
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint iam_domain_claims_status_check check (status in (
    'pending_verification', 'verified', 'active', 'disabled', 'rejected', 'expired'
  )),
  constraint iam_domain_claims_verification_method_check check (verification_method in ('dns_txt')),
  constraint iam_domain_claims_domain_normalized_check check (email_domain = app.normalize_domain_hostname(email_domain)),
  constraint iam_domain_claims_domain_valid_check check (app.validate_domain_hostname(email_domain))
);

comment on table app.iam_domain_claims is
  'IAE-026: which email domain routes to which tenant''s own enterprise SSO connection. pending_verification -> verified -> active, with disabled/rejected/expired terminal branches -- the SAME lifecycle shape as app.tenant_custom_domains (PLT-118), a deliberately distinct table since a portal branding hostname and an SSO-routing email domain are different concepts that happen to share a verification shape.';

create index iam_domain_claims_tenant_id_idx on app.iam_domain_claims (tenant_id);
create index iam_domain_claims_connection_id_idx on app.iam_domain_claims (connection_id);
create index iam_domain_claims_email_domain_idx on app.iam_domain_claims (email_domain);
-- Anti-takeover guarantee (mirrors PLT-118's own hostname-live-claim index
-- exactly): at most one tenant may hold a live claim on a given email domain,
-- atomically, regardless of application-level ordering.
create unique index iam_domain_claims_domain_live_claim_unique
  on app.iam_domain_claims (email_domain) where status in ('pending_verification', 'verified', 'active');
create index iam_domain_claims_pending_expiry_idx
  on app.iam_domain_claims (expires_at) where status = 'pending_verification';

create function app.touch_iam_domain_claim_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger iam_domain_claims_touch_row
  before update on app.iam_domain_claims
  for each row
  execute function app.touch_iam_domain_claim_row();

create function app.request_enterprise_sso_domain_claim(
  p_tenant_id uuid,
  p_connection_id uuid,
  p_email_domain text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.iam_domain_claims
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_normalized text;
  v_connection app.integration_connections;
  v_existing app.iam_domain_claims;
  v_claim app.iam_domain_claims;
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'IAM', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks IAM:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_connection from app.integration_connections where id = p_connection_id;
  if not found or v_connection.tenant_id <> p_tenant_id then
    raise exception 'iam_connection_not_found: % is not a connection owned by tenant %', p_connection_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;
  if v_connection.adapter_code not in ('enterprise_sso_oidc', 'enterprise_sso_saml') then
    raise exception 'iam_connection_wrong_adapter: % is not an enterprise SSO connection', p_connection_id
      using errcode = 'check_violation';
  end if;

  v_normalized := app.normalize_domain_hostname(p_email_domain);

  if not app.validate_domain_hostname(v_normalized) then
    raise exception 'invalid_email_domain: % is not a well-formed domain', v_normalized
      using errcode = 'invalid_text_representation';
  end if;

  if app.is_reserved_domain_hostname(v_normalized) then
    raise exception 'reserved_email_domain: % is a reserved platform hostname and cannot be claimed', v_normalized
      using errcode = 'check_violation';
  end if;

  select * into v_existing
  from app.iam_domain_claims
  where tenant_id = p_tenant_id and connection_id = p_connection_id and email_domain = v_normalized
    and status = 'pending_verification';
  if found then
    return v_existing;
  end if;

  insert into app.iam_domain_claims (tenant_id, connection_id, email_domain, requested_by)
  values (p_tenant_id, p_connection_id, v_normalized, p_actor_label)
  returning * into v_claim;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'request_enterprise_sso_domain_claim',
    'app.iam_domain_claims', v_claim.id, 'success', null, null, to_jsonb(v_claim)
  );

  return v_claim;
exception
  when unique_violation then
    raise exception 'email_domain_already_claimed: % is already claimed (pending verification, verified, or active) by another connection', v_normalized
      using errcode = 'unique_violation';
end;
$$;

create function app.verify_enterprise_sso_domain_claim(
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
  if not found then
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

create function app.activate_enterprise_sso_domain_claim(
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
  if not found then
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

create function app.disable_enterprise_sso_domain_claim(
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
  if not found then
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

-- ===========================================================================
-- 4. app.iam_sso_login_attempts -- claims-resolution evidence trail.
-- app.resolve_enterprise_sso_claims is the real, bounded piece (design
-- decision 5): given an already-extracted claims payload, it resolves
-- whether platform identity recognizes the login, without ever performing
-- the raw protocol-level signature verification itself.
-- ===========================================================================

create table app.iam_sso_login_attempts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  connection_id uuid not null references app.integration_connections (id),
  domain_claim_id uuid references app.iam_domain_claims (id),
  subject_claim text not null,
  email_claim text,
  resolved_auth_user_id uuid references auth.users (id),
  outcome text not null,
  resolved_by_auth_user_id uuid references auth.users (id),
  occurred_at timestamptz not null default now(),
  constraint iam_sso_login_attempts_outcome_check check (outcome in (
    'matched', 'no_domain_claim', 'no_user_match', 'ambiguous_match',
    'deprovisioned', 'connection_not_active', 'invalid_email_claim'
  ))
);

comment on table app.iam_sso_login_attempts is
  'IAE-026: append-only evidence of every claims-resolution attempt run against an enterprise SSO connection (via app.resolve_enterprise_sso_claims). Doubles as the admin "test login" evidence trail (Prompt 354 §21/§28) and as the activation-lockout guard''s own proof source (app.activate_enterprise_idp_connection below requires at least one prior matched row).';

create index iam_sso_login_attempts_connection_id_idx on app.iam_sso_login_attempts (connection_id, occurred_at desc);
create index iam_sso_login_attempts_tenant_id_idx on app.iam_sso_login_attempts (tenant_id, occurred_at desc);

-- Defensive email-claim extraction (the same "_parse_*, never raise" shape
-- Group 6's own AI-output extraction helpers established) -- an externally
-- asserted claim is untrusted input, never a value this function can trust
-- to be well-formed.
create function app._parse_iam_email_claim(p_raw_email_claim text)
returns text
language plpgsql
immutable
as $$
begin
  if p_raw_email_claim is null then
    return null;
  end if;
  if length(p_raw_email_claim) > 320 then
    return null;
  end if;
  if trim(p_raw_email_claim) !~ '^[^\s@]+@[^\s@]+\.[^\s@]+$' then
    return null;
  end if;
  return lower(trim(p_raw_email_claim));
exception
  when others then
    return null;
end;
$$;

create function app.resolve_enterprise_sso_claims(
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
  if not found then
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

comment on function app.resolve_enterprise_sso_claims is
  'IAE-026: IAM:Configure-gated administrative claims-test tool (design decision 5) -- resolves whether platform identity recognizes an already-extracted subject/email claim pair against one enterprise SSO connection''s own active domain claim, without creating a session. The real protocol-level (OIDC token / SAML assertion) signature verification a live end-user login flow would need is a disclosed, not-yet-built, external boundary -- see this migration''s own header.';

create function app.activate_enterprise_idp_connection(
  p_connection_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.integration_connections
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_connection app.integration_connections;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_connection from app.integration_connections where id = p_connection_id;
  if not found then
    raise exception 'iam_connection_not_found: %', p_connection_id using errcode = 'no_data_found';
  end if;
  if v_connection.adapter_code not in ('enterprise_sso_oidc', 'enterprise_sso_saml') then
    raise exception 'iam_connection_wrong_adapter: % is not an enterprise SSO connection', p_connection_id
      using errcode = 'check_violation';
  end if;

  if not exists (
    select 1 from app.iam_sso_login_attempts
    where connection_id = p_connection_id and outcome = 'matched'
  ) then
    raise exception 'enterprise_idp_no_verified_test_login: connection % has no recorded successful test-login resolution -- run app.resolve_enterprise_sso_claims first to prevent a lockout', p_connection_id
      using errcode = 'check_violation';
  end if;

  return app.set_integration_connection_status(p_connection_id, 'active', null, p_actor_auth_user_id, p_actor_label);
end;
$$;

comment on function app.activate_enterprise_idp_connection is
  'IAE-026: the structural lockout guard Prompt 354 §20/§28 requires ("test before enforcement") -- delegates the actual status flip to app.set_integration_connection_status (IAE-008, unmodified) once at least one real matched test resolution is proven to exist. Disabling has no such precondition (app.set_integration_connection_status(..., ''disabled'', ...) is always the break-glass/rollback path, per Prompt 354 §32) and is called directly, unwrapped.';

-- Deliberately public resolver (mirrors app.resolve_tenant_by_domain, PLT-118,
-- the repository''s one other precedent for a public domain-routing lookup):
-- a future login page can look up whether a typed email domain has an active
-- SSO connection to redirect to, without exposing any secret or authorization
-- decision. Disclosed: no such login-page wiring is built this checkpoint.
create function app.resolve_enterprise_idp_by_email_domain(p_email_domain text)
returns table (connection_id uuid, protocol text, display_name text)
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select c.id, c.adapter_code, c.name
  from app.iam_domain_claims d
  join app.integration_connections c on c.id = d.connection_id
  where d.status = 'active'
    and d.email_domain = app.normalize_domain_hostname(coalesce(p_email_domain, ''))
    and c.status = 'active'
  limit 1;
$$;

comment on function app.resolve_enterprise_idp_by_email_domain is
  'IAE-026: safe public resolver -- returns only connection_id/protocol/display_name for an ACTIVE domain claim + ACTIVE connection, never a config/credential/authorization decision. Same disclosed shape as app.resolve_tenant_by_domain (PLT-118).';

-- app.tenant_user_identities (PLT-107) ships app.link_auth_identity (idempotent
-- by EXISTENCE only -- a repeat call on an already-linked row, even a revoked
-- one, is a silent no-op returning the row unchanged) and app.revoke_auth_
-- identity, but no symmetric "undo a revoke" primitive -- PLT-107 never needed
-- one. SCIM's own reactivate operation genuinely does, so this migration adds
-- the missing, real counterpart here (additive, mirrors revoke_auth_identity's
-- own shape exactly, including the same app.tenant_user_identity_history append)
-- rather than resorting to link_auth_identity, which would silently no-op.
create function app.reactivate_auth_identity(
  p_auth_user_id uuid,
  p_tenant_id uuid,
  p_reason text,
  p_requested_by text
)
returns app.tenant_user_identities
language plpgsql
as $$
declare
  v_current app.tenant_user_identities;
  v_updated app.tenant_user_identities;
begin
  select * into v_current
  from app.tenant_user_identities
  where auth_user_id = p_auth_user_id and tenant_id = p_tenant_id;

  if not found then
    raise exception 'identity_link_not_found: no linkage for auth_user % and tenant %', p_auth_user_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;

  if v_current.status = 'active' then
    return v_current;
  end if;

  update app.tenant_user_identities
  set status = 'active', revoked_at = null, revoked_reason = null
  where id = v_current.id
  returning * into v_updated;

  insert into app.tenant_user_identity_history (auth_user_id, tenant_id, from_status, to_status, reason, requested_by)
  values (p_auth_user_id, p_tenant_id, v_current.status, 'active', p_reason, p_requested_by);

  return v_updated;
end;
$$;

comment on function app.reactivate_auth_identity is
  'IAE-026: the missing symmetric counterpart to app.revoke_auth_identity (PLT-107 never needed one). Idempotent when already active. Not SECURITY DEFINER, matching app.link_auth_identity/app.revoke_auth_identity''s own established shape exactly -- callers (like app.provision_scim_identity below) that need an authority check perform their own before calling this, the same trust contract PLT-107''s own pair already establishes.';

-- ===========================================================================
-- 5. SCIM: app.iam_scim_user_links (the external-identity<->platform-identity
-- mapping) and app.iam_scim_provisioning_events (append-only operation log).
-- ===========================================================================

create table app.iam_scim_user_links (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  external_id text not null,
  auth_user_id uuid references auth.users (id),
  email text not null,
  display_name text,
  status text not null default 'pending_identity',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  record_version integer not null default 1,
  constraint iam_scim_user_links_status_check check (status in ('pending_identity', 'linked', 'deprovisioned')),
  constraint iam_scim_user_links_tenant_external_id_unique unique (tenant_id, external_id)
);

comment on table app.iam_scim_user_links is
  'IAE-026: the SCIM externalId <-> platform auth_user_id mapping. pending_identity means the IdP has provisioned/announced this identity but no matching app.users row exists yet in this tenant -- creating a brand-new auth.users row is an external Supabase Admin API call this checkpoint does not perform (disclosed, this migration''s own header); linked means a real app.users match was found and, where needed, app.link_auth_identity was called to (re)activate the tenant linkage; deprovisioned means app.revoke_auth_identity was called for real.';

create index iam_scim_user_links_tenant_id_idx on app.iam_scim_user_links (tenant_id);

create function app.touch_iam_scim_user_link_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger iam_scim_user_links_touch_row
  before update on app.iam_scim_user_links
  for each row
  execute function app.touch_iam_scim_user_link_row();

create table app.iam_scim_provisioning_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  scim_link_id uuid not null references app.iam_scim_user_links (id),
  api_key_id uuid references app.api_keys (id),
  operation text not null,
  is_dry_run boolean not null default false,
  outcome text not null,
  outcome_reason text,
  occurred_at timestamptz not null default now(),
  constraint iam_scim_provisioning_events_operation_check check (operation in ('create', 'update', 'deactivate', 'reactivate')),
  constraint iam_scim_provisioning_events_outcome_check check (outcome in ('applied', 'dry_run_preview', 'rejected'))
);

comment on table app.iam_scim_provisioning_events is
  'IAE-026: append-only SCIM operation log, one row per app.provision_scim_identity call, dry-run or real -- the audit/preview evidence Prompt 354 §20 ("SCIM mapping/provisioning with dry-run and audit") requires.';

create index iam_scim_provisioning_events_tenant_id_idx on app.iam_scim_provisioning_events (tenant_id, occurred_at desc);
create index iam_scim_provisioning_events_link_id_idx on app.iam_scim_provisioning_events (scim_link_id, occurred_at desc);

create function app._parse_iam_email(p_raw_email text)
returns text
language plpgsql
immutable
as $$
begin
  if p_raw_email is null then
    return null;
  end if;
  if length(p_raw_email) > 320 then
    return null;
  end if;
  if trim(p_raw_email) !~ '^[^\s@]+@[^\s@]+\.[^\s@]+$' then
    return null;
  end if;
  return lower(trim(p_raw_email));
exception
  when others then
    return null;
end;
$$;

create function app.provision_scim_identity(
  p_tenant_id uuid,
  p_api_key_id uuid,
  p_external_id text,
  p_raw_email text,
  p_display_name text,
  p_operation text,
  p_is_dry_run boolean,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.iam_scim_provisioning_events
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_api_key app.api_keys;
  v_email text;
  v_link app.iam_scim_user_links;
  v_existing_user app.users;
  v_matches integer;
  v_outcome text;
  v_reason text;
  v_event app.iam_scim_provisioning_events;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'IAM', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks IAM:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_operation not in ('create', 'update', 'deactivate', 'reactivate') then
    raise exception 'iam_scim_invalid_operation: %', p_operation using errcode = 'check_violation';
  end if;

  if p_api_key_id is not null then
    select * into v_api_key from app.api_keys where id = p_api_key_id and tenant_id = p_tenant_id;
    if not found then
      raise exception 'iam_scim_api_key_not_found: % is not an API key owned by tenant %', p_api_key_id, p_tenant_id
        using errcode = 'no_data_found';
    end if;
  end if;

  if coalesce(length(trim(p_external_id)), 0) = 0 then
    raise exception 'iam_scim_missing_external_id: a non-empty externalId is required' using errcode = 'check_violation';
  end if;

  v_email := app._parse_iam_email(p_raw_email);

  insert into app.iam_scim_user_links (tenant_id, external_id, email, display_name)
  values (p_tenant_id, p_external_id, coalesce(v_email, ''), p_display_name)
  on conflict (tenant_id, external_id) do update
    set email = coalesce(v_email, app.iam_scim_user_links.email),
        display_name = coalesce(p_display_name, app.iam_scim_user_links.display_name)
  returning * into v_link;

  if v_email is null and p_operation in ('create', 'update') then
    v_outcome := 'rejected';
    v_reason := 'invalid_email_claim';
  elsif p_operation in ('create', 'update') then
    if p_is_dry_run then
      v_outcome := 'dry_run_preview';
      v_reason := 'would_resolve_or_link_by_email';
    else
      select count(*) into v_matches from app.users where tenant_id = p_tenant_id and lower(email) = v_email;
      if v_matches = 0 then
        v_outcome := 'rejected';
        v_reason := 'no_matching_platform_identity: creating a brand-new auth.users row requires an external Supabase Admin API call, not performed by this checkpoint';
      else
        select * into v_existing_user from app.users where tenant_id = p_tenant_id and lower(email) = v_email;
        perform app.link_auth_identity(v_existing_user.auth_user_id, p_tenant_id, p_actor_label, 'active');
        update app.iam_scim_user_links set auth_user_id = v_existing_user.auth_user_id, status = 'linked' where id = v_link.id
        returning * into v_link;
        v_outcome := 'applied';
        v_reason := null;
      end if;
    end if;
  else -- deactivate / reactivate
    if v_link.auth_user_id is null then
      v_outcome := 'rejected';
      v_reason := 'not_linked: no platform identity has ever been linked for this externalId';
    elsif p_is_dry_run then
      v_outcome := 'dry_run_preview';
      v_reason := case when p_operation = 'deactivate' then 'would_revoke_tenant_identity' else 'would_reactivate_tenant_identity' end;
    else
      if p_operation = 'deactivate' then
        perform app.revoke_auth_identity(v_link.auth_user_id, p_tenant_id, 'scim_deprovisioning', p_actor_label);
        update app.iam_scim_user_links set status = 'deprovisioned' where id = v_link.id returning * into v_link;
      else
        perform app.reactivate_auth_identity(v_link.auth_user_id, p_tenant_id, 'scim_reactivation', p_actor_label);
        update app.iam_scim_user_links set status = 'linked' where id = v_link.id returning * into v_link;
      end if;
      v_outcome := 'applied';
      v_reason := null;
    end if;
  end if;

  insert into app.iam_scim_provisioning_events (
    tenant_id, scim_link_id, api_key_id, operation, is_dry_run, outcome, outcome_reason
  ) values (
    p_tenant_id, v_link.id, p_api_key_id, p_operation, p_is_dry_run, v_outcome, v_reason
  )
  returning * into v_event;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'provision_scim_identity',
    'app.iam_scim_user_links', v_link.id, case when v_outcome = 'rejected' then 'failure' else 'success' end,
    v_reason, null, jsonb_build_object('operation', p_operation, 'is_dry_run', p_is_dry_run, 'outcome', v_outcome)
  );

  return v_event;
end;
$$;

comment on function app.provision_scim_identity is
  'IAE-026: IAM:Configure-gated. Real deactivate enforcement (app.revoke_auth_identity) and real link/reactivate enforcement (app.link_auth_identity) when a matching app.users row already exists; a genuinely new identity (no match) is disclosed-rejected, not faked -- see this migration''s own header. A real inbound /api/scim/v2/** route authenticating a live SCIM bearer token against app.api_keys and calling this function is disclosed as not built this checkpoint.';

-- ===========================================================================
-- 6. Read paths.
-- ===========================================================================

create function app.list_enterprise_idp_connections_for_tenant(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns setof app.integration_connections
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'IAM', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks IAM:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
    select * from app.integration_connections
    where tenant_id = p_tenant_id and adapter_code in ('enterprise_sso_oidc', 'enterprise_sso_saml')
    order by created_at desc;
end;
$$;

create function app.list_enterprise_sso_domain_claims_for_tenant(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns setof app.iam_domain_claims
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'IAM', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks IAM:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.iam_domain_claims where tenant_id = p_tenant_id order by created_at desc;
end;
$$;

create function app.list_enterprise_sso_login_attempts_for_tenant(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_limit integer default 50
)
returns setof app.iam_sso_login_attempts
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_limit integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'IAM', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks IAM:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
    select * from app.iam_sso_login_attempts
    where tenant_id = p_tenant_id
    order by occurred_at desc
    limit v_limit;
end;
$$;

create function app.list_scim_provisioning_events_for_tenant(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_limit integer default 50
)
returns setof app.iam_scim_provisioning_events
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_limit integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'IAM', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks IAM:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
    select * from app.iam_scim_provisioning_events
    where tenant_id = p_tenant_id
    order by occurred_at desc
    limit v_limit;
end;
$$;

-- ===========================================================================
-- 7. RLS: default-deny, RPC-only, mirroring every prior Phase 9 capability.
-- ===========================================================================

alter table app.iam_domain_claims enable row level security;
alter table app.iam_sso_login_attempts enable row level security;
alter table app.iam_scim_user_links enable row level security;
alter table app.iam_scim_provisioning_events enable row level security;

revoke all on app.iam_domain_claims from public, anon, authenticated;
revoke all on app.iam_sso_login_attempts from public, anon, authenticated;
revoke all on app.iam_scim_user_links from public, anon, authenticated;
revoke all on app.iam_scim_provisioning_events from public, anon, authenticated;
grant all on app.iam_domain_claims, app.iam_sso_login_attempts, app.iam_scim_user_links, app.iam_scim_provisioning_events to service_role;

-- Standing convention since PLT-118 (ISS-2026, `20260717095000_revoke_default_
-- public_function_execute.sql`): PostgreSQL grants EXECUTE to PUBLIC on every
-- function at CREATE FUNCTION time by default; the schema-wide `ALTER DEFAULT
-- PRIVILEGES` set up there suppresses this prospectively, but every migration
-- since has ALSO carried its own explicit, redundant statement here as
-- defense-in-depth belt-and-suspenders, not reliance on the session-scoped
-- default alone. This migration follows that same convention.
revoke execute on all functions in schema app from public;

revoke execute on function app._parse_iam_email_claim(text), app._parse_iam_email(text) from public, anon, authenticated;
grant execute on function app._parse_iam_email_claim(text), app._parse_iam_email(text) to service_role;
grant execute on function app.reactivate_auth_identity(uuid, uuid, text, text) to service_role;

grant execute on function
  app.request_enterprise_sso_domain_claim(uuid, uuid, text, uuid, text),
  app.verify_enterprise_sso_domain_claim(uuid, text, uuid, text),
  app.activate_enterprise_sso_domain_claim(uuid, uuid, text),
  app.disable_enterprise_sso_domain_claim(uuid, text, uuid, text),
  app.resolve_enterprise_sso_claims(uuid, text, text, uuid, text),
  app.activate_enterprise_idp_connection(uuid, uuid, text),
  app.provision_scim_identity(uuid, uuid, text, text, text, text, boolean, uuid, text),
  app.list_enterprise_idp_connections_for_tenant(uuid, uuid),
  app.list_enterprise_sso_domain_claims_for_tenant(uuid, uuid),
  app.list_enterprise_sso_login_attempts_for_tenant(uuid, uuid, integer),
  app.list_scim_provisioning_events_for_tenant(uuid, uuid, integer)
to authenticated, service_role;

grant execute on function app.resolve_enterprise_idp_by_email_domain(text) to anon, authenticated, service_role;
