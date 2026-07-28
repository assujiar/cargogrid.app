import type { SupabaseClient } from "@supabase/supabase-js";
import {
  getOpsDashboardShipmentStatus,
  getOpsDashboardMilestoneSla,
  getOpsDashboardExceptionQueue,
  getOpsDashboardEpodCompletion,
  getOpsDashboardCostVariance,
  getOpsDashboardBillingReadiness,
} from "../../../../../server/queries/ops-dashboard.ts";

/**
 * Dispatches a report code to its one named source_function (OPS-183's own migration
 * header: "adds no new aggregation SQL at all"), reusing OPS-182's dashboard queries
 * verbatim -- the same dispatch shape `commercial/reports/run-report.ts` (COM-159)
 * already established. Returns each row already flattened to plain objects so the
 * report page can render a generic table.
 */
export async function runOpsReportByCode(
  client: SupabaseClient,
  reportTypeCode: string,
  filter: { tenantId: string },
): Promise<readonly Record<string, unknown>[]> {
  switch (reportTypeCode) {
    case "shipment_status_summary":
      return getOpsDashboardShipmentStatus(client, filter);
    case "milestone_sla_summary":
      return getOpsDashboardMilestoneSla(client, filter);
    case "exception_queue_summary":
      return getOpsDashboardExceptionQueue(client, filter);
    case "epod_completion_summary":
      return getOpsDashboardEpodCompletion(client, filter);
    case "cost_variance_summary":
      return getOpsDashboardCostVariance(client, filter);
    case "billing_readiness_summary":
      return getOpsDashboardBillingReadiness(client, filter);
    default:
      return [];
  }
}

/** Every `*Masked`-shaped boolean flag that was true in at least one row -- an honest, generic audit signal (Prompt 183 §18's "sensitive columns"), the same generic collector `commercial/reports/run-report.ts` (COM-159) already established. */
export function collectMaskedColumnFlags(rows: readonly Record<string, unknown>[]): string[] {
  const flags = new Set<string>();
  for (const row of rows) {
    for (const [key, value] of Object.entries(row)) {
      if (key.toLowerCase().endsWith("masked") && value === true) {
        flags.add(key);
      }
    }
  }
  return [...flags].sort();
}
