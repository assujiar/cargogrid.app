-- ISS-2026-311 (docs/runtime/KNOWN_ISSUES.md): the product's default domain moves from
-- `cargogrid.app` to `app.cargogrid.net`, by owner instruction 2026-09-03.
--
-- ===========================================================================
-- What actually has to change in the database, and what deliberately does not
-- ===========================================================================
--
-- The tenant custom-domain capability itself is UNCHANGED and stays fully working -- the owner's
-- instruction is explicit that it must: `app.cargogrid.net` is only the standard domain for
-- tenants (and the Supreme Admin console) that have NOT requested a custom domain of their own.
-- `app.request_tenant_domain`, the verification flow, the DNS-token issuance and every policy
-- around them are untouched by this migration.
--
-- The one thing that must move is `app.is_reserved_domain_hostname`. It exists so a tenant cannot
-- claim the PLATFORM'S OWN hostname as its custom domain -- a tenant that successfully claimed
-- `app.cargogrid.net` would be claiming the console every other tenant signs in through. Today
-- that guard names only the old domain, so the moment the product answers on
-- `app.cargogrid.net`, the new hostname is claimable. That is the security half of this rename,
-- and it is why a documentation-only change would not have been enough.
--
-- ===========================================================================
-- Why the OLD domain stays reserved too
-- ===========================================================================
--
-- `cargogrid.app` and `*.cargogrid.app` remain reserved, deliberately. Removing a reservation is
-- a security-weakening change, and the old domain may still resolve, still be owned, or still be
-- pointed somewhere during the cutover. Letting a tenant claim it mid-migration would be a real
-- takeover of a hostname users may still be visiting. Keeping both costs nothing: the function is
-- a pure IMMUTABLE predicate over a hostname string, and no legitimate tenant has any reason to
-- claim either domain.
--
-- ===========================================================================
-- Live definition re-verified before writing this file
-- ===========================================================================
--
--   * app.is_reserved_domain_hostname was read from the hosted project via pg_get_functiondef,
--     not from 20260717103015's file text, and is reproduced below verbatim apart from the two
--     added disjuncts: `language sql`, `immutable`, the localhost arm and the IPv4-literal regex
--     are all unchanged. (It carries no `set search_path`, being a `language sql` IMMUTABLE
--     predicate that touches no table -- restated here rather than silently "fixed", since
--     changing a function's attributes while replacing it is exactly the failure ISS-2026-318
--     already found once in this codebase.)

create or replace function app.is_reserved_domain_hostname(p_hostname text)
returns boolean
language sql
immutable
as $$
  -- ISS-2026-311: the current platform domain. `%.cargogrid.net` covers `app.cargogrid.net`
  -- (the standard tenant/Supreme-Admin console), `status.cargogrid.net`, and every future
  -- platform subdomain without needing another migration each time one is added.
  select p_hostname = 'cargogrid.net'
    or p_hostname like '%.cargogrid.net'
    -- The previous platform domain, kept reserved through and after the cutover for the reason
    -- in this file's header: un-reserving a hostname somebody may still be visiting would let a
    -- tenant claim it.
    or p_hostname = 'cargogrid.app'
    or p_hostname like '%.cargogrid.app'
    or p_hostname = 'localhost'
    or p_hostname ~ '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$';
$$;

comment on function app.is_reserved_domain_hostname(text) is
  'ISS-2026-311: refuses a tenant custom-domain claim over a hostname the platform owns -- the current domain (cargogrid.net and every subdomain, which is what protects app.cargogrid.net, the standard console for tenants that have not requested a custom domain of their own), the previous domain (cargogrid.app and every subdomain, kept reserved because un-reserving a hostname users may still be visiting would let a tenant claim it), localhost, and any bare IPv4 literal. The tenant custom-domain capability itself is unaffected: this predicate only rules out the platform''s own hostnames, never a domain a tenant genuinely owns.';
