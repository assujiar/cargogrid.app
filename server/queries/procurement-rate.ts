/**
 * Vendor Rate and Pricelist extension read queries (PRC-255, CG-S11-PRC-006). Thin,
 * typed wrappers around direct RLS-scoped selects against the new
 * app.vendor_rate_tiers_directory masked view (PRC:View cost gated, ADR-0020) and
 * app.vendor_rate_versions_directory (COM-149, now carrying vendor_master_id/
 * lead_time_days/capacity_terms too -- server/queries/rate.ts's own
 * listRateVersionsForMasterRecord/getRateVersionById already read this same view and
 * pick those new columns up automatically via parseRateVersion... except
 * parseRateVersion (rate.ts) does not declare them, so this file adds its own
 * extended row shape rather than editing rate.ts's own contract).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { parseVendorRateTier, type VendorRateTier } from "../contracts/procurement-rate/procurement-rate.ts";

export type ProcurementRateQueryTableClient = Pick<SupabaseClient, "from">;

export class ProcurementRateQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ProcurementRateQueryError";
  }
}

/** Every tier for one rate version, ordered -- app.vendor_rate_tiers_directory is the read path (PRC:View cost masked), never the base table directly. */
export async function listVendorRateTiers(client: ProcurementRateQueryTableClient, rateVersionId: string): Promise<VendorRateTier[]> {
  const { data, error } = await client
    .from("vendor_rate_tiers_directory")
    .select("*")
    .eq("rate_version_id", rateVersionId)
    .order("tier_order", { ascending: true });
  if (error) {
    throw new ProcurementRateQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseVendorRateTier(row));
}

// PRC-255 §17 requires cursor pagination / no unbounded browser-loaded dataset.
// Neither function below previously bounded its result set (post-review fix) --
// the identical unbounded pattern pre-exists in COM-149's own
// server/queries/rate.ts, which this checkpoint does not touch, but that is not
// license to add two more unbounded instances of it. A hard LIMIT (not full
// cursor pagination -- out of scope for this fix pass, disclosed in
// docs/build-log/phase-06/PRC-255.md) keeps a single request bounded; a tenant
// with more rows than this needs a follow-up cursor-paginated query, tracked
// as a disclosed limitation rather than silently left unbounded.
const PROCUREMENT_RATE_LIST_LIMIT = 200;

/** Every rate version linked to ANY real Procurement vendor identity (ADR-0020), for one tenant -- the Procurement-side rate directory (COM-149's own app.v_active_vendor_rates browses all rates tenant-wide, approved-only; this is the Procurement-scoped, all-statuses equivalent). Bounded to the most recent PROCUREMENT_RATE_LIST_LIMIT rows. */
export async function listProcurementLinkedVendorRateVersions(client: ProcurementRateQueryTableClient, tenantId: string): Promise<Record<string, unknown>[]> {
  const { data, error } = await client
    .from("vendor_rate_versions_directory")
    .select("*")
    .eq("tenant_id", tenantId)
    .not("vendor_master_id", "is", null)
    .order("created_at", { ascending: false })
    .limit(PROCUREMENT_RATE_LIST_LIMIT);
  if (error) {
    throw new ProcurementRateQueryError(error.message);
  }
  return data ?? [];
}

/** Every rate version linked to a real Procurement vendor identity (ADR-0020), for one tenant -- reads the same app.vendor_rate_versions_directory server/queries/rate.ts uses, filtered on the new vendor_master_id column. Bounded to the most recent PROCUREMENT_RATE_LIST_LIMIT rows. */
export async function listVendorRateVersionsForVendor(
  client: ProcurementRateQueryTableClient,
  tenantId: string,
  vendorMasterId: string,
): Promise<Record<string, unknown>[]> {
  const { data, error } = await client
    .from("vendor_rate_versions_directory")
    .select("*")
    .eq("tenant_id", tenantId)
    .eq("vendor_master_id", vendorMasterId)
    .order("created_at", { ascending: false })
    .limit(PROCUREMENT_RATE_LIST_LIMIT);
  if (error) {
    throw new ProcurementRateQueryError(error.message);
  }
  return data ?? [];
}
