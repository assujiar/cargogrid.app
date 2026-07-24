/**
 * Customer Contract and Pricing contract (COM-156, CG-S7-COM-015). Mirrors
 * supabase/migrations/20260724300000_create_commercial_customer_contract_pricing.sql's
 * app.customer_contracts/app.customer_contract_price_components shape and the
 * app.create_customer_contract_draft / app.add_customer_contract_price_component /
 * app.remove_customer_contract_price_component / app.publish_customer_contract /
 * app.retire_customer_contract / app.get_effective_customer_price RPCs.
 *
 * Price components carry no column masking in this contract layer's own `parse*`
 * functions -- masking (COM:View selling price) happens entirely in the database, via
 * app.customer_contract_price_components_directory / app.get_effective_customer_price's
 * own price_masked column, which these parsers read as an ordinary boolean field.
 */

import { z } from "zod";

export const CUSTOMER_CONTRACT_STATUSES = ["draft", "published", "retired"] as const;
export const CustomerContractStatusSchema = z.enum(CUSTOMER_CONTRACT_STATUSES);
export type CustomerContractStatus = z.infer<typeof CustomerContractStatusSchema>;

export const CustomerContractSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  accountId: z.string().uuid(),
  rootContractId: z.string().uuid(),
  versionNumber: z.number().int().positive(),
  status: CustomerContractStatusSchema,
  sourceQuotationId: z.string().uuid().nullable(),
  amendmentReason: z.string().nullable(),
  effectiveFrom: z.string(),
  effectiveTo: z.string().nullable(),
  retiredReason: z.string().nullable(),
  ownerUserId: z.string().uuid().nullable(),
  orgUnitId: z.string().uuid().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type CustomerContract = z.infer<typeof CustomerContractSchema>;

export function parseCustomerContract(row: Record<string, unknown>): CustomerContract {
  return CustomerContractSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    accountId: row.account_id,
    rootContractId: row.root_contract_id,
    versionNumber: row.version_number,
    status: row.status,
    sourceQuotationId: row.source_quotation_id,
    amendmentReason: row.amendment_reason,
    effectiveFrom: row.effective_from,
    effectiveTo: row.effective_to,
    retiredReason: row.retired_reason,
    ownerUserId: row.owner_user_id,
    orgUnitId: row.org_unit_id,
    recordVersion: row.record_version,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Maps app.customer_contract_price_components_directory's own masked row. */
export const CustomerContractPriceComponentSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  contractId: z.string().uuid(),
  serviceType: z.string(),
  mode: z.string().nullable(),
  originLane: z.string().nullable(),
  destinationLane: z.string().nullable(),
  equipmentType: z.string().nullable(),
  currency: z.string().nullable(),
  baseAmount: z.coerce.number().nullable(),
  minimumAmount: z.coerce.number().nullable(),
  discountPct: z.coerce.number().nullable(),
  surchargeComponents: z.array(z.record(z.string(), z.unknown())).nullable(),
  priceMasked: z.boolean(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
});
export type CustomerContractPriceComponent = z.infer<typeof CustomerContractPriceComponentSchema>;

export function parseCustomerContractPriceComponent(row: Record<string, unknown>): CustomerContractPriceComponent {
  return CustomerContractPriceComponentSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    contractId: row.contract_id,
    serviceType: row.service_type,
    mode: row.mode,
    originLane: row.origin_lane,
    destinationLane: row.destination_lane,
    equipmentType: row.equipment_type,
    currency: row.currency,
    baseAmount: row.base_amount,
    minimumAmount: row.minimum_amount,
    discountPct: row.discount_pct,
    surchargeComponents: row.surcharge_components,
    priceMasked: row.price_masked,
    createdBy: row.created_by,
    createdAt: row.created_at,
  });
}

