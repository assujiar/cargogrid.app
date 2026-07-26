"use server";

/**
 * Quotation Approval Rule Server Actions (COM-153, CG-S7-COM-012). Uses the RLS-scoped
 * `authenticated` client -- app.create_quotation_approval_rule_version/
 * app.publish_quotation_approval_rule_version are granted directly to `authenticated` and
 * perform their own COM:Create/COM:Approve entitlement check in-body, the same convention
 * every prior Commercial capability's actions.ts uses (mirrors margin-rules/actions.ts,
 * COM-150).
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveCommercialAccessForRequest } from "../../../../../lib/portal/resolve-commercial-access.server.ts";
import { createQuotationApprovalRuleVersion, publishQuotationApprovalRuleVersion, QuotationApprovalMutationError } from "../../../../../server/mutations/quotation-approval.ts";

export interface QuotationApprovalRuleFormState {
  readonly error: string | null;
}

export async function createQuotationApprovalRuleVersionAction(tenantSlug: string, _prevState: QuotationApprovalRuleFormState, formData: FormData): Promise<QuotationApprovalRuleFormState> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Commercial workspace." };
  }

  const minMarginPctRaw = String(formData.get("minMarginPct") ?? "").trim();
  const maxDiscountPctRaw = String(formData.get("maxDiscountPct") ?? "").trim();
  const minValueAmountRaw = String(formData.get("minValueAmount") ?? "").trim();

  const minMarginPct = minMarginPctRaw === "" ? null : Number(minMarginPctRaw);
  const maxDiscountPct = maxDiscountPctRaw === "" ? null : Number(maxDiscountPctRaw);
  const minValueAmount = minValueAmountRaw === "" ? null : Number(minValueAmountRaw);

  if (minMarginPct === null && maxDiscountPct === null && minValueAmount === null) {
    return { error: "At least one of minimum margin %, maximum discount %, or minimum value is required." };
  }
  if ([minMarginPct, maxDiscountPct, minValueAmount].some((value) => value !== null && !Number.isFinite(value))) {
    return { error: "Every threshold you fill in must be a valid number." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await createQuotationApprovalRuleVersion(supabase, {
      tenantId: access.tenant.id,
      minMarginPct,
      maxDiscountPct,
      minValueAmount,
      actorAuthUserId: access.authUserId,
      createdBy: access.authUserId,
    });
  } catch (error) {
    if (error instanceof QuotationApprovalMutationError) {
      return { error: `Could not create quotation approval rule: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/commercial/approval-rules`);
  return { error: null };
}

/** Bound directly to a <form action={...}> -- FormData is appended automatically by the form submission but unused here (every argument this action needs is already bound). */
export async function publishQuotationApprovalRuleVersionAction(
  tenantSlug: string,
  ruleVersionId: string,
  expectedVersion: number,
  supersedesVersionId: string | null,
  _formData: FormData,
): Promise<void> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return;
  }

  const supabase = await createSupabaseServerClient();
  try {
    await publishQuotationApprovalRuleVersion(supabase, { ruleVersionId, expectedVersion, supersedesVersionId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof QuotationApprovalMutationError) {
      return;
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/commercial/approval-rules`);
}
