import { ElementRegistry } from "./element-registry";
import { PowderEngine } from "./powder-engine";
import { ParticleEngine } from "./particle-engine";

let registry: ElementRegistry | null = null;
let powder: PowderEngine | null = null;
let particle: ParticleEngine | null = null;

export function getRegistry(): ElementRegistry {
  if (!registry) registry = new ElementRegistry();
  return registry;
}

export function getPowderEngine(): PowderEngine {
  if (!powder) powder = new PowderEngine(220, 150, getRegistry());
  return powder;
}

export function getParticleEngine(): ParticleEngine {
  if (!particle) particle = new ParticleEngine(800, 600);
  return particle;
}
