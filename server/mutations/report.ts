/**
 * Commercial Reports mutation primitives (COM-159, CG-S7-COM-018), extended by
 * IAE-002 (Reporting Engine, Prompt 330). Thin, typed wrappers around
 * app.record_report_run / app.enqueue_report_export
 * (supabase/migrations/20260724330000_create_commercial_reports.sql) and
 * app.publish_report_type_version / app.cancel_report_run
 * (supabase/migrations/20260802010000_create_intelligence_reporting_engine.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  RecordReportRunInputSchema,
  EnqueueReportExportInputSchema,
  PublishReportTypeVersionInputSchema,
  CancelReportRunInputSchema,
  parseReportRun,
  parseReportTypeVersion,
  type RecordReportRunInput,
  type EnqueueReportExportInput,
  type PublishReportTypeVersionInput,
  type CancelReportRunInput,
  type ReportRun,
  type ReportTypeVersion,
} from "../contracts/report/report.ts";

export type ReportMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const REPORT_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "report_type_unknown",
  "report_type_retired",
  "report_unsafe_parameters",
  "report_invalid_row_count",
  "report_invalid_parameter_schema",
  "report_invalid_source_function",
  "report_run_not_found",
  "report_run_not_cancellable",
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

/** IAE-002: cancels a still-queued export run. See app.cancel_report_run's own header for why this only ever touches app.report_runs, never app.jobs. */
export async function cancelReportRun(client: ReportMutationRpcClient, input: CancelReportRunInput): Promise<ReportRun> {
  const parsedInput = CancelReportRunInputSchema.parse(input);
  return callAndParseRun(client, "cancel_report_run", {
    p_run_id: parsedInput.runId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** IAE-002: Supreme-only. Publishes a new report-type definition version -- app.report_types moves to this new "current" state; every already-recorded run keeps citing its own prior version, never rewritten. */
export async function publishReportTypeVersion(client: ReportMutationRpcClient, input: PublishReportTypeVersionInput): Promise<ReportTypeVersion> {
  const parsedInput = PublishReportTypeVersionInputSchema.parse(input);
  const { data, error } = await client.rpc("publish_report_type_version", {
    p_code: parsedInput.code,
    p_source_function: parsedInput.sourceFunction,
    p_parameter_schema: parsedInput.parameterSchema,
    p_description: parsedInput.description,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ReportMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ReportMutationError("invalid_response", "publish_report_type_version returned no row");
  }
  return parseReportTypeVersion(data as Record<string, unknown>);
}
