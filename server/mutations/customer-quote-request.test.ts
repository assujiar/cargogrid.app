import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createCustomerQuoteRequestDraft,
  updateCustomerQuoteRequestDraft,
  submitCustomerQuoteRequest,
  cancelCustomerQuoteRequest,
  linkCustomerQuoteRequestToQuotation,
  CustomerQuoteRequestMutationError,
  type CustomerQuoteRequestMutationRpcClient,
} from "./customer-quote-request.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "323e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";
const QUOTATION_ID = "623e4567-e89b-12d3-a456-426614174000";

const ROW = {
  id: REQUEST_ID,
  tenant_id: TENANT_ID,
  account_id: ACCOUNT_ID,
  requested_by_auth_user_id: ACTOR_ID,
  status: "draft",
  cargo_description: null,
  origin: {},
  destination: {},
  service_type: null,
  requested_pickup_date: null,
  requested_delivery_date: null,
  notes: null,
  idempotency_key: "create-1",
  submitted_idempotency_key: null,
  linked_quotation_id: null,
  record_version: 1,
  created_by: ACTOR_ID,
  created_at: "2026-08-16T00:00:00.000Z",
  updated_at: "2026-08-16T00:00:00.000Z",
  submitted_at: null,
  cancelled_at: null,
  cancelled_reason: null,
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: CustomerQuoteRequestMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as CustomerQuoteRequestMutationRpcClient;
  return { client, calls };
}

describe("createCustomerQuoteRequestDraft", () => {
  test("passes exact param names, defaulting origin/destination to {} and optional fields to null", async () => {
    const { client, calls } = fakeRpcClient({ data: [ROW], error: null });
    const result = await createCustomerQuoteRequestDraft(client, { tenantId: TENANT_ID, accountId: ACCOUNT_ID, idempotencyKey: "create-1", actorAuthUserId: ACTOR_ID, actorLabel: "alpha-admin" });
    assert.equal(result.status, "draft");
    assert.deepEqual(calls[0], {
      fn: "create_customer_quote_request_draft",
      args: {
        p_tenant_id: TENANT_ID,
        p_account_id: ACCOUNT_ID,
        p_cargo_description: null,
        p_origin: {},
        p_destination: {},
        p_service_type: null,
        p_requested_pickup_date: null,
        p_requested_delivery_date: null,
        p_notes: null,
        p_idempotency_key: "create-1",
        p_actor_auth_user_id: ACTOR_ID,
        p_actor_label: "alpha-admin",
      },
    });
  });

  test("classifies account_not_available for a forged/unowned account", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "account_not_available: x is not an account this identity may request a quotation for" } });
    await assert.rejects(
      () => createCustomerQuoteRequestDraft(client, { tenantId: TENANT_ID, accountId: ACCOUNT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "x" }),
      (err: unknown) => {
        assert.ok(err instanceof CustomerQuoteRequestMutationError);
        assert.equal(err.code, "account_not_available");
        return true;
      },
    );
  });
});

describe("updateCustomerQuoteRequestDraft", () => {
  test("passes exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [ROW], error: null });
    await updateCustomerQuoteRequestDraft(client, { requestId: REQUEST_ID, expectedVersion: 1, cargoDescription: "General cargo", actorAuthUserId: ACTOR_ID, actorLabel: "alpha-member" });
    assert.deepEqual(calls[0]?.args, {
      p_request_id: REQUEST_ID,
      p_expected_version: 1,
      p_cargo_description: "General cargo",
      p_origin: {},
      p_destination: {},
      p_service_type: null,
      p_requested_pickup_date: null,
      p_requested_delivery_date: null,
      p_notes: null,
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "alpha-member",
    });
  });

  test("classifies stale_version", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "stale_version: quote request x expected version 1 but found 2" } });
    await assert.rejects(
      () => updateCustomerQuoteRequestDraft(client, { requestId: REQUEST_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "x" }),
      (err: unknown) => {
        assert.ok(err instanceof CustomerQuoteRequestMutationError);
        assert.equal(err.code, "stale_version");
        return true;
      },
    );
  });

  test("classifies record_not_found for an out-of-scope request", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "record_not_found: no permitted quote request exists for x" } });
    await assert.rejects(
      () => updateCustomerQuoteRequestDraft(client, { requestId: REQUEST_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "x" }),
      (err: unknown) => {
        assert.ok(err instanceof CustomerQuoteRequestMutationError);
        assert.equal(err.code, "record_not_found");
        return true;
      },
    );
  });
});

