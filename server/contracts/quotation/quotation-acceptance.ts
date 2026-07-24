/**
 * Customer Acceptance contract (COM-154, CG-S7-COM-013). Mirrors
 * supabase/migrations/20260724280000_create_commercial_quotation_customer_acceptance.sql's
 * app.quotation_acceptance_tokens/app.quotation_customer_decisions shape and the
 * app.send_quotation_for_acceptance / app.revoke_quotation_acceptance_token /
 * app.get_quotation_for_customer_decision / app.record_quotation_customer_decision RPCs.
 *
 * token_hash never appears in this contract -- neither internal reads (server/queries/
 * quotation-acceptance.ts's authenticated-facing query) nor the raw-token-returning
 * mutations expose it; the migration's own grants never select it either.
 */

import { z } from "zod";

export const QUOTATION_ACCEPTANCE_TOKEN_STATUSES = ["active", "consumed", "revoked", "expired"] as const;
export const QuotationAcceptanceTokenStatusSchema = z.enum(QUOTATION_ACCEPTANCE_TOKEN_STATUSES);
export type QuotationAcceptanceTokenStatus = z.infer<typeof QuotationAcceptanceTokenStatusSchema>;

export const QUOTATION_ACCEPTANCE_CHANNELS = ["email", "manual_link"] as const;
export const QuotationAcceptanceChannelSchema = z.enum(QUOTATION_ACCEPTANCE_CHANNELS);
export type QuotationAcceptanceChannel = z.infer<typeof QuotationAcceptanceChannelSchema>;

export const CUSTOMER_DECISION_VALUES = ["accepted", "rejected"] as const;
export const CustomerDecisionValueSchema = z.enum(CUSTOMER_DECISION_VALUES);
export type CustomerDecisionValue = z.infer<typeof CustomerDecisionValueSchema>;

/** Maps a raw app.quotation_acceptance_tokens row (authenticated-facing columns only -- token_hash is never selected). */
export const QuotationAcceptanceTokenSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  quotationId: z.string().uuid(),
  status: QuotationAcceptanceTokenStatusSchema,
  channel: QuotationAcceptanceChannelSchema,
  recipientContactId: z.string().uuid().nullable(),
  recipientEmail: z.string().nullable(),
  expiresAt: z.string(),
  sentAt: z.string(),
  sentBy: z.string().nullable(),
  revokedAt: z.string().nullable(),
  revokedReason: z.string().nullable(),
  consumedAt: z.string().nullable(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
});
export type QuotationAcceptanceToken = z.infer<typeof QuotationAcceptanceTokenSchema>;

export function parseQuotationAcceptanceToken(row: Record<string, unknown>): QuotationAcceptanceToken {
  return QuotationAcceptanceTokenSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    quotationId: row.quotation_id,
    status: row.status,
    channel: row.channel,
    recipientContactId: row.recipient_contact_id,
    recipientEmail: row.recipient_email,
    expiresAt: row.expires_at,
    sentAt: row.sent_at,
    sentBy: row.sent_by,
    revokedAt: row.revoked_at,
    revokedReason: row.revoked_reason,
    consumedAt: row.consumed_at,
    createdBy: row.created_by,
    createdAt: row.created_at,
  });
}

/** The raw-token-bearing result of app.send_quotation_for_acceptance -- the one and only place a raw token is ever available (never stored, never returned again). */
export const SendQuotationForAcceptanceResultSchema = z.object({
  tokenId: z.string().uuid(),
  rawToken: z.string(),
  expiresAt: z.string(),
  quotationId: z.string().uuid(),
});
export type SendQuotationForAcceptanceResult = z.infer<typeof SendQuotationForAcceptanceResultSchema>;

export function parseSendQuotationForAcceptanceResult(row: Record<string, unknown>): SendQuotationForAcceptanceResult {
  return SendQuotationForAcceptanceResultSchema.parse({
    tokenId: row.token_id,
    rawToken: row.raw_token,
    expiresAt: row.expires_at,
    quotationId: row.quotation_id,
  });
}

/** The public, customer-safe projection app.get_quotation_for_customer_decision returns -- never cost/margin (Prompt 154 §26). */
export const CustomerQuotationViewSchema = z.object({
  tokenStatus: QuotationAcceptanceTokenStatusSchema,
  quotationId: z.string().uuid(),
  quoteNumber: z.string(),
  customerSnapshot: z.record(z.string(), z.unknown()),
  currency: z.string(),
  validityTo: z.string(),
  terms: z.record(z.string(), z.unknown()),
  subtotalAmount: z.coerce.number().nullable(),
  discountAmount: z.coerce.number().nullable(),
  taxAmount: z.coerce.number().nullable(),
  totalAmount: z.coerce.number().nullable(),
  alreadyDecided: z.boolean(),
});
export type CustomerQuotationView = z.infer<typeof CustomerQuotationViewSchema>;

export function parseCustomerQuotationView(row: Record<string, unknown>): CustomerQuotationView {
  return CustomerQuotationViewSchema.parse({
    tokenStatus: row.token_status,
    quotationId: row.quotation_id,
    quoteNumber: row.quote_number,
    customerSnapshot: row.customer_snapshot ?? {},
    currency: row.currency,
    validityTo: row.validity_to,
    terms: row.terms ?? {},
    subtotalAmount: row.subtotal_amount,
    discountAmount: row.discount_amount,
    taxAmount: row.tax_amount,
    totalAmount: row.total_amount,
    alreadyDecided: row.already_decided,
  });
}

export const SendQuotationForAcceptanceInputSchema = z.object({
  quotationId: z.string().uuid(),
  recipientContactId: z.string().uuid().nullable().default(null),
  channel: QuotationAcceptanceChannelSchema.default("email"),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SendQuotationForAcceptanceInput = z.input<typeof SendQuotationForAcceptanceInputSchema>;

export const RevokeQuotationAcceptanceTokenInputSchema = z.object({
  tokenId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
  reason: z.string().min(1),
});
export type RevokeQuotationAcceptanceTokenInput = z.input<typeof RevokeQuotationAcceptanceTokenInputSchema>;

export const GetQuotationForCustomerDecisionInputSchema = z.object({
  rawToken: z.string().min(1),
});
export type GetQuotationForCustomerDecisionInput = z.input<typeof GetQuotationForCustomerDecisionInputSchema>;

/** decidedByName is the customer's own typed attestation -- bearer-token possession is the only authority in this bounded slice (no verified customer account exists yet, COM-155 has not run). reason is required when decision="rejected" (server-enforced). */
export const RecordQuotationCustomerDecisionInputSchema = z.object({
  rawToken: z.string().min(1),
  decision: CustomerDecisionValueSchema,
  decidedByName: z.string().min(1),
  decidedByTitle: z.string().nullable().default(null),
  decidedByEmail: z.string().nullable().default(null),
  reason: z.string().nullable().default(null),
  ipAddress: z.string().nullable().default(null),
  userAgent: z.string().nullable().default(null),
});
export type RecordQuotationCustomerDecisionInput = z.input<typeof RecordQuotationCustomerDecisionInputSchema>;
