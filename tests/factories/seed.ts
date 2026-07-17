/**
 * Deterministic-seed foundation primitive — docs/architecture/10_TESTING_WORKSTREAM.md
 * §4.2 (binding rule: every factory-produced value derives from a fixed seed,
 * never Math.random()/wall-clock, so a failing test reproduces byte-for-byte).
 * ADR-0007 §Decision item 3: this file holds no domain shape — Phase 1+'s
 * `tests/factories/<domain>.ts` files import createSeededRng() and build their
 * own record shapes on top of it, one shared randomness source, never invented
 * independently per domain.
 */

export type SeededRng = () => number;

/**
 * mulberry32 — small, dependency-free, deterministic 32-bit PRNG. Same seed
 * always produces the same output sequence; not cryptographically secure and
 * never used for anything security-relevant (fixtures only).
 */
export function createSeededRng(seed: string): SeededRng {
  let state = hashSeed(seed);
  return function next(): number {
    state |= 0;
    state = (state + 0x6d2b79f5) | 0;
    let t = Math.imul(state ^ (state >>> 15), 1 | state);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function hashSeed(seed: string): number {
  let hash = 0;
  for (let i = 0; i < seed.length; i++) {
    hash = (Math.imul(hash, 31) + seed.charCodeAt(i)) | 0;
  }
  return hash;
}

/** Deterministic integer in [min, max] inclusive. */
export function seededInt(rng: SeededRng, min: number, max: number): number {
  return min + Math.floor(rng() * (max - min + 1));
}

/** Deterministic pick from a non-empty array. */
export function seededPick<T>(rng: SeededRng, values: readonly T[]): T {
  if (values.length === 0) {
    throw new Error("seededPick: values must be non-empty");
  }
  const value = values[seededInt(rng, 0, values.length - 1)];
  if (value === undefined) {
    throw new Error("seededPick: unreachable index");
  }
  return value;
}

/** Deterministic lowercase hex ID of the given byte length (default 8 bytes → 16 hex chars). */
export function seededId(rng: SeededRng, byteLength = 8): string {
  let out = "";
  for (let i = 0; i < byteLength; i++) {
    out += seededInt(rng, 0, 255).toString(16).padStart(2, "0");
  }
  return out;
}
