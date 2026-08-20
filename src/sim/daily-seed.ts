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

export function applyDailyPowder(engine: PowderEngine) {
  const h = dailyHash();
  const recipe = POWDER_RECIPES[h % POWDER_RECIPES.length];
  recipe?.run(engine);
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
