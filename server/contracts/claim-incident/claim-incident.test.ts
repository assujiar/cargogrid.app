import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseClaimCaseExtension,
  parseClaimCaseListRow,
  parseClaimItem,
  parseClaimEvidenceLink,
  parseClaimInvestigationFinding,
  parseClaimResponsibilityReview,
  parseClaimRecoveryRecord,
  parseClaimSettlementReadinessEvaluation,
  parseClaimSettlementReadinessHandoff,
  OpenClaimCaseInputSchema,
  AddClaimItemInputSchema,
  LinkClaimEvidenceInputSchema,
  DecideClaimResponsibilityInputSchema,
  RecordClaimRecoveryInputSchema,
  RecordClaimFinanceReconciliationOutcomeInputSchema,
  ClaimContactSnapshotSchema,
  ListClaimCasesInputSchema,
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
const EVALUATION_ID = "b23e4567-e89b-12d3-a456-426614174000";
const HANDOFF_ID = "c23e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "d23e4567-e89b-12d3-a456-426614174000";

describe("parseClaimCaseExtension", () => {
  test("maps a fresh intake row (no claimant account, contact snapshot minimized)", () => {
    const row = parseClaimCaseExtension({
      id: CASE_ID,
      tenant_id: TENANT_ID,
      operational_exception_id: EXCEPTION_ID,
      claimant_type: "customer",
      claimant_account_id: ACCOUNT_ID,
      claimant_label: null,
      contact_snapshot: { name: "Alice", email: "alice@example.test" },
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
    });
    assert.equal(row.claimStage, "intake");
    assert.equal(row.claimantAccountId, ACCOUNT_ID);
    assert.deepEqual(row.contactSnapshot, { name: "Alice", email: "alice@example.test" });
    assert.equal(row.closedAt, null);
  });

  test("maps a closed row with closure/reopen history preserved", () => {
    const row = parseClaimCaseExtension({
      id: CASE_ID,
      tenant_id: TENANT_ID,
      operational_exception_id: EXCEPTION_ID,
      claimant_type: "internal",
      claimant_account_id: null,
      claimant_label: null,
      contact_snapshot: null,
      claim_stage: "investigating",
      opened_by: "rep",
      opened_at: "2026-08-04T00:00:00.000Z",
      closure_note: "resolved and reconciled",
      closure_basis: "finance_reconciled",
      closed_at: "2026-08-04T01:00:00.000Z",
      closed_by: "supervisor",
      reopened_at: "2026-08-04T02:00:00.000Z",
      reopened_by: "supervisor",
      reopen_reason: "new evidence surfaced",
      record_version: 5,
      created_by: "rep",
      created_at: "2026-08-04T00:00:00.000Z",
      updated_at: "2026-08-04T02:00:00.000Z",
    });
    assert.equal(row.claimStage, "investigating");
    assert.equal(row.closureBasis, "finance_reconciled");
    assert.equal(row.reopenReason, "new evidence surfaced");
  });
});

describe("parseClaimCaseListRow", () => {
  test("maps the joined list-row shape (case + denormalized exception fields)", () => {
    const row = parseClaimCaseListRow({
      id: CASE_ID,
      tenant_id: TENANT_ID,
      operational_exception_id: EXCEPTION_ID,
      claimant_type: "carrier",
      claimant_account_id: null,
      claimant_label: "Acme Trucking",
      claim_stage: "decided",
      opened_by: "rep",
      opened_at: "2026-08-04T00:00:00.000Z",
      closure_basis: null,
      closed_at: null,
      record_version: 3,
      updated_at: "2026-08-04T01:00:00.000Z",
      exception_type: "damage",
      exception_severity: "high",
      exception_status: "acknowledged",
      shipment_order_id: SHIPMENT_ID,
    });
    assert.equal(row.exceptionType, "damage");
    assert.equal(row.exceptionSeverity, "high");
    assert.equal(row.shipmentOrderId, SHIPMENT_ID);
  });
});

