/**
 * Vendor Rate and Pricelist extension contract (PRC-255, CG-S11-PRC-006). Mirrors
 * supabase/migrations/20260730620000_extend_commercial_vendor_rate_for_procurement.sql
 * -- the PRC-owned additive extension of COM-149's own canonical vendor-rate engine
 * (server/contracts/rate/rate.ts). Two kinds of shapes live here:
 *
 *  - Genuinely NEW PRC-owned entities (app.vendor_rate_tiers and its masked
 *    directory view, the calculate-rate RPC's own return row, the import-adapter
 *    RPCs) -- their own Zod schemas.
 *  - The WIDENED trailing-optional-parameter inputs to COM-149's own
 *    create_rate_version/select_vendor_rate (never re-exported as a competing
 *    contract -- server/mutations/procurement-rate.ts composes directly with
 *    server/mutations/rate.ts's existing wrapper functions plus these extra,
 *    optional fields, exactly the "extend, do not duplicate" rule this migration's
 *    own header holds itself to).
 */

import { z } from "zod";

export const VendorRateTierSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  rateVersionId: z.string().uuid(),
  tierOrder: z.number().int().positive(),
  weightMin: z.coerce.number(),
  weightMax: z.coerce.number().nullable(),
  volumeMin: z.coerce.number(),
  volumeMax: z.coerce.number().nullable(),
  amount: z.coerce.number().nullable(),
  minimumCharge: z.coerce.number().nullable(),
  costMasked: z.boolean(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type VendorRateTier = z.infer<typeof VendorRateTierSchema>;

export function parseVendorRateTier(row: Record<string, unknown>): VendorRateTier {
  return VendorRateTierSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    rateVersionId: row.rate_version_id,
    tierOrder: row.tier_order,
    weightMin: row.weight_min,
    weightMax: row.weight_max,
    volumeMin: row.volume_min,
    volumeMax: row.volume_max,
    amount: row.amount,
    minimumCharge: row.minimum_charge,
    costMasked: row.cost_masked,
    recordVersion: row.record_version,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const AddVendorRateTierInputSchema = z.object({
  rateVersionId: z.string().uuid(),
  tierOrder: z.number().int().positive(),
  weightMin: z.number().nonnegative().nullable().default(null),
  weightMax: z.number().nonnegative().nullable().default(null),
  volumeMin: z.number().nonnegative().nullable().default(null),
  volumeMax: z.number().nonnegative().nullable().default(null),
  amount: z.number().nonnegative(),
  minimumCharge: z.number().nonnegative().nullable().default(null),
  idempotencyKey: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type AddVendorRateTierInput = z.input<typeof AddVendorRateTierInputSchema>;

export const RemoveVendorRateTierInputSchema = z.object({
  tierId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RemoveVendorRateTierInput = z.input<typeof RemoveVendorRateTierInputSchema>;

/** Maps a raw app.calculate_vendor_rate(...) result row (snake_case) to this contract's camelCase shape. */
export const VendorRateCalculationSchema = z.object({
  rateVersionId: z.string().uuid(),
  matchedTierId: z.string().uuid().nullable(),
  currency: z.string(),
  baseComponent: z.coerce.number(),
  tierComponent: z.coerce.number().nullable(),
  surchargeComponent: z.coerce.number(),
  subtotalAmount: z.coerce.number(),
  minimumAmountApplied: z.boolean(),
  computedAmount: z.coerce.number(),
  roundingMode: z.string(),
  roundingPrecision: z.number().int(),
  uomBasis: z.record(z.string(), z.unknown()),
  componentBreakdown: z.record(z.string(), z.unknown()),
  computedAt: z.string(),
});
export type VendorRateCalculation = z.infer<typeof VendorRateCalculationSchema>;

export function parseVendorRateCalculation(row: Record<string, unknown>): VendorRateCalculation {
  return VendorRateCalculationSchema.parse({
    rateVersionId: row.rate_version_id,
    matchedTierId: row.matched_tier_id,
    currency: row.currency,
    baseComponent: row.base_component,
    tierComponent: row.tier_component,
    surchargeComponent: row.surcharge_component,
    subtotalAmount: row.subtotal_amount,
    minimumAmountApplied: row.minimum_amount_applied,
    computedAmount: row.computed_amount,
    roundingMode: row.rounding_mode,
    roundingPrecision: row.rounding_precision,
    uomBasis: row.uom_basis,
    componentBreakdown: row.component_breakdown,
    computedAt: row.computed_at,
  });
}

export const CalculateVendorRateInputSchema = z.object({
  rateVersionId: z.string().uuid(),
  weight: z.number().positive().nullable().default(null),
  volume: z.number().positive().nullable().default(null),
  quantity: z.number().positive().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
});
export type CalculateVendorRateInput = z.input<typeof CalculateVendorRateInputSchema>;

/** The three new optional trailing fields server/mutations/rate.ts's own CreateRateVersionInput does not carry -- composed alongside it, never duplicated (ADR-0020). */
export const VendorRateProcurementLinkSchema = z.object({
  vendorMasterId: z.string().uuid().nullable().default(null),
  leadTimeDays: z.number().int().nonnegative().nullable().default(null),
  capacityTerms: z.string().nullable().default(null),
});
export type VendorRateProcurementLink = z.input<typeof VendorRateProcurementLinkSchema>;

/** The three new optional trailing fields server/mutations/rate.ts's own SelectVendorRateInput does not carry. */
export const VendorRateSelectionCalculationInputsSchema = z.object({
  weight: z.number().positive().nullable().default(null),
  volume: z.number().positive().nullable().default(null),
  quantity: z.number().positive().nullable().default(null),
});
export type VendorRateSelectionCalculationInputs = z.input<typeof VendorRateSelectionCalculationInputsSchema>;

// -- Import adapter (design notes 8-11) -----------------------------------------

/** The exact, disclosed vendor_rate_import column convention (migration header design note 9) -- bounded at three flat tier slots per staged row. */
export const VENDOR_RATE_IMPORT_SCHEMA_CODE = "vendor_rate_import";

export const VENDOR_RATE_IMPORT_COLUMNS = [
  { key: "vendor_code", label: "Vendor code", required: true, data_type: "text" },
  { key: "vendor_name", label: "Vendor name", required: true, data_type: "text" },
  { key: "vendor_master_code", label: "Linked vendor master code (optional)", required: false, data_type: "text" },
  { key: "service_type", label: "Service type", required: true, data_type: "text" },
  { key: "mode", label: "Mode", required: false, data_type: "text" },
  { key: "origin_lane", label: "Origin lane", required: true, data_type: "text" },
  { key: "destination_lane", label: "Destination lane", required: true, data_type: "text" },
  { key: "equipment_type", label: "Equipment type", required: false, data_type: "text" },
  { key: "currency", label: "Currency (ISO 4217)", required: true, data_type: "text" },
  { key: "base_amount", label: "Base amount", required: true, data_type: "number" },
  { key: "minimum_amount", label: "Minimum amount", required: false, data_type: "number" },
  { key: "lead_time_days", label: "Lead time (days)", required: false, data_type: "number" },
  { key: "capacity_terms", label: "Capacity terms", required: false, data_type: "text" },
  ...[1, 2, 3].flatMap((tier) => [
    { key: `tier${tier}_weight_min`, label: `Tier ${tier} weight min`, required: false, data_type: "number" },
    { key: `tier${tier}_weight_max`, label: `Tier ${tier} weight max`, required: false, data_type: "number" },
    { key: `tier${tier}_volume_min`, label: `Tier ${tier} volume min`, required: false, data_type: "number" },
    { key: `tier${tier}_volume_max`, label: `Tier ${tier} volume max`, required: false, data_type: "number" },
    { key: `tier${tier}_amount`, label: `Tier ${tier} amount`, required: false, data_type: "number" },
    { key: `tier${tier}_minimum_charge`, label: `Tier ${tier} minimum charge`, required: false, data_type: "number" },
  ]),
] as const;

export const CommitVendorRateImportJobInputSchema = z.object({
  jobId: z.string().uuid(),
  allowPartial: z.boolean().default(false),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CommitVendorRateImportJobInput = z.input<typeof CommitVendorRateImportJobInputSchema>;

export const ValidateVendorRateImportRowInputSchema = z.object({
  stagingRowId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ValidateVendorRateImportRowInput = z.input<typeof ValidateVendorRateImportRowInputSchema>;
