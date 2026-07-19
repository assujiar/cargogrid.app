import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  publishNumberingDefinition,
  bootstrapNumberingCounter,
  allocateNumber,
  reserveNumber,
  confirmNumberReservation,
  releaseNumberReservation,
  voidNumberAllocation,
  NumberingMutationError,
  type NumberingMutationRpcClient,
} from "./numbering.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const OBJECT_ID = "323e4567-e89b-12d3-a456-426614174000";
const VERSION_ID = "423e4567-e89b-12d3-a456-426614174000";
const COUNTER_ID = "523e4567-e89b-12d3-a456-426614174000";
const ALLOCATION_ID = "623e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "723e4567-e89b-12d3-a456-426614174000";

const VALID_VERSION_ROW = {
  id: VERSION_ID,
  config_object_id: OBJECT_ID,
  version_number: 1,
  status: "published",
  effective_from: "2026-07-19T00:00:00.000Z",
  effective_to: null,
  cloned_from_version_id: null,
  rollback_of_version_id: null,
  created_by: "tenant admin",
  published_by: "tenant admin",
  published_at: "2026-07-19T00:00:00.000Z",
  archived_at: null,
  archived_reason: null,
  record_version: 2,
  created_at: "2026-07-19T00:00:00.000Z",
  updated_at: "2026-07-19T00:00:00.000Z",
};

const VALID_COUNTER_ROW = {
  id: COUNTER_ID,
  config_version_id: VERSION_ID,
  scope_key: "default",
  period_key: "2026",
  next_seq: 1000,
  created_at: "2026-07-19T00:00:00.000Z",
  updated_at: "2026-07-19T00:00:00.000Z",
};

const VALID_ALLOCATION_ROW = {
  id: ALLOCATION_ID,
  tenant_id: TENANT_ID,
  config_version_id: VERSION_ID,
  scope_key: "default",
  period_key: "2026",
  seq: 1,
  formatted_number: "INV-2026-000001",
  entity_type: "generic",
  entity_id: null,
  status: "allocated",
  idempotency_key: "num-9001",
  allocated_by: "tenant user",
  allocated_at: "2026-07-19T00:00:00.000Z",
  voided_at: null,
  voided_reason: null,
  record_version: 1,
  created_at: "2026-07-19T00:00:00.000Z",
  updated_at: "2026-07-19T00:00:00.000Z",
};

function fakeClient(
  response: { data: unknown; error: { message: string } | null },
): NumberingMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn, args) {
      calls.push({ fn, args });
      return response;
    },
  };
}