describe("parseClaimItem", () => {
  test("maps an active item with both value and currency present", () => {
    const row = parseClaimItem({
      id: ITEM_ID,
      tenant_id: TENANT_ID,
      claim_case_id: CASE_ID,
      item_type: "inventory",
      linked_inventory_movement_id: EVIDENCE_ID,
      linked_wms_outbound_shipment_id: null,
      item_master_id: null,
      declared_quantity: "20",
      uom_code: "PCS",
      declared_value: "1500000.00",
      currency: "IDR",
      description: "20 units crushed in transit",
      status: "active",
      withdrawn_at: null,
      withdrawn_by: null,
      withdrawal_reason: null,
      record_version: 1,
      created_by: "rep",
      created_at: "2026-08-04T00:00:00.000Z",
      updated_at: "2026-08-04T00:00:00.000Z",
    });
    assert.equal(row.declaredQuantity, 20);
    assert.equal(row.declaredValue, 1500000);
    assert.equal(row.status, "active");
  });

  test("maps a masked item row (declaredValue/currency nulled)", () => {
    const row = parseClaimItem({
      id: ITEM_ID,
      tenant_id: TENANT_ID,
      claim_case_id: CASE_ID,
      item_type: "inventory",
      linked_inventory_movement_id: null,
      linked_wms_outbound_shipment_id: null,
      item_master_id: null,
      declared_quantity: "20",
      uom_code: "PCS",
      declared_value: null,
      currency: null,
      description: "20 units crushed in transit",
      status: "active",
      withdrawn_at: null,
      withdrawn_by: null,
      withdrawal_reason: null,
      record_version: 1,
      created_by: "rep",
      created_at: "2026-08-04T00:00:00.000Z",
      updated_at: "2026-08-04T00:00:00.000Z",
    });
    assert.equal(row.declaredValue, null);
    assert.equal(row.currency, null);
  });

  test("maps a withdrawn item", () => {
    const row = parseClaimItem({
      id: ITEM_ID,
      tenant_id: TENANT_ID,
      claim_case_id: CASE_ID,
      item_type: "cargo_general",
      linked_inventory_movement_id: null,
      linked_wms_outbound_shipment_id: null,
      item_master_id: null,
      declared_quantity: "1",
      uom_code: "PCS",
      declared_value: null,
      currency: null,
      description: "duplicate line, withdrawn",
      status: "withdrawn",
      withdrawn_at: "2026-08-04T03:00:00.000Z",
      withdrawn_by: "rep",
      withdrawal_reason: "duplicate entry",
      record_version: 2,
      created_by: "rep",
      created_at: "2026-08-04T00:00:00.000Z",
      updated_at: "2026-08-04T03:00:00.000Z",
    });
    assert.equal(row.status, "withdrawn");
    assert.equal(row.withdrawalReason, "duplicate entry");
  });
});

describe("parseClaimEvidenceLink", () => {
  test("maps a file evidence link", () => {
    const row = parseClaimEvidenceLink({
      id: EVIDENCE_ID,
      tenant_id: TENANT_ID,
      claim_case_id: CASE_ID,
      evidence_type: "file",
      evidence_id: "e23e4567-e89b-12d3-a456-426614174000",
      note: "damage photo",
      added_by_auth_user_id: ACTOR_ID,
      added_by: "rep",
      added_at: "2026-08-04T00:00:00.000Z",
    });
    assert.equal(row.evidenceType, "file");
    assert.equal(row.note, "damage photo");
  });
});

describe("parseClaimInvestigationFinding", () => {
  test("maps a finding row", () => {
    const row = parseClaimInvestigationFinding({
      id: EVIDENCE_ID,
      tenant_id: TENANT_ID,
      claim_case_id: CASE_ID,
      investigator_auth_user_id: ACTOR_ID,
      finding_text: "custody chain confirms carrier handling damage",
      evidence_sufficiency: "sufficient",
      created_by: "investigator",
      created_at: "2026-08-04T00:00:00.000Z",
    });
    assert.equal(row.evidenceSufficiency, "sufficient");
  });
});

