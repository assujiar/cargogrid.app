/**
 * Reconciliation contract (FIN-209, CG-S9-FIN-020). Mirrors
 * supabase/migrations/20260729230000_create_finance_reconciliation.sql's
 * app.finance_reconciliation_runs / app.finance_reconciliation_exceptions
 * shapes and their RPCs.
 */

import { z } from "zod";

export const FINANCE_RECONCILIATION_SCOPES = ["ar", "ap"] as const;
export const FinanceReconciliationScopeSchema = z.enum(FINANCE_RECONCILIATION_SCOPES);
export type FinanceReconciliationScope = z.infer<typeof FinanceReconciliationScopeSchema>;

export const FINANCE_RECONCILIATION_RUN_STATUSES = ["completed", "certified"] as const;
export const FinanceReconciliationRunStatusSchema = z.enum(FINANCE_RECONCILIATION_RUN_STATUSES);
export type FinanceReconciliationRunStatus = z.infer<typeof FinanceReconciliationRunStatusSchema>;

export const FinanceReconciliationRunSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  companyId: z.string().uuid().nullable(),
  scope: FinanceReconciliationScopeSchema,
  asOfDate: z.string(),
  toleranceAmount: z.number(),
  controlTotal: z.number(),
  sourceTotal: z.number(),
  varianceAmount: z.number(),
  isWithinTolerance: z.boolean(),
  status: FinanceReconciliationRunStatusSchema,
  certifyReason: z.string().nullable(),
  certifiedBy: z.string().nullable(),
  certifiedAt: z.string().nullable(),
  preparedBy: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type FinanceReconciliationRun = z.infer<typeof FinanceReconciliationRunSchema>;

export const FINANCE_RECONCILIATION_EXCEPTION_STATUSES = ["open", "resolved"] as const;
export const FinanceReconciliationExceptionStatusSchema = z.enum(FINANCE_RECONCILIATION_EXCEPTION_STATUSES);
export type FinanceReconciliationExceptionStatus = z.infer<typeof FinanceReconciliationExceptionStatusSchema>;

export const FinanceReconciliationExceptionSchema = z.object({
  id: z.string().uuid(),
  runId: z.string().uuid(),
  tenantId: z.string().uuid(),
  itemType: z.string(),
  description: z.string(),
  expectedAmount: z.number(),
  actualAmount: z.number(),
  varianceAmount: z.number(),
  status: FinanceReconciliationExceptionStatusSchema,
  owner: z.string().nullable(),
  resolutionReason: z.string().nullable(),
  resolvedBy: z.string().nullable(),
  resolvedAt: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type FinanceReconciliationException = z.infer<typeof FinanceReconciliationExceptionSchema>;

export const ExecuteFinanceReconciliationRunInputSchema = z.object({
  tenantId: z.string().uuid(),
  companyId: z.string().uuid().nullable().default(null),
  scope: FinanceReconciliationScopeSchema,
  asOfDate: z.string(),
  toleranceAmount: z.number().min(0).default(0),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ExecuteFinanceReconciliationRunInput = z.input<typeof ExecuteFinanceReconciliationRunInputSchema>;

export const CertifyFinanceReconciliationRunInputSchema = z.object({
  runId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CertifyFinanceReconciliationRunInput = z.input<typeof CertifyFinanceReconciliationRunInputSchema>;

export const ResolveFinanceReconciliationExceptionInputSchema = z.object({
  exceptionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  resolutionReason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ResolveFinanceReconciliationExceptionInput = z.input<typeof ResolveFinanceReconciliationExceptionInputSchema>;

/** Maps a raw app.finance_reconciliation_runs row (snake_case) to this contract's camelCase shape. */
export function parseFinanceReconciliationRun(row: Record<string, unknown>): FinanceReconciliationRun {
  const numeric = (value: unknown) => (typeof value === "string" ? Number(value) : value);
  return FinanceReconciliationRunSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    companyId: row.company_id,
    scope: row.scope,
    asOfDate: row.as_of_date,
    toleranceAmount: numeric(row.tolerance_amount),
    controlTotal: numeric(row.control_total),
    sourceTotal: numeric(row.source_total),
    varianceAmount: numeric(row.variance_amount),
    isWithinTolerance: row.is_within_tolerance,
    status: row.status,
    certifyReason: row.certify_reason,
    certifiedBy: row.certified_by,
    certifiedAt: row.certified_at,
    preparedBy: row.prepared_by,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Maps a raw app.finance_reconciliation_exceptions row (snake_case) to this contract's camelCase shape. */
export function parseFinanceReconciliationException(row: Record<string, unknown>): FinanceReconciliationException {
  const numeric = (value: unknown) => (typeof value === "string" ? Number(value) : value);
  return FinanceReconciliationExceptionSchema.parse({
    id: row.id,
    runId: row.run_id,
    tenantId: row.tenant_id,
    itemType: row.item_type,
    description: row.description,
    expectedAmount: numeric(row.expected_amount),
    actualAmount: numeric(row.actual_amount),
    varianceAmount: numeric(row.variance_amount),
    status: row.status,
    owner: row.owner,
    resolutionReason: row.resolution_reason,
    resolvedBy: row.resolved_by,
    resolvedAt: row.resolved_at,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}
