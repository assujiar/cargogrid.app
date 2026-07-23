/**
 * Prospect Lifecycle contract (COM-144, CG-S7-COM-003). Mirrors
 * supabase/migrations/20260723120000_create_commercial_prospect_lifecycle.sql's
 * app.prospects shape and the app.convert_lead_to_prospect /
 * app.link_lead_to_existing_prospect / app.find_duplicate_prospects /
 * app.get_prospect_conversion_readiness / app.disqualify_prospect /
 * app.archive_prospect / app.merge_prospects RPCs.
 */

import { z } from "zod";

export const PROSPECT_STATUSES = ["active", "disqualified", "archived", "merged"] as const;
export const ProspectStatusSchema = z.enum(PROSPECT_STATUSES);
export type ProspectStatus = z.infer<typeof ProspectStatusSchema>;

export const ProspectSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  leadId: z.string().uuid(),
  legalName: z.string(),
  tradeName: z.string().nullable(),
  taxId: z.string().nullable(),
  billingAddress: z.record(z.string(), z.unknown()),
  contactName: z.string(),
  contactEmail: z.string().nullable(),
  contactPhone: z.string().nullable(),
  status: ProspectStatusSchema,
  disqualifyReason: z.string().nullable(),
  ownerUserId: z.string().uuid().nullable(),
  orgUnitId: z.string().uuid().nullable(),
  mergedIntoId: z.string().uuid().nullable(),
  mergedAt: z.string().nullable(),
  mergedBy: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type Prospect = z.infer<typeof ProspectSchema>;

export const ConversionReadinessSchema = z.object({
  ready: z.boolean(),
  missing: z.array(z.string()),
});
export type ConversionReadiness = z.infer<typeof ConversionReadinessSchema>;

export const ConvertLeadToProspectInputSchema = z.object({
  leadId: z.string().uuid(),
  legalName: z.string().min(1),
  tradeName: z.string().min(1).nullable().default(null),
  taxId: z.string().min(1).nullable().default(null),
  billingAddress: z.record(z.string(), z.unknown()).default({}),
  actorAuthUserId: z.string().uuid(),
  createdBy: z.string().min(1),
});
export type ConvertLeadToProspectInput = z.input<typeof ConvertLeadToProspectInputSchema>;

export const LinkLeadToExistingProspectInputSchema = z.object({
  leadId: z.string().uuid(),
  prospectId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type LinkLeadToExistingProspectInput = z.infer<typeof LinkLeadToExistingProspectInputSchema>;

export const FindDuplicateProspectsInputSchema = z.object({
  tenantId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  legalName: z.string().nullable().default(null),
  taxId: z.string().nullable().default(null),
});
export type FindDuplicateProspectsInput = z.input<typeof FindDuplicateProspectsInputSchema>;

export const DisqualifyProspectInputSchema = z.object({
  prospectId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type DisqualifyProspectInput = z.infer<typeof DisqualifyProspectInputSchema>;

export const ArchiveProspectInputSchema = z.object({
  prospectId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ArchiveProspectInput = z.infer<typeof ArchiveProspectInputSchema>;

export const MergeProspectsInputSchema = z.object({
  survivorProspectId: z.string().uuid(),
  duplicateProspectId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type MergeProspectsInput = z.infer<typeof MergeProspectsInputSchema>;

/** Maps a raw app.prospects row (snake_case) to this contract's camelCase shape. */
export function parseProspect(row: Record<string, unknown>): Prospect {
  return ProspectSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    leadId: row.lead_id,
    legalName: row.legal_name,
    tradeName: row.trade_name,
    taxId: row.tax_id,
    billingAddress: row.billing_address,
    contactName: row.contact_name,
    contactEmail: row.contact_email,
    contactPhone: row.contact_phone,
    status: row.status,
    disqualifyReason: row.disqualify_reason,
    ownerUserId: row.owner_user_id,
    orgUnitId: row.org_unit_id,
    mergedIntoId: row.merged_into_id,
    mergedAt: row.merged_at,
    mergedBy: row.merged_by,
    recordVersion: row.record_version,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}
