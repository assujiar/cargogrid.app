-- Track B Batch 5, ISS-2026-149 (docs/runtime/KNOWN_ISSUES.md): DRAFT, not yet
-- applied to any live/hosted project. Research-and-drafting pass only -- see
-- Batch 5 writeup for the full independent re-verification this migration is
-- based on.
--
-- `app.resolve_enterprise_idp_by_email_domain` (IAE-026,
-- 20260807000000_create_intelligence_enterprise_iam_sso.sql:592-609) is the only
-- one of the 10 `anon`-grant-holding `app.*` functions in this schema with no
-- `client_key` parameter, no attempt-counting table, and no throttle of any kind
-- -- confirmed unchanged by direct read of its current (and only) body, no later
-- migration ever touches it. Its 9 anon-reachable siblings each carry a real
-- anti-enumeration control: an HMAC-signed-payload + attempt-lockout for the 3
-- `ingest_*_webhook_event` functions, a `client_key`-scoped rate limiter for
-- `app.lookup_public_shipment_tracking` (`app.tracking_lookup_attempts`,
-- 20260728130000_create_operations_public_tracking.sql:88-268), or a narrow,
-- non-enumerable resolver shape (`resolve_tenant_by_domain`,
-- `resolve_tenant_locale`, `resolve_locale_context`, `evaluate_tenant_brand`).
--
-- Escalating fact NOT reflected in the entry's own text (independently found
-- this pass, not previously disclosed anywhere in KNOWN_ISSUES.md): the entry's
-- own stated mitigation -- "the app schema is not yet in PostgREST's exposed-
-- schema list ... so no live Supabase Data API endpoint reaches it yet either"
-- -- is no longer accurate. `RGL-BLK-002`'s Option-2 remediation
-- (docs/build-log/release-go-live/RGL-BLK-002-OPTION2-REMEDIATION.md) and
-- `RGL-394` (20260826000000_create_public_api_data_wrappers.sql:34352-34369)
-- mechanically wrapped every anon/authenticated/service_role-granted `app.*`
-- function -- this one included -- in a matching `public.*` thin pass-through,
-- specifically so PostgREST (whose own `supabase/config.toml` exposes `public`,
-- not `app`) can reach it; the live hosted project had the fix applied
-- (RGL-394.md §5). `public.resolve_enterprise_idp_by_email_domain(text)` is
-- `anon`-granted (20260826000000:34366-34369) and neither RGL-BLK-002 nor
-- RGL-394's own text ever revisited this function's own already-disclosed
-- ISS-2026-149 gap when wrapping it. In other words: the one condition the
-- entry's own "Low severity, not fixed here" ruling leaned on (dead code, not
-- reachable via the Data API) no longer holds -- this function is now a real,
-- live, unauthenticated, anon-reachable, unthrottled HTTP endpoint via the
-- standard Supabase REST RPC path, whether or not any first-party TS caller
-- exists yet.
--
-- Fix, mirroring `app.lookup_public_shipment_tracking`'s own established
-- shape exactly (same threshold/window, same attempt-log table shape, same
-- "log the outcome, never raise on rate-limit -- a raise would unwind this
-- very call's own attempt-log insert" rationale):
--   1. New `app.enterprise_idp_domain_lookup_attempts` table (mirrors
--      `app.tracking_lookup_attempts` byte-for-byte in shape).
--   2. `app.resolve_enterprise_idp_by_email_domain` gains a required
--      `p_client_key text` second parameter (raises `iam_domain_lookup_client_
--      key_required` if null/empty, matching `lookup_public_shipment_tracking`'s
--      own `tracking_client_key_required` convention) and now requires
--      `language plpgsql` (was `language sql`) to log the attempt. A `client_key`
--      accumulating 10+ non-matching lookups within a trailing 15-minute window
--      is rate-limited -- returned as zero rows (identical to a genuine
--      non-match), never a distinguishable error or status column, so a caller
--      cannot use the rate-limit response itself as a second oracle.
--   3. `public.resolve_enterprise_idp_by_email_domain` (the RGL-394 Option-2
--      wrapper) updated to the matching 2-parameter signature, same technique
--      (DROP FUNCTION old signature + CREATE FUNCTION new signature, never a
--      bare CREATE OR REPLACE with an added parameter -- taxonomy class C-29,
--      docs/standards/RECURRING_DEFECT_TAXONOMY.md, the exact defect class
--      `ISS-2026-150`'s own first draft hit and self-caught) + re-GRANT the
--      identical anon/authenticated/service_role set already on record
--      (20260826000000:34366-34369).
--   4. Zero real callers exist anywhere in this repository outside this
--      function's own migration/db-test/thin-TS-wrapper (independently
--      reconfirmed this pass, `grep -rn resolveEnterpriseIdpByEmailDomain`) --
--      the DROP+CREATE signature change is genuinely safe: no production route
--      or Server Action calls either the `app.*` or `public.*` name today.
--
-- Not addressed here, deliberately, matching the entry's own recommended
-- fix shape: a real per-caller-IP rate limit at the route-handler layer for
-- whenever this resolver is actually wired to a live HTTP login route --
-- that remains a genuine future task, this migration only closes the "zero
-- throttle of any kind, unlike every sibling anon function" gap at the RPC
-- layer itself, today, before that route exists.
--
-- Regression coverage: scripts/db-tests/enterprise-iam-sso-scim.sql's 3
-- existing call sites updated to pass a client_key (draft diff described in
-- the Batch 5 writeup; not applied to that file by this migration itself --
-- see that file for the actual db-test changes). New assertions added there
-- proving (a) 10 consecutive not_found lookups for the SAME client_key
-- rate-limit the 11th (returns zero rows, would otherwise have matched a
-- real, active domain claim) and (b) a DIFFERENT client_key against the same
-- domain is unaffected (proves the throttle is truly client_key-scoped, not
-- global).

\set ON_ERROR_STOP on

create table app.enterprise_idp_domain_lookup_attempts (
  id uuid primary key default gen_random_uuid(),
  client_key text not null,
  result text not null,
  occurred_at timestamptz not null default now(),
  constraint enterprise_idp_domain_lookup_attempts_result_check check (result in ('found', 'not_found', 'rate_limited'))
);

comment on table app.enterprise_idp_domain_lookup_attempts is
  'ISS-2026-149: append-only evidence of every app.resolve_enterprise_idp_by_email_domain() call, keyed by a caller-supplied client_key (a hash of the caller''s own IP/session, computed by the calling Server Action -- mirrors app.tracking_lookup_attempts, OPS-180). A client_key accumulating 10+ not_found results within a trailing 15-minute window is rate-limited -- the real, queryable anti-enumeration mechanism this resolver now implements, closing the one gap that made it the only anon-reachable function in this schema with zero throttle of any kind.';

create index enterprise_idp_domain_lookup_attempts_client_key_idx on app.enterprise_idp_domain_lookup_attempts (client_key, occurred_at desc);

-- Old signature (1-arg, `language sql`) must be explicitly dropped, never
-- silently shadowed by a bare CREATE OR REPLACE with an added parameter --
-- taxonomy class C-29 (ISS-2026-150's own self-caught defect: an added
-- parameter, even a trailing one, is not a signature match for CREATE OR
-- REPLACE, and would leave every existing 1-arg caller permanently bound to
-- the old, unthrottled overload).
drop function if exists app.resolve_enterprise_idp_by_email_domain(text);

create function app.resolve_enterprise_idp_by_email_domain(p_email_domain text, p_client_key text)
returns table (connection_id uuid, protocol text, display_name text)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_recent_not_found_count integer;
  v_row record;
begin
  if p_client_key is null or length(trim(p_client_key)) = 0 then
    raise exception 'iam_domain_lookup_client_key_required: a client_key is required' using errcode = 'check_violation';
  end if;

  select count(*) into v_recent_not_found_count
  from app.enterprise_idp_domain_lookup_attempts
  where client_key = p_client_key and result = 'not_found' and occurred_at > now() - interval '15 minutes';
  if v_recent_not_found_count >= 10 then
    insert into app.enterprise_idp_domain_lookup_attempts (client_key, result) values (p_client_key, 'rate_limited');
    return;
  end if;

  select c.id, c.adapter_code, c.name into v_row
  from app.iam_domain_claims d
  join app.integration_connections c on c.id = d.connection_id
  where d.status = 'active'
    and d.email_domain = app.normalize_domain_hostname(coalesce(p_email_domain, ''))
    and c.status = 'active'
  limit 1;

  if v_row.id is null then
    insert into app.enterprise_idp_domain_lookup_attempts (client_key, result) values (p_client_key, 'not_found');
    return;
  end if;

  insert into app.enterprise_idp_domain_lookup_attempts (client_key, result) values (p_client_key, 'found');
  connection_id := v_row.id;
  protocol := v_row.adapter_code;
  display_name := v_row.name;
  return next;
end;
$$;

comment on function app.resolve_enterprise_idp_by_email_domain is
  'IAE-026, hardened ISS-2026-149 (Track B Batch 5): safe public resolver -- returns only connection_id/protocol/display_name for an ACTIVE domain claim + ACTIVE connection, never a config/credential/authorization decision (unchanged from the original IAE-026 shape). Now requires a caller-supplied p_client_key (mirrors app.lookup_public_shipment_tracking, OPS-180) -- a client_key accumulating 10+ not_found lookups within a trailing 15-minute window is rate-limited, returned as zero rows, indistinguishable from a genuine non-match. Closes the one gap that made this the only anon-reachable function in this schema with no client_key parameter, no attempt-counting table, and no throttle of any kind.';

grant execute on function app.resolve_enterprise_idp_by_email_domain(text, text) to anon, authenticated, service_role;

-- Matching public.* Option-2 wrapper (RGL-BLK-002/RGL-394,
-- 20260826000000_create_public_api_data_wrappers.sql:34352-34369) -- same
-- DROP+CREATE discipline, same re-GRANT set restored exactly.
drop function if exists public.resolve_enterprise_idp_by_email_domain(text);

create function public.resolve_enterprise_idp_by_email_domain(p_email_domain text, p_client_key text)
returns table (connection_id uuid, protocol text, display_name text)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.resolve_enterprise_idp_by_email_domain(p_email_domain, p_client_key);
$wrap$;

comment on function public.resolve_enterprise_idp_by_email_domain(p_email_domain text, p_client_key text) is
  'RGL-394 Option-2 wrapper, re-created for ISS-2026-149''s p_client_key signature change: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.resolve_enterprise_idp_by_email_domain with an identical grant set, never a reimplementation. See docs/build-log/release-go-live/RGL-394.md.';

revoke execute on function public.resolve_enterprise_idp_by_email_domain(text, text) from public;
grant execute on function public.resolve_enterprise_idp_by_email_domain(text, text) to service_role;
grant execute on function public.resolve_enterprise_idp_by_email_domain(text, text) to authenticated;
grant execute on function public.resolve_enterprise_idp_by_email_domain(text, text) to anon;
