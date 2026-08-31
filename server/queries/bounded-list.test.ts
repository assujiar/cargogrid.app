import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { BOUNDED_LIST_LIMIT, boundedRange, toBoundedList, toBoundedListByCapReached } from "./bounded-list.ts";

describe("boundedRange", () => {
  /**
   * The `to` bound is the limit, not `limit - 1`, and that off-by-one is deliberate: PostgREST's
   * range is inclusive, so this asks for limit + 1 rows. That extra row is the entire truncation
   * detector — getting this wrong would either lose a real row or never report truncation at all.
   */
  test("asks for one row past the cap, because that extra row IS the truncation detector", () => {
    assert.deepEqual(boundedRange(200), { from: 0, to: 200 });
    assert.deepEqual(boundedRange(5), { from: 0, to: 5 });
  });

  test("defaults to the shared cap", () => {
    assert.deepEqual(boundedRange(), { from: 0, to: BOUNDED_LIST_LIMIT });
  });
});

describe("toBoundedList", () => {
  test("a short list is returned whole and reports no truncation", () => {
    const result = toBoundedList([1, 2, 3], 5);
    assert.deepEqual(result.rows, [1, 2, 3]);
    assert.equal(result.truncated, false);
    assert.equal(result.limit, 5);
  });

  /**
   * Exactly at the cap is NOT truncated. This is the boundary that decides whether a tenant with
   * exactly 200 accounts sees a "there may be more" warning that is false — a warning nobody can
   * act on teaches people to ignore warnings.
   */
  test("exactly at the cap is not truncated", () => {
    const result = toBoundedList([1, 2, 3, 4, 5], 5);
    assert.deepEqual(result.rows, [1, 2, 3, 4, 5]);
    assert.equal(result.truncated, false);
  });

  test("one row past the cap is truncated, and the extra row is dropped rather than shown", () => {
    const result = toBoundedList([1, 2, 3, 4, 5, 6], 5);
    assert.deepEqual(result.rows, [1, 2, 3, 4, 5]);
    assert.equal(result.truncated, true);
  });

  test("an empty list is not truncated", () => {
    const result = toBoundedList([], 5);
    assert.deepEqual(result.rows, []);
    assert.equal(result.truncated, false);
  });

  /**
   * The cap matches the one the RPC layer already uses for its own transactional lists. Pinned so
   * a future change has to be deliberate about diverging: two different caps in one product is a
   * difference a reader has to learn for no benefit.
   */
  test("the shared cap is 200, the same number the RPC list endpoints already use", () => {
    assert.equal(BOUNDED_LIST_LIMIT, 200);
  });
});

describe("toBoundedListByCapReached", () => {
  /**
   * The distinction this variant exists for. `toBoundedList` detects truncation by fetching one
   * row past the cap and discarding it — free for a plain select, and WRONG for
   * `app.list_files_for_tenant`, which writes an access-log entry per row it returns. The
   * discarded row would leave a log entry claiming somebody viewed a file they were never shown,
   * and an audit trail that records views which did not happen is worse than one that is merely
   * incomplete.
   */
  test("reaching the cap is treated as truncated, without needing an extra fetched row", () => {
    const result = toBoundedListByCapReached([1, 2, 3, 4, 5], 5);
    assert.deepEqual(result.rows, [1, 2, 3, 4, 5]);
    assert.equal(result.truncated, true);
  });

  test("below the cap is not truncated", () => {
    assert.equal(toBoundedListByCapReached([1, 2, 3], 5).truncated, false);
    assert.equal(toBoundedListByCapReached([], 5).truncated, false);
  });

  /**
   * It keeps every row it was given rather than slicing. Slicing here would discard a row the
   * caller has ALREADY been logged as having viewed — compounding the same dishonesty from the
   * other direction.
   */
  test("never discards a row, because a discarded row here has already been logged as viewed", () => {
    const result = toBoundedListByCapReached([1, 2, 3, 4, 5, 6], 5);
    assert.deepEqual(result.rows, [1, 2, 3, 4, 5, 6]);
  });
});
