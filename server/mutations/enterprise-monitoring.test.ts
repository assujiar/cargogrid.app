import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  setSloDefinition,
  recordObservabilitySignal,
  setAlertRoute,
  raiseObservabilityAlert,
  acknowledgeIncident,
  resolveIncident,
  EnterpriseMonitoringMutationError,
  type EnterpriseMonitoringMutationRpcClient,
} from "./enterprise-monitoring.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const ROW_ID = "423e4567-e89b-12d3-a456-426614174000";

const VALID_SLO_ROW = {
  id: ROW_ID, tenant_id: TENANT_ID, service_name: "dispatch-api", metric_type: "latency_p95", target_value: 500,
  evaluation_window_minutes: 60, created_by: "admin1", created_at: "2026-08-22T00:00:00.000Z", updated_at: "2026-08-22T00:00:00.000Z", record_version: 1,
};

const VALID_SIGNAL_ROW = {
  id: ROW_ID, tenant_id: TENANT_ID, source_type: "job", source_reference: "audit_export:abc", signal_type: "latency_ms",
  value: 842, occurred_at: "2026-08-22T00:00:00.000Z",
};

const VALID_ROUTE_ROW = {
  id: ROW_ID, tenant_id: TENANT_ID, source_type: "job", signal_type: "backlog_depth", owner_team: "sre-team",
  owner_email: "sre@example.test", dedupe_window_minutes: 30, created_by: "admin1", created_at: "2026-08-22T00:00:00.000Z",
};

const VALID_INCIDENT_ROW = {
  id: ROW_ID, tenant_id: TENANT_ID, source_type: "job", signal_type: "backlog_depth", title: "Dispatch queue backlog rising",
  severity: "high", status: "open", owner_team: "sre-team", opened_at: "2026-08-22T00:00:00.000Z",
  acknowledged_at: null, acknowledged_by: null, resolved_at: null, resolved_by: null, resolution_note: null,
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: EnterpriseMonitoringMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as EnterpriseMonitoringMutationRpcClient;
  return { client, calls };
}

describe("setSloDefinition", () => {
  test("calls set_slo_definition with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: VALID_SLO_ROW, error: null });
    const slo = await setSloDefinition(client, { tenantId: TENANT_ID, serviceName: "dispatch-api", metricType: "latency_p95", targetValue: 500, evaluationWindowMinutes: 60, actorAuthUserId: ACTOR_ID, actorLabel: "admin1" });
    assert.equal(slo.targetValue, 500);
    assert.equal(calls[0]?.args.p_metric_type, "latency_p95");
  });

  test("classifies insufficient_authority", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity lacks authority" } });
    await assert.rejects(
      setSloDefinition(client, { tenantId: TENANT_ID, serviceName: "dispatch-api", metricType: "latency_p95", targetValue: 500, evaluationWindowMinutes: 60, actorAuthUserId: ACTOR_ID, actorLabel: "viewer1" }),
      (err: unknown) => err instanceof EnterpriseMonitoringMutationError && err.code === "insufficient_authority",
    );
  });
});

describe("recordObservabilitySignal", () => {
  test("returns a persisted, numeric-only signal", async () => {
    const { client } = fakeRpcClient({ data: VALID_SIGNAL_ROW, error: null });
    const signal = await recordObservabilitySignal(client, { tenantId: TENANT_ID, sourceType: "job", sourceReference: "audit_export:abc", signalType: "latency_ms", value: 842 });
    assert.equal(signal.value, 842);
  });

  test("classifies observability_signal_invalid_source_type", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "observability_signal_invalid_source_type: not-a-real-source" } });
    await assert.rejects(
      recordObservabilitySignal(client, { tenantId: TENANT_ID, sourceType: "job", sourceReference: null, signalType: "error", value: 1 }),
      (err: unknown) => err instanceof EnterpriseMonitoringMutationError && err.code === "observability_signal_invalid_source_type",
    );
  });
});

describe("setAlertRoute", () => {
  test("calls set_alert_route with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: VALID_ROUTE_ROW, error: null });
    const route = await setAlertRoute(client, { tenantId: TENANT_ID, sourceType: "job", signalType: "backlog_depth", ownerTeam: "sre-team", ownerEmail: "sre@example.test", dedupeWindowMinutes: 30, actorAuthUserId: ACTOR_ID, actorLabel: "admin1" });
    assert.equal(route.dedupeWindowMinutes, 30);
    assert.equal(calls[0]?.args.p_owner_team, "sre-team");
  });

  test("classifies alert_route_invalid_dedupe_window", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "alert_route_invalid_dedupe_window: 5000 must be between 1 and 1440 minutes" } });
    await assert.rejects(
      setAlertRoute(client, { tenantId: TENANT_ID, sourceType: "job", signalType: "backlog_depth", ownerTeam: null, ownerEmail: null, dedupeWindowMinutes: 30, actorAuthUserId: ACTOR_ID, actorLabel: "admin1" }),
      (err: unknown) => err instanceof EnterpriseMonitoringMutationError && err.code === "alert_route_invalid_dedupe_window",
    );
  });
});

describe("raiseObservabilityAlert", () => {
  test("returns a real incident, deduplicated or fresh", async () => {
    const { client } = fakeRpcClient({ data: VALID_INCIDENT_ROW, error: null });
    const incident = await raiseObservabilityAlert(client, { tenantId: TENANT_ID, sourceType: "job", signalType: "backlog_depth", title: "Dispatch queue backlog rising", severity: "high", detail: "depth=120" });
    assert.equal(incident.status, "open");
  });

  test("classifies incident_invalid_severity", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "incident_invalid_severity: not-a-real-severity" } });
    await assert.rejects(
      raiseObservabilityAlert(client, { tenantId: TENANT_ID, sourceType: "job", signalType: "backlog_depth", title: "bad severity", severity: "high", detail: null }),
      (err: unknown) => err instanceof EnterpriseMonitoringMutationError && err.code === "incident_invalid_severity",
    );
  });
});

describe("acknowledgeIncident / resolveIncident", () => {
  test("acknowledge returns the acknowledged incident", async () => {
    const { client } = fakeRpcClient({ data: { ...VALID_INCIDENT_ROW, status: "acknowledged", acknowledged_by: "admin1" }, error: null });
    const incident = await acknowledgeIncident(client, { incidentId: ROW_ID, actorAuthUserId: ACTOR_ID, actorLabel: "admin1" });
    assert.equal(incident.status, "acknowledged");
  });

  test("resolve classifies incident_not_open on an already-resolved incident", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "incident_not_open: is not an open/acknowledged incident" } });
    await assert.rejects(
      resolveIncident(client, { incidentId: ROW_ID, resolutionNote: "again", actorAuthUserId: ACTOR_ID, actorLabel: "admin1" }),
      (err: unknown) => err instanceof EnterpriseMonitoringMutationError && err.code === "incident_not_open",
    );
  });

  test("resolve returns the resolved incident", async () => {
    const { client } = fakeRpcClient({ data: { ...VALID_INCIDENT_ROW, status: "resolved", resolution_note: "queue drained" }, error: null });
    const incident = await resolveIncident(client, { incidentId: ROW_ID, resolutionNote: "queue drained", actorAuthUserId: ACTOR_ID, actorLabel: "admin1" });
    assert.equal(incident.status, "resolved");
  });
});
