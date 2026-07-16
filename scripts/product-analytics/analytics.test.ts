import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  validateEventName,
  findProhibitedProperties,
  isConsentGranted,
  payloadSizeBytes,
  validateEvent,
  pseudonymizeId,
  buildEvent,
  Deduplicator,
  track,
  type AnalyticsEventInput,
  type AnalyticsEvent,
} from "./analytics.ts";

const FIXED_NOW = () => new Date("2026-07-15T10:00:00.000Z");

function baseInput(overrides: Partial<AnalyticsEventInput> = {}): AnalyticsEventInput {
  return {
    event: "quote.created",
    pseudonymousId: "pseudo-user-1",
    tenantRef: "pseudo-tenant-1",
    context: { source: "web" },
    consentState: "granted",
    ...overrides,
  };
}

describe("validateEventName", () => {
  test("accepts a well-formed domain.action name", () => {
    assert.equal(validateEventName("quote.created"), true);
    assert.equal(validateEventName("shipment.status_changed"), true);
  });

  test("rejects a name with no domain segment", () => {
    assert.equal(validateEventName("created"), false);
  });

  test("rejects an uppercase name", () => {
    assert.equal(validateEventName("Quote.Created"), false);
  });

  test("rejects a name with more than two segments", () => {
    assert.equal(validateEventName("quote.created.extra"), false);
  });
});

describe("findProhibitedProperties", () => {
  test("flags an email-shaped key", () => {
    assert.deepEqual(findProhibitedProperties({ email: "x" }), ["email"]);
  });

  test("flags a finance/security-shaped key", () => {
    const found = findProhibitedProperties({ bankAccountNumber: "1", apiKey: "2" });
    assert.equal(found.length, 2);
  });

  test("does not flag an ordinary, non-sensitive key", () => {
    assert.deepEqual(findProhibitedProperties({ quoteId: "q1", status: "created" }), []);
  });

  test("returns empty for undefined properties", () => {
    assert.deepEqual(findProhibitedProperties(undefined), []);
  });
});

describe("isConsentGranted", () => {
  test("granted and not_required are both allowed", () => {
    assert.equal(isConsentGranted("granted"), true);
    assert.equal(isConsentGranted("not_required"), true);
  });

  test("denied is not allowed", () => {
    assert.equal(isConsentGranted("denied"), false);
  });
});

describe("payloadSizeBytes", () => {
  test("measures the real serialized byte size", () => {
    assert.equal(payloadSizeBytes({ a: "b" }), Buffer.byteLength('{"a":"b"}', "utf8"));
  });

  test("undefined properties measure as an empty object", () => {
    assert.equal(payloadSizeBytes(undefined), Buffer.byteLength("{}", "utf8"));
  });
});

describe("validateEvent", () => {
  test("a well-formed event is valid with no rejection reasons", () => {
    const result = validateEvent(baseInput({ properties: { quoteId: "q1" } }));
    assert.deepEqual(result, { valid: true, reasons: [] });
  });

  test("collects every applicable rejection reason at once, not just the first", () => {
    const result = validateEvent(baseInput({ event: "bad name", properties: { email: "x" }, consentState: "denied" }));
    assert.equal(result.valid, false);
    const kinds = [...result.reasons].sort();
    assert.deepEqual(kinds, ["CONSENT_NOT_GRANTED", "INVALID_EVENT_NAME", "PROHIBITED_PROPERTY"]);
  });

  test("rejects an oversized payload", () => {
    const result = validateEvent(baseInput({ properties: { blob: "x".repeat(9000) } }));
    assert.ok(result.reasons.includes("OVERSIZED_PAYLOAD"));
  });
});

