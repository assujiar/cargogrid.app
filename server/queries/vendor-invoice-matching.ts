/**
 * Vendor Invoice Matching read queries (PRC-265, CG-S11-PRC-016). Thin, typed wrappers
 * around the dedicated read RPCs (supabase/migrations/20260730750000_create_
 * procurement_vendor_invoice_matching.sql) -- mirrors server/queries/vendor-contract.ts
 * exactly: every RPC already carries its own explicit evaluate_permission check plus
 * PRC:View cost field masking, so this file calls `.rpc(...)`, never `.from(...)`, on a
 * base table.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseVendorBillMatchTolerancePolicy,
  parseVendorBillMatchCase,
  parseVendorBillMatchLine,
  parseVendorBillMatchEvent,
  parseVendorBillMatchDispute,
  parseVendorBillMatchExceptionApproval,
  parseVendorBillMatchReadiness,
  parseVendorBillMatchReconciliationRow,
  type VendorBillMatchTolerancePolicy,
  type VendorBillMatchCase,
  type VendorBillMatchLine,
  type VendorBillMatchEvent,
  type VendorBillMatchDispute,
  type VendorBillMatchExceptionApproval,
  type VendorBillMatchReadiness,
  type VendorBillMatchReconciliationRow,
  type VendorBillMatchCaseStatus,
  type VendorBillMatchReadinessStatus,
} from "../contracts/vendor-invoice-matching/vendor-invoice-matching.ts";

export type VendorInvoiceMatchingQueryRpcClient = Pick<SupabaseClient, "rpc">;

export class VendorInvoiceMatchingQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "VendorInvoiceMatchingQueryError";
  }
}

const LIST_DEFAULT_LIMIT = 50;

export async function getActiveVendorBillMatchTolerancePolicy(client: VendorInvoiceMatchingQueryRpcClient, tenantId: string, actorAuthUserId: string): Promise<VendorBillMatchTolerancePolicy | null> {
  const { data, error } = await client.rpc("get_active_vendor_bill_match_tolerance_policy", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new VendorInvoiceMatchingQueryError(error.message);
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object" || row.id == null) return null;
  return parseVendorBillMatchTolerancePolicy(row as Record<string, unknown>);
}

export async function listVendorBillMatchTolerancePolicies(client: VendorInvoiceMatchingQueryRpcClient, tenantId: string, actorAuthUserId: string): Promise<VendorBillMatchTolerancePolicy[]> {
  const { data, error } = await client.rpc("list_vendor_bill_match_tolerance_policies", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new VendorInvoiceMatchingQueryError(error.message);
  return (data ?? []).map((row: Record<string, unknown>) => parseVendorBillMatchTolerancePolicy(row));
}

/** A single match case -- pass exactly one of matchCaseId (a specific version) or billId (the current version). */
export async function getVendorBillMatchCase(client: VendorInvoiceMatchingQueryRpcClient, lookup: { matchCaseId?: string; billId?: string }, actorAuthUserId: string): Promise<VendorBillMatchCase> {
  const { data, error } = await client.rpc("get_vendor_bill_match_case", { p_match_case_id: lookup.matchCaseId ?? null, p_bill_id: lookup.billId ?? null, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new VendorInvoiceMatchingQueryError(error.message);
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") throw new VendorInvoiceMatchingQueryError("get_vendor_bill_match_case returned no row");
  return parseVendorBillMatchCase(row as Record<string, unknown>);
}

export async function listVendorBillMatchCases(
  client: VendorInvoiceMatchingQueryRpcClient,
  tenantId: string,
  actorAuthUserId: string,
  filters: { vendorMasterId?: string | null; overallStatus?: VendorBillMatchCaseStatus | null; readinessStatus?: VendorBillMatchReadinessStatus | null; limit?: number } = {},
): Promise<VendorBillMatchCase[]> {
  const { data, error } = await client.rpc("list_vendor_bill_match_cases", {
    p_tenant_id: tenantId,
    p_vendor_master_id: filters.vendorMasterId ?? null,
    p_overall_status: filters.overallStatus ?? null,
    p_readiness_status: filters.readinessStatus ?? null,
    p_actor_auth_user_id: actorAuthUserId,
    p_limit: filters.limit ?? LIST_DEFAULT_LIMIT,
  });
  if (error) throw new VendorInvoiceMatchingQueryError(error.message);
  return (data ?? []).map((row: Record<string, unknown>) => parseVendorBillMatchCase(row));
}

export async function listVendorBillMatchCaseVersions(client: VendorInvoiceMatchingQueryRpcClient, billId: string, tenantId: string, actorAuthUserId: string): Promise<VendorBillMatchCase[]> {
  const { data, error } = await client.rpc("list_vendor_bill_match_case_versions", { p_bill_id: billId, p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new VendorInvoiceMatchingQueryError(error.message);
  return (data ?? []).map((row: Record<string, unknown>) => parseVendorBillMatchCase(row));
}

export async function listVendorBillMatchLines(client: VendorInvoiceMatchingQueryRpcClient, matchCaseId: string, actorAuthUserId: string): Promise<VendorBillMatchLine[]> {
  const { data, error } = await client.rpc("list_vendor_bill_match_lines", { p_match_case_id: matchCaseId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new VendorInvoiceMatchingQueryError(error.message);
  return (data ?? []).map((row: Record<string, unknown>) => parseVendorBillMatchLine(row));
}

export async function listVendorBillMatchCaseEvents(client: VendorInvoiceMatchingQueryRpcClient, matchCaseId: string, actorAuthUserId: string): Promise<VendorBillMatchEvent[]> {
  const { data, error } = await client.rpc("list_vendor_bill_match_case_events", { p_match_case_id: matchCaseId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new VendorInvoiceMatchingQueryError(error.message);
  return (data ?? []).map((row: Record<string, unknown>) => parseVendorBillMatchEvent(row));
}

export async function listVendorBillMatchDisputes(client: VendorInvoiceMatchingQueryRpcClient, matchCaseId: string, actorAuthUserId: string): Promise<VendorBillMatchDispute[]> {
  const { data, error } = await client.rpc("list_vendor_bill_match_disputes", { p_match_case_id: matchCaseId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new VendorInvoiceMatchingQueryError(error.message);
  return (data ?? []).map((row: Record<string, unknown>) => parseVendorBillMatchDispute(row));
}

export async function listVendorBillMatchExceptionApprovals(client: VendorInvoiceMatchingQueryRpcClient, matchCaseId: string, actorAuthUserId: string): Promise<VendorBillMatchExceptionApproval[]> {
  const { data, error } = await client.rpc("list_vendor_bill_match_exception_approvals", { p_match_case_id: matchCaseId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new VendorInvoiceMatchingQueryError(error.message);
  return (data ?? []).map((row: Record<string, unknown>) => parseVendorBillMatchExceptionApproval(row));
}

/** The clean, read-only Finance handoff surface -- gated on PRC:View OR FIN:View at the RPC layer. Returns an empty readiness shape (never throws not-found) when no case exists yet for the bill. */
export async function getVendorBillMatchReadiness(client: VendorInvoiceMatchingQueryRpcClient, billId: string, tenantId: string, actorAuthUserId: string): Promise<VendorBillMatchReadiness> {
  const { data, error } = await client.rpc("get_vendor_bill_match_readiness", { p_bill_id: billId, p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new VendorInvoiceMatchingQueryError(error.message);
  const row = Array.isArray(data) ? data[0] : data;
  return parseVendorBillMatchReadiness(billId, (row as Record<string, unknown> | null) ?? null);
}

export async function getVendorBillMatchReconciliationStatus(client: VendorInvoiceMatchingQueryRpcClient, tenantId: string, actorAuthUserId: string): Promise<VendorBillMatchReconciliationRow[]> {
  const { data, error } = await client.rpc("get_vendor_bill_match_reconciliation_status", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new VendorInvoiceMatchingQueryError(error.message);
  return (data ?? []).map((row: Record<string, unknown>) => parseVendorBillMatchReconciliationRow(row));
}
