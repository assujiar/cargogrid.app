/**
 * Dashboard Builder read queries (IAE-003, Prompt 331). Thin, typed wrappers
 * around direct RLS-scoped selects on app.tenant_dashboards (tenant-wide
 * visibility, mirrors app.report_runs' own precedent), app.tenant_dashboard_versions
 * (append-only version history) and app.tenant_dashboard_widgets -- see
 * supabase/migrations/20260802020000_create_intelligence_dashboard_builder.sql's
 * own header.
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

export type TenantDashboardQueryTableClient = Pick<SupabaseClient, "from">;

export class TenantDashboardQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "TenantDashboardQueryError";
  }
}

/** Every dashboard for one tenant, most recently updated first -- RLS (tenant_dashboards_select_scoped) is the real scope gate. */
export async function listTenantDashboards(client: TenantDashboardQueryTableClient, tenantId: string): Promise<TenantDashboard[]> {
  const { data, error } = await client
    .from("tenant_dashboards")
    .select("*")
    .eq("tenant_id", tenantId)
    .order("updated_at", { ascending: false });
  if (error) {
    throw new TenantDashboardQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseTenantDashboard(row));
}

/** A single dashboard by id -- returns null (never an error) when it does not exist or RLS hides it. */
export async function getTenantDashboardById(client: TenantDashboardQueryTableClient, dashboardId: string): Promise<TenantDashboard | null> {
  const { data, error } = await client.from("tenant_dashboards").select("*").eq("id", dashboardId).maybeSingle();
  if (error) {
    throw new TenantDashboardQueryError(error.message);
  }
  if (!data) {
    return null;
  }
  return parseTenantDashboard(data as Record<string, unknown>);
}

/** The full append-only version history for one dashboard, newest first. */
export async function listTenantDashboardVersions(client: TenantDashboardQueryTableClient, dashboardId: string): Promise<TenantDashboardVersion[]> {
  const { data, error } = await client
    .from("tenant_dashboard_versions")
    .select("*")
    .eq("dashboard_id", dashboardId)
    .order("version_number", { ascending: false });
  if (error) {
    throw new TenantDashboardQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseTenantDashboardVersion(row));
}

/** A single dashboard version by id -- returns null (never an error) when it does not exist. */
export async function getTenantDashboardVersionById(client: TenantDashboardQueryTableClient, versionId: string): Promise<TenantDashboardVersion | null> {
  const { data, error } = await client.from("tenant_dashboard_versions").select("*").eq("id", versionId).maybeSingle();
  if (error) {
    throw new TenantDashboardQueryError(error.message);
  }
  if (!data) {
    return null;
  }
  return parseTenantDashboardVersion(data as Record<string, unknown>);
}

/** The widgets bound to one dashboard version, in display order. */
export async function listDashboardWidgets(client: TenantDashboardQueryTableClient, dashboardVersionId: string): Promise<TenantDashboardWidget[]> {
  const { data, error } = await client
    .from("tenant_dashboard_widgets")
    .select("*")
    .eq("dashboard_version_id", dashboardVersionId)
    .order("display_order", { ascending: true });
  if (error) {
    throw new TenantDashboardQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseTenantDashboardWidget(row));
}
