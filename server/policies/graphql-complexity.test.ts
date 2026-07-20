import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  computeQueryDepth,
  computeQueryComplexity,
  checkQueryDepth,
  checkQueryComplexity,
  QueryTooDeepError,
  QueryTooComplexError,
  MAX_QUERY_DEPTH,
  MAX_LIST_ITEM_COUNT,
  LIST_FIELD_BASE_COST,
  LIST_FIELD_PER_ITEM_COST,
  type QueryField,
} from "./graphql-complexity.ts";

function buildChain(depth: number): QueryField {
  let node: QueryField = { name: `f${depth - 1}` };
  for (let i = depth - 2; i >= 0; i--) {
    node = { name: `f${i}`, children: [node] };
  }
  return node;
}

describe("computeQueryDepth", () => {
  test("a single scalar field has depth 1", () => {
    assert.equal(computeQueryDepth({ name: "id" }), 1);
  });

  test("an object field with one scalar child has depth 2", () => {
    assert.equal(computeQueryDepth({ name: "tenant", children: [{ name: "id" }] }), 2);
  });

  test("depth is the deepest branch, not the shallowest", () => {
    const field: QueryField = {
      name: "root",
      children: [{ name: "shallow" }, { name: "deep", children: [{ name: "deeper", children: [{ name: "deepest" }] }] }],
    };
    assert.equal(computeQueryDepth(field), 4);
  });
});

describe("checkQueryDepth", () => {
  test("passes at exactly MAX_QUERY_DEPTH", () => {
    assert.doesNotThrow(() => checkQueryDepth([buildChain(MAX_QUERY_DEPTH)]));
  });

  test("throws QueryTooDeepError one level past MAX_QUERY_DEPTH", () => {
    assert.throws(() => checkQueryDepth([buildChain(MAX_QUERY_DEPTH + 1)]), QueryTooDeepError);
  });
});

describe("computeQueryComplexity", () => {
  test("a bare scalar field costs 1 unit", () => {
    assert.equal(computeQueryComplexity([{ name: "id" }]), 1);
  });

  test("an object field with children costs 2 plus its children's cost", () => {
    const complexity = computeQueryComplexity([{ name: "tenant", children: [{ name: "id" }, { name: "name" }] }]);
    assert.equal(complexity, 2 + 1 + 1);
  });

  test("a list field's children cost is multiplied by the requested item count", () => {
    const field: QueryField = { name: "shipments", isList: true, requestedItemCount: 20, children: [{ name: "id" }, { name: "status" }, { name: "reference" }] };
    const expected = LIST_FIELD_BASE_COST + LIST_FIELD_PER_ITEM_COST * 20 + 3 * 20;
    assert.equal(computeQueryComplexity([field]), expected);
  });

  test("requestedItemCount is capped at MAX_LIST_ITEM_COUNT regardless of what is claimed", () => {
    const atCap: QueryField = { name: "shipments", isList: true, requestedItemCount: MAX_LIST_ITEM_COUNT };
    const wayOverCap: QueryField = { name: "shipments", isList: true, requestedItemCount: 999999 };
    assert.equal(computeQueryComplexity([atCap]), computeQueryComplexity([wayOverCap]));
  });
});

describe("checkQueryComplexity", () => {
  test("passes a small paginated list well under the budget", () => {
    const field: QueryField = { name: "shipments", isList: true, requestedItemCount: 20, children: [{ name: "id" }, { name: "status" }, { name: "reference" }] };
    assert.doesNotThrow(() => checkQueryComplexity([field]));
  });

  test("throws QueryTooComplexError for a nested-list-inside-list at the item-count cap", () => {
    const inner: QueryField = { name: "milestones", isList: true, requestedItemCount: MAX_LIST_ITEM_COUNT };
    const outer: QueryField = { name: "shipments", isList: true, requestedItemCount: MAX_LIST_ITEM_COUNT, children: [inner] };
    assert.throws(() => checkQueryComplexity([outer]), QueryTooComplexError);
  });

  test("returns the computed complexity when within budget", () => {
    const complexity = checkQueryComplexity([{ name: "id" }]);
    assert.equal(complexity, 1);
  });
});
