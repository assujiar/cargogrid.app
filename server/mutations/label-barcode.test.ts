import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createLabelTemplate,
  createLabelTemplateVersionDraft,
  publishLabelTemplateVersion,
  setLabelTemplateVersionStatus,
  createLabelPrinter,
  setLabelPrinterStatus,
  previewLabel,
  generateLabel,
  printLabel,
  reprintLabel,
  voidLabel,
  recordLabelPrintOutcome,
  resolveLabel,
  LabelBarcodeMutationError,
  type LabelBarcodeMutationRpcClient,
} from "./label-barcode.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const TEMPLATE_ID = "323e4567-e89b-12d3-a456-426614174000";
const VERSION_ID = "423e4567-e89b-12d3-a456-426614174000";
const PRINTER_ID = "523e4567-e89b-12d3-a456-426614174000";
const INSTANCE_ID = "623e4567-e89b-12d3-a456-426614174000";
const SUBJECT_ID = "723e4567-e89b-12d3-a456-426614174000";
const PRINT_JOB_ID = "823e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "923e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: LabelBarcodeMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as LabelBarcodeMutationRpcClient;
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

const VERSION_ROW = {
  id: VERSION_ID,
  tenant_id: TENANT_ID,
  template_id: TEMPLATE_ID,
  version_number: 1,
  content_template: "ITEM {{sku}}",
  allowed_variables: ["sku"],
  symbology: "code128",
  status: "draft",
  supersedes_version_id: null,
  effective_from: "2026-08-04T00:00:00.000Z",
  record_version: 1,
  created_by: "rep",
  created_at: "2026-08-04T00:00:00.000Z",
  updated_at: "2026-08-04T00:00:00.000Z",
};

const PRINTER_ROW = {
  id: PRINTER_ID,
  tenant_id: TENANT_ID,
  warehouse_id: null,
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
  template_version_id: VERSION_ID,
  subject_type: "item",
  subject_id: SUBJECT_ID,
  owner_account_id: "a23e4567-e89b-12d3-a456-426614174000",
  warehouse_id: null,
  encoded_value: "ITE-0123456789AB-4",
  encoded_value_digest: "abc123",
  variables_snapshot: { sku: "SKU-1" },
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

const PRINT_JOB_ROW = {
  id: PRINT_JOB_ID,
  tenant_id: TENANT_ID,
  label_instance_id: INSTANCE_ID,
  printer_id: PRINTER_ID,
  app_job_id: "b23e4567-e89b-12d3-a456-426614174000",
  copies: 1,
  is_reprint: false,
  reprint_reason: null,
  rendered_payload: "ITEM SKU-1",
  status: "queued",
  outcome_error: null,
  requested_by_auth_user_id: ACTOR_ID,
  requested_by_label: "rep",
  requested_at: "2026-08-04T00:00:00.000Z",
  completed_at: null,
  idempotency_key: "idem-print-1",
  record_version: 1,
  updated_at: "2026-08-04T00:00:00.000Z",
};

describe("createLabelTemplate", () => {
  test("sends the mapped RPC args and parses the response row", async () => {
    const { client, calls } = fakeRpcClient({ data: [TEMPLATE_ROW], error: null });
    const template = await createLabelTemplate(client, {
      tenantId: TENANT_ID,
      code: "TPL-ITEM",
      name: "Item Label",
      subjectType: "item",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "supervisor",
    });
    assert.equal(template.code, "TPL-ITEM");
    assert.equal(calls[0]?.fn, "create_label_template");
  });

  test("classifies label_template_code_conflict", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "label_template_code_conflict: code TPL-ITEM already exists for tenant x with a different name/subject_type" } });
    await assert.rejects(
      () =>
        createLabelTemplate(client, {
          tenantId: TENANT_ID,
          code: "TPL-ITEM",
          name: "A Different Name",
          subjectType: "item",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "supervisor",
        }),
      (err: unknown) => err instanceof LabelBarcodeMutationError && err.code === "label_template_code_conflict",
    );
  });

  test("classifies an unrecognized error prefix as mutation_failed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "some_unexpected_db_error: boom" } });
    await assert.rejects(
      () =>
        createLabelTemplate(client, {
          tenantId: TENANT_ID,
          code: "TPL-ITEM",
          name: "Item Label",
          subjectType: "item",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "supervisor",
        }),
      (err: unknown) => err instanceof LabelBarcodeMutationError && err.code === "mutation_failed",
    );
  });
});

