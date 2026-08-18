import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  executeLoyaltyLiabilityReconciliationRun,
  resolveLoyaltyLiabilityReconciliationException,
  certifyLoyaltyLiabilityReconciliationRun,
  LoyaltyLiabilityMutationError,
  type LoyaltyLiabilityMutationRpcClient,
} from "./customer-portal-loyalty-liability.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const RUN_ID = "223e4567-e89b-12d3-a456-426614174000";
const EXCEPTION_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "423e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: LoyaltyLiabilityMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as LoyaltyLiabilityMutationRpcClient;
  return { client, calls };
}

const RUN_ROW = {
  id: RUN_ID,
  tenant_id: TENANT_ID,
  as_of: "2026-08-18T00:00:00.000Z",
  currency: "USD",
  status: "open",
  points_liability_total: 400,
  cashback_liability_total: 0,
  discount_liability_total: 0,
  voucher_liability_total: 40,
  reward_fulfillment_liability_total: 75,
  computed_at: "2026-08-18T00:00:00.000Z",
  config_version: 1,
  idempotency_key: "lra-clean-run",
  executed_by: "manager1",
  certified_by: null,
  certified_at: null,
  record_version: 1,
  created_at: "2026-08-18T00:00:00.000Z",
  updated_at: "2026-08-18T00:00:00.000Z",
};

describe("executeLoyaltyLiabilityReconciliationRun", () => {
  test("defaults optional fields and forwards required ones", async () => {
    const { client, calls } = fakeRpcClient({ data: [RUN_ROW], error: null });
    const result = await executeLoyaltyLiabilityReconciliationRun(client, { tenantId: TENANT_ID, currency: "USD", actorAuthUserId: ACTOR_ID, actorLabel: "manager1" });
    assert.equal(result.currency, "USD");
    assert.deepEqual(calls[0], {
      fn: "execute_loyalty_liability_reconciliation_run",
      args: { p_tenant_id: TENANT_ID, p_as_of: null, p_currency: "USD", p_actor_auth_user_id: ACTOR_ID, p_actor_label: "manager1", p_idempotency_key: null, p_config_version: null },
    });
  });

  test("classifies insufficient_authority", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity lacks LYL:Edit" } });
    await assert.rejects(
      () => executeLoyaltyLiabilityReconciliationRun(client, { tenantId: TENANT_ID, currency: "USD", actorAuthUserId: ACTOR_ID, actorLabel: "plain1" }),
      (err: unknown) => {
        assert.ok(err instanceof LoyaltyLiabilityMutationError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });
});

describe("resolveLoyaltyLiabilityReconciliationException", () => {
  const EXCEPTION_ROW = {
    id: EXCEPTION_ID,
    tenant_id: TENANT_ID,
    run_id: RUN_ID,
    exception_type: "point_balance_derivation_mismatch",
    detail: { expectedAvailable: 200, actualAvailable: 700 },
    status: "resolved",
    resolved_by: "manager1",
    resolution_reason: "acknowledged",
    resolved_at: "2026-08-18T00:05:00.000Z",
    record_version: 2,
    created_at: "2026-08-18T00:00:00.000Z",
    updated_at: "2026-08-18T00:05:00.000Z",
  };

  test("forwards args and maps the resolved row", async () => {
    const { client, calls } = fakeRpcClient({ data: [EXCEPTION_ROW], error: null });
    const result = await resolveLoyaltyLiabilityReconciliationException(client, {
      tenantId: TENANT_ID,
      exceptionId: EXCEPTION_ID,
      expectedVersion: 1,
      resolutionReason: "acknowledged",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "manager1",
    });
    assert.equal(result.status, "resolved");
    assert.deepEqual(calls[0], {
      fn: "resolve_loyalty_liability_reconciliation_exception",
      args: { p_tenant_id: TENANT_ID, p_exception_id: EXCEPTION_ID, p_expected_version: 1, p_resolution_reason: "acknowledged", p_actor_auth_user_id: ACTOR_ID, p_actor_label: "manager1" },
    });
  });

  test("rejects an empty resolutionReason before ever calling rpc", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await assert.rejects(() =>
      resolveLoyaltyLiabilityReconciliationException(client, { tenantId: TENANT_ID, exceptionId: EXCEPTION_ID, expectedVersion: 1, resolutionReason: "", actorAuthUserId: ACTOR_ID, actorLabel: "manager1" }),
    );
    assert.equal(calls.length, 0);
  });

  test("classifies stale_version", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "stale_version: expected version 1 but found 2" } });
    await assert.rejects(
      () =>
        resolveLoyaltyLiabilityReconciliationException(client, { tenantId: TENANT_ID, exceptionId: EXCEPTION_ID, expectedVersion: 1, resolutionReason: "x", actorAuthUserId: ACTOR_ID, actorLabel: "manager1" }),
      (err: unknown) => {
        assert.ok(err instanceof LoyaltyLiabilityMutationError);
        assert.equal(err.code, "stale_version");
        return true;
      },
    );
  });
});

describe("certifyLoyaltyLiabilityReconciliationRun", () => {
  test("forwards args and maps the certified row", async () => {
    const certifiedRow = { ...RUN_ROW, status: "certified", certified_by: "manager1", certified_at: "2026-08-18T00:10:00.000Z" };
    const { client, calls } = fakeRpcClient({ data: [certifiedRow], error: null });
    const result = await certifyLoyaltyLiabilityReconciliationRun(client, { tenantId: TENANT_ID, runId: RUN_ID, expectedVersion: 3, actorAuthUserId: ACTOR_ID, actorLabel: "manager1" });
    assert.equal(result.status, "certified");
    assert.deepEqual(calls[0], {
      fn: "certify_loyalty_liability_reconciliation_run",
      args: { p_tenant_id: TENANT_ID, p_run_id: RUN_ID, p_expected_version: 3, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "manager1" },
    });
  });

  test("classifies loyalty_liability_reconciliation_unresolved_exceptions", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "loyalty_liability_reconciliation_unresolved_exceptions: run has 2 unresolved exception(s)" } });
    await assert.rejects(
      () => certifyLoyaltyLiabilityReconciliationRun(client, { tenantId: TENANT_ID, runId: RUN_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "manager1" }),
      (err: unknown) => {
        assert.ok(err instanceof LoyaltyLiabilityMutationError);
        assert.equal(err.code, "loyalty_liability_reconciliation_unresolved_exceptions");
        return true;
      },
    );
  });

  test("rejects a non-positive expectedVersion before ever calling rpc", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await assert.rejects(() => certifyLoyaltyLiabilityReconciliationRun(client, { tenantId: TENANT_ID, runId: RUN_ID, expectedVersion: 0, actorAuthUserId: ACTOR_ID, actorLabel: "manager1" }));
    assert.equal(calls.length, 0);
  });
});
