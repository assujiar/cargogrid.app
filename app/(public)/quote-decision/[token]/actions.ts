"use server";

/**
 * Customer decision Server Action (COM-154, CG-S7-COM-013). The one, and only, public
 * route in this repository that calls a service-role Supabase client
 * (`lib/supabase/service-role.ts`, PLT-135) -- the customer presenting this token has no
 * `auth.users` session for the RLS-scoped `authenticated` client to key off of.
 * ip_address/user_agent are read from the request's own headers (`next/headers`) --
 * best-effort, never fabricated (this migration's own disclosed limitation: no verified
 * customer identity exists yet, COM-155 has not run).
 */

import { headers } from "next/headers";
import { revalidatePath } from "next/cache";
import { createSupabaseServiceRoleClient } from "../../../../lib/supabase/service-role.ts";
import { recordQuotationCustomerDecision, QuotationAcceptanceMutationError } from "../../../../server/mutations/quotation-acceptance.ts";

export interface CustomerDecisionFormState {
  readonly error: string | null;
  readonly success: boolean;
}

export async function recordCustomerDecisionAction(rawToken: string, _prevState: CustomerDecisionFormState, formData: FormData): Promise<CustomerDecisionFormState> {
  const decision = String(formData.get("decision") ?? "");
  const decidedByName = String(formData.get("decidedByName") ?? "").trim();
  const decidedByTitle = String(formData.get("decidedByTitle") ?? "").trim() || null;
  const decidedByEmail = String(formData.get("decidedByEmail") ?? "").trim() || null;
  const reason = String(formData.get("reason") ?? "").trim() || null;

  if (decision !== "accepted" && decision !== "rejected") {
    return { error: "An explicit accept or reject decision is required.", success: false };
  }
  if (!decidedByName) {
    return { error: "Your name is required.", success: false };
  }

  const requestHeaders = await headers();
  const ipAddress = requestHeaders.get("x-forwarded-for")?.split(",")[0]?.trim() ?? null;
  const userAgent = requestHeaders.get("user-agent");

  const client = createSupabaseServiceRoleClient();
  try {
    await recordQuotationCustomerDecision(client, { rawToken, decision, decidedByName, decidedByTitle, decidedByEmail, reason, ipAddress, userAgent });
  } catch (error) {
    if (error instanceof QuotationAcceptanceMutationError) {
      return { error: `Could not record your decision: ${error.message}`, success: false };
    }
    throw error;
  }

  revalidatePath(`/quote-decision/${rawToken}`);
  return { error: null, success: true };
}
