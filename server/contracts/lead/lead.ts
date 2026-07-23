/**
 * Lead Management contract (COM-143, CG-S7-COM-002). Mirrors
 * supabase/migrations/20260723090000_create_commercial_lead_management.sql's app.leads
 * shape and the app.capture_lead / app.find_duplicate_leads / app.score_lead /
 * app.assign_lead / app.qualify_lead / app.disqualify_lead / app.merge_leads RPCs.
 */

import { z } from "zod";

export const LEAD_SOURCES = ["manual", "import", "api", "referral", "campaign", "integration"] as const;
export const LeadSourceSchema = z.enum(LEAD_SOURCES);
export type LeadSource = z.infer<typeof LeadSourceSchema>;

export const LEAD_STATUSES = ["new", "contacted", "qualified", "disqualified", "merged", "converted"] as const;
export const LeadStatusSchema = z.enum(LEAD_STATUSES);
export type LeadStatus = z.infer<typeof LeadStatusSchema>;

export const LeadScoreExplanationSchema = z.object({
  version: z.number().int().positive(),
  rules: z.array(z.object({ rule: z.string(), points: z.number().int() }).catchall(z.unknown())),
});
export type LeadScoreExplanation = z.infer<typeof LeadScoreExplanationSchema>;

export const LeadSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  source: LeadSourceSchema,
  externalReference: z.string().nullable(),
  companyName: z.string().nullable(),
  contactName: z.string(),
  email: z.string().nullable(),
  phone: z.string().nullable(),
  duplicateFingerprint: z.string(),
  status: LeadStatusSchema,
  disqualifyReason: z.string().nullable(),
  score: z.number().int().min(0).max(100),
  scoreExplanation: LeadScoreExplanationSchema,
  scoreVersion: z.number().int().positive(),
  ownerUserId: z.string().uuid().nullable(),
  orgUnitId: z.string().uuid().nullable(),
  assignedAt: z.string().nullable(),
  assignedBy: z.string().nullable(),
  qualifiedAt: z.string().nullable(),
  disqualifiedAt: z.string().nullable(),
  mergedIntoId: z.string().uuid().nullable(),
  mergedAt: z.string().nullable(),
  mergedBy: z.string().nullable(),
  convertedAt: z.string().nullable(),
  lastActivityAt: z.string(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type Lead = z.infer<typeof LeadSchema>;

export const CaptureLeadInputSchema = z.object({
  tenantId: z.string().uuid(),
  source: LeadSourceSchema,
  externalReference: z.string().min(1).nullable().default(null),
  companyName: z.string().min(1).nullable().default(null),
  contactName: z.string().min(1),
  email: z.string().email().nullable().default(null),
  phone: z.string().min(1).nullable().default(null),
  ownerUserId: z.string().uuid().nullable().default(null),
  orgUnitId: z.string().uuid().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  createdBy: z.string().min(1),
});
export type CaptureLeadInput = z.input<typeof CaptureLeadInputSchema>;

export const FindDuplicateLeadsInputSchema = z.object({
  tenantId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  email: z.string().nullable().default(null),
  phone: z.string().nullable().default(null),
  companyName: z.string().nullable().default(null),
});
export type FindDuplicateLeadsInput = z.input<typeof FindDuplicateLeadsInputSchema>;

export const ScoreLeadInputSchema = z.object({
  leadId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
});
export type ScoreLeadInput = z.infer<typeof ScoreLeadInputSchema>;

export const AssignLeadInputSchema = z.object({
  leadId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  newOwnerUserId: z.string().uuid().nullable(),
  newOrgUnitId: z.string().uuid().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type AssignLeadInput = z.infer<typeof AssignLeadInputSchema>;

export const QualifyLeadInputSchema = z.object({
  leadId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type QualifyLeadInput = z.infer<typeof QualifyLeadInputSchema>;

export const DisqualifyLeadInputSchema = z.object({
  leadId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type DisqualifyLeadInput = z.infer<typeof DisqualifyLeadInputSchema>;

export const MergeLeadsInputSchema = z.object({
  survivorLeadId: z.string().uuid(),
  duplicateLeadId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type MergeLeadsInput = z.infer<typeof MergeLeadsInputSchema>;

/** Maps a raw app.leads row (snake_case) to this contract's camelCase shape. */
export function parseLead(row: Record<string, unknown>): Lead {
  return LeadSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    source: row.source,
    externalReference: row.external_reference,
    companyName: row.company_name,
    contactName: row.contact_name,
    email: row.email,
    phone: row.phone,
    duplicateFingerprint: row.duplicate_fingerprint,
    status: row.status,
    disqualifyReason: row.disqualify_reason,
    score: row.score,
    scoreExplanation: row.score_explanation,
    scoreVersion: row.score_version,
    ownerUserId: row.owner_user_id,
    orgUnitId: row.org_unit_id,
    assignedAt: row.assigned_at,
    assignedBy: row.assigned_by,
    qualifiedAt: row.qualified_at,
    disqualifiedAt: row.disqualified_at,
    mergedIntoId: row.merged_into_id,
    mergedAt: row.merged_at,
    mergedBy: row.merged_by,
    convertedAt: row.converted_at,
    lastActivityAt: row.last_activity_at,
    recordVersion: row.record_version,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}
