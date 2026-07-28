/**
 * Document Requirement mutation primitives (OPS-176, CG-S8-OPS-010). Thin, typed
 * wrappers around the RPCs in
 * supabase/migrations/20260728090000_create_operations_document_requirement.sql.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateDocumentRequirementDraftInputSchema,
  PublishDocumentRequirementVersionInputSchema,
  PinShipmentDocumentChecklistInputSchema,
  LinkDocumentToChecklistItemInputSchema,
  ReviewDocumentChecklistItemInputSchema,
  parseDocumentRequirementDefinition,
  parseShipmentDocumentChecklistItem,
  type CreateDocumentRequirementDraftInput,
  type PublishDocumentRequirementVersionInput,
  type PinShipmentDocumentChecklistInput,
  type LinkDocumentToChecklistItemInput,
  type ReviewDocumentChecklistItemInput,
  type DocumentRequirementDefinition,
  type ShipmentDocumentChecklistItem,
} from "../contracts/document-requirement/document-requirement.ts";
import { parseFile, type File as PlatformFile } from "../contracts/document/document.ts";

export interface UploadShipmentDocumentFileInput {
  readonly tenantId: string;
  readonly shipmentOrderId: string;
  readonly documentTypeCode: string;
  readonly originalFilename: string;
  readonly mimeType: string;
  readonly sizeBytes: number;
  readonly idempotencyKey: string;
  readonly actorAuthUserId: string;
  readonly actorLabel: string;
}

export type DocumentRequirementMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const DOCUMENT_REQUIREMENT_KNOWN_MUTATION_ERROR_CODES = [
  "document_requirement_unknown_document_type",
  "document_requirement_not_found",
  "concurrent_modification",
  "invalid_transition",
  "shipment_order_not_found",
  "document_checklist_item_not_found",
  "document_file_not_found",
  "document_checklist_cross_tenant",
  "document_checklist_record_mismatch",
  "document_checklist_type_mismatch",
  "document_checklist_file_deleted",
  "document_checklist_invalid_decision",
  "document_checklist_no_linked_file",
  "document_checklist_unsafe_file",
  "document_unsafe_filename",
  "document_type_not_configured",
  "document_mime_type_not_allowed",
  "document_file_too_large",
  "document_invalid_classification",
  "document_classification_too_weak",
  "insufficient_authority",
] as const;
type KnownDocumentRequirementMutationErrorCode = (typeof DOCUMENT_REQUIREMENT_KNOWN_MUTATION_ERROR_CODES)[number];
export type DocumentRequirementMutationErrorCode = KnownDocumentRequirementMutationErrorCode | "mutation_failed" | "invalid_response";

export class DocumentRequirementMutationError extends Error {
  readonly code: DocumentRequirementMutationErrorCode;

  constructor(code: DocumentRequirementMutationErrorCode, message: string) {
    super(message);
    this.name = "DocumentRequirementMutationError";
    this.code = code;
  }
}

function classifyError(message: string): DocumentRequirementMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (DOCUMENT_REQUIREMENT_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownDocumentRequirementMutationErrorCode)
    : "mutation_failed";
}

export async function createDocumentRequirementDraft(
  client: DocumentRequirementMutationRpcClient,
  input: CreateDocumentRequirementDraftInput,
): Promise<DocumentRequirementDefinition> {
  const parsedInput = CreateDocumentRequirementDraftInputSchema.parse(input);
  const { data, error } = await client.rpc("create_document_requirement_draft", {
    p_tenant_id: parsedInput.tenantId,
    p_mode: parsedInput.mode,
    p_service_type: parsedInput.serviceType,
    p_applicable_status: parsedInput.applicableStatus,
    p_party: parsedInput.party,
    p_document_type_code: parsedInput.documentTypeCode,
    p_criticality: parsedInput.criticality,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new DocumentRequirementMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new DocumentRequirementMutationError("invalid_response", "create_document_requirement_draft returned no row");
  }
  return parseDocumentRequirementDefinition(data as Record<string, unknown>);
}

export async function publishDocumentRequirementVersion(
  client: DocumentRequirementMutationRpcClient,
  input: PublishDocumentRequirementVersionInput,
): Promise<DocumentRequirementDefinition> {
  const parsedInput = PublishDocumentRequirementVersionInputSchema.parse(input);
  const { data, error } = await client.rpc("publish_document_requirement_version", {
    p_version_id: parsedInput.versionId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new DocumentRequirementMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new DocumentRequirementMutationError("invalid_response", "publish_document_requirement_version returned no row");
  }
  return parseDocumentRequirementDefinition(data as Record<string, unknown>);
}

/** Additive-only checklist sync -- returns the shipment's full pinned checklist (pre-existing rows included, never mutated). */
export async function pinShipmentDocumentChecklist(
  client: DocumentRequirementMutationRpcClient,
  input: PinShipmentDocumentChecklistInput,
): Promise<ShipmentDocumentChecklistItem[]> {
  const parsedInput = PinShipmentDocumentChecklistInputSchema.parse(input);
  const { data, error } = await client.rpc("pin_shipment_document_checklist", {
    p_shipment_order_id: parsedInput.shipmentOrderId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new DocumentRequirementMutationError(classifyError(error.message), error.message);
  }
  if (!Array.isArray(data)) {
    throw new DocumentRequirementMutationError("invalid_response", "pin_shipment_document_checklist returned a non-array result");
  }
  return data.map((row: Record<string, unknown>) => parseShipmentDocumentChecklistItem(row));
}

export async function linkDocumentToChecklistItem(
  client: DocumentRequirementMutationRpcClient,
  input: LinkDocumentToChecklistItemInput,
): Promise<ShipmentDocumentChecklistItem> {
  const parsedInput = LinkDocumentToChecklistItemInputSchema.parse(input);
  const { data, error } = await client.rpc("link_document_to_checklist_item", {
    p_checklist_item_id: parsedInput.checklistItemId,
    p_file_id: parsedInput.fileId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new DocumentRequirementMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new DocumentRequirementMutationError("invalid_response", "link_document_to_checklist_item returned no row");
  }
  return parseShipmentDocumentChecklistItem(data as Record<string, unknown>);
}

/**
 * Calls the Platform Document/File Engine's own app.initiate_file_upload (PLT-128) --
 * service_role-only (never granted to authenticated), so the caller must pass a
 * service-role client (lib/supabase/service-role.ts's createSupabaseServiceRoleClient),
 * the same "explicit actor, service-role execution" pattern
 * lib/portal/tenant-admin-guard-deps.server.ts already established for
 * app.resolve_access_context. record_type is always 'shipment_order' -- this wrapper
 * never uploads for any other record kind.
 */
export async function uploadShipmentDocumentFile(client: DocumentRequirementMutationRpcClient, input: UploadShipmentDocumentFileInput): Promise<PlatformFile> {
  const { data, error } = await client.rpc("initiate_file_upload", {
    p_tenant_id: input.tenantId,
    p_document_type_code: input.documentTypeCode,
    p_record_type: "shipment_order",
    p_record_id: input.shipmentOrderId,
    p_original_filename: input.originalFilename,
    p_mime_type: input.mimeType,
    p_size_bytes: input.sizeBytes,
    p_classification: null,
    p_legal_hold: false,
    p_legal_hold_reason: null,
    p_shared_org_unit_ids: [],
    p_customer_account_ref: null,
    p_idempotency_key: input.idempotencyKey,
    p_actor_auth_user_id: input.actorAuthUserId,
    p_actor_label: input.actorLabel,
  });
  if (error) {
    throw new DocumentRequirementMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new DocumentRequirementMutationError("invalid_response", "initiate_file_upload returned no row");
  }
  return parseFile(data as Record<string, unknown>);
}

/** approved requires the linked file to have already resolved to a clean malware scan (app.review_document_checklist_item's own document_checklist_unsafe_file gate). */
export async function reviewDocumentChecklistItem(
  client: DocumentRequirementMutationRpcClient,
  input: ReviewDocumentChecklistItemInput,
): Promise<ShipmentDocumentChecklistItem> {
  const parsedInput = ReviewDocumentChecklistItemInputSchema.parse(input);
  const { data, error } = await client.rpc("review_document_checklist_item", {
    p_checklist_item_id: parsedInput.checklistItemId,
    p_decision: parsedInput.decision,
    p_notes: parsedInput.notes ?? null,
    p_expires_at: parsedInput.expiresAt ?? null,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new DocumentRequirementMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new DocumentRequirementMutationError("invalid_response", "review_document_checklist_item returned no row");
  }
  return parseShipmentDocumentChecklistItem(data as Record<string, unknown>);
}
