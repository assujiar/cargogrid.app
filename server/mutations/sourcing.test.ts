import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createSourcingRequestFromCosting,
  createSourcingRequestFromOperationalDemand,
  createProactiveSourcingRequest,
  submitSourcingRequest,
  overrideSourcingRequestConstraints,
  evaluateSourcingCandidateEligibility,
  shortlistSourcingCandidate,
  submitSourcingShortlist,
  closeSourcingRequestNoSource,
  cancelSourcingRequest,
  reopenSourcingRequest,
  SourcingMutationError,
  type SourcingMutationRpcClient,
} from "./sourcing.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "323e4567-e89b-12d3-a456-426614174000";
const CANDIDATE_ID = "423e4567-e89b-12d3-a456-426614174000";
const COSTING_REQUEST_ID = "523e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ORDER_ID = "623e4567-e89b-12d3-a456-426614174000";
const VENDOR_MASTER_ID = "723e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "823e4567-e89b-12d3-a456-426614174000";

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
  budget_amount: 50000000,
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
  shortlisted: true,
  shortlist_reason: "strong fit",
  shortlisted_by: "tester",
  shortlisted_at: "2026-08-01T00:00:00.000Z",
  record_version: 2,
  created_at: "2026-08-01T00:00:00.000Z",
  updated_at: "2026-08-01T00:00:00.000Z",
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }, calls: { fn: string; args: Record<string, unknown> }[]): SourcingMutationRpcClient {
  return {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as SourcingMutationRpcClient;
}

describe("createSourcingRequestFromCosting", () => {
  test("calls create_sourcing_request_from_costing with the exact snake_case params", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: { ...VALID_REQUEST_ROW, source_type: "costing_request", source_costing_request_id: COSTING_REQUEST_ID }, error: null }, calls);

    const request = await createSourcingRequestFromCosting(client, {
      tenantId: TENANT_ID,
      costingRequestId: COSTING_REQUEST_ID,
      idempotencyKey: "idem-1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
    });

    assert.equal(calls[0]?.fn, "create_sourcing_request_from_costing");
    assert.equal(calls[0]?.args.p_costing_request_id, COSTING_REQUEST_ID);
    assert.equal(calls[0]?.args.p_owner_user_id, null);
    assert.equal(calls[0]?.args.p_idempotency_key, "idem-1");
    assert.equal(request.sourceCostingRequestId, COSTING_REQUEST_ID);
  });

  test("classifies a source_demand_incomplete error via the generic prefix classifier", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "source_demand_incomplete: costing request x requirements_snapshot has no usable service_type/origin/destination" } }, []);
    await assert.rejects(
      () => createSourcingRequestFromCosting(client, { tenantId: TENANT_ID, costingRequestId: COSTING_REQUEST_ID, idempotencyKey: "idem-1", actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof SourcingMutationError);
        assert.equal(err.code, "source_demand_incomplete");
        return true;
      },
    );
  });

  test("an unrecognized error message classifies as mutation_failed", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "some_unexpected_postgres_error: detail" } }, []);
    await assert.rejects(
      () => createSourcingRequestFromCosting(client, { tenantId: TENANT_ID, costingRequestId: COSTING_REQUEST_ID, idempotencyKey: "idem-1", actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof SourcingMutationError);
        assert.equal(err.code, "mutation_failed");
        return true;
      },
    );
  });
});

describe("createSourcingRequestFromOperationalDemand", () => {
  test("calls create_sourcing_request_from_operational_demand with the exact snake_case params", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: { ...VALID_REQUEST_ROW, source_type: "operational_demand", source_shipment_order_id: SHIPMENT_ORDER_ID }, error: null }, calls);

    const request = await createSourcingRequestFromOperationalDemand(client, {
      tenantId: TENANT_ID,
      shipmentOrderId: SHIPMENT_ORDER_ID,
      idempotencyKey: "idem-2",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
    });

    assert.equal(calls[0]?.fn, "create_sourcing_request_from_operational_demand");
    assert.equal(calls[0]?.args.p_shipment_order_id, SHIPMENT_ORDER_ID);
    assert.equal(request.sourceShipmentOrderId, SHIPMENT_ORDER_ID);
  });
});

