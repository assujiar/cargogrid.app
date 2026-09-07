-- CG-AUDIT-2026-09-02 B8 (independent launch-readiness audit, finding B8): every finance
-- write RPC that accepts a caller-supplied p_company_id writes it straight onto the new
-- row with no check that it is even a real org_units row for the caller's OWN tenant, let
-- alone a company-typed one. A caller holding valid FIN:* authority for their own tenant
-- could therefore post finance data (journals, AP/AR open items, settlements, receipts,
-- bank accounts, reconciliation runs, fiscal calendars, accounts) tagged with a
-- company_id belonging to a DIFFERENT tenant, or to a non-company org unit (a branch,
-- department, business_unit, or team) -- a tenant-isolation and data-integrity gap the
-- audit found across all company_id-accepting finance write functions.
--
-- Fix: one shared precondition, app.assert_finance_company_org_unit(p_tenant_id,
-- p_company_id), mirroring app.enforce_employee_org_unit_shape's own established
-- tenant-scope + unit_type check for org_unit foreign keys elsewhere in the schema. It is
-- a no-op when p_company_id is null -- company scoping is optional on every affected
-- function (company_id is a nullable column on every one of their target tables) -- and
-- otherwise raises unless the id resolves to an app.org_units row that both belongs to
-- p_tenant_id and has unit_type = 'company'. Deliberately does NOT also require
-- status = 'active': unlike an employee's current org assignment (where an inactive unit
-- is a live process to prevent), several of these functions post HISTORICAL finance data
-- (app.import_historical_finance_journal explicitly bypasses its own period's
-- posting_eligible check for the identical reason) against a company that may since have
-- been deactivated, and the audit's own finding is scoped to tenant isolation /
-- unit-type correctness, not company lifecycle state.
--
-- Called with `perform` immediately after each function's own existing authority (and,
-- where present, IP-allowlist) checks and before any other business-logic validation --
-- the same ordering app.enforce_employee_org_unit_shape's callers already use, and the
-- ordering every other check in these functions already follows: never let an
-- unauthorized caller learn anything about another tenant's data (existence of a
-- company id, its precise unit_type) before their own authority is established.
--
-- Every affected function below is otherwise a byte-for-byte `create or replace` of its
-- current, already-applied body (each one's own preceding migration remains the historical
-- record of prior changes) -- the one new `perform app.assert_finance_company_org_unit(...)`
-- line is the only change in each.
--
-- app.assert_finance_company_org_unit is SECURITY INVOKER (the plpgsql default, no
-- `security definer` clause) and left with no explicit grant, mirroring
-- app.assert_vendor_profile_editable's own established shape for a shared
-- precondition helper: called only from the SECURITY DEFINER functions below, it executes
-- with each caller's already-elevated, already-pinned-search_path privilege, and needs no
-- EXECUTE grant of its own (schema `app` carries no default-privilege auto-grant to
-- anon/authenticated/service_role the way `public` does) -- so it requires no
-- public.* wrapper under scripts/db-tests/public-api-wrapper-regression.sql's own
-- externally-callable criterion.

create function app.assert_finance_company_org_unit(p_tenant_id uuid, p_company_id uuid)
returns void
language plpgsql
as $$
declare
  v_company app.org_units;
begin
  if p_company_id is null then
    return;
  end if;

  select * into v_company from app.org_units where id = p_company_id;
  if not found or v_company.tenant_id <> p_tenant_id then
    raise exception 'finance_company_not_found: company_id % is not a valid org unit for tenant %', p_company_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;
  if v_company.unit_type <> 'company' then
    raise exception 'finance_company_invalid_org_unit_type: company_id % is a %, expected company', p_company_id, v_company.unit_type
      using errcode = 'check_violation';
  end if;
end;
$$;

comment on function app.assert_finance_company_org_unit is 'CG-AUDIT-2026-09-02 B8: shared tenant-scope + unit_type precondition for every finance write RPC that accepts a caller-supplied p_company_id, mirroring app.enforce_employee_org_unit_shape''s own tenant-scope + unit_type checks for org_unit foreign keys. Without this, a caller could write a finance row whose company_id points at another tenant''s org_units row (or a non-company unit_type) -- an audit-identified tenant-isolation gap. A null p_company_id is a no-op -- company scoping is optional on these functions (company_id is a nullable column on every affected table). Deliberately does not also require status=''active'' -- several callers post historical finance data against a company that may since have been deactivated, and this precondition''s scope is tenant isolation and type correctness, not company lifecycle state. Not itself callable by anyone but the SECURITY DEFINER functions that call it (SECURITY INVOKER, executes with the definer caller''s already-elevated privilege) -- unlike app.has_active_tenant_membership/app.has_active_identity_link, it is never referenced from an RLS policy or called directly, so (mirroring app.assert_vendor_profile_editable''s own identical shape) every role''s default EXECUTE grant is revoked below rather than exposed through a public.* wrapper.';

-- Schema `app` carries a default-privilege auto-grant of EXECUTE to
-- anon/authenticated/service_role on newly created functions (unlike
-- app.assert_vendor_profile_editable, created before that default-privilege rule existed).
-- Revoked here because this precondition is never called from an RLS policy and never
-- invoked directly -- only from within the SECURITY DEFINER function bodies below -- so it
-- needs no role's EXECUTE grant and, per
-- scripts/db-tests/public-api-wrapper-regression.sql's own externally-callable
-- criterion, no public.* wrapper.
revoke execute on function app.assert_finance_company_org_unit(uuid, uuid) from anon, authenticated, service_role, public;

