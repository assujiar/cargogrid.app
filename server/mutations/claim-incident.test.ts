import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  openClaimCase,
  addClaimItem,
  withdrawClaimItem,
  linkClaimEvidence,
  recordClaimInvestigationFinding,
  proposeClaimResponsibility,
  decideClaimResponsibility,
  recordClaimRecovery,
  evaluateClaimSettlementReadiness,
  handoffClaimSettlementReadiness,
  recordClaimFinanceReconciliationOutcome,
  closeClaimCase,
  reopenClaimCase,
  ClaimIncidentMutationError,
  type ClaimIncidentMutationRpcClient,
} from "./claim-incident.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const EXCEPTION_ID = "323e4567-e89b-12d3-a456-426614174000";
const CASE_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const ITEM_ID = "723e4567-e89b-12d3-a456-426614174000";
const EVIDENCE_ID = "823e4567-e89b-12d3-a456-426614174000";
const REVIEW_ID = "923e4567-e89b-12d3-a456-426614174000";
const RECOVERY_ID = "a23e4567-e89b-12d3-a456-426614174000";
const HANDOFF_ID = "c23e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: ClaimIncidentMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as ClaimIncidentMutationRpcClient;
  return { client, calls };
}

const CASE_ROW = {
  id: CASE_ID,
  tenant_id: TENANT_ID,
  operational_exception_id: EXCEPTION_ID,
  claimant_type: "customer",
  claimant_account_id: ACCOUNT_ID,
  claimant_label: null,
  contact_snapshot: null,
  claim_stage: "intake",
  opened_by: "rep",
  opened_at: "2026-08-04T00:00:00.000Z",
  closure_note: null,
  closure_basis: null,
  closed_at: null,
  closed_by: null,
  reopened_at: null,
  reopened_by: null,
  reopen_reason: null,
  record_version: 1,
  created_by: "rep",
  created_at: "2026-08-04T00:00:00.000Z",
  updated_at: "2026-08-04T00:00:00.000Z",
};

const ITEM_ROW = {
  id: ITEM_ID,
  tenant_id: TENANT_ID,
  claim_case_id: CASE_ID,
  item_type: "inventory",
  linked_inventory_movement_id: null,
  linked_wms_outbound_shipment_id: null,
  item_master_id: null,
  declared_quantity: "10",
  uom_code: "PCS",
  declared_value: "500000.00",
  currency: "IDR",
  description: "10 units damaged",
  status: "active",
  withdrawn_at: null,
  withdrawn_by: null,
  withdrawal_reason: null,
  record_version: 1,
  created_by: "rep",
  created_at: "2026-08-04T00:00:00.000Z",
  updated_at: "2026-08-04T00:00:00.000Z",
};

const EVIDENCE_ROW = {
  id: EVIDENCE_ID,
  tenant_id: TENANT_ID,
  claim_case_id: CASE_ID,
  evidence_type: "epod_capture",
  evidence_id: "d23e4567-e89b-12d3-a456-426614174000",
  note: null,
  added_by_auth_user_id: ACTOR_ID,
  added_by: "rep",
  added_at: "2026-08-04T00:00:00.000Z",
};

const REVIEW_ROW = {
  id: REVIEW_ID,
  tenant_id: TENANT_ID,
  claim_case_id: CASE_ID,
  version_number: 1,
  is_current: true,
  proposed_responsibility_party: "carrier",
  proposed_reserve_amount: "2000000.00",
  proposed_currency: "IDR",
  proposed_rationale: "custody chain shows carrier fault",
  proposed_by_auth_user_id: ACTOR_ID,
  proposed_by: "investigator",
  proposed_at: "2026-08-04T00:00:00.000Z",
  status: "proposed",
  decided_by_auth_user_id: null,
  decided_by: null,
  decided_at: null,
  final_responsibility_party: null,
  final_reserve_amount: null,
  final_currency: null,
  decision_notes: null,
  supersedes_review_id: null,
  record_version: 1,
  created_by: "investigator",
  created_at: "2026-08-04T00:00:00.000Z",
  updated_at: "2026-08-04T00:00:00.000Z",
};

const RECOVERY_ROW = {
  id: RECOVERY_ID,
  tenant_id: TENANT_ID,
  claim_case_id: CASE_ID,
  recovered_from: "carrier",
  recovered_amount: "2000000.00",
  currency: "IDR",
  recovered_at: "2026-08-05T00:00:00.000Z",
  reference: "CARRIER-REMIT-1",
  corrects_recovery_id: null,
  recorded_by_auth_user_id: ACTOR_ID,
  recorded_by: "rep",
  created_at: "2026-08-05T00:00:00.000Z",
};

