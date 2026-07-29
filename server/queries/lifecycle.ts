/**
 * Draft-versus-Posted State Control read query (FIN-205, CG-S9-FIN-016).
 * Thin, typed wrapper around app.get_finance_lifecycle_record_state
 * (supabase/migrations/20260729190000_create_finance_lifecycle_state_control.sql),
 * the one shared cross-domain lifecycle-state reader for invoice/
 * vendor_bill/receipt/settlement/subledger_batch/journal. No mutations file --
 * this checkpoint adds no new mutation surface, only a shared read.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseFinanceLifecycleRecordState,
  type FinanceLifecycleEntityType,
  type FinanceLifecycleRecordState,
} from "../contracts/lifecycle/lifecycle.ts";

export type LifecycleQueryRpcClient = Pick<SupabaseClient, "rpc">;

export class LifecycleQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "LifecycleQueryError";
  }
}

/** FIN:View-gated (composes each domain's own check_finance_*_authority). */
export async function getFinanceLifecycleRecordState(
  client: LifecycleQueryRpcClient,
  input: { tenantId: string; entityType: FinanceLifecycleEntityType; recordId: string; actorAuthUserId: string },
): Promise<FinanceLifecycleRecordState> {
  const { data, error } = await client.rpc("get_finance_lifecycle_record_state", {
    p_tenant_id: input.tenantId,
    p_entity_type: input.entityType,
    p_record_id: input.recordId,
    p_actor_auth_user_id: input.actorAuthUserId,
  });
  if (error) {
    throw new LifecycleQueryError(error.message);
  }
  if (!data || typeof data !== "object") {
    throw new LifecycleQueryError("get_finance_lifecycle_record_state returned no result");
  }
  return parseFinanceLifecycleRecordState(data as Record<string, unknown>);
}
