/**
 * Contact and Activity Management read queries (COM-145, CG-S7-COM-004). Thin, typed
 * wrappers around app.find_duplicate_contacts and direct RLS-scoped selects for the
 * Contact directory/detail and Activity timeline views -- app.contacts'/app.activities'
 * own RLS policies are the real access gate, not a second check in this layer.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { FindDuplicateContactsInputSchema, parseContact, parseActivity, type FindDuplicateContactsInput, type Contact, type Activity } from "../contracts/contact/contact.ts";

const MAX_PAGE_SIZE = 100;
const DEFAULT_PAGE_SIZE = 50;

export type ContactQueryRpcClient = Pick<SupabaseClient, "rpc">;

export interface ListContactsInput {
  readonly tenantId: string;
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

/** Server-side paginated Contact directory -- RLS (contacts_select_scoped) is the real scope gate. */
export async function listContacts(client: Pick<SupabaseClient, "from">, input: ListContactsInput): Promise<ListContactsResult> {
  const pageSize = Math.min(Math.max(Math.trunc(input.pageSize ?? DEFAULT_PAGE_SIZE), 1), MAX_PAGE_SIZE);
  const page = Math.max(Math.trunc(input.page), 1);
  const from = (page - 1) * pageSize;
  const to = from + pageSize - 1;

  const { data, error, count } = await client
    .from("contacts")
    .select("*", { count: "exact" })
    .eq("tenant_id", input.tenantId)
    .order("full_name", { ascending: true })
    .range(from, to);

  if (error) {
    throw new ContactQueryError(error.message);
  }

  return {
    contacts: (data ?? []).map((row: Record<string, unknown>) => parseContact(row)),
    totalCount: count ?? 0,
    page,
    pageSize,
  };
}

/** A single contact by id, for the Contact Detail view -- returns null (never an error) when RLS/no-match yields zero rows. */
export async function getContactById(client: Pick<SupabaseClient, "from">, contactId: string): Promise<Contact | null> {
  const { data, error } = await client.from("contacts").select("*").eq("id", contactId).maybeSingle();
  if (error) {
    throw new ContactQueryError(error.message);
  }
  if (!data) {
    return null;
  }
  return parseContact(data as Record<string, unknown>);
}

/** The unified activity timeline for one related record (lead or prospect), most recent first -- RLS (activities_select_scoped) is the real scope gate. */
export async function listActivitiesForRecord(
  client: Pick<SupabaseClient, "from">,
  relatedType: "lead" | "prospect",
  relatedId: string,
): Promise<Activity[]> {
  const { data, error } = await client
    .from("activities")
    .select("*")
    .eq("related_type", relatedType)
    .eq("related_id", relatedId)
    .order("created_at", { ascending: false });
  if (error) {
    throw new ContactQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseActivity(row));
}
