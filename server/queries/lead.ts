/**
 * Lead Management read queries (COM-143, CG-S7-COM-002). Thin, typed wrappers around
 * app.find_duplicate_leads (supabase/migrations/20260723090000_create_commercial_lead_management.sql)
 * and a direct RLS-scoped select for the Lead List/Detail views -- app.leads' own
 * leads_select_scoped policy (composing app.can_access_record + org-unit ancestry) is the
 * real access gate, not a second check in this layer. Mirrors server/queries/portal-users.ts's
 * own `Pick<SupabaseClient, "from">` convention rather than a hand-rolled table-client shape.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { FindDuplicateLeadsInputSchema, parseLead, type FindDuplicateLeadsInput, type Lead } from "../contracts/lead/lead.ts";

const MAX_PAGE_SIZE = 100;
const DEFAULT_PAGE_SIZE = 50;

/** `Pick<SupabaseClient, "rpc">` -- see server/mutations/lead.ts's own header for why this must structurally match the real client rather than a hand-rolled shape. */
export type LeadQueryRpcClient = Pick<SupabaseClient, "rpc">;

export interface ListLeadsInput {
  readonly tenantId: string;
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

/** Server-side paginated Lead List -- RLS (leads_select_scoped) is the real scope gate; this query only bounds page size and orders deterministically. Never loads an entire tenant's leads into the browser. */
export async function listLeads(client: Pick<SupabaseClient, "from">, input: ListLeadsInput): Promise<ListLeadsResult> {
  const pageSize = Math.min(Math.max(Math.trunc(input.pageSize ?? DEFAULT_PAGE_SIZE), 1), MAX_PAGE_SIZE);
  const page = Math.max(Math.trunc(input.page), 1);
  const from = (page - 1) * pageSize;
  const to = from + pageSize - 1;

  const { data, error, count } = await client
    .from("leads")
    .select("*", { count: "exact" })
    .eq("tenant_id", input.tenantId)
    .order("last_activity_at", { ascending: false })
    .range(from, to);

  if (error) {
    throw new LeadQueryError(error.message);
  }

  return {
    leads: (data ?? []).map((row: Record<string, unknown>) => parseLead(row)),
    totalCount: count ?? 0,
    page,
    pageSize,
  };
}

/** A single lead by id, for the Lead Detail view -- RLS (leads_select_scoped) returns zero rows, not an error, when the caller lacks access; the caller must treat null as "not found or not accessible" (never distinguished, per the same "no confirming/denying beyond what the viewer is already entitled to know" discipline PLT-135's own guard uses). */
export async function getLeadById(client: Pick<SupabaseClient, "from">, leadId: string): Promise<Lead | null> {
  const { data, error } = await client.from("leads").select("*").eq("id", leadId).maybeSingle();
  if (error) {
    throw new LeadQueryError(error.message);
  }
  if (!data) {
    return null;
  }
  return parseLead(data as Record<string, unknown>);
}
