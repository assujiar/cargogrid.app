import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  reportException,
  assignExceptionOwner,
  acknowledgeException,
  escalateException,
  resolveException,
  closeException,
  reopenException,
  setExceptionSensitiveFields,
  createExceptionSlaPolicyDraft,
  publishExceptionSlaPolicyVersion,
  ExceptionEscalationMutationError,
  type ExceptionEscalationMutationRpcClient,
} from "./exception-escalation.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const VERSION_ID = "323e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";
const EXCEPTION_ID = "623e4567-e89b-12d3-a456-426614174000";
const OWNER_ID = "723e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: ExceptionEscalationMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as ExceptionEscalationMutationRpcClient;
  return { client, calls };
}

const EXCEPTION_ROW = {
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
  description: "Carrier reports a delay",
  internal_notes: null,
  damage_loss_details: null,
  claim_amount: null,
  claim_currency: null,
  resolution_evidence: null,
  resolved_at: null,
  reopened_at: null,
  closed_at: null,
  record_version: 1,
  created_by: "rep",
  created_at: "2026-07-27T08:00:00.000Z",
  updated_at: "2026-07-27T08:00:00.000Z",
};

const POLICY_ROW = {
  id: VERSION_ID,
  tenant_id: TENANT_ID,
  type: "delay",
  severity: "high",
  status: "draft",
  sla_hours: null,
  escalation_schedule: [],
  supersedes_version_id: null,
  record_version: 1,
  created_by: "rep",
  created_at: "2026-07-27T00:00:00.000Z",
  updated_at: "2026-07-27T00:00:00.000Z",
};

describe("createExceptionSlaPolicyDraft / publishExceptionSlaPolicyVersion", () => {
  test("createExceptionSlaPolicyDraft calls with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: POLICY_ROW, error: null });
    const version = await createExceptionSlaPolicyDraft(client, { tenantId: TENANT_ID, type: "delay", severity: "high", actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(calls[0]?.fn, "create_exception_sla_policy_draft");
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_type: "delay", p_severity: "high", p_actor_auth_user_id: ACTOR_ID, p_actor_label: "rep" });
    assert.equal(version.status, "draft");
  });

  test("publishExceptionSlaPolicyVersion classifies exception_invalid_sla_hours", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "exception_invalid_sla_hours: a policy cannot publish without sla_hours set" } });
    await assert.rejects(
      () => publishExceptionSlaPolicyVersion(client, { versionId: VERSION_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof ExceptionEscalationMutationError);
        assert.equal(err.code, "exception_invalid_sla_hours");
        return true;
      },
    );
  });
});

describe("reportException", () => {
  test("calls report_exception with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: EXCEPTION_ROW, error: null });
    const exception = await reportException(client, {
      shipmentOrderId: SHIPMENT_ID,
      type: "delay",
      severity: "high",
      description: "Carrier reports a delay",
      source: "manual",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(calls[0]?.fn, "report_exception");
    assert.deepEqual(calls[0]?.args, {
      p_shipment_order_id: SHIPMENT_ID,
      p_milestone_event_id: null,
      p_type: "delay",
      p_severity: "high",
      p_description: "Carrier reports a delay",
      p_source: "manual",
      p_correlation_key: null,
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "rep",
    });
    assert.equal(exception.type, "delay");
  });

  test("classifies invalid_transition for a cancelled shipment", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "invalid_transition: shipment order X is cancelled" } });
    await assert.rejects(
      () =>
        reportException(client, { shipmentOrderId: SHIPMENT_ID, type: "delay", severity: "high", description: "x", source: "manual", actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof ExceptionEscalationMutationError);
        assert.equal(err.code, "invalid_transition");
        return true;
      },
    );
  });
});

