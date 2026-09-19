import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { createItemMaster, updateItemMaster, setItemMasterStatus, validateItemImportRow, commitItemImportJob, ItemUomMasterMutationError, type ItemUomMasterMutationRpcClient } from "./item-uom-master.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ITEM_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "723e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const JOB_ID = "823e4567-e89b-12d3-a456-426614174000";
const ROW_ID = "923e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: ItemUomMasterMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as ItemUomMasterMutationRpcClient;
  return { client, calls };
}

const ITEM_ROW = {
  id: ITEM_ID,
  tenant_id: TENANT_ID,
  owner_account_id: ACCOUNT_ID,
  code: "SKU-100",
  name: "Test Widget",
  description: null,
  base_uom_code: "PCS",
  lot_controlled: false,
  serial_controlled: false,
  expiry_controlled: false,
  status: "active",
  record_version: 1,
  created_by: "rep",
  created_at: "2026-08-03T00:00:00.000Z",
  updated_at: "2026-08-03T00:00:00.000Z",
};

describe("createItemMaster", () => {
  test("sends the mapped RPC args and parses the response row", async () => {
    const { client, calls } = fakeRpcClient({ data: [ITEM_ROW], error: null });
    const item = await createItemMaster(client, {
      tenantId: TENANT_ID,
      ownerAccountId: ACCOUNT_ID,
      code: "SKU-100",
      name: "Test Widget",
      description: null,
      baseUomCode: "PCS",
      lotControlled: false,
      serialControlled: false,
      expiryControlled: false,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(item.code, "SKU-100");
    assert.equal(calls[0]?.fn, "create_item_master");
    assert.equal(calls[0]?.args.p_owner_account_id, ACCOUNT_ID);
    assert.equal(calls[0]?.args.p_base_uom_code, "PCS");
  });

  test("classifies a known error prefix", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "owner_account_not_found: nope is not an active account" } });
    await assert.rejects(
      () =>
        createItemMaster(client, {
          tenantId: TENANT_ID,
          ownerAccountId: ACCOUNT_ID,
          code: "SKU-100",
          name: "Test Widget",
          description: null,
          baseUomCode: "PCS",
          lotControlled: false,
          serialControlled: false,
          expiryControlled: false,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => err instanceof ItemUomMasterMutationError && err.code === "owner_account_not_found",
    );
  });

  test("classifies an unrecognized error prefix as mutation_failed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "some_unexpected_db_error: boom" } });
    await assert.rejects(
      () =>
        createItemMaster(client, {
          tenantId: TENANT_ID,
          ownerAccountId: ACCOUNT_ID,
          code: "SKU-100",
          name: "Test Widget",
          description: null,
          baseUomCode: "PCS",
          lotControlled: false,
          serialControlled: false,
          expiryControlled: false,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => err instanceof ItemUomMasterMutationError && err.code === "mutation_failed",
    );
  });

  test("throws invalid_response when the RPC returns no row", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    await assert.rejects(
      () =>
        createItemMaster(client, {
          tenantId: TENANT_ID,
          ownerAccountId: ACCOUNT_ID,
          code: "SKU-100",
          name: "Test Widget",
          description: null,
          baseUomCode: "PCS",
          lotControlled: false,
          serialControlled: false,
          expiryControlled: false,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => err instanceof ItemUomMasterMutationError && err.code === "invalid_response",
    );
  });
});

describe("updateItemMaster", () => {
  test("sends the mapped RPC args (no code/owner/uom params exist -- immutable)", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...ITEM_ROW, name: "Renamed", record_version: 2 }], error: null });
    const item = await updateItemMaster(client, {
      itemMasterId: ITEM_ID,
      name: "Renamed",
      description: "updated",
      lotControlled: true,
      serialControlled: false,
      expiryControlled: true,
      expectedVersion: 1,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(item.name, "Renamed");
    assert.equal(calls[0]?.fn, "update_item_master");
    assert.equal(calls[0]?.args.p_expected_version, 1);
    assert.equal("p_code" in (calls[0]?.args ?? {}), false);
  });

  test("classifies stale_version", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "stale_version: item master x expected version 1 but found 2" } });
    await assert.rejects(
      () =>
        updateItemMaster(client, {
          itemMasterId: ITEM_ID,
          name: "Renamed",
          description: null,
          lotControlled: false,
          serialControlled: false,
          expiryControlled: false,
          expectedVersion: 1,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => err instanceof ItemUomMasterMutationError && err.code === "stale_version",
    );
  });
});

