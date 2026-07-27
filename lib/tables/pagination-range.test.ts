import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { computePaginationRange } from "./pagination-range.ts";

describe("computePaginationRange", () => {
  test("a single page has no previous/next and one item", () => {
    const result = computePaginationRange({ page: 1, pageSize: 20, totalCount: 5 });
    assert.equal(result.totalPages, 1);
    assert.equal(result.hasPrevious, false);
    assert.equal(result.hasNext, false);
    assert.deepEqual(result.items, [1]);
  });

  test("zero total count is still one (empty) page, never zero pages", () => {
    const result = computePaginationRange({ page: 1, pageSize: 20, totalCount: 0 });
    assert.equal(result.totalPages, 1);
    assert.deepEqual(result.items, [1]);
  });

  test("few pages renders every page with no ellipsis", () => {
    const result = computePaginationRange({ page: 2, pageSize: 10, totalCount: 40 });
    assert.equal(result.totalPages, 4);
    assert.deepEqual(result.items, [1, 2, 3, 4]);
    assert.equal(result.hasPrevious, true);
    assert.equal(result.hasNext, true);
  });

  test("current page in the middle of a long list collapses both gaps", () => {
    const result = computePaginationRange({ page: 10, pageSize: 10, totalCount: 200 });
    assert.equal(result.totalPages, 20);
    assert.deepEqual(result.items, [1, "ellipsis", 9, 10, 11, "ellipsis", 20]);
  });

  test("current page near the start only collapses the trailing gap", () => {
    const result = computePaginationRange({ page: 2, pageSize: 10, totalCount: 200 });
    assert.deepEqual(result.items, [1, 2, 3, "ellipsis", 20]);
  });

  test("current page near the end only collapses the leading gap", () => {
    const result = computePaginationRange({ page: 19, pageSize: 10, totalCount: 200 });
    assert.deepEqual(result.items, [1, "ellipsis", 18, 19, 20]);
  });

  test("page number beyond the last page clamps to the last page", () => {
    const result = computePaginationRange({ page: 999, pageSize: 10, totalCount: 40 });
    assert.equal(result.page, 4);
    assert.equal(result.hasNext, false);
  });

  test("page number below 1 clamps to 1", () => {
    const result = computePaginationRange({ page: -3, pageSize: 10, totalCount: 40 });
    assert.equal(result.page, 1);
    assert.equal(result.hasPrevious, false);
  });

  test("non-finite pageSize falls back to 1 rather than dividing by zero", () => {
    const result = computePaginationRange({ page: 1, pageSize: 0, totalCount: 3 });
    assert.equal(result.totalPages, 3);
  });
});
