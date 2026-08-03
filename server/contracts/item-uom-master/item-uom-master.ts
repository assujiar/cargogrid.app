/**
 * Item/SKU and UOM Master contract (ATW-011A, CG-S10-ATW-011A). Mirrors
 * supabase/migrations/20260730160000_create_advanced_tms_item_uom_master.sql's
 * app.item_masters/app.uoms/app.uom_conversions shapes and their
 * create/update/status/read/convert RPCs.
 *
 * This capability was inserted between the VERIFIED Prompt 230 (Bin and Racking) and
 * Prompt 231 (WMS Inbound) by explicit operator authorization -- no prompt in
 * docs/ai-agent-build-prompt-package/ ever creates an item/SKU/product master or a
 * UOM master, yet Prompt 231 §9 and Prompt 234 §9 both require one already VERIFIED
 * (docs/adr/ADR-0019). unitCategory is a deliberately narrow closed enum (weight/
 * volume/count/length) -- discrete packaging/handling units (box, carton, pallet) are
 * not a UOM here, deferred to Prompt 237 (design note 4 of the migration above).
 */

import { z } from "zod";

export const ITEM_MASTER_STATUSES = ["active", "inactive"] as const;
export const ItemMasterStatusSchema = z.enum(ITEM_MASTER_STATUSES);
export type ItemMasterStatus = z.infer<typeof ItemMasterStatusSchema>;

export const UOM_CATEGORIES = ["weight", "volume", "count", "length"] as const;
export const UomCategorySchema = z.enum(UOM_CATEGORIES);
export type UomCategory = z.infer<typeof UomCategorySchema>;

export const ItemMasterSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  ownerAccountId: z.string().uuid(),
  code: z.string(),
  name: z.string(),
  description: z.string().nullable(),
  baseUomCode: z.string(),
  lotControlled: z.boolean(),
  serialControlled: z.boolean(),
  expiryControlled: z.boolean(),
  status: ItemMasterStatusSchema,
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type ItemMaster = z.infer<typeof ItemMasterSchema>;

export function parseItemMaster(row: Record<string, unknown>): ItemMaster {
  return ItemMasterSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    ownerAccountId: row.owner_account_id,
    code: row.code,
    name: row.name,
    description: row.description ?? null,
    baseUomCode: row.base_uom_code,
    lotControlled: row.lot_controlled,
    serialControlled: row.serial_controlled,
    expiryControlled: row.expiry_controlled,
    status: row.status,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const UomSchema = z.object({
  code: z.string(),
  name: z.string(),
  unitCategory: UomCategorySchema,
  isActive: z.boolean(),
});
export type Uom = z.infer<typeof UomSchema>;

export function parseUom(row: Record<string, unknown>): Uom {
  return UomSchema.parse({
    code: row.code,
    name: row.name,
    unitCategory: row.unit_category,
    isActive: row.is_active,
  });
}

// --- Mutation input schemas ---

export const CreateItemMasterInputSchema = z.object({
  tenantId: z.string().uuid(),
  ownerAccountId: z.string().uuid(),
  code: z.string().min(1),
  name: z.string().min(1),
  description: z.string().nullable(),
  baseUomCode: z.string().min(1),
  lotControlled: z.boolean(),
  serialControlled: z.boolean(),
  expiryControlled: z.boolean(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreateItemMasterInput = z.input<typeof CreateItemMasterInputSchema>;

export const UpdateItemMasterInputSchema = z.object({
  itemMasterId: z.string().uuid(),
  name: z.string().min(1),
  description: z.string().nullable(),
  lotControlled: z.boolean(),
  serialControlled: z.boolean(),
  expiryControlled: z.boolean(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type UpdateItemMasterInput = z.input<typeof UpdateItemMasterInputSchema>;

export const SetItemMasterStatusInputSchema = z.object({
  itemMasterId: z.string().uuid(),
  newStatus: ItemMasterStatusSchema,
  reason: z.string().nullable(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type SetItemMasterStatusInput = z.input<typeof SetItemMasterStatusInputSchema>;
