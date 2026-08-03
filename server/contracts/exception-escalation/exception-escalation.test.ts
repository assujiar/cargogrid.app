import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseExceptionSlaPolicyVersion,
  parseOperationalException,
  parseExceptionDirectoryRow,
  parseExceptionEscalation,
  ReportExceptionInputSchema,
  SetExceptionSlaPolicyTermsInputSchema,
  EscalateExceptionInputSchema,
  SetExceptionSensitiveFieldsInputSchema,
} from "./exception-escalation.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const VERSION_ID = "323e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";
const EXCEPTION_ID = "623e4567-e89b-12d3-a456-426614174000";
const ESCALATION_ID = "723e4567-e89b-12d3-a456-426614174000";

const BASE_EXCEPTION_ROW = {
  id: EXCEPTION_ID,
  tenant_id: TENANT_ID,
  shipment_order_id: SHIPMENT_ID,
  milestone_event_id: null,
  type: "delay",
  severity: "high",
  status: "open",
  owner_user_id: null,
  sla_policy_version_id: VERSION_ID,
  sla_hours: 24,
  due_at: "2026-07-28T08:00:00.000Z",
  escalation_level: 0,
  source: "manual",
  correlation_key: null,
  description: "Carrier reports a delay",
  internal_notes: null,
  damage_loss_details: null,
  claim_amount: null,
  claim_currency: null,
  resolution_evidence: null,
  resolved_at: null,
  reopened_at: null,
  closed_at: null,
  record_version: 1,
  created_by: "rep",
  created_at: "2026-07-27T08:00:00.000Z",
  updated_at: "2026-07-27T08:00:00.000Z",
};

describe("parseExceptionSlaPolicyVersion", () => {
  test("maps a real row, coercing sla_hours to a number", () => {
    const version = parseExceptionSlaPolicyVersion({
      id: VERSION_ID,
      tenant_id: TENANT_ID,
      type: "delay",
      severity: "high",
      status: "published",
      sla_hours: "24.00",
      escalation_schedule: [0, 24, 72],
      supersedes_version_id: null,
      record_version: 1,
      created_by: "rep",
      created_at: "2026-07-27T00:00:00.000Z",
      updated_at: "2026-07-27T00:00:00.000Z",
    });
    assert.equal(version.slaHours, 24);
    assert.deepEqual(version.escalationSchedule, [0, 24, 72]);
  });

  test("leaves slaHours null before terms are set", () => {
    const version = parseExceptionSlaPolicyVersion({
      id: VERSION_ID,
      tenant_id: TENANT_ID,
      type: "delay",
      severity: "high",
      status: "draft",
      sla_hours: null,
      escalation_schedule: [],
      supersedes_version_id: null,
      record_version: 1,
      created_by: "rep",
      created_at: "2026-07-27T00:00:00.000Z",
      updated_at: "2026-07-27T00:00:00.000Z",
    });
    assert.equal(version.slaHours, null);
  });
});

describe("parseOperationalException", () => {
  test("maps a real row with a pinned SLA snapshot", () => {
    const exception = parseOperationalException(BASE_EXCEPTION_ROW);
    assert.equal(exception.slaHours, 24);
    assert.equal(exception.dueAt, "2026-07-28T08:00:00.000Z");
    assert.equal(exception.internalNotes, null);
  });

  test("leaves slaHours/dueAt null when no policy was pinned", () => {
    const exception = parseOperationalException({ ...BASE_EXCEPTION_ROW, sla_policy_version_id: null, sla_hours: null, due_at: null });
    assert.equal(exception.slaHours, null);
    assert.equal(exception.dueAt, null);
  });

  test("defaults telemetry provenance to null for a manual exception", () => {
    const exception = parseOperationalException(BASE_EXCEPTION_ROW);
    assert.equal(exception.sourceClass, null);
    assert.equal(exception.sourceConfidenceScore, null);
    assert.equal(exception.sourceSignalId, null);
  });

  test("maps real telemetry provenance (ATW-228 widening)", () => {
    const exception = parseOperationalException({
      ...BASE_EXCEPTION_ROW,
      source: "system",
      source_class: "third_party_platform",
      source_confidence_score: "0.4",
      source_freshness_status: "stale",
      source_signal_id: "923e4567-e89b-12d3-a456-426614174000",
    });
    assert.equal(exception.sourceClass, "third_party_platform");
    assert.equal(exception.sourceConfidenceScore, 0.4);
    assert.equal(exception.sourceFreshnessStatus, "stale");
  });
});

