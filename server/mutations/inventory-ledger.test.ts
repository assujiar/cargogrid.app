import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  postInventoryMovement,
  reserveInventory,
  releaseInventoryReservation,
  consumeInventoryReservation,
  reverseInventoryMovement,
  validateInventoryOpeningBalanceImportRow,
  commitInventoryOpeningBalanceImportJob,
  InventoryLedgerMutationError,
  type InventoryLedgerMutationRpcClient,
} from "./inventory-ledger.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const WAREHOUSE_ID = "323e4567-e89b-12d3-a456-426614174000";
const MOVEMENT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const ITEM_ID = "723e4567-e89b-12d3-a456-426614174000";
const LOCATION_ID = "823e4567-e89b-12d3-a456-426614174000";
const BALANCE_ID = "a23e4567-e89b-12d3-a456-426614174000";
const RESERVATION_ID = "b23e4567-e89b-12d3-a456-426614174000";
const JOB_ID = "c23e4567-e89b-12d3-a456-426614174000";
const ROW_ID = "d23e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: InventoryLedgerMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as InventoryLedgerMutationRpcClient;
  return { client, calls };
}

const MOVEMENT_ROW = {
  id: MOVEMENT_ID,
  tenant_id: TENANT_ID,
  warehouse_id: WAREHOUSE_ID,
  movement_type: "opening_balance",
  source_type: "opening_balance",
  source_id: null,
  idempotency_key: "idem-open-1",
  corrects_movement_id: null,
  reason: null,
  occurred_at: "2026-08-03T00:00:00.000Z",
  posted_by: "rep",
  created_at: "2026-08-03T00:00:00.000Z",
};

const RESERVATION_ROW = {
  id: RESERVATION_ID,
  tenant_id: TENANT_ID,
  balance_id: BALANCE_ID,
  reserved_quantity: "5",
  status: "active",
  source_type: "manual",
  source_id: null,
  idempotency_key: "idem-reserve-1",
  released_reason: null,
  consumed_movement_id: null,
  record_version: 1,
  created_by: "rep",
  created_at: "2026-08-03T00:00:00.000Z",
  updated_at: "2026-08-03T00:00:00.000Z",
};

describe("postInventoryMovement", () => {
  test("sends the mapped RPC args, including nulled optional line fields, and parses the response row", async () => {
    const { client, calls } = fakeRpcClient({ data: [MOVEMENT_ROW], error: null });
    const movement = await postInventoryMovement(client, {
      tenantId: TENANT_ID,
      warehouseId: WAREHOUSE_ID,
      movementType: "opening_balance",
      sourceType: "opening_balance",
      idempotencyKey: "idem-open-1",
      lines: [{ ownerAccountId: ACCOUNT_ID, itemMasterId: ITEM_ID, locationId: LOCATION_ID, uomCode: "PCS", signedQuantity: 100 }],
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(movement.movementType, "opening_balance");
    assert.equal(calls[0]?.fn, "post_inventory_movement");
    const args = calls[0]?.args;
    assert.equal(args?.p_corrects_movement_id, null);
    const lines = args?.p_lines as Record<string, unknown>[];
    assert.equal(lines[0]?.lot_number, null);
    assert.equal(lines[0]?.signed_quantity, 100);
  });

  test("passes p_corrects_movement_id through for a reversal", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...MOVEMENT_ROW, movement_type: "reversal", corrects_movement_id: MOVEMENT_ID }], error: null });
    await postInventoryMovement(client, {
      tenantId: TENANT_ID,
      warehouseId: WAREHOUSE_ID,
      movementType: "reversal",
      sourceType: "reversal",
      idempotencyKey: "idem-reverse-1",
      reason: "wrong quantity",
      lines: [{ ownerAccountId: ACCOUNT_ID, itemMasterId: ITEM_ID, locationId: LOCATION_ID, uomCode: "PCS", signedQuantity: -100 }],
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
      correctsMovementId: MOVEMENT_ID,
    });
    assert.equal(calls[0]?.args.p_corrects_movement_id, MOVEMENT_ID);
  });

  test("classifies insufficient_stock", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_stock: movement would drive on_hand negative for item x at location y" } });
    await assert.rejects(
      () =>
        postInventoryMovement(client, {
          tenantId: TENANT_ID,
          warehouseId: WAREHOUSE_ID,
          movementType: "adjustment",
          sourceType: "manual",
          reason: "test",
          idempotencyKey: "idem-neg-1",
          lines: [{ ownerAccountId: ACCOUNT_ID, itemMasterId: ITEM_ID, locationId: LOCATION_ID, uomCode: "PCS", signedQuantity: -1000 }],
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => err instanceof InventoryLedgerMutationError && err.code === "insufficient_stock",
    );
  });

  test("classifies unbalanced_transfer", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "unbalanced_transfer: a transfer movement's own lines must sum to exactly zero, got -5" } });
    await assert.rejects(
      () =>
        postInventoryMovement(client, {
          tenantId: TENANT_ID,
          warehouseId: WAREHOUSE_ID,
          movementType: "transfer",
          sourceType: "manual",
          idempotencyKey: "idem-unbalanced-1",
          lines: [
            { ownerAccountId: ACCOUNT_ID, itemMasterId: ITEM_ID, locationId: LOCATION_ID, uomCode: "PCS", signedQuantity: -20 },
            { ownerAccountId: ACCOUNT_ID, itemMasterId: ITEM_ID, locationId: LOCATION_ID, uomCode: "PCS", signedQuantity: 15 },
          ],
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => err instanceof InventoryLedgerMutationError && err.code === "unbalanced_transfer",
    );
  });

  test("classifies an unrecognized error prefix as mutation_failed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "some_unexpected_db_error: boom" } });
    await assert.rejects(
      () =>
        postInventoryMovement(client, {
          tenantId: TENANT_ID,
          warehouseId: WAREHOUSE_ID,
          movementType: "opening_balance",
          sourceType: "opening_balance",
          idempotencyKey: "idem-open-1",
          lines: [{ ownerAccountId: ACCOUNT_ID, itemMasterId: ITEM_ID, locationId: LOCATION_ID, uomCode: "PCS", signedQuantity: 1 }],
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => err instanceof InventoryLedgerMutationError && err.code === "mutation_failed",
    );
  });
});

