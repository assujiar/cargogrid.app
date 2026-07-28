/**
 * ePOD Capture and Review read queries (OPS-177, CG-S8-OPS-011). A thin, typed
 * wrapper around app.get_epod_capture_history.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { parseEpodCapture, GetEpodCaptureHistoryInputSchema, type EpodCapture, type GetEpodCaptureHistoryInput } from "../contracts/epod-capture-review/epod-capture-review.ts";

export type EpodCaptureReviewQueryClient = Pick<SupabaseClient, "rpc">;

export class EpodCaptureReviewQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "EpodCaptureReviewQueryError";
  }
}

/** Authority-gated (OPS:View + record scope) full version lineage for a shipment, oldest-first -- every rejected/revised version remains, never trimmed. */
export async function getEpodCaptureHistory(client: EpodCaptureReviewQueryClient, input: GetEpodCaptureHistoryInput): Promise<EpodCapture[]> {
  const parsedInput = GetEpodCaptureHistoryInputSchema.parse(input);
  const { data, error } = await client.rpc("get_epod_capture_history", {
    p_shipment_order_id: parsedInput.shipmentOrderId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
  });
  if (error) {
    throw new EpodCaptureReviewQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new EpodCaptureReviewQueryError("get_epod_capture_history returned a non-array result");
  }
  return data.map((row: Record<string, unknown>) => parseEpodCapture(row));
}
