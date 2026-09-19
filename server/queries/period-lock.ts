/**
 * Period Lock and Governed Reopen read queries (FIN-207, CG-S9-FIN-018).
 * Thin, typed wrappers around app.list_finance_period_locks /
 * app.get_finance_period_lock_events
 * (supabase/migrations/20260729210000_create_finance_period_lock.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { parseFinancePeriodLock, parseFinancePeriodLockEvent, type FinancePeriodLock, type FinancePeriodLockEvent } from "../contracts/period-lock/period-lock.ts";
import { BOUNDED_LIST_LIMIT } from "./bounded-list.ts";

export type PeriodLockQueryRpcClient = Pick<SupabaseClient, "rpc">;

export class PeriodLockQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "PeriodLockQueryError";
  }
}

/** FIN:View-gated. Bounded (200-row), server-filtered list, most-recent first. */
/** CG-AUDIT-2026-09-02 F3: `afterId`/`limit` optional and additive -- see server/queries/accounts-receivable.ts#listFinanceArOpenItems's own header comment for the full rationale. */
export async function listFinancePeriodLocks(
  client: PeriodLockQueryRpcClient,
  input: { tenantId: string; companyId: string | null; periodId: string | null; actorAuthUserId: string; limit?: number; afterId?: string | null },
): Promise<FinancePeriodLock[]> {
  const limit = input.limit ?? BOUNDED_LIST_LIMIT;
  const { data, error } = await client.rpc("list_finance_period_locks", {
    p_tenant_id: input.tenantId,
    p_company_id: input.companyId,
    p_period_id: input.periodId,
    p_actor_auth_user_id: input.actorAuthUserId,
    p_limit: limit,
    p_after_id: input.afterId ?? null,
  });
  if (error) {
    throw new PeriodLockQueryError(error.message);
  }
  const rows = Array.isArray(data) ? data : [];
  return rows.slice(0, limit).map((row) => parseFinancePeriodLock(row as Record<string, unknown>));
}

/** FIN:View-gated. The full close/reopen/re-lock history for one lock, oldest first. */
export async function getFinancePeriodLockEvents(
  client: PeriodLockQueryRpcClient,
  input: { lockId: string; actorAuthUserId: string },
): Promise<FinancePeriodLockEvent[]> {
  const { data, error } = await client.rpc("get_finance_period_lock_events", {
    p_lock_id: input.lockId,
    p_actor_auth_user_id: input.actorAuthUserId,
  });
  if (error) {
    throw new PeriodLockQueryError(error.message);
  }
  const rows = Array.isArray(data) ? data : [];
  return rows.map((row) => parseFinancePeriodLockEvent(row as Record<string, unknown>));
}
