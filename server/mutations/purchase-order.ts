/**
 * Purchase Order mutation primitives (PRC-260, CG-S11-PRC-011). Thin, typed wrappers
 * around the write RPCs supabase/migrations/20260730680000_create_procurement_purchase_
 * order.sql adds -- the same KNOWN_MUTATION_ERROR_CODES / classifyError / callRpc shape
 * server/mutations/vendor-comparison.ts already establishes for this checkpoint's own
 * template.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  DraftPurchaseOrderFromSelectionInputSchema,
  SubmitPurchaseOrderForApprovalInputSchema,
  IssuePurchaseOrderInputSchema,
  AcknowledgePurchaseOrderInputSchema,
  RecordPurchaseOrderFulfillmentStatusInputSchema,
  AmendPurchaseOrderInputSchema,
  CancelPurchaseOrderInputSchema,
  parsePurchaseOrder,
  type DraftPurchaseOrderFromSelectionInput,
  type SubmitPurchaseOrderForApprovalInput,
  type IssuePurchaseOrderInput,
  type AcknowledgePurchaseOrderInput,
  type RecordPurchaseOrderFulfillmentStatusInput,
  type AmendPurchaseOrderInput,
  type CancelPurchaseOrderInput,
  type PurchaseOrder,
} from "../contracts/purchase-order/purchase-order.ts";

export type PurchaseOrderMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const PURCHASE_ORDER_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "purchase_order_not_found",
  "vendor_comparison_not_found",
  "vendor_comparison_offer_not_found",
  "tenant_mismatch",
  "invalid_source_status",
  "selection_approval_pending",
  "no_selected_offer",
  "excluded_offer",
  "offer_not_normalized",
  "vendor_not_active",
  "tax_rule_currency_mismatch",
  "duplicate_issue",
  "purchase_order_approval_pending",
  "fulfillment_in_progress",
  "invalid_fulfillment_status",
  "invalid_fulfillment_transition",
  "invalid_status_filter",
  "idempotency_key_required",
  "idempotency_key_conflict",
  "reason_required",
  "stale_version",
  "invalid_transition",
  // Batch 260 review (C-21 fix, defense in depth): app.cancel_purchase_order's own
  // nested app.cancel_approval_request (PLT-123) call can now surface this typed code
  // to a caller who raced a concurrent decide_purchase_order_approval_step that
  // finalized the bound approval request between this function's own unlocked initial
  // read and the nested call -- a narrow, self-consistent outcome of the C-21 lock-order
  // fix, never a raw/opaque error.
  "approval_request_not_pending",
] as const;
type KnownPurchaseOrderMutationErrorCode = (typeof PURCHASE_ORDER_KNOWN_MUTATION_ERROR_CODES)[number];
export type PurchaseOrderMutationErrorCode = KnownPurchaseOrderMutationErrorCode | "mutation_failed" | "invalid_response";

export class PurchaseOrderMutationError extends Error {
  readonly code: PurchaseOrderMutationErrorCode;

  constructor(code: PurchaseOrderMutationErrorCode, message: string) {
    super(message);
    this.name = "PurchaseOrderMutationError";
    this.code = code;
  }
}

function classifyError(message: string): PurchaseOrderMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (PURCHASE_ORDER_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownPurchaseOrderMutationErrorCode) : "mutation_failed";
}

async function callRpc(client: PurchaseOrderMutationRpcClient, fn: string, args: Record<string, unknown>): Promise<unknown> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new PurchaseOrderMutationError(classifyError(error.message), error.message);
  }
  return data;
}

function requirePurchaseOrderRow(data: unknown, fn: string): PurchaseOrder {
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new PurchaseOrderMutationError("invalid_response", `${fn} returned no row`);
  }
  return parsePurchaseOrder(row as Record<string, unknown>);
}

/** Creates (or, on idempotency-key replay, returns the existing) a draft purchase order from an approved, submitted vendor comparison selection. status=draft. */
export async function draftPurchaseOrderFromSelection(client: PurchaseOrderMutationRpcClient, input: DraftPurchaseOrderFromSelectionInput): Promise<PurchaseOrder> {
  const parsed = DraftPurchaseOrderFromSelectionInputSchema.parse(input);
  const data = await callRpc(client, "draft_purchase_order_from_selection", {
    p_tenant_id: parsed.tenantId,
    p_comparison_id: parsed.comparisonId,
    p_idempotency_key: parsed.idempotencyKey,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
    p_tax_code: parsed.taxCode,
    p_payment_term_days: parsed.paymentTermDays,
    p_expected_delivery_date: parsed.expectedDeliveryDate,
    p_service_period_start: parsed.servicePeriodStart,
    p_service_period_end: parsed.servicePeriodEnd,
    p_commercial_terms: parsed.commercialTerms,
    p_notes: parsed.notes,
  });
  return requirePurchaseOrderRow(data, "draft_purchase_order_from_selection");
}

