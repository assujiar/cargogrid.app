/**
 * Customer/Account read queries (COM-155, CG-S7-COM-014). app.accounts carries no
 * masking (ADR-0018's own disclosed reason) -- reads go straight to the base table, not
 * through a *_directory view.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { toBoundedListByCapReached, type BoundedList } from "./bounded-list.ts";
import {
  FindDuplicateAccountsInputSchema,
  GetAccountConversionForQuotationInputSchema,
  GetAccountConversionReadinessInputSchema,
  parseAccount,
  parseAccountConversionReadiness,
  type FindDuplicateAccountsInput,
  type GetAccountConversionForQuotationInput,
  type GetAccountConversionReadinessInput,
  type Account,
  type AccountConversionReadiness,
} from "../contracts/account/account.ts";

export type AccountQueryClient = Pick<SupabaseClient, "rpc">;

export class AccountQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AccountQueryError";
  }
}

/**
 * Accounts for one tenant (any status), most recently created first -- tenant-wide reference data,
 * RLS-scoped by tenant membership only (not record-scoped).
 *
 * ISS-2026-238: bounded. This previously fetched EVERY account for the tenant on every page load,
 * live-verified by EXPLAIN as a quicksort over the full row set. It returns a BoundedList rather
 * than an array on purpose -- a silently capped list is worse than an unbounded one, because the
 * reader believes they are looking at all their accounts when they are looking at the newest 200.
 * The type change is what forces every caller to decide what to say about that.
 */
export async function listAccounts(client: AccountQueryClient, tenantId: string, actorAuthUserId: string): Promise<BoundedList<Account>> {
  const { data, error } = await client.rpc("list_accounts", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_limit: 200,
  });
  if (error) {
    throw new AccountQueryError(error.message);
  }
  return toBoundedListByCapReached((data ?? []).map((row: Record<string, unknown>) => parseAccount(row)));
}

/**
 * The subsidiaries of one account, resolved by the database rather than by filtering a capped
 * list in memory.
 *
 * ISS-2026-238 nearly introduced a correctness bug here. The account detail page used to call
 * `listAccounts` and then `.find()`/`.filter()` over the whole tenant to resolve a parent and its
 * subsidiaries. Capping that list would have made the page silently WRONG rather than merely
 * truncated: a parent outside the newest 200 would render as "no parent", and subsidiaries would
 * be under-reported with nothing indicating it. A targeted query is both correct and cheaper --
 * it was always the right shape, and the cap is what made that obvious.
 */
export async function listSubsidiaryAccounts(client: AccountQueryClient, parentAccountId: string, actorAuthUserId: string): Promise<Account[]> {
  const { data, error } = await client.rpc("list_subsidiary_accounts", {
    p_parent_account_id: parentAccountId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new AccountQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseAccount(row));
}

/** Returns null when not found or RLS denies it (matching every prior Commercial detail-page query's posture). */
export async function getAccountById(client: AccountQueryClient, accountId: string, actorAuthUserId: string): Promise<Account | null> {
  const { data, error } = await client.rpc("get_account_by_id", {
    p_account_id: accountId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new AccountQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row) {
    return null;
  }
  return parseAccount(row as Record<string, unknown>);
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

/** Returns null when the quotation has never been converted. Reads app.account_conversions, scoped to the quotation's own record-access envelope (RGL-BLK-002 / CG-AUDIT-2026-09-02 O1). */
export async function getAccountConversionForQuotation(
  client: AccountQueryClient,
  input: GetAccountConversionForQuotationInput,
): Promise<AccountConversionRecord | null> {
  const parsedInput = GetAccountConversionForQuotationInputSchema.parse(input);
  const { data, error } = await client.rpc("get_account_conversion_for_quotation", {
    p_quotation_id: parsedInput.quotationId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
  });
  if (error) {
    throw new AccountQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row) {
    return null;
  }
  const typed = row as { account_id: string; outcome: "created" | "linked_existing" };
  return { accountId: typed.account_id, outcome: typed.outcome };
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
