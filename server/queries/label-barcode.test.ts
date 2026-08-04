import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  getLabelTemplate,
  listLabelTemplates,
  listLabelTemplateVersions,
  listLabelPrinters,
  getLabelInstance,
  listLabelInstances,
  listLabelPrintJobs,
  listLabelScanEvents,
  LabelBarcodeQueryError,
  type LabelBarcodeQueryClient,
} from "./label-barcode.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const TEMPLATE_ID = "323e4567-e89b-12d3-a456-426614174000";
const PRINTER_ID = "423e4567-e89b-12d3-a456-426614174000";
const INSTANCE_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const WAREHOUSE_ID = "723e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: LabelBarcodeQueryClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as LabelBarcodeQueryClient;
  return { client, calls };
}

const TEMPLATE_ROW = {
  id: TEMPLATE_ID,
  tenant_id: TENANT_ID,
  code: "TPL-ITEM",
  name: "Item Label",
  subject_type: "item",
  created_by: "supervisor",
  created_at: "2026-08-04T00:00:00.000Z",
};

const PRINTER_ROW = {
  id: PRINTER_ID,
  tenant_id: TENANT_ID,
  warehouse_id: WAREHOUSE_ID,
  code: "PRN-1",
  name: "Dock Printer 1",
  connection_descriptor: {},
  status: "active",
  record_version: 1,
  created_by: "supervisor",
  created_at: "2026-08-04T00:00:00.000Z",
  updated_at: "2026-08-04T00:00:00.000Z",
};

const INSTANCE_ROW = {
  id: INSTANCE_ID,
  tenant_id: TENANT_ID,
  template_version_id: "823e4567-e89b-12d3-a456-426614174000",
  subject_type: "item",
  subject_id: "923e4567-e89b-12d3-a456-426614174000",
  owner_account_id: "a23e4567-e89b-12d3-a456-426614174000",
  warehouse_id: null,
  encoded_value: "ITE-0123456789AB-4",
  encoded_value_digest: "abc123",
  variables_snapshot: {},
  status: "active",
  void_reason: null,
  voided_by_auth_user_id: null,
  voided_by_label: null,
  voided_at: null,
  idempotency_key: "idem-gen-1",
  record_version: 1,
  created_by: "rep",
  created_at: "2026-08-04T00:00:00.000Z",
  updated_at: "2026-08-04T00:00:00.000Z",
};

describe("getLabelTemplate", () => {
  test("sends p_template_id/p_actor_auth_user_id and parses the response row", async () => {
    const { client, calls } = fakeRpcClient({ data: [TEMPLATE_ROW], error: null });
    const template = await getLabelTemplate(client, TEMPLATE_ID, ACTOR_ID);
    assert.equal(template.code, "TPL-ITEM");
    assert.equal(calls[0]?.fn, "get_label_template");
    assert.equal(calls[0]?.args.p_template_id, TEMPLATE_ID);
  });

  test("throws LabelBarcodeQueryError on an RPC error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "label_template_not_found: x" } });
    await assert.rejects(() => getLabelTemplate(client, TEMPLATE_ID, ACTOR_ID), LabelBarcodeQueryError);
  });

  test("throws when the RPC returns no row", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    await assert.rejects(() => getLabelTemplate(client, TEMPLATE_ID, ACTOR_ID), LabelBarcodeQueryError);
  });
});

describe("listLabelTemplates", () => {
  test("defaults p_limit to 50 and p_subject_type_filter to null", async () => {
    const { client, calls } = fakeRpcClient({ data: [TEMPLATE_ROW], error: null });
    const templates = await listLabelTemplates(client, TENANT_ID, ACTOR_ID);
    assert.equal(templates.length, 1);
    assert.equal(calls[0]?.args.p_limit, 50);
    assert.equal(calls[0]?.args.p_subject_type_filter, null);
  });

  test("passes an explicit subjectTypeFilter/limit through", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await listLabelTemplates(client, TENANT_ID, ACTOR_ID, { subjectTypeFilter: "item", limit: 200 });
    assert.equal(calls[0]?.args.p_subject_type_filter, "item");
    assert.equal(calls[0]?.args.p_limit, 200);
  });
});

describe("listLabelTemplateVersions", () => {
  test("sends p_template_id and parses rows", async () => {
    const { client, calls } = fakeRpcClient({
      data: [
        {
          id: "b23e4567-e89b-12d3-a456-426614174000",
          tenant_id: TENANT_ID,
          template_id: TEMPLATE_ID,
          version_number: 1,
          content_template: "ITEM {{sku}}",
          allowed_variables: ["sku"],
          symbology: "code128",
          status: "published",
          supersedes_version_id: null,
          effective_from: "2026-08-04T00:00:00.000Z",
          record_version: 1,
          created_by: "rep",
          created_at: "2026-08-04T00:00:00.000Z",
          updated_at: "2026-08-04T00:00:00.000Z",
        },
      ],
      error: null,
    });
    const versions = await listLabelTemplateVersions(client, TEMPLATE_ID, ACTOR_ID);
    assert.equal(versions[0]?.status, "published");
    assert.equal(calls[0]?.fn, "list_label_template_versions");
  });
});

describe("listLabelPrinters", () => {
  test("passes warehouseId/statusFilter through", async () => {
    const { client, calls } = fakeRpcClient({ data: [PRINTER_ROW], error: null });
    const printers = await listLabelPrinters(client, TENANT_ID, ACTOR_ID, { warehouseId: WAREHOUSE_ID, statusFilter: "active" });
    assert.equal(printers[0]?.code, "PRN-1");
    assert.equal(calls[0]?.args.p_warehouse_id, WAREHOUSE_ID);
    assert.equal(calls[0]?.args.p_status_filter, "active");
  });
});

describe("getLabelInstance", () => {
  test("sends p_label_instance_id and parses the response row", async () => {
    const { client, calls } = fakeRpcClient({ data: [INSTANCE_ROW], error: null });
    const instance = await getLabelInstance(client, INSTANCE_ID, ACTOR_ID);
    assert.equal(instance.status, "active");
    assert.equal(calls[0]?.fn, "get_label_instance");
  });
});

describe("listLabelInstances", () => {
  test("passes subjectType/subjectId/statusFilter through", async () => {
    const { client, calls } = fakeRpcClient({ data: [INSTANCE_ROW], error: null });
    const instances = await listLabelInstances(client, TENANT_ID, ACTOR_ID, { subjectType: "item", statusFilter: "active" });
    assert.equal(instances.length, 1);
    assert.equal(calls[0]?.args.p_subject_type, "item");
    assert.equal(calls[0]?.args.p_status_filter, "active");
  });
});

describe("listLabelPrintJobs", () => {
  test("returns an empty array when data is null", async () => {
    const { client } = fakeRpcClient({ data: null, error: null });
    const jobs = await listLabelPrintJobs(client, TENANT_ID, ACTOR_ID);
    assert.deepEqual(jobs, []);
  });
});

describe("listLabelScanEvents", () => {
  test("sends p_label_instance_id when provided", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await listLabelScanEvents(client, TENANT_ID, ACTOR_ID, { labelInstanceId: INSTANCE_ID });
    assert.equal(calls[0]?.args.p_label_instance_id, INSTANCE_ID);
  });
});
