/**
 * Dashboard Builder read queries (IAE-003, Prompt 331). All RLS-scoped reads
 * via RPC (O1 remediation, cluster 6) -- app is not exposed to PostgREST. All
 * 5 functions are SECURITY INVOKER, zero actor parameter.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseTenantDashboard,
  parseTenantDashboardVersion,
  parseTenantDashboardWidget,
  type TenantDashboard,
  type TenantDashboardVersion,
  type TenantDashboardWidget,
} from "../contracts/tenant-dashboard/tenant-dashboard.ts";

export type TenantDashboardQueryTableClient = Pick<SupabaseClient, "rpc">;

export class TenantDashboardQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "TenantDashboardQueryError";
  }
}

/** Every dashboard for one tenant, most recently updated first -- RLS (tenant_dashboards_select_scoped) is the real scope gate. */
export async function listTenantDashboards(client: TenantDashboardQueryTableClient, tenantId: string): Promise<TenantDashboard[]> {
  const { data, error } = await client.rpc("list_tenant_dashboards", { p_tenant_id: tenantId });
  if (error) {
    throw new TenantDashboardQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseTenantDashboard(row));
}

/** A single dashboard by id -- returns null (never an error) when it does not exist or RLS hides it. */
export async function getTenantDashboardById(client: TenantDashboardQueryTableClient, dashboardId: string): Promise<TenantDashboard | null> {
  const { data, error } = await client.rpc("get_tenant_dashboard_by_id", { p_dashboard_id: dashboardId });
  if (error) {
    throw new TenantDashboardQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row) {
    return null;
  }
  return parseTenantDashboard(row as Record<string, unknown>);
}

/** The full append-only version history for one dashboard, newest first. */
export async function listTenantDashboardVersions(client: TenantDashboardQueryTableClient, dashboardId: string): Promise<TenantDashboardVersion[]> {
  const { data, error } = await client.rpc("list_tenant_dashboard_versions", { p_dashboard_id: dashboardId });
  if (error) {
    throw new TenantDashboardQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseTenantDashboardVersion(row));
}

/** A single dashboard version by id -- returns null (never an error) when it does not exist. */
export async function getTenantDashboardVersionById(client: TenantDashboardQueryTableClient, versionId: string): Promise<TenantDashboardVersion | null> {
  const { data, error } = await client.rpc("get_tenant_dashboard_version_by_id", { p_version_id: versionId });
  if (error) {
    throw new TenantDashboardQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row) {
    return null;
  }
  return parseTenantDashboardVersion(row as Record<string, unknown>);
}

/** The widgets bound to one dashboard version, in display order. */
export async function listDashboardWidgets(client: TenantDashboardQueryTableClient, dashboardVersionId: string): Promise<TenantDashboardWidget[]> {
  const { data, error } = await client.rpc("list_dashboard_widgets", { p_dashboard_version_id: dashboardVersionId });
  if (error) {
    throw new TenantDashboardQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseTenantDashboardWidget(row));
}