describe("parseClaimResponsibilityReview", () => {
  test("maps a proposed (undecided) review", () => {
    const row = parseClaimResponsibilityReview({
      id: REVIEW_ID,
      tenant_id: TENANT_ID,
      claim_case_id: CASE_ID,
      version_number: 1,
      is_current: true,
      proposed_responsibility_party: "carrier",
      proposed_reserve_amount: "2500000.00",
      proposed_currency: "IDR",
      proposed_rationale: "custody log shows carrier-side handling damage",
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
    });
    assert.equal(row.status, "proposed");
    assert.equal(row.finalReserveAmount, null);
  });

  test("maps a masked review row (all money/narrative fields nulled)", () => {
    const row = parseClaimResponsibilityReview({
      id: REVIEW_ID,
      tenant_id: TENANT_ID,
      claim_case_id: CASE_ID,
      version_number: 1,
      is_current: true,
      proposed_responsibility_party: "carrier",
      proposed_reserve_amount: null,
      proposed_currency: null,
      proposed_rationale: null,
      proposed_by_auth_user_id: ACTOR_ID,
      proposed_by: "investigator",
      proposed_at: "2026-08-04T00:00:00.000Z",
      status: "approved",
      decided_by_auth_user_id: ACTOR_ID,
      decided_by: "supervisor",
      decided_at: "2026-08-04T01:00:00.000Z",
      final_responsibility_party: "carrier",
      final_reserve_amount: null,
      final_currency: null,
      decision_notes: null,
      supersedes_review_id: null,
      record_version: 2,
      created_by: "investigator",
      created_at: "2026-08-04T00:00:00.000Z",
      updated_at: "2026-08-04T01:00:00.000Z",
    });
    assert.equal(row.proposedReserveAmount, null);
    assert.equal(row.finalReserveAmount, null);
    assert.equal(row.finalResponsibilityParty, "carrier");
  });
});

describe("parseClaimRecoveryRecord", () => {
  test("maps a recovery row", () => {
    const row = parseClaimRecoveryRecord({
      id: RECOVERY_ID,
      tenant_id: TENANT_ID,
      claim_case_id: CASE_ID,
      recovered_from: "carrier",
      recovered_amount: "2500000.00",
      currency: "IDR",
      recovered_at: "2026-08-05T00:00:00.000Z",
      reference: "CARRIER-REMIT-001",
      corrects_recovery_id: null,
      recorded_by_auth_user_id: ACTOR_ID,
      recorded_by: "rep",
      created_at: "2026-08-05T00:00:00.000Z",
    });
    assert.equal(row.recoveredAmount, 2500000);
    assert.equal(row.correctsRecoveryId, null);
  });

  test("maps a correcting recovery row", () => {
    const row = parseClaimRecoveryRecord({
      id: "f23e4567-e89b-12d3-a456-426614174000",
      tenant_id: TENANT_ID,
      claim_case_id: CASE_ID,
      recovered_from: "carrier",
      recovered_amount: "2000000.00",
      currency: "IDR",
      recovered_at: "2026-08-06T00:00:00.000Z",
      reference: "CARRIER-REMIT-001-CORRECTED",
      corrects_recovery_id: RECOVERY_ID,
      recorded_by_auth_user_id: ACTOR_ID,
      recorded_by: "rep",
      created_at: "2026-08-06T00:00:00.000Z",
    });
    assert.equal(row.correctsRecoveryId, RECOVERY_ID);
  });
});

