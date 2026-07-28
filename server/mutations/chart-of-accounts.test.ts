import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createFinanceAccountDraft,
  amendFinanceAccountDraft,
  activateFinanceAccount,
  deactivateFinanceAccount,
  ChartOfAccountsMutationError,
  type ChartOfAccountsMutationRpcClient,
} from "./chart-of-accounts.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "423e4567-e89b-12d3-a456-426614174000";

const VALID_ACCOUNT_ROW = {
  id: ACCOUNT_ID,
  tenant_id: TENANT_ID,
  company_id: null,
  code: "1200-AR",
  name: "Accounts Receivable",
  account_type: "asset",
  normal_balance: "debit",
  parent_account_id: null,
  is_control_account: false,
  is_postable: true,
  currency_restriction: null,
  status: "draft",
  record_version: 1,
  created_by: "finance-admin",
  created_at: "2026-07-28T00:00:00.000Z",
  updated_at: "2026-07-28T00:00:00.000Z",
};

function fakeClient(
  response: { data: unknown; error: { message: string } | null },
): ChartOfAccountsMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as ChartOfAccountsMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] };
}

describe("createFinanceAccountDraft", () => {
  test("calls create_finance_account_draft with the exact snake_case params", async () => {
    const client = fakeClient({ data: VALID_ACCOUNT_ROW, error: null });
    await createFinanceAccountDraft(client, {
      tenantId: TENANT_ID,
      code: "1200-AR",
      name: "Accounts Receivable",
      accountType: "asset",
      normalBalance: "debit",
      actorAuthUserId: ACTOR_ID,
      createdBy: "finance-admin",
    });

    assert.deepEqual(client.calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_company_id: null,
      p_code: "1200-AR",
      p_name: "Accounts Receivable",
      p_account_type: "asset",
      p_normal_balance: "debit",
      p_parent_account_id: null,
      p_is_control_account: false,
      p_currency_restriction: null,
      p_actor_auth_user_id: ACTOR_ID,
      p_created_by: "finance-admin",
    });
  });

  test("wraps a finance_account_duplicate_code error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_account_duplicate_code: code 1200-AR already exists in this tenant/company scope" } });
    await assert.rejects(
      () =>
        createFinanceAccountDraft(client, {
          tenantId: TENANT_ID,
          code: "1200-AR",
          name: "Accounts Receivable",
          accountType: "asset",
          normalBalance: "debit",
          actorAuthUserId: ACTOR_ID,
          createdBy: "finance-admin",
        }),
      (err: unknown) => {
        assert.ok(err instanceof ChartOfAccountsMutationError);
        assert.equal(err.code, "finance_account_duplicate_code");
        return true;
      },
    );
  });
});

describe("amendFinanceAccountDraft", () => {
  test("calls amend_finance_account_draft with the exact snake_case params", async () => {
    const client = fakeClient({ data: { ...VALID_ACCOUNT_ROW, name: "Accounts Receivable -- Trade" }, error: null });
    const account = await amendFinanceAccountDraft(client, { accountId: ACCOUNT_ID, expectedVersion: 1, name: "Accounts Receivable -- Trade", actorAuthUserId: ACTOR_ID, actorLabel: "finance-admin" });
    assert.equal(account.name, "Accounts Receivable -- Trade");
  });

  test("wraps a finance_account_not_draft error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_account_not_draft: account is active, only a draft may be amended" } });
    await assert.rejects(
      () => amendFinanceAccountDraft(client, { accountId: ACCOUNT_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "finance-admin" }),
      (err: unknown) => {
        assert.ok(err instanceof ChartOfAccountsMutationError);
        assert.equal(err.code, "finance_account_not_draft");
        return true;
      },
    );
  });
});

describe("activateFinanceAccount", () => {
  test("calls activate_finance_account and returns the activated row", async () => {
    const client = fakeClient({ data: { ...VALID_ACCOUNT_ROW, status: "active" }, error: null });
    const account = await activateFinanceAccount(client, { accountId: ACCOUNT_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "finance-admin" });
    assert.equal(account.status, "active");
  });

  test("wraps a finance_account_hierarchy_cycle error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_account_hierarchy_cycle: activating account would create or confirm a cyclic/over-deep hierarchy" } });
    await assert.rejects(
      () => activateFinanceAccount(client, { accountId: ACCOUNT_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "finance-admin" }),
      (err: unknown) => {
        assert.ok(err instanceof ChartOfAccountsMutationError);
        assert.equal(err.code, "finance_account_hierarchy_cycle");
        return true;
      },
    );
  });
});

describe("deactivateFinanceAccount", () => {
  test("calls deactivate_finance_account with the exact snake_case params including the mandatory reason", async () => {
    const client = fakeClient({ data: { ...VALID_ACCOUNT_ROW, status: "inactive" }, error: null });
    await deactivateFinanceAccount(client, { accountId: ACCOUNT_ID, expectedVersion: 2, reason: "superseded by a restructured chart", actorAuthUserId: ACTOR_ID, actorLabel: "finance-admin" });

    assert.deepEqual(client.calls[0]?.args, {
      p_account_id: ACCOUNT_ID,
      p_expected_version: 2,
      p_reason: "superseded by a restructured chart",
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "finance-admin",
    });
  });

  test("wraps a finance_account_has_active_children error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_account_has_active_children: account has 2 active/draft child account(s) -- deactivate or reparent them first" } });
    await assert.rejects(
      () => deactivateFinanceAccount(client, { accountId: ACCOUNT_ID, expectedVersion: 2, reason: "trying anyway", actorAuthUserId: ACTOR_ID, actorLabel: "finance-admin" }),
      (err: unknown) => {
        assert.ok(err instanceof ChartOfAccountsMutationError);
        assert.equal(err.code, "finance_account_has_active_children");
        return true;
      },
    );
  });

  test("wraps a finance_account_referenced_by_posting_map error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_account_referenced_by_posting_map: account is referenced by a published posting map -- update the posting map first" } });
    await assert.rejects(
      () => deactivateFinanceAccount(client, { accountId: ACCOUNT_ID, expectedVersion: 2, reason: "trying anyway", actorAuthUserId: ACTOR_ID, actorLabel: "finance-admin" }),
      (err: unknown) => {
        assert.ok(err instanceof ChartOfAccountsMutationError);
        assert.equal(err.code, "finance_account_referenced_by_posting_map");
        return true;
      },
    );
  });
});
