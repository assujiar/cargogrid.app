/**
 * RFQ contract (PRC-257, CG-S11-PRC-008). Mirrors
 * supabase/migrations/20260730640000_create_procurement_rfq.sql -- Zod
 * schemas + parse functions for every entity (Rfq, RfqRequirementLine,
 * RfqInvitation, RfqClarification, RfqResponse, RfqResponseAttachment,
 * RfqEvent) plus one *InputSchema per mutation (camelCase field names,
 * actorAuthUserId/actorLabel/expectedVersion/idempotencyKey included where
 * the corresponding RPC needs them), the same shape
 * server/contracts/sourcing/sourcing.ts already establishes for this
 * checkpoint's own template.
 *
 * Rfq itself carries no cost-sensitive column (requirements_snapshot never
 * carries budget_amount -- design note 3 in the migration) -- there is no
 * "masked" vs "unmasked" shape to reconcile for Rfq the way sourcing.ts has
 * to for SourcingRequest. RfqResponse IS cost-sensitive (currency/
 * totalAmount/validityUntil/commercialTerms) -- parseRfqResponse normalizes
 * both the masked read-RPC shape (cost_masked present) and any future plain
 * shape into the same camelCase contract, defaulting costMasked to false
 * when absent.
 */

import { z } from "zod";

export const RFQ_STATUSES = ["draft", "issued", "closed", "cancelled", "superseded"] as const;
export const RfqStatusSchema = z.enum(RFQ_STATUSES);
export type RfqStatus = z.infer<typeof RfqStatusSchema>;

export const RFQ_INVITATION_STATUSES = ["invited", "declined", "no_response", "responded", "withdrawn"] as const;
export const RfqInvitationStatusSchema = z.enum(RFQ_INVITATION_STATUSES);
export type RfqInvitationStatus = z.infer<typeof RfqInvitationStatusSchema>;

export const RFQ_RESPONSE_STATUSES = ["submitted", "withdrawn"] as const;
export const RfqResponseStatusSchema = z.enum(RFQ_RESPONSE_STATUSES);
export type RfqResponseStatus = z.infer<typeof RfqResponseStatusSchema>;

export const RFQ_RESPONSE_CAPTURE_MODES = ["offline", "email"] as const;
export const RfqResponseCaptureModeSchema = z.enum(RFQ_RESPONSE_CAPTURE_MODES);
export type RfqResponseCaptureMode = z.infer<typeof RfqResponseCaptureModeSchema>;

export const RfqSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  orgUnitId: z.string().uuid().nullable(),
  sourcingRequestId: z.string().uuid(),
  rfqNumber: z.string(),
  version: z.number().int().positive(),
  revisedFromId: z.string().uuid().nullable(),
  requirementsSnapshot: z.record(z.string(), z.unknown()),
  serviceType: z.string(),
  mode: z.string().nullable(),
  originLane: z.string(),
  destinationLane: z.string(),
  cargoWeightMin: z.coerce.number().nullable(),
  cargoWeightMax: z.coerce.number().nullable(),
  cargoVolumeMin: z.coerce.number().nullable(),
  cargoVolumeMax: z.coerce.number().nullable(),
  currency: z.string().nullable(),
  status: RfqStatusSchema,
  issuedAt: z.string().nullable(),
  responseDeadlineAt: z.string().nullable(),
  closedAt: z.string().nullable(),
  closedReason: z.string().nullable(),
  ownerUserId: z.string().uuid().nullable(),
  idempotencyKey: z.string(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type Rfq = z.infer<typeof RfqSchema>;

export function parseRfq(row: Record<string, unknown>): Rfq {
  return RfqSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    orgUnitId: row.org_unit_id,
    sourcingRequestId: row.sourcing_request_id,
    rfqNumber: row.rfq_number,
    version: row.version,
    revisedFromId: row.revised_from_id,
    requirementsSnapshot: row.requirements_snapshot ?? {},
    serviceType: row.service_type,
    mode: row.mode,
    originLane: row.origin_lane,
    destinationLane: row.destination_lane,
    cargoWeightMin: row.cargo_weight_min,
    cargoWeightMax: row.cargo_weight_max,
    cargoVolumeMin: row.cargo_volume_min,
    cargoVolumeMax: row.cargo_volume_max,
    currency: row.currency,
    status: row.status,
    issuedAt: row.issued_at,
    responseDeadlineAt: row.response_deadline_at,
    closedAt: row.closed_at,
    closedReason: row.closed_reason,
    ownerUserId: row.owner_user_id,
    idempotencyKey: row.idempotency_key,
    recordVersion: row.record_version,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const RfqRequirementLineSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  rfqId: z.string().uuid(),
  lineNo: z.number().int().positive(),
  description: z.string(),
  quantity: z.coerce.number().nullable(),
  uom: z.string().nullable(),
  notes: z.string().nullable(),
  createdAt: z.string(),
});
export type RfqRequirementLine = z.infer<typeof RfqRequirementLineSchema>;

