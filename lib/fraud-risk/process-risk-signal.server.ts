/**
 * Fraud and Risk Assistance orchestration (IAE-024, Prompt 352). The FIFTH
 * real consumer of IAE-019's own `dispatchAiGovernedRequest` -- reused
 * completely unmodified (migration design decision 7). This module's only
 * job is to dispatch a real, governed request over the caller-supplied
 * input snapshot and sync the linked app.risk_signals row to the real
 * outcome either way, mirroring processOcrDocumentJob (IAE-021)/
 * processEtaPrediction (IAE-022)/processOptimizationScenario (IAE-023)'s
 * own "always sync, success or failure" shape.
 *
 * Must be called with a service-role client: dispatchAiGovernedRequest's own
 * internal record_ai_governed_request_outcome call is granted to
 * service_role only (IAE-019).
 */

import { recordRiskSignalOutcome, type FraudRiskMutationRpcClient } from "../../server/mutations/fraud-risk.ts";
import type { RiskSignal } from "../../server/contracts/fraud-risk/fraud-risk.ts";
import { dispatchAiGovernedRequest, type DispatchAiGovernedRequestRpcClient, type AiGovernanceDispatchUrlSafetyChecker } from "../ai-governance/dispatch-ai-governed-request.server.ts";

export type ProcessRiskSignalClient = DispatchAiGovernedRequestRpcClient & FraudRiskMutationRpcClient;

export interface ProcessRiskSignalOptions {
  readonly tenantId: string;
  readonly signalId: string;
  readonly entityType: string;
  readonly entityId: string;
  readonly inputSnapshot: Record<string, unknown>;
  readonly actorAuthUserId: string;
  readonly actorLabel: string;
}

export interface ProcessRiskSignalResult {
  readonly requestId: string;
  readonly success: boolean;
  readonly signal: RiskSignal;
  readonly errorMessage: string | null;
}

/**
 * Real, synchronous end-to-end flow: dispatch the caller-supplied input
 * snapshot -> sync the signal's own status either way. Never throws for a
 * delivery-side failure -- dispatchAiGovernedRequest itself already turns
 * those into a real, recorded `failed` outcome and a `success: false`
 * result, which this function passes through after syncing the signal to
 * its own terminal `failed` status (score/band stay null). Throws only for
 * whatever dispatchAiGovernedRequest itself still throws for (no active
 * connection configured at all) or a genuine precondition failure surfaced
 * by record_risk_signal_outcome.
 */
export async function processRiskSignal(client: ProcessRiskSignalClient, options: ProcessRiskSignalOptions, checkUrlSafety?: AiGovernanceDispatchUrlSafetyChecker): Promise<ProcessRiskSignalResult> {
  const { tenantId, signalId, entityType, entityId, inputSnapshot, actorAuthUserId, actorLabel } = options;

  const dispatch = await dispatchAiGovernedRequest(
    client,
    {
      tenantId,
      actorAuthUserId,
      actorLabel,
      featureCode: "fraud_risk_assistance",
      correlationRecordType: entityType,
      correlationRecordId: entityId,
      promptPayload: inputSnapshot,
    },
    checkUrlSafety,
  );

  const signal = await recordRiskSignalOutcome(client, {
    signalId,
    aiGovernedRequestId: dispatch.requestId,
    actorAuthUserId,
    actorLabel,
  });

  return { requestId: dispatch.requestId, success: dispatch.success, signal, errorMessage: dispatch.errorMessage };
}
