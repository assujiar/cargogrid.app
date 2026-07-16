import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  SEVERITIES,
  compareSeverity,
  redact,
  generateCorrelationId,
  buildLogEvent,
  emit,
  log,
  assertBoundedDimension,
  type LogEvent,
} from "./logger.ts";

const FIXED_NOW = () => new Date("2026-07-15T10:00:00.000Z");

describe("buildLogEvent", () => {
  test("produces every required field per docs/standards/OBSERVABILITY_STANDARDS.md §3", () => {
    const event = buildLogEvent(
      { severity: "info", event: "job.started", message: "job started", correlationId: "corr-1", source: "job" },
      FIXED_NOW,
    );
    assert.equal(event.timestamp, "2026-07-15T10:00:00.000Z");
    assert.equal(event.severity, "info");
    assert.equal(event.event, "job.started");
    assert.equal(event.message, "job started");
    assert.equal(event.correlation_id, "corr-1");
    assert.equal(event.source, "job");
    assert.equal(event.tenant_id, undefined);
    assert.equal(event.fields, undefined);
  });

  test("includes tenant_id only when provided", () => {
    const event = buildLogEvent(
      { severity: "warn", event: "auth.denied", message: "denied", correlationId: "corr-2", source: "auth", tenantId: "tenant-abc" },
      FIXED_NOW,
    );
    assert.equal(event.tenant_id, "tenant-abc");
  });

  test("redacts sensitive fields before they ever reach the built event", () => {
    const event = buildLogEvent(
      {
        severity: "error",
        event: "api.request",
        message: "request failed",
        correlationId: "corr-3",
        source: "api",
        fields: { apiKey: "sk_live_super_secret", statusCode: 500 },
      },
      FIXED_NOW,
    );
    assert.notEqual(event.fields?.["apiKey"], "sk_live_super_secret");
    assert.equal(event.fields?.["statusCode"], 500);
  });
});

describe("redact", () => {
  test("replaces a sensitive key's value with a non-reversible fingerprint, never the literal value", () => {
    const redacted = redact({ password: "hunter2" });
    assert.notEqual(redacted["password"], "hunter2");
    assert.match(String(redacted["password"]), /^len\d+:[0-9a-f]+$/);
  });

  test("matches a key that merely contains a sensitive pattern (e.g. supabaseServiceKey)", () => {
    const redacted = redact({ supabaseServiceKey: "abc123" });
    assert.notEqual(redacted["supabaseServiceKey"], "abc123");
  });

  test("leaves a non-sensitive key untouched", () => {
    const redacted = redact({ statusCode: 200, path: "/v1/shipments" });
    assert.equal(redacted["statusCode"], 200);
    assert.equal(redacted["path"], "/v1/shipments");
  });

  test("redacts nested objects recursively", () => {
    const redacted = redact({ user: { name: "Alice", authToken: "raw-token-value" } });
    const nested = redacted["user"] as Record<string, unknown>;
    assert.equal(nested["name"], "Alice");
    assert.notEqual(nested["authToken"], "raw-token-value");
  });

  test("the same sensitive value always redacts to the same fingerprint (deterministic, evidence-readback safe)", () => {
    const a = redact({ token: "same-value" });
    const b = redact({ token: "same-value" });
    assert.equal(a["token"], b["token"]);
  });

  test("redacts Indonesia-specific tax/bank/payroll key names", () => {
    const redacted = redact({ npwp: "01.234.567.8-901.000", bankAccountNumber: "1234567890", payrollAmount: 15000000 });
    assert.notEqual(redacted["npwp"], "01.234.567.8-901.000");
    assert.notEqual(redacted["bankAccountNumber"], "1234567890");
    assert.notEqual(redacted["payrollAmount"], 15000000);
  });
});

describe("compareSeverity", () => {
  test("orders every severity from least to most severe", () => {
    const sorted = [...SEVERITIES].sort((a, b) => compareSeverity(a, b));
    assert.deepEqual(sorted, ["debug", "info", "warn", "error", "critical"]);
  });

  test("returns 0 for equal severities", () => {
    assert.equal(compareSeverity("error", "error"), 0);
  });

  test("critical is greater than debug", () => {
    assert.ok(compareSeverity("critical", "debug") > 0);
  });
});

describe("generateCorrelationId", () => {
  test("produces a valid UUID", () => {
    const id = generateCorrelationId();
    assert.match(id, /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i);
  });

  test("produces a different id on every call", () => {
    assert.notEqual(generateCorrelationId(), generateCorrelationId());
  });
});

describe("assertBoundedDimension", () => {
  test("accepts a value present in the allowlist", () => {
    assert.equal(assertBoundedDimension("api", ["api", "job", "webhook"]), true);
  });

  test("rejects a value absent from the allowlist without throwing", () => {
    assert.equal(assertBoundedDimension("raw-tenant-id-should-never-be-a-label", ["api", "job", "webhook"]), false);
  });
});

describe("emit — safe-degrade rule (docs/standards/OBSERVABILITY_STANDARDS.md §8)", () => {
  const sampleEvent: LogEvent = {
    timestamp: "2026-07-15T10:00:00.000Z",
    severity: "info",
    event: "test.event",
    message: "test",
    correlation_id: "corr-x",
    source: "system",
  };

  test("calls the primary sink under normal operation", () => {
    let received = "";
    emit(sampleEvent, (line) => (received = line));
    assert.match(received, /"event":"test\.event"/);
  });

  test("falls back to the fallback sink when the primary sink throws", () => {
    let fellBackTo = "";
    emit(
      sampleEvent,
      () => {
        throw new Error("primary sink unavailable");
      },
      (line) => (fellBackTo = line),
    );
    assert.match(fellBackTo, /"event":"test\.event"/);
  });

  test("never rethrows even when both primary and fallback sinks throw (real failure injection, not asserted in prose)", () => {
    assert.doesNotThrow(() => {
      emit(
        sampleEvent,
        () => {
          throw new Error("primary down");
        },
        () => {
          throw new Error("fallback down too");
        },
      );
    });
  });
});

describe("log", () => {
  test("builds and emits in one call", () => {
    let received = "";
    log({ severity: "critical", event: "db.connection_lost", message: "lost DB connection", correlationId: "corr-y", source: "db" }, (line) => (received = line));
    const parsed = JSON.parse(received) as LogEvent;
    assert.equal(parsed.severity, "critical");
    assert.equal(parsed.event, "db.connection_lost");
  });
});
