/**
 * Period Lock and Governed Reopen read queries (FIN-207, CG-S9-FIN-018).
 * Thin, typed wrappers around app.list_finance_period_locks /
 * app.get_finance_period_lock_events
 * (supabase/migrations/20260729210000_create_finance_period_lock.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { parseFinancePeriodLock, parseFinancePeriodLockEvent, type FinancePeriodLock, type FinancePeriodLockEvent } from "../contracts/period-lock/period-lock.ts";

export type PeriodLockQueryRpcClient = Pick<SupabaseClient, "rpc">;

export class PeriodLockQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "PeriodLockQueryError";
  }
}

/** FIN:View-gated. Bounded (200-row), server-filtered list, most-recent first. */
export async function listFinancePeriodLocks(
  client: PeriodLockQueryRpcClient,
  input: { tenantId: string; companyId: string | null; periodId: string | null; actorAuthUserId: string },
): Promise<FinancePeriodLock[]> {
  const { data, error } = await client.rpc("list_finance_period_locks", {
    p_tenant_id: input.tenantId,
    p_company_id: input.companyId,
    p_period_id: input.periodId,
    p_actor_auth_user_id: input.actorAuthUserId,
  });
  if (error) {
    throw new PeriodLockQueryError(error.message);
  }
  const rows = Array.isArray(data) ? data : [];
  return rows.map((row) => parseFinancePeriodLock(row as Record<string, unknown>));
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