describe("createProactiveSourcingRequest", () => {
  test("calls create_proactive_sourcing_request with every field, defaulting optional constraints to null", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: VALID_REQUEST_ROW, error: null }, calls);

    await createProactiveSourcingRequest(client, {
      tenantId: TENANT_ID,
      serviceType: "ocean_freight",
      originLane: "Jakarta",
      destinationLane: "Surabaya",
      idempotencyKey: "idem-3",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
    });

    assert.equal(calls[0]?.fn, "create_proactive_sourcing_request");
    assert.equal(calls[0]?.args.p_service_type, "ocean_freight");
    assert.equal(calls[0]?.args.p_mode, null);
    assert.equal(calls[0]?.args.p_cargo_weight_max, null);
    assert.equal(calls[0]?.args.p_budget_amount, null);
  });
});

describe("submitSourcingRequest", () => {
  test("calls submit_sourcing_request with p_expected_version", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: VALID_REQUEST_ROW, error: null }, calls);

    await submitSourcingRequest(client, { sourcingRequestId: REQUEST_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "tester" });

    assert.equal(calls[0]?.fn, "submit_sourcing_request");
    assert.equal(calls[0]?.args.p_expected_version, 1);
  });

  test("classifies invalid_transition", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "invalid_transition: sourcing request x is source_type costing_request -- only a proactive request may be submitted" } }, []);
    await assert.rejects(
      () => submitSourcingRequest(client, { sourcingRequestId: REQUEST_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof SourcingMutationError);
        assert.equal(err.code, "invalid_transition");
        return true;
      },
    );
  });
});

describe("overrideSourcingRequestConstraints", () => {
  test("passes cargoWeightMax/cargoVolumeMax/destinationLane/reason/overrideExpiresAt through", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: VALID_REQUEST_ROW, error: null }, calls);

    await overrideSourcingRequestConstraints(client, {
      sourcingRequestId: REQUEST_ID,
      cargoWeightMax: 1500,
      reason: "need more capacity",
      overrideExpiresAt: "2026-09-01T00:00:00.000Z",
      expectedVersion: 1,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
    });

    assert.equal(calls[0]?.fn, "override_sourcing_request_constraints");
    assert.equal(calls[0]?.args.p_cargo_weight_max, 1500);
    assert.equal(calls[0]?.args.p_cargo_volume_max, null);
    assert.equal(calls[0]?.args.p_reason, "need more capacity");
    assert.equal(calls[0]?.args.p_override_expires_at, "2026-09-01T00:00:00.000Z");
  });

  test("classifies constraint_narrowing_not_allowed", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "constraint_narrowing_not_allowed: cargo_weight_max override 1000 is less than the current value 1500" } }, []);
    await assert.rejects(
      () =>
        overrideSourcingRequestConstraints(client, {
          sourcingRequestId: REQUEST_ID,
          cargoWeightMax: 1000,
          reason: "attempt to narrow",
          expectedVersion: 1,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "tester",
        }),
      (err: unknown) => {
        assert.ok(err instanceof SourcingMutationError);
        assert.equal(err.code, "constraint_narrowing_not_allowed");
        return true;
      },
    );
  });
});