export function parseRfqRequirementLine(row: Record<string, unknown>): RfqRequirementLine {
  return RfqRequirementLineSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    rfqId: row.rfq_id,
    lineNo: row.line_no,
    description: row.description,
    quantity: row.quantity,
    uom: row.uom,
    notes: row.notes,
    createdAt: row.created_at,
  });
}

export const RfqInvitationSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  rfqId: z.string().uuid(),
  sourcingCandidateId: z.string().uuid(),
  vendorMasterId: z.string().uuid(),
  status: RfqInvitationStatusSchema,
  invitedAt: z.string(),
  invitedBy: z.string().nullable(),
  declineReason: z.string().nullable(),
  declinedAt: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type RfqInvitation = z.infer<typeof RfqInvitationSchema>;

export function parseRfqInvitation(row: Record<string, unknown>): RfqInvitation {
  return RfqInvitationSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    rfqId: row.rfq_id,
    sourcingCandidateId: row.sourcing_candidate_id,
    vendorMasterId: row.vendor_master_id,
    status: row.status,
    invitedAt: row.invited_at,
    invitedBy: row.invited_by,
    declineReason: row.decline_reason,
    declinedAt: row.declined_at,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const RfqClarificationSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  rfqId: z.string().uuid(),
  vendorMasterId: z.string().uuid().nullable(),
  question: z.string(),
  askedBy: z.string().nullable(),
  askedAt: z.string(),
  answer: z.string().nullable(),
  answeredBy: z.string().nullable(),
  answeredAt: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type RfqClarification = z.infer<typeof RfqClarificationSchema>;

export function parseRfqClarification(row: Record<string, unknown>): RfqClarification {
  return RfqClarificationSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    rfqId: row.rfq_id,
    vendorMasterId: row.vendor_master_id,
    question: row.question,
    askedBy: row.asked_by,
    askedAt: row.asked_at,
    answer: row.answer,
    answeredBy: row.answered_by,
    answeredAt: row.answered_at,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const RfqResponseSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  rfqId: z.string().uuid(),
  rfqInvitationId: z.string().uuid(),
  vendorMasterId: z.string().uuid(),
  version: z.number().int().positive(),
  previousVersionId: z.string().uuid().nullable(),
  status: RfqResponseStatusSchema,
  currency: z.string().nullable(),
  totalAmount: z.coerce.number().nullable(),
  validityUntil: z.string().nullable(),
  leadTimeDays: z.number().int().nullable(),
  commercialTerms: z.record(z.string(), z.unknown()),
  costMasked: z.boolean(),
  captureMode: RfqResponseCaptureModeSchema,
  sourceMessageRef: z.string().nullable(),
  receivedAt: z.string(),
  vendorConfirmed: z.boolean(),
  lateCapture: z.boolean(),
  lateReason: z.string().nullable(),
  comparisonEligible: z.boolean(),
  idempotencyKey: z.string(),
  actorAuthUserId: z.string().uuid().nullable(),
  actorLabel: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type RfqResponse = z.infer<typeof RfqResponseSchema>;

export function parseRfqResponse(row: Record<string, unknown>): RfqResponse {
  return RfqResponseSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    rfqId: row.rfq_id,
    rfqInvitationId: row.rfq_invitation_id,
    vendorMasterId: row.vendor_master_id,
    version: row.version,
    previousVersionId: row.previous_version_id,
    status: row.status,
    currency: row.currency,
    totalAmount: row.total_amount,
    validityUntil: row.validity_until,
    leadTimeDays: row.lead_time_days,
    commercialTerms: row.commercial_terms ?? {},
    costMasked: Boolean(row.cost_masked),
    captureMode: row.capture_mode,
    sourceMessageRef: row.source_message_ref,
    receivedAt: row.received_at,
    vendorConfirmed: row.vendor_confirmed,
    lateCapture: row.late_capture,
    lateReason: row.late_reason,
    comparisonEligible: row.comparison_eligible,
    idempotencyKey: row.idempotency_key,
    actorAuthUserId: row.actor_auth_user_id,
    actorLabel: row.actor_label,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const RfqResponseAttachmentSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  rfqResponseId: z.string().uuid(),
  fileId: z.string().uuid(),
  createdAt: z.string(),
});
export type RfqResponseAttachment = z.infer<typeof RfqResponseAttachmentSchema>;

export function parseRfqResponseAttachment(row: Record<string, unknown>): RfqResponseAttachment {
  return RfqResponseAttachmentSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    rfqResponseId: row.rfq_response_id,
    fileId: row.file_id,
    createdAt: row.created_at,
  });
}

