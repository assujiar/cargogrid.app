import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createLoyaltyProgram,
  updateLoyaltyProgramStatus,
  createLoyaltyProgramRuleVersion,
  updateLoyaltyProgramRuleVersionDraft,
  publishLoyaltyProgramRuleVersion,
  enrollCustomerLoyaltyAccount,
  setLoyaltyAccountStatus,
  evaluateCustomerLoyaltyEarningForPaidInvoice,
  reverseLoyaltyEarningEvent,
  LoyaltyProgramMutationError,
  type LoyaltyProgramMutationRpcClient,
} from "./customer-portal-loyalty-program.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const PROGRAM_ID = "223e4567-e89b-12d3-a456-426614174000";
const RULE_VERSION_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "423e4567-e89b-12d3-a456-426614174000";
const CUSTOMER_ACCOUNT_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const EVENT_ID = "723e4567-e89b-12d3-a456-426614174000";
const AR_OPEN_ITEM_ID = "823e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: LoyaltyProgramMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as LoyaltyProgramMutationRpcClient;
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

const RULE_VERSION_ROW = {
  id: RULE_VERSION_ID,
  tenant_id: TENANT_ID,
  program_id: PROGRAM_ID,
  version_number: 1,
  earning_basis: "per_paid_invoice_amount",
  reward_type: "points",
  rate: "0.1",
  eligibility_config: {},
  status: "draft",
  effective_from: null,
  effective_to: null,
  published_by: null,
  published_at: null,
  record_version: 1,
  created_by: "staff-1",
  created_at: "2026-08-17T00:00:00.000Z",
  updated_at: "2026-08-17T00:00:00.000Z",
};

const ACCOUNT_ROW = {
  id: ACCOUNT_ID,
  tenant_id: TENANT_ID,
  customer_account_id: CUSTOMER_ACCOUNT_ID,
  program_id: PROGRAM_ID,
  status: "active",
  enrolled_at: "2026-08-17T00:00:00.000Z",
  closed_by: null,
  closed_at: null,
  closed_reason: null,
  record_version: 1,
  created_at: "2026-08-17T00:00:00.000Z",
  updated_at: "2026-08-17T00:00:00.000Z",
};

const EVENT_ROW = {
  id: EVENT_ID,
  tenant_id: TENANT_ID,
  loyalty_account_id: ACCOUNT_ID,
  program_id: PROGRAM_ID,
  rule_version_id: RULE_VERSION_ID,
  reward_type: "points",
  amount: "110",
  source_type: "finance_invoice_paid",
  source_id: AR_OPEN_ITEM_ID,
  idempotency_key: `ar-open-item:${AR_OPEN_ITEM_ID}`,
  corrects_event_id: null,
  reason: null,
  created_by: "staff-1",
  created_at: "2026-08-17T00:00:00.000Z",
};

