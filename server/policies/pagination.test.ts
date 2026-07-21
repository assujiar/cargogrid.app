import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { encodeCursor, decodeCursor, buildPageInfo, InvalidCursorError } from "./pagination.ts";

describe("encodeCursor / decodeCursor", () => {
  test("round-trips a payload", () => {
    const payload = { sortValue: "2026-07-19T00:00:00.000Z", id: "123e4567-e89b-12d3-a456-426614174000" };
    const cursor = encodeCursor(payload);
    assert.deepEqual(decodeCursor(cursor), payload);
  });

  test("produces a URL-safe, opaque string", () => {
    const cursor = encodeCursor({ sortValue: "x", id: "y" });
    assert.equal(/^[A-Za-z0-9_-]+$/.test(cursor), true);
  });

  test("rejects a cursor that is not valid base64url", () => {
    assert.throws(() => decodeCursor("not base64!! at all $$"), InvalidCursorError);
  });

  test("rejects a cursor that decodes to non-JSON", () => {
    const garbage = Buffer.from("not json", "utf8").toString("base64url");
    assert.throws(() => decodeCursor(garbage), InvalidCursorError);
  });

  test("rejects a cursor missing sortValue/id", () => {
    const malformed = Buffer.from(JSON.stringify({ foo: "bar" }), "utf8").toString("base64url");
    assert.throws(() => decodeCursor(malformed), InvalidCursorError);
  });
});

describe("buildPageInfo", () => {
  test("encodes non-null cursor payloads and passes through null ones", () => {
    const pageInfo = buildPageInfo({
      hasNextPage: true,
      hasPreviousPage: false,
      nextCursorPayload: { sortValue: "b", id: "2" },
      previousCursorPayload: null,
    });
    assert.equal(pageInfo.hasNextPage, true);
    assert.equal(pageInfo.previousCursor, null);
    assert.deepEqual(decodeCursor(pageInfo.nextCursor!), { sortValue: "b", id: "2" });
  });
});
