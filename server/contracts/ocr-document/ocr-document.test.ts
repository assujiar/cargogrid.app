import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseOcrDocumentJob,
  parseOcrDocumentJobDetail,
  parseOcrDocumentJobFullDetail,
  SubmitOcrDocumentJobInputSchema,
  ApplyOcrDocumentJobToTicketInputSchema,
  DismissOcrDocumentJobInputSchema,
} from "./ocr-document.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const FILE_ID = "323e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "423e4567-e89b-12d3-a456-426614174000";
const JOB_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const EMPLOYEE_ID = "723e4567-e89b-12d3-a456-426614174000";
const CATEGORY_ID = "823e4567-e89b-12d3-a456-426614174000";
const QUEUE_ID = "923e4567-e89b-12d3-a456-426614174000";

describe("parseOcrDocumentJob", () => {
  test("round-trips a pending row", () => {
    const job = parseOcrDocumentJob({
      id: JOB_ID, tenant_id: TENANT_ID, file_id: FILE_ID, ai_governed_request_id: null,
      document_type_hint: "finance", status: "pending", reviewer_corrected_fields: null,
      low_confidence_override_reason: null, applied_target_type: null, applied_target_id: null,
      dismiss_reason: null, requested_by: "reviewer", reviewed_by: null,
      created_at: "2026-08-22T00:00:00.000Z", reviewed_at: null, applied_at: null,
    });
    assert.equal(job.status, "pending");
    assert.equal(job.aiGovernedRequestId, null);
  });

  test("rejects an unrecognized status", () => {
    assert.throws(() =>
      parseOcrDocumentJob({
        id: JOB_ID, tenant_id: TENANT_ID, file_id: FILE_ID, ai_governed_request_id: null,
        document_type_hint: "finance", status: "not-a-real-status", reviewer_corrected_fields: null,
        low_confidence_override_reason: null, applied_target_type: null, applied_target_id: null,
        dismiss_reason: null, requested_by: null, reviewed_by: null,
        created_at: "2026-08-22T00:00:00.000Z", reviewed_at: null, applied_at: null,
      }),
    );
  });
});

describe("parseOcrDocumentJobDetail / parseOcrDocumentJobFullDetail", () => {
  test("surfaces the linked governed request's own evidence", () => {
    const detail = parseOcrDocumentJobDetail({
      id: JOB_ID, tenant_id: TENANT_ID, file_id: FILE_ID, ai_governed_request_id: REQUEST_ID,
      document_type_hint: "finance", status: "extracted", applied_target_type: null, applied_target_id: null,
      requested_by: "reviewer", created_at: "2026-08-22T00:00:00.000Z", confidence_label: "high", request_status: "succeeded",
    });
    assert.equal(detail.confidenceLabel, "high");
  });

  test("full detail carries output_payload", () => {
    const full = parseOcrDocumentJobFullDetail({
      id: JOB_ID, tenant_id: TENANT_ID, file_id: FILE_ID, ai_governed_request_id: REQUEST_ID,
      document_type_hint: "finance", status: "extracted", reviewer_corrected_fields: null,
      low_confidence_override_reason: null, applied_target_type: null, applied_target_id: null,
      dismiss_reason: null, requested_by: "reviewer", reviewed_by: null, created_at: "2026-08-22T00:00:00.000Z",
      reviewed_at: null, applied_at: null, confidence_label: "high", request_status: "succeeded",
      output_payload: { extracted_subject: "x" }, model_version: "openai-multimodal",
    });
    assert.deepEqual(full.outputPayload, { extracted_subject: "x" });
  });
});

describe("SubmitOcrDocumentJobInputSchema", () => {
  test("accepts a valid input", () => {
    const parsed = SubmitOcrDocumentJobInputSchema.parse({
      tenantId: TENANT_ID, fileId: FILE_ID, documentTypeHint: "finance", idempotencyKey: "idem-1", actorAuthUserId: ACTOR_ID, actorLabel: "reviewer",
    });
    assert.equal(parsed.documentTypeHint, "finance");
  });

  test("rejects an unrecognized document type hint", () => {
    assert.throws(() =>
      SubmitOcrDocumentJobInputSchema.parse({
        tenantId: TENANT_ID, fileId: FILE_ID, documentTypeHint: "not-a-real-hint", idempotencyKey: "idem-1", actorAuthUserId: ACTOR_ID, actorLabel: "reviewer",
      }),
    );
  });
});

describe("ApplyOcrDocumentJobToTicketInputSchema", () => {
  test("accepts a valid input with a null override reason by default", () => {
    const parsed = ApplyOcrDocumentJobToTicketInputSchema.parse({
      jobId: JOB_ID, tenantId: TENANT_ID, requesterEmployeeId: EMPLOYEE_ID, categoryId: CATEGORY_ID, queueId: QUEUE_ID,
      priority: "normal", subject: "Damaged shipment", body: "Please review.", actorAuthUserId: ACTOR_ID, actorLabel: "reviewer",
    });
    assert.equal(parsed.lowConfidenceOverrideReason, null);
  });

  test("rejects an empty subject", () => {
    assert.throws(() =>
      ApplyOcrDocumentJobToTicketInputSchema.parse({
        jobId: JOB_ID, tenantId: TENANT_ID, requesterEmployeeId: EMPLOYEE_ID, categoryId: CATEGORY_ID, queueId: QUEUE_ID,
        priority: "normal", subject: "", body: "Please review.", actorAuthUserId: ACTOR_ID, actorLabel: "reviewer",
      }),
    );
  });

  test("rejects an unrecognized priority", () => {
    assert.throws(() =>
      ApplyOcrDocumentJobToTicketInputSchema.parse({
        jobId: JOB_ID, tenantId: TENANT_ID, requesterEmployeeId: EMPLOYEE_ID, categoryId: CATEGORY_ID, queueId: QUEUE_ID,
        priority: "critical", subject: "x", body: "y", actorAuthUserId: ACTOR_ID, actorLabel: "reviewer",
      }),
    );
  });
});

describe("DismissOcrDocumentJobInputSchema", () => {
  test("rejects an empty reason", () => {
    assert.throws(() => DismissOcrDocumentJobInputSchema.parse({ jobId: JOB_ID, tenantId: TENANT_ID, reason: "", actorAuthUserId: ACTOR_ID, actorLabel: "reviewer" }));
  });
});