describe("assignExceptionOwner", () => {
  test("classifies reason_required for a reassignment with no reason", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "reason_required: reassigning an already-owned exception requires a non-empty reason" } });
    await assert.rejects(
      () => assignExceptionOwner(client, { exceptionId: EXCEPTION_ID, ownerUserId: OWNER_ID, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof ExceptionEscalationMutationError);
        assert.equal(err.code, "reason_required");
        return true;
      },
    );
  });
});

describe("acknowledgeException", () => {
  test("calls acknowledge_exception with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: { ...EXCEPTION_ROW, status: "acknowledged" }, error: null });
    const exception = await acknowledgeException(client, { exceptionId: EXCEPTION_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(calls[0]?.fn, "acknowledge_exception");
    assert.equal(exception.status, "acknowledged");
  });
});

describe("escalateException", () => {
  test("rejects an empty reason at the schema layer, before ever calling the RPC", async () => {
    const { client, calls } = fakeRpcClient({ data: EXCEPTION_ROW, error: null });
    await assert.rejects(() => escalateException(client, { exceptionId: EXCEPTION_ID, reason: "", actorAuthUserId: ACTOR_ID, actorLabel: "rep" }));
    assert.equal(calls.length, 0);
  });

  test("classifies invalid_transition once resolved/closed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "invalid_transition: exception X is resolved and can no longer be escalated" } });
    await assert.rejects(
      () => escalateException(client, { exceptionId: EXCEPTION_ID, reason: "still overdue", actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof ExceptionEscalationMutationError);
        assert.equal(err.code, "invalid_transition");
        return true;
      },
    );
  });
});

describe("resolveException", () => {
  test("classifies evidence_required", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "evidence_required: resolving an exception requires non-empty resolution_evidence" } });
    await assert.rejects(
      () => resolveException(client, { exceptionId: EXCEPTION_ID, expectedVersion: 1, resolutionEvidence: "x", actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof ExceptionEscalationMutationError);
        assert.equal(err.code, "evidence_required");
        return true;
      },
    );
  });
});

describe("closeException / reopenException", () => {
  test("closeException calls close_exception with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: { ...EXCEPTION_ROW, status: "closed" }, error: null });
    const exception = await closeException(client, { exceptionId: EXCEPTION_ID, expectedVersion: 2, actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(calls[0]?.fn, "close_exception");
    assert.equal(exception.status, "closed");
  });

  test("reopenException rejects an empty reason at the schema layer", async () => {
    const { client, calls } = fakeRpcClient({ data: EXCEPTION_ROW, error: null });
    await assert.rejects(() => reopenException(client, { exceptionId: EXCEPTION_ID, expectedVersion: 3, reason: "", actorAuthUserId: ACTOR_ID, actorLabel: "rep" }));
    assert.equal(calls.length, 0);
  });
});

describe("setExceptionSensitiveFields", () => {
  test("classifies insufficient_authority for an actor lacking OPS:View cost", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity X lacks OPS:View cost for tenant Y" } });
    await assert.rejects(
      () => setExceptionSensitiveFields(client, { exceptionId: EXCEPTION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "restricted" }),
      (err: unknown) => {
        assert.ok(err instanceof ExceptionEscalationMutationError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });

  test("calls with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: { ...EXCEPTION_ROW, internal_notes: "GPS malfunctioned", claim_amount: "750.50", claim_currency: "USD" }, error: null });
    const exception = await setExceptionSensitiveFields(client, {
      exceptionId: EXCEPTION_ID,
      internalNotes: "GPS malfunctioned",
      claimAmount: 750.5,
      claimCurrency: "USD",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(calls[0]?.fn, "set_exception_sensitive_fields");
    assert.deepEqual(calls[0]?.args, {
      p_exception_id: EXCEPTION_ID,
      p_internal_notes: "GPS malfunctioned",
      p_damage_loss_details: null,
      p_claim_amount: 750.5,
      p_claim_currency: "USD",
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "rep",
    });
    assert.equal(exception.claimAmount, 750.5);
  });
});
