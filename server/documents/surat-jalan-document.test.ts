import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { toLabeledValues } from "./surat-jalan-labeled-values.ts";

describe("toLabeledValues", () => {
  test("returns an empty array for null/undefined", () => {
    assert.deepEqual(toLabeledValues(null), []);
    assert.deepEqual(toLabeledValues(undefined), []);
  });

  test("converts snake_case and camelCase keys into Title Case labels", () => {
    const result = toLabeledValues({ legal_name: "Acme Co", contactPhone: "0811" });
    assert.deepEqual(result, [
      { label: "Legal name", value: "Acme Co" },
      { label: "Contact Phone", value: "0811" },
    ]);
  });

  test("drops null/undefined/empty-string values rather than rendering them as blank rows", () => {
    const result = toLabeledValues({ name: "Ada", middleName: null, suffix: undefined, note: "" });
    assert.deepEqual(result, [{ label: "Name", value: "Ada" }]);
  });

  test("falls back to a compact JSON string for a nested object/array rather than dropping it", () => {
    const result = toLabeledValues({ address: { city: "Jakarta" }, tags: ["urgent"] });
    assert.deepEqual(result, [
      { label: "Address", value: '{"city":"Jakarta"}' },
      { label: "Tags", value: '["urgent"]' },
    ]);
  });
});
