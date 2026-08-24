-- HDN-373 (Step 15, Prompt 373, RLS and RBAC Audit, `CG-S15-HDN-005`) -- closes
-- `HDN-BLK-015`/`ISS-2026-180`, the largest single finding this checkpoint's own
-- investigation surfaced.
--
-- ===========================================================================
-- The finding
-- ===========================================================================
--
-- 95 functions across the Finance domain (journal, period close/lock, exchange rate, tax,
-- invoice, AP settlement/hold, AR allocation/hold, cash receipt, settlement, vendor bill,
-- correction, reconciliation, account, bank statement/reconciliation) plus the generic
-- `app.enqueue_job` were authored `SECURITY INVOKER` (Postgres' implicit default -- no
-- caller ever wrote `SECURITY DEFINER`) instead of `SECURITY DEFINER`, unlike essentially
-- every other client-callable RPC in this schema (1,878 `SECURITY DEFINER` functions vs
-- 817 `SECURITY INVOKER` at last count; the Finance/generic-job outlier above accounts for
-- a large share of that 817). 76 of the 95 are top-level entry points already granted
-- `EXECUTE` directly to `authenticated` -- real, intended, currently-shipped reachability,
-- not a theoretical one -- and the remaining 19 are the `app.check_finance_*_authority`
-- family, each a one-line `language sql` wrapper around `app.evaluate_permission`.
--
-- **Live-forced and confirmed** (Tier C investigation lens, `docs/build-log/full-system-
-- hardening/HDN-373.md` §6): a genuine, real Finance Manager identity (an ordinary
-- `authenticated` session, not superuser, not `service_role`), calling
-- `app.create_finance_journal_draft` for their own tenant, was refused with `permission
-- denied for table permissions` -- three call frames deep, inside `app.evaluate_permission`
-- itself. `SECURITY INVOKER` means every nested call in the chain keeps executing as
-- whatever role is active at the call site; since `authenticated` holds no direct grant on
-- `app.permissions`, `app.role_assignments`, or (before this fix) most of the Finance
-- authority-check helpers, and no direct `INSERT`/`UPDATE` grant at all on
-- `app.finance_journals` and its siblings (by design -- every other domain's tables are
-- identically locked to `service_role` only, because every other domain's RPCs are
-- `SECURITY DEFINER`), the entire chain fails closed. This is not a narrow gap: it means
-- every Finance write RPC in this list, and every background job enqueued through the
-- generic path, has been **completely unreachable by any real tenant user since it
-- shipped** -- the `authenticated` grant on each was always present and always futile.
-- Confirmed independently by two Tier C investigation lenses (access-matrix/`DEFINER`
-- posture; maker/checker), and by this repository's own `scripts/db-tests/finance-*.sql`
-- suite, which only ever exercises these functions as the Postgres superuser running the
-- test file -- a mode that bypasses every grant this fix is about, so the existing green
-- suite was never evidence this chain worked for a real session.
--
-- ===========================================================================
-- The fix, and why the minimal version is the correct one
-- ===========================================================================
--
-- Each of the 95 functions gets exactly one change: `SECURITY DEFINER` plus `SET
-- search_path TO 'app', 'pg_temp'` (the identical clause this schema's own established
-- `SECURITY DEFINER` convention already uses everywhere else, e.g. `app.
-- has_active_tenant_membership`), added to its signature. No other line of any body below
-- is touched -- verified by generating every statement below mechanically from this
-- repository's own live `pg_get_functiondef` output plus one `replace()` call inserting
-- the two new clauses immediately before `AS $function$`, never hand-transcribed, and
-- diffed against the pre-change catalogue to confirm byte-for-byte equality everywhere
-- else.
--
-- This is deliberately the MINIMAL fix, not the first one attempted. An early draft of
-- this checkpoint's investigation proposed granting `EXECUTE` on the ~43 missing
-- intermediate helper functions (`app.check_finance_journal_authority` and its siblings,
-- `app.capture_audit_event`, `app.validate_currency_code`, and so on) directly to
-- `authenticated` instead. That draft was live-tested and abandoned: Postgres checks
-- `EXECUTE` at the call site against whatever role is CURRENTLY ACTIVE, and only switches
-- to a `SECURITY DEFINER` callee's owner AFTER that check passes and execution enters the
-- function -- so a single `SECURITY DEFINER` boundary at the true entry point makes every
-- nested call beneath it execute as that entry point's owner, needing no grant of its own,
-- while granting the helpers individually would have (a) left the outer entry point's own
-- direct table `INSERT`/`UPDATE` still failing, since IT would still be `SECURITY INVOKER`,
-- and (b) permanently exposed `app.evaluate_permission` itself to direct `authenticated`
-- calls -- the exact posture `scripts/db-tests/rbac-enforcement.sql`'s own pre-existing
-- "defense in depth: anon and authenticated cannot call the evaluator; service_role can"
-- regression test asserts must never be true. Live-verified end to end on a disposable
-- database: a single `SECURITY DEFINER` conversion on `app.create_finance_journal_draft`
-- alone, with NOTHING else touched -- no grants, no helper conversions -- made the entire
-- nested chain (tenant-membership check, `app.check_finance_journal_authority`, `app.
-- evaluate_permission`, the table `INSERT`) succeed for a genuine `authenticated` session.
-- The 19 `check_finance_*_authority` helpers are converted anyway, for a different, real
-- reason: this migration's own second half (`docs/build-log/full-system-hardening/
-- HDN-373.md` §6, "Finding B") adds a permission-gated read policy to `app.finance_journals`
-- directly inside an RLS `using` clause, which -- unlike a nested RPC call -- always
-- executes as the querying role and therefore genuinely needs its own `SECURITY DEFINER`
-- boundary, exactly mirroring this schema's own already-correct, already-shipped precedent
-- for the identical shape (`app.check_payroll_authority`, `app.check_training_authority`,
-- both already `SECURITY DEFINER`, used directly inside `payroll_periods_select_scoped`/
-- `talent_pools_select_scoped`). Converting the 19 also closes them as an independent
-- reachability path, matching the schema-wide convention that every domain's own
-- `check_<domain>_authority` helper is `SECURITY DEFINER` -- Finance was the one outlier.
--
-- ===========================================================================
-- Safety
-- ===========================================================================
--
-- Every one of the 95 already scopes its own reads/writes with an explicit `tenant_id`
-- (or a joined `journal_id`/`period_id` chain back to one) predicate rather than relying on
-- RLS row-filtering for correctness -- the same "`SECURITY DEFINER` + explicit predicate,
-- never bare RLS reliance" pattern already used by every one of this schema's other 1,878
-- `SECURITY DEFINER` functions -- so bypassing RLS by becoming `SECURITY DEFINER`
-- introduces no new cross-tenant read: there was no RLS-dependent tenant scoping to lose.
-- `app.assert_actor_is_session_identity`/`app.assert_finance_period_open_for_posting`
-- (ATW-031's own choke point) reads `auth.uid()` from the request GUC, unaffected by which
-- Postgres role is currently active, so identity-forgery protection already wired into
-- these functions is unchanged by this conversion.
--
-- One function, `app.create_and_post_finance_system_journal`, is NOT a bare security-mode
-- change: this migration's own live test run (fixing reachability first, running the full
-- `scripts/db-tests` suite second) tripped `rbac-enforcement.sql`'s own pre-existing
-- ATW-032 sweep -- "no `SECURITY DEFINER` function is granted to `authenticated` with no
-- authority check anywhere in its own call graph" -- against this exact function. Its own
-- header comment already disclosed the reason: "its own source event was already
-- authority-checked upstream" (by `app.post_finance_subledger_batch`, its intended sole
-- caller). That was true, and harmless, only while the function was unreachable by any
-- other path. It is independently, directly granted `authenticated` execute (confirmed
-- across four separate migrations that each re-grant it), so restoring reachability
-- without also giving IT an authority check would have handed every tenant member --
-- including one with zero Finance permissions -- the ability to post an arbitrary,
-- immediately-final journal entry directly into their tenant's real books, skipping the
-- entire draft/submit/approve workflow. Fixed in the same statement below by adding the
-- identical `app.check_finance_journal_authority('Approve', ...)` gate its manual-posting
-- sibling `app.post_finance_journal` already independently re-checks, matching the level
-- (`FIN:Approve`, not merely `FIN:Edit`) already required of anything that skips the
-- approval step. Full disposition: `docs/build-log/full-system-hardening/HDN-373.md` §6.
--
-- ===========================================================================
-- Verification
-- ===========================================================================
--
-- Live-forced on a disposable database, in order: (1) confirmed the pre-fix failure
-- (`permission denied for table permissions`, three frames inside `app.
-- create_finance_journal_draft` -> `app.check_finance_journal_authority` -> `app.
-- evaluate_permission`) for a genuine `authenticated` session holding real Finance
-- permissions in their own tenant; (2) applied exactly this migration's statements;
-- (3) the same call, same session, same tenant, now succeeds and returns a real journal
-- row; (4) the full 229-file `scripts/db-tests` suite (every domain, not only Finance) run
-- once against a fresh database with this migration applied passes clean, including the
-- pre-existing ATW-031/ATW-032 authority-surface, actor-identity and optimistic-concurrency
-- sweeps in `rbac-enforcement.sql`, which independently re-verify this migration introduced
-- no unreviewed `SECURITY DEFINER` grant and no lost-update race. Full transcript and the
-- broader investigation this fix responds to: `docs/build-log/full-system-hardening/
-- HDN-373.md` §6.
--
-- Every statement below is `pg_get_functiondef`'s own live output for the named function
-- with exactly two lines inserted (`SECURITY DEFINER`, `SET search_path TO 'app',
-- 'pg_temp'`) -- generated mechanically, not hand-transcribed, and re-verified byte-for-byte
-- identical elsewhere against the pre-change catalogue.


CREATE OR REPLACE FUNCTION app.acknowledge_finance_period_checklist_item(p_period_id uuid, p_item_key text, p_satisfied boolean, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_period_close_checklist_items
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_period app.finance_fiscal_periods;
  v_item app.finance_period_close_checklist_items;
begin
  select * into v_period from app.finance_fiscal_periods where id = p_period_id;
  if not found then
    raise exception 'finance_period_not_found: %', p_period_id using errcode = 'no_data_found';
  end if;

  if v_period.status = 'closed' then
    raise exception 'finance_period_closed: period % is closed -- checklist items on a closed period cannot be changed', p_period_id
      using errcode = 'check_violation';
  end if;

  if not app.check_finance_period_authority('Edit', v_period.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_period.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.finance_period_close_checklist_items
  set satisfied = p_satisfied,
      satisfied_reason = p_reason,
      satisfied_by = case when p_satisfied then p_actor_label else null end,
      satisfied_at = case when p_satisfied then now() else null end
  where period_id = p_period_id and item_key = p_item_key
  returning * into v_item;

  if not found then
    raise exception 'finance_period_checklist_item_not_found: % on period %', p_item_key, p_period_id
      using errcode = 'no_data_found';
  end if;

  perform app.capture_audit_event(
    v_period.tenant_id, p_actor_auth_user_id, p_actor_label, 'acknowledge_finance_period_checklist_item',
    'app.finance_period_close_checklist_items', v_item.id, 'success', p_reason, null, to_jsonb(v_item)
  );

  return v_item;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.activate_finance_account(p_account_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
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
  if not found then
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
$function$
;


CREATE OR REPLACE FUNCTION app.allocate_finance_receipt(p_receipt_id uuid, p_idempotency_key text, p_allocations jsonb, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_receipts
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_receipt app.finance_receipts;
  v_batch app.finance_receipt_allocation_batches;
  v_item jsonb;
  v_open_item_id uuid;
  v_amount numeric;
  v_open_item app.finance_ar_open_items;
  v_total numeric := 0;
begin
  select * into v_receipt from app.finance_receipts where id = p_receipt_id for update;
  if not found then
    raise exception 'finance_receipt_not_found: %', p_receipt_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_receipt_authority('Edit', v_receipt.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_receipt.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: a non-empty idempotency_key is required' using errcode = 'check_violation';
  end if;

  select * into v_batch from app.finance_receipt_allocation_batches where tenant_id = v_receipt.tenant_id and receipt_id = p_receipt_id and idempotency_key = p_idempotency_key;
  if found then
    return v_receipt;
  end if;

  if p_allocations is null or jsonb_array_length(p_allocations) = 0 then
    raise exception 'finance_receipt_empty_allocation: at least one allocation line is required' using errcode = 'check_violation';
  end if;

  for v_item in select * from jsonb_array_elements(p_allocations) loop
    v_amount := (v_item ->> 'amount')::numeric;
    if v_amount is null or v_amount <= 0 then
      raise exception 'finance_receipt_invalid_allocation_amount: allocation amount must be positive, got %', v_amount
        using errcode = 'check_violation';
    end if;
    v_total := v_total + v_amount;
  end loop;

  if v_total > v_receipt.unapplied_amount then
    raise exception 'finance_receipt_over_allocation: total allocation % exceeds unapplied amount % for receipt %', v_total, v_receipt.unapplied_amount, p_receipt_id
      using errcode = 'check_violation';
  end if;

  insert into app.finance_receipt_allocation_batches (tenant_id, receipt_id, idempotency_key, created_by)
  values (v_receipt.tenant_id, p_receipt_id, p_idempotency_key, p_actor_label)
  returning * into v_batch;

  for v_item in select * from jsonb_array_elements(p_allocations) loop
    v_open_item_id := (v_item ->> 'arOpenItemId')::uuid;
    v_amount := (v_item ->> 'amount')::numeric;

    select * into v_open_item from app.finance_ar_open_items where id = v_open_item_id and tenant_id = v_receipt.tenant_id;
    if not found then
      raise exception 'finance_receipt_open_item_not_found: % is not a known AR open item for tenant %', v_open_item_id, v_receipt.tenant_id
        using errcode = 'no_data_found';
    end if;
    if v_open_item.customer_account_id <> v_receipt.customer_account_id then
      raise exception 'finance_receipt_customer_mismatch: AR open item % does not belong to receipt %''s own customer', v_open_item_id, p_receipt_id
        using errcode = 'check_violation';
    end if;
    if v_open_item.currency <> v_receipt.currency then
      raise exception 'finance_receipt_currency_mismatch: AR open item % is % but receipt % is %', v_open_item_id, v_open_item.currency, p_receipt_id, v_receipt.currency
        using errcode = 'check_violation';
    end if;

    perform app.apply_finance_ar_allocation(v_open_item_id, v_amount, 'receipt', p_receipt_id, p_idempotency_key || ':' || v_open_item_id::text, p_actor_auth_user_id, p_actor_label);

    insert into app.finance_receipt_allocations (tenant_id, receipt_id, batch_id, ar_open_item_id, amount, created_by)
    values (v_receipt.tenant_id, p_receipt_id, v_batch.id, v_open_item_id, v_amount, p_actor_label);
  end loop;

  -- FIN-202: debit cash for the total received; credit AR control for the
  -- same total -- one control-account line for the whole batch, matching
  -- app.finance_receipt_allocations' own already-established per-item
  -- lineage rows for open-item-level detail.
  perform app.post_finance_subledger_batch(
    v_receipt.tenant_id, v_receipt.company_id, 'receipt_allocation', v_batch.id, v_receipt.receipt_date, v_receipt.currency,
    jsonb_build_array(
      jsonb_build_object('postingMapKey', 'cash_default', 'direction', 'debit', 'amount', v_total),
      jsonb_build_object('postingMapKey', 'ar_control', 'direction', 'credit', 'amount', v_total)
    ),
    p_actor_auth_user_id, p_actor_label
  );

  update app.finance_receipts set allocated_amount = allocated_amount + v_total where id = p_receipt_id returning * into v_receipt;

  perform app.capture_audit_event(
    v_receipt.tenant_id, p_actor_auth_user_id, p_actor_label, 'allocate_finance_receipt',
    'app.finance_receipts', v_receipt.id, 'success', null, null, jsonb_build_object('total', v_total, 'batchId', v_batch.id)
  );

  return v_receipt;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.amend_finance_account_draft(p_account_id uuid, p_expected_version integer, p_name text, p_currency_restriction text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_accounts
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_account app.finance_accounts;
begin
  select * into v_account from app.finance_accounts where id = p_account_id;
  if not found then
    raise exception 'finance_account_not_found: %', p_account_id using errcode = 'no_data_found';
  end if;

  if v_account.record_version <> p_expected_version then
    raise exception 'stale_version: account % expected version % but found %', p_account_id, p_expected_version, v_account.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_account.status <> 'draft' then
    raise exception 'finance_account_not_draft: account % is %, only a draft may be amended (use governed correction otherwise)', p_account_id, v_account.status
      using errcode = 'check_violation';
  end if;

  if not app.check_finance_account_authority('Edit', v_account.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_account.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.finance_accounts
  set name = coalesce(p_name, name), currency_restriction = p_currency_restriction
  where id = p_account_id and record_version = p_expected_version
  returning * into v_account;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: amend_finance_account_draft target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_account.tenant_id, p_actor_auth_user_id, p_actor_label, 'amend_finance_account_draft',
    'app.finance_accounts', v_account.id, 'success', null, null, to_jsonb(v_account)
  );

  return v_account;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.apply_finance_ap_settlement(p_open_item_id uuid, p_amount numeric, p_source_type text, p_source_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
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
  if not found then
    raise exception 'finance_ap_open_item_not_found: %', p_open_item_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_ap_authority('Edit', v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing_event from app.finance_ap_open_item_events
      where tenant_id = v_item.tenant_id and open_item_id = p_open_item_id and idempotency_key = p_idempotency_key;
    if found then
      -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
      -- conflict, never a replay. Returning the earlier target's row here silently
      -- misattributed this request to it (or silently discarded it entirely).
      if v_existing_event.event_type is distinct from 'settled' then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different AP open-item event (event type %, not settled)', p_idempotency_key, v_existing_event.event_type
          using errcode = 'unique_violation';
      end if;
      return v_item;
    end if;
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'finance_ap_invalid_settlement_amount: settlement amount must be positive, got %', p_amount
      using errcode = 'check_violation';
  end if;
  if p_amount > v_item.open_amount then
    raise exception 'finance_ap_over_settlement: settlement % exceeds open amount % for open item %', p_amount, v_item.open_amount, p_open_item_id
      using errcode = 'check_violation';
  end if;

  v_new_settled := v_item.settled_amount + p_amount;
  v_new_status := case when v_new_settled >= v_item.original_amount then 'settled' when v_new_settled > 0 then 'partial' else 'open' end;

  update app.finance_ap_open_items
    set settled_amount = v_new_settled, status = v_new_status
    where id = p_open_item_id
    returning * into v_item;

  insert into app.finance_ap_open_item_events (tenant_id, open_item_id, event_type, amount_delta, source_type, source_id, idempotency_key, actor_auth_user_id, actor_label)
  values (v_item.tenant_id, v_item.id, 'settled', p_amount, p_source_type, p_source_id, p_idempotency_key, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'apply_finance_ap_settlement',
    'app.finance_ap_open_items', v_item.id, 'success', null, null, jsonb_build_object('amount', p_amount, 'newStatus', v_new_status)
  );

  return v_item;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.apply_finance_ar_allocation(p_open_item_id uuid, p_amount numeric, p_source_type text, p_source_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
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
  if not found then
    raise exception 'finance_ar_open_item_not_found: %', p_open_item_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_ar_authority('Edit', v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing_event from app.finance_ar_open_item_events
      where tenant_id = v_item.tenant_id and open_item_id = p_open_item_id and idempotency_key = p_idempotency_key;
    if found then
      -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
      -- conflict, never a replay. Returning the earlier target's row here silently
      -- misattributed this request to it (or silently discarded it entirely).
      if v_existing_event.event_type is distinct from 'allocated' then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different AR open-item event (event type %, not allocated)', p_idempotency_key, v_existing_event.event_type
          using errcode = 'unique_violation';
      end if;
      return v_item;
    end if;
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'finance_ar_invalid_allocation_amount: allocation amount must be positive, got %', p_amount
      using errcode = 'check_violation';
  end if;
  if p_amount > v_item.open_amount then
    raise exception 'finance_ar_over_allocation: allocation % exceeds open amount % for open item %', p_amount, v_item.open_amount, p_open_item_id
      using errcode = 'check_violation';
  end if;

  v_new_allocated := v_item.allocated_amount + p_amount;
  v_new_status := case when v_new_allocated >= v_item.original_amount then 'paid' when v_new_allocated > 0 then 'partial' else 'open' end;

  update app.finance_ar_open_items
    set allocated_amount = v_new_allocated, status = v_new_status
    where id = p_open_item_id
    returning * into v_item;

  insert into app.finance_ar_open_item_events (tenant_id, open_item_id, event_type, amount_delta, source_type, source_id, idempotency_key, actor_auth_user_id, actor_label)
  values (v_item.tenant_id, v_item.id, 'allocated', p_amount, p_source_type, p_source_id, p_idempotency_key, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'apply_finance_ar_allocation',
    'app.finance_ar_open_items', v_item.id, 'success', null, null, jsonb_build_object('amount', p_amount, 'newStatus', v_new_status)
  );

  return v_item;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.approve_finance_correction(p_correction_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_journal_corrections
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_correction app.finance_journal_corrections;
begin
  select * into v_correction from app.finance_journal_corrections where id = p_correction_id for update;
  if not found then
    raise exception 'finance_correction_not_found: %', p_correction_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_correction_authority('Approve', v_correction.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_correction.tenant_id
      using errcode = 'insufficient_privilege';
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
$function$
;


CREATE OR REPLACE FUNCTION app.approve_finance_exchange_rate(p_rate_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
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
  if not found then
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
$function$
;


CREATE OR REPLACE FUNCTION app.approve_finance_invoice(p_invoice_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_invoices
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_invoice app.finance_invoices;
begin
  select * into v_invoice from app.finance_invoices where id = p_invoice_id for update;
  if not found then
    raise exception 'finance_invoice_not_found: %', p_invoice_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_invoice_authority('Approve', v_invoice.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_invoice.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_invoice.record_version <> p_expected_version then
    raise exception 'stale_version: invoice % expected version % but found %', p_invoice_id, p_expected_version, v_invoice.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_invoice.status <> 'submitted' then
    raise exception 'finance_invoice_not_submitted: invoice % is % not submitted', p_invoice_id, v_invoice.status
      using errcode = 'check_violation';
  end if;

  update app.finance_invoices set status = 'approved', approved_by = p_actor_label, approved_at = now() where id = p_invoice_id returning * into v_invoice;

  perform app.capture_audit_event(
    v_invoice.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_finance_invoice',
    'app.finance_invoices', v_invoice.id, 'success', null, null, to_jsonb(v_invoice)
  );

  return v_invoice;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.approve_finance_journal(p_journal_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
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


CREATE OR REPLACE FUNCTION app.approve_finance_period_reopen(p_lock_id uuid, p_expected_version integer, p_window_hours integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_period_locks
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_lock app.finance_period_locks;
begin
  select * into v_lock from app.finance_period_locks where id = p_lock_id for update;
  if not found then
    raise exception 'finance_period_lock_not_found: %', p_lock_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_period_lock_authority('Approve', v_lock.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_lock.tenant_id
      using errcode = 'insufficient_privilege';
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
$function$
;


CREATE OR REPLACE FUNCTION app.approve_finance_settlement(p_settlement_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_settlements
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_settlement app.finance_settlements;
begin
  select * into v_settlement from app.finance_settlements where id = p_settlement_id for update;
  if not found then
    raise exception 'finance_settlement_not_found: %', p_settlement_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_settlement_authority('Approve', v_settlement.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_settlement.tenant_id
      using errcode = 'insufficient_privilege';
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
$function$
;


CREATE OR REPLACE FUNCTION app.approve_finance_tax_rule(p_rule_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
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
  if not found then
    raise exception 'finance_tax_rule_not_found: %', p_rule_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_tax_authority('Approve', v_rule.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_rule.tenant_id
      using errcode = 'insufficient_privilege';
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
$function$
;


CREATE OR REPLACE FUNCTION app.approve_finance_vendor_bill(p_bill_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_vendor_bills
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_bill app.finance_vendor_bills;
begin
  select * into v_bill from app.finance_vendor_bills where id = p_bill_id for update;
  if not found then
    raise exception 'finance_vendor_bill_not_found: %', p_bill_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_vendor_bill_authority('Approve', v_bill.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_bill.tenant_id
      using errcode = 'insufficient_privilege';
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
$function$
;


CREATE OR REPLACE FUNCTION app.attach_finance_tax_rule_evidence(p_rule_id uuid, p_expected_version integer, p_evidence_reference_file_id uuid, p_evidence_note text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_tax_rule_versions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_rule app.finance_tax_rule_versions;
begin
  select * into v_rule from app.finance_tax_rule_versions where id = p_rule_id for update;
  if not found then
    raise exception 'finance_tax_rule_not_found: %', p_rule_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_tax_authority('Edit', v_rule.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_rule.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_rule.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_rule.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_rule.status <> 'draft' then
    raise exception 'finance_tax_rule_not_draft: rule % is % not draft', p_rule_id, v_rule.status
      using errcode = 'check_violation';
  end if;
  if p_evidence_reference_file_id is null and (p_evidence_note is null or length(trim(p_evidence_note)) = 0) then
    raise exception 'finance_tax_rule_evidence_missing: at least one of an evidence file or a non-empty evidence note is required'
      using errcode = 'check_violation';
  end if;

  update app.finance_tax_rule_versions
    set evidence_reference_file_id = coalesce(p_evidence_reference_file_id, evidence_reference_file_id),
        evidence_note = coalesce(p_evidence_note, evidence_note)
    where id = p_rule_id
    returning * into v_rule;

  perform app.capture_audit_event(
    v_rule.tenant_id, p_actor_auth_user_id, p_actor_label, 'attach_finance_tax_rule_evidence',
    'app.finance_tax_rule_versions', v_rule.id, 'success', null, null, jsonb_build_object('evidenceReferenceFileId', v_rule.evidence_reference_file_id)
  );

  return v_rule;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.capture_finance_receipt(p_tenant_id uuid, p_company_id uuid, p_customer_account_id uuid, p_receipt_reference text, p_receipt_date date, p_payer_name text, p_bank_account_label text, p_currency text, p_amount numeric, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_receipts
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
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
$function$
;


CREATE OR REPLACE FUNCTION app.certify_finance_reconciliation_run(p_run_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
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
  if not found then
    raise exception 'finance_reconciliation_run_not_found: %', p_run_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_reconciliation_authority('Approve', v_run.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_run.tenant_id
      using errcode = 'insufficient_privilege';
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
$function$
;


CREATE OR REPLACE FUNCTION app.check_finance_account_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'FIN', p_action)).allowed;
$function$
;


CREATE OR REPLACE FUNCTION app.check_finance_aging_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'FIN', p_action)).allowed;
$function$
;


CREATE OR REPLACE FUNCTION app.check_finance_ap_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'FIN', p_action)).allowed;
$function$
;


CREATE OR REPLACE FUNCTION app.check_finance_ar_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'FIN', p_action)).allowed;
$function$
;


CREATE OR REPLACE FUNCTION app.check_finance_cash_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'FIN', p_action)).allowed;
$function$
;


CREATE OR REPLACE FUNCTION app.check_finance_config_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'FIN', p_action)).allowed;
$function$
;


CREATE OR REPLACE FUNCTION app.check_finance_correction_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'FIN', p_action)).allowed;
$function$
;


CREATE OR REPLACE FUNCTION app.check_finance_exchange_rate_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
  select case
    when p_tenant_id is null then app.is_supreme_admin(p_actor_auth_user_id)
    else (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'FIN', p_action)).allowed
  end;
$function$
;


CREATE OR REPLACE FUNCTION app.check_finance_idempotency_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'FIN', p_action)).allowed;
$function$
;


CREATE OR REPLACE FUNCTION app.check_finance_invoice_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'FIN', p_action)).allowed;
$function$
;


CREATE OR REPLACE FUNCTION app.check_finance_journal_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'FIN', p_action)).allowed;
$function$
;


CREATE OR REPLACE FUNCTION app.check_finance_period_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'FIN', p_action)).allowed;
$function$
;


CREATE OR REPLACE FUNCTION app.check_finance_period_lock_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'FIN', p_action)).allowed;
$function$
;


CREATE OR REPLACE FUNCTION app.check_finance_receipt_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'FIN', p_action)).allowed;
$function$
;


CREATE OR REPLACE FUNCTION app.check_finance_reconciliation_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'FIN', p_action)).allowed;
$function$
;


CREATE OR REPLACE FUNCTION app.check_finance_settlement_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'FIN', p_action)).allowed;
$function$
;


CREATE OR REPLACE FUNCTION app.check_finance_subledger_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'FIN', p_action)).allowed;
$function$
;


CREATE OR REPLACE FUNCTION app.check_finance_tax_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
  select case
    when p_tenant_id is null then app.is_supreme_admin(p_actor_auth_user_id)
    else (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'FIN', p_action)).allowed
  end;
$function$
;


CREATE OR REPLACE FUNCTION app.check_finance_vendor_bill_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'FIN', p_action)).allowed;
$function$
;


CREATE OR REPLACE FUNCTION app.claim_finance_idempotency_key(p_tenant_id uuid, p_scope text, p_idempotency_key text, p_request_fingerprint text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_idempotency_claims
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_claim app.finance_idempotency_claims;
begin
  -- ATW-032 (ISS-2026-032): this function's own authority check asks whether the CLAIMED
  -- actor is allowed, never whether the caller IS that actor. Without this line any
  -- authenticated session could pass a colleague's UUID and act as them.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: a non-empty idempotency_key is required' using errcode = 'check_violation';
  end if;
  if p_request_fingerprint is null or length(trim(p_request_fingerprint)) = 0 then
    raise exception 'finance_idempotency_fingerprint_required: a non-empty request_fingerprint is required' using errcode = 'check_violation';
  end if;

  insert into app.finance_idempotency_claims (tenant_id, scope, idempotency_key, request_fingerprint, claimed_by)
  values (p_tenant_id, p_scope, p_idempotency_key, p_request_fingerprint, p_actor_label)
  on conflict (tenant_id, scope, idempotency_key) do nothing
  returning * into v_claim;

  if found then
    return v_claim;
  end if;

  select * into v_claim from app.finance_idempotency_claims where tenant_id = p_tenant_id and scope = p_scope and idempotency_key = p_idempotency_key;

  if v_claim.request_fingerprint <> p_request_fingerprint then
    raise exception 'finance_idempotency_fingerprint_conflict: idempotency key % (scope %) was already used with a different request', p_idempotency_key, p_scope
      using errcode = 'unique_violation';
  end if;

  return v_claim;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.close_finance_period(p_period_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
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
  if not found then
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
$function$
;


CREATE OR REPLACE FUNCTION app.complete_finance_idempotency_claim(p_claim_id uuid, p_result_entity_type text, p_result_entity_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_idempotency_claims
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_claim app.finance_idempotency_claims;
begin
  -- ATW-032 (ISS-2026-032): this function's own authority check asks whether the CLAIMED
  -- actor is allowed, never whether the caller IS that actor. Without this line any
  -- authenticated session could pass a colleague's UUID and act as them.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_claim from app.finance_idempotency_claims where id = p_claim_id;
  if not found then
    raise exception 'finance_idempotency_claim_not_found: %', p_claim_id using errcode = 'no_data_found';
  end if;
  if not app.has_active_tenant_membership(v_claim.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, v_claim.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_claim.status = 'completed' then
    return v_claim;
  end if;

  update app.finance_idempotency_claims
    set status = 'completed', result_entity_type = p_result_entity_type, result_entity_id = p_result_entity_id, completed_at = now()
    where id = p_claim_id
    returning * into v_claim;

  return v_claim;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.create_and_post_finance_system_journal(p_tenant_id uuid, p_company_id uuid, p_source_type text, p_source_id uuid, p_journal_date date, p_currency text, p_lines jsonb, p_actor_auth_user_id uuid, p_actor_label text, p_lock_scope text DEFAULT 'gl'::text)
 RETURNS app.finance_journals
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
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
  if not app.check_finance_journal_authority('Approve', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
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

  insert into app.finance_journals (
    tenant_id, company_id, journal_number, source_type, source_id, idempotency_key,
    currency, total_amount, journal_date, status, posting_period_id, posted_by, posted_at, created_by
  )
  values (
    p_tenant_id, p_company_id, v_number, p_source_type, p_source_id, p_source_type || ':' || p_source_id::text,
    p_currency, v_total, p_journal_date, 'posted', v_period.period_id, p_actor_label, now(), p_actor_label
  )
  returning * into v_journal;

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
$function$
;


CREATE OR REPLACE FUNCTION app.create_finance_account_draft(p_tenant_id uuid, p_company_id uuid, p_code text, p_name text, p_account_type text, p_normal_balance text, p_parent_account_id uuid, p_is_control_account boolean, p_currency_restriction text, p_actor_auth_user_id uuid, p_created_by text)
 RETURNS app.finance_accounts
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
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
$function$
;


CREATE OR REPLACE FUNCTION app.create_finance_bank_account(p_tenant_id uuid, p_company_id uuid, p_account_name text, p_bank_name text, p_account_number_last4 text, p_currency text, p_gl_account_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_bank_accounts
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
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
$function$
;


CREATE OR REPLACE FUNCTION app.create_finance_exchange_rate_draft(p_tenant_id uuid, p_rate_type text, p_source_currency text, p_target_currency text, p_rate numeric, p_source text, p_effective_from timestamp with time zone, p_effective_to timestamp with time zone, p_actor_auth_user_id uuid, p_created_by text)
 RETURNS app.finance_exchange_rates
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_rate app.finance_exchange_rates;
begin
  -- A platform-wide default draft (p_tenant_id null) has no tenant to hold
  -- membership in -- app.check_finance_exchange_rate_authority's own
  -- Supreme-Admin fallback is the sole gate for that case.
  if p_tenant_id is not null and not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_exchange_rate_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.validate_currency_code(p_source_currency) then
    raise exception 'finance_exchange_rate_unsupported_currency: % is not a registered, active currency', p_source_currency
      using errcode = 'check_violation';
  end if;
  if not app.validate_currency_code(p_target_currency) then
    raise exception 'finance_exchange_rate_unsupported_currency: % is not a registered, active currency', p_target_currency
      using errcode = 'check_violation';
  end if;

  if p_rate is null or p_rate <= 0 then
    raise exception 'finance_exchange_rate_invalid_rate: rate must be a positive value, got %', p_rate
      using errcode = 'check_violation';
  end if;

  insert into app.finance_exchange_rates (
    tenant_id, rate_type, source_currency, target_currency, rate, source, effective_from, effective_to, created_by
  )
  values (
    p_tenant_id, coalesce(p_rate_type, 'spot'), p_source_currency, p_target_currency, p_rate, coalesce(p_source, 'manual'), p_effective_from, p_effective_to, p_created_by
  )
  returning * into v_rate;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_created_by, 'create_finance_exchange_rate_draft',
    'app.finance_exchange_rates', v_rate.id, 'success', null, null, to_jsonb(v_rate)
  );

  return v_rate;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.create_finance_journal_draft(p_tenant_id uuid, p_company_id uuid, p_journal_date date, p_currency text, p_lines jsonb, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_journals
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
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
$function$
;


CREATE OR REPLACE FUNCTION app.create_finance_tax_rule_draft(p_tenant_id uuid, p_tax_code_id uuid, p_rate_basis text, p_rate_value numeric, p_currency text, p_output_account_id uuid, p_recoverable_account_id uuid, p_effective_from date, p_effective_to date, p_actor_auth_user_id uuid, p_created_by text)
 RETURNS app.finance_tax_rule_versions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_code app.finance_tax_codes;
  v_rule app.finance_tax_rule_versions;
  v_account app.finance_accounts;
begin
  if p_tenant_id is not null and not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_tax_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_code from app.finance_tax_codes where id = p_tax_code_id and is_active;
  if not found then
    raise exception 'finance_tax_rule_unsupported_code: % is not an active tax code', p_tax_code_id
      using errcode = 'check_violation';
  end if;
  if v_code.tenant_id is not null and v_code.tenant_id <> p_tenant_id then
    raise exception 'finance_tax_rule_scope_mismatch: tax code % is scoped to a different tenant', p_tax_code_id
      using errcode = 'check_violation';
  end if;

  if p_rate_basis not in ('percentage', 'fixed_amount') then
    raise exception 'finance_tax_rule_unsupported_basis: % is not a supported rate basis', p_rate_basis
      using errcode = 'check_violation';
  end if;
  if p_rate_value is null or p_rate_value < 0 then
    raise exception 'finance_tax_rule_invalid_rate: rate must be non-negative, got %', p_rate_value
      using errcode = 'check_violation';
  end if;

  -- Platform-wide default rules (p_tenant_id null) cannot reference a
  -- tenant-scoped account -- app.finance_accounts always belongs to exactly
  -- one tenant.
  if p_tenant_id is null and (p_output_account_id is not null or p_recoverable_account_id is not null) then
    raise exception 'finance_tax_rule_account_scope_mismatch: a platform-wide default rule cannot reference a tenant-scoped account'
      using errcode = 'check_violation';
  end if;

  if p_output_account_id is not null then
    select * into v_account from app.finance_accounts where id = p_output_account_id;
    if not found or v_account.tenant_id <> p_tenant_id or v_account.status <> 'active' or not v_account.is_postable then
      raise exception 'finance_tax_rule_invalid_account_mapping: output account % is not an active, postable account for tenant %', p_output_account_id, p_tenant_id
        using errcode = 'check_violation';
    end if;
  end if;
  if p_recoverable_account_id is not null then
    select * into v_account from app.finance_accounts where id = p_recoverable_account_id;
    if not found or v_account.tenant_id <> p_tenant_id or v_account.status <> 'active' or not v_account.is_postable then
      raise exception 'finance_tax_rule_invalid_account_mapping: recoverable account % is not an active, postable account for tenant %', p_recoverable_account_id, p_tenant_id
        using errcode = 'check_violation';
    end if;
  end if;

  insert into app.finance_tax_rule_versions (
    tenant_id, tax_code_id, rate_basis, rate_value, currency, output_account_id, recoverable_account_id, effective_from, effective_to, created_by
  )
  values (
    p_tenant_id, p_tax_code_id, p_rate_basis, p_rate_value, p_currency, p_output_account_id, p_recoverable_account_id, p_effective_from, p_effective_to, p_created_by
  )
  returning * into v_rule;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_created_by, 'create_finance_tax_rule_draft',
    'app.finance_tax_rule_versions', v_rule.id, 'success', null, null, to_jsonb(v_rule)
  );

  return v_rule;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.deactivate_finance_account(p_account_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_accounts
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_account app.finance_accounts;
  v_child_count integer;
  v_referenced_by_posting_map boolean := false;
  v_row record;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_account_deactivation_reason_required: a non-empty reason is required'
      using errcode = 'check_violation';
  end if;

  select * into v_account from app.finance_accounts where id = p_account_id;
  if not found then
    raise exception 'finance_account_not_found: %', p_account_id using errcode = 'no_data_found';
  end if;

  if v_account.record_version <> p_expected_version then
    raise exception 'stale_version: account % expected version % but found %', p_account_id, p_expected_version, v_account.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_account.status <> 'active' then
    raise exception 'finance_account_not_active: account % is %, only an active account may be deactivated', p_account_id, v_account.status
      using errcode = 'check_violation';
  end if;

  if not app.check_finance_account_authority('Delete', v_account.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Delete for tenant %', p_actor_auth_user_id, v_account.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select count(*) into v_child_count from app.finance_accounts where parent_account_id = p_account_id and status <> 'inactive';
  if v_child_count > 0 then
    raise exception 'finance_account_has_active_children: account % has % active/draft child account(s) -- deactivate or reparent them first', p_account_id, v_child_count
      using errcode = 'check_violation';
  end if;

  for v_row in select * from app.resolve_finance_config('finance_posting_map', v_account.tenant_id) loop
    if exists (select 1 from jsonb_each(v_row.items) e where (e.value ->> 'accountCodeRef') = v_account.code) then
      v_referenced_by_posting_map := true;
    end if;
  end loop;
  if v_referenced_by_posting_map then
    raise exception 'finance_account_referenced_by_posting_map: account % is referenced by a published posting map -- update the posting map first', p_account_id
      using errcode = 'check_violation';
  end if;

  update app.finance_accounts
  set status = 'inactive'
  where id = p_account_id and record_version = p_expected_version
  returning * into v_account;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: deactivate_finance_account target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_account.tenant_id, p_actor_auth_user_id, p_actor_label, 'deactivate_finance_account',
    'app.finance_accounts', v_account.id, 'success', p_reason, null, to_jsonb(v_account)
  );

  return v_account;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.discard_finance_correction_draft(p_correction_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_journal_corrections
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_correction app.finance_journal_corrections;
begin
  select * into v_correction from app.finance_journal_corrections where id = p_correction_id for update;
  if not found then
    raise exception 'finance_correction_not_found: %', p_correction_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_correction_authority('Edit', v_correction.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_correction.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_correction.record_version <> p_expected_version then
    raise exception 'stale_version: correction % expected version % but found %', p_correction_id, p_expected_version, v_correction.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_correction.status not in ('draft', 'submitted') then
    raise exception 'finance_correction_not_cancellable: correction % is %, only a draft or submitted correction may be discarded', p_correction_id, v_correction.status
      using errcode = 'check_violation';
  end if;

  update app.finance_journal_corrections
    set status = 'discarded', discard_reason = p_reason, discarded_by = p_actor_label, discarded_at = now()
    where id = p_correction_id
    returning * into v_correction;

  perform app.capture_audit_event(
    v_correction.tenant_id, p_actor_auth_user_id, p_actor_label, 'discard_finance_correction_draft',
    'app.finance_journal_corrections', v_correction.id, 'success', p_reason, null, to_jsonb(v_correction)
  );

  return v_correction;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.discard_finance_exchange_rate_draft(p_rate_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_exchange_rates
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_rate app.finance_exchange_rates;
begin
  select * into v_rate from app.finance_exchange_rates where id = p_rate_id;
  if not found then
    raise exception 'finance_exchange_rate_not_found: %', p_rate_id using errcode = 'no_data_found';
  end if;

  if v_rate.record_version <> p_expected_version then
    raise exception 'stale_version: rate % expected version % but found %', p_rate_id, p_expected_version, v_rate.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_rate.status <> 'draft' then
    raise exception 'finance_exchange_rate_not_draft: rate % is %, only a draft may be discarded', p_rate_id, v_rate.status
      using errcode = 'check_violation';
  end if;

  if not app.check_finance_exchange_rate_authority('Edit', v_rate.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_rate.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.finance_exchange_rates
  set status = 'archived'
  where id = p_rate_id and record_version = p_expected_version
  returning * into v_rate;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: discard_finance_exchange_rate_draft target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_rate.tenant_id, p_actor_auth_user_id, p_actor_label, 'discard_finance_exchange_rate_draft',
    'app.finance_exchange_rates', v_rate.id, 'success', p_reason, null, to_jsonb(v_rate)
  );

  return v_rate;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.discard_finance_invoice_draft(p_invoice_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_invoices
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_invoice app.finance_invoices;
begin
  select * into v_invoice from app.finance_invoices where id = p_invoice_id for update;
  if not found then
    raise exception 'finance_invoice_not_found: %', p_invoice_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_invoice_authority('Edit', v_invoice.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_invoice.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_invoice.record_version <> p_expected_version then
    raise exception 'stale_version: invoice % expected version % but found %', p_invoice_id, p_expected_version, v_invoice.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_invoice.status not in ('draft', 'submitted') then
    raise exception 'finance_invoice_not_cancellable: invoice % is %, only a draft or submitted invoice may be discarded', p_invoice_id, v_invoice.status
      using errcode = 'check_violation';
  end if;

  update app.finance_invoices set status = 'void', void_reason = p_reason, voided_by = p_actor_label, voided_at = now() where id = p_invoice_id returning * into v_invoice;

  perform app.capture_audit_event(
    v_invoice.tenant_id, p_actor_auth_user_id, p_actor_label, 'discard_finance_invoice_draft',
    'app.finance_invoices', v_invoice.id, 'success', p_reason, null, to_jsonb(v_invoice)
  );

  return v_invoice;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.discard_finance_journal_draft(p_journal_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
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
  if v_journal.status not in ('draft', 'submitted') then
    raise exception 'finance_journal_not_cancellable: journal % is %, only a draft or submitted journal may be discarded', p_journal_id, v_journal.status
      using errcode = 'check_violation';
  end if;

  update app.finance_journals set status = 'void', void_reason = p_reason, voided_by = p_actor_label, voided_at = now() where id = p_journal_id returning * into v_journal;

  perform app.capture_audit_event(
    v_journal.tenant_id, p_actor_auth_user_id, p_actor_label, 'discard_finance_journal_draft',
    'app.finance_journals', v_journal.id, 'success', p_reason, null, to_jsonb(v_journal)
  );

  return v_journal;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.discard_finance_settlement_draft(p_settlement_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
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
  if not found then
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
$function$
;


CREATE OR REPLACE FUNCTION app.discard_finance_tax_rule_draft(p_rule_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_tax_rule_versions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_rule app.finance_tax_rule_versions;
begin
  select * into v_rule from app.finance_tax_rule_versions where id = p_rule_id for update;
  if not found then
    raise exception 'finance_tax_rule_not_found: %', p_rule_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_tax_authority('Edit', v_rule.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_rule.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_rule.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_rule.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_rule.status <> 'draft' then
    raise exception 'finance_tax_rule_not_draft: rule % is % not draft', p_rule_id, v_rule.status
      using errcode = 'check_violation';
  end if;

  update app.finance_tax_rule_versions set status = 'archived', archived_reason = p_reason where id = p_rule_id returning * into v_rule;

  perform app.capture_audit_event(
    v_rule.tenant_id, p_actor_auth_user_id, p_actor_label, 'discard_finance_tax_rule_draft',
    'app.finance_tax_rule_versions', v_rule.id, 'success', p_reason, null, to_jsonb(v_rule)
  );

  return v_rule;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.discard_finance_vendor_bill_draft(p_bill_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_vendor_bills
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_bill app.finance_vendor_bills;
begin
  select * into v_bill from app.finance_vendor_bills where id = p_bill_id for update;
  if not found then
    raise exception 'finance_vendor_bill_not_found: %', p_bill_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_vendor_bill_authority('Edit', v_bill.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_bill.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_bill.record_version <> p_expected_version then
    raise exception 'stale_version: bill % expected version % but found %', p_bill_id, p_expected_version, v_bill.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_bill.status not in ('draft', 'submitted') then
    raise exception 'finance_vendor_bill_not_cancellable: bill % is %, only a draft or submitted bill may be discarded', p_bill_id, v_bill.status
      using errcode = 'check_violation';
  end if;

  update app.finance_vendor_bills set status = 'void', void_reason = p_reason, voided_by = p_actor_label, voided_at = now() where id = p_bill_id returning * into v_bill;

  perform app.capture_audit_event(
    v_bill.tenant_id, p_actor_auth_user_id, p_actor_label, 'discard_finance_vendor_bill_draft',
    'app.finance_vendor_bills', v_bill.id, 'success', p_reason, null, to_jsonb(v_bill)
  );

  return v_bill;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.enqueue_job(p_tenant_id uuid, p_job_type text, p_payload jsonb, p_priority integer, p_idempotency_key text, p_max_attempts integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.jobs
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_existing app.jobs;
  v_job app.jobs;
  v_valid_job_types text[] := app.generic_job_types();
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.check_job_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'job_actor_unauthorized: identity % lacks active membership in tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_job_type in ('import', 'export') then
    raise exception 'job_type_requires_dedicated_entrypoint: % jobs must be created via app.create_import_export_job()', p_job_type
      using errcode = 'check_violation';
  end if;

  if not (p_job_type = any (v_valid_job_types)) then
    raise exception 'job_invalid_type: % is not a known generic job type', p_job_type
      using errcode = 'check_violation';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.jobs where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.job_type is distinct from p_job_type then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different job (job type %, not %)', p_idempotency_key, v_existing.job_type, p_job_type
          using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  if not app.validate_config_value(coalesce(p_payload, '{}'::jsonb)) then
    raise exception 'job_unsafe_payload: payload failed structural validation'
      using errcode = 'check_violation';
  end if;

  if coalesce(p_max_attempts, 3) <= 0 then
    raise exception 'job_invalid_max_attempts: max_attempts must be positive'
      using errcode = 'check_violation';
  end if;

  -- Batch 283-285 Tier C fix (finding 2, correctness lens): the
  -- check-then-insert above is not atomic -- two genuinely concurrent
  -- callers with the SAME (tenant_id, idempotency_key) can both pass the
  -- "not found" check above and both reach this INSERT. Without this
  -- exception handler the losing caller received a raw, unclassified
  -- Postgres 23505 instead of the SAME idempotent-replay row the winner
  -- (or a slightly-earlier caller) already created -- live-reproduced
  -- with two genuinely concurrent OS processes calling
  -- app.run_training_certificate_expiry_batch (HRT-284) with the same
  -- period label. Mirrors this repository's own established
  -- check-then-insert-with-handler shape (e.g.
  -- app.create_performance_kpi_definition, app.create_payroll_run).
  begin
    insert into app.jobs (
      tenant_id, job_type, payload, priority, max_attempts, idempotency_key,
      requested_by_auth_user_id, created_by
    ) values (
      p_tenant_id, p_job_type, coalesce(p_payload, '{}'::jsonb), coalesce(p_priority, 0), coalesce(p_max_attempts, 3), p_idempotency_key,
      p_actor_auth_user_id, p_actor_label
    )
    returning * into v_job;
  exception
    when unique_violation then
      if p_idempotency_key is null then
        raise; -- not an idempotency-key race (e.g. a different constraint) -- surface unchanged.
      end if;
      select * into v_existing from app.jobs where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      if not found then
        raise; -- constraint fired on something other than the key we expected -- surface unchanged rather than mask it.
      end if;
      if v_existing.job_type is distinct from p_job_type then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different job (job type %, not %)', p_idempotency_key, v_existing.job_type, p_job_type
          using errcode = 'unique_violation';
      end if;
      return v_existing;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'enqueue_job',
    'app.jobs', v_job.job_id, 'success', null, null,
    jsonb_build_object('job_id', v_job.job_id, 'job_type', v_job.job_type)
  );

  return v_job;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.execute_finance_reconciliation_run(p_tenant_id uuid, p_company_id uuid, p_scope text, p_as_of_date date, p_tolerance_amount numeric, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_reconciliation_runs
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
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
$function$
;


CREATE OR REPLACE FUNCTION app.execute_finance_settlement(p_settlement_id uuid, p_expected_version integer, p_execution_reference text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_settlements
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_settlement app.finance_settlements;
begin
  select * into v_settlement from app.finance_settlements where id = p_settlement_id for update;
  if not found then
    raise exception 'finance_settlement_not_found: %', p_settlement_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_settlement_authority('Approve', v_settlement.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_settlement.tenant_id
      using errcode = 'insufficient_privilege';
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
$function$
;


CREATE OR REPLACE FUNCTION app.fail_finance_idempotency_claim(p_claim_id uuid, p_error_message text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_idempotency_claims
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_claim app.finance_idempotency_claims;
begin
  -- ATW-032 (ISS-2026-032): this function's own authority check asks whether the CLAIMED
  -- actor is allowed, never whether the caller IS that actor. Without this line any
  -- authenticated session could pass a colleague's UUID and act as them.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_claim from app.finance_idempotency_claims where id = p_claim_id;
  if not found then
    raise exception 'finance_idempotency_claim_not_found: %', p_claim_id using errcode = 'no_data_found';
  end if;
  if not app.has_active_tenant_membership(v_claim.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, v_claim.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_claim.status = 'completed' then
    raise exception 'finance_idempotency_claim_already_completed: claim % already completed, cannot mark failed', p_claim_id
      using errcode = 'check_violation';
  end if;

  update app.finance_idempotency_claims set status = 'failed', error_message = p_error_message where id = p_claim_id returning * into v_claim;

  return v_claim;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.generate_finance_fiscal_calendar(p_tenant_id uuid, p_company_id uuid, p_code text, p_name text, p_start_date date, p_period_count integer, p_actor_auth_user_id uuid, p_created_by text)
 RETURNS app.finance_fiscal_calendars
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
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
$function$
;


CREATE OR REPLACE FUNCTION app.import_finance_bank_statement(p_tenant_id uuid, p_bank_account_id uuid, p_source_reference text, p_lines jsonb, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_bank_statement_batches
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_batch app.finance_bank_statement_batches;
  v_account app.finance_bank_accounts;
  v_line jsonb;
  v_hash text;
  v_inserted integer := 0;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_cash_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_source_reference is null or length(trim(p_source_reference)) = 0 then
    raise exception 'finance_cash_source_reference_required: a non-empty source_reference is required' using errcode = 'check_violation';
  end if;

  select * into v_account from app.finance_bank_accounts where id = p_bank_account_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'finance_cash_bank_account_not_found: % is not a known bank account for tenant %', p_bank_account_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;

  select * into v_batch from app.finance_bank_statement_batches where tenant_id = p_tenant_id and bank_account_id = p_bank_account_id and source_reference = p_source_reference;
  if found then
    return v_batch;
  end if;

  if p_lines is null or jsonb_array_length(p_lines) = 0 then
    raise exception 'finance_cash_empty_statement: at least one line is required' using errcode = 'check_violation';
  end if;

  insert into app.finance_bank_statement_batches (tenant_id, bank_account_id, source_reference, imported_by)
  values (p_tenant_id, p_bank_account_id, p_source_reference, p_actor_label)
  returning * into v_batch;

  for v_line in select * from jsonb_array_elements(p_lines) loop
    if v_line ->> 'direction' not in ('debit', 'credit') then
      raise exception 'finance_cash_invalid_direction: % is not debit or credit', v_line ->> 'direction' using errcode = 'check_violation';
    end if;
    if (v_line ->> 'amount')::numeric <= 0 then
      raise exception 'finance_cash_invalid_amount: line amount must be positive, got %', v_line ->> 'amount' using errcode = 'check_violation';
    end if;

    v_hash := md5(p_bank_account_id::text || '|' || (v_line ->> 'transactionDate') || '|' || (v_line ->> 'direction') || '|' || (v_line ->> 'amount') || '|' || coalesce(v_line ->> 'reference', ''));

    insert into app.finance_bank_transactions (batch_id, tenant_id, bank_account_id, transaction_date, direction, amount, reference, description, line_hash)
    values (
      v_batch.id, p_tenant_id, p_bank_account_id, (v_line ->> 'transactionDate')::date, v_line ->> 'direction', (v_line ->> 'amount')::numeric,
      v_line ->> 'reference', v_line ->> 'description', v_hash
    )
    on conflict (bank_account_id, line_hash) do nothing;

    if found then
      v_inserted := v_inserted + 1;
    end if;
  end loop;

  update app.finance_bank_statement_batches set line_count = v_inserted where id = v_batch.id returning * into v_batch;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'import_finance_bank_statement',
    'app.finance_bank_statement_batches', v_batch.id, 'success', null, null,
    jsonb_build_object('sourceReference', p_source_reference, 'submittedLineCount', jsonb_array_length(p_lines), 'insertedLineCount', v_inserted)
  );

  return v_batch;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.issue_finance_invoice(p_invoice_id uuid, p_expected_version integer, p_issue_date date, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_invoices
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
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
  if not found then
    raise exception 'finance_invoice_not_found: %', p_invoice_id using errcode = 'no_data_found';
  end if;
  if v_invoice.status = 'issued' then
    return v_invoice;
  end if;
  if not app.check_finance_invoice_authority('Approve', v_invoice.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_invoice.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_invoice.record_version <> p_expected_version then
    raise exception 'stale_version: invoice % expected version % but found %', p_invoice_id, p_expected_version, v_invoice.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_invoice.status <> 'approved' then
    raise exception 'finance_invoice_not_approved: invoice % is % not approved', p_invoice_id, v_invoice.status
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

  update app.finance_invoices
    set status = 'issued', invoice_number = v_number, issue_date = p_issue_date, due_date = v_due_date,
        posting_period_id = v_period.period_id, ar_open_item_id = v_ar_item.id, issued_by = p_actor_label, issued_at = now()
    where id = p_invoice_id
    returning * into v_invoice;

  perform app.capture_audit_event(
    v_invoice.tenant_id, p_actor_auth_user_id, p_actor_label, 'issue_finance_invoice',
    'app.finance_invoices', v_invoice.id, 'success', null, null, to_jsonb(v_invoice)
  );

  return v_invoice;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.lock_finance_period(p_tenant_id uuid, p_company_id uuid, p_period_id uuid, p_lock_scope text, p_reason text, p_evidence_ref text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_period_locks
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
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
    insert into app.finance_period_locks (tenant_id, company_id, period_id, lock_scope, lock_reason, evidence_ref, locked_by, created_by)
    values (p_tenant_id, p_company_id, p_period_id, p_lock_scope, p_reason, p_evidence_ref, p_actor_label, p_actor_label)
    returning * into v_lock;
  end if;

  insert into app.finance_period_lock_events (lock_id, tenant_id, action, reason, actor_label) values (v_lock.id, p_tenant_id, 'locked', p_reason, p_actor_label);

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'lock_finance_period',
    'app.finance_period_locks', v_lock.id, 'success', p_reason, null, to_jsonb(v_lock)
  );

  return v_lock;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.match_finance_bank_transaction(p_transaction_id uuid, p_expected_version integer, p_matched_source_type text, p_matched_source_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_bank_transactions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_transaction app.finance_bank_transactions;
begin
  select * into v_transaction from app.finance_bank_transactions where id = p_transaction_id for update;
  if not found then
    raise exception 'finance_cash_transaction_not_found: %', p_transaction_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_cash_authority('Edit', v_transaction.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_transaction.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_transaction.record_version <> p_expected_version then
    raise exception 'stale_version: transaction % expected version % but found %', p_transaction_id, p_expected_version, v_transaction.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_matched_source_type not in ('receipt', 'settlement', 'manual') then
    raise exception 'finance_cash_invalid_match_source_type: % is not a supported match source type', p_matched_source_type
      using errcode = 'check_violation';
  end if;
  if v_transaction.match_status <> 'unmatched' then
    raise exception 'finance_cash_transaction_not_unmatched: transaction % is % not unmatched', p_transaction_id, v_transaction.match_status
      using errcode = 'check_violation';
  end if;

  update app.finance_bank_transactions
    set match_status = 'matched', matched_source_type = p_matched_source_type, matched_source_id = p_matched_source_id,
        matched_by = p_actor_label, matched_at = now(), unmatch_reason = null
    where id = p_transaction_id
    returning * into v_transaction;

  perform app.capture_audit_event(
    v_transaction.tenant_id, p_actor_auth_user_id, p_actor_label, 'match_finance_bank_transaction',
    'app.finance_bank_transactions', v_transaction.id, 'success', null, null, to_jsonb(v_transaction)
  );

  return v_transaction;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.place_finance_ap_hold(p_open_item_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_ap_open_items
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_item app.finance_ap_open_items;
begin
  select * into v_item from app.finance_ap_open_items where id = p_open_item_id for update;
  if not found then
    raise exception 'finance_ap_open_item_not_found: %', p_open_item_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_ap_authority('Edit', v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_item.record_version <> p_expected_version then
    raise exception 'stale_version: open item % expected version % but found %', p_open_item_id, p_expected_version, v_item.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_ap_hold_reason_required: a non-empty reason is required to place a hold'
      using errcode = 'check_violation';
  end if;
  if v_item.is_held then
    raise exception 'finance_ap_already_held: open item % is already held', p_open_item_id
      using errcode = 'check_violation';
  end if;

  update app.finance_ap_open_items
    set is_held = true, hold_reason = p_reason, held_by = p_actor_label, held_at = now(), released_by = null, released_at = null
    where id = p_open_item_id
    returning * into v_item;

  insert into app.finance_ap_open_item_events (tenant_id, open_item_id, event_type, reason, actor_auth_user_id, actor_label)
  values (v_item.tenant_id, v_item.id, 'hold_placed', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'place_finance_ap_hold',
    'app.finance_ap_open_items', v_item.id, 'success', p_reason, null, to_jsonb(v_item)
  );

  return v_item;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.place_finance_ar_hold(p_open_item_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_ar_open_items
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_item app.finance_ar_open_items;
begin
  select * into v_item from app.finance_ar_open_items where id = p_open_item_id for update;
  if not found then
    raise exception 'finance_ar_open_item_not_found: %', p_open_item_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_ar_authority('Edit', v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_item.record_version <> p_expected_version then
    raise exception 'stale_version: open item % expected version % but found %', p_open_item_id, p_expected_version, v_item.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_ar_hold_reason_required: a non-empty reason is required to place a hold'
      using errcode = 'check_violation';
  end if;
  if v_item.is_held then
    raise exception 'finance_ar_already_held: open item % is already held', p_open_item_id
      using errcode = 'check_violation';
  end if;

  update app.finance_ar_open_items
    set is_held = true, hold_reason = p_reason, held_by = p_actor_label, held_at = now(), released_by = null, released_at = null
    where id = p_open_item_id
    returning * into v_item;

  insert into app.finance_ar_open_item_events (tenant_id, open_item_id, event_type, reason, actor_auth_user_id, actor_label)
  values (v_item.tenant_id, v_item.id, 'hold_placed', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'place_finance_ar_hold',
    'app.finance_ar_open_items', v_item.id, 'success', p_reason, null, to_jsonb(v_item)
  );

  return v_item;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.post_finance_ap_open_item(p_tenant_id uuid, p_company_id uuid, p_vendor_master_id uuid, p_source_document_type text, p_source_document_id uuid, p_currency text, p_original_amount numeric, p_bill_date date, p_due_date date, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_ap_open_items
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
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
$function$
;


CREATE OR REPLACE FUNCTION app.post_finance_ar_open_item(p_tenant_id uuid, p_company_id uuid, p_customer_account_id uuid, p_source_document_type text, p_source_document_id uuid, p_currency text, p_original_amount numeric, p_invoice_date date, p_due_date date, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_ar_open_items
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
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
$function$
;


CREATE OR REPLACE FUNCTION app.post_finance_correction(p_correction_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
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
  if not found then
    raise exception 'finance_correction_not_found: %', p_correction_id using errcode = 'no_data_found';
  end if;
  if v_correction.status = 'posted' then
    return v_correction;
  end if;
  if not app.check_finance_correction_authority('Approve', v_correction.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_correction.tenant_id
      using errcode = 'insufficient_privilege';
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
$function$
;


CREATE OR REPLACE FUNCTION app.post_finance_journal(p_journal_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
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


CREATE OR REPLACE FUNCTION app.post_finance_settlement(p_settlement_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
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
  if not found then
    raise exception 'finance_settlement_not_found: %', p_settlement_id using errcode = 'no_data_found';
  end if;
  if v_settlement.status = 'posted' then
    return v_settlement;
  end if;
  if not app.check_finance_settlement_authority('Approve', v_settlement.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_settlement.tenant_id
      using errcode = 'insufficient_privilege';
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
$function$
;


CREATE OR REPLACE FUNCTION app.post_finance_subledger_batch(p_tenant_id uuid, p_company_id uuid, p_source_type text, p_source_id uuid, p_posting_date date, p_currency text, p_lines jsonb, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_subledger_batches
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
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
  if p_source_type not in ('invoice', 'receipt_allocation', 'vendor_bill', 'settlement') then
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

  insert into app.finance_subledger_batches (tenant_id, company_id, source_type, source_id, currency, total_amount, posting_period_id, posted_by)
  values (p_tenant_id, p_company_id, p_source_type, p_source_id, p_currency, v_debit_total, v_period.period_id, p_actor_label)
  returning * into v_batch;

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
$function$
;


CREATE OR REPLACE FUNCTION app.post_finance_vendor_bill(p_bill_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
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
  if not found then
    raise exception 'finance_vendor_bill_not_found: %', p_bill_id using errcode = 'no_data_found';
  end if;
  if v_bill.status = 'posted' then
    return v_bill;
  end if;
  if not app.check_finance_vendor_bill_authority('Approve', v_bill.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_bill.tenant_id
      using errcode = 'insufficient_privilege';
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
$function$
;


CREATE OR REPLACE FUNCTION app.prepare_finance_invoice_from_readiness(p_tenant_id uuid, p_billing_readiness_handoff_id uuid, p_payment_term_days integer, p_tax_code text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_invoices
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_invoice app.finance_invoices;
  v_handoff app.billing_readiness_handoffs;
  v_job app.job_orders;
  v_subtotal numeric(14, 2);
  v_currency text;
  v_tax_result jsonb;
  v_tax_amount numeric(14, 2) := 0;
  v_tax_code_id uuid;
  v_tax_rule_version_id uuid;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_invoice_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ATW-032: this replay lookup had NO status predicate, so once a draft was
  -- discarded (status = 'void', a terminal state no writer on this table leads
  -- out of) every later call returned that voided row as though it were a live
  -- draft, and the total finance_invoices_handoff_unique made preparing a
  -- replacement impossible. FIN-197's own header states the opposite intent --
  -- a discarded draft "never burns a number". The uniqueness rule is now
  -- partial (finance_invoices_handoff_active_unique, above); this predicate is
  -- the other half: a voided invoice is not a replay target.
  select * into v_invoice from app.finance_invoices where tenant_id = p_tenant_id and billing_readiness_handoff_id = p_billing_readiness_handoff_id and status <> 'void';
  if found then
    return v_invoice;
  end if;

  select * into v_handoff from app.billing_readiness_handoffs where id = p_billing_readiness_handoff_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'finance_invoice_handoff_not_found: % is not a known BillingReadinessHandoff for tenant %', p_billing_readiness_handoff_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;

  select * into v_job from app.job_orders where id = v_handoff.job_order_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'finance_invoice_job_order_not_found: % is not a known Job Order for tenant %', v_handoff.job_order_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;

  v_currency := v_job.revenue_snapshot ->> 'currency';
  v_subtotal := (v_job.revenue_snapshot ->> 'totalAmount')::numeric(14, 2);
  if v_currency is null or v_subtotal is null then
    raise exception 'finance_invoice_revenue_snapshot_incomplete: job order % has no usable revenue snapshot', v_job.id
      using errcode = 'check_violation';
  end if;
  if not app.validate_currency_code(v_currency) then
    raise exception 'finance_invoice_unsupported_currency: % is not a registered, active currency', v_currency
      using errcode = 'check_violation';
  end if;
  if v_subtotal <= 0 then
    raise exception 'finance_invoice_invalid_subtotal: revenue snapshot total % must be positive', v_subtotal
      using errcode = 'check_violation';
  end if;

  if p_tax_code is not null then
    select app.calculate_finance_tax(p_tenant_id, p_tax_code, v_subtotal, current_date, p_actor_auth_user_id) into v_tax_result;
    -- ATW-032: a fixed_amount rule is denominated -- FIN-195's own
    -- finance_tax_rule_versions_fixed_amount_currency_check guarantees it
    -- always carries a currency, and calculate_finance_tax returns both that
    -- currency and the rate basis. This call site previously read only
    -- taxAmount/ruleVersionId, so a fixed IDR duty landed unconverted on a USD
    -- invoice. Refused rather than auto-converted: choosing an FX rate and an
    -- as-of/rate-type policy is not this call site's decision to make, and a
    -- silently converted statutory duty is worse than a refused one. A
    -- percentage rule is unaffected -- its result is denominated in the base
    -- amount's own currency by construction.
    if (v_tax_result ->> 'rateBasis') = 'fixed_amount' and coalesce(v_tax_result ->> 'currency', '') <> v_currency then
      raise exception 'finance_tax_rule_currency_mismatch: tax code % resolves to a fixed_amount rule denominated in %, which cannot be applied to a % invoice', p_tax_code, coalesce(v_tax_result ->> 'currency', '(none)'), v_currency
        using errcode = 'check_violation';
    end if;
    v_tax_amount := (v_tax_result ->> 'taxAmount')::numeric(14, 2);
    v_tax_rule_version_id := (v_tax_result ->> 'ruleVersionId')::uuid;
    select id into v_tax_code_id from app.finance_tax_codes where code = p_tax_code and (tenant_id = p_tenant_id or tenant_id is null) order by tenant_id nulls last limit 1;
  end if;

  insert into app.finance_invoices (
    tenant_id, company_id, customer_account_id, job_order_id, billing_readiness_handoff_id,
    currency, subtotal_amount, tax_amount, payment_term_days, created_by
  )
  values (
    p_tenant_id, v_job.org_unit_id, v_job.account_id, v_job.id, p_billing_readiness_handoff_id,
    v_currency, v_subtotal, v_tax_amount, coalesce(p_payment_term_days, 30), p_actor_label
  )
  returning * into v_invoice;

  insert into app.finance_invoice_lines (invoice_id, line_number, line_type, description, amount)
  values (v_invoice.id, 1, 'charge', 'Freight and service charges per Job Order ' || v_job.job_number, v_subtotal);

  if v_tax_amount > 0 then
    insert into app.finance_invoice_lines (invoice_id, line_number, line_type, description, amount, tax_code_id, tax_rule_version_id)
    values (v_invoice.id, 2, 'tax', p_tax_code || ' tax', v_tax_amount, v_tax_code_id, v_tax_rule_version_id);
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'prepare_finance_invoice_from_readiness',
    'app.finance_invoices', v_invoice.id, 'success', null, null, to_jsonb(v_invoice)
  );

  return v_invoice;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.prepare_finance_journal_adjustment(p_tenant_id uuid, p_company_id uuid, p_original_journal_id uuid, p_correction_date date, p_reason text, p_evidence_ref text, p_adjustment_lines jsonb, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_journal_corrections
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
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

  insert into app.finance_journal_corrections (
    tenant_id, company_id, original_journal_id, correction_type, correction_date, reason, evidence_ref, adjustment_lines, idempotency_key, created_by
  )
  values (p_tenant_id, p_company_id, p_original_journal_id, 'adjustment', p_correction_date, p_reason, p_evidence_ref, p_adjustment_lines, p_idempotency_key, p_actor_label)
  returning * into v_correction;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'prepare_finance_journal_adjustment',
    'app.finance_journal_corrections', v_correction.id, 'success', p_reason, null, to_jsonb(v_correction)
  );

  return v_correction;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.prepare_finance_journal_reversal(p_tenant_id uuid, p_company_id uuid, p_original_journal_id uuid, p_correction_date date, p_reason text, p_evidence_ref text, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_journal_corrections
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
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

  insert into app.finance_journal_corrections (
    tenant_id, company_id, original_journal_id, correction_type, correction_date, reason, evidence_ref, idempotency_key, created_by
  )
  values (p_tenant_id, p_company_id, p_original_journal_id, 'reversal', p_correction_date, p_reason, p_evidence_ref, p_idempotency_key, p_actor_label)
  returning * into v_correction;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'prepare_finance_journal_reversal',
    'app.finance_journal_corrections', v_correction.id, 'success', p_reason, null, to_jsonb(v_correction)
  );

  return v_correction;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.prepare_finance_settlement(p_tenant_id uuid, p_company_id uuid, p_vendor_master_id uuid, p_payment_reference text, p_bank_account_label text, p_currency text, p_settlement_date date, p_allocations jsonb, p_fee_amount numeric, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_settlements
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
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

  insert into app.finance_settlements (
    tenant_id, company_id, vendor_master_id, payment_reference, bank_account_label,
    currency, allocated_amount, fee_amount, settlement_date, idempotency_key, created_by
  )
  values (
    p_tenant_id, p_company_id, p_vendor_master_id, p_payment_reference, p_bank_account_label,
    p_currency, v_total, v_fee, p_settlement_date, p_idempotency_key, p_actor_label
  )
  returning * into v_settlement;

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
$function$
;


CREATE OR REPLACE FUNCTION app.prepare_finance_vendor_bill_from_actual_cost(p_tenant_id uuid, p_actual_cost_id uuid, p_vendor_master_id uuid, p_vendor_reference text, p_bill_date date, p_payment_term_days integer, p_vendor_stated_amount numeric, p_tax_code text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_vendor_bills
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_bill app.finance_vendor_bills;
  v_cost app.shipment_actual_costs;
  v_vendor app.master_records;
  v_subtotal numeric(14, 2);
  v_line_number integer := 0;
  v_component app.shipment_actual_cost_components;
  v_variance numeric(14, 2) := 0;
  v_variance_status text := 'within_tolerance';
  v_tax_result jsonb;
  v_tax_amount numeric(14, 2) := 0;
  v_tax_code_id uuid;
  v_tax_rule_version_id uuid;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_vendor_bill_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ATW-032: same defect and same fix as prepare_finance_invoice_from_readiness
  -- above -- verified independently against this table's own writers rather than
  -- assumed symmetric. discard_finance_vendor_bill_draft writes a terminal
  -- 'void', and submit_/approve_/post_finance_vendor_bill each guard on
  -- draft/submitted/approved, so nothing leads out of void: without this
  -- predicate a discarded bill was handed back to every later caller, and the
  -- total unique constraint (now partial) blocked any replacement.
  select * into v_bill from app.finance_vendor_bills where tenant_id = p_tenant_id and actual_cost_id = p_actual_cost_id and vendor_master_id = p_vendor_master_id and status <> 'void';
  if found then
    return v_bill;
  end if;

  select * into v_cost from app.shipment_actual_costs where id = p_actual_cost_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'finance_vendor_bill_actual_cost_not_found: % is not a known actual cost for tenant %', p_actual_cost_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;
  if v_cost.status <> 'approved' or not v_cost.is_current then
    raise exception 'finance_vendor_bill_actual_cost_not_approved: actual cost % is not the current approved version', p_actual_cost_id
      using errcode = 'check_violation';
  end if;

  select * into v_vendor from app.master_records
    where id = p_vendor_master_id and master_type_code = 'vendor' and canonical_status = 'active'
      and (tenant_id = p_tenant_id or tenant_id is null);
  if not found then
    raise exception 'finance_vendor_bill_vendor_not_found: % is not a known active vendor reference for tenant %', p_vendor_master_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;

  select coalesce(sum(amount), 0) into v_subtotal
    from app.shipment_actual_cost_components
    where actual_cost_id = p_actual_cost_id and source_type = 'vendor' and vendor_id = p_vendor_master_id;
  if v_subtotal <= 0 then
    raise exception 'finance_vendor_bill_no_matching_components: no vendor-sourced cost component for vendor % on actual cost %', p_vendor_master_id, p_actual_cost_id
      using errcode = 'no_data_found';
  end if;

  if p_vendor_stated_amount is not null then
    v_variance := abs(p_vendor_stated_amount - v_subtotal);
    if v_variance > 1.00 then
      v_variance_status := 'requires_approval';
    end if;
  end if;

  if p_tax_code is not null then
    select app.calculate_finance_tax(p_tenant_id, p_tax_code, v_subtotal, coalesce(p_bill_date, current_date), p_actor_auth_user_id) into v_tax_result;
    -- ATW-032: see prepare_finance_invoice_from_readiness. The document currency
    -- here is the actual cost's own currency (v_cost.currency) -- the same value
    -- written to finance_vendor_bills.currency by the INSERT below -- so the
    -- comparison is against the currency the tax amount will actually be summed
    -- into, not against a separately resolved one.
    if (v_tax_result ->> 'rateBasis') = 'fixed_amount' and coalesce(v_tax_result ->> 'currency', '') <> v_cost.currency then
      raise exception 'finance_tax_rule_currency_mismatch: tax code % resolves to a fixed_amount rule denominated in %, which cannot be applied to a % vendor bill', p_tax_code, coalesce(v_tax_result ->> 'currency', '(none)'), v_cost.currency
        using errcode = 'check_violation';
    end if;
    v_tax_amount := (v_tax_result ->> 'taxAmount')::numeric(14, 2);
    v_tax_rule_version_id := (v_tax_result ->> 'ruleVersionId')::uuid;
    select id into v_tax_code_id from app.finance_tax_codes where code = p_tax_code and (tenant_id = p_tenant_id or tenant_id is null) order by tenant_id nulls last limit 1;
  end if;

  insert into app.finance_vendor_bills (
    tenant_id, company_id, vendor_master_id, vendor_reference, shipment_order_id, actual_cost_id,
    currency, subtotal_amount, tax_amount, vendor_stated_amount, variance_amount, variance_status,
    payment_term_days, bill_date, due_date, created_by
  )
  select
    p_tenant_id, so.org_unit_id, p_vendor_master_id, p_vendor_reference, v_cost.shipment_order_id, p_actual_cost_id,
    v_cost.currency, v_subtotal, v_tax_amount, p_vendor_stated_amount, v_variance, v_variance_status,
    coalesce(p_payment_term_days, 30), p_bill_date, p_bill_date + (coalesce(p_payment_term_days, 30) || ' days')::interval, p_actor_label
  from app.shipment_orders so where so.id = v_cost.shipment_order_id
  returning * into v_bill;

  for v_component in
    select * from app.shipment_actual_cost_components
    where actual_cost_id = p_actual_cost_id and source_type = 'vendor' and vendor_id = p_vendor_master_id
    order by created_at asc
  loop
    v_line_number := v_line_number + 1;
    insert into app.finance_vendor_bill_lines (bill_id, line_number, line_type, description, amount, source_component_id)
    values (v_bill.id, v_line_number, 'cost', coalesce(v_component.description, v_component.category), v_component.amount, v_component.id);
  end loop;

  if v_tax_amount > 0 then
    v_line_number := v_line_number + 1;
    insert into app.finance_vendor_bill_lines (bill_id, line_number, line_type, description, amount, tax_code_id, tax_rule_version_id)
    values (v_bill.id, v_line_number, 'tax', p_tax_code || ' tax', v_tax_amount, v_tax_code_id, v_tax_rule_version_id);
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'prepare_finance_vendor_bill_from_actual_cost',
    'app.finance_vendor_bills', v_bill.id, 'success', null, null, to_jsonb(v_bill)
  );

  return v_bill;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.release_finance_ap_hold(p_open_item_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_ap_open_items
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_item app.finance_ap_open_items;
begin
  select * into v_item from app.finance_ap_open_items where id = p_open_item_id for update;
  if not found then
    raise exception 'finance_ap_open_item_not_found: %', p_open_item_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_ap_authority('Approve', v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_item.tenant_id
      using errcode = 'insufficient_privilege';
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
$function$
;


CREATE OR REPLACE FUNCTION app.release_finance_ar_hold(p_open_item_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_ar_open_items
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_item app.finance_ar_open_items;
begin
  select * into v_item from app.finance_ar_open_items where id = p_open_item_id for update;
  if not found then
    raise exception 'finance_ar_open_item_not_found: %', p_open_item_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_ar_authority('Approve', v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_item.tenant_id
      using errcode = 'insufficient_privilege';
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
$function$
;


CREATE OR REPLACE FUNCTION app.relock_finance_period(p_lock_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_period_locks
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_lock app.finance_period_locks;
begin
  select * into v_lock from app.finance_period_locks where id = p_lock_id for update;
  if not found then
    raise exception 'finance_period_lock_not_found: %', p_lock_id using errcode = 'no_data_found';
  end if;
  if v_lock.status = 'locked' then
    return v_lock;
  end if;
  if not app.check_finance_period_lock_authority('Approve', v_lock.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_lock.tenant_id
      using errcode = 'insufficient_privilege';
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
$function$
;


CREATE OR REPLACE FUNCTION app.reopen_finance_period(p_period_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
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
  if not found then
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
$function$
;


CREATE OR REPLACE FUNCTION app.request_finance_period_reopen(p_lock_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_period_locks
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_lock app.finance_period_locks;
begin
  select * into v_lock from app.finance_period_locks where id = p_lock_id for update;
  if not found then
    raise exception 'finance_period_lock_not_found: %', p_lock_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_period_lock_authority('Edit', v_lock.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_lock.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_lock.record_version <> p_expected_version then
    raise exception 'stale_version: lock % expected version % but found %', p_lock_id, p_expected_version, v_lock.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_period_lock_reason_required: a non-empty reason is required' using errcode = 'check_violation';
  end if;
  if v_lock.status <> 'locked' then
    raise exception 'finance_period_lock_not_locked: lock % is % not locked', p_lock_id, v_lock.status
      using errcode = 'check_violation';
  end if;

  update app.finance_period_locks
    set status = 'reopen_requested', reopen_reason = p_reason, reopen_requested_by = p_actor_label, reopen_requested_at = now()
    where id = p_lock_id
    returning * into v_lock;

  insert into app.finance_period_lock_events (lock_id, tenant_id, action, reason, actor_label) values (v_lock.id, v_lock.tenant_id, 'reopen_requested', p_reason, p_actor_label);

  perform app.capture_audit_event(
    v_lock.tenant_id, p_actor_auth_user_id, p_actor_label, 'request_finance_period_reopen',
    'app.finance_period_locks', v_lock.id, 'success', p_reason, null, to_jsonb(v_lock)
  );

  return v_lock;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.request_finance_receipt_deallocation(p_allocation_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
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
  if not found then
    raise exception 'finance_receipt_allocation_not_found: %', p_allocation_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_receipt_authority('Approve', v_allocation.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_allocation.tenant_id
      using errcode = 'insufficient_privilege';
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
$function$
;


CREATE OR REPLACE FUNCTION app.request_finance_settlement_reversal(p_settlement_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_settlements
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_settlement app.finance_settlements;
  v_allocation app.finance_settlement_allocations;
begin
  select * into v_settlement from app.finance_settlements where id = p_settlement_id for update;
  if not found then
    raise exception 'finance_settlement_not_found: %', p_settlement_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_settlement_authority('Approve', v_settlement.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_settlement.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_settlement_reversal_reason_required: a non-empty reason is required to reverse a posted settlement'
      using errcode = 'check_violation';
  end if;
  if v_settlement.status <> 'posted' then
    raise exception 'finance_settlement_not_posted: settlement % is % not posted', p_settlement_id, v_settlement.status
      using errcode = 'check_violation';
  end if;

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
$function$
;


CREATE OR REPLACE FUNCTION app.resolve_finance_reconciliation_exception(p_exception_id uuid, p_expected_version integer, p_resolution_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_reconciliation_exceptions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_exception app.finance_reconciliation_exceptions;
begin
  select * into v_exception from app.finance_reconciliation_exceptions where id = p_exception_id for update;
  if not found then
    raise exception 'finance_reconciliation_exception_not_found: %', p_exception_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_reconciliation_authority('Edit', v_exception.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_exception.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_exception.record_version <> p_expected_version then
    raise exception 'stale_version: exception % expected version % but found %', p_exception_id, p_expected_version, v_exception.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_resolution_reason is null or length(trim(p_resolution_reason)) = 0 then
    raise exception 'finance_reconciliation_resolution_reason_required: a non-empty resolution reason is required' using errcode = 'check_violation';
  end if;
  if v_exception.status <> 'open' then
    raise exception 'finance_reconciliation_exception_not_open: exception % is % not open', p_exception_id, v_exception.status
      using errcode = 'check_violation';
  end if;

  update app.finance_reconciliation_exceptions
    set status = 'resolved', resolution_reason = p_resolution_reason, resolved_by = p_actor_label, resolved_at = now()
    where id = p_exception_id
    returning * into v_exception;

  perform app.capture_audit_event(
    v_exception.tenant_id, p_actor_auth_user_id, p_actor_label, 'resolve_finance_reconciliation_exception',
    'app.finance_reconciliation_exceptions', v_exception.id, 'success', p_resolution_reason, null, to_jsonb(v_exception)
  );

  return v_exception;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.reverse_finance_ap_settlement(p_open_item_id uuid, p_amount numeric, p_reason text, p_source_type text, p_source_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
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
  if not found then
    raise exception 'finance_ap_open_item_not_found: %', p_open_item_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_ap_authority('Approve', v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_item.tenant_id
      using errcode = 'insufficient_privilege';
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
$function$
;


CREATE OR REPLACE FUNCTION app.reverse_finance_ar_allocation(p_open_item_id uuid, p_amount numeric, p_reason text, p_source_type text, p_source_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
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
  if not found then
    raise exception 'finance_ar_open_item_not_found: %', p_open_item_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_ar_authority('Approve', v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_item.tenant_id
      using errcode = 'insufficient_privilege';
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
$function$
;


CREATE OR REPLACE FUNCTION app.set_finance_aging_bucket_config(p_tenant_id uuid, p_entity_type text, p_buckets jsonb, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_aging_bucket_configs
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_config app.finance_aging_bucket_configs;
  v_next_version integer;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_aging_authority('Approve', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_entity_type not in ('ar', 'ap') then
    raise exception 'finance_aging_invalid_entity_type: % is not a supported aging entity type', p_entity_type
      using errcode = 'check_violation';
  end if;

  perform app.validate_finance_aging_buckets(p_buckets);

  select coalesce(max(version), 0) + 1 into v_next_version from app.finance_aging_bucket_configs where tenant_id = p_tenant_id and entity_type = p_entity_type;

  update app.finance_aging_bucket_configs set is_active = false where tenant_id = p_tenant_id and entity_type = p_entity_type and is_active;

  insert into app.finance_aging_bucket_configs (tenant_id, entity_type, version, buckets, created_by)
  values (p_tenant_id, p_entity_type, v_next_version, p_buckets, p_actor_label)
  returning * into v_config;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'set_finance_aging_bucket_config',
    'app.finance_aging_bucket_configs', v_config.id, 'success', null, null, to_jsonb(v_config)
  );

  return v_config;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.soft_close_finance_period(p_period_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_fiscal_periods
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_period app.finance_fiscal_periods;
begin
  select * into v_period from app.finance_fiscal_periods where id = p_period_id;
  if not found then
    raise exception 'finance_period_not_found: %', p_period_id using errcode = 'no_data_found';
  end if;

  if v_period.record_version <> p_expected_version then
    raise exception 'stale_version: period % expected version % but found %', p_period_id, p_expected_version, v_period.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_period.status <> 'open' then
    raise exception 'finance_period_not_open: period % is %, only an open period may be soft-closed', p_period_id, v_period.status
      using errcode = 'check_violation';
  end if;

  if not app.check_finance_period_authority('Edit', v_period.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_period.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.finance_fiscal_periods
  set status = 'soft_closed'
  where id = p_period_id and record_version = p_expected_version
  returning * into v_period;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: soft_close_finance_period target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.finance_period_transitions (period_id, tenant_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (p_period_id, v_period.tenant_id, 'open', 'soft_closed', null, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_period.tenant_id, p_actor_auth_user_id, p_actor_label, 'soft_close_finance_period',
    'app.finance_fiscal_periods', v_period.id, 'success', null, null, to_jsonb(v_period)
  );

  return v_period;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.stage_finance_exchange_rate_import(p_tenant_id uuid, p_idempotency_key text, p_rows jsonb, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_exchange_rate_import_batches
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_batch app.finance_exchange_rate_import_batches;
  v_row jsonb;
  v_count integer := 0;
begin
  if not app.check_finance_exchange_rate_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_batch from app.finance_exchange_rate_import_batches
    where coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(p_tenant_id, '00000000-0000-0000-0000-000000000000'::uuid)
      and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
    -- conflict, never a replay. Returning the earlier target's row here silently
    -- misattributed this request to it (or silently discarded it entirely).
    if v_batch.row_count is distinct from coalesce(jsonb_array_length(p_rows), 0) then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different exchange rate import batch (row count %, not %)', p_idempotency_key, v_batch.row_count, coalesce(jsonb_array_length(p_rows), 0)
        using errcode = 'unique_violation';
    end if;
    return v_batch;
  end if;

  insert into app.finance_exchange_rate_import_batches (tenant_id, idempotency_key, created_by)
  values (p_tenant_id, p_idempotency_key, p_actor_label)
  returning * into v_batch;

  for v_row in select * from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    insert into app.finance_exchange_rates (
      tenant_id, rate_type, source_currency, target_currency, rate, source, effective_from, effective_to, import_batch_id, created_by
    )
    values (
      p_tenant_id,
      coalesce(v_row ->> 'rate_type', 'spot'),
      v_row ->> 'source_currency',
      v_row ->> 'target_currency',
      (v_row ->> 'rate')::numeric,
      coalesce(v_row ->> 'source', 'import'),
      (v_row ->> 'effective_from')::timestamptz,
      (v_row ->> 'effective_to')::timestamptz,
      v_batch.id,
      p_actor_label
    );
    v_count := v_count + 1;
  end loop;

  update app.finance_exchange_rate_import_batches set row_count = v_count where id = v_batch.id returning * into v_batch;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'stage_finance_exchange_rate_import',
    'app.finance_exchange_rate_import_batches', v_batch.id, 'success', null, null, jsonb_build_object('row_count', v_count)
  );

  return v_batch;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.submit_finance_correction_for_approval(p_correction_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_journal_corrections
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_correction app.finance_journal_corrections;
begin
  select * into v_correction from app.finance_journal_corrections where id = p_correction_id for update;
  if not found then
    raise exception 'finance_correction_not_found: %', p_correction_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_correction_authority('Edit', v_correction.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_correction.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_correction.record_version <> p_expected_version then
    raise exception 'stale_version: correction % expected version % but found %', p_correction_id, p_expected_version, v_correction.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_correction.status <> 'draft' then
    raise exception 'finance_correction_not_draft: correction % is % not draft', p_correction_id, v_correction.status
      using errcode = 'check_violation';
  end if;

  update app.finance_journal_corrections set status = 'submitted', submitted_by = p_actor_label, submitted_at = now() where id = p_correction_id returning * into v_correction;

  perform app.capture_audit_event(
    v_correction.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_finance_correction_for_approval',
    'app.finance_journal_corrections', v_correction.id, 'success', null, null, to_jsonb(v_correction)
  );

  return v_correction;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.submit_finance_invoice_for_approval(p_invoice_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_invoices
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_invoice app.finance_invoices;
begin
  select * into v_invoice from app.finance_invoices where id = p_invoice_id for update;
  if not found then
    raise exception 'finance_invoice_not_found: %', p_invoice_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_invoice_authority('Edit', v_invoice.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_invoice.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_invoice.record_version <> p_expected_version then
    raise exception 'stale_version: invoice % expected version % but found %', p_invoice_id, p_expected_version, v_invoice.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_invoice.status <> 'draft' then
    raise exception 'finance_invoice_not_draft: invoice % is % not draft', p_invoice_id, v_invoice.status
      using errcode = 'check_violation';
  end if;

  update app.finance_invoices set status = 'submitted', submitted_by = p_actor_label, submitted_at = now() where id = p_invoice_id returning * into v_invoice;

  perform app.capture_audit_event(
    v_invoice.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_finance_invoice_for_approval',
    'app.finance_invoices', v_invoice.id, 'success', null, null, to_jsonb(v_invoice)
  );

  return v_invoice;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.submit_finance_journal_for_approval(p_journal_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
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

  update app.finance_journals set status = 'submitted', submitted_by = p_actor_label, submitted_at = now() where id = p_journal_id returning * into v_journal;

  perform app.capture_audit_event(
    v_journal.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_finance_journal_for_approval',
    'app.finance_journals', v_journal.id, 'success', null, null, to_jsonb(v_journal)
  );

  return v_journal;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.submit_finance_settlement_for_approval(p_settlement_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_settlements
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_settlement app.finance_settlements;
begin
  select * into v_settlement from app.finance_settlements where id = p_settlement_id for update;
  if not found then
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
  if v_settlement.status <> 'draft' then
    raise exception 'finance_settlement_not_draft: settlement % is % not draft', p_settlement_id, v_settlement.status
      using errcode = 'check_violation';
  end if;

  update app.finance_settlements set status = 'submitted', submitted_by = p_actor_label, submitted_at = now() where id = p_settlement_id returning * into v_settlement;

  perform app.capture_audit_event(
    v_settlement.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_finance_settlement_for_approval',
    'app.finance_settlements', v_settlement.id, 'success', null, null, to_jsonb(v_settlement)
  );

  return v_settlement;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.submit_finance_vendor_bill_for_approval(p_bill_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_vendor_bills
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_bill app.finance_vendor_bills;
begin
  select * into v_bill from app.finance_vendor_bills where id = p_bill_id for update;
  if not found then
    raise exception 'finance_vendor_bill_not_found: %', p_bill_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_vendor_bill_authority('Edit', v_bill.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_bill.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_bill.record_version <> p_expected_version then
    raise exception 'stale_version: bill % expected version % but found %', p_bill_id, p_expected_version, v_bill.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_bill.status <> 'draft' then
    raise exception 'finance_vendor_bill_not_draft: bill % is % not draft', p_bill_id, v_bill.status
      using errcode = 'check_violation';
  end if;

  update app.finance_vendor_bills set status = 'submitted', submitted_by = p_actor_label, submitted_at = now() where id = p_bill_id returning * into v_bill;

  perform app.capture_audit_event(
    v_bill.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_finance_vendor_bill_for_approval',
    'app.finance_vendor_bills', v_bill.id, 'success', null, null, to_jsonb(v_bill)
  );

  return v_bill;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.unmatch_finance_bank_transaction(p_transaction_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_bank_transactions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_transaction app.finance_bank_transactions;
begin
  select * into v_transaction from app.finance_bank_transactions where id = p_transaction_id for update;
  if not found then
    raise exception 'finance_cash_transaction_not_found: %', p_transaction_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_cash_authority('Approve', v_transaction.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_transaction.tenant_id
      using errcode = 'insufficient_privilege';
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
$function$
;

revoke execute on all functions in schema app from public;