describe("publishNumberingDefinition", () => {
  test("calls publish_numbering_definition and returns the published version row", async () => {
    const client = fakeClient({ data: VALID_VERSION_ROW, error: null });
    const version = await publishNumberingDefinition(client, { versionId: VERSION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tenant admin" });
    assert.equal(version.status, "published");
  });

  test("wraps a numbering_invalid_seq_token_count error", async () => {
    const client = fakeClient({ data: null, error: { message: "numbering_invalid_seq_token_count: format must contain exactly one {SEQ} token, found 0" } });
    await assert.rejects(
      () => publishNumberingDefinition(client, { versionId: VERSION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tenant admin" }),
      (err: unknown) => {
        assert.ok(err instanceof NumberingMutationError);
        assert.equal(err.code, "numbering_invalid_seq_token_count");
        return true;
      },
    );
  });
});

describe("bootstrapNumberingCounter", () => {
  test("calls bootstrap_numbering_counter with the exact snake_case params", async () => {
    const client = fakeClient({ data: VALID_COUNTER_ROW, error: null });
    await bootstrapNumberingCounter(client, { configVersionId: VERSION_ID, periodKey: "2026", startingSeq: 1000, actorAuthUserId: ACTOR_ID, actorLabel: "tenant admin" });

    assert.deepEqual(client.calls[0]?.args, {
      p_config_version_id: VERSION_ID,
      p_scope_key: "default",
      p_period_key: "2026",
      p_starting_seq: 1000,
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "tenant admin",
    });
  });

  test("wraps a numbering_counter_cannot_decrease error", async () => {
    const client = fakeClient({ data: null, error: { message: "numbering_counter_cannot_decrease: starting_seq 5 is below the counter's current value 1000" } });
    await assert.rejects(
      () => bootstrapNumberingCounter(client, { configVersionId: VERSION_ID, periodKey: "2026", startingSeq: 5, actorAuthUserId: ACTOR_ID, actorLabel: "tenant admin" }),
      (err: unknown) => {
        assert.ok(err instanceof NumberingMutationError);
        assert.equal(err.code, "numbering_counter_cannot_decrease");
        return true;
      },
    );
  });
});

describe("allocateNumber", () => {
  test("calls allocate_number with the exact snake_case params", async () => {
    const client = fakeClient({ data: VALID_ALLOCATION_ROW, error: null });
    const allocation = await allocateNumber(client, {
      configVersionId: VERSION_ID,
      tenantId: TENANT_ID,
      idempotencyKey: "num-9001",
      actorAuthUserId: ACTOR_ID,
      allocatedBy: "tenant user",
    });

    assert.deepEqual(client.calls[0]?.args, {
      p_config_version_id: VERSION_ID,
      p_tenant_id: TENANT_ID,
      p_scope_key: "default",
      p_entity_type: "generic",
      p_entity_id: null,
      p_idempotency_key: "num-9001",
      p_actor_auth_user_id: ACTOR_ID,
      p_allocated_by: "tenant user",
    });
    assert.equal(allocation.formattedNumber, "INV-2026-000001");
  });

  test("wraps a numbering_definition_not_published error", async () => {
    const client = fakeClient({ data: null, error: { message: "numbering_definition_not_published: config version x is not a published numbering definition" } });
    await assert.rejects(
      () => allocateNumber(client, { configVersionId: VERSION_ID, tenantId: TENANT_ID, idempotencyKey: "num-9001", actorAuthUserId: ACTOR_ID, allocatedBy: "tenant user" }),
      (err: unknown) => {
        assert.ok(err instanceof NumberingMutationError);
        assert.equal(err.code, "numbering_definition_not_published");
        return true;
      },
    );
  });
});

describe("reserveNumber", () => {
  test("calls reserve_number and returns a reserved allocation", async () => {
    const reservedRow = { ...VALID_ALLOCATION_ROW, status: "reserved" };
    const client = fakeClient({ data: reservedRow, error: null });
    const allocation = await reserveNumber(client, { configVersionId: VERSION_ID, tenantId: TENANT_ID, idempotencyKey: "num-9002", actorAuthUserId: ACTOR_ID, allocatedBy: "tenant user" });
    assert.equal(allocation.status, "reserved");
    assert.equal(client.calls[0]?.fn, "reserve_number");
  });
});

describe("confirmNumberReservation", () => {
  test("calls confirm_number_reservation and returns the allocated allocation", async () => {
    const client = fakeClient({ data: VALID_ALLOCATION_ROW, error: null });
    const allocation = await confirmNumberReservation(client, { allocationId: ALLOCATION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tenant user" });
    assert.equal(allocation.status, "allocated");
  });

  test("wraps a numbering_allocation_not_reserved error", async () => {
    const client = fakeClient({ data: null, error: { message: "numbering_allocation_not_reserved: allocation x is allocated, only a reserved allocation can be confirmed" } });
    await assert.rejects(
      () => confirmNumberReservation(client, { allocationId: ALLOCATION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tenant user" }),
      (err: unknown) => {
        assert.ok(err instanceof NumberingMutationError);
        assert.equal(err.code, "numbering_allocation_not_reserved");
        return true;
      },
    );
  });
});

describe("releaseNumberReservation", () => {
  test("calls release_number_reservation with the exact snake_case params", async () => {
    const releasedRow = { ...VALID_ALLOCATION_ROW, status: "released", voided_reason: "duplicate request" };
    const client = fakeClient({ data: releasedRow, error: null });
    const allocation = await releaseNumberReservation(client, { allocationId: ALLOCATION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tenant user", reason: "duplicate request" });

    assert.deepEqual(client.calls[0]?.args, {
      p_allocation_id: ALLOCATION_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "tenant user",
      p_reason: "duplicate request",
    });
    assert.equal(allocation.status, "released");
  });
});

describe("voidNumberAllocation", () => {
  test("calls void_number_allocation with the exact snake_case params", async () => {
    const voidedRow = { ...VALID_ALLOCATION_ROW, status: "voided", voided_reason: "customer cancelled" };
    const client = fakeClient({ data: voidedRow, error: null });
    const allocation = await voidNumberAllocation(client, { allocationId: ALLOCATION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tenant admin", reason: "customer cancelled" });

    assert.deepEqual(client.calls[0]?.args, {
      p_allocation_id: ALLOCATION_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "tenant admin",
      p_reason: "customer cancelled",
    });
    assert.equal(allocation.status, "voided");
  });

  test("wraps a numbering_void_reason_required error", async () => {
    const client = fakeClient({ data: null, error: { message: "numbering_void_reason_required: voiding an allocated number requires an explicit, non-empty reason" } });
    await assert.rejects(
      () => voidNumberAllocation(client, { allocationId: ALLOCATION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tenant admin", reason: "x" }),
      (err: unknown) => {
        assert.ok(err instanceof NumberingMutationError);
        assert.equal(err.code, "numbering_void_reason_required");
        return true;
      },
    );
  });
});
