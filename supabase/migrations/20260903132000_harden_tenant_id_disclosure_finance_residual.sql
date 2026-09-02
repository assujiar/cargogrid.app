-- ISS-2026-146 -- cross-tenant tenant_id disclosure via exception message text.
-- Lane: Ticketing / white-label / localization / IAM "and the rest" (the residual after the
-- 20260902100000..20260902104000 Finance/HRIS/Procurement/Ticketing/Platform-Core batch).
--
-- Root cause, unchanged from the original disclosure: a SECURITY DEFINER function looks a
-- record up by its own bare id (unscoped, because the caller does not yet know which tenant
-- owns it), THEN evaluates the actor's authority against the looked-up row's own real
-- tenant_id, and on denial raises 'insufficient_authority: ... for tenant %' interpolating
-- that genuine tenant_id -- handing it to a caller with no demonstrated relationship to that
-- tenant at all.
--
-- Fix, identical in shape to the already-merged precedent (20260902100000, ISS-2026-043/048/
-- 054, and 20260730820000 before them): fold
-- app.has_active_tenant_membership(<row>.tenant_id, <actor>) into the SAME not-found branch
-- the row-miss case already raises, reusing that branch's own generic message and
-- errcode='no_data_found'. A caller with zero relationship to the record's tenant now gets
-- byte-for-byte the error a nonexistent id already produces. A SAME-TENANT member who merely
-- lacks the ROLE authority is untouched: they still reach the insufficient_authority raise
-- below with errcode='insufficient_privilege', exactly as before. That distinction is the
-- whole point of the shape and is preserved deliberately.
--
-- No permission check is weakened. The authority check itself (app.evaluate_permission /
-- app.check_*_authority) is byte-for-byte unchanged; only a tenant-membership pre-check was
-- placed ahead of it. app.evaluate_permission has itself required
-- app.has_active_tenant_membership since 20260810300000 (it returns
-- 'not_active_tenant_member' otherwise), and every app.check_*_authority helper is a thin
-- wrapper over it -- so the added gate can never deny a caller that the authority check
-- would have allowed.
--
-- Bodies were taken from each function's CURRENT, LIVE definition -- the LAST migration in
-- filename order that defines that name, not its creating migration. 40 of them were last
-- defined by 20260831270000 (the p_client_ip widening), which DROPped the pre-p_client_ip
-- signature; the p_client_ip signature below is therefore the only live one and CREATE OR
-- REPLACE matches it exactly. Signatures, SECURITY DEFINER, search_path, volatility and
-- return types are unchanged throughout, so no grant and no public.* wrapper is affected.
--
-- Part 3 of 4: Finance -- the residual Finance functions the 20260902100000 pass did not
-- reach, including the 20260831270000 p_client_ip signatures and job profitability.
--
-- 35 functions in this part.

-- app.acknowledge_loyalty_finance_liability_handoff -- live definition from 20260902072000_close_iss2026134_item5_loyalty_finance_liability_handoff.sql
create or replace function app.acknowledge_loyalty_finance_liability_handoff(p_batch_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.loyalty_finance_liability_handoff_batches
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_batch app.loyalty_finance_liability_handoff_batches;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_batch from app.loyalty_finance_liability_handoff_batches where id = p_batch_id for update;
  if not found or not app.has_active_tenant_membership(v_batch.tenant_id, p_actor_auth_user_id) then
    raise exception 'loyalty_finance_liability_handoff_batch_not_found: %', p_batch_id using errcode = 'no_data_found';
  end if;

  -- The ONE place in this handoff pair the calling actor must hold FINANCE
  -- authority, not Loyalty authority -- proves the acknowledging actor is
  -- genuinely Finance-side.
  if not (app.evaluate_permission(p_actor_auth_user_id, v_batch.tenant_id, 'FIN', 'Edit')).allowed then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_batch.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_batch.status = 'acknowledged' then
    return v_batch;
  end if;
  -- Double-defended NULL-bypass (this repository's own established
  -- discipline, ISS-2026-318): a null p_expected_version is rejected
  -- outright, never silently treated as "no concurrency check requested."
  if p_expected_version is null or v_batch.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_batch.record_version
      using errcode = 'serialization_failure';
  end if;

  update app.loyalty_finance_liability_handoff_batches set status = 'acknowledged', acknowledged_by = p_actor_label, acknowledged_at = now()
  where id = p_batch_id and record_version = p_expected_version
  returning * into v_batch;
  if not found then
    raise exception 'stale_version: concurrent update detected for handoff batch %', p_batch_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_batch.tenant_id, p_actor_auth_user_id, p_actor_label, 'acknowledge_loyalty_finance_liability_handoff',
    'app.loyalty_finance_liability_handoff_batches', v_batch.id, 'success', null, null, jsonb_build_object('status', v_batch.status)
  );

  return v_batch;
end;
$$;

-- app.acknowledge_payroll_finance_handoff_batch -- live definition from 20260731010000_bind_hris_payroll_to_finance_handoff.sql
create or replace function app.acknowledge_payroll_finance_handoff_batch(p_batch_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.payroll_finance_handoff_batches
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_batch app.payroll_finance_handoff_batches;
begin
  select * into v_batch from app.payroll_finance_handoff_batches where id = p_batch_id for update;
  if not found or not app.has_active_tenant_membership(v_batch.tenant_id, p_actor_auth_user_id) then
    raise exception 'payroll_finance_handoff_batch_not_found: %', p_batch_id using errcode = 'no_data_found';
  end if;
  -- The ONE place in this entire checkpoint the calling actor must hold
  -- FINANCE authority, not Payroll authority -- proves the acknowledging
  -- actor is genuinely Finance-side (decision 1).
  if not (app.evaluate_permission(p_actor_auth_user_id, v_batch.tenant_id, 'FIN', 'Edit')).allowed then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_batch.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_batch.status = 'acknowledged' then
    -- Idempotent no-op: a second acknowledgement of an already-acknowledged
    -- batch (by the same or a different Finance-authorized actor) returns
    -- the ORIGINAL acknowledgement unchanged, never overwrites who/when.
    return v_batch;
  end if;
  if v_batch.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_batch.record_version
      using errcode = 'serialization_failure';
  end if;

  update app.payroll_finance_handoff_batches set status = 'acknowledged', acknowledged_by = p_actor_label, acknowledged_at = now()
  where id = p_batch_id and record_version = p_expected_version
  returning * into v_batch;
  if not found then
    raise exception 'stale_version: concurrent update detected for handoff batch %', p_batch_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_batch.tenant_id, p_actor_auth_user_id, p_actor_label, 'acknowledge_payroll_finance_handoff_batch',
    'app.payroll_finance_handoff_batches', v_batch.id, 'success', null, null, jsonb_build_object('status', v_batch.status)
  );

  return v_batch;
end;
$$;

