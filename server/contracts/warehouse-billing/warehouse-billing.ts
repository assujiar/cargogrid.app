/**
 * Warehouse Billing Events contract (ATW-022, CG-S10-ATW-022, Prompt 241). Mirrors
 * supabase/migrations/20260730300000_create_advanced_tms_warehouse_billing_events.sql's
 * app.warehouse_billing_rate_components/app.warehouse_billing_events/
 * app.warehouse_billing_handoffs shapes and their configure/capture/calculate/
 * recalculate/hold/review/approve/handoff/reconcile/correct/reverse/read RPCs.
 */

import { z } from "zod";

export const WAREHOUSE_BILLING_ACTIVITY_TYPES = [
  "storage",
  "receiving",
  "handling",
  "putaway",
  "pick",
  "pack",
  "outbound",
  "value_added",
] as const;
export const WarehouseBillingActivityTypeSchema = z.enum(WAREHOUSE_BILLING_ACTIVITY_TYPES);
export type WarehouseBillingActivityType = z.infer<typeof WarehouseBillingActivityTypeSchema>;

export const WAREHOUSE_BILLING_RATE_BASES = ["flat", "per_unit", "tiered", "time_basis"] as const;
export const WarehouseBillingRateBasisSchema = z.enum(WAREHOUSE_BILLING_RATE_BASES);
export type WarehouseBillingRateBasis = z.infer<typeof WarehouseBillingRateBasisSchema>;

export const WAREHOUSE_BILLING_SOURCE_TYPES = [
  "wms_receipt_line",
  "wms_putaway_confirmation",
  "wms_pick_task_confirmation",
  "wms_package_confirmation",
  "wms_billing_eligibility_event",
  "manual",
] as const;
export const WarehouseBillingSourceTypeSchema = z.enum(WAREHOUSE_BILLING_SOURCE_TYPES);
export type WarehouseBillingSourceType = z.infer<typeof WarehouseBillingSourceTypeSchema>;

export const WAREHOUSE_BILLING_EVENT_STATUSES = [
  "draft",
  "pending_review",
  "reviewed",
  "approved",
  "on_hold",
  "handed_off",
  "corrected",
  "reversed",
] as const;
export const WarehouseBillingEventStatusSchema = z.enum(WAREHOUSE_BILLING_EVENT_STATUSES);
export type WarehouseBillingEventStatus = z.infer<typeof WarehouseBillingEventStatusSchema>;

export const WAREHOUSE_BILLING_RECONCILIATION_STATUSES = ["reconciled", "rejected"] as const;
export const WarehouseBillingReconciliationStatusSchema = z.enum(WAREHOUSE_BILLING_RECONCILIATION_STATUSES);
export type WarehouseBillingReconciliationStatus = z.infer<typeof WarehouseBillingReconciliationStatusSchema>;

export const WarehouseBillingTierSchema = z.object({
  threshold: z.number().positive(),
  rate: z.number().nonnegative(),
});
export type WarehouseBillingTier = z.infer<typeof WarehouseBillingTierSchema>;

// --- Row schemas ---

export const WarehouseBillingRateComponentSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  contractId: z.string().uuid(),
  warehouseId: z.string().uuid().nullable(),
  activityType: WarehouseBillingActivityTypeSchema,
  rateBasis: WarehouseBillingRateBasisSchema,
  rateUomCode: z.string().nullable(),
  unitRate: z.coerce.number(),
  minimumAmount: z.coerce.number().nullable(),
  currency: z.string(),
  tierSchedule: z.array(WarehouseBillingTierSchema).nullable(),
  timeBasisUnit: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type WarehouseBillingRateComponent = z.infer<typeof WarehouseBillingRateComponentSchema>;

