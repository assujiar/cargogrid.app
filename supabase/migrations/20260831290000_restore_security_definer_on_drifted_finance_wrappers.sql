-- ISS-2026-318 (docs/runtime/KNOWN_ISSUES.md) -- 111 public.* finance wrappers had lost their
-- `security definer` flag on the live project while the migration set declares it.
--
-- HOW IT WAS FOUND. ISS-2026-302's migration rebuilds public.* wrappers from their LIVE
-- pg_get_functiondef output. The first db-test run after that failed immediately, naming 29
-- wrappers whose definer/invoker mode now differed from their app.* counterpart. The gate was
-- right and the input was wrong: the live wrappers are language sql with no SECURITY DEFINER,
-- while 20260826000000_create_public_api_data_wrappers.sql -- the migration that created every
-- one of them -- declares `security definer` explicitly and comments each as "a thin
-- security-definer pass-through". Copying live into a migration is what made the divergence
-- visible. Those 29 were repaired inside 20260831270000; a direct live query then returned 111
-- more.
--
-- CORRECTION TO ISS-2026-318 AS FILED. That entry says "every one is a finance wrapper". 107
-- are (106 finance-named plus public.get_numbering_allocation_status, which finance numbering
-- uses); FOUR are not: public.enqueue_job, public.list_n8n_action_allowlist,
-- public.validate_automation_rule_definition and public.validate_custom_field_values. The
-- shape of the finding is unchanged -- one event, not gradual decay -- but "all finance" was a
-- guess from the first 25 names and it was wrong. The ledger entry is corrected in place.
--
-- THE LIVE BODIES ARE OTHERWISE IDENTICAL, VERIFIED RATHER THAN ASSUMED. Copying a live
-- definition into a migration imports whatever else has drifted with it, so before generating
-- anything the 111 live definitions were compared against the same 111 from a disposable
-- database built from the migration set alone. All 111 match exactly once the SECURITY DEFINER
-- token is set aside -- same body, same volatility, same search_path, same return type. The
-- flag is the only thing that moved.
--
-- THAT THE MIGRATION SET DECLARES DEFINER FOR ALL 111 IS PROVEN, NOT ASSUMED.
-- scripts/db-tests/public-api-wrapper-regression.sql asserts, exhaustively and by join on
-- proname, that no public.* wrapper's mode differs from its app.* counterpart -- and it passes
-- against a migration-built database. All 111 app.* functions here are definer. So on a
-- migration-built database all 111 public.* wrappers are definer too. No grep required.
--
-- NOT AN EXPOSURE, AND THE DIRECTION MATTERS. An invoker-rights wrapper is MORE restrictive
-- than a definer one: the caller must hold EXECUTE on the inner app.* function in their own
-- right. Those grants exist, so nothing is broken today and nothing is reachable that was not
-- reachable before. What is wrong is that these functions do not behave the way the code says
-- they behave. If someone later tightens an app.* grant -- an ordinary hardening step this
-- backlog has taken repeatedly -- the finance wrappers would start failing in production for
-- reasons nobody could find by reading the repository, because the repository says they run as
-- their owner and they do not.
--
-- Each of the 111 below is the LIVE pg_get_functiondef output with SECURITY DEFINER inserted
-- after its LANGUAGE line and nothing else changed -- body, volatility, search_path and return
-- type all preserved verbatim, and the absence of an existing SECURITY DEFINER asserted per
-- function before emitting. DROP + CREATE rather than CREATE OR REPLACE, because replacing a
-- function does not reliably reset its security attribute, and grants are re-emitted from each
-- wrapper's own live grantee set rather than assumed.
--
-- WHAT THIS DOES NOT FIX. The parity gate still cannot see live drift: it runs against a
-- database built from the migrations, so it compares what the migrations say to what the
-- migrations say. Every divergence of this class is invisible to it by construction, and always
-- will be. A live-versus-migrations reconciliation is a separate design question -- CI has no
-- live database credentials and should not have any -- and stays open under ISS-2026-318's own
-- residual rather than being claimed here.
-- A SECOND, DISTINCT DRIFT FOUND WHILE VERIFYING THIS ONE, and repaired here too.
-- public.check_finance_journal_authority has also lost its `authenticated` grant live, while
-- the migration set grants it. Generating this migration's grants from the LIVE grantee sets
-- would have carried that loss into the migration set -- and did, on the first attempt: the
-- wrapper-parity gate rejected it immediately, naming that one function. So the grants below
-- come from a disposable database built from the migration set alone, not from the live
-- project. Only that one wrapper's grant set differs; the other 110 match.
--
-- The general lesson, and the reason this file says it out loud: when a live definition is the
-- input to a migration, EVERY attribute of it is an input, not just the one being repaired.
-- Body, volatility, search_path, return type and grants were each compared against the
-- migration-built reference before anything was emitted.


-- 1. public.acknowledge_finance_period_checklist_item -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.acknowledge_finance_period_checklist_item(p_period_id uuid, p_item_key text, p_satisfied boolean, p_reason text, p_actor_auth_user_id uuid, p_actor_label text);

create function public.acknowledge_finance_period_checklist_item(p_period_id uuid, p_item_key text, p_satisfied boolean, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_period_close_checklist_items
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.acknowledge_finance_period_checklist_item(p_period_id, p_item_key, p_satisfied, p_reason, p_actor_auth_user_id, p_actor_label);
$function$;

revoke execute on function public.acknowledge_finance_period_checklist_item(p_period_id uuid, p_item_key text, p_satisfied boolean, p_reason text, p_actor_auth_user_id uuid, p_actor_label text) from anon, authenticated, service_role, public;
grant execute on function public.acknowledge_finance_period_checklist_item(p_period_id uuid, p_item_key text, p_satisfied boolean, p_reason text, p_actor_auth_user_id uuid, p_actor_label text) to authenticated;
grant execute on function public.acknowledge_finance_period_checklist_item(p_period_id uuid, p_item_key text, p_satisfied boolean, p_reason text, p_actor_auth_user_id uuid, p_actor_label text) to service_role;

-- 2. public.allocate_finance_receipt -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.allocate_finance_receipt(p_receipt_id uuid, p_idempotency_key text, p_allocations jsonb, p_actor_auth_user_id uuid, p_actor_label text);

create function public.allocate_finance_receipt(p_receipt_id uuid, p_idempotency_key text, p_allocations jsonb, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_receipts
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.allocate_finance_receipt(p_receipt_id, p_idempotency_key, p_allocations, p_actor_auth_user_id, p_actor_label);
$function$;

revoke execute on function public.allocate_finance_receipt(p_receipt_id uuid, p_idempotency_key text, p_allocations jsonb, p_actor_auth_user_id uuid, p_actor_label text) from anon, authenticated, service_role, public;
grant execute on function public.allocate_finance_receipt(p_receipt_id uuid, p_idempotency_key text, p_allocations jsonb, p_actor_auth_user_id uuid, p_actor_label text) to authenticated;
grant execute on function public.allocate_finance_receipt(p_receipt_id uuid, p_idempotency_key text, p_allocations jsonb, p_actor_auth_user_id uuid, p_actor_label text) to service_role;

-- 3. public.amend_finance_account_draft -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.amend_finance_account_draft(p_account_id uuid, p_expected_version integer, p_name text, p_currency_restriction text, p_actor_auth_user_id uuid, p_actor_label text);

create function public.amend_finance_account_draft(p_account_id uuid, p_expected_version integer, p_name text, p_currency_restriction text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_accounts
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.amend_finance_account_draft(p_account_id, p_expected_version, p_name, p_currency_restriction, p_actor_auth_user_id, p_actor_label);
$function$;

revoke execute on function public.amend_finance_account_draft(p_account_id uuid, p_expected_version integer, p_name text, p_currency_restriction text, p_actor_auth_user_id uuid, p_actor_label text) from anon, authenticated, service_role, public;
grant execute on function public.amend_finance_account_draft(p_account_id uuid, p_expected_version integer, p_name text, p_currency_restriction text, p_actor_auth_user_id uuid, p_actor_label text) to authenticated;
grant execute on function public.amend_finance_account_draft(p_account_id uuid, p_expected_version integer, p_name text, p_currency_restriction text, p_actor_auth_user_id uuid, p_actor_label text) to service_role;

-- 4. public.apply_finance_ap_settlement -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.apply_finance_ap_settlement(p_open_item_id uuid, p_amount numeric, p_source_type text, p_source_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text);

create function public.apply_finance_ap_settlement(p_open_item_id uuid, p_amount numeric, p_source_type text, p_source_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_ap_open_items
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.apply_finance_ap_settlement(p_open_item_id, p_amount, p_source_type, p_source_id, p_idempotency_key, p_actor_auth_user_id, p_actor_label);
$function$;

revoke execute on function public.apply_finance_ap_settlement(p_open_item_id uuid, p_amount numeric, p_source_type text, p_source_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text) from anon, authenticated, service_role, public;
grant execute on function public.apply_finance_ap_settlement(p_open_item_id uuid, p_amount numeric, p_source_type text, p_source_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text) to authenticated;
grant execute on function public.apply_finance_ap_settlement(p_open_item_id uuid, p_amount numeric, p_source_type text, p_source_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text) to service_role;

-- 5. public.apply_finance_ar_allocation -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.apply_finance_ar_allocation(p_open_item_id uuid, p_amount numeric, p_source_type text, p_source_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text);

create function public.apply_finance_ar_allocation(p_open_item_id uuid, p_amount numeric, p_source_type text, p_source_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_ar_open_items
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.apply_finance_ar_allocation(p_open_item_id, p_amount, p_source_type, p_source_id, p_idempotency_key, p_actor_auth_user_id, p_actor_label);
$function$;

revoke execute on function public.apply_finance_ar_allocation(p_open_item_id uuid, p_amount numeric, p_source_type text, p_source_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text) from anon, authenticated, service_role, public;
grant execute on function public.apply_finance_ar_allocation(p_open_item_id uuid, p_amount numeric, p_source_type text, p_source_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text) to authenticated;
grant execute on function public.apply_finance_ar_allocation(p_open_item_id uuid, p_amount numeric, p_source_type text, p_source_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text) to service_role;

-- 6. public.attach_finance_tax_rule_evidence -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.attach_finance_tax_rule_evidence(p_rule_id uuid, p_expected_version integer, p_evidence_reference_file_id uuid, p_evidence_note text, p_actor_auth_user_id uuid, p_actor_label text);

create function public.attach_finance_tax_rule_evidence(p_rule_id uuid, p_expected_version integer, p_evidence_reference_file_id uuid, p_evidence_note text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_tax_rule_versions
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.attach_finance_tax_rule_evidence(p_rule_id, p_expected_version, p_evidence_reference_file_id, p_evidence_note, p_actor_auth_user_id, p_actor_label);
$function$;

revoke execute on function public.attach_finance_tax_rule_evidence(p_rule_id uuid, p_expected_version integer, p_evidence_reference_file_id uuid, p_evidence_note text, p_actor_auth_user_id uuid, p_actor_label text) from anon, authenticated, service_role, public;
grant execute on function public.attach_finance_tax_rule_evidence(p_rule_id uuid, p_expected_version integer, p_evidence_reference_file_id uuid, p_evidence_note text, p_actor_auth_user_id uuid, p_actor_label text) to authenticated;
grant execute on function public.attach_finance_tax_rule_evidence(p_rule_id uuid, p_expected_version integer, p_evidence_reference_file_id uuid, p_evidence_note text, p_actor_auth_user_id uuid, p_actor_label text) to service_role;

-- 7. public.calculate_finance_tax -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.calculate_finance_tax(p_tenant_id uuid, p_tax_code text, p_base_amount numeric, p_as_of date, p_actor_auth_user_id uuid);

create function public.calculate_finance_tax(p_tenant_id uuid, p_tax_code text, p_base_amount numeric, p_as_of date, p_actor_auth_user_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.calculate_finance_tax(p_tenant_id, p_tax_code, p_base_amount, p_as_of, p_actor_auth_user_id);
$function$;

revoke execute on function public.calculate_finance_tax(p_tenant_id uuid, p_tax_code text, p_base_amount numeric, p_as_of date, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.calculate_finance_tax(p_tenant_id uuid, p_tax_code text, p_base_amount numeric, p_as_of date, p_actor_auth_user_id uuid) to authenticated;
grant execute on function public.calculate_finance_tax(p_tenant_id uuid, p_tax_code text, p_base_amount numeric, p_as_of date, p_actor_auth_user_id uuid) to service_role;

-- 8. public.capture_finance_receipt -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.capture_finance_receipt(p_tenant_id uuid, p_company_id uuid, p_customer_account_id uuid, p_receipt_reference text, p_receipt_date date, p_payer_name text, p_bank_account_label text, p_currency text, p_amount numeric, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text);

create function public.capture_finance_receipt(p_tenant_id uuid, p_company_id uuid, p_customer_account_id uuid, p_receipt_reference text, p_receipt_date date, p_payer_name text, p_bank_account_label text, p_currency text, p_amount numeric, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_receipts
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.capture_finance_receipt(p_tenant_id, p_company_id, p_customer_account_id, p_receipt_reference, p_receipt_date, p_payer_name, p_bank_account_label, p_currency, p_amount, p_idempotency_key, p_actor_auth_user_id, p_actor_label);
$function$;

revoke execute on function public.capture_finance_receipt(p_tenant_id uuid, p_company_id uuid, p_customer_account_id uuid, p_receipt_reference text, p_receipt_date date, p_payer_name text, p_bank_account_label text, p_currency text, p_amount numeric, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text) from anon, authenticated, service_role, public;
grant execute on function public.capture_finance_receipt(p_tenant_id uuid, p_company_id uuid, p_customer_account_id uuid, p_receipt_reference text, p_receipt_date date, p_payer_name text, p_bank_account_label text, p_currency text, p_amount numeric, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text) to authenticated;
grant execute on function public.capture_finance_receipt(p_tenant_id uuid, p_company_id uuid, p_customer_account_id uuid, p_receipt_reference text, p_receipt_date date, p_payer_name text, p_bank_account_label text, p_currency text, p_amount numeric, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text) to service_role;

-- 9. public.check_finance_account_authority -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.check_finance_account_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid);

create function public.check_finance_account_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.check_finance_account_authority(p_action, p_tenant_id, p_actor_auth_user_id);
$function$;

revoke execute on function public.check_finance_account_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.check_finance_account_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid) to service_role;

-- 10. public.check_finance_aging_authority -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.check_finance_aging_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid);

create function public.check_finance_aging_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.check_finance_aging_authority(p_action, p_tenant_id, p_actor_auth_user_id);
$function$;

revoke execute on function public.check_finance_aging_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.check_finance_aging_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid) to service_role;

-- 11. public.check_finance_ap_authority -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.check_finance_ap_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid);

create function public.check_finance_ap_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.check_finance_ap_authority(p_action, p_tenant_id, p_actor_auth_user_id);
$function$;

revoke execute on function public.check_finance_ap_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.check_finance_ap_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid) to service_role;

-- 12. public.check_finance_ar_authority -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.check_finance_ar_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid);

create function public.check_finance_ar_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.check_finance_ar_authority(p_action, p_tenant_id, p_actor_auth_user_id);
$function$;

revoke execute on function public.check_finance_ar_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.check_finance_ar_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid) to service_role;

-- 13. public.check_finance_cash_authority -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.check_finance_cash_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid);

