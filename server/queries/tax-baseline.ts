/**
 * Tax Baseline read queries (FIN-195, CG-S9-FIN-006). Thin, typed wrappers
 * around app.list_finance_tax_codes / app.list_finance_tax_rule_versions /
 * app.resolve_finance_tax_rule / app.calculate_finance_tax
 * (supabase/migrations/20260729090000_create_finance_tax_baseline.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseFinanceTaxCode,
  parseFinanceTaxRuleVersion,
  parseFinanceTaxCalculation,
  type FinanceTaxCode,
  type FinanceTaxRuleVersion,
  type FinanceTaxCalculation,
} from "../contracts/tax-baseline/tax-baseline.ts";

export type TaxBaselineQueryRpcClient = Pick<SupabaseClient, "rpc">;

export class TaxBaselineQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "TaxBaselineQueryError";
  }
}

/** FIN:View-gated. Every tax code visible to this tenant (platform-wide catalog plus any tenant-specific code), active only. */
export async function listFinanceTaxCodes(
  client: TaxBaselineQueryRpcClient,
  input: { tenantId: string | null; actorAuthUserId: string },
): Promise<FinanceTaxCode[]> {
  const { data, error } = await client.rpc("list_finance_tax_codes", {
    p_tenant_id: input.tenantId,
    p_actor_auth_user_id: input.actorAuthUserId,
  });
  if (error) {
    throw new TaxBaselineQueryError(error.message);
  }
  const rows = Array.isArray(data) ? data : [];
  return rows.map((row) => parseFinanceTaxCode(row as Record<string, unknown>));
}

/** FIN:View-gated, bounded list read, ordered effective_from desc. */
export async function listFinanceTaxRuleVersions(
  client: TaxBaselineQueryRpcClient,
  input: { tenantId: string | null; taxCodeId: string | null; actorAuthUserId: string },
): Promise<FinanceTaxRuleVersion[]> {
  const { data, error } = await client.rpc("list_finance_tax_rule_versions", {
    p_tenant_id: input.tenantId,
    p_tax_code_id: input.taxCodeId,
    p_actor_auth_user_id: input.actorAuthUserId,
  });
  if (error) {
    throw new TaxBaselineQueryError(error.message);
  }
  const rows = Array.isArray(data) ? data : [];
  return rows.map((row) => parseFinanceTaxRuleVersion(row as Record<string, unknown>));
}

/**
 * Exact-decimal calculation preview (FIN:View-gated). Throws (via
 * TaxBaselineQueryError) when no approved rule covers the tax code/instant --
 * never silently returns a zero or guessed tax amount.
 */
export async function calculateFinanceTax(
  client: TaxBaselineQueryRpcClient,
  input: { tenantId: string | null; taxCode: string; baseAmount: number; asOf: string | null; actorAuthUserId: string },
): Promise<FinanceTaxCalculation> {
  const { data, error } = await client.rpc("calculate_finance_tax", {
    p_tenant_id: input.tenantId,
    p_tax_code: input.taxCode,
    p_base_amount: input.baseAmount,
    p_as_of: input.asOf ?? undefined,
    p_actor_auth_user_id: input.actorAuthUserId,
  });
  if (error) {
    throw new TaxBaselineQueryError(error.message);
  }
  if (!data || typeof data !== "object") {
    throw new TaxBaselineQueryError("calculate_finance_tax returned no result");
  }
  return parseFinanceTaxCalculation(data as Record<string, unknown>);
}
