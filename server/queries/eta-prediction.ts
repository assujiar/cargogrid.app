/**
 * Predictive ETA queries (IAE-022, Prompt 350). Thin, typed wrappers around
 * app.get_eta_prediction / app.list_eta_predictions_for_shipment
 * (supabase/migrations/20260806100000_create_intelligence_predictive_eta.sql).
 */

import {
  GetEtaPredictionInputSchema,
  ListEtaPredictionsForShipmentInputSchema,
  parseEtaPredictionDetail,
  parseEtaPredictionSummary,
  type GetEtaPredictionInput,
  type ListEtaPredictionsForShipmentInput,
  type EtaPredictionDetail,
  type EtaPredictionSummary,
} from "../contracts/eta-prediction/eta-prediction.ts";

export interface EtaPredictionQueryRpcClient {
  rpc(fn: "get_eta_prediction" | "list_eta_predictions_for_shipment", args: Record<string, unknown>): Promise<{ data: unknown; error: { message: string } | null }>;
}

export class EtaPredictionQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "EtaPredictionQueryError";
  }
}

/** Authority: AI:View. Returns null if the prediction does not exist (or belongs to a different tenant than p_tenant_id). */
export async function getEtaPrediction(client: EtaPredictionQueryRpcClient, input: GetEtaPredictionInput): Promise<EtaPredictionDetail | null> {
  const parsedInput = GetEtaPredictionInputSchema.parse(input);
  const { data, error } = await client.rpc("get_eta_prediction", {
    p_prediction_id: parsedInput.predictionId,
    p_tenant_id: parsedInput.tenantId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
  });
  if (error) {
    throw new EtaPredictionQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    return null;
  }
  return parseEtaPredictionDetail(row as Record<string, unknown>);
}

/** Authority: AI:View. */
export async function listEtaPredictionsForShipment(client: EtaPredictionQueryRpcClient, input: ListEtaPredictionsForShipmentInput): Promise<EtaPredictionSummary[]> {
  const parsedInput = ListEtaPredictionsForShipmentInputSchema.parse(input);
  const { data, error } = await client.rpc("list_eta_predictions_for_shipment", {
    p_tenant_id: parsedInput.tenantId,
    p_shipment_order_id: parsedInput.shipmentOrderId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_limit: parsedInput.limit,
  });
  if (error) {
    throw new EtaPredictionQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new EtaPredictionQueryError("list_eta_predictions_for_shipment returned a non-array result");
  }
  return data.map((row) => parseEtaPredictionSummary(row as Record<string, unknown>));
}