export function parseWarehouseBillingRateComponent(row: Record<string, unknown>): WarehouseBillingRateComponent {
  return WarehouseBillingRateComponentSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    contractId: row.contract_id,
    warehouseId: row.warehouse_id ?? null,
    activityType: row.activity_type,
    rateBasis: row.rate_basis,
    rateUomCode: row.rate_uom_code ?? null,
    unitRate: row.unit_rate,
    minimumAmount: row.minimum_amount ?? null,
    currency: row.currency,
    tierSchedule: row.tier_schedule ?? null,
    timeBasisUnit: row.time_basis_unit ?? null,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const WarehouseBillingEventSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  warehouseId: z.string().uuid(),
  ownerAccountId: z.string().uuid(),
  activityType: WarehouseBillingActivityTypeSchema,
  sourceType: WarehouseBillingSourceTypeSchema,
  sourceId: z.string().uuid().nullable(),
  sourceVersion: z.number().int().nullable(),
  activityDate: z.string(),
  quantity: z.coerce.number(),
  uomCode: z.string(),
  contractId: z.string().uuid().nullable(),
  rateComponentId: z.string().uuid().nullable(),
  baseAmount: z.coerce.number().nullable(),
  taxCode: z.string().nullable(),
  taxRuleVersionId: z.string().uuid().nullable(),
  taxAmount: z.coerce.number().nullable(),
  totalAmount: z.coerce.number().nullable(),
  currency: z.string().nullable(),
  roundingMode: z.string().nullable(),
  calculationExplanation: z.record(z.string(), z.unknown()),
  status: WarehouseBillingEventStatusSchema,
  holdReason: z.string().nullable(),
  reviewedByAuthUserId: z.string().uuid().nullable(),
  reviewedByLabel: z.string().nullable(),
  reviewedAt: z.string().nullable(),
  approvedByAuthUserId: z.string().uuid().nullable(),
  approvedByLabel: z.string().nullable(),
  approvedAt: z.string().nullable(),
  correctsEventId: z.string().uuid().nullable(),
  reversesEventId: z.string().uuid().nullable(),
  correctionReason: z.string().nullable(),
  idempotencyKey: z.string(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type WarehouseBillingEvent = z.infer<typeof WarehouseBillingEventSchema>;

export function parseWarehouseBillingEvent(row: Record<string, unknown>): WarehouseBillingEvent {
  return WarehouseBillingEventSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    warehouseId: row.warehouse_id,
    ownerAccountId: row.owner_account_id,
    activityType: row.activity_type,
    sourceType: row.source_type,
    sourceId: row.source_id ?? null,
    sourceVersion: row.source_version ?? null,
    activityDate: row.activity_date,
    quantity: row.quantity,
    uomCode: row.uom_code,
    contractId: row.contract_id ?? null,
    rateComponentId: row.rate_component_id ?? null,
    baseAmount: row.base_amount ?? null,
    taxCode: row.tax_code ?? null,
    taxRuleVersionId: row.tax_rule_version_id ?? null,
    taxAmount: row.tax_amount ?? null,
    totalAmount: row.total_amount ?? null,
    currency: row.currency ?? null,
    roundingMode: row.rounding_mode ?? null,
    calculationExplanation: (row.calculation_explanation as Record<string, unknown>) ?? {},
    status: row.status,
    holdReason: row.hold_reason ?? null,
    reviewedByAuthUserId: row.reviewed_by_auth_user_id ?? null,
    reviewedByLabel: row.reviewed_by_label ?? null,
    reviewedAt: row.reviewed_at ?? null,
    approvedByAuthUserId: row.approved_by_auth_user_id ?? null,
    approvedByLabel: row.approved_by_label ?? null,
    approvedAt: row.approved_at ?? null,
    correctsEventId: row.corrects_event_id ?? null,
    reversesEventId: row.reverses_event_id ?? null,
    correctionReason: row.correction_reason ?? null,
    idempotencyKey: row.idempotency_key,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const WarehouseBillingHandoffSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  billingEventId: z.string().uuid(),
  idempotencyKey: z.string(),
  handedOffByAuthUserId: z.string().uuid(),
  handedOffByLabel: z.string().nullable(),
  handedOffAt: z.string(),
  reconciliationStatus: WarehouseBillingReconciliationStatusSchema.nullable(),
  reconciliationNote: z.string().nullable(),
  reconciledAt: z.string().nullable(),
  updatedAt: z.string().nullable(),
  createdAt: z.string(),
});
export type WarehouseBillingHandoff = z.infer<typeof WarehouseBillingHandoffSchema>;

export function parseWarehouseBillingHandoff(row: Record<string, unknown>): WarehouseBillingHandoff {
  return WarehouseBillingHandoffSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    billingEventId: row.billing_event_id,
    idempotencyKey: row.idempotency_key,
    handedOffByAuthUserId: row.handed_off_by_auth_user_id,
    handedOffByLabel: row.handed_off_by_label ?? null,
    handedOffAt: row.handed_off_at,
    reconciliationStatus: row.reconciliation_status ?? null,
    reconciliationNote: row.reconciliation_note ?? null,
    reconciledAt: row.reconciled_at ?? null,
    updatedAt: row.updated_at ?? null,
    createdAt: row.created_at,
  });
}

/** app.preview_warehouse_billing_calculation's own jsonb return shape. No row is created. */
export const WarehouseBillingCalculationPreviewSchema = z.object({
  contractId: z.string().uuid().nullable(),
  rateComponentId: z.string().uuid().nullable(),
  baseAmount: z.coerce.number(),
  taxCode: z.string().nullable(),
  taxAmount: z.coerce.number(),
  taxRuleVersionId: z.string().uuid().nullable(),
  totalAmount: z.coerce.number(),
  currency: z.string(),
  roundingMode: z.string(),
  calculationExplanation: z.record(z.string(), z.unknown()),
});
export type WarehouseBillingCalculationPreview = z.infer<typeof WarehouseBillingCalculationPreviewSchema>;

export function parseWarehouseBillingCalculationPreview(data: Record<string, unknown>): WarehouseBillingCalculationPreview {
  return WarehouseBillingCalculationPreviewSchema.parse({
    contractId: data.contractId ?? null,
    rateComponentId: data.rateComponentId ?? null,
    baseAmount: data.baseAmount,
    taxCode: data.taxCode ?? null,
    taxAmount: data.taxAmount,
    taxRuleVersionId: data.taxRuleVersionId ?? null,
    totalAmount: data.totalAmount,
    currency: data.currency,
    roundingMode: data.roundingMode,
    calculationExplanation: (data.calculationExplanation as Record<string, unknown>) ?? {},
  });
}

