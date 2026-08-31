-- ISS-2026-307 (docs/runtime/KNOWN_ISSUES.md) -- app.ip_access_evaluations can never contain a
-- `denied` row: the IP allowlist's own audit trail records every access it let through and
-- none it blocked.
--
-- THE RESIDUAL THIS CLOSES, restated exactly. 20260830170000 built app.evaluate_ip_access,
-- which records the evaluation and returns the decision rather than raising it, so a caller
-- that does not abort keeps its row. That fixed the standalone path. It did not fix -- and did
-- not claim to fix -- a denial raised from INSIDE a business transaction: app.assert_ip_allowed
-- raises, the transaction aborts, and the INSERT goes with it. ISS-2026-302 then widened the
-- control from 5 functions to 70, which made the hole wider rather than narrower.
--
-- WHY THE OBVIOUS FIXES WERE REJECTED, each for a concrete reason rather than a vague one:
--
--   An autonomous transaction (dblink / pg_background) genuinely works, and is a new extension,
--   a new connection path out of the database, and a new security surface -- on the one code
--   path whose entire job is refusing untrusted callers. That trade is not worth it to record
--   evidence for the rare denial.
--
--   Having the 70 gated functions RETURN a denial instead of raising is a breaking contract
--   change for every caller, and would turn a refusal into something a caller can ignore by
--   forgetting to check a return value. The current shape -- an exception -- is the safer one
--   and should not be traded away for logging.
--
--   An application-layer pre-check (call public.evaluate_ip_access before each business RPC)
--   costs an extra database round trip on every finance approval and every HR decision, in
--   order to record evidence for the rare denial. It also cannot see the tenant id at many
--   call sites: app.approve_finance_invoice takes an invoice id, not a tenant.
--
-- WHAT ACTUALLY SURVIVES A ROLLBACK IN POSTGRES. Two things, and this migration uses both:
--
--   1. A SEQUENCE. nextval() is deliberately non-transactional -- an advance is never rolled
--      back, which is exactly the property that makes sequences unusable for gap-free numbering
--      and perfect for counting events that must outlive an aborted transaction.
--
--   2. THE SERVER LOG. RAISE LOG writes through the logging collector immediately, outside
--      transaction control. Verified against the live project rather than assumed: its
--      log_min_messages is `warning`, and LOG outranks WARNING in the logging severity order,
--      so these lines are captured. Supabase retains and exposes them.
--
-- So the evidence for an in-transaction denial moves from a table to the database log, and the
-- sequence makes the move VERIFIABLE: app.get_ip_denial_evidence_gap() reports how many
-- denials have ever occurred against how many left a row, and the difference is exactly the
-- set an operator must go and find in the log. Each log line carries its own serial, so
-- "which addresses did we block, and when" is answerable again, and answerable completely --
-- a responder can tell when they have found them all rather than hoping.
--
-- WHAT THIS DOES NOT CLAIM. The row still does not survive; app.ip_access_evaluations remains
-- structurally unable to hold an in-transaction denial, and querying that table alone still
-- gives an incomplete picture. What changes is that the incompleteness is now measured and the
-- missing detail is recoverable, instead of both being silent. The db-test asserts the missing
-- row as a property and says in its own failure message that if it ever starts persisting the
-- assertion must be INVERTED, not deleted.

-- ---------------------------------------------------------------------------------------
-- 1. The durable counter.
-- ---------------------------------------------------------------------------------------

create sequence app.ip_denial_serial;

comment on sequence app.ip_denial_serial is
  'ISS-2026-307: counts every IP-allowlist denial, including those whose app.ip_access_evaluations row is lost to the aborting business transaction that raised them. A sequence is used precisely because nextval() is non-transactional -- the advance survives a rollback. Compare against the recorded rows via app.get_ip_denial_evidence_gap(); the difference is the number of denials whose detail lives only in the Postgres log.';

revoke all on sequence app.ip_denial_serial from public;
grant usage on sequence app.ip_denial_serial to service_role;

-- ---------------------------------------------------------------------------------------
-- 2. app.evaluate_ip_access -- unchanged in signature, decision logic and return values.
--    The live definition, with a durable emission added to each of its two `denied` paths.
--    Read back from pg_get_functiondef rather than reconstructed from 20260830170000.
-- ---------------------------------------------------------------------------------------

