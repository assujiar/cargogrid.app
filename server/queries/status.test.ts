import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { resolveLegacyStatus, getStatusSetRegistry, resolveStatusPresentation, StatusPresentationCache, StatusQueryError, type StatusQueryRpcClient } from "./status.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const STATUS_ID = "323e4567-e89b-12d3-a456-426614174000";

const RESOLVED_ROW = {
  canonical_status_code: "draft",
  category: "initial",
  is_terminal: false,
  resolved_label: "Draft",
  resolved_color: "#6b7280",
  resolved_icon: "circle-dashed",
  is_fallback: false,
  resolved_version_id: STATUS_ID,
};

function fakeClient(
  response: { data: unknown; error: { message: string } | null },
): StatusQueryRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn, args) {
      calls.push({ fn, args });
      return response;
    },
  };
}

describe("resolveLegacyStatus", () => {
  test("calls resolve_legacy_status with the exact snake_case params", async () => {
    const client = fakeClient({
      data: {
        id: STATUS_ID,
        status_set_code: "quotation_status",
        code: "draft",
        category: "initial",
        sort_order: 0,
        registered_by: "tester",
        created_at: "2026-07-19T00:00:00.000Z",
        is_terminal: false,
      },
      error: null,
    });
    const status = await resolveLegacyStatus(client, { statusSetCode: "quotation_status", legacyValue: "PENDING" });
    assert.deepEqual(client.calls[0]?.args, { p_status_set_code: "quotation_status", p_legacy_value: "PENDING" });
    assert.equal(status.code, "draft");
  });

  test("throws StatusQueryError on an rpc error", async () => {
    const client = fakeClient({ data: null, error: { message: "status_legacy_value_unmapped: no mapping for legacy value x in set y" } });
    await assert.rejects(() => resolveLegacyStatus(client, { statusSetCode: "quotation_status", legacyValue: "UNKNOWN" }));
  });
});

describe("getStatusSetRegistry", () => {
  test("calls get_status_set_registry and maps rows", async () => {
    const client = fakeClient({
      data: [
        { id: STATUS_ID, status_set_code: "quotation_status", code: "draft", category: "initial", sort_order: 0, registered_by: "tester", created_at: "2026-07-19T00:00:00.000Z", is_terminal: false },
      ],
      error: null,
    });
    const statuses = await getStatusSetRegistry(client, { statusSetCode: "quotation_status" });
    assert.deepEqual(client.calls[0]?.args, { p_status_set_code: "quotation_status" });
    assert.equal(statuses.length, 1);
  });

  test("throws StatusQueryError if data is not an array", async () => {
    const client = fakeClient({ data: null, error: null });
    await assert.rejects(() => getStatusSetRegistry(client, { statusSetCode: "quotation_status" }));
  });
});

describe("resolveStatusPresentation", () => {
  test("calls resolve_status_presentation with the exact snake_case params", async () => {
    const client = fakeClient({ data: RESOLVED_ROW, error: null });
    const resolved = await resolveStatusPresentation(client, { statusSetCode: "quotation_status", canonicalStatusCode: "draft", tenantId: TENANT_ID });

    assert.deepEqual(client.calls[0]?.args, {
      p_status_set_code: "quotation_status",
      p_canonical_status_code: "draft",
      p_tenant_id: TENANT_ID,
      p_company_id: null,
      p_branch_id: null,
      p_role_id: null,
      p_user_id: null,
    });
    assert.equal(resolved.resolvedLabel, "Draft");
  });

  test("caches within TTL and does not re-issue the RPC call", async () => {
    const client = fakeClient({ data: RESOLVED_ROW, error: null });
    const cache = new StatusPresentationCache(60_000);
    const now = 1_000_000;

    await resolveStatusPresentation(client, { statusSetCode: "quotation_status", canonicalStatusCode: "draft", tenantId: TENANT_ID }, cache, now);
    await resolveStatusPresentation(client, { statusSetCode: "quotation_status", canonicalStatusCode: "draft", tenantId: TENANT_ID }, cache, now + 1000);

    assert.equal(client.calls.length, 1);
  });

  test("invalidate() clears the cache so the next call re-issues the RPC", async () => {
    const client = fakeClient({ data: RESOLVED_ROW, error: null });
    const cache = new StatusPresentationCache(60_000);
    const now = 1_000_000;

    await resolveStatusPresentation(client, { statusSetCode: "quotation_status", canonicalStatusCode: "draft", tenantId: TENANT_ID }, cache, now);
    cache.invalidate();
    await resolveStatusPresentation(client, { statusSetCode: "quotation_status", canonicalStatusCode: "draft", tenantId: TENANT_ID }, cache, now + 1000);

    assert.equal(client.calls.length, 2);
  });

  test("throws StatusQueryError on an rpc error", async () => {
    const client = fakeClient({ data: null, error: { message: "status_unknown_code: bogus is not a registered canonical status in set quotation_status" } });
    await assert.rejects(() => resolveStatusPresentation(client, { statusSetCode: "quotation_status", canonicalStatusCode: "bogus", tenantId: TENANT_ID }));
  });
});
