/**
 * IP Restriction and Network Access contract (IAE-028, Prompt 356). Mirrors
 * supabase/migrations/20260807200000_create_intelligence_ip_restriction_network_access.sql's
 * app.ip_allowlist_policies/app.ip_allowlist_entries/app.ip_access_evaluations/
 * app.ip_allowlist_bypass_grants shapes and their set/add/revoke/assert/
 * request/approve/list RPCs.
 */

import { z } from "zod";

export const IP_ALLOWLIST_ENFORCEMENT_MODES = ["disabled", "dry_run", "enforced"] as const;
export const IpAllowlistEnforcementModeSchema = z.enum(IP_ALLOWLIST_ENFORCEMENT_MODES);
export type IpAllowlistEnforcementMode = z.infer<typeof IpAllowlistEnforcementModeSchema>;

export const IpAllowlistPolicySchema = z.object({
  tenantId: z.string().uuid(),
  enforcementMode: IpAllowlistEnforcementModeSchema,
  updatedBy: z.string().nullable(),
  updatedAt: z.string(),
});
export type IpAllowlistPolicy = z.infer<typeof IpAllowlistPolicySchema>;

export function parseIpAllowlistPolicy(row: Record<string, unknown>): IpAllowlistPolicy {
  return IpAllowlistPolicySchema.parse({
    tenantId: row.tenant_id,
    enforcementMode: row.enforcement_mode,
    updatedBy: row.updated_by,
    updatedAt: row.updated_at,
  });
}

export const IP_ALLOWLIST_ENTRY_SCOPES = ["ui", "api", "admin", "all"] as const;
export const IpAllowlistEntryScopeSchema = z.enum(IP_ALLOWLIST_ENTRY_SCOPES);
export type IpAllowlistEntryScope = z.infer<typeof IpAllowlistEntryScopeSchema>;

export const IpAllowlistEntrySchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  cidr: z.string(),
  label: z.string().nullable(),
  scope: IpAllowlistEntryScopeSchema,
  status: z.enum(["active", "revoked"]),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  revokedAt: z.string().nullable(),
  revokedBy: z.string().nullable(),
});
export type IpAllowlistEntry = z.infer<typeof IpAllowlistEntrySchema>;

export function parseIpAllowlistEntry(row: Record<string, unknown>): IpAllowlistEntry {
  return IpAllowlistEntrySchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    cidr: row.cidr,
    label: row.label,
    scope: row.scope,
    status: row.status,
    createdBy: row.created_by,
    createdAt: row.created_at,
    revokedAt: row.revoked_at,
    revokedBy: row.revoked_by,
  });
}

export const IP_ACCESS_EVALUATION_DECISIONS = ["allowed", "denied", "dry_run_would_deny"] as const;
export const IpAccessEvaluationDecisionSchema = z.enum(IP_ACCESS_EVALUATION_DECISIONS);
export type IpAccessEvaluationDecision = z.infer<typeof IpAccessEvaluationDecisionSchema>;

export const IpAccessEvaluationSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  subjectLabel: z.string().nullable(),
  ipAddress: z.string(),
  scope: z.string(),
  decision: IpAccessEvaluationDecisionSchema,
  matchedEntryId: z.string().uuid().nullable(),
  occurredAt: z.string(),
});
export type IpAccessEvaluation = z.infer<typeof IpAccessEvaluationSchema>;

export function parseIpAccessEvaluation(row: Record<string, unknown>): IpAccessEvaluation {
  return IpAccessEvaluationSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    subjectLabel: row.subject_label,
    ipAddress: row.ip_address,
    scope: row.scope,
    decision: row.decision,
    matchedEntryId: row.matched_entry_id,
    occurredAt: row.occurred_at,
  });
}

export const IpAllowlistBypassGrantSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  targetAuthUserId: z.string().uuid(),
  reason: z.string(),
  requestedByAuthUserId: z.string().uuid(),
  requestedBy: z.string().nullable(),
  approvedByAuthUserId: z.string().uuid().nullable(),
  approvedBy: z.string().nullable(),
  status: z.enum(["pending", "approved", "denied", "expired", "revoked"]),
  requestedAt: z.string(),
  decidedAt: z.string().nullable(),
  expiresAt: z.string(),
});
export type IpAllowlistBypassGrant = z.infer<typeof IpAllowlistBypassGrantSchema>;

export function parseIpAllowlistBypassGrant(row: Record<string, unknown>): IpAllowlistBypassGrant {
  return IpAllowlistBypassGrantSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    targetAuthUserId: row.target_auth_user_id,
    reason: row.reason,
    requestedByAuthUserId: row.requested_by_auth_user_id,
    requestedBy: row.requested_by,
    approvedByAuthUserId: row.approved_by_auth_user_id,
    approvedBy: row.approved_by,
    status: row.status,
    requestedAt: row.requested_at,
    decidedAt: row.decided_at,
    expiresAt: row.expires_at,
  });
}

export const SetIpAllowlistEnforcementModeInputSchema = z.object({
  tenantId: z.string().uuid(),
  enforcementMode: IpAllowlistEnforcementModeSchema,
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SetIpAllowlistEnforcementModeInput = z.input<typeof SetIpAllowlistEnforcementModeInputSchema>;

export const AddIpAllowlistEntryInputSchema = z.object({
  tenantId: z.string().uuid(),
  rawCidr: z.string().min(1),
  label: z.string().nullable(),
  scope: IpAllowlistEntryScopeSchema,
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type AddIpAllowlistEntryInput = z.input<typeof AddIpAllowlistEntryInputSchema>;

export const RevokeIpAllowlistEntryInputSchema = z.object({
  entryId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RevokeIpAllowlistEntryInput = z.input<typeof RevokeIpAllowlistEntryInputSchema>;

export const AssertIpAllowedInputSchema = z.object({
  tenantId: z.string().uuid(),
  rawIpAddress: z.string(),
  scope: z.string().min(1),
  subjectLabel: z.string().nullable(),
});
export type AssertIpAllowedInput = z.input<typeof AssertIpAllowedInputSchema>;

export const RequestIpAllowlistBypassInputSchema = z.object({
  tenantId: z.string().uuid(),
  targetAuthUserId: z.string().uuid(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RequestIpAllowlistBypassInput = z.input<typeof RequestIpAllowlistBypassInputSchema>;

export const ApproveIpAllowlistBypassInputSchema = z.object({
  grantId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ApproveIpAllowlistBypassInput = z.input<typeof ApproveIpAllowlistBypassInputSchema>;