describe("createLoyaltyProgram / updateLoyaltyProgramStatus", () => {
  test("createLoyaltyProgram passes the exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [PROGRAM_ROW], error: null });
    const result = await createLoyaltyProgram(client, { tenantId: TENANT_ID, name: "Freight Rewards", actorAuthUserId: ACTOR_ID, actorLabel: "staff-1" });
    assert.equal(result.name, "Freight Rewards");
    assert.deepEqual(calls[0], {
      fn: "create_loyalty_program",
      args: { p_tenant_id: TENANT_ID, p_name: "Freight Rewards", p_description: null, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "staff-1" },
    });
  });

  test("createLoyaltyProgram classifies insufficient_authority", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity x lacks LYL:Create (no_granting_role) for tenant y" } });
    await assert.rejects(
      () => createLoyaltyProgram(client, { tenantId: TENANT_ID, name: "Freight Rewards", actorAuthUserId: ACTOR_ID, actorLabel: "no-role" }),
      (error: unknown) => error instanceof LoyaltyProgramMutationError && error.code === "insufficient_authority",
    );
  });

  test("updateLoyaltyProgramStatus passes the exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...PROGRAM_ROW, status: "inactive" }], error: null });
    const result = await updateLoyaltyProgramStatus(client, { tenantId: TENANT_ID, programId: PROGRAM_ID, expectedVersion: 1, newStatus: "inactive", actorAuthUserId: ACTOR_ID, actorLabel: "staff-1" });
    assert.equal(result.status, "inactive");
    assert.deepEqual(calls[0], {
      fn: "update_loyalty_program_status",
      args: { p_tenant_id: TENANT_ID, p_program_id: PROGRAM_ID, p_expected_version: 1, p_new_status: "inactive", p_actor_auth_user_id: ACTOR_ID, p_actor_label: "staff-1" },
    });
  });

  test("updateLoyaltyProgramStatus classifies invalid_transition", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "invalid_transition: draft -> inactive is not a canonical loyalty program transition" } });
    await assert.rejects(
      () => updateLoyaltyProgramStatus(client, { tenantId: TENANT_ID, programId: PROGRAM_ID, expectedVersion: 1, newStatus: "inactive", actorAuthUserId: ACTOR_ID, actorLabel: "staff-1" }),
      (error: unknown) => error instanceof LoyaltyProgramMutationError && error.code === "invalid_transition",
    );
  });
});

describe("rule version lifecycle", () => {
  test("createLoyaltyProgramRuleVersion passes the exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [RULE_VERSION_ROW], error: null });
    const result = await createLoyaltyProgramRuleVersion(client, {
      tenantId: TENANT_ID,
      programId: PROGRAM_ID,
      earningBasis: "per_paid_invoice_amount",
      rewardType: "points",
      rate: 0.1,
      eligibilityConfig: {},
      actorAuthUserId: ACTOR_ID,
      actorLabel: "staff-1",
    });
    assert.equal(result.status, "draft");
    assert.deepEqual(calls[0], {
      fn: "create_loyalty_program_rule_version",
      args: { p_tenant_id: TENANT_ID, p_program_id: PROGRAM_ID, p_earning_basis: "per_paid_invoice_amount", p_reward_type: "points", p_rate: 0.1, p_eligibility_config: {}, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "staff-1" },
    });
  });

  test("createLoyaltyProgramRuleVersion classifies draft_already_exists", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "draft_already_exists: program x already has an open draft rule version" } });
    await assert.rejects(
      () =>
        createLoyaltyProgramRuleVersion(client, {
          tenantId: TENANT_ID,
          programId: PROGRAM_ID,
          earningBasis: "per_paid_invoice_amount",
          rewardType: "points",
          rate: 0.1,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "staff-1",
        }),
      (error: unknown) => error instanceof LoyaltyProgramMutationError && error.code === "draft_already_exists",
    );
  });

  test("updateLoyaltyProgramRuleVersionDraft passes the exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...RULE_VERSION_ROW, rate: "0.15" }], error: null });
    await updateLoyaltyProgramRuleVersionDraft(client, {
      tenantId: TENANT_ID,
      ruleVersionId: RULE_VERSION_ID,
      expectedVersion: 1,
      earningBasis: "per_paid_invoice_amount",
      rewardType: "points",
      rate: 0.15,
      eligibilityConfig: { min_invoice_amount: 100 },
      actorAuthUserId: ACTOR_ID,
      actorLabel: "staff-1",
    });
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_rule_version_id: RULE_VERSION_ID,
      p_expected_version: 1,
      p_earning_basis: "per_paid_invoice_amount",
      p_reward_type: "points",
      p_rate: 0.15,
      p_eligibility_config: { min_invoice_amount: 100 },
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "staff-1",
    });
  });

  test("publishLoyaltyProgramRuleVersion passes the exact param names and maps the published row", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...RULE_VERSION_ROW, status: "published", published_by: "staff-1", published_at: "2026-08-17T00:00:00.000Z", effective_from: "2026-08-17T00:00:00.000Z" }], error: null });
    const result = await publishLoyaltyProgramRuleVersion(client, { tenantId: TENANT_ID, ruleVersionId: RULE_VERSION_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "staff-1" });
    assert.equal(result.status, "published");
    assert.deepEqual(calls[0], {
      fn: "publish_loyalty_program_rule_version",
      args: { p_tenant_id: TENANT_ID, p_rule_version_id: RULE_VERSION_ID, p_expected_version: 1, p_effective_from: null, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "staff-1" },
    });
  });

  test("publishLoyaltyProgramRuleVersion classifies stale_version", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "stale_version: rule version x expected version 1 but found 2" } });
    await assert.rejects(
      () => publishLoyaltyProgramRuleVersion(client, { tenantId: TENANT_ID, ruleVersionId: RULE_VERSION_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "staff-1" }),
      (error: unknown) => error instanceof LoyaltyProgramMutationError && error.code === "stale_version",
    );
  });
});

