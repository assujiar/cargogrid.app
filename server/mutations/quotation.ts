/**
 * Quotation Builder mutation primitives (COM-151, CG-S7-COM-010). Thin, typed wrappers
 * around app.create_quotation_draft / app.clone_quotation / app.add_quotation_line /
 * app.remove_quotation_line / app.update_quotation_terms / app.submit_quotation
 * (supabase/migrations/20260724210000_create_commercial_quotation_builder.sql). Every one
 * of these RPCs returns a base app.quotations row (never the field-masked
 * app.quotations_directory projection) -- the caller already demonstrated the authority
 * to reach this point, so nothing is masked, the same posture app.calculate_margin's own
 * mutation wrapper (COM-150) already established.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateQuotationDraftInputSchema,
  CloneQuotationInputSchema,
  AddQuotationLineInputSchema,
  RemoveQuotationLineInputSchema,
  UpdateQuotationTermsInputSchema,
  SubmitQuotationInputSchema,
  toTermsJson,
  parseQuotation,
  type CreateQuotationDraftInput,
  type CloneQuotationInput,
  type AddQuotationLineInput,
  type RemoveQuotationLineInput,
  type UpdateQuotationTermsInput,
  type SubmitQuotationInput,
  type Quotation,
} from "../contracts/quotation/quotation.ts";

export type QuotationMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const QUOTATION_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "opportunity_not_found",
  "cross_tenant_opportunity_denied",
  "insufficient_privilege",
  "invalid_currency",
  "invalid_validity",
  "prospect_not_found",
  "contact_not_found",
  "quotation_not_found",
  "stale_version",
  "invalid_transition",
  "invalid_line_type",
  "description_required",
  "margin_calculation_not_found",
  "cross_tenant_margin_calculation_denied",
  "mixed_currency",
  "invalid_quantity",
  "invalid_unit_price",
  "quotation_line_not_found",
  "invalid_terms",
  "unknown_terms_key",
  "submission_not_ready",
] as const;
type KnownQuotationMutationErrorCode = (typeof QUOTATION_KNOWN_MUTATION_ERROR_CODES)[number];
export type QuotationMutationErrorCode = KnownQuotationMutationErrorCode | "mutation_failed" | "invalid_response";

export class QuotationMutationError extends Error {
  readonly code: QuotationMutationErrorCode;

  constructor(code: QuotationMutationErrorCode, message: string) {
    super(message);
    this.name = "QuotationMutationError";
    this.code = code;
  }
}

function classifyError(message: string): QuotationMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (QUOTATION_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownQuotationMutationErrorCode)
    : "mutation_failed";
}

async function callAndParseQuotation(client: QuotationMutationRpcClient, fn: string, args: Record<string, unknown>): Promise<Quotation> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new QuotationMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new QuotationMutationError("invalid_response", `${fn} returned no row`);
  }
  const row = data as Record<string, unknown>;
  return parseQuotation({ ...row, sell_masked: false });
}

/** Draft creation from an opportunity, gated by COM:Create + record access on the opportunity. Pins source_opportunity_version and copies a real customer_snapshot from the opportunity's prospect. */
export async function createQuotationDraft(client: QuotationMutationRpcClient, input: CreateQuotationDraftInput): Promise<Quotation> {
  const parsedInput = CreateQuotationDraftInputSchema.parse(input);
  return callAndParseQuotation(client, "create_quotation_draft", {
    p_tenant_id: parsedInput.tenantId,
    p_opportunity_id: parsedInput.opportunityId,
    p_currency: parsedInput.currency,
    p_validity_to: parsedInput.validityTo,
    p_contact_id: parsedInput.contactId,
    p_owner_user_id: parsedInput.ownerUserId,
    p_org_unit_id: parsedInput.orgUnitId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_created_by: parsedInput.createdBy,
  });
}

/** The "clone a prior draft with explicit origin" alternative flow -- copies header and every line into a brand-new draft, never mutates the source. */
export async function cloneQuotation(client: QuotationMutationRpcClient, input: CloneQuotationInput): Promise<Quotation> {
  const parsedInput = CloneQuotationInputSchema.parse(input);
  return callAndParseQuotation(client, "clone_quotation", {
    p_source_quotation_id: parsedInput.sourceQuotationId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_created_by: parsedInput.createdBy,
  });
}

/** Appends one typed line and returns the recalculated quotation header. Requires status=draft and matching optimistic concurrency. */
export async function addQuotationLine(client: QuotationMutationRpcClient, input: AddQuotationLineInput): Promise<Quotation> {
  const parsedInput = AddQuotationLineInputSchema.parse(input);
  return callAndParseQuotation(client, "add_quotation_line", {
    p_quotation_id: parsedInput.quotationId,
    p_expected_version: parsedInput.expectedVersion,
    p_line_type: parsedInput.lineType,
    p_description: parsedInput.description,
    p_margin_calculation_id: parsedInput.marginCalculationId,
    p_quantity: parsedInput.quantity,
    p_unit_price: parsedInput.unitPrice,
    p_discount_pct: parsedInput.discountPct,
    p_tax_pct: parsedInput.taxPct,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** Removes one line and returns the recalculated quotation header. Editing a line's numbers is done by removing and re-adding it (this checkpoint's own disclosed boundary, migration header). */
export async function removeQuotationLine(client: QuotationMutationRpcClient, input: RemoveQuotationLineInput): Promise<Quotation> {
  const parsedInput = RemoveQuotationLineInputSchema.parse(input);
  return callAndParseQuotation(client, "remove_quotation_line", {
    p_quotation_id: parsedInput.quotationId,
    p_expected_version: parsedInput.expectedVersion,
    p_line_id: parsedInput.lineId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** Updates currency/validity/terms/contact. terms keys are a real, bounded allowlist (payment_terms/incoterm/notes) enforced server-side. */
export async function updateQuotationTerms(client: QuotationMutationRpcClient, input: UpdateQuotationTermsInput): Promise<Quotation> {
  const parsedInput = UpdateQuotationTermsInputSchema.parse(input);
  return callAndParseQuotation(client, "update_quotation_terms", {
    p_quotation_id: parsedInput.quotationId,
    p_expected_version: parsedInput.expectedVersion,
    p_currency: parsedInput.currency,
    p_validity_from: parsedInput.validityFrom,
    p_validity_to: parsedInput.validityTo,
    p_terms: toTermsJson(parsedInput.terms),
    p_contact_id: parsedInput.contactId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** draft -> submitted, gated by a real readiness check that fails closed (submission_not_ready) with the exact blocking reasons. Approval routing is Prompt 153's own scope, not performed here. */
export async function submitQuotation(client: QuotationMutationRpcClient, input: SubmitQuotationInput): Promise<Quotation> {
  const parsedInput = SubmitQuotationInputSchema.parse(input);
  return callAndParseQuotation(client, "submit_quotation", {
    p_quotation_id: parsedInput.quotationId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}