export const RfqEventSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  rfqId: z.string().uuid(),
  fromStatus: z.string(),
  toStatus: z.string(),
  reason: z.string().nullable(),
  evidenceRef: z.string().nullable(),
  actorAuthUserId: z.string().uuid().nullable(),
  actorLabel: z.string().nullable(),
  occurredAt: z.string(),
});
export type RfqEvent = z.infer<typeof RfqEventSchema>;

export function parseRfqEvent(row: Record<string, unknown>): RfqEvent {
  return RfqEventSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    rfqId: row.rfq_id,
    fromStatus: row.from_status,
    toStatus: row.to_status,
    reason: row.reason,
    evidenceRef: row.evidence_ref,
    actorAuthUserId: row.actor_auth_user_id,
    actorLabel: row.actor_label,
    occurredAt: row.occurred_at,
  });
}

// -- Mutation inputs -------------------------------------------------------

export const DraftRfqFromSourcingInputSchema = z.object({
  tenantId: z.string().uuid(),
  sourcingRequestId: z.string().uuid(),
  ownerUserId: z.string().uuid().nullable().default(null),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type DraftRfqFromSourcingInput = z.input<typeof DraftRfqFromSourcingInputSchema>;

export const ReviseRfqInputSchema = z.object({
  rfqId: z.string().uuid(),
  cargoWeightMax: z.number().nonnegative().nullable().default(null),
  cargoVolumeMax: z.number().nonnegative().nullable().default(null),
  destinationLane: z.string().nullable().default(null),
  currency: z.string().nullable().default(null),
  reason: z.string().min(1),
  idempotencyKey: z.string().min(1),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ReviseRfqInput = z.input<typeof ReviseRfqInputSchema>;

export const IssueRfqInputSchema = z.object({
  rfqId: z.string().uuid(),
  responseDeadlineAt: z.string(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type IssueRfqInput = z.input<typeof IssueRfqInputSchema>;

export const InviteAdditionalRfqVendorInputSchema = z.object({
  rfqId: z.string().uuid(),
  sourcingCandidateId: z.string().uuid(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type InviteAdditionalRfqVendorInput = z.input<typeof InviteAdditionalRfqVendorInputSchema>;

export const ExtendRfqDeadlineInputSchema = z.object({
  rfqId: z.string().uuid(),
  newDeadlineAt: z.string(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ExtendRfqDeadlineInput = z.input<typeof ExtendRfqDeadlineInputSchema>;

export const CloseRfqForComparisonInputSchema = z.object({
  rfqId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CloseRfqForComparisonInput = z.input<typeof CloseRfqForComparisonInputSchema>;

export const CancelRfqInputSchema = z.object({
  rfqId: z.string().uuid(),
  reason: z.string().min(1),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CancelRfqInput = z.input<typeof CancelRfqInputSchema>;

export const DeclineRfqInvitationInputSchema = z.object({
  rfqInvitationId: z.string().uuid(),
  reason: z.string().min(1),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type DeclineRfqInvitationInput = z.input<typeof DeclineRfqInvitationInputSchema>;

export const RecordRfqClarificationInputSchema = z.object({
  rfqId: z.string().uuid(),
  vendorMasterId: z.string().uuid().nullable().default(null),
  question: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RecordRfqClarificationInput = z.input<typeof RecordRfqClarificationInputSchema>;

export const AnswerRfqClarificationInputSchema = z.object({
  clarificationId: z.string().uuid(),
  answer: z.string().min(1),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type AnswerRfqClarificationInput = z.input<typeof AnswerRfqClarificationInputSchema>;

export const SubmitRfqResponseInputSchema = z.object({
  rfqInvitationId: z.string().uuid(),
  currency: z.string().min(1),
  totalAmount: z.number().nonnegative(),
  validityUntil: z.string().nullable().default(null),
  leadTimeDays: z.number().int().nonnegative().nullable().default(null),
  commercialTerms: z.record(z.string(), z.unknown()).default({}),
  captureMode: RfqResponseCaptureModeSchema.default("offline"),
  sourceMessageRef: z.string().nullable().default(null),
  receivedAt: z.string(),
  vendorConfirmed: z.boolean().default(false),
  fileIds: z.array(z.string().uuid()).nullable().default(null),
  lateReason: z.string().nullable().default(null),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SubmitRfqResponseInput = z.input<typeof SubmitRfqResponseInputSchema>;

export const WithdrawRfqResponseInputSchema = z.object({
  rfqResponseId: z.string().uuid(),
  reason: z.string().min(1),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type WithdrawRfqResponseInput = z.input<typeof WithdrawRfqResponseInputSchema>;
