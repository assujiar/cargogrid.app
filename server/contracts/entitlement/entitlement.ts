/**
 * Entitlement contract (PLT-106, CG-S6-PLT-003). Mirrors
 * supabase/migrations/20260716094432_create_entitlements.sql's app.entitlement_decision
 * composite type and the app.assign_entitlement/app.transition_entitlement_status RPCs.
 * The SQL migration is the source of truth for shape and precedence; this file is a typed
 * client-side view of that same contract.
 */

import { z } from "zod";

export const ENTITLEMENT_STATUSES = ["trial", "active", "suspended", "expired", "cancelled"] as const;
export const EntitlementStatusSchema = z.enum(ENTITLEMENT_STATUSES);
export type EntitlementStatus = z.infer<typeof EntitlementStatusSchema>;

export const EntitlementDecisionSchema = z.object({
  allowed: z.boolean(),
  reason: z.string(),
  limitValue: z.number().nullable(),
  packageCode: z.string().nullable(),
  evaluatedAt: z.string(),
});
export type EntitlementDecision = z.infer<typeof EntitlementDecisionSchema>;

export const EvaluateEntitlementInputSchema = z.object({
  tenantId: z.string().uuid(),
  moduleCode: z.string().min(1),
  featureCode: z.string().min(1).optional(),
  asOf: z.string().optional(),
});
export type EvaluateEntitlementInput = z.infer<typeof EvaluateEntitlementInputSchema>;

export const AssignEntitlementInputSchema = z.object({
  tenantId: z.string().uuid(),
  packageId: z.string().uuid(),
  status: z.enum(["trial", "active"]),
  reason: z.string().min(1),
  requestedBy: z.string().min(1),
  trialEndsAt: z.string().optional(),
  effectiveFrom: z.string().optional(),
  effectiveUntil: z.string().optional(),
});
export type AssignEntitlementInput = z.infer<typeof AssignEntitlementInputSchema>;

export const TransitionEntitlementInputSchema = z.object({
  tenantId: z.string().uuid(),
  newStatus: EntitlementStatusSchema,
  reason: z.string().min(1),
  requestedBy: z.string().min(1),
});
export type TransitionEntitlementInput = z.infer<typeof TransitionEntitlementInputSchema>;

/** Maps a raw app.entitlement_decision row (snake_case) to this contract's camelCase shape. */
export function parseEntitlementDecision(row: Record<string, unknown>): EntitlementDecision {
  return EntitlementDecisionSchema.parse({
    allowed: row.allowed,
    reason: row.reason,
    limitValue: row.limit_value,
    packageCode: row.package_code,
    evaluatedAt: row.evaluated_at,
  });
}