create or replace function app.create_finance_journal_draft(p_tenant_id uuid, p_company_id uuid, p_journal_date date, p_currency text, p_lines jsonb, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 returns app.finance_journals
 language plpgsql
 security definer
 set search_path to 'app', 'pg_temp'
as $function$
declare
  v_journal app.finance_journals;
  v_line jsonb;
  v_account app.finance_accounts;
  v_total numeric(14, 2);
  v_line_number integer := 0;
  v_fingerprint text;
  v_claim app.finance_idempotency_claims;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_journal_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  perform app.assert_finance_company_org_unit(p_tenant_id, p_company_id);
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: a non-empty idempotency_key is required' using errcode = 'check_violation';
  end if;
  if not app.validate_currency_code(p_currency) then
    raise exception 'finance_journal_unsupported_currency: % is not a registered, active currency', p_currency
      using errcode = 'check_violation';
  end if;

  v_fingerprint := md5(jsonb_build_object('companyId', p_company_id, 'journalDate', p_journal_date, 'currency', p_currency, 'lines', p_lines)::text);
  v_claim := app.claim_finance_idempotency_key(p_tenant_id, 'journal', p_idempotency_key, v_fingerprint, p_actor_auth_user_id, p_actor_label);

  if v_claim.status = 'completed' then
    select * into v_journal from app.finance_journals where id = v_claim.result_entity_id;
    return v_journal;
  end if;

  v_total := app.validate_finance_journal_line_balance(p_lines);

  for v_line in select * from jsonb_array_elements(p_lines) loop
    select * into v_account from app.finance_accounts where id = (v_line ->> 'accountId')::uuid and tenant_id = p_tenant_id;
    if not found then
      raise exception 'finance_journal_account_not_found: % is not a known account for tenant %', v_line ->> 'accountId', p_tenant_id
        using errcode = 'no_data_found';
    end if;
    if v_account.status <> 'active' then
      raise exception 'finance_journal_inactive_account: account % is not active (status=%)', v_account.code, v_account.status
        using errcode = 'check_violation';
    end if;
    if not v_account.is_postable then
      raise exception 'finance_journal_not_postable_account: account % is not postable (control account)', v_account.code
        using errcode = 'check_violation';
    end if;
  end loop;

  insert into app.finance_journals (tenant_id, company_id, source_type, currency, total_amount, journal_date, idempotency_key, created_by)
  values (p_tenant_id, p_company_id, 'manual', p_currency, v_total, p_journal_date, p_idempotency_key, p_actor_label)
  returning * into v_journal;

  for v_line in select * from jsonb_array_elements(p_lines) loop
    v_line_number := v_line_number + 1;
    insert into app.finance_journal_lines (journal_id, tenant_id, line_number, account_id, dimension, direction, amount, description)
    values (
      v_journal.id, p_tenant_id, v_line_number, (v_line ->> 'accountId')::uuid, v_line -> 'dimension',
      v_line ->> 'direction', (v_line ->> 'amount')::numeric, v_line ->> 'description'
    );
  end loop;

  perform app.complete_finance_idempotency_claim(v_claim.id, 'journal', v_journal.id, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_finance_journal_draft',
    'app.finance_journals', v_journal.id, 'success', null, null, to_jsonb(v_journal)
  );

  return v_journal;
end;
$function$;

create or replace function app.lock_finance_period(p_tenant_id uuid, p_company_id uuid, p_period_id uuid, p_lock_scope text, p_reason text, p_evidence_ref text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text DEFAULT NULL::text)
 returns app.finance_period_locks
 language plpgsql
 security definer
 set search_path to 'app', 'pg_temp'
as $function$
declare
  v_lock app.finance_period_locks;
  v_period app.finance_fiscal_periods;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_period_lock_authority('Approve', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(p_tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(p_tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
  perform app.assert_finance_company_org_unit(p_tenant_id, p_company_id);
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_period_lock_reason_required: a non-empty reason is required' using errcode = 'check_violation';
  end if;
  if p_lock_scope not in ('all', 'gl', 'ar', 'ap', 'tax') then
    raise exception 'finance_period_lock_invalid_scope: % is not a supported lock scope', p_lock_scope using errcode = 'check_violation';
  end if;

  select * into v_period from app.finance_fiscal_periods where id = p_period_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'finance_period_not_found: % is not a known fiscal period for tenant %', p_period_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;

  select * into v_lock from app.finance_period_locks
    where tenant_id = p_tenant_id and period_id = p_period_id and lock_scope = p_lock_scope
      and coalesce(company_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(p_company_id, '00000000-0000-0000-0000-000000000000'::uuid);

  if found and v_lock.status = 'locked' then
    return v_lock;
  end if;

  if found then
    update app.finance_period_locks
      set status = 'locked', lock_reason = p_reason, evidence_ref = p_evidence_ref, locked_by = p_actor_label, locked_at = now(),
          relocked_by = p_actor_label, relocked_at = now()
      where id = v_lock.id
      returning * into v_lock;
  else
    -- HDN-374 Tier C fix: a genuine race between the not-found check above and this insert
    -- (two concurrent first-time lock calls for the same tenant/period/scope) is resolved by
    -- re-selecting the now-existing row and applying the same locked-transition logic the
    -- ordinary "found" branch above already uses, rather than surfacing a raw unique_violation
    -- or silently discarding the loser's own genuine lock intent.
    begin
      insert into app.finance_period_locks (tenant_id, company_id, period_id, lock_scope, lock_reason, evidence_ref, locked_by, created_by)
      values (p_tenant_id, p_company_id, p_period_id, p_lock_scope, p_reason, p_evidence_ref, p_actor_label, p_actor_label)
      returning * into v_lock;
    exception
      when unique_violation then
        select * into v_lock from app.finance_period_locks
          where tenant_id = p_tenant_id and period_id = p_period_id and lock_scope = p_lock_scope
            and coalesce(company_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(p_company_id, '00000000-0000-0000-0000-000000000000'::uuid);
        if not found then
          raise;
        end if;
        if v_lock.status = 'locked' then
          return v_lock;
        end if;
        update app.finance_period_locks
          set status = 'locked', lock_reason = p_reason, evidence_ref = p_evidence_ref, locked_by = p_actor_label, locked_at = now(),
              relocked_by = p_actor_label, relocked_at = now()
          where id = v_lock.id
          returning * into v_lock;
    end;
  end if;

  insert into app.finance_period_lock_events (lock_id, tenant_id, action, reason, actor_label) values (v_lock.id, p_tenant_id, 'locked', p_reason, p_actor_label);

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'lock_finance_period',
    'app.finance_period_locks', v_lock.id, 'success', p_reason, null, to_jsonb(v_lock)
  );

  return v_lock;
end;
$function$;

create or replace function app.create_and_post_finance_system_journal(p_tenant_id uuid, p_company_id uuid, p_source_type text, p_source_id uuid, p_journal_date date, p_currency text, p_lines jsonb, p_actor_auth_user_id uuid, p_actor_label text, p_lock_scope text DEFAULT 'gl'::text)
 returns app.finance_journals
 language plpgsql
 security definer
 set search_path to 'app', 'pg_temp'
as $function$
declare
  v_journal app.finance_journals;
  v_line jsonb;
  v_line_number integer := 0;
  v_total numeric(14, 2);
  v_period record;
  v_year integer;
  v_seq integer;
  v_number text;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  -- HDN-373 Tier C fix: either level is a legitimate caller (app.post_finance_subledger_batch
  -- and app.allocate_finance_receipt both require only FIN:Edit at their own front door;
  -- app.post_finance_correction requires FIN:Approve, which this OR already admits).
  -- Still denies an actor holding neither -- ISS-2026-183's own original concern.
  if not (app.check_finance_journal_authority('Edit', p_tenant_id, p_actor_auth_user_id)
          or app.check_finance_journal_authority('Approve', p_tenant_id, p_actor_auth_user_id)) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit or FIN:Approve for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  perform app.assert_finance_company_org_unit(p_tenant_id, p_company_id);
  if p_source_type not in ('subledger', 'correction') then
    raise exception 'finance_journal_unsupported_source_type: % is not a supported system journal source type', p_source_type
      using errcode = 'check_violation';
  end if;

  select * into v_journal from app.finance_journals where tenant_id = p_tenant_id and source_type = p_source_type and source_id = p_source_id;
  if found then
    return v_journal;
  end if;

  v_total := app.validate_finance_journal_line_balance(p_lines);

  select * into v_period from app.resolve_finance_period_for_date(p_tenant_id, p_company_id, p_journal_date);
  if not found then
    raise exception 'finance_journal_period_not_found: no fiscal period covers %', p_journal_date
      using errcode = 'no_data_found';
  end if;
  if not v_period.posting_eligible then
    raise exception 'finance_journal_period_not_open: fiscal period % for % is not open', v_period.period_code, p_journal_date
      using errcode = 'check_violation';
  end if;
  perform app.assert_finance_period_open_for_posting(p_tenant_id, p_company_id, v_period.period_id, p_lock_scope);

  v_year := extract(year from p_journal_date)::integer;
  insert into app.finance_journal_number_counters (tenant_id, company_id, year, next_seq)
  values (p_tenant_id, p_company_id, v_year, 2)
  on conflict (tenant_id, coalesce(company_id, '00000000-0000-0000-0000-000000000000'::uuid), year)
  do update set next_seq = app.finance_journal_number_counters.next_seq + 1
  returning next_seq - 1 into v_seq;
  v_number := 'JRNL-' || v_year::text || '-' || lpad(v_seq::text, 6, '0');

  -- HDN-374 finding 3 (closes HDN-BLK-010's own required scope): a genuine race between
  -- the select above and this insert (two concurrent callers preparing the same
  -- source_type/source_id) is resolved by re-selecting and returning the winner.
  -- Backed by finance_journals_idempotency_unique.
  begin
    insert into app.finance_journals (
      tenant_id, company_id, journal_number, source_type, source_id, idempotency_key,
      currency, total_amount, journal_date, status, posting_period_id, posted_by, posted_at, created_by
    )
    values (
      p_tenant_id, p_company_id, v_number, p_source_type, p_source_id, p_source_type || ':' || p_source_id::text,
      p_currency, v_total, p_journal_date, 'posted', v_period.period_id, p_actor_label, now(), p_actor_label
    )
    returning * into v_journal;
  exception
    when unique_violation then
      select * into v_journal from app.finance_journals where tenant_id = p_tenant_id and source_type = p_source_type and source_id = p_source_id;
      if found then
        return v_journal;
      end if;
      raise;
  end;

  for v_line in select * from jsonb_array_elements(p_lines) loop
    v_line_number := v_line_number + 1;
    insert into app.finance_journal_lines (journal_id, tenant_id, line_number, account_id, dimension, direction, amount)
    values (v_journal.id, p_tenant_id, v_line_number, (v_line ->> 'accountId')::uuid, v_line -> 'dimension', v_line ->> 'direction', (v_line ->> 'amount')::numeric);
  end loop;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_and_post_finance_system_journal',
    'app.finance_journals', v_journal.id, 'success', null, null, to_jsonb(v_journal)
  );

  return v_journal;
end;
$function$;

create or replace function app.create_finance_bank_account(p_tenant_id uuid, p_company_id uuid, p_account_name text, p_bank_name text, p_account_number_last4 text, p_currency text, p_gl_account_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text DEFAULT NULL::text)
 returns app.finance_bank_accounts
 language plpgsql
 security definer
 set search_path to 'app', 'pg_temp'
as $function$
declare
  v_account app.finance_bank_accounts;
  v_gl_account app.finance_accounts;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_cash_authority('Approve', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(p_tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(p_tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
  perform app.assert_finance_company_org_unit(p_tenant_id, p_company_id);
  if not app.validate_currency_code(p_currency) then
    raise exception 'finance_cash_unsupported_currency: % is not a registered, active currency', p_currency
      using errcode = 'check_violation';
  end if;

  select * into v_gl_account from app.finance_accounts where id = p_gl_account_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'finance_cash_gl_account_not_found: % is not a known account for tenant %', p_gl_account_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;
  if v_gl_account.status <> 'active' or not v_gl_account.is_postable then
    raise exception 'finance_cash_gl_account_not_postable: account % is not active/postable', v_gl_account.code
      using errcode = 'check_violation';
  end if;

  insert into app.finance_bank_accounts (tenant_id, company_id, account_name, bank_name, account_number_last4, currency, gl_account_id, created_by)
  values (p_tenant_id, p_company_id, p_account_name, p_bank_name, p_account_number_last4, p_currency, p_gl_account_id, p_actor_label)
  returning * into v_account;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_finance_bank_account',
    'app.finance_bank_accounts', v_account.id, 'success', null, null, to_jsonb(v_account)
  );

  return v_account;
end;
$function$;

create or replace function app.execute_finance_reconciliation_run(p_tenant_id uuid, p_company_id uuid, p_scope text, p_as_of_date date, p_tolerance_amount numeric, p_actor_auth_user_id uuid, p_actor_label text)
 returns app.finance_reconciliation_runs
 language plpgsql
 security definer
 set search_path to 'app', 'pg_temp'
as $function$
declare
  v_run app.finance_reconciliation_runs;
  v_control_account app.finance_accounts;
  v_control_total numeric(14, 2) := 0;
  v_source_total numeric(14, 2) := 0;
  v_within boolean;
  v_source_document_type text;
  v_basis_cutoff date;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_reconciliation_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  perform app.assert_finance_company_org_unit(p_tenant_id, p_company_id);
  if p_scope not in ('ar', 'ap') then
    raise exception 'finance_reconciliation_invalid_scope: % is not a supported reconciliation scope', p_scope
      using errcode = 'check_violation';
  end if;
  if p_tolerance_amount is null or p_tolerance_amount < 0 then
    raise exception 'finance_reconciliation_invalid_tolerance: % must be a non-negative amount', p_tolerance_amount
      using errcode = 'check_violation';
  end if;

  v_control_account := app.resolve_finance_posting_map_account(p_tenant_id, p_scope || '_control');
  v_source_document_type := case when p_scope = 'ar' then 'invoice' else 'vendor_bill' end;

  -- ATW-032: ONE comparison basis for both sides. The GL side can only be
  -- bounded by whole fiscal periods -- app.finance_subledger_batches carries no
  -- business posting-date column at all (only posted_at, a wall-clock insert
  -- timestamp, and posting_period_id), a real constraint this function's
  -- original comment already disclosed. The source side was bounded by the
  -- document date instead, so the two agreed ONLY when p_as_of_date happened to
  -- land on a period end; every other as-of date counted documents on the source
  -- side whose own GL batches sat in a not-yet-elapsed period and were excluded
  -- from the control side. That fabricated variance auto-opened a
  -- finance_reconciliation_exceptions row and blocked
  -- certify_finance_reconciliation_run with finance_reconciliation_unexplained_variance.
  -- The cutoff is therefore the last fiscal period end that has fully elapsed on
  -- or before p_as_of_date, and BOTH sides are bounded by it. The GL side is
  -- unchanged in meaning by this (no period ends strictly between v_basis_cutoff
  -- and p_as_of_date, by construction of the max) -- it is written against the
  -- cutoff so that the shared basis is explicit rather than coincidental.
  -- Company scope (ATW-032, finding 4) is applied here too, so a company-scoped
  -- run is bounded by that company's own calendar -- the same company convention
  -- app.resolve_finance_period_for_date applies when it resolves a posting period.
  select max(fp.end_date) into v_basis_cutoff
    from app.finance_fiscal_periods fp
    where fp.tenant_id = p_tenant_id
      and (p_company_id is null or fp.company_id = p_company_id)
      and fp.end_date <= p_as_of_date;

  -- ATW-032: handled explicitly rather than silently. With no elapsed period the
  -- control side is necessarily zero, so a naive comparison would report 0 vs 0,
  -- declare itself within tolerance, and offer a vacuously certifiable run as
  -- Financial Close evidence -- the exact "silent close on unreconciled data"
  -- FIN-209 exists to prevent.
  if v_basis_cutoff is null then
    raise exception 'finance_reconciliation_no_elapsed_period: no fiscal period has fully ended on or before % for this scope, so there is no basis on which the GL control side can be compared', p_as_of_date
      using errcode = 'no_data_found';
  end if;

  -- ATW-032 (finding 4): p_company_id was stored on the run row and never used
  -- to filter anything, so a run tagged with one company reported tenant-wide
  -- totals. app.get_finance_aging_report -- the architecturally identical sibling
  -- over the same open-item tables -- already applies exactly this predicate.
  select coalesce(sum(case when p_scope = 'ar' then (case when l.direction = 'debit' then l.amount else -l.amount end) else (case when l.direction = 'credit' then l.amount else -l.amount end) end), 0)
    into v_control_total
    from app.finance_subledger_lines l
    join app.finance_subledger_batches b on b.id = l.batch_id
    join app.finance_fiscal_periods fp on fp.id = b.posting_period_id
    where b.tenant_id = p_tenant_id
      and (p_company_id is null or b.company_id = p_company_id)
      and l.account_id = v_control_account.id
      and fp.end_date <= v_basis_cutoff;

  -- ATW-032: the source (open-item) side is bounded by each domain's own real
  -- business date column (invoice_date for AR, bill_date for AP, never created_at)
  -- as before -- but now against the SAME elapsed-period cutoff the control side
  -- uses, not against the raw requested as-of date.
  if p_scope = 'ar' then
    select coalesce(sum(i.open_amount), 0) into v_source_total
      from app.finance_ar_open_items i
      where i.tenant_id = p_tenant_id
        and (p_company_id is null or i.company_id = p_company_id)
        and i.source_document_type = v_source_document_type
        and i.invoice_date <= v_basis_cutoff;
  else
    select coalesce(sum(i.open_amount), 0) into v_source_total
      from app.finance_ap_open_items i
      where i.tenant_id = p_tenant_id
        and (p_company_id is null or i.company_id = p_company_id)
        and i.source_document_type = v_source_document_type
        and i.bill_date <= v_basis_cutoff;
  end if;

  v_within := abs(v_control_total - v_source_total) <= p_tolerance_amount;

  -- ATW-032: as_of_date still records what the caller ASKED for; v_basis_cutoff
  -- is the basis the engine could actually answer on, and is disclosed in the
  -- exception description and the audit payload rather than hidden.
  insert into app.finance_reconciliation_runs (tenant_id, company_id, scope, as_of_date, tolerance_amount, control_total, source_total, is_within_tolerance, prepared_by)
  values (p_tenant_id, p_company_id, p_scope, p_as_of_date, p_tolerance_amount, v_control_total, v_source_total, v_within, p_actor_label)
  returning * into v_run;

  if not v_within then
    insert into app.finance_reconciliation_exceptions (run_id, tenant_id, description, expected_amount, actual_amount)
    values (v_run.id, p_tenant_id, format('%s control account (%s) balance does not match open-item total within tolerance %s (comparison basis: fiscal periods ending on or before %s)', upper(p_scope), v_control_account.code, p_tolerance_amount, v_basis_cutoff), v_source_total, v_control_total);
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'execute_finance_reconciliation_run',
    'app.finance_reconciliation_runs', v_run.id, 'success', null, null,
    to_jsonb(v_run) || jsonb_build_object('comparisonBasisCutoff', v_basis_cutoff)
  );

  return v_run;
end;
$function$;

create or replace function app.generate_finance_fiscal_calendar(p_tenant_id uuid, p_company_id uuid, p_code text, p_name text, p_start_date date, p_period_count integer, p_actor_auth_user_id uuid, p_created_by text)
 returns app.finance_fiscal_calendars
 language plpgsql
 security definer
 set search_path to 'app', 'pg_temp'
as $function$
declare
  v_calendar app.finance_fiscal_calendars;
  v_period app.finance_fiscal_periods;
  v_period_start date;
  v_period_end date;
  v_seq integer;
  v_policy_row record;
  v_item record;
  v_found_policy boolean := false;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_period_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  perform app.assert_finance_company_org_unit(p_tenant_id, p_company_id);

  if p_period_count is null or p_period_count < 1 or p_period_count > 24 then
    raise exception 'finance_calendar_invalid_period_count: period count % must be between 1 and 24', p_period_count
      using errcode = 'check_violation';
  end if;

  begin
    insert into app.finance_fiscal_calendars (tenant_id, company_id, code, name, created_by)
    values (p_tenant_id, p_company_id, p_code, p_name, p_created_by)
    returning * into v_calendar;
  exception
    when unique_violation then
      raise exception 'finance_calendar_duplicate_code: code % already exists in this tenant/company scope', p_code
        using errcode = 'unique_violation';
  end;

  -- Resolve the tenant's currently-effective finance_close_policy once, then
  -- pin an identical checklist snapshot onto every generated period.
  for v_policy_row in select * from app.resolve_finance_config('finance_close_policy', p_tenant_id) loop
    v_found_policy := true;
  end loop;

  v_period_start := p_start_date;
  for v_seq in 1..p_period_count loop
    v_period_end := (v_period_start + interval '1 month' - interval '1 day')::date;

    if exists (
      select 1 from app.finance_fiscal_periods
      where tenant_id = p_tenant_id
        and coalesce(company_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(p_company_id, '00000000-0000-0000-0000-000000000000'::uuid)
        and start_date <= v_period_end and end_date >= v_period_start
    ) then
      raise exception 'finance_period_overlap: the period starting % would overlap an existing period in this tenant/company scope', v_period_start
        using errcode = 'check_violation';
    end if;

    insert into app.finance_fiscal_periods (calendar_id, tenant_id, company_id, period_code, name, start_date, end_date, sequence_number, created_by)
    values (
      v_calendar.id, p_tenant_id, p_company_id, to_char(v_period_start, 'YYYY-MM'), to_char(v_period_start, 'YYYY-MM'),
      v_period_start, v_period_end, v_seq, p_created_by
    )
    returning * into v_period;

    if v_found_policy then
      for v_item in select key, value from jsonb_each(v_policy_row.items) loop
        insert into app.finance_period_close_checklist_items (period_id, item_key, label, required, source_capability)
        values (v_period.id, v_item.key, v_item.value ->> 'label', coalesce((v_item.value ->> 'required')::boolean, false), v_item.value ->> 'sourceCapability');
      end loop;
    end if;

    insert into app.finance_period_transitions (period_id, tenant_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
    values (v_period.id, p_tenant_id, 'none', 'open', null, p_actor_auth_user_id, p_created_by);

    v_period_start := v_period_start + interval '1 month';
  end loop;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_created_by, 'generate_finance_fiscal_calendar',
    'app.finance_fiscal_calendars', v_calendar.id, 'success', null, null, jsonb_build_object('period_count', p_period_count, 'start_date', p_start_date)
  );

  return v_calendar;
end;
$function$;

create or replace function app.import_historical_finance_journal(p_tenant_id uuid, p_company_id uuid, p_source_id uuid, p_journal_date date, p_currency text, p_lines jsonb, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text DEFAULT NULL::text)
 returns app.finance_journals
 language plpgsql
 security definer
 set search_path to 'app', 'pg_temp'
as $function$
declare
  v_journal app.finance_journals;
  v_line jsonb;
  v_line_number integer := 0;
  v_total numeric(14, 2);
  v_period record;
  v_year integer;
  v_seq integer;
  v_number text;
begin
  if not app.check_finance_journal_authority('Approve', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(p_tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(p_tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
  perform app.assert_finance_company_org_unit(p_tenant_id, p_company_id);

  if p_source_id is null then
    raise exception 'finance_journal_migration_source_id_required: a real, non-null source_id is required to import a historical journal' using errcode = 'check_violation';
  end if;

  if coalesce(trim(p_reason), '') = '' then
    raise exception 'finance_journal_migration_reason_required: a real, non-empty reason is required to import a historical journal' using errcode = 'check_violation';
  end if;

  select * into v_journal from app.finance_journals where tenant_id = p_tenant_id and source_type = 'migration' and source_id = p_source_id;
  if found then
    return v_journal;
  end if;

  v_total := app.validate_finance_journal_line_balance(p_lines);

  select * into v_period from app.resolve_finance_period_for_date(p_tenant_id, p_company_id, p_journal_date);
  if not found then
    raise exception 'finance_journal_period_not_found: no fiscal period covers % -- create the covering fiscal period before importing historical data into it', p_journal_date
      using errcode = 'no_data_found';
  end if;
  -- Deliberately does NOT require v_period.posting_eligible -- see this migration's own
  -- header for why (confirmed with the operator before implementing).

  v_year := extract(year from p_journal_date)::integer;
  insert into app.finance_journal_number_counters (tenant_id, company_id, year, next_seq)
  values (p_tenant_id, p_company_id, v_year, 2)
  on conflict (tenant_id, coalesce(company_id, '00000000-0000-0000-0000-000000000000'::uuid), year)
  do update set next_seq = app.finance_journal_number_counters.next_seq + 1
  returning next_seq - 1 into v_seq;
  v_number := 'JRNL-' || v_year::text || '-' || lpad(v_seq::text, 6, '0');

  insert into app.finance_journals (
    tenant_id, company_id, journal_number, source_type, source_id, idempotency_key,
    currency, total_amount, journal_date, status, posting_period_id, posted_by, posted_at, created_by
  )
  values (
    p_tenant_id, p_company_id, v_number, 'migration', p_source_id, 'migration:' || p_source_id::text,
    p_currency, v_total, p_journal_date, 'posted', v_period.period_id, p_actor_label, now(), p_actor_label
  )
  returning * into v_journal;

  for v_line in select * from jsonb_array_elements(p_lines) loop
    v_line_number := v_line_number + 1;
    insert into app.finance_journal_lines (journal_id, tenant_id, line_number, account_id, direction, amount)
    values (v_journal.id, p_tenant_id, v_line_number, (v_line ->> 'accountId')::uuid, v_line ->> 'direction', (v_line ->> 'amount')::numeric);
  end loop;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'import_historical_finance_journal',
    'app.finance_journals', v_journal.id, 'success', p_reason, null, to_jsonb(v_journal)
  );

  return v_journal;
end;
$function$;

create or replace function app.post_finance_ap_open_item(p_tenant_id uuid, p_company_id uuid, p_vendor_master_id uuid, p_source_document_type text, p_source_document_id uuid, p_currency text, p_original_amount numeric, p_bill_date date, p_due_date date, p_actor_auth_user_id uuid, p_actor_label text)
 returns app.finance_ap_open_items
 language plpgsql
 security definer
 set search_path to 'app', 'pg_temp'
as $function$
declare
  v_item app.finance_ap_open_items;
  v_vendor app.master_records;
  v_period record;
  v_required_action text;
begin
  if p_source_document_type not in ('vendor_bill', 'opening_balance') then
    raise exception 'finance_ap_unsupported_source_type: % is not a supported AP source document type', p_source_document_type
      using errcode = 'check_violation';
  end if;
  v_required_action := case when p_source_document_type = 'opening_balance' then 'Approve' else 'Edit' end;

  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_ap_authority(v_required_action, p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:% for tenant %', p_actor_auth_user_id, v_required_action, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  perform app.assert_finance_company_org_unit(p_tenant_id, p_company_id);

  select * into v_item from app.finance_ap_open_items
    where tenant_id = p_tenant_id and source_document_type = p_source_document_type and source_document_id = p_source_document_id;
  if found then
    return v_item;
  end if;

  select * into v_vendor from app.master_records
    where id = p_vendor_master_id and master_type_code = 'vendor' and canonical_status = 'active'
      and (tenant_id = p_tenant_id or tenant_id is null);
  if not found then
    raise exception 'finance_ap_vendor_not_found: % is not a known active vendor reference for tenant %', p_vendor_master_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;

  if not app.validate_currency_code(p_currency) then
    raise exception 'finance_ap_unsupported_currency: % is not a registered, active currency', p_currency
      using errcode = 'check_violation';
  end if;
  if p_original_amount is null or p_original_amount <= 0 then
    raise exception 'finance_ap_invalid_amount: original amount must be positive, got %', p_original_amount
      using errcode = 'check_violation';
  end if;
  if p_due_date < p_bill_date then
    raise exception 'finance_ap_invalid_due_date: due date % is before bill date %', p_due_date, p_bill_date
      using errcode = 'check_violation';
  end if;

  select * into v_period from app.resolve_finance_period_for_date(p_tenant_id, p_company_id, p_bill_date);
  if not found then
    raise exception 'finance_ap_period_not_found: no fiscal period covers %', p_bill_date
      using errcode = 'no_data_found';
  end if;
  if not v_period.posting_eligible then
    raise exception 'finance_ap_period_not_open: fiscal period % for % is not open', v_period.period_code, p_bill_date
      using errcode = 'check_violation';
  end if;

  begin
    insert into app.finance_ap_open_items (
      tenant_id, company_id, vendor_master_id, source_document_type, source_document_id,
      currency, original_amount, bill_date, due_date, posting_period_id, created_by
    )
    values (
      p_tenant_id, p_company_id, p_vendor_master_id, p_source_document_type, p_source_document_id,
      p_currency, p_original_amount, p_bill_date, p_due_date, v_period.period_id, p_actor_label
    )
    returning * into v_item;
  exception
    when unique_violation then
      select * into v_item from app.finance_ap_open_items
        where tenant_id = p_tenant_id and source_document_type = p_source_document_type and source_document_id = p_source_document_id;
      return v_item;
  end;

  insert into app.finance_ap_open_item_events (tenant_id, open_item_id, event_type, amount_delta, source_type, source_id, actor_auth_user_id, actor_label)
  values (p_tenant_id, v_item.id, 'created', p_original_amount, p_source_document_type, p_source_document_id, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'post_finance_ap_open_item',
    'app.finance_ap_open_items', v_item.id, 'success', null, null, to_jsonb(v_item)
  );

  return v_item;
end;
$function$;

create or replace function app.post_finance_ar_open_item(p_tenant_id uuid, p_company_id uuid, p_customer_account_id uuid, p_source_document_type text, p_source_document_id uuid, p_currency text, p_original_amount numeric, p_invoice_date date, p_due_date date, p_actor_auth_user_id uuid, p_actor_label text)
 returns app.finance_ar_open_items
 language plpgsql
 security definer
 set search_path to 'app', 'pg_temp'
as $function$
declare
  v_item app.finance_ar_open_items;
  v_customer app.accounts;
  v_period record;
  v_required_action text;
begin
  if p_source_document_type not in ('invoice', 'opening_balance') then
    raise exception 'finance_ar_unsupported_source_type: % is not a supported AR source document type', p_source_document_type
      using errcode = 'check_violation';
  end if;
  v_required_action := case when p_source_document_type = 'opening_balance' then 'Approve' else 'Edit' end;

  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_ar_authority(v_required_action, p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:% for tenant %', p_actor_auth_user_id, v_required_action, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  perform app.assert_finance_company_org_unit(p_tenant_id, p_company_id);

  -- Idempotent: a retried call for the same source document returns the
  -- existing open item rather than raising a duplicate error.
  select * into v_item from app.finance_ar_open_items
    where tenant_id = p_tenant_id and source_document_type = p_source_document_type and source_document_id = p_source_document_id;
  if found then
    return v_item;
  end if;

  select * into v_customer from app.accounts where id = p_customer_account_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'finance_ar_customer_not_found: % is not a known customer account for tenant %', p_customer_account_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;

  if not app.validate_currency_code(p_currency) then
    raise exception 'finance_ar_unsupported_currency: % is not a registered, active currency', p_currency
      using errcode = 'check_violation';
  end if;
  if p_original_amount is null or p_original_amount <= 0 then
    raise exception 'finance_ar_invalid_amount: original amount must be positive, got %', p_original_amount
      using errcode = 'check_violation';
  end if;
  if p_due_date < p_invoice_date then
    raise exception 'finance_ar_invalid_due_date: due date % is before invoice date %', p_due_date, p_invoice_date
      using errcode = 'check_violation';
  end if;

  select * into v_period from app.resolve_finance_period_for_date(p_tenant_id, p_company_id, p_invoice_date);
  if not found then
    raise exception 'finance_ar_period_not_found: no fiscal period covers %', p_invoice_date
      using errcode = 'no_data_found';
  end if;
  if not v_period.posting_eligible then
    raise exception 'finance_ar_period_not_open: fiscal period % for % is not open', v_period.period_code, p_invoice_date
      using errcode = 'check_violation';
  end if;

  begin
    insert into app.finance_ar_open_items (
      tenant_id, company_id, customer_account_id, source_document_type, source_document_id,
      currency, original_amount, invoice_date, due_date, posting_period_id, created_by
    )
    values (
      p_tenant_id, p_company_id, p_customer_account_id, p_source_document_type, p_source_document_id,
      p_currency, p_original_amount, p_invoice_date, p_due_date, v_period.period_id, p_actor_label
    )
    returning * into v_item;
  exception
    when unique_violation then
      select * into v_item from app.finance_ar_open_items
        where tenant_id = p_tenant_id and source_document_type = p_source_document_type and source_document_id = p_source_document_id;
      return v_item;
  end;

  insert into app.finance_ar_open_item_events (tenant_id, open_item_id, event_type, amount_delta, source_type, source_id, actor_auth_user_id, actor_label)
  values (p_tenant_id, v_item.id, 'created', p_original_amount, p_source_document_type, p_source_document_id, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'post_finance_ar_open_item',
    'app.finance_ar_open_items', v_item.id, 'success', null, null, to_jsonb(v_item)
  );

  return v_item;
end;
$function$;

create or replace function app.post_finance_subledger_batch(p_tenant_id uuid, p_company_id uuid, p_source_type text, p_source_id uuid, p_posting_date date, p_currency text, p_lines jsonb, p_actor_auth_user_id uuid, p_actor_label text)
 returns app.finance_subledger_batches
 language plpgsql
 security definer
 set search_path to 'app', 'pg_temp'
as $function$
declare
  v_batch app.finance_subledger_batches;
  v_period record;
  v_line jsonb;
  v_line_number integer := 0;
  v_debit_total numeric(14, 2) := 0;
  v_credit_total numeric(14, 2) := 0;
  v_direction text;
  v_amount numeric;
  v_account app.finance_accounts;
  v_key text;
  v_journal_lines jsonb := '[]'::jsonb;
  v_journal app.finance_journals;
  v_lock_scope text;
begin
  if p_source_type not in ('invoice', 'receipt_allocation', 'vendor_bill', 'settlement', 'opening_balance') then
    -- ISS-2026-273: 'opening_balance' added. This is the ONLY change to this function's
    -- body; every other line is a mechanical, script-extracted copy of
    -- 20260811000000's own definition (the latest), including its `security definer`
    -- and `set search_path` clauses, so no line is retyped and none can drift.
    raise exception 'finance_subledger_unsupported_source_type: % is not a supported subledger source type', p_source_type
      using errcode = 'check_violation';
  end if;
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_subledger_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  perform app.assert_finance_company_org_unit(p_tenant_id, p_company_id);

  select * into v_batch from app.finance_subledger_batches where tenant_id = p_tenant_id and source_type = p_source_type and source_id = p_source_id;
  if found then
    return v_batch;
  end if;

  if p_lines is null or jsonb_array_length(p_lines) = 0 then
    raise exception 'finance_subledger_empty_batch: at least one line is required' using errcode = 'check_violation';
  end if;

  select * into v_period from app.resolve_finance_period_for_date(p_tenant_id, p_company_id, p_posting_date);
  if not found then
    raise exception 'finance_subledger_period_not_found: no fiscal period covers %', p_posting_date
      using errcode = 'no_data_found';
  end if;
  if not v_period.posting_eligible then
    raise exception 'finance_subledger_period_not_open: fiscal period % for % is not open', v_period.period_code, p_posting_date
      using errcode = 'check_violation';
  end if;

  v_lock_scope := case when p_source_type in ('invoice', 'receipt_allocation') then 'ar' when p_source_type in ('vendor_bill', 'settlement') then 'ap' else 'gl' end;
  perform app.assert_finance_period_open_for_posting(p_tenant_id, p_company_id, v_period.period_id, v_lock_scope);

  for v_line in select * from jsonb_array_elements(p_lines) loop
    v_direction := v_line ->> 'direction';
    v_amount := (v_line ->> 'amount')::numeric;
    if v_direction not in ('debit', 'credit') then
      raise exception 'finance_subledger_invalid_direction: % is not debit or credit', v_direction using errcode = 'check_violation';
    end if;
    if v_amount is null or v_amount <= 0 then
      raise exception 'finance_subledger_invalid_line_amount: line amount must be positive, got %', v_amount using errcode = 'check_violation';
    end if;
    if v_direction = 'debit' then
      v_debit_total := v_debit_total + v_amount;
    else
      v_credit_total := v_credit_total + v_amount;
    end if;
  end loop;

  if v_debit_total <> v_credit_total then
    raise exception 'finance_subledger_unbalanced_batch: debit total % does not equal credit total % for source % %', v_debit_total, v_credit_total, p_source_type, p_source_id
      using errcode = 'check_violation';
  end if;

  -- HDN-374 finding 3 (new instance, not in HDN-BLK-010's original scope): a genuine
  -- race between the select above and this insert (two concurrent callers posting the
  -- same source_type/source_id) is resolved by re-selecting and returning the winner.
  -- Backed by finance_subledger_batches_source_unique. Caught here, before any
  -- finance_subledger_lines row is written, so the losing caller leaves no partial state.
  begin
    insert into app.finance_subledger_batches (tenant_id, company_id, source_type, source_id, currency, total_amount, posting_period_id, posted_by)
    values (p_tenant_id, p_company_id, p_source_type, p_source_id, p_currency, v_debit_total, v_period.period_id, p_actor_label)
    returning * into v_batch;
  exception
    when unique_violation then
      select * into v_batch from app.finance_subledger_batches where tenant_id = p_tenant_id and source_type = p_source_type and source_id = p_source_id;
      if found then
        return v_batch;
      end if;
      raise;
  end;

  for v_line in select * from jsonb_array_elements(p_lines) loop
    v_line_number := v_line_number + 1;

    if v_line ->> 'accountId' is not null then
      select * into v_account from app.finance_accounts where id = (v_line ->> 'accountId')::uuid and tenant_id = p_tenant_id;
      if not found then
        raise exception 'finance_subledger_unresolved_account: % is not a known account for tenant %', v_line ->> 'accountId', p_tenant_id
          using errcode = 'no_data_found';
      end if;
      if v_account.status <> 'active' then
        raise exception 'finance_subledger_inactive_mapped_account: account % is not active (status=%)', v_account.code, v_account.status
          using errcode = 'check_violation';
      end if;
      if not v_account.is_postable then
        raise exception 'finance_subledger_not_postable_mapped_account: account % is not postable (control account)', v_account.code
          using errcode = 'check_violation';
      end if;
      v_key := null;
    else
      v_key := v_line ->> 'postingMapKey';
      v_account := app.resolve_finance_posting_map_account(p_tenant_id, v_key);
    end if;

    insert into app.finance_subledger_lines (batch_id, tenant_id, line_number, account_id, posting_map_key, direction, amount, open_item_type, open_item_id)
    values (
      v_batch.id, p_tenant_id, v_line_number, v_account.id, v_key, v_line ->> 'direction', (v_line ->> 'amount')::numeric,
      v_line ->> 'openItemType', nullif(v_line ->> 'openItemId', '')::uuid
    );

    v_journal_lines := v_journal_lines || jsonb_build_array(jsonb_build_object('accountId', v_account.id, 'direction', v_line ->> 'direction', 'amount', (v_line ->> 'amount')::numeric));
  end loop;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'post_finance_subledger_batch',
    'app.finance_subledger_batches', v_batch.id, 'success', null, null,
    jsonb_build_object('sourceType', p_source_type, 'sourceId', p_source_id, 'totalAmount', v_debit_total)
  );

  select * into v_journal from app.create_and_post_finance_system_journal(
    p_tenant_id, p_company_id, 'subledger', v_batch.id, p_posting_date, p_currency, v_journal_lines, p_actor_auth_user_id, p_actor_label, v_lock_scope
  );
  update app.finance_subledger_batches set gl_journal_id = v_journal.id where id = v_batch.id returning * into v_batch;

  return v_batch;
end;
$function$;

create or replace function app.prepare_finance_journal_adjustment(p_tenant_id uuid, p_company_id uuid, p_original_journal_id uuid, p_correction_date date, p_reason text, p_evidence_ref text, p_adjustment_lines jsonb, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 returns app.finance_journal_corrections
 language plpgsql
 security definer
 set search_path to 'app', 'pg_temp'
as $function$
declare
  v_correction app.finance_journal_corrections;
  v_original app.finance_journals;
  v_line jsonb;
  v_account app.finance_accounts;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_correction_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  perform app.assert_finance_company_org_unit(p_tenant_id, p_company_id);
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: a non-empty idempotency_key is required' using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_correction_reason_required: a non-empty reason is required' using errcode = 'check_violation';
  end if;

  select * into v_correction from app.finance_journal_corrections where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
    -- conflict, never a replay. Returning the earlier target's row here silently
    -- misattributed this request to it (or silently discarded it entirely).
    if v_correction.original_journal_id is distinct from p_original_journal_id or v_correction.correction_type is distinct from 'adjustment' or v_correction.company_id is distinct from p_company_id then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different journal correction (journal %/type %, not journal %/type adjustment)', p_idempotency_key, v_correction.original_journal_id, v_correction.correction_type, p_original_journal_id
        using errcode = 'unique_violation';
    end if;
    return v_correction;
  end if;

  select * into v_original from app.finance_journals where id = p_original_journal_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'finance_journal_not_found: % is not a known journal for tenant %', p_original_journal_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;
  if v_original.status <> 'posted' then
    raise exception 'finance_correction_original_not_posted: journal % is % not posted', p_original_journal_id, v_original.status
      using errcode = 'check_violation';
  end if;

  perform app.validate_finance_journal_line_balance(p_adjustment_lines);

  for v_line in select * from jsonb_array_elements(p_adjustment_lines) loop
    select * into v_account from app.finance_accounts where id = (v_line ->> 'accountId')::uuid and tenant_id = p_tenant_id;
    if not found then
      raise exception 'finance_journal_account_not_found: % is not a known account for tenant %', v_line ->> 'accountId', p_tenant_id
        using errcode = 'no_data_found';
    end if;
    if v_account.status <> 'active' or not v_account.is_postable then
      raise exception 'finance_journal_not_postable_account: account % is not active/postable', v_account.code
        using errcode = 'check_violation';
    end if;
  end loop;

  -- HDN-374 finding 3 (closes HDN-BLK-010's own required scope): a genuine race between
  -- the select above and this insert is resolved by re-selecting and re-applying the
  -- same conflict check, never a raw unique_violation on a legitimate concurrent retry.
  -- Backed by finance_journal_corrections_idempotency_unique.
  begin
    insert into app.finance_journal_corrections (
      tenant_id, company_id, original_journal_id, correction_type, correction_date, reason, evidence_ref, adjustment_lines, idempotency_key, created_by
    )
    values (p_tenant_id, p_company_id, p_original_journal_id, 'adjustment', p_correction_date, p_reason, p_evidence_ref, p_adjustment_lines, p_idempotency_key, p_actor_label)
    returning * into v_correction;
  exception
    when unique_violation then
      select * into v_correction from app.finance_journal_corrections where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      if found then
        if v_correction.original_journal_id is distinct from p_original_journal_id or v_correction.correction_type is distinct from 'adjustment' or v_correction.company_id is distinct from p_company_id then
          raise exception 'idempotency_key_conflict: idempotency key % was already used for a different journal correction (journal %/type %, not journal %/type adjustment)', p_idempotency_key, v_correction.original_journal_id, v_correction.correction_type, p_original_journal_id
            using errcode = 'unique_violation';
        end if;
        return v_correction;
      end if;
      raise;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'prepare_finance_journal_adjustment',
    'app.finance_journal_corrections', v_correction.id, 'success', p_reason, null, to_jsonb(v_correction)
  );

  return v_correction;
end;
$function$;

create or replace function app.prepare_finance_journal_reversal(p_tenant_id uuid, p_company_id uuid, p_original_journal_id uuid, p_correction_date date, p_reason text, p_evidence_ref text, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 returns app.finance_journal_corrections
 language plpgsql
 security definer
 set search_path to 'app', 'pg_temp'
as $function$
declare
  v_correction app.finance_journal_corrections;
  v_original app.finance_journals;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_correction_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  perform app.assert_finance_company_org_unit(p_tenant_id, p_company_id);
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: a non-empty idempotency_key is required' using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_correction_reason_required: a non-empty reason is required' using errcode = 'check_violation';
  end if;

  select * into v_correction from app.finance_journal_corrections where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
    -- conflict, never a replay. Returning the earlier target's row here silently
    -- misattributed this request to it (or silently discarded it entirely).
    if v_correction.original_journal_id is distinct from p_original_journal_id or v_correction.correction_type is distinct from 'reversal' or v_correction.company_id is distinct from p_company_id then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different journal correction (journal %/type %, not journal %/type reversal)', p_idempotency_key, v_correction.original_journal_id, v_correction.correction_type, p_original_journal_id
        using errcode = 'unique_violation';
    end if;
    return v_correction;
  end if;

  select * into v_original from app.finance_journals where id = p_original_journal_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'finance_journal_not_found: % is not a known journal for tenant %', p_original_journal_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;
  if v_original.status <> 'posted' then
    raise exception 'finance_correction_original_not_posted: journal % is % not posted', p_original_journal_id, v_original.status
      using errcode = 'check_violation';
  end if;
  if exists (
    select 1 from app.finance_journal_corrections
    where tenant_id = p_tenant_id and original_journal_id = p_original_journal_id
      and correction_type = 'reversal' and status <> 'discarded'
  ) then
    raise exception 'finance_correction_duplicate_reversal: journal % already has an active reversal request', p_original_journal_id
      using errcode = 'check_violation';
  end if;

  -- HDN-374 finding 3 (closes HDN-BLK-010's own required scope): this insert can race
  -- on TWO distinct unique constraints -- finance_journal_corrections_idempotency_unique
  -- (a genuine concurrent retry with the same key: re-select and return) or the partial
  -- unique index backing "one active reversal per original journal" (two DIFFERENT
  -- idempotency keys racing to reverse the SAME original journal concurrently: a genuine
  -- conflict, not a replay -- surfaced as the same named exception the pre-check above
  -- already raises for the non-concurrent case, never a raw unique_violation).
  begin
    insert into app.finance_journal_corrections (
      tenant_id, company_id, original_journal_id, correction_type, correction_date, reason, evidence_ref, idempotency_key, created_by
    )
    values (p_tenant_id, p_company_id, p_original_journal_id, 'reversal', p_correction_date, p_reason, p_evidence_ref, p_idempotency_key, p_actor_label)
    returning * into v_correction;
  exception
    when unique_violation then
      select * into v_correction from app.finance_journal_corrections where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      if found then
        if v_correction.original_journal_id is distinct from p_original_journal_id or v_correction.correction_type is distinct from 'reversal' or v_correction.company_id is distinct from p_company_id then
          raise exception 'idempotency_key_conflict: idempotency key % was already used for a different journal correction (journal %/type %, not journal %/type reversal)', p_idempotency_key, v_correction.original_journal_id, v_correction.correction_type, p_original_journal_id
            using errcode = 'unique_violation';
        end if;
        return v_correction;
      end if;
      raise exception 'finance_correction_duplicate_reversal: journal % already has an active reversal request', p_original_journal_id
        using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'prepare_finance_journal_reversal',
    'app.finance_journal_corrections', v_correction.id, 'success', p_reason, null, to_jsonb(v_correction)
  );

  return v_correction;
end;
$function$;

create or replace function app.prepare_finance_settlement(p_tenant_id uuid, p_company_id uuid, p_vendor_master_id uuid, p_payment_reference text, p_bank_account_label text, p_currency text, p_settlement_date date, p_allocations jsonb, p_fee_amount numeric, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 returns app.finance_settlements
 language plpgsql
 security definer
 set search_path to 'app', 'pg_temp'
as $function$
declare
  v_settlement app.finance_settlements;
  v_vendor app.master_records;
  v_item jsonb;
  v_open_item_id uuid;
  v_amount numeric;
  v_open_item app.finance_ap_open_items;
  v_total numeric := 0;
  v_fee numeric := coalesce(p_fee_amount, 0);
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_settlement_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  perform app.assert_finance_company_org_unit(p_tenant_id, p_company_id);
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: a non-empty idempotency_key is required' using errcode = 'check_violation';
  end if;

  select * into v_settlement from app.finance_settlements where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
    -- conflict, never a replay. Returning the earlier target's row here silently
    -- misattributed this request to it (or silently discarded it entirely).
    if v_settlement.company_id is distinct from p_company_id or v_settlement.vendor_master_id is distinct from p_vendor_master_id then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different settlement (company %/vendor %, not company %/vendor %)', p_idempotency_key, v_settlement.company_id, v_settlement.vendor_master_id, p_company_id, p_vendor_master_id
        using errcode = 'unique_violation';
    end if;
    return v_settlement;
  end if;

  select * into v_vendor from app.master_records
    where id = p_vendor_master_id and master_type_code = 'vendor' and canonical_status = 'active'
      and (tenant_id = p_tenant_id or tenant_id is null);
  if not found then
    raise exception 'finance_settlement_vendor_not_found: % is not a known active vendor reference for tenant %', p_vendor_master_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;

  if not app.validate_currency_code(p_currency) then
    raise exception 'finance_settlement_unsupported_currency: % is not a registered, active currency', p_currency
      using errcode = 'check_violation';
  end if;
  if v_fee < 0 then
    raise exception 'finance_settlement_invalid_fee: fee amount must not be negative, got %', v_fee
      using errcode = 'check_violation';
  end if;
  if p_allocations is null or jsonb_array_length(p_allocations) = 0 then
    raise exception 'finance_settlement_empty_allocation: at least one AP allocation line is required' using errcode = 'check_violation';
  end if;

  for v_item in select * from jsonb_array_elements(p_allocations) loop
    v_open_item_id := (v_item ->> 'apOpenItemId')::uuid;
    v_amount := (v_item ->> 'amount')::numeric;
    if v_amount is null or v_amount <= 0 then
      raise exception 'finance_settlement_invalid_allocation_amount: allocation amount must be positive, got %', v_amount
        using errcode = 'check_violation';
    end if;

    select * into v_open_item from app.finance_ap_open_items where id = v_open_item_id and tenant_id = p_tenant_id;
    if not found then
      raise exception 'finance_settlement_open_item_not_found: % is not a known AP open item for tenant %', v_open_item_id, p_tenant_id
        using errcode = 'no_data_found';
    end if;
    if v_open_item.vendor_master_id <> p_vendor_master_id then
      raise exception 'finance_settlement_vendor_mismatch: AP open item % does not belong to vendor %', v_open_item_id, p_vendor_master_id
        using errcode = 'check_violation';
    end if;
    if v_open_item.currency <> p_currency then
      raise exception 'finance_settlement_currency_mismatch: AP open item % is % but settlement is %', v_open_item_id, v_open_item.currency, p_currency
        using errcode = 'check_violation';
    end if;
    if v_open_item.is_held then
      raise exception 'finance_settlement_open_item_held: AP open item % is held and cannot be settled', v_open_item_id
        using errcode = 'check_violation';
    end if;
    if v_open_item.status = 'settled' then
      raise exception 'finance_settlement_open_item_already_settled: AP open item % is already fully settled', v_open_item_id
        using errcode = 'check_violation';
    end if;
    if v_amount > v_open_item.open_amount then
      raise exception 'finance_settlement_over_allocation: allocation % exceeds open amount % for AP open item %', v_amount, v_open_item.open_amount, v_open_item_id
        using errcode = 'check_violation';
    end if;

    v_total := v_total + v_amount;
  end loop;

  -- HDN-374 finding 3 (closes HDN-BLK-010's own required scope): a genuine race between
  -- the select above and this insert is resolved by re-selecting and re-applying the
  -- same conflict check. Backed by finance_settlements_idempotency_unique.
  begin
    insert into app.finance_settlements (
      tenant_id, company_id, vendor_master_id, payment_reference, bank_account_label,
      currency, allocated_amount, fee_amount, settlement_date, idempotency_key, created_by
    )
    values (
      p_tenant_id, p_company_id, p_vendor_master_id, p_payment_reference, p_bank_account_label,
      p_currency, v_total, v_fee, p_settlement_date, p_idempotency_key, p_actor_label
    )
    returning * into v_settlement;
  exception
    when unique_violation then
      select * into v_settlement from app.finance_settlements where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      if found then
        if v_settlement.company_id is distinct from p_company_id or v_settlement.vendor_master_id is distinct from p_vendor_master_id then
          raise exception 'idempotency_key_conflict: idempotency key % was already used for a different settlement (company %/vendor %, not company %/vendor %)', p_idempotency_key, v_settlement.company_id, v_settlement.vendor_master_id, p_company_id, p_vendor_master_id
            using errcode = 'unique_violation';
        end if;
        return v_settlement;
      end if;
      raise;
  end;

  for v_item in select * from jsonb_array_elements(p_allocations) loop
    insert into app.finance_settlement_allocations (tenant_id, settlement_id, ap_open_item_id, amount)
    values (p_tenant_id, v_settlement.id, (v_item ->> 'apOpenItemId')::uuid, (v_item ->> 'amount')::numeric);
  end loop;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'prepare_finance_settlement',
    'app.finance_settlements', v_settlement.id, 'success', null, null, to_jsonb(v_settlement)
  );

  return v_settlement;
end;
$function$;

create or replace function app.capture_finance_receipt(p_tenant_id uuid, p_company_id uuid, p_customer_account_id uuid, p_receipt_reference text, p_receipt_date date, p_payer_name text, p_bank_account_label text, p_currency text, p_amount numeric, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 returns app.finance_receipts
 language plpgsql
 security definer
 set search_path to 'app', 'pg_temp'
as $function$
declare
  v_receipt app.finance_receipts;
  v_period record;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_receipt_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  perform app.assert_finance_company_org_unit(p_tenant_id, p_company_id);
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: a non-empty idempotency_key is required' using errcode = 'check_violation';
  end if;

  select * into v_receipt from app.finance_receipts where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
    -- conflict, never a replay. Returning the earlier target's row here silently
    -- misattributed this request to it (or silently discarded it entirely).
    if v_receipt.company_id is distinct from p_company_id or v_receipt.customer_account_id is distinct from p_customer_account_id then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different receipt (company %/customer %, not company %/customer %)', p_idempotency_key, v_receipt.company_id, v_receipt.customer_account_id, p_company_id, p_customer_account_id
        using errcode = 'unique_violation';
    end if;
    return v_receipt;
  end if;

  if not exists (select 1 from app.accounts where id = p_customer_account_id and tenant_id = p_tenant_id) then
    raise exception 'finance_receipt_customer_not_found: % is not a known customer account for tenant %', p_customer_account_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;
  if not app.validate_currency_code(p_currency) then
    raise exception 'finance_receipt_unsupported_currency: % is not a registered, active currency', p_currency
      using errcode = 'check_violation';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'finance_receipt_invalid_amount: amount must be positive, got %', p_amount
      using errcode = 'check_violation';
  end if;

  select * into v_period from app.resolve_finance_period_for_date(p_tenant_id, p_company_id, p_receipt_date);
  if not found then
    raise exception 'finance_receipt_period_not_found: no fiscal period covers %', p_receipt_date
      using errcode = 'no_data_found';
  end if;
  if not v_period.posting_eligible then
    raise exception 'finance_receipt_period_not_open: fiscal period % for % is not open', v_period.period_code, p_receipt_date
      using errcode = 'check_violation';
  end if;

  begin
    insert into app.finance_receipts (
      tenant_id, company_id, customer_account_id, receipt_reference, receipt_date, payer_name, bank_account_label,
      currency, amount, posting_period_id, idempotency_key, created_by
    )
    values (
      p_tenant_id, p_company_id, p_customer_account_id, p_receipt_reference, p_receipt_date, p_payer_name, p_bank_account_label,
      p_currency, p_amount, v_period.period_id, p_idempotency_key, p_actor_label
    )
    returning * into v_receipt;
  exception
    when unique_violation then
      raise exception 'finance_receipt_duplicate_reference: bank reference % already exists for tenant %', p_receipt_reference, p_tenant_id
        using errcode = 'unique_violation';
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'capture_finance_receipt',
    'app.finance_receipts', v_receipt.id, 'success', null, null, to_jsonb(v_receipt)
  );

  return v_receipt;
end;
$function$;

create or replace function app.create_finance_account_draft(p_tenant_id uuid, p_company_id uuid, p_code text, p_name text, p_account_type text, p_normal_balance text, p_parent_account_id uuid, p_is_control_account boolean, p_currency_restriction text, p_actor_auth_user_id uuid, p_created_by text)
 returns app.finance_accounts
 language plpgsql
 security definer
 set search_path to 'app', 'pg_temp'
as $function$
declare
  v_parent app.finance_accounts;
  v_account app.finance_accounts;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_account_authority('Create', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Create for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  perform app.assert_finance_company_org_unit(p_tenant_id, p_company_id);

  if p_parent_account_id is not null then
    select * into v_parent from app.finance_accounts where id = p_parent_account_id;
    if not found then
      raise exception 'finance_account_parent_not_found: %', p_parent_account_id using errcode = 'no_data_found';
    end if;
    if v_parent.tenant_id <> p_tenant_id or v_parent.company_id is distinct from p_company_id then
      raise exception 'finance_account_cross_scope_parent: parent account % does not share this account''s own tenant/company scope', p_parent_account_id
        using errcode = 'check_violation';
    end if;
    if v_parent.account_type <> p_account_type then
      raise exception 'finance_account_type_mismatch: parent account % is type % but child requests type %', p_parent_account_id, v_parent.account_type, p_account_type
        using errcode = 'check_violation';
    end if;
  end if;

  begin
    insert into app.finance_accounts (
      tenant_id, company_id, code, name, account_type, normal_balance,
      parent_account_id, is_control_account, is_postable, currency_restriction, created_by
    )
    values (
      p_tenant_id, p_company_id, p_code, p_name, p_account_type, p_normal_balance,
      p_parent_account_id, coalesce(p_is_control_account, false), not coalesce(p_is_control_account, false), p_currency_restriction, p_created_by
    )
    returning * into v_account;
  exception
    when unique_violation then
      raise exception 'finance_account_duplicate_code: code % already exists in this tenant/company scope', p_code
        using errcode = 'unique_violation';
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_created_by, 'create_finance_account_draft',
    'app.finance_accounts', v_account.id, 'success', null, null, to_jsonb(v_account)
  );

  return v_account;
end;
$function$;
