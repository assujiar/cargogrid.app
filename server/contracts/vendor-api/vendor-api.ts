/**
 * Vendor API contract (IAE-011, Prompt 339). Mirrors
 * supabase/migrations/20260804030000_create_intelligence_vendor_api.sql's
 * additive app.api_keys.vendor_master_record_id column and the
 * app.create_vendor_api_key / app.list_vendor_api_keys_for_tenant /
 * app.get_rfq_for_vendor_api / app.submit_rfq_response_via_vendor_api /
 * app.accept_vendor_assignment_invitation_via_vendor_api /
 * app.decline_vendor_assignment_invitation_via_vendor_api RPCs. Revoke/rotate
 * reuse ../api-key-webhook/api-key-webhook.ts's own
 * RevokeApiKeyInputSchema/RotateApiKeyInputSchema/revokeApiKey/rotateApiKey
 * directly (PLT-129, extended in-place by this migration) -- not
 * re-declared here. A vendor key is a DATA-scope binding, not an actor
 * identity -- there is no VendorApiKey.actorAuthUserId field, unlike
 * CustomerApiKey.customerActorAuthUserId, since no vendor auth.users
 * identity exists anywhere in this repository.
 */

import { z } from "zod";

export const VendorApiKeySchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  name: z.string(),
  keyPrefix: z.string(),
  scopes: z.array(z.string()),
  status: z.enum(["active", "revoked", "expired"]),
  rateLimitPerMinute: z.number().int().positive().nullable(),
  expiresAt: z.string().nullable(),
  lastUsedAt: z.string().nullable().optional(),
  createdAt: z.string(),
  updatedAt: z.string().optional(),
  vendorMasterRecordId: z.string().uuid(),
  vendorLegalName: z.string().optional(),
});
export type VendorApiKey = z.infer<typeof VendorApiKeySchema>;

export const CreatedVendorApiKeySchema = VendorApiKeySchema.omit({ vendorLegalName: true }).extend({ rawKey: z.string() });
export type CreatedVendorApiKey = z.infer<typeof CreatedVendorApiKeySchema>;

export const CreateVendorApiKeyInputSchema = z.object({
  tenantId: z.string().uuid(),
  vendorMasterRecordId: z.string().uuid(),
  name: z.string().min(1),
  expiresAt: z.string().nullable().default(null),
  rateLimitPerMinute: z.number().int().positive().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CreateVendorApiKeyInput = z.input<typeof CreateVendorApiKeyInputSchema>;

export const ListVendorApiKeysForTenantInputSchema = z.object({
  tenantId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
});
export type ListVendorApiKeysForTenantInput = z.input<typeof ListVendorApiKeysForTenantInputSchema>;

export function parseVendorApiKey(row: Record<string, unknown>): VendorApiKey {
  return VendorApiKeySchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    name: row.name,
    keyPrefix: row.key_prefix,
    scopes: row.scopes,
    status: row.status,
    rateLimitPerMinute: row.rate_limit_per_minute,
    expiresAt: row.expires_at,
    lastUsedAt: row.last_used_at,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    vendorMasterRecordId: row.vendor_master_record_id,
    vendorLegalName: row.vendor_legal_name ?? undefined,
  });
}

/** Maps app.create_vendor_api_key()'s one-time return row, including raw_key. */
export function parseCreatedVendorApiKey(row: Record<string, unknown>): CreatedVendorApiKey {
  return CreatedVendorApiKeySchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    name: row.name,
    keyPrefix: row.key_prefix,
    scopes: row.scopes,
    status: row.status,
    rateLimitPerMinute: row.rate_limit_per_minute,
    expiresAt: row.expires_at,
    createdAt: row.created_at,
    vendorMasterRecordId: row.vendor_master_record_id,
    rawKey: row.raw_key,
  });
}

export const RfqForVendorApiSchema = z.object({
  rfqInvitationId: z.string().uuid(),
  rfqId: z.string().uuid(),
  invitationStatus: z.string(),
  responseDeadlineAt: z.string().nullable(),
  rfqNumber: z.string(),
  rfqStatus: z.string(),
});
export type RfqForVendorApi = z.infer<typeof RfqForVendorApiSchema>;

export function parseRfqForVendorApi(row: Record<string, unknown>): RfqForVendorApi {
  return RfqForVendorApiSchema.parse({
    rfqInvitationId: row.rfq_invitation_id,
    rfqId: row.rfq_id,
    invitationStatus: row.invitation_status,
    responseDeadlineAt: row.response_deadline_at,
    rfqNumber: row.rfq_number,
    rfqStatus: row.rfq_status,
  });
}

export const SubmitRfqResponseViaVendorApiInputSchema = z.object({
  tenantId: z.string().uuid(),
  vendorMasterRecordId: z.string().uuid(),
  rfqInvitationId: z.string().uuid(),
  currency: z.string().min(1),
  totalAmount: z.number().nonnegative(),
  validityUntil: z.string().nullable().default(null),
  leadTimeDays: z.number().int().nonnegative().nullable().default(null),
  commercialTerms: z.record(z.string(), z.unknown()).default({}),
  vendorConfirmed: z.boolean().default(true),
  idempotencyKey: z.string().min(1),
});
export type SubmitRfqResponseViaVendorApiInput = z.input<typeof SubmitRfqResponseViaVendorApiInputSchema>;

export const RfqResponseSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  rfqId: z.string().uuid(),
  rfqInvitationId: z.string().uuid(),
  version: z.number().int(),
  status: z.string(),
  currency: z.string(),
  totalAmount: z.number(),
  validityUntil: z.string().nullable(),
  leadTimeDays: z.number().int().nullable(),
  captureMode: z.string(),
  lateCapture: z.boolean(),
  createdAt: z.string(),
});
export type RfqResponse = z.infer<typeof RfqResponseSchema>;

export function parseRfqResponse(row: Record<string, unknown>): RfqResponse {
  return RfqResponseSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    rfqId: row.rfq_id,
    rfqInvitationId: row.rfq_invitation_id,
    version: row.version,
    status: row.status,
    currency: row.currency,
    totalAmount: Number(row.total_amount),
    validityUntil: row.validity_until,
    leadTimeDays: row.lead_time_days,
    captureMode: row.capture_mode,
    lateCapture: row.late_capture,
    createdAt: row.created_at,
  });
}

export const VendorAssignmentDecisionInputSchema = z.object({
  tenantId: z.string().uuid(),
  vendorMasterRecordId: z.string().uuid(),
  invitationId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
});
export type VendorAssignmentDecisionInput = z.input<typeof VendorAssignmentDecisionInputSchema>;

export const DeclineVendorAssignmentViaVendorApiInputSchema = VendorAssignmentDecisionInputSchema.extend({
  reason: z.string().min(1),
});
export type DeclineVendorAssignmentViaVendorApiInput = z.input<typeof DeclineVendorAssignmentViaVendorApiInputSchema>;

export const VendorAssignmentInvitationSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  shipmentOrderId: z.string().uuid(),
  vendorMasterId: z.string().uuid(),
  status: z.string(),
  declineReason: z.string().nullable(),
  recordVersion: z.number().int(),
});
export type VendorAssignmentInvitation = z.infer<typeof VendorAssignmentInvitationSchema>;

export function parseVendorAssignmentInvitation(row: Record<string, unknown>): VendorAssignmentInvitation {
  return VendorAssignmentInvitationSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    shipmentOrderId: row.shipment_order_id,
    vendorMasterId: row.vendor_master_id,
    status: row.status,
    declineReason: row.decline_reason,
    recordVersion: row.record_version,
  });
}
