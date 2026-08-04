/**
 * Warehouse Billing Events mutation primitives (ATW-022, CG-S10-ATW-022). Thin,
 * typed wrappers around app.create_warehouse_billing_rate_component/
 * app.get_effective_warehouse_billing_rate/app.capture_warehouse_billing_event/
 * app.calculate_warehouse_billing_event/app.recalculate_warehouse_billing_event/
 * app.hold_warehouse_billing_event/app.release_warehouse_billing_event_hold/
 * app.review_warehouse_billing_event/app.approve_warehouse_billing_event/
 * app.handoff_warehouse_billing_event/app.record_warehouse_billing_reconciliation_
 * outcome/app.correct_warehouse_billing_event/app.reverse_warehouse_billing_event/
 * app.preview_warehouse_billing_calculation
 * (supabase/migrations/20260730300000_create_advanced_tms_warehouse_billing_events.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateWarehouseBillingRateComponentInputSchema,
  GetEffectiveWarehouseBillingRateInputSchema,
  CaptureWarehouseBillingEventInputSchema,
  CalculateWarehouseBillingEventInputSchema,
  RecalculateWarehouseBillingEventInputSchema,
  HoldWarehouseBillingEventInputSchema,
  ReleaseWarehouseBillingEventHoldInputSchema,
  ReviewWarehouseBillingEventInputSchema,
  ApproveWarehouseBillingEventInputSchema,
  HandoffWarehouseBillingEventInputSchema,
  RecordWarehouseBillingReconciliationOutcomeInputSchema,
  CorrectWarehouseBillingEventInputSchema,
  ReverseWarehouseBillingEventInputSchema,
  PreviewWarehouseBillingCalculationInputSchema,
  parseWarehouseBillingRateComponent,
  parseWarehouseBillingEvent,
  parseWarehouseBillingHandoff,
  parseWarehouseBillingCalculationPreview,
  type CreateWarehouseBillingRateComponentInput,
  type GetEffectiveWarehouseBillingRateInput,
  type CaptureWarehouseBillingEventInput,
  type CalculateWarehouseBillingEventInput,
  type RecalculateWarehouseBillingEventInput,
  type HoldWarehouseBillingEventInput,
  type ReleaseWarehouseBillingEventHoldInput,
  type ReviewWarehouseBillingEventInput,
  type ApproveWarehouseBillingEventInput,
  type HandoffWarehouseBillingEventInput,
  type RecordWarehouseBillingReconciliationOutcomeInput,
  type CorrectWarehouseBillingEventInput,
  type ReverseWarehouseBillingEventInput,
  type PreviewWarehouseBillingCalculationInput,
  type WarehouseBillingRateComponent,
  type WarehouseBillingEvent,
  type WarehouseBillingHandoff,
  type WarehouseBillingCalculationPreview,
} from "../contracts/warehouse-billing/warehouse-billing.ts";

export type WarehouseBillingMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const WAREHOUSE_BILLING_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "contract_not_found",
  "rate_component_requires_draft_contract",
  "warehouse_not_found",
  "invalid_activity_type",
  "invalid_rate_basis",
  "invalid_unit_rate",
  "invalid_minimum_amount",
  "invalid_currency",
  "invalid_rate_uom_for_basis",
  "invalid_uom_code",
  "invalid_tier_schedule",
  "invalid_time_basis_unit",
  "rate_component_scope_conflict",
  "no_effective_rate",
  "invalid_idempotency_key",
  "invalid_source_type",
  "invalid_quantity",
  "invalid_activity_date",
  "idempotency_key_conflict",
  "source_id_required",
  "source_not_found",
  "source_not_eligible",
  "source_mismatch",
  "source_already_captured",
  "manual_reason_required",
  "warehouse_billing_event_not_found",
  "already_calculated",
  "stale_version",
  "invalid_transition",
  "invalid_reason",
  "self_approval_not_allowed",
  "warehouse_billing_handoff_not_found",
  "invalid_status",
  "invalid_note",
  "invalid_actor_label",
  "reconciliation_outcome_conflict",
  "already_corrected",
  "already_reversed",
] as const;
type KnownWarehouseBillingMutationErrorCode = (typeof WAREHOUSE_BILLING_KNOWN_MUTATION_ERROR_CODES)[number];
export type WarehouseBillingMutationErrorCode = KnownWarehouseBillingMutationErrorCode | "mutation_failed" | "invalid_response";

export class WarehouseBillingMutationError extends Error {
  readonly code: WarehouseBillingMutationErrorCode;

  constructor(code: WarehouseBillingMutationErrorCode, message: string) {
    super(message);
    this.name = "WarehouseBillingMutationError";
    this.code = code;
  }
}

function classifyError(message: string): WarehouseBillingMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (WAREHOUSE_BILLING_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownWarehouseBillingMutationErrorCode) : "mutation_failed";
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

function parseRateComponentResponse(data: unknown, rpcName: string): WarehouseBillingRateComponent {
  const row = firstRow(data);
  if (!row) {
    throw new WarehouseBillingMutationError("invalid_response", `${rpcName} returned no row`);
  }
  return parseWarehouseBillingRateComponent(row);
}

function parseEventResponse(data: unknown, rpcName: string): WarehouseBillingEvent {
  const row = firstRow(data);
  if (!row) {
    throw new WarehouseBillingMutationError("invalid_response", `${rpcName} returned no row`);
  }
  return parseWarehouseBillingEvent(row);
}

function parseHandoffResponse(data: unknown, rpcName: string): WarehouseBillingHandoff {
  const row = firstRow(data);
  if (!row) {
    throw new WarehouseBillingMutationError("invalid_response", `${rpcName} returned no row`);
  }
  return parseWarehouseBillingHandoff(row);
}

/** COM:Edit-gated -- extends an EXISTING Commercial contract's own pricing configuration. Requires the contract to be status=draft. */
export async function createWarehouseBillingRateComponent(client: WarehouseBillingMutationRpcClient, input: CreateWarehouseBillingRateComponentInput): Promise<WarehouseBillingRateComponent> {
  const parsedInput = CreateWarehouseBillingRateComponentInputSchema.parse(input);
  const { data, error } = await client.rpc("create_warehouse_billing_rate_component", {
    p_contract_id: parsedInput.contractId,
    p_warehouse_id: parsedInput.warehouseId ?? null,
    p_activity_type: parsedInput.activityType,
    p_rate_basis: parsedInput.rateBasis,
    p_rate_uom_code: parsedInput.rateUomCode ?? null,
    p_unit_rate: parsedInput.unitRate,
    p_minimum_amount: parsedInput.minimumAmount ?? null,
    p_currency: parsedInput.currency,
    p_tier_schedule: parsedInput.tierSchedule ?? null,
    p_time_basis_unit: parsedInput.timeBasisUnit ?? null,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WarehouseBillingMutationError(classifyError(error.message), error.message);
  }
  return parseRateComponentResponse(data, "create_warehouse_billing_rate_component");
}

/** OPS:View + record-scope. Raises no_effective_rate on zero match -- never a silent zero/wrong rate. */
export async function getEffectiveWarehouseBillingRate(client: WarehouseBillingMutationRpcClient, input: GetEffectiveWarehouseBillingRateInput): Promise<WarehouseBillingRateComponent> {
  const parsedInput = GetEffectiveWarehouseBillingRateInputSchema.parse(input);
  const { data, error } = await client.rpc("get_effective_warehouse_billing_rate", {
    p_tenant_id: parsedInput.tenantId,
    p_account_id: parsedInput.accountId,
    p_warehouse_id: parsedInput.warehouseId,
    p_activity_type: parsedInput.activityType,
    p_as_of: parsedInput.asOf,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
  });
  if (error) {
    throw new WarehouseBillingMutationError(classifyError(error.message), error.message);
  }
  return parseRateComponentResponse(data, "get_effective_warehouse_billing_rate");
}

/** OPS:Create for a real dispatch source_type; OPS:Override for source_type='manual'. Idempotent on (tenantId, idempotencyKey). */
export async function captureWarehouseBillingEvent(client: WarehouseBillingMutationRpcClient, input: CaptureWarehouseBillingEventInput): Promise<WarehouseBillingEvent> {
  const parsedInput = CaptureWarehouseBillingEventInputSchema.parse(input);
  const { data, error } = await client.rpc("capture_warehouse_billing_event", {
    p_tenant_id: parsedInput.tenantId,
    p_warehouse_id: parsedInput.warehouseId,
    p_owner_account_id: parsedInput.ownerAccountId,
    p_activity_type: parsedInput.activityType,
    p_source_type: parsedInput.sourceType,
    p_source_id: parsedInput.sourceId ?? null,
    p_quantity: parsedInput.quantity,
    p_uom_code: parsedInput.uomCode,
    p_activity_date: parsedInput.activityDate,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_correction_reason: parsedInput.correctionReason ?? null,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WarehouseBillingMutationError(classifyError(error.message), error.message);
  }
  return parseEventResponse(data, "capture_warehouse_billing_event");
}

/** OPS:Edit + record/owner-scope. status must be draft. status -> pending_review. */
export async function calculateWarehouseBillingEvent(client: WarehouseBillingMutationRpcClient, input: CalculateWarehouseBillingEventInput): Promise<WarehouseBillingEvent> {
  const parsedInput = CalculateWarehouseBillingEventInputSchema.parse(input);
  const { data, error } = await client.rpc("calculate_warehouse_billing_event", {
    p_event_id: parsedInput.eventId,
    p_expected_version: parsedInput.expectedVersion,
    p_tax_code: parsedInput.taxCode ?? null,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WarehouseBillingMutationError(classifyError(error.message), error.message);
  }
  return parseEventResponse(data, "calculate_warehouse_billing_event");
}

/** OPS:Override, reason mandatory. status must be pending_review or reviewed. Always resets to pending_review. */
export async function recalculateWarehouseBillingEvent(client: WarehouseBillingMutationRpcClient, input: RecalculateWarehouseBillingEventInput): Promise<WarehouseBillingEvent> {
  const parsedInput = RecalculateWarehouseBillingEventInputSchema.parse(input);
  const { data, error } = await client.rpc("recalculate_warehouse_billing_event", {
    p_event_id: parsedInput.eventId,
    p_expected_version: parsedInput.expectedVersion,
    p_reason: parsedInput.reason,
    p_tax_code: parsedInput.taxCode ?? null,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WarehouseBillingMutationError(classifyError(error.message), error.message);
  }
  return parseEventResponse(data, "recalculate_warehouse_billing_event");
}

/** OPS:Override. status must be pending_review or reviewed -> on_hold. Reason required. */
export async function holdWarehouseBillingEvent(client: WarehouseBillingMutationRpcClient, input: HoldWarehouseBillingEventInput): Promise<WarehouseBillingEvent> {
  const parsedInput = HoldWarehouseBillingEventInputSchema.parse(input);
  const { data, error } = await client.rpc("hold_warehouse_billing_event", {
    p_event_id: parsedInput.eventId,
    p_reason: parsedInput.reason,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WarehouseBillingMutationError(classifyError(error.message), error.message);
  }
  return parseEventResponse(data, "hold_warehouse_billing_event");
}

/** OPS:Override. status must be on_hold -> pending_review (never directly to reviewed/approved). */
export async function releaseWarehouseBillingEventHold(client: WarehouseBillingMutationRpcClient, input: ReleaseWarehouseBillingEventHoldInput): Promise<WarehouseBillingEvent> {
  const parsedInput = ReleaseWarehouseBillingEventHoldInputSchema.parse(input);
  const { data, error } = await client.rpc("release_warehouse_billing_event_hold", {
    p_event_id: parsedInput.eventId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WarehouseBillingMutationError(classifyError(error.message), error.message);
  }
  return parseEventResponse(data, "release_warehouse_billing_event_hold");
}

/** OPS:Edit. status must be pending_review -> reviewed. */
export async function reviewWarehouseBillingEvent(client: WarehouseBillingMutationRpcClient, input: ReviewWarehouseBillingEventInput): Promise<WarehouseBillingEvent> {
  const parsedInput = ReviewWarehouseBillingEventInputSchema.parse(input);
  const { data, error } = await client.rpc("review_warehouse_billing_event", {
    p_event_id: parsedInput.eventId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WarehouseBillingMutationError(classifyError(error.message), error.message);
  }
  return parseEventResponse(data, "review_warehouse_billing_event");
}

/** OPS:Override (a governed release-to-Finance decision). status must be reviewed -> approved. Rejects self_approval_not_allowed if the actor also reviewed it. */
export async function approveWarehouseBillingEvent(client: WarehouseBillingMutationRpcClient, input: ApproveWarehouseBillingEventInput): Promise<WarehouseBillingEvent> {
  const parsedInput = ApproveWarehouseBillingEventInputSchema.parse(input);
  const { data, error } = await client.rpc("approve_warehouse_billing_event", {
    p_event_id: parsedInput.eventId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WarehouseBillingMutationError(classifyError(error.message), error.message);
  }
  return parseEventResponse(data, "approve_warehouse_billing_event");
}

/** OPS:Edit (release-authority already spent at approve). status must be approved. Idempotent on (tenantId via the event's own tenant, idempotencyKey). */
export async function handoffWarehouseBillingEvent(client: WarehouseBillingMutationRpcClient, input: HandoffWarehouseBillingEventInput): Promise<WarehouseBillingHandoff> {
  const parsedInput = HandoffWarehouseBillingEventInputSchema.parse(input);
  const { data, error } = await client.rpc("handoff_warehouse_billing_event", {
    p_event_id: parsedInput.eventId,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WarehouseBillingMutationError(classifyError(error.message), error.message);
  }
  return parseHandoffResponse(data, "handoff_warehouse_billing_event");
}

/**
 * service_role only -- a Finance-side worker callback called from server-side/worker
 * code paths only, never a browser client. No authenticated grant exists on the
 * underlying RPC at all (mirrors app.record_label_print_outcome's exact precedent,
 * ATW-021). Idempotent on a same-outcome replay; rejects a conflicting second outcome.
 */
export async function recordWarehouseBillingReconciliationOutcome(
  client: WarehouseBillingMutationRpcClient,
  input: RecordWarehouseBillingReconciliationOutcomeInput,
): Promise<WarehouseBillingHandoff> {
  const parsedInput = RecordWarehouseBillingReconciliationOutcomeInputSchema.parse(input);
  const { data, error } = await client.rpc("record_warehouse_billing_reconciliation_outcome", {
    p_handoff_id: parsedInput.handoffId,
    p_status: parsedInput.status,
    p_note: parsedInput.note,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WarehouseBillingMutationError(classifyError(error.message), error.message);
  }
  return parseHandoffResponse(data, "record_warehouse_billing_reconciliation_outcome");
}

/** OPS:Override. Callable regardless of the original's own status (including handed_off); rejects stale_version on a record_version mismatch. Creates a NEW draft event (corrects_event_id set); the original's status flips to corrected, its own calculated amounts untouched. */
export async function correctWarehouseBillingEvent(client: WarehouseBillingMutationRpcClient, input: CorrectWarehouseBillingEventInput): Promise<WarehouseBillingEvent> {
  const parsedInput = CorrectWarehouseBillingEventInputSchema.parse(input);
  const { data, error } = await client.rpc("correct_warehouse_billing_event", {
    p_original_event_id: parsedInput.originalEventId,
    p_expected_version: parsedInput.expectedVersion,
    p_new_quantity: parsedInput.newQuantity,
    p_reason: parsedInput.reason,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WarehouseBillingMutationError(classifyError(error.message), error.message);
  }
  return parseEventResponse(data, "correct_warehouse_billing_event");
}

/** OPS:Override. Requires the original to be approved or handed_off; rejects stale_version on a record_version mismatch. Creates a NEW event whose amounts are the exact negation of the original's own already-calculated values (never recalculated); the original's status flips to reversed. */
export async function reverseWarehouseBillingEvent(client: WarehouseBillingMutationRpcClient, input: ReverseWarehouseBillingEventInput): Promise<WarehouseBillingEvent> {
  const parsedInput = ReverseWarehouseBillingEventInputSchema.parse(input);
  const { data, error } = await client.rpc("reverse_warehouse_billing_event", {
    p_original_event_id: parsedInput.originalEventId,
    p_expected_version: parsedInput.expectedVersion,
    p_reason: parsedInput.reason,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WarehouseBillingMutationError(classifyError(error.message), error.message);
  }
  return parseEventResponse(data, "reverse_warehouse_billing_event");
}

/** OPS:View, STABLE, creates no row -- "what would this cost" before capturing anything. No tax preview (the underlying RPC's own signature has no tax-code parameter). */
export async function previewWarehouseBillingCalculation(
  client: WarehouseBillingMutationRpcClient,
  input: PreviewWarehouseBillingCalculationInput,
): Promise<WarehouseBillingCalculationPreview> {
  const parsedInput = PreviewWarehouseBillingCalculationInputSchema.parse(input);
  const { data, error } = await client.rpc("preview_warehouse_billing_calculation", {
    p_tenant_id: parsedInput.tenantId,
    p_account_id: parsedInput.accountId,
    p_warehouse_id: parsedInput.warehouseId,
    p_activity_type: parsedInput.activityType,
    p_quantity: parsedInput.quantity,
    p_uom_code: parsedInput.uomCode,
    p_as_of: parsedInput.asOf,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
  });
  if (error) {
    throw new WarehouseBillingMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new WarehouseBillingMutationError("invalid_response", "preview_warehouse_billing_calculation returned a non-object result");
  }
  return parseWarehouseBillingCalculationPreview(data as Record<string, unknown>);
}
