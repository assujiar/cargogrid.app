/**
 * Advanced Claim and Incident Operations mutation primitives (ATW-025,
 * CG-S10-ATW-025). Thin, typed wrappers around app.open_claim_case/app.
 * add_claim_item/app.withdraw_claim_item/app.link_claim_evidence/app.
 * record_claim_investigation_finding/app.propose_claim_responsibility/app.
 * decide_claim_responsibility/app.record_claim_recovery/app.
 * evaluate_claim_settlement_readiness/app.handoff_claim_settlement_readiness/app.
 * record_claim_finance_reconciliation_outcome/app.close_claim_case/app.
 * reopen_claim_case
 * (supabase/migrations/20260730340000_create_advanced_tms_claim_incident_operations.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  OpenClaimCaseInputSchema,
  AddClaimItemInputSchema,
  WithdrawClaimItemInputSchema,
  LinkClaimEvidenceInputSchema,
  RecordClaimInvestigationFindingInputSchema,
  ProposeClaimResponsibilityInputSchema,
  DecideClaimResponsibilityInputSchema,
  RecordClaimRecoveryInputSchema,
  EvaluateClaimSettlementReadinessInputSchema,
  HandoffClaimSettlementReadinessInputSchema,
  RecordClaimFinanceReconciliationOutcomeInputSchema,
  CloseClaimCaseInputSchema,
  ReopenClaimCaseInputSchema,
  parseClaimCaseExtension,
  parseClaimItem,
  parseClaimEvidenceLink,
  parseClaimInvestigationFinding,
  parseClaimResponsibilityReview,
  parseClaimRecoveryRecord,
  parseClaimSettlementReadinessEvaluation,
  parseClaimSettlementReadinessHandoff,
  type OpenClaimCaseInput,
  type AddClaimItemInput,
  type WithdrawClaimItemInput,
  type LinkClaimEvidenceInput,
  type RecordClaimInvestigationFindingInput,
  type ProposeClaimResponsibilityInput,
  type DecideClaimResponsibilityInput,
  type RecordClaimRecoveryInput,
  type EvaluateClaimSettlementReadinessInput,
  type HandoffClaimSettlementReadinessInput,
  type RecordClaimFinanceReconciliationOutcomeInput,
  type CloseClaimCaseInput,
  type ReopenClaimCaseInput,
  type ClaimCaseExtension,
  type ClaimItem,
  type ClaimEvidenceLink,
  type ClaimInvestigationFinding,
  type ClaimResponsibilityReview,
  type ClaimRecoveryRecord,
  type ClaimSettlementReadinessEvaluation,
  type ClaimSettlementReadinessHandoff,
} from "../contracts/claim-incident/claim-incident.ts";

export type ClaimIncidentMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const CLAIM_INCIDENT_KNOWN_MUTATION_ERROR_CODES = [
  "operational_exception_not_found",
  "claim_case_not_found",
  "claim_case_closed",
  "claim_case_already_closed",
  "claim_case_not_reconciled",
  "claim_case_open_conflict",
  "claim_claimant_account_not_found",
  "claim_claimant_identification_required",
  "claim_closure_note_required",
  "claim_decision_notes_required",
  "claim_denied_decision_shape_invalid",
  "claim_evidence_file_access_denied",
  "claim_evidence_file_unsafe",
  "claim_evidence_link_conflict",
  "claim_evidence_not_found",
  "claim_evidence_required",
  "claim_evidence_scope_mismatch",
  "claim_finding_text_required",
  "claim_ineligible_exception_type",
  "claim_invalid_claimant_type",
  "claim_invalid_contact_snapshot",
  "claim_invalid_decision",
  "claim_invalid_declared_quantity",
  "claim_invalid_declared_value",
  "claim_invalid_evidence_sufficiency",
  "claim_invalid_evidence_type",
  "claim_invalid_item_type",
  "claim_invalid_recovered_amount",
  "claim_invalid_recovered_from",
  "claim_invalid_reserve_amount",
  "claim_invalid_responsibility_party",
  "claim_item_description_required",
  "claim_item_not_found",
  "claim_not_investigator",
  "claim_rationale_required",
  "claim_recovery_not_found",
  "claim_recovery_requires_decision",
  "claim_reserve_currency_shape_invalid",
  "claim_responsibility_review_not_found",
  "claim_settlement_handoff_not_found",
  "claim_settlement_not_evaluated",
  "claim_settlement_not_ready",
  "claim_settlement_reevaluation_reason_required",
  "claim_value_currency_shape_invalid",
  "insufficient_authority",
  "invalid_actor_label",
  "invalid_currency",
  "invalid_cursor",
  "invalid_idempotency_key",
  "invalid_note",
  "invalid_status",
  "invalid_transition",
  "invalid_uom_code",
  "reason_required",
  "reconciliation_outcome_conflict",
  "self_approval_not_allowed",
  "stale_version",
] as const;
type KnownClaimIncidentMutationErrorCode = (typeof CLAIM_INCIDENT_KNOWN_MUTATION_ERROR_CODES)[number];
export type ClaimIncidentMutationErrorCode = KnownClaimIncidentMutationErrorCode | "mutation_failed" | "invalid_response";

export class ClaimIncidentMutationError extends Error {
  readonly code: ClaimIncidentMutationErrorCode;

  constructor(code: ClaimIncidentMutationErrorCode, message: string) {
    super(message);
    this.name = "ClaimIncidentMutationError";
    this.code = code;
  }
}

function classifyError(message: string): ClaimIncidentMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (CLAIM_INCIDENT_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownClaimIncidentMutationErrorCode) : "mutation_failed";
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

function parseCaseResponse(data: unknown, rpcName: string): ClaimCaseExtension {
  const row = firstRow(data);
  if (!row) {
    throw new ClaimIncidentMutationError("invalid_response", `${rpcName} returned no row`);
  }
  return parseClaimCaseExtension(row);
}

function parseItemResponse(data: unknown, rpcName: string): ClaimItem {
  const row = firstRow(data);
  if (!row) {
    throw new ClaimIncidentMutationError("invalid_response", `${rpcName} returned no row`);
  }
  return parseClaimItem(row);
}

function parseEvidenceResponse(data: unknown, rpcName: string): ClaimEvidenceLink {
  const row = firstRow(data);
  if (!row) {
    throw new ClaimIncidentMutationError("invalid_response", `${rpcName} returned no row`);
  }
  return parseClaimEvidenceLink(row);
}

function parseFindingResponse(data: unknown, rpcName: string): ClaimInvestigationFinding {
  const row = firstRow(data);
  if (!row) {
    throw new ClaimIncidentMutationError("invalid_response", `${rpcName} returned no row`);
  }
  return parseClaimInvestigationFinding(row);
}

function parseReviewResponse(data: unknown, rpcName: string): ClaimResponsibilityReview {
  const row = firstRow(data);
  if (!row) {
    throw new ClaimIncidentMutationError("invalid_response", `${rpcName} returned no row`);
  }
  return parseClaimResponsibilityReview(row);
}

function parseRecoveryResponse(data: unknown, rpcName: string): ClaimRecoveryRecord {
  const row = firstRow(data);
  if (!row) {
    throw new ClaimIncidentMutationError("invalid_response", `${rpcName} returned no row`);
  }
  return parseClaimRecoveryRecord(row);
}

function parseEvaluationResponse(data: unknown, rpcName: string): ClaimSettlementReadinessEvaluation {
  const row = firstRow(data);
  if (!row) {
    throw new ClaimIncidentMutationError("invalid_response", `${rpcName} returned no row`);
  }
  return parseClaimSettlementReadinessEvaluation(row);
}

function parseHandoffResponse(data: unknown, rpcName: string): ClaimSettlementReadinessHandoff {
  const row = firstRow(data);
  if (!row) {
    throw new ClaimIncidentMutationError("invalid_response", `${rpcName} returned no row`);
  }
  return parseClaimSettlementReadinessHandoff(row);
}

/** OPS:Create + record-scope. Idempotent on operationalExceptionId -- a retry returns the existing row, never a second one. */
export async function openClaimCase(client: ClaimIncidentMutationRpcClient, input: OpenClaimCaseInput): Promise<ClaimCaseExtension> {
  const parsedInput = OpenClaimCaseInputSchema.parse(input);
  const { data, error } = await client.rpc("open_claim_case", {
    p_operational_exception_id: parsedInput.operationalExceptionId,
    p_claimant_type: parsedInput.claimantType,
    p_claimant_account_id: parsedInput.claimantAccountId ?? null,
    p_claimant_label: parsedInput.claimantLabel ?? null,
    p_contact_snapshot: parsedInput.contactSnapshot ?? null,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ClaimIncidentMutationError(classifyError(error.message), error.message);
  }
  return parseCaseResponse(data, "open_claim_case");
}

/** OPS:Edit + record-scope. Rejected claim_case_closed once the case has been closed (reopen first). */
export async function addClaimItem(client: ClaimIncidentMutationRpcClient, input: AddClaimItemInput): Promise<ClaimItem> {
  const parsedInput = AddClaimItemInputSchema.parse(input);
  const { data, error } = await client.rpc("add_claim_item", {
    p_case_id: parsedInput.caseId,
    p_item_type: parsedInput.itemType,
    p_linked_inventory_movement_id: parsedInput.linkedInventoryMovementId ?? null,
    p_linked_wms_outbound_shipment_id: parsedInput.linkedWmsOutboundShipmentId ?? null,
    p_item_master_id: parsedInput.itemMasterId ?? null,
    p_declared_quantity: parsedInput.declaredQuantity,
    p_uom_code: parsedInput.uomCode,
    p_declared_value: parsedInput.declaredValue ?? null,
    p_currency: parsedInput.currency ?? null,
    p_description: parsedInput.description,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ClaimIncidentMutationError(classifyError(error.message), error.message);
  }
  return parseItemResponse(data, "add_claim_item");
}

/** OPS:Edit + record-scope. status must be active -> withdrawn (a status flip, never a delete). */
export async function withdrawClaimItem(client: ClaimIncidentMutationRpcClient, input: WithdrawClaimItemInput): Promise<ClaimItem> {
  const parsedInput = WithdrawClaimItemInputSchema.parse(input);
  const { data, error } = await client.rpc("withdraw_claim_item", {
    p_item_id: parsedInput.itemId,
    p_expected_version: parsedInput.expectedVersion,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ClaimIncidentMutationError(classifyError(error.message), error.message);
  }
  return parseItemResponse(data, "withdraw_claim_item");
}

/** OPS:Edit + record-scope. Validates evidenceId against its real source table before linking; rejects an unsafe/unscanned file. */
export async function linkClaimEvidence(client: ClaimIncidentMutationRpcClient, input: LinkClaimEvidenceInput): Promise<ClaimEvidenceLink> {
  const parsedInput = LinkClaimEvidenceInputSchema.parse(input);
  const { data, error } = await client.rpc("link_claim_evidence", {
    p_case_id: parsedInput.caseId,
    p_evidence_type: parsedInput.evidenceType,
    p_evidence_id: parsedInput.evidenceId,
    p_note: parsedInput.note ?? null,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ClaimIncidentMutationError(classifyError(error.message), error.message);
  }
  return parseEvidenceResponse(data, "link_claim_evidence");
}

/** OPS:Edit + record-scope. The actor must be the case's own assigned investigator (the underlying exception's owner_user_id). */
export async function recordClaimInvestigationFinding(client: ClaimIncidentMutationRpcClient, input: RecordClaimInvestigationFindingInput): Promise<ClaimInvestigationFinding> {
  const parsedInput = RecordClaimInvestigationFindingInputSchema.parse(input);
  const { data, error } = await client.rpc("record_claim_investigation_finding", {
    p_case_id: parsedInput.caseId,
    p_finding_text: parsedInput.findingText,
    p_evidence_sufficiency: parsedInput.evidenceSufficiency,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ClaimIncidentMutationError(classifyError(error.message), error.message);
  }
  return parseFindingResponse(data, "record_claim_investigation_finding");
}

/** OPS:Edit + record-scope. Updates the SAME row in place while status=proposed; starts a new version once a decision already exists. expectedVersion enforces real optimistic concurrency (stale_version) -- null iff no current review exists yet for this case. Rejects claim_evidence_required for a positive reserve with zero items/evidence on file. */
export async function proposeClaimResponsibility(client: ClaimIncidentMutationRpcClient, input: ProposeClaimResponsibilityInput): Promise<ClaimResponsibilityReview> {
  const parsedInput = ProposeClaimResponsibilityInputSchema.parse(input);
  const { data, error } = await client.rpc("propose_claim_responsibility", {
    p_case_id: parsedInput.caseId,
    p_proposed_responsibility_party: parsedInput.proposedResponsibilityParty,
    p_proposed_reserve_amount: parsedInput.proposedReserveAmount ?? null,
    p_proposed_currency: parsedInput.proposedCurrency ?? null,
    p_proposed_rationale: parsedInput.proposedRationale,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ClaimIncidentMutationError(classifyError(error.message), error.message);
  }
  return parseReviewResponse(data, "propose_claim_responsibility");
}

/** OPS:Override (a governed liability/reserve decision). Enforces decidedBy <> proposedBy (self_approval_not_allowed). */
export async function decideClaimResponsibility(client: ClaimIncidentMutationRpcClient, input: DecideClaimResponsibilityInput): Promise<ClaimResponsibilityReview> {
  const parsedInput = DecideClaimResponsibilityInputSchema.parse(input);
  const { data, error } = await client.rpc("decide_claim_responsibility", {
    p_review_id: parsedInput.reviewId,
    p_expected_version: parsedInput.expectedVersion,
    p_decision: parsedInput.decision,
    p_final_responsibility_party: parsedInput.finalResponsibilityParty ?? null,
    p_final_reserve_amount: parsedInput.finalReserveAmount ?? null,
    p_final_currency: parsedInput.finalCurrency ?? null,
    p_decision_notes: parsedInput.decisionNotes,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ClaimIncidentMutationError(classifyError(error.message), error.message);
  }
  return parseReviewResponse(data, "decide_claim_responsibility");
}

/** OPS:Edit + record-scope. Requires an approved/amended responsibility decision to already exist. Append-only -- a correction is a new row via correctsRecoveryId. */
export async function recordClaimRecovery(client: ClaimIncidentMutationRpcClient, input: RecordClaimRecoveryInput): Promise<ClaimRecoveryRecord> {
  const parsedInput = RecordClaimRecoveryInputSchema.parse(input);
  const { data, error } = await client.rpc("record_claim_recovery", {
    p_case_id: parsedInput.caseId,
    p_recovered_from: parsedInput.recoveredFrom,
    p_recovered_amount: parsedInput.recoveredAmount,
    p_currency: parsedInput.currency,
    p_recovered_at: parsedInput.recoveredAt ?? null,
    p_reference: parsedInput.reference ?? null,
    p_corrects_recovery_id: parsedInput.correctsRecoveryId ?? null,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ClaimIncidentMutationError(classifyError(error.message), error.message);
  }
  return parseRecoveryResponse(data, "record_claim_recovery");
}

/** OPS:Edit + record-scope. The one evidence-reading, versioning entry point. Real computed blockers only, never fabricated. */
export async function evaluateClaimSettlementReadiness(client: ClaimIncidentMutationRpcClient, input: EvaluateClaimSettlementReadinessInput): Promise<ClaimSettlementReadinessEvaluation> {
  const parsedInput = EvaluateClaimSettlementReadinessInputSchema.parse(input);
  const { data, error } = await client.rpc("evaluate_claim_settlement_readiness", {
    p_case_id: parsedInput.caseId,
    p_reevaluation_reason: parsedInput.reevaluationReason ?? null,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ClaimIncidentMutationError(classifyError(error.message), error.message);
  }
  return parseEvaluationResponse(data, "evaluate_claim_settlement_readiness");
}

/** OPS:Edit + record-scope. Idempotent on (tenantId via the case's own tenant, caseId, idempotencyKey). Requires evaluatedStatus=ready. */
export async function handoffClaimSettlementReadiness(client: ClaimIncidentMutationRpcClient, input: HandoffClaimSettlementReadinessInput): Promise<ClaimSettlementReadinessHandoff> {
  const parsedInput = HandoffClaimSettlementReadinessInputSchema.parse(input);
  const { data, error } = await client.rpc("handoff_claim_settlement_readiness", {
    p_case_id: parsedInput.caseId,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ClaimIncidentMutationError(classifyError(error.message), error.message);
  }
  return parseHandoffResponse(data, "handoff_claim_settlement_readiness");
}

/**
 * service_role only -- a Finance-side worker callback called from server-side/worker
 * code paths only, never a browser client. No authenticated grant exists on the
 * underlying RPC at all (mirrors app.record_warehouse_billing_reconciliation_
 * outcome's exact precedent, ATW-022). Idempotent on a same-outcome replay; rejects
 * a conflicting second outcome.
 */
export async function recordClaimFinanceReconciliationOutcome(
  client: ClaimIncidentMutationRpcClient,
  input: RecordClaimFinanceReconciliationOutcomeInput,
): Promise<ClaimSettlementReadinessHandoff> {
  const parsedInput = RecordClaimFinanceReconciliationOutcomeInputSchema.parse(input);
  const { data, error } = await client.rpc("record_claim_finance_reconciliation_outcome", {
    p_handoff_id: parsedInput.handoffId,
    p_status: parsedInput.status,
    p_note: parsedInput.note,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ClaimIncidentMutationError(classifyError(error.message), error.message);
  }
  return parseHandoffResponse(data, "record_claim_finance_reconciliation_outcome");
}

/**
 * OPS:Close + record-scope. Requires the case's own most recent Finance handoff to
 * be reconciled, OR a decided (denied, or approved/amended with a null-or-zero
 * final reserve) responsibility decision -- else claim_case_not_reconciled. Drives
 * the underlying operational exception through its own real resolve/close RPCs.
 */
export async function closeClaimCase(client: ClaimIncidentMutationRpcClient, input: CloseClaimCaseInput): Promise<ClaimCaseExtension> {
  const parsedInput = CloseClaimCaseInputSchema.parse(input);
  const { data, error } = await client.rpc("close_claim_case", {
    p_case_id: parsedInput.caseId,
    p_expected_version: parsedInput.expectedVersion,
    p_exception_expected_version: parsedInput.exceptionExpectedVersion,
    p_closure_note: parsedInput.closureNote,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ClaimIncidentMutationError(classifyError(error.message), error.message);
  }
  return parseCaseResponse(data, "close_claim_case");
}

/** OPS:Edit + record-scope (mirrors app.reopen_exception's own actual precedent). closed -> investigating only, mandatory reason. */
export async function reopenClaimCase(client: ClaimIncidentMutationRpcClient, input: ReopenClaimCaseInput): Promise<ClaimCaseExtension> {
  const parsedInput = ReopenClaimCaseInputSchema.parse(input);
  const { data, error } = await client.rpc("reopen_claim_case", {
    p_case_id: parsedInput.caseId,
    p_expected_version: parsedInput.expectedVersion,
    p_exception_expected_version: parsedInput.exceptionExpectedVersion,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ClaimIncidentMutationError(classifyError(error.message), error.message);
  }
  return parseCaseResponse(data, "reopen_claim_case");
}
