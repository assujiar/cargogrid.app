/**
 * Transaction Lineage mutation primitives (OPS-184, CG-S8-OPS-018). Thin, typed
 * wrappers around the RPCs in
 * supabase/migrations/20260728170000_create_operations_transaction_lineage.sql.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  RecordTransactionLineageOverrideInputSchema,
  BackfillTransactionLineageInputSchema,
  parseTransactionLineageEdge,
  type RecordTransactionLineageOverrideInput,
  type BackfillTransactionLineageInput,
  type TransactionLineageEdge,
} from "../contracts/transaction-lineage/transaction-lineage.ts";

export type TransactionLineageMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const TRANSACTION_LINEAGE_KNOWN_MUTATION_ERROR_CODES = [
  "transaction_lineage_override_reason_required",
  "transaction_lineage_edge_already_recorded",
  "insufficient_authority",
] as const;
type KnownTransactionLineageMutationErrorCode = (typeof TRANSACTION_LINEAGE_KNOWN_MUTATION_ERROR_CODES)[number];
export type TransactionLineageMutationErrorCode = KnownTransactionLineageMutationErrorCode | "mutation_failed" | "invalid_response";

export class TransactionLineageMutationError extends Error {
  readonly code: TransactionLineageMutationErrorCode;

  constructor(code: TransactionLineageMutationErrorCode, message: string) {
    super(message);
    this.name = "TransactionLineageMutationError";
    this.code = code;
  }
}

function classifyError(message: string): TransactionLineageMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (TRANSACTION_LINEAGE_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownTransactionLineageMutationErrorCode) : "mutation_failed";
}

/** The one authorized way to add a lineage edge outside the six automatic triggers -- OPS:Override-gated, reason mandatory, rejects (transaction_lineage_edge_already_recorded) a pairing that already exists rather than silently doing nothing. */
export async function recordTransactionLineageOverride(client: TransactionLineageMutationRpcClient, input: RecordTransactionLineageOverrideInput): Promise<TransactionLineageEdge> {
  const parsedInput = RecordTransactionLineageOverrideInputSchema.parse(input);
  const { data, error } = await client.rpc("record_transaction_lineage_override", {
    p_tenant_id: parsedInput.tenantId,
    p_relation_type: parsedInput.relationType,
    p_source_type: parsedInput.sourceType,
    p_source_id: parsedInput.sourceId,
    p_target_type: parsedInput.targetType,
    p_target_id: parsedInput.targetId,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new TransactionLineageMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new TransactionLineageMutationError("invalid_response", "record_transaction_lineage_override returned no row");
  }
  return parseTransactionLineageEdge(data as Record<string, unknown>);
}

/** Idempotent brownfield reconciliation -- safe to call repeatedly (already-captured rows are silently skipped), OPS:Override-gated, returns the count of edges newly captured this call. */
export async function backfillTransactionLineage(client: TransactionLineageMutationRpcClient, input: BackfillTransactionLineageInput): Promise<number> {
  const parsedInput = BackfillTransactionLineageInputSchema.parse(input);
  const { data, error } = await client.rpc("backfill_transaction_lineage", {
    p_tenant_id: parsedInput.tenantId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new TransactionLineageMutationError(classifyError(error.message), error.message);
  }
  if (typeof data !== "number") {
    throw new TransactionLineageMutationError("invalid_response", "backfill_transaction_lineage returned a non-numeric result");
  }
  return data;
}