describe("loyalty account enrollment/lifecycle", () => {
  test("enrollCustomerLoyaltyAccount passes the exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [ACCOUNT_ROW], error: null });
    const result = await enrollCustomerLoyaltyAccount(client, { tenantId: TENANT_ID, customerAccountId: CUSTOMER_ACCOUNT_ID, programId: PROGRAM_ID, actorAuthUserId: ACTOR_ID, actorLabel: "staff-1" });
    assert.equal(result.status, "active");
    assert.deepEqual(calls[0], {
      fn: "enroll_customer_loyalty_account",
      args: { p_tenant_id: TENANT_ID, p_customer_account_id: CUSTOMER_ACCOUNT_ID, p_program_id: PROGRAM_ID, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "staff-1" },
    });
  });

  test("enrollCustomerLoyaltyAccount classifies customer_already_has_active_enrollment", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "customer_already_has_active_enrollment: account x already holds an active loyalty enrollment in a different program" } });
    await assert.rejects(
      () => enrollCustomerLoyaltyAccount(client, { tenantId: TENANT_ID, customerAccountId: CUSTOMER_ACCOUNT_ID, programId: PROGRAM_ID, actorAuthUserId: ACTOR_ID, actorLabel: "staff-1" }),
      (error: unknown) => error instanceof LoyaltyProgramMutationError && error.code === "customer_already_has_active_enrollment",
    );
  });

  test("setLoyaltyAccountStatus passes the exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...ACCOUNT_ROW, status: "suspended" }], error: null });
    const result = await setLoyaltyAccountStatus(client, { tenantId: TENANT_ID, accountId: ACCOUNT_ID, expectedVersion: 1, newStatus: "suspended", reason: "fraud review", actorAuthUserId: ACTOR_ID, actorLabel: "staff-1" });
    assert.equal(result.status, "suspended");
    assert.deepEqual(calls[0], {
      fn: "set_loyalty_account_status",
      args: { p_tenant_id: TENANT_ID, p_account_id: ACCOUNT_ID, p_expected_version: 1, p_new_status: "suspended", p_reason: "fraud review", p_actor_auth_user_id: ACTOR_ID, p_actor_label: "staff-1" },
    });
  });

  test("setLoyaltyAccountStatus classifies reason_required", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "reason_required: a non-empty reason is required to suspended a loyalty account" } });
    await assert.rejects(
      () => setLoyaltyAccountStatus(client, { tenantId: TENANT_ID, accountId: ACCOUNT_ID, expectedVersion: 1, newStatus: "suspended", actorAuthUserId: ACTOR_ID, actorLabel: "staff-1" }),
      (error: unknown) => error instanceof LoyaltyProgramMutationError && error.code === "reason_required",
    );
  });
});

