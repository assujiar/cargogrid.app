/**
 * Support access and impersonation contract (PLT-115, CG-S6-PLT-012). Mirrors
 * supabase/migrations/20260716111315_create_support_access.sql's app.support_access_grants
 * / app.support_access_sessions shapes and the app.request_support_access /
 * app.approve_support_access / app.deny_support_access / app.revoke_support_access /
 * app.start_support_session / app.end_support_session /
 * app.complete_support_access_post_review RPCs.
 */

import { z } from "zod";

export const SUPPORT_ACCESS_SCOPES = ["read_only", "read_write"] as const;
export const SupportAccessScopeSchema = z.enum(SUPPORT_ACCESS_SCOPES);
export type SupportAccessScope = z.infer<typeof SupportAccessScopeSchema>;

export const SUPPORT_ACCESS_GRANT_STATUSES = ["pending_approval", "approved", "denied", "revoked"] as const;
export const SupportAccessGrantStatusSchema = z.enum(SUPPORT_ACCESS_GRANT_STATUSES);
export type SupportAccessGrantStatus = z.infer<typeof SupportAccessGrantStatusSchema>;

export const SUPPORT_ACCESS_SESSION_ENDED_REASONS = ["manual_end", "revoked", "expired"] as const;
export const SupportAccessSessionEndedReasonSchema = z.enum(SUPPORT_ACCESS_SESSION_ENDED_REASONS);
export type SupportAccessSessionEndedReason = z.infer<typeof SupportAccessSessionEndedReasonSchema>;

export const SupportAccessGrantSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  granteeAuthUserId: z.string().uuid(),
  reason: z.string(),
  caseId: z.string(),
  scope: SupportAccessScopeSchema,
  emergency: z.boolean(),
  status: SupportAccessGrantStatusSchema,
  requestedBy: z.string(),
  requestedAt: z.string(),
  authorizedByAuthUserId: z.string().uuid().nullable(),
  approvedBy: z.string().nullable(),
  grantedAt: z.string().nullable(),
  deniedBy: z.string().nullable(),
  deniedAt: z.string().nullable(),
  denialReason: z.string().nullable(),
  expiresAt: z.string(),
  revokedAt: z.string().nullable(),
  revokedBy: z.string().nullable(),
  revokedReason: z.string().nullable(),
  postReviewCompletedAt: z.string().nullable(),
  postReviewBy: z.string().nullable(),
  postReviewNote: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type SupportAccessGrant = z.infer<typeof SupportAccessGrantSchema>;

export const SupportAccessSessionSchema = z.object({
  id: z.string().uuid(),
  grantId: z.string().uuid(),
  tenantId: z.string().uuid(),
  granteeAuthUserId: z.string().uuid(),
  reauthConfirmedAt: z.string(),
  startedAt: z.string(),
  endedAt: z.string().nullable(),
  endedReason: SupportAccessSessionEndedReasonSchema.nullable(),
  createdAt: z.string(),
});
export type SupportAccessSession = z.infer<typeof SupportAccessSessionSchema>;

export const RequestSupportAccessInputSchema = z.object({
  tenantId: z.string().uuid(),
  granteeAuthUserId: z.string().uuid(),
  reason: z.string().min(1),
  caseId: z.string().min(1),
  expiryMinutes: z.number().int().positive(),
  requestedBy: z.string().min(1),
  scope: SupportAccessScopeSchema.default("read_only"),
  emergency: z.boolean().default(false),
  authorizedByAuthUserId: z.string().uuid().nullable().default(null),
});
export type RequestSupportAccessInput = z.input<typeof RequestSupportAccessInputSchema>;

export const ApproveSupportAccessInputSchema = z.object({
  grantId: z.string().uuid(),
  approverAuthUserId: z.string().uuid(),
  approvedBy: z.string().min(1),
  expiresAt: z.string().nullable().default(null),
});
export type ApproveSupportAccessInput = z.input<typeof ApproveSupportAccessInputSchema>;

export const DenySupportAccessInputSchema = z.object({
  grantId: z.string().uuid(),
  denierAuthUserId: z.string().uuid(),
  deniedBy: z.string().min(1),
  reason: z.string().min(1),
});
export type DenySupportAccessInput = z.infer<typeof DenySupportAccessInputSchema>;

export const RevokeSupportAccessInputSchema = z.object({
  grantId: z.string().uuid(),
  revokerAuthUserId: z.string().uuid(),
  revokedBy: z.string().min(1),
  reason: z.string().min(1),
});
export type RevokeSupportAccessInput = z.infer<typeof RevokeSupportAccessInputSchema>;

