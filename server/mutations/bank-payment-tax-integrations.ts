/**
 * Bank, Payment Gateway, E-Invoice and Tax Integrations mutation primitives
 * (IAE-017, Prompt 345). Thin, typed wrappers around
 * app.ingest_finance_payment_gateway_webhook_event /
 * app.trigger_finance_bank_feed_sync /
 * app.review_finance_payment_gateway_event /
 * app.record_einvoice_submission_attempt / app.record_tax_authority_lookup
 * (supabase/migrations/20260805040000_create_intelligence_bank_payment_einvoice_tax_integrations.sql).
 */

import {
  IngestFinancePaymentGatewayWebhookEventInputSchema,
  parseIngestFinancePaymentGatewayWebhookEventResult,
  TriggerFinanceBankFeedSyncInputSchema,
  ReviewFinancePaymentGatewayEventInputSchema,
  parseFinancePaymentGatewayEvent,
  RecordEinvoiceSubmissionAttemptInputSchema,
  RecordTaxAuthorityLookupInputSchema,
  parseFinanceProviderCallEvidence,
  type IngestFinancePaymentGatewayWebhookEventInput,
  type IngestFinancePaymentGatewayWebhookEventResult,
  type TriggerFinanceBankFeedSyncInput,
  type ReviewFinancePaymentGatewayEventInput,
  type FinancePaymentGatewayEvent,
  type RecordEinvoiceSubmissionAttemptInput,
  type RecordTaxAuthorityLookupInput,
  type FinanceProviderCallEvidence,
} from "../contracts/bank-payment-tax-integrations/bank-payment-tax-integrations.ts";

export interface FinanceIntegrationsMutationRpcClient {
  rpc(
    fn:
      | "ingest_finance_payment_gateway_webhook_event"
      | "trigger_finance_bank_feed_sync"
      | "review_finance_payment_gateway_event"
      | "record_einvoice_submission_attempt"
      | "record_tax_authority_lookup",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export const FINANCE_INTEGRATIONS_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "finance_payment_client_key_required",
  "finance_provider_invalid_adapter_code",
  "finance_provider_connection_not_found",
  "finance_provider_connection_not_active",
  "finance_cash_bank_account_not_found",
  "finance_payment_event_not_found",
  "finance_payment_event_invalid_decision",
  "finance_payment_event_invalid_limit",
  "finance_invoice_not_found",
  "finance_einvoice_invoice_not_issued",
  "finance_provider_call_invalid_status",
  "finance_provider_call_invalid_cost_amount",
  "finance_tax_lookup_code_required",
  "finance_tax_lookup_as_of_date_required",
  "finance_provider_call_evidence_invalid_call_type",
  "finance_provider_call_evidence_invalid_limit",
] as const;
type KnownFinanceIntegrationsMutationErrorCode = (typeof FINANCE_INTEGRATIONS_KNOWN_MUTATION_ERROR_CODES)[number];
export type FinanceIntegrationsMutationErrorCode = KnownFinanceIntegrationsMutationErrorCode | "mutation_failed" | "invalid_response";

export class FinanceIntegrationsMutationError extends Error {
  readonly code: FinanceIntegrationsMutationErrorCode;

  constructor(code: FinanceIntegrationsMutationErrorCode, message: string) {
    super(message);
    this.name = "FinanceIntegrationsMutationError";
    this.code = code;
  }
}

function classifyError(message: string): FinanceIntegrationsMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (FINANCE_INTEGRATIONS_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownFinanceIntegrationsMutationErrorCode) : "mutation_failed";
}

