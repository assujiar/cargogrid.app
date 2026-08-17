/**
 * Customer ePOD access primitive (CPL-307, CG-S13-CPL-009, Prompt 307). Thin,
 * typed wrapper around the one RPC in supabase/migrations/20260801080000_
 * create_customer_portal_epod_access.sql, app.get_customer_epod.
 *
 * Placed in mutations/, not queries/, mirroring server/mutations/vendor-
 * compliance.ts's own accessVendorComplianceDocumentEvidence (the closest
 * real precedent in this repository): conceptually a read, but every call
 * writes a durable app.file_access_logs/app.capture_audit_event side effect
 * (migration design decision 3), so it belongs alongside this repository's
 * other side-effecting "read" wrappers, not the pure queries/ directory.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { parseCustomerEpod, type CustomerEpod } from "../contracts/customer-epod/customer-epod.ts";

export type CustomerEpodMutationRpcClient = Pick<SupabaseClient, "rpc">;

const CUSTOMER_EPOD_KNOWN_ERROR_CODES = ["record_not_found", "actor_identity_mismatch"] as const;
type KnownCustomerEpodErrorCode = (typeof CUSTOMER_EPOD_KNOWN_ERROR_CODES)[number];
export type CustomerEpodErrorCode = KnownCustomerEpodErrorCode | "mutation_failed";

export class CustomerEpodMutationError extends Error {
  readonly code: CustomerEpodErrorCode;

  constructor(message: string) {
    super(message);
    this.name = "CustomerEpodMutationError";
    const prefix = message.split(":")[0]?.trim();
    this.code = (CUSTOMER_EPOD_KNOWN_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownCustomerEpodErrorCode) : "mutation_failed";
  }
}

/**
 * The customer-safe ePOD projection for one shipment order -- status plus
 * (when available) evidence file metadata. Throws record_not_found
 * (anti-enumerating) whether the shipment order genuinely does not exist,
 * belongs to another tenant, or exists but is outside this identity's
 * resolved scope -- the caller must not try to distinguish the three from
 * the thrown error's own content.
 *
 * Never throws for "not yet available" or "quarantined" -- both are real,
 * distinct `epodStatus` values on the returned row once scope is genuinely
 * established (migration design decision 4); only render logic should branch
 * on them, never error handling.
 *
 * Every call is a real, audited access attempt (migration design decision
 * 3) -- call it once per page render for the initial status, and again for
 * an explicit customer-initiated "Download"/"Check again" action, exactly
 * like server/mutations/vendor-compliance.ts's own accessVendorCompliance
 * DocumentEvidence is called once per "View evidence" click.
 */
export async function getCustomerEpod(client: CustomerEpodMutationRpcClient, tenantId: string, actorAuthUserId: string, shipmentOrderId: string): Promise<CustomerEpod> {
  const { data, error } = await client.rpc("get_customer_epod", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_shipment_order_id: shipmentOrderId,
  });
  if (error) {
    throw new CustomerEpodMutationError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new CustomerEpodMutationError("mutation_failed: get_customer_epod returned no row");
  }
  return parseCustomerEpod(row as Record<string, unknown>);
}
