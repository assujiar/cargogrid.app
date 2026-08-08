/**
 * Vendor Performance read queries (PRC-264, CG-S11-PRC-015). Thin, typed wrappers
 * around the dedicated read RPCs (supabase/migrations/20260730740000_create_
 * procurement_vendor_performance.sql) -- mirrors server/queries/vendor-contract.ts
 * exactly: every RPC already carries its own explicit evaluate_permission check plus
 * PRC:View cost source-evidence masking, so this file calls `.rpc(...)`, never
 * `.from(...)`, on a base table.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseVendorKpiDefinition,
  parseVendorKpiScorecard,
  parseVendorKpiScorecardDrilldownLine,
  parseVendorKpiSourceDispute,
  parseVendorPerformanceIssue,
  parseVendorPerformanceCorrectiveAction,
  parseVendorKpiManualAdjustment,
  parseVendorLifecycleRecommendation,
  parseVendorKpiMeasurementRun,
  type VendorKpiDefinition,
  type VendorKpiDefinitionStatus,
  type VendorKpiCode,
  type VendorKpiScorecard,
  type VendorKpiScorecardDrilldownLine,
  type VendorKpiSourceDispute,
  type VendorPerformanceIssue,
  type VendorPerformanceCorrectiveAction,
  type VendorKpiManualAdjustment,
  type VendorLifecycleRecommendation,
  type VendorKpiMeasurementRun,
} from "../contracts/vendor-performance/vendor-performance.ts";

export type VendorPerformanceQueryRpcClient = Pick<SupabaseClient, "rpc">;

export class VendorPerformanceQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "VendorPerformanceQueryError";
  }
}

function requireRow<T>(data: unknown, parse: (row: Record<string, unknown>) => T, fn: string): T {
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new VendorPerformanceQueryError(`${fn} returned no row`);
  }
  return parse(row as Record<string, unknown>);
}

async function callRpc(client: VendorPerformanceQueryRpcClient, fn: string, args: Record<string, unknown>): Promise<unknown> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new VendorPerformanceQueryError(error.message);
  }
  return data;
}

// -- KPI catalogue -----------------------------------------------------------

export async function getVendorKpiDefinition(client: VendorPerformanceQueryRpcClient, definitionId: string, actorAuthUserId: string): Promise<VendorKpiDefinition> {
  const data = await callRpc(client, "get_vendor_kpi_definition", { p_definition_id: definitionId, p_actor_auth_user_id: actorAuthUserId });
  return requireRow(data, parseVendorKpiDefinition, "get_vendor_kpi_definition");
}

export async function listVendorKpiDefinitions(
  client: VendorPerformanceQueryRpcClient,
  tenantId: string,
  actorAuthUserId: string,
  statusFilter: VendorKpiDefinitionStatus | null = null,
  limit = 50,
): Promise<VendorKpiDefinition[]> {
  const { data, error } = await client.rpc("list_vendor_kpi_definitions", { p_tenant_id: tenantId, p_status: statusFilter, p_actor_auth_user_id: actorAuthUserId, p_limit: limit });
  if (error) throw new VendorPerformanceQueryError(error.message);
  return (data ?? []).map((row: Record<string, unknown>) => parseVendorKpiDefinition(row));
}

export async function listVendorKpiDefinitionVersions(client: VendorPerformanceQueryRpcClient, tenantId: string, kpiCode: VendorKpiCode, actorAuthUserId: string): Promise<VendorKpiDefinition[]> {
  const { data, error } = await client.rpc("list_vendor_kpi_definition_versions", { p_tenant_id: tenantId, p_kpi_code: kpiCode, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new VendorPerformanceQueryError(error.message);
  return (data ?? []).map((row: Record<string, unknown>) => parseVendorKpiDefinition(row));
}

// -- Measurement / scorecards -------------------------------------------------
// Metric VALUES themselves have no standalone list RPC -- they are always read through
// the scorecard drilldown (getVendorKpiScorecardDrilldown below), which is the one
// place the source_evidence PRC:View-cost masking applies. app.vendor_kpi_metric_
// values is a real, tested table (scripts/db-tests/procurement-vendor-performance.sql)
// with no direct UI read path of its own, by design, not omission.

export async function getVendorKpiMeasurementRun(client: VendorPerformanceQueryRpcClient, runId: string, actorAuthUserId: string): Promise<VendorKpiMeasurementRun> {
  const data = await callRpc(client, "get_vendor_kpi_measurement_run", { p_run_id: runId, p_actor_auth_user_id: actorAuthUserId });
  return requireRow(data, parseVendorKpiMeasurementRun, "get_vendor_kpi_measurement_run");
}

export async function getVendorKpiScorecard(client: VendorPerformanceQueryRpcClient, scorecardId: string, actorAuthUserId: string): Promise<VendorKpiScorecard> {
  const data = await callRpc(client, "get_vendor_kpi_scorecard", { p_scorecard_id: scorecardId, p_actor_auth_user_id: actorAuthUserId });
  return requireRow(data, parseVendorKpiScorecard, "get_vendor_kpi_scorecard");
}

/** p_vendor_master_id=null lists the latest CURRENT scorecard per vendor (the queue view); a supplied vendor id lists that vendor's full version history. */
export async function listVendorKpiScorecards(
  client: VendorPerformanceQueryRpcClient,
  tenantId: string,
  actorAuthUserId: string,
  vendorMasterId: string | null = null,
  limit = 25,
): Promise<VendorKpiScorecard[]> {
  const { data, error } = await client.rpc("list_vendor_kpi_scorecards", { p_tenant_id: tenantId, p_vendor_master_id: vendorMasterId, p_actor_auth_user_id: actorAuthUserId, p_limit: limit });
  if (error) throw new VendorPerformanceQueryError(error.message);
  return (data ?? []).map((row: Record<string, unknown>) => parseVendorKpiScorecard(row));
}