describe("parseClaimSettlementReadinessEvaluation", () => {
  test("maps a not_ready evaluation with real blockers", () => {
    const row = parseClaimSettlementReadinessEvaluation({
      id: EVALUATION_ID,
      tenant_id: TENANT_ID,
      claim_case_id: CASE_ID,
      version_number: 1,
      is_current: true,
      evaluated_status: "not_ready",
      blockers: [{ code: "no_approved_responsibility_decision" }],
      evidence: { claimItemCount: 1 },
      reevaluation_reason: null,
      supersedes_evaluation_id: null,
      evaluated_by_auth_user_id: ACTOR_ID,
      evaluated_by: "rep",
      record_version: 1,
      created_by: "rep",
      created_at: "2026-08-04T00:00:00.000Z",
      updated_at: "2026-08-04T00:00:00.000Z",
    });
    assert.equal(row.evaluatedStatus, "not_ready");
    assert.equal(row.blockers.length, 1);
    assert.equal(row.blockers[0]?.code, "no_approved_responsibility_decision");
  });

  test("maps a ready evaluation with no blockers", () => {
    const row = parseClaimSettlementReadinessEvaluation({
      id: EVALUATION_ID,
      tenant_id: TENANT_ID,
      claim_case_id: CASE_ID,
      version_number: 2,
      is_current: true,
      evaluated_status: "ready",
      blockers: [],
      evidence: {},
      reevaluation_reason: "responsibility decided",
      supersedes_evaluation_id: EVALUATION_ID,
      evaluated_by_auth_user_id: ACTOR_ID,
      evaluated_by: "rep",
      record_version: 1,
      created_by: "rep",
      created_at: "2026-08-04T00:00:00.000Z",
      updated_at: "2026-08-04T00:00:00.000Z",
    });
    assert.equal(row.evaluatedStatus, "ready");
    assert.deepEqual(row.blockers, []);
  });
});

describe("parseClaimSettlementReadinessHandoff", () => {
  test("maps an un-reconciled handoff", () => {
    const row = parseClaimSettlementReadinessHandoff({
      id: HANDOFF_ID,
      tenant_id: TENANT_ID,
      claim_case_id: CASE_ID,
      evaluation_id: EVALUATION_ID,
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
    });
    assert.equal(row.reconciliationStatus, null);
    assert.equal(row.handoffSeq, 1);
  });

  test("maps a reconciled handoff, coercing a string-typed bigint handoff_seq", () => {
    const row = parseClaimSettlementReadinessHandoff({
      id: HANDOFF_ID,
      tenant_id: TENANT_ID,
      claim_case_id: CASE_ID,
      evaluation_id: EVALUATION_ID,
      idempotency_key: "idem-handoff-1",
      handed_off_by_auth_user_id: ACTOR_ID,
      handed_off_by: "rep",
      handed_off_at: "2026-08-04T00:00:00.000Z",
      handoff_seq: "2",
      reconciliation_status: "reconciled",
      reconciliation_note: "posted",
      reconciled_at: "2026-08-04T02:00:00.000Z",
      updated_at: "2026-08-04T02:00:00.000Z",
      created_at: "2026-08-04T00:00:00.000Z",
    });
    assert.equal(row.reconciliationStatus, "reconciled");
    assert.equal(row.reconciliationNote, "posted");
    assert.equal(row.handoffSeq, 2);
  });
});

describe("ClaimContactSnapshotSchema", () => {
  test("accepts name/phone/email only", () => {
    const parsed = ClaimContactSnapshotSchema.parse({ name: "Alice", phone: "0811", email: "alice@example.test" });
    assert.equal(parsed.name, "Alice");
  });

  test("rejects an extra, non-minimized key", () => {
    assert.throws(() => ClaimContactSnapshotSchema.parse({ name: "Alice", address: "Jl. Sudirman 1" }));
  });
});