-- app.activate_finance_account -- live definition from 20260831270000_wire_ip_allowlist_into_sec_configure_fin_approve_hrs_approve.sql
create or replace function app.activate_finance_account(p_account_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_accounts
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_account app.finance_accounts;
  v_parent app.finance_accounts;
begin
  select * into v_account from app.finance_accounts where id = p_account_id;
  if not found or not app.has_active_tenant_membership(v_account.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_account_not_found: %', p_account_id using errcode = 'no_data_found';
  end if;

  if v_account.record_version <> p_expected_version then
    raise exception 'stale_version: account % expected version % but found %', p_account_id, p_expected_version, v_account.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_account.status <> 'draft' then
    raise exception 'finance_account_not_draft: account % is %, only a draft may be activated', p_account_id, v_account.status
      using errcode = 'check_violation';
  end if;

  if not app.check_finance_account_authority('Approve', v_account.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_account.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_account.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_account.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  if app.detect_finance_account_hierarchy_cycle(v_account.id, v_account.parent_account_id) then
    raise exception 'finance_account_hierarchy_cycle: activating account % would create or confirm a cyclic/over-deep hierarchy', p_account_id
      using errcode = 'check_violation';
  end if;

  if v_account.parent_account_id is not null then
    select * into v_parent from app.finance_accounts where id = v_account.parent_account_id;
    if v_parent.status = 'inactive' then
      raise exception 'finance_account_parent_inactive: parent account % is inactive', v_account.parent_account_id
        using errcode = 'check_violation';
    end if;
  end if;

  update app.finance_accounts
  set status = 'active'
  where id = p_account_id and record_version = p_expected_version
  returning * into v_account;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: activate_finance_account target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_account.tenant_id, p_actor_auth_user_id, p_actor_label, 'activate_finance_account',
    'app.finance_accounts', v_account.id, 'success', null, null, to_jsonb(v_account)
  );

  return v_account;
end;
$function$;

-- app.approve_finance_correction -- live definition from 20260831270000_wire_ip_allowlist_into_sec_configure_fin_approve_hrs_approve.sql
create or replace function app.approve_finance_correction(p_correction_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_journal_corrections
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_correction app.finance_journal_corrections;
begin
  select * into v_correction from app.finance_journal_corrections where id = p_correction_id for update;
  if not found or not app.has_active_tenant_membership(v_correction.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_correction_not_found: %', p_correction_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_correction_authority('Approve', v_correction.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_correction.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_correction.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_correction.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
  if v_correction.record_version <> p_expected_version then
    raise exception 'stale_version: correction % expected version % but found %', p_correction_id, p_expected_version, v_correction.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_correction.status <> 'submitted' then
    raise exception 'finance_correction_not_submitted: correction % is % not submitted', p_correction_id, v_correction.status
      using errcode = 'check_violation';
  end if;

  update app.finance_journal_corrections set status = 'approved', approved_by = p_actor_label, approved_at = now() where id = p_correction_id returning * into v_correction;

  perform app.capture_audit_event(
    v_correction.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_finance_correction',
    'app.finance_journal_corrections', v_correction.id, 'success', null, null, to_jsonb(v_correction)
  );

  return v_correction;
end;
$function$;

-- app.approve_finance_exchange_rate -- live definition from 20260831270000_wire_ip_allowlist_into_sec_configure_fin_approve_hrs_approve.sql
create or replace function app.approve_finance_exchange_rate(p_rate_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_exchange_rates
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_rate app.finance_exchange_rates;
  v_overlap_count integer;
begin
  select * into v_rate from app.finance_exchange_rates where id = p_rate_id for update;
  -- ATW-032: the overlapping-approved-window check below was an unlocked read with no
  -- exclusion constraint behind it, so two concurrent approvals for the same currency pair
  -- could both pass it and leave two overlapping approved rates -- after which every
  -- conversion for that pair depends on which row a query happens to pick. Locking the
  -- row being approved serialises approvals of the same rate.
  if not found or not app.has_active_tenant_membership(v_rate.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_exchange_rate_not_found: %', p_rate_id using errcode = 'no_data_found';
  end if;

  if v_rate.record_version <> p_expected_version then
    raise exception 'stale_version: rate % expected version % but found %', p_rate_id, p_expected_version, v_rate.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_rate.status <> 'draft' then
    raise exception 'finance_exchange_rate_not_draft: rate % is %, only a draft may be approved', p_rate_id, v_rate.status
      using errcode = 'check_violation';
  end if;

  if not app.check_finance_exchange_rate_authority('Approve', v_rate.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_rate.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_rate.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_rate.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  select count(*) into v_overlap_count from app.finance_exchange_rates
    where id <> p_rate_id
      and status = 'approved'
      and coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(v_rate.tenant_id, '00000000-0000-0000-0000-000000000000'::uuid)
      and rate_type = v_rate.rate_type
      and source_currency = v_rate.source_currency
      and target_currency = v_rate.target_currency
      and effective_from <= coalesce(v_rate.effective_to, 'infinity'::timestamptz)
      and coalesce(effective_to, 'infinity'::timestamptz) >= v_rate.effective_from;
  if v_overlap_count > 0 then
    raise exception 'finance_exchange_rate_overlap: an approved rate already covers an overlapping window for this scope/type/pair'
      using errcode = 'check_violation';
  end if;

  update app.finance_exchange_rates
  set status = 'approved', approved_by = p_actor_label, approved_at = now()
  where id = p_rate_id and record_version = p_expected_version
  returning * into v_rate;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: approve_finance_exchange_rate target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_rate.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_finance_exchange_rate',
    'app.finance_exchange_rates', v_rate.id, 'success', null, null, to_jsonb(v_rate)
  );

  return v_rate;
end;
$function$;

-- app.approve_finance_journal -- live definition from 20260831270000_wire_ip_allowlist_into_sec_configure_fin_approve_hrs_approve.sql
create or replace function app.approve_finance_journal(p_journal_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_journals
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_journal app.finance_journals;
begin
  select * into v_journal from app.finance_journals where id = p_journal_id for update;
  if not found or not app.has_active_tenant_membership(v_journal.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_journal_not_found: %', p_journal_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_journal_authority('Approve', v_journal.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_journal.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_journal.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_journal.tenant_id, p_client_ip, 'admin', p_actor_label);
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
$function$;

-- app.approve_finance_period_reopen -- live definition from 20260831270000_wire_ip_allowlist_into_sec_configure_fin_approve_hrs_approve.sql
create or replace function app.approve_finance_period_reopen(p_lock_id uuid, p_expected_version integer, p_window_hours integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_period_locks
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_lock app.finance_period_locks;
begin
  select * into v_lock from app.finance_period_locks where id = p_lock_id for update;
  if not found or not app.has_active_tenant_membership(v_lock.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_period_lock_not_found: %', p_lock_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_period_lock_authority('Approve', v_lock.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_lock.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_lock.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_lock.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
  if v_lock.record_version <> p_expected_version then
    raise exception 'stale_version: lock % expected version % but found %', p_lock_id, p_expected_version, v_lock.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_lock.status <> 'reopen_requested' then
    raise exception 'finance_period_lock_not_reopen_requested: lock % is % not reopen_requested', p_lock_id, v_lock.status
      using errcode = 'check_violation';
  end if;
  if p_window_hours is null or p_window_hours <= 0 or p_window_hours > 720 then
    raise exception 'finance_period_reopen_window_invalid: % is not a valid reopen window (1-720 hours)', p_window_hours
      using errcode = 'check_violation';
  end if;

  update app.finance_period_locks
    set status = 'reopened', reopen_approved_by = p_actor_label, reopened_at = now(), reopen_window_expires_at = now() + make_interval(hours => p_window_hours)
    where id = p_lock_id
    returning * into v_lock;

  insert into app.finance_period_lock_events (lock_id, tenant_id, action, reason, actor_label) values (v_lock.id, v_lock.tenant_id, 'reopened', v_lock.reopen_reason, p_actor_label);

  perform app.capture_audit_event(
    v_lock.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_finance_period_reopen',
    'app.finance_period_locks', v_lock.id, 'success', null, null, to_jsonb(v_lock)
  );

  return v_lock;
end;
$function$;

-- app.approve_finance_settlement -- live definition from 20260831270000_wire_ip_allowlist_into_sec_configure_fin_approve_hrs_approve.sql
create or replace function app.approve_finance_settlement(p_settlement_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_settlements
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_settlement app.finance_settlements;
begin
  select * into v_settlement from app.finance_settlements where id = p_settlement_id for update;
  if not found or not app.has_active_tenant_membership(v_settlement.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_settlement_not_found: %', p_settlement_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_settlement_authority('Approve', v_settlement.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_settlement.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_settlement.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_settlement.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
  if v_settlement.record_version <> p_expected_version then
    raise exception 'stale_version: settlement % expected version % but found %', p_settlement_id, p_expected_version, v_settlement.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_settlement.status <> 'submitted' then
    raise exception 'finance_settlement_not_submitted: settlement % is % not submitted', p_settlement_id, v_settlement.status
      using errcode = 'check_violation';
  end if;

  update app.finance_settlements set status = 'approved', approved_by = p_actor_label, approved_at = now() where id = p_settlement_id returning * into v_settlement;

  perform app.capture_audit_event(
    v_settlement.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_finance_settlement',
    'app.finance_settlements', v_settlement.id, 'success', null, null, to_jsonb(v_settlement)
  );

  return v_settlement;
end;
$function$;

-- app.approve_finance_tax_rule -- live definition from 20260831270000_wire_ip_allowlist_into_sec_configure_fin_approve_hrs_approve.sql
create or replace function app.approve_finance_tax_rule(p_rule_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_tax_rule_versions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_rule app.finance_tax_rule_versions;
  v_overlap_count integer;
begin
  select * into v_rule from app.finance_tax_rule_versions where id = p_rule_id for update;
  if not found or not app.has_active_tenant_membership(v_rule.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_tax_rule_not_found: %', p_rule_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_tax_authority('Approve', v_rule.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_rule.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_rule.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_rule.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
  if v_rule.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_rule.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_rule.status <> 'draft' then
    raise exception 'finance_tax_rule_not_draft: rule % is % not draft', p_rule_id, v_rule.status
      using errcode = 'check_violation';
  end if;
  if v_rule.is_example_fixture then
    raise exception 'finance_tax_rule_example_fixture_not_activatable: rule % is a seeded illustrative example and can never be approved -- create a fresh evidence-backed draft', p_rule_id
      using errcode = 'check_violation';
  end if;
  if v_rule.evidence_reference_file_id is null and (v_rule.evidence_note is null or length(trim(v_rule.evidence_note)) = 0) then
    raise exception 'finance_tax_rule_evidence_missing: rule % has no attached SME evidence', p_rule_id
      using errcode = 'check_violation';
  end if;

  select count(*) into v_overlap_count
    from app.finance_tax_rule_versions r
    where r.tax_code_id = v_rule.tax_code_id
      and coalesce(r.tenant_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(v_rule.tenant_id, '00000000-0000-0000-0000-000000000000'::uuid)
      and r.status = 'approved'
      and r.id <> v_rule.id
      and r.effective_from <= coalesce(v_rule.effective_to, 'infinity'::date)
      and coalesce(r.effective_to, 'infinity'::date) >= v_rule.effective_from;
  if v_overlap_count > 0 then
    raise exception 'finance_tax_rule_overlap: an approved rule for this tax code and scope already covers an overlapping effective window'
      using errcode = 'check_violation';
  end if;

  update app.finance_tax_rule_versions
    set status = 'approved', approved_by = p_actor_label, approved_at = now()
    where id = p_rule_id
    returning * into v_rule;

  perform app.capture_audit_event(
    v_rule.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_finance_tax_rule',
    'app.finance_tax_rule_versions', v_rule.id, 'success', null, null, to_jsonb(v_rule)
  );

  return v_rule;
end;
$function$;

-- app.approve_finance_vendor_bill -- live definition from 20260831270000_wire_ip_allowlist_into_sec_configure_fin_approve_hrs_approve.sql
create or replace function app.approve_finance_vendor_bill(p_bill_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_vendor_bills
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_bill app.finance_vendor_bills;
begin
  select * into v_bill from app.finance_vendor_bills where id = p_bill_id for update;
  if not found or not app.has_active_tenant_membership(v_bill.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_vendor_bill_not_found: %', p_bill_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_vendor_bill_authority('Approve', v_bill.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_bill.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_bill.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_bill.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
  if v_bill.record_version <> p_expected_version then
    raise exception 'stale_version: bill % expected version % but found %', p_bill_id, p_expected_version, v_bill.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_bill.status <> 'submitted' then
    raise exception 'finance_vendor_bill_not_submitted: bill % is % not submitted', p_bill_id, v_bill.status
      using errcode = 'check_violation';
  end if;

  update app.finance_vendor_bills set status = 'approved', approved_by = p_actor_label, approved_at = now() where id = p_bill_id returning * into v_bill;

  perform app.capture_audit_event(
    v_bill.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_finance_vendor_bill',
    'app.finance_vendor_bills', v_bill.id, 'success', null, jsonb_build_object('varianceStatus', v_bill.variance_status), to_jsonb(v_bill)
  );

  return v_bill;
end;
$function$;

-- app.calculate_finance_job_profitability -- live definition from 20260729280000_create_finance_field_level_security.sql
create or replace function app.calculate_finance_job_profitability(
  p_job_order_id uuid,
  p_recalculation_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_job_profitability_facts
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_job app.job_orders;
  v_existing_current app.finance_job_profitability_facts;
  v_revenue_currency_count integer;
  v_invoice_count integer;
  v_raw_revenue_amount numeric(14, 2);
  v_invoice_ids uuid[];
  v_revenue_currency text;
  v_revenue_amount numeric(14, 2);
  v_cost_currency_count integer;
  v_cost_count integer;
  v_raw_cost_amount numeric(14, 2);
  v_cost_version_ids uuid[];
  v_cost_currency_check text;
  v_status text;
  v_blocked_reason text;
  v_cost_currency text;
  v_cost_amount numeric(14, 2);
  v_profit_amount numeric(14, 2);
  v_margin_percent numeric(9, 4);
  v_new_version integer;
  v_fact app.finance_job_profitability_facts;
begin
  select * into v_job from app.job_orders jo where jo.id = p_job_order_id;
  if not found or not app.has_active_tenant_membership(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'job_order_not_found: %', p_job_order_id using errcode = 'no_data_found';
  end if;

  if not app.check_finance_profitability_authority('Edit', v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.has_view_finance_margin(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View margin for tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_existing_current from app.finance_job_profitability_facts where job_order_id = p_job_order_id and is_current;
  if found and (p_recalculation_reason is null or length(trim(p_recalculation_reason)) = 0) then
    raise exception 'finance_profitability_recalculation_reason_required: a reason is required to recalculate an existing profitability fact' using errcode = 'check_violation';
  end if;

  select count(distinct currency), count(*), sum(subtotal_amount), coalesce(array_agg(id), '{}'::uuid[])
  into v_revenue_currency_count, v_invoice_count, v_raw_revenue_amount, v_invoice_ids
  from app.finance_invoices
  where job_order_id = p_job_order_id and status = 'issued';

  select count(distinct sac.currency), count(*), sum(sac.total_amount), coalesce(array_agg(sac.id), '{}'::uuid[])
  into v_cost_currency_count, v_cost_count, v_raw_cost_amount, v_cost_version_ids
  from app.shipment_actual_costs sac
  join app.shipment_orders so on so.id = sac.shipment_order_id
  where so.job_order_id = p_job_order_id and sac.is_current and sac.status = 'approved';

  if v_invoice_count = 0 then
    v_status := 'unavailable';
    v_blocked_reason := 'no_billed_revenue';
  elsif v_revenue_currency_count > 1 then
    v_status := 'unavailable';
    v_blocked_reason := 'mixed_currency';
  else
    select currency into v_revenue_currency from app.finance_invoices where id = v_invoice_ids[1];
    v_revenue_amount := v_raw_revenue_amount;
  end if;

  if v_status is null then
    if v_cost_count = 0 then
      v_status := 'unavailable';
      v_blocked_reason := 'no_approved_cost';
    else
      select sac.currency into v_cost_currency_check from app.shipment_actual_costs sac where sac.id = v_cost_version_ids[1];
      if v_cost_currency_count > 1 or v_cost_currency_check <> v_revenue_currency then
        v_status := 'unavailable';
        v_blocked_reason := 'mixed_currency';
      else
        v_status := 'calculated';
        v_cost_currency := v_revenue_currency;
        v_cost_amount := v_raw_cost_amount;
        v_profit_amount := v_revenue_amount - v_cost_amount;
        v_margin_percent := case when v_revenue_amount <> 0 then round((v_profit_amount / v_revenue_amount) * 100, 4) else null end;
      end if;
    end if;
  end if;

  v_new_version := coalesce(v_existing_current.version_number, 0) + 1;
  if found then
    update app.finance_job_profitability_facts set is_current = false where id = v_existing_current.id;
  end if;

  insert into app.finance_job_profitability_facts (
    tenant_id, job_order_id, version_number, is_current, status, blocked_reason, revenue_basis,
    revenue_currency, revenue_amount, cost_currency, cost_amount, profit_amount, margin_percent,
    source_invoice_ids, source_cost_version_ids, recalculation_reason, calculated_by_auth_user_id, created_by
  ) values (
    v_job.tenant_id, p_job_order_id, v_new_version, true, v_status, v_blocked_reason, 'billed',
    v_revenue_currency, v_revenue_amount, v_cost_currency, v_cost_amount, v_profit_amount, v_margin_percent,
    v_invoice_ids, v_cost_version_ids, p_recalculation_reason, p_actor_auth_user_id, p_actor_label
  )
  returning * into v_fact;

  -- FIN-214: redacted audit payload -- an explicit allowlist of non-sensitive
  -- fields only, never the financial figures or source-document id arrays.
  -- Byte-for-byte identical to FIN-212's own body above this line.
  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'calculate_finance_job_profitability',
    'app.finance_job_profitability_facts', v_fact.id, 'success', p_recalculation_reason, null,
    jsonb_build_object(
      'id', v_fact.id,
      'job_order_id', v_fact.job_order_id,
      'version_number', v_fact.version_number,
      'is_current', v_fact.is_current,
      'status', v_fact.status,
      'blocked_reason', v_fact.blocked_reason,
      'revenue_basis', v_fact.revenue_basis,
      'calculated_at', v_fact.calculated_at
    )
  );

  return v_fact;
end;
$$;

-- app.certify_finance_reconciliation_run -- live definition from 20260831270000_wire_ip_allowlist_into_sec_configure_fin_approve_hrs_approve.sql
create or replace function app.certify_finance_reconciliation_run(p_run_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_reconciliation_runs
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_run app.finance_reconciliation_runs;
  v_open_exceptions integer;
begin
  select * into v_run from app.finance_reconciliation_runs where id = p_run_id for update;
  if not found or not app.has_active_tenant_membership(v_run.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_reconciliation_run_not_found: %', p_run_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_reconciliation_authority('Approve', v_run.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_run.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_run.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_run.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
  if v_run.record_version <> p_expected_version then
    raise exception 'stale_version: run % expected version % but found %', p_run_id, p_expected_version, v_run.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_reconciliation_certify_reason_required: a non-empty reason is required' using errcode = 'check_violation';
  end if;
  if v_run.status = 'certified' then
    return v_run;
  end if;

  select count(*) into v_open_exceptions from app.finance_reconciliation_exceptions where run_id = p_run_id and status = 'open';
  if v_open_exceptions > 0 then
    raise exception 'finance_reconciliation_unexplained_variance: run % has % unresolved exception(s)', p_run_id, v_open_exceptions
      using errcode = 'check_violation';
  end if;

  update app.finance_reconciliation_runs
    set status = 'certified', certify_reason = p_reason, certified_by = p_actor_label, certified_at = now()
    where id = p_run_id
    returning * into v_run;

  perform app.capture_audit_event(
    v_run.tenant_id, p_actor_auth_user_id, p_actor_label, 'certify_finance_reconciliation_run',
    'app.finance_reconciliation_runs', v_run.id, 'success', p_reason, null, to_jsonb(v_run)
  );

  return v_run;
end;
$function$;

-- app.close_finance_period -- live definition from 20260831270000_wire_ip_allowlist_into_sec_configure_fin_approve_hrs_approve.sql
create or replace function app.close_finance_period(p_period_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_fiscal_periods
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_period app.finance_fiscal_periods;
  v_unsatisfied_count integer;
begin
  select * into v_period from app.finance_fiscal_periods where id = p_period_id;
  if not found or not app.has_active_tenant_membership(v_period.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_period_not_found: %', p_period_id using errcode = 'no_data_found';
  end if;

  if v_period.record_version <> p_expected_version then
    raise exception 'stale_version: period % expected version % but found %', p_period_id, p_expected_version, v_period.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_period.status <> 'soft_closed' then
    raise exception 'finance_period_not_soft_closed: period % is %, only a soft-closed period may be closed', p_period_id, v_period.status
      using errcode = 'check_violation';
  end if;

  if not app.check_finance_period_authority('Approve', v_period.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_period.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_period.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_period.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  select count(*) into v_unsatisfied_count from app.finance_period_close_checklist_items
    where period_id = p_period_id and required and not satisfied;
  if v_unsatisfied_count > 0 then
    raise exception 'finance_period_checklist_incomplete: period % has % unsatisfied required close-checklist item(s)', p_period_id, v_unsatisfied_count
      using errcode = 'check_violation';
  end if;

  update app.finance_fiscal_periods
  set status = 'closed', closed_at = now(), closed_by = p_actor_label
  where id = p_period_id and record_version = p_expected_version
  returning * into v_period;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: close_finance_period target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.finance_period_transitions (period_id, tenant_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (p_period_id, v_period.tenant_id, 'soft_closed', 'closed', null, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_period.tenant_id, p_actor_auth_user_id, p_actor_label, 'close_finance_period',
    'app.finance_fiscal_periods', v_period.id, 'success', null, null, to_jsonb(v_period)
  );

  return v_period;
end;
$function$;

-- app.discard_finance_settlement_draft -- live definition from 20260831270000_wire_ip_allowlist_into_sec_configure_fin_approve_hrs_approve.sql
create or replace function app.discard_finance_settlement_draft(p_settlement_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_settlements
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_settlement app.finance_settlements;
  v_was_executed boolean;
begin
  select * into v_settlement from app.finance_settlements where id = p_settlement_id for update;
  if not found or not app.has_active_tenant_membership(v_settlement.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_settlement_not_found: %', p_settlement_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_settlement_authority('Edit', v_settlement.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_settlement.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_settlement.record_version <> p_expected_version then
    raise exception 'stale_version: settlement % expected version % but found %', p_settlement_id, p_expected_version, v_settlement.record_version
      using errcode = 'serialization_failure';
  end if;
  -- ATW-032: 'executed' had no outgoing edge other than post_finance_settlement,
  -- and that edge fails unconditionally with finance_ap_over_settlement once a
  -- competing settlement has consumed the same AP open item. Such a settlement
  -- could not post, could not reverse (that path requires 'posted') and could not
  -- be discarded -- a real bank payment left permanently without a governed
  -- disposition. finance_settlements_status_check already admits 'void', so this
  -- needs no schema change; it needs an authorized, evidenced exit.
  -- 'approved' is deliberately NOT admitted: execute_finance_settlement is the
  -- correct next step from there and it is not blocked.
  if v_settlement.status not in ('draft', 'submitted', 'executed') then
    raise exception 'finance_settlement_not_cancellable: settlement % is %, only a draft, submitted or executed settlement may be discarded', p_settlement_id, v_settlement.status
      using errcode = 'check_violation';
  end if;

  v_was_executed := (v_settlement.status = 'executed');

  -- ATW-032: voiding an EXECUTED settlement is an approval-grade act, not an
  -- editing one -- a payment instruction has already left the bank
  -- (execution_reference/executed_by/executed_at are set). It is therefore held
  -- to the same FIN:Approve gate execute_/post_/request_..._reversal each apply,
  -- and to the same non-empty-reason requirement request_finance_settlement_reversal
  -- already imposes on the other post-execution correction path. The
  -- pre-execution statuses keep their original FIN:Edit-only behaviour exactly.
  if v_was_executed then
    if not app.check_finance_settlement_authority('Approve', v_settlement.tenant_id, p_actor_auth_user_id) then
      raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant % -- voiding an executed settlement requires approval authority, not edit authority', p_actor_auth_user_id, v_settlement.tenant_id
        using errcode = 'insufficient_privilege';
    end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_settlement.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_settlement.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
    if p_reason is null or length(trim(p_reason)) = 0 then
      raise exception 'finance_settlement_void_reason_required: a non-empty reason is required to void an executed settlement'
        using errcode = 'check_violation';
    end if;
  end if;

  -- ATW-032: execution_reference, executed_by and executed_at are deliberately
  -- left untouched -- the evidence that a real payment left the bank must survive
  -- the void, not be erased by it.
  update app.finance_settlements set status = 'void', void_reason = p_reason, voided_by = p_actor_label, voided_at = now() where id = p_settlement_id returning * into v_settlement;

  -- ATW-032: a distinct action so a reviewer reading the audit trail can never
  -- mistake the voiding of a real executed payment for an ordinary draft discard.
  perform app.capture_audit_event(
    v_settlement.tenant_id, p_actor_auth_user_id, p_actor_label,
    case when v_was_executed then 'void_finance_executed_settlement' else 'discard_finance_settlement_draft' end,
    'app.finance_settlements', v_settlement.id, 'success', p_reason, null, to_jsonb(v_settlement)
  );

  return v_settlement;
end;
$function$;

-- app.execute_finance_settlement -- live definition from 20260831270000_wire_ip_allowlist_into_sec_configure_fin_approve_hrs_approve.sql
create or replace function app.execute_finance_settlement(p_settlement_id uuid, p_expected_version integer, p_execution_reference text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_settlements
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_settlement app.finance_settlements;
begin
  select * into v_settlement from app.finance_settlements where id = p_settlement_id for update;
  if not found or not app.has_active_tenant_membership(v_settlement.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_settlement_not_found: %', p_settlement_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_settlement_authority('Approve', v_settlement.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_settlement.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_settlement.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_settlement.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
  if v_settlement.record_version <> p_expected_version then
    raise exception 'stale_version: settlement % expected version % but found %', p_settlement_id, p_expected_version, v_settlement.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_settlement.status <> 'approved' then
    raise exception 'finance_settlement_not_approved: settlement % is % not approved', p_settlement_id, v_settlement.status
      using errcode = 'check_violation';
  end if;

  update app.finance_settlements
    set status = 'executed', execution_reference = p_execution_reference, executed_by = p_actor_label, executed_at = now()
    where id = p_settlement_id
    returning * into v_settlement;

  perform app.capture_audit_event(
    v_settlement.tenant_id, p_actor_auth_user_id, p_actor_label, 'execute_finance_settlement',
    'app.finance_settlements', v_settlement.id, 'success', null, null, to_jsonb(v_settlement)
  );

  return v_settlement;
end;
$function$;

-- app.get_finance_job_profitability -- live definition from 20260729260000_create_finance_job_profitability.sql
create or replace function app.get_finance_job_profitability(p_job_order_id uuid, p_actor_auth_user_id uuid)
returns setof app.finance_job_profitability_facts
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_job app.job_orders;
begin
  select * into v_job from app.job_orders jo where jo.id = p_job_order_id;
  if not found or not app.has_active_tenant_membership(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'job_order_not_found: %', p_job_order_id using errcode = 'no_data_found';
  end if;
  if not app.has_view_finance_margin(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View margin for tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_job_profitability_facts where job_order_id = p_job_order_id and is_current;
end;
$$;

-- app.get_finance_journal_lines -- live definition from 20260729170000_create_finance_journal.sql
create or replace function app.get_finance_journal_lines(p_journal_id uuid, p_actor_auth_user_id uuid)
returns setof app.finance_journal_lines
language plpgsql
stable
as $$
declare
  v_journal app.finance_journals;
begin
  select * into v_journal from app.finance_journals where id = p_journal_id;
  if not found or not app.has_active_tenant_membership(v_journal.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_journal_not_found: %', p_journal_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_journal_authority('View', v_journal.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, v_journal.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_journal_lines where journal_id = p_journal_id order by line_number asc;
end;
$$;

-- app.get_payroll_finance_handoff_reconciliation -- live definition from 20260731010000_bind_hris_payroll_to_finance_handoff.sql
create or replace function app.get_payroll_finance_handoff_reconciliation(p_batch_id uuid, p_actor_auth_user_id uuid)
returns table (
  gl_lines_net numeric, payment_instructions_total numeric, run_results_net_total numeric, is_reconciled boolean
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_batch app.payroll_finance_handoff_batches;
  v_gl_net numeric(14, 2);
  v_pay_total numeric(14, 2);
begin
  select * into v_batch from app.payroll_finance_handoff_batches where id = p_batch_id;
  if not found or not app.has_active_tenant_membership(v_batch.tenant_id, p_actor_auth_user_id) then
    raise exception 'payroll_finance_handoff_batch_not_found: %', p_batch_id using errcode = 'no_data_found';
  end if;
  if not (
    (app.evaluate_permission(p_actor_auth_user_id, v_batch.tenant_id, 'HRS', 'View payroll')).allowed
    or (app.evaluate_permission(p_actor_auth_user_id, v_batch.tenant_id, 'FIN', 'View')).allowed
  ) then
    raise exception 'insufficient_authority: identity % lacks HRS:View payroll or FIN:View for tenant %', p_actor_auth_user_id, v_batch.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select coalesce(sum(amount) filter (where line_type in ('earning', 'reimbursement')), 0)
       - coalesce(sum(amount) filter (where line_type in ('deduction', 'tax', 'loan_repayment')), 0)
  into v_gl_net
  from app.payroll_finance_handoff_gl_lines where handoff_batch_id = p_batch_id;

  select coalesce(sum(net_pay_amount), 0) into v_pay_total from app.payroll_finance_handoff_payment_instructions where handoff_batch_id = p_batch_id;

  gl_lines_net := v_gl_net;
  payment_instructions_total := v_pay_total;
  run_results_net_total := v_batch.net_pay_total;
  is_reconciled := (v_gl_net = v_batch.net_pay_total) and (v_pay_total = v_batch.net_pay_total);
  return next;
end;
$$;

-- app.issue_finance_invoice -- live definition from 20260831270000_wire_ip_allowlist_into_sec_configure_fin_approve_hrs_approve.sql
create or replace function app.issue_finance_invoice(p_invoice_id uuid, p_expected_version integer, p_issue_date date, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_invoices
 LANGUAGE plpgsql
AS $function$
declare
  v_invoice app.finance_invoices;
  v_period record;
  v_year integer;
  v_seq integer;
  v_number text;
  v_ar_item app.finance_ar_open_items;
  v_due_date date;
  v_lines jsonb;
  v_tax_line app.finance_invoice_lines;
  v_tax_rule app.finance_tax_rule_versions;
begin
  select * into v_invoice from app.finance_invoices where id = p_invoice_id for update;
  if not found or not app.has_active_tenant_membership(v_invoice.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_invoice_not_found: %', p_invoice_id using errcode = 'no_data_found';
  end if;
  if v_invoice.status = 'issued' then
    return v_invoice;
  end if;
  if not app.check_finance_invoice_authority('Approve', v_invoice.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_invoice.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_invoice.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_invoice.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
  if v_invoice.record_version <> p_expected_version then
    raise exception 'stale_version: invoice % expected version % but found %', p_invoice_id, p_expected_version, v_invoice.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_invoice.status <> 'approved' then
    raise exception 'finance_invoice_not_approved: invoice % is % not approved', p_invoice_id, v_invoice.status
      using errcode = 'check_violation';
  end if;

  -- HDN-374 (Financial Integrity Audit) finding 2: a job order may reach `issued` for at
  -- most one invoice at a time -- backed by finance_invoices_job_order_issued_unique
  -- (Tier C fix), not merely this application-level pre-check. Draft/submitted/approved
  -- invoices from a legitimate re-handoff (OPS-181) remain freely creatable and discardable
  -- (see the migration header); this is the actual AR/GL posting boundary, so it is the one
  -- place a second full-amount bill for the same job's revenue must be refused.
  if exists (
    select 1 from app.finance_invoices
    where tenant_id = v_invoice.tenant_id and job_order_id = v_invoice.job_order_id
      and id <> v_invoice.id and status = 'issued'
  ) then
    raise exception 'finance_invoice_job_order_already_issued: job order % already has a different issued invoice', v_invoice.job_order_id
      using errcode = 'check_violation';
  end if;

  select * into v_period from app.resolve_finance_period_for_date(v_invoice.tenant_id, v_invoice.company_id, p_issue_date);
  if not found then
    raise exception 'finance_invoice_period_not_found: no fiscal period covers %', p_issue_date
      using errcode = 'no_data_found';
  end if;
  if not v_period.posting_eligible then
    raise exception 'finance_invoice_period_not_open: fiscal period % for % is not open', v_period.period_code, p_issue_date
      using errcode = 'check_violation';
  end if;

  v_year := extract(year from p_issue_date)::integer;
  insert into app.finance_invoice_number_counters (tenant_id, company_id, year, next_seq)
  values (v_invoice.tenant_id, v_invoice.company_id, v_year, 2)
  on conflict (tenant_id, coalesce(company_id, '00000000-0000-0000-0000-000000000000'::uuid), year)
  do update set next_seq = app.finance_invoice_number_counters.next_seq + 1
  returning next_seq - 1 into v_seq;
  v_number := 'INV-' || v_year::text || '-' || lpad(v_seq::text, 6, '0');

  v_due_date := p_issue_date + (v_invoice.payment_term_days || ' days')::interval;

  select * into v_ar_item from app.post_finance_ar_open_item(
    v_invoice.tenant_id, v_invoice.company_id, v_invoice.customer_account_id, 'invoice', v_invoice.id,
    v_invoice.currency, v_invoice.total_amount, p_issue_date, v_due_date, p_actor_auth_user_id, p_actor_label
  );

  -- FIN-202: debit AR control for the full total; credit revenue for the
  -- subtotal; credit each tax line's own governed output account (or the
  -- tax_payable_default posting-map key when none is configured).
  v_lines := jsonb_build_array(
    jsonb_build_object('postingMapKey', 'ar_control', 'direction', 'debit', 'amount', v_invoice.total_amount, 'openItemType', 'ar_open_item', 'openItemId', v_ar_item.id)
  );
  if v_invoice.subtotal_amount > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('postingMapKey', 'revenue_default', 'direction', 'credit', 'amount', v_invoice.subtotal_amount));
  end if;
  for v_tax_line in select * from app.finance_invoice_lines where invoice_id = p_invoice_id and line_type = 'tax' and amount > 0 loop
    v_tax_rule := null;
    if v_tax_line.tax_rule_version_id is not null then
      select * into v_tax_rule from app.finance_tax_rule_versions where id = v_tax_line.tax_rule_version_id and output_account_id is not null;
    end if;
    if v_tax_rule is not null then
      v_lines := v_lines || jsonb_build_array(jsonb_build_object('accountId', v_tax_rule.output_account_id, 'direction', 'credit', 'amount', v_tax_line.amount));
    else
      v_lines := v_lines || jsonb_build_array(jsonb_build_object('postingMapKey', 'tax_payable_default', 'direction', 'credit', 'amount', v_tax_line.amount));
    end if;
  end loop;

  perform app.post_finance_subledger_batch(
    v_invoice.tenant_id, v_invoice.company_id, 'invoice', v_invoice.id, p_issue_date, v_invoice.currency,
    v_lines, p_actor_auth_user_id, p_actor_label
  );

  -- HDN-374 Tier C finding 2: a genuine race between the exists() pre-check above and this
  -- update (two concurrent issue_finance_invoice calls for two DIFFERENT invoices on the
  -- SAME job order, each already past its own exists() check before either commits) is
  -- caught here by finance_invoices_job_order_issued_unique -- the loser's own update
  -- raises unique_violation instead of silently succeeding; re-raised as the same named
  -- exception the non-concurrent pre-check above already gives, never a raw unique_violation.
  begin
    update app.finance_invoices
      set status = 'issued', invoice_number = v_number, issue_date = p_issue_date, due_date = v_due_date,
          posting_period_id = v_period.period_id, ar_open_item_id = v_ar_item.id, issued_by = p_actor_label, issued_at = now()
      where id = p_invoice_id
      returning * into v_invoice;
  exception
    when unique_violation then
      raise exception 'finance_invoice_job_order_already_issued: job order % already has a different issued invoice', v_invoice.job_order_id
        using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    v_invoice.tenant_id, p_actor_auth_user_id, p_actor_label, 'issue_finance_invoice',
    'app.finance_invoices', v_invoice.id, 'success', null, null, to_jsonb(v_invoice)
  );

  return v_invoice;
end;
$function$;

-- app.post_finance_correction -- live definition from 20260831270000_wire_ip_allowlist_into_sec_configure_fin_approve_hrs_approve.sql
create or replace function app.post_finance_correction(p_correction_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_journal_corrections
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_correction app.finance_journal_corrections;
  v_original app.finance_journals;
  v_lines jsonb := '[]'::jsonb;
  v_line record;
  v_flipped text;
  v_journal app.finance_journals;
  v_batch app.finance_subledger_batches;
begin
  select * into v_correction from app.finance_journal_corrections where id = p_correction_id for update;
  if not found or not app.has_active_tenant_membership(v_correction.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_correction_not_found: %', p_correction_id using errcode = 'no_data_found';
  end if;
  if v_correction.status = 'posted' then
    return v_correction;
  end if;
  if not app.check_finance_correction_authority('Approve', v_correction.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_correction.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_correction.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_correction.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
  if v_correction.record_version <> p_expected_version then
    raise exception 'stale_version: correction % expected version % but found %', p_correction_id, p_expected_version, v_correction.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_correction.status <> 'approved' then
    raise exception 'finance_correction_not_approved: correction % is % not approved', p_correction_id, v_correction.status
      using errcode = 'check_violation';
  end if;

  select * into v_original from app.finance_journals where id = v_correction.original_journal_id;
  if not found or v_original.status <> 'posted' then
    raise exception 'finance_correction_original_not_posted: journal % is no longer posted', v_correction.original_journal_id
      using errcode = 'check_violation';
  end if;

  if v_correction.correction_type = 'reversal' then
    for v_line in select direction, account_id, amount, dimension from app.finance_journal_lines where journal_id = v_original.id order by line_number asc loop
      v_flipped := case when v_line.direction = 'debit' then 'credit' else 'debit' end;
      v_lines := v_lines || jsonb_build_array(jsonb_build_object('accountId', v_line.account_id, 'direction', v_flipped, 'amount', v_line.amount, 'dimension', v_line.dimension));
    end loop;
  else
    v_lines := v_correction.adjustment_lines;
  end if;

  select * into v_journal from app.create_and_post_finance_system_journal(
    v_correction.tenant_id, v_correction.company_id, 'correction', v_correction.id, v_correction.correction_date,
    v_original.currency, v_lines, p_actor_auth_user_id, p_actor_label, 'gl'
  );

  if v_correction.correction_type = 'reversal' and v_original.source_type = 'subledger' then
    update app.finance_subledger_batches set status = 'reversed' where gl_journal_id = v_original.id and status = 'posted' returning * into v_batch;
  end if;

  update app.finance_journal_corrections
    set status = 'posted', correction_journal_id = v_journal.id, posted_by = p_actor_label, posted_at = now()
    where id = p_correction_id
    returning * into v_correction;

  perform app.capture_audit_event(
    v_correction.tenant_id, p_actor_auth_user_id, p_actor_label, 'post_finance_correction',
    'app.finance_journal_corrections', v_correction.id, 'success', null, null, to_jsonb(v_correction)
  );

  return v_correction;
end;
$function$;

-- app.post_finance_journal -- live definition from 20260831270000_wire_ip_allowlist_into_sec_configure_fin_approve_hrs_approve.sql
create or replace function app.post_finance_journal(p_journal_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
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
  if not found or not app.has_active_tenant_membership(v_journal.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_journal_not_found: %', p_journal_id using errcode = 'no_data_found';
  end if;
  if v_journal.status = 'posted' then
    return v_journal;
  end if;
  if not app.check_finance_journal_authority('Approve', v_journal.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_journal.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_journal.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_journal.tenant_id, p_client_ip, 'admin', p_actor_label);
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
$function$;

-- app.post_finance_settlement -- live definition from 20260831270000_wire_ip_allowlist_into_sec_configure_fin_approve_hrs_approve.sql
create or replace function app.post_finance_settlement(p_settlement_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_settlements
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_settlement app.finance_settlements;
  v_period record;
  v_year integer;
  v_seq integer;
  v_number text;
  v_allocation app.finance_settlement_allocations;
  v_lines jsonb;
begin
  select * into v_settlement from app.finance_settlements where id = p_settlement_id for update;
  if not found or not app.has_active_tenant_membership(v_settlement.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_settlement_not_found: %', p_settlement_id using errcode = 'no_data_found';
  end if;
  if v_settlement.status = 'posted' then
    return v_settlement;
  end if;
  if not app.check_finance_settlement_authority('Approve', v_settlement.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_settlement.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_settlement.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_settlement.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
  if v_settlement.record_version <> p_expected_version then
    raise exception 'stale_version: settlement % expected version % but found %', p_settlement_id, p_expected_version, v_settlement.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_settlement.status <> 'executed' then
    raise exception 'finance_settlement_not_executed: settlement % is % not executed', p_settlement_id, v_settlement.status
      using errcode = 'check_violation';
  end if;

  select * into v_period from app.resolve_finance_period_for_date(v_settlement.tenant_id, v_settlement.company_id, v_settlement.settlement_date);
  if not found then
    raise exception 'finance_settlement_period_not_found: no fiscal period covers %', v_settlement.settlement_date
      using errcode = 'no_data_found';
  end if;
  if not v_period.posting_eligible then
    raise exception 'finance_settlement_period_not_open: fiscal period % for % is not open', v_period.period_code, v_settlement.settlement_date
      using errcode = 'check_violation';
  end if;

  for v_allocation in select * from app.finance_settlement_allocations where settlement_id = p_settlement_id and status = 'applied' order by created_at asc loop
    perform app.apply_finance_ap_settlement(
      v_allocation.ap_open_item_id, v_allocation.amount, 'settlement', v_settlement.id,
      v_settlement.idempotency_key || ':' || v_allocation.ap_open_item_id::text, p_actor_auth_user_id, p_actor_label
    );
  end loop;

  -- FIN-202: debit AP control for the allocated total (plus a governed fee
  -- expense debit when a fee applies); credit cash for the full total.
  v_lines := jsonb_build_array(
    jsonb_build_object('postingMapKey', 'ap_control', 'direction', 'debit', 'amount', v_settlement.allocated_amount)
  );
  if v_settlement.fee_amount > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('postingMapKey', 'fee_expense_default', 'direction', 'debit', 'amount', v_settlement.fee_amount));
  end if;
  v_lines := v_lines || jsonb_build_array(jsonb_build_object('postingMapKey', 'cash_default', 'direction', 'credit', 'amount', v_settlement.total_amount));

  perform app.post_finance_subledger_batch(
    v_settlement.tenant_id, v_settlement.company_id, 'settlement', v_settlement.id, v_settlement.settlement_date, v_settlement.currency,
    v_lines, p_actor_auth_user_id, p_actor_label
  );

  v_year := extract(year from v_settlement.settlement_date)::integer;
  insert into app.finance_settlement_number_counters (tenant_id, company_id, year, next_seq)
  values (v_settlement.tenant_id, v_settlement.company_id, v_year, 2)
  on conflict (tenant_id, coalesce(company_id, '00000000-0000-0000-0000-000000000000'::uuid), year)
  do update set next_seq = app.finance_settlement_number_counters.next_seq + 1
  returning next_seq - 1 into v_seq;
  v_number := 'SETL-' || v_year::text || '-' || lpad(v_seq::text, 6, '0');

  update app.finance_settlements
    set status = 'posted', settlement_number = v_number, posting_period_id = v_period.period_id,
        posted_by = p_actor_label, posted_at = now()
    where id = p_settlement_id
    returning * into v_settlement;

  perform app.capture_audit_event(
    v_settlement.tenant_id, p_actor_auth_user_id, p_actor_label, 'post_finance_settlement',
    'app.finance_settlements', v_settlement.id, 'success', null, null, to_jsonb(v_settlement)
  );

  return v_settlement;
end;
$function$;

-- app.post_finance_vendor_bill -- live definition from 20260831270000_wire_ip_allowlist_into_sec_configure_fin_approve_hrs_approve.sql
create or replace function app.post_finance_vendor_bill(p_bill_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_vendor_bills
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_bill app.finance_vendor_bills;
  v_period record;
  v_year integer;
  v_seq integer;
  v_number text;
  v_ap_item app.finance_ap_open_items;
  v_lines jsonb;
  v_tax_line app.finance_vendor_bill_lines;
  v_tax_rule app.finance_tax_rule_versions;
begin
  select * into v_bill from app.finance_vendor_bills where id = p_bill_id for update;
  if not found or not app.has_active_tenant_membership(v_bill.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_vendor_bill_not_found: %', p_bill_id using errcode = 'no_data_found';
  end if;
  if v_bill.status = 'posted' then
    return v_bill;
  end if;
  if not app.check_finance_vendor_bill_authority('Approve', v_bill.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_bill.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_bill.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_bill.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
  if v_bill.record_version <> p_expected_version then
    raise exception 'stale_version: bill % expected version % but found %', p_bill_id, p_expected_version, v_bill.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_bill.status <> 'approved' then
    raise exception 'finance_vendor_bill_not_approved: bill % is % not approved', p_bill_id, v_bill.status
      using errcode = 'check_violation';
  end if;

  select * into v_period from app.resolve_finance_period_for_date(v_bill.tenant_id, v_bill.company_id, v_bill.bill_date);
  if not found then
    raise exception 'finance_vendor_bill_period_not_found: no fiscal period covers %', v_bill.bill_date
      using errcode = 'no_data_found';
  end if;
  if not v_period.posting_eligible then
    raise exception 'finance_vendor_bill_period_not_open: fiscal period % for % is not open', v_period.period_code, v_bill.bill_date
      using errcode = 'check_violation';
  end if;

  v_year := extract(year from v_bill.bill_date)::integer;
  insert into app.finance_vendor_bill_number_counters (tenant_id, company_id, year, next_seq)
  values (v_bill.tenant_id, v_bill.company_id, v_year, 2)
  on conflict (tenant_id, coalesce(company_id, '00000000-0000-0000-0000-000000000000'::uuid), year)
  do update set next_seq = app.finance_vendor_bill_number_counters.next_seq + 1
  returning next_seq - 1 into v_seq;
  v_number := 'BILL-' || v_year::text || '-' || lpad(v_seq::text, 6, '0');

  select * into v_ap_item from app.post_finance_ap_open_item(
    v_bill.tenant_id, v_bill.company_id, v_bill.vendor_master_id, 'vendor_bill', v_bill.id,
    v_bill.currency, v_bill.total_amount, v_bill.bill_date, v_bill.due_date, p_actor_auth_user_id, p_actor_label
  );

  -- FIN-202: debit expense for the subtotal; debit each tax line's own
  -- governed recoverable account (or the input_tax_default posting-map key
  -- when none is configured); credit AP control for the full total.
  v_lines := '[]'::jsonb;
  if v_bill.subtotal_amount > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('postingMapKey', 'expense_default', 'direction', 'debit', 'amount', v_bill.subtotal_amount));
  end if;
  for v_tax_line in select * from app.finance_vendor_bill_lines where bill_id = p_bill_id and line_type = 'tax' and amount > 0 loop
    v_tax_rule := null;
    if v_tax_line.tax_rule_version_id is not null then
      select * into v_tax_rule from app.finance_tax_rule_versions where id = v_tax_line.tax_rule_version_id and recoverable_account_id is not null;
    end if;
    if v_tax_rule is not null then
      v_lines := v_lines || jsonb_build_array(jsonb_build_object('accountId', v_tax_rule.recoverable_account_id, 'direction', 'debit', 'amount', v_tax_line.amount));
    else
      v_lines := v_lines || jsonb_build_array(jsonb_build_object('postingMapKey', 'input_tax_default', 'direction', 'debit', 'amount', v_tax_line.amount));
    end if;
  end loop;
  v_lines := v_lines || jsonb_build_array(jsonb_build_object('postingMapKey', 'ap_control', 'direction', 'credit', 'amount', v_bill.total_amount, 'openItemType', 'ap_open_item', 'openItemId', v_ap_item.id));

  perform app.post_finance_subledger_batch(
    v_bill.tenant_id, v_bill.company_id, 'vendor_bill', v_bill.id, v_bill.bill_date, v_bill.currency,
    v_lines, p_actor_auth_user_id, p_actor_label
  );

  update app.finance_vendor_bills
    set status = 'posted', bill_number = v_number, posting_period_id = v_period.period_id, ap_open_item_id = v_ap_item.id,
        posted_by = p_actor_label, posted_at = now()
    where id = p_bill_id
    returning * into v_bill;

  perform app.capture_audit_event(
    v_bill.tenant_id, p_actor_auth_user_id, p_actor_label, 'post_finance_vendor_bill',
    'app.finance_vendor_bills', v_bill.id, 'success', null, null, to_jsonb(v_bill)
  );

  return v_bill;
end;
$function$;

-- app.publish_finance_config_version -- live definition from 20260831270000_wire_ip_allowlist_into_sec_configure_fin_approve_hrs_approve.sql
create or replace function app.publish_finance_config_version(p_version_id uuid, p_actor_auth_user_id uuid, p_effective_from timestamp with time zone, p_actor_label text, p_client_ip text default null)
 RETURNS app.config_versions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_version app.config_versions;
  v_object app.config_objects;
  v_item record;
  v_ref text;
  v_account app.finance_accounts;
begin
  select * into v_version from app.config_versions where id = p_version_id;
  if not found then
    raise exception 'config_version_not_found: no config version %', p_version_id
      using errcode = 'no_data_found';
  end if;
  select * into v_object from app.config_objects where id = v_version.config_object_id;
  if not app.has_active_tenant_membership(v_object.tenant_id, p_actor_auth_user_id) then
    raise exception 'config_version_not_found: no config version %', p_version_id
      using errcode = 'no_data_found';
  end if;

  if not app.is_finance_config_type(v_object.config_type_code) then
    raise exception 'not_finance_config_type: % is not a Finance Configuration class', v_object.config_type_code
      using errcode = 'check_violation';
  end if;
  if not app.check_finance_config_authority('Approve', v_object.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_object.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_object.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_object.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  perform app.validate_finance_config_version(p_version_id, v_object.config_type_code);

  -- FIN-192 addition: a finance_posting_map publish now also requires every
  -- referenced account code to resolve to an active, postable account in this
  -- tenant -- Prompt 191 section 25 / Prompt 192's own closed forward reference.
  if v_object.config_type_code = 'finance_posting_map' then
    for v_item in select key, value from app.config_items where config_version_id = p_version_id loop
      v_ref := v_item.value ->> 'accountCodeRef';
      select * into v_account from app.finance_accounts
        where tenant_id = v_object.tenant_id and code = v_ref
          and company_id is not distinct from case when v_object.scope_level = 'company' then v_object.scope_id else null end;
      if not found then
        raise exception 'finance_posting_map_unresolved_account: posting map key % references account code % which does not exist in this tenant''s chart of accounts', v_item.key, v_ref
          using errcode = 'check_violation';
      end if;
      if v_account.status <> 'active' then
        raise exception 'finance_posting_map_inactive_account: posting map key % references account code % which is not active (status=%)', v_item.key, v_ref, v_account.status
          using errcode = 'check_violation';
      end if;
      if not v_account.is_postable then
        raise exception 'finance_posting_map_not_postable_account: posting map key % references account code % which is not postable (control account)', v_item.key, v_ref
          using errcode = 'check_violation';
      end if;
    end loop;
  end if;

  return app.publish_config_version(p_version_id, p_actor_auth_user_id, p_effective_from, p_actor_label);
end;
$function$;

-- app.release_finance_ap_hold -- live definition from 20260831270000_wire_ip_allowlist_into_sec_configure_fin_approve_hrs_approve.sql
create or replace function app.release_finance_ap_hold(p_open_item_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_ap_open_items
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_item app.finance_ap_open_items;
begin
  select * into v_item from app.finance_ap_open_items where id = p_open_item_id for update;
  if not found or not app.has_active_tenant_membership(v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_ap_open_item_not_found: %', p_open_item_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_ap_authority('Approve', v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_item.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_item.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
  if v_item.record_version <> p_expected_version then
    raise exception 'stale_version: open item % expected version % but found %', p_open_item_id, p_expected_version, v_item.record_version
      using errcode = 'serialization_failure';
  end if;
  if not v_item.is_held then
    raise exception 'finance_ap_not_held: open item % is not currently held', p_open_item_id
      using errcode = 'check_violation';
  end if;

  update app.finance_ap_open_items
    set is_held = false, released_by = p_actor_label, released_at = now()
    where id = p_open_item_id
    returning * into v_item;

  insert into app.finance_ap_open_item_events (tenant_id, open_item_id, event_type, reason, actor_auth_user_id, actor_label)
  values (v_item.tenant_id, v_item.id, 'hold_released', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'release_finance_ap_hold',
    'app.finance_ap_open_items', v_item.id, 'success', p_reason, null, to_jsonb(v_item)
  );

  return v_item;
end;
$function$;

-- app.release_finance_ar_hold -- live definition from 20260831270000_wire_ip_allowlist_into_sec_configure_fin_approve_hrs_approve.sql
create or replace function app.release_finance_ar_hold(p_open_item_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_ar_open_items
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_item app.finance_ar_open_items;
begin
  select * into v_item from app.finance_ar_open_items where id = p_open_item_id for update;
  if not found or not app.has_active_tenant_membership(v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_ar_open_item_not_found: %', p_open_item_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_ar_authority('Approve', v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_item.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_item.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
  if v_item.record_version <> p_expected_version then
    raise exception 'stale_version: open item % expected version % but found %', p_open_item_id, p_expected_version, v_item.record_version
      using errcode = 'serialization_failure';
  end if;
  if not v_item.is_held then
    raise exception 'finance_ar_not_held: open item % is not currently held', p_open_item_id
      using errcode = 'check_violation';
  end if;

  update app.finance_ar_open_items
    set is_held = false, released_by = p_actor_label, released_at = now()
    where id = p_open_item_id
    returning * into v_item;

  insert into app.finance_ar_open_item_events (tenant_id, open_item_id, event_type, reason, actor_auth_user_id, actor_label)
  values (v_item.tenant_id, v_item.id, 'hold_released', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'release_finance_ar_hold',
    'app.finance_ar_open_items', v_item.id, 'success', p_reason, null, to_jsonb(v_item)
  );

  return v_item;
end;
$function$;

-- app.relock_finance_period -- live definition from 20260831270000_wire_ip_allowlist_into_sec_configure_fin_approve_hrs_approve.sql
create or replace function app.relock_finance_period(p_lock_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_period_locks
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_lock app.finance_period_locks;
begin
  select * into v_lock from app.finance_period_locks where id = p_lock_id for update;
  if not found or not app.has_active_tenant_membership(v_lock.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_period_lock_not_found: %', p_lock_id using errcode = 'no_data_found';
  end if;
  if v_lock.status = 'locked' then
    return v_lock;
  end if;
  if not app.check_finance_period_lock_authority('Approve', v_lock.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_lock.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_lock.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_lock.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
  if v_lock.record_version <> p_expected_version then
    raise exception 'stale_version: lock % expected version % but found %', p_lock_id, p_expected_version, v_lock.record_version
      using errcode = 'serialization_failure';
  end if;

  update app.finance_period_locks
    set status = 'locked', relocked_by = p_actor_label, relocked_at = now()
    where id = p_lock_id
    returning * into v_lock;

  insert into app.finance_period_lock_events (lock_id, tenant_id, action, reason, actor_label) values (v_lock.id, v_lock.tenant_id, 'relocked', null, p_actor_label);

  perform app.capture_audit_event(
    v_lock.tenant_id, p_actor_auth_user_id, p_actor_label, 'relock_finance_period',
    'app.finance_period_locks', v_lock.id, 'success', null, null, to_jsonb(v_lock)
  );

  return v_lock;
end;
$function$;

-- app.reopen_finance_period -- live definition from 20260831270000_wire_ip_allowlist_into_sec_configure_fin_approve_hrs_approve.sql
create or replace function app.reopen_finance_period(p_period_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_fiscal_periods
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_period app.finance_fiscal_periods;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_period_reopen_reason_required: a non-empty reason is required'
      using errcode = 'check_violation';
  end if;

  select * into v_period from app.finance_fiscal_periods where id = p_period_id;
  if not found or not app.has_active_tenant_membership(v_period.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_period_not_found: %', p_period_id using errcode = 'no_data_found';
  end if;

  if v_period.record_version <> p_expected_version then
    raise exception 'stale_version: period % expected version % but found %', p_period_id, p_expected_version, v_period.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_period.status <> 'closed' then
    raise exception 'finance_period_not_closed: period % is %, only a closed period may be reopened', p_period_id, v_period.status
      using errcode = 'check_violation';
  end if;

  if not app.check_finance_period_authority('Approve', v_period.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_period.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_period.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_period.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  update app.finance_fiscal_periods
  set status = 'open', closed_at = null, closed_by = null
  where id = p_period_id and record_version = p_expected_version
  returning * into v_period;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: reopen_finance_period target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.finance_period_transitions (period_id, tenant_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (p_period_id, v_period.tenant_id, 'closed', 'open', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_period.tenant_id, p_actor_auth_user_id, p_actor_label, 'reopen_finance_period',
    'app.finance_fiscal_periods', v_period.id, 'success', p_reason, null, to_jsonb(v_period)
  );

  return v_period;
end;
$function$;

-- app.request_finance_receipt_deallocation -- live definition from 20260831270000_wire_ip_allowlist_into_sec_configure_fin_approve_hrs_approve.sql
create or replace function app.request_finance_receipt_deallocation(p_allocation_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_receipts
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_allocation app.finance_receipt_allocations;
  v_receipt app.finance_receipts;
begin
  select * into v_allocation from app.finance_receipt_allocations where id = p_allocation_id for update;
  if not found or not app.has_active_tenant_membership(v_allocation.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_receipt_allocation_not_found: %', p_allocation_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_receipt_authority('Approve', v_allocation.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_allocation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_allocation.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_allocation.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_receipt_deallocation_reason_required: a non-empty reason is required to reverse an allocation'
      using errcode = 'check_violation';
  end if;
  if v_allocation.status <> 'applied' then
    raise exception 'finance_receipt_allocation_not_applied: allocation % is % not applied', p_allocation_id, v_allocation.status
      using errcode = 'check_violation';
  end if;

  perform app.reverse_finance_ar_allocation(
    v_allocation.ar_open_item_id, v_allocation.amount, p_reason, 'receipt', v_allocation.receipt_id,
    'dealloc:' || v_allocation.id::text, p_actor_auth_user_id, p_actor_label
  );

  update app.finance_receipt_allocations set status = 'reversed', reason = p_reason, reversed_by = p_actor_label, reversed_at = now() where id = p_allocation_id;

  update app.finance_receipts set allocated_amount = allocated_amount - v_allocation.amount where id = v_allocation.receipt_id returning * into v_receipt;

  perform app.capture_audit_event(
    v_allocation.tenant_id, p_actor_auth_user_id, p_actor_label, 'request_finance_receipt_deallocation',
    'app.finance_receipt_allocations', v_allocation.id, 'success', p_reason, null, jsonb_build_object('amount', v_allocation.amount)
  );

  return v_receipt;
end;
$function$;

-- app.request_finance_settlement_reversal -- live definition from 20260831270000_wire_ip_allowlist_into_sec_configure_fin_approve_hrs_approve.sql
create or replace function app.request_finance_settlement_reversal(p_settlement_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_settlements
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_settlement app.finance_settlements;
  v_allocation app.finance_settlement_allocations;
  v_period record;
  v_batch app.finance_subledger_batches;
  v_original_journal app.finance_journals;
  v_reversal_lines jsonb := '[]'::jsonb;
  v_line record;
  v_flipped text;
  v_correction app.finance_journal_corrections;
  v_reversal_journal app.finance_journals;
begin
  select * into v_settlement from app.finance_settlements where id = p_settlement_id for update;
  if not found or not app.has_active_tenant_membership(v_settlement.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_settlement_not_found: %', p_settlement_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_settlement_authority('Approve', v_settlement.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_settlement.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_settlement.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_settlement.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_settlement_reversal_reason_required: a non-empty reason is required to reverse a posted settlement'
      using errcode = 'check_violation';
  end if;
  if v_settlement.status <> 'posted' then
    raise exception 'finance_settlement_not_posted: settlement % is % not posted', p_settlement_id, v_settlement.status
      using errcode = 'check_violation';
  end if;

  select * into v_period from app.resolve_finance_period_for_date(v_settlement.tenant_id, v_settlement.company_id, v_settlement.settlement_date);
  if not found then
    raise exception 'finance_settlement_reversal_period_not_found: no fiscal period covers %', v_settlement.settlement_date
      using errcode = 'no_data_found';
  end if;
  if not v_period.posting_eligible then
    raise exception 'finance_settlement_reversal_period_not_open: fiscal period % for % is not open', v_period.period_code, v_settlement.settlement_date
      using errcode = 'check_violation';
  end if;

  select * into v_batch from app.finance_subledger_batches where tenant_id = v_settlement.tenant_id and source_type = 'settlement' and source_id = v_settlement.id;
  if not found or v_batch.gl_journal_id is null then
    raise exception 'finance_settlement_reversal_batch_not_found: settlement % has no posted subledger batch/GL journal to reverse -- data integrity anomaly', p_settlement_id
      using errcode = 'no_data_found';
  end if;
  select * into v_original_journal from app.finance_journals where id = v_batch.gl_journal_id;
  if not found or v_original_journal.status <> 'posted' then
    raise exception 'finance_settlement_reversal_journal_not_posted: journal % for settlement % is not posted', v_batch.gl_journal_id, p_settlement_id
      using errcode = 'check_violation';
  end if;

  for v_line in select direction, account_id, amount, dimension from app.finance_journal_lines where journal_id = v_original_journal.id order by line_number asc loop
    v_flipped := case when v_line.direction = 'debit' then 'credit' else 'debit' end;
    v_reversal_lines := v_reversal_lines || jsonb_build_array(jsonb_build_object('accountId', v_line.account_id, 'direction', v_flipped, 'amount', v_line.amount, 'dimension', v_line.dimension));
  end loop;

  insert into app.finance_journal_corrections (
    tenant_id, company_id, original_journal_id, correction_type, correction_date, reason, evidence_ref, adjustment_lines,
    status, idempotency_key, submitted_by, submitted_at, approved_by, approved_at, created_by
  )
  values (
    v_settlement.tenant_id, v_settlement.company_id, v_original_journal.id, 'reversal', v_settlement.settlement_date, p_reason, null, null,
    'approved', 'settlement_reversal:' || v_settlement.id::text, p_actor_label, now(), p_actor_label, now(), p_actor_label
  )
  returning * into v_correction;

  select * into v_reversal_journal from app.create_and_post_finance_system_journal(
    v_settlement.tenant_id, v_settlement.company_id, 'correction', v_correction.id, v_settlement.settlement_date,
    v_original_journal.currency, v_reversal_lines, p_actor_auth_user_id, p_actor_label, 'ap'
  );

  update app.finance_journal_corrections
    set status = 'posted', correction_journal_id = v_reversal_journal.id, posted_by = p_actor_label, posted_at = now()
    where id = v_correction.id
    returning * into v_correction;

  update app.finance_subledger_batches set status = 'reversed' where id = v_batch.id and status = 'posted';

  perform app.capture_audit_event(
    v_settlement.tenant_id, p_actor_auth_user_id, p_actor_label, 'post_finance_correction',
    'app.finance_journal_corrections', v_correction.id, 'success', p_reason, null, to_jsonb(v_correction)
  );

  for v_allocation in select * from app.finance_settlement_allocations where settlement_id = p_settlement_id and status = 'applied' order by created_at asc loop
    perform app.reverse_finance_ap_settlement(
      v_allocation.ap_open_item_id, v_allocation.amount, p_reason, 'settlement', v_settlement.id,
      'reversal:' || v_settlement.id::text || ':' || v_allocation.ap_open_item_id::text, p_actor_auth_user_id, p_actor_label
    );
    update app.finance_settlement_allocations set status = 'reversed', reason = p_reason, reversed_by = p_actor_label, reversed_at = now() where id = v_allocation.id;
  end loop;

  update app.finance_settlements set status = 'reversed', void_reason = p_reason, voided_by = p_actor_label, voided_at = now() where id = p_settlement_id returning * into v_settlement;

  perform app.capture_audit_event(
    v_settlement.tenant_id, p_actor_auth_user_id, p_actor_label, 'request_finance_settlement_reversal',
    'app.finance_settlements', v_settlement.id, 'success', p_reason, null, to_jsonb(v_settlement)
  );

  return v_settlement;
end;
$function$;

-- app.reverse_finance_ap_settlement -- live definition from 20260831270000_wire_ip_allowlist_into_sec_configure_fin_approve_hrs_approve.sql
create or replace function app.reverse_finance_ap_settlement(p_open_item_id uuid, p_amount numeric, p_reason text, p_source_type text, p_source_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_ap_open_items
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_item app.finance_ap_open_items;
  v_existing_event app.finance_ap_open_item_events;
  v_new_settled numeric;
  v_new_status text;
begin
  select * into v_item from app.finance_ap_open_items where id = p_open_item_id for update;
  if not found or not app.has_active_tenant_membership(v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_ap_open_item_not_found: %', p_open_item_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_ap_authority('Approve', v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_item.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_item.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  if p_idempotency_key is not null then
    select * into v_existing_event from app.finance_ap_open_item_events
      where tenant_id = v_item.tenant_id and open_item_id = p_open_item_id and idempotency_key = p_idempotency_key;
    if found then
      -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
      -- conflict, never a replay. Returning the earlier target's row here silently
      -- misattributed this request to it (or silently discarded it entirely).
      if v_existing_event.event_type is distinct from 'unsettled' then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different AP open-item event (event type %, not unsettled)', p_idempotency_key, v_existing_event.event_type
          using errcode = 'unique_violation';
      end if;
      return v_item;
    end if;
  end if;

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_ap_unsettlement_reason_required: a non-empty reason is required to reverse a settlement'
      using errcode = 'check_violation';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'finance_ap_invalid_settlement_amount: reversal amount must be positive, got %', p_amount
      using errcode = 'check_violation';
  end if;
  if p_amount > v_item.settled_amount then
    raise exception 'finance_ap_over_reversal: reversal % exceeds settled amount % for open item %', p_amount, v_item.settled_amount, p_open_item_id
      using errcode = 'check_violation';
  end if;

  v_new_settled := v_item.settled_amount - p_amount;
  v_new_status := case when v_new_settled >= v_item.original_amount then 'settled' when v_new_settled > 0 then 'partial' else 'open' end;

  update app.finance_ap_open_items
    set settled_amount = v_new_settled, status = v_new_status
    where id = p_open_item_id
    returning * into v_item;

  insert into app.finance_ap_open_item_events (tenant_id, open_item_id, event_type, amount_delta, reason, source_type, source_id, idempotency_key, actor_auth_user_id, actor_label)
  values (v_item.tenant_id, v_item.id, 'unsettled', -p_amount, p_reason, p_source_type, p_source_id, p_idempotency_key, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'reverse_finance_ap_settlement',
    'app.finance_ap_open_items', v_item.id, 'success', p_reason, null, jsonb_build_object('amount', p_amount, 'newStatus', v_new_status)
  );

  return v_item;
end;
$function$;

-- app.reverse_finance_ar_allocation -- live definition from 20260831270000_wire_ip_allowlist_into_sec_configure_fin_approve_hrs_approve.sql
create or replace function app.reverse_finance_ar_allocation(p_open_item_id uuid, p_amount numeric, p_reason text, p_source_type text, p_source_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_ar_open_items
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_item app.finance_ar_open_items;
  v_existing_event app.finance_ar_open_item_events;
  v_new_allocated numeric;
  v_new_status text;
begin
  select * into v_item from app.finance_ar_open_items where id = p_open_item_id for update;
  if not found or not app.has_active_tenant_membership(v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_ar_open_item_not_found: %', p_open_item_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_ar_authority('Approve', v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_item.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_item.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  if p_idempotency_key is not null then
    select * into v_existing_event from app.finance_ar_open_item_events
      where tenant_id = v_item.tenant_id and open_item_id = p_open_item_id and idempotency_key = p_idempotency_key;
    if found then
      -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
      -- conflict, never a replay. Returning the earlier target's row here silently
      -- misattributed this request to it (or silently discarded it entirely).
      if v_existing_event.event_type is distinct from 'deallocated' then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different AR open-item event (event type %, not deallocated)', p_idempotency_key, v_existing_event.event_type
          using errcode = 'unique_violation';
      end if;
      return v_item;
    end if;
  end if;

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_ar_deallocation_reason_required: a non-empty reason is required to reverse an allocation'
      using errcode = 'check_violation';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'finance_ar_invalid_allocation_amount: reversal amount must be positive, got %', p_amount
      using errcode = 'check_violation';
  end if;
  if p_amount > v_item.allocated_amount then
    raise exception 'finance_ar_over_reversal: reversal % exceeds allocated amount % for open item %', p_amount, v_item.allocated_amount, p_open_item_id
      using errcode = 'check_violation';
  end if;

  v_new_allocated := v_item.allocated_amount - p_amount;
  v_new_status := case when v_new_allocated >= v_item.original_amount then 'paid' when v_new_allocated > 0 then 'partial' else 'open' end;

  update app.finance_ar_open_items
    set allocated_amount = v_new_allocated, status = v_new_status
    where id = p_open_item_id
    returning * into v_item;

  insert into app.finance_ar_open_item_events (tenant_id, open_item_id, event_type, amount_delta, reason, source_type, source_id, idempotency_key, actor_auth_user_id, actor_label)
  values (v_item.tenant_id, v_item.id, 'deallocated', -p_amount, p_reason, p_source_type, p_source_id, p_idempotency_key, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'reverse_finance_ar_allocation',
    'app.finance_ar_open_items', v_item.id, 'success', p_reason, null, jsonb_build_object('amount', p_amount, 'newStatus', v_new_status)
  );

  return v_item;
end;
$function$;

-- app.revoke_ip_allowlist_entry -- live definition from 20260831270000_wire_ip_allowlist_into_sec_configure_fin_approve_hrs_approve.sql
create or replace function app.revoke_ip_allowlist_entry(p_entry_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.ip_allowlist_entries
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_entry app.ip_allowlist_entries;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_entry from app.ip_allowlist_entries where id = p_entry_id and status = 'active' for update;
  if not found or not app.has_active_tenant_membership(v_entry.tenant_id, p_actor_auth_user_id) then
    raise exception 'ip_allowlist_entry_not_active: % is not an active entry', p_entry_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_entry.tenant_id, 'SEC', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks SEC:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_entry.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_entry.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_entry.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  update app.ip_allowlist_entries
  set status = 'revoked', revoked_at = now(), revoked_by = p_actor_label
  where id = p_entry_id
  returning * into v_entry;

  perform app.capture_audit_event(
    v_entry.tenant_id, p_actor_auth_user_id, p_actor_label, 'revoke_ip_allowlist_entry',
    'app.ip_allowlist_entries', v_entry.id, 'success', null, null, to_jsonb(v_entry)
  );

  return v_entry;
end;
$function$;

-- app.rollback_finance_config_version -- live definition from 20260831270000_wire_ip_allowlist_into_sec_configure_fin_approve_hrs_approve.sql
create or replace function app.rollback_finance_config_version(p_target_version_id uuid, p_actor_auth_user_id uuid, p_reason text, p_actor_label text, p_client_ip text default null)
 RETURNS app.config_versions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_target app.config_versions;
  v_object app.config_objects;
begin
  select * into v_target from app.config_versions where id = p_target_version_id;
  if not found then
    raise exception 'config_version_not_found: no config version %', p_target_version_id
      using errcode = 'no_data_found';
  end if;
  select * into v_object from app.config_objects where id = v_target.config_object_id;
  if not app.has_active_tenant_membership(v_object.tenant_id, p_actor_auth_user_id) then
    raise exception 'config_version_not_found: no config version %', p_target_version_id
      using errcode = 'no_data_found';
  end if;

  if not app.is_finance_config_type(v_object.config_type_code) then
    raise exception 'not_finance_config_type: % is not a Finance Configuration class', v_object.config_type_code
      using errcode = 'check_violation';
  end if;
  if not app.check_finance_config_authority('Approve', v_object.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_object.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_object.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_object.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  return app.rollback_config_version(p_target_version_id, p_actor_auth_user_id, p_reason, p_actor_label);
end;
$function$;

-- app.unmatch_finance_bank_transaction -- live definition from 20260831270000_wire_ip_allowlist_into_sec_configure_fin_approve_hrs_approve.sql
create or replace function app.unmatch_finance_bank_transaction(p_transaction_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_bank_transactions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_transaction app.finance_bank_transactions;
begin
  select * into v_transaction from app.finance_bank_transactions where id = p_transaction_id for update;
  if not found or not app.has_active_tenant_membership(v_transaction.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_cash_transaction_not_found: %', p_transaction_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_cash_authority('Approve', v_transaction.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_transaction.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_transaction.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_transaction.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
  if v_transaction.record_version <> p_expected_version then
    raise exception 'stale_version: transaction % expected version % but found %', p_transaction_id, p_expected_version, v_transaction.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_cash_unmatch_reason_required: a non-empty reason is required' using errcode = 'check_violation';
  end if;
  if v_transaction.match_status <> 'matched' then
    raise exception 'finance_cash_transaction_not_matched: transaction % is % not matched', p_transaction_id, v_transaction.match_status
      using errcode = 'check_violation';
  end if;

  update app.finance_bank_transactions
    set match_status = 'unmatched', matched_source_type = null, matched_source_id = null, matched_by = null, matched_at = null, unmatch_reason = p_reason
    where id = p_transaction_id
    returning * into v_transaction;

  perform app.capture_audit_event(
    v_transaction.tenant_id, p_actor_auth_user_id, p_actor_label, 'unmatch_finance_bank_transaction',
    'app.finance_bank_transactions', v_transaction.id, 'success', p_reason, null, to_jsonb(v_transaction)
  );

  return v_transaction;
end;
$function$;
