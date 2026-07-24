/**
 * Customer Acceptance read queries (COM-154, CG-S7-COM-013). `listQuotationAcceptanceTokens`
 * is the authenticated, RLS-scoped internal read (never selects token_hash -- the
 * migration's own column-level grant excludes it entirely). `getQuotationForCustomerDecision`
 * is the public, unauthenticated read -- called with a service-role client
 * (`lib/supabase/service-role.ts`, PLT-135) from the public `/quote-decision/[token]` route,
 * since the caller has no `auth.users` session for RLS to key off of.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  GetQuotationForCustomerDecisionInputSchema,
  parseQuotationAcceptanceToken,
  parseCustomerQuotationView,
  type GetQuotationForCustomerDecisionInput,
  type QuotationAcceptanceToken,
  type CustomerQuotationView,
} from "../contracts/quotation/quotation-acceptance.ts";

export type QuotationAcceptanceQueryTableClient = Pick<SupabaseClient, "from">;
export type QuotationAcceptanceQueryRpcClient = Pick<SupabaseClient, "rpc">;

export class QuotationAcceptanceQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "QuotationAcceptanceQueryError";
  }
}

/** Every acceptance token for one quotation, most recently sent first -- record-scoped via RLS (app.quotation_acceptance_tokens_select_scoped), token_hash never selected. */
export async function listQuotationAcceptanceTokens(client: QuotationAcceptanceQueryTableClient, quotationId: string): Promise<QuotationAcceptanceToken[]> {
  const { data, error } = await client
    .from("quotation_acceptance_tokens")
    .select("id, tenant_id, quotation_id, status, channel, recipient_contact_id, recipient_email, expires_at, sent_at, sent_by, revoked_at, revoked_reason, consumed_at, created_by, created_at")
    .eq("quotation_id", quotationId)
    .order("sent_at", { ascending: false });
  if (error) {
    throw new QuotationAcceptanceQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseQuotationAcceptanceToken(row));
}

/** The public token-consumption read. Never raises for an expired/revoked/consumed token -- the caller renders the returned tokenStatus as a real UI state (Prompt 154 §23); only a genuinely unknown token raises. */
export async function getQuotationForCustomerDecision(client: QuotationAcceptanceQueryRpcClient, input: GetQuotationForCustomerDecisionInput): Promise<CustomerQuotationView> {
  const parsedInput = GetQuotationForCustomerDecisionInputSchema.parse(input);
  const { data, error } = await client.rpc("get_quotation_for_customer_decision", { p_raw_token: parsedInput.rawToken });
  if (error) {
    throw new QuotationAcceptanceQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new QuotationAcceptanceQueryError("get_quotation_for_customer_decision returned no row");
  }
  return parseCustomerQuotationView(row as Record<string, unknown>);
}
