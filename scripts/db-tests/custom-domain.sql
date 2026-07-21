-- Real, executable test evidence for PLT-118 (Custom Domain, CG-S6-PLT-015).

\set ON_ERROR_STOP on

\echo '>> setup: two tenants each with a tenant_admin and a regular org_user, a global Supreme Admin'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000001001', 'tenantadmindom@example.test'),
    ('00000000-0000-0000-0000-000000001002', 'regularuserdom@example.test'),
    ('00000000-0000-0000-0000-000000001003', 'supremedom@example.test'),
    ('00000000-0000-0000-0000-000000001004', 'othertenantadmindom@example.test');

  perform app.provision_tenant('acmedom', 'Acme Domain Co', 'idem-acmedom', 'tester');
  v_tenant_id := (select id from app.tenants where slug = 'acmedom');
  perform app.transition_tenant_status(v_tenant_id, 'active', 'setup', 'tester');
  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000001001', 'tenantadmindom@example.test', 'Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'tenantadmindom@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000001001', 'tenant_admin', v_tenant_id, null, 'tester');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000001002', 'regularuserdom@example.test', 'Regular User', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'regularuserdom@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000001002', 'org_user', v_tenant_id, null, 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000001003', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('gizmodom', 'Gizmo Domain Co', 'idem-gizmodom', 'tester');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmodom');
  perform app.transition_tenant_status(v_other_tenant_id, 'active', 'setup', 'tester');
  perform app.invite_user(v_other_tenant_id, '00000000-0000-0000-0000-000000001004', 'othertenantadmindom@example.test', 'Other Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'othertenantadmindom@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000001004', 'tenant_admin', v_other_tenant_id, null, 'tester');
end;
$$;

\echo '>> app.normalize_domain_hostname / app.validate_domain_hostname: normalization and IDN/uppercase/trailing-dot/IP-literal handling'
do $$
begin
  if app.normalize_domain_hostname('Shipping.Acme.Example.') <> 'shipping.acme.example' then
    raise exception 'assertion failed: expected uppercase + trailing dot to normalize to lowercase, no trailing dot';
  end if;
  if app.normalize_domain_hostname('  shipping.acme.example  ') <> 'shipping.acme.example' then
    raise exception 'assertion failed: expected surrounding whitespace to be trimmed';
  end if;

  if not app.validate_domain_hostname('shipping.acme.example') then
    raise exception 'assertion failed: expected a well-formed two-label hostname to validate';
  end if;
  if not app.validate_domain_hostname('xn--caf-dma.example.test') then
    raise exception 'assertion failed: expected a punycode-encoded IDN label to validate';
  end if;
  if app.validate_domain_hostname('café.example.test') then
    raise exception 'assertion failed: expected a raw Unicode IDN label to be rejected (no homograph support)';
  end if;
  if app.validate_domain_hostname('localhost') then
    raise exception 'assertion failed: expected a bare single-label hostname to be rejected';
  end if;
  if app.validate_domain_hostname('192.168.1.1') then
    raise exception 'assertion failed: expected an IPv4-literal string to be rejected (all-numeric TLD)';
  end if;
  if app.validate_domain_hostname('SHIPPING.ACME.EXAMPLE') then
    raise exception 'assertion failed: expected an un-normalized uppercase hostname to fail structural validation';
  end if;

  if not app.is_reserved_domain_hostname('cargogrid.app') then
    raise exception 'assertion failed: expected the platform apex to be reserved';
  end if;
  if not app.is_reserved_domain_hostname('tenant.cargogrid.app') then
    raise exception 'assertion failed: expected a platform subdomain to be reserved';
  end if;
  if not app.is_reserved_domain_hostname('localhost') then
    raise exception 'assertion failed: expected localhost to be reserved';
  end if;
  if app.is_reserved_domain_hostname('shipping.acme.example') then
    raise exception 'assertion failed: expected an ordinary external hostname to not be reserved';
  end if;
end;
$$;

\echo '>> app.tenant_custom_domains CHECK constraints: an un-normalized or malformed hostname is rejected structurally'
do $$
declare
  v_tenant_id uuid;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmedom');

  begin
    insert into app.tenant_custom_domains (tenant_id, hostname) values (v_tenant_id, 'Shipping.Acme.Example');
    raise exception 'assertion failed: expected an un-normalized (uppercase) hostname to violate the normalized-form CHECK constraint';
  exception
    when check_violation then
      null;
  end;

  begin
    insert into app.tenant_custom_domains (tenant_id, hostname) values (v_tenant_id, 'not a hostname');
    raise exception 'assertion failed: expected a malformed hostname to violate the format CHECK constraint';
  exception
    when check_violation then
      null;
  end;
end;
$$;

\echo '>> app.request_tenant_domain: authority-gated, rejects reserved/invalid hostnames, idempotent for a repeated pending request'
do $$
declare
  v_tenant_id uuid;
  v_domain1 app.tenant_custom_domains;
  v_domain2 app.tenant_custom_domains;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmedom');

  begin
    perform app.request_tenant_domain(v_tenant_id, '00000000-0000-0000-0000-000000001002', 'shipping.acme.example', 'regular user');
    raise exception 'assertion failed: expected a regular org_user to be denied';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.request_tenant_domain(v_tenant_id, '00000000-0000-0000-0000-000000001001', 'cargogrid.app', 'tenant admin');
    raise exception 'assertion failed: expected a reserved hostname to be rejected';
  exception
    when check_violation then
      null;
  end;

  begin
    perform app.request_tenant_domain(v_tenant_id, '00000000-0000-0000-0000-000000001001', 'not a hostname', 'tenant admin');
    raise exception 'assertion failed: expected a malformed hostname to be rejected';
  exception
    when invalid_text_representation then
      null;
  end;

  v_domain1 := app.request_tenant_domain(v_tenant_id, '00000000-0000-0000-0000-000000001001', 'Shipping.Acme.Example.', 'tenant admin');
  if v_domain1.hostname <> 'shipping.acme.example' then
    raise exception 'assertion failed: expected the stored hostname to be normalized, got %', v_domain1.hostname;
  end if;
  if v_domain1.status <> 'pending_verification' then
    raise exception 'assertion failed: expected a fresh request to be pending_verification, got %', v_domain1.status;
  end if;
  if v_domain1.verification_challenge_host <> '_cargogrid-verify.shipping.acme.example' then
    raise exception 'assertion failed: unexpected verification_challenge_host %', v_domain1.verification_challenge_host;
  end if;

  v_domain2 := app.request_tenant_domain(v_tenant_id, '00000000-0000-0000-0000-000000001001', 'shipping.acme.example', 'tenant admin');
  if v_domain2.id <> v_domain1.id or v_domain2.verification_token <> v_domain1.verification_token then
    raise exception 'assertion failed: expected a repeated request to return the same pending row with the same token, not regenerate it';
  end if;
end;
$$;

\echo '>> takeover prevention: a second tenant cannot claim a hostname another tenant already has live (pending/verified/active)'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmedom');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmodom');

  begin
    perform app.request_tenant_domain(v_other_tenant_id, '00000000-0000-0000-0000-000000001004', 'shipping.acme.example', 'other tenant admin');
    raise exception 'assertion failed: expected a second tenant''s claim on a live hostname to be rejected';
  exception
    when unique_violation then
      null;
  end;
