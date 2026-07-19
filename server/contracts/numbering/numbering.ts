/**
 * Numbering engine contract (PLT-125, CG-S6-PLT-022). Mirrors
 * supabase/migrations/20260719110000_create_numbering_engine.sql's
 * app.numbering_counters/app.numbering_allocations shape and the
 * app.publish_numbering_definition / app.bootstrap_numbering_counter /
 * app.allocate_number / app.reserve_number / app.confirm_number_reservation /
 * app.release_number_reservation / app.void_number_allocation /
 * app.get_numbering_allocation_status RPCs.
 *
 * A numbering *definition* is not modeled here as its own row type -- it is PLT-121's
 * own ConfigVersion/config_items (config_type_code='numbering'), reused directly (this
 * migration's own header). `publishNumberingDefinition` therefore still returns a
 * `ConfigVersion` (server/contracts/config/config.ts), not a bespoke type.
 */

import { z } from "zod";
import { ConfigVersionSchema, type ConfigVersion } from "../config/config.ts";

export const NUMBERING_RESET_PERIODS = ["never", "yearly", "monthly", "daily"] as const;
export const NumberingResetPeriodSchema = z.enum(NUMBERING_RESET_PERIODS);
export type NumberingResetPeriod = z.infer<typeof NumberingResetPeriodSchema>;

export const NUMBERING_ALLOCATION_STATUSES = ["reserved", "allocated", "released", "voided"] as const;
export const NumberingAllocationStatusSchema = z.enum(NUMBERING_ALLOCATION_STATUSES);
export type NumberingAllocationStatus = z.infer<typeof NumberingAllocationStatusSchema>;

export const NumberingCounterSchema = z.object({
  id: z.string().uuid(),
  configVersionId: z.string().uuid(),
  scopeKey: z.string(),
  periodKey: z.string(),
  nextSeq: z.number().int().nonnegative(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type NumberingCounter = z.infer<typeof NumberingCounterSchema>;

export const NumberingAllocationSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  configVersionId: z.string().uuid(),
  scopeKey: z.string(),
  periodKey: z.string(),
  seq: z.number().int().positive(),
  formattedNumber: z.string(),
  entityType: z.string(),
  entityId: z.string().uuid().nullable(),
  status: NumberingAllocationStatusSchema,
  idempotencyKey: z.string(),
  allocatedBy: z.string().nullable(),
  allocatedAt: z.string(),
  voidedAt: z.string().nullable(),
  voidedReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type NumberingAllocation = z.infer<typeof NumberingAllocationSchema>;

export const PublishNumberingDefinitionInputSchema = z.object({
  versionId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  effectiveFrom: z.string().nullable().default(null),
  actorLabel: z.string().min(1),
});
export type PublishNumberingDefinitionInput = z.input<typeof PublishNumberingDefinitionInputSchema>;

export const BootstrapNumberingCounterInputSchema = z.object({
  configVersionId: z.string().uuid(),
  scopeKey: z.string().min(1).default("default"),
  periodKey: z.string().min(1),
  startingSeq: z.number().int().nonnegative(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type BootstrapNumberingCounterInput = z.input<typeof BootstrapNumberingCounterInputSchema>;

const AllocateOrReserveNumberInputSchema = z.object({
  configVersionId: z.string().uuid(),
  tenantId: z.string().uuid(),
  scopeKey: z.string().min(1).default("default"),
  entityType: z.string().min(1).default("generic"),
  entityId: z.string().uuid().nullable().default(null),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  allocatedBy: z.string().min(1),
});
export const AllocateNumberInputSchema = AllocateOrReserveNumberInputSchema;
export const ReserveNumberInputSchema = AllocateOrReserveNumberInputSchema;
export type AllocateNumberInput = z.input<typeof AllocateNumberInputSchema>;
export type ReserveNumberInput = z.input<typeof ReserveNumberInputSchema>;

export const ConfirmNumberReservationInputSchema = z.object({
  allocationId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ConfirmNumberReservationInput = z.input<typeof ConfirmNumberReservationInputSchema>;

export const ReleaseNumberReservationInputSchema = z.object({
  allocationId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
  reason: z.string().nullable().default(null),
});
export type ReleaseNumberReservationInput = z.input<typeof ReleaseNumberReservationInputSchema>;

export const VoidNumberAllocationInputSchema = z.object({
  allocationId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
  reason: z.string().min(1),
});
export type VoidNumberAllocationInput = z.input<typeof VoidNumberAllocationInputSchema>;

export const GetNumberingAllocationStatusInputSchema = z.object({
  allocationId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
});
export type GetNumberingAllocationStatusInput = z.input<typeof GetNumberingAllocationStatusInputSchema>;

export const FormatNumberingPreviewInputSchema = z.object({
  format: z.string().min(1),
  seq: z.number().int().positive(),
  padding: z.number().int().min(1).max(10),
  scopeCode: z.string().nullable().default(null),
  asOf: z.string().nullable().default(null),
});
export type FormatNumberingPreviewInput = z.input<typeof FormatNumberingPreviewInputSchema>;

/** Re-exported so callers of publishNumberingDefinition don't need a separate import from ../config/config.ts. */
export { ConfigVersionSchema };
export type { ConfigVersion };

/** Maps a raw app.numbering_counters row (snake_case) to this contract's camelCase shape. */
export function parseNumberingCounter(row: Record<string, unknown>): NumberingCounter {
  return NumberingCounterSchema.parse({
    id: row.id,
    configVersionId: row.config_version_id,
    scopeKey: row.scope_key,
    periodKey: row.period_key,
    nextSeq: row.next_seq,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Maps a raw app.numbering_allocations row (snake_case) to this contract's camelCase shape. */
export function parseNumberingAllocation(row: Record<string, unknown>): NumberingAllocation {
  return NumberingAllocationSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    configVersionId: row.config_version_id,
    scopeKey: row.scope_key,
    periodKey: row.period_key,
    seq: row.seq,
    formattedNumber: row.formatted_number,
    entityType: row.entity_type,
    entityId: row.entity_id,
    status: row.status,
    idempotencyKey: row.idempotency_key,
    allocatedBy: row.allocated_by,
    allocatedAt: row.allocated_at,
    voidedAt: row.voided_at,
    voidedReason: row.voided_reason,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}
