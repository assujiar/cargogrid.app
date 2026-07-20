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

import { parseFile, parseDocumentType, type File, type DocumentType } from "../contracts/document/document.ts";

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

/** Every file row the caller's RLS grants them visibility into for this tenant (own uploads, shared/record-scoped access, non-restricted classification, non-deleted -- see the migration's own files_select_scoped policy for the exact composed rule). */
export async function listFilesForTenant(client: FileLookupClient, tenantId: string): Promise<File[]> {
  const { data, error } = await client.from("files").select("*").eq("tenant_id", tenantId);

  if (error) {
    throw new FileLookupError(error.message);
  }
  return (data ?? []).map((row) => parseFile(row as Record<string, unknown>));
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
