/**
 * Bank, Payment Gateway, E-Invoice and Tax Integrations contract (IAE-017,
 * Prompt 345). Mirrors supabase/migrations/
 * 20260805040000_create_intelligence_bank_payment_einvoice_tax_integrations.sql's
 * app.finance_payment_gateway_events / app.finance_provider_call_evidence
 * shapes and their ingest/sync/review/list/record RPCs.
 */

import { z } from "zod";

export const FINANCE_PROVIDER_ADAPTER_CODES = ["bank_feed_api", "payment_gateway", "einvoice_provider", "tax_authority_api"] as const;
export const FinanceProviderAdapterCodeSchema = z.enum(FINANCE_PROVIDER_ADAPTER_CODES);
export type FinanceProviderAdapterCode = z.infer<typeof FinanceProviderAdapterCodeSchema>;

export const FINANCE_PAYMENT_GATEWAY_EVENT_TYPES = ["payment_confirmed", "payment_failed", "refund_issued", "chargeback"] as const;
export const FinancePaymentGatewayEventTypeSchema = z.enum(FINANCE_PAYMENT_GATEWAY_EVENT_TYPES);
export type FinancePaymentGatewayEventType = z.infer<typeof FinancePaymentGatewayEventTypeSchema>;

export const FINANCE_MATCH_STATUSES = ["matched", "unmatched", "ambiguous"] as const;
export const FinanceMatchStatusSchema = z.enum(FINANCE_MATCH_STATUSES);
export type FinanceMatchStatus = z.infer<typeof FinanceMatchStatusSchema>;

export const FINANCE_PAYMENT_EVENT_PROCESSING_STATUSES = ["received", "reviewed", "dismissed"] as const;
export const FinancePaymentEventProcessingStatusSchema = z.enum(FINANCE_PAYMENT_EVENT_PROCESSING_STATUSES);
export type FinancePaymentEventProcessingStatus = z.infer<typeof FinancePaymentEventProcessingStatusSchema>;

export const FinancePaymentGatewayEventSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  connectionId: z.string().uuid(),
  providerEventId: z.string(),
  eventType: FinancePaymentGatewayEventTypeSchema,
  externalReference: z.string().nullable(),
  bankTransactionId: z.string().uuid().nullable(),
  matchStatus: FinanceMatchStatusSchema,
  rawPayload: z.record(z.string(), z.unknown()),
  processingStatus: FinancePaymentEventProcessingStatusSchema,
  reviewNotes: z.string().nullable(),
  reviewedByAuthUserId: z.string().uuid().nullable(),
  reviewedAt: z.string().nullable(),
  createdAt: z.string(),
});
export type FinancePaymentGatewayEvent = z.infer<typeof FinancePaymentGatewayEventSchema>;

export function parseFinancePaymentGatewayEvent(row: Record<string, unknown>): FinancePaymentGatewayEvent {
  return FinancePaymentGatewayEventSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    connectionId: row.connection_id,
    providerEventId: row.provider_event_id,
    eventType: row.event_type,
    externalReference: row.external_reference,
    bankTransactionId: row.bank_transaction_id,
    matchStatus: row.match_status,
    rawPayload: row.raw_payload,
    processingStatus: row.processing_status,
    reviewNotes: row.review_notes,
    reviewedByAuthUserId: row.reviewed_by_auth_user_id,
    reviewedAt: row.reviewed_at,
    createdAt: row.created_at,
  });
}

export const FINANCE_PAYMENT_INGEST_STATUSES = ["ok", "duplicate", "invalid", "rate_limited"] as const;
export const FinancePaymentIngestStatusSchema = z.enum(FINANCE_PAYMENT_INGEST_STATUSES);
export type FinancePaymentIngestStatus = z.infer<typeof FinancePaymentIngestStatusSchema>;

export const IngestFinancePaymentGatewayWebhookEventInputSchema = z.object({
  connectionId: z.string().uuid(),
  clientKey: z.string().min(1),
  rawPayload: z.string(),
  timestamp: z.number(),
  signature: z.string(),
});
export type IngestFinancePaymentGatewayWebhookEventInput = z.input<typeof IngestFinancePaymentGatewayWebhookEventInputSchema>;

export const IngestFinancePaymentGatewayWebhookEventResultSchema = z.object({
  ingestStatus: FinancePaymentIngestStatusSchema,
  eventId: z.string().uuid().nullable(),
});
export type IngestFinancePaymentGatewayWebhookEventResult = z.infer<typeof IngestFinancePaymentGatewayWebhookEventResultSchema>;

export function parseIngestFinancePaymentGatewayWebhookEventResult(row: Record<string, unknown>): IngestFinancePaymentGatewayWebhookEventResult {
  return IngestFinancePaymentGatewayWebhookEventResultSchema.parse({
    ingestStatus: row.ingest_status,
    eventId: row.event_id,
  });
}