const EVALUATION_ROW = {
  id: "e23e4567-e89b-12d3-a456-426614174000",
  tenant_id: TENANT_ID,
  claim_case_id: CASE_ID,
  version_number: 1,
  is_current: true,
  evaluated_status: "ready",
  blockers: [],
  evidence: {},
  reevaluation_reason: null,
  supersedes_evaluation_id: null,
  evaluated_by_auth_user_id: ACTOR_ID,
  evaluated_by: "rep",
  record_version: 1,
  created_by: "rep",
  created_at: "2026-08-04T00:00:00.000Z",
  updated_at: "2026-08-04T00:00:00.000Z",
};

const HANDOFF_ROW = {
  id: HANDOFF_ID,
  tenant_id: TENANT_ID,
  claim_case_id: CASE_ID,
  evaluation_id: "e23e4567-e89b-12d3-a456-426614174000",
  idempotency_key: "idem-handoff-1",
  handed_off_by_auth_user_id: ACTOR_ID,
  handed_off_by: "rep",
  handed_off_at: "2026-08-04T00:00:00.000Z",
  handoff_seq: 1,
  reconciliation_status: null,
  reconciliation_note: null,
  reconciled_at: null,
  updated_at: null,
  created_at: "2026-08-04T00:00:00.000Z",
};

describe("openClaimCase", () => {
  test("calls open_claim_case with p_-prefixed args", async () => {
    const { client, calls } = fakeRpcClient({ data: [CASE_ROW], error: null });
    const row = await openClaimCase(client, {
      operationalExceptionId: EXCEPTION_ID,
      claimantType: "customer",
      claimantAccountId: ACCOUNT_ID,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(calls[0]?.fn, "open_claim_case");
    assert.equal(calls[0]?.args.p_operational_exception_id, EXCEPTION_ID);
    assert.equal(calls[0]?.args.p_claimant_type, "customer");
    assert.equal(row.id, CASE_ID);
  });

  test("classifies a claim_ineligible_exception_type error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "claim_ineligible_exception_type: exception x is type hold which is not eligible for a claim case" } });
    await assert.rejects(
      () => openClaimCase(client, { operationalExceptionId: EXCEPTION_ID, claimantType: "customer", actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof ClaimIncidentMutationError);
        assert.equal(err.code, "claim_ineligible_exception_type");
        return true;
      },
    );
  });

  test("classifies an unrecognized error message as mutation_failed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "some_unmapped_db_error: boom" } });
    await assert.rejects(
      () => openClaimCase(client, { operationalExceptionId: EXCEPTION_ID, claimantType: "internal", actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof ClaimIncidentMutationError);
        assert.equal(err.code, "mutation_failed");
        return true;
      },
    );
  });

  test("throws invalid_response when the RPC returns no row", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    await assert.rejects(
      () => openClaimCase(client, { operationalExceptionId: EXCEPTION_ID, claimantType: "internal", actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof ClaimIncidentMutationError);
        assert.equal(err.code, "invalid_response");
        return true;
      },
    );
  });
});

describe("addClaimItem", () => {
  test("calls add_claim_item with p_-prefixed args", async () => {
    const { client, calls } = fakeRpcClient({ data: [ITEM_ROW], error: null });
    const row = await addClaimItem(client, {
      caseId: CASE_ID,
      itemType: "inventory",
      declaredQuantity: 10,
      uomCode: "PCS",
      declaredValue: 500000,
      currency: "IDR",
      description: "10 units damaged",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(calls[0]?.fn, "add_claim_item");
    assert.equal(calls[0]?.args.p_declared_quantity, 10);
    assert.equal(row.declaredValue, 500000);
  });

  test("classifies a claim_case_closed error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "claim_case_closed: claim case x is closed -- reopen it first" } });
    await assert.rejects(
      () => addClaimItem(client, { caseId: CASE_ID, itemType: "inventory", declaredQuantity: 1, uomCode: "PCS", description: "x", actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof ClaimIncidentMutationError);
        assert.equal(err.code, "claim_case_closed");
        return true;
      },
    );
  });
});

describe("withdrawClaimItem", () => {
  test("calls withdraw_claim_item with p_-prefixed args", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...ITEM_ROW, status: "withdrawn", withdrawn_at: "2026-08-04T05:00:00.000Z", withdrawn_by: "rep", withdrawal_reason: "duplicate" }], error: null });
    const row = await withdrawClaimItem(client, { itemId: ITEM_ID, expectedVersion: 1, reason: "duplicate", actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(calls[0]?.fn, "withdraw_claim_item");
    assert.equal(calls[0]?.args.p_reason, "duplicate");
    assert.equal(row.status, "withdrawn");
  });

  test("classifies a stale_version error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "stale_version: claim item x expected version 1 but found 2" } });
    await assert.rejects(
      () => withdrawClaimItem(client, { itemId: ITEM_ID, expectedVersion: 1, reason: "duplicate", actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof ClaimIncidentMutationError);
        assert.equal(err.code, "stale_version");
        return true;
      },
    );
  });
});

