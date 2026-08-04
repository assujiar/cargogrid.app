import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseLabelTemplate,
  parseLabelTemplateVersion,
  parseLabelPrinter,
  parseLabelInstance,
  parseLabelPrintJob,
  parseLabelScanEvent,
  parseLabelResolveResult,
  LabelTemplateSchema,
  CreateLabelTemplateInputSchema,
  CreateLabelTemplateVersionDraftInputSchema,
  GenerateLabelInputSchema,
  PrintLabelInputSchema,
  ReprintLabelInputSchema,
  VoidLabelInputSchema,
  RecordLabelPrintOutcomeInputSchema,
} from "./label-barcode.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const TEMPLATE_ID = "323e4567-e89b-12d3-a456-426614174000";
const VERSION_ID = "423e4567-e89b-12d3-a456-426614174000";
const PRINTER_ID = "523e4567-e89b-12d3-a456-426614174000";
const INSTANCE_ID = "623e4567-e89b-12d3-a456-426614174000";
const OWNER_ID = "723e4567-e89b-12d3-a456-426614174000";
const WAREHOUSE_ID = "823e4567-e89b-12d3-a456-426614174000";
const SUBJECT_ID = "923e4567-e89b-12d3-a456-426614174000";
const PRINT_JOB_ID = "a23e4567-e89b-12d3-a456-426614174000";
const JOB_ID = "b23e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "c23e4567-e89b-12d3-a456-426614174000";
const AUTH_USER_ID = "d23e4567-e89b-12d3-a456-426614174000";

describe("parseLabelTemplate", () => {
  test("maps a bin-subject template row", () => {
    const template = parseLabelTemplate({
      id: TEMPLATE_ID,
      tenant_id: TENANT_ID,
      code: "TPL-BIN",
      name: "Bin Label",
      subject_type: "bin",
      created_by: "supervisor",
      created_at: "2026-08-04T00:00:00.000Z",
    });
    assert.equal(template.subjectType, "bin");
  });

  test("rejects an invalid subject_type via the schema", () => {
    assert.throws(() =>
      LabelTemplateSchema.parse({
        id: TEMPLATE_ID,
        tenantId: TENANT_ID,
        code: "TPL-BAD",
        name: "Bad",
        subjectType: "spaceship",
        createdBy: null,
        createdAt: "2026-08-04T00:00:00.000Z",
      }),
    );
  });
});

describe("parseLabelTemplateVersion", () => {
  test("maps a published version row, coercing allowed_variables/record_version", () => {
    const version = parseLabelTemplateVersion({
      id: VERSION_ID,
      tenant_id: TENANT_ID,
      template_id: TEMPLATE_ID,
      version_number: 2,
      content_template: "ITEM {{sku}}",
      allowed_variables: ["sku"],
      symbology: "qr",
      status: "published",
      supersedes_version_id: null,
      effective_from: "2026-08-04T00:00:00.000Z",
      record_version: 1,
      created_by: "rep",
      created_at: "2026-08-04T00:00:00.000Z",
      updated_at: "2026-08-04T00:00:00.000Z",
    });
    assert.equal(version.versionNumber, 2);
    assert.deepEqual(version.allowedVariables, ["sku"]);
    assert.equal(version.symbology, "qr");
  });
});

describe("parseLabelPrinter", () => {
  test("maps a printer row with a null warehouse (virtual/office printer)", () => {
    const printer = parseLabelPrinter({
      id: PRINTER_ID,
      tenant_id: TENANT_ID,
      warehouse_id: null,
      code: "PRN-VIRTUAL",
      name: "Virtual Office Printer",
      connection_descriptor: {},
      status: "active",
      record_version: 1,
      created_by: "supervisor",
      created_at: "2026-08-04T00:00:00.000Z",
      updated_at: "2026-08-04T00:00:00.000Z",
    });
    assert.equal(printer.warehouseId, null);
    assert.equal(printer.status, "active");
  });
});