describe("setItemMasterStatus", () => {
  test("sends the mapped RPC args and parses the response row", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...ITEM_ROW, status: "inactive", record_version: 2 }], error: null });
    const item = await setItemMasterStatus(client, {
      itemMasterId: ITEM_ID,
      newStatus: "inactive",
      reason: "discontinued",
      expectedVersion: 1,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(item.status, "inactive");
    assert.equal(calls[0]?.fn, "set_item_master_status");
    assert.equal(calls[0]?.args.p_reason, "discontinued");
  });

  test("classifies invalid_reason (deactivation requires a reason)", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "invalid_reason: a reason is required to deactivate an item master" } });
    await assert.rejects(
      () =>
        setItemMasterStatus(client, {
          itemMasterId: ITEM_ID,
          newStatus: "inactive",
          reason: null,
          expectedVersion: 1,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => err instanceof ItemUomMasterMutationError && err.code === "invalid_reason",
    );
  });
});

describe("validateItemImportRow (CG-AUDIT-2026-09-02 A4)", () => {
  test("calls validate_item_import_row with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({
      data: {
        id: ROW_ID,
        tenant_id: TENANT_ID,
        job_id: JOB_ID,
        row_number: 1,
        raw_payload: { code: "SKU-100" },
        validation_status: "valid",
        error: null,
        created_at: "2026-09-17T00:00:00.000Z",
      },
      error: null,
    });
    const row = await validateItemImportRow(client, { stagingRowId: ROW_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" });

    assert.deepEqual(calls[0]?.args, { p_staging_row_id: ROW_ID, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "tester" });
    assert.equal(row.validationStatus, "valid");
  });

  test("wraps a database error into a typed ItemUomMasterMutationError", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "import_export_staging_row_not_found: no staging row" } });
    await assert.rejects(() => validateItemImportRow(client, { stagingRowId: ROW_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }), ItemUomMasterMutationError);
  });
});

describe("commitItemImportJob (CG-AUDIT-2026-09-02 A4)", () => {
  test("calls commit_item_import_job with the exact snake_case params, including client IP, defaulting allowPartial to false", async () => {
    const { client, calls } = fakeRpcClient({
      data: {
        job_id: JOB_ID,
        tenant_id: TENANT_ID,
        job_type: "import",
        status: "completed",
        priority: 0,
        payload: {},
        attempts: 0,
        max_attempts: 3,
        locked_by: null,
        locked_until: null,
        error: null,
        result_url: null,
        created_by: "tester",
        created_at: "2026-09-17T00:00:00.000Z",
        completed_at: "2026-09-17T00:05:00.000Z",
        requested_by_auth_user_id: ACTOR_ID,
        idempotency_key: "idem-item-import-job",
        import_export_schema_code: "item_import",
        source_file_id: "a23e4567-e89b-12d3-a456-426614174000",
        result_file_id: null,
        total_rows: 1,
        processed_rows: 1,
        valid_row_count: 1,
        invalid_row_count: 0,
        cancel_reason: null,
        updated_at: "2026-09-17T00:05:00.000Z",
      },
      error: null,
    });
    const job = await commitItemImportJob(client, { jobId: JOB_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester", clientIp: "203.0.113.5" });

    assert.deepEqual(calls[0]?.args, { p_job_id: JOB_ID, p_allow_partial: false, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "tester", p_client_ip: "203.0.113.5" });
    assert.equal(job.status, "completed");
  });

  test("classifies import_owner_account_not_found and import_blocked_legal_hold", async () => {
    const ownerClient = fakeRpcClient({ data: null, error: { message: "import_owner_account_not_found: staged row 3 names owner_account_tax_id x, which no longer resolves to exactly one active account in tenant y" } }).client;
    await assert.rejects(
      () => commitItemImportJob(ownerClient, { jobId: JOB_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof ItemUomMasterMutationError);
        assert.equal(err.code, "import_owner_account_not_found");
        return true;
      },
    );
    const holdClient = fakeRpcClient({ data: null, error: { message: "import_blocked_legal_hold: item master x is under legal hold, this import commit cannot target it" } }).client;
    await assert.rejects(
      () => commitItemImportJob(holdClient, { jobId: JOB_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof ItemUomMasterMutationError);
        assert.equal(err.code, "import_blocked_legal_hold");
        return true;
      },
    );
  });

  test("classifies mfa_step_up_required and ip_not_allowed", async () => {
    const mfaClient = fakeRpcClient({ data: null, error: { message: "mfa_step_up_required: OPS:Import requires a current MFA step-up verification" } }).client;
    await assert.rejects(
      () => commitItemImportJob(mfaClient, { jobId: JOB_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof ItemUomMasterMutationError);
        assert.equal(err.code, "mfa_step_up_required");
        return true;
      },
    );
    const ipClient = fakeRpcClient({ data: null, error: { message: "ip_not_allowed: malformed IP address denied for scope" } }).client;
    await assert.rejects(
      () => commitItemImportJob(ipClient, { jobId: JOB_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester", clientIp: "bad-ip" }),
      (err: unknown) => {
        assert.ok(err instanceof ItemUomMasterMutationError);
        assert.equal(err.code, "ip_not_allowed");
        return true;
      },
    );
  });
});