describe("linkClaimEvidence", () => {
  test("calls link_claim_evidence with p_-prefixed args", async () => {
    const { client, calls } = fakeRpcClient({ data: [EVIDENCE_ROW], error: null });
    const row = await linkClaimEvidence(client, { caseId: CASE_ID, evidenceType: "epod_capture", evidenceId: "d23e4567-e89b-12d3-a456-426614174000", actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(calls[0]?.fn, "link_claim_evidence");
    assert.equal(calls[0]?.args.p_evidence_type, "epod_capture");
    assert.equal(row.evidenceType, "epod_capture");
  });

  test("classifies a claim_evidence_file_unsafe error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "claim_evidence_file_unsafe: file x has scan status pending -- only clean evidence may be linked to a claim" } });
    await assert.rejects(
      () => linkClaimEvidence(client, { caseId: CASE_ID, evidenceType: "file", evidenceId: EVIDENCE_ID, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof ClaimIncidentMutationError);
        assert.equal(err.code, "claim_evidence_file_unsafe");
        return true;
      },
    );
  });

  test("classifies a claim_evidence_scope_mismatch error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "claim_evidence_scope_mismatch: shipment_leg x does not belong to this claim case's own shipment order" } });
    await assert.rejects(
      () => linkClaimEvidence(client, { caseId: CASE_ID, evidenceType: "shipment_leg", evidenceId: EVIDENCE_ID, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof ClaimIncidentMutationError);
        assert.equal(err.code, "claim_evidence_scope_mismatch");
        return true;
      },
    );
  });
});

describe("recordClaimInvestigationFinding", () => {
  test("calls record_claim_investigation_finding with p_-prefixed args", async () => {
    const { client, calls } = fakeRpcClient({
      data: [
        {
          id: "f23e4567-e89b-12d3-a456-426614174000",
          tenant_id: TENANT_ID,
          claim_case_id: CASE_ID,
          investigator_auth_user_id: ACTOR_ID,
          finding_text: "custody chain confirms carrier fault",
          evidence_sufficiency: "sufficient",
          created_by: "investigator",
          created_at: "2026-08-04T00:00:00.000Z",
        },
      ],
      error: null,
    });
    const row = await recordClaimInvestigationFinding(client, { caseId: CASE_ID, findingText: "custody chain confirms carrier fault", evidenceSufficiency: "sufficient", actorAuthUserId: ACTOR_ID, actorLabel: "investigator" });
    assert.equal(calls[0]?.fn, "record_claim_investigation_finding");
    assert.equal(row.evidenceSufficiency, "sufficient");
  });

  test("classifies a claim_not_investigator error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "claim_not_investigator: identity x is not the assigned investigator (owner) of exception y" } });
    await assert.rejects(
      () => recordClaimInvestigationFinding(client, { caseId: CASE_ID, findingText: "x", evidenceSufficiency: "pending", actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof ClaimIncidentMutationError);
        assert.equal(err.code, "claim_not_investigator");
        return true;
      },
    );
  });
});

