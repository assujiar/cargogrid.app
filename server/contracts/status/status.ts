/**
 * Status engine contract (PLT-124, CG-S6-PLT-021). Mirrors
 * supabase/migrations/20260719100000_create_status_engine.sql's
 * app.status_sets/app.canonical_statuses/app.status_legacy_mappings shape and the
 * app.register_status_set / app.register_canonical_status /
 * app.register_status_legacy_mapping / app.resolve_legacy_status /
 * app.get_status_set_registry / app.publish_status_presentation /
 * app.resolve_status_presentation RPCs.
 *
 * A status *presentation* is not modeled here as its own row type -- it is PLT-121's
 * own ConfigVersion/config_items (config_type_code='status:<code>'), reused directly
 * (this migration's own header). `publishStatusPresentation` therefore still returns a
 * `ConfigVersion` (server/contracts/config/config.ts), not a bespoke type.
 */

import { z } from "zod";
import { ConfigVersionSchema, type ConfigVersion } from "../config/config.ts";

export const STATUS_CATEGORIES = ["initial", "active", "terminal"] as const;
export const StatusCategorySchema = z.enum(STATUS_CATEGORIES);
export type StatusCategory = z.infer<typeof StatusCategorySchema>;

export const StatusSetSchema = z.object({
  code: z.string(),
  name: z.string(),
  ownerPrimitiveCode: z.string(),
  registeredBy: z.string().nullable(),
  createdAt: z.string(),
});
export type StatusSet = z.infer<typeof StatusSetSchema>;

export const CanonicalStatusSchema = z.object({
  id: z.string().uuid(),
  statusSetCode: z.string(),
  code: z.string(),
  category: StatusCategorySchema,
  sortOrder: z.number().int(),
  registeredBy: z.string().nullable(),
  createdAt: z.string(),
  isTerminal: z.boolean(),
});
export type CanonicalStatus = z.infer<typeof CanonicalStatusSchema>;

export const StatusLegacyMappingSchema = z.object({
  id: z.string().uuid(),
  statusSetCode: z.string(),
  legacyValue: z.string(),
  canonicalStatusId: z.string().uuid(),
  registeredBy: z.string().nullable(),
  createdAt: z.string(),
});
export type StatusLegacyMapping = z.infer<typeof StatusLegacyMappingSchema>;

export const ResolvedStatusPresentationSchema = z.object({
  canonicalStatusCode: z.string(),
  category: StatusCategorySchema,
  isTerminal: z.boolean(),
  resolvedLabel: z.string(),
  resolvedColor: z.string().nullable(),
  resolvedIcon: z.string(),
  isFallback: z.boolean(),
  resolvedVersionId: z.string().uuid().nullable(),
});
export type ResolvedStatusPresentation = z.infer<typeof ResolvedStatusPresentationSchema>;

export const RegisterStatusSetInputSchema = z.object({
  code: z.string().min(1),
  name: z.string().min(1),
  ownerPrimitiveCode: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  registeredBy: z.string().min(1),
});
export type RegisterStatusSetInput = z.input<typeof RegisterStatusSetInputSchema>;

export const RegisterCanonicalStatusInputSchema = z.object({
  statusSetCode: z.string().min(1),
  code: z.string().min(1),
  category: StatusCategorySchema,
  sortOrder: z.number().int().default(0),
  actorAuthUserId: z.string().uuid(),
  registeredBy: z.string().min(1),
});
export type RegisterCanonicalStatusInput = z.input<typeof RegisterCanonicalStatusInputSchema>;

export const RegisterStatusLegacyMappingInputSchema = z.object({
  statusSetCode: z.string().min(1),
  legacyValue: z.string().min(1),
  canonicalStatusCode: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  registeredBy: z.string().min(1),
});
export type RegisterStatusLegacyMappingInput = z.input<typeof RegisterStatusLegacyMappingInputSchema>;

export const PublishStatusPresentationInputSchema = z.object({
  versionId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  effectiveFrom: z.string().nullable().default(null),
  actorLabel: z.string().min(1),
});
export type PublishStatusPresentationInput = z.input<typeof PublishStatusPresentationInputSchema>;

export const ResolveLegacyStatusInputSchema = z.object({
  statusSetCode: z.string().min(1),
  legacyValue: z.string().min(1),
});
export type ResolveLegacyStatusInput = z.input<typeof ResolveLegacyStatusInputSchema>;

export const GetStatusSetRegistryInputSchema = z.object({
  statusSetCode: z.string().min(1),
});
export type GetStatusSetRegistryInput = z.input<typeof GetStatusSetRegistryInputSchema>;

export const ResolveStatusPresentationInputSchema = z.object({
  statusSetCode: z.string().min(1),
  canonicalStatusCode: z.string().min(1),
  tenantId: z.string().uuid(),
  companyId: z.string().uuid().nullable().default(null),
  branchId: z.string().uuid().nullable().default(null),
  roleId: z.string().uuid().nullable().default(null),
  userId: z.string().uuid().nullable().default(null),
});
export type ResolveStatusPresentationInput = z.input<typeof ResolveStatusPresentationInputSchema>;

/** Re-exported so callers of publishStatusPresentation don't need a separate import from ../config/config.ts. */
export { ConfigVersionSchema };
export type { ConfigVersion };

/** Maps a raw app.status_sets row (snake_case) to this contract's camelCase shape. */
export function parseStatusSet(row: Record<string, unknown>): StatusSet {
  return StatusSetSchema.parse({
    code: row.code,
    name: row.name,
    ownerPrimitiveCode: row.owner_primitive_code,
    registeredBy: row.registered_by,
    createdAt: row.created_at,
  });
}

/** Maps a raw app.canonical_statuses row (snake_case) to this contract's camelCase shape. */
export function parseCanonicalStatus(row: Record<string, unknown>): CanonicalStatus {
  return CanonicalStatusSchema.parse({
    id: row.id,
    statusSetCode: row.status_set_code,
    code: row.code,
    category: row.category,
    sortOrder: row.sort_order,
    registeredBy: row.registered_by,
    createdAt: row.created_at,
    isTerminal: row.is_terminal,
  });
}

/** Maps a raw app.status_legacy_mappings row (snake_case) to this contract's camelCase shape. */
export function parseStatusLegacyMapping(row: Record<string, unknown>): StatusLegacyMapping {
  return StatusLegacyMappingSchema.parse({
    id: row.id,
    statusSetCode: row.status_set_code,
    legacyValue: row.legacy_value,
    canonicalStatusId: row.canonical_status_id,
    registeredBy: row.registered_by,
    createdAt: row.created_at,
  });
}

/** Maps a raw app.resolve_status_presentation() row (snake_case) to this contract's camelCase shape. */
export function parseResolvedStatusPresentation(row: Record<string, unknown>): ResolvedStatusPresentation {
  return ResolvedStatusPresentationSchema.parse({
    canonicalStatusCode: row.canonical_status_code,
    category: row.category,
    isTerminal: row.is_terminal,
    resolvedLabel: row.resolved_label,
    resolvedColor: row.resolved_color,
    resolvedIcon: row.resolved_icon,
    isFallback: row.is_fallback,
    resolvedVersionId: row.resolved_version_id,
  });
}
