/**
 * Tracking entitlement and tenant source policy read queries (ATW-226A,
 * CG-S10-ATW-006's own child). Thin, typed wrappers around
 * app.resolve_tenant_tracking_package / app.is_shipment_tracking_entitled /
 * app.resolve_tenant_tracking_source_policy
 * (supabase/migrations/20260729340000_create_advanced_tms_tracking_entitlement_source_policy.sql),
 * plus a direct RLS-scoped read of the raw app.tenant_tracking_source_policies row for
 * callers that need to know whether an explicit row exists at all (e.g. an edit form
 * pre-fill) rather than the always-present resolved-with-defaults shape.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseTrackingPackageResolution,
  parseTenantTrackingSourcePolicy,
  parseResolvedTenantTrackingSourcePolicy,
  type TrackingPackageResolution,
  type TenantTrackingSourcePolicy,
  type ResolvedTenantTrackingSourcePolicy,
} from "../contracts/tracking-source-policy/tracking-source-policy.ts";

export type TrackingSourcePolicyQueryClient = Pick<SupabaseClient, "from" | "rpc">;

export class TrackingSourcePolicyQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "TrackingSourcePolicyQueryError";
  }
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

/** The single tracking-package resolution point (Configuration Engine, PLT-121) -- always resolves, enabled=false with every other field null when no package was ever assigned. */
export async function resolveTenantTrackingPackage(client: TrackingSourcePolicyQueryClient, tenantId: string): Promise<TrackingPackageResolution> {
  const { data, error } = await client.rpc("resolve_tenant_tracking_package", { p_tenant_id: tenantId });
  if (error) {
    throw new TrackingSourcePolicyQueryError(error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new TrackingSourcePolicyQueryError("resolve_tenant_tracking_package returned no row");
  }
  return parseTrackingPackageResolution(row);
}

/** Real per-tenant entitlement check, replacing ATW-222's always-false stub. */
export async function isShipmentTrackingEntitled(client: TrackingSourcePolicyQueryClient, tenantId: string): Promise<boolean> {
  const { data, error } = await client.rpc("is_shipment_tracking_entitled", { p_tenant_id: tenantId });
  if (error) {
    throw new TrackingSourcePolicyQueryError(error.message);
  }
  if (typeof data !== "boolean") {
    throw new TrackingSourcePolicyQueryError("is_shipment_tracking_entitled returned a non-boolean result");
  }
  return data;
}

/** Always resolves -- explicit tenant override when one exists, otherwise the disclosed system default (isExplicit=false). This is what ATW-223's per-vehicle source-priority fallback and every later ATW-226 child should read. */
export async function resolveTenantTrackingSourcePolicy(client: TrackingSourcePolicyQueryClient, tenantId: string): Promise<ResolvedTenantTrackingSourcePolicy> {
  const { data, error } = await client.rpc("resolve_tenant_tracking_source_policy", { p_tenant_id: tenantId });
  if (error) {
    throw new TrackingSourcePolicyQueryError(error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new TrackingSourcePolicyQueryError("resolve_tenant_tracking_source_policy returned no row");
  }
  return parseResolvedTenantTrackingSourcePolicy(row);
}

/** The raw explicit policy row for one tenant, or null when the tenant has never set one (use resolveTenantTrackingSourcePolicy when a default fallback is acceptable -- this is for admin-form pre-fill, which needs to distinguish "never set" from "set to the same values as the default"). */
export async function getTenantTrackingSourcePolicy(client: TrackingSourcePolicyQueryClient, tenantId: string): Promise<TenantTrackingSourcePolicy | null> {
  const { data, error } = await client.from("tenant_tracking_source_policies").select("*").eq("tenant_id", tenantId).maybeSingle();
  if (error) {
    throw new TrackingSourcePolicyQueryError(error.message);
  }
  return data ? parseTenantTrackingSourcePolicy(data as Record<string, unknown>) : null;
}
