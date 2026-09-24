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