create function public.check_finance_cash_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.check_finance_cash_authority(p_action, p_tenant_id, p_actor_auth_user_id);
$function$;

revoke execute on function public.check_finance_cash_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.check_finance_cash_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid) to service_role;

-- 14. public.check_finance_config_authority -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.check_finance_config_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid);

create function public.check_finance_config_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.check_finance_config_authority(p_action, p_tenant_id, p_actor_auth_user_id);
$function$;

revoke execute on function public.check_finance_config_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.check_finance_config_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid) to service_role;

-- 15. public.check_finance_correction_authority -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.check_finance_correction_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid);

create function public.check_finance_correction_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.check_finance_correction_authority(p_action, p_tenant_id, p_actor_auth_user_id);
$function$;

revoke execute on function public.check_finance_correction_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.check_finance_correction_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid) to service_role;

-- 16. public.check_finance_exchange_rate_authority -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.check_finance_exchange_rate_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid);

create function public.check_finance_exchange_rate_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.check_finance_exchange_rate_authority(p_action, p_tenant_id, p_actor_auth_user_id);
$function$;

revoke execute on function public.check_finance_exchange_rate_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.check_finance_exchange_rate_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid) to service_role;

-- 17. public.check_finance_idempotency_authority -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.check_finance_idempotency_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid);

create function public.check_finance_idempotency_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.check_finance_idempotency_authority(p_action, p_tenant_id, p_actor_auth_user_id);
$function$;

revoke execute on function public.check_finance_idempotency_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.check_finance_idempotency_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid) to service_role;

-- 18. public.check_finance_invoice_authority -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.check_finance_invoice_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid);

create function public.check_finance_invoice_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.check_finance_invoice_authority(p_action, p_tenant_id, p_actor_auth_user_id);
$function$;

revoke execute on function public.check_finance_invoice_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.check_finance_invoice_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid) to service_role;

-- 19. public.check_finance_journal_authority -- declared security definer by 20260826000000, live had drifted to invoker [grant set ALSO drifted live -- restored to the declared set]
drop function public.check_finance_journal_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid);

create function public.check_finance_journal_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.check_finance_journal_authority(p_action, p_tenant_id, p_actor_auth_user_id);
$function$;

revoke execute on function public.check_finance_journal_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.check_finance_journal_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid) to authenticated;
grant execute on function public.check_finance_journal_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid) to service_role;

-- 20. public.check_finance_period_authority -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.check_finance_period_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid);

create function public.check_finance_period_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.check_finance_period_authority(p_action, p_tenant_id, p_actor_auth_user_id);
$function$;

revoke execute on function public.check_finance_period_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.check_finance_period_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid) to service_role;

-- 21. public.check_finance_period_lock_authority -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.check_finance_period_lock_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid);

create function public.check_finance_period_lock_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.check_finance_period_lock_authority(p_action, p_tenant_id, p_actor_auth_user_id);
$function$;

revoke execute on function public.check_finance_period_lock_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.check_finance_period_lock_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid) to service_role;

-- 22. public.check_finance_receipt_authority -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.check_finance_receipt_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid);

create function public.check_finance_receipt_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.check_finance_receipt_authority(p_action, p_tenant_id, p_actor_auth_user_id);
$function$;

revoke execute on function public.check_finance_receipt_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.check_finance_receipt_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid) to service_role;

-- 23. public.check_finance_reconciliation_authority -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.check_finance_reconciliation_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid);

create function public.check_finance_reconciliation_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.check_finance_reconciliation_authority(p_action, p_tenant_id, p_actor_auth_user_id);
$function$;

revoke execute on function public.check_finance_reconciliation_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.check_finance_reconciliation_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid) to service_role;

-- 24. public.check_finance_settlement_authority -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.check_finance_settlement_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid);

create function public.check_finance_settlement_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.check_finance_settlement_authority(p_action, p_tenant_id, p_actor_auth_user_id);
$function$;

revoke execute on function public.check_finance_settlement_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.check_finance_settlement_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid) to service_role;

-- 25. public.check_finance_subledger_authority -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.check_finance_subledger_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid);

create function public.check_finance_subledger_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.check_finance_subledger_authority(p_action, p_tenant_id, p_actor_auth_user_id);
$function$;

revoke execute on function public.check_finance_subledger_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.check_finance_subledger_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid) to service_role;

-- 26. public.check_finance_tax_authority -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.check_finance_tax_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid);

create function public.check_finance_tax_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.check_finance_tax_authority(p_action, p_tenant_id, p_actor_auth_user_id);
$function$;

revoke execute on function public.check_finance_tax_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.check_finance_tax_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid) to service_role;

-- 27. public.check_finance_vendor_bill_authority -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.check_finance_vendor_bill_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid);

create function public.check_finance_vendor_bill_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.check_finance_vendor_bill_authority(p_action, p_tenant_id, p_actor_auth_user_id);
$function$;

revoke execute on function public.check_finance_vendor_bill_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.check_finance_vendor_bill_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid) to service_role;

-- 28. public.claim_finance_idempotency_key -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.claim_finance_idempotency_key(p_tenant_id uuid, p_scope text, p_idempotency_key text, p_request_fingerprint text, p_actor_auth_user_id uuid, p_actor_label text);

