import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  getClaimCase,
  listClaimCases,
  listClaimItems,
  listClaimEvidence,
  getClaimInvestigationHistory,
  getClaimResponsibilityReview,
  listClaimRecoveryRecords,
  getClaimSettlementReadiness,
  listClaimSettlementReadinessHandoffs,
  ClaimIncidentQueryError,
  type ClaimIncidentQueryClient,
} from "./claim-incident.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const CASE_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const EXCEPTION_ID = "323e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "d23e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: ClaimIncidentQueryClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as ClaimIncidentQueryClient;
  return { client, calls };
}

const CASE_ROW = {
  id: CASE_ID,
  tenant_id: TENANT_ID,
  operational_exception_id: EXCEPTION_ID,
  claimant_type: "customer",
  claimant_account_id: null,
  claimant_label: "Acme Shipper",
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

const CASE_LIST_ROW = {
  id: CASE_ID,
  tenant_id: TENANT_ID,
  operational_exception_id: EXCEPTION_ID,
  claimant_type: "customer",
  claimant_account_id: null,
  claimant_label: "Acme Shipper",
  claim_stage: "intake",
  opened_by: "rep",
  opened_at: "2026-08-04T00:00:00.000Z",
  closure_basis: null,
  closed_at: null,
  record_version: 1,
  updated_at: "2026-08-04T00:00:00.000Z",
  exception_type: "damage",
  exception_severity: "high",
  exception_status: "open",
  shipment_order_id: SHIPMENT_ID,
};

describe("getClaimCase", () => {
  test("calls get_claim_case with p_-prefixed args", async () => {
    const { client, calls } = fakeRpcClient({ data: [CASE_ROW], error: null });
    const row = await getClaimCase(client, CASE_ID, ACTOR_ID);
    assert.equal(calls[0]?.fn, "get_claim_case");
    assert.equal(calls[0]?.args.p_case_id, CASE_ID);
    assert.equal(calls[0]?.args.p_actor_auth_user_id, ACTOR_ID);
    assert.equal(row.id, CASE_ID);
  });

  test("throws ClaimIncidentQueryError on an RPC error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "claim_case_not_found: x" } });
    await assert.rejects(() => getClaimCase(client, CASE_ID, ACTOR_ID), ClaimIncidentQueryError);
  });

  test("throws when the RPC returns no row", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    await assert.rejects(() => getClaimCase(client, CASE_ID, ACTOR_ID), ClaimIncidentQueryError);
  });
});

describe("listClaimCases", () => {
  test("passes cursor and filter args through with p_ prefixes", async () => {
    const { client, calls } = fakeRpcClient({ data: [CASE_LIST_ROW], error: null });
    const rows = await listClaimCases(client, {
      tenantId: TENANT_ID,
      actorAuthUserId: ACTOR_ID,
      claimStageFilter: "intake",
      cursorUpdatedAt: "2026-08-04T00:00:00.000Z",
      cursorId: CASE_ID,
      limit: 10,
    });
    assert.equal(calls[0]?.fn, "list_claim_cases");
    assert.equal(calls[0]?.args.p_claim_stage_filter, "intake");
    assert.equal(calls[0]?.args.p_cursor_id, CASE_ID);
    assert.equal(calls[0]?.args.p_limit, 10);
    assert.equal(rows[0]?.exceptionType, "damage");
    assert.equal(rows[0]?.shipmentOrderId, SHIPMENT_ID);
  });

  test("defaults p_limit to 50 and every filter to null", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await listClaimCases(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(calls[0]?.args.p_limit, 50);
    assert.equal(calls[0]?.args.p_claim_stage_filter, null);
    assert.equal(calls[0]?.args.p_cursor_id, null);
  });

  test("returns an empty array when data is null", async () => {
    const { client } = fakeRpcClient({ data: null, error: null });
    const rows = await listClaimCases(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID });
    assert.deepEqual(rows, []);
  });
});