describe("reserveInventory", () => {
  test("sends the mapped RPC args and parses the response row", async () => {
    const { client, calls } = fakeRpcClient({ data: [RESERVATION_ROW], error: null });
    const reservation = await reserveInventory(client, {
      tenantId: TENANT_ID,
      warehouseId: WAREHOUSE_ID,
      ownerAccountId: ACCOUNT_ID,
      itemMasterId: ITEM_ID,
      locationId: LOCATION_ID,
      quantity: 5,
      sourceType: "manual",
      idempotencyKey: "idem-reserve-1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(reservation.status, "active");
    assert.equal(calls[0]?.fn, "reserve_inventory");
  });

  test("classifies insufficient_available_stock", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_available_stock: 3 available but 5 requested" } });
    await assert.rejects(
      () =>
        reserveInventory(client, {
          tenantId: TENANT_ID,
          warehouseId: WAREHOUSE_ID,
          ownerAccountId: ACCOUNT_ID,
          itemMasterId: ITEM_ID,
          locationId: LOCATION_ID,
          quantity: 5,
          sourceType: "manual",
          idempotencyKey: "idem-reserve-2",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => err instanceof InventoryLedgerMutationError && err.code === "insufficient_available_stock",
    );
  });
});

describe("releaseInventoryReservation", () => {
  test("classifies invalid_transition for a non-active reservation", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "invalid_transition: reservation x is released -- only an active reservation may be released" } });
    await assert.rejects(
      () => releaseInventoryReservation(client, { reservationId: RESERVATION_ID, reason: "no longer needed", actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => err instanceof InventoryLedgerMutationError && err.code === "invalid_transition",
    );
  });
});

describe("consumeInventoryReservation", () => {
  test("sends the mapped RPC args and parses the response row", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...RESERVATION_ROW, status: "consumed", consumed_movement_id: MOVEMENT_ID }], error: null });
    const reservation = await consumeInventoryReservation(client, { reservationId: RESERVATION_ID, idempotencyKey: "idem-consume-1", actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(reservation.status, "consumed");
    assert.equal(calls[0]?.fn, "consume_inventory_reservation");
  });
});

describe("reverseInventoryMovement", () => {
  test("classifies already_reversed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "already_reversed: movement x has already been reversed" } });
    await assert.rejects(
      () => reverseInventoryMovement(client, { movementId: MOVEMENT_ID, idempotencyKey: "idem-reverse-1", reason: "wrong quantity", actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => err instanceof InventoryLedgerMutationError && err.code === "already_reversed",
    );
  });

  test("classifies invalid_reversal", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "invalid_reversal: a reversal movement may not itself be reversed" } });
    await assert.rejects(
      () => reverseInventoryMovement(client, { movementId: MOVEMENT_ID, idempotencyKey: "idem-reverse-2", reason: "wrong quantity", actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => err instanceof InventoryLedgerMutationError && err.code === "invalid_reversal",
    );
  });
});

