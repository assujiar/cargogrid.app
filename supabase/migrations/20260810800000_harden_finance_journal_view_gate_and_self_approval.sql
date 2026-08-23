-- HDN-373 (Step 15, Prompt 373, RLS and RBAC Audit, `CG-S15-HDN-005`) -- two further
-- Finance-journal findings from this checkpoint's own investigation, both dependent on
-- `20260810700000`'s `SECURITY DEFINER` conversion (the `app.check_finance_journal_authority`
-- half specifically) landing first in this same batch.
--
-- ===========================================================================
-- Finding B -- `app.finance_journals`/`app.finance_journal_lines` RLS bypasses FIN:View
-- ===========================================================================
--
-- Both tables' own `SELECT` policy is membership-only: `app.has_active_tenant_membership
-- (tenant_id) or app.is_supreme_admin()`, with no permission predicate at all -- unlike the
-- already-correct precedent this schema already ships elsewhere for the identical shape
-- (`app.payroll_periods_select_scoped`/`app.talent_pools_select_scoped`, both `app.
-- is_supreme_admin() or app.check_<domain>_authority('View...', tenant_id, auth.uid())`).
-- **Live-forced and confirmed** (`docs/build-log/full-system-hardening/HDN-373.md` §6): a
-- genuine tenant member holding zero Finance permissions -- not even `FIN:View` -- reads
-- every one of their tenant's real journal rows and lines directly via RLS, entirely
-- bypassing `app.list_finance_journals`/`app.get_finance_journal_lines`'s own correct
-- `FIN:View` gate. The RPC layer was never the only path to this data; the raw table grant
-- (`grant select on app.finance_journals to authenticated`) always was too.
--
-- Fix: add the same permission gate the RPC layer already enforces, directly to the RLS
-- policy, mirroring `payroll_periods_select_scoped`'s own exact, already-shipped shape.
-- This requires `app.check_finance_journal_authority` to be independently `SECURITY
-- DEFINER` (an RLS `using` clause always executes as the querying role, never nested
-- inside another function's security context) -- done in `20260810700000`, which this
-- migration depends on landing first. `app.check_finance_journal_authority`'s own nested
-- call to `app.evaluate_permission` already enforces tenant membership as of this same
-- checkpoint's `20260810300000` fix, so no separate `has_active_tenant_membership`
-- conjunct is needed here, exactly matching the `payroll_periods_select_scoped` precedent.
--
-- Self-caught grant gap, found by this migration's own live regression test rather than
-- left for a later session: `app.check_finance_journal_authority` has only ever been
-- granted `to service_role` (`20260729170000_create_finance_journal.sql`), because every
-- existing caller reached it nested inside another function's own execution context. An
-- RLS `using` clause is not nested -- it always runs as the querying role -- so embedding
-- it here needs its own direct `authenticated` grant, exactly like the already-shipped
-- reference pattern (`app.check_payroll_authority`/`app.check_training_authority`, both
-- granted `to authenticated, service_role`) already carries. Live-confirmed broken
-- (`permission denied for function check_finance_journal_authority` from a genuine
-- `authenticated` session) before this grant, fixed after.

grant execute on function app.check_finance_journal_authority(text, uuid, uuid) to authenticated;

drop policy finance_journals_select_scoped on app.finance_journals;
create policy finance_journals_select_scoped on app.finance_journals
  for select to authenticated
  using (app.is_supreme_admin() or app.check_finance_journal_authority('View', tenant_id, (select auth.uid())));

drop policy finance_journal_lines_select_scoped on app.finance_journal_lines;
create policy finance_journal_lines_select_scoped on app.finance_journal_lines
  for select to authenticated
  using (app.is_supreme_admin() or app.check_finance_journal_authority('View', tenant_id, (select auth.uid())));

-- ===========================================================================
-- Maker/checker -- the manual GL journal chain has no self-approval guard
-- ===========================================================================
--
-- `app.approve_finance_journal`/`app.post_finance_journal` gate on `FIN:Approve` alone,
-- with no check that the approving/posting identity differs from whoever submitted the
-- journal for approval. `app.finance_journals` records `submitted_by`/`approved_by`/
-- `posted_by` only as free-text display labels (`text`, caller-supplied), never as an
-- `auth_user_id` -- this schema's own established convention treats a label as unusable
-- for an authorization decision (exactly what this checkpoint's broader investigation, and
-- `ISS-2026-139`'s loyalty-redemption fix earlier in this same checkpoint, both turn on:
-- the real identity, not a caller-chosen display string). **Live-forced and confirmed**
-- (`docs/build-log/full-system-hardening/HDN-373.md` §6, shares `ISS-2026-139`'s exact
-- shape): a single identity holding `FIN:Edit` and `FIN:Approve` together -- the existing
-- `scripts/db-tests/finance-journal.sql` fixture's own "Finance Manager A" is exactly such
-- an identity -- drafts, submits, approves and posts a journal alone, in one session, with
-- no second identity ever involved. Closing the reachability gap in `20260810700000`
-- without this guard would have turned a latent design gap into a live one the moment the
-- chain became callable by a real session, per this checkpoint's own investigation
-- warning.
--
-- Fix: a minimal, additive `submitted_by_auth_user_id uuid` column (nullable -- existing
-- rows predate this fix and are not retroactively enforced against; only journals
-- submitted after this migration carry a value, so the guard applies going forward, not to
-- history it has no reliable data for). `app.submit_finance_journal_for_approval` now
-- records it; `app.approve_finance_journal`/`app.post_finance_journal` both deny (a
-- distinct, named exception, not folded into the existing `insufficient_authority` one) an
-- actor attempting to approve or post their own submission. Both re-check independently,
-- mirroring this pair's own existing convention of each re-checking `FIN:Approve`
-- separately rather than trusting the prior step's authority check alone.

alter table app.finance_journals add column submitted_by_auth_user_id uuid;

comment on column app.finance_journals.submitted_by_auth_user_id is
  'HDN-373: the real identity that submitted this journal for approval, set only from this migration forward (null on rows submitted before it). Used solely for the self-approval guard in app.approve_finance_journal/app.post_finance_journal -- submitted_by remains the caller-supplied display label and is never used for an authorization decision.';

create or replace function app.submit_finance_journal_for_approval(p_journal_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_journals
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_journal app.finance_journals;
begin
  select * into v_journal from app.finance_journals where id = p_journal_id for update;
  if not found then
    raise exception 'finance_journal_not_found: %', p_journal_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_journal_authority('Edit', v_journal.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_journal.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_journal.record_version <> p_expected_version then
    raise exception 'stale_version: journal % expected version % but found %', p_journal_id, p_expected_version, v_journal.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_journal.status <> 'draft' then
    raise exception 'finance_journal_not_draft: journal % is % not draft', p_journal_id, v_journal.status
      using errcode = 'check_violation';
  end if;

  update app.finance_journals
    set status = 'submitted', submitted_by = p_actor_label, submitted_by_auth_user_id = p_actor_auth_user_id, submitted_at = now()
    where id = p_journal_id
    returning * into v_journal;

  perform app.capture_audit_event(
    v_journal.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_finance_journal_for_approval',
    'app.finance_journals', v_journal.id, 'success', null, null, to_jsonb(v_journal)
  );

  return v_journal;
end;
$function$
;

create or replace function app.approve_finance_journal(p_journal_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_journals
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_journal app.finance_journals;
begin
  select * into v_journal from app.finance_journals where id = p_journal_id for update;
  if not found then
    raise exception 'finance_journal_not_found: %', p_journal_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_journal_authority('Approve', v_journal.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_journal.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  -- HDN-373 (ISS-2026-181, maker/checker): the preparer may not also be the approver.
  if v_journal.submitted_by_auth_user_id is not null and v_journal.submitted_by_auth_user_id = p_actor_auth_user_id then
    raise exception 'self_approval_denied: identity % submitted journal % and may not also approve it', p_actor_auth_user_id, p_journal_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_journal.record_version <> p_expected_version then
    raise exception 'stale_version: journal % expected version % but found %', p_journal_id, p_expected_version, v_journal.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_journal.status <> 'submitted' then
    raise exception 'finance_journal_not_submitted: journal % is % not submitted', p_journal_id, v_journal.status
      using errcode = 'check_violation';
  end if;

  update app.finance_journals set status = 'approved', approved_by = p_actor_label, approved_at = now() where id = p_journal_id returning * into v_journal;

  perform app.capture_audit_event(
    v_journal.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_finance_journal',
    'app.finance_journals', v_journal.id, 'success', null, null, to_jsonb(v_journal)
  );

  return v_journal;
end;
$function$
;

create or replace function app.post_finance_journal(p_journal_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_journals
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_journal app.finance_journals;
  v_period record;
  v_year integer;
  v_seq integer;
  v_number text;
  v_lines jsonb;
begin
  select * into v_journal from app.finance_journals where id = p_journal_id for update;
  if not found then
    raise exception 'finance_journal_not_found: %', p_journal_id using errcode = 'no_data_found';
  end if;
  if v_journal.status = 'posted' then
    return v_journal;
  end if;
  if not app.check_finance_journal_authority('Approve', v_journal.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_journal.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  -- HDN-373 (ISS-2026-181, maker/checker): defense in depth, mirroring this function's own
  -- existing convention of independently re-checking FIN:Approve rather than trusting the
  -- prior step alone -- the preparer may not reach posted status either.
  if v_journal.submitted_by_auth_user_id is not null and v_journal.submitted_by_auth_user_id = p_actor_auth_user_id then
    raise exception 'self_approval_denied: identity % submitted journal % and may not also post it', p_actor_auth_user_id, p_journal_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_journal.record_version <> p_expected_version then
    raise exception 'stale_version: journal % expected version % but found %', p_journal_id, p_expected_version, v_journal.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_journal.status <> 'approved' then
    raise exception 'finance_journal_not_approved: journal % is % not approved', p_journal_id, v_journal.status
      using errcode = 'check_violation';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('direction', direction, 'amount', amount)), '[]'::jsonb)
    into v_lines
    from app.finance_journal_lines where journal_id = p_journal_id;
  perform app.validate_finance_journal_line_balance(v_lines);

  select * into v_period from app.resolve_finance_period_for_date(v_journal.tenant_id, v_journal.company_id, v_journal.journal_date);
  if not found then
    raise exception 'finance_journal_period_not_found: no fiscal period covers %', v_journal.journal_date
      using errcode = 'no_data_found';
  end if;
  if not v_period.posting_eligible then
    raise exception 'finance_journal_period_not_open: fiscal period % for % is not open', v_period.period_code, v_journal.journal_date
      using errcode = 'check_violation';
  end if;
  perform app.assert_finance_period_open_for_posting(v_journal.tenant_id, v_journal.company_id, v_period.period_id, 'gl');

  v_year := extract(year from v_journal.journal_date)::integer;
  insert into app.finance_journal_number_counters (tenant_id, company_id, year, next_seq)
  values (v_journal.tenant_id, v_journal.company_id, v_year, 2)
  on conflict (tenant_id, coalesce(company_id, '00000000-0000-0000-0000-000000000000'::uuid), year)
  do update set next_seq = app.finance_journal_number_counters.next_seq + 1
  returning next_seq - 1 into v_seq;
  v_number := 'JRNL-' || v_year::text || '-' || lpad(v_seq::text, 6, '0');

  update app.finance_journals
    set status = 'posted', journal_number = v_number, posting_period_id = v_period.period_id, posted_by = p_actor_label, posted_at = now()
    where id = p_journal_id
    returning * into v_journal;

  perform app.capture_audit_event(
    v_journal.tenant_id, p_actor_auth_user_id, p_actor_label, 'post_finance_journal',
    'app.finance_journals', v_journal.id, 'success', null, null, to_jsonb(v_journal)
  );

  return v_journal;
end;
$function$
;

revoke execute on all functions in schema app from public;
