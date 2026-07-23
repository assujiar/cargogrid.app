/**
 * RFQ and Costing Request contract (COM-148, CG-S7-COM-007). Mirrors
 * supabase/migrations/20260724090000_create_commercial_costing_request.sql's
 * app.costing_requests/app.costing_request_components/app.costing_responses/
 * app.costing_response_components/app.costing_responses_directory shape and their RPCs.
 */

import { z } from "zod";

export const COSTING_REQUEST_STATUSES = ["pending", "assigned", "responded", "cancelled", "superseded"] as const;
export const CostingRequestStatusSchema = z.enum(COSTING_REQUEST_STATUSES);
export type CostingRequestStatus = z.infer<typeof CostingRequestStatusSchema>;

export const COSTING_RESPONSE_SOURCE_TYPES = ["internal", "vendor"] as const;
export const CostingResponseSourceTypeSchema = z.enum(COSTING_RESPONSE_SOURCE_TYPES);
export type CostingResponseSourceType = z.infer<typeof CostingResponseSourceTypeSchema>;

export const RequirementsSnapshotSchema = z.object({
  serviceType: z.string().nullable().optional(),
  cargoDescription: z.string().nullable().optional(),
  origin: z.string().nullable().optional(),
  destination: z.string().nullable().optional(),
  targetReadyDate: z.string().nullable().optional(),
  specialInstructions: z.string().nullable().optional(),
});
export type RequirementsSnapshot = z.infer<typeof RequirementsSnapshotSchema>;

function parseRequirementsSnapshot(raw: unknown): RequirementsSnapshot {
  const row = (raw ?? {}) as Record<string, unknown>;
  return RequirementsSnapshotSchema.parse({
    serviceType: row.service_type ?? null,
    cargoDescription: row.cargo_description ?? null,
    origin: row.origin ?? null,
    destination: row.destination ?? null,
    targetReadyDate: row.target_ready_date ?? null,
    specialInstructions: row.special_instructions ?? null,
  });
}

export const CostingRequestSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  opportunityId: z.string().uuid(),
  sourceOpportunityVersion: z.number().int().positive(),
  requirementsSnapshot: RequirementsSnapshotSchema,
  status: CostingRequestStatusSchema,
  dueAt: z.string().nullable(),
  assigneeUserId: z.string().uuid().nullable(),
  cancelReason: z.string().nullable(),
  revisedFromId: z.string().uuid().nullable(),
  ownerUserId: z.string().uuid().nullable(),
  orgUnitId: z.string().uuid().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type CostingRequest = z.infer<typeof CostingRequestSchema>;

export const CostingRequestComponentSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  costingRequestId: z.string().uuid(),
  componentCode: z.string(),
  description: z.string().nullable(),
  quantity: z.coerce.number().nonnegative().nullable(),
  unit: z.string().nullable(),
  createdAt: z.string(),
});
export type CostingRequestComponent = z.infer<typeof CostingRequestComponentSchema>;

export const CostingResponseSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  costingRequestId: z.string().uuid(),
  sourceType: CostingResponseSourceTypeSchema,
  vendorRef: z.string().nullable(),
  currency: z.string().nullable(),
  totalAmount: z.coerce.number().nonnegative().nullable(),
  costMasked: z.boolean().nullable().optional(),
  effectiveAt: z.string(),
  expiryAt: z.string().nullable(),
  isExpired: z.boolean().nullable().optional(),
  submittedBy: z.string().nullable(),
  createdAt: z.string(),
});
export type CostingResponse = z.infer<typeof CostingResponseSchema>;

export const CostingResponseComponentSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  costingResponseId: z.string().uuid(),
  costingRequestComponentId: z.string().uuid(),
  amount: z.coerce.number().nonnegative(),
  createdAt: z.string(),
});
export type CostingResponseComponent = z.infer<typeof CostingResponseComponentSchema>;

