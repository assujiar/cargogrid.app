import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  getLoyaltyProgram,
  listLoyaltyPrograms,
  getLoyaltyProgramRuleVersion,
  listLoyaltyProgramRuleVersions,
  getLoyaltyAccount,
  listLoyaltyAccounts,
  getLoyaltyEarningEvent,
  listLoyaltyEarningEvents,
  listCustomerPortalLoyaltyAccounts,
  listCustomerPortalLoyaltyEarningEvents,
  LoyaltyProgramQueryError,
  type LoyaltyProgramQueryClient,
} from "./customer-portal-loyalty-program.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const PROGRAM_ID = "223e4567-e89b-12d3-a456-426614174000";
const RULE_VERSION_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";
const EVENT_ID = "623e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: LoyaltyProgramQueryClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as LoyaltyProgramQueryClient;
  return { client, calls };
}

const PROGRAM_ROW = {
  id: PROGRAM_ID,
  tenant_id: TENANT_ID,
  name: "Freight Rewards",
  status: "active",
  description: null,
  created_by: "staff-1",
  record_version: 1,
  created_at: "2026-08-17T00:00:00.000Z",
  updated_at: "2026-08-17T00:00:00.000Z",
};

describe("getLoyaltyProgram / listLoyaltyPrograms", () => {
  test("getLoyaltyProgram passes the exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [PROGRAM_ROW], error: null });
    const result = await getLoyaltyProgram(client, TENANT_ID, PROGRAM_ID, ACTOR_ID);
    assert.equal(result.name, "Freight Rewards");
    assert.deepEqual(calls[0], { fn: "get_loyalty_program", args: { p_tenant_id: TENANT_ID, p_program_id: PROGRAM_ID, p_actor_auth_user_id: ACTOR_ID } });
  });

  test("getLoyaltyProgram propagates loyalty_program_not_found with .code set", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "loyalty_program_not_found: x" } });
    await assert.rejects(
      () => getLoyaltyProgram(client, TENANT_ID, PROGRAM_ID, ACTOR_ID),
      (err: unknown) => err instanceof LoyaltyProgramQueryError && err.code === "loyalty_program_not_found",
    );
  });

  test("listLoyaltyPrograms defaults filters to null and limit to 50", async () => {
    const { client, calls } = fakeRpcClient({ data: [PROGRAM_ROW], error: null });
    await listLoyaltyPrograms(client, TENANT_ID, ACTOR_ID);
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_status: null, p_cursor_updated_at: null, p_cursor_id: null, p_limit: 50 });
  });

  test("listLoyaltyPrograms returns an empty array when data is null", async () => {
    const { client } = fakeRpcClient({ data: null, error: null });
    const result = await listLoyaltyPrograms(client, TENANT_ID, ACTOR_ID);
    assert.deepEqual(result, []);
  });
});

describe("getLoyaltyProgramRuleVersion / listLoyaltyProgramRuleVersions", () => {
  const RULE_VERSION_ROW = {
    id: RULE_VERSION_ID,
    tenant_id: TENANT_ID,
    program_id: PROGRAM_ID,
    version_number: 1,
    earning_basis: "per_paid_invoice_amount",
    reward_type: "points",
    rate: "0.1",
    eligibility_config: {},
    status: "published",
    effective_from: "2026-08-01T00:00:00.000Z",
    effective_to: null,
    published_by: "staff-1",
    published_at: "2026-08-01T00:00:00.000Z",
    record_version: 1,
    created_by: "staff-1",
    created_at: "2026-07-30T00:00:00.000Z",
    updated_at: "2026-08-01T00:00:00.000Z",
  };

  test("getLoyaltyProgramRuleVersion maps rate string to number", async () => {
    const { client } = fakeRpcClient({ data: [RULE_VERSION_ROW], error: null });
    const result = await getLoyaltyProgramRuleVersion(client, TENANT_ID, RULE_VERSION_ID, ACTOR_ID);
    assert.equal(result.rate, 0.1);
  });

  test("listLoyaltyProgramRuleVersions forwards programId and status filter", async () => {
    const { client, calls } = fakeRpcClient({ data: [RULE_VERSION_ROW], error: null });
    await listLoyaltyProgramRuleVersions(client, TENANT_ID, PROGRAM_ID, ACTOR_ID, { status: "published" });
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_program_id: PROGRAM_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_status: "published",
      p_cursor_updated_at: null,
      p_cursor_id: null,
      p_limit: 50,
    });
  });
});

describe("getLoyaltyAccount / listLoyaltyAccounts", () => {
  const ACCOUNT_ROW = {
    id: ACCOUNT_ID,
    tenant_id: TENANT_ID,
    customer_account_id: "723e4567-e89b-12d3-a456-426614174000",
    program_id: PROGRAM_ID,
    status: "active",
    enrolled_at: "2026-08-01T00:00:00.000Z",
    closed_by: null,
    closed_at: null,
    closed_reason: null,
    record_version: 1,
    created_at: "2026-08-01T00:00:00.000Z",
    updated_at: "2026-08-01T00:00:00.000Z",
  };

  test("getLoyaltyAccount propagates loyalty_account_not_found", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "loyalty_account_not_found: x" } });
    await assert.rejects(
      () => getLoyaltyAccount(client, TENANT_ID, ACCOUNT_ID, ACTOR_ID),
      (err: unknown) => err instanceof LoyaltyProgramQueryError && err.code === "loyalty_account_not_found",
    );
  });

  test("listLoyaltyAccounts forwards every optional filter", async () => {
    const { client, calls } = fakeRpcClient({ data: [ACCOUNT_ROW], error: null });
    await listLoyaltyAccounts(client, TENANT_ID, ACTOR_ID, { programId: PROGRAM_ID, customerAccountId: ACCOUNT_ROW.customer_account_id, status: "active", limit: 10 });
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_program_id: PROGRAM_ID,
      p_customer_account_id: ACCOUNT_ROW.customer_account_id,
      p_status: "active",
      p_cursor_updated_at: null,
      p_cursor_id: null,
      p_limit: 10,
    });
  });
});