/** The provider's own webhook entry point. Never throws for a bad signature/malformed payload/duplicate event -- see the migration's own header. Only a genuine transport/serialization error throws. */
export async function ingestFinancePaymentGatewayWebhookEvent(client: FinanceIntegrationsMutationRpcClient, input: IngestFinancePaymentGatewayWebhookEventInput): Promise<IngestFinancePaymentGatewayWebhookEventResult> {
  const parsedInput = IngestFinancePaymentGatewayWebhookEventInputSchema.parse(input);
  const { data, error } = await client.rpc("ingest_finance_payment_gateway_webhook_event", {
    p_connection_id: parsedInput.connectionId,
    p_client_key: parsedInput.clientKey,
    p_raw_payload: parsedInput.rawPayload,
    p_timestamp: parsedInput.timestamp,
    p_signature: parsedInput.signature,
  });
  if (error) {
    throw new FinanceIntegrationsMutationError(classifyError(error.message), error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new FinanceIntegrationsMutationError("invalid_response", "ingest_finance_payment_gateway_webhook_event returned no row");
  }
  return parseIngestFinancePaymentGatewayWebhookEventResult(row as Record<string, unknown>);
}

export interface TriggerFinanceBankFeedSyncResult {
  readonly jobId: string;
}

/** The real second caller of app.check_integration_connection_active (IAE-336), after IAE-016's own poll-sync trigger. */
export async function triggerFinanceBankFeedSync(client: FinanceIntegrationsMutationRpcClient, input: TriggerFinanceBankFeedSyncInput): Promise<TriggerFinanceBankFeedSyncResult> {
  const parsedInput = TriggerFinanceBankFeedSyncInputSchema.parse(input);
  const { data, error } = await client.rpc("trigger_finance_bank_feed_sync", {
    p_tenant_id: parsedInput.tenantId,
    p_connection_id: parsedInput.connectionId,
    p_bank_account_id: parsedInput.bankAccountId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new FinanceIntegrationsMutationError(classifyError(error.message), error.message);
  }
  const row = data as Record<string, unknown> | null;
  if (!row || typeof row.job_id !== "string") {
    throw new FinanceIntegrationsMutationError("invalid_response", "trigger_finance_bank_feed_sync returned no row");
  }
  return { jobId: row.job_id };
}

/** Evidence-only -- never writes to app.finance_bank_transactions. Authority: FIN:Edit for the event's own tenant. */
export async function reviewFinancePaymentGatewayEvent(client: FinanceIntegrationsMutationRpcClient, input: ReviewFinancePaymentGatewayEventInput): Promise<FinancePaymentGatewayEvent> {
  const parsedInput = ReviewFinancePaymentGatewayEventInputSchema.parse(input);
  const { data, error } = await client.rpc("review_finance_payment_gateway_event", {
    p_event_id: parsedInput.eventId,
    p_decision: parsedInput.decision,
    p_notes: parsedInput.notes,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new FinanceIntegrationsMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new FinanceIntegrationsMutationError("invalid_response", "review_finance_payment_gateway_event returned no row");
  }
  return parseFinancePaymentGatewayEvent(data as Record<string, unknown>);
}

/** Never mutates app.finance_invoices.status -- a parallel compliance tracking record. billed_amount computed server-side (RPD-028). */
export async function recordEinvoiceSubmissionAttempt(client: FinanceIntegrationsMutationRpcClient, input: RecordEinvoiceSubmissionAttemptInput): Promise<FinanceProviderCallEvidence> {
  const parsedInput = RecordEinvoiceSubmissionAttemptInputSchema.parse(input);
  const { data, error } = await client.rpc("record_einvoice_submission_attempt", {
    p_tenant_id: parsedInput.tenantId,
    p_connection_id: parsedInput.connectionId,
    p_finance_invoice_id: parsedInput.financeInvoiceId,
    p_status: parsedInput.status,
    p_request_payload: parsedInput.requestPayload,
    p_response_payload: parsedInput.responsePayload,
    p_provider_unit_cost_amount: parsedInput.providerUnitCostAmount,
    p_currency: parsedInput.currency,
    p_error_message: parsedInput.errorMessage,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new FinanceIntegrationsMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new FinanceIntegrationsMutationError("invalid_response", "record_einvoice_submission_attempt returned no row");
  }
  return parseFinanceProviderCallEvidence(data as Record<string, unknown>);
}

/** Never mutates app.finance_tax_rule_versions -- this row's own id is meant to be cited as human-supplied evidence when a Finance user separately approves a tax rule (RPD-016). */
export async function recordTaxAuthorityLookup(client: FinanceIntegrationsMutationRpcClient, input: RecordTaxAuthorityLookupInput): Promise<FinanceProviderCallEvidence> {
  const parsedInput = RecordTaxAuthorityLookupInputSchema.parse(input);
  const { data, error } = await client.rpc("record_tax_authority_lookup", {
    p_tenant_id: parsedInput.tenantId,
    p_connection_id: parsedInput.connectionId,
    p_tax_code: parsedInput.taxCode,
    p_as_of_date: parsedInput.asOfDate,
    p_status: parsedInput.status,
    p_request_payload: parsedInput.requestPayload,
    p_response_payload: parsedInput.responsePayload,
    p_provider_unit_cost_amount: parsedInput.providerUnitCostAmount,
    p_currency: parsedInput.currency,
    p_error_message: parsedInput.errorMessage,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new FinanceIntegrationsMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new FinanceIntegrationsMutationError("invalid_response", "record_tax_authority_lookup returned no row");
  }
  return parseFinanceProviderCallEvidence(data as Record<string, unknown>);
}