describe("evaluateSourcingCandidateEligibility", () => {
  test("calls evaluate_sourcing_candidate_eligibility and parses every returned candidate row", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: [VALID_CANDIDATE_ROW, { ...VALID_CANDIDATE_ROW, id: "923e4567-e89b-12d3-a456-426614174000", eligible: false, exclusion_reasons: ["service_mismatch"] }], error: null }, calls);

    const candidates = await evaluateSourcingCandidateEligibility(client, { sourcingRequestId: REQUEST_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" });

    assert.equal(calls[0]?.fn, "evaluate_sourcing_candidate_eligibility");
    assert.equal(candidates.length, 2);
    assert.equal(candidates[1]?.eligible, false);
  });

  test("returns an empty array (not an error) when the RPC returns null data", async () => {
    const client = fakeRpcClient({ data: null, error: null }, []);
    const candidates = await evaluateSourcingCandidateEligibility(client, { sourcingRequestId: REQUEST_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" });
    assert.deepEqual(candidates, []);
  });
});

describe("shortlistSourcingCandidate", () => {
  test("calls shortlist_sourcing_candidate with p_shortlisted/p_reason", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: VALID_CANDIDATE_ROW, error: null }, calls);

    const candidate = await shortlistSourcingCandidate(client, {
      candidateId: CANDIDATE_ID,
      shortlisted: true,
      reason: "strong fit",
      expectedVersion: 1,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
    });

    assert.equal(calls[0]?.fn, "shortlist_sourcing_candidate");
    assert.equal(calls[0]?.args.p_shortlisted, true);
    assert.equal(calls[0]?.args.p_reason, "strong fit");
    assert.equal(candidate.shortlisted, true);
  });

  test("classifies reason_required", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "reason_required: shortlisting a candidate requires a non-empty reason" } }, []);
    await assert.rejects(
      () => shortlistSourcingCandidate(client, { candidateId: CANDIDATE_ID, shortlisted: true, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof SourcingMutationError);
        assert.equal(err.code, "reason_required");
        return true;
      },
    );
  });
});

describe("submitSourcingShortlist", () => {
  test("classifies no_candidates_shortlisted", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "no_candidates_shortlisted: sourcing request x has zero shortlisted candidates" } }, []);
    await assert.rejects(
      () => submitSourcingShortlist(client, { sourcingRequestId: REQUEST_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof SourcingMutationError);
        assert.equal(err.code, "no_candidates_shortlisted");
        return true;
      },
    );
  });

  test("calls submit_sourcing_shortlist and returns the shortlisted request", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: { ...VALID_REQUEST_ROW, status: "shortlisted", shortlist_locked_at: "2026-08-01T00:00:00.000Z" }, error: null }, calls);

    const request = await submitSourcingShortlist(client, { sourcingRequestId: REQUEST_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "tester" });

    assert.equal(calls[0]?.fn, "submit_sourcing_shortlist");
    assert.equal(request.status, "shortlisted");
  });
});

describe("closeSourcingRequestNoSource", () => {
  test("calls close_sourcing_request_no_source with p_reason", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: { ...VALID_REQUEST_ROW, status: "closed_no_source", closed_reason: "no eligible vendor" }, error: null }, calls);

    const request = await closeSourcingRequestNoSource(client, { sourcingRequestId: REQUEST_ID, reason: "no eligible vendor", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "tester" });

    assert.equal(calls[0]?.fn, "close_sourcing_request_no_source");
    assert.equal(calls[0]?.args.p_reason, "no eligible vendor");
    assert.equal(request.status, "closed_no_source");
  });
});

describe("cancelSourcingRequest", () => {
  test("calls cancel_sourcing_request with p_reason", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: { ...VALID_REQUEST_ROW, status: "cancelled", closed_reason: "no longer needed" }, error: null }, calls);

    const request = await cancelSourcingRequest(client, { sourcingRequestId: REQUEST_ID, reason: "no longer needed", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "tester" });

    assert.equal(calls[0]?.fn, "cancel_sourcing_request");
    assert.equal(request.status, "cancelled");
  });
});

describe("reopenSourcingRequest", () => {
  test("calls reopen_sourcing_request with p_reason and returns status=open", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: { ...VALID_REQUEST_ROW, status: "open", shortlist_locked_at: null, closed_reason: null }, error: null }, calls);

    const request = await reopenSourcingRequest(client, { sourcingRequestId: REQUEST_ID, reason: "reconsidered", expectedVersion: 3, actorAuthUserId: ACTOR_ID, actorLabel: "tester" });

    assert.equal(calls[0]?.fn, "reopen_sourcing_request");
    assert.equal(calls[0]?.args.p_expected_version, 3);
    assert.equal(request.status, "open");
  });

  test("classifies insufficient_authority", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity x lacks PRC:Override (no_active_assignment) for tenant y" } }, []);
    await assert.rejects(
      () => reopenSourcingRequest(client, { sourcingRequestId: REQUEST_ID, reason: "reconsidered", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof SourcingMutationError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });
});
