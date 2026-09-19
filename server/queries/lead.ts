/**
 * Lead Management read queries (COM-143, CG-S7-COM-002). Thin, typed wrappers around
 * app.find_duplicate_leads (supabase/migrations/20260723090000_create_commercial_lead_management.sql)
 * and a direct RLS-scoped select for the Lead List/Detail views -- app.leads' own
 * leads_select_scoped policy (composing app.can_access_record + org-unit ancestry) is the
 * real access gate, not a second check in this layer. Mirrors server/queries/portal-users.ts's
 * own `Pick<SupabaseClient, "from">` convention rather than a hand-rolled table-client shape.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  FindDuplicateLeadsInputSchema,
  FindExistingAccountsForLeadInputSchema,
  parseLead,
  type FindDuplicateLeadsInput,
  type FindExistingAccountsForLeadInput,
  type Lead,
} from "../contracts/lead/lead.ts";
import { parseAccount, type Account } from "../contracts/account/account.ts";

const MAX_PAGE_SIZE = 100;
const DEFAULT_PAGE_SIZE = 50;

/** `Pick<SupabaseClient, "rpc">` -- see server/mutations/lead.ts's own header for why this must structurally match the real client rather than a hand-rolled shape. */
export type LeadQueryRpcClient = Pick<SupabaseClient, "rpc">;

export interface ListLeadsInput {
  readonly tenantId: string;
  readonly actorAuthUserId: string;
  readonly page: number;
  readonly pageSize?: number;
}

export interface ListLeadsResult {
  readonly leads: readonly Lead[];
  readonly totalCount: number;
  readonly page: number;
  readonly pageSize: number;
}

export class LeadQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "LeadQueryError";
  }
}

/** Tenant-scoped duplicate-candidate search by normalized email/phone/company. Fails closed (raises) for an actor with no active membership in tenantId -- never a silent empty result that could be mistaken for "no duplicates." */
export async function findDuplicateLeads(client: LeadQueryRpcClient, input: FindDuplicateLeadsInput): Promise<Lead[]> {
  const parsedInput = FindDuplicateLeadsInputSchema.parse(input);
  const { data, error } = await client.rpc("find_duplicate_leads", {
    p_tenant_id: parsedInput.tenantId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_email: parsedInput.email,
    p_phone: parsedInput.phone,
    p_company_name: parsedInput.companyName,
  });
  if (error) {
    throw new LeadQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new LeadQueryError("find_duplicate_leads returned a non-array result");
  }
  return data.map((row) => parseLead(row as Record<string, unknown>));
}

/** Server-side paginated Lead List -- app.list_leads reproduces leads_select_scoped's own authority predicate exactly; this query only bounds page size and orders deterministically. Never loads an entire tenant's leads into the browser. */
export async function listLeads(client: LeadQueryRpcClient, input: ListLeadsInput): Promise<ListLeadsResult> {
  const pageSize = Math.min(Math.max(Math.trunc(input.pageSize ?? DEFAULT_PAGE_SIZE), 1), MAX_PAGE_SIZE);
  const page = Math.max(Math.trunc(input.page), 1);

  const { data, error } = await client.rpc("list_leads", {
    p_tenant_id: input.tenantId,
    p_actor_auth_user_id: input.actorAuthUserId,
    p_page: page,
    p_page_size: pageSize,
  });

  if (error) {
    throw new LeadQueryError(error.message);
  }

  const rows = (data ?? []) as Record<string, unknown>[];
  const totalCount = rows.length > 0 ? Number(rows[0]!.total_count) : 0;

  return {
    leads: rows.map((row) => parseLead(row)),
    totalCount,
    page,
    pageSize,
  };
}

/** A single lead by id, for the Lead Detail view -- app.get_lead_by_id returns zero rows, not an error, when the caller lacks access; the caller must treat null as "not found or not accessible" (never distinguished, per the same "no confirming/denying beyond what the viewer is already entitled to know" discipline PLT-135's own guard uses). */
export async function getLeadById(client: LeadQueryRpcClient, leadId: string, actorAuthUserId: string): Promise<Lead | null> {
  const { data, error } = await client.rpc("get_lead_by_id", {
    p_lead_id: leadId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new LeadQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row) {
    return null;
  }
  return parseLead(row as Record<string, unknown>);
}

/** COM-161: "is this Lead's company already a known Account" -- advisory only, never blocks capture. Fails closed (raises) for an actor with no active membership in tenantId. */
export async function findExistingAccountsForLead(client: LeadQueryRpcClient, input: FindExistingAccountsForLeadInput): Promise<Account[]> {
  const parsedInput = FindExistingAccountsForLeadInputSchema.parse(input);
  const { data, error } = await client.rpc("find_existing_accounts_for_lead", {
    p_tenant_id: parsedInput.tenantId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_lead_id: parsedInput.leadId,
  });
  if (error) {
    throw new LeadQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new LeadQueryError("find_existing_accounts_for_lead returned a non-array result");
  }
  return data.map((row) => parseAccount(row as Record<string, unknown>));
}
