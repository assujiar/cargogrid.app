/**
 * The real AI provider dispatch client (IAE-019, Prompt 347) -- the NINTH
 * real outbound HTTP client in this repository. Mirrors IAE-015's own
 * geocode client shape exactly: a live, SYNCHRONOUS request/response call
 * (prompt in, output out), never `app.jobs`-queued.
 *
 * This is the governance FOUNDATION every later AI-assisted capability
 * (Prompt 348+) calls -- it never decides what a prompt should contain or
 * what a caller should do with the output. It only: (1) records a real,
 * governed request BEFORE dispatching (app.request_ai_governed_action),
 * (2) makes the real outbound call, (3) records the real outcome
 * (app.record_ai_governed_request_outcome). The output is evidence, never
 * applied to any domain table by this module -- the caller reads the
 * returned request row and decides what to do with it through its own,
 * unmodified domain RPCs, gating on human approval first when RPD-021
 * requires it (before financial/legal posting or critical status changes).
 *
 * Reuses ../webhooks/ssrf-guard.server.ts's checkWebhookDispatchUrlIsSafe
 * directly, the same proactive reuse every prior real outbound client in
 * this repository has already established.
 */

import { getAiGovernedDispatchInfo, getAiGovernedCredential, type AiGovernanceQueryRpcClient } from "../../server/queries/ai-governance.ts";
import { requestAiGovernedAction, recordAiGovernedRequestOutcome, type AiGovernanceMutationRpcClient } from "../../server/mutations/ai-governance.ts";
import type { AiConfidenceLabel } from "../../server/contracts/ai-governance/ai-governance.ts";
import { checkWebhookDispatchUrlIsSafe, type SsrfCheckResult } from "../webhooks/ssrf-guard.server.ts";

const REQUEST_TIMEOUT_MS = 30_000;

export type AiGovernanceDispatchUrlSafetyChecker = (rawUrl: string) => Promise<SsrfCheckResult>;

export type DispatchAiGovernedRequestRpcClient = AiGovernanceQueryRpcClient & AiGovernanceMutationRpcClient;

export interface DispatchAiGovernedRequestResult {
  readonly requestId: string;
  readonly success: boolean;
  readonly outputPayload: Record<string, unknown> | null;
  readonly confidenceLabel: AiConfidenceLabel | null;
  readonly errorMessage: string | null;
}

interface DispatchAiGovernedRequestOptions {
  readonly tenantId: string;
  readonly actorAuthUserId: string;
  readonly actorLabel: string;
  readonly featureCode: string;
  readonly correlationRecordType: string | null;
  readonly correlationRecordId: string | null;
  readonly promptPayload: Record<string, unknown>;
}

function placeholderCost(payloadLength: number): number {
  return Math.round((0.02 + payloadLength * 0.00004) * 10000) / 10000;
}

/**
 * Real, synchronous AI dispatch. Never throws for a delivery-side failure
 * (no connection configured, HTTP error, timeout, unsafe URL) -- those are
 * real, expected outcomes recorded via app.record_ai_governed_request_
 * outcome and returned as `success: false`. The governed request row is
 * ALWAYS created first (app.request_ai_governed_action) regardless of what
 * happens next, so every real dispatch attempt is real, queryable evidence.
 */
