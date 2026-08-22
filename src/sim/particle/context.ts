import type { ParticleObject } from "../types";
import type { Swarm } from "../swarm";

/**
 * Structural slice of `ParticleEngine` that the physics/render modules
 * operate on. The modules never import the engine class, which keeps them
 * independently testable and free of circular imports.
 */
export interface ParticleCtx {
  particles: ParticleObject[];
  springs: { a: number; b: number; rest: number; k: number }[];
  swarm: Swarm;

  width: number;
  height: number;

  gravityX: number;
  gravityY: number;
  damping: number;
  elasticity: number;
  electrostaticFactor: number;
  vortexForce: number;
  maxSpeed: number;
  boundaryMode: "bounce" | "wrap" | "void";
  mouseMode:
    | "attract"
    | "repel"
    | "vortex"
    | "emitter"
    | "painter"
    | "gravity_well"
    | "freeze"
    | "hawk"
    | "hyper_drive";
  mouseRadius: number;
  mouseForceMultiplier: number;
  lastMouseX: number;
  lastMouseY: number;
  lastMouseActive: boolean;
  colorMode: "element" | "velocity" | "charge" | "rainbow" | "density" | "lifespan";
  particleSize: number;
  maxParticles: number;
  showTrails: boolean;
  decaySpeed: number;
  collisionsEnabled: boolean;
  fluidEnabled: boolean;
  flockEnabled: boolean;
  nbodyEnabled: boolean;

  // Render scratch buffers
  imgData: ImageData | null;
  buf32: Uint32Array | null;

  // Lifecycle hooks
  onAfterStep: (() => void) | null;

  // Plumbing the modules rely on
  addParticle(particle: Partial<ParticleObject>): void;
  pushUndo(): void;
  clear(): void;
  parseColorToUint32(colorStr: string): number;
}
