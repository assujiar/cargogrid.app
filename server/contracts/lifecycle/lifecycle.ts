/**
 * Draft-versus-Posted State Control contract (FIN-205, CG-S9-FIN-016).
 * Mirrors supabase/migrations/20260729190000_create_finance_lifecycle_state_control.sql's
 * app.finance_lifecycle_editability_matrix shape and the jsonb result of
 * app.get_finance_lifecycle_record_state.
 */

import { z } from "zod";

export const FINANCE_LIFECYCLE_ENTITY_TYPES = [
  "invoice",
  "vendor_bill",
  "receipt",
  "settlement",
  "subledger_batch",
  "journal",
] as const;
export const FinanceLifecycleEntityTypeSchema = z.enum(FINANCE_LIFECYCLE_ENTITY_TYPES);
export type FinanceLifecycleEntityType = z.infer<typeof FinanceLifecycleEntityTypeSchema>;

export const FINANCE_LIFECYCLE_CANONICAL_STATES = [
  "draft",
  "in_review",
  "approved",
  "posted",
  "corrected",
  "discarded",
] as const;
export const FinanceLifecycleCanonicalStateSchema = z.enum(FINANCE_LIFECYCLE_CANONICAL_STATES);
export type FinanceLifecycleCanonicalState = z.infer<typeof FinanceLifecycleCanonicalStateSchema>;

/**
 * The jsonb shape app.get_finance_lifecycle_record_state returns. Fields are
 * already camelCase at the database boundary (built via jsonb_build_object),
 * unlike a raw table-row parse elsewhere in this codebase.
 */
export const FinanceLifecycleRecordStateSchema = z.object({
  entityType: FinanceLifecycleEntityTypeSchema,
  recordId: z.string().uuid(),
  tenantId: z.string().uuid(),
  concreteStatus: z.string(),
  canonicalState: FinanceLifecycleCanonicalStateSchema,
  recordVersion: z.number().int().nullable(),
  isEditable: z.boolean(),
  allowedActions: z.array(z.string()),
  lockedReason: z.string().nullable(),
  postedTriggerProtected: z.boolean(),
});
export type FinanceLifecycleRecordState = z.infer<typeof FinanceLifecycleRecordStateSchema>;

export function parseFinanceLifecycleRecordState(row: Record<string, unknown>): FinanceLifecycleRecordState {
  return FinanceLifecycleRecordStateSchema.parse(row);
}
