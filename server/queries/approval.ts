/**
 * Approval request read queries (PLT-123, CG-S6-PLT-020). Thin, typed wrappers around
 * app.get_approval_request_history / app.list_pending_approval_steps_for_actor
 * (supabase/migrations/20260719090000_create_approval_engine.sql) -- the reusable
 * pending-approver/timeline view models Prompt 123 §15 calls for.
 *
 * getApprovalRequestStep / getApprovalRequestById (O1 remediation, cluster 7): replace two
 * broken direct `.from()` reads embedded in procurement/approvals/[stepId]/page.tsx (app is
 * not exposed to PostgREST). Both are SECURITY INVOKER, zero actor parameter -- see
 * 20260913050000's own header for why (live RLS is the current, correct authority surface for
 * both tables; app.check_approval_request_authority is a stale helper this series deliberately
 * does not call).
 */

import {
  GetApprovalRequestHistoryInputSchema,
  ListPendingApprovalStepsInputSchema,
  parseApprovalRequestHistoryEntry,
  parseApprovalRequestStep,
  parseApprovalRequest,
  type GetApprovalRequestHistoryInput,
  type ListPendingApprovalStepsInput,
  type ApprovalRequestHistoryEntry,
  type ApprovalRequestStep,
  type ApprovalRequest,
} from "../contracts/approval/approval.ts";

export interface ApprovalQueryRpcClient {
  rpc(
    fn: "get_approval_request_history" | "list_pending_approval_steps_for_actor" | "get_approval_request_step" | "get_approval_request_by_id",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export class ApprovalQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ApprovalQueryError";
  }
}

/** Ordered by step_order then decided_at. Authority-gated -- raises insufficient_authority if the actor is not an active member of the request's tenant (nor Supreme Admin). */
export async function getApprovalRequestHistory(
  client: ApprovalQueryRpcClient,
  input: GetApprovalRequestHistoryInput,
): Promise<ApprovalRequestHistoryEntry[]> {
  const parsedInput = GetApprovalRequestHistoryInputSchema.parse(input);
  const { data, error } = await client.rpc("get_approval_request_history", {
    p_request_id: parsedInput.requestId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
  });

  if (error) {
    throw new ApprovalQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new ApprovalQueryError("get_approval_request_history returned a non-array result");
  }
  return data.map((row) => parseApprovalRequestHistoryEntry(row as Record<string, unknown>));
}

/** The pending-approver inbox view model: every currently-active step across the tenant this actor is eligible to decide right now (direct role/user match or an active delegation). */
export async function listPendingApprovalStepsForActor(
  client: ApprovalQueryRpcClient,
  input: ListPendingApprovalStepsInput,
): Promise<ApprovalRequestStep[]> {
  const parsedInput = ListPendingApprovalStepsInputSchema.parse(input);
  const { data, error } = await client.rpc("list_pending_approval_steps_for_actor", {
    p_tenant_id: parsedInput.tenantId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
  });

  if (error) {
    throw new ApprovalQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new ApprovalQueryError("list_pending_approval_steps_for_actor returned a non-array result");
  }
  return data.map((row) => parseApprovalRequestStep(row as Record<string, unknown>));
}

/** One approval step by id. Returns null (never an error) when it does not exist or RLS hides it. */
export async function getApprovalRequestStep(client: ApprovalQueryRpcClient, stepId: string): Promise<ApprovalRequestStep | null> {
  const { data, error } = await client.rpc("get_approval_request_step", { p_step_id: stepId });

  if (error) {
    throw new ApprovalQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row) {
    return null;
  }
  return parseApprovalRequestStep(row as Record<string, unknown>);
}

/** One approval request by id. Returns null (never an error) when it does not exist or RLS hides it. */
export async function getApprovalRequestById(client: ApprovalQueryRpcClient, requestId: string): Promise<ApprovalRequest | null> {
  const { data, error } = await client.rpc("get_approval_request_by_id", { p_request_id: requestId });

  if (error) {
    throw new ApprovalQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row) {
    return null;
  }
  return parseApprovalRequest(row as Record<string, unknown>);
}
