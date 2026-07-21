-- Platform Core capability PLT-118 (Custom Domain, CG-S6-PLT-015)
-- Tenant custom-domain lifecycle: request -> verify -> activate -> disable, plus a
-- reject/expire path, with a safe public hostname->tenant resolver for routing context
-- (Prompt 118 §4/§20/§24). Builds on `PLT-107`'s Supabase Auth linkage and `PLT-117`'s
-- white-label evaluator (a resolved tenant_id from this migration is the natural input
-- to `app.evaluate_tenant_brand()` for rendering, though that composition is a future
-- caller's responsibility, not built here).
--
-- Scope, disclosed rather than left implicit (matching every prior checkpoint's
-- discipline):
--
-- * "No live DNS/cert mutation without external authority" (§12, forbidden). This
--   migration never queries or mutates real DNS/TLS state -- it cannot, from inside a
--   database migration. `app.verify_tenant_domain()`'s `p_observed_txt_value` parameter
--   is the provider-independent verification *interface* (§20 task 2): a future external
--   job performs the actual DNS TXT lookup and passes its observed value in; this
--   function only compares that value against the stored challenge token and transitions
--   state atomically. The DNS-lookup job itself, and any TLS/certificate provisioning,
--   are disclosed `NOT_RUN` -- no such job/adapter exists yet (`JOB`/`API-WH` are
--   `PLT-129..132`, downstream), the same "mechanism proven, live wiring deferred"
--   posture `PLT-107` established for GoTrue.
-- * **Full Unicode IDN is deliberately out of scope.** `app.validate_domain_hostname()`
--   accepts only ASCII hostnames (including already-punycode-encoded IDN labels, e.g.
--   `xn--caf-dma.example.test`) -- a raw Unicode domain (e.g. `café.example.test`) is
--   rejected outright, proven in `scripts/db-tests/custom-domain.sql`. This is a
--   deliberate, disclosed security-conscious boundary (Unicode homograph/lookalike-
--   domain attacks are a real, well-known phishing vector), not an oversight; a caller
--   that already has a punycode-converted hostname is unaffected.
-- * **Reserved-hostname rejection is a real, disclosed, bounded list** (`app.
--   is_reserved_domain_hostname()`): the platform's own apex/subdomain namespace
--   (`cargogrid.app` and any `*.cargogrid.app`), `localhost`, and any IPv4-literal-
--   shaped string. The single-alpha-TLD requirement inside `app.
--   validate_domain_hostname()`'s own regex already structurally excludes bare IP
--   literals from ever validating as a hostname in the first place; the IPv4 branch of
--   `is_reserved_domain_hostname()` is kept anyway as an explicit, independently-testable
--   defense-in-depth check, not dead code.
-- * **"Custom domain changes presentation/routing, not access authorization"** (§24,
--   verbatim) is a structural property, not a convention: `app.resolve_tenant_by_domain()`
--   returns a bare `tenant_id`/`canonical_status` pair with no permission/role/session
--   information whatsoever -- nothing this function returns can be substituted for
--   `PLT-108`'s `app.resolve_access_context()` or any RBAC/RLS check. A caller that
--   mistakenly treated a resolved tenant_id as an authorization decision would still hit
--   every existing RLS policy/RPC authority check unchanged.
-- * A tenant may hold multiple simultaneously active custom domains (no per-tenant
--   uniqueness) -- only the *hostname* is exclusive while a claim on it is live (§24:
--   "One domain maps to one active tenant at a time"), enforced by a partial unique
--   index spanning `pending_verification`/`verified`/`active` together (the states in
--   which a claim is live) -- once a domain is `disabled`/`rejected`/`expired`, the exact
--   same hostname string becomes claimable again by any tenant (real-world domain
--   ownership does change hands), proven directly as the "rebinding" test.

-- Normalization is applied once, inside app.request_tenant_domain() below, before a row
-- is ever inserted -- callers never see a raw, un-normalized value stored. The CHECK
-- constraints on the table itself are the structural backstop (any other insert path,
-- present or future, cannot bypass normalization), the same "database guarantee, not an
-- application convention" discipline `PLT-117`'s token/asset validation established.
create function app.normalize_domain_hostname(p_hostname text)
returns text
language sql
immutable
as $$
  select lower(trim(both '.' from trim(both from p_hostname)));
$$;

comment on function app.normalize_domain_hostname is
  'PLT-118: lowercases, trims surrounding whitespace, and trims a leading/trailing dot from a raw hostname input -- applied once by app.request_tenant_domain() before validation/storage.';

-- Requires at least two labels (no bare single-label hostname), each RFC-1123-shaped
-- (alphanumeric, internal hyphens only, no leading/trailing hyphen, <=63 chars per
-- label), and an alphabetic-only final label (a real domain TLD is never all-numeric --
-- this alone already structurally excludes any IPv4-literal string from ever validating).
create function app.validate_domain_hostname(p_hostname text)
returns boolean
language sql
immutable
as $$
  select p_hostname is not null
    and length(p_hostname) <= 253
    and p_hostname ~ '^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$';
$$;

comment on function app.validate_domain_hostname is
  'PLT-118: structural hostname-format check on an already-normalized (lowercase, no surrounding/trailing dot) value. ASCII/punycode only -- a raw Unicode IDN label is rejected (see this migration''s own header). Applied as a table CHECK constraint, not merely an application convention.';

create function app.is_reserved_domain_hostname(p_hostname text)
returns boolean
language sql
immutable
as $$
  select p_hostname = 'cargogrid.app'
    or p_hostname like '%.cargogrid.app'
    or p_hostname = 'localhost'
    or p_hostname ~ '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$';
$$;

comment on function app.is_reserved_domain_hostname is
  'PLT-118: the platform''s own apex/subdomain namespace, localhost, and IPv4-literal-shaped strings can never be claimed as a tenant custom domain. Checked by app.request_tenant_domain() -- not a table CHECK constraint, since "reserved" is a business rule about *who* may hold a hostname, not a structural shape property of the value itself.';

-- 64 random hex characters (two concatenated gen_random_uuid() values, dashes removed)
-- -- reuses the same gen_random_uuid() primitive already relied on throughout this
-- repository rather than introducing a new pgcrypto dependency (gen_random_bytes) for
-- one token generator.
create function app.generate_domain_verification_token()
returns text
language sql
volatile
as $$
  select replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
$$;

create table app.tenant_custom_domains (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  hostname text not null,
  status text not null default 'pending_verification',
  verification_method text not null default 'dns_txt',
  verification_token text not null default app.generate_domain_verification_token(),
  verification_challenge_host text generated always as ('_cargogrid-verify.' || hostname) stored,
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
  constraint tenant_custom_domains_status_check check (status in (
    'pending_verification', 'verified', 'active', 'disabled', 'rejected', 'expired'
  )),
  constraint tenant_custom_domains_verification_method_check check (verification_method in ('dns_txt')),
  constraint tenant_custom_domains_hostname_normalized_check check (hostname = app.normalize_domain_hostname(hostname)),
  constraint tenant_custom_domains_hostname_valid_check check (app.validate_domain_hostname(hostname))
);

comment on table app.tenant_custom_domains is
  'Tenant custom-domain lifecycle (PLT-118): pending_verification -> verified -> active, with disabled/rejected/expired terminal branches. hostname is only exclusive while a claim on it is live -- see the partial unique index below and this migration''s own header.';

create index tenant_custom_domains_tenant_id_idx on app.tenant_custom_domains (tenant_id);
create index tenant_custom_domains_hostname_idx on app.tenant_custom_domains (hostname);
-- The core takeover/rebinding-prevention guarantee (§24/§25): at most one row per
-- hostname across the three "claim is live" states at any time -- a second tenant's
-- request for the same hostname is rejected by this index, atomically, regardless of
-- application-level ordering (the real defense against a concurrent-request race, not
-- merely an app-level check-then-insert).
create unique index tenant_custom_domains_hostname_live_claim_unique
  on app.tenant_custom_domains (hostname) where status in ('pending_verification', 'verified', 'active');
-- Fast lookup for app.expire_stale_domain_verifications() below.
create index tenant_custom_domains_pending_expiry_idx
  on app.tenant_custom_domains (expires_at) where status = 'pending_verification';

create function app.touch_tenant_custom_domain_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger tenant_custom_domains_touch_row
  before update on app.tenant_custom_domains
  for each row
  execute function app.touch_tenant_custom_domain_row();

-- Authority: "Tenant Admin manages own domains; Supreme oversees... with audit" (§26) --
-- app.is_support_grant_authority() (PLT-115) reused verbatim, the same authority check
-- every PLT-117 mutation already uses. Idempotent: a repeated request for the exact
-- same (tenant_id, hostname) while the prior request is still pending_verification
-- returns that existing row rather than raising or regenerating its token.
create function app.request_tenant_domain(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_hostname text,
  p_requested_by text
)
returns app.tenant_custom_domains
language plpgsql
as $$
declare
  v_normalized text;
  v_existing app.tenant_custom_domains;
  v_domain app.tenant_custom_domains;
begin
  if not app.is_support_grant_authority(p_actor_auth_user_id, p_tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_normalized := app.normalize_domain_hostname(p_hostname);

  if not app.validate_domain_hostname(v_normalized) then
    raise exception 'invalid_hostname: % is not a well-formed domain hostname', v_normalized
      using errcode = 'invalid_text_representation';
  end if;

  if app.is_reserved_domain_hostname(v_normalized) then
    raise exception 'reserved_hostname: % is a reserved platform hostname and cannot be claimed', v_normalized
      using errcode = 'check_violation';
  end if;

  select * into v_existing
  from app.tenant_custom_domains
  where tenant_id = p_tenant_id and hostname = v_normalized and status = 'pending_verification';
  if found then
    return v_existing;
  end if;

  insert into app.tenant_custom_domains (tenant_id, hostname, requested_by)
  values (p_tenant_id, v_normalized, p_requested_by)
  returning * into v_domain;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_requested_by, 'request_tenant_domain',
    'app.tenant_custom_domains', v_domain.id, 'success', null, null, to_jsonb(v_domain)
  );

  return v_domain;
exception
  when unique_violation then
    raise exception 'domain_already_claimed: % is already claimed (pending verification, verified, or active) by another tenant', v_normalized
      using errcode = 'unique_violation';
end;
$$;

-- The provider-independent verification interface (§20 task 2, this migration's own
-- header): p_observed_txt_value is whatever a future external DNS-lookup job actually
-- read from the challenge host's TXT record -- compared here against the stored
-- verification_token, never re-derived or trusted from the caller's own claim about
-- success.
create function app.verify_tenant_domain(
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
  if not found then
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

create function app.activate_tenant_domain(
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
  if not found then
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

-- The kill switch: works from either 'verified' or 'active' (an admin may want to pull
-- a domain before it ever goes live, not only after) -- never from 'pending_verification'
-- (use app.reject_tenant_domain() for that) or a terminal state.
create function app.disable_tenant_domain(
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
  if not found then
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

-- Manual rejection of a still-pending request (abuse mitigation -- e.g. a hostname an
-- operator judges suspicious even though it passed format/reserved checks).
create function app.reject_tenant_domain(
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
  if not found then
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

-- Batch maintenance (§20 task 4's "cert failure/expiry" side, applied to verification
-- expiry): a system action, not an individual actor's -- one summary app.audit_logs
-- entry naming the affected count rather than one row-level actor per expiry, since no
-- human/session triggered any individual transition. No live JOB scheduler exists yet
-- to call this on a cadence (PLT-132, downstream) -- disclosed `NOT_RUN` wiring, the
-- function itself is real and directly callable/testable today.
create function app.expire_stale_domain_verifications()
returns integer
language plpgsql
as $$
declare
  v_count integer;
begin
  with expired as (
    update app.tenant_custom_domains
    set status = 'expired'
    where status = 'pending_verification' and expires_at < now()
    returning id, tenant_id
  )
  select count(*) into v_count from expired;

  if v_count > 0 then
    perform app.capture_audit_event(
      null, null, 'system', 'expire_stale_domain_verifications',
      'app.tenant_custom_domains', null, 'success', null, null, jsonb_build_object('expired_count', v_count)
    );
  end if;

  return v_count;
end;
$$;

-- Admin view-model read path (§15: "Admin view models for DNS guidance/verification/
-- error"). Authority-gated identically to every mutation above -- a tenant sees only its
-- own domains, Supreme Admin sees any tenant's on request.
create function app.list_tenant_domains(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid
)
returns setof app.tenant_custom_domains
language plpgsql
as $$
begin
  if not app.is_support_grant_authority(p_actor_auth_user_id, p_tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
    select * from app.tenant_custom_domains where tenant_id = p_tenant_id order by created_at desc;
end;
$$;

-- The safe public resolver (§14/§25): hostname (already normalized by the caller, or
-- normalized here defensively) -> tenant_id, returned only when a domain is 'active'
-- AND the owning tenant is itself 'active' -- an inactive tenant's domain resolves to no
-- row at all, never a stale/wrong tenant. SECURITY DEFINER + fixed search_path because
-- `authenticated`/`anon` are never granted direct SELECT on app.tenant_custom_domains
-- itself; STABLE (not IMMUTABLE) since the result depends on live table state.
-- Structurally returns *only* tenant_id/canonical_status -- see this migration's own
-- header for why that alone can never substitute for a real authorization decision.
create function app.resolve_tenant_by_domain(p_hostname text)
returns table (
  domain_id uuid,
  resolved_tenant_id uuid,
  tenant_canonical_status text
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_normalized text := app.normalize_domain_hostname(p_hostname);
  v_domain app.tenant_custom_domains;
  v_tenant app.tenants;
begin
  select * into v_domain
  from app.tenant_custom_domains d
  where d.hostname = v_normalized and d.status = 'active';

  if not found then
    return;
  end if;

  select * into v_tenant from app.tenants t where t.id = v_domain.tenant_id;
  if not found or v_tenant.canonical_status <> 'active' then
    return;
  end if;

  return query select v_domain.id, v_domain.tenant_id, v_tenant.canonical_status;
end;
$$;

comment on function app.resolve_tenant_by_domain is
  'Safe public hostname->tenant resolver (PLT-118). Returns zero rows (never a wrong/stale tenant) unless the domain is currently active AND its owning tenant is currently active. Presentation/routing context only -- never an authorization decision, see this migration''s own header.';

alter table app.tenant_custom_domains enable row level security;

-- Defense-in-depth, redundant with 20260717095000_revoke_default_public_function_execute.sql
-- (applied immediately before this migration, which also sets ALTER DEFAULT PRIVILEGES
-- so this repository's functions never receive a PUBLIC EXECUTE grant again): an
-- explicit, directly-provable statement in this migration's own text rather than
-- relying solely on the session-scoped default-privilege setting from a separate file.
-- See that migration's own header for the full disclosure of the real, severe,
-- repository-wide gap it corrects (every function created through PLT-117 was
-- PUBLIC/anon-executable). Adopted here as the new standing convention going forward.
revoke execute on all functions in schema app from public;

-- No RLS SELECT policy for authenticated/anon -- deliberately, matching PLT-117's
-- app.tenant_brand_versions posture: the only read paths for anyone but service_role are
-- app.resolve_tenant_by_domain() (public, routing-only) and app.list_tenant_domains()
-- (authority-gated), both SECURITY DEFINER/service_role-invoked, neither a raw policy.
grant select, insert, update, delete on app.tenant_custom_domains to service_role;
grant execute on function app.normalize_domain_hostname(text) to service_role;
grant execute on function app.validate_domain_hostname(text) to service_role;
grant execute on function app.is_reserved_domain_hostname(text) to service_role;
grant execute on function app.generate_domain_verification_token() to service_role;
grant execute on function app.request_tenant_domain(uuid, uuid, text, text) to service_role;
grant execute on function app.verify_tenant_domain(uuid, uuid, text, text) to service_role;
grant execute on function app.activate_tenant_domain(uuid, uuid, text) to service_role;
grant execute on function app.disable_tenant_domain(uuid, uuid, text, text) to service_role;
grant execute on function app.reject_tenant_domain(uuid, uuid, text, text) to service_role;
grant execute on function app.expire_stale_domain_verifications() to service_role;
grant execute on function app.list_tenant_domains(uuid, uuid) to service_role;
-- The one deliberately broader grant, matching app.evaluate_tenant_brand()'s precedent:
-- inbound HTTP requests must resolve host->tenant before any session/auth exists.
grant execute on function app.resolve_tenant_by_domain(text) to anon, authenticated, service_role;
