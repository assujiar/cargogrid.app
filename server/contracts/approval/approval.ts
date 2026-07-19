/**
 * Approval engine contract (PLT-123, CG-S6-PLT-020). Mirrors
 * supabase/migrations/20260719090000_create_approval_engine.sql's
 * app.approval_requests/app.approval_request_steps/app.approval_decisions/
 * app.approval_delegations shape and the app.publish_approval_definition /
 * app.request_approval / app.decide_approval_step / app.cancel_approval_request /
 * app.escalate_approval_step / app.create_approval_delegation /
 * app.revoke_approval_delegation RPCs.
 *
 * An approval *definition* is not modeled here as its own row type -- it is PLT-121's
 * own ConfigVersion/config_items (config_type_code='approval'), reused directly (this
 * migration's own header). `publishApprovalDefinition` therefore still returns a
 * `ConfigVersion` (server/contracts/config/config.ts), not a bespoke type.
 */

import { z } from "zod";
import { ConfigVersionSchema, type ConfigVersion } from "../config/config.ts";

export const APPROVAL_PATTERNS = ["sequential", "parallel", "threshold"] as const;
export const ApprovalPatternSchema = z.enum(APPROVAL_PATTERNS);
export type ApprovalPattern = z.infer<typeof ApprovalPatternSchema>;

export const APPROVAL_REQUEST_STATUSES = ["pending", "approved", "rejected", "cancelled"] as const;
export const ApprovalRequestStatusSchema = z.enum(APPROVAL_REQUEST_STATUSES);
export type ApprovalRequestStatus = z.infer<typeof ApprovalRequestStatusSchema>;

export const APPROVAL_STEP_STATUSES = ["pending", "active", "approved", "rejected", "skipped"] as const;
export const ApprovalStepStatusSchema = z.enum(APPROVAL_STEP_STATUSES);
export type ApprovalStepStatus = z.infer<typeof ApprovalStepStatusSchema>;

export const APPROVER_TYPES = ["role", "specific_user"] as const;
export const ApproverTypeSchema = z.enum(APPROVER_TYPES);
export type ApproverType = z.infer<typeof ApproverTypeSchema>;

export const APPROVAL_DECISIONS = ["approved", "rejected"] as const;
export const ApprovalDecisionValueSchema = z.enum(APPROVAL_DECISIONS);
export type ApprovalDecisionValue = z.infer<typeof ApprovalDecisionValueSchema>;

export const APPROVAL_DELEGATION_SCOPES = ["all", "role"] as const;
export const ApprovalDelegationScopeSchema = z.enum(APPROVAL_DELEGATION_SCOPES);
export type ApprovalDelegationScope = z.infer<typeof ApprovalDelegationScopeSchema>;

export const ApprovalRequestSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  configVersionId: z.string().uuid(),
  entityType: z.string(),
  entityId: z.string().uuid().nullable(),
  pattern: ApprovalPatternSchema,
  status: ApprovalRequestStatusSchema,
  idempotencyKey: z.string(),
  requestedByAuthUserId: z.string().uuid().nullable(),
  requestedBy: z.string().nullable(),
  startedAt: z.string(),
  endedAt: z.string().nullable(),
  endedReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type ApprovalRequest = z.infer<typeof ApprovalRequestSchema>;

