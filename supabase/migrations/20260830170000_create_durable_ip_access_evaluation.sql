-- Closes the security-denial slice of ISS-2026-249, and the live-reproduced defect
-- registered as ISS-2026-307.
--
-- WHAT WAS WRONG, reproduced live before writing a line of this file:
--
--   app.ip_access_evaluations is the IP-restriction control's own audit trail. It has a
--   dedicated read RPC (app.list_ip_access_evaluations_for_tenant) and a TypeScript query
--   wrapper, so it is a table someone is expected to review after an incident: "who was
--   blocked, from where, when".
--
--   It can never contain a `denied` row.
--
--   app.assert_ip_allowed is its ONLY writer (grep-confirmed across every migration). On a
--   genuine denial it INSERTs the row and then immediately `raise exception ip_not_allowed`
--   to deny the caller. That exception aborts the transaction -- so the INSERT it just made
--   goes with it. Every caller reaches it the same way (`perform app.assert_ip_allowed(...)`
--   at the top of an import-commit RPC, or as a standalone RPC from
--   server/mutations/ip-restriction.ts), and every one of those paths loses the row.
--
--   Live reproduction, on a disposable database with a real tenant, an enforced policy and
--   one 10.0.0.0/8 allowlist entry:
--       denied  203.0.113.9 -> exception raised, ip_access_evaluations count 0 -> 0
--       allowed 10.1.2.3    -> ip_access_evaluations count 0 -> 1   (control: the table works)
--
--   So the table records exactly the cases where the control did nothing, and never the
--   cases where it acted. The harder the control works, the emptier its evidence gets.
--   `dry_run_would_deny` rows persist for the same reason -- dry run does not raise.
--
-- WHY THE PREVIOUS ATTEMPT WAS WITHDRAWN, and why this one is different.
--
--   20260827000000_wire_observability_alert_producers.sql drafted an alert call inside this
--   same denial branch as its Part D, then withdrew it before applying, having caught the
--   rollback with the local db-tests suite. Its note recorded the alert being lost. The
--   finding is actually wider than that note: the evaluation row, which predates the alert
--   idea entirely, was already being lost the same way.
--
--   That note named the correct fix -- "moving the alert call to the CALLING code instead of
--   inside the enforcement function itself" -- and correctly called it a design change rather
--   than a same-signature body edit. This migration is that design change, done as the
--   smallest version of itself:
--
--     app.evaluate_ip_access  -- decides, records, alerts. NEVER raises.
--     app.assert_ip_allowed   -- composes it and raises. Signature and behaviour unchanged.
--
--   A caller that wants a durable denial record calls app.evaluate_ip_access as its own
--   statement -- its own transaction, which commits -- and acts on the returned decision.
--   A caller that wants fail-closed enforcement inside a business transaction keeps calling
--   app.assert_ip_allowed exactly as before and gets byte-identical behaviour.
--
-- WHAT THIS DOES NOT FIX, stated plainly rather than left to be discovered:
--
--   A denial raised from INSIDE a business transaction (app.commit_import_job and its
--   siblings) still loses its own evaluation row, because that transaction still aborts.
--   Postgres offers no in-transaction escape from that; recording it would need an autonomous
--   transaction (dblink/pg_background -- a real new dependency and a new security surface) or
--   the business RPCs returning a denial instead of raising one, which is a breaking contract
--   change for every caller. Neither belongs in this migration. The durable path now EXISTS,
--   which it did not before; wiring the remaining call sites onto it is ISS-2026-307's own
--   residual, tracked there rather than implied here.
--
-- Additive only. No table, column, constraint, grant or policy is dropped or narrowed.

-- ===========================================================================
-- 1. app.evaluate_ip_access -- the decision, the record, and the alert
-- ===========================================================================
-- Body reproduced from app.assert_ip_allowed's own current, live-effective definition
-- (20260807200000_create_intelligence_ip_restriction_network_access.sql, never redefined
-- since -- grep-confirmed), with exactly two changes:
--   (a) each `raise exception` becomes a returned decision, and
--   (b) a genuine denial also raises an observability alert.
-- Every decision string, every branch order and every insert is otherwise identical, so the
-- two functions cannot disagree about what counts as allowed.
create function app.evaluate_ip_access(
  p_tenant_id uuid,
  p_raw_ip_address text,
  p_scope text,
  p_subject_label text
)
returns text
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_policy app.ip_allowlist_policies;
  v_ip inet;
  v_matched app.ip_allowlist_entries;
  v_decision text;
