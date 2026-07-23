/**
 * Contact and Activity Management contract (COM-145, CG-S7-COM-004). Mirrors
 * supabase/migrations/20260723150000_create_commercial_contact_activity_management.sql's
 * app.contacts/app.contact_links/app.activities shape and their RPCs.
 */

import { z } from "zod";

export const RELATED_TYPES = ["lead", "prospect"] as const;
export const RelatedTypeSchema = z.enum(RELATED_TYPES);
export type RelatedType = z.infer<typeof RelatedTypeSchema>;

export const CONTACT_STATUSES = ["active", "archived"] as const;
export const ContactStatusSchema = z.enum(CONTACT_STATUSES);
export type ContactStatus = z.infer<typeof ContactStatusSchema>;

export const CONTACT_LINK_ROLES = ["primary", "billing", "technical", "decision_maker", "other"] as const;
export const ContactLinkRoleSchema = z.enum(CONTACT_LINK_ROLES);
export type ContactLinkRole = z.infer<typeof ContactLinkRoleSchema>;

export const ACTIVITY_TYPES = ["call", "email", "meeting", "visit", "follow_up", "task"] as const;
export const ActivityTypeSchema = z.enum(ACTIVITY_TYPES);
export type ActivityType = z.infer<typeof ActivityTypeSchema>;

export const ACTIVITY_STATUSES = ["scheduled", "completed", "cancelled"] as const;
export const ActivityStatusSchema = z.enum(ACTIVITY_STATUSES);
export type ActivityStatus = z.infer<typeof ActivityStatusSchema>;

export const ContactSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  fullName: z.string(),
  title: z.string().nullable(),
  email: z.string().nullable(),
  phone: z.string().nullable(),
  status: ContactStatusSchema,
  ownerUserId: z.string().uuid().nullable(),
  orgUnitId: z.string().uuid().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type Contact = z.infer<typeof ContactSchema>;

export const ContactLinkSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  contactId: z.string().uuid(),
  relatedType: RelatedTypeSchema,
  relatedId: z.string().uuid(),
  role: ContactLinkRoleSchema,
  isPrimary: z.boolean(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
});
export type ContactLink = z.infer<typeof ContactLinkSchema>;

export const ActivitySchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  type: ActivityTypeSchema,
  subject: z.string(),
  notes: z.string().nullable(),
  status: ActivityStatusSchema,
  dueAt: z.string().nullable(),
  completedAt: z.string().nullable(),
  outcome: z.string().nullable(),
  relatedType: RelatedTypeSchema,
  relatedId: z.string().uuid(),
  contactId: z.string().uuid().nullable(),
  ownerUserId: z.string().uuid().nullable(),
  orgUnitId: z.string().uuid().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type Activity = z.infer<typeof ActivitySchema>;

export const CreateContactInputSchema = z.object({
  tenantId: z.string().uuid(),
  fullName: z.string().min(1),
  title: z.string().min(1).nullable().default(null),
  email: z.string().email().nullable().default(null),
  phone: z.string().min(1).nullable().default(null),
  ownerUserId: z.string().uuid().nullable().default(null),
  orgUnitId: z.string().uuid().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  createdBy: z.string().min(1),
});
export type CreateContactInput = z.input<typeof CreateContactInputSchema>;

export const FindDuplicateContactsInputSchema = z.object({
  tenantId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  email: z.string().nullable().default(null),
  phone: z.string().nullable().default(null),
});
export type FindDuplicateContactsInput = z.input<typeof FindDuplicateContactsInputSchema>;

export const LinkContactToRecordInputSchema = z.object({
  contactId: z.string().uuid(),
  relatedType: RelatedTypeSchema,
  relatedId: z.string().uuid(),
  role: ContactLinkRoleSchema.default("other"),
  isPrimary: z.boolean().default(false),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type LinkContactToRecordInput = z.input<typeof LinkContactToRecordInputSchema>;

export const UnlinkContactFromRecordInputSchema = z.object({
  linkId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type UnlinkContactFromRecordInput = z.infer<typeof UnlinkContactFromRecordInputSchema>;

export const LogActivityInputSchema = z.object({
  relatedType: RelatedTypeSchema,
  relatedId: z.string().uuid(),
  contactId: z.string().uuid().nullable().default(null),
  type: ActivityTypeSchema,
  subject: z.string().min(1),
  notes: z.string().nullable().default(null),
  status: ActivityStatusSchema.default("scheduled"),
  dueAt: z.string().nullable().default(null),
  completedAt: z.string().nullable().default(null),
  outcome: z.string().nullable().default(null),
  ownerUserId: z.string().uuid().nullable().default(null),
  orgUnitId: z.string().uuid().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  createdBy: z.string().min(1),
});
export type LogActivityInput = z.input<typeof LogActivityInputSchema>;

export const CompleteActivityInputSchema = z.object({
  activityId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  outcome: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CompleteActivityInput = z.input<typeof CompleteActivityInputSchema>;

export const RescheduleActivityInputSchema = z.object({
  activityId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  newDueAt: z.string(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RescheduleActivityInput = z.infer<typeof RescheduleActivityInputSchema>;

export const CancelActivityInputSchema = z.object({
  activityId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CancelActivityInput = z.infer<typeof CancelActivityInputSchema>;

/** Maps a raw app.contacts row (snake_case) to this contract's camelCase shape. */
export function parseContact(row: Record<string, unknown>): Contact {
  return ContactSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    fullName: row.full_name,
    title: row.title,
    email: row.email,
    phone: row.phone,
    status: row.status,
    ownerUserId: row.owner_user_id,
    orgUnitId: row.org_unit_id,
    recordVersion: row.record_version,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Maps a raw app.contact_links row (snake_case) to this contract's camelCase shape. */
export function parseContactLink(row: Record<string, unknown>): ContactLink {
  return ContactLinkSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    contactId: row.contact_id,
    relatedType: row.related_type,
    relatedId: row.related_id,
    role: row.role,
    isPrimary: row.is_primary,
    createdBy: row.created_by,
    createdAt: row.created_at,
  });
}

/** Maps a raw app.activities row (snake_case) to this contract's camelCase shape. */
export function parseActivity(row: Record<string, unknown>): Activity {
  return ActivitySchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    type: row.type,
    subject: row.subject,
    notes: row.notes,
    status: row.status,
    dueAt: row.due_at,
    completedAt: row.completed_at,
    outcome: row.outcome,
    relatedType: row.related_type,
    relatedId: row.related_id,
    contactId: row.contact_id,
    ownerUserId: row.owner_user_id,
    orgUnitId: row.org_unit_id,
    recordVersion: row.record_version,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}
