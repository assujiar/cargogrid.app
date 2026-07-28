/**
 * Document Requirement contract (OPS-176, CG-S8-OPS-010). Mirrors
 * supabase/migrations/20260728090000_create_operations_document_requirement.sql's
 * app.document_requirement_definitions/app.shipment_document_checklist_items/
 * app.document_checklist_events shapes and their RPCs.
 *
 * Versioned document requirements (by mode/service/status/party) plus a pinned
 * per-shipment checklist and a private link/review lifecycle layered on top of the
 * Platform Document/File Engine (PLT-128) -- this capability never re-implements file
 * storage, malware scanning, or the signed-URL access gate.
 */

import { z } from "zod";

export const DocumentRequirementDefinitionSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  mode: z.enum(["land", "air", "sea"]).nullable(),
  serviceType: z.string().nullable(),
  applicableStatus: z.enum(["draft", "confirmed", "planned", "assigned", "dispatched", "in_transit", "delivered", "epod", "closed"]),
  party: z.enum(["shipper", "carrier", "consignee", "ops"]),
  documentTypeCode: z.string(),
  criticality: z.enum(["mandatory", "optional"]),
  status: z.enum(["draft", "published", "archived"]),
  supersedesVersionId: z.string().uuid().nullable(),
  recordVersion: z.number().int(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type DocumentRequirementDefinition = z.infer<typeof DocumentRequirementDefinitionSchema>;

export function parseDocumentRequirementDefinition(row: Record<string, unknown>): DocumentRequirementDefinition {
  return DocumentRequirementDefinitionSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    mode: row.mode ?? null,
    serviceType: row.service_type ?? null,
    applicableStatus: row.applicable_status,
    party: row.party,
    documentTypeCode: row.document_type_code,
    criticality: row.criticality,
    status: row.status,
    supersedesVersionId: row.supersedes_version_id ?? null,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const ShipmentDocumentChecklistItemSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  shipmentOrderId: z.string().uuid(),
  requirementDefinitionId: z.string().uuid(),
  party: z.enum(["shipper", "carrier", "consignee", "ops"]),
  documentTypeCode: z.string(),
  criticality: z.enum(["mandatory", "optional"]),
  fileId: z.string().uuid().nullable(),
  reviewStatus: z.enum(["pending", "approved", "rejected"]),
  reviewedByAuthUserId: z.string().uuid().nullable(),
  reviewedAt: z.string().nullable(),
  reviewNotes: z.string().nullable(),
  expiresAt: z.string().nullable(),
  pinnedAt: z.string(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type ShipmentDocumentChecklistItem = z.infer<typeof ShipmentDocumentChecklistItemSchema>;

export function parseShipmentDocumentChecklistItem(row: Record<string, unknown>): ShipmentDocumentChecklistItem {
  return ShipmentDocumentChecklistItemSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    shipmentOrderId: row.shipment_order_id,
    requirementDefinitionId: row.requirement_definition_id,
    party: row.party,
    documentTypeCode: row.document_type_code,
    criticality: row.criticality,
    fileId: row.file_id ?? null,
    reviewStatus: row.review_status,
    reviewedByAuthUserId: row.reviewed_by_auth_user_id ?? null,
    reviewedAt: row.reviewed_at ?? null,
    reviewNotes: row.review_notes ?? null,
    expiresAt: row.expires_at ?? null,
    pinnedAt: row.pinned_at,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** app.get_shipment_document_checklist's own row shape -- the checklist item plus a live-computed effective_status, never a stored fourth column. */
export const ChecklistItemViewSchema = z.object({
  id: z.string().uuid(),
  requirementDefinitionId: z.string().uuid(),
  party: z.enum(["shipper", "carrier", "consignee", "ops"]),
  documentTypeCode: z.string(),
  criticality: z.enum(["mandatory", "optional"]),
  fileId: z.string().uuid().nullable(),
  malwareScanStatus: z.enum(["pending", "clean", "infected", "error"]).nullable(),
  reviewStatus: z.enum(["pending", "approved", "rejected"]),
  reviewedByAuthUserId: z.string().uuid().nullable(),
  reviewedAt: z.string().nullable(),
  reviewNotes: z.string().nullable(),
  expiresAt: z.string().nullable(),
  effectiveStatus: z.enum(["missing", "pending_review", "approved", "rejected", "expired"]),
});
export type ChecklistItemView = z.infer<typeof ChecklistItemViewSchema>;

export function parseChecklistItemView(row: Record<string, unknown>): ChecklistItemView {
  return ChecklistItemViewSchema.parse({
    id: row.id,
    requirementDefinitionId: row.requirement_definition_id,
    party: row.party,
    documentTypeCode: row.document_type_code,
    criticality: row.criticality,
    fileId: row.file_id ?? null,
    malwareScanStatus: row.malware_scan_status ?? null,
    reviewStatus: row.review_status,
    reviewedByAuthUserId: row.reviewed_by_auth_user_id ?? null,
    reviewedAt: row.reviewed_at ?? null,
    reviewNotes: row.review_notes ?? null,
    expiresAt: row.expires_at ?? null,
    effectiveStatus: row.effective_status,
  });
}

export const ChecklistCompletenessSchema = z.object({
  isComplete: z.boolean(),
  missingMandatory: z.array(
    z.object({
      checklistItemId: z.string().uuid(),
      documentTypeCode: z.string(),
      party: z.enum(["shipper", "carrier", "consignee", "ops"]),
    }),
  ),
});
export type ChecklistCompleteness = z.infer<typeof ChecklistCompletenessSchema>;

export function parseChecklistCompleteness(row: Record<string, unknown>): ChecklistCompleteness {
  const missing = (row.missing_mandatory as Array<Record<string, unknown>>) ?? [];
  return ChecklistCompletenessSchema.parse({
    isComplete: row.is_complete,
    missingMandatory: missing.map((m) => ({
      checklistItemId: m.checklist_item_id,
      documentTypeCode: m.document_type_code,
      party: m.party,
    })),
  });
}

export const CreateDocumentRequirementDraftInputSchema = z.object({
  tenantId: z.string().uuid(),
  mode: z.enum(["land", "air", "sea"]).nullable(),
  serviceType: z.string().nullable(),
  applicableStatus: z.enum(["draft", "confirmed", "planned", "assigned", "dispatched", "in_transit", "delivered", "epod", "closed"]),
  party: z.enum(["shipper", "carrier", "consignee", "ops"]),
  documentTypeCode: z.string().min(1),
  criticality: z.enum(["mandatory", "optional"]),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CreateDocumentRequirementDraftInput = z.input<typeof CreateDocumentRequirementDraftInputSchema>;

export const PublishDocumentRequirementVersionInputSchema = z.object({
  versionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type PublishDocumentRequirementVersionInput = z.input<typeof PublishDocumentRequirementVersionInputSchema>;

export const PinShipmentDocumentChecklistInputSchema = z.object({
  shipmentOrderId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type PinShipmentDocumentChecklistInput = z.input<typeof PinShipmentDocumentChecklistInputSchema>;

export const LinkDocumentToChecklistItemInputSchema = z.object({
  checklistItemId: z.string().uuid(),
  fileId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type LinkDocumentToChecklistItemInput = z.input<typeof LinkDocumentToChecklistItemInputSchema>;

export const ReviewDocumentChecklistItemInputSchema = z.object({
  checklistItemId: z.string().uuid(),
  decision: z.enum(["approved", "rejected"]),
  notes: z.string().nullable().optional(),
  expiresAt: z.string().nullable().optional(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ReviewDocumentChecklistItemInput = z.input<typeof ReviewDocumentChecklistItemInputSchema>;

export const GetShipmentDocumentChecklistInputSchema = z.object({
  shipmentOrderId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
});
export type GetShipmentDocumentChecklistInput = z.input<typeof GetShipmentDocumentChecklistInputSchema>;
