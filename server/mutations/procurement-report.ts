/**
 * Procurement Reports export mutation primitive (PRC-266, CG-S11-PRC-017). A thin,
 * typed wrapper around the one genuinely new RPC, app.enqueue_procurement_report_export
 * (supabase/migrations/20260730780000_create_procurement_dashboard_reports.sql) --
 * mirrors server/mutations/finance-report.ts's (FIN-213) own identical shape, a
 * parallel entry point to server/mutations/report.ts's (COM-159) own
 * enqueueReportExport. Preview runs reuse recordReportRun (server/mutations/report.ts)
 * directly -- unchanged, module-agnostic.
 *
 * Unlike its FIN-213/OPS-183 siblings, this function's own RPC takes a REAL
 * idempotency key (design note 7 in the migration's own header: a confirmed, disclosed
 * C-01 gap in the reused app.enqueue_job primitive is worked around at this call site),
 * so this wrapper's input shape adds idempotencyKey where the shared
 * EnqueueReportExportInputSchema (report.ts) has none.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { z } from "zod";
import { ReportParametersSchema, parseReportRun, type ReportRun } from "../contracts/report/report.ts";
import { ReportMutationError, REPORT_KNOWN_MUTATION_ERROR_CODES, type ReportMutationErrorCode } from "./report.ts";

export type ProcurementReportMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const EnqueueProcurementReportExportInputSchema = z.object({
  tenantId: z.string().uuid(),
  reportTypeCode: z.string().min(1),
  parameters: ReportParametersSchema.default({ orgUnitId: null, ownerUserId: null, periodStart: null, periodEnd: null }),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type EnqueueProcurementReportExportInput = z.input<typeof EnqueueProcurementReportExportInputSchema>;

/**
 * report_type_not_procurement_owned (this RPC's own module-scoping check, design note
 * 6) is a real error prefix but deliberately NOT added to the shared
 * ReportMutationErrorCode union -- that union is owned by server/mutations/report.ts
 * (COM-159) and shared across three modules; widening it for one Procurement-only
 * error code would be exactly the kind of unrelated cross-module edit this checkpoint
 * has no mandate to make. It classifies as "mutation_failed" here, same as any other
 * unrecognized prefix -- callers that need to distinguish it read error.message.
 */
function classifyError(message: string): ReportMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (REPORT_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as ReportMutationErrorCode) : "mutation_failed";
}

/** PRC:Export-gated. Enqueues a real report_generation job (PLT-132's app.enqueue_job) and returns the linking, status=queued app.report_runs row -- no live worker advances it further in this environment (disclosed, see the migration's own header). */
export async function enqueueProcurementReportExport(client: ProcurementReportMutationRpcClient, input: EnqueueProcurementReportExportInput): Promise<ReportRun> {
  const p = EnqueueProcurementReportExportInputSchema.parse(input);
  const { data, error } = await client.rpc("enqueue_procurement_report_export", {
    p_tenant_id: p.tenantId,
    p_report_type_code: p.reportTypeCode,
    p_parameters: p.parameters,
    p_idempotency_key: p.idempotencyKey,
    p_actor_auth_user_id: p.actorAuthUserId,
    p_actor_label: p.actorLabel,
  });
  if (error) {
    throw new ReportMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ReportMutationError("invalid_response", "enqueue_procurement_report_export returned no row");
  }
  return parseReportRun(data as Record<string, unknown>);
}
