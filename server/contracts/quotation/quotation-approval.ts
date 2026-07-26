/**
 * Quotation Approval contract (COM-153, CG-S7-COM-012). Mirrors
 * supabase/migrations/20260724270000_create_commercial_quotation_approval.sql's
 * app.quotation_approval_rules shape and its create/publish RPCs, plus the input schema for
 * app.decide_quotation_approval_step -- the one domain-specific sync wrapper this migration
 * adds over the already-VERIFIED Approval Engine (PLT-123, server/contracts/approval/
 * approval.ts). Delegation/escalation/history/inbox reads still go through that generic
 * Approval Engine contract directly -- there is no quotation-specific duplicate of those.
 */

import { z } from "zod";

export const QUOTATION_APPROVAL_RULE_STATUSES = ["draft", "published", "archived"] as const;
export const QuotationApprovalRuleStatusSchema = z.enum(QUOTATION_APPROVAL_RULE_STATUSES);
export type QuotationApprovalRuleStatus = z.infer<typeof QuotationApprovalRuleStatusSchema>;

/** Maps a raw app.quotation_approval_rules row (snake_case) to this contract's camelCase shape. Tenant-wide reference/policy data -- never field-masked (this migration's own header, mirroring app.margin_rule_versions, COM-150). */
export const QuotationApprovalRuleVersionSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  minMarginPct: z.coerce.number().nullable(),
  maxDiscountPct: z.coerce.number().nullable(),
  minValueAmount: z.coerce.number().nullable(),
  status: QuotationApprovalRuleStatusSchema,
  supersedesVersionId: z.string().uuid().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type QuotationApprovalRuleVersion = z.infer<typeof QuotationApprovalRuleVersionSchema>;

export function parseQuotationApprovalRuleVersion(row: Record<string, unknown>): QuotationApprovalRuleVersion {
  return QuotationApprovalRuleVersionSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    minMarginPct: row.min_margin_pct,
    maxDiscountPct: row.max_discount_pct,
    minValueAmount: row.min_value_amount,
    status: row.status,
    supersedesVersionId: row.supersedes_version_id,
    recordVersion: row.record_version,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Maps app.evaluate_quotation_approval_requirement()'s returned row. Reason codes only, never a dollar figure -- safe regardless of COM:View cost/selling price. */
export const QuotationApprovalRequirementSchema = z.object({
  required: z.boolean(),
  reasons: z.array(z.string()),
  ruleVersionId: z.string().uuid().nullable(),
});
export type QuotationApprovalRequirement = z.infer<typeof QuotationApprovalRequirementSchema>;

export function parseQuotationApprovalRequirement(row: Record<string, unknown>): QuotationApprovalRequirement {
  return QuotationApprovalRequirementSchema.parse({
    required: row.required,
    reasons: row.reasons ?? [],
    ruleVersionId: row.rule_version_id,
  });
}

const MIN_MARGIN_PCT = z.coerce.number().min(0).max(100).nullable().default(null);
const MAX_DISCOUNT_PCT = z.coerce.number().min(0).max(100).nullable().default(null);
const MIN_VALUE_AMOUNT = z.coerce.number().min(0).nullable().default(null);

export const CreateQuotationApprovalRuleVersionInputSchema = z
  .object({
    tenantId: z.string().uuid(),
    minMarginPct: MIN_MARGIN_PCT,
    maxDiscountPct: MAX_DISCOUNT_PCT,
    minValueAmount: MIN_VALUE_AMOUNT,
    actorAuthUserId: z.string().uuid(),
    createdBy: z.string().min(1),
  })
  .refine((input) => input.minMarginPct !== null || input.maxDiscountPct !== null || input.minValueAmount !== null, {
    message: "At least one of minMarginPct/maxDiscountPct/minValueAmount is required",
  });
export type CreateQuotationApprovalRuleVersionInput = z.input<typeof CreateQuotationApprovalRuleVersionInputSchema>;

export const PublishQuotationApprovalRuleVersionInputSchema = z.object({
  ruleVersionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  supersedesVersionId: z.string().uuid().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type PublishQuotationApprovalRuleVersionInput = z.input<typeof PublishQuotationApprovalRuleVersionInputSchema>;

export const EvaluateQuotationApprovalRequirementInputSchema = z.object({
  quotationId: z.string().uuid(),
});
export type EvaluateQuotationApprovalRequirementInput = z.input<typeof EvaluateQuotationApprovalRequirementInputSchema>;

/** app.decide_quotation_approval_step's decision is the same approved/rejected verb the Approval Engine itself supports (this migration's own header: "request revision" is not a fourth verb -- reject with a reason, then app.create_quotation_revision). */
export const DecideQuotationApprovalStepInputSchema = z.object({
  requestStepId: z.string().uuid(),
  decision: z.enum(["approved", "rejected"]),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
  reason: z.string().nullable().default(null),
});
export type DecideQuotationApprovalStepInput = z.input<typeof DecideQuotationApprovalStepInputSchema>;
