/**
 * Commercial Reports mutation primitives (COM-159, CG-S7-COM-018). Thin, typed
 * wrappers around app.record_report_run / app.enqueue_report_export
 * (supabase/migrations/20260724330000_create_commercial_reports.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  RecordReportRunInputSchema,
  EnqueueReportExportInputSchema,
  parseReportRun,
  type RecordReportRunInput,
  type EnqueueReportExportInput,
  type ReportRun,
} from "../contracts/report/report.ts";

export type ReportMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const REPORT_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "report_type_unknown",
  "report_type_retired",
  "report_unsafe_parameters",
  "report_invalid_row_count",
] as const;
type KnownReportMutationErrorCode = (typeof REPORT_KNOWN_MUTATION_ERROR_CODES)[number];
export type ReportMutationErrorCode = KnownReportMutationErrorCode | "mutation_failed" | "invalid_response";

export class ReportMutationError extends Error {
  readonly code: ReportMutationErrorCode;

  constructor(code: ReportMutationErrorCode, message: string) {
    super(message);
    this.name = "ReportMutationError";
    this.code = code;
  }
}

function classifyError(message: string): ReportMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (REPORT_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownReportMutationErrorCode)
    : "mutation_failed";
}

async function callAndParseRun(client: ReportMutationRpcClient, fn: string, args: Record<string, unknown>): Promise<ReportRun> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new ReportMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ReportMutationError("invalid_response", `${fn} returned no row`);
  }
  return parseReportRun(data as Record<string, unknown>);
}

/** Records a synchronous preview run's evidence. rowCount/maskedColumns must be computed by the caller from the app.get_dashboard_* RPC it already ran -- this never re-derives the query or the masking decision. */
export async function recordReportRun(client: ReportMutationRpcClient, input: RecordReportRunInput): Promise<ReportRun> {
  const parsedInput = RecordReportRunInputSchema.parse(input);
  return callAndParseRun(client, "record_report_run", {
    p_tenant_id: parsedInput.tenantId,
    p_report_type_code: parsedInput.reportTypeCode,
    p_parameters: parsedInput.parameters,
    p_row_count: parsedInput.rowCount,
    p_masked_columns: parsedInput.maskedColumns,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** COM:Export-gated. Enqueues a real report_generation job (PLT-132's app.enqueue_job) and returns the linking, status=queued app.report_runs row -- no live worker advances it further in this environment (disclosed, see the migration's own header). */
export async function enqueueReportExport(client: ReportMutationRpcClient, input: EnqueueReportExportInput): Promise<ReportRun> {
  const parsedInput = EnqueueReportExportInputSchema.parse(input);
  return callAndParseRun(client, "enqueue_report_export", {
    p_tenant_id: parsedInput.tenantId,
    p_report_type_code: parsedInput.reportTypeCode,
    p_parameters: parsedInput.parameters,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}