// --- Mutation input schemas ---

export const CreateWarehouseBillingRateComponentInputSchema = z.object({
  contractId: z.string().uuid(),
  warehouseId: z.string().uuid().nullable().optional(),
  activityType: WarehouseBillingActivityTypeSchema,
  rateBasis: WarehouseBillingRateBasisSchema,
  rateUomCode: z.string().nullable().optional(),
  unitRate: z.number().nonnegative(),
  minimumAmount: z.number().nonnegative().nullable().optional(),
  currency: z.string().length(3),
  tierSchedule: z.array(WarehouseBillingTierSchema).nullable().optional(),
  timeBasisUnit: z.string().nullable().optional(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreateWarehouseBillingRateComponentInput = z.input<typeof CreateWarehouseBillingRateComponentInputSchema>;

export const GetEffectiveWarehouseBillingRateInputSchema = z.object({
  tenantId: z.string().uuid(),
  accountId: z.string().uuid(),
  warehouseId: z.string().uuid(),
  activityType: WarehouseBillingActivityTypeSchema,
  asOf: z.string(),
  actorAuthUserId: z.string().uuid(),
});
export type GetEffectiveWarehouseBillingRateInput = z.input<typeof GetEffectiveWarehouseBillingRateInputSchema>;

export const CaptureWarehouseBillingEventInputSchema = z.object({
  tenantId: z.string().uuid(),
  warehouseId: z.string().uuid(),
  ownerAccountId: z.string().uuid(),
  activityType: WarehouseBillingActivityTypeSchema,
  sourceType: WarehouseBillingSourceTypeSchema,
  sourceId: z.string().uuid().nullable().optional(),
  quantity: z.number().positive(),
  uomCode: z.string().min(1),
  activityDate: z.string(),
  idempotencyKey: z.string().min(1),
  correctionReason: z.string().nullable().optional(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CaptureWarehouseBillingEventInput = z.input<typeof CaptureWarehouseBillingEventInputSchema>;

export const CalculateWarehouseBillingEventInputSchema = z.object({
  eventId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  taxCode: z.string().nullable().optional(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CalculateWarehouseBillingEventInput = z.input<typeof CalculateWarehouseBillingEventInputSchema>;

export const RecalculateWarehouseBillingEventInputSchema = z.object({
  eventId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  taxCode: z.string().nullable().optional(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type RecalculateWarehouseBillingEventInput = z.input<typeof RecalculateWarehouseBillingEventInputSchema>;

export const HoldWarehouseBillingEventInputSchema = z.object({
  eventId: z.string().uuid(),
  reason: z.string().min(1),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type HoldWarehouseBillingEventInput = z.input<typeof HoldWarehouseBillingEventInputSchema>;

export const ReleaseWarehouseBillingEventHoldInputSchema = z.object({
  eventId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ReleaseWarehouseBillingEventHoldInput = z.input<typeof ReleaseWarehouseBillingEventHoldInputSchema>;

export const ReviewWarehouseBillingEventInputSchema = z.object({
  eventId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ReviewWarehouseBillingEventInput = z.input<typeof ReviewWarehouseBillingEventInputSchema>;

export const ApproveWarehouseBillingEventInputSchema = z.object({
  eventId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ApproveWarehouseBillingEventInput = z.input<typeof ApproveWarehouseBillingEventInputSchema>;

export const HandoffWarehouseBillingEventInputSchema = z.object({
  eventId: z.string().uuid(),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type HandoffWarehouseBillingEventInput = z.input<typeof HandoffWarehouseBillingEventInputSchema>;

/** service_role only -- a Finance-side worker callback, never a client action (no authenticated grant at all). */
export const RecordWarehouseBillingReconciliationOutcomeInputSchema = z.object({
  handoffId: z.string().uuid(),
  status: WarehouseBillingReconciliationStatusSchema,
  note: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RecordWarehouseBillingReconciliationOutcomeInput = z.input<typeof RecordWarehouseBillingReconciliationOutcomeInputSchema>;

export const CorrectWarehouseBillingEventInputSchema = z.object({
  originalEventId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  newQuantity: z.number().positive(),
  reason: z.string().min(1),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CorrectWarehouseBillingEventInput = z.input<typeof CorrectWarehouseBillingEventInputSchema>;

export const ReverseWarehouseBillingEventInputSchema = z.object({
  originalEventId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ReverseWarehouseBillingEventInput = z.input<typeof ReverseWarehouseBillingEventInputSchema>;

export const PreviewWarehouseBillingCalculationInputSchema = z.object({
  tenantId: z.string().uuid(),
  accountId: z.string().uuid(),
  warehouseId: z.string().uuid(),
  activityType: WarehouseBillingActivityTypeSchema,
  quantity: z.number().positive(),
  uomCode: z.string().min(1),
  asOf: z.string(),
  actorAuthUserId: z.string().uuid(),
});
export type PreviewWarehouseBillingCalculationInput = z.input<typeof PreviewWarehouseBillingCalculationInputSchema>;