end;
$$;

\echo '>> app.verify_tenant_domain: rejects a wrong observed TXT value, requires pending_verification status, succeeds with the exact issued token'
do $$
declare
  v_tenant_id uuid;
  v_pending app.tenant_custom_domains;
  v_verified app.tenant_custom_domains;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmedom');
  select * into v_pending from app.tenant_custom_domains where tenant_id = v_tenant_id and hostname = 'shipping.acme.example';

  begin
    perform app.verify_tenant_domain(v_pending.id, '00000000-0000-0000-0000-000000001001', 'the-wrong-value', 'tenant admin');
    raise exception 'assertion failed: expected a mismatched observed TXT value to be rejected';
  exception
    when check_violation then
      null;
  end;

  begin
    perform app.verify_tenant_domain(v_pending.id, '00000000-0000-0000-0000-000000001002', v_pending.verification_token, 'regular user');
    raise exception 'assertion failed: expected a regular org_user to be denied verification authority';
  exception
    when insufficient_privilege then
      null;
  end;

  v_verified := app.verify_tenant_domain(v_pending.id, '00000000-0000-0000-0000-000000001001', v_pending.verification_token, 'tenant admin');
  if v_verified.status <> 'verified' or v_verified.verified_by <> 'tenant admin' then
    raise exception 'assertion failed: expected the domain to become verified with the correct actor label';
  end if;

  begin
    perform app.verify_tenant_domain(v_verified.id, '00000000-0000-0000-0000-000000001001', v_verified.verification_token, 'tenant admin');
    raise exception 'assertion failed: expected re-verifying an already-verified domain to be rejected';
  exception
    when check_violation then
      null;
  end;
