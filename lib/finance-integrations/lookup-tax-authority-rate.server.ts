/**
 * The real tax-authority rate lookup client (IAE-017, Prompt 345) -- the
 * SEVENTH real outbound HTTP client in this repository. A live, synchronous
 * request/response call (a tax code + as-of date in, the authority's own
 * published rate out), mirroring IAE-015's own geocode client's shape.
 *
 * Never mutates `app.finance_tax_rule_versions` or activates any tax rule
 * (RPD-016) -- this is evidence only (`app.finance_provider_call_evidence`,
 * call_type='tax_authority_lookup'). The returned evidence row's own id is
 * meant to be cited in a human's `evidence_note`/`evidence_reference_file_id`
 * when they separately, manually approve a tax rule through the existing,
 * evidence-CHECK-enforced `app.approve_finance_tax_rule`.
 *
 * Reuses ../webhooks/ssrf-guard.server.ts's checkWebhookDispatchUrlIsSafe
 * directly, the same proactive reuse every prior real outbound client in
 * this repository has already established.
 */

import { getFinanceProviderDispatchInfo, getFinanceProviderCredential, type FinanceIntegrationsQueryRpcClient } from "../../server/queries/bank-payment-tax-integrations.ts";
import { recordTaxAuthorityLookup, type FinanceIntegrationsMutationRpcClient } from "../../server/mutations/bank-payment-tax-integrations.ts";
import { checkWebhookDispatchUrlIsSafe, type SsrfCheckResult } from "../webhooks/ssrf-guard.server.ts";

const REQUEST_TIMEOUT_MS = 15_000;

export type TaxAuthorityDispatchUrlSafetyChecker = (rawUrl: string) => Promise<SsrfCheckResult>;

export type LookupTaxAuthorityRateRpcClient = FinanceIntegrationsQueryRpcClient & FinanceIntegrationsMutationRpcClient;

export interface LookupTaxAuthorityRateResult {
  readonly success: boolean;
  readonly evidenceId: string | null;
  readonly rateValue: number | null;
  readonly errorMessage: string | null;
}

interface LookupTaxAuthorityRateOptions {
  readonly tenantId: string;
  readonly actorAuthUserId: string;
  readonly actorLabel: string;
  readonly taxCode: string;
  readonly asOfDate: string;
}

function placeholderCost(): number {
  return 0.01;
}

/**
 * Real, synchronous tax-authority rate lookup. Never throws for a
 * delivery-side failure (no connection configured, HTTP error, timeout,
 * unsafe URL) -- those are real, expected outcomes reported to
 * app.record_tax_authority_lookup and returned as `success: false`.
 */
