/**
 * Procurement Approval read queries (PRC-259, CG-S11-PRC-010). Thin, typed wrappers
 * around direct RLS-scoped selects on app.procurement_approval_policies, plus RPC
 * wrappers for app.evaluate_procurement_approval_requirement /
 * app.get_procurement_approval_context_snapshot / app.get_procurement_exception_request
 * / app.list_procurement_exception_requests, plus pure TypeScript composition over the
 * already-existing Approval Engine query primitives (server/queries/approval.ts,
 * PLT-123) for the unified pending inbox -- mirrors
 * server/queries/quotation-approval.ts's own exact shape.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseProcurementApprovalPolicyVersion,
  parseProcurementApprovalRequirement,
  parseProcurementApprovalContextSnapshot,
  parseProcurementExceptionRequest,
  EvaluateProcurementApprovalRequirementInputSchema,
  GetProcurementApprovalContextSnapshotInputSchema,
  ListProcurementExceptionRequestsInputSchema,
  PROCUREMENT_APPROVAL_ENTITY_TYPES,
  type ProcurementApprovalPolicyVersion,
  type ProcurementApprovalRequirement,
  type ProcurementApprovalContextSnapshot,
  type ProcurementExceptionRequest,
  type EvaluateProcurementApprovalRequirementInput,
  type GetProcurementApprovalContextSnapshotInput,
  type ListProcurementExceptionRequestsInput,
} from "../contracts/procurement-approval/procurement-approval.ts";
import { listPendingApprovalStepsForActor, type ApprovalQueryRpcClient } from "./approval.ts";
import type { ApprovalRequestStep } from "../contracts/approval/approval.ts";

export type ProcurementApprovalQueryClient = Pick<SupabaseClient, "from" | "rpc">;

/** Supabase's own `.rpc()` returns a `PostgrestFilterBuilder` (thenable, not a strict `Promise`) -- structurally incompatible with server/queries/approval.ts's hand-written `ApprovalQueryRpcClient` interface. The same `async (fn, args) => await client.rpc(fn, args)` adapter every other cross-module RPC composition in this repository already uses for that exact mismatch (mirrors server/queries/quotation-approval.ts). Exported so pages that need to compose the generic Approval Engine's own history/pending-inbox reads directly (e.g. the step detail page) can reuse it rather than redefining it. */
export function toApprovalQueryRpcClient(client: ProcurementApprovalQueryClient): ApprovalQueryRpcClient {
  return { rpc: async (fn, args) => await client.rpc(fn, args) };
}

export class ProcurementApprovalQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ProcurementApprovalQueryError";
  }
}

/** Every procurement approval policy version for one tenant (any status, any entity_type), most recently created first -- tenant-wide reference/policy data, never field-masked (mirrors app.quotation_approval_rules, COM-153). */
export async function listProcurementApprovalPolicyVersions(client: ProcurementApprovalQueryClient, tenantId: string): Promise<ProcurementApprovalPolicyVersion[]> {
  const { data, error } = await client.from("procurement_approval_policies").select("*").eq("tenant_id", tenantId).order("created_at", { ascending: false });
  if (error) {
    throw new ProcurementApprovalQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseProcurementApprovalPolicyVersion(row));
}

export async function evaluateProcurementApprovalRequirement(client: ProcurementApprovalQueryClient, input: EvaluateProcurementApprovalRequirementInput): Promise<ProcurementApprovalRequirement> {
  const parsedInput = EvaluateProcurementApprovalRequirementInputSchema.parse(input);
  const { data, error } = await client.rpc("evaluate_procurement_approval_requirement", {
    p_entity_type: parsedInput.entityType,
    p_tenant_id: parsedInput.tenantId,
    p_value_amount: parsedInput.valueAmount,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
  });
  if (error) {
    throw new ProcurementApprovalQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new ProcurementApprovalQueryError("evaluate_procurement_approval_requirement returned no row");
  }
  return parseProcurementApprovalRequirement(row as Record<string, unknown>);
}