describe("parseLabelInstance", () => {
  test("maps an active item-subject instance row (owner_account_id set, warehouse_id null)", () => {
    const instance = parseLabelInstance({
      id: INSTANCE_ID,
      tenant_id: TENANT_ID,
      template_version_id: VERSION_ID,
      subject_type: "item",
      subject_id: SUBJECT_ID,
      owner_account_id: OWNER_ID,
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
    });
    assert.equal(instance.ownerAccountId, OWNER_ID);
    assert.equal(instance.warehouseId, null);
    assert.equal(instance.status, "active");
  });

  test("maps a void instance row", () => {
    const instance = parseLabelInstance({
      id: INSTANCE_ID,
      tenant_id: TENANT_ID,
      template_version_id: VERSION_ID,
      subject_type: "bin",
      subject_id: SUBJECT_ID,
      owner_account_id: null,
      warehouse_id: WAREHOUSE_ID,
      encoded_value: "BIN-0123456789AB-4",
      encoded_value_digest: "def456",
      variables_snapshot: {},
      status: "void",
      void_reason: "damaged label",
      voided_by_auth_user_id: AUTH_USER_ID,
      voided_by_label: "supervisor",
      voided_at: "2026-08-04T01:00:00.000Z",
      idempotency_key: "idem-gen-2",
      record_version: 2,
      created_by: "rep",
      created_at: "2026-08-04T00:00:00.000Z",
      updated_at: "2026-08-04T01:00:00.000Z",
    });
    assert.equal(instance.status, "void");
    assert.equal(instance.voidReason, "damaged label");
  });
});

describe("parseLabelPrintJob", () => {
  test("maps a queued print job row with a null app_job_id (mid-generate_label transaction shape)", () => {
    const job = parseLabelPrintJob({
      id: PRINT_JOB_ID,
      tenant_id: TENANT_ID,
      label_instance_id: INSTANCE_ID,
      printer_id: PRINTER_ID,
      app_job_id: null,
      copies: 2,
      is_reprint: false,
      reprint_reason: null,
      rendered_payload: "ITEM SKU-1",
      status: "queued",
      outcome_error: null,
      requested_by_auth_user_id: AUTH_USER_ID,
      requested_by_label: "rep",
      requested_at: "2026-08-04T00:00:00.000Z",
      completed_at: null,
      idempotency_key: "idem-print-1",
      record_version: 1,
      updated_at: "2026-08-04T00:00:00.000Z",
    });
    assert.equal(job.appJobId, null);
    assert.equal(job.copies, 2);
  });

  test("maps a reprint job row", () => {
    const job = parseLabelPrintJob({
      id: PRINT_JOB_ID,
      tenant_id: TENANT_ID,
      label_instance_id: INSTANCE_ID,
      printer_id: PRINTER_ID,
      app_job_id: JOB_ID,
      copies: 1,
      is_reprint: true,
      reprint_reason: "lost in transit",
      rendered_payload: "ITEM SKU-1",
      status: "succeeded",
      outcome_error: null,
      requested_by_auth_user_id: AUTH_USER_ID,
      requested_by_label: "supervisor",
      requested_at: "2026-08-04T00:00:00.000Z",
      completed_at: "2026-08-04T00:05:00.000Z",
      idempotency_key: "idem-reprint-1",
      record_version: 2,
      updated_at: "2026-08-04T00:05:00.000Z",
    });
    assert.equal(job.isReprint, true);
    assert.equal(job.reprintReason, "lost in transit");
    assert.equal(job.status, "succeeded");
  });
});

describe("parseLabelScanEvent", () => {
  test("maps a resolved scan event", () => {
    const event = parseLabelScanEvent({
      id: PRINT_JOB_ID,
      tenant_id: TENANT_ID,
      encoded_value: "ITE-0123456789AB-4",
      label_instance_id: INSTANCE_ID,
      subject_type: "item",
      resolved: true,
      rejection_reason: null,
      scanned_by_auth_user_id: AUTH_USER_ID,
      scanned_by_label: "rep",
      scanned_at: "2026-08-04T00:00:00.000Z",
    });
    assert.equal(event.resolved, true);
    assert.equal(event.rejectionReason, null);
  });

  test("maps a rejected scan event with no real label_instance_id (unknown_code)", () => {
    const event = parseLabelScanEvent({
      id: PRINT_JOB_ID,
      tenant_id: TENANT_ID,
      encoded_value: "BIN-AAAAAAAAAAAA-0",
      label_instance_id: null,
      subject_type: null,
      resolved: false,
      rejection_reason: "unknown_code",
      scanned_by_auth_user_id: AUTH_USER_ID,
      scanned_by_label: "rep",
      scanned_at: "2026-08-04T00:00:00.000Z",
    });
    assert.equal(event.labelInstanceId, null);
    assert.equal(event.rejectionReason, "unknown_code");
  });
});

