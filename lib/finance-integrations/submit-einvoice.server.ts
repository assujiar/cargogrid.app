/**
 * The real e-invoice submission client (IAE-017, Prompt 345) -- the SIXTH
 * real outbound HTTP client in this repository. Unlike the bank-feed
 * poller, this is a live, synchronous request/response call (an already-
 * issued invoice in, a submission outcome out), mirroring IAE-015's own
 * geocode client's "synchronous, not app.jobs-backed" shape.
 *
 * Never mutates `app.finance_invoices` -- e-invoice submission tracking is
 * a parallel compliance record (`app.finance_provider_call_evidence`,
 * call_type='einvoice_submission'), never the invoice's own source of
 * truth. Requires an ALREADY-`issued` invoice (via the existing, unmodified
 * `app.issue_finance_invoice`).
 *
 * Reuses ../webhooks/ssrf-guard.server.ts's checkWebhookDispatchUrlIsSafe
 * directly, the same proactive reuse every prior real outbound client in
 * this repository has already established.
 */

import { getFinanceProviderDispatchInfo, getFinanceProviderCredential, type FinanceIntegrationsQueryRpcClient } from "../../server/queries/bank-payment-tax-integrations.ts";
import { recordEinvoiceSubmissionAttempt, type FinanceIntegrationsMutationRpcClient } from "../../server/mutations/bank-payment-tax-integrations.ts";
import { checkWebhookDispatchUrlIsSafe, type SsrfCheckResult } from "../webhooks/ssrf-guard.server.ts";

const REQUEST_TIMEOUT_MS = 15_000;

export type EinvoiceDispatchUrlSafetyChecker = (rawUrl: string) => Promise<SsrfCheckResult>;

export type SubmitEinvoiceRpcClient = FinanceIntegrationsQueryRpcClient & FinanceIntegrationsMutationRpcClient;

export interface SubmitEinvoiceResult {
  readonly success: boolean;
  readonly providerReference: string | null;
  readonly errorMessage: string | null;
}

interface SubmitEinvoiceOptions {
  readonly tenantId: string;
  readonly actorAuthUserId: string;
  readonly actorLabel: string;
  readonly financeInvoiceId: string;
  readonly invoicePayload: Record<string, unknown>;
}

function placeholderCost(payloadLength: number): number {
  return Math.round((0.01 + payloadLength * 0.00002) * 10000) / 10000;
}

/**
 * Real, synchronous e-invoice submission. Never throws for a delivery-side
 * failure (no connection configured, HTTP error, timeout, unsafe URL) --
 * those are real, expected outcomes reported to
 * app.record_einvoice_submission_attempt and returned as `success: false`.
 */
