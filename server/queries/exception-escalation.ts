/**
 * Exception and Escalation read queries (OPS-174, CG-S8-OPS-008). Thin, typed
 * wrappers around app.get_exception_escalation_history and
 * app.list_shipment_exceptions. CG-AUDIT-2026-09-02 O1 remediation (cluster 3
 * batch 4,
 * 20260911040000_close_o1_query_layer_cluster3_batch4_shipment_order_capacity_exceptions.sql):
 * the field-masked app.exceptions_directory read also now goes through a
 * thin, security-invoker RPC wrapper (app is not exposed to PostgREST, so a
 * `.from()` call against it has never worked in production).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseExceptionEscalation,
  parseExceptionDirectoryRow,
  GetExceptionEscalationHistoryInputSchema,
  type ExceptionEscalation,
  type ExceptionDirectoryRow,
  type GetExceptionEscalationHistoryInput,
} from "../contracts/exception-escalation/exception-escalation.ts";

export type ExceptionEscalationQueryRpcClient = Pick<SupabaseClient, "rpc">;
export type ExceptionEscalationQueryTableClient = Pick<SupabaseClient, "rpc">;

export class ExceptionEscalationQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ExceptionEscalationQueryError";
  }
}

/** The full, ordered (oldest-first) escalation history for one exception -- authority-gated. */
export async function getExceptionEscalationHistory(
  client: ExceptionEscalationQueryRpcClient,
  input: GetExceptionEscalationHistoryInput,
): Promise<ExceptionEscalation[]> {
  const parsedInput = GetExceptionEscalationHistoryInputSchema.parse(input);
  const { data, error } = await client.rpc("get_exception_escalation_history", {
    p_exception_id: parsedInput.exceptionId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
  });
  if (error) {
    throw new ExceptionEscalationQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new ExceptionEscalationQueryError("get_exception_escalation_history returned a non-array result");
  }
  return data.map((row: Record<string, unknown>) => parseExceptionEscalation(row));
}

/** The field-masked list of exceptions for one Shipment Order, RLS-scoped, ordered newest-first. */
export async function listShipmentExceptions(client: ExceptionEscalationQueryTableClient, shipmentOrderId: string): Promise<ExceptionDirectoryRow[]> {
  const { data, error } = await client.rpc("list_shipment_exceptions", { p_shipment_order_id: shipmentOrderId });
  if (error) {
    throw new ExceptionEscalationQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseExceptionDirectoryRow(row));
}
