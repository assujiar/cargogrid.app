/**
 * Vendor Assignment read queries (PRC-263, CG-S11-PRC-014). Thin, typed wrappers
 * around the dedicated read RPCs (supabase/migrations/
 * 20260730720000_create_procurement_vendor_assignment.sql) -- mirrors
 * server/queries/vendor-capacity.ts exactly: every RPC already carries its own
 * explicit evaluate_permission check, so this file calls `.rpc(...)`, never
 * `.from(...)`, on a base table.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseVendorAssignmentInvitation,
  VendorAssignmentEligibilityPreviewSchema,
  type VendorAssignmentInvitation,
  type VendorAssignmentInvitationStatus,
  type VendorAssignmentEligibilityPreview,
} from "../contracts/vendor-assignment/vendor-assignment.ts";

export type VendorAssignmentQueryRpcClient = Pick<SupabaseClient, "rpc">;

export class VendorAssignmentQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "VendorAssignmentQueryError";
  }
}

export async function getVendorAssignmentInvitation(client: VendorAssignmentQueryRpcClient, invitationId: string, actorAuthUserId: string): Promise<VendorAssignmentInvitation> {
  const { data, error } = await client.rpc("get_vendor_assignment_invitation", { p_invitation_id: invitationId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new VendorAssignmentQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new VendorAssignmentQueryError("get_vendor_assignment_invitation returned no row");
  }
  return parseVendorAssignmentInvitation(row as Record<string, unknown>);
}

export async function listVendorAssignmentInvitations(
  client: VendorAssignmentQueryRpcClient,
  tenantId: string,
  actorAuthUserId: string,
  shipmentOrderId: string | null = null,
  vendorMasterId: string | null = null,
  statusFilter: VendorAssignmentInvitationStatus | null = null,
  limit = 25,
): Promise<VendorAssignmentInvitation[]> {
  const { data, error } = await client.rpc("list_vendor_assignment_invitations", {
    p_tenant_id: tenantId,
    p_shipment_order_id: shipmentOrderId,
    p_vendor_master_id: vendorMasterId,
    p_status: statusFilter,
    p_actor_auth_user_id: actorAuthUserId,
    p_limit: limit,
  });
  if (error) {
    throw new VendorAssignmentQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseVendorAssignmentInvitation(row));
}

/** Best-effort preview only (migration comment on app.get_vendor_assignment_eligibility_preview) -- the real routing decision happens server-side inside app.propose_vendor_assignment_invitation itself regardless. */
export async function getVendorAssignmentEligibilityPreview(
  client: VendorAssignmentQueryRpcClient,
  tenantId: string,
  vendorMasterId: string,
  contractId: string | null,
  poId: string | null,
  capacityReservationId: string | null,
  actorAuthUserId: string,
): Promise<VendorAssignmentEligibilityPreview> {
  const { data, error } = await client.rpc("get_vendor_assignment_eligibility_preview", {
    p_tenant_id: tenantId,
    p_vendor_master_id: vendorMasterId,
    p_contract_id: contractId,
    p_po_id: poId,
    p_capacity_reservation_id: capacityReservationId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new VendorAssignmentQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new VendorAssignmentQueryError("get_vendor_assignment_eligibility_preview returned no row");
  }
  const record = row as Record<string, unknown>;
  return VendorAssignmentEligibilityPreviewSchema.parse({ eligible: record.eligible, reasons: record.reasons ?? [] });
}