begin
  select * into v_policy from app.ip_allowlist_policies where tenant_id = p_tenant_id;
  if not found or v_policy.enforcement_mode = 'disabled' then
    -- A true no-op, and deliberately zero log rows: a tenant who never turns this on must not
    -- accumulate an unbounded evaluation log. Same rule as the original.
    return 'not_enforced';
  end if;

  begin
    v_ip := trim(coalesce(p_raw_ip_address, ''))::inet;
  exception
    when others then
      v_ip := null;
  end;

  if v_ip is null then
    v_decision := case when v_policy.enforcement_mode = 'enforced' then 'denied' else 'dry_run_would_deny' end;
    insert into app.ip_access_evaluations (tenant_id, subject_label, ip_address, scope, decision)
    values (p_tenant_id, p_subject_label, coalesce(p_raw_ip_address, ''), p_scope, v_decision);
    if v_decision = 'denied' then
      perform app.raise_observability_alert(
        p_tenant_id, 'security', 'error',
        format('IP allowlist denied a malformed address for scope %s', p_scope),
        'high',
        format('subject=%s raw_ip=%s scope=%s', p_subject_label, coalesce(p_raw_ip_address, ''), p_scope)
      );
    end if;
    return v_decision;
  end if;

  select * into v_matched
  from app.ip_allowlist_entries
  where tenant_id = p_tenant_id and status = 'active'
    and (scope = p_scope or scope = 'all')
    and v_ip <<= cidr
  limit 1;

  if found then
    insert into app.ip_access_evaluations (tenant_id, subject_label, ip_address, scope, decision, matched_entry_id)
    values (p_tenant_id, p_subject_label, host(v_ip), p_scope, 'allowed', v_matched.id);
    return 'allowed';
  end if;

  v_decision := case when v_policy.enforcement_mode = 'enforced' then 'denied' else 'dry_run_would_deny' end;
  insert into app.ip_access_evaluations (tenant_id, subject_label, ip_address, scope, decision)
  values (p_tenant_id, p_subject_label, host(v_ip), p_scope, v_decision);

  if v_decision = 'denied' then
    -- The alert survives because this function does not raise. That is the whole difference
    -- between this and the withdrawn Part D of 20260827000000.
    -- app.raise_observability_alert carries its own advisory-lock deduplication, so a host
    -- being brute-forced from one address produces one incident, not one per attempt.
    perform app.raise_observability_alert(
      p_tenant_id, 'security', 'error',
      format('IP allowlist denied %s for scope %s', host(v_ip), p_scope),
      'high',
      format('subject=%s ip=%s scope=%s', p_subject_label, host(v_ip), p_scope)
    );
  end if;

  return v_decision;
end;
$$;

comment on function app.evaluate_ip_access is
  'IAE-028, added by ISS-2026-307: the IP allowlist decision WITHOUT the denial exception. Returns not_enforced/allowed/denied/dry_run_would_deny, records the evaluation in app.ip_access_evaluations, and raises a deduplicated app.raise_observability_alert (source_type=security, signal_type=error, high) on a genuine denial. Exists because app.assert_ip_allowed raises on denial, which aborts the transaction and takes its own just-written audit row with it -- live-reproduced: a denied address left ip_access_evaluations at 0 rows while an allowed one left 1. Call this as its own statement when the denial must be durably recorded; call app.assert_ip_allowed when a business transaction must fail closed. Same decision logic in both -- assert_ip_allowed composes this one.';

-- ===========================================================================
-- 2. app.assert_ip_allowed -- unchanged signature, unchanged behaviour
-- ===========================================================================
-- Now a thin composition. Every existing caller is unaffected: the same inputs produce the
-- same evaluation row, the same errcode, and an error message carrying the same information.
create or replace function app.assert_ip_allowed(
  p_tenant_id uuid,
  p_raw_ip_address text,
  p_scope text,
  p_subject_label text
)
returns void
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision text;
begin
  v_decision := app.evaluate_ip_access(p_tenant_id, p_raw_ip_address, p_scope, p_subject_label);
  if v_decision = 'denied' then
    raise exception 'ip_not_allowed: % denied for scope % (tenant %)',
      coalesce(nullif(trim(coalesce(p_raw_ip_address, '')), ''), '<empty>'), p_scope, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
end;
$$;

comment on function app.assert_ip_allowed is
  'IAE-028: the real enforcement gate. disabled -> true no-op, zero log rows (avoids unbounded growth for tenants who never turn this on). dry_run -> always allows, but logs what it WOULD have denied. enforced -> genuinely denies and logs. A malformed IP address is treated exactly like a non-matching one (denied under enforced, logged under dry_run), never silently allowed and never a raw, unclassified crash. ISS-2026-307: the decision logic now lives in app.evaluate_ip_access and this function composes it -- identical behaviour, but callers that need the denial DURABLY recorded can call the evaluator directly, since the exception this function raises rolls back the evaluation row it just wrote.';

-- ===========================================================================
-- 3. Grants -- mirror app.assert_ip_allowed exactly, no wider
-- ===========================================================================
-- assert_ip_allowed is service_role-only and deliberately takes no actor parameter (it must
-- stay reachable from an API-key-authenticated caller with no auth_user_id at all). The
-- evaluator inherits that reasoning verbatim: it decides on a raw IP/scope pair, carries no
-- authority check of its own, and must never be reachable by an end-user session.
revoke execute on function app.evaluate_ip_access(uuid, text, text, text) from public;
grant execute on function app.evaluate_ip_access(uuid, text, text, text) to service_role;

-- ===========================================================================
-- 4. public.* wrapper (RGL-394 Option 2)
-- ===========================================================================
-- `app` is not exposed to PostgREST, so every externally-callable app.* function needs a thin
-- public.* pass-through with a MATCHING security mode. scripts/db-tests/
-- public-api-wrapper-regression.sql enforces both halves exhaustively, and it caught this one
-- missing on the first run of this migration -- which is the gate doing its job, not an
-- afterthought. Mirrors public.assert_ip_allowed exactly: security definer (matching the app
-- function), service_role-only, a pass-through and never a reimplementation.
create function public.evaluate_ip_access(p_tenant_id uuid, p_raw_ip_address text, p_scope text, p_subject_label text)
returns text
language sql
volatile
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select app.evaluate_ip_access(p_tenant_id, p_raw_ip_address, p_scope, p_subject_label);
$wrap$;

comment on function public.evaluate_ip_access(p_tenant_id uuid, p_raw_ip_address text, p_scope text, p_subject_label text) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.evaluate_ip_access with an identical grant set, never a reimplementation. See docs/build-log/release-go-live/RGL-394.md.';

revoke execute on function public.evaluate_ip_access(p_tenant_id uuid, p_raw_ip_address text, p_scope text, p_subject_label text) from public;
grant execute on function public.evaluate_ip_access(p_tenant_id uuid, p_raw_ip_address text, p_scope text, p_subject_label text) to service_role;
