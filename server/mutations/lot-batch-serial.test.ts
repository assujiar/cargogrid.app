import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createItemControlPolicyVersionDraft,
  publishItemControlPolicyVersion,
  registerLotIdentity,
  registerSerialIdentity,
  setLotIdentityStatus,
  setSerialIdentityStatus,
  LotBatchSerialMutationError,
  type LotBatchSerialMutationRpcClient,
} from "./lot-batch-serial.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ITEM_ID = "723e4567-e89b-12d3-a456-426614174000";
const OWNER_ID = "823e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "923e4567-e89b-12d3-a456-426614174000";
const SUPERVISOR_ID = "923e4567-e89b-12d3-a456-426614174001";
const POLICY_ID = "a23e4567-e89b-12d3-a456-426614174000";
const LOT_ID = "b23e4567-e89b-12d3-a456-426614174000";
const SERIAL_ID = "c23e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: LotBatchSerialMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as LotBatchSerialMutationRpcClient;
  return { client, calls };
}

const POLICY_ROW = {
  id: POLICY_ID,
  tenant_id: TENANT_ID,
  item_master_id: ITEM_ID,
  owner_account_id: OWNER_ID,
  allocation_rule: "fifo",
  hold_on_unknown_lot: true,
  near_expiry_warning_days: null,
  status: "draft",
  supersedes_version_id: null,
  effective_from: "2026-08-03T00:00:00.000Z",
  record_version: 1,
  created_at: "2026-08-03T00:00:00.000Z",
  updated_at: "2026-08-03T00:00:00.000Z",
};

const LOT_ROW = {
  id: LOT_ID,
  tenant_id: TENANT_ID,
  owner_account_id: OWNER_ID,
  item_master_id: ITEM_ID,
  lot_number: "LOT-001",
  manufacture_date: null,
  expiry_date: null,
  status: "held",
  hold_reason: "hold_on_unknown_lot_policy_default",
  parent_lot_id: null,
  source_type: "receipt",
  source_id: null,
  record_version: 1,
  created_at: "2026-08-03T00:00:00.000Z",
  updated_at: "2026-08-03T00:00:00.000Z",
};

const SERIAL_ROW = {
  id: SERIAL_ID,
  tenant_id: TENANT_ID,
  owner_account_id: OWNER_ID,
  item_master_id: ITEM_ID,
  serial_number: "SN-001",
  lot_number: null,
  manufacture_date: null,
  expiry_date: null,
  status: "active",
  hold_reason: null,
  source_type: "receipt",
  source_id: null,
  idempotency_key: "idem-serial-1",
  record_version: 1,
  created_at: "2026-08-03T00:00:00.000Z",
  updated_at: "2026-08-03T00:00:00.000Z",
};

describe("createItemControlPolicyVersionDraft", () => {
  test("sends the mapped RPC args and parses the response row", async () => {
    const { client, calls } = fakeRpcClient({ data: [POLICY_ROW], error: null });
    const policy = await createItemControlPolicyVersionDraft(client, {
      itemMasterId: ITEM_ID,
      allocationRule: "fifo",
      holdOnUnknownLot: true,
      nearExpiryWarningDays: null,
      effectiveFrom: null,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(policy.status, "draft");
    assert.equal(calls[0]?.fn, "create_item_control_policy_version_draft");
    assert.equal(calls[0]?.args.p_allocation_rule, "fifo");
  });

  test("classifies invalid_allocation_rule (fefo on a non-expiry-controlled item)", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "invalid_allocation_rule: fefo requires item x to be expiry-controlled" } });
    await assert.rejects(
      () =>
        createItemControlPolicyVersionDraft(client, {
          itemMasterId: ITEM_ID,
          allocationRule: "fefo",
          holdOnUnknownLot: true,
          nearExpiryWarningDays: null,
          effectiveFrom: null,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => err instanceof LotBatchSerialMutationError && err.code === "invalid_allocation_rule",
    );
  });

  test("classifies an unrecognized error prefix as mutation_failed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "some_unexpected_db_error: boom" } });
    await assert.rejects(
      () =>
        createItemControlPolicyVersionDraft(client, {
          itemMasterId: ITEM_ID,
          allocationRule: null,
          holdOnUnknownLot: null,
          nearExpiryWarningDays: null,
          effectiveFrom: null,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => err instanceof LotBatchSerialMutationError && err.code === "mutation_failed",
    );
  });
});

describe("publishItemControlPolicyVersion", () => {
  test("classifies active_policy_exists", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "active_policy_exists: item x already has a published control policy -- supply p_supersedes_version_id to replace it" } });
    await assert.rejects(
      () =>
        publishItemControlPolicyVersion(client, {
          policyVersionId: POLICY_ID,
          expectedVersion: 1,
          supersedesVersionId: null,
          actorAuthUserId: SUPERVISOR_ID,
          actorLabel: "supervisor",
        }),
      (err: unknown) => err instanceof LotBatchSerialMutationError && err.code === "active_policy_exists",
    );
  });

  test("sends the mapped RPC args and parses the response row", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...POLICY_ROW, status: "published" }], error: null });
    const policy = await publishItemControlPolicyVersion(client, {
      policyVersionId: POLICY_ID,
      expectedVersion: 1,
      supersedesVersionId: null,
      actorAuthUserId: SUPERVISOR_ID,
      actorLabel: "supervisor",
    });
    assert.equal(policy.status, "published");
    assert.equal(calls[0]?.fn, "publish_item_control_policy_version");
  });
});