/** Masked read of one context snapshot -- valueAmount/currency null (costMasked=true) for a caller without PRC:View cost. */
export async function getProcurementApprovalContextSnapshot(client: ProcurementApprovalQueryClient, input: GetProcurementApprovalContextSnapshotInput): Promise<ProcurementApprovalContextSnapshot> {
  const parsedInput = GetProcurementApprovalContextSnapshotInputSchema.parse(input);
  const { data, error } = await client.rpc("get_procurement_approval_context_snapshot", {
    p_approval_request_id: parsedInput.approvalRequestId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
  });
  if (error) {
    throw new ProcurementApprovalQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new ProcurementApprovalQueryError("get_procurement_approval_context_snapshot returned no row");
  }
  return parseProcurementApprovalContextSnapshot(row as Record<string, unknown>);
}

export async function getProcurementExceptionRequest(client: ProcurementApprovalQueryClient, id: string, actorAuthUserId: string): Promise<ProcurementExceptionRequest> {
  const { data, error } = await client.rpc("get_procurement_exception_request", { p_id: id, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new ProcurementApprovalQueryError(error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ProcurementApprovalQueryError("get_procurement_exception_request returned no row");
  }
  return parseProcurementExceptionRequest(data as Record<string, unknown>);
}

export async function listProcurementExceptionRequests(client: ProcurementApprovalQueryClient, input: ListProcurementExceptionRequestsInput): Promise<ProcurementExceptionRequest[]> {
  const parsedInput = ListProcurementExceptionRequestsInputSchema.parse(input);
  const { data, error } = await client.rpc("list_procurement_exception_requests", {
    p_tenant_id: parsedInput.tenantId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_status_filter: parsedInput.statusFilter,
    p_limit: parsedInput.limit,
  });
  if (error) {
    throw new ProcurementApprovalQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new ProcurementApprovalQueryError("list_procurement_exception_requests returned a non-array result");
  }
  return data.map((row) => parseProcurementExceptionRequest(row as Record<string, unknown>));
}

export interface ProcurementApprovalInboxItem {
  readonly stepId: string;
  readonly stepOrder: number;
  readonly requestId: string;
  readonly entityType: string;
  readonly entityId: string | null;
}

/** The unified procurement approval inbox (Prompt 259 §15): every currently-active step across the tenant this actor is eligible to decide right now, filtered to this capability's own 6 governed entity_type values -- app.list_pending_approval_steps_for_actor (PLT-123) is entity-agnostic (shared with Commercial's quotation/credit approvals, this migration's own header), so this resolves each pending step's own request via a direct, RLS-scoped select on app.approval_requests (no new SQL), mirroring listQuotationApprovalInboxForActor exactly. */
export async function listProcurementApprovalInboxForActor(client: ProcurementApprovalQueryClient, tenantId: string, actorAuthUserId: string): Promise<ProcurementApprovalInboxItem[]> {
  const steps: ApprovalRequestStep[] = await listPendingApprovalStepsForActor(toApprovalQueryRpcClient(client), { tenantId, actorAuthUserId });
  if (steps.length === 0) {
    return [];
  }

  const requestIds = [...new Set(steps.map((step) => step.requestId))];
  const { data, error } = await client.from("approval_requests").select("id, entity_type, entity_id").in("id", requestIds);
  if (error) {
    throw new ProcurementApprovalQueryError(error.message);
  }

  const requestById = new Map<string, { entityType: string; entityId: string | null }>();
  for (const row of (data ?? []) as Array<{ id: string; entity_type: string; entity_id: string | null }>) {
    if ((PROCUREMENT_APPROVAL_ENTITY_TYPES as readonly string[]).includes(row.entity_type)) {
      requestById.set(row.id, { entityType: row.entity_type, entityId: row.entity_id });
    }
  }

  return steps
    .filter((step) => requestById.has(step.requestId))
    .map((step) => {
      const request = requestById.get(step.requestId)!;
      return { stepId: step.id, stepOrder: step.stepOrder, requestId: step.requestId, entityType: request.entityType, entityId: request.entityId };
    });
}
