/**
 * Resource/Vendor Assignment contract (OPS-172, CG-S8-OPS-006). Mirrors
 * supabase/migrations/20260727130000_create_operations_resource_assignment.sql's
 * app.resource_assignments shape and its RPCs.
 *
 * Basic vendor, fleet, vehicle and driver assignment to a Shipment Order (OPS-169) --
 * binds to real canonical references (app.master_records, PLT-120's generic
 * master-data registry) rather than the plain text OPS-171 deliberately left in place.
 * resourceSnapshot is deliberately limited to {code, name} -- never the full
 * app.master_records.attributes blob, which may hold driver PII (Prompt 172 §26).
 */

import { z } from "zod";

export const RESOURCE_ASSIGNMENT_ROLES = ["vendor", "fleet", "vehicle", "driver"] as const;
export const ResourceAssignmentRoleSchema = z.enum(RESOURCE_ASSIGNMENT_ROLES);
export type ResourceAssignmentRole = z.infer<typeof ResourceAssignmentRoleSchema>;

export const RESOURCE_ASSIGNMENT_STATUSES = ["active", "held", "unassigned"] as const;
export const ResourceAssignmentStatusSchema = z.enum(RESOURCE_ASSIGNMENT_STATUSES);
export type ResourceAssignmentStatus = z.infer<typeof ResourceAssignmentStatusSchema>;

export const ResourceSnapshotSchema = z
  .object({
    code: z.string(),
    name: z.string(),
  })
  .strict();
export type ResourceSnapshot = z.infer<typeof ResourceSnapshotSchema>;

export const ResourceAssignmentSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  shipmentOrderId: z.string().uuid(),
  role: ResourceAssignmentRoleSchema,
  resourceId: z.string().uuid(),
  resourceSnapshot: ResourceSnapshotSchema,
  status: ResourceAssignmentStatusSchema,
  isCurrent: z.boolean(),
  effectiveFrom: z.string(),
  effectiveTo: z.string().nullable(),
  reason: z.string().nullable(),
  supersededById: z.string().uuid().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type ResourceAssignment = z.infer<typeof ResourceAssignmentSchema>;

/** Maps a raw app.resource_assignments row (snake_case) into the typed shape. */
export function parseResourceAssignment(row: Record<string, unknown>): ResourceAssignment {
  return ResourceAssignmentSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    shipmentOrderId: row.shipment_order_id,
    role: row.role,
    resourceId: row.resource_id,
    resourceSnapshot: row.resource_snapshot,
    status: row.status,
    isCurrent: row.is_current,
    effectiveFrom: row.effective_from,
    effectiveTo: row.effective_to ?? null,
    reason: row.reason ?? null,
    supersededById: row.superseded_by_id ?? null,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const AssignmentCandidateSchema = z.object({
  id: z.string().uuid(),
  code: z.string(),
  name: z.string(),
});
export type AssignmentCandidate = z.infer<typeof AssignmentCandidateSchema>;

/** Maps a raw app.find_assignment_candidates() row (snake_case: id, code, name -- already minimized, no attributes). */
export function parseAssignmentCandidate(row: Record<string, unknown>): AssignmentCandidate {
  return AssignmentCandidateSchema.parse({ id: row.id, code: row.code, name: row.name });
}

export const FindAssignmentCandidatesInputSchema = z.object({
  tenantId: z.string().uuid(),
  role: ResourceAssignmentRoleSchema,
  actorAuthUserId: z.string().uuid(),
});
export type FindAssignmentCandidatesInput = z.input<typeof FindAssignmentCandidatesInputSchema>;

export const AssignResourceInputSchema = z.object({
  shipmentOrderId: z.string().uuid(),
  role: ResourceAssignmentRoleSchema,
  resourceId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type AssignResourceInput = z.input<typeof AssignResourceInputSchema>;

export const ReassignResourceInputSchema = z.object({
  shipmentOrderId: z.string().uuid(),
  role: ResourceAssignmentRoleSchema,
  newResourceId: z.string().uuid(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ReassignResourceInput = z.input<typeof ReassignResourceInputSchema>;

export const HoldResourceAssignmentInputSchema = z.object({
  shipmentOrderId: z.string().uuid(),
  role: ResourceAssignmentRoleSchema,
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type HoldResourceAssignmentInput = z.input<typeof HoldResourceAssignmentInputSchema>;

export const ResumeResourceAssignmentInputSchema = z.object({
  shipmentOrderId: z.string().uuid(),
  role: ResourceAssignmentRoleSchema,
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ResumeResourceAssignmentInput = z.input<typeof ResumeResourceAssignmentInputSchema>;

export const UnassignResourceInputSchema = z.object({
  shipmentOrderId: z.string().uuid(),
  role: ResourceAssignmentRoleSchema,
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type UnassignResourceInput = z.input<typeof UnassignResourceInputSchema>;

export const GetResourceAssignmentHistoryInputSchema = z.object({
  shipmentOrderId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
});
export type GetResourceAssignmentHistoryInput = z.input<typeof GetResourceAssignmentHistoryInputSchema>;