describe("earning ledger: evaluate / reverse", () => {
  test("evaluateCustomerLoyaltyEarningForPaidInvoice passes the exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [EVENT_ROW], error: null });
    const result = await evaluateCustomerLoyaltyEarningForPaidInvoice(client, { tenantId: TENANT_ID, arOpenItemId: AR_OPEN_ITEM_ID, actorAuthUserId: ACTOR_ID, actorLabel: "staff-1" });
    assert.equal(result.amount, 110);
    assert.deepEqual(calls[0], {
      fn: "evaluate_customer_loyalty_earning_for_paid_invoice",
      args: { p_tenant_id: TENANT_ID, p_ar_open_item_id: AR_OPEN_ITEM_ID, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "staff-1" },
    });
  });

  test("evaluateCustomerLoyaltyEarningForPaidInvoice classifies ar_open_item_not_paid", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "ar_open_item_not_paid: x is open -- only a fully paid open item is eligible for loyalty earning" } });
    await assert.rejects(
      () => evaluateCustomerLoyaltyEarningForPaidInvoice(client, { tenantId: TENANT_ID, arOpenItemId: AR_OPEN_ITEM_ID, actorAuthUserId: ACTOR_ID, actorLabel: "staff-1" }),
      (error: unknown) => error instanceof LoyaltyProgramMutationError && error.code === "ar_open_item_not_paid",
    );
  });

  test("evaluateCustomerLoyaltyEarningForPaidInvoice classifies ar_open_item_held", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "ar_open_item_held: x is currently held -- a held item is not eligible for loyalty earning" } });
    await assert.rejects(
      () => evaluateCustomerLoyaltyEarningForPaidInvoice(client, { tenantId: TENANT_ID, arOpenItemId: AR_OPEN_ITEM_ID, actorAuthUserId: ACTOR_ID, actorLabel: "staff-1" }),
      (error: unknown) => error instanceof LoyaltyProgramMutationError && error.code === "ar_open_item_held",
    );
  });

  test("reverseLoyaltyEarningEvent passes the exact param names and returns a negative-amount linked row", async () => {
    const REVERSAL_ROW = { ...EVENT_ROW, id: "923e4567-e89b-12d3-a456-426614174000", amount: "-110", source_type: "reversal", source_id: EVENT_ID, idempotency_key: `reversal:${EVENT_ID}`, corrects_event_id: EVENT_ID, reason: "duplicate award" };
    const { client, calls } = fakeRpcClient({ data: [REVERSAL_ROW], error: null });
    const result = await reverseLoyaltyEarningEvent(client, { tenantId: TENANT_ID, eventId: EVENT_ID, reason: "duplicate award", idempotencyKey: `reversal:${EVENT_ID}`, actorAuthUserId: ACTOR_ID, actorLabel: "staff-1" });
    assert.equal(result.amount, -110);
    assert.equal(result.correctsEventId, EVENT_ID);
    assert.deepEqual(calls[0], {
      fn: "reverse_loyalty_earning_event",
      args: { p_tenant_id: TENANT_ID, p_event_id: EVENT_ID, p_reason: "duplicate award", p_idempotency_key: `reversal:${EVENT_ID}`, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "staff-1" },
    });
  });

  test("reverseLoyaltyEarningEvent classifies already_reversed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "already_reversed: loyalty earning event x has already been reversed" } });
    await assert.rejects(
      () => reverseLoyaltyEarningEvent(client, { tenantId: TENANT_ID, eventId: EVENT_ID, reason: "attempt again", idempotencyKey: "reversal:again", actorAuthUserId: ACTOR_ID, actorLabel: "staff-1" }),
      (error: unknown) => error instanceof LoyaltyProgramMutationError && error.code === "already_reversed",
    );
  });

  test("reverseLoyaltyEarningEvent requires a non-empty reason at the Zod boundary, before ever calling the RPC", async () => {
    const { client, calls } = fakeRpcClient({ data: [EVENT_ROW], error: null });
    await assert.rejects(() =>
      reverseLoyaltyEarningEvent(client, {
        tenantId: TENANT_ID,
        eventId: EVENT_ID,
        reason: "",
        idempotencyKey: "reversal:x",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "staff-1",
      }),
    );
    assert.equal(calls.length, 0);
  });
});
