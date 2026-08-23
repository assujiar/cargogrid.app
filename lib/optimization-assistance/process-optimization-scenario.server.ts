/**
 * Optimization Assistance orchestration (IAE-023, Prompt 351). The FOURTH
 * real consumer of IAE-019's own `dispatchAiGovernedRequest` -- reused
 * completely unmodified (migration design decision 6). This module's only
 * job is to dispatch a real, governed request over the caller-supplied
 * input snapshot/constraint set and sync the linked
 * app.optimization_scenarios row to the real outcome either way, mirroring
 * processOcrDocumentJob (IAE-021)/processEtaPrediction (IAE-022)'s own
 * "always sync, success or failure" shape.
 *
 * Must be called with a service-role client: dispatchAiGovernedRequest's own
 * internal record_ai_governed_request_outcome call is granted to
 * service_role only (IAE-019).
 */

import { recordOptimizationScenarioOutcome, type OptimizationAssistanceMutationRpcClient } from "../../server/mutations/optimization-assistance.ts";
import type { OptimizationScenario } from "../../server/contracts/optimization-assistance/optimization-assistance.ts";
import { dispatchAiGovernedRequest, type DispatchAiGovernedRequestRpcClient, type AiGovernanceDispatchUrlSafetyChecker } from "../ai-governance/dispatch-ai-governed-request.server.ts";

export type ProcessOptimizationScenarioClient = DispatchAiGovernedRequestRpcClient & OptimizationAssistanceMutationRpcClient;

export interface ProcessOptimizationScenarioOptions {
  readonly tenantId: string;
  readonly scenarioId: string;
  readonly inputSnapshot: Record<string, unknown>;
  readonly constraintSet: Record<string, unknown>;
  readonly actorAuthUserId: string;
  readonly actorLabel: string;
}

export interface ProcessOptimizationScenarioResult {
  readonly requestId: string;
  readonly success: boolean;
  readonly scenario: OptimizationScenario;
  readonly errorMessage: string | null;
}

/**
 * Real, synchronous end-to-end flow: dispatch the caller-supplied input
 * snapshot/constraint set -> sync the scenario's own status either way.
 * Never throws for a delivery-side failure -- dispatchAiGovernedRequest
 * itself already turns those into a real, recorded `failed` outcome and a
 * `success: false` result, which this function passes through after syncing
 * the scenario to its own terminal `failed` status. Throws only for
 * whatever dispatchAiGovernedRequest itself still throws for (no active
 * connection configured at all) or a genuine precondition failure surfaced
 * by record_optimization_scenario_outcome.
 */
export async function processOptimizationScenario(
  client: ProcessOptimizationScenarioClient,
  options: ProcessOptimizationScenarioOptions,
  checkUrlSafety?: AiGovernanceDispatchUrlSafetyChecker,
): Promise<ProcessOptimizationScenarioResult> {
  const { tenantId, scenarioId, inputSnapshot, constraintSet, actorAuthUserId, actorLabel } = options;

  const dispatch = await dispatchAiGovernedRequest(
    client,
    {
      tenantId,
      actorAuthUserId,
      actorLabel,
      featureCode: "optimization_assistance",
      correlationRecordType: "optimization_scenario",
      correlationRecordId: scenarioId,
      promptPayload: { inputSnapshot, constraintSet },
    },
    checkUrlSafety,
  );

  const scenario = await recordOptimizationScenarioOutcome(client, {
    scenarioId,
    aiGovernedRequestId: dispatch.requestId,
    actorAuthUserId,
    actorLabel,
  });

  return { requestId: dispatch.requestId, success: dispatch.success, scenario, errorMessage: dispatch.errorMessage };
}
