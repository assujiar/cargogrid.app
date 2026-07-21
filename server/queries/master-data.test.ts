import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { resolveMasterRecord, searchMasterRecords, MasterDataQueryError, type MasterDataQueryRpcClient } from "./master-data.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const RECORD_ID = "323e4567-e89b-12d3-a456-426614174000";

const RECORD_ROW = {
  id: RECORD_ID,
  master_type_code: "vendor_rate",
  tenant_id: TENANT_ID,
  code: "VR-001",
  name: "Sample Vendor Rate",
  aliases: [],
  attributes: {},
  canonical_status: "active",
  merged_into_id: null,
  effective_from: "2026-07-17T00:00:00.000Z",
  effective_to: null,
  created_by: "tester",
  deactivated_at: null,
  deactivated_by: null,
  deactivated_reason: null,
  merged_at: null,
  merged_by: null,
  record_version: 1,
  created_at: "2026-07-17T00:00:00.000Z",
  updated_at: "2026-07-17T00:00:00.000Z",
};

function fakeClient(response: { data: unknown; error: { message: string } | null }): MasterDataQueryRpcClient & { calls: number } {
  let calls = 0;
  return {
    get calls() {
      return calls;
    },
    async rpc(_fn, _args) {
      calls += 1;
      return response;
    },
  };
}

describe("resolveMasterRecord", () => {
  test("parses a matched row (array response, matching Supabase's table-returning RPC shape)", async () => {
    const client = fakeClient({ data: [RECORD_ROW], error: null });
    const record = await resolveMasterRecord(client, { masterTypeCode: "vendor_rate", tenantId: TENANT_ID, codeOrAlias: "VR-001" });
    assert.equal(record?.code, "VR-001");
  });

  test("returns null for no match (empty array response)", async () => {
    const client = fakeClient({ data: [], error: null });
    const record = await resolveMasterRecord(client, { masterTypeCode: "vendor_rate", tenantId: TENANT_ID, codeOrAlias: "UNKNOWN" });
    assert.equal(record, null);
  });

  test("wraps a database error into a typed MasterDataQueryError", async () => {
    const client = fakeClient({ data: null, error: { message: "connection reset" } });
    await assert.rejects(
      () => resolveMasterRecord(client, { masterTypeCode: "vendor_rate", tenantId: TENANT_ID, codeOrAlias: "VR-001" }),
      (err: unknown) => {
        assert.ok(err instanceof MasterDataQueryError);
        return true;
      },
    );
  });
});

describe("searchMasterRecords", () => {
  test("calls search_master_records with defaults applied", async () => {
    const client = fakeClient({ data: [RECORD_ROW], error: null }) as MasterDataQueryRpcClient & { calls: number };
    let capturedArgs: Record<string, unknown> | undefined;
    client.rpc = async (_fn, args) => {
      capturedArgs = args;
      return { data: [RECORD_ROW], error: null };
    };
    await searchMasterRecords(client, { masterTypeCode: "vendor_rate", tenantId: TENANT_ID });
    assert.deepEqual(capturedArgs, {
      p_master_type_code: "vendor_rate",
      p_tenant_id: TENANT_ID,
      p_query: null,
      p_limit: 50,
      p_after_code: null,
    });
  });

  test("rejects a limit above 200 before ever calling the RPC", async () => {
    const client = fakeClient({ data: [RECORD_ROW], error: null });
    await assert.rejects(() => searchMasterRecords(client, { masterTypeCode: "vendor_rate", tenantId: TENANT_ID, limit: 500 }));
    assert.equal(client.calls, 0);
  });
});
