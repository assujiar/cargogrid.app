/**
 * Field-level and record-level access queries (PLT-114, CG-S6-PLT-011). Thin, typed
 * wrappers around app.can_access_record() and app.users_directory
 * (supabase/migrations/20260716110430_create_field_record_access.sql).
 */

import {
  CanAccessRecordInputSchema,
  parseUserDirectoryEntry,
  type CanAccessRecordInput,
  type UserDirectoryEntry,
} from "../contracts/field-access/field-access.ts";

export interface FieldAccessRpcClient {
  rpc(fn: "can_access_record", args: Record<string, unknown>): Promise<{ data: unknown; error: { message: string } | null }>;
}

export class RecordAccessCheckError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "RecordAccessCheckError";
  }
}

export async function canAccessRecord(client: FieldAccessRpcClient, input: CanAccessRecordInput): Promise<boolean> {
  const parsedInput = CanAccessRecordInputSchema.parse(input);

  const { data, error } = await client.rpc("can_access_record", {
    p_auth_user_id: parsedInput.authUserId,
    p_tenant_id: parsedInput.tenantId,
    p_owner_user_id: parsedInput.ownerUserId,
    p_shared_org_unit_ids: parsedInput.sharedOrgUnitIds,
    p_customer_account_ref: parsedInput.customerAccountRef,
  });

  if (error) {
    throw new RecordAccessCheckError(error.message);
  }
  if (typeof data !== "boolean") {
    throw new RecordAccessCheckError("can_access_record returned a non-boolean result");
  }
  return data;
}

export interface UserDirectoryLookupClient {
  from(table: "users_directory"): {
    select(columns: string): {
      eq(column: string, value: string): Promise<{ data: unknown[] | null; error: { message: string } | null }>;
    };
  };
}

export class UserDirectoryLookupError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "UserDirectoryLookupError";
  }
}

/** The field-masked directory for a tenant -- email is redacted per row unless the caller holds HRS:View personal data (RLS + app.has_view_personal_data() decide this server-side, not the caller). */
export async function listUserDirectory(client: UserDirectoryLookupClient, tenantId: string): Promise<UserDirectoryEntry[]> {
  const { data, error } = await client.from("users_directory").select("*").eq("tenant_id", tenantId);

  if (error) {
    throw new UserDirectoryLookupError(error.message);
  }
  return (data ?? []).map((row) => parseUserDirectoryEntry(row as Record<string, unknown>));
}