describe("proposeClaimResponsibility", () => {
  test("calls propose_claim_responsibility with p_-prefixed args, including p_expected_version", async () => {
    const { client, calls } = fakeRpcClient({ data: [REVIEW_ROW], error: null });
    const row = await proposeClaimResponsibility(client, {
      caseId: CASE_ID,
      proposedResponsibilityParty: "carrier",
      proposedReserveAmount: 2000000,
      proposedCurrency: "IDR",
      proposedRationale: "custody chain shows carrier fault",
      expectedVersion: null,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "investigator",
    });
    assert.equal(calls[0]?.fn, "propose_claim_responsibility");
    assert.equal(calls[0]?.args.p_proposed_responsibility_party, "carrier");
    assert.equal(calls[0]?.args.p_expected_version, null);
    assert.equal(row.status, "proposed");
  });

  test("passes a real expectedVersion through for a re-proposal on an existing review", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...REVIEW_ROW, proposed_reserve_amount: "2500000.00" }], error: null });
    await proposeClaimResponsibility(client, {
      caseId: CASE_ID,
      proposedResponsibilityParty: "carrier",
      proposedReserveAmount: 2500000,
      proposedCurrency: "IDR",
      proposedRationale: "revised after full custody chain review",
      expectedVersion: 1,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "investigator",
    });
    assert.equal(calls[0]?.args.p_expected_version, 1);
  });

  test("classifies a stale_version error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "stale_version: claim responsibility review x expected version 1 but found 2" } });
    await assert.rejects(
      () =>
        proposeClaimResponsibility(client, {
          caseId: CASE_ID,
          proposedResponsibilityParty: "carrier",
          proposedRationale: "stale re-propose",
          expectedVersion: 1,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "investigator",
        }),
      (err: unknown) => {
        assert.ok(err instanceof ClaimIncidentMutationError);
        assert.equal(err.code, "stale_version");
        return true;
      },
    );
  });
});

describe("decideClaimResponsibility", () => {
  test("calls decide_claim_responsibility with p_-prefixed args", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...REVIEW_ROW, status: "approved", final_responsibility_party: "carrier", final_reserve_amount: "2000000.00", final_currency: "IDR", decided_by_auth_user_id: ACTOR_ID, decided_by: "supervisor", decided_at: "2026-08-04T01:00:00.000Z", decision_notes: "approved as proposed" }], error: null });
    const row = await decideClaimResponsibility(client, {
      reviewId: REVIEW_ID,
      expectedVersion: 1,
      decision: "approved",
      finalResponsibilityParty: "carrier",
      finalReserveAmount: 2000000,
      finalCurrency: "IDR",
      decisionNotes: "approved as proposed",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "supervisor",
    });
    assert.equal(calls[0]?.fn, "decide_claim_responsibility");
    assert.equal(row.status, "approved");
  });

  test("classifies a self_approval_not_allowed error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "self_approval_not_allowed: identity x proposed claim responsibility review y and may not also decide it" } });
    await assert.rejects(
      () => decideClaimResponsibility(client, { reviewId: REVIEW_ID, expectedVersion: 1, decision: "denied", decisionNotes: "x", actorAuthUserId: ACTOR_ID, actorLabel: "investigator" }),
      (err: unknown) => {
        assert.ok(err instanceof ClaimIncidentMutationError);
        assert.equal(err.code, "self_approval_not_allowed");
        return true;
      },
    );
  });
});

describe("recordClaimRecovery", () => {
  test("calls record_claim_recovery with p_-prefixed args", async () => {
    const { client, calls } = fakeRpcClient({ data: [RECOVERY_ROW], error: null });
    const row = await recordClaimRecovery(client, { caseId: CASE_ID, recoveredFrom: "carrier", recoveredAmount: 2000000, currency: "IDR", reference: "CARRIER-REMIT-1", actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(calls[0]?.fn, "record_claim_recovery");
    assert.equal(row.recoveredAmount, 2000000);
  });

  test("classifies a claim_recovery_requires_decision error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "claim_recovery_requires_decision: claim case x has no approved/amended responsibility decision yet" } });
    await assert.rejects(
      () => recordClaimRecovery(client, { caseId: CASE_ID, recoveredFrom: "carrier", recoveredAmount: 1, currency: "IDR", actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof ClaimIncidentMutationError);
        assert.equal(err.code, "claim_recovery_requires_decision");
        return true;
      },
    );
  });
});

describe("evaluateClaimSettlementReadiness", () => {
  test("calls evaluate_claim_settlement_readiness with p_-prefixed args", async () => {
    const { client, calls } = fakeRpcClient({ data: [EVALUATION_ROW], error: null });
    const row = await evaluateClaimSettlementReadiness(client, { caseId: CASE_ID, actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(calls[0]?.fn, "evaluate_claim_settlement_readiness");
    assert.equal(row.evaluatedStatus, "ready");
  });
});

describe("handoffClaimSettlementReadiness", () => {
  test("calls handoff_claim_settlement_readiness with p_-prefixed args", async () => {
    const { client, calls } = fakeRpcClient({ data: [HANDOFF_ROW], error: null });
    const row = await handoffClaimSettlementReadiness(client, { caseId: CASE_ID, idempotencyKey: "idem-handoff-1", actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(calls[0]?.fn, "handoff_claim_settlement_readiness");
    assert.equal(row.idempotencyKey, "idem-handoff-1");
  });

  test("classifies a claim_settlement_not_ready error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "claim_settlement_not_ready: claim case x is not ready for Finance settlement handoff" } });
    await assert.rejects(
      () => handoffClaimSettlementReadiness(client, { caseId: CASE_ID, idempotencyKey: "idem-1", actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof ClaimIncidentMutationError);
        assert.equal(err.code, "claim_settlement_not_ready");
        return true;
      },
    );
  });
});

describe("recordClaimFinanceReconciliationOutcome", () => {
  test("calls record_claim_finance_reconciliation_outcome with p_-prefixed args (service_role only)", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...HANDOFF_ROW, reconciliation_status: "reconciled", reconciliation_note: "posted", reconciled_at: "2026-08-04T02:00:00.000Z", updated_at: "2026-08-04T02:00:00.000Z" }], error: null });
    const row = await recordClaimFinanceReconciliationOutcome(client, { handoffId: HANDOFF_ID, status: "reconciled", note: "posted", actorAuthUserId: ACTOR_ID, actorLabel: "finance-worker" });
    assert.equal(calls[0]?.fn, "record_claim_finance_reconciliation_outcome");
    assert.equal(row.reconciliationStatus, "reconciled");
  });

  test("classifies a reconciliation_outcome_conflict error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "reconciliation_outcome_conflict: handoff x already has reconciliation_status reconciled and cannot be changed to rejected" } });
    await assert.rejects(
      () => recordClaimFinanceReconciliationOutcome(client, { handoffId: HANDOFF_ID, status: "rejected", note: "x", actorAuthUserId: ACTOR_ID, actorLabel: "finance-worker" }),
      (err: unknown) => {
        assert.ok(err instanceof ClaimIncidentMutationError);
        assert.equal(err.code, "reconciliation_outcome_conflict");
        return true;
      },
    );
  });
});

