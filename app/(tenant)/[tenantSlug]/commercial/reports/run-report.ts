import type { SupabaseClient } from "@supabase/supabase-js";
import {
  getDashboardLeadAging,
  getDashboardActivityQueue,
  getDashboardPipelineSummary,
  getDashboardQuoteSla,
  getDashboardMarginSummary,
  getDashboardWinLossSummary,
  getDashboardForecastSummary,
} from "../../../../../server/queries/dashboard.ts";

/**
 * Dispatches a report code to its one named source_function (COM-159's own migration
 * header: "adds no new aggregation SQL at all"), reusing COM-158's dashboard queries
 * verbatim. Returns each row already flattened to plain objects so the report page can
 * render a generic table and this checkpoint never re-implements per-report rendering
 * logic for what is, underneath, the identical governed read.
 */
export async function runReportByCode(
  client: SupabaseClient,
  reportTypeCode: string,
  filter: { tenantId: string },
): Promise<readonly Record<string, unknown>[]> {
  switch (reportTypeCode) {
    case "lead_aging":
      return getDashboardLeadAging(client, filter);
    case "activity_queue":
      return getDashboardActivityQueue(client, filter);
    case "pipeline_summary":
      return getDashboardPipelineSummary(client, filter);
    case "quote_sla":
      return getDashboardQuoteSla(client, filter);
    case "margin_summary":
      return getDashboardMarginSummary(client, filter);
    case "win_loss_summary":
      return getDashboardWinLossSummary(client, filter);
    case "forecast_summary":
      return getDashboardForecastSummary(client, filter);
    default:
      return [];
  }
}

/** Every `*Masked` boolean flag that was true in at least one row -- an honest, generic audit signal (Prompt 159 §18's "sensitive columns"), not an attempt to translate each flag to its exact underlying amount column name, which differs per report. */
export function collectMaskedColumnFlags(rows: readonly Record<string, unknown>[]): string[] {
  const flags = new Set<string>();
  for (const row of rows) {
    for (const [key, value] of Object.entries(row)) {
      if (key.endsWith("Masked") && value === true) {
        flags.add(key);
      }
    }
  }
  return [...flags].sort();
}
