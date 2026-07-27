/**
 * Resource/Vendor Assignment read queries (OPS-172, CG-S8-OPS-006). Thin, typed
 * wrappers around app.find_assignment_candidates / app.get_resource_assignment_history.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseAssignmentCandidate,
  parseResourceAssignment,
  FindAssignmentCandidatesInputSchema,
  GetResourceAssignmentHistoryInputSchema,
  type AssignmentCandidate,
  type ResourceAssignment,
  type FindAssignmentCandidatesInput,
  type GetResourceAssignmentHistoryInput,
} from "../contracts/resource-assignment/resource-assignment.ts";

export type ResourceAssignmentQueryRpcClient = Pick<SupabaseClient, "rpc">;

export class ResourceAssignmentQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ResourceAssignmentQueryError";
  }
}

/** Tenant-scoped, active-only candidate lookup for a given role -- never projects app.master_records.attributes. */
export async function findAssignmentCandidates(
  client: ResourceAssignmentQueryRpcClient,
  input: FindAssignmentCandidatesInput,
): Promise<AssignmentCandidate[]> {
  const parsedInput = FindAssignmentCandidatesInputSchema.parse(input);
  const { data, error } = await client.rpc("find_assignment_candidates", {
    p_tenant_id: parsedInput.tenantId,
    p_role: parsedInput.role,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
  });
  if (error) {
    throw new ResourceAssignmentQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new ResourceAssignmentQueryError("find_assignment_candidates returned a non-array result");
  }
  return data.map((row: Record<string, unknown>) => parseAssignmentCandidate(row));
}

/** The full, ordered (oldest-first) append-oriented assignment history for one Shipment Order -- authority-gated. */
export async function getResourceAssignmentHistory(
  client: ResourceAssignmentQueryRpcClient,
  input: GetResourceAssignmentHistoryInput,
): Promise<ResourceAssignment[]> {
  const parsedInput = GetResourceAssignmentHistoryInputSchema.parse(input);
  const { data, error } = await client.rpc("get_resource_assignment_history", {
    p_shipment_order_id: parsedInput.shipmentOrderId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
  });
  if (error) {
    throw new ResourceAssignmentQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new ResourceAssignmentQueryError("get_resource_assignment_history returned a non-array result");
  }
  return data.map((row: Record<string, unknown>) => parseResourceAssignment(row));
}
