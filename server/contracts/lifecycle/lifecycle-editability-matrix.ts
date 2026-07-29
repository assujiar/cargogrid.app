/**
 * Static TypeScript mirror of app.finance_lifecycle_editability_matrix
 * (FIN-205, supabase/migrations/20260729190000_create_finance_lifecycle_state_control.sql).
 *
 * Every Finance list page renders its own canonical-state badge and
 * locked-reason text directly from this table -- entityType and
 * concreteStatus are already present on every already-fetched row, so no
 * extra per-row (or even per-page) network round trip is needed to label
 * them (Prompt 205 section 17: "without per-row N+1 checks"). This is a
 * disclosed, must-stay-in-sync mirror of the database table, the same
 * "mirrors X's own convention" pattern this repository already uses
 * elsewhere (e.g. FIN-194's own currency-code seed). The database table
 * and app.get_finance_lifecycle_editability/app.get_finance_lifecycle_record_state
 * remain the authoritative source for anything requiring server-side
 * enforcement, not this client-facing copy.
 */

import type { FinanceLifecycleCanonicalState, FinanceLifecycleEntityType } from "./lifecycle.ts";

export interface FinanceLifecycleEditabilityEntry {
  readonly canonicalState: FinanceLifecycleCanonicalState;
  readonly isEditable: boolean;
  readonly allowedActions: readonly string[];
  readonly lockedReason: string | null;
  readonly postedTriggerProtected: boolean;
}

const FINANCE_LIFECYCLE_EDITABILITY_MATRIX: Record<FinanceLifecycleEntityType, Record<string, FinanceLifecycleEditabilityEntry>> = {
  invoice: {
    draft: { canonicalState: "draft", isEditable: false, allowedActions: ["submit", "discard"], lockedReason: null, postedTriggerProtected: false },
    submitted: { canonicalState: "in_review", isEditable: false, allowedActions: ["approve", "discard"], lockedReason: "awaiting_approval", postedTriggerProtected: false },
    approved: { canonicalState: "approved", isEditable: false, allowedActions: ["issue"], lockedReason: "awaiting_post", postedTriggerProtected: false },
    issued: { canonicalState: "posted", isEditable: false, allowedActions: [], lockedReason: "posted_immutable_normal_role", postedTriggerProtected: false },
    void: { canonicalState: "discarded", isEditable: false, allowedActions: [], lockedReason: "discarded", postedTriggerProtected: false },
  },
  vendor_bill: {
    draft: { canonicalState: "draft", isEditable: false, allowedActions: ["submit", "discard"], lockedReason: null, postedTriggerProtected: false },
    submitted: { canonicalState: "in_review", isEditable: false, allowedActions: ["approve", "discard"], lockedReason: "awaiting_approval", postedTriggerProtected: false },
    approved: { canonicalState: "approved", isEditable: false, allowedActions: ["post"], lockedReason: "awaiting_post", postedTriggerProtected: false },
    posted: { canonicalState: "posted", isEditable: false, allowedActions: [], lockedReason: "posted_immutable_normal_role", postedTriggerProtected: false },
    void: { canonicalState: "discarded", isEditable: false, allowedActions: [], lockedReason: "discarded", postedTriggerProtected: false },
  },
  receipt: {
    captured: { canonicalState: "posted", isEditable: false, allowedActions: ["allocate", "request_deallocation"], lockedReason: null, postedTriggerProtected: false },
    void: { canonicalState: "discarded", isEditable: false, allowedActions: [], lockedReason: "discarded", postedTriggerProtected: false },
  },
  settlement: {
    draft: { canonicalState: "draft", isEditable: false, allowedActions: ["submit", "discard"], lockedReason: null, postedTriggerProtected: false },
    submitted: { canonicalState: "in_review", isEditable: false, allowedActions: ["approve", "discard"], lockedReason: "awaiting_approval", postedTriggerProtected: false },
    approved: { canonicalState: "approved", isEditable: false, allowedActions: ["execute"], lockedReason: "awaiting_execution", postedTriggerProtected: false },
    executed: { canonicalState: "approved", isEditable: false, allowedActions: ["post"], lockedReason: "awaiting_post", postedTriggerProtected: false },
    posted: { canonicalState: "posted", isEditable: false, allowedActions: ["request_reversal"], lockedReason: "posted_correction_via_governed_reversal_only", postedTriggerProtected: false },
    void: { canonicalState: "discarded", isEditable: false, allowedActions: [], lockedReason: "discarded", postedTriggerProtected: false },
    reversed: { canonicalState: "corrected", isEditable: false, allowedActions: [], lockedReason: "corrected_terminal", postedTriggerProtected: false },
  },
  subledger_batch: {
    posted: { canonicalState: "posted", isEditable: false, allowedActions: [], lockedReason: "system_generated_posted_immutable_normal_role", postedTriggerProtected: false },
    reversed: { canonicalState: "corrected", isEditable: false, allowedActions: [], lockedReason: "corrected_terminal", postedTriggerProtected: false },
  },
  journal: {
    draft: { canonicalState: "draft", isEditable: false, allowedActions: ["submit", "discard"], lockedReason: null, postedTriggerProtected: false },
    submitted: { canonicalState: "in_review", isEditable: false, allowedActions: ["approve", "discard"], lockedReason: "awaiting_approval", postedTriggerProtected: false },
    approved: { canonicalState: "approved", isEditable: false, allowedActions: ["post"], lockedReason: "awaiting_post", postedTriggerProtected: false },
    posted: { canonicalState: "posted", isEditable: false, allowedActions: [], lockedReason: "posted_immutable_normal_role", postedTriggerProtected: true },
    void: { canonicalState: "discarded", isEditable: false, allowedActions: [], lockedReason: "discarded", postedTriggerProtected: false },
  },
};

/**
 * Resolves the canonical-state/editability entry for one (entityType,
 * concreteStatus) pair from the static mirror above. Falls back to a
 * neutral "unmapped" entry rather than throwing -- the database function
 * app.get_finance_lifecycle_editability is the authoritative rejection
 * path for a genuinely unmapped pair; this client-facing mirror degrades
 * gracefully instead of crashing a list page render.
 */
export function resolveFinanceLifecycleEditability(
  entityType: FinanceLifecycleEntityType,
  concreteStatus: string,
): FinanceLifecycleEditabilityEntry {
  return (
    FINANCE_LIFECYCLE_EDITABILITY_MATRIX[entityType]?.[concreteStatus] ?? {
      // Safest assume-nothing-can-be-done default for a pair this mirror
      // does not recognize -- never implies an action is available.
      canonicalState: "posted",
      isEditable: false,
      allowedActions: [],
      lockedReason: "unmapped_lifecycle_state",
      postedTriggerProtected: false,
    }
  );
}
