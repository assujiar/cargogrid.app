/**
 * Contact and Activity Management mutation primitives (COM-145, CG-S7-COM-004). Thin,
 * typed wrappers around app.create_contact / app.link_contact_to_record /
 * app.unlink_contact_from_record / app.log_activity / app.complete_activity /
 * app.reschedule_activity / app.cancel_activity
 * (supabase/migrations/20260723150000_create_commercial_contact_activity_management.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateContactInputSchema,
  LinkContactToRecordInputSchema,
  UnlinkContactFromRecordInputSchema,
  LogActivityInputSchema,
  CompleteActivityInputSchema,
  RescheduleActivityInputSchema,
  CancelActivityInputSchema,
  parseContact,
  parseContactLink,
  parseActivity,
  type CreateContactInput,
  type LinkContactToRecordInput,
  type UnlinkContactFromRecordInput,
  type LogActivityInput,
  type CompleteActivityInput,
  type RescheduleActivityInput,
  type CancelActivityInput,
  type Contact,
  type ContactLink,
  type Activity,
} from "../contracts/contact/contact.ts";

export type ContactMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const CONTACT_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "contact_not_found",
  "contact_link_not_found",
  "activity_not_found",
  "cross_tenant_link_denied",
  "unknown_related_type",
  "related_record_not_found",
  "stale_version",
  "invalid_transition",
] as const;
type KnownContactMutationErrorCode = (typeof CONTACT_KNOWN_MUTATION_ERROR_CODES)[number];
export type ContactMutationErrorCode = KnownContactMutationErrorCode | "mutation_failed" | "invalid_response";

export class ContactMutationError extends Error {
  readonly code: ContactMutationErrorCode;

  constructor(code: ContactMutationErrorCode, message: string) {
    super(message);
    this.name = "ContactMutationError";
    this.code = code;
  }
}

function classifyError(message: string): ContactMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (CONTACT_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownContactMutationErrorCode)
    : "mutation_failed";
}

async function callRpc(client: ContactMutationRpcClient, fn: string, args: Record<string, unknown>): Promise<unknown> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new ContactMutationError(classifyError(error.message), error.message);
  }
  return data;
}

async function callAndParseContact(client: ContactMutationRpcClient, fn: string, args: Record<string, unknown>): Promise<Contact> {
  const data = await callRpc(client, fn, args);
  if (!data || typeof data !== "object") {
    throw new ContactMutationError("invalid_response", `${fn} returned no row`);
  }
  return parseContact(data as Record<string, unknown>);
}

async function callAndParseActivity(client: ContactMutationRpcClient, fn: string, args: Record<string, unknown>): Promise<Activity> {
  const data = await callRpc(client, fn, args);
  if (!data || typeof data !== "object") {
    throw new ContactMutationError("invalid_response", `${fn} returned no row`);
  }
  return parseActivity(data as Record<string, unknown>);
}

/** Always creates a new contact -- never idempotent on an external key. Call findDuplicateContacts first to review candidates. */
export async function createContact(client: ContactMutationRpcClient, input: CreateContactInput): Promise<Contact> {
  const parsedInput = CreateContactInputSchema.parse(input);
  return callAndParseContact(client, "create_contact", {
    p_tenant_id: parsedInput.tenantId,
    p_full_name: parsedInput.fullName,
    p_title: parsedInput.title,
    p_email: parsedInput.email,
    p_phone: parsedInput.phone,
    p_owner_user_id: parsedInput.ownerUserId,
    p_org_unit_id: parsedInput.orgUnitId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_created_by: parsedInput.createdBy,
  });
}

/** Idempotent on (contactId, relatedType, relatedId, role). Requires access to both the contact and the target record. */
export async function linkContactToRecord(client: ContactMutationRpcClient, input: LinkContactToRecordInput): Promise<ContactLink> {
  const parsedInput = LinkContactToRecordInputSchema.parse(input);
  const data = await callRpc(client, "link_contact_to_record", {
    p_contact_id: parsedInput.contactId,
    p_related_type: parsedInput.relatedType,
    p_related_id: parsedInput.relatedId,
    p_role: parsedInput.role,
    p_is_primary: parsedInput.isPrimary,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (!data || typeof data !== "object") {
    throw new ContactMutationError("invalid_response", "link_contact_to_record returned no row");
  }
  return parseContactLink(data as Record<string, unknown>);
}

/** Removes a contact-to-record relationship (not the contact itself). */
export async function unlinkContactFromRecord(client: ContactMutationRpcClient, input: UnlinkContactFromRecordInput): Promise<void> {
  const parsedInput = UnlinkContactFromRecordInputSchema.parse(input);
  await callRpc(client, "unlink_contact_from_record", {
    p_link_id: parsedInput.linkId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** Covers both already-happened activities (status=completed) and to-do activities (status=scheduled) -- the caller chooses the initial status. */
export async function logActivity(client: ContactMutationRpcClient, input: LogActivityInput): Promise<Activity> {
  const parsedInput = LogActivityInputSchema.parse(input);
  return callAndParseActivity(client, "log_activity", {
    p_related_type: parsedInput.relatedType,
    p_related_id: parsedInput.relatedId,
    p_contact_id: parsedInput.contactId,
    p_type: parsedInput.type,
    p_subject: parsedInput.subject,
    p_notes: parsedInput.notes,
    p_status: parsedInput.status,
    p_due_at: parsedInput.dueAt,
    p_completed_at: parsedInput.completedAt,
    p_outcome: parsedInput.outcome,
    p_owner_user_id: parsedInput.ownerUserId,
    p_org_unit_id: parsedInput.orgUnitId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_created_by: parsedInput.createdBy,
  });
}

/** scheduled -> completed. */
export async function completeActivity(client: ContactMutationRpcClient, input: CompleteActivityInput): Promise<Activity> {
  const parsedInput = CompleteActivityInputSchema.parse(input);
  return callAndParseActivity(client, "complete_activity", {
    p_activity_id: parsedInput.activityId,
    p_expected_version: parsedInput.expectedVersion,
    p_outcome: parsedInput.outcome,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** Only a scheduled activity may be rescheduled. */
export async function rescheduleActivity(client: ContactMutationRpcClient, input: RescheduleActivityInput): Promise<Activity> {
  const parsedInput = RescheduleActivityInputSchema.parse(input);
  return callAndParseActivity(client, "reschedule_activity", {
    p_activity_id: parsedInput.activityId,
    p_expected_version: parsedInput.expectedVersion,
    p_new_due_at: parsedInput.newDueAt,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** scheduled -> cancelled. */
export async function cancelActivity(client: ContactMutationRpcClient, input: CancelActivityInput): Promise<Activity> {
  const parsedInput = CancelActivityInputSchema.parse(input);
  return callAndParseActivity(client, "cancel_activity", {
    p_activity_id: parsedInput.activityId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}
