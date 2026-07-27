/**
 * Resource/Vendor Assignment mutation primitives (OPS-172, CG-S8-OPS-006). Thin, typed
 * wrappers around app.assign_resource / app.reassign_resource /
 * app.hold_resource_assignment / app.resume_resource_assignment /
 * app.unassign_resource
 * (supabase/migrations/20260727130000_create_operations_resource_assignment.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  AssignResourceInputSchema,
  ReassignResourceInputSchema,
  HoldResourceAssignmentInputSchema,
  ResumeResourceAssignmentInputSchema,
  UnassignResourceInputSchema,
  parseResourceAssignment,
  type AssignResourceInput,
  type ReassignResourceInput,
  type HoldResourceAssignmentInput,
  type ResumeResourceAssignmentInput,
  type UnassignResourceInput,
  type ResourceAssignment,
} from "../contracts/resource-assignment/resource-assignment.ts";

export type ResourceAssignmentMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const RESOURCE_ASSIGNMENT_KNOWN_MUTATION_ERROR_CODES = [
  "invalid_role",
  "shipment_order_not_found",
  "invalid_transition",
  "invalid_resource",
  "insufficient_authority",
  "assignment_conflict",
  "already_assigned",
  "no_current_assignment",
  "reason_required",
] as const;
type KnownResourceAssignmentMutationErrorCode = (typeof RESOURCE_ASSIGNMENT_KNOWN_MUTATION_ERROR_CODES)[number];
export type ResourceAssignmentMutationErrorCode = KnownResourceAssignmentMutationErrorCode | "mutation_failed" | "invalid_response";

export class ResourceAssignmentMutationError extends Error {
  readonly code: ResourceAssignmentMutationErrorCode;

  constructor(code: ResourceAssignmentMutationErrorCode, message: string) {
    super(message);
    this.name = "ResourceAssignmentMutationError";
    this.code = code;
  }
}

function classifyError(message: string): ResourceAssignmentMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (RESOURCE_ASSIGNMENT_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownResourceAssignmentMutationErrorCode)
    : "mutation_failed";
}

function parseRpcAssignment(data: unknown, rpcName: string): ResourceAssignment {
  if (!data || typeof data !== "object") {
    throw new ResourceAssignmentMutationError("invalid_response", `${rpcName} returned no row`);
  }
  return parseResourceAssignment(data as Record<string, unknown>);
}

/** Creates the first assignment for a (shipmentOrderId, role) slot -- already_assigned if a current row exists, assignment_conflict if the resource already holds a live assignment elsewhere. */
export async function assignResource(client: ResourceAssignmentMutationRpcClient, input: AssignResourceInput): Promise<ResourceAssignment> {
  const parsedInput = AssignResourceInputSchema.parse(input);
  const { data, error } = await client.rpc("assign_resource", {
    p_shipment_order_id: parsedInput.shipmentOrderId,
    p_role: parsedInput.role,
    p_resource_id: parsedInput.resourceId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ResourceAssignmentMutationError(classifyError(error.message), error.message);
  }
  return parseRpcAssignment(data, "assign_resource");
}

/** Creates a new row and links the prior current row's supersededById at it -- the prior row is never deleted or overwritten. Reason mandatory. */
export async function reassignResource(client: ResourceAssignmentMutationRpcClient, input: ReassignResourceInput): Promise<ResourceAssignment> {
  const parsedInput = ReassignResourceInputSchema.parse(input);
  const { data, error } = await client.rpc("reassign_resource", {
    p_shipment_order_id: parsedInput.shipmentOrderId,
    p_role: parsedInput.role,
    p_new_resource_id: parsedInput.newResourceId,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ResourceAssignmentMutationError(classifyError(error.message), error.message);
  }
  return parseRpcAssignment(data, "reassign_resource");
}

/** In-place status flip active -> held on the one current row for a (shipmentOrderId, role) slot. Reason mandatory. */
export async function holdResourceAssignment(client: ResourceAssignmentMutationRpcClient, input: HoldResourceAssignmentInput): Promise<ResourceAssignment> {
  const parsedInput = HoldResourceAssignmentInputSchema.parse(input);
  const { data, error } = await client.rpc("hold_resource_assignment", {
    p_shipment_order_id: parsedInput.shipmentOrderId,
    p_role: parsedInput.role,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ResourceAssignmentMutationError(classifyError(error.message), error.message);
  }
  return parseRpcAssignment(data, "hold_resource_assignment");
}

/** In-place status flip held -> active on the one current row for a (shipmentOrderId, role) slot. */
export async function resumeResourceAssignment(client: ResourceAssignmentMutationRpcClient, input: ResumeResourceAssignmentInput): Promise<ResourceAssignment> {
  const parsedInput = ResumeResourceAssignmentInputSchema.parse(input);
  const { data, error } = await client.rpc("resume_resource_assignment", {
    p_shipment_order_id: parsedInput.shipmentOrderId,
    p_role: parsedInput.role,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ResourceAssignmentMutationError(classifyError(error.message), error.message);
  }
  return parseRpcAssignment(data, "resume_resource_assignment");
}

/** In-place status flip to unassigned and releases the (shipmentOrderId, role) slot -- a subsequent assignResource may then create a fresh current row. Reason mandatory. */
export async function unassignResource(client: ResourceAssignmentMutationRpcClient, input: UnassignResourceInput): Promise<ResourceAssignment> {
  const parsedInput = UnassignResourceInputSchema.parse(input);
  const { data, error } = await client.rpc("unassign_resource", {
    p_shipment_order_id: parsedInput.shipmentOrderId,
    p_role: parsedInput.role,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ResourceAssignmentMutationError(classifyError(error.message), error.message);
  }
  return parseRpcAssignment(data, "unassign_resource");
}
