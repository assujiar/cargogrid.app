import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  draftRfqFromSourcing,
  reviseRfq,
  issueRfq,
  inviteAdditionalRfqVendor,
  submitRfqResponse,
  withdrawRfqResponse,
  RfqMutationError,
  type RfqMutationRpcClient,
} from "./rfq.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const RFQ_ID = "323e4567-e89b-12d3-a456-426614174000";
const SOURCING_REQUEST_ID = "423e4567-e89b-12d3-a456-426614174000";
const CANDIDATE_ID = "623e4567-e89b-12d3-a456-426614174000";
const VENDOR_MASTER_ID = "723e4567-e89b-12d3-a456-426614174000";
const INVITATION_ID = "523e4567-e89b-12d3-a456-426614174000";
const RESPONSE_ID = "923e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "823e4567-e89b-12d3-a456-426614174000";

const VALID_RFQ_ROW = {
  id: RFQ_ID,
  tenant_id: TENANT_ID,
  org_unit_id: null,
  sourcing_request_id: SOURCING_REQUEST_ID,
  rfq_number: "RFQ-2026-000001",
  version: 1,
  revised_from_id: null,
  requirements_snapshot: {},
  service_type: "ocean_freight",
  mode: "FCL",
  origin_lane: "Jakarta",
  destination_lane: "Surabaya",
  cargo_weight_min: null,
  cargo_weight_max: null,
  cargo_volume_min: null,
  cargo_volume_max: null,
  currency: "IDR",
  status: "draft",
  issued_at: null,
  response_deadline_at: null,
  closed_at: null,
  closed_reason: null,
  owner_user_id: ACTOR_ID,
  idempotency_key: "idem-1",
  record_version: 1,
  created_by: "tester",
  created_at: "2026-08-01T00:00:00.000Z",
  updated_at: "2026-08-01T00:00:00.000Z",
};

const VALID_INVITATION_ROW = {
  id: INVITATION_ID,
  tenant_id: TENANT_ID,
  rfq_id: RFQ_ID,
  sourcing_candidate_id: CANDIDATE_ID,
  vendor_master_id: VENDOR_MASTER_ID,
  status: "invited",
  invited_at: "2026-08-01T00:00:00.000Z",
  invited_by: "staff",
  decline_reason: null,
  declined_at: null,
  record_version: 1,
  created_at: "2026-08-01T00:00:00.000Z",
  updated_at: "2026-08-01T00:00:00.000Z",
};

const VALID_RESPONSE_ROW = {
  id: RESPONSE_ID,
  tenant_id: TENANT_ID,
  rfq_id: RFQ_ID,
  rfq_invitation_id: INVITATION_ID,
  vendor_master_id: VENDOR_MASTER_ID,
  version: 1,
  previous_version_id: null,
  status: "submitted",
  currency: "IDR",
  total_amount: 12000000,
  validity_until: null,
  lead_time_days: null,
  commercial_terms: {},
  capture_mode: "offline",
  source_message_ref: null,
  received_at: "2026-08-05T00:00:00.000Z",
  vendor_confirmed: true,
  late_capture: false,
  late_reason: null,
  comparison_eligible: true,
  idempotency_key: "idem-resp-1",
  actor_auth_user_id: ACTOR_ID,
  actor_label: "staff",
  record_version: 1,
  created_at: "2026-08-05T00:00:00.000Z",
  updated_at: "2026-08-05T00:00:00.000Z",
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }, calls: { fn: string; args: Record<string, unknown> }[]): RfqMutationRpcClient {
  return {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as RfqMutationRpcClient;
}

describe("draftRfqFromSourcing", () => {
  test("calls draft_rfq_from_sourcing with the exact snake_case params", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: VALID_RFQ_ROW, error: null }, calls);

    const rfq = await draftRfqFromSourcing(client, { tenantId: TENANT_ID, sourcingRequestId: SOURCING_REQUEST_ID, idempotencyKey: "idem-1", actorAuthUserId: ACTOR_ID, actorLabel: "tester" });

    assert.equal(calls[0]?.fn, "draft_rfq_from_sourcing");
    assert.equal(calls[0]?.args.p_sourcing_request_id, SOURCING_REQUEST_ID);
    assert.equal(rfq.sourcingRequestId, SOURCING_REQUEST_ID);
  });

  test("classifies invalid_source_status via the generic prefix classifier", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "invalid_source_status: sourcing request x is open" } }, []);
    await assert.rejects(
      () => draftRfqFromSourcing(client, { tenantId: TENANT_ID, sourcingRequestId: SOURCING_REQUEST_ID, idempotencyKey: "idem-1", actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof RfqMutationError);
        assert.equal(err.code, "invalid_source_status");
        return true;
      },
    );
  });

  test("an unrecognized error message classifies as mutation_failed", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "some_unexpected_postgres_error: detail" } }, []);
    await assert.rejects(
      () => draftRfqFromSourcing(client, { tenantId: TENANT_ID, sourcingRequestId: SOURCING_REQUEST_ID, idempotencyKey: "idem-1", actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof RfqMutationError);
        assert.equal(err.code, "mutation_failed");
        return true;
      },
    );
  });
});