describe("createLabelTemplateVersionDraft", () => {
  test("classifies unwhitelisted_template_variable", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "unwhitelisted_template_variable: warehouse is used in content_template but is not present in allowed_variables" } });
    await assert.rejects(
      () =>
        createLabelTemplateVersionDraft(client, {
          templateId: TEMPLATE_ID,
          contentTemplate: "BIN {{code}} in {{warehouse}}",
          allowedVariables: ["code"],
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => err instanceof LabelBarcodeMutationError && err.code === "unwhitelisted_template_variable",
    );
  });

  test("sends the mapped RPC args and parses the response row", async () => {
    const { client, calls } = fakeRpcClient({ data: [VERSION_ROW], error: null });
    const version = await createLabelTemplateVersionDraft(client, {
      templateId: TEMPLATE_ID,
      contentTemplate: "ITEM {{sku}}",
      allowedVariables: ["sku"],
      symbology: "code128",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(version.status, "draft");
    const args = calls[0]?.args as Record<string, unknown>;
    assert.deepEqual(args.p_allowed_variables, ["sku"]);
  });
});

describe("publishLabelTemplateVersion", () => {
  test("classifies active_template_version_exists", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "active_template_version_exists: template x already has a published version -- supply p_supersedes_version_id to replace it" } });
    await assert.rejects(
      () => publishLabelTemplateVersion(client, { versionId: VERSION_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "supervisor" }),
      (err: unknown) => err instanceof LabelBarcodeMutationError && err.code === "active_template_version_exists",
    );
  });

  test("classifies stale_version", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "stale_version: label template version x expected version 1 but found 2" } });
    await assert.rejects(
      () => publishLabelTemplateVersion(client, { versionId: VERSION_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "supervisor" }),
      (err: unknown) => err instanceof LabelBarcodeMutationError && err.code === "stale_version",
    );
  });
});

describe("setLabelTemplateVersionStatus", () => {
  test("sends p_new_status=archived", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...VERSION_ROW, status: "archived" }], error: null });
    const version = await setLabelTemplateVersionStatus(client, {
      versionId: VERSION_ID,
      newStatus: "archived",
      reason: "end of life",
      expectedVersion: 1,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "supervisor",
    });
    assert.equal(version.status, "archived");
    assert.equal(calls[0]?.args.p_new_status, "archived");
  });
});

describe("createLabelPrinter", () => {
  test("sends the mapped RPC args, defaulting warehouseId to null", async () => {
    const { client, calls } = fakeRpcClient({ data: [PRINTER_ROW], error: null });
    const printer = await createLabelPrinter(client, {
      tenantId: TENANT_ID,
      code: "PRN-1",
      name: "Dock Printer 1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "supervisor",
    });
    assert.equal(printer.code, "PRN-1");
    assert.equal(calls[0]?.args.p_warehouse_id, null);
  });
});

describe("setLabelPrinterStatus", () => {
  test("classifies reason_required", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "reason_required: a non-empty reason is required to deactivate a printer" } });
    await assert.rejects(
      () => setLabelPrinterStatus(client, { printerId: PRINTER_ID, newStatus: "inactive", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => err instanceof LabelBarcodeMutationError && err.code === "reason_required",
    );
  });
});