end;
$$;

\echo '>> app.activate_tenant_domain: only a verified domain may be activated; app.resolve_tenant_by_domain now resolves it'
do $$
declare
  v_tenant_id uuid;
  v_verified app.tenant_custom_domains;
  v_active app.tenant_custom_domains;
  v_resolved record;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmedom');
  select * into v_verified from app.tenant_custom_domains where tenant_id = v_tenant_id and hostname = 'shipping.acme.example';

  select * into v_resolved from app.resolve_tenant_by_domain('shipping.acme.example');
  if v_resolved.resolved_tenant_id is not null then
    raise exception 'assertion failed: expected a verified-but-not-yet-active domain to not resolve';
  end if;

  v_active := app.activate_tenant_domain(v_verified.id, '00000000-0000-0000-0000-000000001001', 'tenant admin');
  if v_active.status <> 'active' then
    raise exception 'assertion failed: expected the domain to become active, got %', v_active.status;
  end if;

  select * into v_resolved from app.resolve_tenant_by_domain('shipping.acme.example');
  if v_resolved.resolved_tenant_id <> v_tenant_id then
    raise exception 'assertion failed: expected the now-active domain to resolve to its own tenant';
  end if;

  begin
    perform app.activate_tenant_domain(v_active.id, '00000000-0000-0000-0000-000000001001', 'tenant admin');
    raise exception 'assertion failed: expected re-activating an already-active domain to be rejected';
  exception
    when check_violation then
      null;
  end;
end;
$$;

\echo '>> app.resolve_tenant_by_domain: cross-tenant isolation, hostname-not-found, and case-insensitive Host header lookup'
do $$
declare
  v_tenant_id uuid;
  v_resolved record;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmedom');

  select * into v_resolved from app.resolve_tenant_by_domain('never-claimed.example.test');
  if v_resolved.resolved_tenant_id is not null then
    raise exception 'assertion failed: expected an unclaimed hostname to resolve to nothing';
  end if;

  select * into v_resolved from app.resolve_tenant_by_domain('SHIPPING.ACME.EXAMPLE');
  if v_resolved.resolved_tenant_id <> v_tenant_id then
    raise exception 'assertion failed: expected the resolver to normalize a mixed-case Host header before lookup';
  end if;
end;
$$;

\echo '>> app.resolve_tenant_by_domain: an active domain belonging to a now-suspended tenant no longer resolves (never a stale/wrong tenant)'
do $$
declare
  v_tenant_id uuid;
  v_resolved record;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmedom');
  perform app.transition_tenant_status(v_tenant_id, 'suspended', 'billing hold', 'tester');

  select * into v_resolved from app.resolve_tenant_by_domain('shipping.acme.example');
  if v_resolved.resolved_tenant_id is not null then
    raise exception 'assertion failed: expected a suspended tenant''s domain to no longer resolve';
  end if;

  perform app.transition_tenant_status(v_tenant_id, 'active', 'billing resolved', 'tester');
  select * into v_resolved from app.resolve_tenant_by_domain('shipping.acme.example');
  if v_resolved.resolved_tenant_id <> v_tenant_id then
    raise exception 'assertion failed: expected resolution to resume once the tenant is active again';
  end if;