describe("OpenClaimCaseInputSchema", () => {
  test("parses a minimal customer claimant input", () => {
    const parsed = OpenClaimCaseInputSchema.parse({
      operationalExceptionId: EXCEPTION_ID,
      claimantType: "customer",
      claimantAccountId: ACCOUNT_ID,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(parsed.claimantType, "customer");
  });

  test("rejects an unrecognized claimantType", () => {
    assert.throws(() =>
      OpenClaimCaseInputSchema.parse({
        operationalExceptionId: EXCEPTION_ID,
        claimantType: "insurer",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });
});

describe("AddClaimItemInputSchema", () => {
  test("requires a positive declaredQuantity", () => {
    assert.throws(() =>
      AddClaimItemInputSchema.parse({
        caseId: CASE_ID,
        itemType: "inventory",
        declaredQuantity: 0,
        uomCode: "PCS",
        description: "damaged",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });

  test("requires a non-empty description", () => {
    assert.throws(() =>
      AddClaimItemInputSchema.parse({
        caseId: CASE_ID,
        itemType: "inventory",
        declaredQuantity: 1,
        uomCode: "PCS",
        description: "",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });
});

describe("LinkClaimEvidenceInputSchema", () => {
  test("accepts every fixed evidence type", () => {
    for (const evidenceType of ["shipment_leg", "shipment_leg_custody_event", "inventory_movement", "wms_outbound_shipment", "epod_capture", "file"] as const) {
      const parsed = LinkClaimEvidenceInputSchema.parse({
        caseId: CASE_ID,
        evidenceType,
        evidenceId: EVIDENCE_ID,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      });
      assert.equal(parsed.evidenceType, evidenceType);
    }
  });

  test("rejects an evidence type outside the fixed 6-value enum", () => {
    assert.throws(() =>
      LinkClaimEvidenceInputSchema.parse({
        caseId: CASE_ID,
        evidenceType: "wms_receipt_line",
        evidenceId: EVIDENCE_ID,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });
});

describe("DecideClaimResponsibilityInputSchema", () => {
  test("accepts a denied decision with no final party/amount", () => {
    const parsed = DecideClaimResponsibilityInputSchema.parse({
      reviewId: REVIEW_ID,
      expectedVersion: 1,
      decision: "denied",
      decisionNotes: "insufficient evidence of carrier fault",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "supervisor",
    });
    assert.equal(parsed.decision, "denied");
  });

  test("rejects an unrecognized decision value", () => {
    assert.throws(() =>
      DecideClaimResponsibilityInputSchema.parse({
        reviewId: REVIEW_ID,
        expectedVersion: 1,
        decision: "escalated",
        decisionNotes: "x",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "supervisor",
      }),
    );
  });
});

describe("RecordClaimRecoveryInputSchema", () => {
  test("requires a positive recoveredAmount", () => {
    assert.throws(() =>
      RecordClaimRecoveryInputSchema.parse({
        caseId: CASE_ID,
        recoveredFrom: "carrier",
        recoveredAmount: 0,
        currency: "IDR",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });

  test("requires a 3-letter currency code", () => {
    assert.throws(() =>
      RecordClaimRecoveryInputSchema.parse({
        caseId: CASE_ID,
        recoveredFrom: "carrier",
        recoveredAmount: 100,
        currency: "RUPIAH",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });
});

describe("RecordClaimFinanceReconciliationOutcomeInputSchema", () => {
  test("accepts a rejected outcome with a note", () => {
    const parsed = RecordClaimFinanceReconciliationOutcomeInputSchema.parse({
      handoffId: HANDOFF_ID,
      status: "rejected",
      note: "amount mismatch",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "finance-worker",
    });
    assert.equal(parsed.status, "rejected");
  });

  test("requires a non-empty note", () => {
    assert.throws(() =>
      RecordClaimFinanceReconciliationOutcomeInputSchema.parse({
        handoffId: HANDOFF_ID,
        status: "reconciled",
        note: "",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "finance-worker",
      }),
    );
  });
});

describe("ListClaimCasesInputSchema", () => {
  test("accepts filters and cursor pagination fields", () => {
    const parsed = ListClaimCasesInputSchema.parse({
      tenantId: TENANT_ID,
      actorAuthUserId: ACTOR_ID,
      claimStageFilter: "investigating",
      shipmentOrderIdFilter: SHIPMENT_ID,
      cursorUpdatedAt: "2026-08-04T00:00:00.000Z",
      cursorId: CASE_ID,
      limit: 25,
    });
    assert.equal(parsed.claimStageFilter, "investigating");
    assert.equal(parsed.limit, 25);
  });

  test("defaults every filter to unset", () => {
    const parsed = ListClaimCasesInputSchema.parse({ tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(parsed.claimStageFilter, undefined);
  });
});