/** draft -> submitted. Routes for platform-engine governance approval when a published purchase_order policy is crossed. */
export async function submitPurchaseOrderForApproval(client: PurchaseOrderMutationRpcClient, input: SubmitPurchaseOrderForApprovalInput): Promise<PurchaseOrder> {
  const parsed = SubmitPurchaseOrderForApprovalInputSchema.parse(input);
  const data = await callRpc(client, "submit_purchase_order_for_approval", {
    p_purchase_order_id: parsed.purchaseOrderId,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requirePurchaseOrderRow(data, "submit_purchase_order_for_approval");
}

/** submitted -> issued. Requires approvalStatus in (approved, not_required). */
export async function issuePurchaseOrder(client: PurchaseOrderMutationRpcClient, input: IssuePurchaseOrderInput): Promise<PurchaseOrder> {
  const parsed = IssuePurchaseOrderInputSchema.parse(input);
  const data = await callRpc(client, "issue_purchase_order", {
    p_purchase_order_id: parsed.purchaseOrderId,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requirePurchaseOrderRow(data, "issue_purchase_order");
}

/** issued -> acknowledged. Internal capture of the vendor's own acknowledgement, mandatory note. */
export async function acknowledgePurchaseOrder(client: PurchaseOrderMutationRpcClient, input: AcknowledgePurchaseOrderInput): Promise<PurchaseOrder> {
  const parsed = AcknowledgePurchaseOrderInputSchema.parse(input);
  const data = await callRpc(client, "acknowledge_purchase_order", {
    p_purchase_order_id: parsed.purchaseOrderId,
    p_expected_version: parsed.expectedVersion,
    p_acknowledgement_note: parsed.acknowledgementNote,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requirePurchaseOrderRow(data, "acknowledge_purchase_order");
}

/** Monotonic not_started -> partial -> fulfilled, mandatory fulfillmentReference (canonical Operations shipment/service evidence). Only while issued|acknowledged. */
export async function recordPurchaseOrderFulfillmentStatus(client: PurchaseOrderMutationRpcClient, input: RecordPurchaseOrderFulfillmentStatusInput): Promise<PurchaseOrder> {
  const parsed = RecordPurchaseOrderFulfillmentStatusInputSchema.parse(input);
  const data = await callRpc(client, "record_purchase_order_fulfillment_status", {
    p_purchase_order_id: parsed.purchaseOrderId,
    p_expected_version: parsed.expectedVersion,
    p_fulfillment_status: parsed.fulfillmentStatus,
    p_fulfillment_reference: parsed.fulfillmentReference,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requirePurchaseOrderRow(data, "record_purchase_order_fulfillment_status");
}

/** Only from issued|acknowledged (blocked once fulfillment has begun), mandatory reason. Marks the current version superseded and creates a new draft version, which must independently pass back through submit + issue. Idempotent on (tenant_id, idempotencyKey). */
export async function amendPurchaseOrder(client: PurchaseOrderMutationRpcClient, input: AmendPurchaseOrderInput): Promise<PurchaseOrder> {
  const parsed = AmendPurchaseOrderInputSchema.parse(input);
  const data = await callRpc(client, "amend_purchase_order", {
    p_purchase_order_id: parsed.purchaseOrderId,
    p_expected_version: parsed.expectedVersion,
    p_reason: parsed.reason,
    p_idempotency_key: parsed.idempotencyKey,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
    p_payment_term_days: parsed.paymentTermDays,
    p_expected_delivery_date: parsed.expectedDeliveryDate,
    p_service_period_start: parsed.servicePeriodStart,
    p_service_period_end: parsed.servicePeriodEnd,
    p_commercial_terms: parsed.commercialTerms,
    p_notes: parsed.notes,
  });
  return requirePurchaseOrderRow(data, "amend_purchase_order");
}

/** draft|submitted|issued|acknowledged -> cancelled. Mandatory reason. Cancel-eligible only (blocked once fulfillment has begun on an issued/acknowledged PO). */
export async function cancelPurchaseOrder(client: PurchaseOrderMutationRpcClient, input: CancelPurchaseOrderInput): Promise<PurchaseOrder> {
  const parsed = CancelPurchaseOrderInputSchema.parse(input);
  const data = await callRpc(client, "cancel_purchase_order", {
    p_purchase_order_id: parsed.purchaseOrderId,
    p_expected_version: parsed.expectedVersion,
    p_reason: parsed.reason,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requirePurchaseOrderRow(data, "cancel_purchase_order");
}