export const StartSupportSessionInputSchema = z.object({
  grantId: z.string().uuid(),
  reauthConfirmedAt: z.string(),
  startedBy: z.string().min(1),
});
export type StartSupportSessionInput = z.infer<typeof StartSupportSessionInputSchema>;

export const EndSupportSessionInputSchema = z.object({
  sessionId: z.string().uuid(),
  endedBy: z.string().min(1),
  endedReason: SupportAccessSessionEndedReasonSchema.default("manual_end"),
});
export type EndSupportSessionInput = z.input<typeof EndSupportSessionInputSchema>;

export const CompleteSupportAccessPostReviewInputSchema = z.object({
  grantId: z.string().uuid(),
  reviewerAuthUserId: z.string().uuid(),
  note: z.string().min(1),
});
export type CompleteSupportAccessPostReviewInput = z.infer<typeof CompleteSupportAccessPostReviewInputSchema>;

/** Maps a raw app.support_access_grants row (snake_case) to this contract's camelCase shape. */
export function parseSupportAccessGrant(row: Record<string, unknown>): SupportAccessGrant {
  return SupportAccessGrantSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    granteeAuthUserId: row.grantee_auth_user_id,
    reason: row.reason,
    caseId: row.case_id,
    scope: row.scope,
    emergency: row.emergency,
    status: row.status,
    requestedBy: row.requested_by,
    requestedAt: row.requested_at,
    authorizedByAuthUserId: row.authorized_by_auth_user_id,
    approvedBy: row.approved_by,
    grantedAt: row.granted_at,
    deniedBy: row.denied_by,
    deniedAt: row.denied_at,
    denialReason: row.denial_reason,
    expiresAt: row.expires_at,
    revokedAt: row.revoked_at,
    revokedBy: row.revoked_by,
    revokedReason: row.revoked_reason,
    postReviewCompletedAt: row.post_review_completed_at,
    postReviewBy: row.post_review_by,
    postReviewNote: row.post_review_note,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Maps a raw app.support_access_sessions row (snake_case) to this contract's camelCase shape. */
export function parseSupportAccessSession(row: Record<string, unknown>): SupportAccessSession {
  return SupportAccessSessionSchema.parse({
    id: row.id,
    grantId: row.grant_id,
    tenantId: row.tenant_id,
    granteeAuthUserId: row.grantee_auth_user_id,
    reauthConfirmedAt: row.reauth_confirmed_at,
    startedAt: row.started_at,
    endedAt: row.ended_at,
    endedReason: row.ended_reason,
    createdAt: row.created_at,
  });
}

/**
 * Reusable impersonation banner state (Prompt 115 §15: "Reusable impersonation
 * banner/context/reason/end action and denied/expired states; full portal integration
 * later"). A pure derivation from a session/grant pair -- no live portal-shell component
 * exists yet in this repository (Phase 1 has not reached PLT-135/136, the Admin portals),
 * so this is the same "mechanism proven, live UI wiring deferred" posture every capability
 * since PLT-107 has used, not a fabricated component.
 */
export const SupportSessionBannerSchema = z.object({
  visible: z.boolean(),
  tenantId: z.string().uuid(),
  caseId: z.string(),
  reason: z.string(),
  emergency: z.boolean(),
  expiresAt: z.string(),
  secondsRemaining: z.number().int(),
  state: z.enum(["active", "no_session"]),
});
export type SupportSessionBanner = z.infer<typeof SupportSessionBannerSchema>;

/**
 * Derives the banner a portal shell would render for an open support session, or a
 * `no_session` state if none is open. Underlying identity never changes (Prompt 115 §24) --
 * this banner is what makes that fact visible to the tenant user watching the screen, not a
 * mechanism that itself changes anything.
 */
export function deriveSupportSessionBanner(
  grant: Pick<SupportAccessGrant, "tenantId" | "caseId" | "reason" | "emergency" | "expiresAt">,
  session: Pick<SupportAccessSession, "endedAt"> | null,
  now: Date = new Date(),
): SupportSessionBanner {
  if (!session || session.endedAt !== null) {
    return {
      visible: false,
      tenantId: grant.tenantId,
      caseId: grant.caseId,
      reason: grant.reason,
      emergency: grant.emergency,
      expiresAt: grant.expiresAt,
      secondsRemaining: 0,
      state: "no_session",
    };
  }

  const secondsRemaining = Math.max(0, Math.floor((new Date(grant.expiresAt).getTime() - now.getTime()) / 1000));

  return {
    visible: true,
    tenantId: grant.tenantId,
    caseId: grant.caseId,
    reason: grant.reason,
    emergency: grant.emergency,
    expiresAt: grant.expiresAt,
    secondsRemaining,
    state: "active",
  };
}
