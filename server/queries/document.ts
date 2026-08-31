/**
 * Document and file engine read queries (PLT-128, CG-S6-PLT-025).
 *
 * ISS-2026-172(b), 2026-08-31: `listFilesForTenant` no longer reads app.files directly. It
 * now calls the `list_files_for_tenant` RPC (20260831040000), which composes
 * app.authorize_file_access per row with access_type='metadata_view' -- so every row it
 * returns leaves an app.file_access_logs entry. The direct RLS read it used to do could not
 * be logged by any means: PostgreSQL has no SELECT trigger.
 *
 * The direct column grant on app.files is deliberately NOT revoked. It backs the
 * files_select_scoped RLS policy that 12 db-test assertions exercise (uploader sees own row,
 * shared teammate sees it, outsider and cross-tenant do not, customer_user sees zero), and
 * revoking it would turn a working tenant-isolation control into dead code, since every RPC
 * runs as definer and bypasses RLS anyway. This module simply stops being the thing that
 * uses it.
 *
 * listDocumentTypes below is unchanged and stays a direct read: app.document_types is a
 * deliberately broadly-readable registry (app.document_types_select_all), not tenant data.
 */

import { parseFileSummary, parseDocumentType, type FileSummary, type DocumentType } from "../contracts/document/document.ts";

export interface FileLookupClient {
  rpc(
    fn: "list_files_for_tenant",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export class FileLookupError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "FileLookupError";
  }
}

/**
 * Every file in this tenant the actor is authorized to see, as metadata.
 *
 * Goes through the `list_files_for_tenant` RPC rather than reading app.files, so each row
 * returned is both authority-checked and access-logged by app.authorize_file_access. A row
 * the actor may not see is skipped by the RPC rather than raising, so an unauthorized row
 * neither breaks the listing nor discloses its own existence through an error.
 *
 * Returns FileSummary, never File: storage_path is not in the RPC's authorized projection,
 * and `authenticated` holds no column grant on it either (ISS-2026-216).
 *
 * `actorAuthUserId` must be the calling session's own identity -- the RPC asserts it, so
 * passing another user's id is refused rather than silently honoured.
 */
export async function listFilesForTenant(
  client: FileLookupClient,
  tenantId: string,
  actorAuthUserId: string,
  correlationId: string | null = null,
): Promise<FileSummary[]> {
  const { data, error } = await client.rpc("list_files_for_tenant", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_correlation_id: correlationId,
  });

  if (error) {
    throw new FileLookupError(error.message);
  }
  if (data !== null && data !== undefined && !Array.isArray(data)) {
    throw new FileLookupError("list_files_for_tenant returned a non-array result");
  }
  return ((data as unknown[] | null) ?? []).map((row) => parseFileSummary(row as Record<string, unknown>));
}

export interface DocumentTypeLookupClient {
  from(table: "document_types"): {
    select(columns: string): Promise<{ data: unknown[] | null; error: { message: string } | null }>;
  };
}

export class DocumentTypeLookupError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "DocumentTypeLookupError";
  }
}

/** The full document-type registry -- broadly readable to any authenticated caller (app.document_types_select_all policy). */
export async function listDocumentTypes(client: DocumentTypeLookupClient): Promise<DocumentType[]> {
  const { data, error } = await client.from("document_types").select("*");

  if (error) {
    throw new DocumentTypeLookupError(error.message);
  }
  return (data ?? []).map((row) => parseDocumentType(row as Record<string, unknown>));
}