describe("listClaimItems", () => {
  test("calls list_claim_items and maps rows", async () => {
    const { client, calls } = fakeRpcClient({
      data: [
        {
          id: "723e4567-e89b-12d3-a456-426614174000",
          tenant_id: TENANT_ID,
          claim_case_id: CASE_ID,
          item_type: "inventory",
          linked_inventory_movement_id: null,
          linked_wms_outbound_shipment_id: null,
          item_master_id: null,
          declared_quantity: "5",
          uom_code: "PCS",
          declared_value: null,
          currency: null,
          description: "masked row",
          status: "active",
          withdrawn_at: null,
          withdrawn_by: null,
          withdrawal_reason: null,
          record_version: 1,
          created_by: "rep",
          created_at: "2026-08-04T00:00:00.000Z",
          updated_at: "2026-08-04T00:00:00.000Z",
        },
      ],
      error: null,
    });
    const rows = await listClaimItems(client, CASE_ID, ACTOR_ID);
    assert.equal(calls[0]?.fn, "list_claim_items");
    assert.equal(rows[0]?.declaredQuantity, 5);
    assert.equal(rows[0]?.declaredValue, null);
  });
});

describe("listClaimEvidence", () => {
  test("calls list_claim_evidence and maps rows", async () => {
    const { client } = fakeRpcClient({
      data: [
        {
          id: "823e4567-e89b-12d3-a456-426614174000",
          tenant_id: TENANT_ID,
          claim_case_id: CASE_ID,
          evidence_type: "epod_capture",
          evidence_id: "923e4567-e89b-12d3-a456-426614174000",
          note: null,
          added_by_auth_user_id: ACTOR_ID,
          added_by: "rep",
          added_at: "2026-08-04T00:00:00.000Z",
        },
      ],
      error: null,
    });
    const rows = await listClaimEvidence(client, CASE_ID, ACTOR_ID);
    assert.equal(rows[0]?.evidenceType, "epod_capture");
  });
});

describe("getClaimInvestigationHistory", () => {
  test("calls get_claim_investigation_history and maps rows", async () => {
    const { client } = fakeRpcClient({
      data: [
        {
          id: "a23e4567-e89b-12d3-a456-426614174000",
          tenant_id: TENANT_ID,
          claim_case_id: CASE_ID,
          investigator_auth_user_id: ACTOR_ID,
          finding_text: "evidence sufficient",
          evidence_sufficiency: "sufficient",
          created_by: "investigator",
          created_at: "2026-08-04T00:00:00.000Z",
        },
      ],
      error: null,
    });
    const rows = await getClaimInvestigationHistory(client, CASE_ID, ACTOR_ID);
    assert.equal(rows.length, 1);
    assert.equal(rows[0]?.evidenceSufficiency, "sufficient");
  });
});

describe("getClaimResponsibilityReview", () => {
  test("calls get_claim_responsibility_review and maps the current row", async () => {
    const { client, calls } = fakeRpcClient({
      data: [
        {
          id: "b23e4567-e89b-12d3-a456-426614174000",
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
        },
      ],
      error: null,
    });
    const row = await getClaimResponsibilityReview(client, CASE_ID, ACTOR_ID);
    assert.equal(calls[0]?.fn, "get_claim_responsibility_review");
    assert.equal(row.status, "proposed");
  });

  test("throws when no current review exists", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "claim_responsibility_review_not_found: x" } });
    await assert.rejects(() => getClaimResponsibilityReview(client, CASE_ID, ACTOR_ID), ClaimIncidentQueryError);
  });
});

describe("listClaimRecoveryRecords", () => {
  test("calls list_claim_recovery_records and maps rows", async () => {
    const { client } = fakeRpcClient({
      data: [
        {
          id: "c23e4567-e89b-12d3-a456-426614174000",
          tenant_id: TENANT_ID,
          claim_case_id: CASE_ID,
          recovered_from: "carrier",
          recovered_amount: "1000000.00",
          currency: "IDR",
          recovered_at: "2026-08-05T00:00:00.000Z",
          reference: null,
          corrects_recovery_id: null,
          recorded_by_auth_user_id: ACTOR_ID,
          recorded_by: "rep",
          created_at: "2026-08-05T00:00:00.000Z",
        },
      ],
      error: null,
    });
    const rows = await listClaimRecoveryRecords(client, CASE_ID, ACTOR_ID, 25);
    assert.equal(rows[0]?.recoveredAmount, 1000000);
  });
});

