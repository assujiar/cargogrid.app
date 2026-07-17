/**
 * RBAC evaluation contract (PLT-112, CG-S6-PLT-009). Mirrors
 * supabase/migrations/20260716104519_create_rbac_evaluator.sql's app.rbac_decision
 * composite and app.evaluate_permission RPC. Stage 3 of the 8-stage access flow
 * (docs/architecture/06_RLS_RBAC_WORKSTREAM.md §3) -- never a replacement for RLS
 * (PLT-113) or field/record checks (PLT-114).
 */

import { z } from "zod";

export const RbacDecisionSchema = z.object({
  allowed: z.boolean(),
  reason: z.string(),
  permissionId: z.string().uuid().nullable(),
  roleId: z.string().uuid().nullable(),
  roleVersionId: z.string().uuid().nullable(),
  evaluatedAt: z.string(),
});
export type RbacDecision = z.infer<typeof RbacDecisionSchema>;

export const EvaluatePermissionInputSchema = z.object({
  authUserId: z.string().uuid(),
  tenantId: z.string().uuid(),
  resourceModuleCode: z.string().min(1),
  action: z.string().min(1),
  asOf: z.string().optional(),
});
export type EvaluatePermissionInput = z.infer<typeof EvaluatePermissionInputSchema>;

/** Maps a raw app.rbac_decision composite (snake_case) to this contract's camelCase shape. */
export function parseRbacDecision(row: Record<string, unknown>): RbacDecision {
  return RbacDecisionSchema.parse({
    allowed: row.allowed,
    reason: row.reason,
    permissionId: row.permission_id,
    roleId: row.role_id,
    roleVersionId: row.role_version_id,
    evaluatedAt: row.evaluated_at,
  });
}