describe("submitCustomerQuoteRequest", () => {
  test("passes exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...ROW, status: "submitted" }], error: null });
    const result = await submitCustomerQuoteRequest(client, { requestId: REQUEST_ID, expectedVersion: 1, idempotencyKey: "submit-1", actorAuthUserId: ACTOR_ID, actorLabel: "alpha-admin" });
    assert.equal(result.status, "submitted");
    assert.deepEqual(calls[0], {
      fn: "submit_customer_quote_request",
      args: { p_request_id: REQUEST_ID, p_expected_version: 1, p_idempotency_key: "submit-1", p_actor_auth_user_id: ACTOR_ID, p_actor_label: "alpha-admin" },
    });
  });

  test("classifies idempotency_key_required", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "idempotency_key_required: a non-empty idempotency key is required to submit a quote request" } });
    await assert.rejects(
      () => submitCustomerQuoteRequest(client, { requestId: REQUEST_ID, expectedVersion: 1, idempotencyKey: "x", actorAuthUserId: ACTOR_ID, actorLabel: "x" }),
      (err: unknown) => {
        assert.ok(err instanceof CustomerQuoteRequestMutationError);
        assert.equal(err.code, "idempotency_key_required");
        return true;
      },
    );
  });

  test("classifies idempotency_conflict for a colliding key against a different request", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "idempotency_conflict: idempotency key already used by a different quote request x on this account" } });
    await assert.rejects(
      () => submitCustomerQuoteRequest(client, { requestId: REQUEST_ID, expectedVersion: 1, idempotencyKey: "dup", actorAuthUserId: ACTOR_ID, actorLabel: "x" }),
      (err: unknown) => {
        assert.ok(err instanceof CustomerQuoteRequestMutationError);
        assert.equal(err.code, "idempotency_conflict");
        return true;
      },
    );
  });
});

describe("cancelCustomerQuoteRequest", () => {
  test("passes exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...ROW, status: "cancelled", cancelled_reason: "no longer needed" }], error: null });
    const result = await cancelCustomerQuoteRequest(client, { requestId: REQUEST_ID, expectedVersion: 1, reason: "no longer needed", actorAuthUserId: ACTOR_ID, actorLabel: "alpha-admin" });
    assert.equal(result.status, "cancelled");
    assert.deepEqual(calls[0], {
      fn: "cancel_customer_quote_request",
      args: { p_request_id: REQUEST_ID, p_expected_version: 1, p_reason: "no longer needed", p_actor_auth_user_id: ACTOR_ID, p_actor_label: "alpha-admin" },
    });
  });

  test("rejects an empty reason at the schema layer before any RPC call", async () => {
    const { client, calls } = fakeRpcClient({ data: null, error: null });
    await assert.rejects(() => cancelCustomerQuoteRequest(client, { requestId: REQUEST_ID, expectedVersion: 1, reason: "", actorAuthUserId: ACTOR_ID, actorLabel: "x" }));
    assert.equal(calls.length, 0);
  });

  test("classifies invalid_transition for a terminal request", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "invalid_transition: quote request x is converted and can no longer be cancelled" } });
    await assert.rejects(
      () => cancelCustomerQuoteRequest(client, { requestId: REQUEST_ID, expectedVersion: 1, reason: "x", actorAuthUserId: ACTOR_ID, actorLabel: "x" }),
      (err: unknown) => {
        assert.ok(err instanceof CustomerQuoteRequestMutationError);
        assert.equal(err.code, "invalid_transition");
        return true;
      },
    );
  });
});

describe("linkCustomerQuoteRequestToQuotation", () => {
  test("passes exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...ROW, status: "converted", linked_quotation_id: QUOTATION_ID }], error: null });
    const result = await linkCustomerQuoteRequestToQuotation(client, { requestId: REQUEST_ID, quotationId: QUOTATION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "commercial-staff" });
    assert.equal(result.status, "converted");
    assert.equal(result.linkedQuotationId, QUOTATION_ID);
    assert.deepEqual(calls[0], {
      fn: "link_customer_quote_request_to_quotation",
      args: { p_request_id: REQUEST_ID, p_quotation_id: QUOTATION_ID, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "commercial-staff" },
    });
  });

  test("classifies insufficient_authority for a staff actor lacking COM:Edit", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity x lacks COM:Edit (no_granting_role) for tenant y" } });
    await assert.rejects(
      () => linkCustomerQuoteRequestToQuotation(client, { requestId: REQUEST_ID, quotationId: QUOTATION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "x" }),
      (err: unknown) => {
        assert.ok(err instanceof CustomerQuoteRequestMutationError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });

  test("classifies already_converted for re-linking to a different quotation", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "already_converted: quote request x is already linked to quotation y, not z" } });
    await assert.rejects(
      () => linkCustomerQuoteRequestToQuotation(client, { requestId: REQUEST_ID, quotationId: QUOTATION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "x" }),
      (err: unknown) => {
        assert.ok(err instanceof CustomerQuoteRequestMutationError);
        assert.equal(err.code, "already_converted");
        return true;
      },
    );
  });
});
