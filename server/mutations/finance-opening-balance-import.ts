/**
 * Finance opening-balance import domain adapter (ISS-2026-273, CG-AUDIT-2026-09-02
 * A4). Thin, typed wrappers around app.validate_finance_opening_balance_import_row /
 * app.commit_finance_opening_balance_import_job
 * (supabase/migrations/20260830130000_create_finance_opening_balance_import_and_gl_posting.sql).
 * Both are service_role-only (see that migration's own final grants block).
 *
 * app.validate_finance_opening_balance_import_row returns app.import_staging_rows
 * (the SAME composite type the generic app.validate_staging_row returns) and
 * app.commit_finance_opening_balance_import_job returns app.jobs (the same type
 * app.commit_import_job returns) -- both reuse the generic PLT-131 parsers
 * (parseImportStagingRow/parseImportExportJob) directly rather than duplicating
 * them, unlike server/mutations/employee.ts's own HRS-domain import adapters,
 * which have no shared parser to reuse.
 */

import {
  ValidateStagingRowInputSchema,
  CommitFinanceOpeningBalanceImportJobInputSchema,
  parseImportStagingRow,
  parseImportExportJob,
  type ValidateStagingRowInput,
  type CommitFinanceOpeningBalanceImportJobInput,
  type ImportStagingRow,
  type ImportExportJob,
} from "../contracts/import-export/import-export.ts";
import { IMPORT_EXPORT_KNOWN_MUTATION_ERROR_CODES } from "./import-export.ts";

export interface FinanceOpeningBalanceImportMutationRpcClient {
  rpc(
    fn: "validate_finance_opening_balance_import_row" | "commit_finance_opening_balance_import_job",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

const FINANCE_OPENING_BALANCE_IMPORT_KNOWN_MUTATION_ERROR_CODES = [
  ...IMPORT_EXPORT_KNOWN_MUTATION_ERROR_CODES,
  // app.commit_finance_opening_balance_import_job additionally composes
  // app.is_support_grant_authority + FIN:Import, app.assert_ip_allowed, and
  // app.assert_current_step_up_authorization on top of the generic framework's
  // own checks (20260901110000_harden_import_commit_step_up_mfa_gating.sql,
  // 20260807200000_create_intelligence_ip_restriction_network_access.sql:328's
  // and 20260807100000_create_intelligence_enterprise_mfa_session_controls.sql's
  // own exact raise-exception prefixes).
  "insufficient_authority",
  "ip_not_allowed",
  "mfa_step_up_required",
] as const;
type KnownFinanceOpeningBalanceImportMutationErrorCode = (typeof FINANCE_OPENING_BALANCE_IMPORT_KNOWN_MUTATION_ERROR_CODES)[number];
export type FinanceOpeningBalanceImportMutationErrorCode = KnownFinanceOpeningBalanceImportMutationErrorCode | "mutation_failed" | "invalid_response";

export class FinanceOpeningBalanceImportMutationError extends Error {
  readonly code: FinanceOpeningBalanceImportMutationErrorCode;

  constructor(code: FinanceOpeningBalanceImportMutationErrorCode, message: string) {
    super(message);
    this.name = "FinanceOpeningBalanceImportMutationError";
    this.code = code;
  }
}

function classifyError(message: string): FinanceOpeningBalanceImportMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (FINANCE_OPENING_BALANCE_IMPORT_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownFinanceOpeningBalanceImportMutationErrorCode)
    : "mutation_failed";
}

/** Calls app.validate_staging_row UNCHANGED first, then adds formula-injection rejection, ar/ap discrimination, currency/amount/date shape, fiscal-period-open, and counterparty resolution -- every check run at validation time precisely so a thousand-row cutover does not abort mid-commit. */
export async function validateFinanceOpeningBalanceImportRow(client: FinanceOpeningBalanceImportMutationRpcClient, input: ValidateStagingRowInput): Promise<ImportStagingRow> {
  const parsedInput = ValidateStagingRowInputSchema.parse(input);
  const { data, error } = await client.rpc("validate_finance_opening_balance_import_row", {
    p_staging_row_id: parsedInput.stagingRowId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new FinanceOpeningBalanceImportMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new FinanceOpeningBalanceImportMutationError("invalid_response", "validate_finance_opening_balance_import_row returned no row");
  }
  return parseImportStagingRow(data as Record<string, unknown>);
}

/** Requires BOTH tenant_admin/Supreme (app.is_support_grant_authority) AND FIN:Import, plus the IP-allowlist step-up gate when clientIp is supplied. All-or-nothing unless allowPartial is set. Posts BOTH the AR/AP open item AND its GL batch in the same transaction per row -- see the migration's own comment on why no state where they disagree is reachable. */
export async function commitFinanceOpeningBalanceImportJob(client: FinanceOpeningBalanceImportMutationRpcClient, input: CommitFinanceOpeningBalanceImportJobInput): Promise<ImportExportJob> {
  const parsedInput = CommitFinanceOpeningBalanceImportJobInputSchema.parse(input);
  const { data, error } = await client.rpc("commit_finance_opening_balance_import_job", {
    p_job_id: parsedInput.jobId,
    p_allow_partial: parsedInput.allowPartial,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
    p_client_ip: parsedInput.clientIp,
  });
  if (error) {
    throw new FinanceOpeningBalanceImportMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new FinanceOpeningBalanceImportMutationError("invalid_response", "commit_finance_opening_balance_import_job returned no row");
  }
  return parseImportExportJob(data as Record<string, unknown>);
}
