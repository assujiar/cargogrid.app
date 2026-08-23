/**
 * Predictive ETA orchestration (IAE-022, Prompt 350). The THIRD real
 * consumer of IAE-019's own `dispatchAiGovernedRequest` -- reused
 * completely unmodified (migration design decision 7). This module's only
 * job is to dispatch a real, governed request over the caller-supplied
 * feature snapshot (canonical shipment/tracking fields only, never a
 * fabricated one) and sync the linked app.eta_predictions row to the real
 * outcome either way -- mirroring processOcrDocumentJob (IAE-021)'s own
 * "always sync, success or failure" shape, not generateAiQuotationSuggestion
 * (IAE-020)'s "only track on success" shape, since app.eta_predictions has
 * its own `failed` terminal status for this.
 *
 * Must be called with a service-role client: dispatchAiGovernedRequest's own
 * internal record_ai_governed_request_outcome call is granted to
 * service_role only (IAE-019).
 */

import { recordEtaPredictionOutcome, type EtaPredictionMutationRpcClient } from "../../server/mutations/eta-prediction.ts";
import type { EtaPrediction } from "../../server/contracts/eta-prediction/eta-prediction.ts";
import { dispatchAiGovernedRequest, type DispatchAiGovernedRequestRpcClient, type AiGovernanceDispatchUrlSafetyChecker } from "../ai-governance/dispatch-ai-governed-request.server.ts";

export type ProcessEtaPredictionClient = DispatchAiGovernedRequestRpcClient & EtaPredictionMutationRpcClient;

export interface ProcessEtaPredictionOptions {
  readonly tenantId: string;
  readonly predictionId: string;
  readonly shipmentOrderId: string;
  readonly featureSnapshot: Record<string, unknown>;
  readonly actorAuthUserId: string;
  readonly actorLabel: string;
}

export interface ProcessEtaPredictionResult {
  readonly requestId: string;
  readonly success: boolean;
  readonly prediction: EtaPrediction;
  readonly errorMessage: string | null;
}

/**
 * Real, synchronous end-to-end flow: dispatch the caller-supplied feature
 * snapshot -> sync the prediction's own status either way. Never throws for
 * a delivery-side failure -- dispatchAiGovernedRequest itself already turns
 * those into a real, recorded `failed` outcome and a `success: false`
 * result, which this function passes through after syncing the prediction
 * to its own terminal `failed` status (predicted_eta stays null). Throws
 * only for whatever dispatchAiGovernedRequest itself still throws for (no
 * active connection configured at all) or a genuine precondition failure
 * surfaced by record_eta_prediction_outcome (e.g. a wrong/foreign governed
 * request id).
 */
export async function processEtaPrediction(client: ProcessEtaPredictionClient, options: ProcessEtaPredictionOptions, checkUrlSafety?: AiGovernanceDispatchUrlSafetyChecker): Promise<ProcessEtaPredictionResult> {
  const { tenantId, predictionId, shipmentOrderId, featureSnapshot, actorAuthUserId, actorLabel } = options;

  const dispatch = await dispatchAiGovernedRequest(
    client,
    {
      tenantId,
      actorAuthUserId,
      actorLabel,
      featureCode: "predictive_eta",
      correlationRecordType: "shipment_order",
      correlationRecordId: shipmentOrderId,
      promptPayload: featureSnapshot,
    },
    checkUrlSafety,
  );

  const prediction = await recordEtaPredictionOutcome(client, {
    predictionId,
    aiGovernedRequestId: dispatch.requestId,
    actorAuthUserId,
    actorLabel,
  });

  return { requestId: dispatch.requestId, success: dispatch.success, prediction, errorMessage: dispatch.errorMessage };
}
