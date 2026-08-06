/**
 * Vendor Compliance read queries (PRC-253, CG-S11-PRC-004). Thin, typed wrappers
 * around app.get_vendor_compliance_requirement/app.list_vendor_compliance_requirements/
 * app.get_vendor_compliance_document/app.list_vendor_compliance_documents/
 * app.list_vendor_compliance_document_versions/app.get_vendor_compliance_waiver/
 * app.list_vendor_compliance_waivers/app.get_vendor_compliance_eligibility/
 * app.list_tenant_vendor_compliance_matrix
 * (supabase/migrations/20260730600000_create_procurement_vendor_compliance.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseVendorComplianceRequirement,
  parseVendorComplianceDocument,
  parseVendorComplianceWaiver,
  parseVendorComplianceEligibilityRow,
  parseVendorComplianceMatrixRow,
  type VendorComplianceRequirement,
  type VendorComplianceDocument,
  type VendorComplianceWaiver,
  type VendorComplianceEligibilityRow,
  type VendorComplianceMatrixRow,
  type VendorComplianceRequirementStatus,
  type VendorComplianceWaiverStatus,
  type VendorComplianceStatusValue,
} from "../contracts/vendor-compliance/vendor-compliance.ts";

export type VendorComplianceQueryClient = Pick<SupabaseClient, "rpc">;

export class VendorComplianceQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "VendorComplianceQueryError";
  }
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

function rows(data: unknown): Record<string, unknown>[] {
  return (data as Record<string, unknown>[] | null) ?? [];
}

// --- Requirements ---

export async function getVendorComplianceRequirement(client: VendorComplianceQueryClient, requirementVersionId: string, actorAuthUserId: string): Promise<VendorComplianceRequirement> {
  const { data, error } = await client.rpc("get_vendor_compliance_requirement", { p_requirement_version_id: requirementVersionId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new VendorComplianceQueryError(error.message);
  const row = firstRow(data);
  if (!row) throw new VendorComplianceQueryError("get_vendor_compliance_requirement returned no row");
  return parseVendorComplianceRequirement(row);
}

export async function listVendorComplianceRequirements(
  client: VendorComplianceQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { statusFilter?: VendorComplianceRequirementStatus | null; vendorCategory?: string | null; serviceType?: string | null; requirementFamilyId?: string | null; limit?: number; afterId?: string | null },
): Promise<VendorComplianceRequirement[]> {
  const { data, error } = await client.rpc("list_vendor_compliance_requirements", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_status_filter: options?.statusFilter ?? null,
    p_vendor_category: options?.vendorCategory ?? null,
    p_service_type: options?.serviceType ?? null,
    p_requirement_family_id: options?.requirementFamilyId ?? null,
    p_limit: options?.limit ?? 50,
    p_after_id: options?.afterId ?? null,
  });
  if (error) throw new VendorComplianceQueryError(error.message);
  return rows(data).map(parseVendorComplianceRequirement);
}

// --- Documents ---

export async function getVendorComplianceDocument(client: VendorComplianceQueryClient, documentId: string, actorAuthUserId: string): Promise<VendorComplianceDocument> {
  const { data, error } = await client.rpc("get_vendor_compliance_document", { p_document_id: documentId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new VendorComplianceQueryError(error.message);
  const row = firstRow(data);
  if (!row) throw new VendorComplianceQueryError("get_vendor_compliance_document returned no row");
  return parseVendorComplianceDocument(row);
}

export async function listVendorComplianceDocuments(
  client: VendorComplianceQueryClient,
  vendorMasterRecordId: string,
  actorAuthUserId: string,
  options?: { requirementVersionId?: string | null; latestOnly?: boolean; limit?: number; afterId?: string | null },
): Promise<VendorComplianceDocument[]> {
  const { data, error } = await client.rpc("list_vendor_compliance_documents", {
    p_vendor_master_record_id: vendorMasterRecordId,
    p_actor_auth_user_id: actorAuthUserId,
    p_requirement_version_id: options?.requirementVersionId ?? null,
    p_latest_only: options?.latestOnly ?? true,
    p_limit: options?.limit ?? 100,
    p_after_id: options?.afterId ?? null,
  });
  if (error) throw new VendorComplianceQueryError(error.message);
  return rows(data).map(parseVendorComplianceDocument);
}

/** The document/version viewer's own data source -- full lineage for one compliance evidence slot, oldest to newest, proving renewal never deletes prior evidence. */
export async function listVendorComplianceDocumentVersions(client: VendorComplianceQueryClient, versionGroupId: string, actorAuthUserId: string): Promise<VendorComplianceDocument[]> {
  const { data, error } = await client.rpc("list_vendor_compliance_document_versions", { p_version_group_id: versionGroupId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new VendorComplianceQueryError(error.message);
  return rows(data).map(parseVendorComplianceDocument);
}

// --- Waivers ---

export async function getVendorComplianceWaiver(client: VendorComplianceQueryClient, waiverId: string, actorAuthUserId: string): Promise<VendorComplianceWaiver> {
  const { data, error } = await client.rpc("get_vendor_compliance_waiver", { p_waiver_id: waiverId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new VendorComplianceQueryError(error.message);
  const row = firstRow(data);
  if (!row) throw new VendorComplianceQueryError("get_vendor_compliance_waiver returned no row");
  return parseVendorComplianceWaiver(row);
}

export async function listVendorComplianceWaivers(
  client: VendorComplianceQueryClient,
  vendorMasterRecordId: string,
  actorAuthUserId: string,
  options?: { statusFilter?: VendorComplianceWaiverStatus | null; limit?: number; afterId?: string | null },
): Promise<VendorComplianceWaiver[]> {
  const { data, error } = await client.rpc("list_vendor_compliance_waivers", {
    p_vendor_master_record_id: vendorMasterRecordId,
    p_actor_auth_user_id: actorAuthUserId,
    p_status_filter: options?.statusFilter ?? null,
    p_limit: options?.limit ?? 50,
    p_after_id: options?.afterId ?? null,
  });
  if (error) throw new VendorComplianceQueryError(error.message);
  return rows(data).map(parseVendorComplianceWaiver);
}

// --- Eligibility / matrix ---

/** The downstream-composable read (Prompts 256+ own composition target) -- one row per requirement family tracked for this vendor. Never composed here. */
export async function getVendorComplianceEligibility(client: VendorComplianceQueryClient, vendorMasterRecordId: string, actorAuthUserId: string): Promise<VendorComplianceEligibilityRow[]> {
  const { data, error } = await client.rpc("get_vendor_compliance_eligibility", { p_vendor_master_record_id: vendorMasterRecordId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new VendorComplianceQueryError(error.message);
  return rows(data).map(parseVendorComplianceEligibilityRow);
}

/** The compliance matrix / expiring-soon-and-holds queue's own shared data source -- cursor-paginated, server-filtered. Pass statusFilter=['expiring_soon'|'expired'] or holdOnly=true for the reminders/holds queue view. */
export async function listTenantVendorComplianceMatrix(
  client: VendorComplianceQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { statusFilter?: VendorComplianceStatusValue | null; holdOnly?: boolean; vendorMasterRecordId?: string | null; limit?: number; afterId?: string | null },
): Promise<VendorComplianceMatrixRow[]> {
  const { data, error } = await client.rpc("list_tenant_vendor_compliance_matrix", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_status_filter: options?.statusFilter ?? null,
    p_hold_only: options?.holdOnly ?? false,
    p_vendor_master_record_id: options?.vendorMasterRecordId ?? null,
    p_limit: options?.limit ?? 100,
    p_after_id: options?.afterId ?? null,
  });
  if (error) throw new VendorComplianceQueryError(error.message);
  return rows(data).map(parseVendorComplianceMatrixRow);
}
