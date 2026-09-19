/**
 * Customer/Account mutation primitives (COM-155, CG-S7-COM-014). Thin, typed wrapper
 * around app.convert_quotation_to_account
 * (supabase/migrations/20260724290000_create_commercial_customer_account_conversion.sql)
 * -- the one atomic, idempotent create-or-link operation.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { ConvertQuotationToAccountInputSchema, parseAccount, type ConvertQuotationToAccountInput, type Account } from "../contracts/account/account.ts";
import {
  ValidateStagingRowInputSchema,
  CommitCustomerImportJobInputSchema,
  parseImportStagingRow,
  parseImportExportJob,
  type ValidateStagingRowInput,
  type CommitCustomerImportJobInput,
  type ImportStagingRow,
  type ImportExportJob,
} from "../contracts/import-export/import-export.ts";

export type AccountMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const ACCOUNT_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "quotation_not_found",
  "quotation_not_accepted",
  "missing_legal_name",
  "target_account_not_found",
  // --- Staged import (CG-AUDIT-2026-09-02 A4, fifth import schema) ---
  // app.validate_customer_import_row/app.commit_customer_import_job
  // (supabase/migrations/20260830120000_create_customer_and_item_import_adapters.sql,
  // latest commit redefinition
  // 20260903122000_harden_tenant_id_disclosure_hris_payroll_import_commit.sql)
  // compose the generic PLT-131 framework's own errors plus these
  // domain-specific ones.
  "import_export_job_not_found",
  "import_export_wrong_schema",
  "job_actor_unauthorized",
  "mfa_step_up_required",
  "ip_not_allowed",
  "import_export_job_not_committable",
  "import_export_job_not_fully_validated",
  "import_export_job_has_invalid_rows",
  // ISS-2026-277: a resolved duplicate-fingerprint match (create-or-link, not
  // flag-for-review) that lands on an account under legal hold refuses the
  // whole commit rather than silently linking import content to a held record.
  "import_blocked_legal_hold",
] as const;
type KnownAccountMutationErrorCode = (typeof ACCOUNT_KNOWN_MUTATION_ERROR_CODES)[number];
export type AccountMutationErrorCode = KnownAccountMutationErrorCode | "mutation_failed" | "invalid_response";

export class AccountMutationError extends Error {
  readonly code: AccountMutationErrorCode;

  constructor(code: AccountMutationErrorCode, message: string) {
    super(message);
    this.name = "AccountMutationError";
    this.code = code;
  }
}

function classifyError(message: string): AccountMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (ACCOUNT_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownAccountMutationErrorCode) : "mutation_failed";
}

/** Idempotent on quotationId (unique(quotation_id) on app.account_conversions) -- a repeated call for an already-converted quotation returns the same account, never a duplicate. targetAccountId set = link to an existing account (after duplicate review); null = create a brand-new one, optionally under parentAccountId. */
export async function convertQuotationToAccount(client: AccountMutationRpcClient, input: ConvertQuotationToAccountInput): Promise<Account> {
  const parsedInput = ConvertQuotationToAccountInputSchema.parse(input);
  const { data, error } = await client.rpc("convert_quotation_to_account", {
    p_quotation_id: parsedInput.quotationId,
    p_target_account_id: parsedInput.targetAccountId,
    p_parent_account_id: parsedInput.parentAccountId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new AccountMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new AccountMutationError("invalid_response", "convert_quotation_to_account returned no row");
  }
  return parseAccount(data as Record<string, unknown>);
}

// --- Staged import (CG-AUDIT-2026-09-02 A4, fifth import schema) ---
// app.validate_customer_import_row returns app.import_staging_rows and
// app.commit_customer_import_job returns app.jobs -- the SAME composite types
// the generic PLT-131 app.validate_staging_row/app.commit_import_job return, so
// both reuse the generic parsers directly, mirroring
// server/mutations/finance-opening-balance-import.ts's own precedent.

/** Calls app.validate_staging_row UNCHANGED first, then adds formula/spreadsheet-injection rejection (legal_name, trade_name, tax_id, billing_line1/city/region/postal_code/country), a whitespace-only legal_name check, and refuses a row that supplies status/merged_into_id/duplicate_fingerprint/normalized_legal_name/normalized_tax_id/source_prospect_id -- those are derived or controlled by the platform, never importable. */
export async function validateCustomerImportRow(client: AccountMutationRpcClient, input: ValidateStagingRowInput): Promise<ImportStagingRow> {
  const parsed = ValidateStagingRowInputSchema.parse(input);
  const { data, error } = await client.rpc("validate_customer_import_row", {
    p_staging_row_id: parsed.stagingRowId,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new AccountMutationError(classifyError(error.message), error.message);
  if (!data || typeof data !== "object") throw new AccountMutationError("invalid_response", "validate_customer_import_row returned no row");
  return parseImportStagingRow(data as Record<string, unknown>);
}

/** Requires COM:Import AND is_support_grant_authority (additive, never either-or). Writes only through app.create_customer_account_direct (never a direct INSERT), assembling the billing address from flat CSV columns. Create-or-link, not flag-for-review: a duplicate-fingerprint match resolves to the existing account and is counted as linked, never blocked -- unless that account is under legal hold, which aborts the whole commit (import_blocked_legal_hold). */
export async function commitCustomerImportJob(client: AccountMutationRpcClient, input: CommitCustomerImportJobInput): Promise<ImportExportJob> {
  const parsed = CommitCustomerImportJobInputSchema.parse(input);
  const { data, error } = await client.rpc("commit_customer_import_job", {
    p_job_id: parsed.jobId,
    p_allow_partial: parsed.allowPartial,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
    p_client_ip: parsed.clientIp,
  });
  if (error) throw new AccountMutationError(classifyError(error.message), error.message);
  if (!data || typeof data !== "object") throw new AccountMutationError("invalid_response", "commit_customer_import_job returned no row");
  return parseImportExportJob(data as Record<string, unknown>);
}
