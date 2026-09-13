/**
 * Document Requirement read queries (OPS-176, CG-S8-OPS-010). Thin, typed wrappers
 * around app.get_shipment_document_checklist / app.evaluate_shipment_document_checklist_completeness
 * plus app.list_document_requirement_definitions (RPC, SECURITY DEFINER, explicit
 * actor + RULE A -- O1 remediation, cluster 5).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseChecklistItemView,
  parseChecklistCompleteness,
  parseDocumentRequirementDefinition,
  GetShipmentDocumentChecklistInputSchema,
  type ChecklistItemView,
  type ChecklistCompleteness,
  type DocumentRequirementDefinition,
  type GetShipmentDocumentChecklistInput,
} from "../contracts/document-requirement/document-requirement.ts";

export type DocumentRequirementQueryClient = Pick<SupabaseClient, "rpc">;

export class DocumentRequirementQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "DocumentRequirementQueryError";
  }
}

/** Authority-gated (OPS:View + record scope) live checklist read -- effective_status is computed fresh from review_status/expires_at/the linked file's own current scan status. */
export async function getShipmentDocumentChecklist(
  client: DocumentRequirementQueryClient,
  input: GetShipmentDocumentChecklistInput,
): Promise<ChecklistItemView[]> {
  const parsedInput = GetShipmentDocumentChecklistInputSchema.parse(input);
  const { data, error } = await client.rpc("get_shipment_document_checklist", {
    p_shipment_order_id: parsedInput.shipmentOrderId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
  });
  if (error) {
    throw new DocumentRequirementQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new DocumentRequirementQueryError("get_shipment_document_checklist returned a non-array result");
  }
  return data.map((row: Record<string, unknown>) => parseChecklistItemView(row));
}

/** Pure, side-effect-free completeness evaluation -- the disclosed forward seam ePOD (OPS-177) and Billing Readiness (OPS-181) call. */
export async function evaluateShipmentDocumentChecklistCompleteness(
  client: DocumentRequirementQueryClient,
  input: GetShipmentDocumentChecklistInput,
): Promise<ChecklistCompleteness> {
  const parsedInput = GetShipmentDocumentChecklistInputSchema.parse(input);
  const { data, error } = await client.rpc("evaluate_shipment_document_checklist_completeness", {
    p_shipment_order_id: parsedInput.shipmentOrderId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
  });
  if (error) {
    throw new DocumentRequirementQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new DocumentRequirementQueryError("evaluate_shipment_document_checklist_completeness returned no row");
  }
  return parseChecklistCompleteness(row as Record<string, unknown>);
}

export interface ListDocumentRequirementDefinitionsInput {
  readonly tenantId: string;
  readonly actorAuthUserId: string;
  readonly status?: "draft" | "published" | "archived";
}

/** Tenant-membership-gated read (app.document_requirement_definitions_select_scoped's current predicate, reproduced by app.list_document_requirement_definitions) -- broadly readable within the tenant, mirrors app.exception_sla_policy_versions' own read shape. */
export async function listDocumentRequirementDefinitions(
  client: DocumentRequirementQueryClient,
  input: ListDocumentRequirementDefinitionsInput,
): Promise<DocumentRequirementDefinition[]> {
  const { data, error } = await client.rpc("list_document_requirement_definitions", {
    p_tenant_id: input.tenantId,
    p_actor_auth_user_id: input.actorAuthUserId,
    p_status: input.status ?? null,
  });
  if (error) {
    throw new DocumentRequirementQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseDocumentRequirementDefinition(row));
}