end;
$$;

\echo '>> app.disable_tenant_domain: the kill switch stops resolution and frees the hostname for rebinding'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
  v_active app.tenant_custom_domains;
  v_disabled app.tenant_custom_domains;
  v_resolved record;
  v_rebound app.tenant_custom_domains;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmedom');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmodom');
  select * into v_active from app.tenant_custom_domains where tenant_id = v_tenant_id and hostname = 'shipping.acme.example';

  v_disabled := app.disable_tenant_domain(v_active.id, '00000000-0000-0000-0000-000000001001', 'switching providers', 'tenant admin');
  if v_disabled.status <> 'disabled' or v_disabled.disabled_reason <> 'switching providers' then
    raise exception 'assertion failed: expected the domain to be disabled with the given reason';
  end if;

  select * into v_resolved from app.resolve_tenant_by_domain('shipping.acme.example');
  if v_resolved.resolved_tenant_id is not null then
    raise exception 'assertion failed: expected a disabled domain to no longer resolve';
  end if;

  -- Rebinding: the exact same hostname is now claimable by a *different* tenant.
  v_rebound := app.request_tenant_domain(v_other_tenant_id, '00000000-0000-0000-0000-000000001004', 'shipping.acme.example', 'other tenant admin');
  if v_rebound.tenant_id <> v_other_tenant_id then
    raise exception 'assertion failed: expected the freed hostname to be claimable by a different tenant';
  end if;

  begin
    perform app.disable_tenant_domain(v_disabled.id, '00000000-0000-0000-0000-000000001001', 'x', 'tenant admin');
    raise exception 'assertion failed: expected disabling an already-disabled domain to be rejected';
  exception
    when check_violation then
      null;
  end;

  -- Clean up the rebound claim so later tests in this file that also touch this hostname are unaffected.
  perform app.reject_tenant_domain(v_rebound.id, '00000000-0000-0000-0000-000000001004', 'test cleanup', 'other tenant admin');
end;
$$;

\echo '>> app.reject_tenant_domain: only a pending_verification domain may be rejected; a rejected domain frees its hostname'
do $$
declare
  v_tenant_id uuid;
  v_pending app.tenant_custom_domains;
  v_rejected app.tenant_custom_domains;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmedom');
  v_pending := app.request_tenant_domain(v_tenant_id, '00000000-0000-0000-0000-000000001001', 'billing.acme.example', 'tenant admin');

  v_rejected := app.reject_tenant_domain(v_pending.id, '00000000-0000-0000-0000-000000001003', 'suspicious hostname', 'supreme admin');
  if v_rejected.status <> 'rejected' or v_rejected.rejected_by <> 'supreme admin' then
    raise exception 'assertion failed: expected Supreme Admin to be able to reject a pending request';
  end if;

  begin
    perform app.reject_tenant_domain(v_rejected.id, '00000000-0000-0000-0000-000000001001', 'x', 'tenant admin');
    raise exception 'assertion failed: expected rejecting an already-rejected domain to be rejected';
  exception
    when check_violation then
      null;
  end;
end;
$$;

\echo '>> app.expire_stale_domain_verifications: a pending request past its expiry is auto-expired, an unexpired one is untouched'
do $$
declare
  v_tenant_id uuid;
  v_stale app.tenant_custom_domains;
  v_fresh app.tenant_custom_domains;
  v_expired_count integer;
  v_after_stale app.tenant_custom_domains;
  v_after_fresh app.tenant_custom_domains;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmedom');
  v_stale := app.request_tenant_domain(v_tenant_id, '00000000-0000-0000-0000-000000001001', 'stale-request.acme.example', 'tenant admin');
  update app.tenant_custom_domains set expires_at = now() - interval '1 hour' where id = v_stale.id;

  v_fresh := app.request_tenant_domain(v_tenant_id, '00000000-0000-0000-0000-000000001001', 'fresh-request.acme.example', 'tenant admin');

  v_expired_count := app.expire_stale_domain_verifications();
  if v_expired_count < 1 then
    raise exception 'assertion failed: expected at least one domain to be expired, saw %', v_expired_count;
  end if;

  select * into v_after_stale from app.tenant_custom_domains where id = v_stale.id;
  if v_after_stale.status <> 'expired' then
    raise exception 'assertion failed: expected the stale request to become expired, got %', v_after_stale.status;
  end if;

  select * into v_after_fresh from app.tenant_custom_domains where id = v_fresh.id;
  if v_after_fresh.status <> 'pending_verification' then
    raise exception 'assertion failed: expected the fresh request to remain untouched, got %', v_after_fresh.status;
  end if;

  -- An expired hostname is claimable again, same as disabled/rejected.
  perform app.request_tenant_domain(v_tenant_id, '00000000-0000-0000-0000-000000001001', 'stale-request.acme.example', 'tenant admin');