describe("previewLabel", () => {
  test("returns the rendered text directly (not wrapped in a row)", async () => {
    const { client, calls } = fakeRpcClient({ data: "ITEM SKU-1", error: null });
    const rendered = await previewLabel(client, { templateVersionId: VERSION_ID, variables: { sku: "SKU-1" }, actorAuthUserId: ACTOR_ID });
    assert.equal(rendered, "ITEM SKU-1");
    assert.equal(calls[0]?.fn, "preview_label");
  });

  test("classifies unsafe_variable", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "unsafe_variable: unexpected_field is not a whitelisted variable for this template version" } });
    await assert.rejects(
      () => previewLabel(client, { templateVersionId: VERSION_ID, variables: { unexpected_field: "x" }, actorAuthUserId: ACTOR_ID }),
      (err: unknown) => err instanceof LabelBarcodeMutationError && err.code === "unsafe_variable",
    );
  });
});

describe("generateLabel", () => {
  test("sends the mapped RPC args and parses the response row", async () => {
    const { client, calls } = fakeRpcClient({ data: [INSTANCE_ROW], error: null });
    const instance = await generateLabel(client, {
      tenantId: TENANT_ID,
      templateCode: "TPL-ITEM",
      subjectType: "item",
      subjectId: SUBJECT_ID,
      variables: { sku: "SKU-1" },
      idempotencyKey: "idem-gen-1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(instance.encodedValue, "ITE-0123456789AB-4");
    assert.equal(calls[0]?.fn, "generate_label");
  });

  test("classifies subject_type_mismatch", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "subject_type_mismatch: template TPL-ITEM is scoped to item but bin was requested" } });
    await assert.rejects(
      () =>
        generateLabel(client, {
          tenantId: TENANT_ID,
          templateCode: "TPL-ITEM",
          subjectType: "bin",
          subjectId: SUBJECT_ID,
          idempotencyKey: "idem-gen-2",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => err instanceof LabelBarcodeMutationError && err.code === "subject_type_mismatch",
    );
  });

  test("classifies subject_not_found", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "subject_not_found: no item x for tenant y" } });
    await assert.rejects(
      () =>
        generateLabel(client, {
          tenantId: TENANT_ID,
          templateCode: "TPL-ITEM",
          subjectType: "item",
          subjectId: SUBJECT_ID,
          idempotencyKey: "idem-gen-3",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => err instanceof LabelBarcodeMutationError && err.code === "subject_not_found",
    );
  });

  test("classifies stale_template", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "stale_template: template TPL-BIN has no currently published version" } });
    await assert.rejects(
      () =>
        generateLabel(client, {
          tenantId: TENANT_ID,
          templateCode: "TPL-BIN",
          subjectType: "bin",
          subjectId: SUBJECT_ID,
          idempotencyKey: "idem-gen-4",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => err instanceof LabelBarcodeMutationError && err.code === "stale_template",
    );
  });
});

describe("printLabel", () => {
  test("sends the mapped RPC args and parses the response row", async () => {
    const { client, calls } = fakeRpcClient({ data: [PRINT_JOB_ROW], error: null });
    const job = await printLabel(client, { labelInstanceId: INSTANCE_ID, printerId: PRINTER_ID, idempotencyKey: "idem-print-1", actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(job.status, "queued");
    assert.equal(calls[0]?.args.p_copies, 1);
  });

  test("classifies label_voided", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "label_voided: label instance x is void" } });
    await assert.rejects(
      () => printLabel(client, { labelInstanceId: INSTANCE_ID, printerId: PRINTER_ID, idempotencyKey: "idem-print-2", actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => err instanceof LabelBarcodeMutationError && err.code === "label_voided",
    );
  });

  test("classifies printer_inactive", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "printer_inactive: printer x is not active" } });
    await assert.rejects(
      () => printLabel(client, { labelInstanceId: INSTANCE_ID, printerId: PRINTER_ID, idempotencyKey: "idem-print-3", actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => err instanceof LabelBarcodeMutationError && err.code === "printer_inactive",
    );
  });
});

describe("reprintLabel", () => {
  test("sends p_reason and p_is_reprint-shaped response", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...PRINT_JOB_ROW, is_reprint: true, reprint_reason: "lost in transit" }], error: null });
    const job = await reprintLabel(client, {
      labelInstanceId: INSTANCE_ID,
      printerId: PRINTER_ID,
      reason: "lost in transit",
      idempotencyKey: "idem-reprint-1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "supervisor",
    });
    assert.equal(job.isReprint, true);
    assert.equal(calls[0]?.args.p_reason, "lost in transit");
  });
});