export const TriggerFinanceBankFeedSyncInputSchema = z.object({
  tenantId: z.string().uuid(),
  connectionId: z.string().uuid(),
  bankAccountId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type TriggerFinanceBankFeedSyncInput = z.input<typeof TriggerFinanceBankFeedSyncInputSchema>;

export const ReviewFinancePaymentGatewayEventInputSchema = z.object({
  eventId: z.string().uuid(),
  decision: z.enum(["reviewed", "dismissed"]),
  notes: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ReviewFinancePaymentGatewayEventInput = z.input<typeof ReviewFinancePaymentGatewayEventInputSchema>;

export const ListFinancePaymentGatewayEventsForTenantInputSchema = z.object({
  tenantId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  bankTransactionId: z.string().uuid().nullable().default(null),
  limit: z.number().int().positive().max(200).default(50),
});
export type ListFinancePaymentGatewayEventsForTenantInput = z.input<typeof ListFinancePaymentGatewayEventsForTenantInputSchema>;

/** The real outbound client's own minimal read -- never the raw credential. */
export const FinanceProviderDispatchInfoSchema = z.object({
  connectionId: z.string().uuid(),
  connectionStatus: z.string(),
  connectionConfig: z.record(z.string(), z.unknown()),
});
export type FinanceProviderDispatchInfo = z.infer<typeof FinanceProviderDispatchInfoSchema>;

export function parseFinanceProviderDispatchInfo(row: Record<string, unknown>): FinanceProviderDispatchInfo {
  return FinanceProviderDispatchInfoSchema.parse({
    connectionId: row.connection_id,
    connectionStatus: row.connection_status,
    connectionConfig: row.connection_config,
  });
}

/** The real bank-feed poll worker's own connection read -- no actor authority check (already-authorized background job). */
export const FinanceProviderConnectionForSyncSchema = z.object({
  tenantId: z.string().uuid(),
  adapterCode: z.string(),
  connectionStatus: z.string(),
  connectionConfig: z.record(z.string(), z.unknown()),
});
export type FinanceProviderConnectionForSync = z.infer<typeof FinanceProviderConnectionForSyncSchema>;

export function parseFinanceProviderConnectionForSync(row: Record<string, unknown>): FinanceProviderConnectionForSync {
  return FinanceProviderConnectionForSyncSchema.parse({
    tenantId: row.tenant_id,
    adapterCode: row.adapter_code,
    connectionStatus: row.connection_status,
    connectionConfig: row.connection_config,
  });
}

export const FINANCE_PROVIDER_CALL_TYPES = ["einvoice_submission", "tax_authority_lookup"] as const;
export const FinanceProviderCallTypeSchema = z.enum(FINANCE_PROVIDER_CALL_TYPES);
export type FinanceProviderCallType = z.infer<typeof FinanceProviderCallTypeSchema>;

export const FINANCE_PROVIDER_CALL_STATUSES = ["success", "failed"] as const;
export const FinanceProviderCallStatusSchema = z.enum(FINANCE_PROVIDER_CALL_STATUSES);
export type FinanceProviderCallStatus = z.infer<typeof FinanceProviderCallStatusSchema>;

export const FinanceProviderCallEvidenceSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  connectionId: z.string().uuid(),
  callType: FinanceProviderCallTypeSchema,
  financeInvoiceId: z.string().uuid().nullable(),
  taxCode: z.string().nullable(),
  asOfDate: z.string().nullable(),
  requestPayload: z.record(z.string(), z.unknown()),
  status: FinanceProviderCallStatusSchema,
  responsePayload: z.record(z.string(), z.unknown()).nullable(),
  providerUnitCostAmount: z.number().nullable(),
  currency: z.string().nullable(),
  billedAmount: z.number().nullable(),
  errorMessage: z.string().nullable(),
  requestedByAuthUserId: z.string().uuid().nullable(),
  requestedBy: z.string().nullable(),
  createdAt: z.string(),
});
export type FinanceProviderCallEvidence = z.infer<typeof FinanceProviderCallEvidenceSchema>;

export function parseFinanceProviderCallEvidence(row: Record<string, unknown>): FinanceProviderCallEvidence {
  return FinanceProviderCallEvidenceSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    connectionId: row.connection_id,
    callType: row.call_type,
    financeInvoiceId: row.finance_invoice_id,
    taxCode: row.tax_code,
    asOfDate: row.as_of_date,
    requestPayload: row.request_payload,
    status: row.status,
    responsePayload: row.response_payload,
    providerUnitCostAmount: row.provider_unit_cost_amount,
    currency: row.currency,
    billedAmount: row.billed_amount,
    errorMessage: row.error_message,
    requestedByAuthUserId: row.requested_by_auth_user_id,
    requestedBy: row.requested_by,
    createdAt: row.created_at,
  });
}

export const RecordEinvoiceSubmissionAttemptInputSchema = z.object({
  tenantId: z.string().uuid(),
  connectionId: z.string().uuid(),
  financeInvoiceId: z.string().uuid(),
  status: FinanceProviderCallStatusSchema,
  requestPayload: z.record(z.string(), z.unknown()),
  responsePayload: z.record(z.string(), z.unknown()).nullable().default(null),
  providerUnitCostAmount: z.number().nonnegative().nullable().default(null),
  currency: z.string().nullable().default(null),
  errorMessage: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RecordEinvoiceSubmissionAttemptInput = z.input<typeof RecordEinvoiceSubmissionAttemptInputSchema>;

export const RecordTaxAuthorityLookupInputSchema = z.object({
  tenantId: z.string().uuid(),
  connectionId: z.string().uuid(),
  taxCode: z.string().min(1),
  asOfDate: z.string(),
  status: FinanceProviderCallStatusSchema,
  requestPayload: z.record(z.string(), z.unknown()),
  responsePayload: z.record(z.string(), z.unknown()).nullable().default(null),
  providerUnitCostAmount: z.number().nonnegative().nullable().default(null),
  currency: z.string().nullable().default(null),
  errorMessage: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RecordTaxAuthorityLookupInput = z.input<typeof RecordTaxAuthorityLookupInputSchema>;

export const ListFinanceProviderCallEvidenceForTenantInputSchema = z.object({
  tenantId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  callType: FinanceProviderCallTypeSchema.nullable().default(null),
  limit: z.number().int().positive().max(200).default(50),
});
export type ListFinanceProviderCallEvidenceForTenantInput = z.input<typeof ListFinanceProviderCallEvidenceForTenantInputSchema>;