describe("parseExceptionDirectoryRow", () => {
  test("maps a masked row", () => {
    const row = parseExceptionDirectoryRow({ ...BASE_EXCEPTION_ROW, sensitive_masked: true });
    assert.equal(row.sensitiveMasked, true);
    assert.equal(row.claimAmount, null);
  });

  test("maps an unmasked row with real sensitive values", () => {
    const row = parseExceptionDirectoryRow({
      ...BASE_EXCEPTION_ROW,
      internal_notes: "GPS malfunctioned",
      claim_amount: "750.50",
      claim_currency: "USD",
      sensitive_masked: false,
    });
    assert.equal(row.sensitiveMasked, false);
    assert.equal(row.claimAmount, 750.5);
    assert.equal(row.internalNotes, "GPS malfunctioned");
  });
});

describe("parseExceptionEscalation", () => {
  test("maps a real row", () => {
    const escalation = parseExceptionEscalation({
      id: ESCALATION_ID,
      tenant_id: TENANT_ID,
      exception_id: EXCEPTION_ID,
      escalation_level: 1,
      reason: "no response from owner within SLA",
      actor_auth_user_id: ACTOR_ID,
      actor_label: "rep",
      escalated_at: "2026-07-27T09:00:00.000Z",
    });
    assert.equal(escalation.escalationLevel, 1);
  });
});

describe("ReportExceptionInputSchema", () => {
  test("rejects an unsupported source", () => {
    assert.throws(() =>
      ReportExceptionInputSchema.parse({
        shipmentOrderId: SHIPMENT_ID,
        type: "delay",
        severity: "high",
        description: "test",
        source: "carrier_pigeon",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });

  test("defaults milestoneEventId/correlationKey to null", () => {
    const parsed = ReportExceptionInputSchema.parse({
      shipmentOrderId: SHIPMENT_ID,
      type: "delay",
      severity: "high",
      description: "test",
      source: "manual",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(parsed.milestoneEventId, null);
    assert.equal(parsed.correlationKey, null);
  });
});

describe("SetExceptionSlaPolicyTermsInputSchema", () => {
  test("rejects a non-positive slaHours", () => {
    assert.throws(() =>
      SetExceptionSlaPolicyTermsInputSchema.parse({ versionId: VERSION_ID, slaHours: 0, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
    );
  });
});

describe("EscalateExceptionInputSchema", () => {
  test("requires a non-empty reason", () => {
    assert.throws(() => EscalateExceptionInputSchema.parse({ exceptionId: EXCEPTION_ID, reason: "", actorAuthUserId: ACTOR_ID, actorLabel: "rep" }));
  });
});

describe("SetExceptionSensitiveFieldsInputSchema", () => {
  test("rejects a negative claimAmount", () => {
    assert.throws(() =>
      SetExceptionSensitiveFieldsInputSchema.parse({ exceptionId: EXCEPTION_ID, claimAmount: -5, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
    );
  });

  test("defaults everything else to null", () => {
    const parsed = SetExceptionSensitiveFieldsInputSchema.parse({ exceptionId: EXCEPTION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(parsed.internalNotes, null);
    assert.equal(parsed.damageLossDetails, null);
    assert.equal(parsed.claimAmount, null);
    assert.equal(parsed.claimCurrency, null);
  });
});