export async function submitEinvoice(client: SubmitEinvoiceRpcClient, options: SubmitEinvoiceOptions, checkUrlSafety: EinvoiceDispatchUrlSafetyChecker = checkWebhookDispatchUrlIsSafe): Promise<SubmitEinvoiceResult> {
  const { tenantId, actorAuthUserId, actorLabel, financeInvoiceId, invoicePayload } = options;

  const dispatchInfo = await getFinanceProviderDispatchInfo(client, tenantId, actorAuthUserId, "einvoice_provider");
  if (!dispatchInfo) {
    // Tier C fix: there is no real connection_id to attribute evidence to --
    // app.finance_provider_call_evidence.connection_id is NOT NULL
    // REFERENCES app.integration_connections(id), so a sentinel UUID here
    // previously raised a raw foreign-key-violation instead of the
    // documented clean failure result.
    return { success: false, providerReference: null, errorMessage: "no active einvoice_provider connection configured for this tenant" };
  }
  if (dispatchInfo.connectionStatus !== "active") {
    const errorMessage = "no active einvoice_provider connection configured for this tenant";
    await recordEinvoiceSubmissionAttempt(client, { tenantId, connectionId: dispatchInfo.connectionId, financeInvoiceId, status: "failed", requestPayload: invoicePayload, errorMessage, actorAuthUserId, actorLabel });
    return { success: false, providerReference: null, errorMessage };
  }

  const apiUrl = typeof dispatchInfo.connectionConfig.apiUrl === "string" ? dispatchInfo.connectionConfig.apiUrl : null;
  if (!apiUrl) {
    const errorMessage = "einvoice_provider connection has no apiUrl configured";
    await recordEinvoiceSubmissionAttempt(client, { tenantId, connectionId: dispatchInfo.connectionId, financeInvoiceId, status: "failed", requestPayload: invoicePayload, errorMessage, actorAuthUserId, actorLabel });
    return { success: false, providerReference: null, errorMessage };
  }

  const urlSafety = await checkUrlSafety(apiUrl);
  if (!urlSafety.safe) {
    const errorMessage = `refusing to dispatch: ${urlSafety.reason ?? "provider apiUrl failed the delivery-time safety check"}`;
    await recordEinvoiceSubmissionAttempt(client, { tenantId, connectionId: dispatchInfo.connectionId, financeInvoiceId, status: "failed", requestPayload: invoicePayload, errorMessage, actorAuthUserId, actorLabel });
    return { success: false, providerReference: null, errorMessage };
  }

  const credential = await getFinanceProviderCredential(client, dispatchInfo.connectionId);
  if (!credential) {
    const errorMessage = "einvoice_provider connection has no stored credential";
    await recordEinvoiceSubmissionAttempt(client, { tenantId, connectionId: dispatchInfo.connectionId, financeInvoiceId, status: "failed", requestPayload: invoicePayload, errorMessage, actorAuthUserId, actorLabel });
    return { success: false, providerReference: null, errorMessage };
  }

  const requestPayload = JSON.stringify(invoicePayload);
  const controller = new AbortController();
  const timeoutHandle = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  let response: Response;
  try {
    response = await fetch(apiUrl, {
      method: "POST",
      headers: { "content-type": "application/json", authorization: `Bearer ${credential}` },
      body: requestPayload,
      signal: controller.signal,
      redirect: "manual",
    });
  } catch (error) {
    const errorMessage = error instanceof Error && error.name === "AbortError" ? `request timed out after ${REQUEST_TIMEOUT_MS}ms` : error instanceof Error ? error.message : "unknown fetch error";
    await recordEinvoiceSubmissionAttempt(client, { tenantId, connectionId: dispatchInfo.connectionId, financeInvoiceId, status: "failed", requestPayload: invoicePayload, errorMessage, actorAuthUserId, actorLabel });
    return { success: false, providerReference: null, errorMessage };
  } finally {
    clearTimeout(timeoutHandle);
  }

  if (response.status < 200 || response.status >= 300) {
    const errorMessage = `e-invoice provider responded with HTTP ${response.status}`;
    await recordEinvoiceSubmissionAttempt(client, { tenantId, connectionId: dispatchInfo.connectionId, financeInvoiceId, status: "failed", requestPayload: invoicePayload, errorMessage, actorAuthUserId, actorLabel });
    return { success: false, providerReference: null, errorMessage };
  }

  let body: { providerReference?: unknown };
  try {
    body = await response.json();
  } catch {
    const errorMessage = "e-invoice provider returned a non-JSON response body";
    await recordEinvoiceSubmissionAttempt(client, { tenantId, connectionId: dispatchInfo.connectionId, financeInvoiceId, status: "failed", requestPayload: invoicePayload, errorMessage, actorAuthUserId, actorLabel });
    return { success: false, providerReference: null, errorMessage };
  }

  const providerReference = typeof body.providerReference === "string" ? body.providerReference : null;
  if (!providerReference) {
    const errorMessage = "e-invoice provider response is missing providerReference";
    await recordEinvoiceSubmissionAttempt(client, { tenantId, connectionId: dispatchInfo.connectionId, financeInvoiceId, status: "failed", requestPayload: invoicePayload, errorMessage, actorAuthUserId, actorLabel });
    return { success: false, providerReference: null, errorMessage };
  }

  await recordEinvoiceSubmissionAttempt(client, {
    tenantId,
    connectionId: dispatchInfo.connectionId,
    financeInvoiceId,
    status: "success",
    requestPayload: invoicePayload,
    responsePayload: { providerReference },
    providerUnitCostAmount: placeholderCost(requestPayload.length),
    currency: "USD",
    actorAuthUserId,
    actorLabel,
  });

  return { success: true, providerReference, errorMessage: null };
}
