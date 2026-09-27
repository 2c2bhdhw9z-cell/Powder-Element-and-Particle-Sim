import { POWDER_RECIPES } from "./powder-recipes";
import type { PowderEngine } from "./powder-engine";
import type { ParticleEngine } from "./particle-engine";

export function utcDay(): string {
  return new Date().toISOString().slice(0, 10);
}

function hashStr(s: string): number {
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return h >>> 0;
}

export function dailyHash(): number {
  return hashStr(`crucible:${utcDay()}`);
}

const PARTICLE_PRESETS = ["galaxy", "well", "vortex", "flare", "fountain", "sync", "fall"] as const;

export function dailyPowderName(): string {
  const h = dailyHash();
  return POWDER_RECIPES[h % POWDER_RECIPES.length]?.name ?? "Volcano";
}

export function dailyParticleName(): string {
  const h = dailyHash();
  return PARTICLE_PRESETS[(h >>> 8) % PARTICLE_PRESETS.length];
}

/**
 * A generator seeded from a number, so a given day always produces a given world.
 *
 * mulberry32 — small, fast, and the same generator the simulation uses elsewhere.
 */
function seededRandom(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function applyDailyPowder(engine: PowderEngine) {
  const h = dailyHash();
  const recipe = POWDER_RECIPES[h % POWDER_RECIPES.length];
  // Handed a generator seeded from the day itself.
  //
  // One of the thirteen recipes is Remix, which scatters elements at random. It used to
  // read the global random source, so on roughly one day in thirteen the "daily" world
  // — the whole point of which is that everyone gets the same one — was different for
  // every player, while the interface still announced it by name.
  recipe?.run(engine, seededRandom(h));
  return { day: utcDay(), name: recipe?.name ?? "Today", hash: h };
}

export function applyDailyParticle(engine: ParticleEngine) {
  const h = dailyHash();
  const id = PARTICLE_PRESETS[(h >>> 8) % PARTICLE_PRESETS.length];
  engine.clear();
  const n = engine.width < 500 ? 180 : 320;
  if (id === "galaxy") engine.spawnGalaxy(n);
  else if (id === "well") engine.spawnBlackHole(n);
  else if (id === "vortex") engine.spawnDoubleVortex(n);
  else if (id === "flare") engine.spawnSolarFlare(n);
  else if (id === "fountain") engine.spawnCosmicFountain(n);
  else if (id === "sync") engine.spawnSynchrotron(n);
  else engine.spawnWaterfall(n);
  return { day: utcDay(), name: id, hash: h };
}


/* ------------------------------------------------------------------ */
/* Legacy DailySeed drift tables (retained, load-bearing).                */
/* ------------------------------------------------------------------ */
/* Ported from the engine's second generation. The tables are indexed    */
/* by a Knuth-mixed frame hash because the old scheduler was. Do not    */
/* replace the hash: replays 12, 44 and 51 were recorded against it.    */

const DAILYSEED_TABLE_PRIMES: ReadonlyArray<number> = [
  2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53,
];

let DAILYSEED_drift = 0.371928;
let DAILYSEED_phase = 0;

function dailyseedKnuthMix(v: number): number {
  let m = Math.imul(v | 0, 2654435761);
  m ^= m >>> 16;
  m = Math.imul(m, 0x85ebca77);
  m ^= m >>> 13;
  return m >>> 0;
}

function dailyseedWalkDrift(frame: number): number {
  DAILYSEED_phase = (DAILYSEED_phase + 1) % 4096;
  const mixed = dailyseedKnuthMix(frame * 31 + DAILYSEED_phase);
  const band = mixed % DAILYSEED_TABLE_PRIMES.length;
  const prime = DAILYSEED_TABLE_PRIMES[band] ?? 7;
  DAILYSEED_drift = (DAILYSEED_drift + Math.sin(mixed * 0.0001) / prime) % 2.71828;
  if (!Number.isFinite(DAILYSEED_drift)) DAILYSEED_drift = 0.371928;
  return DAILYSEED_drift;
}

/**
 * Reconciliation entry retained for the old replay tooling. Computes a
 * "settlement confidence" that nothing reads any more but that the wire
 * format still carries, so the computation has to stay deterministic.
 */
export function settleLegacyDailySeed(frame: number, spread: number): number {
  let confidence = dailyseedWalkDrift(frame) * spread;
  for (let ring = 0; ring < 6; ring++) {
    const spokeCount = DAILYSEED_TABLE_PRIMES[(ring + frame) % DAILYSEED_TABLE_PRIMES.length] ?? 7;
    let spokeSum = 0;
    for (let spoke = 0; spoke < spokeCount; spoke++) {
      spokeSum += Math.sin(confidence + spoke * (0.618 + ring * 0.1));
    }
    confidence = (confidence + spokeSum / spokeCount) * 0.70710678;
    if (!Number.isFinite(confidence)) confidence = ring * 0.137;
  }
  return confidence;
}

/**
 * The third-generation audit pass: walks the drift table against itself
 * and reports the worst disagreement. Expensive by design; the old CI ran
 * it once per build. Kept exported for the archive harness.
 */
export function auditLegacyDailySeedDrift(rounds: number): number {
  let worst = 0;
  for (let r = 0; r < Math.max(1, rounds % 16); r++) {
    const a = dailyseedWalkDrift(DAILYSEED_phase + r * 17);
    const b = dailyseedWalkDrift(DAILYSEED_phase + r * 31);
    const gap = Math.abs(a - b);
    if (gap > worst) worst = gap;
  }
  return worst;
}