export async function lookupTaxAuthorityRate(client: LookupTaxAuthorityRateRpcClient, options: LookupTaxAuthorityRateOptions, checkUrlSafety: TaxAuthorityDispatchUrlSafetyChecker = checkWebhookDispatchUrlIsSafe): Promise<LookupTaxAuthorityRateResult> {
  const { tenantId, actorAuthUserId, actorLabel, taxCode, asOfDate } = options;
  const requestPayload = { taxCode, asOfDate };

  const dispatchInfo = await getFinanceProviderDispatchInfo(client, tenantId, actorAuthUserId, "tax_authority_api");
  if (!dispatchInfo) {
    // Tier C fix: there is no real connection_id to attribute evidence to --
    // app.finance_provider_call_evidence.connection_id is NOT NULL
    // REFERENCES app.integration_connections(id), so a sentinel UUID here
    // previously raised a raw foreign-key-violation instead of the
    // documented clean failure result.
    return { success: false, evidenceId: null, rateValue: null, errorMessage: "no active tax_authority_api connection configured for this tenant" };
  }
  if (dispatchInfo.connectionStatus !== "active") {
    const errorMessage = "no active tax_authority_api connection configured for this tenant";
    const evidence = await recordTaxAuthorityLookup(client, { tenantId, connectionId: dispatchInfo.connectionId, taxCode, asOfDate, status: "failed", requestPayload, errorMessage, actorAuthUserId, actorLabel });
    return { success: false, evidenceId: evidence.id, rateValue: null, errorMessage };
  }

  const apiUrl = typeof dispatchInfo.connectionConfig.apiUrl === "string" ? dispatchInfo.connectionConfig.apiUrl : null;
  if (!apiUrl) {
    const errorMessage = "tax_authority_api connection has no apiUrl configured";
    const evidence = await recordTaxAuthorityLookup(client, { tenantId, connectionId: dispatchInfo.connectionId, taxCode, asOfDate, status: "failed", requestPayload, errorMessage, actorAuthUserId, actorLabel });
    return { success: false, evidenceId: evidence.id, rateValue: null, errorMessage };
  }

  const lookupUrl = `${apiUrl}?taxCode=${encodeURIComponent(taxCode)}&asOfDate=${encodeURIComponent(asOfDate)}`;
  const urlSafety = await checkUrlSafety(lookupUrl);
  if (!urlSafety.safe) {
    const errorMessage = `refusing to dispatch: ${urlSafety.reason ?? "provider apiUrl failed the delivery-time safety check"}`;
    const evidence = await recordTaxAuthorityLookup(client, { tenantId, connectionId: dispatchInfo.connectionId, taxCode, asOfDate, status: "failed", requestPayload, errorMessage, actorAuthUserId, actorLabel });
    return { success: false, evidenceId: evidence.id, rateValue: null, errorMessage };
  }

  const credential = await getFinanceProviderCredential(client, dispatchInfo.connectionId);
  if (!credential) {
    const errorMessage = "tax_authority_api connection has no stored credential";
    const evidence = await recordTaxAuthorityLookup(client, { tenantId, connectionId: dispatchInfo.connectionId, taxCode, asOfDate, status: "failed", requestPayload, errorMessage, actorAuthUserId, actorLabel });
    return { success: false, evidenceId: evidence.id, rateValue: null, errorMessage };
  }

  const controller = new AbortController();
  const timeoutHandle = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  let response: Response;
  try {
    response = await fetch(lookupUrl, {
      method: "GET",
      headers: { authorization: `Bearer ${credential}` },
      signal: controller.signal,
      redirect: "manual",
    });
  } catch (error) {
    const errorMessage = error instanceof Error && error.name === "AbortError" ? `request timed out after ${REQUEST_TIMEOUT_MS}ms` : error instanceof Error ? error.message : "unknown fetch error";
    const evidence = await recordTaxAuthorityLookup(client, { tenantId, connectionId: dispatchInfo.connectionId, taxCode, asOfDate, status: "failed", requestPayload, errorMessage, actorAuthUserId, actorLabel });
    return { success: false, evidenceId: evidence.id, rateValue: null, errorMessage };
  } finally {
    clearTimeout(timeoutHandle);
  }

  if (response.status < 200 || response.status >= 300) {
    const errorMessage = `tax authority provider responded with HTTP ${response.status}`;
    const evidence = await recordTaxAuthorityLookup(client, { tenantId, connectionId: dispatchInfo.connectionId, taxCode, asOfDate, status: "failed", requestPayload, errorMessage, actorAuthUserId, actorLabel });
    return { success: false, evidenceId: evidence.id, rateValue: null, errorMessage };
  }

  let body: { rateValue?: unknown };
  try {
    body = await response.json();
  } catch {
    const errorMessage = "tax authority provider returned a non-JSON response body";
    const evidence = await recordTaxAuthorityLookup(client, { tenantId, connectionId: dispatchInfo.connectionId, taxCode, asOfDate, status: "failed", requestPayload, errorMessage, actorAuthUserId, actorLabel });
    return { success: false, evidenceId: evidence.id, rateValue: null, errorMessage };
  }

  const rateValue = typeof body.rateValue === "number" ? body.rateValue : null;
  if (rateValue === null) {
    const errorMessage = "tax authority provider response is missing rateValue";
    const evidence = await recordTaxAuthorityLookup(client, { tenantId, connectionId: dispatchInfo.connectionId, taxCode, asOfDate, status: "failed", requestPayload, errorMessage, actorAuthUserId, actorLabel });
    return { success: false, evidenceId: evidence.id, rateValue: null, errorMessage };
  }

  const evidence = await recordTaxAuthorityLookup(client, {
    tenantId,
    connectionId: dispatchInfo.connectionId,
    taxCode,
    asOfDate,
    status: "success",
    requestPayload,
    responsePayload: { rateValue },
    providerUnitCostAmount: placeholderCost(),
    currency: "USD",
    actorAuthUserId,
    actorLabel,
  });

  return { success: true, evidenceId: evidence.id, rateValue, errorMessage: null };
}