export async function dispatchAiGovernedRequest(client: DispatchAiGovernedRequestRpcClient, options: DispatchAiGovernedRequestOptions, checkUrlSafety: AiGovernanceDispatchUrlSafetyChecker = checkWebhookDispatchUrlIsSafe): Promise<DispatchAiGovernedRequestResult> {
  const { tenantId, actorAuthUserId, actorLabel, featureCode, correlationRecordType, correlationRecordId, promptPayload } = options;

  const dispatchInfo = await getAiGovernedDispatchInfo(client, tenantId, actorAuthUserId);
  if (!dispatchInfo || dispatchInfo.connectionStatus !== "active") {
    throw new Error("no active openai_multimodal connection configured for this tenant -- refusing to record a governed request with no real connection to dispatch through");
  }

  const request = await requestAiGovernedAction(client, {
    tenantId,
    connectionId: dispatchInfo.connectionId,
    featureCode,
    correlationRecordType,
    correlationRecordId,
    promptPayload,
    actorAuthUserId,
    actorLabel,
  });

  const apiUrl = typeof dispatchInfo.connectionConfig.apiUrl === "string" ? dispatchInfo.connectionConfig.apiUrl : null;
  if (!apiUrl) {
    const errorMessage = "openai_multimodal connection has no apiUrl configured";
    await recordAiGovernedRequestOutcome(client, { requestId: request.id, status: "failed", errorMessage, actorAuthUserId, actorLabel });
    return { requestId: request.id, success: false, outputPayload: null, confidenceLabel: null, errorMessage };
  }

  const urlSafety = await checkUrlSafety(apiUrl);
  if (!urlSafety.safe) {
    const errorMessage = `refusing to dispatch: ${urlSafety.reason ?? "provider apiUrl failed the delivery-time safety check"}`;
    await recordAiGovernedRequestOutcome(client, { requestId: request.id, status: "failed", errorMessage, actorAuthUserId, actorLabel });
    return { requestId: request.id, success: false, outputPayload: null, confidenceLabel: null, errorMessage };
  }

  const credential = await getAiGovernedCredential(client, dispatchInfo.connectionId);
  if (!credential) {
    const errorMessage = "openai_multimodal connection has no stored credential";
    await recordAiGovernedRequestOutcome(client, { requestId: request.id, status: "failed", errorMessage, actorAuthUserId, actorLabel });
    return { requestId: request.id, success: false, outputPayload: null, confidenceLabel: null, errorMessage };
  }

  const requestPayload = JSON.stringify(promptPayload);
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
    await recordAiGovernedRequestOutcome(client, { requestId: request.id, status: "failed", errorMessage, actorAuthUserId, actorLabel });
    return { requestId: request.id, success: false, outputPayload: null, confidenceLabel: null, errorMessage };
  } finally {
    clearTimeout(timeoutHandle);
  }

  if (response.status < 200 || response.status >= 300) {
    const errorMessage = `AI provider responded with HTTP ${response.status}`;
    await recordAiGovernedRequestOutcome(client, { requestId: request.id, status: "failed", errorMessage, actorAuthUserId, actorLabel });
    return { requestId: request.id, success: false, outputPayload: null, confidenceLabel: null, errorMessage };
  }

  let body: { output?: unknown; confidenceLabel?: unknown; model?: unknown };
  try {
    body = await response.json();
  } catch {
    const errorMessage = "AI provider returned a non-JSON response body";
    await recordAiGovernedRequestOutcome(client, { requestId: request.id, status: "failed", errorMessage, actorAuthUserId, actorLabel });
    return { requestId: request.id, success: false, outputPayload: null, confidenceLabel: null, errorMessage };
  }

  const outputPayload = body.output && typeof body.output === "object" ? (body.output as Record<string, unknown>) : null;
  if (!outputPayload) {
    const errorMessage = "AI provider response is missing an output object";
    await recordAiGovernedRequestOutcome(client, { requestId: request.id, status: "failed", errorMessage, actorAuthUserId, actorLabel });
    return { requestId: request.id, success: false, outputPayload: null, confidenceLabel: null, errorMessage };
  }

  const confidenceLabel: AiConfidenceLabel | null = body.confidenceLabel === "high" || body.confidenceLabel === "medium" || body.confidenceLabel === "low" ? body.confidenceLabel : null;
  // Tier C fix: record the model the provider actually reports serving, not
  // a hardcoded adapter-code literal -- falls back to the adapter code only
  // when the provider's own response omits a model field entirely.
  const modelVersion = typeof body.model === "string" && body.model.length > 0 ? body.model : "openai-multimodal";

  await recordAiGovernedRequestOutcome(client, {
    requestId: request.id,
    status: "succeeded",
    outputPayload,
    confidenceLabel,
    modelVersion,
    providerUnitCostAmount: placeholderCost(requestPayload.length),
    currency: "USD",
    actorAuthUserId,
    actorLabel,
  });

  return { requestId: request.id, success: true, outputPayload, confidenceLabel, errorMessage: null };
}