end;
$$;

\echo '>> every lifecycle mutation self-captures a canonical app.audit_logs entry (no bespoke *_history table exists for this capability)'
do $$
declare
  v_tenant_id uuid;
  v_actions text[] := array['request_tenant_domain', 'verify_tenant_domain', 'activate_tenant_domain', 'disable_tenant_domain', 'reject_tenant_domain'];
  v_action text;
  v_count integer;
  v_system_count integer;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmedom');

  foreach v_action in array v_actions loop
    select count(*) into v_count
    from app.audit_logs
    where tenant_id = v_tenant_id and action = v_action and resource_type = 'app.tenant_custom_domains';
    if v_count = 0 then
      raise exception 'assertion failed: expected at least one app.audit_logs entry for action=%, saw none', v_action;
    end if;
  end loop;

  select count(*) into v_system_count
  from app.audit_logs
  where action = 'expire_stale_domain_verifications' and actor_label = 'system' and tenant_id is null;
  if v_system_count = 0 then
    raise exception 'assertion failed: expected a platform-wide (null tenant_id) system audit entry for the batch expiry';
  end if;
end;
$$;

\echo '>> app.list_tenant_domains: authority-gated, tenant-scoped view-model read'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
  v_own_domains app.tenant_custom_domains[];
  v_count integer;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmedom');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmodom');

  select count(*) into v_count from app.list_tenant_domains(v_tenant_id, '00000000-0000-0000-0000-000000001001');
  if v_count = 0 then
    raise exception 'assertion failed: expected the tenant admin to see at least one of their own domains';
  end if;

  begin
    perform app.list_tenant_domains(v_tenant_id, '00000000-0000-0000-0000-000000001004');
    raise exception 'assertion failed: expected a different tenant''s admin to be denied';
  exception
    when insufficient_privilege then
      null;
  end;

  -- Supreme Admin may list any tenant's domains.
  select count(*) into v_count from app.list_tenant_domains(v_other_tenant_id, '00000000-0000-0000-0000-000000001003');
  if v_count = 0 then
    raise exception 'assertion failed: expected Supreme Admin to be able to list gizmodom''s domains';
  end if;
end;
$$;

\echo '>> schema-privilege defense in depth: authenticated/anon have no direct table access; anon holds EXECUTE only on the public resolver'
do $$
declare
  v_has_privilege boolean;
begin
  select has_table_privilege('authenticated', 'app.tenant_custom_domains', 'SELECT') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected authenticated to hold no direct SELECT privilege on app.tenant_custom_domains';
  end if;

  select has_table_privilege('anon', 'app.tenant_custom_domains', 'SELECT') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected anon to hold no direct SELECT privilege on app.tenant_custom_domains';
  end if;

  select has_function_privilege('anon', 'app.resolve_tenant_by_domain(text)', 'EXECUTE') into v_has_privilege;
  if not v_has_privilege then
    raise exception 'assertion failed: expected anon to hold EXECUTE on app.resolve_tenant_by_domain (needed pre-authentication for inbound routing)';
  end if;

  select has_function_privilege('anon', 'app.list_tenant_domains(uuid, uuid)', 'EXECUTE') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected anon to hold no EXECUTE on the authority-gated app.list_tenant_domains';
  end if;
end;
$$;
