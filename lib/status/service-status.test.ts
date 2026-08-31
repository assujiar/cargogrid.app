import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { interpretServiceStatus, readProbeResponse } from "./service-status.ts";

describe("interpretServiceStatus", () => {
  test("both probes healthy is operational", () => {
    const status = interpretServiceStatus("ok", "ok");
    assert.equal(status.state, "operational");
  });

  test("THE CASE THIS PAGE EXISTS FOR: liveness up, readiness down is degraded, never operational and never a bare 'down'", () => {
    // ISS-2026-261 records that CargoGrid runs on one managed backend vendor with no failover,
    // so "app serving, database unreachable" is the realistic incident. Collapsing it into
    // "down" would tell an operator the opposite of what is happening.
    const status = interpretServiceStatus("ok", "unreachable");
    assert.equal(status.state, "degraded");
    assert.match(status.headline, /database/i);
  });

  test("a 503 that arrived is degraded, not down -- an answer is different from no answer", () => {
    assert.equal(interpretServiceStatus("ok", "degraded").state, "degraded");
  });

  test("liveness unreachable is down, and says why the visitor can still read the page", () => {
    const status = interpretServiceStatus("unreachable", "unreachable");
    assert.equal(status.state, "down");
    // The page being readable during the outage is the whole design claim; it should not look
    // like a contradiction to the person reading it.
    assert.match(status.detail, /served separately/i);
  });

  test("readiness is not consulted when liveness already failed", () => {
    // A readiness 'ok' alongside a liveness failure is incoherent; liveness wins rather than
    // the page reporting a reachable database behind an unreachable application.
    assert.equal(interpretServiceStatus("unreachable", "ok").state, "down");
  });

  test("an unrecognised liveness state is reported as unknown, never as healthy", () => {
    const status = interpretServiceStatus("degraded", "ok");
    assert.equal(status.state, "unknown");
    assert.match(status.detail, /unverified/i);
  });

  test("every state carries a headline and a detail a non-technical visitor can act on", () => {
    for (const [liveness, readiness] of [
      ["ok", "ok"],
      ["ok", "degraded"],
      ["ok", "unreachable"],
      ["degraded", "ok"],
      ["unreachable", "ok"],
    ] as const) {
      const status = interpretServiceStatus(liveness, readiness);
      assert.ok(status.headline.length > 10, `${liveness}/${readiness} needs a real headline`);
      assert.ok(status.detail.length > 20, `${liveness}/${readiness} needs a real detail`);
    }
  });
});

describe("readProbeResponse", () => {
  test("200 with status ok", () => {
    assert.equal(readProbeResponse(200, { status: "ok" }), "ok");
  });

  test("503 with the readiness probe's own degraded body", () => {
    assert.equal(readProbeResponse(503, { status: "degraded", reason: ["database_unreachable"] }), "degraded");
  });

  test("a 200 with no recognisable body is NOT treated as ok -- a proxy's own error page is a 200 surprisingly often", () => {
    assert.equal(readProbeResponse(200, null), "unreachable");
    assert.equal(readProbeResponse(200, "<html>maintenance</html>"), "unreachable");
    assert.equal(readProbeResponse(200, {}), "unreachable");
  });

  test("a 500 with no body is unreachable", () => {
    assert.equal(readProbeResponse(500, null), "unreachable");
  });

  test("a degraded body wins over the HTTP status either way", () => {
    // Defensive: if a future deployment fronts the probe with something that rewrites the
    // status code, the body still carries the truth.
    assert.equal(readProbeResponse(200, { status: "degraded" }), "degraded");
  });
});