export const RequestComponentInputSchema = z.object({
  code: z.string().min(1),
  description: z.string().nullable().optional(),
  quantity: z.number().nonnegative().nullable().optional(),
  unit: z.string().nullable().optional(),
});
export type RequestComponentInput = z.input<typeof RequestComponentInputSchema>;

export const RequestCostingInputSchema = z.object({
  opportunityId: z.string().uuid(),
  components: z.array(RequestComponentInputSchema).default([]),
  dueAt: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  createdBy: z.string().min(1),
});
export type RequestCostingInput = z.input<typeof RequestCostingInputSchema>;

export const AssignCostingRequestInputSchema = z.object({
  requestId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  assigneeUserId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type AssignCostingRequestInput = z.input<typeof AssignCostingRequestInputSchema>;

export const ResponseComponentInputSchema = z.object({
  requestComponentId: z.string().uuid(),
  amount: z.number().nonnegative(),
});
export type ResponseComponentInput = z.input<typeof ResponseComponentInputSchema>;

export const SubmitCostingResponseInputSchema = z.object({
  requestId: z.string().uuid(),
  sourceType: CostingResponseSourceTypeSchema,
  vendorRef: z.string().nullable().default(null),
  currency: z.string().regex(/^[A-Z]{3}$/),
  effectiveAt: z.string().nullable().default(null),
  expiryAt: z.string().nullable().default(null),
  components: z.array(ResponseComponentInputSchema).min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SubmitCostingResponseInput = z.input<typeof SubmitCostingResponseInputSchema>;

export const ReviseCostingRequestInputSchema = z.object({
  requestId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  createdBy: z.string().min(1),
});
export type ReviseCostingRequestInput = z.input<typeof ReviseCostingRequestInputSchema>;

export const CancelCostingRequestInputSchema = z.object({
  requestId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CancelCostingRequestInput = z.input<typeof CancelCostingRequestInputSchema>;

/** Maps a raw app.costing_requests row (snake_case) to this contract's camelCase shape. */
export function parseCostingRequest(row: Record<string, unknown>): CostingRequest {
  return CostingRequestSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    opportunityId: row.opportunity_id,
    sourceOpportunityVersion: row.source_opportunity_version,
    requirementsSnapshot: parseRequirementsSnapshot(row.requirements_snapshot),
    status: row.status,
    dueAt: row.due_at,
    assigneeUserId: row.assignee_user_id,
    cancelReason: row.cancel_reason,
    revisedFromId: row.revised_from_id,
    ownerUserId: row.owner_user_id,
    orgUnitId: row.org_unit_id,
    recordVersion: row.record_version,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Maps a raw app.costing_request_components row (snake_case) to this contract's camelCase shape. */
export function parseCostingRequestComponent(row: Record<string, unknown>): CostingRequestComponent {
  return CostingRequestComponentSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    costingRequestId: row.costing_request_id,
    componentCode: row.component_code,
    description: row.description,
    quantity: row.quantity,
    unit: row.unit,
    createdAt: row.created_at,
  });
}

/** Maps a raw app.costing_responses/app.costing_responses_directory row (snake_case) to this contract's camelCase shape. */
export function parseCostingResponse(row: Record<string, unknown>): CostingResponse {
  return CostingResponseSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    costingRequestId: row.costing_request_id,
    sourceType: row.source_type,
    vendorRef: row.vendor_ref,
    currency: row.currency,
    totalAmount: row.total_amount,
    costMasked: row.cost_masked ?? null,
    effectiveAt: row.effective_at,
    expiryAt: row.expiry_at,
    isExpired: row.is_expired ?? null,
    submittedBy: row.submitted_by,
    createdAt: row.created_at,
  });
}

/** Maps a raw app.costing_response_components row (snake_case) to this contract's camelCase shape. */
export function parseCostingResponseComponent(row: Record<string, unknown>): CostingResponseComponent {
  return CostingResponseComponentSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    costingResponseId: row.costing_response_id,
    costingRequestComponentId: row.costing_request_component_id,
    amount: row.amount,
    createdAt: row.created_at,
  });
}