create function public.claim_finance_idempotency_key(p_tenant_id uuid, p_scope text, p_idempotency_key text, p_request_fingerprint text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_idempotency_claims
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.claim_finance_idempotency_key(p_tenant_id, p_scope, p_idempotency_key, p_request_fingerprint, p_actor_auth_user_id, p_actor_label);
$function$;

revoke execute on function public.claim_finance_idempotency_key(p_tenant_id uuid, p_scope text, p_idempotency_key text, p_request_fingerprint text, p_actor_auth_user_id uuid, p_actor_label text) from anon, authenticated, service_role, public;
grant execute on function public.claim_finance_idempotency_key(p_tenant_id uuid, p_scope text, p_idempotency_key text, p_request_fingerprint text, p_actor_auth_user_id uuid, p_actor_label text) to authenticated;
grant execute on function public.claim_finance_idempotency_key(p_tenant_id uuid, p_scope text, p_idempotency_key text, p_request_fingerprint text, p_actor_auth_user_id uuid, p_actor_label text) to service_role;

-- 29. public.complete_finance_idempotency_claim -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.complete_finance_idempotency_claim(p_claim_id uuid, p_result_entity_type text, p_result_entity_id uuid, p_actor_auth_user_id uuid, p_actor_label text);

create function public.complete_finance_idempotency_claim(p_claim_id uuid, p_result_entity_type text, p_result_entity_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_idempotency_claims
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.complete_finance_idempotency_claim(p_claim_id, p_result_entity_type, p_result_entity_id, p_actor_auth_user_id, p_actor_label);
$function$;

revoke execute on function public.complete_finance_idempotency_claim(p_claim_id uuid, p_result_entity_type text, p_result_entity_id uuid, p_actor_auth_user_id uuid, p_actor_label text) from anon, authenticated, service_role, public;
grant execute on function public.complete_finance_idempotency_claim(p_claim_id uuid, p_result_entity_type text, p_result_entity_id uuid, p_actor_auth_user_id uuid, p_actor_label text) to authenticated;
grant execute on function public.complete_finance_idempotency_claim(p_claim_id uuid, p_result_entity_type text, p_result_entity_id uuid, p_actor_auth_user_id uuid, p_actor_label text) to service_role;

-- 30. public.convert_finance_amount -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.convert_finance_amount(p_tenant_id uuid, p_amount numeric, p_source_currency text, p_target_currency text, p_rate_type text, p_as_of timestamp with time zone, p_actor_auth_user_id uuid);

create function public.convert_finance_amount(p_tenant_id uuid, p_amount numeric, p_source_currency text, p_target_currency text, p_rate_type text, p_as_of timestamp with time zone, p_actor_auth_user_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.convert_finance_amount(p_tenant_id, p_amount, p_source_currency, p_target_currency, p_rate_type, p_as_of, p_actor_auth_user_id);
$function$;

revoke execute on function public.convert_finance_amount(p_tenant_id uuid, p_amount numeric, p_source_currency text, p_target_currency text, p_rate_type text, p_as_of timestamp with time zone, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.convert_finance_amount(p_tenant_id uuid, p_amount numeric, p_source_currency text, p_target_currency text, p_rate_type text, p_as_of timestamp with time zone, p_actor_auth_user_id uuid) to authenticated;
grant execute on function public.convert_finance_amount(p_tenant_id uuid, p_amount numeric, p_source_currency text, p_target_currency text, p_rate_type text, p_as_of timestamp with time zone, p_actor_auth_user_id uuid) to service_role;

-- 31. public.create_finance_account_draft -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.create_finance_account_draft(p_tenant_id uuid, p_company_id uuid, p_code text, p_name text, p_account_type text, p_normal_balance text, p_parent_account_id uuid, p_is_control_account boolean, p_currency_restriction text, p_actor_auth_user_id uuid, p_created_by text);

create function public.create_finance_account_draft(p_tenant_id uuid, p_company_id uuid, p_code text, p_name text, p_account_type text, p_normal_balance text, p_parent_account_id uuid, p_is_control_account boolean, p_currency_restriction text, p_actor_auth_user_id uuid, p_created_by text)
 RETURNS app.finance_accounts
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.create_finance_account_draft(p_tenant_id, p_company_id, p_code, p_name, p_account_type, p_normal_balance, p_parent_account_id, p_is_control_account, p_currency_restriction, p_actor_auth_user_id, p_created_by);
$function$;

revoke execute on function public.create_finance_account_draft(p_tenant_id uuid, p_company_id uuid, p_code text, p_name text, p_account_type text, p_normal_balance text, p_parent_account_id uuid, p_is_control_account boolean, p_currency_restriction text, p_actor_auth_user_id uuid, p_created_by text) from anon, authenticated, service_role, public;
grant execute on function public.create_finance_account_draft(p_tenant_id uuid, p_company_id uuid, p_code text, p_name text, p_account_type text, p_normal_balance text, p_parent_account_id uuid, p_is_control_account boolean, p_currency_restriction text, p_actor_auth_user_id uuid, p_created_by text) to authenticated;
grant execute on function public.create_finance_account_draft(p_tenant_id uuid, p_company_id uuid, p_code text, p_name text, p_account_type text, p_normal_balance text, p_parent_account_id uuid, p_is_control_account boolean, p_currency_restriction text, p_actor_auth_user_id uuid, p_created_by text) to service_role;

-- 32. public.create_finance_config_draft -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.create_finance_config_draft(p_config_type_code text, p_tenant_id uuid, p_scope_level text, p_scope_id uuid, p_actor_auth_user_id uuid, p_created_by text);

create function public.create_finance_config_draft(p_config_type_code text, p_tenant_id uuid, p_scope_level text, p_scope_id uuid, p_actor_auth_user_id uuid, p_created_by text)
 RETURNS app.config_versions
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.create_finance_config_draft(p_config_type_code, p_tenant_id, p_scope_level, p_scope_id, p_actor_auth_user_id, p_created_by);
$function$;

revoke execute on function public.create_finance_config_draft(p_config_type_code text, p_tenant_id uuid, p_scope_level text, p_scope_id uuid, p_actor_auth_user_id uuid, p_created_by text) from anon, authenticated, service_role, public;
grant execute on function public.create_finance_config_draft(p_config_type_code text, p_tenant_id uuid, p_scope_level text, p_scope_id uuid, p_actor_auth_user_id uuid, p_created_by text) to authenticated;
grant execute on function public.create_finance_config_draft(p_config_type_code text, p_tenant_id uuid, p_scope_level text, p_scope_id uuid, p_actor_auth_user_id uuid, p_created_by text) to service_role;

-- 33. public.create_finance_exchange_rate_draft -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.create_finance_exchange_rate_draft(p_tenant_id uuid, p_rate_type text, p_source_currency text, p_target_currency text, p_rate numeric, p_source text, p_effective_from timestamp with time zone, p_effective_to timestamp with time zone, p_actor_auth_user_id uuid, p_created_by text);

create function public.create_finance_exchange_rate_draft(p_tenant_id uuid, p_rate_type text, p_source_currency text, p_target_currency text, p_rate numeric, p_source text, p_effective_from timestamp with time zone, p_effective_to timestamp with time zone, p_actor_auth_user_id uuid, p_created_by text)
 RETURNS app.finance_exchange_rates
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.create_finance_exchange_rate_draft(p_tenant_id, p_rate_type, p_source_currency, p_target_currency, p_rate, p_source, p_effective_from, p_effective_to, p_actor_auth_user_id, p_created_by);
$function$;

revoke execute on function public.create_finance_exchange_rate_draft(p_tenant_id uuid, p_rate_type text, p_source_currency text, p_target_currency text, p_rate numeric, p_source text, p_effective_from timestamp with time zone, p_effective_to timestamp with time zone, p_actor_auth_user_id uuid, p_created_by text) from anon, authenticated, service_role, public;
grant execute on function public.create_finance_exchange_rate_draft(p_tenant_id uuid, p_rate_type text, p_source_currency text, p_target_currency text, p_rate numeric, p_source text, p_effective_from timestamp with time zone, p_effective_to timestamp with time zone, p_actor_auth_user_id uuid, p_created_by text) to authenticated;
grant execute on function public.create_finance_exchange_rate_draft(p_tenant_id uuid, p_rate_type text, p_source_currency text, p_target_currency text, p_rate numeric, p_source text, p_effective_from timestamp with time zone, p_effective_to timestamp with time zone, p_actor_auth_user_id uuid, p_created_by text) to service_role;

-- 34. public.create_finance_journal_draft -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.create_finance_journal_draft(p_tenant_id uuid, p_company_id uuid, p_journal_date date, p_currency text, p_lines jsonb, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text);

create function public.create_finance_journal_draft(p_tenant_id uuid, p_company_id uuid, p_journal_date date, p_currency text, p_lines jsonb, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_journals
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.create_finance_journal_draft(p_tenant_id, p_company_id, p_journal_date, p_currency, p_lines, p_idempotency_key, p_actor_auth_user_id, p_actor_label);
$function$;

revoke execute on function public.create_finance_journal_draft(p_tenant_id uuid, p_company_id uuid, p_journal_date date, p_currency text, p_lines jsonb, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text) from anon, authenticated, service_role, public;
grant execute on function public.create_finance_journal_draft(p_tenant_id uuid, p_company_id uuid, p_journal_date date, p_currency text, p_lines jsonb, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text) to authenticated;
grant execute on function public.create_finance_journal_draft(p_tenant_id uuid, p_company_id uuid, p_journal_date date, p_currency text, p_lines jsonb, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text) to service_role;

-- 35. public.create_finance_tax_rule_draft -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.create_finance_tax_rule_draft(p_tenant_id uuid, p_tax_code_id uuid, p_rate_basis text, p_rate_value numeric, p_currency text, p_output_account_id uuid, p_recoverable_account_id uuid, p_effective_from date, p_effective_to date, p_actor_auth_user_id uuid, p_created_by text);

create function public.create_finance_tax_rule_draft(p_tenant_id uuid, p_tax_code_id uuid, p_rate_basis text, p_rate_value numeric, p_currency text, p_output_account_id uuid, p_recoverable_account_id uuid, p_effective_from date, p_effective_to date, p_actor_auth_user_id uuid, p_created_by text)
 RETURNS app.finance_tax_rule_versions
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.create_finance_tax_rule_draft(p_tenant_id, p_tax_code_id, p_rate_basis, p_rate_value, p_currency, p_output_account_id, p_recoverable_account_id, p_effective_from, p_effective_to, p_actor_auth_user_id, p_created_by);
$function$;

revoke execute on function public.create_finance_tax_rule_draft(p_tenant_id uuid, p_tax_code_id uuid, p_rate_basis text, p_rate_value numeric, p_currency text, p_output_account_id uuid, p_recoverable_account_id uuid, p_effective_from date, p_effective_to date, p_actor_auth_user_id uuid, p_created_by text) from anon, authenticated, service_role, public;
grant execute on function public.create_finance_tax_rule_draft(p_tenant_id uuid, p_tax_code_id uuid, p_rate_basis text, p_rate_value numeric, p_currency text, p_output_account_id uuid, p_recoverable_account_id uuid, p_effective_from date, p_effective_to date, p_actor_auth_user_id uuid, p_created_by text) to authenticated;
grant execute on function public.create_finance_tax_rule_draft(p_tenant_id uuid, p_tax_code_id uuid, p_rate_basis text, p_rate_value numeric, p_currency text, p_output_account_id uuid, p_recoverable_account_id uuid, p_effective_from date, p_effective_to date, p_actor_auth_user_id uuid, p_created_by text) to service_role;

-- 36. public.deactivate_finance_account -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.deactivate_finance_account(p_account_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text);

create function public.deactivate_finance_account(p_account_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_accounts
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.deactivate_finance_account(p_account_id, p_expected_version, p_reason, p_actor_auth_user_id, p_actor_label);
$function$;

revoke execute on function public.deactivate_finance_account(p_account_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text) from anon, authenticated, service_role, public;
grant execute on function public.deactivate_finance_account(p_account_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text) to authenticated;
grant execute on function public.deactivate_finance_account(p_account_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text) to service_role;

-- 37. public.discard_finance_config_draft -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.discard_finance_config_draft(p_version_id uuid, p_actor_auth_user_id uuid, p_reason text, p_actor_label text);

create function public.discard_finance_config_draft(p_version_id uuid, p_actor_auth_user_id uuid, p_reason text, p_actor_label text)
 RETURNS app.config_versions
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.discard_finance_config_draft(p_version_id, p_actor_auth_user_id, p_reason, p_actor_label);
$function$;

revoke execute on function public.discard_finance_config_draft(p_version_id uuid, p_actor_auth_user_id uuid, p_reason text, p_actor_label text) from anon, authenticated, service_role, public;
grant execute on function public.discard_finance_config_draft(p_version_id uuid, p_actor_auth_user_id uuid, p_reason text, p_actor_label text) to authenticated;
grant execute on function public.discard_finance_config_draft(p_version_id uuid, p_actor_auth_user_id uuid, p_reason text, p_actor_label text) to service_role;

-- 38. public.discard_finance_correction_draft -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.discard_finance_correction_draft(p_correction_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text);

create function public.discard_finance_correction_draft(p_correction_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_journal_corrections
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.discard_finance_correction_draft(p_correction_id, p_expected_version, p_reason, p_actor_auth_user_id, p_actor_label);
$function$;

revoke execute on function public.discard_finance_correction_draft(p_correction_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text) from anon, authenticated, service_role, public;
grant execute on function public.discard_finance_correction_draft(p_correction_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text) to authenticated;
grant execute on function public.discard_finance_correction_draft(p_correction_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text) to service_role;

-- 39. public.discard_finance_exchange_rate_draft -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.discard_finance_exchange_rate_draft(p_rate_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text);

create function public.discard_finance_exchange_rate_draft(p_rate_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_exchange_rates
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.discard_finance_exchange_rate_draft(p_rate_id, p_expected_version, p_reason, p_actor_auth_user_id, p_actor_label);
$function$;

revoke execute on function public.discard_finance_exchange_rate_draft(p_rate_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text) from anon, authenticated, service_role, public;
grant execute on function public.discard_finance_exchange_rate_draft(p_rate_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text) to authenticated;
grant execute on function public.discard_finance_exchange_rate_draft(p_rate_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text) to service_role;

-- 40. public.discard_finance_invoice_draft -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.discard_finance_invoice_draft(p_invoice_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text);

create function public.discard_finance_invoice_draft(p_invoice_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_invoices
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.discard_finance_invoice_draft(p_invoice_id, p_expected_version, p_reason, p_actor_auth_user_id, p_actor_label);
$function$;

revoke execute on function public.discard_finance_invoice_draft(p_invoice_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text) from anon, authenticated, service_role, public;
grant execute on function public.discard_finance_invoice_draft(p_invoice_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text) to authenticated;
grant execute on function public.discard_finance_invoice_draft(p_invoice_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text) to service_role;

-- 41. public.discard_finance_journal_draft -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.discard_finance_journal_draft(p_journal_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text);

create function public.discard_finance_journal_draft(p_journal_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_journals
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.discard_finance_journal_draft(p_journal_id, p_expected_version, p_reason, p_actor_auth_user_id, p_actor_label);
$function$;

revoke execute on function public.discard_finance_journal_draft(p_journal_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text) from anon, authenticated, service_role, public;
grant execute on function public.discard_finance_journal_draft(p_journal_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text) to authenticated;
grant execute on function public.discard_finance_journal_draft(p_journal_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text) to service_role;

-- 42. public.discard_finance_tax_rule_draft -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.discard_finance_tax_rule_draft(p_rule_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text);

create function public.discard_finance_tax_rule_draft(p_rule_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_tax_rule_versions
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.discard_finance_tax_rule_draft(p_rule_id, p_expected_version, p_reason, p_actor_auth_user_id, p_actor_label);
$function$;

revoke execute on function public.discard_finance_tax_rule_draft(p_rule_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text) from anon, authenticated, service_role, public;
grant execute on function public.discard_finance_tax_rule_draft(p_rule_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text) to authenticated;
grant execute on function public.discard_finance_tax_rule_draft(p_rule_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text) to service_role;

-- 43. public.discard_finance_vendor_bill_draft -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.discard_finance_vendor_bill_draft(p_bill_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text);

create function public.discard_finance_vendor_bill_draft(p_bill_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_vendor_bills
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.discard_finance_vendor_bill_draft(p_bill_id, p_expected_version, p_reason, p_actor_auth_user_id, p_actor_label);
$function$;

revoke execute on function public.discard_finance_vendor_bill_draft(p_bill_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text) from anon, authenticated, service_role, public;
grant execute on function public.discard_finance_vendor_bill_draft(p_bill_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text) to authenticated;
grant execute on function public.discard_finance_vendor_bill_draft(p_bill_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text) to service_role;

-- 44. public.enqueue_job -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.enqueue_job(p_tenant_id uuid, p_job_type text, p_payload jsonb, p_priority integer, p_idempotency_key text, p_max_attempts integer, p_actor_auth_user_id uuid, p_actor_label text);

create function public.enqueue_job(p_tenant_id uuid, p_job_type text, p_payload jsonb, p_priority integer, p_idempotency_key text, p_max_attempts integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.jobs
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.enqueue_job(p_tenant_id, p_job_type, p_payload, p_priority, p_idempotency_key, p_max_attempts, p_actor_auth_user_id, p_actor_label);
$function$;

revoke execute on function public.enqueue_job(p_tenant_id uuid, p_job_type text, p_payload jsonb, p_priority integer, p_idempotency_key text, p_max_attempts integer, p_actor_auth_user_id uuid, p_actor_label text) from anon, authenticated, service_role, public;
grant execute on function public.enqueue_job(p_tenant_id uuid, p_job_type text, p_payload jsonb, p_priority integer, p_idempotency_key text, p_max_attempts integer, p_actor_auth_user_id uuid, p_actor_label text) to authenticated;
grant execute on function public.enqueue_job(p_tenant_id uuid, p_job_type text, p_payload jsonb, p_priority integer, p_idempotency_key text, p_max_attempts integer, p_actor_auth_user_id uuid, p_actor_label text) to service_role;

-- 45. public.execute_finance_reconciliation_run -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.execute_finance_reconciliation_run(p_tenant_id uuid, p_company_id uuid, p_scope text, p_as_of_date date, p_tolerance_amount numeric, p_actor_auth_user_id uuid, p_actor_label text);

create function public.execute_finance_reconciliation_run(p_tenant_id uuid, p_company_id uuid, p_scope text, p_as_of_date date, p_tolerance_amount numeric, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_reconciliation_runs
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.execute_finance_reconciliation_run(p_tenant_id, p_company_id, p_scope, p_as_of_date, p_tolerance_amount, p_actor_auth_user_id, p_actor_label);
$function$;

revoke execute on function public.execute_finance_reconciliation_run(p_tenant_id uuid, p_company_id uuid, p_scope text, p_as_of_date date, p_tolerance_amount numeric, p_actor_auth_user_id uuid, p_actor_label text) from anon, authenticated, service_role, public;
grant execute on function public.execute_finance_reconciliation_run(p_tenant_id uuid, p_company_id uuid, p_scope text, p_as_of_date date, p_tolerance_amount numeric, p_actor_auth_user_id uuid, p_actor_label text) to authenticated;
grant execute on function public.execute_finance_reconciliation_run(p_tenant_id uuid, p_company_id uuid, p_scope text, p_as_of_date date, p_tolerance_amount numeric, p_actor_auth_user_id uuid, p_actor_label text) to service_role;

-- 46. public.fail_finance_idempotency_claim -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.fail_finance_idempotency_claim(p_claim_id uuid, p_error_message text, p_actor_auth_user_id uuid, p_actor_label text);

create function public.fail_finance_idempotency_claim(p_claim_id uuid, p_error_message text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_idempotency_claims
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.fail_finance_idempotency_claim(p_claim_id, p_error_message, p_actor_auth_user_id, p_actor_label);
$function$;

revoke execute on function public.fail_finance_idempotency_claim(p_claim_id uuid, p_error_message text, p_actor_auth_user_id uuid, p_actor_label text) from anon, authenticated, service_role, public;
grant execute on function public.fail_finance_idempotency_claim(p_claim_id uuid, p_error_message text, p_actor_auth_user_id uuid, p_actor_label text) to authenticated;
grant execute on function public.fail_finance_idempotency_claim(p_claim_id uuid, p_error_message text, p_actor_auth_user_id uuid, p_actor_label text) to service_role;

-- 47. public.generate_finance_fiscal_calendar -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.generate_finance_fiscal_calendar(p_tenant_id uuid, p_company_id uuid, p_code text, p_name text, p_start_date date, p_period_count integer, p_actor_auth_user_id uuid, p_created_by text);

create function public.generate_finance_fiscal_calendar(p_tenant_id uuid, p_company_id uuid, p_code text, p_name text, p_start_date date, p_period_count integer, p_actor_auth_user_id uuid, p_created_by text)
 RETURNS app.finance_fiscal_calendars
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.generate_finance_fiscal_calendar(p_tenant_id, p_company_id, p_code, p_name, p_start_date, p_period_count, p_actor_auth_user_id, p_created_by);
$function$;

revoke execute on function public.generate_finance_fiscal_calendar(p_tenant_id uuid, p_company_id uuid, p_code text, p_name text, p_start_date date, p_period_count integer, p_actor_auth_user_id uuid, p_created_by text) from anon, authenticated, service_role, public;
grant execute on function public.generate_finance_fiscal_calendar(p_tenant_id uuid, p_company_id uuid, p_code text, p_name text, p_start_date date, p_period_count integer, p_actor_auth_user_id uuid, p_created_by text) to authenticated;
grant execute on function public.generate_finance_fiscal_calendar(p_tenant_id uuid, p_company_id uuid, p_code text, p_name text, p_start_date date, p_period_count integer, p_actor_auth_user_id uuid, p_created_by text) to service_role;

-- 48. public.get_finance_account_dependency_impact -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.get_finance_account_dependency_impact(p_account_id uuid, p_actor_auth_user_id uuid);

create function public.get_finance_account_dependency_impact(p_account_id uuid, p_actor_auth_user_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.get_finance_account_dependency_impact(p_account_id, p_actor_auth_user_id);
$function$;

revoke execute on function public.get_finance_account_dependency_impact(p_account_id uuid, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_finance_account_dependency_impact(p_account_id uuid, p_actor_auth_user_id uuid) to authenticated;
grant execute on function public.get_finance_account_dependency_impact(p_account_id uuid, p_actor_auth_user_id uuid) to service_role;

-- 49. public.get_finance_aging_report -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.get_finance_aging_report(p_tenant_id uuid, p_company_id uuid, p_entity_type text, p_as_of_date date, p_include_held boolean, p_actor_auth_user_id uuid);

create function public.get_finance_aging_report(p_tenant_id uuid, p_company_id uuid, p_entity_type text, p_as_of_date date, p_include_held boolean, p_actor_auth_user_id uuid)
 RETURNS TABLE(open_item_id uuid, party_id uuid, currency text, original_amount numeric, open_amount numeric, document_date date, due_date date, days_overdue integer, bucket_label text, is_held boolean, source_document_type text, source_document_id uuid)
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select * from app.get_finance_aging_report(p_tenant_id, p_company_id, p_entity_type, p_as_of_date, p_include_held, p_actor_auth_user_id);
$function$;

revoke execute on function public.get_finance_aging_report(p_tenant_id uuid, p_company_id uuid, p_entity_type text, p_as_of_date date, p_include_held boolean, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_finance_aging_report(p_tenant_id uuid, p_company_id uuid, p_entity_type text, p_as_of_date date, p_include_held boolean, p_actor_auth_user_id uuid) to authenticated;
grant execute on function public.get_finance_aging_report(p_tenant_id uuid, p_company_id uuid, p_entity_type text, p_as_of_date date, p_include_held boolean, p_actor_auth_user_id uuid) to service_role;

-- 50. public.get_finance_ap_exposure_summary -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.get_finance_ap_exposure_summary(p_tenant_id uuid, p_vendor_master_id uuid, p_actor_auth_user_id uuid);

create function public.get_finance_ap_exposure_summary(p_tenant_id uuid, p_vendor_master_id uuid, p_actor_auth_user_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.get_finance_ap_exposure_summary(p_tenant_id, p_vendor_master_id, p_actor_auth_user_id);
$function$;

revoke execute on function public.get_finance_ap_exposure_summary(p_tenant_id uuid, p_vendor_master_id uuid, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_finance_ap_exposure_summary(p_tenant_id uuid, p_vendor_master_id uuid, p_actor_auth_user_id uuid) to authenticated;
grant execute on function public.get_finance_ap_exposure_summary(p_tenant_id uuid, p_vendor_master_id uuid, p_actor_auth_user_id uuid) to service_role;

-- 51. public.get_finance_ap_open_item_activity -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.get_finance_ap_open_item_activity(p_open_item_id uuid, p_actor_auth_user_id uuid);

create function public.get_finance_ap_open_item_activity(p_open_item_id uuid, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_ap_open_item_events
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select * from app.get_finance_ap_open_item_activity(p_open_item_id, p_actor_auth_user_id);
$function$;

revoke execute on function public.get_finance_ap_open_item_activity(p_open_item_id uuid, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_finance_ap_open_item_activity(p_open_item_id uuid, p_actor_auth_user_id uuid) to authenticated;
grant execute on function public.get_finance_ap_open_item_activity(p_open_item_id uuid, p_actor_auth_user_id uuid) to service_role;

-- 52. public.get_finance_ar_exposure_summary -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.get_finance_ar_exposure_summary(p_tenant_id uuid, p_customer_account_id uuid, p_actor_auth_user_id uuid);

create function public.get_finance_ar_exposure_summary(p_tenant_id uuid, p_customer_account_id uuid, p_actor_auth_user_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.get_finance_ar_exposure_summary(p_tenant_id, p_customer_account_id, p_actor_auth_user_id);
$function$;

revoke execute on function public.get_finance_ar_exposure_summary(p_tenant_id uuid, p_customer_account_id uuid, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_finance_ar_exposure_summary(p_tenant_id uuid, p_customer_account_id uuid, p_actor_auth_user_id uuid) to authenticated;
grant execute on function public.get_finance_ar_exposure_summary(p_tenant_id uuid, p_customer_account_id uuid, p_actor_auth_user_id uuid) to service_role;

-- 53. public.get_finance_ar_open_item_activity -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.get_finance_ar_open_item_activity(p_open_item_id uuid, p_actor_auth_user_id uuid);

create function public.get_finance_ar_open_item_activity(p_open_item_id uuid, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_ar_open_item_events
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select * from app.get_finance_ar_open_item_activity(p_open_item_id, p_actor_auth_user_id);
$function$;

revoke execute on function public.get_finance_ar_open_item_activity(p_open_item_id uuid, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_finance_ar_open_item_activity(p_open_item_id uuid, p_actor_auth_user_id uuid) to authenticated;
grant execute on function public.get_finance_ar_open_item_activity(p_open_item_id uuid, p_actor_auth_user_id uuid) to service_role;

-- 54. public.get_finance_cash_position -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.get_finance_cash_position(p_tenant_id uuid, p_bank_account_id uuid, p_as_of_date date, p_actor_auth_user_id uuid);

create function public.get_finance_cash_position(p_tenant_id uuid, p_bank_account_id uuid, p_as_of_date date, p_actor_auth_user_id uuid)
 RETURNS TABLE(bank_account_id uuid, currency text, statement_balance numeric, gl_balance numeric, variance_amount numeric)
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select * from app.get_finance_cash_position(p_tenant_id, p_bank_account_id, p_as_of_date, p_actor_auth_user_id);
$function$;

revoke execute on function public.get_finance_cash_position(p_tenant_id uuid, p_bank_account_id uuid, p_as_of_date date, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_finance_cash_position(p_tenant_id uuid, p_bank_account_id uuid, p_as_of_date date, p_actor_auth_user_id uuid) to authenticated;
grant execute on function public.get_finance_cash_position(p_tenant_id uuid, p_bank_account_id uuid, p_as_of_date date, p_actor_auth_user_id uuid) to service_role;

-- 55. public.get_finance_config_version_items -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.get_finance_config_version_items(p_version_id uuid, p_actor_auth_user_id uuid);

create function public.get_finance_config_version_items(p_version_id uuid, p_actor_auth_user_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.get_finance_config_version_items(p_version_id, p_actor_auth_user_id);
$function$;

revoke execute on function public.get_finance_config_version_items(p_version_id uuid, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_finance_config_version_items(p_version_id uuid, p_actor_auth_user_id uuid) to authenticated;
grant execute on function public.get_finance_config_version_items(p_version_id uuid, p_actor_auth_user_id uuid) to service_role;

-- 56. public.get_finance_correction_chain -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.get_finance_correction_chain(p_correction_id uuid, p_actor_auth_user_id uuid);

create function public.get_finance_correction_chain(p_correction_id uuid, p_actor_auth_user_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.get_finance_correction_chain(p_correction_id, p_actor_auth_user_id);
$function$;

revoke execute on function public.get_finance_correction_chain(p_correction_id uuid, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_finance_correction_chain(p_correction_id uuid, p_actor_auth_user_id uuid) to authenticated;
grant execute on function public.get_finance_correction_chain(p_correction_id uuid, p_actor_auth_user_id uuid) to service_role;

-- 57. public.get_finance_dashboard_billing_summary -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.get_finance_dashboard_billing_summary(p_tenant_id uuid, p_company_id uuid, p_actor_auth_user_id uuid);

create function public.get_finance_dashboard_billing_summary(p_tenant_id uuid, p_company_id uuid, p_actor_auth_user_id uuid)
 RETURNS TABLE(status text, currency text, invoice_count bigint, total_amount numeric, open_amount numeric)
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select * from app.get_finance_dashboard_billing_summary(p_tenant_id, p_company_id, p_actor_auth_user_id);
$function$;

revoke execute on function public.get_finance_dashboard_billing_summary(p_tenant_id uuid, p_company_id uuid, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_finance_dashboard_billing_summary(p_tenant_id uuid, p_company_id uuid, p_actor_auth_user_id uuid) to authenticated;
grant execute on function public.get_finance_dashboard_billing_summary(p_tenant_id uuid, p_company_id uuid, p_actor_auth_user_id uuid) to service_role;

-- 58. public.get_finance_dashboard_cash_summary -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.get_finance_dashboard_cash_summary(p_tenant_id uuid, p_company_id uuid, p_as_of_date date, p_actor_auth_user_id uuid);

create function public.get_finance_dashboard_cash_summary(p_tenant_id uuid, p_company_id uuid, p_as_of_date date, p_actor_auth_user_id uuid)
 RETURNS TABLE(bank_account_id uuid, account_name text, currency text, statement_balance numeric, gl_balance numeric, variance_amount numeric)
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select * from app.get_finance_dashboard_cash_summary(p_tenant_id, p_company_id, p_as_of_date, p_actor_auth_user_id);
$function$;

revoke execute on function public.get_finance_dashboard_cash_summary(p_tenant_id uuid, p_company_id uuid, p_as_of_date date, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_finance_dashboard_cash_summary(p_tenant_id uuid, p_company_id uuid, p_as_of_date date, p_actor_auth_user_id uuid) to authenticated;
grant execute on function public.get_finance_dashboard_cash_summary(p_tenant_id uuid, p_company_id uuid, p_as_of_date date, p_actor_auth_user_id uuid) to service_role;

-- 59. public.get_finance_dashboard_close_status -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.get_finance_dashboard_close_status(p_tenant_id uuid, p_company_id uuid, p_actor_auth_user_id uuid);

create function public.get_finance_dashboard_close_status(p_tenant_id uuid, p_company_id uuid, p_actor_auth_user_id uuid)
 RETURNS TABLE(period_id uuid, period_code text, period_name text, end_date date, period_status text, lock_status text, reconciliation_status text, reconciliation_within_tolerance boolean)
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select * from app.get_finance_dashboard_close_status(p_tenant_id, p_company_id, p_actor_auth_user_id);
$function$;

revoke execute on function public.get_finance_dashboard_close_status(p_tenant_id uuid, p_company_id uuid, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_finance_dashboard_close_status(p_tenant_id uuid, p_company_id uuid, p_actor_auth_user_id uuid) to authenticated;
grant execute on function public.get_finance_dashboard_close_status(p_tenant_id uuid, p_company_id uuid, p_actor_auth_user_id uuid) to service_role;

-- 60. public.get_finance_idempotency_claim -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.get_finance_idempotency_claim(p_tenant_id uuid, p_scope text, p_idempotency_key text, p_actor_auth_user_id uuid);

create function public.get_finance_idempotency_claim(p_tenant_id uuid, p_scope text, p_idempotency_key text, p_actor_auth_user_id uuid)
 RETURNS app.finance_idempotency_claims
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.get_finance_idempotency_claim(p_tenant_id, p_scope, p_idempotency_key, p_actor_auth_user_id);
$function$;

revoke execute on function public.get_finance_idempotency_claim(p_tenant_id uuid, p_scope text, p_idempotency_key text, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_finance_idempotency_claim(p_tenant_id uuid, p_scope text, p_idempotency_key text, p_actor_auth_user_id uuid) to authenticated;
grant execute on function public.get_finance_idempotency_claim(p_tenant_id uuid, p_scope text, p_idempotency_key text, p_actor_auth_user_id uuid) to service_role;

-- 61. public.get_finance_invoice_lines -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.get_finance_invoice_lines(p_invoice_id uuid, p_actor_auth_user_id uuid);

create function public.get_finance_invoice_lines(p_invoice_id uuid, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_invoice_lines
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select * from app.get_finance_invoice_lines(p_invoice_id, p_actor_auth_user_id);
$function$;

revoke execute on function public.get_finance_invoice_lines(p_invoice_id uuid, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_finance_invoice_lines(p_invoice_id uuid, p_actor_auth_user_id uuid) to authenticated;
grant execute on function public.get_finance_invoice_lines(p_invoice_id uuid, p_actor_auth_user_id uuid) to service_role;

-- 62. public.get_finance_lifecycle_record_state -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.get_finance_lifecycle_record_state(p_tenant_id uuid, p_entity_type text, p_record_id uuid, p_actor_auth_user_id uuid);

create function public.get_finance_lifecycle_record_state(p_tenant_id uuid, p_entity_type text, p_record_id uuid, p_actor_auth_user_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.get_finance_lifecycle_record_state(p_tenant_id, p_entity_type, p_record_id, p_actor_auth_user_id);
$function$;

revoke execute on function public.get_finance_lifecycle_record_state(p_tenant_id uuid, p_entity_type text, p_record_id uuid, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_finance_lifecycle_record_state(p_tenant_id uuid, p_entity_type text, p_record_id uuid, p_actor_auth_user_id uuid) to authenticated;
grant execute on function public.get_finance_lifecycle_record_state(p_tenant_id uuid, p_entity_type text, p_record_id uuid, p_actor_auth_user_id uuid) to service_role;

-- 63. public.get_finance_period_close_readiness -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.get_finance_period_close_readiness(p_period_id uuid, p_actor_auth_user_id uuid);

create function public.get_finance_period_close_readiness(p_period_id uuid, p_actor_auth_user_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.get_finance_period_close_readiness(p_period_id, p_actor_auth_user_id);
$function$;

revoke execute on function public.get_finance_period_close_readiness(p_period_id uuid, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_finance_period_close_readiness(p_period_id uuid, p_actor_auth_user_id uuid) to authenticated;
grant execute on function public.get_finance_period_close_readiness(p_period_id uuid, p_actor_auth_user_id uuid) to service_role;

-- 64. public.get_finance_period_lock_events -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.get_finance_period_lock_events(p_lock_id uuid, p_actor_auth_user_id uuid);

create function public.get_finance_period_lock_events(p_lock_id uuid, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_period_lock_events
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select * from app.get_finance_period_lock_events(p_lock_id, p_actor_auth_user_id);
$function$;

revoke execute on function public.get_finance_period_lock_events(p_lock_id uuid, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_finance_period_lock_events(p_lock_id uuid, p_actor_auth_user_id uuid) to authenticated;
grant execute on function public.get_finance_period_lock_events(p_lock_id uuid, p_actor_auth_user_id uuid) to service_role;

-- 65. public.get_finance_period_transition_history -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.get_finance_period_transition_history(p_period_id uuid, p_actor_auth_user_id uuid);

create function public.get_finance_period_transition_history(p_period_id uuid, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_period_transitions
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select * from app.get_finance_period_transition_history(p_period_id, p_actor_auth_user_id);
$function$;

revoke execute on function public.get_finance_period_transition_history(p_period_id uuid, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_finance_period_transition_history(p_period_id uuid, p_actor_auth_user_id uuid) to authenticated;
grant execute on function public.get_finance_period_transition_history(p_period_id uuid, p_actor_auth_user_id uuid) to service_role;

-- 66. public.get_finance_receipt_allocations -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.get_finance_receipt_allocations(p_receipt_id uuid, p_actor_auth_user_id uuid);

create function public.get_finance_receipt_allocations(p_receipt_id uuid, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_receipt_allocations
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select * from app.get_finance_receipt_allocations(p_receipt_id, p_actor_auth_user_id);
$function$;

revoke execute on function public.get_finance_receipt_allocations(p_receipt_id uuid, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_finance_receipt_allocations(p_receipt_id uuid, p_actor_auth_user_id uuid) to authenticated;
grant execute on function public.get_finance_receipt_allocations(p_receipt_id uuid, p_actor_auth_user_id uuid) to service_role;

-- 67. public.get_finance_settlement_allocations -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.get_finance_settlement_allocations(p_settlement_id uuid, p_actor_auth_user_id uuid);

create function public.get_finance_settlement_allocations(p_settlement_id uuid, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_settlement_allocations
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select * from app.get_finance_settlement_allocations(p_settlement_id, p_actor_auth_user_id);
$function$;

revoke execute on function public.get_finance_settlement_allocations(p_settlement_id uuid, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_finance_settlement_allocations(p_settlement_id uuid, p_actor_auth_user_id uuid) to authenticated;
grant execute on function public.get_finance_settlement_allocations(p_settlement_id uuid, p_actor_auth_user_id uuid) to service_role;

-- 68. public.get_finance_subledger_lines -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.get_finance_subledger_lines(p_batch_id uuid, p_actor_auth_user_id uuid);

create function public.get_finance_subledger_lines(p_batch_id uuid, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_subledger_lines
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select * from app.get_finance_subledger_lines(p_batch_id, p_actor_auth_user_id);
$function$;

revoke execute on function public.get_finance_subledger_lines(p_batch_id uuid, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_finance_subledger_lines(p_batch_id uuid, p_actor_auth_user_id uuid) to authenticated;
grant execute on function public.get_finance_subledger_lines(p_batch_id uuid, p_actor_auth_user_id uuid) to service_role;

-- 69. public.get_finance_subledger_reconciliation_summary -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.get_finance_subledger_reconciliation_summary(p_tenant_id uuid, p_actor_auth_user_id uuid);

create function public.get_finance_subledger_reconciliation_summary(p_tenant_id uuid, p_actor_auth_user_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.get_finance_subledger_reconciliation_summary(p_tenant_id, p_actor_auth_user_id);
$function$;

revoke execute on function public.get_finance_subledger_reconciliation_summary(p_tenant_id uuid, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_finance_subledger_reconciliation_summary(p_tenant_id uuid, p_actor_auth_user_id uuid) to authenticated;
grant execute on function public.get_finance_subledger_reconciliation_summary(p_tenant_id uuid, p_actor_auth_user_id uuid) to service_role;

-- 70. public.get_finance_vendor_bill_lines -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.get_finance_vendor_bill_lines(p_bill_id uuid, p_actor_auth_user_id uuid);

create function public.get_finance_vendor_bill_lines(p_bill_id uuid, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_vendor_bill_lines
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select * from app.get_finance_vendor_bill_lines(p_bill_id, p_actor_auth_user_id);
$function$;

revoke execute on function public.get_finance_vendor_bill_lines(p_bill_id uuid, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_finance_vendor_bill_lines(p_bill_id uuid, p_actor_auth_user_id uuid) to authenticated;
grant execute on function public.get_finance_vendor_bill_lines(p_bill_id uuid, p_actor_auth_user_id uuid) to service_role;

-- 71. public.get_numbering_allocation_status -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.get_numbering_allocation_status(p_allocation_id uuid, p_actor_auth_user_id uuid);

create function public.get_numbering_allocation_status(p_allocation_id uuid, p_actor_auth_user_id uuid)
 RETURNS app.numbering_allocations
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.get_numbering_allocation_status(p_allocation_id, p_actor_auth_user_id);
$function$;

revoke execute on function public.get_numbering_allocation_status(p_allocation_id uuid, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_numbering_allocation_status(p_allocation_id uuid, p_actor_auth_user_id uuid) to authenticated;
grant execute on function public.get_numbering_allocation_status(p_allocation_id uuid, p_actor_auth_user_id uuid) to service_role;

-- 72. public.list_finance_accounts -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.list_finance_accounts(p_tenant_id uuid, p_company_id uuid, p_status text, p_actor_auth_user_id uuid);

create function public.list_finance_accounts(p_tenant_id uuid, p_company_id uuid, p_status text, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_accounts
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select * from app.list_finance_accounts(p_tenant_id, p_company_id, p_status, p_actor_auth_user_id);
$function$;

revoke execute on function public.list_finance_accounts(p_tenant_id uuid, p_company_id uuid, p_status text, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_finance_accounts(p_tenant_id uuid, p_company_id uuid, p_status text, p_actor_auth_user_id uuid) to authenticated;
grant execute on function public.list_finance_accounts(p_tenant_id uuid, p_company_id uuid, p_status text, p_actor_auth_user_id uuid) to service_role;

-- 73. public.list_finance_aging_bucket_configs -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.list_finance_aging_bucket_configs(p_tenant_id uuid, p_entity_type text, p_actor_auth_user_id uuid);

create function public.list_finance_aging_bucket_configs(p_tenant_id uuid, p_entity_type text, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_aging_bucket_configs
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select * from app.list_finance_aging_bucket_configs(p_tenant_id, p_entity_type, p_actor_auth_user_id);
$function$;

revoke execute on function public.list_finance_aging_bucket_configs(p_tenant_id uuid, p_entity_type text, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_finance_aging_bucket_configs(p_tenant_id uuid, p_entity_type text, p_actor_auth_user_id uuid) to authenticated;
grant execute on function public.list_finance_aging_bucket_configs(p_tenant_id uuid, p_entity_type text, p_actor_auth_user_id uuid) to service_role;

-- 74. public.list_finance_ap_open_items -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.list_finance_ap_open_items(p_tenant_id uuid, p_company_id uuid, p_vendor_master_id uuid, p_status text, p_overdue_only boolean, p_actor_auth_user_id uuid);

create function public.list_finance_ap_open_items(p_tenant_id uuid, p_company_id uuid, p_vendor_master_id uuid, p_status text, p_overdue_only boolean, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_ap_open_items
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select * from app.list_finance_ap_open_items(p_tenant_id, p_company_id, p_vendor_master_id, p_status, p_overdue_only, p_actor_auth_user_id);
$function$;

revoke execute on function public.list_finance_ap_open_items(p_tenant_id uuid, p_company_id uuid, p_vendor_master_id uuid, p_status text, p_overdue_only boolean, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_finance_ap_open_items(p_tenant_id uuid, p_company_id uuid, p_vendor_master_id uuid, p_status text, p_overdue_only boolean, p_actor_auth_user_id uuid) to authenticated;
grant execute on function public.list_finance_ap_open_items(p_tenant_id uuid, p_company_id uuid, p_vendor_master_id uuid, p_status text, p_overdue_only boolean, p_actor_auth_user_id uuid) to service_role;

-- 75. public.list_finance_ar_open_items -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.list_finance_ar_open_items(p_tenant_id uuid, p_company_id uuid, p_customer_account_id uuid, p_status text, p_overdue_only boolean, p_actor_auth_user_id uuid);

create function public.list_finance_ar_open_items(p_tenant_id uuid, p_company_id uuid, p_customer_account_id uuid, p_status text, p_overdue_only boolean, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_ar_open_items
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select * from app.list_finance_ar_open_items(p_tenant_id, p_company_id, p_customer_account_id, p_status, p_overdue_only, p_actor_auth_user_id);
$function$;

revoke execute on function public.list_finance_ar_open_items(p_tenant_id uuid, p_company_id uuid, p_customer_account_id uuid, p_status text, p_overdue_only boolean, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_finance_ar_open_items(p_tenant_id uuid, p_company_id uuid, p_customer_account_id uuid, p_status text, p_overdue_only boolean, p_actor_auth_user_id uuid) to authenticated;
grant execute on function public.list_finance_ar_open_items(p_tenant_id uuid, p_company_id uuid, p_customer_account_id uuid, p_status text, p_overdue_only boolean, p_actor_auth_user_id uuid) to service_role;

-- 76. public.list_finance_bank_accounts -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.list_finance_bank_accounts(p_tenant_id uuid, p_company_id uuid, p_actor_auth_user_id uuid);

create function public.list_finance_bank_accounts(p_tenant_id uuid, p_company_id uuid, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_bank_accounts
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select * from app.list_finance_bank_accounts(p_tenant_id, p_company_id, p_actor_auth_user_id);
$function$;

revoke execute on function public.list_finance_bank_accounts(p_tenant_id uuid, p_company_id uuid, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_finance_bank_accounts(p_tenant_id uuid, p_company_id uuid, p_actor_auth_user_id uuid) to authenticated;
grant execute on function public.list_finance_bank_accounts(p_tenant_id uuid, p_company_id uuid, p_actor_auth_user_id uuid) to service_role;

-- 77. public.list_finance_bank_transactions -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.list_finance_bank_transactions(p_tenant_id uuid, p_bank_account_id uuid, p_match_status text, p_actor_auth_user_id uuid);

create function public.list_finance_bank_transactions(p_tenant_id uuid, p_bank_account_id uuid, p_match_status text, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_bank_transactions
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select * from app.list_finance_bank_transactions(p_tenant_id, p_bank_account_id, p_match_status, p_actor_auth_user_id);
$function$;

revoke execute on function public.list_finance_bank_transactions(p_tenant_id uuid, p_bank_account_id uuid, p_match_status text, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_finance_bank_transactions(p_tenant_id uuid, p_bank_account_id uuid, p_match_status text, p_actor_auth_user_id uuid) to authenticated;
grant execute on function public.list_finance_bank_transactions(p_tenant_id uuid, p_bank_account_id uuid, p_match_status text, p_actor_auth_user_id uuid) to service_role;

-- 78. public.list_finance_exchange_rates -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.list_finance_exchange_rates(p_tenant_id uuid, p_rate_type text, p_source_currency text, p_target_currency text, p_actor_auth_user_id uuid);

create function public.list_finance_exchange_rates(p_tenant_id uuid, p_rate_type text, p_source_currency text, p_target_currency text, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_exchange_rates
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select * from app.list_finance_exchange_rates(p_tenant_id, p_rate_type, p_source_currency, p_target_currency, p_actor_auth_user_id);
$function$;

revoke execute on function public.list_finance_exchange_rates(p_tenant_id uuid, p_rate_type text, p_source_currency text, p_target_currency text, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_finance_exchange_rates(p_tenant_id uuid, p_rate_type text, p_source_currency text, p_target_currency text, p_actor_auth_user_id uuid) to authenticated;
grant execute on function public.list_finance_exchange_rates(p_tenant_id uuid, p_rate_type text, p_source_currency text, p_target_currency text, p_actor_auth_user_id uuid) to service_role;

-- 79. public.list_finance_fiscal_periods -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.list_finance_fiscal_periods(p_tenant_id uuid, p_company_id uuid, p_calendar_id uuid, p_actor_auth_user_id uuid);

create function public.list_finance_fiscal_periods(p_tenant_id uuid, p_company_id uuid, p_calendar_id uuid, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_fiscal_periods
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select * from app.list_finance_fiscal_periods(p_tenant_id, p_company_id, p_calendar_id, p_actor_auth_user_id);
$function$;

revoke execute on function public.list_finance_fiscal_periods(p_tenant_id uuid, p_company_id uuid, p_calendar_id uuid, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_finance_fiscal_periods(p_tenant_id uuid, p_company_id uuid, p_calendar_id uuid, p_actor_auth_user_id uuid) to authenticated;
grant execute on function public.list_finance_fiscal_periods(p_tenant_id uuid, p_company_id uuid, p_calendar_id uuid, p_actor_auth_user_id uuid) to service_role;

-- 80. public.list_finance_invoices -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.list_finance_invoices(p_tenant_id uuid, p_company_id uuid, p_customer_account_id uuid, p_status text, p_actor_auth_user_id uuid);

create function public.list_finance_invoices(p_tenant_id uuid, p_company_id uuid, p_customer_account_id uuid, p_status text, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_invoices
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select * from app.list_finance_invoices(p_tenant_id, p_company_id, p_customer_account_id, p_status, p_actor_auth_user_id);
$function$;

revoke execute on function public.list_finance_invoices(p_tenant_id uuid, p_company_id uuid, p_customer_account_id uuid, p_status text, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_finance_invoices(p_tenant_id uuid, p_company_id uuid, p_customer_account_id uuid, p_status text, p_actor_auth_user_id uuid) to authenticated;
grant execute on function public.list_finance_invoices(p_tenant_id uuid, p_company_id uuid, p_customer_account_id uuid, p_status text, p_actor_auth_user_id uuid) to service_role;

-- 81. public.list_finance_journal_corrections -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.list_finance_journal_corrections(p_tenant_id uuid, p_company_id uuid, p_correction_type text, p_status text, p_actor_auth_user_id uuid);

create function public.list_finance_journal_corrections(p_tenant_id uuid, p_company_id uuid, p_correction_type text, p_status text, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_journal_corrections
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select * from app.list_finance_journal_corrections(p_tenant_id, p_company_id, p_correction_type, p_status, p_actor_auth_user_id);
$function$;

revoke execute on function public.list_finance_journal_corrections(p_tenant_id uuid, p_company_id uuid, p_correction_type text, p_status text, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_finance_journal_corrections(p_tenant_id uuid, p_company_id uuid, p_correction_type text, p_status text, p_actor_auth_user_id uuid) to authenticated;
grant execute on function public.list_finance_journal_corrections(p_tenant_id uuid, p_company_id uuid, p_correction_type text, p_status text, p_actor_auth_user_id uuid) to service_role;

-- 82. public.list_finance_period_locks -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.list_finance_period_locks(p_tenant_id uuid, p_company_id uuid, p_period_id uuid, p_actor_auth_user_id uuid);

create function public.list_finance_period_locks(p_tenant_id uuid, p_company_id uuid, p_period_id uuid, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_period_locks
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select * from app.list_finance_period_locks(p_tenant_id, p_company_id, p_period_id, p_actor_auth_user_id);
$function$;

revoke execute on function public.list_finance_period_locks(p_tenant_id uuid, p_company_id uuid, p_period_id uuid, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_finance_period_locks(p_tenant_id uuid, p_company_id uuid, p_period_id uuid, p_actor_auth_user_id uuid) to authenticated;
grant execute on function public.list_finance_period_locks(p_tenant_id uuid, p_company_id uuid, p_period_id uuid, p_actor_auth_user_id uuid) to service_role;

-- 83. public.list_finance_receipts -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.list_finance_receipts(p_tenant_id uuid, p_company_id uuid, p_customer_account_id uuid, p_status text, p_actor_auth_user_id uuid);

create function public.list_finance_receipts(p_tenant_id uuid, p_company_id uuid, p_customer_account_id uuid, p_status text, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_receipts
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select * from app.list_finance_receipts(p_tenant_id, p_company_id, p_customer_account_id, p_status, p_actor_auth_user_id);
$function$;

revoke execute on function public.list_finance_receipts(p_tenant_id uuid, p_company_id uuid, p_customer_account_id uuid, p_status text, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_finance_receipts(p_tenant_id uuid, p_company_id uuid, p_customer_account_id uuid, p_status text, p_actor_auth_user_id uuid) to authenticated;
grant execute on function public.list_finance_receipts(p_tenant_id uuid, p_company_id uuid, p_customer_account_id uuid, p_status text, p_actor_auth_user_id uuid) to service_role;

-- 84. public.list_finance_reconciliation_exceptions -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.list_finance_reconciliation_exceptions(p_run_id uuid, p_actor_auth_user_id uuid);

create function public.list_finance_reconciliation_exceptions(p_run_id uuid, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_reconciliation_exceptions
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select * from app.list_finance_reconciliation_exceptions(p_run_id, p_actor_auth_user_id);
$function$;

revoke execute on function public.list_finance_reconciliation_exceptions(p_run_id uuid, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_finance_reconciliation_exceptions(p_run_id uuid, p_actor_auth_user_id uuid) to authenticated;
grant execute on function public.list_finance_reconciliation_exceptions(p_run_id uuid, p_actor_auth_user_id uuid) to service_role;

-- 85. public.list_finance_reconciliation_runs -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.list_finance_reconciliation_runs(p_tenant_id uuid, p_company_id uuid, p_scope text, p_actor_auth_user_id uuid);

create function public.list_finance_reconciliation_runs(p_tenant_id uuid, p_company_id uuid, p_scope text, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_reconciliation_runs
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select * from app.list_finance_reconciliation_runs(p_tenant_id, p_company_id, p_scope, p_actor_auth_user_id);
$function$;

revoke execute on function public.list_finance_reconciliation_runs(p_tenant_id uuid, p_company_id uuid, p_scope text, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_finance_reconciliation_runs(p_tenant_id uuid, p_company_id uuid, p_scope text, p_actor_auth_user_id uuid) to authenticated;
grant execute on function public.list_finance_reconciliation_runs(p_tenant_id uuid, p_company_id uuid, p_scope text, p_actor_auth_user_id uuid) to service_role;

-- 86. public.list_finance_settlements -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.list_finance_settlements(p_tenant_id uuid, p_company_id uuid, p_vendor_master_id uuid, p_status text, p_actor_auth_user_id uuid);

create function public.list_finance_settlements(p_tenant_id uuid, p_company_id uuid, p_vendor_master_id uuid, p_status text, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_settlements
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select * from app.list_finance_settlements(p_tenant_id, p_company_id, p_vendor_master_id, p_status, p_actor_auth_user_id);
$function$;

revoke execute on function public.list_finance_settlements(p_tenant_id uuid, p_company_id uuid, p_vendor_master_id uuid, p_status text, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_finance_settlements(p_tenant_id uuid, p_company_id uuid, p_vendor_master_id uuid, p_status text, p_actor_auth_user_id uuid) to authenticated;
grant execute on function public.list_finance_settlements(p_tenant_id uuid, p_company_id uuid, p_vendor_master_id uuid, p_status text, p_actor_auth_user_id uuid) to service_role;

-- 87. public.list_finance_subledger_batches -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.list_finance_subledger_batches(p_tenant_id uuid, p_company_id uuid, p_source_type text, p_actor_auth_user_id uuid);

create function public.list_finance_subledger_batches(p_tenant_id uuid, p_company_id uuid, p_source_type text, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_subledger_batches
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select * from app.list_finance_subledger_batches(p_tenant_id, p_company_id, p_source_type, p_actor_auth_user_id);
$function$;

revoke execute on function public.list_finance_subledger_batches(p_tenant_id uuid, p_company_id uuid, p_source_type text, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_finance_subledger_batches(p_tenant_id uuid, p_company_id uuid, p_source_type text, p_actor_auth_user_id uuid) to authenticated;
grant execute on function public.list_finance_subledger_batches(p_tenant_id uuid, p_company_id uuid, p_source_type text, p_actor_auth_user_id uuid) to service_role;

-- 88. public.list_finance_tax_codes -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.list_finance_tax_codes(p_tenant_id uuid, p_actor_auth_user_id uuid);

create function public.list_finance_tax_codes(p_tenant_id uuid, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_tax_codes
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select * from app.list_finance_tax_codes(p_tenant_id, p_actor_auth_user_id);
$function$;

revoke execute on function public.list_finance_tax_codes(p_tenant_id uuid, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_finance_tax_codes(p_tenant_id uuid, p_actor_auth_user_id uuid) to authenticated;
grant execute on function public.list_finance_tax_codes(p_tenant_id uuid, p_actor_auth_user_id uuid) to service_role;

-- 89. public.list_finance_tax_rule_versions -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.list_finance_tax_rule_versions(p_tenant_id uuid, p_tax_code_id uuid, p_actor_auth_user_id uuid);

create function public.list_finance_tax_rule_versions(p_tenant_id uuid, p_tax_code_id uuid, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_tax_rule_versions
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select * from app.list_finance_tax_rule_versions(p_tenant_id, p_tax_code_id, p_actor_auth_user_id);
$function$;

revoke execute on function public.list_finance_tax_rule_versions(p_tenant_id uuid, p_tax_code_id uuid, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_finance_tax_rule_versions(p_tenant_id uuid, p_tax_code_id uuid, p_actor_auth_user_id uuid) to authenticated;
grant execute on function public.list_finance_tax_rule_versions(p_tenant_id uuid, p_tax_code_id uuid, p_actor_auth_user_id uuid) to service_role;

-- 90. public.list_finance_vendor_bills -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.list_finance_vendor_bills(p_tenant_id uuid, p_company_id uuid, p_vendor_master_id uuid, p_status text, p_actor_auth_user_id uuid);

create function public.list_finance_vendor_bills(p_tenant_id uuid, p_company_id uuid, p_vendor_master_id uuid, p_status text, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_vendor_bills
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select * from app.list_finance_vendor_bills(p_tenant_id, p_company_id, p_vendor_master_id, p_status, p_actor_auth_user_id);
$function$;

revoke execute on function public.list_finance_vendor_bills(p_tenant_id uuid, p_company_id uuid, p_vendor_master_id uuid, p_status text, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_finance_vendor_bills(p_tenant_id uuid, p_company_id uuid, p_vendor_master_id uuid, p_status text, p_actor_auth_user_id uuid) to authenticated;
grant execute on function public.list_finance_vendor_bills(p_tenant_id uuid, p_company_id uuid, p_vendor_master_id uuid, p_status text, p_actor_auth_user_id uuid) to service_role;

-- 91. public.list_n8n_action_allowlist -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.list_n8n_action_allowlist();

create function public.list_n8n_action_allowlist()
 RETURNS SETOF app.n8n_action_allowlist
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select * from app.list_n8n_action_allowlist();
$function$;

revoke execute on function public.list_n8n_action_allowlist() from anon, authenticated, service_role, public;
grant execute on function public.list_n8n_action_allowlist() to authenticated;
grant execute on function public.list_n8n_action_allowlist() to service_role;

-- 92. public.match_finance_bank_transaction -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.match_finance_bank_transaction(p_transaction_id uuid, p_expected_version integer, p_matched_source_type text, p_matched_source_id uuid, p_actor_auth_user_id uuid, p_actor_label text);

create function public.match_finance_bank_transaction(p_transaction_id uuid, p_expected_version integer, p_matched_source_type text, p_matched_source_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_bank_transactions
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.match_finance_bank_transaction(p_transaction_id, p_expected_version, p_matched_source_type, p_matched_source_id, p_actor_auth_user_id, p_actor_label);
$function$;

revoke execute on function public.match_finance_bank_transaction(p_transaction_id uuid, p_expected_version integer, p_matched_source_type text, p_matched_source_id uuid, p_actor_auth_user_id uuid, p_actor_label text) from anon, authenticated, service_role, public;
grant execute on function public.match_finance_bank_transaction(p_transaction_id uuid, p_expected_version integer, p_matched_source_type text, p_matched_source_id uuid, p_actor_auth_user_id uuid, p_actor_label text) to authenticated;
grant execute on function public.match_finance_bank_transaction(p_transaction_id uuid, p_expected_version integer, p_matched_source_type text, p_matched_source_id uuid, p_actor_auth_user_id uuid, p_actor_label text) to service_role;

-- 93. public.place_finance_ap_hold -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.place_finance_ap_hold(p_open_item_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text);

create function public.place_finance_ap_hold(p_open_item_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_ap_open_items
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.place_finance_ap_hold(p_open_item_id, p_expected_version, p_reason, p_actor_auth_user_id, p_actor_label);
$function$;

revoke execute on function public.place_finance_ap_hold(p_open_item_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text) from anon, authenticated, service_role, public;
grant execute on function public.place_finance_ap_hold(p_open_item_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text) to authenticated;
grant execute on function public.place_finance_ap_hold(p_open_item_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text) to service_role;

-- 94. public.place_finance_ar_hold -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.place_finance_ar_hold(p_open_item_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text);

create function public.place_finance_ar_hold(p_open_item_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_ar_open_items
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.place_finance_ar_hold(p_open_item_id, p_expected_version, p_reason, p_actor_auth_user_id, p_actor_label);
$function$;

revoke execute on function public.place_finance_ar_hold(p_open_item_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text) from anon, authenticated, service_role, public;
grant execute on function public.place_finance_ar_hold(p_open_item_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text) to authenticated;
grant execute on function public.place_finance_ar_hold(p_open_item_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text) to service_role;

-- 95. public.post_finance_ap_open_item -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.post_finance_ap_open_item(p_tenant_id uuid, p_company_id uuid, p_vendor_master_id uuid, p_source_document_type text, p_source_document_id uuid, p_currency text, p_original_amount numeric, p_bill_date date, p_due_date date, p_actor_auth_user_id uuid, p_actor_label text);

create function public.post_finance_ap_open_item(p_tenant_id uuid, p_company_id uuid, p_vendor_master_id uuid, p_source_document_type text, p_source_document_id uuid, p_currency text, p_original_amount numeric, p_bill_date date, p_due_date date, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_ap_open_items
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.post_finance_ap_open_item(p_tenant_id, p_company_id, p_vendor_master_id, p_source_document_type, p_source_document_id, p_currency, p_original_amount, p_bill_date, p_due_date, p_actor_auth_user_id, p_actor_label);
$function$;

revoke execute on function public.post_finance_ap_open_item(p_tenant_id uuid, p_company_id uuid, p_vendor_master_id uuid, p_source_document_type text, p_source_document_id uuid, p_currency text, p_original_amount numeric, p_bill_date date, p_due_date date, p_actor_auth_user_id uuid, p_actor_label text) from anon, authenticated, service_role, public;
grant execute on function public.post_finance_ap_open_item(p_tenant_id uuid, p_company_id uuid, p_vendor_master_id uuid, p_source_document_type text, p_source_document_id uuid, p_currency text, p_original_amount numeric, p_bill_date date, p_due_date date, p_actor_auth_user_id uuid, p_actor_label text) to authenticated;
grant execute on function public.post_finance_ap_open_item(p_tenant_id uuid, p_company_id uuid, p_vendor_master_id uuid, p_source_document_type text, p_source_document_id uuid, p_currency text, p_original_amount numeric, p_bill_date date, p_due_date date, p_actor_auth_user_id uuid, p_actor_label text) to service_role;

-- 96. public.post_finance_ar_open_item -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.post_finance_ar_open_item(p_tenant_id uuid, p_company_id uuid, p_customer_account_id uuid, p_source_document_type text, p_source_document_id uuid, p_currency text, p_original_amount numeric, p_invoice_date date, p_due_date date, p_actor_auth_user_id uuid, p_actor_label text);

create function public.post_finance_ar_open_item(p_tenant_id uuid, p_company_id uuid, p_customer_account_id uuid, p_source_document_type text, p_source_document_id uuid, p_currency text, p_original_amount numeric, p_invoice_date date, p_due_date date, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_ar_open_items
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.post_finance_ar_open_item(p_tenant_id, p_company_id, p_customer_account_id, p_source_document_type, p_source_document_id, p_currency, p_original_amount, p_invoice_date, p_due_date, p_actor_auth_user_id, p_actor_label);
$function$;

revoke execute on function public.post_finance_ar_open_item(p_tenant_id uuid, p_company_id uuid, p_customer_account_id uuid, p_source_document_type text, p_source_document_id uuid, p_currency text, p_original_amount numeric, p_invoice_date date, p_due_date date, p_actor_auth_user_id uuid, p_actor_label text) from anon, authenticated, service_role, public;
grant execute on function public.post_finance_ar_open_item(p_tenant_id uuid, p_company_id uuid, p_customer_account_id uuid, p_source_document_type text, p_source_document_id uuid, p_currency text, p_original_amount numeric, p_invoice_date date, p_due_date date, p_actor_auth_user_id uuid, p_actor_label text) to authenticated;
grant execute on function public.post_finance_ar_open_item(p_tenant_id uuid, p_company_id uuid, p_customer_account_id uuid, p_source_document_type text, p_source_document_id uuid, p_currency text, p_original_amount numeric, p_invoice_date date, p_due_date date, p_actor_auth_user_id uuid, p_actor_label text) to service_role;

-- 97. public.preview_finance_config_impact -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.preview_finance_config_impact(p_version_id uuid);

create function public.preview_finance_config_impact(p_version_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.preview_finance_config_impact(p_version_id);
$function$;

revoke execute on function public.preview_finance_config_impact(p_version_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.preview_finance_config_impact(p_version_id uuid) to authenticated;
grant execute on function public.preview_finance_config_impact(p_version_id uuid) to service_role;

-- 98. public.preview_finance_subledger_posting -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.preview_finance_subledger_posting(p_tenant_id uuid, p_lines jsonb, p_actor_auth_user_id uuid);

create function public.preview_finance_subledger_posting(p_tenant_id uuid, p_lines jsonb, p_actor_auth_user_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.preview_finance_subledger_posting(p_tenant_id, p_lines, p_actor_auth_user_id);
$function$;

revoke execute on function public.preview_finance_subledger_posting(p_tenant_id uuid, p_lines jsonb, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.preview_finance_subledger_posting(p_tenant_id uuid, p_lines jsonb, p_actor_auth_user_id uuid) to authenticated;
grant execute on function public.preview_finance_subledger_posting(p_tenant_id uuid, p_lines jsonb, p_actor_auth_user_id uuid) to service_role;

-- 99. public.request_finance_period_reopen -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.request_finance_period_reopen(p_lock_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text);

create function public.request_finance_period_reopen(p_lock_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_period_locks
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.request_finance_period_reopen(p_lock_id, p_expected_version, p_reason, p_actor_auth_user_id, p_actor_label);
$function$;

revoke execute on function public.request_finance_period_reopen(p_lock_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text) from anon, authenticated, service_role, public;
grant execute on function public.request_finance_period_reopen(p_lock_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text) to authenticated;
grant execute on function public.request_finance_period_reopen(p_lock_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text) to service_role;

-- 100. public.resolve_finance_reconciliation_exception -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.resolve_finance_reconciliation_exception(p_exception_id uuid, p_expected_version integer, p_resolution_reason text, p_actor_auth_user_id uuid, p_actor_label text);

create function public.resolve_finance_reconciliation_exception(p_exception_id uuid, p_expected_version integer, p_resolution_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_reconciliation_exceptions
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.resolve_finance_reconciliation_exception(p_exception_id, p_expected_version, p_resolution_reason, p_actor_auth_user_id, p_actor_label);
$function$;

revoke execute on function public.resolve_finance_reconciliation_exception(p_exception_id uuid, p_expected_version integer, p_resolution_reason text, p_actor_auth_user_id uuid, p_actor_label text) from anon, authenticated, service_role, public;
grant execute on function public.resolve_finance_reconciliation_exception(p_exception_id uuid, p_expected_version integer, p_resolution_reason text, p_actor_auth_user_id uuid, p_actor_label text) to authenticated;
grant execute on function public.resolve_finance_reconciliation_exception(p_exception_id uuid, p_expected_version integer, p_resolution_reason text, p_actor_auth_user_id uuid, p_actor_label text) to service_role;

-- 101. public.search_finance_ap_candidates_for_settlement -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.search_finance_ap_candidates_for_settlement(p_tenant_id uuid, p_vendor_master_id uuid, p_currency text, p_actor_auth_user_id uuid);

create function public.search_finance_ap_candidates_for_settlement(p_tenant_id uuid, p_vendor_master_id uuid, p_currency text, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_ap_open_items
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select * from app.search_finance_ap_candidates_for_settlement(p_tenant_id, p_vendor_master_id, p_currency, p_actor_auth_user_id);
$function$;

revoke execute on function public.search_finance_ap_candidates_for_settlement(p_tenant_id uuid, p_vendor_master_id uuid, p_currency text, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.search_finance_ap_candidates_for_settlement(p_tenant_id uuid, p_vendor_master_id uuid, p_currency text, p_actor_auth_user_id uuid) to authenticated;
grant execute on function public.search_finance_ap_candidates_for_settlement(p_tenant_id uuid, p_vendor_master_id uuid, p_currency text, p_actor_auth_user_id uuid) to service_role;

-- 102. public.search_finance_ar_candidates_for_receipt -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.search_finance_ar_candidates_for_receipt(p_receipt_id uuid, p_actor_auth_user_id uuid);

create function public.search_finance_ar_candidates_for_receipt(p_receipt_id uuid, p_actor_auth_user_id uuid)
 RETURNS SETOF app.finance_ar_open_items
 LANGUAGE sql
 SECURITY DEFINER
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select * from app.search_finance_ar_candidates_for_receipt(p_receipt_id, p_actor_auth_user_id);
$function$;

revoke execute on function public.search_finance_ar_candidates_for_receipt(p_receipt_id uuid, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.search_finance_ar_candidates_for_receipt(p_receipt_id uuid, p_actor_auth_user_id uuid) to authenticated;
grant execute on function public.search_finance_ar_candidates_for_receipt(p_receipt_id uuid, p_actor_auth_user_id uuid) to service_role;

-- 103. public.set_finance_config_items -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.set_finance_config_items(p_version_id uuid, p_items jsonb, p_actor_auth_user_id uuid, p_actor_label text);

create function public.set_finance_config_items(p_version_id uuid, p_items jsonb, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS integer
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.set_finance_config_items(p_version_id, p_items, p_actor_auth_user_id, p_actor_label);
$function$;

revoke execute on function public.set_finance_config_items(p_version_id uuid, p_items jsonb, p_actor_auth_user_id uuid, p_actor_label text) from anon, authenticated, service_role, public;
grant execute on function public.set_finance_config_items(p_version_id uuid, p_items jsonb, p_actor_auth_user_id uuid, p_actor_label text) to authenticated;
grant execute on function public.set_finance_config_items(p_version_id uuid, p_items jsonb, p_actor_auth_user_id uuid, p_actor_label text) to service_role;

-- 104. public.soft_close_finance_period -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.soft_close_finance_period(p_period_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);

create function public.soft_close_finance_period(p_period_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_fiscal_periods
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.soft_close_finance_period(p_period_id, p_expected_version, p_actor_auth_user_id, p_actor_label);
$function$;

revoke execute on function public.soft_close_finance_period(p_period_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text) from anon, authenticated, service_role, public;
grant execute on function public.soft_close_finance_period(p_period_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text) to authenticated;
grant execute on function public.soft_close_finance_period(p_period_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text) to service_role;

-- 105. public.submit_finance_correction_for_approval -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.submit_finance_correction_for_approval(p_correction_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);

create function public.submit_finance_correction_for_approval(p_correction_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_journal_corrections
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.submit_finance_correction_for_approval(p_correction_id, p_expected_version, p_actor_auth_user_id, p_actor_label);
$function$;

revoke execute on function public.submit_finance_correction_for_approval(p_correction_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text) from anon, authenticated, service_role, public;
grant execute on function public.submit_finance_correction_for_approval(p_correction_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text) to authenticated;
grant execute on function public.submit_finance_correction_for_approval(p_correction_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text) to service_role;

-- 106. public.submit_finance_invoice_for_approval -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.submit_finance_invoice_for_approval(p_invoice_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);

create function public.submit_finance_invoice_for_approval(p_invoice_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_invoices
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.submit_finance_invoice_for_approval(p_invoice_id, p_expected_version, p_actor_auth_user_id, p_actor_label);
$function$;

revoke execute on function public.submit_finance_invoice_for_approval(p_invoice_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text) from anon, authenticated, service_role, public;
grant execute on function public.submit_finance_invoice_for_approval(p_invoice_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text) to authenticated;
grant execute on function public.submit_finance_invoice_for_approval(p_invoice_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text) to service_role;

-- 107. public.submit_finance_journal_for_approval -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.submit_finance_journal_for_approval(p_journal_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);

create function public.submit_finance_journal_for_approval(p_journal_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_journals
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.submit_finance_journal_for_approval(p_journal_id, p_expected_version, p_actor_auth_user_id, p_actor_label);
$function$;

revoke execute on function public.submit_finance_journal_for_approval(p_journal_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text) from anon, authenticated, service_role, public;
grant execute on function public.submit_finance_journal_for_approval(p_journal_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text) to authenticated;
grant execute on function public.submit_finance_journal_for_approval(p_journal_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text) to service_role;

-- 108. public.submit_finance_settlement_for_approval -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.submit_finance_settlement_for_approval(p_settlement_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);

create function public.submit_finance_settlement_for_approval(p_settlement_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_settlements
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.submit_finance_settlement_for_approval(p_settlement_id, p_expected_version, p_actor_auth_user_id, p_actor_label);
$function$;

revoke execute on function public.submit_finance_settlement_for_approval(p_settlement_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text) from anon, authenticated, service_role, public;
grant execute on function public.submit_finance_settlement_for_approval(p_settlement_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text) to authenticated;
grant execute on function public.submit_finance_settlement_for_approval(p_settlement_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text) to service_role;

-- 109. public.submit_finance_vendor_bill_for_approval -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.submit_finance_vendor_bill_for_approval(p_bill_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);

create function public.submit_finance_vendor_bill_for_approval(p_bill_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_vendor_bills
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.submit_finance_vendor_bill_for_approval(p_bill_id, p_expected_version, p_actor_auth_user_id, p_actor_label);
$function$;

revoke execute on function public.submit_finance_vendor_bill_for_approval(p_bill_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text) from anon, authenticated, service_role, public;
grant execute on function public.submit_finance_vendor_bill_for_approval(p_bill_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text) to authenticated;
grant execute on function public.submit_finance_vendor_bill_for_approval(p_bill_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text) to service_role;

-- 110. public.validate_automation_rule_definition -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.validate_automation_rule_definition(p_trigger_event_type text, p_conditions jsonb, p_actions jsonb);

create function public.validate_automation_rule_definition(p_trigger_event_type text, p_conditions jsonb, p_actions jsonb)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.validate_automation_rule_definition(p_trigger_event_type, p_conditions, p_actions);
$function$;

revoke execute on function public.validate_automation_rule_definition(p_trigger_event_type text, p_conditions jsonb, p_actions jsonb) from anon, authenticated, service_role, public;
grant execute on function public.validate_automation_rule_definition(p_trigger_event_type text, p_conditions jsonb, p_actions jsonb) to authenticated;
grant execute on function public.validate_automation_rule_definition(p_trigger_event_type text, p_conditions jsonb, p_actions jsonb) to service_role;

-- 111. public.validate_custom_field_values -- declared security definer by 20260826000000, live had drifted to invoker
drop function public.validate_custom_field_values(p_config_version_id uuid, p_values jsonb);

create function public.validate_custom_field_values(p_config_version_id uuid, p_values jsonb)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.validate_custom_field_values(p_config_version_id, p_values);
$function$;

revoke execute on function public.validate_custom_field_values(p_config_version_id uuid, p_values jsonb) from anon, authenticated, service_role, public;
grant execute on function public.validate_custom_field_values(p_config_version_id uuid, p_values jsonb) to authenticated;
grant execute on function public.validate_custom_field_values(p_config_version_id uuid, p_values jsonb) to service_role;
