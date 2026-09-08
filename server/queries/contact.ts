/**
 * Contact and Activity Management read queries (COM-145, CG-S7-COM-004). Thin, typed
 * wrappers around app.find_duplicate_contacts and direct RLS-scoped selects for the
 * Contact directory/detail and Activity timeline views -- app.contacts'/app.activities'
 * own RLS policies are the real access gate, not a second check in this layer.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { FindDuplicateContactsInputSchema, parseContact, parseActivity, type FindDuplicateContactsInput, type Contact, type Activity, type RelatedType } from "../contracts/contact/contact.ts";

const MAX_PAGE_SIZE = 100;
const DEFAULT_PAGE_SIZE = 50;

export type ContactQueryRpcClient = Pick<SupabaseClient, "rpc">;

export interface ListContactsInput {
  readonly tenantId: string;
  readonly actorAuthUserId: string;
  readonly page: number;
  readonly pageSize?: number;
}

export interface ListContactsResult {
  readonly contacts: readonly Contact[];
  readonly totalCount: number;
  readonly page: number;
  readonly pageSize: number;
}

export class ContactQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ContactQueryError";
  }
}

/** Tenant-scoped duplicate-candidate search by normalized email/phone. Fails closed (raises) for an actor with no active membership in tenantId. */
export async function findDuplicateContacts(client: ContactQueryRpcClient, input: FindDuplicateContactsInput): Promise<Contact[]> {
  const parsedInput = FindDuplicateContactsInputSchema.parse(input);
  const { data, error } = await client.rpc("find_duplicate_contacts", {
    p_tenant_id: parsedInput.tenantId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_email: parsedInput.email,
    p_phone: parsedInput.phone,
  });
  if (error) {
    throw new ContactQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new ContactQueryError("find_duplicate_contacts returned a non-array result");
  }
  return data.map((row) => parseContact(row as Record<string, unknown>));
}

/** Server-side paginated Contact directory -- app.list_contacts (SECURITY DEFINER) is the real scope gate; never returns normalized_email/normalized_phone/duplicate_fingerprint. */
export async function listContacts(client: ContactQueryRpcClient, input: ListContactsInput): Promise<ListContactsResult> {
  const pageSize = Math.min(Math.max(Math.trunc(input.pageSize ?? DEFAULT_PAGE_SIZE), 1), MAX_PAGE_SIZE);
  const page = Math.max(Math.trunc(input.page), 1);

  const { data, error } = await client.rpc("list_contacts", {
    p_tenant_id: input.tenantId,
    p_actor_auth_user_id: input.actorAuthUserId,
    p_page: page,
    p_page_size: pageSize,
  });

  if (error) {
    throw new ContactQueryError(error.message);
  }

  const rows = (data ?? []) as Record<string, unknown>[];
  const totalCount = rows.length > 0 ? Number(rows[0]?.total_count) : 0;

  return {
    contacts: rows.map((row) => parseContact(row)),
    totalCount,
    page,
    pageSize,
  };
}

/** A single contact by id, for the Contact Detail view -- returns null (never an error) when denied/no-match yields zero rows. */
export async function getContactById(client: ContactQueryRpcClient, contactId: string, actorAuthUserId: string): Promise<Contact | null> {
  const { data, error } = await client.rpc("get_contact_by_id", {
    p_contact_id: contactId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new ContactQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row) {
    return null;
  }
  return parseContact(row as Record<string, unknown>);
}

/** The unified activity timeline for one related record (lead, prospect, or -- since COM-147 -- opportunity), most recent first -- app.list_activities_for_record (SECURITY DEFINER) is the real scope gate. */
export async function listActivitiesForRecord(
  client: ContactQueryRpcClient,
  relatedType: RelatedType,
  relatedId: string,
  actorAuthUserId: string,
): Promise<Activity[]> {
  const { data, error } = await client.rpc("list_activities_for_record", {
    p_related_type: relatedType,
    p_related_id: relatedId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new ContactQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new ContactQueryError("list_activities_for_record returned a non-array result");
  }
  return data.map((row) => parseActivity(row as Record<string, unknown>));
}
