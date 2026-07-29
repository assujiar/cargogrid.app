import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  resolveFinanceConfig,
  previewFinanceConfigImpact,
  listFinanceConfigVersions,
  getFinanceConfigVersionItems,
  listFinanceRoundingModes,
  FinanceConfigResolutionCache,
  FinanceConfigQueryError,
  type FinanceConfigQueryRpcClient,
  type FinanceRoundingModesTableClient,
} from "./finance-config.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const VERSION_ID = "423e4567-e89b-12d3-a456-426614174000";

const RESOLVED_ROW = {
  config_type_code: "finance_rounding",
  resolved_scope_level: "tenant",
  resolved_version_id: VERSION_ID,
  effective_from: "2026-07-28T00:00:00.000Z",
  items: { default: { mode: "round_half_up", precision: 2, order: "convert_then_round" } },
};

function fakeClient(response: { data: unknown; error: { message: string } | null }): FinanceConfigQueryRpcClient & { calls: number } {
  let calls = 0;
  return {
    get calls() {
      return calls;
    },
    async rpc(_fn: string, _args: Record<string, unknown>) {
      calls += 1;
      return response;
    },
  } as unknown as FinanceConfigQueryRpcClient & { calls: number };
}

describe("resolveFinanceConfig", () => {
  test("parses a resolved row (array response, matching Supabase's table-returning RPC shape)", async () => {
    const client = fakeClient({ data: [RESOLVED_ROW], error: null });
    const resolved = await resolveFinanceConfig(client, { configTypeCode: "finance_rounding", tenantId: TENANT_ID });
    assert.equal(resolved?.resolvedScopeLevel, "tenant");
  });

  test("returns null when no level resolves (empty array response)", async () => {
    const client = fakeClient({ data: [], error: null });
    const resolved = await resolveFinanceConfig(client, { configTypeCode: "finance_rounding", tenantId: TENANT_ID });
    assert.equal(resolved, null);
  });

  test("wraps a database error into a typed FinanceConfigQueryError", async () => {
    const client = fakeClient({ data: null, error: { message: "connection reset" } });
    await assert.rejects(
      () => resolveFinanceConfig(client, { configTypeCode: "finance_rounding", tenantId: TENANT_ID }),
      (err: unknown) => {
        assert.ok(err instanceof FinanceConfigQueryError);
        return true;
      },
    );
  });
});

describe("previewFinanceConfigImpact", () => {
  test("parses a structural preview result", async () => {
    const client = fakeClient({
      data: { configTypeCode: "finance_posting_map", valid: true, error: null, itemCount: 2, pendingChartOfAccountsRefs: ["4000-AR"] },
      error: null,
    });
    const preview = await previewFinanceConfigImpact(client, VERSION_ID);
    assert.equal(preview.valid, true);
    assert.deepEqual(preview.pendingChartOfAccountsRefs, ["4000-AR"]);
  });

  test("throws FinanceConfigQueryError when the RPC returns no result", async () => {
    const client = fakeClient({ data: null, error: null });
    await assert.rejects(() => previewFinanceConfigImpact(client, VERSION_ID), FinanceConfigQueryError);
  });
});

describe("listFinanceConfigVersions", () => {
  test("maps every returned row to the ConfigVersion contract shape", async () => {
    const client = fakeClient({
      data: [
        {
          id: VERSION_ID,
          config_object_id: "523e4567-e89b-12d3-a456-426614174000",
          version_number: 1,
          status: "draft",
          effective_from: null,
          effective_to: null,
          cloned_from_version_id: null,
          rollback_of_version_id: null,
          created_by: "finance-admin",
          published_by: null,
          published_at: null,
          archived_at: null,
          archived_reason: null,
          record_version: 1,
          created_at: "2026-07-28T00:00:00.000Z",
          updated_at: "2026-07-28T00:00:00.000Z",
        },
      ],
      error: null,
    });
    const versions = await listFinanceConfigVersions(client, {
      configTypeCode: "finance_rounding",
      tenantId: TENANT_ID,
      scopeLevel: "tenant",
      scopeId: null,
      actorAuthUserId: "623e4567-e89b-12d3-a456-426614174000",
    });
    assert.equal(versions.length, 1);
    assert.equal(versions[0]?.status, "draft");
  });
});

describe("getFinanceConfigVersionItems", () => {
  test("returns the raw item map for a draft's own current items", async () => {
    const client = fakeClient({ data: { default: { mode: "round_half_up", precision: 2, order: "convert_then_round" } }, error: null });
    const items = await getFinanceConfigVersionItems(client, VERSION_ID, "623e4567-e89b-12d3-a456-426614174000");
    assert.deepEqual(items, { default: { mode: "round_half_up", precision: 2, order: "convert_then_round" } });
  });

  test("returns an empty object when the RPC returns null (a draft with zero items yet)", async () => {
    const client = fakeClient({ data: null, error: null });
    const items = await getFinanceConfigVersionItems(client, VERSION_ID, "623e4567-e89b-12d3-a456-426614174000");
    assert.deepEqual(items, {});
  });

  test("wraps a database error into a typed FinanceConfigQueryError", async () => {
    const client = fakeClient({ data: null, error: { message: "insufficient_authority: identity lacks FIN:Edit for tenant" } });
    await assert.rejects(() => getFinanceConfigVersionItems(client, VERSION_ID, "623e4567-e89b-12d3-a456-426614174000"), FinanceConfigQueryError);
  });
});

describe("listFinanceRoundingModes", () => {
  function fakeTableClient(rows: unknown[]): FinanceRoundingModesTableClient {
    return {
      from: () => ({
        select: async () => ({ data: rows, error: null }),
      }),
    } as unknown as FinanceRoundingModesTableClient;
  }

  test("maps every rounding-mode reference row", async () => {
    const client = fakeTableClient([{ code: "round_half_up", name: "Round half up", description: "..." }]);
    const modes = await listFinanceRoundingModes(client);
    assert.equal(modes.length, 1);
    assert.equal(modes[0]?.code, "round_half_up");
  });
});

describe("FinanceConfigResolutionCache", () => {
  test("caches a positive resolution within the TTL without a second RPC call", async () => {
    const client = fakeClient({ data: [RESOLVED_ROW], error: null });
    const cache = new FinanceConfigResolutionCache(30_000);
    const now = 1_000_000;

    await resolveFinanceConfig(client, { configTypeCode: "finance_rounding", tenantId: TENANT_ID }, cache, now);
    await resolveFinanceConfig(client, { configTypeCode: "finance_rounding", tenantId: TENANT_ID }, cache, now + 1_000);

    assert.equal(client.calls, 1);
  });

  test("invalidate() clears every cached entry, forcing a re-fetch on the next call", async () => {
    const client = fakeClient({ data: [RESOLVED_ROW], error: null });
    const cache = new FinanceConfigResolutionCache(30_000);
    const now = 1_000_000;

    await resolveFinanceConfig(client, { configTypeCode: "finance_rounding", tenantId: TENANT_ID }, cache, now);
    cache.invalidate();
    await resolveFinanceConfig(client, { configTypeCode: "finance_rounding", tenantId: TENANT_ID }, cache, now + 1_000);

    assert.equal(client.calls, 2);
  });
});