describe("reviseRfq", () => {
  test("passes the override fields and reason/idempotencyKey through", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: { ...VALID_RFQ_ROW, version: 2, revised_from_id: RFQ_ID }, error: null }, calls);

    const rfq = await reviseRfq(client, {
      rfqId: RFQ_ID,
      cargoWeightMax: 6000,
      reason: "shipper increased cargo weight",
      idempotencyKey: "idem-revise-1",
      expectedVersion: 1,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
    });

    assert.equal(calls[0]?.fn, "revise_rfq");
    assert.equal(calls[0]?.args.p_cargo_weight_max, 6000);
    assert.equal(calls[0]?.args.p_reason, "shipper increased cargo weight");
    assert.equal(rfq.version, 2);
  });
});

describe("issueRfq", () => {
  test("classifies no_shortlisted_vendors", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "no_shortlisted_vendors: sourcing request x has no shortlisted candidates to invite" } }, []);
    await assert.rejects(
      () => issueRfq(client, { rfqId: RFQ_ID, responseDeadlineAt: "2026-09-01T00:00:00.000Z", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof RfqMutationError);
        assert.equal(err.code, "no_shortlisted_vendors");
        return true;
      },
    );
  });

  test("calls issue_rfq and returns status=issued", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: { ...VALID_RFQ_ROW, status: "issued", issued_at: "2026-08-02T00:00:00.000Z", response_deadline_at: "2026-09-01T00:00:00.000Z" }, error: null }, calls);

    const rfq = await issueRfq(client, { rfqId: RFQ_ID, responseDeadlineAt: "2026-09-01T00:00:00.000Z", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "tester" });

    assert.equal(calls[0]?.fn, "issue_rfq");
    assert.equal(rfq.status, "issued");
  });
});

describe("inviteAdditionalRfqVendor", () => {
  test("classifies ineligible_vendor", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "ineligible_vendor: candidate x is not eligible and cannot be invited" } }, []);
    await assert.rejects(
      () => inviteAdditionalRfqVendor(client, { rfqId: RFQ_ID, sourcingCandidateId: CANDIDATE_ID, reason: "need more coverage", actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof RfqMutationError);
        assert.equal(err.code, "ineligible_vendor");
        return true;
      },
    );
  });

  test("calls invite_additional_rfq_vendor with p_reason", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: VALID_INVITATION_ROW, error: null }, calls);

    const invitation = await inviteAdditionalRfqVendor(client, { rfqId: RFQ_ID, sourcingCandidateId: CANDIDATE_ID, reason: "need more coverage", actorAuthUserId: ACTOR_ID, actorLabel: "tester" });

    assert.equal(calls[0]?.fn, "invite_additional_rfq_vendor");
    assert.equal(calls[0]?.args.p_reason, "need more coverage");
    assert.equal(invitation.status, "invited");
  });
});

describe("submitRfqResponse", () => {
  test("passes every field including fileIds/lateReason through", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: VALID_RESPONSE_ROW, error: null }, calls);

    await submitRfqResponse(client, {
      rfqInvitationId: INVITATION_ID,
      currency: "IDR",
      totalAmount: 12000000,
      receivedAt: "2026-08-05T00:00:00.000Z",
      fileIds: ["a23e4567-e89b-12d3-a456-426614174000"],
      idempotencyKey: "idem-resp-1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
    });

    assert.equal(calls[0]?.fn, "submit_rfq_response");
    assert.equal(calls[0]?.args.p_total_amount, 12000000);
    assert.deepEqual(calls[0]?.args.p_file_ids, ["a23e4567-e89b-12d3-a456-426614174000"]);
    assert.equal(calls[0]?.args.p_capture_mode, "offline");
  });

  test("classifies late_reason_required", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "late_reason_required: a reason is required to capture a response received after the deadline" } }, []);
    await assert.rejects(
      () =>
        submitRfqResponse(client, {
          rfqInvitationId: INVITATION_ID,
          currency: "IDR",
          totalAmount: 12000000,
          receivedAt: "2026-08-05T00:00:00.000Z",
          idempotencyKey: "idem-resp-1",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "tester",
        }),
      (err: unknown) => {
        assert.ok(err instanceof RfqMutationError);
        assert.equal(err.code, "late_reason_required");
        return true;
      },
    );
  });
});

describe("withdrawRfqResponse", () => {
  test("classifies not_latest_response_version", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "not_latest_response_version: a newer response version exists for this invitation" } }, []);
    await assert.rejects(
      () => withdrawRfqResponse(client, { rfqResponseId: RESPONSE_ID, reason: "correction", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof RfqMutationError);
        assert.equal(err.code, "not_latest_response_version");
        return true;
      },
    );
  });

  test("calls withdraw_rfq_response and returns status=withdrawn", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: { ...VALID_RESPONSE_ROW, status: "withdrawn" }, error: null }, calls);

    const response = await withdrawRfqResponse(client, { rfqResponseId: RESPONSE_ID, reason: "correction", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "tester" });

    assert.equal(calls[0]?.fn, "withdraw_rfq_response");
    assert.equal(response.status, "withdrawn");
  });
});
