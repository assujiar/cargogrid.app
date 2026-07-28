/**
 * Fiscal Period contract (FIN-193, CG-S9-FIN-004). Mirrors
 * supabase/migrations/20260728220000_create_finance_fiscal_period.sql's
 * app.finance_fiscal_calendars / app.finance_fiscal_periods /
 * app.finance_period_close_checklist_items / app.finance_period_transitions
 * shapes and their RPCs.
 */

import { z } from "zod";

export const FINANCE_PERIOD_STATUSES = ["open", "soft_closed", "closed"] as const;
export const FinancePeriodStatusSchema = z.enum(FINANCE_PERIOD_STATUSES);
export type FinancePeriodStatus = z.infer<typeof FinancePeriodStatusSchema>;

export const FinanceFiscalCalendarSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  companyId: z.string().uuid().nullable(),
  code: z.string(),
  name: z.string(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
});
export type FinanceFiscalCalendar = z.infer<typeof FinanceFiscalCalendarSchema>;

export const FinanceFiscalPeriodSchema = z.object({
  id: z.string().uuid(),
  calendarId: z.string().uuid(),
  tenantId: z.string().uuid(),
  companyId: z.string().uuid().nullable(),
  periodCode: z.string(),
  name: z.string(),
  startDate: z.string(),
  endDate: z.string(),
  sequenceNumber: z.number().int(),
  status: FinancePeriodStatusSchema,
  closedAt: z.string().nullable(),
  closedBy: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type FinanceFiscalPeriod = z.infer<typeof FinanceFiscalPeriodSchema>;

export const FinancePeriodChecklistItemSchema = z.object({
  id: z.string().uuid(),
  periodId: z.string().uuid(),
  itemKey: z.string(),
  label: z.string(),
  required: z.boolean(),
  sourceCapability: z.string().nullable(),
  satisfied: z.boolean(),
  satisfiedReason: z.string().nullable(),
  satisfiedBy: z.string().nullable(),
  satisfiedAt: z.string().nullable(),
  createdAt: z.string(),
});
export type FinancePeriodChecklistItem = z.infer<typeof FinancePeriodChecklistItemSchema>;

export const FinancePeriodTransitionSchema = z.object({
  id: z.string().uuid(),
  periodId: z.string().uuid(),
  tenantId: z.string().uuid(),
  fromStatus: z.string(),
  toStatus: z.string(),
  reason: z.string().nullable(),
  actorAuthUserId: z.string().uuid().nullable(),
  actorLabel: z.string().nullable(),
  createdAt: z.string(),
});
export type FinancePeriodTransition = z.infer<typeof FinancePeriodTransitionSchema>;

export const FinancePeriodCloseReadinessSchema = z.object({
  periodId: z.string().uuid(),
  status: FinancePeriodStatusSchema,
  ready: z.boolean(),
  unsatisfiedRequiredItems: z.array(z.string()),
});
export type FinancePeriodCloseReadiness = z.infer<typeof FinancePeriodCloseReadinessSchema>;

export const FinancePeriodDateResolutionSchema = z.object({
  periodId: z.string().uuid(),
  periodCode: z.string(),
  status: FinancePeriodStatusSchema,
  postingEligible: z.boolean(),
});
export type FinancePeriodDateResolution = z.infer<typeof FinancePeriodDateResolutionSchema>;

export const GenerateFinanceFiscalCalendarInputSchema = z.object({
  tenantId: z.string().uuid(),
  companyId: z.string().uuid().nullable().default(null),
  code: z.string().min(1),
  name: z.string().min(1),
  startDate: z.string(),
  periodCount: z.number().int().min(1).max(24),
  actorAuthUserId: z.string().uuid(),
  createdBy: z.string().min(1),
});
export type GenerateFinanceFiscalCalendarInput = z.input<typeof GenerateFinanceFiscalCalendarInputSchema>;

export const AcknowledgeFinancePeriodChecklistItemInputSchema = z.object({
  periodId: z.string().uuid(),
  itemKey: z.string().min(1),
  satisfied: z.boolean(),
  reason: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type AcknowledgeFinancePeriodChecklistItemInput = z.input<typeof AcknowledgeFinancePeriodChecklistItemInputSchema>;

export const SoftCloseFinancePeriodInputSchema = z.object({
  periodId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SoftCloseFinancePeriodInput = z.input<typeof SoftCloseFinancePeriodInputSchema>;

export const CloseFinancePeriodInputSchema = z.object({
  periodId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CloseFinancePeriodInput = z.input<typeof CloseFinancePeriodInputSchema>;

export const ReopenFinancePeriodInputSchema = z.object({
  periodId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ReopenFinancePeriodInput = z.input<typeof ReopenFinancePeriodInputSchema>;

/** Maps a raw app.finance_fiscal_calendars row (snake_case) to this contract's camelCase shape. */
export function parseFinanceFiscalCalendar(row: Record<string, unknown>): FinanceFiscalCalendar {
  return FinanceFiscalCalendarSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    companyId: row.company_id,
    code: row.code,
    name: row.name,
    createdBy: row.created_by,
    createdAt: row.created_at,
  });
}

/** Maps a raw app.finance_fiscal_periods row (snake_case) to this contract's camelCase shape. */
export function parseFinanceFiscalPeriod(row: Record<string, unknown>): FinanceFiscalPeriod {
  return FinanceFiscalPeriodSchema.parse({
    id: row.id,
    calendarId: row.calendar_id,
    tenantId: row.tenant_id,
    companyId: row.company_id,
    periodCode: row.period_code,
    name: row.name,
    startDate: row.start_date,
    endDate: row.end_date,
    sequenceNumber: row.sequence_number,
    status: row.status,
    closedAt: row.closed_at,
    closedBy: row.closed_by,
    recordVersion: row.record_version,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Maps a raw app.finance_period_close_checklist_items row (snake_case) to this contract's camelCase shape. */
export function parseFinancePeriodChecklistItem(row: Record<string, unknown>): FinancePeriodChecklistItem {
  return FinancePeriodChecklistItemSchema.parse({
    id: row.id,
    periodId: row.period_id,
    itemKey: row.item_key,
    label: row.label,
    required: row.required,
    sourceCapability: row.source_capability,
    satisfied: row.satisfied,
    satisfiedReason: row.satisfied_reason,
    satisfiedBy: row.satisfied_by,
    satisfiedAt: row.satisfied_at,
    createdAt: row.created_at,
  });
}

/** Maps a raw app.finance_period_transitions row (snake_case) to this contract's camelCase shape. */
export function parseFinancePeriodTransition(row: Record<string, unknown>): FinancePeriodTransition {
  return FinancePeriodTransitionSchema.parse({
    id: row.id,
    periodId: row.period_id,
    tenantId: row.tenant_id,
    fromStatus: row.from_status,
    toStatus: row.to_status,
    reason: row.reason,
    actorAuthUserId: row.actor_auth_user_id,
    actorLabel: row.actor_label,
    createdAt: row.created_at,
  });
}

/** Maps a raw app.get_finance_period_close_readiness() jsonb result to this contract's camelCase shape. */
export function parseFinancePeriodCloseReadiness(row: Record<string, unknown>): FinancePeriodCloseReadiness {
  return FinancePeriodCloseReadinessSchema.parse({
    periodId: row.periodId,
    status: row.status,
    ready: row.ready,
    unsatisfiedRequiredItems: row.unsatisfiedRequiredItems,
  });
}

/** Maps a raw app.resolve_finance_period_for_date() row (snake_case) to this contract's camelCase shape. */
export function parseFinancePeriodDateResolution(row: Record<string, unknown>): FinancePeriodDateResolution {
  return FinancePeriodDateResolutionSchema.parse({
    periodId: row.period_id,
    periodCode: row.period_code,
    status: row.status,
    postingEligible: row.posting_eligible,
  });
}
