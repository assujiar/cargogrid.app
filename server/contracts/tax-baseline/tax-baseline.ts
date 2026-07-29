/**
 * Tax Baseline contract (FIN-195, CG-S9-FIN-006). Mirrors
 * supabase/migrations/20260729090000_create_finance_tax_baseline.sql's
 * app.finance_tax_codes / app.finance_tax_rule_versions shapes and their RPCs.
 */

import { z } from "zod";

export const FinanceTaxTypeSchema = z.enum(["vat", "withholding", "exempt", "other"]);
export type FinanceTaxType = z.infer<typeof FinanceTaxTypeSchema>;

export const FinanceTaxCodeSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid().nullable(),
  code: z.string(),
  name: z.string(),
  taxType: FinanceTaxTypeSchema,
  jurisdictionCountry: z.string(),
  isRecoverable: z.boolean(),
  isActive: z.boolean(),
});
export type FinanceTaxCode = z.infer<typeof FinanceTaxCodeSchema>;

export const FINANCE_TAX_RULE_STATUSES = ["draft", "approved", "archived"] as const;
export const FinanceTaxRuleStatusSchema = z.enum(FINANCE_TAX_RULE_STATUSES);
export type FinanceTaxRuleStatus = z.infer<typeof FinanceTaxRuleStatusSchema>;

export const FinanceTaxRateBasisSchema = z.enum(["percentage", "fixed_amount"]);
export type FinanceTaxRateBasis = z.infer<typeof FinanceTaxRateBasisSchema>;

export const FinanceTaxRuleVersionSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid().nullable(),
  taxCodeId: z.string().uuid(),
  rateBasis: FinanceTaxRateBasisSchema,
  rateValue: z.number(),
  currency: z.string().nullable(),
  outputAccountId: z.string().uuid().nullable(),
  recoverableAccountId: z.string().uuid().nullable(),
  effectiveFrom: z.string(),
  effectiveTo: z.string().nullable(),
  status: FinanceTaxRuleStatusSchema,
  isExampleFixture: z.boolean(),
  evidenceReferenceFileId: z.string().uuid().nullable(),
  evidenceNote: z.string().nullable(),
  approvedBy: z.string().nullable(),
  approvedAt: z.string().nullable(),
  archivedReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type FinanceTaxRuleVersion = z.infer<typeof FinanceTaxRuleVersionSchema>;

export const FinanceTaxCalculationSchema = z.object({
  baseAmount: z.number(),
  taxCode: z.string(),
  ruleVersionId: z.string().uuid(),
  rateBasis: FinanceTaxRateBasisSchema,
  rateValue: z.number(),
  currency: z.string().nullable(),
  taxAmount: z.number(),
  roundingMode: z.string(),
  effectiveFrom: z.string(),
  effectiveTo: z.string().nullable(),
});
export type FinanceTaxCalculation = z.infer<typeof FinanceTaxCalculationSchema>;

export const CreateFinanceTaxRuleDraftInputSchema = z.object({
  tenantId: z.string().uuid().nullable().default(null),
  taxCodeId: z.string().uuid(),
  rateBasis: FinanceTaxRateBasisSchema,
  rateValue: z.number().min(0),
  currency: z.string().regex(/^[A-Z]{3}$/).nullable().default(null),
  outputAccountId: z.string().uuid().nullable().default(null),
  recoverableAccountId: z.string().uuid().nullable().default(null),
  effectiveFrom: z.string(),
  effectiveTo: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  createdBy: z.string().min(1),
});
export type CreateFinanceTaxRuleDraftInput = z.input<typeof CreateFinanceTaxRuleDraftInputSchema>;

export const AttachFinanceTaxRuleEvidenceInputSchema = z.object({
  ruleId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  evidenceReferenceFileId: z.string().uuid().nullable().default(null),
  evidenceNote: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type AttachFinanceTaxRuleEvidenceInput = z.input<typeof AttachFinanceTaxRuleEvidenceInputSchema>;

export const DiscardFinanceTaxRuleDraftInputSchema = z.object({
  ruleId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type DiscardFinanceTaxRuleDraftInput = z.input<typeof DiscardFinanceTaxRuleDraftInputSchema>;

export const ApproveFinanceTaxRuleInputSchema = z.object({
  ruleId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ApproveFinanceTaxRuleInput = z.input<typeof ApproveFinanceTaxRuleInputSchema>;

export const CalculateFinanceTaxInputSchema = z.object({
  tenantId: z.string().uuid().nullable(),
  taxCode: z.string().min(1),
  baseAmount: z.number().min(0),
  asOf: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
});
export type CalculateFinanceTaxInput = z.input<typeof CalculateFinanceTaxInputSchema>;

/** Maps a raw app.finance_tax_codes row (snake_case) to this contract's camelCase shape. */
export function parseFinanceTaxCode(row: Record<string, unknown>): FinanceTaxCode {
  return FinanceTaxCodeSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    code: row.code,
    name: row.name,
    taxType: row.tax_type,
    jurisdictionCountry: row.jurisdiction_country,
    isRecoverable: row.is_recoverable,
    isActive: row.is_active,
  });
}

/** Maps a raw app.finance_tax_rule_versions row (snake_case) to this contract's camelCase shape. */
export function parseFinanceTaxRuleVersion(row: Record<string, unknown>): FinanceTaxRuleVersion {
  return FinanceTaxRuleVersionSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    taxCodeId: row.tax_code_id,
    rateBasis: row.rate_basis,
    rateValue: typeof row.rate_value === "string" ? Number(row.rate_value) : row.rate_value,
    currency: row.currency,
    outputAccountId: row.output_account_id,
    recoverableAccountId: row.recoverable_account_id,
    effectiveFrom: row.effective_from,
    effectiveTo: row.effective_to,
    status: row.status,
    isExampleFixture: row.is_example_fixture,
    evidenceReferenceFileId: row.evidence_reference_file_id,
    evidenceNote: row.evidence_note,
    approvedBy: row.approved_by,
    approvedAt: row.approved_at,
    archivedReason: row.archived_reason,
    recordVersion: row.record_version,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Maps a raw app.calculate_finance_tax() jsonb result to this contract's camelCase shape. */
export function parseFinanceTaxCalculation(row: Record<string, unknown>): FinanceTaxCalculation {
  return FinanceTaxCalculationSchema.parse({
    baseAmount: row.baseAmount,
    taxCode: row.taxCode,
    ruleVersionId: row.ruleVersionId,
    rateBasis: row.rateBasis,
    rateValue: typeof row.rateValue === "string" ? Number(row.rateValue) : row.rateValue,
    currency: row.currency ?? null,
    taxAmount: typeof row.taxAmount === "string" ? Number(row.taxAmount) : row.taxAmount,
    roundingMode: row.roundingMode,
    effectiveFrom: row.effectiveFrom,
    effectiveTo: row.effectiveTo ?? null,
  });
}
