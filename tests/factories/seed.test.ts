import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { createSeededRng, seededInt, seededPick, seededId } from "./seed.ts";

describe("createSeededRng", () => {
  test("the same seed produces the identical output sequence", () => {
    const a = createSeededRng("tenant-a");
    const b = createSeededRng("tenant-a");
    const sequenceA = [a(), a(), a(), a()];
    const sequenceB = [b(), b(), b(), b()];
    assert.deepEqual(sequenceA, sequenceB);
  });

  test("different seeds produce different sequences", () => {
    const a = createSeededRng("tenant-a");
    const b = createSeededRng("tenant-b");
    assert.notEqual(a(), b());
  });

  test("every draw is within [0, 1)", () => {
    const rng = createSeededRng("range-check");
    for (let i = 0; i < 200; i++) {
      const value = rng();
      assert.ok(value >= 0 && value < 1, `draw ${i} out of range: ${value}`);
    }
  });

  test("an empty-string seed is still deterministic (regression guard)", () => {
    const a = createSeededRng("");
    const b = createSeededRng("");
    assert.equal(a(), b());
  });
});

describe("seededInt", () => {
  test("stays within [min, max] inclusive across many draws", () => {
    const rng = createSeededRng("int-range");
    for (let i = 0; i < 500; i++) {
      const value = seededInt(rng, 3, 7);
      assert.ok(value >= 3 && value <= 7, `value out of range: ${value}`);
    }
  });

  test("a single-valued range always returns that value", () => {
    const rng = createSeededRng("single-value");
    assert.equal(seededInt(rng, 5, 5), 5);
  });

  test("the same seed produces the identical integer sequence", () => {
    const first = seededInt(createSeededRng("repeat"), 0, 1000);
    const second = seededInt(createSeededRng("repeat"), 0, 1000);
    assert.equal(first, second);
  });
});

describe("seededPick", () => {
  test("only returns values from the supplied array", () => {
    const rng = createSeededRng("pick-check");
    const options = ["alpha", "beta", "gamma"] as const;
    for (let i = 0; i < 100; i++) {
      assert.ok(options.includes(seededPick(rng, options)));
    }
  });

  test("rejects an empty array rather than returning undefined", () => {
    assert.throws(() => seededPick(createSeededRng("empty"), []), /non-empty/);
  });

  test("the same seed picks the identical element", () => {
    const first = seededPick(createSeededRng("pick-repeat"), ["a", "b", "c", "d"]);
    const second = seededPick(createSeededRng("pick-repeat"), ["a", "b", "c", "d"]);
    assert.equal(first, second);
  });
});

describe("seededId", () => {
  test("produces a lowercase hex string of the requested byte length", () => {
    const rng = createSeededRng("id-check");
    const id = seededId(rng, 8);
    assert.equal(id.length, 16);
    assert.match(id, /^[0-9a-f]+$/);
  });

  test("the same seed produces the identical id", () => {
    assert.equal(seededId(createSeededRng("id-repeat")), seededId(createSeededRng("id-repeat")));
  });

  test("different seeds produce different ids", () => {
    assert.notEqual(seededId(createSeededRng("id-a")), seededId(createSeededRng("id-b")));
  });
});
