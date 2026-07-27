import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  getExceptionEscalationHistory,
  listShipmentExceptions,
  ExceptionEscalationQueryError,
  type ExceptionEscalationQueryRpcClient,
  type ExceptionEscalationQueryTableClient,
} from "./exception-escalation.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "423e4567-e89b-12d3-a456-426614174000";
const EXCEPTION_ID = "523e4567-e89b-12d3-a456-426614174000";
const ESCALATION_ID = "623e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): ExceptionEscalationQueryRpcClient {
  return { rpc: () => Promise.resolve(response) } as unknown as ExceptionEscalationQueryRpcClient;
}

describe("getExceptionEscalationHistory", () => {
  test("maps every row in the returned array", async () => {
    const client = fakeRpcClient({
      data: [
        {
          id: ESCALATION_ID,
          tenant_id: TENANT_ID,
          exception_id: EXCEPTION_ID,
          escalation_level: 1,
          reason: "no response within SLA",
          actor_auth_user_id: ACTOR_ID,
          actor_label: "rep",
          escalated_at: "2026-07-27T09:00:00.000Z",
        },
      ],
      error: null,
    });
    const history = await getExceptionEscalationHistory(client, { exceptionId: EXCEPTION_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(history.length, 1);
    assert.equal(history[0]?.escalationLevel, 1);
  });

  test("returns an empty array (never an error) when nothing has ever escalated", async () => {
    const client = fakeRpcClient({ data: [], error: null });
    const history = await getExceptionEscalationHistory(client, { exceptionId: EXCEPTION_ID, actorAuthUserId: ACTOR_ID });
    assert.deepEqual(history, []);
  });

  test("wraps an rpc error", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "boom" } });
    await assert.rejects(
      () => getExceptionEscalationHistory(client, { exceptionId: EXCEPTION_ID, actorAuthUserId: ACTOR_ID }),
      (err: unknown) => err instanceof ExceptionEscalationQueryError,
    );
  });
});

function fakeTableClient(response: { data: unknown; error: { message: string } | null }): ExceptionEscalationQueryTableClient {
  return {
    from: () => ({
      select: () => ({
        eq: () => ({
          order: () => Promise.resolve(response),
        }),
      }),
    }),
  } as unknown as ExceptionEscalationQueryTableClient;
}

describe("listShipmentExceptions", () => {
  test("maps every row, including the masking flag", async () => {
    const client = fakeTableClient({
      data: [
        {
          id: EXCEPTION_ID,
          tenant_id: TENANT_ID,
          shipment_order_id: SHIPMENT_ID,
          milestone_event_id: null,
          type: "delay",
          severity: "high",
          status: "open",
          owner_user_id: null,
          sla_policy_version_id: null,
          sla_hours: null,
          due_at: null,
          escalation_level: 0,
          source: "manual",
          correlation_key: null,
          description: "test",
          internal_notes: null,
          damage_loss_details: null,
          claim_amount: null,
          claim_currency: null,
          sensitive_masked: true,
          resolution_evidence: null,
          resolved_at: null,
          reopened_at: null,
          closed_at: null,
          record_version: 1,
          created_by: "rep",
          created_at: "2026-07-27T08:00:00.000Z",
          updated_at: "2026-07-27T08:00:00.000Z",
        },
      ],
      error: null,
    });
    const exceptions = await listShipmentExceptions(client, SHIPMENT_ID);
    assert.equal(exceptions.length, 1);
    assert.equal(exceptions[0]?.sensitiveMasked, true);
  });

  test("returns an empty array (never an error) when nothing has been reported yet", async () => {
    const client = fakeTableClient({ data: [], error: null });
    const exceptions = await listShipmentExceptions(client, SHIPMENT_ID);
    assert.deepEqual(exceptions, []);
  });

  test("wraps a query error", async () => {
    const client = fakeTableClient({ data: null, error: { message: "boom" } });
    await assert.rejects(() => listShipmentExceptions(client, SHIPMENT_ID), (err: unknown) => err instanceof ExceptionEscalationQueryError);
  });
});