describe("pseudonymizeId", () => {
  test("is deterministic for the same raw id and salt", () => {
    assert.equal(pseudonymizeId("user-123", "dev-salt"), pseudonymizeId("user-123", "dev-salt"));
  });

  test("produces different output for a different salt", () => {
    assert.notEqual(pseudonymizeId("user-123", "dev-salt"), pseudonymizeId("user-123", "other-salt"));
  });

  test("produces different output for a different raw id", () => {
    assert.notEqual(pseudonymizeId("user-123", "dev-salt"), pseudonymizeId("user-456", "dev-salt"));
  });

  test("produces a real 64-character hex SHA-256 digest, not a placeholder", () => {
    const result = pseudonymizeId("user-123", "dev-salt");
    assert.match(result, /^[0-9a-f]{64}$/);
  });

  test("never returns the raw id verbatim", () => {
    assert.notEqual(pseudonymizeId("user-123", "dev-salt"), "user-123");
  });
});

describe("buildEvent", () => {
  test("attaches version, timestamp, and eventId to the input", () => {
    const event = buildEvent(baseInput(), "evt-1", FIXED_NOW);
    assert.equal(event.version, 1);
    assert.equal(event.timestamp, "2026-07-15T10:00:00.000Z");
    assert.equal(event.eventId, "evt-1");
    assert.equal(event.event, "quote.created");
  });
});

describe("Deduplicator", () => {
  test("a fresh id is not a duplicate", () => {
    const dedup = new Deduplicator();
    assert.equal(dedup.isDuplicate("evt-1"), false);
  });

  test("a repeated id is a duplicate", () => {
    const dedup = new Deduplicator();
    dedup.isDuplicate("evt-1");
    assert.equal(dedup.isDuplicate("evt-1"), true);
  });

  test("size tracks the number of unique ids seen", () => {
    const dedup = new Deduplicator();
    dedup.isDuplicate("evt-1");
    dedup.isDuplicate("evt-2");
    dedup.isDuplicate("evt-1");
    assert.equal(dedup.size(), 2);
  });
});

describe("track — safe disablement (Prompt 97 §22)", () => {
  test("returns DISABLED immediately with zero validation/sink work when enabled=false", () => {
    let sinkCalled = false;
    const result = track(baseInput({ event: "!!!invalid!!!" }), "evt-1", {
      enabled: false,
      sink: () => {
        sinkCalled = true;
      },
    });
    assert.deepEqual(result, { delivered: false, reasons: ["DISABLED"] });
    assert.equal(sinkCalled, false);
  });
});

describe("track — validation and delivery", () => {
  test("delivers a valid, consented, enabled event to the sink", () => {
    let received: AnalyticsEvent | undefined;
    const result = track(baseInput(), "evt-1", {
      enabled: true,
      sink: (event) => {
        received = event;
      },
    });
    assert.equal(result.delivered, true);
    assert.equal(received?.event, "quote.created");
  });

  test("rejects an invalid event before reaching the sink", () => {
    let sinkCalled = false;
    const result = track(baseInput({ consentState: "denied" }), "evt-1", {
      enabled: true,
      sink: () => {
        sinkCalled = true;
      },
    });
    assert.equal(result.delivered, false);
    assert.deepEqual(result.reasons, ["CONSENT_NOT_GRANTED"]);
    assert.equal(sinkCalled, false);
  });

  test("rejects a duplicate eventId on the second call", () => {
    const dedup = new Deduplicator();
    const first = track(baseInput(), "evt-1", { enabled: true, deduplicator: dedup });
    const second = track(baseInput(), "evt-1", { enabled: true, deduplicator: dedup });
    assert.equal(first.delivered, true);
    assert.equal(second.delivered, false);
    assert.deepEqual(second.reasons, ["DUPLICATE"]);
  });
});

describe("track — safe-degrade on sink failure (Prompt 97 §23, real failure injection)", () => {
  test("a throwing sink never propagates to the caller", () => {
    assert.doesNotThrow(() => {
      const result = track(baseInput(), "evt-1", {
        enabled: true,
        sink: () => {
          throw new Error("provider outage");
        },
      });
      assert.equal(result.delivered, false);
      assert.deepEqual(result.reasons, ["SINK_ERROR"]);
    });
  });
});
