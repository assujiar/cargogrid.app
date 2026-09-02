import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseEventLog,
  GENERIC_JOB_TYPES,
  GenericJobTypeSchema,
  EnqueueJobInputSchema,
  ClaimNextJobInputSchema,
  DispatchEventAsJobInputSchema,
} from "./background-job.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const EVENT_ID = "323e4567-e89b-12d3-a456-426614174000";
const JOB_ID = "423e4567-e89b-12d3-a456-426614174000";
const AUTH_USER_ID = "523e4567-e89b-12d3-a456-426614174000";

describe("GenericJobTypeSchema", () => {
  test("accepts every generic job_type code", () => {
    for (const jobType of GENERIC_JOB_TYPES) {
      assert.equal(GenericJobTypeSchema.parse(jobType), jobType);
    }
  });

  test("rejects import/export -- those keep their own dedicated create_import_export_job entrypoint", () => {
    assert.throws(() => GenericJobTypeSchema.parse("import"));
    assert.throws(() => GenericJobTypeSchema.parse("export"));
  });
});

describe("parseEventLog", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const event = parseEventLog({
      id: EVENT_ID,
      tenant_id: TENANT_ID,
      event_type: "shipment.dispatched",
      resource_type: "shipment",
      resource_id: JOB_ID,
      payload: { carrier: "DHL" },
      dispatch_status: "pending",
      related_job_id: null,
      occurred_at: "2026-07-19T00:00:00.000Z",
      dispatched_at: null,
      error: null,
      created_by: "requester",
    });
    assert.equal(event.eventType, "shipment.dispatched");
    assert.equal(event.dispatchStatus, "pending");
    assert.equal(event.relatedJobId, null);
  });
});

describe("EnqueueJobInputSchema", () => {
  test("defaults payload/priority/idempotencyKey/maxAttempts", () => {
    const parsed = EnqueueJobInputSchema.parse({
      tenantId: TENANT_ID,
      jobType: "notification_batch",
      actorAuthUserId: AUTH_USER_ID,
      actorLabel: "requester",
    });
    assert.deepEqual(parsed.payload, {});
    assert.equal(parsed.priority, 0);
    assert.equal(parsed.idempotencyKey, null);
    assert.equal(parsed.maxAttempts, 3);
  });

  test("rejects import/export -- must use the dedicated import-export entrypoint instead", () => {
    assert.throws(() =>
      EnqueueJobInputSchema.parse({
        tenantId: TENANT_ID,
        jobType: "import",
        actorAuthUserId: AUTH_USER_ID,
        actorLabel: "requester",
      }),
    );
  });
});

describe("ClaimNextJobInputSchema", () => {
  test("defaults leaseDurationSeconds to 300 and requires at least one jobType", () => {
    const parsed = ClaimNextJobInputSchema.parse({ workerId: "worker-1", jobTypes: ["notification_batch"] });
    assert.equal(parsed.leaseDurationSeconds, 300);

    assert.throws(() => ClaimNextJobInputSchema.parse({ workerId: "worker-1", jobTypes: [] }));
  });
});

describe("DispatchEventAsJobInputSchema", () => {
  test("defaults priority/idempotencyKey/maxAttempts and requires a generic job_type", () => {
    const parsed = DispatchEventAsJobInputSchema.parse({ eventId: EVENT_ID, jobType: "webhook_retry", actorLabel: "outbox-drain" });
    assert.equal(parsed.priority, 0);
    assert.equal(parsed.maxAttempts, 3);

    assert.throws(() => DispatchEventAsJobInputSchema.parse({ eventId: EVENT_ID, jobType: "export", actorLabel: "outbox-drain" }));
  });
});

test("ATW-031 (ISS-2026-012): GENERIC_JOB_TYPES matches app.generic_job_types() exactly", () => {
  // The SQL source of truth is app.generic_job_types()
  // (supabase/migrations/20260730410000_harden_job_type_single_source_of_truth.sql, as
  // widened by every subsequent migration that adds a generic job type).
  //
  // This list previously held only the first eight, so `route_load_planning` (ATW-224)
  // and `print_label` (ATW-021) failed contract parsing even though both the app.jobs
  // CHECK constraint and app.enqueue_job accepted them.
  //
  // Batch 2 Tier C fix (20260803030000_harden_intelligence_batch2_tier_c_review_fixes.sql,
  // finding 7): this assertion previously checked GENERIC_JOB_TYPES against a SECOND
  // hand-copied literal in this SAME file -- a same-file tautology structurally incapable
  // of catching drift against the real, live database. It caught neither the 10 prior
  // migrations that widened app.generic_job_types() without updating this array, nor
  // IAE-007's own automation_action_execution. This test still cannot reach a live
  // database on its own (a plain node:test unit test) -- the genuine cross-language drift
  // gate now lives in scripts/db-tests/background-job.sql, which asserts a hardcoded
  // TS-mirror literal against the LIVE app.generic_job_types() output. Keep this literal,
  // that SQL literal, and GENERIC_JOB_TYPES itself all in lockstep by hand; letting any
  // one drift fails either this test or `pnpm run db:test`.
  assert.deepEqual(
    [...GENERIC_JOB_TYPES],
    [
      "report_generation",
      "notification_batch",
      "webhook_retry",
      "document_generation",
      "dashboard_refresh",
      "loyalty_expiration",
      "recurring_billing",
      "integration_sync",
      "route_load_planning",
      "print_label",
      "roster_generation",
      "leave_accrual",
      "leave_carry_forward_expiry",
      "payroll_calculation",
      "training_certificate_expiry",
      "training_certificate_expiry_reminder",
      "ticket_sla_evaluation",
      "kb_article_expiry",
      "ticket_escalation_evaluation",
      "loyalty_expiry_sweep",
      "automation_action_execution",
      "logistics_partner_sync",
      "finance_bank_feed_sync",
      "external_sync",
      "audit_export",
      "retention_archive",
      "incident_escalation_sweep",
      "loyalty_earning_evaluation_sweep",
      "loyalty_tier_recalculation_sweep",
      "loyalty_points_posting_sweep",
      "loyalty_benefit_issuance_sweep",
    ],
  );
});
