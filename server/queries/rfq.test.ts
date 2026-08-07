import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { getRfq, listRfqs, listRfqInvitations, listRfqResponses, RfqQueryError, type RfqQueryRpcClient } from "./rfq.ts";

const RFQ_ID = "323e4567-e89b-12d3-a456-426614174000";
const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "823e4567-e89b-12d3-a456-426614174000";

const VALID_RFQ_ROW = {
  id: RFQ_ID,
  tenant_id: TENANT_ID,
  org_unit_id: null,
  sourcing_request_id: "423e4567-e89b-12d3-a456-426614174000",
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

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }, calls: { fn: string; args: Record<string, unknown> }[]): RfqQueryRpcClient {
  return {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as RfqQueryRpcClient;
}

describe("getRfq", () => {
  test("calls get_rfq with p_rfq_id/p_actor_auth_user_id and parses the row", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: VALID_RFQ_ROW, error: null }, calls);

    const rfq = await getRfq(client, RFQ_ID, ACTOR_ID);

    assert.equal(calls[0]?.fn, "get_rfq");
    assert.equal(calls[0]?.args.p_rfq_id, RFQ_ID);
    assert.equal(rfq.id, RFQ_ID);
  });

  test("throws RfqQueryError on a rfq_not_found error", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "rfq_not_found: 323e4567-e89b-12d3-a456-426614174000" } }, []);
    await assert.rejects(
      () => getRfq(client, RFQ_ID, ACTOR_ID),
      (err: unknown) => {
        assert.ok(err instanceof RfqQueryError);
        return true;
      },
    );
  });
});

describe("listRfqs", () => {
  test("passes p_status/p_limit through and returns an empty array on null data", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: null, error: null }, calls);

    const rfqs = await listRfqs(client, TENANT_ID, ACTOR_ID, "issued", 25);

    assert.equal(calls[0]?.fn, "list_rfqs");
    assert.equal(calls[0]?.args.p_status, "issued");
    assert.equal(calls[0]?.args.p_limit, 25);
    assert.deepEqual(rfqs, []);
  });
});

describe("listRfqInvitations", () => {
  test("calls list_rfq_invitations and parses every row", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient(
      {
        data: [
          {
            id: "523e4567-e89b-12d3-a456-426614174000",
            tenant_id: TENANT_ID,
            rfq_id: RFQ_ID,
            sourcing_candidate_id: "623e4567-e89b-12d3-a456-426614174000",
            vendor_master_id: "723e4567-e89b-12d3-a456-426614174000",
            status: "invited",
            invited_at: "2026-08-01T00:00:00.000Z",
            invited_by: "staff",
            decline_reason: null,
            declined_at: null,
            record_version: 1,
            created_at: "2026-08-01T00:00:00.000Z",
            updated_at: "2026-08-01T00:00:00.000Z",
          },
        ],
        error: null,
      },
      calls,
    );

    const invitations = await listRfqInvitations(client, RFQ_ID, ACTOR_ID);

    assert.equal(calls[0]?.fn, "list_rfq_invitations");
    assert.equal(invitations.length, 1);
    assert.equal(invitations[0]?.status, "invited");
  });
});

describe("listRfqResponses", () => {
  test("returns masked rows unchanged (masking itself is server-side, this is a pass-through)", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient(
      {
        data: [
          {
            id: "923e4567-e89b-12d3-a456-426614174000",
            tenant_id: TENANT_ID,
            rfq_id: RFQ_ID,
            rfq_invitation_id: "523e4567-e89b-12d3-a456-426614174000",
            vendor_master_id: "723e4567-e89b-12d3-a456-426614174000",
            version: 1,
            previous_version_id: null,
            status: "submitted",
            currency: null,
            total_amount: null,
            validity_until: null,
            lead_time_days: 7,
            commercial_terms: {},
            cost_masked: true,
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
          },
        ],
        error: null,
      },
      calls,
    );

    const responses = await listRfqResponses(client, RFQ_ID, ACTOR_ID);

    assert.equal(calls[0]?.fn, "list_rfq_responses");
    assert.equal(responses[0]?.costMasked, true);
    assert.equal(responses[0]?.totalAmount, null);
  });
});
