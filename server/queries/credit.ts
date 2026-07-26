/**
 * Credit and Commercial Control read queries (COM-157, CG-S7-COM-016). Every read goes
 * through a masked `*_directory` view (COM:View selling price) -- app.credit_profiles/
 * app.credit_profile_overrides/app.credit_check_snapshots carry no direct authenticated
 * column grant on their own money-bearing columns. The approval-inbox composition mirrors
 * server/queries/quotation-approval.ts (COM-153) exactly, filtered to entity_type=
 * credit_profile instead of quotation.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { parseCreditProfile, parseCreditProfileOverride, type CreditProfile, type CreditProfileOverride } from "../contracts/credit/credit.ts";
import { getApprovalRequestHistory, listPendingApprovalStepsForActor, type ApprovalQueryRpcClient } from "./approval.ts";
import type { ApprovalRequestHistoryEntry } from "../contracts/approval/approval.ts";

export type CreditQueryClient = Pick<SupabaseClient, "from" | "rpc">;

/** Supabase's own `.rpc()` returns a `PostgrestFilterBuilder` (thenable, not a strict `Promise`) -- structurally incompatible with server/queries/approval.ts's hand-written `ApprovalQueryRpcClient` interface. The same adapter every other cross-module RPC composition in this repository already uses for that exact mismatch. */
function toApprovalQueryRpcClient(client: CreditQueryClient): ApprovalQueryRpcClient {
  return { rpc: async (fn, args) => await client.rpc(fn, args) };
}

export class CreditQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "CreditQueryError";
  }
}

/** Every credit profile for one tenant (any status), most recently created first -- tenant-wide reference data, RLS-scoped by tenant membership only (not record-scoped, mirrors app.accounts). */
export async function listCreditProfiles(client: CreditQueryClient, tenantId: string): Promise<CreditProfile[]> {
  const { data, error } = await client.from("credit_profiles_directory").select("*").eq("tenant_id", tenantId).order("created_at", { ascending: false });
  if (error) {
    throw new CreditQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseCreditProfile(row));
}

/** The current (most recently created) credit profile for one account, or null if it has never had one. */
export async function getCreditProfileForAccount(client: CreditQueryClient, accountId: string): Promise<CreditProfile | null> {
  const { data, error } = await client.from("credit_profiles_directory").select("*").eq("account_id", accountId).order("created_at", { ascending: false }).limit(1);
  if (error) {
    throw new CreditQueryError(error.message);
  }
  const row = (data ?? [])[0];
  if (!row) {
    return null;
  }
  return parseCreditProfile(row as Record<string, unknown>);
}

export async function getCreditProfileById(client: CreditQueryClient, profileId: string): Promise<CreditProfile | null> {
  const { data, error } = await client.from("credit_profiles_directory").select("*").eq("id", profileId).maybeSingle();
  if (error) {
    throw new CreditQueryError(error.message);
  }
  if (!data) {
    return null;
  }
  return parseCreditProfile(data as Record<string, unknown>);
}

/** Currently-valid (not yet expired) overrides for one profile, most recent first. */
export async function listCreditProfileOverrides(client: CreditQueryClient, profileId: string): Promise<CreditProfileOverride[]> {
  const { data, error } = await client.from("credit_profile_overrides_directory").select("*").eq("credit_profile_id", profileId).order("created_at", { ascending: false });
  if (error) {
    throw new CreditQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseCreditProfileOverride(row));
}

export interface CreditProfileApprovalOverview {
  readonly history: ApprovalRequestHistoryEntry[];
  /** Request-step ids on this profile's own bound request that this actor is eligible to decide right now (direct role/user match or an active delegation) -- drives whether the decide form renders. */
  readonly myEligibleStepIds: string[];
}

/** Composes the Approval Engine's own history/pending-inbox view models for one credit profile's bound request. Returns null when the profile has never been routed (approvalRequestId is null). */
export async function getCreditProfileApprovalOverview(
  client: CreditQueryClient,
  profile: Pick<CreditProfile, "tenantId" | "approvalRequestId">,
  actorAuthUserId: string,
): Promise<CreditProfileApprovalOverview | null> {
  if (!profile.approvalRequestId) {
    return null;
  }

  const approvalClient = toApprovalQueryRpcClient(client);
  const [history, pendingSteps] = await Promise.all([
    getApprovalRequestHistory(approvalClient, { requestId: profile.approvalRequestId, actorAuthUserId }),
    listPendingApprovalStepsForActor(approvalClient, { tenantId: profile.tenantId, actorAuthUserId }),
  ]);

  const myEligibleStepIds = pendingSteps.filter((step) => step.requestId === profile.approvalRequestId).map((step) => step.id);

  return { history, myEligibleStepIds };
}

export interface CreditProfileApprovalInboxItem {
  readonly stepId: string;
  readonly stepOrder: number;
  readonly requestId: string;
  readonly creditProfileId: string;
}

/** The pending-approver inbox, filtered to credit_profile-entity requests only -- app.list_pending_approval_steps_for_actor (PLT-123) is entity-agnostic, so this resolves each pending step's own request to its bound profile via a direct, RLS-scoped select on app.approval_requests (no new SQL), mirroring listQuotationApprovalInboxForActor (COM-153) exactly. */
export async function listCreditProfileApprovalInboxForActor(client: CreditQueryClient, tenantId: string, actorAuthUserId: string): Promise<CreditProfileApprovalInboxItem[]> {
  const steps = await listPendingApprovalStepsForActor(toApprovalQueryRpcClient(client), { tenantId, actorAuthUserId });
  if (steps.length === 0) {
    return [];
  }

  const requestIds = [...new Set(steps.map((step) => step.requestId))];
  const { data, error } = await client.from("approval_requests").select("id, entity_type, entity_id").in("id", requestIds);
  if (error) {
    throw new CreditQueryError(error.message);
  }

  const profileIdByRequestId = new Map<string, string>();
  for (const row of (data ?? []) as Array<{ id: string; entity_type: string; entity_id: string | null }>) {
    if (row.entity_type === "credit_profile" && row.entity_id) {
      profileIdByRequestId.set(row.id, row.entity_id);
    }
  }

  return steps
    .filter((step) => profileIdByRequestId.has(step.requestId))
    .map((step) => ({
      stepId: step.id,
      stepOrder: step.stepOrder,
      requestId: step.requestId,
      creditProfileId: profileIdByRequestId.get(step.requestId)!,
    }));
}
