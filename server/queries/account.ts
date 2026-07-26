/**
 * Customer/Account read queries (COM-155, CG-S7-COM-014). app.accounts carries no
 * masking (ADR-0018's own disclosed reason) -- reads go straight to the base table, not
 * through a *_directory view.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  FindDuplicateAccountsInputSchema,
  GetAccountConversionReadinessInputSchema,
  parseAccount,
  parseAccountConversionReadiness,
  type FindDuplicateAccountsInput,
  type GetAccountConversionReadinessInput,
  type Account,
  type AccountConversionReadiness,
} from "../contracts/account/account.ts";

export type AccountQueryClient = Pick<SupabaseClient, "from" | "rpc">;

export class AccountQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AccountQueryError";
  }
}

/** Every account for one tenant (any status), most recently created first -- tenant-wide reference data, RLS-scoped by tenant membership only (not record-scoped). */
export async function listAccounts(client: AccountQueryClient, tenantId: string): Promise<Account[]> {
  const { data, error } = await client.from("accounts").select("*").eq("tenant_id", tenantId).order("created_at", { ascending: false });
  if (error) {
    throw new AccountQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseAccount(row));
}

/** Returns null when not found or RLS denies it (matching every prior Commercial detail-page query's posture). */
export async function getAccountById(client: AccountQueryClient, accountId: string): Promise<Account | null> {
  const { data, error } = await client.from("accounts").select("*").eq("id", accountId).maybeSingle();
  if (error) {
    throw new AccountQueryError(error.message);
  }
  if (!data) {
    return null;
  }
  return parseAccount(data as Record<string, unknown>);
}

/** Tenant-scoped only, fails closed on missing membership. */
export async function findDuplicateAccounts(client: AccountQueryClient, input: FindDuplicateAccountsInput): Promise<Account[]> {
  const parsedInput = FindDuplicateAccountsInputSchema.parse(input);
  const { data, error } = await client.rpc("find_duplicate_accounts", {
    p_tenant_id: parsedInput.tenantId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_legal_name: parsedInput.legalName,
    p_tax_id: parsedInput.taxId,
  });
  if (error) {
    throw new AccountQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new AccountQueryError("find_duplicate_accounts returned a non-array result");
  }
  return data.map((row) => parseAccount(row as Record<string, unknown>));
}

export interface AccountConversionRecord {
  readonly accountId: string;
  readonly outcome: "created" | "linked_existing";
}

/** Returns null when the quotation has never been converted. Reads app.account_conversions directly (tenant-wide RLS, same posture as app.accounts). */
export async function getAccountConversionForQuotation(client: AccountQueryClient, quotationId: string): Promise<AccountConversionRecord | null> {
  const { data, error } = await client.from("account_conversions").select("account_id, outcome").eq("quotation_id", quotationId).maybeSingle();
  if (error) {
    throw new AccountQueryError(error.message);
  }
  if (!data) {
    return null;
  }
  const row = data as { account_id: string; outcome: "created" | "linked_existing" };
  return { accountId: row.account_id, outcome: row.outcome };
}

/** Structural readiness + duplicate-candidate preview for one accepted quotation -- reason codes only, never a dollar figure. */
export async function getAccountConversionReadiness(client: AccountQueryClient, input: GetAccountConversionReadinessInput): Promise<AccountConversionReadiness> {
  const parsedInput = GetAccountConversionReadinessInputSchema.parse(input);
  const { data, error } = await client.rpc("get_account_conversion_readiness", {
    p_quotation_id: parsedInput.quotationId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
  });
  if (error) {
    throw new AccountQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new AccountQueryError("get_account_conversion_readiness returned no row");
  }
  return parseAccountConversionReadiness(row as Record<string, unknown>);
}