describe("validateInventoryOpeningBalanceImportRow (CG-AUDIT-2026-09-02 A4)", () => {
  test("calls validate_inventory_opening_balance_import_row with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({
      data: {
        id: ROW_ID,
        tenant_id: TENANT_ID,
        job_id: JOB_ID,
        row_number: 1,
        raw_payload: { warehouse_code: "WH-1", item_code: "ITEM-1", quantity: "10" },
        validation_status: "valid",
        error: null,
        created_at: "2026-09-17T00:00:00.000Z",
      },
      error: null,
    });
    const row = await validateInventoryOpeningBalanceImportRow(client, { stagingRowId: ROW_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" });

    assert.deepEqual(calls[0]?.args, { p_staging_row_id: ROW_ID, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "tester" });
    assert.equal(row.validationStatus, "valid");
  });

  test("wraps a database error into a typed InventoryLedgerMutationError", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "import_export_staging_row_not_found: no staging row" } });
    await assert.rejects(() => validateInventoryOpeningBalanceImportRow(client, { stagingRowId: ROW_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }), InventoryLedgerMutationError);
  });
});

describe("commitInventoryOpeningBalanceImportJob (CG-AUDIT-2026-09-02 A4)", () => {
  test("calls commit_inventory_opening_balance_import_job with the exact snake_case params, including client IP, defaulting allowPartial to false", async () => {
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
        idempotency_key: "idem-inventory-opening-balance-import-job",
        import_export_schema_code: "inventory_opening_balance_import",
        source_file_id: "e23e4567-e89b-12d3-a456-426614174000",
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
    const job = await commitInventoryOpeningBalanceImportJob(client, { jobId: JOB_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester", clientIp: "203.0.113.5" });

    assert.deepEqual(calls[0]?.args, { p_job_id: JOB_ID, p_allow_partial: false, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "tester", p_client_ip: "203.0.113.5" });
    assert.equal(job.status, "completed");
  });

  test("classifies job_actor_unauthorized, mfa_step_up_required, and ip_not_allowed", async () => {
    const membershipClient = fakeRpcClient({ data: null, error: { message: "job_actor_unauthorized: identity x lacks active membership in tenant y" } }).client;
    await assert.rejects(
      () => commitInventoryOpeningBalanceImportJob(membershipClient, { jobId: JOB_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof InventoryLedgerMutationError);
        assert.equal(err.code, "job_actor_unauthorized");
        return true;
      },
    );
    const mfaClient = fakeRpcClient({ data: null, error: { message: "mfa_step_up_required: OPS:Import requires a current MFA step-up verification" } }).client;
    await assert.rejects(
      () => commitInventoryOpeningBalanceImportJob(mfaClient, { jobId: JOB_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof InventoryLedgerMutationError);
        assert.equal(err.code, "mfa_step_up_required");
        return true;
      },
    );
    const ipClient = fakeRpcClient({ data: null, error: { message: "ip_not_allowed: malformed IP address denied for scope" } }).client;
    await assert.rejects(
      () => commitInventoryOpeningBalanceImportJob(ipClient, { jobId: JOB_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester", clientIp: "bad-ip" }),
      (err: unknown) => {
        assert.ok(err instanceof InventoryLedgerMutationError);
        assert.equal(err.code, "ip_not_allowed");
        return true;
      },
    );
  });

  test("classifies insufficient_authority when the actor lacks is_support_grant_authority even with OPS:Import", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: actor lacks Supreme Admin or tenant_admin grant" } });
    await assert.rejects(
      () => commitInventoryOpeningBalanceImportJob(client, { jobId: JOB_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => err instanceof InventoryLedgerMutationError && err.code === "insufficient_authority",
    );
  });

  test("classifies import_row_no_longer_resolvable when a resolved warehouse/item went inactive between validate and commit", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "import_row_no_longer_resolvable: row x's item is no longer active" } });
    await assert.rejects(
      () => commitInventoryOpeningBalanceImportJob(client, { jobId: JOB_ID, allowPartial: true, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => err instanceof InventoryLedgerMutationError && err.code === "import_row_no_longer_resolvable",
    );
  });
});
