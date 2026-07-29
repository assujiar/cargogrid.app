/**
 * Idempotent Posting read query (FIN-208, CG-S9-FIN-019). A thin, typed
 * wrapper around app.get_finance_idempotency_claim
 * (supabase/migrations/20260729220000_create_finance_idempotent_posting.sql)
 * -- lets a client distinguish processing/completed/failed for a stable
 * key it already submitted, without silently retrying.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { parseFinanceIdempotencyClaim, type FinanceIdempotencyClaim } from "../contracts/idempotency/idempotency.ts";

export type IdempotencyQueryRpcClient = Pick<SupabaseClient, "rpc">;

export class IdempotencyQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "IdempotencyQueryError";
  }
}

/** FIN:View-gated. Raises finance_idempotency_claim_not_found (via rpc error) rather than returning null for an unknown key. */
export async function getFinanceIdempotencyClaim(
  client: IdempotencyQueryRpcClient,
  input: { tenantId: string; scope: string; idempotencyKey: string; actorAuthUserId: string },
): Promise<FinanceIdempotencyClaim> {
  const { data, error } = await client.rpc("get_finance_idempotency_claim", {
    p_tenant_id: input.tenantId,
    p_scope: input.scope,
    p_idempotency_key: input.idempotencyKey,
    p_actor_auth_user_id: input.actorAuthUserId,
  });
  if (error) {
    throw new IdempotencyQueryError(error.message);
  }
  if (!data || typeof data !== "object") {
    throw new IdempotencyQueryError("get_finance_idempotency_claim returned no row");
  }
  return parseFinanceIdempotencyClaim(data as Record<string, unknown>);
}
