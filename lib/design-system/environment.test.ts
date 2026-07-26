import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { isNonProductionEnvironment } from "./environment.ts";

describe("isNonProductionEnvironment", () => {
  test("CARGOGRID_ENV=production is production, regardless of NODE_ENV", () => {
    assert.equal(isNonProductionEnvironment({ CARGOGRID_ENV: "production", NODE_ENV: "development" }), false);
  });

  test("CARGOGRID_ENV=local/development/testing/staging/uat/sandbox are all non-production", () => {
    for (const tier of ["local", "development", "testing", "staging", "uat", "sandbox"]) {
      assert.equal(isNonProductionEnvironment({ CARGOGRID_ENV: tier, NODE_ENV: "production" }), true, tier);
    }
  });

  test("falls back to NODE_ENV when CARGOGRID_ENV is unset", () => {
    assert.equal(isNonProductionEnvironment({ NODE_ENV: "production" }), false);
    assert.equal(isNonProductionEnvironment({ NODE_ENV: "development" }), true);
  });

  test("both unset (this sandbox's real condition) is treated as non-production", () => {
    assert.equal(isNonProductionEnvironment({}), true);
  });
});
