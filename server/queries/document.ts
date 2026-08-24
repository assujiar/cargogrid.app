/**
 * Document and file engine read queries (PLT-128, CG-S6-PLT-025). Both reads here are
 * direct-table, RLS-governed `authenticated` grants (mirrors server/queries/field-access.ts's
 * `listUserDirectory` shape) -- app.files/app.document_types have no bespoke read RPC
 * (supabase/migrations/20260719140000_create_document_file_engine.sql's own header: this
 * capability is server-mediated for writes only, reads rely on RLS composing
 * app.can_access_record() directly). Record-type/record_id-scoped filtering beyond
 * tenant_id is left to the caller (or a future capability) -- no business-domain table
 * with a real record_type exists yet in this repository, the same disclosed scope
 * boundary every prior "no live consumer yet" capability this session recorded.
 */

import { parseFileSummary, parseDocumentType, type FileSummary, type DocumentType } from "../contracts/document/document.ts";

export interface FileLookupClient {
  from(table: "files"): {
    select(columns: string): {
      eq(column: string, value: string): Promise<{ data: unknown[] | null; error: { message: string } | null }>;
    };
  };
}

export class FileLookupError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "FileLookupError";
  }
}

/**
 * Every file row the caller's RLS grants them visibility into for this tenant (own
 * uploads, shared/record-scoped access, non-restricted classification, non-deleted
 * -- see the migration's own files_select_scoped policy for the exact composed
 * rule). Returns FileSummary, never File -- app.files no longer grants
 * `authenticated` column-level SELECT on storage_path at all (HDN-377, Storage and
 * Signed URL Audit), so this explicit column list omits it too.
 */
export async function listFilesForTenant(client: FileLookupClient, tenantId: string): Promise<FileSummary[]> {
  const { data, error } = await client
    .from("files")
    .select(
      "id, tenant_id, document_type_code, config_version_id, record_type, record_id, classification, original_filename, mime_type, size_bytes, malware_scan_status, malware_scan_completed_at, malware_scan_provider_ref, version_group_id, version_number, is_latest_version, lifecycle_status, legal_hold, legal_hold_reason, deleted_at, uploaded_by_auth_user_id, shared_org_unit_ids, customer_account_ref, idempotency_key, created_at, updated_at",
    )
    .eq("tenant_id", tenantId);

  if (error) {
    throw new FileLookupError(error.message);
  }
  return (data ?? []).map((row) => parseFileSummary(row as Record<string, unknown>));
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
