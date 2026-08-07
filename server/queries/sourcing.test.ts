import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { getSourcingRequest, listSourcingRequests, listSourcingCandidates, getSourcingRequestHistory, SourcingQueryError, type SourcingQueryRpcClient } from "./sourcing.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "323e4567-e89b-12d3-a456-426614174000";
const CANDIDATE_ID = "423e4567-e89b-12d3-a456-426614174000";
const VENDOR_MASTER_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

const VALID_REQUEST_ROW = {
  id: REQUEST_ID,
  tenant_id: TENANT_ID,
  org_unit_id: null,
  source_type: "proactive",
  source_costing_request_id: null,
  source_shipment_order_id: null,
  demand_snapshot: {},
  service_type: "ocean_freight",
  mode: "FCL",
  origin_lane: "Jakarta",
  destination_lane: "Surabaya",
  cargo_weight_min: null,
  cargo_weight_max: null,
  cargo_volume_min: null,
  cargo_volume_max: null,
  requested_pickup_at: null,
  requested_delivery_at: null,
  currency: "IDR",
  budget_amount: null,
  cost_masked: true,
  status: "open",
  owner_user_id: ACTOR_ID,
  sla_due_at: null,
  closed_reason: null,
  shortlist_locked_at: null,
  record_version: 1,
  created_by: "tester",
  created_at: "2026-08-01T00:00:00.000Z",
  updated_at: "2026-08-01T00:00:00.000Z",
};

const VALID_CANDIDATE_ROW = {
  id: CANDIDATE_ID,
  tenant_id: TENANT_ID,
  sourcing_request_id: REQUEST_ID,
  vendor_master_id: VENDOR_MASTER_ID,
  eligible: true,
  exclusion_reasons: [],
  evaluation_snapshot: {},
  shortlisted: false,
  shortlist_reason: null,
  shortlisted_by: null,
  shortlisted_at: null,
  record_version: 1,
  created_at: "2026-08-01T00:00:00.000Z",
  updated_at: "2026-08-01T00:00:00.000Z",
};

const VALID_EVENT_ROW = {
  id: "723e4567-e89b-12d3-a456-426614174000",
  tenant_id: TENANT_ID,
  sourcing_request_id: REQUEST_ID,
  from_status: "none",
  to_status: "open",
  reason: null,
  evidence_ref: null,
  actor_auth_user_id: ACTOR_ID,
  actor_label: "tester",
  occurred_at: "2026-08-01T00:00:00.000Z",
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }, calls: { fn: string; args: Record<string, unknown> }[]): SourcingQueryRpcClient {
  return {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as SourcingQueryRpcClient;
}

describe("getSourcingRequest", () => {
  test("calls get_sourcing_request with the exact snake_case params and parses the masked row", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: VALID_REQUEST_ROW, error: null }, calls);

    const request = await getSourcingRequest(client, REQUEST_ID, ACTOR_ID);

    assert.equal(calls[0]?.fn, "get_sourcing_request");
    assert.equal(calls[0]?.args.p_sourcing_request_id, REQUEST_ID);
    assert.equal(calls[0]?.args.p_actor_auth_user_id, ACTOR_ID);
    assert.equal(request.id, REQUEST_ID);
    assert.equal(request.costMasked, true);
  });

  test("throws SourcingQueryError on a real RPC error (e.g. insufficient_privilege)", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity x lacks PRC:View (no_active_assignment) for tenant y" } }, []);
    await assert.rejects(() => getSourcingRequest(client, REQUEST_ID, ACTOR_ID), SourcingQueryError);
  });

  test("throws SourcingQueryError when the RPC returns no row", async () => {
    const client = fakeRpcClient({ data: null, error: null }, []);
    await assert.rejects(() => getSourcingRequest(client, REQUEST_ID, ACTOR_ID), SourcingQueryError);
  });
});

describe("listSourcingRequests", () => {
  test("passes tenantId/status/limit through as p_ params", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: [VALID_REQUEST_ROW], error: null }, calls);

    const rows = await listSourcingRequests(client, TENANT_ID, ACTOR_ID, "open", 25);

    assert.equal(calls[0]?.fn, "list_sourcing_requests");
    assert.equal(calls[0]?.args.p_tenant_id, TENANT_ID);
    assert.equal(calls[0]?.args.p_status, "open");
    assert.equal(calls[0]?.args.p_limit, 25);
    assert.equal(rows.length, 1);
  });

  test("defaults status to null and limit to the default page size when omitted", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: [], error: null }, calls);

    await listSourcingRequests(client, TENANT_ID, ACTOR_ID);

    assert.equal(calls[0]?.args.p_status, null);
    assert.equal(calls[0]?.args.p_limit, 50);
  });

  test("returns an empty array (not an error) when the RPC returns null data", async () => {
    const client = fakeRpcClient({ data: null, error: null }, []);
    const rows = await listSourcingRequests(client, TENANT_ID, ACTOR_ID);
    assert.deepEqual(rows, []);
  });
});

describe("listSourcingCandidates", () => {
  test("calls list_sourcing_candidates and parses every row", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: [VALID_CANDIDATE_ROW], error: null }, calls);

    const rows = await listSourcingCandidates(client, REQUEST_ID, ACTOR_ID);

    assert.equal(calls[0]?.fn, "list_sourcing_candidates");
    assert.equal(calls[0]?.args.p_sourcing_request_id, REQUEST_ID);
    assert.equal(rows[0]?.id, CANDIDATE_ID);
  });
});

describe("getSourcingRequestHistory", () => {
  test("calls get_sourcing_request_history and parses every event row", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: [VALID_EVENT_ROW], error: null }, calls);

    const rows = await getSourcingRequestHistory(client, REQUEST_ID, ACTOR_ID);

    assert.equal(calls[0]?.fn, "get_sourcing_request_history");
    assert.equal(rows[0]?.toStatus, "open");
  });
});