describe("closeClaimCase", () => {
  test("calls close_claim_case with p_-prefixed args", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...CASE_ROW, claim_stage: "closed", closure_basis: "finance_reconciled", closure_note: "reconciled", closed_at: "2026-08-04T03:00:00.000Z", closed_by: "supervisor" }], error: null });
    const row = await closeClaimCase(client, { caseId: CASE_ID, expectedVersion: 3, exceptionExpectedVersion: 2, closureNote: "reconciled", actorAuthUserId: ACTOR_ID, actorLabel: "supervisor" });
    assert.equal(calls[0]?.fn, "close_claim_case");
    assert.equal(calls[0]?.args.p_exception_expected_version, 2);
    assert.equal(row.claimStage, "closed");
    assert.equal(row.closureBasis, "finance_reconciled");
  });

  test("classifies a claim_case_not_reconciled error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "claim_case_not_reconciled: claim case x is not yet finance-reconciled and does not qualify for the no-handoff-required closure path" } });
    await assert.rejects(
      () => closeClaimCase(client, { caseId: CASE_ID, expectedVersion: 1, exceptionExpectedVersion: 1, closureNote: "x", actorAuthUserId: ACTOR_ID, actorLabel: "supervisor" }),
      (err: unknown) => {
        assert.ok(err instanceof ClaimIncidentMutationError);
        assert.equal(err.code, "claim_case_not_reconciled");
        return true;
      },
    );
  });
});

describe("reopenClaimCase", () => {
  test("calls reopen_claim_case with p_-prefixed args", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...CASE_ROW, claim_stage: "investigating", reopened_at: "2026-08-04T04:00:00.000Z", reopened_by: "supervisor", reopen_reason: "new evidence" }], error: null });
    const row = await reopenClaimCase(client, { caseId: CASE_ID, expectedVersion: 4, exceptionExpectedVersion: 3, reason: "new evidence", actorAuthUserId: ACTOR_ID, actorLabel: "supervisor" });
    assert.equal(calls[0]?.fn, "reopen_claim_case");
    assert.equal(calls[0]?.args.p_reason, "new evidence");
    assert.equal(row.claimStage, "investigating");
    assert.equal(row.reopenReason, "new evidence");
  });

  test("classifies an invalid_transition error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "invalid_transition: claim case x is intake and cannot be reopened" } });
    await assert.rejects(
      () => reopenClaimCase(client, { caseId: CASE_ID, expectedVersion: 1, exceptionExpectedVersion: 1, reason: "x", actorAuthUserId: ACTOR_ID, actorLabel: "supervisor" }),
      (err: unknown) => {
        assert.ok(err instanceof ClaimIncidentMutationError);
        assert.equal(err.code, "invalid_transition");
        return true;
      },
    );
  });
});
