/**
 * Period Lock and Governed Reopen mutation primitives (FIN-207,
 * CG-S9-FIN-018). Thin, typed wrappers around app.lock_finance_period /
 * app.request_finance_period_reopen / app.approve_finance_period_reopen /
 * app.relock_finance_period
 * (supabase/migrations/20260729210000_create_finance_period_lock.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  LockFinancePeriodInputSchema,
  RequestFinancePeriodReopenInputSchema,
  ApproveFinancePeriodReopenInputSchema,
  FinancePeriodLockLifecycleInputSchema,
  parseFinancePeriodLock,
  type LockFinancePeriodInput,
  type RequestFinancePeriodReopenInput,
  type ApproveFinancePeriodReopenInput,
  type FinancePeriodLockLifecycleInput,
  type FinancePeriodLock,
} from "../contracts/period-lock/period-lock.ts";
import { resolveRequestClientIp } from "../../lib/security/client-ip.ts";

export type PeriodLockMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const PERIOD_LOCK_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "finance_period_lock_reason_required",
  "finance_period_lock_invalid_scope",
  "finance_period_not_found",
  "finance_period_lock_not_found",
  "finance_period_lock_not_locked",
  "finance_period_lock_not_reopen_requested",
  "finance_period_reopen_window_invalid",
  "finance_period_locked",
  "stale_version",
] as const;
type KnownPeriodLockMutationErrorCode = (typeof PERIOD_LOCK_KNOWN_MUTATION_ERROR_CODES)[number];
export type PeriodLockMutationErrorCode = KnownPeriodLockMutationErrorCode | "mutation_failed" | "invalid_response";

export class PeriodLockMutationError extends Error {
  readonly code: PeriodLockMutationErrorCode;

  constructor(code: PeriodLockMutationErrorCode, message: string) {
    super(message);
    this.name = "PeriodLockMutationError";
    this.code = code;
  }
}

function classifyError(message: string): PeriodLockMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (PERIOD_LOCK_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownPeriodLockMutationErrorCode) : "mutation_failed";
}

async function callAndParseLock(
  client: PeriodLockMutationRpcClient,
  fn: "lock_finance_period" | "request_finance_period_reopen" | "approve_finance_period_reopen" | "relock_finance_period",
  args: Record<string, unknown>,
): Promise<FinancePeriodLock> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new PeriodLockMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new PeriodLockMutationError("invalid_response", `${fn} returned no row`);
  }
  return parseFinancePeriodLock(data as Record<string, unknown>);
}

/** FIN:Approve-gated. Idempotent when already locked for the same scope; re-locks a reopened/reopen_requested row in place otherwise. */
export async function lockFinancePeriod(client: PeriodLockMutationRpcClient, input: LockFinancePeriodInput): Promise<FinancePeriodLock> {
  const parsedInput = LockFinancePeriodInputSchema.parse(input);
  return callAndParseLock(client, "lock_finance_period", {
    p_tenant_id: parsedInput.tenantId,
    p_company_id: parsedInput.companyId,
    p_period_id: parsedInput.periodId,
    p_lock_scope: parsedInput.lockScope,
    p_reason: parsedInput.reason,
    p_evidence_ref: parsedInput.evidenceRef,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
    // ISS-2026-302: read here rather than threaded through every caller -- a security
    // control a call site can forget to pass is not a control. Null outside a request.
    p_client_ip: await resolveRequestClientIp(),
  });
}

/** FIN:Edit-gated. locked -> reopen_requested. */
export async function requestFinancePeriodReopen(client: PeriodLockMutationRpcClient, input: RequestFinancePeriodReopenInput): Promise<FinancePeriodLock> {
  const parsedInput = RequestFinancePeriodReopenInputSchema.parse(input);
  return callAndParseLock(client, "request_finance_period_reopen", {
    p_lock_id: parsedInput.lockId,
    p_expected_version: parsedInput.expectedVersion,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** FIN:Approve-gated. reopen_requested -> reopened; sets a bounded (1-720h) reopen_window_expires_at. */
export async function approveFinancePeriodReopen(client: PeriodLockMutationRpcClient, input: ApproveFinancePeriodReopenInput): Promise<FinancePeriodLock> {
  const parsedInput = ApproveFinancePeriodReopenInputSchema.parse(input);
  return callAndParseLock(client, "approve_finance_period_reopen", {
    p_lock_id: parsedInput.lockId,
    p_expected_version: parsedInput.expectedVersion,
    p_window_hours: parsedInput.windowHours,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
    // ISS-2026-302: read here rather than threaded through every caller -- a security
    // control a call site can forget to pass is not a control. Null outside a request.
    p_client_ip: await resolveRequestClientIp(),
  });
}

/** FIN:Approve-gated, idempotent. reopened/reopen_requested -> locked. */
export async function relockFinancePeriod(client: PeriodLockMutationRpcClient, input: FinancePeriodLockLifecycleInput): Promise<FinancePeriodLock> {
  const parsedInput = FinancePeriodLockLifecycleInputSchema.parse(input);
  return callAndParseLock(client, "relock_finance_period", {
    p_lock_id: parsedInput.lockId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
    // ISS-2026-302: read here rather than threaded through every caller -- a security
    // control a call site can forget to pass is not a control. Null outside a request.
    p_client_ip: await resolveRequestClientIp(),
  });
}
