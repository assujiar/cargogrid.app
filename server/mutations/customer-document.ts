/**
 * Customer Document Center access primitive (CPL-308, CG-S13-CPL-010). Thin,
 * typed wrapper around app.get_customer_document (supabase/migrations/
 * 20260801090000_create_customer_portal_document_center.sql).
 *
 * Placed in mutations/, not queries/, mirroring server/mutations/
 * customer-epod.ts's own placement rationale exactly: conceptually a read,
 * but every call writes a durable app.file_access_logs/app.capture_audit_
 * event side effect (migration design decision 7), so it belongs alongside
 * this repository's other side-effecting "read" wrappers.
 *
 * The RPC itself never raises document_not_downloadable (migration design
 * decision 5) -- raising there would roll back the very app.file_access_logs
 * INSERT it just made, the moment this call propagates uncaught. The RPC
 * always returns a normal row once scope is established (with a real,
 * durably-logged granted/denied outcome already recorded); THIS function is
 * the one place that turns a non-"clean" malwareScanStatus into the
 * document_not_downloadable error external callers expect, deliberately
 * AFTER the RPC's own audit trail has already committed.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { parseCustomerDocument, type CustomerDocument } from "../contracts/customer-document/customer-document.ts";

export type CustomerDocumentMutationRpcClient = Pick<SupabaseClient, "rpc">;

const CUSTOMER_DOCUMENT_KNOWN_ERROR_CODES = ["document_not_found", "document_not_downloadable", "actor_identity_mismatch"] as const;
type KnownCustomerDocumentErrorCode = (typeof CUSTOMER_DOCUMENT_KNOWN_ERROR_CODES)[number];
export type CustomerDocumentMutationErrorCode = KnownCustomerDocumentErrorCode | "mutation_failed";

export class CustomerDocumentMutationError extends Error {
  readonly code: CustomerDocumentMutationErrorCode;

  constructor(message: string) {
    super(message);
    this.name = "CustomerDocumentMutationError";
    const prefix = message.split(":")[0]?.trim();
    this.code = (CUSTOMER_DOCUMENT_KNOWN_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownCustomerDocumentErrorCode) : "mutation_failed";
  }
}

/**
 * The scoped, audited per-document access ("download") action. Throws
 * document_not_found (anti-enumerating) whether documentId genuinely does
 * not exist, belongs to another tenant, is outside this identity's resolved
 * scope, or is a real file this capability does not compose at all (e.g. a
 * shipment_order-typed file not referenced by any completed ePOD capture,
 * migration design decision 4) -- the caller must not try to distinguish
 * these from the thrown error's own content.
 *
 * Throws document_not_downloadable for a real, in-scope document whose own
 * malwareScanStatus is not "clean" -- enforced HERE, at the service
 * boundary, not by the RPC itself (see this file's own header) -- this is
 * not a new disclosure (the caller's own prior listCustomerDocuments call
 * already showed this exact status), only a real, enforced refusal to treat
 * it as downloadable. The underlying RPC call has already durably recorded a
 * DENIED app.file_access_logs row for this exact attempt before this
 * function ever throws.
 *
 * Every call is a real, audited access attempt (migration design decision
 * 7) -- call it once per explicit customer-initiated "Download" action,
 * exactly like server/mutations/customer-epod.ts's own getCustomerEpod is
 * called once per "Download"/"Check again" click.
 */
export async function getCustomerDocument(client: CustomerDocumentMutationRpcClient, tenantId: string, actorAuthUserId: string, documentId: string): Promise<CustomerDocument> {
  const { data, error } = await client.rpc("get_customer_document", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_document_id: documentId,
  });
  if (error) {
    throw new CustomerDocumentMutationError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new CustomerDocumentMutationError("mutation_failed: get_customer_document returned no row");
  }
  const document = parseCustomerDocument(row as Record<string, unknown>);
  if (document.malwareScanStatus !== "clean") {
    throw new CustomerDocumentMutationError(`document_not_downloadable: document ${document.documentId} has not cleared malware scanning (status ${document.malwareScanStatus})`);
  }
  return document;
}
