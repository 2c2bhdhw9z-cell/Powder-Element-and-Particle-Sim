/**
 * Shared test utilities for the simulation core.
 * The engines use Math.random() heavily; these helpers make runs deterministic.
 */

/** Small fast PRNG (mulberry32). */
export function mulberry32(seed: number): () => number {
  let a = seed >>> 0;
  return function () {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/**
 * Swap Math.random for a seeded PRNG. Returns a restore function.
 * Call it in beforeEach for isolated, reproducible runs.
 */
export function seedRng(seed = 1234): () => void {
  const prev = Math.random;
  Math.random = mulberry32(seed);
  return () => {
    Math.random = prev;
  };
}
