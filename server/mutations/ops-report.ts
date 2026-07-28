/**
 * Operations Reports mutation primitives (OPS-183, CG-S8-OPS-017). A thin, typed
 * wrapper around the one genuinely new RPC, app.enqueue_ops_report_export
 * (supabase/migrations/20260728160000_create_operations_reports.sql). Preview runs
 * reuse `recordReportRun` (`server/mutations/report.ts`, COM-159) directly -- that
 * function is already module-agnostic (only tenant membership is checked, no
 * COM-specific gate), so no Operations-specific wrapper is needed for it.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { EnqueueReportExportInputSchema, parseReportRun, type EnqueueReportExportInput, type ReportRun } from "../contracts/report/report.ts";
import { ReportMutationError, REPORT_KNOWN_MUTATION_ERROR_CODES, type ReportMutationErrorCode } from "./report.ts";

export type OpsReportMutationRpcClient = Pick<SupabaseClient, "rpc">;

function classifyError(message: string): ReportMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (REPORT_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as ReportMutationErrorCode) : "mutation_failed";
}

/** OPS:Export-gated. Enqueues a real report_generation job (PLT-132's app.enqueue_job) and returns the linking, status=queued app.report_runs row -- no live worker advances it further in this environment (disclosed, see the migration's own header). */
export async function enqueueOpsReportExport(client: OpsReportMutationRpcClient, input: EnqueueReportExportInput): Promise<ReportRun> {
  const parsedInput = EnqueueReportExportInputSchema.parse(input);
  const { data, error } = await client.rpc("enqueue_ops_report_export", {
    p_tenant_id: parsedInput.tenantId,
    p_report_type_code: parsedInput.reportTypeCode,
    p_parameters: parsedInput.parameters,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ReportMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ReportMutationError("invalid_response", "enqueue_ops_report_export returned no row");
  }
  return parseReportRun(data as Record<string, unknown>);
}