export async function getVendorKpiScorecardDrilldown(client: VendorPerformanceQueryRpcClient, scorecardId: string, actorAuthUserId: string): Promise<VendorKpiScorecardDrilldownLine[]> {
  const { data, error } = await client.rpc("get_vendor_kpi_scorecard_drilldown", { p_scorecard_id: scorecardId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new VendorPerformanceQueryError(error.message);
  return (data ?? []).map((row: Record<string, unknown>) => parseVendorKpiScorecardDrilldownLine(row));
}

// -- Source disputes -----------------------------------------------------------

export async function getVendorKpiSourceDispute(client: VendorPerformanceQueryRpcClient, disputeId: string, actorAuthUserId: string): Promise<VendorKpiSourceDispute> {
  const data = await callRpc(client, "get_vendor_kpi_source_dispute", { p_dispute_id: disputeId, p_actor_auth_user_id: actorAuthUserId });
  return requireRow(data, parseVendorKpiSourceDispute, "get_vendor_kpi_source_dispute");
}

export async function listVendorKpiSourceDisputes(
  client: VendorPerformanceQueryRpcClient,
  tenantId: string,
  actorAuthUserId: string,
  vendorMasterId: string | null = null,
  statusFilter: string | null = null,
): Promise<VendorKpiSourceDispute[]> {
  const { data, error } = await client.rpc("list_vendor_kpi_source_disputes", { p_tenant_id: tenantId, p_vendor_master_id: vendorMasterId, p_status: statusFilter, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new VendorPerformanceQueryError(error.message);
  return (data ?? []).map((row: Record<string, unknown>) => parseVendorKpiSourceDispute(row));
}

// -- Issues / corrective actions -------------------------------------------------

export async function getVendorPerformanceIssue(client: VendorPerformanceQueryRpcClient, issueId: string, actorAuthUserId: string): Promise<VendorPerformanceIssue> {
  const data = await callRpc(client, "get_vendor_performance_issue", { p_issue_id: issueId, p_actor_auth_user_id: actorAuthUserId });
  return requireRow(data, parseVendorPerformanceIssue, "get_vendor_performance_issue");
}

export async function listVendorPerformanceIssues(
  client: VendorPerformanceQueryRpcClient,
  tenantId: string,
  actorAuthUserId: string,
  vendorMasterId: string | null = null,
  statusFilter: string | null = null,
  limit = 50,
): Promise<VendorPerformanceIssue[]> {
  const { data, error } = await client.rpc("list_vendor_performance_issues", { p_tenant_id: tenantId, p_vendor_master_id: vendorMasterId, p_status: statusFilter, p_actor_auth_user_id: actorAuthUserId, p_limit: limit });
  if (error) throw new VendorPerformanceQueryError(error.message);
  return (data ?? []).map((row: Record<string, unknown>) => parseVendorPerformanceIssue(row));
}

export async function listVendorPerformanceCorrectiveActions(client: VendorPerformanceQueryRpcClient, issueId: string, actorAuthUserId: string): Promise<VendorPerformanceCorrectiveAction[]> {
  const { data, error } = await client.rpc("list_vendor_performance_corrective_actions", { p_issue_id: issueId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new VendorPerformanceQueryError(error.message);
  return (data ?? []).map((row: Record<string, unknown>) => parseVendorPerformanceCorrectiveAction(row));
}

// -- Manual adjustments -------------------------------------------------

export async function getVendorKpiManualAdjustment(client: VendorPerformanceQueryRpcClient, adjustmentId: string, actorAuthUserId: string): Promise<VendorKpiManualAdjustment> {
  const data = await callRpc(client, "get_vendor_kpi_manual_adjustment", { p_adjustment_id: adjustmentId, p_actor_auth_user_id: actorAuthUserId });
  return requireRow(data, parseVendorKpiManualAdjustment, "get_vendor_kpi_manual_adjustment");
}

export async function listVendorKpiManualAdjustments(client: VendorPerformanceQueryRpcClient, scorecardId: string, actorAuthUserId: string): Promise<VendorKpiManualAdjustment[]> {
  const { data, error } = await client.rpc("list_vendor_kpi_manual_adjustments", { p_scorecard_id: scorecardId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new VendorPerformanceQueryError(error.message);
  return (data ?? []).map((row: Record<string, unknown>) => parseVendorKpiManualAdjustment(row));
}

// -- Governed lifecycle recommendations -------------------------------------------------

export async function getVendorLifecycleRecommendation(client: VendorPerformanceQueryRpcClient, recommendationId: string, actorAuthUserId: string): Promise<VendorLifecycleRecommendation> {
  const data = await callRpc(client, "get_vendor_lifecycle_recommendation", { p_recommendation_id: recommendationId, p_actor_auth_user_id: actorAuthUserId });
  return requireRow(data, parseVendorLifecycleRecommendation, "get_vendor_lifecycle_recommendation");
}

export async function listVendorLifecycleRecommendations(
  client: VendorPerformanceQueryRpcClient,
  tenantId: string,
  actorAuthUserId: string,
  vendorMasterId: string | null = null,
  statusFilter: string | null = null,
  limit = 50,
): Promise<VendorLifecycleRecommendation[]> {
  const { data, error } = await client.rpc("list_vendor_lifecycle_recommendations", { p_tenant_id: tenantId, p_vendor_master_id: vendorMasterId, p_status: statusFilter, p_actor_auth_user_id: actorAuthUserId, p_limit: limit });
  if (error) throw new VendorPerformanceQueryError(error.message);
  return (data ?? []).map((row: Record<string, unknown>) => parseVendorLifecycleRecommendation(row));
}
