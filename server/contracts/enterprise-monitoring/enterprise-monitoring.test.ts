import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseSloDefinition,
  parseObservabilitySignal,
  parseAlertRoute,
  parseIncident,
  parseIncidentTimelineEvent,
  SetSloDefinitionInputSchema,
  SetAlertRouteInputSchema,
  RaiseObservabilityAlertInputSchema,
} from "./enterprise-monitoring.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ROW_ID = "423e4567-e89b-12d3-a456-426614174000";

describe("parseSloDefinition", () => {
  test("round-trips a tenant-scoped SLO", () => {
    const slo = parseSloDefinition({
      id: ROW_ID, tenant_id: TENANT_ID, service_name: "dispatch-api", metric_type: "latency_p95", target_value: 500,
      evaluation_window_minutes: 60, created_by: "admin1", created_at: "2026-08-22T00:00:00.000Z", updated_at: "2026-08-22T00:00:00.000Z", record_version: 1,
    });
    assert.equal(slo.targetValue, 500);
  });

  test("round-trips a platform-wide (tenant_id null) SLO", () => {
    const slo = parseSloDefinition({
      id: ROW_ID, tenant_id: null, service_name: "shared-job-queue", metric_type: "queue_backlog", target_value: 100,
      evaluation_window_minutes: 15, created_by: "supreme", created_at: "2026-08-22T00:00:00.000Z", updated_at: "2026-08-22T00:00:00.000Z", record_version: 1,
    });
    assert.equal(slo.tenantId, null);
  });

  test("rejects an unrecognized metric_type", () => {
    assert.throws(() =>
      parseSloDefinition({
        id: ROW_ID, tenant_id: TENANT_ID, service_name: "dispatch-api", metric_type: "not-a-real-metric", target_value: 500,
        evaluation_window_minutes: 60, created_by: null, created_at: "2026-08-22T00:00:00.000Z", updated_at: "2026-08-22T00:00:00.000Z", record_version: 1,
      }),
    );
  });
});

describe("parseObservabilitySignal", () => {
  test("round-trips a numeric-only signal", () => {
    const signal = parseObservabilitySignal({
      id: ROW_ID, tenant_id: TENANT_ID, source_type: "job", source_reference: "audit_export:abc123", signal_type: "latency_ms",
      value: 842, occurred_at: "2026-08-22T00:00:00.000Z",
    });
    assert.equal(signal.value, 842);
  });
});

describe("parseAlertRoute / parseIncident / parseIncidentTimelineEvent", () => {
  test("round-trips a real alert route", () => {
    const route = parseAlertRoute({
      id: ROW_ID, tenant_id: TENANT_ID, source_type: "job", signal_type: "backlog_depth", owner_team: "sre-team",
      owner_email: "sre@example.test", dedupe_window_minutes: 30, created_by: "admin1", created_at: "2026-08-22T00:00:00.000Z",
    });
    assert.equal(route.dedupeWindowMinutes, 30);
  });

  test("round-trips an open incident", () => {
    const incident = parseIncident({
      id: ROW_ID, tenant_id: TENANT_ID, source_type: "job", signal_type: "backlog_depth", title: "Dispatch queue backlog rising",
      severity: "high", status: "open", owner_team: "sre-team", opened_at: "2026-08-22T00:00:00.000Z",
      acknowledged_at: null, acknowledged_by: null, resolved_at: null, resolved_by: null, resolution_note: null,
    });
    assert.equal(incident.status, "open");
  });

  test("round-trips a duplicate_signal timeline event", () => {
    const event = parseIncidentTimelineEvent({
      id: ROW_ID, incident_id: ROW_ID, event_type: "duplicate_signal", detail: "depth=140", occurred_at: "2026-08-22T00:00:00.000Z",
    });
    assert.equal(event.eventType, "duplicate_signal");
  });
});

describe("input schemas", () => {
  test("SetSloDefinitionInputSchema rejects an out-of-range evaluationWindowMinutes", () => {
    assert.throws(() =>
      SetSloDefinitionInputSchema.parse({
        tenantId: TENANT_ID, serviceName: "dispatch-api", metricType: "latency_p95", targetValue: 500,
        evaluationWindowMinutes: 20000, actorAuthUserId: ROW_ID, actorLabel: "admin1",
      }),
    );
  });

  test("SetAlertRouteInputSchema rejects an out-of-range dedupeWindowMinutes", () => {
    assert.throws(() =>
      SetAlertRouteInputSchema.parse({
        tenantId: TENANT_ID, sourceType: "job", signalType: "backlog_depth", ownerTeam: null, ownerEmail: null,
        dedupeWindowMinutes: 5000, actorAuthUserId: ROW_ID, actorLabel: "admin1",
      }),
    );
  });

  test("RaiseObservabilityAlertInputSchema rejects an empty title", () => {
    assert.throws(() =>
      RaiseObservabilityAlertInputSchema.parse({
        tenantId: TENANT_ID, sourceType: "job", signalType: "backlog_depth", title: "", severity: "high", detail: null,
      }),
    );
  });
});
