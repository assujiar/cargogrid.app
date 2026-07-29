/**
 * Idempotent Posting contract (FIN-208, CG-S9-FIN-019). Mirrors
 * supabase/migrations/20260729220000_create_finance_idempotent_posting.sql's
 * app.finance_idempotency_claims shape and its read RPC.
 */

import { z } from "zod";

export const FINANCE_IDEMPOTENCY_CLAIM_STATUSES = ["claimed", "completed", "failed"] as const;
export const FinanceIdempotencyClaimStatusSchema = z.enum(FINANCE_IDEMPOTENCY_CLAIM_STATUSES);
export type FinanceIdempotencyClaimStatus = z.infer<typeof FinanceIdempotencyClaimStatusSchema>;

export const FinanceIdempotencyClaimSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  scope: z.string(),
  idempotencyKey: z.string(),
  requestFingerprint: z.string(),
  status: FinanceIdempotencyClaimStatusSchema,
  resultEntityType: z.string().nullable(),
  resultEntityId: z.string().uuid().nullable(),
  errorMessage: z.string().nullable(),
  claimedBy: z.string().nullable(),
  claimedAt: z.string(),
  completedAt: z.string().nullable(),
  createdAt: z.string(),
});
export type FinanceIdempotencyClaim = z.infer<typeof FinanceIdempotencyClaimSchema>;

/** Maps a raw app.finance_idempotency_claims row (snake_case) to this contract's camelCase shape. */
export function parseFinanceIdempotencyClaim(row: Record<string, unknown>): FinanceIdempotencyClaim {
  return FinanceIdempotencyClaimSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    scope: row.scope,
    idempotencyKey: row.idempotency_key,
    requestFingerprint: row.request_fingerprint,
    status: row.status,
    resultEntityType: row.result_entity_type,
    resultEntityId: row.result_entity_id,
    errorMessage: row.error_message,
    claimedBy: row.claimed_by,
    claimedAt: row.claimed_at,
    completedAt: row.completed_at,
    createdAt: row.created_at,
  });
}
