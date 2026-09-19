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
 * listDocumentTypes below now goes through the app.list_document_types RPC (O1 remediation,
 * cluster 5): app.document_types is a deliberately broadly-readable registry
 * (app.document_types_select_all, a bare `using (true)` policy), but "app" is never exposed
 * to PostgREST regardless of how permissive its own RLS policy is, so the direct
 * `.from("document_types")` read this module used before had never actually worked in
 * production -- the same defect class this whole module's header already documents for
 * app.files. The new RPC is SECURITY INVOKER, zero actor parameter, matching
 * app.list_milestone_codes' own identical precedent for a genuinely-open-RLS reference table.
 *
 * listFilesForRecord (O1 remediation, cluster 7): the same broken-`.from("files")`-never-worked
 * defect, this time a record-scoped read embedded directly in
 * app/(tenant)/[tenantSlug]/hris/employees/[masterRecordId]/page.tsx. Goes through the new
 * `list_files_for_record` RPC (20260913050000), which mirrors `list_files_for_tenant` exactly
 * (same per-row app.authorize_file_access('metadata_view') composition, same [1,200] clamp),
 * scoped by (tenant_id, record_type, record_id) instead of tenant_id alone.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { parseFileSummary, parseDocumentType, type FileSummary, type DocumentType } from "../contracts/document/document.ts";
import { BOUNDED_LIST_LIMIT, toBoundedListByCapReached, type BoundedList } from "./bounded-list.ts";

export interface FileLookupClient {
  rpc(
    fn: "list_files_for_tenant" | "list_files_for_record",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

/** Adapts a real Supabase client (whose own .rpc() returns a thenable query builder, not a plain Promise) into this module's narrower rpc-only contract -- same idiom as server/queries/procurement-approval.ts's toApprovalQueryRpcClient. */
export function toFileLookupClient(client: Pick<SupabaseClient, "rpc">): FileLookupClient {
  return { rpc: async (fn, args) => await client.rpc(fn, args) };
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
): Promise<BoundedList<FileSummary>> {
  // ISS-2026-238. This one does NOT use the usual fetch-one-past-the-cap truncation detector,
  // and the difference matters: this path WRITES an app.file_access_logs row per row it returns,
  // so the discarded extra row would leave an audit entry claiming somebody viewed a file they
  // were never shown. Truncation is inferred from reaching the cap instead -- conservative by
  // one row, and never dishonest about who saw what.
  const { data, error } = await client.rpc("list_files_for_tenant", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_correlation_id: correlationId,
    p_limit: BOUNDED_LIST_LIMIT,
  });

  if (error) {
    throw new FileLookupError(error.message);
  }
  if (data !== null && data !== undefined && !Array.isArray(data)) {
    throw new FileLookupError("list_files_for_tenant returned a non-array result");
  }
  return toBoundedListByCapReached(((data as unknown[] | null) ?? []).map((row) => parseFileSummary(row as Record<string, unknown>)));
}

/**
 * One record's own attachments (e.g. one employee's uploaded documents), as metadata.
 *
 * Goes through the `list_files_for_record` RPC (O1 remediation, cluster 7) rather than reading
 * app.files directly -- mirrors `listFilesForTenant` above exactly (same per-row
 * app.authorize_file_access composition and [1,200] clamp), scoped by (tenantId, recordType,
 * recordId) instead of tenantId alone.
 *
 * `actorAuthUserId` must be the calling session's own identity -- the RPC asserts it.
 */
export async function listFilesForRecord(
  client: FileLookupClient,
  tenantId: string,
  recordType: string,
  recordId: string,
  actorAuthUserId: string,
  correlationId: string | null = null,
): Promise<BoundedList<FileSummary>> {
  const { data, error } = await client.rpc("list_files_for_record", {
    p_tenant_id: tenantId,
    p_record_type: recordType,
    p_record_id: recordId,
    p_actor_auth_user_id: actorAuthUserId,
    p_correlation_id: correlationId,
    p_limit: BOUNDED_LIST_LIMIT,
  });

  if (error) {
    throw new FileLookupError(error.message);
  }
  if (data !== null && data !== undefined && !Array.isArray(data)) {
    throw new FileLookupError("list_files_for_record returned a non-array result");
  }
  return toBoundedListByCapReached(((data as unknown[] | null) ?? []).map((row) => parseFileSummary(row as Record<string, unknown>)));
}

export interface DocumentTypeLookupClient {
  rpc(fn: "list_document_types"): Promise<{ data: unknown[] | null; error: { message: string } | null }>;
}

export class DocumentTypeLookupError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "DocumentTypeLookupError";
  }
}

/** The full document-type registry -- broadly readable to any authenticated caller (app.document_types_select_all policy). */
export async function listDocumentTypes(client: DocumentTypeLookupClient): Promise<DocumentType[]> {
  const { data, error } = await client.rpc("list_document_types");

  if (error) {
    throw new DocumentTypeLookupError(error.message);
  }
  return (data ?? []).map((row) => parseDocumentType(row as Record<string, unknown>));
}
