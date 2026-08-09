/**
 * Procurement Dashboard saved-view mutation primitives (PRC-266, CG-S11-PRC-017). Thin,
 * typed wrappers around the write RPCs supabase/migrations/20260730780000_create_
 * procurement_dashboard_reports.sql adds for app.procurement_dashboard_saved_views --
 * the same KNOWN_MUTATION_ERROR_CODES / classifyError / callRpc shape server/mutations/
 * vendor-performance.ts already establishes.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateProcurementDashboardSavedViewInputSchema,
  UpdateProcurementDashboardSavedViewInputSchema,
  DeleteProcurementDashboardSavedViewInputSchema,
  parseProcurementDashboardSavedView,
  type CreateProcurementDashboardSavedViewInput,
  type UpdateProcurementDashboardSavedViewInput,
  type DeleteProcurementDashboardSavedViewInput,
  type ProcurementDashboardSavedView,
} from "../contracts/procurement-dashboard/procurement-dashboard.ts";

export type ProcurementDashboardMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const PROCUREMENT_DASHBOARD_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "procurement_dashboard_saved_view_not_found",
  "invalid_metric_group",
  "name_required",
  "saved_view_unsafe_filters",
  "saved_view_unsafe_sort",
  "idempotency_key_conflict",
  "stale_version",
] as const;
type KnownProcurementDashboardMutationErrorCode = (typeof PROCUREMENT_DASHBOARD_KNOWN_MUTATION_ERROR_CODES)[number];
export type ProcurementDashboardMutationErrorCode = KnownProcurementDashboardMutationErrorCode | "mutation_failed" | "invalid_response";

export class ProcurementDashboardMutationError extends Error {
  readonly code: ProcurementDashboardMutationErrorCode;

  constructor(code: ProcurementDashboardMutationErrorCode, message: string) {
    super(message);
    this.name = "ProcurementDashboardMutationError";
    this.code = code;
  }
}

function classifyError(message: string): ProcurementDashboardMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (PROCUREMENT_DASHBOARD_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownProcurementDashboardMutationErrorCode) : "mutation_failed";
}

async function callRpc(client: ProcurementDashboardMutationRpcClient, fn: string, args: Record<string, unknown>): Promise<unknown> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new ProcurementDashboardMutationError(classifyError(error.message), error.message);
  }
  return data;
}

function requireRow<T>(data: unknown, parse: (row: Record<string, unknown>) => T, fn: string): T {
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new ProcurementDashboardMutationError("invalid_response", `${fn} returned no row`);
  }
  return parse(row as Record<string, unknown>);
}

export async function createProcurementDashboardSavedView(client: ProcurementDashboardMutationRpcClient, input: CreateProcurementDashboardSavedViewInput): Promise<ProcurementDashboardSavedView> {
  const p = CreateProcurementDashboardSavedViewInputSchema.parse(input);
  const data = await callRpc(client, "create_procurement_dashboard_saved_view", {
    p_tenant_id: p.tenantId,
    p_metric_group: p.metricGroup,
    p_name: p.name,
    p_description: p.description,
    p_filters: p.filters,
    p_sort: p.sort,
    p_idempotency_key: p.idempotencyKey,
    p_actor_auth_user_id: p.actorAuthUserId,
    p_actor_label: p.actorLabel,
  });
  return requireRow(data, parseProcurementDashboardSavedView, "create_procurement_dashboard_saved_view");
}

export async function updateProcurementDashboardSavedView(client: ProcurementDashboardMutationRpcClient, input: UpdateProcurementDashboardSavedViewInput): Promise<ProcurementDashboardSavedView> {
  const p = UpdateProcurementDashboardSavedViewInputSchema.parse(input);
  const data = await callRpc(client, "update_procurement_dashboard_saved_view", {
    p_view_id: p.viewId,
    p_expected_version: p.expectedVersion,
    p_name: p.name,
    p_description: p.description,
    p_filters: p.filters,
    p_sort: p.sort,
    p_actor_auth_user_id: p.actorAuthUserId,
    p_actor_label: p.actorLabel,
  });
  return requireRow(data, parseProcurementDashboardSavedView, "update_procurement_dashboard_saved_view");
}

export async function deleteProcurementDashboardSavedView(client: ProcurementDashboardMutationRpcClient, input: DeleteProcurementDashboardSavedViewInput): Promise<boolean> {
  const p = DeleteProcurementDashboardSavedViewInputSchema.parse(input);
  const data = await callRpc(client, "delete_procurement_dashboard_saved_view", {
    p_view_id: p.viewId,
    p_expected_version: p.expectedVersion,
    p_actor_auth_user_id: p.actorAuthUserId,
    p_actor_label: p.actorLabel,
  });
  return data === true;
}
