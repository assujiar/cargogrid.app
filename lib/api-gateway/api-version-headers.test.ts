import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { apiVersionHeaders } from "./authenticate.server.ts";

/**
 * `ISS-2026-207` closed a gap where `app.api_versions` was audited, admin-visible, db-tested and
 * completely inert — marking `v1` sunset changed nothing about a real request. These assertions
 * cover the half that turns a registry decision into something a client can act on.
 */
describe("apiVersionHeaders", () => {
  test("an active version carries no deprecation signal at all", () => {
    assert.deepEqual(apiVersionHeaders({ decision: "ok", status: "active", sunsetAt: null }), {});
  });

  test("a deprecated version signals deprecation, and the sunset date when one is announced", () => {
    const headers = apiVersionHeaders({ decision: "deprecated", status: "sunset", sunsetAt: "2027-01-01T00:00:00.000Z" });
    assert.equal(headers.deprecation, "true");
    // RFC 8594's Sunset is an HTTP-date, not an ISO-8601 string — a client parsing per the RFC
    // would reject the latter.
    assert.equal(headers.sunset, "Fri, 01 Jan 2027 00:00:00 GMT");
  });

  test("a deprecated version with no announced date still signals deprecation", () => {
    const headers = apiVersionHeaders({ decision: "deprecated", status: "deprecated", sunsetAt: null });
    assert.equal(headers.deprecation, "true");
    assert.equal(headers.sunset, undefined);
  });

  /**
   * Better to send the deprecation signal alone than a header a client cannot act on: `Sunset:
   * Invalid Date` is worse than no Sunset header, because a conforming client has to decide what
   * to do with a date it cannot parse.
   */
  test("an unparseable stored date is dropped rather than emitted as 'Invalid Date'", () => {
    const headers = apiVersionHeaders({ decision: "deprecated", status: "sunset", sunsetAt: "not-a-date" });
    assert.equal(headers.deprecation, "true");
    assert.equal(headers.sunset, undefined);
  });

  /**
   * A `gone` version never reaches this function — the gateway refuses it with 410 before any
   * response headers are composed. Asserting the empty result pins that separation, so a future
   * change that started routing `gone` through here would fail rather than quietly emit a
   * deprecation header on a 410.
   */
  test("a gone version produces no headers here — it is refused upstream, not signalled", () => {
    assert.deepEqual(apiVersionHeaders({ decision: "gone", status: "sunset", sunsetAt: "2020-01-01T00:00:00.000Z" }), {});
  });

  /**
   * The unreadable case decides `ok`, not `gone`, and therefore emits nothing. 410 means
   * PERMANENTLY gone; emitting it because a SELECT blipped would tell every integrator the
   * endpoint had been withdrawn.
   */
  test("an unreadable registry emits nothing rather than a false permanence claim", () => {
    assert.deepEqual(apiVersionHeaders({ decision: "ok", status: "unreadable", sunsetAt: null }), {});
  });
});
