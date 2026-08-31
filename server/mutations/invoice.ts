/**
 * Customer Invoice mutation primitives (FIN-197, CG-S9-FIN-008). Thin, typed
 * wrappers around app.prepare_finance_invoice_from_readiness /
 * app.submit_finance_invoice_for_approval / app.discard_finance_invoice_draft /
 * app.approve_finance_invoice / app.issue_finance_invoice
 * (supabase/migrations/20260729110000_create_finance_invoice.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  PrepareFinanceInvoiceFromReadinessInputSchema,
  FinanceInvoiceLifecycleInputSchema,
  DiscardFinanceInvoiceDraftInputSchema,
  IssueFinanceInvoiceInputSchema,
  parseFinanceInvoice,
  type PrepareFinanceInvoiceFromReadinessInput,
  type FinanceInvoiceLifecycleInput,
  type DiscardFinanceInvoiceDraftInput,
  type IssueFinanceInvoiceInput,
  type FinanceInvoice,
} from "../contracts/invoice/invoice.ts";
import { resolveRequestClientIp } from "../../lib/security/client-ip.ts";

export type InvoiceMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const INVOICE_KNOWN_MUTATION_ERROR_CODES = [
  // ATW-032: a fixed-amount tax rule denominated in a currency other than the document's.
  "finance_tax_rule_currency_mismatch",
  "insufficient_authority",
  "finance_invoice_handoff_not_found",
  "finance_invoice_job_order_not_found",
  "finance_invoice_revenue_snapshot_incomplete",
  "finance_invoice_unsupported_currency",
  "finance_invoice_invalid_subtotal",
  "finance_invoice_not_found",
  "finance_invoice_not_draft",
  "finance_invoice_not_submitted",
  "finance_invoice_not_approved",
  "finance_invoice_not_cancellable",
  "finance_invoice_period_not_found",
  "finance_invoice_period_not_open",
  "finance_tax_rule_missing",
  "stale_version",
] as const;
type KnownInvoiceMutationErrorCode = (typeof INVOICE_KNOWN_MUTATION_ERROR_CODES)[number];
export type InvoiceMutationErrorCode = KnownInvoiceMutationErrorCode | "mutation_failed" | "invalid_response";

export class InvoiceMutationError extends Error {
  readonly code: InvoiceMutationErrorCode;

  constructor(code: InvoiceMutationErrorCode, message: string) {
    super(message);
    this.name = "InvoiceMutationError";
    this.code = code;
  }
}

function classifyError(message: string): InvoiceMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (INVOICE_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownInvoiceMutationErrorCode) : "mutation_failed";
}

async function callAndParseInvoice(
  client: InvoiceMutationRpcClient,
  fn: "prepare_finance_invoice_from_readiness" | "submit_finance_invoice_for_approval" | "discard_finance_invoice_draft" | "approve_finance_invoice" | "issue_finance_invoice",
  args: Record<string, unknown>,
): Promise<FinanceInvoice> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new InvoiceMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new InvoiceMutationError("invalid_response", `${fn} returned no row`);
  }
  return parseFinanceInvoice(data as Record<string, unknown>);
}

/** FIN:Edit-gated, idempotent on (tenantId, billingReadinessHandoffId). Inherits the exact governed revenue snapshot; an optional tax code calls FIN-195's own calculation service. */
export async function prepareFinanceInvoiceFromReadiness(
  client: InvoiceMutationRpcClient,
  input: PrepareFinanceInvoiceFromReadinessInput,
): Promise<FinanceInvoice> {
  const parsedInput = PrepareFinanceInvoiceFromReadinessInputSchema.parse(input);
  return callAndParseInvoice(client, "prepare_finance_invoice_from_readiness", {
    p_tenant_id: parsedInput.tenantId,
    p_billing_readiness_handoff_id: parsedInput.billingReadinessHandoffId,
    p_payment_term_days: parsedInput.paymentTermDays,
    p_tax_code: parsedInput.taxCode,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** FIN:Edit-gated. draft -> submitted. */
export async function submitFinanceInvoiceForApproval(client: InvoiceMutationRpcClient, input: FinanceInvoiceLifecycleInput): Promise<FinanceInvoice> {
  const parsedInput = FinanceInvoiceLifecycleInputSchema.parse(input);
  return callAndParseInvoice(client, "submit_finance_invoice_for_approval", {
    p_invoice_id: parsedInput.invoiceId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** FIN:Edit-gated. draft/submitted -> void. Rejected once approved or issued -- a normal role cannot edit a posted invoice. */
export async function discardFinanceInvoiceDraft(client: InvoiceMutationRpcClient, input: DiscardFinanceInvoiceDraftInput): Promise<FinanceInvoice> {
  const parsedInput = DiscardFinanceInvoiceDraftInputSchema.parse(input);
  return callAndParseInvoice(client, "discard_finance_invoice_draft", {
    p_invoice_id: parsedInput.invoiceId,
    p_expected_version: parsedInput.expectedVersion,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** FIN:Approve-gated. submitted -> approved. */
export async function approveFinanceInvoice(client: InvoiceMutationRpcClient, input: FinanceInvoiceLifecycleInput): Promise<FinanceInvoice> {
  const parsedInput = FinanceInvoiceLifecycleInputSchema.parse(input);
  return callAndParseInvoice(client, "approve_finance_invoice", {
    p_invoice_id: parsedInput.invoiceId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
    // ISS-2026-302: read here rather than threaded through every caller -- a security
    // control a call site can forget to pass is not a control. Null outside a request.
    p_client_ip: await resolveRequestClientIp(),
  });
}

/** FIN:Approve-gated, period-aware, idempotent. approved -> issued; posts exactly one FIN-196 AR open item. A retried call against an already-issued invoice returns it unchanged. */
export async function issueFinanceInvoice(client: InvoiceMutationRpcClient, input: IssueFinanceInvoiceInput): Promise<FinanceInvoice> {
  const parsedInput = IssueFinanceInvoiceInputSchema.parse(input);
  return callAndParseInvoice(client, "issue_finance_invoice", {
    p_invoice_id: parsedInput.invoiceId,
    p_expected_version: parsedInput.expectedVersion,
    p_issue_date: parsedInput.issueDate,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
    // ISS-2026-302: read here rather than threaded through every caller -- a security
    // control a call site can forget to pass is not a control. Null outside a request.
    p_client_ip: await resolveRequestClientIp(),
  });
}