describe("voidLabel", () => {
  test("classifies already_void", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "already_void: label instance x is already void" } });
    await assert.rejects(
      () => voidLabel(client, { labelInstanceId: INSTANCE_ID, reason: "again", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "supervisor" }),
      (err: unknown) => err instanceof LabelBarcodeMutationError && err.code === "already_void",
    );
  });

  test("sends the mapped RPC args and parses the response row", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...INSTANCE_ROW, status: "void", void_reason: "damaged" }], error: null });
    const instance = await voidLabel(client, { labelInstanceId: INSTANCE_ID, reason: "damaged", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "supervisor" });
    assert.equal(instance.status, "void");
    assert.equal(calls[0]?.fn, "void_label");
  });
});

describe("recordLabelPrintOutcome", () => {
  test("classifies label_print_job_already_resolved", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "label_print_job_already_resolved: print job x is already succeeded and cannot be recorded as failed" } });
    await assert.rejects(
      () => recordLabelPrintOutcome(client, { labelPrintJobId: PRINT_JOB_ID, outcomeStatus: "failed", error: "printer jammed", actorAuthUserId: ACTOR_ID, actorLabel: "worker" }),
      (err: unknown) => err instanceof LabelBarcodeMutationError && err.code === "label_print_job_already_resolved",
    );
  });

  test("sends the mapped RPC args and parses the response row", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...PRINT_JOB_ROW, status: "succeeded", completed_at: "2026-08-04T00:05:00.000Z" }], error: null });
    const job = await recordLabelPrintOutcome(client, { labelPrintJobId: PRINT_JOB_ID, outcomeStatus: "succeeded", actorAuthUserId: ACTOR_ID, actorLabel: "worker" });
    assert.equal(job.status, "succeeded");
    assert.equal(calls[0]?.fn, "record_label_print_outcome");
  });
});

describe("resolveLabel", () => {
  test("returns a resolved=true result with a minimal subject projection on success", async () => {
    const { client, calls } = fakeRpcClient({
      data: [
        {
          resolved: true,
          rejection_reason: null,
          label_instance_id: INSTANCE_ID,
          template_version_id: VERSION_ID,
          subject_type: "item",
          subject_id: SUBJECT_ID,
          encoded_value: "ITE-0123456789AB-4",
          status: "active",
          subject_code: "SKU-1",
          subject_name: "Widget",
          subject_status: "active",
        },
      ],
      error: null,
    });
    const result = await resolveLabel(client, { tenantId: TENANT_ID, encodedValue: "ITE-0123456789AB-4", actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(result.resolved, true);
    assert.equal(result.subjectCode, "SKU-1");
    assert.equal(calls[0]?.fn, "resolve_label");
  });

  test("returns a resolved=false result (not a thrown error) for an ordinary rejection like void_code", async () => {
    const { client } = fakeRpcClient({
      data: [
        {
          resolved: false,
          rejection_reason: "void_code",
          label_instance_id: INSTANCE_ID,
          template_version_id: null,
          subject_type: "item",
          subject_id: null,
          encoded_value: "ITE-0123456789AB-4",
          status: "void",
          subject_code: null,
          subject_name: null,
          subject_status: null,
        },
      ],
      error: null,
    });
    const result = await resolveLabel(client, { tenantId: TENANT_ID, encodedValue: "ITE-0123456789AB-4", actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(result.resolved, false);
    assert.equal(result.rejectionReason, "void_code");
  });

  test("still throws LabelBarcodeMutationError for a prior authority-gate failure (no scan attempt to log)", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity x has no active membership in tenant y" } });
    await assert.rejects(
      () => resolveLabel(client, { tenantId: TENANT_ID, encodedValue: "ITE-0123456789AB-4", actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => err instanceof LabelBarcodeMutationError && err.code === "insufficient_authority",
    );
  });
});