describe("getLoyaltyEarningEvent / listLoyaltyEarningEvents", () => {
  const EVENT_ROW = {
    id: EVENT_ID,
    tenant_id: TENANT_ID,
    loyalty_account_id: ACCOUNT_ID,
    program_id: PROGRAM_ID,
    rule_version_id: RULE_VERSION_ID,
    reward_type: "points",
    amount: "110",
    source_type: "finance_invoice_paid",
    source_id: "823e4567-e89b-12d3-a456-426614174000",
    idempotency_key: "ar-open-item:823e4567-e89b-12d3-a456-426614174000",
    corrects_event_id: null,
    reason: null,
    created_by: "staff-1",
    created_at: "2026-08-17T00:00:00.000Z",
  };

  test("getLoyaltyEarningEvent maps a full row", async () => {
    const { client } = fakeRpcClient({ data: [EVENT_ROW], error: null });
    const result = await getLoyaltyEarningEvent(client, TENANT_ID, EVENT_ID, ACTOR_ID);
    assert.equal(result.amount, 110);
  });

  test("listLoyaltyEarningEvents uses the created_at cursor shape (no updated_at column)", async () => {
    const { client, calls } = fakeRpcClient({ data: [EVENT_ROW], error: null });
    await listLoyaltyEarningEvents(client, TENANT_ID, ACTOR_ID, { loyaltyAccountId: ACCOUNT_ID, cursorCreatedAt: "2026-08-17T00:00:00.000Z", cursorId: EVENT_ID });
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_loyalty_account_id: ACCOUNT_ID,
      p_program_id: null,
      p_cursor_created_at: "2026-08-17T00:00:00.000Z",
      p_cursor_id: EVENT_ID,
      p_limit: 50,
    });
  });
});

describe("customer-facing reads", () => {
  test("listCustomerPortalLoyaltyAccounts returns an empty array when data is null (deny-by-default)", async () => {
    const { client, calls } = fakeRpcClient({ data: null, error: null });
    const result = await listCustomerPortalLoyaltyAccounts(client, TENANT_ID, ACTOR_ID);
    assert.deepEqual(result, []);
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_customer_account_id: null, p_cursor_updated_at: null, p_cursor_id: null, p_limit: 50 });
  });

  test("listCustomerPortalLoyaltyAccounts maps program_name into the result", async () => {
    const { client } = fakeRpcClient({
      data: [{ id: ACCOUNT_ID, customer_account_id: "923e4567-e89b-12d3-a456-426614174000", program_id: PROGRAM_ID, program_name: "Freight Rewards", status: "active", enrolled_at: "2026-08-01T00:00:00.000Z", record_version: 1, updated_at: "2026-08-01T00:00:00.000Z" }],
      error: null,
    });
    const result = await listCustomerPortalLoyaltyAccounts(client, TENANT_ID, ACTOR_ID);
    assert.equal(result[0]?.programName, "Freight Rewards");
  });

  test("listCustomerPortalLoyaltyEarningEvents forwards customerAccountId and the created_at cursor", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await listCustomerPortalLoyaltyEarningEvents(client, TENANT_ID, ACTOR_ID, { customerAccountId: ACCOUNT_ID, cursorCreatedAt: "2026-08-17T00:00:00.000Z", cursorId: EVENT_ID, limit: 5 });
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_customer_account_id: ACCOUNT_ID,
      p_cursor_created_at: "2026-08-17T00:00:00.000Z",
      p_cursor_id: EVENT_ID,
      p_limit: 5,
    });
  });

  test("listCustomerPortalLoyaltyEarningEvents maps earning_basis/rate, never internal linkage", async () => {
    const { client } = fakeRpcClient({
      data: [{ id: EVENT_ID, program_name: "Freight Rewards", reward_type: "points", amount: "110", earning_basis: "per_paid_invoice_amount", rate: "0.1", source_type: "finance_invoice_paid", reason: null, corrects_event_id: null, created_at: "2026-08-17T00:00:00.000Z" }],
      error: null,
    });
    const result = await listCustomerPortalLoyaltyEarningEvents(client, TENANT_ID, ACTOR_ID);
    assert.equal(result[0]?.amount, 110);
    assert.equal(result[0]?.earningBasis, "per_paid_invoice_amount");
    assert.ok(!("loyaltyAccountId" in (result[0] as object)));
  });

  test("propagates a non-record error (e.g. invalid_cursor)", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "invalid_cursor: p_cursor_created_at is required when p_cursor_id is supplied" } });
    await assert.rejects(
      () => listCustomerPortalLoyaltyEarningEvents(client, TENANT_ID, ACTOR_ID, { cursorId: EVENT_ID }),
      (err: unknown) => err instanceof LoyaltyProgramQueryError && err.code === "invalid_cursor",
    );
  });
});