describe("parseLabelResolveResult", () => {
  test("maps a successful resolve result with a minimal subject projection", () => {
    const result = parseLabelResolveResult({
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
    });
    assert.equal(result.resolved, true);
    assert.equal(result.subjectCode, "SKU-1");
  });

  test("maps a rejected resolve result (void_code) with the instance still populated", () => {
    const result = parseLabelResolveResult({
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
    });
    assert.equal(result.resolved, false);
    assert.equal(result.rejectionReason, "void_code");
    assert.equal(result.labelInstanceId, INSTANCE_ID);
  });

  test("maps a rejected resolve result (invalid_checksum) with no real label reference at all", () => {
    const result = parseLabelResolveResult({
      resolved: false,
      rejection_reason: "invalid_checksum",
      label_instance_id: null,
      template_version_id: null,
      subject_type: null,
      subject_id: null,
      encoded_value: null,
      status: null,
      subject_code: null,
      subject_name: null,
      subject_status: null,
    });
    assert.equal(result.resolved, false);
    assert.equal(result.labelInstanceId, null);
  });
});

describe("CreateLabelTemplateInputSchema", () => {
  test("requires a non-empty code and name", () => {
    assert.throws(() =>
      CreateLabelTemplateInputSchema.parse({
        tenantId: TENANT_ID,
        code: "",
        name: "Bin Label",
        subjectType: "bin",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "supervisor",
      }),
    );
  });

  test("accepts a well-formed input", () => {
    const parsed = CreateLabelTemplateInputSchema.parse({
      tenantId: TENANT_ID,
      code: "TPL-BIN",
      name: "Bin Label",
      subjectType: "bin",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "supervisor",
    });
    assert.equal(parsed.subjectType, "bin");
  });
});

describe("CreateLabelTemplateVersionDraftInputSchema", () => {
  test("defaults allowedVariables to an empty array", () => {
    const parsed = CreateLabelTemplateVersionDraftInputSchema.parse({
      templateId: TEMPLATE_ID,
      contentTemplate: "STATIC TEXT ONLY",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.deepEqual(parsed.allowedVariables, []);
  });

  test("rejects an empty contentTemplate", () => {
    assert.throws(() =>
      CreateLabelTemplateVersionDraftInputSchema.parse({
        templateId: TEMPLATE_ID,
        contentTemplate: "",
        allowedVariables: [],
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });
});

describe("GenerateLabelInputSchema", () => {
  test("requires a non-empty idempotencyKey", () => {
    assert.throws(() =>
      GenerateLabelInputSchema.parse({
        tenantId: TENANT_ID,
        templateCode: "TPL-ITEM",
        subjectType: "item",
        subjectId: SUBJECT_ID,
        idempotencyKey: "",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });
});

describe("PrintLabelInputSchema / ReprintLabelInputSchema", () => {
  test("PrintLabelInputSchema defaults copies to 1", () => {
    const parsed = PrintLabelInputSchema.parse({
      labelInstanceId: INSTANCE_ID,
      printerId: PRINTER_ID,
      idempotencyKey: "idem-print-1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(parsed.copies, 1);
  });

  test("ReprintLabelInputSchema requires a non-empty reason", () => {
    assert.throws(() =>
      ReprintLabelInputSchema.parse({
        labelInstanceId: INSTANCE_ID,
        printerId: PRINTER_ID,
        reason: "",
        idempotencyKey: "idem-reprint-1",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "supervisor",
      }),
    );
  });
});

describe("VoidLabelInputSchema", () => {
  test("requires a non-empty reason", () => {
    assert.throws(() =>
      VoidLabelInputSchema.parse({
        labelInstanceId: INSTANCE_ID,
        reason: "",
        expectedVersion: 1,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "supervisor",
      }),
    );
  });
});

describe("RecordLabelPrintOutcomeInputSchema", () => {
  test("rejects an unrecognized outcomeStatus", () => {
    assert.throws(() =>
      RecordLabelPrintOutcomeInputSchema.parse({
        labelPrintJobId: PRINT_JOB_ID,
        outcomeStatus: "bogus",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "worker",
      }),
    );
  });

  test("requires a non-empty actorLabel (a worker-side callback still needs a real label)", () => {
    assert.throws(() =>
      RecordLabelPrintOutcomeInputSchema.parse({
        labelPrintJobId: PRINT_JOB_ID,
        outcomeStatus: "succeeded",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "",
      }),
    );
  });
});
