-- CG-AUDIT-2026-09-02 C3 (write-side correction). The read-side half of C3
-- (the admin tax-rule list rendering 0.11 as "0.11%" instead of "11%") was
-- already fixed. This is the write-side counterpart: app.create_finance_tax_rule_draft
-- has always enforced "rate_value >= 0" but never the percentage-basis upper
-- bound (`rate_value <= 1`, since a percentage rate is stored as a fraction --
-- see finance_tax_rule_versions_percentage_bound_check in
-- 20260729090000_create_finance_tax_baseline.sql). An SME who types "11" for
-- an 11% rate (rather than the required fractional "0.11") currently falls
-- through the RPC's own validation entirely and hits the raw, unclassified
-- Postgres CHECK-constraint violation on insert instead of a clean,
-- TAX_BASELINE_KNOWN_MUTATION_ERROR_CODES-classified error.
--
-- Fix: validate the same bound the CHECK constraint already enforces, one
-- statement earlier, reusing the existing `finance_tax_rule_invalid_rate`
-- error code (server/mutations/tax-baseline.ts already classifies it -- zero
-- TS change needed). This is a mechanical widening of an existing guard,
-- not a new validation concept.
--
-- Base definition for this CREATE OR REPLACE is deliberately taken from
-- 20260810700000_harden_finance_authority_chain_security_definer.sql (the
-- LAST migration to redefine this function), not from this function's
-- original 20260729090000 declaration -- that hardening pass added
-- `SECURITY DEFINER` + `SET search_path TO 'app', 'pg_temp'`, neither of
-- which the original declaration had. Copying the original body here would
-- have silently reverted that hardening (CREATE OR REPLACE FUNCTION always
-- takes the security/search_path clauses of the new statement, never
-- inherits the previous definition's), reintroducing exactly the class of
-- drift 20260831290000_restore_security_definer_on_drifted_finance_wrappers.sql
-- exists to fix. Caught by scripts/db-tests/public-api-wrapper-regression.sql's
-- own security-mode-parity check before this migration was ever committed.
create or replace function app.create_finance_tax_rule_draft(p_tenant_id uuid, p_tax_code_id uuid, p_rate_basis text, p_rate_value numeric, p_currency text, p_output_account_id uuid, p_recoverable_account_id uuid, p_effective_from date, p_effective_to date, p_actor_auth_user_id uuid, p_created_by text)
returns app.finance_tax_rule_versions
language plpgsql
security definer
set search_path to 'app', 'pg_temp'
as $function$
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
  if p_rate_basis = 'percentage' and p_rate_value > 1 then
    raise exception 'finance_tax_rule_invalid_rate: a percentage rate is stored as a fraction of 1 (e.g. 0.11 for 11%%), got % -- did you mean %?', p_rate_value, round(p_rate_value / 100, 6)
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

comment on function app.create_finance_tax_rule_draft(uuid, uuid, text, numeric, text, uuid, uuid, date, date, uuid, text) is
  'FIN-195: creates a draft tax rule version, FIN:Edit-gated. Hardened to SECURITY DEFINER with a restricted search_path by 20260810700000. CG-AUDIT-2026-09-02 C3: validates the percentage-basis upper bound (rate_value <= 1, a fraction of 1) in-RPC, ahead of finance_tax_rule_versions_percentage_bound_check, so a misentered whole-number rate (e.g. 11 instead of 0.11) is rejected with a classified finance_tax_rule_invalid_rate error rather than a raw constraint violation.';
