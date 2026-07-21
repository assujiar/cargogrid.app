/**
 * Master-data read queries (PLT-120, CG-S6-PLT-017). Thin, typed wrappers around
 * app.resolve_master_record / app.search_master_records
 * (supabase/migrations/20260717120000_create_master_data.sql). Both are RLS-governed,
 * plain `authenticated` grants (not SECURITY DEFINER evaluators) -- master-data lookup
 * has no pre-authentication use case, unlike PLT-117/118/119's public resolvers.
 */

import {
  ResolveMasterRecordInputSchema,
  SearchMasterRecordsInputSchema,
  parseMasterRecord,
  type MasterRecord,
  type ResolveMasterRecordInput,
  type SearchMasterRecordsInput,
} from "../contracts/master-data/master-data.ts";

export interface MasterDataQueryRpcClient {
  rpc(
    fn: "resolve_master_record" | "search_master_records",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export class MasterDataQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "MasterDataQueryError";
  }
}

/** Resolves a code or alias to its live canonical record (following any merge chain), or null if there is no match. Never ambiguous -- code/alias uniqueness guarantees at most one starting row. */
export async function resolveMasterRecord(client: MasterDataQueryRpcClient, input: ResolveMasterRecordInput): Promise<MasterRecord | null> {
  const parsedInput = ResolveMasterRecordInputSchema.parse(input);
  const { data, error } = await client.rpc("resolve_master_record", {
    p_master_type_code: parsedInput.masterTypeCode,
    p_tenant_id: parsedInput.tenantId,
    p_code_or_alias: parsedInput.codeOrAlias,
  });

  if (error) {
    throw new MasterDataQueryError(error.message);
  }

  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    return null;
  }
  return parseMasterRecord(row as Record<string, unknown>);
}

/** Keyset-paginated search by code/name substring match, scoped to one master type + tenant (or the global scope when tenantId is null). */
export async function searchMasterRecords(client: MasterDataQueryRpcClient, input: SearchMasterRecordsInput): Promise<MasterRecord[]> {
  const parsedInput = SearchMasterRecordsInputSchema.parse(input);
  const { data, error } = await client.rpc("search_master_records", {
    p_master_type_code: parsedInput.masterTypeCode,
    p_tenant_id: parsedInput.tenantId,
    p_query: parsedInput.query,
    p_limit: parsedInput.limit,
    p_after_code: parsedInput.afterCode,
  });

  if (error) {
    throw new MasterDataQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new MasterDataQueryError("search_master_records returned a non-array result");
  }
  return data.map((row) => parseMasterRecord(row as Record<string, unknown>));
}
