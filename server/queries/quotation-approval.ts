/**
 * Quotation Approval read queries (COM-153, CG-S7-COM-012). Thin, typed wrappers around
 * direct RLS-scoped selects on app.quotation_approval_rules, plus pure TypeScript
 * composition over the already-existing Approval Engine query primitives
 * (server/queries/approval.ts, PLT-123) -- no new SQL function is added for either read,
 * the same "compute in TypeScript when the underlying reads are already access-controlled"
 * precedent server/contracts/quotation/quotation-diff.ts (COM-152) already established.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { parseQuotationApprovalRuleVersion, type QuotationApprovalRuleVersion } from "../contracts/quotation/quotation-approval.ts";
import { getApprovalRequestHistory, listPendingApprovalStepsForActor, type ApprovalQueryRpcClient } from "./approval.ts";
import type { ApprovalRequestHistoryEntry } from "../contracts/approval/approval.ts";
import type { Quotation } from "../contracts/quotation/quotation.ts";

export type QuotationApprovalQueryClient = Pick<SupabaseClient, "from" | "rpc">;

/** Supabase's own `.rpc()` returns a `PostgrestFilterBuilder` (thenable, not a strict `Promise`) -- structurally incompatible with server/queries/approval.ts's hand-written `ApprovalQueryRpcClient` interface. This adapter is the same `async (fn, args) => await client.rpc(fn, args)` wrapper every other cross-module RPC composition in this repository already uses for that exact mismatch. */
function toApprovalQueryRpcClient(client: QuotationApprovalQueryClient): ApprovalQueryRpcClient {
  return { rpc: async (fn, args) => await client.rpc(fn, args) };
}

export class QuotationApprovalQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "QuotationApprovalQueryError";
  }
}

/** Every quotation approval rule version for one tenant (any status), most recently created first -- tenant-wide reference/policy data, never field-masked (mirrors app.margin_rule_versions, COM-150). */
export async function listQuotationApprovalRuleVersions(client: QuotationApprovalQueryClient, tenantId: string): Promise<QuotationApprovalRuleVersion[]> {
  const { data, error } = await client.from("quotation_approval_rules").select("*").eq("tenant_id", tenantId).order("created_at", { ascending: false });
  if (error) {
    throw new QuotationApprovalQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseQuotationApprovalRuleVersion(row));
}

export interface QuotationApprovalOverview {
  readonly history: ApprovalRequestHistoryEntry[];
  /** Request-step ids on this quotation's own bound request that this actor is eligible to decide right now (direct role/user match or an active delegation) -- drives whether the decide form renders. */
  readonly myEligibleStepIds: string[];
}

/** Composes the Approval Engine's own history/pending-inbox view models for one quotation's bound request. Returns null when the quotation has never been routed (approvalRequestId is null -- not_required or not yet submitted). */
export async function getQuotationApprovalOverview(
  client: QuotationApprovalQueryClient,
  quotation: Pick<Quotation, "tenantId" | "approvalRequestId">,
  actorAuthUserId: string,
): Promise<QuotationApprovalOverview | null> {
  if (!quotation.approvalRequestId) {
    return null;
  }

  const approvalClient = toApprovalQueryRpcClient(client);
  const [history, pendingSteps] = await Promise.all([
    getApprovalRequestHistory(approvalClient, { requestId: quotation.approvalRequestId, actorAuthUserId }),
    listPendingApprovalStepsForActor(approvalClient, { tenantId: quotation.tenantId, actorAuthUserId }),
  ]);

  const myEligibleStepIds = pendingSteps.filter((step) => step.requestId === quotation.approvalRequestId).map((step) => step.id);

  return { history, myEligibleStepIds };
}

export interface QuotationApprovalInboxItem {
  readonly stepId: string;
  readonly stepOrder: number;
  readonly requestId: string;
  readonly quotationId: string;
}

/** The pending-approver inbox, filtered to quotation-entity requests only -- app.list_pending_approval_steps_for_actor (PLT-123) is entity-agnostic, so this resolves each pending step's own request to its bound quotation via a direct, RLS-scoped select on app.approval_requests (no new SQL). */
export async function listQuotationApprovalInboxForActor(client: QuotationApprovalQueryClient, tenantId: string, actorAuthUserId: string): Promise<QuotationApprovalInboxItem[]> {
  const steps = await listPendingApprovalStepsForActor(toApprovalQueryRpcClient(client), { tenantId, actorAuthUserId });
  if (steps.length === 0) {
    return [];
  }

  const requestIds = [...new Set(steps.map((step) => step.requestId))];
  const { data, error } = await client.from("approval_requests").select("id, entity_type, entity_id").in("id", requestIds);
  if (error) {
    throw new QuotationApprovalQueryError(error.message);
  }

  const quotationIdByRequestId = new Map<string, string>();
  for (const row of (data ?? []) as Array<{ id: string; entity_type: string; entity_id: string | null }>) {
    if (row.entity_type === "quotation" && row.entity_id) {
      quotationIdByRequestId.set(row.id, row.entity_id);
    }
  }

  return steps
    .filter((step) => quotationIdByRequestId.has(step.requestId))
    .map((step) => ({
      stepId: step.id,
      stepOrder: step.stepOrder,
      requestId: step.requestId,
      quotationId: quotationIdByRequestId.get(step.requestId)!,
    }));
}