describe("registerLotIdentity", () => {
  test("classifies item_not_lot_controlled", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "item_not_lot_controlled: item x is not lot-controlled -- a lot identity is not relevant" } });
    await assert.rejects(
      () =>
        registerLotIdentity(client, {
          itemMasterId: ITEM_ID,
          lotNumber: "LOT-001",
          manufactureDate: null,
          expiryDate: null,
          sourceType: null,
          sourceId: null,
          parentLotId: null,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => err instanceof LotBatchSerialMutationError && err.code === "item_not_lot_controlled",
    );
  });

  test("sends the mapped RPC args and parses the response row", async () => {
    const { client, calls } = fakeRpcClient({ data: [LOT_ROW], error: null });
    const lot = await registerLotIdentity(client, {
      itemMasterId: ITEM_ID,
      lotNumber: "LOT-001",
      manufactureDate: null,
      expiryDate: null,
      sourceType: "receipt",
      sourceId: null,
      parentLotId: null,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(lot.lotNumber, "LOT-001");
    assert.equal(calls[0]?.fn, "register_lot_identity");
  });
});

describe("registerSerialIdentity", () => {
  test("classifies duplicate_serial", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "duplicate_serial: serial x is already registered for item y (owner z) in tenant w" } });
    await assert.rejects(
      () =>
        registerSerialIdentity(client, {
          itemMasterId: ITEM_ID,
          serialNumber: "SN-001",
          lotNumber: null,
          manufactureDate: null,
          expiryDate: null,
          sourceType: null,
          sourceId: null,
          idempotencyKey: "idem-serial-2",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => err instanceof LotBatchSerialMutationError && err.code === "duplicate_serial",
    );
  });

  test("sends the mapped RPC args and parses the response row", async () => {
    const { client, calls } = fakeRpcClient({ data: [SERIAL_ROW], error: null });
    const serial = await registerSerialIdentity(client, {
      itemMasterId: ITEM_ID,
      serialNumber: "SN-001",
      lotNumber: null,
      manufactureDate: null,
      expiryDate: null,
      sourceType: "receipt",
      sourceId: null,
      idempotencyKey: "idem-serial-1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(serial.serialNumber, "SN-001");
    assert.equal(calls[0]?.fn, "register_serial_identity");
  });
});

describe("setLotIdentityStatus / setSerialIdentityStatus", () => {
  test("setLotIdentityStatus classifies invalid_transition (consumed is terminal)", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "invalid_transition: lot identity x is consumed -- a terminal status, no further transition is permitted" } });
    await assert.rejects(
      () =>
        setLotIdentityStatus(client, {
          lotIdentityId: LOT_ID,
          newStatus: "active",
          reason: null,
          expectedVersion: 3,
          actorAuthUserId: SUPERVISOR_ID,
          actorLabel: "supervisor",
        }),
      (err: unknown) => err instanceof LotBatchSerialMutationError && err.code === "invalid_transition",
    );
  });

  test("setSerialIdentityStatus sends the mapped RPC args and parses the response row", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...SERIAL_ROW, status: "held", hold_reason: "quality hold" }], error: null });
    const serial = await setSerialIdentityStatus(client, {
      serialIdentityId: SERIAL_ID,
      newStatus: "held",
      reason: "quality hold",
      expectedVersion: 1,
      actorAuthUserId: SUPERVISOR_ID,
      actorLabel: "supervisor",
    });
    assert.equal(serial.status, "held");
    assert.equal(calls[0]?.fn, "set_serial_identity_status");
  });
});
