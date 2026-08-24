-- HDN-373 (Step 15, Prompt 373, RLS and RBAC Audit, `CG-S15-HDN-005`) -- Tier C
-- correction. This checkpoint's own four-lens adversarial review found two genuine gaps
-- in the fix pass this migration corrects before the checkpoint may close.
--
-- ===========================================================================
-- Gap 1 -- 57 more Finance/Config/Automation/Integration functions share `HDN-BLK-015`'s
-- exact shape and were not caught by the original diagnosis
-- ===========================================================================
--
-- `20260810700000_harden_finance_authority_chain_security_definer.sql` converted 76
-- top-level entry points plus the 19 `app.check_finance_*_authority` helpers to
-- `SECURITY DEFINER`, but granted a direct `authenticated` `EXECUTE` to only ONE of those
-- 19 helpers (`check_finance_journal_authority`, needed for `ISS-2026-184`'s RLS
-- embedding) -- correct for a caller nested inside an already-`SECURITY DEFINER` entry
-- point, but fatal for every OTHER entry point that was never itself converted and still
-- calls its own `check_finance_*_authority` helper (now `SECURITY DEFINER`, but reached
-- from a still-`SECURITY INVOKER` caller running as `authenticated`, which needs its own
-- direct grant on that helper -- exactly the same `EXECUTE`-checked-at-the-call-site
-- mechanism `20260810700000`'s own header already explains).
--
-- **Found by this checkpoint's own Tier C review** (an independent schema-wide sweep for
-- the identical `SECURITY INVOKER` + `authenticated`-granted + broken-nested-call shape,
-- deliberately run wider than the original Finance-only investigation), and independently
-- re-derived and confirmed by the closing session before this migration was written.
-- **Live-forced**: a genuine, non-superuser Finance Manager session calling
-- `app.list_finance_accounts`/`app.get_finance_cash_position`/`app.create_finance_config_draft`
-- and 15 further representative functions each failed with `permission denied for
-- function check_finance_*_authority` (or, for `app.list_n8n_action_allowlist` and the
-- generic Config-Engine table reads inside the Finance config-management wrappers,
-- `permission denied for table`) -- the identical failure shape `HDN-BLK-015` already
-- root-caused, just not exhaustively swept the first time.
--
-- 57 functions: 54 Finance-domain (accounts, cash/bank, tax, exchange rate, AP/AR
-- open-items and exposure, aging, reconciliation, period, invoice, vendor bill,
-- settlement, receipt, subledger, correction, numbering, idempotency, and the
-- Finance-config-management wrapper family -- `create/discard/publish/rollback_finance_
-- config_*`, `set_finance_config_items`, `get_finance_config_version_items`,
-- `preview_finance_config_impact`), plus 2 generic Config-Engine functions reached the
-- same way from outside Finance (`validate_automation_rule_definition`,
-- `validate_custom_field_values` -- the latter confirmed independently reachable today via
-- `server/queries/form.ts`'s own direct `client.rpc('validate_custom_field_values', ...)`
-- call, not merely a theoretical path), plus 1 Integration-domain function
-- (`app.list_n8n_action_allowlist`).
--
-- **Fix, identical pattern, independently re-verified before being applied at scale**:
-- `SECURITY DEFINER SET search_path TO 'app', 'pg_temp'` added to each of the 57, no other
-- line touched -- generated mechanically from live `pg_get_functiondef` output, applied,
-- then the identical sweep re-run against the fixed state and confirmed to return zero
-- further rows (fixed-point convergence, not merely "no longer complains about the 57
-- named here"). A live two-hop case the sweep does not directly enumerate
-- (`app.get_finance_aging_summary`, which calls nothing but `app.get_finance_aging_report`,
-- itself one of the 57) was independently live-verified to require no separate fix of its
-- own: once its sole callee is `SECURITY DEFINER` and already carries the `authenticated`
-- grant `get_finance_aging_summary`'s own call site needs, the call succeeds without
-- `get_finance_aging_summary` itself changing at all -- confirming `HDN-BLK-015`'s own
-- established principle (a single `SECURITY DEFINER` boundary at the true entry point is
-- both necessary and sufficient) generalizes correctly rather than needing a deeper,
-- per-hop fix.
--
-- None of the 57 needs a new `EXECUTE` grant of its own -- every one already carries a
-- real, deliberate `authenticated` grant from its own original migration (that grant is
-- what made it a genuine, reachable, currently-broken entry point in the first place, and
-- what qualified it for this sweep).
--
-- ===========================================================================
-- Gap 2 -- `app.create_and_post_finance_system_journal`'s new authority gate
-- (`ISS-2026-183`, `20260810700000`) was stricter than its own legitimate callers
-- ===========================================================================
--
-- `20260810700000` added `app.check_finance_journal_authority('Approve', ...)` to close
-- `ISS-2026-183` (the function had no authority check of its own, independently
-- `authenticated`-callable). **Found by this checkpoint's own Tier C review, live-forced**:
-- of this function's two legitimate nested callers, `app.post_finance_subledger_batch`
-- (called directly with `p_source_type = 'subledger'`) and `app.allocate_finance_receipt`
-- (same), each independently gates on `FIN:Edit` (`check_finance_subledger_authority`/
-- `check_finance_receipt_authority`), never `FIN:Approve` -- a genuine `FIN:Edit`-only
-- actor (a real, legitimate role shape this schema's own "Finance Editor" test fixture
-- already models) passed both of those functions' own front-door checks and then hit a
-- newly-introduced `insufficient_authority: ... lacks FIN:Approve` deeper in the chain, a
-- capability that worked before `20260810700000` (when the function was simply
-- unreachable for everyone, masking the question) and should still work now that
-- reachability is restored.
--
-- The THIRD source type, `'correction'` (called from `app.post_finance_correction`),
-- genuinely does require `FIN:Approve` at its own front door
-- (`app.check_finance_correction_authority('Approve', ...)`) -- and, confirmed by reading
-- its definition, that helper checks the exact same `('FIN', 'Approve')` permission pair
-- `check_finance_journal_authority('Approve', ...)` does (both are thin wrappers around
-- `app.evaluate_permission(actor, tenant, 'FIN', p_action)`), so an actor who already
-- passed the correction chain's own gate necessarily also holds `FIN:Approve` and is
-- unaffected by loosening this function's own gate to accept either level.
--
-- **Fix**: the gate now accepts `FIN:Edit` OR `FIN:Approve` (either is sufficient) --
-- covering both legitimate call shapes without assuming one implies the other at the
-- schema level (nothing in `app.evaluate_permission`/`app.role_version_permissions`
-- guarantees that relationship; it has only ever held by role-provisioning convention in
-- this repository's own fixtures, which is not a safe thing for this function to depend
-- on). Still closes `ISS-2026-183`'s own original concern in full: an actor with NEITHER
-- `FIN:Edit` nor `FIN:Approve` -- zero Finance authority at all -- is still denied.
--
-- Full disposition of both gaps: `docs/build-log/full-system-hardening/HDN-373.md` §6.


CREATE OR REPLACE FUNCTION app.calculate_finance_tax(p_tenant_id uuid, p_tax_code text, p_base_amount numeric, p_as_of date, p_actor_auth_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_rule app.finance_tax_rule_versions;
  v_mode text;
  v_precision integer;
  v_raw numeric;
  v_tax_amount numeric;
  v_rounding_row record;
begin
  if not app.check_finance_tax_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_base_amount is null or p_base_amount < 0 then
    raise exception 'finance_tax_rule_invalid_base_amount: base amount must be non-negative, got %', p_base_amount
      using errcode = 'check_violation';
  end if;

  select * into v_rule from app.resolve_finance_tax_rule(p_tenant_id, p_tax_code, coalesce(p_as_of, current_date));
  if not found then
    raise exception 'finance_tax_rule_missing: no approved tax rule for % covers %', p_tax_code, coalesce(p_as_of, current_date)
      using errcode = 'no_data_found';
  end if;

  v_raw := case when v_rule.rate_basis = 'percentage' then p_base_amount * v_rule.rate_value else v_rule.rate_value end;

  v_mode := 'round_half_up';
  v_precision := 2;
  for v_rounding_row in select * from app.resolve_finance_config('finance_rounding', p_tenant_id) loop
    if v_rounding_row.items ? 'tax_calculation' then
      v_mode := coalesce(v_rounding_row.items -> 'tax_calculation' ->> 'mode', v_mode);
      v_precision := coalesce((v_rounding_row.items -> 'tax_calculation' ->> 'precision')::integer, v_precision);
    elsif v_rounding_row.items ? 'default' then
      v_mode := coalesce(v_rounding_row.items -> 'default' ->> 'mode', v_mode);
      v_precision := coalesce((v_rounding_row.items -> 'default' ->> 'precision')::integer, v_precision);
    end if;
  end loop;

  v_tax_amount := app.apply_finance_rounding(v_raw, v_precision, v_mode);

  return jsonb_build_object(
    'baseAmount', p_base_amount,
    'taxCode', p_tax_code,
    'ruleVersionId', v_rule.id,
    'rateBasis', v_rule.rate_basis,
    'rateValue', v_rule.rate_value,
    'currency', v_rule.currency,
    'taxAmount', v_tax_amount,
    'roundingMode', v_mode,
    'effectiveFrom', v_rule.effective_from,
    'effectiveTo', v_rule.effective_to
  );
end;
$function$
;


CREATE OR REPLACE FUNCTION app.convert_finance_amount(p_tenant_id uuid, p_amount numeric, p_source_currency text, p_target_currency text, p_rate_type text, p_as_of timestamp with time zone, p_actor_auth_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_rate app.finance_exchange_rates;
  v_rounding_row record;
  v_mode text;
  v_precision integer;
  v_order text;
  v_target_precision integer;
  v_converted numeric;
begin
  if not app.check_finance_exchange_rate_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select minor_unit_precision into v_target_precision from app.finance_currencies where code = p_target_currency;
  if v_target_precision is null then
    raise exception 'finance_exchange_rate_unsupported_currency: % is not a registered, active currency', p_target_currency
      using errcode = 'check_violation';
  end if;

  if p_source_currency = p_target_currency then
    return jsonb_build_object(
      'amount', p_amount, 'sourceCurrency', p_source_currency, 'targetCurrency', p_target_currency,
      'rate', 1, 'rateId', null, 'convertedAmount', round(p_amount, v_target_precision), 'roundingMode', 'identity'
    );
  end if;

  select * into v_rate from app.resolve_finance_exchange_rate(p_tenant_id, coalesce(p_rate_type, 'spot'), p_source_currency, p_target_currency, coalesce(p_as_of, now()));
  if not found then
    raise exception 'finance_exchange_rate_missing: no approved % rate from % to % covers %', coalesce(p_rate_type, 'spot'), p_source_currency, p_target_currency, coalesce(p_as_of, now())
      using errcode = 'no_data_found';
  end if;

  v_mode := 'round_half_up';
  v_precision := v_target_precision;
  v_order := 'convert_then_round';

  for v_rounding_row in select * from app.resolve_finance_config('finance_rounding', p_tenant_id) loop
    if v_rounding_row.items ? 'fx_conversion' then
      v_mode := coalesce(v_rounding_row.items -> 'fx_conversion' ->> 'mode', v_mode);
      v_precision := coalesce((v_rounding_row.items -> 'fx_conversion' ->> 'precision')::integer, v_precision);
      v_order := coalesce(v_rounding_row.items -> 'fx_conversion' ->> 'order', v_order);
    elsif v_rounding_row.items ? 'default' then
      v_mode := coalesce(v_rounding_row.items -> 'default' ->> 'mode', v_mode);
      v_precision := coalesce((v_rounding_row.items -> 'default' ->> 'precision')::integer, v_precision);
      v_order := coalesce(v_rounding_row.items -> 'default' ->> 'order', v_order);
    end if;
  end loop;

  -- ATW-032: v_order was resolved from the governed finance_rounding config and REPORTED
  -- back to the caller as `roundingOrder`, but never applied -- the arithmetic was always
  -- convert-then-round regardless. A tenant that configures round_then_convert was told its
  -- setting was honoured while it was not. Both branches are now real.
  if v_order = 'round_then_convert' then
    v_converted := app.apply_finance_rounding(p_amount, v_precision, v_mode) * v_rate.rate;
    v_converted := app.apply_finance_rounding(v_converted, v_precision, v_mode);
  else
    v_converted := app.apply_finance_rounding(p_amount * v_rate.rate, v_precision, v_mode);
  end if;

  return jsonb_build_object(
    'amount', p_amount, 'sourceCurrency', p_source_currency, 'targetCurrency', p_target_currency,
    'rate', v_rate.rate, 'rateId', v_rate.id, 'convertedAmount', v_converted, 'roundingMode', v_mode, 'roundingOrder', v_order
  );
end;
$function$
;


CREATE OR REPLACE FUNCTION app.create_finance_config_draft(p_config_type_code text, p_tenant_id uuid, p_scope_level text, p_scope_id uuid, p_actor_auth_user_id uuid, p_created_by text)
 RETURNS app.config_versions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
begin
  if not app.is_finance_config_type(p_config_type_code) then
    raise exception 'not_finance_config_type: % is not a Finance Configuration class', p_config_type_code
      using errcode = 'check_violation';
  end if;
  if not app.check_finance_config_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return app.create_config_draft(p_config_type_code, p_tenant_id, p_scope_level, p_scope_id, p_actor_auth_user_id, p_created_by);
end;
$function$
;


CREATE OR REPLACE FUNCTION app.discard_finance_config_draft(p_version_id uuid, p_actor_auth_user_id uuid, p_reason text, p_actor_label text)
 RETURNS app.config_versions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_version app.config_versions;
  v_object app.config_objects;
begin
  select * into v_version from app.config_versions where id = p_version_id;
  if not found then
    raise exception 'config_version_not_found: no config version %', p_version_id
      using errcode = 'no_data_found';
  end if;
  select * into v_object from app.config_objects where id = v_version.config_object_id;

  if not app.is_finance_config_type(v_object.config_type_code) then
    raise exception 'not_finance_config_type: % is not a Finance Configuration class', v_object.config_type_code
      using errcode = 'check_violation';
  end if;
  if not app.check_finance_config_authority('Edit', v_object.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_object.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return app.discard_config_draft(p_version_id, p_actor_auth_user_id, p_reason, p_actor_label);
end;
$function$
;


CREATE OR REPLACE FUNCTION app.get_finance_account_dependency_impact(p_account_id uuid, p_actor_auth_user_id uuid)
 RETURNS jsonb
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
  select * into v_account from app.finance_accounts where id = p_account_id;
  if not found then
    raise exception 'finance_account_not_found: %', p_account_id using errcode = 'no_data_found';
  end if;

  if not app.check_finance_account_authority('View', v_account.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, v_account.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select count(*) into v_child_count from app.finance_accounts where parent_account_id = p_account_id and status <> 'inactive';

  for v_row in select * from app.resolve_finance_config('finance_posting_map', v_account.tenant_id) loop
    if exists (
      select 1 from jsonb_each(v_row.items) e
      where (e.value ->> 'accountCodeRef') = v_account.code
    ) then
      v_referenced_by_posting_map := true;
    end if;
  end loop;

  return jsonb_build_object(
    'accountId', v_account.id,
    'code', v_account.code,
    'activeChildAccountCount', v_child_count,
    'referencedByPublishedPostingMap', v_referenced_by_posting_map
  );
end;
$function$
;


CREATE OR REPLACE FUNCTION app.get_finance_aging_report(p_tenant_id uuid, p_company_id uuid, p_entity_type text, p_as_of_date date, p_include_held boolean, p_actor_auth_user_id uuid)
 RETURNS TABLE(open_item_id uuid, party_id uuid, currency text, original_amount numeric, open_amount numeric, document_date date, due_date date, days_overdue integer, bucket_label text, is_held boolean, source_document_type text, source_document_id uuid)
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_bucket_resolution record;
begin
  if not app.check_finance_aging_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_entity_type not in ('ar', 'ap') then
    raise exception 'finance_aging_invalid_entity_type: % is not a supported aging entity type', p_entity_type
      using errcode = 'check_violation';
  end if;

  select * into v_bucket_resolution from app.resolve_finance_aging_buckets(p_tenant_id, p_entity_type);

  if p_entity_type = 'ar' then
    return query
      select
        i.id, i.customer_account_id, i.currency, i.original_amount, i.open_amount, i.invoice_date, i.due_date,
        greatest(0, p_as_of_date - i.due_date)::integer,
        app.assign_finance_aging_bucket(v_bucket_resolution.buckets, greatest(0, p_as_of_date - i.due_date)::integer),
        i.is_held, i.source_document_type, i.source_document_id
      from app.finance_ar_open_items i
      where i.tenant_id = p_tenant_id
        and (p_company_id is null or i.company_id = p_company_id)
        and i.open_amount > 0
        and i.invoice_date <= p_as_of_date
        and (p_include_held or not i.is_held)
      order by greatest(0, p_as_of_date - i.due_date) desc;
  else
    return query
      select
        i.id, i.vendor_master_id, i.currency, i.original_amount, i.open_amount, i.bill_date, i.due_date,
        greatest(0, p_as_of_date - i.due_date)::integer,
        app.assign_finance_aging_bucket(v_bucket_resolution.buckets, greatest(0, p_as_of_date - i.due_date)::integer),
        i.is_held, i.source_document_type, i.source_document_id
      from app.finance_ap_open_items i
      where i.tenant_id = p_tenant_id
        and (p_company_id is null or i.company_id = p_company_id)
        and i.open_amount > 0
        and i.bill_date <= p_as_of_date
        and (p_include_held or not i.is_held)
      order by greatest(0, p_as_of_date - i.due_date) desc;
  end if;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.get_finance_ap_exposure_summary(p_tenant_id uuid, p_vendor_master_id uuid, p_actor_auth_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_summary record;
begin
  if not app.check_finance_ap_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select
    coalesce(sum(open_amount), 0) as total_open,
    count(*) filter (where status <> 'settled') as open_count,
    coalesce(sum(open_amount) filter (where status <> 'settled' and due_date < current_date), 0) as overdue_open,
    count(*) filter (where status <> 'settled' and due_date < current_date) as overdue_count
  into v_summary
  from app.finance_ap_open_items
  where tenant_id = p_tenant_id and vendor_master_id = p_vendor_master_id;

  return jsonb_build_object(
    'totalOpen', v_summary.total_open,
    'openCount', v_summary.open_count,
    'overdueOpen', v_summary.overdue_open,
    'overdueCount', v_summary.overdue_count
  );
end;
$function$
;


CREATE OR REPLACE FUNCTION app.get_finance_ap_open_item_activity(p_open_item_id uuid, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_ap_open_item_events
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_item app.finance_ap_open_items;
begin
  select * into v_item from app.finance_ap_open_items where id = p_open_item_id;
  if not found then
    raise exception 'finance_ap_open_item_not_found: %', p_open_item_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_ap_authority('View', v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_ap_open_item_events where open_item_id = p_open_item_id order by created_at asc;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.get_finance_ar_exposure_summary(p_tenant_id uuid, p_customer_account_id uuid, p_actor_auth_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_summary record;
begin
  if not app.check_finance_ar_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select
    coalesce(sum(open_amount), 0) as total_open,
    count(*) filter (where status <> 'paid') as open_count,
    coalesce(sum(open_amount) filter (where status <> 'paid' and due_date < current_date), 0) as overdue_open,
    count(*) filter (where status <> 'paid' and due_date < current_date) as overdue_count
  into v_summary
  from app.finance_ar_open_items
  where tenant_id = p_tenant_id and customer_account_id = p_customer_account_id;

  return jsonb_build_object(
    'totalOpen', v_summary.total_open,
    'openCount', v_summary.open_count,
    'overdueOpen', v_summary.overdue_open,
    'overdueCount', v_summary.overdue_count
  );
end;
$function$
;


CREATE OR REPLACE FUNCTION app.get_finance_ar_open_item_activity(p_open_item_id uuid, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_ar_open_item_events
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_item app.finance_ar_open_items;
begin
  select * into v_item from app.finance_ar_open_items where id = p_open_item_id;
  if not found then
    raise exception 'finance_ar_open_item_not_found: %', p_open_item_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_ar_authority('View', v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_ar_open_item_events where open_item_id = p_open_item_id order by created_at asc;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.get_finance_cash_position(p_tenant_id uuid, p_bank_account_id uuid, p_as_of_date date, p_actor_auth_user_id uuid)
 RETURNS TABLE(bank_account_id uuid, currency text, statement_balance numeric, gl_balance numeric, variance_amount numeric)
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_account app.finance_bank_accounts;
  v_statement_balance numeric(14, 2) := 0;
  v_gl_balance numeric(14, 2) := 0;
begin
  if not app.check_finance_cash_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_account from app.finance_bank_accounts where id = p_bank_account_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'finance_cash_bank_account_not_found: % is not a known bank account for tenant %', p_bank_account_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;

  select coalesce(sum(case when t.direction = 'debit' then t.amount else -t.amount end), 0) into v_statement_balance
    from app.finance_bank_transactions t
    where t.bank_account_id = p_bank_account_id and t.transaction_date <= p_as_of_date;

  select coalesce(sum(case when l.direction = 'debit' then l.amount else -l.amount end), 0) into v_gl_balance
    from app.finance_subledger_lines l
    join app.finance_subledger_batches b on b.id = l.batch_id
    join app.finance_fiscal_periods fp on fp.id = b.posting_period_id
    where b.tenant_id = p_tenant_id and l.account_id = v_account.gl_account_id and fp.end_date <= p_as_of_date;

  return query select v_account.id, v_account.currency, v_statement_balance, v_gl_balance, (v_gl_balance - v_statement_balance);
end;
$function$
;


CREATE OR REPLACE FUNCTION app.get_finance_config_version_items(p_version_id uuid, p_actor_auth_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_version app.config_versions;
  v_object app.config_objects;
begin
  select * into v_version from app.config_versions where id = p_version_id;
  if not found then
    raise exception 'config_version_not_found: no config version %', p_version_id
      using errcode = 'no_data_found';
  end if;
  select * into v_object from app.config_objects where id = v_version.config_object_id;

  if not app.is_finance_config_type(v_object.config_type_code) then
    raise exception 'not_finance_config_type: % is not a Finance Configuration class', v_object.config_type_code
      using errcode = 'check_violation';
  end if;
  if not app.check_finance_config_authority('Edit', v_object.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_object.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return coalesce(
    (select jsonb_object_agg(key, value) from app.config_items where config_version_id = p_version_id),
    '{}'::jsonb
  );
end;
$function$
;


CREATE OR REPLACE FUNCTION app.get_finance_correction_chain(p_correction_id uuid, p_actor_auth_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_correction app.finance_journal_corrections;
  v_original app.finance_journals;
  v_correction_journal app.finance_journals;
begin
  select * into v_correction from app.finance_journal_corrections where id = p_correction_id;
  if not found then
    raise exception 'finance_correction_not_found: %', p_correction_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_correction_authority('View', v_correction.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, v_correction.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_original from app.finance_journals where id = v_correction.original_journal_id;
  if v_correction.correction_journal_id is not null then
    select * into v_correction_journal from app.finance_journals where id = v_correction.correction_journal_id;
  end if;

  return jsonb_build_object(
    'correction', to_jsonb(v_correction),
    'originalJournal', to_jsonb(v_original),
    'correctionJournal', case when v_correction.correction_journal_id is not null then to_jsonb(v_correction_journal) else null end
  );
end;
$function$
;


CREATE OR REPLACE FUNCTION app.get_finance_dashboard_billing_summary(p_tenant_id uuid, p_company_id uuid, p_actor_auth_user_id uuid)
 RETURNS TABLE(status text, currency text, invoice_count bigint, total_amount numeric, open_amount numeric)
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
begin
  if not app.check_finance_invoice_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
    select
      inv.status,
      inv.currency,
      count(*)::bigint,
      sum(inv.total_amount),
      coalesce(sum(oi.open_amount), 0)
    from app.finance_invoices inv
    left join app.finance_ar_open_items oi on oi.id = inv.ar_open_item_id
    where inv.tenant_id = p_tenant_id
      and (p_company_id is null or inv.company_id = p_company_id)
    group by inv.status, inv.currency
    order by inv.status, inv.currency;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.get_finance_dashboard_cash_summary(p_tenant_id uuid, p_company_id uuid, p_as_of_date date, p_actor_auth_user_id uuid)
 RETURNS TABLE(bank_account_id uuid, account_name text, currency text, statement_balance numeric, gl_balance numeric, variance_amount numeric)
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_account app.finance_bank_accounts;
begin
  if not app.check_finance_cash_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  for v_account in
    select * from app.finance_bank_accounts
    where tenant_id = p_tenant_id
      and status = 'active'
      and (p_company_id is null or company_id = p_company_id)
    order by account_name
  loop
    return query
      select v_account.id, v_account.account_name, p.currency, p.statement_balance, p.gl_balance, p.variance_amount
      from app.get_finance_cash_position(p_tenant_id, v_account.id, p_as_of_date, p_actor_auth_user_id) p;
  end loop;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.get_finance_dashboard_close_status(p_tenant_id uuid, p_company_id uuid, p_actor_auth_user_id uuid)
 RETURNS TABLE(period_id uuid, period_code text, period_name text, end_date date, period_status text, lock_status text, reconciliation_status text, reconciliation_within_tolerance boolean)
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
begin
  if not app.check_finance_period_lock_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_reconciliation_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
    select
      fp.id, fp.period_code, fp.name, fp.end_date, fp.status,
      lk.lock_status, rc.reconciliation_status, rc.reconciliation_within_tolerance
    from app.finance_fiscal_periods fp
    left join lateral (
      select l.status as lock_status
      from app.finance_period_locks l
      where l.period_id = fp.id
        and l.tenant_id = p_tenant_id
        and (p_company_id is null or l.company_id = p_company_id)
      order by l.created_at desc
      limit 1
    ) lk on true
    left join lateral (
      select r.status as reconciliation_status, r.is_within_tolerance as reconciliation_within_tolerance
      from app.finance_reconciliation_runs r
      where r.tenant_id = p_tenant_id
        and (p_company_id is null or r.company_id = p_company_id)
        and r.as_of_date between fp.start_date and fp.end_date
      order by r.created_at desc
      limit 1
    ) rc on true
    where fp.tenant_id = p_tenant_id
      and (p_company_id is null or fp.company_id = p_company_id)
    order by fp.end_date desc
    limit 12;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.get_finance_idempotency_claim(p_tenant_id uuid, p_scope text, p_idempotency_key text, p_actor_auth_user_id uuid)
 RETURNS app.finance_idempotency_claims
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_claim app.finance_idempotency_claims;
begin
  if not app.check_finance_idempotency_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  select * into v_claim from app.finance_idempotency_claims where tenant_id = p_tenant_id and scope = p_scope and idempotency_key = p_idempotency_key;
  if not found then
    raise exception 'finance_idempotency_claim_not_found: no claim for scope % key %', p_scope, p_idempotency_key using errcode = 'no_data_found';
  end if;
  return v_claim;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.get_finance_invoice_lines(p_invoice_id uuid, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_invoice_lines
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_invoice app.finance_invoices;
begin
  select * into v_invoice from app.finance_invoices where id = p_invoice_id;
  if not found then
    raise exception 'finance_invoice_not_found: %', p_invoice_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_invoice_authority('View', v_invoice.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, v_invoice.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_invoice_lines where invoice_id = p_invoice_id order by line_number asc;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.get_finance_lifecycle_record_state(p_tenant_id uuid, p_entity_type text, p_record_id uuid, p_actor_auth_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_status text;
  v_record_version integer;
  v_editability app.finance_lifecycle_editability_matrix;
begin
  if p_entity_type = 'invoice' then
    if not app.check_finance_invoice_authority('View', p_tenant_id, p_actor_auth_user_id) then
      raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
        using errcode = 'insufficient_privilege';
    end if;
    select status, record_version into v_status, v_record_version from app.finance_invoices where id = p_record_id and tenant_id = p_tenant_id;
  elsif p_entity_type = 'vendor_bill' then
    if not app.check_finance_vendor_bill_authority('View', p_tenant_id, p_actor_auth_user_id) then
      raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
        using errcode = 'insufficient_privilege';
    end if;
    select status, record_version into v_status, v_record_version from app.finance_vendor_bills where id = p_record_id and tenant_id = p_tenant_id;
  elsif p_entity_type = 'receipt' then
    if not app.check_finance_receipt_authority('View', p_tenant_id, p_actor_auth_user_id) then
      raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
        using errcode = 'insufficient_privilege';
    end if;
    select status, record_version into v_status, v_record_version from app.finance_receipts where id = p_record_id and tenant_id = p_tenant_id;
  elsif p_entity_type = 'settlement' then
    if not app.check_finance_settlement_authority('View', p_tenant_id, p_actor_auth_user_id) then
      raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
        using errcode = 'insufficient_privilege';
    end if;
    select status, record_version into v_status, v_record_version from app.finance_settlements where id = p_record_id and tenant_id = p_tenant_id;
  elsif p_entity_type = 'subledger_batch' then
    if not app.check_finance_subledger_authority('View', p_tenant_id, p_actor_auth_user_id) then
      raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
        using errcode = 'insufficient_privilege';
    end if;
    -- app.finance_subledger_batches carries no record_version -- it has no
    -- direct-editable normal-role mutation surface at all (system-sourced,
    -- immediate-posted only), so no optimistic-concurrency token was ever
    -- needed for it (FIN-202's own design).
    select status, null into v_status, v_record_version from app.finance_subledger_batches where id = p_record_id and tenant_id = p_tenant_id;
  elsif p_entity_type = 'journal' then
    if not app.check_finance_journal_authority('View', p_tenant_id, p_actor_auth_user_id) then
      raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
        using errcode = 'insufficient_privilege';
    end if;
    select status, record_version into v_status, v_record_version from app.finance_journals where id = p_record_id and tenant_id = p_tenant_id;
  else
    raise exception 'finance_lifecycle_entity_type_unsupported: % is not a recognized Finance lifecycle entity type', p_entity_type
      using errcode = 'invalid_parameter_value';
  end if;

  if v_status is null then
    raise exception 'finance_lifecycle_record_not_found: no % record % found for tenant %', p_entity_type, p_record_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;

  v_editability := app.get_finance_lifecycle_editability(p_entity_type, v_status);

  return jsonb_build_object(
    'entityType', p_entity_type,
    'recordId', p_record_id,
    'tenantId', p_tenant_id,
    'concreteStatus', v_status,
    'canonicalState', v_editability.canonical_state,
    'recordVersion', v_record_version,
    'isEditable', v_editability.is_editable,
    'allowedActions', to_jsonb(v_editability.allowed_actions),
    'lockedReason', v_editability.locked_reason,
    'postedTriggerProtected', v_editability.posted_trigger_protected
  );
end;
$function$
;


CREATE OR REPLACE FUNCTION app.get_finance_period_close_readiness(p_period_id uuid, p_actor_auth_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_period app.finance_fiscal_periods;
  v_unsatisfied jsonb;
begin
  select * into v_period from app.finance_fiscal_periods where id = p_period_id;
  if not found then
    raise exception 'finance_period_not_found: %', p_period_id using errcode = 'no_data_found';
  end if;

  if not app.check_finance_period_authority('View', v_period.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, v_period.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select coalesce(jsonb_agg(item_key), '[]'::jsonb) into v_unsatisfied
  from app.finance_period_close_checklist_items
  where period_id = p_period_id and required and not satisfied;

  return jsonb_build_object(
    'periodId', p_period_id,
    'status', v_period.status,
    'ready', (v_unsatisfied = '[]'::jsonb),
    'unsatisfiedRequiredItems', v_unsatisfied
  );
end;
$function$
;


CREATE OR REPLACE FUNCTION app.get_finance_period_lock_events(p_lock_id uuid, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_period_lock_events
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_lock app.finance_period_locks;
begin
  select * into v_lock from app.finance_period_locks where id = p_lock_id;
  if not found then
    raise exception 'finance_period_lock_not_found: %', p_lock_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_period_lock_authority('View', v_lock.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, v_lock.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_period_lock_events where lock_id = p_lock_id order by created_at asc;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.get_finance_period_transition_history(p_period_id uuid, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_period_transitions
 LANGUAGE plpgsql
 STABLE
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
  if not app.check_finance_period_authority('View', v_period.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, v_period.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.finance_period_transitions where period_id = p_period_id order by created_at asc;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.get_finance_receipt_allocations(p_receipt_id uuid, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_receipt_allocations
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_receipt app.finance_receipts;
begin
  select * into v_receipt from app.finance_receipts where id = p_receipt_id;
  if not found then
    raise exception 'finance_receipt_not_found: %', p_receipt_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_receipt_authority('View', v_receipt.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, v_receipt.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_receipt_allocations where receipt_id = p_receipt_id order by created_at asc;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.get_finance_settlement_allocations(p_settlement_id uuid, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_settlement_allocations
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_settlement app.finance_settlements;
begin
  select * into v_settlement from app.finance_settlements where id = p_settlement_id;
  if not found then
    raise exception 'finance_settlement_not_found: %', p_settlement_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_settlement_authority('View', v_settlement.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, v_settlement.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_settlement_allocations where settlement_id = p_settlement_id order by created_at asc;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.get_finance_subledger_lines(p_batch_id uuid, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_subledger_lines
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_batch app.finance_subledger_batches;
begin
  select * into v_batch from app.finance_subledger_batches where id = p_batch_id;
  if not found then
    raise exception 'finance_subledger_batch_not_found: %', p_batch_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_subledger_authority('View', v_batch.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, v_batch.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_subledger_lines where batch_id = p_batch_id order by line_number asc;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.get_finance_subledger_reconciliation_summary(p_tenant_id uuid, p_actor_auth_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_ar_account app.finance_accounts;
  v_ap_account app.finance_accounts;
  v_ar_subledger_balance numeric(14, 2) := 0;
  v_ap_subledger_balance numeric(14, 2) := 0;
  v_ar_open_total numeric(14, 2) := 0;
  v_ap_open_total numeric(14, 2) := 0;
begin
  if not app.check_finance_subledger_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_ar_account := app.resolve_finance_posting_map_account(p_tenant_id, 'ar_control');
  v_ap_account := app.resolve_finance_posting_map_account(p_tenant_id, 'ap_control');

  select coalesce(sum(case when l.direction = 'debit' then l.amount else -l.amount end), 0) into v_ar_subledger_balance
    from app.finance_subledger_lines l join app.finance_subledger_batches b on b.id = l.batch_id
    where b.tenant_id = p_tenant_id and l.account_id = v_ar_account.id;

  select coalesce(sum(case when l.direction = 'credit' then l.amount else -l.amount end), 0) into v_ap_subledger_balance
    from app.finance_subledger_lines l join app.finance_subledger_batches b on b.id = l.batch_id
    where b.tenant_id = p_tenant_id and l.account_id = v_ap_account.id;

  select coalesce(sum(open_amount), 0) into v_ar_open_total from app.finance_ar_open_items where tenant_id = p_tenant_id and source_document_type = 'invoice';
  select coalesce(sum(open_amount), 0) into v_ap_open_total from app.finance_ap_open_items where tenant_id = p_tenant_id and source_document_type = 'vendor_bill';

  return jsonb_build_object(
    'arControlAccountCode', v_ar_account.code,
    'arControlSubledgerBalance', v_ar_subledger_balance,
    'arOpenItemTotal', v_ar_open_total,
    'arReconciled', v_ar_subledger_balance = v_ar_open_total,
    'apControlAccountCode', v_ap_account.code,
    'apControlSubledgerBalance', v_ap_subledger_balance,
    'apOpenItemTotal', v_ap_open_total,
    'apReconciled', v_ap_subledger_balance = v_ap_open_total
  );
end;
$function$
;


CREATE OR REPLACE FUNCTION app.get_finance_vendor_bill_lines(p_bill_id uuid, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_vendor_bill_lines
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_bill app.finance_vendor_bills;
begin
  select * into v_bill from app.finance_vendor_bills where id = p_bill_id;
  if not found then
    raise exception 'finance_vendor_bill_not_found: %', p_bill_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_vendor_bill_authority('View', v_bill.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, v_bill.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_vendor_bill_lines where bill_id = p_bill_id order by line_number asc;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.get_numbering_allocation_status(p_allocation_id uuid, p_actor_auth_user_id uuid)
 RETURNS app.numbering_allocations
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_allocation app.numbering_allocations;
begin
  select * into v_allocation from app.numbering_allocations where id = p_allocation_id;
  if not found then
    raise exception 'numbering_allocation_not_found: no numbering allocation %', p_allocation_id
      using errcode = 'no_data_found';
  end if;
  if not app.check_numbering_allocation_authority(v_allocation.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, v_allocation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return v_allocation;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.list_finance_accounts(p_tenant_id uuid, p_company_id uuid, p_status text, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_accounts
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
begin
  if not app.check_finance_account_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
    select * from app.finance_accounts
    where tenant_id = p_tenant_id
      and company_id is not distinct from p_company_id
      and (p_status is null or status = p_status)
    order by code asc;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.list_finance_aging_bucket_configs(p_tenant_id uuid, p_entity_type text, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_aging_bucket_configs
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
begin
  if not app.check_finance_aging_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_aging_bucket_configs
    where tenant_id = p_tenant_id and (p_entity_type is null or entity_type = p_entity_type)
    order by entity_type, version desc;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.list_finance_ap_open_items(p_tenant_id uuid, p_company_id uuid, p_vendor_master_id uuid, p_status text, p_overdue_only boolean, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_ap_open_items
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
begin
  if not app.check_finance_ap_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_ap_open_items
    where tenant_id = p_tenant_id
      and (p_company_id is null or company_id = p_company_id)
      and (p_vendor_master_id is null or vendor_master_id = p_vendor_master_id)
      and (p_status is null or status = p_status)
      and (not coalesce(p_overdue_only, false) or (status <> 'settled' and due_date < current_date))
    order by due_date asc
    limit 200;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.list_finance_ar_open_items(p_tenant_id uuid, p_company_id uuid, p_customer_account_id uuid, p_status text, p_overdue_only boolean, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_ar_open_items
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
begin
  if not app.check_finance_ar_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_ar_open_items
    where tenant_id = p_tenant_id
      and (p_company_id is null or company_id = p_company_id)
      and (p_customer_account_id is null or customer_account_id = p_customer_account_id)
      and (p_status is null or status = p_status)
      and (not coalesce(p_overdue_only, false) or (status <> 'paid' and due_date < current_date))
    order by due_date asc
    limit 200;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.list_finance_bank_accounts(p_tenant_id uuid, p_company_id uuid, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_bank_accounts
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
begin
  if not app.check_finance_cash_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_bank_accounts
    where tenant_id = p_tenant_id and (p_company_id is null or company_id = p_company_id)
    order by created_at desc
    limit 200;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.list_finance_bank_transactions(p_tenant_id uuid, p_bank_account_id uuid, p_match_status text, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_bank_transactions
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
begin
  if not app.check_finance_cash_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_bank_transactions
    where tenant_id = p_tenant_id
      and (p_bank_account_id is null or bank_account_id = p_bank_account_id)
      and (p_match_status is null or match_status = p_match_status)
    order by transaction_date desc
    limit 200;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.list_finance_exchange_rates(p_tenant_id uuid, p_rate_type text, p_source_currency text, p_target_currency text, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_exchange_rates
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
begin
  if not app.check_finance_exchange_rate_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
    select * from app.finance_exchange_rates
    where coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(p_tenant_id, '00000000-0000-0000-0000-000000000000'::uuid)
      and (p_rate_type is null or rate_type = p_rate_type)
      and (p_source_currency is null or source_currency = p_source_currency)
      and (p_target_currency is null or target_currency = p_target_currency)
    order by effective_from desc;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.list_finance_fiscal_periods(p_tenant_id uuid, p_company_id uuid, p_calendar_id uuid, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_fiscal_periods
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
begin
  if not app.check_finance_period_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
    select * from app.finance_fiscal_periods
    where tenant_id = p_tenant_id
      and company_id is not distinct from p_company_id
      and (p_calendar_id is null or calendar_id = p_calendar_id)
    order by sequence_number asc;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.list_finance_invoices(p_tenant_id uuid, p_company_id uuid, p_customer_account_id uuid, p_status text, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_invoices
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
begin
  if not app.check_finance_invoice_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_invoices
    where tenant_id = p_tenant_id
      and (p_company_id is null or company_id = p_company_id)
      and (p_customer_account_id is null or customer_account_id = p_customer_account_id)
      and (p_status is null or status = p_status)
    order by created_at desc
    limit 200;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.list_finance_journal_corrections(p_tenant_id uuid, p_company_id uuid, p_correction_type text, p_status text, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_journal_corrections
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
begin
  if not app.check_finance_correction_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_journal_corrections
    where tenant_id = p_tenant_id
      and (p_company_id is null or company_id = p_company_id)
      and (p_correction_type is null or correction_type = p_correction_type)
      and (p_status is null or status = p_status)
    order by created_at desc
    limit 200;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.list_finance_period_locks(p_tenant_id uuid, p_company_id uuid, p_period_id uuid, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_period_locks
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
begin
  if not app.check_finance_period_lock_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_period_locks
    where tenant_id = p_tenant_id
      and (p_company_id is null or company_id = p_company_id)
      and (p_period_id is null or period_id = p_period_id)
    order by created_at desc
    limit 200;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.list_finance_receipts(p_tenant_id uuid, p_company_id uuid, p_customer_account_id uuid, p_status text, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_receipts
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
begin
  if not app.check_finance_receipt_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_receipts
    where tenant_id = p_tenant_id
      and (p_company_id is null or company_id = p_company_id)
      and (p_customer_account_id is null or customer_account_id = p_customer_account_id)
      and (p_status is null or status = p_status)
    order by receipt_date desc
    limit 200;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.list_finance_reconciliation_exceptions(p_run_id uuid, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_reconciliation_exceptions
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_run app.finance_reconciliation_runs;
begin
  select * into v_run from app.finance_reconciliation_runs where id = p_run_id;
  if not found then
    raise exception 'finance_reconciliation_run_not_found: %', p_run_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_reconciliation_authority('View', v_run.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, v_run.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_reconciliation_exceptions where run_id = p_run_id order by created_at asc;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.list_finance_reconciliation_runs(p_tenant_id uuid, p_company_id uuid, p_scope text, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_reconciliation_runs
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
begin
  if not app.check_finance_reconciliation_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_reconciliation_runs
    where tenant_id = p_tenant_id
      and (p_company_id is null or company_id = p_company_id)
      and (p_scope is null or scope = p_scope)
    order by created_at desc
    limit 200;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.list_finance_settlements(p_tenant_id uuid, p_company_id uuid, p_vendor_master_id uuid, p_status text, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_settlements
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
begin
  if not app.check_finance_settlement_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_settlements
    where tenant_id = p_tenant_id
      and (p_company_id is null or company_id = p_company_id)
      and (p_vendor_master_id is null or vendor_master_id = p_vendor_master_id)
      and (p_status is null or status = p_status)
    order by created_at desc
    limit 200;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.list_finance_subledger_batches(p_tenant_id uuid, p_company_id uuid, p_source_type text, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_subledger_batches
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
begin
  if not app.check_finance_subledger_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_subledger_batches
    where tenant_id = p_tenant_id
      and (p_company_id is null or company_id = p_company_id)
      and (p_source_type is null or source_type = p_source_type)
    order by posted_at desc
    limit 200;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.list_finance_tax_codes(p_tenant_id uuid, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_tax_codes
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
begin
  if not app.check_finance_tax_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_tax_codes
    where (tenant_id = p_tenant_id or tenant_id is null) and is_active
    order by code;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.list_finance_tax_rule_versions(p_tenant_id uuid, p_tax_code_id uuid, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_tax_rule_versions
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
begin
  if not app.check_finance_tax_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_tax_rule_versions
    where (tenant_id = p_tenant_id or tenant_id is null)
      and (p_tax_code_id is null or tax_code_id = p_tax_code_id)
    order by effective_from desc;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.list_finance_vendor_bills(p_tenant_id uuid, p_company_id uuid, p_vendor_master_id uuid, p_status text, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_vendor_bills
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
begin
  if not app.check_finance_vendor_bill_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_vendor_bills
    where tenant_id = p_tenant_id
      and (p_company_id is null or company_id = p_company_id)
      and (p_vendor_master_id is null or vendor_master_id = p_vendor_master_id)
      and (p_status is null or status = p_status)
    order by created_at desc
    limit 200;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.list_n8n_action_allowlist()
 RETURNS SETOF app.n8n_action_allowlist
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
  select * from app.n8n_action_allowlist order by scope;
$function$
;


CREATE OR REPLACE FUNCTION app.preview_finance_config_impact(p_version_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_version app.config_versions;
  v_object app.config_objects;
  v_valid boolean;
  v_error text;
  v_item_count integer;
  v_pending_refs jsonb;
begin
  select * into v_version from app.config_versions where id = p_version_id;
  if not found then
    raise exception 'config_version_not_found: no config version %', p_version_id
      using errcode = 'no_data_found';
  end if;
  select * into v_object from app.config_objects where id = v_version.config_object_id;

  if not app.is_finance_config_type(v_object.config_type_code) then
    raise exception 'not_finance_config_type: % is not a Finance Configuration class', v_object.config_type_code
      using errcode = 'check_violation';
  end if;

  select count(*) into v_item_count from app.config_items where config_version_id = p_version_id;

  begin
    v_valid := app.validate_finance_config_version(p_version_id, v_object.config_type_code);
  exception
    when others then
      v_valid := false;
      v_error := sqlerrm;
  end;

  v_pending_refs := '[]'::jsonb;
  if v_object.config_type_code = 'finance_posting_map' then
    select coalesce(jsonb_agg(distinct value ->> 'accountCodeRef'), '[]'::jsonb)
    into v_pending_refs
    from app.config_items
    where config_version_id = p_version_id and value ->> 'accountCodeRef' is not null;
  end if;

  return jsonb_build_object(
    'configTypeCode', v_object.config_type_code,
    'valid', v_valid,
    'error', v_error,
    'itemCount', v_item_count,
    'pendingChartOfAccountsRefs', case when v_object.config_type_code = 'finance_posting_map' then v_pending_refs else null end
  );
end;
$function$
;


CREATE OR REPLACE FUNCTION app.preview_finance_subledger_posting(p_tenant_id uuid, p_lines jsonb, p_actor_auth_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_line jsonb;
  v_direction text;
  v_amount numeric;
  v_account app.finance_accounts;
  v_key text;
  v_debit_total numeric(14, 2) := 0;
  v_credit_total numeric(14, 2) := 0;
  v_resolved jsonb := '[]'::jsonb;
begin
  if not app.check_finance_subledger_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_lines is null or jsonb_array_length(p_lines) = 0 then
    raise exception 'finance_subledger_empty_batch: at least one line is required' using errcode = 'check_violation';
  end if;

  for v_line in select * from jsonb_array_elements(p_lines) loop
    v_direction := v_line ->> 'direction';
    v_amount := (v_line ->> 'amount')::numeric;
    if v_direction not in ('debit', 'credit') then
      raise exception 'finance_subledger_invalid_direction: % is not debit or credit', v_direction using errcode = 'check_violation';
    end if;
    if v_amount is null or v_amount <= 0 then
      raise exception 'finance_subledger_invalid_line_amount: line amount must be positive, got %', v_amount using errcode = 'check_violation';
    end if;

    if v_line ->> 'accountId' is not null then
      select * into v_account from app.finance_accounts where id = (v_line ->> 'accountId')::uuid and tenant_id = p_tenant_id;
      if not found then
        raise exception 'finance_subledger_unresolved_account: % is not a known account for tenant %', v_line ->> 'accountId', p_tenant_id
          using errcode = 'no_data_found';
      end if;
      v_key := null;
    else
      v_key := v_line ->> 'postingMapKey';
      v_account := app.resolve_finance_posting_map_account(p_tenant_id, v_key);
    end if;

    if v_direction = 'debit' then
      v_debit_total := v_debit_total + v_amount;
    else
      v_credit_total := v_credit_total + v_amount;
    end if;

    v_resolved := v_resolved || jsonb_build_array(jsonb_build_object(
      'postingMapKey', v_key, 'accountId', v_account.id, 'accountCode', v_account.code, 'direction', v_direction, 'amount', v_amount
    ));
  end loop;

  return jsonb_build_object('lines', v_resolved, 'debitTotal', v_debit_total, 'creditTotal', v_credit_total, 'balanced', v_debit_total = v_credit_total);
end;
$function$
;


CREATE OR REPLACE FUNCTION app.publish_finance_config_version(p_version_id uuid, p_actor_auth_user_id uuid, p_effective_from timestamp with time zone, p_actor_label text)
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

  if not app.is_finance_config_type(v_object.config_type_code) then
    raise exception 'not_finance_config_type: % is not a Finance Configuration class', v_object.config_type_code
      using errcode = 'check_violation';
  end if;
  if not app.check_finance_config_authority('Approve', v_object.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_object.tenant_id
      using errcode = 'insufficient_privilege';
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
$function$
;


CREATE OR REPLACE FUNCTION app.rollback_finance_config_version(p_target_version_id uuid, p_actor_auth_user_id uuid, p_reason text, p_actor_label text)
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

  if not app.is_finance_config_type(v_object.config_type_code) then
    raise exception 'not_finance_config_type: % is not a Finance Configuration class', v_object.config_type_code
      using errcode = 'check_violation';
  end if;
  if not app.check_finance_config_authority('Approve', v_object.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_object.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return app.rollback_config_version(p_target_version_id, p_actor_auth_user_id, p_reason, p_actor_label);
end;
$function$
;


CREATE OR REPLACE FUNCTION app.search_finance_ap_candidates_for_settlement(p_tenant_id uuid, p_vendor_master_id uuid, p_currency text, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_ap_open_items
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
begin
  if not app.check_finance_settlement_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_ap_open_items
    where tenant_id = p_tenant_id
      and vendor_master_id = p_vendor_master_id
      and currency = p_currency
      and status <> 'settled'
      and not is_held
    order by due_date asc
    limit 200;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.search_finance_ar_candidates_for_receipt(p_receipt_id uuid, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_ar_open_items
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_receipt app.finance_receipts;
begin
  select * into v_receipt from app.finance_receipts where id = p_receipt_id;
  if not found then
    raise exception 'finance_receipt_not_found: %', p_receipt_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_receipt_authority('View', v_receipt.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, v_receipt.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_ar_open_items
    where tenant_id = v_receipt.tenant_id
      and customer_account_id = v_receipt.customer_account_id
      and currency = v_receipt.currency
      and status <> 'paid'
      and not is_held
    order by due_date asc
    limit 200;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.set_finance_config_items(p_version_id uuid, p_items jsonb, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_version app.config_versions;
  v_object app.config_objects;
begin
  select * into v_version from app.config_versions where id = p_version_id;
  if not found then
    raise exception 'config_version_not_found: no config version %', p_version_id
      using errcode = 'no_data_found';
  end if;
  select * into v_object from app.config_objects where id = v_version.config_object_id;

  if not app.is_finance_config_type(v_object.config_type_code) then
    raise exception 'not_finance_config_type: % is not a Finance Configuration class', v_object.config_type_code
      using errcode = 'check_violation';
  end if;
  if not app.check_finance_config_authority('Edit', v_object.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_object.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return app.set_config_items(p_version_id, p_items, p_actor_auth_user_id, p_actor_label);
end;
$function$
;


CREATE OR REPLACE FUNCTION app.validate_automation_rule_definition(p_trigger_event_type text, p_conditions jsonb, p_actions jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_cond jsonb;
  v_action jsonb;
  v_action_type text;
  v_job_type text;
begin
  if coalesce(length(trim(p_trigger_event_type)), 0) = 0 then
    raise exception 'automation_rule_missing_trigger: a trigger_event_type is required to publish'
      using errcode = 'check_violation';
  end if;

  if not app.validate_config_value(coalesce(p_conditions, '[]'::jsonb)) then
    raise exception 'automation_rule_unsafe_conditions: conditions failed structural validation'
      using errcode = 'check_violation';
  end if;
  if p_conditions is not null and jsonb_typeof(p_conditions) <> 'array' then
    raise exception 'automation_rule_invalid_conditions: conditions must be a jsonb array'
      using errcode = 'check_violation';
  end if;
  for v_cond in select * from jsonb_array_elements(coalesce(p_conditions, '[]'::jsonb)) loop
    if coalesce(v_cond ->> 'field', '') = '' then
      raise exception 'automation_rule_condition_missing_field: every condition requires a field'
        using errcode = 'check_violation';
    end if;
    if coalesce(v_cond ->> 'operator', '') not in ('eq', 'neq', 'gt', 'gte', 'lt', 'lte', 'contains') then
      raise exception 'automation_rule_condition_invalid_operator: % is not a supported condition operator', v_cond ->> 'operator'
        using errcode = 'check_violation';
    end if;
    if not (v_cond ? 'value') then
      raise exception 'automation_rule_condition_missing_value: every condition requires a value'
        using errcode = 'check_violation';
    end if;
  end loop;

  if not app.validate_config_value(coalesce(p_actions, '[]'::jsonb)) then
    raise exception 'automation_rule_unsafe_actions: actions failed structural validation'
      using errcode = 'check_violation';
  end if;
  if p_actions is null or jsonb_typeof(p_actions) <> 'array' or jsonb_array_length(p_actions) = 0 then
    raise exception 'automation_rule_missing_actions: at least one action is required to publish'
      using errcode = 'check_violation';
  end if;
  if jsonb_array_length(p_actions) > 10 then
    raise exception 'automation_rule_too_many_actions: at most 10 actions are allowed per rule'
      using errcode = 'check_violation';
  end if;

  for v_action in select * from jsonb_array_elements(p_actions) loop
    v_action_type := v_action ->> 'action_type';
    if v_action_type not in ('notify', 'transition_workflow', 'enqueue_job') then
      raise exception 'automation_rule_invalid_action_type: % is not a supported action_type', v_action_type
        using errcode = 'check_violation';
    end if;

    if v_action_type = 'notify' then
      if coalesce(v_action ->> 'notification_type_code', '') = '' then
        raise exception 'automation_rule_action_missing_notification_type: a notify action requires notification_type_code'
          using errcode = 'check_violation';
      end if;
      if not exists (select 1 from app.notification_types where code = v_action ->> 'notification_type_code') then
        raise exception 'automation_rule_action_unknown_notification_type: % is not a registered notification type', v_action ->> 'notification_type_code'
          using errcode = 'check_violation';
      end if;
      if coalesce(v_action ->> 'channel', '') = '' then
        raise exception 'automation_rule_action_missing_channel: a notify action requires channel'
          using errcode = 'check_violation';
      end if;
      if coalesce(v_action ->> 'recipient_field', '') = '' then
        raise exception 'automation_rule_action_missing_recipient_field: a notify action requires recipient_field (the event payload key holding the recipient''s auth_user_id)'
          using errcode = 'check_violation';
      end if;
    elsif v_action_type = 'transition_workflow' then
      if coalesce(v_action ->> 'instance_id_field', '') = '' then
        raise exception 'automation_rule_action_missing_instance_field: a transition_workflow action requires instance_id_field'
          using errcode = 'check_violation';
      end if;
      if coalesce(v_action ->> 'to_state', '') = '' then
        raise exception 'automation_rule_action_missing_to_state: a transition_workflow action requires to_state'
          using errcode = 'check_violation';
      end if;
    elsif v_action_type = 'enqueue_job' then
      v_job_type := v_action ->> 'job_type';
      if v_job_type is distinct from 'automation_action_execution' then
        raise exception 'automation_rule_action_invalid_job_type: an enqueue_job action may only target automation_action_execution, got %', v_job_type
          using errcode = 'check_violation';
      end if;
    end if;
  end loop;

  return true;
end;
$function$
;


CREATE OR REPLACE FUNCTION app.validate_custom_field_values(p_config_version_id uuid, p_values jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_fields jsonb;
  v_field jsonb;
  v_field_code text;
  v_field_type text;
  v_options jsonb;
  v_condition jsonb;
  v_visible boolean;
  v_value jsonb;
  v_validators jsonb;
  v_validator jsonb;
  v_key text;
  v_declared_codes text[] := array[]::text[];
begin
  select value into v_fields from app.config_items where config_version_id = p_config_version_id and key = 'fields';
  if v_fields is null then
    raise exception 'custom_field_missing_fields: config version % has no ''fields'' item', p_config_version_id
      using errcode = 'check_violation';
  end if;

  for v_field in select * from jsonb_array_elements(v_fields) loop
    v_declared_codes := v_declared_codes || (v_field ->> 'code');
  end loop;

  for v_key in select jsonb_object_keys(coalesce(p_values, '{}'::jsonb)) loop
    if not (v_key = any (v_declared_codes)) then
      raise exception 'custom_field_unknown_field: % is not a declared field on this form', v_key
        using errcode = 'check_violation';
    end if;
  end loop;

  for v_field in select * from jsonb_array_elements(v_fields) loop
    v_field_code := v_field ->> 'code';
    v_field_type := v_field ->> 'type';
    v_options := v_field -> 'options';
    v_condition := v_field -> 'condition';
    v_validators := coalesce(v_field -> 'validators', '[]'::jsonb);
    v_value := p_values -> v_field_code;
    v_visible := app.evaluate_field_condition(v_condition, p_values);

    if coalesce((v_field ->> 'required')::boolean, false) and v_visible and v_value is null then
      raise exception 'custom_field_required_missing: field % is required and currently visible, but no value was provided', v_field_code
        using errcode = 'check_violation';
    end if;

    if v_value is null or jsonb_typeof(v_value) = 'null' then
      continue;
    end if;

    if v_field_type in ('text', 'textarea', 'email') and jsonb_typeof(v_value) <> 'string' then
      raise exception 'custom_field_invalid_value: field % expects a string value', v_field_code
        using errcode = 'check_violation';
    elsif v_field_type = 'number' and jsonb_typeof(v_value) <> 'number' then
      raise exception 'custom_field_invalid_value: field % expects a number value', v_field_code
        using errcode = 'check_violation';
    elsif v_field_type = 'boolean' and jsonb_typeof(v_value) <> 'boolean' then
      raise exception 'custom_field_invalid_value: field % expects a boolean value', v_field_code
        using errcode = 'check_violation';
    elsif v_field_type = 'date' and (jsonb_typeof(v_value) <> 'string' or (v_value #>> '{}') !~ '^\d{4}-\d{2}-\d{2}$') then
      raise exception 'custom_field_invalid_value: field % expects a YYYY-MM-DD date string', v_field_code
        using errcode = 'check_violation';
    elsif v_field_type = 'email' and (v_value #>> '{}') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
      raise exception 'custom_field_invalid_value: field % expects a valid email address', v_field_code
        using errcode = 'check_violation';
    elsif v_field_type = 'select' and (jsonb_typeof(v_value) <> 'string' or not (v_options ? (v_value #>> '{}'))) then
      raise exception 'custom_field_invalid_value: field %''s value is not one of its declared options', v_field_code
        using errcode = 'check_violation';
    elsif v_field_type = 'multiselect' then
      if jsonb_typeof(v_value) <> 'array' then
        raise exception 'custom_field_invalid_value: field % expects an array of options', v_field_code
          using errcode = 'check_violation';
      end if;
      if exists (select 1 from jsonb_array_elements_text(v_value) e where not (v_options ? e)) then
        raise exception 'custom_field_invalid_value: field %''s value contains an option not in its declared options', v_field_code
          using errcode = 'check_violation';
      end if;
    end if;

    for v_validator in select * from jsonb_array_elements(v_validators) loop
      if v_validator ->> 'type' = 'min_length' and length(v_value #>> '{}') < (v_validator ->> 'value')::integer then
        raise exception 'custom_field_validator_failed: field % is shorter than its min_length validator', v_field_code
          using errcode = 'check_violation';
      elsif v_validator ->> 'type' = 'max_length' and length(v_value #>> '{}') > (v_validator ->> 'value')::integer then
        raise exception 'custom_field_validator_failed: field % is longer than its max_length validator', v_field_code
          using errcode = 'check_violation';
      elsif v_validator ->> 'type' = 'min' and (v_value #>> '{}')::numeric < (v_validator ->> 'value')::numeric then
        raise exception 'custom_field_validator_failed: field % is below its min validator', v_field_code
          using errcode = 'check_violation';
      elsif v_validator ->> 'type' = 'max' and (v_value #>> '{}')::numeric > (v_validator ->> 'value')::numeric then
        raise exception 'custom_field_validator_failed: field % is above its max validator', v_field_code
          using errcode = 'check_violation';
      elsif v_validator ->> 'type' = 'pattern' and (v_value #>> '{}') !~ (v_validator ->> 'value') then
        raise exception 'custom_field_validator_failed: field % does not match its pattern validator', v_field_code
          using errcode = 'check_violation';
      end if;
    end loop;
  end loop;

  return true;
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
  -- HDN-373 Tier C fix: either level is a legitimate caller (app.post_finance_subledger_batch
  -- and app.allocate_finance_receipt both require only FIN:Edit at their own front door;
  -- app.post_finance_correction requires FIN:Approve, which this OR already admits).
  -- Still denies an actor holding neither -- ISS-2026-183's own original concern.
  if not (app.check_finance_journal_authority('Edit', p_tenant_id, p_actor_auth_user_id)
          or app.check_finance_journal_authority('Approve', p_tenant_id, p_actor_auth_user_id)) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit or FIN:Approve for tenant %', p_actor_auth_user_id, p_tenant_id
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

-- ===========================================================================
-- Gap 3 -- two of the 57 (Gap 1) had no authority check of their own, and it turned out
-- to be a real cross-tenant disclosure, not a false alarm
-- ===========================================================================
--
-- Converting the 57 to SECURITY DEFINER surfaced them to `scripts/db-tests/rbac-
-- enforcement.sql`'s own pre-existing ATW-032 authority-surface sweep, exactly as it
-- surfaced `ISS-2026-183` for `app.create_and_post_finance_system_journal` in
-- `20260810700000`. Four functions were newly flagged; two are genuinely correct by
-- design and added to that sweep's own exemption list (`app.list_n8n_action_allowlist`,
-- `app.validate_automation_rule_definition` -- see `rbac-enforcement.sql`'s own updated
-- comment for the full reasoning). **The other two are a real, live cross-tenant
-- disclosure**, distinct from `HDN-BLK-015`'s own reachability shape:
--
-- `app.preview_finance_config_impact(p_version_id uuid)` and `app.
-- validate_custom_field_values(p_config_version_id uuid, p_values jsonb)` both resolve a
-- caller-supplied config-version UUID straight into `app.config_versions`/`app.
-- config_objects`/`app.config_items` with no check at all that the resolved config
-- object's own `tenant_id` has anything to do with the calling session -- any
-- authenticated member of ANY tenant who knows or guesses another tenant's config-version
-- UUID gets back that tenant's Finance posting-map validity state, item count and pending
-- chart-of-accounts references (`preview_finance_config_impact`), or another tenant's
-- custom-form field definitions -- codes, types, options, validators -- via the
-- function's own validation error text (`validate_custom_field_values`). Neither function
-- takes a `p_actor_auth_user_id` parameter to check identity against (there is nothing to
-- forge), so the fix is a plain `app.has_active_tenant_membership` check against the
-- resolved object's own tenant, using the session's real identity (`auth.uid()`, that
-- function's own default), not a caller-supplied one.
--
-- Neither function is reachable via any nested nor nested-through-Finance caller with its
-- OWN independent tenant check upstream (grep-confirmed) -- both were exposed directly.

create or replace function app.preview_finance_config_impact(p_version_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'app', 'pg_temp'
as $function$
declare
  v_version app.config_versions;
  v_object app.config_objects;
  v_valid boolean;
  v_error text;
  v_item_count integer;
  v_pending_refs jsonb;
begin
  select * into v_version from app.config_versions where id = p_version_id;
  if not found then
    raise exception 'config_version_not_found: no config version %', p_version_id
      using errcode = 'no_data_found';
  end if;
  select * into v_object from app.config_objects where id = v_version.config_object_id;

  -- HDN-373 Tier C fix: the caller must be a genuine active member of the tenant this
  -- config version belongs to -- neither table nor row is otherwise scoped here. NULL
  -- auth.uid() (service_role/superuser, no genuine end-user session) is an intentional
  -- no-op, mirroring app.assert_actor_is_session_identity's own established convention
  -- for exactly this shape (a function reachable both by real authenticated sessions and
  -- by internal/system callers with no session identity at all).
  if auth.uid() is not null and not app.has_active_tenant_membership(v_object.tenant_id) then
    raise exception 'insufficient_authority: caller holds no active membership in tenant %', v_object.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.is_finance_config_type(v_object.config_type_code) then
    raise exception 'not_finance_config_type: % is not a Finance Configuration class', v_object.config_type_code
      using errcode = 'check_violation';
  end if;

  select count(*) into v_item_count from app.config_items where config_version_id = p_version_id;

  begin
    v_valid := app.validate_finance_config_version(p_version_id, v_object.config_type_code);
  exception
    when others then
      v_valid := false;
      v_error := sqlerrm;
  end;

  v_pending_refs := '[]'::jsonb;
  if v_object.config_type_code = 'finance_posting_map' then
    select coalesce(jsonb_agg(distinct value ->> 'accountCodeRef'), '[]'::jsonb)
    into v_pending_refs
    from app.config_items
    where config_version_id = p_version_id and value ->> 'accountCodeRef' is not null;
  end if;

  return jsonb_build_object(
    'configTypeCode', v_object.config_type_code,
    'valid', v_valid,
    'error', v_error,
    'itemCount', v_item_count,
    'pendingChartOfAccountsRefs', case when v_object.config_type_code = 'finance_posting_map' then v_pending_refs else null end
  );
end;
$function$
;

create or replace function app.validate_custom_field_values(p_config_version_id uuid, p_values jsonb)
returns boolean
language plpgsql
security definer
set search_path to 'app', 'pg_temp'
as $function$
declare
  v_tenant_id uuid;
  v_fields jsonb;
  v_field jsonb;
  v_field_code text;
  v_field_type text;
  v_options jsonb;
  v_condition jsonb;
  v_visible boolean;
  v_value jsonb;
  v_validators jsonb;
  v_validator jsonb;
  v_key text;
  v_declared_codes text[] := array[]::text[];
begin
  -- HDN-373 Tier C fix: resolve this version's own tenant and require active
  -- membership before reading its field definitions. A nonexistent p_config_version_id
  -- leaves v_tenant_id null (skipping this check) and falls through unchanged to the
  -- existing custom_field_missing_fields exception below, preserving that error shape.
  -- NULL auth.uid() (service_role/superuser) is an intentional no-op, mirroring app.
  -- assert_actor_is_session_identity's own established convention -- see app.
  -- preview_finance_config_impact's identical guard, added in this same migration.
  select co.tenant_id into v_tenant_id
  from app.config_versions cv join app.config_objects co on co.id = cv.config_object_id
  where cv.id = p_config_version_id;
  if v_tenant_id is not null and auth.uid() is not null and not app.has_active_tenant_membership(v_tenant_id) then
    raise exception 'insufficient_authority: caller holds no active membership in tenant %', v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select value into v_fields from app.config_items where config_version_id = p_config_version_id and key = 'fields';
  if v_fields is null then
    raise exception 'custom_field_missing_fields: config version % has no ''fields'' item', p_config_version_id
      using errcode = 'check_violation';
  end if;

  for v_field in select * from jsonb_array_elements(v_fields) loop
    v_declared_codes := v_declared_codes || (v_field ->> 'code');
  end loop;

  for v_key in select jsonb_object_keys(coalesce(p_values, '{}'::jsonb)) loop
    if not (v_key = any (v_declared_codes)) then
      raise exception 'custom_field_unknown_field: % is not a declared field on this form', v_key
        using errcode = 'check_violation';
    end if;
  end loop;

  for v_field in select * from jsonb_array_elements(v_fields) loop
    v_field_code := v_field ->> 'code';
    v_field_type := v_field ->> 'type';
    v_options := v_field -> 'options';
    v_condition := v_field -> 'condition';
    v_validators := coalesce(v_field -> 'validators', '[]'::jsonb);
    v_value := p_values -> v_field_code;
    v_visible := app.evaluate_field_condition(v_condition, p_values);

    if coalesce((v_field ->> 'required')::boolean, false) and v_visible and v_value is null then
      raise exception 'custom_field_required_missing: field % is required and currently visible, but no value was provided', v_field_code
        using errcode = 'check_violation';
    end if;

    if v_value is null or jsonb_typeof(v_value) = 'null' then
      continue;
    end if;

    if v_field_type in ('text', 'textarea', 'email') and jsonb_typeof(v_value) <> 'string' then
      raise exception 'custom_field_invalid_value: field % expects a string value', v_field_code
        using errcode = 'check_violation';
    elsif v_field_type = 'number' and jsonb_typeof(v_value) <> 'number' then
      raise exception 'custom_field_invalid_value: field % expects a number value', v_field_code
        using errcode = 'check_violation';
    elsif v_field_type = 'boolean' and jsonb_typeof(v_value) <> 'boolean' then
      raise exception 'custom_field_invalid_value: field % expects a boolean value', v_field_code
        using errcode = 'check_violation';
    elsif v_field_type = 'date' and (jsonb_typeof(v_value) <> 'string' or (v_value #>> '{}') !~ '^\d{4}-\d{2}-\d{2}$') then
      raise exception 'custom_field_invalid_value: field % expects a YYYY-MM-DD date string', v_field_code
        using errcode = 'check_violation';
    elsif v_field_type = 'email' and (v_value #>> '{}') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
      raise exception 'custom_field_invalid_value: field % expects a valid email address', v_field_code
        using errcode = 'check_violation';
    elsif v_field_type = 'select' and (jsonb_typeof(v_value) <> 'string' or not (v_options ? (v_value #>> '{}'))) then
      raise exception 'custom_field_invalid_value: field %''s value is not one of its declared options', v_field_code
        using errcode = 'check_violation';
    elsif v_field_type = 'multiselect' then
      if jsonb_typeof(v_value) <> 'array' then
        raise exception 'custom_field_invalid_value: field % expects an array of options', v_field_code
          using errcode = 'check_violation';
      end if;
      if exists (select 1 from jsonb_array_elements_text(v_value) e where not (v_options ? e)) then
        raise exception 'custom_field_invalid_value: field %''s value contains an option not in its declared options', v_field_code
          using errcode = 'check_violation';
      end if;
    end if;

    for v_validator in select * from jsonb_array_elements(v_validators) loop
      if v_validator ->> 'type' = 'min_length' and length(v_value #>> '{}') < (v_validator ->> 'value')::integer then
        raise exception 'custom_field_validator_failed: field % is shorter than its min_length validator', v_field_code
          using errcode = 'check_violation';
      elsif v_validator ->> 'type' = 'max_length' and length(v_value #>> '{}') > (v_validator ->> 'value')::integer then
        raise exception 'custom_field_validator_failed: field % is longer than its max_length validator', v_field_code
          using errcode = 'check_violation';
      elsif v_validator ->> 'type' = 'min' and (v_value #>> '{}')::numeric < (v_validator ->> 'value')::numeric then
        raise exception 'custom_field_validator_failed: field % is below its min validator', v_field_code
          using errcode = 'check_violation';
      elsif v_validator ->> 'type' = 'max' and (v_value #>> '{}')::numeric > (v_validator ->> 'value')::numeric then
        raise exception 'custom_field_validator_failed: field % is above its max validator', v_field_code
          using errcode = 'check_violation';
      elsif v_validator ->> 'type' = 'pattern' and (v_value #>> '{}') !~ (v_validator ->> 'value') then
        raise exception 'custom_field_validator_failed: field % does not match its pattern validator', v_field_code
          using errcode = 'check_violation';
      end if;
    end loop;
  end loop;

  return true;
end;
$function$
;

revoke execute on all functions in schema app from public;
