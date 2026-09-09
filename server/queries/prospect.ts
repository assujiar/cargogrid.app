/**
 * Prospect Lifecycle read queries (COM-144, CG-S7-COM-003). Thin, typed wrappers around
 * app.find_duplicate_prospects / app.get_prospect_conversion_readiness and a direct
 * RLS-scoped select for the Prospect queue/detail views -- app.prospects' own
 * prospects_select_scoped policy is the real access gate, not a second check in this layer.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  FindDuplicateProspectsInputSchema,
  FindExistingAccountsForProspectInputSchema,
  ConversionReadinessSchema,
  parseProspect,
  type FindDuplicateProspectsInput,
  type FindExistingAccountsForProspectInput,
  type Prospect,
  type ConversionReadiness,
} from "../contracts/prospect/prospect.ts";
import { parseAccount, type Account } from "../contracts/account/account.ts";

const MAX_PAGE_SIZE = 100;
const DEFAULT_PAGE_SIZE = 50;

export type ProspectQueryRpcClient = Pick<SupabaseClient, "rpc">;

export interface ListProspectsInput {
  readonly tenantId: string;
  readonly actorAuthUserId: string;
  readonly page: number;
  readonly pageSize?: number;
}

export interface ListProspectsResult {
  readonly prospects: readonly Prospect[];
  readonly totalCount: number;
  readonly page: number;
  readonly pageSize: number;
}

export class ProspectQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ProspectQueryError";
  }
}

/** Tenant-scoped duplicate-candidate search by normalized legal name/tax id. Fails closed (raises) for an actor with no active membership in tenantId. */
export async function findDuplicateProspects(client: ProspectQueryRpcClient, input: FindDuplicateProspectsInput): Promise<Prospect[]> {
  const parsedInput = FindDuplicateProspectsInputSchema.parse(input);
  const { data, error } = await client.rpc("find_duplicate_prospects", {
    p_tenant_id: parsedInput.tenantId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_legal_name: parsedInput.legalName,
    p_tax_id: parsedInput.taxId,
  });
  if (error) {
    throw new ProspectQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new ProspectQueryError("find_duplicate_prospects returned a non-array result");
  }
  return data.map((row) => parseProspect(row as Record<string, unknown>));
}

/** Reads the fixed, deterministic conversion-readiness signal for one prospect. */
export async function getProspectConversionReadiness(client: ProspectQueryRpcClient, prospectId: string): Promise<ConversionReadiness> {
  const { data, error } = await client.rpc("get_prospect_conversion_readiness", { p_prospect_id: prospectId });
  if (error) {
    throw new ProspectQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new ProspectQueryError("get_prospect_conversion_readiness returned no row");
  }
  const typedRow = row as Record<string, unknown>;
  return ConversionReadinessSchema.parse({ ready: typedRow.ready, missing: typedRow.missing });
}

/** Server-side paginated Prospect queue -- app.list_prospects reproduces prospects_select_scoped's own authority predicate exactly; this query only bounds page size and orders deterministically. */
export async function listProspects(client: ProspectQueryRpcClient, input: ListProspectsInput): Promise<ListProspectsResult> {
  const pageSize = Math.min(Math.max(Math.trunc(input.pageSize ?? DEFAULT_PAGE_SIZE), 1), MAX_PAGE_SIZE);
  const page = Math.max(Math.trunc(input.page), 1);

  const { data, error } = await client.rpc("list_prospects", {
    p_tenant_id: input.tenantId,
    p_actor_auth_user_id: input.actorAuthUserId,
    p_page: page,
    p_page_size: pageSize,
  });

  if (error) {
    throw new ProspectQueryError(error.message);
  }

  const rows = (data ?? []) as Record<string, unknown>[];
  const totalCount = rows.length > 0 ? Number(rows[0]!.total_count) : 0;

  return {
    prospects: rows.map((row) => parseProspect(row)),
    totalCount,
    page,
    pageSize,
  };
}

/** A single prospect by id, for the Prospect Detail view -- app.get_prospect_by_id returns null (never an error) when denied/no-match yields zero rows. */
export async function getProspectById(client: ProspectQueryRpcClient, prospectId: string, actorAuthUserId: string): Promise<Prospect | null> {
  const { data, error } = await client.rpc("get_prospect_by_id", {
    p_prospect_id: prospectId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new ProspectQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row) {
    return null;
  }
  return parseProspect(row as Record<string, unknown>);
}

/** COM-161: reuses app.find_duplicate_accounts' own legal_name+tax_id fingerprint match, surfaced at Prospect stage. Advisory only, never blocks qualification. Fails closed (raises) for an actor with no active membership in tenantId. */
export async function findExistingAccountsForProspect(client: ProspectQueryRpcClient, input: FindExistingAccountsForProspectInput): Promise<Account[]> {
  const parsedInput = FindExistingAccountsForProspectInputSchema.parse(input);
  const { data, error } = await client.rpc("find_existing_accounts_for_prospect", {
    p_tenant_id: parsedInput.tenantId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_prospect_id: parsedInput.prospectId,
  });
  if (error) {
    throw new ProspectQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new ProspectQueryError("find_existing_accounts_for_prospect returned a non-array result");
  }
  return data.map((row) => parseAccount(row as Record<string, unknown>));
}
