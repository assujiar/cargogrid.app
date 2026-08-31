-- Closes `ISS-2026-207`: `app.api_versions` is a real, audited, Supreme-only state machine that
-- had **zero effect on a real request**. Live-forced at `CG-S15-HDN-008`: mark `v1` `deprecated`,
-- then `sunset` with a real future `sunset_at`, then call the gateway with an otherwise valid
-- key — still `outcome = ok`. The gateway takes no version argument and never queries the
-- registry, and `x-cargogrid-api-version` is a hardcoded literal.
--
-- WHY THE GATEWAY RPC IS NOT THE PLACE TO PUT THIS
--
--   The obvious fix is a version argument on `app.authenticate_and_authorize_api_request`. It was
--   rejected for two reasons that both point the same way.
--
--   First, version state is not an authentication or authorization fact. Deprecation is a
--   *contract* signal: RFC 8594 says a deprecated endpoint still answers normally and carries
--   `Deprecation`/`Sunset` headers, so folding it into the auth outcome would force a choice
--   between "deny a request that should succeed" and "return ok and lose the signal". The
--   registry needs to say three things (serve it, serve it with a warning, refuse it), and an
--   auth outcome has room for two.
--
--   Second, the header is emitted by the route layer, which is where the decision has to be
--   readable anyway. Putting the decision in a small dedicated function keeps one caller instead
--   of threading a new argument through every existing gateway call site.
--
-- THE THREE STATES, AND THE ONE THAT IS A JUDGEMENT CALL
--
--   `active`                     -> ok
--   `deprecated`                 -> deprecated: still served, with headers
--   `sunset`, sunset_at future   -> deprecated, NOT gone
--   `sunset`, sunset_at past     -> gone
--   `sunset`, sunset_at null     -> gone
--   unknown code                 -> gone
--
--   The judgement call is the third row. A version marked `sunset` with a date in the future is
--   an announcement, not a removal — `app.set_api_version_status` requires a real `sunset_at`
--   precisely so a client can be told when it will stop working. Refusing it the moment the
--   status flips would turn the announcement into the outage it exists to warn about. So it is
--   served, with a `Sunset` header carrying the date, until the date arrives.
--
--   An unknown code is `gone` rather than `ok`, because a caller asking for a version this
--   platform has never heard of should be told no, not silently served v1's behaviour under
--   another name.

create function app.evaluate_api_version_request(p_code text)
returns table (decision text, status text, sunset_at timestamptz)
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select
    case
      when v.code is null then 'gone'
      when v.status = 'sunset' and (v.sunset_at is null or v.sunset_at <= now()) then 'gone'
      when v.status in ('deprecated', 'sunset') then 'deprecated'
      else 'ok'
    end,
    coalesce(v.status, 'unknown'),
    v.sunset_at
  from (select 1) placeholder
  left join app.api_versions v on v.code = p_code;
$$;

comment on function app.evaluate_api_version_request is
  'ISS-2026-207: turns app.api_versions from an admin-console display into a live request-time decision. Returns ok (serve normally), deprecated (serve, and emit RFC 8594 Deprecation/Sunset headers) or gone (refuse with 410). Deliberately NOT folded into app.authenticate_and_authorize_api_request: deprecation is a contract signal, not an authorization outcome, and an auth result has room for two answers where this needs three -- folding it in would force a choice between denying a request that should succeed and returning ok while losing the signal. A version marked sunset with a FUTURE sunset_at is served, not refused: that status is an announcement, and app.set_api_version_status requires a real date precisely so clients can be warned before the date rather than by it. An unknown code is gone, never ok -- a caller asking for a version this platform has never heard of should be told no rather than silently served v1 under another name.';

-- service_role only, NOT authenticated. The first draft granted both, and
-- scripts/db-tests/rbac-enforcement.sql's ISS-2026-033 sweep failed it: a SECURITY DEFINER
-- function reachable by `authenticated` with no authority check anywhere in its call graph. The
-- gate offers two ways out -- add a check, or justify it on the reviewed list -- and there is a
-- third that is better than either: the only caller is the /api/v1 gateway, which runs as
-- service_role. An `authenticated` grant here was reach nobody needed, and the narrower grant
-- removes the question rather than answering it.
revoke execute on function app.evaluate_api_version_request(text) from anon, authenticated, public;
grant execute on function app.evaluate_api_version_request(text) to service_role;

-- public.* wrapper (RGL-394 Option 2). `from anon, ...` rather than `from public` alone: Supabase's
-- ALTER DEFAULT PRIVILEGES grants anon EXECUTE explicitly at CREATE time in schema public, and an
-- explicit grant survives a PUBLIC revoke -- the ISS-2026-309 mechanism.
create function public.evaluate_api_version_request(p_code text)
returns table (decision text, status text, sunset_at timestamptz)
language sql
stable
security definer
set search_path = app, public, pg_temp
as $wrap$
  select * from app.evaluate_api_version_request(p_code);
$wrap$;

comment on function public.evaluate_api_version_request(text) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.evaluate_api_version_request, never a reimplementation.';

revoke execute on function public.evaluate_api_version_request(text) from anon, authenticated, service_role, public;
grant execute on function public.evaluate_api_version_request(text) to service_role;

comment on table app.api_versions is
  'PLT/IAE-009 API version registry. ISS-2026-207 (20260831110000): this registry now has live request-time effect. app.evaluate_api_version_request turns a row here into a decision the /api/v1 gateway acts on -- a deprecated version is served with RFC 8594 Deprecation/Sunset headers, a version past its sunset_at is refused with 410 Gone. Before that migration the registry was audited, admin-visible, db-tested and completely inert: marking v1 sunset changed nothing about a real request.';
