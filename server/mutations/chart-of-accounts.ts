/**
 * Chart of Accounts mutation primitives (FIN-192, CG-S9-FIN-003). Thin, typed
 * wrappers around app.create_finance_account_draft / app.amend_finance_account_draft /
 * app.activate_finance_account / app.deactivate_finance_account
 * (supabase/migrations/20260728210000_create_finance_chart_of_accounts.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateFinanceAccountDraftInputSchema,
  AmendFinanceAccountDraftInputSchema,
  ActivateFinanceAccountInputSchema,
  DeactivateFinanceAccountInputSchema,
  parseFinanceAccount,
  type CreateFinanceAccountDraftInput,
  type AmendFinanceAccountDraftInput,
  type ActivateFinanceAccountInput,
  type DeactivateFinanceAccountInput,
  type FinanceAccount,
} from "../contracts/chart-of-accounts/chart-of-accounts.ts";
import { resolveRequestClientIp } from "../../lib/security/client-ip.ts";

export type ChartOfAccountsMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const CHART_OF_ACCOUNTS_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "finance_account_not_found",
  "finance_account_parent_not_found",
  "finance_account_cross_scope_parent",
  "finance_account_type_mismatch",
  "finance_account_duplicate_code",
  "finance_account_not_draft",
  "finance_account_not_active",
  "finance_account_hierarchy_cycle",
  "finance_account_parent_inactive",
  "finance_account_has_active_children",
  "finance_account_referenced_by_posting_map",
  "finance_account_deactivation_reason_required",
  "stale_version",
] as const;
type KnownChartOfAccountsMutationErrorCode = (typeof CHART_OF_ACCOUNTS_KNOWN_MUTATION_ERROR_CODES)[number];
export type ChartOfAccountsMutationErrorCode = KnownChartOfAccountsMutationErrorCode | "mutation_failed" | "invalid_response";

export class ChartOfAccountsMutationError extends Error {
  readonly code: ChartOfAccountsMutationErrorCode;

  constructor(code: ChartOfAccountsMutationErrorCode, message: string) {
    super(message);
    this.name = "ChartOfAccountsMutationError";
    this.code = code;
  }
}

function classifyError(message: string): ChartOfAccountsMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (CHART_OF_ACCOUNTS_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownChartOfAccountsMutationErrorCode)
    : "mutation_failed";
}

async function callAndParseAccount(
  client: ChartOfAccountsMutationRpcClient,
  fn: "create_finance_account_draft" | "amend_finance_account_draft" | "activate_finance_account" | "deactivate_finance_account",
  args: Record<string, unknown>,
): Promise<FinanceAccount> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new ChartOfAccountsMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ChartOfAccountsMutationError("invalid_response", `${fn} returned no row`);
  }
  return parseFinanceAccount(data as Record<string, unknown>);
}

/** Requires FIN:Create. Rejects a cross-scope/type-mismatched parent before ever inserting. */
export async function createFinanceAccountDraft(client: ChartOfAccountsMutationRpcClient, input: CreateFinanceAccountDraftInput): Promise<FinanceAccount> {
  const parsedInput = CreateFinanceAccountDraftInputSchema.parse(input);
  return callAndParseAccount(client, "create_finance_account_draft", {
    p_tenant_id: parsedInput.tenantId,
    p_company_id: parsedInput.companyId,
    p_code: parsedInput.code,
    p_name: parsedInput.name,
    p_account_type: parsedInput.accountType,
    p_normal_balance: parsedInput.normalBalance,
    p_parent_account_id: parsedInput.parentAccountId,
    p_is_control_account: parsedInput.isControlAccount,
    p_currency_restriction: parsedInput.currencyRestriction,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_created_by: parsedInput.createdBy,
  });
}

/** Requires FIN:Edit. Only a draft account may be amended. */
export async function amendFinanceAccountDraft(client: ChartOfAccountsMutationRpcClient, input: AmendFinanceAccountDraftInput): Promise<FinanceAccount> {
  const parsedInput = AmendFinanceAccountDraftInputSchema.parse(input);
  return callAndParseAccount(client, "amend_finance_account_draft", {
    p_account_id: parsedInput.accountId,
    p_expected_version: parsedInput.expectedVersion,
    p_name: parsedInput.name,
    p_currency_restriction: parsedInput.currencyRestriction,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** Requires FIN:Approve. Rejects an activation that would confirm a cyclic hierarchy or an inactive parent. */
export async function activateFinanceAccount(client: ChartOfAccountsMutationRpcClient, input: ActivateFinanceAccountInput): Promise<FinanceAccount> {
  const parsedInput = ActivateFinanceAccountInputSchema.parse(input);
  return callAndParseAccount(client, "activate_finance_account", {
    p_account_id: parsedInput.accountId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
    // ISS-2026-302: read here rather than threaded through every caller -- a security
    // control a call site can forget to pass is not a control. Null outside a request.
    p_client_ip: await resolveRequestClientIp(),
  });
}

/** Requires FIN:Delete and a mandatory reason. Rejects an account with active/draft children or a published posting-map reference. */
export async function deactivateFinanceAccount(client: ChartOfAccountsMutationRpcClient, input: DeactivateFinanceAccountInput): Promise<FinanceAccount> {
  const parsedInput = DeactivateFinanceAccountInputSchema.parse(input);
  return callAndParseAccount(client, "deactivate_finance_account", {
    p_account_id: parsedInput.accountId,
    p_expected_version: parsedInput.expectedVersion,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}