create or replace function app.evaluate_ip_access(p_tenant_id uuid, p_raw_ip_address text, p_scope text, p_subject_label text)
returns text
language plpgsql
security definer
set search_path to 'app', 'pg_temp'
as $function$
declare
  v_policy app.ip_allowlist_policies;
  v_ip inet;
  v_matched app.ip_allowlist_entries;
  v_decision text;
  v_serial bigint;
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
      -- ISS-2026-307: durable first, in-transaction second. If the caller aborts, the INSERT
      -- above and the alert below both vanish; these two do not.
      v_serial := nextval('app.ip_denial_serial');
      raise log 'ip_denial serial=% tenant=% subject=% ip=% scope=% reason=malformed_address',
        v_serial, p_tenant_id, p_subject_label, coalesce(p_raw_ip_address, ''), p_scope;
      perform app.raise_observability_alert(
        p_tenant_id, 'security', 'error',
        format('IP allowlist denied a malformed address for scope %s', p_scope),
        'high',
        format('subject=%s raw_ip=%s scope=%s denial_serial=%s', p_subject_label, coalesce(p_raw_ip_address, ''), p_scope, v_serial)
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
    -- ISS-2026-307: the sequence advance and the log line are the two things that survive a
    -- caller's rollback. Taken BEFORE the alert so that a denial raised inside a business
    -- transaction still leaves a counted, greppable trace even though the row above and the
    -- incident below are about to be discarded with it.
    v_serial := nextval('app.ip_denial_serial');
    raise log 'ip_denial serial=% tenant=% subject=% ip=% scope=% reason=no_matching_entry',
      v_serial, p_tenant_id, p_subject_label, host(v_ip), p_scope;

    -- The alert survives for a caller that does not raise. That is the whole difference
    -- between this and the withdrawn Part D of 20260827000000.
    -- app.raise_observability_alert carries its own advisory-lock deduplication, so a host
    -- being brute-forced from one address produces one incident, not one per attempt.
    perform app.raise_observability_alert(
      p_tenant_id, 'security', 'error',
      format('IP allowlist denied %s for scope %s', host(v_ip), p_scope),
      'high',
      format('subject=%s ip=%s scope=%s denial_serial=%s', p_subject_label, host(v_ip), p_scope, v_serial)
    );
  end if;

  return v_decision;
end;
$function$;

comment on function app.evaluate_ip_access(uuid, text, text, text) is
  'ISS-2026-307: the IP-allowlist decision, returned rather than raised, so a caller that does not abort keeps its app.ip_access_evaluations row and its security incident. On a genuine denial it additionally takes a nextval from app.ip_denial_serial and writes one structured RAISE LOG line -- the two things Postgres does NOT roll back -- so that a denial raised from inside a business transaction, whose row and incident are both discarded when that transaction aborts, still leaves a counted and greppable trace. app.get_ip_denial_evidence_gap() measures the difference.';

-- ---------------------------------------------------------------------------------------
-- 3. The measurement. Operator/forensics tooling: service_role only, no `authenticated`
--    grant at all, matching app.list_untracked_table_mutations (ISS-2026-259) and
--    app.detect_reverted_security_state (ISS-2026-254).
-- ---------------------------------------------------------------------------------------

create function app.get_ip_denial_evidence_gap()
returns table (
  total_denials bigint,
  recorded_denials bigint,
  unrecorded_denials bigint
)
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select
    -- pg_sequence_last_value returns NULL until the first nextval, which is the honest answer
    -- for "no denial has ever happened" -- coalesced to 0 rather than reported as unknown.
    coalesce(pg_sequence_last_value('app.ip_denial_serial'::regclass), 0) as total_denials,
    (select count(*) from app.ip_access_evaluations where decision = 'denied') as recorded_denials,
    greatest(
      coalesce(pg_sequence_last_value('app.ip_denial_serial'::regclass), 0)
        - (select count(*) from app.ip_access_evaluations where decision = 'denied'),
      0
    ) as unrecorded_denials;
$$;

comment on function app.get_ip_denial_evidence_gap is
  'ISS-2026-307: how many IP-allowlist denials have ever occurred (the non-transactional app.ip_denial_serial sequence) against how many left a durable row (app.ip_access_evaluations). The difference is the set whose detail exists only as `ip_denial serial=...` lines in the Postgres log, because the business transaction that raised them aborted and took the row with it. greatest(..., 0) because an operator may legitimately prune old evaluation rows, which would otherwise report a negative gap.';

revoke execute on function app.get_ip_denial_evidence_gap() from anon, authenticated, service_role, public;
grant execute on function app.get_ip_denial_evidence_gap() to service_role;

create function public.get_ip_denial_evidence_gap()
returns table (
  total_denials bigint,
  recorded_denials bigint,
  unrecorded_denials bigint
)
language sql
stable
security definer
set search_path = app, public, pg_temp
as $wrap$
  select * from app.get_ip_denial_evidence_gap();
$wrap$;

comment on function public.get_ip_denial_evidence_gap is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.get_ip_denial_evidence_gap with an identical grant set, never a reimplementation.';

revoke execute on function public.get_ip_denial_evidence_gap() from anon, authenticated, service_role, public;
grant execute on function public.get_ip_denial_evidence_gap() to service_role;