export const ApprovalRequestStepSchema = z.object({
  id: z.string().uuid(),
  requestId: z.string().uuid(),
  stepOrder: z.number().int().positive(),
  approverType: ApproverTypeSchema,
  roleId: z.string().uuid().nullable(),
  specificUserId: z.string().uuid().nullable(),
  requiredApprovals: z.number().int().positive(),
  approvalsCount: z.number().int().nonnegative(),
  status: ApprovalStepStatusSchema,
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type ApprovalRequestStep = z.infer<typeof ApprovalRequestStepSchema>;

export const ApprovalDelegationSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  delegatorAuthUserId: z.string().uuid(),
  delegateAuthUserId: z.string().uuid(),
  scope: ApprovalDelegationScopeSchema,
  roleId: z.string().uuid().nullable(),
  startsAt: z.string(),
  expiresAt: z.string(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  revokedAt: z.string().nullable(),
  revokedReason: z.string().nullable(),
});
export type ApprovalDelegation = z.infer<typeof ApprovalDelegationSchema>;

export const ApprovalRequestHistoryEntrySchema = z.object({
  stepId: z.string().uuid(),
  stepOrder: z.number().int().positive(),
  approverType: ApproverTypeSchema,
  stepStatus: ApprovalStepStatusSchema,
  decisionId: z.string().uuid().nullable(),
  actorAuthUserId: z.string().uuid().nullable(),
  actorLabel: z.string().nullable(),
  decision: ApprovalDecisionValueSchema.nullable(),
  reason: z.string().nullable(),
  decidedAt: z.string().nullable(),
});
export type ApprovalRequestHistoryEntry = z.infer<typeof ApprovalRequestHistoryEntrySchema>;

const ApprovalStepInputSchema = z.object({
  stepOrder: z.number().int().positive(),
  approverType: ApproverTypeSchema,
  roleId: z.string().uuid().nullable().default(null),
  specificUserId: z.string().uuid().nullable().default(null),
  requiredApprovals: z.number().int().positive().default(1),
});
export type ApprovalStepInput = z.input<typeof ApprovalStepInputSchema>;

export const PublishApprovalDefinitionInputSchema = z.object({
  versionId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  effectiveFrom: z.string().nullable().default(null),
  actorLabel: z.string().min(1),
});
export type PublishApprovalDefinitionInput = z.input<typeof PublishApprovalDefinitionInputSchema>;

export const RequestApprovalInputSchema = z.object({
  configVersionId: z.string().uuid(),
  tenantId: z.string().uuid(),
  entityType: z.string().min(1).default("generic"),
  entityId: z.string().uuid().nullable().default(null),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  requestedBy: z.string().min(1),
});
export type RequestApprovalInput = z.input<typeof RequestApprovalInputSchema>;

export const DecideApprovalStepInputSchema = z.object({
  requestStepId: z.string().uuid(),
  decision: ApprovalDecisionValueSchema,
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
  reason: z.string().nullable().default(null),
});
export type DecideApprovalStepInput = z.input<typeof DecideApprovalStepInputSchema>;

export const CancelApprovalRequestInputSchema = z.object({
  requestId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
  reason: z.string().nullable().default(null),
});
export type CancelApprovalRequestInput = z.input<typeof CancelApprovalRequestInputSchema>;

export const EscalateApprovalStepInputSchema = z.object({
  requestStepId: z.string().uuid(),
  newApproverType: ApproverTypeSchema,
  newRoleId: z.string().uuid().nullable().default(null),
  newSpecificUserId: z.string().uuid().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
  reason: z.string().nullable().default(null),
});
export type EscalateApprovalStepInput = z.input<typeof EscalateApprovalStepInputSchema>;

export const CreateApprovalDelegationInputSchema = z.object({
  tenantId: z.string().uuid(),
  delegatorAuthUserId: z.string().uuid(),
  delegateAuthUserId: z.string().uuid(),
  scope: ApprovalDelegationScopeSchema.default("all"),
  roleId: z.string().uuid().nullable().default(null),
  startsAt: z.string().nullable().default(null),
  expiresAt: z.string(),
  actorAuthUserId: z.string().uuid(),
  createdBy: z.string().min(1),
});
export type CreateApprovalDelegationInput = z.input<typeof CreateApprovalDelegationInputSchema>;

export const RevokeApprovalDelegationInputSchema = z.object({
  delegationId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
  reason: z.string().nullable().default(null),
});
export type RevokeApprovalDelegationInput = z.input<typeof RevokeApprovalDelegationInputSchema>;

export const GetApprovalRequestHistoryInputSchema = z.object({
  requestId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
});
export type GetApprovalRequestHistoryInput = z.input<typeof GetApprovalRequestHistoryInputSchema>;

export const ListPendingApprovalStepsInputSchema = z.object({
  tenantId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
});
export type ListPendingApprovalStepsInput = z.input<typeof ListPendingApprovalStepsInputSchema>;

/** Re-exported so callers of publishApprovalDefinition don't need a separate import from ../config/config.ts. */
export { ConfigVersionSchema, ApprovalStepInputSchema };
export type { ConfigVersion };

/** Maps a raw app.approval_requests row (snake_case) to this contract's camelCase shape. */
export function parseApprovalRequest(row: Record<string, unknown>): ApprovalRequest {
  return ApprovalRequestSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    configVersionId: row.config_version_id,
    entityType: row.entity_type,
    entityId: row.entity_id,
    pattern: row.pattern,
    status: row.status,
    idempotencyKey: row.idempotency_key,
    requestedByAuthUserId: row.requested_by_auth_user_id,
    requestedBy: row.requested_by,
    startedAt: row.started_at,
    endedAt: row.ended_at,
    endedReason: row.ended_reason,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Maps a raw app.approval_request_steps row (snake_case) to this contract's camelCase shape. */
export function parseApprovalRequestStep(row: Record<string, unknown>): ApprovalRequestStep {
  return ApprovalRequestStepSchema.parse({
    id: row.id,
    requestId: row.request_id,
    stepOrder: row.step_order,
    approverType: row.approver_type,
    roleId: row.role_id,
    specificUserId: row.specific_user_id,
    requiredApprovals: row.required_approvals,
    approvalsCount: row.approvals_count,
    status: row.status,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Maps a raw app.approval_delegations row (snake_case) to this contract's camelCase shape. */
export function parseApprovalDelegation(row: Record<string, unknown>): ApprovalDelegation {
  return ApprovalDelegationSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    delegatorAuthUserId: row.delegator_auth_user_id,
    delegateAuthUserId: row.delegate_auth_user_id,
    scope: row.scope,
    roleId: row.role_id,
    startsAt: row.starts_at,
    expiresAt: row.expires_at,
    createdBy: row.created_by,
    createdAt: row.created_at,
    revokedAt: row.revoked_at,
    revokedReason: row.revoked_reason,
  });
}

/** Maps a raw app.get_approval_request_history() row (snake_case) to this contract's camelCase shape. */
export function parseApprovalRequestHistoryEntry(row: Record<string, unknown>): ApprovalRequestHistoryEntry {
  return ApprovalRequestHistoryEntrySchema.parse({
    stepId: row.step_id,
    stepOrder: row.step_order,
    approverType: row.approver_type,
    stepStatus: row.step_status,
    decisionId: row.decision_id,
    actorAuthUserId: row.actor_auth_user_id,
    actorLabel: row.actor_label,
    decision: row.decision,
    reason: row.reason,
    decidedAt: row.decided_at,
  });
}