/** Maps app.get_effective_customer_price()'s returned row -- the deterministic, reproducible lookup result. */
export const EffectiveCustomerPriceSchema = z.object({
  contractId: z.string().uuid(),
  priceComponentId: z.string().uuid(),
  serviceType: z.string(),
  mode: z.string().nullable(),
  originLane: z.string().nullable(),
  destinationLane: z.string().nullable(),
  equipmentType: z.string().nullable(),
  currency: z.string().nullable(),
  baseAmount: z.coerce.number().nullable(),
  minimumAmount: z.coerce.number().nullable(),
  discountPct: z.coerce.number().nullable(),
  surchargeComponents: z.array(z.record(z.string(), z.unknown())).nullable(),
  priceMasked: z.boolean(),
  effectiveFrom: z.string(),
  effectiveTo: z.string().nullable(),
});
export type EffectiveCustomerPrice = z.infer<typeof EffectiveCustomerPriceSchema>;

export function parseEffectiveCustomerPrice(row: Record<string, unknown>): EffectiveCustomerPrice {
  return EffectiveCustomerPriceSchema.parse({
    contractId: row.contract_id,
    priceComponentId: row.price_component_id,
    serviceType: row.service_type,
    mode: row.mode,
    originLane: row.origin_lane,
    destinationLane: row.destination_lane,
    equipmentType: row.equipment_type,
    currency: row.currency,
    baseAmount: row.base_amount,
    minimumAmount: row.minimum_amount,
    discountPct: row.discount_pct,
    surchargeComponents: row.surcharge_components,
    priceMasked: row.price_masked,
    effectiveFrom: row.effective_from,
    effectiveTo: row.effective_to,
  });
}

/** Exactly one of sourceQuotationId/sourceContractId must be supplied -- the main flow (from an accepted+converted quote) vs. the alternative flow (a renewal/amendment). */
export const CreateCustomerContractDraftInputSchema = z
  .object({
    sourceQuotationId: z.string().uuid().nullable().default(null),
    sourceContractId: z.string().uuid().nullable().default(null),
    effectiveFrom: z.string(),
    effectiveTo: z.string().nullable().default(null),
    amendmentReason: z.string().nullable().default(null),
    actorAuthUserId: z.string().uuid(),
    actorLabel: z.string().min(1),
  })
  .refine((input) => (input.sourceQuotationId === null) !== (input.sourceContractId === null), {
    message: "Exactly one of sourceQuotationId/sourceContractId must be supplied",
  });
export type CreateCustomerContractDraftInput = z.input<typeof CreateCustomerContractDraftInputSchema>;

export const AddCustomerContractPriceComponentInputSchema = z.object({
  contractId: z.string().uuid(),
  serviceType: z.string().min(1),
  mode: z.string().nullable().default(null),
  originLane: z.string().nullable().default(null),
  destinationLane: z.string().nullable().default(null),
  equipmentType: z.string().nullable().default(null),
  currency: z.string().regex(/^[A-Z]{3}$/),
  baseAmount: z.number().nonnegative(),
  minimumAmount: z.number().nonnegative().nullable().default(null),
  discountPct: z.number().min(0).max(100).default(0),
  surchargeComponents: z.array(z.record(z.string(), z.unknown())).default([]),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type AddCustomerContractPriceComponentInput = z.input<typeof AddCustomerContractPriceComponentInputSchema>;

export const RemoveCustomerContractPriceComponentInputSchema = z.object({
  componentId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RemoveCustomerContractPriceComponentInput = z.input<typeof RemoveCustomerContractPriceComponentInputSchema>;

export const PublishCustomerContractInputSchema = z.object({
  contractId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type PublishCustomerContractInput = z.input<typeof PublishCustomerContractInputSchema>;

export const RetireCustomerContractInputSchema = z.object({
  contractId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RetireCustomerContractInput = z.input<typeof RetireCustomerContractInputSchema>;

export const GetEffectiveCustomerPriceInputSchema = z.object({
  tenantId: z.string().uuid(),
  accountId: z.string().uuid(),
  serviceType: z.string().min(1),
  mode: z.string().nullable().default(null),
  originLane: z.string().nullable().default(null),
  destinationLane: z.string().nullable().default(null),
  equipmentType: z.string().nullable().default(null),
  asOf: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
});
export type GetEffectiveCustomerPriceInput = z.input<typeof GetEffectiveCustomerPriceInputSchema>;