describe("getClaimSettlementReadiness", () => {
  test("calls get_claim_settlement_readiness and maps the current evaluation", async () => {
    const { client, calls } = fakeRpcClient({
      data: [
        {
          id: "e23e4567-e89b-12d3-a456-426614174000",
          tenant_id: TENANT_ID,
          claim_case_id: CASE_ID,
          version_number: 1,
          is_current: true,
          evaluated_status: "ready",
          blockers: [],
          evidence: { claimItemCount: 1, currentReviewStatus: "approved", finalResponsibilityParty: "carrier" },
          reevaluation_reason: null,
          supersedes_evaluation_id: null,
          evaluated_by_auth_user_id: ACTOR_ID,
          evaluated_by: "rep",
          record_version: 1,
          created_by: "rep",
          created_at: "2026-08-04T00:00:00.000Z",
          updated_at: "2026-08-04T00:00:00.000Z",
        },
      ],
      error: null,
    });
    const row = await getClaimSettlementReadiness(client, CASE_ID, ACTOR_ID);
    assert.equal(calls[0]?.fn, "get_claim_settlement_readiness");
    assert.equal(row.evaluatedStatus, "ready");
    assert.equal(row.evidence.finalResponsibilityParty, "carrier");
  });

  test("maps a masked evaluation (evidence.finalReserveAmount stripped)", async () => {
    const { client } = fakeRpcClient({
      data: [
        {
          id: "e23e4567-e89b-12d3-a456-426614174000",
          tenant_id: TENANT_ID,
          claim_case_id: CASE_ID,
          version_number: 1,
          is_current: true,
          evaluated_status: "not_ready",
          blockers: [{ code: "no_recovery_records_yet" }],
          evidence: { claimItemCount: 1, currentReviewStatus: "approved", finalResponsibilityParty: "carrier" },
          reevaluation_reason: null,
          supersedes_evaluation_id: null,
          evaluated_by_auth_user_id: ACTOR_ID,
          evaluated_by: "rep",
          record_version: 1,
          created_by: "rep",
          created_at: "2026-08-04T00:00:00.000Z",
          updated_at: "2026-08-04T00:00:00.000Z",
        },
      ],
      error: null,
    });
    const row = await getClaimSettlementReadiness(client, CASE_ID, ACTOR_ID);
    assert.equal(row.evidence.finalReserveAmount, undefined);
    assert.equal(row.evidence.finalResponsibilityParty, "carrier");
  });

  test("throws when the RPC returns no row", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    await assert.rejects(() => getClaimSettlementReadiness(client, CASE_ID, ACTOR_ID), ClaimIncidentQueryError);
  });
});

describe("listClaimSettlementReadinessHandoffs", () => {
  test("calls list_claim_settlement_readiness_handoffs and maps rows, ordered by handoffSeq", async () => {
    const { client, calls } = fakeRpcClient({
      data: [
        {
          id: "c23e4567-e89b-12d3-a456-426614174000",
          tenant_id: TENANT_ID,
          claim_case_id: CASE_ID,
          evaluation_id: "e23e4567-e89b-12d3-a456-426614174000",
          idempotency_key: "idem-handoff-2",
          handed_off_by_auth_user_id: ACTOR_ID,
          handed_off_by: "rep",
          handed_off_at: "2026-08-04T01:00:00.000Z",
          handoff_seq: "2",
          reconciliation_status: "reconciled",
          reconciliation_note: "posted",
          reconciled_at: "2026-08-04T02:00:00.000Z",
          updated_at: "2026-08-04T02:00:00.000Z",
          created_at: "2026-08-04T01:00:00.000Z",
        },
        {
          id: "d23e4567-e89b-12d3-a456-426614174000",
          tenant_id: TENANT_ID,
          claim_case_id: CASE_ID,
          evaluation_id: "e23e4567-e89b-12d3-a456-426614174000",
          idempotency_key: "idem-handoff-1",
          handed_off_by_auth_user_id: ACTOR_ID,
          handed_off_by: "rep",
          handed_off_at: "2026-08-04T00:00:00.000Z",
          handoff_seq: "1",
          reconciliation_status: "rejected",
          reconciliation_note: "amount mismatch",
          reconciled_at: "2026-08-04T00:30:00.000Z",
          updated_at: "2026-08-04T00:30:00.000Z",
          created_at: "2026-08-04T00:00:00.000Z",
        },
      ],
      error: null,
    });
    const rows = await listClaimSettlementReadinessHandoffs(client, CASE_ID, ACTOR_ID, 25);
    assert.equal(calls[0]?.fn, "list_claim_settlement_readiness_handoffs");
    assert.equal(calls[0]?.args.p_limit, 25);
    assert.equal(rows[0]?.handoffSeq, 2);
    assert.equal(rows[1]?.handoffSeq, 1);
  });

  test("returns an empty array when data is null", async () => {
    const { client } = fakeRpcClient({ data: null, error: null });
    const rows = await listClaimSettlementReadinessHandoffs(client, CASE_ID, ACTOR_ID);
    assert.deepEqual(rows, []);
  });
});
